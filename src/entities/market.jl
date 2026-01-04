"""
    Market entities for OpenDESSEM.

Defines market structure components including submarkets and loads.
"""

using Dates

"""
    MarketEntity <: PhysicalEntity

Abstract base type for all market-related entities.

Market entities define the economic structure of the power system:
- Submarkets (geographical or bidding zones)
- Loads (demand curves)
"""
abstract type MarketEntity <: PhysicalEntity end

"""
    Submarket <: MarketEntity

Geographical or bidding zone in the electricity market.

Submarkets represent regions with specific characteristics,
price signals, and transmission constraints.

# Fields
- `id::String`: Unique submarket identifier
- `name::String`: Human-readable submarket name
- `code::String`: Short code (typically 2-4 characters)
- `country::String`: Country identifier
- `description::String`: Detailed description
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Energy balance: sum(generation) - sum(load) - net_interchange = 0
- Price formation: locational marginal prices (LMP) or uniform pricing
- Reserve requirements: regional reserve obligations

# Examples
```julia
submarket = Submarket(;
    id = "SM_001",
    name = "Southeast",
    code = "SE",
    country = "Brazil",
    description = "Southeast submarket including São Paulo and Rio"
)
```
"""
Base.@kwdef struct Submarket <: MarketEntity
    id::String
    name::String
    code::String
    country::String
    description::String = ""
    metadata::EntityMetadata = EntityMetadata()

    function Submarket(;
        id::String,
        name::String,
        code::String,
        country::String,
        description::String = "",
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)

        # Validate code (2-4 characters)
        code = validate_id(code; min_length = 2, max_length = 4)

        # Validate country
        country = validate_id(country; min_length = 2, max_length = 50)

        new(id, name, code, country, description, metadata)
    end
end

"""
    Load <: MarketEntity

Electricity demand (load) curve for a submarket or bus.

Loads represent time-varying electricity consumption that must be met
by generation and imports.

# Fields
- `id::String`: Unique load identifier
- `name::String`: Human-readable load name
- `submarket_id::Union{String, Nothing}`: Associated submarket ID
- `bus_id::Union{String, Nothing}`: Associated bus ID (for distributed loads)
- `base_mw::Float64`: Base demand (MW)
- `load_profile::Vector{Float64}`: Time series of load multipliers (typically normalized to 1.0)
- `is_elastic::Bool`: If true, demand responds to price
- `elasticity::Float64`: Price elasticity of demand (if elastic)
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Energy balance: `demand[t] = base_mw * load_profile[t]`
- Price response: `d_demand/d_price = elasticity * (demand/price)` (if elastic)
- Must be served: generation + imports >= demand (unless elastic)

# Examples
```julia
load = Load(;
    id = "LOAD_001",
    name = "Southeast Load",
    submarket_id = "SE",
    base_mw = 50000.0,
    load_profile = ones(168),  # Flat profile for 1 week
    is_elastic = false
)
```
"""
Base.@kwdef struct Load <: MarketEntity
    id::String
    name::String
    submarket_id::Union{String,Nothing}
    base_mw::Float64
    load_profile::Vector{Float64}
    is_elastic::Bool = false
    elasticity::Float64 = -0.1
    bus_id::Union{String,Nothing} = nothing
    metadata::EntityMetadata = EntityMetadata()

    function Load(;
        id::String,
        name::String,
        submarket_id::Union{String,Nothing},
        base_mw::Float64,
        load_profile::Vector{Float64},
        is_elastic::Bool = false,
        elasticity::Float64 = -0.1,
        bus_id::Union{String,Nothing} = nothing,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)

        # Validate submarket_id or bus_id (at least one required)
        if submarket_id === nothing && bus_id === nothing
            throw(ArgumentError("At least one of submarket_id or bus_id must be provided"))
        end

        if submarket_id !== nothing
            submarket_id = validate_id(submarket_id; min_length = 2, max_length = 4)
        end

        if bus_id !== nothing
            bus_id = validate_id(bus_id)
        end

        # Validate base demand
        base_mw = validate_strictly_positive(base_mw, "base_mw")

        # Validate load profile
        if isempty(load_profile)
            throw(ArgumentError("load_profile cannot be empty"))
        end

        if any(x -> x < 0, load_profile)
            throw(ArgumentError("load_profile cannot contain negative values"))
        end

        # Validate elasticity if load is elastic
        if is_elastic
            if elasticity >= 0
                throw(
                    ArgumentError(
                        "elasticity must be negative (demand decreases as price increases)",
                    ),
                )
            end
        end

        new(
            id,
            name,
            submarket_id,
            base_mw,
            load_profile,
            is_elastic,
            elasticity,
            bus_id,
            metadata,
        )
    end
end

# Export market types
export MarketEntity, Submarket, Load
