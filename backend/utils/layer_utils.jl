function get_max_layer_id(layers::Dict{String, Any})
    ids = [parse(Int, layer_config["id"]) for layer_config in values(layers)]
    return string(maximum(ids))
end

function generate_layer_ids(layers::Dict{String, Any})
    max_layer_id = parse(Int, get_max_layer_id(layers))
    return [string(layer_id) for layer_id in 2:max_layer_id]
end

function get_upper_layer_id(layer_id::String)
    upper_layer_id = parse(Int, layer_id) - 1
    upper_layer_id >= 1 || error("Layer $(layer_id) does not have an upper layer.")
    return string(upper_layer_id)
end
