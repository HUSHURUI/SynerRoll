# ═══════════════════════════════════════════════════════════════════════════
# power_grid/flexibility.jl — 电网接口灵活性计算
#
# 电网接口是系统边界而非内部设备（说明文档 §2.2.8）：上、下调空间只度量
# 基准并网点功率到接口功率上下限的距离，结果不得默认加入内部资源灵活性之和。
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::PowerGrid,
    context::ComponentFlexibilityContext,
)
    paras = component_paras(component)
    capacity_kw = paras["capacity"]

    return calculate_grid_flexibility(
        component,
        context;
        default_maximum_poi_power_kw=paras["sell_ratio"] * capacity_kw,
        default_minimum_poi_power_kw=-paras["buy_ratio"] * capacity_kw,
    )
end
