"""
    Two-Stage LMP Pricing for OpenDESSEM

Implements the industry-standard two-stage approach for calculating
locational marginal prices (LMPs) in unit commitment markets.

## Background

Unit commitment problems are mixed-integer programs (MIPs) that do not have
valid dual variables. The industry standard solution is a two-stage approach:

### Stage 1: Security-Constrained Unit Commitment (SCUC)
- Solves full MIP with binary commitment variables
- Determines which plants to commit (u), start (v), and shut down (w)
- No valid dual variables (cannot compute LMPs)

### Stage 2: Security-Constrained Economic Dispatch (SCED)
- Fixes commitment decisions from Stage 1
- Re-solves as pure Linear Program (LP)
- Valid dual variables exist → can compute LMPs

This approach is used by all major US electricity markets (PJM, MISO, CAISO,
ERCOT, NYISO, ISO-NE).

## Functions

- `fix_commitment!()`: Fix binary variables to Stage 1 values
- `solve_sced_for_pricing()`: Solve Stage 2 SCED for LMPs
- `compute_two_stage_lmps()`: Complete two-stage optimization wrapper
"""

"""
    fix_commitment!(model::Model, system::ElectricitySystem, uc_result::SolverResult) -> Function

Fix binary commitment variables to their Stage 1 optimal values from the
unit commitment solution.

This modifies the model in-place by:
1. Extracting u, v, w values from the UC result
2. Fixing these variables at their optimal values
3. Removing integrality constraints (unset_binary)
4. Returning an undo function to restore the MIP formulation

# Arguments
- `model::Model`: JuMP model to modify (will be changed in-place)
- `system::ElectricitySystem`: Electricity system (used to rebuild indices after model copy)
- `uc_result::SolverResult`: Stage 1 UC solution with commitment decisions

# Returns
- `Function`: Undo function that restores the MIP formulation (unfix + set_binary)

# Notes
- Commitment values < 0.5 are rounded to 0, >= 0.5 are rounded to 1
- This handles floating point errors from MIP solver (e.g., 0.9999999)
- The undo function should be called after SCED solve to restore original model
- The `system` parameter is needed to rebuild index dictionaries after model copy

# Example
```julia
# Fix commitments from Stage 1
restore_mip = fix_commitment!(model, system, uc_result)

# Solve SCED (model now has fixed commitments, no binary variables)
optimize!(model)

# Restore original MIP formulation
restore_mip()
```
"""
function fix_commitment!(model::Model, system::ElectricitySystem, uc_result::SolverResult)
    # Check if UC result has the required variables
    if !uc_result.has_values
        error("UC result does not have variable values. Cannot fix commitments.")
    end

    # Extract commitment values from UC result
    if !haskey(uc_result.variables, :thermal_commitment)
        error("UC result missing thermal_commitment values")
    end

    u_values = uc_result.variables[:thermal_commitment]
    v_values = get(uc_result.variables, :thermal_startup, nothing)
    w_values = get(uc_result.variables, :thermal_shutdown, nothing)

    # Get model variables
    obj_dict = object_dictionary(model)

    if !haskey(obj_dict, :u)
        error("Model missing commitment variable :u")
    end

    u = model[:u]
    v = get(obj_dict, :v, nothing)
    w = get(obj_dict, :w, nothing)

    # Rebuild or get plant indices from system
    # After model copy, index dictionaries may be lost, so we rebuild from system
    thermal_indices = get(obj_dict, :thermal_indices, nothing)
    if thermal_indices === nothing
        thermal_indices = get_thermal_plant_indices(system)
        model[:thermal_indices] = thermal_indices
    end

    # Track modified variables for undo function
    modified_vars = VariableRef[]

    # Helper to round binary values (handles floating point errors)
    round_binary(val::Float64) = val < 0.5 ? 0.0 : 1.0

    # Fix u variables (commitment status)
    # Note: u_values keys are (plant_id_string, t) but model variables use (idx_int, t)
    for ((plant_id, t), val) in u_values
        # Convert plant_id string to integer index
        if !haskey(thermal_indices, plant_id)
            @warn "Plant ID not found in indices, skipping" plant_id = plant_id
            continue
        end
        idx = thermal_indices[plant_id]
        u_fixed = round_binary(val)
        fix(u[idx, t], u_fixed; force = true)
        unset_binary(u[idx, t])
        push!(modified_vars, u[idx, t])
    end

    # Fix v variables (startup indicators)
    if v_values !== nothing && v !== nothing
        for ((plant_id, t), val) in v_values
            if !haskey(thermal_indices, plant_id)
                continue
            end
            idx = thermal_indices[plant_id]
            v_fixed = round_binary(val)
            fix(v[idx, t], v_fixed; force = true)
            unset_binary(v[idx, t])
            push!(modified_vars, v[idx, t])
        end
    end

    # Fix w variables (shutdown indicators)
    if w_values !== nothing && w !== nothing
        for ((plant_id, t), val) in w_values
            if !haskey(thermal_indices, plant_id)
                continue
            end
            idx = thermal_indices[plant_id]
            w_fixed = round_binary(val)
            fix(w[idx, t], w_fixed; force = true)
            unset_binary(w[idx, t])
            push!(modified_vars, w[idx, t])
        end
    end

    # Return undo function to restore MIP formulation
    return function restore_mip!()
        for var in modified_vars
            unfix(var)
            set_binary(var)
        end
    end
end

"""
    solve_sced_for_pricing(
        model::Model,
        system::ElectricitySystem,
        uc_result::SolverResult,
        optimizer_factory;
        options::SolverOptions=SolverOptions()
    ) -> SolverResult

Stage 2: Solve Security-Constrained Economic Dispatch (SCED) for pricing.

Creates a copy of the model, fixes commitment decisions from Stage 1,
and solves as a pure LP to obtain valid dual values for LMP calculation.

# Arguments
- `model::Model`: Original UC model (will NOT be modified)
- `system::ElectricitySystem`: Electricity system
- `uc_result::SolverResult`: Stage 1 UC solution with commitment decisions
- `optimizer_factory`: JuMP optimizer factory (e.g., HiGHS.Optimizer)
- `options::SolverOptions`: Solver configuration options

# Returns
- `SolverResult`: SCED solution with valid LMPs in dual_values

# Process
1. Copy the model (to preserve original)
2. Fix commitment decisions using `fix_commitment!()`
3. Solve as pure LP
4. Extract solution and dual values
5. Restore MIP formulation
6. Return SCED result

# Example
```julia
# Stage 1: Solve UC
uc_result = optimize!(model, system, HiGHS.Optimizer)

# Stage 2: Solve SCED for pricing
sced_result = solve_sced_for_pricing(model, system, uc_result, HiGHS.Optimizer)

# Extract LMPs (now valid!)
lmps_se = get_submarket_lmps(sced_result, "SE", 1:24)
```
"""
function solve_sced_for_pricing(
    model::Model,
    system::ElectricitySystem,
    uc_result::SolverResult,
    optimizer_factory;
    options::SolverOptions = SolverOptions(),
)
    @info "Starting Stage 2: SCED for pricing"

    start_time = time()

    # Check UC result validity
    if !is_optimal(uc_result)
        @error "Stage 1 UC result is not optimal" status = uc_result.status
        return SolverResult(;
            status = uc_result.status,
            solve_time_seconds = 0.0,
            has_values = false,
            has_duals = false,
        )
    end

    # Copy the model to avoid modifying original
    # Note: JuMP.copy_model returns (Model, ReferenceMap) tuple
    sced_model = nothing  # Declare outside try block for scope
    ref_map = nothing

    try
        sced_model, ref_map = JuMP.copy_model(model)
    catch e
        @error "Failed to copy model" error = e
        return SolverResult(;
            status = MOI.INTERNAL_ERROR,
            solve_time_seconds = 0.0,
            has_values = false,
            has_duals = false,
        )
    end

    # Check that copy succeeded
    if sced_model === nothing
        @error "Model copy failed - sced_model is nothing"
        return SolverResult(;
            status = MOI.INTERNAL_ERROR,
            solve_time_seconds = 0.0,
            has_values = false,
            has_duals = false,
        )
    end

    # Rebuild the submarket_balance constraint dictionary using ReferenceMap
    # JuMP.copy_model skips Dict objects, so we need to rebuild manually
    if haskey(object_dictionary(model), :submarket_balance) && ref_map !== nothing
        original_balance = model[:submarket_balance]
        copied_balance = Dict{Tuple{String,Int},ConstraintRef}()

        for (key, original_constraint) in original_balance
            # Use ReferenceMap as a callable to get the copied constraint
            try
                copied_constraint = ref_map[original_constraint]
                copied_balance[key] = copied_constraint
            catch e
                @warn "Could not map constraint for key $key: $e"
            end
        end

        sced_model[:submarket_balance] = copied_balance
    end

    # Fix commitment decisions from Stage 1
    restore_mip = fix_commitment!(sced_model, system, uc_result)

    # Attach optimizer and solve SCED (pure LP now)
    set_optimizer(sced_model, optimizer_factory)
    apply_solver_options!(sced_model, options, HIGHS)

    @info "Solving SCED (LP)..."
    JuMP.optimize!(sced_model)

    # Extract results
    sced_status = termination_status(sced_model)
    solve_time = time() - start_time

    sced_result = if sced_status == MOI.OPTIMAL
        # Infer time periods
        time_periods = _infer_time_periods(sced_model, system)

        # Create result object
        result = SolverResult(;
            status = sced_status,
            objective_value = objective_value(sced_model),
            solve_time_seconds = solve_time,
            has_values = false,
            has_duals = false,
        )

        # Extract solution values
        extract_solution_values!(result, sced_model, system, time_periods)

        # Extract dual values (these are now valid!)
        extract_dual_values!(result, sced_model, system, time_periods)

        @info "SCED pricing complete" objective_value = result.objective_value has_duals =
            result.has_duals

        result
    else
        @warn "SCED solve failed" status = sced_status
        SolverResult(;
            status = sced_status,
            solve_time_seconds = solve_time,
            has_values = false,
            has_duals = false,
        )
    end

    # Restore original MIP formulation
    restore_mip()

    return sced_result
end

"""
    compute_two_stage_lmps(
        model::Model,
        system::ElectricitySystem,
        optimizer_factory;
        options::SolverOptions=SolverOptions()
    ) -> Tuple{SolverResult, Union{SolverResult, Nothing}}

Complete two-stage LMP calculation: Unit Commitment followed by SCED pricing.

This is the main user-facing function for two-stage optimization with pricing.

# Arguments
- `model::Model`: UC model with objective and constraints
- `system::ElectricitySystem`: Electricity system
- `optimizer_factory`: JuMP optimizer factory (e.g., HiGHS.Optimizer)
- `options::SolverOptions`: Solver configuration options

# Returns
- `uc_result::SolverResult`: Stage 1 UC solution (commitment + dispatch)
- `sced_result::Union{SolverResult, Nothing}`: Stage 2 SCED solution with LMPs (nothing if Stage 1 fails)

# Process
1. **Stage 1**: Solve Unit Commitment (MIP) → get commitment decisions
2. **Stage 2**: Fix commitments, solve SCED (LP) → get valid LMPs

# When to Use
- Use this function for **unit commitment problems** (has binary variables)
- Use `solve_lp_relaxation()` only for **pure LP problems** (no binary variables)

# Example
```julia
# Complete two-stage pricing
uc_result, sced_result = compute_two_stage_lmps(
    model, system, HiGHS.Optimizer;
    options=SolverOptions(time_limit_seconds=300, mip_gap=0.01)
)

# Check results
if sced_result !== nothing && is_optimal(sced_result)
    println("Stage 1 UC Objective: R\$ ", uc_result.objective_value)
    println("Stage 2 SCED Objective: R\$ ", sced_result.objective_value)

    # Extract valid LMPs
    lmps_se = get_submarket_lmps(sced_result, "SE", 1:24)
    println("Peak price in SE: R\$ ", maximum(lmps_se), "/MWh")
end
```

# See Also
- [`solve_lp_relaxation`](@ref): For pure LP problems (not UC)
- [`solve_sced_for_pricing`](@ref): Stage 2 only
- [`fix_commitment!`](@ref): Fix commitment variables
"""
function compute_two_stage_lmps(
    model::Model,
    system::ElectricitySystem,
    optimizer_factory;
    options::SolverOptions = SolverOptions(),
)
    @info "Starting two-stage LMP calculation"

    # Stage 1: Solve Unit Commitment (MIP)
    @info "Stage 1: Solving Unit Commitment (MIP)"
    uc_result = optimize!(model, system, optimizer_factory; options = options)

    if !is_optimal(uc_result)
        @error "Stage 1 UC failed to solve optimally" status = uc_result.status
        return uc_result, nothing
    end

    @info "Stage 1 complete" objective_value = uc_result.objective_value solve_time =
        uc_result.solve_time_seconds

    # Stage 2: Solve SCED for pricing
    sced_result = solve_sced_for_pricing(
        model,
        system,
        uc_result,
        optimizer_factory;
        options = options,
    )

    return uc_result, sced_result
end

# Export public functions
export fix_commitment!, solve_sced_for_pricing, compute_two_stage_lmps
