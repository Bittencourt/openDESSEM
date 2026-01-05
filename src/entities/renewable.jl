"""
    Renewable energy plant entities for OpenDESSEM.

Defines renewable generation types with intermittent characteristics including
wind and solar plants with time-varying capacity forecasts.
"""

using Dates

"""
    RenewableType

Enumeration of renewable energy plant types.

# Values
- `WIND`: Wind power generation
- `SOLAR`: Solar photovoltaic generation
"""
@enum RenewableType begin
    WIND
    SOLAR
end

"""
    ForecastType

Enumeration of forecast types for renewable generation.

# Values
- `DETERMINISTIC`: Single deterministic forecast scenario
- `STOCHASTIC`: Probabilistic forecast with distribution
- `SCENARIO_BASED`: Multiple explicit forecast scenarios
"""
@enum ForecastType begin
    DETERMINISTIC
    STOCHASTIC
    SCENARIO_BASED
end

"""
    RenewablePlant <: PhysicalEntity

Abstract base type for all renewable power plants.

Renewable plants generate electricity from variable resources:
- Wind farms with variable wind speeds
- Solar farms with diurnal generation patterns

Key characteristics:
- Zero marginal cost (fuel is free)
- Intermittent generation based on weather
- Capacity varies by time period (from forecasts)
- Potential for curtailment
"""
abstract type RenewablePlant <: PhysicalEntity end

"""
    WindPlant <: RenewablePlant

Wind power generation plant with time-varying capacity forecasts.

Wind plants convert kinetic energy from wind into electricity using turbines.
Generation is highly variable and depends on wind speed patterns, making
forecasts essential for operational planning.

# Fields
- `id::String`: Unique plant identifier (e.g., "W_NE_001")
- `name::String`: Human-readable plant name
- `bus_id::String`: Bus ID where plant is connected
- `submarket_id::String`: Submarket identifier (e.g., "NE", "SE")
- `installed_capacity_mw::Float64`: Nameplate capacity (MW)
- `capacity_forecast_mw::Vector{Float64}`: Available capacity by time period (MW)
- `forecast_type::ForecastType`: Type of forecast (DETERMINISTIC/STOCHASTIC/SCENARIO_BASED)
- `min_generation_mw::Float64`: Minimum stable generation (MW, typically 0)
- `max_generation_mw::Float64`: Maximum generation (MW, capped by forecast)
- `ramp_up_mw_per_min::Float64`: Maximum ramp-up rate (MW/min)
- `ramp_down_mw_per_min::Float64`: Maximum ramp-down rate (MW/min)
- `curtailment_allowed::Bool`: Can generation be reduced below forecast?
- `forced_outage_rate::Float64`: Probability of unavailability (0-1)
- `is_dispatchable::Bool`: Can generation be controlled? (false = pure pass-through)
- `commissioning_date::DateTime`: Plant commissioning date (ONS compatibility)
- `num_turbines::Int`: Number of wind turbines (ONS compatibility)
- `must_run::Bool`: If true, plant generates when wind is available
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Capacity limit: `g[t] <= capacity_forecast_mw[t]` (intermittent availability)
- Curtailment: `g[t] <= capacity_forecast_mw[t]` if curtailment_allowed = true
- Ramp limits: `g[t] - g[t-1] <= ramp_up * 60` (wind changes gradually)
- Minimum generation: `g[t] >= min_generation_mw` if is_dispatchable = true

# Operational Characteristics
- **Zero marginal cost**: No fuel costs
- **Intermittent**: Generation follows wind speed patterns
- **Forecast-dependent**: Capacity varies by time period
- **Curtailable**: Can reduce output if needed (grid balancing)
- **Limited control**: Wind has physical ramp rate constraints

# Examples
```julia
# Wind plant with 24-hour forecast
wind = WindPlant(;
    id = "W_NE_001",
    name = "Nordeste Wind Farm 1",
    bus_id = "NE_230KV_001",
    submarket_id = "NE",
    installed_capacity_mw = 200.0,
    capacity_forecast_mw = [180.0, 175.0, 160.0, 150.0, 140.0, 130.0,
                            125.0, 120.0, 115.0, 110.0, 105.0, 100.0,
                            95.0, 90.0, 85.0, 80.0, 75.0, 70.0,
                             65.0, 60.0, 55.0, 50.0, 45.0, 40.0],
    forecast_type = DETERMINISTIC,
    min_generation_mw = 0.0,
    max_generation_mw = 200.0,
    ramp_up_mw_per_min = 10.0,
    ramp_down_mw_per_min = 10.0,
    curtailment_allowed = true,
    forced_outage_rate = 0.02,
    is_dispatchable = false,
    commissioning_date = DateTime(2018, 6, 15),
    num_turbines = 50,
    must_run = true
)

# Wind plant with stochastic forecast
wind_stochastic = WindPlant(;
    id = "W_SE_002",
    name = "Sudeste Offshore Wind",
    bus_id = "SE_230KV_002",
    submarket_id = "SE",
    installed_capacity_mw = 500.0,
    capacity_forecast_mw = fill(400.0, 168),  # Weekly horizon
    forecast_type = STOCHASTIC,
    min_generation_mw = 0.0,
    max_generation_mw = 500.0,
    ramp_up_mw_per_min = 25.0,
    ramp_down_mw_per_min = 25.0,
    curtailment_allowed = true,
    forced_outage_rate = 0.03,
    is_dispatchable = false,
    commissioning_date = DateTime(2020, 3, 10),
    num_turbines = 100
)
```
"""
struct WindPlant <: RenewablePlant
    id::String
    name::String
    bus_id::String
    submarket_id::String
    installed_capacity_mw::Float64
    capacity_forecast_mw::Vector{Float64}
    forecast_type::ForecastType
    min_generation_mw::Float64
    max_generation_mw::Float64
    ramp_up_mw_per_min::Float64
    ramp_down_mw_per_min::Float64
    curtailment_allowed::Bool
    forced_outage_rate::Float64
    is_dispatchable::Bool
    commissioning_date::DateTime
    num_turbines::Int
    must_run::Bool
    metadata::EntityMetadata

    function WindPlant(;
        id::String,
        name::String,
        bus_id::String,
        submarket_id::String,
        installed_capacity_mw::Float64,
        capacity_forecast_mw::Vector{Float64},
        forecast_type::ForecastType,
        min_generation_mw::Float64,
        max_generation_mw::Float64,
        ramp_up_mw_per_min::Float64,
        ramp_down_mw_per_min::Float64,
        curtailment_allowed::Bool,
        forced_outage_rate::Float64,
        is_dispatchable::Bool,
        commissioning_date::DateTime,
        num_turbines::Int = 1,
        must_run::Bool = true,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length = 2, max_length = 4)

        # Validate capacity
        installed_capacity_mw =
            validate_strictly_positive(installed_capacity_mw, "installed_capacity_mw")

        # Validate forecast dimensions (must be non-empty)
        if isempty(capacity_forecast_mw)
            throw(ArgumentError("capacity_forecast_mw cannot be empty"))
        end

        # Validate forecast values (all non-negative, ≤ installed capacity)
        for (t, forecast) in enumerate(capacity_forecast_mw)
            if forecast < 0
                throw(
                    ArgumentError(
                        "capacity_forecast_mw[$t] must be non-negative (got $forecast)",
                    ),
                )
            end
            if forecast > installed_capacity_mw
                throw(
                    ArgumentError(
                        "capacity_forecast_mw[$t] ($forecast) cannot exceed installed_capacity_mw ($installed_capacity_mw)",
                    ),
                )
            end
        end

        # Validate forecast type (enum)
        if !(forecast_type in instances(ForecastType))
            throw(
                ArgumentError(
                    "forecast_type must be one of: DETERMINISTIC, STOCHASTIC, SCENARIO_BASED",
                ),
            )
        end

        # Validate generation limits
        min_generation_mw =
            validate_non_negative(min_generation_mw, "min_generation_mw")
        max_generation_mw = validate_positive(max_generation_mw, "max_generation_mw")
        validate_min_leq_max(
            min_generation_mw,
            max_generation_mw,
            "min_generation_mw",
            "max_generation_mw",
        )
        validate_min_leq_max(
            max_generation_mw,
            installed_capacity_mw,
            "max_generation_mw",
            "installed_capacity_mw",
        )

        # Validate ramp rates
        ramp_up_mw_per_min = validate_non_negative(ramp_up_mw_per_min, "ramp_up_mw_per_min")
        ramp_down_mw_per_min = validate_non_negative(
            ramp_down_mw_per_min,
            "ramp_down_mw_per_min",
        )

        # Validate forced outage rate (0-1)
        if forced_outage_rate < 0 || forced_outage_rate > 1
            throw(
                ArgumentError(
                    "forced_outage_rate must be between 0 and 1 (got $forced_outage_rate)",
                ),
            )
        end

        # Curtailment only allowed if dispatchable
        if curtailment_allowed && !is_dispatchable
            @warn "curtailment_allowed=true but is_dispatchable=false for plant $id; forcing curtailment_allowed=false"
            curtailment_allowed = false
        end

        # Validate num_turbines
        if num_turbines < 1
            throw(ArgumentError("num_turbines must be at least 1 (got $num_turbines)"))
        end

        new(
            id,
            name,
            bus_id,
            submarket_id,
            installed_capacity_mw,
            capacity_forecast_mw,
            forecast_type,
            min_generation_mw,
            max_generation_mw,
            ramp_up_mw_per_min,
            ramp_down_mw_per_min,
            curtailment_allowed,
            forced_outage_rate,
            is_dispatchable,
            commissioning_date,
            num_turbines,
            must_run,
            metadata,
        )
    end
end

"""
    SolarPlant <: RenewablePlant

Solar photovoltaic power generation plant with time-varying capacity forecasts.

Solar farms convert sunlight into electricity using PV panels. Generation follows
diurnal patterns (zero at night) and depends on solar irradiance, weather
conditions, and time of year.

# Fields
- `id::String`: Unique plant identifier (e.g., "S_SE_001")
- `name::String`: Human-readable plant name
- `bus_id::String`: Bus ID where plant is connected
- `submarket_id::String`: Submarket identifier (e.g., "SE", "NE")
- `installed_capacity_mw::Float64`: Nameplate capacity (MW)
- `capacity_forecast_mw::Vector{Float64}`: Available capacity by time period (MW)
- `forecast_type::ForecastType`: Type of forecast (DETERMINISTIC/STOCHASTIC/SCENARIO_BASED)
- `min_generation_mw::Float64`: Minimum generation (MW, typically 0)
- `max_generation_mw::Float64`: Maximum generation (MW, capped by forecast)
- `ramp_up_mw_per_min::Float64`: Maximum ramp-up rate (MW/min)
- `ramp_down_mw_per_min::Float64`: Maximum ramp-down rate (MW/min)
- `curtailment_allowed::Bool`: Can generation be reduced below forecast?
- `forced_outage_rate::Float64`: Probability of unavailability (0-1)
- `is_dispatchable::Bool`: Can generation be controlled? (false = pure pass-through)
- `commissioning_date::DateTime`: Plant commissioning date (ONS compatibility)
- `tracking_system::String`: Type of tracking (FIXED, SINGLE_AXIS, DUAL_AXIS)
- `must_run::Bool`: If true, plant generates when sunlight is available
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Capacity limit: `g[t] <= capacity_forecast_mw[t]` (intermittent availability)
- Curtailment: `g[t] <= capacity_forecast_mw[t]` if curtailment_allowed = true
- Ramp limits: `g[t] - g[t-1] <= ramp_up * 60` (solar has very fast ramping)
- Diurnal pattern: `capacity_forecast_mw[t] = 0` at night (implicitly enforced)

# Operational Characteristics
- **Zero marginal cost**: No fuel costs
- **Diurnal pattern**: Zero generation at night
- **Weather-dependent**: Clouds, rain reduce output
- **Fast ramping**: Solar output can change rapidly (cloud transients)
- **Predictable**: Sunrise/sunset times are known

# Examples
```julia
# Solar plant with 24-hour forecast (daytime only generation)
solar = SolarPlant(;
    id = "S_SE_001",
    name = "Sudeste Solar Farm 1",
    bus_id = "SE_230KV_001",
    submarket_id = "SE",
    installed_capacity_mw = 150.0,
    capacity_forecast_mw = [
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,    # Midnight to 5 AM
        10.0, 30.0, 60.0, 95.0, 130.0, 145.0,  # Sunrise to noon
        140.0, 120.0, 90.0, 50.0, 20.0, 5.0,   # Afternoon to sunset
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0     # Evening to midnight
    ],
    forecast_type = DETERMINISTIC,
    min_generation_mw = 0.0,
    max_generation_mw = 150.0,
    ramp_up_mw_per_min = 50.0,  # Solar has very fast ramping
    ramp_down_mw_per_min = 50.0,
    curtailment_allowed = true,
    forced_outage_rate = 0.01,
    is_dispatchable = false,
    commissioning_date = DateTime(2019, 9, 20),
    tracking_system = "SINGLE_AXIS",
    must_run = true
)

# Solar plant with tracking system
solar_tracking = SolarPlant(;
    id = "S_NE_002",
    name = "Nordeste Solar with Tracking",
    bus_id = "NE_230KV_002",
    submarket_id = "NE",
    installed_capacity_mw = 200.0,
    capacity_forecast_mw = fill(180.0, 24),  # Simplified constant day capacity
    forecast_type = DETERMINISTIC,
    min_generation_mw = 0.0,
    max_generation_mw = 200.0,
    ramp_up_mw_per_min = 75.0,
    ramp_down_mw_per_min = 75.0,
    curtailment_allowed = true,
    forced_outage_rate = 0.015,
    is_dispatchable = false,
    commissioning_date = DateTime(2021, 4, 10),
    tracking_system = "DUAL_AXIS"
)
```
"""
struct SolarPlant <: RenewablePlant
    id::String
    name::String
    bus_id::String
    submarket_id::String
    installed_capacity_mw::Float64
    capacity_forecast_mw::Vector{Float64}
    forecast_type::ForecastType
    min_generation_mw::Float64
    max_generation_mw::Float64
    ramp_up_mw_per_min::Float64
    ramp_down_mw_per_min::Float64
    curtailment_allowed::Bool
    forced_outage_rate::Float64
    is_dispatchable::Bool
    commissioning_date::DateTime
    tracking_system::String
    must_run::Bool
    metadata::EntityMetadata

    function SolarPlant(;
        id::String,
        name::String,
        bus_id::String,
        submarket_id::String,
        installed_capacity_mw::Float64,
        capacity_forecast_mw::Vector{Float64},
        forecast_type::ForecastType,
        min_generation_mw::Float64,
        max_generation_mw::Float64,
        ramp_up_mw_per_min::Float64,
        ramp_down_mw_per_min::Float64,
        curtailment_allowed::Bool,
        forced_outage_rate::Float64,
        is_dispatchable::Bool,
        commissioning_date::DateTime,
        tracking_system::String = "FIXED",
        must_run::Bool = true,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length = 2, max_length = 4)

        # Validate capacity
        installed_capacity_mw =
            validate_strictly_positive(installed_capacity_mw, "installed_capacity_mw")

        # Validate forecast dimensions (must be non-empty)
        if isempty(capacity_forecast_mw)
            throw(ArgumentError("capacity_forecast_mw cannot be empty"))
        end

        # Validate forecast values (all non-negative, ≤ installed capacity)
        for (t, forecast) in enumerate(capacity_forecast_mw)
            if forecast < 0
                throw(
                    ArgumentError(
                        "capacity_forecast_mw[$t] must be non-negative (got $forecast)",
                    ),
                )
            end
            if forecast > installed_capacity_mw
                throw(
                    ArgumentError(
                        "capacity_forecast_mw[$t] ($forecast) cannot exceed installed_capacity_mw ($installed_capacity_mw)",
                    ),
                )
            end
        end

        # Validate forecast type (enum)
        if !(forecast_type in instances(ForecastType))
            throw(
                ArgumentError(
                    "forecast_type must be one of: DETERMINISTIC, STOCHASTIC, SCENARIO_BASED",
                ),
            )
        end

        # Validate generation limits
        min_generation_mw =
            validate_non_negative(min_generation_mw, "min_generation_mw")
        max_generation_mw = validate_positive(max_generation_mw, "max_generation_mw")
        validate_min_leq_max(
            min_generation_mw,
            max_generation_mw,
            "min_generation_mw",
            "max_generation_mw",
        )
        validate_min_leq_max(
            max_generation_mw,
            installed_capacity_mw,
            "max_generation_mw",
            "installed_capacity_mw",
        )

        # Validate ramp rates (solar has very fast ramping)
        ramp_up_mw_per_min = validate_non_negative(ramp_up_mw_per_min, "ramp_up_mw_per_min")
        ramp_down_mw_per_min = validate_non_negative(
            ramp_down_mw_per_min,
            "ramp_down_mw_per_min",
        )

        # Validate forced outage rate (0-1)
        if forced_outage_rate < 0 || forced_outage_rate > 1
            throw(
                ArgumentError(
                    "forced_outage_rate must be between 0 and 1 (got $forced_outage_rate)",
                ),
            )
        end

        # Curtailment only allowed if dispatchable
        if curtailment_allowed && !is_dispatchable
            @warn "curtailment_allowed=true but is_dispatchable=false for plant $id" curtailment_allowed = false
        end

        # Validate tracking system
        valid_tracking = ["FIXED", "SINGLE_AXIS", "DUAL_AXIS"]
        if !(uppercase(tracking_system) in valid_tracking)
            throw(
                ArgumentError(
                    "tracking_system must be one of: $(join(valid_tracking, ", ")) (got $tracking_system)",
                ),
            )
        end

        new(
            id,
            name,
            bus_id,
            submarket_id,
            installed_capacity_mw,
            capacity_forecast_mw,
            forecast_type,
            min_generation_mw,
            max_generation_mw,
            ramp_up_mw_per_min,
            ramp_down_mw_per_min,
            curtailment_allowed,
            forced_outage_rate,
            is_dispatchable,
            commissioning_date,
            uppercase(tracking_system),
            must_run,
            metadata,
        )
    end
end

# Export renewable types and enums
export RenewablePlant, WindPlant, SolarPlant
export RenewableType, ForecastType, WIND, SOLAR
export DETERMINISTIC, STOCHASTIC, SCENARIO_BASED
