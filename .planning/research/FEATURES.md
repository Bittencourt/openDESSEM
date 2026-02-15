# Feature Landscape

**Domain:** Hydrothermal Dispatch Optimization Solver
**Researched:** 2026-02-15

## Table Stakes

Features users expect. Missing = solver is incomplete or unusable.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Production Cost Objective** | Core economic optimization goal | Low | Fuel + O&M + startup/shutdown costs. Already partially implemented in `ProductionCostObjective` |
| **Water Value Integration** | Future cost of water (from NEWAVE/DECOMP) | Medium | Critical for hydro-dominated systems. Imported as FCF curves, added to objective as terminal value |
| **Submarket Energy Balance Constraints** | Physical requirement: generation = demand + interchange | Low | Already implemented. Foundation for marginal pricing |
| **Thermal UC Constraints** | Operational limits (ramps, min up/down, startup/shutdown) | Medium | Already implemented. Standard UC formulation |
| **Hydro Water Balance** | Conservation of mass in cascaded reservoirs | Medium | Already implemented with cascade delays |
| **Transmission Limits** | Network capacity constraints (line flow limits) | Medium | Already implemented via PowerModels integration |
| **LP Relaxation for Pricing** | Get valid dual variables for marginal prices | Medium | **CRITICAL**: Already implemented in `two_stage_pricing.jl`. Industry standard UC→SCED pattern |
| **PLD Extraction** | Marginal settlement prices per submarket per hour | Low | Already implemented in `extract_dual_values!()`. Core output for Brazilian market |
| **CSV Export** | Standard tabular format (Excel-compatible) | Low | Already implemented in `export_to_csv()` |
| **JSON Export** | Machine-readable full solution | Low | Already implemented in `export_to_json()` |
| **Infeasibility Diagnostics** | Why did the model fail? Which constraint? | Medium | Essential for debugging. Partially implemented (needs constraint violation reporting) |
| **Solution Validation** | Check bounds, energy balance, reserve requirements | Low | Already has `check_solution_validity()`. Needs expansion |
| **Basic Logging** | Solver progress, iteration count, objective value | Low | Already implemented via `@info` statements in solver interface |
| **HiGHS Solver Support** | Free, open-source LP/MIP solver | Low | Already implemented. Primary solver for open-source users |
| **Gurobi Support** | Commercial solver (10-100x faster for large MIP) | Low | Already implemented as optional. Industry standard for production |

## Differentiators

Features that set product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Validation Against Official DESSEM** | Prove correctness vs ONS results | Medium | Already planned in `VALIDATION_FRAMEWORK_DESIGN.md`. Key trust factor |
| **Database-Native Loading** | Production systems use PostgreSQL, not files | Medium | Partially implemented (`DatabaseLoader` exists but incomplete) |
| **Scenario-Based Optimization** | Stochastic inflow scenarios (PSR SDDP pattern) | High | Extension beyond deterministic DESSEM. Future water value under uncertainty |
| **Network-Constrained Dispatch** | Full AC/DC power flow, not just zonal | High | Partially implemented via PowerModels. Gives locational vs zonal prices |
| **Reserve Co-Optimization** | Spinning/non-spinning reserves in objective | Medium | Common in PLEXOS, rare in DESSEM. Improves reliability |
| **Renewable Curtailment Analysis** | How much wind/solar was wasted? | Low | Already has curtailment variables. Just need reporting |
| **Constraint Violation Reporting** | Rank constraints by shadow price or slack | Low | Helps operators understand binding constraints |
| **Warm Start** | Initialize from previous solution (rolling horizon) | Medium | Standard in production. Speeds up 168-hour weekly runs |
| **Parallel Scenario Solving** | Solve multiple inflow scenarios concurrently | High | Requires distributed computing. PSR SDDP pattern |
| **Custom Objective Components** | User-defined penalty terms or objectives | Low | Already has `AbstractObjective` framework. Just needs documentation |
| **Solution Comparison Tool** | Diff two solutions (official DESSEM vs OpenDESSEM) | Low | Critical for validation workflow. Simple diff logic |
| **HTML Dashboard Export** | Interactive solution explorer (web-based) | Medium | Modern UX vs CSV files. Plotly.jl or web framework |
| **Slack Variable Reporting** | What violated and by how much? | Low | Essential for infeasibility diagnosis |
| **Convergence Metrics** | MIP gap over time, primal/dual bounds | Low | Industry standard. Helps tune solver parameters |

## Anti-Features

Features to explicitly NOT build (at least not in Phase 3).

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Custom LP/MIP Solver** | Reinventing the wheel poorly | Use HiGHS/Gurobi/CPLEX. Solver development is PhD-level work |
| **Graphical User Interface** | Scope creep, maintenance burden | CLI + CSV/JSON export. Users can use Excel/Tableau/Python |
| **Real-Time Dispatch** | Different problem (millisecond timescale, state estimation) | Focus on day-ahead planning. Real-time is DESSEM-PAT, not DESSEM |
| **Transmission Expansion Planning** | Multi-year investment problem, not dispatch | Focus on operational dispatch. Expansion is NEWAVE/PDM domain |
| **Demand Response Modeling** | Complex bidding, price elasticity curves | Use fixed demand or simple price caps. DR is market design, not physics |
| **Multi-Area SDDP** | Stochastic dual dynamic programming (months to implement) | Use deterministic water values from DECOMP. SDDP is PSR's product |
| **Automatic Tuning** | ML-based solver parameter optimization | Document good defaults. Tuning is user's job after profiling |
| **Built-in Visualization** | Plotting, charts, graphics in solver | Export data, use external tools (Python/R/Plotly) |
| **Multi-Objective Optimization** | Pareto frontiers, cost vs emissions tradeoffs | Single objective (cost). Let users do scenario analysis externally |
| **Forecast Generation** | Wind/solar/inflow prediction models | Load forecasts from files. Forecasting is a separate domain |

## Feature Dependencies

```
Production Cost Objective → Fuel costs, startup costs, water values
                          ↓
                   Solver Interface
                          ↓
              UC Solution (MIP) → Basic feasibility check
                          ↓
          LP Relaxation (SCED) → Two-stage pricing pattern
                          ↓
            Extract Dual Values → PLD (marginal prices)
                          ↓
                   Export Results → CSV, JSON, Database
                          ↓
            Validation Framework → Compare with official DESSEM
```

**Critical Path**: Objective → Solve UC → LP Relaxation → Extract Duals → Validate
**Parallel Paths**:
- Export infrastructure (can develop alongside solver)
- Validation framework (can develop once solution works)
- Database loading (can parallelize with file-based testing)

## MVP Recommendation

Prioritize (Phase 3 focus):

1. **Complete Production Cost Objective** (LOW complexity)
   - Fuel costs: Already implemented
   - Water values: Need FCF curve integration from `infofcf.dat`
   - Startup/shutdown costs: Already in thermal entities
   - **Status**: 80% done, needs water value loading

2. **Solver Orchestration** (LOW complexity)
   - Already has `build_model()`, `optimize!()`, `solve_lp_relaxation()`
   - Need: Workflow that calls UC solve → LP relaxation → extract duals
   - **Status**: Infrastructure exists, needs integration test

3. **PLD Extraction via LP Relaxation** (MEDIUM complexity)
   - Already implemented in `two_stage_pricing.jl` and `extract_dual_values!()`
   - Industry-standard UC→SCED pattern for getting valid duals
   - **Status**: Implemented, needs end-to-end testing

4. **Solution Export** (LOW complexity)
   - CSV: Already implemented
   - JSON: Already implemented
   - Need: Validation that exported data matches expected format
   - **Status**: 90% done, needs format verification

5. **Validation Against Official DESSEM** (MEDIUM complexity)
   - Already has sample data in `docs/Sample/DS_ONS_102025_RV2D11/`
   - Already has validation framework design in `VALIDATION_FRAMEWORK_DESIGN.md`
   - Need: Load official output, compare with OpenDESSEM output
   - **Status**: Framework designed, needs implementation

6. **Infeasibility Diagnostics** (MEDIUM complexity)
   - Check termination status (optimal, infeasible, time limit)
   - Report which constraint is violated (if infeasible)
   - **Status**: Basic checks exist, needs constraint-level reporting

Defer (Future phases):

- **Database Loading**: File-based loading works for validation. Database is production feature
- **Network-Constrained Dispatch**: Already has PowerModels integration. Full AC/DC is research topic
- **Warm Start**: Optimization (not correctness). Add after validation passes
- **HTML Dashboard**: UX feature. CSV export is sufficient for MVP

## Complexity Assessment

| Feature Category | Effort | Risk | Priority |
|------------------|--------|------|----------|
| Complete objective function | 1-2 days | LOW | **P0** |
| Solver orchestration workflow | 1 day | LOW | **P0** |
| LP relaxation integration test | 1 day | LOW | **P0** |
| Solution export verification | 1 day | LOW | **P0** |
| Validation against DESSEM | 3-5 days | MEDIUM | **P0** |
| Infeasibility diagnostics | 2-3 days | LOW | **P1** |
| Constraint violation reporting | 2 days | LOW | **P1** |
| Warm start implementation | 3-5 days | MEDIUM | **P2** |
| Database loader completion | 3-5 days | MEDIUM | **P2** |
| Network-constrained dispatch | 10-15 days | HIGH | **P3** |

**Total MVP effort**: ~10-15 days (P0 features only)

## Research Confidence

**Overall confidence:** HIGH (based on existing codebase analysis and domain knowledge)

| Area | Confidence | Evidence |
|------|------------|----------|
| Table stakes features | HIGH | Standard hydrothermal dispatch formulation. Verified in existing code |
| Objective function components | HIGH | Already implemented in `ProductionCostObjective`. Just needs water value loading |
| LP relaxation for pricing | HIGH | Already implemented in `two_stage_pricing.jl`. Industry standard UC→SCED pattern |
| Solution export formats | HIGH | Already implemented CSV/JSON. Verified by code inspection |
| Validation requirements | HIGH | Official DESSEM sample data available in `docs/Sample/`. Framework already designed |
| Differentiators | MEDIUM | Based on PSR SDDP and PLEXOS feature sets (from training data, not recent docs) |
| Anti-features | HIGH | Clear scope boundary: day-ahead dispatch, not real-time or planning |

## Gaps to Address

### Known Gaps (from code inspection):

1. **Water Value Loading**: Need to load FCF curves from `infofcf.dat` and integrate into objective
   - File format: CSV with submarket, stage, FCF value
   - Already has `DessemLoader` framework
   - **Action**: Extend loader to parse FCF file

2. **End-to-End Integration Test**: No test that goes load→build→solve→extract→export
   - All components exist individually
   - Need workflow test with small sample system
   - **Action**: Create `test/integration/test_full_workflow.jl`

3. **Constraint Violation Reporting**: Can detect infeasibility but not which constraint
   - Need to iterate over constraints and check slack variables
   - **Action**: Add `report_constraint_violations()` to `solution_extraction.jl`

4. **Official DESSEM Output Parser**: Can load inputs but not official outputs for comparison
   - Need to parse DESSEM result files (`.csv` or binary)
   - **Action**: Add `parse_dessem_results()` to validation module

### Unknown Gaps (need investigation):

1. **Water Value Terminal Value Formulation**: How exactly does DESSEM penalize final storage?
   - Is it piecewise linear interpolation of FCF curves?
   - Is it per-reservoir or per-submarket?
   - **Action**: Research DESSEM documentation or reverse-engineer from sample files

2. **Reserve Requirements**: Does DESSEM include spinning reserves in base formulation?
   - Training data suggests "maybe" but code doesn't show it
   - **Action**: Check official DESSEM manual or sample constraint counts

3. **Transmission Loss Modeling**: Does network formulation include losses?
   - PowerModels supports lossy networks
   - Unclear if DESSEM includes losses or is lossless
   - **Action**: Check sample network files for loss coefficients

## Sources

**Evidence from codebase inspection:**
- `/home/pedro/programming/openDESSEM/src/objective/production_cost.jl` - Objective function implementation
- `/home/pedro/programming/openDESSEM/src/solvers/two_stage_pricing.jl` - LP relaxation for dual variables
- `/home/pedro/programming/openDESSEM/src/solvers/solution_extraction.jl` - PLD extraction via duals
- `/home/pedro/programming/openDESSEM/src/analysis/solution_exporter.jl` - CSV/JSON export
- `/home/pedro/programming/openDESSEM/docs/VALIDATION_FRAMEWORK_DESIGN.md` - Validation strategy
- `/home/pedro/programming/openDESSEM/docs/Sample/DS_ONS_102025_RV2D11/` - Official ONS sample data

**Domain knowledge (training data, Jan 2025 cutoff):**
- DESSEM: Brazilian day-ahead hydrothermal dispatch model (ONS official documentation)
- PSR SDDP: Commercial stochastic optimization suite (PSR Inc. product literature)
- PLEXOS: Commercial energy market simulation (Energy Exemplar documentation)
- Two-stage pricing (UC→SCED): Industry standard for extracting valid LMPs from MIP unit commitment
- Hydrothermal dispatch formulation: Standard operations research (Pereira & Pinto 1991, Wood & Wollenberg)

**Confidence assessment:**
- Table stakes features: HIGH confidence (verified in code, standard formulation)
- LP relaxation approach: HIGH confidence (already implemented, industry standard)
- Differentiators: MEDIUM confidence (based on training data about competing products, not verified via recent sources)
- Anti-features: HIGH confidence (clear problem scope, operational dispatch vs planning/real-time)
