"""
    Thermal power plant entities for OpenDESSEM.

Defines all thermal plant types including conventional thermal and combined-cycle plants.
"""

using Dates

"""
    ThermalPlant <: PhysicalEntity

Abstract base type for all thermal power plants.

Thermal plants generate electricity from heat sources:
- Fossil fuels (coal, natural gas, oil)
- Nuclear
- Biomass
- Biogas
"""
abstract type ThermalPlant <: PhysicalEntity end

"""
    FuelType

Enumeration of supported fuel types for thermal plants.

# Values
- `NATURAL_GAS`: Natural gas (including LNG)
- `COAL`: Coal (various types)
- `FUEL_OIL`: Fuel oil/diesel
- `DIESEL`: Diesel fuel
- `NUCLEAR`: Nuclear fuel
- `BIOMASS`: Biomass (wood, agricultural waste)
- `BIOGAS`: Biogas (landfill gas, anaerobic digestion)
- `OTHER`: Other fuel types
"""
@enum FuelType begin
    NATURAL_GAS
    COAL
    FUEL_OIL
    DIESEL
    NUCLEAR
    BIOMASS
    BIOGAS
    OTHER
end

"""
    ConventionalThermal <: ThermalPlant

Standard thermal power plant with unit commitment constraints.

Represents conventional thermal generating units including:
- Coal-fired power plants
- Natural gas simple cycle plants
- Oil-fired plants
- Nuclear plants
- Biomass plants

# Fields
- `id::String`: Unique plant identifier (e.g., "T_SE_001")
- `name::String`: Human-readable plant name
- `bus_id::String`: Bus ID where plant is connected
- `submarket_id::String`: Submarket identifier (e.g., "SE", "NE", "S", "N")
- `fuel_type::FuelType`: Primary fuel type
- `capacity_mw::Float64`: Installed capacity (MW)
- `min_generation_mw::Float64`: Minimum stable generation (MW)
- `max_generation_mw::Float64`: Maximum generation (MW)
- `ramp_up_mw_per_min::Float64`: Ramp-up rate (MW/min)
- `ramp_down_mw_per_min::Float64`: Ramp-down rate (MW/min)
- `min_up_time_hours::Int`: Minimum time online after startup (hours)
- `min_down_time_hours::Int`: Minimum time offline after shutdown (hours)
- `fuel_cost_rsj_per_mwh::Float64`: Fuel cost (R\$/MWh), can be time-varying
- `startup_cost_rs::Float64`: Fixed startup cost (R\$)
- `shutdown_cost_rs::Float64`: Fixed shutdown cost (R\$)
- `must_run::Bool`: If true, unit must remain committed (rare)
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Energy balance: `min_gen * u <= g <= max_gen * u`
- Ramp limits: `g[t] - g[t-1] <= ramp_up * 60`
- Minimum up/down time: prevent rapid cycling
- Startup/shutdown logic: `u[t] - u[t-1] = z[t] - w[t]`

# Examples
```julia
plant = ConventionalThermal(;
    id="T_SE_001",
    name="Sudeste Gas Plant 1",
    bus_id="SE_230KV_001",
    submarket_id="SE",
    fuel_type=NATURAL_GAS,
    capacity_mw=500.0,
    min_generation_mw=150.0,
    max_generation_mw=500.0,
    ramp_up_mw_per_min=50.0,
    ramp_down_mw_per_min=50.0,
    min_up_time_hours=6,
    min_down_time_hours=4,
    fuel_cost_rsj_per_mwh=150.0,
    startup_cost_rs=15000.0,
    shutdown_cost_rs=8000.0,
    must_run=false
)
```
"""
Base.@kwdef struct ConventionalThermal <: ThermalPlant
    id::String
    name::String
    bus_id::String
    submarket_id::String
    fuel_type::FuelType
    capacity_mw::Float64
    min_generation_mw::Float64
    max_generation_mw::Float64
    ramp_up_mw_per_min::Float64
    ramp_down_mw_per_min::Float64
    min_up_time_hours::Int
    min_down_time_hours::Int
    fuel_cost_rsj_per_mwh::Float64
    startup_cost_rs::Float64
    shutdown_cost_rs::Float64
    must_run::Bool = false
    metadata::EntityMetadata = EntityMetadata()

    function ConventionalThermal(;
            id::String,
            name::String,
            bus_id::String,
            submarket_id::String,
            fuel_type::FuelType,
            capacity_mw::Float64,
            min_generation_mw::Float64,
            max_generation_mw::Float64,
            ramp_up_mw_per_min::Float64,
            ramp_down_mw_per_min::Float64,
            min_up_time_hours::Int,
            min_down_time_hours::Int,
            fuel_cost_rsj_per_mwh::Float64,
            startup_cost_rs::Float64,
            shutdown_cost_rs::Float64,
            must_run::Bool = false,
            metadata::EntityMetadata = EntityMetadata()
        )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length=2, max_length=4)

        # Validate capacity
        capacity_mw = validate_strictly_positive(capacity_mw, "capacity_mw")

        # Validate generation limits
        min_generation_mw = validate_non_negative(min_generation_mw, "min_generation_mw")
        max_generation_mw = validate_positive(max_generation_mw, "max_generation_mw")
        validate_min_leq_max(min_generation_mw, max_generation_mw, "min_generation_mw", "max_generation_mw")
        validate_min_leq_max(max_generation_mw, capacity_mw, "max_generation_mw", "capacity_mw")

        # Validate ramp rates
        ramp_up_mw_per_min = validate_non_negative(ramp_up_mw_per_min, "ramp_up_mw_per_min")
        ramp_down_mw_per_min = validate_non_negative(ramp_down_mw_per_min, "ramp_down_mw_per_min")

        # Validate time constraints
        if min_up_time_hours < 0
            throw(ArgumentError("min_up_time_hours must be non-negative (got $min_up_time_hours)"))
        end
        if min_down_time_hours < 0
            throw(ArgumentError("min_down_time_hours must be non-negative (got $min_down_time_hours)"))
        end

        # Validate costs
        fuel_cost_rsj_per_mwh = validate_non_negative(fuel_cost_rsj_per_mwh, "fuel_cost_rsj_per_mwh")
        startup_cost_rs = validate_non_negative(startup_cost_rs, "startup_cost_rs")
        shutdown_cost_rs = validate_non_negative(shutdown_cost_rs, "shutdown_cost_rs")

        new(id, name, bus_id, submarket_id, fuel_type, capacity_mw,
            min_generation_mw, max_generation_mw, ramp_up_mw_per_min, ramp_down_mw_per_min,
            min_up_time_hours, min_down_time_hours, fuel_cost_rsj_per_mwh,
            startup_cost_rs, shutdown_cost_rs, must_run, metadata)
    end
end

"""
    CombinedCyclePlant <: ThermalPlant

Combined-cycle gas turbine (CCGT) power plant.

CCGT plants operate in multiple modes:
1. Gas-only mode: Only gas turbine(s) operating
2. Combined mode: Gas + steam turbines operating
3. Steam-only mode: Only steam turbine (rare, using duct burners)

# Fields
- `id::String`: Unique plant identifier
- `name::String`: Human-readable plant name
- `bus_id::String`: Bus ID where plant is connected
- `submarket_id::String`: Submarket identifier
- `fuel_type::FuelType`: Primary fuel (typically NATURAL_GAS)
- `capacity_mw::Float64`: Total installed capacity (MW)
- `gas_turbine_capacity_mw::Float64`: Gas turbine capacity (MW)
- `steam_turbine_capacity_mw::Float64`: Steam turbine capacity (MW)
- `min_generation_gas_only_mw::Float64`: Minimum generation in gas-only mode (MW)
- `min_generation_combined_mw::Float64`: Minimum generation in combined mode (MW)
- `max_generation_combined_mw::Float64`: Maximum generation in combined mode (MW)
- `ramp_up_mw_per_min::Float64`: Ramp-up rate (MW/min)
- `ramp_down_mw_per_min::Float64`: Ramp-down rate (MW/min)
- `min_up_time_hours::Int`: Minimum time online after startup (hours)
- `min_down_time_hours::Int`: Minimum time offline after shutdown (hours)
- `fuel_cost_rsj_per_mwh::Float64`: Fuel cost (R\$/MWh)
- `startup_cost_rs::Float64`: Fixed startup cost (R\$)
- `shutdown_cost_rs::Float64`: Fixed shutdown cost (R\$)
- `heat_rate_gas_only::Float64`: Heat rate in gas-only mode (GJ/MWh)
- `heat_rate_combined::Float64`: Heat rate in combined mode (GJ/MWh)
- `must_run::Bool`: If true, unit must remain committed
- `metadata::EntityMetadata`: Additional metadata

# Examples
```julia
plant = CombinedCyclePlant(;
    id="CCGT_001",
    name="Combined Cycle Plant 1",
    bus_id="SE_230KV_001",
    submarket_id="SE",
    fuel_type=NATURAL_GAS,
    capacity_mw=800.0,
    gas_turbine_capacity_mw=500.0,
    steam_turbine_capacity_mw=300.0,
    min_generation_gas_only_mw=200.0,
    min_generation_combined_mw=400.0,
    max_generation_combined_mw=800.0,
    ramp_up_mw_per_min=40.0,
    ramp_down_mw_per_min=40.0,
    min_up_time_hours=8,
    min_down_time_hours=6,
    fuel_cost_rsj_per_mwh=120.0,
    startup_cost_rs=20000.0,
    shutdown_cost_rs=10000.0,
    heat_rate_gas_only=9.5,
    heat_rate_combined=6.5
)
```
"""
Base.@kwdef struct CombinedCyclePlant <: ThermalPlant
    id::String
    name::String
    bus_id::String
    submarket_id::String
    fuel_type::FuelType
    capacity_mw::Float64
    gas_turbine_capacity_mw::Float64
    steam_turbine_capacity_mw::Float64
    min_generation_gas_only_mw::Float64
    min_generation_combined_mw::Float64
    max_generation_combined_mw::Float64
    ramp_up_mw_per_min::Float64
    ramp_down_mw_per_min::Float64
    min_up_time_hours::Int
    min_down_time_hours::Int
    fuel_cost_rsj_per_mwh::Float64
    startup_cost_rs::Float64
    shutdown_cost_rs::Float64
    heat_rate_gas_only::Float64
    heat_rate_combined::Float64
    must_run::Bool = false
    metadata::EntityMetadata = EntityMetadata()

    function CombinedCyclePlant(;
            id::String,
            name::String,
            bus_id::String,
            submarket_id::String,
            fuel_type::FuelType,
            capacity_mw::Float64,
            gas_turbine_capacity_mw::Float64,
            steam_turbine_capacity_mw::Float64,
            min_generation_gas_only_mw::Float64,
            min_generation_combined_mw::Float64,
            max_generation_combined_mw::Float64,
            ramp_up_mw_per_min::Float64,
            ramp_down_mw_per_min::Float64,
            min_up_time_hours::Int,
            min_down_time_hours::Int,
            fuel_cost_rsj_per_mwh::Float64,
            startup_cost_rs::Float64,
            shutdown_cost_rs::Float64,
            heat_rate_gas_only::Float64,
            heat_rate_combined::Float64,
            must_run::Bool = false,
            metadata::EntityMetadata = EntityMetadata()
        )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length=2, max_length=4)

        # Validate capacities
        capacity_mw = validate_strictly_positive(capacity_mw, "capacity_mw")
        gas_turbine_capacity_mw = validate_positive(gas_turbine_capacity_mw, "gas_turbine_capacity_mw")
        steam_turbine_capacity_mw = validate_positive(steam_turbine_capacity_mw, "steam_turbine_capacity_mw")

        # Check that gas + steam capacity equals total capacity (within tolerance)
        total_gt_st = gas_turbine_capacity_mw + steam_turbine_capacity_mw
        if abs(total_gt_st - capacity_mw) > 0.01  # 0.01 MW tolerance
            throw(ArgumentError("gas_turbine_capacity_mw + steam_turbine_capacity_mw ($total_gt_st) must equal capacity_mw ($capacity_mw)"))
        end

        # Validate generation limits
        min_generation_gas_only_mw = validate_non_negative(min_generation_gas_only_mw, "min_generation_gas_only_mw")
        validate_min_leq_max(min_generation_gas_only_mw, gas_turbine_capacity_mw,
                           "min_generation_gas_only_mw", "gas_turbine_capacity_mw")

        min_generation_combined_mw = validate_non_negative(min_generation_combined_mw, "min_generation_combined_mw")
        max_generation_combined_mw = validate_positive(max_generation_combined_mw, "max_generation_combined_mw")
        validate_min_leq_max(min_generation_combined_mw, max_generation_combined_mw,
                           "min_generation_combined_mw", "max_generation_combined_mw")
        validate_min_leq_max(max_generation_combined_mw, capacity_mw,
                           "max_generation_combined_mw", "capacity_mw")

        # Validate ramp rates
        ramp_up_mw_per_min = validate_non_negative(ramp_up_mw_per_min, "ramp_up_mw_per_min")
        ramp_down_mw_per_min = validate_non_negative(ramp_down_mw_per_min, "ramp_down_mw_per_min")

        # Validate time constraints
        if min_up_time_hours < 0
            throw(ArgumentError("min_up_time_hours must be non-negative"))
        end
        if min_down_time_hours < 0
            throw(ArgumentError("min_down_time_hours must be non-negative"))
        end

        # Validate costs and heat rates
        fuel_cost_rsj_per_mwh = validate_non_negative(fuel_cost_rsj_per_mwh, "fuel_cost_rsj_per_mwh")
        startup_cost_rs = validate_non_negative(startup_cost_rs, "startup_cost_rs")
        shutdown_cost_rs = validate_non_negative(shutdown_cost_rs, "shutdown_cost_rs")
        heat_rate_gas_only = validate_positive(heat_rate_gas_only, "heat_rate_gas_only")
        heat_rate_combined = validate_positive(heat_rate_combined, "heat_rate_combined")

        new(id, name, bus_id, submarket_id, fuel_type, capacity_mw,
            gas_turbine_capacity_mw, steam_turbine_capacity_mw,
            min_generation_gas_only_mw, min_generation_combined_mw, max_generation_combined_mw,
            ramp_up_mw_per_min, ramp_down_mw_per_min,
            min_up_time_hours, min_down_time_hours, fuel_cost_rsj_per_mwh,
            startup_cost_rs, shutdown_cost_rs, heat_rate_gas_only, heat_rate_combined,
            must_run, metadata)
    end
end

# Export thermal types and enum values
export ThermalPlant, ConventionalThermal, CombinedCyclePlant
export FuelType, NATURAL_GAS, COAL, FUEL_OIL, DIESEL, NUCLEAR, BIOMASS, BIOGAS, OTHER
