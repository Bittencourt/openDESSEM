"""
    Solution Exporter

Export functions for OpenDESSEM optimization results.

Supports multiple export formats:
- CSV: Spreadsheet-compatible format for analysis
- JSON: Structured format for web applications and APIs
- Database: PostgreSQL storage for historical results

# Example
```julia
using OpenDESSEM.Analysis

# Export to CSV
export_csv(result, "results/"; time_periods=1:24)

# Export to JSON
export_json(result, "results/solution.json"; time_periods=1:24)

# Export to database
export_database(result, db_conn; scenario_id="SCENARIO_001")
```
"""

module SolutionExporter

using ..Solvers: SolverResult
using Dates
using CSV
using DataFrames
using JSON3

"""
    ExportResult

Configuration and metadata for solution export.

# Fields
- `export_timestamp::DateTime`: When the export was created
- `scenario_id::String`: Scenario identifier (if applicable)
- `base_date::Date`: Base date for the optimization
- `time_periods::UnitRange{Int}`: Time period range included
- `export_path::String`: File path (for file-based exports)
- `metadata::Dict{String, Any}`: Additional metadata

# Example
```julia
export_config = ExportResult(;
    scenario_id="WEEK_01_2025",
    base_date=Date("2025-01-06"),
    time_periods=1:168,
    export_path="results/week01"
)
```
"""
Base.@kwdef struct ExportResult
    export_timestamp::DateTime = now()
    scenario_id::String = ""
    base_date::Date = Date(0)
    time_periods::UnitRange{Int} = 1:24
    export_path::String = ""
    metadata::Dict{String,Any} = Dict{String,Any}()
end

"""
    export_csv(
        result::SolverResult,
        path::String;
        time_periods::UnitRange{Int}=1:24,
        scenario_id::String="",
        base_date::Date=Date(0)
    )::Vector{String}

Export solver results to CSV files.

Creates multiple CSV files in the specified directory:
- `thermal_generation.csv`: Thermal plant dispatch (MW)
- `thermal_commitment.csv`: Thermal plant commitment status (0/1)
- `hydro_generation.csv`: Hydro plant generation (MW)
- `hydro_storage.csv`: Hydro reservoir storage (hm³)
- `hydro_outflow.csv`: Hydro plant outflow (m³/s)
- `renewable_generation.csv`: Renewable plant generation (MW)
- `renewable_curtailment.csv`: Renewable curtailment (MW)
- `submarket_lmps.csv`: Locational marginal prices (R\$/MWh)
- `summary.csv`: Solution summary statistics

# Arguments
- `result::SolverResult`: Solver result with variable values
- `path::String`: Directory path for CSV files (created if doesn't exist)
- `time_periods::UnitRange{Int}`: Time periods to export (default 1:24)
- `scenario_id::String`: Scenario identifier for metadata
- `base_date::Date`: Base date for the optimization

# Returns
- `Vector{String}`: List of created file paths

# Example
```julia
files = export_csv(
    result,
    "results/scenario_01/";
    time_periods=1:168,
    scenario_id="SCENARIO_01",
    base_date=Date("2025-01-06")
)
println("Created $(length(files)) CSV files")
```

# Throws
- `Error` if path cannot be created
- `Error` if result does not have variable values
"""
function export_csv(
    result::SolverResult,
    path::String;
    time_periods::UnitRange{Int}=1:24,
    scenario_id::String="",
    base_date::Date=Date(0),
)::Vector{String}
    # Validate input
    if !result.has_values
        error("Result does not have variable values. Call extract_solution_values! first.")
    end

    # Create directory if it doesn't exist
    mkpath(path)

    created_files = String[]

    # Export thermal generation
    if haskey(result.variables, :thermal_generation)
        df = _create_thermal_generation_df(result, time_periods)
        filepath = joinpath(path, "thermal_generation.csv")
        CSV.write(filepath, df)
        push!(created_files, filepath)
    end

    # Export thermal commitment
    if haskey(result.variables, :thermal_commitment)
        df = _create_thermal_commitment_df(result, time_periods)
        filepath = joinpath(path, "thermal_commitment.csv")
        CSV.write(filepath, df)
        push!(created_files, filepath)
    end

    # Export hydro generation
    if haskey(result.variables, :hydro_generation)
        df = _create_hydro_generation_df(result, time_periods)
        filepath = joinpath(path, "hydro_generation.csv")
        CSV.write(filepath, df)
        push!(created_files, filepath)
    end

    # Export hydro storage
    if haskey(result.variables, :hydro_storage)
        df = _create_hydro_storage_df(result, time_periods)
        filepath = joinpath(path, "hydro_storage.csv")
        CSV.write(filepath, df)
        push!(created_files, filepath)
    end

    # Export hydro outflow
    if haskey(result.variables, :hydro_outflow)
        df = _create_hydro_outflow_df(result, time_periods)
        filepath = joinpath(path, "hydro_outflow.csv")
        CSV.write(filepath, df)
        push!(created_files, filepath)
    end

    # Export renewable generation
    if haskey(result.variables, :renewable_generation)
        df = _create_renewable_generation_df(result, time_periods)
        filepath = joinpath(path, "renewable_generation.csv")
        CSV.write(filepath, df)
        push!(created_files, filepath)
    end

    # Export renewable curtailment
    if haskey(result.variables, :renewable_curtailment)
        df = _create_renewable_curtailment_df(result, time_periods)
        filepath = joinpath(path, "renewable_curtailment.csv")
        CSV.write(filepath, df)
        push!(created_files, filepath)
    end

    # Export submarket LMPs
    if haskey(result.dual_values, "submarket_balance")
        df = _create_submarket_lmp_df(result, time_periods)
        filepath = joinpath(path, "submarket_lmps.csv")
        CSV.write(filepath, df)
        push!(created_files, filepath)
    end

    # Export summary
    df_summary = _create_summary_df(result, time_periods, scenario_id, base_date)
    filepath_summary = joinpath(path, "summary.csv")
    CSV.write(filepath_summary, df_summary)
    push!(created_files, filepath_summary)

    return created_files
end

"""
    export_json(
        result::SolverResult,
        filepath::String;
        time_periods::UnitRange{Int}=1:24,
        scenario_id::String="",
        base_date::Date=Date(0),
        pretty::Bool=true
    )::String

Export solver results to JSON format.

Creates a structured JSON file containing:
- Solution metadata (objective, status, solve time)
- Variable values (thermal, hydro, renewable)
- Dual values (LMPs)
- System statistics

# Arguments
- `result::SolverResult`: Solver result with variable values
- `filepath::String`: Output file path (.json)
- `time_periods::UnitRange{Int}`: Time periods to export (default 1:24)
- `scenario_id::String`: Scenario identifier for metadata
- `base_date::Date`: Base date for the optimization
- `pretty::Bool`: Format JSON with indentation (default true)

# Returns
- `String`: Absolute path to created file

# Example
```julia
filepath = export_json(
    result,
    "results/scenario_01/solution.json";
    time_periods=1:168,
    scenario_id="SCENARIO_01",
    base_date=Date("2025-01-06"),
    pretty=true
)
println("Exported to: ", filepath)
```

# JSON Structure
```json
{
  "metadata": {
    "export_timestamp": "2025-01-06T12:00:00",
    "scenario_id": "SCENARIO_01",
    "base_date": "2025-01-06",
    "time_periods": [1, 168],
    "solve_time_seconds": 45.2
  },
  "solution": {
    "status": "OPTIMAL",
    "objective_value": 1234567.89,
    "variables": {...},
    "dual_values": {...}
  }
}
```
"""
function export_json(
    result::SolverResult,
    filepath::String;
    time_periods::UnitRange{Int}=1:24,
    scenario_id::String="",
    base_date::Date=Date(0),
    pretty::Bool=true,
)::String
    # Validate input
    if !result.has_values
        error("Result does not have variable values. Call extract_solution_values! first.")
    end

    # Build JSON structure
    json_data = Dict{String,Any}()

    # Metadata
    json_data["metadata"] = Dict{String,Any}(
        "export_timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "scenario_id" => scenario_id,
        "base_date" => Dates.format(base_date, "yyyy-mm-dd"),
        "time_periods" => Dict(
            "start" => first(time_periods),
            "end" => last(time_periods),
            "count" => length(time_periods)
        ),
        "solve_time_seconds" => result.solve_time_seconds
    )

    # Solution info
    json_data["solution"] = Dict{String,Any}(
        "status" => string(result.status),
        "objective_value" => result.objective_value,
        "objective_bound" => result.objective_bound,
        "node_count" => result.node_count
    )

    # Variables
    json_data["variables"] = _convert_variables_to_dict(result, time_periods)

    # Dual values
    if result.has_duals
        json_data["dual_values"] = _convert_duals_to_dict(result, time_periods)
    end

    # Statistics
    json_data["statistics"] = _calculate_statistics(result, time_periods)

    # Create directory if needed
    mkpath(dirname(filepath))

    # Write JSON file
    if pretty
        open(filepath, "w") do io
            JSON3.write(io, json_data)
        end
        # Re-format with pretty printing
        content = read(filepath, String)
        pretty_content = JSON3.pretty(content)
        write(filepath, pretty_content)
    else
        open(filepath, "w") do io
            JSON3.write(io, json_data)
        end
    end

    return abspath(filepath)
end

"""
    export_database(
        result::SolverResult,
        conn;
        time_periods::UnitRange{Int}=1:24,
        scenario_id::String="",
        base_date::Date=Date(0),
        schema::String="public",
        overwrite::Bool=false
    )::Dict{String,Int}

Export solver results to PostgreSQL database.

Creates tables in the specified schema:
- `solution_metadata`: Solution summary information
- `thermal_generation`: Thermal plant dispatch results
- `thermal_commitment`: Thermal plant commitment status
- `hydro_generation`: Hydro plant generation results
- `hydro_storage`: Hydro reservoir storage trajectory
- `renewable_generation`: Renewable plant generation results
- `submarket_lmps`: Locational marginal prices

# Arguments
- `result::SolverResult`: Solver result with variable values
- `conn`: Database connection (LibPQ.Connection)
- `time_periods::UnitRange{Int}`: Time periods to export (default 1:24)
- `scenario_id::String`: Scenario identifier (required)
- `base_date::Date`: Base date for the optimization
- `schema::String`: Database schema (default "public")
- `overwrite::Bool`: Drop and recreate tables (default false)

# Returns
- `Dict{String,Int}`: Number of rows inserted per table

# Example
```julia
using LibPQ

conn = LibPQ.Connection("dbname=dessem user=postgres")

row_counts = export_database(
    result,
    conn;
    time_periods=1:168,
    scenario_id="SCENARIO_01",
    base_date=Date("2025-01-06"),
    overwrite=false
)

println("Inserted ", sum(values(row_counts)), " rows total")
```

# Throws
- `Error` if scenario_id is empty
- `Error` if database connection fails
- `Error` if tables cannot be created
"""
function export_database(
    result::SolverResult,
    conn;
    time_periods::UnitRange{Int}=1:24,
    scenario_id::String="",
    base_date::Date=Date(0),
    schema::String="public",
    overwrite::Bool=false,
)::Dict{String,Int}
    # Validate input
    if !result.has_values
        error("Result does not have variable values. Call extract_solution_values! first.")
    end

    if isempty(scenario_id)
        error("scenario_id is required for database export")
    end

    # This is a placeholder implementation
    # Actual implementation requires LibPQ package and SQL execution
    @warn "Database export not yet fully implemented. Requires LibPQ package."

    # TODO: Implement when LibPQ is added as dependency
    # 1. Create tables if not exist
    # 2. Insert metadata
    # 3. Insert variable values
    # 4. Insert dual values
    # 5. Return row counts

    return Dict{String,Int}()
end

# ============================================================================
# Internal helper functions
# ============================================================================

function _create_thermal_generation_df(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::DataFrame
    data = result.variables[:thermal_generation]

    # Get unique plant IDs
    plant_ids = unique([key[1] for key in keys(data)])

    # Build dataframe
    rows = []
    for plant_id in plant_ids
        row = Dict{String,Any}("plant_id" => plant_id)
        for t in time_periods
            key = (plant_id, t)
            row["t_$t"] = get(data, key, 0.0)
        end
        push!(rows, row)
    end

    return DataFrame(rows)
end

function _create_thermal_commitment_df(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::DataFrame
    data = result.variables[:thermal_commitment]

    plant_ids = unique([key[1] for key in keys(data)])

    rows = []
    for plant_id in plant_ids
        row = Dict{String,Any}("plant_id" => plant_id)
        for t in time_periods
            key = (plant_id, t)
            row["t_$t"] = get(data, key, 0.0)
        end
        push!(rows, row)
    end

    return DataFrame(rows)
end

function _create_hydro_generation_df(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::DataFrame
    data = result.variables[:hydro_generation]

    plant_ids = unique([key[1] for key in keys(data)])

    rows = []
    for plant_id in plant_ids
        row = Dict{String,Any}("plant_id" => plant_id)
        for t in time_periods
            key = (plant_id, t)
            row["t_$t"] = get(data, key, 0.0)
        end
        push!(rows, row)
    end

    return DataFrame(rows)
end

function _create_hydro_storage_df(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::DataFrame
    data = result.variables[:hydro_storage]

    plant_ids = unique([key[1] for key in keys(data)])

    rows = []
    for plant_id in plant_ids
        row = Dict{String,Any}("plant_id" => plant_id)
        for t in time_periods
            key = (plant_id, t)
            row["t_$t"] = get(data, key, 0.0)
        end
        push!(rows, row)
    end

    return DataFrame(rows)
end

function _create_hydro_outflow_df(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::DataFrame
    data = result.variables[:hydro_outflow]

    plant_ids = unique([key[1] for key in keys(data)])

    rows = []
    for plant_id in plant_ids
        row = Dict{String,Any}("plant_id" => plant_id)
        for t in time_periods
            key = (plant_id, t)
            row["t_$t"] = get(data, key, 0.0)
        end
        push!(rows, row)
    end

    return DataFrame(rows)
end

function _create_renewable_generation_df(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::DataFrame
    data = result.variables[:renewable_generation]

    plant_ids = unique([key[1] for key in keys(data)])

    rows = []
    for plant_id in plant_ids
        row = Dict{String,Any}("plant_id" => plant_id)
        for t in time_periods
            key = (plant_id, t)
            row["t_$t"] = get(data, key, 0.0)
        end
        push!(rows, row)
    end

    return DataFrame(rows)
end

function _create_renewable_curtailment_df(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::DataFrame
    data = result.variables[:renewable_curtailment]

    plant_ids = unique([key[1] for key in keys(data)])

    rows = []
    for plant_id in plant_ids
        row = Dict{String,Any}("plant_id" => plant_id)
        for t in time_periods
            key = (plant_id, t)
            row["t_$t"] = get(data, key, 0.0)
        end
        push!(rows, row)
    end

    return DataFrame(rows)
end

function _create_submarket_lmp_df(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::DataFrame
    data = result.dual_values["submarket_balance"]

    submarket_ids = unique([key[1] for key in keys(data)])

    rows = []
    for submarket_id in submarket_ids
        row = Dict{String,Any}("submarket_id" => submarket_id)
        for t in time_periods
            key = (submarket_id, t)
            row["t_$t"] = get(data, key, 0.0)
        end
        push!(rows, row)
    end

    return DataFrame(rows)
end

function _create_summary_df(
    result::SolverResult,
    time_periods::UnitRange{Int},
    scenario_id::String,
    base_date::Date
)::DataFrame
    rows = [
        Dict(
            "metric" => "scenario_id",
            "value" => scenario_id
        ),
        Dict(
            "metric" => "base_date",
            "value" => string(base_date)
        ),
        Dict(
            "metric" => "time_period_start",
            "value" => first(time_periods)
        ),
        Dict(
            "metric" => "time_period_end",
            "value" => last(time_periods)
        ),
        Dict(
            "metric" => "status",
            "value" => string(result.status)
        ),
        Dict(
            "metric" => "objective_value",
            "value" => coalesce(result.objective_value, 0.0)
        ),
        Dict(
            "metric" => "solve_time_seconds",
            "value" => result.solve_time_seconds
        ),
        Dict(
            "metric" => "has_variable_values",
            "value" => result.has_values
        ),
        Dict(
            "metric" => "has_dual_values",
            "value" => result.has_duals
        ),
    ]

    return DataFrame(rows)
end

function _convert_variables_to_dict(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::Dict{String,Any}
    vars = Dict{String,Any}()

    # Thermal generation
    if haskey(result.variables, :thermal_generation)
        vars["thermal_generation"] = _dict_to_nested(result.variables[:thermal_generation], time_periods)
    end

    # Thermal commitment
    if haskey(result.variables, :thermal_commitment)
        vars["thermal_commitment"] = _dict_to_nested(result.variables[:thermal_commitment], time_periods)
    end

    # Hydro generation
    if haskey(result.variables, :hydro_generation)
        vars["hydro_generation"] = _dict_to_nested(result.variables[:hydro_generation], time_periods)
    end

    # Hydro storage
    if haskey(result.variables, :hydro_storage)
        vars["hydro_storage"] = _dict_to_nested(result.variables[:hydro_storage], time_periods)
    end

    # Hydro outflow
    if haskey(result.variables, :hydro_outflow)
        vars["hydro_outflow"] = _dict_to_nested(result.variables[:hydro_outflow], time_periods)
    end

    # Renewable generation
    if haskey(result.variables, :renewable_generation)
        vars["renewable_generation"] = _dict_to_nested(result.variables[:renewable_generation], time_periods)
    end

    # Renewable curtailment
    if haskey(result.variables, :renewable_curtailment)
        vars["renewable_curtailment"] = _dict_to_nested(result.variables[:renewable_curtailment], time_periods)
    end

    return vars
end

function _convert_duals_to_dict(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::Dict{String,Any}
    duals = Dict{String,Any}()

    # Submarket LMPs
    if haskey(result.dual_values, "submarket_balance")
        duals["submarket_lmps"] = _dict_to_nested(result.dual_values["submarket_balance"], time_periods)
    end

    return duals
end

function _dict_to_nested(
    data::Dict{Tuple{String,Int},Float64},
    time_periods::UnitRange{Int}
)::Dict{String,Vector{Float64}}
    nested = Dict{String,Vector{Float64}}()

    # Initialize with all entity IDs
    for (entity_id, t) in keys(data)
        if !haskey(nested, entity_id)
            nested[entity_id] = Float64[]
        end
    end

    # Fill with time series data
    for entity_id in keys(nested)
        values_vec = Float64[]
        for t in time_periods
            key = (entity_id, t)
            val = get(data, key, 0.0)
            push!(values_vec, val)
        end
        nested[entity_id] = values_vec
    end

    return nested
end

function _calculate_statistics(
    result::SolverResult,
    time_periods::UnitRange{Int}
)::Dict{String,Any}
    stats = Dict{String,Any}()

    # Count plants
    if haskey(result.variables, :thermal_generation)
        thermal_plants = unique([k[1] for k in keys(result.variables[:thermal_generation])])
        stats["num_thermal_plants"] = length(thermal_plants)
    end

    if haskey(result.variables, :hydro_generation)
        hydro_plants = unique([k[1] for k in keys(result.variables[:hydro_generation])])
        stats["num_hydro_plants"] = length(hydro_plants)
    end

    if haskey(result.variables, :renewable_generation)
        renewable_plants = unique([k[1] for k in keys(result.variables[:renewable_generation])])
        stats["num_renewable_plants"] = length(renewable_plants)
    end

    # Calculate total generation by type
    if haskey(result.variables, :thermal_generation)
        total_thermal = sum(v for (k, v) in result.variables[:thermal_generation]
                           if k[2] in time_periods)
        stats["total_thermal_generation_mwh"] = total_thermal
    end

    if haskey(result.variables, :hydro_generation)
        total_hydro = sum(v for (k, v) in result.variables[:hydro_generation]
                         if k[2] in time_periods)
        stats["total_hydro_generation_mwh"] = total_hydro
    end

    if haskey(result.variables, :renewable_generation)
        total_renewable = sum(v for (k, v) in result.variables[:renewable_generation]
                             if k[2] in time_periods)
        stats["total_renewable_generation_mwh"] = total_renewable
    end

    # Calculate average LMP by submarket
    if haskey(result.dual_values, "submarket_balance")
        lmp_data = result.dual_values["submarket_balance"]
        submarkets = unique([k[1] for k in keys(lmp_data)])
        avg_lmps = Dict{String,Float64}()
        for sm in submarkets
            values = [v for (k, v) in lmp_data if k[1] == sm && k[2] in time_periods]
            if !isempty(values)
                avg_lmps[sm] = sum(values) / length(values)
            end
        end
        stats["average_lmp_by_submarket"] = avg_lmps
    end

    return stats
end

# Export public functions
export export_csv, export_json, export_database, ExportResult

end # module
