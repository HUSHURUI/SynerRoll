# 计算任务 REST + WebSocket 路由
# 文档：docs/compute-task-architecture.md § 10
# 依赖：utils/server_utils.jl（json_success / json_error / require_string / optional_string）
#        services/task_manager.jl（任务 CRUD + ctx）
#        services/simulation_runner.jl（spawn_task）

query_params(req) = HTTP.queryparams(req.url)

using UUIDs: uuid4

# ───── POST /api/task/create ─────
# 请求体必须包含 projectJson（前端画布完整 JSON），供 parse 阶段使用
@post "/api/task/create" function (req)
    try
        body = JSON3.read(req.body, Dict)

        project_id  = require_string(body, "projectId")
        canvas_id   = require_string(body, "canvasId")
        layer_id    = require_string(body, "layerId")
        mode        = get(body, "mode", "offline")
        sim_start   = require_string(body, "simStartTime")
        sim_end     = optional_string(body, "simEndTime", "")
        name        = optional_string(body, "name", "")
        params_json = JSON3.write(body)
        params_hash = bytes2hex(SHA.sha256(params_json))

        # projectJson 是前端传来的完整画布 JSON，parse 阶段需要
        project_json = get(body, "projectJson", nothing)
        if project_json === nothing
            return json_error("缺少 projectJson（前端画布数据）")
        end

        task_id = string(uuid4())
        sim_end_val = isempty(sim_end) ? nothing : sim_end
        name_val = isempty(name) ? nothing : name
        flexibility_config = normalize_flexibility_evaluation_config(
            get(body, "flexibility", nothing);
            default_layer_id=layer_id,
        )
        flexibility_extra = flexibility_config === nothing ?
            StringAnyDict("enabled" => false) :
            flexibility_evaluation_config_dict(flexibility_config)
        extra_json = JSON3.write(StringAnyDict("flexibility" => flexibility_extra))

        # 存储 project.json 到任务目录（parse 阶段读取）
        task_dir = joinpath(TASKS_DATA_ROOT, task_id)
        mkpath(task_dir)
        write(joinpath(task_dir, "project.json"), JSON3.write(project_json))

        insert_task!(
            id              = task_id,
            project_id      = project_id,
            canvas_id       = canvas_id,
            layer_id        = layer_id,
            mode            = mode,
            name            = name_val,
            sim_start_time  = sim_start,
            sim_end_time    = sim_end_val,
            params_hash     = params_hash,
            extra_json      = extra_json,
        )

        task = get_task(task_id)
        if task === nothing
            return json_error("创建任务后查不到")
        end

        # 将前端传递的仿真模式参数添加到 task 字典
        task["sim_mode"] = get(body, "simMode", "multi_layer")
        task["target_layer_id"] = get(body, "targetLayerId", layer_id)

        spawn_task(task_id, task)
        return json_success(data = task)
    catch e
        return json_error("创建任务异常: $(sprint(showerror, e))")
    end
end

# ───── GET /api/task/list ─────
@get "/api/task/list" function (req)
    try
        q = query_params(req)
        project_id = get(q, "projectId", nothing)
        status     = get(q, "status", nothing)
        tasks = list_tasks(project_id = project_id, status = status)
        return json_success(data = Dict("tasks" => tasks))
    catch e
        return json_error("列任务异常: $(sprint(showerror, e))")
    end
end

# ───── GET /api/task/{id}/state ─────
@get "/api/task/{id}/state" function (req, id)
    try
        task = get_task(id)
        task === nothing && return json_error("任务不存在: $id")
        return json_success(data = task)
    catch e
        return json_error("查任务状态异常: $(sprint(showerror, e))")
    end
end

# ───── POST /api/task/{id}/cancel ─────
@post "/api/task/{id}/cancel" function (req, id)
    try
        lock(TASK_CONTEXTS_LOCK) do
            if !haskey(TASK_CONTEXTS, id)
                update_task_status!(id, TASK_CANCELLED)
                return json_success(message = "任务不在运行中，已直接标 cancelled")
            end
            ctx = TASK_CONTEXTS[id]
            try
                put!(ctx.signal_ch, SIGNAL_CANCEL)
            catch
                return json_error("发送 cancel 信号失败")
            end
        end
        return json_success(message = "cancel signal sent")
    catch e
        return json_error("取消异常: $(sprint(showerror, e))")
    end
end

# ───── DELETE /api/task/{id}（清理：删任务 DB + tasks.db 记录）──
@delete "/api/task/{id}" function (req, id)
    try
        task_dir = joinpath(TASKS_DATA_ROOT, id)
        if isdir(task_dir)
            rm(task_dir, recursive = true, force = true)
        end
        close_store(joinpath(task_dir, "timeseries.db"))
        delete_task!(id)
        remove_context(id)
        return json_success(data = Dict("taskId" => id), message = "任务已清理")
    catch e
        return json_error("清理异常: $(sprint(showerror, e))")
    end
end

# ───── GET /api/task/{id}/connection（拉任务总线→变量映射）──
@get "/api/task/{id}/connection" function (req, id)
    try
        conn_path = joinpath(TASKS_DATA_ROOT, id, "connection.json")
        if !isfile(conn_path)
            return json_success(data = [])
        end
        conn_data = JSON3.read(read(conn_path, String))
        return json_success(data = conn_data)
    catch e
        return json_error("拉连接数据异常: $(sprint(showerror, e))")
    end
end

# ───── GET /api/task/{id}/data（拉任务全部 TS 数据）──
@get "/api/task/{id}/data" function (req, id)
    try
        store_path = joinpath(TASKS_DATA_ROOT, id, "timeseries.db")
        isfile(store_path) || return json_success(data = Dict("rows" => []))

        store = get_store(store_path)
        lock(store.write_lock) do
            meta_rows = _query(store.db,
                "SELECT id, source_id, var_name, remark, layer_id FROM time_series_meta")

            isempty(meta_rows[1]) && return json_success(data = Dict("rows" => []))

            all_rows = Dict{String,Any}[]
            for i in 1:length(meta_rows[1])
                series_id = meta_rows[1][i]
                src_id = meta_rows[2][i]
                v_name = meta_rows[3][i]
                layer_id = meta_rows[5][i]

                data_rows = _query(store.db,
                    "SELECT ts, value FROM time_series_data WHERE series_id=?",
                    [series_id])
                isempty(data_rows[1]) && continue

                timestamps = Vector{String}(data_rows[1])
                values = Vector{Float64}(data_rows[2])
                perm = sortperm(timestamps; lt=time_label_less_than)

                for j in 1:length(perm)
                    push!(all_rows, Dict(
                        "sourceId" => src_id,
                        "varName" => v_name,
                        "layerId" => layer_id,
                        "ts" => timestamps[perm[j]],
                        "value" => values[perm[j]]
                    ))
                end
            end
            return json_success(data = Dict("rows" => all_rows))
        end
    catch e
        return json_error("拉数据异常: $(sprint(showerror, e))")
    end
end

# ───── GET /api/task/{id}/trace（拉回溯步列表）──
@get "/api/task/{id}/trace" function (req, id)
    try
        store_path = joinpath(TASKS_DATA_ROOT, id, "timeseries.db")
        isfile(store_path) || return json_success(data = Dict("steps" => []))
        steps = get_solve_trace_steps(store_path, id)
        return json_success(data = Dict("steps" => steps))
    catch e
        return json_error("拉回溯步列表异常: $(sprint(showerror, e))")
    end
end

# ───── GET /api/task/{id}/trace/{step}（拉某步全部数据）──
@get "/api/task/{id}/trace/{step}" function (req, id, step)
    try
        store_path = joinpath(TASKS_DATA_ROOT, id, "timeseries.db")
        isfile(store_path) || return json_success(data = Dict("rows" => []))
        step_num = parse(Int, String(step))
        data = get_solve_trace_data(store_path, id, step_num)
        # 转为 rows 格式，与 getData 保持一致风格
        rows = Dict{String,Any}[]
        for (data_key, ts) in data
            parsed = parse_ts_label(data_key)
            for i in 1:length(ts.timestamps)
                push!(rows, Dict(
                    "sourceId" => parsed["source_id"],
                    "varName"  => parsed["var_name"],
                    "remark"   => parsed["remark"],
                    "layerId"  => parsed["layer_id"],
                    "ts"       => ts.timestamps[i],
                    "value"    => ts.values[i],
                ))
            end
        end
        return json_success(data = Dict("rows" => rows))
    catch e
        return json_error("拉回溯数据异常: $(sprint(showerror, e))")
    end
end

# ───── GET /api/task/{id}/flexibility（拉灵活性逐时段与全时域结果）──
@get "/api/task/{id}/flexibility" function (req, id)
    try
        task = get_task(id)
        task === nothing && return json_error("任务不存在: $id")
        config = flexibility_evaluation_config_from_task(task)
        q = query_params(req)
        requested_layer_id = get(q, "layerId", nothing)
        layer_id = if requested_layer_id === nothing
            config === nothing ? String(task["layer_id"]) : config.layer_id
        else
            String(requested_layer_id)
        end
        store_path = joinpath(TASKS_DATA_ROOT, id, "timeseries.db")
        if !isfile(store_path)
            return json_success(data=Dict(
                "config" => config === nothing ? Dict("enabled" => false) :
                    flexibility_evaluation_config_dict(config),
                "periods" => Dict{String,Any}[],
                "summaries" => Dict{String,Any}[],
            ))
        end
        periods = read_system_flexibility_period_results(
            store_path;
            layer_id=layer_id,
        )
        summaries = read_system_flexibility_summary_results(
            store_path;
            layer_id=layer_id,
        )
        return json_success(data=Dict(
            "config" => config === nothing ? Dict("enabled" => false) :
                flexibility_evaluation_config_dict(config),
            "periods" => periods,
            "summaries" => summaries,
        ))
    catch e
        return json_error("拉灵活性结果异常: $(sprint(showerror, e))")
    end
end

# ───── WS /ws/task/{id}（实时双向）──
# Oxygen 的 parse_func_params 会把 ws 当查询参数，导致 KeyError
# 改用通配路由 + 手动匹配 req.target
@websocket "/ws/task/*" function (ws; request)
    m = match(r"^/ws/task/([^/]+)", String(request.target))
    task_id = m === nothing ? "" : String(m.captures[1])
    @info "[TaskWS] handler entered: task_id=$task_id target=$(request.target)"

    # 任务不存在则关闭连接
    if get_task(task_id) === nothing
        @warn "[TaskWS] task not found: $task_id"
        try send(ws, JSON3.write(Dict("type" => "error", "message" => "任务不存在"))) catch end
        return
    end

    # 取/建 ctx（resume 场景下 ctx 已存在，subscribe 拿 channel）
    ctx = lock(TASK_CONTEXTS_LOCK) do
        if haskey(TASK_CONTEXTS, task_id)
            TASK_CONTEXTS[task_id]
        else
            # 任务未运行（completed/failed/cancelled），订阅不到 live 事件
            nothing
        end
    end
    @info "[TaskWS] ctx lookup: task_id=$task_id has_ctx=$(ctx !== nothing)"

    if ctx === nothing
        # 任务未运行：保持连接，定期推送状态（前端可能在等任务完成）
        # 用 for msg in ws 迭代检测客户端断开，辅助定时轮询
        @info "[TaskWS] no ctx, entering poll loop: task_id=$task_id"
        last_status = ""
        try
            # 启动后台轮询 task 状态
            poll_task = @async begin
                while true
                    task = get_task(task_id)
                    if task === nothing
                        try send(ws, JSON3.write(Dict("type" => "error", "message" => "任务不存在"))) catch end
                        break
                    end
                    cur_status = task["status"]
                    if cur_status != last_status
                        send(ws, JSON3.write(Dict(
                            "type" => "status",
                            "taskId" => task_id,
                            "status" => cur_status
                        )))
                        last_status = cur_status
                    end
                    # 如果任务重新开始运行（resume），结束轮询
                    if haskey(TASK_CONTEXTS, task_id)
                        break
                    end
                    sleep(1)
                end
            end
            # 前台：等待客户端消息（保持连接存活），收到任何消息忽略
            for msg in ws
                @debug "[TaskWS] poll-mode received client msg (ignored): $msg"
            end
        catch e
            @info "[TaskWS] poll loop ended: task_id=$task_id err=$(sprint(showerror, e))"
        finally
            @info "[TaskWS] exiting poll loop: task_id=$task_id"
        end
        return
    end

    ch = subscribe(ctx)
    @info "[TaskWS] subscribed: task_id=$task_id"
    try
        # 立即推当前状态
        task = get_task(task_id)
        if task !== nothing
            try
                send(ws, JSON3.write(Dict(
                    "type" => "status",
                    "taskId" => task_id,
                    "status" => task["status"],
                    "currentTime" => task["cur_time"]
                )))
            catch e
                @warn "[TaskWS] failed to send initial status" exception=(e, catch_backtrace())
            end
        end

        # 后台推：ctx 广播事件 → ws
        forward_task = @async begin
            try
                while true
                    evt = take!(ch)  # 阻塞直到有事件或 channel 关闭
                    send(ws, JSON3.write(evt))
                end
            catch e
                if !(e isa InvalidStateException)
                    @warn "[TaskWS] forward error" exception=(e, catch_backtrace())
                end
            end
        end

        # 前台收：用 for msg in ws 迭代（HTTP.jl 推荐模式）
        # 连接关闭时自动结束迭代，不需要手动检查 isopen
        for msg in ws
            try
                data = JSON3.read(String(msg), Dict)
                sig = get(data, "type", "")
                if sig == "cancel"
                    put!(ctx.signal_ch, SIGNAL_CANCEL)
                end
            catch e
                @warn "[TaskWS] msg parse error" exception=(e, catch_backtrace())
            end
        end

        @info "[TaskWS] client disconnected: task_id=$task_id"
    catch e
        @warn "[TaskWS] handler error: task_id=$task_id" exception=(e, catch_backtrace())
    finally
        unsubscribe(ctx, ch)
        @info "[TaskWS] unsubscribed: task_id=$task_id"
    end
    return
end

# ───── 启动恢复（register 到 server.jl 启动时）──
function init_task_routes!()
    reconcile_running_tasks!()
    @info "Task routes initialized: $(length(TASK_CONTEXTS)) active tasks recovered"
    return nothing
end