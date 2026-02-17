"""
    ONS Data Example - Loading Official Brazilian DESSEM Files

This example demonstrates how to load official ONS (Operador Nacional do Sistema)
DESSEM data files and run a comprehensive optimization using the OpenDESSEM pipeline.

# ONS Data Files

ONS provides official DESSEM input files for the Brazilian National Interconnected
System (SIN - Sistema Interligado Nacional). These files contain:

- Thermal plant data (termdat.dat): Plant registry, units, costs
- Hydro plant data (hidr.dat): Binary hydro plant registry (792 bytes per plant)
- General data (entdados.dat): Subsystems, demands, time periods
- Operational data (operut.dat, operuh.dat): Unit operational constraints
- Renewable data (renovaveis.dat): Wind and solar farms
- Network data (desselet.dat): Power flow case mapping
- FCF curves (infofcf.dat): Future cost function for hydro water values

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
5. Runs comprehensive optimization with all constraint types
6. Extracts PLDs via two-stage pricing (UC → SCED)
7. Shows cost breakdown and exports results to CSV/JSON
"""

using OpenDESSEM
using OpenDESSEM.Entities
using OpenDESSEM.Variables
using OpenDESSEM.Constraints: build!, ThermalCommitmentConstraint, HydroWaterBalanceConstraint,
    HydroGenerationConstraint, RenewableLimitConstraint, SubmarketBalanceConstraint,
    ConstraintMetadata
using OpenDESSEM.Objective: ProductionCostObjective, ObjectiveMetadata, build! as build_objective!
using OpenDESSEM.Solvers: solve_model!, SolverOptions, is_optimal, get_thermal_generation,
    get_hydro_storage, get_pld_dataframe, get_cost_breakdown, CostBreakdown, SolverResult
using OpenDESSEM.Analysis: export_csv, export_json
using OpenDESSEM: load_fcf_curves, FCFCurveData, load_dessem_case
using OpenDESSEM.DessemLoader: load_inflow_data, InflowData
using JuMP
using Printf
using Dates
using DataFrames
using Statistics: mean, std

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
    # STEP 5: Comprehensive Optimization
    # ============================================================================

    if has_highs
        println("\n" * "=" ^ 70)
        println("COMPREHENSIVE OPTIMIZATION")
        println("=" ^ 70)
        println("\nRunning full OpenDESSEM optimization pipeline:")
        println("  - All constraint types with full options")
        println("  - Inter-submarket interconnections (SE<->S, SE<->NE, NE<->N)")
        println("  - FCF water values (if infofcf.dat available)")
        println("  - Two-stage pricing (UC -> SCED) for valid PLDs")
        println("  - Cost breakdown and CSV/JSON export")
        println()

        # --- 5a: Setup ---

        # Use 48 half-hour periods (simplified DESSEM horizon)
        time_periods = 1:48

        # Create Brazilian SIN interconnections with approximate transfer limits
        # These represent the main transmission corridors between submarkets
        sm_codes = Set(sm.code for sm in system.submarkets)
        bus_lookup = Dict(sm.code => "B_$(sm.code)_0001" for sm in system.submarkets)

        interconnections = Interconnection[]

        # SE <-> S (Southeast <-> South) - ~7000 MW capacity
        # SU is the ONS code for South
        se_code = "SE" in sm_codes ? "SE" : nothing
        s_code = "SU" in sm_codes ? "SU" : ("S" in sm_codes ? "S" : nothing)
        if se_code !== nothing && s_code !== nothing
            push!(interconnections, Interconnection(;
                id = "IC_SE_S",
                name = "Southeast - South",
                from_bus_id = bus_lookup[se_code],
                to_bus_id = bus_lookup[s_code],
                from_submarket_id = se_code,
                to_submarket_id = s_code,
                capacity_mw = 7000.0,
                loss_percent = 1.5
            ))
        end

        # SE <-> NE (Southeast <-> Northeast) - ~10000 MW capacity
        ne_code = "NE" in sm_codes ? "NE" : nothing
        if se_code !== nothing && ne_code !== nothing
            push!(interconnections, Interconnection(;
                id = "IC_SE_NE",
                name = "Southeast - Northeast",
                from_bus_id = bus_lookup[se_code],
                to_bus_id = bus_lookup[ne_code],
                from_submarket_id = se_code,
                to_submarket_id = ne_code,
                capacity_mw = 10000.0,
                loss_percent = 3.0
            ))
        end

        # NE <-> N (Northeast <-> North) - ~4000 MW capacity
        # NO is the ONS code for North
        n_code = "NO" in sm_codes ? "NO" : ("N" in sm_codes ? "N" : nothing)
        if ne_code !== nothing && n_code !== nothing
            push!(interconnections, Interconnection(;
                id = "IC_NE_N",
                name = "Northeast - North",
                from_bus_id = bus_lookup[ne_code],
                to_bus_id = bus_lookup[n_code],
                from_submarket_id = ne_code,
                to_submarket_id = n_code,
                capacity_mw = 4000.0,
                loss_percent = 4.0
            ))
        end

        @printf("  Created %d inter-submarket interconnections\n", length(interconnections))

        # Rebuild system with interconnections
        system = ElectricitySystem(;
            thermal_plants = system.thermal_plants,
            hydro_plants = system.hydro_plants,
            wind_farms = system.wind_farms,
            solar_farms = system.solar_farms,
            buses = system.buses,
            ac_lines = system.ac_lines,
            dc_lines = system.dc_lines,
            submarkets = system.submarkets,
            loads = system.loads,
            interconnections = interconnections,
            base_date = system.base_date,
            description = system.description,
            version = "1.0",
        )

        # Try to load FCF curves for water values
        fcf_data = try
            fcf = load_fcf_curves(ons_data_path)
            @info "Loaded FCF curves" num_plants=length(fcf.curves)
            fcf
        catch e
            @warn "Could not load FCF curves (infofcf.dat), using base water values" error=e
            nothing
        end

        # Try to load inflow data
        inflow_data = try
            inflows = load_inflow_data(ons_data_path)
            @info "Loaded inflow data" num_plants=length(inflows.plant_numbers) num_periods=inflows.num_periods
            inflows
        catch e
            @warn "Could not load inflow data (dadvaz.dat)" error=e
            nothing
        end

        # --- 5b: Create model and variables ---

        println("\nCreating 48-period optimization model...")
        model = Model()

        println("Creating variables...")
        create_all_variables!(model, system, time_periods)

        # --- 5c: Build constraints ---

        println("Building constraints...")

        # Thermal unit commitment (full options)
        println("  - Thermal unit commitment (ramp rates + min up/down)")
        thermal_constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal Unit Commitment",
                description = "Full UC constraints with ramp rates and min up/down time",
                priority = 10
            ),
            include_ramp_rates = true,
            include_min_up_down = true,
            initial_commitment = Dict(p.id => false for p in system.thermal_plants)
        )
        result_tc = build!(model, system, thermal_constraint)
        @printf("    Built %d constraints\n", result_tc.num_constraints)

        # Hydro water balance (with cascade and spill)
        println("  - Hydro water balance (cascade + spill)")
        hydro_wb_constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance with cascade topology and spill",
                priority = 10
            ),
            include_cascade = true,
            include_spill = true
        )
        result_hwb = build!(model, system, hydro_wb_constraint;
            inflow_data = inflow_data
        )
        @printf("    Built %d constraints\n", result_hwb.num_constraints)

        # Hydro generation function (linear model)
        println("  - Hydro generation function (linear)")
        hydro_gen_constraint = HydroGenerationConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Generation",
                description = "Linear generation function linking outflow to power",
                priority = 10
            ),
            model_type = "linear"
        )
        result_hg = build!(model, system, hydro_gen_constraint)
        @printf("    Built %d constraints\n", result_hg.num_constraints)

        # Renewable limits (with curtailment)
        println("  - Renewable limits (with curtailment)")
        renewable_constraint = RenewableLimitConstraint(;
            metadata = ConstraintMetadata(;
                name = "Renewable Limits",
                description = "Wind/solar generation limits with curtailment",
                priority = 10
            ),
            include_curtailment = true
        )
        result_rl = build!(model, system, renewable_constraint)
        @printf("    Built %d constraints\n", result_rl.num_constraints)

        # Submarket energy balance (with deficit + interconnections)
        println("  - Submarket balance (deficit + interconnections + renewables)")
        balance_constraint = SubmarketBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Submarket Energy Balance",
                description = "Balance with deficit slack and inter-submarket flows",
                priority = 10
            ),
            use_time_periods = time_periods,
            include_deficit = true,
            include_interconnections = true,
            include_renewables = true
        )
        result_sb = build!(model, system, balance_constraint)
        @printf("    Built %d constraints (%d flow variables)\n",
            result_sb.num_constraints, result_sb.num_variables)

        total_constraints = result_tc.num_constraints + result_hwb.num_constraints +
            result_hg.num_constraints + result_rl.num_constraints + result_sb.num_constraints
        @printf("  Total: %d constraints\n", total_constraints)

        # --- 5d: Build objective ---

        println("\nBuilding objective (all cost terms)...")

        # Time-varying fuel costs
        fuel_costs = Dict{String,Vector{Float64}}()
        for plant in system.thermal_plants
            fuel_costs[plant.id] = fill(plant.fuel_cost_rsj_per_mwh, length(time_periods))
        end

        # Brazilian regulatory VOLL = 5406.96 R$/MWh (2025 value)
        deficit_penalty_rsj = 5406.96

        objective = ProductionCostObjective(;
            metadata = ObjectiveMetadata(;
                name = "Production Cost Minimization",
                description = "Minimize total system operating cost"
            ),
            thermal_fuel_cost = true,
            thermal_startup_cost = true,
            thermal_shutdown_cost = true,
            hydro_water_value = true,
            deficit_cost = true,
            deficit_penalty = deficit_penalty_rsj,
            time_varying_fuel_costs = fuel_costs,
            fcf_data = fcf_data,
            use_terminal_water_value = (fcf_data !== nothing)
        )
        build_objective!(model, system, objective)

        # --- 5e: Solve with two-stage pricing ---

        println("\nSolving optimization problem...")
        println("  Stage 1: Unit Commitment (MIP)")
        println("  Stage 2: SCED (LP) for valid PLDs")
        println("  (This may take several minutes for large systems)")

        result = solve_model!(model, system;
            solver = HiGHS.Optimizer,
            time_limit = 300.0,
            mip_gap = 0.01,
            output_level = 1,
            pricing = true
        )

        # --- 5f: Display results ---

        println("\n" * "=" ^ 70)
        println("OPTIMIZATION RESULTS")
        println("=" ^ 70)

        @printf("\n  Status: %s\n", result.solve_status)
        @printf("  Solve Time: %.2f seconds\n", result.solve_time_seconds)

        if result.objective_value !== nothing
            # The objective is scaled by COST_SCALE (1e-6), so we reverse it
            obj_rs = result.objective_value / 1e-6
            @printf("  Objective Value: R\$ %.2f\n", obj_rs)
        end

        if result.has_values
            # Top 10 dispatched thermal plants
            println("\nTop 10 Dispatched Thermal Plants (total generation over horizon):")
            println("  " * "-"^60)

            plant_gen_totals = Tuple{String,String,Float64}[]
            for plant in system.thermal_plants
                gen = get_thermal_generation(result, plant.id, time_periods)
                total = sum(gen)
                if total > 0.1  # Only show plants that generated
                    push!(plant_gen_totals, (plant.id, plant.name, total))
                end
            end
            sort!(plant_gen_totals; by = x -> -x[3])

            for (i, (id, name, total)) in enumerate(plant_gen_totals[1:min(10, end)])
                @printf("  %2d. %-30s %10.1f MWh\n", i, name[1:min(30, end)], total)
            end

            if isempty(plant_gen_totals)
                println("  (No thermal plants dispatched)")
            end

            # Hydro storage trajectory for largest hydro plant
            if !isempty(system.hydro_plants)
                largest_hydro = argmax(p -> p.max_generation_mw, system.hydro_plants)
                storage = get_hydro_storage(result, largest_hydro.id, time_periods)

                println("\nHydro Storage Trajectory ($(largest_hydro.name)):")
                @printf("  Initial: %.1f hm³\n", largest_hydro.initial_volume_hm3)
                @printf("  Period 1:  %.1f hm³\n", storage[1])
                @printf("  Period 24: %.1f hm³\n", storage[min(24, end)])
                @printf("  Period 48: %.1f hm³\n", storage[end])
                @printf("  Range: [%.1f, %.1f] hm³\n", minimum(storage), maximum(storage))
            end

            # PLDs from SCED result
            println("\nPLD (Locational Marginal Prices) by Submarket:")
            println("  " * "-"^60)

            pld_source = result.lp_result !== nothing ? result.lp_result : result
            pld_df = get_pld_dataframe(pld_source)

            if !isempty(pld_df)
                for sm in system.submarkets
                    sm_df = filter(row -> row.submarket == sm.code, pld_df)
                    if !isempty(sm_df)
                        avg_pld = mean(sm_df.pld)
                        min_pld = minimum(sm_df.pld)
                        max_pld = maximum(sm_df.pld)
                        @printf("  %-4s: Avg=%.2f  Min=%.2f  Max=%.2f R\$/MWh\n",
                            sm.code, avg_pld, min_pld, max_pld)
                    end
                end
            else
                println("  (No PLD data available - SCED may not have converged)")
            end

            # ============================================================================
            # STEP 6: Optional Nodal Pricing with PWF Network (if PowerModels available)
            # ============================================================================

            println("\n" * "=" ^ 70)
            println("NODAL PRICING (OPTIONAL)")
            println("=" ^ 70)

            # Check if PowerModels is available
            has_powermodels = try
                eval(:(using PowerModels))
                @info "✓ PowerModels is available for nodal pricing"
                true
            catch e
                @info "PowerModels not found - skipping nodal pricing section"
                false
            end

            if has_powermodels && has_highs && result.has_values
                try
                    # Path to PWF network file (leve.pwf = light load case)
                    pwf_path = joinpath(ons_data_path, "leve.pwf")

                    if !isfile(pwf_path)
                        @warn "PWF file not found: $pwf_path"
                        println("  Skipping nodal pricing - no PWF network file")
                    else
                        println("\nLoading PWF network topology...")
                        println("  File: leve.pwf")

                        # Parse PWF file
                        pwf_network = OpenDESSEM.Integration.parse_pwf_file(pwf_path)
                        @printf("  Loaded: %d buses, %d branches\n",
                            length(pwf_network.buses), length(pwf_network.branches))

                        # Convert to OpenDESSEM entities
                        pwf_buses, pwf_lines = OpenDESSEM.Integration.pwf_to_entities(pwf_network)
                        @printf("  Converted: %d buses, %d AC lines\n",
                            length(pwf_buses), length(pwf_lines))

                        # Get generator dispatch from solved model (first period)
                        # Map to PowerModels generators at their buses
                        pm_gens = OpenDESSEM.Entities.ThermalPlant[]
                        for plant in system.thermal_plants[1:min(10, end)]  # Limit for demo
                            push!(pm_gens, plant)
                        end

                        # Convert to PowerModels format
                        # Use period 1 dispatch as snapshot
                        pm_data = OpenDESSEM.Integration.convert_to_powermodel(;
                            buses = pwf_buses,
                            lines = pwf_lines,
                            thermals = pm_gens,
                            base_mva = 100.0
                        )

                        # Validate conversion
                        if !OpenDESSEM.Integration.validate_powermodel_conversion(pm_data)
                            @warn "PowerModels validation failed"
                        else
                            println("\nSolving DC-OPF for nodal LMPs...")

                            # Solve DC-OPF and extract nodal LMPs
                            nodal_result = OpenDESSEM.Integration.solve_dc_opf_nodal_lmps(
                                pm_data, HiGHS.Optimizer)

                            if nodal_result["status"] == "OPTIMAL" ||
                               nodal_result["status"] == "LOCALLY_SOLVED"
                                nodal_lmps = nodal_result["nodal_lmps"]

                                println("\nNodal LMPs (sample buses):")
                                println("  " * "-"^60)

                                # Show top 10 buses by LMP
                                sorted_lmps = sort(collect(nodal_lmps); by = x -> x[2], rev = true)
                                for (i, (bus_id, lmp)) in enumerate(sorted_lmps[1:min(10, end)])
                                    # Find bus name if available
                                    bus_idx = parse(Int, bus_id)
                                    bus_name = bus_idx <= length(pwf_buses) ?
                                               pwf_buses[bus_idx].name : "Bus $bus_id"
                                    @printf("  %2d. %-30s %8.2f R\$/MWh\n", i, bus_name, lmp)
                                end

                                # Summary statistics
                                lmp_values = collect(values(nodal_lmps))
                                println("\nLMP Statistics:")
                                @printf("  Buses with LMP: %d\n", length(lmp_values))
                                @printf("  Average LMP:    %.2f R\$/MWh\n", mean(lmp_values))
                                @printf("  Min LMP:        %.2f R\$/MWh\n", minimum(lmp_values))
                                @printf("  Max LMP:        %.2f R\$/MWh\n", maximum(lmp_values))
                                @printf("  Std Dev:        %.2f R\$/MWh\n", std(lmp_values))

                                println("\nComparison with Submarket PLDs:")
                                println("  Nodal pricing shows congestion costs within submarkets")
                                println("  Submarket PLDs = uniform price per submarket")
                                println("  Nodal LMPs = location-specific prices including losses")
                            else
                                @warn "DC-OPF did not converge" status=nodal_result["status"]
                            end
                        end
                    end
                catch e
                    @warn "Nodal pricing section failed" error=e
                    println("  Continuing with example...")
                end
            elseif !has_powermodels
                println("\nPowerModels.jl not installed - skipping nodal pricing.")
                println("To enable nodal pricing:")
                println("  using Pkg")
                println("  Pkg.add(\"PowerModels\")")
            elseif !result.has_values
                println("\nNo feasible solution available - skipping nodal pricing.")
            end

            # Cost breakdown
            println("\nCost Breakdown:")
            println("  " * "-"^60)

            breakdown = get_cost_breakdown(result, system; time_periods = time_periods)
            @printf("  Thermal Fuel:     R\$ %12.2f\n", breakdown.thermal_fuel)
            @printf("  Thermal Startup:  R\$ %12.2f\n", breakdown.thermal_startup)
            @printf("  Thermal Shutdown: R\$ %12.2f\n", breakdown.thermal_shutdown)
            @printf("  Deficit Penalty:  R\$ %12.2f\n", breakdown.deficit_penalty)
            @printf("  Hydro Water Value:R\$ %12.2f\n", breakdown.hydro_water_value)
            println("  " * "-"^40)
            @printf("  TOTAL:            R\$ %12.2f\n", breakdown.total)

            # --- 5g: Export results ---

            println("\nExporting results...")
            export_dir = mktempdir()

            # Export to CSV
            csv_files = export_csv(result, joinpath(export_dir, "csv");
                time_periods = time_periods)
            @printf("  CSV files: %d files in %s\n", length(csv_files),
                joinpath(export_dir, "csv"))

            # Export to JSON
            json_path = joinpath(export_dir, "solution.json")
            export_json(result, json_path;
                time_periods = time_periods,
                scenario_id = "DS_ONS_102025_RV2D11")
            @printf("  JSON file: %s\n", json_path)

            println("\n  Export directory: $export_dir")
        else
            println("\n  Optimization did not produce a feasible solution.")
            @printf("  Status: %s\n", result.solve_status)
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

    if has_highs
        println("  ✓ Built all constraint types (thermal UC, hydro, renewable, balance)")
        println("  ✓ Added inter-submarket interconnections")
        println("  ✓ Solved with two-stage pricing (UC → SCED)")
        println("  ✓ Extracted PLDs and cost breakdown")
        println("  ✓ Exported results to CSV and JSON")
    end

    println("\nThis demonstrates OpenDESSEM's ability to:")
    println("  - Load official Brazilian power system data")
    println("  - Work with real-world system sizes")
    println("  - Handle complex hydro-thermal systems with cascades")
    println("  - Model inter-submarket interconnections with losses")
    println("  - Compute valid marginal prices via two-stage pricing")
    println("  - Export results for external analysis")

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
