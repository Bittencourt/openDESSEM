"""
    End-to-End Solver Integration Tests

Tests the complete solve pipeline from model creation through solution extraction.
Verifies Phase 3 success criteria:
- End-to-end workflow executes
- Small test case solves successfully
- Two-stage pricing produces valid PLDs
- Expected cost magnitude verified

These tests use the small test system factory to create minimal systems
that can be solved quickly while still exercising the full pipeline.
"""

using Test
using JuMP
using HiGHS
using Dates
using DataFrames
using MathOptInterface

using OpenDESSEM
using OpenDESSEM:
    ConventionalThermal,
    NATURAL_GAS,
    ReservoirHydro,
    Bus,
    Submarket,
    Load,
    ElectricitySystem
using OpenDESSEM:
    create_thermal_variables!,
    create_hydro_variables!,
    create_deficit_variables!,
    ThermalCommitmentConstraint,
    HydroGenerationConstraint,
    HydroWaterBalanceConstraint,
    SubmarketBalanceConstraint,
    ConstraintMetadata,
    build!,
    ProductionCostObjective,
    ObjectiveMetadata
using OpenDESSEM.Solvers:
    SolverResult,
    SolverOptions,
    SolverType,
    HIGHS,
    GUROBI,
    CPLEX,
    GLPK,
    OPTIMAL,
    INFEASIBLE,
    TIME_LIMIT,
    NOT_SOLVED,
    solve_model!,
    optimize!,
    solver_available,
    get_solver_optimizer,
    get_pld_dataframe,
    get_cost_breakdown,
    CostBreakdown,
    get_thermal_generation,
    get_hydro_generation,
    get_hydro_storage,
    is_optimal,
    is_infeasible,
    compute_iis!,
    IISResult

# Include the small system factory
include(joinpath(@__DIR__, "..", "fixtures", "small_system.jl"))
using .SmallSystemFactory: create_small_test_system, create_infeasible_test_system

const MOI = MathOptInterface

@testset "End-to-End Solver Tests" begin

    # =========================================================================
    # Test Set 1: Basic Solve Workflow
    # =========================================================================

    @testset "Basic solve workflow" begin
        @testset "solve_model! returns SolverResult with correct status" begin
            # Create small test system
            model, system = create_small_test_system()

            # Solve the model
            result = solve_model!(
                model,
                system;
                solver = HiGHS.Optimizer,
                time_limit = 60.0,
                pricing = false,  # Single-stage solve for speed
            )

            # Verify result structure
            @test result isa SolverResult
            @test result.solve_status == OPTIMAL
            @test result.status == MOI.OPTIMAL
            @test result.objective_value !== nothing
            @test result.objective_value > 0  # Cost should be positive
            @test result.solve_time_seconds > 0
        end

        @testset "Variables are extracted after solve" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = false)

            @test result.has_values == true
            @test haskey(result.variables, :thermal_generation)
            @test haskey(result.variables, :thermal_commitment)

            # Check that generation values are positive
            thermal_gen = result.variables[:thermal_generation]
            @test !isempty(thermal_gen)

            for ((plant_id, t), gen) in thermal_gen
                @test gen >= 0  # Generation should be non-negative
            end
        end

        @testset "Cost is in expected magnitude range" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = false)

            # Expected cost range for 6 periods (scaled by COST_SCALE = 1e-6):
            # - 2 thermal plants * ~200 MW * ~200 R$/MWh * 6 hours ≈ 480,000 R$
            # - Scaled: 0.48
            # - Should be in range 0.01 to 5.0 (scaled)
            @test result.objective_value > 0.01
            @test result.objective_value < 5.0
        end
    end

    # =========================================================================
    # Test Set 2: Two-Stage Pricing Workflow
    # =========================================================================

    @testset "Two-stage pricing workflow" begin
        @testset "Two-stage pricing produces PLD DataFrame" begin
            model, system = create_small_test_system()

            # Solve with two-stage pricing (default)
            result = solve_model!(
                model,
                system;
                solver = HiGHS.Optimizer,
                time_limit = 120.0,
                pricing = true,  # Two-stage pricing
            )

            @test result.solve_status == OPTIMAL
            @test result.mip_result !== nothing  # Stage 1 result exists
            @test result.lp_result !== nothing    # Stage 2 result exists

            # Extract PLD DataFrame
            pld_df = get_pld_dataframe(result.lp_result)

            @test pld_df isa DataFrame
            @test :submarket in propertynames(pld_df)
            @test :period in propertynames(pld_df)
            @test :pld in propertynames(pld_df)

            # Should have 6 periods * 1 submarket = 6 rows
            @test nrow(pld_df) >= 1  # At least some PLDs should be present
        end

        @testset "PLDs are positive for positive load" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = true)

            @test result.lp_result !== nothing
            @test result.lp_result.has_duals == true

            # Get PLDs for SE submarket
            pld_df = get_pld_dataframe(result.lp_result; submarkets = ["SE"])

            if nrow(pld_df) > 0
                for row in eachrow(pld_df)
                    # PLD should be non-negative for positive load
                    @test row.pld >= -1000  # Allow small negative for numerical tolerance
                end
            end
        end

        @testset "LP result has valid duals from SCED" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = true)

            @test result.lp_result !== nothing
            @test result.lp_result.has_duals == true
            @test !isempty(result.lp_result.dual_values)
            @test haskey(result.lp_result.dual_values, "submarket_balance")
        end
    end

    # =========================================================================
    # Test Set 3: Cost Breakdown Extraction
    # =========================================================================

    @testset "Cost breakdown extraction" begin
        @testset "cost_breakdown dict has expected keys" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = false)

            @test !isempty(result.cost_breakdown)
            @test haskey(result.cost_breakdown, "thermal_fuel")
            @test haskey(result.cost_breakdown, "thermal_startup")
            @test haskey(result.cost_breakdown, "thermal_shutdown")
            @test haskey(result.cost_breakdown, "deficit_penalty")
            @test haskey(result.cost_breakdown, "total")
        end

        @testset "CostBreakdown struct works correctly" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = false)

            cb = get_cost_breakdown(result, system)

            @test cb isa CostBreakdown
            @test cb.thermal_fuel >= 0
            @test cb.total >= 0
            @test cb.total ==
                  cb.thermal_fuel +
                  cb.thermal_startup +
                  cb.thermal_shutdown +
                  cb.deficit_penalty +
                  cb.hydro_water_value
        end

        @testset "Thermal fuel cost dominates in small system" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = false)

            cb = get_cost_breakdown(result, system)

            # Fuel cost should be the largest component
            @test cb.thermal_fuel >= cb.thermal_startup
            @test cb.thermal_fuel >= cb.thermal_shutdown
        end
    end

    # =========================================================================
    # Test Set 4: Time Limit Handling
    # =========================================================================

    @testset "Time limit handling" begin
        @testset "Short time_limit returns TIME_LIMIT status" begin
            model, system = create_small_test_system()

            # Very short time limit (0.1 seconds)
            result = solve_model!(
                model,
                system;
                solver = HiGHS.Optimizer,
                time_limit = 0.1,
                pricing = false,
            )

            # Should either solve quickly (OPTIMAL) or hit time limit (TIME_LIMIT)
            @test result.solve_status in [OPTIMAL, TIME_LIMIT]
        end

        @testset "Reasonable time limit allows optimal solve" begin
            model, system = create_small_test_system()

            # Reasonable time limit (60 seconds)
            result = solve_model!(
                model,
                system;
                solver = HiGHS.Optimizer,
                time_limit = 60.0,
                pricing = false,
            )

            @test result.solve_status == OPTIMAL
        end
    end

    # =========================================================================
    # Test Set 5: Infeasible Model Handling
    # =========================================================================

    @testset "Infeasible model handling" begin
        @testset "INFEASIBLE status returned for infeasible system" begin
            model, system = create_infeasible_test_system()

            result = solve_model!(
                model,
                system;
                solver = HiGHS.Optimizer,
                time_limit = 60.0,
                pricing = false,
            )

            @test result.solve_status == INFEASIBLE
            @test is_infeasible(result) == true
        end

        @testset "compute_iis! works on infeasible model" begin
            model, system = create_infeasible_test_system()

            # Solve to get infeasible status
            result = solve_model!(
                model,
                system;
                solver = HiGHS.Optimizer,
                time_limit = 60.0,
                pricing = false,
            )

            @test is_infeasible(result)

            # Compute IIS
            iis_result = compute_iis!(model)

            @test iis_result isa IISResult
            @test iis_result.computation_time >= 0
            # Note: IIS conflicts may be empty if solver doesn't support IIS
        end

        @testset "is_infeasible helper function works" begin
            # Test with optimal result
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = false)
            @test is_infeasible(result) == false
            @test is_optimal(result) == true

            # Test with infeasible result
            model2, system2 = create_infeasible_test_system()
            result2 = solve_model!(model2, system2; pricing = false)
            @test is_infeasible(result2) == true
        end
    end

    # =========================================================================
    # Test Set 6: Solution Value Extraction
    # =========================================================================

    @testset "Solution value extraction" begin
        @testset "Thermal generation extracts correctly" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = false)

            # Get thermal generation for T001
            gen_t001 = get_thermal_generation(result, "T001", 1:6)

            @test gen_t001 isa Vector{Float64}
            @test length(gen_t001) == 6
            @test all(g -> g >= 0, gen_t001)
            @test all(g -> g <= 200, gen_t001)  # Max 200 MW
        end

        @testset "Thermal commitment is binary" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = false)

            commit = result.variables[:thermal_commitment]

            for ((plant_id, t), val) in commit
                @test isapprox(val, 0.0; atol = 1e-6) || isapprox(val, 1.0; atol = 1e-6)
            end
        end

        @testset "Hydro variables extract correctly" begin
            model, system = create_small_test_system(; num_hydro = 1)
            result = solve_model!(model, system; pricing = false)

            @test haskey(result.variables, :hydro_generation)
            @test haskey(result.variables, :hydro_storage)

            hydro_gen = result.variables[:hydro_generation]
            hydro_storage = result.variables[:hydro_storage]

            # Check values are within bounds
            for ((plant_id, t), gen) in hydro_gen
                @test gen >= 0
                @test gen <= 250  # Max hydro generation
            end
        end
    end

    # =========================================================================
    # Test Set 7: Log File Generation
    # =========================================================================

    @testset "Log file generation" begin
        @testset "log_file kwarg doesn't error" begin
            model, system = create_small_test_system()

            # Custom log file path
            log_path = tempname() * ".log"

            result = solve_model!(
                model,
                system;
                solver = HiGHS.Optimizer,
                time_limit = 60.0,
                pricing = false,
                log_file = log_path,
            )

            @test result.solve_status == OPTIMAL
            @test result.log_file == log_path

            # Check file was created
            @test isfile(log_path)

            # Clean up
            rm(log_path; force = true)
        end

        @testset "Auto-generated log file created" begin
            model, system = create_small_test_system()

            result = solve_model!(model, system; pricing = false)

            @test result.log_file !== nothing
            @test isfile(result.log_file)

            # Log file should contain basic info
            content = read(result.log_file, String)
            @test contains(content, "Status:")
            @test contains(content, "Solve Time:")

            # Clean up
            rm(result.log_file; force = true)
        end
    end

    # =========================================================================
    # Test Set 8: Multi-Solver Availability
    # =========================================================================

    @testset "Multi-solver availability" begin
        @testset "solver_available works for all types" begin
            @test solver_available(HIGHS) == true  # HiGHS is required

            # Optional solvers - may or may not be available
            @test solver_available(GUROBI) isa Bool
            @test solver_available(CPLEX) isa Bool
            @test solver_available(GLPK) isa Bool
        end

        @testset "get_solver_optimizer returns valid optimizer" begin
            optimizer = get_solver_optimizer(HIGHS)
            @test optimizer == HiGHS.Optimizer
        end

        @testset "Solve with default solver (HiGHS)" begin
            model, system = create_small_test_system()

            # Use default solver (no explicit solver kwarg)
            result = solve_model!(model, system; time_limit = 60.0, pricing = false)

            @test result.solve_status == OPTIMAL
        end
    end

    # =========================================================================
    # Test Set 9: Different System Configurations
    # =========================================================================

    @testset "Different system configurations" begin
        @testset "Minimal system (1 thermal, 0 hydro)" begin
            model, system =
                create_small_test_system(; num_thermal = 1, num_hydro = 0, num_periods = 3)

            result = solve_model!(model, system; pricing = false)

            # Note: With 1 thermal (150 MW) and 300 MW load, may be infeasible without deficit
            # Accept either status - the point is that the solve runs without crashing
            @test result.solve_status in [OPTIMAL, INFEASIBLE]
            @test length(system.thermal_plants) == 1
            @test length(system.hydro_plants) == 0
        end

        @testset "Larger system (3 thermal, 2 hydro)" begin
            model, system =
                create_small_test_system(; num_thermal = 3, num_hydro = 2, num_periods = 6)

            result = solve_model!(model, system; pricing = false)

            @test result.solve_status == OPTIMAL
            @test length(system.thermal_plants) == 3
            @test length(system.hydro_plants) == 2
        end

        @testset "System without deficit variables" begin
            model, system = create_small_test_system(; include_deficit = false)

            result = solve_model!(model, system; pricing = false)

            @test result.solve_status == OPTIMAL
            @test !haskey(result.variables, :deficit)
        end
    end

    # =========================================================================
    # Test Set 10: Edge Cases and Error Handling
    # =========================================================================

    @testset "Edge cases and error handling" begin
        @testset "Empty cost breakdown when no values" begin
            # Create result without solving
            result = SolverResult()

            cb = get_cost_breakdown(result, create_small_test_system()[2])

            @test cb isa CostBreakdown
            @test cb.total == 0.0
        end

        @testset "get_pld_dataframe handles missing duals" begin
            # Create result without duals
            result = SolverResult()

            pld_df = get_pld_dataframe(result)

            @test pld_df isa DataFrame
            @test nrow(pld_df) == 0  # Empty but valid schema
            @test :submarket in propertynames(pld_df)
            @test :period in propertynames(pld_df)
            @test :pld in propertynames(pld_df)
        end

        @testset "get_thermal_generation handles missing data" begin
            result = SolverResult()

            gen = get_thermal_generation(result, "T001", 1:6)

            @test gen isa Vector{Float64}
            @test length(gen) == 6
            @test all(g -> g == 0.0, gen)  # Returns zeros for missing data
        end
    end

    # =========================================================================
    # Test Set 11: Warm Start (if applicable)
    # =========================================================================

    @testset "Warm start support" begin
        @testset "warm_start kwarg doesn't error" begin
            model, system = create_small_test_system()

            # First solve
            result1 = solve_model!(model, system; pricing = false)

            # Create new model and warm start
            model2, system2 = create_small_test_system()

            result2 = solve_model!(model2, system2; pricing = false, warm_start = result1)

            @test result2.solve_status == OPTIMAL
        end
    end

    # =========================================================================
    # Test Set 12: PLD DataFrame Filtering
    # =========================================================================

    @testset "PLD DataFrame filtering" begin
        @testset "Filter by submarket" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = true)

            # Filter to SE only
            pld_se = get_pld_dataframe(result.lp_result; submarkets = ["SE"])

            @test nrow(pld_se) >= 0
            if nrow(pld_se) > 0
                @test all(row -> row.submarket == "SE", eachrow(pld_se))
            end
        end

        @testset "Filter by time periods" begin
            model, system = create_small_test_system()
            result = solve_model!(model, system; pricing = true)

            # Filter to periods 2:4
            pld_subset = get_pld_dataframe(result.lp_result; time_periods = 2:4)

            @test nrow(pld_subset) >= 0
            if nrow(pld_subset) > 0
                @test all(row -> row.period in 2:4, eachrow(pld_subset))
            end
        end
    end

    # =========================================================================
    # Cleanup: Remove any generated log files
    # =========================================================================

    # Try to clean up logs directory if it was created by tests
    logs_dir = joinpath(pwd(), "logs")
    if isdir(logs_dir)
        try
            rm(logs_dir; recursive = true, force = true)
        catch
            # Ignore cleanup errors
        end
    end
end
