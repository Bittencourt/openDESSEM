"""
    Test suite for Production Cost Objective module

Tests COST_SCALE application, FCF integration, load shedding/deficit cost
terms, and complete objective building.
"""

using OpenDESSEM.Entities:
    ConventionalThermal,
    ReservoirHydro,
    HydroPlant,
    WindPlant,
    SolarPlant,
    Bus,
    Submarket,
    Load,
    NATURAL_GAS
using OpenDESSEM: ElectricitySystem
using OpenDESSEM.Objective:
    ProductionCostObjective,
    ObjectiveMetadata,
    ObjectiveBuildResult,
    validate_objective_system,
    get_fuel_cost,
    COST_SCALE
using OpenDESSEM.Variables
using OpenDESSEM.FCFCurveLoader
using Test
using JuMP
using MathOptInterface
using Dates

const obj_build! = OpenDESSEM.Objective.build!

@testset "Production Cost Objective Tests" begin

    # =====================================================================
    # Test Fixtures
    # =====================================================================

    function create_test_thermal(; id::String, fuel_cost::Float64 = 150.0)
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
            fuel_cost_rsj_per_mwh = fuel_cost,
            startup_cost_rs = 10000.0,
            shutdown_cost_rs = 5000.0,
            commissioning_date = DateTime(2020, 1, 1),
        )
    end

    function create_test_hydro(; id::String, water_value::Float64 = 50.0)
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
            water_value_rs_per_hm3 = water_value,
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

    function create_test_load(;
        id::String,
        submarket_id::String = "SE",
        base_mw::Float64 = 1000.0,
    )
        Load(;
            id = id,
            name = "Load $id",
            submarket_id = submarket_id,
            base_mw = base_mw,
            load_profile = fill(1.0, 24),
            is_elastic = false,
            elasticity = -0.1,
        )
    end

    function create_test_system(;
        thermal_count::Int = 1,
        hydro_count::Int = 1,
        wind_count::Int = 0,
        load_count::Int = 0,
    )
        thermals =
            ConventionalThermal[create_test_thermal(id = "T$i") for i = 1:thermal_count]
        hydros = OpenDESSEM.Entities.HydroPlant[
            create_test_hydro(id = "H$i") for i = 1:hydro_count
        ]
        winds = WindPlant[create_test_wind(id = "W$i") for i = 1:wind_count]
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
            solar_farms = SolarPlant[],
            buses = buses,
            submarkets = submarkets,
            loads = loads,
            base_date = Date(2025, 1, 1),
            description = "Test system for objective tests",
        )
    end

    function create_test_fcf_data(; plant_ids::Vector{String} = ["H1"])
        curves = Dict{String,FCFCurve}()
        for pid in plant_ids
            curves[pid] = FCFCurve(;
                plant_id = pid,
                num_pieces = 5,
                storage_breakpoints = [0.0, 250.0, 500.0, 750.0, 1000.0],
                water_values = [200.0, 150.0, 100.0, 60.0, 30.0],
            )
        end
        return FCFCurveData(;
            curves = curves,
            study_date = Date(2025, 1, 1),
            num_periods = 24,
            source_file = "test_fcf.dat",
        )
    end

    function create_default_objective(; kwargs...)
        return ProductionCostObjective(;
            metadata = ObjectiveMetadata(;
                name = "Test Objective",
                description = "Test production cost objective",
            ),
            kwargs...,
        )
    end

    function setup_model_with_variables(
        system,
        time_periods;
        include_shed::Bool = false,
        include_deficit::Bool = false,
    )
        model = Model()
        create_thermal_variables!(model, system, time_periods)
        create_hydro_variables!(model, system, time_periods)

        if !isempty(system.wind_farms)
            create_renewable_variables!(model, system, time_periods)
        end

        if include_shed && !isempty(system.loads)
            create_load_shedding_variables!(model, system, time_periods)
        end

        if include_deficit && !isempty(system.submarkets)
            create_deficit_variables!(model, system, time_periods)
        end

        return model
    end

    # =====================================================================
    # COST_SCALE Tests
    # =====================================================================

    @testset "COST_SCALE constant" begin
        @test COST_SCALE == 1e-6
        @test COST_SCALE > 0.0
        @test COST_SCALE < 1.0
    end

    @testset "COST_SCALE applied to all cost terms" begin
        system = create_test_system(thermal_count = 1, hydro_count = 1)
        time_periods = 1:4
        model = setup_model_with_variables(system, time_periods)

        objective = create_default_objective()
        result = obj_build!(model, system, objective)

        @test result.success
        @test haskey(result.cost_component_summary, "thermal_fuel")
        @test haskey(result.cost_component_summary, "thermal_startup")
        @test haskey(result.cost_component_summary, "thermal_shutdown")
        @test haskey(result.cost_component_summary, "hydro_water_value")

        # Verify objective was set (minimization)
        @test objective_sense(model) == MathOptInterface.MIN_SENSE

        # Verify that objective expression contains scaled coefficients
        # The objective coefficients should include COST_SCALE factor
        obj = objective_function(model)
        @test obj isa AffExpr

        # Get the thermal generation variable coefficient
        g = model[:g]
        fuel_cost = 150.0  # default test thermal fuel cost
        expected_coeff = fuel_cost * COST_SCALE
        # Check the coefficient of g[1,1] is fuel_cost * COST_SCALE
        @test coefficient(obj, g[1, 1]) == expected_coeff

        # Check startup cost coefficient
        v = model[:v]
        startup_cost = 10000.0
        expected_startup_coeff = startup_cost * COST_SCALE
        @test coefficient(obj, v[1, 1]) == expected_startup_coeff

        # Check shutdown cost coefficient
        w = model[:w]
        shutdown_cost = 5000.0
        expected_shutdown_coeff = shutdown_cost * COST_SCALE
        @test coefficient(obj, w[1, 1]) == expected_shutdown_coeff

        # Check hydro water value coefficient
        s = model[:s]
        water_value = 50.0  # default test hydro water value
        expected_water_coeff = water_value * COST_SCALE
        @test coefficient(obj, s[1, 1]) == expected_water_coeff
    end

    @testset "cost_component_summary is NOT scaled" begin
        system = create_test_system(thermal_count = 1, hydro_count = 0)
        time_periods = 1:4
        model = setup_model_with_variables(system, time_periods)

        objective = create_default_objective(hydro_water_value = false)
        result = obj_build!(model, system, objective)

        @test result.success

        # cost_component_summary should be in original R$ (not scaled)
        # For thermal fuel: cost * max_generation * n_periods
        fuel_cost = 150.0
        max_gen = 500.0
        n_periods = 4
        expected_summary = fuel_cost * max_gen * n_periods
        @test result.cost_component_summary["thermal_fuel"] == expected_summary

        # For startup: startup_cost * n_periods
        startup_cost = 10000.0
        expected_startup_summary = startup_cost * n_periods
        @test result.cost_component_summary["thermal_startup"] == expected_startup_summary
    end

    # =====================================================================
    # FCF Integration Tests
    # =====================================================================

    @testset "FCF integration for terminal water value" begin
        @testset "FCF water value used at terminal period" begin
            system = create_test_system(thermal_count = 0, hydro_count = 1)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods)

            fcf_data = create_test_fcf_data(plant_ids = ["H1"])
            objective = create_default_objective(
                thermal_fuel_cost = false,
                thermal_startup_cost = false,
                thermal_shutdown_cost = false,
                fcf_data = fcf_data,
                use_terminal_water_value = true,
            )

            result = obj_build!(model, system, objective)
            @test result.success

            # Get the objective expression
            obj = objective_function(model)
            s = model[:s]

            # At terminal period (t=4), FCF should be used
            # Plant initial_volume is 500 hm3, FCF at 500 = 100.0 R$/hm3
            fcf_water_value = get_water_value(fcf_data, "H1", 500.0)
            @test fcf_water_value == 100.0

            # Terminal period coefficient should use FCF value
            expected_terminal_coeff = fcf_water_value * COST_SCALE
            @test coefficient(obj, s[1, 4]) == expected_terminal_coeff

            # Non-terminal period should use base water value
            base_water_value = 50.0  # from create_test_hydro default
            expected_base_coeff = base_water_value * COST_SCALE
            @test coefficient(obj, s[1, 1]) == expected_base_coeff
            @test coefficient(obj, s[1, 2]) == expected_base_coeff
            @test coefficient(obj, s[1, 3]) == expected_base_coeff
        end

        @testset "FCF fallback to base water value when plant not in FCF" begin
            system = create_test_system(thermal_count = 0, hydro_count = 1)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods)

            # FCF data does NOT contain "H1"
            fcf_data = create_test_fcf_data(plant_ids = ["H_OTHER"])
            objective = create_default_objective(
                thermal_fuel_cost = false,
                thermal_startup_cost = false,
                thermal_shutdown_cost = false,
                fcf_data = fcf_data,
                use_terminal_water_value = true,
            )

            result = obj_build!(model, system, objective)
            @test result.success

            # All periods should use base water value since plant not in FCF
            obj = objective_function(model)
            s = model[:s]
            base_water_value = 50.0
            expected_coeff = base_water_value * COST_SCALE
            for t = 1:4
                @test coefficient(obj, s[1, t]) == expected_coeff
            end
        end

        @testset "FCF disabled when use_terminal_water_value=false" begin
            system = create_test_system(thermal_count = 0, hydro_count = 1)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods)

            fcf_data = create_test_fcf_data(plant_ids = ["H1"])
            objective = create_default_objective(
                thermal_fuel_cost = false,
                thermal_startup_cost = false,
                thermal_shutdown_cost = false,
                fcf_data = fcf_data,
                use_terminal_water_value = false,
            )

            result = obj_build!(model, system, objective)
            @test result.success

            # All periods use base water value since FCF disabled
            obj = objective_function(model)
            s = model[:s]
            base_water_value = 50.0
            expected_coeff = base_water_value * COST_SCALE
            for t = 1:4
                @test coefficient(obj, s[1, t]) == expected_coeff
            end
        end

        @testset "FCF with no fcf_data (nothing)" begin
            system = create_test_system(thermal_count = 0, hydro_count = 1)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods)

            objective = create_default_objective(
                thermal_fuel_cost = false,
                thermal_startup_cost = false,
                thermal_shutdown_cost = false,
                fcf_data = nothing,
                use_terminal_water_value = true,
            )

            result = obj_build!(model, system, objective)
            @test result.success

            # All periods use base water value
            obj = objective_function(model)
            s = model[:s]
            base_water_value = 50.0
            expected_coeff = base_water_value * COST_SCALE
            for t = 1:4
                @test coefficient(obj, s[1, t]) == expected_coeff
            end
        end

        @testset "FCF override via build! keyword argument" begin
            system = create_test_system(thermal_count = 0, hydro_count = 1)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods)

            fcf_data = create_test_fcf_data(plant_ids = ["H1"])
            # Objective has no fcf_data
            objective = create_default_objective(
                thermal_fuel_cost = false,
                thermal_startup_cost = false,
                thermal_shutdown_cost = false,
                fcf_data = nothing,
                use_terminal_water_value = true,
            )

            # But pass fcf_data via keyword argument
            result = obj_build!(model, system, objective; fcf_data = fcf_data)
            @test result.success

            # Terminal period should use FCF value
            obj = objective_function(model)
            s = model[:s]
            fcf_water_value = get_water_value(fcf_data, "H1", 500.0)
            expected_terminal_coeff = fcf_water_value * COST_SCALE
            @test coefficient(obj, s[1, 4]) == expected_terminal_coeff
        end
    end

    # =====================================================================
    # Load Shedding Cost Tests
    # =====================================================================

    @testset "Load shedding cost" begin
        @testset "Load shedding term with shed variables" begin
            system = create_test_system(thermal_count = 1, hydro_count = 0, load_count = 2)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods; include_shed = true)

            objective = create_default_objective(
                load_shedding_cost = true,
                shedding_penalty = 5000.0,
            )

            result = obj_build!(model, system, objective)
            @test result.success
            @test haskey(result.cost_component_summary, "load_shedding")
            @test result.cost_component_summary["load_shedding"] > 0.0

            # Verify shed variable coefficients are scaled
            obj = objective_function(model)
            shed = model[:shed]
            expected_coeff = 5000.0 * COST_SCALE
            @test coefficient(obj, shed[1, 1]) == expected_coeff
            @test coefficient(obj, shed[2, 1]) == expected_coeff
        end

        @testset "Load shedding warning when variables missing" begin
            system = create_test_system(thermal_count = 1, hydro_count = 0, load_count = 2)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods; include_shed = false)

            objective = create_default_objective(
                load_shedding_cost = true,
                shedding_penalty = 5000.0,
            )

            result = obj_build!(model, system, objective)
            @test result.success
            @test !isempty(result.warnings)
            @test any(contains(w, "shed") for w in result.warnings)
            @test any(
                contains(w, "create_load_shedding_variables!") for w in result.warnings
            )
            @test !haskey(result.cost_component_summary, "load_shedding")
        end

        @testset "Load shedding disabled by default" begin
            system = create_test_system(thermal_count = 1, hydro_count = 0)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods)

            objective = create_default_objective()
            result = obj_build!(model, system, objective)
            @test result.success
            @test !haskey(result.cost_component_summary, "load_shedding")
        end
    end

    # =====================================================================
    # Deficit Cost Tests
    # =====================================================================

    @testset "Deficit cost" begin
        @testset "Deficit term with deficit variables" begin
            system = create_test_system(thermal_count = 1, hydro_count = 0, load_count = 1)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods; include_deficit = true)

            objective =
                create_default_objective(deficit_cost = true, deficit_penalty = 10000.0)

            result = obj_build!(model, system, objective)
            @test result.success
            @test haskey(result.cost_component_summary, "deficit")
            @test result.cost_component_summary["deficit"] > 0.0

            # Verify deficit variable coefficients are scaled
            obj = objective_function(model)
            deficit = model[:deficit]
            expected_coeff = 10000.0 * COST_SCALE
            @test coefficient(obj, deficit[1, 1]) == expected_coeff
        end

        @testset "Deficit warning when variables missing" begin
            system = create_test_system(thermal_count = 1, hydro_count = 0, load_count = 1)
            time_periods = 1:4
            model =
                setup_model_with_variables(system, time_periods; include_deficit = false)

            objective =
                create_default_objective(deficit_cost = true, deficit_penalty = 10000.0)

            result = obj_build!(model, system, objective)
            @test result.success
            @test !isempty(result.warnings)
            @test any(contains(w, "deficit") for w in result.warnings)
            @test any(contains(w, "create_deficit_variables!") for w in result.warnings)
            @test !haskey(result.cost_component_summary, "deficit")
        end

        @testset "Deficit disabled by default" begin
            system = create_test_system(thermal_count = 1, hydro_count = 0)
            time_periods = 1:4
            model = setup_model_with_variables(system, time_periods)

            objective = create_default_objective()
            result = obj_build!(model, system, objective)
            @test result.success
            @test !haskey(result.cost_component_summary, "deficit")
        end
    end

    # =====================================================================
    # Complete Objective Tests
    # =====================================================================

    @testset "Complete objective with all components" begin
        system = create_test_system(
            thermal_count = 2,
            hydro_count = 1,
            wind_count = 1,
            load_count = 2,
        )
        time_periods = 1:4
        model = setup_model_with_variables(
            system,
            time_periods;
            include_shed = true,
            include_deficit = true,
        )

        fcf_data = create_test_fcf_data(plant_ids = ["H1"])
        objective = create_default_objective(
            thermal_fuel_cost = true,
            thermal_startup_cost = true,
            thermal_shutdown_cost = true,
            hydro_water_value = true,
            renewable_curtailment_cost = true,
            curtailment_penalty = 10.0,
            load_shedding_cost = true,
            shedding_penalty = 5000.0,
            deficit_cost = true,
            deficit_penalty = 10000.0,
            fcf_data = fcf_data,
        )

        result = obj_build!(model, system, objective)

        @test result.success
        @test length(result.cost_component_summary) >= 6
        @test haskey(result.cost_component_summary, "thermal_fuel")
        @test haskey(result.cost_component_summary, "thermal_startup")
        @test haskey(result.cost_component_summary, "thermal_shutdown")
        @test haskey(result.cost_component_summary, "hydro_water_value")
        @test haskey(result.cost_component_summary, "renewable_curtailment")
        @test haskey(result.cost_component_summary, "load_shedding")
        @test haskey(result.cost_component_summary, "deficit")

        # Verify minimization sense
        @test objective_sense(model) == MathOptInterface.MIN_SENSE

        # Verify objective message
        @test contains(result.message, "7 components")
    end

    @testset "Empty system fails gracefully" begin
        system = ElectricitySystem(;
            thermal_plants = ConventionalThermal[],
            hydro_plants = OpenDESSEM.Entities.HydroPlant[],
            wind_farms = WindPlant[],
            solar_farms = SolarPlant[],
            buses = [create_test_bus(id = "B1", is_reference = true)],
            submarkets = [create_test_submarket(id = "SM_SE", code = "SE")],
            loads = Load[],
            base_date = Date(2025, 1, 1),
            description = "Empty test system",
        )

        model = Model()
        objective = create_default_objective()
        result = obj_build!(model, system, objective)

        @test !result.success
        @test contains(result.message, "validation failed")
    end

    @testset "Objective with no valid cost components" begin
        # System with thermal but no variables in model
        system = create_test_system(thermal_count = 1, hydro_count = 0)
        model = Model()  # No variables created

        objective = create_default_objective()
        result = obj_build!(model, system, objective)

        @test !result.success
        @test contains(result.message, "No valid cost components")
        @test !isempty(result.warnings)
    end

    # =====================================================================
    # get_fuel_cost Tests
    # =====================================================================

    @testset "get_fuel_cost" begin
        plant = create_test_thermal(id = "T1", fuel_cost = 200.0)

        @testset "Returns base cost when no time-varying costs" begin
            costs = Dict{String,Vector{Float64}}()
            @test get_fuel_cost(plant, 1, costs) == 200.0
            @test get_fuel_cost(plant, 10, costs) == 200.0
        end

        @testset "Returns time-varying cost when available" begin
            costs = Dict{String,Vector{Float64}}("T1" => [100.0, 120.0, 140.0])
            @test get_fuel_cost(plant, 1, costs) == 100.0
            @test get_fuel_cost(plant, 2, costs) == 120.0
            @test get_fuel_cost(plant, 3, costs) == 140.0
        end

        @testset "Falls back to base cost when period exceeds vector" begin
            costs = Dict{String,Vector{Float64}}("T1" => [100.0, 120.0])
            @test get_fuel_cost(plant, 3, costs) == 200.0
        end

        @testset "Returns base cost for unknown plant" begin
            costs = Dict{String,Vector{Float64}}("T_OTHER" => [100.0])
            @test get_fuel_cost(plant, 1, costs) == 200.0
        end
    end

    # =====================================================================
    # ProductionCostObjective Struct Tests
    # =====================================================================

    @testset "ProductionCostObjective struct" begin
        @testset "Default construction" begin
            obj = create_default_objective()
            @test obj.thermal_fuel_cost == true
            @test obj.thermal_startup_cost == true
            @test obj.thermal_shutdown_cost == true
            @test obj.hydro_water_value == true
            @test obj.renewable_curtailment_cost == false
            @test obj.curtailment_penalty == 0.0
            @test obj.load_shedding_cost == false
            @test obj.shedding_penalty == 5000.0
            @test obj.deficit_cost == false
            @test obj.deficit_penalty == 10000.0
            @test isempty(obj.time_varying_fuel_costs)
            @test isempty(obj.plant_filter)
            @test obj.fcf_data === nothing
            @test obj.use_terminal_water_value == true
        end

        @testset "Construction with FCF data" begin
            fcf_data = create_test_fcf_data()
            obj = create_default_objective(fcf_data = fcf_data)
            @test obj.fcf_data !== nothing
            @test obj.fcf_data === fcf_data
        end

        @testset "Construction with all options" begin
            obj = ProductionCostObjective(;
                metadata = ObjectiveMetadata(;
                    name = "Full Objective",
                    description = "All options enabled",
                ),
                thermal_fuel_cost = true,
                thermal_startup_cost = true,
                thermal_shutdown_cost = true,
                hydro_water_value = true,
                renewable_curtailment_cost = true,
                curtailment_penalty = 15.0,
                load_shedding_cost = true,
                shedding_penalty = 3000.0,
                deficit_cost = true,
                deficit_penalty = 8000.0,
                fcf_data = nothing,
                use_terminal_water_value = false,
            )

            @test obj.curtailment_penalty == 15.0
            @test obj.shedding_penalty == 3000.0
            @test obj.deficit_penalty == 8000.0
            @test obj.use_terminal_water_value == false
        end
    end

    # =====================================================================
    # Plant Filter Tests
    # =====================================================================

    @testset "Plant filter" begin
        system = create_test_system(thermal_count = 3, hydro_count = 0)
        time_periods = 1:4
        model = setup_model_with_variables(system, time_periods)

        # Only include T1 and T3
        objective =
            create_default_objective(plant_filter = ["T1", "T3"], hydro_water_value = false)

        result = obj_build!(model, system, objective)
        @test result.success

        # Cost summary should reflect only 2 plants, not 3
        fuel_cost = 150.0
        max_gen = 500.0
        n_periods = 4
        expected_fuel = fuel_cost * max_gen * n_periods * 2  # 2 plants
        @test result.cost_component_summary["thermal_fuel"] == expected_fuel
    end

    # =====================================================================
    # Time-Varying Fuel Cost Tests
    # =====================================================================

    @testset "Time-varying fuel costs in objective" begin
        system = create_test_system(thermal_count = 1, hydro_count = 0)
        time_periods = 1:3
        model = setup_model_with_variables(system, time_periods)

        time_varying = Dict{String,Vector{Float64}}("T1" => [100.0, 200.0, 300.0])
        objective = create_default_objective(
            time_varying_fuel_costs = time_varying,
            hydro_water_value = false,
        )

        result = obj_build!(model, system, objective)
        @test result.success

        obj = objective_function(model)
        g = model[:g]

        @test coefficient(obj, g[1, 1]) == 100.0 * COST_SCALE
        @test coefficient(obj, g[1, 2]) == 200.0 * COST_SCALE
        @test coefficient(obj, g[1, 3]) == 300.0 * COST_SCALE
    end

    # =====================================================================
    # ObjectiveBuildResult Tests
    # =====================================================================

    @testset "ObjectiveBuildResult" begin
        result = ObjectiveBuildResult(;
            objective_type = "ProductionCostObjective",
            build_time_seconds = 0.015,
            success = true,
            message = "Built successfully",
            cost_component_summary = Dict("thermal_fuel" => 50000.0),
            warnings = String[],
        )

        @test result.objective_type == "ProductionCostObjective"
        @test result.build_time_seconds == 0.015
        @test result.success == true
        @test result.message == "Built successfully"
        @test result.cost_component_summary["thermal_fuel"] == 50000.0
        @test isempty(result.warnings)
    end

    # =====================================================================
    # validate_objective_system Tests
    # =====================================================================

    @testset "validate_objective_system" begin
        @testset "Valid system with thermal plants" begin
            system = create_test_system(thermal_count = 1, hydro_count = 0)
            @test validate_objective_system(system)
        end

        @testset "Valid system with hydro plants" begin
            system = create_test_system(thermal_count = 0, hydro_count = 1)
            @test validate_objective_system(system)
        end

        @testset "Valid system with wind plants" begin
            system = create_test_system(thermal_count = 0, hydro_count = 0, wind_count = 1)
            @test validate_objective_system(system)
        end

        @testset "Invalid empty system" begin
            system = ElectricitySystem(;
                thermal_plants = ConventionalThermal[],
                hydro_plants = OpenDESSEM.Entities.HydroPlant[],
                wind_farms = WindPlant[],
                solar_farms = SolarPlant[],
                buses = [create_test_bus(id = "B1", is_reference = true)],
                submarkets = [create_test_submarket(id = "SM_SE", code = "SE")],
                loads = Load[],
                base_date = Date(2025, 1, 1),
                description = "Empty system",
            )
            @test !validate_objective_system(system)
        end
    end

    # =====================================================================
    # Build Result Metrics Tests
    # =====================================================================

    @testset "Build result metrics" begin
        system = create_test_system(thermal_count = 1, hydro_count = 1)
        time_periods = 1:4
        model = setup_model_with_variables(system, time_periods)

        objective = create_default_objective()
        result = obj_build!(model, system, objective)

        @test result.success
        @test result.build_time_seconds >= 0.0
        @test result.objective_type == "ProductionCostObjective"
        @test !isempty(result.cost_component_summary)
    end

end # main testset
