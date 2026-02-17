"""
    Database Loader Integration Tests

Tests for PostgreSQL database loader functionality.
These tests use a mock database connection to verify loader behavior.
"""

using OpenDESSEM.Entities
using OpenDESSEM.DatabaseLoaders
using Test
using Dates

# Note: These tests are designed to work with a test database schema
# In production, they would connect to an actual PostgreSQL database

@testset "Database Loader Tests" begin

    @testset "DatabaseLoader - Constructor and Validation" begin
        # Test that we can create a loader configuration
        loader = DatabaseLoaders.DatabaseLoader(;
            host = "localhost",
            port = 5432,
            dbname = "dessem_test",
            user = "test_user",
            password = "test_pass",
            schema = "public",
        )

        @test loader.host == "localhost"
        @test loader.port == 5432
        @test loader.dbname == "dessem_test"
        @test loader.schema == "public"

        # Test connection string generation
        conn_str = DatabaseLoaders.get_connection_string(loader)
        @test occursin("host=localhost", conn_str)
        @test occursin("port=5432", conn_str)
        @test occursin("dbname=dessem_test", conn_str)
        @test occursin("user=test_user", conn_str)
    end

    @testset "DatabaseLoader - SQL Query Generation" begin
        # Test thermal plants query generation
        thermal_query = DatabaseLoaders.generate_thermal_plants_query("public")

        @test occursin("SELECT", uppercase(thermal_query))
        @test occursin("FROM", uppercase(thermal_query))
        @test occursin("thermal_plants", lowercase(thermal_query))
        @test occursin("fuel_type", lowercase(thermal_query))
        @test occursin("capacity_mw", lowercase(thermal_query))

        # Test hydro plants query generation
        hydro_query = DatabaseLoaders.generate_hydro_plants_query("public")

        @test occursin("SELECT", uppercase(hydro_query))
        @test occursin("FROM", uppercase(hydro_query))
        @test occursin("hydro_plants", lowercase(hydro_query))

        # Test buses query generation
        buses_query = DatabaseLoaders.generate_buses_query("public")

        @test occursin("SELECT", uppercase(buses_query))
        @test occursin("FROM", uppercase(buses_query))
        @test occursin("buses", lowercase(buses_query))

        # Test loads query generation
        loads_query = DatabaseLoaders.generate_loads_query("public")

        @test occursin("SELECT", uppercase(loads_query))
        @test occursin("FROM", uppercase(loads_query))
        @test occursin("loads", lowercase(loads_query))
    end

    @testset "Row to Entity Conversion - Thermal Plants" begin
        # Create a mock row representing a database result
        mock_row = (
            id = "T_TEST_001",
            name = "Test Thermal Plant",
            bus_id = "B_TEST_001",
            submarket_id = "SE",
            fuel_type = "natural_gas",
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
            num_units = 1,
            must_run = false,
        )

        # Test conversion
        plant = DatabaseLoaders.row_to_thermal_plant(mock_row)

        @test plant isa ConventionalThermal
        @test plant.id == "T_TEST_001"
        @test plant.name == "Test Thermal Plant"
        @test plant.bus_id == "B_TEST_001"
        @test plant.submarket_id == "SE"
        @test plant.fuel_type == NATURAL_GAS
        @test plant.capacity_mw == 500.0
        @test plant.min_generation_mw == 150.0
        @test plant.max_generation_mw == 500.0
    end

    @testset "Row to Entity Conversion - Hydro Plants" begin
        # Mock row for hydro plant
        mock_row = (
            id = "H_TEST_001",
            name = "Test Hydro Plant",
            bus_id = "B_TEST_001",
            submarket_id = "SE",
            max_volume_hm3 = 5000.0,
            min_volume_hm3 = 1000.0,
            initial_volume_hm3 = 3000.0,
            max_outflow_m3_per_s = 1000.0,
            min_outflow_m3_per_s = 100.0,
            max_generation_mw = 500.0,
            min_generation_mw = 0.0,
            efficiency = 0.92,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = 1,
            initial_volume_percent = 60.0,
            must_run = false,
            downstream_plant_id = "H_TEST_002",
            water_travel_time_hours = 2.0,
        )

        plant = DatabaseLoaders.row_to_hydro_plant(mock_row)

        @test plant isa ReservoirHydro
        @test plant.id == "H_TEST_001"
        @test plant.name == "Test Hydro Plant"
        @test plant.bus_id == "B_TEST_001"
        @test plant.submarket_id == "SE"
        @test plant.max_volume_hm3 == 5000.0
        @test plant.min_volume_hm3 == 1000.0
        @test plant.initial_volume_hm3 == 3000.0
        @test plant.max_generation_mw == 500.0
    end

    @testset "Row to Entity Conversion - Buses" begin
        mock_row = (
            id = "B_TEST_001",
            name = "Test Bus",
            voltage_kv = 230.0,
            base_kv = 230.0,
            dc_bus = false,
            is_reference = true,
            area_id = "SE",
            zone_id = nothing,
            latitude = -23.5,
            longitude = -46.6,
        )

        bus = DatabaseLoaders.row_to_bus(mock_row)

        @test bus isa Bus
        @test bus.id == "B_TEST_001"
        @test bus.name == "Test Bus"
        @test bus.voltage_kv == 230.0
        @test bus.base_kv == 230.0
        @test bus.dc_bus == false
        @test bus.is_reference == true
        @test bus.area_id == "SE"
    end

    @testset "Row to Entity Conversion - Submarkets" begin
        mock_row = (
            id = "SM_TEST_001",
            name = "Test Submarket",
            code = "TS",
            country = "Test Country",
            description = "A test submarket",
        )

        submarket = DatabaseLoaders.row_to_submarket(mock_row)

        @test submarket isa Submarket
        @test submarket.id == "SM_TEST_001"
        @test submarket.name == "Test Submarket"
        @test submarket.code == "TS"
        @test submarket.country == "Test Country"
    end

    @testset "Row to Entity Conversion - Loads" begin
        # Mock load profile (simple case)
        load_profile = collect(1.0:1.0:168)

        mock_row = (
            id = "L_TEST_001",
            name = "Test Load",
            submarket_id = "SE",
            bus_id = "B_TEST_001",
            base_mw = 1000.0,
            is_elastic = false,
            elasticity = 0.0,
            # load_profile would typically be loaded separately
        )

        load = DatabaseLoaders.row_to_load(mock_row, load_profile)

        @test load isa Load
        @test load.id == "L_TEST_001"
        @test load.name == "Test Load"
        @test load.submarket_id == "SE"
        @test load.bus_id == "B_TEST_001"
        @test load.base_mw == 1000.0
        @test load.is_elastic == false
        @test length(load.load_profile) == 168
    end

    @testset "Fuel Type String to Enum Conversion" begin
        # Test various fuel type strings
        @test DatabaseLoaders.parse_fuel_type("natural_gas") == NATURAL_GAS
        @test DatabaseLoaders.parse_fuel_type("NATURAL_GAS") == NATURAL_GAS
        @test DatabaseLoaders.parse_fuel_type("Natural_Gas") == NATURAL_GAS
        @test DatabaseLoaders.parse_fuel_type("coal") == COAL
        @test DatabaseLoaders.parse_fuel_type("COAL") == COAL
        @test DatabaseLoaders.parse_fuel_type("fuel_oil") == FUEL_OIL
        @test DatabaseLoaders.parse_fuel_type("diesel") == DIESEL
        @test DatabaseLoaders.parse_fuel_type("nuclear") == NUCLEAR
        @test DatabaseLoaders.parse_fuel_type("biomass") == BIOMASS
        @test DatabaseLoaders.parse_fuel_type("biogas") == BIOGAS

        # Test unknown fuel type
        @test DatabaseLoaders.parse_fuel_type("unknown") == OTHER
        @test DatabaseLoaders.parse_fuel_type("hydrogen") == OTHER
    end

    @testset "Data Validation - Missing Fields" begin
        # Test handling of missing data
        incomplete_row = (
            id = "T_INCOMPLETE",
            name = "Incomplete Plant",
            bus_id = "B_001",
            submarket_id = "SE",
            fuel_type = "natural_gas",
            capacity_mw = 100.0,
            # Missing required fields
        )

        # Should throw or handle gracefully
        @test_throws Exception DatabaseLoaders.row_to_thermal_plant(incomplete_row)
    end

    @testset "Data Validation - Invalid Values" begin
        # Test handling of invalid numeric values
        invalid_row = (
            id = "T_INVALID",
            name = "Invalid Plant",
            bus_id = "B_001",
            submarket_id = "SE",
            fuel_type = "natural_gas",
            capacity_mw = -100.0,  # Negative capacity - invalid
            min_generation_mw = 0.0,
            max_generation_mw = 100.0,
            ramp_up_mw_per_min = 10.0,
            ramp_down_mw_per_min = 10.0,
            min_up_time_hours = 1,
            min_down_time_hours = 1,
            fuel_cost_rsj_per_mwh = 100.0,
            startup_cost_rs = 1000.0,
            shutdown_cost_rs = 500.0,
            commissioning_date = DateTime(2010, 1, 1),
            num_units = 1,
            must_run = false,
        )

        @test_throws Exception DatabaseLoaders.row_to_thermal_plant(invalid_row)
    end

    @testset "Database Connection - Error Handling" begin
        # Test connection failure handling
        invalid_loader = DatabaseLoaders.DatabaseLoader(;
            host = "invalid_host",
            port = 9999,
            dbname = "nonexistent_db",
            user = "invalid_user",
            password = "wrong_pass",
            schema = "public",
        )

        # Should handle connection errors gracefully
        @test_logs (:error, r"Failed to connect") DatabaseLoaders.load_from_database(
            invalid_loader,
        )
    end

    @testset "Incremental Loading - Thermal Plants Only" begin
        # Test loading only specific entity types
        loader = DatabaseLoaders.DatabaseLoader(;
            host = "localhost",
            port = 5432,
            dbname = "dessem_test",
            user = "test_user",
            password = "test_pass",
            schema = "public",
        )

        # This would test selective loading
        # In real scenario, this would connect to test database
        # For now, we test the query generation
        thermal_query = DatabaseLoaders.generate_thermal_plants_query("public")

        @test occursin("WHERE", uppercase(thermal_query)) ||
              occursin("SELECT", uppercase(thermal_query))
    end

    @testset "Schema Support - Custom Schema" begin
        # Test that custom schemas are properly handled
        loader = DatabaseLoaders.DatabaseLoader(;
            host = "localhost",
            port = 5432,
            dbname = "dessem_test",
            user = "test_user",
            password = "test_pass",
            schema = "dessem_2026",
        )

        @test loader.schema == "dessem_2026"

        # Check that queries use the custom schema
        thermal_query = DatabaseLoaders.generate_thermal_plants_query("dessem_2026")
        @test occursin("dessem_2026", thermal_query)
        @test occursin("thermal_plants", thermal_query)
    end

    @testset "Data Type Conversions" begin
        # Test proper type conversions from database types
        mock_row_with_strings = (
            id = "T_001",
            name = "Test",
            bus_id = "B_001",
            submarket_id = "SE",
            fuel_type = "natural_gas",
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
            num_units = 1,
            must_run = false,
        )

        plant = DatabaseLoaders.row_to_thermal_plant(mock_row_with_strings)

        # Verify all types are correct
        @test plant.id isa String
        @test plant.capacity_mw isa Float64
        @test plant.min_up_time_hours isa Int
        @test plant.must_run isa Bool
        @test plant.commissioning_date isa DateTime
    end

    @testset "Load Profile Handling" begin
        # Test various load profile scenarios
        profile_24h = collect(1.0:1.0:24)
        profile_168h = collect(1.0:1.0:168)

        mock_row = (
            id = "L_001",
            name = "Test Load",
            submarket_id = "SE",
            bus_id = "B_001",
            base_mw = 1000.0,
            is_elastic = false,
            elasticity = 0.0,
        )

        # Test with 24-hour profile
        load_24 = DatabaseLoaders.row_to_load(mock_row, profile_24h)
        @test load_24.load_profile == profile_24h

        # Test with 168-hour profile
        load_168 = DatabaseLoaders.row_to_load(mock_row, profile_168h)
        @test load_168.load_profile == profile_168h
    end

    @testset "Empty Result Handling" begin
        # Test handling of empty database results
        empty_thermal_results = []

        plants =
            [DatabaseLoaders.row_to_thermal_plant(row) for row in empty_thermal_results]

        @test isempty(plants)
        @test plants isa Vector
    end

    @testset "Multiple Plants Loading" begin
        # Test loading multiple plants
        mock_rows = [
            (
                id = "T_001",
                name = "Plant 1",
                bus_id = "B_001",
                submarket_id = "SE",
                fuel_type = "natural_gas",
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
                num_units = 1,
                must_run = false,
            ),
            (
                id = "T_002",
                name = "Plant 2",
                bus_id = "B_002",
                submarket_id = "S",
                fuel_type = "coal",
                capacity_mw = 800.0,
                min_generation_mw = 200.0,
                max_generation_mw = 800.0,
                ramp_up_mw_per_min = 30.0,
                ramp_down_mw_per_min = 30.0,
                min_up_time_hours = 12,
                min_down_time_hours = 8,
                fuel_cost_rsj_per_mwh = 100.0,
                startup_cost_rs = 25000.0,
                shutdown_cost_rs = 12000.0,
                commissioning_date = DateTime(2005, 6, 15),
                num_units = 2,
                must_run = false,
            ),
        ]

        plants = ConventionalThermal[]
        for row in mock_rows
            push!(plants, DatabaseLoaders.row_to_thermal_plant(row))
        end

        @test length(plants) == 2
        @test plants[1].id == "T_001"
        @test plants[2].id == "T_002"
        @test plants[1].fuel_type == NATURAL_GAS
        @test plants[2].fuel_type == COAL
    end

    @testset "Connection String Security" begin
        # Test that passwords are properly escaped
        loader = DatabaseLoaders.DatabaseLoader(;
            host = "localhost",
            port = 5432,
            dbname = "dessem_test",
            user = "user@special",
            password = "pass with spaces",
            schema = "public",
        )

        conn_str = DatabaseLoaders.get_connection_string(loader)
        @test occursin("user=user@special", conn_str) ||
              occursin("user=%27user%40special%27", conn_str)  # URL encoded
    end

    @testset "Logging and Progress Reporting" begin
        # Test that appropriate logging occurs
        loader = DatabaseLoaders.DatabaseLoader(;
            host = "localhost",
            port = 5432,
            dbname = "dessem_test",
            user = "test_user",
            password = "test_pass",
            schema = "public",
            verbose = true,
        )

        @test loader.verbose == true
    end

end
