# ═══════════════════════════════════════════════════════════════════════════
# BackendStandardized-Base.jl — 原始构建系统测试文件
#
# 用途：
#   - 使用 model-base.jl（数学原理蓝图）进行单实例组件的数学功能验证
#   - 变量名无后缀（E_WT, E_CP, E_ES 等），直接可读
#   - 不支持同类型多组件（如2台风机），不生成代码追踪
#   - 用于原始开发和数学原理校验
#
# 对应的新版测试系统见 BackendStandardized.jl（支持多组件 + 代码追踪）
# ═══════════════════════════════════════════════════════════════════════════

begin
    using JSON3
    using JuMP
    using COPT

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

    # ── 组件定义（加载 model-base.jl：数学原理蓝图，无后缀变量名）────────
    include("components/wind_turbine/component.jl")
    include("components/wind_turbine/validation.jl")
    include("components/wind_turbine/model-common.jl")
    include("components/wind_turbine/flexibility.jl")
    include("components/wind_turbine/model-base.jl")

    include("components/photovoltaic/component.jl")
    include("components/photovoltaic/validation.jl")
    include("components/photovoltaic/model-common.jl")
    include("components/photovoltaic/flexibility.jl")
    include("components/photovoltaic/model-base.jl")

    include("components/coal_power/component.jl")
    include("components/coal_power/validation.jl")
    include("components/coal_power/model-common.jl")
    include("components/coal_power/flexibility.jl")
    include("components/coal_power/model-base.jl")

    include("components/gas_power/component.jl")
    include("components/gas_power/validation.jl")
    include("components/gas_power/model-common.jl")
    include("components/gas_power/flexibility.jl")
    include("components/gas_power/model-base.jl")

    include("components/combined_heat_power/component.jl")
    include("components/combined_heat_power/validation.jl")
    include("components/combined_heat_power/model-common.jl")
    include("components/combined_heat_power/flexibility.jl")
    include("components/combined_heat_power/model-base.jl")

    include("components/electricity_load/component.jl")
    include("components/electricity_load/validation.jl")
    include("components/electricity_load/model-common.jl")
    include("components/electricity_load/flexibility.jl")
    include("components/electricity_load/model-base.jl")

    include("components/hydrogen_load/component.jl")
    include("components/hydrogen_load/validation.jl")
    include("components/hydrogen_load/model-common.jl")
    include("components/hydrogen_load/flexibility.jl")
    include("components/hydrogen_load/model-base.jl")

    include("components/electrolyzer/component.jl")
    include("components/electrolyzer/validation.jl")
    include("components/electrolyzer/model-common.jl")
    include("components/electrolyzer/flexibility.jl")
    include("components/electrolyzer/model-base.jl")

    include("components/electricity_storage/component.jl")
    include("components/electricity_storage/validation.jl")
    include("components/electricity_storage/model-common.jl")
    include("components/electricity_storage/flexibility.jl")
    include("components/electricity_storage/model-base.jl")

    include("components/hydrogen_storage/component.jl")
    include("components/hydrogen_storage/validation.jl")
    include("components/hydrogen_storage/model-common.jl")
    include("components/hydrogen_storage/flexibility.jl")
    include("components/hydrogen_storage/model-base.jl")

    include("components/flywheel_storage/component.jl")
    include("components/flywheel_storage/validation.jl")
    include("components/flywheel_storage/model-common.jl")
    include("components/flywheel_storage/flexibility.jl")
    include("components/flywheel_storage/model-base.jl")

    include("components/compressed_air_storage/component.jl")
    include("components/compressed_air_storage/validation.jl")
    include("components/compressed_air_storage/model-common.jl")
    include("components/compressed_air_storage/flexibility.jl")
    include("components/compressed_air_storage/model-base.jl")

    include("components/pumped_storage/component.jl")
    include("components/pumped_storage/validation.jl")
    include("components/pumped_storage/model-common.jl")
    include("components/pumped_storage/flexibility.jl")
    include("components/pumped_storage/model-base.jl")

    include("components/power_grid/component.jl")
    include("components/power_grid/validation.jl")
    include("components/power_grid/model-common.jl")
    include("components/power_grid/flexibility.jl")
    include("components/power_grid/model-base.jl")

    include("components/hydro_power/component.jl")
    include("components/hydro_power/validation.jl")
    include("components/hydro_power/model-common.jl")
    include("components/hydro_power/flexibility.jl")
    include("components/hydro_power/model-base.jl")

    include("services/flexibility_baseline_adapter.jl")
    include("services/flexibility_supply_service.jl")
    include("services/flexibility_requirement_service.jl")
    include("services/flexibility_margin_service.jl")
    include("services/model_service.jl")
    include("services/flexibility_evaluation_service.jl")
    include("services/flexibility_result_service.jl")
end

# ═══════════════════════════════════════════════════════════════════════════
# 测试：加载数据 + 构建模型
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

# ── 使用原始 build_model（无代码追踪）────────────────────────────────
model, components = build_model(component_dicts, algorithms, nodes, layers[1], time, db_path)

@info "模型构建完成"
@info "变量数: $(num_variables(model))  约束数: $( num_constraints(model; count_variable_in_set_constraints = true))"

# ── 求解 ──────────────────────────────────────────────────────────────
JuMP.optimize!(model)

if JuMP.termination_status(model) == MOI.OPTIMAL
    @info "求解成功！目标值: $(JuMP.objective_value(model))"
else
    @warn "求解状态: $(JuMP.termination_status(model))"
end
