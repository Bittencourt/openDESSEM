# External Integrations

**Analysis Date:** 2025-02-15

## APIs & External Services

**DESSEM File Format Integration:**
- DESSEM2Julia parser - Parses official ONS DESSEM case files
  - SDK/Client: `DESSEM2Julia` package (0.1.0+)
  - Data source: ONS (Operador Nacional do Sistema) official dispatch model
  - Entry point: `load_dessem_case()` in `src/data/loaders/dessem_loader.jl`
  - Supported formats: `dessem.arq`, `entdados.dat`, `termdat.dat`, `hidr.dat` (binary), `operut.dat`, `operuh.dat`, `dadvaz.dat`, `renovaveis.dat`, `desselet.dat`, `*.pwf`

**Power Flow File Integration:**
- PWF file parser - Parses power flow network case files
  - SDK/Client: `PWF` package (0.1.0+)
  - Used by: `src/data/loaders/dessem_loader.jl` for network data conversion
  - Entry point: Referenced via DessemLoader's network entity conversion

**Network Optimization Integration:**
- PowerModels.jl - Power flow and network constraint modeling
  - SDK/Client: `PowerModels` package (1.0+)
  - Used by: `src/integration/powermodels_adapter.jl` and network constraint builder
  - Functions: `convert_to_powermodel()`, `convert_bus_to_powermodel()`, `convert_line_to_powermodel()`, `convert_gen_to_powermodel()`, `convert_load_to_powermodel()`
  - AC-OPF and DC-OPF capability for transmission network constraints

## Data Storage

**Databases:**
- PostgreSQL (production)
  - Connection client: LibPQ 1.18.0+
  - Purpose: Load system entities (thermal plants, hydro plants, buses, lines, loads, submarkets)
  - Tables expected: `thermal_plants`, `hydro_plants`, `buses`, `ac_lines`, `dc_lines`, `submarkets`, `loads`, `renewable_plants`
  - Schema documentation: `src/data/loaders/database_loader.jl` (lines 14-126)
  - Connection pattern: `LibPQ.Connection(connection_string)`
  - Entry point: `load_from_database()` in `src/data/loaders/database_loader.jl`

- SQLite (development/testing)
  - Primary use: Unit and integration test data
  - No explicit integration code; can be used via standard Julia SQLite.jl if needed

**File Storage:**
- Local filesystem only (CSV, JSON exports)
  - CSV export: `export_csv()` in `src/analysis/solution_exporter.jl`
  - JSON export: `export_json()` in `src/analysis/solution_exporter.jl`
  - DESSEM files: Local disk loader via `load_dessem_case(path)`

**Caching:**
- None detected - models computed on-demand per solve

## Authentication & Identity

**Auth Provider:**
- Custom/None - PostgreSQL uses standard connection string authentication
  - Approach: libpq connection string with optional password
  - Environment variables: Not used (connection string passed directly)

**Database Credentials:**
- Managed outside codebase (connection strings, env config)
- LibPQ handles standard PostgreSQL authentication via `.pgpass` or connection string

## Monitoring & Observability

**Error Tracking:**
- None - Errors surface as Julia exceptions
- Future: Could integrate Sentry.jl, but not currently present

**Logs:**
- Custom logging via `@info`, `@warn` macros throughout codebase
- Examples:
  - `src/data/loaders/database_loader.jl`: Log data loading progress and validation
  - `src/solvers/solver_interface.jl`: Log solver options and result status
  - `src/analysis/solution_exporter.jl`: Log export operations
- No structured logging framework (could integrate TensorBoardLogger.jl or Logging.jl formats)

## CI/CD & Deployment

**Hosting:**
- Not detected - Framework is library/CLI only (no web server)
- Can be deployed as: standalone Julia scripts, Docker containers, or integrated into larger systems

**CI Pipeline:**
- Not found - No `.github/workflows/` detected
- Manual testing via `julia --project=test test/runtests.jl`
- Opportunity: Add GitHub Actions for automated testing on PR/push

**Version Control:**
- Git-based development (repository verified)
- Branching follows: `feature/...`, `bugfix/...`, `develop`, `main` pattern (per CLAUDE.md)

## Environment Configuration

**Required env vars:**
- None mandatory - PostgreSQL connection passed as parameter
- Optional runtime config via `SolverOptions` struct

**Secrets location:**
- PostgreSQL credentials: Via connection string (external to code)
- Solver licenses (Gurobi/CPLEX): System environment or solver package configuration
- Example connection: `LibPQ.Connection("dbname=opendessem user=dessem password=...")`

**Database Connection Pattern:**
```julia
loader = DatabaseLoader(
    connection = LibPQ.Connection("host=localhost dbname=opendessem user=dessem"),
    scenario_id = "deterministic",
    base_date = Date("2024-01-15")
)
```

## Webhooks & Callbacks

**Incoming:**
- None detected - No web API server

**Outgoing:**
- None detected - Data export only (CSV, JSON, database writes)

## External File Format Support

**Input Formats:**
- **DESSEM formats** (via DESSEM2Julia):
  - Binary: `hidr.dat` (792 bytes per hydro plant record)
  - Text: `.dat` files (entdados, termdat, operut, operuh, dadvaz, renovaveis, desselet)
  - Control: `dessem.arq` (master file index)
- **Power flow**: `*.pwf` files (parsed via PWF package)
- **CSV**: Data input/output
- **JSON**: Solution export and metadata

**Output Formats:**
- **CSV**: Complete solution export (generation, commitment, storage, prices)
  - Functions: `export_csv()` creates files like `thermal_generation.csv`, `hydro_storage.csv`, etc.
  - Location: `src/analysis/solution_exporter.jl`
- **JSON**: Structured solution export with metadata
  - Function: `export_json()`
- **PostgreSQL**: Direct database insert via `export_database()`
  - Function: `export_database(result, db_conn)`

## Data Flow

**Load → Build → Solve → Export:**
1. **Load**: DESSEM files or PostgreSQL database via loader classes
2. **Build**: Entity objects (thermal, hydro, renewable, network, market)
3. **Validate**: ElectricitySystem referential integrity checks
4. **Convert**: PowerModels format for network constraints (if needed)
5. **Solve**: JuMP model via HiGHS/Gurobi/CPLEX
6. **Extract**: Solution values, duals, marginal prices
7. **Export**: CSV, JSON, or PostgreSQL

## Integration Points for Extension

**Solver Extensibility:**
- Add new solver via `SolverType` enum in `src/solvers/solver_types.jl`
- Implement optimizer factory in `get_solver_optimizer()`
- Location: `src/solvers/solver_interface.jl`

**Data Loader Extensibility:**
- Create new loader struct implementing `load_from_<source>()` pattern
- Location: `src/data/loaders/`
- Example: Create `excel_loader.jl` or `csv_loader.jl` following `dessem_loader.jl` structure

**Constraint Extensibility:**
- New constraint type extends `AbstractConstraint`
- Implement `build!(model, constraint)` method
- Location: `src/constraints/`
- Examples: `thermal_commitment.jl`, `hydro_water_balance.jl`

**Export Format Extensibility:**
- Add new export function in `src/analysis/solution_exporter.jl`
- Pattern: `export_<format>(result::SolverResult, path::String; kwargs...)`
- Return: List of created file paths or count of inserted records

---

*Integration audit: 2025-02-15*
