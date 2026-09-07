const CAPACITY_COMPONENT_NODE_PATH = "data.business.commonTechParams.capacity"

function _candidate_canvas(project_snapshot::AbstractDict, canvas_id::String)
    workspace = get(project_snapshot, "workspace", nothing)
    workspace isa AbstractDict || throw(CapacityPlanningError("INVALID_SNAPSHOT", "项目缺少 workspace"))
    canvases = get(workspace, "canvases", nothing)
    canvases isa AbstractVector || throw(CapacityPlanningError("INVALID_SNAPSHOT", "项目缺少画布列表"))
    canvas = findfirst(item -> string(get(item, "id", "")) == canvas_id, canvases)
    canvas === nothing && throw(CapacityPlanningError("CANVAS_NOT_FOUND", "项目中不存在画布 $(canvas_id)"))
    return workspace, canvases[canvas]
end

function _candidate_number(value, field::String, component_id::String)
    value isa Real || throw(CapacityPlanningError("INVALID_CAPACITY", "$(component_id) 的 $(field) 必须是数值"))
    number = Float64(value)
    isfinite(number) || throw(CapacityPlanningError("INVALID_CAPACITY", "$(component_id) 的 $(field) 必须是有限数值"))
    number >= 0 || throw(CapacityPlanningError("INVALID_CAPACITY", "$(component_id) 的 $(field) 不能小于 0"))
    return number
end

"""
    apply_capacity_candidate(project_snapshot, canvas_id, variables, candidate_values)

从不可变基线快照深拷贝出候选项目，并按已校验的规划变量写入容量。函数会再次核对
componentId、componentKey、parameterPath、unit 和边界，防止规划运行期间项目结构漂移。
`candidate_values` 的顺序只对应 mode=optimize 的变量。
"""
function apply_capacity_candidate(
    project_snapshot::AbstractDict,
    canvas_id::String,
    variables::AbstractVector,
    candidate_values::AbstractVector,
)
    candidate = deepcopy(project_snapshot)
    workspace, canvas = _candidate_canvas(candidate, canvas_id)
    workspace["activeCanvasId"] = canvas_id

    nodes = get(canvas, "nodes", nothing)
    nodes isa AbstractVector || throw(CapacityPlanningError("INVALID_SNAPSHOT", "目标画布缺少 nodes"))
    nodes_by_id = Dict(string(get(node, "id", "")) => node for node in nodes)
    optimize_count = count(item -> string(get(item, "mode", "")) == "optimize", variables)
    length(candidate_values) == optimize_count || throw(CapacityPlanningError(
        "CANDIDATE_DIMENSION_MISMATCH",
        "候选容量维度 $(length(candidate_values)) 与优化变量数 $(optimize_count) 不一致",
    ))

    optimized_index = 0
    applied = Dict{String,Float64}()
    for raw_variable in variables
        variable = raw_variable isa AbstractDict ? raw_variable : throw(CapacityPlanningError("INVALID_VARIABLE", "规划变量格式错误"))
        component_id = string(get(variable, "componentId", ""))
        node = get(nodes_by_id, component_id, nothing)
        node === nothing && throw(CapacityPlanningError("COMPONENT_NOT_FOUND", "画布中不存在组件 $(component_id)"))

        data = get(node, "data", nothing)
        data isa AbstractDict || throw(CapacityPlanningError("COMPONENT_CHANGED", "组件 $(component_id) 缺少 data"))
        business = get(data, "business", nothing)
        business isa AbstractDict || throw(CapacityPlanningError("COMPONENT_CHANGED", "组件 $(component_id) 缺少 business"))
        actual_key = string(get(business, "componentKey", get(data, "componentKey", "")))
        expected_key = string(get(variable, "componentKey", ""))
        actual_key == expected_key || throw(CapacityPlanningError(
            "COMPONENT_CHANGED", "组件 $(component_id) 类型已从 $(expected_key) 变为 $(actual_key)",
        ))
        string(get(variable, "parameterPath", "")) == CAPACITY_COMPONENT_NODE_PATH ||
            throw(CapacityPlanningError("PARAMETER_PATH_CHANGED", "组件 $(component_id) 的容量参数路径不受支持"))

        tech_params = get(business, "commonTechParams", nothing)
        tech_params isa AbstractDict || throw(CapacityPlanningError("COMPONENT_CHANGED", "组件 $(component_id) 缺少技术参数"))
        haskey(tech_params, "capacity") || throw(CapacityPlanningError("COMPONENT_CHANGED", "组件 $(component_id) 缺少 capacity"))
        _candidate_number(tech_params["capacity"], "当前 capacity", component_id)

        mode = string(get(variable, "mode", ""))
        value = if mode == "optimize"
            optimized_index += 1
            number = _candidate_number(candidate_values[optimized_index], "候选容量", component_id)
            lower = _candidate_number(get(variable, "lowerBound", nothing), "lowerBound", component_id)
            upper = _candidate_number(get(variable, "upperBound", nothing), "upperBound", component_id)
            lower <= number <= upper || throw(CapacityPlanningError(
                "CANDIDATE_OUT_OF_BOUNDS", "组件 $(component_id) 的候选容量 $(number) 不在 [$(lower), $(upper)] 内",
            ))
            number
        elseif mode == "fixed"
            _candidate_number(get(variable, "fixedValue", nothing), "fixedValue", component_id)
        else
            throw(CapacityPlanningError("INVALID_VARIABLE_MODE", "组件 $(component_id) 的 mode 必须是 optimize 或 fixed"))
        end
        tech_params["capacity"] = value
        applied[component_id] = value
    end
    return candidate, applied
end
