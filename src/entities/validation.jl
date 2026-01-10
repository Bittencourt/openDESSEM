"""
    Validation utilities for OpenDESSEM entities.

Provides validation functions for entity fields to ensure data integrity.
All validation functions throw `ArgumentError` with descriptive messages.
"""

"""
    ValidationError <: Exception

Exception type for validation failures.

# Fields
- `msg::String`: Error message describing the validation failure
"""
struct ValidationError <: Exception
    msg::String
end

"""
    validate_id(id::String; min_length::Int=1, max_length::Int=50)

Validate entity ID.

# Arguments
- `id::String`: The ID to validate
- `min_length::Int=1`: Minimum allowed length
- `max_length::Int=50`: Maximum allowed length

# Returns
- `String`: The validated ID

# Throws
- `ArgumentError`: If ID is empty, too long, or contains invalid characters

# Examples
```julia
validate_id("T001")  # Returns "T001"
validate_id("A1_B2")  # Returns "A1_B2"
validate_id("")  # Throws ArgumentError
validate_id("A"^100)  # Throws ArgumentError (too long)
```
"""
function validate_id(id::String; min_length::Int = 1, max_length::Int = 50)
    if isempty(id)
        throw(ArgumentError("ID cannot be empty"))
    end

    if length(id) < min_length
        throw(ArgumentError("ID must be at least $min_length character(s)"))
    end

    if length(id) > max_length
        throw(ArgumentError("ID must be at most $max_length character(s)"))
    end

    # Check for valid characters (alphanumeric, underscore, hyphen)
    if !all(c -> isletter(c) || isdigit(c) || c == '_' || c == '-', id)
        throw(
            ArgumentError(
                "ID '$id' contains invalid characters (only alphanumeric, '_', and '-' allowed)",
            ),
        )
    end

    return id
end

"""
    validate_name(name::String; min_length::Int=1, max_length::Int=255)

Validate entity name.

# Arguments
- `name::String`: The name to validate
- `min_length::Int=1`: Minimum allowed length
- `max_length::Int=255`: Maximum allowed length

# Returns
- `String`: The validated name

# Throws
- `ArgumentError`: If name is empty or too long

# Examples
```julia
validate_name("Plant A")  # Returns "Plant A"
validate_name("")  # Throws ArgumentError
```
"""
function validate_name(name::String; min_length::Int = 1, max_length::Int = 255)
    stripped = strip(name)

    if isempty(stripped)
        throw(ArgumentError("Name cannot be empty or whitespace only"))
    end

    if length(stripped) < min_length
        throw(ArgumentError("Name must be at least $min_length character(s)"))
    end

    if length(stripped) > max_length
        throw(ArgumentError("Name must be at most $max_length character(s)"))
    end

    return stripped
end

"""
    validate_positive(value::Real, field_name::String="value")

Validate that a numeric value is positive (> 0).

# Arguments
- `value::Real`: The value to validate
- `field_name::String="value"`: Field name for error message

# Returns
- The validated value

# Throws
- `ArgumentError`: If value is not positive

# Examples
```julia
validate_positive(5.0)  # Returns 5.0
validate_positive(0.0)  # Throws ArgumentError
validate_positive(-1.0)  # Throws ArgumentError
```
"""
function validate_positive(value::Real, field_name::String = "value")
    if value < 0
        throw(ArgumentError("$field_name must be positive (got $value)"))
    end
    return value
end

"""
    validate_non_negative(value::Real, field_name::String="value")

Validate that a numeric value is non-negative (>= 0).

# Arguments
- `value::Real`: The value to validate
- `field_name::String="value"`: Field name for error message

# Returns
- The validated value

# Throws
- `ArgumentError`: If value is negative

# Examples
```julia
validate_non_negative(5.0)  # Returns 5.0
validate_non_negative(0.0)  # Returns 0.0
validate_non_negative(-1.0)  # Throws ArgumentError
```
"""
function validate_non_negative(value::Real, field_name::String = "value")
    if value < 0
        throw(ArgumentError("$field_name must be non-negative (got $value)"))
    end
    return value
end

"""
    validate_strictly_positive(value::Real, field_name::String="value")

Alias for `validate_positive`. Ensures value is > 0.

# Arguments
- `value::Real`: The value to validate
- `field_name::String="value"`: Field name for error message

# Returns
- The validated value

# Throws
- `ArgumentError`: If value is not strictly positive
"""
validate_strictly_positive(value::Real, field_name::String = "value") =
    validate_positive(value, field_name)

"""
    validate_percentage(value::Real, field_name::String="value")

Validate that a value is a valid percentage (0-100).

# Arguments
- `value::Real`: The value to validate
- `field_name::String="value"`: Field name for error message

# Returns
- The validated value

# Throws
- `ArgumentError`: If value is outside [0, 100]

# Examples
```julia
validate_percentage(50.0)  # Returns 50.0
validate_percentage(0.0)  # Returns 0.0
validate_percentage(100.0)  # Returns 100.0
validate_percentage(-1.0)  # Throws ArgumentError
validate_percentage(101.0)  # Throws ArgumentError
```
"""
function validate_percentage(value::Real, field_name::String = "value")
    if value < 0 || value > 100
        throw(ArgumentError("$field_name must be between 0 and 100 (got $value)"))
    end
    return value
end

"""
    validate_in_range(value::Real, min_val::Real, max_val::Real, field_name::String="value")

Validate that a value is within a specified range [min_val, max_val].

# Arguments
- `value::Real`: The value to validate
- `min_val::Real`: Minimum allowed value (inclusive)
- `max_val::Real`: Maximum allowed value (inclusive)
- `field_name::String="value"`: Field name for error message

# Returns
- The validated value

# Throws
- `ArgumentError`: If value is outside the specified range

# Examples
```julia
validate_in_range(5.0, 0.0, 10.0)  # Returns 5.0
validate_in_range(0.0, 0.0, 10.0)  # Returns 0.0
validate_in_range(10.0, 0.0, 10.0)  # Returns 10.0
validate_in_range(-1.0, 0.0, 10.0)  # Throws ArgumentError
validate_in_range(11.0, 0.0, 10.0)  # Throws ArgumentError
```
"""
function validate_in_range(
    value::Real,
    min_val::Real,
    max_val::Real,
    field_name::String = "value",
)
    # Auto-swap if bounds are reversed
    actual_min = min(min_val, max_val)
    actual_max = max(min_val, max_val)

    if value < actual_min || value > actual_max
        throw(
            ArgumentError(
                "$field_name must be between $actual_min and $actual_max (got $value)",
            ),
        )
    end
    return value
end

"""
    validate_min_leq_max(min_val::Real, max_val::Real, min_name::String="min", max_name::String="max")

Validate that min_val <= max_val.

# Arguments
- `min_val::Real`: Minimum value
- `max_val::Real`: Maximum value
- `min_name::String="min"`: Name for minimum field
- `max_name::String="max"`: Name for maximum field

# Throws
- `ArgumentError`: If min_val > max_val

# Examples
```julia
validate_min_leq_max(0.0, 10.0)  # OK
validate_min_leq_max(5.0, 5.0)  # OK
validate_min_leq_max(10.0, 5.0)  # Throws ArgumentError
```
"""
function validate_min_leq_max(
    min_val::Real,
    max_val::Real,
    min_name::String = "min",
    max_name::String = "max",
)
    if min_val > max_val
        throw(ArgumentError("$min_name ($min_val) must be <= $max_name ($max_val)"))
    end
    return nothing
end

"""
    validate_one_of(value, allowed_values::Vector, field_name::String="value")

Validate that a value is in a set of allowed values.

# Arguments
- `value`: The value to validate
- `allowed_values::Vector`: Set of allowed values
- `field_name::String="value"`: Field name for error message

# Returns
- The validated value

# Throws
- `ArgumentError`: If value is not in allowed_values

# Examples
```julia
validate_one_of("coal", ["coal", "gas", "nuclear"])  # Returns "coal"
validate_one_of("invalid", ["coal", "gas", "nuclear"])  # Throws ArgumentError
```
"""
function validate_one_of(value, allowed_values::Vector, field_name::String = "value")
    if !(value in allowed_values)
        throw(
            ArgumentError(
                "$field_name must be one of $(join(allowed_values, ", ")) (got $value)",
            ),
        )
    end
    return value
end

"""
    validate_unique_ids(items::Vector, item_type::String="items")

Validate that all items in a collection have unique IDs.

# Arguments
- `items::Vector`: Collection of items with `id` field
- `item_type::String="items"`: Type name for error message

# Throws
- `ValidationError`: If duplicate IDs are found

# Examples
```julia
struct TestItem
    id::String
end

items = [TestItem("A"), TestItem("B")]
validate_unique_ids(items)  # OK

items = [TestItem("A"), TestItem("A")]
validate_unique_ids(items)  # Throws ValidationError
```
"""
function validate_unique_ids(items::Vector, item_type::String = "items")
    ids = [item.id for item in items]

    if length(ids) != length(unique(ids))
        duplicates = ids[findall(x -> count(==(x), ids) > 1, unique(ids))]
        throw(
            ValidationError("Duplicate IDs found in $item_type: $(join(duplicates, ", "))"),
        )
    end

    return nothing
end
