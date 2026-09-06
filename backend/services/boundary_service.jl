using Random

function parse_boundary_data(
    data_array::Vector{Any},
    time_step::String,
    layer::Dict{String, Any};
    start_time::String="0:00",
    interpolate_type::String="copy",
    noise_level::Float64=0.0,
    boundary_length::Union{String,Nothing}=nothing,
)
    interpolate_type in ["copy", "linear"] || error("interpolate_type must be copy or linear")
    noise_level >= 0.0 || error("noise_level must be non-negative")

    # 使用 boundary_length（如果提供），否则使用 layer["length"]
    effective_length = boundary_length !== nothing ? boundary_length : layer["length"]
    layer_length_minutes = time_str_to_minutes(effective_length)
    layer_step_minutes = time_str_to_minutes(layer["step"])
    data_step_minutes = time_str_to_minutes(time_step)

    layer_length_minutes % (24 * 60) == 0 || error("layer length must be a multiple of 24h")
    layer_step_minutes >= 1 || error("layer step must be at least 1 minute")
    60 % layer_step_minutes == 0 || error("layer step must divide 60 minutes")
    layer_step_minutes <= 4 * 60 || error("layer step cannot exceed 4h")

    data_total_minutes = length(data_array) * data_step_minutes
    data_total_minutes >= layer_length_minutes || error("boundary data coverage is shorter than the target layer horizon")

    layer_point_count = layer_length_minutes ÷ layer_step_minutes
    offset_minutes = time_label_to_minutes(start_time)
    offset_points = offset_minutes ÷ data_step_minutes

    aligned_data = if 0 < offset_points < length(data_array)
        vcat(data_array[end - offset_points + 1:end], data_array[1:end - offset_points])
    else
        copy(data_array)
    end

    final_values = if data_step_minutes == layer_step_minutes
        values = Float64.(aligned_data[1:min(length(aligned_data), layer_point_count)])
        if length(values) < layer_point_count
            vcat(values, repeat([values[end]], layer_point_count - length(values)))
        else
            values
        end
    elseif data_step_minutes < layer_step_minutes
        sampled_values = Float64[]
        for index in 0:layer_point_count - 1
            current_minutes = index * layer_step_minutes
            raw_index = floor(Int, current_minutes / data_step_minutes) + 1
            raw_index = min(raw_index, length(aligned_data))
            push!(sampled_values, Float64(aligned_data[raw_index]))
        end
        sampled_values
    else
        interpolated_values = Float64[]
        for index in 0:layer_point_count - 1
            current_minutes = index * layer_step_minutes
            raw_index = floor(Int, current_minutes / data_step_minutes) + 1

            if raw_index >= length(aligned_data)
                value = Float64(aligned_data[end])
            else
                previous_value = Float64(aligned_data[raw_index])
                next_value = Float64(aligned_data[min(raw_index + 1, length(aligned_data))])
                previous_minutes = (raw_index - 1) * data_step_minutes
                next_minutes = raw_index * data_step_minutes
                ratio = (current_minutes - previous_minutes) / (next_minutes - previous_minutes)

                if interpolate_type == "copy"
                    value = previous_value
                else
                    value = previous_value + ratio * (next_value - previous_value)
                end
            end

            push!(interpolated_values, value)
        end
        interpolated_values[1:layer_point_count]
    end

    if noise_level > 0.0
        rng = Random.MersenneTwister()
        final_values .+= randn(rng, length(final_values)) .* noise_level
    end

    timestamps = generate_timestamps("0:00", layer["step"], effective_length)
    return TimeSeries(timestamps, abs.(final_values))
end

"""
    preprocess_boundary_data(data_array, time_step) -> Dict

预处理边界数据：截断到24h的倍数（最少24h）。
返回截断后的数据和元信息。

# Arguments
- `data_array::Vector{Any}`: 原始数据数组
- `time_step::String`: 时间步长，如 "1h", "15m", "30m"

# Returns
Dict包含：
- `values`: 截断后的数据数组
- `timestamps`: 对应的时间戳
- `pointCount`: 数据点个数
- `totalHours`: 总小时数
- `dayCount`: 天数
- `timeStep`: 时间步长
"""
function preprocess_boundary_data(
    data_array::Vector{Any},
    time_step::String,
)
    # 解析时间步长（分钟）
    data_step_minutes = time_str_to_minutes(time_step)
    data_step_minutes > 0 || error("时间步长必须大于0")

    # 计算原始数据的总时长（小时）
    raw_count = length(data_array)
    raw_total_minutes = raw_count * data_step_minutes
    raw_total_hours = raw_total_minutes / 60

    # 至少24h，截断到24h的倍数
    raw_total_hours >= 24 || error("边界数据不足24小时（当前 $(round(raw_total_hours; digits=1))h），请补充数据")

    # 计算截断后的天数和点数
    day_count = floor(Int, raw_total_hours / 24)
    truncate_point_count = day_count * 24 * 60 ÷ data_step_minutes

    # 截断数据
    truncated_values = Float64.(data_array[1:truncate_point_count])

    # 生成时间戳
    total_minutes = truncate_point_count * data_step_minutes
    timestamps = generate_timestamps("0:00", time_step, "$(total_minutes)m")

    return Dict(
        "values" => truncated_values,
        "timestamps" => timestamps,
        "pointCount" => truncate_point_count,
        "totalHours" => day_count * 24,
        "dayCount" => day_count,
        "timeStep" => time_step,
    )
end

# ───── boundary_config 表：存储 boundary 元信息 ─────

"""
    ensure_boundary_config_table!(db_path::String)

确保 boundary.db 中存在 boundary_config 表，用于存储 boundary 的长度和尺度元信息。
"""
function ensure_boundary_config_table!(db_path::String)
    store = get_store(db_path)
    lock(store.write_lock) do
        _exec(store.db, """
            CREATE TABLE IF NOT EXISTS boundary_config (
                boundary_id     TEXT PRIMARY KEY,
                boundary_length TEXT NOT NULL,
                boundary_step   TEXT NOT NULL,
                day_count       INTEGER NOT NULL,
                point_count     INTEGER NOT NULL,
                created_at      TEXT DEFAULT (datetime('now')),
                updated_at      TEXT DEFAULT (datetime('now'))
            )
        """)
    end
    return nothing
end

"""
    save_boundary_config(db_path, boundary_id, boundary_length, boundary_step, day_count, point_count)

保存 boundary 的元信息到 boundary_config 表。
"""
function save_boundary_config(
    db_path::String,
    boundary_id::String,
    boundary_length::String,
    boundary_step::String,
    day_count::Int,
    point_count::Int,
)
    ensure_boundary_config_table!(db_path)
    store = get_store(db_path)
    lock(store.write_lock) do
        _exec(store.db, """
            INSERT OR REPLACE INTO boundary_config
                (boundary_id, boundary_length, boundary_step, day_count, point_count, updated_at)
            VALUES (?, ?, ?, ?, ?, datetime('now'))
        """, (boundary_id, boundary_length, boundary_step, day_count, point_count))
    end
    return nothing
end

"""
    get_boundary_config(db_path, boundary_id) -> Dict 或 nothing

从 boundary_config 表获取 boundary 的元信息。
"""
function get_boundary_config(db_path::String, boundary_id::String)
    ensure_boundary_config_table!(db_path)
    store = get_store(db_path)
    return lock(store.write_lock) do
        rows = _query(store.db, """
            SELECT boundary_length, boundary_step, day_count, point_count
            FROM boundary_config WHERE boundary_id=?
        """, [boundary_id])
        isempty(rows[1]) && return nothing
        return Dict(
            "boundaryLength" => String(rows[1][1]),
            "boundaryStep" => String(rows[2][1]),
            "dayCount" => Int(rows[3][1]),
            "pointCount" => Int(rows[4][1]),
        )
    end
end

"""
    get_all_boundary_configs(db_path) -> Dict{String, Dict}

获取 boundary.db 中所有 boundary 的元信息。
返回 Dict{boundary_id => config_dict}。
"""
function get_all_boundary_configs(db_path::String)
    ensure_boundary_config_table!(db_path)
    store = get_store(db_path)
    return lock(store.write_lock) do
        rows = _query(store.db, """
            SELECT boundary_id, boundary_length, boundary_step, day_count, point_count
            FROM boundary_config
        """)
        result = Dict{String, Dict}()
        if !isempty(rows[1])
            for i in eachindex(rows[1])
                bid = String(rows[1][i])
                result[bid] = Dict(
                    "boundaryLength" => String(rows[2][i]),
                    "boundaryStep" => String(rows[3][i]),
                    "dayCount" => Int(rows[4][i]),
                    "pointCount" => Int(rows[5][i]),
                )
            end
        end
        return result
    end
end

"""
    get_all_boundary_ids(project_id::String) -> Vector{String}

从 boundary.db 获取所有有数据的边界ID（source_id）。
"""
function get_all_boundary_ids(project_id::String)
    db_path = joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")
    isfile(db_path) || return String[]

    store = get_store(db_path)
    return lock(store.write_lock) do
        rows = _query(store.db, """
            SELECT DISTINCT source_id FROM time_series_meta
            WHERE remark='planned'
            ORDER BY source_id
        """)
        isempty(rows[1]) ? String[] : String.(rows[1])
    end
end

"""
    prepare_boundaries_for_clustering(project_id, boundary_ids) -> Dict

预处理所有边界数据，用于聚类计算。
- 以最短的 boundaryLength 为准，截断到24h的倍数
- 先截断再统一尺度到1h

返回 Dict：
- `data`: Dict{boundary_id => Vector{Float64}} （1h尺度的数据）
- `totalHours`: 统一后的总小时数
- `dayCount`: 天数
- `warnings`: 提示信息
"""
function prepare_boundaries_for_clustering(project_id::String, boundary_ids::Vector{String})
    isempty(boundary_ids) && error("至少需要一个边界")

    db_path = joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")
    isfile(db_path) || error("项目边界数据库不存在: $(db_path)")

    # 1. 获取所有边界的配置信息
    configs = get_all_boundary_configs(db_path)
    store = get_store(db_path)

    # 2. 读取每个边界的数据和配置
    boundary_data = Dict{String, Dict{String, Any}}()
    warnings = String[]

    for bid in boundary_ids
        config = get(configs, bid, nothing)
        if config === nothing
            # 如果没有配置信息，尝试从数据推断
            push!(warnings, "边界 $(bid) 缺少配置信息，将从数据推断")
            # 读取数据
            lock(store.write_lock) do
                meta_rows = _query(store.db, """
                    SELECT id, var_name FROM time_series_meta
                    WHERE source_id=? AND remark='planned'
                    ORDER BY CAST(layer_id AS INTEGER) ASC LIMIT 1
                """, [bid])
                isempty(meta_rows[1]) && error("边界 $(bid) 没有数据")

                series_id = Int(meta_rows[1][1])
                data_rows = _query(store.db,
                    "SELECT ts, value FROM time_series_data WHERE series_id=?",
                    [series_id])
                isempty(data_rows[1]) && error("边界 $(bid) 没有时序数据点")

                timestamps = Vector{String}(data_rows[1])
                values = Vector{Float64}(data_rows[2])
                perm = sortperm(timestamps; lt=time_label_less_than)
                sorted_ts = timestamps[perm]
                sorted_vals = values[perm]

                # 推断分辨率
                point_count = length(sorted_vals)
                resolution_min = if point_count >= 288
                    5
                elseif point_count >= 96
                    15
                else
                    60
                end

                # 计算总时长（小时）
                total_hours = point_count * resolution_min / 60
                # 截断到24h的倍数
                day_count = floor(Int, total_hours / 24)
                truncate_count = day_count * 24 * 60 ÷ resolution_min

                boundary_data[bid] = Dict(
                    "values" => Float64.(sorted_vals[1:truncate_count]),
                    "resolutionMin" => resolution_min,
                    "totalHours" => day_count * 24,
                    "dayCount" => day_count,
                    "boundaryStep" => "$(resolution_min)m",
                )
            end
        else
            # 有配置信息
            boundary_length = config["boundaryLength"]
            boundary_step = config["boundaryStep"]

            # 解析长度（小时）
            length_match = match(r"^(\d+)h$", boundary_length)
            length_match === nothing && error("边界 $(bid) 的长度格式错误: $(boundary_length)")
            total_hours = parse(Int, length_match[1])

            # 解析尺度（分钟）
            step_minutes = time_str_to_minutes(boundary_step)

            # 截断到24h的倍数
            day_count = floor(Int, total_hours / 24)
            actual_hours = day_count * 24

            # 读取数据
            lock(store.write_lock) do
                meta_rows = _query(store.db, """
                    SELECT id FROM time_series_meta
                    WHERE source_id=? AND remark='planned'
                    ORDER BY CAST(layer_id AS INTEGER) ASC LIMIT 1
                """, [bid])
                isempty(meta_rows[1]) && error("边界 $(bid) 没有数据")

                series_id = Int(meta_rows[1][1])
                data_rows = _query(store.db,
                    "SELECT ts, value FROM time_series_data WHERE series_id=?",
                    [series_id])
                isempty(data_rows[1]) && error("边界 $(bid) 没有时序数据点")

                timestamps = Vector{String}(data_rows[1])
                values = Vector{Float64}(data_rows[2])
                perm = sortperm(timestamps; lt=time_label_less_than)
                sorted_ts = timestamps[perm]
                sorted_vals = values[perm]

                # 截断到实际需要的点数
                truncate_count = actual_hours * 60 ÷ step_minutes
                truncate_count = min(truncate_count, length(sorted_vals))

                boundary_data[bid] = Dict(
                    "values" => Float64.(sorted_vals[1:truncate_count]),
                    "resolutionMin" => step_minutes,
                    "totalHours" => actual_hours,
                    "dayCount" => day_count,
                    "boundaryStep" => boundary_step,
                )
            end
        end
    end

    # 3. 以最短的长度为准
    min_day_count = minimum(d["dayCount"] for d in values(boundary_data))
    min_day_count < 1 && error("边界数据不足24小时，无法进行聚类")

    # 统一截断到最短长度
    processed = Dict{String, Vector{Float64}}()
    for (bid, data) in boundary_data
        values = data["values"]
        step_min = data["resolutionMin"]
        target_points = min_day_count * 24 * 60 ÷ step_min
        target_points = min(target_points, length(values))

        if step_min == 60
            # 已经是1h尺度
            processed[bid] = values[1:target_points]
        else
            # 需要重采样到1h
            layer = Dict{String,Any}("length" => "$(min_day_count * 24)h", "step" => "1h")
            ts = parse_boundary_data(
                Vector{Any}(values[1:target_points]),
                "$(step_min)m",
                layer;
                start_time="0:00",
                interpolate_type="linear",
            )
            processed[bid] = ts.values
        end
    end

    # 检查是否所有边界长度一致
    lengths = [length(v) for v in values(processed)]
    if length(unique(lengths)) > 1
        push!(warnings, "警告：统一后边界长度不一致，将截断到最短长度")
        min_len = minimum(lengths)
        for bid in keys(processed)
            processed[bid] = processed[bid][1:min_len]
        end
    end

    return Dict(
        "data" => processed,
        "totalHours" => min_day_count * 24,
        "dayCount" => min_day_count,
        "warnings" => warnings,
    )
end

"""
    delete_ts_by_source_id(; db_path, source_id, var_name, remark) -> Int

按 (source_id, var_name, remark) 组合删除所有匹配的 series（不限 layer_id）。
返回被删除的 series 数量（包含其下全部 data 点）。
至少需要提供一个过滤维度，否则报错。
"""
function delete_ts_by_source_id(;
    db_path::String,
    source_id::Union{String,Nothing}=nothing,
    var_name::Union{String,Nothing}=nothing,
    remark::Union{String,Nothing}=nothing,
)
    source_id !== nothing || var_name !== nothing || remark !== nothing ||
        error("delete_ts_by_source_id requires at least one of source_id/var_name/remark")

    store = get_store(db_path)

    where_clauses = String[]
    params = String[]
    source_id !== nothing && (push!(where_clauses, "source_id=?"); push!(params, source_id))
    var_name !== nothing && (push!(where_clauses, "var_name=?"); push!(params, var_name))
    remark !== nothing && (push!(where_clauses, "remark=?"); push!(params, remark))
    where_sql = join(where_clauses, " AND ")

    lock(store.write_lock) do
        # 1) 先把命中的 series_id 都查出来
        rows = _query(store.db,
            "SELECT id FROM time_series_meta WHERE $where_sql", params)
        isempty(rows[1]) && return 0
        n = length(rows[1])

        # 2) 事务内删除：先删 data（子表），再删 meta（父表）
        #    外键 ON DELETE CASCADE 保证一致性，但显式删更安全（SQLite 默认可能未开 FK）
        _exec(store.db, "BEGIN IMMEDIATE")
        try
            _exec(store.db,
                "DELETE FROM time_series_data WHERE series_id IN (SELECT id FROM time_series_meta WHERE $where_sql)",
                params)
            _exec(store.db, "DELETE FROM time_series_meta WHERE $where_sql", params)
            _exec(store.db, "COMMIT")
        catch e
            try; _exec(store.db, "ROLLBACK"); catch; end
            rethrow(e)
        end

        return n
    end
end

# 计算任务边界注入
# 任务启动时，把项目级 boundary DB 里的 planned 边界数据，按 layer_id 过滤后
# 复制到任务自己的 DB。
# 如果提供 sim_start_time 和 sim_end_time，则按仿真时间范围截断边界数据。
# 文档：docs/compute-task-architecture.md § 9

"""
    seed_task_boundary_data(task_id, project_id, layer_id; sim_start_time, sim_end_time)

从 `data/projects/<project_id>/boundary.db` 读所有
`(source_id, var_name, layer_id, remark="planned")` 的元数据和数据，
写入 `data/tasks/<task_id>/timeseries.db`。

如果提供 `sim_start_time` 和 `sim_end_time`，则按仿真时间范围截断边界数据。
如果仿真时间范围大于边界数据本身的长度，报错。
"""
function seed_task_boundary_data(
    task_id::String,
    project_id::String,
    layer_id::String;
    sim_start_time::Union{String,Nothing}=nothing,
    sim_end_time::Union{String,Nothing}=nothing,
)
    src_path = joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")
    dst_path = joinpath(BACKEND_DATA_DIR, "tasks", task_id, "timeseries.db")

    if !isfile(src_path)
        @warn "boundary_seeder: 源 DB 不存在" src_path
        return 0
    end

    # 计算仿真时间范围（分钟）
    sim_start_minutes = sim_start_time !== nothing ? time_label_to_minutes(sim_start_time) : nothing
    sim_end_minutes = sim_end_time !== nothing ? time_label_to_minutes(sim_end_time) : nothing
    sim_duration_minutes = if sim_start_minutes !== nothing && sim_end_minutes !== nothing
        sim_end_minutes - sim_start_minutes
    else
        nothing
    end

    src_db = SQLite.DB(src_path)
    try
        # 取该 layer 下的 planned 系列
        # 列顺序：1=id (series_id), 2=source_id, 3=var_name
        # 使用 _query 确保 stmt 被 sqlite3_finalize（而非仅 sqlite3_reset）
        meta_rows = _query(src_db, """
            SELECT id, source_id, var_name
            FROM time_series_meta
            WHERE layer_id=? AND remark='planned'
        """, [layer_id])

        isempty(meta_rows[1]) && return 0

        # 先收集所有要写入的 (label, TimeSeries) 对
        pairs = Tuple{String,TimeSeries}[]
        for i in 1:length(meta_rows[1])
            sid = meta_rows[1][i]
            source_id = meta_rows[2][i]
            var_name = meta_rows[3][i]
            data_rows = _query(src_db,
                "SELECT ts, value FROM time_series_data WHERE series_id=?",
                [sid])
            isempty(data_rows[1]) && continue
            # 按时间数值排序（ts 格式为 "H:MM"，字典序不等于时间序）
            timestamps = Vector{String}(data_rows[1])
            values = Vector{Float64}(data_rows[2])
            perm = sortperm(timestamps; lt=time_label_less_than)
            sorted_ts = timestamps[perm]
            sorted_vals = values[perm]

            # 如果有仿真时间范围，检查并截断
            if sim_duration_minutes !== nothing
                # 获取 boundary 的实际时长（从 boundary_config 表）
                boundary_config = get_boundary_config(src_path, source_id)
                if boundary_config !== nothing
                    boundary_length_minutes = time_str_to_minutes(boundary_config["boundaryLength"])
                    # 如果仿真时间范围大于边界数据长度，报错
                    sim_duration_minutes > boundary_length_minutes && error(
                        "仿真时间范围（$(sim_duration_minutes)分钟）大于边界数据长度（$(boundary_length_minutes)分钟），请缩短仿真范围或补充边界数据"
                    )
                end

                # 按仿真时间范围截断
                # 需要知道时间步长来计算截断点数
                # 从 sorted_ts 推断时间步长
                if length(sorted_ts) >= 2
                    t1 = time_label_to_minutes(sorted_ts[1])
                    t2 = time_label_to_minutes(sorted_ts[2])
                    step_minutes = t2 - t1
                    # 截断到仿真结束时间
                    truncate_count = ceil(Int, sim_duration_minutes / step_minutes)
                    truncate_count = min(truncate_count, length(sorted_ts))
                    sorted_ts = sorted_ts[1:truncate_count]
                    sorted_vals = sorted_vals[1:truncate_count]
                end
            else
                # 没有仿真时间范围时，复制一倍：防止滚动优化越界（如24h层用到25:00~47:00的边界数据）
                extended_ts = vcat(sorted_ts, [minutes_to_time_label(time_label_to_minutes(t) + 24 * 60) for t in sorted_ts])
                extended_vals = vcat(sorted_vals, sorted_vals)
                sorted_ts = extended_ts
                sorted_vals = extended_vals
            end

            ts = TimeSeries(sorted_ts, sorted_vals)
            label = "$(source_id)|$(var_name)|planned#$(layer_id)"
            push!(pairs, (label, ts))
        end

        isempty(pairs) && return 0

        # 批量写入：单次 lock + 单个事务，避免 N 次加锁/开事务
        store = get_store(dst_path)
        lock(store.write_lock) do
            for (label, ts) in pairs
                _write_ts(store, label, ts)
            end
        end
        return length(pairs)
    finally
        close(src_db)
    end
end