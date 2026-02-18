# Phase 5: End-to-End Validation - Research

**Researched:** 2026-02-17
**Domain:** Optimization result validation against reference DESSEM outputs
**Confidence:** HIGH

## Summary

Phase 5 validates that OpenDESSEM produces correct results by comparing its outputs against official DESSEM reference data from ONS (Operador Nacional do Sistema Eletrico). The reference data already exists in the repository as PDO (Post-Dispatch Output) files within the sample data directories. These files contain semicolon-delimited tabular data with system-level CMOs (marginal costs), per-plant dispatch values, and hydro storage trajectories across all 75 time periods.

The implementation requires three main components: (1) reference data extraction from PDO files or pre-generated CSV/JSON into a normalized format, (2) a comparison engine that evaluates total cost, PLD pass-rates, and per-plant dispatch against configurable tolerances, and (3) a multi-format reporting system producing console, Markdown, and JSON outputs. The existing `Analysis` module and `SolverResult` type provide natural extension points.

**Primary recommendation:** Build validation as a new submodule (`src/validation/`) under `Analysis`, with reference data parsers for the PDO output format. Create `expected/` directories containing pre-extracted CSV reference data from the PDO files, since the CONTEXT.md specifies reference files are pre-generated CSV/JSON (not binary parsing).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Reference Data Source
- Reference output files located in sample data folders (e.g., `docs/Sample/DS_ONS_102025_RV2D11/expected/`)
- Support both CSV and JSON formats for reference data (CSV is default)
- Reference files contain complete results: PLDs per period, dispatch per plant per period, storage trajectories
- Validation is for testing only - actual usage does not compare against official DESSEM outputs
- User can specify format preference when running validation

#### Validation Metrics & Scope
- **Total cost**: 5% relative tolerance (OpenDESSEM within 5% of reference)
- **PLD comparison**: Pass rate threshold approach (not correlation)
  - Configurable thresholds: user sets pass rate % and tolerance %
  - Example: "90% of periods must be within 15% tolerance"
- **Dispatch comparison**: Per-plant per-period granularity (most detailed)
  - Compare each plant's generation at each time period
  - Tolerance configurable per validation run

#### Report Format
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

#### Failure Handling
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

### Claude's Discretion
- Exact `ValidationResult` struct field names and types
- Default values for configurable thresholds (suggest: 80% pass rate, 10% tolerance)
- Exact markdown table formatting
- Error message wording
- How to handle missing reference data (skip metric vs fail validation)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia Test.jl | stdlib | Test assertions and testsets | Built-in, already used throughout project |
| CSV.jl | already in deps | Read reference CSV files | Already a project dependency |
| DataFrames.jl | already in deps | Tabular data manipulation | Already a project dependency |
| JSON3.jl | already in deps | Read/write JSON reference/reports | Already a project dependency |
| Printf | stdlib | Formatted console output | Built-in, used in examples |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Dates | stdlib | Timestamps for reports | Report generation |
| Statistics | stdlib | Mean/median for summary stats | Computing aggregate metrics |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom CSV parsing | DelimitedFiles.jl | CSV.jl already in deps, more robust |
| Custom struct comparison | DeepDiffs.jl | Overkill; simple numeric diffs suffice |

**Installation:** No new packages needed. All required packages are already in the project's dependencies.

## Architecture Patterns

### Recommended Project Structure
```
src/
├── validation/                     # NEW: Validation module
│   ├── Validation.jl               # Module definition and exports
│   ├── validation_types.jl         # ValidationResult, MetricComparison, etc.
│   ├── reference_loader.jl         # Load CSV/JSON reference data
│   ├── comparators.jl              # Cost, PLD, dispatch comparison logic
│   └── reporters.jl                # Console, Markdown, JSON report generators
├── analysis/
│   └── Analysis.jl                 # Updated to include Validation submodule
docs/Sample/
├── DS_ONS_102025_RV2D11/
│   ├── expected/                   # NEW: Pre-extracted reference data
│   │   ├── total_cost.csv          # Expected total cost
│   │   ├── pld_by_submarket.csv    # Expected PLDs per submarket per period
│   │   ├── thermal_dispatch.csv    # Expected thermal dispatch per plant per period
│   │   ├── hydro_dispatch.csv      # Expected hydro dispatch per plant per period
│   │   └── hydro_storage.csv       # Expected hydro storage trajectories
│   └── [existing PDO files]
test/
├── validation/                     # NEW: Validation tests
│   ├── test_validation_types.jl    # Tests for ValidationResult, comparisons
│   ├── test_reference_loader.jl    # Tests for CSV/JSON loading
│   ├── test_comparators.jl         # Tests for comparison logic
│   └── test_reporters.jl           # Tests for report generation
└── integration/
    └── test_end_to_end_validation.jl  # NEW: Full validation integration test
```

### Pattern 1: Accumulating Validator (Collect-All-Then-Report)
**What:** Run all comparisons, collect every result (pass or fail), then generate comprehensive report.
**When to use:** Required by CONTEXT.md: "Continue all comparisons even when failures occur."
**Example:**
```julia
# Core pattern: accumulate all comparison results
function validate_against_reference(
    result::SolverResult,
    reference_dir::String;
    cost_tolerance::Float64 = 0.05,
    pld_pass_rate::Float64 = 0.80,
    pld_tolerance::Float64 = 0.10,
    dispatch_tolerance::Float64 = 0.10,
)::ValidationResult
    comparisons = MetricComparison[]

    # Total cost comparison (never skip, always run)
    cost_ref = load_reference_cost(reference_dir)
    if cost_ref !== nothing
        push!(comparisons, compare_total_cost(result, cost_ref, cost_tolerance))
    else
        push!(comparisons, MetricComparison(
            metric_type = :cost,
            status = :skipped,
            reason = "Reference cost file not found"
        ))
    end

    # PLD comparison
    pld_ref = load_reference_pld(reference_dir)
    if pld_ref !== nothing
        push!(comparisons, compare_pld(result, pld_ref, pld_pass_rate, pld_tolerance))
    else
        push!(comparisons, MetricComparison(
            metric_type = :pld,
            status = :skipped,
            reason = "Reference PLD file not found"
        ))
    end

    # Dispatch comparison
    dispatch_ref = load_reference_dispatch(reference_dir)
    if dispatch_ref !== nothing
        append!(comparisons, compare_dispatch(result, dispatch_ref, dispatch_tolerance))
    else
        push!(comparisons, MetricComparison(
            metric_type = :dispatch,
            status = :skipped,
            reason = "Reference dispatch file not found"
        ))
    end

    return ValidationResult(comparisons)
end
```

### Pattern 2: Three-Output Reporter
**What:** Generate console, Markdown, and JSON from same data.
**When to use:** Every validation run (all three required by CONTEXT.md).
**Example:**
```julia
function report_validation(vr::ValidationResult; output_dir::String = ".")
    # Console: compact sectioned summary
    print_console_report(vr)

    # Markdown: full tables with expected vs actual
    md_path = joinpath(output_dir, "validation_report.md")
    write_markdown_report(vr, md_path)

    # JSON: structured mirror of markdown content
    json_path = joinpath(output_dir, "validation_report.json")
    write_json_report(vr, json_path)

    return (md_path, json_path)
end
```

### Pattern 3: Exit Code Calculation from ValidationResult
**What:** Map validation failures to CLI exit codes using bit flags.
**When to use:** CI integration.
**Example:**
```julia
function validation_exit_code(vr::ValidationResult)::Int
    code = 0
    if !vr.cost_passed
        code |= 1  # bit 0: cost failed
    end
    if !vr.pld_passed
        code |= 2  # bit 1: PLD failed
    end
    if !vr.dispatch_passed
        code |= 4  # bit 2: dispatch failed (using 4 not 3 for clean bit flags)
    end
    return code
end
```
**Note on exit codes:** The CONTEXT.md specifies exit codes 1, 2, 3 but also mentions "combinations possible via bit flags." Using 1, 2, 4 for clean bit flags is recommended. However, the user specified exact codes 1, 2, 3 so the planner should follow those unless bit-flag combinations are needed. If sticking with 1/2/3, then the highest-priority failure code wins (e.g., cost=1 takes precedence).

### Anti-Patterns to Avoid
- **Early termination on failure:** Do NOT stop validation when first comparison fails. Collect all results first.
- **Correlation-based PLD comparison:** Do NOT use Pearson correlation. Use pass-rate threshold as specified.
- **Parsing PDO binary files at validation time:** Reference files are pre-generated CSV/JSON. Do NOT parse raw DESSEM output during validation.
- **Hardcoded tolerances:** All thresholds must be configurable parameters, not constants.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CSV reading | Custom parser | CSV.jl + DataFrames.jl | Already in deps, handles edge cases |
| JSON serialization | String concatenation | JSON3.jl | Already in deps, handles escaping |
| Relative tolerance comparison | Manual `abs(a-b)/max(abs(a),abs(b))` | Well-tested helper function | Division by zero, sign handling |
| DataFrame operations | Manual loops over dicts | DataFrames.jl joins/filters | Already used throughout codebase |

**Key insight:** The validation module is primarily glue code connecting existing infrastructure (SolverResult, CSV.jl, JSON3.jl) with comparison logic. Keep it thin.

## Common Pitfalls

### Pitfall 1: Division by Zero in Relative Tolerance
**What goes wrong:** Comparing actual vs expected when expected = 0 causes division by zero in relative tolerance calculation.
**Why it happens:** Some periods have zero PLD (e.g., `FC` submarket always has CMO = 0.00 in reference data), and some plants have zero dispatch.
**How to avoid:** Use safe relative difference: `abs(actual - expected) / max(abs(expected), epsilon)` where epsilon is a small positive number (e.g., 1e-10). Or skip comparison when expected is below a minimum threshold.
**Warning signs:** NaN or Inf in comparison results.

### Pitfall 2: Mismatched Identifiers Between OpenDESSEM and Reference
**What goes wrong:** Plant IDs in OpenDESSEM (e.g., "T001", "H_SE_001") don't match reference data plant IDs (e.g., "ANGRA 1", USIT code 001).
**Why it happens:** OpenDESSEM uses its own entity ID scheme; DESSEM output uses USIT/USIH codes and names.
**How to avoid:** Reference CSV files should use the same ID scheme as OpenDESSEM entities. This is part of the pre-generation step: extract from PDO files using OpenDESSEM's ID mapping.
**Warning signs:** Empty comparison results, "plant not found" warnings.

### Pitfall 3: Time Period Indexing Mismatch
**What goes wrong:** OpenDESSEM uses 1-indexed periods (1:75); reference data might use different indexing or duration conventions.
**Why it happens:** PDO files use IPER field (1-based) but with variable durations (0.5h for first 48, then multi-hour).
**How to avoid:** Reference CSVs should include explicit period indices matching OpenDESSEM's convention. Include period duration in reference data so energy comparisons account for it.
**Warning signs:** Systematic offset in all comparisons.

### Pitfall 4: Scaled vs Unscaled Cost Values
**What goes wrong:** OpenDESSEM objective uses `COST_SCALE = 1e-6` for solver stability. Comparing scaled objective value against unscaled reference cost gives wrong results.
**Why it happens:** `result.objective_value` is in scaled units; reference total cost from DESSEM is in actual R$.
**How to avoid:** Use `get_cost_breakdown(result, system).total` which returns unscaled R$ values, or multiply objective_value by 1/COST_SCALE. Document clearly which is used.
**Warning signs:** Cost comparison off by exactly 1e6.

### Pitfall 5: PLD Scaling from Duals
**What goes wrong:** PLD values from `get_pld_dataframe()` are already scaled by PLD_SCALE (1e6). Double-scaling if not careful.
**Why it happens:** The extraction functions handle scaling internally. If you also apply PLD_SCALE, values are wrong.
**How to avoid:** Use `get_pld_dataframe()` which returns correctly-scaled R$/MWh values. Don't manually scale again.
**Warning signs:** PLD values 1e6 times too large or too small.

### Pitfall 6: FC (Fictitious) Submarket Noise
**What goes wrong:** The FC submarket in DESSEM reference data always has CMO = 0.00. Including it inflates pass rates artificially.
**Why it happens:** FC is a fictitious submarket used for accounting, not a real market.
**How to avoid:** Either exclude FC from PLD comparison or note it explicitly. The four real submarkets are SE, S, NE, N.
**Warning signs:** Suspiciously high pass rates that drop when FC is excluded.

## Code Examples

Verified patterns from the existing codebase:

### Loading Reference CSV Data
```julia
# Pattern from existing CSV.jl usage in solution_exporter.jl
using CSV
using DataFrames

function load_reference_pld(reference_dir::String; format::Symbol = :csv)::Union{DataFrame, Nothing}
    if format == :csv
        filepath = joinpath(reference_dir, "pld_by_submarket.csv")
        if !isfile(filepath)
            @warn "Reference PLD file not found" filepath = filepath
            return nothing
        end
        return CSV.read(filepath, DataFrame)
    elseif format == :json
        filepath = joinpath(reference_dir, "pld_by_submarket.json")
        if !isfile(filepath)
            @warn "Reference PLD file not found" filepath = filepath
            return nothing
        end
        json_data = JSON3.read(read(filepath, String))
        # Convert JSON to DataFrame
        return _json_to_pld_dataframe(json_data)
    end
end
```

### Comparing PLD with Pass-Rate Threshold
```julia
# Using the pass-rate approach specified in CONTEXT.md
function compare_pld(
    actual_df::DataFrame,      # From get_pld_dataframe()
    reference_df::DataFrame,   # From load_reference_pld()
    pass_rate_threshold::Float64,  # e.g., 0.80
    tolerance::Float64,           # e.g., 0.10
)::MetricComparison
    # Join on (submarket, period)
    joined = innerjoin(actual_df, reference_df;
        on = [:submarket, :period],
        makeunique = true
    )

    comparisons = PLDComparison[]
    for row in eachrow(joined)
        actual_pld = row.pld
        expected_pld = row.pld_1  # from reference

        # Safe relative difference
        if abs(expected_pld) < 1e-10
            within_tolerance = abs(actual_pld) < 1e-10  # Both ~zero
        else
            rel_diff = abs(actual_pld - expected_pld) / abs(expected_pld)
            within_tolerance = rel_diff <= tolerance
        end

        push!(comparisons, PLDComparison(
            submarket = row.submarket,
            period = row.period,
            expected = expected_pld,
            actual = actual_pld,
            passed = within_tolerance
        ))
    end

    total = length(comparisons)
    passed = count(c -> c.passed, comparisons)
    actual_pass_rate = total > 0 ? passed / total : 0.0

    return MetricComparison(
        metric_type = :pld,
        status = actual_pass_rate >= pass_rate_threshold ? :passed : :failed,
        pass_rate = actual_pass_rate,
        threshold = pass_rate_threshold,
        tolerance = tolerance,
        details = comparisons,
        total_comparisons = total,
        passed_comparisons = passed
    )
end
```

### Console Report Section Pattern
```julia
# Compact sectioned output matching CONTEXT.md "not verbose - key results only"
function _print_cost_section(io::IO, comparison::MetricComparison)
    status_str = comparison.status == :passed ? "PASS" : "FAIL"
    println(io, "--- Total Cost ---")
    println(io, "  Status: $status_str")
    if comparison.status == :passed
        @printf(io, "  Expected: R\$ %.2f\n", comparison.expected)
        @printf(io, "  Actual:   R\$ %.2f\n", comparison.actual)
        @printf(io, "  Tolerance: %.1f%%\n", comparison.tolerance * 100)
    else
        @printf(io, "  Expected: R\$ %.2f\n", comparison.expected)
        @printf(io, "  Actual:   R\$ %.2f\n", comparison.actual)
        @printf(io, "  Delta:    R\$ %.2f (%.1f%%)\n",
            comparison.actual - comparison.expected,
            comparison.relative_diff * 100)
        @printf(io, "  Tolerance: %.1f%% EXCEEDED\n", comparison.tolerance * 100)
    end
    println(io)
end
```

### ValidationResult Struct (Recommended Design)
```julia
# Based on existing patterns in SolverResult and ViolationReport
Base.@kwdef struct ValidationResult
    passed::Bool                              # Overall pass/fail
    cost_passed::Bool                         # Cost within tolerance
    pld_passed::Bool                          # PLD pass rate met
    dispatch_passed::Bool                     # Dispatch within tolerance
    comparisons::Vector{MetricComparison}     # All individual comparisons
    cost_comparison::Union{MetricComparison, Nothing}     # Cost details
    pld_comparison::Union{MetricComparison, Nothing}      # PLD details
    dispatch_comparisons::Vector{MetricComparison}        # Per-plant dispatch details
    reference_dir::String                     # Path to reference data used
    timestamp::DateTime                       # When validation was run
    exit_code::Int                            # CI exit code
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Eyeball comparison | Automated validation with tolerance | This phase | Reproducible, CI-compatible |
| Single pass/fail | Per-metric detailed diagnostics | This phase | Debuggable failures |
| Manual report | Triple-format reports (console/MD/JSON) | This phase | CI + human reviewable |

**Current state of the codebase:**
- `SolverResult` already has all the fields needed for comparison (objective_value, variables dict with per-plant dispatch, dual_values for PLDs)
- `get_pld_dataframe()`, `get_cost_breakdown()`, `get_thermal_generation()`, `get_hydro_generation()`, `get_hydro_storage()` already extract the values we need to compare
- `export_csv()` and `export_json()` already demonstrate the output patterns
- `check_constraint_violations()` and `ViolationReport` demonstrate the accumulate-then-report pattern
- PDO output files in the ONS sample contain all reference data needed (pdo_cmosist.dat for PLDs, pdo_sist.dat for system-level data, pdo_term.dat for thermal dispatch, pdo_hidr.dat for hydro)

## Reference Data Analysis

### Available PDO Output Files (DS_ONS_102025_RV2D11)

| File | Lines | Content | Validation Use |
|------|-------|---------|----------------|
| `pdo_cmosist.dat` | 399 | CMO per submarket per period (Cmarg, PI_Demanda) | **PLD reference** - 75 periods x 5 submarkets |
| `pdo_sist.dat` | 404 | System-level data (CMO, demand, generation by type, storage) | **Cost & dispatch aggregates** |
| `pdo_term.dat` | 36,624 | Thermal plant generation per unit per period | **Thermal dispatch reference** |
| `pdo_hidr.dat` | 68,124 | Hydro plant generation, storage, outflow per period | **Hydro dispatch & storage reference** |
| `pdo_oper_term.dat` | 29,286 | Thermal unit-level generation with bus and CMO | **Detailed thermal reference** |
| `pdo_sumaoper.dat` | 5,952 | Daily hydro balance summary (vol initial, final, flows) | **Hydro storage trajectory reference** |
| `pdo_operacao.dat` | 57,873 | Detailed operation results | Additional reference data |
| `pdo_cmobar.dat` | 595,223 | Nodal CMO per bus per period | **Nodal LMP reference** (if needed) |
| `pdo_eolica.dat` | 257,360 | Wind/renewable generation per period | **Renewable dispatch reference** |

### Key Reference Data Format (pdo_cmosist.dat)
```
------;-------;------;---------------;---------------;
 IPER ;  Pat  ; SIST ;     Cmarg     ;  PI_Demanda   ;
------;-------;------;---------------;---------------;
    1 ;  LEVE ; SE   ;        304.30 ;        300.79 ;
    1 ;  LEVE ; S    ;        279.26 ;        300.78 ;
```
- Semicolon-delimited with padding
- IPER = period index (1-75)
- SIST = submarket (SE, S, NE, N, FC)
- Cmarg = marginal cost in R$/MWh
- 75 periods x 5 submarkets = 375 data rows

### Key Reference Data Format (pdo_term.dat)
```
-----;-------;----;-------------;----;----;-----------;-----------;-----------;------------;-----;-----------;
IPER ;  Pat  ;USIT;     Nome    ;Unid;Sist;  Geracao  ;    GMin   ;    GMax   ; Capacidade ; L/D ;CustoLinear;
    1 ;  LEVE ;  1 ;ANGRA 1      ;  1 ; SE ;    640.00 ;      0.00 ;    640.00 ;     640.00 ;  L  ;     31.17 ;
    1 ;  LEVE ;  1 ;ANGRA 1      ; 99 ; SE ;    640.00 ;    640.00 ;    640.00 ;     640.00 ;  -  ;           ;
```
- USIT = thermal plant code (maps to ConventionalThermal.id)
- Unid = unit number (99 = plant-level summary)
- Geracao = generation in MW

### Pre-Generation Strategy

The CONTEXT.md states "reference files are pre-generated CSV/JSON." The reference CSV files should be extracted from PDO files once and committed to `expected/` directories. This avoids parsing complex DESSEM output format at validation time.

**Recommended reference CSV schemas:**

1. **total_cost.csv**: `total_cost_rs` (single value)
2. **pld_by_submarket.csv**: `period,submarket,pld_rs_per_mwh`
3. **thermal_dispatch.csv**: `period,plant_id,generation_mw`
4. **hydro_dispatch.csv**: `period,plant_id,generation_mw`
5. **hydro_storage.csv**: `period,plant_id,storage_hm3`

A one-time extraction script should be created to parse PDO files and produce these CSVs. This script is a build/setup tool, not part of the validation module itself.

## Open Questions

1. **Total cost source in reference data**
   - What we know: `pdo_sist.dat` contains CMO per submarket but no explicit total system cost. The `des_log_relato.dat` log file likely contains the total cost.
   - What's unclear: Exact location and format of total cost in PDO output files.
   - Recommendation: Extract total cost from the DESSEM log file or compute it from `pdo_sist.dat` aggregates. The extraction script handles this. Alternatively, the reference CSV can be hand-populated from known DESSEM output.

2. **Plant ID mapping between OpenDESSEM and DESSEM**
   - What we know: DESSEM uses numeric USIT/USIH codes; OpenDESSEM uses string IDs.
   - What's unclear: How the DessemLoader maps between these. Currently `convert_dessem_thermal()` creates IDs from DESSEM codes.
   - Recommendation: The reference CSV files should use whatever ID scheme OpenDESSEM uses after loading. This is resolved during the one-time extraction step.

3. **Which time periods to validate**
   - What we know: ONS sample has 75 periods (48 half-hourly for day 1, then multi-hour for days 2-7). First 48 periods have network modeling enabled.
   - What's unclear: Should validation cover all 75 periods or only the first 48 (network-enabled day)?
   - Recommendation: Validate all periods that OpenDESSEM actually solves. If the model only covers day 1 (48 periods), validate those 48. The reference CSV should cover whatever range the model produces.

4. **Handling the FC (fictitious) submarket**
   - What we know: FC submarket has CMO = 0.00 in all periods in the reference.
   - What's unclear: Whether to include FC in PLD pass-rate calculation.
   - Recommendation: Exclude FC from PLD validation by default (configurable). Document that FC is fictitious.

## Sources

### Primary (HIGH confidence)
- **Codebase analysis** - Direct reading of all source files in `src/`, `test/`, and `docs/Sample/`
- **PDO output files** - Direct inspection of `pdo_cmosist.dat`, `pdo_sist.dat`, `pdo_term.dat`, `pdo_hidr.dat` format and content
- **CONTEXT.md** - Phase 5 locked decisions

### Secondary (MEDIUM confidence)
- **SAMPLE_VALIDATION.md** - Previous analysis of sample data compatibility
- **ONS_VALIDATION.md** - Parser compatibility analysis for ONS data
- **Existing test patterns** - `test/integration/test_solver_end_to_end.jl` for end-to-end test architecture

### Tertiary (LOW confidence)
- None. All findings based on direct codebase inspection.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in project dependencies, no new packages needed
- Architecture: HIGH - Extension of existing patterns (ViolationReport, SolverResult, export_csv/json)
- Pitfalls: HIGH - Identified from actual reference data inspection (FC submarket, scaling, ID mapping)
- Reference data format: HIGH - Directly inspected all PDO files in the sample directory

**Research date:** 2026-02-17
**Valid until:** 2026-03-17 (stable - internal project architecture)
