"""
    Production Cost Objective

Standard production cost minimization objective for hydrothermal scheduling.
Minimizes total operating cost across all thermal and hydro plants.
"""

"""
    ProductionCostObjective <: AbstractObjective

Standard production cost minimization objective for hydrothermal scheduling.

Minimizes total operating cost across all thermal and hydro plants:
- Thermal fuel costs (generation-dependent)
- Thermal startup costs (per-startup event)
- Thermal shutdown costs (per-shutdown event)
- Hydro water value (opportunity cost of water usage)
- Renewable curtailment costs (optional)
- Load shedding penalty costs (optional)
- Deficit penalty costs (optional)

# Fields
- `metadata::ObjectiveMetadata`: Objective metadata
- `thermal_fuel_cost::Bool`: Include thermal fuel costs (default true)
- `thermal_startup_cost::Bool`: Include thermal startup costs (default true)
- `thermal_shutdown_cost::Bool`: Include thermal shutdown costs (default true)
- `hydro_water_value::Bool`: Include hydro water value (default true)
- `renewable_curtailment_cost::Bool`: Include renewable curtailment costs (default false)
- `curtailment_penalty::Float64`: Penalty per MW of curtailed renewable (default 0.0)
- `load_shedding_cost::Bool`: Include load shedding penalty (default false)
- `shedding_penalty::Float64`: Penalty per MW of shed load (default 5000.0)
- `deficit_cost::Bool`: Include deficit penalty (default false)
- `deficit_penalty::Float64`: Penalty per MW of energy deficit (default 10000.0)
- `time_varying_fuel_costs::Dict{String, Vector{Float64}}`: Time-varying fuel costs by plant ID
- `plant_filter::Vector{String}`: Specific plant IDs to include (empty = all)

# Example
```julia
objective = ProductionCostObjective(;
    metadata=ObjectiveMetadata(;
        name="Production Cost",
        description="Minimize total system operating cost"
    ),
    thermal_fuel_cost=true,
    thermal_startup_cost=true,
    thermal_shutdown_cost=true,
    hydro_water_value=true,
    renewable_curtailment_cost=true,
    curtailment_penalty=10.0,
    load_shedding_cost=true,
    shedding_penalty=5000.0
)

result = build!(model, system, objective)
```
"""
Base.@kwdef struct ProductionCostObjective <: AbstractObjective
    metadata::ObjectiveMetadata
    thermal_fuel_cost::Bool = true
    thermal_startup_cost::Bool = true
    thermal_shutdown_cost::Bool = true
    hydro_water_value::Bool = true
    renewable_curtailment_cost::Bool = false
    curtailment_penalty::Float64 = 0.0
    load_shedding_cost::Bool = false
    shedding_penalty::Float64 = 5000.0
    deficit_cost::Bool = false
    deficit_penalty::Float64 = 10000.0
    time_varying_fuel_costs::Dict{String,Vector{Float64}} = Dict{String,Vector{Float64}}()
    plant_filter::Vector{String} = String[]
end

"""
    get_fuel_cost(plant::ConventionalThermal, period::Int, time_varying_costs::Dict) -> Float64

Get the fuel cost for a plant at a specific period.

Returns time-varying cost if available, otherwise returns base cost.

# Arguments
- `plant::ConventionalThermal`: Thermal plant
- `period::Int`: Time period (1-indexed)
- `time_varying_costs::Dict`: Dictionary of plant_id -> cost vector

# Returns
- `Float64`: Fuel cost in R\$/MWh for the period

# Example
```julia
cost = get_fuel_cost(plant, 5, time_varying_costs)
```
"""
function get_fuel_cost(
    plant::ConventionalThermal,
    period::Int,
    time_varying_costs::Dict{String,Vector{Float64}},
)::Float64
    if haskey(time_varying_costs, plant.id) && period <= length(time_varying_costs[plant.id])
        return time_varying_costs[plant.id][period]
    end
    return plant.fuel_cost_rsj_per_mwh
end

"""
    build!(model::Model, system::ElectricitySystem, objective::ProductionCostObjective)

Build the production cost minimization objective.

# Arguments
- `model::Model`: JuMP optimization model with variables already created
- `system::ElectricitySystem`: Complete electricity system
- `objective::ProductionCostObjective`: Objective configuration

# Variables Required (from VariableManager)
- `g[i,t]`: Thermal generation (MW)
- `v[i,t]`: Thermal startup indicator
- `w[i,t]`: Thermal shutdown indicator
- `s[i,t]`: Hydro storage volume (hm³)
- `curtail[i,t]`: Renewable curtailment (MW)
- `shed[l,t]`: Load shedding (MW) - optional variable
- `deficit[s,t]`: Energy deficit (MW) - optional variable

# Returns
- `ObjectiveBuildResult`: Build statistics with cost component breakdown

# Cost Components Calculated
1. **Thermal Fuel Cost**: `sum(plant.fuel_cost * g[i,t] for all plants, periods)`
2. **Thermal Startup Cost**: `sum(plant.startup_cost * v[i,t] for all plants, periods)`
3. **Thermal Shutdown Cost**: `sum(plant.shutdown_cost * w[i,t] for all plants, periods)`
4. **Hydro Water Value**: `sum(plant.water_value * s[i,t] for all plants, periods)`
5. **Curtailment Cost**: `sum(penalty * curtail[i,t] for all renewables, periods)`
6. **Load Shedding Cost**: `sum(penalty * shed[t] for all periods)`
7. **Deficit Cost**: `sum(penalty * deficit[submarket,t] for all submarkets, periods)`

# Example
```julia
result = build!(model, system, objective)
println("Thermal fuel cost: R\$ ", result.cost_component_summary["thermal_fuel"])
println("Total objective: R\$ ", result.message)
```
"""
function build!(
    model::Model,
    system::ElectricitySystem,
    objective::ProductionCostObjective,
)
    start_time = time()
    warnings = String[]

    # Validate system
    if !validate_objective_system(system)
        return ObjectiveBuildResult(;
            objective_type="ProductionCostObjective",
            build_time_seconds=time() - start_time,
            success=false,
            message="System validation failed: no generation sources",
            cost_component_summary=Dict{String,Float64}(),
            warnings=warnings
        )
    end

    # Determine time periods from model variables
    time_periods = if haskey(model, :g) && !isempty(model[:g])
        # Get time periods from thermal generation variable size
        # g is indexed as [plant_idx, time_idx]
        n_periods = size(model[:g], 2)
        1:n_periods
    elseif haskey(model, :gh) && !isempty(model[:gh])
        # Fallback to hydro generation variable
        n_periods = size(model[:gh], 2)
        1:n_periods
    else
        @warn "Could not determine time periods from model, assuming 1:24"
        1:24
    end

    # Get plant indices (compute from system)
    thermal_indices = get_thermal_plant_indices(system)
    hydro_indices = get_hydro_plant_indices(system)
    renewable_indices = get_renewable_plant_indices(system)

    # Build objective expression
    cost_components = Dict{String,Float64}()
    objective_expr = AffExpr(0.0)

    # Filter plants if plant_filter is specified
    thermal_plants = if isempty(objective.plant_filter)
        system.thermal_plants
    else
        filter(p -> p.id in objective.plant_filter, system.thermal_plants)
    end

    hydro_plants = if isempty(objective.plant_filter)
        system.hydro_plants
    else
        filter(p -> p.id in objective.plant_filter, system.hydro_plants)
    end

    # === Thermal Fuel Cost ===
    if objective.thermal_fuel_cost && !isempty(thermal_plants)
        if !haskey(model, :g)
            push!(warnings, "Thermal generation variable :g not found in model")
        else
            g = model[:g]
            fuel_cost_expr = AffExpr(0.0)
            total_fuel_cost = 0.0

            for plant in thermal_plants
                if haskey(thermal_indices, plant.id)
                    idx = thermal_indices[plant.id]
                    for t in time_periods
                        cost = get_fuel_cost(plant, t, objective.time_varying_fuel_costs)
                        fuel_cost_expr += cost * g[idx, t]
                        # Calculate expected cost for summary (coefficient only)
                        total_fuel_cost += cost * plant.max_generation_mw
                    end
                end
            end

            objective_expr += fuel_cost_expr
            cost_components["thermal_fuel"] = total_fuel_cost
        end
    end

    # === Thermal Startup Cost ===
    if objective.thermal_startup_cost && !isempty(thermal_plants)
        if !haskey(model, :v)
            push!(warnings, "Thermal startup variable :v not found in model")
        else
            v = model[:v]
            startup_cost_expr = AffExpr(0.0)
            total_startup_cost = 0.0

            for plant in thermal_plants
                if haskey(thermal_indices, plant.id)
                    idx = thermal_indices[plant.id]
                    for t in time_periods
                        startup_cost_expr += plant.startup_cost_rs * v[idx, t]
                        total_startup_cost += plant.startup_cost_rs
                    end
                end
            end

            objective_expr += startup_cost_expr
            cost_components["thermal_startup"] = total_startup_cost
        end
    end

    # === Thermal Shutdown Cost ===
    if objective.thermal_shutdown_cost && !isempty(thermal_plants)
        if !haskey(model, :w)
            push!(warnings, "Thermal shutdown variable :w not found in model")
        else
            w = model[:w]
            shutdown_cost_expr = AffExpr(0.0)
            total_shutdown_cost = 0.0

            for plant in thermal_plants
                if haskey(thermal_indices, plant.id)
                    idx = thermal_indices[plant.id]
                    for t in time_periods
                        shutdown_cost_expr += plant.shutdown_cost_rs * w[idx, t]
                        total_shutdown_cost += plant.shutdown_cost_rs
                    end
                end
            end

            objective_expr += shutdown_cost_expr
            cost_components["thermal_shutdown"] = total_shutdown_cost
        end
    end

    # === Hydro Water Value ===
    if objective.hydro_water_value && !isempty(hydro_plants)
        if !haskey(model, :s)
            push!(warnings, "Hydro storage variable :s not found in model")
        else
            s = model[:s]
            water_value_expr = AffExpr(0.0)
            total_water_value = 0.0

            for plant in hydro_plants
                if haskey(hydro_indices, plant.id)
                    idx = hydro_indices[plant.id]
                    for t in time_periods
                        water_value_expr += plant.water_value_rs_per_hm3 * s[idx, t]
                        total_water_value += plant.water_value_rs_per_hm3 * plant.initial_volume_hm3
                    end
                end
            end

            objective_expr += water_value_expr
            cost_components["hydro_water_value"] = total_water_value
        end
    end

    # === Renewable Curtailment Cost ===
    if objective.renewable_curtailment_cost && !isempty(system.wind_farms)
        if !haskey(model, :curtail)
            push!(warnings, "Renewable curtailment variable :curtail not found in model")
        else
            curtail = model[:curtail]
            curtail_cost_expr = AffExpr(0.0)
            total_curtail_cost = 0.0

            for farm in system.wind_farms
                if haskey(renewable_indices, farm.id)
                    idx = renewable_indices[farm.id]
                    for t in time_periods
                        curtail_cost_expr += objective.curtailment_penalty * curtail[idx, t]
                        total_curtail_cost += objective.curtailment_penalty * farm.installed_capacity_mw
                    end
                end
            end

            if !isempty(system.solar_farms)
                for farm in system.solar_farms
                    if haskey(renewable_indices, farm.id)
                        idx = renewable_indices[farm.id]
                        for t in time_periods
                            curtail_cost_expr += objective.curtailment_penalty * curtail[idx, t]
                            total_curtail_cost += objective.curtailment_penalty * farm.installed_capacity_mw
                        end
                    end
                end
            end

            objective_expr += curtail_cost_expr
            cost_components["renewable_curtailment"] = total_curtail_cost
        end
    end

    # === Load Shedding Cost ===
    if objective.load_shedding_cost
        if !haskey(model, :shed)
            push!(warnings, "Load shedding variable :shed not found in model (optional)")
        else
            shed = model[:shed]
            # Assuming shed is indexed by (submarket_id, t) or similar
            # This is a simplified placeholder
            shed_cost_expr = AffExpr(0.0)
            for load in system.loads
                for t in time_periods
                    if haskey(shed, (load.submarket_id, t))
                        shed_cost_expr += objective.shedding_penalty * shed[(load.submarket_id, t)]
                    end
                end
            end
            objective_expr += shed_cost_expr
            cost_components["load_shedding"] = objective.shedding_penalty * length(time_periods)
        end
    end

    # === Deficit Cost ===
    if objective.deficit_cost
        if !haskey(model, :deficit)
            push!(warnings, "Deficit variable :deficit not found in model (optional)")
        else
            deficit = model[:deficit]
            # Assuming deficit is indexed by (submarket_id, t)
            deficit_cost_expr = AffExpr(0.0)
            for submarket in system.submarkets
                for t in time_periods
                    if haskey(deficit, (submarket.code, t))
                        deficit_cost_expr += objective.deficit_penalty * deficit[(submarket.code, t)]
                    end
                end
            end
            objective_expr += deficit_cost_expr
            cost_components["deficit"] = objective.deficit_penalty * length(time_periods)
        end
    end

    # Check if objective expression is empty
    if isempty(cost_components)
        return ObjectiveBuildResult(;
            objective_type="ProductionCostObjective",
            build_time_seconds=time() - start_time,
            success=false,
            message="No valid cost components found - check variable availability",
            cost_component_summary=Dict{String,Float64}(),
            warnings=warnings
        )
    end

    # Add objective to model
    if objective.metadata.objective_sense == MOI.MAX_SENSE
        @objective(model, Max, objective_expr)
    else
        @objective(model, Min, objective_expr)
    end

    build_time = time() - start_time

    return ObjectiveBuildResult(;
        objective_type="ProductionCostObjective",
        build_time_seconds=build_time,
        success=true,
        message="Built production cost objective with $(length(cost_components)) components",
        cost_component_summary=cost_components,
        warnings=warnings
    )
end

"""
    calculate_cost_breakdown(
        model::Model,
        system::ElectricitySystem,
        objective::ProductionCostObjective,
        time_periods::UnitRange{Int}
    ) -> Dict{String, Float64}

Calculate the breakdown of cost components from a solved model.

Used for post-solution analysis to understand what contributes to total cost.

# Arguments
- `model::Model`: Solved JuMP model
- `system::ElectricitySystem`: Electricity system
- `objective::ProductionCostObjective`: Objective configuration
- `time_periods::UnitRange{Int}`: Time periods to analyze

# Returns
- `Dict{String, Float64}`: Cost breakdown by component (in R\$)

# Example
```julia
breakdown = calculate_cost_breakdown(model, system, objective, 1:24)
println("Fuel cost: R\$ ", breakdown["thermal_fuel"])
println("Startup cost: R\$ ", breakdown["thermal_startup"])
```
"""
function calculate_cost_breakdown(
    model::Model,
    system::ElectricitySystem,
    objective::ProductionCostObjective,
    time_periods::UnitRange{Int},
)::Dict{String,Float64}
    breakdown = Dict{String,Float64}()

    # Get plant indices (compute from system)
    thermal_indices = get_thermal_plant_indices(system)
    hydro_indices = get_hydro_plant_indices(system)
    renewable_indices = get_renewable_plant_indices(system)

    # Calculate thermal fuel cost from solution
    if objective.thermal_fuel_cost && haskey(model, :g)
        g = model[:g]
        fuel_cost = 0.0
        for plant in system.thermal_plants
            if haskey(thermal_indices, plant.id)
                idx = thermal_indices[plant.id]
                for t in time_periods
                    cost = get_fuel_cost(plant, t, objective.time_varying_fuel_costs)
                    fuel_cost += cost * value(g[idx, t])
                end
            end
        end
        breakdown["thermal_fuel"] = fuel_cost
    end

    # Calculate thermal startup cost from solution
    if objective.thermal_startup_cost && haskey(model, :v)
        v = model[:v]
        startup_cost = 0.0
        for plant in system.thermal_plants
            if haskey(thermal_indices, plant.id)
                idx = thermal_indices[plant.id]
                for t in time_periods
                    startup_cost += plant.startup_cost_rs * value(v[idx, t])
                end
            end
        end
        breakdown["thermal_startup"] = startup_cost
    end

    # Calculate thermal shutdown cost from solution
    if objective.thermal_shutdown_cost && haskey(model, :w)
        w = model[:w]
        shutdown_cost = 0.0
        for plant in system.thermal_plants
            if haskey(thermal_indices, plant.id)
                idx = thermal_indices[plant.id]
                for t in time_periods
                    shutdown_cost += plant.shutdown_cost_rs * value(w[idx, t])
                end
            end
        end
        breakdown["thermal_shutdown"] = shutdown_cost
    end

    # Calculate hydro water value from solution
    if objective.hydro_water_value && haskey(model, :s)
        s = model[:s]
        water_value = 0.0
        for plant in system.hydro_plants
            if haskey(hydro_indices, plant.id)
                idx = hydro_indices[plant.id]
                for t in time_periods
                    water_value += plant.water_value_rs_per_hm3 * value(s[idx, t])
                end
            end
        end
        breakdown["hydro_water_value"] = water_value
    end

    # Calculate renewable curtailment cost from solution
    if objective.renewable_curtailment_cost && haskey(model, :curtail)
        curtail = model[:curtail]
        curtail_cost = 0.0
        for farm in system.wind_farms
            if haskey(renewable_indices, farm.id)
                idx = renewable_indices[farm.id]
                for t in time_periods
                    curtail_cost += objective.curtailment_penalty * value(curtail[idx, t])
                end
            end
        end
        for farm in system.solar_farms
            if haskey(renewable_indices, farm.id)
                idx = renewable_indices[farm.id]
                for t in time_periods
                    curtail_cost += objective.curtailment_penalty * value(curtail[idx, t])
                end
            end
        end
        breakdown["renewable_curtailment"] = curtail_cost
    end

    # Calculate total
    total = sum(values(breakdown))
    breakdown["total"] = total

    return breakdown
end

# Export public types and functions
export ProductionCostObjective,
    get_fuel_cost,
    calculate_cost_breakdown
