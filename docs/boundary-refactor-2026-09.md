# 边界数据与容量规划重构记录（2026-09）

## 概述

本次重构以 boundary.db 为核心数据源，统一了边界配置页（仿真业务）和容量规划业务的数据处理路径，新增了边界元信息管理、数据预处理、典型场景聚类等功能，并清理了冗余代码。

---

## 一、边界配置页（仿真业务）

###1.1 前端修改（`app/pages/boundary/[projectId].vue`）

| 修改项 | 说明 |
|---|---|
| 图表标题 | 原始数据图表新增标题，格式：`时间尺度：1h，数据点：8760个（365天）` |
| 纵坐标中文 | y轴从英文 `BoundaryMeaning` 改为中文标签，通过 `BOUNDARY_MEANING_LABELS` 映射 |
| 去除平滑 | 所有 echarts 设置 `smooth: false`，直接折线连接 |
| boundaryMeta 持久化 | `BoundaryItem` 接口新增 `boundaryMeta` 字段，导入时保存、加载时恢复 |

**boundaryMeta 数据结构：**
```typescript
boundaryMeta?: {
  boundaryLength: string   // 如 "168h"
  boundaryStep: string     // 如 "1h"、"15m"
  dayCount: number         // 天数
  pointCount: number       // 数据点数
}
```

###1.2 后端修改（`backend/services/boundary_service.jl`）

#### 新增函数

| 函数 | 功能 |
|---|---|
| `preprocess_boundary_data(data, time_step)` | 截断到24h的倍数，返回截断后的数据和元信息 |
| `ensure_boundary_config_table!(db_path)` | 确保 `boundary_config` 表存在 |
| `save_boundary_config(...)` | 保存边界元信息到 `boundary_config` 表 |
| `get_boundary_config(db_path, boundary_id)` | 获取单条边界元信息 |
| `get_all_boundary_configs(db_path)` | 获取所有边界元信息 |

#### 修改函数

| 函数 | 修改内容 |
|---|---|
| `parse_boundary_data` | 新增 `boundary_length` 可选参数，使用边界自身长度替代 layer["length"] |
| `seed_task_boundary_data` | 新增 `sim_start_time`/`sim_end_time` 参数，按仿真时间范围截断，超范围报错 |

#### 新增数据表（`boundary_config`）

```sql
CREATE TABLE boundary_config (
    boundary_id     TEXT PRIMARY KEY,
    boundary_length TEXT NOT NULL,     -- 如 "168h"
    boundary_step   TEXT NOT NULL,     -- 如 "1h"
    day_count       INTEGER NOT NULL,  -- 天数
    point_count     INTEGER NOT NULL   -- 数据点数
)
```

###1.3 API 修改（`backend/server.jl`）

| API | 修改内容 |
|---|---|
| `POST /api/boundary/import` | 调用 `preprocess_boundary_data`，返回截断数据及元信息（pointCount, totalHours, dayCount, timeStep） |
| `POST /api/boundary/transform` | 接收 `boundaryLength` 参数，传给 `parse_boundary_data` |
| `POST /api/boundary/submit` | 保存 boundaryMeta 到 `boundary_config` 表 |

###1.4 Bug 修复

- **boundaryMeta 空字符串问题**：前端在 `importData` 时设置 `boundaryMeta`，但未持久化到 `BoundaryItem`，导致切换标签后丢失。修复：在 `types/boundary.ts` 新增字段，在 `saveCurrentFormToBoundary`/`loadBoundary` 中持久化和恢复。

---

## 二、容量规划业务

###2.1 数据预处理（`backend/services/boundary_service.jl`）

#### 新增函数

| 函数 | 功能 |
|---|---|
| `get_all_boundary_ids(project_id)` | 从 boundary.db 的 `time_series_meta` 获取所有有数据的边界ID |
| `prepare_boundaries_for_clustering(project_id, boundary_ids)` | 预处理所有边界数据用于聚类 |

**`prepare_boundaries_for_clustering` 处理流程：**
1. 从 `boundary_config` 表获取每个边界的长度和尺度
2. 以最短的 `boundaryLength` 为准，截断到24h的倍数
3. 使用 `parse_boundary_data` 统一重采样到1h尺度
4. 对于没有配置信息的边界，从数据推断分辨率
5. 返回 `Dict("data" => ..., "totalHours" => ..., "dayCount" => ..., "warnings" => ...)`

###2.2 典型场景聚类（`backend/services/capacity_planning/scenario_reducer.jl`）

#### 重写函数

| 函数 | 修改内容 |
|---|---|
| `load_ts_boundary_features` | 始终处理所有边界（特征+跟随），调用 `prepare_boundaries_for_clustering` |
| `reduce_boundary_scenarios` | 自动获取所有边界ID，天数不足时限制场景数（警告而非报错），聚类后提取所有边界数据 |

#### 删除函数

| 函数 | 原因 |
|---|---|
| `_preprocess_boundaries` | 功能被 `prepare_boundaries_for_clustering` 替代 |
| `_fill_missing_day` | 旧的"加噪补齐"逻辑已移除，此辅助函数不再需要 |

**聚类流程：**
1. `get_all_boundary_ids(project_id)` 获取所有边界ID
2. `prepare_boundaries_for_clustering` 预处理所有边界数据
3. 按24h切分为天
4. 天数不足时：限制场景数为可用天数，发出警告
5. 构建聚类矩阵（仅使用特征边界）
6. 执行 K-means/K-medoids 聚类
7. 提取所有边界数据（特征+跟随）存入场景

**关键设计：**
- **特征边界**：参与聚类计算
- **跟随边界**：不参与聚类，但聚类完成后跟随相同的天数提取数据
- **场景数量**：受限于可用天数，天数不足时警告而非报错

###2.3 场景数据存储（`backend/services/capacity_planning/planning_store.jl`）

场景数据存储在 `cp-{id}/scenarios.db` 中：

```sql
CREATE TABLE scenario_series (
    scenario_id    TEXT NOT NULL,
    boundary_id    TEXT NOT NULL,
    hour           INTEGER NOT NULL,
    value          REAL NOT NULL,
    PRIMARY KEY (scenario_id, boundary_id, hour)
)
```

#### 使用函数

| 函数 | 功能 |
|---|---|
| `save_scenario_set_series!(planning_id, scenarios)` | 批量保存所有场景的时序数据 |
| `get_scenario_set_series(planning_id)` | 获取所有场景的时序数据 |

---

## 三、容量规划前端

###3.1 图表修改（`app/pages/capacity-planning/[projectId].vue`）

| 修改项 | 说明 |
|---|---|
| 图表标题 | 新增 `boundaryPreviewChartTitle` 计算属性，格式同边界配置页 |
| 去除平滑 | `smooth: false`，移除 `sampling: 'lttb'` |
| 纵坐标中文 | 优先使用 `BOUNDARY_MEANING_LABELS[meaning]`，而非 `rawData.yAxisLabel` |
| 网格调整 | `top: 35`（为标题留空间），`bottom: '8%'` |

---

## 四、清理的冗余代码

###4.1 删除的文件

| 文件 | 原因 |
|---|---|
| `backend/services/capacity_planning/boundary_dataset_service.jl` | 旧的"数据集导入"路径，前端未调用，聚类未使用 |
| `server/api/v1/capacity-planning/datasets/`（3个文件） | 对应的 BFF 代理 |

###4.2 删除的函数

| 函数 | 文件 | 原因 |
|---|---|---|
| `save_scenario_series!`（单条） | planning_store.jl | 未被调用，使用批量版 `save_scenario_set_series!` |
| `get_scenario_series`（单条） | planning_store.jl | 未被调用，使用批量版 `get_scenario_set_series` |
| `delete_scenario_series!` | planning_store.jl | 未被调用 |
| `_fill_missing_day` | scenario_reducer.jl | 旧的加噪逻辑已移除 |
| `_preprocess_boundaries` | scenario_reducer.jl | 被 `prepare_boundaries_for_clustering` 替代 |

###4.3 删除的路由

| 路由 | 文件 | 原因 |
|---|---|---|
| `POST /api/capacity-planning/datasets/import` | routes/capacity_planning.jl | 前端未调用 |
| `GET /api/capacity-planning/datasets` | routes/capacity_planning.jl | 前端未调用 |
| `GET /api/capacity-planning/datasets/{id}` | routes/capacity_planning.jl | 前端未调用 |
| `DELETE /api/capacity-planning/datasets/{id}` | routes/capacity_planning.jl | 前端未调用 |

###4.4 删除的数据表

| 表名 | 原因 |
|---|---|
| `boundary_dataset` | 旧数据集路径，未使用 |
| `boundary_series` | 旧数据集路径，未使用 |
| `boundary_point` | 旧数据集路径，未使用 |

---

## 五、数据流总览

### 边界配置页（仿真业务）

```
用户导入CSV
    ↓
POST /api/boundary/import
    → preprocess_boundary_data（截断到24h倍数）
    → 返回截断数据 + 元信息
    ↓
用户配置时层参数
    ↓
POST /api/boundary/transform
    → parse_boundary_data（按boundaryLength转换）
    → 返回各时层数据
    ↓
POST /api/boundary/submit
    → 写入 time_series_meta + time_series_data
    → 写入 boundary_config（元信息）
```

### 容量规划业务

```
边界数据已存在于 boundary.db
    ↓
POST /api/capacity-planning/scenarios/preview
    → get_all_boundary_ids（获取所有边界ID）
    → prepare_boundaries_for_clustering（预处理）
        - 以最短长度为准截断到24h倍数
        - 统一重采样到1h
    → reduce_boundary_scenarios（聚类）
        - 仅用特征边界构建聚类矩阵
        - 提取所有边界数据（特征+跟随）
    → save_scenario_set_series!（存入 scenarios.db）
```

### 仿真计算业务

```
用户创建任务，输入仿真时间范围
    ↓
POST /api/tasks
    → seed_task_boundary_data（按时间范围截断）
        - 检查仿真范围 ≤ 边界长度
        - 截断到指定范围
    → 写入 timeseries.db
    ↓
run_task / run_single_layer_task
    → 使用 timeseries.db 数据求解
```

---

## 六、关键约定

1. **边界相关后端函数**：统一放在 `backend/services/boundary_service.jl`
2. **聚类算法**：放在 `backend/services/capacity_planning/scenario_reducer.jl`
3. **场景存储**：`cp-{id}/scenarios.db`，每个容量规划任务独立
4. **边界元信息**：存储在 `boundary_config` 表，各时层共用
5. **纵坐标标签**：优先使用 `BOUNDARY_MEANING_LABELS[meaning]` 中文映射
