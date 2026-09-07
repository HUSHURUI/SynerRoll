struct Photovoltaic <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{Photovoltaic}) = get_component_schema("PV")

component_result_bindings(::Type{Photovoltaic}) = ResultBinding[]

function component_result_bindings(component::Photovoltaic)
    c = component_code(component)
    return [
        ResultBinding("PV", Symbol("E_PV_", c), "power"),
        ResultBinding("PV", Symbol("E_PV_cut_", c), "power"),
    ]
end

function Photovoltaic(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(Photovoltaic);
        component_name="Photovoltaic",
        special_validator=normalized_dict -> validate_special_rules(Photovoltaic, normalized_dict),
    )
    return Photovoltaic(config)
end
