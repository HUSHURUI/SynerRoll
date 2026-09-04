# ═══════════════════════════════════════════════════════════════════════════
# heat_load/model-base.jl — 数学原理蓝图
#
# 本文件是热负荷组件模型的原始实现，变量名无后缀，用于：
#   - 单实例场景的数学功能验证
#   - 理解模型的数学原理
#
# 共享函数（resolve_heat_load_params）见 model-common.jl
# 对应的元编程追踪版本见 model.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::HeatLoad, ctx::BuildContext)
    params = resolve_heat_load_params(component, ctx)
    return build_heat_load_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_heat_load_status_model!(model, component::HeatLoad, params, ctx::BuildContext, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)
    @variable(model, Q_QLOAD[t in time_index], lower_bound=params.data[t], upper_bound=params.data[t] + 1.0)
    return @expression(model, 0.0)
end

function build_heat_load_status_model!(model, component::HeatLoad, params, ctx::BuildContext, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    @variable(model, Q_QLOAD[t in time_index], lower_bound=0.0, upper_bound=1.0)
    return @expression(model, 0.0)
end

function build_heat_load_status_model!(model, component::HeatLoad, params, ctx::BuildContext, status)
    error("HeatLoad status $(params.status) is intentionally left blank because the original implementation does not define a dedicated model yet.")
end
