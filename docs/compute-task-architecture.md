# 计算任务（Simulation Compute Task）架构方案

> 状态：方案已定，待实施
> 最后更新：2026-07-07

本文档覆盖前后端完整流程，针对"仿真计算"按钮触发的端到端业务：
任务创建 → 解析 → 构建模型 → 求解 → 时序数据回写 → 前端实时渲染 → 暂停/恢复/取消/清理。

---

## 1. 核心概念与术语

| 术语 | 含义 |
|---|---|
| **任务 (Task)** | 用户点一次"仿真计算"产生的独立计算单元；有自己的线程、配置文件、时序数据库 |
| **项目 boundary DB** | 每个项目一份 boundary 时序数据（`data/projects/<id>/boundary.db`）；项目内所有画布共用 |
| **`sim_time`** | 调度世界里的"当前时刻"（任务元数据里的 `current_time`） |
| **`real_time`** | 物理世界时间 |
| **离线模式 (offline)** | 以求解器最快速度推进 `sim_time`；不解的部分立刻接着解下一段 |
| **在线模式 (online)** | `sim_time` 跟随 `real_time` 同步推进；每解完一步要等真实物理时间到下一步才继续解 |
| **任务层 (layer)** | 任务绑定的时层（日前 / 日内 / 实时 等），决定 `step` 步长和 `sim_end_time` 的范围 |
| **边界注入** | 任务启动时，从项目 boundary DB 按 `boundaryId` + `layerId` 拷贝到任务自己的 TS DB |

> 在线模式设计原则（与用户确认）：
> 1. `sim_time` 始终 = `real_time`（**不允许超前**）
> 2. `pause` 后 `sim_time` 不前进；`resume` 时 `sim_time` **跳到当前 `real_time`**（跳过暂停期间流逝的现实时间），从该点重新对齐起步

---

## 2. 实际产品效果

### 2.1 用户视角
- 编辑器工具栏点"仿真计算" → 后台立刻建一个任务 → 解析、build、开始求解
- 同时可以打开"任务列表"查看所有历史任务
- 实时图表面板订阅任务的 WebSocket，每时间步更新一次
- 任务列表可过滤 / 删除 / 查看

### 2.2 数据完全隔离
每个任务自带：
- 一个 Julia 协程（`@async` 启动）
- 一份 `component.json` / `connection.json` / `mapping.json` 配置
- 一个独立的 SQLite 时序数据库文件

不同任务之间除共享 OS 资源（CPU / 内存 / 磁盘）外**无任何数据耦合**。

---

## 3. 目录结构

```
backend/
├── data/
│   ├── tasks.db                      # 全局任务元数据 DB（一份）
│   ├── projects/
│   │   └── <project_id>/
│   │       └── boundary.db            # 该项目的 boundary TS DB（一个项目一份，所有画布共用）
│   └── tasks/
│       ├── <task_uuid_1>/
│       │   ├── timeseries.db        # 该任务的求解结果时序数据
│       │   ├── component.json       # parse 产物
│       │   ├── connection.json
│       │   └── mapping.json
│       ├── <task_uuid_2>/
│       │   └── ...
│       └── ...
├── services/
│   ├── task_manager.jl                # 新增：任务生命周期管理
│   ├── simulation_runner.jl           # 新增：求解主循环
│   ├── boundary_seeder.jl             # 新增：从 project boundary DB 注入任务 DB
│   └── ...
└── routes/
    ├── task.jl                        # 新增：REST + WebSocket
    └── ...
```

> **关键变更（2026-07-07 用户补充）**：
> - 旧的全局 `backend/data/timeseries.db` **不再使用**——boundary TS 数据按**项目**拆分
> - 每个项目有自己的 `data/projects/<project_id>/boundary.db`，项目内所有画布共享
> - 计算任务启动时从这个**项目级** boundary DB 注入数据到任务 DB
> - 项目 / boundary / 任务的关联完全靠**文件路径约定**实现，无需额外映射表
> - 项目级 boundary DB 由**项目创建时**自动建立（空文件也可），项目删除时一并清理

### 3.1 三种 DB 的关系

```
项目级 boundary DB（projects/<id>/boundary.db）
   │  source_id = boundary.id（沿用现有约定）
   │  被所有属于该项目的 canvas 共享
   │  由 boundary 业务写入（import/transform/submit/delete）
   ▼
   任务级 DB（tasks/<task_id>/timeseries.db）
   │  source_id 同样 = boundary.id
   │  启动时从项目级 DB 拷贝 + 求解过程中追加新数据
   │  任务结束 = 数据独立，与项目级 DB 解耦
```

> 任务级 DB 不再写回项目级 DB——它是**只读起点 + 求解结果**的快照，任务结束后即使项目级 DB 修改也不影响。

---

## 4. 数据库 Schema

### 4.1 `backend/data/tasks/tasks.db`（任务元数据，全局一份）

```sql
CREATE TABLE tasks (
    id              TEXT PRIMARY KEY,           -- UUID v4
    project_id      TEXT NOT NULL,
    canvas_id       TEXT NOT NULL,
    layer_id        TEXT NOT NULL,              -- 绑定的时层 id（"1".."5"）
    mode            TEXT NOT NULL,              -- 'online' | 'offline'
    name            TEXT,                       -- 可选用户命名
    status          TEXT NOT NULL,              -- 'pending'|'parsing'|'building'|'solving'|'paused'|'completed'|'failed'|'cancelled'
    params_hash     TEXT NOT NULL,              -- 组件配置指纹（SHA256 of normalized JSON）
    sim_start_time  TEXT NOT NULL,              -- 模拟起点（"H:MM"）
    sim_end_time    TEXT,                       -- 模拟终点；NULL = 跑到手动取消
    current_time    TEXT,                       -- 当前求解到的时刻（pause/resume 关键）
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    started_at      TEXT,                       -- 首次进入 solving 的时刻
    finished_at     TEXT,                       -- 进入终态的时刻
    error_message   TEXT,                       -- 失败原因
    extra_json      TEXT                        -- 求解器配置、并发度等扩展
);
CREATE INDEX idx_tasks_project ON tasks(project_id);
CREATE INDEX idx_tasks_status  ON tasks(status);
```

### 4.2 `backend/data/tasks/<uuid>/timeseries.db`（每任务独立）

跟全局 boundary TS DB 同 schema，**不加 task_id 列**（文件本身就标识任务）。复用 `utils/timeseries_utils.jl` 已有函数：

```sql
CREATE TABLE time_series_meta (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id   TEXT NOT NULL,
    var_name    TEXT NOT NULL,
    remark      TEXT NOT NULL,
    layer_id    TEXT NOT NULL,
    created_at  TEXT DEFAULT (datetime('now')),
    updated_at  TEXT DEFAULT (datetime('now')),
    UNIQUE(source_id, var_name, remark, layer_id)
);

CREATE TABLE time_series_data (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    series_id   INTEGER NOT NULL REFERENCES time_series_meta(id) ON DELETE CASCADE,
    ts          TEXT NOT NULL,
    value       REAL NOT NULL
);
```

> **`SQLiteTimeSeriesStore` 重构点**：构造函数硬编码路径 → 接受 `db_path` 参数。改动小，所有调用方适配传 `backend/data/tasks/<task_id>/timeseries.db`。

---

## 5. 任务生命周期

```
       ┌──────────┐
   创建 │ pending  │
       └────┬─────┘
            ▼
       ┌──────────┐
       │ parsing  │ ─── parse_project 失败 ──► failed
       └────┬─────┘
            ▼
       ┌──────────┐
       │ building │ ─── build_model 失败 ──► failed
       └────┬─────┘
            ▼
       ┌──────────┐
       │ solving  │ ─── 求解过程异常 ─────► failed
       └────┬─────┘
            │
       ┌────┴─────────────┐
       │                  │
       ▼                  ▼
   ┌──────────┐    ┌────────────┐
   │  paused  │    │ completed  │ (sim_time 到达 sim_end_time)
   └────┬─────┘    └────────────┘
        │ resume
        ▼
   (回 solving)
            │
            ▼ 手动 cancel
       ┌────────────┐
       │ cancelled  │ (数据保留)
       └────────────┘
```

| 状态 | TS 数据保留 | 任务列表显示 | 可恢复动作 |
|---|---|---|---|
| pending / parsing / building | 仅元数据 | 是（灰色） | cancel → cancelled |
| solving | 持续追加 | 是 | pause → paused；cancel → cancelled |
| paused | 全部保留 | 是 | resume → solving；cancel → cancelled |
| completed | 全部保留 | 是（绿色） | DELETE 显式清理 |
| failed | 部分保留（看失败点） | 是（红色） | DELETE 显式清理 |
| cancelled | 全部保留 | 是（黄色） | DELETE 显式清理 |

**DELETE 是单独的"清理"动作**（用户确认），不与 cancel 联动——这样用户能"取消但保留数据以便事后查看"。

---

## 6. 求解主循环

### 6.1 离线模式

```
while sim_time < sim_end_time:
    if pause_requested(task_id):
        update_task(status="paused", current_time=sim_time)
        notify_ws("paused", sim_time)
        return                              # 协程退出
    if cancel_requested(task_id):
        update_task(status="cancelled", current_time=sim_time)
        notify_ws("cancelled", sim_time)
        return

    step_results = solve_one_step(params, sim_time, sim_time + step)
    write_step_results(task_store, step_results)         # 每时间步一次
    notify_ws("data", rows=step_results)

    sim_time += step
    update_task(current_time=sim_time)
update_task(status="completed", finished_at=now())
notify_ws("completed", finalTime=sim_time)
```

### 6.2 在线模式（sim_time = real_time 联动）

```
while true:
    if sim_time >= sim_end_time:
        update_task(status="completed", finished_at=now())
        notify_ws("completed", finalTime=sim_time)
        return

    if cancel_requested(task_id):
        update_task(status="cancelled", current_time=sim_time)
        notify_ws("cancelled", sim_time)
        return

    if pause_requested(task_id):
        # 暂停仅是标记当前步后退出，不推进 sim_time
        update_task(status="paused", current_time=sim_time)
        notify_ws("paused", sim_time)
        return

    # 在线核心：等真实物理时间走到下一步
    now = real_wall_clock()
    if now < sim_time + step:
        sleep_until(sim_time + step)
        continue   # 再检查一次 pause/cancel/条件

    step_results = solve_one_step(params, sim_time, sim_time + step)
    write_step_results(task_store, step_results)
    notify_ws("data", rows=step_results)

    sim_time += step
    update_task(current_time=sim_time)
```

> 在线模式 `sim_start_time` 强制 ≤ 任务创建时的 `real_time`。
> 若 `sim_end_time = NULL` → 在线任务永远跑下去直到 cancel。

---

## 7. Pause / Resume 语义

| 模式 | pause 行为 | resume 行为 |
|---|---|---|
| offline | 等当前步写完 → `current_time = sim_time` → 状态 `paused` → 协程退出 | 重新 build → 从 `current_time` 接着解（重 build 是为了对齐 solve 上下文；要不要缓存模型看后续优化） |
| online | 等当前步写完 → `current_time = sim_time` → 状态 `paused` → 协程退出 | `current_time` 跳到当前 `real_time` → 重新 build → 从该点解（**丢掉暂停期间流逝的物理时间**） |

实现上 pause/resume 用 `Channel{String}`（每任务一个）作为信号通道：

```julia
const signal_ch = Channel{String}(Inf)  # "pause" | "resume" | "cancel"
put!(signal_ch, "pause")    # 由 API 路由调用
take!(signal_ch)            # 由 solve_loop 在每步开头 check
```

---

## 8. Cancel / Cleanup 语义

| 动作 | 触发方式 | 效果 |
|---|---|---|
| Cancel | `POST /:id/cancel`（用户主动） | 协程退出 → 状态 `cancelled` → **数据全部保留** |
| Cleanup | `DELETE /:id`（用户主动） | 删 `tasks/<id>/` 整目录 + `tasks.db` 那条记录 → 任务从列表消失 |

> **不联动**：cancel 不会自动删数据；cleanup 是独立动作。允许用户"取消但保留历史"。

---

## 9. 边界注入流程

任务启动时，需要把 boundary 数据从**该项目级** DB 复制到任务自己的 DB：

```julia
function seed_task_db(task_id, project_id, layer_id)
    src_path = "data/projects/$project_id/boundary.db"
    dst_path = "data/tasks/$task_id/timeseries.db"
    src_db = SQLiteTimeSeriesStore(src_path)
    dst_db = SQLiteTimeSeriesStore(dst_path)

    # 读该项目在目标 layer 下的所有 planned 边界
    for (source_id, var_name) in list_meta(src_db, layer_id=layer_id, remark="planned"):
        ts = get_ts(src_db, build_label(source_id, var_name, "planned", layer_id))
        if ts !== nothing:
            set_ts(dst_db, build_label(source_id, var_name, "planned", layer_id), ts)
end
```

> `source_id = boundary.id`（沿用现有 boundary 业务约定），与项目级 DB 的 key 兼容。
>
> **重要**：不再从全局 DB 读取。任务启动时项目级 DB 才是 boundary 数据的唯一来源。

---

## 10. API 设计

### 10.1 REST

| 路径 | 方法 | 请求体 | 响应 |
|---|---|---|---|
| `/api/task/create` | POST | `{projectId, canvasId, layerId, mode, simStartTime?, simEndTime?, name?, solveConfig?}` | `{taskId, status: "pending"}` |
| `/api/task/list` | GET | query: `projectId?, status?` | `[{id, status, currentTime, ...}]` |
| `/api/task/:id/state` | GET | — | `{id, status, mode, currentTime, simEndTime, startedAt, finishedAt, errorMessage}` |
| `/api/task/:id/pause` | POST | — | `{success: true}` |
| `/api/task/:id/resume` | POST | — | `{success: true}` |
| `/api/task/:id/cancel` | POST | — | `{success: true}` |
| `/api/task/:id` | DELETE | — | `{success: true, deleted: "<taskId>"}` |
| `/api/task/:id/data` | GET | query: `layerId, varName?, sourceId?, fromTime?, toTime?` | `[{sourceId, varName, layerId, ts, value}, ...]` |
| `/api/ingest/ts/:taskId` | POST | `{sourceId, varName, layerId, remark?, ts, value}` | `{success: true}` |

### 10.2 WebSocket `/ws/task/:id`

**服务端 → 客户端**：

```json
{ "type": "status",     "status": "solving",  "currentTime": "24:00" }
{ "type": "data",       "rows": [{ "sourceId":"WT", "varName":"E_WT", "layerId":"1", "ts":"24:00", "value":1234.5 }] }
{ "type": "paused",     "currentTime": "24:00" }
{ "type": "resumed",    "currentTime": "168:00" }
{ "type": "completed",  "finalTime": "120:00" }
{ "type": "failed",     "error": "..." }
{ "type": "cancelled",  "currentTime": "..." }
```

**客户端 → 服务端**：

```json
{ "type": "pause" }
{ "type": "resume" }
{ "type": "cancel" }
```

---

## 11. 并发与锁

- **任务间**：每任务独立 Julia 协程 + 独立 DB 文件 → **无锁竞争**
- **同一任务内**：求解器是单写者（每时间步写一次）；第三方 ingest 也可能并发写 → 用 `Channel` 串行化（同 task 的所有 DB 写操作走同一队列）
- **跨进程**（重启 / 第三方平台）：每个 task DB 一个 SQLite 连接，SQLite WAL + `busy_timeout`
- **同时运行任务数**：配置项 `MAX_CONCURRENT_TASKS`（默认 8），超出排队
- **求解线程分配**：`Threads.@spawn` 让求解跑在独立线程，避免阻塞 Oxygen HTTP 主循环

---

## 12. 启动恢复

服务重启时扫 `data/tasks/tasks.db`：

| 重启前 status | 重启后 status | 原因 |
|---|---|---|
| pending / parsing / building | failed | 进程死了，半成品没意义 |
| solving | paused | 求解协程已死，标 paused 让用户决定 resume |
| paused | paused | 保留，用户可手动 resume |
| completed / failed / cancelled | （保持） | 终态不变 |

启动时**不**自动 resume solving 任务——避免用户重启服务器时被意外重启多个求解。

---

## 13. 外部数据接入（第三方平台）

### 13.1 第三方写项目级 boundary DB

第三方采集 / 预测平台推送的是**项目的输入数据**，不是任务的计算结果：

```
POST /api/ingest/project/<projectId>/boundary
{
  "sourceId": "sensor_001",
  "varName": "wind_speed",
  "layerId": "1",
  "remark": "actual",          // 或 "predict"
  "ts": "0:00",
  "value": 8.5
}
```

写到 `data/projects/<projectId>/boundary.db`。下次启动任务时会被自动注入。

### 13.2 第三方写任务级 DB（实时仿真接入）

如果第三方想看任务的中间结果或注入实际测量到任务：

```
POST /api/ingest/ts/<taskId>
{
  "sourceId": "...",
  "varName": "...",
  "layerId": "...",
  "remark": "actual",
  "ts": "...",
  "value": ...
}
```

后端校验：
1. 任务存在 + status ∉ {failed, cancelled}
2. 通过同任务的 `Channel` 串行写 DB
3. 写完后 WS 推 `data` 给该任务的所有订阅者

支持场景：第三方采集平台 → 直接 POST；预测平台 → POST 写 `remark="predict"`。

---

## 14. 前端流程

```
[工具栏"仿真计算"按钮]
    ↓
[POST /api/task/create] → { taskId }
    ↓
[打开 WS /ws/task/<taskId>]
    ↓
[订阅 status / data 消息]
    ↓
[实时图表组件订阅同 WS, 增量渲染]
    ↓
[任务列表页轮询 /api/task/list 刷新状态]
    ↓
[用户点暂停 → ws.send({type:"pause"}) / 后端收到 → Channel.put]
    ↓
[用户点取消 → DELETE 或 ws.send({type:"cancel"})]
```

任务列表页路径：`/tasks`（新页面），展示：
- 状态图标（pending/parsing/building/solving/paused/completed/failed/cancelled）
- 进度条（仅 solving 状态有）
- 启动时间 / 完成时间 / 当前时刻
- 操作按钮（暂停 / 继续 / 取消 / 清理 / 查看图表）

---

## 15. 数据流全景

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. 创建任务 (POST /api/task/create)                              │
│    - 校验 projectId / canvasId / layerId 存在                     │
│    - 生成 UUID, 写 tasks.db (status=pending)                      │
│    - 启动 @async 协程                                              │
└────────────────────┬────────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. 协程内: parse                                                  │
│    - update status=parsing                                         │
│    - parse_project(canvas) → component.json / connection.json      │
│    - 写 .json 到 tasks/<id>/                                       │
└────────────────────┬────────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. 协程内: build                                                   │
│    - update status=building                                       │
│    - build_model(...) → JuMP model                                │
│    - update status=solving                                         │
└────────────────────┬────────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. 边界注入 (任务启动前一次性)                                       │
│    - seed_task_db(task_id, project_id, layer_id)                   │
│    - 源: data/projects/<project_id>/boundary.db                  │
│    - 目的: data/tasks/<task_id>/timeseries.db                     │
│    - 读全局 TS DB, 写到 tasks/<id>/timeseries.db                  │
└────────────────────┬────────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. 求解主循环                                                      │
│    while sim_time < sim_end_time:                                  │
│       check pause/cancel signals                                   │
│       if online: sleep until real_time >= sim_time                 │
│       solve_one_step → step_results                                │
│       write_step_results(task_store, step_results)                │
│       notify_ws(task_id, "data", step_results)                     │
│       sim_time += step                                              │
│       update_task(current_time=sim_time)                           │
│    update_task(status=completed)                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 16. 实施阶段建议

按依赖顺序：

0. **Boundary 业务路径改造**（前置任务，必须先做）
   - `SQLiteTimeSeriesStore` 接受 `db_path` 参数
   - `server.jl` 的 5 个 boundary 路由 + BFF 从 `projectId`（路由参数）算出 `data/projects/<project_id>/boundary.db` 路径传入
   - `POST /api/project` 创建项目时自动 `mkpath("data/projects/<new_id>")` 并初始化空 DB
   - 旧 `data/timeseries.db` 直接 `rm` 清掉
1. **`services/task_manager.jl`** —— 任务 CRUD + 协程调度 + Channel 信号 + WS 订阅管理
2. **`services/boundary_seeder.jl`** —— 从项目级 DB 注入数据到任务 DB
3. **`services/simulation_runner.jl`** —— 求解主循环（offline / online 双模式 + pause/resume/cancel）
4. **`routes/task.jl`** —— REST + WebSocket
5. **前端 `pages/tasks/index.vue`** + 工具栏按钮 + 实时图表面板订阅
6. **外部 ingest 接口（项目级 + 任务级）+ 测试**

---

## 17. 关键实现细节与风险

| 项 | 风险 / 注意 |
|---|---|
| `SQLiteTimeSeriesStore` 重构 | 改动要兼容现有 boundary 业务（仍用全局 DB 路径） |
| Oxygen 3 WebSocket | 用 `@websocket` 宏；需验证重连 / 多任务路由分发 |
| 每时间步写 DB 性能 | LP 求解毫秒级，写库可控；MIP 每步可能分钟级，写 1ms 不是瓶颈 |
| Resume 重 build 代价 | build_model 通常秒级，可接受；要在 UI 提示"重建中..." |
| 多任务并发 | SQLite WAL + busy_timeout 即可；不需要外部锁服务 |
| 求解器协程异常捕获 | 协程里 `try/catch` 兜底，任何异常 → `status=failed` + `error_message` |
| WS 推送频率 | 每时间步一次 ≈ 用户看到的就是 "1h 一次" / "5min 一次" 的更新频次；够用 |
| 旧数据迁移 | `backend/data/timeseries.db` 废弃；如需迁移现有数据，按 boundary → relatedComponents → node → canvas → project 的链反向归位到 `data/projects/<project_id>/boundary.db`（一次性脚本） |

---

## 18. 已定决策（2026-07-07 用户确认）

| 决策项 | 选择 | 备注 |
|---|---|---|
| 项目 boundary DB 路径 | `data/projects/<project_id>/boundary.db`（**约定**，无映射表） | 简单直接 |
| 项目 boundary DB 创建时机 | **项目创建时**（`POST /api/project` 后端 mkpath + 初始化空 DB） | 最干净 |
| 旧 `data/timeseries.db` | **直接 `rm` 清掉** | 测试数据丢失，可接受 |
| Boundary 业务路径改造 | 同意（必做，是阶段 0 的前置） | 见 § 16 |
| 在线模式 `sim_time` 行为 | 必须 = `real_time`，**不允许超前** | 实现：solve loop 开头 `sleep_until(real_time >= sim_time)` |
| 在线模式 pause/resume | 暂停时 sim_time 不动；恢复时 sim_time **跳到当前 real_time** | 跳过暂停期间流逝的现实时间 |

## 19. 仍开放问题（待定）

| 问题 | 当前默认 | 影响 |
|---|---|---|
| `sim_end_time` 是否允许 NULL（跑无限久） | 允许；在线场景常见 | 需 UI 给出"无限"选项 |
| Resume 时是否缓存上一次 build 的 JuMP model | 不缓存（每次重 build） | 简单；后续可优化 |
| 多任务同时运行上限 | 默认 8（可配置） | 超过排队 |
| `sim_start_time` 精度 | "H:MM" 字符串 | 跟现有时层表示一致 |
| 任务超时机制 | 无（依赖手 cancel） | 后续可加 |
| 第三方 ingest 鉴权 | 暂用 Oxygen 同源（CORS 开放） | 后续接 API key / token |

---

## 19. 相关文件索引

| 文件 | 用途 |
|---|---|
| `backend/server.jl` | 现有入口，需追加 task 路由的注册 |
| `backend/services/timeseries_utils.jl` | TS 库工具（要重构接受 db_path） |
| `backend/services/boundary_service.jl` | 全局 boundary 服务（不动） |
| `backend/utils/timeseries_utils.jl` | 旧路径（已被 services/ 替代，注释保留） |
| `backend/services/model_service.jl` | 求解器入口（被 simulation_runner 调用） |
| `backend/services/boundary_service.jl` | `parse_boundary_data`（被 boundary_seeder 调用） |
| `app/pages/editor/[projectId].vue` | 加仿真按钮（已有 toolbar） |
| `app/pages/tasks/index.vue` | 新增任务列表页 |
| `docs/CODE_STANDARDS.md` | 命名 / 代码风格参考 |