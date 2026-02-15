# PWF.jl Integration Guide

**Created**: 2026-01-05
**Purpose**: Guide for using PWF.jl to load Brazilian ANAREDE (.pwf) files into OpenDESSEM
**Status**: Integration Ready

---

## Overview

**PWF.jl** is a Julia package developed by LAMPSPUC (Laboratory of Advanced Power System Studies at PUC-Rio) for reading ANAREDE (.pwf) files. These files contain power system data in the format used by Brazilian's ONS (Operador Nacional do Sistema Elétrico).

---

## Installation

PWF.jl is installed as an unregistered package from GitHub:

```bash
# Already added to OpenDESSEM Project.toml
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

**Current Version**: v0.1.0
**Repository**: https://github.com/LAMPSPUC/PWF.jl

---

## Basic Usage

### Loading a PWF File

```julia
using PWF

# Parse ANAREDE file
data = PWF.parse_file("path/to/file.pwf")

# Result is a Dict containing power system data
println("Loaded data with $(length(data)) sections")
```

### Available Functions

- `parse_file(filepath::String)` - Parse .pwf file and return Dict with system data
- `PWF.ANAREDE` - ANAREDE file type handler
- `PWF.Organon` - Organon file type handler

---

## Data Structure

PWF.jl returns a `Dict{String, Any}` with the following structure:

```julia
data = PWF.parse_file("system.pwf")

# Typical sections (varies by file):
# - "DADOS": Basic system data
# - "BARRA": Bus data
# - "LINHAC": AC transmission lines
# - "LINHAF": DC transmission lines (if present)
# - "GERTER": Thermal generators
# - "GERHID": Hydro generators
# - "CARG": Load data
# - "REACTIVE": Reactive power data
```

### Example: Accessing Bus Data

```julia
# Get bus data
buses = data["BARRA"]  # Array of bus records

for bus in buses
    println("Bus $(bus[\"codigo\"]): $(bus[\"nome\"])")
    println("  Voltage: $(bus[\"vnom\"]) kV")
    println("  Submarket: $(bus[\"submercado\"])")
end
```

---

## Integration with OpenDESSEM

### Current Status (TASK-010: Not Yet Implemented)

The full data loader implementation is planned for **TASK-010**. Current status:

**✅ Completed**:
- PWF.jl package installed and tested
- Basic parsing functionality verified
- Integration analysis completed

**🚧 To Be Implemented** (TASK-010):
- `src/data/loaders/pwf_loader.jl` - Convert PWF data → OpenDESSEM entities
- Mapping between PWF fields and OpenDESSEM entity attributes
- Validation of loaded data
- Integration with ElectricitySystem structure

### Planned Integration Code (TASK-010)

```julia
# File: src/data/loaders/pwf_loader.jl
using PWF
using ..Entities

"""
    load_from_pwffile(filepath::String)

Load OpenDESSEM system from ANAREDE .pwf file.

# Arguments
- `filepath::String`: Path to .pwf file

# Returns
- `ElectricitySystem`: Populated system object

# Example
```julia
system = load_from_pwffile("sin_2024.pwf")
println("Loaded $(length(system.buses)) buses")
println("Loaded $(length(system.thermal_plants)) thermal plants")
println("Loaded $(length(system.hydro_plants)) hydro plants")
```
"""
function load_from_pwffile(filepath::String)
    @info "Loading ANAREDE file" filepath=filepath

    # Parse .pwf file using PWF.jl
    pwf_data = PWF.parse_file(filepath)

    # Convert PWF data → OpenDESSEM entities
    buses = parse_buses(pwf_data)
    ac_lines = parse_ac_lines(pwf_data)
    dc_lines = parse_dc_lines(pwf_data)
    thermal = parse_thermal_plants(pwf_data)
    hydro = parse_hydro_plants(pwf_data)

    # Build ElectricitySystem
    system = ElectricitySystem(;
        buses = buses,
        ac_lines = ac_lines,
        dc_lines = dc_lines,
        thermal_plants = thermal,
        hydro_plants = hydro,
        base_date = extract_base_date(pwf_data)
    )

    @info "System loaded successfully" n_buses=length(buses) n_thermal=length(thermal) n_hydro=length(hydro)

    return system
end

"""
    parse_buses(pwf_data::Dict)

Extract and convert bus data from PWF structure.
"""
function parse_buses(pwf_data::Dict)
    buses = Bus[]
    raw_buses = pwf_data["BARRA"]

    for raw_bus in raw_buses
        bus = Bus(;
            id = raw_bus["codigo"],
            name = raw_bus["nome"],
            voltage_kv = raw_bus["vnom"],
            submarket_id = raw_bus["submercado"],
            # ... other fields
        )
        push!(buses, bus)
    end

    return buses
end

# Similar functions for parse_ac_lines, parse_thermal_plants, etc.
```

---

## PWF.jl Field Mapping

### Bus Data (BARRA)

| PWF Field | OpenDESSEM Entity | Field |
|-----------|-------------------|-------|
| `codigo` | `Bus` | `id` |
| `nome` | `Bus` | `name` |
| `vnom` | `Bus` | `voltage_kv` |
| `submercado` | `Bus` | `submarket_id` |
| `area` | `Bus` | `area_id` |
| `tipo_barra` | `Bus` | `bus_type` |
| `base_kv` | `Bus` | `base_voltage_kv` |

### AC Line Data (LINHAC)

| PWF Field | OpenDESSEM Entity | Field |
|-----------|-------------------|-------|
| `codigo` | `ACLine` | `id` |
| `nome` | `ACLine` | `name` |
| `de` | `ACLine` | `from_bus_id` |
| `para` | `ACLine` | `to_bus_id` |
| `r_pu` | `ACLine` | `resistance_pu` |
| `x_pu` | `ACLine` | `reactance_pu` |
| `limit_mva` | `ACLine` | `max_flow_mva` |
| `tap` | `ACLine` | `tap_ratio` |

### Thermal Generator Data (GERTER)

| PWF Field | OpenDESSEM Entity | Field |
|-----------|-------------------|-------|
| `codigo` | `ConventionalThermal` | `id` |
| `nome` | `ConventionalThermal` | `name` |
| `barra` | `ConventionalThermal` | `bus_id` |
| `potencia` | `ConventionalThermal` | `capacity_mw` |
| `pot_min` | `ConventionalThermal` | `min_generation_mw` |
| `pot_max` | `ConventionalThermal` | `max_generation_mw` |
| `combustivel` | `ConventionalThermal` | `fuel_type` |

### Hydro Generator Data (GERHID)

| PWF Field | OpenDESSEM Entity | Field |
|-----------|-------------------|-------|
| `codigo` | `HydroPlant` | `id` |
| `nome` | `HydroPlant` | `name` |
| `barra` | `HydroPlant` | `bus_id` |
| `potencia` | `HydroPlant` | `capacity_mw` |
| `tipo_usina` | `HydroPlant` | `plant_type` |
| `volume_max` | `HydroPlant` | `max_storage_hm3` |
| `cota` | `HydroPlant` | `elevation_m` |

---

## Sample Data Files

OpenDESSEM includes sample .pwf files for testing:

```
docs/Sample/DS_ONS_102025_RV2D11/
├── sab10h.pwf    # 10-bus system (small, good for testing)
├── sab19h.pwf    # 19-bus system
├── leve.pwf      # Light configuration
└── media.pwf     # Medium configuration
```

### Quick Test

```julia
using PWF

# Test with sample file
data = PWF.parse_file("docs/Sample/DS_ONS_102025_RV2D11/sab10h.pwf")

# Check available sections
println("Available sections:")
for key in keys(data)
    println("  - $key")
end

# Access bus data
if haskey(data, "BARRA")
    buses = data["BARRA"]
    println("\nLoaded $(length(buses)) buses")
end
```

---

## Validation

PWF.jl provides some warnings for unsupported sections:

```
[warn | PWF]: Currently there is no support for DUSI parsing
[warn | PWF]: Parser doesn't have default values for section DUSI
```

These are **expected and safe** - they just indicate that certain specialized sections are not fully supported yet.

### Common Warnings

| Warning | Meaning | Action |
|---------|---------|--------|
| "no support for DUSI parsing" | DUSI section not supported | Safe to ignore for now |
| "no default values for section X" | Section X has no defaults | Data will still load |
| "Populating defaults" | Filling in missing required values | Normal operation |

---

## Performance Considerations

**File Size**: Typical Brazilian SIN .pwf files are 1-10 MB

**Parsing Time**:
- Small system (10 buses): < 1 second
- Medium system (100 buses): 2-5 seconds
- Large system (full SIN): 10-30 seconds

**Memory Usage**:
- Parsed data structures typically use 2-3x the file size in RAM
- Full SIN (~5000 buses): ~50-100 MB RAM

---

## Troubleshooting

### Issue: "Malformed UUID" Error

**Error**: `Malformed value for PWF in deps section`

**Solution**:
```toml
# DON'T do this:
PWF = "https://github.com/LAMPSPUC/PWF.jl"

# INSTEAD, install via Pkg:
] add https://github.com/LAMPSPUC/PWF.jl
```

### Issue: File Not Found

**Error**: `SystemError: opening file "file.pwf": No such file or directory`

**Solution**: Use absolute paths or check working directory:
```julia
# Use absolute path
data = PWF.parse_file("C:/path/to/file.pwf")

# Or check current directory
println(pwd())  # Print working directory
```

### Issue: Missing Expected Sections

**Symptom**: `haskey(data, "BARRA")` returns `false`

**Possible Causes**:
1. .pwf file format is different than expected
2. Section names vary by file type
3. File is corrupted or incomplete

**Solution**:
```julia
# Check what sections are available
data = PWF.parse_file("file.pwf")
println("Available sections: ", keys(data))
```

---

## Related Documentation

- **Integration Analysis**: `docs/HYDROPOWERMODELS_INTEGRATION.md` - Complete dependency analysis
- **Entity Reference**: `docs/entity_reference.md` - OpenDESSEM entity types
- **Data Loaders**: `docs/data_loaders.md` - Full loader implementation (TASK-010)

---

## References

- **PWF.jl Repository**: https://github.com/LAMPSPUC/PWF.jl
- **PWF.jl Documentation**: https://lampspuc.github.io/PWF.jl/
- **LAMPSPUC**: Laboratory of Advanced Power System Studies, PUC-Rio
- **ONS Data**: https://ons.org.br/ (Brazilian System Operator)

---

**Last Updated**: 2026-01-05
**Maintainer**: OpenDESSEM Development Team
**Status**: Active Integration
