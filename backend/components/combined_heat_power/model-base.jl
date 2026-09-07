# ═══════════════════════════════════════════════════════════════════════════
# combined_heat_power/model-base.jl — 数学原理蓝图
#
# 本文件是热电联产机组模型的原始实现，变量名无后缀，用于：
#   - 单实例场景的数学功能验证
#   - 理解模型的数学原理
#
# 数学关系：
#   Q_CHP[t] = heat_demand[t]         （供热功率跟随外部热负荷边界）
#   Q_CHP[t] = E_CHP[t] * β           （固定热电比，热负荷反算电出力）
#   E_CHP[t] = F_CHP[t] * η_e        （电出力 = 燃料 × 发电效率）
#
# 共享函数（resolve_chp_params）见 model-common.jl
# 对应的元编程追踪版本见 model.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::CombinedHeatPower, ctx::BuildContext)
    params = resolve_chp_params(component, ctx)
    return build_chp_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_chp_status_model!(model, component::CombinedHeatPower, params, ctx::BuildContext, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_CHP[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, Q_CHP[t in time_index], lower_bound = 0.0, upper_bound = params.capacity * params.β)
    @variable(model, F_CHP[t in time_index])

    # 以热定电：供热功率首先由外部热负荷边界固定
    @constraint(model, [t in time_index], Q_CHP[t] == params.heat_demand[t])
    # 燃料-电约束：E = F * η_e
    @constraint(model, [t in time_index], E_CHP[t] == F_CHP[t] * params.η_e)
    # 热电耦合约束：H = E * β
    @constraint(model, [t in time_index], Q_CHP[t] == E_CHP[t] * params.β)

    if params.ramp_constraint_on
        define_chp_ramp_constraints!(model, time_index, E_CHP, params.ramp_ratio, params.capacity)
    end

    on_off_objective_expr = @expression(model, 0.0)
    if params.on_off_constraint_on
        status_vector, on_off_objective_expr = define_chp_on_off_constraints!(
            model, time_index, E_CHP, params.min_on_steps, params.min_off_steps,
            params.on_off_cost, params.capacity)
        define_chp_min_constraints!(model, time_index, E_CHP, status_vector, params.min_output_ratio, params.capacity)
    elseif params.min_constraint_on
        define_chp_min_constraints!(model, time_index, E_CHP, params.min_output_ratio, params.capacity)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_chp_om_cost!(model, time_index, E_CHP, params.om_cost)
    end
    if params.on_off_objective_on
        objective_expr += on_off_objective_expr
    end

    return objective_expr
end

function build_chp_status_model!(model, component::CombinedHeatPower, params, ctx::BuildContext, ::Val{:adjust_power})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_CHP[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, Q_CHP[t in time_index], lower_bound = 0.0, upper_bound = params.capacity * params.β)
    @variable(model, F_CHP[t in time_index])

    @constraint(model, [t in time_index], Q_CHP[t] == params.heat_demand[t])
    @constraint(model, [t in time_index], E_CHP[t] == F_CHP[t] * params.η_e)
    @constraint(model, [t in time_index], Q_CHP[t] == E_CHP[t] * params.β)

    if params.ramp_constraint_on
        define_chp_ramp_constraints!(model, time_index, E_CHP, params.ramp_ratio, params.capacity)
    end
    if params.min_constraint_on
        define_chp_min_constraints!(model, time_index, E_CHP, params.min_output_ratio, params.capacity)
    end

    adjust_objective_expr = define_chp_adjust_constraints!(model, time_index, E_CHP, params.capacity,
        params.adjust_limit, params.adjust_cost, ctx)

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_chp_om_cost!(model, time_index, E_CHP, params.om_cost)
    end
    if params.adjust_objective_on
        objective_expr += adjust_objective_expr
    end

    return objective_expr
end

function build_chp_status_model!(model, component::CombinedHeatPower, params, ctx::BuildContext, ::Val{:fixed_state})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_CHP[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, Q_CHP[t in time_index], lower_bound = 0.0, upper_bound = params.capacity * params.β)
    @variable(model, F_CHP[t in time_index])

    @constraint(model, [t in time_index], Q_CHP[t] == params.heat_demand[t])
    @constraint(model, [t in time_index], E_CHP[t] == F_CHP[t] * params.η_e)
    @constraint(model, [t in time_index], Q_CHP[t] == E_CHP[t] * params.β)

    if params.ramp_constraint_on
        define_chp_ramp_constraints!(model, time_index, E_CHP, params.ramp_ratio, params.capacity)
    end

    status_vector, on_off_objective_expr = define_chp_fixed_state_constraints!(
        model, time_index, E_CHP, params.on_off_cost, params.min_output_ratio, params.capacity, ctx)
    define_chp_min_constraints!(model, time_index, E_CHP, status_vector, params.min_output_ratio, params.capacity)

    adjust_objective_expr = @expression(model, 0.0)
    if params.adjust_constraint_on
        adjust_objective_expr = define_chp_adjust_constraints!(model, time_index, E_CHP, status_vector,
            params.capacity, params.adjust_limit, params.adjust_cost, ctx)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_chp_om_cost!(model, time_index, E_CHP, params.om_cost)
    end
    if params.on_off_objective_on
        objective_expr += on_off_objective_expr
    end
    if params.adjust_objective_on
        objective_expr += adjust_objective_expr
    end

    return objective_expr
end

function build_chp_status_model!(model, component::CombinedHeatPower, params, ctx::BuildContext, ::Val{:full_follow})
    time_index = generate_timespan(ctx.layer)
    planned_output = upper_layer_values(ctx, "E_CHP")

    @variable(model, E_CHP[t in time_index], lower_bound = planned_output[t], upper_bound = planned_output[t] + 1.0)
    @variable(model, Q_CHP[t in time_index])
    @variable(model, F_CHP[t in time_index])

    @constraint(model, [t in time_index], Q_CHP[t] == params.heat_demand[t])
    @constraint(model, [t in time_index], E_CHP[t] == F_CHP[t] * params.η_e)
    @constraint(model, [t in time_index], Q_CHP[t] == E_CHP[t] * params.β)

    on_off_objective_expr = @expression(model, 0.0)
    if params.on_off_constraint_on
        _, on_off_objective_expr = define_chp_follow_on_off_constraints!(
            model, time_index, planned_output, params.min_output_ratio, params.capacity, params.on_off_cost)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_chp_om_cost!(model, time_index, planned_output, params.om_cost)
    end
    if params.on_off_objective_on
        objective_expr += on_off_objective_expr
    end

    return objective_expr
end

function build_chp_status_model!(model, component::CombinedHeatPower, params, ctx::BuildContext, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    @variable(model, E_CHP[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    @variable(model, Q_CHP[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    @variable(model, F_CHP[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    return @expression(model, 0.0)
end

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function define_chp_om_cost!(model, time_index, output_power, om_cost)
    return @expression(model, C_chp_om, sum(output_power[t] * om_cost for t in time_index))
end

function define_chp_min_constraints!(model, time_index, output_power, min_output_ratio, capacity)
    @constraint(model, [t in time_index], output_power[t] >= min_output_ratio * capacity)
    return nothing
end

function define_chp_min_constraints!(model, time_index, output_power, status_vector, min_output_ratio, capacity)
    @constraint(model, [t in time_index], output_power[t] >= status_vector[t] * min_output_ratio * capacity)
    return nothing
end

function define_chp_ramp_constraints!(model, time_index, output_power, ramp_ratio, capacity)
    if length(time_index) <= 1
        return nothing
    end

    @variable(
        model,
        ΔE_CHP[t in time_index[1:(end-1)]],
        lower_bound = -ramp_ratio * capacity,
        upper_bound = ramp_ratio * capacity,
    )
    @constraint(model, [t in time_index[1:(end-1)]], ΔE_CHP[t] == output_power[t+1] - output_power[t])
    return nothing
end

function define_chp_on_off_constraints!(model, time_index, output_power, min_on_steps, min_off_steps, on_off_cost, capacity)
    @variable(model, γ_CHP[t in time_index], Bin)
    @variable(model, γ_CHP_start[t in time_index], Bin)
    @variable(model, γ_CHP_stop[t in time_index], Bin)

    @constraint(model, [t in time_index], output_power[t] <= γ_CHP[t] * capacity)
    @constraint(model, γ_CHP[first(time_index)] == γ_CHP_start[first(time_index)])
    @constraint(model, [t in time_index[2:end]], γ_CHP[t] - γ_CHP[t-1] == γ_CHP_start[t] - γ_CHP_stop[t])
    @constraint(model, [t in time_index], γ_CHP_start[t] + γ_CHP_stop[t] <= 1)

    if length(time_index) > min_on_steps
        @constraint(model, [t in time_index[(min_on_steps+1):end]], sum(γ_CHP_start[h] for h in (t-min_on_steps+1):t) <= γ_CHP[t])
    end

    if length(time_index) > min_off_steps
        @constraint(model, [t in time_index[(min_off_steps+1):end]], sum(γ_CHP_stop[h] for h in (t-min_off_steps+1):t) <= 1 - γ_CHP[t])
    end

    objective_expr = @expression(model, C_chp_on_off, sum((γ_CHP_start[t] + γ_CHP_stop[t]) * on_off_cost for t in time_index))
    return γ_CHP, objective_expr
end

function define_chp_fixed_state_constraints!(model, time_index, output_power, on_off_cost, min_output_ratio, capacity, ctx::BuildContext)
    planned_output = upper_layer_values(ctx, "E_CHP")
    status_vector = planned_output .> min_output_ratio * capacity

    @variable(model, γ_CHP_start[t in time_index], Bin)
    @variable(model, γ_CHP_stop[t in time_index], Bin)

    @constraint(model, [t in time_index], output_power[t] <= status_vector[t] * capacity)
    @constraint(model, status_vector[first(time_index)] == γ_CHP_start[first(time_index)])
    @constraint(model, [t in time_index[2:end]], status_vector[t] - status_vector[t-1] == γ_CHP_start[t] - γ_CHP_stop[t])
    @constraint(model, [t in time_index], γ_CHP_start[t] + γ_CHP_stop[t] <= 1)

    objective_expr = @expression(model, C_chp_on_off, sum((γ_CHP_start[t] + γ_CHP_stop[t]) * on_off_cost for t in time_index))
    return status_vector, objective_expr
end

function define_chp_follow_on_off_constraints!(model, time_index, planned_output::Vector{Float64}, min_output_ratio, capacity, on_off_cost)
    status_vector = planned_output .> min_output_ratio * capacity

    @variable(model, γ_CHP_start[t in time_index], Bin)
    @variable(model, γ_CHP_stop[t in time_index], Bin)

    @constraint(model, status_vector[first(time_index)] == γ_CHP_start[first(time_index)])
    @constraint(model, [t in time_index[2:end]], status_vector[t] - status_vector[t-1] == γ_CHP_start[t] - γ_CHP_stop[t])
    @constraint(model, [t in time_index], γ_CHP_start[t] + γ_CHP_stop[t] <= 1)

    objective_expr = @expression(model, C_chp_on_off, sum((γ_CHP_start[t] + γ_CHP_stop[t]) * on_off_cost for t in time_index))
    return status_vector, objective_expr
end

function define_chp_adjust_constraints!(model, time_index, output_power, capacity, adjust_limit, adjust_cost, ctx::BuildContext)
    planned_output = upper_layer_values(ctx, "E_CHP")

    @variable(model, δ_CHP[t in time_index], Bin)
    @variable(model, δ_CHP_up[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)
    @variable(model, δ_CHP_down[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)

    @constraint(model, [t in time_index], output_power[t] == planned_output[t] + δ_CHP_up[t] - δ_CHP_down[t])
    @constraint(model, [t in time_index], δ_CHP_up[t] <= BIG_M * δ_CHP[t])
    @constraint(model, [t in time_index], δ_CHP_down[t] <= BIG_M * (1 - δ_CHP[t]))

    return @expression(model, C_chp_adjust, sum(δ_CHP_up[t] + δ_CHP_down[t] for t in time_index) * adjust_cost)
end

function define_chp_adjust_constraints!(model, time_index, output_power, status_vector, capacity, adjust_limit, adjust_cost, ctx::BuildContext)
    planned_output = upper_layer_values(ctx, "E_CHP")
    active_periods = [t for t in time_index if status_vector[t]]

    if isempty(active_periods)
        return @expression(model, 0.0)
    end

    @variable(model, δ_CHP[t in active_periods], Bin)
    @variable(model, δ_CHP_up[t in active_periods], lower_bound = 0.0, upper_bound = adjust_limit * capacity)
    @variable(model, δ_CHP_down[t in active_periods], lower_bound = 0.0, upper_bound = adjust_limit * capacity)

    @constraint(model, [t in active_periods], output_power[t] == planned_output[t] + δ_CHP_up[t] - δ_CHP_down[t])
    @constraint(model, [t in active_periods], δ_CHP_up[t] <= BIG_M * δ_CHP[t])
    @constraint(model, [t in active_periods], δ_CHP_down[t] <= BIG_M * (1 - δ_CHP[t]))

    return @expression(model, C_chp_adjust, sum(δ_CHP_up[t] + δ_CHP_down[t] for t in active_periods) * adjust_cost)
end
