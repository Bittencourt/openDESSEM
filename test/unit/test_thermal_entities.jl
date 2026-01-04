"""
    Tests for thermal plant entities.

Tests ConventionalThermal and CombinedCyclePlant entities with comprehensive validation.
"""

using Test
using OpenDESSEM.Entities
using Dates

@testset "Thermal Plant Entities" begin

    @testset "ConventionalThermal - Constructor" begin
        @testset "Valid plant creation" begin
            plant = ConventionalThermal(;
                id="T_SE_001",
                name="Sudeste Gas Plant 1",
                bus_id="SE_230KV_001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=500.0,
                min_generation_mw=150.0,
                max_generation_mw=500.0,
                ramp_up_mw_per_min=50.0,
                ramp_down_mw_per_min=50.0,
                min_up_time_hours=6,
                min_down_time_hours=4,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=15000.0,
                shutdown_cost_rs=8000.0,
                must_run=false
            )

            @test plant.id == "T_SE_001"
            @test plant.name == "Sudeste Gas Plant 1"
            @test plant.bus_id == "SE_230KV_001"
            @test plant.submarket_id == "SE"
            @test plant.fuel_type == NATURAL_GAS
            @test plant.capacity_mw == 500.0
            @test plant.min_generation_mw == 150.0
            @test plant.max_generation_mw == 500.0
            @test plant.ramp_up_mw_per_min == 50.0
            @test plant.ramp_down_mw_per_min == 50.0
            @test plant.min_up_time_hours == 6
            @test plant.min_down_time_hours == 4
            @test plant.fuel_cost_rsj_per_mwh == 150.0
            @test plant.startup_cost_rs == 15000.0
            @test plant.shutdown_cost_rs == 8000.0
            @test plant.must_run == false
        end

        @testset "Plant with default metadata" begin
            plant = ConventionalThermal(;
                id="T_001",
                name="Test Plant",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=COAL,
                capacity_mw=300.0,
                min_generation_mw=100.0,
                max_generation_mw=300.0,
                ramp_up_mw_per_min=30.0,
                ramp_down_mw_per_min=30.0,
                min_up_time_hours=8,
                min_down_time_hours=4,
                fuel_cost_rsj_per_mwh=100.0,
                startup_cost_rs=10000.0,
                shutdown_cost_rs=5000.0
            )

            @test plant.metadata isa EntityMetadata
            @test plant.metadata.version == 1
            @test plant.metadata.source == "unknown"
        end
    end

    @testset "ConventionalThermal - Validation" begin
        @testset "Invalid capacity - negative" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="T_001",
                name="Invalid",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=-100.0,  # Invalid!
                min_generation_mw=0.0,
                max_generation_mw=100.0,
                ramp_up_mw_per_min=10.0,
                ramp_down_mw_per_min=10.0,
                min_up_time_hours=4,
                min_down_time_hours=2,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=5000.0,
                shutdown_cost_rs=3000.0
            )
        end

        @testset "Invalid capacity - zero" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="T_001",
                name="Invalid",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=0.0,  # Invalid!
                min_generation_mw=0.0,
                max_generation_mw=100.0,
                ramp_up_mw_per_min=10.0,
                ramp_down_mw_per_min=10.0,
                min_up_time_hours=4,
                min_down_time_hours=2,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=5000.0,
                shutdown_cost_rs=3000.0
            )
        end

        @testset "Invalid generation limits - min > max" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="T_001",
                name="Invalid",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=500.0,
                min_generation_mw=400.0,  # Invalid!
                max_generation_mw=300.0,
                ramp_up_mw_per_min=10.0,
                ramp_down_mw_per_min=10.0,
                min_up_time_hours=4,
                min_down_time_hours=2,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=5000.0,
                shutdown_cost_rs=3000.0
            )
        end

        @testset "Invalid generation limits - max > capacity" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="T_001",
                name="Invalid",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=300.0,
                min_generation_mw=100.0,
                max_generation_mw=400.0,  # Invalid!
                ramp_up_mw_per_min=10.0,
                ramp_down_mw_per_min=10.0,
                min_up_time_hours=4,
                min_down_time_hours=2,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=5000.0,
                shutdown_cost_rs=3000.0
            )
        end

        @testset "Negative min generation" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="T_001",
                name="Invalid",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=500.0,
                min_generation_mw=-10.0,  # Invalid!
                max_generation_mw=500.0,
                ramp_up_mw_per_min=10.0,
                ramp_down_mw_per_min=10.0,
                min_up_time_hours=4,
                min_down_time_hours=2,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=5000.0,
                shutdown_cost_rs=3000.0
            )
        end

        @testset "Negative ramp rates" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="T_001",
                name="Invalid",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=500.0,
                min_generation_mw=150.0,
                max_generation_mw=500.0,
                ramp_up_mw_per_min=-10.0,  # Invalid!
                ramp_down_mw_per_min=50.0,
                min_up_time_hours=6,
                min_down_time_hours=4,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=15000.0,
                shutdown_cost_rs=8000.0
            )
        end

        @testset "Negative time constraints" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="T_001",
                name="Invalid",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=500.0,
                min_generation_mw=150.0,
                max_generation_mw=500.0,
                ramp_up_mw_per_min=50.0,
                ramp_down_mw_per_min=50.0,
                min_up_time_hours=-2,  # Invalid!
                min_down_time_hours=4,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=15000.0,
                shutdown_cost_rs=8000.0
            )
        end

        @testset "Negative costs" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="T_001",
                name="Invalid",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=500.0,
                min_generation_mw=150.0,
                max_generation_mw=500.0,
                ramp_up_mw_per_min=50.0,
                ramp_down_mw_per_min=50.0,
                min_up_time_hours=6,
                min_down_time_hours=4,
                fuel_cost_rsj_per_mwh=-150.0,  # Invalid!
                startup_cost_rs=15000.0,
                shutdown_cost_rs=8000.0
            )
        end

        @testset "Invalid ID" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="",  # Invalid!
                name="Invalid",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=500.0,
                min_generation_mw=150.0,
                max_generation_mw=500.0,
                ramp_up_mw_per_min=50.0,
                ramp_down_mw_per_min=50.0,
                min_up_time_hours=6,
                min_down_time_hours=4,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=15000.0,
                shutdown_cost_rs=8000.0
            )
        end

        @testset "Invalid name" begin
            @test_throws ArgumentError ConventionalThermal(;
                id="T_001",
                name="",  # Invalid!
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=500.0,
                min_generation_mw=150.0,
                max_generation_mw=500.0,
                ramp_up_mw_per_min=50.0,
                ramp_down_mw_per_min=50.0,
                min_up_time_hours=6,
                min_down_time_hours=4,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=15000.0,
                shutdown_cost_rs=8000.0
            )
        end
    end

    @testset "ConventionalThermal - Different Fuel Types" begin
        @testset "Coal plant" begin
            plant = ConventionalThermal(;
                id="COAL_001",
                name="Coal Plant 1",
                bus_id="B001",
                submarket_id="SUL",  # 3 characters (min 2)
                fuel_type=COAL,
                capacity_mw=600.0,
                min_generation_mw=200.0,
                max_generation_mw=600.0,
                ramp_up_mw_per_min=20.0,
                ramp_down_mw_per_min=20.0,
                min_up_time_hours=24,
                min_down_time_hours=12,
                fuel_cost_rsj_per_mwh=80.0,
                startup_cost_rs=50000.0,
                shutdown_cost_rs=20000.0
            )

            @test plant.fuel_type == COAL
        end

        @testset "Nuclear plant" begin
            plant = ConventionalThermal(;
                id="NUC_001",
                name="Nuclear Plant 1",
                bus_id="B002",
                submarket_id="SE",
                fuel_type=NUCLEAR,
                capacity_mw=1200.0,
                min_generation_mw=1000.0,
                max_generation_mw=1200.0,
                ramp_up_mw_per_min=10.0,
                ramp_down_mw_per_min=10.0,
                min_up_time_hours=168,  # 1 week
                min_down_time_hours=168,
                fuel_cost_rsj_per_mwh=20.0,
                startup_cost_rs=200000.0,
                shutdown_cost_rs=100000.0,
                must_run=true
            )

            @test plant.fuel_type == NUCLEAR
            @test plant.must_run == true
        end

        @testset "Biomass plant" begin
            plant = ConventionalThermal(;
                id="BIO_001",
                name="Biomass Plant 1",
                bus_id="B003",
                submarket_id="NE",
                fuel_type=BIOMASS,
                capacity_mw=50.0,
                min_generation_mw=10.0,
                max_generation_mw=50.0,
                ramp_up_mw_per_min=5.0,
                ramp_down_mw_per_min=5.0,
                min_up_time_hours=2,
                min_down_time_hours=1,
                fuel_cost_rsj_per_mwh=200.0,
                startup_cost_rs=3000.0,
                shutdown_cost_rs=1000.0
            )

            @test plant.fuel_type == BIOMASS
        end
    end

    @testset "ConventionalThermal - Edge Cases" begin
        @testset "Zero minimum generation" begin
            plant = ConventionalThermal(;
                id="T_001",
                name="Flexible Plant",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=300.0,
                min_generation_mw=0.0,  # Can shut down completely
                max_generation_mw=300.0,
                ramp_up_mw_per_min=30.0,
                ramp_down_mw_per_min=30.0,
                min_up_time_hours=2,
                min_down_time_hours=1,
                fuel_cost_rsj_per_mwh=120.0,
                startup_cost_rs=5000.0,
                shutdown_cost_rs=2000.0
            )

            @test plant.min_generation_mw == 0.0
        end

        @testset "Zero ramp rates" begin
            plant = ConventionalThermal(;
                id="T_001",
                name="Baseload Plant",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=COAL,
                capacity_mw=500.0,
                min_generation_mw=400.0,
                max_generation_mw=500.0,
                ramp_up_mw_per_min=0.0,  # No ramp limits
                ramp_down_mw_per_min=0.0,
                min_up_time_hours=24,
                min_down_time_hours=12,
                fuel_cost_rsj_per_mwh=80.0,
                startup_cost_rs=40000.0,
                shutdown_cost_rs=15000.0
            )

            @test plant.ramp_up_mw_per_min == 0.0
            @test plant.ramp_down_mw_per_min == 0.0
        end

        @testset "Zero minimum time constraints" begin
            plant = ConventionalThermal(;
                id="T_001",
                name="Fast Start Plant",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=100.0,
                min_generation_mw=30.0,
                max_generation_mw=100.0,
                ramp_up_mw_per_min=20.0,
                ramp_down_mw_per_min=20.0,
                min_up_time_hours=0,  # Can start/stop freely
                min_down_time_hours=0,
                fuel_cost_rsj_per_mwh=180.0,
                startup_cost_rs=2000.0,
                shutdown_cost_rs=500.0
            )

            @test plant.min_up_time_hours == 0
            @test plant.min_down_time_hours == 0
        end
    end

    @testset "CombinedCyclePlant - Constructor" begin
        @testset "Valid CCGT plant" begin
            plant = CombinedCyclePlant(;
                id="CCGT_001",
                name="Combined Cycle Plant 1",
                bus_id="SE_230KV_001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=800.0,
                gas_turbine_capacity_mw=500.0,
                steam_turbine_capacity_mw=300.0,
                min_generation_gas_only_mw=200.0,
                min_generation_combined_mw=400.0,
                max_generation_combined_mw=800.0,
                ramp_up_mw_per_min=40.0,
                ramp_down_mw_per_min=40.0,
                min_up_time_hours=8,
                min_down_time_hours=6,
                fuel_cost_rsj_per_mwh=120.0,
                startup_cost_rs=20000.0,
                shutdown_cost_rs=10000.0,
                heat_rate_gas_only=9.5,
                heat_rate_combined=6.5
            )

            @test plant.id == "CCGT_001"
            @test plant.capacity_mw == 800.0
            @test plant.gas_turbine_capacity_mw == 500.0
            @test plant.steam_turbine_capacity_mw == 300.0
            @test plant.min_generation_gas_only_mw == 200.0
            @test plant.min_generation_combined_mw == 400.0
            @test plant.max_generation_combined_mw == 800.0
            @test plant.heat_rate_gas_only == 9.5
            @test plant.heat_rate_combined == 6.5
        end
    end

    @testset "CombinedCyclePlant - Validation" begin
        @testset "Gas + steam capacity != total capacity" begin
            @test_throws ArgumentError CombinedCyclePlant(;
                id="CCGT_001",
                name="Invalid CCGT",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=800.0,
                gas_turbine_capacity_mw=500.0,
                steam_turbine_capacity_mw=400.0,  # 500 + 400 = 900, not 800!
                min_generation_gas_only_mw=200.0,
                min_generation_combined_mw=400.0,
                max_generation_combined_mw=800.0,
                ramp_up_mw_per_min=40.0,
                ramp_down_mw_per_min=40.0,
                min_up_time_hours=8,
                min_down_time_hours=6,
                fuel_cost_rsj_per_mwh=120.0,
                startup_cost_rs=20000.0,
                shutdown_cost_rs=10000.0,
                heat_rate_gas_only=9.5,
                heat_rate_combined=6.5
            )
        end

        @testset "Min gas-only generation > gas turbine capacity" begin
            @test_throws ArgumentError CombinedCyclePlant(;
                id="CCGT_001",
                name="Invalid CCGT",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=800.0,
                gas_turbine_capacity_mw=500.0,
                steam_turbine_capacity_mw=300.0,
                min_generation_gas_only_mw=600.0,  # > 500!
                min_generation_combined_mw=400.0,
                max_generation_combined_mw=800.0,
                ramp_up_mw_per_min=40.0,
                ramp_down_mw_per_min=40.0,
                min_up_time_hours=8,
                min_down_time_hours=6,
                fuel_cost_rsj_per_mwh=120.0,
                startup_cost_rs=20000.0,
                shutdown_cost_rs=10000.0,
                heat_rate_gas_only=9.5,
                heat_rate_combined=6.5
            )
        end

        @testset "Negative heat rates" begin
            @test_throws ArgumentError CombinedCyclePlant(;
                id="CCGT_001",
                name="Invalid CCGT",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=800.0,
                gas_turbine_capacity_mw=500.0,
                steam_turbine_capacity_mw=300.0,
                min_generation_gas_only_mw=200.0,
                min_generation_combined_mw=400.0,
                max_generation_combined_mw=800.0,
                ramp_up_mw_per_min=40.0,
                ramp_down_mw_per_min=40.0,
                min_up_time_hours=8,
                min_down_time_hours=6,
                fuel_cost_rsj_per_mwh=120.0,
                startup_cost_rs=20000.0,
                shutdown_cost_rs=10000.0,
                heat_rate_gas_only=-9.5,  # Invalid!
                heat_rate_combined=6.5
            )
        end

        @testset "Zero heat rate" begin
            @test_throws ArgumentError CombinedCyclePlant(;
                id="CCGT_001",
                name="Invalid CCGT",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=800.0,
                gas_turbine_capacity_mw=500.0,
                steam_turbine_capacity_mw=300.0,
                min_generation_gas_only_mw=200.0,
                min_generation_combined_mw=400.0,
                max_generation_combined_mw=800.0,
                ramp_up_mw_per_min=40.0,
                ramp_down_mw_per_min=40.0,
                min_up_time_hours=8,
                min_down_time_hours=6,
                fuel_cost_rsj_per_mwh=120.0,
                startup_cost_rs=20000.0,
                shutdown_cost_rs=10000.0,
                heat_rate_gas_only=9.5,
                heat_rate_combined=0.0  # Invalid!
            )
        end
    end

    @testset "FuelType Enum" begin
        @testset "All fuel types defined" begin
            @test NATURAL_GAS isa FuelType
            @test COAL isa FuelType
            @test FUEL_OIL isa FuelType
            @test DIESEL isa FuelType
            @test NUCLEAR isa FuelType
            @test BIOMASS isa FuelType
            @test BIOGAS isa FuelType
            @test OTHER isa FuelType
        end

        @testset "Fuel type comparison" begin
            @test NATURAL_GAS == NATURAL_GAS
            @test NATURAL_GAS != COAL
            @test Int(NATURAL_GAS) == 0  # First enum value
            @test Int(COAL) == 1
        end
    end

    @testset "ThermalPlant - Type Hierarchy" begin
        @testset "ConventionalThermal is ThermalPlant" begin
            plant = ConventionalThermal(;
                id="T_001",
                name="Test",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=500.0,
                min_generation_mw=150.0,
                max_generation_mw=500.0,
                ramp_up_mw_per_min=50.0,
                ramp_down_mw_per_min=50.0,
                min_up_time_hours=6,
                min_down_time_hours=4,
                fuel_cost_rsj_per_mwh=150.0,
                startup_cost_rs=15000.0,
                shutdown_cost_rs=8000.0
            )

            @test plant isa ThermalPlant
            @test plant isa PhysicalEntity
            @test plant isa AbstractEntity
        end

        @testset "CombinedCyclePlant is ThermalPlant" begin
            plant = CombinedCyclePlant(;
                id="CCGT_001",
                name="Test CCGT",
                bus_id="B001",
                submarket_id="SE",
                fuel_type=NATURAL_GAS,
                capacity_mw=800.0,
                gas_turbine_capacity_mw=500.0,
                steam_turbine_capacity_mw=300.0,
                min_generation_gas_only_mw=200.0,
                min_generation_combined_mw=400.0,
                max_generation_combined_mw=800.0,
                ramp_up_mw_per_min=40.0,
                ramp_down_mw_per_min=40.0,
                min_up_time_hours=8,
                min_down_time_hours=6,
                fuel_cost_rsj_per_mwh=120.0,
                startup_cost_rs=20000.0,
                shutdown_cost_rs=10000.0,
                heat_rate_gas_only=9.5,
                heat_rate_combined=6.5
            )

            @test plant isa ThermalPlant
            @test plant isa PhysicalEntity
            @test plant isa AbstractEntity
        end
    end
end
