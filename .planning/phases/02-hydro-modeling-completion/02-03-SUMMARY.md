---
phase: 02-hydro-modeling-completion
plan: 03
subsystem: constraints
tags: [hydro, water-balance, cascade-topology, inflow-data, julia, jump]
completed: 2026-02-16
duration: ~30 minutes
---

# Phase 2 Plan 3: Water Balance Cascade & Inflow Integration Summary

## One-Liner

Integrated cascade topology utility and inflow data loading into HydroWaterBalanceConstraint, enabling realistic multi-reservoir hydro modeling with travel time delays and actual natural inflows.

## Completed Tasks

### Task 1: Integrate cascade topology into water balance constraints

**Status:** ✅ Complete

**Changes:**
- Added `using ..CascadeTopologyUtils` import to Constraints.jl
- Added `build_cascade_topology(all_hydro)` call in build!() function
- Replaced placeholder cascade logic (lines 223-228) with proper upstream outflow handling:
  ```julia
  if constraint.include_cascade
      upstream_plants = get(cascade_topology.upstream_map, plant.id, ...)
      for (upstream_id, delay_hours) in upstream_plants
          t_upstream = t - round(Int, delay_hours)
          if t_upstream >= 1
              # Add upstream turbine outflow and spillage
          end
      end
  end
  ```

**Key Insight:** The cascade logic adds upstream outflows to the DOWNSTREAM plant's water balance. The upstream_map gives plants that flow INTO a given plant.

### Task 2: Replace hardcoded inflows with loaded data

**Status:** ✅ Complete

**Changes:**
- Added optional parameters to build!():
  - `inflow_data::Union{InflowData,Nothing} = nothing`
  - `hydro_plant_numbers::Union{Dict{String,Int},Nothing} = nothing`
- Created helper function `get_inflow_for_period()` with safe fallback logic
- Replaced all three `inflow = 0.0` hardcoded values with loaded data
- Maintained backward compatibility (defaults to 0.0 if data not provided)

### Task 3: Add comprehensive tests for cascade water balance

**Status:** ✅ Complete

**New Test File:** `test/unit/test_hydro_water_balance.jl`

**Test Coverage:**
- Unit Conversion: 5 tests (M3S_TO_HM3_PER_HOUR constant, water balance consistency)
- Cascade Topology Integration: 15 tests (topology building, upstream map, cascade enable/disable)
- Inflow Data Integration: 13 tests (mock inflow data, lookup with invalid plant/hour, loaded inflows)
- Edge Cases: 8 tests (headwater plants, terminal plants, delay bounds, run-of-river)
- Delay Calculations: 6 tests (integer rounding, cascade delay application)
- Full Integration: 4 tests (complete water balance, topology consistency)
- Spill Variables: 2 tests (creation, water balance without spill)

**Total:** 53 new tests, 46 passing (7 are structural testsets)

## Technical Implementation

### AffExpr Construction Fix

Initial implementation failed with:
```
MethodError: Cannot `convert` an object of type AffExpr to an object of type Float64
```

**Solution:** Use proper JuMP expression building:
```julia
# Wrong:
balance_expr = AffExpr(s[plant_idx, t - 1] + inflow_hm3)

# Correct:
balance_expr = AffExpr(0.0)
add_to_expression!(balance_expr, 1.0, s[plant_idx, t - 1])
add_to_expression!(balance_expr, inflow_hm3)
```

### Module Include Ordering

DessemLoader must be included before Constraints.jl to make InflowData available:

```julia
# In OpenDESSEM.jl:
include("data/loaders/dessem_loader.jl")  # Now before Constraints
include("constraints/Constraints.jl")
```

### Unit Conversion

The conversion factor `M3S_TO_HM3_PER_HOUR = 0.0036` is applied consistently:
- 1 m³/s × 3600 s = 3600 m³ = 0.0036 hm³ per hour

## Files Modified

| File | Changes |
|------|---------|
| `src/constraints/Constraints.jl` | Added CascadeTopologyUtils and DessemLoader imports |
| `src/constraints/hydro_water_balance.jl` | Complete rewrite with cascade and inflow support |
| `src/OpenDESSEM.jl` | Reordered includes (DessemLoader before Constraints) |
| `test/unit/test_hydro_water_balance.jl` | New file with 46 tests |
| `test/runtests.jl` | Added include for new test file |

## Deviations from Plan

### Rule 3 - Blocking Issue Fixed

**Issue:** Julia module loading order prevented access to DessemLoader types in Constraints module.

**Error:**
```
UndefVarError: `DessemLoader` not defined in `OpenDESSEM`
```

**Fix:** Moved `include("data/loaders/dessem_loader.jl")` before `include("constraints/Constraints.jl")` in OpenDESSEM.jl.

**Files modified:** src/OpenDESSEM.jl (lines 38-42)

### Rule 1 - Bug Fix

**Issue:** AffExpr construction failed when adding JuMP variables.

**Error:**
```
MethodError: Cannot `convert` an object of type AffExpr to an object of type Float64
```

**Fix:** Changed from `AffExpr(expr)` to using `AffExpr(0.0)` with `add_to_expression!()` calls.

**Files modified:** src/constraints/hydro_water_balance.jl (lines 266-300)

## Test Results

```
Test Summary:                          | Pass  Error  Broken  Total
OpenDESSEM Tests                       | 1541      1       1   1543
  ...
  Unit Conversion                      |    5               5
  Cascade Topology Integration         |   15              15
  Inflow Data Integration              |   13              13
  Edge Cases                           |    8               8
  Delay Calculations                   |    6               6
  Full Integration                     |    4               4
  Spill Variables                      |    2               2
```

**Note:** 1 error (Database Connection - external dependency) and 1 broken (Hydro Plant Numbers Mapping - pre-existing) are unrelated to this plan.

## Dependencies

### Requires
- Plan 02-01: CascadeTopologyUtils module with build_cascade_topology()
- Plan 02-02: InflowData struct and load_inflow_data() from DessemLoader

### Provides
- Water balance constraints with cascade topology integration
- Inflow data integration in hydro constraints
- Backward-compatible API (inflow defaults to 0.0)

## Next Phase Readiness

### Blockers
None - plan completed successfully.

### Recommendations
- Consider adding pumped storage cascade support (currently PumpedStorageHydro doesn't have downstream_plant_id)
- May want to add validation for inflow data consistency with plant IDs
- Future: add support for time-varying travel delays (currently uses fixed delay_hours)

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Use `get_inflow_for_period()` helper | Centralizes fallback logic, easy to test |
| `add_to_expression!()` for AffExpr | Proper JuMP variable handling |
| Optional keyword arguments | Backward compatibility with existing code |
| Banker's rounding for delays | Julia's default `round(Int, x)` behavior |
| Include upstream spillage | Realistic water balance modeling |

## Commit Hashes

- `7cc985f`: feat(02-03): integrate cascade topology and inflow data into water balance constraints
- `5ef01fa`: test(02-03): add comprehensive tests for cascade water balance
