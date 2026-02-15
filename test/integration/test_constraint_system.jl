"""
    Integration Tests for Constraint System

Tests the full constraint building workflow from system loading
through constraint building to model readiness.
"""

using OpenDESSEM
using OpenDESSEM.Constraints
using OpenDESSEM.Variables
using Test
using JuMP
using Dates

"""
Helper function to create a realistic multi-plant test system.
"""
function create_integration_test_system()
    # Create buses
    buses = Bus[]
    for i in 1:5
        push!(buses, Bus(;
            id="B00$i",
            name="Bus $i",
            voltage_kv=230.0,
            base_kv=230.0,
            is_reference=(i == 1)
        ))
    end

    # Create submarkets (4 Brazilian submarkets)
    submarkets = [
        Submarket(; id="SM_SE", name="Southeast", code="SE", country="Brazil"),
        Submarket(; id="SM_S", name="South", code="S", country="Brazil"),
        Submarket(; id="SM_NE", name="Northeast", code="NE", country="Brazil"),
        Submarket(; id="SM_N", name="North", code="N", country="Brazil")
    ]

    # Create thermal plants
    thermal_plants = ConventionalThermal[]
    for (sm, idx) in zip(["SE", "S", "NE", "N"], 1:4)
        push!(thermal_plants, ConventionalThermal(;
            id="T_$(sm)_001",
            name="$(sm) Thermal Plant",
            bus_id=buses[idx].id,
            submarket_id=sm,
            fuel_type=NATURAL_GAS,
            capacity_mw=500.0,
            min_generation_mw=100.0,
            max_generation_mw=500.0,
            ramp_up_mw_per_min=50.0,
            ramp_down_mw_per_min=50.0,
            min_up_time_hours=4,
            min_down_time_hours=2,
            fuel_cost_rsj_per_mwh=150.0,
            startup_cost_rs=10000.0,
            shutdown_cost_rs=5000.0,
            commissioning_date=DateTime(2010, 1, 1)
        ))
    end

    # Create hydro plants
    hydro_plants = ReservoirHydro[]
    for (sm, idx) in zip(["SE", "S"], 1:2)
        push!(hydro_plants, ReservoirHydro(;
            id="H_$(sm)_001",
            name="$(sm) Hydro Plant",
            bus_id=buses[idx].id,
            submarket_id=sm,
            max_volume_hm3=1000.0,
            min_volume_hm3=100.0,
            initial_volume_hm3=500.0,
            max_outflow_m3_per_s=1000.0,
            min_outflow_m3_per_s=0.0,
            max_generation_mw=500.0,
            min_generation_mw=0.0,
            efficiency=0.92,
            water_value_rs_per_hm3=50.0,
            subsystem_code=idx,
            initial_volume_percent=50.0,
            must_run=false,
            downstream_plant_id=nothing,
            water_travel_time_hours=nothing
        ))
    end

    # Create wind farms
    wind_farms = WindPlant[]
    for (sm, idx) in zip(["NE", "S"], 3:4)
        push!(wind_farms, WindPlant(;
            id="W_$(sm)_001",
            name="$(sm) Wind Farm",
            bus_id=buses[idx].id,
            submarket_id=sm,
            installed_capacity_mw=200.0,
            min_generation_mw=0.0,
            max_generation_mw=200.0,
            capacity_forecast_mw=ones(168) .* 150.0,
            forecast_type=DETERMINISTIC,
            commissioning_date=DateTime(2020, 1, 1)
        ))
    end

    # Create loads for each submarket
    loads = Load[]
    for sm in ["SE", "S", "NE", "N"]
        push!(loads, Load(;
            id="LOAD_$(sm)_001",
            name="$(sm) Load",
            submarket_id=sm,
            base_mw=5000.0,
            load_profile=ones(168) .+ (rand(168) .* 0.2),  # ±20% variation
            is_elastic=false
        ))
    end

    # Create interconnections (AC lines)
    ac_lines = ACLine[]
    push!(ac_lines, ACLine(;
        id="L_SE_S",
        name="SE-S Interconnection",
        from_bus_id=buses[1].id,
        to_bus_id=buses[2].id,
        length_km=500.0,
        resistance_ohm=0.01,
        reactance_ohm=0.1,
        susceptance_siemen=0.0,
        max_flow_mw=2000.0,
        min_flow_mw=0.0,
        num_circuits=2
    ))

    # Assemble system
    system = ElectricitySystem(;
        thermal_plants=thermal_plants,
        hydro_plants=hydro_plants,
        wind_farms=wind_farms,
        solar_farms=SolarPlant[],
        buses=buses,
        ac_lines=ac_lines,
        dc_lines=DCLine[],
        submarkets=submarkets,
        loads=loads,
        base_date=Date(2025, 1, 1),
        description="4-submarket integration test system"
    )

    return system
end

@testset "Constraint System Integration Tests" begin
    @testset "Full workflow - 24 hour horizon" begin
        system = create_integration_test_system()
        time_periods = 1:24

        # Create model
        model = Model()

        # Create all variables
        @test_logs create_thermal_variables!(model, system, time_periods)
        @test_logs create_hydro_variables!(model, system, time_periods)
        @test_logs create_renewable_variables!(model, system, time_periods)

        # Verify variables exist
        @test haskey(object_dictionary(model), :u)
        @test haskey(object_dictionary(model), :v)
        @test haskey(object_dictionary(model), :w)
        @test haskey(object_dictionary(model), :g)
        @test haskey(object_dictionary(model), :s)
        @test haskey(object_dictionary(model), :q)
        @test haskey(object_dictionary(model), :gh)
        @test haskey(object_dictionary(model), :gr)
        @test haskey(object_dictionary(model), :curtail)

        # Build thermal constraints
        thermal_constraint = ThermalCommitmentConstraint(;
            metadata=ConstraintMetadata(;
                name="Thermal UC",
                description="Unit commitment for thermal plants",
                priority=10
            )
        )

        thermal_result = build!(model, system, thermal_constraint)
        @test thermal_result.success
        @test thermal_result.num_constraints > 0
        @info "Thermal constraints: $(thermal_result.num_constraints)"

        # Build hydro water balance constraints
        hydro_water_constraint = HydroWaterBalanceConstraint(;
            metadata=ConstraintMetadata(;
                name="Hydro Water Balance",
                description="Reservoir water balance",
                priority=10
            )
        )

        hydro_water_result = build!(model, system, hydro_water_constraint)
        @test hydro_water_result.success
        @test hydro_water_result.num_constraints > 0
        @info "Hydro water balance constraints: $(hydro_water_result.num_constraints)"

        # Build hydro generation constraints
        hydro_gen_constraint = HydroGenerationConstraint(;
            metadata=ConstraintMetadata(;
                name="Hydro Generation",
                description="Hydro generation function",
                priority=10
            )
        )

        hydro_gen_result = build!(model, system, hydro_gen_constraint)
        @test hydro_gen_result.success
        @test hydro_gen_result.num_constraints > 0
        @info "Hydro generation constraints: $(hydro_gen_result.num_constraints)"

        # Build submarket balance constraints
        submarket_constraint = SubmarketBalanceConstraint(;
            metadata=ConstraintMetadata(;
                name="Submarket Balance",
                description="4-submarket energy balance",
                priority=10
            )
        )

        submarket_result = build!(model, system, submarket_constraint)
        @test submarket_result.success
        @test submarket_result.num_constraints > 0
        @info "Submarket balance constraints: $(submarket_result.num_constraints)"

        # Build renewable constraints
        renewable_constraint = RenewableLimitConstraint(;
            metadata=ConstraintMetadata(;
                name="Renewable Limits",
                description="Wind and solar capacity limits",
                priority=10
            )
        )

        renewable_result = build!(model, system, renewable_constraint)
        @test renewable_result.success
        @test renewable_result.num_constraints > 0
        @info "Renewable limit constraints: $(renewable_result.num_constraints)"

        # Build interconnection constraints
        interconnection_constraint = SubmarketInterconnectionConstraint(;
            metadata=ConstraintMetadata(;
                name="Interconnection Limits",
                description="Transfer limits between submarkets",
                priority=10
            )
        )

        interconnection_result = build!(model, system, interconnection_constraint)
        @test interconnection_result.success
        @info "Interconnection constraints: $(interconnection_result.num_constraints)"

        # Verify model has constraints
        num_constraints = num_constraints(model)
        @test num_constraints > 0
        @info "Total constraints in model: $num_constraints"

        # Verify model is ready for solving (has variables and constraints)
        @test num_variables(model) > 0
        @test num_constraints > 0
        @info "Total variables in model: $(num_variables(model))"
    end

    @testset "Error handling - missing variables" begin
        system = create_integration_test_system()
        model = Model()

        # Try to build constraints without creating variables
        thermal_constraint = ThermalCommitmentConstraint(;
            metadata=ConstraintMetadata(;
                name="Thermal UC",
                description="Unit commitment"
            )
        )

        result = build!(model, system, thermal_constraint)

        @test result.success == false
        @test occursin("not found", result.message)
    end

    @testset "Constraint priority system" begin
        constraint1 = ThermalCommitmentConstraint(;
            metadata=ConstraintMetadata(;
                name="Low Priority",
                description="Test",
                priority=5
            )
        )

        constraint2 = ThermalCommitmentConstraint(;
            metadata=ConstraintMetadata(;
                name="High Priority",
                description="Test",
                priority=20
            )
        )

        @test get_priority(constraint1) < get_priority(constraint2)
    end

    @testset "Constraint tagging system" begin
        constraint = ThermalCommitmentConstraint(;
            metadata=ConstraintMetadata(;
                name="Test",
                description="Test",
                tags=String[]
            )
        )

        add_tag!(constraint, "thermal")
        add_tag!(constraint, "unit-commitment")
        add_tag!(constraint, "operational")

        @test has_tag(constraint, "thermal")
        @test has_tag(constraint, "unit-commitment")
        @test has_tag(constraint, "operational")
        @test !has_tag(constraint, "hydro")

        @test length(constraint.metadata.tags) == 3
    end

    @testset "Enable/disable constraints" begin
        constraint = ThermalCommitmentConstraint(;
            metadata=ConstraintMetadata(;
                name="Test",
                description="Test",
                enabled=true
            )
        )

        @test is_enabled(constraint)

        disable!(constraint)
        @test !is_enabled(constraint)

        enable!(constraint)
        @test is_enabled(constraint)
    end

    @testset "Constraint-specific plant filtering" begin
        system = create_integration_test_system()
        model = Model()
        time_periods = 1:24

        create_thermal_variables!(model, system, time_periods)

        # Build constraint for specific plants only
        constraint = ThermalCommitmentConstraint(;
            metadata=ConstraintMetadata(;
                name="Selective Thermal UC",
                description="Only SE thermal plants"
            ),
            plant_ids=["T_SE_001"]
        )

        result = build!(model, system, constraint)

        @test result.success
        @test result.num_constraints > 0

        # Should have fewer constraints than all plants
        all_plants_constraint = ThermalCommitmentConstraint(;
            metadata=ConstraintMetadata(;
                name="All Thermal UC",
                description="All thermal plants"
            ),
            plant_ids=[]
        )

        all_result = build!(model, system, all_plants_constraint)

        @test all_result.success
        @test all_result.num_constraints > result.num_constraints
    end

    @testset "Weekly horizon (168 hours)" begin
        system = create_integration_test_system()
        time_periods = 1:168

        model = Model()

        create_thermal_variables!(model, system, time_periods)
        create_hydro_variables!(model, system, time_periods)

        thermal_constraint = ThermalCommitmentConstraint(;
            metadata=ConstraintMetadata(;
                name="Weekly Thermal UC",
                description="Weekly unit commitment"
            )
        )

        result = build!(model, system, thermal_constraint)

        @test result.success
        @test result.num_constraints > 0
        @info "Weekly thermal constraints: $(result.num_constraints)"
    end

    @testset "Multiple constraint interactions" begin
        system = create_integration_test_system()
        time_periods = 1:24

        model = Model()

        create_all_variables!(model, system, time_periods)

        # Build multiple constraint types
        constraints = [
            ThermalCommitmentConstraint(;
                metadata=ConstraintMetadata(;
                    name="Thermal UC",
                    description="Unit commitment"
                )
            ),
            HydroWaterBalanceConstraint(;
                metadata=ConstraintMetadata(;
                    name="Hydro Water",
                    description="Water balance"
                )
            ),
            HydroGenerationConstraint(;
                metadata=ConstraintMetadata(;
                    name="Hydro Gen",
                    description="Generation function"
                )
            ),
            RenewableLimitConstraint(;
                metadata=ConstraintMetadata(;
                    name="Renewable",
                    description="Renewable limits"
                )
            )
        ]

        total_constraints = 0
        for constraint in constraints
            result = build!(model, system, constraint)
            @test result.success
            total_constraints += result.num_constraints
        end

        @test total_constraints > 0
        @info "Total constraints from multiple types: $total_constraints"

        # Verify model integrity
        @test num_variables(model) > 0
        @test num_constraints(model) > 0
    end
end
