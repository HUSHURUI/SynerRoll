# 画布解析服务
# 功能：前端项目 JSON → component.json + connection.json + mapping.json
# 入口：parse_project(project_json; output_dir)
# 被 simulation_runner.jl 在任务 PARSE 阶段调用

# ═══════════════════════════════════════════════════════════════════════════
# 类型定义
# ═══════════════════════════════════════════════════════════════════════════

Base.@kwdef struct ComponentRecord
    type::String
    name::String
    code::String
    paras::Dict{String, Any}
    costs::Dict{String, Float64}
    layer::Dict{String, Any}
    boundaryIds::Vector{String}
end

Base.@kwdef mutable struct ConnectionRecord
    busLabel::String
    busCode::String = ""
    variables::Vector{String}
end

Base.@kwdef struct ParseResult
    success::Bool
    message::String
    outputPath::String = ""
    componentCount::Int = 0
    connectionCount::Int = 0
end

Base.@kwdef struct NodeCodeMapping
    nodeId::String
    componentKey::String
    componentName::String
    code::String
end

# ═══════════════════════════════════════════════════════════════════════════
# 常量
# ═══════════════════════════════════════════════════════════════════════════

const MEDIUM_PREFIX = Dict(
    "electric" => "E",
    "thermal" => "Q",
    "gas" => "G",
    "hydrogen" => "H",
    "material" => "M",  # ？？后续再改介质
    "general" => "X",
    "ammonia" => "NH3",
    "methanol" => "M",
    "carbon" => "C"
)

const NODE_ID_PREFIX = "node-"

# ═══════════════════════════════════════════════════════════════════════════
# 节点 / 连线工具函数
# ═══════════════════════════════════════════════════════════════════════════

is_bus_node(node) = get(get(node, "data", Dict()), "categoryKey", "") == "bus"
get_component_key(node) = get(get(node, "data", Dict()), "componentKey", "")
get_node_label(node) = get(get(node, "data", Dict()), "label", "")
get_business_data(node) = get(get(node, "data", Dict()), "business", Dict())
get_port_config(node) = get(get(node, "data", Dict()), "portConfig", Dict())

function get_node_by_id(nodes, node_id::String)::Union{Dict, Nothing}
    for node in nodes
        if get(node, "id", "") == node_id
            return node
        end
    end
    return nothing
end

get_edge_medium(edge) = get(get(edge, "data", Dict()), "medium", "general")

"""将前端的 {"key": {"enabled": true/false}} 展平为 {"key": true/false}"""
function flatten_enabled_flags(dict::Dict{String, Any})::Dict{String, Any}
    result = Dict{String, Any}()
    for (k, v) in dict
        if v isa Dict && haskey(v, "enabled")
            result[k] = v["enabled"]
        else
            result[k] = v
        end
    end
    return result
end

function strip_handle_suffix(handle_id::String)::String
    handle_id = replace(handle_id, "-src" => "")
    handle_id = replace(handle_id, "-tgt" => "")
    return handle_id
end

function strip_bus_handle_suffix(handle_id::String)::String
    return replace(handle_id, "bus-" => "")
end

"""从 nodeID 提取短编码：去掉 'node-' 前缀后取前4个字符"""
function node_id_to_code(node_id::String)::String
    if startswith(node_id, NODE_ID_PREFIX)
        return node_id[length(NODE_ID_PREFIX)+1:min(end, length(NODE_ID_PREFIX)+4)]
    end
    return node_id[1:min(end, 4)]
end

function build_node_code_mapping(nodes)::Tuple{Dict{String, String}, Vector{NodeCodeMapping}}
    node_to_code = Dict{String, String}()
    mappings = NodeCodeMapping[]
    for node in nodes
        if !is_bus_node(node)
            node_id = get(node, "id", "")
            code = node_id_to_code(node_id)
            node_to_code[node_id] = code
            push!(mappings, NodeCodeMapping(;
                nodeId = node_id,
                componentKey = get_component_key(node),
                componentName = get_node_label(node),
                code = code
            ))
        end
    end
    return node_to_code, mappings
end

function build_variable_name(component_key::String, medium::String, direction::Symbol, node_code::String)::String
    prefix = get(MEDIUM_PREFIX, medium, "X")
    dir_str = direction == :out ? "out" : "in"
    return "$(prefix)_$(component_key)_$(dir_str)_$(node_code)"
end

# ═══════════════════════════════════════════════════════════════════════════
# 校验
# ═══════════════════════════════════════════════════════════════════════════

function validate_edge_mediums(edge, source_node, target_node)::Union{Nothing, String}
    edge_medium = get_edge_medium(edge)

    function get_bus_port_medium(node, handle_id)
        handle_id = strip_handle_suffix(handle_id)
        port_config = get_port_config(node)
        if haskey(port_config, handle_id)
            return get(port_config[handle_id], "medium", "general")
        end
        return "general"
    end

    if is_bus_node(source_node)
        port_medium = get_bus_port_medium(source_node, get(edge, "sourceHandle", ""))
        if port_medium != edge_medium
            return "总线端口介质 ($(port_medium)) 与连线介质 ($(edge_medium)) 不一致"
        end
    end

    if is_bus_node(target_node)
        port_medium = get_bus_port_medium(target_node, get(edge, "targetHandle", ""))
        if port_medium != edge_medium
            return "总线端口介质 ($(port_medium)) 与连线介质 ($(edge_medium)) 不一致"
        end
    end

    if !is_bus_node(source_node) && !is_bus_node(target_node)
        source_handle = strip_handle_suffix(get(edge, "sourceHandle", ""))
        target_handle = strip_handle_suffix(get(edge, "targetHandle", ""))
        source_port_config = get_port_config(source_node)
        target_port_config = get_port_config(target_node)
        source_pm = haskey(source_port_config, source_handle) ? get(source_port_config[source_handle], "medium", "general") : "general"
        target_pm = haskey(target_port_config, target_handle) ? get(target_port_config[target_handle], "medium", "general") : "general"
        if source_pm != target_pm
            return "二元连线两端端口介质不匹配：$(source_pm) vs $(target_pm)"
        end
    end

    return nothing
end

function validate_no_nested_buses(edge, all_nodes)::Union{Nothing, String}
    source_node = get_node_by_id(all_nodes, get(edge, "source", ""))
    target_node = get_node_by_id(all_nodes, get(edge, "target", ""))
    if source_node === nothing || target_node === nothing
        return "连线引用了不存在的节点"
    end
    if is_bus_node(source_node) && is_bus_node(target_node)
        return "不允许嵌套总线连接：$(get_node_label(source_node)) -> $(get_node_label(target_node))"
    end
    return validate_edge_mediums(edge, source_node, target_node)
end

function validate_all_edges(edges, nodes)::Union{Nothing, String}
    for edge in edges
        error_msg = validate_no_nested_buses(edge, nodes)
        error_msg !== nothing && return error_msg
    end
    return nothing
end

function validate_component_names(nodes)::Union{Nothing, String}
    name_counts = Dict{String, Vector{String}}()
    for node in nodes
        if !is_bus_node(node)
            key = "$(get_component_key(node))|$(get_node_label(node))"
            if !haskey(name_counts, key)
                name_counts[key] = String[]
            end
            push!(name_counts[key], get(node, "id", ""))
        end
    end
    conflicts = String[]
    for (key, ids) in name_counts
        if length(ids) > 1
            comp_key, comp_name = split(key, "|")
            push!(conflicts, "组件类型 $(comp_key) 中存在 $(length(ids)) 个同名节点「$(comp_name)」")
        end
    end
    return isempty(conflicts) ? nothing : join(conflicts, "；")
end

# ═══════════════════════════════════════════════════════════════════════════
# 解析逻辑
# ═══════════════════════════════════════════════════════════════════════════

"""解析非总线节点，生成 ComponentRecord"""
function parse_non_bus_node(node, code::String)::ComponentRecord
    business = get_business_data(node)
    component_key = get(business, "componentKey", "")
    component_name = get(business, "componentName", get(get(node, "data", Dict()), "label", ""))

    tech_params = get(business, "commonTechParams", Dict{String, Any}())
    paras = Dict{String, Any}()
    for (k, v) in tech_params
        paras[string(k)] = v
    end

    eco_params = get(business, "commonEconomicParams", Dict{String, Any}())
    costs = Dict{String, Float64}()
    for (k, v) in eco_params
        v isa Real && (costs[string(k)] = Float64(v))
    end

    raw_layer_configs = get(business, "layerConfigs", Dict{String, Any}())
    layer_configs = Dict{String, Any}()
    for (layer_id, layer_data) in raw_layer_configs
        layer_configs[layer_id] = Dict{String, Any}(
            "status" => get(layer_data, "status", "stand_alone"),
            "paras" => get(layer_data, "techParams", Dict{String, Any}()),
            "costs" => get(layer_data, "economicParams", Dict{String, Any}()),
            "constraints" => flatten_enabled_flags(get(layer_data, "constraints", Dict{String, Any}())),
            "objectives" => flatten_enabled_flags(get(layer_data, "objectives", Dict{String, Any}()))
        )
    end

    boundary_ids = String[string(id) for id in get(business, "boundaryIds", [])]

    return ComponentRecord(; type = component_key, name = component_name, code = code, paras = paras, costs = costs, layer = layer_configs, boundaryIds = boundary_ids)
end

"""解析所有拓扑连接关系，生成 ConnectionRecord 数组"""
function parse_bus_connections(nodes, edges, node_to_code::Dict{String, String})::Vector{ConnectionRecord}
    connections = ConnectionRecord[]
    bus_id_to_label = Dict{String, String}()
    for node in nodes
        is_bus_node(node) && (bus_id_to_label[get(node, "id", "")] = get_node_label(node))
    end

    for edge in edges
        source_id = get(edge, "source", "")
        target_id = get(edge, "target", "")
        source_handle = get(edge, "sourceHandle", "")
        target_handle = get(edge, "targetHandle", "")
        medium = get_edge_medium(edge)
        source_is_bus = haskey(bus_id_to_label, source_id)
        target_is_bus = haskey(bus_id_to_label, target_id)

        if source_is_bus ⊻ target_is_bus
            bus_id, non_bus_id, non_bus_handle = source_is_bus ?
                (source_id, target_id, target_handle) :
                (target_id, source_id, source_handle)
            bus_label = bus_id_to_label[bus_id]
            bus_code = node_id_to_code(bus_id)
            clean_handle = strip_bus_handle_suffix(non_bus_handle)
            direction = endswith(clean_handle, "-out") ? :out : :in
            non_bus_node = get_node_by_id(nodes, non_bus_id)
            non_bus_node === nothing && continue
            var_name = build_variable_name(get_component_key(non_bus_node), medium, direction, get(node_to_code, non_bus_id, "?"))
            existing_idx = findfirst(c -> c.busLabel == bus_label, connections)
            if existing_idx !== nothing
                push!(connections[existing_idx].variables, var_name)
            else
                push!(connections, ConnectionRecord(; busLabel = bus_label, busCode = bus_code, variables = [var_name]))
            end
        elseif !source_is_bus && !target_is_bus
            source_node = get_node_by_id(nodes, source_id)
            target_node = get_node_by_id(nodes, target_id)
            (source_node === nothing || target_node === nothing) && continue
            source_var = build_variable_name(get_component_key(source_node), medium, :out, get(node_to_code, source_id, "?"))
            target_var = build_variable_name(get_component_key(target_node), medium, :in, get(node_to_code, target_id, "?"))
            push!(connections, ConnectionRecord(; busLabel = "", variables = [source_var, target_var]))
        end
    end
    return connections
end

# ═══════════════════════════════════════════════════════════════════════════
# 文件写入
# ═══════════════════════════════════════════════════════════════════════════

function write_json_file(filepath::String, data)
    open(filepath, "w") do io
        JSON3.pretty(io, data)
    end
end

# ═══════════════════════════════════════════════════════════════════════════
# 入口函数
# ═══════════════════════════════════════════════════════════════════════════

"""
    parse_project(project_json; output_dir) -> ParseResult

解析前端项目 JSON，生成 component.json / connection.json / mapping.json。
output_dir: 输出目录，默认 backend/（兼容旧路由）；任务模式传 data/tasks/<id>/。
"""
function parse_project(project_json::Dict; output_dir::String = joinpath(@__DIR__, ".."))::ParseResult
    try
        workspace = get(project_json, "workspace", Dict())
        canvases = get(workspace, "canvases", [])
        active_canvas_id = get(workspace, "activeCanvasId", "")

        active_canvas = nothing
        for canvas in canvases
            if get(canvas, "id", "") == active_canvas_id
                active_canvas = canvas
                break
            end
        end
        if active_canvas === nothing
            active_canvas = isempty(canvases) ? nothing : canvases[1]
        end
        active_canvas === nothing && return ParseResult(; success = false, message = "未找到活动画布")

        nodes = get(active_canvas, "nodes", [])
        edges = get(active_canvas, "edges", [])

        name_error = validate_component_names(nodes)
        name_error !== nothing && return ParseResult(; success = false, message = name_error)

        validate_error = validate_all_edges(edges, nodes)
        validate_error !== nothing && return ParseResult(; success = false, message = validate_error)

        node_to_code, code_mappings = build_node_code_mapping(nodes)

        components = ComponentRecord[]
        for node in nodes
            if !is_bus_node(node)
                node_id = get(node, "id", "")
                code = get(node_to_code, node_id, node_id_to_code(node_id))
                push!(components, parse_non_bus_node(node, code))
            end
        end

        connections = parse_bus_connections(nodes, edges, node_to_code)

        mkpath(output_dir)
        write_json_file(joinpath(output_dir, "component.json"), components)
        write_json_file(joinpath(output_dir, "connection.json"), connections)
        write_json_file(joinpath(output_dir, "mapping.json"), code_mappings)

        return ParseResult(;
            success = true,
            message = "解析成功，生成 $(length(components)) 个组件、$(length(connections)) 条连接、$(length(code_mappings)) 个编码映射",
            outputPath = output_dir,
            componentCount = length(components),
            connectionCount = length(connections)
        )
    catch e
        return ParseResult(; success = false, message = "解析异常: $(sprint(showerror, e))")
    end
end
