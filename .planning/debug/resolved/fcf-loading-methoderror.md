---
status: resolved
trigger: "Investigate issue: fcf-loading-methoderror - The ONS example fails to load FCF (cost of water) curves from infofcf.dat with a MethodError for parse_fcf_line"
created: 2026-02-16T00:00:00
updated: 2026-02-16T00:00:00
---

## Current Focus

hypothesis: CONFIRMED - strip() returns SubString{String}, but parse_fcf_line expects String
test: Applied fix and verified with tests
expecting: All tests pass
next_action: Archive session

## Symptoms

expected: FCF curves should load and apply water values to hydro plants from infofcf.dat file
actual: MethodError - no method matching parse_fcf_line(::SubString{String}, ::Int64)
errors: MethodError when trying to parse FCF file - the parse_fcf_line function exists but no method for SubString{String}
reproduction: Run `julia --project=. examples/ons_data_example.jl`
started: Started happening when the example tries to load FCF curves via load_fcf_curves() function

## Eliminated

(none - hypothesis was correct)

## Evidence

- timestamp: 2026-02-16T00:00:00
  checked: src/data/loaders/fcf_loader.jl
  found: parse_fcf_line is defined at line 439 with signature (line::String, line_num::Int)
  implication: The function exists and expects String, but is being called with SubString{String}

- timestamp: 2026-02-16T00:00:00
  checked: parse_infofcf_file function at line 390
  found: line = strip(line) converts String to SubString{String}
  implication: The strip() function in Julia returns SubString{String} for performance, not String

- timestamp: 2026-02-16T00:00:00
  checked: Direct test with load_fcf_curves()
  found: Reproduced error - MethodError: no method matching parse_fcf_line(::SubString{String}, ::Int64)
  implication: Root cause confirmed - type mismatch between SubString{String} argument and String parameter

- timestamp: 2026-02-16T00:00:00
  checked: After fix - parse_fcf_line type flexibility tests
  found: Both String and SubString{String} now work correctly
  implication: Fix verified - parse_fcf_line now accepts AbstractString

## Resolution

root_cause: In parse_infofcf_file(), line 390 does `line = strip(line)` which returns SubString{String}. This is then passed to parse_fcf_line(line::String, line_num::Int) at line 398, causing MethodError because Julia's type system requires exact match for String, and SubString{String} is a different type.

fix: Changed parse_fcf_line signature from `line::String` to `line::AbstractString` to accept both String and SubString{String}. This is the idiomatic Julia approach - using AbstractString allows any string subtype to be accepted.

verification: 
- Tested parse_fcf_line with both String and SubString{String} inputs - both work
- load_fcf_curves() now completes without MethodError
- Full ONS example runs successfully

files_changed: 
- src/data/loaders/fcf_loader.jl: Changed `parse_fcf_line(line::String, ...)` to `parse_fcf_line(line::AbstractString, ...)` and updated docstring
