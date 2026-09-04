struct FlywheelStorage <: AbstractComponent
    config::ComponentConfig
end

component_schema(::Type{FlywheelStorage}) = get_component_schema("FS")

component_result_bindings(::Type{FlywheelStorage}) = ResultBinding[]

function component_result_bindings(component::FlywheelStorage)
    c = component_code(component)
    return [
        ResultBinding("FS", Symbol("E_FS_", c), "energy"),
        ResultBinding("FS", Symbol("E_FS_in_", c), "power"),
        ResultBinding("FS", Symbol("E_FS_out_", c), "power"),
    ]
end

function FlywheelStorage(comp_dict::Dict{String, Any})
    config = create_component_config(
        comp_dict,
        component_schema(FlywheelStorage);
        component_name="FlywheelStorage",
        special_validator=normalized_dict -> validate_special_rules(FlywheelStorage, normalized_dict),
    )
    return FlywheelStorage(config)
end
