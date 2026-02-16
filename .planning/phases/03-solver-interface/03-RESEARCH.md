# Phase 3: Solver Interface Implementation - Research

**Researched:** 2026-02-16
**Domain:** JuMP optimization, solver abstraction, two-stage pricing, infeasibility diagnostics
**Confidence:** HIGH

## Summary

Phase 3 extends the existing solver infrastructure to provide a polished, production-ready API with two-stage pricing for PLD marginal prices, multi-solver support with lazy loading, comprehensive infeasibility diagnostics, and configurable progress/logging.

The project already has substantial solver infrastructure in `src/solvers/` with `SolverOptions`, `SolverResult`, `optimize!()`, `solve_lp_relaxation()`, `compute_two_stage_lmps()`, and solution extraction functions. This phase focuses on refining the API to match user decisions, adding missing features (logging, IIS, warm starts, DataFrame outputs), and ensuring robust multi-solver support.

**Primary recommendation:** Build on existing `Solvers.jl` infrastructure using JuMP 1.0's `fix_discrete_variables()` for two-stage pricing, `compute_conflict!()` for IIS, and Logging.jl for file logging.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.0 | Optimization modeling | Industry standard, full MOI support |
| MathOptInterface | 1.0 | Solver abstraction | JuMP's solver-agnostic layer |
| HiGHS | 1.0 | Primary MILP/LP solver | Open-source, high performance, MIT license |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Logging | stdlib | File logging | All production runs |
| DataFrames | 1.0 | PLD output format | When returning PLD tables |
| Dates | stdlib | Timestamp generation | Log file naming |
| Gurobi | 1.9+ | Commercial solver | When license available, faster |
| CPLEX | 1.0+ | Commercial solver | Alternative to Gurobi |
| GLPK | 1.1+ | Open-source backup | When HiGHS unavailable |

### Optional (for IIS)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MathOptIIS | 0.1+ | IIS for solvers without native support | Fallback for HiGHS |

**Installation:**
```julia
# Already in Project.toml
# For optional MathOptIIS:
import Pkg; Pkg.add("MathOptIIS")
```

## Architecture Patterns

### Recommended Solver Module Structure
```
src/solvers/
├── Solvers.jl              # Main module, exports
├── solver_types.jl         # SolverType enum, SolverOptions, SolverResult, SolveStatus
├── solver_interface.jl     # solve_model!(), lazy loading, status handling
├── two_stage_pricing.jl    # MIP→LP for duals, fix_discrete_variables
├── solution_extraction.jl  # Variable/dual extraction, PLD DataFrame
├── infeasibility.jl        # compute_iis(), conflict analysis, reports
└── logging.jl              # File logging, progress callbacks
```

### Pattern 1: Unified Solve API
**What:** Single entry point with keyword args and sensible defaults
**When to use:** All optimization solves
**Example:**
```julia
# Source: User decision + JuMP 1.0 patterns
"""
    solve_model!(model; kwargs...) -> SolveResult

Solve the optimization model with configurable options.

# Keyword Arguments
- `solver`: Optimizer factory (default: HiGHS.Optimizer)
- `time_limit::Float64`: Time limit in seconds (default: 3600.0)
- `mip_gap::Float64`: MIP gap tolerance (default: 0.01)
- `output_level::Int`: 0=silent, 1=minimal, 2=detailed (default: 1)
- `pricing::Bool`: Enable two-stage pricing for PLDs (default: true)
- `log_file::Union{String,Nothing}`: Log file path (default: auto-generate)
- `progress_callback`: Function for progress updates (default: nothing)
- `warm_start::Union{SolverResult,Nothing}`: Previous solution for warm start
- `solver_attributes::Dict{String,Any}`: Solver-specific options
"""
function solve_model!(model; kwargs...)
```

### Pattern 2: Two-Stage Pricing
**What:** Use JuMP 1.0's `fix_discrete_variables()` to simplify two-stage pricing
**When to use:** Unit commitment problems requiring valid duals (PLDs)
**Example:**
```julia
# Source: https://jump.dev/JuMP.jl/stable/tutorials/linear/mip_duality/
function solve_two_stage!(model; options=SolverOptions())
    # Stage 1: Solve MIP for commitment
    optimize!(model)
    mip_result = extract_result(model)
    
    if !is_optimal(mip_result)
        return (mip_result, nothing)
    end
    
    # Fix discrete variables and relax
    undo = fix_discrete_variables(model)
    
    # Stage 2: Solve LP relaxation for duals
    optimize!(model)
    lp_result = extract_result(model)
    
    # Restore MIP formulation
    undo()
    
    return (mip_result, lp_result)
end
```

### Pattern 3: Lazy Solver Loading
**What:** Attempt to load optional solvers on demand, fall back gracefully
**When to use:** Multi-solver support without hard dependencies
**Example:**
```julia
# Source: User decision + Julia module patterns
const _GUROBI_LOADED = Ref(false)
const _GUROBI_AVAILABLE = Ref(false)

function _try_load_gurobi()
    _GUROBI_LOADED[] && return _GUROBI_AVAILABLE[]
    try
        @eval import Gurobi
        _GUROBI_AVAILABLE[] = true
    catch
        @warn "Gurobi.jl not available. Install with: import Pkg; Pkg.add(\"Gurobi\")"
        _GUROBI_AVAILABLE[] = false
    end
    _GUROBI_LOADED[] = true
    return _GUROBI_AVAILABLE[]
end

function get_solver_factory(::Val{:gurobi})
    _try_load_gurobi() || error("Gurobi not available")
    return Gurobi.Optimizer
end
```

### Pattern 4: Infeasibility Diagnostics
**What:** Use JuMP's `compute_conflict!()` for IIS computation
**When to use:** When model is infeasible and user requests diagnostics
**Example:**
```julia
# Source: https://jump.dev/JuMP.jl/stable/manual/solutions/#Conflicts
function compute_iis!(model)
    compute_conflict!(model)
    status = get_attribute(model, MOI.ConflictStatus())
    
    if status == MOI.CONFLICT_FOUND
        iis_model, _ = copy_conflict(model)
        # Extract conflicting constraints
        conflicts = ConstraintRef[]
        for (F, S) in list_of_constraint_types(model)
            for con in all_constraints(model, F, S)
                if get_attribute(con, MOI.ConstraintConflictStatus()) == MOI.IN_CONFLICT
                    push!(conflicts, con)
                end
            end
        end
        return IISResult(status=MOI.CONFLICT_FOUND, constraints=conflicts)
    end
    
    return IISResult(status=status, constraints=ConstraintRef[])
end
```

### Anti-Patterns to Avoid
- **Throwing errors on missing solvers:** Use graceful fallback with warnings
- **Querying duals before checking status:** Always verify `is_solved_and_feasible(model; dual=true)`
- **Modifying model after solve without extracting results:** Causes `OptimizeNotCalled` errors
- **Assuming all solvers support IIS:** HiGHS has limited support, use MathOptIIS as fallback

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Two-stage pricing | Manual fix/unfix loops | `fix_discrete_variables()` | Handles all variable types, returns undo function |
| IIS computation | Custom infeasibility search | `compute_conflict!()` | Solver-native when available, standardized API |
| Progress tracking | Custom callback system | MOI callback attributes | Solver-agnostic, well-tested |
| Log file naming | Manual timestamp formatting | `Dates.format(now(), "yyyymmdd_HHMMSS")` | Consistent format |
| Solver option mapping | Custom parameter handling | `MOI.RawParameter` | Works with any solver |

**Key insight:** JuMP 1.0 and MOI 1.0 provide rich functionality. Leverage existing functions rather than reimplementing.

## Common Pitfalls

### Pitfall 1: Dual Query on MIP
**What goes wrong:** Calling `dual()` on a MIP model returns `NO_SOLUTION`
**Why it happens:** MIPs don't have valid duals - only LP relaxations do
**How to avoid:** Always use two-stage pricing: solve MIP, fix binaries, solve LP
**Warning signs:** `dual_status(model) == NO_SOLUTION` when expecting duals

### Pitfall 2: OptimizeNotCalled Errors
**What goes wrong:** Modifying model after solve then querying results
**Why it happens:** JuMP resets solution state on model modification
**How to avoid:** Extract all results BEFORE modifying the model
```julia
# Bad
optimize!(model)
set_upper_bound(x, 10)  # Modification
value(x)  # Error!

# Good
optimize!(model)
x_val = value(x)  # Extract first
set_upper_bound(x, 10)  # Then modify
```

### Pitfall 3: Gurobi Performance Pitfall
**What goes wrong:** Excessive time in model updates warning
**Why it happens:** Gurobi buffers changes; querying triggers update
**How to avoid:** Batch modifications before queries in loops
```julia
# Bad: modify-query in loop
for i in 1:100
    set_upper_bound(x[i], i)
    println(lower_bound(x[i]))  # Triggers update each iteration
end

# Good: batch modify, then batch query
for i in 1:100
    set_upper_bound(x[i], i)
end
for i in 1:100
    println(lower_bound(x[i]))  # Only first query triggers update
end
```

### Pitfall 4: Infeasibility Certificate Confusion
**What goes wrong:** Misinterpreting infeasibility certificates as duals
**Why it happens:** `primal_status == INFEASIBILITY_CERTIFICATE` looks like a solution
**How to avoid:** Check `termination_status` before using certificates
```julia
if termination_status(model) == INFEASIBLE && 
   dual_status(model) == INFEASIBILITY_CERTIFICATE
    # This is a Farkas certificate, not a dual solution
    farkas = dual(constraint)
end
```

### Pitfall 5: Thread Safety with Solver Environments
**What goes wrong:** Gurobi environments are not thread-safe
**Why it happens:** Solvers use global state for license management
**How to avoid:** Don't share Gurobi.Env between parallel solves

## Code Examples

### Two-Stage Pricing with PLD Extraction
```julia
# Source: JuMP docs + user decisions
using JuMP, HiGHS, DataFrames

function solve_with_pld!(
    model::Model, 
    system::ElectricitySystem;
    solver=HiGHS.Optimizer,
    time_limit=3600.0,
    mip_gap=0.01
)
    # Configure solver
    set_optimizer(model, solver)
    set_attribute(model, MOI.TimeLimitSec(), time_limit)
    set_attribute(model, MOI.RelativeGapTolerance(), mip_gap)
    
    # Stage 1: MIP solve
    optimize!(model)
    
    if termination_status(model) != MOI.OPTIMAL
        return (mip_result=nothing, lp_result=nothing, pld=DataFrame())
    end
    
    mip_result = extract_result(model)
    
    # Stage 2: Fix binaries and solve LP for duals
    undo = fix_discrete_variables(model)
    optimize!(model)
    
    lp_result = extract_result(model)
    
    # Extract PLDs as DataFrame
    pld_df = DataFrame(
        submarket = String[],
        period = Int[],
        pld = Float64[]
    )
    
    for sm in system.submarkets, t in 1:system.time_periods
        constraint = model[:submarket_balance][(sm.code, t)]
        pld = dual(constraint)
        push!(pld_df, (sm.code, t, pld))
    end
    
    # Restore MIP formulation
    undo()
    
    return (mip_result=mip_result, lp_result=lp_result, pld=pld_df)
end
```

### Infeasibility Diagnostics
```julia
# Source: https://jump.dev/JuMP.jl/stable/manual/solutions/#Conflicts
function diagnose_infeasibility!(model::Model; output_file=nothing)
    # Check if already infeasible
    if termination_status(model) ∉ (MOI.INFEASIBLE, MOI.LOCALLY_INFEASIBLE)
        @warn "Model is not infeasible"
        return nothing
    end
    
    # Compute conflict
    compute_conflict!(model)
    status = get_attribute(model, MOI.ConflictStatus())
    
    if status != MOI.CONFLICT_FOUND
        @warn "Could not find conflict. Status: $status"
        return IISResult(status=status)
    end
    
    # Extract conflicting constraints
    conflicts = Tuple{ConstraintRef,String}[]
    for (F, S) in list_of_constraint_types(model)
        for con in all_constraints(model, F, S)
            if get_attribute(con, MOI.ConstraintConflictStatus()) == MOI.IN_CONFLICT
                push!(conflicts, (con, name(con)))
            end
        end
    end
    
    result = IISResult(status=status, constraints=conflicts)
    
    # Write report if requested
    if output_file !== nothing
        write_iis_report(result, output_file)
    end
    
    return result
end
```

### Progress Callback Integration
```julia
# Source: User decision + MOI patterns
function solve_with_progress!(
    model::Model;
    progress_callback=nothing,
    output_level::Int=1
)
    start_time = time()
    
    # Configure verbosity
    if output_level == 0
        set_attribute(model, MOI.Silent(), true)
    end
    
    # Solve
    optimize!(model)
    
    # Report progress if callback provided
    if progress_callback !== nothing
        status = (
            termination_status = termination_status(model),
            objective_value = objective_value(model),
            solve_time = time() - start_time,
            node_count = node_count(model)
        )
        progress_callback(status)
    end
    
    return extract_result(model)
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual binary fixing | `fix_discrete_variables()` | JuMP 1.0 | Simpler, returns undo function |
| Solver-specific IIS | `compute_conflict!()` | JuMP 1.0+ | Unified API across solvers |
| Direct solver calls | `set_optimizer()` + `optimize!()` | MOI 1.0 | Solver-agnostic code |
| Custom status handling | `is_solved_and_feasible()` | JuMP 1.0 | Handles all status combinations |

**Deprecated/outdated:**
- `MathProgBase`: Replaced by MathOptInterface
- `@variable(model, x, Bin)` → `@variable(model, x, Bin)` (still valid, but use `set_binary()` for dynamic)
- `setsolver()`: Use `set_optimizer()` instead

## Open Questions

Things that couldn't be fully resolved:

1. **HiGHS IIS Limitations**
   - What we know: HiGHS has infeasibility certificates but limited IIS support
   - What's unclear: Exact extent of IIS computation in HiGHS 1.0+
   - Recommendation: Use MathOptIIS.jl as fallback; document that Gurobi/CPLEX have better IIS

2. **Progress Bar Implementation**
   - What we know: User wants progress bar with % complete and best bound
   - What's unclear: MIP solvers don't provide reliable progress percentages
   - Recommendation: Use callback for objective bound updates; don't promise percentage

3. **Log File Rotation**
   - What we know: User wants auto-generated log files
   - What's unclear: Rotation strategy (by size, by date, by count)
   - Recommendation: Start with single file per solve; rotation is future enhancement

## Sources

### Primary (HIGH confidence)
- JuMP Solutions Manual: https://jump.dev/JuMP.jl/stable/manual/solutions/ - Status handling, duals, conflicts
- JuMP Callbacks Manual: https://jump.dev/JuMP.jl/stable/manual/callbacks/ - Solver-independent callbacks
- MIP Duality Tutorial: https://jump.dev/JuMP.jl/stable/tutorials/linear/mip_duality/ - Two-stage pricing pattern
- HiGHS.jl Docs: https://jump.dev/JuMP.jl/stable/packages/HiGHS/ - Solver options, infeasibility certificates
- Gurobi.jl Docs: https://jump.dev/JuMP.jl/stable/packages/Gurobi/ - Callbacks, IIS, performance pitfalls
- MathOptIIS.jl: https://jump.dev/JuMP.jl/stable/packages/MathOptIIS/ - Fallback IIS computation

### Secondary (MEDIUM confidence)
- Existing codebase: `src/solvers/` - Current implementation patterns
- Project.toml - Dependency versions (JuMP 1.0, HiGHS 1.0, MOI 1.0)

### Tertiary (LOW confidence)
- None required - all critical information from official sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - JuMP 1.0, HiGHS 1.0, MOI 1.0 are stable, well-documented
- Architecture: HIGH - Patterns from official JuMP documentation and tutorials
- Pitfalls: HIGH - Documented in JuMP manual and solver packages

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days - stable ecosystem)

---

## Implementation Notes for Planner

### Existing Infrastructure to Preserve
The current `src/solvers/` already implements:
- `SolverType` enum with HIGHS, GUROBI, CPLEX, GLPK
- `SolverOptions` with time_limit, mip_gap, threads, verbose, solver_specific
- `SolverResult` with status, objective_value, solve_time, variables, dual_values
- `optimize!()`, `solve_lp_relaxation()`, `compute_two_stage_lmps()`
- `fix_commitment!()`, `solve_sced_for_pricing()`
- `extract_solution_values!()`, `extract_dual_values!()`
- `get_submarket_lmps()`, `get_thermal_generation()`, etc.

### Key Additions Needed
1. **SolveStatus enum**: Map MOI.TerminationStatusCode to user-friendly enum
2. **solve_model!()**: New unified API per user decisions
3. **Log file generation**: Using Logging.jl, auto-create `./logs/solve_YYYYMMDD_HHMMSS.log`
4. **Progress callback**: ProgressCallback type and integration
5. **compute_iis()**: On-demand IIS computation with report generation
6. **PLD DataFrame output**: Convert dual_values to DataFrame format
7. **Cost breakdown**: Detailed cost components in result
8. **Warm start integration**: Use existing field, implement value setting
9. **Lazy loading refinement**: Graceful fallback instead of errors
10. **Result struct refinement**: Separate `mip_result` and `lp_result` fields

### Testing Strategy
- Unit tests for each new function
- Integration test with small system (3-5 plants)
- Infeasibility test case with known IIS
- Multi-solver test (HiGHS, skip Gurobi/CPLEX if unavailable)
- Two-stage pricing validation (verify duals are valid)
