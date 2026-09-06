using Clustering
using Dates
using JSON3
using Random
using SHA
using Statistics
using TimeZones

# ───── 数据读取与预处理 ─────

"""
    load_ts_boundary_features(project_id, feature_ids, all_boundary_ids) -> (metadata, processed_data, warnings)

从 boundary.db 读取并预处理边界数据。
- 如果 feature_ids 为空，自动从 boundary.db 获取所有有数据的边界ID
- 以最短的 boundaryLength 为准，截断到24h的倍数
- 先截断再统一尺度到1h

返回：
- metadata: 包含 series 信息的元数据
- processed_data: Dict{boundary_id => Vector{Float64}} （1h尺度的数据）
- warnings: 提示信息
"""
function load_ts_boundary_features(
    project_id::String,
    feature_ids::Vector{String},
    all_boundary_ids::Vector{String},
)
    # 始终处理所有边界（特征+跟随），确保后续能提取完整数据
    isempty(all_boundary_ids) && error("项目 $(project_id) 没有配置任何边界")

    # 验证特征边界ID存在于项目中
    for fid in feature_ids
        fid in all_boundary_ids || error("边界 $(fid) 不存在于项目中")
    end

    # 调用预处理函数，始终处理所有边界
    prepared = prepare_boundaries_for_clustering(project_id, all_boundary_ids)

    # 构建 metadata：从 time_series_meta 读取 var_name
    db_path = joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")
    store = get_store(db_path)

    series_info = Dict{String,Any}[]
    lock(store.write_lock) do
        for fid in all_boundary_ids
            meta_rows = _query(store.db, """
                SELECT var_name, layer_id FROM time_series_meta
                WHERE source_id=? AND remark='planned'
                ORDER BY CAST(layer_id AS INTEGER) ASC LIMIT 1
            """, [fid])
            var_name = isempty(meta_rows[1]) ? fid : String(meta_rows[1][1])
            layer_id = isempty(meta_rows[2]) ? "1" : String(meta_rows[2][1])
            push!(series_info, Dict{String,Any}(
                "boundaryId" => fid,
                "name" => var_name,
                "meaning" => var_name,
                "unit" => "",
                "layerId" => layer_id,
            ))
        end
    end

    metadata = Dict{String,Any}(
        "id" => "ts-$(project_id)",
        "name" => "项目边界数据",
        "resolutionMinutes" => 60,
        "timezone" => "Asia/Shanghai",
        "contentHash" => bytes2hex(SHA.sha256(Vector{UInt8}(codeunits(join(all_boundary_ids, ","))))),
        "series" => series_info,
    )

    return metadata, prepared["data"], prepared["warnings"]
end

# ───── 辅助函数 ─────

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

# ───── 主函数 ─────

"""
    reduce_boundary_scenarios(config) -> Dict

从 boundary.db 读取边界数据，预处理后执行聚类，返回典型场景。

config 字段：
- projectId: 项目ID（必填）
- featureIds: 聚类特征边界ID数组（可选，为空时使用所有边界）
- clusterCount: 场景数（必填，但会被限制为可用天数）
- algorithm: "kmeans" 或 "kmedoids"（默认 "kmeans"）
- normalize: "zscore"、"minmax" 或 "none"（默认 "zscore"）
- missingDayThreshold: 缺失天数阈值（0~1，默认 0.05）
- seed: 随机种子（默认 20260828）
- representative: 代表场景选择方式（默认 "nearest-observation"）
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
    algorithm in ("kmeans", "kmedoids") || error("algorithm 只能是 kmeans 或 kmedoids")
    0.0 <= missing_threshold <= 1.0 || error("missingDayThreshold 必须在 0 到 1 之间")
    representative == "nearest-observation" || error("MVP 仅支持 nearest-observation 代表场景")

    # 1. 获取所有边界ID
    all_boundary_ids = get_all_boundary_ids(project_id)
    isempty(all_boundary_ids) && error("项目 $(project_id) 没有配置任何边界")

    # 2. 读取并预处理边界数据
    metadata, processed_data, preprocess_warnings = load_ts_boundary_features(
        project_id, feature_ids, all_boundary_ids
    )

    warnings = String[]
    append!(warnings, preprocess_warnings)
    timezone = TimeZone(String(metadata["timezone"]))

    # 确定实际使用的边界ID（特征边界）
    actual_feature_ids = isempty(feature_ids) ? all_boundary_ids : feature_ids
    # 跟随边界：all_boundary_ids 中不在 feature_ids 中的
    follow_ids = setdiff(all_boundary_ids, actual_feature_ids)

    # 3. 按24h切分为天
    points_per_day = 24  # 1h分辨率
    first_data = first(values(processed_data))
    day_count = length(first_data) ÷ points_per_day

    day_data = Dict{String,Dict{String,Vector{Float64}}}()
    for day_index in 1:day_count
        day_label = "day-$(day_index)"
        day_slices = Dict{String,Vector{Float64}}()
        for bid in keys(processed_data)
            start_idx = (day_index - 1) * points_per_day + 1
            end_idx = day_index * points_per_day
            day_slices[bid] = processed_data[bid][start_idx:end_idx]
        end
        day_data[day_label] = day_slices
    end

    # 4. 处理天数与场景数的关系
    if day_count < cluster_count
        # 天数不足：限制场景数为可用天数，发出警告
        push!(warnings, "原始数据仅 $(day_count) 天，不足 $(cluster_count) 个场景，将限制场景数为 $(day_count)")
        cluster_count = day_count
    end

    all_day_keys = sort(collect(keys(day_data)))
    valid_days = all_day_keys  # 预处理后所有天都有效

    2 <= cluster_count <= length(valid_days) ||
        error("clusterCount 必须在 2 到有效天数 $(length(valid_days)) 之间")

    # 5. 构建聚类矩阵（仅使用特征边界）
    raw_matrix = Matrix{Float64}(undef, points_per_day * length(actual_feature_ids), length(valid_days))
    for (day_index, day_key) in enumerate(valid_days)
        for (feature_index, fid) in enumerate(actual_feature_ids)
            row_range = ((feature_index-1)*points_per_day+1):(feature_index*points_per_day)
            raw_matrix[row_range, day_index] = day_data[day_key][fid]
        end
    end

    # 6. 归一化
    normalized_matrix = copy(raw_matrix)
    normalization = _normalize_scenario_matrix!(
        normalized_matrix, actual_feature_ids, points_per_day, normalize, warnings
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

        # 提取所有边界的数据（特征+跟随）
        all_series = Dict{String,Vector{Float64}}()
        for bid in all_boundary_ids
            all_series[bid] = day_data[representative_day][bid]
        end

        push!(scenario_records, Dict{String,Any}(
            "representativeDate" => representative_day,
            "weightDays" => weight_days,
            "probability" => weight_days / length(valid_days),
            "memberDates" => valid_days[member_indices],
            "distanceToCenter" => result.costs[representative_index],
            "series" => all_series,
        ))
    end
    sort!(scenario_records; by=item -> item["representativeDate"])
    for (index, item) in enumerate(scenario_records)
        item["scenarioId"] = "scenario-$(index)"
    end

    # 9. 质量统计
    weighted_mean_error = Dict{String,Any}()
    for fid in actual_feature_ids
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
        "featureIds" => actual_feature_ids,
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
            "featureIds" => actual_feature_ids,
            "followIds" => follow_ids,
            "allBoundaryIds" => all_boundary_ids,
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
