# OpenDESSEM Development Task List

**Last Updated**: 2026-01-05
**Status**: Active
**Current Phase**: Entity System Expansion → Constraint Development (PowerModels.jl Integration)

**Recent Updates**:
- ✅ TASK-001, TASK-002, TASK-003, TASK-003.5, TASK-004, TASK-004.5 completed (All entity types + PowerModels adapter + ElectricitySystem)
- ✅ PWF.jl added for Brazilian .pwf file parsing
- ✅ PowerModels.jl adopted for network constraints (TASK-006 updated)
- ✅ PowerModels.jl adapter layer implemented (see docs/POWERMODELS_ADAPTER.md)
- 📧 Comprehensive compatibility analysis completed (see docs/POWERMODELS_COMPATIBILITY_ANALYSIS.md)
- 🎉 **DISCOVERED**: DESSEM2Julia - complete DESSEM parser (32/32 files, 7,680+ tests)
- 📝 **UPDATED TASK**: TASK-010 now uses DESSEM2Julia (complexity 7/10 → 3/10)
- 🔗 **COMPLETE DEPENDENCY MAPPING**: All task dependencies documented with updated execution order
- 📊 **COMPLEXITY UPDATED**: Total complexity 84/140 across 13 tasks (down from original estimates)
- 🎯 **PHASE 1 & 2 COMPLETE**: All entity types implemented, ready for optimization layer

This document outlines the remaining development tasks for the OpenDESSEM project, organized by logical dependency order and complexity.

---

## Legend

- **ID**: Unique task identifier
- **Complexity**: 0-10 scale (0 = trivial, 10 = extremely complex)
- **Precedence**: Task IDs that must be completed first
- **Status**: 🟡 Planned | 🔵 In Progress | 🟢 Completed | 🔴 Blocked

---

## Phase 2: Complete Entity System

### TASK-001: Hydroelectric Plant Entities

**Status**: 🟢 Completed (2026-01-04)
**Complexity**: 7/10
**Precedence**: None (builds on existing entity system)

**Description**:
Implement comprehensive hydroelectric plant entity types for Brazilian power system modeling. This includes three distinct plant types with different operational characteristics:

1. **Reservoir Hydro Plants** (Usinas a Fio D'água com Reservatório)
   - Large storage capacity
   - Multi-year regulation capability
   - Water storage tracking (hm³)
   - Minimum and maximum operational limits
   - Evaporation losses
   - Water inflow forecasting

2. **Run-of-River Plants** (Usinas a Fio D'água)
   - Limited or no storage capacity
   - Must use water as it arrives (constraint: outflow = inflow)
   - Minimum ecological flow requirements
   - Dependent on upstream cascade

3. **Pumped Storage Plants** (Usinas Reversíveis)
   - Can pump water upstream during low-cost periods
   - Generate during high-cost periods
   - Upper and lower reservoir tracking
   - Pumping efficiency curves
   - Generation mode vs pumping mode

**Required Fields**:
- `id::String` - Unique plant identifier (e.g., "H_ITAIPU_001")
- `name::String` - Human-readable plant name
- `bus_id::String` - Electrical network connection point
- `submarket_id::String` - Submarket (SE/CO, S, NE, N)
- `plant_type::HydroPlantType` - Enum: RESERVOIR, RUN_OF_RIVER, PUMPED_STORAGE
- `installed_capacity_mw::Float64` - Maximum generation capacity
- `min_generation_mw::Float64` - Minimum stable generation
- `max_generation_mw::Float64` - Maximum generation (may be < installed)
- `min_flow_m3_per_s::Float64` - Minimum water flow
- `max_flow_m3_per_s::Float64` - Maximum water flow
- `storage_capacity_hm3::Float64` - Maximum reservoir storage (for reservoir/pumped)
- `initial_storage_hm3::Float64` - Initial water volume
- `final_storage_constraint_hm3::Float64` - Required final storage
- `min_storage_hm3::Float64` - Minimum operational storage
- `max_storage_hm3::Float64` - Maximum operational storage
- `inflow_forecast_m3_per_s::Vector{Float64}` - Expected inflows by time period
- `evaporation_loss_mm_per_day::Float64` - Daily evaporation (reservoir only)
- `upstream_plant_ids::Vector{String}` - IDs of immediate upstream plants
- `downstream_plant_ids::Vector{String}` - IDs of immediate downstream plants
- `water_travel_time_hours::Float64` - Time to reach downstream (cascade delay)
- `pump_capacity_mw::Float64` - Maximum pumping capacity (pumped storage only)
- `pump_efficiency::Float64` - Energy efficiency for pumping (0-1)
- `must_run::Bool` - If true, must generate when water available

**Validation Requirements**:
- Storage capacity must be positive for reservoir/pumped plants
- Initial storage must be within min/max bounds
- Pump capacity only applicable for pumped storage
- Upstream/downstream references must be valid plant IDs
- Minimum flow ≤ maximum flow
- Water travel time ≥ 0
- Pump efficiency between 0 and 1

**Test Cases**:
- Create reservoir plant with valid parameters
- Create run-of-river plant with zero storage
- Create pumped storage plant with pumping capacity
- Validate storage constraints (initial within bounds)
- Validate cascade relationships (upstream/downstream)
- Test invalid configurations (negative capacity, min > max, etc.)
- Test water balance calculations

**Files to Create**:
- `src/entities/hydro.jl` - Hydro entity definitions
- `test/unit/test_hydro_entities.jl` - Comprehensive tests

**Perfect Prompt for Coding Agent**:
```
Implement the hydroelectric plant entity system for OpenDESSEM following the project's TDD principles and existing entity patterns.

Context:
- The project already has a working entity system with base types (PhysicalEntity, EntityMetadata)
- Thermal plant entities exist in src/entities/thermal.jl as reference
- Validation utilities are available in src/entities/validation.jl
- We need three hydro plant types: RESERVOIR, RUN_OF_RIVER, and PUMPED_STORAGE

Requirements:
1. Create HydroPlantType enum with three values: RESERVOIR, RUN_OF_RIVER, PUMPED_STORAGE
2. Create HydroelectricPlant abstract type <: PhysicalEntity
3. Create three concrete structs: ReservoirHydro, RunOfRiverHydro, PumpedStorageHydro
4. All structs should use Base.@kwdef with inner constructors for validation
5. Use validation functions from src/entities/validation.jl (validate_id, validate_positive, etc.)
6. Include all fields specified in the detailed requirements
7. Add comprehensive docstrings with examples for each entity type
8. Follow the JuliaFormatter spacing convention (spaces around = in keyword arguments)

Testing:
- Write test file test/unit/test_hydro_entities.jl BEFORE implementing entities
- Include tests for all three plant types
- Test valid configurations and invalid inputs (negative values, min > max, etc.)
- Test cascade relationship validation
- Ensure all 453 existing tests still pass
- Target: >90% code coverage for new code

Expected Output:
- src/entities/hydro.jl with all three entity types (approximately 300-400 lines)
- test/unit/test_hydro_entities.jl with comprehensive tests (approximately 400-500 lines)
- All tests passing (453+ new tests)
- Code formatted with JuliaFormatter
```

---

### TASK-002: Renewable Energy Plant Entities

**Status**: 🟢 Completed (2026-01-04)
**Complexity**: 5/10
**Precedence**: None (can be done in parallel with TASK-001)

**Completion Notes**:
- Implemented WindPlant and SolarPlant entities with time-varying capacity forecasts
- Added RenewableType enum (WIND, SOLAR) and ForecastType enum (DETERMINISTIC, STOCHASTIC, SCENARIO_BASED)
- Both plant types support capacity_forecast_mw::Vector{Float64} for intermittent generation
- Implemented curtailment logic with is_dispatchable flag
- Ramp rate constraints for both plant types
- Comprehensive validation including forecast dimension checking
- Full test coverage with 100+ tests for both plant types
- Fixed network.jl string interpolation issue with R$ currency symbols

**Description**:
Implement renewable energy plant entities for wind and solar generation, which have different characteristics from thermal and hydro plants:

1. **Wind Power Plants**
   - Intermittent generation based on wind forecasts
   - Zero marginal cost (fuel is free)
   - Capacity varies by time period (based on wind speed forecasts)
   - Ramping constraints (wind changes gradually)
   - Curtailment possible (can reduce generation if needed)

2. **Solar Power Plants**
   - Intermittent based on solar irradiance
   - Zero marginal cost
   - Generation only during daylight hours
   - Capacity factor varies by time of day and weather
   - No storage (unless battery hybrid system)
   - Very fast ramping capabilities

**Required Fields**:
- `id::String` - Unique plant identifier
- `name::String` - Human-readable name
- `bus_id::String` - Network connection point
- `submarket_id::String` - Submarket location
- `plant_type::RenewableType` - Enum: WIND, SOLAR
- `installed_capacity_mw::Float64` - Nameplate capacity
- `capacity_forecast_mw::Vector{Float64}` - Available capacity by time period
- `forcast_type::ForecastType` - Enum: DETERMINISTIC, STOCHASTIC, SCENARIO_BASED
- `min_generation_mw::Float64` - Minimum generation (usually 0)
- `max_generation_mw::Float64` - Maximum (capped by forecast)
- `ramp_up_mw_per_min::Float64` - Max increase rate
- `ramp_down_mw_per_min::Float64` - Max decrease rate
- `curtailment_allowed::Bool` - Can generation be reduced below forecast?
- `forced_outage_rate::Float64` - Probability of unavailability
- `is_dispatchable::Bool` - Can be controlled (false for pure pass-through)

**Validation Requirements**:
- Capacity forecast length must match optimization horizon
- Capacity forecast values ≤ installed capacity
- Min generation ≤ max generation
- Forced outage rate between 0 and 1
- Curtailment allowed only if is_dispatchable = true

**Test Cases**:
- Create wind plant with time-varying capacity forecast
- Create solar plant with zero night capacity
- Test curtailment logic (generation ≤ forecast)
- Validate forecast dimensions
- Test ramp rate constraints
- Test forced outage scenarios

**Perfect Prompt for Coding Agent**:
```
Implement renewable energy plant entities (wind and solar) for OpenDESSEM following TDD principles.

Context:
- Existing entity system in src/entities/ with validation utilities
- Thermal and hydro plants already implemented
- Renewable plants have intermittent generation based on forecasts
- Zero marginal cost but capacity varies by time period

Requirements:
1. Create RenewableType enum: WIND, SOLAR
2. Create ForecastType enum: DETERMINISTIC, STOCHASTIC, SCENARIO_BASED
3. Create WindPlant and SolarPlant structs <: PhysicalEntity
4. Include capacity_forecast_mw::Vector{Float64} field for time-varying availability
5. Add curtailment logic (can reduce generation below forecast if needed)
6. Validate forecast dimensions match optimization horizon
7. Comprehensive docstrings explaining intermittent characteristics

Testing:
- Create test/unit/test_renewable_entities.jl
- Test wind plant with time-varying forecasts
- Test solar plant with day/night pattern
- Test curtailment constraints
- Test ramp rate limits
- Ensure all existing tests pass
- Target >90% coverage

Expected Output:
- src/entities/renewable.jl with WindPlant and SolarPlant entities
- test/unit/test_renewable_entities.jl with comprehensive tests
- All tests passing
- Code formatted with JuliaFormatter
```

---

### TASK-003: Electrical Network Entity Types

**Status**: 🟢 Completed (2026-01-04)
**Complexity**: 8/10
**Precedence**: None (can be done in parallel with TASK-001 and TASK-002)

**Description**:
Implement electrical network entities to model the transmission system and load distribution. This is critical for representing power flows and network constraints.

**Entity Types**:

1. **Electrical Bus**
   - Network node where generation/load connect
   - Voltage level (kV)
   - Submarket location
   - Connected loads, generators, transmission lines
   - Angle and voltage magnitude variables (for AC-OPF)
   - Power balance constraints

2. **Transmission Line**
   - Connection between two buses
   - Thermal capacity limit (MW)
   - Electrical characteristics (resistance, reactance, susceptance)
   - Number of circuits (parallel lines)
   - Voltage level
   - Losses (I²R)
   - Contingency status (can be out for maintenance)

3. **Load (Carga)**
   - Power demand by bus and time period
   - Load profile (daily pattern)
   - Price elasticity (optional)
   - Interruptible load flag
   - Priority level (firm vs. curtailable)

4. **Submarket (Submercado)**
   - Geographic region (SE/CO, S, NE, N)
   - Aggregated demand
   - Interconnection capacity limits
   - Local marginal price (PLD) calculation
   - Import/export constraints

**Required Fields (Bus)**:
- `id::String` - Unique bus identifier (e.g., "BUS_SE_230KV_001")
- `name::String` - Bus name
- `voltage_kv::Float64` - Voltage level (e.g., 230.0, 500.0)
- `submarket_id::String` - Submarket location
- `area_id::String` - Control area
- `is_slack_bus::Bool` - Reference bus for power flow
- `min_voltage_pu::Float64` - Minimum voltage (per unit)
- `max_voltage_pu::Float64` - Maximum voltage (per unit)
- `connected_generators::Vector{String}` - IDs of connected plants
- `connected_loads::Vector{String}` - IDs of connected loads
- `connected_lines::Vector{String}` - IDs of connected lines

**Required Fields (TransmissionLine)**:
- `id::String` - Unique line identifier
- `name::String` - Line name
- `from_bus_id::String` - Origin bus
- `to_bus_id::String` - Destination bus
- `voltage_kv::Float64` - Voltage level
- `thermal_capacity_mw::Float64` - Maximum power flow
- `resistance_ohm::Float64` - Line resistance (R)
- `reactance_ohm::Float64` - Line reactance (X)
- `susceptance_siemens::Float64` - Line susceptance (B)
- `num_circuits::Int` - Number of parallel lines
- `length_km::Float64` - Line length
- `is_in_service::Bool` - Operational status
- `contingency_enabled::Bool` - Consider in N-1 contingency?

**Required Fields (Load)**:
- `id::String` - Unique load identifier
- `name::String` - Load name
- `bus_id::String` - Connection bus
- `submarket_id::String` - Submarket location
- `load_profile_mw::Vector{Float64}` - Demand by time period
- `is_firm::Bool` - Firm (must serve) or curtailable
- `is_interruptible::Bool` - Can be interrupted for payment
- `priority::Int` - Service priority (1-10, 1 = highest)
- `price_elasticity::Float64` - Demand response to price changes
- `interruption_cost_rs_per_mwh::Float64` - Cost to curtail

**Required Fields (Submarket)**:
- `id::String` - Submarket ID (SE, S, NE, N)
- `name::String` - Full name
- `interconnection_capacity_mw::Dict{String, Float64}` - Max transfer to/from other submarkets
- `demand_forecast_mw::Vector{Float64}` - Aggregated demand by period
- `reference_bus_id::String` - Slack bus for price calculation

**Test Cases**:
- Create buses with different voltage levels
- Create transmission lines connecting buses
- Validate thermal capacity constraints
- Test network topology (islands detection)
- Create load profiles with daily patterns
- Test submarket interconnection limits
- Validate bus-generator associations

**Perfect Prompt for Coding Agent**:
```
Implement electrical network entity types for OpenDESSEM to model the Brazilian transmission system.

Context:
- Need to model buses, transmission lines, loads, and submarkets
- This is foundational for network constraints and power flow calculations
- Follow existing entity patterns from thermal and hydro plants
- Brazilian system has 4 submarkets (SE/CO, S, NE, N) interconnected by transmission

Requirements:
1. Create entities for: ElectricalBus, TransmissionLine, Load, Submarket
2. Implement topological validation (buses must exist, lines connect valid buses)
3. Add voltage level constraints (min/max per unit)
4. Model thermal capacity limits on transmission lines
5. Support multiple circuits (parallel lines)
6. Include load profiles (time-varying demand)
7. Model interconnection limits between submarkets
8. Comprehensive docstrings with Brazilian system examples

Testing:
- Create test/unit/test_network_entities.jl
- Test bus creation with voltage constraints
- Test transmission line R/X/B parameters
- Test load profiles with daily patterns
- Test submarket interconnections
- Validate network topology (detect invalid references)
- Test islanding detection (disconnected subnetworks)
- Ensure all existing tests pass
- Target >90% coverage

Expected Output:
- src/entities/network.jl with all network entity types
- test/unit/test_network_entities.jl with comprehensive tests
- All tests passing
- Code formatted with JuliaFormatter
```

---

### TASK-003.5: PowerModels.jl Integration Layer

**Status**: 🟢 Completed (2026-01-04)
**Complexity**: 6/10
**Precedence**: TASK-003 (requires network entities)

**Description**:
Create an adapter layer that converts OpenDESSEM entities to PowerModels.jl data format. This is a critical bridge between our type-safe entity system and PowerModels' proven constraint formulations.

**🎯 PURPOSE**: Enable PowerModels.jl network constraints without rewriting formulations

**Key Components**:

1. **Entity → PowerModels Converter**
   - Convert OpenDESSEM entities → PowerModels Dict{String, Any}
   - Map Bus → PowerModels bus data structure
   - Map ACLine → PowerModels branch data structure
   - Map ThermalPlant/HydroPlant/RenewablePlant → PowerModels gen data structure
   - Map Load → PowerModels load data structure
   - Handle ONS-specific fields (4 submarkets, Brazilian conventions)

2. **Bidirectional Mapping**
   - Forward: Entities → PowerModels (for building constraints)
   - Reverse: PowerModels results → Entities (for extracting solution)
   - Preserve entity IDs through conversion

3. **Validation**
   - Verify all entities map successfully
   - Check for missing required fields
   - Validate network topology consistency
   - Handle edge cases (slack bus, isolated buses, etc.)

**Required Functions**:
```julia
convert_to_powermodel(system::ElectricitySystem)::Dict{String, Any}
convert_bus_to_powermodel(bus::Bus)::Dict{String, Any}
convert_line_to_powermodel(line::ACLine)::Dict{String, Any}
convert_gen_to_powermodel(plant::Union{ThermalPlant, HydroPlant, RenewablePlant})::Dict{String, Any}
convert_load_to_powermodel(load::Load)::Dict{String, Any}
find_bus_index(bus_id::String, buses::Vector{Bus})::Int
validate_powermodel_conversion(pm_data::Dict{String, Any})::Bool
```

**PowerModels Data Format** (what we're converting TO):
```julia
Dict{String, Any}(
    "name" => "opendessem_system",
    "baseMVA" => 100.0,
    "bus" => [
        Dict("bus_i" => 1, "vmax" => 1.1, "vmin" => 0.9, "base_kv" => 230.0, ...),
        Dict("bus_i" => 2, "vmax" => 1.1, "vmin" => 0.9, "base_kv" => 230.0, ...),
        ...
    ],
    "branch" => [
        Dict("fbus" => 1, "tbus" => 2, "br_r" => 0.002, "br_x" => 0.028, "rate_a" => 400.0, ...),
        ...
    ],
    "gen" => [
        Dict("gen_bus" => 1, "pmax" => 200.0, "pmin" => 0.0, ...),
        ...
    ],
    "load" => [
        Dict("load_bus" => 2, "pd" => 100.0, "qd" => 0.0, ...),
        ...
    ]
)
```

**Test Cases**:
- Convert simple 3-bus system (see scripts/test_powermodels_api.jl)
- Verify all entity types convert correctly
- Test network topology preservation
- Test with Brazilian 4-submarket system
- Validate against PowerModels.instantiate_model()
- Test reverse conversion (results → entities)

**ONS-Specific Considerations**:
- Map 4 Brazilian submarkets (SE/CO, S, NE, N) to PowerModels "area" field
- Handle multiple generators per bus (common in Brazilian system)
- Preserve DC line representations if using DC-OPF
- Map special ONS constraint types to PowerModels extensions

**Perfect Prompt for Coding Agent**:
```
Implement the PowerModels.jl adapter layer for OpenDESSEM.

Context:
- We have adopted PowerModels.jl for network constraint formulations
- PowerModels uses Dict{String, Any} data format (not entities)
- We need to convert our type-safe entities to PowerModels format
- See docs/POWERMODELS_COMPATIBILITY_ANALYSIS.md for complete specification

Requirements:
1. Create src/adapters/powermodels_adapter.jl
2. Implement convert_to_powermodel(system::ElectricitySystem) main function
3. Convert each entity type to PowerModels format:
   - Bus → Dict("bus_i", "vmax", "vmin", "base_kv", "area", "vm", "va")
   - ACLine → Dict("fbus", "tbus", "br_r", "br_x", "rate_a", "rate_b", "rate_c")
   - ThermalPlant/HydroPlant/RenewablePlant → Dict("gen_bus", "pmax", "pmin", "qmax", "qmin")
   - Load → Dict("load_bus", "pd", "qd", "status")
4. Use find_bus_index() to map bus_id → integer indices
5. Add metadata (name, baseMVA)
6. Validate all conversions with tests
7. Support reverse conversion (PowerModels results → entities)

Testing:
- Create test/unit/test_powermodels_adapter.jl
- Create test/adapters/test_adapter_integration.jl
- Test with 3-bus example from PowerModels.jl docs
- Test with Brazilian 4-submarket system
- Validate conversion produces valid PowerModels data
- Test reverse conversion
- Ensure all 544+ existing tests pass
- Target >90% coverage

Expected Output:
- src/adapters/powermodels_adapter.jl (approximately 300 lines)
- test/unit/test_powermodels_adapter.jl (approximately 400 lines)
- test/adapters/test_adapter_integration.jl (approximately 200 lines)
- All tests passing
- Code formatted with JuliaFormatter

Example Usage:
```julia
using OpenDESSEM
using PowerModels as PM

# Convert entities to PowerModels format
pm_data = convert_to_powermodel(electricity_system)

# Use PowerModels directly
pm = PM.instantiate_model(
    pm_data,
    PM.DCPPowerModel,
    PM.build_opf,
    jump_model=Model(HiGHS.Optimizer)
)

# Solve
result = PM.optimize_model!(pm, optimizer=HiGHS.Optimizer)
```
```

**Files to Create**:
- `src/adapters/powermodels_adapter.jl` - Adapter implementation
- `test/unit/test_powermodels_adapter.jl` - Unit tests
- `test/adapters/test_adapter_integration.jl` - Integration tests

**Dependencies**:
- **Blocks**: TASK-006 (Constraint Builder) - needs adapter first
- **Enables**: TASK-006 can use PowerModels once adapter exists

---

### TASK-004: Market Entity Types

**Status**: � Completed (2026-01-04)
**Complexity**: 4/10
**Precedence**: TASK-003 (depends on network entities)

**Completion Notes**:
- Implemented BilateralContract entity with seller/buyer relationships
- Added contract price, energy amount, and date validation
- Comprehensive test coverage in test/unit/test_market_entities.jl
- Submarket and Load entities were already implemented

**Description**:
Implement market-related entities for modeling energy trading, contracts, and market mechanisms in the Brazilian electricity market.

**Entity Types**:

1. **Bilateral Contract**
   - Generator sells to consumer/distributor at fixed price
   - Contract amount (MW) by time period
   - Contract price (R$/MWh)
   - Start/end dates
   - Flexibility options

2. **Energy Auction**
   - Quantity auctioned
   - Winning price
   - Contract duration
   - Product type (existing, new energy)

**Required Fields**:
- `id::String` - Unique contract identifier
- `seller_id::String` - Generator ID
- `buyer_id::String` - Buyer/distributor ID
- `contract_amount_mw::Float64` - Contracted quantity
- `price_rs_per_mwh::Float64` - Contract price
- `start_date::Date` - Contract start
- `end_date::Date` - Contract end
- `is_flexible::Bool` - Can quantity be adjusted?

**Perfect Prompt for Coding Agent**:
```
Implement market entity types for energy contracts in the Brazilian electricity market.

Requirements:
1. Create BilateralContract entity with seller/buyer relationships
2. Include contract amount, price, duration, and flexibility options
3. Validate seller/buyer references exist in other entities
4. Add comprehensive docstrings with market examples
5. Follow existing entity patterns

Testing:
- Create test/unit/test_market_entities.jl
- Test contract creation and validation
- Test date constraints (end date ≥ start date)
- Test seller/buyer reference validation
- Ensure all existing tests pass

Expected Output:
- src/entities/market.jl with market entities
- test/unit/test_market_entities.jl with tests
- All tests passing
```

---

### TASK-004.5: ElectricitySystem Container

**Status**: ✅ Completed (2025-01-04)
**Complexity**: 5/10
**Precedence**: TASK-001, TASK-002, TASK-003, TASK-004 (requires all entity types)

**Description**:
Create a unified container struct that holds all entities for a complete electrical system. This is the central data structure that the optimization model operates on.

**🎯 PURPOSE**: Single source of truth for all system entities

**Implementation Summary**:
- ✅ Created `src/core/electricity_system.jl` with full ElectricitySystem struct
- ✅ Implemented comprehensive validation (duplicate IDs, foreign key references)
- ✅ Added helper functions: `get_thermal_plant`, `get_hydro_plant`, `get_bus`, `get_submarket`, `count_generators`, `total_capacity`, `validate_system`
- ✅ Wrote comprehensive test suite (`test/unit/test_electricity_system.jl`) with 20+ test cases
- ✅ Updated main OpenDESSEM module to export ElectricitySystem and helpers
- ✅ Note: Transformer and BilateralContract entities omitted as they don't exist yet (graceful handling)

**Files Created/Modified**:
- `src/core/electricity_system.jl` (new)
- `test/unit/test_electricity_system.jl` (new)
- `src/OpenDESSEM.jl` (updated exports)
- `test/runtests.jl` (added new test file)

**Key Components**:

1. **ElectricitySystem Struct**
   - Container for all entity collections
   - Metadata (base date, description, version)
   - Validation methods
   - Query methods (get by type, get by ID, filter by submarket, etc.)

2. **Entity Collections**
   - `thermal_plants::Vector{ThermalPlant}`
   - `hydro_plants::Vector{HydroPlant}`
   - `wind_farms::Vector{WindFarm}`
   - `solar_farms::Vector{SolarFarm}`
   - `buses::Vector{Bus}`
   - `ac_lines::Vector{ACLine}`
   - `dc_lines::Vector{DCLine}`
   - `transformers::Vector{Transformer}`
   - `loads::Vector{Load}`
   - `submarkets::Vector{Submarket}`
   - `contracts::Vector{BilateralContract}`

3. **Query Methods**
   - `get_thermal_plants(system, submarket_id)` - Filter by location
   - `get_hydro_plants_in_cascade(system, plant_id)` - Find cascade
   - `get_buses_by_voltage(system, voltage_kv)` - Filter by voltage level
   - `get_loads_by_submarket(system, submarket_id)` - Aggregate demand
   - `total_capacity(system)` - Sum all generation capacity
   - `get_entity_by_id(system, id, type)` - Find specific entity

4. **Validation**
   - Check all IDs are unique
   - Verify all references exist (bus_id, plant_id, etc.)
   - Validate cascade relationships (no cycles)
   - Check network connectivity (no isolated buses)
   - Verify time series dimensions match

**Required Struct**:
```julia
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
    contracts::Vector{BilateralContract} = BilateralContract[]

    # Metadata
    base_date::Date
    description::String = ""
    version::String = "1.0"
end
```

**Required Functions**:
```julia
# Query methods
get_thermal_plants(system::ElectricitySystem, submarket_id::String)::Vector{ThermalPlant}
get_hydro_plants_in_cascade(system::ElectricitySystem, plant_id::String)::Vector{HydroPlant}
get_buses_by_voltage(system::ElectricitySystem, voltage_kv::Float64)::Vector{Bus}
get_loads_by_submarket(system::ElectricitySystem, submarket_id::String)::Vector{Load}
total_generation_capacity(system::ElectricitySystem)::Float64

# Validation
validate_system(system::ElectricitySystem)::Bool
check_unique_ids(system::ElectricitySystem)::Bool
verify_references(system::ElectricitySystem)::Bool
check_network_connectivity(system::ElectricitySystem)::Bool
validate_cascade_relationships(system::ElectricitySystem)::Bool
```

**Test Cases**:
- Create simple system with 3 thermal plants, 2 buses, 1 line
- Create complex Brazilian 4-submarket system
- Test query methods (filter by submarket, voltage, etc.)
- Test validation (detect duplicate IDs, broken references, network islands)
- Test cascade detection (find all upstream/downstream plants)
- Test total capacity calculations

**Perfect Prompt for Coding Agent**:
```
Implement the ElectricitySystem container for OpenDESSEM.

Context:
- All entity types are implemented (TASK-001, TASK-002, TASK-003, TASK-004)
- Need a unified container to hold all entities
- This container is what the optimization model operates on
- Must support queries and validation

Requirements:
1. Create src/data/electricity_system.jl
2. Define ElectricitySystem struct with all entity collections
3. Include metadata (base_date, description, version)
4. Implement query methods:
   - get_thermal_plants(system, submarket_id)
   - get_hydro_plants_in_cascade(system, plant_id)
   - get_buses_by_voltage(system, voltage_kv)
   - total_generation_capacity(system)
5. Implement validation methods:
   - validate_system() - check all rules
   - check_unique_ids() - no duplicates
   - verify_references() - all IDs exist
   - check_network_connectivity() - no islands
   - validate_cascade_relationships() - no cycles
6. Add comprehensive docstrings
7. Use Base.@kwdef for easy construction

Testing:
- Create test/unit/test_electricity_system.jl
- Create test/data/test_system_queries.jl
- Test simple 3-plant system creation
- Test complex Brazilian system
- Test all query methods
- Test validation (detect errors)
- Test cascade traversal
- Ensure all 544+ existing tests pass
- Target >90% coverage

Expected Output:
- src/data/electricity_system.jl (approximately 400 lines)
- test/unit/test_electricity_system.jl (approximately 300 lines)
- test/data/test_system_queries.jl (approximately 200 lines)
- All tests passing
- Code formatted with JuliaFormatter

Example Usage:
```julia
using OpenDESSEM

# Create system
system = ElectricitySystem(;
    thermal_plants = [plant1, plant2, plant3],
    hydro_plants = [hydro1, hydro2],
    buses = [bus1, bus2, bus3],
    ac_lines = [line1, line2],
    loads = [load1, load2],
    submarkets = [se, s, ne, n],
    base_date = Date("2024-01-15"),
    description = "Test system"
)

# Query
se_thermal = get_thermal_plants(system, "SE")
total_cap = total_generation_capacity(system)

# Validate
if !validate_system(system)
    error("System validation failed")
end
```
```

**Files to Create**:
- `src/data/electricity_system.jl` - Container implementation
- `test/unit/test_electricity_system.jl` - Unit tests
- `test/data/test_system_queries.jl` - Query tests

**Dependencies**:
- **Blocks**: TASK-005 (Variable Manager) - needs ElectricitySystem to iterate over
- **Enables**: TASK-005 can scan entities once ElectricitySystem exists

---

## Phase 3: Integration Layer and Variable Management

### TASK-005: Variable Manager Module

**Status**: 🟡 Planned
**Complexity**: 9/10 (reduced scope - ElectricitySystem simplifies this)
**Precedence**: TASK-004.5 (requires ElectricitySystem container)
**Also Requires**: TASK-001, TASK-002, TASK-003, TASK-004 (all entity types)

**Description**:
Create a dynamic variable management system that automatically creates JuMP optimization variables based on discovered entities in the system. This is the core engine that transforms static entity data into optimization model variables.

**Core Components**:

1. **Variable Creation Engine**
   - Scan ElectricitySystem for all entities
   - Create appropriate variables for each entity type
   - Support binary, integer, and continuous variables
   - Handle time-indexed variables (2D: entity × time)
   - Support scenario-indexed variables (3D: entity × time × scenario)

2. **Variable Registry**
   - Track all created variables
   - Provide access by entity ID and time index
   - Support variable queries (get all generation variables, etc.)
   - Maintain metadata (variable type, bounds, entity reference)

3. **Automatic Variable Types**:
   - Thermal: `u[i,t]` (commitment), `g[i,t]` (generation), `z[i,t]` (startup), `w[i,t]` (shutdown)
   - Hydro: `h[i,t]` (generation), `s[i,t]` (storage), `q[i,t]` (turbine outflow), `v[i,t]` (spill)
   - Renewable: `g[i,t]` (generation), `c[i,t]` (curtailment)
   - Network: `θ[b,t]` (bus angle), `V[b,t]` (voltage magnitude)
   - Load: `shed[l,t]` (load shedding)
   - Submarket: `deficit[s,t]` (energy deficit), `PLD[s,t]` (marginal price)

**Required Functions**:
- `create_variables!(model::DessemModel, system::ElectricitySystem)` - Main entry point
- `create_thermal_variables!()` - Create thermal plant variables
- `create_hydro_variables!()` - Create hydro plant variables
- `create_renewable_variables!()` - Create renewable variables
- `create_network_variables!()` - Create network variables
- `create_market_variables!()` - Create market variables
- `get_variable(model, variable_name, entity_id, time_index)` - Access variable
- `has_variable(model, variable_name, entity_id, time_index)` - Check existence
- `list_variables(model, entity_id)` - Get all variables for an entity

**Variable Metadata**:
- Each variable should track: name, entity_id, variable_type, bounds, time_index, scenario_index
- Support for variable groups (e.g., all thermal generation variables)

**Error Handling**:
- Validate entity exists before creating variables
- Validate time index bounds
- Check for duplicate variable creation
- Provide clear error messages

**Test Cases**:
- Create variables for simple 3-plant thermal system
- Verify variable count matches entity count × time periods
- Test variable retrieval by ID and index
- Test time-indexed variable bounds
- Test binary variable creation (unit commitment)
- Test scenario-indexed variables
- Validate variable registry integrity
- Test error handling (invalid entity IDs, out-of-bounds indices)

**Perfect Prompt for Coding Agent**:
```
Implement the variable management system for OpenDESSEM that dynamically creates JuMP optimization variables.

Context:
- All entity types are implemented (thermal, hydro, renewable, network)
- Need to bridge entities → JuMP model variables
- Model structure: src/model/DessemModel.jl (to be created)
- Variables are time-indexed: variable[entity_id, time_period]

Requirements:
1. Create src/model/variable_manager.jl module
2. Implement create_variables!(model, system) main function
3. Discover all entities in ElectricitySystem
4. Create appropriate variables per entity type:
   - Thermal: u (commitment), g (generation), z (startup), w (shutdown)
   - Hydro: h (generation), s (storage), q (outflow), v (spill)
   - Renewable: g (generation), c (curtailment)
   - Network: θ (angle), V (voltage)
5. Use JuMP.@variable macro for creation
6. Register all variables in a VariableRegistry (Dict-based lookup)
7. Support get_variable(), has_variable(), list_variables() accessors
8. Comprehensive docstrings with variable naming conventions
9. Validate entity existence, time bounds, prevent duplicates

Data Structures:
```julia
mutable struct VariableRegistry
    binary::Dict{Tuple{String, Symbol, Int}, JuMP.VariableRef}  # (entity_id, var_name, time)
    continuous::Dict{Tuple{String, Symbol, Int}, JuMP.VariableRef}
    integer::Dict{Tuple{String, Symbol, Int}, JuMP.VariableRef}
    metadata::Dict{Tuple{String, Symbol, Int}, VariableMetadata}
end

struct VariableMetadata
    entity_id::String
    variable_name::Symbol
    variable_type::Symbol  # :binary, :continuous, :integer
    time_index::Int
    lower_bound::Union{Float64, Nothing}
    upper_bound::Union{Float64, Nothing}
    entity_type::String
end
```

Testing:
- Create test/unit/test_variable_manager.jl
- Create test/model/test_dessem_model.jl
- Test variable creation for each entity type
- Test variable retrieval and queries
- Test time-indexed variable bounds
- Test registry integrity
- Test error handling (invalid entities, duplicate creation)
- Test with simple 3-bus, 3-thermal system
- Ensure all 453+ tests pass
- Target >90% coverage

Expected Output:
- src/model/variable_manager.jl (approximately 500-600 lines)
- src/model/DessemModel.jl - Main model structure (approximately 100 lines)
- test/unit/test_variable_manager.jl (approximately 600-700 lines)
- test/model/test_dessem_model.jl (approximately 200 lines)
- All tests passing
- Code formatted with JuliaFormatter

Example Usage:
```julia
model = DessemModel(system, time_periods=24)
create_variables!(model)

# Access variables
u_ITAIPU_5 = get_variable(model, :u, "H_ITAIPU_001", 5)
g_thermal = list_variables(model, "T_SE_001")
```
```

---

### TASK-006: Constraint Builder System (PowerModels.jl Integration)

**Status**: 🟡 Planned (Updated 2026-01-05)
**Complexity**: 8/10 (reduced from 10/10 thanks to PowerModels.jl + PowerModels Adapter)
**Precedence**: TASK-005 (requires variables), TASK-003.5 (requires PowerModels adapter)
**Also Requires**: TASK-001, TASK-002, TASK-003 (all entities for custom constraints)

**Description**:
Implement a modular, extensible constraint building system that leverages **PowerModels.jl** for network constraints while adding custom ONS-specific constraints. This is where the mathematical optimization model is constructed.

**🎯 NEW DIRECTIVE**: **ADOPT PowerModels.jl for Network Constraints**

Based on comprehensive compatibility analysis (`docs/POWERMODELS_COMPATIBILITY_ANALYSIS.md`), we will use PowerModels.jl for all network constraint formulations. Key findings:

- ✅ PowerModels v0.21.5 installed and tested successfully
- ✅ Proven mathematical formulations (422+ citations, peer-reviewed)
- ✅ Works perfectly with HiGHS solver (tested: 0.01s solve time)
- ✅ 75% compatible out of the box; 25% needs custom Brazilian extensions
- ✅ Reduces implementation time from 8 weeks to 4 weeks
- ✅ Lower risk: community support vs. custom implementation

**Architecture**:
```
OpenDESSEM Entity System → Adapter → PowerModels Network Constraints → Custom ONS Constraints → Solver
```

**Constraint Categories**:

1. **Network Constraints (via PowerModels.jl)** ✅ ADOPTED
   - **DC-OPF**: Linearized power flow (fast, used in DESSEM)
   - **AC-OPF**: Full nonlinear power flow (optional, for validation)
   - **Power flow equations**: flow = (θ_from - θ_to) / X_line
   - **Thermal limits**: -capacity ≤ flow ≤ capacity
   - **Voltage limits**: V_min ≤ V ≤ V_max
   - **Angle reference**: θ_slack = 0

2. **ONS-Specific Extensions (Custom Implementation)**
   - **4-Submarket Energy Balance**: Supply-demand per submarket (SE/CO, NE, S, N)
   - **Interconnection Limits**: Transfer capacity between submarkets
   - **Cascading Hydro**: Water travel time delays between reservoirs
   - **Brazilian UC Rules**: ONS-specific unit commitment logic

3. **Thermal Unit Commitment Constraints** (Custom)
   - Capacity limits: g_min * u ≤ g ≤ g_max * u
   - Ramp limits: g[t] - g[t-1] ≤ ramp_up * 60
   - Minimum up/down time
   - Startup/shutdown logic: u[t] - u[t-1] = z[t] - w[t]

4. **Hydro Constraints** (Custom)
   - Water balance: s[t] = s[t-1] + inflow[t] - outflow[t] - spill[t]
   - Generation function: h[t] = f(outflow[t], head[t])
   - Storage bounds: s_min ≤ s[t] ≤ s_max
   - Final storage requirement: s[T] ≥ s_final
   - **Cascade coupling with delays**: outflow_upstream[t] = inflow_downstream[t + travel_time]

5. **Renewable Constraints** (Custom)
   - Generation ≤ forecast: g ≤ g_forecast
   - Curtailment: g + c = g_forecast

6. **Market Constraints** (Custom)
   - Bilateral contract fulfillment
   - Deficit limits (load shedding)
   - Price calculation (dual variables)

**Implementation Plan**:

**Week 1: PowerModels Integration**
- Study PowerModels API and formulations ✅ (DONE - see analysis doc)
- Design entity → PowerModels adapter interface
- Implement `convert_to_powermodel(system::ElectricitySystem)` adapter
- Test adapter with sample systems
- Document adapter usage patterns

**Week 2-3: Network Constraints**
- Implement `build_network_constraints!()` using PowerModels
- Support DC-OPF formulation (primary)
- Add AC-OPF support (optional, for validation)
- Test with Brazilian sample data
- Document PowerModels integration

**Week 4: ONS Extensions**
- Add 4-submarket energy balance constraints
- Add submarket interchange limits
- Add cascading hydro with water travel times
- Add Brazilian-specific data fields
- Test with full Brazilian system

**Week 5: Integration and Testing**
- Integrate PowerModels constraints with custom ONS constraints
- Comprehensive testing with sample systems
- Validate against official DESSEM results
- Performance testing

**Architecture**:

```julia
abstract type AbstractConstraint end

function build!(model::DessemModel, constraint::AbstractConstraint)
    # To be implemented by each constraint type
end

# Example constraint
struct EnergyBalanceConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    include_losses::Bool
    allow_shedding::Bool
end

function build!(model::DessemModel, constraint::EnergyBalanceConstraint)
    # Add energy balance constraints for each bus/time
    for bus in model.system.buses
        for t in 1:model.time_periods
            # Build constraint: generation = load
            @constraint(model.model,
                sum(generation for generators at bus) ==
                sum(demand for loads at bus)
            )
        end
    end
end
```

**Required Functions**:
- `add_constraint!(model, constraint)` - Register and build constraint
- `build_all_constraints!(model)` - Build all registered constraints
- `validate_constraints(model)` - Check constraint consistency
- `get_constraint(model, constraint_name, indices)` - Retrieve specific constraint

**Constraint Metadata**:
- Name, description, priority (for ordering)
- Required entities
- Constraint type (equality, inequality, range)
- Mathematical formulation reference

**Test Cases**:
- Build energy balance for simple system
- Build thermal UC constraints (capacity, ramp, min up/down)
- Build hydro water balance with single reservoir
- Build hydro cascade with 2 plants
- Build network power flow constraints
- Build renewable generation limits
- Test constraint conflict detection
- Test constraint priority ordering
- Validate constraint mathematical correctness

**Perfect Prompt for Coding Agent**:
```
Implement the constraint builder system for OpenDESSEM with PowerModels.jl integration.

Context:
- Variables are created by VariableManager (TASK-005)
- We have decided to ADOPT PowerModels.jl for network constraints (see docs/POWERMODELS_COMPATIBILITY_ANALYSIS.md)
- PowerModels provides proven DC-OPF/AC-OPF formulations (422+ citations)
- We need to build an adapter layer and add custom ONS-specific constraints
- This reduces implementation time from 8 weeks to 4 weeks and lowers risk

Requirements:
1. Create src/constraints/ directory with modular constraint system
2. Define AbstractConstraint base type with build!(model, constraint) interface
3. **Create src/adapters/powermodels_adapter.jl**:
   - Implement convert_to_powermodel(system::ElectricitySystem)::Dict{String, Any}
   - Convert OpenDESSEM entities → PowerModels data dict format
   - Map buses: Bus → Dict("bus_i", "vmax", "vmin", "base_kv", ...)
   - Map AC lines: ACLine → Dict("fbus", "tbus", "br_r", "br_x", "rate_a", ...)
   - Map generators: ThermalPlant/HydroPlant → Dict("gen_bus", "pmax", "pmin", ...)
   - Map loads: Load → Dict("load_bus", "pd", "qd", ...)
   - Validate all conversions
4. **Create src/constraints/network_powermodels.jl**:
   - Implement build_network_constraints!(model, formulation=:DC)
   - Use PowerModels.instantiate_model() with DCPPowerModel
   - Use PowerModels.build_opf() to add network constraints
   - Support DC-OPF (primary) and AC-OPF (optional) formulations
   - Extract PowerModels variables into OpenDESSEM variable registry
5. **Create custom constraint modules**:
   - energy_balance.jl - Bus-level energy balance
   - thermal_commitment.jl - UC constraints (capacity, ramp, min up/down)
   - hydro_water_balance.jl - Reservoir dynamics, cascade with delays
   - hydro_generation.jl - Generation function (outflow → power)
   - submarket_balance.jl - 4-submarket energy balance (ONS-specific)
   - submarket_interconnection.jl - Interchange limits (ONS-specific)
   - renewable_limits.jl - Generation ≤ forecast
6. Use ConstraintMetadata for documentation and ordering
7. Support constraint enable/disable flags
8. Validate constraint consistency (no conflicting bounds)
9. Comprehensive docstrings with mathematical formulations

PowerModels Integration Example:
```julia
using PowerModels as PM

function build_network_constraints!(model::DessemModel; formulation::Symbol=:DC)
    # Convert entities to PowerModels format
    pm_data = convert_to_powermodel(model.system)

    # Select PowerModels formulation
    pm_formulation = formulation == :DC ? PM.DCPPowerModel : PM.ACPPowerModel

    # Instantiate PowerModels model
    pm = PM.instantiate_model(
        pm_data,
        pm_formulation,
        PM.build_opf,
        jump_model=model.jump_model
    )

    # Variables are now in model.jump_model
    # Constraint references available via pm.model
    @info "Built network constraints using PowerModels.jl" formulation=pm_formulation
end
```

Key Constraint Formulations:

Thermal Unit Commitment:
```julia
# Capacity limit
@constraint(model, g[i,t] ≤ g_max[i] * u[i,t])
@constraint(model, g[i,t] ≥ g_min[i] * u[i,t])

# Ramp rate
@constraint(model, g[i,t] - g[i,t-1] ≤ ramp_up[i] * 60)
@constraint(model, g[i,t-1] - g[i,t] ≤ ramp_down[i] * 60)

# Min up/down time
# (Complex - requires auxiliary variables)
```

Hydro Water Balance:
```julia
# Storage dynamics
@constraint(model, s[i,t] == s[i,t-1] + inflow[i,t] - q[i,t] - v[i,t])

# Cascade coupling
@constraint(model, q_upstream[t] == inflow_downstream[t + delay])
```

Network Power Flow (DC-OPF):
```julia
# Power flow
@constraint(model, flow[l,t] == (θ[bus_from, t] - θ[bus_to, t]) / X[l])

# Thermal limit
@constraint(model, -capacity[l] ≤ flow[l,t] ≤ capacity[l])
```

Testing:
- Create test/unit/test_constraints.jl
- Create test/integration/test_constraint_system.jl
- Test each constraint type in isolation
- Test constraint interactions (thermal + hydro + network)
- Test mathematical correctness (verify against manual calculations)
- Test infeasibility detection
- Test with realistic Brazilian system (small example)
- Validate constraint count (expect ~100K for full system)
- Ensure all tests pass
- Target >85% coverage (some constraint paths hard to test)

Expected Output:
- src/adapters/powermodels_adapter.jl (approximately 250 lines) - NEW
- src/constraints/constraint_types.jl (base types, approximately 100 lines)
- src/constraints/network_powermodels.jl (approximately 150 lines) - PowerModels wrapper
- src/constraints/energy_balance.jl (approximately 150 lines)
- src/constraints/thermal_commitment.jl (approximately 300 lines)
- src/constraints/hydro_water_balance.jl (approximately 200 lines)
- src/constraints/hydro_generation.jl (approximately 150 lines)
- src/constraints/submarket_balance.jl (approximately 150 lines) - NEW (ONS-specific)
- src/constraints/submarket_interconnection.jl (approximately 100 lines) - NEW (ONS-specific)
- src/constraints/renewable_limits.jl (approximately 100 lines)
- test/unit/test_powermodels_adapter.jl (approximately 300 lines) - NEW
- test/unit/test_constraints.jl (approximately 800 lines)
- test/integration/test_constraint_system.jl (approximately 400 lines)
- All tests passing
- Code formatted with JuliaFormatter

Example Usage:
```julia
model = DessemModel(system, time_periods=168)
create_variables!(model)

# Add network constraints (using PowerModels)
add_constraint!(model, NetworkPowerModelsConstraint(; formulation=:DC))

# Add ONS-specific constraints
add_constraint!(model, SubmarketEnergyBalanceConstraint(; include_losses=true))
add_constraint!(model, SubmarketInterconnectionConstraint())
add_constraint!(model, ThermalCommitmentConstraint(; include_ramp=true))
add_constraint!(model, HydroWaterBalanceConstraint(; include_cascade=true))
add_constraint!(model, RenewableLimitsConstraint())

# Build all constraints
build_all_constraints!(model)

# Solve with HiGHS
solution = optimize!(model, HiGHS.Optimizer)
```
```

---

## Phase 4: Objective Function and Solvers

### TASK-007: Objective Function Builder

**Status**: 🟡 Planned
**Complexity**: 6/10
**Precedence**: TASK-006 (requires constraints to be built)

**Description**:
Implement the objective function for cost minimization in the Brazilian electricity market. The objective minimizes total system operating costs.

**Cost Components**:

1. **Thermal Generation Costs**
   - Fuel cost: Σ(g[i,t] × cost[i,t])
   - Startup cost: Σ(z[i,t] × startup_cost[i])
   - Shutdown cost: Σ(w[i,t] × shutdown_cost[i])

2. **Hydro Generation Costs**
   - Opportunity cost of water usage (future value)
   - Usually modeled via constraints, not direct cost

3. **Renewable Costs**
   - Usually zero marginal cost
   - Curtailment cost (if any)

4. **Load Shedding Costs**
   - Very high penalty cost (R$/MWh)
   - Encourages meeting demand

5. **Deficit Costs**
   - Penalty for not meeting demand

**Objective Function**:
```
Minimize:
  Σ(thermal_generation_cost + startup_cost + shutdown_cost)
  + Σ(load_shedding_cost × shed[l,t])
  + Σ(deficit_cost × deficit[s,t])
```

**Perfect Prompt for Coding Agent**:
```
Implement the objective function for OpenDESSEM to minimize total system operating costs.

Requirements:
1. Create src/objective/objective_function.jl
2. Implement build_objective!(model) function
3. Minimize: thermal costs + startup/shutdown + load shedding + deficit
4. Support cost scenarios (different fuel prices)
5. Allow cost component weights
6. Return objective value structure (breakdown by component)
7. Comprehensive docstrings

Testing:
- Create test/unit/test_objective.jl
- Test cost calculation for simple system
- Test thermal cost components
- Test startup/shutdown costs
- Test load shedding penalty
- Verify objective value matches manual calculation
- Ensure all tests pass

Expected Output:
- src/objective/objective_function.jl (approximately 200 lines)
- test/unit/test_objective.jl (approximately 300 lines)
- All tests passing
```

---

### TASK-008: Solver Interface

**Status**: 🟡 Planned
**Complexity**: 7/10
**Precedence**: TASK-007 (requires objective function)

**Description**:
Create a unified interface for solving the optimization model with different solvers (HiGHS, Gurobi, CPLEX, etc.).

**Required Functions**:
- `optimize!(model, solver)` - Solve the model
- `get_solution(model)` - Extract solution
- `solve_status(model)` - Check if optimal/infeasible/unbounded
- `solve_time(model)` - Get solution time
- `objective_value(model)` - Get optimal cost
- `get_dual_values(model)` - Extract shadow prices

**Perfect Prompt for Coding Agent**:
```
Implement the solver interface for OpenDESSEM to solve optimization models.

Requirements:
1. Create src/solvers/solver_interface.jl
2. Support HiGHS (open source) and Gurobi (commercial)
3. Handle solver errors gracefully
4. Extract solution, dual values, solve time
5. Provide solve status (optimal, infeasible, unbounded)
6. Comprehensive error messages
7. Solver options (time limit, MIP gap, threads)

Testing:
- Create test/unit/test_solver_interface.jl
- Test HiGHS solver
- Test solution extraction
- Test error handling
- Test with infeasible model
- Ensure all tests pass

Expected Output:
- src/solvers/solver_interface.jl (approximately 250 lines)
- test/unit/test_solver_interface.jl (approximately 200 lines)
- All tests passing
```

---

## Phase 5: Data Loading and Integration

### TASK-009: Database Loaders (PostgreSQL)

**Status**: 🟡 Planned
**Complexity**: 8/10
**Precedence**: TASK-008 (can be done in parallel)

**Description**:
Implement data loaders that read from PostgreSQL databases used by ONS and CCEE to populate the ElectricitySystem.

**Perfect Prompt for Coding Agent**:
```
Implement PostgreSQL data loaders for OpenDESSEM to read Brazilian system data.

Requirements:
1. Create src/data/loaders/database_loader.jl
2. Use LibPQ.jl for PostgreSQL connection
3. Load entities: thermal, hydro, renewable, network, market
4. Validate data integrity on load
5. Support incremental updates
6. Handle missing data gracefully
7. Comprehensive logging
8. Return populated ElectricitySystem

Testing:
- Create test/integration/test_database_loader.jl
- Test connection to test database
- Test data loading for each entity type
- Test validation errors
- Ensure all tests pass

Expected Output:
- src/data/loaders/database_loader.jl (approximately 600 lines)
- test/integration/test_database_loader.jl (approximately 400 lines)
- All tests passing
```

---

### TASK-010: DESSEM2Julia Integration (ONS Format Loader)

**Status**: 🟡 Planned (MAJOR REVISION - Now uses DESSEM2Julia)
**Complexity**: 3/10 (⬇️ REDUCED from 7/10 - DESSEM2Julia is complete!)
**Precedence**: TASK-004.5 (requires ElectricitySystem container)
**Can be parallel with**: TASK-009 (PostgreSQL loader)

**Description**:
Integrate **DESSEM2Julia** library to load ONS DESSEM input files. This is dramatically simpler than writing custom parsers - DESSEM2Julia already has complete, production-ready parsers for all 32 DESSEM file formats with 7,680+ passing tests!

**🎉 DISCOVERY**: DESSEM2Julia (https://github.com/Bittencourt/DESSEM2Julia)

**What is DESSEM2Julia?**
- Complete DESSEM file parser (32/32 file formats - 100% coverage)
- Production-ready with 7,680+ passing tests
- Converts DESSEM files → structured Julia objects
- Developed specifically for Brazilian DESSEM format
- Actively maintained and documented

**Parsed File Formats** (32 total):
- **Core**: dessem.arq, termdat.dat, entdados.dat, operut.dat, dadvaz.dat, hidr.dat
- **Hydro**: operuh.dat, deflant.dat, cotasr11.dat, curvtviag.dat
- **Network**: desselet.dat, ils_tri.dat, areacont.dat, infofcf.dat
- **Constraints**: restseg.dat, rstlpp.dat, rmpflx.dat, rampas.dat, respot.dat
- **Renewables**: renovaveis.dat (wind, solar, biomass, small hydro)
- **Auxiliary**: dessopc.dat, ptoper.dat, rivar.dat, cortdeco.rv2
- **Binary**: mlt.dat (FPHA binary), hidr.dat (hydro binary - 111 fields!)

**🎯 NEW STRATEGY**: Use DESSEM2Julia as the DESSEM file parser (don't reinvent the wheel!)

**Implementation Approach**:

1. **Add DESSEM2Julia as Dependency**
   ```toml
   # In Project.toml
   DESSEM2Julia = "44e5fb91-fbef-4ac9-87eb-32963ceede09"
   ```

2. **Create Adapter Layer**
   - Load DESSEM case with DESSEM2Julia
   - Convert DESSEM2Julia objects → OpenDESSEM entities
   - Map field names (DESSEM2Julia → OpenDESSEM conventions)
   - Handle data type conversions

3. **Entity Mapping** (DESSEM2Julia → OpenDESSEM):
   ```
   DESSEM2Julia ThermalUnit → ConventionalThermal
   DESSEM2Julia HydroUnit → ReservoirHydro / RunOfRiverHydro / PumpedStorageHydro
   DESSEM2Julia WindUnit → WindPlant
   DESSEM2Julia SolarUnit → SolarPlant
   DESSEM2Julia Bus → Bus
   DESSEM2Julia Branch → ACLine
   DESSEM2Julia Demand → Load
   ```

4. **Data Flow**:
   ```
   DESSEM Files (.dat, .pwf)
     ↓ (DESSEM2Julia parses)
   DESSEM2Julia Structs (DessemCase)
     ↓ (Adapter converts)
   OpenDESSEM ElectricitySystem
   ```

**Key Functions**:
```julia
# Main loader
load_dessem_case(case_directory::String)::ElectricitySystem

# Entity converters
convert_thermal_unit(d2_thermal::DESSEM2Julia.ThermalUnit)::ConventionalThermal
convert_hydro_unit(d2_hydro::DESSEM2Julia.HydroUnit)::Union{ReservoirHydro, RunOfRiverHydro}
convert_wind_unit(d2_wind::DESSEM2Julia.WindUnit)::WindPlant
convert_solar_unit(d2_solar::DESSEM2Julia.SolarUnit)::SolarPlant
convert_bus(d2_bus::DESSEM2Julia.Bus)::Bus
convert_branch(d2_branch::DESSEM2Julia.Branch)::ACLine
convert_demand(d2_demand::DESSEM2Julia.Demand)::Load

# Helper
map_dessem2julia_to_opendessem(d2_case::DESSEM2Julia.DessemCase)::ElectricitySystem
```

**Advantages of Using DESSEM2Julia**:
- ✅ **No custom parsers needed** - 7,680+ tests already written
- ✅ **Production-ready** - handles all edge cases, real ONS data
- ✅ **Actively maintained** - get bug fixes and new features for free
- ✅ **Well-documented** - comprehensive docs and examples
- ✅ **Reduces implementation time** - 3 weeks → 1 week
- ✅ **Lower risk** - proven to work with real CCEE and ONS data
- ✅ **Network topology extraction** - built-in support for electrical network
- ✅ **Binary file support** - handles complex binary formats (HIDR, MLT)

**Test Cases**:
- Load sample DESSEM case (docs/Sample/DS_ONS_102025_RV2D11/)
- Verify all entity types convert correctly
- Test with CCEE case (docs/Sample/DS_CCEE_102025_SEMREDE_RV0D28/)
- Validate converted ElectricitySystem (using validate_system())
- Test entity counts match (thermal: 116, hydro: 168, buses: 342, etc.)
- Test network topology preservation

**Perfect Prompt for Coding Agent**:
```
Integrate DESSEM2Julia to load DESSEM input files for OpenDESSEM.

Context:
- DESSEM2Julia is a complete DESSEM parser (32/32 files, 7,680+ tests)
- GitHub: https://github.com/Bittencourt/DESSEM2Julia
- It parses DESSEM files and returns structured Julia objects
- We need to convert those objects to OpenDESSEM entity types
- This is MUCH simpler than writing custom parsers

Requirements:
1. Add DESSEM2Julia to Project.toml dependencies
2. Create src/data/loaders/dessem2julia_loader.jl
3. Implement load_dessem_case(case_directory) main function:
   - Use DESSEM2Julia.parse_case() to load .dat files
   - Convert DESSEM2Julia objects → OpenDESSEM entities
   - Return populated ElectricitySystem
4. Implement entity converters:
   - convert_thermal_unit()
   - convert_hydro_unit() (detect type: RESERVOIR, RUN_OF_RIVER, PUMPED_STORAGE)
   - convert_wind_unit()
   - convert_solar_unit()
   - convert_bus()
   - convert_branch()
   - convert_demand()
5. Map field names correctly (DESSEM2Julia → OpenDESSEM conventions)
6. Use OpenDESSEM entity constructors (they handle validation)
7. Add comprehensive docstrings
8. Handle all error cases gracefully

DESSEM2Julia API Example:
```julia
using DESSEM2Julia

# Parse DESSEM case
d2_case = DESSEM2Julia.parse_case("path/to/dessem/case")

# Access data
d2_case.thermal_units  # Vector{ThermalUnit}
d2_case.hydro_units    # Vector{HydroUnit}
d2_case.buses          # Vector{Bus}
d2_case.branches       # Vector{Branch}
d2_case.demands        # Vector{Demand}
```

Testing:
- Create test/integration/test_dessem2julia_loader.jl
- Test loading docs/Sample/DS_ONS_102025_RV2D11/
- Verify entity counts match expected
- Test entity field mappings
- Validate converted ElectricitySystem
- Test error handling (missing files, malformed data)
- Ensure all 544+ existing tests pass
- Target >85% coverage (some DESSEM2Julia code paths untestable)

Expected Output:
- src/data/loaders/dessem2julia_loader.jl (approximately 200 lines - simple adapter!)
- test/integration/test_dessem2julia_loader.jl (approximately 150 lines)
- Updated Project.toml with DESSEM2Julia dependency
- All tests passing
- Can load real ONS/CCEE DESSEM cases

Example Usage:
```julia
using OpenDESSEM

# Load DESSEM case using DESSEM2Julia
system = load_dessem_case("docs/Sample/DS_ONS_102025_RV2D11/")

# Now we have a complete ElectricitySystem
println("Loaded $(length(system.thermal_plants)) thermal plants")
println("Loaded $(length(system.hydro_plants)) hydro plants")
println("Loaded $(length(system.buses)) buses")

# Validate
@assert validate_system(system)

# Use in optimization model
model = DessemModel(system, time_periods=168)
```
```

**Files to Create**:
- `src/data/loaders/dessem2julia_loader.jl` - Adapter implementation
- `test/integration/test_dessem2julia_loader.jl` - Integration tests

**Dependencies**:
- **Blocks**: TASK-011, TASK-012 (need data loaded first)
- **Requires**: TASK-004.5 (ElectricitySystem container)

**Comparison With Original Plan**:

| Aspect | Original (Custom Parsers) | NEW (DESSEM2Julia) |
|--------|---------------------------|---------------------|
| Complexity | 7/10 | **3/10** ⬇️ |
| Implementation Time | 3-4 weeks | **1 week** ⬇️ |
| Test Coverage | Write 1,000+ tests | **7,680+ tests existing** ✅ |
| Maintenance Burden | High (maintain parsers) | **Low** (DESSEM2Julia team) ✅ |
| Risk | High (custom parsers) | **Low** (proven with real data) ✅ |
| Network Support | PWF.jl + custom | **Built-in** ✅ |
| Binary Files | Custom implementation | **Already supported** ✅ |

---

### TASK-011: Solution Export and Analysis

**Status**: 🟡 Planned
**Complexity**: 5/10
**Precedence**: TASK-008 (requires solver interface)

**Description**:
Create tools to export solutions and analyze optimization results.

**Perfect Prompt for Coding Agent**:
```
Implement solution export and analysis tools for OpenDESSEM.

Requirements:
1. Create src/analysis/solution_exporter.jl
2. Export to CSV, JSON, and ONS format
3. Generate reports (generation by plant, marginal prices, etc.)
4. Plotting functions for visualization
5. Calculate summary statistics
6. Compare solutions across scenarios
7. Comprehensive docstrings

Testing:
- Create test/unit/test_solution_exporter.jl
- Test CSV export
- Test JSON export
- Test summary statistics
- Test visualization generation
- Ensure all tests pass

Expected Output:
- src/analysis/solution_exporter.jl (approximately 400 lines)
- test/unit/test_solution_exporter.jl (approximately 250 lines)
- All tests passing
```

---

## Phase 6: Validation and Testing

### TASK-012: Validation Against Official DESSEM

**Status**: 🟡 Planned
**Complexity**: 9/10
**Precedence**: TASK-010, TASK-011 (needs data loading and solution export)

**Description**:
Validate OpenDESSEM results against official DESSEM software outputs to ensure correctness.

**Perfect Prompt for Coding Agent**:
```
Implement validation framework to compare OpenDESSEM with official DESSEM results.

Requirements:
1. Create test/validation/compare_with_dessem.jl
2. Load official DESSEM results from .dat files
3. Compare generation, storage, flows, prices
4. Calculate error metrics (MAE, RMSE, MAPE)
5. Generate comparison reports
6. Identify discrepancies > tolerance
7. Validate with sample cases (docs/Sample/)

Testing:
- Use docs/Sample/DS_ONS_102025_RV2D11/ as test data
- Compare with official DESSEM output
- Generate validation report
- Target: <1% error for key variables
- Ensure all tests pass

Expected Output:
- test/validation/compare_with_dessem.jl (approximately 500 lines)
- docs/VALIDATION_REPORT.md (generated)
- Validation results showing <1% error
```

---

## Task Complexity Summary

| Complexity | Tasks | Count |
|------------|-------|-------|
| 0-3 (Trivial-Easy) | TASK-010 | 1 |
| 4-6 (Moderate) | TASK-002, TASK-004, TASK-007, TASK-011, TASK-003.5, TASK-004.5 | 6 |
| 7-8 (Complex) | TASK-001, TASK-003, TASK-005, TASK-006, TASK-009 | 5 |
| 9-10 (Very Complex) | TASK-012 | 1 |

**Total Tasks**: 13 (2 new tasks added: TASK-003.5, TASK-004.5)
**Estimated Total Complexity**: **84/140**

**Complexity Reductions**:
- ✅ TASK-006: 10/10 → 8/10 (PowerModels.jl integration)
- ✅ TASK-010: 7/10 → 3/10 (DESSEM2Julia adoption)
- ✅ TASK-005: 10/10 → 9/10 (ElectricitySystem simplifies variable management)

**New Tasks**:
- ✅ TASK-003.5: PowerModels.jl Integration Layer (6/10)
- ✅ TASK-004.5: ElectricitySystem Container (5/10)

---

## Recommended Execution Order

### First Wave (Foundation - Entity System)
1. **TASK-001**: Hydroelectric entities (builds entity system)
2. **TASK-002**: Renewable entities (parallel with TASK-001)
3. **TASK-003**: Network entities (parallel with TASK-001, TASK-002)
4. **TASK-004**: Market entities (quick win, depends on TASK-003)
5. **TASK-003.5**: PowerModels.jl Integration Layer (requires TASK-003) 🆕
6. **TASK-004.5**: ElectricitySystem Container (requires all entity types) 🆕

### Second Wave (Core Optimization)
7. **TASK-005**: Variable manager (requires TASK-004.5 ElectricitySystem)
8. **TASK-006**: Constraint builder (requires TASK-005 variables + TASK-003.5 PowerModels adapter)
9. **TASK-007**: Objective function (requires constraints)
10. **TASK-008**: Solver interface (requires objective)

### Third Wave (Data & Validation)
11. **TASK-009**: PostgreSQL loaders (parallel with TASK-010)
12. **TASK-010**: DESSEM2Julia Integration (parallel with TASK-009) ⬇️ Complexity reduced!
13. **TASK-011**: Solution export (requires solver)
14. **TASK-012**: Validation (requires data loading and export)

---

## Next Steps

**✅ Completed** (First & Second Wave - Entity System Complete):
- TASK-001: Hydroelectric entities ✅
- TASK-002: Renewable entities ✅
- TASK-003: Network entities ✅
- TASK-003.5: PowerModels.jl Integration Layer ✅
- TASK-004: Market entities ✅
- TASK-004.5: ElectricitySystem Container ✅

**Current Priority** (Third Wave - Optimization Core):
1. **TASK-005**: Variable Manager (9/10 complexity)
   - Create JuMP variables from ElectricitySystem entities
   - Depends on TASK-004.5 (completed)
   - No blockers - ready to start

2. **TASK-006**: Constraint Builder System (8/10 complexity)
   - Build constraints using PowerModels + custom ONS constraints
   - Depends on TASK-005 and TASK-003.5 (both ready)

**Parallel Work**: TASK-009 (PostgreSQL loaders) and TASK-010 (DESSEM2Julia) can be worked on in parallel with TASK-005/006

**Next Wave Preparation**: Complete TASK-005 and TASK-006 before starting TASK-007 (Objective Function)

---

**End of TODO List**

For questions or clarifications about any task, refer to:
- Project guidelines: `.claude/CLAUDE.md`
- Agent instructions: `AGENTS.md`
- Entity reference: `docs/entity_reference.md` (to be created)
- Constraint reference: `docs/constraint_reference.md` (to be created)
