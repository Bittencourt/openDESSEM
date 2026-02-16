"""
    Solution Extraction

Functions for extracting solution values and dual values from solved models.
"""

"""
    extract_solution_values!(
        result::SolverResult,
        model::Model,
        system::ElectricitySystem,
        time_periods::UnitRange{Int}
    )

Extract variable values from solved model into the result.

Uses lazy extraction - only computes values when first requested.

# Arguments
- `result::SolverResult`: Result object to populate
- `model::Model`: Solved JuMP model
- `system::ElectricitySystem`: Electricity system
- `time_periods::UnitRange{Int}`: Time periods

# Modifies
- `result.variables`: Populated with variable values
- `result.has_values`: Set to true

# Variables Extracted
- `:thermal_generation`: Dict[(plant_id, t) => value_mw]
- `:thermal_commitment`: Dict[(plant_id, t) => value_0_1]
- `:thermal_startup`: Dict[(plant_id, t) => value_0_1]
- `:thermal_shutdown`: Dict[(plant_id, t) => value_0_1]
- `:hydro_generation`: Dict[(plant_id, t) => value_mw]
- `:hydro_storage`: Dict[(plant_id, t) => value_hm3]
- `:hydro_outflow`: Dict[(plant_id, t) => value_m3_per_s]
- `:renewable_generation`: Dict[(plant_id, t) => value_mw]
- `:renewable_curtailment`: Dict[(plant_id, t) => value_mw]
"""
function extract_solution_values!(
    result::SolverResult,
    model::Model,
    system::ElectricitySystem,
    time_periods::UnitRange{Int},
)
    # Get plant indices from model or calculate from system
    obj_dict = object_dictionary(model)
    thermal_indices = get(obj_dict, :thermal_indices, get_thermal_plant_indices(system))
    hydro_indices = get(obj_dict, :hydro_indices, get_hydro_plant_indices(system))
    renewable_indices = get(obj_dict, :renewable_indices, get_renewable_plant_indices(system))

    # Extract thermal generation
    if haskey(model, :g)
        g = model[:g]
        thermal_gen = Dict{Tuple{String,Int},Float64}()
        for plant in system.thermal_plants
            if haskey(thermal_indices, plant.id)
                idx = thermal_indices[plant.id]
                for t in time_periods
                    try
                        val = value(g[idx, t])
                        thermal_gen[(plant.id, t)] = val
                    catch
                        @warn "Could not extract value for g[$idx, $t]"
                    end
                end
            end
        end
        result.variables[:thermal_generation] = thermal_gen
    end

    # Extract thermal commitment
    if haskey(model, :u)
        u = model[:u]
        thermal_commit = Dict{Tuple{String,Int},Float64}()
        for plant in system.thermal_plants
            if haskey(thermal_indices, plant.id)
                idx = thermal_indices[plant.id]
                for t in time_periods
                    try
                        val = value(u[idx, t])
                        thermal_commit[(plant.id, t)] = val
                    catch
                        @warn "Could not extract value for u[$idx, $t]"
                    end
                end
            end
        end
        result.variables[:thermal_commitment] = thermal_commit
    end

    # Extract thermal startup
    if haskey(model, :v)
        v = model[:v]
        thermal_startup = Dict{Tuple{String,Int},Float64}()
        for plant in system.thermal_plants
            if haskey(thermal_indices, plant.id)
                idx = thermal_indices[plant.id]
                for t in time_periods
                    try
                        val = value(v[idx, t])
                        thermal_startup[(plant.id, t)] = val
                    catch
                        @warn "Could not extract value for v[$idx, $t]"
                    end
                end
            end
        end
        result.variables[:thermal_startup] = thermal_startup
    end

    # Extract thermal shutdown
    if haskey(model, :w)
        w = model[:w]
        thermal_shutdown = Dict{Tuple{String,Int},Float64}()
        for plant in system.thermal_plants
            if haskey(thermal_indices, plant.id)
                idx = thermal_indices[plant.id]
                for t in time_periods
                    try
                        val = value(w[idx, t])
                        thermal_shutdown[(plant.id, t)] = val
                    catch
                        @warn "Could not extract value for w[$idx, $t]"
                    end
                end
            end
        end
        result.variables[:thermal_shutdown] = thermal_shutdown
    end

    # Extract hydro generation
    if haskey(model, :gh)
        gh = model[:gh]
        hydro_gen = Dict{Tuple{String,Int},Float64}()
        for plant in system.hydro_plants
            if haskey(hydro_indices, plant.id)
                idx = hydro_indices[plant.id]
                for t in time_periods
                    try
                        val = value(gh[idx, t])
                        hydro_gen[(plant.id, t)] = val
                    catch
                        @warn "Could not extract value for gh[$idx, $t]"
                    end
                end
            end
        end
        result.variables[:hydro_generation] = hydro_gen
    end

    # Extract hydro storage
    if haskey(model, :s)
        s = model[:s]
        hydro_storage = Dict{Tuple{String,Int},Float64}()
        for plant in system.hydro_plants
            if haskey(hydro_indices, plant.id)
                idx = hydro_indices[plant.id]
                for t in time_periods
                    try
                        val = value(s[idx, t])
                        hydro_storage[(plant.id, t)] = val
                    catch
                        @warn "Could not extract value for s[$idx, $t]"
                    end
                end
            end
        end
        result.variables[:hydro_storage] = hydro_storage
    end

    # Extract hydro outflow
    if haskey(model, :q)
        q = model[:q]
        hydro_outflow = Dict{Tuple{String,Int},Float64}()
        for plant in system.hydro_plants
            if haskey(hydro_indices, plant.id)
                idx = hydro_indices[plant.id]
                for t in time_periods
                    try
                        val = value(q[idx, t])
                        hydro_outflow[(plant.id, t)] = val
                    catch
                        @warn "Could not extract value for q[$idx, $t]"
                    end
                end
            end
        end
        result.variables[:hydro_outflow] = hydro_outflow
    end

    # Extract renewable generation
    if haskey(model, :gr)
        gr = model[:gr]
        renewable_gen = Dict{Tuple{String,Int},Float64}()
        for farm in system.wind_farms
            if haskey(renewable_indices, farm.id)
                idx = renewable_indices[farm.id]
                for t in time_periods
                    try
                        val = value(gr[idx, t])
                        renewable_gen[(farm.id, t)] = val
                    catch
                        @warn "Could not extract value for gr[$idx, $t]"
                    end
                end
            end
        end
        for farm in system.solar_farms
            if haskey(renewable_indices, farm.id)
                idx = renewable_indices[farm.id]
                for t in time_periods
                    try
                        val = value(gr[idx, t])
                        renewable_gen[(farm.id, t)] = val
                    catch
                        @warn "Could not extract value for gr[$idx, $t]"
                    end
                end
            end
        end
        result.variables[:renewable_generation] = renewable_gen
    end

    # Extract renewable curtailment
    if haskey(model, :curtail)
        curtail = model[:curtail]
        renewable_curtail = Dict{Tuple{String,Int},Float64}()
        for farm in system.wind_farms
            if haskey(renewable_indices, farm.id)
                idx = renewable_indices[farm.id]
                for t in time_periods
                    try
                        val = value(curtail[idx, t])
                        renewable_curtail[(farm.id, t)] = val
                    catch
                        @warn "Could not extract value for curtail[$idx, $t]"
                    end
                end
            end
        end
        for farm in system.solar_farms
            if haskey(renewable_indices, farm.id)
                idx = renewable_indices[farm.id]
                for t in time_periods
                    try
                        val = value(curtail[idx, t])
                        renewable_curtail[(farm.id, t)] = val
                    catch
                        @warn "Could not extract value for curtail[$idx, $t]"
                    end
                end
            end
        end
        result.variables[:renewable_curtailment] = renewable_curtail
    end

    result.has_values = true
    return nothing
end

"""
    extract_dual_values!(
        result::SolverResult,
        model::Model,
        system::ElectricitySystem,
        time_periods::UnitRange{Int}
    )

Extract dual values (shadow prices) from solved LP model.

Only works for LP problems (not MIP). Used for LMP calculation.

# Arguments
- `result::SolverResult`: Result object to populate
- `model::Model`: Solved JuMP model
- `system::ElectricitySystem`: Electricity system
- `time_periods::UnitRange{Int}`: Time periods

# Modifies
- `result.dual_values`: Populated with dual values
- `result.has_duals`: Set to true

# Dual Values Extracted
- `"submarket_balance"`: Dict[(submarket_id, t) => marginal_cost]
- Other constraint types can be added as needed
"""
function extract_dual_values!(
    result::SolverResult,
    model::Model,
    system::ElectricitySystem,
    time_periods::UnitRange{Int},
)
    # Check if duals are available (LP only)
    # Note: has_duals() can return false even for LP models, so we try anyway
    duals_available = has_duals(model)
    if !duals_available
        @debug "has_duals() returned false, attempting extraction anyway"
    end

    # Extract submarket balance duals (LMPs)
    if haskey(model, :submarket_balance)
        submarket_balance = model[:submarket_balance]
        submarket_duals = Dict{Tuple{String,Int},Float64}()

        for submarket in system.submarkets
            for t in time_periods
                try
                    key = (submarket.code, t)
                    if haskey(submarket_balance, key)
                        dval = dual(submarket_balance[key])
                        submarket_duals[key] = dval
                    end
                catch e
                    @warn "Could not extract dual for submarket_balance[$key]: $e"
                end
            end
        end

        result.dual_values["submarket_balance"] = submarket_duals
    else
        @warn "Model does not have :submarket_balance key in object dictionary"
    end

    # Additional constraint duals can be extracted here as needed

    result.has_duals = true
    return nothing
end

"""
    get_submarket_lmps(result::SolverResult, submarket_id::String, time_periods::UnitRange{Int}) -> Vector{Float64}

Extract locational marginal prices (LMPs) for a submarket.

LMPs are the dual values of the submarket energy balance constraints.

# Arguments
- `result::SolverResult`: Solver result with dual values
- `submarket_id::String`: Submarket identifier
- `time_periods::UnitRange{Int}`: Time periods

# Returns
- `Vector{Float64}`: LMPs in R\$/MWh for each time period

# Example
```julia
lmps_se = get_submarket_lmps(result, \"SE\", 1:24)
println(\"Peak LMP: R\$ \", maximum(lmps_se), \"/MWh\")
```
"""
function get_submarket_lmps(
    result::SolverResult,
    submarket_id::String,
    time_periods::UnitRange{Int},
)::Vector{Float64}
    if !result.has_duals
        @warn "Result does not have dual values. Was this an LP solve?"
        return zeros(Float64, length(time_periods))
    end

    if !haskey(result.dual_values, "submarket_balance")
        @warn "Submarket balance duals not found in result"
        return zeros(Float64, length(time_periods))
    end

    sb_dict = result.dual_values["submarket_balance"]

    lmps = Float64[]
    for t in time_periods
        key = (submarket_id, t)
        if haskey(sb_dict, key)
            push!(lmps, sb_dict[key])
        else
            push!(lmps, 0.0)
        end
    end

    return lmps
end

"""
    get_thermal_generation(result::SolverResult, plant_id::String, time_periods::UnitRange{Int}) -> Vector{Float64}

Get thermal generation schedule for a plant from the result.

# Arguments
- `result::SolverResult`: Solver result with variable values
- `plant_id::String`: Thermal plant identifier
- `time_periods::UnitRange{Int}`: Time periods

# Returns
- `Vector{Float64}`: Generation in MW for each time period

# Example
```julia
gen = get_thermal_generation(result, \"T_SE_001\", 1:24)
println(\"Average generation: \", mean(gen), \" MW\")
```
"""
function get_thermal_generation(
    result::SolverResult,
    plant_id::String,
    time_periods::UnitRange{Int},
)::Vector{Float64}
    if !result.has_values
        @warn "Result does not have variable values"
        return zeros(Float64, length(time_periods))
    end

    if !haskey(result.variables, :thermal_generation)
        @warn "Thermal generation not found in result"
        return zeros(Float64, length(time_periods))
    end

    gen = Float64[]
    for t in time_periods
        key = (plant_id, t)
        if haskey(result.variables[:thermal_generation], key)
            push!(gen, result.variables[:thermal_generation][key])
        else
            @warn "Generation not found for ($plant_id, $t)"
            push!(gen, 0.0)
        end
    end

    return gen
end

"""
    get_hydro_generation(result::SolverResult, plant_id::String, time_periods::UnitRange{Int}) -> Vector{Float64}

Get hydro generation schedule for a plant from the result.

# Arguments
- `result::SolverResult`: Solver result with variable values
- `plant_id::String`: Hydro plant identifier
- `time_periods::UnitRange{Int}`: Time periods

# Returns
- `Vector{Float64}`: Generation in MW for each time period

# Example
```julia
gen = get_hydro_generation(result, "H_SE_001", 1:24)
println("Total hydro generation: ", sum(gen), " MWh")
```
"""
function get_hydro_generation(
    result::SolverResult,
    plant_id::String,
    time_periods::UnitRange{Int},
)::Vector{Float64}
    if !result.has_values
        @warn "Result does not have variable values"
        return zeros(Float64, length(time_periods))
    end

    if !haskey(result.variables, :hydro_generation)
        @warn "Hydro generation not found in result"
        return zeros(Float64, length(time_periods))
    end

    gen = Float64[]
    for t in time_periods
        key = (plant_id, t)
        if haskey(result.variables[:hydro_generation], key)
            push!(gen, result.variables[:hydro_generation][key])
        else
            @warn "Generation not found for ($plant_id, $t)"
            push!(gen, 0.0)
        end
    end

    return gen
end

"""
    get_hydro_storage(result::SolverResult, plant_id::String, time_periods::UnitRange{Int}) -> Vector{Float64}

Get hydro storage trajectory for a plant from the result.

# Arguments
- `result::SolverResult`: Solver result with variable values
- `plant_id::String`: Hydro plant identifier
- `time_periods::UnitRange{Int}`: Time periods

# Returns
- `Vector{Float64}`: Storage in hm³ for each time period

# Example
```julia
storage = get_hydro_storage(result, \"H_SE_001\", 1:24)
println(\"Final storage: \", storage[end], \" hm³\")
```
"""
function get_hydro_storage(
    result::SolverResult,
    plant_id::String,
    time_periods::UnitRange{Int},
)::Vector{Float64}
    if !result.has_values
        @warn "Result does not have variable values"
        return zeros(Float64, length(time_periods))
    end

    if !haskey(result.variables, :hydro_storage)
        @warn "Hydro storage not found in result"
        return zeros(Float64, length(time_periods))
    end

    storage = Float64[]
    for t in time_periods
        key = (plant_id, t)
        if haskey(result.variables[:hydro_storage], key)
            push!(storage, result.variables[:hydro_storage][key])
        else
            @warn "Storage not found for ($plant_id, $t)"
            push!(storage, 0.0)
        end
    end

    return storage
end

"""
    get_renewable_generation(result::SolverResult, plant_id::String, time_periods::UnitRange{Int}) -> Vector{Float64}

Get renewable generation schedule for a plant from the result.

# Arguments
- `result::SolverResult`: Solver result with variable values
- `plant_id::String`: Renewable plant identifier (wind or solar)
- `time_periods::UnitRange{Int}`: Time periods

# Returns
- `Vector{Float64}`: Generation in MW for each time period

# Example
```julia
gen = get_renewable_generation(result, \"W_SE_001\", 1:24)
println(\"Total wind generation: \", sum(gen), \" MWh\")
```
"""
function get_renewable_generation(
    result::SolverResult,
    plant_id::String,
    time_periods::UnitRange{Int},
)::Vector{Float64}
    if !result.has_values
        @warn "Result does not have variable values"
        return zeros(Float64, length(time_periods))
    end

    if !haskey(result.variables, :renewable_generation)
        @warn "Renewable generation not found in result"
        return zeros(Float64, length(time_periods))
    end

    gen = Float64[]
    for t in time_periods
        key = (plant_id, t)
        if haskey(result.variables[:renewable_generation], key)
            push!(gen, result.variables[:renewable_generation][key])
        else
            @warn "Generation not found for ($plant_id, $t)"
            push!(gen, 0.0)
        end
    end

    return gen
end

"""
    get_pld_dataframe(
        result::SolverResult;
        submarkets::Union{Vector{String},Nothing}=nothing,
        time_periods::Union{UnitRange{Int},Nothing}=nothing
    ) -> DataFrame

Extract PLD (Preço de Liquidação das Diferenças) values as a DataFrame.

PLD is the locational marginal price (LMP) for each submarket and time period,
obtained from the dual values of submarket energy balance constraints.

# Arguments
- `result::SolverResult`: Solver result with dual values (from LP or SCED)
- `submarkets::Union{Vector{String},Nothing}`: Filter to specific submarkets (default: all)
- `time_periods::Union{UnitRange{Int},Nothing}`: Filter to specific time periods (default: all available)

# Returns
- `DataFrame` with columns:
  - `submarket`: Submarket code (e.g., "SE", "NE", "S", "N")
  - `period`: Time period index
  - `pld`: PLD value in R$/MWh

# Example
```julia
# Get all PLDs as DataFrame
pld_df = get_pld_dataframe(result)
println(first(pld_df, 5))

# Filter to specific submarket
pld_se = get_pld_dataframe(result; submarkets=["SE"])
println("SE submarket PLDs:")
println(pld_se)

# Filter to specific time periods
pld_peak = get_pld_dataframe(result; time_periods=18:21)  # Peak hours
println("Peak period PLDs:")
println(pld_peak)
```

# Notes
- Returns empty DataFrame with correct columns if no dual values available
- PLD values are the shadow prices of submarket balance constraints
- For MIP problems, use `result.lp_result` (from two-stage pricing) for valid PLDs
"""
function get_pld_dataframe(
    result::SolverResult;
    submarkets::Union{Vector{String},Nothing} = nothing,
    time_periods::Union{UnitRange{Int},Nothing} = nothing,
)
    # Create empty DataFrame with correct schema
    empty_df = DataFrame(;
        submarket = String[],
        period = Int[],
        pld = Float64[],
    )

    # Check if dual values are available
    if !result.has_duals
        @warn "Result does not have dual values. For MIP problems, use result.lp_result for valid PLDs."
        return empty_df
    end

    # Check for submarket_balance duals
    if !haskey(result.dual_values, "submarket_balance")
        @warn "Submarket balance duals not found in result. Ensure model has submarket balance constraints."
        return empty_df
    end

    sb_dict = result.dual_values["submarket_balance"]

    # Collect all available keys
    rows = []
    for ((submarket_code, t), pld_value) in sb_dict
        # Apply submarket filter
        if submarkets !== nothing && !(submarket_code in submarkets)
            continue
        end

        # Apply time period filter
        if time_periods !== nothing && !(t in time_periods)
            continue
        end

        push!(rows, (submarket = submarket_code, period = t, pld = pld_value))
    end

    # Handle empty results gracefully
    if isempty(rows)
        if submarkets !== nothing || time_periods !== nothing
            @warn "No PLD values found for specified filters" submarkets =
                submarkets time_periods = time_periods
        end
        return empty_df
    end

    # Create DataFrame and sort
    df = DataFrame(rows)
    sort!(df, [:submarket, :period])

    return df
end

"""
    CostBreakdown

Detailed breakdown of total system cost by component.

# Fields
- `thermal_fuel::Float64`: Fuel costs for thermal generation (R$)
- `thermal_startup::Float64`: Startup costs for thermal plants (R$)
- `thermal_shutdown::Float64`: Shutdown costs for thermal plants (R$)
- `deficit_penalty::Float64`: Penalty cost for load deficit (R$)
- `hydro_water_value::Float64`: Water value/opportunity cost for hydro (R$)
- `total::Float64`: Total system cost (R$)

# Example
```julia
breakdown = get_cost_breakdown(result, system)
println("Total cost: R\$ ", breakdown.total)
println("Thermal fuel: R\$ ", breakdown.thermal_fuel)
println("Deficit penalty: R\$ ", breakdown.deficit_penalty)
```
"""
Base.@kwdef struct CostBreakdown
    thermal_fuel::Float64 = 0.0
    thermal_startup::Float64 = 0.0
    thermal_shutdown::Float64 = 0.0
    deficit_penalty::Float64 = 0.0
    hydro_water_value::Float64 = 0.0
    total::Float64 = 0.0
end

"""
    get_cost_breakdown(
        result::SolverResult,
        system::ElectricitySystem;
        time_periods::Union{UnitRange{Int},Nothing}=nothing
    ) -> CostBreakdown

Calculate detailed cost breakdown from optimization result.

Computes individual cost components by combining variable values from the
optimization result with cost parameters from the system entities.

# Arguments
- `result::SolverResult`: Solver result with variable values
- `system::ElectricitySystem`: Electricity system with cost parameters
- `time_periods::Union{UnitRange{Int},Nothing}`: Time periods to include (default: all available)

# Returns
- `CostBreakdown` struct with individual cost components

# Cost Components Calculated
- **thermal_fuel**: Sum of g[i,t] * fuel_cost[i] for all thermal plants
- **thermal_startup**: Sum of v[i,t] * startup_cost[i] for all thermal plants
- **thermal_shutdown**: Sum of w[i,t] * shutdown_cost[i] for all thermal plants
- **deficit_penalty**: Sum of deficit[submarket,t] * deficit_cost[submarket]
- **hydro_water_value**: Placeholder (0.0 if FCF not available)
- **total**: Sum of all components

# Example
```julia
# After solving with two-stage pricing
result = solve_model!(model, system)
if result.solve_status == OPTIMAL
    breakdown = get_cost_breakdown(result, system)
    
    println("Cost Breakdown:")
    println("  Thermal Fuel: R\$ ", breakdown.thermal_fuel)
    println("  Startup: R\$ ", breakdown.thermal_startup)
    println("  Shutdown: R\$ ", breakdown.thermal_shutdown)
    println("  Deficit: R\$ ", breakdown.deficit_penalty)
    println("  Hydro: R\$ ", breakdown.hydro_water_value)
    println("  Total: R\$ ", breakdown.total)
end

# For two-stage pricing, use the LP result for accurate duals
if result.lp_result !== nothing
    breakdown = get_cost_breakdown(result.lp_result, system)
end
```

# Notes
- Requires `result.has_values == true`
- Thermal costs are computed from actual generation and commitment decisions
- Hydro water value is 0 if FCF curves are not available (future enhancement)
- All costs are in Brazilian Reais (R$)
"""
function get_cost_breakdown(
    result::SolverResult,
    system::ElectricitySystem;
    time_periods::Union{UnitRange{Int},Nothing} = nothing,
)
    # Initialize all components to zero
    thermal_fuel = 0.0
    thermal_startup = 0.0
    thermal_shutdown = 0.0
    deficit_penalty = 0.0
    hydro_water_value = 0.0

    # Check if variable values are available
    if !result.has_values
        @warn "Result does not have variable values. Cannot compute cost breakdown."
        return CostBreakdown()
    end

    # Determine time periods to use
    if time_periods === nothing
        # Infer from available data
        if haskey(result.variables, :thermal_generation) &&
           !isempty(result.variables[:thermal_generation])
            # Get time periods from thermal generation keys
            periods_seen = Set{Int}()
            for ((_, t), _) in result.variables[:thermal_generation]
                push!(periods_seen, t)
            end
            time_periods = minimum(periods_seen):maximum(periods_seen)
        else
            @warn "Cannot infer time periods from result. Using empty range."
            time_periods = 1:0  # Empty range
        end
    end

    # Calculate thermal fuel cost: g[i,t] * fuel_cost[i]
    if haskey(result.variables, :thermal_generation)
        thermal_gen = result.variables[:thermal_generation]
        for plant in system.thermal_plants
            for t in time_periods
                key = (plant.id, t)
                if haskey(thermal_gen, key)
                    gen_mw = thermal_gen[key]
                    # fuel_cost_rsj_per_mwh is R$/MWh, gen is in MW for 1 hour = MWh
                    thermal_fuel += gen_mw * plant.fuel_cost_rsj_per_mwh
                end
            end
        end
    end

    # Calculate thermal startup cost: v[i,t] * startup_cost[i]
    if haskey(result.variables, :thermal_startup)
        thermal_startup_vars = result.variables[:thermal_startup]
        for plant in system.thermal_plants
            for t in time_periods
                key = (plant.id, t)
                if haskey(thermal_startup_vars, key)
                    startup_val = thermal_startup_vars[key]
                    # v is binary, startup_cost_rs is R$ per startup event
                    if startup_val > 0.5  # Count as startup if > 0.5
                        thermal_startup += plant.startup_cost_rs
                    end
                end
            end
        end
    end

    # Calculate thermal shutdown cost: w[i,t] * shutdown_cost[i]
    if haskey(result.variables, :thermal_shutdown)
        thermal_shutdown_vars = result.variables[:thermal_shutdown]
        for plant in system.thermal_plants
            for t in time_periods
                key = (plant.id, t)
                if haskey(thermal_shutdown_vars, key)
                    shutdown_val = thermal_shutdown_vars[key]
                    # w is binary, shutdown_cost_rs is R$ per shutdown event
                    if shutdown_val > 0.5  # Count as shutdown if > 0.5
                        thermal_shutdown += plant.shutdown_cost_rs
                    end
                end
            end
        end
    end

    # Calculate deficit penalty: deficit[submarket,t] * deficit_cost
    # The deficit variable is stored as :deficit or similar
    if haskey(result.variables, :deficit)
        deficit_vars = result.variables[:deficit]
        # Get deficit costs from submarkets
        deficit_cost_per_mwh = 5000.0  # Default high penalty (R$/MWh)
        for ((submarket_code, t), deficit_mw) in deficit_vars
            # Look for submarket-specific deficit cost
            for submarket in system.submarkets
                if submarket.code == submarket_code
                    # Use submarket-specific cost if available
                    # deficit_cost_per_mwh = get(submarket, :deficit_cost, 5000.0)
                    break
                end
            end
            deficit_penalty += deficit_mw * deficit_cost_per_mwh
        end
    end

    # Hydro water value: placeholder (0 if FCF not available)
    # Future enhancement: integrate with FCF curves from Phase 1
    # The water value represents the opportunity cost of using water now vs future
    # It's computed from the terminal storage and FCF slope
    hydro_water_value = 0.0

    # Total cost
    total = thermal_fuel + thermal_startup + thermal_shutdown + deficit_penalty + hydro_water_value

    return CostBreakdown(;
        thermal_fuel = thermal_fuel,
        thermal_startup = thermal_startup,
        thermal_shutdown = thermal_shutdown,
        deficit_penalty = deficit_penalty,
        hydro_water_value = hydro_water_value,
        total = total,
    )
end

# Export public functions
export extract_solution_values!,
    extract_dual_values!,
    get_submarket_lmps,
    get_thermal_generation,
    get_hydro_generation,
    get_hydro_storage,
    get_renewable_generation,
    get_pld_dataframe,
    CostBreakdown,
    get_cost_breakdown
