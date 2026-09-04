# ═══════════════════════════════════════════════════════════════════════════
# heat_load/flexibility.jl — 刚性热负荷电功率灵活性接口
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::HeatLoad,
    context::ComponentFlexibilityContext,
)
    return zero_component_flexibility_results(
        component,
        context,
        "not_direct_electric_resource",
    )
end
