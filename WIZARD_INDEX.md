# OpenDESSEM Wizard - Complete Documentation Index

## Quick Links

- **[Implementation Summary](#implementation-summary)** - Technical overview
- **[User Guide](#user-guide)** - How to use the wizard
- **[Developer Guide](#developer-guide)** - How to extend the wizard
- **[API Reference](#api-reference)** - Function documentation

---

## Implementation Summary

### Overview

The OpenDESSEM Wizard is an interactive, step-by-step system builder that guides users through creating power system models. It provides sensible defaults and comprehensive validation.

**File**: `examples/wizard_example.jl` (1,200+ lines)

**Key Features**:
- 9 guided steps
- Two modes: Interactive and Quick Start
- Input validation with helpful error messages
- Context-sensitive help system
- Automatic optimization
- Complete results display

**Related Files**:
- `test_wizard.jl` - Component tests
- `examples/WIZARD_README.md` - User documentation
- `examples/wizard_transcript.jl` - Usage examples
- `WIZARD_IMPLEMENTATION_SUMMARY.md` - Technical details
- `WIZARD_FLOWCHART.md` - Visual flowcharts

### Architecture

```
WizardState (Configuration)
    │
    ├─> User Input (Prompts)
    │   └─> Validation (Range/Type checking)
    │
    ├─> Entity Creation (Default/Custom)
    │   ├─> Buses
    │   ├─> Submarkets
    │   ├─> Thermal Plants
    │   ├─> Hydro Plants
    │   ├─> Renewables
    │   ├─> Loads
    │   └─> Interconnections
    │
    ├─> System Building
    │   └─> ElectricitySystem
    │
    └─> Optimization
        ├─> JuMP Model
        ├─> Variables
        ├─> Constraints
        ├─> Objective
        └─> Solver (HiGHS)
```

### Design Principles

1. **User-Friendly**: Clear prompts, helpful errors, sensible defaults
2. **Robust**: Comprehensive validation, error handling
3. **Modular**: Each step is independent, easy to modify
4. **Extensible**: Easy to add new steps or features
5. **Documented**: Extensive inline documentation

---

## User Guide

### Getting Started

#### Installation

Ensure you have OpenDESSEM installed:

```bash
# In project directory
julia --project=.
] instantiate
```

#### Running the Wizard

```bash
# Basic usage
julia --project=. examples/wizard_example.jl

# With specific Julia version
/path/to/julia --project=. examples/wizard_example.jl
```

#### Mode Selection

On startup, you'll see:

```
Choose your mode:
  1. Interactive Wizard (guided step-by-step)
  2. Quick Start (simple 3-bus system)
  3. Exit

Enter choice [Default: 2]:
```

**Quick Start** (Recommended for first-time users):
- Press Enter or type `2`
- Creates a complete 3-bus system automatically
- Solves and displays results

**Interactive Mode**:
- Type `1`
- Guides through 9 configuration steps
- Full customization available

### Wizard Steps

#### Step 1: System Basics

Configure fundamental information:
- **System Name**: Identifier for your system
- **Base Date**: Simulation start date (YYYY-MM-DD)
- **Time Periods**: Hours to simulate (1-168)

Example:
```
Enter a name for your system
[Default: My Power System]: Brazilian Test System

Enter the base date
[Default: 2025-01-15] (format: YYYY-MM-DD): 2025-02-01

How many time periods?
(must be between 1 and 168)
[Default: 24]: 48
```

#### Step 2: Define Buses

Create electrical network nodes:
- **Number of Buses**: 1-100
- **Names**: Custom or default (BUS_1, BUS_2, etc.)
- **Voltage**: 69kV to 765kV

```
How many buses do you want?
[Default: 3]: 5

Create buses with default settings?
[Default: Y/n]: Y
```

#### Step 3: Define Submarkets

Create market regions/bidding zones:
- **Number**: 1-10 submarkets
- **Codes**: Standard (N, NE, SE, S) or custom

#### Steps 4-8: Generation, Loads, Transmission

For each category:
1. Specify how many (or 0 to skip)
2. Choose default or custom settings
3. Wizard creates entities with sensible parameters

#### Step 9: Solver Options

Configure optimization:
- **Time Limit**: Maximum solve time (seconds)
- **MIP Gap**: Optimality tolerance (0.01 = 1%)
- **Threads**: CPU cores to use

### Input Tips

#### Accepting Defaults

Press Enter at any prompt to use the default value:

```
How many buses do you want?
[Default: 3]: [Enter]
✓ Using default: 3 buses
```

#### Getting Help

Type `help` at any prompt for detailed information:

```
How many thermal plants?
[Default: 3]: help

[THERMAL PLANT HELP]
Thermal plants generate electricity from heat sources.
...
```

#### Numeric Input

For numeric prompts, type a number within the specified range:

```
How many time periods?
(must be between 1 and 168)
[Default: 24]: 48
```

#### Yes/No Questions

For yes/no prompts, type:
- `y`, `yes`, `1`, `true` for Yes
- `n`, `no`, `0`, `false` for No
- Or press Enter for default

```
Create buses with default settings?
[Default: Y/n]: y
```

### Output

After configuration, you'll see:

#### System Summary

```
======================================================================
SYSTEM CONFIGURATION SUMMARY
======================================================================

System: Brazilian Test System
Base Date: 2025-02-01
Time Periods: 48

Network:
  Buses: 5
  Submarkets: 4

Generation:
  Thermal Plants: 5
  Hydro Plants: 1
  Wind Farms: 1

[...]
```

#### Optimization Results

```
✓ Optimization successful!
  Stage 1 (UC) Objective: R$ 248760.00
  Stage 1 Solve Time: 2.34 seconds
  Stage 2 (SCED) Objective: R$ 248760.00
  Stage 2 Solve Time: 0.15 seconds
```

#### Locational Marginal Prices

```
North Region (N)
  Hour   1:    80.00 R$/MWh
  Hour   2:    80.00 R$/MWh
  Hour   3:    80.00 R$/MWh
  ...
  Average: 85.42 R$/MWh
```

### Troubleshooting

#### "Validation failed" Error

**Problem**: Invalid input or conflicting parameters

**Solution**:
- Check min/max ranges in prompt
- Ensure min <= max for all parameters
- Verify referenced IDs exist

#### "Optimization failed" Error

**Problem**: Solver couldn't find solution

**Solution**:
- Increase time limit (e.g., 600 instead of 300)
- Relax MIP gap (e.g., 0.05 instead of 0.01)
- Check system has enough generation capacity
- Verify interconnections allow power flow

#### "Infeasible problem" Error

**Problem**: Constraints cannot be satisfied

**Solution**:
- Increase generation capacity
- Reduce minimum generation requirements
- Check renewable forecasts aren't too high
- Verify load can be met with available generation

---

## Developer Guide

### Code Structure

#### Main Components

```
wizard_example.jl
├── Utility Functions
│   ├── print_header()
│   ├── print_prompt()
│   ├── prompt()
│   ├── prompt_number()
│   ├── prompt_yes_no()
│   ├── prompt_choice()
│   └── show_help()
│
├── Wizard Steps (9 functions)
│   ├── step_1_system_basics()
│   ├── step_2_buses()
│   ├── step_3_submarkets()
│   ├── step_4_thermal_plants()
│   ├── step_5_hydro_plants()
│   ├── step_6_renewables()
│   ├── step_7_loads()
│   ├── step_8_interconnections()
│   └── step_9_solver_options()
│
├── Entity Creation Functions
│   ├── create_default_buses()
│   ├── create_default_submarkets()
│   ├── create_default_thermal_plants()
│   ├── create_default_hydro_plants()
│   ├── create_default_wind_farms()
│   ├── create_default_solar_farms()
│   ├── create_default_loads()
│   └── create_default_interconnections()
│
├── Orchestrator Functions
│   ├── display_summary()
│   ├── build_system()
│   ├── run_optimization()
│   └── display_results()
│
└── Main Entry Points
    ├── run_wizard()
    ├── quick_start()
    └── [main mode selection]
```

#### Adding a New Step

**1. Create step function**:

```julia
function step_10_storage()
    print_header("DEFINE ENERGY STORAGE", 10, wizard.total_steps)

    show_help("storage")

    n_storage = prompt_number(
        "How many battery storage systems?",
        0;
        type=Int,
        min=0,
        max=20,
        integer=true
    )

    if n_storage == 0
        wizard.config["storage"] = BatteryStorage[]
        println("\n✓ No storage systems created")
        return
    end

    create_simple = prompt_yes_no(
        "Create storage with default settings?",
        true
    )

    if create_simple
        wizard.config["storage"] = create_default_storage(
            n_storage,
            wizard.config["bus_names"],
            wizard.config["submarkets"]
        )
    end

    println("\n✓ Storage configured")
end
```

**2. Create default entity function**:

```julia
function create_default_storage(n::Int, bus_names::Vector{String},
                                submarkets::Vector{Submarket})
    storage = BatteryStorage[]

    for i in 1:n
        bus_idx = min(i, length(bus_names))
        sub_idx = min(i, length(submarkets))

        bat = BatteryStorage(;
            id = "BATT_$i",
            name = "Battery Storage $i",
            bus_id = bus_names[bus_idx],
            submarket_id = submarkets[sub_idx].code,
            capacity_mw = 100.0,
            energy_capacity_mwh = 400.0,
            initial_energy_mwh = 200.0,
            charge_efficiency = 0.90,
            discharge_efficiency = 0.90
        )
        push!(storage, bat)
    end

    return storage
end
```

**3. Add to orchestrator**:

```julia
function run_wizard()
    try
        step_1_system_basics()
        # ... existing steps ...
        step_9_solver_options()
        step_10_storage()  # New step

        display_summary()
        # ... rest of function
    end
end
```

**4. Update total steps**:

```julia
WizardState() = new(Dict{String, Any}(), 1, 10)  # Was 9
```

**5. Add help text**:

```julia
function show_help(topic::String)
    help_text = Dict(
        # ... existing topics ...
        "storage" => """
        STORAGE HELP:
        Battery storage systems provide energy time-shifting.
        ... (detailed information)
        """
    )
    # ... rest of function
end
```

**6. Update system builder**:

```julia
function build_system()::ElectricitySystem
    # ... existing code ...

    storage = get(wizard.config, "storage", BatteryStorage[])

    system = ElectricitySystem(;
        # ... existing parameters ...
        storage = storage,
        # ... rest of parameters ...
    )

    return system
end
```

#### Testing New Features

Use `test_wizard.jl` as a template:

```julia
println("\n13. Testing storage creation...")

storage = [
    BatteryStorage(;
        id = "BATT_1",
        name = "Battery 1",
        bus_id = "BUS_1",
        submarket_id = "N",
        capacity_mw = 100.0,
        # ... other parameters
    )
]

println("  ✓ Created $(length(storage)) storage systems")
```

### Code Style Guidelines

1. **Function Naming**
   - Step functions: `step_N_description()`
   - Creation functions: `create_default_entity()`
   - Helpers: `verb_noun()` (e.g., `print_header`)

2. **Variable Naming**
   - Use descriptive names
   - Abbreviations only when common (e.g., `sub` for submarket)
   - Avoid single-letter variables except in loops

3. **Error Handling**
   - Always validate user input
   - Provide helpful error messages
   - Use try-catch for external calls

4. **Documentation**
   - Every function needs a docstring
   - Include examples in docstrings
   - Comment complex logic

5. **Prompts**
   - Be clear and specific
   - Show valid ranges
   - Provide sensible defaults
   - Format consistently

---

## API Reference

### Core Functions

#### `prompt(prompt::String, default::String; validate::Function)`

Prompt user for text input.

**Parameters**:
- `prompt`: Question to ask
- `default`: Default value if Enter pressed
- `validate`: Optional validation function

**Returns**: User input or default

**Example**:
```julia
name = prompt("Enter system name", "My System")
```

#### `prompt_number(prompt::String, default::Number; ...)`

Prompt user for numeric input.

**Parameters**:
- `prompt`: Question to ask
- `default`: Default value
- `type`: Expected type (Int or Float64)
- `min`: Minimum allowed value (NaN = no minimum)
- `max`: Maximum allowed value (NaN = no maximum)
- `integer`: Enforce integer values

**Returns**: Parsed number

**Example**:
```julia
n_buses = prompt_number("How many buses?", 3;
                        type=Int, min=1, max=100)
```

#### `prompt_yes_no(prompt::String, default::Bool)`

Prompt user for yes/no response.

**Parameters**:
- `prompt`: Question to ask
- `default`: Default boolean value

**Returns**: Boolean

**Example**:
```julia
proceed = prompt_yes_no("Continue?", true)
```

#### `prompt_choice(prompt::String, options::Vector{String}, default_index::Int)`

Prompt user to choose from list.

**Parameters**:
- `prompt`: Question to ask
- `options`: List of choices
- `default_index`: Index of default (1-based)

**Returns**: Selected option string

**Example**:
```julia
voltage = prompt_choice("Select voltage",
                        ["69 kV", "138 kV", "230 kV"],
                        3)  # Defaults to 230 kV
```

### Step Functions

Each step function follows the pattern:
```julia
function step_N_description()
    print_header("DESCRIPTION", N, wizard.total_steps)

    # Optional: Show help
    show_help("topic")

    # Get count
    n = prompt_number("How many?", default;
                      type=Int, min=0, max=MAX, integer=true)

    # Handle zero case
    if n == 0
        wizard.config["key"] = EntityType[]
        return
    end

    # Ask for defaults or custom
    use_defaults = prompt_yes_no("Use defaults?", true)

    # Create entities
    if use_defaults
        wizard.config["key"] = create_default_entities(n, ...)
    else
        # Custom configuration (future)
    end

    println("\n✓ Configured")
end
```

### Entity Creation Functions

Default entity creators follow this pattern:
```julia
function create_default_entities(n::Int, dependencies...)::Vector{EntityType}
    entities = EntityType[]

    for i in 1:n
        # Select appropriate dependency
        idx = min(i, length(dependency))

        entity = EntityType(;
            id = "ENTITY_$i",
            name = "Entity $i",
            # ... parameters ...
            dependency_id = dependencies[idx].id,
            # ... more parameters ...
        )
        push!(entities, entity)
    end

    return entities
end
```

### System Building

#### `build_system() -> ElectricitySystem`

Builds the ElectricitySystem from wizard configuration.

**Returns**: Populated ElectricitySystem

**Process**:
1. Get entities from `wizard.config`
2. Add forecasts to renewables
3. Create ElectricitySystem
4. Validate references

#### `run_optimization(system::ElectricitySystem)`

Runs the two-stage optimization.

**Returns**: `(uc_result, sced_result)`

**Process**:
1. Create JuMP model
2. Add variables
3. Build constraints
4. Build objective
5. Solve (UC → SCED)
6. Return results

---

## Examples

### Example 1: Quick Start

```bash
$ julia --project=. examples/wizard_example.jl

Choose your mode:
  1. Interactive Wizard (guided step-by-step)
  2. Quick Start (simple 3-bus system)
  3. Exit

Enter choice [Default: 2]: [Enter]

[Creates and solves complete system]
```

### Example 2: Custom System

```bash
$ julia --project=. examples/wizard_example.jl

Choose your mode:
  1. Interactive Wizard (guided step-by-step)
  2. Quick Start (simple 3-bus system)
  3. Exit

Enter choice [Default: 2]: 1

======================================================================
STEP 1 of 9: SYSTEM BASICS
======================================================================

Enter a name for your system
[Default: My Power System]: Texas Grid

How many time periods (hours) to simulate?
[Default: 24]: 168

[... continues through all steps ...]
```

### Example 3: Minimal System

```julia
# Programmatically create minimal system

wizard.config["system_name"] = "Minimal"
wizard.config["time_periods"] = 24
wizard.config["n_buses"] = 1
wizard.config["n_submarkets"] = 1
wizard.config["n_thermal"] = 1
wizard.config["n_hydro"] = 0
wizard.config["n_wind"] = 0
wizard.config["n_solar"] = 0
wizard.config["n_loads"] = 1

# Build and solve
system = build_system()
uc_result, sced_result = run_optimization(system)
```

---

## See Also

- `examples/complete_workflow_example.jl` - Non-interactive example
- `examples/WIZARD_README.md` - Detailed user guide
- `WIZARD_FLOWCHART.md` - Visual flowcharts
- `WIZARD_IMPLEMENTATION_SUMMARY.md` - Technical details
- `src/entities/` - Entity type definitions
- `src/constraints/` - Constraint building
- `docs/guide.md` - Full OpenDESSEM guide
