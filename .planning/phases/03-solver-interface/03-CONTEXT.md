# Phase 3: Solver Interface Implementation - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can solve the full MILP model and extract dual variables via two-stage pricing. This phase delivers solver orchestration: load system, create variables, build constraints, set objective, optimize, extract results. It handles solver selection, status reporting, and the two-stage pricing workflow for PLD marginal prices.

</domain>

<decisions>
## Implementation Decisions

### Solver Invocation Options

- **API pattern:** Keyword args with sensible defaults — `solve_model!(model)` or `solve_model!(model; time_limit=3600, mip_gap=0.01)`
- **Default solver:** Auto-detect HiGHS as default, allow override via `solver=HiGHS.Optimizer` kwarg
- **Solver-specific settings:** Both layers — standardized options (`time_limit`, `mip_gap`, `output_level`) plus passthrough dict `solver_attributes=(\"presolve\"=>\"aggressive\")`
- **Return type:** Rich result struct with status, objective, primal values, duals
- **Mutation:** Mutating version — `solve_model!(model)` stores solution in `model.solution`
- **Lazy loading:** Auto-loading with try-catch — attempt to load Gurobi/CPLEX/Glk on demand, fall back gracefully
- **Warm starts:** Stored warm-start field — `model.warm_start` populated from prior solution
- **Execution model:** Immediate status return — solve is synchronous, returns `SolveStatus` enum

### Progress/Logging During Solve

- **Default behavior:** Configurable verbosity — `output_level=0` silent, `1` minimal, `2` detailed
- **File logging:** Auto-log to file — creates `./logs/solve_YYYYMMDD_HHMMSS.log` automatically
- **Progress display:** Progress bar with % complete and current best bound
- **Solver output:** Passthrough raw solver output — let solver print directly, depends on solver settings
- **Control mechanism:** Kwargs only — `output_level`, `log_file`, `progress_callback` as direct kwargs
- **Log filename:** Auto-generated with timestamp — `solve_20260216_143052.log` in `./logs/`
- **Programmatic access:** Callback function option — `progress_callback=(status) -> ...` receives progress updates
- **Detail level:** Depends on verbosity level — full iteration history at level 2, summary at level 1

### Infeasibility Diagnostics

- **Auto behavior:** On-demand IIS computation — `compute_iis(model)` called explicitly when needed, not auto on infeasible
- **Diagnostic content:** Full conflict analysis with bounds — constraint expressions, variable bounds, values at infeasibility
- **Storage location:** Stored in model — `model.infeasibility_diagnostics` field after `compute_iis()` call
- **Console output:** Auto-write report file — creates `infeasibility_YYYYMMDD_HHMMSS.log` with full IIS
- **Report format:** Full mathematical expressions — not just names, includes actual constraint formulas
- **UNBOUNDED handling:** Same as infeasible — no duals available, report as failure
- **Near-feasible solutions:** Report all violations above tolerance — list every violated constraint with magnitude
- **Solver differences:** Best-effort per solver — HiGHS has limited IIS, Gurobi has full, degrade gracefully

### Two-Stage Pricing Exposure

- **Workflow API:** Single call, auto two-stage — `solve_model!(model)` does MIP then LP automatically
- **Results organization:** Separate results tuple — `(mip_solution, lp_solution)` accessible via `model.mip_result` and `model.lp_result`
- **PLD access format:** DataFrame table format — columns: `submarket`, `period`, `pld` in `lp_solution.pld`
- **LP failure handling:** Return inf/NaN placeholders — no error thrown, unavailable duals marked clearly
- **Binary fixing:** Fix via JuMP.fix() — `JuMP.fix(u[i,t], mip_value)` on all binary variables
- **Skip LP stage:** Optional kwarg — `solve_model!(model; pricing=false)` for MIP-only solve
- **Cost breakdown:** By component — thermal_cost, hydro_value, deficit_penalty, startup_cost, shutdown_cost, etc.
- **Other duals:** All duals in result — not just PLD, all constraint duals accessible in `lp_solution.duals`

### OpenCode's Discretion

- Exact progress bar implementation (UnicodeProgressMeter.jl vs custom)
- Log file rotation strategy
- IIS computation timeout behavior
- Precise Solution struct field names and types
- Error message wording and format
- Tolerance defaults for violation checking

</decisions>

<specifics>
## Specific Ideas

- "I want it to feel like a standard optimization library — familiar to anyone who's used JuMP directly"
- Log files should be useful for debugging production runs — include timestamped stage transitions
- PLD DataFrame makes it easy to export to CSV for reporting

</specifics>

<deferred>
## Deferred Ideas

- Async solve with Future/SolveHandle — could be separate phase if needed
- Integration with distributed computing (multiple solves in parallel) — out of scope for v1
- Solution pooling and comparison tools — future enhancement
- Automatic model repair suggestions on infeasibility — future enhancement

</deferred>

---

*Phase: 03-solver-interface*
*Context gathered: 2026-02-16*
