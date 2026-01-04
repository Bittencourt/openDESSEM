"""
    Electrical network entities for OpenDESSEM.

Defines transmission network components including buses, AC lines, and DC lines.
"""

using Dates

"""
    NetworkEntity <: PhysicalEntity

Abstract base type for all electrical network components.

Network entities form the transmission grid topology:
- Buses (nodes) where generation and load connect
- AC transmission lines (edges)
- DC transmission lines (HVDC links)
"""
abstract type NetworkEntity <: PhysicalEntity end

"""
    Bus <: NetworkEntity

Electrical bus (node) in the transmission network.

Buses are connection points for generators, loads, and transmission lines.
Each bus has a voltage level and can be a reference bus for power flow.

# Fields
- `id::String`: Unique bus identifier
- `name::String`: Human-readable bus name
- `voltage_kv::Float64`: Base voltage level (kilovolts)
- `base_kv::Float64`: Base voltage for power flow (kV)
- `dc_bus::Bool`: If true, this is a DC bus (for HVDC)
- `is_reference::Bool`: If true, this is the reference/slack bus
- `area_id::Union{String, Nothing}`: Area/region identifier
- `zone_id::Union{String, Nothing}`: Load zone identifier
- `latitude::Union{Float64, Nothing}`: Geographic latitude
- `longitude::Union{Float64, Nothing}`: Geographic longitude
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Voltage limits: `min_voltage <= voltage <= max_voltage`
- Reference bus: exactly one per island
- Power balance: sum(generation) - sum(load) - sum(flow_out) = 0

# Examples
```julia
bus = Bus(;
    id = "B_001",
    name = "Substation Alpha",
    voltage_kv = 230.0,
    base_kv = 230.0,
    dc_bus = false,
    is_reference = true,
    area_id = "NE",
    zone_id = "Z1",
    latitude = -23.5,
    longitude = -46.6
)
```
"""
Base.@kwdef struct Bus <: NetworkEntity
    id::String
    name::String
    voltage_kv::Float64
    base_kv::Float64
    dc_bus::Bool = false
    is_reference::Bool = false
    area_id::Union{String,Nothing} = nothing
    zone_id::Union{String,Nothing} = nothing
    latitude::Union{Float64,Nothing} = nothing
    longitude::Union{Float64,Nothing} = nothing
    metadata::EntityMetadata = EntityMetadata()

    function Bus(;
        id::String,
        name::String,
        voltage_kv::Float64,
        base_kv::Float64,
        dc_bus::Bool = false,
        is_reference::Bool = false,
        area_id::Union{String,Nothing} = nothing,
        zone_id::Union{String,Nothing} = nothing,
        latitude::Union{Float64,Nothing} = nothing,
        longitude::Union{Float64,Nothing} = nothing,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)

        # Validate voltage
        voltage_kv = validate_strictly_positive(voltage_kv, "voltage_kv")
        base_kv = validate_strictly_positive(base_kv, "base_kv")

        # Validate area_id and zone_id if provided
        if area_id !== nothing
            area_id = validate_id(area_id)
        end

        if zone_id !== nothing
            zone_id = validate_id(zone_id)
        end

        # Validate coordinates if provided
        if latitude !== nothing
            latitude = validate_in_range(latitude, -90.0, 90.0, "latitude")
        end

        if longitude !== nothing
            longitude = validate_in_range(longitude, -180.0, 180.0, "longitude")
        end

        new(
            id,
            name,
            voltage_kv,
            base_kv,
            dc_bus,
            is_reference,
            area_id,
            zone_id,
            latitude,
            longitude,
            metadata,
        )
    end
end

"""
    ACLine <: NetworkEntity

Alternating current transmission line.

AC lines connect buses in the transmission network and have impedance,
capacity limits, and operational constraints.

# Fields
- `id::String`: Unique line identifier
- `name::String`: Human-readable line name
- `from_bus_id::String`: Origin bus ID
- `to_bus_id::String`: Destination bus ID
- `length_km::Float64`: Line length (kilometers)
- `resistance_ohm::Float64`: Line resistance (ohms)
- `reactance_ohm::Float64`: Line reactance (ohms)
- `susceptance_siemen::Float64`: Line susceptance (siemens)
- `max_flow_mw::Float64`: Maximum power flow (MW)
- `min_flow_mw::Float64`: Minimum power flow (MW, can be negative)
- `num_circuits::Int`: Number of parallel circuits
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Power flow: `-max_flow <= flow <= max_flow`
- Thermal limit: `|flow| <= max_flow`
- Voltage angle difference: typically limited to < 90 degrees
- Power flow equation: `p_ij = (vi*vj/X) * sin(theta_i - theta_j)`

# Examples
```julia
line = ACLine(;
    id = "L_001",
    name = "Alpha to Beta",
    from_bus_id = "B_001",
    to_bus_id = "B_002",
    length_km = 150.0,
    resistance_ohm = 5.2,
    reactance_ohm = 15.8,
    susceptance_siemen = 0.0002,
    max_flow_mw = 500.0,
    min_flow_mw = -500.0,
    num_circuits = 1
)
```
"""
Base.@kwdef struct ACLine <: NetworkEntity
    id::String
    name::String
    from_bus_id::String
    to_bus_id::String
    length_km::Float64
    resistance_ohm::Float64
    reactance_ohm::Float64
    susceptance_siemen::Float64
    max_flow_mw::Float64
    min_flow_mw::Float64
    num_circuits::Int = 1
    metadata::EntityMetadata = EntityMetadata()

    function ACLine(;
        id::String,
        name::String,
        from_bus_id::String,
        to_bus_id::String,
        length_km::Float64,
        resistance_ohm::Float64,
        reactance_ohm::Float64,
        susceptance_siemen::Float64,
        max_flow_mw::Float64,
        min_flow_mw::Float64,
        num_circuits::Int = 1,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)

        # Validate bus IDs
        from_bus_id = validate_id(from_bus_id)
        to_bus_id = validate_id(to_bus_id)

        if from_bus_id == to_bus_id
            throw(ArgumentError("from_bus_id and to_bus_id must be different"))
        end

        # Validate length
        length_km = validate_strictly_positive(length_km, "length_km")

        # Validate electrical parameters
        resistance_ohm = validate_non_negative(resistance_ohm, "resistance_ohm")
        reactance_ohm = validate_strictly_positive(reactance_ohm, "reactance_ohm")
        susceptance_siemen = validate_non_negative(susceptance_siemen, "susceptance_siemen")

        # Validate flow limits
        max_flow_mw = validate_strictly_positive(max_flow_mw, "max_flow_mw")
        min_flow_mw = validate_non_negative(min_flow_mw, "min_flow_mw")
        validate_min_leq_max(min_flow_mw, max_flow_mw, "min_flow", "max_flow")

        # Validate number of circuits
        if num_circuits < 1
            throw(ArgumentError("num_circuits must be at least 1"))
        end

        new(
            id,
            name,
            from_bus_id,
            to_bus_id,
            length_km,
            resistance_ohm,
            reactance_ohm,
            susceptance_siemen,
            max_flow_mw,
            min_flow_mw,
            num_circuits,
            metadata,
        )
    end
end

"""
    DCLine <: NetworkEntity

High Voltage Direct Current (HVDC) transmission line.

DC lines provide asynchronous interconnections and have controllable power flow.
Unlike AC lines, power flow on DC lines is fully controllable.

# Fields
- `id::String`: Unique line identifier
- `name::String`: Human-readable line name
- `from_bus_id::String`: Origin (rectifier) bus ID
- `to_bus_id::String`: Destination (inverter) bus ID
- `length_km::Float64`: Line length (kilometers)
- `max_flow_mw::Float64`: Maximum power flow (MW)
- `min_flow_mw::Float64`: Minimum power flow (MW, typically negative)
- `resistance_ohm::Float64`: Line resistance (ohms)
- `inductance_henry::Float64`: Line inductance (henries)
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Power flow: `min_flow <= flow <= max_flow`
- Fully controllable: `flow` is a decision variable
- Losses: typically modeled as quadratic function of flow
- Asynchronous: no phase angle constraints

# Examples
```julia
line = DCLine(;
    id = "DC_001",
    name = "HVDC Interconnector",
    from_bus_id = "B_001",
    to_bus_id = "B_002",
    length_km = 800.0,
    max_flow_mw = 2000.0,
    min_flow_mw = -2000.0,
    resistance_ohm = 10.5,
    inductance_henry = 0.5
)
```
"""
Base.@kwdef struct DCLine <: NetworkEntity
    id::String
    name::String
    from_bus_id::String
    to_bus_id::String
    length_km::Float64
    max_flow_mw::Float64
    min_flow_mw::Float64
    resistance_ohm::Float64
    inductance_henry::Float64
    metadata::EntityMetadata = EntityMetadata()

    function DCLine(;
        id::String,
        name::String,
        from_bus_id::String,
        to_bus_id::String,
        length_km::Float64,
        max_flow_mw::Float64,
        min_flow_mw::Float64,
        resistance_ohm::Float64,
        inductance_henry::Float64,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)

        # Validate bus IDs
        from_bus_id = validate_id(from_bus_id)
        to_bus_id = validate_id(to_bus_id)

        if from_bus_id == to_bus_id
            throw(ArgumentError("from_bus_id and to_bus_id must be different"))
        end

        # Validate length
        length_km = validate_strictly_positive(length_km, "length_km")

        # Validate flow limits
        max_flow_mw = validate_strictly_positive(max_flow_mw, "max_flow_mw")
        min_flow_mw = validate_non_negative(min_flow_mw, "min_flow_mw")
        validate_min_leq_max(min_flow_mw, max_flow_mw, "min_flow", "max_flow")

        # Validate electrical parameters
        resistance_ohm = validate_non_negative(resistance_ohm, "resistance_ohm")
        inductance_henry = validate_non_negative(inductance_henry, "inductance_henry")

        new(
            id,
            name,
            from_bus_id,
            to_bus_id,
            length_km,
            max_flow_mw,
            min_flow_mw,
            resistance_ohm,
            inductance_henry,
            metadata,
        )
    end
end

# Export network types
export NetworkEntity, Bus, ACLine, DCLine
