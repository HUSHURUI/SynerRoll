# system_flexibility.jl — 系统灵活性供给、需求与裕度公共结果类型

"""
    DeviceFlexibilityContribution

单设备灵活性及其经过 POI 截断后的可归属贡献。

`device_contribution` 用于首版结果展示和裕度核算，不表示新的调度指令。
"""
struct DeviceFlexibilityContribution
    result::ComponentFlexibilityResult
    device_contribution::Float64

    function DeviceFlexibilityContribution(
        result::ComponentFlexibilityResult,
        device_contribution::Real,
    )
        value = Float64(device_contribution)
        isfinite(value) || throw(ArgumentError("device_contribution must be finite."))
        value >= 0.0 || throw(ArgumentError("device_contribution must be non-negative."))
        value <= result.device_flexibility + 1e-9 || throw(
            ArgumentError("device_contribution cannot exceed device_flexibility."),
        )
        return new(result, min(value, result.device_flexibility))
    end
end

"""将单设备灵活性及其贡献转换为可序列化字典。"""
function device_flexibility_contribution_dict(
    contribution::DeviceFlexibilityContribution,
)
    row = component_flexibility_result_dict(contribution.result)
    row["device_contribution"] = contribution.device_contribution
    return row
end

"""
    SystemFlexibilitySupplyResult

单时段、单方向的系统灵活性供给结果。

并网时，系统供给取内部设备灵活性合计与同方向 POI 剩余交换空间的较小值；
离网时不存在 POI，系统供给等于内部设备灵活性合计。电网接口只作为外部
截断边界，不加入内部设备求和。设备贡献按设备可用灵活性比例分配。
"""
struct SystemFlexibilitySupplyResult
    timestamp::String
    time_step::String
    case_id::String
    application_type::String
    operation_mode::String
    boundary_condition::String
    poi_id::Union{Nothing,String}
    direction::String
    internal_flexibility_sum::Float64
    baseline_poi_power::Union{Nothing,Float64}
    poi_power_limit::Union{Nothing,Float64}
    poi_remaining_space::Union{Nothing,Float64}
    system_supply::Float64
    binding_constraint::String
    device_contributions::Vector{DeviceFlexibilityContribution}
    boundary_result::Union{Nothing,ComponentFlexibilityResult}

    function SystemFlexibilitySupplyResult(
        timestamp::String,
        time_step::String,
        case_id::String,
        application_type::String,
        operation_mode::String,
        boundary_condition::String,
        poi_id::Union{Nothing,String},
        direction::String,
        internal_flexibility_sum::Real,
        poi_remaining_space::Union{Nothing,Real},
        system_supply::Real,
        binding_constraint::String,
        device_contributions::Vector{DeviceFlexibilityContribution},
        boundary_result::Union{Nothing,ComponentFlexibilityResult},
    )
        _require_flexibility_text("timestamp", timestamp)
        _require_flexibility_text("time_step", time_step)
        _require_flexibility_text("case_id", case_id)
        _require_flexibility_text("application_type", application_type)
        _require_flexibility_text("operation_mode", operation_mode)
        _require_flexibility_text("boundary_condition", boundary_condition)
        poi_id === nothing || _require_flexibility_text("poi_id", poi_id)
        direction in FLEXIBILITY_DIRECTIONS ||
            throw(ArgumentError("direction must be \"up\" or \"down\", got $(direction)."))
        _require_flexibility_text("binding_constraint", binding_constraint)

        internal_value = Float64(internal_flexibility_sum)
        poi_value = poi_remaining_space === nothing ? nothing : Float64(poi_remaining_space)
        supply_value = Float64(system_supply)
        isfinite(internal_value) && isfinite(supply_value) &&
            (poi_value === nothing || isfinite(poi_value)) ||
            throw(ArgumentError("System flexibility supply values must be finite."))
        internal_value >= 0.0 && supply_value >= 0.0 &&
            (poi_value === nothing || poi_value >= 0.0) ||
            throw(ArgumentError("System flexibility supply values must be non-negative."))
        (boundary_result === nothing) == (poi_value === nothing) || throw(
            ArgumentError(
                "poi_remaining_space and boundary_result must both be absent for islanded results.",
            ),
        )
        expected_supply = poi_value === nothing ? internal_value : min(internal_value, poi_value)
        isapprox(supply_value, expected_supply; atol=1e-9, rtol=1e-12) || throw(
            ArgumentError(
                "system_supply must match the active network-boundary rule.",
            ),
        )

        contribution_sum = sum(
            item.device_contribution for item in device_contributions;
            init=0.0,
        )
        isapprox(contribution_sum, supply_value; atol=1e-8, rtol=1e-10) || throw(
            ArgumentError("Device contributions must sum to system_supply."),
        )

        return new(
            timestamp,
            time_step,
            case_id,
            application_type,
            operation_mode,
            boundary_condition,
            poi_id,
            direction,
            internal_value,
            boundary_result === nothing ? nothing : boundary_result.baseline_poi_power,
            boundary_result === nothing ? nothing : boundary_result.poi_power_limit,
            poi_value,
            expected_supply,
            binding_constraint,
            copy(device_contributions),
            boundary_result,
        )
    end
end

"""将系统灵活性供给及设备贡献明细转换为可序列化字典。"""
function system_flexibility_supply_result_dict(result::SystemFlexibilitySupplyResult)
    return StringAnyDict(
        "timestamp" => result.timestamp,
        "time_step" => result.time_step,
        "case_id" => result.case_id,
        "application_type" => result.application_type,
        "operation_mode" => result.operation_mode,
        "boundary_condition" => result.boundary_condition,
        "poi_id" => result.poi_id,
        "direction" => result.direction,
        "internal_flexibility_sum" => result.internal_flexibility_sum,
        "baseline_poi_power" => result.baseline_poi_power,
        "poi_power_limit" => result.poi_power_limit,
        "poi_remaining_space" => result.poi_remaining_space,
        "system_supply" => result.system_supply,
        "binding_constraint" => result.binding_constraint,
        "internal_device_count" => length(result.device_contributions),
        "device_results" => [
            device_flexibility_contribution_dict(item)
            for item in result.device_contributions
        ],
        "network_mode" => result.boundary_result === nothing ? "islanded" : "grid_connected",
        "boundary_result" => result.boundary_result === nothing ?
            nothing : component_flexibility_result_dict(result.boundary_result),
    )
end

const FLEXIBILITY_REQUIREMENT_NET_LOAD = "net_load_change"
const FLEXIBILITY_REQUIREMENT_AGC_SCHEDULE = "agc_or_schedule"
const FLEXIBILITY_REQUIREMENT_USER_DEFINED = "user_defined"
const FLEXIBILITY_REQUIREMENT_SOURCES = (
    FLEXIBILITY_REQUIREMENT_NET_LOAD,
    FLEXIBILITY_REQUIREMENT_AGC_SCHEDULE,
    FLEXIBILITY_REQUIREMENT_USER_DEFINED,
)

"""
    SystemFlexibilityRequirementContext

单个相邻时段区间的系统灵活性需求上下文。`timestamp` 表示区间起点，
`next_timestamp` 表示需求目标所在的下一时段。
"""
struct SystemFlexibilityRequirementContext
    timestamp::String
    next_timestamp::String
    time_step::String
    case_id::String
    application_type::String
    operation_mode::String
    boundary_condition::String
    poi_id::Union{Nothing,String}
end

function SystemFlexibilityRequirementContext(;
    timestamp::String,
    next_timestamp::String,
    time_step::String,
    case_id::String,
    application_type::String,
    operation_mode::String,
    boundary_condition::String,
    poi_id::Union{Nothing,String}=nothing,
)
    _require_flexibility_text("timestamp", timestamp)
    _require_flexibility_text("next_timestamp", next_timestamp)
    timestamp != next_timestamp ||
        throw(ArgumentError("next_timestamp must differ from timestamp."))
    _require_flexibility_text("time_step", time_step)
    time_str_to_minutes(time_step) > 0 ||
        throw(ArgumentError("time_step must be positive."))
    _require_flexibility_text("case_id", case_id)
    _require_flexibility_text("application_type", application_type)
    _require_flexibility_text("operation_mode", operation_mode)
    _require_flexibility_text("boundary_condition", boundary_condition)
    poi_id === nothing || _require_flexibility_text("poi_id", poi_id)

    return SystemFlexibilityRequirementContext(
        timestamp,
        next_timestamp,
        time_step,
        case_id,
        application_type,
        operation_mode,
        boundary_condition,
        poi_id,
    )
end

abstract type AbstractSystemFlexibilityRequirementInput end

"""净负荷变化需求输入；柔性负荷、风电和光伏字段均为同类设备的功率合计。"""
struct NetLoadRequirementInput <: AbstractSystemFlexibilityRequirementInput
    current_rigid_load_kw::Float64
    next_rigid_load_kw::Float64
    current_flexible_load_kw::Float64
    next_flexible_load_kw::Float64
    current_wind_available_power_kw::Float64
    next_wind_available_power_kw::Float64
    current_pv_available_power_kw::Float64
    next_pv_available_power_kw::Float64
end

"""AGC/计划功率需求输入；两个功率均对应 `next_timestamp`。"""
struct AgcScheduleRequirementInput <: AbstractSystemFlexibilityRequirementInput
    baseline_poi_power_kw::Float64
    target_poi_power_kw::Float64
end

"""用户直接给定的非负上、下调需求。"""
struct UserDefinedRequirementInput <: AbstractSystemFlexibilityRequirementInput
    upward_requirement_kw::Float64
    downward_requirement_kw::Float64
end

function _require_finite_requirement_value(
    field_name::String,
    value::Real;
    nonnegative::Bool=false,
)
    result = Float64(value)
    isfinite(result) || throw(ArgumentError("$(field_name) must be finite."))
    nonnegative && result < 0.0 &&
        throw(ArgumentError("$(field_name) must be non-negative."))
    return result
end

function NetLoadRequirementInput(;
    current_rigid_load_kw::Real,
    next_rigid_load_kw::Real,
    current_flexible_load_kw::Real=0.0,
    next_flexible_load_kw::Real=0.0,
    current_wind_available_power_kw::Real=0.0,
    next_wind_available_power_kw::Real=0.0,
    current_pv_available_power_kw::Real=0.0,
    next_pv_available_power_kw::Real=0.0,
)
    values = (
        _require_finite_requirement_value(
            "current_rigid_load_kw",
            current_rigid_load_kw;
            nonnegative=true,
        ),
        _require_finite_requirement_value(
            "next_rigid_load_kw",
            next_rigid_load_kw;
            nonnegative=true,
        ),
        _require_finite_requirement_value(
            "current_flexible_load_kw",
            current_flexible_load_kw;
            nonnegative=true,
        ),
        _require_finite_requirement_value(
            "next_flexible_load_kw",
            next_flexible_load_kw;
            nonnegative=true,
        ),
        _require_finite_requirement_value(
            "current_wind_available_power_kw",
            current_wind_available_power_kw;
            nonnegative=true,
        ),
        _require_finite_requirement_value(
            "next_wind_available_power_kw",
            next_wind_available_power_kw;
            nonnegative=true,
        ),
        _require_finite_requirement_value(
            "current_pv_available_power_kw",
            current_pv_available_power_kw;
            nonnegative=true,
        ),
        _require_finite_requirement_value(
            "next_pv_available_power_kw",
            next_pv_available_power_kw;
            nonnegative=true,
        ),
    )
    return NetLoadRequirementInput(values...)
end

function AgcScheduleRequirementInput(;
    baseline_poi_power_kw::Real,
    target_poi_power_kw::Real,
)
    return AgcScheduleRequirementInput(
        _require_finite_requirement_value(
            "baseline_poi_power_kw",
            baseline_poi_power_kw,
        ),
        _require_finite_requirement_value("target_poi_power_kw", target_poi_power_kw),
    )
end

function UserDefinedRequirementInput(;
    upward_requirement_kw::Real,
    downward_requirement_kw::Real,
)
    return UserDefinedRequirementInput(
        _require_finite_requirement_value(
            "upward_requirement_kw",
            upward_requirement_kw;
            nonnegative=true,
        ),
        _require_finite_requirement_value(
            "downward_requirement_kw",
            downward_requirement_kw;
            nonnegative=true,
        ),
    )
end

"""
    SystemFlexibilityRequirementResult

单时段、单方向的系统灵活性需求，单位为 kW。`reference_power` 和
`target_power` 保存该需求来源的两个比较值；用户直接给定需求时二者为
`nothing`。
"""
struct SystemFlexibilityRequirementResult
    timestamp::String
    next_timestamp::String
    time_step::String
    case_id::String
    application_type::String
    operation_mode::String
    boundary_condition::String
    poi_id::Union{Nothing,String}
    direction::String
    requirement_source::String
    requirement::Float64
    reference_power::Union{Nothing,Float64}
    target_power::Union{Nothing,Float64}

    function SystemFlexibilityRequirementResult(
        context::SystemFlexibilityRequirementContext;
        direction::String,
        requirement_source::String,
        requirement::Real,
        reference_power::Union{Nothing,Real}=nothing,
        target_power::Union{Nothing,Real}=nothing,
    )
        direction in FLEXIBILITY_DIRECTIONS ||
            throw(ArgumentError("direction must be \"up\" or \"down\", got $(direction)."))
        requirement_source in FLEXIBILITY_REQUIREMENT_SOURCES || throw(
            ArgumentError("Unsupported requirement_source $(requirement_source)."),
        )
        requirement_value = _require_finite_requirement_value(
            "requirement",
            requirement;
            nonnegative=true,
        )
        (reference_power === nothing) == (target_power === nothing) || throw(
            ArgumentError("reference_power and target_power must be provided together."),
        )
        reference_value = reference_power === nothing ?
            nothing : _require_finite_requirement_value("reference_power", reference_power)
        target_value = target_power === nothing ?
            nothing : _require_finite_requirement_value("target_power", target_power)

        return new(
            context.timestamp,
            context.next_timestamp,
            context.time_step,
            context.case_id,
            context.application_type,
            context.operation_mode,
            context.boundary_condition,
            context.poi_id,
            direction,
            requirement_source,
            requirement_value,
            reference_value,
            target_value,
        )
    end
end

"""将系统灵活性需求结果转换为可序列化字典。"""
function system_flexibility_requirement_result_dict(
    result::SystemFlexibilityRequirementResult,
)
    return StringAnyDict(
        "timestamp" => result.timestamp,
        "next_timestamp" => result.next_timestamp,
        "time_step" => result.time_step,
        "case_id" => result.case_id,
        "application_type" => result.application_type,
        "operation_mode" => result.operation_mode,
        "boundary_condition" => result.boundary_condition,
        "poi_id" => result.poi_id,
        "direction" => result.direction,
        "requirement_source" => result.requirement_source,
        "requirement" => result.requirement,
        "reference_power" => result.reference_power,
        "target_power" => result.target_power,
    )
end

"""
    SystemFlexibilityMarginResult

同一时段、同一方向的系统灵活性供给与需求配对结果。裕度为供给减需求；
缺额只在裕度为负时取其绝对值；需求为零时充足率为 `nothing`。
"""
struct SystemFlexibilityMarginResult
    supply_result::SystemFlexibilitySupplyResult
    requirement_result::SystemFlexibilityRequirementResult
    margin::Float64
    deficit::Float64
    adequacy_ratio::Union{Nothing,Float64}
    is_adequate::Bool

    function SystemFlexibilityMarginResult(
        supply_result::SystemFlexibilitySupplyResult,
        requirement_result::SystemFlexibilityRequirementResult,
    )
        matching_fields = (
            :timestamp,
            :time_step,
            :case_id,
            :application_type,
            :operation_mode,
            :boundary_condition,
            :poi_id,
            :direction,
        )
        for field in matching_fields
            getfield(supply_result, field) == getfield(requirement_result, field) || throw(
                ArgumentError(
                    "System flexibility supply and requirement $(field) values must match.",
                ),
            )
        end

        margin = supply_result.system_supply - requirement_result.requirement
        deficit = max(0.0, -margin)
        adequacy_ratio = iszero(requirement_result.requirement) ?
            nothing : supply_result.system_supply / requirement_result.requirement

        return new(
            supply_result,
            requirement_result,
            margin,
            deficit,
            adequacy_ratio,
            margin >= 0.0,
        )
    end
end

"""将系统灵活性裕度结果转换为包含供给、需求和充足性字段的可序列化字典。"""
function system_flexibility_margin_result_dict(result::SystemFlexibilityMarginResult)
    row = system_flexibility_supply_result_dict(result.supply_result)
    requirement_row = system_flexibility_requirement_result_dict(
        result.requirement_result,
    )
    for field in (
        "next_timestamp",
        "requirement_source",
        "requirement",
        "reference_power",
        "target_power",
    )
        row[field] = requirement_row[field]
    end
    row["margin"] = result.margin
    row["deficit"] = result.deficit
    row["adequacy_ratio"] = result.adequacy_ratio
    row["is_adequate"] = result.is_adequate
    return row
end

"""
    SystemFlexibilityMarginSummaryResult

同一算例、运行口径、POI、时间步长、需求来源和方向的全时域裕度汇总。
`deficit_energy` 的单位为 kWh；单方向与双向达标时段比例均以已校验的连续
时段数为分母。
"""
struct SystemFlexibilityMarginSummaryResult
    start_timestamp::String
    end_timestamp::String
    time_step::String
    case_id::String
    application_type::String
    operation_mode::String
    boundary_condition::String
    poi_id::Union{Nothing,String}
    direction::String
    requirement_source::String
    period_count::Int
    adequate_period_count::Int
    bidirectional_adequate_period_count::Int
    minimum_margin::Float64
    minimum_margin_timestamp::String
    maximum_deficit::Float64
    maximum_deficit_timestamp::Union{Nothing,String}
    deficit_energy::Float64
    adequate_period_ratio::Float64
    bidirectional_adequate_period_ratio::Float64

    function SystemFlexibilityMarginSummaryResult(
        start_timestamp::String,
        end_timestamp::String,
        time_step::String,
        case_id::String,
        application_type::String,
        operation_mode::String,
        boundary_condition::String,
        poi_id::Union{Nothing,String},
        direction::String,
        requirement_source::String,
        period_count::Int,
        adequate_period_count::Int,
        bidirectional_adequate_period_count::Int,
        minimum_margin::Real,
        minimum_margin_timestamp::String,
        maximum_deficit::Real,
        maximum_deficit_timestamp::Union{Nothing,String},
        deficit_energy::Real,
    )
        for (field_name, value) in (
            ("start_timestamp", start_timestamp),
            ("end_timestamp", end_timestamp),
            ("time_step", time_step),
            ("case_id", case_id),
            ("application_type", application_type),
            ("operation_mode", operation_mode),
            ("boundary_condition", boundary_condition),
            ("minimum_margin_timestamp", minimum_margin_timestamp),
        )
            _require_flexibility_text(field_name, value)
        end
        poi_id === nothing || _require_flexibility_text("poi_id", poi_id)
        time_label_to_minutes(end_timestamp) > time_label_to_minutes(start_timestamp) ||
            throw(ArgumentError("end_timestamp must be after start_timestamp."))
        time_str_to_minutes(time_step) > 0 ||
            throw(ArgumentError("time_step must be positive."))
        direction in FLEXIBILITY_DIRECTIONS ||
            throw(ArgumentError("direction must be \"up\" or \"down\"."))
        requirement_source in FLEXIBILITY_REQUIREMENT_SOURCES || throw(
            ArgumentError("Unsupported requirement_source $(requirement_source)."),
        )
        period_count > 0 || throw(ArgumentError("period_count must be positive."))
        0 <= adequate_period_count <= period_count || throw(
            ArgumentError("adequate_period_count must be between zero and period_count."),
        )
        0 <= bidirectional_adequate_period_count <= period_count || throw(
            ArgumentError(
                "bidirectional_adequate_period_count must be between zero and period_count.",
            ),
        )

        minimum_margin_value = Float64(minimum_margin)
        maximum_deficit_value = Float64(maximum_deficit)
        deficit_energy_value = Float64(deficit_energy)
        all(
            isfinite,
            (minimum_margin_value, maximum_deficit_value, deficit_energy_value),
        ) || throw(ArgumentError("System flexibility summary values must be finite."))
        maximum_deficit_value >= 0.0 ||
            throw(ArgumentError("maximum_deficit must be non-negative."))
        deficit_energy_value >= 0.0 ||
            throw(ArgumentError("deficit_energy must be non-negative."))
        expected_maximum_deficit = max(0.0, -minimum_margin_value)
        isapprox(
            maximum_deficit_value,
            expected_maximum_deficit;
            atol=1e-9,
            rtol=1e-12,
        ) || throw(
            ArgumentError("maximum_deficit must correspond to minimum_margin."),
        )
        if iszero(maximum_deficit_value)
            maximum_deficit_timestamp === nothing || throw(
                ArgumentError(
                    "maximum_deficit_timestamp must be nothing when no deficit occurs.",
                ),
            )
        else
            maximum_deficit_timestamp === nothing && throw(
                ArgumentError(
                    "maximum_deficit_timestamp is required when a deficit occurs.",
                ),
            )
            _require_flexibility_text(
                "maximum_deficit_timestamp",
                maximum_deficit_timestamp,
            )
        end

        return new(
            start_timestamp,
            end_timestamp,
            time_step,
            case_id,
            application_type,
            operation_mode,
            boundary_condition,
            poi_id,
            direction,
            requirement_source,
            period_count,
            adequate_period_count,
            bidirectional_adequate_period_count,
            minimum_margin_value,
            minimum_margin_timestamp,
            maximum_deficit_value,
            maximum_deficit_timestamp,
            deficit_energy_value,
            adequate_period_count / period_count,
            bidirectional_adequate_period_count / period_count,
        )
    end
end

"""将全时域系统灵活性裕度汇总转换为可序列化字典。"""
function system_flexibility_margin_summary_result_dict(
    result::SystemFlexibilityMarginSummaryResult,
)
    return StringAnyDict(
        "start_timestamp" => result.start_timestamp,
        "end_timestamp" => result.end_timestamp,
        "time_step" => result.time_step,
        "case_id" => result.case_id,
        "application_type" => result.application_type,
        "operation_mode" => result.operation_mode,
        "boundary_condition" => result.boundary_condition,
        "poi_id" => result.poi_id,
        "direction" => result.direction,
        "requirement_source" => result.requirement_source,
        "period_count" => result.period_count,
        "adequate_period_count" => result.adequate_period_count,
        "bidirectional_adequate_period_count" =>
            result.bidirectional_adequate_period_count,
        "minimum_margin" => result.minimum_margin,
        "minimum_margin_timestamp" => result.minimum_margin_timestamp,
        "maximum_deficit" => result.maximum_deficit,
        "maximum_deficit_timestamp" => result.maximum_deficit_timestamp,
        "deficit_energy" => result.deficit_energy,
        "adequate_period_ratio" => result.adequate_period_ratio,
        "bidirectional_adequate_period_ratio" =>
            result.bidirectional_adequate_period_ratio,
    )
end
