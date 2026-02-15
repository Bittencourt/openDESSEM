# Validation Framework Design Document

**Task**: TASK-012 - Validation Against Official DESSEM
**Date**: 2025-01-09
**Status**: Design Phase

---

## 1. Overview

### 1.1 Purpose

The validation framework ensures that OpenDESSEM produces results consistent with the official DESSEM software from CEPEL. This is critical for:

- **Model correctness**: Verifying that our implementation matches the reference
- **Credibility**: Building trust with stakeholders (ONS, CCEE, researchers)
- **Debugging**: Identifying discrepancies in constraints, objective, or data handling
- **Continuous quality**: Ensuring changes don't break accuracy

### 1.2 Scope

The validation framework will:

1. **Parse DESSEM output files** (pdo_*.dat format)
2. **Compare key variables** between OpenDESSEM and DESSEM
3. **Calculate statistical metrics** (MAE, RMSE, MAPE, max error)
4. **Generate validation reports** with pass/fail criteria
5. **Support multiple case types** (with/without network, different revisions)

### 1.3 What We Validate

| Category | Variables | Files |
|----------|-----------|-------|
| **Hydro** | Storage (hm³), Outflow (m³/s), Generation (MW) | `pdo_hidr.dat` |
| **Thermal** | Generation (MW), Commitment, Startup/Shutdown | `pdo_term.dat` |
| **Renewable** | Generation (MW), Curtailment (MW) | `pdo_eolica.dat` |
| **System** | Submarket balance, Interchange flows | `pdo_sist.dat`, `pdo_sumaoper.dat` |
| **Prices** | Marginal cost (R$/MWh) | Dual values from energy balance |
| **Network** | Bus voltages, Line flows | `pdo_cmobar.dat`, `pdo_somflux.dat` |

---

## 2. DESSEM Output File Formats

### 2.1 Identified Output Files

From the sample case `DS_ONS_102025_RV2D11`:

| File | Size | Type | Description |
|------|------|------|-------------|
| `pdo_hidr.dat` | 28.9 MB | Binary | Hydro plant operation (storage, outflow, generation) |
| `pdo_term.dat` | 4.0 MB | Binary | Thermal plant operation |
| `pdo_eolica.dat` | 27.5 MB | Binary | Wind/solar generation |
| `pdo_sist.dat` | 94 KB | ASCII | System summary (submarket totals) |
| `pdo_sumaoper.dat` | 553 KB | Binary | Operational summary |
| `pdo_cmobar.dat` | 35.7 MB | Binary | Network bar data (bus voltages, angles) |
| `pdo_somflux.dat` | 9.0 MB | Binary | Line flows |
| `des_log_relato.dat` | 4.1 MB | Binary | Execution log/summary |

### 2.2 File Format Categories

**ASCII Text Files**:
- `pdo_sist.dat` - System summary
- `des_log_relato.dat` - Execution log

**Binary Files** (likely FORTRAN unformatted):
- `pdo_hidr.dat` - Hydro operations
- `pdo_term.dat` - Thermal operations
- `pdo_eolica.dat` - Renewable operations
- `pdo_sumaoper.dat` - Operational summary
- `pdo_cmobar.dat` - Network bus data
- `pdo_somflux.dat` - Network flow data

---

## 3. Validation Metrics

### 3.1 Error Metrics

| Metric | Formula | Use Case | Target |
|--------|---------|----------|--------|
| **MAE** | Mean Absolute Error | Average deviation | < 1% |
| **RMSE** | Root Mean Square Error | Large errors penalized | < 2% |
| **MAPE** | Mean Absolute % Error | Relative error | < 5% |
| **Max Error** | Max(absolute error) | Worst-case | < 10% |
| **Correlation** | Pearson r | Pattern match | > 0.95 |
| **Bias** | Mean(dessem - opendesserm) | Systematic offset | ≈ 0 |

### 3.2 Pass/Fail Criteria

**Tier 1 - Critical** (must pass):
- Total system generation: MAE < 0.5%
- Submarket balance: Max error < 1%
- Total hydro generation: MAE < 1%
- Total thermal generation: MAE < 1%

**Tier 2 - Important** (should pass):
- Individual plant generation: MAE < 5%
- Hydro storage trajectories: MAE < 5%
- Marginal prices: MAE < 5%

**Tier 3 - Nice to have**:
- Renewable generation: MAE < 10% (highly variable)
- Network flows: MAE < 10% (depends on network modeling)

---

## 4. Module Architecture

### 4.1 Directory Structure

```
test/validation/
├── Validation.jl              # Main validation module
├── dessem_parser.jl           # DESSEM output file parser
├── comparison.jl              # Comparison functions
├── metrics.jl                 # Statistical metrics
├── report.jl                  # Report generation
├── types.jl                   # Validation-specific types
└── test_validation.jl         # Validation tests
```

### 4.2 Core Types

```julia
# Validation result container
struct ValidationMetric
    name::String
    value::Float64
    unit::String
    tolerance::Float64
    passed::Bool
end

struct ValidationResult
    case_name::String
    case_date::Date
    overall_passed::Bool
    metrics::Dict{String, Vector{ValidationMetric}}
    worst_offenders::Vector{Tuple{String, Float64}}
    timestamp::DateTime
end

# DESSEM output data
struct DessemOutput
    hydro::Dict{Tuple{String, Int}, HydroData}
    thermal::Dict{Tuple{String, Int}, ThermalData}
    renewable::Dict{Tuple{String, Int}, RenewableData}
    system::SystemSummary
    prices::Dict{Tuple{String, Int}, Float64}
    metadata::CaseMetadata
end
```

---

## 5. Implementation Plan

### Phase 1: Foundation (Current)

**Objective**: Create skeleton and parse simple ASCII files

- [x] Design validation framework architecture
- [ ] Create module structure in `test/validation/`
- [ ] Define validation types (`types.jl`)
- [ ] Implement ASCII parser for `pdo_sist.dat`
- [ ] Implement basic metrics calculator
- [ ] Create simple validation test

### Phase 2: DESSEM Output Parser

**Objective**: Parse all DESSEM output files

- [ ] Reverse-engineer binary file formats (pdo_hidr.dat, pdo_term.dat)
- [ ] Implement FORTRAN unformatted reader
- [ ] Parse hydro operations (storage, outflow, generation)
- [ ] Parse thermal operations (generation, commitment)
- [ ] Parse renewable operations (generation, curtailment)
- [ ] Parse network data (bus voltages, line flows)
- [ ] Add data validation and error handling

### Phase 3: Comparison Engine

**Objective**: Compare OpenDESSEM results with DESSEM

- [ ] Implement hydro comparison function
- [ ] Implement thermal comparison function
- [ ] Implement renewable comparison function
- [ ] Implement system-level comparison
- [ ] Implement price comparison (dual values)
- [ ] Add time series alignment
- [ ] Handle missing data gracefully

### Phase 4: Metrics & Reporting

**Objective**: Calculate metrics and generate reports

- [ ] Implement all error metrics (MAE, RMSE, MAPE, etc.)
- [ ] Add statistical tests (t-test, correlation)
- [ ] Generate ASCII reports
- [ ] Generate HTML reports with plots
- [ ] Generate CSV summaries for analysis
- [ ] Add worst-offender identification
- [ ] Create pass/fail logic with tiers

### Phase 5: Integration & Testing

**Objective**: Integrate with main codebase and test

- [ ] Add validation workflow to examples
- [ ] Create validation test suite
- [ ] Add continuous validation (run on every commit)
- [ ] Document validation process
- [ ] Create validation dashboard (optional)

---

## 6. Key Challenges & Solutions

### Challenge 1: Binary File Formats

**Problem**: DESSEM output files use FORTRAN unformatted binary format

**Solution**:
1. Use Julia's `read` and `reinterpret` for binary reading
2. Analyze hex dumps to identify record structure
3. Map FORTRAN data types to Julia types:
   - `INTEGER*4` → `Int32`
   - `REAL*8` → `Float64`
   - `CHARACTER*n` → `String` (fixed-width)
4. Test with known data points from ASCII files

### Challenge 2: Time Alignment

**Problem**: Different time discretizations (hourly vs half-hourly)

**Solution**:
1. Detect time resolution from data
2. Aggregate/disaggregate as needed
3. Use interpolation for continuous variables
4. Use sum for energy variables

### Challenge 3: Plant ID Mapping

**Problem**: DESSEM plant codes may not match OpenDESSEM IDs

**Solution**:
1. Create mapping table based on subsystem + plant number
2. Use fuzzy matching for names if needed
3. Allow manual mapping configuration
4. Log unmatched plants for investigation

### Challenge 4: Numerical Precision

**Problem**: Small numerical differences due to solver tolerances

**Solution**:
1. Use appropriate tolerances (1-5% for most variables)
2. Account for solver precision (HiGHS vs CPLEX)
3. Use relative errors for large values
4. Use absolute tolerances for small values

---

## 7. Example Usage

```julia
using OpenDESSEM
using OpenDESSEM.Validation

# Step 1: Load DESSEM case
system = load_dessem_case("docs/Sample/DS_ONS_102025_RV2D11/")

# Step 2: Run OpenDESSEM solver
result = optimize!(system, HiGHS.Optimizer)

# Step 3: Parse DESSEM output files
dessem_output = parse_dessem_output("docs/Sample/DS_ONS_102025_RV2D11/")

# Step 4: Compare results
validation_result = compare_all(dessem_output, result)

# Step 5: Generate report
generate_html_report(validation_result, "validation_report.html")

# Step 6: Check results
if validation_result.overall_passed
    println("✅ Validation passed!")
else
    println("❌ Validation failed - see report")
end
```

---

## 8. Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Foundation | 2-3 days | None |
| Phase 2: Parser | 5-7 days | Phase 1 |
| Phase 3: Comparison | 3-4 days | Phase 2 |
| Phase 4: Metrics | 3-4 days | Phase 3 |
| Phase 5: Integration | 2-3 days | Phase 4 |
| **Total** | **15-21 days** | |

---

## 9. Next Steps

1. **Review this design** with team
2. **Create module structure** in `test/validation/`
3. **Start Phase 1**: Implement ASCII parser for `pdo_sist.dat`
4. **Test on sample case**: `DS_ONS_102025_RV2D11`
5. **Iterate**: Add more parsers and metrics based on findings

---

**Document Version**: 1.0
**Last Updated**: 2025-01-09
**Author**: OpenDESSEM Development Team
**Status**: Ready for Implementation
