using Clustering
using Dates
using JSON3
using Random
using SHA
using Statistics
using TimeZones

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
        row_range = ((feature_index - 1) * points_per_day + 1):(feature_index * points_per_day)
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

function _align_feature_points(
    feature_points::Dict{String,Vector{Tuple{String,Float64}}},
    feature_ids::Vector{String},
)
    original_point_counts = Dict(
        feature_id => length(feature_points[feature_id]) for feature_id in feature_ids
    )
    original_lengths_consistent = length(unique(values(original_point_counts))) == 1
    reference_timestamps = first.(feature_points[first(feature_ids)])
    originally_aligned = all(
        first.(feature_points[feature_id]) == reference_timestamps for feature_id in feature_ids
    )

    common_timestamps = Set(timestamp for (timestamp, _) in feature_points[first(feature_ids)])
    for feature_id in feature_ids[2:end]
        common_timestamps = intersect(
            common_timestamps,
            Set(timestamp for (timestamp, _) in feature_points[feature_id]),
        )
    end
    isempty(common_timestamps) && error("所选聚类特征没有重叠时间范围，无法对齐")

    ordered_timestamps = sort!(collect(common_timestamps))
    aligned_points = Dict{String,Vector{Tuple{String,Float64}}}()
    truncated_point_counts = Dict{String,Int}()
    for feature_id in feature_ids
        values_by_timestamp = Dict(feature_points[feature_id])
        aligned_points[feature_id] = [
            (timestamp, values_by_timestamp[timestamp]) for timestamp in ordered_timestamps
        ]
        truncated_point_counts[feature_id] = original_point_counts[feature_id] - length(ordered_timestamps)
    end

    alignment = Dict{String,Any}(
        "originallyAligned" => originally_aligned,
        "originalLengthsConsistent" => original_lengths_consistent,
        "originalPointCounts" => original_point_counts,
        "alignedPointCount" => length(ordered_timestamps),
        "truncatedPointCount" => sum(values(truncated_point_counts)),
        "truncatedPointCounts" => truncated_point_counts,
        "commonStartAt" => first(ordered_timestamps),
        "commonEndAt" => last(ordered_timestamps),
    )
    return aligned_points, alignment
end

function _pairwise_squared_distances(matrix::Matrix{Float64})
    point_count = size(matrix, 2)
    dimension_count = size(matrix, 1)
    distances = zeros(Float64, point_count, point_count)
    @inbounds for left in 1:(point_count - 1)
        for right in (left + 1):point_count
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

"""
    reduce_boundary_scenarios(config) -> Dict

先按共同时间戳对齐并截断所选历史边界，再按数据集时区切为自然日；
按 feature 独立归一化后执行指定聚类算法，每簇返回真实观测场景。
"""
function reduce_boundary_scenarios(config::AbstractDict)
    project_id = string(get(config, "projectId", ""))
    dataset_id = string(get(config, "datasetId", ""))
    feature_ids = String.(collect(_dataset_array(get(config, "featureIds", nothing))))
    cluster_count = Int(get(config, "clusterCount", 0))
    algorithm = string(get(config, "algorithm", "kmeans"))
    normalize = string(get(config, "normalize", "zscore"))
    missing_threshold = Float64(get(config, "missingDayThreshold", 0.05))
    seed = Int(get(config, "seed", 20260828))
    representative = string(get(config, "representative", "nearest-observation"))

    isempty(project_id) && error("缺少 projectId")
    isempty(dataset_id) && error("缺少 datasetId")
    algorithm in ("kmeans", "kmedoids") || error("algorithm 只能是 kmeans 或 kmedoids")
    0.0 <= missing_threshold <= 1.0 || error("missingDayThreshold 必须在 0 到 1 之间")
    representative == "nearest-observation" || error("MVP 仅支持 nearest-observation 代表场景")

    metadata, feature_points = load_boundary_dataset_features(project_id, dataset_id, feature_ids)
    feature_points, alignment = _align_feature_points(feature_points, feature_ids)
    resolution_min = Int(metadata["resolutionMinutes"])
    points_per_day = 1440 ÷ resolution_min
    timezone = TimeZone(String(metadata["timezone"]))
    warnings = String[]
    if alignment["truncatedPointCount"] > 0
        push!(
            warnings,
            "聚类前已按共同时间戳对齐，共截断 $(alignment["truncatedPointCount"]) 个多余数据点",
        )
    end

    buckets = Dict{Date,Dict{String,Dict{Int,Float64}}}()
    duplicate_days = Set{Date}()
    for feature_id in feature_ids
        for (timestamp, value) in feature_points[feature_id]
            local_datetime = _utc_timestamp_to_local(timestamp, timezone)
            day = Date(local_datetime)
            minute_of_day = Dates.hour(local_datetime) * 60 + Dates.minute(local_datetime)
            minute_of_day % resolution_min == 0 || error("$(timestamp) 未落在 $(resolution_min) 分钟网格上")
            slot = minute_of_day ÷ resolution_min + 1
            day_features = get!(buckets, day, Dict{String,Dict{Int,Float64}}())
            feature_slots = get!(day_features, feature_id, Dict{Int,Float64}())
            haskey(feature_slots, slot) && push!(duplicate_days, day)
            feature_slots[slot] = value
        end
    end

    valid_days = Date[]
    day_values = Dict{Date,Dict{String,Vector{Float64}}}()
    excluded_days = Dict{String,String}()
    for day in sort(collect(keys(buckets)))
        if day in duplicate_days
            excluded_days[string(day)] = "duplicate-local-time"
            continue
        end

        raw = Dict{String,Vector{Union{Nothing,Float64}}}()
        missing_count = 0
        for feature_id in feature_ids
            slots = get(buckets[day], feature_id, Dict{Int,Float64}())
            values = Union{Nothing,Float64}[get(slots, slot, nothing) for slot in 1:points_per_day]
            missing_count += count(isnothing, values)
            raw[feature_id] = values
        end

        missing_rate = missing_count / (points_per_day * length(feature_ids))
        if missing_rate > missing_threshold
            excluded_days[string(day)] = "missing-rate=$(round(missing_rate; digits=4))"
            continue
        end

        filled = Dict{String,Vector{Float64}}()
        try
            for feature_id in feature_ids
                filled[feature_id] = _fill_missing_day(raw[feature_id])
            end
        catch e
            excluded_days[string(day)] = sprint(showerror, e)
            continue
        end
        day_values[day] = filled
        push!(valid_days, day)
    end

    2 <= cluster_count <= length(valid_days) ||
        error("clusterCount 必须在 2 到有效日数 $(length(valid_days)) 之间")

    raw_matrix = Matrix{Float64}(undef, points_per_day * length(feature_ids), length(valid_days))
    for (day_index, day) in enumerate(valid_days)
        for (feature_index, feature_id) in enumerate(feature_ids)
            row_range = ((feature_index - 1) * points_per_day + 1):(feature_index * points_per_day)
            raw_matrix[row_range, day_index] = day_values[day][feature_id]
        end
    end

    normalized_matrix = copy(raw_matrix)
    normalization = _normalize_scenario_matrix!(
        normalized_matrix, feature_ids, points_per_day, normalize, warnings
    )
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

    scenario_records = Dict{String,Any}[]
    for cluster in 1:cluster_count
        member_indices = findall(==(cluster), result.assignments)
        isempty(member_indices) && error("$(algorithm_label) 产生空簇: $(cluster)")
        representative_index = member_indices[argmin(result.costs[member_indices])]
        representative_day = valid_days[representative_index]
        weight_days = length(member_indices)

        push!(scenario_records, Dict{String,Any}(
            "representativeDate" => string(representative_day),
            "weightDays" => weight_days,
            "probability" => weight_days / length(valid_days),
            "memberDates" => string.(valid_days[member_indices]),
            "distanceToCenter" => result.costs[representative_index],
            "series" => Dict(feature_id => day_values[representative_day][feature_id] for feature_id in feature_ids),
        ))
    end
    sort!(scenario_records; by=item -> item["representativeDate"])
    for (index, item) in enumerate(scenario_records)
        item["scenarioId"] = "scenario-$(index)"
    end

    weighted_mean_error = Dict{String,Any}()
    for feature_id in feature_ids
        original_mean = mean(vcat([day_values[day][feature_id] for day in valid_days]...))
        representative_mean = sum(
            mean(item["series"][feature_id]) * item["weightDays"] for item in scenario_records
        ) / length(valid_days)
        denominator = max(abs(original_mean), eps(Float64))
        weighted_mean_error[feature_id] = Dict(
            "originalMean" => original_mean,
            "representativeMean" => representative_mean,
            "relativeError" => (representative_mean - original_mean) / denominator,
        )
    end

    scenario_hash_payload = Dict(
        "datasetHash" => metadata["contentHash"],
        "featureIds" => feature_ids,
        "clusterCount" => cluster_count,
        "algorithm" => algorithm,
        "normalize" => normalize,
        "missingDayThreshold" => missing_threshold,
        "seed" => seed,
        "scenarios" => scenario_records,
    )
    scenario_set_hash = bytes2hex(SHA.sha256(Vector{UInt8}(codeunits(JSON3.write(scenario_hash_payload)))))

    return Dict{String,Any}(
        "scenarioSetHash" => scenario_set_hash,
        "dataset" => metadata,
        "config" => Dict(
            "featureIds" => feature_ids,
            "resolutionMinutes" => resolution_min,
            "clusterCount" => cluster_count,
            "algorithm" => algorithm,
            "normalize" => normalize,
            "missingDayThreshold" => missing_threshold,
            "seed" => seed,
            "representative" => representative,
        ),
        "scenarios" => scenario_records,
        "quality" => Dict(
            "validDayCount" => length(valid_days),
            "excludedDayCount" => length(excluded_days),
            "excludedDays" => excluded_days,
            "sse" => result.totalcost,
            "iterations" => result.iterations,
            "converged" => result.converged,
            "normalization" => normalization,
            "alignment" => alignment,
            "weightedMeanError" => weighted_mean_error,
            "warnings" => warnings,
        ),
    )
end
