# 组件模型架构文档

> 本文档描述 SynerRoll 后端中风机(WT)、燃煤机组(CP)、电化学储能(ES)三个核心设备组件的数学模型、代码架构与协作关系。

---

## 目录

1. [架构总览](#1-架构总览)
2. [文件协作关系](#2-文件协作关系)
3. [风机 (WT)](#3-风机-wt)
4. [燃煤机组 (CP)](#4-燃煤机组-cp)
5. [电化学储能 (ES)](#5-电化学储能-es)
6. [代码生成管线](#6-代码生成管线)
7. [测试框架](#7-测试框架)
8. [开发者指南](#8-开发者指南)

---

## 1. 架构总览

### 1.1 系统定位

SynerRoll 是一个多时间尺度滚动优化系统。设备组件模型负责将物理设备的运行特性转化为 JuMP 数学优化模型，供求解器计算最优调度方案。

### 1.2 核心设计原则

- **配置驱动**：设备参数、约束开关、目标开关全部由 JSON 配置定义，代码不做硬编码
- **模式分派**：每种设备支持多种运行模式（stand_alone / adjust_power / fixed_state / full_follow / disabled），通过 Julia 的 `Val` 多分派机制路由到对应的数学模型
- **代码追踪**：构建模型的同时生成可读的 Julia 代码字符串，支持代码审查和独立执行
- **分层抽象**：配置解析、数学公式、代码生成三层解耦

### 1.3 数据流

```
component.json (用户配置)
    ↓
ComponentSchema (校验 + 类型归一化)
    ↓
ComponentConfig (运行时参数结构体)
    ↓
resolve_*_params() (参数解析 → 命名元组)
    ↓
build_component_model!() (数学模型构建)
    ├→ JuMP 模型 (直接 API 创建变量/约束/目标)
    └→ CodeTracer (代码字符串追踪)
         ↓
    generated_code.jl (可独立执行的 Julia 代码)
```

---

## 2. 文件协作关系

### 2.1 分层架构图

```
┌─────────────────────────────────────────────────────────────┐
│                     配置层 (Configuration)                    │
│                                                             │
│  config/component-library.json    ← 统一组件 schema 定义     │
│  core/schema.jl                   ← JSON → ComponentSchema  │
│  core/types.jl                    ← 基础类型定义             │
│  core/validation.jl               ← 通用校验框架             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                     组件层 (Components)                       │
│                                                             │
│  components/{type}/component.jl    ← 结构体 + schema 绑定    │
│  components/{type}/validation.jl   ← 特殊校验规则            │
│  components/{type}/model-common.jl ← 参数解析 + 共享函数     │
│  components/{type}/model-base.jl   ← 数学原理蓝图（参考）     │
│  components/{type}/model.jl        ← 元编程追踪版本（生产）   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                     基础设施层 (Infrastructure)               │
│                                                             │
│  utils/model_builder_utils.jl      ← CodeTracer + 追踪 API  │
│  utils/model_utils.jl              ← 模型工具（时间轴等）     │
│  utils/timeseries_utils.jl         ← 时序数据库读写          │
│  services/model_service.jl         ← 组装调度 + 能量平衡     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                     测试层 (Testing)                          │
│                                                             │
│  test/run_test.jl                  ← 测试运行器              │
│  test/{type}/case_*.json           ← 测试用例配置            │
│  test/{type}/generated_code/*.jl   ← 生成的代码（审查用）    │
│  test/mock_data/                   ← mock 时序数据库         │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 各文件职责

| 文件 | 职责 | 面向 |
|------|------|------|
| `component-library.json` | 定义所有组件的参数 schema（字段名、类型、默认值、范围） | 前端表单 + 后端校验 |
| `core/types.jl` | `ComponentConfig`、`FieldSpec`、`ComponentSchema` 等基础类型 | 开发者 |
| `core/schema.jl` | 从 JSON 加载 schema 到全局缓存 | 开发者 |
| `core/validation.jl` | 通用校验：类型检查、范围校验、必填校验 | 开发者 |
| `{type}/component.jl` | 组件结构体定义 + schema 绑定 + 结果绑定 | 开发者 |
| `{type}/validation.jl` | 组件特殊校验规则（当前为 stub） | 开发者 |
| `{type}/model-common.jl` | `resolve_*_params()` 参数解析 + 共享数学函数 | 开发者 |
| `{type}/model-base.jl` | 数学原理蓝图：纯 JuMP 宏写法，用于理解公式 | 算法研究者 |
| `{type}/model.jl` | 生产版本：用追踪 API 构建模型 + 记录代码 | 生产环境 |
| `utils/model_builder_utils.jl` | `CodeTracer` + `add_tracked_variable!` 等追踪 API | 开发者 |
| `services/model_service.jl` | `build_model` / `build_model_tracked` 组装入口 | 生产环境 |
| `test/run_test.jl` | 测试运行器 + mock 数据生成 | 测试 |
| `test/{type}/case_*.json` | 单设备测试用例配置 | 测试 |

### 2.3 关键依赖关系

```
model.jl  ──调用──→  model_builder_utils.jl (追踪 API)
    │
    ├──引用──→  model-common.jl (参数解析)
    │
    └──参考──→  model-base.jl (数学公式对照)

model_service.jl  ──实例化──→  component.jl
    │
    ├──调用──→  model.jl (build_component_model!)
    │
    └──调用──→  model_builder_utils.jl (CodeTracer)

component.jl  ──依赖──→  schema.jl + validation.jl + types.jl
    │
    └──读取──→  component-library.json (通过 schema 缓存)
```

---

## 3. 风机 (WT)

### 3.1 物理模型

风机将风能转化为电能。出力取决于风速、切入/额定/切出风速、空气密度、传动效率、发电机效率、逆变器效率。

### 3.2 数学公式

#### 决策变量

| 符号 | 含义 | 下界 | 上界 |
|------|------|------|------|
| E_WT[t] | 时段 t 的实际出力 (kW) | 0 | available_power[t] |
| E_WT_cut[t] | 时段 t 的弃风功率 (kW) | 0 | available_power[t] |

#### 可用功率计算

根据边界数据类型（`var_name`）选择计算方式：

**风速边界** (`wind_speed`)：
```
scaled_speed = |wind_speed| × (h2/h1)^α          # 风切变修正
coefficient  = f(scaled_speed, v_in, v_r, v_out)  # 风速-功率系数
available    = coefficient × η_t × η_g × η_inv × capacity
```

其中风速-功率系数：
```
if speed < v_in:        coefficient = 0
if v_in ≤ speed < v_r:  coefficient = (speed³ - v_in³) / (v_r³ - v_in³)
if v_r ≤ speed < v_out: coefficient = 1
if speed ≥ v_out:       coefficient = 0
```

**因子边界** (`factor`)：
```
available = clamp(factor, 0, 1) × capacity
```

**功率边界** (`power`)：
```
available = |power|
```

#### 约束

| 编号 | 名称 | 公式 | 开关 |
|------|------|------|------|
| C1 | 功率平衡 | E_WT[t] + E_WT_cut[t] = available_power[t] | 始终启用 |
| C2 | 弃风上限 | Σ E_WT_cut ≤ max_cut_ratio × Σ available_power | curtailment_constraint_on & max_cut_ratio < 1.0 |

#### 目标函数

```
min Z = cut_objective_on  × cut_cost × Σ E_WT_cut
      + om_objective_on   × om_cost  × Σ E_WT
```

### 3.3 运行模式

WT 仅支持 `stand_alone` 模式。

### 3.4 参数说明

**通用技术参数** (`paras`)：

| 参数 | 含义 | 单位 | 默认值 |
|------|------|------|--------|
| capacity | 额定容量 | kW | 300000 |
| efficiency | 综合效率 | - | 0.95 |
| v_in | 切入风速 | m/s | 3.0 |
| v_r | 额定风速 | m/s | 9.5 |
| v_out | 切出风速 | m/s | 19.5 |
| h1 | 测风高度 | m | 10 |
| h2 | 轮毂高度 | m | 135 |
| α | 风切变指数 | - | 0.143 |
| η_t | 传动效率 | - | 0.96 |
| η_g | 发电机效率 | - | 0.93 |
| η_inverter | 逆变器效率 | - | 0.96 |

**时层技术参数** (`layer.paras`)：

| 参数 | 含义 | 默认值 |
|------|------|--------|
| max_cut_ratio | 最大弃风比例 | 1.0 |

**约束开关** (`layer.constraints`)：

| 开关 | 含义 | 默认值 |
|------|------|--------|
| curtailment_constraint_on | 启用弃风上限约束 | true |

**目标开关** (`layer.objectives`)：

| 开关 | 含义 | 默认值 |
|------|------|--------|
| om_objective_on | 启用运维成本目标 | true |
| cut_objective_on | 启用弃风惩罚目标 | true |

---

## 4. 燃煤机组 (CP)

### 4.1 物理模型

燃煤机组通过燃烧燃料发电。出力受容量上下限、爬坡速率、最低出力、最小开停机时间等约束。

### 4.2 数学公式

#### 决策变量

| 符号 | 含义 | 下界 | 上界 |
|------|------|------|------|
| E_CP[t] | 时段 t 的电出力 (kW) | 0 | capacity |
| F_CP[t] | 时段 t 的燃料消耗 | 0 | +∞ |
| ΔE_CP[t] | 时段 t 的爬坡量 | -ramp×capacity | +ramp×capacity |
| u_CP[t] | 时段 t 的开停机状态 (0/1) | - | - |
| u_CP_start[t] | 时段 t 的开机标志 (0/1) | - | - |
| u_CP_stop[t] | 时段 t 的停机标志 (0/1) | - | - |
| cp_adjust_direction[t] | 调节方向 (0/1) | - | - |
| cp_adjust_up[t] | 上调量 (kW) | 0 | adjust_limit × capacity |
| cp_adjust_down[t] | 下调量 (kW) | 0 | adjust_limit × capacity |

#### 核心约束

| 编号 | 名称 | 公式 | 适用模式 | 开关 |
|------|------|------|---------|------|
| C1 | 燃料转换 | E_CP[t] = F_CP[t] × η | 全部 | 始终 |
| C2 | 爬坡 | ΔE_CP[t] = E_CP[t+1] - E_CP[t], \|ΔE_CP\| ≤ ramp×capacity | SA/ADJ/FS | ramp_constraint_on |
| C3 | 最低出力 | E_CP[t] ≥ min × capacity | SA(无u)/ADJ | min_constraint_on |
| C3' | 最低出力(含状态) | E_CP[t] ≥ u_CP[t] × min × capacity | SA(有u) | min + on_off |
| C4 | 状态上限 | E_CP[t] ≤ u_CP[t] × capacity | SA(有u) | on_off_constraint_on |
| C5 | 初始状态 | u_CP[first] = u_CP_start[first] | SA(有u) | on_off |
| C6 | 状态转移 | u_CP[t] - u_CP[t-1] = u_CP_start[t] - u_CP_stop[t] | SA(有u) | on_off |
| C7 | 互斥 | u_CP_start[t] + u_CP_stop[t] ≤ 1 | SA(有u) | on_off |
| C8 | 最小开机 | Σ u_CP_start[h] (h=t-T_on+1..t) ≤ u_CP[t] | SA(有u) | on_off |
| C9 | 最小停机 | Σ u_CP_stop[h] (h=t-T_off+1..t) ≤ 1-u_CP[t] | SA(有u) | on_off |
| C10 | 调节平衡 | E_CP[t] = planned[t] + adj_up[t] - adj_down[t] | ADJ/FS | adjust |
| C11 | 调节互斥 | adj_up ≤ M×dir, adj_down ≤ M×(1-dir) | ADJ/FS | adjust |

#### 目标函数

```
min Z = om_objective_on    × om_cost    × Σ E_CP[t]
      + on_off_objective_on × on_off_cost × Σ (u_CP_start[t] + u_CP_stop[t])
      + adjust_objective_on × adjust_cost × Σ (adj_up[t] + adj_down[t])
```

### 4.3 运行模式

| 模式 | 含义 | 变量 | 约束 |
|------|------|------|------|
| stand_alone | 独立运行 | E_CP, F_CP, (可选 u_CP 系列) | C1 + C2 + (C3-C9) |
| adjust_power | 基于计划调节 | E_CP, F_CP, adj 系列 | C1 + C2 + C3 + C10-C11 |
| fixed_state | 固定开停状态 | E_CP, F_CP, u_CP_start/stop, adj 系列 | C1 + C2 + C4-C9 + (C10-C11) |
| full_follow | 严格跟随计划 | E_CP (bounds锁定), F_CP | C1 + (可选 C4-C9) |
| disabled | 停用 | E_CP [0,1], F_CP [0,1] | 无 |

### 4.4 参数说明

**通用技术参数** (`paras`)：

| 参数 | 含义 | 单位 | 默认值 |
|------|------|------|--------|
| capacity | 额定容量 | kW | 350000 |
| η | 转化效率 | - | 0.5 |
| ramp | 爬坡率 | 1/h | 0.5 |
| min | 最低出力率 | - | 0.3 |
| T_min_on | 最小开机时间 | h | 10 |
| T_min_off | 最小停机时间 | h | 10 |

**时层参数** (`layer.paras`)：

| 参数 | 含义 | 默认值 |
|------|------|--------|
| adjust_limit | 调节幅度上限率 | 0.3 |

---

## 5. 电化学储能 (ES)

### 5.1 物理模型

电化学储能通过充放电实现能量的时移。荷电状态 (SOC) 遵循能量守恒方程，充放电互斥。

### 5.2 数学公式

#### 决策变量

| 符号 | 含义 | 下界 | 上界 |
|------|------|------|------|
| E_ES[t] | 时段 t 的荷电量 SOC (kWh) | 0 | max_soc × capacity |
| E_ES_in[t] | 时段 t 的充电功率 (kW) | 0 | +∞ |
| E_ES_out[t] | 时段 t 的放电功率 (kW) | 0 | +∞ |
| γ_ES[t] | 充放电状态 (0/1 二元) | - | - |

#### 核心约束

| 编号 | 名称 | 公式 | 适用模式 | 开关 |
|------|------|------|---------|------|
| C1 | 能量守恒 | E_ES[t] = E_ES[t-1]×(1-loss) + E_ES_in[t-1]×η - E_ES_out[t-1]/η | 全部 | 始终 |
| C2 | 荷电下限 | E_ES[t] ≥ min_soc × capacity | SA/FS | min_constraint_on |
| C3 | 充电爬坡 | E_ES_in[t] ≤ ramp × capacity | SA/FS | ramp_constraint_on |
| C4 | 放电爬坡 | E_ES_out[t] ≤ ramp × capacity | SA/FS | ramp_constraint_on |
| C5 | 首末相等 | E_ES[first] = E_ES[last] | SA | start_end_equality |
| C6 | 初始 SOC | E_ES[first] = DB值 或 capacity × ini_soc | 全部 | 始终 |
| C7 | 充放互斥(二元) | E_ES_in ≤ M×γ, E_ES_out ≤ M×(1-γ) | SA | 始终 |
| C7' | 充放互斥(三值) | 见下文 | FS | 始终 |
| C8 | 调节平衡 | E_ES_in[t] = planned_in[t]×(γ=1) + adj_up×(γ=1) - adj_down×(γ=1) | FS | adjust |
| C9 | 调节互斥 | adj_up ≤ M×dir, adj_down ≤ M×(1-dir) | FS | adjust |

#### 三值状态互斥约束 (fixed_state 专用)

当 `storage_state` 为三值常量 (+1/-1/0) 时：

```
E_ES_in[t]  ≤ M × (storage_state[t] + 1) / 2    # γ=1 允许充电, γ=-1/0 禁止
E_ES_out[t] ≤ M × (1 - storage_state[t]) / 2    # γ=-1 允许放电, γ=1/0 禁止
E_ES_in[t]  ≤ M × storage_state[t]²             # γ=0 禁止充电
E_ES_out[t] ≤ M × storage_state[t]²             # γ=0 禁止放电
```

#### 目标函数

```
min Z = om_objective_on    × om_cost    × Σ (E_ES_in[t] + E_ES_out[t])
      + adjust_objective_on × adjust_cost × Σ (adj_up[t] + adj_down[t])
```

### 5.3 运行模式

| 模式 | 含义 | 决策变量 | 能量守恒用 |
|------|------|---------|-----------|
| stand_alone | 独立运行 | E_ES, E_ES_in, E_ES_out, γ_ES | 决策变量 |
| fixed_state | 固定充放状态 | E_ES, E_ES_in, E_ES_out | 决策变量 + 三值互斥 |
| full_follow | 严格跟随计划 | E_ES (bounds 锁定) | 计划值(常量) |
| disabled | 停用 | E_ES/E_ES_in/E_ES_out [0,1] | 无 |

### 5.4 参数说明

**通用技术参数** (`paras`)：

| 参数 | 含义 | 单位 | 默认值 |
|------|------|------|--------|
| capacity | 额定容量 | kWh | 200000 |
| η | 充放电效率 | - | 0.95 |
| ramp | 爬坡率 | 1/h | 0.5 |
| max | 最大 SOC 率 | - | 1.0 |
| min | 最小 SOC 率 | - | 0.1 |
| ini | 初始 SOC 率 | - | 0.1 |
| loss | 自放电率 | 1/h | 0.001 |

---

## 6. 代码生成管线

### 6.1 CodeTracer 机制

`CodeTracer` 是代码追踪的核心数据结构：

```julia
mutable struct CodeTracer
    lines::Vector{String}              # 生成的代码行
    objective_expr_names::Vector{String}  # 属于目标函数的命名表达式
end
```

### 6.2 追踪 API

| 函数 | 作用 | 生成的代码示例 |
|------|------|---------------|
| `add_tracked_variable!` | 创建变量 + 记录 | `@variable(model, E_CP[1:24], lower_bound=0)` |
| `add_tracked_linear_constraint!` | 创建约束 + 记录 | `@constraint(model, [t in 1:24], E_CP[t] >= 0.3*350000)` |
| `add_tracked_expression!` | 创建表达式 + 记录 | `@expression(model, C_cp_om, sum(E_CP[t]*0.1 for t in 1:24))` |
| `register_objective_expr!` | 注册目标表达式名 | (影响 @objective 行的生成) |

### 6.3 代码生成流程

```julia
# model_service.jl 中的 build_model_tracked
model, code = build_model_tracked(component_dicts, algorithms, nodes, layer, time, db_path)

# 内部流程：
# 1. 创建 CodeTracer
# 2. 记录模型初始化代码（using JuMP, COPT 等）
# 3. 遍历组件，调用 build_component_model!(model, component, ctx, tracer)
#    - 每个 add_tracked_variable! 调用 → record! 一行 @variable
#    - 每个 add_tracked_linear_constraint! 调用 → record! 一行 @constraint
#    - 每个 add_tracked_expression! 调用 → record! 一行 @expression
# 4. 记录能量平衡约束
# 5. 拼接 @objective 行（使用 objective_expr_names）
# 6. 返回 (model, get_code(tracer))
```

### 6.4 参数内联策略

生成的代码中所有参数都内联为硬值，不依赖外部变量：

```julia
# 运行时代码（闭包捕获变量）
@constraint(model, [t in time_index], E_CP[t] >= status_vector[t] * params.min * params.capacity)

# 生成的代码（参数内联）
@constraint(model, [t in 1:24], E_CP_cp01[t] >= [1,1,0,...][t] * 0.3 * 350000)
```

向量 bound 使用 `[t]` 索引：

```julia
@variable(model, E_CP_test01[t in 1:24], lower_bound = [105000.0, ...][t], upper_bound = [105001.0, ...][t])
```

---

## 7. 测试框架

### 7.1 测试理念

测试框架验证两个层面的正确性：
1. **构建正确性**：`build_model_tracked` 是否能成功构建模型（变量数、约束数符合预期）
2. **代码正确性**：生成的代码是否能独立执行（语法正确、数学逻辑可审查）

### 7.2 测试用例设计

每个组件覆盖所有运行模式 × 关键约束/目标组合：

| 组件 | 模式 | 用例数 | 覆盖重点 |
|------|------|--------|---------|
| WT | stand_alone | 5 | 弃风约束开关 × 弃风/运维目标开关 |
| CP | stand_alone | 2 | 有/无开停机约束 |
| CP | adjust_power | 2 | 有/无爬坡约束 |
| CP | fixed_state | 1 | 全约束 + 全目标 |
| CP | full_follow | 2 | 仅运维 / 含开停机 |
| CP | disabled | 1 | 最小模型 |
| ES | stand_alone | 4 | 全约束 / 无首末相等 / 无爬坡 / 最小 |
| ES | fixed_state | 1 | 全约束 + 调节 |
| ES | full_follow | 1 | 仅运维 |
| ES | disabled | 1 | 最小模型 |

### 7.3 Mock 数据

`test/mock_data/test_timeseries.db` 自动生成，包含：

| 数据 | 用途 |
|------|------|
| 风速边界 (b_mock_wind) | WT 可用功率计算 |
| 电负荷边界 (b_mock_load) | E_LOAD 测试 |
| CP 上层结果 (E_CP_cp03/cp04/test01) | CP adjust_power/fixed_state/full_follow |
| ES 上层结果 (E_ES_in/out_test01) | ES fixed_state/full_follow |
| ES SOC 轨迹 (ES_test01) | ES 初始 SOC 约束 |

### 7.4 使用方式

```julia
include("test/run_test.jl")

# 运行单个用例
run_case("WT/case_01_sa_full")
run_case("CP/case_05_fixed_full")  # 自动检测 layer_id="2"

# 运行全部
run_all()
run_all(force_db=true)  # 强制重新生成 mock 数据
```

---

## 8. 开发者指南

### 8.1 新增组件的步骤

1. 在 `config/component-library.json` 中添加组件定义
2. 创建 `components/{type}/` 目录，包含 5 个文件：
   - `component.jl`：结构体 + schema 绑定 + 结果绑定
   - `validation.jl`：特殊校验规则
   - `model-common.jl`：`resolve_*_params()` + 共享函数
   - `model-base.jl`：数学原理蓝图（纯 JuMP 宏）
   - `model.jl`：元编程追踪版本
3. 在 `model_service.jl` 的 `COMPONENT_CONSTRUCTORS` 中注册
4. 在 `BackendStandardized.jl` 中 include
5. 在 `test/` 中添加测试用例

### 8.2 添加新运行模式

1. 在 `component-library.json` 的 `layerStatuses` 中添加模式名
2. 在 `model-base.jl` 中实现数学公式
3. 在 `model.jl` 中实现追踪版本：
   - 新增 `build_*_status_model!(model, component, params, ctx, code, tracer, ::Val{:new_mode})` 方法
   - 使用 `add_tracked_variable!` / `add_tracked_linear_constraint!` / `add_tracked_expression!`
4. 添加测试用例

### 8.3 调试生成的代码

生成的代码保存在 `test/{type}/generated_code/{case}_layer{id}.jl`，可以独立执行：

```julia
using JuMP, COPT
include("test/CP/generated_code/case_01_sa_basic_layer1.jl")
optimize!(model)
termination_status(model)
value.(model[:E_CP_cp01])
```

### 8.4 关键设计决策

| 决策 | 原因 |
|------|------|
| 用 `Val` 分派而非 if-else | Julia 多分派机制，编译时优化，类型安全 |
| 参数内联为硬值 | 生成的代码可独立执行，不依赖外部变量 |
| model-base.jl 保留 | 数学原理参考，不参与生产 |
| CodeTracer 追踪 | 支持代码审查 + 人工验证数学逻辑 |
| mock 数据自动生成 | 测试可重复，不依赖外部数据 |
