"""
    OpenDESSEM Entities Module

Defines all entity types for the OpenDESSEM system.
Entities are database-ready data structures representing physical and logical components.

# Main Types
- `AbstractEntity`: Base type for all entities
- `PhysicalEntity`: Base type for physical infrastructure
- `EntityMetadata`: Metadata attached to entities
"""

module Entities

# Include validation first (used by other modules)
include("validation.jl")
include("base.jl")

# Export validation functions
export ValidationError
export validate_id, validate_name, validate_positive, validate_non_negative
export validate_strictly_positive, validate_percentage
export validate_in_range, validate_min_leq_max, validate_one_of, validate_unique_ids

# Export base types
export AbstractEntity, PhysicalEntity, EntityMetadata
export get_id, has_id, update_metadata, add_tag, set_property, is_empty

# Include entity types
include("thermal.jl")
include("hydro.jl")
include("renewable.jl")
include("network.jl")
include("market.jl")

end # module
