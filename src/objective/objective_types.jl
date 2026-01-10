"""
    Objective Types for OpenDESSEM

Defines the base abstractions and types for the objective function builder system.
Provides a modular, extensible framework for building optimization objectives
that minimize production costs in the Brazilian hydrothermal system.

Note: JuMP, Dates, and entity types are imported in parent Objective.jl module.
All types (ElectricitySystem, ThermalPlant, etc.) are available in scope.
"""

"""
    AbstractObjective

Abstract base type for all objective function types in OpenDESSEM.

All concrete objective types must:
1. Inherit from `AbstractObjective`
2. Implement a `build!()` method that takes a `JuMP.Model` and adds the objective
3. Include an `ObjectiveMetadata` field for tracking
4. Follow the builder pattern for fluent API

# Example
```julia
struct MyCustomObjective <: AbstractObjective
    metadata::ObjectiveMetadata
    parameter1::Float64
    parameter2::Bool
end

function build!(model::Model, system::ElectricitySystem, objective::MyCustomObjective)
    # Build objective expression here
    @objective(model, Min, expression)
    return ObjectiveBuildResult(...)
end
```
"""
abstract type AbstractObjective end

"""
    ObjectiveMetadata

Metadata for objective function tracking and management.

# Fields
- `name::String`: Human-readable objective name
- `description::String`: Detailed description of what the objective minimizes/maximizes
- `objective_sense::MOI.OptimizationSense`: Minimization (MOI.MIN_SENSE) or Maximization (MOI.MAX_SENSE)
- `created_at::DateTime`: Timestamp when objective was created
- `tags::Vector{String}`: User-defined tags for grouping/filtering

# Example
```julia
metadata = ObjectiveMetadata(;
    name="Production Cost Minimization",
    description="Minimize total thermal fuel cost plus startup/shutdown costs",
    objective_sense=MOI.MIN_SENSE,
    tags=["thermal", "production-cost"]
)
```
"""
Base.@kwdef struct ObjectiveMetadata
    name::String
    description::String
    objective_sense::MathOptInterface.OptimizationSense = MathOptInterface.MIN_SENSE
    created_at::DateTime = Dates.now()
    tags::Vector{String} = String[]
end

"""
    ObjectiveBuildResult

Result object returned after building an objective function.

# Fields
- `objective_type::String`: Type name of objective built
- `build_time_seconds::Float64`: Time taken to build objective
- `success::Bool`: Whether objective building succeeded
- `message::String`: Status message or error description
- `cost_component_summary::Dict{String, Float64}`: Breakdown of cost components (if applicable)
- `warnings::Vector{String}`: Any warnings generated during build

# Example
```julia
result = ObjectiveBuildResult(;
    objective_type="ProductionCostObjective",
    build_time_seconds=0.015,
    success=true,
    message="Built production cost objective with 3 components",
    cost_component_summary=Dict(
        "thermal_fuel" => 150000.0,
        "thermal_startup" => 30000.0,
        "hydro_water_value" => 50000.0
    ),
    warnings=String[]
)
```
"""
Base.@kwdef struct ObjectiveBuildResult
    objective_type::String
    build_time_seconds::Float64 = 0.0
    success::Bool = true
    message::String = ""
    cost_component_summary::Dict{String,Float64} = Dict{String,Float64}()
    warnings::Vector{String} = String[]
end

"""
    build!(model::Model, system::ElectricitySystem, objective::AbstractObjective)

Build an objective function and add it to the optimization model.

This generic function dispatches to the appropriate `build!()` method
based on the concrete type of `objective`.

# Arguments
- `model::Model`: JuMP optimization model
- `system::ElectricitySystem`: Complete electricity system
- `objective::AbstractObjective`: Objective to build

# Returns
- `ObjectiveBuildResult`: Result object with build statistics

# Example
```julia
result = build!(model, system, production_cost_objective)
if result.success
    println("Objective built: ", result.cost_component_summary)
end
```
"""
function build! end

"""
    validate_objective_system(system::ElectricitySystem)::Bool

Validate that the system has all required entities for objective building.

# Arguments
- `system::ElectricitySystem`: System to validate

# Returns
- `Bool`: true if system is valid for objective building

# Checks
- ✓ At least one thermal plant or hydro plant exists
- ✓ Time periods are defined (implicitly via model variables)

# Example
```julia
if validate_objective_system(system)
    println("System is ready for objective building")
end
```
"""
function validate_objective_system(system::ElectricitySystem)::Bool
    # Check for at least one generation source
    if isempty(system.thermal_plants) &&
       isempty(system.hydro_plants) &&
       isempty(system.wind_farms) &&
       isempty(system.solar_farms)
        @warn "No generation sources defined in system"
        return false
    end

    # Additional checks can be added here

    return true
end

# Export public types and functions
export AbstractObjective,
    ObjectiveMetadata, ObjectiveBuildResult, build!, validate_objective_system
