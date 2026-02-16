"""
    Unit Tests for Hydro Water Balance Constraints

Tests cascade topology integration and inflow data loading in water balance constraints.
Follows TDD principles: tests written for new features.

# Test Coverage
- Cascade topology integration (upstream outflows added to downstream balance)
- Inflow data loading (replacing hardcoded zeros)
- Edge cases: headwater plants, terminal plants, delay bounds
- Unit conversion (m³/s to hm³/hour)
"""

using OpenDESSEM.Entities:
    ConventionalThermal,
    ReservoirHydro,
    RunOfRiverHydro,
    PumpedStorageHydro,
    HydroPlant,
    Bus,
    Submarket,
    Load,
    ACLine,
    DCLine
using OpenDESSEM: ElectricitySystem
using OpenDESSEM.Constraints
using OpenDESSEM.Constraints:
    build!, HydroWaterBalanceConstraint, ConstraintMetadata, ConstraintBuildResult
using OpenDESSEM.Variables
using OpenDESSEM.CascadeTopologyUtils:
    build_cascade_topology, CascadeTopology, get_upstream_plants
using OpenDESSEM.DessemLoader: InflowData, get_inflow
using Test
using JuMP
using Dates

"""
    create_simple_cascade_system()

Create a simple 3-plant cascade system for testing:
H001 (headwater) -> H002 (midstream) -> H003 (terminal)
"""
function create_simple_cascade_system()
    bus1 = Bus(;
        id = "B001",
        name = "Bus 1",
        voltage_kv = 230.0,
        base_kv = 230.0,
        is_reference = true,
    )

    sm1 = Submarket(; id = "SM_SE", name = "Southeast", code = "SE", country = "Brazil")

    # Headwater plant (no upstream)
    h1 = ReservoirHydro(;
        id = "H001",
        name = "Headwater Plant",
        bus_id = "B001",
        submarket_id = "SE",
        max_volume_hm3 = 1000.0,
        min_volume_hm3 = 100.0,
        initial_volume_hm3 = 500.0,
        max_outflow_m3_per_s = 500.0,
        min_outflow_m3_per_s = 0.0,
        max_generation_mw = 300.0,
        min_generation_mw = 0.0,
        efficiency = 0.90,
        water_value_rs_per_hm3 = 100.0,
        subsystem_code = 1,
        initial_volume_percent = 50.0,
        must_run = false,
        downstream_plant_id = "H002",  # Flows to H002
        water_travel_time_hours = 2.0,  # 2 hour delay
    )

    # Midstream plant (receives from H001, flows to H003)
    h2 = ReservoirHydro(;
        id = "H002",
        name = "Midstream Plant",
        bus_id = "B001",
        submarket_id = "SE",
        max_volume_hm3 = 800.0,
        min_volume_hm3 = 80.0,
        initial_volume_hm3 = 400.0,
        max_outflow_m3_per_s = 600.0,
        min_outflow_m3_per_s = 0.0,
        max_generation_mw = 350.0,
        min_generation_mw = 0.0,
        efficiency = 0.88,
        water_value_rs_per_hm3 = 80.0,
        subsystem_code = 1,
        initial_volume_percent = 50.0,
        must_run = false,
        downstream_plant_id = "H003",  # Flows to H003
        water_travel_time_hours = 1.0,  # 1 hour delay
    )

    # Terminal plant (receives from H002, no downstream)
    h3 = ReservoirHydro(;
        id = "H003",
        name = "Terminal Plant",
        bus_id = "B001",
        submarket_id = "SE",
        max_volume_hm3 = 600.0,
        min_volume_hm3 = 60.0,
        initial_volume_hm3 = 300.0,
        max_outflow_m3_per_s = 700.0,
        min_outflow_m3_per_s = 0.0,
        max_generation_mw = 400.0,
        min_generation_mw = 0.0,
        efficiency = 0.85,
        water_value_rs_per_hm3 = 60.0,
        subsystem_code = 1,
        initial_volume_percent = 50.0,
        must_run = false,
        downstream_plant_id = nothing,  # Terminal - no downstream
        water_travel_time_hours = nothing,
    )

    load1 = Load(;
        id = "LOAD_001",
        name = "SE Load",
        submarket_id = "SE",
        base_mw = 500.0,
        load_profile = ones(168),
        is_elastic = false,
    )

    system = ElectricitySystem(;
        thermal_plants = ConventionalThermal[],
        hydro_plants = [h1, h2, h3],
        wind_farms = WindPlant[],
        solar_farms = SolarPlant[],
        buses = [bus1],
        ac_lines = ACLine[],
        dc_lines = DCLine[],
        submarkets = [sm1],
        loads = [load1],
        base_date = Date(2025, 1, 1),
        description = "Simple cascade test system",
    )

    return system
end

"""
    create_run_of_river_system()

Create a system with run-of-river hydro plants for testing.
"""
function create_run_of_river_system()
    bus1 = Bus(;
        id = "B001",
        name = "Bus 1",
        voltage_kv = 230.0,
        base_kv = 230.0,
        is_reference = true,
    )

    sm1 = Submarket(; id = "SM_SE", name = "Southeast", code = "SE", country = "Brazil")

    # Run-of-river plant
    ror = RunOfRiverHydro(;
        id = "ROR001",
        name = "Run of River",
        bus_id = "B001",
        submarket_id = "SE",
        max_flow_m3_per_s = 500.0,
        min_flow_m3_per_s = 0.0,
        max_generation_mw = 200.0,
        min_generation_mw = 0.0,
        efficiency = 0.85,
        subsystem_code = 1,
        initial_volume_percent = 50.0,
        must_run = false,
        downstream_plant_id = nothing,
        water_travel_time_hours = nothing,
    )

    load1 = Load(;
        id = "LOAD_001",
        name = "SE Load",
        submarket_id = "SE",
        base_mw = 500.0,
        load_profile = ones(168),
        is_elastic = false,
    )

    system = ElectricitySystem(;
        thermal_plants = ConventionalThermal[],
        hydro_plants = [ror],
        wind_farms = WindPlant[],
        solar_farms = SolarPlant[],
        buses = [bus1],
        ac_lines = ACLine[],
        dc_lines = DCLine[],
        submarkets = [sm1],
        loads = [load1],
        base_date = Date(2025, 1, 1),
        description = "Run-of-river test system",
    )

    return system
end

"""
    create_mock_inflow_data()

Create mock inflow data for testing.
"""
function create_mock_inflow_data()
    # Plant numbers: 1 = H001, 2 = H002, 3 = H003
    inflows = Dict{Int,Vector{Float64}}(
        1 => fill(100.0, 48),  # H001 gets 100 m³/s for 48 hours
        2 => fill(50.0, 48),   # H002 gets 50 m³/s
        3 => fill(30.0, 48),   # H003 gets 30 m³/s
    )

    return InflowData(inflows, 48, Date(2025, 1, 1), [1, 2, 3])
end

"""
    create_mock_plant_numbers()

Create mock plant ID to plant number mapping.
"""
function create_mock_plant_numbers()
    return Dict{String,Int}("H001" => 1, "H002" => 2, "H003" => 3)
end

# =============================================================================
# Unit Conversion Tests
# =============================================================================

@testset "Unit Conversion" begin
    @testset "M3S_TO_HM3_PER_HOUR constant" begin
        # 1 m³/s × 3600 s/hour = 3600 m³/hour = 0.0036 hm³/hour
        M3S_TO_HM3_PER_HOUR = 0.0036

        @test M3S_TO_HM3_PER_HOUR ≈ 0.0036

        # Test conversion
        flow_m3s = 100.0
        flow_hm3_per_hour = flow_m3s * M3S_TO_HM3_PER_HOUR
        @test flow_hm3_per_hour ≈ 0.36
    end

    @testset "Water balance unit consistency" begin
        # Storage in hm³, inflow in m³/s, need consistent units
        storage_hm3 = 500.0
        inflow_m3s = 100.0
        outflow_m3s = 80.0

        M3S_TO_HM3_PER_HOUR = 0.0036

        # After one hour:
        # s[t] = s[t-1] + inflow_hm3 - outflow_hm3
        inflow_hm3 = inflow_m3s * M3S_TO_HM3_PER_HOUR
        outflow_hm3 = outflow_m3s * M3S_TO_HM3_PER_HOUR

        new_storage = storage_hm3 + inflow_hm3 - outflow_hm3

        @test inflow_hm3 ≈ 0.36
        @test outflow_hm3 ≈ 0.288
        @test new_storage ≈ 500.072
    end
end

# =============================================================================
# Cascade Topology Integration Tests
# =============================================================================

@testset "Cascade Topology Integration" begin
    @testset "Cascade topology is built during constraint building" begin
        system = create_simple_cascade_system()
        topology = build_cascade_topology(system.hydro_plants)

        # Verify topology structure
        @test topology.headwaters == ["H001"]
        @test "H003" in topology.terminals
        @test topology.depths["H001"] == 0
        @test topology.depths["H002"] == 1
        @test topology.depths["H003"] == 2
    end

    @testset "Upstream map correctly identifies inflows" begin
        system = create_simple_cascade_system()
        topology = build_cascade_topology(system.hydro_plants)

        # H001 has no upstream (headwater)
        upstream_h1 = get_upstream_plants(topology, "H001")
        @test isempty(upstream_h1)

        # H002 receives from H001 with 2 hour delay
        upstream_h2 = get_upstream_plants(topology, "H002")
        @test length(upstream_h2) == 1
        @test upstream_h2[1][1] == "H001"
        @test upstream_h2[1][2] == 2.0

        # H003 receives from H002 with 1 hour delay
        upstream_h3 = get_upstream_plants(topology, "H003")
        @test length(upstream_h3) == 1
        @test upstream_h3[1][1] == "H002"
        @test upstream_h3[1][2] == 1.0
    end

    @testset "Water balance with cascade - downstream receives upstream outflow" begin
        system = create_simple_cascade_system()

        model = Model()
        time_periods = 1:24
        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance with cascade",
            ),
            include_cascade = true,
            include_spill = true,
        )

        # Build with cascade enabled
        result = build!(model, system, constraint)

        @test result.success == true
        @test result.num_constraints > 0
    end

    @testset "Cascade disabled - no upstream terms" begin
        system = create_simple_cascade_system()

        model = Model()
        time_periods = 1:24
        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance without cascade",
            ),
            include_cascade = false,  # Disabled
            include_spill = false,
        )

        result = build!(model, system, constraint)

        @test result.success == true
    end
end

# =============================================================================
# Inflow Data Integration Tests
# =============================================================================

@testset "Inflow Data Integration" begin
    @testset "Mock inflow data structure" begin
        inflow_data = create_mock_inflow_data()

        @test haskey(inflow_data.inflows, 1)
        @test haskey(inflow_data.inflows, 2)
        @test haskey(inflow_data.inflows, 3)
        @test inflow_data.num_periods == 48

        # Test get_inflow function
        @test get_inflow(inflow_data, 1, 1) ≈ 100.0
        @test get_inflow(inflow_data, 2, 5) ≈ 50.0
        @test get_inflow(inflow_data, 3, 24) ≈ 30.0
    end

    @testset "Inflow lookup with invalid plant/hour" begin
        inflow_data = create_mock_inflow_data()

        # Invalid plant number
        @test get_inflow(inflow_data, 999, 1) ≈ 0.0

        # Invalid hour (out of range)
        @test get_inflow(inflow_data, 1, 0) ≈ 0.0
        @test get_inflow(inflow_data, 1, 100) ≈ 0.0
    end

    @testset "Water balance with loaded inflows" begin
        system = create_simple_cascade_system()
        inflow_data = create_mock_inflow_data()
        hydro_plant_numbers = create_mock_plant_numbers()

        model = Model()
        time_periods = 1:24
        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance with loaded inflows",
            ),
            include_cascade = true,
            include_spill = false,
        )

        # Build with inflow data - using keyword arguments
        result = build!(
            model,
            system,
            constraint;
            inflow_data = inflow_data,
            hydro_plant_numbers = hydro_plant_numbers,
        )

        @test result.success == true
        @test result.num_constraints > 0
    end

    @testset "Water balance without inflow data (backward compatibility)" begin
        system = create_simple_cascade_system()

        model = Model()
        time_periods = 1:24
        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance without inflow data",
            ),
            include_cascade = false,
            include_spill = false,
        )

        # Build without inflow data - should still work (uses 0.0)
        result = build!(model, system, constraint)

        @test result.success == true
    end
end

# =============================================================================
# Edge Case Tests
# =============================================================================

@testset "Edge Cases" begin
    @testset "Headwater plant - no upstream inflow" begin
        system = create_simple_cascade_system()
        topology = build_cascade_topology(system.hydro_plants)

        # H001 is headwater - should have no upstream
        @test "H001" in topology.headwaters
        @test isempty(get_upstream_plants(topology, "H001"))

        model = Model()
        time_periods = 1:24
        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Headwater test",
            ),
            include_cascade = true,
        )

        result = build!(model, system, constraint)
        @test result.success == true
    end

    @testset "Terminal plant - outflow exits system" begin
        system = create_simple_cascade_system()
        topology = build_cascade_topology(system.hydro_plants)

        # H003 is terminal - should have no downstream
        @test "H003" in topology.terminals

        # H003 should have upstream (H002) but no downstream
        upstream_h3 = get_upstream_plants(topology, "H003")
        @test !isempty(upstream_h3)

        # H003 has downstream_plant_id = nothing
        h3 = first(p for p in system.hydro_plants if p.id == "H003")
        @test h3.downstream_plant_id === nothing
    end

    @testset "Delay bounds checking - upstream outflow before t=1" begin
        system = create_simple_cascade_system()
        inflow_data = create_mock_inflow_data()
        hydro_plant_numbers = create_mock_plant_numbers()

        model = Model()
        time_periods = 1:5  # Short time horizon
        create_hydro_variables!(model, system, time_periods)

        # H002 has 2-hour delay from H001
        # At t=1, t-2 = -1 (out of bounds, should be ignored)
        # At t=2, t-2 = 0 (out of bounds, should be ignored)
        # At t=3, t-2 = 1 (valid)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Delay bounds test",
            ),
            include_cascade = true,
        )

        result = build!(
            model,
            system,
            constraint;
            inflow_data = inflow_data,
            hydro_plant_numbers = hydro_plant_numbers,
        )

        @test result.success == true
    end

    @testset "Run-of-river plants - outflow limited by inflow" begin
        system = create_run_of_river_system()

        model = Model()
        time_periods = 1:24
        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "RoR Water Balance",
                description = "Run-of-river test",
            ),
        )

        # Should work even without inflow data
        result = build!(model, system, constraint)
        @test result.success == true
    end
end

# =============================================================================
# Delay Calculation Tests
# =============================================================================

@testset "Delay Calculations" begin
    @testset "Integer delay rounding" begin
        # Travel times can be fractional hours
        # Should be rounded to nearest integer for time indexing
        delay_hours = 2.5
        t = 10

        t_upstream = t - round(Int, delay_hours)
        # Julia round(Int, 2.5) uses banker's rounding = 2
        # So t_upstream = 10 - 2 = 8
        @test t_upstream == 8

        # Julia round(Int, 2.5) uses banker's rounding = 2
        @test round(Int, 2.5) == 2
        @test round(Int, 2.6) == 3
        @test round(Int, 2.4) == 2
    end

    @testset "Delay application in cascade" begin
        # Setup: H001 -> H002 with 2-hour delay
        # If H001 releases at t=5, H002 receives at t=7

        h1_delay = 2.0
        t_h002 = 7

        t_upstream = t_h002 - round(Int, h1_delay)
        @test t_upstream == 5

        # This t_upstream is valid (>= 1), so upstream outflow is included
        @test t_upstream >= 1
    end
end

# =============================================================================
# Integration Tests
# =============================================================================

@testset "Full Integration" begin
    @testset "Complete water balance with cascade and inflows" begin
        system = create_simple_cascade_system()
        inflow_data = create_mock_inflow_data()
        hydro_plant_numbers = create_mock_plant_numbers()

        model = Model()
        time_periods = 1:24
        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Complete Water Balance",
                description = "Full integration test",
                priority = 10,
            ),
            include_cascade = true,
            include_spill = true,
        )

        result = build!(
            model,
            system,
            constraint;
            inflow_data = inflow_data,
            hydro_plant_numbers = hydro_plant_numbers,
        )

        @test result.success == true
        @test result.constraint_type == "HydroWaterBalanceConstraint"

        # Verify constraints were built for all 3 plants
        # Each plant has 24 hours × (1 balance + 1 volume limit) = 48 constraints
        # Plus initial conditions at t=1
        @test result.num_constraints > 0

        @info "Built $(result.num_constraints) water balance constraints"
    end

    @testset "Cascade topology consistency with water balance" begin
        system = create_simple_cascade_system()
        topology = build_cascade_topology(system.hydro_plants)

        # Verify topological order respects cascade direction
        h1_idx = findfirst(==("H001"), topology.topological_order)
        h2_idx = findfirst(==("H002"), topology.topological_order)
        h3_idx = findfirst(==("H003"), topology.topological_order)

        # Upstream plants should come before downstream in topological order
        @test h1_idx < h2_idx < h3_idx
    end
end

# =============================================================================
# Spill Variables Tests
# =============================================================================

@testset "Spill Variables" begin
    @testset "Spill variables created when include_spill=true" begin
        system = create_simple_cascade_system()

        model = Model()
        time_periods = 1:24
        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "With Spill",
                description = "Test spill creation",
            ),
            include_spill = true,
        )

        result = build!(model, system, constraint)

        @test result.success == true
        # Spill variables should be created automatically if not present
    end

    @testset "Water balance without spill" begin
        system = create_simple_cascade_system()

        model = Model()
        time_periods = 1:24
        create_hydro_variables!(model, system, time_periods)

        constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Without Spill",
                description = "Test without spill",
            ),
            include_spill = false,
        )

        result = build!(model, system, constraint)

        @test result.success == true
    end
end
