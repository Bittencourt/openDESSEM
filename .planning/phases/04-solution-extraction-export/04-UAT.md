---
status: complete
phase: 04-solution-extraction-export
source: [04-01-SUMMARY.md, 04-02-SUMMARY.md, 04-03-SUMMARY.md, 04-04-SUMMARY.md]
started: 2026-02-17T23:30:00Z
updated: 2026-02-17T23:42:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Extract All Variable Types from Solved Model
expected: Running extract_solution_values!() on a solved model populates result with thermal dispatch/commitment, hydro storage/outflow/generation, renewable generation/curtailment, and deficit values. Keys are (entity_id, period) tuples.
result: pass

### 2. PLD Zonal Pricing via Two-Stage Solve
expected: After solve_model!(model, system; pricing=true), calling get_pld_dataframe(result) returns a DataFrame with columns submarket, period, and pld containing per-submarket per-period marginal prices from LP relaxation duals.
result: pass

### 3. Unified Pricing with Nodal-First Fallback
expected: get_pricing_dataframe(result, system) returns nodal LMPs (bus_id, lmp columns) when result.nodal_lmps is populated, or falls back to zonal PLD (submarket, pld columns) when nodal data unavailable. Passing level=:zonal forces zonal even when nodal exists.
result: pass

### 4. CSV Export with Nodal LMPs
expected: export_csv(result, output_dir) creates dispatch CSV files for each plant type plus submarket_lmps.csv. When result.nodal_lmps is populated, also creates nodal_lmps.csv with bus_id, bus_name, period, lmp columns.
result: pass

### 5. JSON Export with Nodal Section
expected: export_json(result, filepath) produces valid JSON with nested structure including dispatch, dual_values, and statistics. When result.nodal_lmps is populated, the JSON includes a nodal_lmps section keyed by bus_id with nested lmps per period.
result: pass

### 6. Constraint Violation Detection
expected: check_constraint_violations(model) returns a ViolationReport. On a feasible solved model, the report has zero total violations. On an infeasible model, it lists specific violated constraints with magnitude values.
result: pass

### 7. Violation Type Classification and Report
expected: Each ConstraintViolation has a type field classified as thermal/hydro/balance/network/ramp/unknown. write_violation_report(report, filepath) creates a human-readable text file with violations sorted by magnitude and summary statistics.
result: pass

### 8. Nodal LMP Auto-Extraction in Solve Pipeline
expected: After solve_model!(), result.nodal_lmps is automatically populated (DataFrame) when the system has buses and lines, or remains nothing when no network data. If nodal extraction fails (e.g. PowerModels unavailable), the solve still completes successfully with a warning.
result: pass

## Summary

total: 8
passed: 8
issues: 0
pending: 0
skipped: 0

## Gaps

[none]
