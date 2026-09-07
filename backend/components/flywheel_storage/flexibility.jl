# ═══════════════════════════════════════════════════════════════════════════
# flywheel_storage/flexibility.jl — 飞轮储能单体灵活性计算
# ═══════════════════════════════════════════════════════════════════════════

function calculate_component_flexibility_impl(
    component::FlywheelStorage,
    context::ComponentFlexibilityContext,
)
    paras = component_paras(component)
    energy_capacity_kwh = paras["capacity"]
    power_limit_kw = paras["ramp"] * energy_capacity_kwh

    return calculate_storage_flexibility(
        component,
        context;
        default_minimum_energy_kwh=paras["min"] * energy_capacity_kwh,
        default_maximum_energy_kwh=paras["max"] * energy_capacity_kwh,
        default_maximum_charge_power_kw=power_limit_kw,
        default_maximum_discharge_power_kw=power_limit_kw,
        charge_efficiency=paras["η"],
        discharge_efficiency=paras["η"],
    )
end
