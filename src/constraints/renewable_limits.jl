"""
    Renewable Generation Constraints

Implements constraints for wind and solar generation including:
- Capacity limits (forecast-based)
- Curtailment
- Ramp limits (for wind)
"""

# Note: JuMP, Dates, and all entity/constraint types are imported in parent Constraints.jl module

"""
    RenewableLimitConstraint <: AbstractConstraint

Generation limits for renewable plants.

# Fields
- `metadata::ConstraintMetadata`: Constraint metadata
- `include_curtailment::Bool`: Allow curtailment (default true)
- `plant_ids::Vector{String}`: Specific plant IDs (empty = all)
- `use_time_periods::Union{Nothing, UnitRange{Int}, Vector{Int}}`: Time periods

# Constraints Added

For each renewable plant `i` and time period `t`:
```
gr[i,t] + curtail[i,t] <= forecast[i,t]
gr[i,t] >= 0
curtail[i,t] >= 0
```

# Example
```julia
constraint = RenewableLimitConstraint(;
    metadata=ConstraintMetadata(;
        name="Renewable Limits",
        description="Wind and solar capacity limits",
        priority=10
    ),
    include_curtailment=true
)

result = build!(model, system, constraint)
```
"""
Base.@kwdef struct RenewableLimitConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    include_curtailment::Bool = true
    plant_ids::Vector{String} = String[]
    use_time_periods::Union{Nothing,UnitRange{Int},Vector{Int}} = nothing
end

"""
    build!(model::Model, system::ElectricitySystem, constraint::RenewableLimitConstraint)
"""
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::RenewableLimitConstraint,
)
    start_time = time()
    num_constraints = 0

    if !validate_constraint_system(system)
        return ConstraintBuildResult(;
            constraint_type = "RenewableLimitConstraint",
            success = false,
            message = "System validation failed",
        )
    end

    # Collect renewables
    all_renewables = vcat(system.wind_farms, system.solar_farms)

    plants = if isempty(constraint.plant_ids)
        all_renewables
    else
        plant_set = Set(constraint.plant_ids)
        [p for p in all_renewables if p.id in plant_set]
    end

    if isempty(plants)
        return ConstraintBuildResult(;
            constraint_type = "RenewableLimitConstraint",
            success = false,
            message = "No renewable plants found",
        )
    end

    plant_indices = get_renewable_plant_indices(system)

    time_periods = if constraint.use_time_periods === nothing
        1:size(model[:gr], 2)
    else
        constraint.use_time_periods
    end

    gr = model[:gr]
    curtail = get(object_dictionary(model), :curtail, nothing)

    if constraint.include_curtailment && curtail === nothing
        @warn "Curtailment enabled but curtail variables not found"
    end

    for plant in plants
        plant_idx = plant_indices[plant.id]

        # Get forecast profile
        forecast = if plant isa WindPlant
            plant.capacity_forecast_mw
        else  # SolarPlant
            plant.capacity_forecast_mw
        end

        for (t_idx, t) in enumerate(time_periods)
            if t_idx <= length(forecast)
                capacity = forecast[t_idx]

                if constraint.include_curtailment && curtail !== nothing
                    @constraint(model, gr[plant_idx, t] + curtail[plant_idx, t] <= capacity)
                    num_constraints += 1
                else
                    @constraint(model, gr[plant_idx, t] <= capacity)
                    num_constraints += 1
                end

                @constraint(model, gr[plant_idx, t] >= 0)
                num_constraints += 1
            end
        end
    end

    build_time = time() - start_time

    return ConstraintBuildResult(;
        constraint_type = "RenewableLimitConstraint",
        num_constraints = num_constraints,
        build_time_seconds = build_time,
        success = true,
        message = "Built $num_constraints renewable limit constraints",
    )
end

# Export
export RenewableLimitConstraint, build!
