# OpenDESSEM: Detailed Technical Implementation Plan

## Executive Summary

This document provides a detailed technical implementation plan for OpenDESSEM, focusing on:
1. **Database-ready entity structures** for persistent storage and flexible data loading
2. **Modular, extensible architecture** for dynamic constraint/variable/objective building
3. **Clean separation of concerns** between data, model, and solver layers

**Key Principle**: The system should be able to load data from either a structured database or native DESSEM input files, with the core optimization model building itself dynamically based on the entities present in the loaded data.

---

## Part 1: Entity-Driven Architecture

### 1.1 Core Design Philosophy

The architecture follows an **entity-component pattern** where:
- Each physical element (thermal plant, hydro plant, bus, line) is an **entity**
- Entities contain **static parameters** (capacity, limits) and **time-series data** (inflows, demand)
- The optimization model **discovers** entities and builds appropriate constraints/variables
- **No hardcoded assumptions** about which entities exist - fully configurable

### 1.2 Entity Type System Hierarchy

```
AbstractEntity
├── PhysicalEntity
│   ├── GenerationEntity
│   │   ├── ThermalPlant
│   │   │   ├── ConventionalThermal
│   │   │   ├── CombinedCyclePlant
│   │   │   └── NuclearPlant
│   │   ├── HydroPlant
│   │   │   ├── RunOfRiver
│   │   │   ├── ReservoirHydro
│   │   │   └── PumpedStorage
│   │   ├── RenewablePlant
│   │   │   ├── WindFarm
│   │   │   ├── SolarFarm
│   │   │   └── HybridRenewable
│   │   └── IntermittentGenerator
│   ├── NetworkEntity
│   │   ├── Bus
│   │   ├── ACLine
│   │   ├── Transformer
│   │   ├── DCLine
│   │   └── ShuntElement
│   └── StorageEntity
│       ├── Battery
│       └── PumpedHydroStorage
├── MarketEntity
│   ├── Submarket
│   ├── LoadZone
│   └── TradingHub
└── ContractEntity
    ├── BilateralContract
    └── FuturesContract
```

---

## Part 2: Complete Project Directory Structure

```
openDESSEM/
├── Project.toml                      # Julia package manifest
├── README.md                         # Quick start guide
├── LICENSE                           # MIT/Apache 2.0
│
├── src/
│   ├── OpenDESSEM.jl                 # Main module
│   │
│   ├── core/
│   │   ├── model.jl                  # DessemModel struct
│   │   ├── variables.jl              # Variable creation
│   │   ├── objective.jl              # Objective function
│   │   └── solution.jl               # Solution extraction
│   │
│   ├── entities/
│   │   ├── base.jl                   # AbstractEntity, EntityMetadata
│   │   ├── thermal.jl                # ThermalPlant types
│   │   ├── hydro.jl                  # HydroPlant types
│   │   ├── renewable.jl              # WindFarm, SolarFarm
│   │   ├── network.jl                # Bus, ACLine, Transformer, DCLine
│   │   └── market.jl                 # Submarket, Load
│   │
│   ├── constraints/
│   │   ├── base.jl                   # AbstractConstraint
│   │   ├── energy_balance.jl         # EnergyBalanceConstraint
│   │   ├── thermal_uc.jl             # ThermalUnitCommitmentConstraint
│   │   ├── hydro_water_balance.jl    # HydroWaterBalanceConstraint
│   │   ├── network_powermodels.jl    # PowerModels-based network constraints
│   │   ├── brazilian_extensions.jl   # ONS-specific constraints
│   │   ├── reserve.jl                # SpinningReserveConstraint
│   │   └── ramp_rate.jl              # RampRateConstraint
│   │
│   ├── adapters/
│   │   ├── powermodels_adapter.jl    # Entity → PowerModels conversion
│   │   └── pwf_adapter.jl            # PWF.jl data integration
│   │
│   ├── data/
│   │   ├── system.jl                 # ElectricitySystem struct
│   │   ├── loaders/
│   │   │   ├── base.jl               # AbstractDataLoader
│   │   │   ├── database.jl           # DatabaseLoader (PostgreSQL)
│   │   │   ├── sqlite.jl             # SQLiteLoader (development)
│   │   │   └── dessem_files.jl       # DessemFileLoader
│   │   ├── time_series.jl            # TimeSeriesData struct
│   │   └── validators.jl             # Data validation
│   │
│   ├── solvers/
│   │   ├── setup.jl                  # Solver configuration
│   │   ├── highs.jl                  # HiGHS wrapper
│   │   ├── gurobi.jl                 # Gurobi wrapper
│   │   └── utils.jl                  # Presolve, warm-start
│   │
│   ├── analysis/
│   │   ├── results.jl                # Result extraction
│   │   ├── validation.jl             # Constraint verification
│   │   ├── marginal_costs.jl         # PLD calculation
│   │   └── visualization.jl          # Plots, reports
│   │
│   └── utils/
│       ├── time_series.jl            # Time discretization
│       ├── logging.jl                # Debugging
│       ├── performance.jl            # Benchmarking
│       └── config.jl                 # Configuration file parsing
│
├── database/
│   ├── schema/
│   │   ├── 01_create_tables.sql      # DDL
│   │   ├── 02_create_indexes.sql     # Performance
│   │   └── 03_seed_data.sql          # Test data
│   │
│   ├── migrations/                   # Schema versioning
│   │   └── v001_initial_schema.sql
│   │
│   └── scripts/
│       ├── import_dessem_data.jl     # Convert DESSEM files → DB
│       ├── export_to_dessem.jl       # Export DB → DESSEM format
│       └── validate_schema.jl        # Schema consistency checks
│
├── test/
│   ├── unit/
│   │   ├── test_entities.jl
│   │   ├── test_constraints.jl
│   │   └── test_variables.jl
│   │
│   ├── integration/
│   │   ├── test_simple_system.jl
│   │   ├── test_brazilian_system.jl
│   │   └── test_database_loader.jl
│   │
│   ├── validation/
│   │   └── test_against_official.jl  # Compare with official DESSEM
│   │
│   └── fixtures/
│       ├── simple_3plant.yaml        # Test case data
│       ├── reduced_sin.yaml
│       └── full_sin_config.yaml
│
├── examples/
│   ├── 01_quick_start.jl             # Minimal working example
│   ├── 02_database_workflow.jl       # Load from DB
│   ├── 03_dessem_files_workflow.jl   # Load from DESSEM files
│   ├── 04_custom_constraints.jl      # Add user constraints
│   └── 05_sensitivity_analysis.jl
│
├── docs/
│   ├── guide.md                      # User guide
│   ├── architecture.md               # System architecture
│   ├── entity_reference.md           # All entity types
│   ├── constraint_reference.md       # Constraint catalog
│   ├── api_reference.md              # Function docs
│   ├── database_schema.md            # DB docs
│   └── examples.md                   # Usage examples
│
├── config/
│   ├── default_config.yaml           # Default settings
│   ├── solver_config.yaml            # Solver parameters
│   └── logging_config.yaml
│
└── .github/
    └── workflows/
        ├── ci.yml                     # Continuous integration
        └── benchmark.yml              # Performance tracking
```

---

## Part 3: Entity Data Structures (Database-Ready)

### 3.1 Abstract Base Entity

```julia
"""
    AbstractEntity

Base type for all entities in the system.
All entities must implement:
- `id`: Unique identifier
- `name`: Human-readable name
- `metadata`: Dict for additional properties
"""
abstract type AbstractEntity end

Base.@kwdef struct EntityMetadata
    created_at::DateTime = now()
    updated_at::DateTime = now()
    version::Int = 1
    source::String = "unknown"  # "database", "dessem_file", "manual"
    tags::Vector{String} = String[]
    properties::Dict{String, Any} = Dict{String, Any}()
end
```

### 3.2 Core System Container

```julia
"""
    ElectricitySystem

Container for all system entities and data.
"""
Base.@kwdef struct ElectricitySystem
    # Generation entities
    thermal_plants::Vector{ThermalPlant} = ThermalPlant[]
    hydro_plants::Vector{HydroPlant} = HydroPlant[]
    wind_farms::Vector{WindFarm} = WindFarm[]
    solar_farms::Vector{SolarFarm} = SolarFarm[]

    # Network entities
    buses::Vector{Bus} = Bus[]
    ac_lines::Vector{ACLine} = ACLine[]
    dc_lines::Vector{DCLine} = DCLine[]
    transformers::Vector{Transformer} = Transformer[]

    # Market entities
    submarkets::Vector{Submarket} = Submarket[]
    loads::Vector{Load} = Load[]

    # Metadata
    base_date::Date
    description::String = ""
    version::String = "1.0"
end
```

---

## Part 4: Database Schema (PostgreSQL)

```sql
-- =====================================================
-- CORE ENTITY TABLES
-- =====================================================

CREATE TABLE thermal_plants (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    metadata JSONB DEFAULT '{}',
    bus_id VARCHAR(50),
    submarket_id VARCHAR(4),

    -- Static parameters
    fuel_type VARCHAR(50) NOT NULL,
    capacity_mw FLOAT NOT NULL,
    min_generation_mw FLOAT NOT NULL,
    max_generation_mw FLOAT NOT NULL,

    -- Operational
    ramp_up_mw_per_min FLOAT,
    ramp_down_mw_per_min FLOAT,
    min_up_time_hours INTEGER,
    min_down_time_hours INTEGER,

    -- Costs
    fuel_cost_rsj_per_mwh FLOAT,
    startup_cost_rs FLOAT,
    shutdown_cost_rs FLOAT,
    no_load_cost_rs_per_hour FLOAT DEFAULT 0,

    -- Flags
    must_run BOOLEAN DEFAULT FALSE,
    is_flexible BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_thermal_bus ON thermal_plants(bus_id);
CREATE INDEX idx_thermal_submarket ON thermal_plants(submarket_id);

-- Hydro plants
CREATE TABLE hydro_plants (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    metadata JSONB DEFAULT '{}',
    plant_type VARCHAR(50) NOT NULL,
    bus_id VARCHAR(50),
    submarket_id VARCHAR(4),
    river_basin VARCHAR(100),

    max_volume_hm3 FLOAT,
    min_volume_hm3 FLOAT,
    initial_volume_hm3 FLOAT,
    installed_capacity_mw FLOAT,
    max_turbine_outflow_m3s FLOAT,
    min_outflow_m3s FLOAT,

    downstream_plant_id VARCHAR(50),
    water_travel_time_hours FLOAT,

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_hydro_cascade ON hydro_plants(downstream_plant_id);

-- Network buses
CREATE TABLE buses (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    metadata JSONB DEFAULT '{}',
    submarket_id VARCHAR(4),
    voltage_level_kv FLOAT NOT NULL,
    base_kv FLOAT NOT NULL,
    coordinates FLOAT[],
    is_slack_bus BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Transmission lines
CREATE TABLE ac_lines (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    metadata JSONB DEFAULT '{}',
    from_bus_id VARCHAR(50) REFERENCES buses(id),
    to_bus_id VARCHAR(50) REFERENCES buses(id),
    resistance_pu FLOAT NOT NULL,
    reactance_pu FLOAT NOT NULL,
    thermal_capacity_mw FLOAT NOT NULL,
    is_in_service BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_lines_from ON ac_lines(from_bus_id);
CREATE INDEX idx_lines_to ON ac_lines(to_bus_id);

-- Submarkets
CREATE TABLE submarkets (
    id VARCHAR(4) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    pld_floor_rs_per_mwh FLOAT,
    pld_ceiling_rs_per_mwh FLOAT
);

-- Time series data (separate table for efficiency)
CREATE TABLE time_series (
    id SERIAL PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,
    entity_id VARCHAR(50) NOT NULL,
    parameter_name VARCHAR(100) NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    value FLOAT NOT NULL,
    scenario_id VARCHAR(50) DEFAULT 'deterministic',
    unit VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_ts_lookup ON time_series(entity_type, entity_id, parameter_name, timestamp);
```

---

## Part 5: Modular Constraint Architecture

### 5.1 Base Constraint Interface

```julia
abstract type AbstractConstraint end

Base.@kwdef struct ConstraintMetadata
    name::String
    description::String
    is_enabled::Bool = true
    priority::Int = 0
end

function build!(model::DessemModel, constraint::AbstractConstraint)
    error("build! not implemented for $(typeof(constraint))")
end
```

### 5.2 Energy Balance Constraint

```julia
Base.@kwdef struct EnergyBalanceConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    submarkets::Vector{String} = String[]
end

function build!(model::DessemModel, c::EnergyBalanceConstraint)
    for sm_id in c.submarkets
        for t in 1:model.time_periods
            supply = sum(model.variables.gen[id, t]
                        for id in get_plants_in_submarket(model, sm_id))
            demand = model.data.demand[sm_id, t]
            @constraint(model.jump_model, supply == demand)
        end
    end
end
```

### 5.3 Thermal Unit Commitment

```julia
Base.@kwdef struct ThermalUCConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    include_ramp_rates::Bool = true
    include_min_up_down::Bool = true
end

function build!(model::DessemModel, c::ThermalUCConstraint)
    for plant in model.system.thermal_plants
        for t in 1:model.time_periods
            u = model.vars.u[plant.id, t]
            g = model.vars.g[plant.id, t]

            # Capacity limits
            @constraint(model.jump_model,
                plant.min_gen * u <= g <= plant.max_gen * u
            )

            # Ramp rates (if enabled)
            if c.include_ramp_rates && t > 1
                g_prev = model.vars.g[plant.id, t-1]
                @constraint(model.jump_model,
                    g - g_prev <= plant.ramp_up * 60
                )
            end

            # Min up/down time (if enabled)
            if c.include_min_up_down
                # ... constraint implementation
            end
        end
    end
end
```

---

## Part 6: Implementation Priority

### Week 1-2: Foundation
1. Entity structs (all types)
2. Database schema SQL
3. Basic DessemModel container
4. Variable manager

### Week 3-4: Core Constraints
1. Energy balance
2. Thermal UC (basic)
3. Hydro water balance
4. Solve 3-plant test case

### Week 5-6: Network
1. DC-OPF constraints
2. Network variables
3. Bus/line entities
4. Test with IEEE systems

### Week 7-8: Integration
1. Objective composer
2. Database loader
3. DESSEM file parser (using **PWF.jl** for .pwf file parsing - **NOW INTEGRATED**)
4. Solution extraction

**Note on PWF.jl**: **PWF.jl v0.1.0 is now integrated** for parsing .pwf (Power World Format) files. This library handles network topology and power flow data from Brazilian ANAREDE format. The adapter layer (`src/adapters/pwf_adapter.jl`) converts PWF data to OpenDESSEM entities. See `docs/PWF_INTEGRATION.md` for details.

### Week 9-12: Advanced
1. Combined-cycle modes
2. Renewable integration
3. AC-OPF (optional)
4. Documentation

---