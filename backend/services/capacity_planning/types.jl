"""容量规划内部错误；`code` 用于向 API 返回稳定、可判断的失败原因。"""
struct CapacityPlanningError <: Exception
    code::String
    message::String
end

Base.showerror(io::IO, error::CapacityPlanningError) = print(io, "$(error.code): $(error.message)")

Base.@kwdef struct EvaluationOptions
    layer_id::String = "1"
    persist_timeseries::Bool = false
    generate_code::Bool = false
    stop_on_infeasible::Bool = true
end

Base.@kwdef struct EvaluationResult
    feasible::Bool
    operating_objective::Float64
    metrics::Dict{String,Float64}
    scenario_metrics::Vector{Dict{String,Any}}
    error_code::Union{Nothing,String} = nothing
    error_message::Union{Nothing,String} = nothing
end

abstract type AbstractEconomicEvaluator end

Base.@kwdef struct EconomicEvaluationInput
    capacities::Dict{String,Float64}
    units::Dict{String,String}
    simulation::EvaluationResult
    config::Dict{String,Any}
end

Base.@kwdef struct EconomicEvaluationResult
    fitness::Float64
    breakdown::Dict{String,Float64}
    indicators::Dict{String,Union{Float64,Nothing}}
    warnings::Vector{String}
    evaluator_version::String
end

struct PlanningCancelled <: Exception
    message::String
end

Base.showerror(io::IO, error::PlanningCancelled) = print(io, error.message)
