# ═══════════════════════════════════════════════════════════════════════════
# pumped_storage/flexibility.jl — 抽水蓄能单体灵活性计算
#
# 发电为正、抽水为负。capacity 是功率容量（kW），storage_capacity 是
# 水库等效能量容量（kWh）。
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::PumpedStorage,
    context::ComponentFlexibilityContext,
)
    paras = component_paras(component)
    power_capacity_kw = paras["capacity"]
    energy_capacity_kwh = paras["storage_capacity"]
    ramp_rate_kw_per_hour = paras["ramp"] * power_capacity_kw

    return calculate_storage_flexibility(
        component,
        context;
        default_minimum_energy_kwh=paras["min"] * energy_capacity_kwh,
        default_maximum_energy_kwh=paras["max"] * energy_capacity_kwh,
        default_maximum_charge_power_kw=power_capacity_kw,
        default_maximum_discharge_power_kw=power_capacity_kw,
        charge_efficiency=paras["η_pump"],
        discharge_efficiency=paras["η_turbine"],
        default_ramp_up_kw_per_hour=ramp_rate_kw_per_hour,
        default_ramp_down_kw_per_hour=ramp_rate_kw_per_hour,
    )
end
