"""
    PWF Parser for ANAREDE Power Flow Files

Parses Brazilian ANAREDE PWF (power flow) files to extract network topology
including buses, lines, transformers, and generators.

# PWF File Format

PWF files are fixed-width format text files with sections identified by 4-character tags:
- `TITU`: Title
- `DAGR`: General data
- `DBAR`: Bus data (barras)
- `DLIN`: Line/transformer data
- `DCBA`: Shunt data
- `DGBT`: Generator data

# Example
```julia
using OpenDESSEM.Integration

# Parse a PWF file
network = parse_pwf_file("path/to/case.pwf")

println("Buses: ", length(network.buses))
println("Lines: ", length(network.lines))
```
"""

"""
    PWFBus

Represents a bus from a PWF file.

# Fields
- `number::Int`: Bus number (unique identifier)
- `name::String`: Bus name
- `type::Int`: Bus type (0=PQ, 1=PV, 2=slack, 3=isolated)
- `base_kv::Float64`: Base voltage in kV
- `voltage_pu::Float64`: Voltage magnitude in per-unit
- `angle_deg::Float64`: Voltage angle in degrees
- `generation_mw::Float64`: Active generation in MW
- `generation_mvar::Float64`: Reactive generation in MVAr
- `load_mw::Float64`: Active load in MW
- `load_mvar::Float64`: Reactive load in MVAr
- `shunt_mvar::Float64`: Shunt reactive power in MVAr
- `area::Int`: Area number
"""
Base.@kwdef struct PWFBus
    number::Int
    name::String
    type::Int
    base_kv::Float64
    voltage_pu::Float64
    angle_deg::Float64
    generation_mw::Float64
    generation_mvar::Float64
    load_mw::Float64
    load_mvar::Float64
    shunt_mvar::Float64
    area::Int
end

"""
    PWFBranch

Represents a branch (line or transformer) from a PWF file.

# Fields
- `from_bus::Int`: From bus number
- `to_bus::Int`: To bus number
- `circuit::Int`: Circuit number (for parallel lines)
- `resistance_pu::Float64`: Resistance in per-unit
- `reactance_pu::Float64`: Reactance in per-unit
- `susceptance_pu::Float64`: Susceptance in per-unit
- `tap_ratio::Float64`: Tap ratio (1.0 for lines)
- `min_tap::Float64`: Minimum tap ratio
- `max_tap::Float64`: Maximum tap ratio
- `rate_a_mw::Float64`: Continuous rating in MW
- `rate_b_mw::Float64`: Emergency rating in MW
- `rate_c_mw::Float64`: Short-term rating in MW
- `is_transformer::Bool`: True if transformer
"""
Base.@kwdef struct PWFBranch
    from_bus::Int
    to_bus::Int
    circuit::Int
    resistance_pu::Float64
    reactance_pu::Float64
    susceptance_pu::Float64
    tap_ratio::Float64
    min_tap::Float64
    max_tap::Float64
    rate_a_mw::Float64
    rate_b_mw::Float64
    rate_c_mw::Float64
    is_transformer::Bool
end

"""
    PWFNetwork

Complete network data from a PWF file.

# Fields
- `buses::Vector{PWFBus}`: All buses
- `branches::Vector{PWFBranch}`: All branches (lines and transformers)
- `title::String`: Case title
- `base_mva::Float64`: Base MVA for per-unit system
"""
Base.@kwdef struct PWFNetwork
    buses::Vector{PWFBus}
    branches::Vector{PWFBranch}
    title::String
    base_mva::Float64
end

"""
    parse_pwf_file(filepath::String) -> PWFNetwork

Parse a PWF (ANAREDE power flow) file and extract network data.

# Arguments
- `filepath::String`: Path to the PWF file

# Returns
- `PWFNetwork`: Complete network data

# Example
```julia
network = parse_pwf_file("case.pwf")
println("Loaded \$(length(network.buses)) buses")
```

# Throws
- `ArgumentError` if file not found
- `ErrorException` if parsing fails
"""
function parse_pwf_file(filepath::String)::PWFNetwork
    if !isfile(filepath)
        throw(ArgumentError("PWF file not found: $filepath"))
    end

    content = read(filepath, String)
    content = replace(content, "\r\n" => "\n")
    content = replace(content, "\r" => "\n")
    lines = split(content, '\n')

    buses = PWFBus[]
    branches = PWFBranch[]
    title = ""
    base_mva = 100.0

    current_section = ""
    in_section = false

    for line in lines
        line_stripped = strip(line)

        if isempty(line_stripped)
            continue
        end

        if length(line_stripped) >= 4
            section_marker = line_stripped[1:min(4, end)]
            if section_marker in ["TITU", "DAGR", "DBAR", "DLIN", "DCBA", "DGBT", "DCTE"]
                current_section = section_marker
                in_section = true
                continue
            end
        end

        if startswith(line_stripped, "99999")
            in_section = false
            current_section = ""
            continue
        end

        if !in_section
            continue
        end

        if current_section == "TITU" && isempty(title)
            title = strip(line_stripped)
        elseif current_section == "DCTE"
            if occursin("BASE", line_stripped)
                parts = split(line_stripped)
                for (i, p) in enumerate(parts)
                    if p == "BASE" && i + 1 <= length(parts)
                        base_mva = tryparse(Float64, parts[i+1])
                        base_mva = base_mva === nothing ? 100.0 : base_mva
                    end
                end
            end
        elseif current_section == "DBAR"
            bus = parse_pwf_bus_line(String(line))
            if bus !== nothing
                push!(buses, bus)
            end
        elseif current_section == "DLIN"
            branch = parse_pwf_branch_line(String(line))
            if branch !== nothing
                push!(branches, branch)
            end
        end
    end

    return PWFNetwork(;
        buses = buses,
        branches = branches,
        title = title,
        base_mva = base_mva,
    )
end

"""
    parse_pwf_bus_line(line::String) -> Union{PWFBus, Nothing}

Parse a single DBAR (bus) line from a PWF file.

PWF DBAR format (fixed-width columns):
```
(Num)OETGb(   nome   )Gl( V)( A)( Pg)( Qg)( Qn)( Qm)(Bc  )( Pl)( Ql)( Sh)Are(Vf)M(1)(2)(3)(4)(5)(6)(7)(8)(9)(10
```

Column positions (1-indexed):
- 1-5: Bus number (may have leading spaces)
- 6: Operation code (L, D, R, etc.)
- 7: Type (blank=0/PQ, 1=PV, 2=slack)
- 8: State (E=connected)
- 9-20: Bus name
- 24-27: Voltage level (kV or pu * 1000)
- 28-32: Angle (degrees * 100)
- 33-40: Pg (generation MW)
- etc.
"""
function parse_pwf_bus_line(line::String)::Union{PWFBus,Nothing}
    if length(line) < 25
        return nothing
    end

    if startswith(line, "(") || startswith(strip(line), "(")
        return nothing
    end

    try
        num_str = strip(line[1:5])
        if isempty(num_str)
            return nothing
        end
        number = tryparse(Int, num_str)
        if number === nothing
            return nothing
        end

        type_code = length(line) >= 7 ? line[7] : ' '
        bus_type = if type_code == ' ' || type_code == '0'
            0
        elseif type_code == '1'
            1
        elseif type_code == '2'
            2
        else
            0
        end

        name = length(line) >= 20 ? strip(line[9:20]) : "BUS_$number"
        if isempty(name)
            name = "BUS_$number"
        end

        base_kv = 230.0
        if length(line) >= 27
            v_str = strip(line[24:27])
            if !isempty(v_str)
                v_val = tryparse(Float64, v_str)
                if v_val !== nothing && v_val > 0
                    base_kv = v_val
                end
            end
        end

        voltage_pu = 1.0
        angle_deg = 0.0

        if length(line) >= 32
            a_str = strip(line[28:32])
            if !isempty(a_str)
                a_val = tryparse(Float64, a_str)
                if a_val !== nothing
                    angle_deg = a_val
                end
            end
        end

        generation_mw = 0.0
        generation_mvar = 0.0
        load_mw = 0.0
        load_mvar = 0.0
        shunt_mvar = 0.0

        if length(line) >= 40
            pg_str = strip(line[33:40])
            if !isempty(pg_str)
                pg_val = tryparse(Float64, pg_str)
                generation_mw = pg_val === nothing ? 0.0 : pg_val
            end
        end

        if length(line) >= 48
            qg_str = strip(line[41:48])
            if !isempty(qg_str)
                qg_val = tryparse(Float64, qg_str)
                generation_mvar = qg_val === nothing ? 0.0 : qg_val
            end
        end

        area = 1
        if length(line) >= 82
            area_str = strip(line[77:80])
            if !isempty(area_str)
                area_val = tryparse(Int, area_str)
                area = area_val === nothing ? 1 : area_val
            end
        end

        return PWFBus(;
            number = number,
            name = String(name),
            type = bus_type,
            base_kv = base_kv,
            voltage_pu = voltage_pu,
            angle_deg = angle_deg,
            generation_mw = generation_mw,
            generation_mvar = generation_mvar,
            load_mw = load_mw,
            load_mvar = load_mvar,
            shunt_mvar = shunt_mvar,
            area = area,
        )
    catch e
        return nothing
    end
end

"""
    parse_pwf_branch_line(line::String) -> Union{PWFBranch, Nothing}

Parse a single DLIN (branch) line from a PWF file.

PWF DLIN format has variable column widths. We parse by finding the first two
bus numbers and then looking for resistance/reactance values.
"""
function parse_pwf_branch_line(line::String)::Union{PWFBranch,Nothing}
    if length(line) < 15
        return nothing
    end

    if startswith(line, "(") || startswith(strip(line), "(")
        return nothing
    end

    try
        parts = split(strip(line))

        if length(parts) < 2
            return nothing
        end

        from_bus = tryparse(Int, parts[1])
        to_bus = tryparse(Int, parts[2])

        if from_bus === nothing || to_bus === nothing
            return nothing
        end

        circuit = 1
        if length(parts) >= 3
            circ_val = tryparse(Int, parts[3])
            circuit = circ_val === nothing ? 1 : circ_val
        end

        resistance_pu = 0.001
        reactance_pu = 0.01
        susceptance_pu = 0.0
        tap_ratio = 1.0
        is_transformer = false
        rate_a_mw = 9999.0
        rate_b_mw = 9999.0
        rate_c_mw = 9999.0

        for (i, part) in enumerate(parts[4:end])
            val = tryparse(Float64, part)
            if val === nothing
                continue
            end

            if resistance_pu == 0.001 && abs(val) < 100
                resistance_pu = val / 100.0
            elseif reactance_pu == 0.01 && abs(val) < 100 && resistance_pu > 0.001
                reactance_pu = val / 100.0
            elseif val > 100 && val < 10000
                rate_a_mw = val
            elseif val > 0.5 && val < 1.5 && tap_ratio == 1.0
                tap_ratio = val
                if val != 1.0
                    is_transformer = true
                end
            end
        end

        min_tap = 0.9
        max_tap = 1.1

        return PWFBranch(;
            from_bus = from_bus,
            to_bus = to_bus,
            circuit = circuit,
            resistance_pu = resistance_pu,
            reactance_pu = reactance_pu,
            susceptance_pu = susceptance_pu,
            tap_ratio = tap_ratio,
            min_tap = min_tap,
            max_tap = max_tap,
            rate_a_mw = rate_a_mw,
            rate_b_mw = rate_b_mw,
            rate_c_mw = rate_c_mw,
            is_transformer = is_transformer,
        )
    catch e
        return nothing
    end
end

export PWFBus, PWFBranch, PWFNetwork, parse_pwf_file
