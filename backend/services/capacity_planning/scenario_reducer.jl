using Clustering
using Dates
using JSON3
using Random
using SHA
using Statistics
using TimeZones

# ───── 数据读取：从 TS 库读取边界数据 ─────

"""
    load_ts_boundary_features(project_id, feature_ids) -> (metadata, feature_points)

从项目级 boundary.db 的 TS 库读取边界数据。
返回 metadata（含 resolutionMinutes, timezone, contentHash, series）和
feature_points（Dict{boundary_id => Vector{(timestamp, value)}}）。
"""
function load_ts_boundary_features(project_id::String, feature_ids::Vector{String})
    isempty(feature_ids) && error("至少选择一个聚类特征")

    db_path = joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")
    isfile(db_path) || error("项目边界数据库不存在: $(db_path)")

    store = get_store(db_path)
    feature_points = Dict{String,Vector{Tuple{String,Float64}}}()
    series_info = Dict{String,Any}[]

    lock(store.write_lock) do
        for boundary_id in feature_ids
            meta_rows = _query(store.db, """
                SELECT id, var_name, layer_id FROM time_series_meta
                WHERE source_id=? AND remark='planned' AND layer_id='1'
            """, [boundary_id])

            if isempty(meta_rows[1])
                # 回退：尝试任意 layer_id
                meta_rows = _query(store.db, """
                    SELECT id, var_name, layer_id FROM time_series_meta
                    WHERE source_id=? AND remark='planned'
                    ORDER BY CAST(layer_id AS INTEGER) ASC LIMIT 1
                """, [boundary_id])
            end

            isempty(meta_rows[1]) && error("TS 库中未找到边界 $(boundary_id) 的数据")

            series_id = Int(meta_rows[1][1])
            var_name = String(meta_rows[2][1])
            layer_id = String(meta_rows[3][1])

            data_rows = _query(store.db,
                "SELECT ts, value FROM time_series_data WHERE series_id=?",
                [series_id])

            isempty(data_rows[1]) && error("边界 $(boundary_id) 没有时序数据点")

            timestamps = Vector{String}(data_rows[1])
            values = Vector{Float64}(data_rows[2])
            perm = sortperm(timestamps; lt=time_label_less_than)
            sorted_ts = timestamps[perm]
            sorted_vals = values[perm]

            feature_points[boundary_id] = [(t, v) for (t, v) in zip(sorted_ts, sorted_vals)]

            push!(series_info, Dict{String,Any}(
                "boundaryId" => boundary_id,
                "name" => var_name,
                "meaning" => var_name,
                "unit" => "",
                "layerId" => layer_id,
            ))
        end
    end

    # 从数据点数推断分辨率
    first_count = length(feature_points[first(feature_ids)])
    resolution_min = if first_count >= 288
        5
    elseif first_count >= 96
        15
    else
        60
    end

    metadata = Dict{String,Any}(
        "id" => "ts-$(project_id)",
        "name" => "项目边界数据（TS库）",
        "resolutionMinutes" => resolution_min,
        "timezone" => "Asia/Shanghai",
        "contentHash" => bytes2hex(SHA.sha256(Vector{UInt8}(codeunits(join(feature_ids, ","))))),
        "series" => series_info,
    )

    return metadata, feature_points
end

# ───── 数据预处理 ─────

"""
    _preprocess_boundaries(feature_points, feature_ids) -> (processed, points_per_day, day_count)

验证边界数据长度（≥24h），截断到24h的倍数，统一重采样到1h分辨率。
返回处理后的 Dict{boundary_id => Vector{Float64}}（1h分辨率）、每天点数、天数。
"""
function _preprocess_boundaries(
    feature_points::Dict{String,Vector{Tuple{String,Float64}}},
    feature_ids::Vector{String},
)
    # 1. 推断原始分辨率
    first_points = feature_points[first(feature_ids)]
    raw_count = length(first_points)
    raw_resolution = if raw_count >= 288
        5
    elseif raw_count >= 96
        15
    else
        60
    end

    # 2. 验证所有边界长度一致
    for fid in feature_ids
        length(feature_points[fid]) == raw_count ||
            error("边界 $(fid) 数据点数 ($(length(feature_points[fid]))) 与首个边界 ($(raw_count)) 不一致")
    end

    # 3. 验证至少24h
    total_hours = raw_count * raw_resolution / 60
    total_hours >= 24 || error("边界数据不足24小时（当前 $(round(total_hours; digits=1))h），请补充数据")

    # 4. 截断到24h的倍数
    points_per_day = 1440 ÷ 60  # 1h分辨率下每天24点
    day_count = floor(Int, total_hours / 24)
    truncate_count = day_count * (60 ÷ raw_resolution) * 24  # 原始分辨率下的截断点数

    # 5. 重采样到1h分辨率（使用 parse_boundary_data）
    processed = Dict{String,Vector{Float64}}()
    layer = Dict{String,Any}("length" => "$(day_count * 24)h", "step" => "1h")

    for fid in feature_ids
        raw_values = Float64[Float64(v) for (_, v) in feature_points[fid][1:truncate_count]]
        ts = parse_boundary_data(
            Vector{Any}(raw_values),
            "$(raw_resolution)m",
            layer;
            start_time="0:00",
            interpolate_type="linear",
        )
        processed[fid] = ts.values
    end

    return processed, points_per_day, day_count
end

# ───── 辅助函数 ─────

function _fill_missing_day(values::Vector{Union{Nothing,Float64}})
    known = findall(value -> value !== nothing, values)
    isempty(known) && error("典型场景没有任何有效数据点")
    result = Vector{Float64}(undef, length(values))

    for index in eachindex(values)
        if values[index] !== nothing
            result[index] = values[index]::Float64
            continue
        end

        previous = findlast(known_index -> known_index < index, known)
        following = findfirst(known_index -> known_index > index, known)
        if previous === nothing
            result[index] = values[known[following]]::Float64
        elseif following === nothing
            result[index] = values[known[previous]]::Float64
        else
            left_index = known[previous]
            right_index = known[following]
            left = values[left_index]::Float64
            right = values[right_index]::Float64
            ratio = (index - left_index) / (right_index - left_index)
            result[index] = left + (right - left) * ratio
        end
    end
    return result
end

function _normalize_scenario_matrix!(
    matrix::Matrix{Float64},
    feature_ids::Vector{String},
    points_per_day::Int,
    normalize::String,
    warnings::Vector{String},
)
    parameters = Dict{String,Any}()
    for (feature_index, feature_id) in enumerate(feature_ids)
        row_range = ((feature_index-1)*points_per_day+1):(feature_index*points_per_day)
        values = vec(matrix[row_range, :])

        if normalize == "zscore"
            center = mean(values)
            scale = std(values; corrected=false)
            if scale <= eps(Float64)
                scale = 1.0
                push!(warnings, "$(feature_id) 为零方差序列，zscore 标准差按 1 处理")
            end
            matrix[row_range, :] .= (matrix[row_range, :] .- center) ./ scale
            parameters[feature_id] = Dict("method" => normalize, "mean" => center, "std" => scale)
        elseif normalize == "minmax"
            minimum = Base.minimum(values)
            maximum = Base.maximum(values)
            scale = maximum - minimum
            if scale <= eps(Float64)
                scale = 1.0
                push!(warnings, "$(feature_id) 为零方差序列，minmax 极差按 1 处理")
            end
            matrix[row_range, :] .= (matrix[row_range, :] .- minimum) ./ scale
            parameters[feature_id] = Dict("method" => normalize, "min" => minimum, "max" => maximum, "scale" => scale)
        elseif normalize == "none"
            parameters[feature_id] = Dict("method" => normalize)
        else
            error("normalize 只能是 zscore、minmax 或 none")
        end
    end
    return parameters
end

function _pairwise_squared_distances(matrix::Matrix{Float64})
    point_count = size(matrix, 2)
    dimension_count = size(matrix, 1)
    distances = zeros(Float64, point_count, point_count)
    @inbounds for left in 1:(point_count-1)
        for right in (left+1):point_count
            distance = 0.0
            for dimension in 1:dimension_count
                delta = matrix[dimension, left] - matrix[dimension, right]
                distance += delta * delta
            end
            distances[left, right] = distance
            distances[right, left] = distance
        end
    end
    return distances
end

# ───── 加噪补齐 ─────

"""
    _augment_with_noise(days, feature_ids, points_per_day, need_count, seed)

当天数不足时，通过加噪生成补充天数。
"""
function _augment_with_noise(
    day_values::Dict{String,Dict{String,Vector{Float64}}},
    feature_ids::Vector{String},
    points_per_day::Int,
    need_count::Int,
    seed::Int,
)
    rng = MersenneTwister(seed)
    source_keys = collect(keys(day_values))
    augmented = Dict{String,Dict{String,Vector{Float64}}}[]

    for i in 1:need_count
        source_key = source_keys[rand(rng, 1:length(source_keys))]
        source_data = day_values[source_key]
        feature_data = Dict{String,Vector{Float64}}()
        for fid in feature_ids
            original = source_data[fid]
            noise_scale = std(original) * 0.05  # 5% 的标准差作为噪声
            noise = randn(rng, length(original)) .* noise_scale
            feature_data[fid] = abs.(original .+ noise)  # 取绝对值避免负值
        end
        push!(augmented, Dict{String,Dict{String,Vector{Float64}}}("augmented-$(i)" => feature_data))
    end

    return augmented
end

# ───── 主函数 ─────

"""
    reduce_boundary_scenarios(config) -> Dict

从 TS 库读取边界数据，预处理后执行聚类，返回典型场景。
"""
function reduce_boundary_scenarios(config::AbstractDict)
    project_id = string(get(config, "projectId", ""))
    raw_feature_ids = get(config, "featureIds", nothing)
    feature_ids = raw_feature_ids === nothing ? String[] : String.(collect(raw_feature_ids))
    cluster_count = Int(get(config, "clusterCount", 0))
    algorithm = string(get(config, "algorithm", "kmeans"))
    normalize = string(get(config, "normalize", "zscore"))
    missing_threshold = Float64(get(config, "missingDayThreshold", 0.05))
    seed = Int(get(config, "seed", 20260828))
    representative = string(get(config, "representative", "nearest-observation"))

    isempty(project_id) && error("缺少 projectId")
    isempty(feature_ids) && error("缺少 featureIds")
    algorithm in ("kmeans", "kmedoids") || error("algorithm 只能是 kmeans 或 kmedoids")
    0.0 <= missing_threshold <= 1.0 || error("missingDayThreshold 必须在 0 到 1 之间")
    representative == "nearest-observation" || error("MVP 仅支持 nearest-observation 代表场景")

    # 1. 从 TS 库读取数据
    metadata, feature_points = load_ts_boundary_features(project_id, feature_ids)

    # 2. 预处理：验证、截断、重采样到1h
    processed, points_per_day, day_count = _preprocess_boundaries(feature_points, feature_ids)

    warnings = String[]
    timezone = TimeZone(String(metadata["timezone"]))

    # 3. 按24h切分为天
    day_data = Dict{String,Dict{String,Vector{Float64}}}()
    for day_index in 1:day_count
        day_label = "day-$(day_index)"
        day_slices = Dict{String,Vector{Float64}}()
        for fid in feature_ids
            start_idx = (day_index - 1) * points_per_day + 1
            end_idx = day_index * points_per_day
            day_slices[fid] = processed[fid][start_idx:end_idx]
        end
        day_data[day_label] = day_slices
    end

    # 4. 处理天数与场景数的关系
    if day_count < cluster_count
        # 天数不足：加噪补齐
        push!(warnings, "原始数据仅 $(day_count) 天，不足 $(cluster_count) 个场景，已通过加噪补齐")
        augmented = _augment_with_noise(day_data, feature_ids, points_per_day, cluster_count - day_count, seed)
        for noisy_day in augmented
            merge!(day_data, noisy_day)
        end
    end

    all_day_keys = sort(collect(keys(day_data)))
    valid_days = all_day_keys  # 预处理后所有天都有效

    2 <= cluster_count <= length(valid_days) ||
        error("clusterCount 必须在 2 到有效天数 $(length(valid_days)) 之间")

    # 5. 构建聚类矩阵
    raw_matrix = Matrix{Float64}(undef, points_per_day * length(feature_ids), length(valid_days))
    for (day_index, day_key) in enumerate(valid_days)
        for (feature_index, fid) in enumerate(feature_ids)
            row_range = ((feature_index-1)*points_per_day+1):(feature_index*points_per_day)
            raw_matrix[row_range, day_index] = day_data[day_key][fid]
        end
    end

    # 6. 归一化
    normalized_matrix = copy(raw_matrix)
    normalization = _normalize_scenario_matrix!(
        normalized_matrix, feature_ids, points_per_day, normalize, warnings
    )
    # 7. 聚类
    result = if algorithm == "kmeans"
        kmeans(
            normalized_matrix,
            cluster_count;
            init=:kmpp,
            maxiter=300,
            tol=1.0e-8,
            display=:none,
            rng=MersenneTwister(seed),
        )
    else
        distance_matrix = _pairwise_squared_distances(normalized_matrix)
        initial_medoids = initseeds_by_costs(
            :kmpp,
            distance_matrix,
            cluster_count;
            rng=MersenneTwister(seed),
        )
        kmedoids(
            distance_matrix,
            cluster_count;
            init=initial_medoids,
            maxiter=300,
            tol=1.0e-8,
            display=:none,
        )
    end
    algorithm_label = algorithm == "kmeans" ? "K-means" : "K-medoids"
    result.converged || push!(warnings, "$(algorithm_label) 达到最大迭代次数但未声明收敛")

    # 8. 构建场景记录
    timestamps_1h = generate_timestamps("0:00", "1h", "$(points_per_day)h")

    scenario_records = Dict{String,Any}[]
    for cluster in 1:cluster_count
        member_indices = findall(==(cluster), result.assignments)
        isempty(member_indices) && error("$(algorithm_label) 产生空簇: $(cluster)")
        representative_index = member_indices[argmin(result.costs[member_indices])]
        representative_day = valid_days[representative_index]
        weight_days = length(member_indices)

        push!(scenario_records, Dict{String,Any}(
            "representativeDate" => representative_day,
            "weightDays" => weight_days,
            "probability" => weight_days / length(valid_days),
            "memberDates" => valid_days[member_indices],
            "distanceToCenter" => result.costs[representative_index],
            "series" => Dict{String,Vector{Float64}}(fid => day_data[representative_day][fid] for fid in feature_ids),
        ))
    end
    sort!(scenario_records; by=item -> item["representativeDate"])
    for (index, item) in enumerate(scenario_records)
        item["scenarioId"] = "scenario-$(index)"
    end

    # 9. 质量统计
    weighted_mean_error = Dict{String,Any}()
    for fid in feature_ids
        original_mean = mean(vcat([day_data[dk][fid] for dk in valid_days]...))
        representative_mean = sum(
            mean(item["series"][fid]) * item["weightDays"] for item in scenario_records
        ) / length(valid_days)
        denominator = max(abs(original_mean), eps(Float64))
        weighted_mean_error[fid] = Dict(
            "originalMean" => original_mean,
            "representativeMean" => representative_mean,
            "relativeError" => (representative_mean - original_mean) / denominator,
        )
    end

    scenario_hash_payload = Dict(
        "featureIds" => feature_ids,
        "clusterCount" => cluster_count,
        "algorithm" => algorithm,
        "normalize" => normalize,
        "seed" => seed,
        "scenarios" => scenario_records,
    )
    scenario_set_hash = bytes2hex(SHA.sha256(Vector{UInt8}(codeunits(JSON3.write(scenario_hash_payload)))))

    result_dict = Dict{String,Any}(
        "scenarioSetHash" => scenario_set_hash,
        "dataset" => metadata,
        "config" => Dict(
            "featureIds" => feature_ids,
            "resolutionMinutes" => 60,
            "clusterCount" => cluster_count,
            "algorithm" => algorithm,
            "normalize" => normalize,
            "missingDayThreshold" => missing_threshold,
            "seed" => seed,
            "representative" => representative,
        ),
        "scenarios" => scenario_records,
        "quality" => Dict(
            "validDayCount" => day_count,
            "augmentedDayCount" => length(valid_days) - day_count,
            "excludedDayCount" => 0,
            "sse" => result.totalcost,
            "iterations" => result.iterations,
            "converged" => result.converged,
            "normalization" => normalization,
            "weightedMeanError" => weighted_mean_error,
            "warnings" => warnings,
        ),
        "timestamps" => timestamps_1h,
    )
    return result_dict
end
