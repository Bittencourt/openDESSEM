"""
    OpenDESSEM

Open-source implementation of DESSEM (Daily Short-Term Hydrothermal Scheduling Model)
in Julia using JuMP.

# Main Components
- Entities: Database-ready data structures for system components
- Constraints: Modular constraint building system
- Data Loaders: PostgreSQL and SQLite data loading
- Solvers: Optimization solver interfaces
- Analysis: Results extraction and visualization

# Quick Start
```julia
using OpenDESSEM

# Load system from database
system = load_system(...)

# Create model
model = DessemModel(system, time_periods=168)

# Add constraints
add_constraint!(model, EnergyBalanceConstraint(...))

# Solve
solution = optimize!(model, HiGHS.Optimizer)
```
"""

module OpenDESSEM

# Include submodules
include("entities/Entities.jl")
include("core/electricity_system.jl")
include("integration/Integration.jl")

# Export main functionality
using .Entities
export AbstractEntity, PhysicalEntity, EntityMetadata
export validate_id, validate_name, validate_positive, validate_non_negative
export get_id, has_id, update_metadata, add_tag, set_property, is_empty
export ThermalPlant, ConventionalThermal, CombinedCyclePlant
export HydroPlant, ReservoirHydro, RunOfRiverHydro, PumpedStorageHydro
export RenewablePlant, WindPlant, SolarPlant
export NetworkEntity, Bus, ACLine, DCLine, NetworkLoad, NetworkSubmarket
export MarketEntity, Submarket, Load
export FuelType, NATURAL_GAS, COAL, FUEL_OIL, DIESEL, NUCLEAR, BIOMASS, BIOGAS, OTHER
export RenewableType, ForecastType, WIND, SOLAR
export DETERMINISTIC, STOCHASTIC, SCENARIO_BASED
export TrackingSystem, FIXED, SINGLE_AXIS, DUAL_AXIS

# Export core system functionality
export ElectricitySystem
export get_thermal_plant, get_hydro_plant, get_bus, get_submarket
export count_generators, total_capacity, validate_system

# Export integration functionality
using .Integration
export convert_to_powermodel,
    convert_bus_to_powermodel,
    convert_line_to_powermodel,
    convert_gen_to_powermodel,
    convert_load_to_powermodel,
    find_bus_index,
    validate_powermodel_conversion

# More modules will be added as we implement them:
# include("core/Model.jl")
# include("constraints/Constraints.jl")
# include("data/Data.jl")

end # module
