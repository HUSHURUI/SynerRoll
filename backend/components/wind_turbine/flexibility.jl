# ═══════════════════════════════════════════════════════════════════════════
# wind_turbine/flexibility.jl — 风机单体灵活性计算
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::WindTurbine,
    context::ComponentFlexibilityContext,
)
    paras = component_paras(component)
    ramp_rate_kw_per_hour = paras["ramp"] * paras["capacity"]

    return calculate_renewable_flexibility(
        component,
        context;
        default_ramp_up_kw_per_hour=ramp_rate_kw_per_hour,
        default_ramp_down_kw_per_hour=ramp_rate_kw_per_hour,
    )
end
