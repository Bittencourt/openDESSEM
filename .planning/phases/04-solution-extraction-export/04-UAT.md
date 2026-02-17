---
status: diagnosed
phase: 04-solution-extraction-export
source: [04-01-SUMMARY.md, 04-02-SUMMARY.md]
started: 2026-02-17T00:00:00Z
updated: 2026-02-17T00:10:00Z
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
reported: "PLD are calculated from the nodal marginal pricing per bus, this should be calculated always (as the duals of each bus energy balance constraint)"
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

- truth: "PLD marginal prices extracted from bus-level energy balance duals (nodal marginal pricing)"
  status: diagnosed
  reason: "User reported: PLD are calculated from the nodal marginal pricing per bus, this should be calculated always (as the duals of each bus energy balance constraint)"
  severity: major
  test: 2
  root_cause: "PLD extraction uses submarket-level energy balance duals instead of bus-level nodal marginal pricing. PowerModels DC-OPF integration exists as a standalone function (solve_dc_opf_nodal_lmps) but is NOT integrated into the main solve pipeline. The NetworkPowerModelsConstraint only validates data without creating bus-level balance constraints, and extract_dual_values!() has no code to extract bus-level duals."
  artifacts:
    - path: "src/solvers/solution_extraction.jl"
      issue: "extract_dual_values!() only extracts submarket_balance duals, no bus_balance extraction"
      lines: "338-360, 657-710"
    - path: "src/constraints/network_powermodels.jl"
      issue: "Placeholder only - validates data but does NOT integrate PowerModels DC-OPF or create bus-level balance constraints"
      lines: "130-138"
    - path: "src/integration/Integration.jl"
      issue: "solve_dc_opf_nodal_lmps exists but is standalone/separate from main solve pipeline"
      lines: "156-204"
  missing:
    - "Integrate PowerModels DC-OPF into main solve pipeline (NetworkPowerModelsConstraint needs full implementation)"
    - "Create bus-level energy balance constraints (model[:bus_balance][(bus_id, t)])"
    - "Add bus_balance dual extraction to extract_dual_values!()"
    - "Create get_nodal_lmp_dataframe() or get_bus_lmp_dataframe() for bus-level LMP extraction"
    - "Ensure nodal pricing is always calculated when network data is available"
  debug_session: "ses_3928fccc6ffeRXnj0HtTsIi9mw"
