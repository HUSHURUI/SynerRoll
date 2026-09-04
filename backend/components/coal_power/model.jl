# ═══════════════════════════════════════════════════════════════════════════
# coal_power/model.jl — 元编程架构
#
# 设计：
#   - 使用 JuMP 直接 API + CodeTracer 构建模型并记录代码
#   - 返回 (objective_expr, code_lines::Vector{String})
#   - 所有参数在代码追踪中内联为硬值
#   - 原始数学原理见 model-base.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::CoalPower, ctx::BuildContext, tracer::CodeTracer)
    params = resolve_coal_power_params(component, ctx)
    code = component_code(component)
    return build_coal_power_status_model!(model, component, params, ctx, code, tracer, Val(Symbol(params.status)))
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)

    # ── 变量 ──────────────────────────────────────────────────────────
    E_CP = add_tracked_variable!(model, tracer, "E_CP_$(code)", time_index;
        lower_bound=0.0, upper_bound=params.capacity)
    F_CP = add_tracked_variable!(model, tracer, "F_CP_$(code)", time_index)

    # ── 约束：出力 = 燃料 × 效率 ─────────────────────────────────────
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_CP_$(code)[t] == F_CP_$(code)[t] * $(format_val(params.efficiency)))",
        () -> @constraint(model, [t in time_index], E_CP[t] == F_CP[t] * params.efficiency)
    )

    # ── 爬坡约束 ──────────────────────────────────────────────────────
    if params.ramp_constraint_on && length(time_index) > 1
        c = code
        add_tracked_variable!(model, tracer, "ΔE_CP_$(c)", time_index[1:(end-1)];
            lower_bound=(-params.ramp_ratio * params.capacity),
            upper_bound=params.ramp_ratio * params.capacity)
        delta = model[Symbol("ΔE_CP_$(c)")]
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index[1:end-1]))], ΔE_CP_$(c)[t] == E_CP_$(c)[t+1] - E_CP_$(c)[t])",
            () -> @constraint(model, [t in time_index[1:(end-1)]], delta[t] == E_CP[t+1] - E_CP[t])
        )
    end

    # ── 开停机约束 ────────────────────────────────────────────────────
    on_off_obj = @expression(model, 0.0)
    status_vector = nothing
    if params.on_off_constraint_on
        status_vector, on_off_obj = define_cp_on_off_constraints_tracked!(
            model, tracer, time_index, E_CP, params, ctx, code)
        define_cp_min_constraints_tracked!(model, tracer, time_index, E_CP, status_vector, params, code;
            status_var_name="γ_CP")
    elseif params.min_constraint_on
        define_cp_min_constraints_tracked!(model, tracer, time_index, E_CP, nothing, params, code)
    end

    # ── 运维成本 ──────────────────────────────────────────────────────
    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        om = define_cp_om_cost_tracked!(model, tracer, time_index, E_CP, params, code)
        objective_expr += om
    end
    if params.on_off_objective_on
        objective_expr += on_off_obj
    end

    return objective_expr
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:adjust_power})
    time_index = generate_timespan(ctx.layer)

    E_CP = add_tracked_variable!(model, tracer, "E_CP_$(code)", time_index;
        lower_bound=0.0, upper_bound=params.capacity)
    F_CP = add_tracked_variable!(model, tracer, "F_CP_$(code)", time_index)

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_CP_$(code)[t] == F_CP_$(code)[t] * $(format_val(params.efficiency)))",
        () -> @constraint(model, [t in time_index], E_CP[t] == F_CP[t] * params.efficiency)
    )

    if params.ramp_constraint_on && length(time_index) > 1
        c = code
        add_tracked_variable!(model, tracer, "ΔE_CP_$(c)", time_index[1:(end-1)];
            lower_bound=(-params.ramp_ratio * params.capacity),
            upper_bound=params.ramp_ratio * params.capacity)
        delta = model[Symbol("ΔE_CP_$(c)")]
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index[1:end-1]))], ΔE_CP_$(c)[t] == E_CP_$(c)[t+1] - E_CP_$(c)[t])",
            () -> @constraint(model, [t in time_index[1:(end-1)]], delta[t] == E_CP[t+1] - E_CP[t])
        )
    end

    if params.min_constraint_on
        define_cp_min_constraints_tracked!(model, tracer, time_index, E_CP, nothing, params, code)
    end

    adjust_obj = define_cp_adjust_constraints_tracked!(model, tracer, time_index, E_CP, nothing, params, ctx, code)

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cp_om_cost_tracked!(model, tracer, time_index, E_CP, params, code)
    end
    if params.adjust_objective_on
        objective_expr += adjust_obj
    end

    return objective_expr
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:fixed_state})
    time_index = generate_timespan(ctx.layer)

    E_CP = add_tracked_variable!(model, tracer, "E_CP_$(code)", time_index;
        lower_bound=0.0, upper_bound=params.capacity)
    F_CP = add_tracked_variable!(model, tracer, "F_CP_$(code)", time_index)

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_CP_$(code)[t] == F_CP_$(code)[t] * $(format_val(params.efficiency)))",
        () -> @constraint(model, [t in time_index], E_CP[t] == F_CP[t] * params.efficiency)
    )

    if params.ramp_constraint_on && length(time_index) > 1
        c = code
        add_tracked_variable!(model, tracer, "ΔE_CP_$(c)", time_index[1:(end-1)];
            lower_bound=(-params.ramp_ratio * params.capacity),
            upper_bound=params.ramp_ratio * params.capacity)
        delta = model[Symbol("ΔE_CP_$(c)")]
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index[1:end-1]))], ΔE_CP_$(c)[t] == E_CP_$(c)[t+1] - E_CP_$(c)[t])",
            () -> @constraint(model, [t in time_index[1:(end-1)]], delta[t] == E_CP[t+1] - E_CP[t])
        )
    end

    status_vector, on_off_obj = define_cp_fixed_state_constraints_tracked!(model, tracer, time_index, E_CP, params, ctx, code)
    define_cp_min_constraints_tracked!(model, tracer, time_index, E_CP, status_vector, params, code)

    adjust_obj = @expression(model, 0.0)
    if params.adjust_constraint_on
        adjust_obj = define_cp_adjust_constraints_tracked!(model, tracer, time_index, E_CP, status_vector, params, ctx, code)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cp_om_cost_tracked!(model, tracer, time_index, E_CP, params, code)
    end
    if params.on_off_objective_on
        objective_expr += on_off_obj
    end
    if params.adjust_objective_on
        objective_expr += adjust_obj
    end

    return objective_expr
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:full_follow})
    time_index = generate_timespan(ctx.layer)
    planned_output = upper_layer_values(ctx, "E_CP", code)

    E_CP = add_tracked_variable!(model, tracer, "E_CP_$(code)", time_index;
        lower_bound=planned_output, upper_bound=planned_output .+ 1.0)
    F_CP = add_tracked_variable!(model, tracer, "F_CP_$(code)", time_index)

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_CP_$(code)[t] == F_CP_$(code)[t] * $(format_val(params.efficiency)))",
        () -> @constraint(model, [t in time_index], E_CP[t] == F_CP[t] * params.efficiency)
    )

    on_off_obj = @expression(model, 0.0)
    if params.on_off_constraint_on
        _, on_off_obj = define_cp_follow_on_off_constraints_tracked!(model, tracer, time_index, planned_output, params, ctx, code)
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr += define_cp_om_cost_tracked!(model, tracer, time_index, E_CP, params, code)
    end
    if params.on_off_objective_on
        objective_expr += on_off_obj
    end

    return objective_expr
end

function build_coal_power_status_model!(model, component::CoalPower, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    add_tracked_variable!(model, tracer, "E_CP_$(code)", time_index; lower_bound=0.0, upper_bound=1.0)
    add_tracked_variable!(model, tracer, "F_CP_$(code)", time_index; lower_bound=0.0, upper_bound=1.0)
    return @expression(model, 0.0)
end

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数（tracked 版本）
# ═══════════════════════════════════════════════════════════════════════════

function define_cp_om_cost_tracked!(model, tracer, time_index, output_power, params, code::String)
    expr = sum(output_power[t] * params.om_cost for t in time_index)
    add_tracked_expression!(model, tracer, "C_cp_om_$(code)",
        "@expression(model, C_cp_om_$(code), sum(E_CP_$(code)[t] * $(format_val(params.om_cost)) for t in $(format_val(time_index))))",
        expr; to_objective=true)
    return expr
end

function define_cp_min_constraints_tracked!(model, tracer, time_index, output_power, status_vector, params, code::String;
    status_var_name::Union{String,Nothing}=nothing)
    if status_vector !== nothing
        # 代码字符串中内联实际值：JuMP 变量用 status_var_name（如 γ_CP），常量数组用 format_val
        if status_var_name !== nothing
            var_label = "$(status_var_name)_$(code)"
        else
            var_label = "$(format_val(status_vector))"
        end
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_CP_$(code)[t] >= $(var_label)[t] * $(format_val(params.min_output_ratio)) * $(format_val(params.capacity)))",
            () -> @constraint(model, [t in time_index], output_power[t] >= status_vector[t] * params.min_output_ratio * params.capacity)
        )
    else
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_CP_$(code)[t] >= $(format_val(params.min_output_ratio)) * $(format_val(params.capacity)))",
            () -> @constraint(model, [t in time_index], output_power[t] >= params.min_output_ratio * params.capacity)
        )
    end
    return nothing
end

function define_cp_on_off_constraints_tracked!(model, tracer, time_index, output_power, params, ctx::BuildContext, code::String)
    c = code
    γ_CP = add_tracked_variable!(model, tracer, "γ_CP_$(c)", time_index; binary=true)
    γ_CP_start = add_tracked_variable!(model, tracer, "γ_CP_start_$(c)", time_index; binary=true)
    γ_CP_stop = add_tracked_variable!(model, tracer, "γ_CP_stop_$(c)", time_index; binary=true)

    cap = params.capacity
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_CP_$(c)[t] <= γ_CP_$(c)[t] * $(format_val(cap)))",
        () -> @constraint(model, [t in time_index], output_power[t] <= γ_CP[t] * cap))

    previous_power = previous_layer_result_value(ctx, "CP", "E_CP", c)
    previous_status = previous_power === nothing ? 0 : Int(previous_power > 1e-6)
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, γ_CP_$(c)[$(format_val(first(time_index)))] - $(previous_status) == γ_CP_start_$(c)[$(format_val(first(time_index)))] - γ_CP_stop_$(c)[$(format_val(first(time_index)))])",
        () -> @constraint(model, γ_CP[first(time_index)] - previous_status == γ_CP_start[first(time_index)] - γ_CP_stop[first(time_index)]))

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index[2:end]))], γ_CP_$(c)[t] - γ_CP_$(c)[t-1] == γ_CP_start_$(c)[t] - γ_CP_stop_$(c)[t])",
        () -> @constraint(model, [t in time_index[2:end]], γ_CP[t] - γ_CP[t-1] == γ_CP_start[t] - γ_CP_stop[t]))

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], γ_CP_start_$(c)[t] + γ_CP_stop_$(c)[t] <= 1)",
        () -> @constraint(model, [t in time_index], γ_CP_start[t] + γ_CP_stop[t] <= 1))

    if length(time_index) > params.min_on_steps
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index[params.min_on_steps+1:end]))], sum(γ_CP_start_$(c)[h] for h in t-$(params.min_on_steps)+1:t) <= γ_CP_$(c)[t])",
            () -> @constraint(model, [t in time_index[(params.min_on_steps+1):end]], sum(γ_CP_start[h] for h in (t-params.min_on_steps+1):t) <= γ_CP[t]))
    end

    if length(time_index) > params.min_off_steps
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index[params.min_off_steps+1:end]))], sum(γ_CP_stop_$(c)[h] for h in t-$(params.min_off_steps)+1:t) <= 1 - γ_CP_$(c)[t])",
            () -> @constraint(model, [t in time_index[(params.min_off_steps+1):end]], sum(γ_CP_stop[h] for h in (t-params.min_off_steps+1):t) <= 1 - γ_CP[t]))
    end

    on_off_obj = sum((γ_CP_start[t] + γ_CP_stop[t]) * params.on_off_cost for t in time_index)
    add_tracked_expression!(model, tracer, "C_cp_on_off_$(c)",
        "@expression(model, C_cp_on_off_$(c), sum((γ_CP_start_$(c)[t] + γ_CP_stop_$(c)[t]) * $(format_val(params.on_off_cost)) for t in $(format_val(time_index))))",
        on_off_obj; to_objective=true)

    return γ_CP, on_off_obj
end

function define_cp_fixed_state_constraints_tracked!(model, tracer, time_index, output_power, params, ctx::BuildContext, code::String)
    planned_output = upper_layer_values(ctx, "E_CP", code)
    status_vector = planned_output .> params.min_output_ratio * params.capacity
    c = code

    γ_CP_start = add_tracked_variable!(model, tracer, "γ_CP_start_$(c)", time_index; binary=true)
    γ_CP_stop = add_tracked_variable!(model, tracer, "γ_CP_stop_$(c)", time_index; binary=true)

    cap = params.capacity
    sv = format_val(status_vector)
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], E_CP_$(c)[t] <= $(sv)[t] * $(format_val(cap)))",
        () -> @constraint(model, [t in time_index], output_power[t] <= status_vector[t] * cap))

    previous_power = previous_layer_result_value(ctx, "CP", "E_CP", c)
    previous_status = previous_power === nothing ? 0 : Int(previous_power > 1e-6)
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, $(sv)[$(format_val(first(time_index)))] - $(previous_status) == γ_CP_start_$(c)[$(format_val(first(time_index)))] - γ_CP_stop_$(c)[$(format_val(first(time_index)))])",
        () -> @constraint(model, status_vector[first(time_index)] - previous_status == γ_CP_start[first(time_index)] - γ_CP_stop[first(time_index)]))

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index[2:end]))], $(sv)[t] - $(sv)[t-1] == γ_CP_start_$(c)[t] - γ_CP_stop_$(c)[t])",
        () -> @constraint(model, [t in time_index[2:end]], status_vector[t] - status_vector[t-1] == γ_CP_start[t] - γ_CP_stop[t]))

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], γ_CP_start_$(c)[t] + γ_CP_stop_$(c)[t] <= 1)",
        () -> @constraint(model, [t in time_index], γ_CP_start[t] + γ_CP_stop[t] <= 1))

    on_off_obj = sum((γ_CP_start[t] + γ_CP_stop[t]) * params.on_off_cost for t in time_index)
    add_tracked_expression!(model, tracer, "C_cp_on_off_$(c)",
        "@expression(model, C_cp_on_off_$(c), sum((γ_CP_start_$(c)[t] + γ_CP_stop_$(c)[t]) * $(format_val(params.on_off_cost)) for t in $(format_val(time_index))))",
        on_off_obj; to_objective=true)

    return status_vector, on_off_obj
end

function define_cp_follow_on_off_constraints_tracked!(model, tracer, time_index, planned_output, params, ctx::BuildContext, code::String)
    status_vector = planned_output .> params.min_output_ratio * params.capacity
    c = code
    sv = format_val(status_vector)

    γ_CP_start = add_tracked_variable!(model, tracer, "γ_CP_start_$(c)", time_index; binary=true)
    γ_CP_stop = add_tracked_variable!(model, tracer, "γ_CP_stop_$(c)", time_index; binary=true)

    previous_power = previous_layer_result_value(ctx, "CP", "E_CP", c)
    previous_status = previous_power === nothing ? 0 : Int(previous_power > 1e-6)
    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, $(sv)[$(format_val(first(time_index)))] - $(previous_status) == γ_CP_start_$(c)[$(format_val(first(time_index)))] - γ_CP_stop_$(c)[$(format_val(first(time_index)))])",
        () -> @constraint(model, status_vector[first(time_index)] - previous_status == γ_CP_start[first(time_index)] - γ_CP_stop[first(time_index)]))

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index[2:end]))], $(sv)[t] - $(sv)[t-1] == γ_CP_start_$(c)[t] - γ_CP_stop_$(c)[t])",
        () -> @constraint(model, [t in time_index[2:end]], status_vector[t] - status_vector[t-1] == γ_CP_start[t] - γ_CP_stop[t]))

    add_tracked_linear_constraint!(model, tracer,
        "@constraint(model, [t in $(format_val(time_index))], γ_CP_start_$(c)[t] + γ_CP_stop_$(c)[t] <= 1)",
        () -> @constraint(model, [t in time_index], γ_CP_start[t] + γ_CP_stop[t] <= 1))

    on_off_obj = sum((γ_CP_start[t] + γ_CP_stop[t]) * params.on_off_cost for t in time_index)
    add_tracked_expression!(model, tracer, "C_cp_on_off_$(c)",
        "@expression(model, C_cp_on_off_$(c), sum((γ_CP_start_$(c)[t] + γ_CP_stop_$(c)[t]) * $(format_val(params.on_off_cost)) for t in $(format_val(time_index))))",
        on_off_obj; to_objective=true)

    return status_vector, on_off_obj
end

function define_cp_adjust_constraints_tracked!(model, tracer, time_index, output_power, status_vector, params, ctx::BuildContext, code::String)
    planned_output = upper_layer_values(ctx, "E_CP", code)
    c = code

    if status_vector !== nothing
        active_periods = [t for t in time_index if status_vector[t]]
        if isempty(active_periods)
            return @expression(model, 0.0)
        end
        adj_dir = add_tracked_variable!(model, tracer, "δ_CP_$(c)", active_periods; binary=true)
        adj_up = add_tracked_variable!(model, tracer, "δ_CP_up_$(c)", active_periods;
            lower_bound=0.0, upper_bound=params.adjust_limit * params.capacity)
        adj_down = add_tracked_variable!(model, tracer, "δ_CP_down_$(c)", active_periods;
            lower_bound=0.0, upper_bound=params.adjust_limit * params.capacity)

        cap = params.capacity;
        limit = params.adjust_limit
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(active_periods))], E_CP_$(c)[t] == $(format_val(planned_output))[t] + δ_CP_up_$(c)[t] - δ_CP_down_$(c)[t])",
            () -> @constraint(model, [t in active_periods], output_power[t] == planned_output[t] + adj_up[t] - adj_down[t]))
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(active_periods))], δ_CP_up_$(c)[t] <= $(BIG_M) * δ_CP_$(c)[t])",
            () -> @constraint(model, [t in active_periods], adj_up[t] <= BIG_M * adj_dir[t]))
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(active_periods))], δ_CP_down_$(c)[t] <= $(BIG_M) * (1 - δ_CP_$(c)[t]))",
            () -> @constraint(model, [t in active_periods], adj_down[t] <= BIG_M * (1 - adj_dir[t])))

        adj_obj = sum(adj_up[t] + adj_down[t] for t in active_periods) * params.adjust_cost
        add_tracked_expression!(model, tracer, "C_cp_adjust_$(c)",
            "@expression(model, C_cp_adjust_$(c), sum(δ_CP_up_$(c)[t] + δ_CP_down_$(c)[t] for t in $(format_val(active_periods))) * $(format_val(params.adjust_cost)))",
            adj_obj; to_objective=true)
        return adj_obj
    else
        adj_dir = add_tracked_variable!(model, tracer, "δ_CP_$(c)", time_index; binary=true)
        adj_up = add_tracked_variable!(model, tracer, "δ_CP_up_$(c)", time_index;
            lower_bound=0.0, upper_bound=params.adjust_limit * params.capacity)
        adj_down = add_tracked_variable!(model, tracer, "δ_CP_down_$(c)", time_index;
            lower_bound=0.0, upper_bound=params.adjust_limit * params.capacity)

        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], E_CP_$(c)[t] == $(format_val(planned_output))[t] + δ_CP_up_$(c)[t] - δ_CP_down_$(c)[t])",
            () -> @constraint(model, [t in time_index], output_power[t] == planned_output[t] + adj_up[t] - adj_down[t]))
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], δ_CP_up_$(c)[t] <= $(BIG_M) * δ_CP_$(c)[t])",
            () -> @constraint(model, [t in time_index], adj_up[t] <= BIG_M * adj_dir[t]))
        add_tracked_linear_constraint!(model, tracer,
            "@constraint(model, [t in $(format_val(time_index))], δ_CP_down_$(c)[t] <= $(BIG_M) * (1 - δ_CP_$(c)[t]))",
            () -> @constraint(model, [t in time_index], adj_down[t] <= BIG_M * (1 - adj_dir[t])))

        adj_obj = sum(adj_up[t] + adj_down[t] for t in time_index) * params.adjust_cost
        add_tracked_expression!(model, tracer, "C_cp_adjust_$(c)",
            "@expression(model, C_cp_adjust_$(c), sum(δ_CP_up_$(c)[t] + δ_CP_down_$(c)[t] for t in $(format_val(time_index))) * $(format_val(params.adjust_cost)))",
            adj_obj; to_objective=true)
        return adj_obj
    end
end
