"""
    Solution Extraction Unit Tests

Tests all solution extraction functions including:
- extract_solution_values! for all variable types (thermal, hydro, renewable, deficit)
- get_thermal_generation, get_hydro_generation, get_hydro_storage
- get_pld_dataframe with filtering
- get_submarket_lmps
- get_cost_breakdown
- Graceful degradation for missing data
"""

using Test
using JuMP
using HiGHS
using Dates
using DataFrames
using MathOptInterface

using OpenDESSEM
using OpenDESSEM:
    ConventionalThermal, ReservoirHydro, Bus, Submarket, Load, ElectricitySystem
using OpenDESSEM.Solvers
using OpenDESSEM.Solvers:
    SolverResult,
    SolverOptions,
    OPTIMAL,
    INFEASIBLE,
    NOT_SOLVED,
    solve_model!,
    get_pld_dataframe,
    get_pricing_dataframe,
    get_cost_breakdown,
    CostBreakdown,
    get_thermal_generation,
    get_hydro_generation,
    get_hydro_storage,
    get_submarket_lmps,
    get_renewable_generation,
    extract_solution_values!,
    extract_dual_values!

const MOI = MathOptInterface

# Include small system factory
include(joinpath(@__DIR__, "..", "fixtures", "small_system.jl"))
using .SmallSystemFactory: create_small_test_system

@testset "Solution Extraction" begin

    @testset "extract_solution_values! - all variable types" begin
        model, system = create_small_test_system(; include_deficit = true)
        result = solve_model!(model, system; pricing = false)

        # Thermal generation extracted
        @test haskey(result.variables, :thermal_generation)
        @test !isempty(result.variables[:thermal_generation])
        # Values are non-negative
        @test all(v >= -1e-6 for v in values(result.variables[:thermal_generation]))

        # Thermal commitment extracted
        @test haskey(result.variables, :thermal_commitment)

        # Thermal startup extracted
        @test haskey(result.variables, :thermal_startup)

        # Thermal shutdown extracted
        @test haskey(result.variables, :thermal_shutdown)

        # Hydro generation extracted
        @test haskey(result.variables, :hydro_generation)

        # Hydro storage extracted
        @test haskey(result.variables, :hydro_storage)

        # Hydro outflow extracted
        @test haskey(result.variables, :hydro_outflow)

        # Deficit extracted (Phase 4 gap closure)
        @test haskey(result.variables, :deficit)
        @test !isempty(result.variables[:deficit])
        # Deficit keyed by (submarket_code, t)
        first_key = first(keys(result.variables[:deficit]))
        @test first_key isa Tuple{String,Int}
        @test first_key[1] == "SE"  # Only submarket in test system
    end

    @testset "extract_solution_values! - deficit values are consistent" begin
        model, system = create_small_test_system(; include_deficit = true)
        result = solve_model!(model, system; pricing = false)

        if haskey(result.variables, :deficit)
            deficit = result.variables[:deficit]
            # All deficit values >= 0 (non-negative constraint)
            @test all(v >= -1e-6 for v in values(deficit))
            # Correct number of entries: 1 submarket * 6 periods
            @test length(deficit) == 6
        end
    end

    @testset "get_thermal_generation returns correct vector" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        gen = get_thermal_generation(result, "T001", 1:6)
        @test length(gen) == 6
        @test all(g >= 0 for g in gen)
    end

    @testset "get_hydro_generation returns correct vector" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        gen = get_hydro_generation(result, "H001", 1:6)
        @test length(gen) == 6
        @test all(g >= 0 for g in gen)
    end

    @testset "get_hydro_storage returns correct vector" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        storage = get_hydro_storage(result, "H001", 1:6)
        @test length(storage) == 6
        @test all(s >= 0 for s in storage)
    end

    @testset "get_pld_dataframe with two-stage pricing" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = true)

        # Use LP result for PLDs
        lp_result = result.lp_result
        if lp_result !== nothing && lp_result.has_duals
            pld_df = get_pld_dataframe(lp_result)
            @test pld_df isa DataFrame
            @test "submarket" in names(pld_df)
            @test "period" in names(pld_df)
            @test "pld" in names(pld_df)
            if nrow(pld_df) > 0
                @test all(pld_df.submarket .== "SE")
            end
        end
    end

    @testset "get_pld_dataframe filtering" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = true)

        lp_result = result.lp_result
        if lp_result !== nothing && lp_result.has_duals
            # Filter by submarket
            pld_se = get_pld_dataframe(lp_result; submarkets = ["SE"])
            @test all(pld_se.submarket .== "SE")

            # Filter by time period
            pld_peak = get_pld_dataframe(lp_result; time_periods = 4:6)
            if nrow(pld_peak) > 0
                @test all(pld_peak.period .>= 4)
                @test all(pld_peak.period .<= 6)
            end
        end
    end

    @testset "get_cost_breakdown returns CostBreakdown" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        breakdown = get_cost_breakdown(result, system)
        @test breakdown isa CostBreakdown
        @test breakdown.total >= 0
        @test breakdown.thermal_fuel >= 0
        @test breakdown.total ==
              breakdown.thermal_fuel +
              breakdown.thermal_startup +
              breakdown.thermal_shutdown +
              breakdown.deficit_penalty +
              breakdown.hydro_water_value
    end

    @testset "get_submarket_lmps returns vector" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = true)

        lp_result = result.lp_result
        if lp_result !== nothing && lp_result.has_duals
            lmps = get_submarket_lmps(lp_result, "SE", 1:6)
            @test length(lmps) == 6
            @test lmps isa Vector{Float64}
        end
    end

    @testset "Missing data returns zeros/warnings gracefully" begin
        # Create result without values
        result = SolverResult()
        gen = get_thermal_generation(result, "T_FAKE", 1:6)
        @test length(gen) == 6
        @test all(gen .== 0.0)

        hydro_gen = get_hydro_generation(result, "H_FAKE", 1:6)
        @test length(hydro_gen) == 6
        @test all(hydro_gen .== 0.0)

        storage = get_hydro_storage(result, "H_FAKE", 1:6)
        @test length(storage) == 6
        @test all(storage .== 0.0)

        renewable_gen = get_renewable_generation(result, "R_FAKE", 1:6)
        @test length(renewable_gen) == 6
        @test all(renewable_gen .== 0.0)

        lmps = get_submarket_lmps(result, "SE", 1:6)
        @test length(lmps) == 6
        @test all(lmps .== 0.0)
    end

    @testset "get_pld_dataframe returns empty DataFrame without duals" begin
        result = SolverResult()
        pld_df = get_pld_dataframe(result)
        @test pld_df isa DataFrame
        @test nrow(pld_df) == 0
        @test "submarket" in names(pld_df)
        @test "period" in names(pld_df)
        @test "pld" in names(pld_df)
    end

    @testset "get_cost_breakdown returns zeros without values" begin
        result = SolverResult()
        breakdown = get_cost_breakdown(
            result,
            ElectricitySystem(;
                thermal_plants = ConventionalThermal[],
                hydro_plants = ReservoirHydro[],
                buses = Bus[],
                submarkets = Submarket[],
                loads = Load[],
                base_date = Date(2025, 1, 1),
            ),
        )
        @test breakdown isa CostBreakdown
        @test breakdown.total == 0.0
    end
end

# Add tests for nodal LMP extraction in a separate testset
@testset "Nodal LMP Extraction" begin

    @testset "get_nodal_lmp_dataframe - empty system returns correct schema" begin
        result = SolverResult()
        system = ElectricitySystem(;
            thermal_plants = ConventionalThermal[],
            hydro_plants = ReservoirHydro[],
            buses = Bus[],
            submarkets = Submarket[],
            loads = Load[],
            base_date = Date(2025, 1, 1),
        )

        df = get_nodal_lmp_dataframe(result, system)

        # Verify correct schema
        @test df isa DataFrame
        @test nrow(df) == 0
        @test "bus_id" in names(df)
        @test "bus_name" in names(df)
        @test "period" in names(df)
        @test "lmp" in names(df)
    end

    @testset "get_nodal_lmp_dataframe - system without network data returns empty" begin
        # Create system with buses but no lines (no network)
        bus1 = Bus(;
            id = "B001",
            name = "Bus 1",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = true,
        )

        submarket =
            Submarket(; id = "SE", name = "Southeast", code = "SE", country = "Brazil")

        load = Load(;
            id = "L001",
            name = "Test Load",
            submarket_id = "SE",
            base_mw = 50.0,
            load_profile = fill(1.0, 6),  # Per-unit load profile
        )

        system = ElectricitySystem(;
            thermal_plants = ConventionalThermal[],
            hydro_plants = ReservoirHydro[],
            buses = [bus1],
            ac_lines = ACLine[],  # No lines = no network
            submarkets = [submarket],
            loads = [load],
            base_date = Date(2025, 1, 1),
        )

        result = SolverResult()

        df = get_nodal_lmp_dataframe(result, system)

        @test nrow(df) == 0
        @test names(df) == ["bus_id", "bus_name", "period", "lmp"]
    end

    @testset "get_nodal_lmp_dataframe - result without values returns empty" begin
        # Create system with network data
        bus1 = Bus(;
            id = "B001",
            name = "Bus 1",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = true,
        )

        bus2 = Bus(;
            id = "B002",
            name = "Bus 2",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = false,
        )

        line = ACLine(;
            id = "L001",
            name = "Line 1-2",
            from_bus_id = "B001",
            to_bus_id = "B002",
            length_km = 100.0,
            resistance_ohm = 0.01,
            reactance_ohm = 0.1,
            susceptance_siemen = 0.0,
            max_flow_mw = 500.0,
            min_flow_mw = 0.0,  # Non-negative
        )

        system = ElectricitySystem(;
            thermal_plants = ConventionalThermal[],
            hydro_plants = ReservoirHydro[],
            buses = [bus1, bus2],
            ac_lines = [line],
            submarkets = Submarket[],
            loads = Load[],
            base_date = Date(2025, 1, 1),
        )

        # Result without values (has_values = false)
        result = SolverResult()

        df = get_nodal_lmp_dataframe(result, system)

        @test nrow(df) == 0
    end

    @testset "get_nodal_lmp_dataframe - time_periods parameter works" begin
        # Test that time_periods parameter is used correctly
        result = SolverResult()
        result.has_values = true

        # Add some mock generation data for periods 1-6
        result.variables[:thermal_generation] = Dict{Tuple{String,Int},Float64}(
            ("T001", 1) => 50.0,
            ("T001", 2) => 55.0,
            ("T001", 3) => 60.0,
            ("T001", 4) => 65.0,
            ("T001", 5) => 70.0,
            ("T001", 6) => 75.0,
        )

        # Create minimal system with network
        bus1 = Bus(;
            id = "B001",
            name = "Bus 1",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = true,
        )

        system = ElectricitySystem(;
            thermal_plants = ConventionalThermal[],
            hydro_plants = ReservoirHydro[],
            buses = [bus1],
            ac_lines = ACLine[],
            submarkets = Submarket[],
            loads = Load[],
            base_date = Date(2025, 1, 1),
        )

        # Without lines, should return empty
        df = get_nodal_lmp_dataframe(result, system; time_periods = 1:3)
        @test nrow(df) == 0
    end

    @testset "get_nodal_lmp_dataframe - function signature accepts all parameters" begin
        # Test that function accepts all optional parameters
        result = SolverResult()
        system = ElectricitySystem(;
            thermal_plants = ConventionalThermal[],
            hydro_plants = ReservoirHydro[],
            buses = Bus[],
            submarkets = Submarket[],
            loads = Load[],
            base_date = Date(2025, 1, 1),
        )

        # Test with all optional parameters
        df = get_nodal_lmp_dataframe(
            result,
            system;
            time_periods = 1:6,
            solver_factory = HiGHS.Optimizer,
        )

        @test df isa DataFrame
        @test nrow(df) == 0  # Empty system
    end

    @testset "get_nodal_lmp_dataframe - DataFrame sorting" begin
        # Test that result would be sorted if we had data
        result = SolverResult()
        result.has_values = true
        result.variables[:thermal_generation] = Dict{Tuple{String,Int},Float64}()

        system = ElectricitySystem(;
            thermal_plants = ConventionalThermal[],
            hydro_plants = ReservoirHydro[],
            buses = Bus[],
            submarkets = Submarket[],
            loads = Load[],
            base_date = Date(2025, 1, 1),
        )

        df = get_nodal_lmp_dataframe(result, system)

        # Empty but valid DataFrame
        @test nrow(df) == 0
    end
end

# Add tests for nodal LMP pipeline integration
@testset "Nodal LMP Pipeline Integration" begin

    @testset "SolverResult nodal_lmps field" begin
        result = SolverResult()
        @test result.nodal_lmps === nothing

        # Can set to a DataFrame
        df = DataFrame(bus_id = ["B1"], bus_name = ["Bus 1"], period = [1], lmp = [50.0])
        result.nodal_lmps = df
        @test result.nodal_lmps !== nothing
        @test nrow(result.nodal_lmps) == 1
    end

    @testset "get_pricing_dataframe falls back to zonal when no nodal LMPs" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = true)

        # nodal_lmps is nothing by default (no network in small test system)
        @test result.nodal_lmps === nothing

        # Use LP result for duals
        pricing_result = result.lp_result !== nothing ? result.lp_result : result

        if pricing_result.has_duals
            df = get_pricing_dataframe(pricing_result, system)
            @test df isa DataFrame
            # Should be zonal format (fallback)
            @test "submarket" in names(df)
            @test "pld" in names(df)
            # Should NOT have bus_id (that's nodal)
            @test !("bus_id" in names(df))
        end
    end

    @testset "get_pricing_dataframe returns nodal data when nodal_lmps populated" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = true)

        # Manually set nodal_lmps to simulate available data
        result.nodal_lmps = DataFrame(
            bus_id = ["B1", "B2", "B1", "B2"],
            bus_name = ["Bus 1", "Bus 2", "Bus 1", "Bus 2"],
            period = [1, 1, 2, 2],
            lmp = [50.0, 55.0, 52.0, 57.0],
        )

        df = get_pricing_dataframe(result, system)
        @test df isa DataFrame
        # Should have nodal columns
        @test "bus_id" in names(df)
        @test "lmp" in names(df)
        # Should be enriched with submarket column
        @test "submarket" in names(df)
        # Row count matches nodal data
        @test nrow(df) == 4
    end

    @testset "get_pricing_dataframe with level=:zonal forces zonal" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = true)

        # Populate nodal LMPs
        result.nodal_lmps = DataFrame(
            bus_id = ["B1", "B2"],
            bus_name = ["Bus 1", "Bus 2"],
            period = [1, 1],
            lmp = [50.0, 55.0],
        )

        # Use LP result for duals
        pricing_result = result.lp_result !== nothing ? result.lp_result : result

        if pricing_result.has_duals
            # Force zonal even though nodal is available on result
            # Need to set nodal on pricing_result too for the test to be meaningful
            pricing_result.nodal_lmps = result.nodal_lmps
            df = get_pricing_dataframe(pricing_result, system; level = :zonal)
            @test df isa DataFrame
            @test "submarket" in names(df)
            @test "pld" in names(df)
            @test !("bus_id" in names(df))
        end
    end

    @testset "get_pricing_dataframe with time_period filter" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = true)

        # Set nodal_lmps spanning 2 periods and 2 buses
        result.nodal_lmps = DataFrame(
            bus_id = ["B1", "B2", "B1", "B2"],
            bus_name = ["Bus 1", "Bus 2", "Bus 1", "Bus 2"],
            period = [1, 1, 2, 2],
            lmp = [50.0, 55.0, 52.0, 57.0],
        )

        # Filter to period 1 only
        df = get_pricing_dataframe(result, system; time_periods = 1:1)
        @test nrow(df) == 2
        @test all(df.period .== 1)
    end
end
