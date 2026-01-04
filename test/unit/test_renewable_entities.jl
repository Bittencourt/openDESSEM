"""
    Test suite for renewable energy plant entities (TASK-002)

Tests for WindPlant and SolarPlant entities with time-varying capacity forecasts
following TDD principles.
"""

using OpenDESSEM
using Test

@testset "Renewable Plant Entities (TASK-002)" begin

    @testset "Enums - RenewableType and ForecastType" begin
        @testset "RenewableType enum values" begin
            @test WIND === OpenDESSEM.WIND
            @test SOLAR === OpenDESSEM.SOLAR
            @test collect(instances(OpenDESSEM.RenewableType)) == [WIND, SOLAR]
        end

        @testset "ForecastType enum values" begin
            @test DETERMINISTIC === OpenDESSEM.DETERMINISTIC
            @test STOCHASTIC === OpenDESSEM.STOCHASTIC
            @test SCENARIO_BASED === OpenDESSEM.SCENARIO_BASED
            @test collect(instances(OpenDESSEM.ForecastType)) ==
                  [DETERMINISTIC, STOCHASTIC, SCENARIO_BASED]
        end
    end

    @testset "WindPlant - Constructor" begin
        @testset "Valid wind plant with 24-hour forecast" begin
            wind = WindPlant(;
                id = "W_NE_001",
                name = "Nordeste Wind Farm 1",
                bus_id = "NE_230KV_001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [
                    180.0,
                    175.0,
                    160.0,
                    150.0,
                    140.0,
                    130.0,
                    125.0,
                    120.0,
                    115.0,
                    110.0,
                    105.0,
                    100.0,
                    95.0,
                    90.0,
                    85.0,
                    80.0,
                    75.0,
                    70.0,
                    65.0,
                    60.0,
                    55.0,
                    50.0,
                    45.0,
                    40.0,
                ],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,  # Consistent with is_dispatchable=false
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2018, 6, 15),
                num_turbines = 50,
                must_run = true,
            )

            @test wind.id == "W_NE_001"
            @test wind.name == "Nordeste Wind Farm 1"
            @test wind.bus_id == "NE_230KV_001"
            @test wind.submarket_id == "NE"
            @test wind.installed_capacity_mw == 200.0
            @test length(wind.capacity_forecast_mw) == 24
            @test wind.capacity_forecast_mw[1] == 180.0
            @test wind.forecast_type == DETERMINISTIC
            @test wind.min_generation_mw == 0.0
            @test wind.max_generation_mw == 200.0
            @test wind.ramp_up_mw_per_min == 10.0
            @test wind.ramp_down_mw_per_min == 10.0
            @test wind.curtailment_allowed == false  # Consistent with is_dispatchable=false
            @test wind.forced_outage_rate == 0.02
            @test wind.is_dispatchable == false
            @test wind.num_turbines == 50
            @test wind.must_run == true
            @test wind isa RenewablePlant
            @test wind isa PhysicalEntity
        end

        @testset "Wind plant with stochastic forecast" begin
            wind = WindPlant(;
                id = "W_SE_002",
                name = "Sudeste Offshore Wind",
                bus_id = "SE_230KV_002",
                submarket_id = "SE",
                installed_capacity_mw = 500.0,
                capacity_forecast_mw = fill(400.0, 168),  # Weekly horizon
                forecast_type = STOCHASTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 500.0,
                ramp_up_mw_per_min = 25.0,
                ramp_down_mw_per_min = 25.0,
                curtailment_allowed = true,
                forced_outage_rate = 0.03,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 3, 10),
                num_turbines = 100,
            )

            @test wind.forecast_type == STOCHASTIC
            @test length(wind.capacity_forecast_mw) == 168
            @test all(wind.capacity_forecast_mw .<= wind.installed_capacity_mw)
        end

        @testset "Default values" begin
            wind = WindPlant(;
                id = "W_003",
                name = "Default Wind",
                bus_id = "B003",
                submarket_id = "SE",
                installed_capacity_mw = 100.0,
                capacity_forecast_mw = [80.0, 75.0, 70.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 5.0,
                ramp_down_mw_per_min = 5.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2019, 1, 1),
            )

            @test wind.num_turbines == 1  # Default
            @test wind.must_run == true  # Default
            @test wind.metadata !== nothing
            @test wind.metadata.version == 1
        end
    end

    @testset "WindPlant - Validation" begin
        @testset "Invalid installed capacity" begin
            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "Negative Capacity",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = -100.0,
                capacity_forecast_mw = [50.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "Zero Capacity",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 0.0,
                capacity_forecast_mw = [50.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )
        end

        @testset "Invalid capacity_forecast_mw" begin
            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "Empty Forecast",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = Float64[],  # Empty
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "Negative Forecast",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [-50.0],  # Negative
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "Forecast Exceeds Capacity",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [250.0],  # > installed capacity
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )
        end

        @testset "Invalid forecast_type" begin
            # NOTE: Julia's type system prevents passing invalid enum values at compile time
            # The ForecastType enum validation is handled by the type system itself
            # This test verifies that all valid enum values are accepted
            for valid_type in [DETERMINISTIC, STOCHASTIC, SCENARIO_BASED]
                wind = WindPlant(;
                    id = "W_001",
                    name = "Valid Forecast Type",
                    bus_id = "B001",
                    submarket_id = "NE",
                    installed_capacity_mw = 200.0,
                    capacity_forecast_mw = [150.0],
                    forecast_type = valid_type,
                    min_generation_mw = 0.0,
                    max_generation_mw = 200.0,
                    ramp_up_mw_per_min = 10.0,
                    ramp_down_mw_per_min = 10.0,
                    curtailment_allowed = false,
                    forced_outage_rate = 0.02,
                    is_dispatchable = false,
                    commissioning_date = DateTime(2020, 1, 1),
                )
                @test wind.forecast_type == valid_type
            end
        end

        @testset "Invalid generation limits" begin
            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "Min > Max",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [150.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 150.0,  # > max_generation_mw
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "Max > Installed",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [150.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 250.0,  # > installed_capacity_mw
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )
        end

        @testset "Invalid forced_outage_rate" begin
            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "High Outage Rate",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [150.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 1.5,  # > 1
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "Negative Outage Rate",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [150.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = -0.1,  # < 0
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )
        end

        @testset "Invalid num_turbines" begin
            @test_throws ArgumentError WindPlant(;
                id = "W_001",
                name = "Zero Turbines",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [150.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
                num_turbines = 0,  # Invalid
            )
        end
    end

    @testset "WindPlant - Curtailment Logic" begin
        @testset "Curtailment with is_dispatchable=true" begin
            wind = WindPlant(;
                id = "W_001",
                name = "Dispatchable Wind",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [150.0, 140.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = true,
                forced_outage_rate = 0.02,
                is_dispatchable = true,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test wind.curtailment_allowed == true
            @test wind.is_dispatchable == true
        end

        @testset "Curtailment warning when is_dispatchable=false" begin
            # This should trigger a warning but not throw an error
            wind = WindPlant(;
                id = "W_002",
                name = "Non-Dispatchable Wind",
                bus_id = "B002",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = [150.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = true,  # Inconsistent with is_dispatchable
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            # After warning, curtailment_allowed should be set to false
            @test wind.curtailment_allowed == false
        end
    end

    @testset "SolarPlant - Constructor" begin
        @testset "Valid solar plant with diurnal pattern" begin
            solar = SolarPlant(;
                id = "S_SE_001",
                name = "Sudeste Solar Farm 1",
                bus_id = "SE_230KV_001",
                submarket_id = "SE",
                installed_capacity_mw = 150.0,
                capacity_forecast_mw = [
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,  # Midnight to 5 AM
                    10.0,
                    30.0,
                    60.0,
                    95.0,
                    130.0,
                    145.0,  # Sunrise to noon
                    140.0,
                    120.0,
                    90.0,
                    50.0,
                    20.0,
                    5.0,  # Afternoon to sunset
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,  # Evening to midnight
                ],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 150.0,
                ramp_up_mw_per_min = 50.0,
                ramp_down_mw_per_min = 50.0,
                curtailment_allowed = true,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2019, 9, 20),
                tracking_system = "SINGLE_AXIS",
                must_run = true,
            )

            @test solar.id == "S_SE_001"
            @test solar.name == "Sudeste Solar Farm 1"
            @test solar.bus_id == "SE_230KV_001"
            @test solar.submarket_id == "SE"
            @test solar.installed_capacity_mw == 150.0
            @test length(solar.capacity_forecast_mw) == 24
            @test solar.capacity_forecast_mw[7] == 10.0  # Sunrise
            @test solar.capacity_forecast_mw[12] == 145.0  # Peak
            @test solar.forecast_type == DETERMINISTIC
            @test solar.min_generation_mw == 0.0
            @test solar.max_generation_mw == 150.0
            @test solar.ramp_up_mw_per_min == 50.0
            @test solar.ramp_down_mw_per_min == 50.0
            @test solar.curtailment_allowed == true
            @test solar.forced_outage_rate == 0.01
            @test solar.is_dispatchable == false
            @test solar.tracking_system == "SINGLE_AXIS"
            @test solar.must_run == true
            @test solar isa RenewablePlant
            @test solar isa PhysicalEntity
        end

        @testset "Solar plant with different tracking systems" begin
            solar_fixed = SolarPlant(;
                id = "S_001",
                name = "Fixed Solar",
                bus_id = "B001",
                submarket_id = "SE",
                installed_capacity_mw = 100.0,
                capacity_forecast_mw = fill(80.0, 24),
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 40.0,
                ramp_down_mw_per_min = 40.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
                tracking_system = "fixed",  # Should be uppercased
            )

            @test solar_fixed.tracking_system == "FIXED"

            solar_dual = SolarPlant(;
                id = "S_002",
                name = "Dual Axis Solar",
                bus_id = "B002",
                submarket_id = "NE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = fill(180.0, 24),
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 75.0,
                ramp_down_mw_per_min = 75.0,
                curtailment_allowed = true,
                forced_outage_rate = 0.015,
                is_dispatchable = false,
                commissioning_date = DateTime(2021, 4, 10),
                tracking_system = "dual_axis",  # Should be uppercased
            )

            @test solar_dual.tracking_system == "DUAL_AXIS"
        end

        @testset "Default values" begin
            solar = SolarPlant(;
                id = "S_003",
                name = "Default Solar",
                bus_id = "B003",
                submarket_id = "SE",
                installed_capacity_mw = 50.0,
                capacity_forecast_mw = [40.0, 35.0, 30.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 50.0,
                ramp_up_mw_per_min = 20.0,
                ramp_down_mw_per_min = 20.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test solar.tracking_system == "FIXED"  # Default
            @test solar.must_run == true  # Default
            @test solar.metadata !== nothing
            @test solar.metadata.version == 1
        end
    end

    @testset "SolarPlant - Validation" begin
        @testset "Invalid tracking_system" begin
            @test_throws ArgumentError SolarPlant(;
                id = "S_001",
                name = "Invalid Tracking",
                bus_id = "B001",
                submarket_id = "SE",
                installed_capacity_mw = 150.0,
                capacity_forecast_mw = [100.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 150.0,
                ramp_up_mw_per_min = 50.0,
                ramp_down_mw_per_min = 50.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
                tracking_system = "INVALID_TRACKING",
            )
        end

        @testset "Invalid installed capacity" begin
            @test_throws ArgumentError SolarPlant(;
                id = "S_001",
                name = "Zero Capacity",
                bus_id = "B001",
                submarket_id = "SE",
                installed_capacity_mw = 0.0,
                capacity_forecast_mw = [100.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 150.0,
                ramp_up_mw_per_min = 50.0,
                ramp_down_mw_per_min = 50.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )
        end

        @testset "Invalid capacity_forecast_mw" begin
            @test_throws ArgumentError SolarPlant(;
                id = "S_001",
                name = "Empty Forecast",
                bus_id = "B001",
                submarket_id = "SE",
                installed_capacity_mw = 150.0,
                capacity_forecast_mw = Float64[],  # Empty
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 150.0,
                ramp_up_mw_per_min = 50.0,
                ramp_down_mw_per_min = 50.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test_throws ArgumentError SolarPlant(;
                id = "S_001",
                name = "Forecast Exceeds Capacity",
                bus_id = "B001",
                submarket_id = "SE",
                installed_capacity_mw = 150.0,
                capacity_forecast_mw = [200.0],  # > installed
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 150.0,
                ramp_up_mw_per_min = 50.0,
                ramp_down_mw_per_min = 50.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )
        end
    end

    @testset "RenewablePlant - Type Hierarchy" begin
        @testset "WindPlant type hierarchy" begin
            wind = WindPlant(;
                id = "W_001",
                name = "Test Wind",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 100.0,
                capacity_forecast_mw = [80.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 5.0,
                ramp_down_mw_per_min = 5.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test wind isa RenewablePlant
            @test wind isa PhysicalEntity
            @test wind isa AbstractEntity
            @test RenewablePlant <: PhysicalEntity
            @test PhysicalEntity <: AbstractEntity
        end

        @testset "SolarPlant type hierarchy" begin
            solar = SolarPlant(;
                id = "S_001",
                name = "Test Solar",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 100.0,
                capacity_forecast_mw = [80.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 40.0,
                ramp_down_mw_per_min = 40.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test solar isa RenewablePlant
            @test solar isa PhysicalEntity
            @test solar isa AbstractEntity
        end
    end

    @testset "RenewablePlant - Edge Cases" begin
        @testset "Zero capacity forecast values" begin
            wind = WindPlant(;
                id = "W_001",
                name = "Zero Forecast Wind",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 100.0,
                capacity_forecast_mw = [0.0, 0.0, 0.0],  # All zeros
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 5.0,
                ramp_down_mw_per_min = 5.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test all(wind.capacity_forecast_mw .== 0.0)

            solar = SolarPlant(;
                id = "S_001",
                name = "Zero Forecast Solar",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 100.0,
                capacity_forecast_mw = [0.0, 0.0, 0.0],  # Night time
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 40.0,
                ramp_down_mw_per_min = 40.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test all(solar.capacity_forecast_mw .== 0.0)
        end

        @testset "Very large capacity forecast" begin
            wind = WindPlant(;
                id = "W_001",
                name = "Large Wind Farm",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 1000.0,
                capacity_forecast_mw = fill(950.0, 168),  # Weekly horizon
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 1000.0,
                ramp_up_mw_per_min = 50.0,
                ramp_down_mw_per_min = 50.0,
                curtailment_allowed = true,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
                num_turbines = 200,
            )

            @test wind.installed_capacity_mw == 1000.0
            @test length(wind.capacity_forecast_mw) == 168
            @test wind.num_turbines == 200

            solar = SolarPlant(;
                id = "S_001",
                name = "Large Solar Farm",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 500.0,
                capacity_forecast_mw = fill(450.0, 24),
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 500.0,
                ramp_up_mw_per_min = 100.0,
                ramp_down_mw_per_min = 100.0,
                curtailment_allowed = true,
                forced_outage_rate = 0.01,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test solar.installed_capacity_mw == 500.0
        end

        @testset "Ramp rate edge cases" begin
            # Zero ramp rates
            wind = WindPlant(;
                id = "W_001",
                name = "Zero Ramp Wind",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 100.0,
                capacity_forecast_mw = [80.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 0.0,  # Zero allowed
                ramp_down_mw_per_min = 0.0,  # Zero allowed
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test wind.ramp_up_mw_per_min == 0.0
            @test wind.ramp_down_mw_per_min == 0.0
        end
    end

    @testset "RenewablePlant - Forecast Dimension Validation" begin
        @testset "Different forecast horizons" begin
            # Hourly (24 periods)
            wind_24h = WindPlant(;
                id = "W_001",
                name = "24h Wind",
                bus_id = "B001",
                submarket_id = "NE",
                installed_capacity_mw = 100.0,
                capacity_forecast_mw = fill(80.0, 24),
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 5.0,
                ramp_down_mw_per_min = 5.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test length(wind_24h.capacity_forecast_mw) == 24

            # Weekly (168 periods)
            wind_weekly = WindPlant(;
                id = "W_002",
                name = "Weekly Wind",
                bus_id = "B002",
                submarket_id = "SE",
                installed_capacity_mw = 200.0,
                capacity_forecast_mw = fill(150.0, 168),
                forecast_type = STOCHASTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 200.0,
                ramp_up_mw_per_min = 10.0,
                ramp_down_mw_per_min = 10.0,
                curtailment_allowed = false,
                forced_outage_rate = 0.03,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
            )

            @test length(wind_weekly.capacity_forecast_mw) == 168
        end
    end

end
