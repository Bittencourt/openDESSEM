# Requirements: OpenDESSEM Phase 3

**Defined:** 2026-02-15
**Core Value:** End-to-end solve pipeline that loads ONS data, builds full SIN model, solves, and extracts validated dispatch + PLD marginal prices matching official DESSEM within 5%.

## v1 Requirements

Requirements for Phase 3 completion. Each maps to roadmap phases.

### Objective Function

- [ ] **OBJ-01**: Complete production cost objective with fuel cost, startup cost, and shutdown cost terms for all thermal plants
- [ ] **OBJ-02**: Implement water value / future cost function (FCF) loading from infofcf.dat and integration into objective as terminal period water value
- [ ] **OBJ-03**: Implement load shedding penalty variables and costs with proper variable creation in VariableManager
- [ ] **OBJ-04**: Apply numerical scaling to objective coefficients for solver stability across different cost magnitudes

### Solver Interface

- [ ] **SOLV-01**: Implement end-to-end solve orchestration: build variables, add constraints, set objective, optimize, extract results
- [ ] **SOLV-02**: Implement two-stage pricing: solve MILP for unit commitment, fix binary variables, solve LP relaxation, extract dual values for PLD
- [ ] **SOLV-03**: Support multi-solver backends via lazy loading: HiGHS (primary), Gurobi, CPLEX, GLPK
- [ ] **SOLV-04**: Handle solver status (optimal, infeasible, time limit) with diagnostic messages and infeasibility analysis

### Hydro Modeling

- [ ] **HYDR-01**: Load real hydrological inflow data from DESSEM files (vazaolateral.csv) replacing hardcoded zero inflows
- [ ] **HYDR-02**: Implement cascade water delay logic: upstream outflows propagate to downstream plants with travel time delay
- [ ] **HYDR-03**: Build cascade topology utility: construct plant dependency DAG, compute depths, detect cycles

### Solution Extraction

- [ ] **EXTR-01**: Extract all optimization variable values: thermal dispatch, hydro storage/outflow/generation, renewable generation/curtailment
- [ ] **EXTR-02**: Extract PLD marginal prices per submarket per time period from LP relaxation dual variables
- [ ] **EXTR-03**: Export dispatch and prices to CSV format with clear column headers and entity identifiers
- [ ] **EXTR-04**: Export dispatch and prices to JSON format for programmatic consumption
- [ ] **EXTR-05**: Report constraint violations with magnitude and constraint type identification

### Validation

- [ ] **VALD-01**: Create end-to-end integration test loading ONS sample data (DS_ONS_102025_RV2D11), solving, and extracting results
- [ ] **VALD-02**: Total optimization cost matches official DESSEM within 5% relative tolerance
- [ ] **VALD-03**: Per-submarket PLD prices match official DESSEM within acceptable tolerance (to be determined during validation)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Performance Optimization

- **PERF-01**: Warm-start solver from previous solve solution
- **PERF-02**: Solver auto-detection and thread count recommendation based on system size
- **PERF-03**: Constraint generation ordering for improved solver performance

### Advanced Hydro

- **AHYDR-01**: Nonlinear hydro efficiency curves via piecewise linear approximation
- **AHYDR-02**: CVaR risk-averse water value formulation

### Extended Export

- **XPRT-01**: Export solution results to PostgreSQL database
- **XPRT-02**: Arrow.jl binary export for large-scale result datasets
- **XPRT-03**: Per-plant dispatch comparison against official DESSEM

### Network Enhancement

- **NETW-01**: Complete PowerModels network constraint coupling (apply constraints, not just validate)
- **NETW-02**: AC-OPF with MILP relaxation for improved network accuracy

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Stochastic UC with scenario trees | Future milestone; deterministic dispatch only for Phase 3 |
| Combined-cycle mode transition scheduling | Entity exists but advanced scheduling adds significant complexity |
| Real-time ONS/CCEE API data connectors | Production deployment concern, not model correctness |
| Web UI or REST API server | CLI/script-based workflow sufficient for Phase 3 |
| Docker/cloud deployment | Infrastructure concern, not model concern |
| Decomposition algorithms (Benders, DW) | Performance optimization beyond Phase 3 scope |
| Rolling/receding horizon dispatch | Advanced operational feature for future milestone |
| Environmental/carbon constraints | Extension feature beyond core DESSEM functionality |
| Custom solver development | Use existing proven solvers (HiGHS, Gurobi) |
| SDDP.jl medium-term model linking | Phase 4+ feature requiring stochastic framework |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| OBJ-01 | TBD | Pending |
| OBJ-02 | TBD | Pending |
| OBJ-03 | TBD | Pending |
| OBJ-04 | TBD | Pending |
| SOLV-01 | TBD | Pending |
| SOLV-02 | TBD | Pending |
| SOLV-03 | TBD | Pending |
| SOLV-04 | TBD | Pending |
| HYDR-01 | TBD | Pending |
| HYDR-02 | TBD | Pending |
| HYDR-03 | TBD | Pending |
| EXTR-01 | TBD | Pending |
| EXTR-02 | TBD | Pending |
| EXTR-03 | TBD | Pending |
| EXTR-04 | TBD | Pending |
| EXTR-05 | TBD | Pending |
| VALD-01 | TBD | Pending |
| VALD-02 | TBD | Pending |
| VALD-03 | TBD | Pending |

**Coverage:**
- v1 requirements: 19 total
- Mapped to phases: 0 (pending roadmap creation)
- Unmapped: 19

---
*Requirements defined: 2026-02-15*
*Last updated: 2026-02-15 after initial definition*
