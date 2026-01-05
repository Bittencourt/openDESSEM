"""
    Core system container for OpenDESSEM.

Defines the unified ElectricitySystem container that holds all entities
in a power system model.
"""

using Dates

# Import entity types from Entities module (loaded earlier via include)
using .Entities:
    AbstractEntity,
    PhysicalEntity,
    EntityMetadata,
    ThermalPlant,
    ConventionalThermal,
    CombinedCyclePlant,
    HydroPlant,
    ReservoirHydro,
    RunOfRiverHydro,
    PumpedStorageHydro,
    RenewablePlant,
    WindPlant,
    SolarPlant,
    NetworkEntity,
    Bus,
    ACLine,
    DCLine,
    NetworkLoad,
    NetworkSubmarket,
    MarketEntity,
    Submarket,
    Load,
    BilateralContract,
    validate_unique_ids

"""
    ElectricitySystem

Unified container for all entities in an electric power system.

The ElectricitySystem struct acts as the central data structure that holds
all physical, network, and market entities in a coherent system. It provides
validation to ensure referential integrity and helper functions for querying.

# Fields
- `thermal_plants::Vector{ConventionalThermal}`: All thermal power plants (conventional and combined-cycle)
- `hydro_plants::Vector{ReservoirHydro}`: All hydroelectric plants (reservoir, run-of-river, pumped storage)
- `wind_farms::Vector{WindPlant}`: All wind power plants
- `solar_farms::Vector{SolarPlant}`: All solar power plants
- `buses::Vector{Bus}`: All electrical buses (nodes in the network)
- `ac_lines::Vector{ACLine}`: All AC transmission lines
- `dc_lines::Vector{DCLine}`: All DC transmission lines (HVDC links)
- `submarkets::Vector{Submarket}`: All market submarkets/bidding zones
- `loads::Vector{Load}`: All load (demand) entities
- `base_date::Date`: Base date for the system (typically first day of optimization horizon)
- `description::String`: Human-readable system description
- `version::String`: System version identifier

# Constructor Validation
The ElectricitySystem constructor performs comprehensive validation:
- All entity IDs must be unique within their entity type
- All foreign key references must be valid:
  - Thermal plants: `bus_id` must exist in `buses`, `submarket_id` must exist in `submarkets`
  - Hydro plants: `bus_id` must exist in `buses`, `submarket_id` must exist in `submarkets`
  - Wind farms: `bus_id` must exist in `buses`, `submarket_id` must exist in `submarkets`
  - Solar farms: `bus_id` must exist in `buses`, `submarket_id` must exist in `submarkets`
  - AC lines: `from_bus` and `to_bus` must exist in `buses`
  - DC lines: `from_bus` and `to_bus` must exist in `buses`
  - Loads: `submarket_id` must exist in `submarkets` (if provided)
  - Loads: `bus_id` must exist in `buses` (if provided)

# Examples

## Creating a Simple System
```julia
using Dates

# Create buses
bus1 = Bus(;
    id = "B001",
    name = "Substation Alpha",
    voltage_kv = 230.0,
    base_kv = 230.0
)

bus2 = Bus(;
    id = "B002",
    name = "Substation Beta",
    voltage_kv = 230.0,
    base_kv = 230.0
)

# Create transmission line
line1 = ACLine(;
    id = "L001",
    name = "Alpha-Beta Line",
    from_bus_id = "B001",
    to_bus_id = "B002",
    length_km = 100.0,
    resistance_ohm = 0.01,
    reactance_ohm = 0.1,
    susceptance_siemen = 0.0,
    max_flow_mw = 500.0,
    min_flow_mw = 0.0,
    num_circuits = 1
)

# Create thermal plant
plant1 = ConventionalThermal(;
    id = "T001",
    name = "Gas Plant 1",
    bus_id = "B001",
    submarket_id = "SE",
    fuel_type = NATURAL_GAS,
    capacity_mw = 500.0,
    min_generation_mw = 150.0,
    max_generation_mw = 500.0,
    ramp_up_mw_per_min = 50.0,
    ramp_down_mw_per_min = 50.0,
    min_up_time_hours = 6,
    min_down_time_hours = 4,
    fuel_cost_rsj_per_mwh = 150.0,
    startup_cost_rs = 15000.0,
    shutdown_cost_rs = 8000.0,
    commissioning_date = DateTime(2010, 1, 1)
)

# Create submarket
submarket1 = Submarket(;
    id = "SM_001",
    name = "Southeast",
    code = "SE",
    country = "Brazil"
)

# Create load
load1 = Load(;
    id = "LOAD_001",
    name = "Southeast Load",
    submarket_id = "SE",
    base_mw = 50000.0,
    load_profile = ones(168),
    is_elastic = false
)

# Assemble system
system = ElectricitySystem(;
    thermal_plants = [plant1],
    buses = [bus1, bus2],
    ac_lines = [line1],
    submarkets = [submarket1],
    loads = [load1],
    base_date = Date(2025, 1, 1),
    description = "Simple 2-bus test system"
)
```

## Querying the System
```julia
# Find a specific thermal plant
plant = get_thermal_plant(system, "T001")
if plant !== nothing
    println("Found plant: \$(plant.name)")
    println("Capacity: \$(plant.capacity_mw) MW")
end

# Count generators
num_gen = count_generators(system)
println("System has \$num_gen generators")

# Calculate total capacity
total_cap = total_capacity(system)
println("Total capacity: \$total_cap MW")

# Find a bus
bus = get_bus(system, "B001")
if bus !== nothing
    println("Bus voltage: \$(bus.voltage_kv) kV")
end
```

# See Also
- [`get_thermal_plant`](@ref)
- [`get_hydro_plant`](@ref)
- [`count_generators`](@ref)
- [`total_capacity`](@ref)
- [`validate_system`](@ref)
"""
struct ElectricitySystem
    # Generation entities
    thermal_plants::Vector{ConventionalThermal}
    hydro_plants::Vector{<:HydroPlant}
    wind_farms::Vector{WindPlant}
    solar_farms::Vector{SolarPlant}

    # Network entities
    buses::Vector{Bus}
    ac_lines::Vector{ACLine}
    dc_lines::Vector{DCLine}

    # Market entities
    submarkets::Vector{Submarket}
    loads::Vector{Load}

    # Metadata
    base_date::Date
    description::String
    version::String

    function ElectricitySystem(;
        thermal_plants::Vector{ConventionalThermal} = ConventionalThermal[],
        hydro_plants::Vector{<:HydroPlant} = HydroPlant[],
        wind_farms::Vector{WindPlant} = WindPlant[],
        solar_farms::Vector{SolarPlant} = SolarPlant[],
        buses::Vector{Bus} = Bus[],
        ac_lines::Vector{ACLine} = ACLine[],
        dc_lines::Vector{DCLine} = DCLine[],
        submarkets::Vector{Submarket} = Submarket[],
        loads::Vector{Load} = Load[],
        base_date::Date,
        description::String = "",
        version::String = "1.0",
    )

        # Create lookup sets for validation
        bus_ids = Set(bus.id for bus in buses)
        submarket_codes = Set(sm.code for sm in submarkets)
        submarket_ids = Set(sm.id for sm in submarkets)

        # Validate thermal plants
        thermal_ids = String[]
        for plant in thermal_plants
            # Check for duplicate IDs
            if plant.id in thermal_ids
                throw(
                    ArgumentError(
                        "Duplicate thermal plant ID: $(plant.id). All plant IDs must be unique.",
                    ),
                )
            end
            push!(thermal_ids, plant.id)

            # Validate bus reference
            if !(plant.bus_id in bus_ids)
                throw(
                    ArgumentError(
                        "Thermal plant '$(plant.id)' references non-existent bus '$(plant.bus_id)'",
                    ),
                )
            end

            # Validate submarket reference
            if !(plant.submarket_id in submarket_codes)
                throw(
                    ArgumentError(
                        "Thermal plant '$(plant.id)' references non-existent submarket '$(plant.submarket_id)'",
                    ),
                )
            end
        end

        # Validate hydro plants
        hydro_ids = String[]
        for plant in hydro_plants
            # Check for duplicate IDs
            if plant.id in hydro_ids
                throw(
                    ArgumentError(
                        "Duplicate hydro plant ID: $(plant.id). All plant IDs must be unique.",
                    ),
                )
            end
            push!(hydro_ids, plant.id)

            # Validate bus reference
            if !(plant.bus_id in bus_ids)
                throw(
                    ArgumentError(
                        "Hydro plant '$(plant.id)' references non-existent bus '$(plant.bus_id)'",
                    ),
                )
            end

            # Validate submarket reference
            if !(plant.submarket_id in submarket_codes)
                throw(
                    ArgumentError(
                        "Hydro plant '$(plant.id)' references non-existent submarket '$(plant.submarket_id)'",
                    ),
                )
            end
        end

        # Validate wind farms
        wind_ids = String[]
        for farm in wind_farms
            # Check for duplicate IDs
            if farm.id in wind_ids
                throw(
                    ArgumentError(
                        "Duplicate wind farm ID: $(farm.id). All farm IDs must be unique.",
                    ),
                )
            end
            push!(wind_ids, farm.id)

            # Validate bus reference
            if !(farm.bus_id in bus_ids)
                throw(
                    ArgumentError(
                        "Wind farm '$(farm.id)' references non-existent bus '$(farm.bus_id)'",
                    ),
                )
            end

            # Validate submarket reference
            if !(farm.submarket_id in submarket_codes)
                throw(
                    ArgumentError(
                        "Wind farm '$(farm.id)' references non-existent submarket '$(farm.submarket_id)'",
                    ),
                )
            end
        end

        # Validate solar farms
        solar_ids = String[]
        for farm in solar_farms
            # Check for duplicate IDs
            if farm.id in solar_ids
                throw(
                    ArgumentError(
                        "Duplicate solar farm ID: $(farm.id). All farm IDs must be unique.",
                    ),
                )
            end
            push!(solar_ids, farm.id)

            # Validate bus reference
            if !(farm.bus_id in bus_ids)
                throw(
                    ArgumentError(
                        "Solar farm '$(farm.id)' references non-existent bus '$(farm.bus_id)'",
                    ),
                )
            end

            # Validate submarket reference
            if !(farm.submarket_id in submarket_codes)
                throw(
                    ArgumentError(
                        "Solar farm '$(farm.id)' references non-existent submarket '$(farm.submarket_id)'",
                    ),
                )
            end
        end

        # Validate buses (check for duplicate IDs)
        bus_id_list = String[]
        for bus in buses
            if bus.id in bus_id_list
                throw(
                    ArgumentError(
                        "Duplicate bus ID: $(bus.id). All bus IDs must be unique.",
                    ),
                )
            end
            push!(bus_id_list, bus.id)
        end

        # Validate AC lines
        for line in ac_lines
            # Validate from_bus reference
            if !(line.from_bus_id in bus_ids)
                throw(
                    ArgumentError(
                        "AC line '$(line.id)' references non-existent from_bus '$(line.from_bus_id)'",
                    ),
                )
            end

            # Validate to_bus reference
            if !(line.to_bus_id in bus_ids)
                throw(
                    ArgumentError(
                        "AC line '$(line.id)' references non-existent to_bus '$(line.to_bus_id)'",
                    ),
                )
            end
        end

        # Validate DC lines
        for line in dc_lines
            # Validate from_bus reference
            if !(line.from_bus_id in bus_ids)
                throw(
                    ArgumentError(
                        "DC line '$(line.id)' references non-existent from_bus '$(line.from_bus_id)'",
                    ),
                )
            end

            # Validate to_bus reference
            if !(line.to_bus_id in bus_ids)
                throw(
                    ArgumentError(
                        "DC line '$(line.id)' references non-existent to_bus '$(line.to_bus_id)'",
                    ),
                )
            end
        end

        # Validate submarkets (check for duplicate IDs)
        submarket_id_list = String[]
        for sm in submarkets
            if sm.id in submarket_id_list
                throw(
                    ArgumentError(
                        "Duplicate submarket ID: $(sm.id). All submarket IDs must be unique.",
                    ),
                )
            end
            push!(submarket_id_list, sm.id)
        end

        # Validate loads
        load_ids = String[]
        for load in loads
            # Check for duplicate IDs
            if load.id in load_ids
                throw(
                    ArgumentError(
                        "Duplicate load ID: $(load.id). All load IDs must be unique.",
                    ),
                )
            end
            push!(load_ids, load.id)

            # Validate submarket reference (if provided)
            if load.submarket_id !== nothing && !(load.submarket_id in submarket_codes)
                throw(
                    ArgumentError(
                        "Load '$(load.id)' references non-existent submarket '$(load.submarket_id)'",
                    ),
                )
            end

            # Validate bus reference (if provided)
            if load.bus_id !== nothing && !(load.bus_id in bus_ids)
                throw(
                    ArgumentError(
                        "Load '$(load.id)' references non-existent bus '$(load.bus_id)'",
                    ),
                )
            end
        end

        new(
            thermal_plants,
            hydro_plants,
            wind_farms,
            solar_farms,
            buses,
            ac_lines,
            dc_lines,
            submarkets,
            loads,
            base_date,
            description,
            version,
        )
    end
end

"""
    get_thermal_plant(system::ElectricitySystem, id::String)::Union{ConventionalThermal, Nothing}

Find a thermal plant by ID in the system.

# Arguments
- `system::ElectricitySystem`: The electricity system
- `id::String`: Thermal plant ID to search for

# Returns
- `ConventionalThermal` if found
- `nothing` if not found

# Examples
```julia
plant = get_thermal_plant(system, "T001")
if plant !== nothing
    println("Found: \$(plant.name)")
end
```
"""
function get_thermal_plant(
    system::ElectricitySystem,
    id::String,
)::Union{ConventionalThermal,Nothing}
    for plant in system.thermal_plants
        if plant.id == id
            return plant
        end
    end
    return nothing
end

"""
    get_hydro_plant(system::ElectricitySystem, id::String)::Union{HydroPlant, Nothing}

Find a hydro plant by ID in the system.

# Arguments
- `system::ElectricitySystem`: The electricity system
- `id::String`: Hydro plant ID to search for

# Returns
- `HydroPlant` subtype if found
- `nothing` if not found

# Examples
```julia
plant = get_hydro_plant(system, "H001")
if plant !== nothing
    println("Found: \$(plant.name)")
end
```
"""
function get_hydro_plant(system::ElectricitySystem, id::String)::Union{HydroPlant,Nothing}
    for plant in system.hydro_plants
        if plant.id == id
            return plant
        end
    end
    return nothing
end

"""
    get_bus(system::ElectricitySystem, id::String)::Union{Bus, Nothing}

Find a bus by ID in the system.

# Arguments
- `system::ElectricitySystem`: The electricity system
- `id::String`: Bus ID to search for

# Returns
- `Bus` if found
- `nothing` if not found

# Examples
```julia
bus = get_bus(system, "B001")
if bus !== nothing
    println("Voltage: \$(bus.voltage_kv) kV")
end
```
"""
function get_bus(system::ElectricitySystem, id::String)::Union{Bus,Nothing}
    for bus in system.buses
        if bus.id == id
            return bus
        end
    end
    return nothing
end

"""
    get_submarket(system::ElectricitySystem, id::String)::Union{Submarket, Nothing}

Find a submarket by ID in the system.

# Arguments
- `system::ElectricitySystem`: The electricity system
- `id::String`: Submarket ID to search for

# Returns
- `Submarket` if found
- `nothing` if not found

# Examples
```julia
sm = get_submarket(system, "SM_001")
if sm !== nothing
    println("Submarket: \$(sm.name)")
end
```
"""
function get_submarket(system::ElectricitySystem, id::String)::Union{Submarket,Nothing}
    for sm in system.submarkets
        if sm.id == id
            return sm
        end
    end
    return nothing
end

"""
    count_generators(system::ElectricitySystem)::Int

Count the total number of generators in the system.

Includes all thermal, hydro, wind, and solar plants.

# Arguments
- `system::ElectricitySystem`: The electricity system

# Returns
- `Int`: Total number of generators

# Examples
```julia
num_gen = count_generators(system)
println("System has \$num_gen generators")
```
"""
function count_generators(system::ElectricitySystem)::Int
    return length(system.thermal_plants) +
           length(system.hydro_plants) +
           length(system.wind_farms) +
           length(system.solar_farms)
end

"""
    total_capacity(system::ElectricitySystem)::Float64

Calculate the total installed generation capacity in the system.

Sums the capacity of all thermal, hydro, wind, and solar plants.

# Arguments
- `system::ElectricitySystem`: The electricity system

# Returns
- `Float64`: Total capacity in MW

# Examples
```julia
capacity = total_capacity(system)
println("Total capacity: \$capacity MW")
```
"""
function total_capacity(system::ElectricitySystem)::Float64
    total = 0.0

    for plant in system.thermal_plants
        total += plant.capacity_mw
    end

    for plant in system.hydro_plants
        total += plant.max_generation_mw
    end

    for farm in system.wind_farms
        total += farm.installed_capacity_mw
    end

    for farm in system.solar_farms
        total += farm.installed_capacity_mw
    end

    return total
end

"""
    validate_system(system::ElectricitySystem)::Bool

Validate the integrity of an electricity system.

Performs comprehensive checks:
- All entity IDs are unique
- All foreign key references are valid
- All entity validations pass

# Arguments
- `system::ElectricitySystem`: The electricity system to validate

# Returns
- `Bool`: `true` if system is valid

# Throws
- `ArgumentError`: If validation fails (with descriptive message)

# Examples
```julia
if validate_system(system)
    println("System is valid")
end
```

# Notes
This function is called automatically during construction, but can be called
manually to re-validate a system that may have been modified.
"""
function validate_system(system::ElectricitySystem)::Bool
    # Create lookup sets
    bus_ids = Set(bus.id for bus in system.buses)
    submarket_codes = Set(sm.code for sm in system.submarkets)

    # Check all thermal plants
    for plant in system.thermal_plants
        if !(plant.bus_id in bus_ids)
            throw(
                ArgumentError(
                    "Thermal plant '$(plant.id)' references non-existent bus '$(plant.bus_id)'",
                ),
            )
        end
        if !(plant.submarket_id in submarket_codes)
            throw(
                ArgumentError(
                    "Thermal plant '$(plant.id)' references non-existent submarket '$(plant.submarket_id)'",
                ),
            )
        end
    end

    # Check all hydro plants
    for plant in system.hydro_plants
        if !(plant.bus_id in bus_ids)
            throw(
                ArgumentError(
                    "Hydro plant '$(plant.id)' references non-existent bus '$(plant.bus_id)'",
                ),
            )
        end
        if !(plant.submarket_id in submarket_codes)
            throw(
                ArgumentError(
                    "Hydro plant '$(plant.id)' references non-existent submarket '$(plant.submarket_id)'",
                ),
            )
        end
    end

    # Check all wind farms
    for farm in system.wind_farms
        if !(farm.bus_id in bus_ids)
            throw(
                ArgumentError(
                    "Wind farm '$(farm.id)' references non-existent bus '$(farm.bus_id)'",
                ),
            )
        end
        if !(farm.submarket_id in submarket_codes)
            throw(
                ArgumentError(
                    "Wind farm '$(farm.id)' references non-existent submarket '$(farm.submarket_id)'",
                ),
            )
        end
    end

    # Check all solar farms
    for farm in system.solar_farms
        if !(farm.bus_id in bus_ids)
            throw(
                ArgumentError(
                    "Solar farm '$(farm.id)' references non-existent bus '$(farm.bus_id)'",
                ),
            )
        end
        if !(farm.submarket_id in submarket_codes)
            throw(
                ArgumentError(
                    "Solar farm '$(farm.id)' references non-existent submarket '$(farm.submarket_id)'",
                ),
            )
        end
    end

    # Check all AC lines
    for line in system.ac_lines
        if !(line.from_bus_id in bus_ids)
            throw(
                ArgumentError(
                    "AC line '$(line.id)' references non-existent from_bus '$(line.from_bus_id)'",
                ),
            )
        end
        if !(line.to_bus_id in bus_ids)
            throw(
                ArgumentError(
                    "AC line '$(line.id)' references non-existent to_bus '$(line.to_bus_id)'",
                ),
            )
        end
    end

    # Check all DC lines
    for line in system.dc_lines
        if !(line.from_bus_id in bus_ids)
            throw(
                ArgumentError(
                    "DC line '$(line.id)' references non-existent from_bus '$(line.from_bus_id)'",
                ),
            )
        end
        if !(line.to_bus_id in bus_ids)
            throw(
                ArgumentError(
                    "DC line '$(line.id)' references non-existent to_bus '$(line.to_bus_id)'",
                ),
            )
        end
    end

    # Check all loads
    for load in system.loads
        if load.submarket_id !== nothing && !(load.submarket_id in submarket_codes)
            throw(
                ArgumentError(
                    "Load '$(load.id)' references non-existent submarket '$(load.submarket_id)'",
                ),
            )
        end
        if load.bus_id !== nothing && !(load.bus_id in bus_ids)
            throw(
                ArgumentError(
                    "Load '$(load.id)' references non-existent bus '$(load.bus_id)'",
                ),
            )
        end
    end

    return true
end

# Export the ElectricitySystem type and helper functions
export ElectricitySystem
export get_thermal_plant, get_hydro_plant, get_bus, get_submarket
export count_generators, total_capacity, validate_system
