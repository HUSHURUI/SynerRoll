# ═══════════════════════════════════════════════════════════════════════════
# economy_evaluation_service.jl — 经济性评价服务
#
# 职责：
#   - 从 timeseries.db 读取覆盖模式的物理量数据
#   - 调用 economy_calculator.jl 计算各项成本
#   - 汇总分层、分设备、分成本项的结果
# ═══════════════════════════════════════════════════════════════════════════

# ───── 数据结构 ──────────────────────────────────────────────────────────

"""时层经济性汇总"""
struct LayerEconomySummary
    layer_id::String
    layer_name::String
    total_cost::Float64                         # 该层总成本（不含松弛惩罚）
    cost_breakdown::Dict{String, Float64}       # 按成本类型分组 {"om_cost": 1234.5, ...}
    component_breakdown::Dict{String, Float64}  # 按组件分组 {"CP_7e8a": 5678.9, ...}
    objective_components::Vector{String}        # 进入目标函数的成本项标识
    objective_value::Float64                    # 目标函数值（不含松弛惩罚）
    slack_penalty::Float64                      # 松弛变量惩罚成本
    has_slack::Bool                             # 是否存在松弛变量 > 0
    revenue_items::Dict{String, Float64}        # 收益项（负成本）{"sell_revenue": -3000, ...}
end

"""完整经济性评价结果"""
struct EconomyEvaluationResult
    task_id::String
    evaluation_time::String
    layers::Vector{LayerEconomySummary}
    all_cost_items::Vector{CostItem}
    objective_composition::Dict{String, Dict{String, Float64}}  # 各层目标函数组成
end

# ───── 辅助函数 ──────────────────────────────────────────────────────────

"""安全读取时序数据并按仿真范围截取，不存在时返回空数组"""
function _safe_get_ts_values(db_path::String, data_key::String, sim_start::String, sim_end::Union{String,Nothing})::Vector{Float64}
    ts = get_ts(db_path, data_key)
    ts === nothing && return Float64[]
    filtered = truncate_timeseries(ts, sim_start, sim_end)
    return filtered.values
end

"""从 project.json 中获取时层列表（按 id 排序）"""
function _get_layers(project_json::Dict)
    layer_config = get(project_json, "layerConfig", get(project_json, "layers", Dict()))
    layers_array = get(layer_config, "layers", [])
    if isempty(layers_array)
        # 尝试从 Dict 格式读取
        layers = Dict{String,Any}[]
        for (lid, ldata) in layer_config
            if ldata isa Dict
                push!(layers, merge(ldata, Dict("id" => lid)))
            end
        end
        return sort(layers; by=x -> parse(Int, string(get(x, "id", "1"))))
    end
    return sort(collect(layers_array); by=x -> parse(Int, string(get(x, "id", "1"))))
end

"""从 project.json 中获取算法配置"""
function _get_algorithms(project_json::Dict)
    return get(project_json, "algorithm", Dict{String,Any}())
end

"""从 project.json 中获取节点列表（合并所有画布节点）"""
function _get_nodes(project_json::Dict)
    workspace = get(project_json, "workspace", Dict())
    canvases = get(workspace, "canvases", [])
    nodes = []
    for canvas in canvases
        append!(nodes, get(canvas, "nodes", []))
    end
    return nodes
end

"""解析组件节点，返回 (component_dicts, node_id_to_code, node_id_to_name)"""
function _parse_component_nodes(nodes::Vector)
    component_dicts = Dict{String,Any}[]
    node_id_to_code = Dict{String,String}()
    node_id_to_name = Dict{String,String}()

    for node in nodes
        is_bus_node(node) && continue
        data = get(node, "data", Dict())
        comp_key = get(data, "componentKey", "")
        isempty(comp_key) && continue

        node_id = get(node, "id", "")
        label = get(data, "label", comp_key)
        business = get(data, "business", Dict())
        code = node_id_to_code_from_node(node_id)

        node_id_to_code[node_id] = code
        node_id_to_name[node_id] = label

        # 构建 component dict（与 parse_service 输出格式兼容）
        paras = Dict{String,Any}()
        costs = Dict{String,Float64}()
        # 前端画布中参数分别存放在 commonTechParams / commonEconomicParams
        eco_params = get(business, "commonEconomicParams", get(business, "economicParams", Dict()))
        tech_params = get(business, "commonTechParams", get(business, "techParams", Dict()))
        for (k, v) in tech_params
            v isa Real && (paras[string(k)] = v)
        end
        for (k, v) in eco_params
            v isa Real && (costs[string(k)] = Float64(v))
        end

        raw_layer_configs = get(business, "layerConfigs", Dict{String,Any}())
        layer_configs = Dict{String,Any}()
        for (layer_id, layer_data) in raw_layer_configs
            layer_configs[layer_id] = Dict{String,Any}(
                "status" => get(layer_data, "status", "stand_alone"),
                "paras" => get(layer_data, "techParams", Dict{String,Any}()),
                "costs" => get(layer_data, "economicParams", Dict{String,Any}()),
                "constraints" => _flatten_enabled(get(layer_data, "constraints", Dict{String,Any}())),
                "objectives" => _flatten_enabled(get(layer_data, "objectives", Dict{String,Any}())),
            )
        end

        boundary_ids = String[string(id) for id in get(business, "boundaryIds", [])]

        push!(component_dicts, Dict{String,Any}(
            "type" => comp_key,
            "name" => label,
            "code" => code,
            "paras" => paras,
            "costs" => costs,
            "layer" => layer_configs,
            "boundaryIds" => boundary_ids,
            "nodeId" => node_id,
        ))
    end

    return component_dicts, node_id_to_code, node_id_to_name
end

"""从 nodeID 提取短编码（与 parse_service 一致）"""
function node_id_to_code_from_node(node_id::String)::String
    prefix = "node-"
    if startswith(node_id, prefix)
        return node_id[length(prefix)+1:min(end, length(prefix)+4)]
    end
    return node_id[1:min(end, 4)]
end

"""将 {"key": {"enabled": true/false}} 展平为 {"key": true/false}"""
function _flatten_enabled(d::Dict{String,Any})
    result = Dict{String,Any}()
    for (k, v) in d
        if v isa Dict && haskey(v, "enabled")
            result[k] = v["enabled"]
        else
            result[k] = v
        end
    end
    return result
end

# ───── 核心函数 ──────────────────────────────────────────────────────────

"""
    load_component_data(store_path, comp_code, comp_type, layer_id) -> Dict{String, Vector{Float64}}

从覆盖模式的数据读取组件物理量。
"""
function load_component_data(store_path::String, comp_code::String, comp_type::String, layer_id::String, sim_start::String, sim_end::Union{String,Nothing})::Dict{String,Vector{Float64}}
    data = Dict{String,Vector{Float64}}()

    if comp_type == "CP"
        data["power"] = _safe_get_ts_values(store_path, "CP|E_CP_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
        data["status"] = _safe_get_ts_values(store_path, "CP|F_CP_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
    elseif comp_type == "WT"
        data["power"] = _safe_get_ts_values(store_path, "WT|E_WT_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
        data["cut"] = _safe_get_ts_values(store_path, "WT|E_WT_cut_$(comp_code)|cut#$(layer_id)", sim_start, sim_end)
    elseif comp_type == "PV"
        data["power"] = _safe_get_ts_values(store_path, "PV|E_PV_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
        data["cut"] = _safe_get_ts_values(store_path, "PV|E_PV_cut_$(comp_code)|cut#$(layer_id)", sim_start, sim_end)
    elseif comp_type == "ES"
        data["energy"] = _safe_get_ts_values(store_path, "ES|E_ES_$(comp_code)|energy#$(layer_id)", sim_start, sim_end)
        data["input"] = _safe_get_ts_values(store_path, "ES|E_ES_in_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
        data["output"] = _safe_get_ts_values(store_path, "ES|E_ES_out_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
    elseif comp_type == "GP"
        data["power"] = _safe_get_ts_values(store_path, "GP|E_GP_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
        data["status"] = _safe_get_ts_values(store_path, "GP|F_GP_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
    elseif comp_type == "CHP"
        data["power"] = _safe_get_ts_values(store_path, "CHP|E_CHP_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
        data["status"] = _safe_get_ts_values(store_path, "CHP|F_CHP_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
    elseif comp_type == "ET"
        data["power"] = _safe_get_ts_values(store_path, "ET|E_ET_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
        data["status"] = _safe_get_ts_values(store_path, "ET|F_ET_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
    elseif comp_type == "GRID"
        data["sell"] = _safe_get_ts_values(store_path, "GRID|E_GRID_in_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
        data["buy"] = _safe_get_ts_values(store_path, "GRID|E_GRID_out_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
    elseif comp_type in ("HS", "FS", "CS", "PS")
        # 其他储能类型
        data["energy"] = _safe_get_ts_values(store_path, "$(comp_type)|E_$(comp_type)_$(comp_code)|energy#$(layer_id)", sim_start, sim_end)
        data["input"] = _safe_get_ts_values(store_path, "$(comp_type)|E_$(comp_type)_in_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
        data["output"] = _safe_get_ts_values(store_path, "$(comp_type)|E_$(comp_type)_out_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
    elseif comp_type == "HYDRO"
        data["power"] = _safe_get_ts_values(store_path, "HYDRO|E_HYDRO_$(comp_code)|power#$(layer_id)", sim_start, sim_end)
    end

    return data
end

"""
    load_slack_data(store_path, layer_id) -> Vector{CostItem}

读取松弛变量数据并计算惩罚成本。
"""
function load_slack_data(store_path::String, layer_id::String, penalty_rate::Float64, sim_start::String, sim_end::Union{String,Nothing})::Vector{CostItem}
    items = CostItem[]

    start_min = time_label_to_minutes(sim_start)
    end_min = sim_end !== nothing ? time_label_to_minutes(sim_end) : nothing

    # 查询所有松弛变量的 meta 记录
    store = get_store(store_path)
    lock(store.write_lock) do
        rows = _query(store.db,
            "SELECT id, source_id, var_name, remark, layer_id FROM time_series_meta WHERE var_name LIKE '%SHORTAGE%' OR var_name LIKE '%EXCESS%'")

        isempty(rows[1]) && return items

        for i in 1:length(rows[1])
            series_layer_id = String(rows[5][i])
            series_layer_id != layer_id && continue

            series_id = rows[1][i]
            var_name_str = String(rows[3][i])

            data_rows = _query(store.db,
                "SELECT ts, value FROM time_series_data WHERE series_id=?", [series_id])
            isempty(data_rows[1]) && continue

            values = Float64[]
            for (ts_label, val) in zip(data_rows[1], data_rows[2])
                m = time_label_to_minutes(ts_label)
                m >= start_min && (end_min === nothing || m < end_min) && push!(values, val)
            end

            if occursin("SHORTAGE", var_name_str)
                val = sum(values) * penalty_rate
                if val > 0.0
                    bus_code = replace(var_name_str, "E_SHORTAGE_" => "", "H_SHORTAGE_" => "", "Q_SHORTAGE_" => "")
                    push!(items, CostItem(
                        "BUS_$(bus_code)", "BUS", "总线($(bus_code))",
                        "shortage_penalty", cost_label("shortage_penalty"),
                        layer_id, val, false, true, false,
                    ))
                end
            elseif occursin("EXCESS", var_name_str)
                val = sum(values) * penalty_rate
                if val > 0.0
                    bus_code = replace(var_name_str, "E_EXCESS_" => "", "H_EXCESS_" => "", "Q_EXCESS_" => "")
                    push!(items, CostItem(
                        "BUS_$(bus_code)", "BUS", "总线($(bus_code))",
                        "excess_penalty", cost_label("excess_penalty"),
                        layer_id, val, false, true, false,
                    ))
                end
            end
        end
    end

    return items
end

"""
    resolve_component_params_economy(comp_dict, layer_id) -> NamedTuple

为经济性评价解析组件参数（复用 model-common.jl 的逻辑）。
返回包含 om_cost, on_off_cost, adjust_cost, buy_price, sell_price, cut_cost, layer_settings 的 named tuple。
"""
function resolve_component_params_economy(comp_dict::Dict{String,Any}, layer_id::String)
    comp_type = comp_dict["type"]
    costs = get(comp_dict, "costs", Dict{String,Any}())
    layer_configs = get(comp_dict, "layer", Dict{String,Any}())
    layer_cfg = get(layer_configs, layer_id, Dict{String,Any}())
    layer_objectives = get(get(layer_cfg, "objectives", Dict{String,Any}()), "objectives", get(layer_cfg, "objectives", Dict{String,Any}()))

    # 获取时层的 step 信息（从 project.json 的 layerConfig 中）
    # 默认使用 1h
    time_step_hours = 1.0

    layer_settings = Dict(
        "status" => get(layer_cfg, "status", "stand_alone"),
        "objectives" => layer_objectives,
        "paras" => get(layer_cfg, "paras", Dict{String,Any}()),
        "costs" => get(layer_cfg, "costs", Dict{String,Any}()),
        "constraints" => get(layer_cfg, "constraints", Dict{String,Any}()),
    )

    if comp_type == "CP" || comp_type == "GP" || comp_type == "CHP" || comp_type == "ET"
        return (
            om_cost = get(costs, "om_cost", 0.0) * time_step_hours,
            on_off_cost = get(costs, "on_off_cost", 0.0) * time_step_hours,
            adjust_cost = get(get(get(layer_cfg, "costs", Dict()), "costs", get(layer_cfg, "costs", Dict())), "adjust_cost",
                get(costs, "adjust_cost", 0.0)) * time_step_hours,
            layer_settings = layer_settings,
        )
    elseif comp_type == "WT" || comp_type == "PV"
        return (
            om_cost = get(costs, "om_cost", 0.0) * time_step_hours,
            cut_cost = get(costs, "cut_cost", 0.0) * time_step_hours,
            layer_settings = layer_settings,
        )
    elseif comp_type in ("ES", "HS", "FS", "CS", "PS")
        return (
            om_cost = get(costs, "om_cost", 0.0) * time_step_hours,
            adjust_cost = get(get(get(layer_cfg, "costs", Dict()), "costs", get(layer_cfg, "costs", Dict())), "adjust_cost",
                get(costs, "adjust_cost", 0.0)) * time_step_hours,
            layer_settings = layer_settings,
        )
    elseif comp_type == "GRID"
        return (
            buy_price = get(costs, "buy_price", 0.0) * time_step_hours,
            sell_price = get(costs, "sell_price", 0.0) * time_step_hours,
            layer_settings = layer_settings,
        )
    else
        return (
            om_cost = get(costs, "om_cost", 0.0) * time_step_hours,
            layer_settings = layer_settings,
        )
    end
end

"""
    build_layer_summary(layer_id, layer_name, cost_items) -> LayerEconomySummary

汇总单个时层的经济性指标。
"""
function build_layer_summary(layer_id::String, layer_name::String, cost_items::Vector{CostItem})
    total_cost = 0.0
    objective_value = 0.0
    slack_penalty = 0.0
    has_slack = false
    cost_breakdown = Dict{String,Float64}()
    component_breakdown = Dict{String,Float64}()
    objective_components = String[]
    revenue_items = Dict{String,Float64}()

    for item in cost_items
        # 按成本类型汇总
        cost_breakdown[item.cost_type] = get(cost_breakdown, item.cost_type, 0.0) + item.value

        # 按组件汇总
        comp_key = "$(item.component_type)_$(item.component_id)"
        component_breakdown[comp_key] = get(component_breakdown, comp_key, 0.0) + item.value

        if item.is_slack
            slack_penalty += item.value
            has_slack = true
        elseif item.is_revenue
            revenue_items[item.cost_type] = get(revenue_items, item.cost_type, 0.0) + item.value
            if item.in_objective
                objective_value += item.value
                push!(objective_components, "$(item.component_id)|$(item.cost_type)")
            end
            total_cost += item.value
        else
            if item.in_objective
                objective_value += item.value
                push!(objective_components, "$(item.component_id)|$(item.cost_type)")
            end
            total_cost += item.value
        end
    end

    return LayerEconomySummary(
        layer_id, layer_name,
        total_cost, cost_breakdown, component_breakdown,
        objective_components, objective_value,
        slack_penalty, has_slack, revenue_items,
    )
end

"""
    evaluate_task_economy(task_id, project_json; sim_start_time, sim_end_time) -> Dict

计算任务的完整经济性指标。返回可直接 JSON 序列化的 Dict。
"""
function evaluate_task_economy(
    task_id::String,
    project_json::Dict;
    sim_start_time::Union{String,Nothing}=nothing,
    sim_end_time::Union{String,Nothing}=nothing,
)
    store_path = joinpath(TASKS_DATA_ROOT, task_id, "timeseries.db")
    if !isfile(store_path)
        error("任务数据不存在: timeseries.db 未找到")
    end

    sim_start = sim_start_time !== nothing ? sim_start_time : "0:00"
    sim_end = sim_end_time
    sim_end === nothing && error("缺少仿真结束时间，无法计算经济性指标")

    # 解析项目结构
    layers = _get_layers(project_json)
    algorithms = _get_algorithms(project_json)
    nodes = _get_nodes(project_json)
    component_dicts, node_id_to_code, node_id_to_name = _parse_component_nodes(nodes)

    # 获取松弛惩罚系数
    _, slack_penalty = get_slack_config(algorithms)

    # 获取时层 step 信息用于 time_step_hours 计算
    layer_step_hours = Dict{String,Float64}()
    for layer in layers
        lid = string(get(layer, "id", "1"))
        step_str = get(layer, "step", "1h")
        layer_step_hours[lid] = _parse_duration_hours(step_str)
    end

    all_cost_items = CostItem[]
    layer_summaries = LayerEconomySummary[]
    objective_composition = Dict{String,Dict{String,Float64}}()

    for layer in layers
        layer_id = string(get(layer, "id", "1"))
        layer_name = get(layer, "name", "时层$(layer_id)")
        time_step_hours = get(layer_step_hours, layer_id, 1.0)

        layer_cost_items = CostItem[]

        for comp_dict in component_dicts
            comp_type = comp_dict["type"]
            comp_code = comp_dict["code"]
            comp_name = get(comp_dict, "name", comp_type)
            comp_node_id = get(comp_dict, "nodeId", "")

            # 跳过负荷类型（不产生经济性成本）
            comp_type in ("ELOAD", "HLOAD", "QLOAD") && continue

            # 读取物理量数据
            power_data = load_component_data(store_path, comp_code, comp_type, layer_id, sim_start, sim_end)

            # 检查数据是否存在（全为空则跳过）
            has_data = false
            for (_, v) in power_data
                if !isempty(v)
                    has_data = true
                    break
                end
            end
            !has_data && continue

            # 解析组件参数
            params = resolve_component_params_economy_with_step(comp_dict, layer_id, time_step_hours)

            # 计算成本
            items = calc_component_cost(comp_type, comp_node_id, comp_name, power_data, params, layer_id)
            append!(layer_cost_items, items)
        end

        # 读取松弛变量
        slack_items = load_slack_data(store_path, layer_id, slack_penalty, sim_start, sim_end)
        append!(layer_cost_items, slack_items)

        # 构建层汇总
        summary = build_layer_summary(layer_id, layer_name, layer_cost_items)
        push!(layer_summaries, summary)

        # 记录目标函数组成
        obj_comp = Dict{String,Float64}()
        for item in layer_cost_items
            if item.in_objective
                obj_comp[item.cost_type] = get(obj_comp, item.cost_type, 0.0) + item.value
            end
        end
        objective_composition[layer_id] = obj_comp

        append!(all_cost_items, layer_cost_items)
    end

    # 构建返回结果
    return Dict(
        "taskId" => task_id,
        "evaluationTime" => string(Dates.now()),
        "layers" => [Dict(
            "layerId" => s.layer_id,
            "layerName" => s.layer_name,
            "totalCost" => round(s.total_cost; digits=2),
            "costBreakdown" => Dict(k => round(v; digits=2) for (k, v) in s.cost_breakdown),
            "componentBreakdown" => Dict(k => round(v; digits=2) for (k, v) in s.component_breakdown),
            "objectiveComponents" => s.objective_components,
            "objectiveValue" => round(s.objective_value; digits=2),
            "slackPenalty" => round(s.slack_penalty; digits=2),
            "hasSlack" => s.has_slack,
            "revenueItems" => Dict(k => round(v; digits=2) for (k, v) in s.revenue_items),
        ) for s in layer_summaries],
        "allCostItems" => [Dict(
            "componentId" => item.component_id,
            "componentType" => item.component_type,
            "componentName" => item.component_name,
            "costType" => item.cost_type,
            "costLabel" => item.cost_label,
            "layerId" => item.layer_id,
            "value" => round(item.value; digits=2),
            "inObjective" => item.in_objective,
            "isSlack" => item.is_slack,
            "isRevenue" => item.is_revenue,
        ) for item in all_cost_items],
        "objectiveComposition" => Dict(
            lid => Dict(k => round(v; digits=2) for (k, v) in comp)
            for (lid, comp) in objective_composition
        ),
    )
end

"""
    resolve_component_params_economy_with_step(comp_dict, layer_id, time_step_hours) -> NamedTuple

带 time_step_hours 参数的组件参数解析。
"""
function resolve_component_params_economy_with_step(comp_dict::Dict{String,Any}, layer_id::String, time_step_hours::Float64)
    comp_type = comp_dict["type"]
    costs = get(comp_dict, "costs", Dict{String,Any}())
    layer_configs = get(comp_dict, "layer", Dict{String,Any}())
    layer_cfg = get(layer_configs, layer_id, Dict{String,Any}())

    layer_objectives = get(layer_cfg, "objectives", Dict{String,Any}())

    layer_settings = Dict(
        "status" => get(layer_cfg, "status", "stand_alone"),
        "objectives" => layer_objectives,
        "paras" => get(layer_cfg, "paras", Dict{String,Any}()),
        "costs" => get(layer_cfg, "costs", Dict{String,Any}()),
        "constraints" => get(layer_cfg, "constraints", Dict{String,Any}()),
    )

    layer_costs = get(layer_cfg, "costs", Dict{String,Any}())

    if comp_type in ("CP", "GP", "CHP", "ET")
        return (
            om_cost = get(costs, "om_cost", 0.0) * time_step_hours,
            on_off_cost = get(costs, "on_off_cost", 0.0) * time_step_hours,
            adjust_cost = get(layer_costs, "adjust_cost", get(costs, "adjust_cost", 0.0)) * time_step_hours,
            layer_settings = layer_settings,
        )
    elseif comp_type in ("WT", "PV")
        return (
            om_cost = get(costs, "om_cost", 0.0) * time_step_hours,
            cut_cost = get(costs, "cut_cost", 0.0) * time_step_hours,
            layer_settings = layer_settings,
        )
    elseif comp_type in ("ES", "HS", "FS", "CS", "PS")
        return (
            om_cost = get(costs, "om_cost", 0.0) * time_step_hours,
            adjust_cost = get(layer_costs, "adjust_cost", get(costs, "adjust_cost", 0.0)) * time_step_hours,
            layer_settings = layer_settings,
        )
    elseif comp_type == "GRID"
        return (
            buy_price = get(costs, "buy_price", 0.0) * time_step_hours,
            sell_price = get(costs, "sell_price", 0.0) * time_step_hours,
            layer_settings = layer_settings,
        )
    else
        return (
            om_cost = get(costs, "om_cost", 0.0) * time_step_hours,
            layer_settings = layer_settings,
        )
    end
end

"""解析时长字符串为小时数（如 "1h" -> 1.0, "15m" -> 0.25）"""
function _parse_duration_hours(s::String)
    s = strip(s)
    if endswith(s, "h")
        return parse(Float64, s[1:end-1])
    elseif endswith(s, "m")
        return parse(Float64, s[1:end-1]) / 60.0
    elseif endswith(s, "s")
        return parse(Float64, s[1:end-1]) / 3600.0
    else
        return parse(Float64, s)
    end
end
