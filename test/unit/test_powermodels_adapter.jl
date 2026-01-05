"""
    Test suite for PowerModels.jl adapter

Tests conversion of OpenDESSEM entities to PowerModels.jl data format.
"""

using OpenDESSEM
using OpenDESSEM.Integration
using Test
using Dates

@testset "PowerModels Adapter Tests" begin

    # Test fixtures
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

    function create_test_ac_line(; id::String, from_bus::String, to_bus::String)
        ACLine(;
            id = id,
            name = "Line $id",
            from_bus_id = from_bus,
            to_bus_id = to_bus,
            length_km = 100.0,
            resistance_ohm = 0.01,
            reactance_ohm = 0.1,
            susceptance_siemen = 0.0,
            max_flow_mw = 500.0,
            min_flow_mw = 0.0,
            num_circuits = 1,
        )
    end

    function create_test_thermal_plant(; id::String, bus_id::String)
        ConventionalThermal(;
            id = id,
            name = "Thermal $id",
            bus_id = bus_id,
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

    function create_test_hydro_plant(; id::String, bus_id::String)
        ReservoirHydro(;
            id = id,
            name = "Hydro $id",
            bus_id = bus_id,
            submarket_id = "SE",
            max_volume_hm3 = 10000.0,
            min_volume_hm3 = 1000.0,
            initial_volume_hm3 = 5000.0,
            max_outflow_m3_per_s = 1000.0,
            min_outflow_m3_per_s = 0.0,
            max_generation_mw = 1000.0,
            min_generation_mw = 0.0,
            efficiency = 0.9,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = 1,
            initial_volume_percent = 50.0,
        )
    end

    function create_test_wind_plant(; id::String, bus_id::String)
        WindPlant(;
            id = id,
            name = "Wind $id",
            bus_id = bus_id,
            submarket_id = "SE",
            installed_capacity_mw = 200.0,
            capacity_forecast_mw = [150.0, 160.0, 140.0],
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = 200.0,
            ramp_up_mw_per_min = 20.0,
            ramp_down_mw_per_min = 20.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.02,
            is_dispatchable = true,
            commissioning_date = DateTime(2020, 1, 1),
        )
    end

    function create_test_load(; id::String, bus_id::String)
        NetworkLoad(;
            id = id,
            name = "Load $id",
            bus_id = bus_id,
            submarket_id = "SE",
            load_profile_mw = [100.0, 110.0, 105.0],
            is_firm = true,
        )
    end

    @testset "Bus Conversion" begin
        @testset "Reference bus" begin
            bus = create_test_bus(id = "B1", is_reference = true)
            pm_bus = convert_bus_to_powermodel(bus, 1, 230.0)

            @test pm_bus["bus_i"] == 1
            @test pm_bus["bus_type"] == 3  # Reference bus
            @test pm_bus["base_kv"] == 230.0
            @test pm_bus["vmin"] == 0.9
            @test pm_bus["vmax"] == 1.1
            @test pm_bus["vm"] == 1.0
            @test pm_bus["va"] == 0.0
        end

        @testset "PQ bus" begin
            bus = create_test_bus(id = "B2", is_reference = false)
            pm_bus = convert_bus_to_powermodel(bus, 2, 230.0)

            @test pm_bus["bus_i"] == 2
            @test pm_bus["bus_type"] == 1  # PQ bus
        end

        @testset "Area and zone hashing" begin
            bus = create_test_bus(id = "B3", is_reference = false)
            pm_bus = convert_bus_to_powermodel(bus, 3, 230.0)

            @test pm_bus["area"] isa Integer  # Can be Int or UInt
            @test pm_bus["zone"] isa Integer  # Can be Int or UInt
            @test pm_bus["area"] >= 0
            @test pm_bus["zone"] >= 0
        end
    end

    @testset "AC Line Conversion" begin
        @testset "Basic line conversion" begin
            bus1 = create_test_bus(id = "B1")
            bus2 = create_test_bus(id = "B2")
            line = create_test_ac_line(id = "L1", from_bus = "B1", to_bus = "B2")

            bus_lookup = Dict("B1" => 1, "B2" => 2)
            pm_line = convert_line_to_powermodel(line, bus_lookup, 230.0)

            @test pm_line["f_bus"] == 1
            @test pm_line["t_bus"] == 2
            @test pm_line["rate_a"] == 500.0
            @test pm_line["rate_b"] == 500.0
            @test pm_line["rate_c"] == 500.0
            @test pm_line["tap"] == 1.0
            @test pm_line["angmin"] == -30.0
            @test pm_line["angmax"] == 30.0
            @test pm_line["transformer"] == false
        end

        @testset "Per-unit impedance calculation" begin
            line = create_test_ac_line(id = "L1", from_bus = "B1", to_bus = "B2")
            bus_lookup = Dict("B1" => 1, "B2" => 2)

            base_kv = 230.0
            pm_line = convert_line_to_powermodel(line, bus_lookup, base_kv)

            expected_br_r = 0.01 / (230.0^2)
            expected_br_x = 0.1 / (230.0^2)

            @test isapprox(pm_line["br_r"], expected_br_r, rtol = 1e-10)
            @test isapprox(pm_line["br_x"], expected_br_x, rtol = 1e-10)
            @test pm_line["br_b"] == 0.0
        end

        @testset "Error on missing from bus" begin
            line = create_test_ac_line(id = "L1", from_bus = "B1", to_bus = "B2")
            bus_lookup = Dict("B2" => 2)  # Missing B1

            @test_throws ArgumentError convert_line_to_powermodel(line, bus_lookup, 230.0)
        end

        @testset "Error on missing to bus" begin
            line = create_test_ac_line(id = "L1", from_bus = "B1", to_bus = "B2")
            bus_lookup = Dict("B1" => 1)  # Missing B2

            @test_throws ArgumentError convert_line_to_powermodel(line, bus_lookup, 230.0)
        end
    end

    @testset "Thermal Generator Conversion" begin
        @testset "Basic thermal conversion" begin
            thermal = create_test_thermal_plant(id = "T1", bus_id = "B1")
            bus_lookup = Dict("B1" => 1)

            pm_gen = convert_gen_to_powermodel(thermal, bus_lookup, 230.0)

            @test pm_gen["gen_bus"] == 1
            @test pm_gen["pmin"] == 100.0
            @test pm_gen["pmax"] == 500.0
            @test pm_gen["gen_status"] == 1
            @test pm_gen["gen_type"] == 2  # Thermal
        end

        @testset "Reactive power defaults" begin
            thermal = create_test_thermal_plant(id = "T1", bus_id = "B1")
            bus_lookup = Dict("B1" => 1)

            pm_gen = convert_gen_to_powermodel(thermal, bus_lookup, 230.0)

            @test pm_gen["qmax"] == 250.0  # 0.5 * pmax
            @test pm_gen["qmin"] == -250.0  # -0.5 * pmax
        end

        @testset "Error on missing bus" begin
            thermal = create_test_thermal_plant(id = "T1", bus_id = "B1")
            bus_lookup = Dict("B2" => 2)  # Missing B1

            @test_throws ArgumentError convert_gen_to_powermodel(thermal, bus_lookup, 230.0)
        end
    end

    @testset "Hydro Generator Conversion" begin
        @testset "Basic hydro conversion" begin
            hydro = create_test_hydro_plant(id = "H1", bus_id = "B1")
            bus_lookup = Dict("B1" => 1)

            pm_gen = convert_gen_to_powermodel(hydro, bus_lookup, 230.0)

            @test pm_gen["gen_bus"] == 1
            @test pm_gen["pmin"] == 0.0
            @test pm_gen["pmax"] == 1000.0
            @test pm_gen["gen_type"] == 1  # Hydro
            @test pm_gen["gen_status"] == 1
        end
    end

    @testset "Renewable Generator Conversion" begin
        @testset "Wind plant conversion" begin
            wind = create_test_wind_plant(id = "W1", bus_id = "B1")
            bus_lookup = Dict("B1" => 1)

            pm_gen = convert_gen_to_powermodel(wind, bus_lookup, 230.0)

            @test pm_gen["gen_bus"] == 1
            @test pm_gen["pmin"] == 0.0
            @test pm_gen["pmax"] == 200.0
            @test pm_gen["gen_type"] == 3  # Renewable
        end

        @testset "Solar plant conversion" begin
            solar = SolarPlant(;
                id = "S1",
                name = "Solar 1",
                bus_id = "B1",
                submarket_id = "SE",
                installed_capacity_mw = 100.0,
                capacity_forecast_mw = [80.0, 90.0, 85.0],
                forecast_type = DETERMINISTIC,
                min_generation_mw = 0.0,
                max_generation_mw = 100.0,
                ramp_up_mw_per_min = 20.0,
                ramp_down_mw_per_min = 20.0,
                curtailment_allowed = true,
                forced_outage_rate = 0.02,
                is_dispatchable = false,
                commissioning_date = DateTime(2020, 1, 1),
                tracking_system = "FIXED",
            )
            bus_lookup = Dict("B1" => 1)

            pm_gen = convert_gen_to_powermodel(solar, bus_lookup, 230.0)

            @test pm_gen["gen_type"] == 3  # Renewable
            @test pm_gen["pmax"] == 100.0
        end
    end

    @testset "Load Conversion" begin
        @testset "Firm load conversion" begin
            load = create_test_load(id = "LD1", bus_id = "B1")
            bus_lookup = Dict("B1" => 1)

            pm_load = convert_load_to_powermodel(load, bus_lookup)

            @test pm_load["load_bus"] == 1
            @test pm_load["pd"] == 100.0  # First period
            @test pm_load["qd"] == 10.0  # 10% of pd
            @test pm_load["status"] == 1  # Firm
        end

        @testset "Interruptible load conversion" begin
            load = NetworkLoad(;
                id = "LD1",
                name = "Load 1",
                bus_id = "B1",
                submarket_id = "SE",
                load_profile_mw = [100.0, 110.0],
                is_firm = false,
            )
            bus_lookup = Dict("B1" => 1)

            pm_load = convert_load_to_powermodel(load, bus_lookup)

            @test pm_load["status"] == 0  # Interruptible
        end

        @testset "Empty load profile rejected" begin
            # NetworkLoad entity now validates that load_profile_mw cannot be empty
            @test_throws ArgumentError NetworkLoad(;
                id = "LD1",
                name = "Load 1",
                bus_id = "B1",
                submarket_id = "SE",
                load_profile_mw = Float64[],
                is_firm = true,
            )
        end

        @testset "Error on missing bus" begin
            load = create_test_load(id = "LD1", bus_id = "B1")
            bus_lookup = Dict("B2" => 2)  # Missing B1

            @test_throws ArgumentError convert_load_to_powermodel(load, bus_lookup)
        end
    end

    @testset "Complete System Conversion" begin
        @testset "Three-bus system" begin
            # Create buses
            buses = [
                create_test_bus(id = "B1", is_reference = true),
                create_test_bus(id = "B2", is_reference = false),
                create_test_bus(id = "B3", is_reference = false),
            ]

            # Create lines
            lines = [
                create_test_ac_line(id = "L1", from_bus = "B1", to_bus = "B2"),
                create_test_ac_line(id = "L2", from_bus = "B2", to_bus = "B3"),
                create_test_ac_line(id = "L3", from_bus = "B1", to_bus = "B3"),
            ]

            # Create generators
            thermals = [create_test_thermal_plant(id = "T1", bus_id = "B1")]
            hydros = [create_test_hydro_plant(id = "H1", bus_id = "B2")]
            renewables = [create_test_wind_plant(id = "W1", bus_id = "B3")]

            # Create loads
            loads = [
                create_test_load(id = "LD1", bus_id = "B1"),
                create_test_load(id = "LD2", bus_id = "B2"),
            ]

            # Convert to PowerModels
            pm_data = convert_to_powermodel(;
                buses = buses,
                lines = lines,
                thermals = thermals,
                hydros = hydros,
                renewables = renewables,
                loads = loads,
                base_mva = 100.0,
            )

            # Validate structure
            @test haskey(pm_data, "bus")
            @test haskey(pm_data, "branch")
            @test haskey(pm_data, "gen")
            @test haskey(pm_data, "load")
            @test haskey(pm_data, "baseMVA")

            # Check counts
            @test length(pm_data["bus"]) == 3
            @test length(pm_data["branch"]) == 3
            @test length(pm_data["gen"]) == 3  # 1 thermal + 1 hydro + 1 wind
            @test length(pm_data["load"]) == 2

            # Check baseMVA
            @test pm_data["baseMVA"] == 100.0

            # Check bus indices
            @test pm_data["bus"]["1"]["bus_i"] == 1
            @test pm_data["bus"]["2"]["bus_i"] == 2
            @test pm_data["bus"]["3"]["bus_i"] == 3

            # Check reference bus
            @test pm_data["bus"]["1"]["bus_type"] == 3
            @test pm_data["bus"]["2"]["bus_type"] == 1
        end

        @testset "Minimal system (single bus)" begin
            buses = [create_test_bus(id = "B1", is_reference = true)]
            lines = ACLine[]  # No lines

            pm_data =
                convert_to_powermodel(; buses = buses, lines = lines, base_mva = 100.0)

            @test length(pm_data["bus"]) == 1
            @test length(pm_data["branch"]) == 0
            @test length(pm_data["gen"]) == 0
            @test length(pm_data["load"]) == 0
        end
    end

    @testset "find_bus_index" begin
        @testset "Find existing bus" begin
            buses = [
                create_test_bus(id = "B1"),
                create_test_bus(id = "B2"),
                create_test_bus(id = "B3"),
            ]

            @test find_bus_index("B1", buses) == 1
            @test find_bus_index("B2", buses) == 2
            @test find_bus_index("B3", buses) == 3
        end

        @testset "Error on non-existent bus" begin
            buses = [create_test_bus(id = "B1")]

            @test_throws ArgumentError find_bus_index("B2", buses)
        end
    end

    @testset "validate_powermodel_conversion" begin
        @testset "Valid system passes" begin
            buses = [
                create_test_bus(id = "B1", is_reference = true),
                create_test_bus(id = "B2", is_reference = false),
            ]
            lines = [create_test_ac_line(id = "L1", from_bus = "B1", to_bus = "B2")]

            pm_data =
                convert_to_powermodel(; buses = buses, lines = lines, base_mva = 100.0)

            @test validate_powermodel_conversion(pm_data) == true
        end

        @testset "Missing baseMVA fails" begin
            pm_data = Dict{String,Any}(
                "bus" => Dict("1" => Dict("bus_type" => 3)),
                "branch" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
                # Missing baseMVA
            )

            @test validate_powermodel_conversion(pm_data) == false
        end

        @testset "No reference bus fails" begin
            pm_data = Dict{String,Any}(
                "bus" => Dict("1" => Dict("bus_type" => 1)),  # Only PQ buses
                "branch" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
                "baseMVA" => 100.0,
            )

            @test validate_powermodel_conversion(pm_data) == false
        end

        @testset "Negative baseMVA fails" begin
            pm_data = Dict{String,Any}(
                "bus" => Dict("1" => Dict("bus_type" => 3)),
                "branch" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
                "baseMVA" => -100.0,
            )

            @test validate_powermodel_conversion(pm_data) == false
        end
    end

    @testset "Edge Cases" begin
        @testset "Empty system" begin
            pm_data =
                convert_to_powermodel(; buses = Bus[], lines = ACLine[], base_mva = 100.0)

            @test length(pm_data["bus"]) == 0
            @test length(pm_data["branch"]) == 0
        end

        @testset "System with only generators" begin
            buses = [create_test_bus(id = "B1", is_reference = true)]
            lines = ACLine[]
            thermals = [create_test_thermal_plant(id = "T1", bus_id = "B1")]

            pm_data = convert_to_powermodel(;
                buses = buses,
                lines = lines,
                thermals = thermals,
                base_mva = 100.0,
            )

            @test length(pm_data["gen"]) == 1
            @test validate_powermodel_conversion(pm_data) == true
        end

        @testset "System with only loads" begin
            buses = [create_test_bus(id = "B1", is_reference = true)]
            lines = ACLine[]
            loads = [create_test_load(id = "LD1", bus_id = "B1")]

            pm_data = convert_to_powermodel(;
                buses = buses,
                lines = lines,
                loads = loads,
                base_mva = 100.0,
            )

            @test length(pm_data["load"]) == 1
            @test validate_powermodel_conversion(pm_data) == true
        end
    end

    @testset "Integration: Bus lookup consistency" begin
        @testset "Multi-generator system" begin
            buses = [
                create_test_bus(id = "B1", is_reference = true),
                create_test_bus(id = "B2", is_reference = false),
                create_test_bus(id = "B3", is_reference = false),
            ]

            # Generators on different buses
            thermals = [
                create_test_thermal_plant(id = "T1", bus_id = "B1"),
                create_test_thermal_plant(id = "T2", bus_id = "B2"),
            ]
            hydros = [create_test_hydro_plant(id = "H1", bus_id = "B3")]
            renewables = [create_test_wind_plant(id = "W1", bus_id = "B1")]

            lines = [
                create_test_ac_line(id = "L1", from_bus = "B1", to_bus = "B2"),
                create_test_ac_line(id = "L2", from_bus = "B2", to_bus = "B3"),
            ]

            loads = [
                create_test_load(id = "LD1", bus_id = "B1"),
                create_test_load(id = "LD2", bus_id = "B2"),
                create_test_load(id = "LD3", bus_id = "B3"),
            ]

            pm_data = convert_to_powermodel(;
                buses = buses,
                lines = lines,
                thermals = thermals,
                hydros = hydros,
                renewables = renewables,
                loads = loads,
                base_mva = 100.0,
            )

            # All generators should be on valid buses
            for (gen_id, gen) in pm_data["gen"]
                bus_idx = gen["gen_bus"]
                @test bus_idx in [1, 2, 3]
                @test haskey(pm_data["bus"], string(bus_idx))
            end

            # All loads should be on valid buses
            for (load_id, load) in pm_data["load"]
                bus_idx = load["load_bus"]
                @test bus_idx in [1, 2, 3]
                @test haskey(pm_data["bus"], string(bus_idx))
            end

            # All lines should connect valid buses
            for (branch_id, branch) in pm_data["branch"]
                from_idx = branch["f_bus"]
                to_idx = branch["t_bus"]
                @test from_idx in [1, 2, 3]
                @test to_idx in [1, 2, 3]
                @test haskey(pm_data["bus"], string(from_idx))
                @test haskey(pm_data["bus"], string(to_idx))
            end
        end
    end
end
