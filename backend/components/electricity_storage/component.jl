struct ElectricityStorage <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{ElectricityStorage}) = get_component_schema("ES")

component_result_bindings(::Type{ElectricityStorage}) = ResultBinding[]

function component_result_bindings(component::ElectricityStorage)
    c = component_code(component)
    return [
        ResultBinding("ES", Symbol("E_ES_", c), "energy"),
        ResultBinding("ES", Symbol("E_ES_in_", c), "power"),
        ResultBinding("ES", Symbol("E_ES_out_", c), "power"),
    ]
end

function ElectricityStorage(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(ElectricityStorage);
        component_name="ElectricityStorage",
        special_validator=normalized_dict -> validate_special_rules(ElectricityStorage, normalized_dict),
    )
    return ElectricityStorage(config)
end
