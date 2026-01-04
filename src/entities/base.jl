"""
    Base entity types for OpenDESSEM.

Defines abstract entity types and metadata structures.
All entities in OpenDESSEM inherit from AbstractEntity.
"""

using Dates

# Validation functions are included directly in this module's scope

"""
    AbstractEntity

Abstract base type for all entities in OpenDESSEM.

All entity types (thermal plants, hydro plants, buses, etc.) should subtype this.
"""
abstract type AbstractEntity end

"""
    EntityMetadata

Metadata associated with entities in the system.

# Fields
- `created_at::DateTime`: Timestamp when entity was created
- `updated_at::DateTime`: Timestamp when entity was last updated
- `version::Int`: Entity version number
- `source::String`: Data source (e.g., "database", "file", "manual")
- `tags::Vector{String}`: Optional tags for categorization
- `properties::Dict{String, Any}`: Additional properties as key-value pairs

# Examples
```julia
metadata = EntityMetadata(
    created_at=now(),
    updated_at=now(),
    version=1,
    source="database",
    tags=["verified", "2024-data"],
    properties=Dict("original_id" => "T_OLD_001")
)
```
"""
Base.@kwdef struct EntityMetadata
    created_at::DateTime = Dates.now()
    updated_at::DateTime = Dates.now()
    version::Int = 1
    source::String = "unknown"
    tags::Vector{String} = String[]
    properties::Dict{String,Any} = Dict{String,Any}()
end

"""
    PhysicalEntity <: AbstractEntity

Abstract base type for physical infrastructure entities.

Physical entities represent real-world equipment and infrastructure:
- Power plants (thermal, hydro, wind, solar)
- Network elements (buses, lines)
- Storage devices

All physical entities have at minimum:
- Unique identifier
- Human-readable name
- Geographic location (bus_id or coordinates)
- Metadata
"""
abstract type PhysicalEntity <: AbstractEntity end

"""
    is_empty(entity::AbstractEntity)

Check if an entity is empty (placeholder).

# Returns
- `Bool`: true if entity is a placeholder/empty, false otherwise
"""
is_empty(entity::AbstractEntity) = false

"""
    get_id(entity::AbstractEntity)

Get the ID of an entity.

# Returns
- `String`: The entity's unique identifier
"""
get_id(entity::AbstractEntity) = entity.id

"""
    has_id(entity::AbstractEntity, id::String)

Check if entity has the specified ID.

# Arguments
- `entity::AbstractEntity`: The entity to check
- `id::String`: The ID to compare

# Returns
- `Bool`: true if entity.id == id
"""
function has_id(entity::AbstractEntity, id::String)
    return entity.id == id
end

"""
    update_metadata!(entity::AbstractEntity; updates::Dict{String, Any}=Dict{String, Any}())

Update metadata for an entity.

# Arguments
- `entity::AbstractEntity`: The entity to update
- `updates::Dict{String, Any}`: Key-value pairs to update in metadata

# Returns
- `EntityMetadata`: The updated metadata

# Note
This creates a new metadata object with the updated values.
For mutable entities, consider using a different approach.
"""
function update_metadata(
    entity::AbstractEntity;
    updates::Dict{String,Any} = Dict{String,Any}(),
)
    new_metadata = EntityMetadata(
        created_at = entity.metadata.created_at,
        updated_at = Dates.now(),
        version = entity.metadata.version + 1,
        source = entity.metadata.source,
        tags = copy(entity.metadata.tags),
        properties = merge(entity.metadata.properties, updates),
    )

    return new_metadata
end

"""
    add_tag!(entity::AbstractEntity, tag::String)

Add a tag to an entity's metadata.

# Arguments
- `entity::AbstractEntity`: The entity
- `tag::String`: Tag to add

# Returns
- `EntityMetadata`: Updated metadata with the new tag
"""
function add_tag(entity::AbstractEntity, tag::String)
    if tag in entity.metadata.tags
        return entity.metadata  # Tag already exists
    end

    new_tags = vcat(entity.metadata.tags, tag)
    new_metadata = EntityMetadata(
        created_at = entity.metadata.created_at,
        updated_at = Dates.now(),
        version = entity.metadata.version + 1,
        source = entity.metadata.source,
        tags = new_tags,
        properties = copy(entity.metadata.properties),
    )

    return new_metadata
end

"""
    set_property!(entity::AbstractEntity, key::String, value::Any)

Set a property in an entity's metadata.

# Arguments
- `entity::AbstractEntity`: The entity
- `key::String`: Property key
- `value::Any`: Property value

# Returns
- `EntityMetadata`: Updated metadata with the new property
"""
function set_property(entity::AbstractEntity, key::String, value::Any)
    new_properties = copy(entity.metadata.properties)
    new_properties[key] = value

    new_metadata = EntityMetadata(
        created_at = entity.metadata.created_at,
        updated_at = Dates.now(),
        version = entity.metadata.version + 1,
        source = entity.metadata.source,
        tags = copy(entity.metadata.tags),
        properties = new_properties,
    )

    return new_metadata
end

export AbstractEntity, PhysicalEntity, EntityMetadata
export getid, has_id, update_metadata, add_tag, set_property
