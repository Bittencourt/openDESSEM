# OpenDESSEM

## What This Is

An open-source Julia implementation of Brazil's DESSEM day-ahead hydrothermal dispatch optimization model. It loads real ONS/CCEE system data (158 hydro plants, 109 thermal plants, 6,450 buses, 8,850 transmission lines across 4 submarkets), builds a mixed-integer linear program using JuMP, solves with configurable solvers, and produces dispatch schedules with marginal prices (PLD) for the Brazilian electricity market.

## Core Value

End-to-end solve pipeline: load official ONS DESSEM data, build the full SIN optimization model, solve it, and extract validated dispatch + PLD marginal prices that match official DESSEM results within 5%.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. Inferred from existing codebase. -->

- Entity type system with full validation (thermal, hydro, renewable, network, market) -- existing
- ElectricitySystem container with referential integrity validation -- existing
- Variable manager creating JuMP variables for all entity types (UC, generation, storage, curtailment) -- existing
- 7 modular constraint types (thermal commitment, hydro water balance, hydro generation, submarket balance, submarket interconnection, renewable limits, network PowerModels) -- existing
- DESSEM file loader (dessem.arq, entdados.dat, termdat.dat, hidr.dat, desselet.dat) -- existing
- PostgreSQL database loader -- existing
- PowerModels.jl adapter converting entities to PowerModels format -- existing
- Objective function scaffolding (ProductionCostObjective) -- existing
- Solver interface scaffolding (SolverResult, SolverOptions, two-stage pricing) -- existing
- Solution export scaffolding (CSV, JSON) -- existing
- 980+ tests passing across 12 test files -- existing

### Active

<!-- Current scope. Building toward these. Phase 3: Optimization & Solvers. -->

- [ ] Complete objective function builder with full production cost terms (fuel, startup, shutdown, load shedding penalties, water value)
- [ ] Implement working solver interface that orchestrates model build, solve, and result extraction end-to-end
- [ ] Implement two-stage pricing: solve MILP for dispatch, fix integers, solve LP relaxation for PLD duals
- [ ] Support all solver backends: HiGHS (primary), Gurobi, CPLEX, GLPK (lazy-loaded)
- [ ] Fix hydro inflow data loading (currently hardcoded to 0.0) using vazaolateral.csv from DESSEM files
- [ ] Implement cascade water delay logic (upstream releases propagate with travel time)
- [ ] Complete PowerModels network constraint coupling (currently validates but doesn't apply)
- [ ] Implement solution extraction for all variable types (thermal dispatch, hydro storage/outflow, renewable generation, network flows)
- [ ] Extract submarket marginal prices (PLD) from LP relaxation dual variables
- [ ] Export results to CSV and JSON with dispatch, prices, and constraint violation reporting
- [ ] Validate end-to-end solve against official DESSEM using ONS sample data (DS_ONS_102025_RV2D11)
- [ ] Results match official DESSEM within 5% on total cost metric

### Out of Scope

<!-- Explicit boundaries. Phase 4+ work. -->

- Stochastic UC with scenario trees -- future milestone, deterministic only for now
- AC-OPF with MILP relaxation -- DC-OPF via PowerModels sufficient for Phase 3
- Combined-cycle plant mode transitions -- entity exists but advanced scheduling deferred
- Real-time data connectors (ONS/CCEE APIs) -- production deployment concern
- Web UI or API server -- CLI/script-based workflow sufficient
- Docker/cloud deployment -- infrastructure concern, not model concern
- Database export of results to PostgreSQL -- stub exists, defer to post-validation
- Decomposition algorithms (Benders, Dantzig-Wolfe) -- performance optimization, future milestone
- Rolling/receding horizon -- advanced operational feature
- Environmental/carbon constraints -- extension feature

## Context

**Existing codebase**: ~15,000+ lines of Julia across entities, constraints, variables, loaders, solvers, and analysis modules. Solid entity-driven architecture with comprehensive test coverage. The foundation layers (data in, model structure) are complete and well-tested.

**What remains**: The "last mile" -- connecting the existing pieces into a working optimization pipeline. The objective function, solver interface, and solution extraction modules exist as scaffolds but need completion. Several constraint implementations have known gaps (hydro inflows hardcoded to zero, cascade delays not implemented, PowerModels coupling incomplete).

**Sample data**: ONS DESSEM case `DS_ONS_102025_RV2D11` available in `docs/Sample/` with 48 time periods, thermal/hydro plant data, network cases (.pwf files), and operational constraints.

**Brazilian power system**: 4 submarkets (N, NE, SE/CO, S), ~158 hydro plants with cascade dependencies, ~109 thermal plants with unit commitment, DC-OPF network with 6,450+ buses.

## Constraints

- **Tech stack**: Julia 1.8+, JuMP.jl, HiGHS (primary solver), PowerModels.jl for network
- **Compatibility**: Must load official ONS DESSEM file formats via DESSEM2Julia package
- **Performance**: Full SIN model should be solvable (target <2h with HiGHS, <15min with Gurobi)
- **Testing**: TDD mandatory, >90% coverage on new code, all 980+ existing tests must continue passing
- **Code style**: JuliaFormatter mandatory, 4-space indentation, 92-char line limit

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| LP relaxation for PLD extraction | Standard DESSEM approach: fix binary UC decisions, solve LP, extract energy balance duals | -- Pending |
| HiGHS as primary solver | Open-source, good MILP performance, no licensing issues | -- Pending |
| DC-OPF via PowerModels (not AC-OPF) | Sufficient accuracy for Phase 3, AC-OPF adds complexity | -- Pending |
| All solvers supported via lazy loading | Maximum flexibility; Gurobi/CPLEX/GLPK loaded only when used | -- Pending |
| Validate against ONS sample case | Concrete, reproducible validation target with known data | -- Pending |

---
*Last updated: 2026-02-15 after initialization*
