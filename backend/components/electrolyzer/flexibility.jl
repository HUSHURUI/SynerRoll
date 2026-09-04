# ═══════════════════════════════════════════════════════════════════════════
# electrolyzer/flexibility.jl — 电解槽柔性负荷灵活性计算
#
# 系统方向：电解槽降低用电提供上调，增加用电提供下调。
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::Electrolyzer,
    context::ComponentFlexibilityContext,
)
    paras = component_paras(component)
    capacity = paras["capacity"]
    ramp_rate_kw_per_hour = paras["ramp"] * capacity

    return calculate_flexible_load_flexibility(
        component,
        context;
        default_minimum_power_kw=paras["min"] * capacity,
        default_maximum_power_kw=capacity,
        default_ramp_up_kw_per_hour=ramp_rate_kw_per_hour,
        default_ramp_down_kw_per_hour=ramp_rate_kw_per_hour,
    )
end
