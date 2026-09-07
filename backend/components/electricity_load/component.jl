struct ElectricityLoad <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{ElectricityLoad}) = get_component_schema("ELOAD")

component_result_bindings(::Type{ElectricityLoad}) = ResultBinding[]

function component_result_bindings(component::ElectricityLoad)
    c = component_code(component)
    return [
        ResultBinding("E_ELOAD", Symbol("E_ELOAD_", c), "power"),
    ]
end

function ElectricityLoad(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(ElectricityLoad);
        component_name="ElectricityLoad",
        special_validator=normalized_dict -> validate_special_rules(ElectricityLoad, normalized_dict),
    )
    return ElectricityLoad(config)
end
