function standard_layer_fields(status_values::Vector{String})
    return [
        FieldSpec("status"; field_type=String, is_required=true, allowed_values=status_values),
        FieldSpec("paras"; field_type=Dict, is_required=true),
        FieldSpec("costs"; field_type=Dict, is_required=true),
        FieldSpec("constraints"; field_type=Dict, is_required=true),
        FieldSpec("objectives"; field_type=Dict, is_required=true),
    ]
end

function standard_layer_specs(layer_statuses::Vector{Pair{String,Vector{String}}})
    return [LayerSpec(layer_id, standard_layer_fields(statuses)) for (layer_id, statuses) in layer_statuses]
end

# function repeat_layer_statuses(layer_ids::Vector{String}, statuses::Vector{String})
#     return [layer_id => copy(statuses) for layer_id in layer_ids]
# end

function build_component_schema(;
    comp_type::String,
    layer_statuses::Vector{Pair{String,Vector{String}}},
    paras_specs::Vector{FieldSpec}=FieldSpec[],
    costs_specs::Vector{FieldSpec}=FieldSpec[],
    layer_paras_specs::Vector{FieldSpec}=FieldSpec[],
    layer_costs_specs::Vector{FieldSpec}=FieldSpec[],
    constraint_specs::Vector{FieldSpec}=FieldSpec[],
    objective_specs::Vector{FieldSpec}=FieldSpec[],
)
    return ComponentSchema(
        comp_type,
        standard_layer_specs(layer_statuses),
        paras_specs,
        costs_specs,
        layer_paras_specs,
        layer_costs_specs,
        constraint_specs,
        objective_specs,
    )
end

# ============================================================
# 从统一 JSON 配置加载组件 schema
# ============================================================

using JSON3

# 全局组件 schema 缓存，由 load_component_library() 填充
const COMPONENT_SCHEMA_CACHE = Dict{String,ComponentSchema}()

function infer_julia_type(field_data::Dict{String,Any})
    # 优先使用显式声明的 juliaType
    if haskey(field_data, "juliaType")
        jt = field_data["juliaType"]
        if jt == "Int64"
            return Int64
        elseif jt == "Bool"
            return Bool
        elseif jt == "String"
            return String
        elseif jt == "Vector{Float64}"
            return Vector{Float64}
        end
    end

    # 根据 defaultValue 推断
    dv = get(field_data, "defaultValue", nothing)
    if dv === nothing
        return Float64
    elseif dv isa Bool
        return Bool
    elseif dv isa Integer && !(dv isa Bool)
        # JSON3 会把 3.0 解析为 Int64(3)，用 step 的类型判断是否为浮点数
        step = get(field_data, "step", nothing)
        if step isa AbstractFloat
            return Float64
        end
        return Int64
    elseif dv isa AbstractFloat
        return Float64
    elseif dv isa AbstractString
        return String
    elseif dv isa AbstractArray
        return Vector{Float64}
    end
    return typeof(dv)
end

function field_spec_from_json(field_data::Dict{String,Any})
    name = field_data["key"]
    ft = infer_julia_type(field_data)
    is_required = get(field_data, "required", false)
    dv = get(field_data, "defaultValue", nothing)
    
    min_val = get(field_data, "min", nothing)
    max_val = get(field_data, "max", nothing)

    info = nothing
    if haskey(field_data, "label") && haskey(field_data, "unit")
        info = FieldInfo(field_data["label"], field_data["unit"])
    elseif haskey(field_data, "label")
        info = FieldInfo(field_data["label"], "")
    end

    return FieldSpec(
        name;
        field_type=ft,
        is_required=is_required,
        default_value=dv,
        min_value=min_val,
        max_value=max_val,
        info=info,
    )
end

function layer_statuses_from_json(layer_statuses_data::Dict{String,Any})
    result = Pair{String,Vector{String}}[]
    for (layer_id, statuses) in layer_statuses_data
        push!(result, layer_id => [s for s in statuses])
    end
    return result
end

function component_schema_from_json(comp_type::String, comp_data::Dict{String,Any})
    layer_statuses = layer_statuses_from_json(comp_data["layerStatuses"])

    paras_specs = field_spec_from_json.(comp_data["commonTechFields"])
    costs_specs = field_spec_from_json.(comp_data["commonEconomicFields"])
    layer_paras_specs = field_spec_from_json.(comp_data["layerTechFields"])
    layer_costs_specs = field_spec_from_json.(comp_data["layerEconomicFields"])
    constraint_specs = field_spec_from_json.(comp_data["constraintFields"])
    objective_specs = field_spec_from_json.(comp_data["objectiveFields"])

    return build_component_schema(;
        comp_type=comp_type,
        layer_statuses=layer_statuses,
        paras_specs=paras_specs,
        costs_specs=costs_specs,
        layer_paras_specs=layer_paras_specs,
        layer_costs_specs=layer_costs_specs,
        constraint_specs=constraint_specs,
        objective_specs=objective_specs,
    )
end

"""
    load_component_library(json_path::String) -> Dict{String, ComponentSchema}

从统一的 JSON 配置文件加载所有组件 schema，填充到全局缓存中。
返回 schema 映射（key 为前端组件 key，如 "WT"、"CP" 等）。
"""
function load_component_library(json_path::String)
    data = JSON3.read(json_path, Dict{String,Any})

    components = data["components"]

    for (key, comp_data) in components
        # 使用后端 key（如果有），否则用前端 key
        backend_type = get(comp_data, "backendKey", key)
        COMPONENT_SCHEMA_CACHE[backend_type] = component_schema_from_json(backend_type, comp_data)
    end

    return copy(COMPONENT_SCHEMA_CACHE)
end

"""
    get_component_schema(comp_type::String) -> ComponentSchema

从全局缓存中获取指定组件类型的 schema。
"""
function get_component_schema(comp_type::String)
    if !haskey(COMPONENT_SCHEMA_CACHE, comp_type)
        error("Component schema for '$comp_type' not found in library. Run load_component_library() first.")
    end
    return COMPONENT_SCHEMA_CACHE[comp_type]
end
