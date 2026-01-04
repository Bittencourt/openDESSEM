# OpenDESSEM Development Task List

**Last Updated**: 2026-01-04
**Status**: Active
**Current Phase**: Entity System Expansion

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

**Status**: 🔵 In Progress (Started 2026-01-04)
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

**Status**: 🔵 In Progress (Started 2026-01-04)
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

### TASK-004: Market Entity Types

**Status**: 🟡 Planned
**Complexity**: 4/10
**Precedence**: TASK-003 (depends on network entities)

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

## Phase 3: Variable Management System

### TASK-005: Variable Manager Module

**Status**: 🟡 Planned
**Complexity**: 9/10
**Precedence**: TASK-001, TASK-002, TASK-003 (needs complete entity system)

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

### TASK-006: Constraint Builder System

**Status**: 🟡 Planned
**Complexity**: 10/10 (most complex part of the system)
**Precedence**: TASK-005 (requires variables to exist first)

**Description**:
Implement a modular, extensible constraint building system that adds optimization constraints to the JuMP model. This is where the mathematical optimization model is constructed.

**Constraint Categories**:

1. **Energy Balance Constraints**
   - Supply = Demand for each bus/submarket/time
   - Include generation, imports, exports, load shedding
   - Handle losses

2. **Thermal Unit Commitment Constraints**
   - Capacity limits: g_min * u ≤ g ≤ g_max * u
   - Ramp limits: g[t] - g[t-1] ≤ ramp_up * 60
   - Minimum up/down time
   - Startup/shutdown logic: u[t] - u[t-1] = z[t] - w[t]

3. **Hydro Constraints**
   - Water balance: s[t] = s[t-1] + inflow[t] - outflow[t] - spill[t]
   - Generation function: h[t] = f(outflow[t], head[t])
   - Storage bounds: s_min ≤ s[t] ≤ s_max
   - Final storage requirement: s[T] ≥ s_final
   - Cascade coupling: outflow_upstream[t] = inflow_downstream[t + travel_time]

4. **Network Constraints**
   - Power flow: flow[line] = (θ_from - θ_to) / X_line
   - Thermal limits: -capacity ≤ flow ≤ capacity
   - Voltage limits: V_min ≤ V ≤ V_max
   - Angle reference: θ_slack = 0

5. **Renewable Constraints**
   - Generation ≤ forecast: g ≤ g_forecast
   - Curtailment: g + c = g_forecast

6. **Market Constraints**
   - Bilateral contract fulfillment
   - Deficit limits (load shedding)
   - Price calculation (dual variables)

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
Implement the constraint builder system for OpenDESSEM - the core optimization engine.

Context:
- Variables are created by VariableManager (TASK-005)
- Need to add mathematical constraints to JuMP model
- This is the most complex part - requires careful optimization modeling
- Brazilian DESSEM has specific constraint formulations

Requirements:
1. Create src/constraints/ directory with modular constraint system
2. Define AbstractConstraint base type
3. Implement build!(model, constraint) method for each constraint type
4. Create constraint modules:
   - energy_balance.jl - Supply-demand balance
   - thermal_commitment.jl - UC constraints (capacity, ramp, min up/down)
   - hydro_water_balance.jl - Reservoir dynamics, cascade coupling
   - hydro_generation.jl - Generation function (outflow → power)
   - network_power_flow.jl - DC power flow (θ-based)
   - renewable_limits.jl - Generation ≤ forecast
5. Use ConstraintMetadata for documentation and ordering
6. Support constraint enable/disable flags
7. Validate constraint consistency (no conflicting bounds)
8. Comprehensive docstrings with mathematical formulations

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
- src/constraints/energy_balance.jl (approximately 150 lines)
- src/constraints/thermal_commitment.jl (approximately 300 lines)
- src/constraints/hydro_water_balance.jl (approximately 200 lines)
- src/constraints/hydro_generation.jl (approximately 150 lines)
- src/constraints/network_power_flow.jl (approximately 250 lines)
- src/constraints/renewable_limits.jl (approximately 100 lines)
- src/constraints/constraint_types.jl (base types, approximately 100 lines)
- test/unit/test_constraints.jl (approximately 800 lines)
- test/integration/test_constraint_system.jl (approximately 400 lines)
- All tests passing
- Code formatted with JuliaFormatter

Example Usage:
```julia
model = DessemModel(system, time_periods=168)
create_variables!(model)

# Add constraints
add_constraint!(model, EnergyBalanceConstraint(; include_losses=true))
add_constraint!(model, ThermalCommitmentConstraint(; include_ramp=true))
add_constraint!(model, HydroWaterBalanceConstraint(; include_cascade=true))
add_constraint!(model, NetworkPowerFlowConstraint(; formulation=:DC))

build_all_constraints!(model)
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

### TASK-010: File-Based Loaders (ONS Format)

**Status**: 🟡 Planned
**Complexity**: 7/10
**Precedence**: TASK-009 (can be done in parallel)

**Description**:
Implement loaders for ONS text file format (the existing DESSEM input format).

**Important Note**: Use **PWF.jl** library for parsing .pwf (Power World Format) files. PWF.jl is a Julia package specifically designed for parsing .pwf files, which contain network topology and power flow data. This will significantly simplify the implementation of network-related file parsing. Add PWF.jl as a dependency in Project.toml:

```toml
[deps]
PWF = "fd6700fa-a6c1-580c-9db4-8a966f3d263a"
```

**Perfect Prompt for Coding Agent**:
```
Implement file-based data loaders for ONS DESSEM input format.

Requirements:
1. Create src/data/loaders/file_loader.jl
2. Parse ONS .dat files (see docs/Sample/DS_ONS_102025_RV2D11/)
3. **Use PWF.jl for parsing .pwf files** (network topology and power flow data)
4. Load thermal, hydro, network data from files
5. Validate file format and data consistency
6. Support multiple scenarios
7. Clear error messages for malformed files
8. Return populated ElectricitySystem

PWF.jl Integration:
- Add PWF.jl to Project.toml dependencies
- Use PWF.jl functions to parse .pwf files containing:
  - Bus data (voltage levels, connections)
  - Line data (impedance, capacity)
  - Transformer data
  - Load data
- Reference: https://github.com/JuliaEnergy/PWF.jl

Testing:
- Create test/integration/test_file_loader.jl
- Test loading sample files from docs/Sample/
- Validate PWF.jl integration with .pwf files
- Validate loaded data integrity
- Test error handling for malformed files
- Ensure all tests pass

Expected Output:
- src/data/loaders/file_loader.jl (approximately 500 lines, reduced complexity with PWF.jl)
- test/integration/test_file_loader.jl (approximately 300 lines)
- Updated Project.toml with PWF.jl dependency
- All tests passing
```

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
| 0-3 (Trivial-Easy) | None planned | 0 |
| 4-6 (Moderate) | TASK-002, TASK-004, TASK-007, TASK-011 | 4 |
| 7-8 (Complex) | TASK-001, TASK-003, TASK-005, TASK-009, TASK-010 | 5 |
| 9-10 (Very Complex) | TASK-006, TASK-012 | 2 |

**Total Tasks**: 11
**Estimated Total Complexity**: 77/110

---

## Recommended Execution Order

### First Wave (Foundation)
1. **TASK-001**: Hydroelectric entities (builds entity system)
2. **TASK-002**: Renewable entities (parallel with TASK-001)
3. **TASK-003**: Network entities (parallel with TASK-001, TASK-002)
4. **TASK-004**: Market entities (quick win, depends on TASK-003)

### Second Wave (Core Optimization)
5. **TASK-005**: Variable manager (requires all entities)
6. **TASK-006**: Constraint builder (most complex, requires variables)
7. **TASK-007**: Objective function (requires constraints)
8. **TASK-008**: Solver interface (requires objective)

### Third Wave (Data & Validation)
9. **TASK-009**: PostgreSQL loaders (parallel with TASK-010)
10. **TASK-010**: File loaders (parallel with TASK-009)
11. **TASK-011**: Solution export (requires solver)
12. **TASK-012**: Validation (requires data loading and export)

---

## Next Steps

**Immediate Priority**: TASK-001 (Hydroelectric Plant Entities)
- Builds on existing entity system
- Essential for Brazilian hydro-dominated system
- Complexity 7/10 (challenging but achievable)
- Can use thermal entities as reference
- No dependencies on other pending tasks

**Parallel Work**: TASK-002 and TASK-003 can be started simultaneously with TASK-001

---

**End of TODO List**

For questions or clarifications about any task, refer to:
- Project guidelines: `.claude/CLAUDE.md`
- Agent instructions: `AGENTS.md`
- Entity reference: `docs/entity_reference.md` (to be created)
- Constraint reference: `docs/constraint_reference.md` (to be created)
