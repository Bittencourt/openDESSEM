"""
    Unit Tests for Constraints Module

Tests all constraint types and their building methods.
Follows TDD principles: tests written first, then implementation.
"""

using OpenDESSEM.Entities:
    ConventionalThermal,
    ReservoirHydro,
    RunOfRiverHydro,
    HydroPlant,
    WindPlant,
    SolarPlant,
    Bus,
    Submarket,
    Load,
    Interconnection,
    NATURAL_GAS
using OpenDESSEM: ElectricitySystem
using OpenDESSEM.Constraints
using OpenDESSEM.Constraints:
    build!,
    is_enabled,
    enable!,
    disable!,
    get_priority,
    set_priority!,
    add_tag!,
    has_tag,
    validate_constraint_system
using OpenDESSEM.Variables
using Test
using JuMP
using Dates

"""
Helper function to create a simple test system for constraint testing.
"""
function create_test_system()
    # Create buses
    bus1 = Bus(;
        id = "B001",
        name = "Bus 1",
        voltage_kv = 230.0,
        base_kv = 230.0,
        is_reference = true,
    )

    bus2 = Bus(;
        id = "B002",
        name = "Bus 2",
        voltage_kv = 230.0,
        base_kv = 230.0,
        is_reference = false,
    )

    # Create submarkets
    sm1 = Submarket(; id = "SM_001", name = "Southeast", code = "SE", country = "Brazil")

    # Create thermal plant
    thermal1 = ConventionalThermal(;
        id = "T001",
        name = "Thermal 1",
        bus_id = "B001",
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
        commissioning_date = DateTime(2010, 1, 1),
    )

    # Create hydro plant
    hydro1 = ReservoirHydro(;
        id = "H001",
        name = "Hydro 1",
        bus_id = "B001",
        submarket_id = "SE",
        max_volume_hm3 = 1000.0,
        min_volume_hm3 = 100.0,
        initial_volume_hm3 = 500.0,
        max_outflow_m3_per_s = 1000.0,
        min_outflow_m3_per_s = 0.0,
        max_generation_mw = 500.0,
        min_generation_mw = 0.0,
        efficiency = 0.92,
        water_value_rs_per_hm3 = 50.0,
        subsystem_code = 1,
        initial_volume_percent = 50.0,
        must_run = false,
        downstream_plant_id = nothing,
        water_travel_time_hours = nothing,
    )

    # Create wind farm
    wind1 = WindPlant(;
        id = "W001",
        name = "Wind 1",
        bus_id = "B001",
        submarket_id = "SE",
        installed_capacity_mw = 100.0,
        min_generation_mw = 0.0,
        max_generation_mw = 100.0,
        capacity_forecast_mw = ones(24) .* 80.0,
        forecast_type = DETERMINISTIC,
        commissioning_date = DateTime(2020, 1, 1),
    )

    # Create load
    load1 = Load(;
        id = "LOAD_001",
        name = "SE Load",
        submarket_id = "SE",
        base_mw = 1000.0,
        load_profile = ones(168),
        is_elastic = false,
    )

    # Assemble system
    system = ElectricitySystem(;
        thermal_plants = [thermal1],
        hydro_plants = [hydro1],
        wind_farms = [wind1],
        solar_farms = SolarPlant[],
        buses = [bus1, bus2],
        ac_lines = ACLine[],
        dc_lines = DCLine[],
        submarkets = [sm1],
        loads = [load1],
        base_date = Date(2025, 1, 1),
        description = "Test system for constraints",
    )

    return system
end

@testset "Constraint Types - Base Abstractions" begin
    @testset "ConstraintMetadata" begin
        metadata =
            ConstraintMetadata(; name = "Test Constraint", description = "Test description")

        @test metadata.name == "Test Constraint"
        @test metadata.description == "Test description"
        @test metadata.priority == 10  # Default
        @test metadata.enabled == true  # Default
        @test isempty(metadata.tags)  # Default
    end

    @testset "ConstraintMetadata - with all fields" begin
        metadata = ConstraintMetadata(;
            name = "Full Test",
            description = "Full test description",
            priority = 20,
            enabled = false,
            tags = ["tag1", "tag2"],
        )

        @test metadata.priority == 20
        @test metadata.enabled == false
        @test length(metadata.tags) == 2
    end

    @testset "ConstraintBuildResult" begin
        result = ConstraintBuildResult(;
            constraint_type = "TestConstraint",
            num_constraints = 100,
            build_time_seconds = 0.5,
            success = true,
            message = "Built successfully",
        )

        @test result.constraint_type == "TestConstraint"
        @test result.num_constraints == 100
        @test result.build_time_seconds == 0.5
        @test result.success == true
        @test isempty(result.warnings)
    end

    @testset "validate_constraint_system" begin
        system = create_test_system()

        # Valid system
        @test validate_constraint_system(system) == true

        # System with no submarkets should fail at construction time
        # (plants reference non-existent submarkets)
        @test_throws ArgumentError ElectricitySystem(;
            thermal_plants = system.thermal_plants,
            hydro_plants = system.hydro_plants,
            wind_farms = system.wind_farms,
            solar_farms = system.solar_farms,
            buses = system.buses,
            ac_lines = system.ac_lines,
            dc_lines = system.dc_lines,
            submarkets = Submarket[],  # Empty submarkets
            loads = system.loads,
            base_date = system.base_date,
            description = "Invalid system",
        )

        # Test validate_constraint_system with no generators (should fail)
        empty_system = ElectricitySystem(;
            thermal_plants = ConventionalThermal[],
            hydro_plants = ReservoirHydro[],
            wind_farms = WindPlant[],
            solar_farms = SolarPlant[],
            buses = system.buses,
            ac_lines = system.ac_lines,
            dc_lines = system.dc_lines,
            submarkets = system.submarkets,
            loads = system.loads,
            base_date = system.base_date,
            description = "System with no generators",
        )

        @test validate_constraint_system(empty_system) == false
    end
end

@testset "Thermal Commitment Constraints" begin
    system = create_test_system()

    @testset "ThermalCommitmentConstraint - creation" begin
        constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal UC",
                description = "Unit commitment",
            ),
        )

        @test constraint.metadata.name == "Thermal UC"
        @test constraint.include_ramp_rates == true
        @test constraint.include_min_up_down == true
        @test isempty(constraint.plant_ids)
    end

    @testset "ThermalCommitmentConstraint - build!" begin
        model = Model()
        time_periods = 1:24

        # Create variables first
        create_thermal_variables!(model, system, time_periods)

        # Build constraints
        constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal UC",
                description = "Unit commitment",
            ),
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints > 0
        @test result.constraint_type == "ThermalCommitmentConstraint"
        @test isempty(result.warnings)
    end

    @testset "ThermalCommitmentConstraint - without variables" begin
        model = Model()

        constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal UC",
                description = "Unit commitment",
            ),
        )

        result = build!(model, system, constraint)

        @test result.success == false
        @test occursin("not found", result.message)
    end

    @testset "ThermalCommitmentConstraint - with specific plants" begin
        model = Model()
        time_periods = 1:24

        create_thermal_variables!(model, system, time_periods)

        constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal UC",
                description = "Unit commitment",
            ),
            plant_ids = ["T001"],  # Specific plant
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints > 0
    end

    @testset "ThermalCommitmentConstraint - without ramp rates" begin
        model = Model()
        time_periods = 1:24

        create_thermal_variables!(model, system, time_periods)

        constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal UC",
                description = "Unit commitment",
            ),
            include_ramp_rates = false,
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints > 0
    end
end

@testset "Hydro Water Balance Constraints" begin
    system = create_test_system()

    @testset "HydroWaterBalanceConstraint - creation" begin
        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance",
            ),
        )

        @test constraint.include_cascade == true
        @test constraint.include_spill == true
    end

    @testset "HydroWaterBalanceConstraint - build!" begin
        model = Model()
        time_periods = 1:24

        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance",
            ),
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints > 0
    end

    @testset "HydroWaterBalanceConstraint - without spill" begin
        model = Model()
        time_periods = 1:24

        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance",
            ),
            include_spill = false,
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints > 0
    end
end

@testset "Hydro Generation Constraints" begin
    system = create_test_system()

    @testset "HydroGenerationConstraint - creation" begin
        constraint = HydroGenerationConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Generation",
                description = "Generation function",
            ),
        )

        @test constraint.model_type == "linear"
    end

    @testset "HydroGenerationConstraint - build!" begin
        model = Model()
        time_periods = 1:24

        create_hydro_variables!(model, system, time_periods)

        constraint = HydroGenerationConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Generation",
                description = "Generation function",
            ),
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints > 0
    end
end

@testset "Submarket Balance Constraints" begin
    system = create_test_system()

    @testset "SubmarketBalanceConstraint - creation" begin
        constraint = SubmarketBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Submarket Balance",
                description = "Energy balance",
            ),
        )

        @test constraint.include_renewables == true
        @test constraint.include_deficit == true
        @test constraint.include_interconnections == true
    end

    @testset "SubmarketBalanceConstraint - creation with options" begin
        constraint = SubmarketBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Submarket Balance",
                description = "Energy balance",
            ),
            include_deficit = false,
            include_interconnections = false,
            include_renewables = false,
        )

        @test constraint.include_deficit == false
        @test constraint.include_interconnections == false
        @test constraint.include_renewables == false
    end

    @testset "SubmarketBalanceConstraint - build!" begin
        model = Model()
        time_periods = 1:24

        # Create all variables
        create_thermal_variables!(model, system, time_periods)
        create_hydro_variables!(model, system, time_periods)
        create_renewable_variables!(model, system, time_periods)

        constraint = SubmarketBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Submarket Balance",
                description = "Energy balance",
            ),
            include_deficit = false,
            include_interconnections = false,
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints > 0
    end

    @testset "SubmarketBalanceConstraint - with deficit" begin
        model = Model()
        time_periods = 1:24

        # Create all variables including deficit
        create_all_variables!(model, system, time_periods)

        constraint = SubmarketBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Submarket Balance",
                description = "Energy balance with deficit",
            ),
            include_deficit = true,
            include_interconnections = false,
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints == 24  # 1 submarket * 24 periods

        # Verify the deficit variable is in the model
        @test haskey(object_dictionary(model), :deficit)
    end

    @testset "SubmarketBalanceConstraint - with interconnections" begin
        # Create a 2-submarket system with interconnection
        bus1 = Bus(;
            id = "B001",
            name = "Bus 1",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = true,
        )
        bus2 = Bus(;
            id = "B002",
            name = "Bus 2",
            voltage_kv = 230.0,
            base_kv = 230.0,
            is_reference = false,
        )

        sm_se =
            Submarket(; id = "SM_001", name = "Southeast", code = "SE", country = "Brazil")
        sm_s = Submarket(; id = "SM_002", name = "South", code = "S", country = "Brazil")

        thermal_se = ConventionalThermal(;
            id = "T001",
            name = "Thermal SE",
            bus_id = "B001",
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
            commissioning_date = DateTime(2010, 1, 1),
        )

        hydro_s = ReservoirHydro(;
            id = "H001",
            name = "Hydro S",
            bus_id = "B002",
            submarket_id = "S",
            max_volume_hm3 = 1000.0,
            min_volume_hm3 = 100.0,
            initial_volume_hm3 = 500.0,
            max_outflow_m3_per_s = 1000.0,
            min_outflow_m3_per_s = 0.0,
            max_generation_mw = 500.0,
            min_generation_mw = 0.0,
            efficiency = 0.92,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = 1,
            initial_volume_percent = 50.0,
            must_run = false,
            downstream_plant_id = nothing,
            water_travel_time_hours = nothing,
        )

        ic = Interconnection(;
            id = "IC_SE_S",
            name = "SE to S",
            from_bus_id = "B001",
            to_bus_id = "B002",
            from_submarket_id = "SE",
            to_submarket_id = "S",
            capacity_mw = 7000.0,
            loss_percent = 2.0,
        )

        load_se = Load(;
            id = "LOAD_SE",
            name = "SE Load",
            submarket_id = "SE",
            base_mw = 400.0,
            load_profile = ones(168),
            is_elastic = false,
        )

        load_s = Load(;
            id = "LOAD_S",
            name = "S Load",
            submarket_id = "S",
            base_mw = 300.0,
            load_profile = ones(168),
            is_elastic = false,
        )

        system_2sm = ElectricitySystem(;
            thermal_plants = [thermal_se],
            hydro_plants = [hydro_s],
            wind_farms = WindPlant[],
            solar_farms = SolarPlant[],
            buses = [bus1, bus2],
            ac_lines = ACLine[],
            dc_lines = DCLine[],
            submarkets = [sm_se, sm_s],
            loads = [load_se, load_s],
            interconnections = [ic],
            base_date = Date(2025, 1, 1),
            description = "2-submarket system with interconnection",
        )

        model = Model()
        time_periods = 1:4

        create_all_variables!(model, system_2sm, time_periods)

        constraint = SubmarketBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Submarket Balance",
                description = "Balance with interconnections",
            ),
            use_time_periods = 1:4,
            include_deficit = true,
            include_interconnections = true,
        )

        result = build!(model, system_2sm, constraint)

        @test result.success == true
        @test result.num_constraints == 8  # 2 submarkets * 4 periods
        @test result.num_variables == 4    # 1 interconnection * 4 periods

        # Verify ic_flow variables were created
        @test haskey(object_dictionary(model), :ic_flow)

        # Verify flow bounds
        ic_flow = model[:ic_flow]
        @test JuMP.lower_bound(ic_flow[1, 1]) == -7000.0
        @test JuMP.upper_bound(ic_flow[1, 1]) == 7000.0
    end
end

@testset "Submarket Interconnection Constraints" begin
    system = create_test_system()

    # Add an AC line for interconnection
    bus1 = system.buses[1]
    bus2 = system.buses[2]

    line1 = ACLine(;
        id = "L001",
        name = "Line 1-2",
        from_bus_id = bus1.id,
        to_bus_id = bus2.id,
        length_km = 100.0,
        resistance_ohm = 0.01,
        reactance_ohm = 0.1,
        susceptance_siemen = 0.0,
        max_flow_mw = 500.0,
        min_flow_mw = 0.0,
        num_circuits = 1,
    )

    system_with_line = ElectricitySystem(;
        thermal_plants = system.thermal_plants,
        hydro_plants = system.hydro_plants,
        wind_farms = system.wind_farms,
        solar_farms = system.solar_farms,
        buses = system.buses,
        ac_lines = [line1],
        dc_lines = system.dc_lines,
        submarkets = system.submarkets,
        loads = system.loads,
        base_date = system.base_date,
        description = "System with interconnection",
    )

    @testset "SubmarketInterconnectionConstraint - creation" begin
        constraint = SubmarketInterconnectionConstraint(;
            metadata = ConstraintMetadata(;
                name = "Interconnection",
                description = "Transfer limits",
            ),
        )

        @test isempty(constraint.line_ids)
    end

    @testset "SubmarketInterconnectionConstraint - build!" begin
        model = Model()

        constraint = SubmarketInterconnectionConstraint(;
            metadata = ConstraintMetadata(;
                name = "Interconnection",
                description = "Transfer limits",
            ),
        )

        result = build!(model, system_with_line, constraint)

        @test result.success == true
    end
end

@testset "Renewable Limit Constraints" begin
    system = create_test_system()

    @testset "RenewableLimitConstraint - creation" begin
        constraint = RenewableLimitConstraint(;
            metadata = ConstraintMetadata(;
                name = "Renewable Limits",
                description = "Capacity limits",
            ),
        )

        @test constraint.include_curtailment == true
    end

    @testset "RenewableLimitConstraint - build!" begin
        model = Model()
        time_periods = 1:24

        create_renewable_variables!(model, system, time_periods)

        constraint = RenewableLimitConstraint(;
            metadata = ConstraintMetadata(;
                name = "Renewable Limits",
                description = "Capacity limits",
            ),
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints > 0
    end
end

@testset "Network PowerModels Constraints" begin
    system = create_test_system()

    @testset "NetworkPowerModelsConstraint - creation" begin
        # Use a dummy solver (won't actually solve in test)
        constraint = NetworkPowerModelsConstraint(;
            metadata = ConstraintMetadata(;
                name = "Network",
                description = "PowerModels network",
            ),
            formulation = "dcopf",
            base_mva = 100.0,
            solver = nothing,  # Placeholder
        )

        @test constraint.formulation == "dcopf"
        @test constraint.base_mva == 100.0
    end

    @testset "NetworkPowerModelsConstraint - build! (data validation)" begin
        model = Model()

        constraint = NetworkPowerModelsConstraint(;
            metadata = ConstraintMetadata(;
                name = "Network",
                description = "PowerModels network",
            ),
            formulation = "dcopf",
            base_mva = 100.0,
            solver = nothing,
        )

        result = build!(model, system, constraint)

        @test result.success == true
        @test !isempty(result.warnings)  # Should warn about integration pending
    end
end

@testset "Constraint Helper Functions" begin
    @testset "is_enabled, enable!, disable!" begin
        constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Test",
                description = "Test",
                enabled = true,
            ),
        )

        @test is_enabled(constraint) == true

        disable!(constraint)
        @test is_enabled(constraint) == false

        enable!(constraint)
        @test is_enabled(constraint) == true
    end

    @testset "get_priority, set_priority!" begin
        constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Test",
                description = "Test",
                priority = 10,
            ),
        )

        @test get_priority(constraint) == 10

        set_priority!(constraint, 20)
        @test get_priority(constraint) == 20
    end

    @testset "add_tag!, has_tag" begin
        constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Test",
                description = "Test",
                tags = String[],
            ),
        )

        @test has_tag(constraint, "thermal") == false

        add_tag!(constraint, "thermal")
        @test has_tag(constraint, "thermal") == true

        # Adding same tag twice should not duplicate
        add_tag!(constraint, "thermal")
        @test length(constraint.metadata.tags) == 1
    end
end

@testset "Constraint Integration - Full Workflow" begin
    system = create_test_system()

    @testset "Build all constraints" begin
        model = Model()
        time_periods = 1:24

        # Create all variables
        create_thermal_variables!(model, system, time_periods)
        create_hydro_variables!(model, system, time_periods)
        create_renewable_variables!(model, system, time_periods)

        # Build all constraints
        thermal_constraint = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal UC",
                description = "Unit commitment",
            ),
        )

        hydro_water_constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water",
                description = "Water balance",
            ),
        )

        hydro_gen_constraint = HydroGenerationConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Gen",
                description = "Generation function",
            ),
        )

        renewable_constraint = RenewableLimitConstraint(;
            metadata = ConstraintMetadata(;
                name = "Renewable",
                description = "Renewable limits",
            ),
        )

        result1 = build!(model, system, thermal_constraint)
        result2 = build!(model, system, hydro_water_constraint)
        result3 = build!(model, system, hydro_gen_constraint)
        result4 = build!(model, system, renewable_constraint)

        @test result1.success
        @test result2.success
        @test result3.success
        @test result4.success

        @test result1.num_constraints > 0
        @test result2.num_constraints > 0
        @test result3.num_constraints > 0
        @test result4.num_constraints > 0

        total_constraints =
            result1.num_constraints +
            result2.num_constraints +
            result3.num_constraints +
            result4.num_constraints

        @test total_constraints > 0
        @info "Total constraints built: $total_constraints"
    end
end
