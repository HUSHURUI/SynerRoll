using Random

function parse_boundary_data(
    data_array::Vector{Any},
    time_step::String,
    layer::Dict{String, Any};
    start_time::String="0:00",
    interpolate_type::String="copy",
    noise_level::Float64=0.0,
)
    interpolate_type in ["copy", "linear"] || error("interpolate_type must be copy or linear")
    noise_level >= 0.0 || error("noise_level must be non-negative")

    layer_length_minutes = time_str_to_minutes(layer["length"])
    layer_step_minutes = time_str_to_minutes(layer["step"])
    data_step_minutes = time_str_to_minutes(time_step)

    layer_length_minutes % (24 * 60) == 0 || error("layer length must be a multiple of 24h")
    24 * 60 <= layer_length_minutes <= 168 * 60 || error("layer length must stay within 24h to 168h")
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

    timestamps = generate_timestamps("0:00", layer["step"], layer["length"])
    return TimeSeries(timestamps, abs.(final_values))
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
# 文档：docs/compute-task-architecture.md § 9

"""
    seed_task_boundary_data(task_id::String, project_id::String, layer_id::String)

从 `data/projects/<project_id>/boundary.db` 读所有
`(source_id, var_name, layer_id, remark="planned")` 的元数据和数据，
写入 `data/tasks/<task_id>/timeseries.db`。
"""
function seed_task_boundary_data(task_id::String, project_id::String, layer_id::String)
    src_path = joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")
    dst_path = joinpath(BACKEND_DATA_DIR, "tasks", task_id, "timeseries.db")

    if !isfile(src_path)
        @warn "boundary_seeder: 源 DB 不存在" src_path
        return 0
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
            # 复制一倍：防止滚动优化越界（如24h层用到25:00~47:00的边界数据）
            extended_ts = vcat(sorted_ts, [minutes_to_time_label(time_label_to_minutes(t) + 24 * 60) for t in sorted_ts])
            extended_vals = vcat(sorted_vals, sorted_vals)
            ts = TimeSeries(extended_ts, extended_vals)
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