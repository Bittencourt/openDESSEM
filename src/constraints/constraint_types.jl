"""
    Constraint Types for OpenDESSEM

Defines the base abstractions and types for the constraint builder system.
Provides a modular, extensible framework for building optimization constraints
that leverage PowerModels.jl for network constraints and custom ONS-specific
constraints for the Brazilian system.
"""

# Note: JuMP, Dates, and entity types are imported in parent Constraints.jl module
# All types (ElectricitySystem, ThermalPlant, etc.) are available in scope

"""
    AbstractConstraint

Abstract base type for all constraint types in OpenDESSEM.

All concrete constraint types must:
1. Inherit from `AbstractConstraint`
2. Implement a `build!()` method that takes a `JuMP.Model` and the constraint
3. Include a `ConstraintMetadata` field for tracking
4. Follow the builder pattern for fluent API

# Example
```julia
struct MyCustomConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    parameter1::Float64
    parameter2::Bool
end

function build!(model::Model, system::ElectricitySystem, constraint::MyCustomConstraint)
    # Build constraints here
    return nothing
end
```
"""
abstract type AbstractConstraint end

"""
    ConstraintMetadata

Metadata for constraint tracking and management.

# Fields
- `name::String`: Human-readable constraint name
- `description::String`: Detailed description of what the constraint does
- `priority::Int`: Priority level (higher = applied earlier, default 10)
- `enabled::Bool`: Whether constraint is active (default true)
- `created_at::DateTime`: Timestamp when constraint was created
- `tags::Vector{String}`: User-defined tags for grouping/filtering

# Example
```julia
metadata = ConstraintMetadata(;
    name="Thermal Unit Commitment",
    description="Standard UC constraints for thermal plants",
    priority=10,
    enabled=true,
    tags=["thermal", "unit-commitment", "operational"]
)
```
"""
Base.@kwdef mutable struct ConstraintMetadata
    name::String
    description::String
    priority::Int = 10
    enabled::Bool = true
    created_at::DateTime = now()
    tags::Vector{String} = String[]
end

"""
    ConstraintBuildResult

Result object returned after building constraints.

# Fields
- `constraint_type::String`: Type name of constraint built
- `num_constraints::Int`: Number of constraints added
- `num_variables::Int`: Number of auxiliary variables created (if any)
- `build_time_seconds::Float64`: Time taken to build constraints
- `success::Bool`: Whether constraint building succeeded
- `message::String`: Status message or error description
- `warnings::Vector{String}`: Any warnings generated during build

# Example
```julia
result = ConstraintBuildResult(;
    constraint_type="ThermalCommitmentConstraint",
    num_constraints=150,
    num_variables=0,
    build_time_seconds=0.023,
    success=true,
    message="Built 150 thermal UC constraints"
)
```
"""
Base.@kwdef struct ConstraintBuildResult
    constraint_type::String
    num_constraints::Int = 0
    num_variables::Int = 0
    build_time_seconds::Float64 = 0.0
    success::Bool = true
    message::String = ""
    warnings::Vector{String} = String[]
end

"""
    build!(model::Model, system::ElectricitySystem, constraint::AbstractConstraint)

Build a constraint and add it to the optimization model.

This generic function dispatches to the appropriate `build!()` method
based on the concrete type of `constraint`.

# Arguments
- `model::Model`: JuMP optimization model
- `system::ElectricitySystem`: Complete electricity system
- `constraint::AbstractConstraint`: Constraint to build

# Returns
- `ConstraintBuildResult`: Result object with build statistics

# Example
```julia
result = build!(model, system, thermal_constraint)
if result.success
    println("Built \$(result.num_constraints) constraints")
else
    println("Build failed: \$(result.message)")
end
```
"""
function build! end

"""
    is_enabled(constraint::AbstractConstraint)::Bool

Check if a constraint is enabled.

# Arguments
- `constraint::AbstractConstraint`: Constraint to check

# Returns
- `Bool`: true if constraint is enabled

# Example
```julia
if is_enabled(my_constraint)
    build!(model, system, my_constraint)
end
```
"""
function is_enabled(constraint::AbstractConstraint)::Bool
    return constraint.metadata.enabled
end

"""
    enable!(constraint::AbstractConstraint)

Enable a constraint.

# Arguments
- `constraint::AbstractConstraint`: Constraint to enable

# Example
```julia
enable!(my_constraint)
```
"""
function enable!(constraint::AbstractConstraint)
    constraint.metadata.enabled = true
    return nothing
end

"""
    disable!(constraint::AbstractConstraint)

Disable a constraint.

# Arguments
- `constraint::AbstractConstraint`: Constraint to disable

# Example
```julia
disable!(my_constraint)
```
"""
function disable!(constraint::AbstractConstraint)
    constraint.metadata.enabled = false
    return nothing
end

"""
    get_priority(constraint::AbstractConstraint)::Int

Get the priority of a constraint.

# Arguments
- `constraint::AbstractConstraint`: Constraint to query

# Returns
- `Int`: Priority value (higher = applied earlier)

# Example
```julia
priority = get_priority(constraint)
println("Constraint priority: \$priority")
```
"""
function get_priority(constraint::AbstractConstraint)::Int
    return constraint.metadata.priority
end

"""
    set_priority!(constraint::AbstractConstraint, priority::Int)

Set the priority of a constraint.

# Arguments
- `constraint::AbstractConstraint`: Constraint to modify
- `priority::Int`: New priority value

# Example
```julia
set_priority!(constraint, 20)  # Higher priority
```
"""
function set_priority!(constraint::AbstractConstraint, priority::Int)
    constraint.metadata.priority = priority
    return nothing
end

"""
    add_tag!(constraint::AbstractConstraint, tag::String)

Add a tag to a constraint's metadata.

# Arguments
- `constraint::AbstractConstraint`: Constraint to tag
- `tag::String`: Tag to add

# Example
```julia
add_tag!(constraint, "network")
add_tag!(constraint, "security")
```
"""
function add_tag!(constraint::AbstractConstraint, tag::String)
    if !(tag in constraint.metadata.tags)
        push!(constraint.metadata.tags, tag)
    end
    return nothing
end

"""
    has_tag(constraint::AbstractConstraint, tag::String)::Bool

Check if a constraint has a specific tag.

# Arguments
- `constraint::AbstractConstraint`: Constraint to check
- `tag::String`: Tag to search for

# Returns
- `Bool`: true if constraint has the tag

# Example
```julia
if has_tag(constraint, "network")
    println("This is a network constraint")
end
```
"""
function has_tag(constraint::AbstractConstraint, tag::String)::Bool
    return tag in constraint.metadata.tags
end

"""
    validate_constraint_system(system::ElectricitySystem)::Bool

Validate that the system has all required entities for constraint building.

# Arguments
- `system::ElectricitySystem`: System to validate

# Returns
- `Bool`: true if system is valid for constraint building

# Checks
- ✓ At least one submarket exists
- ✓ Time periods are defined
- ✓ All entity references are valid

# Example
```julia
if validate_constraint_system(system)
    println("System is ready for constraint building")
end
```
"""
function validate_constraint_system(system::ElectricitySystem)::Bool
    # Check for at least one submarket
    if isempty(system.submarkets)
        @warn "No submarkets defined in system"
        return false
    end

    # Check for at least one generator (thermal, hydro, or renewable)
    has_thermal = !isempty(system.thermal_plants)
    has_hydro = !isempty(system.hydro_plants)
    has_wind = !isempty(system.wind_farms)
    has_solar = !isempty(system.solar_farms)

    if !has_thermal && !has_hydro && !has_wind && !has_solar
        @warn "No generators defined in system"
        return false
    end

    return true
end

# Export public types and functions
export AbstractConstraint,
    ConstraintMetadata,
    ConstraintBuildResult,
    build!,
    is_enabled,
    enable!,
    disable!,
    get_priority,
    set_priority!,
    add_tag!,
    has_tag,
    validate_constraint_system
