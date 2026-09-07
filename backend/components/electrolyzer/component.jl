struct Electrolyzer <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{Electrolyzer}) = get_component_schema("ET")

component_result_bindings(::Type{Electrolyzer}) = ResultBinding[]

function component_result_bindings(component::Electrolyzer)
    c = component_code(component)
    return [
        ResultBinding("ET", Symbol("E_ET_", c), "power"),
        ResultBinding("ET", Symbol("H_ET_", c), "power"),
    ]
end

function Electrolyzer(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(Electrolyzer);
        component_name="Electrolyzer",
        special_validator=normalized_dict -> validate_special_rules(Electrolyzer, normalized_dict),
    )
    return Electrolyzer(config)
end
