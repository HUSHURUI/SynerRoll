struct HydroPower <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{HydroPower}) = get_component_schema("HYDRO")

component_result_bindings(::Type{HydroPower}) = ResultBinding[]

function component_result_bindings(component::HydroPower)
    c = component_code(component)
    return [
        ResultBinding("HYDRO", Symbol("E_HYDRO_", c), "power"),
        ResultBinding("HYDRO", Symbol("AVAILABLE_HYDRO_", c), "power"),
        ResultBinding("HYDRO", Symbol("MINIMUM_HYDRO_", c), "power"),
    ]
end

function HydroPower(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(HydroPower);
        component_name="HydroPower",
        special_validator=normalized_dict -> validate_special_rules(HydroPower, normalized_dict),
    )
    return HydroPower(config)
end
