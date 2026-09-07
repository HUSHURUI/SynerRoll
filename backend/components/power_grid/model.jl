# ═══════════════════════════════════════════════════════════════════════════
# power_grid/model.jl — 元编程架构
#
# 设计：
#   - 使用 JuMP 直接 API + CodeTracer 构建模型并记录代码
#   - 返回 (objective_expr, code_lines::Vector{String})
#   - 所有参数在代码追踪中内联为硬值
#   - 原始数学原理见 model-base.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::PowerGrid, ctx::BuildContext, tracer::CodeTracer)
    params = resolve_power_grid_params(component, ctx)
    code = component_code(component)
    return build_power_grid_status_model!(model, component, params, ctx, code, tracer, Val(Symbol(params.status)))
end

function build_power_grid_status_model!(model, component::PowerGrid, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)
    c = code

    # ── 变量 ──────────────────────────────────────────────────────────
    # E_GRID_in：向电网上送（售电）；E_GRID_out：从电网购入（购电）。
    # 并网点功率 P_POI = E_GRID_in − E_GRID_out，正表示上送、负表示购入。
    E_GRID_in = add_tracked_variable!(model, tracer, "E_GRID_in_$(c)", time_index;
        lower_bound=0.0, upper_bound=params.maximum_sell_power_kw)
    E_GRID_out = add_tracked_variable!(model, tracer, "E_GRID_out_$(c)", time_index;
        lower_bound=0.0, upper_bound=params.maximum_buy_power_kw)

    # ── 目标函数 ──────────────────────────────────────────────────────
    objective_expr = @expression(model, 0.0)
    if params.exchange_objective_on
        objective_expr += define_grid_exchange_cost_tracked!(model, tracer, time_index, E_GRID_in, E_GRID_out, params, c)
    end

    return objective_expr
end

function build_power_grid_status_model!(model, component::PowerGrid, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    c = code
    # 停用即离网：P_POI = 0，缺额必须由本地资源或平衡松弛承担。
    add_tracked_variable!(model, tracer, "E_GRID_in_$(c)", time_index; lower_bound=0.0, upper_bound=0.0)
    add_tracked_variable!(model, tracer, "E_GRID_out_$(c)", time_index; lower_bound=0.0, upper_bound=0.0)
    return @expression(model, 0.0)
end

function build_power_grid_status_model!(model, component::PowerGrid, params, ctx::BuildContext,
    code::String, tracer::CodeTracer, status)
    error("PowerGrid status $(params.status) is intentionally left blank because the original implementation does not define a dedicated model yet.")
end

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数（tracked 版本）
# ═══════════════════════════════════════════════════════════════════════════

function define_grid_exchange_cost_tracked!(model, tracer, time_index, sell_power, buy_power, params, c::String)
    expr = sum((buy_power[t] * params.buy_price - sell_power[t] * params.sell_price) for t in time_index)
    add_tracked_expression!(model, tracer, "C_grid_exchange_$(c)",
        "@expression(model, C_grid_exchange_$(c), sum((E_GRID_out_$(c)[t] * $(format_val(params.buy_price)) - E_GRID_in_$(c)[t] * $(format_val(params.sell_price))) for t in $(format_val(time_index))))",
        expr; to_objective=true)
    return expr
end
