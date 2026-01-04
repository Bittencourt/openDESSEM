"""
    Integration

Integration module for connecting OpenDESSEM with external optimization packages.
Provides adapters for converting OpenDESSEM entities to other data formats.

# Submodules
- `PowerModelsAdapter`: Convert OpenDESSEM entities to PowerModels.jl format

# Exports
- `convert_to_powermodel`: Convert complete system to PowerModels data dict
- `convert_bus_to_powermodel`: Convert Bus entity
- `convert_line_to_powermodel`: Convert ACLine entity
- `convert_gen_to_powermodel`: Convert generator entity
- `convert_load_to_powermodel`: Convert Load entity
- `find_bus_index`: Find bus index by ID
- `validate_powermodel_conversion`: Validate PowerModels data structure

# Example
```julia
using OpenDESSEM
using OpenDESSEM.Integration
using PowerModels

# Create entities
buses = [Bus(...), Bus(...)]
lines = [ACLine(...), ACLine(...)]

# Convert to PowerModels format
pm_data = convert_to_powermodel(;
    buses=buses,
    lines=lines,
    base_mva=100.0
)

# Solve DC-OPF
result = solve_dc_opf(pm_data, HiGHS.Optimizer)
```
"""
module Integration

include("powermodels_adapter.jl")

end # module
