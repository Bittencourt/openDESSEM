# Stack Research: JuMP-Based MILP Hydrothermal Dispatch Solver

**Project**: OpenDESSEM
**Research Date**: 2026-02-15
**Focus**: Completing solver pipeline, dual extraction, solution export, and validation

---

## 1. Recommended Stack Overview

This stack is designed for a production-grade hydrothermal dispatch optimizer targeting the Brazilian SIN (158 hydro, 109 thermal, 6450 buses, 50k-100k variables).

### Core Dependencies (Already in Project.toml)

| Component | Version | Status | Confidence |
|-----------|---------|--------|------------|
| JuMP.jl | 1.23+ | ✅ Active | **HIGH** |
| MathOptInterface.jl | 1.31+ | ✅ Active | **HIGH** |
| HiGHS.jl | 1.9+ | ✅ Active | **HIGH** |
| CSV.jl | 0.10+ | ✅ Active | **HIGH** |
| DataFrames.jl | 1.6+ | ✅ Active | **HIGH** |
| JSON3.jl | 1.14+ | ✅ Active | **HIGH** |
| LibPQ.jl | 1.18+ | ✅ Active | **HIGH** |

### Optional Solver Dependencies (Lazy-Loaded)

| Component | Version | Use Case | Confidence |
|-----------|---------|----------|------------|
| Gurobi.jl | 1.3+ | Commercial MILP (fastest) | **HIGH** |
| CPLEX.jl | 1.0+ | Commercial MILP (IBM) | **MEDIUM** |
| GLPK.jl | 1.2+ | Open-source fallback | **LOW** |

### Validation & Testing

| Component | Version | Purpose | Confidence |
|-----------|---------|---------|------------|
| Test.jl | stdlib | Unit/integration tests | **HIGH** |
| Statistics.jl | stdlib | MAE, RMSE, MAPE metrics | **HIGH** |
| StatsBase.jl | 0.34+ | Advanced statistics | **MEDIUM** |

---

## 2. Solver Pipeline Stack

### 2.1 Solver Configuration Best Practices

**Current Implementation**: `/src/solvers/solver_interface.jl` (lines 56-128)

#### Recommended Pattern (Already Implemented)

```julia
# Use MOI.RawParameter for solver-specific options
MOI.set(model, MOI.RawParameter("parameter_name"), value)

# Standard MOI attributes (cross-solver compatibility)
MOI.set(model, MOI.Silent(), true)
MOI.set(model, MOI.TimeLimitSec(), 3600.0)
MOI.set(model, MOI.NumberOfThreads(), 8)
MOI.set(model, MOI.RelativeGapTolerance(), 0.01)
```

#### HiGHS-Specific Configuration (Primary Solver)

**Status**: ✅ Implemented in `apply_solver_options!`

```julia
# Recommended settings for large-scale hydrothermal dispatch
options = Dict(
    # Presolve (critical for large problems)
    "presolve" => "on",  # Reduces problem size
    "presolve_passes" => 10,  # More aggressive reduction

    # MIP solver method
    "simplex_strategy" => 4,  # Dual simplex (best for LP relaxation)

    # Parallel settings
    "threads" => 8,  # Match available CPU cores
    "parallel" => "on",

    # Tolerances
    "primal_feasibility_tolerance" => 1e-7,
    "dual_feasibility_tolerance" => 1e-7,
    "mip_rel_gap" => 0.01,  # 1% optimality gap acceptable

    # Time limits
    "time_limit" => 3600.0,  # 1 hour for UC

    # Output control
    "log_to_console" => false,
    "log_file" => "highs.log"
)
```

**Rationale**: HiGHS 1.9+ has excellent LP/MIP performance and is free. It's the best default choice.

#### Gurobi Configuration (Optional, for Speed)

```julia
# Gurobi excels at MILP with these settings
options = Dict(
    # Method selection
    "Method" => 2,  # Barrier for LP relaxation
    "Crossover" => 1,  # Crossover to basic solution (for duals)

    # MIP settings
    "MIPGap" => 0.01,
    "MIPFocus" => 1,  # Focus on finding feasible solutions
    "Cuts" => 2,  # Moderate cut generation

    # Parallel
    "Threads" => 8,

    # Presolve
    "Presolve" => 2,  # Aggressive
    "PreDual" => 1,  # Enable primal/dual presolve reductions

    # Tolerances
    "FeasibilityTol" => 1e-6,
    "OptimalityTol" => 1e-6,

    # Time limit
    "TimeLimit" => 3600.0
)
```

**Rationale**: Gurobi is 3-5x faster than HiGHS on large MILP but requires license (~$50k/year).

#### CPLEX Configuration (Optional, IBM Ecosystem)

```julia
# CPLEX settings similar to Gurobi
options = Dict(
    "CPXPARAM_LPMethod" => 4,  # Barrier
    "CPXPARAM_MIP_Tolerances_MIPGap" => 0.01,
    "CPXPARAM_Threads" => 8,
    "CPXPARAM_Preprocessing_Presolve" => 1,
    "CPXPARAM_TimeLimit" => 3600.0
)
```

**Rationale**: Similar performance to Gurobi, preferred if already in IBM ecosystem.

### 2.2 LP Relaxation for Dual Extraction

**Current Implementation**: `/src/solvers/solver_interface.jl` (lines 186-211)

#### Two Approaches

##### Approach 1: Manual Binary Unset (✅ Implemented, RECOMMENDED)

```julia
# Current implementation in solver_interface.jl
if options.lp_relaxation
    binary_vars = VariableRef[]
    integer_vars = VariableRef[]

    for var in all_variables(model)
        if is_binary(var)
            push!(binary_vars, var)
            unset_binary(var)  # Relax to [0, 1]
        elseif is_integer(var)
            push!(integer_vars, var)
            unset_integer(var)  # Relax to continuous
        end
    end
end

# Solve LP
JuMP.optimize!(model)

# Restore integrality
for var in binary_vars
    set_binary(var)
end
for var in integer_vars
    set_integer(var)
end
```

**Pros**:
- Full control over relaxation
- Can selectively relax only some variables
- Works across all solvers
- **Status**: ✅ Already implemented

**Cons**:
- Must manually restore integrality
- Slightly more code

##### Approach 2: JuMP.relax_integrality (Alternative, NOT Implemented)

```julia
# Alternative approach (simpler but less flexible)
relaxed_model = JuMP.relax_integrality(model)
set_optimizer(relaxed_model, HiGHS.Optimizer)
JuMP.optimize!(relaxed_model)

# Extract duals from relaxed_model
duals = JuMP.dual.(constraints)
```

**Pros**:
- One-line relaxation
- Cleaner code
- Model copy automatically created

**Cons**:
- Creates full model copy (memory overhead)
- Less control over what gets relaxed
- Cannot restore integrality in original model

**Recommendation**: Keep current manual approach. It's more flexible and memory-efficient.

### 2.3 Two-Stage Pricing for LMP Calculation

**Current Implementation**: `/src/solvers/two_stage_pricing.jl` (✅ EXCELLENT)

#### Industry-Standard Pattern (Already Implemented)

```julia
# Stage 1: Solve Unit Commitment (MIP)
uc_result = optimize!(model, system, HiGHS.Optimizer;
    options=SolverOptions(
        time_limit_seconds=3600,
        mip_gap=0.01,
        threads=8
    ))

# Stage 2: Fix commitments and solve SCED (LP) for LMPs
sced_result = solve_sced_for_pricing(
    model,
    system,
    uc_result,
    HiGHS.Optimizer;
    options=SolverOptions(threads=8)
)

# Extract valid dual variables (LMPs)
lmps = get_submarket_lmps(sced_result, "SE", 1:24)
```

**Rationale**: This is the correct approach used by all major ISO markets:
- PJM: SCUC → SCED (exactly this pattern)
- MISO: DAM → SCED (same)
- CAISO: IFM → RTD (same)
- ERCOT: DAM → SCED (same)

**Key Implementation Details** (Already Correct):

1. **Model Copying**: Line 234 uses `JuMP.copy_model()` to preserve original
2. **Binary Fixing**: Lines 111-123 fix binary variables to rounded values
3. **Constraint Preservation**: Lines 258-273 rebuild constraint dictionaries
4. **Dual Extraction**: Lines 288-328 extract dual values from LP

**No Changes Needed**: This implementation is production-ready.

### 2.4 MathOptInterface Patterns for Multi-Solver Support

**Current Implementation**: ✅ Correct use of MOI attributes

#### Key MOI Attributes Used

```julia
# Termination status (standardized across solvers)
status = MOI.termination_status(model)  # Returns MOI.TerminationStatusCode

# Primal status
primal_status = MOI.primal_status(model)

# Dual status (LP only)
dual_status = MOI.dual_status(model)

# Objective value
obj = MOI.objective_value(model)

# Objective bound (MIP only)
bound = MOI.objective_bound(model)

# Node count (MIP only)
nodes = MOI.node_count(model)
```

**Recommendation**: Current implementation is correct. These MOI attributes work across all solvers.

#### Solver Detection Pattern

```julia
# Detect solver from optimizer factory (for solver-specific handling)
optimizer_type = typeof(optimizer_factory)

if optimizer_type <: HiGHS.Optimizer
    # HiGHS-specific options
elseif optimizer_type <: Gurobi.Optimizer
    # Gurobi-specific options
elseif optimizer_type <: CPLEX.Optimizer
    # CPLEX-specific options
end
```

**Status**: Partially implemented (lines 179-184 default to HIGHS). Could improve detection.

---

## 3. Solution Export Stack

### 3.1 JuMP Solution Extraction at Scale

**Current Implementation**: `/src/solvers/solution_extraction.jl` (✅ Efficient)

#### Extraction Pattern (Already Optimal)

```julia
# Efficient extraction for large-scale problems
function extract_solution_values!(result, model, system, time_periods)
    # Pre-allocate dictionary
    thermal_gen = Dict{Tuple{String,Int},Float64}()

    # Iterate only over existing plants (sparse extraction)
    for plant in system.thermal_plants
        idx = thermal_indices[plant.id]
        for t in time_periods
            # Extract value using JuMP.value()
            val = value(model[:g][idx, t])
            thermal_gen[(plant.id, t)] = val
        end
    end

    result.variables[:thermal_generation] = thermal_gen
end
```

**Key Performance Features** (Already Implemented):

1. **Sparse Extraction**: Only extract existing variables (lines 56-69)
2. **Pre-indexed Access**: Use plant indices for O(1) lookup
3. **Batched Storage**: Store in Dict for efficient serialization
4. **Lazy Evaluation**: Only extract when requested

**Performance Estimate**:
- 50k variables: ~0.5 seconds
- 100k variables: ~1.0 seconds
- Scales linearly with variable count

**No Changes Needed**: Current implementation is efficient.

### 3.2 Export Format Libraries

**Current Implementation**: `/src/analysis/solution_exporter.jl` (✅ Complete)

#### CSV.jl (✅ Implemented)

**Version**: 0.10.14+
**Use Case**: Spreadsheet analysis, time series plots

```julia
# Wide format (plant × time)
df = DataFrame(
    plant_id = ["T_SE_001"],
    t_1 = [150.0],
    t_2 = [200.0],
    # ... t_24
)
CSV.write("thermal_generation.csv", df)
```

**Pros**:
- Fast write speed (~50 MB/s)
- Excel-compatible
- Human-readable

**Cons**:
- Not ideal for sparse data
- Wide format can be unwieldy for many time periods

**Recommendation**: ✅ Keep for analysis workflows. Already optimal.

#### JSON3.jl (✅ Implemented)

**Version**: 1.14+
**Use Case**: Web APIs, JavaScript visualization

```julia
# Nested structure (plant → time series)
json_data = Dict(
    "thermal_generation" => Dict(
        "T_SE_001" => [150.0, 200.0, ..., 180.0],
        "T_SE_002" => [300.0, 320.0, ..., 310.0]
    )
)
JSON3.write("solution.json", json_data)
```

**Pros**:
- Structured format
- Efficient for nested data
- Standard for web APIs

**Cons**:
- Larger file size than binary formats
- Parsing overhead

**Recommendation**: ✅ Keep for API integration. Already optimal.

#### DataFrames.jl (✅ Implemented)

**Version**: 1.6+
**Use Case**: Internal data manipulation before export

```julia
# Long format (normalized schema)
df = DataFrame(
    plant_id = ["T_SE_001", "T_SE_001", ...],
    time_period = [1, 2, ...],
    generation_mw = [150.0, 200.0, ...]
)
```

**Pros**:
- Efficient in-memory representation
- Easy aggregation and filtering
- Integrates with Plots.jl, Makie.jl

**Recommendation**: ✅ Already used correctly as intermediate format.

#### LibPQ.jl (✅ Declared, Not Implemented)

**Version**: 1.18+
**Use Case**: PostgreSQL bulk insert for historical storage

```julia
# Efficient bulk insert pattern
using LibPQ

conn = LibPQ.Connection("postgresql://user:pass@localhost/dessem")

# Use COPY for fast bulk insert
LibPQ.execute(conn, """
    COPY thermal_generation (scenario_id, plant_id, time_period, generation_mw)
    FROM STDIN WITH (FORMAT CSV)
""")

# Stream CSV data
for row in eachrow(df)
    LibPQ.write(conn, "$(row.scenario_id),$(row.plant_id),$(row.t),$(row.gen)\n")
end
```

**Performance**: 10k-50k rows/second (much faster than INSERT statements)

**Recommendation**: Implement when database integration is prioritized. Pattern in `solution_exporter.jl` line 359 is a good placeholder.

#### Alternative: Arrow.jl (Optional, High Performance)

**Version**: 2.7+
**Use Case**: Ultra-fast columnar storage

```julia
using Arrow

# Write Arrow file (columnar format)
Arrow.write("solution.arrow", df)

# 5-10x faster than CSV for large datasets
# Preserves data types exactly
```

**Pros**:
- Fastest read/write (200+ MB/s)
- Zero-copy memory mapping
- Cross-language (Python, R, C++ can read)

**Cons**:
- Binary format (not human-readable)
- Less familiar to users

**Recommendation**: **Add as optional dependency** for large-scale production runs. Add to Project.toml:

```toml
[deps]
Arrow = "69666777-d1a9-59fb-9406-91d4454c9d45"

[compat]
Arrow = "2.7"
```

**Confidence**: **HIGH** - Arrow.jl is mature and widely used.

---

## 4. Validation Stack

### 4.1 Validation Against Reference Solutions

**Current Status**: Design phase (see `/docs/VALIDATION_FRAMEWORK_DESIGN.md`)

#### Recommended Components

| Component | Version | Purpose | Confidence |
|-----------|---------|---------|------------|
| **Statistics.jl** | stdlib | MAE, RMSE, std, cor | **HIGH** |
| **StatsBase.jl** | 0.34+ | Percentiles, histograms | **HIGH** |
| **Test.jl** | stdlib | Validation test framework | **HIGH** |
| **DataFrames.jl** | 1.6+ | Time series alignment | **HIGH** |

#### Error Metrics (Recommended Implementation)

```julia
using Statistics
using StatsBase

# Mean Absolute Error
function mae(predicted, reference)
    return mean(abs.(predicted .- reference))
end

# Root Mean Square Error
function rmse(predicted, reference)
    return sqrt(mean((predicted .- reference).^2))
end

# Mean Absolute Percentage Error
function mape(predicted, reference)
    # Avoid division by zero
    mask = reference .!= 0.0
    return mean(abs.((predicted[mask] .- reference[mask]) ./ reference[mask])) * 100.0
end

# Maximum Absolute Error
function max_error(predicted, reference)
    return maximum(abs.(predicted .- reference))
end

# Pearson Correlation
function correlation(predicted, reference)
    return cor(predicted, reference)
end

# Bias (systematic offset)
function bias(predicted, reference)
    return mean(predicted .- reference)
end
```

**Rationale**: These are standard power systems validation metrics. No need for advanced libraries.

**Add to Project.toml**:

```toml
[deps]
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"  # stdlib, no version needed
StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"

[compat]
StatsBase = "0.34"
```

**Confidence**: **HIGH** - These are stable, standard libraries.

### 4.2 Numerical Tolerance Handling

#### Tolerance Configuration

```julia
# Recommended tolerances for power system optimization
struct ValidationTolerances
    # Absolute tolerances (MW, hm³, m³/s)
    absolute_generation_mw::Float64 = 1.0  # 1 MW tolerance
    absolute_storage_hm3::Float64 = 0.1     # 0.1 hm³ tolerance
    absolute_flow_m3s::Float64 = 1.0        # 1 m³/s tolerance

    # Relative tolerances (%)
    relative_generation::Float64 = 0.01     # 1% error acceptable
    relative_storage::Float64 = 0.05        # 5% error acceptable
    relative_price::Float64 = 0.05          # 5% price error acceptable

    # System-level tolerances
    energy_balance_mw::Float64 = 0.1        # 0.1 MW balance error
    power_flow_mva::Float64 = 1.0           # 1 MVA flow error
end
```

**Rationale**: Power systems have inherent modeling tolerances. These values are typical for day-ahead markets.

#### Comparison Pattern

```julia
function compare_generation(
    opendessem_gen::Vector{Float64},
    dessem_gen::Vector{Float64},
    tol::ValidationTolerances
)
    # Absolute error
    abs_error = abs.(opendessem_gen .- dessem_gen)

    # Relative error (avoid division by zero)
    mask = dessem_gen .> tol.absolute_generation_mw
    rel_error = abs_error[mask] ./ dessem_gen[mask]

    # Check tolerances
    abs_pass = all(abs_error .<= tol.absolute_generation_mw)
    rel_pass = all(rel_error .<= tol.relative_generation)

    return ValidationResult(
        abs_pass || rel_pass,  # Pass if either criterion met
        mae(opendessem_gen, dessem_gen),
        rmse(opendessem_gen, dessem_gen),
        maximum(abs_error),
        correlation(opendessem_gen, dessem_gen)
    )
end
```

**Rationale**: Use **absolute OR relative** tolerance (not AND). Small values fail relative tests, large values fail absolute tests.

### 4.3 DESSEM Binary File Parsing

**Status**: Not implemented (Phase 2 of validation framework)

#### Recommended Approach

```julia
# FORTRAN unformatted binary reading
function read_fortran_real8(io::IO)
    # FORTRAN writes: [record_size] [data] [record_size]
    record_start = read(io, Int32)
    value = read(io, Float64)  # REAL*8 = Float64
    record_end = read(io, Int32)

    @assert record_start == record_end "FORTRAN record size mismatch"
    return value
end

function read_fortran_string(io::IO, length::Int)
    record_start = read(io, Int32)
    data = String(read(io, length))
    record_end = read(io, Int32)

    @assert record_start == record_end "FORTRAN record size mismatch"
    return strip(data)
end
```

**Rationale**: DESSEM uses FORTRAN unformatted binary. Must read record markers.

**Dependencies**: None needed (use Base Julia `read`, `reinterpret`)

**Confidence**: **MEDIUM** - Requires reverse-engineering actual file structure through trial-and-error.

---

## 5. What NOT to Use

### 5.1 Avoid These Solver Approaches

| Approach | Why to Avoid |
|----------|--------------|
| **JuMP.relax_integrality for two-stage pricing** | Creates unnecessary model copy. Manual unset_binary is more efficient. |
| **Cbc.jl for large MILP** | Very slow on problems >10k variables. Only use for tiny test cases. |
| **GLPK.jl for production** | 10x slower than HiGHS, limited MIP capabilities. Only for fallback. |
| **Multiple solver packages loaded simultaneously** | Increases precompile time. Use lazy loading pattern (try...catch). |

### 5.2 Avoid These Export Patterns

| Pattern | Why to Avoid |
|---------|--------------|
| **JLD2.jl for solution export** | Julia-only format. Use Arrow.jl for binary, JSON for portability. |
| **BSON.jl for structured data** | Deprecated. Use JSON3.jl instead. |
| **Serialization.jl for cross-version storage** | Not portable across Julia versions. Use Arrow or JSON. |
| **Writing to CSV inside optimization loop** | I/O bottleneck. Store in memory, write once at end. |

### 5.3 Avoid These Validation Approaches

| Approach | Why to Avoid |
|----------|-------------|
| **Exact equality checks (==)** | Numerical optimization always has tolerance. Use ≈ with atol, rtol. |
| **RDatasets.jl for test data** | Unnecessary dependency. Store test cases as .csv or .json locally. |
| **MLJ.jl for statistical tests** | Overkill for simple metrics. Use Statistics.jl stdlib. |

---

## 6. Build Order Implications

### Phase 1: Complete Solver Pipeline (Current)
**Status**: ✅ 95% Complete

1. ✅ Solver interface with multi-solver support
2. ✅ LP relaxation for dual extraction
3. ✅ Two-stage pricing (SCUC → SCED)
4. ✅ Solution extraction at scale
5. 🔄 Add solver auto-detection improvement (minor)

**No additional dependencies needed.**

### Phase 2: Solution Export Enhancement (Current)
**Status**: ✅ 90% Complete

1. ✅ CSV export (wide format, time series)
2. ✅ JSON export (nested structure)
3. ✅ DataFrame export (long format)
4. 🔄 LibPQ export (placeholder exists, needs implementation)
5. ⚠️ Consider adding Arrow.jl for large-scale production

**Dependency to add**:
```toml
Arrow = "69666777-d1a9-59fb-9406-91d4454c9d45"
```

### Phase 3: Validation Framework (Next)
**Status**: 📋 Design Complete, Implementation Pending

1. 📋 Add StatsBase.jl for advanced metrics
2. 📋 Implement error metric functions (MAE, RMSE, MAPE)
3. 📋 Create tolerance configuration
4. 📋 Implement comparison functions
5. 📋 Parse DESSEM binary output files
6. 📋 Generate validation reports

**Dependencies to add**:
```toml
StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
```

### Phase 4: Performance Optimization (Future)
**Status**: ⏸️ Not Started

1. ⏸️ Add warm-start from previous solve
2. ⏸️ Implement incremental model building
3. ⏸️ Add parallelization for scenario analysis
4. ⏸️ Consider Distributed.jl for multi-node solving

**No additional dependencies until this phase.**

---

## 7. Recommended Immediate Actions

### 7.1 High Priority (Production Readiness)

1. **Add Arrow.jl for solution export** (1 hour)
   ```bash
   cd /home/pedro/programming/openDESSEM
   julia --project -e 'using Pkg; Pkg.add("Arrow")'
   ```

   Update `solution_exporter.jl`:
   ```julia
   function export_arrow(result, filepath; time_periods=1:24)
       df = _create_long_format_df(result, time_periods)
       Arrow.write(filepath, df)
   end
   ```

2. **Add StatsBase.jl for validation** (1 hour)
   ```bash
   julia --project -e 'using Pkg; Pkg.add("StatsBase")'
   ```

   Create `src/validation/metrics.jl`:
   ```julia
   # Implement MAE, RMSE, MAPE, max_error functions
   ```

3. **Improve solver auto-detection** (2 hours)

   Update `solver_interface.jl` line 180:
   ```julia
   solver_type = if optimizer_factory <: HiGHS.Optimizer
       HIGHS
   elseif optimizer_factory <: Gurobi.Optimizer
       GUROBI
   elseif optimizer_factory <: CPLEX.Optimizer
       CPLEX
   elseif optimizer_factory <: GLPK.Optimizer
       GLPK
   else
       @warn "Unknown solver type, using default settings"
       HIGHS
   end
   ```

### 7.2 Medium Priority (Enhanced Capability)

4. **Implement LibPQ export** (4 hours)
   - Complete `export_database()` function
   - Create SQL schema migration scripts
   - Add bulk COPY for performance

5. **Create validation metric module** (8 hours)
   - Implement error metrics (MAE, RMSE, MAPE)
   - Create tolerance configuration
   - Build comparison engine
   - Generate reports (ASCII, HTML)

### 7.3 Low Priority (Long-Term)

6. **Parse DESSEM binary files** (16 hours)
   - Reverse-engineer FORTRAN binary format
   - Implement readers for pdo_*.dat files
   - Validate against ASCII files
   - **Note**: This is complex and may require ONS documentation

---

## 8. Stack Maturity Assessment

### Production Ready (✅ Use Now)

- **JuMP.jl**: Stable, mature, excellent documentation
- **HiGHS.jl**: Fast, free, production-grade
- **CSV.jl**: Stable, widely used
- **DataFrames.jl**: Core ecosystem package
- **JSON3.jl**: Fast, modern JSON library
- **Statistics.jl**: Standard library, always available

### Production Capable (✅ Use with Testing)

- **MathOptInterface.jl**: Stable but evolving API
- **Gurobi.jl**: Mature but requires license management
- **CPLEX.jl**: Mature but limited community support
- **LibPQ.jl**: Stable but requires PostgreSQL setup

### Experimental (⚠️ Evaluate Carefully)

- **Arrow.jl**: Mature format, Julia library still evolving
- **StatsBase.jl**: Stable but occasional breaking changes

### Not Recommended (❌ Avoid)

- **GLPK.jl**: Too slow for production
- **Cbc.jl**: Performance issues at scale
- **JLD2.jl**: Julia-only format
- **BSON.jl**: Deprecated

---

## 9. Version Compatibility Matrix

| Julia Version | JuMP | MOI | HiGHS | Status |
|---------------|------|-----|-------|--------|
| 1.8 | 1.21+ | 1.27+ | 1.7+ | ✅ Minimum |
| 1.9 | 1.22+ | 1.29+ | 1.8+ | ✅ Recommended |
| 1.10 | 1.23+ | 1.31+ | 1.9+ | ✅ Latest Stable |
| 1.11 | 1.23+ | 1.31+ | 1.9+ | ✅ Future |

**Recommendation**: Target Julia 1.10+ for production. Current Project.toml specifies 1.8 as minimum, which is good for compatibility.

---

## 10. Summary

### Current State: ✅ Excellent Foundation

OpenDESSEM has a **production-ready solver pipeline** with:
- ✅ Multi-solver support (HiGHS, Gurobi, CPLEX)
- ✅ Industry-standard two-stage pricing
- ✅ Efficient solution extraction
- ✅ Multiple export formats (CSV, JSON)

### Gaps to Fill

1. **Arrow.jl** for high-performance binary export (1 hour to add)
2. **StatsBase.jl** for validation metrics (1 hour to add)
3. **LibPQ export** implementation (4 hours)
4. **Validation framework** implementation (8-16 hours)

### Key Insights

1. **Keep current solver approach**: Manual `unset_binary` for LP relaxation is more efficient than `relax_integrality`
2. **Two-stage pricing is correct**: Implementation matches industry standards (PJM, MISO, CAISO)
3. **Solution extraction is optimal**: Sparse extraction pattern scales well to 100k+ variables
4. **Add Arrow.jl**: Will improve large-scale export performance 5-10x
5. **Validation needs metrics library**: StatsBase.jl is the right choice

---

**Document Version**: 1.0
**Last Updated**: 2026-02-15
**Status**: Complete
**Confidence Level**: HIGH (based on established patterns in production power systems optimization)
