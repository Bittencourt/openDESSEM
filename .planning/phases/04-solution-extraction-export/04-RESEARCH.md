# Phase 4: Solution Extraction & Export - Research

**Researched:** 2026-02-16
**Domain:** JuMP solution extraction, CSV/JSON export, constraint violation reporting
**Confidence:** HIGH

## Summary

Phase 4 builds on a substantial existing codebase that already implements most of the solution extraction and export functionality from Phase 3. The core extraction functions (`extract_solution_values!()`, `extract_dual_values!()`, `get_pld_dataframe()`, `get_cost_breakdown()`) and export functions (`export_csv()`, `export_json()`) already exist and are wired into the solve pipeline. Phase 4's work is primarily about **hardening, completing gaps, fixing bugs, and adding constraint violation reporting**.

The main gaps identified are: (1) `extract_solution_values!()` does not extract deficit variables, (2) `export_json()` has a bug in `JSON3.pretty()` usage, (3) no constraint violation reporting exists, (4) the CSV export uses wide format (`t_1, t_2, ...` columns) which may need verification for usability, and (5) comprehensive tests are needed specifically for the extraction and export paths.

**Primary recommendation:** Focus on completing the gap analysis (deficit extraction, JSON bug fix, constraint violation reporter), adding thorough tests for each requirement, and verifying that the existing code works correctly end-to-end with the test fixtures.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP.jl | 1.0+ | Optimization model, `value()`, `dual()`, `primal_feasibility_report()` | Already in Project.toml; provides all solution query APIs |
| DataFrames.jl | 1.0+ | Tabular data for PLD and dispatch results | Already used in `get_pld_dataframe()` |
| CSV.jl | 0.10+ | CSV file writing via `CSV.write()` | Already in Project.toml; standard Julia CSV library |
| JSON3.jl | 1.0+ | JSON serialization via `JSON3.write()` and `JSON3.pretty()` | Already in Project.toml; faster and more robust than JSON.jl |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MathOptInterface | 1.0+ | `MOI.ConstraintConflictStatus()`, feasibility checks | Already imported; needed for constraint violation checking |
| Dates | stdlib | Timestamps in export metadata | Already used in solution_exporter.jl |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSON3.jl | JSON.jl | JSON3 is already used, faster; JSON.jl has nicer pretty-print but different API |
| CSV.jl | DelimitedFiles | CSV handles DataFrames natively, DelimitedFiles is lower-level |

**Installation:**
No new dependencies needed. All libraries already in Project.toml.

## Architecture Patterns

### Existing Project Structure (Phase 4 touches these files)
```
src/
├── solvers/
│   ├── solution_extraction.jl  # EXISTING: extract_solution_values!, get_pld_dataframe, etc.
│   └── Solvers.jl              # EXISTING: module exports
├── analysis/
│   ├── Analysis.jl             # EXISTING: module wrapper
│   ├── solution_exporter.jl    # EXISTING: export_csv, export_json, export_database
│   └── constraint_violations.jl  # NEW: constraint violation reporting
test/
├── unit/
│   ├── test_solution_extraction.jl  # NEW: focused extraction tests
│   └── test_solution_exporter.jl    # NEW: focused export tests
├── integration/
│   └── test_solver_end_to_end.jl    # EXISTING: already tests many extraction paths
└── fixtures/
    └── small_system.jl              # EXISTING: test system factory
```

### Pattern 1: Solution Value Extraction (EXISTING)
**What:** Extract JuMP variable values into Dict[(entity_id, time_period) => value] using entity-to-index mapping
**When to use:** After `optimize!()` returns with `has_solution(result) == true`
**Key pattern:**
```julia
# Source: src/solvers/solution_extraction.jl (existing code)
if haskey(model, :g)
    g = model[:g]
    for plant in system.thermal_plants
        if haskey(thermal_indices, plant.id)
            idx = thermal_indices[plant.id]
            for t in time_periods
                val = value(g[idx, t])
                thermal_gen[(plant.id, t)] = val
            end
        end
    end
    result.variables[:thermal_generation] = thermal_gen
end
```

### Pattern 2: Dual Value Extraction (EXISTING)
**What:** Extract constraint duals from LP model for PLD pricing
**When to use:** After LP or SCED solve (not MIP -- MIP duals are invalid)
**Key pattern:**
```julia
# Source: src/solvers/solution_extraction.jl:302-323 (existing code)
if haskey(model, :submarket_balance)
    submarket_balance = model[:submarket_balance]
    for submarket in system.submarkets
        for t in time_periods
            key = (submarket.code, t)
            if haskey(submarket_balance, key)
                dval = dual(submarket_balance[key])
                submarket_duals[key] = dval
            end
        end
    end
    result.dual_values["submarket_balance"] = submarket_duals
end
```

### Pattern 3: Constraint Violation Reporting (NEW - REQUIRED)
**What:** Use JuMP's `primal_feasibility_report()` to detect constraint violations with magnitudes
**When to use:** After solving, to identify constraints that are violated (or nearly violated)
**Key pattern:**
```julia
# Source: JuMP official documentation (https://jump.dev/JuMP.jl/stable/manual/solutions/)
# primal_feasibility_report returns Dict{ConstraintRef => violation_distance}
report = primal_feasibility_report(model; atol = 1e-6)
# Empty dict means all constraints satisfied within tolerance
# Non-empty means violations found with magnitudes
for (con_ref, violation_magnitude) in report
    name = JuMP.name(con_ref)
    # Classify constraint type from name prefix
end
```

### Pattern 4: CSV Export with Wide Format (EXISTING)
**What:** Export dispatch/prices as CSV with entity IDs in rows, time periods in columns
**When to use:** For spreadsheet analysis
**Current format:**
```csv
plant_id,t_1,t_2,t_3,...,t_24
T001,150.0,200.0,180.0,...,120.0
T002,80.0,100.0,90.0,...,60.0
```

### Pattern 5: JSON Export with Nested Structure (EXISTING - HAS BUG)
**What:** Export all solution data as nested JSON for programmatic consumption
**When to use:** For web APIs, data pipelines
**Bug in existing code (solution_exporter.jl line 299):**
```julia
# BROKEN: JSON3.pretty(content) prints to stdout and returns nothing
pretty_content = JSON3.pretty(content)
write(filepath, pretty_content)  # Writes "nothing" to file

# CORRECT pattern:
open(filepath, "w") do io
    JSON3.pretty(io, JSON3.write(json_data))
end
```

### Anti-Patterns to Avoid
- **Extracting duals from MIP:** MIP problems do not have valid dual variables. Always use the two-stage result (`result.lp_result`) for PLD extraction, never the MIP result.
- **Silent failure on missing variables:** Current code uses `try/catch` blocks that swallow errors. Better to check `haskey(model, :variable_name)` first and warn explicitly.
- **Wide CSV format for large systems:** With 168+ time periods, wide format creates unwieldy files. Consider supporting both formats or defaulting to long format.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Constraint violation detection | Custom iteration over constraints checking bounds | `JuMP.primal_feasibility_report(model; atol)` | Handles all constraint types, signed violations, edge cases |
| CSV writing | Manual string concatenation | `CSV.write(filepath, df)` | Handles escaping, quoting, encoding correctly |
| JSON serialization | Custom Dict-to-string conversion | `JSON3.write()` / `JSON3.pretty()` | Handles nested types, special values (NaN, Inf, nothing) |
| DataFrame pivoting | Manual Dict-to-rows loops | `DataFrames.stack()` / `DataFrames.unstack()` | For converting between wide and long format |
| Solution feasibility checking | Manual bound checking | `JuMP.is_solved_and_feasible(model)` + `primal_feasibility_report()` | Standard JuMP API, solver-independent |

**Key insight:** JuMP provides a mature solution query API. The existing code correctly uses `value()` and `dual()` but misses `primal_feasibility_report()` for constraint violations. Do not reimplement what JuMP provides.

## Common Pitfalls

### Pitfall 1: JSON3.pretty Returns Nothing
**What goes wrong:** `JSON3.pretty(json_string)` writes to stdout and returns `nothing`. Assigning the result to a variable and writing it to a file writes "nothing".
**Why it happens:** JSON3.pretty is designed as a display function (like `show`), not a transformation function.
**How to avoid:** Always use the two-argument form: `JSON3.pretty(io, json_string)` or `JSON3.pretty(io, data_dict)`.
**Warning signs:** JSON files contain the literal text "nothing" or are empty.

### Pitfall 2: Extracting Duals from MIP Result
**What goes wrong:** Calling `dual()` on a MIP constraint returns 0.0 or throws an error because MIP problems do not have valid dual variables.
**Why it happens:** Integer variables break the LP duality theory. The shadow price interpretation requires a pure LP.
**How to avoid:** Always extract PLDs from `result.lp_result` (the SCED stage 2 result), not from `result.mip_result` or the unified `result`. The existing code handles this correctly in `solve_model!()`.
**Warning signs:** All PLD values are 0.0 or NaN.

### Pitfall 3: Missing Deficit Variable Extraction
**What goes wrong:** `extract_solution_values!()` currently does NOT extract deficit variables, even though deficit variables exist in the model and are used by `get_cost_breakdown()` (which references `result.variables[:deficit]`).
**Why it happens:** Deficit variables were added in Phase 1 (plan 02) but the extraction function in Phase 3 did not include them.
**How to avoid:** Add deficit variable extraction to `extract_solution_values!()` following the same pattern as other variables.
**Warning signs:** `get_cost_breakdown()` always returns 0.0 for `deficit_penalty` even when deficit variables are non-zero.

### Pitfall 4: Constraint Name Parsing for Violation Classification
**What goes wrong:** `primal_feasibility_report()` returns constraint references, but classifying them by type (thermal, hydro, balance, etc.) requires parsing the constraint name string.
**Why it happens:** JuMP constraints are named via `@constraint(model, name_string, ...)` but the naming convention varies across constraint builders.
**How to avoid:** Establish consistent naming conventions. The existing code uses patterns like `model[:submarket_balance][(code, t)]`. Constraint names can be extracted via `JuMP.name(constraint_ref)`. Parse prefixes to classify: names starting with `thermal_` are thermal constraints, `hydro_` are hydro constraints, etc.
**Warning signs:** "Unknown" constraint types in violation reports.

### Pitfall 5: Wide Format CSV Readability for Large Systems
**What goes wrong:** With 168 time periods, the CSV has 169 columns. This is hard to read in spreadsheet tools and inefficient for programmatic consumption.
**Why it happens:** The current implementation uses wide format (one column per time period) which works well for small test cases (6 periods) but scales poorly.
**How to avoid:** The existing wide format is fine for Phase 4 delivery (matches success criteria). Consider adding long format as an option in future.
**Warning signs:** Users complain about CSV files being hard to work with.

### Pitfall 6: Tuple Keys in Dicts with JSON3
**What goes wrong:** `Dict{Tuple{String,Int}, Float64}` cannot be directly serialized to JSON because JSON keys must be strings. JSON3 may throw an error or produce malformed output.
**Why it happens:** JSON specification requires string keys.
**How to avoid:** The existing `_dict_to_nested()` helper in `solution_exporter.jl` correctly converts Tuple-keyed dicts to `Dict{String, Vector{Float64}}` before JSON serialization. Keep using this pattern.
**Warning signs:** JSON3.write throws "keys must be strings" error.

## Code Examples

### Verified Pattern: primal_feasibility_report for Constraint Violations
```julia
# Source: https://jump.dev/JuMP.jl/stable/manual/solutions/
# After solving the model
optimize!(model)

# Check for violations with tolerance
violations = primal_feasibility_report(model; atol = 1e-6)

if isempty(violations)
    println("All constraints satisfied within tolerance")
else
    for (con_ref, distance) in violations
        name = JuMP.name(con_ref)
        println("Violated: $name, magnitude: $distance")
    end
end
```

### Verified Pattern: Correct JSON3.pretty Usage
```julia
# Source: https://quinnj.github.io/JSON3.jl/stable/
# Write pretty JSON to file (CORRECT)
open(filepath, "w") do io
    JSON3.pretty(io, JSON3.write(json_data))
end

# Alternative: write dict directly
open(filepath, "w") do io
    JSON3.pretty(io, json_data)
end
```

### Verified Pattern: CSV Export from DataFrame
```julia
# Source: https://csv.juliadata.org/stable/
using CSV, DataFrames

df = DataFrame(
    plant_id = ["T001", "T001", "T002", "T002"],
    period = [1, 2, 1, 2],
    generation_mw = [150.0, 200.0, 80.0, 100.0]
)

CSV.write("thermal_generation.csv", df)
```

### Verified Pattern: Extracting Deficit Variables (Gap to Fill)
```julia
# Pattern matching existing extraction code in solution_extraction.jl
# Currently MISSING - needs to be added
if haskey(model, :deficit)
    deficit = model[:deficit]
    deficit_values = Dict{Tuple{String,Int},Float64}()
    submarket_indices = get_submarket_indices(system)
    for submarket in system.submarkets
        if haskey(submarket_indices, submarket.code)
            idx = submarket_indices[submarket.code]
            for t in time_periods
                try
                    val = value(deficit[idx, t])
                    deficit_values[(submarket.code, t)] = val
                catch
                    @warn "Could not extract deficit value for [$idx, $t]"
                end
            end
        end
    end
    result.variables[:deficit] = deficit_values
end
```

## Existing Code Inventory

### What Already Works (Phase 3 deliverables)
| Function | File | Status | Notes |
|----------|------|--------|-------|
| `extract_solution_values!()` | `solution_extraction.jl:40-260` | PARTIAL | Missing deficit extraction |
| `extract_dual_values!()` | `solution_extraction.jl:288-329` | COMPLETE | Extracts submarket_balance duals |
| `get_submarket_lmps()` | `solution_extraction.jl:352-380` | COMPLETE | Returns Vector{Float64} per submarket |
| `get_thermal_generation()` | `solution_extraction.jl:401-428` | COMPLETE | Returns Vector{Float64} per plant |
| `get_hydro_generation()` | `solution_extraction.jl:449-476` | COMPLETE | Returns Vector{Float64} per plant |
| `get_hydro_storage()` | `solution_extraction.jl:497-524` | COMPLETE | Returns Vector{Float64} per plant |
| `get_renewable_generation()` | `solution_extraction.jl:545-572` | COMPLETE | Returns Vector{Float64} per plant |
| `get_pld_dataframe()` | `solution_extraction.jl:619-675` | COMPLETE | Returns DataFrame, supports filtering |
| `CostBreakdown` struct | `solution_extraction.jl:698-705` | COMPLETE | Type-safe cost components |
| `get_cost_breakdown()` | `solution_extraction.jl:763-883` | COMPLETE | Calculates all cost components |
| `export_csv()` | `solution_exporter.jl:97-185` | COMPLETE | Creates 9 CSV files |
| `export_json()` | `solution_exporter.jl:241-308` | HAS BUG | JSON3.pretty usage incorrect |
| `export_database()` | `solution_exporter.jl:359-389` | PLACEHOLDER | Returns empty Dict |

### What's Missing (Phase 4 scope)
| Feature | Requirement | Effort | Notes |
|---------|-------------|--------|-------|
| Deficit variable extraction | EXTR-01 | Small | Add to `extract_solution_values!()` |
| Fix JSON3.pretty bug | EXTR-04 | Small | Two-line fix in `export_json()` |
| Constraint violation reporter | EXTR-05 | Medium | New file, uses `primal_feasibility_report()` |
| Unit tests for extraction | EXTR-01, EXTR-02 | Medium | Focused tests for each variable type |
| Unit tests for CSV export | EXTR-03 | Medium | Verify file creation, column headers, values |
| Unit tests for JSON export | EXTR-04 | Medium | Verify JSON structure, pretty printing |
| Unit tests for violation reporting | EXTR-05 | Medium | Verify detection, classification, formatting |
| Verification that end-to-end extraction matches expectations | All EXTR | Small | Extend existing integration tests |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual constraint iteration for violations | `primal_feasibility_report()` | JuMP 1.10+ | Provides signed violation distances automatically |
| JSON.jl for serialization | JSON3.jl | Project uses JSON3 already | Faster, struct-aware; different pretty-print API |
| Custom LP sensitivity | `lp_sensitivity_report()` | JuMP 1.10+ | Provides complete sensitivity analysis |

**Deprecated/outdated:**
- `JuMP.shadow_price()` vs `JuMP.dual()`: Both exist, but `dual()` returns the raw dual while `shadow_price()` adjusts for objective sense. For LMP/PLD extraction, `dual()` is correct since we control the sign interpretation. The existing code correctly uses `dual()`.

## Open Questions

1. **Wide vs Long CSV format**
   - What we know: Current implementation uses wide format (columns = time periods). Works for small test cases (6 periods). May be unwieldy for 168+ periods.
   - What's unclear: Whether users prefer wide or long format for their analysis workflows.
   - Recommendation: Keep existing wide format (matches success criteria). Document the format clearly. Long format can be added as optional enhancement later (v2 requirement territory).

2. **Deficit variable indexing**
   - What we know: `create_deficit_variables!()` creates `model[:deficit]` indexed by `(submarket_idx, t)`. The extraction code in `get_cost_breakdown()` expects `result.variables[:deficit]` keyed by `(submarket_code, t)`.
   - What's unclear: Exact indexing used by `create_deficit_variables!()` -- need to verify whether it uses integer index or string code.
   - Recommendation: Read `create_deficit_variables!()` implementation carefully during planning to ensure the extraction uses matching index types.

3. **Constraint violation threshold**
   - What we know: `primal_feasibility_report()` accepts an `atol` parameter for the violation threshold.
   - What's unclear: What threshold is appropriate for DESSEM models. Too small catches numerical noise, too large misses real violations.
   - Recommendation: Default to `1e-6` (JuMP default) with a configurable parameter. Document the threshold choice.

4. **Database export scope**
   - What we know: `export_database()` is a placeholder that returns empty Dict. It's listed in the module exports.
   - What's unclear: Whether Phase 4 should complete this or leave it as v2 (XPRT-01).
   - Recommendation: Leave as placeholder. XPRT-01 is explicitly listed as a v2 requirement, not v1. Phase 4 requirements (EXTR-01 through EXTR-05) do not mention database export.

## Sources

### Primary (HIGH confidence)
- [JuMP Solutions Manual](https://jump.dev/JuMP.jl/stable/manual/solutions/) - `primal_feasibility_report()` API, `value()`, `dual()`, `shadow_price()` functions
- [JuMP Constraints Manual](https://jump.dev/JuMP.jl/stable/manual/constraints/) - Constraint reference querying, dual extraction
- [JSON3.jl Documentation](https://quinnj.github.io/JSON3.jl/stable/) - `JSON3.write()`, `JSON3.pretty()` correct usage
- [CSV.jl Documentation](https://csv.juliadata.org/stable/) - `CSV.write()` API
- Existing codebase inspection (solution_extraction.jl, solution_exporter.jl, solver_interface.jl, test fixtures)

### Secondary (MEDIUM confidence)
- [JuMP Discourse: Dual vs Shadow Price](https://discourse.julialang.org/t/dual-vs-shadow-price-which-one-to-use/99260) - Clarifies sign conventions for dual extraction
- [DataFrames.jl Import/Export Guide](https://juliadata.github.io/DataFrames.jl/stable/man/importing_and_exporting/) - DataFrame to CSV patterns
- [JuMP Debugging Tutorial](https://jump.dev/JuMP.jl/stable/tutorials/getting_started/debugging/) - Feasibility checking patterns

### Tertiary (LOW confidence)
- Energy system optimization modeling best practices literature - Wide vs long format preference is domain-specific; no definitive standard found

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in Project.toml, APIs verified from official docs
- Architecture: HIGH - Existing code patterns are clear, new code follows same patterns
- Pitfalls: HIGH - Bugs identified by direct code inspection (JSON3.pretty, missing deficit extraction)
- Constraint violations: HIGH - `primal_feasibility_report()` API verified from JuMP official docs (Jan 2026)

**Research date:** 2026-02-16
**Valid until:** 2026-04-16 (stable domain, JuMP API unlikely to change)
