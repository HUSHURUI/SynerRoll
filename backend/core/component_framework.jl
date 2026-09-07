function component_config(component::AbstractComponent)
    return getfield(component, :config)
end

component_type(component::AbstractComponent) = component_config(component).type
component_code(component::AbstractComponent) = component_config(component).code
component_layers(component::AbstractComponent) = component_config(component).layer
component_paras(component::AbstractComponent) = component_config(component).paras
component_costs(component::AbstractComponent) = component_config(component).costs
component_boundary_ids(component::AbstractComponent) = component_config(component).boundaryIds

function layer_config(component::AbstractComponent, layer_id::String)
    return component_layers(component)[layer_id]
end

function section_config(component::AbstractComponent, layer_id::String, section_name::String)
    return layer_config(component, layer_id)[section_name]
end

component_schema(::Type{<:AbstractComponent}) = error("Component schema is not defined.")
component_result_bindings(component::AbstractComponent) = ResultBinding[]

validate_special_rules(::Type{<:AbstractComponent}, comp_dict::Dict{String, Any}) = String[]
build_component_model!(model, component::AbstractComponent, ctx::BuildContext) = error("Component model is not defined.")

function create_component_config(
    comp_dict::Dict{String, Any},
    schema::ComponentSchema;
    component_name::String,
    special_validator::Function=(normalized_dict -> String[]),
)
    normalized_dict = deepcopy(comp_dict)
    general_errors = validate_component_config!(normalized_dict, schema)
    isempty(general_errors) || error("$(component_name) validation failed:\n" * join(general_errors, "\n"))

    special_errors = special_validator(normalized_dict)
    isempty(special_errors) || error("$(component_name) special validation failed:\n" * join(special_errors, "\n"))

    raw_boundary_ids = get(normalized_dict, "boundaryIds", String[])
    boundary_ids = String[string(id) for id in raw_boundary_ids]

    return ComponentConfig(
        normalized_dict["type"],
        get(normalized_dict, "code", ""),
        normalized_dict["layer"],
        normalized_dict["paras"],
        normalized_dict["costs"],
        boundary_ids,
    )
end
