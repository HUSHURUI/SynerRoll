# ═══════════════════════════════════════════════════════════════════════════
# photovoltaic/model.jl — 元编程架构
#
# 设计：
#   - 使用 JuMP 直接 API + CodeTracer 构建模型并记录代码
#   - 返回 (objective_expr, code_lines::Vector{String})
#   - 所有参数在代码追踪中内联为硬值
#   - 原始数学原理见 model-base.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::Photovoltaic, ctx::BuildContext, tracer::CodeTracer)
    params = resolve_photovoltaic_params(component, ctx)
    code = component_code(component)
    return build_photovoltaic_status_model!(model, component, params, ctx, code, tracer, Val(Symbol(params.status)))
end

function build_photovoltaic_status_model!(model, component::Photovoltaic, params, ctx::BuildContext,
                                          code::String, tracer::CodeTracer, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)
    available_power = generate_photovoltaic_max_power(component, ctx)

    # ── 变量 ──────────────────────────────────────────────────────────
    E_PV = add_tracked_variable!(model, tracer, "E_PV_$(code)", time_index;
        lower_bound = 0.0, upper_bound = available_power)
    E_PV_cut = add_tracked_variable!(model, tracer, "E_PV_cut_$(code)", time_index;
        lower_bound = 0.0, upper_bound = available_power)

    # ── 约束：出力 + 弃光 = 可用功率 ──────────────────────────────────
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_PV_$(code)[t] + E_PV_cut_$(code)[t] == $(format_val(available_power))[t])",
        () -> @constraint(model, [t in time_index], E_PV[t] + E_PV_cut[t] == available_power[t])
    )

    # ── 约束：主动有功变化率 ──────────────────────────────────────────
    # P = P_available - P_cut，故只约束弃光功率的主动变化，不把自然可用
    # 功率变化误当作场站主动调节。
    if params.ramp_constraint_on && length(time_index) > 1
        ramp_time_index = time_index[1:(end-1)]
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(ramp_time_index))], E_PV_cut_$(code)[t] - E_PV_cut_$(code)[t+1] <= $(format_val(params.ramp_limit_kw)))",
            () -> @constraint(model, [t in ramp_time_index],
                E_PV_cut[t] - E_PV_cut[t+1] <= params.ramp_limit_kw)
        )
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(ramp_time_index))], E_PV_cut_$(code)[t+1] - E_PV_cut_$(code)[t] <= $(format_val(params.ramp_limit_kw)))",
            () -> @constraint(model, [t in ramp_time_index],
                E_PV_cut[t+1] - E_PV_cut[t] <= params.ramp_limit_kw)
        )
    end

    # ── 约束：弃光上限 ────────────────────────────────────────────────
    if params.curtailment_constraint_on && params.max_cut_ratio < 1.0
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, sum(E_PV_cut_$(code)) <= $(format_val(params.max_cut_ratio)) * sum($(format_val(available_power))))",
            () -> @constraint(model, sum(E_PV_cut) <= params.max_cut_ratio * sum(available_power))
        )
    end

    # ── 目标函数 ──────────────────────────────────────────────────────
    objective_expr = @expression(model, 0.0)

    if params.cut_objective_on
        cost_expr = sum(E_PV_cut) * params.cut_cost
        add_tracked_expression!(model, tracer, "C_pv_cut_$(code)",
            "@expression(model, C_pv_cut_$(code), sum(E_PV_cut_$(code)) * $(format_val(params.cut_cost)))",
            cost_expr; to_objective=true)
        objective_expr += cost_expr
    end

    if params.om_objective_on
        om_expr = sum(E_PV) * params.om_cost
        add_tracked_expression!(model, tracer, "C_pv_om_$(code)",
            "@expression(model, C_pv_om_$(code), sum(E_PV_$(code)) * $(format_val(params.om_cost)))",
            om_expr; to_objective=true)
        objective_expr += om_expr
    end

    return objective_expr
end

function build_photovoltaic_status_model!(model, component::Photovoltaic, params, ctx::BuildContext,
                                          code::String, tracer::CodeTracer, status)
    error("Photovoltaic does not support status $(params.status) in the standardized model.")
end
