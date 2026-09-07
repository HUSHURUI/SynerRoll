using Oxygen
using JSON3
using HTTP
using Dates
using JuMP
using CSV
using DataFrames
using SHA

begin
    # 解析服务（画布 JSON → component/connection/mapping JSON）
    include("services/parse_service.jl")

    # 核心模块
    include("core/types.jl")
    include("core/component_framework.jl")
    include("core/schema.jl")
    include("core/validation.jl")

    # 工具模块
    include("utils/timestr_utils.jl")
    include("utils/timeseries_utils.jl")
    include("utils/layer_utils.jl")
    include("utils/model_utils.jl")
    include("utils/prediction_utils.jl")
    include("utils/server_utils.jl")

    # 服务模块（需在utils和components之前加载，prediction_utils.jl依赖TimeSeries）
    include("services/boundary_service.jl")

    # 组件模块
    include("components/wind_turbine/component.jl")
    include("components/photovoltaic/component.jl")
    include("components/coal_power/component.jl")
    include("components/electricity_load/component.jl")
    include("components/electricity_storage/component.jl")
    include("components/hydrogen_storage/component.jl")
    include("components/flywheel_storage/component.jl")

    include("services/model_service.jl")

    # 计算任务模块（计算任务方案：阶段 1-4）
    include("services/task_manager.jl")
    include("services/simulation_runner.jl")
    include("routes/task.jl")
    include("routes/ingest.jl")
end

task_id="e5a6c041-5022-4fa3-82f6-1e8459c4d169"
task=get_task(task_id)
# ■ 接口逻辑：初始化任务上下文
ctx = get_or_create_context(
    task_id,
    task["mode"],
    get(task, "sim_end_time", nothing),
    joinpath(TASKS_DATA_ROOT, task_id, "timeseries.db")
)
store_path = ctx.store_path
mode = ctx.mode
sim_end = ctx.sim_end_time
task_dir = dirname(store_path)
layer_id = task["layer_id"]
step_min = get_layer_step_minutes(layer_id)
mkpath(task_dir)

# ════════════════════════════════════════════
# ■ 接口逻辑：阶段 1 — PARSE
# ════════════════════════════════════════════
update_task_status!(task_id, TASK_PARSING)
broadcast_event(ctx, Dict("type" => "status", "status" => TASK_PARSING, "taskId" => task_id))

project_json_path = joinpath(task_dir, "project.json")
if !isfile(project_json_path)
    msg = "project.json 不存在于任务目录: $task_dir"
    update_task_status!(task_id, TASK_FAILED, error_message=msg)
    broadcast_event(ctx, Dict("type" => "failed", "error" => msg, "taskId" => task_id))
    remove_context(task_id)
    return
end

project_json = JSON3.read(read(project_json_path, String), Dict)
parse_result = parse_project(project_json; output_dir=task_dir)
if !parse_result.success
    msg = "parse 失败: $(parse_result.message)"
    update_task_status!(task_id, TASK_FAILED, error_message=msg)
    broadcast_event(ctx, Dict("type" => "failed", "error" => msg, "taskId" => task_id))
    remove_context(task_id)
    return
end
@info "task $task_id: parse 完成 — $(parse_result.componentCount) 组件, $(parse_result.connectionCount) 连接"

# ■ 接口逻辑：读 parse 产物
component_path = joinpath(task_dir, "component.json")
connection_path = joinpath(task_dir, "connection.json")

components = JSON3.read(read(component_path, String), Vector{Dict{String,Any}})
nodes = JSON3.read(read(connection_path, String), Vector{Dict{String,Any}})
layers = project_json["layerConfig"]["layers"]
algorithms = project_json["algorithm"]

# ════════════════════════════════════════════
# ■ 接口逻辑：阶段 2 — BUILD 准备
# ════════════════════════════════════════════
update_task_status!(task_id, TASK_BUILDING)
broadcast_event(ctx, Dict("type" => "status", "status" => TASK_BUILDING, "taskId" => task_id))

# ════════════════════════════════════════════
# ■ 接口逻辑：阶段 3 — 边界注入
# ════════════════════════════════════════════
try
    n = seed_task_boundary_data(task_id, task["project_id"], layer_id)
    @info "task $task_id: seeded $n boundary series"
catch e
    msg = "boundary seed failed: $(sprint(showerror, e))"
    update_task_status!(task_id, TASK_FAILED, error_message=msg)
    broadcast_event(ctx, Dict("type" => "failed", "error" => msg, "taskId" => task_id))
    remove_context(task_id)
    return
end

# ════════════════════════════════════════════
# ■ 接口逻辑：阶段 4 — 进入 SOLVING
# ════════════════════════════════════════════
update_task_status!(task_id, TASK_SOLVING)
broadcast_event(ctx, Dict("type" => "status", "status" => TASK_SOLVING, "taskId" => task_id))

# ■ 接口逻辑：确定起始时间 ？？？没懂
sim_time = get(task, "cur_time", nothing)
if sim_time === nothing
    sim_time = task["sim_start_time"]
end

solved_steps = 0

# ★═══════════════════════════════════════════════════════════
# ★  [数学业务] 求解主循环 —— 你主要在这里工作
# ★
# ★  你可以修改的部分：
# ★    - 求解步的构建逻辑（多层、多时刻、滚动策略）
# ★    - layer / time 的选择策略（当前是固定单层 + 固定步长推进）
# ★    - 每步求解前后的预处理/后处理
# ★
# ★  你不需要动的部分：
# ★    - signal 检查（pause/cancel）
# ★    - 在线模式的 real_time 对齐
# ★    - WS 推送 / 状态更新 / task 元数据更新
# ★═══════════════════════════════════════════════════════════
# while true

# ■ 接口逻辑：检查 cancel 信号
if isready(ctx.signal_ch)
    sig = take!(ctx.signal_ch)
    if sig == SIGNAL_CANCEL
        update_task_status!(task_id, TASK_CANCELLED, current_time=sim_time)
        broadcast_event(ctx, Dict("type" => "cancelled", "currentTime" => sim_time, "taskId" => task_id))
        remove_context(task_id)
        return
    end
end

# ■ 接口逻辑：在线模式等真实物理时间 ？？？没懂
if mode == "online"
    now_min = time_label_to_minutes(
        minutes_to_time_label(floor(Int, time_label_to_minutes("0:00") +
                                         (time() - floor(time() / 86400) * 86400) / 60)) #差8个小时
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
            if isready(ctx.signal_ch)
                sig = take!(ctx.signal_ch)
                if sig == SIGNAL_CANCEL
                    update_task_status!(task_id, TASK_CANCELLED, current_time=sim_time)
                    broadcast_event(ctx, Dict("type" => "cancelled", "currentTime" => sim_time, "taskId" => task_id))
                    remove_context(task_id)
                    return
                end
            end
        end
    end
end

# ■ 接口逻辑：检查是否到 sim_end
if sim_end !== nothing
    if time_label_to_minutes(sim_time) >= time_label_to_minutes(sim_end)
        break
    end
end

# ★  [数学业务] 求解当前步
step_start = time()

# 构建模型 + 求解
# ？？？？？？layers[1]这种需要做成utils
const _COMPONENT_LIB_PATH = joinpath(@__DIR__, "..", "config", "component-library.json")
if isfile(_COMPONENT_LIB_PATH)
    load_component_library(_COMPONENT_LIB_PATH)
end
model, built_components = build_model(components, algorithms, nodes, layers[1], sim_time, store_path)
result = solve_model(model, built_components, layers[1], sim_time, store_path)

# ★ [数学业务] 求解结果检查
if result === nothing
    msg = "求解失败: layer=$(layer["id"]) time=$sim_time status=$(JuMP.termination_status(model))"
    update_task_status!(task_id, TASK_FAILED, error_message=msg)
    broadcast_event(ctx, Dict("type" => "failed", "error" => msg, "taskId" => task_id))
    remove_context(task_id)
    return
end
# ★═══════════════════════════════════════════════════════
# ★  [数学业务] 求解当前步 — 结束
# ★═══════════════════════════════════════════════════════

step_elapsed = round(time() - step_start; digits=2)

# ■ 接口逻辑：推 WS data 事件给前端
rows_payload = _read_step_results(store_path, layer_id, sim_time)
broadcast_event(ctx, Dict(
    "type" => "data",
    "taskId" => task_id,
    "currentTime" => sim_time,
    "elapsed" => step_elapsed,
    "rows" => rows_payload
))

# ■ 接口逻辑：更新 task 元数据
update_task_current_time!(task_id, sim_time)
solved_steps += 1
@info "task $task_id: step $solved_steps solved — layer=$(layer["id"]) time=$sim_time ($(step_elapsed)s)"

# ★ [数学业务] 推进 sim_time（当前是固定步长，你可以改为自定义策略）
cur_min = time_label_to_minutes(sim_time)
new_min = mod(cur_min + step_min, 24 * 60)
sim_time = minutes_to_time_label(new_min)
# end
# ★═══════════════════════════════════════════════════════════
# ★  [数学业务] 求解主循环 — 结束
# ★═══════════════════════════════════════════════════════════

# ════════════════════════════════════════════
# ■ 接口逻辑：阶段 5 — 完成
# ════════════════════════════════════════════
update_task_status!(task_id, TASK_COMPLETED, current_time=sim_time)
broadcast_event(ctx, Dict("type" => "completed", "taskId" => task_id, "finalTime" => sim_time, "solvedSteps" => solved_steps))
remove_context(task_id)