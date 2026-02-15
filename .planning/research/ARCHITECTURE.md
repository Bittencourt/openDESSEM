# Architecture Patterns: Hydrothermal Dispatch Solver Pipeline

**Domain:** Short-term hydrothermal scheduling optimization (DESSEM-style)
**Researched:** 2026-02-15
**Confidence:** MEDIUM (based on JuMP patterns, power systems literature, and OpenDESSEM context)

## Executive Summary

Hydrothermal dispatch solver pipelines follow a four-stage execution model: **Build → Optimize → Extract → Analyze**. The key architectural challenge is managing the transition from declarative constraint specification to imperative solver orchestration while preserving the ability to extract dual variables through two-stage pricing (MILP solve → fix integers → LP solve).

For OpenDESSEM's entity-driven design, the optimal architecture maintains strict layer separation:
- **Objective Layer**: Builds objective function from entities (similar to constraints)
- **Solver Layer**: Orchestrates optimization and handles solver-specific concerns
- **Extraction Layer**: Pulls primal/dual values from solved model
- **Analysis Layer**: Transforms raw solution into domain objects and export formats

The critical design decision is **where JuMP model mutation stops and solution extraction begins**. Best practice: objective building is the last mutation step, solve is immutable, extraction is read-only.

## Recommended Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    User/Application Layer                        │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Orchestration Layer (ElectricitySystem + time_periods)         │
│                                                                  │
│  • model = create_model(system, periods)                        │
│  • create_variables!(model)                                     │
│  • build_constraints!(model, constraint_list)                   │
│  • build_objective!(model, objective_spec)                      │
│  • solution = solve!(model, solver_options)                     │
│  • analysis = extract_solution(model, solution)                 │
│  • export_results(analysis, format)                             │
└────────────┬────────────────────────────────────────────────────┘
             │
    ┌────────┴────────┬──────────────┬──────────────┬─────────────┐
    ▼                 ▼              ▼              ▼             ▼
┌─────────┐    ┌─────────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│Variables│    │Constraints  │  │Objective │  │ Solvers  │  │Analysis  │
│ Manager │    │             │  │ Builder  │  │          │  │          │
└─────────┘    └─────────────┘  └──────────┘  └──────────┘  └──────────┘
     │              │                │              │              │
     │              │                │              │              │
     ▼              ▼                ▼              ▼              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       JuMP Model (mutable)                          │
│  Variables: [u, v, w, g, s, q, gh, pump, gr, curtail, ...]        │
│  Constraints: [energy_bal, water_bal, thermal_uc, ramp, ...]      │
│  Objective: @objective(model, Min, total_cost)                     │
└────────────┬────────────────────────────────────────────────────────┘
             │
             ▼ optimize!(model)
┌─────────────────────────────────────────────────────────────────────┐
│                    JuMP Model (solved, immutable)                   │
│  Primal Values: value.(model[:g])                                  │
│  Dual Values: dual.(model[:energy_balance])  [LP only]            │
│  Objective: objective_value(model)                                 │
│  Status: termination_status(model)                                 │
└────────────┬────────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Solution Objects                                │
│  • SolverResult (status, objective, solve_time, gap)               │
│  • PlantSchedule (generation by plant/time)                         │
│  • MarginalPrices (LMP by bus/submarket/time)                      │
│  • WaterValues (shadow prices on reservoir storage)                │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Boundaries

| Component | Responsibility | Input | Output | Mutates Model? |
|-----------|---------------|-------|--------|----------------|
| **VariableManager** | Create JuMP variables indexed by (entity, time) | ElectricitySystem, time_periods | Variables added to model | YES |
| **Constraints** | Add constraints via build!(model, system, constraint) | ElectricitySystem, variables | Constraints added to model | YES |
| **ObjectiveBuilder** | Construct objective function from cost terms | ElectricitySystem, variables | @objective set in model | YES |
| **SolverInterface** | Orchestrate solve, handle two-stage pricing | Model, SolverOptions | SolverResult | NO (creates new model for LP) |
| **SolutionExtractor** | Pull primal/dual values from solved model | Solved model, ElectricitySystem | Domain solution objects | NO |
| **AnalysisExporter** | Transform to CSV/JSON/HDF5 | Solution objects | Files on disk | NO |

### Data Flow

**Forward Pass (Build)**:
```
ElectricitySystem
  → VariableManager.create_variables!(model)
  → [JuMP variables: u, v, w, g, s, q, ...]

  → ConstraintBuilder.build!(model, system, constraints)
  → [JuMP constraints: energy_bal, water_bal, thermal_uc, ...]

  → ObjectiveBuilder.build!(model, system, objective_spec)
  → [@objective(model, Min, sum(costs))]
```

**Solve Pass**:
```
JuMP Model (built)
  → SolverInterface.solve!(model, options)
    IF two_stage_pricing:
      1. optimize!(model, Gurobi)  [MILP]
      2. fix_binary_variables!(model, solution)
      3. optimize!(model, HiGHS)   [LP for duals]
    ELSE:
      optimize!(model, solver)
  → SolverResult
```

**Backward Pass (Extract)**:
```
Solved Model
  → SolutionExtractor.extract_primal_values(model, system)
  → PlantSchedule, StorageLevels, Flows, ...

  → SolutionExtractor.extract_dual_values(model, system)
  → MarginalPrices, WaterValues, ...

  → AnalysisExporter.export_to_csv(solution, path)
  → CSV files on disk
```

## Patterns to Follow

### Pattern 1: Objective as Last Mutator

**What:** Objective function building is the final model mutation step before solve.

**Why:**
- Constraints must exist before objective references them
- Variables must be created before objective uses them
- Clear separation: build phase vs solve phase

**Implementation:**
```julia
# src/objective/production_cost.jl

"""Build production cost objective function."""
function build!(model::JuMP.Model, system::ElectricitySystem,
                obj::ProductionCostObjective, periods::Vector{Int})

    # Retrieve existing variables (do not create)
    g = model[:generation]         # thermal generation
    u = model[:commitment]         # thermal commitment
    v = model[:startup]            # thermal startup
    w = model[:shutdown]           # thermal shutdown
    gh = model[:hydro_generation]  # hydro generation
    deficit = model[:deficit]      # load not served

    # Build cost expression from entities
    cost_expr = AffExpr(0.0)

    # Fuel costs
    for plant in system.thermal_plants, t in periods
        add_to_expression!(cost_expr, plant.fuel_cost_rsj_per_mwh * g[plant.id, t])
    end

    # Startup/shutdown costs
    for plant in system.thermal_plants, t in periods
        add_to_expression!(cost_expr, plant.startup_cost_rs * v[plant.id, t])
        add_to_expression!(cost_expr, plant.shutdown_cost_rs * w[plant.id, t])
    end

    # Deficit penalty (very high cost)
    for submarket in system.submarkets, t in periods
        add_to_expression!(cost_expr, obj.deficit_cost * deficit[submarket.id, t])
    end

    # Set objective
    @objective(model, Min, cost_expr)

    return model
end
```

**When to use:** Always. This is the standard JuMP pattern.

### Pattern 2: Two-Stage Pricing for Duals

**What:** Solve MILP for unit commitment, then fix integers and re-solve as LP to get duals.

**Why:**
- MILP solvers don't produce dual variables
- Power system marginal prices come from dual variables on energy balance constraints
- Water values come from duals on storage constraints
- Two-stage is standard practice in hydrothermal dispatch

**Implementation:**
```julia
# src/solvers/two_stage_pricing.jl

"""Two-stage solve: MILP for commitment, LP for duals."""
function solve_two_stage!(model::JuMP.Model, options::SolverOptions)

    # Stage 1: Solve MILP for unit commitment
    set_optimizer(model, options.milp_solver)
    optimize!(model)

    if termination_status(model) != OPTIMAL
        return SolverResult(
            status=termination_status(model),
            feasible=false,
            objective_value=NaN,
            solve_time_seconds=solve_time(model)
        )
    end

    milp_objective = objective_value(model)
    milp_time = solve_time(model)

    # Stage 2: Fix binary variables and re-solve as LP
    binary_vars = all_binary_variables(model)
    binary_values = value.(binary_vars)

    # Create LP model (same structure, fixed binaries)
    lp_model = copy(model)  # Deep copy to preserve MILP solution

    for (var, val) in zip(binary_vars, binary_values)
        unset_binary(lp_model[var])  # Convert to continuous
        fix(lp_model[var], val)       # Fix to MILP solution value
    end

    set_optimizer(lp_model, options.lp_solver)
    optimize!(lp_model)

    if termination_status(lp_model) != OPTIMAL
        @warn "LP stage failed, returning MILP solution without duals"
        return SolverResult(
            status=termination_status(model),
            feasible=true,
            objective_value=milp_objective,
            solve_time_seconds=milp_time,
            has_duals=false
        )
    end

    lp_time = solve_time(lp_model)

    return SolverResult(
        status=OPTIMAL,
        feasible=true,
        objective_value=milp_objective,  # Use MILP objective (correct cost)
        solve_time_seconds=milp_time + lp_time,
        has_duals=true,
        lp_model=lp_model  # Store for dual extraction
    )
end
```

**When to use:** When extracting marginal prices from unit commitment problems.

### Pattern 3: Solution Extraction via Type-Stable Functions

**What:** Extract primal and dual values into typed structs, not raw dictionaries.

**Why:**
- Type stability for performance
- Domain objects are easier to work with than `Dict{String, Vector{Float64}}`
- Enables validation (e.g., generation >= 0)

**Implementation:**
```julia
# src/solvers/solution_extraction.jl

"""Primal solution for thermal plants."""
struct ThermalSolution
    plant_id::String
    commitment::Vector{Bool}     # u[t]
    generation::Vector{Float64}  # g[t]
    startup::Vector{Bool}        # v[t]
    shutdown::Vector{Bool}       # w[t]
end

"""Extract thermal plant solutions."""
function extract_thermal_solution(model::JuMP.Model, plant::ConventionalThermal,
                                  periods::Vector{Int})
    u = model[:commitment]
    g = model[:generation]
    v = model[:startup]
    w = model[:shutdown]

    return ThermalSolution(
        plant_id=plant.id,
        commitment=[value(u[plant.id, t]) > 0.5 for t in periods],
        generation=[value(g[plant.id, t]) for t in periods],
        startup=[value(v[plant.id, t]) > 0.5 for t in periods],
        shutdown=[value(w[plant.id, t]) > 0.5 for t in periods]
    )
end

"""Dual solution: marginal prices."""
struct MarginalPrices
    submarket_id::String
    lmp::Vector{Float64}  # Locational marginal price [R$/MWh]
    periods::Vector{Int}
end

"""Extract marginal prices from energy balance duals."""
function extract_marginal_prices(lp_model::JuMP.Model, system::ElectricitySystem,
                                 periods::Vector{Int})
    energy_bal = lp_model[:energy_balance]

    prices = MarginalPrices[]
    for submarket in system.submarkets
        lmp = [dual(energy_bal[submarket.id, t]) for t in periods]
        push!(prices, MarginalPrices(submarket.id, lmp, periods))
    end

    return prices
end
```

**When to use:** Always. Prefer typed structs over raw dictionaries.

### Pattern 4: Solver Abstraction via Options Struct

**What:** Encapsulate solver selection and parameters in a configuration struct.

**Why:**
- Easy to switch solvers (HiGHS, Gurobi, CPLEX)
- Enables solver-specific tuning
- Supports two-stage pricing configuration

**Implementation:**
```julia
# src/solvers/solver_types.jl

"""Solver configuration options."""
Base.@kwdef struct SolverOptions
    # Solver selection
    milp_solver::Union{Type, Nothing} = Gurobi.Optimizer
    lp_solver::Union{Type, Nothing} = HiGHS.Optimizer

    # Two-stage pricing
    two_stage_pricing::Bool = true

    # Termination criteria
    time_limit_seconds::Float64 = 3600.0
    mip_gap::Float64 = 0.01  # 1% relative gap

    # Solver-specific parameters
    threads::Int = 4
    presolve::Bool = true

    # Output control
    verbose::Bool = false
    log_file::Union{String, Nothing} = nothing
end

"""Apply options to JuMP optimizer."""
function configure_optimizer!(model::JuMP.Model, options::SolverOptions,
                              solver_type::Type)
    set_optimizer(model, solver_type)

    # Generic parameters (most solvers support these)
    set_optimizer_attribute(model, "TimeLimit", options.time_limit_seconds)
    set_optimizer_attribute(model, "Threads", options.threads)

    # Solver-specific
    if solver_type == Gurobi.Optimizer
        set_optimizer_attribute(model, "MIPGap", options.mip_gap)
        set_optimizer_attribute(model, "Presolve", options.presolve ? 1 : 0)
        set_optimizer_attribute(model, "OutputFlag", options.verbose ? 1 : 0)
    elseif solver_type == HiGHS.Optimizer
        set_optimizer_attribute(model, "mip_rel_gap", options.mip_gap)
        set_optimizer_attribute(model, "presolve", options.presolve ? "on" : "off")
        set_optimizer_attribute(model, "log_to_console", options.verbose)
    end

    return model
end
```

**When to use:** Always. Parameterize solver configuration.

### Pattern 5: Constraint-Objective Separation

**What:** Objective function is NOT built by constraints. Separate concerns.

**Why:**
- Constraints enforce feasibility (g <= pmax)
- Objective encodes optimization goal (minimize cost)
- Mixing them breaks single responsibility principle
- Enables multiple objectives (cost, emissions, reliability) with same constraints

**Implementation:**
```julia
# WRONG: Constraint builds objective terms
function build!(model, system, constraint::ThermalUnitCommitmentConstraint)
    # ... add constraints ...

    # WRONG: Adding cost to objective here
    for plant in system.thermal_plants
        @objective(model, Min, sum(plant.fuel_cost * g[plant.id, t] for t in periods))
    end
end

# CORRECT: Constraint only adds constraints
function build!(model, system, constraint::ThermalUnitCommitmentConstraint)
    g = model[:generation]
    u = model[:commitment]

    for plant in system.thermal_plants, t in periods
        # Capacity limits
        @constraint(model, g[plant.id, t] <= plant.max_generation_mw * u[plant.id, t])
        @constraint(model, g[plant.id, t] >= plant.min_generation_mw * u[plant.id, t])
    end

    # No objective manipulation
end

# CORRECT: Objective builder constructs cost
function build!(model, system, obj::ProductionCostObjective, periods)
    g = model[:generation]

    cost_expr = sum(plant.fuel_cost_rsj_per_mwh * g[plant.id, t]
                    for plant in system.thermal_plants, t in periods)

    @objective(model, Min, cost_expr)
end
```

**When to use:** Always. Keep constraint and objective building separate.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Mutating Model After Solve

**What:** Modifying model structure after `optimize!()` is called.

**Why bad:**
- Invalidates solution
- Dual values become meaningless
- Solver state is undefined
- Hard to debug

**Instead:**
- Extract all values immediately after solve
- Store in immutable structs
- If you need to re-solve, create new model or reset properly

**Example:**
```julia
# BAD
optimize!(model)
obj = objective_value(model)
# Later...
@constraint(model, new_constraint)  # WRONG: invalidates solution
optimize!(model)  # Solution no longer valid

# GOOD
optimize!(model)
solution = extract_solution(model, system)  # Immutable snapshot
# If need to add constraint:
model2 = rebuild_model(system, new_constraints)
optimize!(model2)
```

### Anti-Pattern 2: Extracting Duals from MILP

**What:** Calling `dual()` on constraints in a MILP model.

**Why bad:**
- MILP solvers don't produce dual variables
- Will error or return garbage
- Must use two-stage pricing

**Instead:**
```julia
# BAD
set_optimizer(model, Gurobi.Optimizer)  # MILP solver
optimize!(model)
lmp = dual(model[:energy_balance])  # ERROR or meaningless

# GOOD
solution = solve_two_stage!(model, SolverOptions())
if solution.has_duals
    lmp = extract_marginal_prices(solution.lp_model, system, periods)
end
```

### Anti-Pattern 3: Dictionary-Based Solution Storage

**What:** Storing solutions as `Dict{String, Dict{Int, Float64}}`.

**Why bad:**
- Type instability (performance hit)
- No validation
- No clear schema
- Hard to export to CSV/JSON

**Instead:**
```julia
# BAD
solution = Dict{String, Any}()
solution["thermal"] = Dict{String, Dict{Int, Float64}}()
for plant in system.thermal_plants
    solution["thermal"][plant.id] = Dict(t => value(g[plant.id, t]) for t in periods)
end

# GOOD
thermal_solutions = [extract_thermal_solution(model, plant, periods)
                     for plant in system.thermal_plants]
```

### Anti-Pattern 4: Mixing Primal and Dual Extraction

**What:** Extracting duals from MILP model, primals from LP model.

**Why bad:**
- Primal values differ between MILP and LP (LP has relaxed binaries)
- Inconsistent solution
- Marginal prices won't match actual dispatch

**Instead:**
```julia
# Correct approach
milp_result = solve_milp!(model, options)
primals = extract_primal_values(model, system)  # From MILP

lp_model = fix_binaries_and_resolve(model, options)
duals = extract_dual_values(lp_model, system)  # From LP

# Both stored together in SolverResult
```

### Anti-Pattern 5: Rebuilding Model for Every Scenario

**What:** Recreating all variables/constraints when only data changes.

**Why bad:**
- Slow (model building is expensive)
- JuMP can update parameter values directly

**Instead:**
Use JuMP's parameter objects for data that varies across scenarios:
```julia
# GOOD: Use parameters for varying data
@variable(model, p_demand[t in periods])  # Parameter
@constraint(model, energy_bal[t in periods],
            sum(g[i,t] for i in plants) == p_demand[t])

# Update for new scenario
for t in periods
    set_value(p_demand[t], new_demand[t])
end
optimize!(model)  # No rebuilding needed
```

## Scalability Considerations

| Concern | Small System (10 plants, 24h) | Medium System (100 plants, 168h) | Large System (1000 plants, 168h) |
|---------|------------------------------|----------------------------------|----------------------------------|
| **Variables** | ~1,000 | ~100,000 | ~1,000,000 |
| **Constraints** | ~5,000 | ~500,000 | ~5,000,000 |
| **MILP Solve Time** | < 1 minute (HiGHS) | 5-30 minutes (Gurobi) | 1-4 hours (Gurobi, parallel) |
| **LP Solve Time** | < 1 second | 10-60 seconds | 2-10 minutes |
| **Memory** | < 100 MB | 1-4 GB | 8-32 GB |
| **Bottleneck** | None | MILP solve | MILP solve, model building |
| **Architecture Implications** | Simple pipeline | Two-stage pricing essential | Sparse matrices, lazy constraints, warm-start |

**Architectural guidelines by scale:**

**Small Systems (< 10K variables)**:
- Simple pipeline: build → solve → extract
- Any solver works (HiGHS sufficient)
- Two-stage pricing optional

**Medium Systems (10K-100K variables)**:
- Two-stage pricing required for marginal prices
- Commercial solver recommended (Gurobi, CPLEX)
- Sparse matrix construction
- Parallel solve (4-8 threads)

**Large Systems (> 100K variables)**:
- All medium-system practices plus:
- Lazy constraint generation (only add violated constraints)
- Warm-start from previous solve
- Decomposition methods (Benders, column generation)
- Solution pool management
- Model cloning for LP stage (avoid deep copy overhead)

## Integration with OpenDESSEM

### Current State Analysis

OpenDESSEM has:
- ✅ Entity layer (immutable structs)
- ✅ Variable manager (creates JuMP variables)
- ✅ Constraint system (7 constraint types with build!() pattern)
- ⚠️ Objective scaffold (ProductionCostObjective struct exists, build!() missing)
- ⚠️ Solver scaffolds (SolverResult, SolverOptions exist, solve!() missing)
- ⚠️ Analysis scaffolds (export functions exist, implementation incomplete)

### Recommended Build Order

**Phase 1: Complete Objective Builder** (1-2 days)
- Implement `build!(model, system, ProductionCostObjective, periods)`
- Cost terms: fuel, startup, shutdown, deficit penalty
- Test: verify objective function constructed correctly
- **Dependency**: Requires working VariableManager (DONE)

**Phase 2: Basic Solver Interface** (1-2 days)
- Implement `solve!(model, SolverOptions)` for single-stage solve
- Handle termination status, objective value, solve time
- Return SolverResult with status and timing
- Test: solve small system, verify solution quality
- **Dependency**: Requires working objective (Phase 1)

**Phase 3: Two-Stage Pricing** (2-3 days)
- Implement `solve_two_stage!(model, SolverOptions)`
- Fix binary variables, re-solve as LP
- Handle edge cases (MILP infeasible, LP solve fails)
- Test: verify duals extracted correctly
- **Dependency**: Requires basic solver (Phase 2)

**Phase 4: Solution Extraction** (2-3 days)
- Implement typed extraction functions:
  - `extract_thermal_solution(model, plant, periods)`
  - `extract_hydro_solution(model, plant, periods)`
  - `extract_marginal_prices(lp_model, system, periods)`
- Aggregate into system-wide solution struct
- Test: round-trip (build → solve → extract → validate)
- **Dependency**: Requires two-stage pricing (Phase 3)

**Phase 5: Analysis Export** (1-2 days)
- Implement CSV export for:
  - Generation schedule (plant x time)
  - Commitment schedule (plant x time)
  - Marginal prices (submarket x time)
  - Water values (reservoir x time)
- Implement JSON export for full solution
- Test: export → read → verify
- **Dependency**: Requires solution extraction (Phase 4)

**Total estimated timeline: 7-12 days** (depends on testing rigor and edge case handling)

### Integration Points with Existing Code

**Variables Module** (`src/variables/variable_manager.jl`):
```julia
# Objective builder reads from VariableManager
function build!(model, system, obj::ProductionCostObjective, periods)
    # Retrieve variables created by VariableManager
    g = model[:generation]
    u = model[:commitment]
    v = model[:startup]
    # ... use in objective expression
end
```

**Constraints Module** (`src/constraints/*.jl`):
```julia
# Constraints build BEFORE objective
function solve_workflow(system, periods, constraints, objective, options)
    model = Model()
    create_variables!(model, system, periods)

    # Build all constraints first
    for constraint in constraints
        build!(model, system, constraint)
    end

    # Objective last
    build!(model, system, objective, periods)

    # Now solve
    solution = solve!(model, options)
    return solution
end
```

**PowerModels Integration** (`src/integration/powermodels_adapter.jl`):
```julia
# Network constraints may create additional variables/constraints
# Objective builder must handle both:
# 1. OpenDESSEM native variables (g, u, etc.)
# 2. PowerModels variables (p, q, vm, va, etc.)

function build!(model, system, obj::ProductionCostObjective, periods)
    cost_expr = AffExpr(0.0)

    # Native generator costs
    if haskey(model, :generation)
        g = model[:generation]
        for plant in system.thermal_plants, t in periods
            add_to_expression!(cost_expr, plant.fuel_cost * g[plant.id, t])
        end
    end

    # PowerModels generator costs (if network-constrained)
    if haskey(model, :pg)  # PowerModels convention
        pg = model[:pg]
        for (gen_id, gen) in model[:pm_gens], t in periods
            add_to_expression!(cost_expr, gen.cost * pg[gen_id, t])
        end
    end

    @objective(model, Min, cost_expr)
end
```

## Validation Strategy

**Unit Tests** (each component in isolation):
```julia
# Test objective builder
@testset "ProductionCostObjective" begin
    system = create_test_system_3_plants()
    model = Model()
    create_variables!(model, system, 1:24)

    obj = ProductionCostObjective(deficit_cost=10000.0)
    build!(model, system, obj, 1:24)

    @test has_objective(model)
    @test objective_sense(model) == MIN_SENSE
    # Verify cost coefficients match plant data
end

# Test solver interface
@testset "Two-Stage Solver" begin
    model = create_small_uc_problem()
    options = SolverOptions(two_stage_pricing=true, time_limit_seconds=60.0)

    result = solve_two_stage!(model, options)

    @test result.status == OPTIMAL
    @test result.feasible
    @test result.has_duals
    @test result.objective_value > 0
end
```

**Integration Tests** (end-to-end workflows):
```julia
@testset "Full Dispatch Workflow" begin
    # Load test system
    system = load_ons_sample_system()
    periods = 1:168  # Weekly dispatch

    # Build model
    model = Model()
    create_variables!(model, system, periods)

    constraints = [
        EnergyBalanceConstraint(),
        ThermalUnitCommitmentConstraint(),
        HydroWaterBalanceConstraint(),
        RampConstraint(),
        NetworkConstraint()
    ]

    for c in constraints
        build!(model, system, c)
    end

    obj = ProductionCostObjective(deficit_cost=10000.0)
    build!(model, system, obj, periods)

    # Solve
    options = SolverOptions(
        milp_solver=HiGHS.Optimizer,
        lp_solver=HiGHS.Optimizer,
        two_stage_pricing=true,
        time_limit_seconds=600.0
    )

    result = solve_two_stage!(model, options)

    @test result.feasible
    @test result.has_duals

    # Extract solution
    thermal_sol = [extract_thermal_solution(result.lp_model, plant, periods)
                   for plant in system.thermal_plants]
    prices = extract_marginal_prices(result.lp_model, system, periods)

    # Validate solution
    @test all(s -> all(s.generation .>= 0), thermal_sol)
    @test all(p -> all(p.lmp .>= 0), prices)

    # Export
    export_to_csv(thermal_sol, prices, "test_output.csv")
    @test isfile("test_output.csv")
end
```

**Validation Tests** (compare with known solutions):
```julia
@testset "ONS Sample Case Validation" begin
    # Load official ONS DESSEM case
    system = load_ons_case("DS_ONS_102025_RV2D11")

    # Solve with OpenDESSEM
    result = run_dispatch(system, periods=1:48)

    # Load official ONS results
    ons_results = load_ons_results("DS_ONS_102025_RV2D11/results")

    # Compare (allow small tolerance due to solver differences)
    @test isapprox(result.objective_value, ons_results.total_cost, rtol=0.05)
    @test compare_generation_schedules(result, ons_results, rtol=0.02)
    @test compare_marginal_prices(result, ons_results, rtol=0.10)
end
```

## Confidence Assessment

| Area | Level | Rationale |
|------|-------|-----------|
| **Two-Stage Pricing** | HIGH | Standard method, well-documented in literature (Wood & Wollenberg, ONS technical notes), JuMP supports this natively |
| **Objective Builder Pattern** | HIGH | Follows JuMP best practices, consistent with OpenDESSEM's build!() constraint pattern |
| **Solution Extraction** | HIGH | Straightforward application of JuMP's value() and dual() functions, typed structs for safety |
| **Solver Abstraction** | MEDIUM | Options struct is standard, but solver-specific parameter mapping requires careful testing |
| **PowerModels Integration** | MEDIUM | PowerModels.jl variable naming conventions known, but integration with custom objective needs validation |
| **Scalability Estimates** | MEDIUM | Based on typical UC problem sizes, actual performance depends on constraint tightness and solver tuning |

## Sources

**Note on Research Method:**
This architecture document is based on established power systems optimization practices and JuMP.jl patterns from my training data (knowledge cutoff January 2025). I did not have access to web search, official documentation, or the ability to verify current best practices as of February 2026.

**Knowledge Sources (training data):**
- JuMP.jl documentation and best practices (circa 2024)
- Power systems optimization literature:
  - Wood, A.J., Wollenberg, B.F., Sheblé, G.B. "Power Generation, Operation, and Control" (standard UC formulations)
  - ONS technical documentation on DESSEM model (Brazilian system operator)
- PowerModels.jl integration patterns (circa 2024)
- Two-stage pricing methods (standard in unit commitment literature)

**Confidence Notes:**
- **HIGH confidence** areas: Core JuMP patterns, two-stage pricing method, objective/constraint separation principles
- **MEDIUM confidence** areas: Specific solver parameter names (may have changed), PowerModels integration details (version-dependent), exact performance characteristics (system-dependent)
- **Recommended validation**: Verify solver parameter names with current JuMP/HiGHS/Gurobi documentation, test PowerModels integration with actual network cases, benchmark on representative ONS cases

**For roadmap planning:** The architectural patterns described here are sound and stable (based on mathematical optimization fundamentals), but implementation details should be validated against current documentation during Phase 1-2 implementation.
