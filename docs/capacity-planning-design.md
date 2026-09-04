# 容量规划功能设计文档

> 状态：设计阶段
> 最后更新：2026-08-26

本文档覆盖容量规划功能的完整设计方案，基于现有计算任务架构扩展，实现设备容量优化配置的端到端业务流程。

---

## 1. 功能概述

容量规划是一个独立的业务模块，与"仿真计算"并列在编辑器的"建模"工具栏中。用户可以通过该功能：

1. **配置优化变量**：选择哪些设备容量作为优化变量，设置搜索边界和建议值
2. **场景聚类**：将边界时序数据聚类为若干典型日场景，减少计算量
3. **黑箱优化**：使用 BlackBoxOptim 算法框架求解最优容量配置
4. **经济性评价**：根据仿真结果进行项目经济性评估
5. **一键仿真**：将最优配置应用到项目，执行完整仿真

---

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              前端 (Nuxt 4 + Vue 3)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │ 容量规划按钮  │───▶│ 变量配置表单  │───▶│ 优化进度展示  │───▶│ 结果展示面板  │ │
│  └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              后端 (Julia + Oxygen.jl)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │ 表单生成服务  │───▶│ 聚类服务      │───▶│ 优化求解服务  │───▶│ 经济评价服务  │ │
│  └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘ │
│         │                   │                   │                   │         │
│         ▼                   ▼                   ▼                   ▼         │
│  ┌──────────────────────────────────────────────────────────────────────────┐ │
│  │                    复用现有 TaskManager + SimulationRunner                │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              数据层                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │ boundary.db  │───▶│ 优化任务 DB   │───▶│ 聚类结果 DB   │───▶│ 评价结果 DB   │ │
│  └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 与现有系统的关系

容量规划模块**复用**现有计算任务架构的核心组件：

| 组件 | 复用方式 | 说明 |
|---|---|---|
| `TaskManager` | 直接复用 | 任务生命周期管理（创建、状态更新、暂停/恢复） |
| `SimulationRunner` | 扩展复用 | 求解主循环，在外层包裹优化迭代逻辑 |
| `BoundarySeeder` | 直接复用 | 从项目 boundary.db 注入数据到任务 DB |
| `SQLiteTimeSeriesStore` | 直接复用 | 时序数据存储 |
| WebSocket 推送 | 直接复用 | 实时进度推送 |

**关键区别**：容量规划任务是**批量任务组**（一次优化包含 N 个仿真任务），需要额外的任务组管理层。

---

## 3. 数据模型

### 3.1 容量规划配置（前端表单）

```typescript
// types/capacity-planning.ts

// 设备优化变量配置
export interface CapacityVariable {
  componentId: string        // 组件 ID（如 "WT_001"）
  componentKey: string       // 组件类型（如 "WT", "PV", "ES"）
  componentName: string      // 组件显示名称
  enabled: boolean           // 是否作为优化变量（false 表示固定值）
  fixedValue?: number        // 固定值（enabled=false 时使用）
  lowerBound?: number        // 搜索下界（enabled=true 时必填）
  upperBound?: number        // 搜索上界（enabled=true 时必填）
  suggestedValue?: number    // 建议值（初始猜测）
  unit: string               // 单位（kW, kWh, kVA 等）
}

// 聚类配置
export interface ClusteringConfig {
  method: 'kmeans'           // 聚类方法（当前仅支持 K-means）
  numClusters: number        // 典型日数量（K 值）
  features: string[]         // 聚类特征（如 ['wind_speed', 'irradiance', 'load']）
  timeGranularity: string    // 时间粒度（如 '1h', '30m'）
  seasonWeights?: Record<string, number>  // 季节权重（可选）
}

// 优化算法配置
export interface OptimizationConfig {
  algorithm: 'adaptive_de' | 'xnes' | 'separable_nes' | 'dxnes'  // BlackBoxOptim 算法
  maxEvaluations: number     // 最大迭代次数
  populationSize: number     // 种群大小
  targetFitness?: number     // 目标适应度（提前终止条件）
  seed?: number              // 随机种子（可复现）
}

// 经济性评价配置
export interface EconomicConfig {
  projectLifespan: number    // 项目寿命（年）
  discountRate: number       // 折现率
  electricityPrice: number   // 电价（元/kWh）
  carbonPrice?: number       // 碳价（元/吨）
  // 其他经济参数...
}

// 完整容量规划配置
export interface CapacityPlanningConfig {
  id: string                 // 规划任务 ID
  projectId: string          // 关联项目 ID
  canvasId: string           // 关联画布 ID
  name: string               // 规划任务名称
  variables: CapacityVariable[]
  clustering: ClusteringConfig
  optimization: OptimizationConfig
  economic: EconomicConfig
  createdAt: string
  updatedAt: string
}
```

### 3.2 容量规划任务状态

```typescript
// types/capacity-planning.ts

export type CapacityPlanningStatus =
  | 'configuring'    // 配置中（前端表单）
  | 'clustering'     // 聚类计算中
  | 'optimizing'     // 优化求解中
  | 'evaluating'     // 经济评价中
  | 'completed'      // 完成
  | 'failed'         // 失败
  | 'cancelled'      // 已取消

export interface CapacityPlanningTask {
  id: string
  projectId: string
  config: CapacityPlanningConfig
  status: CapacityPlanningStatus
  progress: {
    phase: string           // 当前阶段
    currentIteration: number // 当前迭代次数
    totalIterations: number  // 总迭代次数
    bestFitness: number      // 当前最优适应度
    bestSolution: number[]   // 当前最优解
  }
  results?: CapacityPlanningResult
  createdAt: string
  updatedAt: string
  startedAt?: string
  finishedAt?: string
  errorMessage?: string
}

// 容量规划结果
export interface CapacityPlanningResult {
  optimalVariables: {
    componentId: string
    optimalCapacity: number
    unit: string
  }[]
  totalCost: number          // 总成本（万元）
  annualCost: number         // 年成本（万元）
  economicIndicators: {
    npv: number              // 净现值
    irr: number              // 内部收益率
    paybackPeriod: number    // 投资回收期（年）
    lcoe: number             // 平准化度电成本
  }
  convergenceHistory: {
    iteration: number
    fitness: number
  }[]
  typicalDays: TypicalDay[]  // 聚类得到的典型日
}

// 典型日数据
export interface TypicalDay {
  id: number
  weight: number             // 权重（出现概率）
  representativeDate: string // 代表日期
  boundaryData: Record<string, number[]>  // 边界数据
}
```

### 3.3 数据库 Schema

#### 3.3.1 容量规划任务表（全局一份）

```sql
-- backend/data/capacity_planning.db
CREATE TABLE capacity_planning_tasks (
    id                  TEXT PRIMARY KEY,
    project_id          TEXT NOT NULL,
    canvas_id           TEXT NOT NULL,
    name                TEXT,
    status              TEXT NOT NULL,
    config_json         TEXT NOT NULL,           -- 完整配置 JSON
    progress_json       TEXT,                    -- 进度信息 JSON
    results_json        TEXT,                    -- 结果 JSON
    created_at          TEXT NOT NULL,
    updated_at          TEXT NOT NULL,
    started_at          TEXT,
    finished_at         TEXT,
    error_message       TEXT
);

CREATE INDEX idx_cp_tasks_project ON capacity_planning_tasks(project_id);
CREATE INDEX idx_cp_tasks_status ON capacity_planning_tasks(status);
```

#### 3.3.2 聚类结果表

```sql
-- 存储在 capacity_planning.db 中
CREATE TABLE clustering_results (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    planning_task_id    TEXT NOT NULL REFERENCES capacity_planning_tasks(id),
    num_clusters        INTEGER NOT NULL,
    cluster_id          INTEGER NOT NULL,
    weight              REAL NOT NULL,           -- 该典型日权重
    representative_date TEXT,                    -- 代表日期
    boundary_json       TEXT NOT NULL,           -- 边界数据 JSON
    created_at          TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_clustering_task ON clustering_results(planning_task_id);
```

#### 3.3.3 优化迭代历史表

```sql
-- 存储在 capacity_planning.db 中
CREATE TABLE optimization_history (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    planning_task_id    TEXT NOT NULL REFERENCES capacity_planning_tasks(id),
    iteration           INTEGER NOT NULL,
    fitness             REAL NOT NULL,
    solution_json       TEXT NOT NULL,            -- 解向量 JSON
    evaluation_time_ms  INTEGER,                 -- 本次评估耗时
    created_at          TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_opt_history_task ON optimization_history(planning_task_id);
```

---

## 4. API 设计

### 4.1 REST API

| 路径 | 方法 | 说明 | 请求体 | 响应 |
|---|---|---|---|---|
| `/api/capacity-planning/variables` | POST | 获取可配置变量表单 | `{projectId, canvasId}` | `{variables: CapacityVariable[]}` |
| `/api/capacity-planning/create` | POST | 创建容量规划任务 | `CapacityPlanningConfig` | `{taskId, status}` |
| `/api/capacity-planning/{id}/start` | POST | 启动优化计算 | — | `{success}` |
| `/api/capacity-planning/{id}/cancel` | POST | 取消优化计算 | — | `{success}` |
| `/api/capacity-planning/{id}/status` | GET | 查询任务状态 | — | `CapacityPlanningTask` |
| `/api/capacity-planning/{id}/results` | GET | 获取优化结果 | — | `CapacityPlanningResult` |
| `/api/capacity-planning/{id}/apply` | POST | 应用最优配置到项目 | — | `{success, projectJson}` |
| `/api/capacity-planning/list` | GET | 列出规划任务 | query: `projectId?` | `{tasks: CapacityPlanningTask[]}` |
| `/api/capacity-planning/{id}` | DELETE | 删除规划任务 | — | `{success}` |

### 4.2 WebSocket `/ws/capacity-planning/{id}`

**服务端 → 客户端**：

```json
// 阶段变化
{ "type": "phase", "phase": "clustering", "message": "正在聚类计算..." }

// 优化进度
{
  "type": "progress",
  "iteration": 42,
  "totalIterations": 200,
  "bestFitness": 1234.56,
  "bestSolution": [200.0, 150.5, 80.0],
  "currentFitness": 1300.0
}

// 完成
{
  "type": "completed",
  "results": { /* CapacityPlanningResult */ }
}

// 失败
{ "type": "failed", "error": "求解失败: ..." }
```

### 4.3 API 详细设计

#### 4.3.1 获取可配置变量表单

```
POST /api/capacity-planning/variables
```

**请求体**：
```json
{
  "projectId": "project-xxx",
  "canvasId": "canvas-xxx"
}
```

**响应**：
```json
{
  "success": true,
  "data": {
    "variables": [
      {
        "componentId": "WT_001",
        "componentKey": "WT",
        "componentName": "风机1",
        "enabled": true,
        "lowerBound": 0,
        "upperBound": 500,
        "suggestedValue": 200,
        "unit": "kW"
      },
      {
        "componentId": "PV_001",
        "componentKey": "PV",
        "componentName": "光伏1",
        "enabled": true,
        "lowerBound": 0,
        "upperBound": 1000,
        "suggestedValue": 300,
        "unit": "kW"
      },
      {
        "componentId": "ES_001",
        "componentKey": "ES",
        "componentName": "储能1",
        "enabled": true,
        "lowerBound": 0,
        "upperBound": 500,
        "suggestedValue": 100,
        "unit": "kWh"
      }
    ]
  }
}
```

**后端逻辑**：
1. 读取项目的 `project.json`（画布配置）
2. 遍历所有组件，识别可优化设备类型（WT、PV、ES 等）
3. 根据组件当前配置生成默认的边界范围
4. 返回表单配置供前端展示

#### 4.3.2 创建容量规划任务

```
POST /api/capacity-planning/create
```

**请求体**：完整的 `CapacityPlanningConfig` JSON

**响应**：
```json
{
  "success": true,
  "data": {
    "taskId": "cp-xxx",
    "status": "configuring"
  }
}
```

#### 4.3.3 启动优化计算

```
POST /api/capacity-planning/{id}/start
```

**后端流程**：
1. 读取配置，验证参数完整性
2. 从项目 boundary.db 提取边界数据
3. 执行 K-means 聚类，生成典型日
4. 启动 BlackBoxOptim 优化循环
5. 每次迭代：生成仿真任务 → 运行 → 导出结果 → 经济评价 → 返回适应度
6. 优化完成后保存结果

---

## 5. 后端实现

### 5.1 目录结构

```
backend/
├── services/
│   ├── capacity_planning/
│   │   ├── planning_manager.jl      # 规划任务生命周期管理
│   │   ├── variable_detector.jl     # 变量检测与表单生成
│   │   ├── clustering_service.jl    # K-means 聚类服务
│   │   ├── optimization_runner.jl   # BlackBoxOptim 优化主循环
│   │   ├── economic_evaluator.jl    # 经济性评价（接口）
│   │   └── scenario_generator.jl    # 典型日场景生成
│   ├── task_manager.jl              # 现有：复用
│   ├── simulation_runner.jl         # 现有：复用
│   └── boundary_seeder.jl           # 现有：复用
├── routes/
│   ├── capacity_planning.jl         # 新增：容量规划路由
│   └── task.jl                      # 现有：复用
└── data/
    ├── capacity_planning.db         # 新增：容量规划元数据
    └── projects/
        └── <project_id>/
            └── boundary.db          # 现有：边界数据来源
```

### 5.2 核心模块实现

#### 5.2.1 变量检测服务 (`variable_detector.jl`)

```julia
# backend/services/capacity_planning/variable_detector.jl

"""
    detect_optimizable_variables(project_json::Dict) -> Vector{Dict}

从项目配置中检测可优化的设备变量。
返回每个变量的默认配置（上下界、建议值、单位等）。
"""
function detect_optimizable_variables(project_json::Dict)::Vector{Dict}
    variables = Dict{String,Any}[]

    # 定义可优化的组件类型及其默认参数范围
    OPTIMIZABLE_COMPONENTS = Dict(
        "WT" => Dict(
            name_prefix = "风机",
            capacity_field = "rated_power",
            unit = "kW",
            default_lower = 0,
            default_upper = 1000,
            default_suggested = 200
        ),
        "PV" => Dict(
            name_prefix = "光伏",
            capacity_field = "rated_power",
            unit = "kW",
            default_lower = 0,
            default_upper = 2000,
            default_suggested = 500
        ),
        "ES" => Dict(
            name_prefix = "储能",
            capacity_field = "capacity",
            unit = "kWh",
            default_lower = 0,
            default_upper = 1000,
            default_suggested = 200
        ),
        "CP" => Dict(
            name_prefix = "燃气轮机",
            capacity_field = "rated_power",
            unit = "kW",
            default_lower = 0,
            default_upper = 500,
            default_suggested = 100
        )
        # 可扩展其他组件类型
    )

    # 获取画布中的组件
    canvas = project_json["workspace"]["canvases"][1]  # 默认取第一个画布
    component_counter = Dict{String,Int}()

    for node in get(canvas, "nodes", [])
        comp_key = get(node, "componentKey", "")
        if !haskey(OPTIMIZABLE_COMPONENTS, comp_key)
            continue
        end

        comp_id = node["id"]
        comp_def = OPTIMIZABLE_COMPONENTS[comp_key]

        # 计数器用于命名
        component_counter[comp_key] = get(component_counter, comp_key, 0) + 1
        comp_name = "$(comp_def["name_prefix"])$(component_counter[comp_key])"

        # 从组件配置中提取当前容量值作为建议值
        current_capacity = get(
            get(node, "data", Dict()),
            "parameters",
            Dict()
        )
        suggested = get(current_capacity, comp_def["capacity_field"], comp_def["default_suggested"])

        push!(variables, Dict(
            "componentId" => comp_id,
            "componentKey" => comp_key,
            "componentName" => comp_name,
            "enabled" => true,
            "lowerBound" => comp_def["default_lower"],
            "upperBound" => comp_def["default_upper"],
            "suggestedValue" => suggested,
            "unit" => comp_def["unit"]
        ))
    end

    return variables
end
```

#### 5.2.2 K-means 聚类服务 (`clustering_service.jl`)

```julia
# backend/services/capacity_planning/clustering_service.jl

using Statistics
using Random

"""
    cluster_boundary_data(
        boundary_data::Dict{String, Vector{Float64}},
        num_clusters::Int;
        time_granularity::String = "1h",
        max_iterations::Int = 100
    ) -> Vector{TypicalDay}

对边界时序数据进行 K-means 聚类，生成典型日场景。

# 参数
- `boundary_data`: 边界数据字典，key 为变量名，value 为时序数据
- `num_clusters`: 聚类数量（典型日数量）
- `time_granularity`: 时间粒度
- `max_iterations`: K-means 最大迭代次数

# 返回
典型日列表，每个包含：聚类中心、权重、代表日期
"""
function cluster_boundary_data(
    boundary_data::Dict{String, Vector{Float64}},
    num_clusters::Int;
    time_granularity::String = "1h",
    max_iterations::Int = 100
)::Vector{Dict{String,Any}}

    # 1. 数据预处理：按日分割
    daily_profiles = split_into_daily_profiles(boundary_data, time_granularity)

    # 2. 构建特征矩阵
    feature_matrix = build_feature_matrix(daily_profiles)

    # 3. K-means 聚类
    assignments, centers = kmeans_clustering(
        feature_matrix,
        num_clusters;
        max_iter = max_iterations
    )

    # 4. 计算每个聚类的权重
    cluster_weights = calculate_cluster_weights(assignments, num_clusters)

    # 5. 找到每个聚类的代表日（最接近聚类中心的样本）
    representative_days = find_representative_days(
        feature_matrix,
        centers,
        assignments,
        daily_profiles
    )

    # 6. 构建典型日结果
    typical_days = Dict{String,Any}[]
    for k in 1:num_clusters
        push!(typical_days, Dict(
            "id" => k,
            "weight" => cluster_weights[k],
            "representativeDate" => representative_days[k]["date"],
            "boundaryData" => representative_days[k]["data"]
        ))
    end

    return typical_days
end

"""
    kmeans_clustering(X::Matrix{Float64}, k::Int; max_iter=100)

K-means 聚类核心算法。
"""
function kmeans_clustering(
    X::Matrix{Float64},
    k::Int;
    max_iter::Int = 100,
    tol::Float64 = 1e-4
)
    n_samples, n_features = size(X)

    # K-means++ 初始化
    centers = kmeans_pp_init(X, k)

    assignments = zeros(Int, n_samples)
    prev_cost = Inf

    for iter in 1:max_iter
        # 分配每个样本到最近的聚类中心
        for i in 1:n_samples
            min_dist = Inf
            for j in 1:k
                dist = sum((X[i, :] - centers[j, :]) .^ 2)
                if dist < min_dist
                    min_dist = dist
                    assignments[i] = j
                end
            end
        end

        # 更新聚类中心
        for j in 1:k
            members = X[assignments .== j, :]
            if !isempty(members)
                centers[j, :] = mean(members, dims=1)
            end
        end

        # 计算当前代价
        cost = 0.0
        for i in 1:n_samples
            cost += sum((X[i, :] - centers[assignments[i], :]) .^ 2)
        end

        # 收敛判断
        if abs(prev_cost - cost) < tol
            @info "K-means converged at iteration $iter"
            break
        end
        prev_cost = cost
    end

    return assignments, centers
end

"""
    kmeans_pp_init(X::Matrix{Float64}, k::Int)

K-means++ 初始化策略。
"""
function kmeans_pp_init(X::Matrix{Float64}, k::Int)
    n_samples = size(X, 1)
    centers = zeros(k, size(X, 2))

    # 随机选择第一个中心
    centers[1, :] = X[rand(1:n_samples), :]

    for j in 2:k
        # 计算每个样本到最近已选中心的距离
        distances = zeros(n_samples)
        for i in 1:n_samples
            min_dist = Inf
            for c in 1:j-1
                dist = sum((X[i, :] - centers[c, :]) .^ 2)
                min_dist = min(min_dist, dist)
            end
            distances[i] = min_dist
        end

        # 按概率选择下一个中心
        probs = distances ./ sum(distances)
        cumprobs = cumsum(probs)
        r = rand()
        idx = findfirst(cumprobs .>= r)
        centers[j, :] = X[idx, :]
    end

    return centers
end
```

#### 5.2.3 优化求解服务 (`optimization_runner.jl`)

```julia
# backend/services/capacity_planning/optimization_runner.jl

using BlackBoxOptim

"""
    run_capacity_optimization(
        planning_task_id::String,
        config::Dict,
        typical_days::Vector{Dict},
        boundary_db_path::String
    ) -> Dict

运行容量优化求解主函数。

# 流程
1. 构建优化问题（目标函数、约束、搜索空间）
2. 调用 BlackBoxOptim 求解
3. 每次评估：生成仿真参数 → 运行仿真 → 经济评价 → 返回适应度
4. 保存优化历史和最终结果
"""
function run_capacity_optimization(
    planning_task_id::String,
    config::Dict,
    typical_days::Vector{Dict{String,Any}},
    boundary_db_path::String
)::Dict{String,Any}

    # 1. 提取配置
    variables = config["variables"]
    opt_config = config["optimization"]
    econ_config = config["economic"]

    # 2. 构建搜索空间（仅启用的变量）
    enabled_vars = filter(v -> v["enabled"], variables)
    search_space = Float64[]
    for var in enabled_vars
        push!(search_space, (var["lowerBound"], var["upperBound"]))
    end

    # 3. 构建目标函数
    function objective(solution::Vector{Float64})::Float64
        # 将解向量映射回完整变量配置
        full_solution = map_solution_to_variables(solution, variables, enabled_vars)

        # 生成仿真配置
        sim_config = build_simulation_config(config, full_solution)

        # 对每个典型日运行仿真
        total_cost = 0.0
        for day in typical_days
            # 创建临时任务
            task_id = create_evaluation_task(
                planning_task_id,
                sim_config,
                day["boundaryData"]
            )

            # 运行仿真
            run_evaluation_task(task_id)

            # 导出结果并经济评价
            sim_results = export_task_results(task_id)
            day_cost = evaluate_economics(sim_results, econ_config)

            # 按权重累加
            total_cost += day_cost * day["weight"]

            # 清理临时任务
            cleanup_evaluation_task(task_id)
        end

        # 记录优化历史
        save_optimization_iteration(
            planning_task_id,
            length(get_optimization_history(planning_task_id)) + 1,
            total_cost,
            solution
        )

        return total_cost
    end

    # 4. 运行 BlackBoxOptim
    result = bboptimize(
        objective;
        SearchSpace = [(_, _) for (lo, hi) in search_space],
        Method = Symbol(opt_config["algorithm"]),
        MaxFuncEvals = opt_config["maxEvaluations"],
        PopulationSize = opt_config["populationSize"],
        TargetFitness = get(opt_config, "targetFitness", Inf),
        RandomSeed = get(opt_config, "seed", rand(1:100000)),
        TraceMode = :silent
    )

    # 5. 提取最优解
    best_solution = best_candidate(result)
    best_fitness = best_fitness(result)

    # 6. 构建最终结果
    optimal_variables = map_solution_to_variables(best_solution, variables, enabled_vars)

    return Dict(
        "optimalVariables" => optimal_variables,
        "totalCost" => best_fitness,
        "convergenceHistory" => get_optimization_history(planning_task_id)
    )
end

"""
    map_solution_to_variables(solution, all_vars, enabled_vars)

将优化算法的解向量映射回完整的变量配置。
"""
function map_solution_to_variables(
    solution::Vector{Float64},
    all_vars::Vector,
    enabled_vars::Vector
)
    result = Dict{String,Float64}()
    sol_idx = 1

    for var in all_vars
        if var["enabled"]
            result[var["componentId"]] = solution[sol_idx]
            sol_idx += 1
        else
            result[var["componentId"]] = var["fixedValue"]
        end
    end

    return result
end

"""
    build_simulation_config(config, solution)

根据优化变量值构建仿真配置。
"""
function build_simulation_config(config::Dict, solution::Dict{String,Float64})
    # 深拷贝原始项目配置
    project_json = deepcopy(config["projectJson"])

    # 更新组件容量参数
    canvas = project_json["workspace"]["canvases"][1]
    for node in get(canvas, "nodes", [])
        comp_id = node["id"]
        if haskey(solution, comp_id)
            # 更新组件参数
            if !haskey(node["data"], "parameters")
                node["data"]["parameters"] = Dict()
            end

            comp_key = node["componentKey"]
            capacity_field = get_capacity_field(comp_key)
            if capacity_field !== nothing
                node["data"]["parameters"][capacity_field] = solution[comp_id]
            end
        end
    end

    return project_json
end

"""
    get_capacity_field(comp_key::String)

获取组件类型的容量字段名。
"""
function get_capacity_field(comp_key::String)
    FIELD_MAP = Dict(
        "WT" => "rated_power",
        "PV" => "rated_power",
        "ES" => "capacity",
        "CP" => "rated_power"
    )
    return get(FIELD_MAP, comp_key, nothing)
end
```

#### 5.2.4 经济评价接口 (`economic_evaluator.jl`)

```julia
# backend/services/capacity_planning/economic_evaluator.jl

"""
    evaluate_economics(sim_results::Dict, config::Dict) -> Float64

根据仿真结果进行经济性评价，返回总成本（适应度值）。

# 参数
- `sim_results`: 仿真结果数据
- `config`: 经济评价配置

# 返回
总成本（万元），作为优化算法的适应度值

# 注意
此函数为接口定义，具体评价逻辑需根据业务需求实现。
"""
function evaluate_economics(sim_results::Dict, config::Dict)::Float64
    # TODO: 实现具体的经济评价逻辑
    # 以下为框架示例：

    # 1. 提取仿真结果中的关键指标
    # total_generation = sim_results["totalGeneration"]      # 总发电量 (kWh)
    # total_consumption = sim_results["totalConsumption"]    # 总用电量 (kWh)
    # total_storage_cycles = sim_results["storageCycles"]    # 储能循环次数

    # 2. 计算投资成本
    # investment_cost = calculate_investment_cost(sim_results, config)

    # 3. 计算运维成本
    # maintenance_cost = calculate_maintenance_cost(sim_results, config)

    # 4. 计算燃料成本（如有）
    # fuel_cost = calculate_fuel_cost(sim_results, config)

    # 5. 计算收益
    # revenue = calculate_revenue(sim_results, config)

    # 6. 计算净现值（NPV）
    # npv = calculate_npv(investment_cost, maintenance_cost, fuel_cost, revenue, config)

    # 暂时返回一个占位值
    @warn "evaluate_economics: 使用占位实现，请完成具体评价逻辑"
    return 0.0
end

"""
    calculate_annual_cost(capacities::Dict, config::Dict) -> Float64

计算年化成本（ACO）。
"""
function calculate_annual_cost(capacities::Dict, config::Dict)::Float64
    # 年化投资成本 = 总投资 × CRF
    # CRF = r(1+r)^n / ((1+r)^n - 1)
    # 其中 r = 折现率, n = 项目寿命

    # TODO: 实现具体计算
    return 0.0
end

"""
    calculate_lcoe(total_cost::Float64, total_generation::Float64) -> Float64

计算平准化度电成本（LCOE）。
"""
function calculate_lcoe(total_cost::Float64, total_generation::Float64)::Float64
    if total_generation == 0
        return Inf
    end
    return total_cost / total_generation
end
```

#### 5.2.5 规划任务管理 (`planning_manager.jl`)

```julia
# backend/services/capacity_planning/planning_manager.jl

using UUIDs
using Dates

# 规划任务状态常量
const PL_STATUS_CONFIGURING = "configuring"
const PL_STATUS_CLUSTERING  = "clustering"
const PL_STATUS_OPTIMIZING  = "optimizing"
const PL_STATUS_EVALUATING  = "evaluating"
const PL_STATUS_COMPLETED   = "completed"
const PL_STATUS_FAILED      = "failed"
const PL_STATUS_CANCELLED   = "cancelled"

# 容量规划 DB 路径
const CAPACITY_PLANNING_DB = joinpath(BACKEND_DATA_DIR, "capacity_planning.db")

# 规划任务上下文
mutable struct PlanningContext
    id::String
    signal_ch::Channel{String}
    subscribers::Vector{Channel{Dict}}
    julia_task::Union{Task, Nothing}
end

const PLANNING_CONTEXTS = Dict{String, PlanningContext}()
const PLANNING_CONTEXTS_LOCK = ReentrantLock()

"""
    init_capacity_planning_db()

初始化容量规划数据库。
"""
function init_capacity_planning_db()
    db = SQLite.DB(CAPACITY_PLANNING_DB)
    DBInterface.execute(db, """
        CREATE TABLE IF NOT EXISTS capacity_planning_tasks (
            id              TEXT PRIMARY KEY,
            project_id      TEXT NOT NULL,
            canvas_id       TEXT NOT NULL,
            name            TEXT,
            status          TEXT NOT NULL,
            config_json     TEXT NOT NULL,
            progress_json   TEXT,
            results_json    TEXT,
            created_at      TEXT NOT NULL,
            updated_at      TEXT NOT NULL,
            started_at      TEXT,
            finished_at     TEXT,
            error_message   TEXT
        )
    """)
    DBInterface.execute(db, """
        CREATE TABLE IF NOT EXISTS clustering_results (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            planning_task_id TEXT NOT NULL,
            num_clusters    INTEGER NOT NULL,
            cluster_id      INTEGER NOT NULL,
            weight          REAL NOT NULL,
            representative_date TEXT,
            boundary_json   TEXT NOT NULL,
            created_at      TEXT DEFAULT (datetime('now'))
        )
    """)
    DBInterface.execute(db, """
        CREATE TABLE IF NOT EXISTS optimization_history (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            planning_task_id TEXT NOT NULL,
            iteration       INTEGER NOT NULL,
            fitness         REAL NOT NULL,
            solution_json   TEXT NOT NULL,
            evaluation_time_ms INTEGER,
            created_at      TEXT DEFAULT (datetime('now'))
        )
    """)
    return db
end

"""
    create_planning_task(config::Dict) -> String

创建容量规划任务，返回任务 ID。
"""
function create_planning_task(config::Dict)::String
    task_id = "cp-" * string(uuid4())
    now_s = Dates.format(Dates.now(), Dates.ISODateTimeFormat)

    db = init_capacity_planning_db()
    DBInterface.execute(db, """
        INSERT INTO capacity_planning_tasks
        (id, project_id, canvas_id, name, status, config_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, [
        task_id,
        config["projectId"],
        config["canvasId"],
        get(config, "name", "容量规划任务"),
        PL_STATUS_CONFIGURING,
        JSON3.write(config),
        now_s,
        now_s
    ])

    return task_id
end

"""
    update_planning_status!(task_id::String, status::String; error_message=nothing)

更新规划任务状态。
"""
function update_planning_status!(
    task_id::String,
    status::String;
    error_message::Union{String,Nothing} = nothing
)
    db = init_capacity_planning_db()
    now_s = Dates.format(Dates.now(), Dates.ISODateTimeFormat)

    if status in (PL_STATUS_COMPLETED, PL_STATUS_FAILED, PL_STATUS_CANCELLED)
        DBInterface.execute(db, """
            UPDATE capacity_planning_tasks
            SET status=?, error_message=?, finished_at=?, updated_at=?
            WHERE id=?
        """, [status, error_message, now_s, now_s, task_id])
    else
        DBInterface.execute(db, """
            UPDATE capacity_planning_tasks
            SET status=?, error_message=?, updated_at=?
            WHERE id=?
        """, [status, error_message, now_s, task_id])
    end
end

"""
    save_clustering_results(task_id::String, typical_days::Vector{Dict})

保存聚类结果。
"""
function save_clustering_results(task_id::String, typical_days::Vector{Dict})
    db = init_capacity_planning_db()

    for day in typical_days
        DBInterface.execute(db, """
            INSERT INTO clustering_results
            (planning_task_id, num_clusters, cluster_id, weight, representative_date, boundary_json)
            VALUES (?, ?, ?, ?, ?, ?)
        """, [
            task_id,
            length(typical_days),
            day["id"],
            day["weight"],
            get(day, "representativeDate", ""),
            JSON3.write(day["boundaryData"])
        ])
    end
end

"""
    save_optimization_iteration(task_id::String, iteration::Int, fitness::Float64, solution::Vector{Float64})

保存优化迭代记录。
"""
function save_optimization_iteration(
    task_id::String,
    iteration::Int,
    fitness::Float64,
    solution::Vector{Float64}
)
    db = init_capacity_planning_db()
    DBInterface.execute(db, """
        INSERT INTO optimization_history
        (planning_task_id, iteration, fitness, solution_json)
        VALUES (?, ?, ?, ?)
    """, [task_id, iteration, fitness, JSON3.write(solution)])
end

"""
    spawn_planning_task(task_id::String, config::Dict)

启动容量规划任务协程。
"""
function spawn_planning_task(task_id::String, config::Dict)
    ctx = PlanningContext(
        task_id,
        Channel{String}(4),
        Channel{Dict}[],
        nothing
    )

    lock(PLANNING_CONTEXTS_LOCK) do
        PLANNING_CONTEXTS[task_id] = ctx
    end

    jl_task = @async try
        run_planning_task(task_id, config)
    catch e
        bt = catch_backtrace()
        @error "planning task $task_id: unhandled exception" exception=(e, bt)
        update_planning_status!(task_id, PL_STATUS_FAILED,
            error_message=sprint(showerror, e))
        broadcast_planning_event(ctx, Dict(
            "type" => "failed",
            "error" => sprint(showerror, e)
        ))
    finally
        lock(PLANNING_CONTEXTS_LOCK) do
            delete!(PLANNING_CONTEXTS, task_id)
        end
    end

    ctx.julia_task = jl_task
    return jl_task
end

"""
    run_planning_task(task_id::String, config::Dict)

容量规划任务主流程。
"""
function run_planning_task(task_id::String, config::Dict)
    project_id = config["projectId"]

    try
        # 1. 获取边界数据路径
        boundary_db_path = joinpath(
            BACKEND_DATA_DIR, "projects", project_id, "boundary.db"
        )

        # 2. 阶段 1: 聚类
        update_planning_status!(task_id, PL_STATUS_CLUSTERING)
        broadcast_planning_event(get_context(task_id), Dict(
            "type" => "phase",
            "phase" => "clustering",
            "message" => "正在提取边界数据并聚类..."
        ))

        # 提取边界数据
        boundary_data = extract_boundary_data(boundary_db_path)

        # 执行聚类
        typical_days = cluster_boundary_data(
            boundary_data,
            config["clustering"]["numClusters"];
            time_granularity = get(config["clustering"], "timeGranularity", "1h")
        )

        # 保存聚类结果
        save_clustering_results(task_id, typical_days)

        # 3. 阶段 2: 优化
        update_planning_status!(task_id, PL_STATUS_OPTIMIZING)
        broadcast_planning_event(get_context(task_id), Dict(
            "type" => "phase",
            "phase" => "optimizing",
            "message" => "开始优化求解..."
        ))

        # 运行优化
        results = run_capacity_optimization(
            task_id,
            config,
            typical_days,
            boundary_db_path
        )

        # 4. 阶段 3: 经济评价
        update_planning_status!(task_id, PL_STATUS_EVALUATING)
        broadcast_planning_event(get_context(task_id), Dict(
            "type" => "phase",
            "phase" => "evaluating",
            "message" => "正在进行经济性评价..."
        ))

        # 最终经济评价
        final_results = finalize_economic_evaluation(results, config["economic"])

        # 5. 保存结果
        db = init_capacity_planning_db()
        DBInterface.execute(db, """
            UPDATE capacity_planning_tasks
            SET results_json=?
            WHERE id=?
        """, [JSON3.write(final_results), task_id])

        # 6. 完成
        update_planning_status!(task_id, PL_STATUS_COMPLETED)
        broadcast_planning_event(get_context(task_id), Dict(
            "type" => "completed",
            "results" => final_results
        ))

    catch e
        bt = catch_backtrace()
        @error "planning task $task_id failed" exception=(e, bt)
        update_planning_status!(task_id, PL_STATUS_FAILED,
            error_message=sprint(showerror, e))
        broadcast_planning_event(get_context(task_id), Dict(
            "type" => "failed",
            "error" => sprint(showerror, e)
        ))
    end
end
```

### 5.3 路由实现 (`routes/capacity_planning.jl`)

```julia
# backend/routes/capacity_planning.jl

# ───── POST /api/capacity-planning/variables ─────
@post "/api/capacity-planning/variables" function (req)
    try
        body = JSON3.read(req.body, Dict)
        project_id = require_string(body, "projectId")
        canvas_id = require_string(body, "canvasId")

        # 读取项目配置
        project_path = get_project_json_path(project_id)
        if !isfile(project_path)
            return json_error("项目不存在: $project_id")
        end

        project_json = JSON3.read(read(project_path, String), Dict)

        # 检测可优化变量
        variables = detect_optimizable_variables(project_json)

        return json_success(data = Dict("variables" => variables))
    catch e
        return json_error("检测变量异常: $(sprint(showerror, e))")
    end
end

# ───── POST /api/capacity-planning/create ─────
@post "/api/capacity-planning/create" function (req)
    try
        config = JSON3.read(req.body, Dict)

        # 验证配置
        if !haskey(config, "projectId") || !haskey(config, "variables")
            return json_error("缺少必要配置字段")
        end

        # 创建规划任务
        task_id = create_planning_task(config)

        return json_success(data = Dict(
            "taskId" => task_id,
            "status" => PL_STATUS_CONFIGURING
        ))
    catch e
        return json_error("创建规划任务异常: $(sprint(showerror, e))")
    end
end

# ───── POST /api/capacity-planning/{id}/start ─────
@post "/api/capacity-planning/{id}/start" function (req, id)
    try
        # 读取任务配置
        db = init_capacity_planning_db()
        rows = DBInterface.execute(db,
            "SELECT config_json FROM capacity_planning_tasks WHERE id=?",
            [id]
        ) |> columntable

        if isempty(rows[1])
            return json_error("规划任务不存在: $id")
        end

        config = JSON3.read(rows[1][1], Dict)

        # 启动任务协程
        spawn_planning_task(id, config)

        return json_success(message = "规划任务已启动")
    catch e
        return json_error("启动规划任务异常: $(sprint(showerror, e))")
    end
end

# ───── GET /api/capacity-planning/{id}/status ─────
@get "/api/capacity-planning/{id}/status" function (req, id)
    try
        db = init_capacity_planning_db()
        rows = DBInterface.execute(db,
            "SELECT * FROM capacity_planning_tasks WHERE id=?",
            [id]
        ) |> columntable

        if isempty(rows[1])
            return json_error("规划任务不存在: $id")
        end

        task = Dict(
            "id" => rows[1][1],
            "projectId" => rows[2][1],
            "canvasId" => rows[3][1],
            "name" => rows[4][1],
            "status" => rows[5][1],
            "config" => JSON3.read(rows[6][1], Dict),
            "progress" => rows[7][1] !== nothing ? JSON3.read(rows[7][1], Dict) : nothing,
            "results" => rows[8][1] !== nothing ? JSON3.read(rows[8][1], Dict) : nothing,
            "createdAt" => rows[9][1],
            "updatedAt" => rows[10][1],
            "startedAt" => rows[11][1],
            "finishedAt" => rows[12][1],
            "errorMessage" => rows[13][1]
        )

        return json_success(data = task)
    catch e
        return json_error("查询规划任务状态异常: $(sprint(showerror, e))")
    end
end

# ───── POST /api/capacity-planning/{id}/apply ─────
@post "/api/capacity-planning/{id}/apply" function (req, id)
    try
        # 读取优化结果
        db = init_capacity_planning_db()
        rows = DBInterface.execute(db,
            "SELECT results_json, project_id FROM capacity_planning_tasks WHERE id=?",
            [id]
        ) |> columntable

        if isempty(rows[1]) || rows[1][1] === nothing
            return json_error("规划任务不存在或无结果: $id")
        end

        results = JSON3.read(rows[1][1], Dict)
        project_id = rows[2][1]

        # 读取当前项目配置
        project_path = get_project_json_path(project_id)
        project_json = JSON3.read(read(project_path, String), Dict)

        # 应用最优配置
        optimal_vars = results["optimalVariables"]
        canvas = project_json["workspace"]["canvases"][1]

        for node in get(canvas, "nodes", [])
            comp_id = node["id"]
            if haskey(optimal_vars, comp_id)
                if !haskey(node["data"], "parameters")
                    node["data"]["parameters"] = Dict()
                end

                comp_key = node["componentKey"]
                capacity_field = get_capacity_field(comp_key)
                if capacity_field !== nothing
                    node["data"]["parameters"][capacity_field] = optimal_vars[comp_id]
                end
            end
        end

        # 保存更新后的项目配置
        write(project_path, JSON3.write(project_json))

        return json_success(data = Dict(
            "projectJson" => project_json,
            "message" => "最优配置已应用到项目"
        ))
    catch e
        return json_error("应用配置异常: $(sprint(showerror, e))")
    end
end

# ───── WS /ws/capacity-planning/{id} ─────
@websocket "/ws/capacity-planning/*" function (ws; request)
    m = match(r"^/ws/capacity-planning/([^/]+)", String(request.target))
    task_id = m === nothing ? "" : String(m.captures[1])

    ctx = lock(PLANNING_CONTEXTS_LOCK) do
        get(PLANNING_CONTEXTS, task_id, nothing)
    end

    if ctx === nothing
        # 任务未运行，轮询状态
        # ... 类似 task.jl 的实现
        return
    end

    ch = subscribe_planning(ctx)
    try
        # 推送当前状态
        # ... 类似 task.jl 的实现

        # 转发事件
        forward_task = @async begin
            try
                while true
                    evt = take!(ch)
                    send(ws, JSON3.write(evt))
                end
            catch e
                if !(e isa InvalidStateException)
                    @warn "[PlanningWS] forward error" exception=(e, catch_backtrace())
                end
            end
        end

        # 接收客户端消息
        for msg in ws
            # 处理取消等信号
        end
    finally
        unsubscribe_planning(ctx, ch)
    end
end
```

---

## 6. 前端实现

### 6.1 目录结构

```
app/
├── pages/
│   ├── capacity-planning/
│   │   ├── index.vue              # 容量规划列表页
│   │   └── [taskId].vue           # 容量规划详情页
│   └── editor/
│       └── [projectId].vue        # 现有：添加容量规划按钮
├── components/
│   ├── capacity-planning/
│   │   ├── VariableConfigForm.vue # 变量配置表单
│   │   ├── ClusteringConfig.vue   # 聚类配置组件
│   │   ├── OptimizationConfig.vue # 优化算法配置
│   │   ├── EconomicConfig.vue     # 经济评价配置
│   │   ├── OptimizationProgress.vue # 优化进度展示
│   │   ├── ResultPanel.vue        # 结果展示面板
│   │   └── ConvergenceChart.vue   # 收敛曲线图
│   └── ...existing components...
├── composables/
│   ├── api/
│   │   ├── useCapacityPlanningApi.ts # 容量规划 API
│   │   └── ...existing apis...
│   └── ...existing composables...
└── types/
    └── capacity-planning.ts       # 类型定义
```

### 6.2 类型定义 (`types/capacity-planning.ts`)

```typescript
// types/capacity-planning.ts

// 设备优化变量配置
export interface CapacityVariable {
  componentId: string
  componentKey: string
  componentName: string
  enabled: boolean
  fixedValue?: number
  lowerBound?: number
  upperBound?: number
  suggestedValue?: number
  unit: string
}

// 聚类配置
export interface ClusteringConfig {
  method: 'kmeans'
  numClusters: number
  features: string[]
  timeGranularity: string
  seasonWeights?: Record<string, number>
}

// 优化算法配置
export interface OptimizationConfig {
  algorithm: 'adaptive_de' | 'xnes' | 'separable_nes' | 'dxnes'
  maxEvaluations: number
  populationSize: number
  targetFitness?: number
  seed?: number
}

// 经济性评价配置
export interface EconomicConfig {
  projectLifespan: number
  discountRate: number
  electricityPrice: number
  carbonPrice?: number
}

// 完整容量规划配置
export interface CapacityPlanningConfig {
  id: string
  projectId: string
  canvasId: string
  name: string
  variables: CapacityVariable[]
  clustering: ClusteringConfig
  optimization: OptimizationConfig
  economic: EconomicConfig
  createdAt: string
  updatedAt: string
}

// 规划任务状态
export type CapacityPlanningStatus =
  | 'configuring'
  | 'clustering'
  | 'optimizing'
  | 'evaluating'
  | 'completed'
  | 'failed'
  | 'cancelled'

// 规划任务
export interface CapacityPlanningTask {
  id: string
  projectId: string
  config: CapacityPlanningConfig
  status: CapacityPlanningStatus
  progress?: {
    phase: string
    currentIteration: number
    totalIterations: number
    bestFitness: number
    bestSolution: number[]
  }
  results?: CapacityPlanningResult
  createdAt: string
  updatedAt: string
  startedAt?: string
  finishedAt?: string
  errorMessage?: string
}

// 规划结果
export interface CapacityPlanningResult {
  optimalVariables: {
    componentId: string
    optimalCapacity: number
    unit: string
  }[]
  totalCost: number
  annualCost: number
  economicIndicators: {
    npv: number
    irr: number
    paybackPeriod: number
    lcoe: number
  }
  convergenceHistory: {
    iteration: number
    fitness: number
  }[]
  typicalDays: TypicalDay[]
}

// 典型日
export interface TypicalDay {
  id: number
  weight: number
  representativeDate: string
  boundaryData: Record<string, number[]>
}
```

### 6.3 API 封装 (`composables/api/useCapacityPlanningApi.ts`)

```typescript
// composables/api/useCapacityPlanningApi.ts

import type {
  CapacityPlanningConfig,
  CapacityPlanningTask,
  CapacityPlanningResult,
  CapacityVariable
} from '~~/types/capacity-planning'

export const useCapacityPlanningApi = () => {
  const config = useRuntimeConfig()
  const baseUrl = config.public.apiBaseUrl || '/api/v1'

  /**
   * 获取可配置变量表单
   */
  const getVariables = async (
    projectId: string,
    canvasId: string
  ): Promise<CapacityVariable[]> => {
    const response = await $fetch<{ data: { variables: CapacityVariable[] } }>(
      `${baseUrl}/capacity-planning/variables`,
      {
        method: 'POST',
        body: { projectId, canvasId }
      }
    )
    return response.data.variables
  }

  /**
   * 创建容量规划任务
   */
  const createTask = async (
    config: Omit<CapacityPlanningConfig, 'id' | 'createdAt' | 'updatedAt'>
  ): Promise<{ taskId: string; status: string }> => {
    const response = await $fetch<{ data: { taskId: string; status: string } }>(
      `${baseUrl}/capacity-planning/create`,
      {
        method: 'POST',
        body: config
      }
    )
    return response.data
  }

  /**
   * 启动优化计算
   */
  const startOptimization = async (taskId: string): Promise<void> => {
    await $fetch(`${baseUrl}/capacity-planning/${taskId}/start`, {
      method: 'POST'
    })
  }

  /**
   * 取消优化计算
   */
  const cancelOptimization = async (taskId: string): Promise<void> => {
    await $fetch(`${baseUrl}/capacity-planning/${taskId}/cancel`, {
      method: 'POST'
    })
  }

  /**
   * 查询任务状态
   */
  const getTaskStatus = async (taskId: string): Promise<CapacityPlanningTask> => {
    const response = await $fetch<{ data: CapacityPlanningTask }>(
      `${baseUrl}/capacity-planning/${taskId}/status`
    )
    return response.data
  }

  /**
   * 获取优化结果
   */
  const getResults = async (taskId: string): Promise<CapacityPlanningResult> => {
    const response = await $fetch<{ data: CapacityPlanningResult }>(
      `${baseUrl}/capacity-planning/${taskId}/results`
    )
    return response.data
  }

  /**
   * 应用最优配置到项目
   */
  const applyOptimalConfig = async (
    taskId: string
  ): Promise<{ projectJson: any }> => {
    const response = await $fetch<{ data: { projectJson: any } }>(
      `${baseUrl}/capacity-planning/${taskId}/apply`,
      { method: 'POST' }
    )
    return response.data
  }

  /**
   * 列出规划任务
   */
  const listTasks = async (
    projectId?: string
  ): Promise<CapacityPlanningTask[]> => {
    const params = projectId ? `?projectId=${projectId}` : ''
    const response = await $fetch<{ data: { tasks: CapacityPlanningTask[] } }>(
      `${baseUrl}/capacity-planning/list${params}`
    )
    return response.data.tasks
  }

  /**
   * 删除规划任务
   */
  const deleteTask = async (taskId: string): Promise<void> => {
    await $fetch(`${baseUrl}/capacity-planning/${taskId}`, {
      method: 'DELETE'
    })
  }

  /**
   * 订阅优化进度（WebSocket）
   */
  const subscribeProgress = (
    taskId: string,
    onProgress: (data: any) => void,
    onComplete: (results: CapacityPlanningResult) => void,
    onError: (error: string) => void
  ): (() => void) => {
    const wsUrl = `${config.public.wsBaseUrl || 'ws://localhost:8080'}/ws/capacity-planning/${taskId}`
    const ws = new WebSocket(wsUrl)

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data)
      switch (data.type) {
        case 'phase':
        case 'progress':
          onProgress(data)
          break
        case 'completed':
          onComplete(data.results)
          break
        case 'failed':
          onError(data.error)
          break
      }
    }

    ws.onerror = () => {
      onError('WebSocket 连接失败')
    }

    return () => {
      ws.close()
    }
  }

  return {
    getVariables,
    createTask,
    startOptimization,
    cancelOptimization,
    getTaskStatus,
    getResults,
    applyOptimalConfig,
    listTasks,
    deleteTask,
    subscribeProgress
  }
}
```

### 6.4 核心组件实现

#### 6.4.1 变量配置表单 (`VariableConfigForm.vue`)

```vue
<!-- app/components/capacity-planning/VariableConfigForm.vue -->

<script setup lang="ts">
import type { CapacityVariable } from '~~/types/capacity-planning'

interface Props {
  variables: CapacityVariable[]
}

interface Emits {
  (e: 'update:variables', value: CapacityVariable[]): void
}

const props = defineProps<Props>()
const emit = defineEmits<Emits>()

const updateVariable = (index: number, updates: Partial<CapacityVariable>) => {
  const newVariables = [...props.variables]
  newVariables[index] = { ...newVariables[index], ...updates }
  emit('update:variables', newVariables)
}

const toggleVariable = (index: number) => {
  const variable = props.variables[index]
  updateVariable(index, {
    enabled: !variable.enabled,
    fixedValue: variable.enabled ? variable.suggestedValue : undefined,
    lowerBound: variable.enabled ? undefined : variable.lowerBound,
    upperBound: variable.enabled ? undefined : variable.upperBound
  })
}
</script>

<template>
  <div class="space-y-4">
    <h3 class="text-lg font-semibold text-app-text">设备容量配置</h3>
    <p class="text-sm text-app-muted">
      选择需要优化的设备，设置容量搜索范围。未勾选的设备将使用固定容量值。
    </p>

    <div class="space-y-3">
      <div
        v-for="(variable, index) in variables"
        :key="variable.componentId"
        class="rounded-lg border border-app-border p-4 transition-all"
        :class="variable.enabled ? 'bg-primary/5 border-primary/20' : 'bg-app-panel'"
      >
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-3">
            <input
              type="checkbox"
              :checked="variable.enabled"
              @change="toggleVariable(index)"
              class="h-4 w-4 rounded border-app-border text-primary focus:ring-primary"
            />
            <div>
              <span class="font-medium text-app-text">{{ variable.componentName }}</span>
              <span class="ml-2 text-xs text-app-muted">({{ variable.componentKey }})</span>
            </div>
          </div>
          <span class="text-sm text-app-muted">{{ variable.unit }}</span>
        </div>

        <!-- 固定值模式 -->
        <div v-if="!variable.enabled" class="flex items-center gap-2">
          <label class="text-sm text-app-muted">固定容量：</label>
          <input
            type="number"
            :value="variable.fixedValue"
            @input="updateVariable(index, { fixedValue: Number(($event.target as HTMLInputElement).value) })"
            class="field-input-sm w-32"
            :placeholder="String(variable.suggestedValue)"
          />
          <span class="text-sm text-app-muted">{{ variable.unit }}</span>
        </div>

        <!-- 优化变量模式 -->
        <div v-else class="grid grid-cols-3 gap-3">
          <div>
            <label class="text-xs text-app-muted">搜索下界</label>
            <input
              type="number"
              :value="variable.lowerBound"
              @input="updateVariable(index, { lowerBound: Number(($event.target as HTMLInputElement).value) })"
              class="field-input-sm w-full"
            />
          </div>
          <div>
            <label class="text-xs text-app-muted">建议值</label>
            <input
              type="number"
              :value="variable.suggestedValue"
              @input="updateVariable(index, { suggestedValue: Number(($event.target as HTMLInputElement).value) })"
              class="field-input-sm w-full"
            />
          </div>
          <div>
            <label class="text-xs text-app-muted">搜索上界</label>
            <input
              type="number"
              :value="variable.upperBound"
              @input="updateVariable(index, { upperBound: Number(($event.target as HTMLInputElement).value) })"
              class="field-input-sm w-full"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
```

#### 6.4.2 优化进度展示 (`OptimizationProgress.vue`)

```vue
<!-- app/components/capacity-planning/OptimizationProgress.vue -->

<script setup lang="ts">
import type { CapacityPlanningStatus } from '~~/types/capacity-planning'

interface Props {
  status: CapacityPlanningStatus
  phase?: string
  currentIteration?: number
  totalIterations?: number
  bestFitness?: number
}

defineProps<Props>()

const statusLabels: Record<CapacityPlanningStatus, string> = {
  configuring: '配置中',
  clustering: '聚类计算',
  optimizing: '优化求解',
  evaluating: '经济评价',
  completed: '已完成',
  failed: '失败',
  cancelled: '已取消'
}

const statusColors: Record<CapacityPlanningStatus, string> = {
  configuring: 'text-app-muted',
  clustering: 'text-blue-500',
  optimizing: 'text-primary',
  evaluating: 'text-yellow-500',
  completed: 'text-green-500',
  failed: 'text-red-500',
  cancelled: 'text-orange-500'
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h3 class="text-lg font-semibold text-app-text">优化进度</h3>
      <span :class="statusColors[status]">
        {{ statusLabels[status] }}
      </span>
    </div>

    <!-- 进度条 -->
    <div v-if="status === 'optimizing' && totalIterations" class="space-y-2">
      <div class="flex justify-between text-sm">
        <span class="text-app-muted">迭代次数</span>
        <span class="text-app-text">{{ currentIteration }} / {{ totalIterations }}</span>
      </div>
      <div class="h-2 bg-app-panel rounded-full overflow-hidden">
        <div
          class="h-full bg-primary transition-all duration-300"
          :style="{ width: `${((currentIteration || 0) / totalIterations) * 100}%` }"
        />
      </div>
    </div>

    <!-- 最优适应度 -->
    <div v-if="bestFitness !== undefined" class="rounded-lg bg-app-panel p-3">
      <div class="text-sm text-app-muted">当前最优成本</div>
      <div class="text-2xl font-bold text-primary">
        {{ bestFitness.toFixed(2) }} <span class="text-sm font-normal">万元</span>
      </div>
    </div>

    <!-- 阶段指示器 -->
    <div class="flex gap-2">
      <div
        v-for="s in ['clustering', 'optimizing', 'evaluating']"
        :key="s"
        class="flex-1 h-1 rounded-full transition-colors"
        :class="
          s === status
            ? 'bg-primary'
            : ['clustering', 'optimizing', 'evaluating'].indexOf(s) <
              ['clustering', 'optimizing', 'evaluating'].indexOf(status)
              ? 'bg-primary/30'
              : 'bg-app-panel'
        "
      />
    </div>
  </div>
</template>
```

### 6.5 工具栏集成

#### 6.5.1 更新系统配置 (`config/system-config.ts`)

```typescript
// 在 toolbarConfig.model 中添加容量规划按钮

export const toolbarConfig: Record<EditorMenuKey, ToolbarGroupConfig[]> = {
  // ... existing config ...
  model: [
    {
      key: 'project-config',
      label: '项目配置',
      actions: [
        { key: 'layer-config', label: '时层配置', icon: 'show-label', type: 'button' },
        { key: 'boundary-config', label: '边界配置', icon: 'show-label', type: 'button' },
        { key: 'simulation-parse', label: '仿真计算', icon: 'play', type: 'button' },
        { key: 'capacity-planning', label: '容量规划', icon: 'chart', type: 'button' }  // 新增
      ]
    }
  ]
}
```

#### 6.5.2 更新编辑器页面 (`app/pages/editor/[projectId].vue`)

```typescript
// 在 handleToolbarAction 中添加容量规划处理

if (actionKey === 'capacity-planning') {
  navigateTo(`/capacity-planning?projectId=${projectId.value}&canvasId=${activeCanvas.value?.id}`)
  return
}
```

### 6.6 容量规划页面 (`app/pages/capacity-planning/index.vue`)

```vue
<!-- app/pages/capacity-planning/index.vue -->

<script setup lang="ts">
import type {
  CapacityPlanningConfig,
  CapacityVariable,
  ClusteringConfig,
  OptimizationConfig,
  EconomicConfig
} from '~~/types/capacity-planning'
import { useCapacityPlanningApi } from '~~/composables/api/useCapacityPlanningApi'

const route = useRoute()
const api = useCapacityPlanningApi()

const projectId = computed(() => String(route.query.projectId ?? ''))
const canvasId = computed(() => String(route.query.canvasId ?? ''))

// 状态
const currentStep = ref<'variables' | 'clustering' | 'optimization' | 'economic' | 'review'>('variables')
const variables = ref<CapacityVariable[]>([])
const clusteringConfig = ref<ClusteringConfig>({
  method: 'kmeans',
  numClusters: 5,
  features: ['wind_speed', 'irradiance', 'load'],
  timeGranularity: '1h'
})
const optimizationConfig = ref<OptimizationConfig>({
  algorithm: 'adaptive_de',
  maxEvaluations: 200,
  populationSize: 50
})
const economicConfig = ref<EconomicConfig>({
  projectLifespan: 20,
  discountRate: 0.08,
  electricityPrice: 0.6
})

const loading = ref(false)
const error = ref<string | null>(null)

// 加载变量配置
onMounted(async () => {
  if (projectId.value && canvasId.value) {
    loading.value = true
    try {
      variables.value = await api.getVariables(projectId.value, canvasId.value)
    } catch (e) {
      error.value = '加载变量配置失败'
    } finally {
      loading.value = false
    }
  }
})

// 步骤导航
const steps = [
  { key: 'variables', label: '设备配置', icon: '⚙️' },
  { key: 'clustering', label: '场景聚类', icon: '📊' },
  { key: 'optimization', label: '优化算法', icon: '🔬' },
  { key: 'economic', label: '经济参数', icon: '💰' },
  { key: 'review', label: '确认启动', icon: '🚀' }
]

const currentStepIndex = computed(() =>
  steps.findIndex(s => s.key === currentStep.value)
)

const canProceed = computed(() => {
  switch (currentStep.value) {
    case 'variables':
      return variables.value.length > 0 && variables.value.some(v => v.enabled)
    default:
      return true
  }
})

const nextStep = () => {
  const nextIndex = currentStepIndex.value + 1
  if (nextIndex < steps.length) {
    currentStep.value = steps[nextIndex].key as typeof currentStep.value
  }
}

const prevStep = () => {
  const prevIndex = currentStepIndex.value - 1
  if (prevIndex >= 0) {
    currentStep.value = steps[prevIndex].key as typeof currentStep.value
  }
}

// 提交配置
const submitConfig = async () => {
  loading.value = true
  error.value = null

  try {
    const config: Omit<CapacityPlanningConfig, 'id' | 'createdAt' | 'updatedAt'> = {
      projectId: projectId.value,
      canvasId: canvasId.value,
      name: `容量规划-${new Date().toLocaleDateString()}`,
      variables: variables.value,
      clustering: clusteringConfig.value,
      optimization: optimizationConfig.value,
      economic: economicConfig.value
    }

    const { taskId } = await api.createTask(config)
    await api.startOptimization(taskId)

    // 跳转到进度页面
    navigateTo(`/capacity-planning/${taskId}`)
  } catch (e) {
    error.value = '创建规划任务失败'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="min-h-screen bg-app-surface">
    <!-- 顶部导航 -->
    <header class="border-b border-app-border bg-white px-6 py-4">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-4">
          <button
            @click="navigateTo(`/editor/${projectId}`)"
            class="text-app-muted hover:text-app-text"
          >
            ← 返回编辑器
          </button>
          <h1 class="text-xl font-semibold text-app-text">容量规划</h1>
        </div>
      </div>
    </header>

    <!-- 步骤指示器 -->
    <div class="border-b border-app-border bg-white px-6 py-3">
      <div class="flex items-center justify-center gap-2">
        <button
          v-for="(step, index) in steps"
          :key="step.key"
          @click="currentStep = step.key as typeof currentStep"
          class="flex items-center gap-2 px-4 py-2 rounded-lg transition-colors"
          :class="
            currentStep === step.key
              ? 'bg-primary text-white'
              : index < currentStepIndex
                ? 'bg-primary/10 text-primary'
                : 'text-app-muted hover:bg-app-panel'
          "
        >
          <span>{{ step.icon }}</span>
          <span class="text-sm font-medium">{{ step.label }}</span>
        </button>
      </div>
    </div>

    <!-- 主内容 -->
    <main class="mx-auto max-w-4xl px-6 py-8">
      <div v-if="loading" class="flex justify-center py-12">
        <div class="text-app-muted">加载中...</div>
      </div>

      <div v-else-if="error" class="rounded-lg bg-red-50 p-4 text-red-600">
        {{ error }}
      </div>

      <template v-else>
        <!-- 步骤 1: 设备配置 -->
        <VariableConfigForm
          v-if="currentStep === 'variables'"
          v-model:variables="variables"
        />

        <!-- 步骤 2: 聚类配置 -->
        <ClusteringConfig
          v-else-if="currentStep === 'clustering'"
          v-model:config="clusteringConfig"
        />

        <!-- 步骤 3: 优化算法配置 -->
        <OptimizationConfig
          v-else-if="currentStep === 'optimization'"
          v-model:config="optimizationConfig"
          :variables="variables"
        />

        <!-- 步骤 4: 经济参数配置 -->
        <EconomicConfig
          v-else-if="currentStep === 'economic'"
          v-model:config="economicConfig"
        />

        <!-- 步骤 5: 确认启动 -->
        <div v-else-if="currentStep === 'review'" class="space-y-6">
          <h3 class="text-lg font-semibold text-app-text">配置确认</h3>

          <div class="grid grid-cols-2 gap-4">
            <div class="rounded-lg border border-app-border p-4">
              <h4 class="font-medium text-app-text mb-2">优化变量</h4>
              <div class="space-y-1 text-sm">
                <div v-for="v in variables.filter(v => v.enabled)" :key="v.componentId">
                  {{ v.componentName }}: {{ v.lowerBound }} - {{ v.upperBound }} {{ v.unit }}
                </div>
              </div>
            </div>

            <div class="rounded-lg border border-app-border p-4">
              <h4 class="font-medium text-app-text mb-2">聚类配置</h4>
              <div class="space-y-1 text-sm text-app-muted">
                <div>典型日数量: {{ clusteringConfig.numClusters }}</div>
                <div>时间粒度: {{ clusteringConfig.timeGranularity }}</div>
              </div>
            </div>

            <div class="rounded-lg border border-app-border p-4">
              <h4 class="font-medium text-app-text mb-2">优化算法</h4>
              <div class="space-y-1 text-sm text-app-muted">
                <div>算法: {{ optimizationConfig.algorithm }}</div>
                <div>最大迭代: {{ optimizationConfig.maxEvaluations }}</div>
                <div>种群大小: {{ optimizationConfig.populationSize }}</div>
              </div>
            </div>

            <div class="rounded-lg border border-app-border p-4">
              <h4 class="font-medium text-app-text mb-2">经济参数</h4>
              <div class="space-y-1 text-sm text-app-muted">
                <div>项目寿命: {{ economicConfig.projectLifespan }} 年</div>
                <div>折现率: {{ (economicConfig.discountRate * 100).toFixed(1) }}%</div>
                <div>电价: {{ economicConfig.electricityPrice }} 元/kWh</div>
              </div>
            </div>
          </div>
        </div>
      </template>

      <!-- 底部按钮 -->
      <div class="mt-8 flex justify-between">
        <button
          v-if="currentStepIndex > 0"
          @click="prevStep"
          class="px-4 py-2 text-app-muted hover:text-app-text"
        >
          上一步
        </button>
        <div v-else />

        <button
          v-if="currentStepIndex < steps.length - 1"
          @click="nextStep"
          :disabled="!canProceed"
          class="px-6 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          下一步
        </button>

        <button
          v-else
          @click="submitConfig"
          :disabled="loading"
          class="px-6 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 disabled:opacity-50"
        >
          {{ loading ? '提交中...' : '开始优化' }}
        </button>
      </div>
    </main>
  </div>
</template>
```

### 6.7 任务进度页面 (`app/pages/capacity-planning/[taskId].vue`)

```vue
<!-- app/pages/capacity-planning/[taskId].vue -->

<script setup lang="ts">
import type { CapacityPlanningTask, CapacityPlanningResult } from '~~/types/capacity-planning'
import { useCapacityPlanningApi } from '~~/composables/api/useCapacityPlanningApi'

const route = useRoute()
const api = useCapacityPlanningApi()

const taskId = computed(() => String(route.params.taskId))

const task = ref<CapacityPlanningTask | null>(null)
const loading = ref(true)
const error = ref<string | null>(null)

// WebSocket 订阅
let unsubscribe: (() => void) | null = null

const progressData = ref({
  phase: '',
  currentIteration: 0,
  totalIterations: 0,
  bestFitness: Infinity,
  bestSolution: [] as number[]
})

onMounted(async () => {
  try {
    // 加载任务状态
    task.value = await api.getTaskStatus(taskId.value)
    loading.value = false

    // 如果任务正在运行，订阅进度
    if (['clustering', 'optimizing', 'evaluating'].includes(task.value.status)) {
      subscribeToProgress()
    }
  } catch (e) {
    error.value = '加载任务失败'
    loading.value = false
  }
})

onUnmounted(() => {
  if (unsubscribe) {
    unsubscribe()
  }
})

const subscribeToProgress = () => {
  unsubscribe = api.subscribeProgress(
    taskId.value,
    (data) => {
      // 更新进度
      if (data.type === 'progress') {
        progressData.value = {
          phase: data.phase || 'optimizing',
          currentIteration: data.iteration,
          totalIterations: data.totalIterations,
          bestFitness: data.bestFitness,
          bestSolution: data.bestSolution
        }
      }
    },
    (results) => {
      // 优化完成
      if (task.value) {
        task.value.status = 'completed'
        task.value.results = results
      }
    },
    (errorMsg) => {
      error.value = errorMsg
      if (task.value) {
        task.value.status = 'failed'
      }
    }
  )
}

// 应用最优配置
const applyOptimal = async () => {
  try {
    const { projectJson } = await api.applyOptimalConfig(taskId.value)
    // 跳转到编辑器或启动一键仿真
    navigateTo(`/editor/${task.value?.projectId}`)
  } catch (e) {
    error.value = '应用配置失败'
  }
}

// 一键仿真
const startFullSimulation = async () => {
  try {
    // 先应用最优配置
    await api.applyOptimalConfig(taskId.value)

    // 然后跳转到仿真页面
    navigateTo(`/tasks?projectId=${task.value?.projectId}`)
  } catch (e) {
    error.value = '启动仿真失败'
  }
}
</script>

<template>
  <div class="min-h-screen bg-app-surface">
    <!-- 顶部导航 -->
    <header class="border-b border-app-border bg-white px-6 py-4">
      <div class="flex items-center gap-4">
        <button
          @click="navigateTo('/capacity-planning')"
          class="text-app-muted hover:text-app-text"
        >
          ← 返回列表
        </button>
        <h1 class="text-xl font-semibold text-app-text">
          容量规划任务 {{ taskId }}
        </h1>
      </div>
    </header>

    <!-- 主内容 -->
    <main class="mx-auto max-w-4xl px-6 py-8">
      <div v-if="loading" class="flex justify-center py-12">
        <div class="text-app-muted">加载中...</div>
      </div>

      <div v-else-if="error" class="rounded-lg bg-red-50 p-4 text-red-600">
        {{ error }}
      </div>

      <template v-else-if="task">
        <!-- 进行中：显示进度 -->
        <OptimizationProgress
          v-if="['clustering', 'optimizing', 'evaluating'].includes(task.status)"
          :status="task.status"
          :phase="progressData.phase"
          :current-iteration="progressData.currentIteration"
          :total-iterations="progressData.totalIterations"
          :best-fitness="progressData.bestFitness"
        />

        <!-- 完成：显示结果 -->
        <ResultPanel
          v-else-if="task.status === 'completed' && task.results"
          :results="task.results"
          :variables="task.config.variables"
          @apply="applyOptimal"
          @simulate="startFullSimulation"
        />

        <!-- 失败：显示错误 -->
        <div v-else-if="task.status === 'failed'" class="space-y-4">
          <h3 class="text-lg font-semibold text-red-600">优化失败</h3>
          <p class="text-app-muted">{{ task.errorMessage }}</p>
          <button
            @click="navigateTo('/capacity-planning')"
            class="px-4 py-2 bg-primary text-white rounded-lg"
          >
            返回重新配置
          </button>
        </div>
      </template>
    </main>
  </div>
</template>
```

### 6.8 结果展示面板 (`ResultPanel.vue`)

```vue
<!-- app/components/capacity-planning/ResultPanel.vue -->

<script setup lang="ts">
import type { CapacityPlanningResult, CapacityVariable } from '~~/types/capacity-planning'

interface Props {
  results: CapacityPlanningResult
  variables: CapacityVariable[]
}

interface Emits {
  (e: 'apply'): void
  (e: 'simulate'): void
}

defineProps<Props>()
defineEmits<Emits>()
</script>

<template>
  <div class="space-y-6">
    <h3 class="text-lg font-semibold text-app-text">优化结果</h3>

    <!-- 最优容量配置 -->
    <div class="rounded-lg border border-app-border p-6">
      <h4 class="font-medium text-app-text mb-4">最优容量配置</h4>
      <div class="grid grid-cols-2 gap-4">
        <div
          v-for="optVar in results.optimalVariables"
          :key="optVar.componentId"
          class="flex items-center justify-between rounded-lg bg-app-panel p-3"
        >
          <span class="text-app-muted">
            {{ variables.find(v => v.componentId === optVar.componentId)?.componentName }}
          </span>
          <span class="font-medium text-app-text">
            {{ optVar.optimalCapacity.toFixed(1) }} {{ optVar.unit }}
          </span>
        </div>
      </div>
    </div>

    <!-- 经济指标 -->
    <div class="rounded-lg border border-app-border p-6">
      <h4 class="font-medium text-app-text mb-4">经济性指标</h4>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="text-center">
          <div class="text-2xl font-bold text-primary">
            {{ results.economicIndicators.npv.toFixed(2) }}
          </div>
          <div class="text-sm text-app-muted">净现值 (万元)</div>
        </div>
        <div class="text-center">
          <div class="text-2xl font-bold text-primary">
            {{ (results.economicIndicators.irr * 100).toFixed(2) }}%
          </div>
          <div class="text-sm text-app-muted">内部收益率</div>
        </div>
        <div class="text-center">
          <div class="text-2xl font-bold text-primary">
            {{ results.economicIndicators.paybackPeriod.toFixed(1) }}
          </div>
          <div class="text-sm text-app-muted">回收期 (年)</div>
        </div>
        <div class="text-center">
          <div class="text-2xl font-bold text-primary">
            {{ results.economicIndicators.lcoe.toFixed(3) }}
          </div>
          <div class="text-sm text-app-muted">度电成本 (元/kWh)</div>
        </div>
      </div>
    </div>

    <!-- 收敛曲线 -->
    <div class="rounded-lg border border-app-border p-6">
      <h4 class="font-medium text-app-text mb-4">收敛曲线</h4>
      <ConvergenceChart :history="results.convergenceHistory" />
    </div>

    <!-- 操作按钮 -->
    <div class="flex gap-4">
      <button
        @click="$emit('apply')"
        class="flex-1 px-6 py-3 bg-primary text-white rounded-lg hover:bg-primary/90"
      >
        应用最优配置
      </button>
      <button
        @click="$emit('simulate')"
        class="flex-1 px-6 py-3 border border-primary text-primary rounded-lg hover:bg-primary/5"
      >
        一键仿真
      </button>
    </div>
  </div>
</template>
```

---

## 7. 实施计划

### 7.1 阶段划分

| 阶段 | 内容 | 预计工期 | 依赖 |
|---|---|---|---|
| **阶段 0** | 类型定义 + 数据库 Schema | 0.5 天 | 无 |
| **阶段 1** | 后端：变量检测服务 | 1 天 | 阶段 0 |
| **阶段 2** | 后端：K-means 聚类服务 | 2 天 | 阶段 0 |
| **阶段 3** | 后端：BlackBoxOptim 集成 | 2 天 | 阶段 1, 2 |
| **阶段 4** | 后端：经济评价接口 | 1 天 | 阶段 3 |
| **阶段 5** | 后端：规划任务管理 + 路由 | 2 天 | 阶段 1-4 |
| **阶段 6** | 前端：变量配置表单 | 1 天 | 阶段 1 |
| **阶段 7** | 前端：聚类/优化配置组件 | 1 天 | 阶段 0 |
| **阶段 8** | 前端：进度展示 + 结果面板 | 1.5 天 | 阶段 5 |
| **阶段 9** | 前端：工具栏集成 + 页面路由 | 0.5 天 | 阶段 6-8 |
| **阶段 10** | 集成测试 + 调优 | 2 天 | 阶段 5, 9 |

**总工期**：约 14 天

### 7.2 关键依赖

1. **BlackBoxOptim.jl**：Julia 黑箱优化库，需要添加到项目依赖
2. **Clustering.jl**：Julia 聚类库（或自行实现 K-means）
3. **现有 TaskManager**：复用任务生命周期管理
4. **现有 SimulationRunner**：复用仿真求解逻辑

### 7.3 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 优化收敛慢 | 用户等待时间长 | 设置最大迭代次数；提供提前终止选项 |
| 单次仿真耗时长 | 优化周期长 | 使用典型日减少计算量；支持并行评估 |
| 经济评价逻辑复杂 | 开发周期延长 | 先实现最小版本，留出接口 |
| 前端表单复杂度 | 用户体验差 | 分步骤引导；提供默认值 |

---

## 8. 扩展性设计

### 8.1 支持更多设备类型

在 `variable_detector.jl` 的 `OPTIMIZABLE_COMPONENTS` 字典中添加新设备类型即可。

### 8.2 支持更多优化算法

BlackBoxOptim 支持多种算法，通过配置 `algorithm` 字段切换：
- `adaptive_de`：自适应差分进化（推荐）
- `xnes`：自然进化策略
- `separable_nes`：可分离自然进化策略
- `dxnes`：对角自然进化策略

### 8.3 支持更多聚类方法

当前仅实现 K-means，可扩展支持：
- 层次聚类
- DBSCAN
- 高斯混合模型

### 8.4 支持多目标优化

当前为单目标（最小化成本），可扩展为多目标优化（成本 vs 碳排放 vs 可靠性）。

---

## 9. 附录

### 9.1 相关文件索引

| 文件 | 用途 |
|---|---|
| `types/capacity-planning.ts` | 前端类型定义 |
| `composables/api/useCapacityPlanningApi.ts` | 前端 API 封装 |
| `app/components/capacity-planning/*.vue` | 前端组件 |
| `app/pages/capacity-planning/*.vue` | 前端页面 |
| `config/system-config.ts` | 工具栏配置（需修改） |
| `backend/services/capacity_planning/*.jl` | 后端服务 |
| `backend/routes/capacity_planning.jl` | 后端路由 |
| `backend/data/capacity_planning.db` | 数据库 |

### 9.2 参考资料

- [BlackBoxOptim.jl 文档](https://github.com/robertfeldt/BlackBoxOptim.jl)
- [K-means 算法详解](https://en.wikipedia.org/wiki/K-means_clustering)
- [综合能源系统容量规划方法](相关论文/标准)
- [现有计算任务架构](docs/compute-task-architecture.md)
