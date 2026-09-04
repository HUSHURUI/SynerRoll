struct PumpedStorage <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{PumpedStorage}) = get_component_schema("PS")

component_result_bindings(::Type{PumpedStorage}) = ResultBinding[]

function component_result_bindings(component::PumpedStorage)
    c = component_code(component)
    return [
        ResultBinding("PS", Symbol("E_PS_", c), "energy"),
        ResultBinding("PS", Symbol("E_PS_in_", c), "power"),
        ResultBinding("PS", Symbol("E_PS_out_", c), "power"),
    ]
end

function PumpedStorage(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(PumpedStorage);
        component_name="PumpedStorage",
        special_validator=normalized_dict -> validate_special_rules(PumpedStorage, normalized_dict),
    )
    return PumpedStorage(config)
end
