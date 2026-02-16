"""
    Constraints Module for OpenDESSEM

Provides a modular, extensible constraint building system for power system optimization.
Leverages PowerModels.jl for network constraints and custom ONS-specific constraints
for the Brazilian system.

# Main Components

## Constraint Types
- `ThermalCommitmentConstraint`: Unit commitment for thermal plants
- `HydroWaterBalanceConstraint`: Water balance for hydro plants
- `HydroGenerationConstraint`: Generation function for hydro plants
- `SubmarketBalanceConstraint`: 4-submarket energy balance
- `SubmarketInterconnectionConstraint`: Interconnection limits
- `RenewableLimitConstraint`: Wind and solar capacity limits
- `NetworkPowerModelsConstraint`: PowerModels network integration

## Base Types
- `AbstractConstraint`: Base type for all constraints
- `ConstraintMetadata`: Constraint metadata and configuration
- `ConstraintBuildResult`: Result object from constraint building

# Example Usage

```julia
using OpenDESSEM
using OpenDESSEM.Constraints
using JuMP

# Load system
system = load_system(...)

# Create optimization model
model = Model(HiGHS.Optimizer)

# Create variables
create_all_variables!(model, system, 1:24)

# Build constraints
thermal_constraint = ThermalCommitmentConstraint(;
    metadata=ConstraintMetadata(;
        name="Thermal UC",
        description="Unit commitment constraints",
        priority=10
    )
)

result = build!(model, system, thermal_constraint)
println("Built \$(result.num_constraints) constraints")

# Build more constraints...
hydro_constraint = HydroWaterBalanceConstraint(;
    metadata=ConstraintMetadata(;
        name="Hydro Water Balance",
        description="Reservoir water balance",
        priority=10
    )
)

build!(model, system, hydro_constraint)

# Solve model
optimize!(model)
```

# Constraint Building Workflow

1. **Load System**: Load electricity system from database or file
2. **Create Model**: Create JuMP optimization model with solver
3. **Create Variables**: Use VariableManager to create decision variables
4. **Build Constraints**: Use `build!()` to add constraints
5. **Solve**: Optimize the model
6. **Extract Results**: Extract solution values

# Custom Constraints

To create a custom constraint:

```julia
using ..OpenDESSEM.Constraints

struct MyCustomConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    parameter1::Float64
end

function build!(model::Model, system::ElectricitySystem, constraint::MyCustomConstraint)
    # Build your constraints here
    num_constraints = 0

    for plant in system.thermal_plants
        @constraint(model, ...)
        num_constraints += 1
    end

    return ConstraintBuildResult(;
        constraint_type="MyCustomConstraint",
        num_constraints=num_constraints,
        success=true,
        message="Built \$num_constraints constraints"
    )
end
```

# Integration with PowerModels

Network constraints are handled via PowerModels.jl:

```julia
network_constraint = NetworkPowerModelsConstraint(;
    metadata=ConstraintMetadata(;
        name="DC-OPF Network",
        description="DC optimal power flow",
        priority=10
    ),
    formulation="dcopf",
    base_mva=100.0,
    solver=HiGHS.Optimizer
)

build!(model, system, network_constraint)
```

# See Also
- [VariableManager](@ref): Variable creation
- [PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl): Network optimization
"""

module Constraints

using JuMP
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
    ACLine,
    Submarket,
    Load

# Import integration layer
using ..OpenDESSEM.Integration: convert_to_powermodel, validate_powermodel_conversion

# Import variable manager
using ..OpenDESSEM.Variables:
    get_thermal_plant_indices,
    get_hydro_plant_indices,
    get_renewable_plant_indices

# Import cascade topology utilities
using ..OpenDESSEM.CascadeTopologyUtils: build_cascade_topology, CascadeTopology, get_upstream_plants

# Import inflow data types
using ..OpenDESSEM.DessemLoader: InflowData, get_inflow

# Include all constraint modules
include("constraint_types.jl")
include("thermal_commitment.jl")
include("hydro_water_balance.jl")
include("hydro_generation.jl")
include("submarket_balance.jl")
include("submarket_interconnection.jl")
include("renewable_limits.jl")
include("network_powermodels.jl")

# Re-export all public types and functions
export
    # Base types
    AbstractConstraint,
    ConstraintMetadata,
    ConstraintBuildResult,

    # Constraint types
    ThermalCommitmentConstraint,
    HydroWaterBalanceConstraint,
    HydroGenerationConstraint,
    SubmarketBalanceConstraint,
    SubmarketInterconnectionConstraint,
    RenewableLimitConstraint,
    NetworkPowerModelsConstraint,

    # Functions
    build!,
    is_enabled,
    enable!,
    disable!,
    get_priority,
    set_priority!,
    add_tag!,
    has_tag,
    validate_constraint_system

end # module
