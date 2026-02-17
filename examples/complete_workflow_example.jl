"""
    Complete Workflow Example - Minimal 3-Bus System

Demonstrates the full OpenDESSEM workflow with a minimal 3-bus power system:
- 3 Buses representing different regions
- 3 Thermal plants with different cost characteristics
- 1 Hydro plant for flexibility
- 1 Wind farm for renewable generation
- 3 Loads representing different demand patterns

This example demonstrates:
1. Creating an ElectricitySystem from scratch
2. Building a JuMP optimization model with variables and constraints
3. Two-stage pricing (UC → SCED) for valid LMP calculation
4. Extracting and displaying results
"""

using OpenDESSEM
using OpenDESSEM.Entities
using OpenDESSEM.Variables
using OpenDESSEM.Constraints:
    build!,
    ThermalCommitmentConstraint,
    HydroWaterBalanceConstraint,
    RenewableLimitConstraint,
    SubmarketBalanceConstraint,
    ConstraintMetadata
using OpenDESSEM.Objective:
    ProductionCostObjective, ObjectiveMetadata, build! as build_objective!
using OpenDESSEM.Solvers:
    compute_two_stage_lmps,
    SolverOptions,
    is_optimal,
    get_submarket_lmps,
    get_thermal_generation
using JuMP
using HiGHS
using Printf
using Dates

println("="^70)
println("OpenDESSEM Complete Workflow Example - Minimal 3-Bus System")
println("="^70)

# ============================================================================
# STEP 1: Create Electricity System
# ============================================================================

println("\n[STEP 1] Creating 3-Bus Electricity System...")

# Create 3 buses representing different regions
buses = Bus[
    Bus(;
        id = "BUS_1",
        name = "Bus 1 - North",
        voltage_kv = 230.0,
        base_kv = 230.0,
        latitude = -23.5,
        longitude = -46.6,
    ),
    Bus(;
        id = "BUS_2",
        name = "Bus 2 - Center",
        voltage_kv = 230.0,
        base_kv = 230.0,
        latitude = -22.9,
        longitude = -47.1,
    ),
    Bus(;
        id = "BUS_3",
        name = "Bus 3 - South",
        voltage_kv = 230.0,
        base_kv = 230.0,
        latitude = -22.5,
        longitude = -47.8,
    ),
]

# Create 3 submarkets (one per bus/region)
submarkets = Submarket[
    Submarket(; id = "SUB_1", code = "N", name = "North Region", country = "BR"),
    Submarket(; id = "SUB_2", code = "C", name = "Center Region", country = "BR"),
    Submarket(; id = "SUB_3", code = "S", name = "South Region", country = "BR"),
]

# Create 3 thermal plants with different cost characteristics
# Plant 1: Cheap coal baseload
# Plant 2: Medium-cost gas
# Plant 3: Expensive peaking gas
thermal_plants = ConventionalThermal[
    # Coal plant - cheap baseload (80 R$/MWh)
    ConventionalThermal(;
        id = "T_COAL_1",
        name = "Coal Plant 1",
        bus_id = "BUS_1",
        submarket_id = "N",
        fuel_type = COAL,
        capacity_mw = 500.0,
        min_generation_mw = 250.0,
        max_generation_mw = 500.0,
        ramp_up_mw_per_min = 5.0,
        ramp_down_mw_per_min = 5.0,
        min_up_time_hours = 8,
        min_down_time_hours = 4,
        fuel_cost_rsj_per_mwh = 80.0,
        startup_cost_rs = 50000.0,
        shutdown_cost_rs = 20000.0,
        commissioning_date = Dates.DateTime(2010, 6, 1, 0, 0, 0),
    ),
    # Gas plant - medium cost (120 R$/MWh)
    ConventionalThermal(;
        id = "T_GAS_1",
        name = "Gas Plant 1",
        bus_id = "BUS_2",
        submarket_id = "C",
        fuel_type = NATURAL_GAS,
        capacity_mw = 300.0,
        min_generation_mw = 100.0,
        max_generation_mw = 300.0,
        ramp_up_mw_per_min = 10.0,
        ramp_down_mw_per_min = 10.0,
        min_up_time_hours = 4,
        min_down_time_hours = 2,
        fuel_cost_rsj_per_mwh = 120.0,
        startup_cost_rs = 15000.0,
        shutdown_cost_rs = 5000.0,
        commissioning_date = Dates.DateTime(2010, 6, 1, 0, 0, 0),
    ),
    # Peaker plant - expensive (200 R$/MWh)
    ConventionalThermal(;
        id = "T_PEAK_1",
        name = "Peaker Plant 1",
        bus_id = "BUS_3",
        submarket_id = "S",
        fuel_type = NATURAL_GAS,
        capacity_mw = 200.0,
        min_generation_mw = 0.0,
        max_generation_mw = 200.0,
        ramp_up_mw_per_min = 20.0,
        ramp_down_mw_per_min = 20.0,
        min_up_time_hours = 1,
        min_down_time_hours = 0,
        fuel_cost_rsj_per_mwh = 200.0,
        startup_cost_rs = 5000.0,
        shutdown_cost_rs = 1000.0,
        commissioning_date = Dates.DateTime(2010, 6, 1, 0, 0, 0),
    ),
]

# Create 1 hydro plant for flexibility
hydro_plants = ReservoirHydro[ReservoirHydro(;
    id = "H_1",
    name = "Hydro Plant 1",
    bus_id = "BUS_2",
    submarket_id = "C",
    max_volume_hm3 = 5000.0,
    initial_volume_hm3 = 2500.0,
    min_volume_hm3 = 500.0,
    min_outflow_m3_per_s = 0.0,
    max_outflow_m3_per_s = 500.0,
    efficiency = 0.9,
    max_generation_mw = 200.0,
    min_generation_mw = 50.0,
    water_value_rs_per_hm3 = 50.0,
    subsystem_code = 1,
    initial_volume_percent = 50.0,
)]

# Create 3 loads with different demand patterns
# Time-varying demand over 24 hours
time_periods = 1:24
n_hours = length(time_periods)

# Create wind forecast (simplified: higher during day)
wind_forecast = vcat(
    fill(50.0, 6),   # Night: low wind
    fill(120.0, 12),  # Day: high wind
    fill(80.0, 6),     # Evening: medium wind
)

# Create 1 wind farm
wind_farms = WindPlant[WindPlant(;
    id = "W_1",
    name = "Wind Farm 1",
    bus_id = "BUS_3",
    submarket_id = "S",
    installed_capacity_mw = 150.0,
    capacity_forecast_mw = wind_forecast,
    forecast_type = DETERMINISTIC,
    min_generation_mw = 0.0,
    max_generation_mw = 150.0,
    ramp_up_mw_per_min = 10.0,
    ramp_down_mw_per_min = 10.0,
    curtailment_allowed = false,
    forced_outage_rate = 0.05,
    is_dispatchable = false,
    commissioning_date = DateTime(2020, 1, 1),
)]

# Base demand patterns (MW)
# North: steady industrial load
# Center: high daytime commercial load
# South: residential with evening peak
load_north = fill(300.0, n_hours)
load_center = vcat(fill(150.0, 6), fill(900.0, 12), fill(300.0, 6))  # Peak during day
load_south = vcat(fill(150.0, 12), fill(250.0, 6), fill(200.0, 6))  # Evening peak

loads = Load[
    Load(;
        id = "L_1",
        name = "North Load",
        bus_id = "BUS_1",
        submarket_id = "N",
        base_mw = 1.0,
        load_profile = load_north,
    ),
    Load(;
        id = "L_2",
        name = "Center Load",
        bus_id = "BUS_2",
        submarket_id = "C",
        base_mw = 1.0,
        load_profile = load_center,
    ),
    Load(;
        id = "L_3",
        name = "South Load",
        bus_id = "BUS_3",
        submarket_id = "S",
        base_mw = 1.0,
        load_profile = load_south,
    ),
]

# Create interconnections between regions
interconnections = Interconnection[
    Interconnection(;
        id = "IC_N_C",
        name = "North to Center",
        from_bus_id = "BUS_1",
        to_bus_id = "BUS_2",
        from_submarket_id = "N",
        to_submarket_id = "C",
        capacity_mw = 100.0,
        loss_percent = 1.0,
    ),
    Interconnection(;
        id = "IC_C_S",
        name = "Center to South",
        from_bus_id = "BUS_2",
        to_bus_id = "BUS_3",
        from_submarket_id = "C",
        to_submarket_id = "S",
        capacity_mw = 100.0,
        loss_percent = 1.0,
    ),
    Interconnection(;
        id = "IC_N_S",
        name = "North to South",
        from_bus_id = "BUS_1",
        to_bus_id = "BUS_3",
        from_submarket_id = "N",
        to_submarket_id = "S",
        capacity_mw = 500.0,
        loss_percent = 1.0,
    ),
]

# Create the electricity system
system = ElectricitySystem(;
    buses = buses,
    submarkets = submarkets,
    thermal_plants = thermal_plants,
    hydro_plants = hydro_plants,
    wind_farms = wind_farms,
    solar_farms = SolarPlant[],
    loads = loads,
    interconnections = interconnections,
    base_date = Dates.Date(2025, 1, 15),
)

println("✓ Created 3-bus system:")
println("  - $(length(system.buses)) buses")
println("  - $(length(system.thermal_plants)) thermal plants")
println("  - $(length(system.hydro_plants)) hydro plants")
println("  - $(length(system.wind_farms)) wind farms")
println("  - $(length(system.loads)) loads")
println("  - $(length(system.interconnections)) interconnections")
println("  - $(n_hours) time periods")

# ============================================================================
# STEP 2: Create JuMP Optimization Model
# ============================================================================

println("\n[STEP 2] Creating JuMP Optimization Model...")

model = Model()
println("✓ Created empty model")

# ============================================================================
# STEP 3: Create Optimization Variables
# ============================================================================

println("\n[STEP 3] Creating Optimization Variables...")

create_all_variables!(model, system, time_periods)

println("✓ Variables created")

# ============================================================================
# STEP 4: Build Constraints
# ============================================================================

println("\n[STEP 4] Building Constraints...")

# Thermal unit commitment constraints
thermal_uc_constraint = ThermalCommitmentConstraint(;
    metadata = ConstraintMetadata(;
        name = "Thermal Unit Commitment",
        description = "UC constraints for thermal plants",
        priority = 10,
    ),
    include_ramp_rates = false,
    include_min_up_down = false,
    initial_commitment = Dict("T_COAL_1" => true, "T_GAS_1" => true, "T_PEAK_1" => true),
)
build!(model, system, thermal_uc_constraint)

# Hydro water balance constraints
hydro_constraint = HydroWaterBalanceConstraint(;
    metadata = ConstraintMetadata(;
        name = "Hydro Water Balance",
        description = "Water balance for hydro plants",
        priority = 10,
    ),
)
build!(model, system, hydro_constraint)

# Renewable constraints
renewable_constraint = RenewableLimitConstraint(;
    metadata = ConstraintMetadata(;
        name = "Renewable Limits",
        description = "Wind/solar generation limits",
        priority = 10,
    ),
)
build!(model, system, renewable_constraint)

# Submarket energy balance constraints (for LMP calculation)
balance_constraint = SubmarketBalanceConstraint(;
    metadata = ConstraintMetadata(;
        name = "Submarket Energy Balance",
        description = "Energy balance for LMP calculation",
        priority = 10,
    ),
)
build!(model, system, balance_constraint)

println("✓ Constraints built")

# ============================================================================
# STEP 5: Build Objective Function
# ============================================================================

println("\n[STEP 5] Building Objective Function...")

# Define time-varying fuel costs (higher during peak hours)
fuel_costs = Dict{String,Vector{Float64}}()
fuel_costs["T_COAL_1"] = fill(80.0, n_hours)
fuel_costs["T_GAS_1"] = fill(120.0, n_hours)
fuel_costs["T_PEAK_1"] = vcat(fill(200.0, 12), fill(250.0, 12))  # Higher in evening

# Create objective with time-varying costs
objective = ProductionCostObjective(;
    metadata = ObjectiveMetadata(;
        name = "Production Cost Minimization",
        description = "Minimize total system operating cost",
    ),
    thermal_fuel_cost = true,
    thermal_startup_cost = true,
    thermal_shutdown_cost = true,
    hydro_water_value = true,
    time_varying_fuel_costs = fuel_costs,
)
build_objective!(model, system, objective)

println("✓ Objective built")

# ============================================================================
# STEP 6: Two-Stage Optimization (UC → SCED for LMPs)
# ============================================================================

println("\n[STEP 6] Solving with Two-Stage Pricing...")
println("  Stage 1: Unit Commitment (MIP)")
println("  Stage 2: SCED (LP) for LMPs")

solver_options = SolverOptions(;
    time_limit_seconds = 300.0,
    mip_gap = 0.01,
    threads = 1,
    verbose = false,
)

uc_result, sced_result =
    compute_two_stage_lmps(model, system, HiGHS.Optimizer; options = solver_options)

if sced_result !== nothing && is_optimal(sced_result)
    println("\n✓ Two-stage pricing completed!")
    println("  Stage 1 (UC) Objective: R\$ $(round(uc_result.objective_value, digits=2))")
    println(
        "  Stage 1 Solve Time: $(round(uc_result.solve_time_seconds, digits=2)) seconds",
    )
    println(
        "  Stage 2 (SCED) Objective: R\$ $(round(sced_result.objective_value, digits=2))",
    )
    println(
        "  Stage 2 Solve Time: $(round(sced_result.solve_time_seconds, digits=2)) seconds",
    )
else
    println("\n✗ Optimization failed")
    exit(1)
end

# ============================================================================
# STEP 7: Display Locational Marginal Prices (LMPs)
# ============================================================================

println("\n" * "="^70)
println("LOCATIONAL MARGINAL PRICES (LMP)")
println("="^70)
println("LMPs represent the marginal cost of supplying additional load at each bus.")
println("Different prices reflect transmission constraints and generation costs.")

for submarket in system.submarkets
    println("\n$(submarket.name) ($(submarket.code))")
    @printf("  Hour | LMP (R\$/MWh) |   Status\n")
    println("  " * "-"^40)

    lmps = get_submarket_lmps(sced_result, submarket.code, time_periods)

    # Show a few representative hours
    display_hours = [1, 7, 12, 18, 24]
    for t in display_hours
        lmp = lmps[t]
        status = if lmp > 150
            "HIGH"
        elseif lmp > 100
            "MEDIUM"
        elseif lmp > 50
            "LOW-MED"
        else
            "LOW"
        end
        @printf("  %4d | %11.2f | %8s\n", t, lmp, status)
    end
    println("  ...")

    avg_lmp = sum(lmps) / length(lmps)
    max_lmp = maximum(lmps)
    min_lmp = minimum(lmps)
    @printf("  Summary: Avg=%.1f | Max=%.1f | Min=%.1f\n\n", avg_lmp, max_lmp, min_lmp)
end

# ============================================================================
# STEP 8: Display Generation Schedule
# ============================================================================

println("\n" * "="^70)
println("THERMAL GENERATION SCHEDULE")
println("="^70)

for plant in system.thermal_plants
    println("\n$(plant.name) ($(plant.id))")
    println("  Fuel: $(plant.fuel_type) | Cost: $(plant.fuel_cost_rsj_per_mwh) R\$/MWh")

    gen = get_thermal_generation(uc_result, plant.id, time_periods)
    commit = get_thermal_generation(uc_result, plant.id, time_periods)  # Using same function for now

    avg_gen = sum(gen) / length(gen)
    max_gen = maximum(gen)
    min_gen = minimum(gen)

    @printf("  Avg: %.1f MW | Max: %.1f MW | Min: %.1f MW\n", avg_gen, max_gen, min_gen)

    # Show a few representative hours
    @printf("  Sample hours:\n")
    for t in [1, 12, 18, 24]
        @printf("    Hour %2d: %6.1f MW\n", t, gen[t])
    end
end

# ============================================================================
# STEP 9: Cost Breakdown
# ============================================================================

println("\n" * "="^70)
println("COST BREAKDOWN (24-hour total)")
println("="^70)

total_gen = sum(
    sum(get_thermal_generation(uc_result, p.id, time_periods)) for
    p in system.thermal_plants
)

# Calculate fuel cost using a let block to avoid soft scope issues
let fuel_cost_total = 0.0
    for plant in system.thermal_plants
        gen = get_thermal_generation(uc_result, plant.id, time_periods)
        for t in time_periods
            cost = get(fuel_costs, plant.id, fill(plant.fuel_cost_rsj_per_mwh, n_hours))[t]
            fuel_cost_total += gen[t] * cost
        end
    end

    @printf("  Total Generation: %.1f MWh\n", total_gen)
    @printf("  Total Fuel Cost: R\$ %.2f\n", fuel_cost_total)
    @printf("  Average Cost: R\$ %.2f/MWh\n", fuel_cost_total / total_gen)
end

# ============================================================================
# SUMMARY
# ============================================================================

println("\n" * "="^70)
println("SUMMARY")
println("="^70)

println("\nKey Results:")
println("  ✓ Successfully solved unit commitment problem")
println("  ✓ Calculated valid locational marginal prices (LMPs)")
println("  ✓ Used industry-standard two-stage approach (UC → SCED)")
println("\nLMP Insights:")
println("  - Price differences reflect marginal generation costs")
println("  - Transmission constraints may create price separation")
println("  - Renewable generation can reduce prices during availability")

println("\n" * "="^70)
println("End of Example")
println("="^70)
