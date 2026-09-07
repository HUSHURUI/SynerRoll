struct CombinedHeatPower <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{CombinedHeatPower}) = get_component_schema("CHP")

component_result_bindings(::Type{CombinedHeatPower}) = ResultBinding[]

function component_result_bindings(component::CombinedHeatPower)
    c = component_code(component)
    return [
        ResultBinding("CHP", Symbol("E_CHP_", c), "power"),
        ResultBinding("CHP", Symbol("Q_CHP_", c), "heat"),
        ResultBinding("CHP", Symbol("F_CHP_", c), "power"),
    ]
end

function CombinedHeatPower(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(CombinedHeatPower);
        component_name="CombinedHeatPower",
        special_validator=normalized_dict -> validate_special_rules(CombinedHeatPower, normalized_dict),
    )
    return CombinedHeatPower(config)
end
