"""
    struct HydrogenStorage <: AbstractComponent

氢储氢罐组件。
"""
struct HydrogenStorage <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{HydrogenStorage}) = get_component_schema("HS")

component_result_bindings(::Type{HydrogenStorage}) = ResultBinding[]

function component_result_bindings(component::HydrogenStorage)
    c = component_code(component)
    return [
        ResultBinding("HS", Symbol("H_HS_", c), "energy"),
        ResultBinding("HS", Symbol("H_HS_in_", c), "power"),
        ResultBinding("HS", Symbol("H_HS_out_", c), "power"),
    ]
end

function HydrogenStorage(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(HydrogenStorage);
        component_name="HydrogenStorage",
        special_validator=normalized_dict -> validate_special_rules(HydrogenStorage, normalized_dict),
    )
    return HydrogenStorage(config)
end
