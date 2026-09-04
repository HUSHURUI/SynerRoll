# flexibility_margin_service.jl — 系统灵活性裕度与充足性计算

function _system_flexibility_margin_key(result)
    return (
        result.timestamp,
        result.time_step,
        result.case_id,
        result.application_type,
        result.operation_mode,
        result.boundary_condition,
        result.poi_id,
        result.direction,
    )
end

function _system_flexibility_margin_group_key(result)
    return (
        result.timestamp,
        result.time_step,
        result.case_id,
        result.application_type,
        result.operation_mode,
        result.boundary_condition,
        result.poi_id,
    )
end

function _index_system_flexibility_margin_inputs(results, label::String)
    indexed = Dict{Any,Any}()
    directions_by_group = Dict{Any,Set{String}}()
    for result in results
        key = _system_flexibility_margin_key(result)
        haskey(indexed, key) && error(
            "Duplicate system flexibility $(label) for timestamp=$(result.timestamp), " *
            "poi_id=$(result.poi_id), direction=$(result.direction).",
        )
        indexed[key] = result
        push!(
            get!(
                directions_by_group,
                _system_flexibility_margin_group_key(result),
                Set{String}(),
            ),
            result.direction,
        )
    end

    required_directions = Set(FLEXIBILITY_DIRECTIONS)
    for (group_key, directions) in directions_by_group
        directions == required_directions || error(
            "System flexibility $(label) must contain both up and down directions for " *
            "timestamp=$(group_key[1]), poi_id=$(group_key[7]).",
        )
    end
    return indexed
end

function _validate_system_flexibility_requirement_pairs!(requirements)
    signatures_by_group = Dict{Any,Set{Tuple{String,String}}}()
    for requirement in requirements
        push!(
            get!(
                signatures_by_group,
                _system_flexibility_margin_group_key(requirement),
                Set{Tuple{String,String}}(),
            ),
            (requirement.next_timestamp, requirement.requirement_source),
        )
    end
    for (group_key, signatures) in signatures_by_group
        length(signatures) == 1 || error(
            "Paired system flexibility requirements must use the same next_timestamp " *
            "and requirement_source for timestamp=$(group_key[1]), poi_id=$(group_key[7]).",
        )
    end
    return requirements
end

"""
    calculate_system_flexibility_margin(supplies, requirements)

将同一时段、算例、运行口径、POI 和方向的系统灵活性供给与需求一一配对，
计算裕度、缺额和充足率。每个分组必须同时包含 `up`、`down` 两个方向；供给
和需求的分组必须完全一致。需求为零时充足率返回 `nothing`。
"""
function calculate_system_flexibility_margin(
    raw_supplies::AbstractVector,
    raw_requirements::AbstractVector,
)
    all(item -> item isa SystemFlexibilitySupplyResult, raw_supplies) || throw(
        ArgumentError("supplies must contain only SystemFlexibilitySupplyResult values."),
    )
    all(item -> item isa SystemFlexibilityRequirementResult, raw_requirements) || throw(
        ArgumentError(
            "requirements must contain only SystemFlexibilityRequirementResult values.",
        ),
    )

    supplies = SystemFlexibilitySupplyResult[item for item in raw_supplies]
    requirements = SystemFlexibilityRequirementResult[item for item in raw_requirements]
    isempty(supplies) && isempty(requirements) && return SystemFlexibilityMarginResult[]

    supply_by_key = _index_system_flexibility_margin_inputs(supplies, "supply")
    requirement_by_key = _index_system_flexibility_margin_inputs(
        requirements,
        "requirement",
    )
    _validate_system_flexibility_requirement_pairs!(requirements)

    supply_keys = Set(keys(supply_by_key))
    requirement_keys = Set(keys(requirement_by_key))
    supply_keys == requirement_keys || error(
        "System flexibility supply and requirement groups must match exactly; " *
        "unmatched supplies=$(length(setdiff(supply_keys, requirement_keys))), " *
        "unmatched requirements=$(length(setdiff(requirement_keys, supply_keys))).",
    )

    margins = SystemFlexibilityMarginResult[
        SystemFlexibilityMarginResult(supply_by_key[key], requirement_by_key[key])
        for key in supply_keys
    ]
    direction_order = Dict(FLEXIBILITY_UP => 1, FLEXIBILITY_DOWN => 2)
    sort!(
        margins;
        by=result -> (
            time_label_to_minutes(result.supply_result.timestamp),
            result.supply_result.time_step,
            result.supply_result.case_id,
            result.supply_result.application_type,
            result.supply_result.operation_mode,
            result.supply_result.boundary_condition,
            something(result.supply_result.poi_id, ""),
            direction_order[result.supply_result.direction],
        ),
    )
    return margins
end

function _system_flexibility_margin_summary_group_key(result)
    supply = result.supply_result
    requirement = result.requirement_result
    return (
        supply.time_step,
        supply.case_id,
        supply.application_type,
        supply.operation_mode,
        supply.boundary_condition,
        supply.poi_id,
        requirement.requirement_source,
    )
end

function _index_system_flexibility_margin_summary_periods(group_results)
    results_by_timestamp = Dict{String,Dict{String,SystemFlexibilityMarginResult}}()
    for result in group_results
        timestamp = result.supply_result.timestamp
        direction = result.supply_result.direction
        directions = get!(
            results_by_timestamp,
            timestamp,
            Dict{String,SystemFlexibilityMarginResult}(),
        )
        haskey(directions, direction) && error(
            "Duplicate system flexibility margin for timestamp=$(timestamp), " *
            "poi_id=$(result.supply_result.poi_id), direction=$(direction).",
        )
        directions[direction] = result
    end

    required_directions = Set(FLEXIBILITY_DIRECTIONS)
    for (timestamp, directions) in results_by_timestamp
        Set(keys(directions)) == required_directions || error(
            "System flexibility margin summary requires both up and down directions " *
            "for timestamp=$(timestamp).",
        )
        next_timestamps = Set(
            result.requirement_result.next_timestamp for result in values(directions)
        )
        length(next_timestamps) == 1 || error(
            "Up and down margin results must use the same next_timestamp for " *
            "timestamp=$(timestamp).",
        )
    end

    timestamps = sort(collect(keys(results_by_timestamp)); by=time_label_to_minutes)
    first_result = first(values(results_by_timestamp[first(timestamps)]))
    step_minutes = time_str_to_minutes(first_result.supply_result.time_step)
    for (index, timestamp) in enumerate(timestamps)
        directions = results_by_timestamp[timestamp]
        next_timestamp = first(values(directions)).requirement_result.next_timestamp
        expected_next_minutes = time_label_to_minutes(timestamp) + step_minutes
        time_label_to_minutes(next_timestamp) == expected_next_minutes || error(
            "System flexibility margin interval must match time_step for " *
            "timestamp=$(timestamp); expected next timestamp " *
            "$(minutes_to_time_label(expected_next_minutes)), got $(next_timestamp).",
        )
        if index > 1
            previous_timestamp = timestamps[index - 1]
            expected_timestamp_minutes =
                time_label_to_minutes(previous_timestamp) + step_minutes
            time_label_to_minutes(timestamp) == expected_timestamp_minutes || error(
                "System flexibility margin summary requires continuous periods; " *
                "expected $(minutes_to_time_label(expected_timestamp_minutes)), " *
                "got $(timestamp).",
            )
        end
    end
    return timestamps, results_by_timestamp
end

"""
    summarize_system_flexibility_margin(margins)

按时间步长、算例、应用类型、运行模式、网络边界、POI 和需求来源汇总连续的
全时域裕度结果。每个分组按方向输出最小裕度、最大缺额、缺额电量和单方向
达标时段比例，并同时记录上下调均达标的时段比例。
"""
function summarize_system_flexibility_margin(raw_margins::AbstractVector)
    all(item -> item isa SystemFlexibilityMarginResult, raw_margins) || throw(
        ArgumentError(
            "margins must contain only SystemFlexibilityMarginResult values.",
        ),
    )
    margins = SystemFlexibilityMarginResult[item for item in raw_margins]
    isempty(margins) && return SystemFlexibilityMarginSummaryResult[]

    grouped_results = Dict{Any,Vector{SystemFlexibilityMarginResult}}()
    for result in margins
        push!(
            get!(
                grouped_results,
                _system_flexibility_margin_summary_group_key(result),
                SystemFlexibilityMarginResult[],
            ),
            result,
        )
    end

    summaries = SystemFlexibilityMarginSummaryResult[]
    for (_, group_results) in grouped_results
        timestamps, results_by_timestamp =
            _index_system_flexibility_margin_summary_periods(group_results)
        representative = results_by_timestamp[first(timestamps)][FLEXIBILITY_UP]
        supply = representative.supply_result
        requirement = representative.requirement_result
        period_count = length(timestamps)
        bidirectional_adequate_period_count = count(
            timestamp -> all(
                direction -> results_by_timestamp[timestamp][direction].is_adequate,
                FLEXIBILITY_DIRECTIONS,
            ),
            timestamps,
        )
        end_timestamp = results_by_timestamp[last(timestamps)][FLEXIBILITY_UP].requirement_result.next_timestamp
        time_step_hours = time_str_to_minutes(supply.time_step) / 60.0

        for direction in FLEXIBILITY_DIRECTIONS
            directional_results = [
                results_by_timestamp[timestamp][direction] for timestamp in timestamps
            ]
            margins_by_period = [result.margin for result in directional_results]
            deficits_by_period = [result.deficit for result in directional_results]
            minimum_margin, minimum_index = findmin(margins_by_period)
            maximum_deficit, maximum_index = findmax(deficits_by_period)
            maximum_deficit_timestamp = maximum_deficit > 0.0 ?
                timestamps[maximum_index] : nothing
            adequate_period_count = count(result -> result.is_adequate, directional_results)

            push!(
                summaries,
                SystemFlexibilityMarginSummaryResult(
                    first(timestamps),
                    end_timestamp,
                    supply.time_step,
                    supply.case_id,
                    supply.application_type,
                    supply.operation_mode,
                    supply.boundary_condition,
                    supply.poi_id,
                    direction,
                    requirement.requirement_source,
                    period_count,
                    adequate_period_count,
                    bidirectional_adequate_period_count,
                    minimum_margin,
                    timestamps[minimum_index],
                    maximum_deficit,
                    maximum_deficit_timestamp,
                    sum(deficits_by_period) * time_step_hours,
                ),
            )
        end
    end

    direction_order = Dict(FLEXIBILITY_UP => 1, FLEXIBILITY_DOWN => 2)
    sort!(
        summaries;
        by=result -> (
            result.case_id,
            result.application_type,
            result.operation_mode,
            result.boundary_condition,
            something(result.poi_id, ""),
            result.time_step,
            result.requirement_source,
            time_label_to_minutes(result.start_timestamp),
            direction_order[result.direction],
        ),
    )
    return summaries
end
