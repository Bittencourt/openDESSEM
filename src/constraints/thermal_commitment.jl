"""
    Thermal Unit Commitment Constraints

Implements unit commitment constraints for thermal power plants including:
- Capacity limits (minimum and maximum generation)
- Ramp rate limits (up and down)
- Minimum up/down time constraints
- Startup/shutdown logic

These constraints are essential for modeling the operational characteristics
of thermal power plants in the Brazilian system.
"""

# Note: JuMP, Dates, and all entity/constraint types are imported in parent Constraints.jl module

"""
    ThermalCommitmentConstraint <: AbstractConstraint

Unit commitment constraints for thermal power plants.

# Fields
- `metadata::ConstraintMetadata`: Constraint metadata
- `include_ramp_rates::Bool`: Include ramp rate constraints (default true)
- `include_min_up_down::Bool`: Include minimum up/down time constraints (default true)
- `plant_ids::Vector{String}`: Specific plant IDs to constrain (empty = all thermal plants)
- `use_time_periods::Union{Nothing, UnitRange{Int}, Vector{Int}}`: Time periods to constrain (nothing = all)

# Constraints Added

## Capacity Limits
For each thermal plant `i` and time period `t`:
```
g_min * u[i,t] <= g[i,t] <= g_max * u[i,t]
```

## Ramp Rate Limits (if enabled)
For each thermal plant `i` and time period `t > 1`:
```
g[i,t] - g[i,t-1] <= ramp_up * 60  # MW per hour
g[i,t-1] - g[i,t] <= ramp_down * 60
```

## Startup/Shutdown Logic
For each thermal plant `i` and time period `t`:
```
u[i,t] - u[i,t-1] = v[i,t] - w[i,t]
v[i,t] + w[i,t] <= 1
```

## Minimum Up/Down Time (if enabled)
For each thermal plant `i`:
```
sum(u[i, t-min_up_time+1:t]) >= min_up_time * v[i,t]  # Minimum up
sum(1 - u[i, t-min_down_time+1:t]) >= min_down_time * w[i,t]  # Minimum down
```

# Example
```julia
using OpenDESSEM
using OpenDESSEM.Constraints

constraint = ThermalCommitmentConstraint(;
    metadata=ConstraintMetadata(;
        name="Thermal Unit Commitment",
        description="Standard UC constraints for thermal plants",
        priority=10
    ),
    include_ramp_rates=true,
    include_min_up_down=true,
    plant_ids=[]  # Empty = all thermal plants
)

result = build!(model, system, constraint)
```
"""
Base.@kwdef struct ThermalCommitmentConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    include_ramp_rates::Bool = true
    include_min_up_down::Bool = true
    plant_ids::Vector{String} = String[]
    use_time_periods::Union{Nothing,UnitRange{Int},Vector{Int}} = nothing
    initial_commitment::Dict{String,Bool} = Dict{String,Bool}()  # Plant ID => initially online (true/false)
end

"""
    build!(model::Model, system::ElectricitySystem, constraint::ThermalCommitmentConstraint)

Build thermal unit commitment constraints.

# Arguments
- `model::Model`: JuMP optimization model
- `system::ElectricitySystem`: Electricity system with thermal plants
- `constraint::ThermalCommitmentConstraint`: Constraint configuration

# Returns
- `ConstraintBuildResult`: Build statistics

# Variables Required (from VariableManager)
- `u[i,t]`: Binary commitment status
- `v[i,t]`: Binary startup indicator
- `w[i,t]`: Binary shutdown indicator
- `g[i,t]`: Continuous generation output

# Example
```julia
result = build!(model, system, thermal_constraint)
println("Built \$(result.num_constraints) constraints")
```
"""
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::ThermalCommitmentConstraint,
)
    start_time = time()
    num_constraints = 0
    warnings = String[]

    # Validate system
    if !validate_constraint_system(system)
        return ConstraintBuildResult(;
            constraint_type = "ThermalCommitmentConstraint",
            success = false,
            message = "System validation failed",
        )
    end

    # Check if variables exist
    if !haskey(object_dictionary(model), :u) || !haskey(object_dictionary(model), :g)
        @warn "Thermal variables (u, g) not found in model. Run create_thermal_variables! first."
        return ConstraintBuildResult(;
            constraint_type = "ThermalCommitmentConstraint",
            success = false,
            message = "Required variables not found",
        )
    end

    # Get variables
    u = model[:u]
    v = get(object_dictionary(model), :v, nothing)
    w = get(object_dictionary(model), :w, nothing)
    g = model[:g]

    # Filter plants
    plants = if isempty(constraint.plant_ids)
        system.thermal_plants
    else
        plant_set = Set(constraint.plant_ids)
        [p for p in system.thermal_plants if p.id in plant_set]
    end

    if isempty(plants)
        @warn "No thermal plants found for constraint building"
        return ConstraintBuildResult(;
            constraint_type = "ThermalCommitmentConstraint",
            success = false,
            message = "No thermal plants found",
        )
    end

    # Get plant indices
    plant_indices = get_thermal_plant_indices(system)

    # Determine time periods
    time_periods = if constraint.use_time_periods === nothing
        1:size(u, 2)
    else
        constraint.use_time_periods
    end

    n_periods = length(time_periods)

    @info "Building thermal commitment constraints" num_plants = length(plants) num_periods =
        n_periods

    # Build constraints for each plant
    for (idx, plant) in enumerate(plants)
        plant_idx = plant_indices[plant.id]

        for (t_idx, t) in enumerate(time_periods)
            # Capacity limits: g_min * u <= g <= g_max * u
            @constraint(model, g[plant_idx, t] >= plant.min_generation_mw * u[plant_idx, t])
            @constraint(model, g[plant_idx, t] <= plant.max_generation_mw * u[plant_idx, t])
            num_constraints += 2

            # Ramp rate constraints
            if constraint.include_ramp_rates && t > 1
                ramp_up_mw_per_hour = plant.ramp_up_mw_per_min * 60.0
                ramp_down_mw_per_hour = plant.ramp_down_mw_per_min * 60.0

                @constraint(
                    model,
                    g[plant_idx, t] - g[plant_idx, t-1] <= ramp_up_mw_per_hour
                )
                @constraint(
                    model,
                    g[plant_idx, t-1] - g[plant_idx, t] <= ramp_down_mw_per_hour
                )
                num_constraints += 2
            end

            # Startup/shutdown logic
            if v !== nothing && w !== nothing
                if t > 1
                    @constraint(
                        model,
                        u[plant_idx, t] - u[plant_idx, t-1] ==
                        v[plant_idx, t] - w[plant_idx, t]
                    )
                else
                    # For t=1, use initial commitment state
                    initial_state = get(constraint.initial_commitment, plant.id, false) ? 1.0 : 0.0
                    @constraint(
                        model,
                        u[plant_idx, t] - initial_state ==
                        v[plant_idx, t] - w[plant_idx, t]
                    )
                end
                @constraint(model, v[plant_idx, t] + w[plant_idx, t] <= 1)
                num_constraints += 2
            end
        end

        # Minimum up/down time constraints
        if constraint.include_min_up_down
            min_up = plant.min_up_time_hours
            min_down = plant.min_down_time_hours

            # Minimum up time: if starts up, must stay up for min_up hours
            for t in time_periods
                if t >= min_up && v !== nothing
                    up_window = max(1, t - min_up + 1):t
                    @constraint(
                        model,
                        sum(u[plant_idx, τ] for τ in up_window) >= min_up * v[plant_idx, t]
                    )
                    num_constraints += 1
                end
            end

            # Minimum down time: if shuts down, must stay down for min_down hours
            for t in time_periods
                if t >= min_down && w !== nothing
                    down_window = max(1, t - min_down + 1):t
                    @constraint(
                        model,
                        sum(1 - u[plant_idx, τ] for τ in down_window) >=
                        min_down * w[plant_idx, t]
                    )
                    num_constraints += 1
                end
            end
        end
    end

    build_time = time() - start_time

    @info "Thermal commitment constraints built successfully" num_constraints =
        num_constraints build_time = build_time

    return ConstraintBuildResult(;
        constraint_type = "ThermalCommitmentConstraint",
        num_constraints = num_constraints,
        build_time_seconds = build_time,
        success = true,
        message = "Built $num_constraints thermal UC constraints",
        warnings = warnings,
    )
end

# Export
export ThermalCommitmentConstraint, build!
