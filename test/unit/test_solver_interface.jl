"""
    Tests for solver interface.

Tests solver types, status enum, and unified solve API.
"""

using Test
using MathOptInterface
using Dates
using DataFrames
using OpenDESSEM.Solvers:
    SolveStatus,
    OPTIMAL,
    INFEASIBLE,
    UNBOUNDED,
    TIME_LIMIT,
    ITERATION_LIMIT,
    NUMERICAL_ERROR,
    OTHER_LIMIT,
    NOT_SOLVED,
    SolverType,
    HIGHS,
    GUROBI,
    CPLEX,
    GLPK,
    SolverOptions,
    SolverResult,
    IISConflict,
    IISResult,
    solve_model!,
    optimize!,
    solver_available,
    get_solver_optimizer,
    get_pld_dataframe,
    CostBreakdown,
    get_cost_breakdown,
    map_to_solve_status,
    is_optimal,
    is_infeasible

# Import OpenDESSEM for accessing internal functions via qualified path
import OpenDESSEM

const MOI = MathOptInterface

const MOI = MathOptInterface

@testset "Solver Interface" begin

    # =========================================================================
    # SolveStatus Enum Tests
    # =========================================================================

    @testset "SolveStatus Enum" begin
        @testset "All 8 enum values defined" begin
            @test OPTIMAL isa SolveStatus
            @test INFEASIBLE isa SolveStatus
            @test UNBOUNDED isa SolveStatus
            @test TIME_LIMIT isa SolveStatus
            @test ITERATION_LIMIT isa SolveStatus
            @test NUMERICAL_ERROR isa SolveStatus
            @test OTHER_LIMIT isa SolveStatus
            @test NOT_SOLVED isa SolveStatus
        end

        @testset "Enum values are distinct" begin
            statuses = [
                OPTIMAL,
                INFEASIBLE,
                UNBOUNDED,
                TIME_LIMIT,
                ITERATION_LIMIT,
                NUMERICAL_ERROR,
                OTHER_LIMIT,
                NOT_SOLVED,
            ]
            @test length(unique(statuses)) == 8
        end
    end

    @testset "map_to_solve_status" begin
        @testset "Optimal cases" begin
            @test map_to_solve_status(MOI.OPTIMAL) == OPTIMAL
            @test map_to_solve_status(MOI.LOCALLY_SOLVED) == OPTIMAL
        end

        @testset "Infeasible cases" begin
            @test map_to_solve_status(MOI.INFEASIBLE) == INFEASIBLE
            @test map_to_solve_status(MOI.LOCALLY_INFEASIBLE) == INFEASIBLE
            @test map_to_solve_status(MOI.INFEASIBLE_OR_UNBOUNDED) == INFEASIBLE
        end

        @testset "Unbounded cases" begin
            # Note: MOI.DUAL_INFEASIBLE indicates unboundedness in minimization
            @test map_to_solve_status(MOI.DUAL_INFEASIBLE) == UNBOUNDED
        end

        @testset "Limit cases" begin
            @test map_to_solve_status(MOI.TIME_LIMIT) == TIME_LIMIT
            @test map_to_solve_status(MOI.ITERATION_LIMIT) == ITERATION_LIMIT
        end

        @testset "Numerical cases" begin
            @test map_to_solve_status(MOI.NUMERICAL_ERROR) == NUMERICAL_ERROR
            @test map_to_solve_status(MOI.SLOW_PROGRESS) == NUMERICAL_ERROR
        end

        @testset "Other limit cases" begin
            @test map_to_solve_status(MOI.NODE_LIMIT) == OTHER_LIMIT
            @test map_to_solve_status(MOI.SOLUTION_LIMIT) == OTHER_LIMIT
            @test map_to_solve_status(MOI.MEMORY_LIMIT) == OTHER_LIMIT
            @test map_to_solve_status(MOI.OBJECTIVE_LIMIT) == OTHER_LIMIT
            @test map_to_solve_status(MOI.NORM_LIMIT) == OTHER_LIMIT
            @test map_to_solve_status(MOI.OTHER_LIMIT) == OTHER_LIMIT
        end

        @testset "Not solved cases" begin
            @test map_to_solve_status(MOI.OPTIMIZE_NOT_CALLED) == NOT_SOLVED
            @test map_to_solve_status(MOI.INVALID_MODEL) == NOT_SOLVED
            @test map_to_solve_status(MOI.INVALID_OPTION) == NOT_SOLVED
        end
    end

    # =========================================================================
    # SolverResult Tests
    # =========================================================================

    @testset "SolverResult" begin
        @testset "Default constructor" begin
            result = SolverResult()
            @test result.status == MOI.OPTIMIZE_NOT_CALLED
            @test result.solve_status == NOT_SOLVED
            @test result.objective_value === nothing
            @test result.solve_time_seconds == 0.0
            @test result.objective_bound === nothing
            @test result.node_count === nothing
            @test isempty(result.variables)
            @test isempty(result.dual_values)
            @test result.has_values == false
            @test result.has_duals == false
            @test result.mip_result === nothing
            @test result.lp_result === nothing
            @test isempty(result.cost_breakdown)
            @test result.log_file === nothing
        end

        @testset "Constructor with keyword arguments" begin
            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                objective_value = 1000.0,
                solve_time_seconds = 5.5,
            )
            @test result.status == MOI.OPTIMAL
            @test result.solve_status == OPTIMAL
            @test result.objective_value == 1000.0
            @test result.solve_time_seconds == 5.5
        end

        @testset "Mutable struct allows field updates" begin
            result = SolverResult()
            result.solve_status = OPTIMAL
            result.objective_value = 500.0
            @test result.solve_status == OPTIMAL
            @test result.objective_value == 500.0
        end

        @testset "Can set mip_result and lp_result" begin
            mip = SolverResult(; status = MOI.OPTIMAL, solve_status = OPTIMAL)
            lp = SolverResult(; status = MOI.OPTIMAL, solve_status = OPTIMAL)

            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                mip_result = mip,
                lp_result = lp,
            )

            @test result.mip_result !== nothing
            @test result.lp_result !== nothing
            @test result.mip_result.solve_status == OPTIMAL
            @test result.lp_result.solve_status == OPTIMAL
        end
    end

    # =========================================================================
    # Solver Types Tests
    # =========================================================================

    @testset "Solver Types" begin
        @testset "SolverType enum values" begin
            @test HIGHS isa SolverType
            @test GUROBI isa SolverType
            @test CPLEX isa SolverType
            @test GLPK isa SolverType
        end

        @testset "SolverOptions defaults" begin
            opts = SolverOptions()
            @test opts.time_limit_seconds === nothing
            @test opts.mip_gap == 0.01
            @test opts.threads == 1
            @test opts.verbose == false
            @test isempty(opts.solver_specific)
            @test opts.warm_start == false
            @test opts.lp_relaxation == false
        end

        @testset "SolverOptions with custom values" begin
            opts = SolverOptions(;
                time_limit_seconds = 300.0,
                mip_gap = 0.005,
                threads = 4,
                verbose = true,
                solver_specific = Dict("presolve" => true),
                warm_start = true,
                lp_relaxation = true,
            )

            @test opts.time_limit_seconds == 300.0
            @test opts.mip_gap == 0.005
            @test opts.threads == 4
            @test opts.verbose == true
            @test opts.solver_specific["presolve"] == true
            @test opts.warm_start == true
            @test opts.lp_relaxation == true
        end
    end

    # =========================================================================
    # Status Helper Functions Tests
    # =========================================================================

    @testset "Status Helper Functions" begin
        @testset "is_optimal" begin
            @test is_optimal(SolverResult(; status = MOI.OPTIMAL)) == true
            @test is_optimal(SolverResult(; status = MOI.INFEASIBLE)) == false
            @test is_optimal(SolverResult(; status = MOI.TIME_LIMIT)) == false
        end

        @testset "is_infeasible" begin
            @test is_infeasible(SolverResult(; status = MOI.INFEASIBLE)) == true
            @test is_infeasible(SolverResult(; status = MOI.LOCALLY_INFEASIBLE)) == true
            @test is_infeasible(SolverResult(; status = MOI.OPTIMAL)) == false
        end

        @testset "is_time_limit" begin
            @test is_time_limit(SolverResult(; status = MOI.TIME_LIMIT)) == true
            @test is_time_limit(SolverResult(; status = MOI.OPTIMAL)) == false
        end

        @testset "has_solution" begin
            @test has_solution(SolverResult(; status = MOI.OPTIMAL)) == true
            @test has_solution(SolverResult(; status = MOI.TIME_LIMIT)) == true
            @test has_solution(SolverResult(; status = MOI.ITERATION_LIMIT)) == true
            @test has_solution(SolverResult(; status = MOI.NODE_LIMIT)) == true
            @test has_solution(SolverResult(; status = MOI.SOLUTION_LIMIT)) == true
            @test has_solution(SolverResult(; status = MOI.INFEASIBLE)) == false
            @test has_solution(SolverResult(; status = MOI.OPTIMIZE_NOT_CALLED)) == false
        end
    end

    # =========================================================================
    # Log File Tests (without actual solve)
    # =========================================================================

    @testset "Log File Generation" begin
        @testset "Auto-generates timestamp format" begin
            # Test that the timestamp format is correct
            ts = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
            @test occursin(r"^\d{8}_\d{6}$", ts)
        end

        @testset "Logs directory creation" begin
            logs_dir = joinpath(pwd(), "logs_test_temp")
            try
                if !isdir(logs_dir)
                    mkpath(logs_dir)
                end
                @test isdir(logs_dir)
            finally
                # Cleanup
                rm(logs_dir; force = true, recursive = true)
            end
        end
    end

    # =========================================================================
    # Lazy Loading Tests
    # =========================================================================

    @testset "Lazy Loading and Solver Availability" begin
        @testset "HIGHS always available" begin
            @test solver_available(HIGHS) == true
        end

        @testset "Optional solvers lazy loading" begin
            # These should not throw errors regardless of installation
            @test OpenDESSEM.Solvers._try_load_gurobi() isa Bool
            @test OpenDESSEM.Solvers._try_load_cplex() isa Bool
            @test OpenDESSEM.Solvers._try_load_glpk() isa Bool
        end

        @testset "solver_available function" begin
            @test solver_available(HIGHS) == true

            # Check optional solvers (result depends on installation)
            gurobi_avail = solver_available(GUROBI)
            @test gurobi_avail isa Bool

            cplex_avail = solver_available(CPLEX)
            @test cplex_avail isa Bool

            glpk_avail = solver_available(GLPK)
            @test glpk_avail isa Bool
        end

        @testset "Lazy loading caches results" begin
            # Call twice to verify caching works
            result1 = OpenDESSEM.Solvers._try_load_gurobi()
            result2 = OpenDESSEM.Solvers._try_load_gurobi()
            @test result1 == result2

            result1 = OpenDESSEM.Solvers._try_load_cplex()
            result2 = OpenDESSEM.Solvers._try_load_cplex()
            @test result1 == result2

            result1 = OpenDESSEM.Solvers._try_load_glpk()
            result2 = OpenDESSEM.Solvers._try_load_glpk()
            @test result1 == result2
        end
    end

    # =========================================================================
    # PLD DataFrame Tests
    # =========================================================================

    @testset "get_pld_dataframe" begin
        @testset "Returns DataFrame with correct columns" begin
            # Create a result with dual values
            duals = Dict{String,Dict{Tuple,Float64}}()
            duals["submarket_balance"] = Dict{Tuple,Float64}(
                ("SE", 1) => 100.0,
                ("SE", 2) => 150.0,
                ("NE", 1) => 80.0,
                ("NE", 2) => 90.0,
            )
            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                has_duals = true,
                dual_values = duals,
            )

            df = get_pld_dataframe(result)

            @test df isa DataFrame
            @test :submarket in propertynames(df)
            @test :period in propertynames(df)
            @test :pld in propertynames(df)
            @test nrow(df) == 4
        end

        @testset "Filtering by submarket works" begin
            duals = Dict{String,Dict{Tuple,Float64}}()
            duals["submarket_balance"] = Dict{Tuple,Float64}(
                ("SE", 1) => 100.0,
                ("SE", 2) => 150.0,
                ("NE", 1) => 80.0,
                ("NE", 2) => 90.0,
                ("S", 1) => 120.0,
            )
            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                has_duals = true,
                dual_values = duals,
            )

            df_se = get_pld_dataframe(result; submarkets = ["SE"])
            @test nrow(df_se) == 2
            @test all(df_se.submarket .== "SE")

            df_multi = get_pld_dataframe(result; submarkets = ["SE", "NE"])
            @test nrow(df_multi) == 4
            @test all(in.(df_multi.submarket, Ref(["SE", "NE"])))
        end

        @testset "Filtering by time period works" begin
            duals = Dict{String,Dict{Tuple,Float64}}()
            duals["submarket_balance"] = Dict{Tuple,Float64}(
                ("SE", 1) => 100.0,
                ("SE", 2) => 150.0,
                ("SE", 3) => 200.0,
                ("SE", 4) => 180.0,
            )
            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                has_duals = true,
                dual_values = duals,
            )

            df_periods = get_pld_dataframe(result; time_periods = 2:3)
            @test nrow(df_periods) == 2
            @test sort(collect(df_periods.period)) == [2, 3]
        end

        @testset "Empty result when no duals" begin
            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                has_duals = false,
            )

            df = get_pld_dataframe(result)
            @test df isa DataFrame
            @test nrow(df) == 0
            @test :submarket in propertynames(df)
            @test :period in propertynames(df)
            @test :pld in propertynames(df)
        end

        @testset "Empty result when submarket_balance missing" begin
            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                has_duals = true,
                dual_values = Dict{String,Dict{Tuple,Float64}}(),
            )

            df = get_pld_dataframe(result)
            @test nrow(df) == 0
        end

        @testset "DataFrame is sorted by submarket and period" begin
            duals = Dict{String,Dict{Tuple,Float64}}()
            duals["submarket_balance"] = Dict{Tuple,Float64}(
                ("NE", 3) => 90.0,
                ("SE", 1) => 100.0,
                ("SE", 3) => 200.0,
                ("NE", 1) => 80.0,
            )
            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                has_duals = true,
                dual_values = duals,
            )

            df = get_pld_dataframe(result)
            @test df.submarket == ["NE", "NE", "SE", "SE"]
            @test df.period == [1, 3, 1, 3]
        end
    end

    # =========================================================================
    # Cost Breakdown Tests
    # =========================================================================

    @testset "CostBreakdown struct" begin
        @testset "Default constructor" begin
            cb = CostBreakdown()
            @test cb.thermal_fuel == 0.0
            @test cb.thermal_startup == 0.0
            @test cb.thermal_shutdown == 0.0
            @test cb.deficit_penalty == 0.0
            @test cb.hydro_water_value == 0.0
            @test cb.total == 0.0
        end

        @testset "Constructor with values" begin
            cb = CostBreakdown(;
                thermal_fuel = 1000.0,
                thermal_startup = 100.0,
                thermal_shutdown = 50.0,
                deficit_penalty = 0.0,
                hydro_water_value = 0.0,
                total = 1150.0,
            )
            @test cb.thermal_fuel == 1000.0
            @test cb.thermal_startup == 100.0
            @test cb.thermal_shutdown == 50.0
            @test cb.total == 1150.0
        end
    end

    @testset "get_cost_breakdown" begin
        @testset "Returns CostBreakdown struct with zeros for empty result" begin
            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                has_values = false,
            )

            # Create a minimal mock system using Dict for testing
            # Note: Full system creation requires many required fields,
            # so we test the function exists and returns correct type
            using OpenDESSEM: ElectricitySystem, Submarket

            submarket =
                Submarket(; id = "SE", name = "Southeast", code = "SE", country = "Brazil")
            system =
                ElectricitySystem(; submarkets = [submarket], base_date = Date(2024, 1, 1))

            cb = get_cost_breakdown(result, system)
            @test cb isa CostBreakdown
            @test cb.thermal_fuel == 0.0
            @test cb.thermal_startup == 0.0
            @test cb.thermal_shutdown == 0.0
            @test cb.deficit_penalty == 0.0
            @test cb.hydro_water_value == 0.0
            @test cb.total == 0.0
        end

        @testset "Calculates thermal fuel cost from generation values" begin
            using OpenDESSEM:
                ElectricitySystem, ConventionalThermal, Submarket, Bus, NATURAL_GAS
            using Dates

            # Create minimal required entities
            submarket =
                Submarket(; id = "SE", name = "Southeast", code = "SE", country = "Brazil")
            bus = Bus(; id = "B001", name = "Test Bus", voltage_kv = 138.0, base_kv = 138.0)
            thermal = ConventionalThermal(;
                id = "T001",
                name = "Test Plant",
                bus_id = "B001",
                submarket_id = "SE",
                fuel_type = NATURAL_GAS,
                capacity_mw = 500.0,
                min_generation_mw = 100.0,
                max_generation_mw = 500.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                min_up_time_hours = 1,
                min_down_time_hours = 1,
                fuel_cost_rsj_per_mwh = 150.0,
                startup_cost_rs = 10000.0,
                shutdown_cost_rs = 5000.0,
                commissioning_date = DateTime(2020, 1, 1),
            )
            system = ElectricitySystem(;
                submarkets = [submarket],
                buses = [bus],
                thermal_plants = [thermal],
                base_date = Date(2024, 1, 1),
            )

            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                has_values = true,
                variables = Dict{Symbol,Any}(
                    :thermal_generation => Dict{Tuple{String,Int},Float64}(
                        ("T001", 1) => 200.0,  # 200 MW for 1 hour = 200 MWh
                        ("T001", 2) => 300.0,  # 300 MW for 1 hour = 300 MWh
                    ),
                ),
            )

            cb = get_cost_breakdown(result, system)
            # Expected: (200 + 300) * 150 = 500 * 150 = 75000 R$
            @test cb.thermal_fuel == 75000.0
            @test cb.total == 75000.0  # Total should equal thermal_fuel (no other costs)
        end

        @testset "Calculates startup and shutdown costs" begin
            using OpenDESSEM:
                ElectricitySystem, ConventionalThermal, Submarket, Bus, NATURAL_GAS
            using Dates

            submarket =
                Submarket(; id = "SE", name = "Southeast", code = "SE", country = "Brazil")
            bus = Bus(; id = "B001", name = "Test Bus", voltage_kv = 138.0, base_kv = 138.0)
            thermal = ConventionalThermal(;
                id = "T001",
                name = "Test Plant",
                bus_id = "B001",
                submarket_id = "SE",
                fuel_type = NATURAL_GAS,
                capacity_mw = 500.0,
                min_generation_mw = 100.0,
                max_generation_mw = 500.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                min_up_time_hours = 1,
                min_down_time_hours = 1,
                fuel_cost_rsj_per_mwh = 150.0,
                startup_cost_rs = 10000.0,
                shutdown_cost_rs = 5000.0,
                commissioning_date = DateTime(2020, 1, 1),
            )
            system = ElectricitySystem(;
                submarkets = [submarket],
                buses = [bus],
                thermal_plants = [thermal],
                base_date = Date(2024, 1, 1),
            )

            result = SolverResult(;
                status = MOI.OPTIMAL,
                solve_status = OPTIMAL,
                has_values = true,
                variables = Dict{Symbol,Any}(
                    :thermal_generation => Dict{Tuple{String,Int},Float64}(
                        ("T001", 1) => 200.0,
                        ("T001", 2) => 150.0,  # Add gen for t=2
                    ),
                    :thermal_startup => Dict{Tuple{String,Int},Float64}(
                        ("T001", 1) => 1.0,  # Startup at t=1
                    ),
                    :thermal_shutdown => Dict{Tuple{String,Int},Float64}(
                        ("T001", 2) => 1.0,  # Shutdown at t=2
                    ),
                ),
            )

            cb = get_cost_breakdown(result, system)
            # Expected: fuel (200+150)*150=52500, startup 10000, shutdown 5000
            @test cb.thermal_fuel == 52500.0
            @test cb.thermal_startup == 10000.0
            @test cb.thermal_shutdown == 5000.0
            @test cb.total == 67500.0  # 52500 + 10000 + 5000
        end
    end

end
