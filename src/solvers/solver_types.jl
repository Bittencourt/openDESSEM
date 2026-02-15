"""
    Solver Types for OpenDESSEM

Defines base types for the solver interface system.
Provides enumeration of supported solvers and configuration options.
"""

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
- `status::MOI.TerminationStatusCode`: Solution status (OPTIMAL, INFEASIBLE, etc.)
- `objective_value::Union{Float64, Nothing}`: Optimal objective value (if available)
- `solve_time_seconds::Float64`: Time taken to solve
- `objective_bound::Union{Float64, Nothing}`: Best known objective bound (for MIP)
- `node_count::Union{Int, Nothing}`: Number of branch-and-bound nodes (for MIP)
- `variables::Dict{Symbol, Any}`: Variable values (lazy extraction)
- `dual_values::Dict{String, Dict{Tuple, Float64}}`: Dual values by constraint type
- `has_values::Bool`: Whether variable values were extracted
- `has_duals::Bool`: Whether dual values were extracted

# Example
```julia
result = optimize!(model, system, HiGHS.Optimizer; options=solver_options)
if result.status == MOI.OPTIMAL
    println("Optimal cost: R\$ ", result.objective_value)
    println("Solve time: ", result.solve_time_seconds, " seconds")
end
```
"""
Base.@kwdef mutable struct SolverResult
    status::MathOptInterface.TerminationStatusCode
    objective_value::Union{Float64,Nothing} = nothing
    solve_time_seconds::Float64 = 0.0
    objective_bound::Union{Float64,Nothing} = nothing
    node_count::Union{Int,Nothing} = nothing
    variables::Dict{Symbol,Any} = Dict{Symbol,Any}()
    dual_values::Dict{String,Dict{Tuple,Float64}} = Dict{String,Dict{Tuple,Float64}}()
    has_values::Bool = false
    has_duals::Bool = false
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
export SolverType,
    HIGHS,
    GUROBI,
    CPLEX,
    GLPK,
    SolverOptions,
    SolverResult,
    is_optimal,
    is_infeasible,
    is_time_limit,
    has_solution
