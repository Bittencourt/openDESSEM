"""
    Test PWF.jl integration with OpenDESSEM

Tests basic PWF file parsing functionality.
This is a preliminary integration test before implementing
the full data loader (TASK-010).
"""

using PWF
using Test

@testset "PWF.jl Integration Tests" begin

    @testset "PWF.jl package loads" begin
        @test PWF !== nothing
        @test isdefined(PWF, :parse_file)
        println("✓ PWF.jl package loaded successfully")
    end

    @testset "Parse sample .pwf file" begin
        # Test with one of the sample files
        pwf_file = "docs/Sample/DS_ONS_102025_RV2D11/sab10h.pwf"

        if isfile(pwf_file)
            @info "Parsing PWF file" file = pwf_file

            # Parse the file using PWF.jl
            data = PWF.parse_file(pwf_file)

            # Verify basic structure
            @test data !== nothing
            @test isa(data, Dict)

            # Check for expected data structures
            # PWF.jl typically returns data with buses, branches, generators, etc.
            @test !isempty(data)

            @info "PWF file parsed successfully" n_fields = length(data)

            # Print available fields for documentation
            println("\nAvailable PWF data fields:")
            for key in keys(data)
                println("  - $key")
            end
        else
            @test_skip "PWF sample file not found: $pwf_file"
        end
    end

    @testset "Parse multiple sample files" begin
        pwf_files = [
            "docs/Sample/DS_ONS_102025_RV2D11/sab10h.pwf",
            "docs/Sample/DS_ONS_102025_RV2D11/sab19h.pwf",
            "docs/Sample/DS_ONS_102025_RV2D11/leve.pwf",
            "docs/Sample/DS_ONS_102025_RV2D11/media.pwf",
        ]

        parsed_count = 0
        for pwf_file in pwf_files
            if isfile(pwf_file)
                try
                    data = PWF.parse_file(pwf_file)
                    @test data !== nothing
                    @test isa(data, Dict)
                    parsed_count += 1
                    @info "Successfully parsed" file = pwf_file
                catch e
                    @warn "Failed to parse PWF file" file = pwf_file error = e
                end
            end
        end

        @test parsed_count > 0
        @info "PWF parsing summary" parsed = parsed_count total = length(pwf_files)

        if parsed_count > 0
            println(
                "\n✓ Successfully parsed $parsed_count out of $(length(pwf_files)) sample files",
            )
        end
    end
end
