"""
    Hydro Generation Function Constraints

Implements the relationship between water outflow and power generation for hydro plants:
- Production function: generation = f(outflow, head, efficiency)
- Penstock and turbine capacity limits
- Minimum and minimum generation limits

These constraints model the physics of hydroelectric generation.
"""

# Note: JuMP, Dates, and all entity/constraint types are imported in parent Constraints.jl module

"""
    HydroGenerationConstraint <: AbstractConstraint

Hydro generation function constraints.

# Fields
- `metadata::ConstraintMetadata`: Constraint metadata
- `model_type::String`: Generation model type ("linear" or "piecewise")
- `plant_ids::Vector{String}`: Specific plant IDs to constrain (empty = all hydro plants)
- `use_time_periods::Union{Nothing, UnitRange{Int}, Vector{Int}}`: Time periods to constrain

# Constraints Added

## Linear Generation Model
For each hydro plant `i` and time period `t`:
```
gh[i,t] = efficiency * ρ * g * h * q[i,t]
```
where:
- `gh[i,t]`: Hydro generation (MW)
- `efficiency`: Plant efficiency (0-1)
- `ρ`: Water density (1000 kg/m³)
- `g`: Gravity (9.81 m/s²)
- `h`: Effective head (m) - assumed proportional to storage
- `q[i,t]`: Turbine outflow (m³/s)

For simplicity in OpenDESSEM, we use a simplified linear model:
```
gh[i,t] = productivity_coefficient * q[i,t]
```
where `productivity_coefficient` is pre-computed as:
```
MW_per_m3s = efficiency * 9.81 * 1000 * average_head / 1e6
```

## Generation Limits
```
min_generation * u[i,t] <= gh[i,t] <= max_generation * u[i,t]
```

## Outflow Limits
```
min_outflow <= q[i,t] <= max_outflow
```

# Example
```julia
constraint = HydroGenerationConstraint(;
    metadata=ConstraintMetadata(;
        name="Hydro Generation Function",
        description="Linear generation model for hydro plants",
        priority=10
    ),
    model_type="linear"
)

result = build!(model, system, constraint)
```
"""
Base.@kwdef struct HydroGenerationConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    model_type::String = "linear"  # "linear" or "piecewise"
    plant_ids::Vector{String} = String[]
    use_time_periods::Union{Nothing,UnitRange{Int},Vector{Int}} = nothing
end

"""
    build!(model::Model, system::ElectricitySystem, constraint::HydroGenerationConstraint)

Build hydro generation function constraints.

# Arguments
- `model::Model`: JuMP optimization model
- `system::ElectricitySystem`: Electricity system with hydro plants
- `constraint::HydroGenerationConstraint`: Constraint configuration

# Returns
- `ConstraintBuildResult`: Build statistics

# Variables Required (from VariableManager)
- `gh[i,t]`: Hydro generation (MW)
- `q[i,t]`: Turbine outflow (m³/s)
- `u[i,t]`: Commitment status (binary, optional)

# Notes
- Linear model assumes constant productivity coefficient
- Future versions may support piecewise linear or nonlinear models
- Productivity coefficient: MW per m³/s, typically 0.5-1.5 for Brazilian plants
"""
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::HydroGenerationConstraint,
)
    start_time = time()
    num_constraints = 0
    warnings = String[]

    # Validate system
    if !validate_constraint_system(system)
        return ConstraintBuildResult(;
            constraint_type = "HydroGenerationConstraint",
            success = false,
            message = "System validation failed",
        )
    end

    # Check if variables exist
    if !haskey(object_dictionary(model), :gh) || !haskey(object_dictionary(model), :q)
        @warn "Hydro variables (gh, q) not found in model. Run create_hydro_variables! first."
        return ConstraintBuildResult(;
            constraint_type = "HydroGenerationConstraint",
            success = false,
            message = "Required variables not found",
        )
    end

    # Get variables
    gh = model[:gh]
    q = model[:q]
    # Note: Hydro plants do NOT use thermal commitment variable (u)
    # Hydro has separate commitment logic or is treated as must-run
    u = nothing  # Explicitly disable thermal u for hydro

    # Filter hydro plants
    all_hydro = system.hydro_plants
    plants = if isempty(constraint.plant_ids)
        all_hydro
    else
        plant_set = Set(constraint.plant_ids)
        [p for p in all_hydro if p.id in plant_set]
    end

    if isempty(plants)
        @warn "No hydro plants found for constraint building"
        return ConstraintBuildResult(;
            constraint_type = "HydroGenerationConstraint",
            success = false,
            message = "No hydro plants found",
        )
    end

    # Get plant indices
    plant_indices = get_hydro_plant_indices(system)

    # Determine time periods
    time_periods = if constraint.use_time_periods === nothing
        1:size(gh, 2)
    else
        constraint.use_time_periods
    end

    @info "Building hydro generation constraints" num_plants = length(plants) num_periods =
        length(time_periods)

    for plant in plants
        plant_idx = plant_indices[plant.id]

        # Compute productivity coefficient
        # For reservoir plants: assume head is proportional to storage
        # For simplicity, use average productivity based on max generation and max outflow
        if plant isa ReservoirHydro
            # MW per m³/s = max_generation / max_outflow
            # This is a simplification - actual productivity depends on head
            productivity = plant.max_generation_mw / plant.max_outflow_m3_per_s
        elseif plant isa RunOfRiverHydro
            productivity = plant.max_generation_mw / plant.max_outflow_m3_per_s
        else
            productivity = 1.0  # Default fallback
        end

        for t in time_periods
            # Generation function: gh = productivity * q
            if constraint.model_type == "linear"
                @constraint(model, gh[plant_idx, t] == productivity * q[plant_idx, t])
                num_constraints += 1
            end

            # Generation limits
            if u !== nothing
                @constraint(
                    model,
                    gh[plant_idx, t] >= plant.min_generation_mw * u[plant_idx, t]
                )
                @constraint(
                    model,
                    gh[plant_idx, t] <= plant.max_generation_mw * u[plant_idx, t]
                )
            else
                @constraint(model, gh[plant_idx, t] >= plant.min_generation_mw)
                @constraint(model, gh[plant_idx, t] <= plant.max_generation_mw)
            end
            num_constraints += 2

            # Outflow limits
            @constraint(
                model,
                plant.min_outflow_m3_per_s <= q[plant_idx, t] <= plant.max_outflow_m3_per_s
            )
            num_constraints += 1
        end
    end

    build_time = time() - start_time

    @info "Hydro generation constraints built successfully" num_constraints =
        num_constraints build_time = build_time

    return ConstraintBuildResult(;
        constraint_type = "HydroGenerationConstraint",
        num_constraints = num_constraints,
        build_time_seconds = build_time,
        success = true,
        message = "Built $num_constraints hydro generation constraints",
        warnings = warnings,
    )
end

# Export
export HydroGenerationConstraint, build!
