struct GasPower <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{GasPower}) = get_component_schema("GP")

component_result_bindings(::Type{GasPower}) = ResultBinding[]

function component_result_bindings(component::GasPower)
    c = component_code(component)
    return [
        ResultBinding("GP", Symbol("E_GP_", c), "power"),
        ResultBinding("GP", Symbol("F_GP_", c), "power"),
    ]
end

function GasPower(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(GasPower);
        component_name="GasPower",
        special_validator=normalized_dict -> validate_special_rules(GasPower, normalized_dict),
    )
    return GasPower(config)
end
