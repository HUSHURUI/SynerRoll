function validate_special_rules(::Type{CombinedHeatPower}, comp_dict::Dict{String, Any})
    errors = String[]
    paras = get(comp_dict, "paras", Dict{String,Any}())
    get(paras, "η_e", 0.0) > 0.0 || push!(errors, "paras.η_e must be greater than zero")
    get(paras, "β", 0.0) > 0.0 || push!(errors, "paras.β must be greater than zero")

    boundary_ids = get(comp_dict, "boundaryIds", String[])
    isempty(boundary_ids) && push!(errors, "boundaryIds must contain a heat-load boundary")
    return errors
end
