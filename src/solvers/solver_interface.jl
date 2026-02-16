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
    options::SolverOptions = SolverOptions(),
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
    options::SolverOptions = SolverOptions(),
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
    if status == MOI.OPTIMAL ||
       status == MOI.LOCALLY_SOLVED ||
       status == MOI.TIME_LIMIT ||
       status == MOI.ITERATION_LIMIT ||
       status == MOI.NODE_LIMIT ||
       status == MOI.SOLUTION_LIMIT ||
       status == MOI.MEMORY_LIMIT ||
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
        status = status,
        solve_status = map_to_solve_status(status),
        objective_value = obj_value,
        solve_time_seconds = solve_time,
        objective_bound = obj_bound,
        node_count = node_count,
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
    options::SolverOptions = SolverOptions(),
)
    # Create LP relaxation options
    lp_options = SolverOptions(;
        time_limit_seconds = options.time_limit_seconds,
        threads = options.threads,
        verbose = options.verbose,
        solver_specific = copy(options.solver_specific),
        lp_relaxation = true,  # This triggers the LP relaxation in optimize!
    )

    # Solve with LP relaxation
    return optimize!(model, system, optimizer_factory; options = lp_options)
end

# ============================================================================
# Unified Solve API
# ============================================================================

"""
    solve_model!(
        model::Model,
        system::ElectricitySystem;
        solver=HiGHS.Optimizer,
        time_limit::Float64=3600.0,
        mip_gap::Float64=0.01,
        output_level::Int=1,
        pricing::Bool=true,
        log_file::Union{String,Nothing}=nothing,
        progress_callback=nothing,
        warm_start::Union{SolverResult,Nothing}=nothing,
        solver_attributes::Dict{String,Any}=Dict{String,Any}()
    ) -> SolverResult

Unified solve API with two-stage pricing support.

This is the main entry point for solving OpenDESSEM optimization models.
It supports both single-stage (pricing=false) and two-stage (pricing=true)
solving for obtaining valid locational marginal prices (LMPs).

# Arguments
- `model::Model`: JuMP model with objective and constraints
- `system::ElectricitySystem`: Electricity system (for variable indexing)
- `solver`: Optimizer factory (default: HiGHS.Optimizer)
- `time_limit::Float64`: Time limit in seconds (default: 3600.0)
- `mip_gap::Float64`: MIP gap tolerance (default: 0.01 = 1%)
- `output_level::Int`: 0=silent, 1=minimal, 2=detailed (default: 1)
- `pricing::Bool`: Enable two-stage pricing for PLDs (default: true)
- `log_file::Union{String,Nothing}`: Log file path (default: auto-generate)
- `progress_callback`: Function for progress updates (default: nothing)
- `warm_start::Union{SolverResult,Nothing}`: Previous solution for warm start (default: nothing)
- `solver_attributes::Dict{String,Any}`: Solver-specific options (default: empty Dict)

# Returns
- `SolverResult`: Unified result with:
  - `solve_status`: User-friendly status enum
  - `mip_result`: Stage 1 UC result (when pricing=true)
  - `lp_result`: Stage 2 SCED result (when pricing=true)
  - `cost_breakdown`: Component costs dictionary
  - `log_file`: Path to generated log file

# Two-Stage Pricing
When `pricing=true` (default), uses the standard market approach:
1. **Stage 1 (UC)**: Solve unit commitment MIP → commitment decisions
2. **Stage 2 (SCED)**: Fix commitments, solve LP → valid LMPs

This is required for problems with binary commitment variables to obtain
mathematically valid shadow prices.

# Example
```julia
# Solve with two-stage pricing (default)
result = solve_model!(model, system)
if result.solve_status == OPTIMAL
    println("Total cost: R\$ ", result.objective_value)
    # Extract LMPs from SCED result
    if result.lp_result !== nothing
        lmps_se = get_submarket_lmps(result.lp_result, "SE", 1:24)
    end
end

# Solve without pricing (faster, but no valid LMPs)
result = solve_model!(model, system; pricing=false)

# Solve with custom options
result = solve_model!(model, system;
    solver=HiGHS.Optimizer,
    time_limit=1800.0,
    mip_gap=0.005,
    output_level=2,
    solver_attributes=Dict("presolve" => true)
)

# Warm start from previous solution
result = solve_model!(model, system; warm_start=previous_result)
```

# See Also
- [`compute_two_stage_lmps`](@ref): Lower-level two-stage function
- [`optimize!`](@ref): Lower-level solve function
- [`SolveStatus`](@ref): Status enum values
"""
function solve_model!(
    model::Model,
    system::ElectricitySystem;
    solver = HiGHS.Optimizer,
    time_limit::Float64 = 3600.0,
    mip_gap::Float64 = 0.01,
    output_level::Int = 1,
    pricing::Bool = true,
    log_file::Union{String,Nothing} = nothing,
    progress_callback = nothing,
    warm_start::Union{SolverResult,Nothing} = nothing,
    solver_attributes::Dict{String,Any} = Dict{String,Any}(),
)
    start_time = time()

    # Generate log file path if not provided
    if log_file === nothing
        logs_dir = joinpath(pwd(), "logs")
        if !isdir(logs_dir)
            mkpath(logs_dir)
        end
        timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
        log_file = joinpath(logs_dir, "dessem_solve_$(timestamp).log")
    end

    # Build SolverOptions from kwargs
    verbose = output_level > 0
    options = SolverOptions(;
        time_limit_seconds = time_limit,
        mip_gap = mip_gap,
        threads = 1,
        verbose = verbose,
        solver_specific = solver_attributes,
        warm_start = warm_start !== nothing,
        lp_relaxation = false,
    )

    # Apply warm start if provided
    if warm_start !== nothing && warm_start.has_values
        _apply_warm_start!(model, system, warm_start)
    end

    # Call progress callback if provided
    if progress_callback !== nothing
        progress_callback("Starting solve...")
    end

    # Create unified result
    result = SolverResult(;
        status = MOI.OPTIMIZE_NOT_CALLED,
        solve_status = NOT_SOLVED,
        log_file = log_file,
    )

    # Determine solving approach
    if pricing
        # Two-stage pricing: UC → SCED
        if progress_callback !== nothing
            progress_callback("Stage 1: Solving Unit Commitment (MIP)...")
        end

        uc_result, sced_result =
            compute_two_stage_lmps(model, system, solver; options = options)

        # Populate unified result
        result.status = uc_result.status
        result.solve_status = map_to_solve_status(uc_result.status)
        result.objective_value = uc_result.objective_value
        result.solve_time_seconds = uc_result.solve_time_seconds
        result.objective_bound = uc_result.objective_bound
        result.node_count = uc_result.node_count
        result.variables = uc_result.variables
        result.dual_values = uc_result.dual_values
        result.has_values = uc_result.has_values
        result.has_duals = uc_result.has_duals
        result.mip_result = uc_result
        result.lp_result = sced_result

        # Build cost breakdown from SCED if available
        if sced_result !== nothing && sced_result.has_values
            result.cost_breakdown = _build_cost_breakdown(sced_result, system)
        elseif uc_result.has_values
            result.cost_breakdown = _build_cost_breakdown(uc_result, system)
        end

        if progress_callback !== nothing
            progress_callback("Two-stage solve complete.")
        end
    else
        # Single-stage solve (no pricing)
        if progress_callback !== nothing
            progress_callback("Solving model...")
        end

        single_result = optimize!(model, system, solver; options = options)

        # Populate unified result
        result.status = single_result.status
        result.solve_status = map_to_solve_status(single_result.status)
        result.objective_value = single_result.objective_value
        result.solve_time_seconds = single_result.solve_time_seconds
        result.objective_bound = single_result.objective_bound
        result.node_count = single_result.node_count
        result.variables = single_result.variables
        result.dual_values = single_result.dual_values
        result.has_values = single_result.has_values
        result.has_duals = single_result.has_duals
        result.mip_result = single_result
        result.lp_result = nothing

        if single_result.has_values
            result.cost_breakdown = _build_cost_breakdown(single_result, system)
        end

        if progress_callback !== nothing
            progress_callback("Single-stage solve complete.")
        end
    end

    # Log solve summary to file
    _write_log_summary(result, log_file, start_time)

    return result
end

# ============================================================================
# Internal Helper Functions for solve_model!
# ============================================================================

"""
    _apply_warm_start!(model::Model, system::ElectricitySystem, warm_start::SolverResult)

Apply warm start values from a previous solution to the model variables.
"""
function _apply_warm_start!(
    model::Model,
    system::ElectricitySystem,
    warm_start::SolverResult,
)
    obj_dict = object_dictionary(model)

    # Get plant indices
    thermal_indices = get(obj_dict, :thermal_indices, get_thermal_plant_indices(system))

    # Apply thermal commitment warm starts
    if haskey(warm_start.variables, :thermal_commitment) && haskey(obj_dict, :u)
        u_values = warm_start.variables[:thermal_commitment]
        u = model[:u]

        for ((plant_id, t), val) in u_values
            if haskey(thermal_indices, plant_id)
                idx = thermal_indices[plant_id]
                try
                    set_start_value(u[idx, t], round(val))  # Round to 0 or 1 for binary
                catch
                    @debug "Could not set warm start for u[$idx, $t]"
                end
            end
        end
    end

    # Apply thermal generation warm starts
    if haskey(warm_start.variables, :thermal_generation) && haskey(obj_dict, :g)
        g_values = warm_start.variables[:thermal_generation]
        g = model[:g]

        for ((plant_id, t), val) in g_values
            if haskey(thermal_indices, plant_id)
                idx = thermal_indices[plant_id]
                try
                    set_start_value(g[idx, t], val)
                catch
                    @debug "Could not set warm start for g[$idx, $t]"
                end
            end
        end
    end

    # Additional variable warm starts can be added here as needed

    return nothing
end

"""
    _build_cost_breakdown(result::SolverResult, system::ElectricitySystem) -> Dict{String, Float64}

Build a cost breakdown dictionary from the result.
"""
function _build_cost_breakdown(result::SolverResult, system::ElectricitySystem)
    breakdown = Dict{String,Float64}()

    # Thermal fuel costs
    thermal_cost = 0.0
    if haskey(result.variables, :thermal_generation)
        for plant in system.thermal_plants
            gen = get_thermal_generation(result, plant.id, 1:1)
            if !isempty(gen)
                thermal_cost += sum(gen) * plant.fuel_cost_rsj_per_mwh / 1e6  # Scale down
            end
        end
    end
    breakdown["thermal_fuel"] = thermal_cost

    # Startup costs (if tracked)
    if haskey(result.variables, :thermal_startup)
        startup_cost = 0.0
        for plant in system.thermal_plants
            startup_cost += plant.startup_cost_rs / 1e6  # Scale down
        end
        breakdown["startup"] = startup_cost
    end

    # Total
    if result.objective_value !== nothing
        breakdown["total"] = result.objective_value / 1e6  # Scale down
    end

    return breakdown
end

"""
    _write_log_summary(result::SolverResult, log_file::String, start_time::Float64)

Write a solve summary to the log file.
"""
function _write_log_summary(result::SolverResult, log_file::String, start_time::Float64)
    try
        open(log_file, "w") do io
            println(io, "OpenDESSEM Solve Summary")
            println(io, "="^50)
            println(io, "")
            println(io, "Status: ", result.solve_status)
            println(
                io,
                "Solve Time: ",
                round(result.solve_time_seconds; digits = 2),
                " seconds",
            )
            println(
                io,
                "Total Wall Time: ",
                round(time() - start_time; digits = 2),
                " seconds",
            )

            if result.objective_value !== nothing
                println(io, "Objective Value: ", result.objective_value)
            end

            if result.objective_bound !== nothing
                println(io, "Objective Bound: ", result.objective_bound)
            end

            if result.node_count !== nothing
                println(io, "Node Count: ", result.node_count)
            end

            println(io, "")
            println(io, "Cost Breakdown:")
            for (component, cost) in result.cost_breakdown
                println(io, "  $component: $cost")
            end

            if result.mip_result !== nothing
                println(io, "")
                println(io, "Stage 1 (UC): $(result.mip_result.solve_status)")
            end

            if result.lp_result !== nothing
                println(io, "Stage 2 (SCED): $(result.lp_result.solve_status)")
            end
        end
    catch e
        @warn "Could not write log file: $e"
    end

    return nothing
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
export solve_model!,
    optimize!,
    solve_lp_relaxation,
    get_solver_optimizer,
    apply_solver_options!,
    _infer_time_periods,
    _is_lp_model
