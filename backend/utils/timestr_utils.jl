using Printf

function parse_time_str(time_str::String)
    matched = match(r"^(\d+)(h|m|s)$", time_str)
    matched === nothing && error("Invalid duration string: $(time_str)")

    value = parse(Int, matched.captures[1])
    unit = matched.captures[2]
    return value, unit
end

function time_str_to_minutes(time_str::String)
    value, unit = parse_time_str(time_str)

    if unit == "h"
        return value * 60
    elseif unit == "m"
        return value
    elseif unit == "s"
        value % 60 == 0 || error("Second-level durations must be multiples of 60 seconds: $(time_str)")
        return value ÷ 60
    end

    error("Unsupported duration unit: $(unit)")
end

function time_str_divide(lhs::String, rhs::String)
    return time_str_to_minutes(lhs) / time_str_to_minutes(rhs)
end

function time_str_multiply(time_str::String, multiplier::Int)
    multiplier > 0 || error("Duration multiplier must be positive.")
    value, unit = parse_time_str(time_str)
    return "$(value * multiplier)$(unit)"
end

function time_label_to_minutes(time_label::String)
    matched = match(r"^(\d+):(\d+)$", time_label)
    matched === nothing && error("Invalid time label: $(time_label)")

    hour = parse(Int, matched.captures[1])
    minute = parse(Int, matched.captures[2])
    (hour >= 0 && 0 <= minute <= 59) || error("Time label out of range: $(time_label)")

    return hour * 60 + minute
end

function minutes_to_time_label(total_minutes::Int)
    total_minutes >= 0 || error("Total minutes must be non-negative.")
    hour = total_minutes ÷ 60
    minute = total_minutes % 60
    return "$hour:$(@sprintf("%02d", minute))"
end

function time_label_add(time_label::String, delta::String)
    return minutes_to_time_label(time_label_to_minutes(time_label) + time_str_to_minutes(delta))
end

function time_label_less_than(lhs::String, rhs::String)
    return time_label_to_minutes(lhs) < time_label_to_minutes(rhs)
end

function is_time_divisible(time_label::String, time_str::String)
    total_minutes = time_label_to_minutes(time_label)
    step_minutes = time_str_to_minutes(time_str)
    step_minutes > 0 || error("Step duration must be positive.")
    return total_minutes % step_minutes == 0
end

function generate_timestamps(time::String, time_step::String, time_length::String)
    start_minutes = time_label_to_minutes(time)
    step_minutes = time_str_to_minutes(time_step)
    total_minutes = time_str_to_minutes(time_length)

    step_minutes > 0 || error("Step duration must be positive.")
    total_minutes > 0 || error("Total duration must be positive.")

    point_count = total_minutes ÷ step_minutes
    point_count > 0 || error("time_step cannot exceed time_length.")

    timestamps = Vector{String}(undef, point_count)
    current_minutes = start_minutes

    for index in 1:point_count
        timestamps[index] = minutes_to_time_label(current_minutes)
        current_minutes += step_minutes
    end

    return timestamps
end
