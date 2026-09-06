using Oxygen
using JSON3
using HTTP
using Dates
using JuMP
using CSV
using DataFrames
using SHA
using COPT

# ─────────────────────────────────────────────────────────────────────────────
# 模块加载
# ─────────────────────────────────────────────────────────────────────────────
begin
    # 解析服务（画布 JSON → component/connection/mapping JSON）
    include("services/parse_service.jl")

    # 核心模块
    include("core/types.jl")
    include("core/component_framework.jl")
    include("core/schema.jl")
    include("core/validation.jl")
    include("core/flexibility.jl")
    include("core/system_flexibility.jl")

    # 容量规划类型和检测模块（不依赖 utils）
    include("services/capacity_planning/types.jl")
    include("services/capacity_planning/variable_detector.jl")
    include("services/capacity_planning/candidate_snapshot.jl")

    # 工具模块
    include("utils/timestr_utils.jl")
    include("utils/timeseries_utils.jl")
    include("utils/layer_utils.jl")
    include("utils/model_utils.jl")
    include("utils/model_builder_utils.jl")
    include("utils/prediction_utils.jl")
    include("utils/server_utils.jl")
    include("utils/flexibility_utils.jl")

    # 容量规划存储和服务模块（依赖 utils 中的 get_store/_query/_exec）


    # 服务模块（需在utils和components之前加载，prediction_utils.jl依赖TimeSeries）
    include("services/boundary_service.jl")

    # 聚类模块（依赖 utils + boundary_service 中的 parse_boundary_data）
    include("services/capacity_planning/scenario_reducer.jl")

    # 组件模块
    include("components/wind_turbine/component.jl")
    include("components/wind_turbine/validation.jl")
    include("components/wind_turbine/model-common.jl")
    include("components/wind_turbine/flexibility.jl")
    include("components/wind_turbine/model.jl")

    include("components/photovoltaic/component.jl")
    include("components/photovoltaic/validation.jl")
    include("components/photovoltaic/model-common.jl")
    include("components/photovoltaic/flexibility.jl")
    include("components/photovoltaic/model.jl")

    include("components/coal_power/component.jl")
    include("components/coal_power/validation.jl")
    include("components/coal_power/model-common.jl")
    include("components/coal_power/flexibility.jl")
    include("components/coal_power/model.jl")

    include("components/gas_power/component.jl")
    include("components/gas_power/validation.jl")
    include("components/gas_power/model-common.jl")
    include("components/gas_power/flexibility.jl")
    include("components/gas_power/model.jl")

    include("components/combined_heat_power/component.jl")
    include("components/combined_heat_power/validation.jl")
    include("components/combined_heat_power/model-common.jl")
    include("components/combined_heat_power/flexibility.jl")
    include("components/combined_heat_power/model.jl")

    include("components/electrolyzer/component.jl")
    include("components/electrolyzer/validation.jl")
    include("components/electrolyzer/model-common.jl")
    include("components/electrolyzer/flexibility.jl")
    include("components/electrolyzer/model-base.jl")
    include("components/electrolyzer/model.jl")

    include("components/electricity_load/component.jl")
    include("components/electricity_load/validation.jl")
    include("components/electricity_load/model-common.jl")
    include("components/electricity_load/flexibility.jl")
    include("components/electricity_load/model.jl")

    include("components/hydrogen_load/component.jl")
    include("components/hydrogen_load/validation.jl")
    include("components/hydrogen_load/model-common.jl")
    include("components/hydrogen_load/flexibility.jl")
    include("components/hydrogen_load/model.jl")

    include("components/electricity_storage/component.jl")
    include("components/electricity_storage/validation.jl")
    include("components/electricity_storage/model-common.jl")
    include("components/electricity_storage/flexibility.jl")
    include("components/electricity_storage/model.jl")

    include("components/hydrogen_storage/component.jl")
    include("components/hydrogen_storage/validation.jl")
    include("components/hydrogen_storage/model-common.jl")
    include("components/hydrogen_storage/flexibility.jl")
    include("components/hydrogen_storage/model.jl")

    include("components/flywheel_storage/component.jl")
    include("components/flywheel_storage/validation.jl")
    include("components/flywheel_storage/model-common.jl")
    include("components/flywheel_storage/flexibility.jl")
    include("components/flywheel_storage/model.jl")

    include("components/compressed_air_storage/component.jl")
    include("components/compressed_air_storage/validation.jl")
    include("components/compressed_air_storage/model-common.jl")
    include("components/compressed_air_storage/flexibility.jl")
    include("components/compressed_air_storage/model.jl")

    include("components/pumped_storage/component.jl")
    include("components/pumped_storage/validation.jl")
    include("components/pumped_storage/model-common.jl")
    include("components/pumped_storage/flexibility.jl")
    include("components/pumped_storage/model.jl")

    include("components/heat_load/component.jl")
    include("components/heat_load/validation.jl")
    include("components/heat_load/model-common.jl")
    include("components/heat_load/flexibility.jl")
    include("components/heat_load/model.jl")

    include("components/power_grid/component.jl")
    include("components/power_grid/validation.jl")
    include("components/power_grid/model-common.jl")
    include("components/power_grid/flexibility.jl")
    include("components/power_grid/model.jl")

    include("components/hydro_power/component.jl")
    include("components/hydro_power/validation.jl")
    include("components/hydro_power/model-common.jl")
    include("components/hydro_power/flexibility.jl")
    include("components/hydro_power/model.jl")

    include("services/model_service.jl")

    # 灵活性评价服务
    include("services/flexibility_baseline_adapter.jl")
    include("services/flexibility_supply_service.jl")
    include("services/flexibility_requirement_service.jl")
    include("services/flexibility_margin_service.jl")
    include("services/flexibility_evaluation_service.jl")
    include("services/flexibility_result_service.jl")

    # 容量规划服务（后期加载，依赖 services）
    include("services/capacity_planning/simulation_evaluator.jl")
    include("services/capacity_planning/economic_evaluator.jl")
    include("services/capacity_planning/planning_store.jl")
    include("services/capacity_planning/optimization_runner.jl")
    include("services/capacity_planning/planning_manager.jl")

    # 计算任务模块（计算任务方案：阶段 1-4）
    include("services/task_manager.jl")
    include("services/simulation_runner.jl")
    include("routes/task.jl")
    include("routes/ingest.jl")
    include("routes/capacity_planning.jl")

    const _COMPONENT_LIB_PATH = joinpath(@__DIR__, "..", "config", "component-library.json")
    load_component_library(_COMPONENT_LIB_PATH)
end
# ─────────────────────────────────────────────────────────────────────────────
# 全局常量
# ─────────────────────────────────────────────────────────────────────────────

const PORT = parse(Int, get(ENV, "PORT", "8080"))

# 边界业务下 TS 库的 source_id 字段 = 边界在 projects.json 中的 BoundaryID
# 每条边界拥有独立 source_id，因此即使 meaning 相同也不互覆盖；
# 「哪个节点用了哪个边界」的关联只存于 projects.json。

const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "POST, GET, OPTIONS"
]

"""CORS 中间件：追加 CORS 头，保留原始 status code"""
function CorsMiddleware(handler)
    return function (req::HTTP.Request)
        response = handler(req)
        for (k, v) in CORS_HEADERS
            HTTP.setheader(response, k => v)
        end
        return response
    end
end

# ══════════════════════════════════════════════════════════════════════════════
# 1. 解析服务  POST /api/parse
# 接收前端项目JSON，解析生成: component.json / connection.json / mapping.json
# ══════════════════════════════════════════════════════════════════════════════
# @post "/api/parse" function (req)
#     try
#         project_json = JSON3.read(req.body, Dict)

#         result = parse_project(project_json)

#         if result.success
#             return JSON3.write(Dict(
#                 "success" => true,
#                 "message" => result.message,
#                 "outputPath" => result.outputPath,
#                 "componentCount" => result.componentCount,
#                 "connectionCount" => result.connectionCount,
#             ))
#         else
#             return JSON3.write(Dict("success" => false, "message" => result.message))
#         end
#     catch e
#         return JSON3.write(Dict(
#             "success" => false,
#             "message" => "解析异常: $(sprint(showerror, e))"
#         ))
#     end
# end

# ══════════════════════════════════════════════════════════════════════════════
# 1.5. 边界导入服务  POST /api/boundary/import
# 接收文件路径、列名等信息，读取CSV文件并返回截断后的数据
# 截断到24h的倍数（最少24h）
# ══════════════════════════════════════════════════════════════════════════════
@post "/api/boundary/import" function (req)
    try
        body = JSON3.read(req.body, Dict)

        file_path = require_string(body, "filePath")
        column_name = require_string(body, "columnName")
        time_step = optional_string(body, "timeStep", "1h")

        col_data, _ = read_csv_column(file_path, column_name)
        raw_values = extract_float_column(col_data)

        # 调用预处理函数：截断到24h的倍数
        result = preprocess_boundary_data(Vector{Any}(raw_values), time_step)

        return json_success(data=Dict(
            "values" => result["values"],
            "timestamps" => result["timestamps"],
            "xAxisLabel" => "时间",
            "yAxisLabel" => column_name,
            "pointCount" => result["pointCount"],
            "totalHours" => result["totalHours"],
            "dayCount" => result["dayCount"],
            "timeStep" => result["timeStep"],
        ))
    catch e
        return json_error("导入异常: $(sprint(showerror, e))")
    end
end

# ══════════════════════════════════════════════════════════════════════════════
# 1.6. 边界转换服务  POST /api/boundary/transform
# 按 filePath 读取本地文件，转换为各层的时间序列后返回
# 不查库也不入库，结果通过 submit 正式写入 TS 库
# 如果提供 boundaryLength，则使用它作为转换长度，否则使用 layer1 的长度
# ══════════════════════════════════════════════════════════════════════════════
@post "/api/boundary/transform" function (req)
    try
        body = JSON3.read(req.body, Dict)

        file_path = require_string(body, "filePath")
        column_name = require_string(body, "columnName")
        time_step = optional_string(body, "timeStep", "1h")
        interpolate_type = optional_string(body, "interpolateType", "copy")
        noise_level = get(body, "noiseLevel", 0.0)
        layer_config = get(body, "layerConfig", nothing)
        boundary_length = optional_string(body, "boundaryLength", "")

        layer_config === nothing && error("缺少 layerConfig")

        col_data, _ = read_csv_column(file_path, column_name)
        raw_values = extract_float_column(col_data)

        layers_array = get(layer_config, "layers", [])
        isempty(layers_array) && error("layerConfig.layers 不能为空")

        # length 在所有层间共享，从 layers_array[1] 读出（已加空数组保护）
        # 如果提供了 boundary_length，则使用它
        first_length = isempty(boundary_length) ? get(layers_array[1], "length", nothing) : boundary_length
        first_length === nothing && error("layers[1] 缺少 length 字段")

        result_layers = []
        for layer_info in sort(layers_array; by=x -> parse(Int, get(x, "id", "1")))
            layer_id = string(get(layer_info, "id", "1"))
            ts = parse_boundary_data(
                raw_values,
                time_step,
                Dict{String,Any}(
                    "length" => first_length,
                    "step" => layer_info["step"]
                );
                interpolate_type=interpolate_type,
                noise_level=Float64(noise_level),
                boundary_length=isempty(boundary_length) ? nothing : boundary_length,
            )

            push!(result_layers, Dict(
                "layerId" => layer_id,
                "layerName" => "时层$(layer_id)：$(first_length)长度 / $(layer_info["step"])尺度",
                "values" => ts.values,
                "timestamps" => ts.timestamps,
            ))
        end

        return json_success(data=Dict("layers" => result_layers))
    catch e
        return json_error("转换异常: $(sprint(showerror, e))")
    end
end

# ══════════════════════════════════════════════════════════════════════════════
# 2. 边界提交服务  POST /api/boundary/submit
# 将前端计算好的转换后数据写入 TS 库，同时存储 boundary 元信息
# ══════════════════════════════════════════════════════════════════════════════
@post "/api/boundary/submit" function (req)
    try
        body = JSON3.read(req.body, Dict)

        project_id = require_string(body, "projectId")
        db_path = joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")

        boundaries = get(body, "boundaries", [])
        @info "submit received boundaries count=$(length(boundaries))"
        isempty(boundaries) && error("缺少 boundaries 数据")

        # 先按 source_id + remark="planned" 清除该边界的所有旧数据，
        # 避免 meaning 变更后 UNIQUE 约束不匹配导致重复行。
        seen_ids = Set{String}()
        for boundary in boundaries
            bid = optional_string(boundary, "boundaryId", "")
            isempty(bid) && continue
            bid in seen_ids && continue
            push!(seen_ids, bid)
            delete_ts_by_source_id(db_path=db_path, source_id=bid, remark="planned")
        end

        stored_keys = String[]
        for boundary in boundaries
            layer_id = optional_string(boundary, "layerId", "1")
            boundary_id = optional_string(boundary, "boundaryId", "")
            meaning = get(boundary, "meaning", nothing)
            values = get(boundary, "values", [])
            timestamps = get(boundary, "timestamps", [])

            # 保留 lenient：缺 meaning / boundaryId 的 entry 静默跳过
            meaning === nothing && continue
            isempty(boundary_id) && continue

            ts = TimeSeries(convert(Vector{String}, timestamps), convert(Vector{Float64}, values))
            label = "$(boundary_id)|$(meaning)|planned#$(layer_id)"
            set_ts(db_path, label, ts)
            push!(stored_keys, label)
        end

        # 存储 boundary 元信息（长度和尺度）
        # 从 boundaries 中提取第一个 boundary 的元信息（所有 layer 共用）
        if !isempty(boundaries)
            first_boundary = boundaries[1]
            bid = optional_string(first_boundary, "boundaryId", "")
            if !isempty(bid)
                boundary_length = optional_string(first_boundary, "boundaryLength", "")
                boundary_step = optional_string(first_boundary, "boundaryStep", "")
                day_count = get(first_boundary, "dayCount", 0)
                point_count = get(first_boundary, "pointCount", 0)

                if !isempty(boundary_length) && !isempty(boundary_step)
                    save_boundary_config(db_path, bid, boundary_length, boundary_step, day_count, point_count)
                    @info "boundary config saved: bid=$bid length=$boundary_length step=$boundary_step"
                end
            end
        end

        return json_success(
            data=Dict("storedKeys" => stored_keys),
            message="边界数据提交完成，共 $(length(stored_keys)) 条",
        )
    catch e
        return json_error("边界提交异常: $(sprint(showerror, e))")
    end
end

# ══════════════════════════════════════════════════════════════════════════════
# 2.1. 边界加载服务  POST /api/boundary/load
# 根据 boundary 元信息从 TS 库加载已存储的转换后数据
# ══════════════════════════════════════════════════════════════════════════════
@post "/api/boundary/load" function (req)
    try
        body = JSON3.read(req.body, Dict)

        project_id = require_string(body, "projectId")
        db_path = joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")

        boundaries = get(body, "boundaries", [])
        isempty(boundaries) && error("缺少 boundaries 数据")

        loaded_boundaries = []
        all_found = true

        for boundary in boundaries
            layer_id = optional_string(boundary, "layerId", "1")
            meaning = get(boundary, "meaning", nothing)
            boundary_id = optional_string(boundary, "boundaryId", "")

            # 保留 lenient：缺 meaning / boundaryId 的 entry 标 found=false
            if meaning === nothing || isempty(boundary_id)
                push!(loaded_boundaries, Dict("layerId" => layer_id, "found" => false))
                all_found = false
                continue
            end

            ts, _ = query_ts(db_path;
                source_id=boundary_id,
                var_name=meaning,
                remark="planned",
                layer_id=layer_id
            )

            if ts !== nothing
                push!(loaded_boundaries, Dict(
                    "layerId" => layer_id,
                    "found" => true,
                    "values" => ts.values,
                    "timestamps" => ts.timestamps,
                ))
            else
                push!(loaded_boundaries, Dict("layerId" => layer_id, "found" => false))
                all_found = false
            end
        end

        return json_success(
            data=Dict("allFound" => all_found, "boundaries" => loaded_boundaries),
        )
    catch e
        return json_error("边界加载异常: $(sprint(showerror, e))")
    end
end

# ══════════════════════════════════════════════════════════════════════════════
# 2.2. 边界删除服务  POST /api/boundary/delete
# 按 boundaryId（即 TS 库 source_id）删除该边界在 TS 库中的全部层数据
# ══════════════════════════════════════════════════════════════════════════════
@post "/api/boundary/delete" function (req)
    try


        
        body = JSON3.read(req.body, Dict)

        project_id = require_string(body, "projectId")
        db_path = joinpath(BACKEND_DATA_DIR, "projects", project_id, "boundary.db")
        boundary_id = require_string(body, "boundaryId")

        n = delete_ts_by_source_id(; db_path=db_path, source_id=boundary_id)

        return json_success(
            data=Dict("deletedLayers" => n),
            message="边界数据已删除，共 $(n) 层",
        )
    catch e
        return json_error("删除异常: $(sprint(showerror, e))")
    end
end

# # ══════════════════════════════════════════════════════════════════════════════
# # 3. 模型构建服务  POST /api/model/build
# # 构建优化模型(不求解)
# # ══════════════════════════════════════════════════════════════════════════════
# @post "/api/model/build" function (req)
#     try
#         body = JSON3.read(req.body, Dict)

#         component_dicts = get(body, "components", [])
#         algorithms = get(body, "algorithms", Dict())
#         nodes = get(body, "nodes", [])
#         layer = get(body, "layer", nothing)
#         time = get(body, "time", "0:00")

#         if layer === nothing
#             return JSON3.write(Dict(
#                 "success" => false,
#                 "message" => "缺少 layer 配置"
#             ))
#         end

#         # 调用model_service构建模型
#         model = build_model(component_dicts, algorithms, nodes, layer, time)

#         return JSON3.write(Dict(
#             "success" => true,
#             "message" => "模型构建成功",
#             "layerId" => layer["id"],
#             "time" => time,
#             "terminationStatus" => string(JuMP.termination_status(model))
#         ))
#     catch e
#         return JSON3.write(Dict(
#             "success" => false,
#             "message" => "模型构建异常: $(sprint(showerror, e))"
#         ))
#     end
# end

# # ══════════════════════════════════════════════════════════════════════════════
# # 4. 模型求解服务  POST /api/model/solve
# # 求解已构建的优化模型，支持滚动
# # ══════════════════════════════════════════════════════════════════════════════
# @post "/api/model/solve" function (req)
#     try
#         body = JSON3.read(req.body, Dict)

#         component_dicts = get(body, "components", [])
#         layer = get(body, "layer", nothing)
#         time = get(body, "time", "0:00")
#         rolling = get(body, "rolling", false)

#         if layer === nothing
#             return JSON3.write(Dict(
#                 "success" => false,
#                 "message" => "缺少 layer 配置"
#             ))
#         end

#         # 实例化组件
#         components = [instantiate_component(comp) for comp in component_dicts]

#         # 临时构建模型用于求解(演示用，实际应复用已build的model)
#         algorithms = get(body, "algorithms", Dict())
#         nodes = get(body, "nodes", [])
#         model = build_model(component_dicts, algorithms, nodes, layer, time)

#         # 求解
#         @info "开始求解 layer=$(layer["id"]) time=$time"
#         JuMP.optimize!(model)

#         status = JuMP.termination_status(model)
#         if status != MOI.OPTIMAL
#             return JSON3.write(Dict(
#                 "success" => false,
#                 "message" => "求解失败",
#                 "terminationStatus" => string(status)
#             ))
#         end

#         # 持久化结果到时序库
#         for component in components
#             persist_component_results!(model, component, layer, time)
#         end

#         # 如需滚动: 构建后续层模型并求解
#         rolling_results = []
#         if rolling
#             layers = get(body, "layers", nothing)
#             if layers !== nothing
#                 current_time = time
#                 while time_label_less_than(current_time, time_label_add("0:00", layers["1"]["length"]))
#                     for layer_id in generate_layer_ids(layers)
#                         next_layer = layers[layer_id]
#                         if is_time_divisible(current_time, next_layer["forward"])
#                             rolling_model = build_model(component_dicts, algorithms, nodes, next_layer, current_time)
#                             JuMP.optimize!(rolling_model)
#                             if JuMP.termination_status(rolling_model) == MOI.OPTIMAL
#                                 for comp in components
#                                     persist_component_results!(rolling_model, comp, next_layer, current_time)
#                                 end
#                                 push!(rolling_results, Dict(
#                                     "layerId" => layer_id,
#                                     "time" => current_time,
#                                     "status" => "solved"
#                                 ))
#                             end
#                         end
#                         if layer_id == get_max_layer_id(layers)
#                             current_time = time_label_add(current_time, next_layer["forward"])
#                         end
#                     end
#                 end
#             end
#         end

#         return JSON3.write(Dict(
#             "success" => true,
#             "message" => "求解完成",
#             "terminationStatus" => string(status),
#             "objectiveValue" => JuMP.objective_value(model),
#             "rollingResults" => rolling_results,
#             "storedKeys" => list_all_keys()
#         ))
#     catch e
#         return JSON3.write(Dict(
#             "success" => false,
#             "message" => "求解异常: $(sprint(showerror, e))"
#         ))
#     end
# end

# # ══════════════════════════════════════════════════════════════════════════════
# # 5. 数据可视化服务  POST /api/results
# # 查询优化结果用于可视化
# # ══════════════════════════════════════════════════════════════════════════════
# @post "/api/results" function (req)
#     try
#         body = JSON3.read(req.body, Dict)

#         component = get(body, "component", nothing)
#         var_name = get(body, "var_name", nothing)
#         layer_id = get(body, "layer_id", nothing)
#         remark = get(body, "remark", nothing)

#         ts, label = query_ts(
#             component=component,
#             var_name=var_name,
#             layer_id=layer_id,
#             remark=remark
#         )

#         if ts === nothing
#             return JSON3.write(Dict(
#                 "success" => false,
#                 "message" => "未找到匹配的时序数据",
#                 "query" => body
#             ))
#         end

#         return JSON3.write(Dict(
#             "success" => true,
#             "label" => label,
#             "timestamps" => ts.timestamps,
#             "values" => ts.values,
#             "count" => length(ts.values)
#         ))
#     catch e
#         return JSON3.write(Dict(
#             "success" => false,
#             "message" => "查询异常: $(sprint(showerror, e))"
#         ))
#     end
# end

# # ══════════════════════════════════════════════════════════════════════════════
# # 辅助路由
# # ══════════════════════════════════════════════════════════════════════════════
@get "/health" function (req)
    return JSON3.write(Dict(
        "status" => "ok",
        "service" => "synerroll-backend354646",
        "timestamp" => Dates.now()
    ))
end

# @get "/api/keys" function (req)
#     return JSON3.write(Dict(
#         "success" => true,
#         "keys" => list_all_keys()
#     ))
# end

# @post "/api/cache/clear" function (req)
#     clear_cache()
#     return JSON3.write(Dict(
#         "success" => true,
#         "message" => "时序缓存已清空"
#     ))
# end

# ══════════════════════════════════════════════════════════════════════════════
# 启动服务
# ══════════════════════════════════════════════════════════════════════════════

println("╔═══════════════════════════════════════════╗")
println("║   SynerRoll Backend - 统一服务入口         ║")
println("╠═══════════════════════════════════════════╣")
println("║  1. POST /api/parse     - 解析服务         ║")
println("║  2. POST /api/boundary  - 边界录入        ║")
println("║  3. POST /api/model/build - 模型构建       ║")
println("║  4. POST /api/model/solve - 模型求解      ║")
println("║  5. POST /api/results   - 数据可视化       ║")
println("╚═══════════════════════════════════════════╝")
println("Starting on port $PORT...")

# 启动恢复：把上次运行中"中断"的 solving 任务改为 paused
init_task_routes!()
init_ingest_routes!()

serve(host="0.0.0.0", port=PORT, async=false, middleware=[CorsMiddleware])