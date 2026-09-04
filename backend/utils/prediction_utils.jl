function predict(predict_ts::TimeSeries, actual_ts::TimeSeries, planned_ts::TimeSeries, ::Val{:LSTM})
    # TODO: keep the original placeholder until the prediction logic is finalized.
end

function resolve_prediction_series(ctx::BuildContext; source_id::String, algorithm_key::String)
    timestamps = generate_timestamps(ctx.time, ctx.layer["step"], ctx.layer["length"])
    planned_ts, planned_label = query_ts(ctx.db_path; source_id=source_id, remark="planned")
    planned_data = get_values(planned_ts, timestamps)

    algorithm_name = get(ctx.algorithms, algorithm_key, "None")
    if ctx.layer["id"] == "1" || algorithm_name == "None"
        return planned_data, planned_label
    end

    predict_ts, _ = query_ts(ctx.db_path; source_id=source_id, remark="predict")
    actual_ts, _ = query_ts(ctx.db_path; source_id=source_id, remark="actual")
    return predict(predict_ts, actual_ts, planned_ts, Val(Symbol(algorithm_name))), planned_label
end
