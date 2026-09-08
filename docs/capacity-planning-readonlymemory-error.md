# 容量规划黑箱迭代 `ReadOnlyMemoryError` 问题记录

> 状态：已修复并验证  
> 记录日期：2026-09-08  
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
- 行号：第 175 行（`catch error` 块内的 `@warn`）

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

## 3. 根因：黑箱迭代喘息时间不足

`ReadOnlyMemoryError()` 在 Julia 中通常表示**尝试写入只读内存**或访问了已经被释放/移动的内存区域。

在容量规划场景下，每次黑箱迭代都会经历：

1. 构建新的 JuMP/COPT 模型（`build_model_tracked`）；
2. 求解（`JuMP.optimize!` → COPT 后端）；
3. 将结果写入 `timeseries.db`；
4. 返回 fitness。

COPT 后端会分配 license、环境句柄和内部内存。当迭代节奏非常快时，Julia 的垃圾回收器（GC）来不及释放上一轮迭代残留的 C 对象，下一轮迭代又立即创建新的 COPT 环境。此时可能出现：

- C 指针指向的内存已被 GC 回收或移动；
- COPT 内部的内存映射区域在访问时处于只读/无效状态；
- 最终导致 `ReadOnlyMemoryError`。

这与 Julia 社区中类似案例一致：在频繁调用外部 C 库（如 COPT、Python C API）时，**周期性 `GC.gc()` + 小 sleep** 是常见的缓解手段。

参考：

- [Julia Discourse: ReadOnlyMemoryError](https://discourse.julialang.org/t/readonlymemoryerror/8548)
- [pyjulia #305: Ctypes ReadOnlyMemoryError](https://github.com/JuliaPy/pyjulia/issues/305)
- [Julia Manual: ReadOnlyMemoryError](https://www.jlhub.com/julia/manual/en/function/ReadOnlyMemoryError)

---

## 4. 解决思路

解决思路分三层：

1. **先定位**：让报错自带完整堆栈，确认是否确实来自 COPT 求解阶段；
2. **再释放**：每个场景求解完成后，主动断开对 JuMP/COPT 模型和组件的引用，并触发一次增量 GC；
3. **最后喘息**：在黑箱优化的每次迭代之间加入 `GC.gc(false)` 和 `sleep`，让上一轮的资源有足够时间被回收。

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

### 5.2 每场景求解后立即释放资源

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
- 调用增量 GC `GC.gc(false)`，尽快回收 COPT 后端内存；
- 避免五个场景连续求解时内存压力累积。

### 5.3 每次黑箱迭代之间加入喘息时间

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

### 5.4 运行日志展示优化（顺带改进）

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

`sleep(0.2)` 是一个经验值。后续可以根据实际运行稳定性调整：

| 场景 | 建议 sleep | 说明 |
|---|---|---|
| 评价次数少、模型小 | `sleep(0.05)` | 几乎不影响总耗时 |
| 评价次数多、模型大 | `sleep(0.2 ~ 0.5)` | 用少量时间换稳定性 |
| 仍然偶发报错 | 配合 `GC.gc()`（完整回收）而不是 `GC.gc(false)` | 单次停顿稍长，但回收更彻底 |

也可以把 sleep 做成优化器配置项，让用户在 UI 上调整。

---

## 7. 如果问题复发

如果后续仍出现 `ReadOnlyMemoryError`，可以按以下顺序继续排查：

1. **看新日志的完整堆栈**：确认异常是否仍然来自 `solve_model` / COPT；
2. **检查 COPT 授权与版本**：过期或版本不匹配时，COPT 的错误消息接口可能返回空指针，恰好表现为 `ReadOnlyMemoryError`；
3. **关闭场景 DB 的 WAL 模式**：这些 `timeseries.db` 是单写单读、寿命很短的库，WAL 模式会创建 `.db-wal` / `.db-shm` 共享内存文件，某些 Windows 环境下可能不稳定（[SQLite WAL 锁定行为](https://hynek.me/til/sqlite-read-only-wal-locked/)）；
4. **降低规模验证**：把 `maxFuncEvals` 和 `populationSize` 调小，确认问题是否与迭代次数/种群规模正相关。

---

## 8. 结论

- **根因**：黑箱优化迭代节奏过快，COPT/JuMP 模型创建与销毁之间的 GC 喘息时间不足，导致底层只读内存访问异常。
- **解决方案**：
  1. 详细化错误日志（带堆栈）；
  2. 每场景求解后主动释放模型引用并触发增量 GC；
  3. 每次黑箱迭代前加入 `GC.gc(false)` + `sleep`。
- **验证**：用户反馈该方案有效，`ReadOnlyMemoryError` 不再反复出现。

---

**相关文件**：

- `backend/services/capacity_planning/simulation_evaluator.jl`
- `backend/services/capacity_planning/optimization_runner.jl`
- `app/pages/capacity-planning/[projectId].vue`
