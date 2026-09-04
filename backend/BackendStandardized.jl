begin
    using JSON3
    using JuMP
    using COPT
    # using MathOptInterface

    include("utils/timestr_utils.jl")
    include("utils/layer_utils.jl")
    include("utils/timeseries_utils.jl")

    include("core/types.jl")
    include("core/schema.jl")
    include("core/validation.jl")
    include("core/component_framework.jl")
    include("core/flexibility.jl")
    include("core/system_flexibility.jl")

    include("services/boundary_service.jl")

    include("utils/prediction_utils.jl")
    include("utils/model_utils.jl")
    include("utils/flexibility_utils.jl")
    include("utils/model_builder_utils.jl")

    # 组件定义（schema 已从统一 JSON 配置加载，不再需要独立 schema.jl）
    include("components/wind_turbine/component.jl")
    include("components/wind_turbine/validation.jl")
    include("components/wind_turbine/model-common.jl")
    include("components/wind_turbine/flexibility.jl")
    include("components/wind_turbine/model.jl")        # 元编程架构（新版）

    include("components/photovoltaic/component.jl")
    include("components/photovoltaic/validation.jl")
    include("components/photovoltaic/model-common.jl")
    include("components/photovoltaic/flexibility.jl")
    include("components/photovoltaic/model.jl")        # 元编程架构（新版）

    include("components/coal_power/component.jl")
    include("components/coal_power/validation.jl")
    include("components/coal_power/model-common.jl")
    include("components/coal_power/flexibility.jl")
    include("components/coal_power/model.jl")           # 元编程架构（新版）

    include("components/gas_power/component.jl")
    include("components/gas_power/validation.jl")
    include("components/gas_power/model-common.jl")
    include("components/gas_power/flexibility.jl")
    include("components/gas_power/model.jl")

    include("components/combined_heat_power/component.jl")
    include("components/combined_heat_power/validation.jl")
    include("components/combined_heat_power/model-common.jl")
    include("components/combined_heat_power/flexibility.jl")
    include("components/combined_heat_power/model.jl")   # 元编程架构（新版）

    include("components/electricity_load/component.jl")
    include("components/electricity_load/validation.jl")
    include("components/electricity_load/model-common.jl")
    include("components/electricity_load/flexibility.jl")
    include("components/electricity_load/model.jl")     # 元编程架构（新版）

    include("components/hydrogen_load/component.jl")
    include("components/hydrogen_load/validation.jl")
    include("components/hydrogen_load/model-common.jl")
    include("components/hydrogen_load/flexibility.jl")
    include("components/hydrogen_load/model.jl")       # 元编程架构（新版）

    include("components/heat_load/component.jl")
    include("components/heat_load/validation.jl")
    include("components/heat_load/model-common.jl")
    include("components/heat_load/flexibility.jl")
    include("components/heat_load/model.jl")           # 元编程架构（新版）

    include("components/electrolyzer/component.jl")
    include("components/electrolyzer/validation.jl")
    include("components/electrolyzer/model-common.jl")
    include("components/electrolyzer/flexibility.jl")
    include("components/electrolyzer/model.jl")          # 元编程架构（新版）

    include("components/electricity_storage/component.jl")
    include("components/electricity_storage/validation.jl")
    include("components/electricity_storage/model-common.jl")
    include("components/electricity_storage/flexibility.jl")
    include("components/electricity_storage/model.jl")  # 元编程架构（新版）

    include("components/hydrogen_storage/component.jl")
    include("components/hydrogen_storage/validation.jl")
    include("components/hydrogen_storage/model-common.jl")
    include("components/hydrogen_storage/flexibility.jl")
    include("components/hydrogen_storage/model.jl")  # 元编程架构（新版）

    include("components/flywheel_storage/component.jl")
    include("components/flywheel_storage/validation.jl")
    include("components/flywheel_storage/model-common.jl")
    include("components/flywheel_storage/flexibility.jl")
    include("components/flywheel_storage/model.jl")  # 元编程架构（新版）

    include("components/compressed_air_storage/component.jl")
    include("components/compressed_air_storage/validation.jl")
    include("components/compressed_air_storage/model-common.jl")
    include("components/compressed_air_storage/flexibility.jl")
    include("components/compressed_air_storage/model.jl")  # 元编程架构（新版）

    include("components/pumped_storage/component.jl")
    include("components/pumped_storage/validation.jl")
    include("components/pumped_storage/model-common.jl")
    include("components/pumped_storage/flexibility.jl")
    include("components/pumped_storage/model.jl")  # 元编程架构（新版）

    include("components/power_grid/component.jl")
    include("components/power_grid/validation.jl")
    include("components/power_grid/model-common.jl")
    include("components/power_grid/flexibility.jl")
    include("components/power_grid/model.jl")  # 元编程架构（新版）

    include("components/hydro_power/component.jl")
    include("components/hydro_power/validation.jl")
    include("components/hydro_power/model-common.jl")
    include("components/hydro_power/flexibility.jl")
    include("components/hydro_power/model.jl")  # 元编程架构（新版）

    include("services/flexibility_baseline_adapter.jl")
    include("services/flexibility_supply_service.jl")
    include("services/flexibility_requirement_service.jl")
    include("services/flexibility_margin_service.jl")
    include("services/model_service.jl")
    include("services/flexibility_evaluation_service.jl")
    include("services/flexibility_result_service.jl")
end

# ═══════════════════════════════════════════════════════════════════════════
# 测试：加载数据 + 构建模型 + 输出构建过程代码
# ═══════════════════════════════════════════════════════════════════════════

const _COMPONENT_LIB_PATH = joinpath(@__DIR__, "..", "config", "component-library.json")
load_component_library(_COMPONENT_LIB_PATH)

const _TASK_DIR = joinpath(@__DIR__, "data", "tasks", "a93819bb-5400-416f-b9d9-c6435c8a2fec")
component_dicts = JSON3.read(read(joinpath(_TASK_DIR, "component.json"), String), Vector{Dict{String,Any}})
nodes = JSON3.read(read(joinpath(_TASK_DIR, "connection.json"), String), Vector{Dict{String,Any}})
project_json = JSON3.read(read(joinpath(_TASK_DIR, "project.json"), String), Dict)
layers = project_json["layerConfig"]["layers"]
algorithms = project_json["algorithm"]
time = "0:00"
db_path = joinpath(_TASK_DIR, "timeseries.db")

# ── 使用 build_model_tracked 构建模型 + 追踪代码 ──────────────────────
model, _, construction_code = build_model_tracked(component_dicts, algorithms, nodes, layers[1], time, db_path)

# ── 输出构建过程代码到 .jl 文件 ─────────────────────────────────────────
output_path = joinpath(_TASK_DIR, "generated_code.jl")
open(output_path, "w") do io
    write(io, construction_code)
end
@info "构建过程代码已写入: $(output_path)"
@info "模型变量数: $(num_variables(model))  约束数: $( num_constraints(model; count_variable_in_set_constraints = true))"
println("\n", "="^60)
println("构建过程预览（前 30 行）：")
println("="^60)
for (i, line) in enumerate(split(construction_code, "\n"))
    i > 30 && break
    println(line)
end
