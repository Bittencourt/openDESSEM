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

# Import cascade topology utilities
using ..CascadeTopologyUtils: build_cascade_topology, CascadeTopology, get_upstream_plants

# Import inflow data types
using ..DessemLoader: InflowData, get_inflow

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

# With inflow data (recommended):
result = build!(model, system, constraint;
    inflow_data=inflow_data,
    hydro_plant_numbers=hydro_plant_numbers)

# Without inflow data (backward compatible, uses zero inflows):
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
    get_inflow_for_period(inflow_data, hydro_plant_numbers, plant_id, t) -> Float64

Helper function to look up inflow for a specific plant and time period.

# Arguments
- `inflow_data::Union{InflowData,Nothing}`: Inflow data container (can be nothing)
- `hydro_plant_numbers::Union{Dict{String,Int},Nothing}`: Mapping from plant_id to plant_number
- `plant_id::String`: The plant ID to look up
- `t::Int`: Time period (hour, 1-indexed)

# Returns
- `Float64`: Hourly inflow in m³/s, or 0.0 if data not available

# Notes
- Returns 0.0 if inflow_data is nothing (backward compatibility)
- Returns 0.0 if plant_id not found in hydro_plant_numbers mapping
- Returns 0.0 if time period is out of range
"""
function get_inflow_for_period(
    inflow_data::Union{InflowData,Nothing},
    hydro_plant_numbers::Union{Dict{String,Int},Nothing},
    plant_id::String,
    t::Int,
)::Float64
    # Return 0.0 if no inflow data provided
    if inflow_data === nothing || hydro_plant_numbers === nothing
        return 0.0
    end

    # Look up plant number from plant_id
    plant_num = get(hydro_plant_numbers, plant_id, nothing)
    if plant_num === nothing
        return 0.0
    end

    # Get inflow using the get_inflow helper (handles bounds checking)
    return get_inflow(inflow_data, plant_num, t)
end

"""
    build!(model::Model, system::ElectricitySystem, constraint::HydroWaterBalanceConstraint;
           inflow_data=nothing, hydro_plant_numbers=nothing)

Build hydro water balance constraints.

# Arguments
- `model::Model`: JuMP optimization model
- `system::ElectricitySystem`: Electricity system with hydro plants
- `constraint::HydroWaterBalanceConstraint`: Constraint configuration
- `inflow_data::Union{InflowData,Nothing}`: Optional inflow time series data (default: nothing)
- `hydro_plant_numbers::Union{Dict{String,Int},Nothing}`: Optional mapping from plant_id to plant_number (default: nothing)

# Returns
- `ConstraintBuildResult`: Build statistics

# Variables Required (from VariableManager)
- `s[i,t]`: Storage volume (hm³)
- `q[i,t]`: Turbine outflow (m³/s)
- Optional: `spill[i,t]`: Spillage (m³/s)
- Optional: `pump[i,t]`: Pumping power (MW)

# Notes
- If inflow_data is not provided, natural inflows default to 0.0
- Conversion factor: 1 m³/s × 3600 s = 3600 m³ = 0.0036 hm³ per period (hourly)
- For cascade delays, downstream plants receive upstream outflow after travel time
- Upstream outflows include both turbine outflow (q) and spillage (spill)
"""
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::HydroWaterBalanceConstraint;
    inflow_data::Union{InflowData,Nothing} = nothing,
    hydro_plant_numbers::Union{Dict{String,Int},Nothing} = nothing,
)
    start_time = time()
    num_constraints = 0
    warnings = String[]

    # Validate system
    if !validate_constraint_system(system)
        return ConstraintBuildResult(;
            constraint_type = "HydroWaterBalanceConstraint",
            success = false,
            message = "System validation failed",
        )
    end

    # Check if variables exist
    if !haskey(object_dictionary(model), :s) || !haskey(object_dictionary(model), :q)
        @warn "Hydro variables (s, q) not found in model. Run create_hydro_variables! first."
        return ConstraintBuildResult(;
            constraint_type = "HydroWaterBalanceConstraint",
            success = false,
            message = "Required variables not found",
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
            constraint_type = "HydroWaterBalanceConstraint",
            success = false,
            message = "No hydro plants found",
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

    @info "Building hydro water balance constraints" num_plants = length(plants) num_periods =
        length(time_periods)

    # Build plant lookup for cascade
    plant_dict = Dict(p.id => p for p in all_hydro)

    # Build cascade topology for upstream flow tracking
    cascade_topology = build_cascade_topology(all_hydro)

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
                    @constraint(model, s[plant_idx, t] == plant.initial_volume_hm3)
                    num_constraints += 1
                else
                    # Get natural inflow from loaded data
                    inflow_m3s =
                        get_inflow_for_period(inflow_data, hydro_plant_numbers, plant.id, t)
                    inflow_hm3 = inflow_m3s * M3S_TO_HM3_PER_HOUR

                    # Build balance expression incrementally
                    # s[t] = s[t-1] + inflow - outflow - spill + upstream_outflows
                    balance_expr = AffExpr(0.0)
                    # Add previous period storage
                    add_to_expression!(balance_expr, 1.0, s[plant_idx, t-1])
                    # Add natural inflow (constant)
                    add_to_expression!(balance_expr, inflow_hm3)

                    # Add upstream outflows with cascade delays
                    if constraint.include_cascade
                        upstream_plants = get(
                            cascade_topology.upstream_map,
                            plant.id,
                            Tuple{String,Float64}[],
                        )
                        for (upstream_id, delay_hours) in upstream_plants
                            t_upstream = t - round(Int, delay_hours)
                            if t_upstream >= 1
                                upstream_idx = plant_indices[upstream_id]
                                # Add upstream turbine outflow
                                add_to_expression!(
                                    balance_expr,
                                    M3S_TO_HM3_PER_HOUR,
                                    q[upstream_idx, t_upstream],
                                )
                                # Add upstream spillage if available
                                if constraint.include_spill && spill !== nothing
                                    add_to_expression!(
                                        balance_expr,
                                        M3S_TO_HM3_PER_HOUR,
                                        spill[upstream_idx, t_upstream],
                                    )
                                end
                            end
                        end
                    end

                    # Subtract local outflow
                    add_to_expression!(balance_expr, -M3S_TO_HM3_PER_HOUR, q[plant_idx, t])

                    # Subtract spillage if included
                    if constraint.include_spill && spill !== nothing
                        add_to_expression!(
                            balance_expr,
                            -M3S_TO_HM3_PER_HOUR,
                            spill[plant_idx, t],
                        )
                    end

                    # Build the constraint: s[t] = balance_expr
                    @constraint(model, s[plant_idx, t] == balance_expr)
                    num_constraints += 1
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
                # Get natural inflow from loaded data
                inflow_m3s =
                    get_inflow_for_period(inflow_data, hydro_plant_numbers, plant.id, t)
                @constraint(model, q[plant_idx, t] <= inflow_m3s)
                num_constraints += 1
            end

        elseif plant isa PumpedStorageHydro
            # Pumped storage: account for pumping
            for t in time_periods
                if t == 1
                    @constraint(model, s[plant_idx, t] == plant.initial_volume_hm3)
                    num_constraints += 1
                else
                    # Get natural inflow from loaded data
                    inflow_m3s =
                        get_inflow_for_period(inflow_data, hydro_plant_numbers, plant.id, t)
                    inflow_hm3 = inflow_m3s * M3S_TO_HM3_PER_HOUR

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
                            s[plant_idx, t-1] + inflow_hm3 - outflow_hm3 - spill_hm3 +
                            pump_return
                        )
                    else
                        @constraint(
                            model,
                            s[plant_idx, t] ==
                            s[plant_idx, t-1] + inflow_hm3 - outflow_hm3 + pump_return
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

    @info "Hydro water balance constraints built successfully" num_constraints =
        num_constraints build_time = build_time

    return ConstraintBuildResult(;
        constraint_type = "HydroWaterBalanceConstraint",
        num_constraints = num_constraints,
        build_time_seconds = build_time,
        success = true,
        message = "Built $num_constraints hydro water balance constraints",
        warnings = warnings,
    )
end

# Export
export HydroWaterBalanceConstraint, build!
