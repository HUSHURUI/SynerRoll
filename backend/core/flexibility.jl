const FLEXIBILITY_UP = "up"
const FLEXIBILITY_DOWN = "down"
const FLEXIBILITY_DIRECTIONS = (FLEXIBILITY_UP, FLEXIBILITY_DOWN)

"""
    ComponentFlexibilityContext

单组件灵活性计算的统一输入上下文。

`time_step` 是当前模型的时段长度（例如 `"1h"`、`"15m"`），即说明文档中的
`Δt`。`operating_point` 保存当前时段的基准调度出力、状态量以及组件计算所需的
其他基准值；具体键由各类组件的灵活性实现约定。
"""
struct ComponentFlexibilityContext
    timestamp::String
    time_step::String
    case_id::String
    application_type::String
    operation_mode::String
    boundary_condition::String
    poi_id::Union{Nothing,String}
    operating_point::StringAnyDict
end

function _require_flexibility_text(field_name::String, value::String)
    isempty(strip(value)) && throw(ArgumentError("$(field_name) cannot be empty."))
    return value
end

function ComponentFlexibilityContext(;
    timestamp::String,
    time_step::String,
    case_id::String,
    application_type::String,
    operation_mode::String,
    boundary_condition::String,
    poi_id::Union{Nothing,String}=nothing,
    operating_point::StringAnyDict=StringAnyDict(),
)
    _require_flexibility_text("timestamp", timestamp)
    _require_flexibility_text("time_step", time_step)
    _require_flexibility_text("case_id", case_id)
    _require_flexibility_text("application_type", application_type)
    _require_flexibility_text("operation_mode", operation_mode)
    _require_flexibility_text("boundary_condition", boundary_condition)
    poi_id === nothing || _require_flexibility_text("poi_id", poi_id)

    # 使用项目现有的时长解析规则，同时确保 Δt 为正。
    time_str_to_minutes(time_step) > 0 || throw(ArgumentError("time_step must be positive."))

    return ComponentFlexibilityContext(
        timestamp,
        time_step,
        case_id,
        application_type,
        operation_mode,
        boundary_condition,
        poi_id,
        deepcopy(operating_point),
    )
end

"""返回说明文档中的模型时段长度 `Δt`，单位为小时。"""
time_step_hours(context::ComponentFlexibilityContext) =
    time_str_to_minutes(context.time_step) / 60.0

"""
    ComponentFlexibilityResult

单设备、单时段、单方向的灵活性结果。`device_flexibility` 的单位统一为 kW；
`direction` 只允许 `"up"` 或 `"down"`，方向均从系统净注入角度定义。
`baseline_poi_power` 和 `poi_power_limit` 仅由 `GRID` 结果使用，分别记录基准
并网功率和当前方向对应的接口功率限值，单位均为 kW。
"""
struct ComponentFlexibilityResult
    timestamp::String
    time_step::String
    case_id::String
    application_type::String
    operation_mode::String
    boundary_condition::String
    poi_id::Union{Nothing,String}
    direction::String
    device_id::String
    device_type::String
    device_flexibility::Float64
    binding_constraint::Union{Nothing,String}
    baseline_poi_power::Union{Nothing,Float64}
    poi_power_limit::Union{Nothing,Float64}

    function ComponentFlexibilityResult(
        timestamp::String,
        time_step::String,
        case_id::String,
        application_type::String,
        operation_mode::String,
        boundary_condition::String,
        poi_id::Union{Nothing,String},
        direction::String,
        device_id::String,
        device_type::String,
        device_flexibility::Real,
        binding_constraint::Union{Nothing,String},
        baseline_poi_power::Union{Nothing,Real}=nothing,
        poi_power_limit::Union{Nothing,Real}=nothing,
    )
        direction in FLEXIBILITY_DIRECTIONS ||
            throw(ArgumentError("direction must be \"up\" or \"down\", got $(direction)."))
        _require_flexibility_text("device_id", device_id)
        _require_flexibility_text("device_type", device_type)

        value = Float64(device_flexibility)
        isfinite(value) || throw(ArgumentError("device_flexibility must be finite."))
        value >= 0.0 || throw(ArgumentError("device_flexibility must be non-negative."))

        (baseline_poi_power === nothing) == (poi_power_limit === nothing) || throw(
            ArgumentError(
                "baseline_poi_power and poi_power_limit must be provided together.",
            ),
        )
        baseline_value = baseline_poi_power === nothing ?
            nothing : Float64(baseline_poi_power)
        limit_value = poi_power_limit === nothing ? nothing : Float64(poi_power_limit)
        baseline_value === nothing || isfinite(baseline_value) ||
            throw(ArgumentError("baseline_poi_power must be finite."))
        limit_value === nothing || isfinite(limit_value) ||
            throw(ArgumentError("poi_power_limit must be finite."))

        return new(
            timestamp,
            time_step,
            case_id,
            application_type,
            operation_mode,
            boundary_condition,
            poi_id,
            direction,
            device_id,
            device_type,
            value,
            binding_constraint,
            baseline_value,
            limit_value,
        )
    end
end

function ComponentFlexibilityResult(
    context::ComponentFlexibilityContext,
    component::AbstractComponent;
    direction::String,
    device_flexibility::Real,
    binding_constraint::Union{Nothing,String}=nothing,
    baseline_poi_power::Union{Nothing,Real}=nothing,
    poi_power_limit::Union{Nothing,Real}=nothing,
)
    return ComponentFlexibilityResult(
        context.timestamp,
        context.time_step,
        context.case_id,
        context.application_type,
        context.operation_mode,
        context.boundary_condition,
        context.poi_id,
        direction,
        component_code(component),
        component_type(component),
        device_flexibility,
        binding_constraint,
        baseline_poi_power,
        poi_power_limit,
    )
end

"""将设备灵活性结果转换为与说明文档输出字段一致的字典。"""
function component_flexibility_result_dict(result::ComponentFlexibilityResult)
    return StringAnyDict(
        "timestamp" => result.timestamp,
        "time_step" => result.time_step,
        "case_id" => result.case_id,
        "application_type" => result.application_type,
        "operation_mode" => result.operation_mode,
        "boundary_condition" => result.boundary_condition,
        "poi_id" => result.poi_id,
        "direction" => result.direction,
        "device_id" => result.device_id,
        "device_type" => result.device_type,
        "device_flexibility" => result.device_flexibility,
        "binding_constraint" => result.binding_constraint,
        "baseline_poi_power" => result.baseline_poi_power,
        "poi_power_limit" => result.poi_power_limit,
    )
end

"""
    calculate_component_flexibility(component, context)

统一的组件灵活性计算入口。每个组件实现
`calculate_component_flexibility_impl(::ConcreteComponent, context)`，并且必须返回
当前时段的 `up`、`down` 两条 `ComponentFlexibilityResult`。
"""
function calculate_component_flexibility(
    component::AbstractComponent,
    context::ComponentFlexibilityContext,
)
    raw_results = calculate_component_flexibility_impl(component, context)
    raw_results isa AbstractVector ||
        error("Component flexibility implementation must return a vector of results.")
    all(result -> result isa ComponentFlexibilityResult, raw_results) ||
        error("Component flexibility implementation returned an invalid result type.")

    results = ComponentFlexibilityResult[result for result in raw_results]
    _validate_component_flexibility_results!(results, component, context)
    return results
end

function calculate_component_flexibility_impl(
    component::AbstractComponent,
    ::ComponentFlexibilityContext,
)
    error(
        "Component flexibility is not implemented for type " *
        "$(component_type(component)) (device $(component_code(component))).",
    )
end

function _validate_component_flexibility_results!(
    results::Vector{ComponentFlexibilityResult},
    component::AbstractComponent,
    context::ComponentFlexibilityContext,
)
    length(results) == 2 ||
        error("Component flexibility must return exactly two directional results.")

    directions = Set(result.direction for result in results)
    directions == Set(FLEXIBILITY_DIRECTIONS) ||
        error("Component flexibility must return one up result and one down result.")

    for result in results
        result.timestamp == context.timestamp || error("Result timestamp does not match context.")
        result.time_step == context.time_step || error("Result time_step does not match context.")
        result.case_id == context.case_id || error("Result case_id does not match context.")
        result.application_type == context.application_type ||
            error("Result application_type does not match context.")
        result.operation_mode == context.operation_mode ||
            error("Result operation_mode does not match context.")
        result.boundary_condition == context.boundary_condition ||
            error("Result boundary_condition does not match context.")
        result.poi_id == context.poi_id || error("Result poi_id does not match context.")
        result.device_id == component_code(component) ||
            error("Result device_id does not match component code.")
        result.device_type == component_type(component) ||
            error("Result device_type does not match component type.")
    end

    return results
end
