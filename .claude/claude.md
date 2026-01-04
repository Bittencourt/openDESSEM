# OpenDESSEM Development Guidelines

## Project Overview

**Project**: Open-source implementation of DESSEM (Daily Short-Term Hydrothermal Scheduling Model) in Julia

**Technology Stack**:
- Language: Julia 1.8+
- Optimization: JuMP.jl
- Solvers: HiGHS.jl (primary), Gurobi.jl (optional)
- Database: PostgreSQL (production), SQLite (development)
- Testing: Test.jl
- Code Formatting: JuliaFormatter.jl (Mandatory before commits)

**Architecture Philosophy**:
- Entity-driven design (model discovers entities dynamically)
- Database-ready data structures
- Modular, pluggable constraints
- Clean separation: data → model → solver → analysis

---

## Current Implementation Status

**Last Updated**: 2025-01-04

### ✅ Completed (Phase 1: Entity System Foundation)

**Validation Utilities** (`src/entities/validation.jl`):
- `validate_id()`, `validate_name()` - ID and name validation
- `validate_positive()`, `validate_non_negative()` - Numeric validation
- `validate_percentage()` - 0-100 range validation
- `validate_in_range()` - Flexible range validation with auto-swap
- `validate_min_leq_max()` - Order validation
- `validate_one_of()` - Enum/value set validation
- `validate_unique_ids()` - Duplicate detection

**Base Entity Types** (`src/entities/base.jl`):
- `AbstractEntity` - Root type for all entities
- `PhysicalEntity` - Base for physical infrastructure
- `EntityMetadata` - Timestamps, versioning, tags, properties
- Helper functions: `get_id()`, `has_id()`, `is_empty()`, `update_metadata()`, `add_tag()`, `set_property()`

**Thermal Plant Entities** (`src/entities/thermal.jl`):
- `FuelType` enum: `NATURAL_GAS`, `COAL`, `FUEL_OIL`, `DIESEL`, `NUCLEAR`, `BIOMASS`, `BIOGAS`, `OTHER`
- `ConventionalThermal` - Standard thermal plants with full UC support
- `CombinedCyclePlant` - CCGT plants with multiple operating modes

**Test Coverage**:
- **166 tests, 100% passing** (97 validation/base tests + 69 thermal plant tests)
- All entities validated on construction
- Comprehensive error testing

### 🚧 In Progress

Next priorities (following the detailed plan):
- Hydro plant entities (reservoir, run-of-river, pumped storage)
- Renewable entities (wind, solar)
- Network entities (buses, transmission lines)
- Market entities (submarkets, loads)

### 📋 Not Started

- Constraint builder system
- Database loaders (PostgreSQL/SQLite)
- Variable manager
- Objective function
- Solvers interface

---

## Core Development Rules

### 1. Test-Driven Development (TDD)

**MANDATORY**: Write tests BEFORE or alongside implementation code.

**Workflow**:
```julia
# Step 1: Write failing test
@testset "ThermalPlant creation" begin
    plant = ConventionalThermal(;
        id = "T001",
        name = "Test Plant",
        bus_id = "B001",
        submarket_id = "SE",
        fuel_type = NATURAL_GAS,  # Use FuelType enum
        capacity_mw = 500.0,
        min_generation_mw = 100.0,
        max_generation_mw = 500.0,
        ramp_up_mw_per_min = 50.0,
        ramp_down_mw_per_min = 50.0,
        min_up_time_hours = 4,
        min_down_time_hours = 2,
        fuel_cost_rsj_per_mwh = 150.0,
        startup_cost_rs = 10000.0,
        shutdown_cost_rs = 5000.0,
    )

    @test plant.id == "T001"
    @test plant.capacity_mw == 500.0
    @test plant.min_generation_mw <= plant.max_generation_mw
end

# Step 2: Run test (should fail)
# Step 3: Implement minimal code to pass test
# Step 4: Run test (should pass)
# Step 5: Refactor if needed
```

**Test Coverage Requirements**:
- Unit tests: >90% coverage for core modules (entities, constraints, variables)
- Integration tests: All major workflows (load → solve → extract)
- Validation tests: Compare against known solutions

**Test Organization**:
```
test/
├── unit/           # Test individual functions/structs
├── integration/    # Test workflows and end-to-end
└── validation/     # Test against official DESSEM results
```

### 2. Pre-Commit Verification

**MANDATORY**: Run full test suite before ANY commit.

**Pre-Commit Checklist**:
```bash
# 1. Run tests
julia --project=test test/runtests.jl

# 2. Check test coverage
julia --project=test test/coverage.jl

# 3. Format code (if using JuliaFormatter)
julia --project=formattools -e 'using JuliaFormatter; format(".", verbose=true)'

# 4. Check for temporary/auxiliary files
git status

# 5. Review changes
git diff --staged
```

**Commit Requirements**:
- ✅ All tests passing
- ✅ No temporary files (*.log, *.cache, *~, etc.)
- ✅ Code formatted consistently
- ✅ Documentation updated
- ✅ Commit message follows conventions (see below)

### 3. Documentation Standards

**MANDATORY**: Keep documentation synchronized with code.

**Documentation Requirements**:

**a) Function Documentation (docstrings)**:
```julia
"""
    create_thermal_variables!(model::DessemModel)

Dynamically create optimization variables for all thermal plants in the system.

# Arguments
- `model::DessemModel`: The DESSEM model containing system entities

# Variables Created
For each thermal plant `i` and time period `t`:
- `u[i,t]`: Binary unit commitment status
- `g[i,t]`: Continuous generation (MW)
- `z[i,t]`: Binary startup indicator
- `w[i,t]`: Binary shutdown indicator

# Example
```julia
model = DessemModel(system, time_periods=168)
create_thermal_variables!(model)
# Variables now accessible via model.variables.generation[plant_id, t]
```

# Throws
- `Error` if thermal plants have inconsistent parameters (min > max generation)

# See Also
- [`create_hydro_variables!`](@ref)
- [`create_network_variables!`](@ref)
"""
function create_thermal_variables!(model::DessemModel)
    # Implementation...
end
```

**b) Entity Documentation**:
```julia
"""
    ConventionalThermal <: ThermalPlant

Standard thermal power plant with unit commitment constraints.

# Fields
- `id::String`: Unique plant identifier (e.g., "T_001")
- `name::String`: Human-readable plant name
- `fuel_type::FuelType`: Enum value (e.g., `NATURAL_GAS`, `COAL`, `NUCLEAR`, `BIOMASS`)
- `capacity_mw::Float64`: Installed capacity (MW)
- `min_generation_mw::Float64`: Minimum stable generation (MW)
- `max_generation_mw::Float64`: Maximum generation (MW)
- `ramp_up_mw_per_min::Float64`: Ramp-up rate (MW/min)
- `ramp_down_mw_per_min::Float64`: Ramp-down rate (MW/min)
- `min_up_time_hours::Int`: Minimum time online after startup (hours)
- `min_down_time_hours::Int`: Minimum time offline after shutdown (hours)
- `fuel_cost_rsj_per_mwh::Float64`: Fuel cost (R\$/MWh), can be time-varying
- `startup_cost_rs::Float64`: Fixed startup cost (R\$)
- `shutdown_cost_rs::Float64`: Fixed shutdown cost (R\$)
- `must_run::Bool`: If true, unit must remain committed (rare)

# Constraints Applied
- Energy balance: `min_gen * u <= g <= max_gen * u`
- Ramp limits: `g[t] - g[t-1] <= ramp_up * 60`
- Minimum up/down time: prevent rapid cycling
- Startup/shutdown logic: `u[t] - u[t-1] = z[t] - w[t]`

# Example
```julia
plant = ConventionalThermal(;
    id = "T_SE_001",
    name = "Sudeste Gas Plant 1",
    bus_id = "SE_230KV_001",
    submarket_id = "SE",
    fuel_type = NATURAL_GAS,
    capacity_mw = 500.0,
    min_generation_mw = 150.0,
    max_generation_mw = 500.0,
    ramp_up_mw_per_min = 50.0,
    ramp_down_mw_per_min = 50.0,
    min_up_time_hours = 6,
    min_down_time_hours = 4,
    fuel_cost_rsj_per_mwh = 150.0,
    startup_cost_rs = 15000.0,
    shutdown_cost_rs = 8000.0,
)
```
"""
Base.@kwdef struct ConventionalThermal <: ThermalPlant
    # Fields...
end
```

**c) Update Documentation When**:
- Adding new functions/structs
- Changing function signatures
- Modifying constraint behavior
- Adding new entity types
- Changing database schema

**d) Documentation Files**:
- `README.md`: Quick start, installation, basic usage
- `docs/guide.md`: Comprehensive user guide
- `docs/architecture.md`: System design and data flow
- `docs/entity_reference.md`: All entity types with examples
- `docs/constraint_reference.md`: Constraint catalog
- `docs/api_reference.md`: Auto-generated from docstrings

### 4. Clean Repository Practices

**MANDATORY**: Remove temporary/auxiliary files before commits.

**Files to EXCLUDE from git**:
```
# Add to .gitignore
*.log
*.cache
*~
*.swp
*.swo
.vscode/
.idea/
*.bak
*.tmp
.DS_Store
Thumbs.db
__pycache__/
*.pyc
.julia/history
# Julia artifacts
deps/deps.jl
deps/build.log
Manifest.toml  # For local development only (commit for releases)
# Test artifacts
test/*.csv
test/*.h5
test/artifacts/
# Database files (local development)
*.db
*.sqlite
*.sqlite3
```

**Pre-Commit Cleanup Script**:
```bash
#!/bin/bash
# clean_before_commit.sh

echo "Cleaning temporary files..."

# Remove common temp files
find . -type f -name "*.log" -delete
find . -type f -name "*~" -delete
find . -type f -name "*.swp" -delete
find . -type f -name "*.swo" -delete
find . -type f -name ".DS_Store" -delete
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null

# Clean Julia artifacts
rm -rf deps/build.log
rm -rf deps/deps.jl

echo "✓ Cleanup complete"
echo ""
git status
```

### 5. Code Style Guidelines

**Julia Style Guide**:
- Follow official [Julia Style Guide](https://docs.julialang.org/en/v1/manual/style-guide/)
- **MANDATORY**: Format with JuliaFormatter before committing
  ```bash
  julia --project=formattools -e 'using JuliaFormatter; format(".", verbose=true)'
  ```
- Use 4 spaces for indentation (no tabs)
- Maximum line length: 92 characters
- Function names: `snake_case`
- Type names: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Use `Base.@kwdef` for structs with many fields
- **Keyword arguments**: Add spaces around `=` (e.g., `id = "T001"`, not `id="T001"`)

**Example**:
```julia
# Good
const MAX_ITERATIONS = 1000

function calculate_marginal_cost(model::DessemModel, submarket_id::String, t::Int)
    if !haskey(model.constraints.energy_balance, (submarket_id, t))
        @warn "Energy balance constraint not found" submarket_id=submarket_id t=t
        return nothing
    end

    constraint = model.constraints.energy_balance[(submarket_id, t)]
    return JuMP.dual(constraint)
end

# Bad
function CalcMC(m, sm, t)
    return m.eb[sm,t].dual
end
```

### 6. Git Commit Conventions

**Commit Message Format**:
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Build process, tooling, dependencies

**Examples**:
```
feat(thermal): add combined-cycle plant support

Add support for combined-cycle gas turbine (CCGT) plants with
3 operating modes: gas-only, combined, steam-only.

- Add CombinedCyclePlant entity type
- Implement mode transition constraints
- Add mode-specific generation variables

Closes #123

---

fix(hydro): correct cascade water balance delay

Water travel time was applied in wrong direction, causing
upstream releases to affect downstream immediately instead
of after delay period.

Fixes calculation in HydroWaterBalanceConstraint:build!()

Bug reported in issue #87
```

### 7. Branching Strategy

**Main Branches**:
- `main`: Production-ready code (always stable, tested)
- `develop`: Integration branch for features

**Feature Branches**:
- `feature/thermal-uc`: Add thermal unit commitment
- `feature/hydro-cascade`: Add cascade hydro modeling
- `feature/database-loader`: Add PostgreSQL data loading
- `bugfix/water-balance`: Fix water balance calculation

**Workflow**:
```bash
# Create feature branch
git checkout -b feature/thermal-uc

# Develop with TDD
# Write tests → Implement → Test → Commit

# Rebase with develop regularly
git checkout develop
git pull
git checkout feature/thermal-uc
git rebase develop

# Merge when ready
git checkout develop
git merge --no-ff feature/thermal-uc
git branch -d feature/thermal-uc
```

---

## Module-Specific Guidelines

### Entities Module (`src/entities/`)

**Rules**:
1. Each entity type in its own file
2. Always include docstrings explaining all fields
3. Add validation in inner constructors if needed
4. Use `Base.@kwdef` for easy construction
5. Include example in docstring

**Example**:
```julia
# src/entities/thermal.jl

"""
    ConventionalThermal <: ThermalPlant

[Full docstring here]
"""
Base.@kwdef struct ConventionalThermal <: ThermalPlant
    id::String
    name::String
    # ... other fields

    function ConventionalThermal(;
            id::String,
            name::String,
            capacity_mw::Float64,
            min_generation_mw::Float64,
            max_generation_mw::Float64,
            # ... other kwargs
            )
        # Validation
        @assert capacity_mw > 0 "Capacity must be positive"
        @assert min_generation_mw >= 0 "Min generation must be non-negative"
        @assert max_generation_mw <= capacity_mw "Max generation cannot exceed capacity"
        @assert min_generation_mw <= max_generation_mw "Min must be <= max"

        new(id, name, capacity_mw, min_generation_mw, max_generation_mw, ...)
    end
end
```

### Constraints Module (`src/constraints/`)

**Rules**:
1. Each constraint type in its own file
2. Implement `build!()` method
3. Document what entities are required
4. Add constraint metadata (name, description, priority)
5. Include example in docstring

**Example**:
```julia
# src/constraints/thermal_uc.jl

"""
    ThermalUnitCommitmentConstraint <: AbstractConstraint

Unit commitment constraints for thermal power plants.

# Required Entities
- ThermalPlant (all subtypes)

# Variables Created
None (uses existing variables from VariableManager)

# Constraints Added
For each thermal plant `i` and time period `t`:
- Capacity limits: `g_min * u[i,t] <= g[i,t] <= g_max * u[i,t]`
- Ramp rates (if enabled): `g[i,t] - g[i,t-1] <= ramp_up * 60`
- Minimum up/down time (if enabled)
- Startup/shutdown logic: `u[i,t] - u[i,t-1] = z[i,t] - w[i,t]`

# Configuration
```julia
constraint = ThermalUnitCommitmentConstraint(;
    metadata=ConstraintMetadata(;
        name="Thermal Unit Commitment",
        description="Standard UC constraints for thermal plants",
        priority=10
    ),
    include_ramp_rates=true,
    include_min_up_down=true,
    plants=[]  # Empty = all thermal plants
)

build!(model, constraint)
```
"""
Base.@kwdef struct ThermalUnitCommitmentConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    include_ramp_rates::Bool = true
    include_min_up_down::Bool = true
    plants::Vector{String} = String[]
end

function build!(model::DessemModel, constraint::ThermalUnitCommitmentConstraint)
    # Implementation...
end
```

### Data Loaders Module (`src/data/loaders/`)

**Rules**:
1. Validate data integrity on load
2. Provide clear error messages for missing/invalid data
3. Support progress reporting for large datasets
4. Log data source and timestamp
5. Return `ElectricitySystem` struct

**Example**:
```julia
# src/data/loaders/database.jl

function load_system(loader::DatabaseLoader)
    @info "Loading system from database" scenario=loader.scenario_id base_date=loader.base_date

    # Load with validation
    thermal = load_thermal_plants(loader)
    validate_thermal_plants!(thermal)  # Throws if invalid

    hydro = load_hydro_plants(loader)
    validate_hydro_plants!(hydro)

    # ... load other entities

    system = ElectricitySystem(;
        thermal_plants=thermal,
        hydro_plants=hydro,
        # ... other entities
        base_date=loader.base_date
    )

    @info "System loaded successfully" n_thermal=length(thermal) n_hydro=length(hydro)

    return system
end
```

---

## Testing Guidelines

### Unit Tests

**Location**: `test/unit/`

**Coverage**:
- All entity constructors and validation
- All constraint `build!()` methods
- All variable creation functions
- Data loader functions
- Utility functions

**Example**:
```julia
# test/unit/test_thermal_entities.jl

@testset "ThermalPlant Entities" begin
    @testset "ConventionalThermal - Constructor" begin
        plant = ConventionalThermal(;
            id="T001",
            name="Test Plant",
            bus_id="B001",
            submarket_id="SE",
            fuel_type="natural_gas",
            capacity_mw=500.0,
            min_generation_mw=100.0,
            max_generation_mw=500.0,
            ramp_up_mw_per_min=50.0,
            ramp_down_mw_per_min=50.0,
            min_up_time_hours=4,
            min_down_time_hours=2,
            fuel_cost_rsj_per_mwh=150.0,
            startup_cost_rs=10000.0,
            shutdown_cost_rs=5000.0
        )

        @test plant.id == "T001"
        @test plant.capacity_mw == 500.0
        @test plant.submarket_id == "SE"
    end

    @testset "ConventionalThermal - Validation" begin
        # Test invalid inputs
        @test_throws AssertionError ConventionalThermal(;
            id="T001",
            name="Invalid",
            capacity_mw=-100.0,  # Negative capacity
            # ... other required fields
        )

        @test_throws AssertionError ConventionalThermal(;
            id="T001",
            name="Invalid",
            capacity_mw=500.0,
            min_generation_mw=600.0,  # Min > Max
            max_generation_mw=500.0,
            # ... other fields
        )
    end
end
```

### Integration Tests

**Location**: `test/integration/`

**Coverage**:
- End-to-end workflow: load → build → solve → extract
- Multi-entity systems
- Constraint interactions
- Database loading

**Example**:
```julia
# test/integration/test_simple_system.jl

@testset "Simple 3-Plant System Integration" begin
    # Load test data
    system = load_test_system("simple_3plant")

    # Create model
    model = DessemModel(system, time_periods=24)

    # Build constraints
    add_constraint!(model, EnergyBalanceConstraint(...))
    add_constraint!(model, ThermalUnitCommitmentConstraint(...))
    add_constraint!(model, HydroWaterBalanceConstraint(...))

    # Create variables
    create_variables!(model)

    # Build objective
    build_objective!(model)

    # Solve
    solution = optimize!(model, HiGHS.Optimizer)

    # Verify
    @test is_solved_and_feasible(solution)
    @test solution.objective_value > 0
    @test all(solution.generation .>= 0)
end
```

### Validation Tests

**Location**: `test/validation/`

**Coverage**:
- Compare with official DESSEM results
- Known test cases from literature
- Benchmark instances

---

## Performance Guidelines

### Optimization Targets

**Model Size** (Brazilian SIN, 7-day horizon):
- Variables: ~50,000-100,000
- Constraints: ~100,000-200,000
- Solve time (HiGHS): < 2 hours
- Solve time (Gurobi): < 15 minutes

**Memory Usage**:
- Model building: < 4 GB RAM
- Solving: < 8 GB RAM

### Performance Best Practices

1. **Use sparse matrices** for large constraints
2. **Batch variable creation** (avoid loops in tight inner loops)
3. **Lazy constraint generation** (only create what's needed)
4. **Warm-start** from previous solve if available
5. **Profile** with ProfileView.jl regularly

---

## Documentation Workflow

### When to Update Docs

**BEFORE Commit**:
- ✅ New function added → Add docstring
- ✅ Function signature changed → Update docstring
- ✅ New constraint type → Document in constraint reference
- ✅ Database schema changed → Update schema docs
- ✅ New example → Add to examples directory

**Weekly** (if working continuously):
- Review and update README.md
- Check code examples in documentation still work
- Update architecture diagrams if needed

### Documentation Review Checklist

- [ ] All public functions have docstrings
- [ ] Docstrings include: Arguments, Returns, Example, Throws
- [ ] Examples in docstrings actually run
- [ ] API documentation generated (Documenter.jl)
- [ ] User guide reflects current features
- [ ] Entity reference includes all entity types
- [ ] Constraint reference lists all constraints

---

## Code Review Process

### Self-Review (Before Commit)

**Checklist**:
```bash
# 1. Run tests
julia --project=test test/runtests.jl

# 2. Check coverage
julia test/coverage.jl

# 3. Format code
julia -e 'using JuliaFormatter; format(".", verbose=true)'

# 4. Check docs
julia docs/make.jl

# 5. Clean temp files
./clean_before_commit.sh

# 6. Review diff
git diff
git diff --staged
```

### Peer Review (For Pull Requests)

**Review Criteria**:
- [ ] Tests pass (all, not just local)
- [ ] Code follows style guide
- [ ] Documentation updated
- [ ] No temporary files in PR
- [ ] Commit messages follow conventions
- [ ] Changes match PR description
- [ ] No unnecessary complexity added

---

## Continuous Integration

**GitHub Actions Workflow** (`.github/workflows/ci.yml`):

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Set up Julia
        uses: julia-actions/setup-julia@v1
        with:
          version: '1.10'

      - name: Install dependencies
        run: julia --project=test -e 'using Pkg; Pkg.test()'

      - name: Run tests
        run: julia --project=test test/runtests.jl

      - name: Compute coverage
        run: julia --project=test test/coverage.jl

      - name: Check documentation
        run: julia docs/make.jl

      - name: Check for temporary files
        run: |
          ! find . -name "*.log" -o -name "*~" -o -name "*.swp" | grep -q .
```

---

## Quick Reference Card

### Before ANY Code Change
1. Write test first (TDD)
2. Implement minimal code to pass
3. Run tests: `julia --project=test test/runtests.jl`
4. Format code: JuliaFormatter.format(".")
5. Update documentation

### Before ANY Commit
1. Run full test suite
2. Check coverage > 90%
3. Clean temp files: `./clean_before_commit.sh`
4. Review changes: `git diff`
5. Verify documentation builds

### Before ANY Push
1. Sync with remote: `git pull --rebase`
2. Ensure CI would pass
3. Check branch naming: `feature/...`, `bugfix/...`, etc.
4. Review commit messages

### Commit Message Template
```
<type>(<scope>): <subject>

# type: feat, fix, docs, style, refactor, test, chore
# scope: entities, constraints, data, solvers, docs, etc.
# subject: imperative mood, max 50 chars

# Body: Explain WHAT and WHY, not HOW
# Wrap at 72 chars

# Footer: References to issues (#123)
```

---

## Emergency Procedures

### Tests Failing After Commit
```bash
# Don't push! Create fix branch
git checkout -b bugfix/test-failure
# Fix tests
git add .
git commit -m "fix(tests): repair failing test suite"
git checkout develop
git merge bugfix/test-failure
```

### Accidentally Committed Temp Files
```bash
# Add to .gitignore if not already
echo "*.log" >> .gitignore

# Remove from git history (careful!)
git rm --cached *.log
git commit -m "chore: remove temporary files from tracking"
```

### Need to Undo Recent Commits
```bash
# Soft reset (keep changes)
git reset --soft HEAD~1

# Hard reset (lose changes!)
git reset --hard HEAD~1  # DANGER!
```

---

## Resources

**Julia Documentation**:
- [Julia Style Guide](https://docs.julialang.org/en/v1/manual/style-guide/)
- [JuMP Documentation](https://jump.dev/)
- [Test.jl Documentation](https://docs.julialang.org/en/v1/stdlib/Test/)

**Testing Resources**:
- [Test-Driven Development in Julia](https://www.juliabloggers.com/test-driven-development-in-julia/)
- [TestSetExtensions.jl](https://github.com/JuliaTesting/TestSetExtensions.jl)

**Documentation Tools**:
- [Documenter.jl](https://documenter.juliadocs.org/)
- [LiveServer.jl for docs preview](https://github.com/tlienart/LiveServer.jl)

**Git Resources**:
- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitHub Flow](https://guides.github.com/introduction/flow/)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01-03 | Initial development guidelines established |

---

**Last Updated**: 2025-01-04
**Maintainer**: OpenDESSEM Development Team
**Status**: Active
