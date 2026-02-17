---
status: diagnosed
phase: 04-solution-extraction-export
source: [04-01-SUMMARY.md, 04-02-SUMMARY.md, 04-03-SUMMARY.md]
started: 2026-02-17T00:00:00Z
updated: 2026-02-17T23:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Extract All Variable Types
expected: Running extract_solution_values!() on a solved model returns thermal_dispatch, thermal_commitment, hydro_storage, hydro_outflow, hydro_generation, renewable_generation, renewable_curtailment, and deficit values with correct keys (entity_id, time period).
result: pass

### 2. PLD Marginal Prices Extraction
expected: After solving with two-stage pricing (pricing=true), PLD dual values are extracted per submarket per time period in the result[:pld] Dict.
result: issue
reported: "Default behavior should try to solve nodal LMPs (bus-level via DC-OPF) and use zonal PLD (submarket duals) as fallback. Currently nodal LMPs require a separate explicit call to get_nodal_lmp_dataframe()."
severity: major

### 3. CSV Export
expected: export_csv(result, output_dir) creates dispatch.csv and prices.csv files with entity identifiers, time periods, and values in readable columns.
result: pass

### 4. JSON Export
expected: export_json(result, output_path) creates a valid JSON file with nested structure (dispatch, prices, costs sections) that can be parsed by JSON3.read().
result: pass

### 5. Constraint Violation Detection
expected: check_constraint_violations(model) returns a ViolationReport with zero violations when model is feasible, or lists violated constraints with magnitudes when infeasible.
result: pass

### 6. Violation Type Classification
expected: Violations are classified by type (thermal, hydro, balance, network, ramp) based on constraint naming patterns, visible in the violation report.
result: pass

### 7. Violation Report Text Output
expected: write_violation_report(report, filepath) creates a human-readable text file with sorted violations, magnitudes, and summary statistics.
result: pass

## Summary

total: 7
passed: 6
issues: 1
pending: 0
skipped: 0

## Gaps

- truth: "Default pricing attempts nodal LMPs (bus-level DC-OPF) first, falls back to zonal PLD (submarket duals)"
  status: diagnosed
  reason: "User reported: Default behavior should try to solve nodal LMPs and use zonal PLD as fallback. Currently nodal LMPs require separate explicit call."
  severity: major
  test: 2
  root_cause: "get_nodal_lmp_dataframe() exists but is standalone — not called during solve_model!() or extract_dual_values!(). The main pipeline only extracts submarket-level duals. Need to auto-call nodal LMP extraction in the solve/extract pipeline when network data is present, with zonal PLD as fallback when PowerModels unavailable or no network."
  artifacts:
    - path: "src/solvers/solution_extraction.jl"
      issue: "extract_dual_values!() only extracts submarket_balance duals; get_nodal_lmp_dataframe() exists but not integrated into pipeline"
      lines: "338-360, 970-1030"
    - path: "src/solvers/solver_interface.jl"
      issue: "solve_model!() does not attempt nodal LMP extraction after solve"
    - path: "src/solvers/solution_extraction.jl"
      issue: "get_pld_dataframe() returns only submarket duals, does not attempt nodal first"
  missing:
    - "Integrate nodal LMP extraction into solve pipeline (auto-call after LP pricing stage when network data available)"
    - "Update get_pld_dataframe() or create unified pricing function: try nodal LMPs first, fall back to zonal PLD"
    - "Store nodal LMPs in SolverResult so they don't need recomputation"
    - "Include nodal LMPs in CSV/JSON export when available"
  debug_session: "ses_3928fccc6ffeRXnj0HtTsIi9mw"
