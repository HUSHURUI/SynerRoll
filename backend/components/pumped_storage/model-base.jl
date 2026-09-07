# ═══════════════════════════════════════════════════════════════════════════
# pumped_storage/model-base.jl — 数学原理蓝图
#
# 本文件是抽水蓄能模型的原始实现，变量名无后缀，用于：
#   - 单实例场景的数学功能验证
#   - 理解模型的数学原理
#
# 共享函数（resolve_pumped_storage_params, derive_pumped_storage_state）见 model-common.jl
# 对应的元编程追踪版本见 model.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::PumpedStorage, ctx::BuildContext)
    params = resolve_pumped_storage_params(component, ctx)
    return build_pumped_storage_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_pumped_storage_status_model!(model, component::PumpedStorage, params, ctx::BuildContext, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_PS[t in time_index], lower_bound = 0.0, upper_bound = params.max_soc * params.storage_capacity)
    @variable(model, E_PS_in[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, E_PS_out[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, γ_PS[t in time_index], Bin)

    if params.min_constraint_on
        define_ps_min_constraints!(model, time_index, E_PS, params.min_soc, params.storage_capacity)
    end

    if params.ramp_constraint_on
        define_ps_ramp_constraints!(model, time_index, E_PS_in, E_PS_out,
            params.ramp_ratio, params.capacity, params.time_step_hours)
    end

    if params.start_end_equality_constraint_on
        define_ps_start_end_equality_constraints!(model, time_index, E_PS)
    end

    define_ps_initial_constraints!(model, time_index, E_PS, params.initial_soc, params.storage_capacity, ctx)
    define_ps_energy_conservation_constraints!(model, time_index, E_PS, E_PS_in, E_PS_out, γ_PS,
        params.efficiency, params.loss, params.time_step_hours)

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_ps_om_cost!(model, time_index, E_PS_in, E_PS_out, params.om_cost)
    end

    return objective_expr
end

function build_pumped_storage_status_model!(model, component::PumpedStorage, params, ctx::BuildContext, ::Val{:fixed_state})
    time_index = generate_timespan(ctx.layer)
    planned_input = upper_layer_values(ctx, "E_PS_in")
    planned_output = upper_layer_values(ctx, "E_PS_out")
    γ_PS = derive_pumped_storage_state(planned_input, planned_output)

    @variable(model, E_PS[t in time_index], lower_bound = 0.0, upper_bound = params.max_soc * params.storage_capacity)
    @variable(model, E_PS_in[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)
    @variable(model, E_PS_out[t in time_index], lower_bound = 0.0, upper_bound = params.capacity)

    if params.min_constraint_on
        define_ps_min_constraints!(model, time_index, E_PS, params.min_soc, params.storage_capacity)
    end

    if params.ramp_constraint_on
        define_ps_ramp_constraints!(model, time_index, E_PS_in, E_PS_out,
            params.ramp_ratio, params.capacity, params.time_step_hours)
    end

    define_ps_initial_constraints!(model, time_index, E_PS, params.initial_soc, params.storage_capacity, ctx)
    define_ps_energy_conservation_constraints!(model, time_index, E_PS, E_PS_in, E_PS_out, γ_PS,
        params.efficiency, params.loss, params.time_step_hours)

    adjust_objective_expr = @expression(model, 0.0)
    if params.adjust_constraint_on
        adjust_objective_expr = define_ps_adjust_constraints!(
            model, time_index, E_PS_in, E_PS_out, planned_input, planned_output, γ_PS,
            params.capacity, params.adjust_limit, params.adjust_cost)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_ps_om_cost!(model, time_index, E_PS_in, E_PS_out, params.om_cost)
    end
    if params.adjust_objective_on
        objective_expr += adjust_objective_expr
    end

    return objective_expr
end

function build_pumped_storage_status_model!(model, component::PumpedStorage, params, ctx::BuildContext, ::Val{:full_follow})
    time_index = generate_timespan(ctx.layer)
    planned_input = upper_layer_values(ctx, "E_PS_in")
    planned_output = upper_layer_values(ctx, "E_PS_out")

    @variable(model, E_PS[t in time_index], lower_bound = 0.0, upper_bound = params.max_soc * params.storage_capacity)
    @variable(model, E_PS_in[t in time_index], lower_bound = planned_input[t], upper_bound = planned_input[t] + 1.0)
    @variable(model, E_PS_out[t in time_index], lower_bound = planned_output[t], upper_bound = planned_output[t] + 1.0)

    if params.min_constraint_on
        define_ps_min_constraints!(model, time_index, E_PS, params.min_soc, params.storage_capacity)
    end

    define_ps_initial_constraints!(model, time_index, E_PS, params.initial_soc, params.storage_capacity, ctx)
    define_ps_energy_conservation_constraints!(model, time_index, E_PS, planned_input, planned_output,
        params.efficiency, params.loss, params.time_step_hours)

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_ps_om_cost!(model, time_index, planned_input, planned_output, params.om_cost)
    end

    return objective_expr
end

function build_pumped_storage_status_model!(model, component::PumpedStorage, params, ctx::BuildContext, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    @variable(model, E_PS[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    @variable(model, E_PS_in[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    @variable(model, E_PS_out[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    return @expression(model, 0.0)
end

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function define_ps_om_cost!(model, time_index, input_power, output_power, om_cost)
    return @expression(model, C_ps_om, sum((input_power[t] + output_power[t]) * om_cost for t in time_index))
end

function define_ps_min_constraints!(model, time_index, stored_energy, min_soc, capacity)
    @constraint(model, [t in time_index], stored_energy[t] >= min_soc * capacity)
    return nothing
end

# 爬坡约束：限制相邻时段净功率（发电 − 抽水）的变化幅度。
# 额定功率静态上限由 E_PS_in / E_PS_out 的变量上界（params.capacity）承担；
# 本函数只负责 |P_net[t+1] − P_net[t]| ≤ ramp × capacity × Δt。
function define_ps_ramp_constraints!(model, time_index, input_power, output_power, ramp_ratio, capacity, time_step_hours)
    if length(time_index) <= 1
        return nothing
    end

    ramp_limit = ramp_ratio * capacity * time_step_hours
    @variable(
        model,
        ΔE_PS[t in time_index[1:(end-1)]],
        lower_bound = -ramp_limit,
        upper_bound = ramp_limit,
    )
    @constraint(model, [t in time_index[1:(end-1)]],
        ΔE_PS[t] == (output_power[t+1] - input_power[t+1]) - (output_power[t] - input_power[t]))
    return nothing
end

function define_ps_start_end_equality_constraints!(model, time_index, stored_energy)
    @constraint(model, stored_energy[first(time_index)] == stored_energy[last(time_index)])
    return nothing
end

function define_ps_initial_constraints!(model, time_index, stored_energy, initial_soc, capacity, ctx::BuildContext)
    storage_ts = current_layer_storage_value(ctx)
    if isnothing(storage_ts)
        @constraint(model, stored_energy[first(time_index)] == capacity * initial_soc)
    else
        @constraint(model, stored_energy[first(time_index)] == get_value(storage_ts, ctx.time))
    end
    return nothing
end

function define_ps_energy_conservation_constraints!(model, time_index, stored_energy, input_power, output_power,
    state_switch, efficiency, loss, time_step_hours)
    if length(time_index) > 1
        @constraint(model, [t in time_index[2:end]], stored_energy[t] == stored_energy[t-1] * (1 - loss) +
            (input_power[t-1] * efficiency - output_power[t-1] / efficiency) * time_step_hours)
    end
    @constraint(model, [t in time_index], input_power[t] <= BIG_M * state_switch[t])
    @constraint(model, [t in time_index], output_power[t] <= BIG_M * (1 - state_switch[t]))
    return nothing
end

function define_ps_energy_conservation_constraints!(model, time_index, stored_energy, input_power, output_power,
    γ_PS::Vector{Float64}, efficiency, loss, time_step_hours)
    if length(time_index) > 1
        @constraint(model, [t in time_index[2:end]], stored_energy[t] == stored_energy[t-1] * (1 - loss) +
            (input_power[t-1] * efficiency - output_power[t-1] / efficiency) * time_step_hours)
    end

    @constraint(model, [t in time_index], input_power[t] <= BIG_M * (γ_PS[t] + 1) / 2)
    @constraint(model, [t in time_index], output_power[t] <= BIG_M * (1 - γ_PS[t]) / 2)
    @constraint(model, [t in time_index], input_power[t] <= BIG_M * γ_PS[t]^2)
    @constraint(model, [t in time_index], output_power[t] <= BIG_M * γ_PS[t]^2)
    return nothing
end

function define_ps_energy_conservation_constraints!(model, time_index, stored_energy,
    planned_input::Vector{Float64}, planned_output::Vector{Float64}, efficiency, loss, time_step_hours)
    if length(time_index) > 1
        @constraint(model, [t in time_index[2:end]], stored_energy[t] == stored_energy[t-1] * (1 - loss) +
            (planned_input[t-1] * efficiency - planned_output[t-1] / efficiency) * time_step_hours)
    end
    return nothing
end

function define_ps_adjust_constraints!(model, time_index, input_power, output_power, planned_input, planned_output, γ_PS::Vector{Float64}, capacity, adjust_limit, adjust_cost)
    @variable(model, δ_PS[t in time_index], Bin)
    @variable(model, δ_PS_up[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)
    @variable(model, δ_PS_down[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)

    @constraint(
        model,
        [t in time_index],
        input_power[t] == planned_input[t] * (γ_PS[t] == 1.0) + δ_PS_up[t] * (γ_PS[t] == 1.0) - δ_PS_down[t] * (γ_PS[t] == 1.0),
    )
    @constraint(
        model,
        [t in time_index],
        output_power[t] == planned_output[t] * (γ_PS[t] == -1.0) + δ_PS_up[t] * (γ_PS[t] == -1.0) - δ_PS_down[t] * (γ_PS[t] == -1.0),
    )
    @constraint(model, [t in time_index], δ_PS_up[t] <= BIG_M * abs(γ_PS[t]))
    @constraint(model, [t in time_index], δ_PS_down[t] <= BIG_M * abs(γ_PS[t]))
    @constraint(model, [t in time_index], δ_PS_up[t] <= BIG_M * δ_PS[t])
    @constraint(model, [t in time_index], δ_PS_down[t] <= BIG_M * (1 - δ_PS[t]))

    return @expression(model, C_ps_adjust, sum(δ_PS_up[t] + δ_PS_down[t] for t in time_index) * adjust_cost)
end
