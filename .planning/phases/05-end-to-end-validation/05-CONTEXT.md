# Phase 5: End-to-End Validation - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Validate OpenDESSEM results against official DESSEM reference outputs. Compare total cost, PLD marginal prices, and dispatch decisions to prove correctness. This phase proves the solver produces valid results - it does not add new solving capabilities.

**Key scope:**
- Compare against reference files in sample data folders
- Report pass/fail with detailed diagnostics
- Support CI integration via exit codes

**Out of scope:**
- New solver features
- Performance optimization
- Binary output file parsing (reference files are pre-generated CSV/JSON)

</domain>

<decisions>
## Implementation Decisions

### Reference Data Source
- Reference output files located in sample data folders (e.g., `docs/Sample/DS_ONS_102025_RV2D11/expected/`)
- Support both CSV and JSON formats for reference data (CSV is default)
- Reference files contain complete results: PLDs per period, dispatch per plant per period, storage trajectories
- Validation is for testing only - actual usage does not compare against official DESSEM outputs
- User can specify format preference when running validation

### Validation Metrics & Scope
- **Total cost**: 5% relative tolerance (OpenDESSEM within 5% of reference)
- **PLD comparison**: Pass rate threshold approach (not correlation)
  - Configurable thresholds: user sets pass rate % and tolerance %
  - Example: "90% of periods must be within 15% tolerance"
- **Dispatch comparison**: Per-plant per-period granularity (most detailed)
  - Compare each plant's generation at each time period
  - Tolerance configurable per validation run

### Report Format
- Generate all three formats: Console, Markdown, and JSON
- **Console output**: Sectioned summary
  - One section per metric type (cost, PLD, dispatch)
  - Each section shows pass/fail status
  - Not verbose - key results only
- **Markdown report**: Complete comparison
  - Full comparison tables for ALL metrics regardless of pass/fail
  - Include expected vs actual values
  - Suitable for review and documentation
- **JSON report**: Structured output
  - Machine-readable for programmatic consumption
  - Mirrors markdown content in JSON structure

### Failure Handling
- **Behavior**: Collect all failures
  - Continue all comparisons even when failures occur
  - Report complete results at end (no early termination)
- **Diagnostics**: Show deltas for failed comparisons
  - Display expected value, actual value, and difference
  - For each failed comparison, show the specific discrepancy
- **Return value**: Detailed struct
  - Return `ValidationResult` struct with pass/fail status, detailed metrics, and per-comparison results
  - Not just boolean - full introspection available
- **CLI exit codes**: Coded by failure type for CI integration
  - 0 = All validations passed
  - 1 = Total cost failed tolerance
  - 2 = PLD validation failed
  - 3 = Dispatch validation failed
  - (Combinations possible via bit flags if needed)

### OpenCode's Discretion
- Exact `ValidationResult` struct field names and types
- Default values for configurable thresholds (suggest: 80% pass rate, 10% tolerance)
- Exact markdown table formatting
- Error message wording
- How to handle missing reference data (skip metric vs fail validation)

</decisions>

<specifics>
## Specific Ideas

- Reference files should be in an `expected/` subfolder within each sample case directory
- PLD comparison uses pass rate approach because correlation can be misleading (e.g., both trending together but offset)
- Per-plant per-period dispatch comparison ensures no individual plant is badly wrong even if totals match
- Exit codes enable CI pipelines: `openDESSEM validate && echo "Ready for production"`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 05-end-to-end-validation*
*Context gathered: 2026-02-17*
