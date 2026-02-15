# Architecture

**Analysis Date:** 2025-02-15

## Pattern Overview

**Overall:** Entity-driven layered architecture with modular constraint building and PowerModels.jl integration

**Key Characteristics:**
- Entity-first design: All domain entities (thermal, hydro, renewable plants, network, market) defined upfront
- Database-ready data structures: Entities designed for PostgreSQL persistence
- Unified container pattern: `ElectricitySystem` acts as central data aggregate root
- Modular constraint builder: Pluggable constraint system with extensible architecture
- Network abstraction: PowerModels.jl integration for AC/DC power flow constraints
- Solver abstraction: Unified interface supporting HiGHS, Gurobi, CPLEX, GLPK
- Clean separation: Data → Model Building → Constraint Assembly → Solution Extraction

## Layers

**Entity Layer:**
- Purpose: Define all domain concepts as type-safe data structures
- Location: `src/entities/`
- Contains: ThermalPlant, HydroPlant, RenewablePlant, Bus, ACLine, DCLine, Submarket, Load, Interconnection
- Depends on: Validation utilities
- Used by: Core system, loaders, variable manager, constraints

**Core System Layer:**
- Purpose: Unified container providing referential integrity validation and querying
- Location: `src/core/electricity_system.jl`
- Contains: `ElectricitySystem` struct validating all foreign keys on construction
- Depends on: Entity types
- Used by: All higher layers (variables, constraints, solvers)

**Data Loading Layer:**
- Purpose: Convert external data formats (DESSEM files, PostgreSQL, SQLite) to OpenDESSEM entities
- Location: `src/data/loaders/`
- Contains: `DessemLoader` for ONS DESSEM format, `DatabaseLoader` for PostgreSQL
- Depends on: Entity types, validation utilities
- Used by: Applications, workflow examples

**Integration Layer:**
- Purpose: Convert OpenDESSEM entities to other library formats
- Location: `src/integration/powermodels_adapter.jl`
- Contains: `PowerModelsAdapter` converting buses, lines, generators, loads to PowerModels dict format
- Depends on: Entity types
- Used by: Network-constrained optimization workflows

**Variable Manager Layer:**
- Purpose: Create all JuMP optimization variables for thermal, hydro, renewable units
- Location: `src/variables/variable_manager.jl`
- Contains: Variable creation functions with indexing utilities
- Depends on: JuMP, ElectricitySystem
- Used by: Model builders

**Constraint Builder Layer:**
- Purpose: Modular, pluggable constraint system for building optimization formulations
- Location: `src/constraints/`
- Contains: Abstract constraint framework + 7 concrete constraint types
- Depends on: JuMP, ElectricitySystem, entity types
- Used by: Optimization workflows

**Objective Layer:**
- Purpose: Define objective functions for optimization
- Location: `src/objective/`
- Contains: `ProductionCostObjective` and framework for custom objectives
- Depends on: JuMP, ElectricitySystem, variable manager
- Used by: Optimization workflows

**Solver Layer:**
- Purpose: Unified solver interface with two-stage pricing for unit commitment
- Location: `src/solvers/`
- Contains: Solver type enum, options, result types, solution extraction functions
- Depends on: JuMP, MathOptInterface, ElectricitySystem
- Used by: Main optimization workflows

**Analysis Layer:**
- Purpose: Export and analyze solution results
- Location: `src/analysis/`
- Contains: CSV, JSON, database export functions
- Depends on: Solver results
- Used by: Result visualization and reporting

## Data Flow

**Workflow: Load → Build → Solve → Extract**

1. **Data Loading Phase**
   - Source: DESSEM files or PostgreSQL database
   - Loader: `DessemLoader` or `DatabaseLoader` from `src/data/loaders/`
   - Output: `Vector{ConventionalThermal}`, `Vector{HydroPlant}`, etc.

2. **System Assembly Phase**
   - Function: `ElectricitySystem()` constructor in `src/core/electricity_system.jl`
   - Input: Entity vectors from loading phase
   - Validation: Referential integrity checking (bus_id, submarket_id references)
   - Output: Single `ElectricitySystem` aggregate root

3. **Variable Creation Phase**
   - Functions: `create_thermal_variables!()`, `create_hydro_variables!()`, etc. in `src/variables/variable_manager.jl`
   - Model: JuMP.Model instance
   - Input: ElectricitySystem, time periods
   - Output: JuMP variables indexed by entity and time

4. **Constraint Building Phase**
   - Framework: Constraint builder pattern via `build!(model, system, constraint)` in `src/constraints/`
   - Types: `ThermalCommitmentConstraint`, `HydroWaterBalanceConstraint`, `SubmarketBalanceConstraint`, etc.
   - Input: JuMP model, ElectricitySystem
   - Output: Constraints added to model

5. **Objective Building Phase**
   - Function: `build!(model, system, objective)` in `src/objective/`
   - Type: `ProductionCostObjective` or custom
   - Input: JuMP model, ElectricitySystem
   - Output: Objective function added to model

6. **Solve Phase**
   - Function: `optimize!(model, system, optimizer)` in `src/solvers/solver_interface.jl`
   - Optimizer: HiGHS.Optimizer, Gurobi.Optimizer, etc.
   - Output: `SolverResult` with objective value, status, solver statistics

7. **Solution Extraction Phase**
   - Functions: `get_thermal_generation()`, `get_hydro_storage()`, `get_submarket_lmps()` in `src/solvers/solution_extraction.jl`
   - Input: SolverResult
   - Output: Extracted values by entity and time period

**State Management:**
- **Immutable entities**: Entity types are immutable (struct), never modified
- **Metadata tracking**: EntityMetadata field on each entity for tags, versioning
- **Model state**: JuMP.Model holds all variables and constraints (stateful)
- **Result state**: SolverResult struct encapsulates complete solution snapshot

## Key Abstractions

**ElectricitySystem:**
- Purpose: Central aggregate root holding all system entities
- Location: `src/core/electricity_system.jl`
- Provides: Query functions (`get_thermal_plant()`, `get_bus()`, `count_generators()`)
- Enforces: Referential integrity on construction (validates all foreign keys)
- Example: Created from entity vectors, passed to all subsequent layers

**AbstractConstraint:**
- Purpose: Extensible base type for constraint plugins
- Location: `src/constraints/constraint_types.jl`
- Pattern: All constraints implement `build!(model, system, constraint)` method
- Examples: `ThermalCommitmentConstraint`, `HydroWaterBalanceConstraint`, `SubmarketBalanceConstraint`
- Allows: Custom constraints to be plugged in without modifying core system

**AbstractObjective:**
- Purpose: Extensible base type for objective functions
- Location: `src/objective/objective_types.jl`
- Pattern: All objectives implement `build!(model, system, objective)` method
- Examples: `ProductionCostObjective`
- Allows: Multiple objective functions can be added sequentially

**SolverResult:**
- Purpose: Encapsulates complete optimization solution
- Location: `src/solvers/solver_types.jl`
- Contains: Objective value, termination status, solver time, solution variables, dual values
- Enables: Unified solution extraction interface across all solvers

## Entry Points

**Primary Entry: Model Building Workflow**
- Location: Applications use functions from `src/OpenDESSEM.jl` module
- Typical sequence:
  1. `load_dessem_case()` or `load_from_database()` → entities
  2. `ElectricitySystem()` → system container
  3. `JuMP.Model()` → optimization model
  4. `create_all_variables!()` → decision variables
  5. `build!()` → constraints (multiple calls)
  6. `build!()` → objective
  7. `optimize!()` → solver

**Data Loading Entry Points:**
- `load_dessem_case()`: Load from ONS DESSEM directory structure (`src/data/loaders/dessem_loader.jl`)
- `load_from_database()`: Load from PostgreSQL database (`src/data/loaders/database_loader.jl`)
- Direct: Construct entities manually and pass to `ElectricitySystem()`

**Integration Entry Points:**
- `convert_to_powermodel()`: Convert complete system to PowerModels format (`src/integration/powermodels_adapter.jl`)
- Individual converters: `convert_bus_to_powermodel()`, `convert_line_to_powermodel()`, etc.

## Error Handling

**Strategy:** Validate early, fail fast with descriptive messages

**Patterns:**

**Entity Construction Validation:**
```julia
# In src/entities/*.jl, fields have inner constructor checks
struct ConventionalThermal <: ThermalPlant
    # Constructor validates: capacity_mw > 0, min_gen <= max_gen
    function ConventionalThermal(...; capacity_mw, min_generation_mw, max_generation_mw, ...)
        @assert capacity_mw > 0 "Capacity must be positive"
        @assert min_generation_mw <= max_generation_mw "Min must be <= max"
        new(...)
    end
end
```

**System Validation:**
```julia
# In src/core/electricity_system.jl ElectricitySystem constructor
# Validates all foreign key references exist:
# - thermal plant bus_id must exist in buses
# - all ACLine endpoints must exist
# Throws ArgumentError if validation fails
```

**Data Loading Validation:**
```julia
# In src/data/loaders/, loaders validate:
# - No duplicate entity IDs
# - No negative capacities/costs
# - All required fields present
# Throws exception on invalid data
```

**Constraint Building Validation:**
```julia
# In src/constraints/constraint_types.jl
# Constraint metadata provides debugging context
# build!() returns ConstraintBuildResult with:
# - success::Bool
# - message::String with details
# - warnings::Vector{String} for non-fatal issues
```

## Cross-Cutting Concerns

**Logging:**
- Uses Julia's default `@info`, `@warn`, `@debug` macros
- No centralized logging framework (could be added later)
- Key log points: Data loading progress, constraint building status, solve completion

**Validation:**
- `src/entities/validation.jl` provides reusable validators:
  - `validate_positive()`, `validate_non_negative()`, `validate_strictly_positive()`
  - `validate_percentage()`, `validate_in_range()`
  - `validate_unique_ids()`
- All entities use these validators via inner constructors

**Metadata Tracking:**
- `EntityMetadata` struct in `src/entities/base.jl` provides:
  - Timestamps (created_at, updated_at)
  - Version tracking
  - Tags for custom categorization
  - Properties dict for extensible metadata

**Time Indexing:**
- Constraints use 1-indexed time periods (Julia convention)
- Time periods passed as `UnitRange{Int}` or `Vector{Int}`
- JuMP variables indexed as `variable[entity_index, time_period]`

---

*Architecture analysis: 2025-02-15*
