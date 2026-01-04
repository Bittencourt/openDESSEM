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

# Export main functionality
using .Entities
export AbstractEntity, PhysicalEntity, EntityMetadata
export validate_id, validate_name, validate_positive, validate_non_negative
export get_id, has_id, update_metadata, add_tag, set_property, is_empty
export ThermalPlant, ConventionalThermal, CombinedCyclePlant
export HydroPlant, ReservoirHydro, RunOfRiverHydro, PumpedStorageHydro
export RenewablePlant, WindFarm, SolarFarm
export NetworkEntity, Bus, ACLine, DCLine
export FuelType, NATURAL_GAS, COAL, FUEL_OIL, DIESEL, NUCLEAR, BIOMASS, BIOGAS, OTHER
export TrackingSystem, FIXED, SINGLE_AXIS, DUAL_AXIS

# More modules will be added as we implement them:
# include("core/Model.jl")
# include("constraints/Constraints.jl")
# include("data/Data.jl")

end # module
