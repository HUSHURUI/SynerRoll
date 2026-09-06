# 经济性评价模块设计文档

## 一、需求分析

### 1.1 业务背景

当前系统实现了多时间尺度分层滚动优化仿真，支持16种能源组件（煤电、风电、光伏、储能等）。组件的 `model.jl` 中已经实现了各种成本计算的 `@expression` 代码模板，支持用户动态配置目标函数。

**现状**：经济性评价功能尚未实现，前端 `tasks/index.vue` 中的经济性分析部分为空。

### 1.2 核心需求

#### 需求1：分层经济性对比表
- **视角**：从最终计划执行的角度（覆盖模式数据）
- **内容**：各时层、各设备、各经济性项的值
- **样式**：被选中进入目标函数的项正常显示，未选中的灰色标注
- **用途**：例如对比日内计划相比日前计划，经济性有无提升

#### 需求2：目标函数组成分析
- **内容**：假设目标函数共有6项，展示各项的值及占比
- **样式**：饼状图或类似可视化
- **用途**：直观了解目标函数的构成

#### 需求3：补充建议（待确认）
- 分时经济性评价是否需要？（用户认为不需要，因为经济性评价是整体过程）
- 滚动过程的计划评价是否需要？（用户认为不需要）

### 1.3 关键约束

#### 约束1：选中 vs 未选中
- **选中进入目标函数的指标项** ≠ **能够求解的全部指标项**
- 例如：可以不在目标函数中考虑风电运维成本，但经济性评价环节仍需展示该成本

#### 约束2：后验计算
- 除了日前计划外，下层的目标函数都只是对待定计划的评价
- 最终日内层、实时层的经济性评价需要等求解全部完成后，按照"覆盖模式"的数据进行后验计算

---

## 二、关键问题解读

### 2.1 为什么需要后验计算？

#### 日前层 (Layer 1)
```
objective_value = 运维成本 + 开停机成本 + 调整成本 + ...
```
- `objective_value` 直接反映24h计划的总运行成本
- 可以直接使用

#### 下层 (Layer 2-8)
```
Layer2@8:00的objective_value = 8:00-12:00这4h的成本
Layer2@12:00的objective_value = 12:00-16:00这4h的成本
...
```
- 每次求解只得到该滚动窗口的 `objective_value`
- **不是**该层最终计划的总成本
- 需要等所有滚动窗口求解完成后，基于覆盖模式的数据重新计算

### 2.2 覆盖模式的作用

```julia
# simulation_runner.jl:158
solve_result = solve_model(model, components, layer, sim_time, store_path; overlay_mode=true)

# model_service.jl:393-397
if overlay_mode
    set_ts_merge(db_path, label, ts)  # 新数据覆盖旧数据
else
    set_ts(db_path, label, ts)        # 保留所有历史
end
```

**覆盖模式**：timeseries.db 中存储的是各时层**最终执行的物理量曲线**

**全跟踪模式**：保留所有滚动窗口的历史数据（用于回溯分析）

经济性评价必须基于覆盖模式的数据，因为这是最终执行的计划。

### 2.3 成本表达式的本质

查看组件代码：

```julia
# coal_power/model-base.jl:148-150
function define_cp_om_cost!(model, time_index, output_power, om_cost)
    return @expression(model, C_cp_om, sum(output_power[t] * om_cost for t in time_index))
end
```

**关键洞察**：
- 公式是 `Σ(功率 × 成本率)`
- 当 `output_power` 是 JuMP 变量时，生成的是符号表达式
- 当 `output_power` 是 Float64 数组时，得到的是数值结果
- **公式完全一样，只是输入类型不同**

这意味着我们可以设计一个**通用的计算模块**，同时支持：
1. 构建JuMP模型时生成表达式
2. 后验评价时计算数值

### 2.4 参数解析的复用

```julia
# coal_power/model-common.jl:7-32
function resolve_coal_power_params(component::CoalPower, ctx::BuildContext)
    layer_settings = layer_config(component, ctx.layer["id"])
    time_step_hours = step_hours(ctx.layer)

    return (
        capacity=component_paras(component)["capacity"],
        om_cost=component_costs(component)["om_cost"] * time_step_hours,
        on_off_cost=component_costs(component)["on_off_cost"] * time_step_hours,
        om_objective_on=layer_settings["objectives"]["om_objective_on"],
        # ...
    )
end
```

参数解析函数已经存在，后验评价时可以直接复用。

---

## 三、方案A详细设计

### 3.1 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                        前端 (tasks/index.vue)                    │
│  - 调用API获取经济性数据                                          │
│  - 展示表格、饼图、卡片                                           │
│  - 不涉及任何成本计算公式                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    API层 (routes/task.jl)                        │
│  GET /api/task/{id}/economy                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              评价服务层 (services/economy_evaluation_service.jl) │
│  - 读取覆盖模式的物理量数据                                       │
│  - 调用计算模块计算各项成本                                       │
│  - 汇总分层、分设备、分成本项的结果                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              计算模块层 (utils/economy_calculator.jl)             │
│  - 纯数值计算函数，不依赖JuMP                                    │
│  - 被评价服务层调用（后验计算）                                    │
│  - 可选：被model.jl调用（构建模型时）                              │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 模块设计

#### 3.2.1 计算模块 `economy_calculator.jl`

**位置**：`backend/utils/economy_calculator.jl`

**职责**：
- 提供纯数值计算函数
- 不依赖JuMP、不依赖数据库
- 可被评价服务层和模型构建层复用

**核心数据结构**：

```julia
"""单项成本计算结果"""
struct CostItem
    component_id::String       # 组件标识 (如 "CP_7e8a")
    component_type::String     # 组件类型 (如 "CP")
    component_name::String     # 组件名称 (如 "燃煤机组1号")
    cost_type::String          # 成本类型 (如 "om_cost", "on_off_cost", "slack_penalty")
    cost_label::String         # 显示标签 (如 "运维成本", "开停机成本", "松弛惩罚")
    layer_id::String           # 时层ID
    value::Float64             # 成本值（元），可为负数（如售电收益）
    in_objective::Bool         # 是否进入目标函数
    is_slack::Bool             # 是否为松弛变量成本
    is_revenue::Bool           # 是否为收益项（负成本）
end
```

**核心函数签名**：

```julia
# ═══════════════════════════════════════════════════════════════════════════
# 煤电成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_cp_om_cost(power_values, om_cost_rate) -> Float64

计算煤电运维成本。
- power_values: 出力数组 (kW)
- om_cost_rate: 单位运维成本 (元/kW·时间步长)
- 返回: 总运维成本 (元)
"""
function calc_cp_om_cost(power_values::Vector{Float64}, om_cost_rate::Float64)

"""
    calc_cp_on_off_cost(status_vector, on_off_cost_rate) -> Float64

计算煤电开停机成本。
- status_vector: 开停机状态数组 (0或1)
- on_off_cost_rate: 单次开停机成本 (元/次)
- 返回: 总开停机成本 (元)
"""
function calc_cp_on_off_cost(status_vector::Vector{Float64}, on_off_cost_rate::Float64)

"""
    calc_cp_adjust_cost(actual_power, planned_power, adjust_cost_rate) -> Float64

计算煤电调整成本。
- actual_power: 实际出力数组 (kW)
- planned_power: 计划出力数组 (kW)
- adjust_cost_rate: 单位调整成本 (元/kW)
- 返回: 总调整成本 (元)
"""
function calc_cp_adjust_cost(actual_power::Vector{Float64}, planned_power::Vector{Float64}, adjust_cost_rate::Float64)

"""
    calc_cp_costs(power_values, params, layer_settings; planned_power=nothing) -> Vector{CostItem}

计算煤电组件的所有成本项。
"""
function calc_cp_costs(power_values::Vector{Float64}, params, layer_settings; planned_power=nothing)

# ═══════════════════════════════════════════════════════════════════════════
# 风电成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_wt_cut_cost(cut_power, cut_cost_rate) -> Float64

计算弃风成本。
- cut_power: 弃风功率数组 (kW)
- cut_cost_rate: 单位弃风成本 (元/kW)
- 返回: 总弃风成本 (元)
"""
function calc_wt_cut_cost(cut_power::Vector{Float64}, cut_cost_rate::Float64)

"""
    calc_wt_costs(power_values, cut_values, params, layer_settings) -> Vector{CostItem}

计算风机组件的所有成本项。
"""
function calc_wt_costs(power_values::Vector{Float64}, cut_values::Vector{Float64}, params, layer_settings)

# ═══════════════════════════════════════════════════════════════════════════
# 储能成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_es_om_cost(input_power, output_power, om_cost_rate) -> Float64

计算储能运维成本。
"""
function calc_es_om_cost(input_power::Vector{Float64}, output_power::Vector{Float64}, om_cost_rate::Float64)

# ═══════════════════════════════════════════════════════════════════════════
# 电网成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_grid_purchase_cost(purchase_power, electricity_price) -> Float64

计算购电成本。
- purchase_power: 购电功率数组 (kW)
- electricity_price: 电价 (元/kWh)，已按时间步长换算
- 返回: 总购电成本 (元)
"""
function calc_grid_purchase_cost(purchase_power::Vector{Float64}, electricity_price::Float64)

"""
    calc_grid_sell_revenue(sell_power, electricity_price) -> Float64

计算售电收益（返回负值）。
- sell_power: 售电功率数组 (kW)
- electricity_price: 电价 (元/kWh)，已按时间步长换算
- 返回: 售电收益 (元)，负值
"""
function calc_grid_sell_revenue(sell_power::Vector{Float64}, electricity_price::Float64)

# ═══════════════════════════════════════════════════════════════════════════
# 松弛变量成本计算
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_slack_penalty(shortage, excess, penalty_rate) -> (penalty_cost, has_slack)

计算松弛变量惩罚成本。
- shortage: 短缺量数组
- excess: 过剩量数组
- penalty_rate: 惩罚系数 (元/单位)
- 返回: (惩罚成本, 是否存在松弛)
"""
function calc_slack_penalty(shortage::Vector{Float64}, excess::Vector{Float64}, penalty_rate::Float64)

# ═══════════════════════════════════════════════════════════════════════════
# 统一接口
# ═══════════════════════════════════════════════════════════════════════════

"""
    calc_component_cost(comp_type, power_data, params, layer_settings) -> Vector{CostItem}

根据组件类型调用对应的计算函数。
- comp_type: 组件类型 ("CP", "WT", "ES", "GRID", ...)
- power_data: Dict，包含该组件的物理量数据
- params: 组件参数
- layer_settings: 该层的配置
"""
function calc_component_cost(comp_type::String, power_data::Dict, params, layer_settings)

"""
    calc_bus_slack_cost(bus_data, algorithm) -> Vector{CostItem}

计算总线松弛变量成本。
- bus_data: Dict，包含总线的 SHORTAGE/EXCESS 数据
- algorithm: 算法配置，包含 slack_penalty 等参数
"""
function calc_bus_slack_cost(bus_data::Dict, algorithm::Dict)
```

#### 3.2.2 评价服务层 `economy_evaluation_service.jl`

**位置**：`backend/services/economy_evaluation_service.jl`

**职责**：
- 从 timeseries.db 读取覆盖模式的物理量数据
- 调用 `economy_calculator.jl` 计算各项成本
- 汇总分层、分设备、分成本项的结果

**核心数据结构**：

```julia
"""时层经济性汇总"""
struct LayerEconomySummary
    layer_id::String
    layer_name::String
    total_cost::Float64                         # 该层总成本（不含松弛惩罚）
    cost_breakdown::Dict{String, Float64}       # 按成本类型分组 {"om_cost": 1234.5, ...}
    component_breakdown::Dict{String, Float64}  # 按组件分组 {"CP_7e8a": 5678.9, ...}
    objective_components::Vector{String}        # 进入目标函数的成本项标识
    objective_value::Float64                    # 目标函数值（不含松弛惩罚）
    slack_penalty::Float64                      # 松弛变量惩罚成本
    has_slack::Bool                             # 是否存在松弛变量 > 0
    revenue_items::Dict{String, Float64}        # 收益项（负成本）{"sell_revenue": -3000, ...}
end

"""完整经济性评价结果"""
struct EconomyEvaluationResult
    task_id::String
    evaluation_time::String
    layers::Vector{LayerEconomySummary}
    all_cost_items::Vector{CostItem}
    objective_composition::Dict{String, Float64}  # 各层目标函数组成
end
```

**核心函数**：

```julia
"""
    evaluate_task_economy(task_id, project_json) -> EconomyEvaluationResult

计算任务的完整经济性指标。
"""
function evaluate_task_economy(task_id::String, project_json::Dict)

"""
    load_component_data(store_path, comp_type, comp_code, layer_id) -> Dict

从覆盖模式的数据读取组件物理量。
返回: {"power": [...], "cut": [...], "input": [...], "output": [...]}
"""
function load_component_data(store_path::String, comp_type::String, comp_code::String, layer_id::String)

"""
    build_layer_summary(layer_id, layer_name, cost_items) -> LayerEconomySummary

汇总单个时层的经济性指标。
"""
function build_layer_summary(layer_id::String, layer_name::String, cost_items::Vector{CostItem})
```

#### 3.2.3 API层

**位置**：`backend/routes/task.jl` 新增接口

```julia
# ───── GET /api/task/{id}/economy ─────
@get "/api/task/{id}/economy" function (req, id)
    try
        task = get_task(id)
        task === nothing && return json_error("任务不存在: $id")
        task["status"] != "completed" && return json_error("任务未完成，无法计算经济性指标")

        # 读取项目快照
        project_path = joinpath(TASKS_DATA_ROOT, id, "project.json")
        project_json = JSON3.read(read(project_path, String), Dict)

        result = evaluate_task_economy(id, project_json)
        return json_success(data=result)
    catch e
        return json_error("计算经济性指标异常: $(sprint(showerror, e))")
    end
end
```

#### 3.2.4 前端

**API封装**：`composables/api/useTaskApi.ts`

```typescript
getEconomy: (taskId: string) =>
    apiClient.get<EconomyEvaluationResult>(`/task/${taskId}/economy`),
```

**类型定义**：`types/api.ts`

```typescript
export interface CostItem {
    componentId: string
    componentType: string
    componentName: string
    costType: string
    costLabel: string
    layerId: string
    value: number
    inObjective: boolean
}

export interface LayerEconomySummary {
    layerId: string
    layerName: string
    totalCost: number
    costBreakdown: Record<string, number>
    componentBreakdown: Record<string, number>
    objectiveComponents: string[]
}

export interface EconomyEvaluationResult {
    taskId: string
    evaluationTime: string
    layers: LayerEconomySummary[]
    allCostItems: CostItem[]
    objectiveComposition: Record<string, number>
}
```

**UI布局**：`app/pages/tasks/index.vue`

```
┌─────────────────────────────────────────────────────────────────┐
│                      经济性分析                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  目标函数组成（饼图）                      │    │
│  │                                                          │    │
│  │    [时层选择: 日前 ▼]                                     │    │
│  │                                                          │    │
│  │    [饼图]        运维成本    45%   ¥12,345               │    │
│  │                  开停机成本  30%   ¥8,230                │    │
│  │                  调整成本    15%   ¥4,115                │    │
│  │                  弃风成本    10%   ¥2,743                │    │
│  │                  ─────────────────────────               │    │
│  │                  目标函数值  100%  ¥27,433               │    │
│  │                  (不含松弛惩罚)                           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  各时层经济性对比（表格）                   │    │
│  │                                                          │    │
│  │  时层  目标函数值  运维成本  开停机  调整  购电  售电  状态│    │
│  │  ─────────────────────────────────────────────────────── │    │
│  │  日前  ¥27,433    ¥12,345  ¥8,230  ¥4,115 ¥5,000 -¥2,257 ✓│   │
│  │  日内  ¥26,200    ¥11,789  ¥7,890  ¥3,777 ¥4,800 -¥2,056 ✓│   │
│  │  实时  ¥25,500    ¥11,456  ¥7,654  ¥3,780 ¥4,600 -¥1,990 ⚠│   │
│  │                                                          │    │
│  │  ✓ = 能量平衡  ⚠ = 存在松弛变量                           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  设备经济性明细（卡片）                    │    │
│  │                                                          │    │
│  │  [日前层]                                                 │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │    │
│  │  │ 燃煤机组1 │ │ 风机1    │ │ 电网     │ │ 储能1    │   │    │
│  │  │ 运维成本  │ │ 弃风成本  │ │ 购电成本  │ │ 运维成本  │   │    │
│  │  │ ¥5,678   │ │ ¥1,234   │ │ ¥5,000   │ │ ¥456     │   │    │
│  │  │          │ │          │ │ 售电收益  │ │          │   │    │
│  │  │          │ │          │ │ -¥2,257  │ │          │   │    │
│  │  │ [未选中]  │ │          │ │          │ │          │   │    │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  松弛变量状态（如有）                      │    │
│  │                                                          │    │
│  │  ⚠ 实时层存在能量不平衡                                   │    │
│  │    短缺惩罚: ¥500 (E_SHORTAGE)                           │    │
│  │    过剩惩罚: ¥0 (E_EXCESS)                               │    │
│  │    说明: 松弛变量大于0表示系统能量供应不平衡               │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 四、实施步骤

### 阶段1：后端计算模块（1天）

1. **创建 `backend/utils/economy_calculator.jl`**
   - 定义 `CostItem` 结构体
   - 实现煤电成本计算：`calc_cp_om_cost`, `calc_cp_on_off_cost`, `calc_cp_adjust_cost`, `calc_cp_costs`
   - 实现风电成本计算：`calc_wt_cut_cost`, `calc_wt_om_cost`, `calc_wt_costs`
   - 实现光伏成本计算：类似风电
   - 实现储能成本计算：`calc_es_om_cost`, `calc_es_costs`
   - 实现气电/热电联产成本计算：包括燃料成本
   - 实现电网成本计算：`calc_grid_purchase_cost`, `calc_grid_sell_revenue`
   - 实现松弛变量成本计算：`calc_slack_penalty`
   - 实现统一接口：`calc_component_cost`, `calc_bus_slack_cost`

2. **复用 `model-common.jl` 的参数解析逻辑**
   - 从 `resolve_xxx_params` 函数提取公共部分
   - 确保时间尺度换算一致

3. **编写单元测试**
   - 测试各组件成本计算函数
   - 测试边界情况（空数组、零值等）

### 阶段2：后端评价服务（1天）

1. **创建 `backend/services/economy_evaluation_service.jl`**
   - 定义 `LayerEconomySummary`, `EconomyEvaluationResult` 结构体
   - 实现 `load_component_data` 函数：从覆盖模式数据读取物理量
   - 实现 `evaluate_task_economy` 函数：主入口

2. **实现物理量数据读取**
   - 解析 timeseries.db 中的数据 key 格式：`"source_id|var_name|remark#layer_id"`
   - 读取各组件的功率、能量数据
   - 处理不同层的数据时间范围

3. **实现结果汇总逻辑**
   - 按层汇总：计算各层总成本、目标函数值
   - 按组件汇总：计算各组件成本
   - 按成本类型汇总：计算各类型成本
   - 处理松弛变量：标记是否存在能量不平衡
   - 处理收益项：单独列出售电收益等负成本

### 阶段3：API接口（0.5天）

1. **在 `routes/task.jl` 新增接口**
   - 添加 `GET /api/task/{id}/economy` 路由
   - 实现参数验证（任务必须已完成）
   - 调用 `evaluate_task_economy` 函数

2. **测试API返回结果**
   - 使用已完成的任务测试
   - 验证返回数据格式
   - 验证计算结果正确性

### 阶段4：前端实现（1-2天）

1. **添加类型定义**
   - 在 `types/api.ts` 添加 `CostItem`, `LayerEconomySummary`, `EconomyEvaluationResult` 接口

2. **封装API调用**
   - 在 `composables/api/useTaskApi.ts` 添加 `getEconomy` 方法

3. **实现UI展示**
   - 目标函数组成饼图（使用 ECharts）
   - 各时层经济性对比表格
   - 设备经济性明细卡片
   - 松弛变量状态提示
   - 样式：未选中的成本项灰色显示，收益项绿色/红色显示

---

## 五、已确认的设计决策

### 决策1：时间尺度处理方式
- **方案**：不在运行数据上处理步长差异，而是在经济性参数上换算
- **示例**：小时级电价为1，则15min级电价为0.25
- **依据**：`model-common.jl` 中已有此模式
- **实现**：计算模块复用 `model-common.jl` 的参数解析逻辑

### 决策2：各时层总成本的定义
- **方案**：基于覆盖模式的数据计算
- **说明**：日内层会互相遮盖，最终形成一条完整的日内运行结果
- **示例**：日内层总成本 = 针对覆盖模式数据中日内层时间范围的成本计算
- **依据**：与前端"运行总览"页面的数据来源一致

### 决策3：目标函数组成的计算基准
- **方案**：各层分别计算
- **说明**：每一层选用的目标函数不同，因此各层的目标函数组成也是不同指标拼起来的
- **实现**：
  - 每层独立计算其目标函数组成
  - 前端展示时可以选择查看某一层的目标函数组成
  - 或者展示各层目标函数组成的对比

### 决策4：松弛变量成本的处理
- **方案**：需要展示，但有特殊处理
- **展示规则**：
  - 松弛变量成本单独列出，用于标注给用户这组运行结果是否可行
  - 目标函数值展示时需要扣除松弛变量大于0产生的惩罚数值
  - 正常情况下松弛变量应该全为0，代表系统能量供应平衡
- **实现**：
  - 单独计算 SHORTAGE 和 EXCESS 的惩罚成本
  - 在展示时标记：如果松弛变量 > 0，提示"存在能量不平衡"
  - 目标函数组成中，松弛变量成本单独列为一项（灰色/警告色）

### 决策5：边界组件的处理
- **方案**：售电收益作为负成本
- **展示规则**：
  - 购电成本：正成本，正常展示
  - 售电收益：负成本，可用于抵消买电成本
  - 表格中需要分项单独列出（不合并）
- **示例**：
  ```
  购电成本: ¥10,000
  售电收益: -¥3,000
  净购电成本: ¥7,000  （在汇总中体现）
  ```

### 决策6：单位处理
- **方案**：内部统一用"元"
- **前端展示**：先用元，切换功能后期开发再做
- **实现**：后端返回值统一为元，前端暂不做单位转换

---

## 六、技术风险与缓解措施

### 风险1：覆盖模式数据不完整
- **描述**：某些组件的数据可能没有正确存储到覆盖模式
- **影响**：成本计算结果不准确
- **缓解**：
  - 在计算前检查数据完整性
  - 缺失数据给出警告，使用默认值0
  - 记录日志便于排查

### 风险2：参数解析不一致
- **描述**：后验评价时的参数解析与构建模型时可能不一致
- **影响**：成本计算结果与优化时的目标函数不一致
- **缓解**：
  - 复用 `model-common.jl` 中的参数解析函数
  - 添加单元测试对比两种方式的结果

### 风险3：时间对齐问题
- **描述**：不同层的数据时间戳可能不一致
- **影响**：跨层对比时出现偏差
- **缓解**：
  - 使用统一的时间格式（如 "H:MM"）
  - 按时间戳排序后再计算
  - 处理缺失时间点（填0或插值）

### 风险4：松弛变量识别
- **描述**：需要正确识别 SHORTAGE/EXCESS 变量
- **影响**：松弛变量成本计算错误
- **缓解**：
  - 通过变量名模式匹配：`E_SHORTAGE_*`, `E_EXCESS_*`
  - 从算法配置中读取惩罚系数

### 风险5：收益项处理
- **描述**：售电收益等负成本需要特殊处理
- **影响**：汇总计算错误
- **缓解**：
  - 明确标记收益项（`is_revenue=true`）
  - 汇总时分别累加正成本和负成本
  - 展示时单独列出

### 风险6：性能问题
- **描述**：大量组件和长时间仿真可能导致计算耗时
- **影响**：API响应慢
- **缓解**：
  - 首次实现不考虑缓存
  - 如果性能有问题，考虑：
    - 缓存计算结果
    - 增量计算（只计算变化的部分）
    - 异步计算（后台任务）

---

## 七、附录

### A. 各组件成本类型汇总

| 组件类型 | 成本类型 | 说明 | 公式 | 备注 |
|---------|---------|------|------|------|
| CP (煤电) | om_cost | 运维成本 | Σ(出力 × 成本率) | |
| CP (煤电) | on_off_cost | 开停机成本 | 开停机次数 × 单次成本 | |
| CP (煤电) | adjust_cost | 调整成本 | Σ|实际-计划| × 成本率 | |
| WT (风电) | om_cost | 运维成本 | Σ(出力 × 成本率) | |
| WT (风电) | cut_cost | 弃风成本 | Σ(弃风功率 × 成本率) | |
| PV (光伏) | om_cost | 运维成本 | Σ(出力 × 成本率) | |
| PV (光伏) | cut_cost | 弃光成本 | Σ(弃光功率 × 成本率) | |
| ES (储能) | om_cost | 运维成本 | Σ(充放电功率 × 成本率) | |
| GP (气电) | om_cost | 运维成本 | Σ(出力 × 成本率) | |
| GP (气电) | fuel_cost | 燃料成本 | Σ(出力 × 气耗率 × 气价) | |
| CHP (热电联产) | om_cost | 运维成本 | Σ(出力 × 成本率) | |
| ET (电解槽) | om_cost | 运维成本 | Σ(制氢功率 × 成本率) | |
| GRID (电网) | purchase_cost | 购电成本 | Σ(购电功率 × 电价) | 正成本 |
| GRID (电网) | sell_revenue | 售电收益 | Σ(售电功率 × 电价) | 负成本，单独列出 |
| BUS (总线) | shortage_penalty | 短缺惩罚 | Σ(短缺量 × 惩罚系数) | 松弛变量，单独列出 |
| BUS (总线) | excess_penalty | 过剩惩罚 | Σ(过剩量 × 惩罚系数) | 松弛变量，单独列出 |

**特殊处理说明**：
- **松弛变量成本**：单独列出，用于标注运行结果是否可行。目标函数展示时需扣除松弛惩罚。
- **售电收益**：负成本，在表格中单独列出，不与购电成本合并。
- **时间尺度换算**：经济性参数已按时间步长换算（如小时级电价1元/kWh → 15min级0.25元/kW）。

### B. 数据流向图

```
┌─────────────────────────────────────────────────────────────────┐
│                      timeseries.db (覆盖模式)                    │
│                                                                  │
│  "CP|E_CP_7e8a|power#1" -> [0:00: 500kW, 0:15: 520kW, ...]    │
│  "WT|E_WT_8f3a|power#1" -> [0:00: 200kW, 0:15: 180kW, ...]    │
│  "WT|E_WT_cut_8f3a|power#1" -> [0:00: 50kW, 0:15: 60kW, ...]  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    load_component_data()                         │
│                                                                  │
│  解析数据key，提取物理量数组                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    calc_component_cost()                         │
│                                                                  │
│  根据组件类型调用对应的计算函数                                    │
│  返回: [CostItem("om_cost", 1234.5, true), ...]                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    evaluate_task_economy()                       │
│                                                                  │
│  汇总所有组件、所有层的成本                                       │
│  生成最终结果                                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    API Response                                  │
│                                                                  │
│  {                                                               │
│    "taskId": "...",                                              │
│    "layers": [...],                                              │
│    "allCostItems": [...],                                        │
│    "objectiveComposition": {...}                                 │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 八、版本记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0 | 2026-09-06 | 初始版本，包含需求分析和方案设计 |
| v1.1 | 2026-09-06 | 根据用户反馈完善：确认时间尺度处理、松弛变量处理、收益项处理等 |

---

## 九、待办事项

- [ ] 用户确认设计文档
- [ ] 实现阶段1：后端计算模块
- [ ] 实现阶段2：后端评价服务
- [ ] 实现阶段3：API接口
- [ ] 实现阶段4：前端实现
- [ ] 集成测试
- [ ] 性能优化（如需要）

---

**文档版本**：v1.1
**创建日期**：2026-09-06
**最后更新**：2026-09-06
**作者**：Claude
