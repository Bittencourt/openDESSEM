"""
    Test ElectricitySystem container

Tests for the unified ElectricitySystem container that holds all power system entities.
"""

using OpenDESSEM
using Test
using Dates

@testset "ElectricitySystem Container" begin

    # Common test fixtures
    function create_test_bus(; id = "B001")
        Bus(; id = id, name = "Test Bus", voltage_kv = 230.0, base_kv = 230.0)
    end

    function create_test_submarket(; code = "SE")
        Submarket(;
            id = "SM_$(code)",
            name = "$(code) Submarket",
            code = code,
            country = "Brazil",
        )
    end

    @testset "Constructor - Empty System" begin
        # Test creating an empty system
        system = ElectricitySystem(;
            base_date = Date(2025, 1, 1),
            description = "Empty test system",
        )

        @test system.base_date == Date(2025, 1, 1)
        @test system.description == "Empty test system"
        @test isempty(system.thermal_plants)
        @test isempty(system.hydro_plants)
        @test isempty(system.wind_farms)
        @test isempty(system.solar_farms)
        @test isempty(system.buses)
        @test isempty(system.ac_lines)
        @test isempty(system.dc_lines)
        @test isempty(system.submarkets)
        @test isempty(system.loads)
        @test system.version == "1.0"
    end

    @testset "Constructor - With Thermal Plants" begin
        plant1 = ConventionalThermal(;
            id = "T001",
            name = "Thermal Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 150.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 6,
            min_down_time_hours = 4,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 15000.0,
            shutdown_cost_rs = 8000.0,
            commissioning_date = DateTime(2010, 1, 1),
        )

        plant2 = ConventionalThermal(;
            id = "T002",
            name = "Thermal Plant 2",
            bus_id = "B001",
            submarket_id = "SE",
            fuel_type = COAL,
            capacity_mw = 800.0,
            min_generation_mw = 200.0,
            max_generation_mw = 800.0,
            ramp_up_mw_per_min = 40.0,
            ramp_down_mw_per_min = 40.0,
            min_up_time_hours = 8,
            min_down_time_hours = 6,
            fuel_cost_rsj_per_mwh = 100.0,
            startup_cost_rs = 25000.0,
            shutdown_cost_rs = 12000.0,
            commissioning_date = DateTime(2005, 1, 1),
        )

        system = ElectricitySystem(;
            thermal_plants = [plant1, plant2],
            buses = [create_test_bus()],
            submarkets = [create_test_submarket()],
            base_date = Date(2025, 1, 1),
        )

        @test length(system.thermal_plants) == 2
        @test system.thermal_plants[1].id == "T001"
        @test system.thermal_plants[2].id == "T002"
    end

    @testset "Constructor - With Hydro Plants" begin
        hydro1 = ReservoirHydro(;
            id = "H001",
            name = "Hydro Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            max_volume_hm3 = 10000.0,
            min_volume_hm3 = 1000.0,
            initial_volume_hm3 = 5000.0,
            max_outflow_m3_per_s = 5000.0,
            min_outflow_m3_per_s = 100.0,
            max_generation_mw = 1000.0,
            min_generation_mw = 0.0,
            efficiency = 0.90,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = 1,
            initial_volume_percent = 50.0,
        )

        system = ElectricitySystem(;
            hydro_plants = [hydro1],
            buses = [create_test_bus()],
            submarkets = [create_test_submarket()],
            base_date = Date(2025, 1, 1),
        )

        @test length(system.hydro_plants) == 1
        @test system.hydro_plants[1].id == "H001"
    end

    @testset "Constructor - With Wind Farms" begin
        wind1 = WindPlant(;
            id = "W001",
            name = "Wind Farm 1",
            bus_id = "B001",
            submarket_id = "NE",
            installed_capacity_mw = 200.0,
            capacity_forecast_mw = [180.0, 190.0, 200.0],
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = 200.0,
            ramp_up_mw_per_min = 20.0,
            ramp_down_mw_per_min = 20.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.05,
            is_dispatchable = false,
            commissioning_date = DateTime(2015, 1, 1),
            num_turbines = 50,
        )

        system = ElectricitySystem(;
            wind_farms = [wind1],
            buses = [create_test_bus()],
            submarkets = [create_test_submarket(code = "NE")],
            base_date = Date(2025, 1, 1),
        )

        @test length(system.wind_farms) == 1
        @test system.wind_farms[1].id == "W001"
    end

    @testset "Constructor - With Solar Farms" begin
        solar1 = SolarPlant(;
            id = "S001",
            name = "Solar Farm 1",
            bus_id = "B001",
            submarket_id = "NE",
            installed_capacity_mw = 100.0,
            capacity_forecast_mw = fill(80.0, 24),
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = 100.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.02,
            is_dispatchable = false,
            commissioning_date = DateTime(2018, 1, 1),
            tracking_system = "FIXED",
        )

        system = ElectricitySystem(;
            solar_farms = [solar1],
            buses = [create_test_bus()],
            submarkets = [create_test_submarket(code = "NE")],
            base_date = Date(2025, 1, 1),
        )

        @test length(system.solar_farms) == 1
        @test system.solar_farms[1].id == "S001"
    end

    @testset "Constructor - With Network Entities" begin
        bus1 = Bus(;
            id = "B001",
            name = "Bus 1",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = true,
            area_id = "SE",
        )

        bus2 = Bus(;
            id = "B002",
            name = "Bus 2",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = false,
            area_id = "SE",
        )

        line1 = ACLine(;
            id = "L001",
            name = "Line 1",
            from_bus_id = "B001",
            to_bus_id = "B002",
            length_km = 100.0,
            resistance_ohm = 0.01,
            reactance_ohm = 0.1,
            susceptance_siemen = 0.0,
            max_flow_mw = 500.0,
            min_flow_mw = 0.0,
            num_circuits = 1,
        )

        system = ElectricitySystem(;
            buses = [bus1, bus2],
            ac_lines = [line1],
            base_date = Date(2025, 1, 1),
        )

        @test length(system.buses) == 2
        @test length(system.ac_lines) == 1
        @test system.buses[1].id == "B001"
        @test system.ac_lines[1].from_bus_id == "B001"
    end

    @testset "Constructor - With Market Entities" begin
        submarket1 = Submarket(;
            id = "SM_001",
            name = "Southeast",
            code = "SE",
            country = "Brazil",
            description = "Southeast submarket",
        )

        load1 = Load(;
            id = "LOAD_001",
            name = "Southeast Load",
            submarket_id = "SE",
            base_mw = 50000.0,
            load_profile = ones(168),
            is_elastic = false,
        )

        system = ElectricitySystem(;
            submarkets = [submarket1],
            loads = [load1],
            base_date = Date(2025, 1, 1),
        )

        @test length(system.submarkets) == 1
        @test length(system.loads) == 1
        @test system.submarkets[1].code == "SE"
        @test system.loads[1].base_mw == 50000.0
    end

    @testset "Constructor - Complete System" begin
        # Create a complete system with all entity types
        plant1 = ConventionalThermal(;
            id = "T001",
            name = "Thermal Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 150.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 6,
            min_down_time_hours = 4,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 15000.0,
            shutdown_cost_rs = 8000.0,
            commissioning_date = DateTime(2010, 1, 1),
        )

        hydro1 = ReservoirHydro(;
            id = "H001",
            name = "Hydro Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            max_volume_hm3 = 10000.0,
            min_volume_hm3 = 1000.0,
            initial_volume_hm3 = 5000.0,
            max_outflow_m3_per_s = 5000.0,
            min_outflow_m3_per_s = 100.0,
            max_generation_mw = 1000.0,
            min_generation_mw = 0.0,
            efficiency = 0.90,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = 1,
            initial_volume_percent = 50.0,
        )

        wind1 = WindPlant(;
            id = "W001",
            name = "Wind Farm 1",
            bus_id = "B001",
            submarket_id = "SE",
            installed_capacity_mw = 200.0,
            capacity_forecast_mw = [180.0, 190.0, 200.0],
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = 200.0,
            ramp_up_mw_per_min = 20.0,
            ramp_down_mw_per_min = 20.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.05,
            is_dispatchable = false,
            commissioning_date = DateTime(2015, 1, 1),
            num_turbines = 50,
        )

        bus1 = Bus(;
            id = "B001",
            name = "Bus 1",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = true,
            area_id = "SE",
        )

        bus2 = Bus(;
            id = "B002",
            name = "Bus 2",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = false,
            area_id = "SE",
        )

        line1 = ACLine(;
            id = "L001",
            name = "Line 1",
            from_bus_id = "B001",
            to_bus_id = "B002",
            length_km = 100.0,
            resistance_ohm = 0.01,
            reactance_ohm = 0.1,
            susceptance_siemen = 0.0,
            max_flow_mw = 500.0,
            min_flow_mw = 0.0,
            num_circuits = 1,
        )

        submarket1 = Submarket(;
            id = "SM_001",
            name = "Southeast",
            code = "SE",
            country = "Brazil",
            description = "Southeast submarket",
        )

        load1 = Load(;
            id = "LOAD_001",
            name = "Southeast Load",
            submarket_id = "SE",
            base_mw = 50000.0,
            load_profile = ones(168),
            is_elastic = false,
        )

        system = ElectricitySystem(;
            thermal_plants = [plant1],
            hydro_plants = [hydro1],
            wind_farms = [wind1],
            buses = [bus1, bus2],
            ac_lines = [line1],
            submarkets = [submarket1],
            loads = [load1],
            base_date = Date(2025, 1, 1),
            description = "Complete test system",
            version = "1.0",
        )

        @test length(system.thermal_plants) == 1
        @test length(system.hydro_plants) == 1
        @test length(system.wind_farms) == 1
        @test length(system.buses) == 2
        @test length(system.ac_lines) == 1
        @test length(system.submarkets) == 1
        @test length(system.loads) == 1
        @test system.description == "Complete test system"
    end

    @testset "Validation - Duplicate Thermal Plant IDs" begin
        plant1 = ConventionalThermal(;
            id = "T001",
            name = "Thermal Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 150.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 6,
            min_down_time_hours = 4,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 15000.0,
            shutdown_cost_rs = 8000.0,
            commissioning_date = DateTime(2010, 1, 1),
        )

        plant2 = ConventionalThermal(;
            id = "T001",  # Duplicate ID
            name = "Thermal Plant 2",
            bus_id = "B002",
            submarket_id = "SE",
            fuel_type = COAL,
            capacity_mw = 800.0,
            min_generation_mw = 200.0,
            max_generation_mw = 800.0,
            ramp_up_mw_per_min = 40.0,
            ramp_down_mw_per_min = 40.0,
            min_up_time_hours = 8,
            min_down_time_hours = 6,
            fuel_cost_rsj_per_mwh = 100.0,
            startup_cost_rs = 25000.0,
            shutdown_cost_rs = 12000.0,
            commissioning_date = DateTime(2005, 1, 1),
        )

        @test_throws ArgumentError ElectricitySystem(;
            thermal_plants = [plant1, plant2],
            base_date = Date(2025, 1, 1),
        )
    end

    @testset "Validation - Duplicate Bus IDs" begin
        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)

        bus2 = Bus(;
            id = "B001",  # Duplicate ID
            name = "Bus 2",
            voltage_kv = 230.0,
            base_kv = 230.0,
        )

        @test_throws ArgumentError ElectricitySystem(;
            buses = [bus1, bus2],
            base_date = Date(2025, 1, 1),
        )
    end

    @testset "Validation - Missing Bus Reference" begin
        plant1 = ConventionalThermal(;
            id = "T001",
            name = "Thermal Plant 1",
            bus_id = "B999",  # Non-existent bus
            submarket_id = "SE",
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 150.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 6,
            min_down_time_hours = 4,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 15000.0,
            shutdown_cost_rs = 8000.0,
            commissioning_date = DateTime(2010, 1, 1),
        )

        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)

        @test_throws ArgumentError ElectricitySystem(;
            thermal_plants = [plant1],
            buses = [bus1],
            base_date = Date(2025, 1, 1),
        )
    end

    @testset "Validation - Missing Submarket Reference" begin
        plant1 = ConventionalThermal(;
            id = "T001",
            name = "Thermal Plant 1",
            bus_id = "B001",
            submarket_id = "XX",  # Non-existent submarket
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 150.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 6,
            min_down_time_hours = 4,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 15000.0,
            shutdown_cost_rs = 8000.0,
            commissioning_date = DateTime(2010, 1, 1),
        )

        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)

        submarket1 =
            Submarket(; id = "SM_001", name = "Southeast", code = "SE", country = "Brazil")

        @test_throws ArgumentError ElectricitySystem(;
            thermal_plants = [plant1],
            buses = [bus1],
            submarkets = [submarket1],
            base_date = Date(2025, 1, 1),
        )
    end

    @testset "Validation - AC Line with Missing Bus" begin
        line1 = ACLine(;
            id = "L001",
            name = "Line 1",
            from_bus_id = "B001",
            to_bus_id = "B999",  # Non-existent bus
            length_km = 100.0,
            resistance_ohm = 0.01,
            reactance_ohm = 0.1,
            susceptance_siemen = 0.0,
            max_flow_mw = 500.0,
            min_flow_mw = 0.0,
            num_circuits = 1,
        )

        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)

        @test_throws ArgumentError ElectricitySystem(;
            ac_lines = [line1],
            buses = [bus1],
            base_date = Date(2025, 1, 1),
        )
    end

    @testset "Helper Functions - get_thermal_plant" begin
        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)
        plant1 = ConventionalThermal(;
            id = "T001",
            name = "Thermal Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 150.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 6,
            min_down_time_hours = 4,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 15000.0,
            shutdown_cost_rs = 8000.0,
            commissioning_date = DateTime(2010, 1, 1),
        )

        submarket1 =
            Submarket(; id = "SM_SE", name = "Sudeste", code = "SE", country = "Brazil")
        system = ElectricitySystem(;
            thermal_plants = [plant1],
            buses = [bus1],
            submarkets = [submarket1],
            base_date = Date(2025, 1, 1),
        )

        # Test finding existing plant
        plant = get_thermal_plant(system, "T001")
        @test plant !== nothing
        @test plant.id == "T001"
        @test plant.name == "Thermal Plant 1"

        # Test non-existent plant
        plant = get_thermal_plant(system, "T999")
        @test plant === nothing
    end

    @testset "Helper Functions - get_hydro_plant" begin
        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)
        hydro1 = ReservoirHydro(;
            id = "H001",
            name = "Hydro Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            max_volume_hm3 = 10000.0,
            min_volume_hm3 = 1000.0,
            initial_volume_hm3 = 5000.0,
            max_outflow_m3_per_s = 5000.0,
            min_outflow_m3_per_s = 100.0,
            max_generation_mw = 1000.0,
            min_generation_mw = 0.0,
            efficiency = 0.90,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = 1,
            initial_volume_percent = 50.0,
        )

        submarket1 =
            Submarket(; id = "SM_SE", name = "Sudeste", code = "SE", country = "Brazil")
        system = ElectricitySystem(;
            hydro_plants = [hydro1],
            buses = [bus1],
            submarkets = [submarket1],
            base_date = Date(2025, 1, 1),
        )

        # Test finding existing plant
        plant = get_hydro_plant(system, "H001")
        @test plant !== nothing
        @test plant.id == "H001"

        # Test non-existent plant
        plant = get_hydro_plant(system, "H999")
        @test plant === nothing
    end

    @testset "Helper Functions - get_bus" begin
        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)

        system = ElectricitySystem(; buses = [bus1], base_date = Date(2025, 1, 1))

        # Test finding existing bus
        bus = get_bus(system, "B001")
        @test bus !== nothing
        @test bus.id == "B001"

        # Test non-existent bus
        bus = get_bus(system, "B999")
        @test bus === nothing
    end

    @testset "Helper Functions - get_submarket" begin
        submarket1 =
            Submarket(; id = "SM_001", name = "Southeast", code = "SE", country = "Brazil")

        system =
            ElectricitySystem(; submarkets = [submarket1], base_date = Date(2025, 1, 1))

        # Test finding existing submarket
        submarket = get_submarket(system, "SM_001")
        @test submarket !== nothing
        @test submarket.id == "SM_001"

        # Test non-existent submarket
        submarket = get_submarket(system, "SM_999")
        @test submarket === nothing
    end

    @testset "Helper Functions - count_generators" begin
        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)
        plant1 = ConventionalThermal(;
            id = "T001",
            name = "Thermal Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 150.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 6,
            min_down_time_hours = 4,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 15000.0,
            shutdown_cost_rs = 8000.0,
            commissioning_date = DateTime(2010, 1, 1),
        )

        hydro1 = ReservoirHydro(;
            id = "H001",
            name = "Hydro Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            max_volume_hm3 = 10000.0,
            min_volume_hm3 = 1000.0,
            initial_volume_hm3 = 5000.0,
            max_outflow_m3_per_s = 5000.0,
            min_outflow_m3_per_s = 100.0,
            max_generation_mw = 1000.0,
            min_generation_mw = 0.0,
            efficiency = 0.90,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = 1,
            initial_volume_percent = 50.0,
        )

        wind1 = WindPlant(;
            id = "W001",
            name = "Wind Farm 1",
            bus_id = "B001",
            submarket_id = "SE",
            installed_capacity_mw = 200.0,
            capacity_forecast_mw = [180.0],
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = 200.0,
            ramp_up_mw_per_min = 20.0,
            ramp_down_mw_per_min = 20.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.05,
            is_dispatchable = false,
            commissioning_date = DateTime(2015, 1, 1),
            num_turbines = 50,
        )

        submarket1 =
            Submarket(; id = "SM_SE", name = "Sudeste", code = "SE", country = "Brazil")
        system = ElectricitySystem(;
            thermal_plants = [plant1],
            hydro_plants = [hydro1],
            wind_farms = [wind1],
            buses = [bus1],
            submarkets = [submarket1],
            base_date = Date(2025, 1, 1),
        )

        @test count_generators(system) == 3
    end

    @testset "Helper Functions - total_capacity" begin
        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)
        plant1 = ConventionalThermal(;
            id = "T001",
            name = "Thermal Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 150.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 6,
            min_down_time_hours = 4,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 15000.0,
            shutdown_cost_rs = 8000.0,
            commissioning_date = DateTime(2010, 1, 1),
        )

        hydro1 = ReservoirHydro(;
            id = "H001",
            name = "Hydro Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            max_volume_hm3 = 10000.0,
            min_volume_hm3 = 1000.0,
            initial_volume_hm3 = 5000.0,
            max_outflow_m3_per_s = 5000.0,
            min_outflow_m3_per_s = 100.0,
            max_generation_mw = 1000.0,
            min_generation_mw = 0.0,
            efficiency = 0.90,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = 1,
            initial_volume_percent = 50.0,
        )

        wind1 = WindPlant(;
            id = "W001",
            name = "Wind Farm 1",
            bus_id = "B001",
            submarket_id = "SE",
            installed_capacity_mw = 200.0,
            capacity_forecast_mw = [180.0],
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = 200.0,
            ramp_up_mw_per_min = 20.0,
            ramp_down_mw_per_min = 20.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.05,
            is_dispatchable = false,
            commissioning_date = DateTime(2015, 1, 1),
            num_turbines = 50,
        )

        solar1 = SolarPlant(;
            id = "S001",
            name = "Solar Farm 1",
            bus_id = "B001",
            submarket_id = "SE",
            installed_capacity_mw = 100.0,
            capacity_forecast_mw = fill(80.0, 24),
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = 100.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.02,
            is_dispatchable = false,
            commissioning_date = DateTime(2018, 1, 1),
            tracking_system = "FIXED",
        )

        submarket1 =
            Submarket(; id = "SM_SE", name = "Sudeste", code = "SE", country = "Brazil")
        system = ElectricitySystem(;
            thermal_plants = [plant1],
            hydro_plants = [hydro1],
            wind_farms = [wind1],
            solar_farms = [solar1],
            buses = [bus1],
            submarkets = [submarket1],
            base_date = Date(2025, 1, 1),
        )

        # Total capacity = 500 + 1000 + 200 + 100 = 1800 MW
        @test total_capacity(system) ≈ 1800.0
    end

    @testset "Helper Functions - validate_system" begin
        # Create a valid system
        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)

        plant1 = ConventionalThermal(;
            id = "T001",
            name = "Thermal Plant 1",
            bus_id = "B001",
            submarket_id = "SE",
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 150.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 6,
            min_down_time_hours = 4,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 15000.0,
            shutdown_cost_rs = 8000.0,
            commissioning_date = DateTime(2010, 1, 1),
        )

        submarket1 =
            Submarket(; id = "SM_001", name = "Southeast", code = "SE", country = "Brazil")

        valid_system = ElectricitySystem(;
            buses = [bus1],
            thermal_plants = [plant1],
            submarkets = [submarket1],
            base_date = Date(2025, 1, 1),
        )

        @test validate_system(valid_system) == true
    end

    @testset "Edge Cases - Empty System" begin
        system = ElectricitySystem(; base_date = Date(2025, 1, 1))

        @test count_generators(system) == 0
        @test total_capacity(system) ≈ 0.0
        @test get_thermal_plant(system, "T001") === nothing
        @test get_hydro_plant(system, "H001") === nothing
        @test get_bus(system, "B001") === nothing
        @test get_submarket(system, "SM_001") === nothing
    end

    @testset "Edge Cases - System with Only Buses" begin
        bus1 = Bus(; id = "B001", name = "Bus 1", voltage_kv = 230.0, base_kv = 230.0)

        system = ElectricitySystem(; buses = [bus1], base_date = Date(2025, 1, 1))

        @test count_generators(system) == 0
        @test total_capacity(system) ≈ 0.0
        @test validate_system(system) == true
    end

end
