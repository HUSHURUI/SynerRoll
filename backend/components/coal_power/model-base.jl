# ═══════════════════════════════════════════════════════════════════════════
# coal_power/model-base.jl — 数学原理蓝图
#
# 本文件是燃煤机组模型的原始实现，变量名无后缀，用于：
#   - 单实例场景的数学功能验证
#   - 理解模型的数学原理
#
# 共享函数（resolve_coal_power_params）见 model-common.jl
# 对应的元编程追踪版本见 model.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::CoalPower, ctx::BuildContext)
    params = resolve_coal_power_params(component, ctx)
    return build_coal_power_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_CP[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, F_CP[t in time_index])
    @constraint(model, [t in time_index], E_CP[t] == F_CP[t] * params.efficiency)

    if params.ramp_constraint_on
        define_cp_ramp_constraints!(model, time_index, E_CP, params.ramp_ratio, params.capacity)
    end

    on_off_objective_expr = @expression(model, 0.0)
    if params.on_off_constraint_on
        status_vector, on_off_objective_expr = define_cp_on_off_constraints!(
            model, time_index, E_CP, params.min_on_steps, params.min_off_steps,
            params.on_off_cost, params.capacity)
        define_cp_min_constraints!(model, time_index, E_CP, status_vector, params.min_output_ratio, params.capacity)
    elseif params.min_constraint_on
        define_cp_min_constraints!(model, time_index, E_CP, params.min_output_ratio, params.capacity)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cp_om_cost!(model, time_index, E_CP, params.om_cost)
    end
    if params.on_off_objective_on
        objective_expr += on_off_objective_expr
    end

    return objective_expr
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext, ::Val{:adjust_power})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_CP[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, F_CP[t in time_index])
    @constraint(model, [t in time_index], E_CP[t] == F_CP[t] * params.efficiency)

    if params.ramp_constraint_on
        define_cp_ramp_constraints!(model, time_index, E_CP, params.ramp_ratio, params.capacity)
    end
    if params.min_constraint_on
        define_cp_min_constraints!(model, time_index, E_CP, params.min_output_ratio, params.capacity)
    end

    adjust_objective_expr = define_cp_adjust_constraints!(model, time_index, E_CP, params.capacity,
        params.adjust_limit, params.adjust_cost, ctx)

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cp_om_cost!(model, time_index, E_CP, params.om_cost)
    end
    if params.adjust_objective_on
        objective_expr += adjust_objective_expr
    end

    return objective_expr
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext, ::Val{:fixed_state})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_CP[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, F_CP[t in time_index])
    @constraint(model, [t in time_index], E_CP[t] == F_CP[t] * params.efficiency)

    if params.ramp_constraint_on
        define_cp_ramp_constraints!(model, time_index, E_CP, params.ramp_ratio, params.capacity)
    end

    status_vector, on_off_objective_expr = define_cp_fixed_state_constraints!(
        model, time_index, E_CP, params.on_off_cost, params.min_output_ratio, params.capacity, ctx)
    define_cp_min_constraints!(model, time_index, E_CP, status_vector, params.min_output_ratio, params.capacity)

    adjust_objective_expr = @expression(model, 0.0)
    if params.adjust_constraint_on
        adjust_objective_expr = define_cp_adjust_constraints!(model, time_index, E_CP, status_vector,
            params.capacity, params.adjust_limit, params.adjust_cost, ctx)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cp_om_cost!(model, time_index, E_CP, params.om_cost)
    end
    if params.on_off_objective_on
        objective_expr += on_off_objective_expr
    end
    if params.adjust_objective_on
        objective_expr += adjust_objective_expr
    end

    return objective_expr
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext, ::Val{:full_follow})
    time_index = generate_timespan(ctx.layer)
    planned_output = upper_layer_values(ctx, "E_CP")

    @variable(model, E_CP[t in time_index], lower_bound = planned_output[t], upper_bound = planned_output[t] + 1.0)
    @variable(model, F_CP[t in time_index])
    @constraint(model, [t in time_index], E_CP[t] == F_CP[t] * params.efficiency)

    on_off_objective_expr = @expression(model, 0.0)
    if params.on_off_constraint_on
        _, on_off_objective_expr = define_cp_follow_on_off_constraints!(
            model, time_index, planned_output, params.min_output_ratio, params.capacity, params.on_off_cost)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cp_om_cost!(model, time_index, planned_output, params.om_cost)
    end
    if params.on_off_objective_on
        objective_expr += on_off_objective_expr
    end

    return objective_expr
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    @variable(model, E_CP[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    @variable(model, F_CP[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    return @expression(model, 0.0)
end

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function define_cp_om_cost!(model, time_index, output_power, om_cost)
    return @expression(model, C_cp_om, sum(output_power[t] * om_cost for t in time_index))
end

function define_cp_min_constraints!(model, time_index, output_power, min_output_ratio, capacity)
    @constraint(model, [t in time_index], output_power[t] >= min_output_ratio * capacity)
    return nothing
end

function define_cp_min_constraints!(model, time_index, output_power, status_vector, min_output_ratio, capacity)
    @constraint(model, [t in time_index], output_power[t] >= status_vector[t] * min_output_ratio * capacity)
    return nothing
end

function define_cp_ramp_constraints!(model, time_index, output_power, ramp_ratio, capacity)
    if length(time_index) <= 1
        return nothing
    end

    @variable(
        model,
        ΔE_CP[t in time_index[1:(end-1)]],
        lower_bound = -ramp_ratio * capacity,
        upper_bound = ramp_ratio * capacity,
    )
    @constraint(model, [t in time_index[1:(end-1)]], ΔE_CP[t] == output_power[t+1] - output_power[t])
    return nothing
end

function define_cp_on_off_constraints!(model, time_index, output_power, min_on_steps, min_off_steps, on_off_cost, capacity)
    @variable(model, γ_CP[t in time_index], Bin)
    @variable(model, γ_CP_start[t in time_index], Bin)
    @variable(model, γ_CP_stop[t in time_index], Bin)

    @constraint(model, [t in time_index], output_power[t] <= γ_CP[t] * capacity)
    @constraint(model, γ_CP[first(time_index)] == γ_CP_start[first(time_index)])
    @constraint(model, [t in time_index[2:end]], γ_CP[t] - γ_CP[t-1] == γ_CP_start[t] - γ_CP_stop[t])
    @constraint(model, [t in time_index], γ_CP_start[t] + γ_CP_stop[t] <= 1)

    if length(time_index) > min_on_steps
        @constraint(model, [t in time_index[(min_on_steps+1):end]], sum(γ_CP_start[h] for h in (t-min_on_steps+1):t) <= γ_CP[t])
    end

    if length(time_index) > min_off_steps
        @constraint(model, [t in time_index[(min_off_steps+1):end]], sum(γ_CP_stop[h] for h in (t-min_off_steps+1):t) <= 1 - γ_CP[t])
    end

    objective_expr = @expression(model, C_cp_on_off, sum((γ_CP_start[t] + γ_CP_stop[t]) * on_off_cost for t in time_index))
    return γ_CP, objective_expr
end

function define_cp_fixed_state_constraints!(model, time_index, output_power, on_off_cost, min_output_ratio, capacity, ctx::BuildContext)
    planned_output = upper_layer_values(ctx, "E_CP")
    status_vector = planned_output .> min_output_ratio * capacity

    @variable(model, γ_CP_start[t in time_index], Bin)
    @variable(model, γ_CP_stop[t in time_index], Bin)

    @constraint(model, [t in time_index], output_power[t] <= status_vector[t] * capacity)
    @constraint(model, status_vector[first(time_index)] == γ_CP_start[first(time_index)])
    @constraint(model, [t in time_index[2:end]], status_vector[t] - status_vector[t-1] == γ_CP_start[t] - γ_CP_stop[t])
    @constraint(model, [t in time_index], γ_CP_start[t] + γ_CP_stop[t] <= 1)

    objective_expr = @expression(model, C_cp_on_off, sum((γ_CP_start[t] + γ_CP_stop[t]) * on_off_cost for t in time_index))
    return status_vector, objective_expr
end

function define_cp_follow_on_off_constraints!(model, time_index, planned_output::Vector{Float64}, min_output_ratio, capacity, on_off_cost)
    status_vector = planned_output .> min_output_ratio * capacity

    @variable(model, γ_CP_start[t in time_index], Bin)
    @variable(model, γ_CP_stop[t in time_index], Bin)

    @constraint(model, status_vector[first(time_index)] == γ_CP_start[first(time_index)])
    @constraint(model, [t in time_index[2:end]], status_vector[t] - status_vector[t-1] == γ_CP_start[t] - γ_CP_stop[t])
    @constraint(model, [t in time_index], γ_CP_start[t] + γ_CP_stop[t] <= 1)

    objective_expr = @expression(model, C_cp_on_off, sum((γ_CP_start[t] + γ_CP_stop[t]) * on_off_cost for t in time_index))
    return status_vector, objective_expr
end

function define_cp_adjust_constraints!(model, time_index, output_power, capacity, adjust_limit, adjust_cost, ctx::BuildContext)
    planned_output = upper_layer_values(ctx, "E_CP")

    @variable(model, δ_CP[t in time_index], Bin)
    @variable(model, δ_CP_up[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)
    @variable(model, δ_CP_down[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)

    @constraint(model, [t in time_index], output_power[t] == planned_output[t] + δ_CP_up[t] - δ_CP_down[t])
    @constraint(model, [t in time_index], δ_CP_up[t] <= BIG_M * δ_CP[t])
    @constraint(model, [t in time_index], δ_CP_down[t] <= BIG_M * (1 - δ_CP[t]))

    return @expression(model, C_cp_adjust, sum(δ_CP_up[t] + δ_CP_down[t] for t in time_index) * adjust_cost)
end

function define_cp_adjust_constraints!(model, time_index, output_power, status_vector, capacity, adjust_limit, adjust_cost, ctx::BuildContext)
    planned_output = upper_layer_values(ctx, "E_CP")
    active_periods = [t for t in time_index if status_vector[t]]

    if isempty(active_periods)
        return @expression(model, 0.0)
    end

    @variable(model, δ_CP[t in active_periods], Bin)
    @variable(model, δ_CP_up[t in active_periods], lower_bound = 0.0, upper_bound = adjust_limit * capacity)
    @variable(model, δ_CP_down[t in active_periods], lower_bound = 0.0, upper_bound = adjust_limit * capacity)

    @constraint(model, [t in active_periods], output_power[t] == planned_output[t] + δ_CP_up[t] - δ_CP_down[t])
    @constraint(model, [t in active_periods], δ_CP_up[t] <= BIG_M * δ_CP[t])
    @constraint(model, [t in active_periods], δ_CP_down[t] <= BIG_M * (1 - δ_CP[t]))

    return @expression(model, C_cp_adjust, sum(δ_CP_up[t] + δ_CP_down[t] for t in active_periods) * adjust_cost)
end
