# OpenDESSEM Quick Reference Card

## Essential Commands

### Running Tests
```bash
# Run all tests
julia --project=test test/runtests.jl

# Run specific test file
julia --project=test test/unit/test_thermal_entities.jl

# Run tests with coverage
julia --project=test -e 'using Pkg; Pkg.test(coverage=true)'
```

### Code Quality
```bash
# Format code
julia -e 'using JuliaFormatter; format(".")'

# Check before commit
julia scripts/pre_commit_check.jl

# Clean temp files
./scripts/clean_before_commit.sh
```

### Git Workflow
```bash
# Start new feature
git checkout -b feature/my-feature

# Commit with checks
./scripts/clean_before_commit.sh
julia scripts/pre_commit_check.jl
git add <files>
git commit -m "feat(scope): description"

# Push and create PR
git push origin feature/my-feature
gh pr create
```

### Documentation
```bash
# Build documentation
cd docs
julia --project=. make.jl

# Preview documentation
cd docs
julia --project=. -e 'using LiveServer; serve(dir="build")'
```

---

## Development Rules Summary

### ✅ ALWAYS Do
1. **Write tests first** (TDD)
2. **Run full test suite** before commit
3. **Clean temp files** before commit
4. **Update documentation** with code changes
5. **Follow commit conventions**
6. **Review your code** before pushing

### ❌ NEVER Do
1. Commit without tests passing
2. Commit temporary files
3. Push without reviewing changes
4. Skip documentation updates
5. Ignore failing tests
6. Commit broken code

---

## Commit Message Template

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

**Example**:
```
feat(thermal): add combined-cycle plant support

Implement CCGT plants with 3 operating modes:
- Gas turbine only
- Combined cycle (GT + Steam)
- Steam turbine only

Closes #123
```

---

## File Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Modules | `snake_case.jl` | `thermal_plants.jl` |
| Tests | `test_<name>.jl` | `test_thermal_entities.jl` |
| Entities | `PascalCase` | `ConventionalThermal` |
| Functions | `snake_case()` | `create_variables!()` |
| Constraints | `*Constraint` | `EnergyBalanceConstraint` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_ITERATIONS` |

---

## Code Template

### Function with Documentation
```julia
"""
    brief_description(args)

Detailed description of what the function does.

# Arguments
- `arg1::Type`: Description
- `arg2::Type`: Description

# Returns
- `Type`: Description of return value

# Example
```julia
result = function_name(arg1, arg2)
```

# Throws
- `Error`: When and why

# See Also
- [`related_function`](@ref)
"""
function function_name(arg1::Type, arg2::Type)
    # Implementation
end
```

### Entity Struct
```julia
"""
    EntityType

Brief description.

# Fields
- `field1::Type`: Description
- `field2::Type`: Description

# Example
```julia
entity = EntityType(;
    field1 = value1,
    field2 = value2
)
```
"""
Base.@kwdef struct EntityType
    field1::Type
    field2::Type
end
```

---

## Pre-Commit Checklist

- [ ] All tests passing: `julia --project=test test/runtests.jl`
- [ ] Code formatted: `julia -e 'using JuliaFormatter; format(".")'`
- [ ] Documentation updated
- [ ] Temp files cleaned: `./scripts/clean_before_commit.sh`
- [ ] Changes reviewed: `git diff`
- [ ] Commit message follows conventions

---

## Common Issues & Solutions

### Tests Failing
```bash
# Run with verbose output
julia --project=test test/runtests.jl --verbose

# Run specific failing test
julia --project=test -e 'include("test/unit/test_failing.jl")'
```

### Git Rejecting Push
```bash
# Pull with rebase
git pull --rebase origin develop

# Resolve conflicts, then:
git add .
git rebase --continue
```

### Documentation Won't Build
```bash
cd docs
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. make.jl
```

### Package Not Found
```bash
# Activate project environment
julia --project=.

# Instantiate dependencies
julia -e 'using Pkg; Pkg.instantiate()'

# Or update
julia -e 'using Pkg; Pkg.update()'
```

---

## Directory Structure Quick Reference

```
openDESSEM/
├── .claude/           # Development guidelines
├── config/            # Configuration files
├── database/          # Database schema and scripts
├── docs/              # Documentation
├── examples/          # Example scripts
├── scripts/           # Utility scripts
├── src/               # Source code
│   ├── core/          # Core model structures
│   ├── constraints/   # Constraint implementations
│   ├── data/          # Data loading and management
│   ├── entities/      # Entity type definitions
│   ├── solvers/       # Solver interfaces
│   ├── analysis/      # Results and analysis
│   └── utils/         # Utility functions
└── test/              # Test suites
    ├── fixtures/      # Test data
    ├── integration/   # Integration tests
    ├── unit/          # Unit tests
    └── validation/    # Validation tests
```

---

## Keyboard Shortcuts (Julia REPL)

| Action | Shortcut |
|--------|----------|
| Enter help mode | `?` |
| Enter shell mode | `;` |
| Enter package mode | `]` |
| Clear screen | `Ctrl + L` |
| Exit | `Ctrl + D` |
| Interrupt | `Ctrl + C` |

---

## Environment Variables (Optional)

```bash
# Database connection
export OPENSESSEM_DB_HOST=localhost
export OPENSESSEM_DB_PORT=5432
export OPENSESSEM_DB_NAME=opendessem
export OPENSESSEM_DB_USER=opendessem
export OPENSESSEM_DB_PASSWORD=secret

# Solver paths
export GUROBI_HOME=/opt/gurobi/linux64
export HIGHS_DIR=/opt/highs
```

---

## Useful Julia Packages for Development

```julia
# Add to development environment
using Pkg
Pkg.add([
    "Test",           # Testing framework
    "JuliaFormatter", # Code formatting
    "Documenter",     # Documentation
    "Revise",         # Code hot-reloading
    "ProfileView",    # Performance profiling
    "BenchmarkTools", # Benchmarking
    "BenchmarkTools"  # Performance testing
])
```

---

## Getting Help

1. **Check documentation**: `docs/guide.md`
2. **Check examples**: `examples/`
3. **Check tests**: `test/` for usage examples
4. **Read source code**: `src/` with inline documentation
5. **Open issue**: GitHub Issues

---

## Quick Start

```bash
# Clone repository
git clone <repo-url>
cd openDESSEM

# Install Julia dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run tests
julia --project=test test/runtests.jl

# Ready to develop!
```

---

**Last Updated**: 2025-01-03
**Version**: 1.0
