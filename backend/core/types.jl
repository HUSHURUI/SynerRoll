abstract type AbstractComponent end

const StringAnyDict = Dict{String,Any}

struct ComponentConfig
    type::String
    code::String
    layer::StringAnyDict
    paras::StringAnyDict
    costs::StringAnyDict
    boundaryIds::Vector{String}
end

struct FieldInfo
    display_name::String
    unit::String
end

struct FieldSpec
    name::String
    field_type::Type
    is_required::Bool
    default_value::Any
    min_value::Union{Real,Nothing}
    max_value::Union{Real,Nothing}
    allowed_values::Union{Vector,Nothing}
    info::Union{FieldInfo,Nothing}
end

function FieldSpec(
    name::String;
    field_type::Type=Float64,
    is_required::Bool=false,
    default_value=nothing,
    min_value::Union{Real,Nothing}=0.0,
    max_value::Union{Real,Nothing}=nothing,
    allowed_values::Union{Vector,Nothing}=nothing,
    info::Union{FieldInfo,Nothing}=nothing,
)
    if !is_required && default_value === nothing
        error("Optional field $(name) must declare a default_value.")
    end

    return FieldSpec(name, field_type, is_required, default_value, min_value, max_value, allowed_values, info)
end

struct LayerSpec
    layer_id::String
    fields::Vector{FieldSpec}
end

struct ComponentSchema
    comp_type::String
    layer_specs::Vector{LayerSpec}
    paras_specs::Vector{FieldSpec}
    costs_specs::Vector{FieldSpec}
    layer_paras_specs::Vector{FieldSpec}
    layer_costs_specs::Vector{FieldSpec}
    constraint_specs::Vector{FieldSpec}
    objective_specs::Vector{FieldSpec}
end

struct BuildContext
    layer::StringAnyDict
    time::String
    algorithms::StringAnyDict
    db_path::String  # 任务级 TS DB 路径，求解器读写数据用
    max_layer_id::Int  # 项目最大时层编号（从 layerConfig 传入）
end

struct ResultBinding
    component_label::String
    var_name::Symbol
    remark::String
end
