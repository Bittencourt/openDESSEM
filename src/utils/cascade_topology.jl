"""
    CascadeTopologyUtils module

Cascade topology utilities for OpenDESSEM.

Builds DAG topology from hydro plant downstream_plant_id references, detects circular
dependencies, and computes plant depths for ordered constraint building.

# Main Components
- `CascadeTopology`: Struct holding topology information
- `build_cascade_topology`: Main function to build topology from hydro plants
- Helper functions: `find_headwaters`, `find_terminal_plants`, `get_upstream_plants`

# Examples
```julia
# Build topology from hydro plants
topology = build_cascade_topology(system.hydro_plants)

# Get plants in upstream-first order for constraint building
for plant_id in topology.topological_order
    # Process plants from headwaters to terminals
end

# Check for upstream plants
upstream = get_upstream_plants(topology, "H003")
for (upstream_id, delay) in upstream
    # Water from upstream arrives after delay hours
end
```
"""
module CascadeTopologyUtils

# Import HydroPlant type from Entities module
using ..Entities: HydroPlant

"""
    CascadeTopology

Holds the cascade topology information for a set of hydroelectric plants.

# Fields
- `upstream_map::Dict{String,Vector{Tuple{String,Float64}}}`: Maps downstream_id => [(upstream_id, delay_hours)]
- `depths::Dict{String,Int}`: Maps plant_id => depth from headwater (headwaters = 0)
- `topological_order::Vector{String}`: Plants ordered upstream-first (BFS from headwaters)
- `headwaters::Vector{String}`: Plants with no upstream (depth = 0)
- `terminals::Vector{String}`: Plants with no downstream

# Notes
- Depths are computed via BFS from headwaters
- Topological order ensures upstream plants appear before downstream plants
- Terminals may also be plants whose downstream reference is not in the system

# Examples
```julia
topology = build_cascade_topology(hydro_plants)
# topology.depths["H001"] == 0  # Headwater
# topology.depths["H002"] == 1  # One step from headwater
```
"""
Base.@kwdef struct CascadeTopology
    upstream_map::Dict{String,Vector{Tuple{String,Float64}}}
    depths::Dict{String,Int}
    topological_order::Vector{String}
    headwaters::Vector{String}
    terminals::Vector{String}
end

"""
    build_cascade_topology(hydro_plants::Vector{<:HydroPlant}) -> CascadeTopology

Build cascade topology from a vector of hydro plants.

Analyzes downstream_plant_id references to build a DAG topology, detect circular
dependencies, and compute plant depths for ordered constraint building.

# Arguments
- `hydro_plants::Vector{<:HydroPlant}`: Vector of hydro plants (any subtype)

# Returns
- `CascadeTopology`: Struct containing topology information

# Throws
- `ArgumentError`: If circular cascade dependencies are detected (with full cycle path)

# Warnings
- Logs warning for unknown downstream references (treats plant as terminal)

# Algorithm
1. Build plant_dict: id => plant for lookup
2. Initialize upstream_map with empty vectors for all plants
3. For each plant with downstream_plant_id:
   - If downstream exists: add (plant.id, travel_time) to upstream_map[downstream]
   - If downstream NOT exists: log warning, treat as terminal
4. Detect cycles via DFS with recursion stack
5. Compute depths via BFS from headwaters
6. Build topological_order (BFS traversal order)

# Examples
```julia
# Simple linear cascade: H001 -> H002 -> H003
plants = [
    ReservoirHydro(; id = "H001", downstream_plant_id = "H002", ...),
    ReservoirHydro(; id = "H002", downstream_plant_id = "H003", ...),
    ReservoirHydro(; id = "H003", ...),
]
topology = build_cascade_topology(plants)

# topology.depths == Dict("H001" => 0, "H002" => 1, "H003" => 2)
# topology.headwaters == ["H001"]
# topology.terminals == ["H003"]
```

# See Also
- [`find_headwaters`](@ref)
- [`find_terminal_plants`](@ref)
- [`get_upstream_plants`](@ref)
"""
function build_cascade_topology(hydro_plants::Vector{<:HydroPlant})::CascadeTopology
    # Build plant lookup dict
    plant_dict = Dict{String,HydroPlant}()
    for plant in hydro_plants
        plant_dict[plant.id] = plant
    end

    # Initialize upstream_map with empty vectors for all plants
    upstream_map = Dict{String,Vector{Tuple{String,Float64}}}()
    for plant_id in keys(plant_dict)
        upstream_map[plant_id] = Tuple{String,Float64}[]
    end

    # Build upstream_map from downstream references
    for plant in hydro_plants
        if plant.downstream_plant_id !== nothing
            downstream_id = plant.downstream_plant_id
            delay_hours = plant.water_travel_time_hours

            if haskey(plant_dict, downstream_id)
                # Valid downstream reference
                push!(upstream_map[downstream_id], (plant.id, delay_hours))
            else
                # Unknown downstream reference - warn but don't throw
                @warn """
                Unknown downstream reference in cascade topology:
                  Plant '$(plant.id)' references downstream '$(downstream_id)'
                  which is not in the system. Treating '$(plant.id)' as terminal.
                """ maxlog = 10
            end
        end
    end

    # Detect cycles via DFS with recursion stack
    visited = Set{String}()
    rec_stack = Set{String}()
    path = String[]

    function detect_cycle!(plant_id::String)::Union{String,Nothing}
        push!(visited, plant_id)
        push!(rec_stack, plant_id)
        push!(path, plant_id)

        # Get downstream of this plant
        plant = plant_dict[plant_id]
        if plant.downstream_plant_id !== nothing &&
           haskey(plant_dict, plant.downstream_plant_id)
            downstream_id = plant.downstream_plant_id

            if downstream_id in rec_stack
                # Found cycle - construct error message with path
                cycle_start_idx = findfirst(==(downstream_id), path)
                cycle_path = path[cycle_start_idx:end]
                push!(cycle_path, downstream_id)  # Close the cycle
                return join(cycle_path, " → ")
            end

            if !(downstream_id in visited)
                result = detect_cycle!(downstream_id)
                if result !== nothing
                    return result
                end
            end
        end

        pop!(path)
        pop!(rec_stack)
        return nothing
    end

    # Check all plants for cycles
    for plant_id in keys(plant_dict)
        if !(plant_id in visited)
            cycle_path = detect_cycle!(plant_id)
            if cycle_path !== nothing
                throw(ArgumentError("Circular cascade detected: $cycle_path"))
            end
        end
    end

    # Find headwaters (plants with no upstream)
    headwaters = String[]
    for plant_id in keys(plant_dict)
        if isempty(upstream_map[plant_id])
            push!(headwaters, plant_id)
        end
    end

    # Compute depths via BFS from headwaters
    depths = Dict{String,Int}()
    topological_order = String[]
    queue = collect(headwaters)

    for hw in headwaters
        depths[hw] = 0
    end

    while !isempty(queue)
        current_id = popfirst!(queue)
        push!(topological_order, current_id)

        current_depth = depths[current_id]

        # Find all plants that have current as their downstream
        current_plant = plant_dict[current_id]
        if current_plant.downstream_plant_id !== nothing &&
           haskey(plant_dict, current_plant.downstream_plant_id)
            downstream_id = current_plant.downstream_plant_id

            # Update downstream depth (take max in case of multiple paths)
            new_depth = current_depth + 1
            if !haskey(depths, downstream_id)
                depths[downstream_id] = new_depth
                push!(queue, downstream_id)
            else
                # Already visited - depth should be at least current_depth + 1
                # (BFS ensures this, but let's be safe)
                depths[downstream_id] = max(depths[downstream_id], new_depth)
            end
        end
    end

    # Handle disconnected plants (shouldn't happen with proper BFS, but be safe)
    for plant_id in keys(plant_dict)
        if !haskey(depths, plant_id)
            depths[plant_id] = 0
            push!(headwaters, plant_id)
            push!(topological_order, plant_id)
        end
    end

    # Find terminals (plants with no downstream, or downstream not in system)
    terminals = String[]
    for plant in hydro_plants
        if plant.downstream_plant_id === nothing ||
           !haskey(plant_dict, plant.downstream_plant_id)
            push!(terminals, plant.id)
        end
    end

    return CascadeTopology(;
        upstream_map = upstream_map,
        depths = depths,
        topological_order = topological_order,
        headwaters = headwaters,
        terminals = terminals,
    )
end

"""
    find_headwaters(topology::CascadeTopology) -> Vector{String}

Find all headwater plants (plants with no upstream).

Headwaters are the source plants in the cascade, typically located
at the highest points in the river system.

# Arguments
- `topology::CascadeTopology`: The cascade topology

# Returns
- `Vector{String}`: IDs of headwater plants

# Examples
```julia
headwaters = find_headwaters(topology)
# Process headwaters first in constraint building
for hw_id in headwaters
    # Headwaters have no upstream inflow delays
end
```
"""
function find_headwaters(topology::CascadeTopology)::Vector{String}
    return topology.headwaters
end

"""
    find_terminal_plants(topology::CascadeTopology) -> Vector{String}

Find all terminal plants (plants with no downstream).

Terminals are the end points of the cascade, typically located
at the lowest points before the ocean or another system.

# Arguments
- `topology::CascadeTopology`: The cascade topology

# Returns
- `Vector{String}`: IDs of terminal plants

# Examples
```julia
terminals = find_terminal_plants(topology)
# Terminal plants' outflow doesn't feed another plant in the system
for term_id in terminals
    # No downstream plants affected by this plant's release
end
```
"""
function find_terminal_plants(topology::CascadeTopology)::Vector{String}
    return topology.terminals
end

"""
    get_upstream_plants(topology::CascadeTopology, plant_id::String) -> Vector{Tuple{String,Float64}}

Get all upstream plants for a given plant.

Returns a vector of (upstream_id, delay_hours) tuples for all plants
that flow into this plant.

# Arguments
- `topology::CascadeTopology`: The cascade topology
- `plant_id::String`: The plant ID to query

# Returns
- `Vector{Tuple{String,Float64}}`: Vector of (upstream_id, delay_hours) tuples
  - Empty vector if plant has no upstream (headwater) or plant not found

# Examples
```julia
upstream = get_upstream_plants(topology, "H003")
for (upstream_id, delay) in upstream
    # Water from upstream_id arrives after delay hours
    println("Plant \$upstream_id -> H003 (delay: \$delay hours)")
end
```
"""
function get_upstream_plants(
    topology::CascadeTopology,
    plant_id::String,
)::Vector{Tuple{String,Float64}}
    return get(topology.upstream_map, plant_id, Tuple{String,Float64}[])
end

# Export main types and functions
export CascadeTopology, build_cascade_topology
export find_headwaters, find_terminal_plants, get_upstream_plants

end # module
