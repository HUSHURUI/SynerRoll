struct CoalPower <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{CoalPower}) = get_component_schema("CP")

component_result_bindings(::Type{CoalPower}) = ResultBinding[]

function component_result_bindings(component::CoalPower)
    c = component_code(component)
    return [
        ResultBinding("CP", Symbol("E_CP_", c), "power"),
        ResultBinding("CP", Symbol("F_CP_", c), "power"),
    ]
end

function CoalPower(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(CoalPower);
        component_name="CoalPower",
        special_validator=normalized_dict -> validate_special_rules(CoalPower, normalized_dict),
    )
    return CoalPower(config)
end
