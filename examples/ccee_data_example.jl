"""
    CCEE Data Example - Simplified DESSEM Case (No Network)

This example demonstrates OpenDESSEM on a simplified CCEE (Câmara de Comercialização
de Energia Elétrica) DESSEM case without network constraints.

# Case: DS_CCEE_102025_SEMREDE_RV1D04

This is a simplified DESSEM case used by CCEE for market clearing calculations:
- "SEMREDE" = No network constraints (zonal model only)
- 4 submarkets (SE/CO, S, NE, N)
- Hydro-thermal dispatch without power flow constraints
- FCF curves from DECOMP (cortdeco.rv1)

# Purpose

This case is useful for:
1. Faster testing and validation (smaller than full ONS case)
2. Verifying zonal PLD calculations without network effects
3. Market clearing validation against CCEE reference results
4. Testing hydro cascade and thermal UC in isolation

# Comparison with ONS Case

| Feature        | ONS Case        | CCEE Case       |
|----------------|-----------------|-----------------|
| Network        | Full AC/DC      | None (zonal)    |
| PWF Files      | Yes (leve.pwf)  | No              |
| Size           | Large (320 hydro)| Smaller        |
| Use Case       | Operations      | Market clearing |

"""

using OpenDESSEM
using OpenDESSEM.Entities
using OpenDESSEM.Variables
using OpenDESSEM.Constraints:
    build!,
    ThermalCommitmentConstraint,
    HydroWaterBalanceConstraint,
    HydroGenerationConstraint,
    RenewableLimitConstraint,
    SubmarketBalanceConstraint,
    ConstraintMetadata
using OpenDESSEM.Objective:
    ProductionCostObjective, ObjectiveMetadata, build! as build_objective!
using OpenDESSEM.Solvers:
    solve_model!,
    SolverOptions,
    is_optimal,
    get_thermal_generation,
    get_hydro_storage,
    get_pld_dataframe,
    get_cost_breakdown,
    CostBreakdown,
    SolverResult
using OpenDESSEM.Analysis: export_csv, export_json
using OpenDESSEM: load_fcf_curves, FCFCurveData, load_dessem_case
using OpenDESSEM.DessemLoader: load_inflow_data, InflowData
using JuMP
using Printf
using Dates
using DataFrames
using Statistics: mean, std

println("="^70)
println("CCEE Data Example - Simplified DESSEM (No Network)")
println("="^70)

# ============================================================================
# STEP 1: Check Dependencies
# ============================================================================

println("\n[STEP 1] Checking dependencies...")

has_dessem2julia = try
    using DESSEM2Julia
    @info "✓ DESSEM2Julia is available"
    true
catch e
    @warn "✗ DESSEM2Julia not found" error = e
    false
end

has_highs = try
    using HiGHS
    @info "✓ HiGHS solver is available"
    true
catch e
    @warn "✗ HiGHS solver not found" error = e
    false
end

if !has_dessem2julia
    println("\n" * "="^70)
    println("DEPENDENCY MISSING: DESSEM2Julia")
    println("="^70)
    println("\nInstall with: Pkg.add(url=\"https://github.com/Bittencourt/DESSEM2Julia\")")
    exit(1)
end

# ============================================================================
# STEP 2: Load CCEE Sample Data
# ============================================================================

println("\n[STEP 2] Loading CCEE sample data...")

ccee_data_path = joinpath(@__DIR__, "..", "docs", "Sample", "DS_CCEE_102025_SEMREDE_RV1D04")

if !isdir(ccee_data_path)
    println("\nERROR: CCEE data directory not found: $ccee_data_path")
    exit(1)
end

println("Data directory: $ccee_data_path")

println("\nCCEE data files:")
ccee_files = readdir(ccee_data_path)
for file in sort(ccee_files)
    file_path = joinpath(ccee_data_path, file)
    if isfile(file_path)
        file_size = filesize(file_path)
        @printf("  %-30s %10d bytes\n", file, file_size)
    end
end

# ============================================================================
# STEP 3: Parse DESSEM Files
# ============================================================================

println("\n" * "="^70)
println("[STEP 3] Parsing DESSEM files...")
println("="^70)

try
    system = load_dessem_case(ccee_data_path; skip_validation = true)

    println("\n✓ Successfully loaded CCEE DESSEM case!")
    println("\n" * "="^70)
    println("SYSTEM STATISTICS")
    println("="^70)

    println("\nCCEE Simplified Case (SEMREDE - No Network)")
    println("Case: DS_CCEE_102025_SEMREDE_RV1D04")
    println("Source: CCEE - Câmara de Comercialização de Energia Elétrica")
    println()

    println("Submarkets (Regional Markets):")
    for sm in system.submarkets
        @printf("  %-10s - %s\n", sm.code, sm.name)
    end
    println()

    println("Thermal Generation:")
    @printf("  Total Plants: %d\n", length(system.thermal_plants))
    if !isempty(system.thermal_plants)
        total_thermal_cap = sum(p.capacity_mw for p in system.thermal_plants)
        @printf("  Total Capacity: %.1f MW\n", total_thermal_cap)
    end
    println()

    println("Hydro Generation:")
    @printf("  Total Plants: %d\n", length(system.hydro_plants))
    if !isempty(system.hydro_plants)
        total_hydro_cap = sum(p.max_generation_mw for p in system.hydro_plants)
        total_storage = sum(p.max_volume_hm3 for p in system.hydro_plants)
        @printf("  Total Capacity: %.1f MW\n", total_hydro_cap)
        @printf("  Total Storage: %.1f hm³\n", total_storage)

        cascade_count = count(p -> p.downstream_plant_id !== nothing, system.hydro_plants)
        @printf("  Cascade Plants: %d\n", cascade_count)
    end
    println()

    println("Renewable Generation:")
    @printf("  Wind Farms:   %3d plants\n", length(system.wind_farms))
    @printf("  Solar Farms:  %3d plants\n", length(system.solar_farms))
    if !isempty(system.wind_farms)
        wind_cap = sum(w.installed_capacity_mw for w in system.wind_farms)
        @printf("  Wind Capacity: %.1f MW\n", wind_cap)
    end
    println()

    println("Demand:")
    @printf("  Total Loads: %d\n", length(system.loads))
    if !isempty(system.loads)
        total_demand = sum(l.base_mw for l in system.loads)
        @printf("  Total Base Demand: %.1f MW\n", total_demand)

        demand_by_submarket = Dict{String,Float64}()
        for load in system.loads
            submarket = load.submarket_id
            demand_by_submarket[submarket] =
                get(demand_by_submarket, submarket, 0.0) + load.base_mw
        end

        println("  By Submarket:")
        for (submarket, demand) in sort(collect(demand_by_submarket))
            @printf("    %-10s: %8.1f MW\n", submarket, demand)
        end
    end
    println()

    println("Network (SEMREDE case - no power flow):")
    @printf("  Buses:        %4d (zonal only)\n", length(system.buses))
    @printf("  AC Lines:     %4d\n", length(system.ac_lines))
    @printf("  DC Lines:     %4d\n", length(system.dc_lines))
    println()

    # ============================================================================
    # STEP 4: Optimization (if HiGHS available)
    # ============================================================================

    if has_highs
        println("\n" * "="^70)
        println("OPTIMIZATION (ZONAL MODEL - NO NETWORK)")
        println("="^70)

        println("\nRunning OpenDESSEM optimization pipeline:")
        println("  - Thermal unit commitment with ramp constraints")
        println("  - Hydro water balance with cascade topology")
        println("  - Renewable generation limits")
        println("  - Submarket energy balance with deficit slack")
        println("  - Two-stage pricing for PLD extraction")
        println()

        time_periods = 1:48

        sm_codes = Set(sm.code for sm in system.submarkets)
        bus_lookup = Dict(sm.code => "B_$(sm.code)_0001" for sm in system.submarkets)

        interconnections = Interconnection[]

        se_code = "SE" in sm_codes ? "SE" : nothing
        s_code = "SU" in sm_codes ? "SU" : ("S" in sm_codes ? "S" : nothing)
        ne_code = "NE" in sm_codes ? "NE" : nothing
        n_code = "NO" in sm_codes ? "NO" : ("N" in sm_codes ? "N" : nothing)

        if se_code !== nothing && s_code !== nothing
            push!(
                interconnections,
                Interconnection(;
                    id = "IC_SE_S",
                    name = "Southeast - South",
                    from_bus_id = bus_lookup[se_code],
                    to_bus_id = bus_lookup[s_code],
                    from_submarket_id = se_code,
                    to_submarket_id = s_code,
                    capacity_mw = 7000.0,
                    loss_percent = 1.5,
                ),
            )
        end

        if se_code !== nothing && ne_code !== nothing
            push!(
                interconnections,
                Interconnection(;
                    id = "IC_SE_NE",
                    name = "Southeast - Northeast",
                    from_bus_id = bus_lookup[se_code],
                    to_bus_id = bus_lookup[ne_code],
                    from_submarket_id = se_code,
                    to_submarket_id = ne_code,
                    capacity_mw = 10000.0,
                    loss_percent = 3.0,
                ),
            )
        end

        if ne_code !== nothing && n_code !== nothing
            push!(
                interconnections,
                Interconnection(;
                    id = "IC_NE_N",
                    name = "Northeast - North",
                    from_bus_id = bus_lookup[ne_code],
                    to_bus_id = bus_lookup[n_code],
                    from_submarket_id = ne_code,
                    to_submarket_id = n_code,
                    capacity_mw = 4000.0,
                    loss_percent = 4.0,
                ),
            )
        end

        @printf("  Created %d inter-submarket interconnections\n", length(interconnections))

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

        fcf_data = try
            fcf = load_fcf_curves(ccee_data_path)
            @info "Loaded FCF curves" num_plants = length(fcf.curves)
            fcf
        catch e
            @warn "Could not load FCF curves" error = e
            nothing
        end

        inflow_data = try
            inflows = load_inflow_data(ccee_data_path)
            @info "Loaded inflow data" num_plants = length(inflows.plant_numbers)
            inflows
        catch e
            @warn "Could not load inflow data" error = e
            nothing
        end

        println("\nCreating 48-period optimization model...")
        model = Model()

        println("Creating variables...")
        create_all_variables!(model, system, time_periods)

        println("Building constraints...")

        println("  - Thermal unit commitment")
        thermal_constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal Unit Commitment",
                description = "UC constraints with ramp rates",
                priority = 10,
            ),
            include_ramp_rates = true,
            include_min_up_down = true,
            initial_commitment = Dict(p.id => false for p in system.thermal_plants),
        )
        result_tc = build!(model, system, thermal_constraint)
        @printf("    Built %d constraints\n", result_tc.num_constraints)

        println("  - Hydro water balance")
        hydro_wb_constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance with cascade",
                priority = 10,
            ),
            include_cascade = true,
            include_spill = true,
        )
        result_hwb = build!(model, system, hydro_wb_constraint; inflow_data = inflow_data)
        @printf("    Built %d constraints\n", result_hwb.num_constraints)

        println("  - Hydro generation function")
        hydro_gen_constraint = HydroGenerationConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Generation",
                description = "Linear generation function",
                priority = 10,
            ),
            model_type = "linear",
        )
        result_hg = build!(model, system, hydro_gen_constraint)
        @printf("    Built %d constraints\n", result_hg.num_constraints)

        println("  - Renewable limits")
        renewable_constraint = RenewableLimitConstraint(;
            metadata = ConstraintMetadata(;
                name = "Renewable Limits",
                description = "Wind/solar generation limits",
                priority = 10,
            ),
            include_curtailment = true,
        )
        result_rl = build!(model, system, renewable_constraint)
        @printf("    Built %d constraints\n", result_rl.num_constraints)

        println("  - Submarket balance")
        balance_constraint = SubmarketBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Submarket Energy Balance",
                description = "Balance with deficit and interconnections",
                priority = 10,
            ),
            use_time_periods = time_periods,
            include_deficit = true,
            include_interconnections = true,
            include_renewables = true,
        )
        result_sb = build!(model, system, balance_constraint)
        @printf("    Built %d constraints\n", result_sb.num_constraints)

        total_constraints =
            result_tc.num_constraints +
            result_hwb.num_constraints +
            result_hg.num_constraints +
            result_rl.num_constraints +
            result_sb.num_constraints
        @printf("  Total: %d constraints\n", total_constraints)

        println("\nBuilding objective...")
        fuel_costs = Dict{String,Vector{Float64}}()
        for plant in system.thermal_plants
            fuel_costs[plant.id] = fill(plant.fuel_cost_rsj_per_mwh, length(time_periods))
        end

        deficit_penalty_rsj = 5406.96

        objective = ProductionCostObjective(;
            metadata = ObjectiveMetadata(;
                name = "Production Cost Minimization",
                description = "Minimize total system operating cost",
            ),
            thermal_fuel_cost = true,
            thermal_startup_cost = true,
            thermal_shutdown_cost = true,
            hydro_water_value = true,
            deficit_cost = true,
            deficit_penalty = deficit_penalty_rsj,
            time_varying_fuel_costs = fuel_costs,
            fcf_data = fcf_data,
            use_terminal_water_value = (fcf_data !== nothing),
        )
        build_objective!(model, system, objective)

        println("\nSolving optimization problem...")
        println("  (CCEE case is smaller than ONS - faster solve)")

        result = solve_model!(
            model,
            system;
            solver = HiGHS.Optimizer,
            time_limit = 300.0,
            mip_gap = 0.01,
            output_level = 1,
            pricing = true,
        )

        println("\n" * "="^70)
        println("OPTIMIZATION RESULTS")
        println("="^70)

        @printf("\n  Status: %s\n", result.solve_status)
        @printf("  Solve Time: %.2f seconds\n", result.solve_time_seconds)

        if result.objective_value !== nothing
            obj_rs = result.objective_value / 1e-6
            @printf("  Objective Value: R\$ %.2f\n", obj_rs)
        end

        if result.has_values
            println("\nTop 10 Dispatched Thermal Plants:")
            println("  " * "-"^60)

            plant_gen_totals = Tuple{String,String,Float64}[]
            for plant in system.thermal_plants
                gen = get_thermal_generation(result, plant.id, time_periods)
                total = sum(gen)
                if total > 0.1
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

            if !isempty(system.hydro_plants)
                largest_hydro = argmax(p -> p.max_generation_mw, system.hydro_plants)
                storage = get_hydro_storage(result, largest_hydro.id, time_periods)

                println("\nHydro Storage ($(largest_hydro.name)):")
                @printf("  Initial: %.1f hm³\n", largest_hydro.initial_volume_hm3)
                @printf("  Final:    %.1f hm³\n", storage[end])
            end

            println("\nPLD (Zonal Marginal Prices) by Submarket:")
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
                        @printf(
                            "  %-4s: Avg=%8.2f  Min=%8.2f  Max=%8.2f R\$/MWh\n",
                            sm.code,
                            avg_pld,
                            min_pld,
                            max_pld
                        )
                    end
                end
            else
                println("  (No PLD data available)")
            end

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

            println("\nExporting results...")
            export_dir = mktempdir()

            csv_files =
                export_csv(result, joinpath(export_dir, "csv"); time_periods = time_periods)
            @printf("  CSV files: %d files\n", length(csv_files))

            json_path = joinpath(export_dir, "solution.json")
            export_json(
                result,
                json_path;
                time_periods = time_periods,
                scenario_id = "DS_CCEE_102025_SEMREDE_RV1D04",
            )
            @printf("  JSON file: %s\n", json_path)

            println("\n  Export directory: $export_dir")
        else
            println("\n  Optimization did not produce a feasible solution.")
            @printf("  Status: %s\n", result.solve_status)
        end
    else
        println("\nHiGHS solver not available. Skipping optimization.")
    end

    # ============================================================================
    # SUMMARY
    # ============================================================================

    println("\n" * "="^70)
    println("SUMMARY")
    println("="^70)

    println("\nSuccessfully processed CCEE DESSEM case:")
    println("  ✓ Loaded SEMREDE case (no network constraints)")
    println("  ✓ Parsed thermal, hydro, and renewable data")
    println("  ✓ Created ElectricitySystem")

    if has_highs
        println("  ✓ Built zonal optimization model")
        println("  ✓ Solved with two-stage pricing")
        println("  ✓ Extracted zonal PLDs")
        println("  ✓ Exported results")
    end

    println("\nCCEE vs ONS Case Comparison:")
    println("  • CCEE: Simplified (no network), market clearing")
    println("  • ONS:  Full network (PWF files), operations planning")
    println("  • Both use same OpenDESSEM pipeline")

    println("\n" * "="^70)
    println("End of CCEE Data Example")
    println("="^70)

catch e
    println("\n" * "="^70)
    println("ERROR")
    println("="^70)
    println("\nFailed to process CCEE DESSEM case:")
    showerror(stdout, e, catch_backtrace())
    rethrow(e)
end
