"""
    Small Test System Factory for End-to-End Integration Tests

Provides factory functions to create minimal test systems for solver testing.
These systems are small enough to solve quickly but complete enough to
exercise the full optimization pipeline.

# Factory Functions

- `create_small_test_system()`: Creates a basic 2-thermal, 1-hydro system
- `create_infeasible_test_system()`: Creates a deliberately infeasible system

# System Structure

The small test system consists of:
- 2 thermal plants in SE submarket (150 MW, 200 MW)
- 1 hydro plant in SE submarket (200 MW)
- 1 bus (single-bus model for simplicity)
- 1 submarket (SE)
- 1 load profile
- 6 time periods

# Example

```julia
using Test
using OpenDESSEM
using OpenDESSEM.Solvers

# Create test system
model, system = create_small_test_system()

# Solve with default settings
result = solve_model!(model, system)

# Check result
@test result.solve_status == OPTIMAL
```
"""

module SmallSystemFactory

using Dates
using JuMP
using HiGHS

using OpenDESSEM
using OpenDESSEM:
    ConventionalThermal, NATURAL_GAS, ReservoirHydro, Bus, Submarket, Load,
    ElectricitySystem
using OpenDESSEM:
    create_thermal_variables!, create_hydro_variables!, create_deficit_variables!,
    ThermalCommitmentConstraint, HydroGenerationConstraint, HydroWaterBalanceConstraint,
    SubmarketBalanceConstraint, ConstraintMetadata, build!,
    ProductionCostObjective, ObjectiveMetadata

export create_small_test_system, create_infeasible_test_system

"""
    create_small_test_system(;
        num_thermal::Int=2,
        num_hydro::Int=1,
        num_periods::Int=6,
        include_deficit::Bool=true
    ) -> Tuple{Model, ElectricitySystem}

Create a small test system for end-to-end solver testing.

Creates a minimal electricity system with thermal plants, hydro plants,
and load, then builds a complete JuMP model with variables, constraints,
and objective function.

# Arguments

- `num_thermal::Int`: Number of thermal plants (1-3, default: 2)
- `num_hydro::Int`: Number of hydro plants (0-2, default: 1)
- `num_periods::Int`: Number of time periods (1-24, default: 6)
- `include_deficit::Bool`: Include deficit variables in model (default: true)

# Returns

- `Tuple{Model, ElectricitySystem}`: Tuple of (JuMP model, system)

# System Details

## Thermal Plants
- T001: 150 MW capacity, 50 MW min, 200 R\$/MWh fuel cost
- T002: 200 MW capacity, 80 MW min, 180 R\$/MWh fuel cost
- T003 (optional): 100 MW capacity, 30 MW min, 220 R\$/MWh fuel cost

## Hydro Plant
- H001: 200 MW capacity, 1000 hm³ reservoir, 0.9 productivity

## Load Profile
- Base load: 300 MW
- Simple profile varying from 80% to 120% of base

# Example

```julia
# Create default system (2 thermal, 1 hydro, 6 periods)
model, system = create_small_test_system()

# Create minimal system (1 thermal, 0 hydro, 3 periods)
model, system = create_small_test_system(;
    num_thermal=1,
    num_hydro=0,
    num_periods=3
)

# Solve the model
result = solve_model!(model, system; time_limit=60.0)
```

# Notes

- All plants are in the SE submarket
- Single-bus model (no network topology)
- The model is ready to solve immediately after creation
- Uses HiGHS optimizer by default (required dependency)
"""
function create_small_test_system(;
    num_thermal::Int = 2,
    num_hydro::Int = 1,
    num_periods::Int = 6,
    include_deficit::Bool = true,
)
    # Clamp arguments to valid ranges
    num_thermal = clamp(num_thermal, 1, 3)
    num_hydro = clamp(num_hydro, 0, 2)
    num_periods = clamp(num_periods, 1, 24)

    # ==========================================================================
    # Create System Entities
    # ==========================================================================

    # Create bus
    bus = Bus(;
        id = "B001",
        name = "Test Bus",
        voltage_kv = 230.0,
        base_kv = 230.0,
        area_id = "SE",
    )

    # Create submarket
    submarket = Submarket(;
        id = "SM_SE",
        name = "Southeast Test",
        code = "SE",
        country = "Brazil",
    )

    # Create thermal plants
    thermal_plants = ConventionalThermal[]

    # Plant 1: 150 MW gas plant
    if num_thermal >= 1
        push!(
            thermal_plants,
            ConventionalThermal(;
                id = "T001",
                name = "Thermal Plant 1",
                bus_id = "B001",
                submarket_id = "SE",
                fuel_type = NATURAL_GAS,
                capacity_mw = 150.0,
                min_generation_mw = 50.0,
                max_generation_mw = 150.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                min_up_time_hours = 2,
                min_down_time_hours = 1,
                fuel_cost_rsj_per_mwh = 200.0,
                startup_cost_rs = 5000.0,
                shutdown_cost_rs = 2000.0,
                commissioning_date = DateTime(2020, 1, 1),
            ),
        )
    end

    # Plant 2: 200 MW gas plant
    if num_thermal >= 2
        push!(
            thermal_plants,
            ConventionalThermal(;
                id = "T002",
                name = "Thermal Plant 2",
                bus_id = "B001",
                submarket_id = "SE",
                fuel_type = NATURAL_GAS,
                capacity_mw = 200.0,
                min_generation_mw = 80.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 15.0,
                ramp_down_mw_per_min = 15.0,
                min_up_time_hours = 3,
                min_down_time_hours = 2,
                fuel_cost_rsj_per_mwh = 180.0,
                startup_cost_rs = 8000.0,
                shutdown_cost_rs = 3000.0,
                commissioning_date = DateTime(2018, 6, 1),
            ),
        )
    end

    # Plant 3: 100 MW gas plant
    if num_thermal >= 3
        push!(
            thermal_plants,
            ConventionalThermal(;
                id = "T003",
                name = "Thermal Plant 3",
                bus_id = "B001",
                submarket_id = "SE",
                fuel_type = NATURAL_GAS,
                capacity_mw = 100.0,
                min_generation_mw = 30.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 8.0,
                ramp_down_mw_per_min = 8.0,
                min_up_time_hours = 2,
                min_down_time_hours = 1,
                fuel_cost_rsj_per_mwh = 220.0,
                startup_cost_rs = 3000.0,
                shutdown_cost_rs = 1500.0,
                commissioning_date = DateTime(2022, 3, 1),
            ),
        )
    end

    # Create hydro plants
    hydro_plants = ReservoirHydro[]

    # Hydro Plant 1: 200 MW reservoir
    if num_hydro >= 1
        push!(
            hydro_plants,
            ReservoirHydro(;
                id = "H001",
                name = "Hydro Plant 1",
                bus_id = "B001",
                submarket_id = "SE",
                max_generation_mw = 200.0,
                min_generation_mw = 0.0,
                max_storage_hm3 = 1000.0,
                min_storage_hm3 = 200.0,
                initial_volume_hm3 = 800.0,
                productivity_m3_per_s_to_mw = 0.9,
                max_outflow_m3_per_s = 300.0,
                min_outflow_m3_per_s = 0.0,
                max_turbining_m3_per_s = 250.0,
                commissioning_date = DateTime(2010, 1, 1),
            ),
        )
    end

    # Hydro Plant 2: 150 MW reservoir
    if num_hydro >= 2
        push!(
            hydro_plants,
            ReservoirHydro(;
                id = "H002",
                name = "Hydro Plant 2",
                bus_id = "B001",
                submarket_id = "SE",
                max_generation_mw = 150.0,
                min_generation_mw = 0.0,
                max_storage_hm3 = 800.0,
                min_storage_hm3 = 150.0,
                initial_volume_hm3 = 600.0,
                productivity_m3_per_s_to_mw = 0.85,
                max_outflow_m3_per_s = 250.0,
                min_outflow_m3_per_s = 0.0,
                max_turbining_m3_per_s = 200.0,
                commissioning_date = DateTime(2012, 1, 1),
            ),
        )
    end

    # Create load profile (simple variation)
    base_load_mw = 300.0
    load_profile = Float64[
        0.9,  # Period 1: 270 MW
        0.85, # Period 2: 255 MW
        0.9,  # Period 3: 270 MW
        1.0,  # Period 4: 300 MW
        1.1,  # Period 5: 330 MW
        1.2,  # Period 6: 360 MW
    ]

    # Extend or trim profile to num_periods
    if length(load_profile) < num_periods
        # Repeat the last value
        load_profile = vcat(load_profile, fill(load_profile[end], num_periods - length(load_profile)))
    elseif length(load_profile) > num_periods
        load_profile = load_profile[1:num_periods]
    end

    load = Load(;
        id = "L001",
        name = "SE Load",
        submarket_id = "SE",
        base_mw = base_load_mw,
        load_profile = load_profile,
        is_elastic = false,
    )

    # Assemble the system
    system = ElectricitySystem(;
        thermal_plants = thermal_plants,
        hydro_plants = hydro_plants,
        buses = [bus],
        submarkets = [submarket],
        loads = [load],
        base_date = Date(2025, 1, 1),
        description = "Small test system for end-to-end testing",
        version = "1.0",
    )

    # ==========================================================================
    # Build JuMP Model
    # ==========================================================================

    model = Model()

    # Time periods
    time_periods = 1:num_periods

    # Store system in model for later access
    model[:system] = system
    model[:time_periods] = time_periods

    # Create variables
    create_thermal_variables!(model, system, time_periods)

    if !isempty(hydro_plants)
        create_hydro_variables!(model, system, time_periods)
    end

    if include_deficit
        create_deficit_variables!(model, system, time_periods)
    end

    # Build constraints
    # 1. Thermal commitment constraints (ramp, min up/down, startup/shutdown)
    thermal_constraint = ThermalCommitmentConstraint(;
        metadata = ConstraintMetadata(;
            name = "Thermal Commitment",
            description = "Unit commitment constraints",
            priority = 10,
        ),
    )
    build!(model, system, thermal_constraint)

    # 2. Hydro generation constraint (gh = productivity * q)
    if !isempty(hydro_plants)
        hydro_gen_constraint = HydroGenerationConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Generation",
                description = "Hydro generation function",
                priority = 10,
            ),
        )
        build!(model, system, hydro_gen_constraint)

        # 3. Hydro water balance constraint
        water_balance = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Water Balance",
                description = "Reservoir water balance",
                priority = 10,
            ),
        )
        build!(model, system, water_balance)
    end

    # 4. Submarket balance constraint
    balance_constraint = SubmarketBalanceConstraint(;
        metadata = ConstraintMetadata(;
            name = "Submarket Balance",
            description = "Energy balance per submarket",
            priority = 10,
        ),
        include_renewables = false,  # No renewables in this test system
    )
    build!(model, system, balance_constraint)

    # 5. Build objective function
    objective = ProductionCostObjective(;
        metadata = ObjectiveMetadata(;
            name = "Production Cost",
            description = "Minimize total operating cost",
        ),
        thermal_fuel_cost = true,
        thermal_startup_cost = true,
        thermal_shutdown_cost = true,
        hydro_water_value = false,  # No FCF curves in test system
        deficit_cost = include_deficit,
        deficit_penalty = 5000.0,  # High penalty for deficit
    )
    build!(model, system, objective)

    return model, system
end

"""
    create_infeasible_test_system() -> Tuple{Model, ElectricitySystem}

Create a deliberately infeasible test system for IIS testing.

Creates a system where the total load exceeds maximum possible generation,
guaranteeing infeasibility. Useful for testing `compute_iis!()` and
infeasibility diagnostics.

# Returns

- `Tuple{Model, ElectricitySystem}`: Tuple of (JuMP model, system)

# Infeasibility Source

The system is made infeasible by:
1. Setting load to 1000 MW (exceeds max generation)
2. Only 1 thermal plant (150 MW capacity)
3. No deficit variables allowed

This guarantees the submarket balance constraint cannot be satisfied.

# Example

```julia
# Create infeasible system
model, system = create_infeasible_test_system()

# Solve - should return INFEASIBLE
result = solve_model!(model, system; pricing=false)
@test result.solve_status == INFEASIBLE

# Compute IIS
iis_result = compute_iis!(model)
@test length(iis_result.conflicts) > 0
```
"""
function create_infeasible_test_system()
    # ==========================================================================
    # Create System Entities
    # ==========================================================================

    # Create bus
    bus = Bus(;
        id = "B001",
        name = "Test Bus",
        voltage_kv = 230.0,
        base_kv = 230.0,
        area_id = "SE",
    )

    # Create submarket
    submarket = Submarket(;
        id = "SM_SE",
        name = "Southeast Test",
        code = "SE",
        country = "Brazil",
    )

    # Create single thermal plant (150 MW capacity)
    thermal_plant = ConventionalThermal(;
        id = "T001",
        name = "Small Thermal Plant",
        bus_id = "B001",
        submarket_id = "SE",
        fuel_type = NATURAL_GAS,
        capacity_mw = 150.0,
        min_generation_mw = 50.0,
        max_generation_mw = 150.0,
        ramp_up_mw_per_min = 10.0,
        ramp_down_mw_per_min = 10.0,
        min_up_time_hours = 1,
        min_down_time_hours = 1,
        fuel_cost_rsj_per_mwh = 200.0,
        startup_cost_rs = 5000.0,
        shutdown_cost_rs = 2000.0,
        commissioning_date = DateTime(2020, 1, 1),
    )

    # Create load with demand exceeding capacity (1000 MW > 150 MW max)
    # This guarantees infeasibility
    load = Load(;
        id = "L001",
        name = "Large Load",
        submarket_id = "SE",
        base_mw = 1000.0,  # Exceeds max generation
        load_profile = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],  # Constant high load
        is_elastic = false,
    )

    # Assemble the system
    system = ElectricitySystem(;
        thermal_plants = [thermal_plant],
        hydro_plants = ReservoirHydro[],  # No hydro
        buses = [bus],
        submarkets = [submarket],
        loads = [load],
        base_date = Date(2025, 1, 1),
        description = "Deliberately infeasible test system",
        version = "1.0",
    )

    # ==========================================================================
    # Build JuMP Model (without deficit variables to ensure infeasibility)
    # ==========================================================================

    model = Model()
    time_periods = 1:6

    # Store system in model
    model[:system] = system
    model[:time_periods] = time_periods

    # Create variables (NO deficit variables - this ensures infeasibility)
    create_thermal_variables!(model, system, time_periods)

    # Build constraints
    thermal_constraint = ThermalCommitmentConstraint(;
        metadata = ConstraintMetadata(;
            name = "Thermal Commitment",
            description = "Unit commitment constraints",
            priority = 10,
        ),
    )
    build!(model, system, thermal_constraint)

    # Submarket balance - this will be infeasible
    balance_constraint = SubmarketBalanceConstraint(;
        metadata = ConstraintMetadata(;
            name = "Submarket Balance",
            description = "Energy balance per submarket",
            priority = 10,
        ),
        include_renewables = false,
    )
    build!(model, system, balance_constraint)

    # Build objective
    objective = ProductionCostObjective(;
        metadata = ObjectiveMetadata(;
            name = "Production Cost",
            description = "Minimize total operating cost",
        ),
        thermal_fuel_cost = true,
        thermal_startup_cost = true,
        thermal_shutdown_cost = true,
        hydro_water_value = false,
        deficit_cost = false,  # NO deficit - ensures infeasibility
    )
    build!(model, system, objective)

    return model, system
end

end # module
