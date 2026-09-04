# ═══════════════════════════════════════════════════════════════════════════
# gas_power/flexibility.jl — 燃气机组单体灵活性计算
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::GasPower,
    context::ComponentFlexibilityContext,
)
    paras = component_paras(component)
    capacity = paras["capacity"]
    ramp_rate_kw_per_hour = paras["ramp"] * capacity

    return calculate_generator_flexibility(
        component,
        context;
        default_minimum_power_kw=paras["min"] * capacity,
        default_maximum_power_kw=capacity,
        default_ramp_up_kw_per_hour=ramp_rate_kw_per_hour,
        default_ramp_down_kw_per_hour=ramp_rate_kw_per_hour,
    )
end
