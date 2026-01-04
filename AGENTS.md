# OpenDESSEM - Droid Agent Configuration

This file provides project-specific guidelines, conventions, and workflows for AI agents working on the OpenDESSEM project.

---

## Project Overview

**OpenDESSEM** is a Julia-based open-source implementation of Brazil's official day-ahead hydrothermal dispatch optimization model (DESSEM). The project uses JuMP for optimization and models complex systems including cascade hydro reservoirs, thermal unit commitment, renewable integration, and network constraints.

**Technology Stack:**
- Language: Julia 1.8+
- Optimization: JuMP.jl
- Solvers: HiGHS.jl (primary), Gurobi.jl (optional)
- Database: PostgreSQL (production), SQLite (development)
- Testing: Test.jl
- Code Formatting: JuliaFormatter.jl (Mandatory before commits)

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

Next priorities (following detailed plan):
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

## Development Philosophy

**Core Principles:**
1. **Test-Driven Development (TDD)**: Write tests BEFORE implementation
2. **Entity-Driven Design**: Model discovers entities dynamically from data
3. **Modular Constraints**: Pluggable constraint system for extensibility
4. **Clean Separation**: data → model → solver → analysis
5. **Database-Ready**: Structures designed for PostgreSQL/SQLite storage

---

## Code Style Guidelines

### Julia Conventions

- Follow official [Julia Style Guide](https://docs.julialang.org/en/v1/manual/style-guide/)
- **MANDATORY**: Format with JuliaFormatter before committing
  ```bash
  julia --project=formattools -e 'using JuliaFormatter; format(".", verbose=true)'
  ```
- **Indentation**: 4 spaces (no tabs)
- **Line length**: 92 characters maximum
- **Function names**: `snake_case`
- **Type names**: `PascalCase`
- **Constants**: `UPPER_SNAKE_CASE`
- **Struct definitions**: Use `Base.@kwdef` for structs with many fields
- **Keyword arguments**: Add spaces around `=` (e.g., `id = "T001"`, not `id="T001"`)

### Example Code Style

```julia
# Good - follows conventions
const MAX_ITERATIONS = 1000

function calculate_marginal_cost(model::DessemModel, submarket_id::String, t::Int)
    if !haskey(model.constraints.energy_balance, (submarket_id, t))
        @warn "Energy balance constraint not found" submarket_id=submarket_id t=t
        return nothing
    end

    constraint = model.constraints.energy_balance[(submarket_id, t)]
    return JuMP.dual(constraint)
end
```

### Documentation Requirements

**Every public function MUST have a docstring** with:
- Brief description
- Arguments section with types
- Returns section with types
- Example usage
- Throws section (if applicable)
- See Also references (if applicable)

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

# Example
```julia
model = DessemModel(system, time_periods=168)
create_thermal_variables!(model)
```

# Throws
- `Error` if thermal plants have inconsistent parameters

# See Also
- [`create_hydro_variables!`](@ref)
"""
function create_thermal_variables!(model::DessemModel)
    # Implementation...
end
```

---

## Testing Guidelines

### Test-Driven Development (MANDATORY)

**ALWAYS write tests BEFORE or alongside implementation code.**

### Test Structure

```
test/
├── unit/           # Test individual functions/structs
├── integration/    # Test workflows and end-to-end
└── validation/     # Test against official DESSEM results
```

### Test Coverage Requirements

- **Unit tests**: >90% coverage for core modules (entities, constraints, variables)
- **Integration tests**: All major workflows (load → solve → extract)
- **Validation tests**: Compare against known solutions

### Test Example Pattern

```julia
@testset "ThermalPlant Entities" begin
    @testset "ConventionalThermal - Constructor" begin
        plant = ConventionalThermal(;
            id="T001",
            name="Test Plant",
            bus_id="B001",
            submarket_id="SE",
            fuel_type=NATURAL_GAS,
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
        @test plant.min_generation_mw <= plant.max_generation_mw
    end

    @testset "ConventionalThermal - Validation" begin
        @test_throws AssertionError ConventionalThermal(;
            id="T001",
            name="Invalid",
            capacity_mw=-100.0,  # Negative capacity
            # ... other required fields
        )
    end
end
```

---

## Task Management Workflow

**CRITICAL**: All development work must be tracked and managed through the TODO list system.

### Task Workflow Overview

```
1. Check TODO.md for existing tasks
2. Create task if none exists
3. Create feature branch for the task
4. Implement following TDD
5. Update task status in TODO.md
6. Create pull request with task information
7. Merge to main/master
8. Mark task as completed
```

### Before Starting ANY Task

**MANDATORY STEPS**:

1. **Check TODO.md** (`docs/TODO.md`) for existing tasks
   ```bash
   # Read the TODO list
   cat docs/TODO.md
   # or open in your editor
   ```

2. **Verify task exists** for your planned work
   - Look for relevant task ID (e.g., TASK-001, TASK-002)
   - Check task status: 🟡 Planned | 🔵 In Progress | 🟢 Completed | 🔴 Blocked
   - Review task dependencies (precedence)

3. **Create new task if needed** (if no existing task matches):
   - Add new task to `docs/TODO.md`
   - Use consistent format with existing tasks
   - Include: ID, title, description, complexity, precedence
   - Set status to 🟡 Planned

4. **Update task status** to 🔵 In Progress
   - Edit the task status in TODO.md
   - Add notes about who is working on it (optional)
   - Commit the TODO.md update

### Branch Naming Convention

**Create a dedicated branch for each task**:

```bash
# Format: task-{TASK_ID}-{short-description}
git checkout -b task-TASK-001-hydroelectric-entities
git checkout -b task-TASK-002-renewable-entities
git checkout -b task-TASK-003-network-entities
```

**Branch naming rules**:
- Prefix with `task-`
- Include task ID (e.g., TASK-001, TASK-002)
- Add short, descriptive kebab-case suffix
- Example: `task-TASK-006-constraint-builder`
- Avoid: generic names like `feature`, `update`, `fix`

### Development Process

For each task, follow this workflow:

```bash
# 1. Create/update task in TODO.md
# Edit docs/TODO.md, set status to 🔵 In Progress
git add docs/TODO.md
git commit -m "docs(tasks): start TASK-XXX - task title"

# 2. Create feature branch
git checkout -b task-TASK-XXX-short-description

# 3. Follow TDD workflow
julia --project=test test/runtests.jl  # Run tests continuously

# 4. Make commits with task reference
git commit -m "feat(scope): implement feature for TASK-XXX

- Implement X, Y, Z
- Addresses requirements in TASK-XXX
- See docs/TODO.md for full task description

Refs: TASK-XXX"

# 5. Update TODO.md with progress
git add docs/TODO.md
git commit -m "docs(tasks): update progress on TASK-XXX"
```

### Pull Request Requirements

**When creating a PR to merge to main/master**:

**PR Title Format**:
```
[ TASK-XXX ] Brief description of changes
```

**PR Body Template**:
```markdown
## Summary
Implements changes for **TASK-XXX: [Task Title]**

## Task Reference
- **Task ID**: TASK-XXX
- **Task Title**: [Title from TODO.md]
- **Complexity**: [X/10]
- **Status**: Ready for review

## Description
[Brief description of what was implemented]

## Changes Made
- [ ] Feature 1 implemented
- [ ] Feature 2 implemented
- [ ] Tests added/updated
- [ ] Documentation updated

## Testing
- [ ] All existing tests pass (453+ tests)
- [ ] New tests added for this feature
- [ ] Test coverage >90% for new code
- [ ] Manually tested with [specific scenario]

## Task Completion Checklist
- [ ] All requirements from TASK-XXX completed
- [ ] Code formatted with JuliaFormatter
- [ ] Documentation updated (docstrings, examples)
- [ ] Tests passing
- [ ] No temporary files committed
- [ ] Task status updated to 🟢 Completed in TODO.md

## Files Changed
- List of modified files
- Approximate lines added/changed

## Breaking Changes
- [ ] No breaking changes
- [ ] Breaking changes described below:

## Related Issues
None

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Commented complex code sections
- [ ] Documentation updated
- [ ] No merge conflicts
```

### Task Status Updates

**Keep TODO.md synchronized with development**:

1. **When starting work**:
   - Change status from 🟡 Planned to 🔵 In Progress
   - Add start date note
   - Commit: `docs(tasks): start TASK-XXX - title`

2. **When making progress**:
   - Add progress notes in task description
   - Update completed sub-items
   - Commit: `docs(tasks): update progress on TASK-XXX`

3. **When blocked**:
   - Change status to 🔴 Blocked
   - Add blocking issue description
   - Reference blocking task IDs if applicable
   - Commit: `docs(tasks): block TASK-XXX - reason`

4. **When completing**:
   - Change status to 🟢 Completed
   - Add completion date
   - Link to commit/PR if applicable
   - Commit: `docs(tasks): complete TASK-XXX - title`

### Review Process

**Before marking task as completed**:

1. **Verify all requirements met**
   - Review task description in TODO.md
   - Check all sub-items completed
   - Ensure complexity estimate was reasonable

2. **Code quality checks**
   ```bash
   # Run full test suite
   julia --project=test test/runtests.jl

   # Check formatting
   julia --project=formattools -e 'using JuliaFormatter; format(".")'

   # Pre-commit validation
   julia scripts/pre_commit_check.jl
   ```

3. **Documentation verification**
   - All public functions have docstrings
   - Examples in docstrings work
   - AGENTS.md or CLAUDE.md updated if needed

4. **Update task status**
   - Mark as 🟢 Completed in TODO.md
   - Add completion notes
   - Include PR/commit references

### Merging to Main/Master

**Process for merging completed tasks**:

```bash
# 1. Ensure task is complete
# - All requirements from TASK-XXX met
# - All tests passing
# - Documentation updated
# - Task status marked as 🟢 Completed

# 2. Update main branch
git checkout master
git pull origin master

# 3. Merge feature branch
git merge task-TASK-XXX-short-description
# or use pull request with GitHub/GitLab

# 4. Push to remote
git push origin master

# 5. Clean up (optional)
git branch -d task-TASK-XXX-short-description
```

---

## Common Commands

### Before Any Code Change

**First, check TODO.md and update/create task**:
```bash
# 1. Check if task exists
cat docs/TODO.md | grep -A 20 "TASK-XXX"

# 2. If not, create new task following the format
# Edit docs/TODO.md and add new task

# 3. Update task status to 🔵 In Progress
git add docs/TODO.md
git commit -m "docs(tasks): start TASK-XXX"

# 4. Create feature branch
git checkout -b task-TASK-XXX-description

# 5. Then proceed with development...
julia --project=test test/runtests.jl
```

### Before Any Commit

```bash
# Step 1: Clean temporary files
./scripts/clean_before_commit.sh

# Step 2: Run pre-commit checks
julia scripts/pre_commit_check.jl

# Step 3: If all checks pass, review changes
git diff
git diff --staged
```

### Code Formatting

```bash
# Format all Julia code
julia --project=formattools -e 'using JuliaFormatter; format(".", verbose=true)'
```

### Running Tests

```bash
# Run all tests
julia --project=test test/runtests.jl

# Run specific test file
julia --project=test -e 'include("test/unit/test_thermal_entities.jl")'
```

---

## Module-Specific Patterns

### Entities Module (`src/entities/`)

**Rules:**
1. Each entity type in its own file
2. Always include comprehensive docstrings
3. Add validation in inner constructors
4. Use `Base.@kwdef` for easy construction
5. Include example in docstring
6. Include inner constructor with validation logic

**Validation Functions:**
- `validate_id(id::String; min_length::Int=1, max_length::Int=50)` - ID and name validation
- `validate_name(name::String; min_length::Int=1, max_length::Int=200)` - ID and name validation
- `validate_positive(value::Float64, field_name::String)` - Numeric validation
- `validate_strictly_positive(value::Float64, field_name::String)` - Numeric validation
- `validate_non_negative(value::Float64, field_name::String)` - Numeric validation
- `validate_percentage()` - 0-100 range validation
- `validate_in_range()` - Flexible range validation with auto-swap
- `validate_min_leq_max(min_val, max_val, min_name, max_name)` - Order validation
- `validate_one_of()` - Enum/value set validation
- `validate_unique_ids()` - Duplicate detection

**Entity Structure Pattern:**
```julia
Base.@kwdef struct MyEntity <: PhysicalEntity
    id::String
    name::String
    capacity_mw::Float64
    # ... other fields
    metadata::EntityMetadata = EntityMetadata()

    function MyEntity(;
        id::String,
        name::String,
        capacity_mw::Float64,
        # ... other kwargs
        metadata::EntityMetadata = EntityMetadata(),
    )
        # Validate all inputs
        id = validate_id(id)
        name = validate_name(name)
        capacity_mw = validate_strictly_positive(capacity_mw, "capacity_mw")

        # Additional validation logic...

        new(id, name, capacity_mw, ..., metadata)
    end
end
```

### Constraints Module (`src/constraints/`)

**Rules:**
1. Each constraint type in its own file
2. Implement `build!()` method
3. Document what entities are required
4. Add constraint metadata (name, description, priority)
5. Include example in docstring

**Constraint Pattern:**
```julia
"""
    MyConstraint <: AbstractConstraint

Brief description of the constraint.

# Required Entities
- List entity types needed

# Variables Created
- None (uses existing) OR list variables created

# Constraints Added
- List constraint formulations

# Configuration
```julia
constraint = MyConstraint(;
    metadata=ConstraintMetadata(;
        name="My Constraint",
        description="Description",
        priority=10
    ),
    # ... other config fields
)

build!(model, constraint)
```
"""
Base.@kwdef struct MyConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    # ... other fields
end

function build!(model::DessemModel, constraint::MyConstraint)
    # Implementation...
end
```

### Data Loaders Module (`src/data/loaders/`)

**Rules:**
1. Validate data integrity on load
2. Provide clear error messages for missing/invalid data
3. Support progress reporting for large datasets
4. Log data source and timestamp
5. Return `ElectricitySystem` struct

---

## Git Workflow

### Branching Strategy

- `main`: Production-ready code (always stable, tested)
- `develop`: Integration branch for features
- `feature/<feature-name>`: Feature branches
- `bugfix/<bug-name>`: Bug fix branches

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Build process, tooling, dependencies

**Examples:**
```
feat(thermal): add combined-cycle plant support

Add support for combined-cycle gas turbine (CCGT) plants with
3 operating modes: gas-only, combined, steam-only.

Closes #123

---

fix(hydro): correct cascade water balance delay

Water travel time was applied in wrong direction, causing
upstream releases to affect downstream immediately instead
of after delay period.

Fixes issue #87
```

### Pre-Commit Checklist

- [ ] All tests passing: `julia --project=test test/runtests.jl`
- [ ] No temporary files: `./scripts/clean_before_commit.sh`
- [ ] Code formatted: `julia -e 'using JuliaFormatter; format(".")'`
- [ ] Documentation updated (docstrings, examples)
- [ ] Commit message follows conventions
- [ ] Changes reviewed: `git diff`

---

## Files to Ignore

**Never commit these files:**
```
*.log
*.cache
*~
*.swp
*.swo
*.bak
*.tmp
.temp
.DS_Store
Thumbs.db
Desktop.ini
*.jl.c
*.jl.*.bc
.julia/history
deps/build.log
deps/deps.jl
__pycache__/
*.pyc
*.db
*.sqlite
*.sqlite3
*.cov
test/__outputs__/
.idea/
.vscode/
```

---

## Common Mistakes to Avoid

### Code Mistakes

- **Don't** use `!` in function names unless the function mutates its arguments
- **Don't** commit without running tests first
- **Don't** skip docstrings for public functions
- **Don't** use ambiguous variable names (prefer `generation_mw` over `g`)
- **Don't** hardcode magic numbers (use named constants)
- **Don't** skip validation in entity constructors

### Git Mistakes

- **Never** commit `.env`, `*.db`, `*.sqlite`, or sensitive files
- **Never** push directly to `main` or `develop` without review
- **Never** commit with vague messages like "fixed stuff"
- **Never** merge without resolving conflicts properly

### Documentation Mistakes

- **Don't** update code without updating related docstrings
- **Don't** write docstrings without examples
- **Don't** forget to mention what exceptions functions throw
- **Don't** leave TODO/FIXME comments in production code

---

## Performance Guidelines

### Optimization Targets

**Model Size** (Brazilian SIN, 7-day horizon):
- Variables: ~50,000-100,000
- Constraints: ~100,000-200,000
- Solve time (HiGHS): < 2 hours
- Solve time (Gurobi): < 15 minutes

**Memory Usage:**
- Model building: < 4 GB RAM
- Solving: < 8 GB RAM

### Performance Best Practices

1. Use sparse matrices for large constraints
2. Batch variable creation (avoid loops in tight inner loops)
3. Lazy constraint generation (only create what's needed)
4. Warm-start from previous solve if available
5. Profile with ProfileView.jl regularly

---

## Domain-Specific Knowledge

### Brazilian Power System

**Submarkets (4):**
- **N**: Norte (North)
- **NE**: Nordeste (Northeast)
- **SE/CO**: Sudeste/Centro-Oeste (Southeast/Central-West)
- **S**: Sul (South)

**Units:**
- Power: MW (megawatts)
- Cost: R$ (Brazilian Real)
- Fuel cost: R$/MWh
- Heat rate: GJ/MWh

### DESSEM Terminology

- **PLD**: Preço de Liquidação das Diferenças (Marginal Settlement Price)
- **ONS**: Operador Nacional do Sistema Elétrico (National System Operator)
- **CCEE**: Câmara de Comercialização de Energia Elétrica (Electricity Trading Chamber)
- **SIN**: Sistema Interligado Nacional (National Interconnected System)

---

## Available Droids

### code-quality-evaluator

**Location**: `.factory/droids/code-quality-evaluator.md`

**Purpose**: Monitors and evaluates code quality across the OpenDESSEM project. Runs all tests, checks linting rules, calculates actual code coverage, identifies potential blind spots in testing, and maintains `docs/CRITICAL_EVALUATION.md` with critical evaluation.

**When to Use**:
- After significant code changes
- Before major releases
- Weekly during active development
- Monthly for maintenance periods
- When you need quality assessment

**How to Invoke**:

```bash
# Run full quality evaluation
julia scripts/code_quality_evaluator.jl

# Or ask droid directly (in interactive mode)
"Evaluate code quality"
"Check coverage and blind spots"
"Generate quality report"
```

**What It Evaluates**:
1. **Test Suite**: Runs all tests, tracks pass/fail rates, identifies slow/flaky tests
2. **Code Coverage**: Calculates overall and module-level coverage percentages
3. **Blind Spots**: Identifies untested functions, missing edge cases, integration gaps
4. **Linting**: Checks JuliaFormatter compliance, style guide adherence
5. **Overall Score**: Weighted calculation (0-100 scale)

**Quality Thresholds**:
- Minimum acceptable: >90% overall coverage, 100% test pass rate
- Excellence standards: >95% overall coverage, >90% module coverage

**Output**:
- Detailed report at `docs/CRITICAL_EVALUATION.md`
- Executive summary with key findings
- Prioritized recommendations (P1-P4)
- Module-by-module breakdown

### instruction-set-synchronizer

**Location**: `.factory/droids/instruction-set-synchronizer.md`

**Purpose**: Maintains consistency between AGENTS.md and .claude/claude.md. Monitors both files for changes, merges content intelligently, resolves conflicts, ensures unified instruction set.

**When to Use**:
- Automatically runs when files change
- Can be manually invoked for manual sync

**Priority Rules**:
- claude.md precedence: technical specs, mandatory requirements, code style, implementation status
- AGENTS.md precedence: quick references, common mistakes, agent-focused content

### git-branch-manager

**Location**: `.factory/droids/git-branch-manager.md`

**Purpose**: Manages git workflow including branch protection, PR/merge request validation, controlled merges to dev and main branches, version tagging, and synchronization between local and remote repositories. Ensures code quality gates are enforced before merges.

**When to Use**:
- Before merging any branch to dev or main
- When creating release tags
- When checking if a branch is ready for merge
- When synchronizing local and remote repositories
- For hotfix management
- For rollback procedures

**How to Invoke**:

```bash
# Validate before merge to dev
julia scripts/validate_before_merge.jl --target=dev

# Validate before merge to main
julia scripts/validate_before_merge.jl --target=main

# Or ask droid directly (in interactive mode)
"Check if this branch can be merged"
"Validate PR #123"
"Is dev ready for main merge?"
"Sync local with remote"
"Create release tag v0.1.0"
```

**What It Manages**:
1. **Pre-Merge Validation**: 8 checks before allowing merges
   - Uncommitted changes detection
   - Remote synchronization verification
   - Full test suite execution
   - Code coverage thresholds (90% for main, 85% for dev)
   - Code formatting verification
   - Pre-commit checks
   - Secrets/credentials scanning
   - Git history quality assessment

2. **Branch Protection**: Enforced rules for dev and main branches
   - Require pull request before merging
   - Require status checks to pass
   - Require branches to be up to date
   - Block force pushes

3. **Version Management**: Semantic versioning with proper tags
   - MAJOR.MINOR.PATCH versioning
   - Automated tag creation
   - CHANGELOG updates
   - Pre-release backups

4. **Workflow Control**: Controlled flow through branches
   - Feature → Dev: Tests pass, coverage >85%
   - Dev → Main: All tests pass, coverage >90%, integration tests pass
   - Hotfix bypass for urgent fixes
   - Quality gate enforcement

**Exit Codes**:
- `0`: All checks passed - safe to merge
- `1`: Uncommitted changes detected
- `2`: Branch not up to date with remote
- `3`: Tests failed
- `4`: Coverage below threshold
- `5`: Code needs formatting
- `6`: Pre-commit checks failed
- `7`: Secrets detected in changes
- `8`: Git history quality issues
- `9`: Julia version too old

**Background Execution**:
All droids can run continuously as background processes. See `.factory/DROIDS.md` for:
- Starting/stopping droids (Windows batch scripts provided)
- Status monitoring
- Log file locations
- Configuration options

Quick start:
```batch
# Start all droids in background (Windows)
scripts\start_droids.bat

# Stop all droids
scripts\stop_droids.bat

# Check droid status
scripts\droids_status.bat
```

---

## Getting Help

### Internal Documentation

- **Development Guidelines**: `.claude/claude.md`
- **Quick Reference**: `docs/QUICK_REFERENCE.md`
- **Technical Plan**: `docs/01_DETAILED_TECHNICAL_PLAN.md`
- **Planning Document**: `docs/DESSEM_Planning_Document.md`

### External Resources

- [Julia Documentation](https://docs.julialang.org/en/v1/)
- [JuMP Documentation](https://jump.dev/)
- [Julia Style Guide](https://docs.julialang.org/en/v1/manual/style-guide/)
- [Test.jl Documentation](https://docs.julialang.org/en/v1/stdlib/Test/)

---

## Quick Reference Summary

### Before Coding
1. Read existing patterns in similar modules
2. Write tests first (TDD)
3. Check for similar implementations to reference

### During Coding
1. Follow established patterns from `src/entities/` or `src/constraints/`
2. Use validation functions from `src/entities/validation.jl`
3. Add comprehensive docstrings with examples
4. Run tests continuously

### Before Committing
1. `./scripts/clean_before_commit.sh`
2. `julia scripts/pre_commit_check.jl`
3. `git diff` to review changes
4. Write descriptive commit message

### Common Patterns

**Entity with validation:**
```julia
Base.@kwdef struct MyEntity <: PhysicalEntity
    id::String
    name::String
    value::Float64
    metadata::EntityMetadata = EntityMetadata()

    function MyEntity(; id::String, name::String, value::Float64, metadata::EntityMetadata = EntityMetadata())
        id = validate_id(id)
        name = validate_name(name)
        value = validate_positive(value, "value")
        new(id, name, value, metadata)
    end
end
```

**Constraint with metadata:**
```julia
Base.@kwdef struct MyConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
end

function build!(model::DessemModel, constraint::MyConstraint)
    # Add constraints to model
end
```

**Test structure:**
```julia
@testset "Feature Name" begin
    @testset "Specific behavior" begin
        # Arrange
        input = setup()

        # Act
        result = process(input)

        # Assert
        @test result == expected
    end
end
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.3 | 2026-01-04 | Added git-branch-manager droid: Comprehensive git workflow management including branch protection, PR/merge request validation, controlled merges to dev and main, version tagging, and remote synchronization. Added validation script `scripts/validate_before_merge.jl` with 8 pre-merge checks. |
| 1.2 | 2025-01-04 | Added code-quality-evaluator droid: Comprehensive quality assessment with test execution, coverage calculation, blind spot detection, linting checks, and automated reporting to docs/CRITICAL_EVALUATION.md. Added "Available Droids" section documenting both code-quality-evaluator and instruction-set-synchronizer. |
| 1.1 | 2025-01-04 | Synced with claude.md: Updated Julia version to 1.8+, added JuliaFormatter mandatory requirement, added keyword argument spacing convention, added Current Implementation Status section, expanded validation functions list |
| 1.0 | 2025-01-04 | Initial AGENTS.md created from project documentation |

---

**Last Updated**: 2026-01-04
**Maintainer**: OpenDESSEM Development Team
**Status**: Active
