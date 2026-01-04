# Open-Source DESSEM: Project Planning Document

## Executive Summary

This document outlines a comprehensive plan for developing an open-source implementation of DESSEM (Modelo de Programação Diária da Operação de Sistemas Hidrotérmicos) in Julia using JuMP. DESSEM is Brazil's official day-ahead hydrothermal dispatch optimization model, operated by ONS (Operador Nacional do Sistema) and CCEE (Câmara de Comercialização de Energia Elétrica) since January 2020.

**Project Goal**: Create a flexible, reproducible, and extensible open-source version that enables research, validation, and innovation in short-term electricity market optimization.

**Technology Stack**: Julia, JuMP, SDDP.jl, HiGHS/Gurobi solvers

---

## 1. Problem Definition & Context

### 1.1 What is DESSEM?

DESSEM is a **Mixed-Integer Linear Programming (MILP)** model that solves the daily energy dispatch problem for interconnected hydrothermal systems with:

- **Temporal scope**: Day-ahead scheduling, typically 1-14 days with half-hourly discretization
- **Spatial scope**: Brazilian interconnected system (SIN): ~158 hydro plants, ~109 thermal plants, 6,450 buses, 8,850 transmission lines
- **Optimization horizon**: Up to 14 days (168-336 time steps)
- **Primary objective**: Minimize operational cost (thermal generation + future cost from medium-term model)

### 1.2 Operating Context in Brazil

**Pre-DESSEM (pre-Jan 2020)**:
- Weekly dispatch using DECOMP model with 3 load blocks
- PLD (spot price) calculated on weekly basis

**Post-DESSEM (Jan 2020 onwards)**:
- Daily dispatch with hourly PLD granularity
- Integrated chain: NEWAVE (long-term) → DECOMP (medium-term) → DESSEM (short-term)
- Hourly PLD prices: 2,880 values/month vs. 48 previously
- 4 submarkets (N, NE, SE/CO, S) with independent CMO-based pricing

**Impact**: 
- Efficiency gains in dispatch accuracy
- Better price signals for renewable sources
- More granular market information

---

## 2. Technical Specifications

### 2.1 Core Mathematical Model

#### 2.1.1 Decision Variables

```
Binary variables:
- u[i,t] ∈ {0,1}     Thermal unit i commitment status at time t
- z[i,t] ∈ {0,1}     Startup indicator for unit i at time t
- w[i,t] ∈ {0,1}     Shutdown indicator for unit i at time t
- x[i,t] ∈ {0,1}     Configuration mode for combined-cycle unit

Continuous variables:
- g_th[i,t] ∈ [0, G_th^max_i] Thermal generation (MW)
- g_h[j,t] ∈ [0, G_h^max_j(V_j,t)] Hydro generation (MW, nonlinear function)
- q[j,t] ∈ [0, Q^max_j] Water outflow from plant j (m³/s)
- s[j,t] ∈ [0, S^max_j] Water spillage from plant j (m³/s)
- V[j,t] ∈ [V^min_j, V^max_j] Reservoir volume at plant j (hm³)
- p[ℓ,t], θ[n,t] Active power flows and voltage angles (AC-OPF)
- α[t] ≥ 0 Slack variables for constraint violations (penalty formulation)
```

#### 2.1.2 Objective Function

```
minimize:
  Σ_t [ Σ_i (C^fuel_i · g_th[i,t] + C^startup_i · z[i,t])
        + CVaR_α(ΔV[T])
        + Σ_v (ρ_v · α_v[t]) ]

Where:
- C^fuel_i: Fuel cost (R$/MWh)
- C^startup_i: Startup cost for unit i
- CVaR: Conditional Value at Risk on final reservoir deviations
- ρ_v: Penalty cost for constraint violation v
```

#### 2.1.3 Core Constraints

**Energy Balance** (per submarket):
```
Σ_i g_th[i,t] + Σ_j g_h[j,t] + g_wind[t] + g_solar[t] 
  + imports[t] = demand[t] + exports[t]
∀ t ∈ T, per submarket
```

**Thermal Unit Commitment**:
```
Minimum generation:
  G^min_i · u[i,t] ≤ g_th[i,t] ≤ G^max_i · u[i,t]

Startup/Shutdown dynamics:
  u[i,t] - u[i,t-1] = z[i,t] - w[i,t]
  
Minimum up/down times:
  Σ_{τ=t}^{t+T^up_i-1} u[i,τ] ≥ T^up_i · z[i,t]
  Σ_{τ=t}^{t+T^dn_i-1} (1 - u[i,τ]) ≥ T^dn_i · w[i,t]

Ramp rates:
  g_th[i,t] - g_th[i,t-1] ≤ R^up_i · u[i,t-1] + G^max_i · z[i,t]
  g_th[i,t-1] - g_th[i,t] ≤ R^dn_i · u[i,t] + G^max_i · w[i,t]
```

**Hydro Water Balance** (cascade system):
```
V[j,t] = V[j,t-1] + inflow[j,t] - q[j,t] - s[j,t] 
         + Σ_{k∈upstream(j)} (q[k,t] + s[k,t]) · τ^delay_{k→j}

Reservoir bounds:
  V^min_j ≤ V[j,t] ≤ V^max_j
  
Generation from water discharge (nonlinear):
  g_h[j,t] = ρ_water · g[j] · Q[j,t] · h^net_j(V[j,t], V[j,t+1])
```

**AC Optimal Power Flow**:
```
Power balance (Kirchhoff Current Law):
  p[i,t] = Σ_ℓ (p^flow[i-j,t])
  q[i,t] = Σ_ℓ (q^flow[i-j,t])

Power flow equations:
  p^flow[ℓ,t] = g_ℓ · (V²[i,t] - V[i,t]·V[j,t]·cos(θ[i,t] - θ[j,t]))
  q^flow[ℓ,t] = -b_ℓ · (V²[i,t] - V[i,t]·V[j,t]·cos(θ[i,t] - θ[j,t]))

Line flow limits:
  |p^flow[ℓ,t]|² + |q^flow[ℓ,t]|² ≤ S²^max_ℓ
  
Voltage bounds:
  V^min[i] ≤ V[i,t] ≤ V^max[i]
  θ[i,t] - θ[j,t] ≤ Δθ^max (angle difference limit)
```

**Combined-Cycle Plants**:
```
Dedicated operational modes:
- Mode 1: Gas turbine only
- Mode 2: Combined (GT + Steam turbine)
- Mode 3: Steam turbine only (in certain conditions)

Configuration transitions:
  x[i,t] ∈ {1,2,3}, transition costs C^config[mode_old→mode_new]
```

### 2.2 Network Representation

**Power System Network** (Implemented using PowerModels.jl):
- DC-OPF (linear, simplified): First iteration
- AC-OPF with MILP relaxation: Post-MVP
- Linearized relaxation for speed vs. accuracy tradeoff
- Iterative network constraint inclusion (starting minimal set)

**Architecture**: OpenDESSEM entities → Adapter layer → PowerModels.jl formulations → ONS-specific constraints → Solver

### 2.3 Key Model Parameters

| Parameter | Source | Update Frequency |
|-----------|--------|-----------------|
| Thermal plant costs | CCEE, NEWAVE output | Daily |
| Thermal ramp rates | Plant specifications | Static |
| Hydro plant efficiency | ONS database | Seasonal calibration |
| Reservoir inflows | Hydrological forecast | Daily |
| Transmission network data | ONS ANAREDE | Quarterly |
| Demand forecast | ONS EPE | Daily |
| Renewable generation forecast | ONS/INMET | Hourly |

---

## 3. Architecture & Software Design

### 3.1 Project Structure

```
dessem-julia/
├── src/
│   ├── DESSEM.jl                 # Main module
│   ├── core/
│   │   ├── model.jl              # JuMP model construction
│   │   ├── variables.jl          # Variable definitions
│   │   ├── objective.jl          # Objective function setup
│   │   └── constraints/
│   │       ├── energy_balance.jl
│   │       ├── thermal_uc.jl
│   │       ├── hydro.jl
│   │       ├── network.jl
│   │       └── security.jl
│   ├── data/
│   │   ├── system.jl             # System input parsing
│   │   ├── plants.jl             # Thermal/hydro plant data
│   │   ├── network.jl            # Network topology
│   │   └── io.jl                 # File I/O (CSV/JSON/HDF5)
│   ├── solvers/
│   │   ├── setup.jl              # Solver configuration
│   │   └── utils.jl              # Presolve, warm-start
│   ├── analysis/
│   │   ├── results.jl            # Solution extraction
│   │   ├── validation.jl         # Constraint verification
│   │   └── visualization.jl      # Plots/reports
│   └── utils/
│       ├── time_series.jl        # Time discretization
│       ├── logging.jl            # Debugging/logging
│       └── performance.jl        # Benchmarking
├── test/
│   ├── unit/                      # Unit tests
│   ├── integration/               # Integration tests
│   └── validation/                # Against real DESSEM data
├── examples/
│   ├── simple_hydrothermal.jl    # 3-plant tutorial
│   ├── brazilian_system.jl       # Full SIN configuration
│   └── sensitivity_analysis.jl   # Parameter variation
├── docs/
│   ├── guide.md                  # User guide
│   ├── model_formulation.md      # Detailed math
│   ├── api_reference.md          # Function documentation
│   └── figs/                     # Diagrams
├── Project.toml                  # Julia package manifest
├── README.md
└── LICENSE

Key dependencies:
├── JuMP.jl >= 1.0                # Optimization modeling
├── HiGHS.jl                      # Open-source MILP solver
├── Gurobi.jl (optional)          # Commercial solver option
├── PowerModels.jl (PRIMARY)      # Network constraint formulations (DC-OPF, AC-OPF)
├── PWF.jl (v0.1.0)              # Brazilian .pwf file parser
├── SDDP.jl (future)              # Stochastic medium-term linking
├── DataFrames.jl                 # Tabular data handling
├── Plots.jl / Makie.jl           # Visualization
└── TimeSeries.jl / TSFrames.jl   # Time series data
```

### 3.2 Design Patterns

**Modular Architecture**:
```julia
# User-facing API
model = DessemModel(system, time_periods=336, discretization=:hourly)

# Constraint builders
add_thermal_units!(model, thermal_plants)
add_hydro_plants!(model, hydro_plants)
add_network_constraints!(model, network)

# Solve and extract results
solution = optimize!(model, solver=HiGHS.Optimizer())
dispatch = extract_dispatch(solution)
prices = calculate_marginal_costs(solution)
```

**Extensibility**:
- Abstract constraint types for custom formulations
- Pluggable solver backends
- Middleware for pre/post-processing

### 3.3 Core Components

#### Component 1: Model Builder
```julia
struct DessemModel
    jump_model::JuMP.Model
    system::ElectricitySystem
    time_periods::Int
    discretization::Symbol  # :hourly, :half_hourly
    constraints::Dict{String, Any}
    metadata::Dict{String, Any}
end
```

#### Component 2: Constraint Manager
```julia
abstract type AbstractConstraint end

struct EnergyBalanceConstraint <: AbstractConstraint
    submarkets::Vector{String}
    include_losses::Bool
    include_interchange::Bool
end

add_constraint!(model, constraint::AbstractConstraint)
```

#### Component 3: Data Layer
```julia
struct ThermalPlant
    id::String
    fuel_cost::Vector{Float64}      # $/MWh per time step
    min_gen::Float64
    max_gen::Float64
    ramp_up::Float64
    ramp_down::Float64
    min_up_time::Int
    min_down_time::Int
    startup_cost::Float64
    shutdown_cost::Float64
    # ... combined-cycle specific fields
end

struct HydroPlant
    id::String
    reservoir_min::Float64          # hm³
    reservoir_max::Float64
    reservoir_initial::Float64
    efficiency_curve::Function      # g_h(q, h)
    max_outflow::Float64            # m³/s
    max_spillage::Float64
    min_outflow::Float64
    cascade_downstream::Vector{String}
    time_delay::Int                 # time steps
end
```

---

## 4. Implementation Roadmap

### Phase 1: MVP (Months 1-3)

**Goal**: Functional day-ahead dispatch for simplified system

**Deliverables**:
- [ ] Basic JuMP model structure
- [ ] Thermal unit commitment constraints
- [ ] Hydro water balance (linear approximation)
- [ ] Energy balance per submarket
- [ ] DC-OPF (simplified network model) using PowerModels.jl
- [ ] PWF.jl integration for .pwf file parsing
- [ ] HiGHS solver integration
- [ ] Basic I/O (CSV input, solution export)
- [ ] Unit tests (>80% coverage)
- [ ] Simple 10-plant test case

**Scope**:
- Pure MILP formulation (no stochasticity)
- Deterministic hydro inflows
- Fixed renewable generation
- No combined-cycle complexity
- Linear hydro generation function
- DC power flow (angle difference limits only)

**Success Criteria**:
- Model solves in < 1 minute for 7-day horizon
- Energy balance constraint verified
- Feasible solutions for test cases
- Reproducible results

---

### Phase 2: Full Model (Months 4-6)

**Goal**: Production-grade model matching DESSEM v19-20 capabilities

**Additions**:
- [ ] AC-OPF with MILP relaxation
- [ ] Combined-cycle plant modes
- [ ] Nonlinear hydro efficiency curves
- [ ] Ramp rate constraints
- [ ] Minimum up/down time constraints
- [ ] Spinning reserve requirements
- [ ] CCEE PLD-compatible output
- [ ] Constraint violation penalties (feasibility)
- [ ] Advanced preprocessing
- [ ] Solution warm-start capability
- [ ] Comprehensive validation suite
- [ ] Documentation (300+ pages)
- [ ] 2-3 real case studies (SIN subset)

**Scope**:
- Full Brazilian interconnected system topology option
- Multiple solver backends (HiGHS, Gurobi, CPLEX)
- Parallel solution strategies
- Half-hourly discretization
- Cascade hydro constraints with time delays
- Submarine transmission constraints

**Success Criteria**:
- 7-day real case matches DESSEM within 5% on total cost
- Solves full SIN in < 2 hours (Gurobi)
- <1% optimality gap achievable
- All constraint types functional

---

### Phase 3: Extensions & Optimization (Months 7-9)

**Goal**: Advanced features and computational performance

**Additions**:
- [ ] Stochastic UC with scenario trees
- [ ] Wind/solar forecasting integration
- [ ] Environmental constraints
- [ ] Carbon emissions accounting
- [ ] Demand response modeling
- [ ] Rolling horizon / receding horizon
- [ ] Decomposition algorithms (Benders, Dantzig-Wolfe)
- [ ] Cutting plane algorithms
- [ ] Parallel branch-and-bound customization
- [ ] Performance benchmarking suite
- [ ] Web-based UI (optional)
- [ ] API server for cloud deployment

**Performance Targets**:
- 14-day horizon: < 30 min with HiGHS
- 7-day horizon: < 5 min
- Gap reduction to 0.5-1% routinely achievable

---

### Phase 4: Production Deployment & Ecosystem (Months 10+)

**Goal**: Operational utility and community adoption

**Additions**:
- [ ] Real-time data connectors (ONS, CCEE APIs)
- [ ] Comparison module against official DESSEM
- [ ] Regulatory reporting formats
- [ ] Integration with market bidding systems
- [ ] Commercial solver contract management
- [ ] Cloud deployment (AWS/Azure templates)
- [ ] Docker containerization
- [ ] CI/CD pipeline
- [ ] Publication of benchmark instances
- [ ] Community forum & issue tracking

---

## 5. Technical Deep Dives

### 5.1 Nonlinear Hydro Generation Modeling

**Challenge**: Hydro generation is nonlinear function of water discharge (q) and net head (h):
```
G_h(q, h) = ρ_water · g · η(q,h) · q · h

Where:
- ρ_water = 1000 kg/m³
- g = 9.81 m/s²
- η(q,h) = efficiency curve (0.8-0.95 typical)
- q = water discharge (m³/s)
- h = h_mon(V) - h_jus(V) = net head
```

**DESSEM Approach**: Piecewise linear approximation
```julia
# 10-20 breakpoints in (q, h) space
# Linear interpolation between points
# Additional variables: λ[j,k,t] ≥ 0 (convex combination weights)

g_h[j,t] = Σ_k λ[j,k,t] · G_h_approx(q_k, h_k)
q[j,t] = Σ_k λ[j,k,t] · q_k
Σ_k λ[j,k,t] = 1
λ[j,k,t] ∈ [0,1]
```

**Implementation in JuMP**:
```julia
function add_hydro_generation_nonlinearity!(model, plant::HydroPlant, t)
    # Efficiency curve calibration from historical data
    q_breakpoints = [0, 50, 100, 150, 200]  # m³/s
    h_breakpoints = [200, 250, 300]  # meters
    
    # Create efficiency matrix
    efficiency = plant.compute_efficiency_grid(q_breakpoints, h_breakpoints)
    
    # Add SOS2 constraints for piecewise approximation
    # ...
end
```

### 5.2 Cascade Hydro Constraints with Time Delays

**Challenge**: Water propagation between plants takes time (0.5-72 hours)

**Formulation**:
```julia
# Water balance with delays
V[j,t] = V[j,t-1] + inflow[j,t] - q[j,t] - s[j,t]
         + Σ_{k ∈ upstream(j)} 
           (q[k,t-delay(k,j)] + s[k,t-delay(k,j)])

# Handle initial period (t < delay):
# Use historical cascade releases or initial conditions
```

**Data Structure**:
```julia
struct CascadeNetwork
    plant_order::Vector{String}           # Topological sort
    adjacency::Dict{String, Vector{String}} # Immediate downstream
    propagation_delay::Dict{Tuple, Int}   # (from, to) -> steps
end
```

### 5.3 AC-OPF MILP Formulation

**Challenge**: Full AC power flow is non-convex; DESSEM uses iterative DC → AC refinement

**Implementation Strategy**:
```
Phase 1 (MVP): Pure DC-OPF
  minimize cost s.t.
  p[i,t] - p[j,t] = B_ij · θ_ij  (DC approximation)

Phase 2: Iterative AC refinement
  1. Solve DC-OPF
  2. Check AC feasibility of flows
  3. Add violated AC constraints as cuts
  4. Re-solve (branch-and-cut)
  5. Repeat until convergence
```

**Key Constraints** (SOC relaxation):
```julia
# McCormick-based MILP approximation
# Replaces nonconvex AC constraints with
# linear inequalities in lifted space
```

### 5.4 Combined-Cycle Plant Modeling

**Challenge**: Combined-cycle plants have 3 modes with different cost/efficiency profiles

**DESSEM Representation**:
```
Mode 1: Gas Turbine Only
  - Fastest startup (15-30 min)
  - Highest fuel cost/MWh
  - Lowest min generation

Mode 2: Combined Cycle (GT + Steam)
  - Slowest startup (60+ min)
  - Lowest fuel cost/MWh
  - Higher min generation
  - Cannot startup in this mode directly

Mode 3: Steam Turbine Only
  - Only possible from Mode 2
  - Intermediate cost
  - Used during part-load operation
```

**Implementation**:
```julia
struct CombinedCyclePlant <: ThermalPlant
    # ... standard thermal fields ...
    
    # Mode-specific parameters
    modes::Dict{Symbol, ModeConfig}  # :gas_only, :combined, :steam_only
    
    # Transition matrix (startup/shutdown costs)
    transition_cost::Matrix{Float64} # mode[t-1] × mode[t]
end

# Variables
@variable(model, x[i,t] ∈ {1,2,3})  # Operating mode
@variable(model, g_mode[i,t,m] ≥ 0)  # Generation in mode m

# Constraints
@constraint(model, sum(g_mode[i,t,:]) == g_th[i,t])
@constraint(model, g_mode[i,t,m] ≤ G_max[m] * (x[i,t] == m))
```

### 5.5 Marginal Cost Extraction (for PLD Calculation)

**Key**: DESSEM output includes dual variables (shadow prices) for energy balance constraints

**Challenge**: MILP duality theory is complex; DESSEM uses specialized techniques

**Approaches**:
1. **Relaxed LP duals**: Fix integer variables, solve LP relaxation
2. **Subgradient methods**: Estimate from near-optimal solutions
3. **Decomposition-based**: Use Lagrangian relaxation subproblems

**Implementation**:
```julia
function extract_marginal_costs(solution, model)
    # For each energy balance constraint
    for (submarket, t) in zip(submarkets, time_periods)
        constraint = energy_balance[submarket, t]
        dual_value = dual(constraint)  # JuMP.dual() interface
        
        # PLD bounded by floor/ceiling prices
        pld[submarket, t] = clamp(dual_value,
                                   PLD_MIN,
                                   PLD_MAX)
    end
    return pld
end
```

---

## 6. Data Requirements & Specification

### 6.1 Input Data Formats

**Thermal Plant Inventory** (CSV/JSON):
```csv
plant_id,fuel_type,capacity_mw,min_gen_mw,ramp_up_mw_min,ramp_down_mw_min,min_up_hours,min_down_hours,startup_cost_usd,fuel_cost_usd_mwh
G001,coal,500,250,100,100,12,8,50000,45.5
G002,natural_gas,400,100,50,50,3,2,10000,85.2
```

**Hydro Plant Inventory** (CSV):
```csv
plant_id,reservoir_max_hm3,reservoir_min_hm3,efficiency,max_outflow_m3s,min_outflow_m3s,downstream_plant,propagation_delay_hours
H001,2000,200,0.88,500,50,H002,6
H002,1500,150,0.85,400,30,R001,2
```

**Network Topology** (PSSE or custom JSON):
- Bus definitions (coordinates, voltage bases, demand)
- Transmission lines (impedance, flow limits, losses)
- Transformer specifications
- Renewable injection nodes

**Time Series Data** (HDF5/Parquet for efficiency):
- Hourly demand per submarket
- Wind/solar generation forecasts
- Hydro inflows (deterministic scenario)
- Reservoir initial conditions

### 6.2 DESSEM Configuration File

```yaml
# dessem_config.yml
model:
  horizon_days: 7
  discretization: hourly
  base_case: "january_2024"
  
system:
  n_submarkets: 4
  n_thermal: 109
  n_hydro: 158
  n_buses: 6450
  n_lines: 8850
  
solver:
  backend: HiGHS
  time_limit_seconds: 3600
  optimality_gap: 0.01
  method: "auto"
  parallel_workers: 8
  
constraints:
  enforce_ac_opf: true
  include_combined_cycle: true
  include_ramp_limits: true
  include_min_up_down: true
  reserve_margin: 0.05
  
feasibility:
  allow_load_shedding: true
  load_shed_penalty: 5000  # R$/MWh
  allow_wind_curtailment: true
```

---

## 7. Validation & Testing Strategy

### 7.1 Unit Tests

```julia
# test/unit/constraints/
@testset "Energy Balance Constraints" begin
    @test isapprox(sum(generation[t]) + imports[t], 
                   demand[t] + exports[t], 
                   rtol=1e-6)
end

@testset "Hydro Water Balance" begin
    @test all(reservoir_min .<= V .<= reservoir_max)
    @test all(q .>= 0) && all(s .>= 0)
end

@testset "Thermal UC Logic" begin
    # Startup/shutdown consistency
    @test u[i,t] - u[i,t-1] == z[i,t] - w[i,t]
    # Mutual exclusivity
    @test all((z[i,t] .+ w[i,t]) .<= 1)
end
```

### 7.2 Integration Tests

```julia
# test/integration/
@testset "Simple 3-Plant System" begin
    # Load test case
    system = load_test_case("simple_hydrothermal")
    model = DessemModel(system, 7)
    
    # Solve
    solution = optimize!(model)
    
    # Verify constraints satisfied
    @test is_feasible(solution, tol=1e-4)
    @test is_optimal(solution, gap_tol=0.01)
end
```

### 7.3 Validation Against Real DESSEM

```julia
# test/validation/
@testset "Real Case Validation" begin
    # Load actual DESSEM input and official output
    official_data = load_ccee_official_results("2024-01-15")
    our_result = solve_dessem(same_input_data)
    
    # Compare key metrics
    @test ≈(total_cost(our_result), 
            official_data.total_cost, 
            rtol=0.05)  # Within 5%
    
    @test ≈(generation_dispatch(our_result, "H001"),
            official_data.dispatch("H001"),
            rtol=0.10)  # Within 10% per plant
end
```

### 7.4 Performance Benchmarking

```julia
# benchmark/
using BenchmarkTools, PkgBenchmark

@benchmarkset "DESSEM Solve Times" begin
    @benchgroup "7-day horizon" begin
        @bench "simple system (10 plants)" simple_solve()
        @bench "reduced SIN (50 plants)" reduced_solve()
        @bench "full SIN (267 plants)" full_solve()
    end
end
```

---

## 8. References & Knowledge Resources

### Core Mathematical References

1. **Diniz et al. (2020)** - "Hourly pricing and day-ahead dispatch setting in Brazil: The DESSEM model" (*Electric Power Systems Research*)
   - **Key for**: Model formulation, mathematical framework
   
2. **Dowson & Kapelevich (2021)** - "SDDP.jl: A Julia Package for Stochastic Dual Dynamic Programming" (*INFORMS J. Computing*)
   - **Key for**: Medium-term horizon linking (Phase 4)

3. **Saboia & Diniz (2019)** - "Recent improvements and computational challenges in DESSEM" (CEPEL Technical Report)
   - **Key for**: Solution algorithms, parallel computing strategies

### Solver & Framework References

4. **JuMP Documentation** - https://jump.dev/
   - Core optimization modeling interface

5. **HiGHS Documentation** - https://www.highs.dev/
   - Open-source MILP solver (primary)

6. **Gurobi Documentation** - https://www.gurobi.com/
   - Commercial option for performance-critical deployments

### Brazilian Market References

7. **CCEE Documentation** - https://www.ccee.org.br/
   - PLD calculation procedures, market rules, data feeds

8. **ONS Official Documentation** - https://www.ons.org.br/
   - System operation procedures, DESSEM usage documentation

9. **CEPEL DESSEM Manual** - https://www.cepel.br/
   - User manual versions 19-21, reference documentation

### Cascade Hydro Optimization

10. **Feng et al. (2022)** - "Optimal operation of cascade hydropower"
    - **Key for**: Water balance modeling, cascade constraints

### AC-OPF References

11. **Lavaei & Low (2012)** - "Zero duality gap in optimal power flow"
    - Semidefinite programming relaxations

12. **Oustry et al. (2022)** - "AC OPF: Conic Programming relaxation and MILP refinement"
    - MILP-based AC OPF solution approaches

---

## 9. Resource Planning

### 9.1 Team Structure (Recommended)

| Role | Count | Responsibility |
|------|-------|-----------------|
| Lead Developer (Julia) | 1 | Architecture, core model |
| Power Systems Engineer | 1 | Constraints, validation |
| Data Engineer | 1 | Input/output, APIs |
| QA/Testing Specialist | 1 | Test suite, benchmarking |
| Documentation Writer | 0.5 | User guide, examples |

**Total**: 4-4.5 FTE for production-grade release (9-12 months)

### 9.2 Development Tools

```
IDE:
- VS Code + Julia extension
- Pluto.jl for interactive notebooks
  
Version Control:
- GitHub (github.com/your-org/DESSEM.jl)
- Git branching: main, develop, feature/*
  
CI/CD:
- GitHub Actions for testing
- Codecov for coverage tracking
  
Documentation:
- Documenter.jl for API docs
- Sphinx + ReadTheDocs alternative
```

### 9.3 Computing Infrastructure

**Development**:
- 16-core, 64GB RAM workstation (for local testing)
- 4-8 CPU cores sufficient for MVP testing

**Testing/Validation**:
- 64-core server for nightly benchmarks
- ~2 hours compute per full 7-day SIN solve (HiGHS)
- ~15 minutes with Gurobi commercial license

**Deployment** (operational use):
- Cloud orchestration (Kubernetes optional)
- Auto-scaling based on daily dispatch demand
- Container registry for versioning

---

## 10. Deliverables & Milestones

### Milestone 1: Foundation (Month 1.5)
- [ ] GitHub repository setup with CI/CD
- [ ] Basic JuMP model scaffold
- [ ] Thermal UC constraint implementation
- [ ] First integration test passing
- [ ] README with "quick start" example

### Milestone 2: MVP Release (Month 3)
- [ ] Full thermal + hydro + energy balance constraints
- [ ] DC-OPF network model
- [ ] Example case solving in <2 minutes
- [ ] Basic documentation (100+ pages)
- [ ] v0.1.0 GitHub release

### Milestone 3: Production Ready (Month 6)
- [ ] AC-OPF with MILP refinement
- [ ] Combined-cycle plant support
- [ ] 5-case validation against official DESSEM
- [ ] Comprehensive documentation (300+ pages)
- [ ] Journal/conference paper submission
- [ ] v1.0.0 stable release

### Milestone 4: Extended Features (Month 9)
- [ ] Stochastic UC with scenarios
- [ ] Decomposition algorithms
- [ ] Advanced visualization tools
- [ ] v1.1.0 release

---

## 11. Success Metrics

**Technical**:
- [ ] Model solves 7-day SIN horizon in < 60 min (HiGHS), < 10 min (Gurobi)
- [ ] Achieves 0.5-1% optimality gap on large instances
- [ ] Within 5% of official DESSEM on real cases (cost metric)
- [ ] 95%+ test coverage on critical modules
- [ ] All constraint types functional and validated

**Adoption**:
- [ ] 100+ GitHub stars within 6 months
- [ ] 10+ external research groups using package
- [ ] 2+ publications in peer-reviewed venues
- [ ] Integration with at least 1 commercial energy platform
- [ ] Active open-source community (issues, PRs)

**Code Quality**:
- [ ] Julia code style passes official linting (JuliaFormatter)
- [ ] All functions documented with examples
- [ ] Documentation builds without warnings
- [ ] Reproducible examples in /examples/

---

## Appendix A: Glossary of Terms

| Term | Definition |
|------|-----------|
| **DESSEM** | Modelo de Programação Diária da Operação de Sistemas Hidrotérmicos (Daily Short-Term Hydrothermal Scheduling Model) |
| **CMO** | Custo Marginal de Operação (Marginal Operating Cost) |
| **PLD** | Preço de Liquidação das Diferenças (Spot price for bilateral contract differences) |
| **ONS** | Operador Nacional do Sistema (Brazilian System Operator) |
| **CCEE** | Câmara de Comercialização de Energia Elétrica (Electricity Trading Chamber) |
| **SIN** | Sistema Interligado Nacional (Brazilian Interconnected System) |
| **CVaR** | Conditional Value at Risk (risk-averse optimization measure) |
| **MILP** | Mixed-Integer Linear Programming |
| **UC** | Unit Commitment (generator startup/shutdown decisions) |
| **AC-OPF** | AC Optimal Power Flow (full nonlinear network optimization) |
| **DC-OPF** | DC Optimal Power Flow (linearized approximation) |
| **FTR** | Financial Transmission Right |

---

## Appendix B: Key Publications to Cite

```bibtex
@article{Santos2020,
  author={Santos, T.N. and Diniz, A.L. and Saboia, C.H. and Cabral, R.N. and Cerqueira, L.F.},
  title={Hourly pricing and day-ahead dispatch setting in Brazil: The DESSEM model},
  journal={Electric Power Systems Research},
  volume={189},
  pages={106709},
  year={2020},
  doi={10.1016/j.epsr.2020.106709}
}

@article{Dowson2021,
  author={Dowson, Oscar and Kapelevich, Lea},
  title={SDDP.jl: A Julia Package for Stochastic Dual Dynamic Programming},
  journal={INFORMS Journal on Computing},
  volume={33},
  number={3},
  pages={1025--1043},
  year={2021},
  doi={10.1287/ijoc.2020.0987}
}

@inproceedings{Diniz2018,
  author={Diniz, A.L. and Santos, T.N. and Saboia, C.H. and Maceira, M.E.P.},
  booktitle={6th International Workshop on Hydro Scheduling},
  title={Network constrained hydrothermal unit commitment problem for hourly dispatch and price setting in Brazil: the DESSEM model},
  location={Stavanger, Norway},
  year={2018}
}
```

---

**Document Version**: 1.0  
**Last Updated**: January 2026  
**Status**: Ready for Implementation  
**Recommended Start Date**: Q1 2026
