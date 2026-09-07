# ═══════════════════════════════════════════════════════════════════════════
# economy_calculator.jl — 经济性评价计算模块
#
# 职责：
#   - 提供纯数值计算函数（不依赖 JuMP、不依赖数据库）
#   - 被评价服务层调用（后验计算）
#   - 复用 model-common.jl 的参数解析逻辑
# ═══════════════════════════════════════════════════════════════════════════

# ───── 数据结构 ──────────────────────────────────────────────────────────

"""单项成本计算结果"""
struct CostItem
    component_id::String       # 组件标识 (如 "node-7e8a")
    component_type::String     # 组件类型 (如 "CP")
    component_name::String     # 组件名称 (如 "燃煤机组1号")
    cost_type::String          # 成本类型 (如 "om_cost", "on_off_cost")
    cost_label::String         # 显示标签 (如 "运维成本", "启停成本")
    layer_id::String           # 时层ID
    value::Float64             # 成本值（元），可为负数（如售电收益）
    in_objective::Bool         # 是否进入目标函数
    is_slack::Bool             # 是否为松弛变量成本
    is_revenue::Bool           # 是否为收益项（负成本）
end

# ───── 成本标签映射 ──────────────────────────────────────────────────────

const COST_LABELS = Dict{String,String}(
    "om_cost"          => "运维成本",
    "on_off_cost"      => "启停成本",
    "adjust_cost"      => "调整成本",
    "cut_cost"         => "弃风/弃光成本",
    "purchase_cost"    => "购电成本",
    "sell_revenue"     => "售电收益",
    "shortage_penalty" => "短缺惩罚",
    "excess_penalty"   => "过剩惩罚",
)

cost_label(cost_type::String) = get(COST_LABELS, cost_type, cost_type)

# ═══════════════════════════════════════════════════════════════════════════
# 煤电 (CP) 成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_cp_om_cost(power_values, om_cost_rate) -> Float64

计算煤电运维成本：Σ(出力 × 成本率)
"""
function calc_cp_om_cost(power_values::Vector{Float64}, om_cost_rate::Float64)
    return sum(power_values) * om_cost_rate
end

"""
    calc_cp_on_off_cost(status_vector, on_off_cost_rate) -> Float64

计算煤电启停成本：启停次数 × 单次成本
status_vector: 0或1的状态数组，状态变化计为一次开或停
"""
function calc_cp_on_off_cost(status_vector::Vector{Float64}, on_off_cost_rate::Float64)
    length(status_vector) < 2 && return 0.0
    transitions = 0
    for i in 2:length(status_vector)
        if status_vector[i] != status_vector[i-1]
            transitions += 1
        end
    end
    return Float64(transitions) * on_off_cost_rate
end

"""
    calc_cp_adjust_cost(actual_power, planned_power, adjust_cost_rate) -> Float64

计算煤电调整成本：Σ|实际-计划| × 成本率
"""
function calc_cp_adjust_cost(actual_power::Vector{Float64}, planned_power::Vector{Float64}, adjust_cost_rate::Float64)
    n = min(length(actual_power), length(planned_power))
    total = 0.0
    for i in 1:n
        total += abs(actual_power[i] - planned_power[i])
    end
    return total * adjust_cost_rate
end

"""
    calc_cp_costs(power_values, params, layer_settings; status_vector=nothing, planned_power=nothing) -> Vector{CostItem}

计算煤电组件的所有成本项。
"""
function calc_cp_costs(
    component_id::String, component_name::String,
    power_values::Vector{Float64}, params, layer_id::String;
    status_vector::Union{Vector{Float64},Nothing}=nothing,
    planned_power::Union{Vector{Float64},Nothing}=nothing,
)
    items = CostItem[]

    # 运维成本
    om_on = get(get(params, :layer_settings, Dict()), "objectives", Dict()) |> d -> get(d, "om_objective_on", true)
    om_val = calc_cp_om_cost(power_values, params.om_cost)
    push!(items, CostItem(component_id, "CP", component_name, "om_cost", cost_label("om_cost"),
        layer_id, om_val, om_on, false, false))

    # 启停成本
    if status_vector !== nothing
        on_off_on = get(get(params, :layer_settings, Dict()), "objectives", Dict()) |> d -> get(d, "on_off_objective_on", true)
        on_off_val = calc_cp_on_off_cost(status_vector, params.on_off_cost)
        push!(items, CostItem(component_id, "CP", component_name, "on_off_cost", cost_label("on_off_cost"),
            layer_id, on_off_val, on_off_on, false, false))
    end

    # 调整成本
    if planned_power !== nothing
        adjust_on = get(get(params, :layer_settings, Dict()), "objectives", Dict()) |> d -> get(d, "adjust_objective_on", true)
        adjust_val = calc_cp_adjust_cost(power_values, planned_power, params.adjust_cost)
        push!(items, CostItem(component_id, "CP", component_name, "adjust_cost", cost_label("adjust_cost"),
            layer_id, adjust_val, adjust_on, false, false))
    end

    return items
end

# ═══════════════════════════════════════════════════════════════════════════
# 风电 (WT) / 光伏 (PV) 成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_wt_om_cost(power_values, om_cost_rate) -> Float64

计算风机运维成本：Σ(出力 × 成本率)
"""
function calc_wt_om_cost(power_values::Vector{Float64}, om_cost_rate::Float64)
    return sum(power_values) * om_cost_rate
end

"""
    calc_wt_cut_cost(cut_power, cut_cost_rate) -> Float64

计算弃风/弃光成本：Σ(弃风功率 × 成本率)
"""
function calc_wt_cut_cost(cut_power::Vector{Float64}, cut_cost_rate::Float64)
    return sum(cut_power) * cut_cost_rate
end

"""
    calc_renewable_costs(comp_type, component_id, component_name, power_values, cut_values, params, layer_id) -> Vector{CostItem}

计算风/光组件的所有成本项。
"""
function calc_renewable_costs(
    comp_type::String, component_id::String, component_name::String,
    power_values::Vector{Float64}, cut_values::Vector{Float64},
    params, layer_id::String,
)
    items = CostItem[]
    objectives = get(get(params, :layer_settings, Dict()), "objectives", Dict())

    # 运维成本
    om_on = get(objectives, "om_objective_on", true)
    om_val = calc_wt_om_cost(power_values, params.om_cost)
    push!(items, CostItem(component_id, comp_type, component_name, "om_cost", cost_label("om_cost"),
        layer_id, om_val, om_on, false, false))

    # 弃风/弃光成本
    cut_on = get(objectives, "cut_objective_on", true)
    cut_val = calc_wt_cut_cost(cut_values, params.cut_cost)
    cost_type = comp_type == "WT" ? "cut_cost" : "cut_cost"
    push!(items, CostItem(component_id, comp_type, component_name, cost_type, cost_label("cut_cost"),
        layer_id, cut_val, cut_on, false, false))

    return items
end

# ═══════════════════════════════════════════════════════════════════════════
# 储能 (ES/HS/FS/CS/PS) 成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_es_om_cost(input_power, output_power, om_cost_rate) -> Float64

计算储能运维成本：Σ(充放电功率 × 成本率)
"""
function calc_es_om_cost(input_power::Vector{Float64}, output_power::Vector{Float64}, om_cost_rate::Float64)
    n = min(length(input_power), length(output_power))
    total = 0.0
    for i in 1:n
        total += (input_power[i] + output_power[i])
    end
    return total * om_cost_rate
end

"""
    calc_es_adjust_cost(actual_input, actual_output, planned_input, planned_output, adjust_cost_rate) -> Float64

计算储能调整成本：Σ(|实际-计划|) × 成本率
"""
function calc_es_adjust_cost(
    actual_input::Vector{Float64}, actual_output::Vector{Float64},
    planned_input::Vector{Float64}, planned_output::Vector{Float64},
    adjust_cost_rate::Float64,
)
    n = min(length(actual_input), length(planned_input))
    total = 0.0
    for i in 1:n
        total += abs(actual_input[i] - planned_input[i]) + abs(actual_output[i] - planned_output[i])
    end
    return total * adjust_cost_rate
end

"""
    calc_storage_costs(comp_type, component_id, component_name, input_power, output_power, params, layer_id; planned_input=nothing, planned_output=nothing) -> Vector{CostItem}

计算储能组件的所有成本项。
"""
function calc_storage_costs(
    comp_type::String, component_id::String, component_name::String,
    input_power::Vector{Float64}, output_power::Vector{Float64},
    params, layer_id::String;
    planned_input::Union{Vector{Float64},Nothing}=nothing,
    planned_output::Union{Vector{Float64},Nothing}=nothing,
)
    items = CostItem[]
    objectives = get(get(params, :layer_settings, Dict()), "objectives", Dict())

    # 运维成本
    om_on = get(objectives, "om_objective_on", true)
    om_val = calc_es_om_cost(input_power, output_power, params.om_cost)
    push!(items, CostItem(component_id, comp_type, component_name, "om_cost", cost_label("om_cost"),
        layer_id, om_val, om_on, false, false))

    # 调整成本
    if planned_input !== nothing && planned_output !== nothing
        adjust_on = get(objectives, "adjust_objective_on", true)
        adjust_val = calc_es_adjust_cost(input_power, output_power, planned_input, planned_output, params.adjust_cost)
        push!(items, CostItem(component_id, comp_type, component_name, "adjust_cost", cost_label("adjust_cost"),
            layer_id, adjust_val, adjust_on, false, false))
    end

    return items
end

# ═══════════════════════════════════════════════════════════════════════════
# 气电 (GP) / 热电联产 (CHP) / 电解槽 (ET) 成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_thermal_gen_costs(comp_type, component_id, component_name, power_values, params, layer_id; status_vector=nothing, planned_power=nothing) -> Vector{CostItem}

计算气电/热电联产/电解槽组件的所有成本项。
这些组件有：运维成本、启停成本、调整成本（与煤电类似）。
"""
function calc_thermal_gen_costs(
    comp_type::String, component_id::String, component_name::String,
    power_values::Vector{Float64}, params, layer_id::String;
    status_vector::Union{Vector{Float64},Nothing}=nothing,
    planned_power::Union{Vector{Float64},Nothing}=nothing,
)
    items = CostItem[]
    objectives = get(get(params, :layer_settings, Dict()), "objectives", Dict())

    # 运维成本
    om_on = get(objectives, "om_objective_on", true)
    om_val = sum(power_values) * params.om_cost
    push!(items, CostItem(component_id, comp_type, component_name, "om_cost", cost_label("om_cost"),
        layer_id, om_val, om_on, false, false))

    # 启停成本
    if status_vector !== nothing
        on_off_on = get(objectives, "on_off_objective_on", true)
        on_off_val = calc_cp_on_off_cost(status_vector, params.on_off_cost)
        push!(items, CostItem(component_id, comp_type, component_name, "on_off_cost", cost_label("on_off_cost"),
            layer_id, on_off_val, on_off_on, false, false))
    end

    # 调整成本
    if planned_power !== nothing
        adjust_on = get(objectives, "adjust_objective_on", true)
        adjust_val = calc_cp_adjust_cost(power_values, planned_power, params.adjust_cost)
        push!(items, CostItem(component_id, comp_type, component_name, "adjust_cost", cost_label("adjust_cost"),
            layer_id, adjust_val, adjust_on, false, false))
    end

    return items
end

# ═══════════════════════════════════════════════════════════════════════════
# 电网 (GRID) 成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_grid_purchase_cost(purchase_power, buy_price) -> Float64

计算购电成本：Σ(购电功率 × 电价)
"""
function calc_grid_purchase_cost(purchase_power::Vector{Float64}, buy_price::Float64)
    return sum(purchase_power) * buy_price
end

"""
    calc_grid_sell_revenue(sell_power, sell_price) -> Float64

计算售电收益（返回负值）：-Σ(售电功率 × 电价)
"""
function calc_grid_sell_revenue(sell_power::Vector{Float64}, sell_price::Float64)
    return -sum(sell_power) * sell_price
end

"""
    calc_grid_costs(component_id, component_name, sell_power, buy_power, params, layer_id) -> Vector{CostItem}

计算电网组件的所有成本项。
"""
function calc_grid_costs(
    component_id::String, component_name::String,
    sell_power::Vector{Float64}, buy_power::Vector{Float64},
    params, layer_id::String,
)
    items = CostItem[]
    exchange_on = get(get(params, :layer_settings, Dict()), "objectives", Dict()) |> d -> get(d, "exchange_objective_on", true)

    # 购电成本
    purchase_val = calc_grid_purchase_cost(buy_power, params.buy_price)
    push!(items, CostItem(component_id, "GRID", component_name, "purchase_cost", cost_label("purchase_cost"),
        layer_id, purchase_val, exchange_on, false, false))

    # 售电收益（负成本）
    sell_val = calc_grid_sell_revenue(sell_power, params.sell_price)
    push!(items, CostItem(component_id, "GRID", component_name, "sell_revenue", cost_label("sell_revenue"),
        layer_id, sell_val, exchange_on, false, true))

    return items
end

# ═══════════════════════════════════════════════════════════════════════════
# 松弛变量成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_slack_penalty(shortage, excess, penalty_rate) -> Vector{CostItem}

计算松弛变量惩罚成本。
"""
function calc_slack_penalty(
    bus_id::String, bus_name::String,
    shortage::Vector{Float64}, excess::Vector{Float64},
    penalty_rate::Float64, layer_id::String,
)
    items = CostItem[]

    shortage_val = sum(shortage) * penalty_rate
    if shortage_val > 0.0
        push!(items, CostItem(bus_id, "BUS", bus_name, "shortage_penalty", cost_label("shortage_penalty"),
            layer_id, shortage_val, false, true, false))
    end

    excess_val = sum(excess) * penalty_rate
    if excess_val > 0.0
        push!(items, CostItem(bus_id, "BUS", bus_name, "excess_penalty", cost_label("excess_penalty"),
            layer_id, excess_val, false, true, false))
    end

    return items
end

# ═══════════════════════════════════════════════════════════════════════════
# 统一接口
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_component_cost(comp_type, component_id, component_name, power_data, params, layer_id) -> Vector{CostItem}

根据组件类型调用对应的计算函数。
- comp_type: 组件类型 ("CP", "WT", "PV", "ES", "GRID", ...)
- power_data: Dict，包含该组件的物理量数据
- params: 组件参数（named tuple）
- layer_id: 时层ID
"""
function calc_component_cost(
    comp_type::String, component_id::String, component_name::String,
    power_data::Dict{String,Vector{Float64}}, params, layer_id::String,
)
    if comp_type == "CP"
        return calc_cp_costs(
            component_id, component_name,
            get(power_data, "power", Float64[]), params, layer_id;
            status_vector=get(power_data, "status", nothing),
            planned_power=get(power_data, "planned_power", nothing),
        )
    elseif comp_type in ("WT", "PV")
        return calc_renewable_costs(
            comp_type, component_id, component_name,
            get(power_data, "power", Float64[]), get(power_data, "cut", Float64[]),
            params, layer_id,
        )
    elseif comp_type in ("ES", "HS", "FS", "CS", "PS")
        return calc_storage_costs(
            comp_type, component_id, component_name,
            get(power_data, "input", Float64[]), get(power_data, "output", Float64[]),
            params, layer_id;
            planned_input=get(power_data, "planned_input", nothing),
            planned_output=get(power_data, "planned_output", nothing),
        )
    elseif comp_type in ("GP", "CHP", "ET")
        return calc_thermal_gen_costs(
            comp_type, component_id, component_name,
            get(power_data, "power", Float64[]), params, layer_id;
            status_vector=get(power_data, "status", nothing),
            planned_power=get(power_data, "planned_power", nothing),
        )
    elseif comp_type == "GRID"
        return calc_grid_costs(
            component_id, component_name,
            get(power_data, "sell", Float64[]), get(power_data, "buy", Float64[]),
            params, layer_id,
        )
    else
        @warn "未知组件类型: $(comp_type)，跳过经济性计算"
        return CostItem[]
    end
end
