"""
    Solver Interface

Main solver interface functions for OpenDESSEM optimization.
"""

"""
    get_solver_optimizer(solver_type::SolverType; options::SolverOptions=SolverOptions())

Create a JuMP-compatible optimizer factory for the specified solver.

# Arguments
- `solver_type::SolverType`: Solver type to create
- `options::SolverOptions`: Solver options (optional)

# Returns
- Optimizer factory for use with `Model()`

# Example
```julia
optimizer = get_solver_optimizer(HIGHS;
    options=SolverOptions(threads=4, verbose=true))
model = Model(optimizer)
```
"""
function get_solver_optimizer(
    solver_type::SolverType;
    options::SolverOptions=SolverOptions(),
)
    if solver_type == HIGHS
        return HiGHS.Optimizer
    elseif solver_type == GUROBI
        try
            return Gurobi.Optimizer
        catch
            error("Gurobi.jl not installed. Install with: import Pkg; Pkg.add(\"Gurobi\")")
        end
    elseif solver_type == CPLEX
        try
            return CPLEX.Optimizer
        catch
            error("CPLEX.jl not installed. Install with: import Pkg; Pkg.add(\"CPLEX\")")
        end
    elseif solver_type == GLPK
        try
            return GLPK.Optimizer
        catch
            error("GLPK.jl not installed. Install with: import Pkg; Pkg.add(\"GLPK\")")
        end
    else
        error("Unsupported solver type: $solver_type")
    end
end

"""
    apply_solver_options!(model::Model, options::SolverOptions, solver_type::SolverType)

Apply solver options to the model before solving.

# Arguments
- `model::Model`: JuMP model
- `options::SolverOptions`: Solver options to apply
- `solver_type::SolverType`: Type of solver (for solver-specific handling)

# Example
```julia
model = Model(HiGHS.Optimizer)
apply_solver_options!(model, options, HIGHS)
```
"""
function apply_solver_options!(
    model::Model,
    options::SolverOptions,
    solver_type::SolverType,
)
    # Set verbosity
    if !options.verbose
        MOI.set(model, MOI.Silent(), true)
    end

    # Set time limit
    if options.time_limit_seconds !== nothing
        MOI.set(model, MOI.TimeLimitSec(), options.time_limit_seconds)
    end

    # Set thread count
    if options.threads > 1
        MOI.set(model, MOI.NumberOfThreads(), options.threads)
    end

    # Set MIP gap tolerance (for MIP problems)
    if options.mip_gap !== nothing
        try
            MOI.set(model, MOI.RelativeGapTolerance(), options.mip_gap)
        catch e
            @warn "Could not set MIP gap: $e"
        end
    end

    # Apply solver-specific options
    for (key, value) in options.solver_specific
        try
            if solver_type == HIGHS
                # HiGHS-specific options
                if key == "presolve"
                    MOI.set(model, MOI.RawParameter("presolve"), value ? "on" : "off")
                elseif key == "method"
                    MOI.set(model, MOI.RawParameter("hihs_solver"), value)
                else
                    MOI.set(model, MOI.RawParameter(key), value)
                end
            elseif solver_type == GUROBI
                # Gurobi-specific options
                MOI.set(model, MOI.RawParameter(key), value)
            elseif solver_type == CPLEX
                # CPLEX-specific options
                MOI.set(model, MOI.RawParameter(key), value)
            elseif solver_type == GLPK
                # GLPK-specific options
                MOI.set(model, MOI.RawParameter(key), value)
            end
        catch e
            @warn "Could not set solver option '$key' = $value: $e"
        end
    end

    return nothing
end

"""
    optimize!(
        model::Model,
        system::ElectricitySystem,
        optimizer_factory;
        options::SolverOptions=SolverOptions()
    ) -> SolverResult

Solve the optimization model with the specified solver.

Applies solver options, solves the model, and extracts results.
Handles both MIP and LP problems. Can solve LP relaxation for
locational marginal price (LMP) calculation.

# Arguments
- `model::Model`: JuMP model with objective and constraints
- `system::ElectricitySystem`: Electricity system (for variable indexing)
- `optimizer_factory`: JuMP optimizer factory (e.g., `HiGHS.Optimizer`)
- `options::SolverOptions`: Solver configuration options

# Returns
- `SolverResult`: Complete solution with status and values

# Example
```julia
# Solve with default options
result = optimize!(model, system, HiGHS.Optimizer)

# Solve with time limit
result = optimize!(model, system, HiGHS.Optimizer;
    options=SolverOptions(time_limit_seconds=60.0))

# Check result
if is_optimal(result)
    println("Optimal cost: R\$ ", result.objective_value)
end
```
"""
function optimize!(
    model::Model,
    system::ElectricitySystem,
    optimizer_factory;
    options::SolverOptions=SolverOptions(),
)
    start_time = time()

    # Attach optimizer to model
    set_optimizer(model, optimizer_factory)

    # Determine solver type from optimizer factory
    # Default to HIGHS if we can't determine the type
    solver_type = HIGHS

    # Apply solver options
    apply_solver_options!(model, options, solver_type)

    # Handle LP relaxation if requested
    binary_vars = VariableRef[]
    integer_vars = VariableRef[]

    if options.lp_relaxation
        # Save the binary/integer status of all variables
        for var in all_variables(model)
            if is_binary(var)
                push!(binary_vars, var)
                unset_binary(var)
            elseif is_integer(var)
                push!(integer_vars, var)
                unset_integer(var)
            end
        end
    end

    # Function to restore variable types
    function restore_variable_types()
        for var in binary_vars
            set_binary(var)
        end
        for var in integer_vars
            set_integer(var)
        end
    end

    # Solve the model
    JuMP.optimize!(model)

    # Extract results
    solve_time = time() - start_time
    status = termination_status(model)

    obj_value = nothing
    obj_bound = nothing
    node_count = nothing

    # Check if the solver found a solution
    if status == MOI.OPTIMAL || status == MOI.LOCALLY_SOLVED || status == MOI.TIME_LIMIT ||
       status == MOI.ITERATION_LIMIT || status == MOI.NODE_LIMIT ||
       status == MOI.SOLUTION_LIMIT || status == MOI.MEMORY_LIMIT ||
       status == MOI.OBJECTIVE_LIMIT ||
       status == MOI.NUMERICAL_ERROR
        try
            obj_value = objective_value(model)
        catch
            @warn "Could not extract objective value"
        end

        try
            obj_bound = objective_bound(model)
        catch
            # Some solvers don't provide bound
        end

        try
            node_count = node_count(model)
        catch
            # Not all solvers provide node count
        end
    end

    result = SolverResult(;
        status=status,
        objective_value=obj_value,
        solve_time_seconds=solve_time,
        objective_bound=obj_bound,
        node_count=node_count
    )

    # Extract solution values if available
    if has_solution(result)
        time_periods = _infer_time_periods(model, system)
        extract_solution_values!(result, model, system, time_periods)

        # Extract dual values if LP
        if options.lp_relaxation || _is_lp_model(model)
            extract_dual_values!(result, model, system, time_periods)
        end
    end

    # Restore binary/integer variable types if we relaxed them
    if options.lp_relaxation
        restore_variable_types()
    end

    return result
end

"""
    solve_lp_relaxation(
        model::Model,
        system::ElectricitySystem,
        optimizer_factory;
        options::SolverOptions=SolverOptions()
    ) -> SolverResult

Create and solve an LP relaxation of the model for LMP calculation.

Creates a copy of the model with all integer variables relaxed to continuous,
then solves to get dual values (shadow prices) for marginal cost calculation.

# Arguments
- `model::Model`: Original JuMP model (with integer constraints)
- `system::ElectricitySystem`: Electricity system
- `optimizer_factory`: JuMP optimizer factory
- `options::SolverOptions`: Solver options

# Returns
- `SolverResult`: Solution from LP relaxation with dual values

# Example
```julia
lp_result = solve_lp_relaxation(model, system, HiGHS.Optimizer)
if is_optimal(lp_result)
    lmps = get_submarket_lmps(lp_result, \"SE\", 1:24)
end
```
"""
function solve_lp_relaxation(
    model::Model,
    system::ElectricitySystem,
    optimizer_factory;
    options::SolverOptions=SolverOptions(),
)
    # Create LP relaxation options
    lp_options = SolverOptions(;
        time_limit_seconds=options.time_limit_seconds,
        threads=options.threads,
        verbose=options.verbose,
        solver_specific=copy(options.solver_specific),
        lp_relaxation=true  # This triggers the LP relaxation in optimize!
    )

    # Solve with LP relaxation
    return optimize!(model, system, optimizer_factory; options=lp_options)
end

# ============================================================================
# Internal Helper Functions
# ============================================================================

"""
    _infer_time_periods(model::Model, system::ElectricitySystem) -> UnitRange{Int}

Infer the time periods from the model variables.

Returns a default range of 1:24 if cannot determine from model.
"""
function _infer_time_periods(model::Model, system::ElectricitySystem)
    # Try to infer from variables
    if haskey(model, :g) && !isempty(model[:g])
        # Check dimension of thermal generation variable
        g = model[:g]
        if g isa JuMP.VariableRef
            return 1:1  # Single period
        elseif hasmethod(size, (typeof(g)))
            dims = size(g)
            if length(dims) >= 2
                return 1:dims[2]  # Second dimension is time
            end
        end
    end

    # Default assumption
    @warn "Could not infer time periods from model, assuming 1:24"
    return 1:24
end

"""
    _is_lp_model(model::Model)::Bool

Check if the model is a pure LP (no integer/binary variables).
"""
function _is_lp_model(model::Model)::Bool
    for var in all_variables(model)
        if is_binary(var) || is_integer(var)
            return false
        end
    end
    return true
end

# Export public functions
export optimize!,
    solve_lp_relaxation,
    get_solver_optimizer,
    apply_solver_options!,
    _infer_time_periods,
    _is_lp_model
