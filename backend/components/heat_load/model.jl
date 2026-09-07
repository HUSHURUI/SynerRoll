# ═══════════════════════════════════════════════════════════════════════════
# heat_load/model.jl — 元编程架构
#
# 设计：
#   - 使用 JuMP 直接 API + CodeTracer 构建模型并记录代码
#   - 返回 (objective_expr, code_lines::Vector{String})
#   - 所有参数在代码追踪中内联为硬值
#   - 原始数学原理见 model-base.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::HeatLoad, ctx::BuildContext, tracer::CodeTracer)
    params = resolve_heat_load_params(component, ctx)
    code = component_code(component)
    return build_heat_load_status_model!(model, component, params, ctx, code, tracer, Val(Symbol(params.status)))
end

function build_heat_load_status_model!(model, component::HeatLoad, params, ctx::BuildContext,
                                              code::String, tracer::CodeTracer, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)

    Q_QLOAD = add_tracked_variable!(model, tracer, "Q_QLOAD_$(code)", time_index;
        lower_bound = params.data, upper_bound = params.data .+ 1.0)

    return @expression(model, 0.0)
end

function build_heat_load_status_model!(model, component::HeatLoad, params, ctx::BuildContext,
                                              code::String, tracer::CodeTracer, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)

    add_tracked_variable!(model, tracer, "Q_QLOAD_$(code)", time_index;
        lower_bound = 0.0, upper_bound = 1.0)

    return @expression(model, 0.0)
end

function build_heat_load_status_model!(model, component::HeatLoad, params, ctx::BuildContext,
                                              code::String, tracer::CodeTracer, status)
    error("HeatLoad status $(params.status) is intentionally left blank because the original implementation does not define a dedicated model yet.")
end
