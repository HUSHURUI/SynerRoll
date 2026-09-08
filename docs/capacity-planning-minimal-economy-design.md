# 容量规划最小版本经济性设计约定

> 状态：设计约定  
> 创建日期：2026-09-08  
> 适用范围：容量规划第五步（黑箱优化循环）的最小可运行版本  
> 约定有效期：在明确通知变更前，所有后续需求讨论均以此文档为准

---

## 1. 业务意图复述

容量规划第五步的黑箱优化，每次迭代需要完成：

1. 根据候选容量（`candidate`）修改项目快照，得到临时项目配置；
2. 对用户选定的每个典型场景，独立求解一个 24h 的 JuMP/COPT 模型；
3. 每个场景的求解结果写入独立的 `timeseries.db`；
4. 基于 `timeseries.db` 计算该场景的**运行成本**（operating cost）；
5. 用场景 `weightDays`（天数权重）对运行成本做加权平均/求和；
6. 将加权后的总运行成本作为本次迭代的适应度值（fitness）返回给优化器；
7. 优化器重复上述过程，直到达到评估预算或收敛。

本次约定把目标严格收缩到**“运行成本 + 天数加权”**，其它经济性指标全部后移。

---

## 2. 本次约定的范围边界

### 2.1 包含在本次最小版本内

- 运行成本从 `timeseries.db` 中后验计算；
- 多典型场景按 `weightDays` 加权求和；
- 黑箱优化以加权运行成本作为唯一适应度值；
- 求解生成的 `model.jl` 和 `timeseries.db` 持久化到候选子目录，便于调试。

### 2.2 明确排除在本次最小版本外

| 排除项 | 说明 |
|---|---|
| 投资成本（CAPEX） | 设备初始投资、替换成本、生命周期折旧均不参与 fitness |
| NPV / IRR / LCOE / 投资回收期 | 仅在前端展示占位或隐藏，不参与优化计算 |
| 多目标优化 | 只有一个目标：加权运行成本最小 |
| 技术性约束作为优化约束 | 技术约束仅在第五步前端展示/配置，优化器本轮不强制；求解可行性由 JuMP 模型本身保证 |
| 复杂的 annualized / 年化换算 | 运行成本直接按典型日天数外推到年，不做额外贴现 |
| 场景概率 vs 天数 | 本轮只使用 `weightDays` 做加权（与 `probability` 等价处理） |

---

## 3. 涉及代码位置

### 3.1 前端

| 文件 | 作用 | 相关代码 |
|---|---|---|
| `app/pages/capacity-planning/[projectId].vue` | 容量规划 6 步向导主页面 | `createAndStartPlanning()` 在步骤 5 创建并启动规划任务（约 1408 行）；`applyAndSimulate()` 在步骤 6 调用 `/capacity-planning/{id}/apply-and-simulate`（约 1479 行） |
| `types/capacity-planning.ts` | 容量规划相关类型定义 | 优化变量、聚类配置、优化器配置、经济性配置等结构 |

### 3.2 后端：容量规划服务

| 文件 | 作用 | 相关代码 |
|---|---|---|
| `backend/services/capacity_planning/types.jl` | 内部数据结构 | `EvaluationOptions`（10-15 行）、`EvaluationResult`（16-23 行）、`EconomicEvaluationInput`（27-32 行）、`EconomicEvaluationResult`（34-40 行） |
| `backend/services/capacity_planning/optimization_runner.jl` | 黑箱优化主循环 | `run_capacity_optimization!()`（102-354 行）；核心 `fitness()` 函数（158-273 行） |
| `backend/services/capacity_planning/simulation_evaluator.jl` | 典型场景逐场景仿真 | `evaluate_snapshot()`（109-204 行）；场景循环、生成 `model.jl` 与 `timeseries.db`、按 `weightDays` 加权（139-189 行） |
| `backend/services/capacity_planning/economic_evaluator.jl` | 经济性评价接口 | `OperatingObjectiveEvaluator` 与 `evaluate_economics()`（1-45 行） |
| `backend/services/capacity_planning/candidate_snapshot.jl` | 容量候选应用到项目快照 | `apply_capacity_candidate()`（被 `optimization_runner.jl` 调用） |
| `backend/services/capacity_planning/scenario_reducer.jl` | 边界数据聚类 | `reduce_boundary_scenarios()` 输出带 `weightDays` 的典型场景 |

### 3.3 后端：仿真与经济计算复用模块

| 文件 | 作用 | 相关代码 |
|---|---|---|
| `backend/services/model_service.jl` | JuMP 模型生成与求解 | `build_model_tracked()` 生成可执行 `model.jl`；`solve_model()` 调用 COPT 并写入 `timeseries.db` |
| `backend/services/economy_evaluation_service.jl` | 从 `timeseries.db` 计算运行成本 | `load_component_data()`（169-207 行）；`build_layer_summary()`（337-380 行）；`evaluate_task_economy()`（387-513 行） |
| `backend/utils/economy_calculator.jl` | 纯数值成本计算 | `CostItem` 结构体；`calc_component_cost()` 等按设备类型计算运维、启停、弃风弃光、购电售电、松弛惩罚等 |
| `backend/utils/timeseries_utils.jl` | SQLite 时序库 | `SQLiteTimeSeriesStore`、`get_ts()`、`set_ts()`、`get_store()` 等 |

---

## 4. 当前代码状态评估

### 4.1 已经具备的环节

1. **候选容量生成与应用**
   - `optimization_runner.jl:_quantize_candidate()` 与 `_candidate_payload()` 把优化器原始向量转成设备容量；
   - `candidate_snapshot.jl:apply_capacity_candidate()` 把容量写回项目快照副本。

2. **典型场景生成**
   - `scenario_reducer.jl:reduce_boundary_scenarios()` 输出带 `weightDays` 的场景；
   - 场景集以 JSON 形式保存在规划任务目录下。

3. **逐场景 JuMP 求解与 `timeseries.db` 生成**
   - `simulation_evaluator.jl:evaluate_snapshot()` 循环每个场景；
   - 每个场景在 `work/<candidate_hash>/scenarios/<scenario_id>/timeseries.db` 中独立落库；
   - 同时生成 `model.jl`（当 `options.generate_code=true`）。

4. **天数加权框架**
   - `simulation_evaluator.jl` 已用 `weightDays` 对每场景目标做加权，得到 `weighted_objective`。

5. **经济性计算能力**
   - `economy_evaluation_service.jl` + `economy_calculator.jl` 已经实现从 `timeseries.db` 读取物理量并计算各设备运行成本；
   - 支持 CP / WT / PV / ES / GP / CHP / ET / GRID / HS / FS / CS / PS / HYDRO 等类型；
   - 支持运维、启停、调整、弃风弃光、购电售电、松弛惩罚等成本项。

### 4.2 当前 fitness 来源与目标设计不符

在 `optimization_runner.jl:fitness()` 中：

```julia
simulation = evaluate_snapshot(...)
if simulation.feasible
    economic = evaluate_economics(economic_evaluator, ...)
    evaluation_fitness = economic.fitness
end
```

- `simulation.operating_objective` 是 JuMP 模型返回的加权目标函数值；
- `economic_evaluator.jl:OperatingObjectiveEvaluator` 直接把 `operating_objective` 原样返回为 `fitness`；
- 这意味着当前优化目标等于 **JuMP 目标函数值**，而不是从 `timeseries.db` 后验计算的运行成本。

如果用户在目标函数中只勾选了部分经济性项，或者目标函数包含松弛惩罚，那么 `operating_objective` 与真实的“运行成本”会不一致。

### 4.3 将经济性服务接入容量规划所需的适配

`economy_evaluation_service.jl:evaluate_task_economy()` 当前面向普通仿真任务设计，存在以下耦合：

1. 数据库路径硬编码为 `TASKS_DATA_ROOT/task_id/timeseries.db`；
2. 会遍历项目的所有时层；
3. 需要 `sim_end_time` 等参数。

最小版本需要：

- 新增一个针对**单个场景 DB** 的入口函数（例如 `evaluate_scenario_operating_cost(db_path, project_snapshot, layer_id)`）；
- 只读取规划层（`config["planningLayerId"]`）的物理量；
- 返回该场景的总运行成本（`total_cost` 或 `objective_value`）；
- 在 `optimization_runner.jl:fitness()` 中替换掉 `OperatingObjectiveEvaluator` 的调用，改为对每个场景的 DB 调用该函数并加权求和。

---

## 5. 最小版本数据流

```
┌─────────────────────────────────────────────────────────────┐
│  BlackBoxOptim 优化器                                        │
│  每轮迭代产生候选容量向量 raw_values                          │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  optimization_runner.jl:fitness()                            │
│  1. 量化候选 → candidate                                      │
│  2. 应用候选到项目快照                                         │
│  3. 对每个典型场景循环                                         │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  simulation_evaluator.jl:evaluate_snapshot()                 │
│  对每个 scenario：                                             │
│   - 在 work/<hash>/scenarios/<id>/ 创建 timeseries.db       │
│   - 注入边界数据                                               │
│   - build_model_tracked() → model.jl                         │
│   - solve_model() → 结果写入 timeseries.db                   │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  新增：场景运行成本计算                                        │
│  evaluate_scenario_operating_cost(db_path, snapshot, layer)  │
│   - 读取 timeseries.db                                        │
│   - 调用 economy_calculator 计算各设备成本                    │
│   - 返回该场景运行成本 operating_cost                         │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  optimization_runner.jl:fitness()                            │
│  fitness = Σ(operating_cost_i × weightDays_i)                │
│  返回给 BlackBoxOptim                                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. 需要补充/修改的代码

### 6.1 新增：单场景运行成本计算函数

**建议位置**：`backend/services/capacity_planning/economic_evaluator.jl`（或新建 `scenario_economy_evaluator.jl`）

**职责**：

- 接收单个场景的 `timeseries.db` 路径、候选快照、规划层 ID；
- 复用 `economy_evaluation_service.jl` 的 `load_component_data()`、`calc_component_cost()`、`load_slack_data()`；
- 返回该场景的运行成本（元）。

**伪代码**：

```julia
function evaluate_scenario_operating_cost(
    db_path::String,
    project_snapshot::Dict,
    layer_id::String,
)::Float64
    # 1. 从 project_snapshot 解析 component_dicts、nodes
    # 2. 读取 layer 的 step 得到 time_step_hours
    # 3. 对每个组件：
    #    power_data = load_component_data(db_path, comp_code, comp_type, layer_id, "0:00", nothing)
    #    params = resolve_component_params_economy_with_step(comp_dict, layer_id, time_step_hours)
    #    items = calc_component_cost(comp_type, node_id, comp_name, power_data, params, layer_id)
    #    total_cost += sum(item.value for item in items)
    # 4. 读取 slack 惩罚并累加
    # 5. 返回 total_cost
end
```

### 6.2 修改：`optimization_runner.jl:fitness()` 的 fitness 计算逻辑

**当前逻辑**：

```julia
simulation = evaluate_snapshot(...)
if simulation.feasible
    economic = evaluate_economics(economic_evaluator, EconomicEvaluationInput(...))
    evaluation_fitness = economic.fitness  # = JuMP operating_objective
end
```

**目标逻辑**：

```julia
simulation = evaluate_snapshot(...)  # 仍负责逐场景求解并持久化 DB
if simulation.feasible
    total_cost = 0.0
    total_days = 0
    for metric in simulation.scenario_metrics
        scenario_id = metric["scenarioId"]
        weight_days = metric["weightDays"]
        db_path = joinpath(work_dir, "scenarios", scenario_id, "timeseries.db")
        scenario_cost = evaluate_scenario_operating_cost(
            db_path, candidate_snapshot, string(config["planningLayerId"])
        )
        total_cost += scenario_cost * weight_days
        total_days += weight_days
    end
    evaluation_fitness = total_cost  # 或 total_cost / total_days，取决于优化器目标口径
end
```

> 注：`simulation.scenario_metrics` 已包含每个场景的 `scenarioId` 和 `weightDays`，可直接用于加权。

### 6.3 可选：保留 `OperatingObjectiveEvaluator` 作为调试模式

- 在 `economic_evaluator.jl` 中保留 `OperatingObjectiveEvaluator`；
- 新增一个 `TimeseriesOperatingCostEvaluator`；
- `economic_evaluator_from_config()` 根据 `config["evaluator"]` 选择使用哪一种。

这样可以在调试时快速切换回“JuMP 目标函数值”，便于排查是求解问题还是经济性计算问题。

### 6.4 需要新增/补全的前端功能

| 功能 | 状态 | 说明 |
|---|---|---|
| 第五步优化进度与结果展示 | 已实现基础结构 | 可在 `app/pages/capacity-planning/[projectId].vue` 中查看 |
| 第六步“应用最优解并启动滚动仿真” | 前端已调用，后端路由缺失 | `applyAndSimulate()` 调用 `/capacity-planning/{id}/apply-and-simulate`，该接口当前不存在 |
| NPV/IRR/LCOE/投资回收期展示 | 前端有展示位 | 最小版本中可隐藏或显示“未计算”占位 |

---

## 7. 冗余/暂不使用的代码

| 代码 | 位置 | 说明 |
|---|---|---|
| `OperatingObjectiveEvaluator` 的 NPV/IRR/LCOE 占位返回 | `economic_evaluator.jl:27-30` | 返回 `nothing`，符合当前约定；后续扩展投资模型时再填充 |
| `economic_evaluator.jl:calculate_annual_cost` / `calculate_lcoe` | 当前为 `return 0.0` 占位 | 最小版本不使用 |
| 前端结果面板中的 NPV/IRR/回收期/LCOE 卡片 | `app/pages/capacity-planning/[projectId].vue` 结果区 | 最小版本可保留展示但标注“未参与优化” |
| `evaluate_task_economy()` 中的多层遍历逻辑 | `economy_evaluation_service.jl:423-478` | 普通任务使用；容量规划场景 DB 为单层，可直接调用更细粒度函数 |
| 容量规划配置中的 `economics` 大段参数 | `types/capacity-planning.ts` | 只有 `evaluator` 字段在最小版本有意义，其余字段可保留但不参与计算 |

---

## 8. 结论：现有代码能否支持最小版本？

**可以支持，但需要一个聚焦的代码修改。**

- **不需要**重写仿真求解流程、场景聚类、候选应用、BlackBoxOptim 集成；
- **不需要**新增投资成本、NPV、IRR、LCOE 计算；
- **唯一的核心缺口**是：把 `optimization_runner.jl:fitness()` 中的 `fitness` 来源，从 `simulation.operating_objective` 替换为**基于每个场景 `timeseries.db` 的运行成本 + `weightDays` 加权**。

具体需要：

1. 新增一个读取单个场景 DB 并返回运行成本的函数（可复用 `economy_evaluation_service.jl` / `economy_calculator.jl`）；
2. 在 `fitness()` 中对该函数返回的每场景成本按 `weightDays` 加权求和；
3. 保持 `OperatingObjectiveEvaluator` 作为可切换的调试/对比模式。

完成以上修改后，即可得到一个可运行的最小版本：

```
fitness(candidate) = Σᵢ operating_cost(timeseries.dbᵢ, candidate) × weightDaysᵢ
```

---

## 9. 下一步建议

1. **确认口径**：fitness 是返回“加权总和”还是“加权日均成本”？建议返回加权总和，与当前 `operating_objective` 的量纲一致。
2. **实现 `evaluate_scenario_operating_cost()`**：建议放在 `backend/services/capacity_planning/economic_evaluator.jl` 或单独文件中，避免破坏 `economy_evaluation_service.jl` 的普通任务逻辑。
3. **修改 `optimization_runner.jl:fitness()`**：把 `evaluate_economics(...)` 调用替换为遍历 `simulation.scenario_metrics` 的新逻辑。
4. **调试验证**：先用一个已知容量的候选，对比 `timeseries.db` 计算的运行成本与 JuMP `operating_objective`，确认两者差异来源。
5. **第六步接口**：在最小版本跑通后，再补充 `/capacity-planning/{id}/apply-and-simulate` 后端路由。
