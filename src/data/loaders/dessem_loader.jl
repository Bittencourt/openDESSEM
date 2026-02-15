"""
    DessemLoader - DESSEM to OpenDESSEM Integration Layer

This module provides functions to load official ONS DESSEM files and convert
them to OpenDESSEM entities using the DESSEM2Julia package as the underlying
parser.

# DESSEM File Formats
DESSEM is the Brazilian official hydrothermal dispatch optimization model.
It uses various file types:

- `dessem.arq`: Master index file that maps file types to actual filenames
- `entdados.dat`: General operational data (plants, subsystems, constraints)
- `termdat.dat`: Thermal plant registry (CADUSIT, CADUNIDT records)
- `hidr.dat`: Binary hydro plant registry (792 bytes per plant)
- `operut.dat`: Thermal unit operational data
- `operuh.dat`: Hydro operational constraints
- `dadvaz.dat`: Natural inflow data
- `renovaveis.dat`: Renewable energy plant data (wind, solar)
- `desselet.dat`: Network case mapping to .pwf files
- `*.pwf`: Power flow data files (buses, lines)

# Main Functions
- `load_dessem_case(path)`: Load complete DESSEM case to ElectricitySystem
- `convert_dessem_thermal(...)`: Convert DESSEM thermal to ConventionalThermal
- `convert_dessem_hydro(...)`: Convert DESSEM hydro to ReservoirHydro
- `convert_dessem_bus(...)`: Convert DESSEM bus to OpenDESSEM Bus
- `convert_dessem_renewable(...)`: Convert DESSEM renewable to WindPlant/SolarPlant

# Example
```julia
using OpenDESSEM

# Load a DESSEM case from ONS data
system = load_dessem_case("path/to/DS_ONS_102025_RV2D11/")

# Access converted entities
println("Thermal plants: ", length(system.thermal_plants))
println("Hydro plants: ", length(system.hydro_plants))
println("Buses: ", length(system.buses))
```

# References
- DESSEM Manual: http://www.cepel.br
- DESSEM2Julia: https://github.com/Bittencourt/DESSEM2Julia
- ONS: https://www.ons.org.br
"""
module DessemLoader

using Dates

# Import DESSEM2Julia for parsing
using DESSEM2Julia:
    # Parsers
    parse_dessemarq,
    parse_termdat,
    parse_entdados,
    parse_hidr,
    parse_operut,
    parse_operuh,
    parse_renovaveis,
    parse_desselet,
    parse_dadvaz,
    # Types - Thermal
    ThermalRegistry,
    CADUSIT,
    CADUNIDT,
    # Types - General Data
    GeneralData,
    SISTRecord,
    UHRecord,
    UTRecord,
    DPRecord,
    TMRecord,
    # Types - Hydro
    HidrData,
    BinaryHidrData,
    BinaryHidrRecord,
    # Types - Operational
    OperutData,
    INITRecord,
    OPERRecord,
    OperuhData,
    # Types - Renewables
    RenovaveisData,
    RenovaveisRecord,
    # Types - Network
    DesseletData,
    DessemArq

# Import OpenDESSEM Entities module types
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
    DETERMINISTIC,
    EntityMetadata

# Import ElectricitySystem from parent
import ..ElectricitySystem

export load_dessem_case,
    convert_dessem_thermal,
    convert_dessem_hydro,
    convert_dessem_bus,
    convert_dessem_renewable,
    DessemCaseData

#=============================================================================
# Constants and Mappings
=============================================================================#

"""
Mapping from DESSEM subsystem numeric codes to OpenDESSEM codes.
Based on ONS subsystem numbering convention.

Note: Codes must be at least 2 characters for entity validation.
"""
const SUBSYSTEM_CODE_MAP = Dict{Int,String}(
    1 => "SE",  # Sudeste (Southeast)
    2 => "SU",  # Sul (South) - changed from "S" to meet 2-char min_length
    3 => "NE",  # Nordeste (Northeast)
    4 => "NO",  # Norte (North) - changed from "N" to meet 2-char min_length
    5 => "FC",  # Fictício (Fictitious, for contracts)
)

"""
Mapping from DESSEM fuel type codes to OpenDESSEM FuelType enum values.
"""
const FUEL_TYPE_MAP = Dict{Int,Symbol}(
    1 => :NATURAL_GAS,
    2 => :COAL,
    3 => :FUEL_OIL,
    4 => :DIESEL,
    5 => :NUCLEAR,
    6 => :BIOMASS,
    7 => :BIOGAS,
    0 => :OTHER,
)

"""
Default base voltage for buses when not specified.
"""
const DEFAULT_BASE_KV = 230.0

#=============================================================================
# Data Container
=============================================================================#

"""
    DessemCaseData

Raw parsed data from all DESSEM files before conversion to OpenDESSEM entities.
This intermediate structure holds all parsed DESSEM2Julia types.

# Fields
- `dessem_arq::Union{DessemArq, Nothing}`: Master file index
- `thermal_registry::Union{ThermalRegistry, Nothing}`: Thermal plant data
- `general_data::Union{GeneralData, Nothing}`: General operational data
- `hidr_data::Union{BinaryHidrData, Nothing}`: Hydro plant binary data
- `operut_data::Union{OperutData, Nothing}`: Thermal operational data
- `operuh_data::Union{OperuhData, Nothing}`: Hydro constraints
- `renovaveis_data::Union{RenovaveisData, Nothing}`: Renewable plants
- `desselet_data::Union{DesseletData, Nothing}`: Network case mapping
- `base_path::String`: Base directory of the DESSEM case
- `study_date::Date`: Base date for the study
"""
mutable struct DessemCaseData
    dessem_arq::Union{DessemArq,Nothing}
    thermal_registry::Union{ThermalRegistry,Nothing}
    general_data::Union{GeneralData,Nothing}
    hidr_data::Union{BinaryHidrData,Nothing}
    operut_data::Union{OperutData,Nothing}
    operuh_data::Union{OperuhData,Nothing}
    renovaveis_data::Union{RenovaveisData,Nothing}
    desselet_data::Union{DesseletData,Nothing}
    base_path::String
    study_date::Date

    function DessemCaseData(base_path::String)
        new(
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            base_path,
            Date(2025, 1, 1),
        )
    end
end

#=============================================================================
# File Parsing Functions
=============================================================================#

"""
    parse_dessem_case(path::String) -> DessemCaseData

Parse all DESSEM files in a case directory.

# Arguments
- `path::String`: Path to DESSEM case directory (containing dessem.arq)

# Returns
- `DessemCaseData`: Container with all parsed DESSEM data
"""
function parse_dessem_case(path::String)::DessemCaseData
    # Validate path
    if !isdir(path)
        throw(ArgumentError("DESSEM case path does not exist: $path"))
    end

    data = DessemCaseData(path)

    # Parse master index file
    arq_path = joinpath(path, "dessem.arq")
    if isfile(arq_path)
        try
            data.dessem_arq = parse_dessemarq(arq_path)
        catch e
            @warn "Failed to parse dessem.arq: $e"
        end
    end

    # Parse thermal registry (termdat.dat)
    termdat_path = joinpath(path, "termdat.dat")
    if isfile(termdat_path)
        try
            data.thermal_registry = parse_termdat(termdat_path)
            @info "Parsed thermal registry: $(length(data.thermal_registry.plants)) plants, $(length(data.thermal_registry.units)) units"
        catch e
            @warn "Failed to parse termdat.dat: $e"
        end
    end

    # Parse general data (entdados.dat)
    entdados_path = joinpath(path, "entdados.dat")
    if isfile(entdados_path)
        try
            data.general_data = parse_entdados(entdados_path)
            @info "Parsed general data: $(length(data.general_data.subsystems)) subsystems, $(length(data.general_data.hydro_plants)) hydro, $(length(data.general_data.thermal_plants)) thermal"
        catch e
            @warn "Failed to parse entdados.dat: $e"
        end
    end

    # Parse hydro registry (hidr.dat - binary file)
    hidr_path = joinpath(path, "hidr.dat")
    if isfile(hidr_path)
        try
            data.hidr_data = parse_hidr(hidr_path)
            @info "Parsed hydro registry: $(length(data.hidr_data.records)) plants"
        catch e
            @warn "Failed to parse hidr.dat: $e"
        end
    end

    # Parse thermal operational data (operut.dat)
    operut_path = joinpath(path, "operut.dat")
    if isfile(operut_path)
        try
            data.operut_data = parse_operut(operut_path)
            @info "Parsed operut data: $(length(data.operut_data.init_records)) init records, $(length(data.operut_data.oper_records)) oper records"
        catch e
            @warn "Failed to parse operut.dat: $e"
        end
    end

    # Parse hydro operational constraints (operuh.dat)
    operuh_path = joinpath(path, "operuh.dat")
    if isfile(operuh_path)
        try
            data.operuh_data = parse_operuh(operuh_path)
            @info "Parsed operuh data: $(length(data.operuh_data.rest_records)) constraints"
        catch e
            @warn "Failed to parse operuh.dat: $e"
        end
    end

    # Parse renewable plants (renovaveis.dat)
    renovaveis_path = joinpath(path, "renovaveis.dat")
    if isfile(renovaveis_path)
        try
            data.renovaveis_data = parse_renovaveis(renovaveis_path)
            @info "Parsed renewables: $(length(data.renovaveis_data.plants)) plants"
        catch e
            @warn "Failed to parse renovaveis.dat: $e"
        end
    end

    # Parse network index (desselet.dat)
    desselet_path = joinpath(path, "desselet.dat")
    if isfile(desselet_path)
        try
            data.desselet_data = parse_desselet(desselet_path)
            @info "Parsed desselet: $(length(data.desselet_data.base_cases)) base cases, $(length(data.desselet_data.patamares)) patamares"
        catch e
            @warn "Failed to parse desselet.dat: $e"
        end
    end

    # Try to extract study date from general data
    if data.general_data !== nothing && !isempty(data.general_data.time_periods)
        # First time period gives us the study start
        first_period = first(data.general_data.time_periods)
        # Construct date from available info (assuming October 2025 from sample)
        data.study_date = Date(2025, 10, first_period.day)
    end

    return data
end

#=============================================================================
# Conversion Functions - Thermal Plants
=============================================================================#

"""
    convert_dessem_thermal(
        cadusit::CADUSIT,
        units::Vector{CADUNIDT},
        subsystem_code::String;
        bus_id::String = "B_DEFAULT"
    ) -> ConventionalThermal

Convert a DESSEM thermal plant (CADUSIT) and its units to OpenDESSEM ConventionalThermal.

# Arguments
- `cadusit::CADUSIT`: DESSEM plant registration record
- `units::Vector{CADUNIDT}`: DESSEM unit records for this plant
- `subsystem_code::String`: Converted subsystem code (SE, S, NE, N)
- `bus_id::String`: Bus ID to assign (default placeholder)

# Returns
- OpenDESSEM ConventionalThermal entity
"""
function convert_dessem_thermal(
    cadusit::CADUSIT,
    units::Vector{CADUNIDT},
    subsystem_code::String;
    bus_id::String = "B_DEFAULT",
)
    # Calculate aggregate capacity from units
    total_capacity = sum(u.unit_capacity for u in units; init = 0.0)
    min_gen = sum(u.min_generation for u in units; init = 0.0)

    # Get ramp rates (take average if multiple units)
    avg_ramp_up = if isempty(units)
        Inf
    else
        sum(u.ramp_up_rate for u in units) / length(units)
    end
    avg_ramp_down = if isempty(units)
        Inf
    else
        sum(u.ramp_down_rate for u in units) / length(units)
    end

    # Convert ramp from MW/h to MW/min
    ramp_up_per_min = isinf(avg_ramp_up) ? 999.0 : avg_ramp_up / 60.0
    ramp_down_per_min = isinf(avg_ramp_down) ? 999.0 : avg_ramp_down / 60.0

    # Get min on/off times from first unit
    min_up = isempty(units) ? 1 : first(units).min_on_time
    min_down = isempty(units) ? 1 : first(units).min_off_time

    # Get startup/shutdown costs
    startup_cost = isempty(units) ? 0.0 : first(units).cold_startup_cost
    shutdown_cost = isempty(units) ? 0.0 : first(units).shutdown_cost

    # Determine fuel type
    fuel_type_sym = get(FUEL_TYPE_MAP, cadusit.fuel_type, :OTHER)

    # Build commissioning date
    commission_date = if cadusit.commission_year !== nothing
        year = cadusit.commission_year
        month = something(cadusit.commission_month, 1)
        day = something(cadusit.commission_day, 1)
        # Handle 2-digit years
        year = year < 100 ? (year < 50 ? 2000 + year : 1900 + year) : year
        DateTime(year, month, day)
    else
        DateTime(2000, 1, 1)  # Default commissioning date
    end

    # Generate unique ID
    plant_id = "T_$(subsystem_code)_$(lpad(cadusit.plant_num, 3, '0'))"

    # Access FuelType enum via Main module
    fuel_type_enum = getfield(Main, fuel_type_sym)

    # Create ConventionalThermal entity
    return ConventionalThermal(;
        id = plant_id,
        name = String(strip(cadusit.plant_name)),
        bus_id = bus_id,
        submarket_id = subsystem_code,
        fuel_type = fuel_type_enum,
        capacity_mw = max(total_capacity, 1.0),
        min_generation_mw = min_gen,
        max_generation_mw = max(total_capacity, 1.0),
        ramp_up_mw_per_min = ramp_up_per_min,
        ramp_down_mw_per_min = ramp_down_per_min,
        min_up_time_hours = max(min_up, 0),
        min_down_time_hours = max(min_down, 0),
        fuel_cost_rsj_per_mwh = cadusit.fuel_cost,
        startup_cost_rs = startup_cost,
        shutdown_cost_rs = shutdown_cost,
        commissioning_date = commission_date,
        num_units = cadusit.num_units,
        must_run = false,
    )
end

#=============================================================================
# Conversion Functions - Hydro Plants
=============================================================================#

"""
    convert_dessem_hydro(
        hidr::BinaryHidrRecord,
        uh_record::Union{UHRecord, Nothing},
        subsystem_code::String;
        bus_id::String = "B_DEFAULT"
    ) -> ReservoirHydro

Convert a DESSEM hydro plant to OpenDESSEM ReservoirHydro.

# Arguments
- `hidr::BinaryHidrRecord`: Binary HIDR record with full plant data
- `uh_record::Union{UHRecord, Nothing}`: Optional UH record from ENTDADOS
- `subsystem_code::String`: Subsystem code (SE, S, NE, N)
- `bus_id::String`: Bus ID to assign

# Returns
- OpenDESSEM ReservoirHydro entity
"""
function convert_dessem_hydro(
    hidr::BinaryHidrRecord,
    uh_record::Union{UHRecord,Nothing},
    subsystem_code::String;
    bus_id::String = "B_DEFAULT",
    used_ids::Set{String} = Set{String}(),
    zero_counter::Dict{String,Int} = Dict{String,Int}(),
)
    # Extract key parameters from binary record
    plant_num = hidr.posto
    plant_name = String(strip(hidr.nome))
    # Handle empty names
    if isempty(plant_name)
        plant_name = "Hydro Plant $plant_num"
    end

    # Generate unique ID - ensure uniqueness even when posto is 0
    if plant_num > 0
        plant_id = "H_$(subsystem_code)_$(lpad(plant_num, 3, '0'))"
    else
        # For posto=0, use an incrementing counter per subsystem
        count = get!(zero_counter, subsystem_code, 1)
        plant_id = "H_$(subsystem_code)_Z_$(lpad(count, 3, '0'))"
        zero_counter[subsystem_code] = count + 1
    end

    # Volume limits
    max_vol = hidr.volume_maximo
    min_vol = hidr.volume_minimo

    # Get initial volume from UH record if available
    initial_vol_pct = if uh_record !== nothing
        uh_record.initial_volume_pct
    else
        50.0  # Default 50%
    end
    initial_vol = min_vol + (max_vol - min_vol) * (initial_vol_pct / 100.0)

    # Calculate max outflow from machine sets
    max_flow = sum(hidr.qef_conjunto)

    # Calculate installed capacity from machine sets
    installed_capacity = sum(hidr.potef_conjunto)

    # Productivity (specific productivity in MW/(m³/s)/m)
    productivity = hidr.produtibilidade_especifica

    # Calculate efficiency (simplified)
    efficiency = 0.90  # Default efficiency, could be computed from productivity

    # Subsystem numeric code (reverse mapping from SUBSYSTEM_CODE_MAP)
    subsystem_num = get(Dict("SE" => 1, "SU" => 2, "NE" => 3, "NO" => 4, "FC" => 5), subsystem_code, 1)

    # Water value (default, could be from FCF data)
    water_value = 50.0  # R$/hm³

    # Downstream plant - both downstream_plant_id and water_travel_time_hours
    # must be set or both be nothing (validation requirement)
    downstream_id = if hidr.jusante > 0
        "H_$(subsystem_code)_$(lpad(hidr.jusante, 3, '0'))"
    else
        nothing
    end
    travel_time = if downstream_id !== nothing
        1.0  # Default 1 hour travel time if downstream plant exists
    else
        nothing
    end

    # Generate unique ID - ensure uniqueness even with duplicate posto values
    if plant_num > 0
        base_id = "H_$(subsystem_code)_$(lpad(plant_num, 3, '0'))"
        # Check for duplicates and add suffix if needed
        if base_id in used_ids
            suffix = 1
            while "$(base_id)_$(suffix)" in used_ids
                suffix += 1
            end
            plant_id = "$(base_id)_$(suffix)"
        else
            plant_id = base_id
        end
    else
        # For posto=0, use an incrementing counter per subsystem
        count = get!(zero_counter, subsystem_code, 1)
        plant_id = "H_$(subsystem_code)_Z_$(lpad(count, 3, '0'))"
        zero_counter[subsystem_code] = count + 1
    end

    return ReservoirHydro(;
        id = plant_id,
        name = plant_name,
        bus_id = bus_id,
        submarket_id = subsystem_code,
        max_volume_hm3 = max(max_vol, 1.0),
        min_volume_hm3 = max(min_vol, 0.0),
        initial_volume_hm3 = max(initial_vol, min_vol),
        max_outflow_m3_per_s = max(Float64(max_flow), 1.0),
        min_outflow_m3_per_s = 0.0,
        max_generation_mw = max(installed_capacity, 0.1),  # Minimum 0.1 MW for validation
        min_generation_mw = 0.0,
        efficiency = efficiency,
        water_value_rs_per_hm3 = water_value,
        subsystem_code = subsystem_num,
        initial_volume_percent = initial_vol_pct,
        must_run = false,
        downstream_plant_id = downstream_id,
        water_travel_time_hours = travel_time,
    )
end

#=============================================================================
# Conversion Functions - Buses and Network
=============================================================================#

"""
    convert_dessem_bus(
        bus_num::Int,
        name::String,
        subsystem_code::String;
        voltage_kv::Float64 = DEFAULT_BASE_KV,
        is_reference::Bool = false
    ) -> Bus

Create an OpenDESSEM Bus from DESSEM bus data.

# Arguments
- `bus_num::Int`: Bus number
- `name::String`: Bus name
- `subsystem_code::String`: Subsystem code
- `voltage_kv::Float64`: Voltage level (kV)
- `is_reference::Bool`: Whether this is the reference bus

# Returns
- OpenDESSEM Bus entity
"""
function convert_dessem_bus(
    bus_num::Int,
    name::String,
    subsystem_code::String;
    voltage_kv::Float64 = DEFAULT_BASE_KV,
    is_reference::Bool = false,
)
    bus_id = "B_$(subsystem_code)_$(lpad(bus_num, 4, '0'))"

    return Bus(;
        id = bus_id,
        name = String(strip(name)),
        voltage_kv = voltage_kv,
        base_kv = voltage_kv,
        dc_bus = false,
        is_reference = is_reference,
        area_id = subsystem_code,
        zone_id = nothing,
        latitude = nothing,
        longitude = nothing,
    )
end

#=============================================================================
# Conversion Functions - Renewables
=============================================================================#

"""
    convert_dessem_renewable(
        record::RenovaveisRecord,
        subsystem_code::String;
        bus_id::String = "B_DEFAULT"
    ) -> Union{WindPlant, SolarPlant}

Convert a DESSEM renewable plant record to OpenDESSEM WindPlant or SolarPlant.

# Arguments
- `record::RenovaveisRecord`: DESSEM renewable plant record
- `subsystem_code::String`: Subsystem code
- `bus_id::String`: Bus ID

# Returns
- WindPlant if plant name contains "UEE" (wind)
- SolarPlant if plant name contains "UFV" (solar)
- WindPlant otherwise (default)
"""
function convert_dessem_renewable(
    record::RenovaveisRecord,
    subsystem_code::String;
    bus_id::String = "B_DEFAULT",
)
    plant_name = record.plant_name
    plant_code = record.plant_code
    capacity = record.pmax == 9999.0 ? 100.0 : record.pmax  # Handle placeholder value

    # Determine plant type from name
    is_solar =
        occursin("UFV", uppercase(plant_name)) || occursin("SOLAR", uppercase(plant_name))

    plant_id = if is_solar
        "S_$(subsystem_code)_$(lpad(plant_code, 4, '0'))"
    else
        "W_$(subsystem_code)_$(lpad(plant_code, 4, '0'))"
    end

    # Default capacity forecast (constant capacity)
    capacity_forecast = fill(capacity * record.fcap, 48)  # 48 half-hours

    if is_solar
        return SolarPlant(;
            id = plant_id,
            name = String(strip(plant_name)),
            bus_id = bus_id,
            submarket_id = subsystem_code,
            installed_capacity_mw = capacity,
            capacity_forecast_mw = capacity_forecast,
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = capacity,
            ramp_up_mw_per_min = capacity / 10.0,
            ramp_down_mw_per_min = capacity / 10.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.02,
            is_dispatchable = true,
            commissioning_date = DateTime(2020, 1, 1),
            tracking_system = "FIXED",
            must_run = false,
        )
    else
        return WindPlant(;
            id = plant_id,
            name = String(strip(plant_name)),
            bus_id = bus_id,
            submarket_id = subsystem_code,
            installed_capacity_mw = capacity,
            capacity_forecast_mw = capacity_forecast,
            forecast_type = DETERMINISTIC,
            min_generation_mw = 0.0,
            max_generation_mw = capacity,
            ramp_up_mw_per_min = capacity / 10.0,
            ramp_down_mw_per_min = capacity / 10.0,
            curtailment_allowed = true,
            forced_outage_rate = 0.03,
            is_dispatchable = true,
            commissioning_date = DateTime(2020, 1, 1),
            num_turbines = 10,
            must_run = false,
        )
    end
end

#=============================================================================
# Conversion Functions - Submarkets
=============================================================================#

"""
    convert_dessem_submarket(sist::SISTRecord) -> Submarket

Convert a DESSEM subsystem record to OpenDESSEM Submarket.
"""
function convert_dessem_submarket(sist::SISTRecord)
    code = String(strip(sist.subsystem_code))
    name_str = String(strip(sist.subsystem_name))
    name = isempty(name_str) ? code : name_str

    submarket_id = "SM_$(code)"

    return Submarket(;
        id = submarket_id,
        name = name,
        code = code,
        country = "Brazil",
        description = "Brazilian National Interconnected System - $(name)",
    )
end

#=============================================================================
# Main Loading Function
=============================================================================#

"""
    load_dessem_case(path::String; skip_validation::Bool = false) -> ElectricitySystem

Load a complete DESSEM case and convert to OpenDESSEM ElectricitySystem.

This is the main entry point for loading DESSEM data. It:
1. Parses all DESSEM files in the given directory
2. Converts DESSEM types to OpenDESSEM entities
3. Creates placeholder buses for plant connections
4. Returns a validated ElectricitySystem

# Arguments
- `path::String`: Path to DESSEM case directory (must contain dessem.arq)
- `skip_validation::Bool`: Skip validation of entity references (default: false)

# Returns
- `ElectricitySystem`: Complete system with all entities

# Example
```julia
system = load_dessem_case("docs/Sample/DS_ONS_102025_RV2D11/")
println("Loaded \$(length(system.thermal_plants)) thermal plants")
println("Loaded \$(length(system.hydro_plants)) hydro plants")
```
"""
function load_dessem_case(path::String; skip_validation::Bool = false)
    @info "Loading DESSEM case from: $path"

    # Parse all DESSEM files
    case_data = parse_dessem_case(path)

    # Initialize entity collections
    thermal_plants = ConventionalThermal[]
    hydro_plants = HydroPlant[]
    wind_farms = WindPlant[]
    solar_farms = SolarPlant[]
    buses = Bus[]
    submarkets = Submarket[]
    loads = Load[]

    # Track created buses for validation
    bus_ids = Set{String}()

    # Step 1: Convert submarkets from general data
    if case_data.general_data !== nothing
        for sist in case_data.general_data.subsystems
            try
                sm = convert_dessem_submarket(sist)
                push!(submarkets, sm)
            catch e
                @warn "Failed to convert submarket $(sist.subsystem_code): $e"
            end
        end
    end

    # Ensure we have at least the standard Brazilian submarkets
    standard_codes = ["SE", "SU", "NE", "NO"]
    existing_codes = Set(sm.code for sm in submarkets)
    for code in standard_codes
        if !(code in existing_codes)
            push!(
                submarkets,
                Submarket(;
                    id = "SM_$code",
                    name = code,
                    code = code,
                    country = "Brazil",
                    description = "Brazilian NIS - $code",
                ),
            )
        end
    end

    @info "Created $(length(submarkets)) submarkets"

    # Step 2: Create placeholder buses for each subsystem
    for sm in submarkets
        bus = Bus(;
            id = "B_$(sm.code)_0001",
            name = "$(sm.name) Main Bus",
            voltage_kv = DEFAULT_BASE_KV,
            base_kv = DEFAULT_BASE_KV,
            dc_bus = false,
            is_reference = (sm.code == "SE"),  # SE is typically reference
            area_id = sm.code,
        )
        push!(buses, bus)
        push!(bus_ids, bus.id)
    end

    @info "Created $(length(buses)) buses"

    # Step 3: Convert thermal plants
    if case_data.thermal_registry !== nothing && case_data.general_data !== nothing
        # Build lookup for units by plant number
        units_by_plant = Dict{Int,Vector{CADUNIDT}}()
        for unit in case_data.thermal_registry.units
            if !haskey(units_by_plant, unit.plant_num)
                units_by_plant[unit.plant_num] = CADUNIDT[]
            end
            push!(units_by_plant[unit.plant_num], unit)
        end

        for cadusit in case_data.thermal_registry.plants
            try
                subsystem_code = get(SUBSYSTEM_CODE_MAP, cadusit.subsystem, "SE")
                units = get(units_by_plant, cadusit.plant_num, CADUNIDT[])
                bus_id = "B_$(subsystem_code)_0001"  # Use submarket main bus

                plant =
                    convert_dessem_thermal(cadusit, units, subsystem_code; bus_id = bus_id)
                push!(thermal_plants, plant)
            catch e
                @warn "Failed to convert thermal plant $(cadusit.plant_num): $e"
            end
        end
    end

    @info "Converted $(length(thermal_plants)) thermal plants"

    # Step 4: Convert hydro plants
    if case_data.hidr_data !== nothing
        # Build UH record lookup by plant number
        uh_lookup = Dict{Int,UHRecord}()
        if case_data.general_data !== nothing
            for uh in case_data.general_data.hydro_plants
                uh_lookup[uh.plant_num] = uh
            end
        end

        # Track used IDs to avoid duplicates
        used_hydro_ids = Set{String}()
        zero_posto_counter = Dict{String,Int}()  # Per-subsystem counter for posto=0

        for hidr in case_data.hidr_data.records
            try
                subsystem_code = get(SUBSYSTEM_CODE_MAP, hidr.subsistema, "SE")
                uh_record = get(uh_lookup, hidr.posto, nothing)
                bus_id = "B_$(subsystem_code)_0001"

                plant = convert_dessem_hydro(
                    hidr,
                    uh_record,
                    subsystem_code;
                    bus_id = bus_id,
                    used_ids = used_hydro_ids,
                    zero_counter = zero_posto_counter,
                )
                push!(hydro_plants, plant)
                push!(used_hydro_ids, plant.id)
            catch e
                @warn "Failed to convert hydro plant $(hidr.posto): $e"
            end
        end
    end

    @info "Converted $(length(hydro_plants)) hydro plants"

    # Step 5: Convert renewable plants (limit to avoid overwhelming the system)
    max_renewables = 1000  # Limit for performance
    if case_data.renovaveis_data !== nothing
        # Build subsystem lookup for renewables
        renewable_subsystems = Dict{Int,String}()
        for mapping in case_data.renovaveis_data.subsystem_mappings
            renewable_subsystems[mapping.plant_code] = mapping.subsystem
        end

        count = 0
        for record in case_data.renovaveis_data.plants
            count >= max_renewables && break

            try
                subsystem_code = get(renewable_subsystems, record.plant_code, "SE")
                bus_id = "B_$(subsystem_code)_0001"

                plant = convert_dessem_renewable(record, subsystem_code; bus_id = bus_id)

                if plant isa WindPlant
                    push!(wind_farms, plant)
                else
                    push!(solar_farms, plant)
                end
                count += 1
            catch e
                @warn "Failed to convert renewable $(record.plant_code): $e"
            end
        end
    end

    @info "Converted $(length(wind_farms)) wind farms and $(length(solar_farms)) solar farms"

    # Step 6: Create loads from demand data
    if case_data.general_data !== nothing
        # Aggregate demands by subsystem
        demand_by_subsystem = Dict{Int,Float64}()
        for dp in case_data.general_data.demands
            current = get(demand_by_subsystem, dp.subsystem, 0.0)
            demand_by_subsystem[dp.subsystem] = current + dp.demand
        end

        for (subsys_num, total_demand) in demand_by_subsystem
            subsystem_code = get(SUBSYSTEM_CODE_MAP, subsys_num, "SE")
            # Use subsystem number in ID to ensure uniqueness (e.g., for FC which has multiple entries)
            load = Load(;
                id = "L_$(subsystem_code)_$(subsys_num)",
                name = "$(subsystem_code) System Load",
                submarket_id = subsystem_code,
                bus_id = "B_$(subsystem_code)_0001",
                base_mw = total_demand,
                load_profile = ones(168),  # Flat profile
                is_elastic = false,
            )
            push!(loads, load)
        end
    end

    @info "Created $(length(loads)) loads"

    # Step 7: Create ElectricitySystem
    @info "Creating ElectricitySystem..."

    system = ElectricitySystem(;
        thermal_plants = thermal_plants,
        hydro_plants = hydro_plants,
        wind_farms = wind_farms,
        solar_farms = solar_farms,
        buses = buses,
        ac_lines = ACLine[],  # No lines in simplified model
        dc_lines = DCLine[],
        submarkets = submarkets,
        loads = loads,
        base_date = case_data.study_date,
        description = "DESSEM Case loaded from: $path",
        version = "1.0",
    )

    @info "Successfully loaded DESSEM case with:" thermal_count = length(thermal_plants) hydro_count =
        length(hydro_plants) wind_count = length(wind_farms) solar_count =
        length(solar_farms) bus_count = length(buses) load_count = length(loads)

    return system
end

end # module DessemLoader
