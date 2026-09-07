# hydro_power/validation.jl — 业务规则校验

function validate_special_rules(::Type{HydroPower}, normalized_dict::Dict{String,Any})
    # 常规水电首版暂无额外业务规则；schema 通用范围检查已覆盖参数范围。
    errors = String[]
    return errors
end
