"""
    Variable Manager for OpenDESSEM

Creates JuMP optimization variables for all entity types in the OpenDESSEM system.
This module provides functions to create decision variables for thermal unit commitment,
hydro operations, and renewable generation.

# Variable Naming Convention

## Thermal Variables (Unit Commitment)
- `u[i,t]`: Binary commitment status (1 = online, 0 = offline)
- `v[i,t]`: Binary startup indicator (1 = starting up at t)
- `w[i,t]`: Binary shutdown indicator (1 = shutting down at t)
- `g[i,t]`: Continuous generation output (MW)

## Hydro Variables
- `s[i,t]`: Storage volume (hm³)
- `q[i,t]`: Turbine outflow (m³/s)
- `gh[i,t]`: Hydro generation output (MW)
- `pump[i,t]`: Pumping power for pumped storage (MW)

## Renewable Variables
- `gr[i,t]`: Renewable generation output (MW)
- `curtail[i,t]`: Curtailed generation (MW)

## Load Shedding Variables
- `shed[l,t]`: Load shedding (MW) for load l at time t

## Deficit Variables
- `deficit[s,t]`: Energy deficit (MW) in submarket s at time t

# PowerModels Integration

Network-related variables (voltage angles θ, voltage magnitudes V, power flows P/Q)
are NOT created by this module. These are handled by PowerModels.jl during
network-constrained optimization. Use `get_powermodels_variable()` to access
PowerModels solution values for coupling with OpenDESSEM variables.

# Example Usage

```julia
using JuMP
using OpenDESSEM
using OpenDESSEM.Variables

# Load or create system
system = load_system(...)

# Create JuMP model
model = Model()

# Define time horizon
time_periods = 1:24  # 24 hourly periods

# Create all variables
create_all_variables!(model, system, time_periods)

# Or create specific variable types
create_thermal_variables!(model, system, time_periods)
create_hydro_variables!(model, system, time_periods)
create_renewable_variables!(model, system, time_periods)

# Access variables by index
u = model[:u]
println("Commitment of plant 1 at time 5: ", u[1, 5])

# Use plant ID lookup
indices = get_thermal_plant_indices(system)
plant_idx = indices["T_SE_001"]
println("Generation of T_SE_001 at time 5: ", model[:g][plant_idx, 5])
```
"""
module Variables

using JuMP

# Import entity types from parent module
using ..OpenDESSEM:
    ElectricitySystem,
    ConventionalThermal,
    ThermalPlant,
    HydroPlant,
    ReservoirHydro,
    RunOfRiverHydro,
    PumpedStorageHydro,
    RenewablePlant,
    WindPlant,
    SolarPlant,
    Load

# Export all public functions
export create_thermal_variables!,
    create_hydro_variables!,
    create_renewable_variables!,
    create_load_shedding_variables!,
    create_deficit_variables!,
    create_all_variables!,
    get_powermodels_variable,
    list_supported_powermodels_variables,
    get_thermal_plant_indices,
    get_hydro_plant_indices,
    get_renewable_plant_indices,
    get_load_indices,
    get_submarket_indices,
    get_plant_by_index

"""
    get_thermal_plant_indices(system::ElectricitySystem) -> Dict{String, Int}

Create a mapping from thermal plant IDs to their sequential indices.

# Arguments
- `system::ElectricitySystem`: The electricity system containing thermal plants

# Returns
- `Dict{String, Int}`: Mapping of plant ID to 1-based index

# Example
```julia
indices = get_thermal_plant_indices(system)
plant_idx = indices["T_SE_001"]  # Get index for specific plant
```
"""
function get_thermal_plant_indices(system::ElectricitySystem)::Dict{String,Int}
    return Dict(plant.id => i for (i, plant) in enumerate(system.thermal_plants))
end

"""
    get_hydro_plant_indices(system::ElectricitySystem) -> Dict{String, Int}

Create a mapping from hydro plant IDs to their sequential indices.

# Arguments
- `system::ElectricitySystem`: The electricity system containing hydro plants

# Returns
- `Dict{String, Int}`: Mapping of plant ID to 1-based index

# Example
```julia
indices = get_hydro_plant_indices(system)
plant_idx = indices["H_001"]  # Get index for specific plant
```
"""
function get_hydro_plant_indices(system::ElectricitySystem)::Dict{String,Int}
    return Dict(plant.id => i for (i, plant) in enumerate(system.hydro_plants))
end

"""
    get_renewable_plant_indices(system::ElectricitySystem) -> Dict{String, Int}

Create a mapping from renewable plant IDs to their sequential indices.

Includes both wind and solar plants in the order: wind farms first, then solar farms.

# Arguments
- `system::ElectricitySystem`: The electricity system containing renewable plants

# Returns
- `Dict{String, Int}`: Mapping of plant ID to 1-based index

# Example
```julia
indices = get_renewable_plant_indices(system)
plant_idx = indices["W_NE_001"]  # Get index for wind plant
```
"""
function get_renewable_plant_indices(system::ElectricitySystem)::Dict{String,Int}
    result = Dict{String,Int}()
    idx = 1

    for farm in system.wind_farms
        result[farm.id] = idx
        idx += 1
    end

    for farm in system.solar_farms
        result[farm.id] = idx
        idx += 1
    end

    return result
end

"""
    get_plant_by_index(plants::Vector, index::Int) -> plant

Get a plant from a vector by its 1-based index.

# Arguments
- `plants::Vector`: Vector of plant entities
- `index::Int`: 1-based index

# Returns
- The plant at the given index

# Throws
- `BoundsError` if index is out of range
"""
function get_plant_by_index(plants::Vector, index::Int)
    return plants[index]
end

"""
    validate_plant_ids(system_plants::Vector, plant_ids::Vector{String}, entity_type::String)

Validate that all provided plant IDs exist in the system.

# Arguments
- `system_plants::Vector`: Vector of plant entities in the system
- `plant_ids::Vector{String}`: Plant IDs to validate
- `entity_type::String`: Type of entity for error messages

# Throws
- `ArgumentError` if any plant ID is not found in the system
"""
function validate_plant_ids(
    system_plants::Vector,
    plant_ids::Vector{String},
    entity_type::String,
)
    system_ids = Set(plant.id for plant in system_plants)
    for id in plant_ids
        if !(id in system_ids)
            throw(
                ArgumentError(
                    "$entity_type plant ID '$id' not found in system. " *
                    "Available IDs: $(sort(collect(system_ids)))",
                ),
            )
        end
    end
end

"""
    filter_plants_by_ids(plants::Vector, plant_ids::Union{Nothing, Vector{String}})

Filter plants by IDs if provided, otherwise return all plants.

# Arguments
- `plants::Vector`: Vector of plant entities
- `plant_ids::Union{Nothing, Vector{String}}`: Optional list of plant IDs to filter by

# Returns
- Filtered vector of plants (or original if plant_ids is nothing)
"""
function filter_plants_by_ids(plants::Vector, plant_ids::Union{Nothing,Vector{String}})
    if plant_ids === nothing
        return plants
    end
    id_set = Set(plant_ids)
    return [p for p in plants if p.id in id_set]
end

"""
    create_thermal_variables!(
        model::Model,
        system::ElectricitySystem,
        time_periods::Union{UnitRange{Int}, Vector{Int}};
        plant_ids::Union{Nothing, Vector{String}} = nothing
    )

Create JuMP optimization variables for thermal power plants.

Creates the following variables for unit commitment optimization:
- `u[i,t]`: Binary commitment status (1 = online, 0 = offline)
- `v[i,t]`: Binary startup indicator (1 = starting up at period t)
- `w[i,t]`: Binary shutdown indicator (1 = shutting down at period t)
- `g[i,t]`: Continuous generation output (MW), bounded [0, max_generation_mw]

The logical relationship between these variables is:
- `u[t] - u[t-1] = v[t] - w[t]` (commitment state transition)
- `v[t] + w[t] <= 1` (cannot startup and shutdown simultaneously)

# Arguments
- `model::Model`: JuMP model to add variables to
- `system::ElectricitySystem`: System containing thermal plants
- `time_periods::Union{UnitRange{Int}, Vector{Int}}`: Time periods for variables
- `plant_ids::Union{Nothing, Vector{String}}`: Optional list of specific plant IDs

# Modifies
- Adds `:u`, `:v`, `:w`, `:g` variables to the model

# Throws
- `ArgumentError` if any plant_id is not found in the system

# Example
```julia
model = Model()
create_thermal_variables!(model, system, 1:24)

# Access commitment variable for plant 1 at time 5
u = model[:u]
println(u[1, 5])
```
"""
function create_thermal_variables!(
    model::Model,
    system::ElectricitySystem,
    time_periods::Union{UnitRange{Int},Vector{Int}};
    plant_ids::Union{Nothing,Vector{String}} = nothing,
)
    # Validate plant_ids if provided
    if plant_ids !== nothing
        validate_plant_ids(system.thermal_plants, plant_ids, "thermal")
    end

    # Filter plants
    plants = filter_plants_by_ids(system.thermal_plants, plant_ids)

    # Skip if no plants
    if isempty(plants)
        return nothing
    end

    n_plants = length(plants)
    n_periods = length(time_periods)
    T = collect(time_periods)

    # Create commitment variables (binary)
    @variable(model, u[1:n_plants, 1:n_periods], Bin)

    # Create startup variables (binary)
    @variable(model, v[1:n_plants, 1:n_periods], Bin)

    # Create shutdown variables (binary)
    @variable(model, w[1:n_plants, 1:n_periods], Bin)

    # Create generation variables (continuous, bounded)
    # Lower bound is 0, upper bound will be enforced by constraints
    @variable(model, g[i = 1:n_plants, t = 1:n_periods] >= 0)

    return nothing
end

"""
    create_hydro_variables!(
        model::Model,
        system::ElectricitySystem,
        time_periods::Union{UnitRange{Int}, Vector{Int}};
        plant_ids::Union{Nothing, Vector{String}} = nothing
    )

Create JuMP optimization variables for hydro power plants.

Creates the following variables for hydro operation optimization:
- `s[i,t]`: Storage volume (hm³), bounded by reservoir limits
- `q[i,t]`: Turbine outflow rate (m³/s), bounded by turbine capacity
- `gh[i,t]`: Hydro generation output (MW), bounded [0, max_generation_mw]
- `pump[i,t]`: Pumping power for pumped storage plants (MW)

For pumped storage plants, the `pump` variable represents power consumed
for pumping water from lower to upper reservoir.

# Arguments
- `model::Model`: JuMP model to add variables to
- `system::ElectricitySystem`: System containing hydro plants
- `time_periods::Union{UnitRange{Int}, Vector{Int}}`: Time periods for variables
- `plant_ids::Union{Nothing, Vector{String}}`: Optional list of specific plant IDs

# Modifies
- Adds `:s`, `:q`, `:gh`, `:pump` variables to the model

# Throws
- `ArgumentError` if any plant_id is not found in the system

# Example
```julia
model = Model()
create_hydro_variables!(model, system, 1:168)  # Weekly horizon

# Access storage variable for plant 2 at time 24
s = model[:s]
println(s[2, 24])
```
"""
function create_hydro_variables!(
    model::Model,
    system::ElectricitySystem,
    time_periods::Union{UnitRange{Int},Vector{Int}};
    plant_ids::Union{Nothing,Vector{String}} = nothing,
)
    # Validate plant_ids if provided
    if plant_ids !== nothing
        validate_plant_ids(system.hydro_plants, plant_ids, "hydro")
    end

    # Filter plants
    plants = filter_plants_by_ids(system.hydro_plants, plant_ids)

    # Skip if no plants
    if isempty(plants)
        return nothing
    end

    n_plants = length(plants)
    n_periods = length(time_periods)

    # Create storage variables (continuous, bounded)
    # Lower bound is min_volume, enforced here; upper bound by constraints
    @variable(model, s[i = 1:n_plants, t = 1:n_periods] >= 0)

    # Create outflow variables (continuous, bounded)
    @variable(model, q[i = 1:n_plants, t = 1:n_periods] >= 0)

    # Create hydro generation variables (continuous, bounded)
    @variable(model, gh[i = 1:n_plants, t = 1:n_periods] >= 0)

    # Create pumping variables (continuous, bounded)
    # Only relevant for pumped storage, but created for all for simplicity
    @variable(model, pump[i = 1:n_plants, t = 1:n_periods] >= 0)

    return nothing
end

"""
    create_renewable_variables!(
        model::Model,
        system::ElectricitySystem,
        time_periods::Union{UnitRange{Int}, Vector{Int}};
        plant_ids::Union{Nothing, Vector{String}} = nothing
    )

Create JuMP optimization variables for renewable power plants.

Creates the following variables for renewable generation optimization:
- `gr[i,t]`: Renewable generation output (MW), bounded by forecast
- `curtail[i,t]`: Curtailed generation (MW), non-negative

The relationship between these variables is:
- `gr[i,t] + curtail[i,t] <= capacity_forecast_mw[t]`

Renewables include both wind and solar plants, indexed consecutively
(wind farms first, then solar farms).

# Arguments
- `model::Model`: JuMP model to add variables to
- `system::ElectricitySystem`: System containing renewable plants
- `time_periods::Union{UnitRange{Int}, Vector{Int}}`: Time periods for variables
- `plant_ids::Union{Nothing, Vector{String}}`: Optional list of specific plant IDs

# Modifies
- Adds `:gr`, `:curtail` variables to the model

# Throws
- `ArgumentError` if any plant_id is not found in the system

# Example
```julia
model = Model()
create_renewable_variables!(model, system, 1:24)

# Access generation variable for renewable plant 1 at time 12
gr = model[:gr]
println(gr[1, 12])
```
"""
function create_renewable_variables!(
    model::Model,
    system::ElectricitySystem,
    time_periods::Union{UnitRange{Int},Vector{Int}};
    plant_ids::Union{Nothing,Vector{String}} = nothing,
)
    # Collect all renewables (wind + solar)
    all_renewables = RenewablePlant[system.wind_farms..., system.solar_farms...]

    # Validate plant_ids if provided
    if plant_ids !== nothing
        validate_plant_ids(all_renewables, plant_ids, "renewable")
    end

    # Filter plants
    plants = filter_plants_by_ids(all_renewables, plant_ids)

    # Skip if no plants
    if isempty(plants)
        return nothing
    end

    n_plants = length(plants)
    n_periods = length(time_periods)

    # Create renewable generation variables (continuous, bounded)
    @variable(model, gr[i = 1:n_plants, t = 1:n_periods] >= 0)

    # Create curtailment variables (continuous, non-negative)
    @variable(model, curtail[i = 1:n_plants, t = 1:n_periods] >= 0)

    return nothing
end

"""
    get_load_indices(system::ElectricitySystem) -> Dict{String, Int}

Create a mapping from load IDs to their sequential indices.

# Arguments
- `system::ElectricitySystem`: The electricity system containing loads

# Returns
- `Dict{String, Int}`: Mapping of load ID to 1-based index

# Example
```julia
indices = get_load_indices(system)
load_idx = indices["LOAD_001"]  # Get index for specific load
```
"""
function get_load_indices(system::ElectricitySystem)::Dict{String,Int}
    return Dict(load.id => i for (i, load) in enumerate(system.loads))
end

"""
    create_load_shedding_variables!(
        model::Model,
        system::ElectricitySystem,
        time_periods::Union{UnitRange{Int}, Vector{Int}};
        load_ids::Union{Nothing, Vector{String}} = nothing
    )

Create load shedding penalty variables.

Creates:
- `shed[l, t]`: Load shedding (MW) for load l at time t, >= 0

Load shedding represents demand that cannot be met by available generation.
High penalty costs in objective ensure shedding only occurs as last resort.

# Arguments
- `model::Model`: JuMP model to add variables to
- `system::ElectricitySystem`: System containing loads
- `time_periods::Union{UnitRange{Int}, Vector{Int}}`: Time periods for variables
- `load_ids::Union{Nothing, Vector{String}}`: Optional specific load IDs to create variables for

# Modifies
- Adds `:shed` variables to the model

# Throws
- `ArgumentError` if any load_id is not found in the system

# Example
```julia
model = Model()
create_load_shedding_variables!(model, system, 1:168)
shed = model[:shed]  # Access shedding variable

# Access shedding for load 1 at time 5
println(shed[1, 5])
```
"""
function create_load_shedding_variables!(
    model::Model,
    system::ElectricitySystem,
    time_periods::Union{UnitRange{Int},Vector{Int}};
    load_ids::Union{Nothing,Vector{String}} = nothing,
)
    # Validate load_ids if provided
    if load_ids !== nothing
        system_load_ids = Set(load.id for load in system.loads)
        for id in load_ids
            if !(id in system_load_ids)
                throw(
                    ArgumentError(
                        "Load ID '$id' not found in system. " *
                        "Available IDs: $(sort(collect(system_load_ids)))",
                    ),
                )
            end
        end
    end

    # Filter loads
    loads = if load_ids === nothing
        system.loads
    else
        id_set = Set(load_ids)
        [l for l in system.loads if l.id in id_set]
    end

    # Skip if no loads
    if isempty(loads)
        return nothing
    end

    n_loads = length(loads)
    n_periods = length(time_periods)

    # Create load shedding variables (continuous, non-negative)
    # Upper bound will be enforced by constraints (limited by load demand)
    @variable(model, shed[l = 1:n_loads, t = 1:n_periods] >= 0)

    return nothing
end

"""
    get_submarket_indices(system::ElectricitySystem) -> Dict{String, Int}

Create a mapping from submarket codes to their sequential indices.

# Arguments
- `system::ElectricitySystem`: The electricity system containing submarkets

# Returns
- `Dict{String, Int}`: Mapping of submarket code to 1-based index

# Example
```julia
indices = get_submarket_indices(system)
sm_idx = indices["SE"]  # Get index for Southeast submarket
```
"""
function get_submarket_indices(system::ElectricitySystem)::Dict{String,Int}
    return Dict(sm.code => i for (i, sm) in enumerate(system.submarkets))
end

"""
    create_deficit_variables!(
        model::Model,
        system::ElectricitySystem,
        time_periods::Union{UnitRange{Int}, Vector{Int}};
        submarket_ids::Union{Nothing, Vector{String}} = nothing
    )

Create energy deficit variables per submarket.

Creates:
- `deficit[s, t]`: Energy deficit (MW) in submarket s at time t, >= 0

Deficit represents unmet demand at the submarket level. Different from
load shedding - deficit is per-submarket aggregate, shedding is per-load.

# Arguments
- `model::Model`: JuMP model to add variables to
- `system::ElectricitySystem`: System containing submarkets
- `time_periods::Union{UnitRange{Int}, Vector{Int}}`: Time periods for variables
- `submarket_ids::Union{Nothing, Vector{String}}`: Optional specific submarket codes

# Modifies
- Adds `:deficit` variables to the model

# Throws
- `ArgumentError` if any submarket_id is not found in the system

# Example
```julia
model = Model()
create_deficit_variables!(model, system, 1:168)
deficit = model[:deficit]  # Access deficit variable

# Access deficit for submarket 1 at time 24
println(deficit[1, 24])
```
"""
function create_deficit_variables!(
    model::Model,
    system::ElectricitySystem,
    time_periods::Union{UnitRange{Int},Vector{Int}};
    submarket_ids::Union{Nothing,Vector{String}} = nothing,
)
    # Validate submarket_ids if provided
    if submarket_ids !== nothing
        system_codes = Set(sm.code for sm in system.submarkets)
        for id in submarket_ids
            if !(id in system_codes)
                throw(
                    ArgumentError(
                        "Submarket code '$id' not found in system. " *
                        "Available codes: $(sort(collect(system_codes)))",
                    ),
                )
            end
        end
    end

    # Filter submarkets
    submarkets = if submarket_ids === nothing
        system.submarkets
    else
        id_set = Set(submarket_ids)
        [sm for sm in system.submarkets if sm.code in id_set]
    end

    # Skip if no submarkets
    if isempty(submarkets)
        return nothing
    end

    n_submarkets = length(submarkets)
    n_periods = length(time_periods)

    # Create deficit variables (continuous, non-negative)
    # Upper bound will be enforced by constraints (limited by submarket demand)
    @variable(model, deficit[s = 1:n_submarkets, t = 1:n_periods] >= 0)

    return nothing
end

"""
    create_all_variables!(
        model::Model,
        system::ElectricitySystem,
        time_periods::Union{UnitRange{Int}, Vector{Int}}
    )

Create all JuMP optimization variables for the electricity system.

This is a convenience function that creates variables for all entity types:
- Thermal variables: `u`, `v`, `w`, `g`
- Hydro variables: `s`, `q`, `gh`, `pump`
- Renewable variables: `gr`, `curtail`
- Load shedding variables: `shed`
- Deficit variables: `deficit`

Note: Network variables (voltage angles, magnitudes, power flows) are NOT
created here - they are handled by PowerModels.jl during network-constrained
optimization.

# Arguments
- `model::Model`: JuMP model to add variables to
- `system::ElectricitySystem`: Complete electricity system
- `time_periods::Union{UnitRange{Int}, Vector{Int}}`: Time periods for variables

# Example
```julia
using JuMP

model = Model()
create_all_variables!(model, system, 1:24)

# Now model contains all decision variables
println("Variables created: ", keys(object_dictionary(model)))
```
"""
function create_all_variables!(
    model::Model,
    system::ElectricitySystem,
    time_periods::Union{UnitRange{Int},Vector{Int}},
)
    create_thermal_variables!(model, system, time_periods)
    create_hydro_variables!(model, system, time_periods)
    create_renewable_variables!(model, system, time_periods)
    create_load_shedding_variables!(model, system, time_periods)
    create_deficit_variables!(model, system, time_periods)
    return nothing
end

# PowerModels variable mapping
# Maps OpenDESSEM variable symbols to PowerModels solution paths
const POWERMODELS_VAR_MAPPING = Dict{Symbol,Tuple{String,String}}(
    :va => ("bus", "va"),       # Voltage angle (rad)
    :vm => ("bus", "vm"),       # Voltage magnitude (p.u.)
    :pg => ("gen", "pg"),       # Generator active power (MW)
    :qg => ("gen", "qg"),       # Generator reactive power (MVAr)
    :pf => ("branch", "pf"),    # Branch from-end active power (MW)
    :pt => ("branch", "pt"),    # Branch to-end active power (MW)
    :qf => ("branch", "qf"),    # Branch from-end reactive power (MVAr)
    :qt => ("branch", "qt"),    # Branch to-end reactive power (MVAr)
)

"""
    list_supported_powermodels_variables() -> Vector{Symbol}

List all PowerModels variable types supported by `get_powermodels_variable`.

# Returns
- `Vector{Symbol}`: List of supported variable symbols

# Supported Variables
- `:va` - Voltage angle (radians)
- `:vm` - Voltage magnitude (per-unit)
- `:pg` - Generator active power (MW)
- `:qg` - Generator reactive power (MVAr)
- `:pf` - Branch from-end active power (MW)
- `:pt` - Branch to-end active power (MW)
- `:qf` - Branch from-end reactive power (MVAr)
- `:qt` - Branch to-end reactive power (MVAr)

# Example
```julia
vars = list_supported_powermodels_variables()
println("Supported: ", vars)
```
"""
function list_supported_powermodels_variables()::Vector{Symbol}
    return collect(keys(POWERMODELS_VAR_MAPPING))
end

"""
    get_powermodels_variable(
        pm_result::Dict{String, Any},
        var_name::Symbol,
        index::Any
    ) -> Union{Float64, Nothing}

Bridge function to access PowerModels.jl solution variables.

PowerModels.jl handles all network-related variables (voltage, power flows).
This function provides a unified interface to access these values after
solving a PowerModels problem.

# Arguments
- `pm_result::Dict{String, Any}`: PowerModels solve result dictionary
- `var_name::Symbol`: Variable name (see `list_supported_powermodels_variables()`)
- `index::Any`: Component index (bus, generator, or branch number)

# Returns
- `Float64`: Variable value if found
- `nothing`: If variable or index not found

# Supported Variables
- `:va` - Voltage angle at bus (radians)
- `:vm` - Voltage magnitude at bus (per-unit)
- `:pg` - Active power output of generator (MW)
- `:qg` - Reactive power output of generator (MVAr)
- `:pf` - Active power flow at branch from-end (MW)
- `:pt` - Active power flow at branch to-end (MW)
- `:qf` - Reactive power flow at branch from-end (MVAr)
- `:qt` - Reactive power flow at branch to-end (MVAr)

# Example
```julia
using PowerModels, HiGHS

# Solve DC-OPF with PowerModels
pm_result = solve_dc_opf(pm_data, HiGHS.Optimizer)

# Access voltage angle at bus 1
va_1 = get_powermodels_variable(pm_result, :va, 1)
println("Voltage angle at bus 1: ", va_1, " rad")

# Access generator output
pg_2 = get_powermodels_variable(pm_result, :pg, 2)
println("Generator 2 output: ", pg_2, " MW")

# Access branch flow
pf_1 = get_powermodels_variable(pm_result, :pf, 1)
println("Branch 1 from-end flow: ", pf_1, " MW")
```

# Integration with OpenDESSEM
```julia
# After solving PowerModels problem, couple with OpenDESSEM variables
model = Model()
create_all_variables!(model, system, 1:24)

# Get network injection at bus where thermal is connected
bus_idx = 1
pg = get_powermodels_variable(pm_result, :pg, bus_idx)

# Use in coupling constraint
# @constraint(model, sum(model[:g][i, t] for i in thermals_at_bus) == pg)
```
"""
function get_powermodels_variable(
    pm_result::Dict{String,Any},
    var_name::Symbol,
    index::Any,
)::Union{Float64,Nothing}
    # Check if variable is supported
    if !haskey(POWERMODELS_VAR_MAPPING, var_name)
        return nothing
    end

    # Get the component type and field name
    component_type, field_name = POWERMODELS_VAR_MAPPING[var_name]

    # Navigate to solution
    if !haskey(pm_result, "solution")
        return nothing
    end

    solution = pm_result["solution"]

    # Navigate to component type
    if !haskey(solution, component_type)
        return nothing
    end

    components = solution[component_type]

    # Convert index to string (PowerModels uses string keys)
    idx_str = string(index)

    # Check if index exists
    if !haskey(components, idx_str)
        return nothing
    end

    component = components[idx_str]

    # Check if field exists
    if !haskey(component, field_name)
        return nothing
    end

    return Float64(component[field_name])
end

end # module Variables
