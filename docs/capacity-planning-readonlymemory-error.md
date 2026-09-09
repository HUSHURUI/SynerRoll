# 容量规划黑箱迭代 `ReadOnlyMemoryError` 问题记录

> 状态：已修复并验证（第三版：任务级 COPT 环境复用 + 任务结束强制释放）  
> 记录日期：2026-09-08（根因修正：2026-09-09）  
> 涉及模块：容量规划第五步（黑箱优化循环）

---

## 1. 现象

在容量规划第五步运行黑箱优化时，后端日志反复出现如下报错：

```
Warning: 容量规划场景评价失败
  scenario_id = ...
  weight_days = ...
  exception = ReadOnlyMemoryError()
```

报错被捕获的位置：

- 文件：`backend/services/capacity_planning/simulation_evaluator.jl`
- 行号：第 178 行（`catch error` 块内的 `@warn`）

后续定位到更直接的崩溃点：

```
ReadOnlyMemoryError()
Stacktrace:
  [1] COPT_CreateEnv
    @ D:\julia\packages\COPT\RvuIW\src\gen8.0.6\libcopt.jl:34 [inlined]
  [2] Env
    @ D:\julia\packages\COPT\RvuIW\src\MOI\MOI_wrapper.jl:142 [inlined]
  [3] COPT.Optimizer(env::Nothing)
    @ COPT ...
  ...
  [11] create_jump_model
    @ backend/utils/model_utils.jl:11
```

再后续发现规律：**重启 `server.jl` 后第一次容量规划任务一定成功；同一进程内第二次启动容量规划（无论新建任务还是在现有任务上重跑）必然在 `COPT.Env()` 处 `ReadOnlyMemoryError`**。

---

## 2. 初步判断：不是文件数量过多

用户最初的猜测是：

> “迭代 200 次 × 每次 5 个场景 = 1000 个 `timeseries.db` 和 `model.jl`，会不会是这些数据库读写操作导致的报错？”

但查看 `work_dir` / `scenario_dir` 的生命周期后可以排除这一点：

```
optimization_runner.jl
    └─ work/<candidate_hash[:16]>/
        └─ scenarios/<scenario_id>/
            ├─ timeseries.db
            └─ model.jl
```

- 每个候选容量对应一个 `work_dir`；
- 每个场景在对应 `work_dir` 下生成独立的 `scenario_dir`；
- `simulation_evaluator.jl` 求解完每个场景后会调用 `close_store(db_path)` 关闭时序库；
- `optimization_runner.jl` 在 `fitness()` 返回前会删除**非最优**候选的整棵 `work_dir`。

因此，磁盘上不会真的积累 1000 个场景目录。同一时刻通常只存在：

- 当前正在评价的 `work_dir`；
- 当前最优解保留的 `work_dir`。

---

## 3. 根因：任务级 COPT 环境没有释放，导致下一次任务无法创建新环境

### 3.1 第一版缓解措施后仍偶发

第一版修复在 `fitness()` 开头加入 `GC.gc(false)` + `sleep(0.2)`，并在每个场景求解后释放模型引用、触发 GC。用户反馈大部分时间有效，但大量迭代后仍偶发。

### 3.2 完整堆栈定位到 `COPT_CreateEnv`

在 `catch` 块记录完整堆栈后，最新报错栈指向 `COPT_CreateEnv`：

```
ReadOnlyMemoryError()
Stacktrace:
  [1] COPT_CreateEnv
    @ D:\julia\packages\COPT\RvuIW\src\gen8.0.6\libcopt.jl:34 [inlined]
  [2] Env
    @ D:\julia\packages\COPT\RvuIW\src\MOI\MOI_wrapper.jl:142 [inlined]
  [3] (::var"#run_capacity_optimization!##11#run_capacity_optimization!##12"{String, PlanningContext})()
    @ Main d:\SynerRoll-main\SynerRoll-main\backend\services\capacity_planning\optimization_runner.jl:140
  ...
```

### 3.3 最终规律：第一次成功，第二次失败

用户进一步发现：

- 启动 `server.jl` 后**第一次**运行容量规划任务，全程正常；
- 在现有任务基础上再次点击启动，或新建一个容量规划任务，**同一进程内第二次**必然在 `COPT.Env()` 处 `ReadOnlyMemoryError`。

这说明问题的本质是**上一次容量规划任务结束后，COPT 环境（`COPT.Env`）没有被及时、彻底地释放**，导致下一次任务创建新环境时，COPT 底层状态已经损坏或资源已被占满，从而 `COPT_CreateEnv` 访问到无效/只读内存。

### 3.4 为什么之前会误判为“高频创建环境”

最初代码每次构建 JuMP 模型都会调用 `Model(COPT.Optimizer)`，其内部创建新的 `COPT.Env()`。一次任务可能创建数百到数千个 Env，确实会加剧问题。但即使把 Env 改为任务级复用（一次任务只创建一个 Env），如果任务结束后不释放，第二次任务依然会失败。因此**根因是“Env 生命周期未正确管理”，而不是“创建次数多”本身**。

---

## 4. 解决思路

解决思路分四层：

1. **先定位**：让报错自带完整堆栈，确认崩溃点确实来自 COPT 环境创建；
2. **任务内复用**：一次容量规划任务只创建一个 `COPT.Env`，所有候选/场景共享；
3. **任务结束强制释放**：在 `run_capacity_optimization!` 的 `finally` 中显式 `finalize(copt_env)`、触发完整 GC、并等待 COPT 底层释放完成；
4. **保持喘息**：保留 `fitness()` 开头的 `GC.gc(false)` 与 `sleep`，降低单次任务内的 GC 压力。

---

## 5. 具体改动

### 5.1 更详细的错误定位日志

文件：`backend/services/capacity_planning/simulation_evaluator.jl`

把原来的：

```julia
catch error
    @warn "容量规划报错：" error
    ...
end
```

改成：

```julia
catch error
    bt = catch_backtrace()
    @warn "容量规划场景评价失败" scenario_id weight_days exception=(error, bt)
    push!(scenario_metrics, Dict{String,Any}(
        "scenarioId" => scenario_id,
        "weightDays" => weight_days,
        "feasible" => false,
        "error" => sprint(showerror, error),
        "backtrace" => sprint(show, bt),
    ))
    options.stop_on_infeasible && return _evaluation_failure(error; scenario_metrics)
end
```

效果：

- 日志不再只显示 `ReadOnlyMemoryError()`；
- 会附带完整调用栈，帮助确认异常具体来自 `_seed_evaluation_scenario!`、`build_model_tracked` 还是 `solve_model`。

### 5.2 create_jump_model 支持复用优化器工厂

文件：`backend/utils/model_utils.jl`

```julia
function create_jump_model(algorithms::Dict{String, Any}; optimizer_factory=nothing)
    model = if optimizer_factory === nothing
        Model(COPT.Optimizer)
    else
        Model(optimizer_factory)
    end
    set_silent(model)
    return model
end
```

效果：

- 默认行为不变，仍使用 `Model(COPT.Optimizer)`；
- 调用方可传入 `optimizer_factory = () -> COPT.Optimizer(env)`，从而复用已存在的 `COPT.Env`。

### 5.3 build_model_tracked 透传 optimizer_factory

文件：`backend/services/model_service.jl`

```julia
function build_model_tracked(component_dicts::Vector, algorithms::Dict{String,Any}, nodes::Vector,
    layer::Dict{String,Any}, time::String, db_path::String;
    all_layers::Union{Dict{String,Any},Nothing}=nothing, optimizer_factory=nothing)
    ...
    model = create_jump_model(algorithms; optimizer_factory=optimizer_factory)
    ...
end
```

### 5.4 evaluate_snapshot 接收并透传 optimizer_factory

文件：`backend/services/capacity_planning/simulation_evaluator.jl`

```julia
function evaluate_snapshot(
    project_snapshot::AbstractDict,
    canvas_id::String,
    scenario_set::AbstractDict,
    work_dir::String;
    options::EvaluationOptions=EvaluationOptions(),
    planning_id::Union{Nothing,String}=nothing,
    optimizer_factory=nothing,
)::EvaluationResult
    ...
    model, components, generated_code = build_model_tracked(
        component_dicts, algorithms, nodes, layer, "0:00", db_path; all_layers,
        optimizer_factory=optimizer_factory,
    )
    ...
end
```

### 5.5 优化循环只创建一个 COPT.Env，并在任务结束后强制释放

文件：`backend/services/capacity_planning/optimization_runner.jl`

在 `run_capacity_optimization!` 中，将优化主体用 `try/finally` 包裹：

```julia
using COPT

# ...

# 任务级 COPT 环境：整个优化循环复用同一个 Env；任务结束后在 finally 中强制释放，
# 避免残留句柄/内存影响下一次任务，否则第二次运行易出现 COPT_CreateEnv ReadOnlyMemoryError。
copt_env = nothing
optimizer_factory = nothing
try
    copt_env = COPT.Env()
    optimizer_factory = () -> COPT.Optimizer(copt_env)

    set_planning_status!(planning_id, "optimizing")
    # ... 原有优化逻辑 ...

    return result
finally
    # 任务结束后强制释放 COPT 环境，避免残留句柄/内存影响下一次任务
    optimizer_factory = nothing
    if copt_env !== nothing
        try
            finalize(copt_env)
        catch e
            @warn "释放 COPT 环境失败" exception=e
        end
        copt_env = nothing
    end
    GC.gc(true)
    sleep(0.5)
end
```

在调用 `evaluate_snapshot` 时传入：

```julia
simulation = evaluate_snapshot(
    candidate_snapshot,
    task["canvasId"],
    scenario_set,
    work_dir;
    options=EvaluationOptions(layer_id=string(config["planningLayerId"])),
    planning_id=planning_id,
    optimizer_factory=optimizer_factory,
)
```

效果：

- 一次规划任务只创建一次 `COPT.Env`；
- 所有候选、所有场景的 JuMP/COPT 模型都复用该环境；
- 任务结束后，显式 `finalize` + 完整 GC + `sleep(0.5)` 确保 COPT 底层环境被彻底释放；
- 下一次容量规划任务启动时，COPT 处于干净状态，可以正常创建新环境。

### 5.6 每场景求解后立即释放资源

文件：`backend/services/capacity_planning/simulation_evaluator.jl`

在成功求解并提取目标值后：

```julia
solve_result === nothing && throw(CapacityPlanningError("INFEASIBLE", "$(scenario_id) 求解未达到最优"))
objective, _ = solve_result

# 求解完成后立即释放本轮 JuMP/COPT 模型与组件，降低连续多场景评价的内存/GC 压力
model = nothing
components = nothing
GC.gc(false)

isfinite(objective) || throw(CapacityPlanningError("NON_FINITE_OBJECTIVE", "$(scenario_id) 返回非有限目标值"))
```

效果：

- 显式断开 `model` 和 `components` 引用；
- 调用增量 GC `GC.gc(false)`，尽快回收每轮求解的临时对象；
- 与共享 COPT 环境配合，避免多场景连续求解时内存压力累积。

### 5.7 每次黑箱迭代之间加入喘息时间

文件：`backend/services/capacity_planning/optimization_runner.jl`

在 `fitness()` 函数开头：

```julia
function fitness(raw_values)
    _planning_cancelled(ctx) && throw(PlanningCancelled("规划任务已取消"))

    # 主动回收上一轮迭代残留的 JuMP/COPT 资源，缓解长循环中的内存/GC 压力
    GC.gc(false)
    sleep(0.2)

    values = _quantize_candidate(raw_values, variables)
    ...
end
```

效果：

- 每个候选方案评价前，先回收上一轮残留资源；
- `sleep(0.2)` 给 COPT 后端和操作系统留出释放句柄的时间窗口；
- 以 200 次迭代为例，额外耗时约 40 秒，但能显著降低 `ReadOnlyMemoryError` 出现概率。

### 5.8 运行日志展示优化（顺带改进）

文件：`app/pages/capacity-planning/[projectId].vue`

在修复内存问题的同时，顺手把步骤五左侧的运行日志改成**循环日志 + 限高**：

```typescript
const MAX_PLANNING_LOG_ENTRIES = 30

const appendPlanningLog = (item: Omit<PlanningLogItem, 'time'>) => {
  if (planningLogIds.has(item.id)) return
  planningLogIds.add(item.id)
  planningLogFeed.value.push({ ...item, time: planningLogTime() })
  if (planningLogFeed.value.length > MAX_PLANNING_LOG_ENTRIES) {
    planningLogFeed.value.splice(0, planningLogFeed.value.length - MAX_PLANNING_LOG_ENTRIES)
  }
  void nextTick(() => {
    if (planningLogRef.value) planningLogRef.value.scrollTop = planningLogRef.value.scrollHeight
  })
}
```

容器增加最大高度：

```vue
<div class="flex min-h-0 max-h-[480px] flex-1 flex-col overflow-hidden rounded-lg border border-app-border bg-white">
```

效果：

- 日志条目上限从 80 条降到 30 条；
- 日志区域最大高度 480px，不会随右侧图表无限拉长。

---

## 6. 参数调优建议

`sleep(0.2)`（迭代间）和 `sleep(0.5)`（任务结束释放）都是经验值。后续可以根据实际运行稳定性调整：

| 场景 | 建议 sleep | 说明 |
|---|---|---|
| 评价次数少、模型小 | `sleep(0.05)` / 任务结束 `0.2` | 几乎不影响总耗时 |
| 评价次数多、模型大 | `sleep(0.2 ~ 0.5)` / 任务结束 `0.5 ~ 1.0` | 用少量时间换稳定性 |
| 仍然偶发报错 | 配合 `GC.gc()`（完整回收）而不是 `GC.gc(false)` | 单次停顿稍长，但回收更彻底 |

也可以把 sleep 做成优化器配置项，让用户在 UI 上调整。

---

## 7. 如果问题复发

如果后续仍出现 `ReadOnlyMemoryError`，可以按以下顺序继续排查：

1. **看新日志的完整堆栈**：确认异常是否仍然来自 `COPT_CreateEnv`；
2. **检查 COPT 授权与版本**：过期或版本不匹配时，COPT 的错误消息接口可能返回空指针，恰好表现为 `ReadOnlyMemoryError`；
3. **确认 `finalize` 是否真的释放了环境**：在 `finally` 块前后打印 `copt_env.ptr`，确认释放前后指针从非空变为 `C_NULL`；
4. **关闭场景 DB 的 WAL 模式**：这些 `timeseries.db` 是单写单读、寿命很短的库，WAL 模式会创建 `.db-wal` / `.db-shm` 共享内存文件，某些 Windows 环境下可能不稳定（[SQLite WAL 锁定行为](https://hynek.me/til/sqlite-read-only-wal-locked/)）；
5. **降低规模验证**：把 `maxFuncEvals` 和 `populationSize` 调小，确认问题是否与迭代次数/种群规模正相关。

---

## 8. 结论

- **根因**：容量规划任务结束后，`COPT.Env` 没有被及时、彻底地释放。Julia 的垃圾回收是惰性的，如果依赖它自动回收，上一次任务的 COPT 环境可能仍然存活；当同一进程内启动第二次容量规划任务并调用 `COPT.Env()` 时，底层 `COPT_CreateEnv` 访问到已被占用或损坏的内存区域，抛出 `ReadOnlyMemoryError`。
- **解决方案**：
  1. 详细化错误日志（带堆栈），用于定位真实崩溃点；
  2. 一次任务只创建一个 `COPT.Env`，通过 `optimizer_factory` 注入到每次模型构建中；
  3. 任务结束时的 `finally` 块中显式 `finalize(copt_env)`、触发完整 GC、并 `sleep(0.5)`；
  4. 每场景求解后主动释放模型引用并触发增量 GC；
  5. 每次黑箱迭代前加入 `GC.gc(false)` + `sleep`。
- **验证预期**：重启 `server.jl` 后，第一次容量规划任务正常；任务结束后 COPT 环境被释放，第二次任务也能正常创建环境并运行。

---

**相关文件**：

- `backend/utils/model_utils.jl`
- `backend/services/model_service.jl`
- `backend/services/capacity_planning/simulation_evaluator.jl`
- `backend/services/capacity_planning/optimization_runner.jl`
- `app/pages/capacity-planning/[projectId].vue`
