using JSON3
using CSV
using DataFrames
using HTTP

# backend/data 绝对路径（不依赖 CWD）
# 所有 project / task / boundary DB 都建在这里
const BACKEND_DATA_DIR = joinpath(@__DIR__, "..", "data")

# ─────────────────────────────────────────────────────────────────────────────
# 请求参数解析
# ─────────────────────────────────────────────────────────────────────────────

"""从 HTTP 请求中解析查询参数"""
request_query_params(req) = HTTP.queryparams(HTTP.URI(String(req.target)))

# ─────────────────────────────────────────────────────────────────────────────
# JSON 响应辅助
# ─────────────────────────────────────────────────────────────────────────────

"""
    json_success(; kwargs...) -> String

成功响应 JSON：顶层带 `success=true`，把 kwargs 平铺到顶层。
例：`json_success(data=Dict("x"=>1), message="ok")`
     => `{"success":true,"data":{"x":1},"message":"ok"}`
"""
json_success(; kwargs...) = JSON3.write(Dict(:success => true, kwargs...))

"""
    json_error(message::AbstractString) -> String

错误响应 JSON：顶层带 `success=false` 和 `message`。
"""
json_error(message::AbstractString) = JSON3.write(Dict("success" => false, "message" => message))

# ─────────────────────────────────────────────────────────────────────────────
# 请求参数辅助
# ─────────────────────────────────────────────────────────────────────────────

"""
    require_string(body::Dict, field::AbstractString) -> String

从 body 取必填字符串字段。缺失 key / null / 空串 都抛 ErrorException，
由路由外层 catch 转成 json_error。
"""
function require_string(body::Dict, field::AbstractString)
    haskey(body, field) || error("缺少 $(field) 参数")
    value = body[field]
    value === nothing && error("缺少 $(field) 参数")
    s = string(value)
    isempty(s) && error("缺少 $(field) 参数")
    return s
end

"""
    optional_string(body::Dict, field::AbstractString, default::AbstractString) -> String

从 body 取可选字符串字段，缺失/空串/null 时返回 default。
"""
function optional_string(body::Dict, field::AbstractString, default::AbstractString)
    value = get(body, field, nothing)
    value === nothing && return default
    s = string(value)
    isempty(s) && return default
    return s
end

# ─────────────────────────────────────────────────────────────────────────────
# CSV 辅助（边界导入/转换共用）
# ─────────────────────────────────────────────────────────────────────────────

"""
    read_csv_column(file_path::String, column_name::String)
        -> (col_data, resolved_col_name)

读取 CSV（header=1），按 `column_name` 定位列；找不到时报错并附可用列名。
文件不存在 / CSV 解析失败 / 列找不到 均抛 ErrorException。

返回：
- `col_data`    该列的原始数据（Vector{Any} 之类的 DataFrame 列切片）
- `resolved_col_name` 实际命中的列名字符串
"""
function read_csv_column(file_path::String, column_name::String)
    isfile(file_path) || error("文件不存在: $(file_path)")
    df = CSV.read(file_path, DataFrame; header=1)
    headers = String.(names(df))
    resolved = nothing
    for h in headers
        if string(h) == column_name
            resolved = string(h)
            break
        end
    end
    resolved === nothing &&
        error("未找到列名: $(column_name)，可用列: $(join(headers, ", "))")
    return df[:, resolved], resolved
end

"""
    extract_float_column(col_data) -> Vector{Any}

把 DataFrame 列数据转成 Vector{Any}，每个元素尝试 Float64(val)，
转换失败则填 0.0。
"""
function extract_float_column(col_data)
    values = Vector{Any}()
    for val in col_data
        try
            push!(values, Float64(val))
        catch
            push!(values, 0.0)
        end
    end
    return values
end