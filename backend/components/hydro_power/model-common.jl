# ═══════════════════════════════════════════════════════════════════════════
# hydro_power/model-common.jl — 共享函数
#
# model-base.jl 和 model.jl 共用的参数解析与辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function resolve_hydro_power_params(component::HydroPower, ctx::BuildContext)
    layer_settings = layer_config(component, ctx.layer["id"])
    paras = component_paras(component)
    time_step_hours = step_hours(ctx.layer)

    ramp_rate_kw_per_hour = paras["ramp"] * paras["capacity"]

    return (
        layer_settings=layer_settings,
        status=layer_settings["status"],
        capacity=paras["capacity"],
        minimum_output_ratio=paras["min"],
        ramp_rate_kw_per_hour=ramp_rate_kw_per_hour,
        ramp_limit_kw=ramp_rate_kw_per_hour * time_step_hours,
        time_step_hours=time_step_hours,
        om_cost=component_costs(component)["om_cost"] * time_step_hours,
        ramp_constraint_on=layer_settings["constraints"]["ramp_constraint_on"],
        min_constraint_on=layer_settings["constraints"]["min_constraint_on"],
        om_objective_on=layer_settings["objectives"]["om_objective_on"],
    )
end

"""
    generate_hydro_available_power(component, ctx) -> Vector{Float64}

根据组件关联的边界数据计算常规水电逐时段可用功率（kW）。
`factor` 表示枯/平/丰水期等可用系数，`power` 表示直接给定的可用功率。
未配置边界时以装机容量作为静态上限。
"""
function generate_hydro_available_power(component::HydroPower, ctx::BuildContext)
    boundary_ids = component_boundary_ids(component)
    paras = component_paras(component)
    capacity = paras["capacity"]

    if isempty(boundary_ids)
        time_index = generate_timespan(ctx.layer)
        return fill(Float64(capacity), length(time_index))
    end

    for boundary_id in boundary_ids
        data, label = resolve_prediction_series(
            ctx;
            source_id=boundary_id,
            algorithm_key="hydroPowerPrediction",
        )
        if data === nothing
            continue
        end
        var_name = parse_ts_label(label)["var_name"]
        if var_name == "factor"
            return clamp.(data, 0.0, 1.0) .* capacity
        elseif var_name == "power"
            return clamp.(data, 0.0, capacity)
        end
    end

    error("No valid boundary data found for HydroPower — checked boundaryIds: $(boundary_ids)")
end

"""
    generate_hydro_minimum_power(available_power, params) -> Vector{Float64}

生成逐时段最小技术出力。关闭最小出力约束时返回零；开启时，静态最小
出力不会超过该时段因水情边界给出的可用功率。
"""
function generate_hydro_minimum_power(available_power::Vector{Float64}, params)
    if !params.min_constraint_on
        return zeros(Float64, length(available_power))
    end

    static_minimum = params.minimum_output_ratio * params.capacity
    return min.(available_power, static_minimum)
end
