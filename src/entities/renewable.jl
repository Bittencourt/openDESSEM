"""
    Renewable energy plant entities for OpenDESSEM.

Defines all renewable generation types including wind farms and solar farms.
"""

using Dates

"""
    RenewablePlant <: PhysicalEntity

Abstract base type for all renewable power plants.

Renewable plants generate electricity from variable resources:
- Wind farms with variable wind speeds
- Solar farms with diurnal generation patterns
- Future: biomass, geothermal, etc.
"""
abstract type RenewablePlant <: PhysicalEntity end

"""
    WindFarm <: RenewablePlant

Wind power generation plant.

Wind farms convert kinetic energy from wind into electricity using turbines.
Generation is highly variable and depends on wind speed patterns.

# Fields
- `id::String`: Unique plant identifier
- `name::String`: Human-readable plant name
- `bus_id::String`: Bus ID where plant is connected
- `submarket_id::String`: Submarket identifier
- `capacity_mw::Float64`: Maximum generation capacity (MW)
- `min_generation_mw::Float64`: Minimum generation (MW)
- `efficiency::Float64': Conversion efficiency (0-1)
- `must_run::Bool`: If true, plant generates when wind is available
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Generation limits: `min_gen * avail[t] <= g <= max_gen * avail[t]`
- Availability: typically from time series data (wind speed → power curve)
- Ramping: wind turbines have ramp rate limits

# Examples
```julia
farm = WindFarm(;
    id = "W_001",
    name = "Coastal Wind Farm",
    bus_id = "B001",
    submarket_id = "NE",
    capacity_mw = 200.0,
    min_generation_mw = 0.0,
    efficiency = 0.45,
    must_run = true
)
```
"""
Base.@kwdef struct WindFarm <: RenewablePlant
    id::String
    name::String
    bus_id::String
    submarket_id::String
    capacity_mw::Float64
    min_generation_mw::Float64
    efficiency::Float64
    must_run::Bool = true
    metadata::EntityMetadata = EntityMetadata()

    function WindFarm(;
        id::String,
        name::String,
        bus_id::String,
        submarket_id::String,
        capacity_mw::Float64,
        min_generation_mw::Float64,
        efficiency::Float64,
        must_run::Bool = true,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length = 2, max_length = 4)

        # Validate capacity
        capacity_mw = validate_strictly_positive(capacity_mw, "capacity_mw")
        min_generation_mw = validate_non_negative(min_generation_mw, "min_generation_mw")
        validate_min_leq_max(min_generation_mw, capacity_mw, "min_generation", "capacity")

        # Validate efficiency (0-1)
        efficiency = validate_percentage(efficiency * 100, "efficiency") / 100

        new(
            id,
            name,
            bus_id,
            submarket_id,
            capacity_mw,
            min_generation_mw,
            efficiency,
            must_run,
            metadata,
        )
    end
end

"""
    TrackingSystem

Solar panel tracking technology.
"""
@enum TrackingSystem begin
    FIXED           # Fixed tilt angle
    SINGLE_AXIS     # Tracks east-west movement
    DUAL_AXIS       # Tracks sun position in two dimensions
end

"""
    SolarFarm <: RenewablePlant

Solar photovoltaic power generation plant.

Solar farms convert sunlight into electricity using PV panels.
Generation follows diurnal patterns and depends on solar irradiance.

# Fields
- `id::String`: Unique plant identifier
- `name::String`: Human-readable plant name
- `bus_id::String`: Bus ID where plant is connected
- `submarket_id::String`: Submarket identifier
- `capacity_mw::Float64`: Maximum generation capacity (MW)
- `min_generation_mw::Float64`: Minimum generation (MW)
- `efficiency::Float64`: Panel conversion efficiency (0-1)
- `tracking::TrackingSystem`: Type of solar tracking system
- `must_run::Bool`: If true, plant generates when sunlight is available
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Generation limits: `min_gen * avail[t] <= g <= max_gen * avail[t]`
- Availability: from time series (solar irradiance → power output)
- Diurnal pattern: zero generation at night
- Tracking impact: single/dual-axis increases daily energy capture

# Examples
```julia
farm = SolarFarm(;
    id = "S_001",
    name = "Desert Solar Plant",
    bus_id = "B002",
    submarket_id = "NW",
    capacity_mw = 150.0,
    min_generation_mw = 0.0,
    efficiency = 0.22,
    tracking = SINGLE_AXIS,
    must_run = true
)
```
"""
Base.@kwdef struct SolarFarm <: RenewablePlant
    id::String
    name::String
    bus_id::String
    submarket_id::String
    capacity_mw::Float64
    min_generation_mw::Float64
    efficiency::Float64
    tracking::TrackingSystem
    must_run::Bool = true
    metadata::EntityMetadata = EntityMetadata()

    function SolarFarm(;
        id::String,
        name::String,
        bus_id::String,
        submarket_id::String,
        capacity_mw::Float64,
        min_generation_mw::Float64,
        efficiency::Float64,
        tracking::TrackingSystem,
        must_run::Bool = true,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length = 2, max_length = 4)

        # Validate capacity
        capacity_mw = validate_strictly_positive(capacity_mw, "capacity_mw")
        min_generation_mw = validate_non_negative(min_generation_mw, "min_generation_mw")
        validate_min_leq_max(min_generation_mw, capacity_mw, "min_generation", "capacity")

        # Validate efficiency (0-1)
        efficiency = validate_percentage(efficiency * 100, "efficiency") / 100

        # Validate tracking system (enum)
        if !(tracking in instances(TrackingSystem))
            throw(ArgumentError("tracking must be one of: FIXED, SINGLE_AXIS, DUAL_AXIS"))
        end

        new(
            id,
            name,
            bus_id,
            submarket_id,
            capacity_mw,
            min_generation_mw,
            efficiency,
            tracking,
            must_run,
            metadata,
        )
    end
end

# Export renewable types
export RenewablePlant, WindFarm, SolarFarm, TrackingSystem
export FIXED, SINGLE_AXIS, DUAL_AXIS
