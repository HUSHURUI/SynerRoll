# 容量规划变量表单与配置校验路由。
# 规划任务、聚类和优化执行会在后续阶段沿用这里的服务端 schema 契约。

@post "/api/capacity-planning/form-schema" function (req)
    try
        body = JSON3.read(req.body, Dict)
        canvas_id = require_string(body, "canvasId")
        project_json = get(body, "projectJson", nothing)
        project_json isa AbstractDict || return json_error("缺少 projectJson（项目快照）")

        data = detect_capacity_variables(project_json, canvas_id)
        return json_success(data = data)
    catch e
        return json_error("生成容量变量表单异常: $(sprint(showerror, e))")
    end
end

@post "/api/capacity-planning/validate" function (req)
    try
        body = JSON3.read(req.body, Dict)
        canvas_id = require_string(body, "canvasId")
        project_json = get(body, "projectJson", nothing)
        project_json isa AbstractDict || return json_error("缺少 projectJson（项目快照）")
        variables = get(body, "variables", nothing)
        variables isa AbstractVector || return json_error("variables 必须是数组")

        normalized = validate_capacity_variables(project_json, canvas_id, variables)
        return json_success(data = Dict(
            "canvasId" => canvas_id,
            "projectUpdatedAt" => string(get(project_json, "updateTime", "")),
            "variables" => normalized,
        ))
    catch e
        return json_error("容量变量配置校验失败: $(sprint(showerror, e))")
    end
end

@post "/api/capacity-planning/datasets/import" function (req)
    try
        body = JSON3.read(req.body, Dict)
        data = import_boundary_dataset(body)
        return json_success(data = data)
    catch e
        return json_error("导入历史边界数据集失败: $(sprint(showerror, e))")
    end
end

@get "/api/capacity-planning/datasets" function (req)
    try
        params = request_query_params(req)
        project_id = string(get(params, "projectId", ""))
        isempty(project_id) && return json_error("缺少 projectId")
        datasets = list_boundary_datasets(project_id)
        return json_success(data = Dict("datasets" => datasets))
    catch e
        return json_error("查询历史边界数据集失败: $(sprint(showerror, e))")
    end
end

@get "/api/capacity-planning/datasets/{id}" function (req, id)
    try
        params = request_query_params(req)
        project_id = string(get(params, "projectId", ""))
        isempty(project_id) && return json_error("缺少 projectId")
        data = get_boundary_dataset(project_id, String(id))
        return json_success(data = data)
    catch e
        return json_error("查询历史边界数据集详情失败: $(sprint(showerror, e))")
    end
end

@delete "/api/capacity-planning/datasets/{id}" function (req, id)
    try
        params = request_query_params(req)
        project_id = string(get(params, "projectId", ""))
        isempty(project_id) && return json_error("缺少 projectId")
        delete_boundary_dataset!(project_id, String(id))
        return json_success(data = Dict("datasetId" => String(id)))
    catch e
        return json_error("删除历史边界数据集失败: $(sprint(showerror, e))")
    end
end

@post "/api/capacity-planning/scenarios/preview" function (req)
    try
        body = JSON3.read(req.body, Dict)
        data = reduce_boundary_scenarios(body)
        return json_success(data = data)
    catch e
        return json_error("典型场景聚类失败: $(sprint(showerror, e))")
    end
end

# ───── 规划任务 ─────

@post "/api/capacity-planning" function (req)
    try
        task = create_capacity_planning!(JSON3.read(req.body, Dict))
        return json_success(data = task)
    catch e
        return json_error("创建容量规划任务失败: $(sprint(showerror, e))")
    end
end

@get "/api/capacity-planning" function (req)
    try
        params = request_query_params(req)
        project_id_raw = get(params, "projectId", nothing)
        project_id = project_id_raw === nothing ? nothing : String(project_id_raw)
        tasks = list_planning_tasks(project_id=project_id)
        return json_success(data = Dict("tasks" => tasks))
    catch e
        return json_error("查询容量规划任务失败: $(sprint(showerror, e))")
    end
end

@post "/api/capacity-planning/{id}/start" function (req, id)
    try
        task = start_capacity_planning!(String(id))
        return json_success(data = task)
    catch e
        return json_error("启动容量规划任务失败: $(sprint(showerror, e))")
    end
end

@post "/api/capacity-planning/{id}/cancel" function (req, id)
    try
        task = cancel_capacity_planning!(String(id))
        return json_success(data = task)
    catch e
        return json_error("取消容量规划任务失败: $(sprint(showerror, e))")
    end
end

@get "/api/capacity-planning/{id}/result" function (req, id)
    try
        task = get_planning_task(String(id))
        task === nothing && return json_error("容量规划任务不存在: $(id)")
        result = get_planning_result(String(id))
        result === nothing && return json_error("容量规划结果尚未生成")
        return json_success(data = result)
    catch e
        return json_error("查询容量规划结果失败: $(sprint(showerror, e))")
    end
end

@get "/api/capacity-planning/{id}" function (req, id)
    try
        task = get_planning_task(String(id))
        task === nothing && return json_error("容量规划任务不存在: $(id)")
        return json_success(data = task)
    catch e
        return json_error("查询容量规划任务失败: $(sprint(showerror, e))")
    end
end

@delete "/api/capacity-planning/{id}" function (req, id)
    try
        delete_planning_record!(String(id))
        return json_success(data = Dict("planningId" => String(id)))
    catch e
        return json_error("删除容量规划任务失败: $(sprint(showerror, e))")
    end
end
