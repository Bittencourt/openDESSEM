"""
    Test suite for renewable energy plant entities

Tests for WindFarm and SolarFarm entities following TDD principles.
"""

using OpenDESSEM
using Test

@testset "Renewable Plant Entities" begin

    @testset "WindFarm - Constructor" begin
        @testset "Valid wind farm" begin
            farm = WindFarm(;
                id = "W_001",
                name = "Coastal Wind Farm",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 200.0,
                min_generation_mw = 0.0,
                efficiency = 0.45,
                must_run = true,
            )

            @test farm.id == "W_001"
            @test farm.name == "Coastal Wind Farm"
            @test farm.bus_id == "B001"
            @test farm.submarket_id == "NE"
            @test farm.capacity_mw == 200.0
            @test farm.min_generation_mw == 0.0
            @test farm.efficiency == 0.45
            @test farm.must_run == true
            @test farm isa RenewablePlant
            @test farm isa PhysicalEntity
        end

        @testset "Default values" begin
            farm = WindFarm(;
                id = "W_002",
                name = "Default Wind Farm",
                bus_id = "B002",
                submarket_id = "SE",
                capacity_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.40,
            )

            @test farm.must_run == true  # Default
            @test farm.metadata !== nothing
            @test farm.metadata.version == 1
        end
    end

    @testset "WindFarm - Validation" begin
        @testset "Invalid capacity" begin
            @test_throws ArgumentError WindFarm(;
                id = "W_001",
                name = "Invalid Capacity",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = -100.0,
                min_generation_mw = 0.0,
                efficiency = 0.45,
            )

            @test_throws ArgumentError WindFarm(;
                id = "W_001",
                name = "Zero Capacity",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 0.0,
                min_generation_mw = 0.0,
                efficiency = 0.45,
            )
        end

        @testset "Invalid min_generation" begin
            @test_throws ArgumentError WindFarm(;
                id = "W_001",
                name = "Invalid Min Gen",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 200.0,
                min_generation_mw = 250.0,  # > capacity
                efficiency = 0.45,
            )

            @test_throws ArgumentError WindFarm(;
                id = "W_001",
                name = "Negative Min Gen",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 200.0,
                min_generation_mw = -10.0,
                efficiency = 0.45,
            )
        end

        @testset "Invalid efficiency" begin
            @test_throws ArgumentError WindFarm(;
                id = "W_001",
                name = "High Efficiency",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 200.0,
                min_generation_mw = 0.0,
                efficiency = 1.5,  # > 1
            )

            @test_throws ArgumentError WindFarm(;
                id = "W_001",
                name = "Low Efficiency",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 200.0,
                min_generation_mw = 0.0,
                efficiency = -0.1,  # < 0
            )
        end

        @testset "Invalid submarket_id" begin
            @test_throws ArgumentError WindFarm(;
                id = "W_001",
                name = "Short Submarket",
                bus_id = "B001",
                submarket_id = "X",  # Too short
                capacity_mw = 200.0,
                min_generation_mw = 0.0,
                efficiency = 0.45,
            )

            @test_throws ArgumentError WindFarm(;
                id = "W_001",
                name = "Long Submarket",
                bus_id = "B001",
                submarket_id = "ABCDE",  # Too long
                capacity_mw = 200.0,
                min_generation_mw = 0.0,
                efficiency = 0.45,
            )
        end

        @testset "Invalid ID format" begin
            @test_throws ArgumentError WindFarm(;
                id = "",  # Empty string
                name = "Invalid ID",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 200.0,
                min_generation_mw = 0.0,
                efficiency = 0.45,
            )
        end
    end

    @testset "SolarFarm - Constructor" begin
        @testset "Valid solar farm with fixed tracking" begin
            farm = SolarFarm(;
                id = "S_001",
                name = "Desert Solar Plant",
                bus_id = "B002",
                submarket_id = "NW",
                capacity_mw = 150.0,
                min_generation_mw = 0.0,
                efficiency = 0.22,
                tracking = FIXED,
                must_run = true,
            )

            @test farm.id == "S_001"
            @test farm.name == "Desert Solar Plant"
            @test farm.bus_id == "B002"
            @test farm.submarket_id == "NW"
            @test farm.capacity_mw == 150.0
            @test farm.min_generation_mw == 0.0
            @test farm.efficiency == 0.22
            @test farm.tracking == FIXED
            @test farm.must_run == true
            @test farm isa RenewablePlant
            @test farm isa PhysicalEntity
        end

        @testset "Solar farm with single-axis tracking" begin
            farm = SolarFarm(;
                id = "S_002",
                name = "Single Axis Solar",
                bus_id = "B003",
                submarket_id = "SE",
                capacity_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.20,
                tracking = SINGLE_AXIS,
            )

            @test farm.tracking == SINGLE_AXIS
            @test farm.must_run == true  # Default
        end

        @testset "Solar farm with dual-axis tracking" begin
            farm = SolarFarm(;
                id = "S_003",
                name = "Dual Axis Solar",
                bus_id = "B004",
                submarket_id = "NE",
                capacity_mw = 80.0,
                min_generation_mw = 0.0,
                efficiency = 0.21,
                tracking = DUAL_AXIS,
            )

            @test farm.tracking == DUAL_AXIS
        end

        @testset "Default values" begin
            farm = SolarFarm(;
                id = "S_004",
                name = "Default Solar",
                bus_id = "B005",
                submarket_id = "SE",
                capacity_mw = 50.0,
                min_generation_mw = 0.0,
                efficiency = 0.18,
                tracking = FIXED,
            )

            @test farm.must_run == true  # Default
            @test farm.metadata !== nothing
            @test farm.metadata.version == 1
        end
    end

    @testset "SolarFarm - Validation" begin
        @testset "Invalid capacity" begin
            @test_throws ArgumentError SolarFarm(;
                id = "S_001",
                name = "Negative Capacity",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = -150.0,
                min_generation_mw = 0.0,
                efficiency = 0.22,
                tracking = FIXED,
            )
        end

        @testset "Invalid efficiency" begin
            @test_throws ArgumentError SolarFarm(;
                id = "S_001",
                name = "High Efficiency",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 150.0,
                min_generation_mw = 0.0,
                efficiency = 1.1,  # > 1
                tracking = FIXED,
            )

            @test_throws ArgumentError SolarFarm(;
                id = "S_001",
                name = "Negative Efficiency",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 150.0,
                min_generation_mw = 0.0,
                efficiency = -0.1,  # < 0
                tracking = FIXED,
            )
        end

        @testset "Invalid submarket_id" begin
            @test_throws ArgumentError SolarFarm(;
                id = "S_001",
                name = "Short Submarket",
                bus_id = "B001",
                submarket_id = "X",  # Too short
                capacity_mw = 150.0,
                min_generation_mw = 0.0,
                efficiency = 0.22,
                tracking = FIXED,
            )
        end

        @testset "Invalid ID format" begin
            @test_throws ArgumentError SolarFarm(;
                id = "",  # Empty string
                name = "Invalid ID",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 150.0,
                min_generation_mw = 0.0,
                efficiency = 0.22,
                tracking = FIXED,
            )
        end
    end

    @testset "RenewablePlant - Type Hierarchy" begin
        @testset "WindFarm type hierarchy" begin
            farm = WindFarm(;
                id = "W_001",
                name = "Test Wind",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.40,
            )

            @test farm isa RenewablePlant
            @test farm isa PhysicalEntity
            @test farm isa AbstractEntity
            @test RenewablePlant <: PhysicalEntity
            @test PhysicalEntity <: AbstractEntity
        end

        @testset "SolarFarm type hierarchy" begin
            farm = SolarFarm(;
                id = "S_001",
                name = "Test Solar",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.20,
                tracking = FIXED,
            )

            @test farm isa RenewablePlant
            @test farm isa PhysicalEntity
            @test farm isa AbstractEntity
        end
    end

    @testset "RenewablePlant - Edge Cases" begin
        @testset "Zero min_generation" begin
            wind = WindFarm(;
                id = "W_001",
                name = "Zero Min Wind",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.40,
            )

            solar = SolarFarm(;
                id = "S_001",
                name = "Zero Min Solar",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.20,
                tracking = FIXED,
            )

            @test wind.min_generation_mw == 0.0
            @test solar.min_generation_mw == 0.0
        end

        @testset "High efficiency" begin
            wind = WindFarm(;
                id = "W_001",
                name = "High Efficiency Wind",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.59,  # Close to 1
            )

            solar = SolarFarm(;
                id = "S_001",
                name = "High Efficiency Solar",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.25,  # Typical PV limit
                tracking = FIXED,
            )

            @test wind.efficiency == 0.59
            @test solar.efficiency == 0.25
        end

        @testset "Large capacity" begin
            wind = WindFarm(;
                id = "W_001",
                name = "Large Wind Farm",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 0.45,
            )

            solar = SolarFarm(;
                id = "S_001",
                name = "Large Solar Farm",
                bus_id = "B001",
                submarket_id = "NE",
                capacity_mw = 500.0,
                min_generation_mw = 0.0,
                efficiency = 0.22,
                tracking = SINGLE_AXIS,
            )

            @test wind.capacity_mw == 1000.0
            @test solar.capacity_mw == 500.0
        end

        @testset "Tracking system enum values" begin
            @test FIXED === OpenDESSEM.FIXED
            @test SINGLE_AXIS === OpenDESSEM.SINGLE_AXIS
            @test DUAL_AXIS === OpenDESSEM.DUAL_AXIS

            @test collect(instances(TrackingSystem)) == [FIXED, SINGLE_AXIS, DUAL_AXIS]
        end
    end

end
