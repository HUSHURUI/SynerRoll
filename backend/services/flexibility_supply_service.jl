# flexibility_supply_service.jl — 系统灵活性供给聚合与 POI 截断

const SYSTEM_FLEXIBILITY_BOUNDARY_DEVICE_TYPE = "GRID"

function _system_flexibility_group_key(result::ComponentFlexibilityResult)
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

function _system_flexibility_device_key(result::ComponentFlexibilityResult)
    return (
        result.timestamp,
        result.time_step,
        result.case_id,
        result.application_type,
        result.operation_mode,
        result.boundary_condition,
        result.poi_id,
        result.device_type,
        result.device_id,
    )
end

function _validate_system_flexibility_device_pairs!(
    results::Vector{ComponentFlexibilityResult},
)
    directions_by_device = Dict{Any,Set{String}}()

    for result in results
        device_key = _system_flexibility_device_key(result)
        directions = get!(directions_by_device, device_key, Set{String}())
        result.direction in directions && error(
            "Duplicate component flexibility result for device " *
            "$(result.device_type)/$(result.device_id), direction=$(result.direction), " *
            "timestamp=$(result.timestamp), poi_id=$(result.poi_id).",
        )
        push!(directions, result.direction)
    end

    required_directions = Set(FLEXIBILITY_DIRECTIONS)
    for (device_key, directions) in directions_by_device
        directions == required_directions || error(
            "Component flexibility results must contain both up and down directions for " *
            "device $(device_key[8])/$(device_key[9]), timestamp=$(device_key[1]), " *
            "poi_id=$(device_key[7]).",
        )
    end

    return results
end

function _system_flexibility_binding_constraint(
    direction::String,
    internal_flexibility_sum::Float64,
    poi_remaining_space::Float64,
)
    internal_flexibility_sum <= poi_remaining_space + 1e-9 && return "internal_devices"
    return direction == FLEXIBILITY_UP ? "poi_upper_limit" : "poi_lower_limit"
end

function _allocate_device_flexibility_contributions(
    internal_results::Vector{ComponentFlexibilityResult},
    internal_flexibility_sum::Float64,
    system_supply::Float64,
)
    allocation_ratio = internal_flexibility_sum > 0.0 ?
        system_supply / internal_flexibility_sum : 0.0
    return DeviceFlexibilityContribution[
        DeviceFlexibilityContribution(
            result,
            result.device_flexibility * allocation_ratio,
        )
        for result in internal_results
    ]
end

"""
    aggregate_system_flexibility_supply(results;
        boundary_device_type=SYSTEM_FLEXIBILITY_BOUNDARY_DEVICE_TYPE)

按时间、算例、运行口径、POI 和方向聚合单设备灵活性结果。首版要求每个分组
恰好包含一个 `GRID` 边界结果：内部设备灵活性先求和，再与同方向 POI 剩余
交换空间取较小值，并按设备可用灵活性比例分配贡献。

本函数实现单母线、单 POI、无内部网络约束的首版供给口径，不执行全约束
双向重优化。
"""
function aggregate_system_flexibility_supply(
    raw_results::AbstractVector;
    boundary_device_type::AbstractString=SYSTEM_FLEXIBILITY_BOUNDARY_DEVICE_TYPE,
)
    all(item -> item isa ComponentFlexibilityResult, raw_results) ||
        throw(ArgumentError("results must contain only ComponentFlexibilityResult values."))
    isempty(strip(boundary_device_type)) &&
        throw(ArgumentError("boundary_device_type cannot be empty."))

    results = ComponentFlexibilityResult[item for item in raw_results]
    isempty(results) && return SystemFlexibilitySupplyResult[]
    _validate_system_flexibility_device_pairs!(results)

    grouped_results = Dict{Any,Vector{ComponentFlexibilityResult}}()
    for result in results
        push!(
            get!(
                grouped_results,
                _system_flexibility_group_key(result),
                ComponentFlexibilityResult[],
            ),
            result,
        )
    end

    boundary_type = String(boundary_device_type)
    supplies = SystemFlexibilitySupplyResult[]
    for (group_key, group_results) in grouped_results
        internal_results = sort(
            [item for item in group_results if item.device_type != boundary_type];
            by=item -> (item.device_type, item.device_id),
        )
        boundary_results = [
            item for item in group_results if item.device_type == boundary_type
        ]
        length(boundary_results) == 1 || error(
            "System flexibility supply requires exactly one $(boundary_type) boundary " *
            "result per timestamp, POI and direction; got $(length(boundary_results)) " *
            "for timestamp=$(group_key[1]), poi_id=$(group_key[7]), " *
            "direction=$(group_key[8]).",
        )

        boundary_result = only(boundary_results)
        internal_flexibility_sum = sum(
            item.device_flexibility for item in internal_results;
            init=0.0,
        )
        poi_remaining_space = boundary_result.device_flexibility
        system_supply = min(internal_flexibility_sum, poi_remaining_space)
        device_contributions = _allocate_device_flexibility_contributions(
            internal_results,
            internal_flexibility_sum,
            system_supply,
        )

        push!(
            supplies,
            SystemFlexibilitySupplyResult(
                group_key[1],
                group_key[2],
                group_key[3],
                group_key[4],
                group_key[5],
                group_key[6],
                group_key[7],
                group_key[8],
                internal_flexibility_sum,
                poi_remaining_space,
                system_supply,
                _system_flexibility_binding_constraint(
                    group_key[8],
                    internal_flexibility_sum,
                    poi_remaining_space,
                ),
                device_contributions,
                boundary_result,
            ),
        )
    end

    direction_order = Dict(FLEXIBILITY_UP => 1, FLEXIBILITY_DOWN => 2)
    sort!(
        supplies;
        by=result -> (
            time_label_to_minutes(result.timestamp),
            result.time_step,
            result.case_id,
            result.application_type,
            result.operation_mode,
            result.boundary_condition,
            something(result.poi_id, ""),
            direction_order[result.direction],
        ),
    )
    return supplies
end

"""
    aggregate_islanded_system_flexibility_supply(results)

按时间和方向聚合离网系统的内部设备灵活性。离网系统没有 GRID/POI 外部交换
边界，因此系统供给等于内部设备灵活性合计，设备贡献等于各自可用灵活性。
"""
function aggregate_islanded_system_flexibility_supply(raw_results::AbstractVector)
    all(item -> item isa ComponentFlexibilityResult, raw_results) ||
        throw(ArgumentError("results must contain only ComponentFlexibilityResult values."))

    results = ComponentFlexibilityResult[item for item in raw_results]
    isempty(results) && return SystemFlexibilitySupplyResult[]
    any(item -> item.device_type == SYSTEM_FLEXIBILITY_BOUNDARY_DEVICE_TYPE, results) &&
        throw(ArgumentError("Islanded flexibility results cannot contain GRID devices."))
    any(item -> item.poi_id !== nothing, results) &&
        throw(ArgumentError("Islanded flexibility results cannot contain a POI id."))
    _validate_system_flexibility_device_pairs!(results)

    grouped_results = Dict{Any,Vector{ComponentFlexibilityResult}}()
    for result in results
        push!(
            get!(
                grouped_results,
                _system_flexibility_group_key(result),
                ComponentFlexibilityResult[],
            ),
            result,
        )
    end

    supplies = SystemFlexibilitySupplyResult[]
    for (group_key, group_results) in grouped_results
        internal_results = sort(
            group_results;
            by=item -> (item.device_type, item.device_id),
        )
        internal_flexibility_sum = sum(
            item.device_flexibility for item in internal_results;
            init=0.0,
        )
        device_contributions = [
            DeviceFlexibilityContribution(item, item.device_flexibility)
            for item in internal_results
        ]
        push!(
            supplies,
            SystemFlexibilitySupplyResult(
                group_key[1],
                group_key[2],
                group_key[3],
                group_key[4],
                group_key[5],
                "islanded_local_balance",
                nothing,
                group_key[8],
                internal_flexibility_sum,
                nothing,
                internal_flexibility_sum,
                "internal_devices",
                device_contributions,
                nothing,
            ),
        )
    end

    direction_order = Dict(FLEXIBILITY_UP => 1, FLEXIBILITY_DOWN => 2)
    sort!(
        supplies;
        by=result -> (
            time_label_to_minutes(result.timestamp),
            result.time_step,
            result.case_id,
            result.application_type,
            result.operation_mode,
            result.boundary_condition,
            direction_order[result.direction],
        ),
    )
    return supplies
end
