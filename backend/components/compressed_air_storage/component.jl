struct CompressedAirStorage <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{CompressedAirStorage}) = get_component_schema("CS")

component_result_bindings(::Type{CompressedAirStorage}) = ResultBinding[]

function component_result_bindings(component::CompressedAirStorage)
    c = component_code(component)
    return [
        ResultBinding("CS", Symbol("E_CS_", c), "energy"),
        ResultBinding("CS", Symbol("E_CS_in_", c), "power"),
        ResultBinding("CS", Symbol("E_CS_out_", c), "power"),
    ]
end

function CompressedAirStorage(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(CompressedAirStorage);
        component_name="CompressedAirStorage",
        special_validator=normalized_dict -> validate_special_rules(CompressedAirStorage, normalized_dict),
    )
    return CompressedAirStorage(config)
end
