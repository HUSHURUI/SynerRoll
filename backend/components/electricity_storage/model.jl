# ═══════════════════════════════════════════════════════════════════════════
# electricity_storage/model.jl — 元编程架构
#
# 设计：
#   - 使用 JuMP 直接 API + CodeTracer 构建模型并记录代码
#   - 返回 (objective_expr, code_lines::Vector{String})
#   - 所有参数在代码追踪中内联为硬值
#   - 原始数学原理见 model-base.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::ElectricityStorage, ctx::BuildContext, tracer::CodeTracer)
    params = resolve_electricity_storage_params(component, ctx)
    code = component_code(component)
    return build_electricity_storage_status_model!(model, component, params, ctx, code, tracer, Val(Symbol(params.status)))
end

function build_electricity_storage_status_model!(model, component::ElectricityStorage, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)
    c = code

    # ── 变量 ──────────────────────────────────────────────────────────
    E_ES = add_tracked_variable!(model, tracer, "E_ES_$(c)", time_index;
        lower_bound=0.0, upper_bound=params.max_soc * params.capacity)
    E_ES_in = add_tracked_variable!(model, tracer, "E_ES_in_$(c)", time_index; lower_bound=0.0)
    E_ES_out = add_tracked_variable!(model, tracer, "E_ES_out_$(c)", time_index; lower_bound=0.0)
    γ_ES = add_tracked_variable!(model, tracer, "γ_ES_$(c)", time_index; binary=true)

    # ── 荷电下限 ──────────────────────────────────────────────────────
    if params.min_constraint_on
        cap = params.capacity;
        min_soc = params.min_soc
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_ES_$(c)[t] >= $(format_val(min_soc)) * $(format_val(cap)))",
            () -> @constraint(model, [t in time_index], E_ES[t] >= min_soc * cap))
    end

    # ── 爬坡约束 ──────────────────────────────────────────────────────
    if params.ramp_constraint_on
        cap = params.capacity;
        ramp = params.ramp_ratio
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_ES_in_$(c)[t] <= $(format_val(ramp)) * $(format_val(cap)))",
            () -> @constraint(model, [t in time_index], E_ES_in[t] <= ramp * cap))
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_ES_out_$(c)[t] <= $(format_val(ramp)) * $(format_val(cap)))",
            () -> @constraint(model, [t in time_index], E_ES_out[t] <= ramp * cap))
    end

    # ── 首末时刻相等 ──────────────────────────────────────────────────
    if params.start_end_equality_constraint_on
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, E_ES_$(c)[$(format_val(first(time_index)))] == E_ES_$(c)[$(format_val(last(time_index)))])",
            () -> @constraint(model, E_ES[first(time_index)] == E_ES[last(time_index)]))
    end

    # ── 初始 SOC ──────────────────────────────────────────────────────
    define_es_initial_constraints_tracked!(model, tracer, time_index, E_ES, params, ctx, c)

    # ── 能量守恒 ──────────────────────────────────────────────────────
    define_es_energy_conservation_tracked!(model, tracer, time_index, E_ES, E_ES_in, E_ES_out, γ_ES, params, c, true)

    # ── 目标函数 ──────────────────────────────────────────────────────
    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        om = define_es_om_cost_tracked!(model, tracer, time_index, E_ES_in, E_ES_out, params, c)
        objective_expr += om
    end

    return objective_expr
end

function build_electricity_storage_status_model!(model, component::ElectricityStorage, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:fixed_state})
    time_index = generate_timespan(ctx.layer)
    c = code

    planned_input = upper_layer_values(ctx, "E_ES_in", c)
    planned_output = upper_layer_values(ctx, "E_ES_out", c)
    storage_state = derive_storage_state(planned_input, planned_output)

    E_ES = add_tracked_variable!(model, tracer, "E_ES_$(c)", time_index;
        lower_bound=0.0, upper_bound=params.max_soc * params.capacity)
    E_ES_in = add_tracked_variable!(model, tracer, "E_ES_in_$(c)", time_index; lower_bound=0.0)
    E_ES_out = add_tracked_variable!(model, tracer, "E_ES_out_$(c)", time_index; lower_bound=0.0)

    if params.min_constraint_on
        cap = params.capacity;
        min_soc = params.min_soc
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_ES_$(c)[t] >= $(format_val(min_soc)) * $(format_val(cap)))",
            () -> @constraint(model, [t in time_index], E_ES[t] >= min_soc * cap))
    end

    if params.ramp_constraint_on
        cap = params.capacity;
        ramp = params.ramp_ratio
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_ES_in_$(c)[t] <= $(format_val(ramp)) * $(format_val(cap)))",
            () -> @constraint(model, [t in time_index], E_ES_in[t] <= ramp * cap))
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_ES_out_$(c)[t] <= $(format_val(ramp)) * $(format_val(cap)))",
            () -> @constraint(model, [t in time_index], E_ES_out[t] <= ramp * cap))
    end

    define_es_initial_constraints_tracked!(model, tracer, time_index, E_ES, params, ctx, c)
    define_es_energy_conservation_tracked!(model, tracer, time_index, E_ES, E_ES_in, E_ES_out, storage_state, params, c, Val(:fixed_state))

    adjust_obj = @expression(model, 0.0)
    if params.adjust_constraint_on
        adjust_obj = define_es_adjust_constraints_tracked!(model, tracer, time_index, E_ES_in, E_ES_out,
            planned_input, planned_output, storage_state, params, c)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_es_om_cost_tracked!(model, tracer, time_index, E_ES_in, E_ES_out, params, c)
    end
    if params.adjust_objective_on
        objective_expr += adjust_obj
    end

    return objective_expr
end

function build_electricity_storage_status_model!(model, component::ElectricityStorage, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:full_follow})
    time_index = generate_timespan(ctx.layer)
    c = code

    planned_input = upper_layer_values(ctx, "E_ES_in", c)
    planned_output = upper_layer_values(ctx, "E_ES_out", c)

    E_ES = add_tracked_variable!(model, tracer, "E_ES_$(c)", time_index;
        lower_bound=0.0, upper_bound=params.max_soc * params.capacity)
    E_ES_in = add_tracked_variable!(model, tracer, "E_ES_in_$(c)", time_index;
        lower_bound=planned_input, upper_bound=planned_input .+ 1.0)
    E_ES_out = add_tracked_variable!(model, tracer, "E_ES_out_$(c)", time_index;
        lower_bound=planned_output, upper_bound=planned_output .+ 1.0)

    if params.min_constraint_on
        cap = params.capacity;
        min_soc = params.min_soc
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_ES_$(c)[t] >= $(format_val(min_soc)) * $(format_val(cap)))",
            () -> @constraint(model, [t in time_index], E_ES[t] >= min_soc * cap))
    end

    define_es_initial_constraints_tracked!(model, tracer, time_index, E_ES, params, ctx, c)
    define_es_energy_conservation_tracked!(model, tracer, time_index, E_ES, planned_input, planned_output, params, c, false)

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_es_om_cost_tracked!(model, tracer, time_index, planned_input, planned_output, params, c)
    end

    return objective_expr
end

function build_electricity_storage_status_model!(model, component::ElectricityStorage, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    c = code
    add_tracked_variable!(model, tracer, "E_ES_$(c)", time_index; lower_bound=0.0, upper_bound=1.0)
    add_tracked_variable!(model, tracer, "E_ES_in_$(c)", time_index; lower_bound=0.0, upper_bound=1.0)
    add_tracked_variable!(model, tracer, "E_ES_out_$(c)", time_index; lower_bound=0.0, upper_bound=1.0)
    return @expression(model, 0.0)
end

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数（tracked 版本）
# ═══════════════════════════════════════════════════════════════════════════

function define_es_om_cost_tracked!(model, tracer, time_index, input_power, output_power, params, c::String)
    expr = sum((input_power[t] + output_power[t]) * params.om_cost for t in time_index)
    add_tracked_expression!(model, tracer, "C_es_om_$(c)",
        "@expression(model, C_es_om_$(c), sum((E_ES_in_$(c)[t] + E_ES_out_$(c)[t]) * $(format_val(params.om_cost)) for t in $(format_val(time_index))))",
        expr; to_objective=true)
    return expr
end

function define_es_initial_constraints_tracked!(model, tracer, time_index, stored_energy, params, ctx::BuildContext, c::String)
    storage_ts = current_layer_storage_value(ctx, c, "ES", "E_ES")
    if isnothing(storage_ts)
        cap = params.capacity;
        ini = params.initial_soc
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, E_ES_$(c)[$(format_val(first(time_index)))] == $(format_val(cap)) * $(format_val(ini)))",
            () -> @constraint(model, stored_energy[first(time_index)] == cap * ini))
    else
        val = get_value(storage_ts, ctx.time)
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, E_ES_$(c)[$(format_val(first(time_index)))] == $(format_val(val)))",
            () -> @constraint(model, stored_energy[first(time_index)] == val))
    end
    return nothing
end

function define_es_energy_conservation_tracked!(model, tracer, time_index, stored_energy, input_power, output_power,
    state_switch, params, c::String, has_binary_switch::Bool)
    η = params.efficiency;
    loss = params.loss
    time_step_hours = params.time_step_hours
    if length(time_index) > 1
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index[2:end]))], E_ES_$(c)[t] == E_ES_$(c)[t-1] * $(format_val(1 - loss)) + (E_ES_in_$(c)[t-1] * $(format_val(η)) - E_ES_out_$(c)[t-1] / $(format_val(η))) * $(format_val(time_step_hours)))",
            () -> @constraint(model, [t in time_index[2:end]], stored_energy[t] == stored_energy[t-1] * (1 - loss) +
                (input_power[t-1] * η - output_power[t-1] / η) * time_step_hours))
    end

    if has_binary_switch
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_ES_in_$(c)[t] <= $(BIG_M) * γ_ES_$(c)[t])",
            () -> @constraint(model, [t in time_index], input_power[t] <= BIG_M * state_switch[t]))
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_ES_out_$(c)[t] <= $(BIG_M) * (1 - γ_ES_$(c)[t]))",
            () -> @constraint(model, [t in time_index], output_power[t] <= BIG_M * (1 - state_switch[t])))
    end
    return nothing
end

# fixed_state 专用：storage_state 为三值常量 Vector（+1充电/-1放电/0闲置），无条件执行互斥约束
function define_es_energy_conservation_tracked!(model, tracer, time_index, stored_energy, input_power, output_power,
    storage_state::Vector{Float64}, params, c::String, ::Val{:fixed_state})
    η = params.efficiency;
    loss = params.loss
    time_step_hours = params.time_step_hours
    ss_str = format_val(storage_state)
    m = BIG_M

    # 能量守恒
    if length(time_index) > 1
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index[2:end]))], E_ES_$(c)[t] == E_ES_$(c)[t-1] * $(format_val(1 - loss)) + (E_ES_in_$(c)[t-1] * $(format_val(η)) - E_ES_out_$(c)[t-1] / $(format_val(η))) * $(format_val(time_step_hours)))",
            () -> @constraint(model, [t in time_index[2:end]], stored_energy[t] == stored_energy[t-1] * (1 - loss) +
                (input_power[t-1] * η - output_power[t-1] / η) * time_step_hours))
    end

    # 三值状态互斥约束（参考实现 define_energy_conservation_constraints! 的 Vector{Float64} 重载）
    # γ=1: 允许充电, 禁止放电; γ=-1: 禁止充电, 允许放电; γ=0: 禁止充放
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_ES_in_$(c)[t] <= $(m) * ($(ss_str)[t] + 1) / 2)",
        () -> @constraint(model, [t in time_index], input_power[t] <= m * (storage_state[t] + 1) / 2))
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_ES_out_$(c)[t] <= $(m) * (1 - $(ss_str)[t]) / 2)",
        () -> @constraint(model, [t in time_index], output_power[t] <= m * (1 - storage_state[t]) / 2))
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_ES_in_$(c)[t] <= $(m) * $(ss_str)[t]^2)",
        () -> @constraint(model, [t in time_index], input_power[t] <= m * storage_state[t]^2))
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_ES_out_$(c)[t] <= $(m) * $(ss_str)[t]^2)",
        () -> @constraint(model, [t in time_index], output_power[t] <= m * storage_state[t]^2))

    return nothing
end

function define_es_energy_conservation_tracked!(model, tracer, time_index, stored_energy, planned_input::Vector{Float64}, planned_output::Vector{Float64},
    params, c::String, has_binary_switch::Bool)
    η = params.efficiency;
    loss = params.loss
    time_step_hours = params.time_step_hours
    pi_str = format_val(planned_input)
    po_str = format_val(planned_output)
    if length(time_index) > 1
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index[2:end]))], E_ES_$(c)[t] == E_ES_$(c)[t-1] * $(format_val(1 - loss)) + ($(pi_str)[t-1] * $(format_val(η)) - $(po_str)[t-1] / $(format_val(η))) * $(format_val(time_step_hours)))",
            () -> @constraint(model, [t in time_index[2:end]], stored_energy[t] == stored_energy[t-1] * (1 - loss) +
                (planned_input[t-1] * η - planned_output[t-1] / η) * time_step_hours))
    end
    return nothing
end

function define_es_adjust_constraints_tracked!(model, tracer, time_index, input_power, output_power,
    planned_input, planned_output, storage_state::Vector{Float64}, params, c::String)
    limit = params.adjust_limit;
    cap = params.capacity;
    cost = params.adjust_cost
    pi_str = format_val(planned_input)
    po_str = format_val(planned_output)
    ss_str = format_val(storage_state)

    adj_dir = add_tracked_variable!(model, tracer, "δ_ES_$(c)", time_index; binary=true)
    adj_up = add_tracked_variable!(model, tracer, "δ_ES_up_$(c)", time_index;
        lower_bound=0.0, upper_bound=limit * cap)
    adj_down = add_tracked_variable!(model, tracer, "δ_ES_down_$(c)", time_index;
        lower_bound=0.0, upper_bound=limit * cap)

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_ES_in_$(c)[t] == $(pi_str)[t] * ($(ss_str)[t] == 1.0) + δ_ES_up_$(c)[t] * ($(ss_str)[t] == 1.0) - δ_ES_down_$(c)[t] * ($(ss_str)[t] == 1.0))",
        () -> @constraint(model, [t in time_index], input_power[t] == planned_input[t] * (storage_state[t] == 1.0) + adj_up[t] * (storage_state[t] == 1.0) - adj_down[t] * (storage_state[t] == 1.0)))
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_ES_out_$(c)[t] == $(po_str)[t] * ($(ss_str)[t] == -1.0) + δ_ES_up_$(c)[t] * ($(ss_str)[t] == -1.0) - δ_ES_down_$(c)[t] * ($(ss_str)[t] == -1.0))",
        () -> @constraint(model, [t in time_index], output_power[t] == planned_output[t] * (storage_state[t] == -1.0) + adj_up[t] * (storage_state[t] == -1.0) - adj_down[t] * (storage_state[t] == -1.0)))

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], δ_ES_up_$(c)[t] <= $(BIG_M) * abs($(ss_str)[t]))",
        () -> @constraint(model, [t in time_index], adj_up[t] <= BIG_M * abs(storage_state[t])))
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], δ_ES_down_$(c)[t] <= $(BIG_M) * abs($(ss_str)[t]))",
        () -> @constraint(model, [t in time_index], adj_down[t] <= BIG_M * abs(storage_state[t])))
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], δ_ES_up_$(c)[t] <= $(BIG_M) * δ_ES_$(c)[t])",
        () -> @constraint(model, [t in time_index], adj_up[t] <= BIG_M * adj_dir[t]))
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], δ_ES_down_$(c)[t] <= $(BIG_M) * (1 - δ_ES_$(c)[t]))",
        () -> @constraint(model, [t in time_index], adj_down[t] <= BIG_M * (1 - adj_dir[t])))

    adj_obj = sum(adj_up[t] + adj_down[t] for t in time_index) * cost
    add_tracked_expression!(model, tracer, "C_es_adjust_$(c)",
        "@expression(model, C_es_adjust_$(c), sum(δ_ES_up_$(c)[t] + δ_ES_down_$(c)[t] for t in $(format_val(time_index))) * $(format_val(cost)))",
        adj_obj; to_objective=true)

    return adj_obj
end
