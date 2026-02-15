# HydroPowerModels.jl Integration Analysis

**Created**: 2026-01-05
**Purpose**: Analyze HydroPowerModels.jl dependencies and integration strategy for OpenDESSEM
**Status**: Research Phase

---

## Executive Summary

**HydroPowerModels.jl** is a Julia/JuMP package for **hydrothermal multistage steady-state power network optimization** using **Stochastic Dual Dynamic Programming (SDDP)**.

**Key Finding**: HydroPowerModels.jl is **complementary** to OpenDESSEM, not competitive. It focuses on **long-term multistage planning** while OpenDESSEM focuses on **short-term daily dispatch**.

---

## HydroPowerModels.jl Dependency Analysis

### Direct Dependencies

```toml
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"    # CSV file I/O
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0" # Data manipulation
JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"     # JSON parsing
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"     # Optimization framework
PowerModels = "c36e90e8-916a-50a6-bd94-075b64ef4655" # Power network models
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"     # Random number generation
Reexport = "189a3867-3050-52da-a836-e630ba90ab69"  # Package re-exports
SDDP = "f4570300-c277-11e8-125c-4912f86ce65d"    # Stochastic Dual Dynamic Programming
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2" # Statistical functions
```

### Dependency Versions (as of v0.2.3)

- **JuMP**: 1.6 ✅ (OpenDESSEM uses 1.0 - compatible)
- **PowerModels**: 0.19
- **SDDP**: 1.1
- **DataFrames**: 1.0 ✅ (Already in OpenDESSEM)
- **CSV**: 0.10
- **JSON**: 0.21
- **Julia**: ~1 ✅ (OpenDESSEM uses 1.10)

---

## Component Comparison: What Exists vs What We're Building

### ✅ **ALREADY EXISTS in Dependencies**

#### 1. **PowerModels.jl** (Network Formulations)
**Provides**:
- Mathematical formulations for power flow (AC-OPF, DC-OPF)
- Bus/branch data structures
- Network constraint implementations
- Solver interfaces

**Overlap with OpenDESSEM**:
- ✅ We have entity types: `Bus`, `ACLine`, `DCLine` (TASK-003)
- ❌ We DON'T have constraint implementations yet (TASK-006)
- ❌ We DON'T have power flow solvers

**Integration Strategy**:
```julia
# OPTION A: Use PowerModels.jl network constraints (Recommended)
using PowerModels
# For DC-OPF constraints (simpler, faster)
pm_model = PM.DCPPowerModel
# For AC-OPF constraints (more accurate)
pm_model = PM.ACPPowerModel

# OPTION B: Implement our own (Current OpenDESSEM approach)
# Reuse PowerModels data structures, implement custom constraints
```

**Recommendation**:
- **Adopt PowerModels formulations** for TASK-006 (Constraint Builder)
- Don't reinvent network constraint math
- Keep OpenDESSEM entity system (better than PowerModels' dict-based approach)
- Create adapter layer to convert OpenDESSEM entities → PowerModels data

---

#### 2. **SDDP.jl** (Stochastic Optimization)
**Provides**:
- Stochastic Dual Dynamic Programming algorithm
- Multi-stage stochastic optimization
- Scenario tree management
- Cutting plane methods

**Overlap with OpenDESSEM**:
- ❌ OpenDESSEM is currently **deterministic** (single scenario)
- ❌ We don't have stochastic optimization yet
- ✅ Future work could leverage SDDP.jl

**Integration Strategy**:
```julia
# Future: Add stochastic module to OpenDESSEM
using SDDP

# Extend OpenDESSEM for stochastic hydrothermal planning
struct StochasticHydroModel
    # SDDP.jl handles:
    # - Multi-stage decision making (weekly/monthly planning)
    # - Inflow uncertainty scenarios
    # - Future cost-to-go functions
end
```

**Recommendation**:
- **NOT immediate priority** - OpenDESSEM Phase 1 is deterministic daily dispatch
- **Future enhancement** (Phase 2+) for stochastic planning
- Study SDDP.jl architecture when designing stochastic module

---

### ❌ **NOT IN OpenDESSEM (Complementary)**

#### 3. **HydroPowerModels.jl Core Functionality**

**What HydroPowerModels.jl Does**:
- **Long-term multistage planning** (months/years ahead)
- **Stochastic inflow modeling** (scenario trees)
- **Hydrothermal coordination** across multiple stages
- **Forward-backward decomposition** (Benders cuts)
- **Policy function approximation**

**What OpenDESSEM Does** (or will do):
- **Short-term daily dispatch** (24-168 hours)
- **Deterministic single-scenario** (initially)
- **Detailed unit commitment** (thermal on/off decisions)
- **Fine-grained temporal resolution** (hourly or sub-hourly)
- **ONS-specific Brazilian modeling** (exact DESSEM features)

**Key Difference**: Time Horizon and Uncertainty

| Aspect | HydroPowerModels.jl | OpenDESSEM |
|--------|---------------------|-------------|
| **Time Horizon** | Long-term (weeks/months) | Short-term (day/week) |
| **Resolution** | Coarse (weekly stages) | Fine (hourly periods) |
| **Uncertainty** | Stochastic (scenario trees) | Deterministic (initially) |
| **Problem Type** | Multistage planning | Single-period dispatch |
| **Hydro Modeling** | Aggregated reservoirs | Detailed plant-level |
| **Thermal Modeling** | Aggregate production | Detailed unit commitment |
| **Network** | Simplified (DC-OPF) | Detailed (DC-OPF + AC-OPF) |
| **Brazilian Features** | Generic | ONS-specific |

---

## Dependency Overlap Analysis

### ✅ **SAFE TO ADD** (No Duplication)

#### PWF.jl
- **Purpose**: Read ANAREDE (.pwf) files
- **Function**: File parsing only
- **Overlap**: None - OpenDESSEM has no file parsers yet
- **Action**: ✅ **ADD IMMEDIATELY**

#### CSV.jl, JSON.jl
- **Purpose**: Data I/O
- **Function**: File reading/writing
- **Overlap**: None - OpenDESSEM doesn't have these yet
- **Action**: Add when implementing data loaders (TASK-008/010)

#### Statistics.jl, Random.jl
- **Purpose**: Statistical operations
- **Function**: Math utilities
- **Overlap**: None - not used in core entity system
- **Action**: Add when needed (not priority)

---

### ⚠️ **EVALUATE CAREFULLY** (Potential Overlap)

#### PowerModels.jl
**Overlap Areas**:
1. **Network data structures**: Bus, Branch (ACLine/DCLine)
2. **Network constraint formulations**: DC-OPF, AC-OPF
3. **Mathematical formulations**: Power flow equations

**Current OpenDESSEM Status**:
- ✅ We have entity types (Bus, ACLine, DCLine) - **better than PowerModels**
- ❌ We DON'T have constraint implementations yet (TASK-006)
- ❌ We DON'T have power flow solvers yet

**Integration Options**:

**Option A: Use PowerModels.jl for Constraints (Recommended)**
```julia
using PowerModels as PM

function build_network_constraints!(model::DessemModel)
    # Convert OpenDESSEM entities → PowerModels data
    pm_data = convert_to_powermodel(model.system)

    # Use PowerModels constraint formulations
    PM.build_ref(pm_data, PM.AbstractPowerModel, PM.DCPPowerModel)

    # Extract constraints and add to DessemModel
    # ...
end
```

**Pros**:
- Proven mathematical formulations (422 citations)
- Battle-tested in production
- Active maintenance
- Solver-agnostic (works with HiGHS, Gurobi, etc.)

**Cons**:
- Dict-based data structure (less type-safe than entities)
- Learning curve for PowerModels API
- May need adapter layer

**Option B: Implement Our Own Constraints**
```julia
function build_network_constraints!(model::DessemModel)
    # Custom DC-OPF formulation using OpenDESSEM entities
    for line in model.system.ac_lines
        for t in 1:model.time_periods
            @constraint(model.jump_model,
                -line.max_flow <= flow[line.id, t] <= line.max_flow
            )
            # Add power flow equation: θ_i - θ_j = X_ij * f_ij
        end
    end
end
```

**Pros**:
- Full control over implementation
- Type-safe entity system
- No external dependency

**Cons**:
- Reinventing the wheel
- Potential bugs in constraint math
- Maintenance burden

**Recommendation**: **Option A (Use PowerModels.jl)**
- Study PowerModels constraint formulations
- Create adapter to convert entities → PowerModels data
- Keep OpenDESSEM entity system for type safety
- Leverage PowerModels for mathematical correctness

---

### 🔴 **DO NOT ADD YET** (Different Scope)

#### SDDP.jl
**Reason**:
- HydroPowerModels.jl uses SDDP for **long-term stochastic planning**
- OpenDESSEM Phase 1 is **deterministic daily dispatch**
- No need for stochastic optimization yet

**When to Add**:
- Phase 2: Stochastic module (multi-scenario inflows)
- Phase 3: Multi-week planning (beyond daily dispatch)

**Action**: **DEFER** - Study now, add later

---

## Integration Roadmap

### Phase 1: Current (Deterministic Daily Dispatch)
**Target**: Short-term deterministic optimization (24-168 hours)

**Dependencies to Add**:
1. ✅ **PWF.jl** - Load Brazilian ANAREDE files
2. ⚠️ **PowerModels.jl** - Network constraint formulations (evaluate first)
3. ❌ **SDDP.jl** - NOT YET (different scope)

**Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│                    OpenDESSEM                           │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌────────────────┐      ┌──────────────────┐           │
│  │  Entity System │─────▶│ Variable Manager │           │
│  │  (Built)       │      │  (TASK-005)       │           │
│  └────────────────┘      └──────────────────┘           │
│           │                        │                      │
│           ▼                        ▼                      │
│  ┌──────────────────────────────────────────┐           │
│  │    Constraint Builder (TASK-006)        │           │
│  │    ┌─────────────────────────────────┐   │           │
│  │    │  PowerModels.jl Formulations?   │   │           │
│  │    │  (Adopt or Reference)           │   │           │
│  │    └─────────────────────────────────┘   │           │
│  └──────────────────────────────────────────┘           │
│           │                                                │
│           ▼                                                │
│  ┌────────────────┐                                       │
│  │  Solver        │                                       │
│  │  HiGHS/Gurobi  │                                       │
│  └────────────────┘                                       │
└─────────────────────────────────────────────────────────┘
```

---

### Phase 2: Stochastic Module (Future)
**Target**: Multi-scenario optimization with inflow uncertainty

**Dependencies to Add**:
1. **SDDP.jl** - Stochastic Dual Dynamic Programming
2. **Distributions.jl** - Probability distributions
3. **Scenario generation** for inflows

**Integration Strategy**:
```julia
# New module: OpenDESSEM.Stochastic

module Stochastic

using SDDP
using ..Core  # OpenDESSEM core models

struct StochasticHydroModel
    deterministic::DessemModel
    scenarios::Vector{InflowScenario}
    stage_count::Int  # Number of decision stages
end

function solve(stochastic::StochasticHydroModel)
    # SDDP.jl forward-backward decomposition
    # 1. Forward pass: Decision rules
    # 2. Backward pass: Benders cuts
    # 3. Converges to optimal policy
end

end
```

**When to Implement**: After deterministic version is production-ready

---

## Specific Recommendations

### 1. **PWF.jl Integration** ✅ (Do Now)

**File**: `src/data/loaders/pwf_loader.jl`

```julia
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
```
"""
function load_from_pwffile(filepath::String)
    @info "Loading ANAREDE file" filepath=filepath

    # Parse .pwf file using PWF.jl
    pwf_data = PWF.parse(filepath)

    # Convert PWF data → OpenDESSEM entities
    buses = parse_buses(pwf_data)
    ac_lines = parse_ac_lines(pwf_data)
    dc_lines = parse_dc_lines(pwf_data)
    thermal = parse_thermal(pwf_data)
    hydro = parse_hydro(pwf_data)

    # Build ElectricitySystem
    return ElectricitySystem(;
        buses = buses,
        ac_lines = ac_lines,
        dc_lines = dc_lines,
        thermal_plants = thermal,
        hydro_plants = hydro,
        base_date = Date(pwf_data["data_base"])
    )
end
```

**Timeline**: TASK-010 (File-Based Loaders)

---

### 2. **PowerModels.jl Integration** ⚠️ (Evaluate First)

**File**: `src/constraints/network_powermodels.jl` (new file)

```julia
using PowerModels as PM
using JuMP
using ..Core
using ..Entities

"""
    build_powermodel_constraints!(model::DessemModel, formulation::Symbol)

Build network constraints using PowerModels.jl formulations.

# Formulations
- `:dcopf` - DC Optimal Power Flow (linear, fast)
- `:acopf` - AC Optimal Power Flow (nonlinear, accurate)

# Example
```julia
build_powermodel_constraints!(model, :dcopf)
```
"""
function build_powermodel_constraints!(model::DessemModel, formulation::Symbol)
    # Convert OpenDESSEM entities → PowerModels data dict
    pm_data = convert_to_powermodel(model)

    # Select formulation
    pm_formulation = formulation == :dcopf ? PM.DCPPowerModel : PM.ACPPowerModel

    # Build PowerModels problem
    pm = PM.instantiate_model(pm_data, pm_formulation, JuMP.Optimizer)

    # Extract constraints and add to DessemModel
    # (This requires studying PowerModels.jl API)

    @info "Built $(formulation) constraints using PowerModels.jl"
end

"""
    convert_to_powermodel(system::ElectricitySystem)

Convert OpenDESSEM ElectricitySystem → PowerModels data dict.
"""
function convert_to_powermodel(system::ElectricitySystem)
    Dict{String, Any}(
        "bus" => convert_buses(system.buses),
        "branch" => convert_branches(system.ac_lines, system.dc_lines),
        "gen" => convert_generators(system.thermal_plants, system.hydro_plants),
        # PowerModels-specific data
        "bus_name" => [bus.name for bus in system.buses],
        "branch_name" => [line.name for line in system.ac_lines],
        # ...
    )
end
```

**Decision Point**: TASK-006 (Constraint Builder System)

**Evaluation Criteria**:
1. How complex is PowerModels.jl API?
2. Can we maintain type safety with entities?
3. Performance impact of adapter layer
4. Maintenance burden vs. reimplementation

---

### 3. **HydroPowerModels.jl Integration Study** 📚 (Learn From)

**What to Study**:

1. **Hydrothermal Coordination**
   - How they couple hydro and thermal decisions
   - Water balance constraints
   - Hydro production functions

2. **Temporal Decomposition**
   - How they handle multi-period problems
   - Forward-backward algorithm
   - State variable tracking (reservoir volumes)

3. **Scenario Handling**
   - How they represent inflow uncertainty
   - Scenario tree construction
   - Risk measures (CVaR, expected value)

4. **Data Structures**
   - How they organize system data
   - Time series indexing
   - State representation

**Files to Review**:
```
HydroPowerModels.jl/src/
├── hydro_thermal.jl        # Core hydrothermal model
├── network.jl              # Network constraints
├── hydro_plant.jl          # Hydro plant modeling
├── policies.jl             # Policy functions
└── utils.jl                # Utilities
```

**Action**: Create documentation study notes, NOT code integration yet

---

## Dependency Installation Order

### Immediate (TASK-008/010 Phase)
```julia
# Add to Project.toml
PWF = "https://github.com/LAMPSPUC/PWF.jl"

# Install
] add https://github.com/LAMPSPUC/PWF.jl
```

### Evaluation Phase (TASK-006)
```julia
# Test PowerModels.jl integration
] add PowerModels

# Create prototype constraint builder
# Evaluate performance and API fit
# Decide: adopt or implement custom?
```

### Future Phase (Stochastic Module)
```julia
# When adding stochastic optimization
] add SDDP
] add Distributions
] add HydroPowerModels  # Maybe, as reference
```

---

## Code Duplication Risk Assessment

### ✅ **NO RISK** - Complementary Functionality

| Component | HydroPowerModels | OpenDESSEM | Overlap? |
|-----------|------------------|-------------|----------|
| **Time Horizon** | Long-term (weeks/months) | Short-term (day/week) | ❌ None |
| **Optimization** | Stochastic (scenarios) | Deterministic (single) | ❌ None |
| **Resolution** | Coarse (weekly stages) | Fine (hourly periods) | ❌ None |
| **Purpose** | Planning | Dispatch | ❌ None |

### ⚠️ **POTENTIAL OVERLAP** - Evaluate Before Using

| Component | HydroPowerModels | OpenDESSEM (Planned) | Action |
|-----------|------------------|----------------------|--------|
| **Network Constraints** | PowerModels.jl-based | TASK-006: Custom? | Study PowerModels first |
| **Hydro Modeling** | Aggregate reservoirs | Plant-level entities | ✅ Different (keep both) |
| **Data Structures** | Dict-based | Type-safe entities | ✅ OpenDESSEM better |
| **File I/O** | CSV/JSON | PWF.jl (Brazil) | ✅ Different formats |

---

## Recommended Action Plan

### ✅ **Phase 1: Add PWF.jl Now** (TASK-010)
```bash
# 1. Updated Project.toml (done)
# 2. Install package
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# 3. Test basic functionality
julia --project= -e 'using PWF; println("PWF.jl loaded successfully")'
```

### 📚 **Phase 2: Study PowerModels.jl** (Before TASK-006)
**Tasks**:
1. Read PowerModels.jl documentation
2. Study DC-OPF formulation in [PowerModels.jl Paper](https://arxiv.org/pdf/1711.01728)
3. Create prototype: Convert OpenDESSEM entities → PowerModels data
4. Evaluate: Is PowerModels API a good fit?

### ⚠️ **Phase 3: Decide on PowerModels Integration**
**Criteria**:
- Can we maintain type safety with entities?
- Is adapter layer too complex?
- Do we need custom Brazilian features (e.g., 4 submarkets)?

**Decision Point**: Start TASK-006 implementation

### 🔮 **Phase 4: Study HydroPowerModels for Future** (Post-MVP)
**Tasks**:
1. Read HydroPowerModels.jl source code
2. Study SDDP.jl documentation
3. Design stochastic module architecture
4. Plan Phase 2: Multi-scenario optimization

---

## Conclusion

### Key Findings

1. **PWF.jl**: ✅ **ADD IMMEDIATELY**
   - No overlap with OpenDESSEM
   - Critical for Brazilian data loading
   - Already in technical plan

2. **HydroPowerModels.jl**: ✅ **STUDY, DON'T INTEGRATE YET**
   - Different time horizon (long vs short term)
   - Different problem type (stochastic vs deterministic)
   - Valuable reference for future stochastic work
   - No code duplication risk

3. **PowerModels.jl**: ⚠️ **EVALUATE CAREFULLY**
   - Potential overlap in network constraints
   - Proven mathematical formulations
   - Decision needed: adopt or implement custom?

### Next Steps

1. ✅ Install PWF.jl
2. 📚 Study PowerModels.jl documentation
3. 📚 Read HydroPowerModels.jl source code
4. ⚠️ Make PowerModels integration decision at TASK-006
5. 🔮 Plan stochastic module for future phase

---

**Sources**:
- [HydroPowerModels.jl GitHub](https://github.com/andrewrosemberg/HydroPowerModels.jl)
- [HydroPowerModels.jl Documentation](https://andrewrosemberg.github.io/HydroPowerModels.jl/stable/)
- [PowerModels.jl GitHub](https://github.com/lanl-ansi/PowerModels.jl)
- [PowerModels.jl Documentation](https://lanl-ansi.github.io/PowerModels.jl/stable/)
- [PowerModels.jl Paper](https://arxiv.org/pdf/1711.01728)
- [LAMPSPUC/PWF.jl GitHub](https://github.com/LAMPSPUC/PWF.jl)
- [PWF.jl Documentation](https://lampspuc.github.io/PWF.jl/)
