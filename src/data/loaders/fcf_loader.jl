"""
    FCFCurveLoader - Future Cost Function Curve Loading

This module provides functions to load FCF (Future Cost Function) curves from
DESSEM infofcf.dat files and provide water value lookup functionality.

# FCF Curves in Hydrothermal Optimization
FCF curves represent the future cost of water usage (opportunity cost) derived
from long-term stochastic dual dynamic programming (SDDP) models. They are used
to value stored water at the end of the short-term optimization horizon.

The FCF is a piecewise linear convex function for each hydro plant, mapping
reservoir storage to marginal water value (R\$/hm³).

# Main Functions
- `load_fcf_curves(path)`: Load FCF curves from infofcf.dat file
- `get_water_value(fcf_data, plant_id, storage)`: Get interpolated water value
- `parse_infofcf_file(filepath)`: Parse infofcf.dat file directly

# Example
```julia
using OpenDESSEM

# Load FCF curves from a DESSEM case directory
fcf_data = load_fcf_curves("path/to/case/")

# Get water value for a specific plant at 500 hm³ storage
water_value = get_water_value(fcf_data, "H_SE_001", 500.0)
println("Water value: R\$", water_value, " per hm³")
```

# References
- DESSEM Manual: http://www.cepel.br
- SDDP Water Value Theory: Pereira, M.V.F., Pinto, L.M.V.G. (1991)
"""
module FCFCurveLoader

using Dates

export load_fcf_curves,
    parse_infofcf_file, get_water_value, interpolate_water_value, FCFCurve, FCFCurveData

#=============================================================================
# Data Structures
=============================================================================#

"""
    FCFCurve

Single hydro plant's Future Cost Function curve.

The FCF is represented as a piecewise linear convex function, with breakpoints
at specific storage levels and corresponding water values (marginal costs).

# Fields
- `plant_id::String`: Hydro plant identifier (e.g., "H_SE_001")
- `num_pieces::Int`: Number of piecewise linear segments
- `storage_breakpoints::Vector{Float64}`: Storage levels (hm³) at breakpoints
- `water_values::Vector{Float64}`: Water values (R\$/hm³) at each breakpoint

# Validation
- `num_pieces` must equal `length(storage_breakpoints)` and `length(water_values)`
- Storage breakpoints must be non-negative
- Water values must be non-negative

# Example
```julia
curve = FCFCurve(;
    plant_id = "H_SE_001",
    num_pieces = 5,
    storage_breakpoints = [0.0, 100.0, 500.0, 1000.0, 2000.0],
    water_values = [200.0, 150.0, 100.0, 50.0, 20.0]
)

# Get interpolated water value at 600 hm³ storage
value = interpolate_water_value(curve, 600.0)
```
"""
struct FCFCurve
    plant_id::String
    num_pieces::Int
    storage_breakpoints::Vector{Float64}
    water_values::Vector{Float64}

    function FCFCurve(;
        plant_id::String,
        num_pieces::Int,
        storage_breakpoints::Vector{Float64},
        water_values::Vector{Float64},
    )
        # Validate plant_id
        if isempty(strip(plant_id))
            throw(ArgumentError("plant_id cannot be empty"))
        end

        # Validate num_pieces matches array lengths
        if num_pieces != length(storage_breakpoints)
            throw(
                ArgumentError(
                    "num_pieces ($num_pieces) must equal length of storage_breakpoints ($(length(storage_breakpoints)))",
                ),
            )
        end

        if num_pieces != length(water_values)
            throw(
                ArgumentError(
                    "num_pieces ($num_pieces) must equal length of water_values ($(length(water_values)))",
                ),
            )
        end

        # Validate minimum pieces
        if num_pieces < 2
            throw(ArgumentError("FCF curve must have at least 2 breakpoints, got $num_pieces"))
        end

        # Validate storage values are non-negative
        if any(s -> s < 0, storage_breakpoints)
            throw(ArgumentError("Storage breakpoints must be non-negative"))
        end

        # Validate water values are non-negative
        if any(v -> v < 0, water_values)
            throw(ArgumentError("Water values must be non-negative"))
        end

        # Validate storage breakpoints are sorted (non-decreasing)
        if !issorted(storage_breakpoints)
            throw(ArgumentError("Storage breakpoints must be sorted in non-decreasing order"))
        end

        new(plant_id, num_pieces, storage_breakpoints, water_values)
    end
end

"""
    FCFCurveData

Container for all hydro plant FCF curves in the system.

Holds the complete FCF data loaded from an infofcf.dat file, including
metadata about the study period and the curve lookup dictionary.

# Fields
- `curves::Dict{String, FCFCurve}`: Mapping from plant_id to FCFCurve
- `study_date::Date`: Base date for the study period
- `num_periods::Int`: Number of time periods (typically 168 for weekly)
- `source_file::String`: Path to the source infofcf.dat file

# Example
```julia
# Load from file
fcf_data = load_fcf_curves("path/to/case/")

# Get water value for specific plant
water_value = get_water_value(fcf_data, "H_SE_001", 500.0)

# Check how many plants have FCF curves
println("Plants with FCF: \$(length(fcf_data.curves))")
```
"""
struct FCFCurveData
    curves::Dict{String,FCFCurve}
    study_date::Date
    num_periods::Int
    source_file::String

    function FCFCurveData(;
        curves::Dict{String,FCFCurve} = Dict{String,FCFCurve}(),
        study_date::Date = Date(2025, 1, 1),
        num_periods::Int = 168,
        source_file::String = "",
    )
        # Validate num_periods
        if num_periods < 1
            throw(ArgumentError("num_periods must be at least 1, got $num_periods"))
        end

        new(curves, study_date, num_periods, source_file)
    end
end

#=============================================================================
# Water Value Interpolation
=============================================================================#


"""
    interpolate_water_value(curve::FCFCurve, storage::Float64) -> Float64

Compute water value at given storage level using linear interpolation.

For storage values outside the breakpoint range, the function clamps to
the nearest endpoint (extrapolation is not performed).

# Arguments
- `curve::FCFCurve`: The FCF curve to interpolate
- `storage::Float64`: Storage level in hm³

# Returns
- `Float64`: Interpolated water value in R\$/hm³

# Example
```julia
curve = FCFCurve(;
    plant_id = "H_SE_001",
    num_pieces = 3,
    storage_breakpoints = [0.0, 100.0, 500.0],
    water_values = [200.0, 150.0, 100.0]
)

# Interpolate at 250 hm³ (midpoint)
value = interpolate_water_value(curve, 250.0)  # Returns 125.0

# Below minimum - clamp to first value
value = interpolate_water_value(curve, -10.0)  # Returns 200.0

# Above maximum - clamp to last value
value = interpolate_water_value(curve, 600.0)  # Returns 100.0
```
"""
function interpolate_water_value(curve::FCFCurve, storage::Float64)::Float64
    # Handle edge cases
    if curve.num_pieces == 0 || isempty(curve.storage_breakpoints)
        throw(ArgumentError("FCFCurve has no breakpoints"))
    end

    # Clamp storage to valid range
    min_storage = first(curve.storage_breakpoints)
    max_storage = last(curve.storage_breakpoints)

    clamped_storage = clamp(storage, min_storage, max_storage)

    # If at boundaries, return endpoint values
    if clamped_storage <= min_storage
        return first(curve.water_values)
    end

    if clamped_storage >= max_storage
        return last(curve.water_values)
    end

    # Find the segment containing this storage value
    for i in 1:(curve.num_pieces-1)
        s_low = curve.storage_breakpoints[i]
        s_high = curve.storage_breakpoints[i+1]

        if s_low <= clamped_storage <= s_high
            # Linear interpolation
            v_low = curve.water_values[i]
            v_high = curve.water_values[i+1]

            # Handle degenerate segment (zero width)
            if s_high == s_low
                return v_low
            end

            # Interpolation factor
            t = (clamped_storage - s_low) / (s_high - s_low)

            return v_low + t * (v_high - v_low)
        end
    end

    # Should not reach here if breakpoints are sorted and storage is in range
    return last(curve.water_values)
end

"""
    get_water_value(fcf_data::FCFCurveData, plant_id::String, storage::Float64) -> Float64

Get interpolated water value for a specific plant at given storage level.

This is the main lookup function for water values during optimization.

# Arguments
- `fcf_data::FCFCurveData`: Container with all FCF curves
- `plant_id::String`: Hydro plant identifier
- `storage::Float64`: Storage level in hm³

# Returns
- `Float64`: Interpolated water value in R\$/hm³

# Throws
- `ArgumentError`: If plant_id is not found in FCF data

# Example
```julia
fcf_data = load_fcf_curves("path/to/case/")

# Get water value for specific plant
water_value = get_water_value(fcf_data, "H_SE_001", 500.0)

# Use in optimization
objective += water_value * terminal_storage[i]
```
"""
function get_water_value(
    fcf_data::FCFCurveData,
    plant_id::String,
    storage::Float64,
)::Float64
    if !haskey(fcf_data.curves, plant_id)
        throw(ArgumentError("Plant '$plant_id' not found in FCF data"))
    end

    curve = fcf_data.curves[plant_id]
    return interpolate_water_value(curve, storage)
end

"""
    has_fcf_curve(fcf_data::FCFCurveData, plant_id::String) -> Bool

Check if a plant has an FCF curve defined.

# Arguments
- `fcf_data::FCFCurveData`: Container with all FCF curves
- `plant_id::String`: Hydro plant identifier

# Returns
- `Bool`: true if curve exists, false otherwise
"""
function has_fcf_curve(fcf_data::FCFCurveData, plant_id::String)::Bool
    return haskey(fcf_data.curves, plant_id)
end

"""
    get_plant_ids(fcf_data::FCFCurveData) -> Vector{String}

Get list of all plant IDs with FCF curves.

# Arguments
- `fcf_data::FCFCurveData`: Container with all FCF curves

# Returns
- `Vector{String}`: Sorted list of plant IDs
"""
function get_plant_ids(fcf_data::FCFCurveData)::Vector{String}
    return sort(collect(keys(fcf_data.curves)))
end

#=============================================================================
# File Parsing Functions
=============================================================================#


"""
    parse_infofcf_file(filepath::String) -> FCFCurveData

Parse an infofcf.dat file and return FCF curve data.

The infofcf.dat file contains FCF curves in DESSEM's fixed-format text format.
Each line typically contains:
- Plant number (posto)
- Number of pieces (segments)
- Pairs of (storage, water_value) values

# Arguments
- `filepath::String`: Path to infofcf.dat file

# Returns
- `FCFCurveData`: Container with all parsed FCF curves

# Throws
- `ArgumentError`: If file does not exist or is unreadable

# Example
```julia
fcf_data = parse_infofcf_file("path/to/infofcf.dat")
println("Loaded \$(length(fcf_data.curves)) FCF curves")
```
"""
function parse_infofcf_file(filepath::String)::FCFCurveData
    # Validate file exists
    if !isfile(filepath)
        throw(ArgumentError("FCF file not found: $filepath"))
    end

    @info "Parsing FCF file: $filepath"

    curves = Dict{String,FCFCurve}()
    study_date = Date(2025, 1, 1)  # Default study date
    num_periods = 168  # Default weekly horizon
    line_num = 0

    open(filepath, "r") do f
        for line in eachline(f)
            line_num += 1
            line = strip(line)

            # Skip empty lines and comments
            if isempty(line) || startswith(line, "&") || startswith(line, "#")
                continue
            end

            # Skip metadata record types (not FCF curve data)
            # - MAPFCF: mapping records (TVIAG, SISGNL, DURPAT)
            # - XXXXXX: template/header lines
            # - FCFFIX: fixed cost records for thermal plants
            if startswith(line, "MAPFCF") ||
               startswith(line, "XXXXXX") ||
               startswith(line, "FCFFIX")
                continue
            end

            # FCF curve data lines start with a number (plant number)
            # Skip lines that don't start with a digit
            if !isempty(line) && !isdigit(first(line))
                continue
            end

            # Try to parse as FCF record
            curve = parse_fcf_line(line, line_num)
            if curve !== nothing
                curves[curve.plant_id] = curve
            end
        end
    end

    if length(curves) == 0
        @info "Parsed $(length(curves)) FCF curves from $filepath (file contains metadata only, no FCF curve data)"
    else
        @info "Parsed $(length(curves)) FCF curves from $filepath"
    end

    return FCFCurveData(;
        curves = curves,
        study_date = study_date,
        num_periods = num_periods,
        source_file = filepath,
    )
end

"""
    parse_fcf_line(line::AbstractString, line_num::Int) -> Union{FCFCurve, Nothing}

Parse a single FCF record line from infofcf.dat.

Expected format (space or comma delimited):
```
<posto> <num_pieces> <s1> <v1> <s2> <v2> ... <sn> <vn>
```

Where:
- posto: Plant number (integer)
- num_pieces: Number of piecewise segments (integer)
- s1..sn: Storage breakpoints (hm³)
- v1..vn: Water values (R\$/hm³)

# Arguments
- `line::AbstractString`: Single line from infofcf.dat (accepts String or SubString)
- `line_num::Int`: Line number for error messages

# Returns
- `FCFCurve` if parsing successful
- `nothing` if line cannot be parsed (not an error, may be header/comment)
"""
function parse_fcf_line(line::AbstractString, line_num::Int)::Union{FCFCurve,Nothing}
    # Replace multiple spaces with single space for easier parsing
    normalized = strip(replace(line, r"\s+" => " "))

    # Split by space or comma
    parts = split(normalized, r"[,\s]+")

    # Need at least: posto, num_pieces, and 2 storage-value pairs (4 values)
    if length(parts) < 6
        return nothing  # Not enough data for a valid curve
    end

    try
        # Parse posto (plant number)
        posto = parse(Int, parts[1])

        # Parse num_pieces
        num_pieces = parse(Int, parts[2])

        # Validate num_pieces matches available data
        # Expected: posto, num_pieces, then 2*num_pieces values
        expected_parts = 2 + 2 * num_pieces
        if length(parts) < expected_parts
            @warn "Line $line_num: Expected $expected_parts values for $num_pieces pieces, got $(length(parts))"
            return nothing
        end

        # Parse storage-value pairs
        storage_breakpoints = Float64[]
        water_values = Float64[]

        for i in 1:num_pieces
            s_idx = 2 + 2 * (i - 1) + 1  # Storage index
            v_idx = s_idx + 1             # Value index

            s = parse(Float64, parts[s_idx])
            v = parse(Float64, parts[v_idx])

            push!(storage_breakpoints, s)
            push!(water_values, v)
        end

        # Generate plant ID (format: H_XX_NNN where XX is subsystem placeholder)
        # In actual DESSEM, posto maps to specific plants via hidr.dat
        plant_id = "H_XX_$(lpad(posto, 3, '0'))"

        # Create and validate curve
        return FCFCurve(;
            plant_id = plant_id,
            num_pieces = num_pieces,
            storage_breakpoints = storage_breakpoints,
            water_values = water_values,
        )

    catch e
        @warn "Line $line_num: Failed to parse FCF line: $e" line = line
        return nothing
    end
end

"""
    load_fcf_curves(path::String) -> FCFCurveData

Load FCF curves from a DESSEM case directory.

Searches for FCF data files in the following order:
1. infofcf.dat (standard DESSEM name)
2. INFOFCF.DAT (uppercase variant)
3. fcf.dat (alternative name)
4. FCF.DAT (uppercase variant)

# Arguments
- `path::String`: Path to DESSEM case directory

# Returns
- `FCFCurveData`: Container with all FCF curves

# Throws
- `ArgumentError`: If directory doesn't exist or no FCF file found

# Example
```julia
# Load from case directory
fcf_data = load_fcf_curves("docs/Sample/DS_ONS_102025_RV2D11/")

# Check curves loaded
println("Plants with FCF: \$(length(fcf_data.curves))")

# Get water value
if has_fcf_curve(fcf_data, "H_XX_001")
    value = get_water_value(fcf_data, "H_XX_001", 500.0)
    println("Water value at 500 hm³: R\$", value, "/hm³")
end
```
"""
function load_fcf_curves(path::String)::FCFCurveData
    # Validate path exists
    if !isdir(path)
        throw(ArgumentError("Directory not found: $path"))
    end

    # List of possible FCF file names to search
    fcf_filenames = ["infofcf.dat", "INFOFCF.DAT", "fcf.dat", "FCF.DAT"]

    fcf_filepath = nothing

    for filename in fcf_filenames
        candidate = joinpath(path, filename)
        if isfile(candidate)
            fcf_filepath = candidate
            break
        end
    end

    if fcf_filepath === nothing
        throw(
            ArgumentError(
                "No FCF file found in $path. Tried: $(join(fcf_filenames, ", "))",
            ),
        )
    end

    @info "Found FCF file: $fcf_filepath"

    return parse_infofcf_file(fcf_filepath)
end

"""
    load_fcf_curves_with_mapping(
        path::String,
        plant_id_map::Dict{Int,String}
    ) -> FCFCurveData

Load FCF curves with custom plant ID mapping.

Use this function when you have a mapping from DESSEM posto numbers
to OpenDESSEM plant IDs.

# Arguments
- `path::String`: Path to DESSEM case directory
- `plant_id_map::Dict{Int,String}`: Mapping from posto to plant_id

# Returns
- `FCFCurveData`: Container with FCF curves using mapped plant IDs

# Example
```julia
# Map posto numbers to OpenDESSEM plant IDs
plant_id_map = Dict(
    1 => "H_SE_001",
    2 => "H_SE_002",
    156 => "H_SU_156"
)

fcf_data = load_fcf_curves_with_mapping("path/to/case/", plant_id_map)
```
"""
function load_fcf_curves_with_mapping(
    path::String,
    plant_id_map::Dict{Int,String},
)::FCFCurveData
    # First load with default IDs
    raw_data = load_fcf_curves(path)

    # Remap plant IDs
    remapped_curves = Dict{String,FCFCurve}()

    for (raw_id, curve) in raw_data.curves
        # Extract posto from raw_id (format: H_XX_NNN)
        parts = split(raw_id, "_")
        if length(parts) >= 3
            posto_str = parts[3]
            posto = parse(Int, posto_str)

            if haskey(plant_id_map, posto)
                new_id = plant_id_map[posto]
                # Create new curve with mapped ID
                new_curve = FCFCurve(;
                    plant_id = new_id,
                    num_pieces = curve.num_pieces,
                    storage_breakpoints = curve.storage_breakpoints,
                    water_values = curve.water_values,
                )
                remapped_curves[new_id] = new_curve
            else
                # Keep original if no mapping
                remapped_curves[raw_id] = curve
            end
        else
            remapped_curves[raw_id] = curve
        end
    end

    return FCFCurveData(;
        curves = remapped_curves,
        study_date = raw_data.study_date,
        num_periods = raw_data.num_periods,
        source_file = raw_data.source_file,
    )
end

end # module FCFCurveLoader
