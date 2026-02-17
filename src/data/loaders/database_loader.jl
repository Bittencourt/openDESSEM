"""
    DatabaseLoader - PostgreSQL Data Loader for OpenDESSEM

This module provides functions to load OpenDESSEM entities from PostgreSQL databases
used by ONS (Operador Nacional do Sistema Elétrico) and CCEE (Câmara de Comercialização
de Energia Elétrica).

# Database Schema

The loader expects the following database schema:

```sql
-- Thermal plants table
CREATE TABLE thermal_plants (
    id VARCHAR PRIMARY KEY,
    name VARCHAR NOT NULL,
    bus_id VARCHAR NOT NULL,
    submarket_id VARCHAR NOT NULL,
    fuel_type VARCHAR NOT NULL,
    capacity_mw FLOAT NOT NULL,
    min_generation_mw FLOAT NOT NULL DEFAULT 0,
    max_generation_mw FLOAT NOT NULL,
    ramp_up_mw_per_min FLOAT NOT NULL DEFAULT 0,
    ramp_down_mw_per_min FLOAT NOT NULL DEFAULT 0,
    min_up_time_hours INT NOT NULL DEFAULT 0,
    min_down_time_hours INT NOT NULL DEFAULT 0,
    fuel_cost_rsj_per_mwh FLOAT NOT NULL DEFAULT 0,
    startup_cost_rs FLOAT NOT NULL DEFAULT 0,
    shutdown_cost_rs FLOAT NOT NULL DEFAULT 0,
    commissioning_date TIMESTAMP,
    num_units INT NOT NULL DEFAULT 1,
    must_run BOOLEAN NOT NULL DEFAULT FALSE
);

-- Hydro plants table
CREATE TABLE hydro_plants (
    id VARCHAR PRIMARY KEY,
    name VARCHAR NOT NULL,
    bus_id VARCHAR NOT NULL,
    submarket_id VARCHAR NOT NULL,
    max_volume_hm3 FLOAT NOT NULL,
    min_volume_hm3 FLOAT NOT NULL DEFAULT 0,
    initial_volume_hm3 FLOAT NOT NULL,
    max_outflow_m3_per_s FLOAT NOT NULL,
    min_outflow_m3_per_s FLOAT NOT NULL DEFAULT 0,
    max_generation_mw FLOAT NOT NULL,
    min_generation_mw FLOAT NOT NULL DEFAULT 0,
    efficiency FLOAT NOT NULL,
    water_value_rs_per_hm3 FLOAT NOT NULL DEFAULT 0,
    subsystem_code INT NOT NULL,
    initial_volume_percent FLOAT NOT NULL,
    must_run BOOLEAN NOT NULL DEFAULT FALSE,
    downstream_plant_id VARCHAR,
    water_travel_time_hours FLOAT
);

-- Buses table
CREATE TABLE buses (
    id VARCHAR PRIMARY KEY,
    name VARCHAR NOT NULL,
    voltage_kv FLOAT NOT NULL,
    base_kv FLOAT NOT NULL,
    dc_bus BOOLEAN NOT NULL DEFAULT FALSE,
    is_reference BOOLEAN NOT NULL DEFAULT FALSE,
    area_id VARCHAR,
    zone_id VARCHAR,
    latitude FLOAT,
    longitude FLOAT
);

-- AC transmission lines table
CREATE TABLE ac_lines (
    id VARCHAR PRIMARY KEY,
    name VARCHAR NOT NULL,
    from_bus_id VARCHAR NOT NULL,
    to_bus_id VARCHAR NOT NULL,
    length_km FLOAT NOT NULL,
    resistance_ohm FLOAT NOT NULL,
    reactance_ohm FLOAT NOT NULL,
    susceptance_siemen FLOAT NOT NULL DEFAULT 0,
    max_flow_mw FLOAT NOT NULL,
    min_flow_mw FLOAT NOT NULL DEFAULT 0,
    num_circuits INT NOT NULL DEFAULT 1,
    FOREIGN KEY (from_bus_id) REFERENCES buses(id),
    FOREIGN KEY (to_bus_id) REFERENCES buses(id)
);

-- DC lines table
CREATE TABLE dc_lines (
    id VARCHAR PRIMARY KEY,
    name VARCHAR NOT NULL,
    from_bus_id VARCHAR NOT NULL,
    to_bus_id VARCHAR NOT NULL,
    max_flow_mw FLOAT NOT NULL,
    min_flow_mw FLOAT NOT NULL DEFAULT 0,
    FOREIGN KEY (from_bus_id) REFERENCES buses(id),
    FOREIGN KEY (to_bus_id) REFERENCES buses(id)
);

-- Submarkets table
CREATE TABLE submarkets (
    id VARCHAR PRIMARY KEY,
    name VARCHAR NOT NULL,
    code VARCHAR NOT NULL UNIQUE,
    country VARCHAR NOT NULL,
    description VARCHAR
);

-- Loads table
CREATE TABLE loads (
    id VARCHAR PRIMARY KEY,
    name VARCHAR NOT NULL,
    submarket_id VARCHAR,
    bus_id VARCHAR,
    base_mw FLOAT NOT NULL,
    is_elastic BOOLEAN NOT NULL DEFAULT FALSE,
    elasticity FLOAT NOT NULL DEFAULT 0,
    FOREIGN KEY (submarket_id) REFERENCES submarkets(code),
    FOREIGN KEY (bus_id) REFERENCES buses(id)
);

-- Load profiles time series (optional)
CREATE TABLE load_profiles (
    load_id VARCHAR NOT NULL,
    period INT NOT NULL,
    value FLOAT NOT NULL,
    PRIMARY KEY (load_id, period),
    FOREIGN KEY (load_id) REFERENCES loads(id)
);
```

# Main Functions

- `DatabaseLoader(...)`: Create a database loader configuration
- `load_from_database(loader)`: Load complete system from database
- `load_thermal_plants(conn, schema)`: Load thermal plants only
- `load_hydro_plants(conn, schema)`: Load hydro plants only
- `load_network(conn, schema)`: Load network (buses, lines)
- `load_market(conn, schema)`: Load market entities (submarkets, loads)

# Example

```julia
using OpenDESSEM

# Create loader configuration
loader = DatabaseLoader(;
    host = "localhost",
    port = 5432,
    dbname = "dessem_db",
    user = "ons_user",
    password = "secret",
    schema = "dessem_2026"
)

# Load complete system
system = load_from_database(loader)

println("Loaded \$(length(system.thermal_plants)) thermal plants")
println("Loaded \$(length(system.hydro_plants)) hydro plants")
println("Loaded \$(length(system.buses)) buses")
```

# See Also
- `DessemLoader` for loading DESSEM files
"""
module DatabaseLoaders

using Dates
using LibPQ
using DataFrames

# Import OpenDESSEM types
using ..Entities:
    ConventionalThermal,
    ReservoirHydro,
    HydroPlant,
    WindPlant,
    SolarPlant,
    Bus,
    ACLine,
    DCLine,
    Submarket,
    Load,
    FuelType,
    NATURAL_GAS,
    COAL,
    FUEL_OIL,
    DIESEL,
    NUCLEAR,
    BIOMASS,
    BIOGAS,
    OTHER,
    EntityMetadata

# Import ElectricitySystem from parent
import ..ElectricitySystem

export DatabaseLoader,
    load_from_database,
    load_thermal_plants,
    load_hydro_plants,
    load_renewable_plants,
    load_network,
    load_market,
    validate_loaded_data

# =============================================================================
# Database Loader Configuration
# =============================================================================#

"""
    DatabaseLoader

Configuration for PostgreSQL database connection and data loading.

# Fields
- `host::String`: Database host (default: "localhost")
- `port::Int`: Database port (default: 5432)
- `dbname::String`: Database name
- `user::String`: Database user
- `password::String`: Database password
- `schema::String`: Database schema (default: "public")
- `verbose::Bool`: Enable verbose logging (default: false)
- `timeout::Int`: Connection timeout in seconds (default: 30)

# Examples
```julia
loader = DatabaseLoader(;
    host = "localhost",
    port = 5432,
    dbname = "dessem",
    user = "ons",
    password = "secret",
    schema = "dessem_2026",
    verbose = true
)
```
"""
struct DatabaseLoader
    host::String
    port::Int
    dbname::String
    user::String
    password::String
    schema::String
    verbose::Bool
    timeout::Int

    function DatabaseLoader(;
        host::String = "localhost",
        port::Int = 5432,
        dbname::String,
        user::String,
        password::String,
        schema::String = "public",
        verbose::Bool = false,
        timeout::Int = 30,
    )
        new(host, port, dbname, user, password, schema, verbose, timeout)
    end
end

"""
    get_connection_string(loader::DatabaseLoader) -> String

Generate PostgreSQL connection string from loader configuration.

# Arguments
- `loader::DatabaseLoader`: Database loader configuration

# Returns
- `String`: PostgreSQL connection string
"""
function get_connection_string(loader::DatabaseLoader)::String
    return "host=$(loader.host) port=$(loader.port) dbname=$(loader.dbname) " *
           "user=$(loader.user) password=$(loader.password) " *
           "connect_timeout=$(loader.timeout)"
end

# =============================================================================
# SQL Query Generation Functions
# =============================================================================#

"""
    generate_thermal_plants_query(schema::String) -> String

Generate SQL query to select thermal plants.

# Arguments
- `schema::String`: Database schema name

# Returns
- `String`: SQL SELECT query
"""
function generate_thermal_plants_query(schema::String)::String
    return """
    SELECT
        id, name, bus_id, submarket_id, fuel_type,
        capacity_mw, min_generation_mw, max_generation_mw,
        ramp_up_mw_per_min, ramp_down_mw_per_min,
        min_up_time_hours, min_down_time_hours,
        fuel_cost_rsj_per_mwh, startup_cost_rs, shutdown_cost_rs,
        commissioning_date, num_units, must_run
    FROM $(schema).thermal_plants
    ORDER BY id
    """
end

"""
    generate_hydro_plants_query(schema::String) -> String

Generate SQL query to select hydro plants.

# Arguments
- `schema::String`: Database schema name

# Returns
- `String`: SQL SELECT query
"""
function generate_hydro_plants_query(schema::String)::String
    return """
    SELECT
        id, name, bus_id, submarket_id,
        max_volume_hm3, min_volume_hm3, initial_volume_hm3,
        max_outflow_m3_per_s, min_outflow_m3_per_s,
        max_generation_mw, min_generation_mw,
        efficiency, water_value_rs_per_hm3,
        subsystem_code, initial_volume_percent,
        must_run, downstream_plant_id, water_travel_time_hours
    FROM $(schema).hydro_plants
    ORDER BY id
    """
end

"""
    generate_wind_plants_query(schema::String) -> String

Generate SQL query to select wind plants.

# Arguments
- `schema::String`: Database schema name

# Returns
- `String`: SQL SELECT query
"""
function generate_wind_plants_query(schema::String)::String
    return """
    SELECT
        id, name, bus_id, submarket_id,
        installed_capacity_mw, capacity_factor,
        min_generation_mw, max_generation_mw,
        ramp_up_mw_per_min, ramp_down_mw_per_min,
        curtailment_allowed, forced_outage_rate,
        is_dispatchable, commissioning_date, num_turbines, must_run
    FROM $(schema).wind_plants
    ORDER BY id
    """
end

"""
    generate_solar_plants_query(schema::String) -> String

Generate SQL query to select solar plants.

# Arguments
- `schema::String`: Database schema name

# Returns
- `String`: SQL SELECT query
"""
function generate_solar_plants_query(schema::String)::String
    return """
    SELECT
        id, name, bus_id, submarket_id,
        installed_capacity_mw, capacity_factor,
        min_generation_mw, max_generation_mw,
        ramp_up_mw_per_min, ramp_down_mw_per_min,
        curtailment_allowed, forced_outage_rate,
        is_dispatchable, commissioning_date, num_panels, must_run
    FROM $(schema).solar_plants
    ORDER BY id
    """
end

"""
    generate_buses_query(schema::String) -> String

Generate SQL query to select buses.

# Arguments
- `schema::String`: Database schema name

# Returns
- `String`: SQL SELECT query
"""
function generate_buses_query(schema::String)::String
    return """
    SELECT
        id, name, voltage_kv, base_kv,
        dc_bus, is_reference, area_id, zone_id,
        latitude, longitude
    FROM $(schema).buses
    ORDER BY id
    """
end

"""
    generate_ac_lines_query(schema::String) -> String

Generate SQL query to select AC transmission lines.

# Arguments
- `schema::String`: Database schema name

# Returns
- `String`: SQL SELECT query
"""
function generate_ac_lines_query(schema::String)::String
    return """
    SELECT
        id, name, from_bus_id, to_bus_id,
        length_km, resistance_ohm, reactance_ohm,
        susceptance_siemen, max_flow_mw, min_flow_mw,
        num_circuits
    FROM $(schema).ac_lines
    ORDER BY id
    """
end

"""
    generate_dc_lines_query(schema::String) -> String

Generate SQL query to select DC transmission lines.

# Arguments
- `schema::String`: Database schema name

# Returns
- `String`: SQL SELECT query
"""
function generate_dc_lines_query(schema::String)::String
    return """
    SELECT
        id, name, from_bus_id, to_bus_id,
        max_flow_mw, min_flow_mw
    FROM $(schema).dc_lines
    ORDER BY id
    """
end

"""
    generate_submarkets_query(schema::String) -> String

Generate SQL query to select submarkets.

# Arguments
- `schema::String`: Database schema name

# Returns
- `String`: SQL SELECT query
"""
function generate_submarkets_query(schema::String)::String
    return """
    SELECT
        id, name, code, country, description
    FROM $(schema).submarkets
    ORDER BY code
    """
end

"""
    generate_loads_query(schema::String) -> String

Generate SQL query to select loads.

# Arguments
- `schema::String`: Database schema name

# Returns
- `String`: SQL SELECT query
"""
function generate_loads_query(schema::String)::String
    return """
    SELECT
        id, name, submarket_id, bus_id,
        base_mw, is_elastic, elasticity
    FROM $(schema).loads
    ORDER BY id
    """
end

"""
    generate_load_profile_query(schema::String, load_id::String) -> String

Generate SQL query to select load profile time series.

# Arguments
- `schema::String`: Database schema name
- `load_id::String`: Load ID

# Returns
- `String`: SQL SELECT query
"""
function generate_load_profile_query(schema::String, load_id::String)::String
    return """
    SELECT period, value
    FROM $(schema).load_profiles
    WHERE load_id = '$(escape_string(load_id))'
    ORDER BY period
    """
end

# =============================================================================
# Row to Entity Conversion Functions
# =============================================================================#

"""
    parse_fuel_type(fuel_str::String) -> FuelType

Convert fuel type string to FuelType enum.

# Arguments
- `fuel_str::String`: Fuel type string (e.g., "natural_gas", "COAL")

# Returns
- `FuelType`: Corresponding FuelType enum value
"""
function parse_fuel_type(fuel_str::String)::FuelType
    normalized = lowercase(strip(fuel_str))

    fuel_map = Dict{String,FuelType}(
        "natural_gas" => NATURAL_GAS,
        "gas" => NATURAL_GAS,
        "coal" => COAL,
        "fuel_oil" => FUEL_OIL,
        "oil" => FUEL_OIL,
        "diesel" => DIESEL,
        "nuclear" => NUCLEAR,
        "biomass" => BIOMASS,
        "biogas" => BIOGAS,
    )

    return get(fuel_map, normalized, OTHER)
end

"""
    row_to_thermal_plant(row) -> ConventionalThermal

Convert a database row to ConventionalThermal entity.

# Arguments
- `row`: NamedTuple or DataFrameRow from database query

# Returns
- `ConventionalThermal`: Thermal plant entity

# Throws
- `ArgumentError`: if required fields are missing or invalid
"""
function row_to_thermal_plant(row)::ConventionalThermal
    # Extract all fields with defaults for missing optional fields
    id = coalesce(row.id, "")
    name = coalesce(row.name, "")
    bus_id = coalesce(row.bus_id, "")
    submarket_id = coalesce(row.submarket_id, "")

    # Parse fuel type
    fuel_type_str = coalesce(row.fuel_type, "other")
    fuel_type = parse_fuel_type(fuel_type_str)

    # Extract numeric fields
    capacity_mw = coalesce(row.capacity_mw, 0.0)
    min_generation_mw = coalesce(row.min_generation_mw, 0.0)
    max_generation_mw = coalesce(row.max_generation_mw, capacity_mw)
    ramp_up_mw_per_min = coalesce(row.ramp_up_mw_per_min, 0.0)
    ramp_down_mw_per_min = coalesce(row.ramp_down_mw_per_min, 0.0)

    # Extract time constraints
    min_up_time_hours = coalesce(row.min_up_time_hours, 0)
    min_down_time_hours = coalesce(row.min_down_time_hours, 0)

    # Extract costs
    fuel_cost_rsj_per_mwh = coalesce(row.fuel_cost_rsj_per_mwh, 0.0)
    startup_cost_rs = coalesce(row.startup_cost_rs, 0.0)
    shutdown_cost_rs = coalesce(row.shutdown_cost_rs, 0.0)

    # Extract commissioning date
    commissioning_date =
        if hasproperty(row, :commissioning_date) && row.commissioning_date !== nothing
            row.commissioning_date
        else
            DateTime(2000, 1, 1)
        end

    # Extract other fields
    num_units = coalesce(row.num_units, 1)
    must_run = coalesce(row.must_run, false)

    return ConventionalThermal(;
        id = id,
        name = name,
        bus_id = bus_id,
        submarket_id = submarket_id,
        fuel_type = fuel_type,
        capacity_mw = capacity_mw,
        min_generation_mw = min_generation_mw,
        max_generation_mw = max_generation_mw,
        ramp_up_mw_per_min = ramp_up_mw_per_min,
        ramp_down_mw_per_min = ramp_down_mw_per_min,
        min_up_time_hours = min_up_time_hours,
        min_down_time_hours = min_down_time_hours,
        fuel_cost_rsj_per_mwh = fuel_cost_rsj_per_mwh,
        startup_cost_rs = startup_cost_rs,
        shutdown_cost_rs = shutdown_cost_rs,
        commissioning_date = commissioning_date,
        num_units = num_units,
        must_run = must_run,
    )
end

"""
    row_to_hydro_plant(row) -> ReservoirHydro

Convert a database row to ReservoirHydro entity.

# Arguments
- `row`: NamedTuple or DataFrameRow from database query

# Returns
- `ReservoirHydro`: Hydro plant entity
"""
function row_to_hydro_plant(row)::ReservoirHydro
    id = coalesce(row.id, "")
    name = coalesce(row.name, "")
    bus_id = coalesce(row.bus_id, "")
    submarket_id = coalesce(row.submarket_id, "")

    max_volume_hm3 = coalesce(row.max_volume_hm3, 0.0)
    min_volume_hm3 = coalesce(row.min_volume_hm3, 0.0)
    initial_volume_hm3 = coalesce(row.initial_volume_hm3, min_volume_hm3)

    max_outflow_m3_per_s = coalesce(row.max_outflow_m3_per_s, 0.0)
    min_outflow_m3_per_s = coalesce(row.min_outflow_m3_per_s, 0.0)

    max_generation_mw = coalesce(row.max_generation_mw, 0.0)
    min_generation_mw = coalesce(row.min_generation_mw, 0.0)

    efficiency = coalesce(row.efficiency, 0.9)
    water_value_rs_per_hm3 = coalesce(row.water_value_rs_per_hm3, 0.0)

    subsystem_code = coalesce(row.subsystem_code, 1)
    initial_volume_percent = coalesce(row.initial_volume_percent, 50.0)

    must_run = coalesce(row.must_run, false)
    downstream_plant_id = if hasproperty(row, :downstream_plant_id)
        row.downstream_plant_id
    else
        nothing
    end

    water_travel_time_hours = if hasproperty(row, :water_travel_time_hours)
        row.water_travel_time_hours
    else
        nothing
    end

    return ReservoirHydro(;
        id = id,
        name = name,
        bus_id = bus_id,
        submarket_id = submarket_id,
        max_volume_hm3 = max_volume_hm3,
        min_volume_hm3 = min_volume_hm3,
        initial_volume_hm3 = initial_volume_hm3,
        max_outflow_m3_per_s = max_outflow_m3_per_s,
        min_outflow_m3_per_s = min_outflow_m3_per_s,
        max_generation_mw = max_generation_mw,
        min_generation_mw = min_generation_mw,
        efficiency = efficiency,
        water_value_rs_per_hm3 = water_value_rs_per_hm3,
        subsystem_code = subsystem_code,
        initial_volume_percent = initial_volume_percent,
        must_run = must_run,
        downstream_plant_id = downstream_plant_id,
        water_travel_time_hours = water_travel_time_hours,
    )
end

"""
    row_to_bus(row) -> Bus

Convert a database row to Bus entity.

# Arguments
- `row`: NamedTuple or DataFrameRow from database query

# Returns
- `Bus`: Bus entity
"""
function row_to_bus(row)::Bus
    id = coalesce(row.id, "")
    name = coalesce(row.name, "")
    voltage_kv = coalesce(row.voltage_kv, 230.0)
    base_kv = coalesce(row.base_kv, voltage_kv)

    dc_bus = coalesce(row.dc_bus, false)
    is_reference = coalesce(row.is_reference, false)

    area_id = if hasproperty(row, :area_id)
        row.area_id
    else
        nothing
    end

    zone_id = if hasproperty(row, :zone_id)
        row.zone_id
    else
        nothing
    end

    latitude = if hasproperty(row, :latitude)
        row.latitude
    else
        nothing
    end

    longitude = if hasproperty(row, :longitude)
        row.longitude
    else
        nothing
    end

    return Bus(;
        id = id,
        name = name,
        voltage_kv = voltage_kv,
        base_kv = base_kv,
        dc_bus = dc_bus,
        is_reference = is_reference,
        area_id = area_id,
        zone_id = zone_id,
        latitude = latitude,
        longitude = longitude,
    )
end

"""
    row_to_ac_line(row) -> ACLine

Convert a database row to ACLine entity.

# Arguments
- `row`: NamedTuple or DataFrameRow from database query

# Returns
- `ACLine`: AC transmission line entity
"""
function row_to_ac_line(row)::ACLine
    id = coalesce(row.id, "")
    name = coalesce(row.name, "")
    from_bus_id = coalesce(row.from_bus_id, "")
    to_bus_id = coalesce(row.to_bus_id, "")

    length_km = coalesce(row.length_km, 0.0)
    resistance_ohm = coalesce(row.resistance_ohm, 0.0)
    reactance_ohm = coalesce(row.reactance_ohm, 0.0)
    susceptance_siemen = coalesce(row.susceptance_siemen, 0.0)

    max_flow_mw = coalesce(row.max_flow_mw, 0.0)
    min_flow_mw = coalesce(row.min_flow_mw, 0.0)

    num_circuits = coalesce(row.num_circuits, 1)

    return ACLine(;
        id = id,
        name = name,
        from_bus_id = from_bus_id,
        to_bus_id = to_bus_id,
        length_km = length_km,
        resistance_ohm = resistance_ohm,
        reactance_ohm = reactance_ohm,
        susceptance_siemen = susceptance_siemen,
        max_flow_mw = max_flow_mw,
        min_flow_mw = min_flow_mw,
        num_circuits = num_circuits,
    )
end

"""
    row_to_dc_line(row) -> DCLine

Convert a database row to DCLine entity.

# Arguments
- `row`: NamedTuple or DataFrameRow from database query

# Returns
- `DCLine`: DC transmission line entity
"""
function row_to_dc_line(row)::DCLine
    id = coalesce(row.id, "")
    name = coalesce(row.name, "")
    from_bus_id = coalesce(row.from_bus_id, "")
    to_bus_id = coalesce(row.to_bus_id, "")

    max_flow_mw = coalesce(row.max_flow_mw, 0.0)
    min_flow_mw = coalesce(row.min_flow_mw, 0.0)

    return DCLine(;
        id = id,
        name = name,
        from_bus_id = from_bus_id,
        to_bus_id = to_bus_id,
        max_flow_mw = max_flow_mw,
        min_flow_mw = min_flow_mw,
    )
end

"""
    row_to_submarket(row) -> Submarket

Convert a database row to Submarket entity.

# Arguments
- `row`: NamedTuple or DataFrameRow from database query

# Returns
- `Submarket`: Submarket entity
"""
function row_to_submarket(row)::Submarket
    id = coalesce(row.id, "")
    name = coalesce(row.name, "")
    code = coalesce(row.code, "")
    country = coalesce(row.country, "")

    description = if hasproperty(row, :description)
        coalesce(row.description, "")
    else
        ""
    end

    return Submarket(;
        id = id,
        name = name,
        code = code,
        country = country,
        description = description,
    )
end

"""
    row_to_load(row, load_profile::Vector{Float64}) -> Load

Convert a database row to Load entity.

# Arguments
- `row`: NamedTuple or DataFrameRow from database query
- `load_profile::Vector{Float64}`: Time series of load multipliers

# Returns
- `Load`: Load entity
"""
function row_to_load(row, load_profile::Vector{Float64})::Load
    id = coalesce(row.id, "")
    name = coalesce(row.name, "")

    submarket_id = if hasproperty(row, :submarket_id)
        row.submarket_id
    else
        nothing
    end

    bus_id = if hasproperty(row, :bus_id)
        row.bus_id
    else
        nothing
    end

    base_mw = coalesce(row.base_mw, 0.0)

    is_elastic = coalesce(row.is_elastic, false)
    elasticity = coalesce(row.elasticity, 0.0)

    return Load(;
        id = id,
        name = name,
        submarket_id = submarket_id,
        bus_id = bus_id,
        base_mw = base_mw,
        load_profile = load_profile,
        is_elastic = is_elastic,
        elasticity = elasticity,
    )
end

# =============================================================================
# Entity Loading Functions
# =============================================================================#

"""
    load_thermal_plants(conn::LibPQ.Connection, schema::String) -> Vector{ConventionalThermal}

Load all thermal plants from database.

# Arguments
- `conn::LibPQ.Connection`: PostgreSQL connection
- `schema::String`: Database schema name

# Returns
- `Vector{ConventionalThermal}`: All thermal plants
"""
function load_thermal_plants(
    conn::LibPQ.Connection,
    schema::String,
)::Vector{ConventionalThermal}
    query = generate_thermal_plants_query(schema)

    results = execute(conn, query)
    df = results |> DataFrame

    plants = ConventionalThermal[]
    for row in eachrow(df)
        try
            plant = row_to_thermal_plant(row)
            push!(plants, plant)
        catch e
            @warn "Failed to convert thermal plant $(row.id): $e"
        end
    end

    return plants
end

"""
    load_hydro_plants(conn::LibPQ.Connection, schema::String) -> Vector{ReservoirHydro}

Load all hydro plants from database.

# Arguments
- `conn::LibPQ.Connection`: PostgreSQL connection
- `schema::String`: Database schema name

# Returns
- `Vector{ReservoirHydro}`: All hydro plants
"""
function load_hydro_plants(conn::LibPQ.Connection, schema::String)::Vector{ReservoirHydro}
    query = generate_hydro_plants_query(schema)

    results = execute(conn, query)
    df = results |> DataFrame

    plants = ReservoirHydro[]
    for row in eachrow(df)
        try
            plant = row_to_hydro_plant(row)
            push!(plants, plant)
        catch e
            @warn "Failed to convert hydro plant $(row.id): $e"
        end
    end

    return plants
end

"""
    load_renewable_plants(conn::LibPQ.Connection, schema::String) -> Tuple{Vector{WindPlant}, Vector{SolarPlant}}

Load all renewable plants from database.

# Arguments
- `conn::LibPQ.Connection`: PostgreSQL connection
- `schema::String`: Database schema name

# Returns
- `Tuple{Vector{WindPlant}, Vector{SolarPlant}}`: Wind and solar plants
"""
function load_renewable_plants(
    conn::LibPQ.Connection,
    schema::String,
)::Tuple{Vector{WindPlant},Vector{SolarPlant}}
    wind_farms = WindPlant[]
    solar_farms = SolarPlant[]

    # Load wind plants
    try
        wind_query = generate_wind_plants_query(schema)
        wind_results = execute(conn, wind_query)
        wind_df = wind_results |> DataFrame

        for row in eachrow(wind_df)
            try
                # Convert to wind plant (simplified)
                farm = WindPlant(;
                    id = coalesce(row.id, ""),
                    name = coalesce(row.name, ""),
                    bus_id = coalesce(row.bus_id, ""),
                    submarket_id = coalesce(row.submarket_id, ""),
                    installed_capacity_mw = coalesce(row.installed_capacity_mw, 0.0),
                    capacity_forecast_mw = fill(
                        coalesce(row.installed_capacity_mw, 0.0) *
                        coalesce(row.capacity_factor, 1.0),
                        168,
                    ),
                    forecast_type = DETERMINISTIC,
                    min_generation_mw = coalesce(row.min_generation_mw, 0.0),
                    max_generation_mw = coalesce(row.max_generation_mw, 0.0),
                    ramp_up_mw_per_min = coalesce(row.ramp_up_mw_per_min, 0.0),
                    ramp_down_mw_per_min = coalesce(row.ramp_down_mw_per_min, 0.0),
                    curtailment_allowed = coalesce(row.curtailment_allowed, true),
                    forced_outage_rate = coalesce(row.forced_outage_rate, 0.0),
                    is_dispatchable = coalesce(row.is_dispatchable, true),
                    commissioning_date = if hasproperty(row, :commissioning_date) &&
                                            row.commissioning_date !== nothing
                        row.commissioning_date
                    else
                        DateTime(2020, 1, 1)
                    end,
                    num_turbines = coalesce(row.num_turbines, 1),
                    must_run = coalesce(row.must_run, false),
                )
                push!(wind_farms, farm)
            catch e
                @warn "Failed to convert wind plant $(row.id): $e"
            end
        end
    catch e
        @warn "Failed to load wind plants (table may not exist): $e"
    end

    # Load solar plants
    try
        solar_query = generate_solar_plants_query(schema)
        solar_results = execute(conn, solar_query)
        solar_df = solar_results |> DataFrame

        for row in eachrow(solar_df)
            try
                farm = SolarPlant(;
                    id = coalesce(row.id, ""),
                    name = coalesce(row.name, ""),
                    bus_id = coalesce(row.bus_id, ""),
                    submarket_id = coalesce(row.submarket_id, ""),
                    installed_capacity_mw = coalesce(row.installed_capacity_mw, 0.0),
                    capacity_forecast_mw = fill(
                        coalesce(row.installed_capacity_mw, 0.0) *
                        coalesce(row.capacity_factor, 1.0),
                        168,
                    ),
                    forecast_type = DETERMINISTIC,
                    min_generation_mw = coalesce(row.min_generation_mw, 0.0),
                    max_generation_mw = coalesce(row.max_generation_mw, 0.0),
                    ramp_up_mw_per_min = coalesce(row.ramp_up_mw_per_min, 0.0),
                    ramp_down_mw_per_min = coalesce(row.ramp_down_mw_per_min, 0.0),
                    curtailment_allowed = coalesce(row.curtailment_allowed, true),
                    forced_outage_rate = coalesce(row.forced_outage_rate, 0.0),
                    is_dispatchable = coalesce(row.is_dispatchable, true),
                    commissioning_date = if hasproperty(row, :commissioning_date) &&
                                            row.commissioning_date !== nothing
                        row.commissioning_date
                    else
                        DateTime(2020, 1, 1)
                    end,
                    num_panels = coalesce(row.num_panels, 1000),
                    must_run = coalesce(row.must_run, false),
                )
                push!(solar_farms, farm)
            catch e
                @warn "Failed to convert solar plant $(row.id): $e"
            end
        end
    catch e
        @warn "Failed to load solar plants (table may not exist): $e"
    end

    return wind_farms, solar_farms
end

"""
    load_network(conn::LibPQ.Connection, schema::String) -> Tuple{Vector{Bus}, Vector{ACLine}, Vector{DCLine}}

Load all network entities from database.

# Arguments
- `conn::LibPQ.Connection`: PostgreSQL connection
- `schema::String`: Database schema name

# Returns
- `Tuple{Vector{Bus}, Vector{ACLine}, Vector{DCLine}}`: Buses, AC lines, DC lines
"""
function load_network(
    conn::LibPQ.Connection,
    schema::String,
)::Tuple{Vector{Bus},Vector{ACLine},Vector{DCLine}}
    buses = Bus[]
    ac_lines = ACLine[]
    dc_lines = DCLine[]

    # Load buses
    try
        buses_query = generate_buses_query(schema)
        buses_results = execute(conn, buses_query)
        buses_df = buses_results |> DataFrame

        for row in eachrow(buses_df)
            try
                bus = row_to_bus(row)
                push!(buses, bus)
            catch e
                @warn "Failed to convert bus $(row.id): $e"
            end
        end
    catch e
        @warn "Failed to load buses: $e"
    end

    # Load AC lines
    try
        ac_query = generate_ac_lines_query(schema)
        ac_results = execute(conn, ac_query)
        ac_df = ac_results |> DataFrame

        for row in eachrow(ac_df)
            try
                line = row_to_ac_line(row)
                push!(ac_lines, line)
            catch e
                @warn "Failed to convert AC line $(row.id): $e"
            end
        end
    catch e
        @warn "Failed to load AC lines: $e"
    end

    # Load DC lines
    try
        dc_query = generate_dc_lines_query(schema)
        dc_results = execute(conn, dc_query)
        dc_df = dc_results |> DataFrame

        for row in eachrow(dc_df)
            try
                line = row_to_dc_line(row)
                push!(dc_lines, line)
            catch e
                @warn "Failed to convert DC line $(row.id): $e"
            end
        end
    catch e
        @warn "Failed to load DC lines: $e"
    end

    return buses, ac_lines, dc_lines
end

"""
    load_market(conn::LibPQ.Connection, schema::String) -> Tuple{Vector{Submarket}, Vector{Load}}

Load all market entities from database.

# Arguments
- `conn::LibPQ.Connection`: PostgreSQL connection
- `schema::String`: Database schema name

# Returns
- `Tuple{Vector{Submarket}, Vector{Load}}`: Submarkets and loads
"""
function load_market(
    conn::LibPQ.Connection,
    schema::String;
    default_profile_length::Int = 168,
)::Tuple{Vector{Submarket},Vector{Load}}
    submarkets = Submarket[]
    loads = Load[]

    # Load submarkets
    try
        submarkets_query = generate_submarkets_query(schema)
        submarkets_results = execute(conn, submarkets_query)
        submarkets_df = submarkets_results |> DataFrame

        for row in eachrow(submarkets_df)
            try
                sm = row_to_submarket(row)
                push!(submarkets, sm)
            catch e
                @warn "Failed to convert submarket $(row.id): $e"
            end
        end
    catch e
        @warn "Failed to load submarkets: $e"
    end

    # Load loads
    try
        loads_query = generate_loads_query(schema)
        loads_results = execute(conn, loads_query)
        loads_df = loads_results |> DataFrame

        for row in eachrow(loads_df)
            try
                # Try to load load profile
                load_profile = try
                    profile_query = generate_load_profile_query(schema, row.id)
                    profile_results = execute(conn, profile_query)
                    profile_df = profile_results |> DataFrame

                    if nrow(profile_df) > 0
                        profile_df.value
                    else
                        # Default flat profile
                        ones(default_profile_length)
                    end
                catch e
                    @warn "Failed to load profile for load $(row.id), using flat profile: $e"
                    ones(default_profile_length)
                end

                load = row_to_load(row, load_profile)
                push!(loads, load)
            catch e
                @warn "Failed to convert load $(row.id): $e"
            end
        end
    catch e
        @warn "Failed to load loads: $e"
    end

    return submarkets, loads
end

# =============================================================================
# Main Loading Function
# =============================================================================#

"""
    load_from_database(loader::DatabaseLoader; base_date::Date = Date(2025, 1, 1)) -> ElectricitySystem

Load complete electricity system from PostgreSQL database.

This is the main entry point for database loading. It:
1. Connects to the database
2. Loads all entities (thermal, hydro, renewable, network, market)
3. Validates referential integrity
4. Returns an ElectricitySystem

# Arguments
- `loader::DatabaseLoader`: Database loader configuration
- `base_date::Date`: Base date for the system (default: 2025-01-01)

# Returns
- `ElectricitySystem`: Complete system with all entities

# Throws
- `ConnectionError`: if database connection fails
- `ArgumentError`: if validation fails

# Example
```julia
loader = DatabaseLoader(;
    host = "localhost",
    dbname = "dessem_db",
    user = "ons_user",
    password = "secret",
    schema = "dessem_2026"
)

system = load_from_database(loader)
println("Loaded \$(length(system.thermal_plants)) thermal plants")
```
"""
function load_from_database(
    loader::DatabaseLoader;
    base_date::Date = Date(2025, 1, 1),
)::ElectricitySystem
    conn_str = get_connection_string(loader)

    if loader.verbose
        @info "Connecting to database:" host = loader.host port = loader.port dbname =
            loader.dbname
    end

    conn = try
        LibPQ.Connection(conn_str)
    catch e
        @error "Failed to connect to database" exception = e
        error("Database connection failed: $e")
    end

    try
        if loader.verbose
            @info "Loading entities from schema: $(loader.schema)"
        end

        # Load all entity types
        thermal_plants = load_thermal_plants(conn, loader.schema)
        hydro_plants = load_hydro_plants(conn, loader.schema)
        wind_farms, solar_farms = load_renewable_plants(conn, loader.schema)
        buses, ac_lines, dc_lines = load_network(conn, loader.schema)
        submarkets, loads = load_market(conn, loader.schema)

        if loader.verbose
            @info "Entity loading complete" thermal = length(thermal_plants) hydro =
                length(hydro_plants) wind = length(wind_farms) solar = length(solar_farms) buses =
                length(buses) loads = length(loads)
        end

        # Create ElectricitySystem
        system = ElectricitySystem(;
            thermal_plants = thermal_plants,
            hydro_plants = hydro_plants,
            wind_farms = wind_farms,
            solar_farms = solar_farms,
            buses = buses,
            ac_lines = ac_lines,
            dc_lines = dc_lines,
            submarkets = submarkets,
            loads = loads,
            base_date = base_date,
            description = "System loaded from PostgreSQL database $(loader.dbname).$(loader.schema)",
            version = "1.0",
        )

        if loader.verbose
            @info "Successfully created ElectricitySystem"
        end

        return system

    finally
        close(conn)
        if loader.verbose
            @info "Database connection closed"
        end
    end
end

# =============================================================================
# Validation Functions
# =============================================================================#

"""
    validate_loaded_data(system::ElectricitySystem) -> Bool

Validate integrity of loaded system data.

# Arguments
- `system::ElectricitySystem`: System to validate

# Returns
- `Bool`: true if valid

# Throws
- `ArgumentError`: if validation fails
"""
function validate_loaded_data(system::ElectricitySystem)::Bool
    # Check basic consistency
    if isempty(system.buses) && !isempty(system.thermal_plants)
        @warn "System has thermal plants but no buses"
    end

    if isempty(system.submarkets)
        @warn "System has no submarkets"
    end

    # Validate through ElectricitySystem constructor (already done)
    return validate_system(system)
end

# =============================================================================
# Utility Functions
# =============================================================================#

"""
    escape_string(str::String) -> String

Escape single quotes in SQL string literals.

# Arguments
- `str::String`: String to escape

# Returns
- `String`: Escaped string
"""
function escape_string(str::String)::String
    return replace(str, "'" => "''")
end

end # module DatabaseLoaders
