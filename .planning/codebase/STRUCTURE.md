# Codebase Structure

**Analysis Date:** 2025-02-15

## Directory Layout

```
/home/pedro/programming/openDESSEM/
├── src/                           # Main source code
│   ├── OpenDESSEM.jl             # Module definition and exports
│   ├── entities/                  # Domain entity types
│   │   ├── Entities.jl           # Module definition
│   │   ├── validation.jl         # Reusable validation utilities
│   │   ├── base.jl               # AbstractEntity, PhysicalEntity, EntityMetadata
│   │   ├── thermal.jl            # ConventionalThermal, CombinedCyclePlant
│   │   ├── hydro.jl              # ReservoirHydro, RunOfRiverHydro, PumpedStorageHydro
│   │   ├── renewable.jl          # WindPlant, SolarPlant
│   │   ├── network.jl            # Bus, ACLine, DCLine, NetworkLoad
│   │   └── market.jl             # Submarket, Load, BilateralContract, Interconnection
│   ├── core/                      # Core system container
│   │   └── electricity_system.jl  # ElectricitySystem aggregate root
│   ├── data/                      # Data loading functionality
│   │   └── loaders/
│   │       ├── dessem_loader.jl   # ONS DESSEM file format loading
│   │       └── database_loader.jl # PostgreSQL database loading
│   ├── integration/               # External library integration
│   │   ├── Integration.jl         # Module definition
│   │   └── powermodels_adapter.jl # PowerModels.jl format conversion
│   ├── variables/                 # Optimization variable creation
│   │   └── variable_manager.jl    # JuMP variable builders
│   ├── constraints/               # Constraint builder system
│   │   ├── Constraints.jl         # Module definition
│   │   ├── constraint_types.jl    # AbstractConstraint, ConstraintMetadata
│   │   ├── thermal_commitment.jl  # ThermalCommitmentConstraint
│   │   ├── hydro_water_balance.jl # HydroWaterBalanceConstraint
│   │   ├── hydro_generation.jl    # HydroGenerationConstraint
│   │   ├── submarket_balance.jl   # SubmarketBalanceConstraint
│   │   ├── submarket_interconnection.jl  # SubmarketInterconnectionConstraint
│   │   ├── renewable_limits.jl    # RenewableLimitConstraint
│   │   └── network_powermodels.jl # NetworkPowerModelsConstraint
│   ├── objective/                 # Objective function builders
│   │   ├── Objective.jl           # Module definition
│   │   ├── objective_types.jl     # AbstractObjective, ObjectiveMetadata
│   │   └── production_cost.jl     # ProductionCostObjective
│   ├── solvers/                   # Optimization solver interface
│   │   ├── Solvers.jl             # Module definition
│   │   ├── solver_types.jl        # SolverType enum, SolverOptions, SolverResult
│   │   ├── solver_interface.jl    # optimize!() main function
│   │   ├── solution_extraction.jl # Result extraction utilities
│   │   └── two_stage_pricing.jl   # UC → SCED two-stage workflow
│   ├── analysis/                  # Solution analysis and export
│   │   ├── Analysis.jl            # Module definition
│   │   └── solution_exporter.jl   # CSV, JSON, database export
│   └── utils/                     # Utility functions (currently empty)
├── test/                          # Test suite
│   ├── runtests.jl               # Main test runner
│   ├── unit/                      # Unit tests
│   │   ├── test_entities_base.jl           # AbstractEntity, PhysicalEntity tests
│   │   ├── test_thermal_entities.jl        # ConventionalThermal, CombinedCycle tests
│   │   ├── test_hydro_entities.jl          # HydroPlant variants tests
│   │   ├── test_renewable_entities.jl      # WindPlant, SolarPlant tests
│   │   ├── test_network_entities.jl        # Bus, ACLine, DCLine tests
│   │   ├── test_market_entities.jl         # Submarket, Load tests
│   │   ├── test_electricity_system.jl      # ElectricitySystem validation tests
│   │   ├── test_variable_manager.jl        # Variable creation tests
│   │   ├── test_dessem_loader.jl           # DESSEM data loading tests
│   │   ├── test_powermodels_adapter.jl     # PowerModels conversion tests
│   │   └── test_constraints.jl             # Constraint builder tests
│   └── integration/               # Integration tests
│       ├── test_database_loader.jl         # PostgreSQL loading tests
│       ├── test_constraint_system.jl       # Full constraint system tests
│       └── test_pwf_loader.jl             # PowerFlow file tests
├── examples/                      # Example workflows
│   ├── README.md                 # Examples documentation
│   ├── wizard_example.jl         # Interactive REPL tutorial
│   ├── wizard_transcript.jl      # Recorded wizard session
│   ├── ons_data_example.jl       # ONS DESSEM data loading example
│   ├── complete_workflow_example.jl  # End-to-end workflow example
│   └── docs/                     # Example documentation
├── docs/                          # User documentation
│   ├── README.md
│   ├── Sample/                    # Sample ONS data files
│   └── maintenance/               # Maintenance guides
├── scripts/                       # Utility scripts
│   ├── pre_commit_check.jl
│   ├── code_quality_evaluator.jl
│   └── [other automation scripts]
├── config/                        # Configuration files
├── database/                      # Database schema and migrations
├── .planning/                     # Planning and design documents
├── .claude/                       # Project guidelines
├── .factory/                      # Development factories
├── .vscode/                       # VS Code settings
└── .git/                          # Git repository
```

## Directory Purposes

**`src/entities/`**
- Purpose: Define all domain concepts as immutable data structures
- Contains: Entity types (Thermal, Hydro, Renewable, Network, Market)
- Key files:
  - `validation.jl`: Reusable validators (`validate_positive()`, `validate_non_negative()`, etc.)
  - `base.jl`: Foundation types (`AbstractEntity`, `PhysicalEntity`, `EntityMetadata`)
  - Type-specific files: `thermal.jl`, `hydro.jl`, `renewable.jl`, `network.jl`, `market.jl`

**`src/core/`**
- Purpose: Central system container providing referential integrity
- Key files: `electricity_system.jl` with `ElectricitySystem` struct
- Provides: Query functions, validation on construction

**`src/data/loaders/`**
- Purpose: Convert external data formats to OpenDESSEM entities
- Key files:
  - `dessem_loader.jl`: Load from ONS DESSEM directory structure
  - `database_loader.jl`: Load from PostgreSQL database
- Pattern: Loaders construct entity vectors that feed to `ElectricitySystem()`

**`src/integration/`**
- Purpose: Integration with external optimization libraries
- Key files: `powermodels_adapter.jl` converting to PowerModels.jl format
- Used for: Network-constrained optimization via PowerModels

**`src/variables/`**
- Purpose: Create JuMP optimization variables
- Key files: `variable_manager.jl` with functions like `create_thermal_variables!()`
- Provides: Variable indexing utilities for querying solution

**`src/constraints/`**
- Purpose: Modular constraint builder system
- Key files:
  - `constraint_types.jl`: Abstract framework
  - Type-specific files: `thermal_commitment.jl`, `hydro_water_balance.jl`, etc.
- Pattern: Each constraint type has `build!(model, system, constraint)` method

**`src/objective/`**
- Purpose: Objective function builders
- Key files:
  - `objective_types.jl`: Abstract framework
  - `production_cost.jl`: Cost minimization objective
- Pattern: Implements `build!(model, system, objective)`

**`src/solvers/`**
- Purpose: Unified solver interface across HiGHS, Gurobi, CPLEX, GLPK
- Key files:
  - `solver_types.jl`: SolverType enum, SolverOptions, SolverResult
  - `solver_interface.jl`: `optimize!()` main function
  - `solution_extraction.jl`: Result extraction (`get_thermal_generation()`, etc.)
  - `two_stage_pricing.jl`: UC→SCED workflow for LMP calculation

**`src/analysis/`**
- Purpose: Export and analyze solution results
- Key files: `solution_exporter.jl` with CSV/JSON/database export

**`test/unit/`**
- Purpose: Unit test each module in isolation
- Organization: One test file per source module (e.g., `test_thermal_entities.jl` for `thermal.jl`)
- Coverage: >90% target for core modules

**`test/integration/`**
- Purpose: Test end-to-end workflows and module interactions
- Key tests: Constraint system building, data loading pipelines

**`examples/`**
- Purpose: Demonstrate typical workflows
- Key files:
  - `ons_data_example.jl`: Load real ONS DESSEM data
  - `complete_workflow_example.jl`: Full load→build→solve→extract workflow
  - `wizard_example.jl`: Interactive REPL tutorial

## Key File Locations

**Entry Points:**
- `src/OpenDESSEM.jl`: Main module definition with all exports
- Module functions available via `using OpenDESSEM` (e.g., `create_thermal_variables!()`, `optimize!()`)

**Configuration:**
- `Project.toml`: Julia package configuration (dependencies, version)
- `Manifest.toml`: Locked dependency versions
- `.julia/`: Julia artifact cache (auto-generated)
- `config/`: Database connection strings, solver settings (not in git)

**Core Logic:**
- `src/core/electricity_system.jl`: Central `ElectricitySystem` aggregate root
- `src/entities/*.jl`: All domain entity types
- `src/constraints/Constraints.jl`: Constraint builder framework
- `src/solvers/Solvers.jl`: Solver interface and result handling

**Testing:**
- `test/runtests.jl`: Main test entry point (runs all tests)
- `test/unit/`: Unit tests for each module
- `test/integration/`: Integration tests for workflows

## Naming Conventions

**Files:**
- Snake case: `variable_manager.jl`, `solver_interface.jl`, `thermal_commitment.jl`
- Corresponding module name in file: `module Variables`, `module Solvers`
- Test files: `test_*_*.jl` matching source module (e.g., `test_variable_manager.jl`)

**Directories:**
- Lowercase: `entities/`, `constraints/`, `solvers/`, `analysis/`
- Descriptive: `data/loaders/` not just `data/`

**Types (PascalCase):**
- Concrete types: `ConventionalThermal`, `ReservoirHydro`, `WindPlant`, `Bus`, `ACLine`, `Submarket`, `Load`
- Abstract types: `AbstractConstraint`, `AbstractEntity`, `PhysicalEntity`, `ThermalPlant`, `HydroPlant`
- Enums: `FuelType`, `RenewableType`, `ForecastType`, `SolverType`

**Functions (snake_case):**
- Variable creation: `create_thermal_variables!()`, `create_hydro_variables!()`
- Constraint building: `build!(model, system, constraint)`
- Objective building: `build!(model, system, objective)`
- Solving: `optimize!(model, optimizer)`
- Solution extraction: `get_thermal_generation()`, `get_submarket_lmps()`
- Data loading: `load_dessem_case()`, `load_from_database()`
- Validation: `validate_system()`, `validate_constraint_system()`

**Constants (UPPER_SNAKE_CASE):**
- Fuel types: `NATURAL_GAS`, `COAL`, `FUEL_OIL`, `DIESEL`, `NUCLEAR`, `BIOMASS`, `BIOGAS`
- Renewable types: `WIND`, `SOLAR`
- Forecast types: `DETERMINISTIC`, `STOCHASTIC`, `SCENARIO_BASED`
- Solver types: `HIGHS`, `GUROBI`, `CPLEX`, `GLPK`

## Where to Add New Code

**New Entity Type:**
- Create file: `src/entities/my_entity.jl`
- Define struct inheriting from appropriate abstract type (`AbstractEntity`, `PhysicalEntity`, etc.)
- Add to `src/entities/Entities.jl`: `include("my_entity.jl")` and export
- Add tests: `test/unit/test_my_entity.jl`

**New Constraint Type:**
- Create file: `src/constraints/my_constraint.jl`
- Define struct inheriting from `AbstractConstraint` with `metadata::ConstraintMetadata` field
- Implement `build!(model, system, constraint)` method
- Add to `src/constraints/Constraints.jl`: `include("my_constraint.jl")` and export
- Add tests: Include in `test/unit/test_constraints.jl` or create `test/integration/test_my_constraint.jl`

**New Objective Type:**
- Create file: `src/objective/my_objective.jl`
- Define struct inheriting from `AbstractObjective` with `metadata::ObjectiveMetadata` field
- Implement `build!(model, system, objective)` method
- Add to `src/objective/Objective.jl`: `include("my_objective.jl")` and export
- Add tests: Create `test/unit/test_my_objective.jl`

**New Data Loader:**
- Create file: `src/data/loaders/my_loader.jl`
- Implement loader following pattern of `dessem_loader.jl` or `database_loader.jl`
- Return `ElectricitySystem` from load function
- Add to main OpenDESSEM.jl module exports
- Add tests: Create `test/integration/test_my_loader.jl`

**New Utility Function:**
- Check if it belongs in existing module (e.g., solution extraction in `solvers/`)
- If cross-cutting, add to `src/utils/` (currently empty)
- Document with docstring including examples
- Add tests in appropriate test file

**New Example:**
- Create file: `examples/my_example.jl`
- Include detailed comments and docstring explaining workflow
- Reference existing examples for style guide
- Update `examples/README.md` to describe new example

## Special Directories

**`.planning/codebase/`**
- Purpose: GSD (Goal-Seeking Debugger) codebase analysis documents
- Generated: By `/gsd:map-codebase` command
- Committed: Yes
- Contents: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, STACK.md, INTEGRATIONS.md, CONCERNS.md

**`database/`**
- Purpose: Database schema and migration scripts
- Generated: No (created manually)
- Committed: Yes
- Contains: PostgreSQL schema files, migration scripts

**`.factory/`**
- Purpose: Factory patterns and template code generation
- Generated: No
- Committed: Yes

**`config/`**
- Purpose: Non-secret configuration files
- Generated: No
- Committed: Yes
- Note: Secrets go in `.env` (not committed)

**`.vscode/`**
- Purpose: VS Code workspace settings and extensions
- Generated: No
- Committed: Yes
- Contains: Julia debugger setup, formatters

**`docs/Sample/`**
- Purpose: Sample ONS DESSEM data for examples
- Generated: No (downloaded from ONS)
- Committed: Yes (via Git LFS potentially)
- Contains: Real DESSEM case files (dessem.arq, termdat.dat, etc.)

---

*Structure analysis: 2025-02-15*
