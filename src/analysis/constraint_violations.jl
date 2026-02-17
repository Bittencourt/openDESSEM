"""
    Constraint Violation Reporting

Detect, classify, and report constraint violations in solved optimization models.

Uses JuMP's `primal_feasibility_report()` to identify violations with magnitudes,
then classifies them by constraint type based on naming conventions.

# Usage
```julia
using OpenDESSEM.Analysis

report = check_constraint_violations(model; atol=1e-6)
if !isempty(report.violations)
    println("Found ", length(report.violations), " violations")
    write_violation_report(report, "violations.txt")
end
```
"""

using JuMP
using Dates

"""
    ConstraintViolation

Represents a single constraint violation detected in a solved model.

# Fields
- `constraint_name::String`: Name of the violated constraint (from `JuMP.name(con_ref)`)
- `violation_magnitude::Float64`: How far from feasibility (absolute value)
- `constraint_type::String`: Classified type: "thermal", "hydro", "balance", "network", "ramp", "unknown"

# Example
```julia
cv = ConstraintViolation(
    constraint_name = "thermal_max_gen[T001,3]",
    violation_magnitude = 0.5,
    constraint_type = "thermal"
)
```
"""
Base.@kwdef struct ConstraintViolation
    constraint_name::String
    violation_magnitude::Float64
    constraint_type::String
end

"""
    ViolationReport

Complete constraint violation report for a solved model.

# Fields
- `model_name::String`: Identifier for the model
- `timestamp::DateTime`: When the report was generated
- `tolerance::Float64`: The atol used for violation detection
- `violations::Vector{ConstraintViolation}`: List of violations (sorted by magnitude descending)
- `total_violations::Int`: Total number of violations found
- `max_violation::Float64`: Maximum violation magnitude (0.0 if no violations)
- `violations_by_type::Dict{String, Int}`: Count of violations per constraint type

# Example
```julia
report = check_constraint_violations(model; atol=1e-6, model_name="my_model")
println("Total violations: ", report.total_violations)
println("Max violation: ", report.max_violation)
for (vtype, count) in report.violations_by_type
    println("  ", vtype, ": ", count)
end
```
"""
Base.@kwdef struct ViolationReport
    model_name::String
    timestamp::DateTime
    tolerance::Float64
    violations::Vector{ConstraintViolation}
    total_violations::Int
    max_violation::Float64
    violations_by_type::Dict{String,Int}
end

"""
    Base.isempty(report::ViolationReport)

Returns `true` if the report contains no violations.
"""
Base.isempty(report::ViolationReport) = report.total_violations == 0

"""
    _classify_constraint(name::String) -> String

Classify a constraint by type based on its name.

Returns one of: "thermal", "hydro", "balance", "network", "ramp", "unknown".

Uses case-insensitive matching on constraint name patterns.
"""
function _classify_constraint(name::String)::String
    lname = lowercase(name)

    # Thermal constraints
    if contains(lname, "thermal") || startswith(lname, "thermal_")
        return "thermal"
    end

    # Hydro constraints (including water balance and storage)
    if contains(lname, "hydro") ||
       contains(lname, "water_balance") ||
       contains(lname, "storage")
        return "hydro"
    end

    # Balance constraints (energy balance, submarket balance)
    if contains(lname, "balance") || contains(lname, "submarket")
        return "balance"
    end

    # Network constraints (power flow, transmission)
    if contains(lname, "network") || contains(lname, "flow") || contains(lname, "line")
        return "network"
    end

    # Ramp constraints
    if contains(lname, "ramp")
        return "ramp"
    end

    return "unknown"
end

"""
    check_constraint_violations(model::Model; atol::Float64=1e-6, model_name::String="") -> ViolationReport

Check a solved JuMP model for constraint violations.

Uses `JuMP.primal_feasibility_report()` to detect violations exceeding the
specified tolerance. Each violation is classified by constraint type based on
its name.

# Arguments
- `model::Model`: A solved JuMP model
- `atol::Float64`: Absolute tolerance for violation detection (default: 1e-6)
- `model_name::String`: Identifier for the model (default: "")

# Returns
- `ViolationReport`: Report containing all detected violations, sorted by magnitude

# Example
```julia
using JuMP, HiGHS

model = Model(HiGHS.Optimizer)
# ... build and solve model ...
optimize!(model)

report = check_constraint_violations(model; atol=1e-6, model_name="test")
if !isempty(report)
    println("Found \$(report.total_violations) violations")
    println("Max violation: \$(report.max_violation)")
end
```
"""
function check_constraint_violations(
    model::Model;
    atol::Float64 = 1e-6,
    model_name::String = "",
)::ViolationReport
    # Use JuMP's built-in feasibility checker
    feasibility_report = JuMP.primal_feasibility_report(model; atol = atol)

    # Process violations
    violations = ConstraintViolation[]

    for (con_ref, violation_distance) in feasibility_report
        # Get constraint name (may be empty string for unnamed constraints)
        con_name = try
            JuMP.name(con_ref)
        catch
            ""
        end

        if isempty(con_name)
            con_name = string(con_ref)
        end

        # Classify the constraint type
        con_type = _classify_constraint(con_name)

        # Create violation record
        push!(
            violations,
            ConstraintViolation(;
                constraint_name = con_name,
                violation_magnitude = abs(violation_distance),
                constraint_type = con_type,
            ),
        )
    end

    # Sort by magnitude descending (worst violations first)
    sort!(violations; by = v -> v.violation_magnitude, rev = true)

    # Compute summary statistics
    total = length(violations)
    max_mag = total > 0 ? violations[1].violation_magnitude : 0.0

    # Count violations by type
    by_type = Dict{String,Int}()
    for v in violations
        by_type[v.constraint_type] = get(by_type, v.constraint_type, 0) + 1
    end

    return ViolationReport(;
        model_name = model_name,
        timestamp = now(),
        tolerance = atol,
        violations = violations,
        total_violations = total,
        max_violation = max_mag,
        violations_by_type = by_type,
    )
end

"""
    write_violation_report(report::ViolationReport, filepath::String) -> String

Write a human-readable constraint violation report to a text file.

Creates the parent directory if it does not exist.

# Arguments
- `report::ViolationReport`: The violation report to write
- `filepath::String`: Output file path

# Returns
- `String`: The filepath written to

# Example
```julia
report = check_constraint_violations(model; model_name="my_model")
write_violation_report(report, "output/violations.txt")
```
"""
function write_violation_report(report::ViolationReport, filepath::String)::String
    # Create parent directory if needed
    dir = dirname(filepath)
    if !isempty(dir)
        mkpath(dir)
    end

    open(filepath, "w") do io
        println(io, "Constraint Violation Report")
        println(io, "===========================")
        println(io, "Model: ", report.model_name)
        println(io, "Timestamp: ", report.timestamp)
        println(io, "Tolerance: ", report.tolerance)
        println(io)
        println(io, "Summary")
        println(io, "-------")
        println(io, "Total violations: ", report.total_violations)
        println(io, "Maximum violation: ", report.max_violation)
        println(io)

        if !isempty(report.violations_by_type)
            println(io, "Violations by Type:")
            for (vtype, count) in sort(collect(report.violations_by_type))
                println(io, "  ", vtype, ": ", count)
            end
            println(io)
        end

        println(io, "Detailed Violations (sorted by magnitude)")
        println(io, "-----------------------------------------")

        if isempty(report.violations)
            println(io, "No violations found.")
        else
            for (i, v) in enumerate(report.violations)
                println(
                    io,
                    i,
                    ". [",
                    v.constraint_type,
                    "] ",
                    v.constraint_name,
                    ": ",
                    v.violation_magnitude,
                )
            end
        end
    end

    return filepath
end
