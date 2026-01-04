"""
    Tests for hydro plant entities.

Tests ReservoirHydro, RunOfRiverHydro, and PumpedStorageHydro entities with comprehensive validation.
"""

using Test
using OpenDESSEM.Entities
using Dates

@testset "Hydro Plant Entities" begin

    @testset "ReservoirHydro - Constructor" begin
        @testset "Valid reservoir plant" begin
            plant = ReservoirHydro(;
                id = "H_001",
                name = "Itaipu",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 29000.0,
                min_volume_hm3 = 5000.0,
                initial_volume_hm3 = 20000.0,
                max_outflow_m3_per_s = 15000.0,
                min_outflow_m3_per_s = 500.0,
                max_generation_mw = 14000.0,
                min_generation_mw = 0.0,
                efficiency = 0.92,
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 69.0,
                must_run = false,
                downstream_plant_id = "H_002",
                water_travel_time_hours = 2.0,
            )

            @test plant.id == "H_001"
            @test plant.name == "Itaipu"
            @test plant.max_volume_hm3 == 29000.0
            @test plant.min_volume_hm3 == 5000.0
            @test plant.initial_volume_hm3 == 20000.0
            @test plant.efficiency == 0.92
            @test plant.subsystem_code == 1
            @test plant.initial_volume_percent ≈ 0.69
            @test plant.downstream_plant_id == "H_002"
            @test plant.water_travel_time_hours == 2.0
        end

        @testset "Reservoir without cascade" begin
            plant = ReservoirHydro(;
                id = "H_002",
                name = "Sobradinho",
                bus_id = "B002",
                submarket_id = "NE",
                max_volume_hm3 = 50000.0,
                min_volume_hm3 = 10000.0,
                initial_volume_hm3 = 30000.0,
                max_outflow_m3_per_s = 8000.0,
                min_outflow_m3_per_s = 200.0,
                max_generation_mw = 1050.0,
                min_generation_mw = 0.0,
                efficiency = 0.88,
                water_value_rs_per_hm3 = 30.0,
                subsystem_code = 3,
                initial_volume_percent = 60.0,
            )

            @test plant.downstream_plant_id === nothing
            @test plant.water_travel_time_hours === nothing
            @test plant.subsystem_code == 3
            @test plant.initial_volume_percent ≈ 0.60
        end
    end

    @testset "ReservoirHydro - Validation" begin
        @testset "Invalid volume limits - min > max" begin
            @test_throws ArgumentError ReservoirHydro(;
                id = "H_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 15000.0,  # Invalid!
                initial_volume_hm3 = 12000.0,
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )
        end

        @testset "Invalid initial volume - above max" begin
            @test_throws ArgumentError ReservoirHydro(;
                id = "H_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 1000.0,
                initial_volume_hm3 = 15000.0,  # Invalid!
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )
        end

        @testset "Invalid initial volume - below min" begin
            @test_throws ArgumentError ReservoirHydro(;
                id = "H_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 3000.0,
                initial_volume_hm3 = 2000.0,  # Invalid!
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )
        end

        @testset "Invalid outflow limits - min > max" begin
            @test_throws ArgumentError ReservoirHydro(;
                id = "H_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 1000.0,
                initial_volume_hm3 = 5000.0,
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 6000.0,  # Invalid!
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )
        end

        @testset "Invalid efficiency - above 1.0" begin
            @test_throws ArgumentError ReservoirHydro(;
                id = "H_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 1000.0,
                initial_volume_hm3 = 5000.0,
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 1.5,  # Invalid!
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )
        end

        @testset "Invalid efficiency - negative" begin
            @test_throws ArgumentError ReservoirHydro(;
                id = "H_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 1000.0,
                initial_volume_hm3 = 5000.0,
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = -0.1,  # Invalid!
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )
        end

        @testset "Cascade fields must both be set" begin
            @test_throws ArgumentError ReservoirHydro(;
                id = "H_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 1000.0,
                initial_volume_hm3 = 5000.0,
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
                downstream_plant_id = "H_002",  # Set but water_travel_time_hours is not
            )
        end
    end

    @testset "RunOfRiverHydro - Constructor" begin
        @testset "Valid run-of-river plant" begin
            plant = RunOfRiverHydro(;
                id = "ROR_001",
                name = "Run of River Plant 1",
                bus_id = "B002",
                submarket_id = "SE",
                max_flow_m3_per_s = 500.0,
                min_flow_m3_per_s = 50.0,
                max_generation_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.88,
                subsystem_code = 1,
                initial_volume_percent = 100.0,
                must_run = true,
            )

            @test plant.id == "ROR_001"
            @test plant.max_flow_m3_per_s == 500.0
            @test plant.min_flow_m3_per_s == 50.0
            @test plant.efficiency == 0.88
            @test plant.subsystem_code == 1
            @test plant.initial_volume_percent ≈ 1.0
            @test plant.must_run == true
        end

        @testset "Run-of-river with cascade" begin
            plant = RunOfRiverHydro(;
                id = "ROR_002",
                name = "ROR 2",
                bus_id = "B003",
                submarket_id = "SE",
                max_flow_m3_per_s = 1000.0,
                min_flow_m3_per_s = 100.0,
                max_generation_mw = 200.0,
                min_generation_mw = 50.0,
                efficiency = 0.90,
                subsystem_code = 1,
                initial_volume_percent = 100.0,
                downstream_plant_id = "ROR_003",
                water_travel_time_hours = 0.5,
            )

            @test plant.downstream_plant_id == "ROR_003"
            @test plant.water_travel_time_hours == 0.5
            @test plant.subsystem_code == 1
            @test plant.initial_volume_percent ≈ 1.0
        end
    end

    @testset "RunOfRiverHydro - Validation" begin
        @testset "Invalid flow limits - min > max" begin
            @test_throws ArgumentError RunOfRiverHydro(;
                id = "ROR_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "S",
                max_flow_m3_per_s = 500.0,
                min_flow_m3_per_s = 600.0,  # Invalid!
                max_generation_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                subsystem_code = 1,
                initial_volume_percent = 100.0,
            )
        end

        @testset "Negative max flow" begin
            @test_throws ArgumentError RunOfRiverHydro(;
                id = "ROR_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "S",
                max_flow_m3_per_s = -100.0,  # Invalid!
                min_flow_m3_per_s = 0.0,
                max_generation_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                subsystem_code = 1,
                initial_volume_percent = 100.0,
            )
        end

        @testset "Invalid efficiency" begin
            @test_throws ArgumentError RunOfRiverHydro(;
                id = "ROR_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "S",
                max_flow_m3_per_s = 500.0,
                min_flow_m3_per_s = 0.0,
                max_generation_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 1.2,  # Invalid!
                subsystem_code = 1,
                initial_volume_percent = 100.0,
            )
        end
    end

    @testset "PumpedStorageHydro - Constructor" begin
        @testset "Valid pumped storage plant" begin
            plant = PumpedStorageHydro(;
                id = "PS_001",
                name = "Pumped Storage 1",
                bus_id = "B003",
                submarket_id = "SE",
                upper_max_volume_hm3 = 500.0,
                upper_min_volume_hm3 = 50.0,
                upper_initial_volume_hm3 = 300.0,
                upper_initial_volume_percent = 60.0,
                lower_max_volume_hm3 = 1000.0,
                lower_min_volume_hm3 = 100.0,
                lower_initial_volume_hm3 = 800.0,
                max_generation_mw = 500.0,
                max_pumping_mw = 400.0,
                generation_efficiency = 0.85,
                pumping_efficiency = 0.87,
                min_generation_mw = 0.0,
                subsystem_code = 1,
                must_run = false,
            )

            @test plant.id == "PS_001"
            @test plant.upper_max_volume_hm3 == 500.0
            @test plant.lower_max_volume_hm3 == 1000.0
            @test plant.upper_initial_volume_hm3 == 300.0
            @test plant.lower_initial_volume_hm3 == 800.0
            @test plant.max_generation_mw == 500.0
            @test plant.max_pumping_mw == 400.0
            @test plant.generation_efficiency == 0.85
            @test plant.pumping_efficiency == 0.87
            @test plant.upper_initial_volume_percent ≈ 0.60
            @test plant.subsystem_code == 1
        end
    end

    @testset "PumpedStorageHydro - Validation" begin
        @testset "Invalid upper reservoir - min > max" begin
            @test_throws ArgumentError PumpedStorageHydro(;
                id = "PS_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                upper_max_volume_hm3 = 500.0,
                upper_min_volume_hm3 = 600.0,  # Invalid!
                upper_initial_volume_hm3 = 550.0,
                lower_max_volume_hm3 = 1000.0,
                lower_min_volume_hm3 = 100.0,
                lower_initial_volume_hm3 = 500.0,
                max_generation_mw = 500.0,
                max_pumping_mw = 400.0,
                generation_efficiency = 0.85,
                pumping_efficiency = 0.87,
                min_generation_mw = 0.0,
                upper_initial_volume_percent = 60.0,
                subsystem_code = 1,
            )
        end

        @testset "Invalid lower reservoir - min > max" begin
            @test_throws ArgumentError PumpedStorageHydro(;
                id = "PS_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                upper_max_volume_hm3 = 500.0,
                upper_min_volume_hm3 = 50.0,
                upper_initial_volume_hm3 = 300.0,
                lower_max_volume_hm3 = 1000.0,
                lower_min_volume_hm3 = 1200.0,  # Invalid!
                lower_initial_volume_hm3 = 600.0,
                max_generation_mw = 500.0,
                max_pumping_mw = 400.0,
                generation_efficiency = 0.85,
                pumping_efficiency = 0.87,
                min_generation_mw = 0.0,
                upper_initial_volume_percent = 60.0,
                subsystem_code = 1,
            )
        end

        @testset "Invalid upper initial volume" begin
            @test_throws ArgumentError PumpedStorageHydro(;
                id = "PS_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                upper_max_volume_hm3 = 500.0,
                upper_min_volume_hm3 = 50.0,
                upper_initial_volume_hm3 = 600.0,  # Invalid! > max
                lower_max_volume_hm3 = 1000.0,
                lower_min_volume_hm3 = 100.0,
                lower_initial_volume_hm3 = 500.0,
                max_generation_mw = 500.0,
                max_pumping_mw = 400.0,
                generation_efficiency = 0.85,
                pumping_efficiency = 0.87,
                min_generation_mw = 0.0,
                upper_initial_volume_percent = 60.0,
                subsystem_code = 1,
            )
        end

        @testset "Invalid lower initial volume" begin
            @test_throws ArgumentError PumpedStorageHydro(;
                id = "PS_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                upper_max_volume_hm3 = 500.0,
                upper_min_volume_hm3 = 50.0,
                upper_initial_volume_hm3 = 300.0,
                lower_max_volume_hm3 = 1000.0,
                lower_min_volume_hm3 = 100.0,
                lower_initial_volume_hm3 = 50.0,  # Invalid! < min
                max_generation_mw = 500.0,
                max_pumping_mw = 400.0,
                generation_efficiency = 0.85,
                pumping_efficiency = 0.87,
                min_generation_mw = 0.0,
                upper_initial_volume_percent = 60.0,
                subsystem_code = 1,
            )
        end

        @testset "Invalid generation efficiency" begin
            @test_throws ArgumentError PumpedStorageHydro(;
                id = "PS_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                upper_max_volume_hm3 = 500.0,
                upper_min_volume_hm3 = 50.0,
                upper_initial_volume_hm3 = 300.0,
                lower_max_volume_hm3 = 1000.0,
                lower_min_volume_hm3 = 100.0,
                lower_initial_volume_hm3 = 500.0,
                max_generation_mw = 500.0,
                max_pumping_mw = 400.0,
                generation_efficiency = 1.2,  # Invalid!
                pumping_efficiency = 0.87,
                min_generation_mw = 0.0,
                upper_initial_volume_percent = 60.0,
                subsystem_code = 1,
            )
        end

        @testset "Invalid pumping efficiency" begin
            @test_throws ArgumentError PumpedStorageHydro(;
                id = "PS_001",
                name = "Invalid",
                bus_id = "B001",
                submarket_id = "SE",
                upper_max_volume_hm3 = 500.0,
                upper_min_volume_hm3 = 50.0,
                upper_initial_volume_hm3 = 300.0,
                lower_max_volume_hm3 = 1000.0,
                lower_min_volume_hm3 = 100.0,
                lower_initial_volume_hm3 = 500.0,
                max_generation_mw = 500.0,
                max_pumping_mw = 400.0,
                generation_efficiency = 0.85,
                pumping_efficiency = -0.1,  # Invalid!
                min_generation_mw = 0.0,
                upper_initial_volume_percent = 60.0,
                subsystem_code = 1,
            )
        end
    end

    @testset "HydroPlant - Type Hierarchy" begin
        @testset "ReservoirHydro is HydroPlant" begin
            plant = ReservoirHydro(;
                id = "H_001",
                name = "Test",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 1000.0,
                initial_volume_hm3 = 5000.0,
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )

            @test plant isa HydroPlant
            @test plant isa PhysicalEntity
            @test plant isa AbstractEntity
        end

        @testset "RunOfRiverHydro is HydroPlant" begin
            plant = RunOfRiverHydro(;
                id = "ROR_001",
                name = "Test",
                bus_id = "B001",
                submarket_id = "SE",
                max_flow_m3_per_s = 500.0,
                min_flow_m3_per_s = 0.0,
                max_generation_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                subsystem_code = 1,
                initial_volume_percent = 100.0,
            )

            @test plant isa HydroPlant
            @test plant isa PhysicalEntity
            @test plant isa AbstractEntity
        end

        @testset "PumpedStorageHydro is HydroPlant" begin
            plant = PumpedStorageHydro(;
                id = "PS_001",
                name = "Test",
                bus_id = "B001",
                submarket_id = "SE",
                upper_max_volume_hm3 = 500.0,
                upper_min_volume_hm3 = 50.0,
                upper_initial_volume_hm3 = 300.0,
                lower_max_volume_hm3 = 1000.0,
                lower_min_volume_hm3 = 100.0,
                lower_initial_volume_hm3 = 500.0,
                max_generation_mw = 500.0,
                max_pumping_mw = 400.0,
                generation_efficiency = 0.85,
                pumping_efficiency = 0.87,
                min_generation_mw = 0.0,
                upper_initial_volume_percent = 60.0,
                subsystem_code = 1,
            )

            @test plant isa HydroPlant
            @test plant isa PhysicalEntity
            @test plant isa AbstractEntity
        end
    end

    @testset "HydroPlant - Edge Cases" begin
        @testset "Zero minimum outflow" begin
            plant = ReservoirHydro(;
                id = "H_001",
                name = "Test",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 1000.0,
                initial_volume_hm3 = 5000.0,
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,  # No minimum
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )

            @test plant.min_outflow_m3_per_s == 0.0
        end

        @testset "Zero minimum volume" begin
            plant = RunOfRiverHydro(;
                id = "ROR_001",
                name = "Test",
                bus_id = "B001",
                submarket_id = "SE",
                max_flow_m3_per_s = 500.0,
                min_flow_m3_per_s = 0.0,  # No minimum
                max_generation_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                subsystem_code = 1,
                initial_volume_percent = 100.0,
            )

            @test plant.min_flow_m3_per_s == 0.0
        end

        @testset "Zero water value" begin
            plant = ReservoirHydro(;
                id = "H_001",
                name = "Test",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 1000.0,
                initial_volume_hm3 = 5000.0,
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 0.9,
                water_value_rs_per_hm3 = 0.0,  # Free water
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )

            @test plant.water_value_rs_per_hm3 == 0.0
        end

        @testset "Maximum efficiency (100%)" begin
            plant = ReservoirHydro(;
                id = "H_001",
                name = "Test",
                bus_id = "B001",
                submarket_id = "SE",
                max_volume_hm3 = 10000.0,
                min_volume_hm3 = 1000.0,
                initial_volume_hm3 = 5000.0,
                max_outflow_m3_per_s = 5000.0,
                min_outflow_m3_per_s = 0.0,
                max_generation_mw = 1000.0,
                min_generation_mw = 0.0,
                efficiency = 1.0,  # Perfect efficiency
                water_value_rs_per_hm3 = 50.0,
                subsystem_code = 1,
                initial_volume_percent = 50.0,
            )

            @test plant.efficiency == 1.0
        end
    end
end
