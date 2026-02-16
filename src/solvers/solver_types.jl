"""
    Solver Types for OpenDESSEM

Defines base types for the solver interface system.
Provides enumeration of supported solvers and configuration options.
"""

"""
    SolveStatus

User-friendly solver status enumeration.

Maps MathOptInterface status codes to simple, actionable values.

# Values
- `OPTIMAL`: Solution found and optimal
- `INFEASIBLE`: No feasible solution exists
- `UNBOUNDED`: Objective can improve infinitely
- `TIME_LIMIT`: Time limit reached with solution
- `ITERATION_LIMIT`: Iteration limit reached
- `NUMERICAL_ERROR`: Numerical issues encountered
- `OTHER_LIMIT`: Other limit (memory, nodes, etc.)
- `NOT_SOLVED`: Model not yet solved

# Example
```julia
result = solve_model!(model, system)
if result.solve_status == OPTIMAL
    println("Found optimal solution!")
elseif result.solve_status == INFEASIBLE
    println("Problem is infeasible - check constraints")
end
```
"""
@enum SolveStatus begin
    OPTIMAL           # Solution found and optimal
    INFEASIBLE        # No feasible solution exists
    UNBOUNDED         # Objective can improve infinitely
    TIME_LIMIT        # Time limit reached with solution
    ITERATION_LIMIT   # Iteration limit reached
    NUMERICAL_ERROR   # Numerical issues encountered
    OTHER_LIMIT       # Other limit (memory, nodes, etc.)
    NOT_SOLVED        # Model not yet solved
end

"""
    SolverType

Enumeration of supported solvers.

# Values
- `HIGHS`: Open-source HiGHS solver (default)
- `GUROBI`: Commercial Gurobi solver (optional)
- `CPLEX`: Commercial CPLEX solver (optional)
- `GLPK`: Open-source GLPK solver

# Example
```julia
solver = HIGHS
if solver == HIGHS
    optimizer = HiGHS.Optimizer
end
```
"""
@enum SolverType begin
    HIGHS
    GUROBI
    CPLEX
    GLPK
end

"""
    SolverOptions

Configuration options for optimization solvers.

# Fields
- `time_limit_seconds::Union{Float64, Nothing}`: Maximum solve time in seconds (nothing = unlimited)
- `mip_gap::Union{Float64, Nothing}`: MIP gap tolerance for mixed-integer problems (default 0.01 = 1%)
- `threads::Int`: Number of threads to use (default 1)
- `verbose::Bool`: Enable solver output logging (default false)
- `solver_specific::Dict{String, Any}`: Solver-specific parameters
- `warm_start::Bool`: Use warm start from previous solution (default false)
- `lp_relaxation::Bool`: Solve LP relaxation only (no integer constraints, default false)

# Example
```julia
options = SolverOptions(;
    time_limit_seconds=300.0,
    mip_gap=0.005,
    threads=4,
    verbose=true,
    solver_specific=Dict("presolve" => true)
)
```
"""
Base.@kwdef struct SolverOptions
    time_limit_seconds::Union{Float64,Nothing} = nothing
    mip_gap::Union{Float64,Nothing} = 0.01
    threads::Int = 1
    verbose::Bool = false
    solver_specific::Dict{String,Any} = Dict{String,Any}()
    warm_start::Bool = false
    lp_relaxation::Bool = false
end

"""
    SolverResult

Complete solution result from optimization.

# Fields
- `status::MOI.TerminationStatusCode`: Raw MOI solution status (OPTIMAL, INFEASIBLE, etc.)
- `solve_status::SolveStatus`: User-friendly status enum
- `objective_value::Union{Float64, Nothing}`: Optimal objective value (if available)
- `solve_time_seconds::Float64`: Time taken to solve
- `objective_bound::Union{Float64, Nothing}`: Best known objective bound (for MIP)
- `node_count::Union{Int, Nothing}`: Number of branch-and-bound nodes (for MIP)
- `variables::Dict{Symbol, Any}`: Variable values (lazy extraction)
- `dual_values::Dict{String, Dict{Tuple, Float64}}`: Dual values by constraint type
- `has_values::Bool`: Whether variable values were extracted
- `has_duals::Bool`: Whether dual values were extracted
- `mip_result::Union{SolverResult, Nothing}`: Stage 1 MIP result (for two-stage pricing)
- `lp_result::Union{SolverResult, Nothing}`: Stage 2 LP result (for two-stage pricing)
- `cost_breakdown::Dict{String, Float64}`: Component costs (thermal, hydro, startup, etc.)
- `log_file::Union{String, Nothing}`: Path to solver log file (if generated)

# Example
```julia
result = solve_model!(model, system)
if result.solve_status == OPTIMAL
    println("Optimal cost: R\$ ", result.objective_value)
    println("Solve time: ", result.solve_time_seconds, " seconds")
    
    # For two-stage pricing
    if result.lp_result !== nothing
        lmps = get_submarket_lmps(result.lp_result, "SE", 1:24)
    end
end
```
"""
mutable struct SolverResult
    status::MathOptInterface.TerminationStatusCode
    solve_status::SolveStatus
    objective_value::Union{Float64,Nothing}
    solve_time_seconds::Float64
    objective_bound::Union{Float64,Nothing}
    node_count::Union{Int,Nothing}
    variables::Dict{Symbol,Any}
    dual_values::Dict{String,Dict{Tuple,Float64}}
    has_values::Bool
    has_duals::Bool
    mip_result::Union{SolverResult,Nothing}
    lp_result::Union{SolverResult,Nothing}
    cost_breakdown::Dict{String,Float64}
    log_file::Union{String,Nothing}
end

# Outer constructor with keyword arguments and defaults for SolverResult
function SolverResult(;
    status::MathOptInterface.TerminationStatusCode = MOI.OPTIMIZE_NOT_CALLED,
    solve_status::SolveStatus = NOT_SOLVED,
    objective_value::Union{Float64,Nothing} = nothing,
    solve_time_seconds::Float64 = 0.0,
    objective_bound::Union{Float64,Nothing} = nothing,
    node_count::Union{Int,Nothing} = nothing,
    variables::Dict{Symbol,Any} = Dict{Symbol,Any}(),
    dual_values::Dict{String,Dict{Tuple,Float64}} = Dict{String,Dict{Tuple,Float64}}(),
    has_values::Bool = false,
    has_duals::Bool = false,
    mip_result::Union{SolverResult,Nothing} = nothing,
    lp_result::Union{SolverResult,Nothing} = nothing,
    cost_breakdown::Dict{String,Float64} = Dict{String,Float64}(),
    log_file::Union{String,Nothing} = nothing,
)
    return SolverResult(
        status,
        solve_status,
        objective_value,
        solve_time_seconds,
        objective_bound,
        node_count,
        variables,
        dual_values,
        has_values,
        has_duals,
        mip_result,
        lp_result,
        cost_breakdown,
        log_file,
    )
end

"""
    map_to_solve_status(moi_status::MOI.TerminationStatusCode)::SolveStatus

Convert MathOptInterface termination status to user-friendly SolveStatus enum.

# Arguments
- `moi_status::MOI.TerminationStatusCode`: Raw MOI status code from solver

# Returns
- `SolveStatus`: User-friendly status enum

# Mapping Table
| MOI Status | SolveStatus |
|------------|-------------|
| OPTIMAL, LOCALLY_SOLVED | OPTIMAL |
| INFEASIBLE, LOCALLY_INFEASIBLE, INFEASIBLE_OR_UNBOUNDED | INFEASIBLE |
| UNBOUNDED, DUAL_INFEASIBLE | UNBOUNDED |
| TIME_LIMIT | TIME_LIMIT |
| ITERATION_LIMIT | ITERATION_LIMIT |
| NUMERICAL_ERROR, SLOW_PROGRESS | NUMERICAL_ERROR |
| NODE_LIMIT, SOLUTION_LIMIT, MEMORY_LIMIT, OBJECTIVE_LIMIT, NORM_LIMIT, OTHER_LIMIT | OTHER_LIMIT |
| OPTIMIZE_NOT_CALLED, INVALID_MODEL, INVALID_OPTION | NOT_SOLVED |

# Example
```julia
status = map_to_solve_status(termination_status(model))
if status == OPTIMAL
    println("Found optimal solution!")
end
```
"""
function map_to_solve_status(moi_status::MOI.TerminationStatusCode)::SolveStatus
    if moi_status == MOI.OPTIMAL || moi_status == MOI.LOCALLY_SOLVED
        return OPTIMAL
    elseif moi_status == MOI.INFEASIBLE ||
           moi_status == MOI.LOCALLY_INFEASIBLE ||
           moi_status == MOI.INFEASIBLE_OR_UNBOUNDED
        return INFEASIBLE
    elseif moi_status == MOI.UNBOUNDED || moi_status == MOI.DUAL_INFEASIBLE
        return UNBOUNDED
    elseif moi_status == MOI.TIME_LIMIT
        return TIME_LIMIT
    elseif moi_status == MOI.ITERATION_LIMIT
        return ITERATION_LIMIT
    elseif moi_status == MOI.NUMERICAL_ERROR || moi_status == MOI.SLOW_PROGRESS
        return NUMERICAL_ERROR
    elseif moi_status == MOI.NODE_LIMIT ||
           moi_status == MOI.SOLUTION_LIMIT ||
           moi_status == MOI.MEMORY_LIMIT ||
           moi_status == MOI.OBJECTIVE_LIMIT ||
           moi_status == MOI.NORM_LIMIT ||
           moi_status == MOI.OTHER_LIMIT
        return OTHER_LIMIT
    else
        # Includes OPTIMIZE_NOT_CALLED, INVALID_MODEL, INVALID_OPTION, etc.
        return NOT_SOLVED
    end
end

"""
    is_optimal(result::SolverResult)::Bool

Check if the solver result is optimal.

# Arguments
- `result::SolverResult`: Solver result to check

# Returns
- `Bool`: true if solution is optimal

# Example
```julia
if is_optimal(result)
    println("Solution is optimal!")
end
```
"""
function is_optimal(result::SolverResult)::Bool
    return result.status == MOI.OPTIMAL
end

"""
    is_infeasible(result::SolverResult)::Bool

Check if the problem is infeasible.

# Arguments
- `result::SolverResult`: Solver result to check

# Returns
- `Bool`: true if problem is infeasible

# Example
```julia
if is_infeasible(result)
    println("Problem is infeasible - check constraints")
end
```
"""
function is_infeasible(result::SolverResult)::Bool
    return result.status == MOI.INFEASIBLE
end

"""
    is_time_limit(result::SolverResult)::Bool

Check if the solver hit the time limit.

# Arguments
- `result::SolverResult`: Solver result to check

# Returns
- `Bool`: true if solver stopped due to time limit
"""
function is_time_limit(result::SolverResult)::Bool
    return result.status == MOI.TIME_LIMIT
end

"""
    has_solution(result::SolverResult)::Bool

Check if the result has a valid solution.

Returns true if status is optimal or a time limit/iteration limit was reached
with a feasible solution available.

# Arguments
- `result::SolverResult`: Solver result to check

# Returns
- `Bool`: true if a valid solution exists
"""
function has_solution(result::SolverResult)::Bool
    return result.status == MOI.OPTIMAL ||
           result.status == MOI.TIME_LIMIT ||
           result.status == MOI.ITERATION_LIMIT ||
           result.status == MOI.NODE_LIMIT ||
           result.status == MOI.SOLUTION_LIMIT
end

# Export public types and functions
export SolveStatus,
    OPTIMAL,
    INFEASIBLE,
    UNBOUNDED,
    TIME_LIMIT,
    ITERATION_LIMIT,
    NUMERICAL_ERROR,
    OTHER_LIMIT,
    NOT_SOLVED,
    SolverType,
    HIGHS,
    GUROBI,
    CPLEX,
    GLPK,
    SolverOptions,
    SolverResult,
    map_to_solve_status,
    is_optimal,
    is_infeasible,
    is_time_limit,
    has_solution
