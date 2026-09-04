# 从 model-base.jl 生成 model.jl 的 AI 提示词模板

## 使用场景

当你为一个新类型组件（如燃料电池 FC）编写并调试好 `model-base.jl` 后，
使用以下提示词让 AI 自动生成对应的 `model.jl`（元编程追踪版本）。

---

## 提示词模板

```
请根据 backend/components/{组件目录}/model-base.jl 生成对应的 model.jl（元编程追踪版本）。

## 背景

本项目使用两套模型构建系统：
- model-base.jl：数学原理蓝图，变量名无后缀（如 E_WT, E_CP），用于单实例场景的数学验证
- model.jl：元编程追踪版本，变量名带后缀（如 E_WT_14a1），支持同类型多组件，同时记录构建过程代码

## 你需要做的

1. 读取 model-base.jl，理解其数学逻辑
2. 参考以下已有组件的 model.jl 实现模式：
   - backend/components/wind_turbine/model.jl（简单示例）
   - backend/components/coal_power/model.jl（复杂示例，含开停机约束）
   - backend/components/electricity_storage/model.jl（含多状态模式）
3. 生成新的 model.jl

## 转换规则

### 函数签名
- model-base.jl: `build_component_model!(model, component::T, ctx::BuildContext)`
- model.jl:      `build_component_model!(model, component::T, ctx::BuildContext, tracer::CodeTracer)`
- 状态分发函数同理，增加 `code::String, tracer::CodeTracer` 参数

### 变量创建
- model-base.jl: `@variable(model, E_WT[t in time_index], lower_bound=0.0, upper_bound=available_power[t])`
- model.jl:      `E_WT = add_tracked_variable!(model, tracer, "E_WT_$(code)", time_index; lower_bound=0.0, upper_bound=available_power)`

注意：
  - add_tracked_variable! 的 upper_bound 参数接受数组（会逐元素使用）
  - 返回值是 JuMP DenseAxisArray，后续约束中直接使用
  - binary 变量使用 `binary=true` 关键字参数

### 约束创建
- model-base.jl: `@constraint(model, [t in time_index], E_WT[t] + E_WT_cut[t] == available_power[t])`
- model.jl:
  ```julia
  add_tracked_linear_constraint!(model, tracer,
      "@constraint(model, [t in $(format_val(time_index))], E_WT_$(code)[t] + E_WT_cut_$(code)[t] == $(format_val(available_power))[t])",
      () -> @constraint(model, [t in time_index], E_WT[t] + E_WT_cut[t] == available_power[t])
  )
  ```

注意：
  - 第一个参数是代码追踪字符串，所有参数内联为硬值（用 format_val()）
  - 第二个参数是实际执行约束创建的闭包，使用局部变量（E_WT, available_power 等）
  - 代码字符串中的变量名带后缀（E_WT_14a1），闭包中用局部变量（E_WT）

### 表达式创建
- model-base.jl: `objective_expr += @expression(model, C_wt_om, sum(E_WT) * params.om_cost)`
- model.jl:
  ```julia
  om_expr = sum(E_WT) * params.om_cost
  add_tracked_expression!(model, tracer, "C_wt_om_$(code)",
      "@expression(model, C_wt_om_$(code), sum(E_WT_$(code)) * $(format_val(params.om_cost)))",
      om_expr)
  objective_expr += om_expr
  ```

### 目标函数
- model-base.jl: 不需要处理（由 build_model 统一设置）
- model.jl: 同样不需要处理（由 build_model_tracked 统一设置）

### 内部辅助变量（如 cp_state, cp_start, cp_stop 等）
- 所有 @variable 创建的内部变量也需要加后缀
- 使用 add_tracked_variable! 创建
- 约束中使用局部变量引用

### 辅助函数
- 将 model-base.jl 中的 `define_xxx!` 函数改名为 `define_xxx_tracked!`
- 增加 `code::String` 参数
- 内部变量名加后缀，约束使用 add_tracked_linear_constraint!

### model-base.jl 不要修改
- model-base.jl 是数学原理蓝图，保持原样
- model.jl 是新文件，与 model-base.jl 并存

## 输出格式

输出完整的 model.jl 文件内容，包含：
- 文件头注释（说明是元编程架构版本）
- 所有 build_component_model! 和状态分发函数
- 所有辅助函数（tracked 版本）
- 使用 CodeTracer（来自 backend/utils/model_builder_utils.jl）

## 已有的 model-builder-utils.jl 提供的工具

```julia
# 代码追踪器
tracer = CodeTracer()
record!(tracer, "code line")
get_code(tracer)  # 返回所有代码行的拼接字符串

# 动态变量创建（创建 + 记录代码行）
var = add_tracked_variable!(model, tracer, "E_WT_14a1", 1:24; lower_bound=0.0, upper_bound=100.0)

# 约束创建（记录代码行 + 执行闭包）
add_tracked_linear_constraint!(model, tracer, "code_line_string", () -> @constraint(...))

# 表达式创建
add_tracked_expression!(model, tracer, "name", "code_line", expr)

# 值格式化
format_val(150000.0)  → "150000.0"
format_val(1:24)      → "1:24"
format_val([1,2,3])   → "[1, 2, 3]"
```
```

---

## 快速使用

将上面的提示词复制后，替换 `{组件目录}` 为实际目录名（如 `fuel_cell`），
然后发送给 AI 即可。AI 会读取 model-base.jl 并生成 model.jl。
