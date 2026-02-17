"""
    Integration

Integration module for connecting OpenDESSEM with external optimization packages.
Provides adapters for converting OpenDESSEM entities to other data formats.

# Submodules
- `PowerModelsAdapter`: Convert OpenDESSEM entities to PowerModels.jl format
- `PWFParser`: Parse ANAREDE PWF power flow files

# Exports
- `convert_to_powermodel`: Convert complete system to PowerModels data dict
- `parse_pwf_file`: Parse a PWF power flow file
- `pwf_to_entities`: Convert PWF network to OpenDESSEM entities

# Example
```julia
using OpenDESSEM
using OpenDESSEM.Integration

# Parse PWF file
network = parse_pwf_file("case.pwf")

# Convert to OpenDESSEM entities
buses, lines = pwf_to_entities(network)

# Convert to PowerModels format
pm_data = convert_to_powermodel(;
    buses=buses,
    lines=lines,
    base_mva=100.0
)

# Solve DC-OPF with PowerModels
using PowerModels, HiGHS
result = solve_dc_opf(pm_data, HiGHS.Optimizer)
```
"""
module Integration

include("pwf_parser.jl")
include("powermodels_adapter.jl")

using ..Entities: Bus, ACLine

"""
    pwf_to_entities(network::PWFNetwork) -> Tuple{Vector{Bus}, Vector{ACLine}}

Convert a PWFNetwork to OpenDESSEM Bus and ACLine entities.

# Arguments
- `network::PWFNetwork`: Parsed PWF network data

# Returns
- `Tuple{Vector{Bus}, Vector{ACLine}}`: Bus and ACLine entities

# Example
```julia
network = parse_pwf_file("case.pwf")
buses, lines = pwf_to_entities(network)
```
"""
function pwf_to_entities(network::PWFNetwork)::Tuple{Vector{Bus},Vector{ACLine}}
    buses = Bus[]
    ac_lines = ACLine[]

    bus_lookup = Dict{Int,String}()

    for pwf_bus in network.buses
        bus = Bus(;
            id = "B_$(pwf_bus.number)",
            name = pwf_bus.name,
            voltage_kv = pwf_bus.base_kv * pwf_bus.voltage_pu,
            base_kv = pwf_bus.base_kv,
            dc_bus = false,
            is_reference = pwf_bus.type == 2,
            area_id = "A_$(pwf_bus.area)",
            zone_id = "Z_1",
        )

        push!(buses, bus)
        bus_lookup[pwf_bus.number] = bus.id
    end

    for pwf_branch in network.branches
        from_id = get(bus_lookup, pwf_branch.from_bus, nothing)
        to_id = get(bus_lookup, pwf_branch.to_bus, nothing)

        if from_id === nothing || to_id === nothing
            continue
        end

        base_kv = 230.0
        for pwf_bus in network.buses
            if pwf_bus.number == pwf_branch.from_bus
                base_kv = pwf_bus.base_kv
                break
            end
        end

        base_z = base_kv^2 / network.base_mva
        resistance_ohm = abs(pwf_branch.resistance_pu) * base_z
        reactance_ohm = abs(pwf_branch.reactance_pu) * base_z
        susceptance_siemen = abs(pwf_branch.susceptance_pu) / base_z

        if reactance_ohm < 0.0001
            reactance_ohm = 0.01 * base_z
        end

        line = ACLine(;
            id = "L_$(pwf_branch.from_bus)_$(pwf_branch.to_bus)_$(pwf_branch.circuit)",
            name = "Line $(pwf_branch.from_bus)-$(pwf_branch.to_bus) C$(pwf_branch.circuit)",
            from_bus_id = from_id,
            to_bus_id = to_id,
            resistance_ohm = resistance_ohm,
            reactance_ohm = reactance_ohm,
            susceptance_siemen = susceptance_siemen,
            max_flow_mw = pwf_branch.rate_a_mw,
            min_flow_mw = 0.0,
            length_km = 1.0,
        )

        push!(ac_lines, line)
    end

    return buses, ac_lines
end

"""
    solve_dc_opf_nodal_lmps(pm_data::Dict, solver) -> Dict

Solve DC-OPF using PowerModels and extract nodal LMPs.

# Arguments
- `pm_data::Dict`: PowerModels format network data
- `solver`: Optimizer factory (e.g., HiGHS.Optimizer)

# Returns
- `Dict` with keys:
  - "status": Termination status
  - "objective": Objective value
  - "generation": Dict of generator outputs (MW)
  - "flows": Dict of branch flows (MW)
  - "nodal_lmps": Dict mapping bus_id -> LMP value

# Note
Requires PowerModels.jl to be installed and imported before calling.

# Example
```julia
using PowerModels, HiGHS
result = solve_dc_opf_nodal_lmps(pm_data, HiGHS.Optimizer)
println("Bus 1 LMP: \\\$", result["nodal_lmps"]["1"])
```
"""
function solve_dc_opf_nodal_lmps(pm_data::Dict, solver)::Dict
    try
        result = PowerModels.solve_dc_opf(pm_data, solver)

        nodal_lmps = Dict{String,Float64}()
        if haskey(result, "solution") && haskey(result["solution"], "bus")
            for (bus_id, bus_data) in result["solution"]["bus"]
                lmp = get(bus_data, "lam_kcl_r", 0.0)
                nodal_lmps[bus_id] = lmp
            end
        end

        generation = Dict{String,Float64}()
        base_mva = get(pm_data, "baseMVA", 100.0)
        if haskey(result, "solution") && haskey(result["solution"], "gen")
            for (gen_id, gen_data) in result["solution"]["gen"]
                pg = get(gen_data, "pg", 0.0)
                generation[gen_id] = pg * base_mva
            end
        end

        flows = Dict{String,Float64}()
        if haskey(result, "solution") && haskey(result["solution"], "branch")
            for (br_id, br_data) in result["solution"]["branch"]
                pf = get(br_data, "pf", 0.0)
                flows[br_id] = pf * base_mva
            end
        end

        return Dict{String,Any}(
            "status" => string(result["termination_status"]),
            "objective" => result["objective"],
            "generation" => generation,
            "flows" => flows,
            "nodal_lmps" => nodal_lmps,
            "raw_result" => result,
        )
    catch e
        @warn "PowerModels integration error: $e"
        return Dict{String,Any}(
            "status" => "error",
            "error" => string(e),
            "objective" => 0.0,
            "generation" => Dict{String,Float64}(),
            "flows" => Dict{String,Float64}(),
            "nodal_lmps" => Dict{String,Float64}(),
        )
    end
end

export parse_pwf_file, pwf_to_entities, PWFNetwork, PWFBus, PWFBranch
export solve_dc_opf_nodal_lmps

end # module
