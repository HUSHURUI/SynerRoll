using JSON3
using SHA

mutable struct PlanningContext
    signal_ch::Channel{Symbol}
    julia_task::Union{Task,Nothing}
end

const PLANNING_CONTEXTS = Dict{String,PlanningContext}()
const PLANNING_CONTEXTS_LOCK = ReentrantLock()

function _planning_dict(value, field::String)
    value isa AbstractDict || error("$(field) 必须是对象")
    return Dict{String,Any}(string(key) => item for (key, item) in value)
end

function _normalize_optimizer_config(raw)
    config = _planning_dict(raw, "optimizer")
    method = string(get(config, "method", "adaptive_de_rand_1_bin_radiuslimited"))
    method in CAPACITY_OPTIMIZER_METHODS || error("不支持的优化方法: $(method)")
    max_evals = Int(get(config, "maxFuncEvals", 20))
    2 <= max_evals <= 10_000 || error("maxFuncEvals 必须在 2 到 10000 之间")
    population = Int(get(config, "populationSize", min(10, max_evals)))
    2 <= population <= 500 || error("populationSize 必须在 2 到 500 之间")
    failure_penalty = Float64(get(config, "failurePenalty", 1.0e18))
    isfinite(failure_penalty) && failure_penalty > 0 || error("failurePenalty 必须是正的有限数值")
    result = Dict{String,Any}(
        "method" => method,
        "maxFuncEvals" => max_evals,
        "populationSize" => population,
        "seed" => Int(get(config, "seed", 20260828)),
        "failurePenalty" => failure_penalty,
    )
    if haskey(config, "maxTimeSeconds") && config["maxTimeSeconds"] !== nothing
        max_time = Float64(config["maxTimeSeconds"])
        1 <= max_time <= 86_400 || error("maxTimeSeconds 必须在 1 到 86400 之间")
        result["maxTimeSeconds"] = max_time
    end
    return result
end

const CAPACITY_PLAN_OBJECTIVES = Set([
    "total-cost-min",
    "operating-cost-min",
    "initial-investment-min",
    "npv-max",
    "lcoe-min",
    "payback-period-min",
    "irr-max",
])

function _normalize_percent(value, field::String)
    number = Float64(value)
    isfinite(number) && 0 <= number <= 100 || error("$(field) 必须在 0 到 100 之间")
    return number
end

function _normalize_economics_config(raw)
    config = _planning_dict(raw, "economics")
    evaluator = string(get(config, "evaluator", OPERATING_OBJECTIVE_EVALUATOR_VERSION))
    objective = string(get(config, "objective", "operating-cost-min"))
    objective in CAPACITY_PLAN_OBJECTIVES || error("不支持的方案目标: $(objective)")

    constraint_defaults = Dict(
        "renewableConsumptionRate" => ("gte", 90.0),
        "greenPowerShare" => ("gte", 50.0),
        "purchasedPowerShare" => ("lte", 30.0),
        "stability" => ("gte", 95.0),
    )
    raw_constraints = get(config, "technicalConstraints", Dict{String,Any}())
    raw_constraints isa AbstractDict || error("economics.technicalConstraints 必须是对象")
    constraints = Dict{String,Any}()
    for (key, (default_operator, default_threshold)) in constraint_defaults
        raw_constraint = get(raw_constraints, key, Dict{String,Any}())
        raw_constraint isa AbstractDict || error("economics.technicalConstraints.$(key) 必须是对象")
        operator = string(get(raw_constraint, "operator", default_operator))
        operator in ("gte", "lte") || error("economics.technicalConstraints.$(key).operator 无效")
        constraints[key] = Dict(
            "enabled" => get(raw_constraint, "enabled", false) == true,
            "operator" => operator,
            "threshold" => _normalize_percent(get(raw_constraint, "threshold", default_threshold), "$(key).threshold"),
            "unit" => "%",
        )
    end

    economic_constraint_defaults = Dict(
        "lifecycleYears" => ("gte", 20.0, "年"),
        "interestRatePercent" => ("lte", 5.0, "%"),
        "taxRatePercent" => ("lte", 25.0, "%"),
        "targetIrrPercent" => ("gte", 8.0, "%"),
    )
    raw_economic_constraints = get(config, "economicConstraints", nothing)
    legacy_financial = get(config, "financialParameters", Dict{String,Any}())
    legacy_financial isa AbstractDict || error("economics.financialParameters 必须是对象")
    if raw_economic_constraints === nothing
        raw_economic_constraints = Dict{String,Any}(
            key => Dict("enabled" => false, "threshold" => get(legacy_financial, key, default_threshold))
            for (key, (_, default_threshold, _)) in economic_constraint_defaults
        )
    end
    raw_economic_constraints isa AbstractDict || error("economics.economicConstraints 必须是对象")
    economic_constraints = Dict{String,Any}()
    for (key, (default_operator, default_threshold, unit)) in economic_constraint_defaults
        raw_constraint = get(raw_economic_constraints, key, Dict{String,Any}())
        raw_constraint isa AbstractDict || error("economics.economicConstraints.$(key) 必须是对象")
        operator = string(get(raw_constraint, "operator", default_operator))
        operator in ("gte", "lte") || error("economics.economicConstraints.$(key).operator 无效")
        threshold = Float64(get(raw_constraint, "threshold", default_threshold))
        if key == "lifecycleYears"
            isfinite(threshold) && 1 <= threshold <= 100 || error("lifecycleYears.threshold 必须在 1 到 100 之间")
        else
            threshold = _normalize_percent(threshold, "$(key).threshold")
        end
        economic_constraints[key] = Dict(
            "enabled" => get(raw_constraint, "enabled", false) == true,
            "operator" => operator,
            "threshold" => threshold,
            "unit" => unit,
        )
    end

    raw_extensions = get(config, "extensions", Dict{String,Any}())
    raw_extensions isa AbstractDict || error("economics.extensions 必须是对象")
    result = Dict{String,Any}(
        "evaluator" => evaluator,
        "currency" => string(get(config, "currency", "CNY")),
        "schemaVersion" => "capacity-objective-config-v2",
        "objective" => objective,
        "technicalConstraints" => constraints,
        "economicConstraints" => economic_constraints,
        "extensions" => Dict{String,Any}(string(key) => value for (key, value) in raw_extensions),
    )
    economic_evaluator_from_config(result)
    return result
end

function _normalize_clustering_config(raw, project_id::String)
    config = _planning_dict(raw, "clustering")
    dataset_id = String(strip(string(get(config, "datasetId", ""))))
    # 允许 datasetId 为空（草稿状态，后续步骤中补充）
    feature_ids_raw = get(config, "featureIds", nothing)
    feature_ids = feature_ids_raw isa AbstractVector ? String.(feature_ids_raw) : String[]
    algorithm = string(get(config, "algorithm", "kmeans"))
    algorithm in ("kmeans", "kmedoids") || error("clustering.algorithm 只能是 kmeans 或 kmedoids")
    return Dict{String,Any}(
        "projectId" => project_id,
        "datasetId" => isempty(dataset_id) ? nothing : dataset_id,
        "featureIds" => feature_ids,
        "clusterCount" => Int(get(config, "clusterCount", 0)),
        "algorithm" => algorithm,
        "normalize" => string(get(config, "normalize", "zscore")),
        "missingDayThreshold" => Float64(get(config, "missingDayThreshold", 0.05)),
        "seed" => Int(get(config, "seed", 20260828)),
        "representative" => string(get(config, "representative", "nearest-observation")),
    )
end

function create_capacity_planning!(request::AbstractDict)
    project_id = String(strip(string(get(request, "projectId", ""))))
    canvas_id = String(strip(string(get(request, "canvasId", ""))))
    isempty(project_id) && error("缺少 projectId")
    isempty(canvas_id) && error("缺少 canvasId")
    snapshot = get(request, "projectJson", nothing)
    snapshot isa AbstractDict || error("缺少 projectJson（项目快照）")
    string(get(snapshot, "id", "")) == project_id || error("projectId 与项目快照不一致")
    variables_raw = get(request, "variables", nothing)
    variables_raw isa AbstractVector || error("variables 必须是数组")
    variables = validate_capacity_variables(snapshot, canvas_id, variables_raw)
    clustering = _normalize_clustering_config(get(request, "clustering", nothing), project_id)
    optimizer = _normalize_optimizer_config(get(request, "optimizer", Dict()))
    economics = _normalize_economics_config(get(request, "economics", Dict("evaluator" => OPERATING_OBJECTIVE_EVALUATOR_VERSION)))
    planning_layer_id = string(get(request, "planningLayerId", "1"))
    _planning_layer(snapshot, planning_layer_id)

    project_updated_at = string(get(snapshot, "updateTime", ""))
    isempty(project_updated_at) && error("项目快照缺少 updateTime")
    snapshot_json = JSON3.write(snapshot)
    snapshot_hash = bytes2hex(SHA.sha256(Vector{UInt8}(codeunits(snapshot_json))))
    config = Dict{String,Any}(
        "variables" => variables,
        "clustering" => clustering,
        "optimizer" => optimizer,
        "economics" => economics,
        "planningLayerId" => planning_layer_id,
    )
    planning_id = create_planning_record!(
        project_id=project_id,
        canvas_id=canvas_id,
        name=String(strip(string(get(request, "name", "")))),
        project_updated_at=project_updated_at,
        snapshot_hash=snapshot_hash,
        config=config,
    )
    directory = planning_task_dir(planning_id)
    try
        mkpath(directory)
        write(joinpath(directory, "project_snapshot.json"), snapshot_json)
        write(joinpath(directory, "config.json"), JSON3.write(config))
    catch error
        set_planning_status!(planning_id, "failed"; error_code="SNAPSHOT_WRITE_FAILED", error_message=sprint(showerror, error))
        rethrow()
    end
    return get_planning_task(planning_id)
end

function start_capacity_planning!(planning_id::String)
    task = get_planning_task(planning_id)
    task === nothing && error("规划任务不存在: $(planning_id)")
    task["status"] == "draft" || error("只有 draft 状态可以启动，当前为 $(task["status"])")
    set_planning_status!(planning_id, "queued")
    ctx = PlanningContext(Channel{Symbol}(1), nothing)
    lock(PLANNING_CONTEXTS_LOCK) do
        PLANNING_CONTEXTS[planning_id] = ctx
    end
    # COPT 求解是阻塞调用，放到 Julia worker thread，避免占住 Oxygen 的 HTTP 事件循环。
    worker = Threads.@spawn begin
        try
            run_capacity_optimization!(planning_id, ctx)
        catch error
            if error isa PlanningCancelled
                set_planning_status!(planning_id, "cancelled")
            else
                code = error isa CapacityPlanningError ? error.code : "PLANNING_FAILED"
                message = error isa CapacityPlanningError ? error.message : sprint(showerror, error)
                set_planning_status!(planning_id, "failed"; error_code=code, error_message=message)
                @error "capacity planning failed" planning_id exception=(error, catch_backtrace())
            end
        finally
            lock(PLANNING_CONTEXTS_LOCK) do
                pop!(PLANNING_CONTEXTS, planning_id, nothing)
            end
        end
    end
    ctx.julia_task = worker
    return get_planning_task(planning_id)
end

function cancel_capacity_planning!(planning_id::String)
    task = get_planning_task(planning_id)
    task === nothing && error("规划任务不存在: $(planning_id)")
    task["status"] in PLANNING_TERMINAL_STATUSES && return task
    if task["status"] == "draft"
        set_planning_status!(planning_id, "cancelled")
        return get_planning_task(planning_id)
    end
    delivered = lock(PLANNING_CONTEXTS_LOCK) do
        ctx = get(PLANNING_CONTEXTS, planning_id, nothing)
        ctx === nothing && return false
        isready(ctx.signal_ch) || put!(ctx.signal_ch, :cancel)
        return true
    end
    delivered || set_planning_status!(planning_id, "cancelled")
    return get_planning_task(planning_id)
end

function reconcile_planning_tasks!()
    db = get_planning_store()
    timestamp = _planning_now()
    lock(PLANNING_STORE_LOCK) do
        _exec(db, """
            UPDATE planning_tasks
            SET status='failed', error_code='BACKEND_RESTARTED',
                error_message='后端重启导致规划中断，请新建规划任务重试',
                finished_at=?, updated_at=?
            WHERE status IN ('queued', 'validating', 'clustering', 'optimizing')
        """, (timestamp, timestamp))
    end
    return nothing
end
