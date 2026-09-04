# ═══════════════════════════════════════════════════════════════════════════
# combined_heat_power/model-common.jl — 共享函数
#
# model-base.jl 和 model.jl 共用的参数解析与辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function resolve_chp_params(component::CombinedHeatPower, ctx::BuildContext)
    layer_settings = layer_config(component, ctx.layer["id"])
    time_step_hours = step_hours(ctx.layer)
    paras = component_paras(component)

    boundary_ids = component_boundary_ids(component)
    isempty(boundary_ids) && error(
        "CombinedHeatPower $(component_type(component)) has no heat-load boundary configured",
    )

    heat_demand = nothing
    for boundary_id in boundary_ids
        data, label = resolve_prediction_series(
            ctx;
            source_id=boundary_id,
            algorithm_key="heatLoadPrediction",
        )
        label === nothing && continue
        if parse_ts_label(label)["var_name"] == "heat"
            heat_demand = abs.(data)
            break
        end
    end
    heat_demand === nothing && error(
        "No heat-load boundary data found for CombinedHeatPower — checked boundaryIds: $(boundary_ids)",
    )

    capacity = paras["capacity"]
    β = paras["β"]
    max_demand = maximum(heat_demand)
    max_heat_output = capacity * β
    if max_demand > max_heat_output + 1e-6
        error(
            "CHP 热负荷峰值 $(max_demand) 超过最大热出力 $(max_heat_output) " *
            "(capacity=$(capacity) × β=$(β))。请增大 CHP 容量或降低热负荷边界。"
        )
    end

    return (
        layer_settings=layer_settings,
        status=layer_settings["status"],
        heat_demand=heat_demand,
        capacity=capacity,
        η_e=paras["η_e"],
        β=β,
        ramp_ratio=paras["ramp"] * time_step_hours,
        min_output_ratio=paras["min"],
        min_on_steps=Int(round(paras["T_min_on"] / time_step_hours)),
        min_off_steps=Int(round(paras["T_min_off"] / time_step_hours)),
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
