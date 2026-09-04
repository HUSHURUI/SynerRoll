using CSV
using DataFrames
using Dates
using JSON3
using SHA
using SQLite
using TimeZones
using UUIDs: uuid4

const MAX_BOUNDARY_DATASET_ROWS = 500_000
const UTC_TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"

_dataset_dict(value) = value isa AbstractDict ? value : Dict{String,Any}()
_dataset_array(value) = value isa AbstractVector ? value : Any[]

function _project_boundary_db_path(project_id::String)
    return joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")
end

function ensure_boundary_dataset_schema!(project_id::String)
    store = get_store(_project_boundary_db_path(project_id))
    lock(store.write_lock) do
        _exec(store.db, "PRAGMA foreign_keys=ON")
        _exec(store.db, """
            CREATE TABLE IF NOT EXISTS boundary_dataset (
                id              TEXT PRIMARY KEY,
                project_id      TEXT NOT NULL,
                name            TEXT NOT NULL,
                timezone        TEXT NOT NULL,
                resolution_min  INTEGER NOT NULL,
                start_at        TEXT NOT NULL,
                end_at          TEXT NOT NULL,
                created_at      TEXT NOT NULL,
                content_hash    TEXT NOT NULL,
                point_count     INTEGER NOT NULL,
                series_count    INTEGER NOT NULL
            )
        """)
        _exec(store.db, """
            CREATE TABLE IF NOT EXISTS boundary_series (
                dataset_id      TEXT NOT NULL REFERENCES boundary_dataset(id) ON DELETE CASCADE,
                boundary_id     TEXT NOT NULL,
                name            TEXT NOT NULL,
                meaning         TEXT NOT NULL,
                component_id    TEXT,
                unit            TEXT NOT NULL,
                column_name     TEXT NOT NULL,
                PRIMARY KEY (dataset_id, boundary_id)
            )
        """)
        _exec(store.db, """
            CREATE TABLE IF NOT EXISTS boundary_point (
                dataset_id      TEXT NOT NULL REFERENCES boundary_dataset(id) ON DELETE CASCADE,
                boundary_id     TEXT NOT NULL,
                ts_utc          TEXT NOT NULL,
                value           REAL NOT NULL,
                quality         TEXT NOT NULL DEFAULT 'raw',
                PRIMARY KEY (dataset_id, boundary_id, ts_utc),
                FOREIGN KEY (dataset_id, boundary_id)
                    REFERENCES boundary_series(dataset_id, boundary_id) ON DELETE CASCADE
            )
        """)
        _exec(store.db, "CREATE INDEX IF NOT EXISTS idx_boundary_dataset_project ON boundary_dataset(project_id, created_at)")
        _exec(store.db, "CREATE INDEX IF NOT EXISTS idx_boundary_point_dataset_ts ON boundary_point(dataset_id, ts_utc)")
    end
    return store
end

function _parse_local_datetime(value)
    text = strip(string(value))
    isempty(text) && error("时间戳不能为空")
    normalized = replace(text, ' ' => 'T')
    try
        return DateTime(normalized)
    catch
        try
            return DateTime(normalized, dateformat"yyyy-mm-ddTHH:MM")
        catch
            error("无法解析时间戳: $(text)，请使用 ISO 8601 格式")
        end
    end
end

function _timestamp_to_utc(value, timezone::TimeZone)
    text = strip(string(value))
    isempty(text) && error("时间戳不能为空")

    zoned = try
        ZonedDateTime(text)
    catch
        ZonedDateTime(_parse_local_datetime(text), timezone)
    end
    utc_datetime = DateTime(astimezone(zoned, tz"UTC"))
    return Dates.format(utc_datetime, UTC_TIMESTAMP_FORMAT) * "Z"
end

function _utc_timestamp_to_local(value::AbstractString, timezone::TimeZone)
    utc = ZonedDateTime(String(value))
    return DateTime(astimezone(utc, timezone))
end

function _validate_dataset_timestamps(timestamps::Vector{String}, resolution_min::Int)
    isempty(timestamps) && error("历史边界数据不能为空")
    previous = ZonedDateTime(timestamps[1])
    for index in 2:length(timestamps)
        current = ZonedDateTime(timestamps[index])
        current > previous || error("时间戳必须严格递增且不能重复，第 $(index) 行不合法")
        delta_minutes = Dates.value(DateTime(current) - DateTime(previous)) ÷ 60_000
        delta_minutes >= resolution_min || error("第 $(index) 行时间间隔小于 resolutionMinutes")
        delta_minutes % resolution_min == 0 || error("第 $(index) 行时间戳没有落在统一分辨率网格上")
        previous = current
    end
end

function _dataset_content_hash(file_path::String, config)
    file_digest = SHA.sha256(read(file_path))
    config_digest = SHA.sha256(Vector{UInt8}(codeunits(JSON3.write(config))))
    return bytes2hex(SHA.sha256(vcat(file_digest, config_digest)))
end

function _dataset_summary(rows, index::Int)
    return Dict{String,Any}(
        "id" => String(rows.id[index]),
        "projectId" => String(rows.project_id[index]),
        "name" => String(rows.name[index]),
        "timezone" => String(rows.timezone[index]),
        "resolutionMinutes" => Int(rows.resolution_min[index]),
        "startAt" => String(rows.start_at[index]),
        "endAt" => String(rows.end_at[index]),
        "createdAt" => String(rows.created_at[index]),
        "contentHash" => String(rows.content_hash[index]),
        "pointCount" => Int(rows.point_count[index]),
        "seriesCount" => Int(rows.series_count[index]),
    )
end

"""
    import_boundary_dataset(config) -> Dict

从一个长周期 CSV 导入多条边界序列。时间可以来自 `timestampColumn`，也可以由
`startAt + resolutionMinutes` 无歧义生成；全部按 UTC 写入项目级 boundary.db。
"""
function import_boundary_dataset(config::AbstractDict)
    project_id = string(get(config, "projectId", ""))
    name = strip(string(get(config, "name", "")))
    file_path = string(get(config, "filePath", ""))
    timezone_name = string(get(config, "timezone", "Asia/Shanghai"))
    resolution_min = Int(get(config, "resolutionMinutes", 60))
    timestamp_column = strip(string(get(config, "timestampColumn", "")))
    start_at = strip(string(get(config, "startAt", "")))
    series_config = _dataset_array(get(config, "series", nothing))

    isempty(project_id) && error("缺少 projectId")
    isempty(name) && error("数据集名称不能为空")
    isfile(file_path) || error("CSV 文件不存在: $(file_path)")
    1 <= resolution_min <= 1440 || error("resolutionMinutes 必须在 1 到 1440 之间")
    1440 % resolution_min == 0 || error("resolutionMinutes 必须能整除 1440")
    isempty(series_config) && error("至少选择一条边界序列")

    timezone = try
        TimeZone(timezone_name)
    catch
        error("无效时区: $(timezone_name)")
    end

    frame = CSV.read(file_path, DataFrame; header=1)
    row_count = nrow(frame)
    row_count > 0 || error("CSV 没有数据行")
    row_count <= MAX_BOUNDARY_DATASET_ROWS || error("CSV 超过最大行数 $(MAX_BOUNDARY_DATASET_ROWS)")
    columns = Set(String.(names(frame)))

    timestamps = String[]
    if !isempty(timestamp_column)
        timestamp_column in columns || error("CSV 不存在时间列: $(timestamp_column)")
        for (index, value) in enumerate(frame[!, timestamp_column])
            ismissing(value) && error("时间列第 $(index) 行为空")
            push!(timestamps, _timestamp_to_utc(value, timezone))
        end
    else
        isempty(start_at) && error("未指定 timestampColumn 时必须提供 startAt")
        start_utc = ZonedDateTime(_timestamp_to_utc(start_at, timezone))
        timestamps = [
            Dates.format(DateTime(start_utc + Minute((index - 1) * resolution_min)), UTC_TIMESTAMP_FORMAT) * "Z"
            for index in 1:row_count
        ]
    end
    _validate_dataset_timestamps(timestamps, resolution_min)

    series = Dict{String,Any}[]
    values_by_boundary = Dict{String,Vector{Float64}}()
    seen_boundary_ids = Set{String}()
    for raw_series in series_config
        item = _dataset_dict(raw_series)
        boundary_id = strip(string(get(item, "boundaryId", "")))
        column_name = strip(string(get(item, "columnName", "")))
        isempty(boundary_id) && error("series.boundaryId 不能为空")
        boundary_id in seen_boundary_ids && error("边界序列重复: $(boundary_id)")
        push!(seen_boundary_ids, boundary_id)
        column_name in columns || error("CSV 不存在数据列: $(column_name)")

        values = Float64[]
        for (index, value) in enumerate(frame[!, column_name])
            ismissing(value) && error("$(column_name) 第 $(index) 行为空")
            value isa Real || error("$(column_name) 第 $(index) 行不是数值")
            number = Float64(value)
            isfinite(number) || error("$(column_name) 第 $(index) 行不是有限数值")
            push!(values, number)
        end
        values_by_boundary[boundary_id] = values
        push!(series, Dict{String,Any}(
            "boundaryId" => boundary_id,
            "name" => strip(string(get(item, "name", boundary_id))),
            "meaning" => strip(string(get(item, "meaning", "other"))),
            "componentId" => strip(string(get(item, "componentId", ""))),
            "unit" => strip(string(get(item, "unit", ""))),
            "columnName" => column_name,
        ))
    end

    dataset_id = "dataset-$(uuid4())"
    created_at = Dates.format(now(), dateformat"yyyy-mm-ddTHH:MM:SS.s")
    content_hash = _dataset_content_hash(file_path, Dict(
        "timezone" => timezone_name,
        "resolutionMinutes" => resolution_min,
        "timestampColumn" => timestamp_column,
        "startAt" => start_at,
        "series" => series,
    ))
    store = ensure_boundary_dataset_schema!(project_id)

    lock(store.write_lock) do
        _exec(store.db, "BEGIN IMMEDIATE")
        try
            _exec(store.db, """
                INSERT INTO boundary_dataset
                    (id, project_id, name, timezone, resolution_min, start_at, end_at,
                     created_at, content_hash, point_count, series_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                dataset_id, project_id, name, timezone_name, resolution_min,
                first(timestamps), last(timestamps), created_at, content_hash,
                row_count, length(series),
            ))

            for item in series
                component_id = isempty(item["componentId"]) ? missing : item["componentId"]
                _exec(store.db, """
                    INSERT INTO boundary_series
                        (dataset_id, boundary_id, name, meaning, component_id, unit, column_name)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (
                    dataset_id, item["boundaryId"], item["name"], item["meaning"],
                    component_id, item["unit"], item["columnName"],
                ))

                values = values_by_boundary[item["boundaryId"]]
                for (timestamp, value) in zip(timestamps, values)
                    _exec(store.db, """
                        INSERT INTO boundary_point (dataset_id, boundary_id, ts_utc, value, quality)
                        VALUES (?, ?, ?, ?, 'raw')
                    """, (dataset_id, item["boundaryId"], timestamp, value))
                end
            end
            _exec(store.db, "COMMIT")
        catch
            try
                _exec(store.db, "ROLLBACK")
            catch
            end
            rethrow()
        end
    end

    return Dict{String,Any}(
        "id" => dataset_id,
        "projectId" => project_id,
        "name" => name,
        "timezone" => timezone_name,
        "resolutionMinutes" => resolution_min,
        "startAt" => first(timestamps),
        "endAt" => last(timestamps),
        "createdAt" => created_at,
        "contentHash" => content_hash,
        "pointCount" => row_count,
        "seriesCount" => length(series),
        "series" => series,
    )
end

function list_boundary_datasets(project_id::String)
    store = ensure_boundary_dataset_schema!(project_id)
    return lock(store.write_lock) do
        rows = _query(store.db, """
            SELECT id, project_id, name, timezone, resolution_min, start_at, end_at,
                   created_at, content_hash, point_count, series_count
            FROM boundary_dataset
            WHERE project_id = ?
            ORDER BY created_at DESC
        """, (project_id,))
        isempty(rows.id) && return Dict{String,Any}[]
        return [_dataset_summary(rows, index) for index in eachindex(rows.id)]
    end
end

function get_boundary_dataset(project_id::String, dataset_id::String)
    store = ensure_boundary_dataset_schema!(project_id)
    return lock(store.write_lock) do
        rows = _query(store.db, """
            SELECT id, project_id, name, timezone, resolution_min, start_at, end_at,
                   created_at, content_hash, point_count, series_count
            FROM boundary_dataset WHERE id = ? AND project_id = ?
        """, (dataset_id, project_id))
        isempty(rows.id) && error("历史边界数据集不存在: $(dataset_id)")
        result = _dataset_summary(rows, 1)

        series_rows = _query(store.db, """
            SELECT boundary_id, name, meaning, component_id, unit, column_name
            FROM boundary_series WHERE dataset_id = ? ORDER BY boundary_id
        """, (dataset_id,))
        result["series"] = [Dict{String,Any}(
            "boundaryId" => String(series_rows.boundary_id[index]),
            "name" => String(series_rows.name[index]),
            "meaning" => String(series_rows.meaning[index]),
            "componentId" => ismissing(series_rows.component_id[index]) ? "" : String(series_rows.component_id[index]),
            "unit" => String(series_rows.unit[index]),
            "columnName" => String(series_rows.column_name[index]),
        ) for index in eachindex(series_rows.boundary_id)]
        return result
    end
end

function delete_boundary_dataset!(project_id::String, dataset_id::String)
    get_boundary_dataset(project_id, dataset_id)
    store = ensure_boundary_dataset_schema!(project_id)
    lock(store.write_lock) do
        _exec(store.db, "DELETE FROM boundary_dataset WHERE id = ? AND project_id = ?", (dataset_id, project_id))
    end
    return nothing
end

function load_boundary_dataset_features(
    project_id::String,
    dataset_id::String,
    feature_ids::Vector{String},
)
    isempty(feature_ids) && error("至少选择一个聚类 feature")
    length(unique(feature_ids)) == length(feature_ids) || error("featureIds 不能重复")
    metadata = get_boundary_dataset(project_id, dataset_id)
    available = Dict(item["boundaryId"] => item for item in metadata["series"])
    for feature_id in feature_ids
        haskey(available, feature_id) || error("数据集不包含 feature: $(feature_id)")
    end

    store = ensure_boundary_dataset_schema!(project_id)
    points = Dict(feature_id => Tuple{String,Float64}[] for feature_id in feature_ids)
    lock(store.write_lock) do
        for feature_id in feature_ids
            rows = _query(store.db, """
                SELECT ts_utc, value FROM boundary_point
                WHERE dataset_id = ? AND boundary_id = ? ORDER BY ts_utc
            """, (dataset_id, feature_id))
            for index in eachindex(rows.ts_utc)
                push!(points[feature_id], (String(rows.ts_utc[index]), Float64(rows.value[index])))
            end
        end
    end
    return metadata, points
end
