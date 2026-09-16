# Julia 后端与模型规范

## 1. 模块分层和设计意图

| 层 | 代码位置 | 只负责 | 不应负责 |
|---|---|---|---|
| HTTP 控制面 | `backend/server.jl`、`backend/routes/` | 参数入口、响应、鉴权/CORS、调用服务 | 直接建模、直接建表、长时间求解 |
| 任务调度 | 当前 `backend/services/task_manager.jl`，目标 `supervisor/` | 队列、状态、资源令牌、worker 生命周期 | 在 supervisor 进程内运行 JuMP 求解 |
| 业务服务 | `backend/services/` | 解析、边界注入、模型编排、结果转换 | 拼装 HTTP 响应、依赖页面字段 |
| 容量规划 | `backend/services/capacity_planning/` | 变量、场景、候选方案、经济评价 | 绕过通用 worker 和模型契约 |
| 核心抽象 | `backend/core/` | 类型、schema、灵活性、公共数学语义 | 文件路径、HTTP、UI 标签 |
| 组件模型 | `backend/components/<component>/` | 单组件结构、校验、模型、结果绑定、灵活性 | 读取整个项目或修改全局状态 |
| 存储工具 | `backend/utils/timeseries_utils.jl` 等；目标 `storage/` | SQLite、schema、迁移、事务、查询 | 业务状态推断 |

调用方向只能从上向下；`components` 可依赖 `core`，不能依赖 route。业务线新增能力优先扩展 service/adapter，不在 route 内复制模型逻辑。

## 2. 当前启动上下文

`backend/server.jl` 负责加载 Oxygen/HTTP/SQLite、核心模块、服务和 route，然后初始化任务与容量规划存储并监听端口。当前端口读取 `ENV["PORT"]`，默认 8080；数据目录又在其他文件按 `@__DIR__` 或 cwd 推导，配置来源尚未统一。

目标启动流程：

1. 解析 `AppConfig`：部署模式、HTTP 地址、dataRoot、日志、并发、求解器和许可证；
2. 检查绝对目录、写权限、数据库版本、求解器可用性；
3. 完成 schema migration；
4. 启动 supervisor 和 worker 资源管理；
5. 注册 HTTP/WebSocket；
6. health/readiness 分别报告“服务存活”和“可以接收计算”。

## 3. 多进程任务目标架构

### 3.1 控制面

supervisor 常驻但不求解。建议结构：

```text
HTTP/BFF
  -> TaskService
     -> TaskRepository (tasks.db)
     -> Scheduler (队列、优先级、资源令牌)
     -> WorkerManager (spawn/heartbeat/cancel/reap)
        -> WorkerProcess(taskId)
```

每个任务固化：`taskId`、`projectId`、`canvasId`、输入快照 hash、业务线/任务类型、求解器配置、资源需求和工作目录。任务开始后不得再从 `activeCanvasId` 或可变项目文件读取输入。

### 3.2 worker 隔离

一个 worker 同时只执行一个任务，拥有：

- 独立 Julia 进程；
- 独立 COPT/JuMP 会话；
- `tasks/<taskId>/` 工作目录；
- 独立 `timeseries.db`、日志、生成代码、trace、manifest；
- 只读组件 schema 版本和任务输入快照。

worker 不直接更新全局 tasks.db。它通过版本化消息报告进度，supervisor 负责持久化状态，避免多进程争写控制库。

### 3.3 worker 协议

最小消息：

| 消息 | 方向 | 必填字段 |
|---|---|---|
| `worker.ready` | worker→supervisor | pid、workerVersion、schemaHash、solver |
| `task.start` | supervisor→worker | taskId、snapshotPath、workDir、solverConfig |
| `task.progress` | worker→supervisor | taskId、stage、layerId、simTime、percent |
| `task.heartbeat` | worker→supervisor | taskId、pid、rss、lastProgressAt |
| `task.cancel` | supervisor→worker | taskId、reason |
| `task.completed` | worker→supervisor | taskId、resultManifest、checksums |
| `task.failed` | worker→supervisor | taskId、errorCode、message、diagnosticsPath |

消息需包含 `protocolVersion` 和递增 `seq`；supervisor 对重复消息幂等，对乱序消息拒绝回退状态。

### 3.4 调度和资源

- 最大 worker 数不是常量，由 CPU、内存、COPT license seats、单任务 threadCount 的最小约束决定。
- 调度器先入队，再原子占用资源令牌，spawn 成功后转 starting/running。
- 允许预热空 worker，但接收任务前必须验证无残留模型、数据库句柄和全局缓存。
- 超时分为启动超时、心跳超时、无进度超时和业务总时限；各自错误码不同。
- worker 异常退出只影响当前任务；supervisor/API 继续服务并回收资源令牌。

## 4. 状态机规范

### 4.1 离线计算

```text
pending -> queued -> starting -> parsing -> building -> solving
        -> completed | failed | cancelling -> cancelled | interrupted
```

离线任务不提供 pause/resume。`cancel` 是可控终止，`interrupted` 是进程/服务异常中断，两者不可混为一谈。cleanup 不是状态迁移，它是终态后的显式数据操作。

### 4.2 在线预测控制

在线业务单独扩展：

```text
running -> pausing -> paused -> resuming -> running
running/paused -> switching -> running(new strategy)
```

恢复时按当前真实时间重建 SOC、库存、启停、测量新鲜度和上层计划，不承诺从旧离线时间点继续。策略切换必须保留来源策略、目标策略和切换原因。

## 5. 组件目录契约

每个 `backend/components/<component>/` 当前通常包含：

| 文件 | 职责 |
|---|---|
| `component.jl` | 组件结构、类型标识、结果绑定 |
| `validation.jl` | 字段和物理规则校验 |
| `model-common.jl` | 参数解析和新旧模型共享函数 |
| `model-base.jl` | 可读数学蓝图/基准实现 |
| `model.jl` | 带跟踪、代码生成的生产实现 |
| `flexibility.jl` | 单体灵活性能力与约束 |

新增组件步骤：

1. 在 Component Schema 新增元数据、端口、单位、参数和状态能力；
2. 运行代码生成，得到前端表单/类型和 Julia 静态元数据；
3. 实现上述六类 Julia 文件；
4. 在构造注册表和标准入口 include；
5. 为每个支持状态提供正例、边界例、非法例；
6. 加入电/热/气/氢节点平衡和结果绑定测试；
7. 若支持灵活性，验证 up/down 定义、基线和系统汇总守恒。

## 6. 模型构建习惯

- 公开构建函数使用动词开头，修改 JuMP 模型的函数以 `!` 结尾。
- 组件参数先经 `resolve_*_params` 形成具名结构，再进入约束构建；不要在约束循环中反复读深层 Dict。
- 状态分派使用 `Val(Symbol(status))` 时必须有明确 fallback 错误，禁止静默按 stand_alone 处理。
- 生产模型和跟踪模型必须共享参数解析与物理校验，不能形成两套公式。
- `all_layers`/`max_layer_id` 是必需上下文；禁止缺省为 3。
- 结果变量通过 ResultBinding 注册；页面不依赖 Julia 内部变量对象名称猜测语义。
- 约束名和生成代码应包含稳定组件 code，便于从错误回到画布节点。

## 7. 数值和求解器规范

当前存在 `BIG_M=1e10`、`SLACK_BIG_M=1e8`、`SLACK_PENALTY_DEFAULT=1e6`、failure penalty `1e18` 以及多组 `1e-6/1e-9`。这些值必须迁移到统一的 NumericPolicy：

```text
NumericPolicy
  unitBase            # kW/kWh/元等内部基准
  feasibilityAtol
  comparisonRtol
  coefficientScale
  deriveBigM(bounds, context)
  deriveSlackPenalty(objectiveScale, priority)
```

规则：

- 能从变量上下界推导 M 时禁止固定大数；
- penalty 必须显著高于正常目标边际成本，但不得大到破坏数值条件；
- 每次任务保存最终 M、penalty、容差和推导依据；
- solver adapter 统一 COPT 与开源求解器状态到内部 `SolverOutcome`；
- 求解器专有配置不泄漏到组件模型。

## 8. 错误抽象

错误至少分：CONFIG、DATA、MODEL、SOLVER、RESOURCE、PROCESS、STORAGE、INTERNAL。标准错误包含：

```text
code, category, userMessage, developerMessage,
taskId, projectId, canvasId, componentId?, layerId?, simTime?,
cause?, diagnosticsPath?, retryable
```

route 只映射 HTTP 状态；service 产生领域错误；worker 保存诊断。禁止只返回 Julia stack trace，也禁止把所有异常改成“计算失败”。

## 9. 测试层次

1. 组件单元：各状态公式、上下界、结果绑定；
2. 物理校验：介质、端口、容量、储能状态、网络拓扑；
3. 小系统：电/热/气/氢能量平衡和多层滚动；
4. solver adapter：COPT 与开源求解器状态/容差一致性；
5. worker：取消、崩溃、超时、资源回收；
6. supervisor：并发、排队、许可证令牌、重启对账；
7. 业务黄金案例：四条业务线各自维护输入、输出和允许误差。

## 10. 禁止事项

- route 内直接 `SQLite.execute(CREATE TABLE...)`；
- 生产代码依赖 cwd 或测试任务路径；
- supervisor 进程执行 JuMP optimize；
- 多个任务共享可写 store、solver model 或 signal channel；
- 页面字段名直接成为 Julia 内部约束语义而无 DTO/adapter；
- 新增固定大数、隐式单位、固定层数或固定端口；
- 为节省磁盘自动删除历史生成代码和 trace。
