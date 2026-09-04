function normalize_default_value(spec::FieldSpec)
    if spec.default_value === nothing
        return nothing
    end

    if spec.default_value isa spec.field_type
        return deepcopy(spec.default_value)
    end

    return convert(spec.field_type, spec.default_value)
end

function validate_and_fill_field!(field_path::String, data_dict::Dict{String,Any}, spec::FieldSpec)
    errors = String[]
    field_name = spec.name

    if !haskey(data_dict, field_name)
        if spec.is_required
            push!(errors, "$(field_path): required field is missing")
        else
            data_dict[field_name] = normalize_default_value(spec)
        end
        return errors
    end

    field_value = data_dict[field_name]

    # 宽容处理：Real 子类（Int 等）自动转为目标类型
    if !(field_value isa spec.field_type)
        if spec.field_type <: Real && field_value isa Real
            data_dict[field_name] = convert(spec.field_type, field_value)
        else
            push!(errors, "$(field_path): expected $(spec.field_type), got $(typeof(field_value))")
            return errors
        end
    end

    if spec.field_type <: Real
        if spec.min_value !== nothing && field_value < spec.min_value
            push!(errors, "$(field_path): value $(field_value) is below minimum $(spec.min_value)")
        end
        if spec.max_value !== nothing && field_value > spec.max_value
            push!(errors, "$(field_path): value $(field_value) is above maximum $(spec.max_value)")
        end
    end

    if spec.allowed_values !== nothing
        if !(field_value in spec.allowed_values)
            push!(errors, "$(field_path): value $(field_value) is not in $(join(spec.allowed_values, ", "))")
        end
    end

    return errors
end

function validate_section!(section_path::String, section_dict::Dict{String,Any}, specs::Vector{FieldSpec})
    errors = String[]

    for spec in specs
        append!(errors, validate_and_fill_field!("$(section_path).$(spec.name)", section_dict, spec))
    end

    allowed_fields = Set(spec.name for spec in specs)
    for field_name in keys(section_dict)
        if !(field_name in allowed_fields)
            push!(errors, "$(section_path): unexpected field $(field_name)")
        end
    end

    return errors
end

function validate_nested_section!(
    parent_path::String,
    parent_dict::Dict{String,Any},
    section_name::String,
    specs::Vector{FieldSpec},
)
    errors = String[]

    if !haskey(parent_dict, section_name)
        return errors
    end

    section_value = parent_dict[section_name]
    if !(section_value isa Dict)
        push!(errors, "$(parent_path).$(section_name): expected Dict, got $(typeof(section_value))")
        return errors
    end

    append!(errors, validate_section!("$(parent_path).$(section_name)", section_value, specs))
    return errors
end

function validate_root_sections!(comp_dict::Dict{String,Any}, schema::ComponentSchema)
    errors = String[]

    if !haskey(comp_dict, "type")
        push!(errors, "type: required field is missing")
    elseif comp_dict["type"] != schema.comp_type
        push!(errors, "type: expected $(schema.comp_type), got $(comp_dict["type"])")
    end

    for root_key in ("layer", "paras", "costs")
        if !haskey(comp_dict, root_key)
            push!(errors, "$(root_key): required section is missing")
        end
    end

    return errors
end

function validate_layer_sections!(comp_dict::Dict{String,Any}, schema::ComponentSchema)
    errors = String[]

    if !haskey(comp_dict, "layer")
        return errors
    end

    layer_dict = comp_dict["layer"]
    if !(layer_dict isa Dict)
        push!(errors, "layer: expected Dict, got $(typeof(layer_dict))")
        return errors
    end

    for layer_spec in schema.layer_specs
        layer_id = layer_spec.layer_id

        if layer_id == "1" && !haskey(layer_dict, layer_id)
            push!(errors, "layer.$(layer_id): required layer is missing")
            continue
        end

        haskey(layer_dict, layer_id) || continue
        layer_data = layer_dict[layer_id]

        if !(layer_data isa Dict)
            push!(errors, "layer.$(layer_id): expected Dict, got $(typeof(layer_data))")
            continue
        end

        append!(errors, validate_section!("layer.$(layer_id)", layer_data, layer_spec.fields))
        append!(errors, validate_nested_section!("layer.$(layer_id)", layer_data, "paras", schema.layer_paras_specs))
        append!(errors, validate_nested_section!("layer.$(layer_id)", layer_data, "costs", schema.layer_costs_specs))
        append!(errors, validate_nested_section!("layer.$(layer_id)", layer_data, "constraints", schema.constraint_specs))
        append!(errors, validate_nested_section!("layer.$(layer_id)", layer_data, "objectives", schema.objective_specs))
    end

    return errors
end

function validate_component_config!(comp_dict::Dict{String,Any}, schema::ComponentSchema)
    errors = String[]

    append!(errors, validate_root_sections!(comp_dict, schema))
    append!(errors, validate_layer_sections!(comp_dict, schema))

    if haskey(comp_dict, "paras") && comp_dict["paras"] isa Dict
        append!(errors, validate_section!("paras", comp_dict["paras"], schema.paras_specs))
    elseif haskey(comp_dict, "paras")
        push!(errors, "paras: expected Dict, got $(typeof(comp_dict["paras"]))")
    end

    if haskey(comp_dict, "costs") && comp_dict["costs"] isa Dict
        append!(errors, validate_section!("costs", comp_dict["costs"], schema.costs_specs))
    elseif haskey(comp_dict, "costs")
        push!(errors, "costs: expected Dict, got $(typeof(comp_dict["costs"]))")
    end

    return errors
end
