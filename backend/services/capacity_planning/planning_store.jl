using DBInterface
using Dates
using JSON3
using SQLite
using Tables: columntable
using UUIDs: uuid4

const PLANNING_DB_PATH = joinpath(BACKEND_DATA_DIR, "capacity-planning.db")
const PLANNING_DATA_ROOT = joinpath(BACKEND_DATA_DIR, "capacity-planning")
const PLANNING_STORE_LOCK = ReentrantLock()
const PLANNING_STORE_REF = Ref{Union{Nothing,SQLite.DB}}(nothing)
const PLANNING_TERMINAL_STATUSES = Set(["completed", "failed", "cancelled"])

function planning_task_dir(planning_id::String)
    occursin(r"^cp-[0-9a-f-]+$", planning_id) || error("非法 planningId")
    return joinpath(PLANNING_DATA_ROOT, planning_id)
end

function get_planning_store()
    lock(PLANNING_STORE_LOCK) do
        if PLANNING_STORE_REF[] === nothing
            mkpath(dirname(PLANNING_DB_PATH))
            db = SQLite.DB(PLANNING_DB_PATH)
            _exec(db, "PRAGMA foreign_keys=ON")
            _exec(db, "PRAGMA journal_mode=WAL")
            _exec(db, """
                CREATE TABLE IF NOT EXISTS planning_tasks (
                    id                    TEXT PRIMARY KEY,
                    project_id            TEXT NOT NULL,
                    canvas_id             TEXT NOT NULL,
                    name                  TEXT,
                    status                TEXT NOT NULL,
                    project_updated_at    TEXT NOT NULL,
                    project_snapshot_hash TEXT NOT NULL,
                    scenario_set_hash     TEXT,
                    config_json           TEXT NOT NULL,
                    progress_json         TEXT NOT NULL,
                    best_evaluation_id    INTEGER,
                    created_at            TEXT NOT NULL,
                    updated_at            TEXT NOT NULL,
                    started_at            TEXT,
                    finished_at           TEXT,
                    error_code            TEXT,
                    error_message         TEXT
                )
            """)
            _exec(db, """
                CREATE TABLE IF NOT EXISTS planning_scenarios (
                    planning_id           TEXT NOT NULL REFERENCES planning_tasks(id) ON DELETE CASCADE,
                    scenario_id           TEXT NOT NULL,
                    representative_date   TEXT NOT NULL,
                    weight_days           INTEGER NOT NULL,
                    probability           REAL NOT NULL,
                    member_dates_json     TEXT NOT NULL,
                    metrics_json          TEXT NOT NULL,
                    PRIMARY KEY (planning_id, scenario_id)
                )
            """)
            _exec(db, """
                CREATE TABLE IF NOT EXISTS planning_evaluations (
                    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
                    planning_id           TEXT NOT NULL REFERENCES planning_tasks(id) ON DELETE CASCADE,
                    ordinal               INTEGER NOT NULL,
                    candidate_hash        TEXT NOT NULL,
                    candidate_json        TEXT NOT NULL,
                    feasible              INTEGER NOT NULL,
                    fitness               REAL NOT NULL,
                    breakdown_json        TEXT NOT NULL,
                    duration_ms           INTEGER NOT NULL,
                    error_code            TEXT,
                    error_message         TEXT,
                    created_at            TEXT NOT NULL,
                    UNIQUE (planning_id, candidate_hash),
                    UNIQUE (planning_id, ordinal)
                )
            """)
            _exec(db, """
                CREATE TABLE IF NOT EXISTS planning_results (
                    planning_id           TEXT PRIMARY KEY REFERENCES planning_tasks(id) ON DELETE CASCADE,
                    result_json           TEXT NOT NULL,
                    created_at            TEXT NOT NULL
                )
            """)
            _exec(db, "CREATE INDEX IF NOT EXISTS idx_planning_tasks_project ON planning_tasks(project_id, created_at)")
            _exec(db, "CREATE INDEX IF NOT EXISTS idx_planning_tasks_status ON planning_tasks(status)")
            _exec(db, "CREATE INDEX IF NOT EXISTS idx_planning_evaluations_task ON planning_evaluations(planning_id, ordinal)")
            PLANNING_STORE_REF[] = db
        end
        return PLANNING_STORE_REF[]::SQLite.DB
    end
end

_planning_now() = Dates.format(now(), dateformat"yyyy-mm-ddTHH:MM:SS.s")

function _planning_optional(value)
    return ismissing(value) || value === nothing ? nothing : value
end

function _planning_task_record(rows, index::Int)
    return Dict{String,Any}(
        "id" => String(rows.id[index]),
        "projectId" => String(rows.project_id[index]),
        "canvasId" => String(rows.canvas_id[index]),
        "name" => _planning_optional(rows.name[index]),
        "status" => String(rows.status[index]),
        "projectUpdatedAt" => String(rows.project_updated_at[index]),
        "projectSnapshotHash" => String(rows.project_snapshot_hash[index]),
        "scenarioSetHash" => _planning_optional(rows.scenario_set_hash[index]),
        "config" => JSON3.read(String(rows.config_json[index]), Dict{String,Any}),
        "progress" => JSON3.read(String(rows.progress_json[index]), Dict{String,Any}),
        "bestEvaluationId" => _planning_optional(rows.best_evaluation_id[index]),
        "createdAt" => String(rows.created_at[index]),
        "updatedAt" => String(rows.updated_at[index]),
        "startedAt" => _planning_optional(rows.started_at[index]),
        "finishedAt" => _planning_optional(rows.finished_at[index]),
        "errorCode" => _planning_optional(rows.error_code[index]),
        "errorMessage" => _planning_optional(rows.error_message[index]),
    )
end

const PLANNING_TASK_SELECT = """
    SELECT id, project_id, canvas_id, name, status, project_updated_at,
           project_snapshot_hash, scenario_set_hash, config_json, progress_json,
           best_evaluation_id, created_at, updated_at, started_at, finished_at,
           error_code, error_message
    FROM planning_tasks
"""

function create_planning_record!(; project_id, canvas_id, name, project_updated_at, snapshot_hash, config)
    planning_id = "cp-$(uuid4())"
    timestamp = _planning_now()
    progress = Dict(
        "phase" => "draft",
        "completedEvaluations" => 0,
        "failedEvaluations" => 0,
        "bestFitness" => nothing,
        "bestCandidate" => nothing,
        "convergence" => Any[],
        "elapsedMs" => 0,
    )
    db = get_planning_store()
    lock(PLANNING_STORE_LOCK) do
        _exec(db, """
            INSERT INTO planning_tasks
                (id, project_id, canvas_id, name, status, project_updated_at,
                 project_snapshot_hash, config_json, progress_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, 'draft', ?, ?, ?, ?, ?, ?)
        """, (
            planning_id, project_id, canvas_id, isempty(name) ? missing : name,
            project_updated_at, snapshot_hash, JSON3.write(config), JSON3.write(progress),
            timestamp, timestamp,
        ))
    end
    return planning_id
end

function get_planning_task(planning_id::String)
    db = get_planning_store()
    return lock(PLANNING_STORE_LOCK) do
        rows = _query(db, PLANNING_TASK_SELECT * " WHERE id = ?", (planning_id,))
        isempty(rows.id) ? nothing : _planning_task_record(rows, 1)
    end
end

function list_planning_tasks(; project_id::Union{Nothing,String}=nothing)
    db = get_planning_store()
    return lock(PLANNING_STORE_LOCK) do
        rows = project_id === nothing ?
            _query(db, PLANNING_TASK_SELECT * " ORDER BY created_at DESC") :
            _query(db, PLANNING_TASK_SELECT * " WHERE project_id = ? ORDER BY created_at DESC", (project_id,))
        isempty(rows.id) ? Dict{String,Any}[] : [_planning_task_record(rows, index) for index in eachindex(rows.id)]
    end
end

function set_planning_status!(planning_id::String, status::String; error_code=nothing, error_message=nothing)
    timestamp = _planning_now()
    started_at = status == "validating" ? timestamp : nothing
    finished_at = status in PLANNING_TERMINAL_STATUSES ? timestamp : nothing
    db = get_planning_store()
    lock(PLANNING_STORE_LOCK) do
        _exec(db, """
            UPDATE planning_tasks
            SET status=?, updated_at=?,
                started_at=COALESCE(started_at, ?),
                finished_at=COALESCE(?, finished_at),
                error_code=?, error_message=?
            WHERE id=?
        """, (
            status, timestamp, started_at === nothing ? missing : started_at,
            finished_at === nothing ? missing : finished_at,
            error_code === nothing ? missing : error_code,
            error_message === nothing ? missing : error_message,
            planning_id,
        ))
    end
    return nothing
end

function update_planning_config!(planning_id::String, config)
    db = get_planning_store()
    lock(PLANNING_STORE_LOCK) do
        _exec(db, "UPDATE planning_tasks SET config_json=?, updated_at=? WHERE id=?",
            (JSON3.write(config), _planning_now(), planning_id))
    end
end

function update_planning_progress!(planning_id::String, progress)
    db = get_planning_store()
    lock(PLANNING_STORE_LOCK) do
        _exec(db, "UPDATE planning_tasks SET progress_json=?, updated_at=? WHERE id=?",
            (JSON3.write(progress), _planning_now(), planning_id))
    end
end

function save_planning_scenarios!(planning_id::String, scenario_set)
    db = get_planning_store()
    lock(PLANNING_STORE_LOCK) do
        _exec(db, "BEGIN IMMEDIATE")
        try
            _exec(db, "DELETE FROM planning_scenarios WHERE planning_id=?", (planning_id,))
            for scenario in scenario_set["scenarios"]
                _exec(db, """
                    INSERT INTO planning_scenarios
                        (planning_id, scenario_id, representative_date, weight_days,
                         probability, member_dates_json, metrics_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (
                    planning_id, scenario["scenarioId"], scenario["representativeDate"],
                    scenario["weightDays"], scenario["probability"],
                    JSON3.write(scenario["memberDates"]),
                    JSON3.write(Dict("distanceToCenter" => scenario["distanceToCenter"])),
                ))
            end
            _exec(db, "UPDATE planning_tasks SET scenario_set_hash=?, updated_at=? WHERE id=?",
                (scenario_set["scenarioSetHash"], _planning_now(), planning_id))
            _exec(db, "COMMIT")
        catch
            try _exec(db, "ROLLBACK") catch end
            rethrow()
        end
    end
end

function cached_planning_evaluation(planning_id::String, candidate_hash::String)
    db = get_planning_store()
    return lock(PLANNING_STORE_LOCK) do
        rows = _query(db, """
            SELECT id, ordinal, candidate_json, feasible, fitness, breakdown_json,
                   duration_ms, error_code, error_message, created_at
            FROM planning_evaluations WHERE planning_id=? AND candidate_hash=?
        """, (planning_id, candidate_hash))
        isempty(rows.id) && return nothing
        return Dict{String,Any}(
            "id" => Int(rows.id[1]),
            "ordinal" => Int(rows.ordinal[1]),
            "candidate" => JSON3.read(String(rows.candidate_json[1]), Dict{String,Any}),
            "feasible" => Int(rows.feasible[1]) == 1,
            "fitness" => Float64(rows.fitness[1]),
            "breakdown" => JSON3.read(String(rows.breakdown_json[1]), Dict{String,Any}),
            "durationMs" => Int(rows.duration_ms[1]),
            "errorCode" => _planning_optional(rows.error_code[1]),
            "errorMessage" => _planning_optional(rows.error_message[1]),
            "createdAt" => String(rows.created_at[1]),
        )
    end
end

function insert_planning_evaluation!(;
    planning_id, ordinal, candidate_hash, candidate, feasible, fitness,
    breakdown, duration_ms, error_code=nothing, error_message=nothing,
)
    db = get_planning_store()
    return lock(PLANNING_STORE_LOCK) do
        _exec(db, """
            INSERT INTO planning_evaluations
                (planning_id, ordinal, candidate_hash, candidate_json, feasible,
                 fitness, breakdown_json, duration_ms, error_code, error_message, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            planning_id, ordinal, candidate_hash, JSON3.write(candidate), feasible ? 1 : 0,
            fitness, JSON3.write(breakdown), duration_ms,
            error_code === nothing ? missing : error_code,
            error_message === nothing ? missing : error_message,
            _planning_now(),
        ))
        rows = _query(db, "SELECT id FROM planning_evaluations WHERE planning_id=? AND ordinal=?", (planning_id, ordinal))
        return Int(rows.id[1])
    end
end

function set_best_planning_evaluation!(planning_id::String, evaluation_id::Int)
    db = get_planning_store()
    lock(PLANNING_STORE_LOCK) do
        _exec(db, "UPDATE planning_tasks SET best_evaluation_id=?, updated_at=? WHERE id=?",
            (evaluation_id, _planning_now(), planning_id))
    end
end

function list_planning_evaluations(planning_id::String)
    db = get_planning_store()
    return lock(PLANNING_STORE_LOCK) do
        rows = _query(db, """
            SELECT id, ordinal, candidate_hash, candidate_json, feasible, fitness,
                   breakdown_json, duration_ms, error_code, error_message, created_at
            FROM planning_evaluations WHERE planning_id=? ORDER BY ordinal
        """, (planning_id,))
        isempty(rows.id) && return Dict{String,Any}[]
        return [Dict{String,Any}(
            "id" => Int(rows.id[index]),
            "ordinal" => Int(rows.ordinal[index]),
            "candidateHash" => String(rows.candidate_hash[index]),
            "candidate" => JSON3.read(String(rows.candidate_json[index]), Dict{String,Any}),
            "feasible" => Int(rows.feasible[index]) == 1,
            "fitness" => Float64(rows.fitness[index]),
            "breakdown" => JSON3.read(String(rows.breakdown_json[index]), Dict{String,Any}),
            "durationMs" => Int(rows.duration_ms[index]),
            "errorCode" => _planning_optional(rows.error_code[index]),
            "errorMessage" => _planning_optional(rows.error_message[index]),
            "createdAt" => String(rows.created_at[index]),
        ) for index in eachindex(rows.id)]
    end
end

function save_planning_result!(planning_id::String, result)
    db = get_planning_store()
    lock(PLANNING_STORE_LOCK) do
        _exec(db, """
            INSERT INTO planning_results (planning_id, result_json, created_at)
            VALUES (?, ?, ?)
            ON CONFLICT(planning_id) DO UPDATE SET result_json=excluded.result_json, created_at=excluded.created_at
        """, (planning_id, JSON3.write(result), _planning_now()))
    end
end

function get_planning_result(planning_id::String)
    db = get_planning_store()
    return lock(PLANNING_STORE_LOCK) do
        rows = _query(db, "SELECT result_json FROM planning_results WHERE planning_id=?", (planning_id,))
        isempty(rows.result_json) ? nothing : JSON3.read(String(rows.result_json[1]), Dict{String,Any})
    end
end

function delete_planning_record!(planning_id::String)
    task = get_planning_task(planning_id)
    task === nothing && error("规划任务不存在: $(planning_id)")
    task["status"] in PLANNING_TERMINAL_STATUSES || error("只能删除已完成、失败或取消的规划任务")
    db = get_planning_store()
    lock(PLANNING_STORE_LOCK) do
        _exec(db, "DELETE FROM planning_tasks WHERE id=?", (planning_id,))
    end
    directory = planning_task_dir(planning_id)
    isdir(directory) && rm(directory; recursive=true, force=true)
    return nothing
end
