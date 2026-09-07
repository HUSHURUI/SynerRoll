# ═══════════════════════════════════════════════════════════════════════════
# electrolyzer/model-base.jl — 数学原理蓝图
#
# 本文件是电解槽模型的原始实现，变量名无后缀，用于：
#   - 单实例场景的数学功能验证
#   - 理解模型的数学原理
#
# 数学关系：
#   H_ET[t] = E_ET[t] × η    （产氢量 = 耗电量 × 效率）
#
# 共享函数（resolve_electrolyzer_params）见 model-common.jl
# 对应的元编程追踪版本见 model.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::Electrolyzer, ctx::BuildContext)
    params = resolve_electrolyzer_params(component, ctx)
    return build_electrolyzer_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_electrolyzer_status_model!(model, component::Electrolyzer, params, ctx::BuildContext, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_ET[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, H_ET[t in time_index])
    @constraint(model, [t in time_index], H_ET[t] == E_ET[t] * params.efficiency)

    if params.ramp_constraint_on
        define_et_ramp_constraints!(model, time_index, E_ET, params.ramp_ratio, params.capacity)
    end

    on_off_objective_expr = @expression(model, 0.0)
    if params.on_off_constraint_on
        status_vector, on_off_objective_expr = define_et_on_off_constraints!(
            model, time_index, E_ET, params.min_on_steps, params.min_off_steps,
            params.on_off_cost, params.capacity)
        define_et_min_constraints!(model, time_index, E_ET, status_vector, params.min_output_ratio, params.capacity)
    elseif params.min_constraint_on
        define_et_min_constraints!(model, time_index, E_ET, params.min_output_ratio, params.capacity)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_et_om_cost!(model, time_index, E_ET, params.om_cost)
    end
    if params.on_off_objective_on
        objective_expr += on_off_objective_expr
    end

    return objective_expr
end

function build_electrolyzer_status_model!(model, component::Electrolyzer, params, ctx::BuildContext, ::Val{:adjust_power})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_ET[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, H_ET[t in time_index])
    @constraint(model, [t in time_index], H_ET[t] == E_ET[t] * params.efficiency)

    if params.ramp_constraint_on
        define_et_ramp_constraints!(model, time_index, E_ET, params.ramp_ratio, params.capacity)
    end
    if params.min_constraint_on
        define_et_min_constraints!(model, time_index, E_ET, params.min_output_ratio, params.capacity)
    end

    adjust_objective_expr = define_et_adjust_constraints!(model, time_index, E_ET, params.capacity,
        params.adjust_limit, params.adjust_cost, ctx)

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_et_om_cost!(model, time_index, E_ET, params.om_cost)
    end
    if params.adjust_objective_on
        objective_expr += adjust_objective_expr
    end

    return objective_expr
end

function build_electrolyzer_status_model!(model, component::Electrolyzer, params, ctx::BuildContext, ::Val{:fixed_state})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_ET[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, H_ET[t in time_index])
    @constraint(model, [t in time_index], H_ET[t] == E_ET[t] * params.efficiency)

    if params.ramp_constraint_on
        define_et_ramp_constraints!(model, time_index, E_ET, params.ramp_ratio, params.capacity)
    end

    status_vector, on_off_objective_expr = define_et_fixed_state_constraints!(
        model, time_index, E_ET, params.on_off_cost, params.min_output_ratio, params.capacity, ctx)
    define_et_min_constraints!(model, time_index, E_ET, status_vector, params.min_output_ratio, params.capacity)

    adjust_objective_expr = @expression(model, 0.0)
    if params.adjust_constraint_on
        adjust_objective_expr = define_et_adjust_constraints!(model, time_index, E_ET, status_vector,
            params.capacity, params.adjust_limit, params.adjust_cost, ctx)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_et_om_cost!(model, time_index, E_ET, params.om_cost)
    end
    if params.on_off_objective_on
        objective_expr += on_off_objective_expr
    end
    if params.adjust_objective_on
        objective_expr += adjust_objective_expr
    end

    return objective_expr
end

function build_electrolyzer_status_model!(model, component::Electrolyzer, params, ctx::BuildContext, ::Val{:full_follow})
    time_index = generate_timespan(ctx.layer)
    planned_output = upper_layer_values(ctx, "E_ET")

    @variable(model, E_ET[t in time_index], lower_bound = planned_output[t], upper_bound = planned_output[t] + 1.0)
    @variable(model, H_ET[t in time_index])
    @constraint(model, [t in time_index], H_ET[t] == E_ET[t] * params.efficiency)

    on_off_objective_expr = @expression(model, 0.0)
    if params.on_off_constraint_on
        _, on_off_objective_expr = define_et_follow_on_off_constraints!(
            model, time_index, planned_output, params.min_output_ratio, params.capacity, params.on_off_cost)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_et_om_cost!(model, time_index, planned_output, params.om_cost)
    end
    if params.on_off_objective_on
        objective_expr += on_off_objective_expr
    end

    return objective_expr
end

function build_electrolyzer_status_model!(model, component::Electrolyzer, params, ctx::BuildContext, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    @variable(model, E_ET[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    @variable(model, H_ET[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    return @expression(model, 0.0)
end

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function define_et_om_cost!(model, time_index, input_power, om_cost)
    return @expression(model, C_et_om, sum(input_power[t] * om_cost for t in time_index))
end

function define_et_min_constraints!(model, time_index, input_power, min_output_ratio, capacity)
    @constraint(model, [t in time_index], input_power[t] >= min_output_ratio * capacity)
    return nothing
end

function define_et_min_constraints!(model, time_index, input_power, status_vector, min_output_ratio, capacity)
    @constraint(model, [t in time_index], input_power[t] >= status_vector[t] * min_output_ratio * capacity)
    return nothing
end

function define_et_ramp_constraints!(model, time_index, input_power, ramp_ratio, capacity)
    if length(time_index) <= 1
        return nothing
    end

    @variable(
        model,
        ΔE_ET[t in time_index[1:(end-1)]],
        lower_bound = -ramp_ratio * capacity,
        upper_bound = ramp_ratio * capacity,
    )
    @constraint(model, [t in time_index[1:(end-1)]], ΔE_ET[t] == input_power[t+1] - input_power[t])
    return nothing
end

function define_et_on_off_constraints!(model, time_index, input_power, min_on_steps, min_off_steps, on_off_cost, capacity)
    @variable(model, γ_ET[t in time_index], Bin)
    @variable(model, γ_ET_start[t in time_index], Bin)
    @variable(model, γ_ET_stop[t in time_index], Bin)

    @constraint(model, [t in time_index], input_power[t] <= γ_ET[t] * capacity)
    @constraint(model, γ_ET[first(time_index)] == γ_ET_start[first(time_index)])
    @constraint(model, [t in time_index[2:end]], γ_ET[t] - γ_ET[t-1] == γ_ET_start[t] - γ_ET_stop[t])
    @constraint(model, [t in time_index], γ_ET_start[t] + γ_ET_stop[t] <= 1)

    if length(time_index) > min_on_steps
        @constraint(model, [t in time_index[(min_on_steps+1):end]], sum(γ_ET_start[h] for h in (t-min_on_steps+1):t) <= γ_ET[t])
    end

    if length(time_index) > min_off_steps
        @constraint(model, [t in time_index[(min_off_steps+1):end]], sum(γ_ET_stop[h] for h in (t-min_off_steps+1):t) <= 1 - γ_ET[t])
    end

    objective_expr = @expression(model, C_et_on_off, sum((γ_ET_start[t] + γ_ET_stop[t]) * on_off_cost for t in time_index))
    return γ_ET, objective_expr
end

function define_et_fixed_state_constraints!(model, time_index, input_power, on_off_cost, min_output_ratio, capacity, ctx::BuildContext)
    planned_output = upper_layer_values(ctx, "E_ET")
    status_vector = planned_output .> min_output_ratio * capacity

    @variable(model, γ_ET_start[t in time_index], Bin)
    @variable(model, γ_ET_stop[t in time_index], Bin)

    @constraint(model, [t in time_index], input_power[t] <= status_vector[t] * capacity)
    @constraint(model, status_vector[first(time_index)] == γ_ET_start[first(time_index)])
    @constraint(model, [t in time_index[2:end]], status_vector[t] - status_vector[t-1] == γ_ET_start[t] - γ_ET_stop[t])
    @constraint(model, [t in time_index], γ_ET_start[t] + γ_ET_stop[t] <= 1)

    objective_expr = @expression(model, C_et_on_off, sum((γ_ET_start[t] + γ_ET_stop[t]) * on_off_cost for t in time_index))
    return status_vector, objective_expr
end

function define_et_follow_on_off_constraints!(model, time_index, planned_output::Vector{Float64}, min_output_ratio, capacity, on_off_cost)
    status_vector = planned_output .> min_output_ratio * capacity

    @variable(model, γ_ET_start[t in time_index], Bin)
    @variable(model, γ_ET_stop[t in time_index], Bin)

    @constraint(model, status_vector[first(time_index)] == γ_ET_start[first(time_index)])
    @constraint(model, [t in time_index[2:end]], status_vector[t] - status_vector[t-1] == γ_ET_start[t] - γ_ET_stop[t])
    @constraint(model, [t in time_index], γ_ET_start[t] + γ_ET_stop[t] <= 1)

    objective_expr = @expression(model, C_et_on_off, sum((γ_ET_start[t] + γ_ET_stop[t]) * on_off_cost for t in time_index))
    return status_vector, objective_expr
end

function define_et_adjust_constraints!(model, time_index, input_power, capacity, adjust_limit, adjust_cost, ctx::BuildContext)
    planned_output = upper_layer_values(ctx, "E_ET")

    @variable(model, δ_ET[t in time_index], Bin)
    @variable(model, δ_ET_up[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)
    @variable(model, δ_ET_down[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)

    @constraint(model, [t in time_index], input_power[t] == planned_output[t] + δ_ET_up[t] - δ_ET_down[t])
    @constraint(model, [t in time_index], δ_ET_up[t] <= BIG_M * δ_ET[t])
    @constraint(model, [t in time_index], δ_ET_down[t] <= BIG_M * (1 - δ_ET[t]))

    return @expression(model, C_et_adjust, sum(δ_ET_up[t] + δ_ET_down[t] for t in time_index) * adjust_cost)
end

function define_et_adjust_constraints!(model, time_index, input_power, status_vector, capacity, adjust_limit, adjust_cost, ctx::BuildContext)
    planned_output = upper_layer_values(ctx, "E_ET")
    active_periods = [t for t in time_index if status_vector[t]]

    if isempty(active_periods)
        return @expression(model, 0.0)
    end

    @variable(model, δ_ET[t in active_periods], Bin)
    @variable(model, δ_ET_up[t in active_periods], lower_bound = 0.0, upper_bound = adjust_limit * capacity)
    @variable(model, δ_ET_down[t in active_periods], lower_bound = 0.0, upper_bound = adjust_limit * capacity)

    @constraint(model, [t in active_periods], input_power[t] == planned_output[t] + δ_ET_up[t] - δ_ET_down[t])
    @constraint(model, [t in active_periods], δ_ET_up[t] <= BIG_M * δ_ET[t])
    @constraint(model, [t in active_periods], δ_ET_down[t] <= BIG_M * (1 - δ_ET[t]))

    return @expression(model, C_et_adjust, sum(δ_ET_up[t] + δ_ET_down[t] for t in active_periods) * adjust_cost)
end
