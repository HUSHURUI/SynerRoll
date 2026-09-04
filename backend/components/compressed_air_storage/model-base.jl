# ═══════════════════════════════════════════════════════════════════════════
# compressed_air_storage/model-base.jl — 数学原理蓝图
#
# 本文件是压缩空气储能模型的原始实现，变量名无后缀，用于：
#   - 单实例场景的数学功能验证
#   - 理解模型的数学原理
#
# 共享函数（resolve_compressed_air_storage_params, derive_cas_storage_state）见 model-common.jl
# 对应的元编程追踪版本见 model.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::CompressedAirStorage, ctx::BuildContext)
    params = resolve_compressed_air_storage_params(component, ctx)
    return build_compressed_air_storage_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_compressed_air_storage_status_model!(model, component::CompressedAirStorage, params, ctx::BuildContext, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)

    @variable(model, E_CS[t in time_index], lower_bound = 0.0, upper_bound = params.max_soc * params.capacity)
    @variable(model, E_CS_in[t in time_index], lower_bound = 0.0)
    @variable(model, E_CS_out[t in time_index], lower_bound = 0.0)
    @variable(model, γ_CAS[t in time_index], Bin)

    if params.min_constraint_on
        define_cas_min_constraints!(model, time_index, E_CS, params.min_soc, params.capacity)
    end

    if params.ramp_constraint_on
        define_cas_ramp_constraints!(model, time_index, E_CS_in, E_CS_out, params.ramp_ratio, params.capacity)
    end

    if params.start_end_equality_constraint_on
        define_cas_start_end_equality_constraints!(model, time_index, E_CS)
    end

    define_cas_initial_constraints!(model, time_index, E_CS, params.initial_soc, params.capacity, ctx)
    define_cas_energy_conservation_constraints!(model, time_index, E_CS, E_CS_in, E_CS_out, γ_CAS,
        params.efficiency, params.loss, params.time_step_hours)

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cas_om_cost!(model, time_index, E_CS_in, E_CS_out, params.om_cost)
    end

    return objective_expr
end

function build_compressed_air_storage_status_model!(model, component::CompressedAirStorage, params, ctx::BuildContext, ::Val{:fixed_state})
    time_index = generate_timespan(ctx.layer)
    planned_input = upper_layer_values(ctx, "E_CS_in")
    planned_output = upper_layer_values(ctx, "E_CS_out")
    γ_CAS = derive_cas_storage_state(planned_input, planned_output)

    @variable(model, E_CS[t in time_index], lower_bound = 0.0, upper_bound = params.max_soc * params.capacity)
    @variable(model, E_CS_in[t in time_index], lower_bound = 0.0)
    @variable(model, E_CS_out[t in time_index], lower_bound = 0.0)

    if params.min_constraint_on
        define_cas_min_constraints!(model, time_index, E_CS, params.min_soc, params.capacity)
    end

    if params.ramp_constraint_on
        define_cas_ramp_constraints!(model, time_index, E_CS_in, E_CS_out, params.ramp_ratio, params.capacity)
    end

    define_cas_initial_constraints!(model, time_index, E_CS, params.initial_soc, params.capacity, ctx)
    define_cas_energy_conservation_constraints!(model, time_index, E_CS, E_CS_in, E_CS_out, γ_CAS,
        params.efficiency, params.loss, params.time_step_hours)

    adjust_objective_expr = @expression(model, 0.0)
    if params.adjust_constraint_on
        adjust_objective_expr = define_cas_adjust_constraints!(
            model, time_index, E_CS_in, E_CS_out, planned_input, planned_output, γ_CAS,
            params.capacity, params.adjust_limit, params.adjust_cost)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cas_om_cost!(model, time_index, E_CS_in, E_CS_out, params.om_cost)
    end
    if params.adjust_objective_on
        objective_expr += adjust_objective_expr
    end

    return objective_expr
end

function build_compressed_air_storage_status_model!(model, component::CompressedAirStorage, params, ctx::BuildContext, ::Val{:full_follow})
    time_index = generate_timespan(ctx.layer)
    planned_input = upper_layer_values(ctx, "E_CS_in")
    planned_output = upper_layer_values(ctx, "E_CS_out")

    @variable(model, E_CS[t in time_index], lower_bound = 0.0, upper_bound = params.max_soc * params.capacity)
    @variable(model, E_CS_in[t in time_index], lower_bound = planned_input[t], upper_bound = planned_input[t] + 1.0)
    @variable(model, E_CS_out[t in time_index], lower_bound = planned_output[t], upper_bound = planned_output[t] + 1.0)

    if params.min_constraint_on
        define_cas_min_constraints!(model, time_index, E_CS, params.min_soc, params.capacity)
    end

    define_cas_initial_constraints!(model, time_index, E_CS, params.initial_soc, params.capacity, ctx)
    define_cas_energy_conservation_constraints!(model, time_index, E_CS, planned_input, planned_output,
        params.efficiency, params.loss, params.time_step_hours)

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cas_om_cost!(model, time_index, planned_input, planned_output, params.om_cost)
    end

    return objective_expr
end

function build_compressed_air_storage_status_model!(model, component::CompressedAirStorage, params, ctx::BuildContext, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    @variable(model, E_CS[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    @variable(model, E_CS_in[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    @variable(model, E_CS_out[t in time_index], lower_bound = 0.0, upper_bound = 1.0)
    return @expression(model, 0.0)
end

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function define_cas_om_cost!(model, time_index, input_power, output_power, om_cost)
    return @expression(model, C_cas_om, sum((input_power[t] + output_power[t]) * om_cost for t in time_index))
end

function define_cas_min_constraints!(model, time_index, stored_energy, min_soc, capacity)
    @constraint(model, [t in time_index], stored_energy[t] >= min_soc * capacity)
    return nothing
end

function define_cas_ramp_constraints!(model, time_index, input_power, output_power, ramp_ratio, capacity)
    @constraint(model, [t in time_index], input_power[t] <= ramp_ratio * capacity)
    @constraint(model, [t in time_index], output_power[t] <= ramp_ratio * capacity)
    return nothing
end

function define_cas_start_end_equality_constraints!(model, time_index, stored_energy)
    @constraint(model, stored_energy[first(time_index)] == stored_energy[last(time_index)])
    return nothing
end

function define_cas_initial_constraints!(model, time_index, stored_energy, initial_soc, capacity, ctx::BuildContext)
    storage_ts = current_layer_storage_value(ctx)
    if isnothing(storage_ts)
        @constraint(model, stored_energy[first(time_index)] == capacity * initial_soc)
    else
        @constraint(model, stored_energy[first(time_index)] == get_value(storage_ts, ctx.time))
    end
    return nothing
end

function define_cas_energy_conservation_constraints!(model, time_index, stored_energy, input_power, output_power,
    state_switch, efficiency, loss, time_step_hours)
    if length(time_index) > 1
        @constraint(model, [t in time_index[2:end]], stored_energy[t] == stored_energy[t-1] * (1 - loss) +
            (input_power[t-1] * efficiency - output_power[t-1] / efficiency) * time_step_hours)
    end
    @constraint(model, [t in time_index], input_power[t] <= BIG_M * state_switch[t])
    @constraint(model, [t in time_index], output_power[t] <= BIG_M * (1 - state_switch[t]))
    return nothing
end

function define_cas_energy_conservation_constraints!(model, time_index, stored_energy, input_power, output_power,
    γ_CAS::Vector{Float64}, efficiency, loss, time_step_hours)
    if length(time_index) > 1
        @constraint(model, [t in time_index[2:end]], stored_energy[t] == stored_energy[t-1] * (1 - loss) +
            (input_power[t-1] * efficiency - output_power[t-1] / efficiency) * time_step_hours)
    end

    @constraint(model, [t in time_index], input_power[t] <= BIG_M * (γ_CAS[t] + 1) / 2)
    @constraint(model, [t in time_index], output_power[t] <= BIG_M * (1 - γ_CAS[t]) / 2)
    @constraint(model, [t in time_index], input_power[t] <= BIG_M * γ_CAS[t]^2)
    @constraint(model, [t in time_index], output_power[t] <= BIG_M * γ_CAS[t]^2)
    return nothing
end

function define_cas_energy_conservation_constraints!(model, time_index, stored_energy,
    planned_input::Vector{Float64}, planned_output::Vector{Float64}, efficiency, loss, time_step_hours)
    if length(time_index) > 1
        @constraint(model, [t in time_index[2:end]], stored_energy[t] == stored_energy[t-1] * (1 - loss) +
            (planned_input[t-1] * efficiency - planned_output[t-1] / efficiency) * time_step_hours)
    end
    return nothing
end

function define_cas_adjust_constraints!(model, time_index, input_power, output_power, planned_input, planned_output, γ_CAS::Vector{Float64}, capacity, adjust_limit, adjust_cost)
    @variable(model, δ_CAS[t in time_index], Bin)
    @variable(model, δ_CAS_up[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)
    @variable(model, δ_CAS_down[t in time_index], lower_bound = 0.0, upper_bound = adjust_limit * capacity)

    @constraint(
        model,
        [t in time_index],
        input_power[t] == planned_input[t] * (γ_CAS[t] == 1.0) + δ_CAS_up[t] * (γ_CAS[t] == 1.0) - δ_CAS_down[t] * (γ_CAS[t] == 1.0),
    )
    @constraint(
        model,
        [t in time_index],
        output_power[t] == planned_output[t] * (γ_CAS[t] == -1.0) + δ_CAS_up[t] * (γ_CAS[t] == -1.0) - δ_CAS_down[t] * (γ_CAS[t] == -1.0),
    )
    @constraint(model, [t in time_index], δ_CAS_up[t] <= BIG_M * abs(γ_CAS[t]))
    @constraint(model, [t in time_index], δ_CAS_down[t] <= BIG_M * abs(γ_CAS[t]))
    @constraint(model, [t in time_index], δ_CAS_up[t] <= BIG_M * δ_CAS[t])
    @constraint(model, [t in time_index], δ_CAS_down[t] <= BIG_M * (1 - δ_CAS[t]))

    return @expression(model, C_cas_adjust, sum(δ_CAS_up[t] + δ_CAS_down[t] for t in time_index) * adjust_cost)
end
