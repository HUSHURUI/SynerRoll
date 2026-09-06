# 容量规划数据流重构 - 设计文档

## 一、业务背景

容量规划页面改造为"任务驱动"模式，与仿真计算页面保持一致的架构：
- 用户创建容量规划任务 → 配置变量 → 选择边界数据 → 聚类典型场景 → 优化求解 → 查看结果
- 每个任务独立管理配置和计算结果

## 二、现存问题

### 问题1：boundary.db 存储了两套冗余表

`projects/{id}/boundary.db` 中存在两套完全独立的表系统，存储同一份边界数据：

| 表 | 写入方 | 读取方 |
|---|--------|--------|
| `time_series_meta` + `time_series_data`（TS库） | 边界配置页"提交"按钮 | 灵活性评估 |
| `boundary_dataset` + `boundary_series` + `boundary_point` | 容量规划"导入数据集"功能 | 容量规划聚类系统 |

**后果**：同一份数据存了两遍，写入方和读取方不匹配，需要额外的"同步"逻辑来桥接。

### 问题2：场景时序数据存在全局数据库

`planning_scenario_series` 表在全局 `capacity-planning.db` 中，而非每个任务目录下。

**对比仿真计算**：
- 仿真计算：`tasks.db`（元数据） + 每个任务目录下的 `timeseries.db`（时序数据）
- 容量规划：`capacity-planning.db`（元数据 + 场景时序混在一起）

### 问题3：聚类数据源与边界配置页不匹配

边界配置页的数据写入 TS 库（`time_series_meta` + `time_series_data`），
但聚类系统从 `boundary_dataset*` 表读取 —— 这些表从未被边界配置页写入过。

## 三、目标架构

```
projects/{id}/boundary.db
└── TS库表 (time_series_meta + time_series_data)  ← 唯一的边界数据源
    ├── 边界配置页"提交"写入
    ├── 灵活性评估读取
    └── 容量规划聚类系统读取          ← 新增读取方

capacity-planning.db
├── planning_tasks                    ← 仅任务元数据
├── planning_scenarios                ← 场景元数据
├── planning_evaluations              ← 评价记录
└── planning_results                  ← 最终结果
    （planning_scenario_series 表移除）

cp-{id}/
├── config.json                       ← 任务配置（变量、聚类、优化器参数）
├── project_snapshot.json             ← 项目快照
└── scenarios.db                      ← 典型场景时序数据（从全局db移入）
    └── planning_scenario_series 表
```

数据流：
```
边界配置页 → boundary.db (TS库)
                ↓
聚类系统读取 TS库 → K-means 聚类 → 典型场景
                ↓
场景元数据 → capacity-planning.db (planning_scenarios)
场景时序   → cp-{id}/scenarios.db (planning_scenario_series)
                ↓
优化求解器读取场景时序 → 评价 → 结果写入 capacity-planning.db
```

## 四、修改清单

### 后端

#### 1. scenario_reducer.jl — 改聚类数据源

**当前**：`reduce_boundary_scenarios` 调用 `load_boundary_dataset_features(project_id, dataset_id, feature_ids)`
从 `boundary_dataset*` 表读取数据，需要 `datasetId`。

**改为**：新增 `load_ts_boundary_features(project_id, feature_ids)` 函数，
从 TS 库（`time_series_meta` + `time_series_data`）读取数据。
不再需要 `datasetId`，`featureIds` 即为 `boundary_id`。

TS 库 label 格式：`{boundary_id}|{meaning}|planned#1`（layer_id=1 为小时级数据）

返回格式与原函数兼容：
- metadata: Dict（含 resolutionMinutes, timezone, contentHash, series 等）
- feature_points: Dict{String, Vector{Tuple{String,Float64}}}

#### 2. planning_store.jl — 场景时序移到任务目录

**当前**：`planning_scenario_series` 表在全局 `capacity-planning.db` 中。

**改为**：
- 新增 `get_scenario_store(planning_id)` 函数，打开/创建 `cp-{id}/scenarios.db`
- `save_scenario_series!`、`save_scenario_set_series!`、`get_scenario_series`、`get_scenario_set_series`、`delete_scenario_series!`
  改为操作 `cp-{id}/scenarios.db` 而非全局 db
- 从全局 db 建表语句中移除 `planning_scenario_series` 表

#### 3. boundary_dataset_service.jl — 删除冗余

- 删除 `sync_project_boundaries!` 函数（上一轮新增的，不再需要）
- `boundary_dataset*` 表的 CRUD 函数保留（兼容已有导入功能），
  但聚类系统不再依赖它们

#### 4. capacity_planning.jl (路由) — 清理

- 删除 `POST /api/capacity-planning/datasets/sync` 路由（上一轮新增的）
- `POST /api/capacity-planning/scenarios/preview` 不再要求 `datasetId`
- 聚类配置中 `datasetId` 改为可选（草稿状态可为空）

#### 5. planning_manager.jl — 聚类配置简化

- `_normalize_clustering_config`：`datasetId` 不再是必填项
- 创建任务时聚类配置中 `datasetId` 可为空

### 前端

#### 6. [projectId].vue — 简化步骤二/三

- `loadDatasetContext`：移除 sync 逻辑，移除 `activeDataset` 依赖
- 步骤二：直接使用 `configuredBoundaries`（来自 project.boundaries），去掉数据集选择
- 步骤三：`clusteringFeatureOptions` 从 `configuredBoundaries` 派生（基于 boundary.meaning）
- `confirmBoundaryData`：不再检查 `activeDataset`，直接进入步骤三
- `previewTypicalDays`：调用 `previewScenarios` 时不再传 `datasetId`
- 移除 `activeDataset`、`selectedDatasetId`、`datasetLoading`、`datasetError` 等状态
- 移除 `loadDataset` 函数

#### 7. useCapacityPlanningApi.ts — 清理

- 删除 `syncDatasets` 函数
- 删除 `listDatasets`、`getDataset`、`importDataset`（聚类不再需要）
- `previewScenarios` 参数中 `datasetId` 改为可选

#### 8. Nuxt 代理路由 — 清理

- 删除 `server/api/v1/capacity-planning/datasets/sync.post.ts`
- 其他 datasets 路由保留（兼容已有功能）

## 五、关键约束

1. **向后兼容**：已有任务的 `planning_scenario_series` 数据在全局 db 中，
   需要处理读取时的兼容（优先从任务目录读，回退到全局 db）

2. **TS 库时间戳格式**：TS 库存储 "H:MM" 格式（如 "0:00", "13:00"），
   聚类系统需要按自然日分组 —— 由于边界配置页的数据是日内 profile（无日期），
   所有点视为同一天，`points_per_day = len(values)`

3. **resolution 推断**：TS 库不显式存储 resolution，从数据点数推断
   （24点=60min, 96点=15min, 288点=5min），或从项目边界配置的 timeStep 字段获取
