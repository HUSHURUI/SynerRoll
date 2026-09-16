# 功能扩展与 TODO/风险索引

## 1. 先判断复用还是重构

| 需求 | 优先复用 | 需要重构的触发条件 |
|---|---|---|
| 新组件 | Component Schema、组件六文件模式、ResultBinding | 现有公共类型无法表达新介质/状态 |
| 新求解器 | solver adapter、SolverOutcome | 组件代码直接调用 COPT 专有 API |
| 新结果页 | task data/trace/economy API、共享图表 | 页面要猜 Julia 变量名或读项目 JSON 数组 |
| 新计算类型 | TaskSnapshot、worker 协议、supervisor | 必须在 API 进程内求解或共享可写状态 |
| 新画布能力 | workspace.canvases、canvas 子资源 | 功能仍依赖 activeCanvasId 选择计算输入 |
| 新边界类型 | Domain Schema、边界 SQLite | 前端枚举与 Julia key 各自添加 |
| 在线控制 | 组件/模型/结果公共层 | 试图在旧离线 pause 假入口上补逻辑 |
| 容量经济指标 | economic evaluator、方案 snapshot | 与运行优化使用不同成本口径 |

## 2. 四业务线扩展边界

### 容量设计软件（武玉琨，中石油）

主要目录：容量规划页面、`types/capacity-planning.ts`、`composables/api/useCapacityPlanningApi.ts`、BFF capacity routes、Julia `services/capacity_planning/`。复用计算内核的画布快照、worker、组件模型、边界和结果；不要另建一套组件或数据库真值。

### 灵活性软件（于恺，龙源）

主要目录：任务结果中的灵活性 UI、`config/flexibility.ts`、灵活性图表、Julia `core/flexibility.jl`、`core/system_flexibility.jl`、`services/flexibility_*` 和各组件 `flexibility.jl`。复用普通任务基线结果；必须区分设备、系统、POI 和需求来源。

### 在线预测控制软件（闫聪，中煤）

当前主要入口是 ingest routes 和 online task mode，完整在线状态机尚未实现。复用组件模型、滚动多层计算和 worker；新增数据接入、数据质量、真实时钟、策略切换、在线暂停/恢复和安全降级。

### 计算内核/母机（胡书瑞）

负责 Component Schema、项目/多画布契约、边界真值、supervisor/worker、模型构建、求解器、数据库、结果、错误、部署和公共 UI/API 规范。母机不替各业务线决定业务公式，但提供稳定扩展点和测试框架。

## 3. 当前 TODO 索引

| ID | TODO | 代码上下文 | 风险 | 计划归属 |
|---|---|---|---|---|
| T01 | 修正 Julia 环境并验证干净安装 | `backend/Project.toml`、Manifest | R01/R04 | K-001/K-003 |
| T02 | 统一 dataRoot/endpoint/AppConfig | server/BFF/Julia 路径 | R15/R17 | K-101/K-102 |
| T03 | 多画布任务快照全链路 | project/canvas/task/planning | R13 | K-104 |
| T04 | 边界 SQLite 单一真值 | boundary types/routes/services | R06 | K-105 |
| T05 | supervisor + per-task worker | task_manager/simulation_runner | R10 | K-201～K-204/K-207 |
| T06 | 说明并隔离离线/在线控制语义；预留接口暂不删除 | task routes/UI/types | R02/R11/R25 | K-205/K-308 |
| T07 | 在线策略暂停/切换/恢复 | ingest/online worker | R02/R11 | O-403/O-404 |
| T08 | 先关库后清理目录 | task delete/store registry | R08 | K-206 |
| T09 | all_layers 必填 | model_service | R19 | K-305 |
| T10 | NumericPolicy | model_utils/model_service/components | R12 | K-306 |
| T11 | schema + TS/Julia codegen | component library/types/core schema | R21/R23 | K-301～K-303 |
| T12 | 统一 schema migration | task/planning/boundary DB | R14 | K-106 |
| T13 | 全量代码/trace 分层存储 | task workdir/trace API | R20 | K-402/K-504 |
| T14 | 旧 simulation 链路先清点、隔离，再评审退役 | simulation/result pages/state/410 route | R25 | K-308 |
| T15 | 算法配置专用 DTO | api types/useProjectApi/PUT route | R28 | K-304 |
| T16 | UI token/status/chart theme | CSS/theme/pages/charts | R27 | K-307 |
| T17 | 超大页面拆分技术方案与评审；确认前不实施 | capacity/tasks/boundary/editor | R18 | C-301/K-404/K-405 |
| T18 | 容量经济指标完整化 | capacity economic evaluator/UI | R03 | C-001/C-403/C-404/C-405 |
| T19 | 特殊物理校验矩阵 | components/validation/topology | R09 | K-401 + 各线 |
| T20 | 四业务线黄金模板 | config/project-templates/tests | R22 | K-406；C-501/F-501/O-501 |
| T21 | 统一 Toast `danger` 契约并补失败路径测试 | state/ui、AppToastHost、project/boundary pages | R29 | K-307 |
| T22 | 收口个人中心权限占位 | profile page/产品说明 | R30 | K-308 |
| T23 | 核验后移除容量旧 `financialParameters` 兼容分支 | capacity-planning page/schema/fixtures | R31 | K-304，武玉琨协作 |
| T24 | 淘汰重复边界组件映射 | boundary types/component schema | R32 | K-301/K-304 |

## 4. 已识别的废弃/语义漂移

- `state/simulation.ts` 和 `types/simulation.ts` 的旧 SimulationStatus；
- `app/pages/simulation/[projectId].vue`、`result/[projectId].vue` 旧导出流程；
- `server/api/.../simulation-parse.post.ts` 410 路由；
- editor 中注释掉的 SimulationParseModal 和旧 action key；
- 已停止被边界页采用、但仍实际导出的 `BOUNDARY_COMPONENT_MAPPINGS`；
- 未检出消费的 `config/theme-config.ts`；
- 设置页 `/ws/simulation` 旧默认路径；
- UpdateAlgorithmConfigRequest 与实际 body 不同；
- 边界类型缺 heat/hydrogen；
- 页面内重复 status/device/cost/palette 常量。
- Toast 公共枚举使用 `danger`，但项目/边界页仍使用 `error`；
- profile 页关于角色/项目权限的占位超出当前业务范围；
- 容量页仍通过 `unknown` 读取旧 `financialParameters`；
- `BOUNDARY_COMPONENT_MAPPINGS` 已停用但仍实际导出。

详细证据见 `../03-代码风险审查与回复/05-前端历史遗留与UI一致性专项审查.md`。清理前必须用 `rg` 检索源码、测试、模板和数据。删除旧链路时同步修导航、类型、API、文档和测试。

## 5. ADR 建议

重大设计不要只留在聊天或注释，建议新增 `docs/adr/`：

1. ADR-001：项目与多画布计算隔离；
2. ADR-002：SQLite 边界单一真值；
3. ADR-003：supervisor/worker 多进程计算；
4. ADR-004：离线与在线状态机分离；
5. ADR-005：Component Schema 和代码生成；
6. ADR-006：历史代码/trace 全量保留与分层存储；
7. ADR-007：单位、数值尺度和求解器适配层。

每份 ADR 记录背景、选择、被否决方案、影响、迁移步骤和验证方式。

## 6. 文档维护触发器

出现以下变化必须更新本开发文档：

- 新增/删除 API、状态或持久化字段；
- Component Schema 或单位变化；
- 任务目录/数据库结构变化；
- worker 协议或并发策略变化；
- 四业务线交叉接口变化；
- UI token、页面路由或公共组件规范变化；
- 风险被接受、关闭或重新打开。

代码合并检查表应要求：关联 TODO/风险/计划 ID、更新调用链、补测试条件、说明是否影响历史数据与四业务线。
