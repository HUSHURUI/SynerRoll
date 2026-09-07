struct HydrogenLoad <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{HydrogenLoad}) = get_component_schema("HLOAD")

component_result_bindings(::Type{HydrogenLoad}) = ResultBinding[]

function component_result_bindings(component::HydrogenLoad)
    c = component_code(component)
    return [
        ResultBinding("H_HLOAD", Symbol("H_HLOAD_", c), "hydrogen"),
    ]
end

function HydrogenLoad(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(HydrogenLoad);
        component_name="HydrogenLoad",
        special_validator=normalized_dict -> validate_special_rules(HydrogenLoad, normalized_dict),
    )
    return HydrogenLoad(config)
end
