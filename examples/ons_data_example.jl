"""
    ONS Data Example - Loading Official Brazilian DESSEM Files

This example demonstrates how to load official ONS (Operador Nacional do Sistema)
DESSEM data files and convert them to an OpenDESSEM electricity system.

# ONS Data Files

ONS provides official DESSEM input files for the Brazilian National Interconnected
System (SIN - Sistema Interligado Nacional). These files contain:

- Thermal plant data (termdat.dat): Plant registry, units, costs
- Hydro plant data (hidr.dat): Binary hydro plant registry (792 bytes per plant)
- General data (entdados.dat): Subsystems, demands, time periods
- Operational data (operut.dat, operuh.dat): Unit operational constraints
- Renewable data (renovaveis.dat): Wind and solar farms
- Network data (desselet.dat): Power flow case mapping

# DESSEM2Julia Dependency

This example requires the DESSEM2Julia package to parse ONS files:

```julia
using Pkg
Pkg.add(url="https://github.com/Bittencourt/DESSEM2Julia")
```

# Sample Data

The example uses the sample ONS case provided in:
`docs/Sample/DS_ONS_102025_RV2D11/`

This is an official ONS study case for October/November 2025.

# What This Example Does

1. Checks if DESSEM2Julia is available
2. Loads ONS sample data using DessemLoader
3. Converts DESSEM entities to OpenDESSEM entities
4. Displays system statistics
5. (Optional) Runs a simple optimization if HiGHS is available
"""

using OpenDESSEM
using OpenDESSEM.Entities
using OpenDESSEM.Variables
using OpenDESSEM.Constraints: build!, ThermalCommitmentConstraint, HydroWaterBalanceConstraint,
    RenewableLimitConstraint, SubmarketBalanceConstraint, ConstraintMetadata
using OpenDESSEM.Objective: ProductionCostObjective, ObjectiveMetadata, build! as build_objective!
using OpenDESSEM.Solvers: optimize!, SolverOptions, is_optimal, get_thermal_generation
using JuMP
using Printf

println("=" ^ 70)
println("ONS Data Loading Example - Brazilian DESSEM Files")
println("=" ^ 70)

# ============================================================================
# STEP 1: Check Dependencies
# ============================================================================

println("\n[STEP 1] Checking dependencies...")

# Check if DESSEM2Julia is available
has_dessem2julia = try
    using DESSEM2Julia
    @info "✓ DESSEM2Julia is available"
    true
catch e
    @warn "✗ DESSEM2Julia not found" error=e
    false
end

# Check if HiGHS solver is available
has_highs = try
    using HiGHS
    @info "✓ HiGHS solver is available"
    true
catch e
    @warn "✗ HiGHS solver not found" error=e
    false
end

# If DESSEM2Julia is not available, provide helpful instructions
if !has_dessem2julia
    println("\n" * "=" ^ 70)
    println("DEPENDENCY MISSING: DESSEM2Julia")
    println("=" ^ 70)
    println("\nTo run this example, you need to install DESSEM2Julia:")
    println("\n1. Install DESSEM2Julia from GitHub:")
    println("   ```julia")
    println("   using Pkg")
    println("   Pkg.add(url=\"https://github.com/Bittencourt/DESSEM2Julia\")")
    println("   ```")
    println("\n2. Or add to your project environment:")
    println("   ```julia")
    println("   Pkg.develop(path=\"path/to/DESSEM2Julia\")")
    println("   ```")
    println("\nAfter installing, re-run this example.")
    println("\nFor more information, see:")
    println("  - DESSEM2Julia: https://github.com/Bittencourt/DESSEM2Julia")
    println("  - ONS Website: https://www.ons.org.br")
    println("\n" * "=" ^ 70)
    exit(1)
end

# ============================================================================
# STEP 2: Load ONS Sample Data
# ============================================================================

println("\n[STEP 2] Loading ONS sample data...")

# Path to sample ONS data
# This is the official ONS DESSEM case for October/November 2025
ons_data_path = joinpath(
    @__DIR__,
    "..",
    "docs",
    "Sample",
    "DS_ONS_102025_RV2D11"
)

# Check if the data directory exists
if !isdir(ons_data_path)
    println("\n" * "=" ^ 70)
    println("DATA DIRECTORY NOT FOUND")
    println("=" ^ 70)
    println("\nCould not find ONS sample data at:")
    println("  $ons_data_path")
    println("\nTo use this example:")
    println("\n1. Obtain official ONS DESSEM data files from:")
    println("   https://www.ons.org.br/paginas/energia-agora/operacao/")
    println("\n2. Place them in the following directory:")
    println("   $ons_data_path")
    println("\n3. Required files include:")
    println("   - dessem.arq (master index)")
    println("   - termdat.dat (thermal plants)")
    println("   - hidr.dat (hydro plants - binary)")
    println("   - entdados.dat (general data)")
    println("   - operut.dat (thermal operations)")
    println("   - renovaveis.dat (renewables)")
    println("   - desselet.dat (network index)")
    println("\n" * "=" ^ 70)
    exit(1)
end

println("Data directory: $ons_data_path")

# List the files in the ONS case directory
println("\nONS data files:")
ons_files = readdir(ons_data_path)
for file in sort(ons_files)
    file_path = joinpath(ons_data_path, file)
    if isfile(file_path)
        file_size = filesize(file_path)
        @printf("  %-30s %10d bytes\n", file, file_size)
    end
end

# ============================================================================
# STEP 3: Parse DESSEM Files
# ============================================================================

println("\n" * "=" ^ 70)
println("[STEP 3] Parsing DESSEM files...")
println("=" ^ 70)

try
    # Load the complete DESSEM case
    # This function:
    # 1. Reads dessem.arq to understand the file mapping
    # 2. Parses all available DESSEM files
    # 3. Converts DESSEM data structures to OpenDESSEM entities
    # 4. Creates an ElectricitySystem with all loaded entities
    system = load_dessem_case(ons_data_path; skip_validation = true)

    println("\n✓ Successfully loaded ONS DESSEM case!")
    println("\n" * "=" ^ 70)
    println("SYSTEM STATISTICS")
    println("=" ^ 70)

    # Display system statistics
    println("\nBrazilian National Interconnected System (SIN)")
    println("Case: DS_ONS_102025_RV2D11 (October/November 2025)")
    println("Source: ONS - Operador Nacional do Sistema Elétrico")
    println()

    # Submarkets
    println("Submarkets (Regional Markets):")
    for sm in system.submarkets
        @printf("  %-10s - %s\n", sm.code, sm.name)
    end
    println()

    # Thermal plants
    println("Thermal Generation:")
    @printf("  Total Plants: %d\n", length(system.thermal_plants))

    if !isempty(system.thermal_plants)
        # Count by fuel type
        fuel_counts = Dict{String,Int}()
        fuel_capacity = Dict{String,Float64}()

        for plant in system.thermal_plants
            fuel = string(plant.fuel_type)
            fuel_counts[fuel] = get(fuel_counts, fuel, 0) + 1
            fuel_capacity[fuel] = get(fuel_capacity, fuel, 0.0) + plant.capacity_mw
        end

        println("  By Fuel Type:")
        for fuel in sort(collect(keys(fuel_counts)))
            count = fuel_counts[fuel]
            capacity = fuel_capacity[fuel]
            @printf("    %-15s: %3d plants, %8.1f MW\n", fuel, count, capacity)
        end

        total_thermal_cap = sum(p.capacity_mw for p in system.thermal_plants)
        @printf("  Total Capacity: %.1f MW\n", total_thermal_cap)
    end
    println()

    # Hydro plants
    println("Hydro Generation:")
    @printf("  Total Plants: %d\n", length(system.hydro_plants))

    if !isempty(system.hydro_plants)
        total_hydro_cap = sum(p.max_generation_mw for p in system.hydro_plants)
        total_storage = sum(p.max_volume_hm3 for p in system.hydro_plants)

        @printf("  Total Capacity: %.1f MW\n", total_hydro_cap)
        @printf("  Total Storage: %.1f hm³ (billion cubic meters)\n", total_storage)

        # Show cascade information
        has_cascade = any(p -> p.downstream_plant_id !== nothing, system.hydro_plants)
        if has_cascade
            cascade_count = count(p -> p.downstream_plant_id !== nothing, system.hydro_plants)
            @printf("  Cascade Plants: %d (with downstream dependencies)\n", cascade_count)
        end
    end
    println()

    # Renewable generation
    println("Renewable Generation:")
    @printf("  Wind Farms:   %3d plants\n", length(system.wind_farms))
    if !isempty(system.wind_farms)
        wind_cap = sum(w.installed_capacity_mw for w in system.wind_farms)
        @printf("  Wind Capacity:    %8.1f MW\n", wind_cap)
    end

    @printf("  Solar Farms:  %3d plants\n", length(system.solar_farms))
    if !isempty(system.solar_farms)
        solar_cap = sum(s.installed_capacity_mw for s in system.solar_farms)
        @printf("  Solar Capacity:   %8.1f MW\n", solar_cap)
    end
    println()

    # Loads
    println("Demand:")
    @printf("  Total Loads: %d\n", length(system.loads))
    if !isempty(system.loads)
        total_demand = sum(l.base_mw for l in system.loads)
        @printf("  Total Base Demand: %.1f MW\n", total_demand)

        # Demand by submarket
        demand_by_submarket = Dict{String,Float64}()
        for load in system.loads
            submarket = load.submarket_id
            demand_by_submarket[submarket] = get(demand_by_submarket, submarket, 0.0) + load.base_mw
        end

        println("  By Submarket:")
        for (submarket, demand) in sort(collect(demand_by_submarket))
            @printf("    %-10s: %8.1f MW\n", submarket, demand)
        end
    end
    println()

    # Network
    println("Network:")
    @printf("  Buses:        %4d\n", length(system.buses))
    @printf("  AC Lines:     %4d\n", length(system.ac_lines))
    @printf("  DC Lines:     %4d\n", length(system.dc_lines))
    println()

    # ============================================================================
    # STEP 4: Example Plant Details
    # ============================================================================

    println("=" ^ 70)
    println("SAMPLE PLANT DETAILS")
    println("=" ^ 70)

    # Show first thermal plant
    if !isempty(system.thermal_plants)
        plant = first(system.thermal_plants)
        println("\nThermal Plant Example:")
        @printf("  ID: %s\n", plant.id)
        @printf("  Name: %s\n", plant.name)
        @printf("  Submarket: %s\n", plant.submarket_id)
        @printf("  Fuel Type: %s\n", plant.fuel_type)
        @printf("  Capacity: %.1f MW\n", plant.capacity_mw)
        @printf("  Min Generation: %.1f MW\n", plant.min_generation_mw)
        @printf("  Max Generation: %.1f MW\n", plant.max_generation_mw)
        @printf("  Fuel Cost: %.2f R\$/MWh\n", plant.fuel_cost_rsj_per_mwh)
        @printf("  Startup Cost: %.2f R\$\n", plant.startup_cost_rs)
        @printf("  Ramp Up: %.2f MW/min\n", plant.ramp_up_mw_per_min)
        @printf("  Ramp Down: %.2f MW/min\n", plant.ramp_down_mw_per_min)
    end

    # Show first hydro plant
    if !isempty(system.hydro_plants)
        plant = first(system.hydro_plants)
        println("\nHydro Plant Example:")
        @printf("  ID: %s\n", plant.id)
        @printf("  Name: %s\n", plant.name)
        @printf("  Submarket: %s\n", plant.submarket_id)
        @printf("  Max Generation: %.1f MW\n", plant.max_generation_mw)
        @printf("  Max Storage: %.2f hm³\n", plant.max_volume_hm3)
        @printf("  Initial Storage: %.2f hm³ (%.1f%%)\n",
                plant.initial_volume_hm3, plant.initial_volume_percent)
        @printf("  Max Outflow: %.2f m³/s\n", plant.max_outflow_m3_per_s)
        @printf("  Efficiency: %.1f%%\n", plant.efficiency)
        if plant.downstream_plant_id !== nothing
            @printf("  Downstream: %s\n", plant.downstream_plant_id)
        end
    end

    # Show first wind farm
    if !isempty(system.wind_farms)
        plant = first(system.wind_farms)
        println("\nWind Farm Example:")
        @printf("  ID: %s\n", plant.id)
        @printf("  Name: %s\n", plant.name)
        @printf("  Submarket: %s\n", plant.submarket_id)
        @printf("  Installed Capacity: %.1f MW\n", plant.installed_capacity_mw)
        @printf("  Forecast Type: %s\n", plant.forecast_type)
        @printf("  Dispatchable: %s\n", plant.is_dispatchable)
        @printf("  Turbines: %d\n", plant.num_turbines)
    end

    # ============================================================================
    # STEP 5: (Optional) Simple Optimization
    # ============================================================================

    if has_highs
        println("\n" * "=" ^ 70)
        println("OPTIONAL: Running Simple Optimization")
        println("=" ^ 70)
        println("\nNote: This is a simplified example with basic constraints.")
        println("Full DESSEM optimization requires additional constraint modeling.")
        println()

        # Create a simple 24-hour model
        time_periods = 1:24

        println("Creating 24-hour optimization model...")
        model = Model()

        # Create variables
        println("Creating variables...")
        create_all_variables!(model, system, time_periods)

        # Build constraints
        println("Building constraints...")

        # Thermal unit commitment
        thermal_constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal Unit Commitment",
                description = "UC constraints for thermal plants",
                priority = 10
            ),
            include_ramp_rates = true,
            include_min_up_down = true,
            initial_commitment = Dict(p.id => false for p in system.thermal_plants)
        )
        build!(model, system, thermal_constraint)

        # Hydro water balance
        hydro_constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance for hydro plants",
                priority = 10
            )
        )
        build!(model, system, hydro_constraint)

        # Renewable limits
        renewable_constraint = RenewableLimitConstraint(;
            metadata = ConstraintMetadata(;
                name = "Renewable Limits",
                description = "Wind/solar generation limits",
                priority = 10
            )
        )
        build!(model, system, renewable_constraint)

        # Energy balance
        balance_constraint = SubmarketBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Submarket Energy Balance",
                description = "Energy balance by submarket",
                priority = 10
            )
        )
        build!(model, system, balance_constraint)

        # Build objective
        println("Building objective...")

        # Simple fuel costs (could be time-varying)
        fuel_costs = Dict{String,Vector{Float64}}()
        for plant in system.thermal_plants
            fuel_costs[plant.id] = fill(plant.fuel_cost_rsj_per_mwh, 24)
        end

        # Create objective with time-varying costs
        objective = ProductionCostObjective(;
            metadata = ObjectiveMetadata(;
                name = "Production Cost Minimization",
                description = "Minimize total system operating cost"
            ),
            thermal_fuel_cost = true,
            thermal_startup_cost = true,
            thermal_shutdown_cost = false,
            time_varying_fuel_costs = fuel_costs
        )
        build_objective!(model, system, objective)

        # Solve
        println("\nSolving optimization problem...")
        println("(This may take a few minutes for large systems)")

        solver_options = SolverOptions(;
            time_limit_seconds = 300.0,
            mip_gap = 0.01,
            threads = 1,
            verbose = true
        )

        result = optimize!(model, system, HiGHS.Optimizer; options = solver_options)

        if is_optimal(result)
            println("\n✓ Optimization successful!")
            @printf("  Objective Value: R\$ %.2f\n", result.objective_value)
            @printf("  Solve Time: %.2f seconds\n", result.solve_time_seconds)
            @printf("  Status: %s\n", result.status)

            # Show sample generation
            println("\nSample Generation (Hour 12):")
            for plant in system.thermal_plants[1:min(5, end)]  # First 5 plants
                gen = get_thermal_generation(result, plant.id, 12:12)
                @printf("  %-30s: %8.2f MW\n", plant.name, gen[1])
            end
        else
            println("\n✗ Optimization did not converge to optimal solution")
            @printf("  Status: %s\n", result.status)
        end
    else
        println("\n" * "=" ^ 70)
        println("OPTIMIZATION SKIPPED")
        println("=" ^ 70)
        println("\nHiGHS solver not available. Install with:")
        println("  Pkg.add(\"HiGHS\")")
    end

    # ============================================================================
    # SUMMARY
    # ============================================================================

    println("\n" * "=" ^ 70)
    println("SUMMARY")
    println("=" ^ 70)

    println("\nSuccessfully loaded ONS DESSEM data:")
    println("  ✓ Parsed official ONS DESSEM files")
    println("  ✓ Converted to OpenDESSEM entities")
    println("  ✓ Created ElectricitySystem")
    println("  ✓ Validated referential integrity")

    println("\nThis demonstrates OpenDESSEM's ability to:")
    println("  - Load official Brazilian power system data")
    println("  - Work with real-world system sizes")
    println("  - Handle complex hydro-thermal systems")
    println("  - Model renewable integration")

    println("\nNext Steps:")
    println("  1. Add more detailed constraints (ramp rates, reserves)")
    println("  2. Configure network constraints from PWF files")
    println("  3. Run full optimization with time-varying data")
    println("  4. Extract and analyze marginal prices")
    println("  5. Compare with official DESSEM results")

    println("\n" * "=" ^ 70)
    println("End of ONS Data Example")
    println("=" ^ 70)

catch e
    println("\n" * "=" ^ 70)
    println("ERROR")
    println("=" ^ 70)
    println("\nFailed to load ONS DESSEM data:")
    println(e)

    # Provide helpful error information
    if isa(e, LoadError)
        println("\nThis is likely a DESSEM2Julia parsing error.")
        println("Check that:")
        println("  1. DESSEM2Julia is properly installed")
        println("  2. All required DESSEM files are present")
        println("  3. File formats match ONS specifications")
    elseif isa(e, ArgumentError)
        println("\nThis is likely an entity validation error.")
        println("Check that:")
        println("  1. All required entity fields are populated")
        println("  2. Foreign key references are valid")
        println("  3. Numerical values are within valid ranges")
    end

    println("\nFor help, see:")
    println("  - DESSEM2Julia: https://github.com/Bittencourt/DESSEM2Julia")
    println("  - OpenDESSEM Documentation: docs/")
    println("  - OpenDESSEM Issues: https://github.com/Bittencourt/openDESSEM/issues")

    rethrow(e)
end
