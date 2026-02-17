---
status: complete
phase: 04-solution-extraction-export
source: [04-01-SUMMARY.md, 04-02-SUMMARY.md]
started: 2026-02-17T00:00:00Z
updated: 2026-02-17T00:07:00Z
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
  status: failed
  reason: "User reported: PLD are calculated from the nodal marginal pricing per bus, this should be calculated always (as the duals of each bus energy balance constraint)"
  severity: major
  test: 2
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
