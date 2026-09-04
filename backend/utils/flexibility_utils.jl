# ═══════════════════════════════════════════════════════════════════════════
# flexibility_utils.jl — 组件灵活性共享计算函数
#
# 各组件的 flexibility.jl 只负责将现有组件参数映射到这些通用公式。
# 所有功率单位为 kW，能量单位为 kWh，时间单位为 h。
# ═══════════════════════════════════════════════════════════════════════════

struct FlexibilityValueNotProvided end
const FLEXIBILITY_VALUE_NOT_PROVIDED = FlexibilityValueNotProvided()

function flexibility_operating_value(
    context::ComponentFlexibilityContext,
    key::String;
    default=FLEXIBILITY_VALUE_NOT_PROVIDED,
)
    if haskey(context.operating_point, key)
        return context.operating_point[key]
    end

    default isa FlexibilityValueNotProvided &&
        error("Flexibility operating point is missing required field $(key).")
    return default
end

function flexibility_operating_real(
    context::ComponentFlexibilityContext,
    key::String;
    default=FLEXIBILITY_VALUE_NOT_PROVIDED,
    allow_infinite::Bool=false,
)
    value = flexibility_operating_value(context, key; default=default)
    value isa Real || error("Flexibility operating point field $(key) must be numeric.")

    result = Float64(value)
    if allow_infinite
        isnan(result) && error("Flexibility operating point field $(key) cannot be NaN.")
    else
        isfinite(result) || error("Flexibility operating point field $(key) must be finite.")
    end
    return result
end

function flexibility_operating_bool(
    context::ComponentFlexibilityContext,
    key::String;
    default=FLEXIBILITY_VALUE_NOT_PROVIDED,
)
    value = flexibility_operating_value(context, key; default=default)
    value isa Bool || error("Flexibility operating point field $(key) must be boolean.")
    return value
end

function build_component_flexibility_results(
    component::AbstractComponent,
    context::ComponentFlexibilityContext,
    upward_value::Real,
    downward_value::Real;
    upward_binding_constraint::Union{Nothing,String}=nothing,
    downward_binding_constraint::Union{Nothing,String}=nothing,
)
    return [
        ComponentFlexibilityResult(
            context,
            component;
            direction=FLEXIBILITY_UP,
            device_flexibility=upward_value,
            binding_constraint=upward_binding_constraint,
        ),
        ComponentFlexibilityResult(
            context,
            component;
            direction=FLEXIBILITY_DOWN,
            device_flexibility=downward_value,
            binding_constraint=downward_binding_constraint,
        ),
    ]
end

function zero_component_flexibility_results(
    component::AbstractComponent,
    context::ComponentFlexibilityContext,
    binding_constraint::String,
)
    return build_component_flexibility_results(
        component,
        context,
        0.0,
        0.0;
        upward_binding_constraint=binding_constraint,
        downward_binding_constraint=binding_constraint,
    )
end

function minimum_flexibility_limit(
    first_value::Real,
    first_constraint::String,
    second_value::Real,
    second_constraint::String,
)
    first_limit = max(0.0, Float64(first_value))
    second_limit = max(0.0, Float64(second_value))

    if first_limit <= second_limit
        return first_limit, first_constraint
    end
    return second_limit, second_constraint
end

function calculate_generator_flexibility(
    component::AbstractComponent,
    context::ComponentFlexibilityContext;
    default_minimum_power_kw::Real,
    default_maximum_power_kw::Real,
    default_ramp_up_kw_per_hour::Real,
    default_ramp_down_kw_per_hour::Real,
)
    flexibility_operating_bool(context, "available"; default=true) ||
        return zero_component_flexibility_results(component, context, "unavailable")

    current_power_kw = flexibility_operating_real(context, "power_kw")
    current_power_kw >= 0.0 || error("Generator power_kw must be non-negative.")

    minimum_power_kw = flexibility_operating_real(
        context,
        "minimum_power_kw";
        default=default_minimum_power_kw,
    )
    maximum_power_kw = flexibility_operating_real(
        context,
        "maximum_power_kw";
        default=default_maximum_power_kw,
    )
    0.0 <= minimum_power_kw <= maximum_power_kw ||
        error("Generator power limits must satisfy 0 <= minimum <= maximum.")

    ramp_up_kw_per_hour = flexibility_operating_real(
        context,
        "ramp_up_kw_per_hour";
        default=default_ramp_up_kw_per_hour,
        allow_infinite=true,
    )
    ramp_down_kw_per_hour = flexibility_operating_real(
        context,
        "ramp_down_kw_per_hour";
        default=default_ramp_down_kw_per_hour,
        allow_infinite=true,
    )
    ramp_up_kw_per_hour >= 0.0 || error("Generator upward ramp rate must be non-negative.")
    ramp_down_kw_per_hour >= 0.0 || error("Generator downward ramp rate must be non-negative.")

    delta_t = time_step_hours(context)
    upward_ramp_limit_kw = ramp_up_kw_per_hour * delta_t
    downward_ramp_limit_kw = ramp_down_kw_per_hour * delta_t
    is_online = flexibility_operating_bool(context, "is_online")

    if !is_online
        abs(current_power_kw) <= 1e-9 ||
            error("Offline generator power_kw must be zero.")
        startup_allowed = flexibility_operating_bool(context, "startup_allowed"; default=false)
        startup_time_hours = flexibility_operating_real(
            context,
            "startup_time_hours";
            default=Inf,
            allow_infinite=true,
        )

        if !startup_allowed || startup_time_hours > delta_t
            return zero_component_flexibility_results(component, context, "startup_unavailable")
        end

        upward_value, upward_constraint = minimum_flexibility_limit(
            maximum_power_kw,
            "maximum_power",
            upward_ramp_limit_kw,
            "ramp_up",
        )
        if upward_value + 1e-9 < minimum_power_kw
            return zero_component_flexibility_results(component, context, "minimum_power_on_startup")
        end

        return build_component_flexibility_results(
            component,
            context,
            upward_value,
            0.0;
            upward_binding_constraint=upward_constraint,
            downward_binding_constraint="offline",
        )
    end

    minimum_power_kw - 1e-9 <= current_power_kw <= maximum_power_kw + 1e-9 ||
        error("Online generator power_kw must be within its current power limits.")

    upward_value, upward_constraint = minimum_flexibility_limit(
        maximum_power_kw - current_power_kw,
        "maximum_power",
        upward_ramp_limit_kw,
        "ramp_up",
    )
    downward_value, downward_constraint = minimum_flexibility_limit(
        current_power_kw - minimum_power_kw,
        "minimum_power",
        downward_ramp_limit_kw,
        "ramp_down",
    )

    return build_component_flexibility_results(
        component,
        context,
        upward_value,
        downward_value;
        upward_binding_constraint=upward_constraint,
        downward_binding_constraint=downward_constraint,
    )
end

function calculate_renewable_flexibility(
    component::AbstractComponent,
    context::ComponentFlexibilityContext;
    default_ramp_up_kw_per_hour::Real,
    default_ramp_down_kw_per_hour::Real,
    default_ramp_constraint_on::Bool=false,
)
    flexibility_operating_bool(context, "available"; default=true) ||
        return zero_component_flexibility_results(component, context, "unavailable")

    current_power_kw = flexibility_operating_real(context, "power_kw")
    available_power_kw = flexibility_operating_real(context, "available_power_kw")
    minimum_power_kw = flexibility_operating_real(context, "minimum_power_kw"; default=0.0)
    current_power_kw >= 0.0 || error("Renewable power_kw must be non-negative.")
    available_power_kw >= 0.0 || error("Renewable available_power_kw must be non-negative.")
    0.0 <= minimum_power_kw <= available_power_kw ||
        error("Renewable power limits must satisfy 0 <= minimum <= available.")
    minimum_power_kw - 1e-9 <= current_power_kw <= available_power_kw + 1e-9 ||
        error("Renewable power_kw must be within minimum and available power.")

    ramp_constraint_on = flexibility_operating_bool(
        context,
        "ramp_constraint_on";
        default=default_ramp_constraint_on,
    )
    ramp_up_kw_per_hour = ramp_constraint_on ? flexibility_operating_real(
        context,
        "ramp_up_kw_per_hour";
        default=default_ramp_up_kw_per_hour,
        allow_infinite=true,
    ) : Inf
    ramp_down_kw_per_hour = ramp_constraint_on ? flexibility_operating_real(
        context,
        "ramp_down_kw_per_hour";
        default=default_ramp_down_kw_per_hour,
        allow_infinite=true,
    ) : Inf
    ramp_up_kw_per_hour >= 0.0 || error("Renewable upward ramp rate must be non-negative.")
    ramp_down_kw_per_hour >= 0.0 || error("Renewable downward ramp rate must be non-negative.")

    delta_t = time_step_hours(context)
    upward_value, upward_constraint = minimum_flexibility_limit(
        available_power_kw - current_power_kw,
        "available_power",
        ramp_up_kw_per_hour * delta_t,
        "ramp_up",
    )
    downward_value, downward_constraint = minimum_flexibility_limit(
        current_power_kw - minimum_power_kw,
        "minimum_power",
        ramp_down_kw_per_hour * delta_t,
        "ramp_down",
    )

    return build_component_flexibility_results(
        component,
        context,
        upward_value,
        downward_value;
        upward_binding_constraint=upward_constraint,
        downward_binding_constraint=downward_constraint,
    )
end

function calculate_storage_flexibility(
    component::AbstractComponent,
    context::ComponentFlexibilityContext;
    default_minimum_energy_kwh::Real,
    default_maximum_energy_kwh::Real,
    default_maximum_charge_power_kw::Real,
    default_maximum_discharge_power_kw::Real,
    charge_efficiency::Real,
    discharge_efficiency::Real,
    default_ramp_up_kw_per_hour::Real=Inf,
    default_ramp_down_kw_per_hour::Real=Inf,
)
    flexibility_operating_bool(context, "available"; default=true) ||
        return zero_component_flexibility_results(component, context, "unavailable")

    stored_energy_kwh = flexibility_operating_real(context, "stored_energy_kwh")
    charging_power_kw = flexibility_operating_real(context, "charging_power_kw")
    discharging_power_kw = flexibility_operating_real(context, "discharging_power_kw")
    charging_power_kw >= 0.0 || error("Storage charging_power_kw must be non-negative.")
    discharging_power_kw >= 0.0 || error("Storage discharging_power_kw must be non-negative.")
    charging_power_kw > 1e-9 && discharging_power_kw > 1e-9 &&
        error("Storage cannot charge and discharge simultaneously.")

    minimum_energy_kwh = flexibility_operating_real(
        context,
        "minimum_energy_kwh";
        default=default_minimum_energy_kwh,
    )
    maximum_energy_kwh = flexibility_operating_real(
        context,
        "maximum_energy_kwh";
        default=default_maximum_energy_kwh,
    )
    0.0 <= minimum_energy_kwh <= maximum_energy_kwh ||
        error("Storage energy limits must satisfy 0 <= minimum <= maximum.")
    minimum_energy_kwh - 1e-9 <= stored_energy_kwh <= maximum_energy_kwh + 1e-9 ||
        error("Storage stored_energy_kwh must be within its current energy limits.")

    maximum_charge_power_kw = flexibility_operating_real(
        context,
        "maximum_charge_power_kw";
        default=default_maximum_charge_power_kw,
    )
    maximum_discharge_power_kw = flexibility_operating_real(
        context,
        "maximum_discharge_power_kw";
        default=default_maximum_discharge_power_kw,
    )
    maximum_charge_power_kw >= 0.0 || error("Maximum charge power must be non-negative.")
    maximum_discharge_power_kw >= 0.0 || error("Maximum discharge power must be non-negative.")
    charging_power_kw <= maximum_charge_power_kw + 1e-9 ||
        error("Storage charging_power_kw exceeds maximum charge power.")
    discharging_power_kw <= maximum_discharge_power_kw + 1e-9 ||
        error("Storage discharging_power_kw exceeds maximum discharge power.")

    η_charge = Float64(charge_efficiency)
    η_discharge = Float64(discharge_efficiency)
    0.0 < η_charge <= 1.0 || error("Charge efficiency must be in (0, 1].")
    0.0 < η_discharge <= 1.0 || error("Discharge efficiency must be in (0, 1].")

    delta_t = time_step_hours(context)
    discharge_energy_limit_kw =
        η_discharge * max(0.0, stored_energy_kwh - minimum_energy_kwh) / delta_t
    charge_energy_limit_kw =
        max(0.0, maximum_energy_kwh - stored_energy_kwh) / (η_charge * delta_t)

    maximum_reachable_power_kw, upward_headroom_constraint = minimum_flexibility_limit(
        maximum_discharge_power_kw,
        "maximum_discharge_power",
        discharge_energy_limit_kw,
        "minimum_energy",
    )
    maximum_reachable_charge_kw, downward_headroom_constraint = minimum_flexibility_limit(
        maximum_charge_power_kw,
        "maximum_charge_power",
        charge_energy_limit_kw,
        "maximum_energy",
    )
    minimum_reachable_power_kw = -maximum_reachable_charge_kw
    current_power_kw = discharging_power_kw - charging_power_kw

    ramp_up_kw_per_hour = flexibility_operating_real(
        context,
        "ramp_up_kw_per_hour";
        default=default_ramp_up_kw_per_hour,
        allow_infinite=true,
    )
    ramp_down_kw_per_hour = flexibility_operating_real(
        context,
        "ramp_down_kw_per_hour";
        default=default_ramp_down_kw_per_hour,
        allow_infinite=true,
    )
    ramp_up_kw_per_hour >= 0.0 || error("Storage upward ramp rate must be non-negative.")
    ramp_down_kw_per_hour >= 0.0 || error("Storage downward ramp rate must be non-negative.")

    upward_value, upward_constraint = minimum_flexibility_limit(
        maximum_reachable_power_kw - current_power_kw,
        upward_headroom_constraint,
        ramp_up_kw_per_hour * delta_t,
        "ramp_up",
    )
    downward_value, downward_constraint = minimum_flexibility_limit(
        current_power_kw - minimum_reachable_power_kw,
        downward_headroom_constraint,
        ramp_down_kw_per_hour * delta_t,
        "ramp_down",
    )

    return build_component_flexibility_results(
        component,
        context,
        upward_value,
        downward_value;
        upward_binding_constraint=upward_constraint,
        downward_binding_constraint=downward_constraint,
    )
end

function calculate_flexible_load_flexibility(
    component::AbstractComponent,
    context::ComponentFlexibilityContext;
    default_minimum_power_kw::Real,
    default_maximum_power_kw::Real,
    default_ramp_up_kw_per_hour::Real,
    default_ramp_down_kw_per_hour::Real,
)
    flexibility_operating_bool(context, "available"; default=true) ||
        return zero_component_flexibility_results(component, context, "unavailable")

    current_power_kw = flexibility_operating_real(context, "power_kw")
    current_power_kw >= 0.0 || error("Flexible load power_kw must be non-negative.")

    minimum_power_kw = flexibility_operating_real(
        context,
        "minimum_power_kw";
        default=default_minimum_power_kw,
    )
    maximum_power_kw = flexibility_operating_real(
        context,
        "maximum_power_kw";
        default=default_maximum_power_kw,
    )
    0.0 <= minimum_power_kw <= maximum_power_kw ||
        error("Flexible load limits must satisfy 0 <= minimum <= maximum.")

    ramp_up_kw_per_hour = flexibility_operating_real(
        context,
        "ramp_up_kw_per_hour";
        default=default_ramp_up_kw_per_hour,
        allow_infinite=true,
    )
    ramp_down_kw_per_hour = flexibility_operating_real(
        context,
        "ramp_down_kw_per_hour";
        default=default_ramp_down_kw_per_hour,
        allow_infinite=true,
    )
    ramp_up_kw_per_hour >= 0.0 || error("Flexible load upward ramp rate must be non-negative.")
    ramp_down_kw_per_hour >= 0.0 || error("Flexible load downward ramp rate must be non-negative.")

    delta_t = time_step_hours(context)
    is_online = flexibility_operating_bool(context, "is_online")

    if !is_online
        abs(current_power_kw) <= 1e-9 || error("Offline flexible load power_kw must be zero.")
        startup_allowed = flexibility_operating_bool(context, "startup_allowed"; default=false)
        startup_time_hours = flexibility_operating_real(
            context,
            "startup_time_hours";
            default=Inf,
            allow_infinite=true,
        )
        if !startup_allowed || startup_time_hours > delta_t
            return zero_component_flexibility_results(component, context, "startup_unavailable")
        end

        downward_value, downward_constraint = minimum_flexibility_limit(
            maximum_power_kw,
            "maximum_power",
            ramp_up_kw_per_hour * delta_t,
            "ramp_up",
        )
        if downward_value + 1e-9 < minimum_power_kw
            return zero_component_flexibility_results(component, context, "minimum_power_on_startup")
        end

        return build_component_flexibility_results(
            component,
            context,
            0.0,
            downward_value;
            upward_binding_constraint="offline",
            downward_binding_constraint=downward_constraint,
        )
    end

    minimum_power_kw - 1e-9 <= current_power_kw <= maximum_power_kw + 1e-9 ||
        error("Online flexible load power_kw must be within its current power limits.")

    # 系统方向：负荷降低是上调，负荷增加是下调。
    upward_value, upward_constraint = minimum_flexibility_limit(
        current_power_kw - minimum_power_kw,
        "minimum_power",
        ramp_down_kw_per_hour * delta_t,
        "ramp_down",
    )
    downward_value, downward_constraint = minimum_flexibility_limit(
        maximum_power_kw - current_power_kw,
        "maximum_power",
        ramp_up_kw_per_hour * delta_t,
        "ramp_up",
    )

    return build_component_flexibility_results(
        component,
        context,
        upward_value,
        downward_value;
        upward_binding_constraint=upward_constraint,
        downward_binding_constraint=downward_constraint,
    )
end

# 电网接口灵活性（说明文档 §2.2.8）：只度量基准并网点功率到接口功率上下限
# 的剩余空间，不含联络线变化率；结果是系统边界，不计入内部设备灵活性之和。
# poi_power_kw 正值表示向电网上送、负值表示从电网购入。
function calculate_grid_flexibility(
    component::AbstractComponent,
    context::ComponentFlexibilityContext;
    default_maximum_poi_power_kw::Real,
    default_minimum_poi_power_kw::Real,
)
    flexibility_operating_bool(context, "available"; default=true) ||
        return zero_component_flexibility_results(component, context, "unavailable")

    poi_power_kw = flexibility_operating_real(context, "poi_power_kw")
    maximum_poi_power_kw = flexibility_operating_real(
        context,
        "maximum_poi_power_kw";
        default=default_maximum_poi_power_kw,
    )
    minimum_poi_power_kw = flexibility_operating_real(
        context,
        "minimum_poi_power_kw";
        default=default_minimum_poi_power_kw,
    )
    minimum_poi_power_kw <= maximum_poi_power_kw ||
        error("Grid interface power limits must satisfy minimum <= maximum.")
    minimum_poi_power_kw - 1e-9 <= poi_power_kw <= maximum_poi_power_kw + 1e-9 ||
        error("Grid poi_power_kw must be within its interface power limits.")

    # 系统上调对应并网点功率增大（多上送或少购入），下调对应并网点功率减小。
    upward_value = max(0.0, maximum_poi_power_kw - poi_power_kw)
    downward_value = max(0.0, poi_power_kw - minimum_poi_power_kw)

    return [
        ComponentFlexibilityResult(
            context,
            component;
            direction=FLEXIBILITY_UP,
            device_flexibility=upward_value,
            binding_constraint="maximum_poi_power",
            baseline_poi_power=poi_power_kw,
            poi_power_limit=maximum_poi_power_kw,
        ),
        ComponentFlexibilityResult(
            context,
            component;
            direction=FLEXIBILITY_DOWN,
            device_flexibility=downward_value,
            binding_constraint="minimum_poi_power",
            baseline_poi_power=poi_power_kw,
            poi_power_limit=minimum_poi_power_kw,
        ),
    ]
end
