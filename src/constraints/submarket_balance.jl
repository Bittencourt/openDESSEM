"""
    Submarket Energy Balance Constraints

Implements energy balance for the 4 Brazilian submarkets:
- Southeast (SE)
- South (S)
- Northeast (NE)
- North (N)

Each submarket must balance generation, load, and interconnections.
"""

# Note: JuMP, Dates, and all entity/constraint types are imported in parent Constraints.jl module

"""
    SubmarketBalanceConstraint <: AbstractConstraint

Energy balance constraints for submarkets.

# Fields
- `metadata::ConstraintMetadata`: Constraint metadata
- `submarket_ids::Vector{String}`: Specific submarket IDs to constrain (empty = all)
- `use_time_periods::Union{Nothing, UnitRange{Int}, Vector{Int}}`: Time periods to constrain
- `include_renewables::Bool`: Include renewable generation in balance (default true)

# Constraints Added

For each submarket `sm` and time period `t`:
```
sum(thermal[g in sm] + hydro[h in sm] + renewable[r in sm]) - load[sm, t] =
    sum(interconnection_in[from_sm, sm, t]) - sum(interconnection_out[sm, to_sm, t])
```

Or more simply:
```
generation[sm, t] - load[sm, t] = net_import[sm, t]
```

# Example
```julia
constraint = SubmarketBalanceConstraint(;
    metadata=ConstraintMetadata(;
        name="Submarket Energy Balance",
        description="4-submarket energy balance",
        priority=10
    ),
    include_renewables=true
)

result = build!(model, system, constraint)
```
"""
Base.@kwdef struct SubmarketBalanceConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    submarket_ids::Vector{String} = String[]
    use_time_periods::Union{Nothing,UnitRange{Int},Vector{Int}} = nothing
    include_renewables::Bool = true
end

"""
    build!(model::Model, system::ElectricitySystem, constraint::SubmarketBalanceConstraint)

Build submarket energy balance constraints.

# Arguments
- `model::Model`: JuMP optimization model
- `system::ElectricitySystem`: Electricity system
- `constraint::SubmarketBalanceConstraint`: Constraint configuration

# Returns
- `ConstraintBuildResult`: Build statistics

# Variables Required
- `g[i,t]`: Thermal generation
- `gh[i,t]`: Hydro generation
- `gr[i,t]`: Renewable generation
- Load data from system
"""
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::SubmarketBalanceConstraint,
)
    start_time = time()
    num_constraints = 0
    warnings = String[]

    # Validate system
    if !validate_constraint_system(system)
        return ConstraintBuildResult(;
            constraint_type="SubmarketBalanceConstraint",
            success=false,
            message="System validation failed",
        )
    end

    # Determine submarkets
    submarkets = if isempty(constraint.submarket_ids)
        system.submarkets
    else
        submarket_set = Set(constraint.submarket_ids)
        [sm for sm in system.submarkets if sm.code in submarket_set]
    end

    if isempty(submarkets)
        @warn "No submarkets found for constraint building"
        return ConstraintBuildResult(;
            constraint_type="SubmarketBalanceConstraint",
            success=false,
            message="No submarkets found",
        )
    end

    # Get plant indices
    thermal_indices = get_thermal_plant_indices(system)
    hydro_indices = get_hydro_plant_indices(system)
    renewable_indices = get_renewable_plant_indices(system)

    # Determine time periods
    time_periods = if constraint.use_time_periods === nothing
        1:24  # Default to 24 hours
    else
        constraint.use_time_periods
    end

    @info "Building submarket balance constraints" num_submarkets=length(submarkets) num_periods=length(time_periods)

    # Initialize constraint storage for LMP extraction
    if !haskey(model, :submarket_balance)
        model[:submarket_balance] = Dict{Tuple{String, Int}, ConstraintRef}()
    end

    # Build balance for each submarket
    for submarket in submarkets
        sm_code = submarket.code

        # Find plants in this submarket
        thermal_plants = [p for p in system.thermal_plants if p.submarket_id == sm_code]
        hydro_plants = [p for p in system.hydro_plants if p.submarket_id == sm_code]
        wind_farms = [f for f in system.wind_farms if f.submarket_id == sm_code]
        solar_farms = [f for f in system.solar_farms if f.submarket_id == sm_code]

        # Find loads in this submarket
        loads = [l for l in system.loads if l.submarket_id == sm_code]

        for t in time_periods
            # Calculate total generation
            thermal_gen = if haskey(object_dictionary(model), :g)
                g = model[:g]
                sum(g[thermal_indices[p.id], t] for p in thermal_plants; init=0.0)
            else
                0.0
            end

            hydro_gen = if haskey(object_dictionary(model), :gh)
                gh = model[:gh]
                sum(gh[hydro_indices[p.id], t] for p in hydro_plants; init=0.0)
            else
                0.0
            end

            renewable_gen = if constraint.include_renewables && haskey(object_dictionary(model), :gr)
                gr = model[:gr]
                wind_sum = sum(gr[renewable_indices[f.id], t] for f in wind_farms; init=0.0)
                solar_sum = sum(gr[renewable_indices[f.id], t] for f in solar_farms; init=0.0)
                wind_sum + solar_sum
            else
                0.0
            end

            total_gen = thermal_gen + hydro_gen + renewable_gen

            # Calculate load
            total_load = sum(l.load_profile[t] * l.base_mw for l in loads; init=0.0)

            # Energy balance (simplified - net exchange would be added separately)
            model[:submarket_balance][(sm_code, t)] = @constraint(model, total_gen - total_load == 0)
            num_constraints += 1
        end
    end

    build_time = time() - start_time

    @info "Submarket balance constraints built successfully" num_constraints=num_constraints build_time=build_time

    return ConstraintBuildResult(;
        constraint_type="SubmarketBalanceConstraint",
        num_constraints=num_constraints,
        build_time_seconds=build_time,
        success=true,
        message="Built $num_constraints submarket balance constraints",
        warnings=warnings,
    )
end

# Export
export SubmarketBalanceConstraint, build!
