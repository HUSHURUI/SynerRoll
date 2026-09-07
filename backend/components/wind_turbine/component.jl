struct WindTurbine <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{WindTurbine}) = get_component_schema("WT")

component_result_bindings(::Type{WindTurbine}) = ResultBinding[]

function component_result_bindings(component::WindTurbine)
    c = component_code(component)
    return [
        ResultBinding("WT", Symbol("E_WT_", c), "power"),
        ResultBinding("WT", Symbol("E_WT_cut_", c), "power"),
        ResultBinding("WT", Symbol("AVAILABLE_WT_", c), "power"),
    ]
end

function WindTurbine(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(WindTurbine);
        component_name="WindTurbine",
        special_validator=normalized_dict -> validate_special_rules(WindTurbine, normalized_dict),
    )
    return WindTurbine(config)
end
