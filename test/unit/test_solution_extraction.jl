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
using OpenDESSEM.Solvers
using OpenDESSEM.Solvers:
    SolverResult, SolverOptions,
    OPTIMAL, INFEASIBLE, NOT_SOLVED,
    solve_model!,
    get_pld_dataframe, get_cost_breakdown, CostBreakdown,
    get_thermal_generation, get_hydro_generation, get_hydro_storage,
    get_submarket_lmps, get_renewable_generation,
    extract_solution_values!, extract_dual_values!

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
              breakdown.thermal_fuel + breakdown.thermal_startup +
              breakdown.thermal_shutdown + breakdown.deficit_penalty +
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
        breakdown = get_cost_breakdown(result, ElectricitySystem(;
            thermal_plants = [],
            hydro_plants = [],
            buses = [],
            submarkets = [],
            loads = [],
            base_date = Date(2025, 1, 1),
        ))
        @test breakdown isa CostBreakdown
        @test breakdown.total == 0.0
    end
end
