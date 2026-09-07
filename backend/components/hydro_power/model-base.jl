# ═══════════════════════════════════════════════════════════════════════════
# hydro_power/model-base.jl — 数学原理蓝图
#
# 常规水电首版采用可调发电单元模型：
#   E_HYDRO[t]          : 实际发电功率（kW）
#   AVAILABLE_HYDRO[t]  : 水情/历史边界给出的最大可用功率（kW）
#   MINIMUM_HYDRO[t]    : 最小技术出力（kW）
#
# 精细的来流—库容—水头—弃水耦合留待后续水库模型扩展。
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::HydroPower, ctx::BuildContext)
    params = resolve_hydro_power_params(component, ctx)
    return build_hydro_power_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_hydro_power_status_model!(
    model,
    component::HydroPower,
    params,
    ctx::BuildContext,
    ::Val{:stand_alone},
)
    time_index = generate_timespan(ctx.layer)
    code = component_code(component)
    available_power = generate_hydro_available_power(component, ctx)
    minimum_power = generate_hydro_minimum_power(available_power, params)

    model[Symbol("AVAILABLE_HYDRO_$(code)")] =
        @expression(model, [t in time_index], available_power[t])
    model[Symbol("MINIMUM_HYDRO_$(code)")] =
        @expression(model, [t in time_index], minimum_power[t])

    @variable(
        model,
        minimum_power[t] <= E_HYDRO[t in time_index] <= available_power[t],
    )

    if params.ramp_constraint_on && length(time_index) > 1
        ramp_time_index = time_index[1:(end-1)]
        @constraint(
            model,
            [t in ramp_time_index],
            E_HYDRO[t+1] - E_HYDRO[t] <= params.ramp_limit_kw,
        )
        @constraint(
            model,
            [t in ramp_time_index],
            E_HYDRO[t] - E_HYDRO[t+1] <= params.ramp_limit_kw,
        )
    end

    objective_expr = @expression(model, 0.0)
    if params.om_objective_on
        objective_expr +=
            @expression(model, C_hydro_om, sum(E_HYDRO) * params.om_cost)
    end

    return objective_expr
end

function build_hydro_power_status_model!(
    model,
    component::HydroPower,
    params,
    ctx::BuildContext,
    ::Val{:disabled},
)
    time_index = generate_timespan(ctx.layer)
    code = component_code(component)
    zero_power = zeros(Float64, length(time_index))

    model[Symbol("AVAILABLE_HYDRO_$(code)")] =
        @expression(model, [t in time_index], zero_power[t])
    model[Symbol("MINIMUM_HYDRO_$(code)")] =
        @expression(model, [t in time_index], zero_power[t])
    @variable(model, E_HYDRO[t in time_index] == 0.0)

    return @expression(model, 0.0)
end

function build_hydro_power_status_model!(
    model,
    component::HydroPower,
    params,
    ctx::BuildContext,
    status,
)
    error("HydroPower does not support status $(params.status) in the standardized model.")
end
