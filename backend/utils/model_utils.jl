const BIG_M = 1e10

function generate_timespan(layer::Dict{String, Any})
    span_value = Int(time_str_divide(layer["length"], layer["step"]))
    return 1:span_value
end

step_hours(layer::Dict{String, Any}) = time_str_divide(layer["step"], "1h")

function create_jump_model(algorithms::Dict{String, Any})
    model = Model(COPT.Optimizer)
    set_silent(model)
    return model
end

duplicate_values(values::Vector{Float64}) = vcat(values, values)

function build_result_timestamps(layer::Dict{String, Any}, time::String)
    if layer["id"] == "1"
        return generate_timestamps(time, layer["step"], time_str_multiply(layer["length"], 2))
    end

    return generate_timestamps(time, layer["step"], layer["length"])
end

function generate_result_ts(model, timestamps::Vector{String}, var_name::Symbol, layer::Dict{String, Any})
    values = value.(model[var_name]).data
    if layer["id"] == "1"
        return TimeSeries(timestamps, duplicate_values(values))
    end
    return TimeSeries(timestamps, values)
end

function upper_layer_values(ctx::BuildContext, var_name::String, code::String)
    full_var_name = isempty(code) ? var_name : "$(var_name)_$(code)"
    timestamps = generate_timestamps(ctx.time, ctx.layer["step"], ctx.layer["length"])
    planned_ts, _ = query_ts(ctx.db_path; var_name=full_var_name, layer_id=get_upper_layer_id(ctx.layer["id"]))
    return get_values(planned_ts, timestamps)
end

# 兼容旧签名（model-base.jl 使用）
upper_layer_values(ctx::BuildContext, var_name::String) = upper_layer_values(ctx, var_name, "")

"""
读取当前时层在本次滚动窗口之前一个时间步的已保存结果。

这里必须使用“同一时层 + 精确时间戳”，不能使用 `get_value` 的 floor 回退：
若上一点尚未实际形成，宁可不添加首点衔接约束，也不能误拿更早时刻或其他
时层的值作为滚动初值。
"""
function previous_layer_result_value(
    ctx::BuildContext,
    source_id::String,
    var_prefix::String,
    code::String,
)
    current_minutes = time_label_to_minutes(ctx.time)
    step_minutes = time_str_to_minutes(string(ctx.layer["step"]))
    previous_minutes = current_minutes - step_minutes
    previous_minutes >= 0 || return nothing

    var_name = isempty(code) ? var_prefix : "$(var_prefix)_$(code)"
    series, _ = query_ts(
        ctx.db_path;
        source_id=source_id,
        var_name=var_name,
        layer_id=string(ctx.layer["id"]),
    )
    series === nothing && return nothing

    previous_timestamp = minutes_to_time_label(previous_minutes)
    index = findfirst(==(previous_timestamp), series.timestamps)
    index === nothing && return nothing
    return series.values[index]
end

"""
查询储能组件上一层的存储值时序数据。
source_id: 组件类型标识（如 "ES", "HS", "PS"）
var_prefix: 变量名前缀（如 "E_ES", "H_HS", "E_PS"）
"""
function current_layer_storage_value(ctx::BuildContext, code::String, source_id::String, var_prefix::String)
    var_name = isempty(code) ? var_prefix : "$(var_prefix)_$(code)"
    db_path = ctx.db_path
    t = ctx.time

    max_lid = ctx.max_layer_id

    # ── 策略 1：精确时刻匹配（跨所有层，取最高层）──
    # 覆盖模式下同一时刻最高层的结果是最新的，优先使用
    best_ts = nothing
    best_lid = 0
    for lid in 1:max_lid
        ts, label = query_ts(db_path; source_id=source_id, var_name=var_name, layer_id=string(lid))
        ts === nothing && continue
        if findfirst(==(t), ts.timestamps) !== nothing
            parsed = parse_ts_label(label)
            lid_num = parse(Int, parsed["layer_id"])
            if lid_num > best_lid
                best_lid = lid_num
                best_ts = ts
            end
        end
    end
    best_ts !== nothing && return best_ts

    # ── 策略 2：最高层 floor 回退（取最近的更早时刻）──
    for lid in max_lid:-1:1
        ts, _ = query_ts(db_path; source_id=source_id, var_name=var_name, layer_id=string(lid))
        ts === nothing && continue
        isempty(ts.timestamps) && continue
        first_min = time_label_to_minutes(ts.timestamps[1])
        target_min = time_label_to_minutes(t)
        target_min >= first_min || continue
        try
            get_value(ts, t)  # 只测试能否取到值（含 floor 回退）
            return ts
        catch e
            @debug "layer $lid 无可用值，尝试下一层" time=t exception=e
            continue
        end
    end

    return nothing
end

# 兼容旧签名（model-base.jl 使用）
current_layer_storage_value(ctx::BuildContext) = current_layer_storage_value(ctx, "", "ES", "E_ES")
current_layer_storage_value(ctx::BuildContext, code::String) = current_layer_storage_value(ctx, code, "ES", "E_ES")
