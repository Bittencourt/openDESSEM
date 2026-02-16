"""
    Test suite for Variable Manager module

Tests creation of JuMP optimization variables for all entity types.
Validates variable naming conventions and PowerModels bridge functionality.
"""

using OpenDESSEM.Entities
using OpenDESSEM.Variables
using Test
using JuMP
using Dates

@testset "Variable Manager Tests" begin

    # Test fixtures for creating sample entities
    function create_test_thermal(; id::String)
        ConventionalThermal(;
            id = id,
            name = "Thermal $id",
            bus_id = "B1",
            submarket_id = "SE",
            fuel_type = NATURAL_GAS,
            capacity_mw = 500.0,
            min_generation_mw = 100.0,
            max_generation_mw = 500.0,
            ramp_up_mw_per_min = 50.0,
            ramp_down_mw_per_min = 50.0,
            min_up_time_hours = 4,
            min_down_time_hours = 2,
            fuel_cost_rsj_per_mwh = 150.0,
            startup_cost_rs = 10000.0,
            shutdown_cost_rs = 5000.0,
            commissioning_date = DateTime(2020, 1, 1),
        )
    end

    function create_test_hydro(; id::String)
        ReservoirHydro(;
            id = id,
            name = "Hydro $id",
            bus_id = "B1",
            submarket_id = "SE",
            max_volume_hm3 = 1000.0,
            min_volume_hm3 = 100.0,
            initial_volume_hm3 = 500.0,
            max_outflow_m3_per_s = 1000.0,
            min_outflow_m3_per_s = 50.0,
            max_generation_mw = 500.0,
            min_generation_mw = 0.0,
            efficiency = 0.90,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = 1,
            initial_volume_percent = 50.0,
        )
    end

    function create_test_wind(; id::String)
        WindPlant(;
            id = id,
            name = "Wind $id",
            bus_id = "B1",
            submarket_id = "NE",
            installed_capacity_mw = 200.0,
            capacity_forecast_mw = fill(180.0, 24),
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = 200.0,
            ramp_up_mw_per_min = 10.0,
            ramp_down_mw_per_min = 10.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.02,
            is_dispatchable = true,
            commissioning_date = DateTime(2018, 6, 15),
            num_turbines = 50,
        )
    end

    function create_test_solar(; id::String)
        SolarPlant(;
            id = id,
            name = "Solar $id",
            bus_id = "B1",
            submarket_id = "NE",
            installed_capacity_mw = 100.0,
            capacity_forecast_mw = fill(80.0, 24),
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = 100.0,
            ramp_up_mw_per_min = 5.0,
            ramp_down_mw_per_min = 5.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.01,
            is_dispatchable = true,
            commissioning_date = DateTime(2019, 1, 1),
            tracking_system = "FIXED",
        )
    end

    function create_test_pumped_storage(; id::String)
        PumpedStorageHydro(;
            id = id,
            name = "PumpedStorage $id",
            bus_id = "B1",
            submarket_id = "SE",
            upper_max_volume_hm3 = 500.0,
            upper_min_volume_hm3 = 50.0,
            upper_initial_volume_hm3 = 250.0,
            upper_initial_volume_percent = 50.0,
            lower_max_volume_hm3 = 1000.0,
            lower_min_volume_hm3 = 100.0,
            lower_initial_volume_hm3 = 500.0,
            max_generation_mw = 300.0,
            max_pumping_mw = 280.0,
            generation_efficiency = 0.85,
            pumping_efficiency = 0.80,
            min_generation_mw = 0.0,
            subsystem_code = 1,
        )
    end

    function create_test_bus(; id::String, is_reference::Bool = false)
        Bus(;
            id = id,
            name = "Bus $id",
            voltage_kv = 230.0,
            base_kv = 230.0,
            dc_bus = false,
            is_reference = is_reference,
            area_id = "A1",
            zone_id = "Z1",
        )
    end

    function create_test_submarket(; id::String, code::String)
        Submarket(; id = id, name = "Submarket $code", code = code, country = "Brazil")
    end

    function create_test_load(; id::String, submarket_id::String = "SE")
        Load(;
            id = id,
            name = "Load $id",
            submarket_id = submarket_id,
            base_mw = 1000.0,
            load_profile = fill(1.0, 24),
            is_elastic = false,
            elasticity = -0.1,
        )
    end

    function create_minimal_system(;
        thermal_count::Int = 0,
        hydro_count::Int = 0,
        wind_count::Int = 0,
        solar_count::Int = 0,
        pumped_storage_count::Int = 0,
        load_count::Int = 0,
    )
        # Use typed array initialization to avoid Vector{Any}
        thermals =
            ConventionalThermal[create_test_thermal(id = "T$i") for i = 1:thermal_count]
        hydros = HydroPlant[]

        # Add reservoir hydros
        for i = 1:hydro_count
            push!(hydros, create_test_hydro(id = "H$i"))
        end

        # Add pumped storage hydros
        for i = 1:pumped_storage_count
            push!(hydros, create_test_pumped_storage(id = "PS$i"))
        end

        winds = WindPlant[create_test_wind(id = "W$i") for i = 1:wind_count]
        solars = SolarPlant[create_test_solar(id = "S$i") for i = 1:solar_count]
        loads = Load[create_test_load(id = "L$i") for i = 1:load_count]

        buses = [create_test_bus(id = "B1", is_reference = true)]
        submarkets = [
            create_test_submarket(id = "SM_SE", code = "SE"),
            create_test_submarket(id = "SM_NE", code = "NE"),
        ]

        return ElectricitySystem(;
            thermal_plants = thermals,
            hydro_plants = hydros,
            wind_farms = winds,
            solar_farms = solars,
            buses = buses,
            submarkets = submarkets,
            loads = loads,
            base_date = Date(2025, 1, 1),
            description = "Test system",
        )
    end

    @testset "Thermal Variables" begin
        @testset "create_thermal_variables! basic" begin
            model = Model()
            system = create_minimal_system(thermal_count = 2)
            time_periods = 1:24

            create_thermal_variables!(model, system, time_periods)

            # Check u (commitment) variables exist
            @test haskey(object_dictionary(model), :u)
            u = model[:u]
            @test size(u) == (2, 24)
            @test all(is_binary.(u))

            # Check v (startup) variables exist
            @test haskey(object_dictionary(model), :v)
            v = model[:v]
            @test size(v) == (2, 24)
            @test all(is_binary.(v))

            # Check w (shutdown) variables exist
            @test haskey(object_dictionary(model), :w)
            w = model[:w]
            @test size(w) == (2, 24)
            @test all(is_binary.(w))

            # Check g (generation) variables exist
            @test haskey(object_dictionary(model), :g)
            g = model[:g]
            @test size(g) == (2, 24)
            @test !any(is_binary.(g))
        end

        @testset "create_thermal_variables! with plant_ids" begin
            model = Model()
            system = create_minimal_system(thermal_count = 3)
            time_periods = 1:12
            plant_ids = ["T1", "T3"]  # Only create for these plants

            create_thermal_variables!(model, system, time_periods; plant_ids = plant_ids)

            # Should have 2 plants, 12 time periods
            @test size(model[:u]) == (2, 12)
            @test size(model[:g]) == (2, 12)
        end

        @testset "create_thermal_variables! empty system" begin
            model = Model()
            system = create_minimal_system(thermal_count = 0)
            time_periods = 1:24

            # Should not throw, but also should not create variables
            create_thermal_variables!(model, system, time_periods)

            @test !haskey(object_dictionary(model), :u)
            @test !haskey(object_dictionary(model), :v)
            @test !haskey(object_dictionary(model), :w)
            @test !haskey(object_dictionary(model), :g)
        end

        @testset "create_thermal_variables! variable bounds" begin
            model = Model()
            system = create_minimal_system(thermal_count = 1)
            time_periods = 1:4

            create_thermal_variables!(model, system, time_periods)

            g = model[:g]
            # Generation should have lower bound 0
            for i = 1:1, t = 1:4
                @test lower_bound(g[i, t]) == 0.0
            end
        end

        @testset "create_thermal_variables! invalid plant_id throws" begin
            model = Model()
            system = create_minimal_system(thermal_count = 2)
            time_periods = 1:24

            @test_throws ArgumentError create_thermal_variables!(
                model,
                system,
                time_periods;
                plant_ids = ["INVALID_ID"],
            )
        end
    end

    @testset "Hydro Variables" begin
        @testset "create_hydro_variables! basic" begin
            model = Model()
            system = create_minimal_system(hydro_count = 2)
            time_periods = 1:24

            create_hydro_variables!(model, system, time_periods)

            # Check s (storage) variables exist
            @test haskey(object_dictionary(model), :s)
            s = model[:s]
            @test size(s) == (2, 24)
            @test !any(is_binary.(s))

            # Check q (flow) variables exist
            @test haskey(object_dictionary(model), :q)
            q = model[:q]
            @test size(q) == (2, 24)
            @test !any(is_binary.(q))

            # Check gh (hydro generation) variables exist
            @test haskey(object_dictionary(model), :gh)
            gh = model[:gh]
            @test size(gh) == (2, 24)
            @test !any(is_binary.(gh))
        end

        @testset "create_hydro_variables! with pumped storage" begin
            model = Model()
            system = create_minimal_system(hydro_count = 1, pumped_storage_count = 1)
            time_periods = 1:12

            create_hydro_variables!(model, system, time_periods)

            # Should have 2 plants total
            @test size(model[:s]) == (2, 12)
            @test size(model[:gh]) == (2, 12)

            # Check pump variables exist
            @test haskey(object_dictionary(model), :pump)
            pump = model[:pump]
            @test size(pump) == (2, 12)
        end

        @testset "create_hydro_variables! with plant_ids" begin
            model = Model()
            system = create_minimal_system(hydro_count = 3)
            time_periods = 1:12
            plant_ids = ["H1", "H2"]

            create_hydro_variables!(model, system, time_periods; plant_ids = plant_ids)

            @test size(model[:s]) == (2, 12)
            @test size(model[:gh]) == (2, 12)
        end

        @testset "create_hydro_variables! empty system" begin
            model = Model()
            system = create_minimal_system(hydro_count = 0)
            time_periods = 1:24

            create_hydro_variables!(model, system, time_periods)

            @test !haskey(object_dictionary(model), :s)
            @test !haskey(object_dictionary(model), :q)
            @test !haskey(object_dictionary(model), :gh)
            @test !haskey(object_dictionary(model), :pump)
        end

        @testset "create_hydro_variables! variable bounds" begin
            model = Model()
            system = create_minimal_system(hydro_count = 1)
            time_periods = 1:4

            create_hydro_variables!(model, system, time_periods)

            s = model[:s]
            q = model[:q]
            gh = model[:gh]

            # All hydro variables should have non-negative lower bounds
            for i = 1:1, t = 1:4
                @test lower_bound(s[i, t]) >= 0.0
                @test lower_bound(q[i, t]) >= 0.0
                @test lower_bound(gh[i, t]) >= 0.0
            end
        end

        @testset "create_hydro_variables! invalid plant_id throws" begin
            model = Model()
            system = create_minimal_system(hydro_count = 2)
            time_periods = 1:24

            @test_throws ArgumentError create_hydro_variables!(
                model,
                system,
                time_periods;
                plant_ids = ["INVALID_ID"],
            )
        end
    end

    @testset "Renewable Variables" begin
        @testset "create_renewable_variables! basic with wind" begin
            model = Model()
            system = create_minimal_system(wind_count = 2)
            time_periods = 1:24

            create_renewable_variables!(model, system, time_periods)

            # Check gr (renewable generation) variables exist
            @test haskey(object_dictionary(model), :gr)
            gr = model[:gr]
            @test size(gr) == (2, 24)
            @test !any(is_binary.(gr))

            # Check curtail (curtailment) variables exist
            @test haskey(object_dictionary(model), :curtail)
            curtail = model[:curtail]
            @test size(curtail) == (2, 24)
            @test !any(is_binary.(curtail))
        end

        @testset "create_renewable_variables! with wind and solar" begin
            model = Model()
            system = create_minimal_system(wind_count = 2, solar_count = 3)
            time_periods = 1:12

            create_renewable_variables!(model, system, time_periods)

            # Should have 5 renewables total
            @test size(model[:gr]) == (5, 12)
            @test size(model[:curtail]) == (5, 12)
        end

        @testset "create_renewable_variables! with plant_ids" begin
            model = Model()
            system = create_minimal_system(wind_count = 2, solar_count = 2)
            time_periods = 1:12
            plant_ids = ["W1", "S1"]

            create_renewable_variables!(model, system, time_periods; plant_ids = plant_ids)

            # Should have 2 plants
            @test size(model[:gr]) == (2, 12)
            @test size(model[:curtail]) == (2, 12)
        end

        @testset "create_renewable_variables! empty system" begin
            model = Model()
            system = create_minimal_system(wind_count = 0, solar_count = 0)
            time_periods = 1:24

            create_renewable_variables!(model, system, time_periods)

            @test !haskey(object_dictionary(model), :gr)
            @test !haskey(object_dictionary(model), :curtail)
        end

        @testset "create_renewable_variables! variable bounds" begin
            model = Model()
            system = create_minimal_system(wind_count = 1)
            time_periods = 1:4

            create_renewable_variables!(model, system, time_periods)

            gr = model[:gr]
            curtail = model[:curtail]

            # All renewable variables should have non-negative lower bounds
            for i = 1:1, t = 1:4
                @test lower_bound(gr[i, t]) >= 0.0
                @test lower_bound(curtail[i, t]) >= 0.0
            end
        end

        @testset "create_renewable_variables! invalid plant_id throws" begin
            model = Model()
            system = create_minimal_system(wind_count = 2)
            time_periods = 1:24

            @test_throws ArgumentError create_renewable_variables!(
                model,
                system,
                time_periods;
                plant_ids = ["INVALID_ID"],
            )
        end
    end

    @testset "Create All Variables" begin
        @testset "create_all_variables! complete system" begin
            model = Model()
            system = create_minimal_system(
                thermal_count = 2,
                hydro_count = 2,
                wind_count = 1,
                solar_count = 1,
                pumped_storage_count = 1,
            )
            time_periods = 1:24

            create_all_variables!(model, system, time_periods)

            # Check all thermal variables
            @test haskey(object_dictionary(model), :u)
            @test haskey(object_dictionary(model), :v)
            @test haskey(object_dictionary(model), :w)
            @test haskey(object_dictionary(model), :g)

            # Check all hydro variables
            @test haskey(object_dictionary(model), :s)
            @test haskey(object_dictionary(model), :q)
            @test haskey(object_dictionary(model), :gh)
            @test haskey(object_dictionary(model), :pump)

            # Check all renewable variables
            @test haskey(object_dictionary(model), :gr)
            @test haskey(object_dictionary(model), :curtail)

            # Verify sizes
            @test size(model[:u]) == (2, 24)  # 2 thermals
            @test size(model[:s]) == (3, 24)  # 2 hydros + 1 pumped storage
            @test size(model[:gr]) == (2, 24)  # 1 wind + 1 solar
        end

        @testset "create_all_variables! empty system" begin
            model = Model()
            system = create_minimal_system()
            time_periods = 1:24

            # Should not throw on empty system
            create_all_variables!(model, system, time_periods)

            # Only deficit variables created (for existing submarkets)
            # No plant-specific variables should exist
            @test !haskey(object_dictionary(model), :u)
            @test !haskey(object_dictionary(model), :g)
            @test !haskey(object_dictionary(model), :gh)
            @test !haskey(object_dictionary(model), :gr)
            @test !haskey(object_dictionary(model), :shed)
        end
    end

    @testset "Get Variable Info" begin
        @testset "get_thermal_plant_indices" begin
            system = create_minimal_system(thermal_count = 3)

            indices = get_thermal_plant_indices(system)

            @test length(indices) == 3
            @test haskey(indices, "T1")
            @test haskey(indices, "T2")
            @test haskey(indices, "T3")
            @test indices["T1"] == 1
            @test indices["T2"] == 2
            @test indices["T3"] == 3
        end

        @testset "get_hydro_plant_indices" begin
            system = create_minimal_system(hydro_count = 2, pumped_storage_count = 1)

            indices = get_hydro_plant_indices(system)

            @test length(indices) == 3
            @test haskey(indices, "H1")
            @test haskey(indices, "H2")
            @test haskey(indices, "PS1")
        end

        @testset "get_renewable_plant_indices" begin
            system = create_minimal_system(wind_count = 2, solar_count = 1)

            indices = get_renewable_plant_indices(system)

            @test length(indices) == 3
            @test haskey(indices, "W1")
            @test haskey(indices, "W2")
            @test haskey(indices, "S1")
        end

        @testset "get_plant_by_index" begin
            system = create_minimal_system(thermal_count = 3)

            plant = get_plant_by_index(system.thermal_plants, 2)

            @test plant.id == "T2"
        end
    end

    @testset "PowerModels Bridge" begin
        @testset "get_powermodels_variable documentation" begin
            # Test that the function exists and has proper documentation
            @test hasmethod(get_powermodels_variable, Tuple{Dict{String,Any},Symbol,Any})
        end

        @testset "get_powermodels_variable with mock PM data" begin
            # Create a mock PowerModels-like data structure
            # In real usage, this would come from PowerModels.jl solve result
            mock_pm_result = Dict{String,Any}(
                "solution" => Dict{String,Any}(
                    "bus" => Dict{String,Any}(
                        "1" => Dict{String,Any}("va" => 0.0, "vm" => 1.02),
                        "2" => Dict{String,Any}("va" => -0.05, "vm" => 0.98),
                    ),
                    "gen" => Dict{String,Any}(
                        "1" => Dict{String,Any}("pg" => 100.0, "qg" => 20.0),
                        "2" => Dict{String,Any}("pg" => 150.0, "qg" => 30.0),
                    ),
                    "branch" => Dict{String,Any}(
                        "1" => Dict{String,Any}(
                            "pf" => 50.0,
                            "pt" => -49.5,
                            "qf" => 10.0,
                            "qt" => -9.8,
                        ),
                    ),
                ),
            )

            # Test voltage angle retrieval
            va = get_powermodels_variable(mock_pm_result, :va, 1)
            @test va == 0.0

            va2 = get_powermodels_variable(mock_pm_result, :va, 2)
            @test va2 == -0.05

            # Test voltage magnitude retrieval
            vm = get_powermodels_variable(mock_pm_result, :vm, 1)
            @test vm == 1.02

            # Test generator active power
            pg = get_powermodels_variable(mock_pm_result, :pg, 1)
            @test pg == 100.0

            # Test branch power flow
            pf = get_powermodels_variable(mock_pm_result, :pf, 1)
            @test pf == 50.0
        end

        @testset "get_powermodels_variable missing index" begin
            mock_pm_result = Dict{String,Any}(
                "solution" => Dict{String,Any}(
                    "bus" => Dict{String,Any}("1" => Dict{String,Any}("va" => 0.0)),
                ),
            )

            # Should return nothing for missing index
            result = get_powermodels_variable(mock_pm_result, :va, 99)
            @test result === nothing
        end

        @testset "get_powermodels_variable unsupported variable" begin
            mock_pm_result = Dict{String,Any}(
                "solution" => Dict{String,Any}(
                    "bus" => Dict{String,Any}("1" => Dict{String,Any}("va" => 0.0)),
                ),
            )

            # Should return nothing for unsupported variable type
            result = get_powermodels_variable(mock_pm_result, :unknown_var, 1)
            @test result === nothing
        end

        @testset "list_supported_powermodels_variables" begin
            vars = list_supported_powermodels_variables()

            @test :va in vars  # Voltage angle
            @test :vm in vars  # Voltage magnitude
            @test :pg in vars  # Generator active power
            @test :qg in vars  # Generator reactive power
            @test :pf in vars  # Branch from-end active power
            @test :pt in vars  # Branch to-end active power
            @test :qf in vars  # Branch from-end reactive power
            @test :qt in vars  # Branch to-end reactive power
        end
    end

    @testset "Variable Naming Convention" begin
        @testset "Thermal variable names follow convention" begin
            model = Model()
            system = create_minimal_system(thermal_count = 1)
            time_periods = 1:2

            create_thermal_variables!(model, system, time_periods)

            # Check variable names match convention
            @test name(model[:u][1, 1]) == "u[1,1]"
            @test name(model[:v][1, 1]) == "v[1,1]"
            @test name(model[:w][1, 1]) == "w[1,1]"
            @test name(model[:g][1, 1]) == "g[1,1]"
        end

        @testset "Hydro variable names follow convention" begin
            model = Model()
            system = create_minimal_system(hydro_count = 1)
            time_periods = 1:2

            create_hydro_variables!(model, system, time_periods)

            # Check variable names match convention
            @test name(model[:s][1, 1]) == "s[1,1]"
            @test name(model[:q][1, 1]) == "q[1,1]"
            @test name(model[:gh][1, 1]) == "gh[1,1]"
        end

        @testset "Renewable variable names follow convention" begin
            model = Model()
            system = create_minimal_system(wind_count = 1)
            time_periods = 1:2

            create_renewable_variables!(model, system, time_periods)

            # Check variable names match convention
            @test name(model[:gr][1, 1]) == "gr[1,1]"
            @test name(model[:curtail][1, 1]) == "curtail[1,1]"
        end
    end

    @testset "Load Shedding Variables" begin
        @testset "create_load_shedding_variables! basic" begin
            model = Model()
            system = create_minimal_system(load_count = 2)
            time_periods = 1:24

            create_load_shedding_variables!(model, system, time_periods)

            # Check shed variables exist
            @test haskey(object_dictionary(model), :shed)
            shed = model[:shed]
            @test size(shed) == (2, 24)
            @test !any(is_binary.(shed))
        end

        @testset "create_load_shedding_variables! with load_ids" begin
            model = Model()
            system = create_minimal_system(load_count = 3)
            time_periods = 1:12
            load_ids = ["L1", "L3"]  # Only create for these loads

            create_load_shedding_variables!(model, system, time_periods; load_ids = load_ids)

            # Should have 2 loads, 12 time periods
            @test size(model[:shed]) == (2, 12)
        end

        @testset "create_load_shedding_variables! empty system" begin
            model = Model()
            system = create_minimal_system(load_count = 0)
            time_periods = 1:24

            # Should not throw, but also should not create variables
            create_load_shedding_variables!(model, system, time_periods)

            @test !haskey(object_dictionary(model), :shed)
        end

        @testset "create_load_shedding_variables! variable bounds" begin
            model = Model()
            system = create_minimal_system(load_count = 1)
            time_periods = 1:4

            create_load_shedding_variables!(model, system, time_periods)

            shed = model[:shed]
            # Shedding should have lower bound 0
            for l = 1:1, t = 1:4
                @test lower_bound(shed[l, t]) == 0.0
            end
        end

        @testset "create_load_shedding_variables! invalid load_id throws" begin
            model = Model()
            system = create_minimal_system(load_count = 2)
            time_periods = 1:24

            @test_throws ArgumentError create_load_shedding_variables!(
                model,
                system,
                time_periods;
                load_ids = ["INVALID_ID"],
            )
        end

        @testset "get_load_indices" begin
            system = create_minimal_system(load_count = 3)

            indices = get_load_indices(system)

            @test length(indices) == 3
            @test haskey(indices, "L1")
            @test haskey(indices, "L2")
            @test haskey(indices, "L3")
            @test indices["L1"] == 1
            @test indices["L2"] == 2
            @test indices["L3"] == 3
        end
    end

    @testset "Deficit Variables" begin
        @testset "create_deficit_variables! basic" begin
            model = Model()
            system = create_minimal_system()  # Has 2 submarkets by default
            time_periods = 1:24

            create_deficit_variables!(model, system, time_periods)

            # Check deficit variables exist
            @test haskey(object_dictionary(model), :deficit)
            deficit = model[:deficit]
            @test size(deficit) == (2, 24)  # 2 submarkets
            @test !any(is_binary.(deficit))
        end

        @testset "create_deficit_variables! with submarket_ids" begin
            model = Model()
            system = create_minimal_system()  # Has SE and NE submarkets
            time_periods = 1:12
            submarket_ids = ["SE"]  # Only create for SE

            create_deficit_variables!(model, system, time_periods; submarket_ids = submarket_ids)

            # Should have 1 submarket, 12 time periods
            @test size(model[:deficit]) == (1, 12)
        end

        @testset "create_deficit_variables! empty system" begin
            model = Model()
            # Create system with no submarkets
            system = ElectricitySystem(;
                thermal_plants = ConventionalThermal[],
                hydro_plants = HydroPlant[],
                wind_farms = WindPlant[],
                solar_farms = SolarPlant[],
                buses = Bus[],
                submarkets = Submarket[],
                loads = Load[],
                base_date = Date(2025, 1, 1),
                description = "Empty test system",
            )
            time_periods = 1:24

            # Should not throw, but also should not create variables
            create_deficit_variables!(model, system, time_periods)

            @test !haskey(object_dictionary(model), :deficit)
        end

        @testset "create_deficit_variables! variable bounds" begin
            model = Model()
            system = create_minimal_system()  # Has 2 submarkets
            time_periods = 1:4

            create_deficit_variables!(model, system, time_periods)

            deficit = model[:deficit]
            # Deficit should have lower bound 0
            for s = 1:2, t = 1:4
                @test lower_bound(deficit[s, t]) == 0.0
            end
        end

        @testset "create_deficit_variables! invalid submarket_id throws" begin
            model = Model()
            system = create_minimal_system()
            time_periods = 1:24

            @test_throws ArgumentError create_deficit_variables!(
                model,
                system,
                time_periods;
                submarket_ids = ["INVALID"],
            )
        end

        @testset "get_submarket_indices" begin
            system = create_minimal_system()  # Has SE and NE submarkets

            indices = get_submarket_indices(system)

            @test length(indices) == 2
            @test haskey(indices, "SE")
            @test haskey(indices, "NE")
            @test indices["SE"] == 1
            @test indices["NE"] == 2
        end

        @testset "get_submarket_indices empty system" begin
            system = ElectricitySystem(;
                thermal_plants = ConventionalThermal[],
                hydro_plants = HydroPlant[],
                wind_farms = WindPlant[],
                solar_farms = SolarPlant[],
                buses = Bus[],
                submarkets = Submarket[],
                loads = Load[],
                base_date = Date(2025, 1, 1),
                description = "Empty test system",
            )

            indices = get_submarket_indices(system)

            @test isempty(indices)
        end
    end

    @testset "Create All Variables with Load Shedding and Deficit" begin
        @testset "create_all_variables! includes shed and deficit" begin
            model = Model()
            system = create_minimal_system(
                thermal_count = 2,
                hydro_count = 2,
                wind_count = 1,
                solar_count = 1,
                pumped_storage_count = 1,
                load_count = 3,
            )
            time_periods = 1:24

            create_all_variables!(model, system, time_periods)

            # Check all thermal variables
            @test haskey(object_dictionary(model), :u)
            @test haskey(object_dictionary(model), :v)
            @test haskey(object_dictionary(model), :w)
            @test haskey(object_dictionary(model), :g)

            # Check all hydro variables
            @test haskey(object_dictionary(model), :s)
            @test haskey(object_dictionary(model), :q)
            @test haskey(object_dictionary(model), :gh)
            @test haskey(object_dictionary(model), :pump)

            # Check all renewable variables
            @test haskey(object_dictionary(model), :gr)
            @test haskey(object_dictionary(model), :curtail)

            # Check load shedding variables
            @test haskey(object_dictionary(model), :shed)
            @test size(model[:shed]) == (3, 24)  # 3 loads

            # Check deficit variables
            @test haskey(object_dictionary(model), :deficit)
            @test size(model[:deficit]) == (2, 24)  # 2 submarkets
        end

        @testset "create_all_variables! empty system with submarkets" begin
            model = Model()
            system = create_minimal_system()  # Only has submarkets

            create_all_variables!(model, system, 1:24)

            # Should have deficit variables (from submarkets)
            @test haskey(object_dictionary(model), :deficit)
            # Should not have shed variables (no loads)
            @test !haskey(object_dictionary(model), :shed)
        end
    end

end
