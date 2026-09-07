# ═══════════════════════════════════════════════════════════════════════════
# gas_power/model-common.jl — 共享函数
#
# model-base.jl 和 model.jl 共用的参数解析与辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function resolve_gas_power_params(component::GasPower, ctx::BuildContext)
    layer_settings = layer_config(component, ctx.layer["id"])
    time_step_hours = step_hours(ctx.layer)

    return (
        layer_settings=layer_settings,
        status=layer_settings["status"],
        capacity=component_paras(component)["capacity"],
        efficiency=component_paras(component)["η"],
        ramp_ratio=component_paras(component)["ramp"] * time_step_hours,
        min_output_ratio=component_paras(component)["min"],
        min_on_steps=Int(round(component_paras(component)["T_min_on"] / time_step_hours)),
        min_off_steps=Int(round(component_paras(component)["T_min_off"] / time_step_hours)),
        om_cost=component_costs(component)["om_cost"] * time_step_hours,
        on_off_cost=component_costs(component)["on_off_cost"] * time_step_hours,
        adjust_limit=layer_settings["paras"]["adjust_limit"],
        adjust_cost=layer_settings["costs"]["adjust_cost"] * time_step_hours,
        ramp_constraint_on=layer_settings["constraints"]["ramp_constraint_on"],
        min_constraint_on=layer_settings["constraints"]["min_constraint_on"],
        on_off_constraint_on=layer_settings["constraints"]["on_off_constraint_on"],
        adjust_constraint_on=layer_settings["constraints"]["adjust_constraint_on"],
        om_objective_on=layer_settings["objectives"]["om_objective_on"],
        adjust_objective_on=layer_settings["objectives"]["adjust_objective_on"],
        on_off_objective_on=layer_settings["objectives"]["on_off_objective_on"],
    )
end
