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
struct Bus <: NetworkEntity
    id::String
    name::String
    voltage_kv::Float64
    base_kv::Float64
    dc_bus::Bool
    is_reference::Bool
    area_id::Union{String,Nothing}
    zone_id::Union{String,Nothing}
    latitude::Union{Float64,Nothing}
    longitude::Union{Float64,Nothing}
    metadata::EntityMetadata

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
struct ACLine <: NetworkEntity
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
    num_circuits::Int
    metadata::EntityMetadata

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
struct DCLine <: NetworkEntity
    id::String
    name::String
    from_bus_id::String
    to_bus_id::String
    length_km::Float64
    max_flow_mw::Float64
    min_flow_mw::Float64
    resistance_ohm::Float64
    inductance_henry::Float64
    metadata::EntityMetadata

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

"""
    NetworkLoad <: NetworkEntity

Electrical load (demand) connected to a bus in the transmission network.

Network loads represent physical demand points at specific buses.
They can be firm (must be served) or curtailable (can be interrupted).

This is distinct from the MarketEntity Load type, which represents
economic demand curves. NetworkLoad is for physical transmission modeling.

# Fields
- `id::String`: Unique load identifier
- `name::String`: Human-readable load name
- `bus_id::String`: Bus ID where load is connected
- `submarket_id::String`: Submarket identifier (e.g., "SE", "NE", "S", "N")
- `load_profile_mw::Vector{Float64}`: Demand by time period (MW)
- `is_firm::Bool`: If true, load must be served (cannot be curtailed)
- `is_interruptible::Bool`: If true, can be interrupted for payment
- `priority::Int`: Service priority (1-10, 1 = highest priority)
- `price_elasticity::Union{Float64, Nothing}`: Price elasticity of demand (typically negative)
- `interruption_cost_rs_per_mwh::Union{Float64, Nothing}`: Cost to curtail (BRL per MWh)
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Load shedding: `served[t] <= load_profile[t]`
- Curtailment: if not firm, can reduce served load
- Interruption: if interruptible, can reduce for payment
- Priority: lower priority loads curtailed first

# Examples
```julia
load = NetworkLoad(;
    id = "LOAD_001",
    name = "Industrial Load Alpha",
    bus_id = "B_001",
    submarket_id = "SE",
    load_profile_mw = collect(100.0:10.0:330.0),  # 24-hour profile
    is_firm = true,
    is_interruptible = false,
    priority = 1,
    price_elasticity = -0.1,
    interruption_cost_rs_per_mwh = 5000.0
)
```
"""
struct NetworkLoad <: NetworkEntity
    id::String
    name::String
    bus_id::String
    submarket_id::String
    load_profile_mw::Vector{Float64}
    is_firm::Bool
    is_interruptible::Bool
    priority::Int
    price_elasticity::Union{Float64,Nothing}
    interruption_cost_rs_per_mwh::Union{Float64,Nothing}
    metadata::EntityMetadata

    function NetworkLoad(;
        id::String,
        name::String,
        bus_id::String,
        submarket_id::String,
        load_profile_mw::Vector{Float64},
        is_firm::Bool = true,
        is_interruptible::Bool = false,
        priority::Int = 5,
        price_elasticity::Union{Float64,Nothing} = nothing,
        interruption_cost_rs_per_mwh::Union{Float64,Nothing} = nothing,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length = 1, max_length = 4)

        # Validate load profile
        if isempty(load_profile_mw)
            throw(ArgumentError("load_profile_mw cannot be empty"))
        end

        for (i, demand) in enumerate(load_profile_mw)
            if demand <= 0
                throw(
                    ArgumentError(
                        "load_profile_mw[$i] must be positive (got $demand). Zero or negative demand is not valid for a load.",
                    ),
                )
            end
        end

        # Validate firm/interruptible logic
        if is_firm && is_interruptible
            throw(
                ArgumentError(
                    "Load cannot be both firm (must be served) and interruptible (can be curtailed)",
                ),
            )
        end

        # Validate priority
        if priority < 1 || priority > 10
            throw(ArgumentError("priority must be between 1 and 10 (got $priority)"))
        end

        # Validate price elasticity
        if price_elasticity !== nothing
            # Price elasticity should be negative (demand decreases as price increases)
            if price_elasticity > 0
                throw(
                    ArgumentError(
                        "price_elasticity should be negative (demand decreases as price increases), got $price_elasticity",
                    ),
                )
            end
            if price_elasticity < -1.0
                throw(
                    ArgumentError(
                        "price_elasticity should be >= -1.0 (elastic but not infinitely elastic), got $price_elasticity",
                    ),
                )
            end
        end

        # Validate interruption cost
        if interruption_cost_rs_per_mwh !== nothing
            if interruption_cost_rs_per_mwh < 0
                throw(
                    ArgumentError(
                        "interruption_cost_rs_per_mwh must be non-negative (got $interruption_cost_rs_per_mwh)",
                    ),
                )
            end
        end

        new(
            id,
            name,
            bus_id,
            submarket_id,
            load_profile_mw,
            is_firm,
            is_interruptible,
            priority,
            price_elasticity,
            interruption_cost_rs_per_mwh,
            metadata,
        )
    end
end

"""
    NetworkSubmarket <: NetworkEntity

Geographic region/submarket in the Brazilian power system with transmission interconnections.

Brazil has 4 main submarkets interconnected by transmission lines:
- SE/CO: Sudeste/Centro-Oeste (Southeast/Central-West)
- S: South
- NE: Northeast
- N: North

Network submarkets have transmission interconnection limits and reference buses
for power flow calculations.

This is distinct from the MarketEntity Submarket type, which represents
economic bidding zones. NetworkSubmarket is for physical transmission modeling.

# Fields
- `id::String`: Submarket ID ("SE", "S", "NE", "N")
- `name::String`: Full submarket name
- `demand_forecast_mw::Vector{Float64}`: Aggregated demand by time period (MW)
- `interconnection_capacity_mw::Dict{String, Float64}`: Max transfer to/from other submarkets (MW)
- `reference_bus_id::String`: Reference/slack bus for marginal price calculation
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Interconnection limits: `import/export <= capacity`
- Energy balance: `generation + import = demand + export`
- Marginal price: calculated at reference bus

# Examples
```julia
submarket = NetworkSubmarket(;
    id = "SE",
    name = "Sudeste/Centro-Oeste",
    demand_forecast_mw = collect(10000.0:100.0:12300.0),
    interconnection_capacity_mw = Dict(
        "S" => 2000.0,
        "NE" => 1500.0,
        "N" => 1000.0
    ),
    reference_bus_id = "BUS_SE_REF"
)
```
"""
struct NetworkSubmarket <: NetworkEntity
    id::String
    name::String
    demand_forecast_mw::Vector{Float64}
    interconnection_capacity_mw::Dict{String,Float64}
    reference_bus_id::String
    metadata::EntityMetadata

    function NetworkSubmarket(;
        id::String,
        name::String,
        demand_forecast_mw::Vector{Float64},
        interconnection_capacity_mw::Dict{String,Float64},
        reference_bus_id::String,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate submarket ID (must be one of the 4 Brazilian submarkets)
        valid_submarkets = ["SE", "S", "NE", "N"]
        id = validate_one_of(id, valid_submarkets, "id")

        # Validate name
        name = validate_name(name)

        # Validate demand forecast
        if isempty(demand_forecast_mw)
            throw(ArgumentError("demand_forecast_mw cannot be empty"))
        end

        for (i, demand) in enumerate(demand_forecast_mw)
            if demand <= 0
                throw(
                    ArgumentError("demand_forecast_mw[$i] must be positive (got $demand)"),
                )
            end
        end

        # Validate interconnections
        if isempty(interconnection_capacity_mw)
            throw(ArgumentError("interconnection_capacity_mw cannot be empty"))
        end

        for (other_id, capacity) in interconnection_capacity_mw
            # Validate other submarket ID
            if !(other_id in valid_submarkets)
                throw(
                    ArgumentError(
                        "Invalid interconnection submarket ID '$other_id'. Must be one of $(join(valid_submarkets, ", "))",
                    ),
                )
            end

            # Check for self-interconnection
            if other_id == id
                throw(
                    ArgumentError("Submarket '$id' cannot have interconnection to itself"),
                )
            end

            # Validate capacity
            if capacity <= 0
                throw(
                    ArgumentError(
                        "Interconnection capacity to '$other_id' must be positive (got $capacity)",
                    ),
                )
            end
        end

        # Validate reference bus ID
        reference_bus_id = validate_id(reference_bus_id)

        new(
            id,
            name,
            demand_forecast_mw,
            interconnection_capacity_mw,
            reference_bus_id,
            metadata,
        )
    end
end

# Export network types
export NetworkEntity, Bus, ACLine, DCLine, NetworkLoad, NetworkSubmarket
