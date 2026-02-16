---
phase: 03-solver-interface
plan: 03
subsystem: solver
tags: [iis, infeasibility, diagnostics, jump, conflict-api]

# Dependency graph
requires:
  - phase: 03-01
    provides: Unified solve API, SolverResult struct
  - phase: 03-02
    provides: Lazy loading infrastructure
provides:
  - IISConflict struct for representing individual conflicts
  - IISResult struct for IIS computation results
  - compute_iis!() function using JuMP conflict API
  - write_iis_report() for generating human-readable reports
affects: [validation, debugging]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - On-demand diagnostics (compute only when needed)
    - Auto-generated timestamped reports
    - Graceful solver compatibility handling

key-files:
  created:
    - src/solvers/infeasibility.jl
    - test/unit/test_infeasibility.jl
  modified:
    - src/solvers/solver_types.jl
    - src/solvers/Solvers.jl
    - src/solvers/solution_extraction.jl
    - test/runtests.jl

key-decisions:
  - "On-demand IIS computation via explicit compute_iis!(model) call"
  - "Auto-generate timestamped report files when conflicts found"
  - "Warning (not error) for non-infeasible models"
  - "Graceful handling when solver doesn't support IIS"

patterns-established:
  - "Pattern: On-demand diagnostics - compute_iis!() called explicitly when model is infeasible"
  - "Pattern: Auto-generated reports with timestamp in filename"
  - "Pattern: Solver compatibility handled with fallback to NO_CONFLICT_FOUND"

# Metrics
duration: 36 min
completed: 2026-02-16
---

# Phase 3 Plan 3: Infeasibility Diagnostics Summary

**On-demand IIS computation with auto-generated timestamped reports for debugging infeasible models**

## Performance

- **Duration:** 36 min
- **Started:** 2026-02-16T15:09:52Z
- **Completed:** 2026-02-16T15:45:25Z
- **Tasks:** 4 completed
- **Files modified:** 6 files

## Accomplishments
- Implemented compute_iis!() using JuMP's compute_conflict!() API
- Created IISConflict and IISResult structs for representing IIS results
- Implemented write_iis_report() with troubleshooting guide
- Added 75 comprehensive tests covering all scenarios
- Fixed MOI constant names and escaping issues

## Task Commits

Each task was committed atomically:

1. **Task 1: Create IISResult struct and infeasibility module** - `b2118da` (feat)
2. **Task 4: Add tests for infeasibility diagnostics** - `25e52b7` (test)

**Plan metadata:** (to be committed)

_Note: Tasks 2 and 3 (compute_iis! and write_iis_report) were implemented as part of Task 1_

## Files Created/Modified
- `src/solvers/infeasibility.jl` - New module with compute_iis!() and write_iis_report()
- `src/solvers/solver_types.jl` - Added IISConflict and IISResult structs
- `src/solvers/Solvers.jl` - Added include and exports for infeasibility module
- `src/solvers/solution_extraction.jl` - Fixed R$ escaping in docstrings
- `test/unit/test_infeasibility.jl` - 75 new tests for infeasibility diagnostics
- `test/runtests.jl` - Added include for test_infeasibility.jl

## Decisions Made

1. **On-demand IIS computation**: Per CONTEXT.md decision - users call compute_iis!(model) explicitly when needed, rather than auto-computing on every solve
2. **Auto-generated report files**: When IIS is successfully computed and conflicts are found, automatically write a timestamped report
3. **Warning for non-infeasible models**: compute_iis!() logs a warning but doesn't error when called on non-infeasible models
4. **Solver compatibility handling**: HiGHS uses MathOptIIS package for limited IIS support; Gurobi/CPLEX have full native support

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed R$ escaping in docstrings**
- **Found during:** Task 1 (Module loading verification)
- **Issue:** `R$/MWh` in docstrings caused parsing errors - `$` character needs escaping in Julia strings
- **Fix:** Escaped as `R\$/MWh` in all docstrings
- **Files modified:** src/solvers/solution_extraction.jl
- **Verification:** Module loads without parse errors
- **Committed in:** b2118da (Task 1 commit)

**2. [Rule 1 - Bug] Fixed incorrect MOI constant names**
- **Found during:** Task 4 (Test execution)
- **Issue:** Used non-existent `MOI.COMPUTE_CONFLICT_SUCCESS` and `MOI.COMPUTE_CONFLICT_NOT_SUPPORTED`
- **Fix:** Changed to correct constants: `MOI.CONFLICT_FOUND`, `MOI.NO_CONFLICT_EXISTS`, `MOI.NO_CONFLICT_FOUND`
- **Files modified:** src/solvers/infeasibility.jl, test/unit/test_infeasibility.jl
- **Verification:** All 75 tests pass
- **Committed in:** 25e52b7 (Task 4 commit)

**3. [Rule 3 - Blocking] Handle compute_conflict!() returning Nothing**
- **Found during:** Task 4 (Test execution)
- **Issue:** JuMP's compute_conflict!() can return `Nothing` instead of `ConflictStatusCode`
- **Fix:** Added check for `raw_status !== nothing` before assignment
- **Files modified:** src/solvers/infeasibility.jl
- **Verification:** Tests no longer fail with type conversion error
- **Committed in:** 25e52b7 (Task 4 commit)

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking)
**Impact on plan:** All auto-fixes necessary for correctness. No scope creep.

## Issues Encountered
- MOI constant names are different from expected - resolved by checking actual MOI enum values
- HiGHS uses MathOptIIS package which provides limited IIS support - documented in report

## Verification

All success criteria verified:
- [x] IISResult and IISConflict structs defined
- [x] compute_iis!() function implemented with JuMP conflict API
- [x] write_iis_report() generates formatted report
- [x] Solver compatibility handled (HiGHS uses MathOptIIS, Gurobi/CPLEX have native support)
- [x] Tests created and passing (75 tests)

## Next Phase Readiness
- Infeasibility diagnostics ready for use in validation phase
- Users can debug infeasible models with compute_iis!(model) and write_iis_report()
- Auto-generated reports include troubleshooting guide specific to DESSEM models

---
*Phase: 03-solver-interface*
*Completed: 2026-02-16*
