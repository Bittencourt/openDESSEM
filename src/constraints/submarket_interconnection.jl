"""
    Submarket Interconnection Constraints

Implements transfer limits between Brazilian submarkets via transmission lines.
"""

# Note: JuMP, Dates, and all entity/constraint types are imported in parent Constraints.jl module

"""
    SubmarketInterconnectionConstraint <: AbstractConstraint

Interconnection capacity limits between submarkets.

# Fields
- `metadata::ConstraintMetadata`: Constraint metadata
- `line_ids::Vector{String}`: Specific line IDs to constrain (empty = all)
- `use_time_periods::Union{Nothing, UnitRange{Int}, Vector{Int}}`: Time periods

# Constraints Added

For each interconnection line `l` and time period `t`:
```
-min_flow <= flow[l, t] <= max_flow
```

# Example
```julia
constraint = SubmarketInterconnectionConstraint(;
    metadata=ConstraintMetadata(;
        name="Interconnection Limits",
        description="Transfer limits between submarkets",
        priority=10
    )
)

result = build!(model, system, constraint)
```
"""
Base.@kwdef struct SubmarketInterconnectionConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    line_ids::Vector{String} = String[]
    use_time_periods::Union{Nothing,UnitRange{Int},Vector{Int}} = nothing
end

"""
    build!(model::Model, system::ElectricitySystem, constraint::SubmarketInterconnectionConstraint)
"""
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::SubmarketInterconnectionConstraint,
)
    start_time = time()
    num_constraints = 0

    if !validate_constraint_system(system)
        return ConstraintBuildResult(;
            constraint_type="SubmarketInterconnectionConstraint",
            success=false,
            message="System validation failed",
        )
    end

    lines = if isempty(constraint.line_ids)
        system.ac_lines
    else
        line_set = Set(constraint.line_ids)
        [l for l in system.ac_lines if l.id in line_set]
    end

    if isempty(lines)
        return ConstraintBuildResult(;
            constraint_type="SubmarketInterconnectionConstraint",
            success=true,
            num_constraints=0,
            message="No interconnection lines to constrain",
        )
    end

    time_periods =
        constraint.use_time_periods === nothing ? (1:24) : constraint.use_time_periods

    # Create flow variables if needed
    if !haskey(object_dictionary(model), :flow)
        n_lines = length(lines)
        n_periods = length(time_periods)
        @variable(model, flow[1:n_lines, 1:n_periods])
        @info "Created interconnection flow variables"
    end

    flow = model[:flow]

    for (idx, line) in enumerate(lines)
        for t in time_periods
            @constraint(model, -line.max_flow_mw <= flow[idx, t] <= line.max_flow_mw)
            num_constraints += 1
        end
    end

    build_time = time() - start_time

    return ConstraintBuildResult(;
        constraint_type="SubmarketInterconnectionConstraint",
        num_constraints=num_constraints,
        build_time_seconds=build_time,
        success=true,
        message="Built $num_constraints interconnection constraints",
    )
end

# Export
export SubmarketInterconnectionConstraint, build!
