"""
    Solution Exporter Unit Tests

Tests CSV and JSON export functionality including:
- CSV file creation with correct structure and columns
- JSON file creation with valid content (not "nothing")
- Pretty printing and compact JSON modes
- Error handling for results without values
"""

using Test
using JuMP
using HiGHS
using Dates
using DataFrames
using CSV
using JSON3

using OpenDESSEM
using OpenDESSEM.Solvers
using OpenDESSEM.Solvers:
    SolverResult, OPTIMAL,
    solve_model!
using OpenDESSEM.Analysis:
    export_csv, export_json

# Include small system factory
include(joinpath(@__DIR__, "..", "fixtures", "small_system.jl"))
using .SmallSystemFactory: create_small_test_system

@testset "Solution Exporter" begin

    @testset "export_csv creates expected files" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = true)

        # Use temporary directory
        mktempdir() do tmpdir
            files = export_csv(result, tmpdir; time_periods = 1:6)

            @test length(files) > 0
            @test all(isfile, files)

            # Check thermal generation CSV exists and has correct structure
            thermal_file = joinpath(tmpdir, "thermal_generation.csv")
            if isfile(thermal_file)
                df = CSV.read(thermal_file, DataFrame)
                @test "plant_id" in names(df)
                @test nrow(df) >= 1  # At least 1 thermal plant
                # Check time period columns exist
                @test "t_1" in names(df)
                @test "t_6" in names(df)
            end

            # Check summary CSV exists
            summary_file = joinpath(tmpdir, "summary.csv")
            @test isfile(summary_file)
            summary_df = CSV.read(summary_file, DataFrame)
            @test nrow(summary_df) > 0
        end
    end

    @testset "export_csv includes hydro files" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        mktempdir() do tmpdir
            files = export_csv(result, tmpdir; time_periods = 1:6)

            hydro_gen = joinpath(tmpdir, "hydro_generation.csv")
            hydro_stor = joinpath(tmpdir, "hydro_storage.csv")

            @test isfile(hydro_gen)
            @test isfile(hydro_stor)

            if isfile(hydro_gen)
                df = CSV.read(hydro_gen, DataFrame)
                @test "plant_id" in names(df)
                @test nrow(df) >= 1
            end
        end
    end

    @testset "export_csv with LMP data" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = true)

        # Use LP result for duals
        export_result = result.lp_result !== nothing ? result.lp_result : result

        if export_result.has_duals
            mktempdir() do tmpdir
                files = export_csv(export_result, tmpdir; time_periods = 1:6)
                lmp_file = joinpath(tmpdir, "submarket_lmps.csv")
                @test isfile(lmp_file)

                if isfile(lmp_file)
                    df = CSV.read(lmp_file, DataFrame)
                    @test "submarket_id" in names(df)
                end
            end
        end
    end

    @testset "export_json creates valid JSON file" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        mktempdir() do tmpdir
            filepath = joinpath(tmpdir, "solution.json")
            returned_path = export_json(result, filepath; time_periods = 1:6, pretty = true)

            @test isfile(filepath)
            @test returned_path == abspath(filepath)

            # Read and parse the JSON
            content = read(filepath, String)
            @test length(content) > 10  # Not empty or "nothing"
            @test content != "nothing"  # Verify JSON3.pretty bug is fixed

            # Parse JSON and verify structure
            json = JSON3.read(content)
            @test haskey(json, :metadata) || haskey(json, "metadata")
            @test haskey(json, :solution) || haskey(json, "solution")
            @test haskey(json, :variables) || haskey(json, "variables")
        end
    end

    @testset "export_json with pretty=false" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        mktempdir() do tmpdir
            filepath = joinpath(tmpdir, "solution_compact.json")
            export_json(result, filepath; time_periods = 1:6, pretty = false)

            @test isfile(filepath)
            content = read(filepath, String)
            @test length(content) > 10
            @test content != "nothing"

            # Should be parseable JSON
            json = JSON3.read(content)
            @test haskey(json, :metadata) || haskey(json, "metadata")
        end
    end

    @testset "export_json contains thermal generation data" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        mktempdir() do tmpdir
            filepath = joinpath(tmpdir, "solution.json")
            export_json(result, filepath; time_periods = 1:6, pretty = true)

            content = read(filepath, String)
            json = JSON3.read(content)

            # Check variables section has thermal generation
            vars = get(json, :variables, get(json, "variables", nothing))
            @test vars !== nothing
            if vars !== nothing
                tg = get(vars, :thermal_generation, get(vars, "thermal_generation", nothing))
                @test tg !== nothing
            end
        end
    end

    @testset "export_csv errors on result without values" begin
        result = SolverResult()
        mktempdir() do tmpdir
            @test_throws ErrorException export_csv(result, tmpdir)
        end
    end

    @testset "export_json errors on result without values" begin
        result = SolverResult()
        mktempdir() do tmpdir
            filepath = joinpath(tmpdir, "fail.json")
            @test_throws ErrorException export_json(result, filepath)
        end
    end
end
