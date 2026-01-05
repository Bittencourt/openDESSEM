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
struct Submarket <: MarketEntity
    id::String
    name::String
    code::String
    country::String
    description::String
    metadata::EntityMetadata

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
struct Load <: MarketEntity
    id::String
    name::String
    submarket_id::Union{String,Nothing}
    base_mw::Float64
    load_profile::Vector{Float64}
    is_elastic::Bool
    elasticity::Float64
    bus_id::Union{String,Nothing}
    metadata::EntityMetadata

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

"""
    BilateralContract <: MarketEntity

Bilateral contract between a seller and buyer for energy trading.

Bilateral contracts are pre-negotiated agreements for energy sales
outside of the spot market. They represent firm commitments that
must be honored in the scheduling.

# Fields
- `id::String`: Unique contract identifier
- `seller_id::String`: ID of the selling agent (generator or trader)
- `buyer_id::String`: ID of the buying agent (load or distributor)
- `energy_mwh::Float64`: Contracted energy amount (MWh)
- `price_rsj_per_mwh::Float64`: Contract price (R\$/MWh)
- `start_date::DateTime`: Contract start date
- `end_date::Union{DateTime, Nothing}`: Contract end date (nothing for indefinite)
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Energy balance: seller's generation must account for contracted energy
- Buyer's demand: contracted energy reduces spot market purchase
- Price settlement: difference between contract and spot price
- Must have seller != buyer (no self-contracting)

# Examples
```julia
contract = BilateralContract(;
    id = "BC_001",
    seller_id = "THERMAL_001",
    buyer_id = "DISTRIBUTOR_NE",
    energy_mwh = 1000.0,
    price_rsj_per_mwh = 150.0,
    start_date = DateTime(2024, 1, 1),
    end_date = DateTime(2024, 12, 31)
)
```
"""
struct BilateralContract <: MarketEntity
    id::String
    seller_id::String
    buyer_id::String
    energy_mwh::Float64
    price_rsj_per_mwh::Float64
    start_date::DateTime
    end_date::Union{DateTime,Nothing}
    metadata::EntityMetadata

    function BilateralContract(;
        id::String,
        seller_id::String,
        buyer_id::String,
        energy_mwh::Float64,
        price_rsj_per_mwh::Float64,
        start_date::DateTime,
        end_date::Union{DateTime,Nothing} = nothing,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID
        id = validate_id(id)
        seller_id = validate_id(seller_id)
        buyer_id = validate_id(buyer_id)

        # Seller and buyer must be different
        if seller_id == buyer_id
            throw(
                ArgumentError(
                    "seller_id and buyer_id must be different (got '$seller_id' for both)",
                ),
            )
        end

        # Validate energy (non-negative)
        energy_mwh = validate_non_negative(energy_mwh, "energy_mwh")

        # Validate price (non-negative)
        price_rsj_per_mwh = validate_non_negative(price_rsj_per_mwh, "price_rsj_per_mwh")

        # Validate end_date is after start_date
        if end_date !== nothing && end_date < start_date
            throw(
                ArgumentError(
                    "end_date ($end_date) must be after or equal to start_date ($start_date)",
                ),
            )
        end

        new(id, seller_id, buyer_id, energy_mwh, price_rsj_per_mwh, start_date, end_date, metadata)
    end
end

# Export market types
export MarketEntity, Submarket, Load, BilateralContract
