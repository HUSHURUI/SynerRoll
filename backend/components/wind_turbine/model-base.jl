# ═══════════════════════════════════════════════════════════════════════════
# wind_turbine/model-base.jl — 数学原理蓝图
#
# 本文件是风机组件模型的原始实现，变量名无后缀，用于：
#   - 单实例场景的数学功能验证
#   - 理解模型的数学原理
#
# 共享函数（resolve_wind_turbine_params 等）见 model-common.jl
# 对应的元编程追踪版本见 model.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::WindTurbine, ctx::BuildContext)
    params = resolve_wind_turbine_params(component, ctx)
    return build_wind_turbine_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_wind_turbine_status_model!(model, component::WindTurbine, params, ctx::BuildContext, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)
    code = component_code(component)
    available_power = generate_wind_turbine_max_power(component, ctx)

    model[Symbol("AVAILABLE_WT_$(code)")] = @expression(model, [t in time_index], available_power[t])
    @variable(model, E_WT[t in time_index], lower_bound = 0.0, upper_bound = available_power[t])
    @variable(model, E_WT_cut[t in time_index], lower_bound = 0.0, upper_bound = available_power[t])
    @constraint(model, [t in time_index], E_WT[t] + E_WT_cut[t] == available_power[t])

    # P = P_available - P_cut。可用功率变化属于外生自然变化；主动上、下调
    # 分别对应减少、增加弃风功率，因此变化率只约束 P_cut 的可控变化。
    if params.ramp_constraint_on && length(time_index) > 1
        ramp_time_index = time_index[1:(end-1)]
        @constraint(
            model,
            [t in ramp_time_index],
            E_WT_cut[t] - E_WT_cut[t+1] <= params.ramp_limit_kw,
        )
        @constraint(
            model,
            [t in ramp_time_index],
            E_WT_cut[t+1] - E_WT_cut[t] <= params.ramp_limit_kw,
        )
    end

    if params.curtailment_constraint_on && params.max_cut_ratio < 1.0
        @constraint(model, sum(E_WT_cut) <= params.max_cut_ratio * sum(available_power))
    end

    objective_expr = @expression(model, 0.0)

    if params.cut_objective_on
        objective_expr += @expression(model, C_wt_cut, sum(E_WT_cut) * params.cut_cost)
    end

    if params.om_objective_on
        objective_expr += @expression(model, C_wt_om, sum(E_WT) * params.om_cost)
    end

    return objective_expr
end

function build_wind_turbine_status_model!(model, component::WindTurbine, params, ctx::BuildContext, status)
    error("WindTurbine does not support status $(params.status) in the standardized model.")
end
