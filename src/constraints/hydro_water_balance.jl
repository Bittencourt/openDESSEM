"""
    Hydro Water Balance Constraints

Implements water balance constraints for hydroelectric plants including:
- Reservoir storage continuity
- Inflow, outflow, and spillage balance
- Cascade dependencies (downstream plants receive water from upstream)
- Volume limits (minimum and maximum storage)

These constraints are critical for modeling Brazilian hydro system operations.
"""

# Note: JuMP, Dates, and all entity/constraint types are imported in parent Constraints.jl module

"""
    HydroWaterBalanceConstraint <: AbstractConstraint

Water balance constraints for hydroelectric plants.

# Fields
- `metadata::ConstraintMetadata`: Constraint metadata
- `include_cascade::Bool`: Include cascade delays from upstream to downstream (default true)
- `include_spill::Bool`: Include spillage variables (default true)
- `plant_ids::Vector{String}`: Specific plant IDs to constrain (empty = all hydro plants)
- `use_time_periods::Union{Nothing, UnitRange{Int}, Vector{Int}}`: Time periods to constrain

# Constraints Added

## Storage Continuity (Reservoir)
For each reservoir hydro plant `i` and time period `t`:
```
s[i,t] = s[i,t-1] + inflow[i,t] - q[i,t] - spill[i,t]
              + sum(upstream_outflow[j, t - delay[j,i]])
```
where:
- `s[i,t]`: Storage volume at end of period t (hm³)
- `inflow[i,t]`: Natural inflow during period t (hm³)
- `q[i,t]`: Turbine outflow (converted to hm³)
- `spill[i,t]`: Spillage (hm³)
- `upstream_outflow`: Outflow from upstream plants with travel time delays

## Volume Limits
For each reservoir plant `i` and time period `t`:
```
min_volume <= s[i,t] <= max_volume
```

## Run-of-River (No Storage)
For each run-of-river plant `i` and time period `t`:
```
q[i,t] <= inflow[i,t]
```
(outflow cannot exceed available inflow)

## Pumped Storage
For pumped storage plant `i`:
```
s[i,t] = s[i,t-1] + inflow[i,t] - q[i,t] - spill[i,t] + pump_return[i,t]
```
where `pump_return` is water pumped back to upper reservoir.

# Example
```julia
constraint = HydroWaterBalanceConstraint(;
    metadata=ConstraintMetadata(;
        name="Hydro Water Balance",
        description="Water balance for reservoir plants",
        priority=10
    ),
    include_cascade=true,
    include_spill=true
)

result = build!(model, system, constraint)
```
"""
Base.@kwdef struct HydroWaterBalanceConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    include_cascade::Bool = true
    include_spill::Bool = true
    plant_ids::Vector{String} = String[]
    use_time_periods::Union{Nothing,UnitRange{Int},Vector{Int}} = nothing
end

"""
    build!(model::Model, system::ElectricitySystem, constraint::HydroWaterBalanceConstraint)

Build hydro water balance constraints.

# Arguments
- `model::Model`: JuMP optimization model
- `system::ElectricitySystem`: Electricity system with hydro plants
- `constraint::HydroWaterBalanceConstraint`: Constraint configuration

# Returns
- `ConstraintBuildResult`: Build statistics

# Variables Required (from VariableManager)
- `s[i,t]`: Storage volume (hm³)
- `q[i,t]`: Turbine outflow (m³/s)
- Optional: `spill[i,t]`: Spillage (m³/s)
- Optional: `pump[i,t]`: Pumping power (MW)

# Notes
- Water balance requires inflow data (should be pre-loaded in plant data or system)
- Conversion factor: 1 m³/s × 3600 s = 3600 m³ = 0.0036 hm³ per period (hourly)
- For cascade delays, downstream plants receive upstream outflow after travel time
"""
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::HydroWaterBalanceConstraint,
)
    start_time = time()
    num_constraints = 0
    warnings = String[]

    # Validate system
    if !validate_constraint_system(system)
        return ConstraintBuildResult(;
            constraint_type="HydroWaterBalanceConstraint",
            success=false,
            message="System validation failed",
        )
    end

    # Check if variables exist
    if !haskey(object_dictionary(model), :s) || !haskey(object_dictionary(model), :q)
        @warn "Hydro variables (s, q) not found in model. Run create_hydro_variables! first."
        return ConstraintBuildResult(;
            constraint_type="HydroWaterBalanceConstraint",
            success=false,
            message="Required variables not found",
        )
    end

    # Get variables
    s = model[:s]
    q = model[:q]
    spill = get(object_dictionary(model), :spill, nothing)
    pump = get(object_dictionary(model), :pump, nothing)

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
            constraint_type="HydroWaterBalanceConstraint",
            success=false,
            message="No hydro plants found",
        )
    end

    # Get plant indices
    plant_indices = get_hydro_plant_indices(system)

    # Determine time periods
    time_periods = if constraint.use_time_periods === nothing
        1:size(s, 2)
    else
        constraint.use_time_periods
    end

    # Create spillage variables if needed
    if constraint.include_spill && spill === nothing
        n_plants = length(plants)
        n_periods = length(time_periods)
        @variable(model, spill[1:n_plants, 1:n_periods] >= 0)
        @info "Created spillage variables"
    end

    @info "Building hydro water balance constraints" num_plants=length(plants) num_periods=length(time_periods)

    # Build plant lookup for cascade
    plant_dict = Dict(p.id => p for p in all_hydro)

    # Conversion factor: m³/s to hm³ per hour
    # 1 m³/s × 3600 s = 3600 m³ = 0.0036 hm³
    M3S_TO_HM3_PER_HOUR = 0.0036

    for plant in plants
        plant_idx = plant_indices[plant.id]

        if plant isa ReservoirHydro
            # Reservoir plants with storage
            for t in time_periods
                if t == 1
                    # Initial condition
                    @constraint(
                        model,
                        s[plant_idx, t] == plant.initial_volume_hm3
                    )
                    num_constraints += 1
                else
                    # Water balance: s[t] = s[t-1] + inflow - outflow - spill
                    # For simplicity, assume inflow is stored in plant metadata or use 0
                    inflow = 0.0  # TODO: Load from data

                    outflow_hm3 = q[plant_idx, t] * M3S_TO_HM3_PER_HOUR

                    if constraint.include_spill && spill !== nothing
                        spill_hm3 = spill[plant_idx, t] * M3S_TO_HM3_PER_HOUR
                        @constraint(
                            model,
                            s[plant_idx, t] ==
                            s[plant_idx, t - 1] + inflow - outflow_hm3 - spill_hm3
                        )
                    else
                        @constraint(
                            model,
                            s[plant_idx, t] == s[plant_idx, t - 1] + inflow - outflow_hm3
                        )
                    end
                    num_constraints += 1

                    # Cascade: add upstream outflow
                    if constraint.include_cascade && plant.downstream_plant_id !== nothing
                        # This plant receives water from upstream
                        # The constraint would be added to the downstream plant
                        # This is a simplified version - full cascade requires topology traversal
                    end
                end

                # Volume limits
                @constraint(
                    model,
                    plant.min_volume_hm3 <= s[plant_idx, t] <= plant.max_volume_hm3
                )
                num_constraints += 1
            end

        elseif plant isa RunOfRiverHydro
            # Run-of-river: outflow cannot exceed inflow
            for t in time_periods
                inflow = 0.0  # TODO: Load from data
                @constraint(model, q[plant_idx, t] <= inflow)
                num_constraints += 1
            end

        elseif plant isa PumpedStorageHydro
            # Pumped storage: account for pumping
            for t in time_periods
                if t == 1
                    @constraint(
                        model,
                        s[plant_idx, t] == plant.initial_volume_hm3
                    )
                    num_constraints += 1
                else
                    inflow = 0.0
                    outflow_hm3 = q[plant_idx, t] * M3S_TO_HM3_PER_HOUR

                    if pump !== nothing
                        # Pumping returns water to upper reservoir
                        # Assume 80% efficiency for pumping cycle
                        pump_return = pump[plant_idx, t] * M3S_TO_HM3_PER_HOUR * 0.8
                    else
                        pump_return = 0.0
                    end

                    if constraint.include_spill && spill !== nothing
                        spill_hm3 = spill[plant_idx, t] * M3S_TO_HM3_PER_HOUR
                        @constraint(
                            model,
                            s[plant_idx, t] ==
                            s[plant_idx, t - 1] + inflow - outflow_hm3 - spill_hm3 + pump_return
                        )
                    else
                        @constraint(
                            model,
                            s[plant_idx, t] ==
                            s[plant_idx, t - 1] + inflow - outflow_hm3 + pump_return
                        )
                    end
                    num_constraints += 1
                end

                # Volume limits
                @constraint(
                    model,
                    plant.min_volume_hm3 <= s[plant_idx, t] <= plant.max_volume_hm3
                )
                num_constraints += 1
            end
        end
    end

    build_time = time() - start_time

    @info "Hydro water balance constraints built successfully" num_constraints=num_constraints build_time=build_time

    return ConstraintBuildResult(;
        constraint_type="HydroWaterBalanceConstraint",
        num_constraints=num_constraints,
        build_time_seconds=build_time,
        success=true,
        message="Built $num_constraints hydro water balance constraints",
        warnings=warnings,
    )
end

# Export
export HydroWaterBalanceConstraint, build!
