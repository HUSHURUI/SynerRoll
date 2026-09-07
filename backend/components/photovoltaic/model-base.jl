# ═══════════════════════════════════════════════════════════════════════════
# photovoltaic/model-base.jl — 数学原理蓝图
#
# 本文件是光伏组件模型的原始实现，变量名无后缀，用于：
#   - 单实例场景的数学功能验证
#   - 理解模型的数学原理
#
# 共享函数（resolve_photovoltaic_params 等）见 model-common.jl
# 对应的元编程追踪版本见 model.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::Photovoltaic, ctx::BuildContext)
    params = resolve_photovoltaic_params(component, ctx)
    return build_photovoltaic_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_photovoltaic_status_model!(model, component::Photovoltaic, params, ctx::BuildContext, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)
    available_power = generate_photovoltaic_max_power(component, ctx)

    @variable(model, E_PV[t in time_index], lower_bound = 0.0, upper_bound = available_power[t])
    @variable(model, E_PV_cut[t in time_index], lower_bound = 0.0, upper_bound = available_power[t])
    @constraint(model, [t in time_index], E_PV[t] + E_PV_cut[t] == available_power[t])

    # P = P_available - P_cut。可用功率变化属于外生自然变化；主动上、下调
    # 分别对应减少、增加弃光功率，因此变化率只约束 P_cut 的可控变化。
    if params.ramp_constraint_on && length(time_index) > 1
        ramp_time_index = time_index[1:(end-1)]
        @constraint(
            model,
            [t in ramp_time_index],
            E_PV_cut[t] - E_PV_cut[t+1] <= params.ramp_limit_kw,
        )
        @constraint(
            model,
            [t in ramp_time_index],
            E_PV_cut[t+1] - E_PV_cut[t] <= params.ramp_limit_kw,
        )
    end

    if params.curtailment_constraint_on && params.max_cut_ratio < 1.0
        @constraint(model, sum(E_PV_cut) <= params.max_cut_ratio * sum(available_power))
    end

    objective_expr = @expression(model, 0.0)

    if params.cut_objective_on
        objective_expr += @expression(model, C_pv_cut, sum(E_PV_cut) * params.cut_cost)
    end

    if params.om_objective_on
        objective_expr += @expression(model, C_pv_om, sum(E_PV) * params.om_cost)
    end

    return objective_expr
end

function build_photovoltaic_status_model!(model, component::Photovoltaic, params, ctx::BuildContext, status)
    error("Photovoltaic does not support status $(params.status) in the standardized model.")
end
