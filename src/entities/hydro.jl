"""
    Hydro power plant entities for OpenDESSEM.

Defines all hydro plant types including reservoir, run-of-river, and pumped storage plants.
"""

using Dates

"""
    HydroPlant <: PhysicalEntity

Abstract base type for all hydro power plants.

Hydro plants generate electricity from water:
- Reservoir plants with significant storage
- Run-of-river plants with minimal storage
- Pumped storage plants for energy storage
"""
abstract type HydroPlant <: PhysicalEntity end

"""
    ReservoirHydro <: HydroPlant

Hydroelectric plant with significant water storage reservoir.

# Fields
- `id::String`: Unique plant identifier
- `name::String`: Human-readable plant name
- `bus_id::String`: Bus ID where plant is connected
- `submarket_id::String`: Submarket identifier
- `max_volume_hm3::Float64`: Maximum reservoir volume (cubic hectometers - 1 hm3 = 1 million m3)
- `min_volume_hm3::Float64`: Minimum reservoir volume (dead storage)
- `initial_volume_hm3::Float64`: Initial reservoir volume at time 0
- `max_outflow_m3_per_s::Float64`: Maximum water outflow (m3/s)
- `min_outflow_m3_per_s::Float64`: Minimum outflow (environmental constraints)
- `max_generation_mw::Float64`: Maximum generation capacity (MW)
- `min_generation_mw::Float64`: Minimum generation (MW)
- `efficiency::Float64`: Generation efficiency (0-1)
- `water_value_rs_per_hm3::Float64`: Opportunity cost of water (R\$ per hm3)
- `must_run::Bool`: If true, plant must run when water is available
- `downstream_plant_id::Union{String, Nothing}`: ID of immediately downstream plant
- `water_travel_time_hours::Union{Float64, Nothing}`: Time for water to reach downstream plant
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Water balance: `v[t+1] = v[t] + inflow[t] - outflow[t] - spill[t]`
- Volume limits: `min_volume <= v[t] <= max_volume`
- Generation limits: `min_gen * u <= g <= max_gen * u`
- Outflow limits: `min_outflow <= q[t] <= max_outflow`
- Cascade delays: water from upstream arrives after travel time

# Examples
```julia
plant = ReservoirHydro(;
    id = "H_001",
    name = "Itaipu",
    bus_id = "B001",
    submarket_id = "SE",
    max_volume_hm3 = 29000.0,
    min_volume_hm3 = 5000.0,
    initial_volume_hm3 = 20000.0,
    max_outflow_m3_per_s = 15000.0,
    min_outflow_m3_per_s = 500.0,
    max_generation_mw = 14000.0,
    min_generation_mw = 0.0,
    efficiency = 0.92,
    water_value_rs_per_hm3 = 50.0,
    must_run = false,
    downstream_plant_id = "H_002",
    water_travel_time_hours = 2.0
)
```
"""
Base.@kwdef struct ReservoirHydro <: HydroPlant
    id::String
    name::String
    bus_id::String
    submarket_id::String
    max_volume_hm3::Float64
    min_volume_hm3::Float64
    initial_volume_hm3::Float64
    max_outflow_m3_per_s::Float64
    min_outflow_m3_per_s::Float64
    max_generation_mw::Float64
    min_generation_mw::Float64
    efficiency::Float64
    water_value_rs_per_hm3::Float64
    must_run::Bool = false
    downstream_plant_id::Union{String,Nothing} = nothing
    water_travel_time_hours::Union{Float64,Nothing} = nothing
    metadata::EntityMetadata = EntityMetadata()

    function ReservoirHydro(;
        id::String,
        name::String,
        bus_id::String,
        submarket_id::String,
        max_volume_hm3::Float64,
        min_volume_hm3::Float64,
        initial_volume_hm3::Float64,
        max_outflow_m3_per_s::Float64,
        min_outflow_m3_per_s::Float64,
        max_generation_mw::Float64,
        min_generation_mw::Float64,
        efficiency::Float64,
        water_value_rs_per_hm3::Float64,
        must_run::Bool = false,
        downstream_plant_id::Union{String,Nothing} = nothing,
        water_travel_time_hours::Union{Float64,Nothing} = nothing,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length = 2, max_length = 4)

        # Validate volumes
        max_volume_hm3 = validate_strictly_positive(max_volume_hm3, "max_volume_hm3")
        min_volume_hm3 = validate_non_negative(min_volume_hm3, "min_volume_hm3")
        validate_min_leq_max(
            min_volume_hm3,
            max_volume_hm3,
            "min_volume_hm3",
            "max_volume_hm3",
        )

        initial_volume_hm3 = validate_non_negative(initial_volume_hm3, "initial_volume_hm3")
        if initial_volume_hm3 > max_volume_hm3
            throw(
                ArgumentError(
                    "initial_volume_hm3 ($initial_volume_hm3) must be <= max_volume_hm3 ($max_volume_hm3)",
                ),
            )
        end
        if initial_volume_hm3 < min_volume_hm3
            throw(
                ArgumentError(
                    "initial_volume_hm3 ($initial_volume_hm3) must be >= min_volume_hm3 ($min_volume_hm3)",
                ),
            )
        end

        # Validate outflow
        max_outflow_m3_per_s =
            validate_strictly_positive(max_outflow_m3_per_s, "max_outflow_m3_per_s")
        min_outflow_m3_per_s =
            validate_non_negative(min_outflow_m3_per_s, "min_outflow_m3_per_s")
        validate_min_leq_max(
            min_outflow_m3_per_s,
            max_outflow_m3_per_s,
            "min_outflow",
            "max_outflow",
        )

        # Validate generation
        max_generation_mw =
            validate_strictly_positive(max_generation_mw, "max_generation_mw")
        min_generation_mw = validate_non_negative(min_generation_mw, "min_generation_mw")
        validate_min_leq_max(
            min_generation_mw,
            max_generation_mw,
            "min_generation",
            "max_generation",
        )

        # Validate efficiency (0-1)
        efficiency = validate_percentage(efficiency * 100, "efficiency") / 100

        # Validate water value
        water_value_rs_per_hm3 =
            validate_non_negative(water_value_rs_per_hm3, "water_value_rs_per_hm3")

        # Validate cascade relationships
        if downstream_plant_id !== nothing
            downstream_plant_id = validate_id(downstream_plant_id)
        end

        if water_travel_time_hours !== nothing
            water_travel_time_hours =
                validate_non_negative(water_travel_time_hours, "water_travel_time_hours")
        end

        # If one cascade field is set, both must be set
        if (downstream_plant_id === nothing) != (water_travel_time_hours === nothing)
            throw(
                ArgumentError(
                    "downstream_plant_id and water_travel_time_hours must both be set or both be nothing",
                ),
            )
        end

        new(
            id,
            name,
            bus_id,
            submarket_id,
            max_volume_hm3,
            min_volume_hm3,
            initial_volume_hm3,
            max_outflow_m3_per_s,
            min_outflow_m3_per_s,
            max_generation_mw,
            min_generation_mw,
            efficiency,
            water_value_rs_per_hm3,
            must_run,
            downstream_plant_id,
            water_travel_time_hours,
            metadata,
        )
    end
end

"""
    RunOfRiverHydro <: HydroPlant

Run-of-river hydroelectric plant with minimal storage.

These plants have little to no storage capacity and generation depends primarily on current water flow.

# Fields
- `id::String`: Unique plant identifier
- `name::String`: Human-readable plant name
- `bus_id::String`: Bus ID where plant is connected
- `submarket_id::String`: Submarket identifier
- `max_flow_m3_per_s::Float64`: Maximum usable water flow (m3/s)
- `min_flow_m3_per_s::Float64`: Minimum flow (environmental requirements)
- `max_generation_mw::Float64`: Maximum generation capacity (MW)
- `min_generation_mw::Float64`: Minimum generation (MW)
- `efficiency::Float64`: Generation efficiency (0-1)
- `must_run::Bool`: If true, plant must run when water is available
- `downstream_plant_id::Union{String, Nothing}`: ID of immediately downstream plant
- `water_travel_time_hours::Union{Float64, Nothing}`: Time for water to reach downstream plant
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Energy balance: `g = flow * head * efficiency * constant`
- Flow limits: `min_flow <= q[t] <= max_flow`
- Generation limits: `min_gen * u <= g <= max_gen * u`

# Examples
```julia
plant = RunOfRiverHydro(;
    id = "ROR_001",
    name = "Run of River Plant 1",
    bus_id = "B002",
    submarket_id = "S",
    max_flow_m3_per_s = 500.0,
    min_flow_m3_per_s = 50.0,
    max_generation_mw = 100.0,
    min_generation_mw = 0.0,
    efficiency = 0.88,
    must_run = true
)
```
"""
Base.@kwdef struct RunOfRiverHydro <: HydroPlant
    id::String
    name::String
    bus_id::String
    submarket_id::String
    max_flow_m3_per_s::Float64
    min_flow_m3_per_s::Float64
    max_generation_mw::Float64
    min_generation_mw::Float64
    efficiency::Float64
    must_run::Bool = false
    downstream_plant_id::Union{String,Nothing} = nothing
    water_travel_time_hours::Union{Float64,Nothing} = nothing
    metadata::EntityMetadata = EntityMetadata()

    function RunOfRiverHydro(;
        id::String,
        name::String,
        bus_id::String,
        submarket_id::String,
        max_flow_m3_per_s::Float64,
        min_flow_m3_per_s::Float64,
        max_generation_mw::Float64,
        min_generation_mw::Float64,
        efficiency::Float64,
        must_run::Bool = false,
        downstream_plant_id::Union{String,Nothing} = nothing,
        water_travel_time_hours::Union{Float64,Nothing} = nothing,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length = 2, max_length = 4)

        # Validate flow
        max_flow_m3_per_s =
            validate_strictly_positive(max_flow_m3_per_s, "max_flow_m3_per_s")
        min_flow_m3_per_s = validate_non_negative(min_flow_m3_per_s, "min_flow_m3_per_s")
        validate_min_leq_max(min_flow_m3_per_s, max_flow_m3_per_s, "min_flow", "max_flow")

        # Validate generation
        max_generation_mw =
            validate_strictly_positive(max_generation_mw, "max_generation_mw")
        min_generation_mw = validate_non_negative(min_generation_mw, "min_generation_mw")
        validate_min_leq_max(
            min_generation_mw,
            max_generation_mw,
            "min_generation",
            "max_generation",
        )

        # Validate efficiency (0-1)
        efficiency = validate_percentage(efficiency * 100, "efficiency") / 100

        # Validate cascade relationships
        if downstream_plant_id !== nothing
            downstream_plant_id = validate_id(downstream_plant_id)
        end

        if water_travel_time_hours !== nothing
            water_travel_time_hours =
                validate_non_negative(water_travel_time_hours, "water_travel_time_hours")
        end

        # If one cascade field is set, both must be set
        if (downstream_plant_id === nothing) != (water_travel_time_hours === nothing)
            throw(
                ArgumentError(
                    "downstream_plant_id and water_travel_time_hours must both be set or both be nothing",
                ),
            )
        end

        new(
            id,
            name,
            bus_id,
            submarket_id,
            max_flow_m3_per_s,
            min_flow_m3_per_s,
            max_generation_mw,
            min_generation_mw,
            efficiency,
            must_run,
            downstream_plant_id,
            water_travel_time_hours,
            metadata,
        )
    end
end

"""
    PumpedStorageHydro <: HydroPlant

Pumped storage hydroelectric plant for energy storage.

Can operate in generation mode (producing electricity) or pumping mode (consuming electricity to store water).

# Fields
- `id::String`: Unique plant identifier
- `name::String`: Human-readable plant name
- `bus_id::String`: Bus ID where plant is connected
- `submarket_id::String`: Submarket identifier
- `upper_max_volume_hm3::Float64`: Maximum upper reservoir volume
- `upper_min_volume_hm3::Float64`: Minimum upper reservoir volume
- `upper_initial_volume_hm3::Float64`: Initial upper reservoir volume
- `lower_max_volume_hm3::Float64`: Maximum lower reservoir volume
- `lower_min_volume_hm3::Float64`: Minimum lower reservoir volume
- `lower_initial_volume_hm3::Float64`: Initial lower reservoir volume
- `max_generation_mw::Float64`: Generation capacity (MW)
- `max_pumping_mw::Float64`: Pumping capacity (MW)
- `generation_efficiency::Float64`: Round-trip efficiency for generation (0-1)
- `pumping_efficiency::Float64`: Round-trip efficiency for pumping (0-1)
- `min_generation_mw::Float64`: Minimum generation (MW)
- `must_run::Bool`: If true, plant must run when经济效益 favorable
- `metadata::EntityMetadata`: Additional metadata

# Constraints Applied
- Cannot pump and generate simultaneously
- Water balance: upper_vol decreases during generation, increases during pumping
- Generation limits: `min_gen * u_gen <= g <= max_gen * u_gen`
- Pumping limits: `0 <= p <= max_pump * u_pump`
- Mutually exclusive: `u_gen + u_pump <= 1`

# Examples
```julia
plant = PumpedStorageHydro(;
    id = "PS_001",
    name = "Pumped Storage 1",
    bus_id = "B003",
    submarket_id = "SE",
    upper_max_volume_hm3 = 500.0,
    upper_min_volume_hm3 = 50.0,
    upper_initial_volume_hm3 = 300.0,
    lower_max_volume_hm3 = 1000.0,
    lower_min_volume_hm3 = 100.0,
    lower_initial_volume_hm3 = 800.0,
    max_generation_mw = 500.0,
    max_pumping_mw = 400.0,
    generation_efficiency = 0.85,
    pumping_efficiency = 0.87,
    min_generation_mw = 0.0
)
```
"""
Base.@kwdef struct PumpedStorageHydro <: HydroPlant
    id::String
    name::String
    bus_id::String
    submarket_id::String
    upper_max_volume_hm3::Float64
    upper_min_volume_hm3::Float64
    upper_initial_volume_hm3::Float64
    lower_max_volume_hm3::Float64
    lower_min_volume_hm3::Float64
    lower_initial_volume_hm3::Float64
    max_generation_mw::Float64
    max_pumping_mw::Float64
    generation_efficiency::Float64
    pumping_efficiency::Float64
    min_generation_mw::Float64
    must_run::Bool = false
    metadata::EntityMetadata = EntityMetadata()

    function PumpedStorageHydro(;
        id::String,
        name::String,
        bus_id::String,
        submarket_id::String,
        upper_max_volume_hm3::Float64,
        upper_min_volume_hm3::Float64,
        upper_initial_volume_hm3::Float64,
        lower_max_volume_hm3::Float64,
        lower_min_volume_hm3::Float64,
        lower_initial_volume_hm3::Float64,
        max_generation_mw::Float64,
        max_pumping_mw::Float64,
        generation_efficiency::Float64,
        pumping_efficiency::Float64,
        min_generation_mw::Float64,
        must_run::Bool = false,
        metadata::EntityMetadata = EntityMetadata(),
    )

        # Validate ID and name
        id = validate_id(id)
        name = validate_name(name)
        bus_id = validate_id(bus_id)
        submarket_id = validate_id(submarket_id; min_length = 2, max_length = 4)

        # Validate upper reservoir
        upper_max_volume_hm3 =
            validate_strictly_positive(upper_max_volume_hm3, "upper_max_volume_hm3")
        upper_min_volume_hm3 =
            validate_non_negative(upper_min_volume_hm3, "upper_min_volume_hm3")
        validate_min_leq_max(
            upper_min_volume_hm3,
            upper_max_volume_hm3,
            "upper_min_volume",
            "upper_max_volume",
        )

        upper_initial_volume_hm3 =
            validate_non_negative(upper_initial_volume_hm3, "upper_initial_volume_hm3")
        if upper_initial_volume_hm3 > upper_max_volume_hm3
            throw(ArgumentError("upper_initial_volume_hm3 must be <= upper_max_volume_hm3"))
        end
        if upper_initial_volume_hm3 < upper_min_volume_hm3
            throw(ArgumentError("upper_initial_volume_hm3 must be >= upper_min_volume_hm3"))
        end

        # Validate lower reservoir
        lower_max_volume_hm3 =
            validate_strictly_positive(lower_max_volume_hm3, "lower_max_volume_hm3")
        lower_min_volume_hm3 =
            validate_non_negative(lower_min_volume_hm3, "lower_min_volume_hm3")
        validate_min_leq_max(
            lower_min_volume_hm3,
            lower_max_volume_hm3,
            "lower_min_volume",
            "lower_max_volume",
        )

        lower_initial_volume_hm3 =
            validate_non_negative(lower_initial_volume_hm3, "lower_initial_volume_hm3")
        if lower_initial_volume_hm3 > lower_max_volume_hm3
            throw(ArgumentError("lower_initial_volume_hm3 must be <= lower_max_volume_hm3"))
        end
        if lower_initial_volume_hm3 < lower_min_volume_hm3
            throw(ArgumentError("lower_initial_volume_hm3 must be >= lower_min_volume_hm3"))
        end

        # Validate capacities
        max_generation_mw =
            validate_strictly_positive(max_generation_mw, "max_generation_mw")
        max_pumping_mw = validate_strictly_positive(max_pumping_mw, "max_pumping_mw")
        min_generation_mw = validate_non_negative(min_generation_mw, "min_generation_mw")
        validate_min_leq_max(
            min_generation_mw,
            max_generation_mw,
            "min_generation",
            "max_generation",
        )

        # Validate efficiencies (0-1)
        generation_efficiency =
            validate_percentage(generation_efficiency * 100, "generation_efficiency") / 100
        pumping_efficiency =
            validate_percentage(pumping_efficiency * 100, "pumping_efficiency") / 100

        new(
            id,
            name,
            bus_id,
            submarket_id,
            upper_max_volume_hm3,
            upper_min_volume_hm3,
            upper_initial_volume_hm3,
            lower_max_volume_hm3,
            lower_min_volume_hm3,
            lower_initial_volume_hm3,
            max_generation_mw,
            max_pumping_mw,
            generation_efficiency,
            pumping_efficiency,
            min_generation_mw,
            must_run,
            metadata,
        )
    end
end

# Export hydro types
export HydroPlant, ReservoirHydro, RunOfRiverHydro, PumpedStorageHydro
