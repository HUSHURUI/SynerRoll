# ═══════════════════════════════════════════════════════════════════════════
# power_grid/model-base.jl — 数学原理蓝图
#
# 本文件是电网接口模型的原始实现，变量名无后缀，用于：
#   - 单实例场景的数学功能验证
#   - 理解模型的数学原理
#
# 共享函数（resolve_power_grid_params）见 model-common.jl
# 对应的元编程追踪版本见 model.jl
# ═══════════════════════════════════════════════════════════════════════════

function build_component_model!(model, component::PowerGrid, ctx::BuildContext)
    params = resolve_power_grid_params(component, ctx)
    return build_power_grid_status_model!(model, component, params, ctx, Val(Symbol(params.status)))
end

function build_power_grid_status_model!(model, component::PowerGrid, params, ctx::BuildContext, ::Val{:stand_alone})
    time_index = generate_timespan(ctx.layer)

    # E_GRID_in：向电网上送（售电）；E_GRID_out：从电网购入（购电）。
    # 并网点功率 P_POI = E_GRID_in − E_GRID_out，正表示上送、负表示购入。
    @variable(model, E_GRID_in[t in time_index], lower_bound = 0.0, upper_bound = params.maximum_sell_power_kw)
    @variable(model, E_GRID_out[t in time_index], lower_bound = 0.0, upper_bound = params.maximum_buy_power_kw)

    objective_expr = @expression(model, 0.0)
    if params.exchange_objective_on
        objective_expr += define_grid_exchange_cost!(model, time_index, E_GRID_in, E_GRID_out,
            params.buy_price, params.sell_price)
    end

    return objective_expr
end

function build_power_grid_status_model!(model, component::PowerGrid, params, ctx::BuildContext, ::Val{:disabled})
    time_index = generate_timespan(ctx.layer)
    # 停用即离网：P_POI = 0，缺额必须由本地资源或平衡松弛承担。
    @variable(model, E_GRID_in[t in time_index], lower_bound = 0.0, upper_bound = 0.0)
    @variable(model, E_GRID_out[t in time_index], lower_bound = 0.0, upper_bound = 0.0)
    return @expression(model, 0.0)
end

function build_power_grid_status_model!(model, component::PowerGrid, params, ctx::BuildContext, status)
    error("PowerGrid status $(params.status) is intentionally left blank because the original implementation does not define a dedicated model yet.")
end

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════════

# 购售电成本：购电为正成本、售电为负成本（收益）。
# 购电价不低于售电价时最优解不会同时购售（同时减少 ε 则净交换不变、成本不增），
# 因此首版不引入购售互斥二元变量。
function define_grid_exchange_cost!(model, time_index, sell_power, buy_power, buy_price, sell_price)
    return @expression(model, C_grid_exchange, sum((buy_power[t] * buy_price - sell_power[t] * sell_price) for t in time_index))
end
