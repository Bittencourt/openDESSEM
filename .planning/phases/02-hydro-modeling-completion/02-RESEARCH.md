# Phase 2: Hydro Modeling Completion - Research

**Researched:** 2026-02-15
**Domain:** Hydro cascade modeling, inflow data loading, DAG topology utilities
**Confidence:** HIGH

## Summary

Phase 2 requires implementing three interconnected components for realistic hydro modeling:

1. **Inflow data loading**: Parse `dadvaz.dat` (primary source) and `vazaolateral.csv` (lateral influence factors) from DESSEM files to replace hardcoded zero inflows
2. **Cascade topology utility**: Build a DAG from plant `downstream_plant_id` references, compute plant depths, detect cycles at ElectricitySystem construction
3. **Water travel time delays**: Uncomment and complete the cascade delay logic (lines 224-228 in `hydro_water_balance.jl`) with proper time indexing

The existing codebase already has the foundation: hydro entities have `downstream_plant_id` and `water_travel_time_hours` fields, the DESSEM2Julia package can parse inflow data, and the constraint builder has placeholder cascade code. This phase connects these pieces.

**Primary recommendation:** Use DFS-based cycle detection at ElectricitySystem construction, build reverse adjacency map (downstream → upstream plants) for constraint building, and load inflows from `dadvaz.dat` via existing DESSEM2Julia integration.

## Standard Stack

The established libraries/patterns for this domain:

### Core
| Library/Pattern | Version | Purpose | Why Standard |
|-----------------|---------|---------|--------------|
| DESSEM2Julia | External | Parse DESSEM files | Already integrated, provides `parse_dadvaz` |
| Julia DataStructures | stdlib | Dict, Set for topology | Native, performant |
| JuMP | Current | Constraint building | Existing pattern in codebase |

### Existing Patterns to Follow
| Pattern | Location | Purpose |
|---------|----------|---------|
| Entity validation | `src/entities/validation.jl` | Pattern for validation functions |
| Constraint builder | `src/constraints/hydro_water_balance.jl` | Pattern for building constraints |
| Unit conversion | Line 186: `M3S_TO_HM3_PER_HOUR = 0.0036` | Already defined |

### Data Sources
| File | Purpose | Fields |
|------|---------|--------|
| `dadvaz.dat` | Daily inflow forecasts (primary) | Plant number, day, inflow m³/s |
| `vazaolateral.csv` | Lateral influence factors | UsinaInfluenciada, CodigoPostoInfluenciador, Fator |
| `hidr.dat` | Plant cascade topology | jusante (downstream plant code), tempo de viagem |

## Architecture Patterns

### Recommended Project Structure
```
src/
├── utils/
│   └── cascade_topology.jl      # NEW: DAG utilities, cycle detection, depth computation
├── data/
│   └── loaders/
│       └── dessem_loader.jl     # EXTEND: Add parse_vazaolateral, inflow loading
├── constraints/
│   └── hydro_water_balance.jl   # MODIFY: Uncomment cascade, add inflow data
└── core/
    └── electricity_system.jl    # MODIFY: Add cascade validation in constructor
```

### Pattern 1: Cascade Topology Building

**What:** Build reverse adjacency map (downstream_id → [upstream_plants]) from hydro plant data

**When to use:** Before constraint building, at ElectricitySystem validation

**Example:**
```julia
# Source: Based on existing hydro.jl structure and CONTEXT.md decisions

"""
    CascadeTopology

Holds the computed cascade topology for the hydro system.
"""
struct CascadeTopology
    # downstream_plant_id => Vector of (upstream_plant_id, travel_time_hours)
    upstream_map::Dict{String,Vector{Tuple{String,Float64}}}
    # plant_id => depth from headwater (headwaters have depth 0)
    depths::Dict{String,Int}
    # All plant IDs in topological order (upstream first)
    topological_order::Vector{String}
end

"""
    build_cascade_topology(hydro_plants::Vector{<:HydroPlant}) -> CascadeTopology

Build cascade topology from hydro plant entities.
Throws ArgumentError if circular cascade detected.

# Example
```julia
topology = build_cascade_topology(system.hydro_plants)
# Access upstream plants for downstream plant H_002:
for (upstream_id, delay) in topology.upstream_map["H_002"]
    println("Upstream $upstream_id with delay $delay hours")
end
```
"""
function build_cascade_topology(hydro_plants::Vector{<:HydroPlant})
    # Build plant lookup
    plant_dict = Dict(p.id => p for p in hydro_plants)
    
    # Build upstream map: downstream_id => [(upstream_id, delay)]
    upstream_map = Dict{String,Vector{Tuple{String,Float64}}}()
    for p in hydro_plants
        upstream_map[p.id] = Tuple{String,Float64}[]
    end
    
    for p in hydro_plants
        if p.downstream_plant_id !== nothing
            # Validate downstream exists
            if !haskey(plant_dict, p.downstream_plant_id)
                @warn "Unknown downstream reference" plant=p.id downstream=p.downstream_plant_id
                continue  # Treat as terminal (CONTEXT.md decision)
            end
            push!(upstream_map[p.downstream_plant_id], (p.id, p.water_travel_time_hours))
        end
    end
    
    # Detect cycles via DFS
    visited = Set{String}()
    rec_stack = Set{String}()
    
    function dfs(plant_id::String, path::Vector{String})
        if plant_id in rec_stack
            # Found cycle - format error message per CONTEXT.md
            cycle_start = findfirst(==(plant_id), path)
            cycle_path = vcat(path[cycle_start:end], plant_id)
            throw(ArgumentError("Circular cascade detected: $(join(cycle_path, " → "))"))
        end
        if plant_id in visited
            return
        end
        
        push!(visited, plant_id)
        push!(rec_stack, plant_id)
        push!(path, plant_id)
        
        plant = plant_dict[plant_id]
        if plant.downstream_plant_id !== nothing && haskey(plant_dict, plant.downstream_plant_id)
            dfs(plant.downstream_plant_id, path)
        end
        
        pop!(rec_stack)
        pop!(path)
    end
    
    for p in hydro_plants
        if p.id ∉ visited
            dfs(p.id, String[])
        end
    end
    
    # Compute depths and topological order
    depths = Dict{String,Int}()
    topo_order = String[]
    
    # Headwaters: plants with no upstream
    headwaters = [p.id for p in hydro_plants if isempty(upstream_map[p.id])]
    for hw in headwaters
        depths[hw] = 0
    end
    
    # BFS for depths
    queue = collect(headwaters)
    while !isempty(queue)
        current = popfirst!(queue)
        push!(topo_order, current)
        
        plant = plant_dict[current]
        if plant.downstream_plant_id !== nothing && haskey(plant_dict, plant.downstream_plant_id)
            downstream = plant.downstream_plant_id
            new_depth = get(depths, downstream, 0)
            depths[downstream] = max(new_depth, depths[current] + 1)
            push!(queue, downstream)
        end
    end
    
    return CascadeTopology(upstream_map, depths, topo_order)
end
```

### Pattern 2: Inflow Data Loading

**What:** Parse `dadvaz.dat` to get plant inflows per time period

**When to use:** During `load_dessem_case()` or before constraint building

**Example:**
```julia
# Source: Based on dadvaz.dat format inspection and existing DessemLoader patterns

"""
    InflowData

Container for hydrological inflow time series.
"""
struct InflowData
    # plant_number => [inflow_m3s for each time period]
    inflows::Dict{Int,Vector{Float64}}
    num_periods::Int
    start_date::Date
end

"""
    load_inflow_data(path::String) -> InflowData

Load inflow forecasts from dadvaz.dat file.

# File Format (from sample inspection):
```
NUMERO DE USINAS
XXX
168
...
VAZOES DIARIAS PARA CADA USINA (m3/s)
NUM     NOME      itp   DI HI M DF HF M      VAZAO
XXX XXXXXXXXXXXX   X    XXxXXxXxXXxXXxX     XXXXXXXXX
  1 CAMARGOS       1    11      F                  37
  1 CAMARGOS       1    12      F                  42
...
```

Each line: plant_number, name, interval_type, day/hour info, inflow_m3s
"""
function load_inflow_data(path::String)
    # Use DESSEM2Julia.parse_dadvaz if available, or implement custom parser
    # Pattern follows existing DessemLoader.parse_dessem_case()
    ...
end
```

### Pattern 3: Cascade Delay in Water Balance

**What:** Add upstream outflow terms with travel time delays

**When to use:** In `build!()` for `HydroWaterBalanceConstraint`

**Example:**
```julia
# Source: Lines 224-228 of hydro_water_balance.jl, PITFALLS.md pattern

# Build cascade topology once
topology = build_cascade_topology(plants)

# In water balance constraint loop:
for plant in plants
    plant_idx = plant_indices[plant.id]
    
    # Get upstream plants for this plant
    upstream_plants = get(topology.upstream_map, plant.id, Tuple{String,Float64}[])
    
    for t in time_periods
        # Base water balance
        balance_expr = s[plant_idx, t-1] + inflow_hm3 - outflow_hm3
        
        # Add upstream outflows with delays
        for (upstream_id, delay_hours) in upstream_plants
            t_upstream = t - round(Int, delay_hours)
            
            # Only add if delayed time is within valid range (avoid negative indices)
            if t_upstream >= 1
                upstream_idx = plant_indices[upstream_id]
                upstream_outflow_hm3 = q[upstream_idx, t_upstream] * M3S_TO_HM3_PER_HOUR
                
                # Add spillage if included
                if constraint.include_spill && spill !== nothing
                    upstream_outflow_hm3 += spill[upstream_idx, t_upstream] * M3S_TO_HM3_PER_HOUR
                end
                
                balance_expr += upstream_outflow_hm3
            end
            # For t_upstream < 1: water from initial conditions or before horizon
            # This is implicitly handled by initial storage
        end
        
        @constraint(model, s[plant_idx, t] == balance_expr)
    end
end
```

### Anti-Patterns to Avoid

- **Delay applied to wrong plant**: Downstream plant uses its own `water_travel_time_hours` instead of upstream's (pitfall in PITFALLS.md line 447)
- **Negative time index**: `s[i, t-delay]` with `t=1, delay=2` without bounds check (pitfall in PITFALLS.md line 448)
- **Direct inflow from vazaolateral.csv**: That file contains influence factors, not inflow time series; use `dadvaz.dat` for inflows

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Parsing DESSEM inflow files | Custom parser | `DESSEM2Julia.parse_dadvaz` | Already imported, handles format |
| Cycle detection in graph | Custom algorithm | DFS with recursion stack | Standard, well-tested pattern |
| Unit conversion m³/s to hm³ | Custom calculation | `M3S_TO_HM3_PER_HOUR = 0.0036` | Already defined in codebase |
| Topological sort | Custom sort | BFS from headwaters | Guarantees upstream-first order |

**Key insight:** The DESSEM2Julia package already provides `parse_dadvaz` (imported but unused at line 63 of dessem_loader.jl). Use it instead of writing a new parser.

## Common Pitfalls

### Pitfall 1: Wrong Inflow Data Source
**What goes wrong:** Trying to load inflow time series from `vazaolateral.csv`
**Why it happens:** File name suggests "lateral flow" but it actually contains influence factors
**How to avoid:** Use `dadvaz.dat` for inflow time series; `vazaolateral.csv` contains only lateral influence multipliers
**Warning signs:** File has `HIDRELETRICA-VAZAO-JUSANTE-INFLUENCIA-POSTO` records, not time series

### Pitfall 2: Delay Direction Confusion
**What goes wrong:** Adding upstream outflow at time `t` instead of `t - delay`
**Why it happens:** Misunderstanding water physics - upstream release takes time to travel downstream
**How to avoid:** Always use `t_upstream = t - delay_hours` for the time index of upstream outflow
**Warning signs:** Downstream reservoir fills faster than physics allows

### Pitfall 3: Unknown Downstream References
**What goes wrong:** `downstream_plant_id` points to a plant not in the system
**Why it happens:** Partial system definitions, different subsystems in separate studies
**How to avoid:** Log warning and treat as terminal (per CONTEXT.md decision); do NOT throw error
**Warning signs:** Tests fail when loading partial DESSEM cases

### Pitfall 4: Integer vs Float Delay
**What goes wrong:** Using `water_travel_time_hours` directly as array index without rounding
**Why it happens:** Julia arrays require integer indices
**How to avoid:** `t_upstream = t - round(Int, delay_hours)`
**Warning signs:** Type errors or incorrect constraint indices

## Code Examples

Verified patterns from existing codebase:

### Unit Conversion (Already Defined)
```julia
# Source: src/constraints/hydro_water_balance.jl line 186
# Conversion factor: m³/s to hm³ per hour
# 1 m³/s × 3600 s = 3600 m³ = 0.0036 hm³
M3S_TO_HM3_PER_HOUR = 0.0036
```

### Hydro Entity Cascade Fields (Already Exist)
```julia
# Source: src/entities/hydro.jl lines 93-94, 115
struct ReservoirHydro <: HydroPlant
    ...
    downstream_plant_id::Union{String,Nothing}
    water_travel_time_hours::Union{Float64,Nothing}
    ...
    # Validation: both must be set or both must be nothing (lines 205-211)
end
```

### Downstream Plant ID from Binary HIDR (Already Implemented)
```julia
# Source: src/data/loaders/dessem_loader.jl lines 515-524
downstream_id = if hidr.jusante > 0
    "H_$(subsystem_code)_$(lpad(hidr.jusante, 3, '0'))"
else
    nothing
end
travel_time = if downstream_id !== nothing
    1.0  # Default 1 hour travel time if downstream plant exists
else
    nothing
end
```

### Inflow Data Format (From Sample File)
```
# Source: docs/Sample/DS_ONS_102025_RV2D11/dadvaz.dat
# Format: Plant_number, Name, interval_type, day_info, inflow_m3s
  1 CAMARGOS       1    11      F                  37
  1 CAMARGOS       1    12      F                  42
 33 SAO SIMAO      1    11      F                 174
156 TRES MARIAS    1    11      F                  54
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hardcoded `inflow = 0.0` | Load from dadvaz.dat | Phase 2 | Enables validation |
| Commented cascade logic | Topology-based cascade | Phase 2 | Realistic multi-reservoir |
| No cycle detection | DFS at construction | Phase 2 | Fail-fast on bad data |

**Deprecated/outdated:**
- `inflow = 0.0` in lines 204, 242, 257: Replace with loaded data
- Commented cascade at lines 224-228: Uncomment and complete with topology

## Open Questions

### Question 1: Travel Time Default Value
- **What we know:** Current loader sets default `water_travel_time_hours = 1.0` if downstream exists
- **What's unclear:** Does `hidr.dat` binary contain actual travel times?
- **Recommendation:** Check BinaryHidrRecord structure in DESSEM2Julia for `tempo_viagem` field; if not available, 1-hour default is reasonable

### Question 2: Inflow Data Resolution
- **What we know:** `dadvaz.dat` contains daily inflows; model uses hourly periods
- **What's unclear:** Should daily inflows be distributed evenly or use hourly profiles?
- **Recommendation:** For Phase 2, distribute evenly (daily_inflow / 24 per hour). Hourly profiles can be added later.

### Question 3: Multiple Upstream Merging
- **What we know:** CONTEXT.md says to track inflows by upstream ID separately
- **What's unclear:** Should we expose individual upstream contributions in results?
- **Recommendation:** Keep separate terms in constraint expression for debugging; aggregate in output if needed

## Sources

### Primary (HIGH confidence)
- `src/entities/hydro.jl` - Hydro entity structure with cascade fields (inspected)
- `src/constraints/hydro_water_balance.jl` - Existing constraint builder with TODO markers (inspected)
- `src/data/loaders/dessem_loader.jl` - DESSEM loading patterns and imports (inspected)
- `src/core/electricity_system.jl` - System construction and validation patterns (inspected)
- `.planning/phases/02-hydro-modeling-completion/02-CONTEXT.md` - Locked decisions (read)
- `docs/Sample/DS_ONS_102025_RV2D11/dadvaz.dat` - Inflow data format (inspected)
- `docs/Sample/DS_ONS_102025_RV2D11/vazaolateral.csv` - Lateral influence format (inspected)

### Secondary (MEDIUM confidence)
- `.planning/research/PITFALLS.md` - Documented patterns for cascade delays
- `.planning/research/CONCERNS.md` - Known gaps and fix approaches
- `test/unit/test_constraints.jl` - Test patterns for constraint building

### Tertiary (LOW confidence)
- Standard DFS cycle detection algorithm (textbook pattern, HIGH confidence for algorithm)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All patterns verified in existing codebase
- Architecture: HIGH - Existing code shows clear patterns to follow
- Pitfalls: HIGH - Documented in PITFALLS.md and verified in code
- Inflow data format: HIGH - Inspected sample files directly

**Research date:** 2026-02-15
**Valid until:** 30 days (stable codebase patterns)

---

## Implementation Checklist

For the planner, key files to modify/create:

### New Files
- [ ] `src/utils/cascade_topology.jl` - CascadeTopology struct and build_cascade_topology()

### Modified Files
- [ ] `src/core/electricity_system.jl` - Add cascade validation in constructor
- [ ] `src/data/loaders/dessem_loader.jl` - Add inflow loading from dadvaz.dat
- [ ] `src/constraints/hydro_water_balance.jl` - Uncomment and complete cascade logic (lines 224-228)

### Test Files
- [ ] `test/unit/test_cascade_topology.jl` - Cycle detection, depth computation, edge cases
- [ ] `test/integration/test_inflow_loading.jl` - Load from sample data

### Key Line References
- Hardcoded zero inflows: `src/constraints/hydro_water_balance.jl` lines 204, 242, 257
- Commented cascade: `src/constraints/hydro_water_balance.jl` lines 224-228
- Unit conversion: `src/constraints/hydro_water_balance.jl` line 186
- DESSEM2Julia imports: `src/data/loaders/dessem_loader.jl` line 63 (`parse_dadvaz`)
