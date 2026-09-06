using JSON3

function _evaluation_failure(error; scenario_metrics=Dict{String,Any}[])
    code = error isa CapacityPlanningError ? error.code : "SIMULATION_ERROR"
    message = error isa CapacityPlanningError ? error.message : sprint(showerror, error)
    return EvaluationResult(
        feasible=false,
        operating_objective=0.0,
        metrics=Dict{String,Float64}(),
        scenario_metrics=scenario_metrics,
        error_code=code,
        error_message=message,
    )
end

function _planning_layer(project_snapshot::AbstractDict, layer_id::String)
    layer_config = get(project_snapshot, "layerConfig", nothing)
    layer_config isa AbstractDict || throw(CapacityPlanningError("LAYER_CONFIG_MISSING", "项目缺少 layerConfig"))
    layers = get(layer_config, "layers", nothing)
    layers isa AbstractVector || throw(CapacityPlanningError("LAYER_CONFIG_MISSING", "项目缺少层级列表"))
    index = findfirst(layer -> string(get(layer, "id", "")) == layer_id, layers)
    index === nothing && throw(CapacityPlanningError("LAYER_NOT_FOUND", "项目中不存在层级 $(layer_id)"))
    layer = Dict{String,Any}(string(key) => value for (key, value) in layers[index])
    time_str_to_minutes(string(get(layer, "length", ""))) == 1440 || throw(CapacityPlanningError(
        "PLANNING_LAYER_NOT_DAILY", "典型场景评价要求层级 $(layer_id) 的 length 为 24h",
    ))
    return layer
end

function _validate_storage_cycle!(component_dicts::Vector, layer_id::String)
    storage_types = Set(["ES", "HS", "FS", "CS", "PS"])
    for component in component_dicts
        string(get(component, "type", "")) in storage_types || continue
        layer = get(get(component, "layer", Dict()), layer_id, nothing)
        layer isa AbstractDict || continue
        status = string(get(layer, "status", "disabled"))
        status == "disabled" && continue
        constraints = get(layer, "constraints", Dict())
        get(constraints, "start_end_equality_constraint_on", false) == true || throw(CapacityPlanningError(
            "STORAGE_CYCLE_REQUIRED",
            "典型场景评价要求储能组件 $(get(component, "name", component["type"])) 在层级 $(layer_id) 启用首末状态相等约束",
        ))
    end
    return nothing
end

function _scenario_series_metadata(scenario_set::AbstractDict)
    dataset = get(scenario_set, "dataset", nothing)
    dataset isa AbstractDict || throw(CapacityPlanningError("SCENARIO_DATASET_MISSING", "场景集缺少 dataset 元数据"))
    series = get(dataset, "series", nothing)
    series isa AbstractVector || throw(CapacityPlanningError("SCENARIO_DATASET_MISSING", "场景集缺少边界序列元数据"))
    return Dict(string(get(item, "boundaryId", "")) => item for item in series)
end

function _seed_evaluation_scenario!(db_path::String, layer_id::String, scenario, scenario_set, metadata; planning_id::Union{Nothing,String}=nothing)
    config = get(scenario_set, "config", Dict())
    resolution = Int(get(config, "resolutionMinutes", 0))
    resolution > 0 || throw(CapacityPlanningError("INVALID_SCENARIO_RESOLUTION", "场景分辨率必须大于 0"))
    1440 % resolution == 0 || throw(CapacityPlanningError("INVALID_SCENARIO_RESOLUTION", "场景分辨率必须整除 1440"))
    expected_points = 1440 ÷ resolution
    timestamps = [minutes_to_time_label((index - 1) * resolution) for index in 1:expected_points]
    scenario_id = string(get(scenario, "scenarioId", ""))

    # 确定数据来源：优先从数据库读取，否则从 scenario 的 series 字段读取
    series_data = Dict{String,Vector{Float64}}()
    if planning_id !== nothing && !isempty(scenario_id)
        # 从数据库读取场景时序数据
        db_series = get_scenario_set_series(planning_id)
        if haskey(db_series, scenario_id)
            series_data = db_series[scenario_id]
        end
    end

    if isempty(series_data)
        # 回退：从 scenario 的 series 字段读取（向后兼容）
        series = get(scenario, "series", nothing)
        series isa AbstractDict || throw(CapacityPlanningError("SCENARIO_SERIES_MISSING", "典型场景缺少 series"))
        for (boundary_id_raw, values_raw) in series
            boundary_id = string(boundary_id_raw)
            values_raw isa AbstractVector || continue
            series_data[boundary_id] = Float64.(values_raw)
        end
    end

    isempty(series_data) && throw(CapacityPlanningError("SCENARIO_SERIES_MISSING", "典型场景缺少时序数据"))

    for (boundary_id, values) in series_data
        item = get(metadata, boundary_id, nothing)
        item === nothing && throw(CapacityPlanningError("SCENARIO_FEATURE_UNKNOWN", "场景包含未知边界 $(boundary_id)"))
        length(values) == expected_points || throw(CapacityPlanningError(
            "INVALID_SCENARIO_SERIES", "$(boundary_id) 应有 $(expected_points) 个点，实际为 $(length(values))",
        ))
        all(isfinite, values) || throw(CapacityPlanningError("INVALID_SCENARIO_SERIES", "$(boundary_id) 含非有限数值"))
        meaning = strip(string(get(item, "meaning", "")))
        isempty(meaning) && throw(CapacityPlanningError("SCENARIO_MEANING_MISSING", "边界 $(boundary_id) 缺少 meaning"))
        set_ts(db_path, "$(boundary_id)|$(meaning)|planned#$(layer_id)", TimeSeries(timestamps, values))
    end
    return nothing
end

"""
    evaluate_snapshot(project_snapshot, canvas_id, scenario_set, work_dir; options, planning_id)

在进程内对典型场景逐一运行真实 JuMP/COPT 模型。该函数不创建普通 task、不更新 tasks.db、
默认不落组件结果和回溯，只返回按 `weightDays` 加权的运行目标及场景明细。

当提供 planning_id 时，从数据库读取场景时序数据；否则从 scenario_set 的 scenarios[].series 读取。
"""
function evaluate_snapshot(
    project_snapshot::AbstractDict,
    canvas_id::String,
    scenario_set::AbstractDict,
    work_dir::String;
    options::EvaluationOptions=EvaluationOptions(),
    planning_id::Union{Nothing,String}=nothing,
)::EvaluationResult
    scenario_metrics = Dict{String,Any}[]
    try
        snapshot = deepcopy(project_snapshot)
        workspace, _ = _candidate_canvas(snapshot, canvas_id)
        workspace["activeCanvasId"] = canvas_id
        mkpath(work_dir)

        parse_result = parse_project(snapshot; output_dir=work_dir)
        parse_result.success || throw(CapacityPlanningError("PARSE_FAILED", parse_result.message))
        component_dicts = JSON3.read(read(joinpath(work_dir, "component.json"), String), Vector{Dict{String,Any}})
        connections = JSON3.read(read(joinpath(work_dir, "connection.json"), String), Vector{Dict{String,Any}})
        algorithms = Dict{String,Any}(string(key) => value for (key, value) in get(snapshot, "algorithm", Dict()))
        layer = _planning_layer(snapshot, options.layer_id)
        _validate_storage_cycle!(component_dicts, options.layer_id)
        all_layers = Dict{String,Any}(string(item["id"]) => item for item in snapshot["layerConfig"]["layers"])
        nodes = build_nodes_from_connections(connections)
        metadata = _scenario_series_metadata(scenario_set)
        scenarios = get(scenario_set, "scenarios", nothing)
        scenarios isa AbstractVector && !isempty(scenarios) || throw(CapacityPlanningError("SCENARIOS_MISSING", "场景集不能为空"))

        weighted_objective = 0.0
        total_weight_days = 0
        for scenario in scenarios
            scenario_id = string(get(scenario, "scenarioId", ""))
            isempty(scenario_id) && throw(CapacityPlanningError("SCENARIO_ID_MISSING", "典型场景缺少 scenarioId"))
            weight_days = Int(get(scenario, "weightDays", 0))
            weight_days > 0 || throw(CapacityPlanningError("INVALID_SCENARIO_WEIGHT", "$(scenario_id) 的 weightDays 必须大于 0"))
            scenario_dir = joinpath(work_dir, "scenarios", scenario_id)
            mkpath(scenario_dir)
            db_path = joinpath(scenario_dir, "timeseries.db")
            try
                _seed_evaluation_scenario!(db_path, options.layer_id, scenario, scenario_set, metadata; planning_id)
                # 当前生产模型实现以 tracked builder 为真源；规划只复用其数学模型，
                # 默认丢弃生成的代码文本，不向候选目录写 .jl 文件。
                model, components, generated_code = build_model_tracked(
                    component_dicts, algorithms, nodes, layer, "0:00", db_path; all_layers,
                )
                if options.generate_code
                    write(joinpath(scenario_dir, "model.jl"), generated_code)
                end
                solve_result = solve_model(
                    model, components, layer, "0:00", db_path;
                    overlay_mode=false,
                    persist_results=options.persist_timeseries,
                )
                solve_result === nothing && throw(CapacityPlanningError("INFEASIBLE", "$(scenario_id) 求解未达到最优"))
                objective, _ = solve_result
                isfinite(objective) || throw(CapacityPlanningError("NON_FINITE_OBJECTIVE", "$(scenario_id) 返回非有限目标值"))
                weighted_objective += objective * weight_days
                total_weight_days += weight_days
                push!(scenario_metrics, Dict{String,Any}(
                    "scenarioId" => scenario_id,
                    "representativeDate" => string(get(scenario, "representativeDate", "")),
                    "weightDays" => weight_days,
                    "operatingObjective" => objective,
                    "weightedOperatingObjective" => objective * weight_days,
                    "feasible" => true,
                ))
            catch error
                push!(scenario_metrics, Dict{String,Any}(
                    "scenarioId" => scenario_id,
                    "weightDays" => weight_days,
                    "feasible" => false,
                    "error" => sprint(showerror, error),
                ))
                options.stop_on_infeasible && return _evaluation_failure(error; scenario_metrics)
            finally
                close_store(db_path)
                if !options.persist_timeseries && isdir(scenario_dir)
                    rm(scenario_dir; recursive=true, force=true)
                end
            end
        end

        return EvaluationResult(
            feasible=true,
            operating_objective=weighted_objective,
            metrics=Dict(
                "weightedOperatingObjective" => weighted_objective,
                "totalWeightDays" => Float64(total_weight_days),
                "scenarioCount" => Float64(length(scenario_metrics)),
            ),
            scenario_metrics=scenario_metrics,
        )
    catch error
        return _evaluation_failure(error; scenario_metrics)
    end
end
