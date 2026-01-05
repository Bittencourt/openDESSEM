using PowerModels
using HiGHS

println("Testing PowerModels.jl basic solve_opf...")

# Use built-in test data
result = solve_opf(
    "C:\\Users\\pedro\\.julia\\packages\\PowerModels\\VCmhH\\test\\data\\matpower\\case3.m",
    DCPPowerModel,
    HiGHS.Optimizer,
)

println("Status: ", result["termination_status"])
println("Objective: ", result["objective_value"])

if haskey(result, "solution")
    println("\nGenerator outputs:")
    for (i, gen) in enumerate(result["solution"]["gen"])
        println("  Gen $i: pg=$(gen["pg"])")
    end
end
