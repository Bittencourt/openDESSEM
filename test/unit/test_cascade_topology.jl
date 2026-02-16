"""
    Tests for cascade topology utility module.

Tests for building DAG topology from hydro plant downstream_plant_id references,
detecting circular dependencies, and computing plant depths.
"""

using Test
using Logging: Logging, AbstractLogger, with_logger, @warn

# Use the package modules
using OpenDESSEM.Entities
using OpenDESSEM.CascadeTopologyUtils

# Helper function to create a reservoir hydro plant for testing
function make_test_hydro(;
    id::String,
    name::String = "Test Plant $id",
    downstream_id::Union{String,Nothing} = nothing,
    travel_time::Union{Float64,Nothing} = nothing,
)
    # If downstream is set, travel_time must also be set
    if downstream_id !== nothing && travel_time === nothing
        travel_time = 1.0  # Default travel time
    end

    return ReservoirHydro(;
        id = id,
        name = name,
        bus_id = "B001",
        submarket_id = "SE",
        max_volume_hm3 = 10000.0,
        min_volume_hm3 = 1000.0,
        initial_volume_hm3 = 5000.0,
        max_outflow_m3_per_s = 5000.0,
        min_outflow_m3_per_s = 0.0,
        max_generation_mw = 1000.0,
        min_generation_mw = 0.0,
        efficiency = 0.9,
        water_value_rs_per_hm3 = 50.0,
        subsystem_code = 1,
        initial_volume_percent = 50.0,
        downstream_plant_id = downstream_id,
        water_travel_time_hours = travel_time,
    )
end

# Simple test logger to capture warnings
Base.@kwdef struct WarningCaptureLogger <: AbstractLogger
    messages::Vector{String} = String[]
end

function Logging.handle_message(
    logger::WarningCaptureLogger,
    level,
    message,
    _module,
    group,
    id,
    filepath,
    line;
    kwargs...,
)
    push!(logger.messages, String(message))
end

Logging.shouldlog(logger::WarningCaptureLogger, level, _module, group, id) = true
Logging.min_enabled_level(logger::WarningCaptureLogger) = Logging.Warn

@testset "CascadeTopology" begin

    @testset "CascadeTopology struct" begin
        @testset "Empty topology" begin
            topology = CascadeTopology(;
                upstream_map = Dict{String,Vector{Tuple{String,Float64}}}(),
                depths = Dict{String,Int}(),
                topological_order = String[],
                headwaters = String[],
                terminals = String[],
            )

            @test isempty(topology.upstream_map)
            @test isempty(topology.depths)
            @test isempty(topology.topological_order)
            @test isempty(topology.headwaters)
            @test isempty(topology.terminals)
        end

        @testset "Topology with data" begin
            topology = CascadeTopology(;
                upstream_map = Dict("H002" => [("H001", 2.0)], "H003" => [("H002", 3.0)]),
                depths = Dict("H001" => 0, "H002" => 1, "H003" => 2),
                topological_order = ["H001", "H002", "H003"],
                headwaters = ["H001"],
                terminals = ["H003"],
            )

            @test length(topology.upstream_map) == 2
            @test topology.depths["H001"] == 0
            @test topology.depths["H002"] == 1
            @test topology.depths["H003"] == 2
            @test topology.topological_order == ["H001", "H002", "H003"]
            @test "H001" in topology.headwaters
            @test "H003" in topology.terminals
        end
    end

    @testset "build_cascade_topology - Basic cases" begin
        @testset "Empty list of plants" begin
            plants = HydroPlant[]
            topology = build_cascade_topology(plants)

            @test isempty(topology.upstream_map)
            @test isempty(topology.depths)
            @test isempty(topology.topological_order)
            @test isempty(topology.headwaters)
            @test isempty(topology.terminals)
        end

        @testset "Single plant with no downstream" begin
            plants = HydroPlant[make_test_hydro(id = "H001")]
            topology = build_cascade_topology(plants)

            @test haskey(topology.depths, "H001")
            @test topology.depths["H001"] == 0  # Headwater
            @test "H001" in topology.headwaters
            @test "H001" in topology.terminals  # Also terminal (no downstream)
            @test "H001" in topology.topological_order
        end

        @testset "Two plants - linear cascade" begin
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H002", travel_time = 2.0),
                make_test_hydro(id = "H002"),
            ]
            topology = build_cascade_topology(plants)

            # Check depths
            @test topology.depths["H001"] == 0  # Headwater
            @test topology.depths["H002"] == 1  # Downstream of H001

            # Check upstream map
            @test haskey(topology.upstream_map, "H002")
            @test ("H001", 2.0) in topology.upstream_map["H002"]

            # Check headwaters/terminals
            @test "H001" in topology.headwaters
            @test "H002" in topology.terminals

            # Check topological order
            @test topology.topological_order == ["H001", "H002"]
        end

        @testset "Three plants - linear cascade" begin
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H002", travel_time = 2.0),
                make_test_hydro(id = "H002", downstream_id = "H003", travel_time = 3.0),
                make_test_hydro(id = "H003"),
            ]
            topology = build_cascade_topology(plants)

            @test topology.depths["H001"] == 0
            @test topology.depths["H002"] == 1
            @test topology.depths["H003"] == 2

            @test "H001" in topology.headwaters
            @test "H003" in topology.terminals

            # Check upstream relationships
            @test ("H001", 2.0) in topology.upstream_map["H002"]
            @test ("H002", 3.0) in topology.upstream_map["H003"]
        end
    end

    @testset "build_cascade_topology - Multiple upstream (confluence)" begin
        @testset "Two plants flowing to one" begin
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H003", travel_time = 2.0),
                make_test_hydro(id = "H002", downstream_id = "H003", travel_time = 1.5),
                make_test_hydro(id = "H003"),
            ]
            topology = build_cascade_topology(plants)

            # Both H001 and H002 are headwaters
            @test "H001" in topology.headwaters
            @test "H002" in topology.headwaters

            # H003 has both as upstream
            @test length(topology.upstream_map["H003"]) == 2
            @test ("H001", 2.0) in topology.upstream_map["H003"]
            @test ("H002", 1.5) in topology.upstream_map["H003"]

            # H003 is terminal
            @test "H003" in topology.terminals

            # H003 depth should be 1 (max depth of upstream + 1)
            @test topology.depths["H003"] == 1
        end

        @testset "Complex confluence with different depths" begin
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H002", travel_time = 1.0),
                make_test_hydro(id = "H002", downstream_id = "H004", travel_time = 2.0),
                make_test_hydro(id = "H003", downstream_id = "H004", travel_time = 1.0),
                make_test_hydro(id = "H004"),
            ]
            topology = build_cascade_topology(plants)

            @test topology.depths["H001"] == 0
            @test topology.depths["H002"] == 1
            @test topology.depths["H003"] == 0  # Also headwater
            @test topology.depths["H004"] == 2  # Max(H002, H003) + 1

            @test "H001" in topology.headwaters
            @test "H003" in topology.headwaters
            @test "H004" in topology.terminals
        end
    end

    @testset "build_cascade_topology - Disconnected plants" begin
        @testset "Two independent plants" begin
            plants = HydroPlant[make_test_hydro(id = "H001"), make_test_hydro(id = "H002")]
            topology = build_cascade_topology(plants)

            @test topology.depths["H001"] == 0
            @test topology.depths["H002"] == 0

            # Both are headwaters AND terminals
            @test "H001" in topology.headwaters
            @test "H002" in topology.headwaters
            @test "H001" in topology.terminals
            @test "H002" in topology.terminals
        end

        @testset "Two independent cascades" begin
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H002", travel_time = 1.0),
                make_test_hydro(id = "H002"),
                make_test_hydro(id = "H003", downstream_id = "H004", travel_time = 2.0),
                make_test_hydro(id = "H004"),
            ]
            topology = build_cascade_topology(plants)

            @test "H001" in topology.headwaters
            @test "H003" in topology.headwaters
            @test "H002" in topology.terminals
            @test "H004" in topology.terminals

            @test topology.depths["H001"] == 0
            @test topology.depths["H002"] == 1
            @test topology.depths["H003"] == 0
            @test topology.depths["H004"] == 1
        end
    end

    @testset "build_cascade_topology - Unknown downstream reference" begin
        @testset "Downstream plant not in list - warning, not error" begin
            plants = HydroPlant[make_test_hydro(
                id = "H001",
                downstream_id = "H999",
                travel_time = 1.0,
            ),]

            # Should NOT throw, just warn
            # Capture warnings to verify they're emitted
            warnings = String[]
            with_logger(WarningCaptureLogger(warnings)) do
                topology = build_cascade_topology(plants)
                @test topology.depths["H001"] == 0
                @test "H001" in topology.headwaters
                @test "H001" in topology.terminals  # Treated as terminal since H999 doesn't exist
            end

            # Verify warning was logged
            @test any(w -> occursin("Unknown downstream reference", w), warnings)
        end

        @testset "Mixed valid and invalid downstream references" begin
            warnings = String[]
            topology = with_logger(WarningCaptureLogger(warnings)) do
                plants = HydroPlant[
                    make_test_hydro(id = "H001", downstream_id = "H002", travel_time = 1.0),
                    make_test_hydro(id = "H002", downstream_id = "H999", travel_time = 1.0),  # Unknown
                    make_test_hydro(id = "H003"),
                ]
                build_cascade_topology(plants)
            end

            @test topology.depths["H001"] == 0
            @test topology.depths["H002"] == 1
            @test topology.depths["H003"] == 0

            # H002 should be treated as terminal (H999 doesn't exist)
            @test "H002" in topology.terminals
            @test any(w -> occursin("H999", w), warnings)
        end
    end

    @testset "build_cascade_topology - Cycle detection" begin
        @testset "Self-loop (H001 -> H001)" begin
            plants = HydroPlant[make_test_hydro(
                id = "H001",
                downstream_id = "H001",
                travel_time = 1.0,
            ),]

            err = try
                build_cascade_topology(plants)
                nothing
            catch e
                e
            end

            @test err !== nothing
            @test err isa ArgumentError
            @test occursin("Circular cascade", string(err.msg))
            @test occursin("H001", string(err.msg))
        end

        @testset "Simple cycle (H001 -> H002 -> H001)" begin
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H002", travel_time = 1.0),
                make_test_hydro(id = "H002", downstream_id = "H001", travel_time = 1.0),
            ]

            err = try
                build_cascade_topology(plants)
                nothing
            catch e
                e
            end

            @test err !== nothing
            @test err isa ArgumentError
            @test occursin("Circular cascade", string(err.msg))
        end

        @testset "Longer cycle (H001 -> H002 -> H003 -> H001)" begin
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H002", travel_time = 1.0),
                make_test_hydro(id = "H002", downstream_id = "H003", travel_time = 1.0),
                make_test_hydro(id = "H003", downstream_id = "H001", travel_time = 1.0),
            ]

            err = try
                build_cascade_topology(plants)
                nothing
            catch e
                e
            end

            @test err !== nothing
            @test err isa ArgumentError
            @test occursin("Circular cascade", string(err.msg))
            @test occursin("H001", string(err.msg))
        end

        @testset "Cycle with non-cyclic branch" begin
            # H001 -> H002 -> H003 -> H002 (cycle)
            # H004 -> H003
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H002", travel_time = 1.0),
                make_test_hydro(id = "H002", downstream_id = "H003", travel_time = 1.0),
                make_test_hydro(id = "H003", downstream_id = "H002", travel_time = 1.0),  # Cycle!
                make_test_hydro(id = "H004", downstream_id = "H003", travel_time = 1.0),
            ]

            err = try
                build_cascade_topology(plants)
                nothing
            catch e
                e
            end

            @test err !== nothing
            @test err isa ArgumentError
            @test occursin("Circular cascade", string(err.msg))
        end
    end

    @testset "build_cascade_topology - Topological order" begin
        @testset "Simple linear cascade" begin
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H002", travel_time = 1.0),
                make_test_hydro(id = "H002", downstream_id = "H003", travel_time = 1.0),
                make_test_hydro(id = "H003"),
            ]
            topology = build_cascade_topology(plants)

            # Topological order should be upstream-first (H001 before H002 before H003)
            @test topology.topological_order == ["H001", "H002", "H003"]
        end

        @testset "Confluence - order should respect depth" begin
            plants = HydroPlant[
                make_test_hydro(id = "H001", downstream_id = "H003", travel_time = 1.0),
                make_test_hydro(id = "H002", downstream_id = "H003", travel_time = 1.0),
                make_test_hydro(id = "H003"),
            ]
            topology = build_cascade_topology(plants)

            # H003 should come after both H001 and H002
            idx_h003 = findfirst(==("H003"), topology.topological_order)
            idx_h001 = findfirst(==("H001"), topology.topological_order)
            idx_h002 = findfirst(==("H002"), topology.topological_order)

            @test idx_h003 > idx_h001
            @test idx_h003 > idx_h002
        end
    end

    @testset "Helper functions" begin
        @testset "find_headwaters" begin
            topology = CascadeTopology(;
                upstream_map = Dict("H002" => [("H001", 1.0)]),
                depths = Dict("H001" => 0, "H002" => 1),
                topological_order = ["H001", "H002"],
                headwaters = ["H001"],
                terminals = ["H002"],
            )

            headwaters = find_headwaters(topology)
            @test headwaters == ["H001"]
        end

        @testset "find_terminal_plants" begin
            topology = CascadeTopology(;
                upstream_map = Dict("H002" => [("H001", 1.0)]),
                depths = Dict("H001" => 0, "H002" => 1),
                topological_order = ["H001", "H002"],
                headwaters = ["H001"],
                terminals = ["H002"],
            )

            terminals = find_terminal_plants(topology)
            @test terminals == ["H002"]
        end

        @testset "get_upstream_plants" begin
            topology = CascadeTopology(;
                upstream_map = Dict(
                    "H002" => [("H001", 2.0)],
                    "H003" => [("H001", 1.0), ("H002", 1.5)],
                ),
                depths = Dict("H001" => 0, "H002" => 1, "H003" => 2),
                topological_order = ["H001", "H002", "H003"],
                headwaters = ["H001"],
                terminals = ["H003"],
            )

            upstream_h002 = get_upstream_plants(topology, "H002")
            @test length(upstream_h002) == 1
            @test upstream_h002[1] == ("H001", 2.0)

            upstream_h003 = get_upstream_plants(topology, "H003")
            @test length(upstream_h003) == 2
            @test ("H001", 1.0) in upstream_h003
            @test ("H002", 1.5) in upstream_h003

            # Headwater has no upstream
            upstream_h001 = get_upstream_plants(topology, "H001")
            @test isempty(upstream_h001)

            # Unknown plant
            upstream_h999 = get_upstream_plants(topology, "H999")
            @test isempty(upstream_h999)
        end
    end

    @testset "Mixed hydro plant types" begin
        @testset "ReservoirHydro and RunOfRiverHydro in same cascade" begin
            # Create a mix of plant types
            reservoir =
                make_test_hydro(id = "H001", downstream_id = "ROR001", travel_time = 2.0)

            run_of_river = RunOfRiverHydro(;
                id = "ROR001",
                name = "Run of River 1",
                bus_id = "B001",
                submarket_id = "SE",
                max_flow_m3_per_s = 500.0,
                min_flow_m3_per_s = 50.0,
                max_generation_mw = 100.0,
                min_generation_mw = 0.0,
                efficiency = 0.88,
                subsystem_code = 1,
                initial_volume_percent = 100.0,
                downstream_plant_id = nothing,
                water_travel_time_hours = nothing,
            )

            plants = HydroPlant[reservoir, run_of_river]
            topology = build_cascade_topology(plants)

            @test topology.depths["H001"] == 0
            @test topology.depths["ROR001"] == 1
            @test "H001" in topology.headwaters
            @test "ROR001" in topology.terminals
        end
    end

end
