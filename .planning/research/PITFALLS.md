# MILP Hydrothermal Dispatch Solver Pipeline: Common Pitfalls

**Document Purpose**: Catalog common mistakes in MILP-based hydrothermal dispatch optimization to prevent bugs in OpenDESSEM solver implementation.

**Target Audience**: Developers working on TASK-007 (Objective Function), TASK-008 (Solver Interface), and validation tasks.

**Last Updated**: 2026-02-15

---

## 1. Objective Function Pitfalls

### 1.1 Missing or Incorrect Cost Terms

**Description**: Forgetting critical cost components or using wrong units/signs in the objective function.

**Common Mistakes**:
- **Fuel cost only, missing startup/shutdown**: Only including `c_fuel * g[i,t]` without `c_startup * v[i,t]` or `c_shutdown * w[i,t]`
- **Wrong sign for water value**: Using `+ water_value * s[i,t]` instead of `- water_value * s[i,T]` (water value should incentivize saving water for future)
- **Missing penalty terms**: No penalties for load shedding, deficit, or constraint violations
- **Unit confusion**: Mixing R$/MWh (fuel cost) with R$ (startup cost) without proper time conversion

**Warning Signs**:
- Thermal plants never start up (startup cost too high or missing)
- Hydro plants empty all reservoirs immediately (water value missing or wrong sign)
- Infeasible problems never detected (missing slack/penalty variables)
- Total cost off by orders of magnitude when comparing to DESSEM

**Prevention Strategy**:
```julia
# ✅ CORRECT: Complete objective with all terms
objective = @expression(model,
    # Thermal fuel cost (R$/MWh * MW * hours)
    sum(plant.fuel_cost * g[i,t] for i in thermal, t in periods) +
    # Thermal startup cost (R$ per event)
    sum(plant.startup_cost * v[i,t] for i in thermal, t in periods) +
    # Thermal shutdown cost (R$ per event)
    sum(plant.shutdown_cost * w[i,t] for i in thermal, t in periods) -
    # Hydro water value (maximize final storage, negative to minimize)
    sum(plant.water_value * s[i,T] for i in hydro) +
    # Load shedding penalty (high penalty to discourage)
    sum(PENALTY_SHEDDING * shed[t] for t in periods) +
    # Deficit penalty (even higher to prevent infeasibility)
    sum(PENALTY_DEFICIT * deficit[s,t] for s in submarkets, t in periods)
)
@objective(model, Min, objective)
```

**Phase to Address**: TASK-007 (Objective Function Builder)

**Current Status in Codebase**:
- ✅ `ProductionCostObjective` includes all major terms
- ⚠️ Water value applies to ALL periods, not just final period: `sum(water_value * s[i,t] for t)` instead of `water_value * s[i,T]`
- ⚠️ Missing inflow data (hardcoded to 0.0 in water balance)

### 1.2 Numerical Scaling Issues

**Description**: Cost coefficients spanning many orders of magnitude (R$ 10 vs R$ 10,000,000) cause solver numerical issues.

**Common Mistakes**:
- **Mixing small and large coefficients**: Fuel cost O(R$100/MWh) + Water value O(R$1,000,000/hm³)
- **No scaling applied**: Passing raw costs to solver without normalization
- **Inconsistent time units**: Hourly fuel costs mixed with daily water values

**Warning Signs**:
- Solver reports numerical difficulties or scaling warnings
- Dual values are unrealistic (PLD = R$ 0.0001 or R$ 1,000,000)
- Optimal solution changes drastically with tiny parameter changes
- Solver fails to converge despite feasible problem

**Prevention Strategy**:
```julia
# ✅ CORRECT: Scale large coefficients
const COST_SCALE = 1e-6  # Convert R$ to millions R$

objective = @expression(model,
    # All terms scaled to similar magnitude
    COST_SCALE * sum(plant.fuel_cost * g[i,t] for i in thermal, t in periods) +
    COST_SCALE * sum(plant.startup_cost * v[i,t] for i in thermal, t in periods) +
    COST_SCALE * sum(plant.water_value * s[i,T] for i in hydro) +
    COST_SCALE * sum(PENALTY_SHEDDING * shed[t] for t in periods)
)

# Remember to unscale objective value after solve!
real_cost = objective_value(model) / COST_SCALE
```

**Phase to Address**: TASK-007 (Objective Function Builder)

### 1.3 Time-Varying Cost Handling

**Description**: Failing to handle time-dependent fuel costs (e.g., peak vs off-peak pricing).

**Common Mistakes**:
- **Single fuel cost**: Using `plant.fuel_cost_rsj_per_mwh` for all periods when it should vary by time-of-day
- **Wrong indexing**: Using `fuel_cost[t]` instead of `fuel_cost[plant.id, t]` (mixing plant-specific and system-wide costs)

**Warning Signs**:
- Thermal generation doesn't respond to price signals (same generation pattern regardless of time)
- Comparison with DESSEM fails during peak hours

**Prevention Strategy**:
```julia
# ✅ CORRECT: Support time-varying costs
function get_fuel_cost(plant::ConventionalThermal, period::Int, time_varying_costs::Dict)
    if haskey(time_varying_costs, plant.id) && period <= length(time_varying_costs[plant.id])
        return time_varying_costs[plant.id][period]
    end
    return plant.fuel_cost_rsj_per_mwh  # Fallback to base cost
end

# In objective builder
for plant in thermal_plants
    for t in time_periods
        cost = get_fuel_cost(plant, t, objective.time_varying_fuel_costs)
        fuel_cost_expr += cost * g[idx, t]
    end
end
```

**Phase to Address**: TASK-007 (Objective Function Builder)

**Current Status in Codebase**: ✅ Already implemented in `production_cost.jl`

---

## 2. Solver Configuration Pitfalls

### 2.1 Tolerance Mismanagement

**Description**: Using default solver tolerances that are inappropriate for the problem scale.

**Common Mistakes**:
- **Too tight MIP gap**: Setting `mip_gap=1e-6` (0.0001%) for a R$ 100M problem → solver runs for hours
- **Too loose feasibility tolerance**: Using `feasibility_tol=1e-3` → infeasible solutions accepted
- **Inconsistent tolerances**: Primal tolerance ≠ dual tolerance → strange LP relaxation behavior

**Warning Signs**:
- Solver runs indefinitely despite "good enough" solution
- Constraints violated by small amounts (0.01 MW generation above capacity)
- MIP gap stuck at 0.1% for hours
- LP relaxation gives infeasible duals despite primal feasibility

**Prevention Strategy**:
```julia
# ✅ CORRECT: Set appropriate tolerances for problem scale
solver_options = SolverOptions(;
    # MIP gap: 0.5% is acceptable for operational scheduling
    mip_gap = 0.005,

    # Time limit: Don't run forever
    time_limit_seconds = 3600.0,  # 1 hour max

    # Solver-specific tolerances
    solver_specific = Dict(
        "primal_feasibility_tolerance" => 1e-6,  # Tight for constraint satisfaction
        "dual_feasibility_tolerance" => 1e-6,
        "mip_rel_gap" => 0.005,  # 0.5% relative gap
        "mip_abs_gap" => 1000.0  # R$ 1000 absolute gap (adjust based on total cost)
    )
)
```

**Phase to Address**: TASK-008 (Solver Interface)

**Current Status in Codebase**:
- ✅ `SolverOptions` struct exists with `mip_gap` field
- ⚠️ Default `mip_gap=0.01` (1%) may be too loose for validation
- ⚠️ No default absolute gap or feasibility tolerance settings

### 2.2 Time Limit Traps

**Description**: Setting time limits without checking solution quality at termination.

**Common Mistakes**:
- **Accepting TIME_LIMIT without checking gap**: Returning suboptimal solution with 50% MIP gap
- **No warm start after timeout**: Restarting from scratch instead of using previous solution
- **Wrong time accounting**: Using wall-clock time instead of CPU time for multi-threaded solves

**Warning Signs**:
- Solutions vary wildly between runs
- First run takes 60 seconds, second run takes 3600 seconds (time limit) but is worse
- Solver reports TIME_LIMIT but solution is 10% from bound

**Prevention Strategy**:
```julia
# ✅ CORRECT: Check solution quality after time limit
result = optimize!(model, system, HiGHS.Optimizer; options=solver_options)

if is_time_limit(result)
    if result.objective_bound !== nothing
        gap = abs(result.objective_value - result.objective_bound) / abs(result.objective_value)
        if gap > 0.05  # More than 5% from optimum
            @warn "Time limit reached with large MIP gap" gap=gap
            # Consider: Increase time limit, or use solution with caution
        end
    else
        @warn "Time limit reached but no bound available"
    end
end

# Only accept solution if gap is reasonable
if has_solution(result) && (is_optimal(result) ||
    (is_time_limit(result) && gap_is_acceptable(result)))
    # Extract solution
else
    error("No acceptable solution found within time limit")
end
```

**Phase to Address**: TASK-008 (Solver Interface)

**Current Status in Codebase**:
- ✅ `is_time_limit()` helper exists
- ⚠️ No automatic gap checking after TIME_LIMIT
- ⚠️ No warm start implementation

### 2.3 Thread Configuration Disasters

**Description**: Using all CPU cores for small problems or single thread for large problems.

**Common Mistakes**:
- **threads=1 for large problems**: Single-threaded solve takes 10x longer than necessary
- **threads=32 for tiny test**: Thread overhead dominates (10ms problem takes 100ms due to thread startup)
- **No thread affinity**: OS migrates threads between cores, destroying cache locality

**Warning Signs**:
- Small test problems slower than expected
- Large problems don't scale with cores (adding threads doesn't help)
- CPU utilization < 50% with threads=8

**Prevention Strategy**:
```julia
# ✅ CORRECT: Scale threads based on problem size
function recommend_threads(model::Model, system::ElectricitySystem)
    n_vars = num_variables(model)
    n_constraints = num_constraints(model)

    # Small problem: single thread avoids overhead
    if n_vars < 10_000
        return 1
    # Medium problem: 4 threads
    elseif n_vars < 50_000
        return 4
    # Large problem: use more cores but not all (leave some for OS)
    else
        return min(Sys.CPU_THREADS ÷ 2, 16)
    end
end

threads = recommend_threads(model, system)
solver_options = SolverOptions(threads=threads, verbose=true)
```

**Phase to Address**: TASK-008 (Solver Interface)

**Current Status in Codebase**:
- ⚠️ Default `threads=1` in `SolverOptions`
- ⚠️ No automatic thread recommendation

---

## 3. LP Relaxation / Dual Extraction Pitfalls

### 3.1 Extracting Duals from MIP

**Description**: Attempting to get dual values from a mixed-integer program (invalid).

**Common Mistakes**:
- **Calling dual() on MIP solution**: `dual(energy_balance_constraint)` on model with binary variables
- **No LP relaxation step**: Forgetting the two-stage procedure (UC → SCED)
- **Fixing commitment wrong**: Fixing `u[i,t]` but leaving `v[i,t]` and `w[i,t]` as binary

**Warning Signs**:
- Solver throws error: "Duals not available for MIP"
- Dual values are all zero or nonsensical
- LMP extraction fails silently, returns zeros

**Prevention Strategy**:
```julia
# ❌ WRONG: Extract duals from MIP
uc_result = optimize!(model, system, HiGHS.Optimizer)
lmp = dual(model[:energy_balance]["SE", 1])  # ERROR! Duals don't exist for MIP

# ✅ CORRECT: Two-stage approach
# Stage 1: Solve UC (MIP)
uc_result = optimize!(model, system, HiGHS.Optimizer)

# Stage 2: Fix commitment and solve SCED (LP)
sced_result = solve_sced_for_pricing(model, system, uc_result, HiGHS.Optimizer)

# NOW extract duals (from LP)
lmp = get_submarket_lmps(sced_result, "SE", 1:24)
```

**Phase to Address**: TASK-008 (Solver Interface - Two-Stage Pricing)

**Current Status in Codebase**:
- ✅ `solve_sced_for_pricing()` implemented
- ✅ `fix_commitment!()` fixes u, v, w variables
- ⚠️ Function is untested (scaffold only)

### 3.2 Degenerate Dual Values

**Description**: LP relaxation is degenerate (multiple optimal bases) leading to unstable or zero duals.

**Common Mistakes**:
- **Unbounded constraint**: Energy balance with no generation upper bound → infinite dual
- **Redundant constraints**: Two identical constraints → duals can be distributed arbitrarily
- **Poorly scaled problem**: Tiny coefficient (1e-10) in constraint → huge dual (1e10)

**Warning Signs**:
- Duals are exactly zero for critical constraints (energy balance dual = 0)
- Duals change dramatically with tiny problem changes
- Primal optimal but duals don't satisfy complementary slackness
- Solver reports "numerically unstable" during LP solve

**Prevention Strategy**:
```julia
# ✅ CORRECT: Check for degeneracy after LP solve
sced_result = solve_sced_for_pricing(model, system, uc_result, HiGHS.Optimizer)

if sced_result.has_duals
    # Check if duals are reasonable
    lmps = get_submarket_lmps(sced_result, "SE", 1:24)

    if any(lmp == 0.0 for lmp in lmps)
        @warn "Zero LMPs detected - possible degeneracy" submarkets="SE"
    end

    if any(abs(lmp) > 10_000.0 for lmp in lmps)
        @warn "Extreme LMPs detected - check scaling" max_lmp=maximum(abs.(lmps))
    end

    # Check dual feasibility (manually verify if needed)
    # reduced_cost = c - A' * dual should be non-negative for minimization
end
```

**Phase to Address**: TASK-008 (Solver Interface - Dual Extraction), Validation

**Current Status in Codebase**:
- ⚠️ No degeneracy checks in `extract_dual_values!()`
- ⚠️ No validation of dual feasibility

### 3.3 Wrong Constraint Sense for Duals

**Description**: Misinterpreting dual sign based on constraint type (≤, ≥, =).

**Common Mistakes**:
- **Energy balance dual sign**: For `generation - demand = 0`, dual is negative if generation < demand (shadow price of relaxing constraint)
- **Ignoring constraint normalization**: JuMP normalizes `g - d = 0` vs `d - g = 0` differently, affecting dual sign
- **Mixing sense in different solvers**: HiGHS, Gurobi, CPLEX may report duals with different sign conventions

**Warning Signs**:
- Negative LMPs when they should be positive (or vice versa)
- Dual values opposite sign from expected economic interpretation
- Different solvers give opposite-sign duals

**Prevention Strategy**:
```julia
# ✅ CORRECT: Document and test constraint sense
# Energy balance: generation = demand
# Dual interpretation: marginal cost of serving one additional MW of demand
# If constraint is: sum(generation) - demand = 0
#   → Dual is positive (increasing demand increases cost)
# If constraint is: demand - sum(generation) = 0
#   → Dual is negative (increasing demand increases cost, but constraint is "backwards")

# RECOMMENDATION: Always use standard form for energy balance
@constraint(model, energy_balance[s in submarkets, t in periods],
    sum(generation[i,t] for i in plants_in_submarket[s]) == demand[s,t]
)

# Then extract dual with expected sign
lmp = dual(energy_balance[s, t])
@assert lmp >= 0.0  # LMP should be non-negative in normal conditions
```

**Phase to Address**: Constraint Building (TASK-006 continuation), Validation

**Current Status in Codebase**:
- ⚠️ Submarket balance constraint not reviewed for sense consistency
- ⚠️ No automated tests for dual sign conventions

---

## 4. Hydro Modeling Pitfalls

### 4.1 Water Balance Unit Conversion Errors

**Description**: Mixing units (m³/s, hm³, MWh) without proper conversion factors.

**Common Mistakes**:
- **Forgetting time conversion**: `s[t] = s[t-1] + inflow - outflow` where `s` is in hm³ but `inflow/outflow` in m³/s
- **Missing 3.6 factor**: `1 m³/s * 3600 s/h = 3600 m³/h = 0.0036 hm³/h` (not 3.6!)
- **Confusing turbine flow and generation**: `q[i,t]` (m³/s) vs `gh[i,t]` (MW) related by production coefficient

**Warning Signs**:
- Water balance violated by large margins (1000 hm³ error)
- Reservoirs drain impossibly fast or slow
- Hydro generation doesn't match turbine flow (off by factor of 10 or 100)

**Prevention Strategy**:
```julia
# ✅ CORRECT: Explicit unit conversion with named constants
const M3S_TO_HM3_PER_HOUR = 0.0036  # 1 m³/s = 0.0036 hm³/h

# Water balance constraint
for plant in reservoir_hydro
    for t in 2:T
        inflow_hm3 = plant.inflow_m3s[t] * M3S_TO_HM3_PER_HOUR
        outflow_hm3 = q[i,t] * M3S_TO_HM3_PER_HOUR  # q in m³/s
        spill_hm3 = spill[i,t] * M3S_TO_HM3_PER_HOUR

        @constraint(model,
            s[i,t] == s[i,t-1] + inflow_hm3 - outflow_hm3 - spill_hm3
        )
    end
end

# Turbine flow to generation (production coefficient)
# gh[MW] = rho * g * H * q * eta / 1e6
# For simplicity: gh = prod_coef * q
for plant in hydro_plants
    for t in 1:T
        @constraint(model,
            gh[i,t] == plant.production_coefficient * q[i,t]
        )
    end
end
```

**Phase to Address**: Constraint Building (Hydro Water Balance)

**Current Status in Codebase**:
- ✅ `M3S_TO_HM3_PER_HOUR = 0.0036` defined in `hydro_water_balance.jl`
- ⚠️ Inflow hardcoded to 0.0 (major issue!)
- ⚠️ Production coefficient constraint not implemented

### 4.2 Cascade Delay Implementation Bugs

**Description**: Incorrectly modeling water travel time from upstream to downstream plants.

**Common Mistakes**:
- **Wrong delay direction**: Adding upstream outflow at `t` instead of `t + delay`
- **Delay applied to wrong plant**: Downstream plant uses its own outflow delay instead of upstream's
- **Negative time index**: `s[i, t-delay]` with `t=1, delay=2` → index out of bounds
- **Circular cascade**: Plant A downstream of B, B downstream of A → infinite loop

**Warning Signs**:
- Water appears instantly at downstream plant (no travel time)
- Index out of bounds errors during constraint building
- Cascade topology solver hangs or crashes
- Total system water volume not conserved

**Prevention Strategy**:
```julia
# ✅ CORRECT: Cascade with proper delay handling
function build_cascade_constraints!(model, system, time_periods)
    s = model[:s]
    q = model[:q]

    # Build topology map: downstream_id -> [upstream plants]
    upstream_map = Dict{String, Vector{Tuple{String, Int}}}()
    for plant in system.hydro_plants
        if plant.downstream_plant_id !== nothing
            if !haskey(upstream_map, plant.downstream_plant_id)
                upstream_map[plant.downstream_plant_id] = []
            end
            delay_hours = plant.travel_time_hours
            push!(upstream_map[plant.downstream_plant_id], (plant.id, delay_hours))
        end
    end

    # Add upstream inflow to downstream water balance
    for plant in system.hydro_plants
        if haskey(upstream_map, plant.id)
            downstream_idx = hydro_indices[plant.id]

            for t in time_periods
                # For each upstream plant, add its outflow with delay
                for (upstream_id, delay) in upstream_map[plant.id]
                    upstream_idx = hydro_indices[upstream_id]

                    # Only add if delayed time is within valid range
                    t_upstream = t - delay
                    if t_upstream >= 1
                        # Add to existing water balance constraint
                        # (Requires constraint to be built incrementally)
                        upstream_inflow = q[upstream_idx, t_upstream] * M3S_TO_HM3_PER_HOUR
                        # Modify s[downstream_idx, t] constraint to include this term
                    end
                end
            end
        end
    end
end
```

**Phase to Address**: Constraint Building (Hydro Water Balance - Cascade)

**Current Status in Codebase**:
- ⚠️ Cascade logic commented out in `hydro_water_balance.jl` (line 224-228)
- ⚠️ "Simplified version - full cascade requires topology traversal"
- **CRITICAL**: This is a known gap that must be addressed for validation

### 4.3 Hardcoded Zero Inflows

**Description**: Using `inflow = 0.0` in water balance instead of loading real data.

**Common Mistakes**:
- **No inflow data loader**: Assuming inflows will be "added later"
- **Wrong inflow source**: Using historical averages instead of forecasts
- **Missing spatial variation**: Same inflow for all plants in a river basin

**Warning Signs**:
- All reservoirs drain to minimum volume immediately
- Hydro generation is zero despite available capacity
- Water balance constraints are trivially satisfied
- Total cost dominated by thermal (no hydro contribution)

**Prevention Strategy**:
```julia
# ✅ CORRECT: Load inflow data properly
function load_inflow_data(system::ElectricitySystem, scenario_path::String)
    # Read inflow forecasts from DESSEM input files
    # For ONS format: prevs.dat, vazaolateral.csv, etc.
    inflows = Dict{String, Vector{Float64}}()  # plant_id => [inflow_m3s_per_period]

    # Parse file and populate inflows dict
    for plant in system.hydro_plants
        inflows[plant.id] = read_plant_inflows(scenario_path, plant.id)
    end

    return inflows
end

# Use in water balance constraint
inflows = load_inflow_data(system, scenario_path)
for plant in hydro_plants
    for t in time_periods
        inflow_hm3 = inflows[plant.id][t] * M3S_TO_HM3_PER_HOUR
        # ... rest of water balance
    end
end
```

**Phase to Address**: Data Loading (DESSEM Loader), Constraint Building

**Current Status in Codebase**:
- **CRITICAL ISSUE**: `inflow = 0.0` hardcoded in `hydro_water_balance.jl` (lines 204, 242, 257)
- ⚠️ No inflow data loader implemented
- **BLOCKER FOR VALIDATION**: Cannot match DESSEM without real inflow data

---

## 5. Validation Pitfalls

### 5.1 Apples-to-Oranges Comparison

**Description**: Comparing results with different input data, time resolution, or network models.

**Common Mistakes**:
- **Different time discretization**: OpenDESSEM hourly (168 periods) vs DESSEM half-hourly (336 periods)
- **Different network models**: OpenDESSEM using simplified bus model vs DESSEM full transmission
- **Different inflow scenarios**: OpenDESSEM using mean inflows vs DESSEM using stochastic inflows
- **Different reserve requirements**: Forgetting to include spinning reserve constraints in OpenDESSEM

**Warning Signs**:
- Total cost off by 20%+ (should be within 5%)
- Completely different dispatch patterns (thermal vs hydro mix)
- Different number of thermal startups
- PLD values in wrong range (R$ 50/MWh vs R$ 500/MWh)

**Prevention Strategy**:
```julia
# ✅ CORRECT: Validate input data parity first
function validate_inputs_match_dessem(
    opendessem_system::ElectricitySystem,
    dessem_case_path::String
)
    dessem_inputs = load_dessem_inputs(dessem_case_path)

    # Check dimensions match
    @assert length(opendessem_system.thermal_plants) == length(dessem_inputs.thermal_plants)
    @assert length(opendessem_system.hydro_plants) == length(dessem_inputs.hydro_plants)

    # Check key parameters match
    for (od_plant, dessem_plant) in zip(opendessem_system.thermal_plants, dessem_inputs.thermal_plants)
        @assert od_plant.capacity_mw ≈ dessem_plant.capacity_mw
        @assert od_plant.fuel_cost_rsj_per_mwh ≈ dessem_plant.fuel_cost
    end

    # Check time horizon matches
    @assert opendessem_time_periods == dessem_time_periods

    # Check inflows match
    for plant in opendessem_system.hydro_plants
        @assert opendessem_inflows[plant.id] ≈ dessem_inflows[plant.id]
    end

    @info "Input validation complete - all data matches DESSEM"
end
```

**Phase to Address**: Validation Framework (TASK-009+)

### 5.2 Tolerance Selection Mistakes

**Description**: Using wrong tolerance thresholds for validation (too tight or too loose).

**Common Mistakes**:
- **Absolute tolerance for large values**: Checking `abs(cost1 - cost2) < 1000` for R$ 100M costs (0.001% difference)
- **Relative tolerance for small values**: Checking `abs(gen1 - gen2) / gen1 < 0.05` when `gen1 = 0.1 MW` (5% of 0.1 is nothing)
- **No tolerance for discrete values**: Comparing integer commitment decisions with floating point tolerance

**Warning Signs**:
- Validation passes but results are obviously different
- Validation fails on tiny rounding errors
- Zero-valued variables fail relative tolerance checks

**Prevention Strategy**:
```julia
# ✅ CORRECT: Use appropriate tolerances for each metric
struct ValidationTolerances
    cost_relative::Float64         # 0.05 = 5%
    cost_absolute::Float64         # R$ 10,000
    generation_mw::Float64         # 1.0 MW
    storage_hm3::Float64          # 0.1 hm³
    dual_relative::Float64        # 0.10 = 10% (duals are less stable)
    commitment_exact::Bool        # true = must match exactly
end

function validate_result(
    opendessem_result::SolverResult,
    dessem_result::DessemResult,
    tolerances::ValidationTolerances
)
    # Total cost: use relative + absolute tolerance
    cost_diff = abs(opendessem_result.objective_value - dessem_result.total_cost)
    cost_rel_tol = tolerances.cost_relative * dessem_result.total_cost

    if cost_diff > max(tolerances.cost_absolute, cost_rel_tol)
        @warn "Cost validation failed" cost_diff=cost_diff threshold=max(tolerances.cost_absolute, cost_rel_tol)
        return false
    end

    # Generation: use absolute tolerance (MW)
    for (plant_id, t) in keys(dessem_result.thermal_generation)
        od_gen = opendessem_result.variables[:thermal_generation][(plant_id, t)]
        dessem_gen = dessem_result.thermal_generation[(plant_id, t)]

        if abs(od_gen - dessem_gen) > tolerances.generation_mw
            @warn "Generation mismatch" plant_id=plant_id t=t diff=abs(od_gen - dessem_gen)
            return false
        end
    end

    # Commitment: exact match if required
    if tolerances.commitment_exact
        for (plant_id, t) in keys(dessem_result.thermal_commitment)
            od_commit = round(opendessem_result.variables[:thermal_commitment][(plant_id, t)])
            dessem_commit = dessem_result.thermal_commitment[(plant_id, t)]

            if od_commit != dessem_commit
                @warn "Commitment mismatch" plant_id=plant_id t=t od=od_commit dessem=dessem_commit
                return false
            end
        end
    end

    return true
end
```

**Phase to Address**: Validation Framework (TASK-009+)

### 5.3 Edge Case Neglect

**Description**: Only testing "happy path" scenarios, missing corner cases that expose bugs.

**Common Mistakes**:
- **Only testing feasible cases**: Never testing infeasible load (load > total capacity)
- **Only testing middle-of-range values**: Never testing min/max storage, 0 MW generation
- **Only testing single-submarket**: Never testing interconnection limits
- **Only testing normal operation**: Never testing must-run units, forced outages

**Warning Signs**:
- Production code crashes on edge cases
- Solver returns nonsensical results for extreme inputs
- Validation passes on small test but fails on full SIN

**Prevention Strategy**:
```julia
# ✅ CORRECT: Test suite covers edge cases
@testset "Validation Edge Cases" begin
    @testset "Infeasible Load" begin
        # Load exceeds total capacity → should use deficit variable
        system = create_test_system()
        system.loads[1].demand_mw = 10 * system.total_capacity_mw

        result = solve_with_opendessem(system)
        @test has_solution(result)  # Should find solution with deficit
        @test result.variables[:deficit] > 0  # Deficit variable used
    end

    @testset "Zero Inflow" begin
        # All hydro inflows zero → should use only thermal
        system = create_test_system()
        inflows = zeros(length(system.hydro_plants), 168)

        result = solve_with_inflows(system, inflows)
        @test sum(result.variables[:hydro_generation]) == 0  # No hydro generation
        @test sum(result.variables[:thermal_generation]) ≈ sum(system.loads.demand_mw)
    end

    @testset "Maximum Storage" begin
        # Start all hydro at max volume → may spill
        system = create_test_system()
        for plant in system.hydro_plants
            plant.initial_volume_hm3 = plant.max_volume_hm3
        end

        result = solve_with_opendessem(system)
        @test has_solution(result)
        # Check if spillage occurs (expected for high initial storage + inflow)
    end

    @testset "Must-Run Units" begin
        # Must-run thermal plant → should be committed all periods
        system = create_test_system()
        system.thermal_plants[1].must_run = true

        result = solve_with_opendessem(system)
        commitment = result.variables[:thermal_commitment]
        @test all(commitment[(system.thermal_plants[1].id, t)] == 1.0 for t in 1:168)
    end
end
```

**Phase to Address**: Validation Framework (TASK-009+), Test Suite Development

---

## 6. Performance Pitfalls

### 6.1 Model Size Explosion

**Description**: Problem size grows uncontrollably due to unnecessary variables or constraints.

**Common Mistakes**:
- **Creating variables for infeasible combinations**: Variables for thermal plant at every bus (should only be at plant's bus)
- **Dense constraint matrix**: Every plant connected to every bus in network constraints
- **No variable aggregation**: Creating hourly variables for 7-day horizon when daily aggregation would work
- **Unused variables**: Creating pumping variables for non-pumped-storage plants

**Warning Signs**:
- Model has 500k variables for small test system (should be ~10k)
- Constraint matrix uses >8 GB RAM
- Time to build model >> time to solve
- Solver reports memory issues before optimization starts

**Prevention Strategy**:
```julia
# ✅ CORRECT: Sparse variable creation based on actual entities
function create_thermal_variables!(model::Model, system::ElectricitySystem, time_periods)
    n_thermal = length(system.thermal_plants)
    n_periods = length(time_periods)

    # Only create variables for plants that exist
    @variable(model, g[1:n_thermal, 1:n_periods] >= 0)
    @variable(model, u[1:n_thermal, 1:n_periods], Bin)
    @variable(model, v[1:n_thermal, 1:n_periods], Bin)
    @variable(model, w[1:n_thermal, 1:n_periods], Bin)

    # DON'T create: g[1:n_plants, 1:n_buses, 1:n_periods] (dense matrix)
end

function create_hydro_variables!(model::Model, system::ElectricitySystem, time_periods)
    n_hydro = length(system.hydro_plants)
    n_periods = length(time_periods)

    # Create storage variables only for reservoir plants
    reservoir_indices = [i for (i, p) in enumerate(system.hydro_plants) if p isa ReservoirHydro]
    @variable(model, s[reservoir_indices, 1:n_periods] >= 0)

    # All hydro plants have outflow and generation
    @variable(model, q[1:n_hydro, 1:n_periods] >= 0)
    @variable(model, gh[1:n_hydro, 1:n_periods] >= 0)

    # Pumping variables only for pumped storage
    pumped_indices = [i for (i, p) in enumerate(system.hydro_plants) if p isa PumpedStorageHydro]
    if !isempty(pumped_indices)
        @variable(model, pump[pumped_indices, 1:n_periods] >= 0)
    end
end
```

**Phase to Address**: Variable Manager (already implemented), Constraint Building

**Current Status in Codebase**:
- ✅ Variable manager creates sparse variables
- ⚠️ No variable statistics logging (hard to detect bloat)

### 6.2 Constraint Generation Order

**Description**: Adding constraints in wrong order causes inefficient constraint matrix structure.

**Common Mistakes**:
- **Random constraint order**: Adding constraints as encountered in entity list (random order)
- **No constraint grouping**: Mixing thermal, hydro, network constraints → poor matrix structure
- **No presorting**: Not sorting entities by ID or bus before creating constraints

**Warning Signs**:
- Presolve takes very long (>10% of total solve time)
- Different constraint ordering gives different solve times
- Solver reports "matrix reordering" during presolve

**Prevention Strategy**:
```julia
# ✅ CORRECT: Add constraints in structured order
function build_all_constraints!(model::Model, system::ElectricitySystem)
    # 1. Network constraints first (define topology)
    build_network_constraints!(model, system)

    # 2. Thermal constraints (sorted by plant ID for consistency)
    thermal_sorted = sort(system.thermal_plants, by=p->p.id)
    build_thermal_constraints!(model, thermal_sorted)

    # 3. Hydro constraints (sorted by cascade topology: upstream first)
    hydro_sorted = topological_sort(system.hydro_plants)
    build_hydro_constraints!(model, hydro_sorted)

    # 4. Energy balance constraints (tie everything together)
    build_energy_balance_constraints!(model, system)

    # 5. Reserve constraints (if any)
    build_reserve_constraints!(model, system)
end
```

**Phase to Address**: Constraint Building (all constraint types)

### 6.3 Variable Bounds Neglect

**Description**: Not setting tight variable bounds, forcing solver to explore infeasible region.

**Common Mistakes**:
- **No upper bound**: `@variable(model, g[i,t] >= 0)` without `<= plant.max_generation_mw`
- **Trivial bound**: `s[i,t] >= 0` without `<= plant.max_volume_hm3` (bound from constraint, not variable declaration)
- **Time-varying bounds ignored**: Using constant capacity instead of time-varying available capacity

**Warning Signs**:
- Solver explores many branch-and-bound nodes with infeasible solutions
- LP relaxation bound is very loose (100x from integer solution)
- Adding explicit bounds speeds up solve by 10x

**Prevention Strategy**:
```julia
# ✅ CORRECT: Set tight bounds on variable declaration
function create_thermal_variables!(model::Model, system::ElectricitySystem, time_periods)
    n_thermal = length(system.thermal_plants)
    n_periods = length(time_periods)

    # Generation with plant-specific bounds
    @variable(model, 0 <= g[i=1:n_thermal, t=1:n_periods] <= system.thermal_plants[i].max_generation_mw)

    # Commitment (binary is already bounded 0-1)
    @variable(model, u[1:n_thermal, 1:n_periods], Bin)

    # Startup/shutdown (binary)
    @variable(model, v[1:n_thermal, 1:n_periods], Bin)
    @variable(model, w[1:n_thermal, 1:n_periods], Bin)
end

function create_hydro_variables!(model::Model, system::ElectricitySystem, time_periods)
    # Storage with reservoir-specific bounds
    for (i, plant) in enumerate(system.hydro_plants)
        if plant isa ReservoirHydro
            @variable(model, plant.min_volume_hm3 <= s[i, t] <= plant.max_volume_hm3 for t in time_periods)
        end
    end

    # Outflow with physical bounds
    @variable(model, 0 <= q[i=1:n_hydro, t=1:n_periods] <= system.hydro_plants[i].max_outflow_m3s)
end
```

**Phase to Address**: Variable Manager

**Current Status in Codebase**:
- ⚠️ Variable manager does not set upper bounds on variables
- ⚠️ Bounds enforced via constraints instead (less efficient)

---

## 7. Integration Pitfalls

### 7.1 PowerModels Coupling Issues

**Description**: Incorrectly integrating PowerModels.jl for network-constrained dispatch.

**Common Mistakes**:
- **Validate-only mode**: PowerModels constraints computed but not added to model
- **Double-counting network constraints**: Adding both manual bus balance and PowerModels power flow
- **Per-unit conversion errors**: Mixing SI units (MW) with per-unit values
- **Missing baseMVA**: Forgetting to set base power for per-unit conversion

**Warning Signs**:
- Network constraints "exist" but are never binding
- Line flows violate thermal limits but solver doesn't care
- Voltage magnitudes outside limits in solution
- Bus angles unconstrained (all zero)

**Prevention Strategy**:
```julia
# ✅ CORRECT: Properly integrate PowerModels
function integrate_powermodels!(model::Model, system::ElectricitySystem, time_periods)
    # Convert OpenDESSEM system to PowerModels format
    pm_data = convert_to_powermodel(system)

    # Set baseMVA for per-unit conversion
    pm_data["baseMVA"] = 100.0

    # Instantiate PowerModels formulation
    pm_model = PowerModels.instantiate_model(
        pm_data,
        PowerModels.ACPPowerModel,  # Or DCPPowerModel for speed
        PowerModels.build_opf  # Optimal power flow formulation
    )

    # **CRITICAL**: Actually add PowerModels constraints to JuMP model
    # NOT just validate!
    PowerModels.add_constraints!(model, pm_model)

    # Link OpenDESSEM generation variables to PowerModels
    for plant in system.thermal_plants
        bus_idx = pm_data["bus_map"][plant.bus_id]
        gen_idx = pm_data["gen_map"][plant.id]

        for t in time_periods
            # Link: PowerModels gen[g,t] == OpenDESSEM g[i,t]
            @constraint(model, pm_model[:gen][gen_idx, t] == model[:g][i, t])
        end
    end
end
```

**Phase to Address**: Integration Layer (PowerModels Adapter), Constraint Building

**Current Status in Codebase**:
- ⚠️ PowerModels adapter exists but validation-only noted in CLAUDE.md
- ⚠️ Network constraints "validate-only (not applied to model)"
- **CRITICAL**: This is a known gap

### 7.2 Multi-Solver Compatibility

**Description**: Code works with HiGHS but fails with Gurobi/CPLEX due to solver-specific quirks.

**Common Mistakes**:
- **HiGHS-specific options**: Using `MOI.RawParameter("hihs_solver", "simplex")` that doesn't exist in Gurobi
- **Assuming feature availability**: Expecting `objective_bound()` to work (not all LP solvers provide this)
- **Different binary relaxation**: HiGHS vs Gurobi handle `unset_binary()` differently
- **Silent failures**: Not checking return codes from solver-specific calls

**Warning Signs**:
- Tests pass with HiGHS but fail with Gurobi
- Solver options silently ignored (no error, no warning)
- Performance drastically different between solvers (10x slower)

**Prevention Strategy**:
```julia
# ✅ CORRECT: Write solver-agnostic code
function apply_solver_options!(model::Model, options::SolverOptions, solver_type::SolverType)
    # Generic MOI options (work with all solvers)
    if !options.verbose
        MOI.set(model, MOI.Silent(), true)
    end

    if options.time_limit_seconds !== nothing
        MOI.set(model, MOI.TimeLimitSec(), options.time_limit_seconds)
    end

    if options.threads > 1
        MOI.set(model, MOI.NumberOfThreads(), options.threads)
    end

    # Solver-specific options with error handling
    for (key, value) in options.solver_specific
        try
            if solver_type == HIGHS
                if key == "presolve"
                    MOI.set(model, MOI.RawParameter("presolve"), value ? "on" : "off")
                else
                    MOI.set(model, MOI.RawParameter(key), value)
                end
            elseif solver_type == GUROBI
                MOI.set(model, MOI.RawParameter(key), value)
            elseif solver_type == CPLEX
                MOI.set(model, MOI.RawParameter(key), value)
            end
        catch e
            @warn "Could not set solver option" key=key value=value error=e
            # Don't fail - just warn and continue
        end
    end
end

# Test with multiple solvers
@testset "Multi-Solver Compatibility" begin
    for solver in [HIGHS, GUROBI, CPLEX]
        @testset "$(solver)" begin
            model = build_test_model(system)
            optimizer = get_solver_optimizer(solver)
            result = optimize!(model, system, optimizer)
            @test has_solution(result)
            @test is_optimal(result) || is_time_limit(result)
        end
    end
end
```

**Phase to Address**: Solver Interface (TASK-008)

**Current Status in Codebase**:
- ✅ Multi-solver support scaffolded
- ⚠️ Solver type auto-detection commented: "Default to HIGHS if we can't determine the type"
- ⚠️ Not tested with Gurobi/CPLEX

### 7.3 JuMP API Pattern Violations

**Description**: Using deprecated JuMP patterns or violating JuMP best practices.

**Common Mistakes**:
- **Modifying model after solve**: Changing objective/constraints after `optimize!()` without rebuilding
- **Accessing internal structures**: Using `model.obj_dict[:var]` instead of `model[:var]`
- **Not using object_dictionary()**: Directly accessing JuMP internals that may change
- **Inefficient constraint building**: Adding constraints one-by-one instead of vectorized

**Warning Signs**:
- JuMP deprecation warnings in logs
- Code breaks with JuMP version updates
- Slow constraint building (100+ constraints/second instead of 10,000+/second)

**Prevention Strategy**:
```julia
# ✅ CORRECT: Follow JuMP best practices

# 1. Use object_dictionary() for accessing model objects
obj_dict = object_dictionary(model)
if haskey(obj_dict, :g)
    g = model[:g]  # Preferred access pattern
end

# 2. Vectorized constraint building (fast)
@constraint(model, energy_balance[s in submarkets, t in time_periods],
    sum(g[i,t] for i in thermal_in_submarket[s]) +
    sum(gh[j,t] for j in hydro_in_submarket[s]) ==
    demand[s,t]
)

# 3. Don't modify model after solve (rebuild instead)
result1 = optimize!(model, system, optimizer)
# If you need to change objective, create new model or reset:
empty!(model)  # Clear all variables/constraints
# Rebuild from scratch

# 4. Store model metadata properly
model[:thermal_indices] = thermal_indices  # Store in model's object dictionary
model[:time_periods] = time_periods  # Not as global variable

# 5. Use proper constraint references for dual extraction
energy_balance_ref = model[:energy_balance]
dual_value = dual(energy_balance_ref["SE", 1])  # Access by key
```

**Phase to Address**: All modules (ongoing code review)

---

## Summary: Priority Checklist for Development

### Phase 1: TASK-007 (Objective Function Builder)
- [ ] Verify water value sign and application (final period only?)
- [ ] Implement numerical scaling for large coefficients
- [ ] Add cost component breakdown validation
- [ ] Document expected cost magnitudes for Brazilian SIN

### Phase 2: TASK-008 (Solver Interface)
- [ ] Implement MIP gap checking after TIME_LIMIT
- [ ] Add automatic thread recommendation based on problem size
- [ ] Test two-stage pricing (UC → SCED → Dual extraction)
- [ ] Validate dual sign conventions for energy balance constraints
- [ ] Test with multiple solvers (HiGHS, Gurobi, CPLEX)

### Phase 3: Hydro Modeling (Critical for Validation)
- [ ] **BLOCKER**: Load real inflow data (remove hardcoded 0.0)
- [ ] Implement cascade water delays properly (topology traversal)
- [ ] Add production coefficient constraints (turbine flow → generation)
- [ ] Verify unit conversions (m³/s ↔ hm³)

### Phase 4: PowerModels Integration
- [ ] **BLOCKER**: Change PowerModels from "validate-only" to "apply to model"
- [ ] Add proper constraint linking (gen variables)
- [ ] Test network-constrained dispatch

### Phase 5: Validation Framework
- [ ] Implement input data parity checker (OpenDESSEM vs DESSEM)
- [ ] Define appropriate validation tolerances (relative + absolute)
- [ ] Create edge case test suite
- [ ] Document expected differences (time discretization, network model)

---

## References

**DESSEM Documentation**:
- ONS, "Manual do Usuário DESSEM", 2024
- ONS, "Formato de Arquivos do DESSEM", 2024

**Optimization Best Practices**:
- Bixby, R. E., "Solving Real-World Linear Programs: A Decade and More of Progress", Operations Research, 2002
- Mittelmann, H., "Decision Tree for Optimization Software" (http://plato.asu.edu/guide.html)

**JuMP Documentation**:
- JuMP.jl User Manual: https://jump.dev/JuMP.jl/stable/
- MathOptInterface.jl Documentation: https://jump.dev/MathOptInterface.jl/stable/

**Power System Optimization**:
- Wood, A. J., Wollenberg, B. F., "Power Generation, Operation, and Control", 3rd Edition
- Grigg, C., et al., "The IEEE Reliability Test System-1996", IEEE Transactions on Power Systems, 1999

---

**Document Version**: 1.0
**Last Updated**: 2026-02-15
**Maintained By**: OpenDESSEM Development Team
