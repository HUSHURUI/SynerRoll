using JSON3

const CAPACITY_PARAMETER_PATH = "data.business.commonTechParams.capacity"
const CAPACITY_COMPONENT_LIBRARY_PATH = normpath(joinpath(
    @__DIR__, "..", "..", "..", "config", "component-library.json"
))

const _CAPACITY_COMPONENT_LIBRARY = Ref{Union{Nothing,Dict{String,Any}}}(nothing)

_cp_dict(value) = value isa AbstractDict ? value : Dict{String,Any}()
_cp_array(value) = value isa AbstractVector ? value : Any[]

function _cp_number(value, fallback::Union{Nothing,Float64}=nothing)
    value isa Real && !(value isa Bool) || return fallback
    number = Float64(value)
    return isfinite(number) ? number : fallback
end

function _load_capacity_component_library()
    cached = _CAPACITY_COMPONENT_LIBRARY[]
    cached !== nothing && return cached

    isfile(CAPACITY_COMPONENT_LIBRARY_PATH) ||
        error("组件库不存在: $(CAPACITY_COMPONENT_LIBRARY_PATH)")

    document = JSON3.read(read(CAPACITY_COMPONENT_LIBRARY_PATH, String), Dict{String,Any})
    components = get(document, "components", nothing)
    components isa Dict{String,Any} || error("组件库缺少 components 对象")
    _CAPACITY_COMPONENT_LIBRARY[] = components
    return components
end

function _find_capacity_canvas(project_json::AbstractDict, canvas_id::String)
    workspace = _cp_dict(get(project_json, "workspace", nothing))
    canvases = _cp_array(get(workspace, "canvases", nothing))

    for canvas in canvases
        canvas_dict = _cp_dict(canvas)
        if string(get(canvas_dict, "id", "")) == canvas_id
            return canvas_dict
        end
    end

    error("画布不存在: $(canvas_id)")
end

function _capacity_field_schema(component_schema::AbstractDict)
    fields = _cp_array(get(component_schema, "commonTechFields", nothing))
    for field in fields
        field_dict = _cp_dict(field)
        if string(get(field_dict, "key", "")) == "capacity"
            return field_dict
        end
    end
    return nothing
end

function _capacity_defaults(current_value::Float64, field_schema::AbstractDict)
    planning = _cp_dict(get(field_schema, "planning", nothing))
    schema_min = _cp_number(get(field_schema, "min", nothing))
    schema_max = _cp_number(get(field_schema, "max", nothing))
    step = _cp_number(get(field_schema, "step", nothing))
    lower_factor = _cp_number(get(planning, "defaultLowerFactor", nothing), 0.5)::Float64
    upper_factor = _cp_number(get(planning, "defaultUpperFactor", nothing), 2.0)::Float64

    lower_bound = current_value * lower_factor
    schema_min !== nothing && (lower_bound = max(lower_bound, schema_min))

    explicit_upper = _cp_number(get(planning, "defaultUpperValue", nothing))
    upper_bound = if current_value > 0
        current_value * upper_factor
    elseif explicit_upper !== nothing
        explicit_upper
    elseif step !== nothing && step > 0
        step * 10
    else
        lower_bound
    end

    schema_max !== nothing && (upper_bound = min(upper_bound, schema_max))
    needs_user_input = upper_bound <= lower_bound

    if needs_user_input
        upper_bound = lower_bound + max(step === nothing ? 1.0 : step, 1.0)
    end

    return (
        lower_bound = lower_bound,
        upper_bound = upper_bound,
        step = step,
        schema_min = schema_min,
        schema_max = schema_max,
        needs_user_input = needs_user_input,
    )
end

"""
    detect_capacity_variables(project_json, canvas_id)

根据统一组件 schema 和指定画布实例生成容量规划变量表单。仅返回 schema 明确允许
规划的容量字段；兼容旧 schema 时，非 bus/load 的数值 capacity 字段也可被识别。
"""
function detect_capacity_variables(project_json::AbstractDict, canvas_id::String)
    canvas = _find_capacity_canvas(project_json, canvas_id)
    components = _load_capacity_component_library()
    nodes = _cp_array(get(canvas, "nodes", nothing))
    variables = Dict{String,Any}[]
    warnings = String[]
    seen_component_ids = Set{String}()

    for node in nodes
        node_dict = _cp_dict(node)
        data = _cp_dict(get(node_dict, "data", nothing))
        business = _cp_dict(get(data, "business", nothing))
        component_id = string(get(node_dict, "id", ""))
        component_key = string(get(business, "componentKey", get(data, "componentKey", "")))

        isempty(component_id) && continue
        if component_id in seen_component_ids
            error("画布中存在重复 componentId: $(component_id)")
        end
        push!(seen_component_ids, component_id)

        component_schema = get(components, component_key, nothing)
        component_schema isa AbstractDict || continue
        category = string(get(component_schema, "category", ""))
        category in ("bus", "load") && continue

        field_schema = _capacity_field_schema(component_schema)
        field_schema === nothing && continue
        planning = _cp_dict(get(field_schema, "planning", nothing))
        has_planning_flag = haskey(planning, "optimizable")
        has_planning_flag && get(planning, "optimizable", false) !== true && continue

        params = _cp_dict(get(business, "commonTechParams", nothing))
        raw_current_value = get(params, "capacity", nothing)
        current_value = _cp_number(raw_current_value)
        if current_value === nothing
            push!(warnings, "$(component_id) 的 capacity 不是有限数值，已跳过")
            continue
        end

        if !has_planning_flag
            push!(warnings, "$(component_key) 使用兼容规则识别，建议在组件 schema 中声明 planning.optimizable")
        end

        defaults = _capacity_defaults(current_value, field_schema)
        component_name = string(get(
            data,
            "label",
            get(business, "componentName", get(component_schema, "label", component_key)),
        ))

        push!(variables, Dict{String,Any}(
            "componentId" => component_id,
            "componentKey" => component_key,
            "componentName" => component_name,
            "parameterPath" => CAPACITY_PARAMETER_PATH,
            "unit" => string(get(field_schema, "unit", "")),
            "currentValue" => current_value,
            "mode" => "optimize",
            "fixedValue" => current_value,
            "lowerBound" => defaults.lower_bound,
            "upperBound" => defaults.upper_bound,
            "suggestedValue" => current_value,
            "step" => defaults.step,
            "schemaMin" => defaults.schema_min,
            "schemaMax" => defaults.schema_max,
            "needsUserInput" => defaults.needs_user_input,
        ))
    end

    return Dict{String,Any}(
        "schemaVersion" => "capacity-variable-form-v1",
        "projectId" => string(get(project_json, "id", "")),
        "projectName" => string(get(project_json, "name", "")),
        "projectUpdatedAt" => string(get(project_json, "updateTime", "")),
        "canvasId" => canvas_id,
        "canvasName" => string(get(canvas, "name", canvas_id)),
        "variables" => variables,
        "warnings" => warnings,
    )
end

function _validated_capacity_number(value, field_name::String, component_id::String)
    number = _cp_number(value)
    number === nothing && error("$(component_id).$(field_name) 必须是有限数值")
    number >= 0 || error("$(component_id).$(field_name) 不能为负数")
    return number
end

"""
    validate_capacity_variables(project_json, canvas_id, submitted_variables)

使用服务端重新生成的 schema 校验前端表单，防止 componentKey、单位、参数路径或边界被篡改。
返回按画布顺序规范化后的变量数组。
"""
function validate_capacity_variables(
    project_json::AbstractDict,
    canvas_id::String,
    submitted_variables::AbstractVector,
)
    schema = detect_capacity_variables(project_json, canvas_id)
    detected = schema["variables"]
    detected_by_id = Dict(string(item["componentId"]) => item for item in detected)
    normalized = Dict{String,Any}[]
    submitted_ids = Set{String}()
    optimize_count = 0

    for submitted in submitted_variables
        item = _cp_dict(submitted)
        component_id = string(get(item, "componentId", ""))
        isempty(component_id) && error("容量变量缺少 componentId")
        component_id in submitted_ids && error("容量变量重复: $(component_id)")
        push!(submitted_ids, component_id)

        server_item = get(detected_by_id, component_id, nothing)
        server_item === nothing && error("设备不存在或不可规划: $(component_id)")

        for identity_field in ("componentKey", "parameterPath", "unit")
            string(get(item, identity_field, "")) == string(server_item[identity_field]) ||
                error("$(component_id).$(identity_field) 与服务端 schema 不一致")
        end

        mode = string(get(item, "mode", ""))
        mode in ("optimize", "fixed") || error("$(component_id).mode 只能是 optimize 或 fixed")
        normalized_item = copy(server_item)
        normalized_item["mode"] = mode

        schema_min = server_item["schemaMin"]
        schema_max = server_item["schemaMax"]

        if mode == "fixed"
            fixed_value = _validated_capacity_number(get(item, "fixedValue", nothing), "fixedValue", component_id)
            schema_min !== nothing && fixed_value < schema_min && error("$(component_id).fixedValue 小于 schema 最小值")
            schema_max !== nothing && fixed_value > schema_max && error("$(component_id).fixedValue 大于 schema 最大值")
            normalized_item["fixedValue"] = fixed_value
        else
            lower_bound = _validated_capacity_number(get(item, "lowerBound", nothing), "lowerBound", component_id)
            upper_bound = _validated_capacity_number(get(item, "upperBound", nothing), "upperBound", component_id)
            suggested_value = _validated_capacity_number(get(item, "suggestedValue", nothing), "suggestedValue", component_id)
            lower_bound < upper_bound || error("$(component_id) 的容量下界必须小于上界")
            lower_bound <= suggested_value <= upper_bound ||
                error("$(component_id) 的建议值必须位于上下界之间")
            schema_min !== nothing && lower_bound < schema_min && error("$(component_id).lowerBound 小于 schema 最小值")
            schema_max !== nothing && upper_bound > schema_max && error("$(component_id).upperBound 大于 schema 最大值")
            normalized_item["lowerBound"] = lower_bound
            normalized_item["upperBound"] = upper_bound
            normalized_item["suggestedValue"] = suggested_value
            optimize_count += 1
        end

        push!(normalized, normalized_item)
    end

    length(normalized) == length(detected) || error("必须配置画布中的全部可规划设备")
    optimize_count > 0 || error("至少选择一个设备参与优化")
    return normalized
end
