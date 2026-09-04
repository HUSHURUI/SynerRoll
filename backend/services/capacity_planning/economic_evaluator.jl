struct OperatingObjectiveEvaluator <: AbstractEconomicEvaluator end

const OPERATING_OBJECTIVE_EVALUATOR_VERSION = "operating-objective-v1"

"""
    evaluate_economics(::OperatingObjectiveEvaluator, input)

在财务参数口径尚未确认前，只使用模型真实返回的年度加权运行目标参与优化。
CAPEX、NPV、IRR、LCOE 不填占位数字，结果中明确返回 `nothing` 和 warning。
"""
function evaluate_economics(
    ::OperatingObjectiveEvaluator,
    input::EconomicEvaluationInput,
)::EconomicEvaluationResult
    input.simulation.feasible || throw(CapacityPlanningError("INFEASIBLE", "不可行仿真不能进入经济评价"))
    operating = input.simulation.operating_objective
    isfinite(operating) || throw(CapacityPlanningError("NON_FINITE_FITNESS", "运行目标不是有限数值"))

    return EconomicEvaluationResult(
        fitness=operating,
        breakdown=Dict(
            "weightedOperatingObjective" => operating,
            "annualizedCapex" => 0.0,
            "penalty" => 0.0,
        ),
        indicators=Dict{String,Union{Float64,Nothing}}(
            "npv" => nothing,
            "irr" => nothing,
            "lcoe" => nothing,
        ),
        warnings=[
            "当前使用 operating-objective-v1，仅优化模型运行目标；CAPEX 及 NPV/IRR/LCOE 未参与计算。",
            "确认 initial_cost、replace_cost、life_year 等字段口径后可替换经济评价器，无需修改优化任务和场景数据结构。",
        ],
        evaluator_version=OPERATING_OBJECTIVE_EVALUATOR_VERSION,
    )
end

function economic_evaluator_from_config(config::AbstractDict)
    evaluator = string(get(config, "evaluator", OPERATING_OBJECTIVE_EVALUATOR_VERSION))
    evaluator == OPERATING_OBJECTIVE_EVALUATOR_VERSION || throw(CapacityPlanningError(
        "ECONOMIC_EVALUATOR_UNSUPPORTED", "当前仅支持 $(OPERATING_OBJECTIVE_EVALUATOR_VERSION)",
    ))
    return OperatingObjectiveEvaluator()
end
