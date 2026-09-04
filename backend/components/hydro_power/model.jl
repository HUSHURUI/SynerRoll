# ═══════════════════════════════════════════════════════════════════════════
# hydro_power/model.jl — 元编程追踪版本
#
# 数学含义见 model-base.jl；本文件保持与既有组件一致的 CodeTracer 写法。
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::HydroPower, ctx::BuildContext, tracer::CodeTracer)
    params = resolve_hydro_power_params(component, ctx)
    code = component_code(component)
    return build_hydro_power_status_model!(
        model,
        component,
        params,
        ctx,
        code,
        tracer,
        Val(Symbol(params.status)),
    )
end

function build_hydro_power_status_model!(
    model,
    component::HydroPower,
    params,
    ctx::BuildContext,
    code::String,
    tracer::CodeTracer,
    ::Val{:stand_alone},
)
    time_index = generate_timespan(ctx.layer)
    available_power = generate_hydro_available_power(component, ctx)
    minimum_power = generate_hydro_minimum_power(available_power, params)

    add_tracked_expression!(
        model,
        tracer,
        "AVAILABLE_HYDRO_$(code)",
        "model[Symbol(\"AVAILABLE_HYDRO_$(code)\")] = @expression(model, [t in $(format_val(time_index))], $(format_val(available_power))[t])",
        @expression(model, [t in time_index], available_power[t]),
    )
    add_tracked_expression!(
        model,
        tracer,
        "MINIMUM_HYDRO_$(code)",
        "model[Symbol(\"MINIMUM_HYDRO_$(code)\")] = @expression(model, [t in $(format_val(time_index))], $(format_val(minimum_power))[t])",
        @expression(model, [t in time_index], minimum_power[t]),
    )

    E_HYDRO = add_tracked_variable!(
        model,
        tracer,
        "E_HYDRO_$(code)",
        time_index;
        lower_bound=minimum_power,
        upper_bound=available_power,
    )

    if params.ramp_constraint_on && length(time_index) > 1
        ramp_time_index = time_index[1:(end-1)]
        add_tracked_linear_constraint!(
            model,
            tracer,
            "@constraint(model, [t in $(format_val(ramp_time_index))], E_HYDRO_$(code)[t+1] - E_HYDRO_$(code)[t] <= $(format_val(params.ramp_limit_kw)))",
            () -> @constraint(
                model,
                [t in ramp_time_index],
                E_HYDRO[t+1] - E_HYDRO[t] <= params.ramp_limit_kw,
            ),
        )
        add_tracked_linear_constraint!(
            model,
            tracer,
            "@constraint(model, [t in $(format_val(ramp_time_index))], E_HYDRO_$(code)[t] - E_HYDRO_$(code)[t+1] <= $(format_val(params.ramp_limit_kw)))",
            () -> @constraint(
                model,
                [t in ramp_time_index],
                E_HYDRO[t] - E_HYDRO[t+1] <= params.ramp_limit_kw,
            ),
        )
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        om_expr = sum(E_HYDRO) * params.om_cost
        add_tracked_expression!(
            model,
            tracer,
            "C_hydro_om_$(code)",
            "@expression(model, C_hydro_om_$(code), sum(E_HYDRO_$(code)) * $(format_val(params.om_cost)))",
            om_expr;
            to_objective=true,
        )
        objective_expr += om_expr
    end

    return objective_expr
end

function build_hydro_power_status_model!(
    model,
    component::HydroPower,
    params,
    ctx::BuildContext,
    code::String,
    tracer::CodeTracer,
    ::Val{:disabled},
)
    time_index = generate_timespan(ctx.layer)
    zero_power = zeros(Float64, length(time_index))

    add_tracked_expression!(
        model,
        tracer,
        "AVAILABLE_HYDRO_$(code)",
        "model[Symbol(\"AVAILABLE_HYDRO_$(code)\")] = @expression(model, [t in $(format_val(time_index))], 0.0)",
        @expression(model, [t in time_index], zero_power[t]),
    )
    add_tracked_expression!(
        model,
        tracer,
        "MINIMUM_HYDRO_$(code)",
        "model[Symbol(\"MINIMUM_HYDRO_$(code)\")] = @expression(model, [t in $(format_val(time_index))], 0.0)",
        @expression(model, [t in time_index], zero_power[t]),
    )
    add_tracked_variable!(
        model,
        tracer,
        "E_HYDRO_$(code)",
        time_index;
        lower_bound=0.0,
        upper_bound=0.0,
    )

    return @expression(model, 0.0)
end

function build_hydro_power_status_model!(
    model,
    component::HydroPower,
    params,
    ctx::BuildContext,
    code::String,
    tracer::CodeTracer,
    status,
)
    error("HydroPower does not support status $(params.status) in the standardized model.")
end
