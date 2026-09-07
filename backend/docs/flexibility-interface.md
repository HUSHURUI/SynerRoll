# 组件灵活性统一接口

本文档定义灵活性模块设备层的首版公共接口。计算口径来自《灵活性说明文档》第 1.2、2.1、2.2 和 2.7 节。

## 1. 当前范围

当前阶段包含统一接口、公共数据类型、现有组件的单体快速计算公式、首版系统供给聚合、系统需求计算、逐时段裕度/充足性计算、全时域裕度汇总，以及任务编排、结果持久化、查询与 WebSocket 推送。系统供给采用“内部设备灵活性求和 + POI 剩余交换空间截断”，不进行系统全约束双向重优化。

组件灵活性表示设备在当前状态下、一个模型时段 `Δt` 内能够提供的有功功率调节量。`Δt` 直接采用模型的 `time_step`，不设置独立响应时间参数。

## 2. 统一方向与单位

- `up`：增加系统净注入。发电设备增加出力、储能增加放电或减少充电、柔性负荷降低用电均属于系统上调。
- `down`：减少系统净注入。发电设备降低出力、储能增加充电或减少放电、柔性负荷增加用电均属于系统下调。
- `device_flexibility`：非负有限数值，单位统一为 `kW`。
- `time_step`：模型时段长度，例如 `1h`、`15m`、`5m`。
- `binding_constraint`：限制该方向灵活性的主要约束；没有可报告约束时可以为 `nothing`。
- `baseline_poi_power`、`poi_power_limit`：仅用于 `GRID`，分别记录基准并网功率和当前方向对应的接口限值，单位为 `kW`；其他组件为 `nothing`。

刚性负荷仍需通过统一接口返回 `up=0` 和 `down=0`，不能因为数值为零而省略结果。电网接口属于系统边界，其结果不得默认加入内部资源灵活性之和。

## 3. 输入上下文

`ComponentFlexibilityContext` 统一携带：

- `timestamp`
- `time_step`
- `case_id`
- `application_type`
- `operation_mode`
- `boundary_condition`
- `poi_id`
- `operating_point`

`operating_point` 保存当前时段的基准调度出力、状态量和组件公式所需的其他基准值。键名和单位约定如下：

| 适用组件 | 必需字段 | 可选覆盖字段 |
|---|---|---|
| CP、GP、CHP | `power_kw`, `is_online` | `available`, `minimum_power_kw`, `maximum_power_kw`, `ramp_up_kw_per_hour`, `ramp_down_kw_per_hour`, `startup_allowed`, `startup_time_hours` |
| WT、PV | `power_kw`, `available_power_kw` | `available`, `minimum_power_kw`, `ramp_constraint_on`, `ramp_up_kw_per_hour`, `ramp_down_kw_per_hour` |
| ES、FS、CS、PS | `stored_energy_kwh`, `charging_power_kw`, `discharging_power_kw` | `available`, `minimum_energy_kwh`, `maximum_energy_kwh`, `maximum_charge_power_kw`, `maximum_discharge_power_kw`, `ramp_up_kw_per_hour`, `ramp_down_kw_per_hour` |
| ET | `power_kw`, `is_online` | `available`, `minimum_power_kw`, `maximum_power_kw`, `ramp_up_kw_per_hour`, `ramp_down_kw_per_hour`, `startup_allowed`, `startup_time_hours` |
| GRID | `poi_power_kw` | `available`, `maximum_poi_power_kw`, `minimum_poi_power_kw` |
| HYDRO | `power_kw`、`available_power_kw`、`minimum_power_kw` | `available`、`ramp_constraint_on`、`ramp_up_kw_per_hour`、`ramp_down_kw_per_hour` |
| ELOAD、HS、HLOAD、QLOAD | 无 | 无 |

`available=false` 表示设备当前不可提供灵活性。CHP 在供热工况下应通过 `minimum_power_kw` 和 `maximum_power_kw` 传入当前时段的实际电出力边界。储能的 `charging_power_kw`、`discharging_power_kw` 均为非负数，且不能同时大于零；净有功功率按“放电减充电”计算。

WT、PV 只有在 `ramp_constraint_on=true` 时才应用主动有功变化率；关闭时只按可用功率和最小出力空间计算。基准结果适配层从当前时层的同名约束开关写入该字段，保证基准模型与快速计算使用同一配置。

使用 `time_step_hours(context)` 可将 `time_step` 转换为以小时为单位的 `Δt`。

### 3.1 基准结果适配层

`services/flexibility_baseline_adapter.jl` 负责把现有优化调度结果转换成上述
`operating_point`。它复用组件的 `ResultBinding` 和现有 SQLite 时序标签，不建立
第二套结果命名规则。

主要入口如下：

```julia
context = load_component_flexibility_context(
    component,
    db_path;
    layer=layer,
    timestamp="1:00",
    case_id="case-1",
    application_type="large_renewable_base",
    operation_mode="economic_dispatch",
    boundary_condition="grid_connected",
    poi_id="poi-1",
)

results = calculate_component_flexibility(component, context)
```

若调用方已经持有内存中的求解变量，可以分别调用：

- `adapt_component_baseline_result`：原始求解变量 → `operating_point`；
- `build_component_flexibility_context`：原始求解变量 → 完整上下文；
- `read_component_baseline_result`：SQLite 结果时序 → 原始求解变量。

当前映射规则为：

| 组件 | 求解结果 | `operating_point` |
|---|---|---|
| CP、GP、CHP | `E_*` | `power_kw`；按功率是否大于数值容差推断 `is_online` |
| WT | `E_WT`、`E_WT_cut`、`AVAILABLE_WT` | `power_kw`、`available_power_kw`、`ramp_constraint_on`；旧结果缺少 `AVAILABLE_WT` 时采用出力加弃风量 |
| PV | `E_PV`、`E_PV_cut` | `power_kw`、`available_power_kw`、`ramp_constraint_on`；可用功率采用出力加弃光量 |
| ES、FS、CS、PS | `E_*`、`E_*_in`、`E_*_out` | `stored_energy_kwh`、`charging_power_kw`、`discharging_power_kw` |
| ET | `E_ET` | `power_kw`；按功率是否大于数值容差推断 `is_online` |
| GRID | `E_GRID_in`、`E_GRID_out` | `poi_power_kw`，按“上送 − 购入”合成，正值表示向电网上送 |
| HYDRO | `E_HYDRO`、`AVAILABLE_HYDRO`、`MINIMUM_HYDRO` | `power_kw`、`available_power_kw`、`minimum_power_kw`；爬坡开关从当前时层配置读取 |
| ELOAD、HS、HLOAD、QLOAD | 无需读取 | 设备层电功率灵活性为零 |

组件在当前层的状态为 `disabled` 时，适配结果自动写入 `available=false`。
停用组件不要求结果库中存在占位变量。
求解器产生的绝对值不超过 `numerical_tolerance_kw` 的微小负数或残差会清零。
时序中没有精确时间戳时，沿用平台 `get_value` 的规则，读取最近的更早值。

当前结果库没有持久化 CP、GP、CHP 和 ET 的启停二进制变量，所以仅靠结果无法
区分“零出力但已在线”和“已停机”。涉及启停灵活性时，应通过
`operating_point_overrides` 显式传入 `is_online`、`startup_allowed` 和
`startup_time_hours`。CHP 的分时电出力边界也通过同一覆盖参数传入。

## 4. 输出结果

每个组件、每个时段必须返回两条 `ComponentFlexibilityResult`：一条 `up`，一条 `down`。接口会统一校验：

- 两个方向是否齐全且没有重复；
- 设备ID、设备类型和上下文元数据是否一致；
- 灵活性数值是否非负且有限；
- 返回值是否为统一结果类型。

使用 `component_flexibility_result_dict(result)` 可转换为与说明文档逐时段输出字段一致的字典。

### 4.1 系统供给聚合

使用 `aggregate_system_flexibility_supply(results)`，可以把单设备结果按时间、
算例、应用类型、运行模式、网络边界、POI 和方向聚合，并在同一次计算中完成
POI 截断和设备贡献分配。

```julia
supplies = aggregate_system_flexibility_supply(device_results)
rows = system_flexibility_supply_result_dict.(supplies)
```

聚合结果使用 `SystemFlexibilitySupplyResult`，其中：

- `internal_flexibility_sum`：系统内部设备灵活性的简单合计；
- `baseline_poi_power`：原运行目标下得到的基准并网功率；
- `poi_power_limit`：当前方向对应的 POI 功率上限或下限；
- `poi_remaining_space`：并网时为 `GRID` 在当前方向的 POI 剩余交换空间，离网时为 `nothing`；
- `system_supply`：并网时为内部合计与 POI 空间的较小值，离网时为内部合计；
- `device_contributions`：按设备可用灵活性比例分配的可归属贡献；
- `boundary_result`：并网时为用于本次截断的唯一 `GRID` 边界结果，离网时为 `nothing`；
- `binding_constraint`：`internal_devices`、`poi_upper_limit` 或 `poi_lower_limit`。

输入中每台设备在同一分组下必须同时具有 `up` 和 `down` 结果。并网聚合要求
每个分组恰好有一个 `GRID` 边界结果；离网聚合则禁止包含 GRID。重复结果或
方向缺失会直接报错。空输入返回空结果。

`GRID` 不加入内部设备求和。设备贡献之和等于 `system_supply`；当 POI 截断
内部设备合计时，默认按各设备 `device_flexibility` 的比例分配。该贡献是首版
统计口径，不是新的调度指令，也不是全约束优化得到的唯一物理方案。

画布没有 `GRID` 时采用 `aggregate_islanded_system_flexibility_supply(results)`。
离网结果的 `poi_id`、`poi_remaining_space`、`baseline_poi_power`、
`poi_power_limit` 和 `boundary_result` 均为 `nothing`，`system_supply` 等于内部
设备灵活性合计，`binding_constraint` 为 `internal_devices`。该口径表示内部资源
对本地净负荷变化或用户给定调节需求的可用能力，不允许使用 POI 计划/AGC目标。

### 4.2 系统需求计算

使用 `SystemFlexibilityRequirementContext` 描述从 `timestamp` 到
`next_timestamp` 的相邻时段区间。调用方根据说明文档 §2.4.3 的运行模式和
边界规则，显式选择一种需求输入：

- `NetLoadRequirementInput`：刚性负荷合计、柔性负荷实际功率合计、风电最大
  可用功率合计和光伏最大可用功率合计在相邻时段的取值；
- `AgcScheduleRequirementInput`：下一时段的基准 POI 功率和 AGC/计划目标功率；
- `UserDefinedRequirementInput`：用户直接给定的非负上、下调需求。

统一入口如下：

```julia
context = SystemFlexibilityRequirementContext(
    timestamp="0:00",
    next_timestamp="0:15",
    time_step="15m",
    case_id="case-1",
    application_type="large_renewable_base",
    operation_mode="renewable_smoothing",
    boundary_condition="grid_connected",
    poi_id="poi-1",
)

input = NetLoadRequirementInput(
    current_rigid_load_kw=100000.0,
    next_rigid_load_kw=110000.0,
    current_wind_available_power_kw=30000.0,
    next_wind_available_power_kw=25000.0,
)

requirements = calculate_system_flexibility_requirement(context, input)
rows = system_flexibility_requirement_result_dict.(requirements)
```

每次调用只接受一个输入对象并返回 `up`、`down` 两条
`SystemFlexibilityRequirementResult`，因此不会把净负荷变化和 AGC 需求自动
相加。经济运行、新能源消纳和灵活性增强等存在多种合理口径的模式，也必须由
上层业务显式选择输入类型，不在服务内部猜测。

净负荷计算只使用风光最大可用功率，不接收主动限发后的风光实际出力；AGC
计算中的基准和目标均对应 `next_timestamp`。`requirement_source` 分别输出
`net_load_change`、`agc_or_schedule` 或 `user_defined`。

### 4.3 系统裕度与充足性计算

使用 `calculate_system_flexibility_margin(supplies, requirements)` 将系统供给和
系统需求按时段、算例、应用类型、运行模式、网络边界、POI 与方向一一配对：

```julia
margins = calculate_system_flexibility_margin(supplies, requirements)
rows = system_flexibility_margin_result_dict.(margins)
```

结果使用 `SystemFlexibilityMarginResult`，其中：

- `margin = system_supply - requirement`；
- `deficit = max(0, -margin)`；
- 需求大于零时，`adequacy_ratio = system_supply / requirement`；需求为零时为
  `nothing`；
- `is_adequate` 表示该方向的裕度是否非负。

每个分组必须同时包含 `up`、`down` 两个方向，供给和需求的分组必须完全一致；
同一双向需求还必须使用相同的 `next_timestamp` 和 `requirement_source`。重复、
缺失或元数据错配都会报错。序列化结果在保留供给侧设备贡献和 POI 截断信息的
同时，追加需求、裕度、缺额和充足率字段。

供给和裕度结果按 `time_label_to_minutes(timestamp)` 的数值时间顺序输出，不直接
使用时间字符串字典序，因此 `"9:00"` 会正确排在 `"10:00"` 之前。

### 4.4 全时域裕度汇总

使用 `summarize_system_flexibility_margin(margins)` 对连续的逐时段裕度进行汇总：

```julia
summaries = summarize_system_flexibility_margin(margins)
rows = system_flexibility_margin_summary_result_dict.(summaries)
```

汇总按 `time_step`、`case_id`、`application_type`、`operation_mode`、
`boundary_condition`、`poi_id` 和 `requirement_source` 分组，每组返回 `up`、
`down` 两条 `SystemFlexibilityMarginSummaryResult`。主要指标为：

- `minimum_margin`：该方向全时域最小裕度，并记录
  `minimum_margin_timestamp`；
- `maximum_deficit`：该方向全时域最大缺额；没有发生缺额时
  `maximum_deficit_timestamp` 为 `nothing`；
- `deficit_energy`：`sum(deficit × time_step_hours)`，单位为 kWh；
- `adequate_period_ratio`：该方向裕度非负的时段数除以总时段数；
- `bidirectional_adequate_period_ratio`：上、下调裕度同时非负的时段数除以总
  时段数；该值在同一分组的两条方向汇总中一致。

汇总前会校验每个时段的上、下方向齐全、区间长度等于 `time_step`，并要求相邻
区间连续。出现重复时段、缺方向、时间间隔错误或中间缺口时直接报错，避免把
不完整数据当成完整时域计算达标比例。

### 4.5 任务配置与总编排

创建计算任务时，可在请求体中增加顶层 `flexibility`。缺少该字段或设置
`enabled=false` 时，不执行灵活性计算。

```json
{
  "projectId": "project-1",
  "canvasId": "canvas-1",
  "layerId": "2",
  "mode": "offline",
  "simStartTime": "0:00",
  "simEndTime": "24:00",
  "flexibility": {
    "enabled": true,
    "layerId": "2",
    "operationMode": "flexibility_enhancement",
    "networkMode": "grid_connected",
    "poiId": "grid-1",
    "requirementSource": "net_load_change"
  }
}
```

公共字段为：

- `layerId`：执行灵活性评价的时层；省略时使用任务的 `layerId`；
- `operationMode`：写入所有逐时段和汇总结果的运行口径；
- `networkMode`：`grid_connected` 或 `islanded`；旧任务省略时根据是否存在 GRID 自动判断；
- 系统应用分类已移至新建项目推荐模板，不在计算任务中重复选择；
- 网络边界直接采用所选 `GRID` 的接口容量、上送比例和购入比例，不再单独提交正常并网/弱联网标签；
- `poiId`：单 GRID 时可省略，默认使用 GRID 组件 code；多 GRID 时必须指定并匹配唯一 GRID code；
- `requirementSource`：必须显式选择 `net_load_change`、`agc_or_schedule` 或 `user_defined`，三种需求不自动叠加。

`networkMode=islanded` 要求画布不包含 GRID，`poiId` 必须为 `null`，需求来源仅
允许 `net_load_change` 或 `user_defined`。并网模式要求至少一个 GRID。

不同需求源的附加字段为：

| `requirementSource` | 附加字段 | 取值规则 |
|---|---|---|
| `net_load_change` | 无 | 从 ELOAD、ET、WT、PV 的当前与下一时段求解结果自动派生 |
| `agc_or_schedule` | `targetPoiPowerKw` | 常数，或 `{ "时间戳": 数值, "default": 数值 }`；按 `next_timestamp` 取值 |
| `user_defined` | `upwardRequirementKw`、`downwardRequirementKw` | 非负常数，或时间戳对象；按 `timestamp` 取值 |

前端支持全时域常数、分时表格、CSV/Excel/JSON 文件和项目边界数据库四种数据
来源。文件与数据库数据在提交任务前统一转换为上述时间戳对象，并校验时间标签、
重复项、有限数值和非负要求；后端接口不直接接收文件路径或工作簿二进制。

`flexibility_evaluation_service.jl` 的 `evaluate_system_flexibility` 是总编排入口，
按“基准结果适配 → 组件能力 → 系统供给 → 系统需求 → 裕度”顺序执行。生产任务由
`simulation_runner.jl` 在目标时层每次求解落库后调用该入口。滚动层评价当前
`forward` 窗口，第一层评价一个 `length`；超过 `simEndTime` 的区间不计算。

总编排读取求解结果时要求精确时间戳存在，不使用平台通用的“向前找最近值”
回退规则，避免用旧调度点冒充当前灵活性基准。

### 4.6 持久化、查询和推送

任务级 `timeseries.db` 追加两张表：

- `flexibility_period_results`：逐时段、逐方向保存完整裕度 JSON，并以数值分钟列排序；
- `flexibility_summary_results`：任务完成后保存全时域汇总 JSON。

逐时段写入使用业务主键执行 upsert，重复执行同一窗口不会产生重复行。任务完成
时重新生成目标时层的汇总结果。查询入口为：

```text
GET /api/task/{taskId}/flexibility?layerId=2
```

返回结构：

```json
{
  "config": { "enabled": true },
  "periods": [],
  "summaries": []
}
```

运行中每完成一个评价窗口，通过任务 WebSocket 推送：

```json
{
  "type": "flexibility",
  "taskId": "...",
  "layerId": "2",
  "startTimestamp": "0:00",
  "endTimestamp": "1:00",
  "rows": []
}
```

任务结束并形成全时域指标后推送：

```json
{
  "type": "flexibility_summary",
  "taskId": "...",
  "layerId": "2",
  "rows": []
}
```

## 5. 组件扩展点

各组件只实现内部扩展方法：

```julia
function calculate_component_flexibility_impl(
    component::ConcreteComponent,
    context::ComponentFlexibilityContext,
)
    return [
        ComponentFlexibilityResult(
            context,
            component;
            direction=FLEXIBILITY_UP,
            device_flexibility=upward_value,
            binding_constraint=upward_constraint,
        ),
        ComponentFlexibilityResult(
            context,
            component;
            direction=FLEXIBILITY_DOWN,
            device_flexibility=downward_value,
            binding_constraint=downward_constraint,
        ),
    ]
end
```

业务代码统一调用：

```julia
results = calculate_component_flexibility(component, context)
```

不得绕过公共入口直接调用实现方法，否则公共校验不会执行。

## 6. 当前组件映射

- CP、GP、CHP：通用可控发电机公式；离线设备只有在允许启动且启动时间不超过 `time_step` 时才计入上调。
- WT、PV：`ramp_constraint_on=true` 时取可用功率空间与主动变化率限制的较小值；关闭时只取功率空间。
- ES、FS、CS：电化学储能公式；飞轮和压缩空气储能复用相同的等效能量接口。
- PS：抽水蓄能等效能量公式，发电为正、抽水为负。
- ET：柔性负荷公式，减负荷是系统上调，增负荷是系统下调。
- GRID：电网接口边界公式（说明文档 §2.2.8），只取基准并网点功率到接口功率上下限的剩余空间，不含联络线变化率；结果是系统边界，不得默认加入内部资源灵活性之和。
- HYDRO：常规水电首版按可调发电单元计算；上调受可用功率与爬坡限制，下调受最小技术出力与爬坡限制。常规水电的 `ramp_constraint_on` 默认开启，显式关闭时只按分时出力边界计算。来流—库容—水头—弃水耦合属于后续精细模型扩展。
- ELOAD：刚性电负荷，上、下调均为零。
- HS、HLOAD、QLOAD：不直接与电母线交换有功功率，设备层电功率灵活性为零；其耦合影响留给系统全约束优化计算。
