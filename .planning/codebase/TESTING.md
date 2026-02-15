# Testing Patterns

**Analysis Date:** 2026-02-15

## Test Framework

**Runner:**
- Framework: Test.jl (Julia standard library)
- Config: `test/runtests.jl` is the main entry point
- Julia version: 1.8+

**Assertion Library:**
- Built-in Test.jl: `@test`, `@test_throws`, `@testset`

**Run Commands:**
```bash
# Run all tests (from project root)
julia --project=test test/runtests.jl

# Run specific test file
julia --project=test -e 'include("test/unit/test_thermal_entities.jl")'

# Run with verbose output
julia --project=test -v test/runtests.jl

# Run tests in REPL mode (interactive)
julia --project=test
julia> include("test/runtests.jl")
```

**Test Project Configuration:**
- `Project.toml` lists Test.jl in `[extras]` section
- Tests run in isolated project environment: `--project=test`
- No separate test runner configuration file

## Test File Organization

**Location:**
- Unit tests: `test/unit/` - Test individual modules and functions
- Integration tests: `test/integration/` - Test workflows and component interactions
- All organized hierarchically by functionality

**Naming:**
- Test files: `test_<module_name>.jl`
- Examples: `test_thermal_entities.jl`, `test_variable_manager.jl`, `test_constraints.jl`

**Directory Structure:**
```
test/
├── runtests.jl                 # Main entry point, includes all tests
├── unit/
│   ├── test_entities_base.jl
│   ├── test_thermal_entities.jl
│   ├── test_hydro_entities.jl
│   ├── test_renewable_entities.jl
│   ├── test_network_entities.jl
│   ├── test_market_entities.jl
│   ├── test_electricity_system.jl
│   ├── test_variable_manager.jl
│   ├── test_constraints.jl
│   └── test_powermodels_adapter.jl
└── integration/
    ├── test_constraint_system.jl
    ├── test_database_loader.jl
    └── test_pwf_loader.jl
```

## Test Structure

**Suite Organization - Unit Tests:**
```julia
# From test/unit/test_thermal_entities.jl

using Test
using OpenDESSEM.Entities
using Dates

@testset "Thermal Plant Entities" begin

    @testset "ConventionalThermal - Constructor" begin
        @testset "Valid plant creation" begin
            plant = ConventionalThermal(;
                id = "T_SE_001",
                name = "Sudeste Gas Plant 1",
                # ... all required fields
            )

            @test plant.id == "T_SE_001"
            @test plant.capacity_mw == 500.0
            # More assertions
        end

        @testset "Plant with default metadata" begin
            # Test default values
            @test plant.metadata.version == 1
        end
    end

    @testset "ConventionalThermal - Validation" begin
        @test_throws ArgumentError ConventionalThermal(;
            # Invalid arguments
        )
    end
end
```

**Patterns:**
1. **Outer testset**: File-level grouping by entity/module type
2. **Middle testset**: Feature/functionality grouping (e.g., "Constructor", "Validation")
3. **Inner testset**: Specific test scenario
4. **Assertions**: Use `@test`, `@test_throws`, assertion messages optional

**Suite Organization - Integration Tests:**
```julia
# From test/integration/test_constraint_system.jl

using OpenDESSEM
using OpenDESSEM.Constraints
using Test
using JuMP
using Dates

@testset "Constraint System Integration" begin

    # Helper function defined in test file
    function create_integration_test_system()
        # Build realistic multi-plant system
        buses = Bus[]
        # ... create entities
        return ElectricitySystem(; thermal_plants, hydro_plants, ...)
    end

    @testset "ThermalCommitmentConstraint - Integration" begin
        system = create_integration_test_system()
        model = Model()

        # Create variables
        create_all_variables!(model, system, 1:24)

        # Build constraint
        constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal UC",
                description = "Unit commitment constraints"
            )
        )

        result = build!(model, system, constraint)

        @test result.success
        @test result.num_constraints > 0
    end
end
```

## Test Structure Details

**Setup/Teardown:**
No explicit setup/teardown; tests are self-contained:
- Each test creates its own objects
- Test isolation via local scope (each `@testset` has its own scope)
- No shared state between tests
- Fixtures defined as helper functions within test file

**Assertion Patterns:**
```julia
# Basic assertions
@test condition                           # Assert true
@test value == expected_value
@test value > 0
@test isapprox(value, expected, atol=0.1)

# Error assertions
@test_throws ErrorType function_call()   # Assert error thrown
@test_throws ArgumentError validate_id("")

# Custom assertions
try
    validate_positive(-5.0, "test_field")
    @test false  # Should not reach here
catch e
    @test occursin("test_field", e.msg)
end
```

## Mocking

**Framework:** No external mocking framework
- Manual stub functions instead
- Create simplified test objects
- Replace dependencies with test doubles inline

**Patterns:**
```julia
# Example: Create simple test thermal plant instead of full entity
function create_test_thermal(; id::String)
    ConventionalThermal(;
        id = id,
        name = "Thermal $id",
        bus_id = "B1",
        submarket_id = "SE",
        fuel_type = NATURAL_GAS,
        capacity_mw = 500.0,
        # ... minimal required fields
    )
end

# Use in test
thermal = create_test_thermal(id = "T001")
@test thermal.id == "T001"
```

**Test Data Factory:**
From `test/unit/test_variable_manager.jl` (lines 17-100):
```julia
function create_test_system()
    buses = Bus[]
    for i in 1:5
        push!(buses, Bus(;
            id="B00$i",
            name="Bus $i",
            voltage_kv=230.0,
            base_kv=230.0
        ))
    end

    thermal_plants = ConventionalThermal[]
    for (sm, idx) in zip(["SE", "S", "NE", "N"], 1:4)
        push!(thermal_plants, ConventionalThermal(;
            id="T_$(sm)_001",
            name="$(sm) Thermal Plant",
            bus_id=buses[idx].id,
            # ... other fields
        ))
    end

    return ElectricitySystem(;
        thermal_plants = thermal_plants,
        # ... other entities
    )
end
```

**What to Mock:**
- Database connections (use test fixtures instead of real database)
- External file I/O (use in-memory test data)
- Long-running operations (use simplified test versions)

**What NOT to Mock:**
- Core entity validation logic
- Constraint building logic
- Variable creation
- Mathematical computations (must verify against known results)

## Fixtures and Factories

**Test Data:**
Two patterns:

**Pattern 1: Inline Creation (for simple cases)**
```julia
plant = ConventionalThermal(;
    id = "T001",
    name = "Test Plant",
    # ... required fields
)
```

**Pattern 2: Factory Functions (for complex systems)**
```julia
function create_test_system()
    # Build complete ElectricitySystem with multiple entities
    return system
end

# Use in test
system = create_test_system()
```

**Location:**
- Helper functions defined at top of test file (after imports)
- Examples:
  - `test/unit/test_variable_manager.jl` (lines 17-120): Multiple factory functions
  - `test/integration/test_constraint_system.jl` (lines 16-140): `create_integration_test_system()`
  - `test/unit/test_constraints.jl` (lines 18-100): `create_test_system()`

**Coverage by Type:**
- Entity creation: Simple constructors with valid values
- System assembly: Multi-entity systems with relationships
- Constraint testing: Systems with specific configurations
- Variable creation: Systems of varying sizes

## Coverage

**Requirements:**
- 90%+ coverage target for core modules (per `.claude/CLAUDE.md`)
- Mandatory before commits
- No formal enforcement tool configured, relies on code review

**View Coverage:**
```bash
# Coverage requires additional tooling, not built-in
# Standard approach with Julia:
julia --project=test -e 'using Coverage; Codecov.submit()'

# Manual coverage check: Run tests with coverage
julia --project=test --code-coverage test/runtests.jl
```

**Test Coverage Status (from `.claude/CLAUDE.md`):**
- **Total: 733+ test assertions** (as of 2025-01-05)
- **100% passing**
- Test modules and assertion counts:
  - `test_entities_base.jl`: 151 assertions
  - `test_thermal_entities.jl`: 111 assertions
  - `test_hydro_entities.jl`: 102 assertions
  - `test_renewable_entities.jl`: 130 assertions
  - `test_network_entities.jl`: 216 assertions
  - `test_market_entities.jl`: 125 assertions
  - `test_electricity_system.jl`: 90 assertions
  - `test_variable_manager.jl`: 152 assertions
  - `test_dessem_loader.jl`: 54 assertions
  - `test_powermodels_adapter.jl`: 135 assertions
  - `test_pwf_loader.jl`: 13 assertions (integration)

**Coverage Gaps:**
- Test coverage for solver interface (`src/solvers/`) is limited
- Test coverage for analysis/export functions is limited
- Integration tests for full workflow from load → solve → extract are limited

## Test Types

**Unit Tests:**
- Scope: Individual functions and types
- Location: `test/unit/`
- Examples:
  - Entity constructors and validation
  - Variable creation functions
  - Individual constraint builders
  - Helper/utility functions
- Approach: Test each function in isolation with known inputs/outputs

**Integration Tests:**
- Scope: Component interactions and workflows
- Location: `test/integration/`
- Examples:
  - Full constraint system building on complete system
  - Data loading pipeline (DESSEM files, databases)
  - PowerModels conversion workflows
- Approach: Build realistic systems, apply multiple components, verify overall behavior

**Validation Tests:**
- Scope: Compare against official DESSEM/ONS results
- Location: Not yet implemented (`test/validation/` directory doesn't exist)
- Approach: Would test against known solutions from Brazilian system

**E2E Tests:**
- Framework: Not yet implemented
- Would test: Full workflow from data load → solve → results extraction
- Status: Partial coverage through integration tests

## Common Patterns

**Async Testing:**
Not applicable (Julia doesn't require async testing for synchronous code)

**Error Testing:**
```julia
# Test that function throws correct error type
@test_throws ArgumentError validate_positive(-1.0)

# Test with custom error message validation
@testset "Error messages include field name" begin
    try
        validate_positive(-5.0, "test_field")
        @test false  # Should not reach here
    catch e
        @test occursin("test_field", e.msg)
    end
end
```

**Examples from codebase:**
- `test/unit/test_entities_base.jl` (lines 21-44): Testing validation with multiple error cases
- `test/unit/test_thermal_entities.jl` (lines 100+): Testing invalid plant parameters
- `test/unit/test_constraints.jl`: Testing constraint building on systems without required entities

**Parameter Variation Testing:**
```julia
# Test multiple scenarios in nested structure
@testset "validate_id with custom length limits" begin
    @test validate_id("AB"; min_length = 2) == "AB"
    @test_throws ArgumentError validate_id("A"; min_length = 2)

    @test validate_id("ABC"; max_length = 3) == "ABC"
    @test_throws ArgumentError validate_id("ABCD"; max_length = 3)
end
```

**Type-Parametric Testing:**
```julia
# Test same pattern across different entity types
function test_plant_creation(plant_constructor, id, name)
    plant = plant_constructor(;
        id = id,
        name = name,
        # ... required fields
    )
    @test plant.id == id
    @test plant.name == name
end

# Use for thermal, hydro, wind, solar (if implemented)
```

## Test Execution Flow

**From `test/runtests.jl`:**
```julia
using OpenDESSEM
using Test

@testset "OpenDESSEM Tests" begin
    # Entity tests (unit)
    include("unit/test_entities_base.jl")
    include("unit/test_thermal_entities.jl")
    include("unit/test_hydro_entities.jl")
    include("unit/test_renewable_entities.jl")
    include("unit/test_network_entities.jl")
    include("unit/test_market_entities.jl")

    # Core tests (unit)
    include("unit/test_electricity_system.jl")

    # Integration tests
    include("unit/test_powermodels_adapter.jl")
    include("unit/test_variable_manager.jl")
    include("unit/test_dessem_loader.jl")
    include("integration/test_database_loader.jl")
    include("unit/test_constraints.jl")
    include("integration/test_constraint_system.jl")
end
```

**Execution:**
1. Main `@testset` creates namespace
2. Each include() file loads a test module
3. Tests in each file execute in order
4. Failed tests halt execution (unless `--project=test` config differs)
5. Final summary printed with pass/fail counts

## Pre-Commit Testing Requirements

**Mandatory before any commit (from `.claude/CLAUDE.md`):**
```bash
# 1. Run all tests - ALL MUST PASS
julia --project=test test/runtests.jl

# 2. Check coverage > 90% for core modules
julia --project=test test/coverage.jl  # If script exists

# 3. Format code
julia --project=formattools -e 'using JuliaFormatter; format(".", verbose=true)'

# 4. No temporary files
git status  # Should show no *.log, *.cache, *~, etc.

# 5. Review changes
git diff --staged
```

## Best Practices

**Test-Driven Development (TDD):**
1. Write test first (should fail)
2. Implement minimal code to pass
3. Run test (should pass)
4. Refactor if needed
5. Commit with test and implementation

**Example:**
```julia
# Step 1: Write test (fails)
@testset "ConventionalThermal validation" begin
    @test_throws ArgumentError ConventionalThermal(;
        # Invalid: capacity_mw < min_generation_mw
        capacity_mw = 100.0,
        min_generation_mw = 200.0,
        # ... other fields
    )
end

# Step 2: Implement validation in constructor
# Step 3-5: Test passes, commit
```

**Test Independence:**
- No test should depend on outcome of another test
- Tests should be runnable in any order
- Each test creates its own fixtures
- No shared state between test cases

**Clear Assertion Messages:**
```julia
# Good - clear what failed
@test plant.capacity_mw >= plant.min_generation_mw "Capacity must be >= minimum generation"

# Adequate - assertion is obvious
@test plant.id == "T_SE_001"

# Bad - no context
@test value > 0
```

**Realistic Test Data:**
- Use values from actual Brazilian system where possible
- Example: Submarket codes "SE", "S", "NE", "N" (Brazilian subdivisions)
- Example: Voltage levels 230kV, 345kV, 500kV, 600kV (typical in ONS data)
- Example: Fuel types matching DESSEM specification (NATURAL_GAS, COAL, etc.)

---

*Testing analysis: 2026-02-15*
