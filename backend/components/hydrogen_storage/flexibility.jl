# ═══════════════════════════════════════════════════════════════════════════
# hydrogen_storage/flexibility.jl — 储氢罐电功率灵活性接口
#
# 储氢罐不直接与电母线交换有功功率，其耦合影响由系统全约束优化计算。
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::HydrogenStorage,
    context::ComponentFlexibilityContext,
)
    return zero_component_flexibility_results(
        component,
        context,
        "not_direct_electric_resource",
    )
end
