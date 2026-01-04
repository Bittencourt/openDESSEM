"""
    Test suite for electrical network entities

Tests for Bus, ACLine, and DCLine entities following TDD principles.
"""

using OpenDESSEM
using Test

@testset "Network Entity Tests" begin

    @testset "Bus - Constructor" begin
        @testset "Valid AC bus" begin
            bus = Bus(;
                id = "B_001",
                name = "Substation Alpha",
                voltage_kv = 230.0,
                base_kv = 230.0,
                dc_bus = false,
                is_reference = true,
                area_id = "NE",
                zone_id = "Z1",
                latitude = -23.5,
                longitude = -46.6,
            )

            @test bus.id == "B_001"
            @test bus.name == "Substation Alpha"
            @test bus.voltage_kv == 230.0
            @test bus.base_kv == 230.0
            @test bus.dc_bus == false
            @test bus.is_reference == true
            @test bus.area_id == "NE"
            @test bus.zone_id == "Z1"
            @test bus.latitude == -23.5
            @test bus.longitude == -46.6
            @test bus isa NetworkEntity
            @test bus isa PhysicalEntity
        end

        @testset "Valid DC bus" begin
            bus = Bus(;
                id = "B_002",
                name = "DC Converter Station",
                voltage_kv = 400.0,
                base_kv = 400.0,
                dc_bus = true,
                is_reference = false,
            )

            @test bus.dc_bus == true
            @test bus.is_reference == false
            @test bus.area_id === nothing
            @test bus.latitude === nothing
        end

        @testset "Default values" begin
            bus = Bus(;
                id = "B_003",
                name = "Default Bus",
                voltage_kv = 138.0,
                base_kv = 138.0,
            )

            @test bus.dc_bus == false  # Default
            @test bus.is_reference == false  # Default
            @test bus.area_id === nothing
            @test bus.zone_id === nothing
            @test bus.latitude === nothing
            @test bus.longitude === nothing
            @test bus.metadata !== nothing
        end
    end

    @testset "Bus - Validation" begin
        @testset "Invalid voltage" begin
            @test_throws ArgumentError Bus(;
                id = "B_001",
                name = "Invalid Voltage",
                voltage_kv = -230.0,
                base_kv = 230.0,
            )

            @test_throws ArgumentError Bus(;
                id = "B_001",
                name = "Zero Voltage",
                voltage_kv = 0.0,
                base_kv = 230.0,
            )

            @test_throws ArgumentError Bus(;
                id = "B_001",
                name = "Invalid Base Voltage",
                voltage_kv = 230.0,
                base_kv = 0.0,
            )
        end

        @testset "Invalid coordinates" begin
            @test_throws ArgumentError Bus(;
                id = "B_001",
                name = "Invalid Latitude",
                voltage_kv = 230.0,
                base_kv = 230.0,
                latitude = 95.0,  # > 90
            )

            @test_throws ArgumentError Bus(;
                id = "B_001",
                name = "Invalid Longitude",
                voltage_kv = 230.0,
                base_kv = 230.0,
                longitude = 185.0,  # > 180
            )

            @test_throws ArgumentError Bus(;
                id = "B_001",
                name = "Invalid Latitude Low",
                voltage_kv = 230.0,
                base_kv = 230.0,
                latitude = -95.0,  # < -90
            )
        end

        @testset "Invalid ID format" begin
            @test_throws ArgumentError Bus(;
                id = "",  # Empty string
                name = "Invalid ID",
                voltage_kv = 230.0,
                base_kv = 230.0,
            )
        end
    end

    @testset "ACLine - Constructor" begin
        @testset "Valid AC line" begin
            line = ACLine(;
                id = "L_001",
                name = "Alpha to Beta",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 150.0,
                resistance_ohm = 5.2,
                reactance_ohm = 15.8,
                susceptance_siemen = 0.0002,
                max_flow_mw = 500.0,
                min_flow_mw = 0.0,
                num_circuits = 1,
            )

            @test line.id == "L_001"
            @test line.name == "Alpha to Beta"
            @test line.from_bus_id == "B_001"
            @test line.to_bus_id == "B_002"
            @test line.length_km == 150.0
            @test line.resistance_ohm == 5.2
            @test line.reactance_ohm == 15.8
            @test line.susceptance_siemen == 0.0002
            @test line.max_flow_mw == 500.0
            @test line.min_flow_mw == 0.0
            @test line.num_circuits == 1
            @test line isa NetworkEntity
            @test line isa PhysicalEntity
        end

        @testset "AC line with zero resistance" begin
            line = ACLine(;
                id = "L_002",
                name = "Zero Resistance Line",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 100.0,
                resistance_ohm = 0.0,
                reactance_ohm = 10.0,
                susceptance_siemen = 0.0,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
            )

            @test line.resistance_ohm == 0.0
            @test line.susceptance_siemen == 0.0
        end

        @testset "Default values" begin
            line = ACLine(;
                id = "L_003",
                name = "Default Line",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 120.0,
                resistance_ohm = 4.0,
                reactance_ohm = 12.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 300.0,
                min_flow_mw = 0.0,
            )

            @test line.num_circuits == 1  # Default
            @test line.metadata !== nothing
        end
    end

    @testset "ACLine - Validation" begin
        @testset "Same bus IDs" begin
            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Same Bus",
                from_bus_id = "B_001",
                to_bus_id = "B_001",  # Same as from_bus_id
                length_km = 100.0,
                resistance_ohm = 5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
            )
        end

        @testset "Invalid length" begin
            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Zero Length",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 0.0,
                resistance_ohm = 5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
            )

            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Negative Length",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = -100.0,
                resistance_ohm = 5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
            )
        end

        @testset "Invalid electrical parameters" begin
            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Negative Resistance",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 100.0,
                resistance_ohm = -5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
            )

            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Zero Reactance",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 100.0,
                resistance_ohm = 5.0,
                reactance_ohm = 0.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
            )

            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Negative Susceptance",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 100.0,
                resistance_ohm = 5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = -0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
            )
        end

        @testset "Invalid flow limits" begin
            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Min > Max Flow",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 100.0,
                resistance_ohm = 5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 300.0,
                min_flow_mw = 400.0,  # > max_flow
            )

            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Negative Min Flow",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 100.0,
                resistance_ohm = 5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = -10.0,
            )
        end

        @testset "Invalid number of circuits" begin
            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Zero Circuits",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 100.0,
                resistance_ohm = 5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
                num_circuits = 0,
            )

            @test_throws ArgumentError ACLine(;
                id = "L_001",
                name = "Negative Circuits",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 100.0,
                resistance_ohm = 5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
                num_circuits = -1,
            )
        end
    end

    @testset "DCLine - Constructor" begin
        @testset "Valid DC line" begin
            line = DCLine(;
                id = "DC_001",
                name = "HVDC Interconnector",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 800.0,
                max_flow_mw = 2000.0,
                min_flow_mw = 0.0,
                resistance_ohm = 10.5,
                inductance_henry = 0.5,
            )

            @test line.id == "DC_001"
            @test line.name == "HVDC Interconnector"
            @test line.from_bus_id == "B_001"
            @test line.to_bus_id == "B_002"
            @test line.length_km == 800.0
            @test line.max_flow_mw == 2000.0
            @test line.min_flow_mw == 0.0
            @test line.resistance_ohm == 10.5
            @test line.inductance_henry == 0.5
            @test line isa NetworkEntity
            @test line isa PhysicalEntity
        end

        @testset "DC line with zero inductance" begin
            line = DCLine(;
                id = "DC_002",
                name = "Zero Inductance DC Line",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 600.0,
                max_flow_mw = 1500.0,
                min_flow_mw = 0.0,
                resistance_ohm = 8.0,
                inductance_henry = 0.0,
            )

            @test line.inductance_henry == 0.0
        end

        @testset "Default values" begin
            line = DCLine(;
                id = "DC_003",
                name = "Default DC Line",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 500.0,
                max_flow_mw = 1000.0,
                min_flow_mw = 0.0,
                resistance_ohm = 6.0,
                inductance_henry = 0.3,
            )

            @test line.metadata !== nothing
            @test line.metadata.version == 1
        end
    end

    @testset "DCLine - Validation" begin
        @testset "Same bus IDs" begin
            @test_throws ArgumentError DCLine(;
                id = "DC_001",
                name = "Same Bus",
                from_bus_id = "B_001",
                to_bus_id = "B_001",  # Same as from_bus_id
                length_km = 500.0,
                max_flow_mw = 1000.0,
                min_flow_mw = 0.0,
                resistance_ohm = 6.0,
                inductance_henry = 0.3,
            )
        end

        @testset "Invalid length" begin
            @test_throws ArgumentError DCLine(;
                id = "DC_001",
                name = "Zero Length",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 0.0,
                max_flow_mw = 1000.0,
                min_flow_mw = 0.0,
                resistance_ohm = 6.0,
                inductance_henry = 0.3,
            )
        end

        @testset "Invalid flow limits" begin
            @test_throws ArgumentError DCLine(;
                id = "DC_001",
                name = "Zero Max Flow",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 500.0,
                max_flow_mw = 0.0,
                min_flow_mw = 0.0,
                resistance_ohm = 6.0,
                inductance_henry = 0.3,
            )

            @test_throws ArgumentError DCLine(;
                id = "DC_001",
                name = "Min > Max Flow",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 500.0,
                max_flow_mw = 1000.0,
                min_flow_mw = 1500.0,  # > max_flow
                resistance_ohm = 6.0,
                inductance_henry = 0.3,
            )

            @test_throws ArgumentError DCLine(;
                id = "DC_001",
                name = "Negative Min Flow",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 500.0,
                max_flow_mw = 1000.0,
                min_flow_mw = -10.0,
                resistance_ohm = 6.0,
                inductance_henry = 0.3,
            )
        end

        @testset "Invalid electrical parameters" begin
            @test_throws ArgumentError DCLine(;
                id = "DC_001",
                name = "Negative Resistance",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 500.0,
                max_flow_mw = 1000.0,
                min_flow_mw = 0.0,
                resistance_ohm = -6.0,
                inductance_henry = 0.3,
            )

            @test_throws ArgumentError DCLine(;
                id = "DC_001",
                name = "Negative Inductance",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 500.0,
                max_flow_mw = 1000.0,
                min_flow_mw = 0.0,
                resistance_ohm = 6.0,
                inductance_henry = -0.3,
            )
        end
    end

    @testset "NetworkEntity - Type Hierarchy" begin
        @testset "Bus type hierarchy" begin
            bus =
                Bus(; id = "B_001", name = "Test Bus", voltage_kv = 230.0, base_kv = 230.0)

            @test bus isa NetworkEntity
            @test bus isa PhysicalEntity
            @test bus isa AbstractEntity
            @test NetworkEntity <: PhysicalEntity
            @test PhysicalEntity <: AbstractEntity
        end

        @testset "ACLine type hierarchy" begin
            line = ACLine(;
                id = "L_001",
                name = "Test Line",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 100.0,
                resistance_ohm = 5.0,
                reactance_ohm = 15.0,
                susceptance_siemen = 0.0001,
                max_flow_mw = 400.0,
                min_flow_mw = 0.0,
            )

            @test line isa NetworkEntity
            @test line isa PhysicalEntity
            @test line isa AbstractEntity
        end

        @testset "DCLine type hierarchy" begin
            line = DCLine(;
                id = "DC_001",
                name = "Test DC Line",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 500.0,
                max_flow_mw = 1000.0,
                min_flow_mw = 0.0,
                resistance_ohm = 6.0,
                inductance_henry = 0.3,
            )

            @test line isa NetworkEntity
            @test line isa PhysicalEntity
            @test line isa AbstractEntity
        end
    end

    @testset "NetworkEntity - Edge Cases" begin
        @testset "High voltage bus" begin
            bus = Bus(;
                id = "B_001",
                name = "Extra High Voltage",
                voltage_kv = 500.0,
                base_kv = 500.0,
            )

            @test bus.voltage_kv == 500.0
        end

        @testset "Long AC transmission line" begin
            line = ACLine(;
                id = "L_001",
                name = "Long Distance Line",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 1000.0,
                resistance_ohm = 50.0,
                reactance_ohm = 150.0,
                susceptance_siemen = 0.001,
                max_flow_mw = 1000.0,
                min_flow_mw = 0.0,
            )

            @test line.length_km == 1000.0
        end

        @testset "High capacity HVDC" begin
            line = DCLine(;
                id = "DC_001",
                name = "Ultra High Voltage DC",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 2000.0,
                max_flow_mw = 8000.0,
                min_flow_mw = 0.0,
                resistance_ohm = 20.0,
                inductance_henry = 1.0,
            )

            @test line.max_flow_mw == 8000.0
        end

        @testset "Multiple circuits" begin
            line = ACLine(;
                id = "L_001",
                name = "Double Circuit",
                from_bus_id = "B_001",
                to_bus_id = "B_002",
                length_km = 150.0,
                resistance_ohm = 5.2,
                reactance_ohm = 15.8,
                susceptance_siemen = 0.0002,
                max_flow_mw = 1000.0,
                min_flow_mw = 0.0,
                num_circuits = 2,
            )

            @test line.num_circuits == 2
        end
    end

    @testset "NetworkLoad - Constructor" begin
        @testset "Valid load with profile" begin
            profile = collect(100.0:10.0:330.0)  # 24-hour profile
            load = NetworkLoad(;
                id = "LOAD_001",
                name = "Industrial Load Alpha",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = profile,
                is_firm = true,
                is_interruptible = false,
                priority = 1,
                price_elasticity = -0.1,
                interruption_cost_rs_per_mwh = 5000.0,
            )

            @test load.id == "LOAD_001"
            @test load.name == "Industrial Load Alpha"
            @test load.bus_id == "B_001"
            @test load.submarket_id == "SE"
            @test length(load.load_profile_mw) == 24
            @test load.load_profile_mw[1] == 100.0
            @test load.load_profile_mw[24] == 330.0
            @test load.is_firm == true
            @test load.is_interruptible == false
            @test load.priority == 1
            @test load.price_elasticity == -0.1
            @test load.interruption_cost_rs_per_mwh == 5000.0
            @test load isa NetworkEntity
            @test load isa PhysicalEntity
        end

        @testset "Valid curtaillable load" begin
            profile = collect(50.0:5.0:165.0)
            load = NetworkLoad(;
                id = "LOAD_002",
                name = "Curtailable Load",
                bus_id = "B_002",
                submarket_id = "NE",
                load_profile_mw = profile,
                is_firm = false,
                is_interruptible = true,
                priority = 5,
                interruption_cost_rs_per_mwh = 2000.0,
            )

            @test load.is_firm == false
            @test load.is_interruptible == true
            @test load.priority == 5
            @test load.price_elasticity === nothing  # Default
        end

        @testset "Default values" begin
            profile = ones(24) * 100.0
            load = NetworkLoad(;
                id = "LOAD_003",
                name = "Default Load",
                bus_id = "B_003",
                submarket_id = "S",
                load_profile_mw = profile,
            )

            @test load.is_firm == true  # Default
            @test load.is_interruptible == false  # Default
            @test load.priority == 5  # Default
            @test load.price_elasticity === nothing
            @test load.interruption_cost_rs_per_mwh === nothing
            @test load.metadata !== nothing
        end
    end

    @testset "NetworkLoad - Validation" begin
        @testset "Empty load profile" begin
            @test_throws ArgumentError NetworkLoad(;
                id = "LOAD_001",
                name = "Empty Profile",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = Float64[],
            )
        end

        @testset "Negative demand in profile" begin
            profile = copy(ones(24) * 100.0)
            profile[5] = -10.0
            @test_throws ArgumentError NetworkLoad(;
                id = "LOAD_001",
                name = "Negative Demand",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = profile,
            )
        end

        @testset "Zero demand in profile" begin
            profile = copy(ones(24) * 100.0)
            profile[10] = 0.0
            @test_throws ArgumentError NetworkLoad(;
                id = "LOAD_001",
                name = "Zero Demand",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = profile,
            )
        end

        @testset "Invalid priority" begin
            profile = ones(24) * 100.0
            @test_throws ArgumentError NetworkLoad(;
                id = "LOAD_001",
                name = "Zero Priority",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = profile,
                priority = 0,
            )

            @test_throws ArgumentError NetworkLoad(;
                id = "LOAD_001",
                name = "High Priority",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = profile,
                priority = 11,
            )
        end

        @testset "Invalid price elasticity" begin
            profile = ones(24) * 100.0
            @test_throws ArgumentError NetworkLoad(;
                id = "LOAD_001",
                name = "Positive Elasticity",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = profile,
                price_elasticity = 0.1,  # Should be negative
            )

            @test_throws ArgumentError NetworkLoad(;
                id = "LOAD_001",
                name = "Too Negative Elasticity",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = profile,
                price_elasticity = -2.0,  # Should be >= -1.0
            )
        end

        @testset "Negative interruption cost" begin
            profile = ones(24) * 100.0
            @test_throws ArgumentError NetworkLoad(;
                id = "LOAD_001",
                name = "Negative Interruption Cost",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = profile,
                interruption_cost_rs_per_mwh = -100.0,
            )
        end

        @testset "Firm but interruptible contradiction" begin
            profile = ones(24) * 100.0
            @test_throws ArgumentError NetworkLoad(;
                id = "LOAD_001",
                name = "Contradiction",
                bus_id = "B_001",
                submarket_id = "SE",
                load_profile_mw = profile,
                is_firm = true,
                is_interruptible = true,  # Can't be both
            )
        end
    end

    @testset "NetworkSubmarket - Constructor" begin
        @testset "Valid SE/CO submarket" begin
            demand = collect(10000.0:100.0:12300.0)
            interconnections = Dict("S" => 2000.0, "NE" => 1500.0, "N" => 1000.0)
            submarket = NetworkSubmarket(;
                id = "SE",
                name = "Sudeste/Centro-Oeste",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_SE_REF",
            )

            @test submarket.id == "SE"
            @test submarket.name == "Sudeste/Centro-Oeste"
            @test length(submarket.demand_forecast_mw) == 24
            @test submarket.demand_forecast_mw[1] == 10000.0
            @test submarket.interconnection_capacity_mw["S"] == 2000.0
            @test submarket.interconnection_capacity_mw["NE"] == 1500.0
            @test submarket.interconnection_capacity_mw["N"] == 1000.0
            @test submarket.reference_bus_id == "BUS_SE_REF"
            @test submarket isa NetworkEntity
            @test submarket isa PhysicalEntity
        end

        @testset "Valid South submarket" begin
            demand = collect(5000.0:50.0:6150.0)
            interconnections = Dict("SE" => 2000.0, "N" => 500.0)
            submarket = NetworkSubmarket(;
                id = "S",
                name = "South",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_S_REF",
            )

            @test submarket.id == "S"
            @test submarket.name == "South"
            @test length(submarket.demand_forecast_mw) == 24
            @test submarket.interconnection_capacity_mw["SE"] == 2000.0
        end

        @testset "Valid Northeast submarket" begin
            demand = collect(7000.0:70.0:8610.0)
            interconnections = Dict("SE" => 1500.0)
            submarket = NetworkSubmarket(;
                id = "NE",
                name = "Northeast",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_NE_REF",
            )

            @test submarket.id == "NE"
            @test submarket.name == "Northeast"
        end

        @testset "Valid North submarket" begin
            demand = collect(3000.0:30.0:3690.0)
            interconnections = Dict("SE" => 1000.0, "S" => 500.0)
            submarket = NetworkSubmarket(;
                id = "N",
                name = "North",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_N_REF",
            )

            @test submarket.id == "N"
            @test submarket.name == "North"
        end
    end

    @testset "NetworkSubmarket - Validation" begin
        @testset "Invalid submarket ID" begin
            demand = ones(24) * 5000.0
            interconnections = Dict("SE" => 1000.0)
            @test_throws ArgumentError NetworkSubmarket(;
                id = "XX",  # Invalid
                name = "Invalid Submarket",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_REF",
            )

            @test_throws ArgumentError NetworkSubmarket(;
                id = "SUL",  # Too long
                name = "Invalid Submarket",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_REF",
            )
        end

        @testset "Empty demand forecast" begin
            interconnections = Dict("SE" => 1000.0)
            @test_throws ArgumentError NetworkSubmarket(;
                id = "S",
                name = "South",
                demand_forecast_mw = Float64[],
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_REF",
            )
        end

        @testset "Negative demand forecast" begin
            demand = copy(ones(24) * 5000.0)
            demand[5] = -100.0
            interconnections = Dict("SE" => 1000.0)
            @test_throws ArgumentError NetworkSubmarket(;
                id = "S",
                name = "South",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_REF",
            )
        end

        @testset "Zero demand forecast" begin
            demand = copy(ones(24) * 5000.0)
            demand[10] = 0.0
            interconnections = Dict("SE" => 1000.0)
            @test_throws ArgumentError NetworkSubmarket(;
                id = "S",
                name = "South",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_REF",
            )
        end

        @testset "Empty interconnections" begin
            demand = ones(24) * 5000.0
            @test_throws ArgumentError NetworkSubmarket(;
                id = "S",
                name = "South",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = Dict{String,Float64}(),
                reference_bus_id = "BUS_REF",
            )
        end

        @testset "Negative interconnection capacity" begin
            demand = ones(24) * 5000.0
            interconnections = Dict("SE" => -1000.0)
            @test_throws ArgumentError NetworkSubmarket(;
                id = "S",
                name = "South",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_REF",
            )
        end

        @testset "Self-interconnection" begin
            demand = ones(24) * 5000.0
            interconnections = Dict("S" => 1000.0)  # Self
            @test_throws ArgumentError NetworkSubmarket(;
                id = "S",
                name = "South",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_REF",
            )
        end

        @testset "Invalid interconnection submarket ID" begin
            demand = ones(24) * 5000.0
            interconnections = Dict("XX" => 1000.0)  # Invalid
            @test_throws ArgumentError NetworkSubmarket(;
                id = "S",
                name = "South",
                demand_forecast_mw = demand,
                interconnection_capacity_mw = interconnections,
                reference_bus_id = "BUS_REF",
            )
        end
    end

end
