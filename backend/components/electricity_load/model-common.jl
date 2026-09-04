# ═══════════════════════════════════════════════════════════════════════════
# electricity_load/model-common.jl — 共享函数
#
# model-base.jl 和 model.jl 共用的参数解析与辅助函数
# ═══════════════════════════════════════════════════════════════════════════

function resolve_electricity_load_params(component::ElectricityLoad, ctx::BuildContext)
    layer_settings = layer_config(component, ctx.layer["id"])

    boundary_ids = component_boundary_ids(component)
    isempty(boundary_ids) && error("ElectricityLoad $(component_type(component)) has no boundaryIds configured")

    data = nothing
    for boundary_id in boundary_ids
        result, _ = resolve_prediction_series(
            ctx;
            source_id=boundary_id,
            algorithm_key="electricityLoadPrediction",
        )
        data = result
        break
    end
    data === nothing && error("No valid boundary data found for ElectricityLoad — checked boundaryIds: $(boundary_ids)")

    return (
        layer_settings=layer_settings,
        status=layer_settings["status"],
        data=data,
    )
end
