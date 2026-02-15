# Technology Stack

**Analysis Date:** 2025-02-15

## Languages

**Primary:**
- Julia 1.8+ - Core language for optimization model development and constraint solving

**Secondary:**
- SQL - PostgreSQL database queries for data loading
- Shell/Bash - Build scripts and development utilities

## Runtime

**Environment:**
- Julia 1.8+ (specified in Project.toml)
- Platform support: Linux, macOS, Windows

**Package Manager:**
- Julia Pkg (built-in)
- Lockfile: `Manifest.toml` (present)

## Frameworks

**Core Optimization:**
- JuMP 1.0+ - Mathematical optimization modeling (core framework for building mixed-integer linear programs)
- MathOptInterface 1.0+ - Standardized interface between JuMP and solvers

**Solver Integration:**
- HiGHS 1.0+ - Primary open-source solver (fully integrated, required)
- Gurobi.jl - Optional commercial solver (lazy import, installation required separately)
- CPLEX.jl - Optional commercial solver (lazy import, installation required separately)
- GLPK.jl - Optional open-source solver (lazy import, installation required separately)

**Network Optimization:**
- PowerModels 1.0+ - Power flow modeling and network constraints (AC/DC-OPF support)

**Data Processing:**
- CSV 0.10+ - CSV file I/O for solution export and data loading
- DataFrames 1.0+ - Tabular data structures for analysis and querying
- JSON3 1.0+ - JSON serialization for solution export and web APIs
- Dates (stdlib) - Date/time handling throughout system

**Database:**
- LibPQ 1.18.0+ - PostgreSQL client library for direct database access

**Custom/External Packages:**
- DESSEM2Julia 0.1.0+ - Parser for ONS DESSEM file formats (binary hidr.dat, text files)
- PWF 0.1.0+ - Power flow data file parser for network case files

**Testing:**
- Test.jl (stdlib) - Built-in Julia testing framework
- JuliaFormatter (extras) - Code formatting and style compliance

**Documentation:**
- Documenter.jl (extras) - Documentation generation (not yet integrated in main)

## Key Dependencies

**Critical:**
- JuMP - Core optimization modeling; cannot be substituted
- HiGHS - Primary solver; provides reliability and reproducibility
- MathOptInterface - Essential bridge between JuMP and solver implementations
- PowerModels - Network constraint modeling; enables realistic transmission network representation

**Infrastructure:**
- LibPQ - Enables production PostgreSQL data loading for ONS/CCEE systems
- DESSEM2Julia - Converts official ONS DESSEM files to OpenDESSEM entities
- DataFrames - Analysis and result post-processing
- CSV/JSON3 - Multi-format solution export

**Optional (Lazy-Loaded):**
- Gurobi - Commercial solver for large/complex instances (faster than HiGHS, requires license)
- CPLEX - Alternative commercial solver (requires license and installation)
- GLPK - Fallback open-source solver for resource-constrained environments

## Configuration

**Environment:**
- Julia project-based isolation via `Project.toml`
- No explicit environment variables required for basic usage
- Optional runtime configuration via `SolverOptions` struct for solver parameters
- Database connections use connection strings (e.g., `"dbname=opendessem"`)

**Build:**
- No compiled build step required (Julia uses JIT compilation)
- Dependency management: `Pkg.instantiate()` for first-time setup
- Optional code formatting: `JuliaFormatter.format()` (pre-commit requirement per guidelines)

**Solver Configuration:**
- `SolverOptions` struct in `src/solvers/solver_types.jl` provides:
  - `verbose::Bool` - Solver output control
  - `time_limit_seconds::Union{Nothing, Float64}` - Wall-clock time limit
  - `threads::Int` - Thread count (if supported by solver)
  - `mip_gap::Union{Nothing, Float64}` - MIP optimality gap tolerance
  - `solver_specific::Dict{String, Any}` - Solver-specific raw parameters

## Platform Requirements

**Development:**
- Julia 1.8+ installed
- PostgreSQL client libraries (for LibPQ, optional for file-based workflows)
- 2+ GB RAM minimum (model building)
- C compiler (required by some Julia packages for binary compilation)
- Git (version control)

**Production:**
- Julia 1.8+ runtime
- PostgreSQL database (for production data loading)
- 8+ GB RAM (recommended for large systems like Brazilian SIN with 50k-100k variables)
- 2+ CPU cores (for parallel solver execution)
- No web server or containerization required by framework (can be deployed standalone or in Docker)

**Testing:**
- Julia test environment configured in `test/Project.toml`
- All tests run via `julia --project=test test/runtests.jl`

---

*Stack analysis: 2025-02-15*
