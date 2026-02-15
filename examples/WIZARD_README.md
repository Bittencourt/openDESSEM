# OpenDESSEM System Builder Wizard

## Overview

The System Builder Wizard is an interactive, step-by-step tool for creating power system models in OpenDESSEM. It guides users through defining all components of an electricity system and provides sensible defaults to streamline the process.

## Features

- **Interactive Guidance**: Step-by-step prompts with clear explanations
- **Sensible Defaults**: Press Enter to accept default values at any step
- **Input Validation**: Real-time validation with helpful error messages
- **Help System**: Type 'help' at any prompt for detailed information
- **Progress Tracking**: Clear indication of current step (e.g., "Step 3 of 9")
- **Quick Start Mode**: Create a simple 3-bus system with minimal interaction
- **Automatic Optimization**: Build and solve the system automatically after configuration

## Usage

### Running the Wizard

```bash
# From the project root directory
julia --project=. examples/wizard_example.jl
```

### Modes

The wizard offers three modes:

1. **Interactive Wizard** (Option 1): Full guided experience with detailed configuration
2. **Quick Start** (Option 2): Creates a simple 3-bus system automatically
3. **Exit**: Quit without creating a system

## Wizard Steps

### Step 1: System Basics

Configure fundamental system information:
- **System Name**: Human-readable identifier for your system
- **Base Date**: Simulation start date (format: YYYY-MM-DD)
- **Time Periods**: Number of hours to simulate (1-168)

### Step 2: Define Buses

Create electrical buses (network nodes):
- **Number of Buses**: How many buses to create (1-100)
- **Bus Names**: Custom names or accept defaults (BUS_1, BUS_2, etc.)
- **Voltage Level**: Default system voltage (69kV to 765kV)

**Example Bus:**
```julia
Bus(;
    id = "BUS_1",
    name = "Bus 1 - North",
    voltage_kv = 230.0,
    base_kv = 230.0,
    latitude = -23.5,
    longitude = -46.6
)
```

### Step 3: Define Submarkets

Create market regions/bidding zones:
- **Number of Submarkets**: How many bidding zones (1-10)
- **Submarket Codes**: Standard codes (N, NE, SE, S) or custom

**Example Submarket:**
```julia
Submarket(;
    id = "SUB_1",
    code = "SE",
    name = "Southeast Region",
    country = "BR"
)
```

### Step 4: Define Thermal Plants

Create thermal power plants:
- **Number of Plants**: How many thermal plants (0-50)
- **Fuel Types**: COAL, NATURAL_GAS, FUEL_OIL, NUCLEAR, BIOMASS
- **Characteristics**: Capacity, ramp rates, costs, min up/down times

**Example Thermal Plant:**
```julia
ConventionalThermal(;
    id = "T_1",
    name = "Coal Plant 1",
    bus_id = "BUS_1",
    submarket_id = "SE",
    fuel_type = COAL,
    capacity_mw = 500.0,
    min_generation_mw = 150.0,
    max_generation_mw = 500.0,
    ramp_up_mw_per_min = 5.0,
    ramp_down_mw_per_min = 5.0,
    min_up_time_hours = 8,
    min_down_time_hours = 4,
    fuel_cost_rsj_per_mwh = 80.0,
    startup_cost_rs = 50000.0,
    shutdown_cost_rs = 20000.0
)
```

### Step 5: Define Hydro Plants

Create hydroelectric plants:
- **Number of Plants**: How many hydro plants (0-50)
- **Types**: Reservoir, Run-of-River, Pumped Storage
- **Characteristics**: Storage capacity, outflow limits, efficiency

**Example Hydro Plant:**
```julia
ReservoirHydro(;
    id = "H_1",
    name = "Hydro Plant 1",
    bus_id = "BUS_2",
    submarket_id = "SE",
    max_volume_hm3 = 5000.0,
    initial_volume_hm3 = 2500.0,
    min_volume_hm3 = 500.0,
    max_outflow_m3_per_s = 500.0,
    efficiency = 90.0,
    max_generation_mw = 200.0,
    water_value_rs_per_hm3 = 50.0
)
```

### Step 6: Define Renewables

Add wind and solar generation:
- **Wind Farms**: Number and capacity (if any)
- **Solar Farms**: Number and capacity (if any)

**Example Wind Farm:**
```julia
WindPlant(;
    id = "W_1",
    name = "Wind Farm 1",
    bus_id = "BUS_3",
    submarket_id = "S",
    capacity_mw = 150.0,
    forecast_type = DETERMINISTIC,
    is_dispatchable = false
)
```

### Step 7: Define Loads

Create demand (load) curves:
- **Number of Loads**: How many load points (1-50)
- **Load Patterns**: Time-varying demand profiles

**Example Load:**
```julia
Load(;
    id = "L_1",
    name = "North Load",
    bus_id = "BUS_1",
    submarket_id = "SE",
    base_mw = 400.0,
    load_profile = [400.0, 410.0, 420.0, ...]  # Hourly values
)
```

### Step 8: Define Interconnections

Create transmission links between regions:
- **Number of Interconnections**: How many links (0 to max possible)
- **Connections**: Which buses/submarkets to connect
- **Capacity**: Transmission capacity limits

**Example Interconnection:**
```julia
Interconnection(;
    id = "IC_1_2",
    name = "North to Center",
    from_bus_id = "BUS_1",
    to_bus_id = "BUS_2",
    from_submarket_id = "N",
    to_submarket_id = "C",
    capacity_mw = 200.0,
    loss_percent = 2.0
)
```

### Step 9: Solver Options

Configure optimization solver:
- **Time Limit**: Maximum solve time in seconds (10-7200)
- **MIP Gap**: Relative optimality gap (0.0-1.0, default 0.01)
- **Threads**: Number of CPU cores to use (1-16)

**Example Configuration:**
```julia
SolverOptions(;
    time_limit_seconds = 300.0,
    mip_gap = 0.01,
    threads = 1,
    verbose = false
)
```

## Default System Patterns

The wizard creates systems with realistic default characteristics:

### Thermal Plant Types
- **Coal**: 500 MW, 80 R$/MWh, slow ramping (5 MW/min), baseload
- **Gas (Combined Cycle)**: 300 MW, 120 R$/MWh, medium ramping (10 MW/min)
- **Gas (Peaker)**: 200 MW, 200 R$/MWh, fast ramping (20 MW/min), peaking

### Load Patterns
- **Industrial**: Steady profile, high base load
- **Commercial**: Daytime peak (9 AM - 6 PM)
- **Residential**: Evening peak (6 PM - 10 PM)

### Renewable Profiles
- **Wind**: Higher during daytime, variable (0-150 MW)
- **Solar**: Zero at night, bell curve during day

## Output

After completing the wizard, you'll receive:

1. **System Summary**: Overview of all entities created
2. **Optimization Results**: Two-stage solution (UC → SCED)
3. **Locational Marginal Prices (LMPs)**: Price at each submarket
4. **Generation Schedule**: Dispatch for each plant
5. **Cost Breakdown**: Total costs and average cost per MWh

## Example Output

```
======================================================================
SYSTEM CONFIGURATION SUMMARY
======================================================================

System: Quick Start System
Base Date: 2025-01-15
Time Periods: 24

Network:
  Buses: 3
  Submarkets: 3

Generation:
  Thermal Plants: 3
  Hydro Plants: 1
  Wind Farms: 1
  Solar Farms: 0

Demand & Transmission:
  Loads: 3
  Interconnections: 2

Solver:
  Time Limit: 300.0 seconds
  MIP Gap: 0.01
  Threads: 1

======================================================================
```

## Advanced Features

### Custom Configuration

For more control, choose "n" when prompted for defaults to provide detailed parameters for each entity.

### Help System

Type `help` at any prompt to see:
- Description of the entity type
- Typical parameter ranges
- Examples and best practices

### Save/Load Configuration

The wizard configuration is stored in a `WizardState` object that can be extended to support saving/loading from JSON or YAML files.

## Testing

A test script is provided to verify wizard components:

```bash
julia --project=. test_wizard.jl
```

This tests:
- Entity creation functions
- Validation logic
- System integration
- Constraint building
- Objective setup

## Limitations

1. **No GUI**: Terminal-based only (no graphical interface)
2. **No Backtracking**: Cannot go back to previous steps (would need state management)
3. **No Configuration Files**: Cannot save/load wizard state (future enhancement)
4. **Linear Prompts**: Questions are asked in fixed order

## Future Enhancements

Potential improvements:
- [ ] Save/load configuration to JSON/YAML
- [ ] Back/forward navigation between steps
- [ ] GUI version (using Gtk.jl or Blink.jl)
- [ ] Template systems (predefined configurations)
- [ ] Import from Excel/CSV
- [ ] Export to solver input formats
- [ ] Sensitivity analysis wizard
- [ ] Scenario comparison wizard
- [ ] Multi-objective optimization wizard

## Troubleshooting

### Common Issues

**"Validation failed" error**
- Check that all IDs are unique
- Ensure min <= max for all range parameters
- Verify bus/submarket IDs exist when creating plants

**"Optimization failed" error**
- Increase time limit
- Relax MIP gap (e.g., 0.05 instead of 0.01)
- Check system has sufficient generation
- Verify interconnections allow power flow

**"Infeasible problem" error**
- Check total generation capacity >= peak load
- Verify minimum generation constraints are satisfiable
- Ensure renewable forecasts aren't too high for load

## Contributing

To extend the wizard:

1. Add new steps following the existing pattern
2. Update `total_steps` in `WizardState`
3. Add help text to `show_help()`
4. Test with `test_wizard.jl`

Example new step:
```julia
function step_10_storage()
    print_header("DEFINE ENERGY STORAGE", 10, wizard.total_steps)

    n_storage = prompt_number(
        "How many battery storage systems?",
        0;
        type=Int,
        min=0,
        max=20,
        integer=true
    )

    # ... rest of implementation
end
```

## See Also

- `examples/complete_workflow_example.jl`: Non-interactive example
- `src/entities/`: Entity type definitions
- `src/constraints/`: Constraint building functions
- `docs/guide.md`: Full user guide
