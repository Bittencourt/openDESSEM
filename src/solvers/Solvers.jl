"""
    Solvers Module for OpenDESSEM

Provides unified solver interface for optimization models.

# Components
- `SolverType`: Enumeration of supported solvers (HIGHS, GUROBI, CPLEX, GLPK)
- `SolverOptions`: Configuration options for optimization solvers
- `SolverResult`: Complete solution result from optimization
- `optimize!()`: Main solve function with unified interface
- `solve_lp_relaxation()`: Solve LP relaxation (for pure LP problems)
- `compute_two_stage_lmps()`: Two-stage UC/SCED for LMP calculation (for UC problems)

# Two-Stage Pricing
For unit commitment problems with binary variables, use the two-stage approach:
- **Stage 1**: Solve Unit Commitment (MIP) → commitment decisions
- **Stage 2**: Fix commitments, solve SCED (LP) → valid LMPs

This is the industry standard approach used by all major US electricity markets.

# Example
```julia
using OpenDESSEM.Solvers
using HiGHS

# For unit commitment problems (has binary variables):
uc_result, sced_result = compute_two_stage_lmps(
    model, system, HiGHS.Optimizer;
    options=SolverOptions(time_limit_seconds=300, mip_gap=0.01)
)
# Extract valid LMPs from SCED result
lmps = get_submarket_lmps(sced_result, "SE", 1:24)

# For pure LP problems (no binary variables):
lp_result = solve_lp_relaxation(model, system, HiGHS.Optimizer)
lmps = get_submarket_lmps(lp_result, "SE", 1:24)

# Simple solve without pricing
result = optimize!(model, system, HiGHS.Optimizer)
if is_optimal(result)
    println("Optimal cost: R\$ ", result.objective_value)
end
```
"""

module Solvers

using JuMP
using MathOptInterface
using Dates

# Import entity types from parent module
using ..OpenDESSEM:
    ElectricitySystem,
    ThermalPlant,
    ConventionalThermal,
    HydroPlant,
    ReservoirHydro,
    RenewablePlant,
    WindPlant,
    SolarPlant,
    Submarket,
    Load

# Import variable manager
using ..OpenDESSEM.Variables:
    get_thermal_plant_indices, get_hydro_plant_indices, get_renewable_plant_indices

# Include all solver modules
include("solver_types.jl")
include("solver_interface.jl")
include("solution_extraction.jl")
include("two_stage_pricing.jl")

# Export public types and functions
export
    # User-friendly status enum
    SolveStatus,
    OPTIMAL,
    INFEASIBLE,
    UNBOUNDED,
    TIME_LIMIT,
    ITERATION_LIMIT,
    NUMERICAL_ERROR,
    OTHER_LIMIT,
    NOT_SOLVED,
    map_to_solve_status,

    # Solver type enum
    SolverType,
    HIGHS,
    GUROBI,
    CPLEX,
    GLPK,

    # Configuration and result types
    SolverOptions,
    SolverResult,

    # Main solver functions
    optimize!,
    solve_lp_relaxation,
    get_solver_optimizer,
    apply_solver_options!,
    solver_available,

    # Unified solve API
    solve_model!,

    # Two-stage pricing (UC → SCED for LMPs)
    compute_two_stage_lmps,
    solve_sced_for_pricing,
    fix_commitment!,

    # Solution extraction functions
    extract_solution_values!,
    extract_dual_values!,

    # Convenience functions
    get_submarket_lmps,
    get_thermal_generation,
    get_hydro_generation,
    get_hydro_storage,
    get_renewable_generation,

    # Status helpers
    is_optimal,
    is_infeasible

end # module
