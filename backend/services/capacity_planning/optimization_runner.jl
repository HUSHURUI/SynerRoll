using BlackBoxOptim
using JSON3
using Random
using SHA

const CAPACITY_OPTIMIZER_METHODS = Set([
    "adaptive_de_rand_1_bin_radiuslimited",
    "adaptive_de_rand_1_bin",
    "separable_nes",
])
const CAPACITY_EVALUATOR_VERSION = "simulation-evaluator-v1"
const PLANNING_OPTIMIZER_LOCK = ReentrantLock()

function _quantize_candidate(values, variables)
    quantized = Float64[]
    optimize_variables = [item for item in variables if item["mode"] == "optimize"]
    length(values) == length(optimize_variables) || throw(CapacityPlanningError(
        "CANDIDATE_DIMENSION_MISMATCH", "优化器返回的候选维度不正确",
    ))
    for (value, variable) in zip(values, optimize_variables)
        lower = Float64(variable["lowerBound"])
        upper = Float64(variable["upperBound"])
        step = Float64(get(variable, "step", 0.0))
        number = Float64(value)
        isfinite(number) || throw(CapacityPlanningError("NON_FINITE_CANDIDATE", "优化器返回非有限容量"))
        if step > 0
            number = lower + round((number - lower) / step) * step
        end
        push!(quantized, clamp(number, lower, upper))
    end
    return quantized
end

function _candidate_payload(variables, optimized_values)
    result = Dict{String,Any}()
    optimized_index = 0
    for variable in variables
        value = if variable["mode"] == "optimize"
            optimized_index += 1
            optimized_values[optimized_index]
        else
            Float64(variable["fixedValue"])
        end
        result[string(variable["componentId"])] = Dict(
            "value" => value,
            "unit" => string(variable["unit"]),
            "mode" => string(variable["mode"]),
        )
    end
    return result
end

function _candidate_hash(task, scenario_set, values, economic_version)
    payload = Dict(
        "projectSnapshotHash" => task["projectSnapshotHash"],
        "scenarioSetHash" => scenario_set["scenarioSetHash"],
        "candidate" => values,
        "evaluatorVersion" => CAPACITY_EVALUATOR_VERSION,
        "economicModelVersion" => economic_version,
    )
    return bytes2hex(SHA.sha256(Vector{UInt8}(codeunits(JSON3.write(payload)))))
end

function _planning_cancelled(ctx)
    return isready(ctx.signal_ch) && take!(ctx.signal_ch) == :cancel
end

function _planning_phase_progress!(planning_id, phase, started_ns; kwargs...)
    task = get_planning_task(planning_id)
    progress = task === nothing ? Dict{String,Any}() : task["progress"]
    progress["phase"] = phase
    progress["elapsedMs"] = round(Int, (time_ns() - started_ns) / 1_000_000)
    for (key, value) in kwargs
        progress[string(key)] = value
    end
    update_planning_progress!(planning_id, progress)
    return progress
end

function _planning_result_variables(variables, best_candidate)
    result = Dict{String,Any}[]
    for variable in variables
        component_id = string(variable["componentId"])
        optimal = Float64(best_candidate[component_id]["value"])
        current = Float64(variable["currentValue"])
        change_rate = abs(current) <= eps(Float64) ? nothing : (optimal - current) / current
        push!(result, Dict{String,Any}(
            "componentId" => component_id,
            "componentKey" => variable["componentKey"],
            "componentName" => variable["componentName"],
            "mode" => variable["mode"],
            "unit" => variable["unit"],
            "currentValue" => current,
            "optimalValue" => optimal,
            "changeRate" => change_rate,
        ))
    end
    return result
end

"""运行一个已冻结的规划任务。调用方负责捕获异常并更新终态。"""
function run_capacity_optimization!(planning_id::String, ctx)
    lock(PLANNING_OPTIMIZER_LOCK) do
        started_ns = time_ns()
        task = get_planning_task(planning_id)
        task === nothing && error("规划任务不存在: $(planning_id)")
        config = task["config"]
        planning_dir = planning_task_dir(planning_id)
        snapshot = JSON3.read(read(joinpath(planning_dir, "project_snapshot.json"), String), Dict{String,Any})

        set_planning_status!(planning_id, "validating")
        _planning_phase_progress!(planning_id, "validating", started_ns)
        _planning_cancelled(ctx) && throw(PlanningCancelled("规划任务已取消"))
        variables = validate_capacity_variables(snapshot, task["canvasId"], config["variables"])
        config["variables"] = variables
        update_planning_config!(planning_id, config)

        set_planning_status!(planning_id, "clustering")
        _planning_phase_progress!(planning_id, "clustering", started_ns)
        _planning_cancelled(ctx) && throw(PlanningCancelled("规划任务已取消"))
        scenario_set = reduce_boundary_scenarios(config["clustering"])
        save_planning_scenarios!(planning_id, scenario_set)
        save_scenario_set_series!(planning_id, scenario_set["scenarios"])
        write(joinpath(planning_dir, "scenarios.json"), JSON3.write(scenario_set))

        optimizer = config["optimizer"]
        economics_config = config["economics"]
        economic_evaluator = economic_evaluator_from_config(economics_config)
        economic_version = OPERATING_OBJECTIVE_EVALUATOR_VERSION
        failure_penalty = Float64(optimizer["failurePenalty"])
        max_evaluations = Int(optimizer["maxFuncEvals"])
        variables_optimized = [item for item in variables if item["mode"] == "optimize"]
        suggested = Float64[item["suggestedValue"] for item in variables_optimized]
        search_range = [(Float64(item["lowerBound"]), Float64(item["upperBound"])) for item in variables_optimized]
        units = Dict(string(item["componentId"]) => string(item["unit"]) for item in variables)

        set_planning_status!(planning_id, "optimizing")
        progress = _planning_phase_progress!(
            planning_id, "optimizing", started_ns;
            maxFuncEvals=max_evaluations,
            completedEvaluations=0,
            failedEvaluations=0,
            bestFitness=nothing,
            bestCandidate=nothing,
            convergence=Any[],
        )

        completed = Ref(0)
        failed = Ref(0)
        consecutive_failed = Ref(0)
        best_fitness = Ref(Inf)
        best_candidate = Ref{Union{Nothing,Dict{String,Any}}}(nothing)
        best_breakdown = Ref{Union{Nothing,Dict{String,Any}}}(nothing)
        best_warnings = Ref(String[])
        best_work_dir = Ref{Union{Nothing,String}}(nothing)
        live_history = Dict{String,Any}[]

        function fitness(raw_values)
            _planning_cancelled(ctx) && throw(PlanningCancelled("规划任务已取消"))
            values = _quantize_candidate(raw_values, variables)
            candidate = _candidate_payload(variables, values)
            candidate_hash = _candidate_hash(task, scenario_set, values, economic_version)
            cached = cached_planning_evaluation(planning_id, candidate_hash)
            cached !== nothing && return Float64(cached["fitness"])

            if completed[] >= max_evaluations
                return isfinite(best_fitness[]) ? best_fitness[] : failure_penalty
            end

            evaluation_started = time_ns()
            ordinal = completed[] + 1
            feasible = false
            evaluation_fitness = failure_penalty
            breakdown = Dict{String,Any}()
            error_code = nothing
            error_message = nothing
            warnings = String[]
            work_dir = joinpath(planning_dir, "work", candidate_hash[1:16])

            try
                candidate_snapshot, capacities = apply_capacity_candidate(snapshot, task["canvasId"], variables, values)
                simulation = evaluate_snapshot(
                    candidate_snapshot,
                    task["canvasId"],
                    scenario_set,
                    work_dir;
                    options=EvaluationOptions(layer_id=string(config["planningLayerId"])),
                    planning_id=planning_id,
                )
                if simulation.feasible
                    economic = evaluate_economics(
                        economic_evaluator,
                        EconomicEvaluationInput(
                            capacities=capacities,
                            units=units,
                            simulation=simulation,
                            config=economics_config,
                        ),
                    )
                    evaluation_fitness = economic.fitness
                    breakdown = Dict{String,Any}(economic.breakdown)
                    breakdown["scenarioMetrics"] = simulation.scenario_metrics
                    warnings = economic.warnings
                    feasible = true
                    consecutive_failed[] = 0
                else
                    error_code = simulation.error_code
                    error_message = simulation.error_message
                end
            catch error
                error_code = error isa CapacityPlanningError ? error.code : "EVALUATION_ERROR"
                error_message = error isa CapacityPlanningError ? error.message : sprint(showerror, error)
            end

            if !feasible
                failed[] += 1
                consecutive_failed[] += 1
                evaluation_fitness = isfinite(best_fitness[]) ?
                    max(failure_penalty, abs(best_fitness[]) * 10 + failure_penalty) : failure_penalty
                breakdown = Dict("failurePenalty" => evaluation_fitness)
            end
            isfinite(evaluation_fitness) || (evaluation_fitness = max(failure_penalty, 1.0e18))
            duration_ms = round(Int, (time_ns() - evaluation_started) / 1_000_000)
            evaluation_id = insert_planning_evaluation!(
                planning_id=planning_id,
                ordinal=ordinal,
                candidate_hash=candidate_hash,
                candidate=candidate,
                feasible=feasible,
                fitness=evaluation_fitness,
                breakdown=breakdown,
                duration_ms=duration_ms,
                error_code=error_code,
                error_message=error_message,
            )
            completed[] += 1

            if feasible && evaluation_fitness < best_fitness[]
                previous_best_dir = best_work_dir[]
                if previous_best_dir !== nothing && previous_best_dir != work_dir && isdir(previous_best_dir)
                    rm(previous_best_dir; recursive=true, force=true)
                end
                best_fitness[] = evaluation_fitness
                best_candidate[] = candidate
                best_breakdown[] = breakdown
                best_warnings[] = warnings
                best_work_dir[] = work_dir
                set_best_planning_evaluation!(planning_id, evaluation_id)
            elseif isdir(work_dir)
                rm(work_dir; recursive=true, force=true)
            end

            push!(live_history, Dict{String,Any}(
                "ordinal" => ordinal,
                "fitness" => evaluation_fitness,
                "feasible" => feasible,
                "bestSoFar" => isfinite(best_fitness[]) ? best_fitness[] : nothing,
            ))

            progress = _planning_phase_progress!(
                planning_id, "optimizing", started_ns;
                maxFuncEvals=max_evaluations,
                completedEvaluations=completed[],
                failedEvaluations=failed[],
                bestFitness=isfinite(best_fitness[]) ? best_fitness[] : nothing,
                bestCandidate=best_candidate[],
                convergence=live_history,
            )
            consecutive_failed[] >= 20 && throw(CapacityPlanningError(
                "TOO_MANY_FAILED_EVALUATIONS", "连续 20 个候选评价失败，请检查边界数据和容量范围",
            ))
            return evaluation_fitness
        end

        # 建议解必须先被独立评价并进入历史。
        fitness(suggested)
        _planning_cancelled(ctx) && throw(PlanningCancelled("规划任务已取消"))

        remaining = max_evaluations - completed[]
        if remaining > 0
            Random.seed!(Int(optimizer["seed"]))
            method = Symbol(string(optimizer["method"]))
            kwargs = Dict{Symbol,Any}(
                :SearchRange => search_range,
                :NumDimensions => length(search_range),
                :Method => method,
                :MaxFuncEvals => remaining,
                :PopulationSize => Int(optimizer["populationSize"]),
                :TraceMode => :silent,
            )
            max_time = get(optimizer, "maxTimeSeconds", nothing)
            max_time !== nothing && (kwargs[:MaxTime] = Float64(max_time))
            BlackBoxOptim.bboptimize(fitness, suggested; kwargs...)
        end

        best_candidate[] === nothing && throw(CapacityPlanningError(
            "NO_FEASIBLE_CANDIDATE", "评价预算内没有找到可行容量方案",
        ))
        evaluations = list_planning_evaluations(planning_id)
        best_history = Dict{String,Any}[]
        running_best = Inf
        for item in evaluations
            if item["feasible"]
                running_best = min(running_best, Float64(item["fitness"]))
            end
            push!(best_history, Dict(
                "ordinal" => item["ordinal"],
                "fitness" => item["fitness"],
                "feasible" => item["feasible"],
                "bestSoFar" => isfinite(running_best) ? running_best : nothing,
            ))
        end

        result = Dict{String,Any}(
            "planningId" => planning_id,
            "projectId" => task["projectId"],
            "canvasId" => task["canvasId"],
            "projectUpdatedAt" => task["projectUpdatedAt"],
            "scenarioSetHash" => scenario_set["scenarioSetHash"],
            "fitness" => best_fitness[],
            "breakdown" => best_breakdown[],
            "warnings" => best_warnings[],
            "economicEvaluatorVersion" => economic_version,
            "simulationEvaluatorVersion" => CAPACITY_EVALUATOR_VERSION,
            "variables" => _planning_result_variables(variables, best_candidate[]),
            "bestCandidate" => best_candidate[],
            "evaluationCount" => completed[],
            "failedEvaluationCount" => failed[],
            "convergence" => best_history,
            "scenarioSummary" => Dict(
                "config" => scenario_set["config"],
                "quality" => scenario_set["quality"],
                "scenarios" => [Dict(
                    "scenarioId" => item["scenarioId"],
                    "representativeDate" => item["representativeDate"],
                    "weightDays" => item["weightDays"],
                    "probability" => item["probability"],
                ) for item in scenario_set["scenarios"]],
            ),
        )
        save_planning_result!(planning_id, result)
        write(joinpath(planning_dir, "result.json"), JSON3.write(result))
        _planning_phase_progress!(
            planning_id, "completed", started_ns;
            completedEvaluations=completed[],
            failedEvaluations=failed[],
            bestFitness=best_fitness[],
            bestCandidate=best_candidate[],
            convergence=best_history,
        )
        set_planning_status!(planning_id, "completed")
        return result
    end
end
