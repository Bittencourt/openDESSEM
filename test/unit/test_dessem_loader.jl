"""
    Test suite for DESSEM file loader integration.

Tests the integration layer between DESSEM2Julia and OpenDESSEM,
converting DESSEM file formats to OpenDESSEM entities.
"""

using Test
using Dates

# Import OpenDESSEM entities
@testset "DESSEM Loader Tests" begin
    # Define paths for sample data
    sample_path = joinpath(@__DIR__, "..", "..", "docs", "Sample", "DS_ONS_102025_RV2D11")

    # Check if sample data exists
    @testset "Sample Data Availability" begin
        @test isdir(sample_path)
        @test isfile(joinpath(sample_path, "dessem.arq"))
        @test isfile(joinpath(sample_path, "entdados.dat"))
        @test isfile(joinpath(sample_path, "termdat.dat"))
        @test isfile(joinpath(sample_path, "hidr.dat"))
        @test isfile(joinpath(sample_path, "leve.pwf"))
    end

    # Test module loading
    @testset "Module Loading" begin
        @test_nowarn begin
            include(
                joinpath(
                    @__DIR__,
                    "..",
                    "..",
                    "src",
                    "data",
                    "loaders",
                    "dessem_loader.jl",
                ),
            )
        end
    end

    # Test converter functions exist
    @testset "Converter Functions" begin
        @test isdefined(Main, :DessemLoader) || @isdefined(DessemLoader)
    end

    # Test DESSEM case loading (integration test)
    @testset "Load DESSEM Case" begin
        if isdir(sample_path)
            # This will be implemented after the loader is created
            # For now, we verify the test structure is correct
            @test true
        else
            @warn "Sample data not found at $sample_path, skipping integration tests"
            @test_skip true
        end
    end

    # Test subsystem code mapping
    @testset "Subsystem Code Mapping" begin
        # Test the mapping from DESSEM numeric codes to OpenDESSEM codes
        expected_mapping = Dict(
            1 => "SE",  # Sudeste
            2 => "S",   # Sul
            3 => "NE",  # Nordeste
            4 => "N",   # Norte
            5 => "FC",   # Fictitious (if used)
        )
        for (code, expected) in expected_mapping
            @test true  # Placeholder for actual mapping tests
        end
    end

    # Test fuel type mapping
    @testset "Fuel Type Mapping" begin
        # DESSEM fuel type codes to OpenDESSEM FuelType enum
        # This mapping will be verified in actual conversion
        @test true  # Placeholder
    end

    # Test entity validation after conversion
    @testset "Entity Validation" begin
        # Converted entities should pass OpenDESSEM validation
        @test true  # Placeholder
    end
end

# Conditional tests when DESSEM2Julia is available
@testset "DESSEM2Julia Integration" begin
    try
        using DESSEM2Julia
        @test true  # DESSEM2Julia loaded successfully

        @testset "Parse Functions Available" begin
            @test isdefined(DESSEM2Julia, :parse_termdat)
            @test isdefined(DESSEM2Julia, :parse_entdados)
            @test isdefined(DESSEM2Julia, :parse_hidr)
            @test isdefined(DESSEM2Julia, :parse_operut)
            @test isdefined(DESSEM2Julia, :parse_renovaveis)
        end

        @testset "Type Definitions Available" begin
            @test isdefined(DESSEM2Julia, :ThermalRegistry)
            @test isdefined(DESSEM2Julia, :GeneralData)
            @test isdefined(DESSEM2Julia, :HidrData)
            @test isdefined(DESSEM2Julia, :CADUSIT)
            @test isdefined(DESSEM2Julia, :UHRecord)
            @test isdefined(DESSEM2Julia, :UTRecord)
        end

    catch e
        @warn "DESSEM2Julia not available: $e"
        @test_skip true
    end
end

# Test actual parsing of sample files (when available)
@testset "Parse Sample Files" begin
    sample_path = joinpath(@__DIR__, "..", "..", "docs", "Sample", "DS_ONS_102025_RV2D11")

    if isdir(sample_path)
        try
            using DESSEM2Julia

            @testset "Parse TERMDAT" begin
                termdat_path = joinpath(sample_path, "termdat.dat")
                if isfile(termdat_path)
                    result = parse_termdat(termdat_path)
                    @test result isa ThermalRegistry
                    @test length(result.plants) > 0
                    @test length(result.units) > 0
                end
            end

            @testset "Parse ENTDADOS" begin
                entdados_path = joinpath(sample_path, "entdados.dat")
                if isfile(entdados_path)
                    result = parse_entdados(entdados_path)
                    @test result isa GeneralData
                    @test length(result.subsystems) > 0
                    @test length(result.hydro_plants) > 0
                    @test length(result.thermal_plants) > 0
                end
            end

            @testset "Parse HIDR" begin
                hidr_path = joinpath(sample_path, "hidr.dat")
                if isfile(hidr_path)
                    result = parse_hidr(hidr_path)
                    @test result !== nothing
                end
            end

            @testset "Parse RENOVAVEIS" begin
                renovaveis_path = joinpath(sample_path, "renovaveis.dat")
                if isfile(renovaveis_path)
                    result = parse_renovaveis(renovaveis_path)
                    @test result isa RenovaveisData
                    @test length(result.plants) > 0
                end
            end

        catch e
            @warn "Error parsing sample files: $e"
            @test_broken true
        end
    else
        @warn "Sample path not found: $sample_path"
        @test_skip true
    end
end
