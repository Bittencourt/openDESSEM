# Coding Conventions

**Analysis Date:** 2026-02-15

## Naming Patterns

**Files:**
- Module files: `snake_case.jl` (e.g., `thermal.jl`, `variable_manager.jl`, `solver_interface.jl`)
- Test files: `test_<module_name>.jl` in `test/unit/` or `test/integration/`
- Entity type files: One entity type per file with descriptive name (`thermal.jl`, `hydro.jl`, `renewable.jl`)
- Constraint files: One constraint type per file (`thermal_commitment.jl`, `hydro_water_balance.jl`)

**Functions:**
- All functions use `snake_case` (e.g., `validate_positive()`, `create_thermal_variables!()`, `get_thermal_plant_indices()`)
- Mutating functions end with `!` (e.g., `build!()`, `create_all_variables!()`, `add_tag!()`, `set_property!()`)
- Predicate functions start with `is_` or `has_` (e.g., `is_empty()`, `has_id()`, `is_dispatchable`)
- Getter functions typically start with `get_` (e.g., `get_id()`, `get_thermal_plant()`, `get_solver_optimizer()`)
- Factory/constructor functions: `create_<type>()` (e.g., `create_test_thermal()`, `create_test_system()`)

**Variables:**
- Local variables: `snake_case` (e.g., `plant_id`, `time_periods`, `num_constraints`)
- Constants: `UPPER_SNAKE_CASE` (e.g., `MAX_ITERATIONS`)
- Loop variables: Single letter or short descriptive name (e.g., `i`, `t`, `plant`, `(sm, idx) in zip(...)`)
- Private/internal variables: Prefix with underscore in module scope when needed (e.g., `_internal_cache`)

**Types:**
- All user-defined types use `PascalCase` (e.g., `ConventionalThermal`, `EntityMetadata`, `ElectricitySystem`)
- Abstract types also use `PascalCase` (e.g., `AbstractEntity`, `ThermalPlant`, `AbstractConstraint`)
- Enum values: `UPPER_SNAKE_CASE` (e.g., `NATURAL_GAS`, `COAL`, `WIND`, `SOLAR`, `DETERMINISTIC`)

**Examples from codebase:**
- `src/entities/thermal.jl`: Defines `ConventionalThermal`, `CombinedCyclePlant`, `FuelType` enum
- `src/variables/variable_manager.jl`: Functions like `get_thermal_plant_indices()`, `create_thermal_variables!()`
- `src/constraints/constraint_types.jl`: Types like `AbstractConstraint`, `ConstraintMetadata`
- `src/core/electricity_system.jl`: Main system type `ElectricitySystem` with methods like `get_thermal_plant()`

## Code Style

**Formatting:**
- Tool: JuliaFormatter.jl (MANDATORY before commits per `.claude/CLAUDE.md`)
- Indentation: 4 spaces (no tabs)
- Maximum line length: 92 characters
- Run formatting: `julia --project=formattools -e 'using JuliaFormatter; format(".", verbose=true)'`

**Linting:**
- No formal linter configured; JuliaFormatter enforces consistency
- Manual code review for logical issues and patterns
- Test-driven development catches many errors early

**Code Block Style:**
```julia
# Conditional blocks (spaces around operators)
if condition
    # Implementation
end

# Function definitions with multiple parameters
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::AbstractConstraint,
)
    # Long signatures break across lines
end

# Keyword arguments with spaces around =
plant = ConventionalThermal(;
    id = "T_SE_001",
    name = "Sudeste Gas Plant 1",
    bus_id = "SE_230KV_001",
    # ...
)
```

## Import Organization

**Order:**
1. Standard library imports (e.g., `using Dates`)
2. External package imports (e.g., `using JuMP`, `using DataFrames`)
3. Local module imports (e.g., `using .Entities`, `using ..OpenDESSEM`)

**Examples from codebase:**
- `src/thermal.jl`: `using Dates` (stdlib only)
- `src/variables/variable_manager.jl`: `using JuMP` then `using ..OpenDESSEM: ElectricitySystem, ...`
- `test/unit/test_constraints.jl`: `using OpenDESSEM`, `using Test`, `using JuMP`

**Path Aliases:**
- Module `OpenDESSEM` re-exports main types and functions for convenient access
- Submodules accessible via module name: `using OpenDESSEM.Variables`, `using OpenDESSEM.Constraints`
- See `src/OpenDESSEM.jl` for full export list (lines 42-82)

## Error Handling

**Validation Pattern - Entities:**
Validation happens in constructors using helper functions from `src/entities/validation.jl`:
```julia
function validate_positive(value::Real, field_name::String = "value")
    if value < 0
        throw(ArgumentError("$field_name must be positive (got $value)"))
    end
    return value
end
```

**Validation Pattern - System Assembly:**
`ElectricitySystem` constructor performs referential integrity checks:
```julia
# From src/core/electricity_system.jl
# Validates all foreign key relationships before system creation
# Throws AssertionError with descriptive messages on validation failure
@assert haskey(bus_dict, plant.bus_id) "Thermal plant $(plant.id) references non-existent bus $(plant.bus_id)"
```

**Error Throwing Convention:**
- Use `ArgumentError` for invalid function arguments
- Use `AssertionError` (via `@assert`) for system-level validation failures
- Use `error()` for unrecoverable runtime errors
- Custom `ValidationError` type exists in `src/entities/validation.jl` but `ArgumentError` preferred

**Logging Pattern:**
```julia
# From src/constraints/constraint_types.jl and solvers/
@warn "Message" key=value  # Warnings with context
@info "Message" key=value  # Informational messages
@error "Message" key=value # Error messages (non-fatal)
@debug "Message" key=value # Debug-level messages
```

**Example from `src/solvers/solver_interface.jl`:**
```julia
if !options.verbose
    MOI.set(model, MOI.Silent(), true)
end

# Set MIP gap tolerance
try
    MOI.set(model, MOI.RelativeGapTolerance(), options.mip_gap)
catch e
    @warn "Could not set MIP gap: $e"
end
```

## Logging

**Framework:** Built-in Julia logging (no external package)

**Patterns:**
- Use `@info` for major workflow milestones
- Use `@warn` for recoverable issues
- Use `@error` for non-fatal errors that don't stop execution
- Always include context via named arguments: `@info "Model created" n_thermal=10 n_hydro=5`
- See `src/solvers/solver_interface.jl` and `src/data/loaders/dessem_loader.jl` for examples

## Comments

**When to Comment:**
- Complex algorithms or mathematical relationships (e.g., water balance equations in `src/constraints/hydro_water_balance.jl`)
- Non-obvious design decisions
- Workarounds or temporary solutions (mark with TODO/FIXME)
- Integration points between modules

**When NOT to Comment:**
- Self-documenting code with clear variable names
- Obvious operations (e.g., loop iterations)
- Code that should be replaced with clearer code instead

**JSDoc/TSDoc Style:**
Julia uses docstrings with triple-quote markdown format. All public functions and types must have docstrings.

**Docstring Pattern:**
```julia
"""
    function_name(arg1::Type, arg2::Type) -> ReturnType

One-line summary.

Extended description if needed.

# Arguments
- `arg1::Type`: Description of arg1
- `arg2::Type`: Description of arg2

# Returns
- `ReturnType`: Description of return value

# Throws
- `ErrorType`: When/why this error occurs

# Examples
```julia
result = function_name(value1, value2)
@test result > 0
```

# See Also
- [`related_function`](@ref)
"""
```

**Examples from codebase:**
- `src/entities/validation.jl`: Comprehensive docstrings for all validation functions (lines 8-130)
- `src/variables/variable_manager.jl`: Module docstring with variable naming conventions (lines 1-66)
- `src/entities/thermal.jl`: Detailed docstrings for `ConventionalThermal` type with all fields documented
- `src/constraints/constraint_types.jl`: Docstrings for `AbstractConstraint` and types

## Function Design

**Size Guidelines:**
- Keep functions focused on single responsibility
- Typical range: 10-50 lines of code
- Longer functions may indicate need for helper functions
- Examples:
  - `validate_positive()` in `src/entities/validation.jl`: 6 lines
  - `create_thermal_variables!()` in `src/variables/variable_manager.jl`: ~40 lines
  - `build!()` methods in constraint files: 30-80 lines (varies by complexity)

**Parameters:**
- Use keyword arguments for optional parameters (prefer `f(; kwarg=default)` over positional)
- Group related parameters together
- All keyword arguments should have sensible defaults or clear requirements
- Example from `src/core/electricity_system.jl`:
  ```julia
  Base.@kwdef struct ElectricitySystem
      thermal_plants::Vector{ConventionalThermal}
      hydro_plants::Vector{HydroPlant}
      buses::Vector{Bus}
      base_date::Date = today()
      description::String = ""
      version::String = "unknown"
  end
  ```

**Return Values:**
- Single return value is implicit (last expression)
- Multiple returns use tuples or struct: `return (value1, value2)`
- Functions with side effects use `nothing` or void semantics
- Mutating functions (`!` suffix) typically return `nothing`

## Module Design

**Exports:**
- Public API exported via `export` statement at module level
- See `src/OpenDESSEM.jl` (lines 42-82) for main module exports
- Each submodule exports its public API:
  - `src/entities/Entities.jl` exports all entity types and validation functions
  - `src/variables/variable_manager.jl` exports variable creation functions
  - `src/constraints/Constraints.jl` exports constraint types and `build!()` methods

**Barrel Files:**
- `src/Entities.jl`: Includes and re-exports all entity modules
- `src/Constraints.jl`: Includes and re-exports all constraint modules
- `src/OpenDESSEM.jl`: Main entry point, re-exports public API

**Module Structure Pattern:**
```julia
# Define abstract types
abstract type AbstractEntity end
abstract type ThermalPlant <: PhysicalEntity end

# Define concrete types
Base.@kwdef struct ConventionalThermal <: ThermalPlant
    # Fields...
end

# Define methods
function build!(model::Model, system::ElectricitySystem, constraint::AbstractConstraint)
    # Implementation...
end

# Export public API
export AbstractEntity, ConventionalThermal, build!
```

**Location Guidelines:**
- Entity types: `src/entities/<entity_name>.jl`
- Constraint types: `src/constraints/<constraint_name>.jl`
- Core utilities: `src/core/<feature_name>.jl`
- Integration adapters: `src/integration/<adapter_name>.jl`
- Data loaders: `src/data/loaders/<source_name>_loader.jl`

## Known Issues & Workarounds

**1. Missing Inflow Data (TODO in hydro_water_balance.jl)**
- Location: `src/constraints/hydro_water_balance.jl` (lines 55, 79)
- Issue: Inflow data not yet loaded from database
- Workaround: `inflow = 0.0` hardcoded
- Fix approach: Implement inflow loading in data loaders

**2. Full PowerModels Integration (TODO in network_powermodels.jl)**
- Location: `src/constraints/network_powermodels.jl` (line 30)
- Issue: PowerModels network constraints not fully integrated
- Workaround: Basic stub implementation
- Fix approach: Complete PowerModels constraint bridging

**3. Database Export Not Implemented (TODO in solution_exporter.jl)**
- Location: `src/analysis/solution_exporter.jl` (line 5)
- Issue: LibPQ dependency not yet added
- Workaround: CSV export only (implemented)
- Fix approach: Add LibPQ to Project.toml and implement PostgreSQL export

## Code Quality Practices

**Test-Driven Development:**
- All code changes require tests first (per `.claude/CLAUDE.md` section 1)
- Tests located in `test/unit/` or `test/integration/`
- 90%+ test coverage target for core modules
- Run tests: `julia --project=test test/runtests.jl`

**Pre-Commit Checklist:**
- Format code with JuliaFormatter
- Run full test suite (all tests must pass)
- Check coverage > 90% for modified files
- No TODO/FIXME unless documented with context
- Clean up temporary files (*.log, *.cache, *~, etc.)

**Repository Practices:**
- No temporary files in commits (see `.gitignore` for exhaustive list)
- Commits follow conventional format: `<type>(<scope>): <subject>`
- Example: `feat(thermal): add combined-cycle plant support`
- No `.env` or credential files ever committed

---

*Convention analysis: 2026-02-15*
