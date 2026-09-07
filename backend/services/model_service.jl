const COMPONENT_CONSTRUCTORS = Dict{String,Any}(
    "WT" => WindTurbine,
    "PV" => Photovoltaic,
    "CP" => CoalPower,
    "GP" => GasPower,
    "CHP" => CombinedHeatPower,
    "ET" => Electrolyzer,
    "ELOAD" => ElectricityLoad,
    "HLOAD" => HydrogenLoad,
    "QLOAD" => HeatLoad,
    "ES" => ElectricityStorage,
    "HS" => HydrogenStorage,
    "FS" => FlywheelStorage,
    "CS" => CompressedAirStorage,
    "PS" => PumpedStorage,
    "HYDRO" => HydroPower,
    "GRID" => PowerGrid
)

function instantiate_component(comp_dict::Dict{String,Any})
    constructor = get(COMPONENT_CONSTRUCTORS, comp_dict["type"], nothing)
    constructor === nothing && error("Unsupported component type $(comp_dict["type"])")
    return constructor(comp_dict)
end

# ── 松弛变量常量 ──────────────────────────────────────────────────────────
const SLACK_PENALTY_DEFAULT = 1e6  # 默认惩罚系数（可被 algorithm 配置覆盖）
const SLACK_BIG_M = 1e8  # 互斥约束的大 M 值

"""从 connection 变量名解析出 (comp_key, direction, code)，如 "E_WT_out_14a1" -> ("E_WT", :out, "14a1")"""
function parse_connection_variable(var_name::String)
    parts = split(var_name, "_")
    if length(parts) < 4
        return nothing
    end
    # 格式: {prefix}_{comp}_{dir}_{code}
    # prefix 是能量前缀（E/H），comp 是组件类型（WT/ELOAD/ET/HS 等，不含下划线）
    # dir 是 "in" 或 "out"，code 是最后部分
    dir_str = parts[end-1]
    code = parts[end]
    prefix = parts[1]
    comp_word = join(parts[2:(end-2)], "_")
    # 重建完整组件键：前缀 + "_" + 组件类型（如 "E" + "ELOAD" -> "E_ELOAD"）
    comp_key = isempty(prefix) ? comp_word : "$(prefix)_$(comp_word)"
    direction = dir_str == "out" ? :out : :in
    return (comp_key=comp_key, base_comp=comp_word, direction=direction, code=code)
end

"""根据组件类型和方向，确定对应的电总线 model 变量 symbol 基础名"""
function get_model_var_base(comp_key::String, direction::Symbol)
    if comp_key == "WT" || comp_key == "E_WT"
        return direction == :out ? "E_WT" : nothing
    elseif comp_key == "PV" || comp_key == "E_PV"
        return direction == :out ? "E_PV" : nothing
    elseif comp_key == "CP" || comp_key == "E_CP"
        return direction == :out ? "E_CP" : nothing
    elseif comp_key == "GP" || comp_key == "E_GP"
        return direction == :out ? "E_GP" : nothing
    elseif comp_key == "CHP" || comp_key == "E_CHP"
        return direction == :out ? "E_CHP" : nothing
    elseif comp_key == "ET" || comp_key == "E_ET"
        return direction == :in ? "E_ET" : nothing
    elseif comp_key == "ELOAD" || comp_key == "E_ELOAD"
        return direction == :in ? "E_ELOAD" : nothing
    elseif comp_key == "ES" || comp_key == "E_ES"
        return direction == :in ? "E_ES_in" : "E_ES_out"
    elseif comp_key == "FS" || comp_key == "E_FS"
        return direction == :in ? "E_FS_in" : "E_FS_out"
    elseif comp_key == "CS" || comp_key == "E_CS"
        return direction == :in ? "E_CS_in" : "E_CS_out"
    elseif comp_key == "PS" || comp_key == "E_PS"
        return direction == :in ? "E_PS_in" : "E_PS_out"
    elseif comp_key == "GRID" || comp_key == "E_GRID"
        return direction == :in ? "E_GRID_in" : "E_GRID_out"
    elseif comp_key == "HYDRO" || comp_key == "E_HYDRO"
        return direction == :out ? "E_HYDRO" : nothing
    end
    return nothing
end

"""根据组件类型和方向，确定对应的氢总线 model 变量 symbol 基础名"""
function get_hydrogen_model_var_base(comp_key::String, direction::Symbol)
    if comp_key == "ET" || comp_key == "H_ET"
        return direction == :out ? "H_ET" : nothing
    elseif comp_key == "HLOAD" || comp_key == "H_HLOAD"
        return direction == :in ? "H_HLOAD" : nothing
    elseif comp_key == "HS" || comp_key == "H_HS"
        return direction == :in ? "H_HS_in" : "H_HS_out"
    end
    return nothing
end

"""根据组件类型确定电总线能量符号（正=注入总线，负=从总线提取）"""
function get_energy_signal(comp_key::String, direction::Symbol)
    if comp_key in ("WT", "E_WT", "PV", "E_PV", "CP", "E_CP", "GP", "E_GP", "CHP", "E_CHP")
        return 1.0      # 发电注入总线
    elseif comp_key == "ET" || comp_key == "E_ET"
        return -1.0     # 电解槽从总线提取电能
    elseif comp_key == "ELOAD" || comp_key == "E_ELOAD"
        return -1.0     # 电负荷从总线提取
    elseif comp_key == "ES" || comp_key == "E_ES"
        return direction == :in ? -1.0 : 1.0  # 充电提取，放电注入
    elseif comp_key == "FS" || comp_key == "E_FS"
        return direction == :in ? -1.0 : 1.0  # 充电提取，放电注入
    elseif comp_key == "CS" || comp_key == "E_CS"
        return direction == :in ? -1.0 : 1.0  # 充电提取，放电注入
    elseif comp_key == "PS" || comp_key == "E_PS"
        return direction == :in ? -1.0 : 1.0  # 抽水提取，发电注入
    elseif comp_key == "GRID" || comp_key == "E_GRID"
        return direction == :in ? -1.0 : 1.0  # 上送提取，购入注入
    elseif comp_key == "HYDRO" || comp_key == "E_HYDRO"
        return 1.0      # 水电发电注入总线
    end
    error("未知的电总线组件类型: comp_key=\"$comp_key\", direction=$direction")
end

"""根据组件类型和方向，确定对应的热总线 model 变量 symbol 基础名"""
function get_thermal_model_var_base(comp_key::String, direction::Symbol)
    if comp_key == "CHP" || comp_key == "Q_CHP"
        return direction == :out ? "Q_CHP" : nothing
    elseif comp_key == "QLOAD" || comp_key == "Q_QLOAD"
        return direction == :in ? "Q_QLOAD" : nothing
    end
    return nothing
end

"""根据组件类型确定热总线能量符号（正=注入总线，负=从总线提取）"""
function get_thermal_energy_signal(comp_key::String, direction::Symbol)
    if comp_key == "CHP" || comp_key == "Q_CHP"
        return 1.0      # 热电联产供热注入总线
    elseif comp_key == "QLOAD" || comp_key == "Q_QLOAD"
        return -1.0     # 热负荷从总线提取
    end
    error("未知的热总线组件类型: comp_key=\"$comp_key\", direction=$direction")
end

"""根据组件类型确定氢总线能量符号（正=注入总线，负=从总线提取）"""
function get_hydrogen_energy_signal(comp_key::String, direction::Symbol)
    if comp_key == "ET" || comp_key == "H_ET"
        return 1.0      # 电解槽产氢注入总线
    elseif comp_key == "HLOAD" || comp_key == "H_HLOAD"
        return -1.0     # 氢负荷从总线提取
    elseif comp_key == "HS" || comp_key == "H_HS"
        return direction == :in ? -1.0 : 1.0  # 充氢提取，放氢注入
    end
    error("未知的氢总线组件类型: comp_key=\"$comp_key\", direction=$direction")
end

# ── 松弛变量辅助函数 ──────────────────────────────────────────────────────

"""从 algorithms 配置中读取松弛变量参数，返回 (enabled, penalty)"""
function get_slack_config(algorithms::Dict{String,Any})
    enabled = get(algorithms, "slackEnabled", false)
    penalty = Float64(get(algorithms, "slackPenalty", SLACK_PENALTY_DEFAULT))
    return enabled, penalty
end

"""从 node 的 variables 推断总线前缀（E/H/Q）"""
function determine_bus_prefix(node::Dict{String,Any})
    variables = get(node, "variables", String[])
    for var_name_str in variables
        parts = split(var_name_str, "_")
        if length(parts) >= 2
            prefix = parts[1]
            prefix in ("E", "H", "Q") && return String(prefix)
        end
    end
    return nothing
end

"""
    add_slack_variables!(model, tracer, prefix, bus_code, time_index; penalty)

为能量总线创建松弛变量（SHORTAGE / EXCESS）和互斥二进制变量（γ），
返回惩罚表达式。bus_code 为总线节点短编码，用于区分不同总线。

tracer 为 nothing 时不记录代码行（非追踪模式）。
penalty 为惩罚系数，默认使用 SLACK_PENALTY_DEFAULT。
"""
function add_slack_variables!(model, tracer::Union{CodeTracer,Nothing}, prefix::String, bus_code::String, time_index;
    penalty::Float64=SLACK_PENALTY_DEFAULT)
    suffix = isempty(bus_code) ? "" : "_$(bus_code)"
    shortage_name = "$(prefix)_SHORTAGE$(suffix)"
    excess_name = "$(prefix)_EXCESS$(suffix)"
    gamma_name = "γ_$(prefix)_SLACK$(suffix)"

    # ── 创建变量 ──────────────────────────────────────────────────────
    if tracer !== nothing
        shortage = add_tracked_variable!(model, tracer, shortage_name, time_index; lower_bound=0.0)
        excess = add_tracked_variable!(model, tracer, excess_name, time_index; lower_bound=0.0)
        gamma = add_tracked_variable!(model, tracer, gamma_name, time_index; binary=true)
    else
        # 非追踪模式：直接用 JuMP API
        shortage = @variable(model, [t in time_index], lower_bound=0.0, base_name=shortage_name)
        excess = @variable(model, [t in time_index], lower_bound=0.0, base_name=excess_name)
        gamma = @variable(model, [t in time_index], Bin, base_name=gamma_name)
        model[Symbol(shortage_name)] = shortage
        model[Symbol(excess_name)] = excess
        model[Symbol(gamma_name)] = gamma
    end

    # ── 互斥约束：SHORTAGE[t] <= M * γ[t]，EXCESS[t] <= M * (1 - γ[t]) ────
    # 逐时刻互斥：每个时刻独立选择 SHORTAGE 或 EXCESS
    if tracer !== nothing
        # 记录向量化代码
        record!(tracer, "@constraint(model, [t in $(format_val(time_index))], $(shortage_name)[t] <= $(SLACK_BIG_M) * $(gamma_name)[t])")
        record!(tracer, "@constraint(model, [t in $(format_val(time_index))], $(excess_name)[t] <= $(SLACK_BIG_M) * (1 - $(gamma_name)[t]))")
        # 实际构建约束
        for t in time_index
            JuMP.add_constraint(model,
                JuMP.build_constraint(error, shortage[t] - SLACK_BIG_M * gamma[t], MOI.LessThan(0.0)),
                "$(shortage_name)_m_$(t)")
            JuMP.add_constraint(model,
                JuMP.build_constraint(error, excess[t] - SLACK_BIG_M * (1 - gamma[t]), MOI.LessThan(0.0)),
                "$(excess_name)_m_$(t)")
        end
    else
        for t in time_index
            JuMP.@constraint(model, shortage[t] <= SLACK_BIG_M * gamma[t])
            JuMP.@constraint(model, excess[t] <= SLACK_BIG_M * (1 - gamma[t]))
        end
    end

    # ── 惩罚表达式 ────────────────────────────────────────────────────
    penalty_expr = @expression(model, penalty * (sum(shortage) + sum(excess)))
    penalty_name = "C_slack_$(prefix)$(suffix)"
    if tracer !== nothing
        add_tracked_expression!(model, tracer, penalty_name,
            "@expression(model, $(penalty_name), $(penalty) * (sum($(shortage_name)) + sum($(excess_name))))",
            penalty_expr; to_objective=true)
    end

    return penalty_expr
end

"""
统一的能量平衡约束构建（非追踪模式）。
var_base_fn(comp_key, direction) -> String?：获取变量基础名
signal_fn(comp_key, direction) -> Float64：获取能量符号
"""
function _build_energy_balance!(model, node::Dict{String,Any}, layer::Dict{String,Any}, algorithms::Dict{String,Any},
    var_base_fn::Function, signal_fn::Function)
    time_index = generate_timespan(layer)

    variables = get(node, "variables", String[])
    isempty(variables) && return nothing

    terms = @NamedTuple{var::Symbol, signal::Float64}[]
    for var_name_str in variables
        parsed = parse_connection_variable(var_name_str)
        parsed === nothing && continue
        base = var_base_fn(parsed.comp_key, parsed.direction)
        base === nothing && continue
        sym = Symbol(base)
        signal = signal_fn(parsed.comp_key, parsed.direction)
        push!(terms, (var=sym, signal=signal))
    end

    isempty(terms) && return nothing

    # 松弛变量（仅在启用时添加）
    slack_enabled, slack_penalty = get_slack_config(algorithms)
    prefix = determine_bus_prefix(node)
    penalty_expr = nothing
    shortage_sym = nothing
    excess_sym = nothing

    if slack_enabled && prefix !== nothing
        bus_code = get(node, "busCode", "")
        penalty_expr = add_slack_variables!(model, nothing, prefix, bus_code, time_index; penalty=slack_penalty)
        suffix = isempty(bus_code) ? "" : "_$(bus_code)"
        shortage_sym = Symbol("$(prefix)_SHORTAGE$(suffix)")
        excess_sym = Symbol("$(prefix)_EXCESS$(suffix)")
    end

    if shortage_sym !== nothing && excess_sym !== nothing
        @constraint(
            model,
            [t in time_index],
            sum(model[term.var][t] * term.signal for term in terms) + model[shortage_sym][t] - model[excess_sym][t] == 0.0,
        )
    else
        @constraint(
            model,
            [t in time_index],
            sum(model[term.var][t] * term.signal for term in terms) == 0.0,
        )
    end

    return penalty_expr
end

"""电总线平衡约束"""
build_energy_constraints!(model, node, layer, algorithms) =
    _build_energy_balance!(model, node, layer, algorithms, get_model_var_base, get_energy_signal)

"""热总线平衡约束"""
build_thermal_energy_constraints!(model, node, layer, algorithms) =
    _build_energy_balance!(model, node, layer, algorithms, get_thermal_model_var_base, get_thermal_energy_signal)

"""氢总线平衡约束"""
build_hydrogen_energy_constraints!(model, node, layer, algorithms) =
    _build_energy_balance!(model, node, layer, algorithms, get_hydrogen_model_var_base, get_hydrogen_energy_signal)

"""
统一的能量平衡约束构建（追踪模式）。
var_base_fn(comp_key, direction) -> String?：获取变量基础名
signal_fn(comp_key, direction) -> Float64：获取能量符号
"""
function _build_energy_balance_tracked!(model, tracer::CodeTracer, node::Dict{String,Any}, layer::Dict{String,Any},
    algorithms::Dict{String,Any}, var_base_fn::Function, signal_fn::Function)
    time_index = generate_timespan(layer)

    variables = get(node, "variables", String[])
    isempty(variables) && return nothing

    terms = @NamedTuple{var::Symbol, signal::Float64}[]
    term_strs = String[]
    for var_name_str in variables
        parsed = parse_connection_variable(var_name_str)
        parsed === nothing && continue
        base = var_base_fn(parsed.comp_key, parsed.direction)
        base === nothing && continue
        sym = Symbol(base, "_", parsed.code)
        signal = signal_fn(parsed.comp_key, parsed.direction)
        push!(terms, (var=sym, signal=signal))
        sig_str = signal > 0 ? "+" : "-"
        push!(term_strs, "$(sig_str) $(base)_$(parsed.code)[t]")
    end

    isempty(terms) && return nothing

    # 松弛变量（仅在启用时添加）
    slack_enabled, slack_penalty = get_slack_config(algorithms)
    prefix = determine_bus_prefix(node)
    penalty_expr = nothing
    shortage_sym = nothing
    excess_sym = nothing

    if slack_enabled && prefix !== nothing
        bus_code = get(node, "busCode", "")
        penalty_expr = add_slack_variables!(model, tracer, prefix, bus_code, time_index; penalty=slack_penalty)
        suffix = isempty(bus_code) ? "" : "_$(bus_code)"
        shortage_sym = Symbol("$(prefix)_SHORTAGE$(suffix)")
        excess_sym = Symbol("$(prefix)_EXCESS$(suffix)")
    end

    # 代码行
    sum_str = join(term_strs, " ")
    sum_str = lstrip(sum_str, [' ', '+'])
    if slack_enabled && prefix !== nothing
        sum_str = "$(sum_str) + $(prefix)_SHORTAGE$(suffix)[t] - $(prefix)_EXCESS$(suffix)[t]"
    end
    record!(tracer, "@constraint(model, [t in $(format_val(time_index))], $(sum_str) == 0.0)")

    # 实际创建
    if shortage_sym !== nothing && excess_sym !== nothing
        @constraint(
            model,
            [t in time_index],
            sum(model[term.var][t] * term.signal for term in terms) + model[shortage_sym][t] - model[excess_sym][t] == 0.0,
        )
    else
        @constraint(
            model,
            [t in time_index],
            sum(model[term.var][t] * term.signal for term in terms) == 0.0,
        )
    end

    return penalty_expr
end

"""带追踪的电总线平衡约束"""
build_energy_constraints_tracked!(model, tracer, node, layer, algorithms) =
    _build_energy_balance_tracked!(model, tracer, node, layer, algorithms, get_model_var_base, get_energy_signal)

"""带追踪的热总线平衡约束"""
build_thermal_energy_constraints_tracked!(model, tracer, node, layer, algorithms) =
    _build_energy_balance_tracked!(model, tracer, node, layer, algorithms, get_thermal_model_var_base, get_thermal_energy_signal)

"""带追踪的氢总线平衡约束"""
build_hydrogen_energy_constraints_tracked!(model, tracer, node, layer, algorithms) =
    _build_energy_balance_tracked!(model, tracer, node, layer, algorithms, get_hydrogen_model_var_base, get_hydrogen_energy_signal)

function persist_component_results!(db_path::String, model, component::AbstractComponent, layer::Dict{String,Any}, time::String;
    overlay_mode::Bool=false)
    timestamps = build_result_timestamps(layer, time)

    for binding in component_result_bindings(component)
        label = "$(binding.component_label)|$(String(binding.var_name))|$(binding.remark)#$(layer["id"])"
        ts = generate_result_ts(model, timestamps, binding.var_name, layer)
        if overlay_mode
            set_ts_merge(db_path, label, ts)
        else
            set_ts(db_path, label, ts)
        end
    end

    return nothing
end

# ── 跨窗口滚动优化：爬坡衔接约束 ──────────────────────────────────────────────

"""返回组件在当前时层需要做跨窗口首点衔接的功率变量及爬坡限值。"""
function _rolling_ramp_spec(component::AbstractComponent, ctx::BuildContext)
    comp_type = component_type(component)
    settings = layer_config(component, string(ctx.layer["id"]))
    get(settings, "status", "disabled") == "disabled" && return nothing
    constraints = get(settings, "constraints", Dict{String,Any}())
    get(constraints, "ramp_constraint_on", false) || return nothing

    paras = component_paras(component)
    code = component_code(component)
    step = step_hours(ctx.layer)

    if comp_type in ("CP", "GP", "CHP", "ET", "HYDRO")
        prefix = Dict(
            "CP" => "E_CP",
            "GP" => "E_GP",
            "CHP" => "E_CHP",
            "ET" => "E_ET",
            "HYDRO" => "E_HYDRO",
        )[comp_type]
        return (
            kind=:single,
            source_id=comp_type,
            input_prefix=nothing,
            output_prefix=prefix,
            code=code,
            limit=Float64(paras["ramp"]) * Float64(paras["capacity"]) * step,
        )
    elseif comp_type in ("WT", "PV")
        # 风光的自然资源变化不属于主动爬坡；与组件模型一致，只衔接弃电功率。
        prefix = comp_type == "WT" ? "E_WT_cut" : "E_PV_cut"
        return (
            kind=:single,
            source_id=comp_type,
            input_prefix=nothing,
            output_prefix=prefix,
            code=code,
            limit=Float64(paras["ramp"]) * Float64(paras["capacity"]) * step,
        )
    elseif comp_type == "PS"
        return (
            kind=:net,
            source_id="PS",
            input_prefix="E_PS_in",
            output_prefix="E_PS_out",
            code=code,
            limit=Float64(paras["ramp"]) * Float64(paras["capacity"]) * step,
        )
    end

    return nothing
end

"""
为每个滚动窗口的首点补充与上一已保存点之间的爬坡约束。

组件自身的模型负责窗口内部 `t -> t+1`；本函数只负责上一窗口最后保留点
`t-1 -> 本窗口首点`，两者合起来才构成连续时序。
"""
function add_rolling_ramp_constraints!(
    model,
    tracer::Union{CodeTracer,Nothing},
    components::Vector{<:AbstractComponent},
    ctx::BuildContext,
)
    first_t = first(generate_timespan(ctx.layer))

    for component in components
        spec = _rolling_ramp_spec(component, ctx)
        spec === nothing && continue

        output_name = isempty(spec.code) ? spec.output_prefix : "$(spec.output_prefix)_$(spec.code)"
        output_symbol = Symbol(output_name)
        haskey(JuMP.object_dictionary(model), output_symbol) || continue
        output_power = model[output_symbol]

        previous_output = previous_layer_result_value(
            ctx,
            spec.source_id,
            spec.output_prefix,
            spec.code,
        )
        previous_output === nothing && continue

        current_expr = output_power[first_t]
        previous_net = Float64(previous_output)
        current_code = "$(output_name)[$(first_t)]"

        if spec.kind == :net
            input_name = isempty(spec.code) ? spec.input_prefix : "$(spec.input_prefix)_$(spec.code)"
            input_symbol = Symbol(input_name)
            haskey(JuMP.object_dictionary(model), input_symbol) || continue
            input_power = model[input_symbol]
            previous_input = previous_layer_result_value(
                ctx,
                spec.source_id,
                spec.input_prefix,
                spec.code,
            )
            previous_input === nothing && continue
            current_expr = output_power[first_t] - input_power[first_t]
            previous_net -= Float64(previous_input)
            current_code = "($(output_name)[$(first_t)] - $(input_name)[$(first_t)])"
        end

        limit = Float64(spec.limit)
        if tracer === nothing
            @constraint(model, current_expr - previous_net <= limit)
            @constraint(model, previous_net - current_expr <= limit)
        else
            add_tracked_linear_constraint!(
                model,
                tracer,
                "@constraint(model, $(current_code) - $(format_val(previous_net)) <= $(format_val(limit)))",
                () -> @constraint(model, current_expr - previous_net <= limit),
            )
            add_tracked_linear_constraint!(
                model,
                tracer,
                "@constraint(model, $(format_val(previous_net)) - $(current_code) <= $(format_val(limit)))",
                () -> @constraint(model, previous_net - current_expr <= limit),
            )
        end
    end

    return nothing
end

"""
    build_model(component_dicts, algorithms, nodes, layer, time, db_path; all_layers=nothing)

构建优化模型。db_path 为任务级 TS DB 路径，供 upper_layer_values 等跨层数据读取使用。
all_layers 为项目 layerConfig.layers，传入时用于确定 max_layer_id。
"""
function build_model(component_dicts::Vector, algorithms::Dict{String,Any}, nodes::Vector,
    layer::Dict{String,Any}, time::String, db_path::String; all_layers::Union{Dict{String,Any},Nothing}=nothing)
    components = [instantiate_component(component_dict) for component_dict in component_dicts]
    max_lid = all_layers !== nothing ? parse(Int, get_max_layer_id(all_layers)) : 3 # ？？写死的3
    ctx = BuildContext(layer, time, algorithms, db_path, max_lid)

    model = create_jump_model(algorithms)
    objective_expr = @expression(model, 0.0)

    for component in components
        objective_expr += build_component_model!(model, component, ctx)
    end

    add_rolling_ramp_constraints!(model, nothing, components, ctx)

    for node in nodes
        pe = build_energy_constraints!(model, node, layer, algorithms)
        pe !== nothing && (objective_expr += pe)
        pe = build_hydrogen_energy_constraints!(model, node, layer, algorithms)
        pe !== nothing && (objective_expr += pe)
        pe = build_thermal_energy_constraints!(model, node, layer, algorithms)
        pe !== nothing && (objective_expr += pe)
    end

    @objective(model, Min, objective_expr)
    return model, components
end

"""
    build_model_tracked(component_dicts, algorithms, nodes, layer, time, db_path; all_layers=nothing)

构建优化模型，同时追踪构建过程代码。
返回 (model, construction_code::String)。
construction_code 是可直接在顶层 scope 执行的 Julia 代码字符串。
all_layers 为项目 layerConfig.layers，传入时用于确定 max_layer_id。
"""
function build_model_tracked(component_dicts::Vector, algorithms::Dict{String,Any}, nodes::Vector,
    layer::Dict{String,Any}, time::String, db_path::String; all_layers::Union{Dict{String,Any},Nothing}=nothing)
    components = [instantiate_component(component_dict) for component_dict in component_dicts]
    max_lid = all_layers !== nothing ? parse(Int, get_max_layer_id(all_layers)) : 3
    ctx = BuildContext(layer, time, algorithms, db_path, max_lid)
    tracer = CodeTracer()

    # ── 模型初始化 ────────────────────────────────────────────────────
    model = create_jump_model(algorithms)
    record!(tracer, "# ═══════════════════════════════════════════════════════════")
    record!(tracer, "# 模型构建过程 — 自动生成")
    record!(tracer, "# 时层: $(layer["id"]) | 步长: $(layer["step"]) | 长度: $(layer["length"])")
    record!(tracer, "# ═══════════════════════════════════════════════════════════")
    record!(tracer, "")
    record!(tracer, "using JuMP, COPT")
    record!(tracer, "model = Model(COPT.Optimizer)")
    record!(tracer, "set_silent(model)")
    record!(tracer, "")

    # ── 组件模型 ──────────────────────────────────────────────────────
    objective_expr = @expression(model, 0.0)
    for component in components
        comp_type = component_type(component)
        comp_code = component_code(component)
        record!(tracer, "# ── $(comp_type) ($(comp_code)) ──────────────────────────────────────")
        objective_expr += build_component_model!(model, component, ctx, tracer)
        record!(tracer, "")
    end

    # ── 跨滚动窗口首点衔接约束 ────────────────────────────────────────
    record!(tracer, "# ── 跨滚动窗口首点衔接约束 ────────────────────────────────")
    add_rolling_ramp_constraints!(model, tracer, components, ctx)
    record!(tracer, "")

    # ── 能量平衡约束 ──────────────────────────────────────────────────
    record!(tracer, "# ── 能量平衡约束 ──────────────────────────────────────────")
    for node in nodes
        bus_label = get(node, "busLabel", "")
        record!(tracer, "# 总线: $(bus_label)")
        pe = build_energy_constraints_tracked!(model, tracer, node, layer, algorithms)
        pe !== nothing && (objective_expr += pe)
        pe = build_hydrogen_energy_constraints_tracked!(model, tracer, node, layer, algorithms)
        pe !== nothing && (objective_expr += pe)
        pe = build_thermal_energy_constraints_tracked!(model, tracer, node, layer, algorithms)
        pe !== nothing && (objective_expr += pe)
    end
    record!(tracer, "")

    # ── 目标函数 ──────────────────────────────────────────────────────
    JuMP.set_objective(model, MOI.MIN_SENSE, objective_expr)
    if isempty(tracer.objective_expr_names)
        record!(tracer, "@objective(model, Min, 0.0)")
    else
        obj_str = join(tracer.objective_expr_names, " + ")
        record!(tracer, "@objective(model, Min, $(obj_str))")
    end

    # ── 求解 ──────────────────────────────────────────────────────
    record!(tracer, "JuMP.optimize!(model)")

    return model, components, get_code(tracer)
end

"""从 model 中收集所有松弛变量（SHORTAGE / EXCESS），返回 (label, var_sym) 列表。γ_SLACK 不持久化。"""
function _collect_slack_bindings(model)::Vector{Tuple{String,Symbol}}
    bindings = Tuple{String,Symbol}[]
    for var_name in keys(model.obj_dict)
        name_str = string(var_name)
        if occursin("_SHORTAGE", name_str) || occursin("_EXCESS", name_str)
            push!(bindings, ("BUS|$(name_str)|slack", var_name))
        end
    end
    return bindings
end

"""将松弛变量持久化到时序数据库"""
function _persist_slack_results!(db_path::String, model, layer::Dict{String,Any}, time::String;
    overlay_mode::Bool=false)
    slack_bindings = _collect_slack_bindings(model)
    isempty(slack_bindings) && return nothing

    timestamps = build_result_timestamps(layer, time)
    layer_id = layer["id"]
    for (label, var_sym) in slack_bindings
        full_label = "$(label)#$(layer_id)"
        ts = generate_result_ts(model, timestamps, var_sym, layer)
        if overlay_mode
            set_ts_merge(db_path, full_label, ts)
        else
            set_ts(db_path, full_label, ts)
        end
    end
    return nothing
end

function solve_model(model, component_dicts::Vector, layer::Dict{String,Any}, time::String, db_path::String;
    overlay_mode::Bool=false)
    components = [instantiate_component(component_dict) for component_dict in component_dicts]
    return solve_model(model, components, layer, time, db_path; overlay_mode)
end

function solve_model(model, components::Vector{<:AbstractComponent}, layer::Dict{String,Any}, time::String, db_path::String;
    overlay_mode::Bool=false)
    @info "Solving layer $(layer["id"]) at time $(time)."
    JuMP.optimize!(model)

    if JuMP.termination_status(model) != MOI.OPTIMAL
        status = JuMP.termination_status(model)
        primal = JuMP.primal_status(model)
        dual = JuMP.dual_status(model)
        @error "Optimization failed. Status: $(status), primal: $(primal), dual: $(dual)"
        return nothing
    end

    for component in components
        persist_component_results!(db_path, model, component, layer, time; overlay_mode)
    end

    # 持久化松弛变量
    _persist_slack_results!(db_path, model, layer, time; overlay_mode)

    obj_val = JuMP.objective_value(model)
    return obj_val, components
end
