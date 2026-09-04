# flexibility_result_service.jl — 灵活性逐时段与汇总结果持久化

using JSON3

function _ensure_flexibility_result_tables!(store::SQLiteTimeSeriesStore)
    _exec(store.db, """
        CREATE TABLE IF NOT EXISTS flexibility_period_results (
            layer_id             TEXT NOT NULL,
            timestamp            TEXT NOT NULL,
            timestamp_minutes    INTEGER NOT NULL,
            next_timestamp       TEXT NOT NULL,
            case_id              TEXT NOT NULL,
            application_type     TEXT NOT NULL,
            operation_mode       TEXT NOT NULL,
            boundary_condition   TEXT NOT NULL,
            poi_id               TEXT NOT NULL,
            direction            TEXT NOT NULL,
            requirement_source   TEXT NOT NULL,
            result_json          TEXT NOT NULL,
            updated_at           TEXT DEFAULT (datetime('now')),
            PRIMARY KEY (
                layer_id, timestamp, case_id, application_type,
                operation_mode, boundary_condition, poi_id,
                direction, requirement_source
            )
        )
    """)
    _exec(
        store.db,
        "CREATE INDEX IF NOT EXISTS idx_flex_period_layer_time " *
        "ON flexibility_period_results(layer_id, timestamp_minutes)",
    )
    _exec(store.db, """
        CREATE TABLE IF NOT EXISTS flexibility_summary_results (
            layer_id             TEXT NOT NULL,
            start_timestamp      TEXT NOT NULL,
            start_minutes        INTEGER NOT NULL,
            end_timestamp        TEXT NOT NULL,
            case_id              TEXT NOT NULL,
            application_type     TEXT NOT NULL,
            operation_mode       TEXT NOT NULL,
            boundary_condition   TEXT NOT NULL,
            poi_id               TEXT NOT NULL,
            direction            TEXT NOT NULL,
            requirement_source   TEXT NOT NULL,
            result_json          TEXT NOT NULL,
            updated_at           TEXT DEFAULT (datetime('now')),
            PRIMARY KEY (
                layer_id, start_timestamp, end_timestamp, case_id,
                application_type, operation_mode, boundary_condition,
                poi_id, direction, requirement_source
            )
        )
    """)
    return nothing
end

function persist_system_flexibility_period_results!(
    db_path::String,
    layer_id::String,
    margins::AbstractVector,
)
    all(item -> item isa SystemFlexibilityMarginResult, margins) || throw(
        ArgumentError("margins must contain only SystemFlexibilityMarginResult values."),
    )
    isempty(margins) && return nothing
    store = get_store(db_path)
    lock(store.write_lock) do
        _ensure_flexibility_result_tables!(store)
        _exec(store.db, "BEGIN IMMEDIATE")
        try
            for margin in margins
                supply = margin.supply_result
                requirement = margin.requirement_result
                row = system_flexibility_margin_result_dict(margin)
                _exec(store.db, """
                    INSERT INTO flexibility_period_results (
                        layer_id, timestamp, timestamp_minutes, next_timestamp,
                        case_id, application_type, operation_mode,
                        boundary_condition, poi_id, direction,
                        requirement_source, result_json, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                    ON CONFLICT (
                        layer_id, timestamp, case_id, application_type,
                        operation_mode, boundary_condition, poi_id,
                        direction, requirement_source
                    ) DO UPDATE SET
                        timestamp_minutes=excluded.timestamp_minutes,
                        next_timestamp=excluded.next_timestamp,
                        result_json=excluded.result_json,
                        updated_at=datetime('now')
                """, [
                    layer_id,
                    supply.timestamp,
                    time_label_to_minutes(supply.timestamp),
                    requirement.next_timestamp,
                    supply.case_id,
                    supply.application_type,
                    supply.operation_mode,
                    supply.boundary_condition,
                    something(supply.poi_id, ""),
                    supply.direction,
                    requirement.requirement_source,
                    JSON3.write(row),
                ])
            end
            _exec(store.db, "COMMIT")
        catch error
            try
                _exec(store.db, "ROLLBACK")
            catch
            end
            rethrow(error)
        end
    end
    return nothing
end

function persist_system_flexibility_summary_results!(
    db_path::String,
    layer_id::String,
    summaries::AbstractVector,
)
    all(item -> item isa SystemFlexibilityMarginSummaryResult, summaries) || throw(
        ArgumentError(
            "summaries must contain only SystemFlexibilityMarginSummaryResult values.",
        ),
    )
    store = get_store(db_path)
    lock(store.write_lock) do
        _ensure_flexibility_result_tables!(store)
        _exec(store.db, "BEGIN IMMEDIATE")
        try
            _exec(
                store.db,
                "DELETE FROM flexibility_summary_results WHERE layer_id=?",
                [layer_id],
            )
            for summary in summaries
                row = system_flexibility_margin_summary_result_dict(summary)
                _exec(store.db, """
                    INSERT INTO flexibility_summary_results (
                        layer_id, start_timestamp, start_minutes, end_timestamp,
                        case_id, application_type, operation_mode,
                        boundary_condition, poi_id, direction,
                        requirement_source, result_json, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                """, [
                    layer_id,
                    summary.start_timestamp,
                    time_label_to_minutes(summary.start_timestamp),
                    summary.end_timestamp,
                    summary.case_id,
                    summary.application_type,
                    summary.operation_mode,
                    summary.boundary_condition,
                    something(summary.poi_id, ""),
                    summary.direction,
                    summary.requirement_source,
                    JSON3.write(row),
                ])
            end
            _exec(store.db, "COMMIT")
        catch error
            try
                _exec(store.db, "ROLLBACK")
            catch
            end
            rethrow(error)
        end
    end
    return nothing
end

function _read_flexibility_json_rows(
    db_path::String,
    table_name::String;
    layer_id::Union{Nothing,String}=nothing,
)
    table_name in ("flexibility_period_results", "flexibility_summary_results") ||
        throw(ArgumentError("Unsupported flexibility result table."))
    store = get_store(db_path)
    return lock(store.write_lock) do
        _ensure_flexibility_result_tables!(store)
        where_sql = layer_id === nothing ? "" : " WHERE layer_id=?"
        params = layer_id === nothing ? Any[] : Any[layer_id]
        order_sql = table_name == "flexibility_period_results" ?
            " ORDER BY timestamp_minutes, CASE direction WHEN 'up' THEN 1 ELSE 2 END" :
            " ORDER BY start_minutes, CASE direction WHEN 'up' THEN 1 ELSE 2 END"
        rows = _query(
            store.db,
            "SELECT result_json FROM $(table_name)$(where_sql)$(order_sql)",
            params,
        )
        isempty(rows[1]) && return Dict{String,Any}[]
        return [
            JSON3.read(String(rows[1][index]), Dict{String,Any})
            for index in eachindex(rows[1])
        ]
    end
end

read_system_flexibility_period_results(
    db_path::String;
    layer_id::Union{Nothing,String}=nothing,
) = _read_flexibility_json_rows(
    db_path,
    "flexibility_period_results";
    layer_id=layer_id,
)

read_system_flexibility_summary_results(
    db_path::String;
    layer_id::Union{Nothing,String}=nothing,
) = _read_flexibility_json_rows(
    db_path,
    "flexibility_summary_results";
    layer_id=layer_id,
)
