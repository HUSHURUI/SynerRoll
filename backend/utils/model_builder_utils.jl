# ═══════════════════════════════════════════════════════════════════════════
# model_builder_utils.jl
# 元编程工具：动态变量名创建 + 代码追踪
#
# 核心思路：
#   - 使用 JuMP 直接 API（add_variable / add_constraint）创建带后缀的变量/约束
#   - 同时生成可读的 @variable / @constraint 代码字符串（参数内联为硬值）
#   - 代码字符串可在顶层 scope 通过 eval(Meta.parse(...)) 执行
# ═══════════════════════════════════════════════════════════════════════════

using JuMP

"""
    CodeTracer

模型构建过程追踪器。记录每一步 @variable / @constraint / @expression / @objective 调用的代码文本。
所有参数内联为硬值，输出为可直接执行的 Julia 代码。
"""
mutable struct CodeTracer
    lines::Vector{String}
    objective_expr_names::Vector{String}   # 属于目标函数的命名表达式
end
CodeTracer() = CodeTracer(String[], String[])

record!(tracer::CodeTracer, line::String) = push!(tracer.lines, line)
get_code(tracer::CodeTracer) = join(tracer.lines, "\n")

"""注册一个属于目标函数的命名表达式（如 C_wt_cut_14a1）"""
register_objective_expr!(tracer::CodeTracer, name::String) = push!(tracer.objective_expr_names, name)

# ─── 值格式化 ──────────────────────────────────────────────────────────

"""将值格式化为可嵌入代码字符串的字面量"""
format_val(x::Float64) = string(x)
format_val(x::Int) = string(x)
format_val(x::Bool) = string(x)
format_val(x::String) = "\"$(x)\""
format_val(x::UnitRange{Int}) = "$(first(x)):$(last(x))"
format_val(x::StepRangeLen) = "$(first(x)):$(step(x)):$(last(x))"
format_val(x::AbstractVector) = "[$(join(format_val.(x), ", "))]"
format_val(x::Tuple) = "($(join(format_val.(x), ", ")))"
format_val(x::Nothing) = "nothing"

# ─── 动态变量创建 ─────────────────────────────────────────────────────

"""
    add_tracked_variable!(model, tracer, base_name, time_index; lower_bound, upper_bound, binary)

在 model 中创建 JuMP 变量 `base_name[t in time_index]`，同时记录代码行。

返回值：`model[Symbol(base_name)]`（JuMP DenseAxisArray）

示例：
```julia
E_WT = add_tracked_variable!(model, tracer, "E_WT_14a1", 1:24; lower_bound=0.0, upper_bound=100.0)
# model 中注册了 :E_WT_14a1 变量
# tracer 记录了: @variable(model, E_WT_14a1[1:24], lower_bound = 0.0, upper_bound = 100.0)
```
"""
function add_tracked_variable!(model, tracer::CodeTracer, base_name::String, time_index;
                                lower_bound=nothing, upper_bound=nothing, binary=false)
    idx_str = format_val(time_index)
    bin_str = binary ? ", Bin" : ""

    # 向量 bound 用 [t] 索引，标量 bound 用原值——统一 @variable 语法
    kw_parts = String[]
    if lower_bound !== nothing
        lb_str = lower_bound isa AbstractVector ? "$(format_val(lower_bound))[t]" : format_val(lower_bound)
        push!(kw_parts, "lower_bound = $(lb_str)")
    end
    if upper_bound !== nothing
        ub_str = upper_bound isa AbstractVector ? "$(format_val(upper_bound))[t]" : format_val(upper_bound)
        push!(kw_parts, "upper_bound = $(ub_str)")
    end

    if isempty(kw_parts)
        code_line = "@variable(model, $(base_name)[$(idx_str)]$(bin_str))"
    else
        code_line = "@variable(model, $(base_name)[t in $(idx_str)], $(join(kw_parts, ", "))$(bin_str))"
    end
    record!(tracer, code_line)

    # 实际创建：使用 JuMP 直接 API
    sym = Symbol(base_name)
    n = length(time_index)
    vars = Vector{VariableRef}(undef, n)
    for (i, t) in enumerate(time_index)
        lb = (lower_bound !== nothing) ? (lower_bound isa AbstractVector ? lower_bound[i] : lower_bound) : 0.0
        ub = (upper_bound !== nothing) ? (upper_bound isa AbstractVector ? upper_bound[i] : upper_bound) : 0.0
        info = JuMP.ScalarVariable(
            JuMP.VariableInfo(
                lower_bound !== nothing, lb,
                upper_bound !== nothing, ub,
                false, 0.0,             # has_fix, fix
                false, 0.0,             # has_start, start
                binary, false,          # binary, integer
            )
        )
        vars[i] = JuMP.add_variable(model, info, base_name * "[$t]")
    end

    # 注册为 DenseAxisArray
    ax = time_index isa UnitRange || time_index isa StepRangeLen ? (time_index,) : (collect(time_index),)
    da = JuMP.Containers.DenseAxisArray(vars, ax...)
    model[sym] = da
    return da
end

# ─── 动态约束创建 ─────────────────────────────────────────────────────

"""
    add_tracked_constraint!(model, tracer, name, time_index, lhs_expr, sense, rhs_val)

在 model 中创建约束 `lhs_expr sense rhs_val [for t in time_index]`，同时记录代码行。

sense: `MOI.EqualTo(0.0)`, `MOI.LessThan(capacity)`, etc.
"""
function add_tracked_constraint!(model, tracer::CodeTracer, name::String, time_index,
                                  lhs_builder::Function, sense::MOI.AbstractSet, sense_str::String)
    # 代码行
    record!(tracer, "@constraint(model, [t in $(format_val(time_index))], $(sense_str))")

    # 实际创建
    for t in time_index
        cref = JuMP.build_constraint(error, lhs_builder(t), sense)
        JuMP.add_constraint(model, cref, "$(name)_$(t)")
    end
end

"""
    add_tracked_linear_constraint!(model, tracer, code_line, constraint_builder)

通用约束：记录 code_line，然后用 constraint_builder() 执行实际创建。
constraint_builder 应该返回 nothing（已直接操作 model）。
"""
function add_tracked_linear_constraint!(model, tracer::CodeTracer, code_line::String, constraint_builder::Function)
    record!(tracer, code_line)
    constraint_builder()
    return nothing
end

# ─── 动态表达式创建 ───────────────────────────────────────────────────

"""
    add_tracked_expression!(model, tracer, name, expr_builder)

在 model 中创建命名表达式 `model[:name] = expr_builder()`，同时记录代码行。
`to_objective=true` 时将 name 注册到目标函数表达式列表。
"""
function add_tracked_expression!(model, tracer::CodeTracer, name::String, code_line::String, expr;
    to_objective::Bool=false)
    record!(tracer, code_line)
    model[Symbol(name)] = expr
    to_objective && register_objective_expr!(tracer, name)
    return expr
end

# ─── 目标函数 ─────────────────────────────────────────────────────────

"""
    set_tracked_objective!(model, tracer, sense, code_line, objective_expr)

设置目标函数，同时记录代码行。
"""
function set_tracked_objective!(model, tracer::CodeTracer, sense, code_line::String, objective_expr)
    record!(tracer, code_line)
    JuMP.set_objective(model, sense, objective_expr)
    return nothing
end
