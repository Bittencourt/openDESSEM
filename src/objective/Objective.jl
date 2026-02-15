"""
    Objective Module

Provides objective function builders for OpenDESSEM optimization models.

# Components
- `AbstractObjective`: Base type for all objective functions
- `ObjectiveMetadata`: Metadata for tracking and management
- `ObjectiveBuildResult`: Result object from building objectives
- `ProductionCostObjective`: Production cost minimization objective

# Main Functions
- `build!(model, system, objective)`: Build and add objective to model
- `calculate_cost_breakdown(model, system, objective)`: Post-solution cost analysis

# Example
```julia
using OpenDESSEM.Objective

objective = ProductionCostObjective(;
    metadata=ObjectiveMetadata(;
        name="Production Cost",
        description="Minimize total system operating cost"
    ),
    thermal_fuel_cost=true,
    thermal_startup_cost=true,
    hydro_water_value=true
)

result = build!(model, system, objective)
```
"""

module Objective

using JuMP
using MathOptInterface
using Dates

# Import entity types from parent module (not Entities submodule)
using ..OpenDESSEM:
    ElectricitySystem,
    ThermalPlant,
    ConventionalThermal,
    CombinedCyclePlant,
    HydroPlant,
    ReservoirHydro,
    RunOfRiverHydro,
    PumpedStorageHydro,
    RenewablePlant,
    WindPlant,
    SolarPlant,
    Bus,
    Submarket,
    Load

# Import variable manager
using ..OpenDESSEM.Variables:
    get_thermal_plant_indices, get_hydro_plant_indices, get_renewable_plant_indices

# Include type definitions and implementations
include("objective_types.jl")
include("production_cost.jl")

# Export public types and functions
export
    # Abstract types
    AbstractObjective,

    # Metadata and result types
    ObjectiveMetadata,
    ObjectiveBuildResult,

    # Concrete objective types
    ProductionCostObjective,

    # Main functions
    build!,
    calculate_cost_breakdown,
    get_fuel_cost

end # module
