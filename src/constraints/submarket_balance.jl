"""
    Submarket Energy Balance Constraints

Implements energy balance for the 4 Brazilian submarkets:
- Southeast (SE)
- South (S)
- Northeast (NE)
- North (N)

Each submarket must balance generation, load, deficit, and interconnections.
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
- `include_deficit::Bool`: Add deficit slack variable to generation side (default true)
- `include_interconnections::Bool`: Add interconnection flow terms (default true)

# Constraints Added

For each submarket `sm` and time period `t`:
```
gen(sm,t) + deficit(sm,t) + sum(imports) - sum(exports*(1-loss)) - load(sm,t) = 0
```

Where:
- `gen(sm,t)` = thermal + hydro + renewable generation in submarket
- `deficit(sm,t)` = energy deficit variable (from create_deficit_variables!)
- imports = ic_flow[ic,t] for interconnections where to_submarket == sm
- exports = ic_flow[ic,t] * (1 - loss/100) for interconnections where from_submarket == sm
- Positive flow = from → to direction

# Example
```julia
constraint = SubmarketBalanceConstraint(;
    metadata=ConstraintMetadata(;
        name="Submarket Energy Balance",
        description="4-submarket energy balance with deficit and interconnections",
        priority=10
    ),
    include_renewables=true,
    include_deficit=true,
    include_interconnections=true
)

result = build!(model, system, constraint)
```
"""
Base.@kwdef struct SubmarketBalanceConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    submarket_ids::Vector{String} = String[]
    use_time_periods::Union{Nothing,UnitRange{Int},Vector{Int}} = nothing
    include_renewables::Bool = true
    include_deficit::Bool = true
    include_interconnections::Bool = true
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
- `deficit[s,t]`: Energy deficit per submarket (if include_deficit=true)
- Load data from system

# Variables Created
- `ic_flow[ic,t]`: Interconnection flow variables (if include_interconnections=true)
"""
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::SubmarketBalanceConstraint,
)
    start_time = time()
    num_constraints = 0
    num_variables = 0
    warnings = String[]

    # Validate system
    if !validate_constraint_system(system)
        return ConstraintBuildResult(;
            constraint_type = "SubmarketBalanceConstraint",
            success = false,
            message = "System validation failed",
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
            constraint_type = "SubmarketBalanceConstraint",
            success = false,
            message = "No submarkets found",
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

    @info "Building submarket balance constraints" num_submarkets = length(submarkets) num_periods =
        length(time_periods) include_deficit = constraint.include_deficit include_interconnections =
        constraint.include_interconnections

    # Initialize constraint storage for LMP extraction
    if !haskey(model, :submarket_balance)
        model[:submarket_balance] = Dict{Tuple{String,Int},ConstraintRef}()
    end

    # === Create interconnection flow variables if needed ===
    interconnections = system.interconnections
    sm_codes = Set(sm.code for sm in submarkets)

    # Filter to interconnections relevant to our submarkets
    relevant_ics = if constraint.include_interconnections && !isempty(interconnections)
        [
            ic for ic in interconnections if
            ic.from_submarket_id in sm_codes || ic.to_submarket_id in sm_codes
        ]
    else
        Interconnection[]
    end

    if !isempty(relevant_ics) && constraint.include_interconnections
        if !haskey(object_dictionary(model), :ic_flow)
            n_ics = length(relevant_ics)
            n_periods = length(time_periods)
            @variable(
                model,
                ic_flow[ic_idx = 1:n_ics, t = 1:n_periods],
                lower_bound = -relevant_ics[ic_idx].capacity_mw,
                upper_bound = relevant_ics[ic_idx].capacity_mw
            )
            num_variables = n_ics * n_periods
            @info "Created interconnection flow variables" n_interconnections = n_ics n_periods =
                n_periods
        end
    end

    # === Get deficit variable info ===
    submarket_indices = get_submarket_indices(system)

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
                sum(g[thermal_indices[p.id], t] for p in thermal_plants; init = 0.0)
            else
                0.0
            end

            hydro_gen = if haskey(object_dictionary(model), :gh)
                gh = model[:gh]
                sum(gh[hydro_indices[p.id], t] for p in hydro_plants; init = 0.0)
            else
                0.0
            end

            renewable_gen =
                if constraint.include_renewables && haskey(object_dictionary(model), :gr)
                    gr = model[:gr]
                    wind_sum =
                        sum(gr[renewable_indices[f.id], t] for f in wind_farms; init = 0.0)
                    solar_sum =
                        sum(gr[renewable_indices[f.id], t] for f in solar_farms; init = 0.0)
                    wind_sum + solar_sum
                else
                    0.0
                end

            total_gen = thermal_gen + hydro_gen + renewable_gen

            # Add deficit term if enabled
            deficit_term =
                if constraint.include_deficit &&
                   haskey(object_dictionary(model), :deficit) &&
                   haskey(submarket_indices, sm_code)
                    deficit = model[:deficit]
                    sm_idx = submarket_indices[sm_code]
                    deficit[sm_idx, t]
                else
                    0.0
                end

            # Add interconnection flow terms if enabled
            import_term = 0.0  # power flowing INTO this submarket
            export_term = 0.0  # power flowing OUT of this submarket (net of losses)

            if constraint.include_interconnections &&
               !isempty(relevant_ics) &&
               haskey(object_dictionary(model), :ic_flow)
                ic_flow = model[:ic_flow]
                for (ic_idx, ic) in enumerate(relevant_ics)
                    if ic.to_submarket_id == sm_code
                        # This submarket is the receiver: import = flow (positive = from→to)
                        import_term += ic_flow[ic_idx, t]
                    end
                    if ic.from_submarket_id == sm_code
                        # This submarket is the sender: export = flow * (1 - loss)
                        loss_factor = 1.0 - ic.loss_percent / 100.0
                        export_term += ic_flow[ic_idx, t] * loss_factor
                    end
                end
            end

            # Calculate load
            total_load = sum(l.load_profile[t] * l.base_mw for l in loads; init = 0.0)

            # Energy balance:
            # gen + deficit + imports - exports - load == 0
            model[:submarket_balance][(sm_code, t)] = @constraint(
                model,
                total_gen + deficit_term + import_term - export_term - total_load == 0
            )
            num_constraints += 1
        end
    end

    build_time = time() - start_time

    @info "Submarket balance constraints built successfully" num_constraints =
        num_constraints num_variables = num_variables build_time = build_time

    return ConstraintBuildResult(;
        constraint_type = "SubmarketBalanceConstraint",
        num_constraints = num_constraints,
        num_variables = num_variables,
        build_time_seconds = build_time,
        success = true,
        message = "Built $num_constraints submarket balance constraints",
        warnings = warnings,
    )
end

# Export
export SubmarketBalanceConstraint, build!
