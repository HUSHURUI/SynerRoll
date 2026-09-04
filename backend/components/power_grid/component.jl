struct PowerGrid <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{PowerGrid}) = get_component_schema("GRID")

component_result_bindings(::Type{PowerGrid}) = ResultBinding[]

function component_result_bindings(component::PowerGrid)
    c = component_code(component)
    return [
        ResultBinding("GRID", Symbol("E_GRID_in_", c), "power"),
        ResultBinding("GRID", Symbol("E_GRID_out_", c), "power"),
    ]
end

function PowerGrid(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(PowerGrid);
        component_name="PowerGrid",
        special_validator=normalized_dict -> validate_special_rules(PowerGrid, normalized_dict),
    )
    return PowerGrid(config)
end
