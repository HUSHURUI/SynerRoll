# ═══════════════════════════════════════════════════════════════════════════
# electricity_load/flexibility.jl — 刚性电负荷灵活性计算
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::ElectricityLoad,
    context::ComponentFlexibilityContext,
)
    return zero_component_flexibility_results(component, context, "rigid_load")
end
