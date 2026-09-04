# ═══════════════════════════════════════════════════════════════════════════
# pumped_storage/model-common.jl — 共享函数
#
# model-base.jl 和 model.jl 共用的参数解析与辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function resolve_pumped_storage_params(component::PumpedStorage, ctx::BuildContext)
    layer_settings = layer_config(component, ctx.layer["id"])
    time_step_hours = step_hours(ctx.layer)

    # 抽水蓄能综合效率 = 水泵效率 × 水轮机效率
    η_pump = component_paras(component)["η_pump"]
    η_turbine = component_paras(component)["η_turbine"]

    return (
        layer_settings=layer_settings,
        status=layer_settings["status"],
        # 装机容量是抽水/发电功率上限（kW），storage_capacity 才是状态容量（kWh）。
        capacity=component_paras(component)["capacity"],
        storage_capacity=component_paras(component)["storage_capacity"],
        η_pump=η_pump,
        η_turbine=η_turbine,
        efficiency=sqrt(η_pump * η_turbine),  # 综合往返效率取几何平均
        ramp_ratio=component_paras(component)["ramp"],
        time_step_hours=time_step_hours,
        min_soc=component_paras(component)["min"],
        max_soc=component_paras(component)["max"],
        loss=1 - (1 - component_paras(component)["loss"])^time_step_hours,
        initial_soc=component_paras(component)["ini"],
        head_height=component_paras(component)["head_height"],
        om_cost=component_costs(component)["om_cost"] * time_step_hours,
        adjust_limit=layer_settings["paras"]["adjust_limit"],
        adjust_cost=layer_settings["costs"]["adjust_cost"] * time_step_hours,
        ramp_constraint_on=layer_settings["constraints"]["ramp_constraint_on"],
        min_constraint_on=layer_settings["constraints"]["min_constraint_on"],
        adjust_constraint_on=layer_settings["constraints"]["adjust_constraint_on"],
        start_end_equality_constraint_on=layer_settings["constraints"]["start_end_equality_constraint_on"],
        om_objective_on=layer_settings["objectives"]["om_objective_on"],
        adjust_objective_on=layer_settings["objectives"]["adjust_objective_on"],
    )
end

function derive_pumped_storage_state(planned_input::Vector{Float64}, planned_output::Vector{Float64})
    return [
        (input_value > 1.0 && output_value < 1.0) ? 1.0 :
        (input_value < 1.0 && output_value > 1.0) ? -1.0 :
        0.0
        for (input_value, output_value) in zip(planned_input, planned_output)
    ]
end
