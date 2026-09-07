# ═══════════════════════════════════════════════════════════════════════════
# combined_heat_power/flexibility.jl — 热电联产机组单体灵活性计算
#
# 当前模型采用外部热负荷驱动的固定热电比：每个时段的供热功率固定，
# 电功率也随之唯一确定。未配置储热或弃热通道时，不能把装机余量重复计为
# 可独立调用的电功率灵活性。
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::CombinedHeatPower,
    context::ComponentFlexibilityContext,
)
    return zero_component_flexibility_results(
        component,
        context,
        "heat_led_fixed_ratio",
    )
end
