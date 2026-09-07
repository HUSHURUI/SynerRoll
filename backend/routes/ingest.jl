# 外部数据接入（第三方采集 / 预测平台）
# 文档：docs/compute-task-architecture.md § 13

# ───── POST /api/ingest/project/{projectId}/boundary ─────
# 第三方推送"项目级"boundary 数据：写进 data/projects/<projectId>/boundary.db
@post "/api/ingest/project/{projectId}/boundary" function (req, projectId)
    try
        isempty(projectId) && return json_error("缺少 projectId")

        body = JSON3.read(req.body, Dict)

        source_id = require_string(body, "sourceId")
        var_name  = require_string(body, "varName")
        layer_id  = require_string(body, "layerId")
        ts        = require_string(body, "ts")
        remark    = optional_string(body, "remark", "actual")
        value     = get(body, "value", nothing)
        value === nothing && return json_error("缺少 value 字段")

        db_path = joinpath(BACKEND_DATA_DIR, "projects", projectId, "boundary.db")
        # 标记"接入"语义的 source_id 前缀，避免和前端 boundary.id 冲突
        # 但用户可能希望 source_id 就是第三方平台的标识，所以这里直接写
        label = "$(source_id)|$(var_name)|$(remark)#$(layer_id)"
        ts_obj = TimeSeries([ts], Float64[Float64(value)])
        set_ts(db_path, label, ts_obj)

        return json_success(data = Dict("label" => label), message = "已写入项目 boundary DB")
    catch e
        return json_error("写入项目 boundary 异常: $(sprint(showerror, e))")
    end
end

# ───── POST /api/ingest/ts/{taskId} ─────
# 第三方推送"任务级"求解中间数据：写进 data/tasks/<taskId>/timeseries.db
@post "/api/ingest/ts/{taskId}" function (req, taskId)
    try
        task = get_task(taskId)
        task === nothing && return json_error("任务不存在: $taskId")
        task["status"] in (TASK_CANCELLED, TASK_FAILED) && return json_error("任务已取消或失败，不能写入: $(task["status"])")

        body = JSON3.read(req.body, Dict)

        source_id = require_string(body, "sourceId")
        var_name  = require_string(body, "varName")
        layer_id  = require_string(body, "layerId")
        ts        = require_string(body, "ts")
        remark    = optional_string(body, "remark", "actual")
        value     = get(body, "value", nothing)
        value === nothing && return json_error("缺少 value 字段")

        db_path = joinpath(BACKEND_DATA_DIR, "tasks", taskId, "timeseries.db")
        isfile(db_path) || return json_error("任务 DB 不存在: $db_path（可能任务还未启动或已被清理）")

        label = "$(source_id)|$(var_name)|$(remark)#$(layer_id)"
        ts_obj = TimeSeries([ts], Float64[Float64(value)])
        set_ts(db_path, label, ts_obj)

        return json_success(data = Dict("label" => label), message = "已写入任务 TS DB")
    catch e
        return json_error("写入任务 TS 异常: $(sprint(showerror, e))")
    end
end

"""
    init_ingest_routes!()

占位函数（与 task 路由一样，注册到 server.jl 启动时）。
目前 ingest 路由在 routes/ingest.jl include 时就自动注册到 Oxygen。
"""
function init_ingest_routes!()
    @info "Ingest routes registered: POST /api/ingest/project/{id}/boundary, POST /api/ingest/ts/{id}"
    return nothing
end