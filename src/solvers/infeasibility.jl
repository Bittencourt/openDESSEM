"""
    Infeasibility Diagnostics for OpenDESSEM

Provides on-demand IIS (Irreducible Inconsistent Subsystem) computation for 
diagnosing infeasible optimization models.

# Key Functions
- `compute_iis!()`: Compute IIS for an infeasible model
- `write_iis_report()`: Generate human-readable IIS report file

# When to Use
Call `compute_iis!(model)` when:
1. `solve_model!()` returns with `solve_status == INFEASIBLE`
2. You need to understand which constraints conflict

# Solver Support
- **Gurobi**: Full IIS support (recommended)
- **HiGHS**: Limited support (may not find minimal IIS)
- **CPLEX**: Full IIS support
- **GLPK**: No IIS support

# Example
```julia
result = solve_model!(model, system; solver=HIGHS)
if result.solve_status == INFEASIBLE
    # Compute IIS to diagnose infeasibility
    iis_result = compute_iis!(model)
    
    if iis_result.status == MOI.COMPUTE_CONFLICT_SUCCESS
        println("Found \$(length(iis_result.conflicts)) conflicting constraints:")
        for conflict in iis_result.conflicts
            println("  - \$(conflict.constraint_name)")
        end
        
        # Write detailed report
        report_path = write_iis_report(iis_result)
        println("Report saved to: \$report_path")
    else
        @warn "IIS computation not supported by solver"
    end
end
```
"""

"""
    compute_iis!(model::JuMP.Model; auto_report::Bool=true)::IISResult

Compute the Irreducible Inconsistent Subsystem (IIS) for an infeasible model.

The IIS is a minimal set of constraints and variable bounds that is infeasible.
Removing any single element from the IIS makes the remaining set feasible.

# Arguments
- `model::JuMP.Model`: The JuMP model (should be infeasible)
- `auto_report::Bool=true`: Automatically generate report file (default: true)

# Returns
- `IISResult`: Contains all conflicting constraints/bounds and computation metadata

# Notes
- **Call this AFTER detecting infeasibility**, not before
- If model is not infeasible, returns with warning (no error thrown)
- Not all solvers support IIS - check `result.status` for success

# Solver Support
| Solver | Support Level |
|--------|---------------|
| Gurobi | Full (recommended) |
| CPLEX | Full |
| HiGHS | Limited |
| GLPK | None |

# Example
```julia
result = solve_model!(model, system)
if result.solve_status == INFEASIBLE
    iis = compute_iis!(model)
    if iis.status == MOI.COMPUTE_CONFLICT_SUCCESS
        println("IIS has \$(length(iis.conflicts)) constraints")
    end
end
```

# See Also
- [`write_iis_report`](@ref): Generate detailed report file
- [`IISResult`](@ref): Result structure
- [`IISConflict`](@ref): Individual conflict representation
"""
function compute_iis!(model::JuMP.Model; auto_report::Bool = true)::IISResult
    start_time = time()
    
    # Get solver name from model
    solver_name = _get_solver_name(model)
    
    # Check if model is in an infeasible or unbounded state
    term_status = termination_status(model)
    
    if term_status ∉ [MOI.INFEASIBLE, MOI.LOCALLY_INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED, MOI.UNBOUNDED, MOI.DUAL_INFEASIBLE]
        @warn "compute_iis!() called on model that may not be infeasible. " *
              "Termination status: $term_status. " *
              "For best results, call compute_iis!() after detecting INFEASIBLE status."
    end
    
    # Try to compute conflict using JuMP's conflict API
    conflicts = IISConflict[]
    conflict_status = MOI.COMPUTE_CONFLICT_NOT_SUPPORTED
    
    try
        # Use JuMP's compute_conflict! function
        conflict_status = compute_conflict!(model)
        
        if conflict_status == MOI.COMPUTE_CONFLICT_SUCCESS
            # Extract all constraints that are in the conflict set
            conflicts = _extract_conflicts(model)
        end
    catch e
        if e isa MethodError || (isa(e, ErrorException) && occursin("conflict", lowercase(e.msg)))
            @warn "IIS computation not supported by $solver_name. " *
                  "Consider using Gurobi or CPLEX for full IIS support."
            conflict_status = MOI.COMPUTE_CONFLICT_NOT_SUPPORTED
        else
            rethrow(e)
        end
    end
    
    computation_time = time() - start_time
    
    # Build result
    result = IISResult(
        status = conflict_status,
        conflicts = conflicts,
        computation_time = computation_time,
        solver_used = solver_name,
        report_file = nothing
    )
    
    # Auto-generate report if requested and conflicts were found
    if auto_report && conflict_status == MOI.COMPUTE_CONFLICT_SUCCESS && !isempty(conflicts)
        report_path = write_iis_report(result)
        result = IISResult(
            status = result.status,
            conflicts = result.conflicts,
            computation_time = result.computation_time,
            solver_used = result.solver_used,
            report_file = report_path
        )
    end
    
    return result
end

"""
    _get_solver_name(model::JuMP.Model)::String

Extract the solver name from a JuMP model.

# Arguments
- `model::JuMP.Model`: The JuMP model

# Returns
- `String`: Name of the solver (e.g., "HiGHS", "Gurobi", "CPLEX", "GLPK", "unknown")
"""
function _get_solver_name(model::JuMP.Model)::String
    try
        # Try to get mode from backend
        backend = backend = JuMP.backend(model)
        optimizer = MOI.get(backend, MOI.SolverName())
        return optimizer !== nothing ? String(optimizer) : "unknown"
    catch
        return "unknown"
    end
end

"""
    _extract_conflicts(model::JuMP.Model)::Vector{IISConflict}

Extract all constraints that participate in the conflict set.

# Arguments
- `model::JuMP.Model`: The JuMP model with computed conflict

# Returns
- `Vector{IISConflict}`: List of conflicting constraints/bounds
"""
function _extract_conflicts(model::JuMP.Model)::Vector{IISConflict}
    conflicts = IISConflict[]
    
    # Get all constraints in the model
    constraint_types = list_of_constraint_types(model)
    
    for (F, S) in constraint_types
        try
            for constraint_ref in all_constraints(model, F, S)
                # Check if this constraint is in the conflict
                conflict_status = MOI.get(constraint_ref, MOI.ConstraintConflictStatus())
                
                if conflict_status == MOI.IN_CONFLICT
                    conflict = _build_conflict_from_constraint(constraint_ref, F, S)
                    if conflict !== nothing
                        push!(conflicts, conflict)
                    end
                end
            end
        catch e
            # Skip constraint types that don't support conflict status
            if !(e isa MethodError)
                @debug "Could not check conflict status for constraint type ($F, $S)" exception = e
            end
        end
    end
    
    # Also check variable bounds
    try
        for var in all_variables(model)
            var_conflict = _check_variable_bound_conflict(model, var)
            if var_conflict !== nothing
                push!(conflicts, var_conflict)
            end
        end
    catch e
        @debug "Could not check variable bound conflicts" exception = e
    end
    
    return conflicts
end

"""
    _build_conflict_from_constraint(constraint_ref, F, S)::Union{IISConflict, Nothing}

Build an IISConflict from a constraint reference.

# Arguments
- `constraint_ref`: Reference to the constraint
- `F`: Function type of the constraint
- `S`: Set type of the constraint

# Returns
- `IISConflict` or `nothing` if cannot build
"""
function _build_conflict_from_constraint(constraint_ref, F, S)::Union{IISConflict,Nothing}
    try
        # Get constraint name
        name = JuMP.name(constraint_ref)
        if isempty(name)
            name = "unnamed_$(F)_$(S)"
        end
        
        # Get constraint expression as string
        expr_str = _constraint_to_string(constraint_ref)
        
        # Try to extract bounds based on constraint set type
        lower_bound = nothing
        upper_bound = nothing
        
        set = JuMP.constraint_object(constraint_ref).set
        
        if hasfield(typeof(set), :lower)
            lower_bound = getfield(set, :lower)
        end
        if hasfield(typeof(set), :upper)
            upper_bound = getfield(set, :upper)
        end
        if hasfield(typeof(set), :value)
            # For equality constraints
            val = getfield(set, :value)
            lower_bound = val
            upper_bound = val
        end
        
        return IISConflict(
            constraint_ref = constraint_ref,
            constraint_name = name,
            expression = expr_str,
            lower_bound = lower_bound isa Number ? Float64(lower_bound) : nothing,
            upper_bound = upper_bound isa Number ? Float64(upper_bound) : nothing
        )
    catch e
        @debug "Could not build conflict from constraint" exception = e
        return nothing
    end
end

"""
    _constraint_to_string(constraint_ref)::String

Convert a constraint to a human-readable string representation.

# Arguments
- `constraint_ref`: Reference to the constraint

# Returns
- `String`: Human-readable representation
"""
function _constraint_to_string(constraint_ref)::String
    try
        # Try to get the constraint expression
        con_obj = JuMP.constraint_object(constraint_ref)
        func = con_obj.func
        set = con_obj.set
        
        # Build expression string
        func_str = _jump_function_to_string(func)
        
        # Build set string
        if typeof(set) <: MOI.LessThan
            return "$(func_str) <= $(set.upper)"
        elseif typeof(set) <: MOI.GreaterThan
            return "$(func_str) >= $(set.lower)"
        elseif typeof(set) <: MOI.EqualTo
            return "$(func_str) == $(set.value)"
        elseif typeof(set) <: MOI.Interval
            return "$(set.lower) <= $(func_str) <= $(set.upper)"
        else
            return "$(func_str) in $(typeof(set).name.wrapper)"
        end
    catch e
        @debug "Could not convert constraint to string" exception = e
        return "<unable to represent>"
    end
end

"""
    _jump_function_to_string(func)::String

Convert a JuMP function to a string representation.

# Arguments
- `func`: JuMP function (AffExpr, QuadExpr, VariableRef, etc.)

# Returns
- `String`: String representation
"""
function _jump_function_to_string(func)::String
    try
        if func isa JuMP.VariableRef
            return JuMP.name(func)
        elseif func isa JuMP.AffExpr
            # Build string for affine expression
            terms = String[]
            for (vars, coef) in func.terms
                var_names = [JuMP.name(v) for v in vars]
                if coef == 1.0
                    push!(terms, join(var_names, " * "))
                elseif coef == -1.0
                    push!(terms, "-" * join(var_names, " * "))
                else
                    push!(terms, "$(coef) * " * join(var_names, " * "))
                end
            end
            if func.constant != 0.0
                push!(terms, "$(func.constant)")
            end
            return isempty(terms) ? "0" : join(terms, " + ")
        else
            return string(func)
        end
    catch e
        @debug "Could not convert function to string" exception = e
        return "<expression>"
    end
end

"""
    _check_variable_bound_conflict(model::JuMP.Model, var::JuMP.VariableRef)::Union{IISConflict, Nothing}

Check if a variable's bounds are in conflict.

# Arguments
- `model::JuMP.Model`: The JuMP model
- `var::JuMP.VariableRef`: Variable to check

# Returns
- `IISConflict` if bounds are in conflict, `nothing` otherwise
"""
function _check_variable_bound_conflict(model::JuMP.Model, var::JuMP.VariableRef)::Union{IISConflict,Nothing}
    try
        var_name = JuMP.name(var)
        if isempty(var_name)
            var_name = "unnamed_var"
        end
        
        # Check lower bound conflict
        has_lower = has_lower_bound(var)
        has_upper = has_upper_bound(var)
        
        lower_conflict = false
        upper_conflict = false
        
        # Check if variable bounds are in conflict
        # This is a simplified check - actual IIS detection is more sophisticated
        if has_lower && has_upper
            lb = lower_bound(var)
            ub = upper_bound(var)
            if lb > ub
                # Direct conflict: lower > upper
                return IISConflict(
                    constraint_ref = nothing,
                    constraint_name = "variable_bounds[$(var_name)]",
                    expression = "$(lb) <= $(var_name) <= $(ub)",
                    lower_bound = lb,
                    upper_bound = ub
                )
            end
        end
        
        return nothing
    catch e
        @debug "Could not check variable bound conflict" exception = e
        return nothing
    end
end

"""
    write_iis_report(result::IISResult; 
                     output_dir::String="logs",
                     filename::Union{String, Nothing}=nothing)::String

Write a detailed IIS report to a file.

The report includes:
- Summary of IIS computation
- List of all conflicting constraints/bounds
- Detailed expressions for each conflict
- Recommendations for debugging

# Arguments
- `result::IISResult`: The IIS computation result
- `output_dir::String="logs"`: Directory to write report (default: "logs")
- `filename::Union{String, Nothing}=nothing`: Custom filename (default: auto-generate with timestamp)

# Returns
- `String`: Path to the generated report file

# Example
```julia
iis = compute_iis!(model)
report_path = write_iis_report(iis; output_dir="diagnostics")
println("Report saved to: \$report_path")
```
"""
function write_iis_report(
    result::IISResult;
    output_dir::String = "logs",
    filename::Union{String,Nothing} = nothing
)::String
    # Create output directory if needed
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    
    # Generate filename with timestamp
    if filename === nothing
        timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
        filename = "iis_report_$(timestamp).txt"
    end
    
    filepath = joinpath(output_dir, filename)
    
    # Build report content
    lines = String[]
    
    # Header
    push!(lines, "=" ^ 70)
    push!(lines, "IIS (Irreducible Inconsistent Subsystem) Report")
    push!(lines, "OpenDESSEM Infeasibility Diagnostics")
    push!(lines, "=" ^ 70)
    push!(lines, "")
    
    # Metadata
    push!(lines, "Generated: $(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"))")
    push!(lines, "Solver Used: $(result.solver_used)")
    push!(lines, "Computation Time: $(round(result.computation_time; digits=3)) seconds")
    push!(lines, "Status: $(result.status)")
    push!(lines, "")
    
    # Summary
    push!(lines, "-" ^ 70)
    push!(lines, "SUMMARY")
    push!(lines, "-" ^ 70)
    
    if result.status == MOI.COMPUTE_CONFLICT_SUCCESS
        push!(lines, "IIS computation SUCCESSFUL")
        push!(lines, "Number of conflicting elements: $(length(result.conflicts))")
    elseif result.status == MOI.COMPUTE_CONFLICT_NOT_SUPPORTED
        push!(lines, "IIS computation NOT SUPPORTED by solver")
        push!(lines, "")
        push!(lines, "Recommendations:")
        push!(lines, "  1. Try using Gurobi or CPLEX for full IIS support")
        push!(lines, "  2. Manually review constraints that may conflict")
        push!(lines, "  3. Check for obvious issues like:")
        push!(lines, "     - Variable bounds: lower > upper")
        push!(lines, "     - Capacity constraints: min > max")
        push!(lines, "     - Demand constraints: demand > total capacity")
    else
        push!(lines, "IIS computation status: $(result.status)")
    end
    push!(lines, "")
    
    # Detailed conflicts
    if !isempty(result.conflicts)
        push!(lines, "-" ^ 70)
        push!(lines, "CONFLICTING CONSTRAINTS/BOUNDS")
        push!(lines, "-" ^ 70)
        push!(lines, "")
        
        for (i, conflict) in enumerate(result.conflicts)
            push!(lines, "[$(i)] $(conflict.constraint_name)")
            push!(lines, "    Expression: $(conflict.expression)")
            
            if conflict.lower_bound !== nothing || conflict.upper_bound !== nothing
                bounds_str = "    Bounds: "
                if conflict.lower_bound !== nothing
                    bounds_str *= "lower = $(conflict.lower_bound)"
                end
                if conflict.upper_bound !== nothing
                    if conflict.lower_bound !== nothing
                        bounds_str *= ", "
                    end
                    bounds_str *= "upper = $(conflict.upper_bound)"
                end
                push!(lines, bounds_str)
            end
            push!(lines, "")
        end
    end
    
    # Troubleshooting section
    push!(lines, "-" ^ 70)
    push!(lines, "TROUBLESHOOTING GUIDE")
    push!(lines, "-" ^ 70)
    push!(lines, "")
    push!(lines, "Common causes of infeasibility in DESSEM models:")
    push!(lines, "")
    push!(lines, "1. CAPACITY MISMATCH")
    push!(lines, "   - Thermal min_generation > max_generation")
    push!(lines, "   - Hydro min_outflow > max_outflow")
    push!(lines, "   - Check entity constructor validation")
    push!(lines, "")
    push!(lines, "2. DEMAND IMBALANCE")
    push!(lines, "   - Total demand exceeds total generation capacity")
    push!(lines, "   - Add deficit variables with high penalty cost")
    push!(lines, "   - Check load_shedding variables are present")
    push!(lines, "")
    push!(lines, "3. NETWORK CONSTRAINTS")
    push!(lines, "   - Transmission limits too tight")
    push!(lines, "   - Interconnection flow limits blocking all paths")
    push!(lines, "   - Check ACLine and DCLine limits")
    push!(lines, "")
    push!(lines, "4. HYDRO CASCADE")
    push!(lines, "   - Water balance constraints conflicting")
    push!(lines, "   - Initial storage + inflow < minimum required outflow")
    push!(lines, "   - Check reservoir initial volumes")
    push!(lines, "")
    push!(lines, "5. UNIT COMMITMENT")
    push!(lines, "   - min_up_time/min_down_time conflicts")
    push!(lines, "   - Initial state incompatible with requirements")
    push!(lines, "   - Ramp constraints too restrictive")
    push!(lines, "")
    push!(lines, "=" ^ 70)
    push!(lines, "End of IIS Report")
    push!(lines, "=" ^ 70)
    
    # Write to file
    content = join(lines, "\n")
    open(filepath, "w") do f
        write(f, content)
    end
    
    @info "IIS report written to: $filepath"
    
    return filepath
end

# Export public functions
export compute_iis!, write_iis_report
