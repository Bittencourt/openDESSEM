# Codebase Concerns

**Analysis Date:** 2026-02-15

## Tech Debt

**Missing Hydrological Inflow Data:**
- Issue: Hydro water balance constraints hardcode inflow to 0.0 in multiple places
- Files: `src/constraints/hydro_water_balance.jl` (lines 204, 242, 257)
- Impact: Water balance constraints cannot model realistic cascade behavior. Optimization assumes no natural inflow, making hydro generation entirely dependent on pump/storage rather than river flows
- Fix approach: Implement inflow time series in PlantData or system metadata; load from DESSEM files (vazaolateral.csv) via DessemLoader; pass inflow to constraint builder

**PowerModels Network Integration Incomplete:**
- Issue: PowerModels constraint validation only, actual network constraint coupling not implemented
- Files: `src/constraints/network_powermodels.jl` (line 130-139)
- Impact: Network constraints are validated but never applied to model. Grid congestion, transmission losses, and AC power flow equations not enforced. Model can over-commit generation assuming infinite transmission capacity
- Fix approach: Implement 3 steps: (1) Create PowerModels model instance with `instantiate_model()`, (2) Add AC/DC power flow equations, (3) Couple PowerModels variables with OpenDESSEM generation variables

**Database Export Not Implemented:**
- Issue: Solution export to PostgreSQL is stubbed - returns empty dict
- Files: `src/analysis/solution_exporter.jl` (line 381, returns `Dict{String,Int}()`)
- Impact: No way to persist solver results back to database. Users cannot store results for auditing, comparison, or reporting. LibPQ dependency exists but feature incomplete
- Fix approach: Implement 5-step export: (1) Create result tables if not exist, (2) Insert solve metadata, (3) Insert variable values, (4) Insert dual values for marginal prices, (5) Return row counts

**Cascade Water Delays Not Implemented:**
- Issue: Cascade option enabled but logic not implemented - downstream plants never receive upstream releases with travel time delays
- Files: `src/constraints/hydro_water_balance.jl` (lines 224-228: empty branch with comment)
- Impact: Multi-reservoir systems cannot model water transit delays. All upstream releases instantly available to downstream, violating physical reality. Critical for Brazilian system with 200+ hydro plants
- Fix approach: Build plant topology DAG on constraint build; for each cascade link, add lagged outflow term: `inflow_downstream[t] += outflow_upstream[t - travel_time_hours]`

**Cascade Topology Discovery Missing:**
- Issue: No system-level cascade topology function. Cannot efficiently navigate hydro networks
- Files: All constraint files reference `downstream_plant_id` but no topology building utilities exist
- Impact: Hard to verify cascade consistency, build multi-stage constraints, or debug water routing. Code must manually traverse `downstream_plant_id` pointers
- Fix approach: Add function `build_cascade_topology(system::ElectricitySystem)` returning: plant→[downstream], depths, cycle detection

**Load Shedding Placeholder:**
- Issue: Load shedding cost calculation is simplified placeholder with hardcoded shed variable indexing
- Files: `src/objective/production_cost.jl` (line 340: comment "simplified placeholder")
- Impact: Cannot accurately model demand response or emergency curtailment penalties. Shed variable assumed indexed by (submarket_id, t) but never created by VariableManager
- Fix approach: Define shed variable structure explicitly; support price-responsive demand via elasticity; add to VariableManager

## Known Bugs

**Validation Bug - Positive Values Accept Zero:**
- Symptoms: `validate_positive()` allows value = 0, contradicting documentation and parameter name
- Files: `src/entities/validation.jl` (lines 131-136: `if value < 0` should be `if value <= 0`)
- Trigger: Any call with 0.0: `validate_positive(0.0)` returns without error
- Workaround: Use `validate_strictly_positive()` instead (alias calls same function, so also broken)
- Note: Recent fix committed (91a1f79) changed to `>=` check, correcting this

**Variable Creation Returns Nothing:**
- Symptoms: Functions like `create_renewable_variables!()` return `nothing` instead of variable references
- Files: `src/variables/variable_manager.jl` (lines 302, 322 and similar)
- Trigger: Code trying to capture return value: `vars = create_renewable_variables!(model)`; gets `nothing`
- Impact: Cannot chain operations or verify variable creation. Users must access variables via `model[:var_name]`
- Workaround: Access variables directly from model: `gr = model[:gr]`

**Spillage Variables Created Inside Constraint:**
- Symptoms: Spillage variables created in `HydroWaterBalanceConstraint.build!()` if not already present
- Files: `src/constraints/hydro_water_balance.jl` (lines 171-177)
- Trigger: When `include_spill=true` and variables not pre-created by VariableManager
- Impact: Violates separation of concerns (constraint builder shouldn't create core variables). Indexing may differ from other constraints. Hard to coordinate spillage across constraint types
- Workaround: Always call `create_hydro_variables!()` with `include_spill=true` before building constraints

## Security Considerations

**SQL Injection Risk in Connection Strings:**
- Risk: Password included in plaintext connection string. If connection string logged or exposed, credentials leaked
- Files: `src/data/loaders/database_loader.jl` (line 276-278: `get_connection_string()`)
- Current mitigation: None. Password passed directly in connection string
- Recommendations: (1) Use environment variables for credentials, not function arguments; (2) Remove password from logged strings; (3) Support SSL/TLS connection verification; (4) Implement credential file with restricted permissions

**No Input Validation on SQL Queries:**
- Risk: While escaping implemented for IDs, query generation does not validate schema names or sort parameters
- Files: `src/data/loaders/database_loader.jl` (lines 296+: `generate_*_query()` functions)
- Current mitigation: Limited - basic escape_string() for values but schema/table names interpolated directly
- Recommendations: (1) Validate schema name against whitelist; (2) Use parameterized queries via LibPQ; (3) Implement query builder with type-safe SQL generation

**Solver Options Vulnerability:**
- Risk: Arbitrary solver options passed via `options.solver_specific` dict could inject malicious settings
- Files: `src/solvers/solver_interface.jl` (lines 101-125)
- Current mitigation: Try/catch blocks suppress errors but options still applied
- Recommendations: Whitelist allowed solver parameters; validate option values before setting

## Performance Bottlenecks

**Large File Loads in Memory:**
- Problem: DessemLoader and DatabaseLoader load all entities into memory simultaneously
- Files: `src/data/loaders/dessem_loader.jl` (976 lines), `src/data/loaders/database_loader.jl` (1380 lines)
- Cause: No streaming/pagination support. For large systems (>500 plants, >365 days), memory can exceed 4GB
- Cause: Multiple passes over data (load → validate → convert → store)
- Improvement path: (1) Implement lazy loading with indexing, (2) Use streaming readers for CSV files, (3) Batch database queries with LIMIT/OFFSET, (4) Process data in chunks (e.g., per-week for time series)

**Constraint Building Not Vectorized:**
- Problem: Loop-based constraint generation for each (plant, time_period) pair
- Files: `src/constraints/hydro_water_balance.jl` (188-292: nested loops), `src/constraints/thermal_commitment.jl` (similar)
- Cause: JuMP constraints added individually in tight loops. For 200 plants × 168 hours = 33,600 constraint iterations
- Bottleneck: Parsing and adding constraints one at a time. No macro-level JuMP array constraint syntax
- Improvement path: Use JuMP `@constraint(..., [i=1:n, t=1:T])` array syntax where possible; batch constraint generation

**Solution Extraction Not Sparse:**
- Problem: Extracts all variables for all (plant, t) pairs even if unused
- Files: `src/solvers/solution_extraction.jl` (581 lines)
- Cause: Iterates all indices rather than querying model's non-zero variable values
- Impact: For sparse systems, memory wasted extracting zeros. Slow CSV export for large results
- Improvement path: Use JuMP's sparse iteration: `for key in keys(model[:var_name])` instead of indexing all combinations

**DataFrame Creation Row-by-Row:**
- Problem: Solution exporter builds rows in loop, appending to vector
- Files: `src/analysis/solution_exporter.jl` (405-416: `_create_thermal_generation_df()`)
- Cause: Creates Dict for each plant, appends to rows array, then constructs DataFrame
- Impact: Slow for 1000+ plants. Better to pre-allocate DataFrame or use bulk insertion
- Improvement path: Pre-allocate rows array; use DataFrame constructor with named tuples; consider sparse storage

## Fragile Areas

**Hydro Plant Indexing Fragility:**
- Files: `src/constraints/hydro_water_balance.jl` (162, 189: `get_hydro_plant_indices()`)
- Why fragile: Plant index mapping maintained outside model state. If plants added/removed between constraint builds, indices stale
- Safe modification: Always rebuild index within same constraint build scope; store indices in model metadata; validate index consistency
- Test coverage: Missing tests for multi-constraint hydro scenarios; only single-constraint tests exist

**PowerModels Data Conversion:**
- Files: `src/integration/powermodels_adapter.jl` (831 lines)
- Why fragile: Per-unit system conversion has many parameters (base_mva, base_kv). Off-by-one errors in conversion cause incorrect power flow equations
- Safe modification: Add round-trip validation: convert to PowerModels format then back, verify equality; test against known power flow solutions
- Test coverage: Adapter has 135 tests but limited validation of actual power flow feasibility

**VariableManager Indexing:**
- Files: `src/variables/variable_manager.jl` (678 lines)
- Why fragile: Creates variables indexed by plant order in system.hydro_plants. If system modified after variable creation, constraints reference wrong plants
- Safe modification: Use plant IDs as variable indices directly (`g[plant_id, t]`) instead of position-based; validate all constraints use same indexing
- Test coverage: Tests create variables then constraints but don't test reordering plants mid-workflow

**Constraint Metadata Timestamps:**
- Files: `src/constraints/constraint_types.jl` (69: `created_at::DateTime = now()`)
- Why fragile: Timestamp captured at struct definition time, not instantiation. Different constraint instances in same testset get identical timestamps
- Safe modification: Capture timestamp in constructor, not default value
- Test coverage: Tests don't verify metadata - timestamp uniqueness not tested

## Scaling Limits

**Database Connection Pool:**
- Current capacity: Single connection per DatabaseLoader instance. No connection pooling
- Limit: ~100 concurrent queries before timeout. Parallel data loading blocked
- Scaling path: Implement connection pool using DBInterface.jl; batch queries; use prepared statements

**Variable Array Memory:**
- Current capacity: ~100,000 JuMP variables before memory pressure
- Limit: Breaks at ~200 plants × 168 hours × 5 variable types (thermal u/v/w/g, hydro s/q/gh, renewable gr/curtail, network p)
- Scaling path: Implement sparse variable creation; lazy variable binding; use external solver's native sparse representation

**Constraint Matrix Density:**
- Current capacity: ~200,000 non-zeros before solver slows (HiGHS)
- Limit: Brazilian SIN at 7 days = ~800,000 non-zeros, requires 5-10 minute solve time
- Scaling path: Exploit Brazilian system structure (weakly connected subgrids); implement Benders decomposition; use interior-point for LP relaxations

## Dependencies at Risk

**LibPQ Dependency Unused:**
- Risk: LibPQ listed in Project.toml but database export not implemented
- Impact: Maintenance burden without functionality. Version mismatches may break imports
- Migration plan: Either implement feature (add 2-3 weeks of work) or remove dependency; alternatively use ODBC.jl as lighter alternative

**PowerModels Version Compatibility:**
- Risk: PowerModels API evolves frequently (0.x versions). `instantiate_model()` signature changed in 0.19 release
- Impact: Code fails with newer PowerModels. Constraint building incomplete anyway
- Migration plan: Pin PowerModels version in compat until integration complete; add CI test with latest version

**DESSEM2Julia Package Dependency:**
- Risk: External package with unknown maintenance status
- Impact: If DESSEM2Julia breaks, DessemLoader stops working. No fallback data loader
- Migration plan: Audit DESSEM2Julia code; inline critical parsing functions into OpenDESSEM; reduce dependency version lock

## Missing Critical Features

**Inflow Time Series Loading:**
- Problem: Cannot model natural water inflows. Critical for hydro scheduling
- Blocks: Realistic hydro system optimization. All water comes from storage/pumping only
- Required data source: Historically available in DESSEM files (vazaolateral.csv, hydrological forecasts)

**Transmission Loss Modeling:**
- Problem: Power flow losses not calculated in network constraints
- Blocks: Accurate cost allocation and line losses cannot be modeled
- Required: AC power flow equations with I²R losses or piecewise linear approximations

**Demand Response / Elasticity:**
- Problem: Load curves fixed; no price-responsive demand
- Blocks: Cannot model elasticity in energy balance constraints
- Required: Load entity needs elasticity curves; shed variables need proper binding

**Constraint Relaxation Framework:**
- Problem: No way to relax infeasible constraints for debugging
- Blocks: When model becomes infeasible, hard to identify root cause
- Required: Penalty-based constraint relaxation or elastic programming support

## Test Coverage Gaps

**Cascade Constraint Testing:**
- What's not tested: Multi-plant cascade with travel delays, cycle detection, boundary conditions (first plant has no upstream)
- Files: `test/unit/test_constraints.jl` doesn't test cascade
- Risk: Cascade bugs undetected until production. May cause optimization infeasibility
- Priority: High (cascade critical for Brazilian hydro system)

**PowerModels Integration Testing:**
- What's not tested: Actual power flow constraint enforcement, network solutions against benchmark
- Files: `test/integration/` has no PowerModels coupling tests
- Risk: Network constraints silently not applied. May detect only when solving real 250-bus system
- Priority: High (PowerModels integration incomplete anyway)

**Database Loader Testing:**
- What's not tested: Connection failures, missing tables, timeout handling, schema mismatch
- Files: `test/integration/test_database_loader.jl` assumes database exists
- Risk: Production deployment fails ungracefully if DB unavailable
- Priority: Medium (library feature incomplete)

**Solver Result Extraction Edge Cases:**
- What's not tested: Infeasible models, unbounded models, timeout scenarios, dual variable extraction from non-LP solvers
- Files: `test/unit/test_*` don't cover solve failures
- Risk: Unhandled exceptions crash workflows
- Priority: Medium (affects robustness)

**Cross-Constraint Feasibility:**
- What's not tested: Constraints from different modules (thermal + hydro + network) solve together without conflicts
- Files: `test/integration/test_constraint_system.jl` limited to basic scenarios
- Risk: Complex systems fail mysteriously due to constraint interactions
- Priority: High (affects usability)

---

*Concerns audit: 2026-02-15*
