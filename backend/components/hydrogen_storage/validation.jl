"""
    validate_hydrogen_storage(::Type{HydrogenStorage}, config::ComponentConfig)

氢储氢罐组件参数校验。
"""
function validate_hydrogen_storage(::Type{HydrogenStorage}, config::ComponentConfig)
    # 当前无特殊校验逻辑
end

function validate_special_rules(::Type{HydrogenStorage}, comp_dict::Dict{String, Any})
    errors = String[]
    return errors
end
