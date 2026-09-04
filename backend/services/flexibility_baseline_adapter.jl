# ═══════════════════════════════════════════════════════════════════════════
# flexibility_baseline_adapter.jl — 基准调度结果到组件灵活性输入的适配层
#
# 该服务只负责读取、清洗和转换已有求解结果，不重复计算设备约束。
# 求解结果沿用 ResultBinding 对应的时序标签，适配后的字段统一采用
# flexibility-interface.md 规定的 operating_point 键名和单位。
# ═══════════════════════════════════════════════════════════════════════════

const CONTROLLABLE_GENERATOR_TYPES = Set(["CP", "GP", "CHP"])
const RENEWABLE_GENERATOR_TYPES = Set(["WT", "PV"])
const ELECTRIC_STORAGE_TYPES = Set(["ES", "FS", "CS", "PS"])
const ZERO_ELECTRIC_FLEXIBILITY_TYPES = Set(["ELOAD", "HS", "HLOAD", "QLOAD"])

"""生成与 `persist_component_results!` 完全一致的组件结果时序标签。"""
function component_result_data_key(binding::ResultBinding, layer_id::String)
    isempty(strip(layer_id)) && throw(ArgumentError("layer_id cannot be empty."))
    return "$(binding.component_label)|$(binding.var_name)|$(binding.remark)#$(layer_id)"
end

function _read_persisted_baseline_value(
    db_path::String,
    data_key::String,
    timestamp::String,
)
    series = get_ts(db_path, data_key)
    if series === nothing || isempty(series.timestamps)
        return nothing
    end
    return get_value(series, timestamp)
end

"""
    read_component_baseline_result(component, db_path, layer_id, timestamp;
                                   value_reader=_read_persisted_baseline_value)

按组件的 `ResultBinding` 从已有求解结果中读取指定时刻的原始变量值。

返回值以模型变量名 `Symbol` 为键。不存在的时序先跳过，随后由
`adapt_component_baseline_result` 对该组件真正需要的字段给出明确错误。
`get_value` 的既有规则会在没有精确时间戳时使用最近的更早值。
`value_reader` 用于测试或接入其他结果存储，签名为
`(db_path, data_key, timestamp) -> Real | nothing`。
"""
function read_component_baseline_result(
    component::AbstractComponent,
    db_path::String,
    layer_id::String,
    timestamp::String;
    value_reader::Function=_read_persisted_baseline_value,
)
    isempty(strip(timestamp)) && throw(ArgumentError("timestamp cannot be empty."))
    result = Dict{Symbol,Float64}()

    for binding in component_result_bindings(component)
        data_key = component_result_data_key(binding, layer_id)
        value = value_reader(db_path, data_key, timestamp)
        value === nothing && continue
        value isa Real || error("Baseline result $(data_key) must be numeric.")

        number = Float64(value)
        isfinite(number) || error("Baseline result $(data_key) must be finite.")
        result[binding.var_name] = number
    end

    return result
end

function _component_result_variable(component::AbstractComponent, prefix::String)
    code = component_code(component)
    return isempty(code) ? Symbol(prefix) : Symbol("$(prefix)_$(code)")
end

function _baseline_result_value(
    component::AbstractComponent,
    result_values::AbstractDict,
    prefix::String;
    required::Bool=true,
)
    variable = _component_result_variable(component, prefix)
    value = if haskey(result_values, variable)
        result_values[variable]
    elseif haskey(result_values, String(variable))
        result_values[String(variable)]
    else
        nothing
    end

    if value === nothing
        required || return nothing
        error(
            "Baseline result is missing $(variable) for component " *
            "$(component_type(component))/$(component_code(component)).",
        )
    end
    value isa Real || error("Baseline result $(variable) must be numeric.")

    number = Float64(value)
    isfinite(number) || error("Baseline result $(variable) must be finite.")
    return number
end

function _nonnegative_baseline_result(
    component::AbstractComponent,
    result_values::AbstractDict,
    prefix::String,
    tolerance_kw::Float64;
    required::Bool=true,
)
    value = _baseline_result_value(component, result_values, prefix; required=required)
    value === nothing && return nothing
    value >= -tolerance_kw || error(
        "Baseline result $(_component_result_variable(component, prefix)) must be non-negative.",
    )
    return abs(value) <= tolerance_kw ? 0.0 : value
end

function _component_available(component::AbstractComponent, layer_id::Union{Nothing,String})
    layer_id === nothing && return true
    layers = component_layers(component)
    haskey(layers, layer_id) || error(
        "Component $(component_type(component))/$(component_code(component)) " *
        "does not define layer $(layer_id).",
    )
    return get(layers[layer_id], "status", "stand_alone") != "disabled"
end

function _component_ramp_constraint_on(
    component::AbstractComponent,
    layer_id::Union{Nothing,String},
    ;
    default::Bool=false,
)
    layer_id === nothing && return default
    layer_settings = layer_config(component, layer_id)
    constraints = get(layer_settings, "constraints", StringAnyDict())
    return get(constraints, "ramp_constraint_on", default)
end

function _merge_operating_point_overrides!(
    operating_point::StringAnyDict,
    overrides::AbstractDict,
)
    for (key, value) in overrides
        key isa AbstractString || throw(ArgumentError("Operating-point override keys must be strings."))
        operating_point[String(key)] = value
    end
    return operating_point
end

"""
    adapt_component_baseline_result(component, result_values;
                                    layer_id=nothing,
                                    operating_point_overrides=StringAnyDict(),
                                    numerical_tolerance_kw=1e-6)

将一台组件在一个时刻的原始求解变量转换为灵活性接口的
`operating_point`。

当前求解结果没有持久化 CP、GP、CHP 和 ET 的启停二进制变量，因此首版按
`power_kw > numerical_tolerance_kw` 推断 `is_online`。WT 优先使用已落库的
`AVAILABLE_WT`，缺失时用“实际出力 + 弃风”还原；PV 使用“实际出力 + 弃光”
还原。WT/PV/HYDRO 的 `ramp_constraint_on` 从当前时层约束配置读取。HYDRO
直接读取实际、可用和最小出力。GRID 的
`poi_power_kw` 按“上送 − 购入”合成，正值表示向电网上送。所有推断字段都可以
通过 `operating_point_overrides` 显式覆盖。
"""
function adapt_component_baseline_result(
    component::AbstractComponent,
    result_values::AbstractDict;
    layer_id::Union{Nothing,String}=nothing,
    operating_point_overrides::AbstractDict=StringAnyDict(),
    numerical_tolerance_kw::Real=1e-6,
)
    tolerance = Float64(numerical_tolerance_kw)
    isfinite(tolerance) && tolerance >= 0.0 ||
        throw(ArgumentError("numerical_tolerance_kw must be finite and non-negative."))

    component_kind = component_type(component)
    operating_point = StringAnyDict(
        "available" => _component_available(component, layer_id),
    )

    # 停用组件的统一接口会直接返回零灵活性，不应强制要求结果库中存在占位变量。
    if !operating_point["available"]
        return _merge_operating_point_overrides!(operating_point, operating_point_overrides)
    end

    if component_kind in CONTROLLABLE_GENERATOR_TYPES
        power_kw = _nonnegative_baseline_result(
            component,
            result_values,
            "E_$(component_kind)",
            tolerance,
        )
        operating_point["power_kw"] = power_kw
        operating_point["is_online"] = power_kw > tolerance
    elseif component_kind in RENEWABLE_GENERATOR_TYPES
        power_kw = _nonnegative_baseline_result(
            component,
            result_values,
            "E_$(component_kind)",
            tolerance,
        )
        curtailed_power_kw = _nonnegative_baseline_result(
            component,
            result_values,
            "E_$(component_kind)_cut",
            tolerance,
        )

        available_power_kw = if component_kind == "WT"
            recorded_available = _nonnegative_baseline_result(
                component,
                result_values,
                "AVAILABLE_WT",
                tolerance;
                required=false,
            )
            recorded_available === nothing ? power_kw + curtailed_power_kw : recorded_available
        else
            power_kw + curtailed_power_kw
        end

        # 避免求解器数值误差造成 available_power_kw 略小于实际出力。
        if available_power_kw + tolerance < power_kw
            error("Renewable available power cannot be smaller than its baseline output.")
        end
        operating_point["power_kw"] = power_kw
        operating_point["available_power_kw"] = max(power_kw, available_power_kw)
        operating_point["ramp_constraint_on"] =
            _component_ramp_constraint_on(component, layer_id)
    elseif component_kind in ELECTRIC_STORAGE_TYPES
        operating_point["stored_energy_kwh"] = _nonnegative_baseline_result(
            component,
            result_values,
            "E_$(component_kind)",
            tolerance,
        )
        operating_point["charging_power_kw"] = _nonnegative_baseline_result(
            component,
            result_values,
            "E_$(component_kind)_in",
            tolerance,
        )
        operating_point["discharging_power_kw"] = _nonnegative_baseline_result(
            component,
            result_values,
            "E_$(component_kind)_out",
            tolerance,
        )
    elseif component_kind == "ET"
        power_kw = _nonnegative_baseline_result(component, result_values, "E_ET", tolerance)
        operating_point["power_kw"] = power_kw
        operating_point["is_online"] = power_kw > tolerance
    elseif component_kind == "GRID"
        selling_power_kw = _nonnegative_baseline_result(
            component,
            result_values,
            "E_GRID_in",
            tolerance,
        )
        buying_power_kw = _nonnegative_baseline_result(
            component,
            result_values,
            "E_GRID_out",
            tolerance,
        )
        # 并网点功率：正值表示向电网上送，负值表示从电网购入。
        operating_point["poi_power_kw"] = selling_power_kw - buying_power_kw
    elseif component_kind == "HYDRO"
        power_kw = _nonnegative_baseline_result(
            component,
            result_values,
            "E_HYDRO",
            tolerance,
        )
        available_power_kw = _nonnegative_baseline_result(
            component,
            result_values,
            "AVAILABLE_HYDRO",
            tolerance,
        )
        minimum_power_kw = _nonnegative_baseline_result(
            component,
            result_values,
            "MINIMUM_HYDRO",
            tolerance,
        )
        minimum_power_kw <= available_power_kw + tolerance ||
            error("Hydro minimum power cannot exceed available power.")
        power_kw + tolerance >= minimum_power_kw ||
            error("Hydro baseline output cannot be smaller than minimum power.")
        power_kw <= available_power_kw + tolerance ||
            error("Hydro baseline output cannot exceed available power.")

        operating_point["power_kw"] = clamp(power_kw, minimum_power_kw, available_power_kw)
        operating_point["available_power_kw"] = available_power_kw
        operating_point["minimum_power_kw"] = minimum_power_kw
        operating_point["ramp_constraint_on"] =
            _component_ramp_constraint_on(component, layer_id; default=true)
    elseif component_kind in ZERO_ELECTRIC_FLEXIBILITY_TYPES
        # 这些组件的设备层电功率灵活性恒为零，无需读取基准功率或非电状态量。
    else
        error(
            "Baseline flexibility adapter is not implemented for component type " *
            "$(component_kind).",
        )
    end

    return _merge_operating_point_overrides!(operating_point, operating_point_overrides)
end

"""
    build_component_flexibility_context(component, result_values; ...)

用已读取的基准求解变量直接构造统一的组件灵活性上下文。
"""
function build_component_flexibility_context(
    component::AbstractComponent,
    result_values::AbstractDict;
    timestamp::String,
    time_step::String,
    case_id::String,
    application_type::String,
    operation_mode::String,
    boundary_condition::String,
    poi_id::Union{Nothing,String}=nothing,
    layer_id::Union{Nothing,String}=nothing,
    operating_point_overrides::AbstractDict=StringAnyDict(),
    numerical_tolerance_kw::Real=1e-6,
)
    operating_point = adapt_component_baseline_result(
        component,
        result_values;
        layer_id=layer_id,
        operating_point_overrides=operating_point_overrides,
        numerical_tolerance_kw=numerical_tolerance_kw,
    )

    return ComponentFlexibilityContext(
        timestamp=timestamp,
        time_step=time_step,
        case_id=case_id,
        application_type=application_type,
        operation_mode=operation_mode,
        boundary_condition=boundary_condition,
        poi_id=poi_id,
        operating_point=operating_point,
    )
end

"""
    load_component_flexibility_context(component, db_path; layer, timestamp, ...)

从现有 SQLite 结果库读取一台组件的基准结果，并一步构造灵活性上下文。
`layer["id"]` 决定结果层和设备可用状态，`layer["step"]` 直接作为 `time_step`。
"""
function load_component_flexibility_context(
    component::AbstractComponent,
    db_path::String;
    layer::AbstractDict,
    timestamp::String,
    case_id::String,
    application_type::String,
    operation_mode::String,
    boundary_condition::String,
    poi_id::Union{Nothing,String}=nothing,
    operating_point_overrides::AbstractDict=StringAnyDict(),
    numerical_tolerance_kw::Real=1e-6,
    value_reader::Function=_read_persisted_baseline_value,
)
    haskey(layer, "id") || throw(ArgumentError("layer must contain id."))
    haskey(layer, "step") || throw(ArgumentError("layer must contain step."))
    layer_id = string(layer["id"])
    time_step = string(layer["step"])

    result_values = read_component_baseline_result(
        component,
        db_path,
        layer_id,
        timestamp;
        value_reader=value_reader,
    )
    return build_component_flexibility_context(
        component,
        result_values;
        timestamp=timestamp,
        time_step=time_step,
        case_id=case_id,
        application_type=application_type,
        operation_mode=operation_mode,
        boundary_condition=boundary_condition,
        poi_id=poi_id,
        layer_id=layer_id,
        operating_point_overrides=operating_point_overrides,
        numerical_tolerance_kw=numerical_tolerance_kw,
    )
end
