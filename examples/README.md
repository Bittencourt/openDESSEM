# OpenDESSEM Examples

This directory contains example scripts and tutorials demonstrating how to use OpenDESSEM.

## Interactive Wizard

The best way to get started:

- **[WIZARD_README.md](WIZARD_README.md)** - Complete wizard user guide
- **[wizard_example.jl](wizard_example.jl)** - Interactive system builder
- **[wizard_transcript.jl](wizard_transcript.jl)** - Example session

### Using the Wizard

```bash
julia --project=. examples/wizard_example.jl
```

Choose between:
1. **Interactive Mode** - Step-by-step guided configuration
2. **Quick Start** - Instant 3-bus system

## Other Examples

- **[ons_data_example.jl](ons_data_example.jl)** - Loading ONS sample data
- **[complete_workflow_example.jl](complete_workflow_example.jl)** (if exists) - Full workflow

## Wizard Documentation

Detailed wizard documentation is in [docs/](docs/):
- [docs/WIZARD_INDEX.md](docs/WIZARD_INDEX.md) - Documentation index
- [docs/WIZARD_FLOWCHART.md](docs/WIZARD_FLOWCHART.md) - Visual flowcharts
- [docs/WIZARD_IMPLEMENTATION_SUMMARY.md](docs/WIZARD_IMPLEMENTATION_SUMMARY.md) - Implementation details

## Running Examples

### Prerequisites

```bash
# Install dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Run an Example

```bash
# Interactive wizard
julia --project=. examples/wizard_example.jl

# Other examples
julia --project=. examples/ons_data_example.jl
```

## Example Structure

Each example demonstrates:
1. **Data loading** - From database, files, or wizard
2. **System creation** - Building ElectricitySystem
3. **Model setup** - Creating optimization model
4. **Constraint building** - Adding constraints
5. **Optimization** - Solving the model
6. **Results** - Extracting and displaying results

## Creating Your Own Example

Template structure:

```julia
using OpenDESSEM
using OpenDESSEM.Entities
using OpenDESSEM.Constraints
using OpenDESSEM.Variables
using OpenDESSEM.Objective
using OpenDESSEM.Solvers

# 1. Create or load system
system = ...

# 2. Create model
model = create_model(system, solver=HiGHS.Optimizer)

# 3. Add variables
create_all_variables!(model, system, 1:24)

# 4. Add constraints
add_constraints!(model, system, constraints)

# 5. Build objective
build_objective!(model, system)

# 6. Solve
optimize!(model)

# 7. Extract results
results = extract_solution(model, system)
```

## Need Help?

- **Wizard help**: See [WIZARD_README.md](WIZARD_README.md)
- **API documentation**: See [../docs/INDEX.md](../docs/INDEX.md)
- **Development guide**: See [../.claude/CLAUDE.md](../.claude/CLAUDE.md)
- **Quick reference**: See [../docs/QUICK_REFERENCE.md](../docs/QUICK_REFERENCE.md)

---

**Last Updated**: 2026-02-15
