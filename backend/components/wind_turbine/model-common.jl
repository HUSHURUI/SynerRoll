# ═══════════════════════════════════════════════════════════════════════════
# wind_turbine/model-common.jl — 共享函数
#
# model-base.jl 和 model.jl 共用的参数解析与辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function resolve_wind_turbine_params(component::WindTurbine, ctx::BuildContext)
    layer_settings = layer_config(component, ctx.layer["id"])
    paras = component_paras(component)
    time_step_hours = step_hours(ctx.layer)
    ramp_rate_kw_per_hour = paras["ramp"] * paras["capacity"]

    return (
        layer_settings=layer_settings,
        status=layer_settings["status"],
        max_cut_ratio=layer_settings["paras"]["max_cut_ratio"],
        curtailment_constraint_on=layer_settings["constraints"]["curtailment_constraint_on"],
        ramp_constraint_on=layer_settings["constraints"]["ramp_constraint_on"],
        ramp_rate_kw_per_hour=ramp_rate_kw_per_hour,
        ramp_limit_kw=ramp_rate_kw_per_hour * time_step_hours,
        om_objective_on=layer_settings["objectives"]["om_objective_on"],
        cut_objective_on=layer_settings["objectives"]["cut_objective_on"],
        om_cost=component_costs(component)["om_cost"] * step_hours(ctx.layer),
        cut_cost=component_costs(component)["cut_cost"] * step_hours(ctx.layer),
    )
end

"""
    generate_wind_turbine_max_power(component, ctx) -> Vector{Float64}

根据组件关联的边界数据计算风机可用功率。
遍历 component 的 boundaryIds，从任务时序库中查询边界数据，
按 boundary 的物理意义（factor / wind_speed / power）转换为可用功率。
"""
function generate_wind_turbine_max_power(component::WindTurbine, ctx::BuildContext)
    boundary_ids = component_boundary_ids(component)
    isempty(boundary_ids) && error("WindTurbine $(component_type(component)) has no boundaryIds configured")

    paras = component_paras(component)

    for boundary_id in boundary_ids
        data, label = resolve_prediction_series(
            ctx;
            source_id=boundary_id,
            algorithm_key="windTurbinePrediction",
        )
        var_name = parse_ts_label(label)["var_name"]
        
        if var_name == "factor"
            return clamp.(data, 0.0, 1.0) .* paras["capacity"]
        elseif var_name == "wind_speed"
            scaled_speed = abs.(data) .* (paras["h2"] / paras["h1"])^paras["α"]
            coeff = calculate_wind_turbine_coefficient(
                scaled_speed,
                paras["v_in"],
                paras["v_r"],
                paras["v_out"],
            )
            return coeff .* paras["η_t"] .* paras["η_g"] .* paras["η_inverter"] .* paras["capacity"]
        elseif var_name == "power"
            return abs.(data)
        end
    end

    error("No valid boundary data found for WindTurbine — checked boundaryIds: $(boundary_ids)")
end

function calculate_wind_turbine_coefficient(wind_speed, v_in::Float64, v_r::Float64, v_out::Float64)
    result = similar(wind_speed, Float64)

    for (index, speed) in enumerate(wind_speed)
        if speed < v_in
            result[index] = 0.0
        elseif v_in <= speed < v_r
            result[index] = (speed^3 - v_in^3) / (v_r^3 - v_in^3)
        elseif v_r <= speed < v_out
            result[index] = 1.0
        else
            result[index] = 0.0
        end
    end

    return result
end
