# 任务结果页仿真范围裁剪方案

## Context

SynerRoll 的多层滚动求解中，layer1（日前计划）为了向 layer2+ 提供足够长的引导，会在持久化时把结果长度复制一倍：
- `backend/utils/model_utils.jl:18-32` 让 layer1 的时间戳 span 变成 `2 × length`，数值 `vcat(values, values)`。

这导致两个问题：
1. **前端图表越界**：运行总览、能流平衡、系统灵活性、设备灵活性等结果页的 echarts 横轴会显示 `[0, sim_end)` 之外的复制数据。
2. **后端经济性重复计算**：`economy_evaluation_service.jl` 对 layer1 的每个序列做全量 `sum`，把复制出来的后半段又加了一次，运行成本/收益均翻倍。

本方案要求：
- 前端以任务的 `sim_start_time` / `sim_end_time` 为基准，把上述图表的横轴/数据裁剪到仿真范围内。
- 后端经济性评估在读取 `timeseries.db` 时只取 `[sim_start_time, sim_end_time)` 内的点，避免重复计算。

## Proposed Approach

### 1. 前端：统一仿真范围状态并下传给图表组件

#### 1.1 在 `app/pages/tasks/index.vue` 新增/复用仿真范围状态

`selectedTask`（line 79）从 `taskApi.getState(taskId)` 拿到的 `ComputeTask` 已经包含：
- `sim_start_time: string`（如 `"0:00"`）
- `sim_end_time: string | null`（如 `"24:00"`，`null` 表示未设置终点）

新增一个 computed：

```ts
const taskSimRange = computed(() => {
  const start = selectedTask.value?.sim_start_time ?? '0:00'
  const end = selectedTask.value?.sim_end_time ?? null
  return { start, end, endMinutes: end ? tsToMinutes(end) : null }
})
```

把它作为 props 传给需要裁剪的图表组件：
- `TaskSeriesChart`（运行总览）
- `EnergyFlowChart`（能流平衡）
- `FlexibilitySeriesChart`（系统灵活性）
- `DeviceFlexibilityChart`（设备灵活性）

> 设备出力分析 (`DeviceOutputAnalysis.vue`) 已经通过 `:sim-end-time` 做了类似裁剪，保持现状即可，可统一改为接收新的 `taskSimRange` 以支持 start 不为 0 的场景，但不在本次必须范围内。

#### 1.2 新增公共时间工具 `utils/timeLabel.ts`

当前 `tsToMinutes` / `minutesToLabel` 在多个组件里重复实现。建议新增一个纯工具文件：

```ts
export function timeLabelToMinutes(ts: string): number
export function minutesToTimeLabel(m: number): string
export function isTimeInRange(ts: string, start: string, end: string | null): boolean
```

让 `index.vue`、四个图表组件、`utils/deviceOutputData.ts` 统一复用，避免再复制。

#### 1.3 各图表组件改造

**运行总览 — `TaskSeriesChart.vue`**
- 新增 props：`simStartTime?: string`、`simEndTime?: string | null`。
- 在 `render()` 中过滤 series data：
  ```ts
  const min = timeLabelToMinutes(props.simStartTime ?? '0:00')
  const max = props.simEndTime ? timeLabelToMinutes(props.simEndTime) : Infinity
  const data = points
    .filter(p => { const m = timeLabelToMinutes(p.ts); return m >= min && m < max })
    .map(p => [timeLabelToMinutes(p.ts), truncateSeriesValue(p.value)] as [number, number])
  ```
- xAxis 仍用 `type: 'value'`，保持 `min: 0`（或 `min` 设为 `min`）。

**能流平衡分析 — `EnergyFlowChart.vue`**
- 新增 props：`simStartTime?: string`、`simEndTime?: string | null`。
- 在生成 `allTsSet` 之前先过滤每个 `getVarData` 返回的 `Point[]`：
  ```ts
  const startMin = timeLabelToMinutes(props.simStartTime ?? '0:00')
  const endMin = props.simEndTime ? timeLabelToMinutes(props.simEndTime) : Infinity
  ```
- 用过滤后的数据生成 `allTs` 与 xAxis category labels。
- 源/荷贡献度 sidebar（`calcContribution`）也应基于过滤后的数据求和，否则汇总卡片与图表不一致。

**系统灵活性评估 — `FlexibilitySeriesChart.vue`**
- 已有 `rangeStartMinutes` / `rangeEndMinutes` 与 `DualRangeSlider`。
- 新增 props：`simStartTime?: string`、`simEndTime?: string | null`。
- 当 props 变化或初始化时，把 slider 范围重置为仿真范围：
  ```ts
  rangeStartMinutes.value = timeLabelToMinutes(props.simStartTime ?? '0:00')
  rangeEndMinutes.value = props.simEndTime ? timeLabelToMinutes(props.simEndTime) : sliderMax.value
  ```
- `visibleRows` 过滤逻辑不变，但默认值受仿真范围约束；slider 的 max 不应超过 `simEndTime`（若已设置）。

**设备灵活性评估 — `DeviceFlexibilityChart.vue`**
- 新增 props：`simStartTime?: string`、`simEndTime?: string | null`。
- 过滤 `timeline` 与 `props.rows` 到 `[start, end)`：
  ```ts
  const visibleRows = computed(() => props.rows.filter(row => isTimeInRange(row.timestamp, start, end)))
  const timeline = computed(() => [...new Set(visibleRows.value.map(r => r.timestamp))].sort(...))
  ```
- `valueByDirection` 与 `peak` 改用 `visibleRows`。

### 2. 后端：经济性评估按仿真范围截取

#### 2.1 新增通用截断工具 `backend/utils/timeseries_utils.jl`

在 `get_values` 附近新增：

```julia
function truncate_timeseries(ts::TimeSeries, sim_start::String, sim_end::Union{String,Nothing})
    start_min = time_label_to_minutes(sim_start)
    end_min = sim_end !== nothing ? time_label_to_minutes(sim_end) : nothing

    mask = map(ts.timestamps) do t
        m = time_label_to_minutes(t)
        m >= start_min && (end_min === nothing || m < end_min)
    end
    return TimeSeries(ts.timestamps[mask], ts.values[mask])
end
```

> 注意：`ts.timestamps` 在 `get_ts`/`query_ts` 中已按 `time_label_less_than` 排序，因此可以直接按时间比较。

#### 2.2 修改 `economy_evaluation_service.jl`

1. **`evaluate_task_economy` 签名扩展**（line 379）：
   ```julia
   function evaluate_task_economy(
       task_id::String,
       project_json::Dict;
       sim_start_time::Union{String,Nothing}=nothing,
       sim_end_time::Union{String,Nothing}=nothing,
   )
   ```

2. 在函数内设置默认值：
   ```julia
   sim_start = sim_start_time !== nothing ? sim_start_time : "0:00"
   sim_end = sim_end_time  # nothing 表示无终点
   ```

3. **`_safe_get_ts` 改为返回 `(values, timestamps)` 或 filtered `TimeSeries`**：
   - 当前返回 `ts.values`，下游所有 `calc_*` 函数接收 `Vector{Float64}`。
   - 为最小化改动，新增：
     ```julia
     function _safe_get_ts_values(db_path, data_key, sim_start, sim_end)
         ts = get_ts(db_path, data_key)
         ts === nothing && return Float64[]
         filtered = truncate_timeseries(ts, sim_start, sim_end)
         return filtered.values
     end
     ```
   - 把 `_safe_get_ts` 的调用全部替换为 `_safe_get_ts_values(..., sim_start, sim_end)`。

4. **`load_slack_data`（lines 213-262）SQL 结果按时间过滤**：
   - 当前直接 `sum(values)`。
   - 改为：
     ```julia
     values = Float64[]
     for (ts_label, val) in zip(data_rows[1], data_rows[2])
         m = time_label_to_minutes(ts_label)
         m >= start_min && (end_min === nothing || m < end_min) && push!(values, val)
     end
     total = sum(values) * penalty_rate
     ```

5. **`load_component_data` 与所有 `calc_*` 调用链**：
   - `load_component_data` 本身不需要知道 range，只需要在内部用 `_safe_get_ts_values(..., sim_start, sim_end)`。
   - 对所有 layer 都应用同一范围；layer1 的复制后半段自然被过滤掉（因为它的时间标签 ≥ sim_end）。

#### 2.3 修改 `backend/routes/task.jl`

在 `GET /api/task/{id}/economy` handler（lines 281-300）：

```julia
task = get_task(id)
# ... status check ...
project_json = ...
result = evaluate_task_economy(
    id, project_json;
    sim_start_time=get(task, "sim_start_time", nothing),
    sim_end_time=get(task, "sim_end_time", nothing),
)
```

#### 2.4 处理 `sim_end_time === nothing`

- 在线模式或手动取消的任务可能没有 `sim_end_time`。
- 经济评估 fallback：对 layer1 只取前 `length` 个点（即时间 < sim_start + layer length）。
- 更简单的实现：当 `sim_end === nothing` 时，对每个 layer 用 `sim_start + layer["length"]` 作为终点。该值可从 `time_str_to_minutes(layer["length"])` 得到。
- 建议把 fallback 逻辑封装进 `truncate_timeseries` 的调用方：
  ```julia
  effective_end = sim_end !== nothing ? sim_end : minutes_to_time_label(start_min + time_str_to_minutes(layer["length"]))
  ```

### 3. 文件变更清单

| 文件 | 变更 |
|---|---|
| `app/utils/timeLabel.ts` | **新增**：`timeLabelToMinutes`、`minutesToTimeLabel`、`isTimeInRange` |
| `app/pages/tasks/index.vue` | 新增 `taskSimRange` computed；把 `simStartTime`/`simEndTime` 传给 `TaskSeriesChart`、`EnergyFlowChart`、`FlexibilitySeriesChart`、`DeviceFlexibilityChart` |
| `app/components/TaskSeriesChart.vue` | 新增 props；按范围过滤 data |
| `app/components/EnergyFlowChart.vue` | 新增 props；按范围过滤 `Point[]`、`allTs`、贡献度 |
| `app/components/FlexibilitySeriesChart.vue` | 新增 props；初始化/约束 slider 范围到仿真范围 |
| `app/components/DeviceFlexibilityChart.vue` | 新增 props；过滤 `rows` 与 `timeline` |
| `backend/utils/timeseries_utils.jl` | 新增 `truncate_timeseries` |
| `backend/services/economy_evaluation_service.jl` | `_safe_get_ts` → `_safe_get_ts_values`；`load_component_data` 透传 range；`load_slack_data` 按标签过滤；`evaluate_task_economy` 签名扩展 |
| `backend/routes/task.jl` | economy endpoint 把 task 的 sim range 传给 `evaluate_task_economy` |

### 4. 边界与注意事项

- **layer1 复制消除原理**：复制段的时间标签从 `sim_start + length` 开始，只要 `sim_end <= sim_start + length`，截取后只剩真实计划段。
- **overlay 模式**：`set_ts_merge` 会让后续窗口覆盖前窗口；最终 layer1 在 DB 里保留的是最后一个窗口的 2× 数据。截取到 `[sim_start, sim_end)` 后，只保留真实计划段。
- **下层的 overlay 数据**：低层没有复制，但同样可能超过 `sim_end`（如最后一个不完整的 forward 步）。统一按 `[sim_start, sim_end)` 截取可保证前后端一致。
- **时间标签格式**：所有比较通过 `time_label_to_minutes` 完成，不能直接用字符串比较。
- **`sim_end_time` 为 null**：经济评估按每层 `length` 截断；前端图表按数据最大时间展示。
- **FlexibilitySeriesChart 的 slider**：slider 初始范围固定为 `[sim_start, sim_end)`，且 `sliderMax` clamp 到 `simEndMinutes`，用户只能在该区间内缩放/平移，不能查看复制段。
- **DeviceFlexibilityChart**：目前没有 slider，直接按仿真范围过滤数据与 timeline。
- **性能**：前端过滤在渲染时做，数据量小；后端过滤只影响经济评估 endpoint，不改动求解流程。

### 5. 验证步骤

1. 创建一个 24h 任务（`simStartTime=0:00`, `simEndTime=24:00`）。
2. 运行完成后：
   - 运行总览：每个 layer1 曲线只显示到 24:00，不应出现 25:00-48:00 的复制段。
   - 能流平衡：x 轴终点为 24:00，源/荷 sidebar 求和与图表一致。
   - 系统/设备灵活性：slider 默认 0:00-24:00，图表只显示该区间。
   - 经济性分析：layer1 的“运维成本/购电/售电/启停”等数值约为未修改前的一半（若原值为严格 2×）。
3. 直接查询 `timeseries.db` 确认 layer1 仍然保存了 48h 数据（求解逻辑不变），只是前端/经济评估做了裁剪。
4. 测试 `sim_end_time=null` 的在线任务：经济评估应能正常返回，且 layer1 只计算 24h。
