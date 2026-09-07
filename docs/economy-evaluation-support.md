# 经济性评价模块 — 当前已支持内容与代码位置

> 本文档说明截至当前代码版本，经济性评价模块已支持的设备类型、成本项、数据读取方式以及启停成本判定逻辑。

---

## 一、已支持的设备类型

后端服务 `backend/services/economy_evaluation_service.jl` 中的 `load_component_data()` 负责从覆盖模式的 `timeseries.db` 读取各设备的物理量。当前已支持的设备类型及读取的变量如下：

| 设备类型 | 类型代码 | 读取的物理量 | 对应时序 key 示例 |
|---------|---------|-------------|------------------|
| 燃煤机组 | `CP` | 出力 `power`、启停状态 `status` | `CP\|E_CP_{code}\|power#{layer}`、`CP\|F_CP_{code}\|power#{layer}` |
| 风机 | `WT` | 出力 `power`、弃风 `cut` | `WT\|E_WT_{code}\|power#{layer}`、`WT\|E_WT_cut_{code}\|cut#{layer}` |
| 光伏 | `PV` | 出力 `power`、弃光 `cut` | `PV\|E_PV_{code}\|power#{layer}`、`PV\|E_PV_cut_{code}\|cut#{layer}` |
| 电化学储能 | `ES` | 电量 `energy`、充电 `input`、放电 `output` | `ES\|E_ES_{code}\|energy#{layer}`、`ES\|E_ES_in_{code}\|power#{layer}`、`ES\|E_ES_out_{code}\|power#{layer}` |
| 气电机组 | `GP` | 出力 `power`、启停状态 `status` | `GP\|E_GP_{code}\|power#{layer}`、`GP\|F_GP_{code}\|power#{layer}` |
| 热电联产 | `CHP` | 出力 `power`、启停状态 `status` | `CHP\|E_CHP_{code}\|power#{layer}`、`CHP\|F_CHP_{code}\|power#{layer}` |
| 电解槽 | `ET` | 制氢功率 `power`、启停状态 `status` | `ET\|E_ET_{code}\|power#{layer}`、`ET\|F_ET_{code}\|power#{layer}` |
| 电网接口 | `GRID` | 售电 `sell`、购电 `buy` | `GRID\|E_GRID_in_{code}\|power#{layer}`、`GRID\|E_GRID_out_{code}\|power#{layer}` |
| 储氢设备 | `HS` | 储量 `energy`、充入 `input`、放出 `output` | `HS\|E_HS_{code}\|energy#{layer}`、`HS\|E_HS_in_{code}\|power#{layer}`、`HS\|E_HS_out_{code}\|power#{layer}` |
| 飞轮储能 | `FS` | 同上 | `FS\|E_FS_{code}\|energy#{layer}`、... |
| 压缩空气储能 | `CS` | 同上 | `CS\|E_CS_{code}\|energy#{layer}`、... |
| 抽水蓄能 | `PS` | 同上 | `PS\|E_PS_{code}\|energy#{layer}`、... |
| 常规水电 | `HYDRO` | 出力 `power` | `HYDRO\|E_HYDRO_{code}\|power#{layer}` |

> **不参与经济性计算的设备**：电负荷 `ELOAD`、氢负荷 `HLOAD`、热负荷 `QLOAD` 在 `evaluate_task_economy()` 中被显式 `continue` 跳过。

代码位置：

- 设备类型判断与数据读取：`backend/services/economy_evaluation_service.jl:162-200`
- 跳过负荷类型：`backend/services/economy_evaluation_service.jl:414`

---

## 二、已支持的经济性评价项

所有数值计算集中在 `backend/utils/economy_calculator.jl`，按设备类型分发。

### 2.1 燃煤机组（CP）

| 成本项 | 代码中的 `cost_type` | 计算方式 | 进入目标函数判定字段 |
|-------|---------------------|---------|---------------------|
| 运维成本 | `om_cost` | `Σ(出力 × om_cost_rate)` | `om_objective_on` |
| 启停成本 | `on_off_cost` | 状态变化次数 × `on_off_cost_rate` | `on_off_objective_on` |
| 调整成本 | `adjust_cost` | `Σ|实际出力 - 计划出力| × adjust_cost_rate` | `adjust_objective_on` |

代码位置：

- 运维/启停/调整计算：`backend/utils/economy_calculator.jl:45-121`
- 调用入口：`backend/utils/economy_calculator.jl:378-389`

> 当前 `load_component_data()` 未读取 `planned_power`，因此 **调整成本实际值为 0**；代码结构已预留该能力，待后续接入日前/日内计划数据即可启用。

### 2.2 风机 / 光伏（WT / PV）

| 成本项 | `cost_type` | 计算方式 | 进入目标函数判定字段 |
|-------|------------|---------|---------------------|
| 运维成本 | `om_cost` | `Σ(出力 × om_cost_rate)` | `om_objective_on` |
| 弃风/弃光成本 | `cut_cost` | `Σ(弃风/弃光功率 × cut_cost_rate)` | `cut_objective_on` |

代码位置：

- 计算实现：`backend/utils/economy_calculator.jl:127-172`
- 调用入口：`backend/utils/economy_calculator.jl:390-394`

### 2.3 各类储能（ES / HS / FS / CS / PS）

| 成本项 | `cost_type` | 计算方式 | 进入目标函数判定字段 |
|-------|------------|---------|---------------------|
| 运维成本 | `om_cost` | `Σ(充电功率 + 放电功率) × om_cost_rate` | `om_objective_on` |
| 调整成本 | `adjust_cost` | `Σ(|实际充 - 计划充| + |实际放 - 计划放|) × adjust_cost_rate` | `adjust_objective_on` |

代码位置：

- 计算实现：`backend/utils/economy_calculator.jl:178-240`
- 调用入口：`backend/utils/economy_calculator.jl:395-402`

> 与 CP 类似，`planned_input` / `planned_output` 当前未从数据库读取，调整成本暂为 0。

### 2.4 气电 / 热电联产 / 电解槽（GP / CHP / ET）

复用与 CP 相同的计算逻辑（运维、启停、调整）。

| 成本项 | `cost_type` | 计算方式 |
|-------|------------|---------|
| 运维成本 | `om_cost` | `Σ(出力 × om_cost_rate)` |
| 启停成本 | `on_off_cost` | 状态变化次数 × `on_off_cost_rate` |
| 调整成本 | `adjust_cost` | `Σ|实际 - 计划| × adjust_cost_rate` |

代码位置：

- 计算实现：`backend/utils/economy_calculator.jl:246-284`
- 调用入口：`backend/utils/economy_calculator.jl:403-409`

### 2.5 电网接口（GRID）

| 成本项 | `cost_type` | 计算方式 | 备注 |
|-------|------------|---------|------|
| 购电成本 | `purchase_cost` | `Σ(购电功率 × buy_price)` | 正成本 |
| 售电收益 | `sell_revenue` | `-Σ(售电功率 × sell_price)` | 负成本（收益项） |

代码位置：

- 计算实现：`backend/utils/economy_calculator.jl:290-332`
- 调用入口：`backend/utils/economy_calculator.jl:410-416`

### 2.6 总线松弛变量（BUS）

当仿真存在能量不平衡时，从 `timeseries.db` 读取 `SHORTAGE` / `EXCESS` 变量并计算惩罚。

| 成本项 | `cost_type` | 计算方式 |
|-------|------------|---------|
| 短缺惩罚 | `shortage_penalty` | `Σ(SHORTAGE) × slack_penalty` |
| 过剩惩罚 | `excess_penalty` | `Σ(EXCESS) × slack_penalty` |

代码位置：

- 数据读取与汇总：`backend/services/economy_evaluation_service.jl:207-256`
- 惩罚系数读取：`backend/services/model_service.jl:151-156`

---

## 三、启停成本判定逻辑

### 3.1 核心函数

启停成本计算函数为 `calc_cp_on_off_cost()`，位于：

```text
backend/utils/economy_calculator.jl:54-69
```

### 3.2 判定规则

```julia
function calc_cp_on_off_cost(status_vector::Vector{Float64}, on_off_cost_rate::Float64)
    length(status_vector) < 2 && return 0.0
    transitions = 0
    for i in 2:length(status_vector)
        if status_vector[i] != status_vector[i-1]
            transitions += 1
        end
    end
    return Float64(transitions) * on_off_cost_rate
end
```

规则说明：

1. 输入 `status_vector` 是设备在每个时间点的启停状态数组，期望取值为 `0`（停机）或 `1`（运行）。
2. 遍历相邻两个时间点的状态：
   - 只要 `status[i] != status[i-1]`，即视为一次启停事件。
   - 该判定**不区分是启动（0→1）还是停机（1→0）**，两种变化都计入一次。
3. 启停总成本 = `状态变化次数 × on_off_cost_rate`（单次启停成本）。

### 3.3 使用位置

- 煤电启停：`calc_cp_costs()` 中当 `status_vector !== nothing` 时调用，代码位置 `backend/utils/economy_calculator.jl:104-110`。
- 气电 / 热电联产 / 电解槽启停：`calc_thermal_gen_costs()` 中调用，代码位置 `backend/utils/economy_calculator.jl:267-273`。

### 3.4 参数来源

- 单次启停成本 `on_off_cost` 来自节点业务参数的 `commonEconomicParams.on_off_cost`（或兼容旧字段 `economicParams.on_off_cost`）。
- 是否进入目标函数由对应时层的 `objectives.on_off_objective_on` 决定。

代码位置：

- 参数解析：`backend/services/economy_evaluation_service.jl:497-521`
- 参数读取（原默认参数）：`backend/services/economy_evaluation_service.jl:97-107`

---

## 四、前端展示字段映射

前端 `app/pages/tasks/index.vue` 使用后端返回的 `EconomyEvaluationResult` 进行展示，主要字段映射如下：

| 前端展示 | 后端字段 | 说明 |
|---------|---------|------|
| 时层名称 | `layer.layerName` | |
| 目标函数值 | `layer.objectiveValue` | 不含松弛惩罚 |
| 总成本 | `layer.totalCost` | 含收益项（负成本），不含松弛惩罚 |
| 按成本类型汇总 | `layer.costBreakdown` | 如 `om_cost`、`on_off_cost`、`purchase_cost` 等 |
| 按设备汇总 | `layer.componentBreakdown` | key 为 `组件类型_短编码`，如 `CP_7e8a` |
| 收益项 | `layer.revenueItems` | 当前主要为 `sell_revenue` |
| 松弛惩罚 | `layer.slackPenalty` / `layer.hasSlack` | |
| 单项明细 | `allCostItems` | 每个设备、每个成本项的独立记录 |

代码位置：

- 经济性数据类型定义：`types/api.ts:133-166`
- 前端展示逻辑：`app/pages/tasks/index.vue:203-441`、`app/pages/tasks/index.vue:1462-1620`
