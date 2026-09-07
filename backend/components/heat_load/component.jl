struct HeatLoad <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{HeatLoad}) = get_component_schema("QLOAD")

component_result_bindings(::Type{HeatLoad}) = ResultBinding[]

function component_result_bindings(component::HeatLoad)
    c = component_code(component)
    return [
        ResultBinding("Q_QLOAD", Symbol("Q_QLOAD_", c), "power"),
    ]
end

function HeatLoad(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(HeatLoad);
        component_name="HeatLoad",
        special_validator=normalized_dict -> validate_special_rules(HeatLoad, normalized_dict),
    )
    return HeatLoad(config)
end
