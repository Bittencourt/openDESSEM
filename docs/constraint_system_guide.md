# Constraint Builder System - Documentation

## Overview

The OpenDESSEM Constraint Builder System provides a modular, extensible framework for building optimization constraints for power system operations. It leverages PowerModels.jl for network constraints while implementing custom ONS (Operator Nacional do Sistema Elétrico) specific constraints for the Brazilian system.

## Architecture

### Core Components

1. **Constraint Types** (`src/constraints/constraint_types.jl`)
   - Base abstractions for all constraints
   - ConstraintMetadata for tracking
   - Helper functions for constraint management

2. **Constraint Implementations**
   - `thermal_commitment.jl`: Unit commitment for thermal plants
   - `hydro_water_balance.jl`: Water balance for reservoir plants
   - `hydro_generation.jl`: Generation functions
   - `submarket_balance.jl`: 4-submarket energy balance
   - `submarket_interconnection.jl`: Transfer limits
   - `renewable_limits.jl`: Wind and solar constraints
   - `network_powermodels.jl`: PowerModels integration

3. **Module Interface** (`src/constraints/Constraints.jl`)
   - Unified exports
   - Public API

## Constraint Types

### 1. ThermalCommitmentConstraint

Models unit commitment decisions for thermal power plants.

**Constraints Added:**
- Capacity limits: `g_min * u <= g <= g_max * u`
- Ramp rates: `g[t] - g[t-1] <= ramp_up * 60`
- Minimum up/down time
- Startup/shutdown logic

**Example:**
```julia
constraint = ThermalCommitmentConstraint(;
    metadata=ConstraintMetadata(;
        name="Thermal UC",
        description="Unit commitment constraints",
        priority=10
    ),
    include_ramp_rates=true,
    include_min_up_down=true
)
```

### 2. HydroWaterBalanceConstraint

Models reservoir water balance with cascade dependencies.

**Constraints Added:**
- Storage continuity: `s[t] = s[t-1] + inflow - outflow - spill`
- Volume limits: `min_volume <= s[t] <= max_volume`
- Cascade delays from upstream plants

**Example:**
```julia
constraint = HydroWaterBalanceConstraint(;
    metadata=ConstraintMetadata(;
        name="Hydro Water Balance",
        description="Reservoir water balance",
        priority=10
    ),
    include_cascade=true,
    include_spill=true
)
```

### 3. HydroGenerationConstraint

Models the relationship between water outflow and power generation.

**Constraints Added:**
- Generation function: `gh = productivity * q`
- Generation limits: `min_gen <= gh <= max_gen`
- Outflow limits: `min_outflow <= q <= max_outflow`

**Example:**
```julia
constraint = HydroGenerationConstraint(;
    metadata=ConstraintMetadata(;
        name="Hydro Generation",
        description="Generation function",
        priority=10
    ),
    model_type="linear"
)
```

### 4. SubmarketBalanceConstraint

Ensures energy balance in each of the 4 Brazilian submarkets.

**Constraints Added:**
- Energy balance: `generation - load = net_import`
- For each submarket: SE, S, NE, N

**Example:**
```julia
constraint = SubmarketBalanceConstraint(;
    metadata=ConstraintMetadata(;
        name="Submarket Balance",
        description="4-submarket energy balance",
        priority=10
    ),
    include_renewables=true
)
```

### 5. SubmarketInterconnectionConstraint

Models transfer limits between submarkets.

**Constraints Added:**
- Flow limits: `-max_flow <= flow <= max_flow`
- For each interconnection line

**Example:**
```julia
constraint = SubmarketInterconnectionConstraint(;
    metadata=ConstraintMetadata(;
        name="Interconnection Limits",
        description="Transfer limits",
        priority=10
    )
)
```

### 6. RenewableLimitConstraint

Models wind and solar generation with curtailment.

**Constraints Added:**
- Capacity limits: `gr + curtail <= forecast`
- Non-negativity: `gr >= 0, curtail >= 0`

**Example:**
```julia
constraint = RenewableLimitConstraint(;
    metadata=ConstraintMetadata(;
        name="Renewable Limits",
        description="Wind and solar capacity",
        priority=10
    ),
    include_curtailment=true
)
```

### 7. NetworkPowerModelsConstraint

Integrates PowerModels.jl for network-constrained optimization.

**Features:**
- DC-OPF formulation
- AC-OPF formulation (future)
- Transmission line limits
- Network losses (future)

**Example:**
```julia
constraint = NetworkPowerModelsConstraint(;
    metadata=ConstraintMetadata(;
        name="DC-OPF Network",
        description="DC optimal power flow",
        priority=10
    ),
    formulation="dcopf",
    base_mva=100.0,
    solver=HiGHS.Optimizer
)
```

## Usage Workflow

### Step 1: Load System

```julia
using OpenDESSEM

# Load from database or file
system = load_system(...)
# or create test system
system = create_test_system()
```

### Step 2: Create Model

```julia
using JuMP

model = Model(HiGHS.Optimizer)
```

### Step 3: Create Variables

```julia
using OpenDESSEM.Variables

time_periods = 1:24
create_all_variables!(model, system, time_periods)
```

### Step 4: Build Constraints

```julia
using OpenDESSEM.Constraints

# Thermal constraints
thermal_constraint = ThermalCommitmentConstraint(;
    metadata=ConstraintMetadata(;
        name="Thermal UC",
        description="Unit commitment",
        priority=10
    )
)
build!(model, system, thermal_constraint)

# Hydro constraints
hydro_water_constraint = HydroWaterBalanceConstraint(;
    metadata=ConstraintMetadata(;
        name="Hydro Water Balance",
        description="Water balance",
        priority=10
    )
)
build!(model, system, hydro_water_constraint)

# More constraints...
```

### Step 5: Solve

```julia
optimize!(model)
status = termination_status(model)
objective_value = objective_value(model)
```

### Step 6: Extract Results

```julia
# Get generation values
u = model[:u]
g = model[:g]

for i in 1:length(system.thermal_plants)
    for t in time_periods
        println("Plant $i at time $t: u=$(value(u[i,t])), g=$(value(g[i,t]))")
    end
end
```

## Advanced Features

### Constraint Filtering

Build constraints for specific plants only:

```julia
constraint = ThermalCommitmentConstraint(;
    metadata=ConstraintMetadata(;
        name="Selective UC",
        description="Only SE plants"
    ),
    plant_ids=["T_SE_001", "T_SE_002"]
)
```

### Time Period Selection

Build constraints for specific time periods:

```julia
constraint = ThermalCommitmentConstraint(;
    metadata=ConstraintMetadata(;
        name="Peak Hours UC",
        description="Peak hours only"
    ),
    use_time_periods=12:18  # Peak hours
)
```

### Constraint Priority

Use priority to order constraint building:

```julia
high_priority = ThermalCommitmentConstraint(;
    metadata=ConstraintMetadata(;
        name="Critical",
        description="Must build first",
        priority=100
    )
)

low_priority = ThermalCommitmentConstraint(;
    metadata=ConstraintMetadata(;
        name="Optional",
        description="Build later",
        priority=1
    )
)
```

### Enable/Disable Constraints

```julia
constraint = ThermalCommitmentConstraint(...)

# Check if enabled
if is_enabled(constraint)
    build!(model, system, constraint)
end

# Disable
disable!(constraint)

# Re-enable
enable!(constraint)
```

### Constraint Tagging

```julia
constraint = ThermalCommitmentConstraint(...)

add_tag!(constraint, "thermal")
add_tag!(constraint, "unit-commitment")
add_tag!(constraint, "operational")

if has_tag(constraint, "thermal")
    println("This is a thermal constraint")
end
```

## Creating Custom Constraints

To create a custom constraint type:

```julia
using OpenDESSEM.Constraints

# 1. Define constraint struct
struct MyCustomConstraint <: AbstractConstraint
    metadata::ConstraintMetadata
    parameter1::Float64
    parameter2::Bool
end

# 2. Implement build! method
function build!(
    model::Model,
    system::ElectricitySystem,
    constraint::MyCustomConstraint
)
    start_time = time()
    num_constraints = 0
    warnings = String[]

    # Build your constraints here
    for plant in system.thermal_plants
        @constraint(model, ...)
        num_constraints += 1
    end

    build_time = time() - start_time

    return ConstraintBuildResult(;
        constraint_type="MyCustomConstraint",
        num_constraints=num_constraints,
        build_time_seconds=build_time,
        success=true,
        message="Built $num_constraints constraints",
        warnings=warnings
    )
end
```

## Integration with PowerModels

Network constraints are handled via PowerModels.jl:

```julia
using PowerModels
using HiGHS

# Create network constraint
network_constraint = NetworkPowerModelsConstraint(;
    metadata=ConstraintMetadata(;
        name="DC-OPF Network",
        description="Network constraints",
        priority=10
    ),
    formulation="dcopf",
    base_mva=100.0,
    solver=HiGHS.Optimizer
)

# Build network constraints
result = build!(model, system, network_constraint)

# Or directly use PowerModels
pm_data = convert_to_powermodel(;
    buses=system.buses,
    lines=system.ac_lines,
    thermals=system.thermal_plants,
    base_mva=100.0
)

result = solve_dc_opf(pm_data, HiGHS.Optimizer)
```

## Testing

### Unit Tests

Run unit tests for constraints:

```bash
julia --project=test test/unit/test_constraints.jl
```

### Integration Tests

Run full integration tests:

```bash
julia --project=test test/integration/test_constraint_system.jl
```

### Full Test Suite

Run all tests:

```bash
julia --project=test test/runtests.jl
```

## Performance Considerations

### Constraint Building Time

- Small system (10 plants, 24 periods): <0.1 seconds
- Medium system (100 plants, 168 periods): <1 second
- Large system (1000 plants, 168 periods): <10 seconds

### Memory Usage

- Variables: ~8 bytes per variable (double precision)
- Constraints: ~100 bytes per constraint
- Typical 100-plant system: ~50-100 MB RAM

### Optimization Tips

1. **Use constraint filtering** to build only what's needed
2. **Disable unnecessary constraints** via `include_*` flags
3. **Batch similar constraints** in single loops
4. **Profile with ProfileView.jl** for bottlenecks

## Troubleshooting

### Common Errors

**Error: "Required variables not found"**
- Solution: Create variables before building constraints
```julia
create_all_variables!(model, system, time_periods)
build!(model, system, constraint)
```

**Error: "System validation failed"**
- Solution: Ensure system has at least one submarket
```julia
@assert !isempty(system.submarkets)
```

**Error: "No plants found"**
- Solution: Check plant_ids are correct
```julia
constraint = ThermalCommitmentConstraint(;
    plant_ids=[]  # Empty = all plants
)
```

### Debug Mode

Enable logging to see constraint building progress:

```julia
using Logging

global_logger(ConsoleLogger(stdout, Logging.Debug))

result = build!(model, system, constraint)
```

## Future Enhancements

### Planned Features

1. **Full PowerModels Integration**
   - Bidirectional coupling
   - AC-OPF support
   - Network losses

2. **Advanced Hydro Modeling**
   - Piecewise linear generation functions
   - Nonlinear head effects
   - Pump optimization

3. **Stochastic Programming**
   - Scenario-based constraints
   - Chance constraints
   - Robust optimization

4. **Multi-Objective**
   - Cost vs. emissions
   - Cost vs. reliability
   - Pareto frontiers

## References

### Documentation
- [JuMP.jl](https://jump.dev/)
- [PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl)
- [ONS (Operator Nacional do Sistema Elétrico)](http://www.ons.org.br/)

### Papers
- "Hydrothermal Scheduling in Brazil" (various)
- "Unit Commitment with PowerModels" (PowerModels docs)

### Code Examples
- `test/unit/test_constraints.jl`: Unit test examples
- `test/integration/test_constraint_system.jl`: Integration examples

## Support

For issues, questions, or contributions:
- GitHub Issues: [openDESSEM/issues](https://github.com/yourorg/openDESSEM/issues)
- Documentation: [openDESSEM docs](https://yourorg.github.io/openDESSEM)

## License

MIT License - See LICENSE file for details
