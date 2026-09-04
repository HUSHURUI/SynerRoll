# ═══════════════════════════════════════════════════════════════════════════
# hydro_power/flexibility.jl — 常规水电单体灵活性计算
#
# 首版按可调发电单元计算：受当前出力、可用/最小出力及可选爬坡约束限制。
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::HydroPower,
    context::ComponentFlexibilityContext,
)
    paras = component_paras(component)
    ramp_rate_kw_per_hour = paras["ramp"] * paras["capacity"]

    return calculate_renewable_flexibility(
        component,
        context;
        default_ramp_up_kw_per_hour=ramp_rate_kw_per_hour,
        default_ramp_down_kw_per_hour=ramp_rate_kw_per_hour,
        default_ramp_constraint_on=true,
    )
end
