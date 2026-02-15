"""
    Test PowerModels.jl API and compatibility with OpenDESSEM

This script explores PowerModels.jl to evaluate:
1. Data structure format
2. Model instantiation
3. Constraint building
4. Solution extraction
"""

using PowerModels
using JuMP

println("="^60)
println("PowerModels.jl API Exploration")
println("="^60)

# Test 1: Check available power model types
println("\n### Available Power Model Types ###")
model_types = ["DCPPowerModel", "ACPPowerModel", "DCPLLPowerModel", "BFAPowerModel"]

for mt in model_types
    try
        T = getfield(PowerModels, Symbol(mt))
        println("  ✓ $mt")
    catch
        println("  ✗ $mt (not found)")
    end
end

# Test 2: Check for key functions
println("\n### Key PowerModels Functions ###")
key_functions = [
    "instantiate_model",
    "solve_opf",
    "solve_mc_opf",
    "build_mc_opf",
    "parse_file",
    "make_basic_network",
]

for func_name in key_functions
    if isdefined(PowerModels, Symbol(func_name))
        println("  ✓ $func_name")
    else
        println("  ✗ $func_name (not found)")
    end
end

# Test 3: Create a simple test network
println("\n### Creating Test Network ###")

# Simple 3-bus system based on Matpower format
test_data = Dict{String,Any}(
    "name" => "test",
    "dm" => Dict{String,Any}("bus" => 3, "branch" => 2, "gen" => 2),
    "bus" => [
        Dict(
            "bus_i" => 1,
            "bus_type" => 3,
            "vmax" => 1.1,
            "vmin" => 0.9,
            "area" => 1,
            "vm" => 1.0,
            "va" => 0.0,
            "base_kv" => 230.0,
        ),
        Dict(
            "bus_i" => 2,
            "bus_type" => 2,
            "vmax" => 1.1,
            "vmin" => 0.9,
            "area" => 1,
            "vm" => 1.0,
            "va" => 0.0,
            "base_kv" => 230.0,
        ),
        Dict(
            "bus_i" => 3,
            "bus_type" => 1,
            "vmax" => 1.1,
            "vmin" => 0.9,
            "area" => 1,
            "vm" => 1.0,
            "va" => 0.0,
            "base_kv" => 230.0,
        ),
    ],
    "branch" => [
        Dict(
            "fbus" => 1,
            "tbus" => 2,
            "br_r" => 0.00281,
            "br_x" => 0.0281,
            "rate_a" => 400.0,
            "rate_b" => 400.0,
            "rate_c" => 400.0,
            "tap" => 1.0,
            "shift" => 0.0,
            "br_status" => 1,
        ),
        Dict(
            "fbus" => 1,
            "tbus" => 3,
            "br_r" => 0.00304,
            "br_x" => 0.0304,
            "rate_a" => 400.0,
            "rate_b" => 400.0,
            "rate_c" => 400.0,
            "tap" => 1.0,
            "shift" => 0.0,
            "br_status" => 1,
        ),
    ],
    "gen" => [
        Dict(
            "gen_bus" => 1,
            "pg" => 150.0,
            "qg" => 0.0,
            "qmax" => 100.0,
            "qmin" => -100.0,
            "vg" => 1.0,
            "mbase" => 100.0,
            "gen_status" => 1,
            "pmax" => 200.0,
            "pmin" => 0.0,
        ),
        Dict(
            "gen_bus" => 2,
            "pg" => 50.0,
            "qg" => 0.0,
            "qmax" => 80.0,
            "qmin" => -80.0,
            "vg" => 1.0,
            "mbase" => 100.0,
            "gen_status" => 1,
            "pmax" => 150.0,
            "pmin" => 0.0,
        ),
    ],
    "dcline" => [],
    "load" => [
        Dict("load_bus" => 2, "pd" => 100.0, "qd" => 0.0, "status" => 1),
        Dict("load_bus" => 3, "pd" => 80.0, "qd" => 0.0, "status" => 1),
    ],
    "shunt" => [],
    "storage" => [],
    "switch" => [],
)

println("  Created test network with:")
println("    - $(length(test_data["bus"])) buses")
println("    - $(length(test_data["branch"])) branches")
println("    - $(length(test_data["gen"])) generators")
println("    - $(length(test_data["load"])) loads")

# Test 4: Try to instantiate DC-OPF model
println("\n### Testing DC-OPF Model Instantiation ###")

try
    using HiGHS

    # Correct PowerModels API
    pm = instantiate_model(
        test_data,
        DCPPowerModel,
        build_dc_opf,
        jump_model = Model(HiGHS.Optimizer),
    )

    println("  ✓ DC-OPF model instantiated successfully")
    println("    Model type: ", typeof(pm.model))

    # Check what variables were created
    println("\n  Variables created:")
    for (name, var) in pm.model.obj_dict
        println("    - $name: $(typeof(var))")
        if isa(var, JuMP.VariableRef)
            println("        (single variable)")
        elseif isa(var, DenseAxisArray) || isa(var, JuMP.Containers.DenseAxisArray)
            println("        (array with dimensions: $(size(var)))")
        end
    end

    # Solve the model
    println("\n  Solving DC-OPF...")
    result = solve_model(pm; optimizer = HiGHS.Optimizer)
    println("  ✓ Model solved")
    println("    Status: ", result["termination_status"])

    # Extract solution
    if haskey(result, "solution")
        println("  Solution extracted:")
        sol = result["solution"]
        if haskey(sol, "bus")
            println("    Bus voltages:")
            for (bus_id, bus_data) in sol["bus"]
                println("      Bus $bus_id: vm=$(get(bus_data, "vm", "N/A"))")
            end
        end
        if haskey(sol, "branch")
            println("    Branch flows:")
            for (i, branch_data) in enumerate(sol["branch"])
                println("      Branch $i: pf=$(get(branch_data, "pf", "N/A"))")
            end
        end
        if haskey(sol, "gen")
            println("    Generator outputs:")
            for (i, gen_data) in enumerate(sol["gen"])
                println("      Gen $i: pg=$(get(gen_data, "pg", "N/A"))")
            end
        end
    end

catch e
    println("  ✗ DC-OPF instantiation failed:")
    println("    Error: $e")
    println("    This may indicate compatibility issues")
end

println("\n" * "="^60)
println("PowerModels API Exploration Complete")
println("="^60)
