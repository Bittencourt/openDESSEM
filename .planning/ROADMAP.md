# Roadmap: OpenDESSEM Phase 3 Completion

**Created:** 2026-02-15
**Depth:** Standard (5 phases)
**Coverage:** 19/19 v1 requirements mapped

## Overview

Complete the solver pipeline for OpenDESSEM by finishing the objective function builder, hydro modeling gaps, solver orchestration, solution extraction, and validation against official DESSEM results. The foundation (entities, constraints, variables, 980+ tests) is complete. This roadmap focuses on the final 5% needed to deliver end-to-end solve capability with validated dispatch and marginal pricing.

---

## Phase 1: Objective Function Completion

**Goal:** Users can build a complete production cost objective with all cost terms ready for optimization

**Dependencies:** None (foundation layer complete)

**Requirements:** OBJ-01, OBJ-02, OBJ-03, OBJ-04

**Plans:** 3 plans in 2 waves

**Success Criteria:**
1. Objective function includes fuel cost for all thermal plants across all time periods
2. Objective function includes startup and shutdown costs for thermal unit commitment
3. Objective function includes terminal period water value from FCF curves loaded from infofcf.dat
4. Objective function includes load shedding penalty variables and costs
5. All cost coefficients are numerically scaled (1e-6 factor) to prevent solver instability

**Plans:**
- [x] 01-01-PLAN.md — FCF curve loader for water values
- [x] 01-02-PLAN.md — Load shedding and deficit variables
- [x] 01-03-PLAN.md — Complete objective with FCF and scaling

---

## Phase 2: Hydro Modeling Completion

**Goal:** Hydro plants operate with realistic cascade topology and inflow data

**Dependencies:** Phase 1 (objective must exist to value water)

**Requirements:** HYDR-01, HYDR-02, HYDR-03

**Plans:** 3 plans in 2 waves

**Success Criteria:**
1. Hydrological inflows load from dadvaz.dat DESSEM files instead of hardcoded zeros
2. Cascade water delays work correctly (upstream outflows reach downstream after travel time)
3. Cascade topology utility detects circular dependencies and computes plant depths
4. Water balance constraints use correct unit conversions (m³/s to hm³ with 0.0036 factor)

**Plans:**
- [ ] 02-01-PLAN.md — Cascade topology utility with cycle detection
- [ ] 02-02-PLAN.md — Inflow data loading from dadvaz.dat
- [ ] 02-03-PLAN.md — Water balance with cascade and inflows

---

## Phase 3: Solver Interface Implementation

**Goal:** Users can solve the full MILP model and extract dual variables via two-stage pricing

**Dependencies:** Phase 1 (objective), Phase 2 (hydro constraints)

**Requirements:** SOLV-01, SOLV-02, SOLV-03, SOLV-04

**Success Criteria:**
1. End-to-end workflow executes: load system, create variables, build constraints, set objective, optimize, extract results
2. Two-stage pricing works: solve MILP for unit commitment, fix binaries, solve LP relaxation, extract PLD duals
3. Multi-solver support verified with HiGHS (primary), Gurobi, CPLEX, GLPK via lazy loading
4. Solver status handling reports optimal, infeasible, time limit with diagnostic messages and infeasibility analysis
5. Small test case (3-5 plants) solves successfully and produces expected cost magnitude

---

## Phase 4: Solution Extraction & Export

**Goal:** Users can extract all solution data and export to standard formats with constraint violation reporting

**Dependencies:** Phase 3 (model must be solved)

**Requirements:** EXTR-01, EXTR-02, EXTR-03, EXTR-04, EXTR-05

**Success Criteria:**
1. All primal variable values extract correctly: thermal dispatch/commitment, hydro storage/outflow/generation, renewable generation/curtailment
2. PLD marginal prices extract per submarket per time period from LP relaxation dual variables
3. CSV export produces readable dispatch and price files with entity identifiers and timestamps
4. JSON export produces nested structure suitable for programmatic consumption
5. Constraint violation report identifies violated constraints with magnitudes and types

---

## Phase 5: End-to-End Validation

**Goal:** OpenDESSEM produces results matching official DESSEM within acceptable tolerance on ONS sample data

**Dependencies:** Phase 4 (extraction), Phase 3 (solver), Phase 2 (hydro), Phase 1 (objective)

**Requirements:** VALD-01, VALD-02, VALD-03

**Success Criteria:**
1. Integration test loads ONS sample data DS_ONS_102025_RV2D11, solves model, and extracts results without errors
2. Total optimization cost matches official DESSEM within 5% relative tolerance
3. Per-submarket PLD marginal prices match official DESSEM trends (correlation > 0.85, qualitative validation)
4. Validation report documents input data comparison, solution metrics, and tolerance checks

---

## Progress

| Phase | Status | Requirements | Progress |
|-------|--------|--------------|----------|
| 1 - Objective Function | ✓ Complete (2026-02-15) | OBJ-01, OBJ-02, OBJ-03, OBJ-04 | 5/5 criteria |
| 2 - Hydro Modeling | Planned | HYDR-01, HYDR-02, HYDR-03 | 0/4 criteria |
| 3 - Solver Interface | Not Started | SOLV-01, SOLV-02, SOLV-03, SOLV-04 | 0/5 criteria |
| 4 - Solution Extraction | Not Started | EXTR-01, EXTR-02, EXTR-03, EXTR-04, EXTR-05 | 0/5 criteria |
| 5 - Validation | Not Started | VALD-01, VALD-02, VALD-03 | 0/4 criteria |

**Overall:** 5/23 success criteria complete

---

## Phase Details

### Phase 1 Notes

**Key deliverables:**
- Complete `build_objective!()` in src/objective/production_cost.jl
- Implement FCF curve loader from infofcf.dat
- Add load shedding variables to VariableManager
- Apply COST_SCALE = 1e-6 uniformly to all cost coefficients

**Research flags:** Standard JuMP patterns (no research-phase needed)

**Estimated effort:** 3-5 days

---

### Phase 2 Notes

**Key deliverables:**
- Extend DessemLoader to parse vazaolateral.csv for inflow forecasts
- Complete cascade logic in hydro_water_balance.jl (uncomment lines 224-228)
- Implement cascade topology builder: construct DAG, compute depths, detect cycles
- Add production coefficient constraint linking turbine flow to generation

**Research flags:** Inflow file format parsing may need investigation if documentation sparse

**Estimated effort:** 3-5 days

---

### Phase 3 Notes

**Key deliverables:**
- Implement `solve_model()` orchestration function
- Verify two_stage_pricing.jl works end-to-end
- Add solver auto-detection and lazy loading for Gurobi/CPLEX/GLPK
- Implement termination status checking and infeasibility diagnostics

**Research flags:** Standard MOI patterns (no research-phase needed)

**Estimated effort:** 4-6 days

---

### Phase 4 Notes

**Key deliverables:**
- Complete extraction of all variable types in solution_extraction.jl
- Verify PLD dual extraction from energy balance constraints
- Implement CSV/JSON export with proper formatting
- Add constraint violation reporting with magnitude/type identification

**Research flags:** Standard extraction patterns (no research-phase needed)

**Estimated effort:** 3-4 days

---

### Phase 5 Notes

**Key deliverables:**
- Create integration test for ONS sample case DS_ONS_102025_RV2D11
- Implement tolerance checking (5% total cost, trend correlation for PLD)
- Generate validation report comparing OpenDESSEM vs official DESSEM
- Document any deviations and root cause analysis

**Research flags:** DESSEM binary output parsing may need investigation

**Estimated effort:** 5-7 days

---

**Total estimated effort:** 18-27 days across 5 phases

**Critical path:** Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 (sequential dependencies)

---

*Roadmap created: 2026-02-15*
*Next: `/gsd:plan-phase 1` to begin Phase 1 execution*
