# 计算任务求解主循环
# 文档：docs/compute-task-architecture.md § 6
#
# ┌─────────────────────────────────────────────────────────────────┐
# │  标注约定                                                       │
# │  ■ 接口逻辑（不要动）：状态管理、WS 推送、信号处理、parse、边界注入  │
# │  ★ 数学业务（你要开发的部分）：模型构建、求解、结果处理             │
# │  ★ 块用 #= ══ [数学业务] ══ =# 包裹，方便你快速定位               │
# └─────────────────────────────────────────────────────────────────┘

# ■ 接口逻辑：标记任务失败并清理上下文
function _fail_task!(ctx, task_id::String, msg::String)
    update_task_status!(task_id, TASK_FAILED, error_message=msg)
    broadcast_event(ctx, Dict("type" => "failed", "error" => msg, "taskId" => task_id))
    remove_context(task_id)
    return nothing
end

# ■ 接口逻辑：从 parse 产物构建 build_model 所需的 nodes 参数
# 直接透传 connection 记录，build_energy_constraints! 自行解析变量名
function build_nodes_from_connections(connections::Vector)
    return [Dict("busLabel" => conn["busLabel"], "busCode" => get(conn, "busCode", ""), "variables" => conn["variables"]) for conn in connections]
end

# ■ 接口逻辑：从任务 DB 读取 step_result 数据用于 WS 推送
function _read_step_results(store_path::String, layer_id::String, sim_time::String)
    store = get_store(store_path)
    lock(store.write_lock) do
        rows = _query(store.db, """
            SELECT m.source_id, m.var_name, d.value
            FROM time_series_data d
            JOIN time_series_meta m ON d.series_id = m.id
            WHERE m.remark = 'step_result' AND m.layer_id = ? AND d.ts = ?
        """, [layer_id, sim_time])

        isempty(rows[1]) && return Dict{String,Any}[]
        return [Dict(
            "sourceId" => rows[1][i],
            "varName" => rows[2][i],
            "layerId" => layer_id,
            "ts" => sim_time,
            "value" => Float64(rows[3][i])
        ) for i in 1:length(rows[1])]
    end
end

# ════════════════════════════════════════════════════════════════
# 子函数：阶段 1 — PARSE
# ════════════════════════════════════════════════════════════════

"""
    _parse_phase(ctx, task_id, task_dir)

执行 parse 阶段：读取 project.json，调用 parse_project，读取 parse 产物。
返回 (project_json, component_dicts, connections, algorithms) 或 nothing（失败时）。
"""
function _parse_phase(ctx, task_id::String, task_dir::String)
    update_task_status!(task_id, TASK_PARSING)
    broadcast_event(ctx, Dict("type" => "status", "status" => TASK_PARSING, "taskId" => task_id))

    project_json_path = joinpath(task_dir, "project.json")
    if !isfile(project_json_path)
        msg = "project.json 不存在于任务目录: $task_dir"
        _fail_task!(ctx, task_id, msg)
        return nothing
    end

    project_json = JSON3.read(read(project_json_path, String), Dict)
    parse_result = parse_project(project_json; output_dir=task_dir)
    if !parse_result.success
        msg = "parse 失败: $(parse_result.message)"
        _fail_task!(ctx, task_id, msg)
        return nothing
    end
    @info "task $task_id: parse 完成 — $(parse_result.componentCount) 组件, $(parse_result.connectionCount) 连接"

    # 读取 parse 产物
    component_path = joinpath(task_dir, "component.json")
    connection_path = joinpath(task_dir, "connection.json")
    @info "task $(task_id): [STEP] 读取 parse 产物..."
    component_dicts = JSON3.read(read(component_path, String), Vector{Dict{String,Any}})
    connections = JSON3.read(read(connection_path, String), Vector{Dict{String,Any}})
    algorithms = project_json["algorithm"]
    @info "task $(task_id): [STEP] 读取完成 components=$(length(component_dicts)) connections=$(length(connections))"

    return project_json, component_dicts, connections, algorithms
end

# ════════════════════════════════════════════════════════════════
# 子函数：阶段 2 — BUILD 准备
# ════════════════════════════════════════════════════════════════

"""
    _prepare_build_phase(ctx, task_id, project_json, connections)

执行 build 准备阶段：提取多层配置和 nodes。
返回 (all_layers, nodes) 或 nothing（失败时）。
"""
function _prepare_build_phase(ctx, task_id::String, project_json::Dict, connections::Vector)
    update_task_status!(task_id, TASK_BUILDING)
    broadcast_event(ctx, Dict("type" => "status", "status" => TASK_BUILDING, "taskId" => task_id))

    # layerConfig.layers 是 Vector，转为 Dict{String,Any} 以适配 layer_utils 函数
    layers_vec = project_json["layerConfig"]["layers"]
    all_layers = Dict{String,Any}(lc["id"] => lc for lc in layers_vec)
    nodes = build_nodes_from_connections(connections)
    @info "task $(task_id): [STEP] all_layers=$(length(all_layers)) nodes=$(length(nodes))"

    return all_layers, nodes
end

# ════════════════════════════════════════════════════════════════
# 子函数：阶段 3 — 边界注入
# ════════════════════════════════════════════════════════════════

"""
    _inject_boundary_phase(ctx, task_id, store_path, project_id, all_layers; sim_start_time, sim_end_time)

执行边界注入阶段：seed 边界数据到时序数据库。
基于 max_layer 的尺度生成唯一一组边界数据，按仿真时间范围截断。
返回 true（成功）或 nothing（失败时）。
"""
function _inject_boundary_phase(
    ctx, task_id::String, store_path::String, project_id::String, all_layers::Dict{String,Any};
    sim_start_time::Union{String,Nothing}=nothing,
    sim_end_time::Union{String,Nothing}=nothing,
)
    try
        n = seed_task_boundary_data(
            task_id, project_id, get_max_layer_id(all_layers);
            sim_start_time=sim_start_time,
            sim_end_time=sim_end_time,
        )
        # 确保 timeseries.db 始终存在（即使 seed 没找到数据）
        get_store(store_path)
        @info "task $task_id: seeded $n boundary series"
        return true
    catch e
        msg = "boundary seed failed: $(sprint(showerror, e))"
        _fail_task!(ctx, task_id, msg)
        return nothing
    end
end

# ════════════════════════════════════════════════════════════════
# 子函数：求解单层
# ════════════════════════════════════════════════════════════════

"""
    _solve_layer!(ctx, task_id, component_dicts, algorithms, nodes, layer, sim_time, store_path, code_dir, solved_steps)

构建并求解单个层。返回新的 solved_steps 值，失败时返回 nothing。
"""
function _solve_layer!(ctx, task_id::String, component_dicts::Vector, algorithms::Dict{String,Any},
    nodes::Vector, layer::Dict{String,Any}, sim_time::String, store_path::String, code_dir::String, solved_steps::Int;
    all_layers::Union{Dict{String,Any},Nothing}=nothing)

    lid = layer["id"]
    step_start = time()

    model, components, code = build_model_tracked(component_dicts, algorithms, nodes, layer, sim_time, store_path; all_layers=all_layers)
    time_tag = replace(sim_time, ":" => "-")
    code_file = joinpath(code_dir, "layer_$(lid)_$(time_tag).jl")
    write(code_file, code)

    # 求解（overlay 模式合并写入 + 回溯记录）
    solve_result = solve_model(model, components, layer, sim_time, store_path; overlay_mode=true)
    if solve_result === nothing
        status = JuMP.termination_status(model)
        msg = "求解失败: layer=$lid time=$sim_time status=$status"
        _fail_task!(ctx, task_id, msg)
        return nothing
    end

    _, solved_components = solve_result
    solved_steps += 1

    # 回溯：保存本次求解步完整快照
    trace_results = Tuple{String,TimeSeries}[]
    for comp in solved_components
        tss = build_result_timestamps(layer, sim_time)
        for binding in component_result_bindings(comp)
            blabel = "$(binding.component_label)|$(String(binding.var_name))|$(binding.remark)#$(lid)"
            push!(trace_results, (blabel, generate_result_ts(model, tss, binding.var_name, layer)))
        end
    end
    save_solve_trace!(store_path, task_id, solved_steps, lid, sim_time, trace_results)
    @info "task $(task_id): [SOLVE] step $(solved_steps) layer=$(lid) time=$(sim_time) ($(round(time()-step_start;digits=2))s)"

    return solved_steps
end

# ════════════════════════════════════════════════════════════════
# 子函数：检查 cancel 信号
# ════════════════════════════════════════════════════════════════

"""
    _check_signals(ctx, task_id, sim_time)

检查 cancel 信号。返回 :continue（无信号）或 :cancel。
"""
function _check_signals(ctx, task_id::String, sim_time::String)
    if isready(ctx.signal_ch)
        sig = take!(ctx.signal_ch)
        if sig == SIGNAL_CANCEL
            update_task_status!(task_id, TASK_CANCELLED)
            broadcast_event(ctx, Dict("type" => "cancelled", "currentTime" => sim_time, "taskId" => task_id))
            remove_context(task_id)
            return :cancel
        end
    end
    return :continue
end

# ════════════════════════════════════════════════════════════════
# 子函数：在线模式等待
# ════════════════════════════════════════════════════════════════

"""
    _wait_for_online_time(ctx, task_id, sim_time, mode)

在线模式下等待真实物理时间到达 sim_time。返回 :continue（已到达）或 :cancel（收到信号）。
"""
function _wait_for_online_time(ctx, task_id::String, sim_time::String, mode::String)
    mode != "online" && return :continue

    now_min = time_label_to_minutes(
        minutes_to_time_label(floor(Int, time_label_to_minutes("0:00") +
                                                 (time() - floor(time() / 86400) * 86400) / 60))
    )
    target_min = time_label_to_minutes(sim_time)
    if now_min < target_min
        sleep_min = target_min - now_min
        while true
            chunk = min(sleep_min, 60)
            if chunk <= 0
                break
            end
            sleep(chunk)
            sleep_min -= chunk

            sig_result = _check_signals(ctx, task_id, sim_time)
            sig_result != :continue && return sig_result
        end
    end
    return :continue
end

# ════════════════════════════════════════════════════════════════
# 子函数：辅助函数
# ════════════════════════════════════════════════════════════════

# 从组件配置提取指定 layer_id 的 layer dict
function _extract_layer(comps, layers_cfg, lid)
    # 从 layerConfig 取 step/length/forward，从组件配置取 status/paras/costs 等
    base = get(layers_cfg, lid, nothing)
    base === nothing && return nothing
    result = deepcopy(base)
    result["id"] = lid
    for comp in comps
        lcfg = get(comp, "layer", Dict())
        if haskey(lcfg, lid)
            for (k, v) in lcfg[lid]
                result[k] = v
            end
            break
        end
    end
    return result
end

function _flexibility_evaluation_timestamps(
    layer::AbstractDict,
    sim_time::String,
    sim_end::Union{Nothing,String},
)
    for field in ("id", "step", "length", "forward")
        haskey(layer, field) ||
            throw(ArgumentError("Flexibility evaluation layer must contain $(field)."))
    end
    duration = string(layer["id"]) == "1" ?
        string(layer["length"]) : string(layer["forward"])
    step = string(layer["step"])
    duration_minutes = time_str_to_minutes(duration)
    step_minutes = time_str_to_minutes(step)
    duration_minutes % step_minutes == 0 || throw(
        ArgumentError("Flexibility evaluation window must be divisible by layer step."),
    )
    timestamps = generate_timestamps(sim_time, step, duration)
    sim_end === nothing && return timestamps
    end_minutes = time_label_to_minutes(sim_end)
    return [
        timestamp for timestamp in timestamps
        if time_label_to_minutes(timestamp) + step_minutes <= end_minutes
    ]
end

function _evaluate_flexibility_after_solve!(
    ctx,
    task_id::String,
    component_dicts::Vector,
    layer::AbstractDict,
    sim_time::String,
    sim_end::Union{Nothing,String},
    store_path::String,
    config::Union{Nothing,FlexibilityEvaluationConfig},
)
    config === nothing && return SystemFlexibilityMarginResult[]
    string(layer["id"]) == config.layer_id ||
        return SystemFlexibilityMarginResult[]
    timestamps = _flexibility_evaluation_timestamps(layer, sim_time, sim_end)
    isempty(timestamps) && return SystemFlexibilityMarginResult[]

    components = AbstractComponent[
        instantiate_component(component_dict) for component_dict in component_dicts
    ]
    evaluation = evaluate_system_flexibility(
        components,
        store_path;
        layer=layer,
        timestamps=timestamps,
        case_id=task_id,
        config=config,
    )
    persist_system_flexibility_period_results!(
        store_path,
        config.layer_id,
        evaluation.margin_results,
    )
    rows = system_flexibility_margin_result_dict.(evaluation.margin_results)
    broadcast_event(ctx, Dict(
        "type" => "flexibility",
        "taskId" => task_id,
        "layerId" => config.layer_id,
        "startTimestamp" => first(timestamps),
        "endTimestamp" => time_label_add(last(timestamps), string(layer["step"])),
        "rows" => rows,
    ))
    return evaluation.margin_results
end

# ════════════════════════════════════════════════════════════════
# 单层仿真主函数
# ════════════════════════════════════════════════════════════════

"""
    run_single_layer_task(task_id::String, task::Dict)

单层仿真任务协程入口。只求解用户指定的单层，按时间步长(forward)推进。
与 run_task 的区别：
1. 不先求解 layer1 制定计划
2. 只求解指定的目标层
3. 使用该层的 forward 作为时间步长
"""
function run_single_layer_task(task_id::String, task::Dict)

    # ■ 接口逻辑：初始化任务上下文
    ctx = get_or_create_context(
        task_id,
        task["mode"],
        get(task, "sim_end_time", nothing),
        joinpath(TASKS_DATA_ROOT, task_id, "timeseries.db")
    )
    store_path = ctx.store_path
    target_layer_id = get(task, "target_layer_id", task["layer_id"])
    @info "task $(task_id): run_single_layer_task 启动 mode=$(task["mode"]) target_layer=$(target_layer_id) store=$(store_path)"
    try
        mode = ctx.mode
        sim_end = ctx.sim_end_time
        task_dir = dirname(store_path)
        mkpath(task_dir)

        # ════════════════════════════════════════════
        # 阶段 1 — PARSE
        # ════════════════════════════════════════════
        parse_result = _parse_phase(ctx, task_id, task_dir)
        parse_result === nothing && return nothing
        project_json, component_dicts, connections, algorithms = parse_result

        # ════════════════════════════════════════════
        # 阶段 2 — BUILD 准备
        # ════════════════════════════════════════════
        build_result = _prepare_build_phase(ctx, task_id, project_json, connections)
        build_result === nothing && return nothing
        all_layers, nodes = build_result

        # 验证目标层是否存在
        if !haskey(all_layers, target_layer_id)
            msg = "目标层 $(target_layer_id) 不存在于项目 layerConfig 中"
            _fail_task!(ctx, task_id, msg)
            return nothing
        end

        # ════════════════════════════════════════════
        # 阶段 3 — 边界注入
        # ════════════════════════════════════════════
        boundary_result = _inject_boundary_phase(
            ctx, task_id, store_path, task["project_id"], all_layers;
            sim_start_time=get(task, "sim_start_time", nothing),
            sim_end_time=get(task, "sim_end_time", nothing),
        )
        boundary_result === nothing && return nothing

        # ════════════════════════════════════════════
        # 阶段 4 — SOLVING（单层仿真）
        # ════════════════════════════════════════════
        @info "task $(task_id): [STEP] 进入 SOLVING 阶段（单层仿真）"
        update_task_status!(task_id, TASK_SOLVING)
        broadcast_event(ctx, Dict("type" => "status", "status" => TASK_SOLVING, "taskId" => task_id))

        # ■ 接口逻辑：确定起始时间
        sim_time = task["sim_start_time"]
        solved_steps = 0

        # ★═══════════════════════════════════════════════════════════
        # ★  [数学业务] 单层仿真主循环
        # ★═══════════════════════════════════════════════════════════

        # ★ [数学业务] 准备
        target_layer = _extract_layer(component_dicts, all_layers, target_layer_id)
        if target_layer === nothing
            msg = "无法提取目标层 $(target_layer_id) 的配置"
            _fail_task!(ctx, task_id, msg)
            return nothing
        end

        # 使用目标层的 forward 作为时间步长
        layer_forward = get(target_layer, "forward", nothing)
        if layer_forward === nothing
            msg = "目标层 $(target_layer_id) 缺少 forward 配置"
            _fail_task!(ctx, task_id, msg)
            return nothing
        end
        step_min = time_str_to_minutes(layer_forward)

        sim_end_min = sim_end !== nothing ? time_label_to_minutes(sim_end) : nothing
        code_dir = joinpath(task_dir, "generated")
        mkpath(code_dir)
        @info "task $(task_id): [INIT] single_layer=$(target_layer_id) forward=$(layer_forward) sim_time=$(sim_time)"

        # ★ [数学业务] 单层仿真时间推进循环
        while true
            # ■ 接口逻辑：检查 pause/cancel 信号
            sig_result = _check_signals(ctx, task_id, sim_time)
            sig_result == :cancel && return nothing

            # ■ 接口逻辑：在线模式等真实物理时间
            wait_result = _wait_for_online_time(ctx, task_id, sim_time, mode)
            wait_result == :cancel && return nothing

            # ■ 接口逻辑：检查是否到 sim_end
            if sim_end_min !== nothing
                if time_label_to_minutes(sim_time) >= sim_end_min
                    break
                end
            end

            # ★ [数学业务] 求解目标层
            solved_steps = _solve_layer!(ctx, task_id, component_dicts, algorithms, nodes, target_layer, sim_time, store_path, code_dir, solved_steps; all_layers=all_layers)
            solved_steps === nothing && return nothing

            sleep(0.2) # 必须存在，否则求解速度超过数据库读写速度，会导致前端渲染阻塞

            # ★ [数学业务] 推进 sim_time
            cur_min = time_label_to_minutes(sim_time)
            new_min = cur_min + step_min
            sim_time = minutes_to_time_label(new_min)
        end
        # ★═══════════════════════════════════════════════════════════
        # ★  [数学业务] 单层仿真主循环 — 结束
        # ★═══════════════════════════════════════════════════════════

        # ════════════════════════════════════════════
        # 阶段 5 — 完成
        # ════════════════════════════════════════════
        update_task_status!(task_id, TASK_COMPLETED)
        broadcast_event(ctx, Dict("type" => "completed", "taskId" => task_id, "finalTime" => sim_time, "solvedSteps" => solved_steps))
        remove_context(task_id)
        return nothing

    catch e
        bt = catch_backtrace()
        @error "task $(task_id): 未捕获异常（单层仿真）" exception=(e, bt)
        msg = "内部错误: $(sprint(showerror, e))"
        flush(stderr)
        try
            _fail_task!(ctx, task_id, msg)
        catch e2
            @error "task $(task_id): 错误报告也失败了" exception=e2
        end
        return nothing
    end
end

# ════════════════════════════════════════════════════════════════
# 主函数
# ════════════════════════════════════════════════════════════════

"""
    run_task(task_id::String, task::Dict)

任务协程入口。由 task_manager 在 create_task 时调度。
"""
function run_task(task_id::String, task::Dict)

    # ■ 接口逻辑：初始化任务上下文
    ctx = get_or_create_context(
        task_id,
        task["mode"],
        get(task, "sim_end_time", nothing),
        joinpath(TASKS_DATA_ROOT, task_id, "timeseries.db")
    )
    store_path = ctx.store_path
    @info "task $(task_id): run_task 启动 mode=$(task["mode"]) store=$(store_path)"
    try
        mode = ctx.mode
        sim_end = ctx.sim_end_time
        task_dir = dirname(store_path)
        mkpath(task_dir)

        # ════════════════════════════════════════════
        # 阶段 1 — PARSE
        # ════════════════════════════════════════════
        parse_result = _parse_phase(ctx, task_id, task_dir)
        parse_result === nothing && return nothing
        project_json, component_dicts, connections, algorithms = parse_result

        # ════════════════════════════════════════════
        # 阶段 2 — BUILD 准备
        # ════════════════════════════════════════════
        build_result = _prepare_build_phase(ctx, task_id, project_json, connections)
        build_result === nothing && return nothing
        all_layers, nodes = build_result
        flexibility_config = flexibility_evaluation_config_from_task(task)
        if flexibility_config !== nothing && !haskey(all_layers, flexibility_config.layer_id)
            error(
                "flexibility.layerId=$(flexibility_config.layer_id) does not exist " *
                "in project layerConfig.",
            )
        end
        flexibility_margins = SystemFlexibilityMarginResult[]

        # ════════════════════════════════════════════
        # 阶段 3 — 边界注入
        # ════════════════════════════════════════════
        boundary_result = _inject_boundary_phase(
            ctx, task_id, store_path, task["project_id"], all_layers;
            sim_start_time=get(task, "sim_start_time", nothing),
            sim_end_time=get(task, "sim_end_time", nothing),
        )
        boundary_result === nothing && return nothing

        # ════════════════════════════════════════════
        # 阶段 4 — SOLVING
        # ════════════════════════════════════════════
        @info "task $(task_id): [STEP] 进入 SOLVING 阶段"
        update_task_status!(task_id, TASK_SOLVING)
        broadcast_event(ctx, Dict("type" => "status", "status" => TASK_SOLVING, "taskId" => task_id))

        # ■ 接口逻辑：确定起始时间
        sim_time = task["sim_start_time"]
        solved_steps = 0

        # ★═══════════════════════════════════════════════════════════
        # ★  [数学业务] 分层窗口滚动主循环
        # ★  layer1 按 length 窗口推进，每个窗口内下层按 forward 滚动
        # ★═══════════════════════════════════════════════════════════

        # ★ [数学业务] 准备
        layer_ids = generate_layer_ids(all_layers)   # ["2","3","4",...]（不含第1层）
        max_layer_id = get_max_layer_id(all_layers)
        global_forward = all_layers[max_layer_id]["forward"]
        global_step_min = time_str_to_minutes(global_forward)
        sim_end_min = sim_end !== nothing ? time_label_to_minutes(sim_end) : nothing
        code_dir = joinpath(task_dir, "generated")
        mkpath(code_dir)

        layer1 = _extract_layer(component_dicts, all_layers, "1")
        layer1_length_min = layer1 !== nothing ? time_str_to_minutes(layer1["length"]) : nothing

        @info "task $(task_id): [INIT] all_layers=$(length(all_layers)) global_forward=$(global_forward) sim_time=$(sim_time) layer1_length=$(layer1_length_min !== nothing ? layer1_length_min : "N/A")min"

        # ★ [数学业务] 外层循环：遍历 layer1 窗口
        while true
            # ★ [数学业务] 检查剩余时间是否足够一个完整窗口
            if layer1 !== nothing && layer1_length_min !== nothing
                window_end_min = time_label_to_minutes(sim_time) + layer1_length_min
                if sim_end_min !== nothing && window_end_min > sim_end_min
                    @info "task $(task_id): [END] 剩余时间不足一个 layer1 窗口，仿真结束"
                    break
                end
            else
                # 没有 layer1 时，整个仿真范围作为一个窗口
                window_end_min = sim_end_min
            end

            # ■ 接口逻辑：检查 cancel 信号
            sig_result = _check_signals(ctx, task_id, sim_time)
            sig_result == :cancel && return nothing

            # ★ [数学业务] 求解 layer1（当前窗口起点）
            if layer1 !== nothing
                solved_steps = _solve_layer!(ctx, task_id, component_dicts, algorithms, nodes, layer1, sim_time, store_path, code_dir, solved_steps; all_layers=all_layers)
                solved_steps === nothing && return nothing
                append!(
                    flexibility_margins,
                    _evaluate_flexibility_after_solve!(
                        ctx,
                        task_id,
                        component_dicts,
                        layer1,
                        sim_time,
                        sim_end,
                        store_path,
                        flexibility_config,
                    ),
                )
            end

            # ★ [数学业务] 内层循环：在当前窗口内滚动下层
            inner_sim_time = sim_time
            while true
                # ★ [数学业务] 检查是否到达窗口终点
                if window_end_min !== nothing && time_label_to_minutes(inner_sim_time) >= window_end_min
                    break
                end

                # ■ 接口逻辑：检查 cancel 信号
                sig_result = _check_signals(ctx, task_id, inner_sim_time)
                sig_result == :cancel && return nothing

                # ■ 接口逻辑：在线模式等真实物理时间
                wait_result = _wait_for_online_time(ctx, task_id, inner_sim_time, mode)
                wait_result == :cancel && return nothing

                # ★ [数学业务] 遍历所有后续层，按 is_time_divisible 决定是否构建+求解
                for lid in layer_ids
                    flayer = _extract_layer(component_dicts, all_layers, lid)
                    flayer === nothing && continue
                    fwd = get(flayer, "forward", nothing)
                    fwd === nothing && continue
                    if is_time_divisible(inner_sim_time, fwd)
                        solved_steps = _solve_layer!(ctx, task_id, component_dicts, algorithms, nodes, flayer, inner_sim_time, store_path, code_dir, solved_steps; all_layers=all_layers)
                        solved_steps === nothing && return nothing
                        append!(
                            flexibility_margins,
                            _evaluate_flexibility_after_solve!(
                                ctx,
                                task_id,
                                component_dicts,
                                flayer,
                                inner_sim_time,
                                sim_end,
                                store_path,
                                flexibility_config,
                            ),
                        )
                    end
                end

                sleep(0.2) # 必须存在，否则求解速度超过数据库读写速度，会导致前端渲染阻塞

                # ★ [数学业务] 推进内层 sim_time
                cur_min = time_label_to_minutes(inner_sim_time)
                new_min = cur_min + global_step_min
                inner_sim_time = minutes_to_time_label(new_min)
            end

            # ★ [数学业务] 窗口完成，推进到下一个 layer1 窗口
            if layer1 !== nothing && layer1_length_min !== nothing
                sim_time = minutes_to_time_label(time_label_to_minutes(sim_time) + layer1_length_min)
            else
                break
            end
        end
        # ★═══════════════════════════════════════════════════════════
        # ★  [数学业务] 分层窗口滚动主循环 — 结束
        # ★═══════════════════════════════════════════════════════════

        # ════════════════════════════════════════════
        # 阶段 5 — 完成
        # ════════════════════════════════════════════
        if flexibility_config !== nothing
            isempty(flexibility_margins) && error(
                "Flexibility evaluation produced no periods for " *
                "layer $(flexibility_config.layer_id).",
            )
            summaries = summarize_system_flexibility_margin(flexibility_margins)
            persist_system_flexibility_summary_results!(
                store_path,
                flexibility_config.layer_id,
                summaries,
            )
            broadcast_event(ctx, Dict(
                "type" => "flexibility_summary",
                "taskId" => task_id,
                "layerId" => flexibility_config.layer_id,
                "rows" => system_flexibility_margin_summary_result_dict.(summaries),
            ))
        end
        update_task_status!(task_id, TASK_COMPLETED)
        broadcast_event(ctx, Dict("type" => "completed", "taskId" => task_id, "finalTime" => sim_time, "solvedSteps" => solved_steps))
        remove_context(task_id)
        return nothing

    catch e
        bt = catch_backtrace()
        @error "task $(task_id): 未捕获异常" exception=(e, bt)
        msg = "内部错误: $(sprint(showerror, e))"
        flush(stderr)
        try
            _fail_task!(ctx, task_id, msg)
        catch e2
            @error "task $(task_id): 错误报告也失败了" exception=e2
        end
        return nothing
    end
end

# ■ 接口逻辑：spawn_task（调度入口，不要动）
function spawn_task(task_id::String, task::Dict)
    ctx = get_or_create_context(
        task_id,
        task["mode"],
        get(task, "sim_end_time", nothing),
        joinpath(TASKS_DATA_ROOT, task_id, "timeseries.db")
    )
    # 根据 simMode 分发到不同的求解函数
    sim_mode = get(task, "sim_mode", "multi_layer")
    solve_func = sim_mode == "single_layer" ? run_single_layer_task : run_task
    jl_task = @async try
        solve_func(task_id, task)
    catch e
        bt = catch_backtrace()
        @error "task $(task_id): 协程顶层异常" exception=(e, bt)
        flush(stderr)
        rethrow()
    end
    lock(TASK_CONTEXTS_LOCK) do
        TASK_CONTEXTS[task_id].julia_task = jl_task
    end
    return jl_task
end
