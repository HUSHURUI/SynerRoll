using SQLite
using DBInterface
using Tables

function parse_ts_label(label::String)
    parts = split(label, "#"; limit=2)
    length(parts) == 2 || error("Invalid time-series label: $(label)")

    main_part, layer_id = parts
    main_fields = split(main_part, "|")
    length(main_fields) == 3 || error("Invalid time-series label: $(label)")

    return Dict(
        "source_id" => main_fields[1],
        "var_name" => main_fields[2],
        "remark" => main_fields[3],
        "layer_id" => layer_id,
    )
end

struct TimeSeries
    timestamps::Vector{String}
    values::Vector{Float64}

    function TimeSeries(timestamps::Vector{String}, values::Vector{<:Real})
        length(timestamps) == length(values) || error("TimeSeries timestamps and values must have the same length.")
        return new(timestamps, convert(Vector{Float64}, values))
    end

    function TimeSeries()
        return new(String[], Float64[])
    end
end

function merge_timeseries(ts1::TimeSeries, ts2::TimeSeries)
    merged = Dict{String,Float64}()

    for (timestamp, value) in zip(ts1.timestamps, ts1.values)
        merged[timestamp] = value
    end

    for (timestamp, value) in zip(ts2.timestamps, ts2.values)
        merged[timestamp] = value
    end

    sorted_timestamps = sort(collect(keys(merged)); lt=time_label_less_than)
    sorted_values = [merged[timestamp] for timestamp in sorted_timestamps]
    return TimeSeries(sorted_timestamps, sorted_values)
end

function get_value(ts::TimeSeries, time::String)
    exact_index = findfirst(==(time), ts.timestamps)
    if exact_index !== nothing
        return ts.values[exact_index]
    end

    target_minutes = time_label_to_minutes(time)
    closest_index = nothing
    closest_minutes = -1

    for (index, timestamp) in enumerate(ts.timestamps)
        current_minutes = time_label_to_minutes(timestamp)
        if current_minutes < target_minutes && current_minutes > closest_minutes
            closest_minutes = current_minutes
            closest_index = index
        end
    end

    closest_index === nothing && error("Time $(time) does not exist in the series and no earlier fallback is available.")
    return ts.values[closest_index]
end

function get_values(ts::TimeSeries, times::Vector{String})
    return [get_value(ts, time) for time in times]
end

mutable struct SQLiteTimeSeriesStore
    db::SQLite.DB
    write_lock::ReentrantLock
end

"""
    SQLiteTimeSeriesStore(db_path::String)

打开（或创建）指定路径的 SQLite 时序库文件。
注意：`db_path` 必传；老版本的无参调用已废弃。
"""
function SQLiteTimeSeriesStore(db_path::String)
    mkpath(dirname(db_path))
    db = SQLite.DB(db_path)

    # 开启 WAL 模式，支持并发读 + 单写者（计算任务方案要求第三方 ingest 与任务自身写不冲突）
    # 注意：这里不能用 _exec，因为 _exec 在 store 创建之前还不可用
    # 直接用 DBInterface.prepare + close! 确保 stmt 被 finalize
    function _safe_exec(d, sql)
        s = DBInterface.prepare(d, sql)
        try
            DBInterface.execute(s)
        finally
            DBInterface.close!(s)
        end
    end

    try
        _safe_exec(db, "PRAGMA journal_mode=WAL")
        _safe_exec(db, "PRAGMA busy_timeout=5000")
    catch
        # PRAGMA 失败不致命（如只读场景），但 WAL 还是要尽量开
    end

    _safe_exec(db, """
    CREATE TABLE IF NOT EXISTS time_series_meta (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id   TEXT NOT NULL,
        var_name    TEXT NOT NULL,
        remark      TEXT NOT NULL,
        layer_id    TEXT NOT NULL,
        created_at  TEXT DEFAULT (datetime('now')),
        updated_at  TEXT DEFAULT (datetime('now')),
        UNIQUE(source_id, var_name, remark, layer_id)
    )
""")

    _safe_exec(db, """
    CREATE TABLE IF NOT EXISTS time_series_data (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id   INTEGER NOT NULL REFERENCES time_series_meta(id) ON DELETE CASCADE,
        ts          TEXT NOT NULL,
        value       REAL NOT NULL
    )
""")

    _safe_exec(db, "CREATE INDEX IF NOT EXISTS idx_data_series ON time_series_data(series_id)")

    # ── 回溯模式：按求解步记录完整快照 ──────────────────────────────
    _safe_exec(db, """
    CREATE TABLE IF NOT EXISTS solve_trace_meta (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id      TEXT NOT NULL,
        step         INTEGER NOT NULL,
        layer_id     TEXT NOT NULL,
        sim_time     TEXT NOT NULL,
        created_at   TEXT DEFAULT (datetime('now')),
        UNIQUE(task_id, step)
    )
""")

    _safe_exec(db, """
    CREATE TABLE IF NOT EXISTS solve_trace_data (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        trace_id     INTEGER NOT NULL REFERENCES solve_trace_meta(id) ON DELETE CASCADE,
        data_key     TEXT NOT NULL,
        ts           TEXT NOT NULL,
        value        REAL NOT NULL
    )
""")

    _safe_exec(db, "CREATE INDEX IF NOT EXISTS idx_trace_data ON solve_trace_data(trace_id)")
    _safe_exec(db, "CREATE INDEX IF NOT EXISTS idx_trace_meta_task ON solve_trace_meta(task_id, step)")

    return SQLiteTimeSeriesStore(db, ReentrantLock())
end

"""
    STORE_REGISTRY

按 db_path 缓存已打开的 SQLiteTimeSeriesStore，避免每个请求都重新打开/建表。
key = 完整 db_path 字符串（绝对路径或相对 backend/ 的路径都按字符串存）。
"""
const STORE_REGISTRY = Dict{String,SQLiteTimeSeriesStore}()
const STORE_REGISTRY_LOCK = ReentrantLock()

"""
    get_store(db_path::String) -> SQLiteTimeSeriesStore

按 db_path 取/建 TS 库句柄。同一个 db_path 多次调用复用同一个 handle。
"""
function get_store(db_path::String)
    lock(STORE_REGISTRY_LOCK) do
        return get!(STORE_REGISTRY, db_path) do
            SQLiteTimeSeriesStore(db_path)
        end
    end
end

"""
    close_store(db_path::String)

从 registry 移除 db_path 对应的句柄（项目级 boundary DB 删除时调用，释放 handle）。
下次 get_store 会重新打开。
"""
function close_store(db_path::String)
    store = lock(STORE_REGISTRY_LOCK) do
        pop!(STORE_REGISTRY, db_path, nothing)
    end
    if store !== nothing
        try
            DBInterface.close!(store.db)
        catch
            # 已关闭或不可关闭时忽略
        end
    end
    return nothing
end

function _key_to_meta_params(data_key::String)
    # key format: "source_id|var_name|remark#layer_id"
    # 对边界业务：source_id = projects.json 中的 BoundaryID
    # 对组件结果：source_id = projects.json 中的 nodeID
    main_part, layer_id = split(data_key, "#"; limit=2)
    length(main_part) == 0 && error("Invalid key: $data_key")
    main_fields = split(main_part, "|")
    length(main_fields) == 3 || error("Invalid key: $data_key, got main_fields=$(main_fields)")
    source_id, var_name, remark = main_fields[1], main_fields[2], main_fields[3]
    return source_id, var_name, remark, layer_id
end

"""
    _query(db, sql, params) -> columntable result

查询辅助函数。prepare → execute → columntable → close!(stmt)。
使用 DBInterface.close!(stmt::Stmt) = _close_stmt! = sqlite3_finalize，
确保 stmt 被彻底释放（而非仅 sqlite3_reset）。
"""
function _query(db::SQLite.DB, sql::String, params=())
    stmt = DBInterface.prepare(db, sql)
    try
        result = DBInterface.execute(stmt, params) |> columntable
        return result
    finally
        DBInterface.close!(stmt)   # → sqlite3_finalize，彻底销毁 stmt
    end
end

"""
    _exec(db, sql, params)

DML/DDL 辅助函数。prepare → execute → close!(stmt)。
使用 DBInterface.close!(stmt::Stmt) = _close_stmt! = sqlite3_finalize，
确保 stmt 在执行完毕后被彻底释放，不留活跃 stmt 给事务 COMMIT。

注意：不要用 SQLite.execute(db, sql, params)，它创建的临时 Stmt
在某些 Julia/SQLite.jl 版本中 finalize 时机不可靠。
"""
function _exec(db::SQLite.DB, sql::String, params=())
    stmt = DBInterface.prepare(db, sql)
    try
        DBInterface.execute(stmt, params)
    finally
        DBInterface.close!(stmt)   # → sqlite3_finalize
    end
    return nothing
end

function get_ts(db_path::String, data_key::String)
    store = get_store(db_path)
    source_id, var_name, remark, layer_id = _key_to_meta_params(data_key)

    lock(store.write_lock) do
        meta_rows = _query(store.db,
            "SELECT id FROM time_series_meta WHERE source_id=? AND var_name=? AND remark=? AND layer_id=?",
            [source_id, var_name, remark, layer_id])

        isempty(meta_rows[1]) && return nothing
        series_id = meta_rows[1][1]

        data_rows = _query(store.db,
            "SELECT ts, value FROM time_series_data WHERE series_id=?",
            [series_id])

        isempty(data_rows[1]) && return TimeSeries()
        timestamps = Vector{String}(data_rows[1])
        values = Vector{Float64}(data_rows[2])
        perm = sortperm(timestamps; lt=time_label_less_than)
        return TimeSeries(timestamps[perm], values[perm])
    end
end

"""
    _write_ts(store, data_key, ts)

内部写入原语，调用方必须已持有 store.write_lock。
在一个事务内完成 meta upsert + data DELETE + 批量 INSERT。
"""
function _write_ts(store::SQLiteTimeSeriesStore, data_key::String, ts::TimeSeries)
    source_id, var_name, remark, layer_id = _key_to_meta_params(data_key)

    # 使用手动 BEGIN/COMMIT/ROLLBACK，不走 DBInterface.transaction（避免 savepoint 问题）
    _exec(store.db, "BEGIN IMMEDIATE")
    try
        # 插入或更新 meta
        _exec(store.db,
            "INSERT INTO time_series_meta (source_id, var_name, remark, layer_id, updated_at)
             VALUES (?, ?, ?, ?, datetime('now'))
             ON CONFLICT(source_id, var_name, remark, layer_id)
             DO UPDATE SET updated_at = datetime('now')",
            [source_id, var_name, remark, layer_id])

        # 查询 series_id
        meta_rows = _query(store.db,
            "SELECT id FROM time_series_meta WHERE source_id=? AND var_name=? AND remark=? AND layer_id=?",
            [source_id, var_name, remark, layer_id])
        series_id = meta_rows[1][1]

        # 删除旧数据
        _exec(store.db, "DELETE FROM time_series_data WHERE series_id=?", [series_id])

        # 按时间数值排序后用 prepared statement 批量插入
        perm = sortperm(ts.timestamps; lt=time_label_less_than)
        sorted_ts = ts.timestamps[perm]
        sorted_vals = ts.values[perm]

        insert_stmt = DBInterface.prepare(store.db,
            "INSERT INTO time_series_data (series_id, ts, value) VALUES (?, ?, ?)")
        try
            for (t, v) in zip(sorted_ts, sorted_vals)
                DBInterface.execute(insert_stmt, [series_id, t, v])
            end
        finally
            DBInterface.close!(insert_stmt)
        end

        _exec(store.db, "COMMIT")
    catch e
        try; _exec(store.db, "ROLLBACK"); catch; end
        rethrow(e)
    end
end

function set_ts(db_path::String, data_key::String, ts::TimeSeries)
    store = get_store(db_path)
    lock(store.write_lock) do
        _write_ts(store, data_key, ts)
    end
    return nothing
end

"""
    set_ts_merge(db_path, data_key, new_ts)

合并写入：读取已有数据，与 new_ts 按时间戳合并（new_ts 覆盖重叠时刻），
保留旧数据中不重叠的时刻，然后整体写回。
"""
function set_ts_merge(db_path::String, data_key::String, new_ts::TimeSeries)
    store = get_store(db_path)
    lock(store.write_lock) do
        existing = get_ts(db_path, data_key)
        if existing !== nothing && !isempty(existing.timestamps)
            merged = merge_timeseries(existing, new_ts)  # ts2 wins on overlap
            _write_ts(store, data_key, merged)
        else
            _write_ts(store, data_key, new_ts)
        end
    end
    return nothing
end

function delete_ts(db_path::String, data_key::String)
    store = get_store(db_path)
    source_id, var_name, remark, layer_id = _key_to_meta_params(data_key)

    lock(store.write_lock) do
        meta_rows = _query(store.db,
            "SELECT id FROM time_series_meta WHERE source_id=? AND var_name=? AND remark=? AND layer_id=?",
            [source_id, var_name, remark, layer_id])
        isempty(meta_rows[1]) && return nothing
        series_id = meta_rows[1][1]

        _exec(store.db, "BEGIN IMMEDIATE")
        try
            _exec(store.db, "DELETE FROM time_series_data WHERE series_id=?", [series_id])
            _exec(store.db, "DELETE FROM time_series_meta WHERE id=?", [series_id])
            _exec(store.db, "COMMIT")
        catch e
            try; _exec(store.db, "ROLLBACK"); catch; end
            rethrow(e)
        end
    end
    return nothing
end

function list_all_keys(db_path::String)
    store = get_store(db_path)
    lock(store.write_lock) do
        rows = _query(store.db,
            "SELECT source_id, var_name, remark, layer_id FROM time_series_meta")
        isempty(rows[1]) && return String[]
        return ["$(rows[1][i])|$(rows[2][i])|$(rows[3][i])#$(rows[4][i])" for i in 1:length(rows[1])]
    end
end

function query_ts(db_path::String;
    source_id::Union{String,Nothing}=nothing,
    var_name::Union{String,Nothing}=nothing,
    remark::Union{String,Nothing}=nothing,
    layer_id::Union{String,Nothing}=nothing,
)

    store = get_store(db_path)
    lock(store.write_lock) do
        sql = "SELECT id, source_id, var_name, remark, layer_id FROM time_series_meta WHERE 1=1"
        params = String[]
        if source_id !== nothing
            sql *= " AND source_id=?"
            push!(params, source_id)
        end
        if var_name !== nothing
            sql *= " AND var_name=?"
            push!(params, var_name)
        end
        if remark !== nothing
            sql *= " AND remark=?"
            push!(params, remark)
        end
        if layer_id !== nothing
            sql *= " AND layer_id=?"
            push!(params, layer_id)
        end
        rows = _query(store.db, sql, params)
        if isempty(rows[1])
            @debug "query_ts: 未找到匹配的时序记录" source_id var_name remark layer_id
            return nothing, nothing
        end
        if length(rows[1]) > 1
            @error "query_ts: 匹配到多条记录（期望唯一）" source_id var_name remark layer_id count=length(rows[1])
            return nothing, nothing
        end

        series_id = rows[1][1]
        label = "$(rows[2][1])|$(rows[3][1])|$(rows[4][1])#$(rows[5][1])"

        data_rows = _query(store.db,
            "SELECT ts, value FROM time_series_data WHERE series_id=?", [series_id])
        if isempty(data_rows[1])
            return TimeSeries(), label
        end
        timestamps = Vector{String}(data_rows[1])
        values = Vector{Float64}(data_rows[2])
        perm = sortperm(timestamps; lt=time_label_less_than)
        return TimeSeries(timestamps[perm], values[perm]), label
    end
end

function clear_cache(db_path::String)
    store = get_store(db_path)
    lock(store.write_lock) do
        _exec(store.db, "BEGIN IMMEDIATE")
        try
            _exec(store.db, "DELETE FROM time_series_data")
            _exec(store.db, "DELETE FROM time_series_meta")
            _exec(store.db, "COMMIT")
        catch e
            try; _exec(store.db, "ROLLBACK"); catch; end
            rethrow(e)
        end
    end
    return nothing
end

function get_all_series_meta(db_path::String)
    store = get_store(db_path)
    lock(store.write_lock) do
        rows = _query(store.db,
            "SELECT id, source_id, var_name, remark, layer_id, created_at, updated_at FROM time_series_meta")
        if isempty(rows[1])
            return []
        end
        return [Dict(
            "id" => rows[1][i],
            "source_id" => rows[2][i],
            "var_name" => rows[3][i],
            "remark" => rows[4][i],
            "layer_id" => rows[5][i],
            "created_at" => rows[6][i],
            "updated_at" => rows[7][i]
        ) for i in 1:length(rows[1])]
    end
end

function get_series_data(db_path::String, series_id::Int)
    store = get_store(db_path)
    lock(store.write_lock) do
        rows = _query(store.db,
            "SELECT ts, value FROM time_series_data WHERE series_id=?", [series_id])
        isempty(rows[1]) && return TimeSeries()
        timestamps = Vector{String}(rows[1])
        values = Vector{Float64}(rows[2])
        perm = sortperm(timestamps; lt=time_label_less_than)
        return TimeSeries(timestamps[perm], values[perm])
    end
end

# ════════════════════════════════════════════════════════════════
# 回溯模式（Trace）函数
# ════════════════════════════════════════════════════════════════

"""
    save_solve_trace!(db_path, task_id, step, layer_id, sim_time, results)

保存一次求解步的完整快照到回溯表。
`results` 为 `Vector{Tuple{String, TimeSeries}}`，每项为 (data_key, timeseries)。
"""
function save_solve_trace!(db_path::String, task_id::String, step::Int,
    layer_id::String, sim_time::String,
    results::Vector{Tuple{String,TimeSeries}})

    store = get_store(db_path)

    lock(store.write_lock) do
        _exec(store.db, "BEGIN IMMEDIATE")
        try
            # 插入 trace_meta（step 冲突时更新）
            _exec(store.db,
                """INSERT INTO solve_trace_meta (task_id, step, layer_id, sim_time)
                   VALUES (?, ?, ?, ?)
                   ON CONFLICT(task_id, step) DO UPDATE SET layer_id=?, sim_time=?, created_at=datetime('now')""",
                [task_id, step, layer_id, sim_time, layer_id, sim_time])

            meta_rows = _query(store.db,
                "SELECT id FROM solve_trace_meta WHERE task_id=? AND step=?",
                [task_id, step])
            trace_id = meta_rows[1][1]

            # 删除旧 trace_data（step 冲突场景）
            _exec(store.db, "DELETE FROM solve_trace_data WHERE trace_id=?", [trace_id])

            # 用 prepared statement 批量插入所有数据点
            insert_stmt = DBInterface.prepare(store.db,
                "INSERT INTO solve_trace_data (trace_id, data_key, ts, value) VALUES (?, ?, ?, ?)")
            try
                for (data_key, ts) in results
                    perm = sortperm(ts.timestamps; lt=time_label_less_than)
                    for i in perm
                        DBInterface.execute(insert_stmt,
                            [trace_id, data_key, ts.timestamps[i], ts.values[i]])
                    end
                end
            finally
                DBInterface.close!(insert_stmt)
            end

            _exec(store.db, "COMMIT")
        catch e
            try; _exec(store.db, "ROLLBACK"); catch; end
            rethrow(e)
        end
    end

    return nothing
end

"""
    get_solve_trace_steps(db_path, task_id)

返回任务的所有求解步列表：`Vector{Dict}`，每项含 step, layer_id, sim_time。
"""
function get_solve_trace_steps(db_path::String, task_id::String)
    store = get_store(db_path)
    lock(store.write_lock) do
        rows = _query(store.db,
            "SELECT step, layer_id, sim_time FROM solve_trace_meta WHERE task_id=? ORDER BY step",
            [task_id])
        isempty(rows[1]) && return Dict{String,Any}[]
        return [Dict(
            "step" => rows[1][i],
            "layerId" => rows[2][i],
            "simTime" => rows[3][i],
        ) for i in 1:length(rows[1])]
    end
end

"""
    get_solve_trace_data(db_path, task_id, step)

返回指定求解步的全部数据：`Dict{String, TimeSeries}`，key 为 data_key。
"""
function get_solve_trace_data(db_path::String, task_id::String, step::Int)
    store = get_store(db_path)
    lock(store.write_lock) do
        meta_rows = _query(store.db,
            "SELECT id FROM solve_trace_meta WHERE task_id=? AND step=?",
            [task_id, step])
        isempty(meta_rows[1]) && return Dict{String,TimeSeries}()
        trace_id = meta_rows[1][1]

        data_rows = _query(store.db,
            "SELECT data_key, ts, value FROM solve_trace_data WHERE trace_id=?",
            [trace_id])
        isempty(data_rows[1]) && return Dict{String,TimeSeries}()

        # 按 data_key 分组
        grouped = Dict{String,Vector{Tuple{String,Float64}}}()
        for i in 1:length(data_rows[1])
            key = String(data_rows[1][i])
            ts_val = (String(data_rows[2][i]), Float64(data_rows[3][i]))
            if haskey(grouped, key)
                push!(grouped[key], ts_val)
            else
                grouped[key] = [ts_val]
            end
        end

        # 转为 TimeSeries
        result = Dict{String,TimeSeries}()
        for (key, pairs) in grouped
            perm = sortperm([p[1] for p in pairs]; lt=time_label_less_than)
            sorted_pairs = pairs[perm]
            result[key] = TimeSeries(
                [p[1] for p in sorted_pairs],
                [p[2] for p in sorted_pairs],
            )
        end
        return result
    end
end