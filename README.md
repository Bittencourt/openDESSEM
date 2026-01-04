# OpenDESSEM

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia 1.10](https://img.shields.io/badge/Julia-1.10-blue.svg)](https://julialang.org/)
[![codecov](https://codecov.io/gh/your-org/openDESSEM/branch/main/graph/badge.svg)](https://codecov.io/gh/your-org/openDESSEM)

**Open-source implementation of DESSEM** (Daily Short-Term Hydrothermal Scheduling Model) in Julia using JuMP.

## Overview

OpenDESSEM is a Julia-based implementation of Brazil's official day-ahead hydrothermal dispatch optimization model (DESSEM - Modelo de Programação Diária da Operação de Sistemas Hidrotérmicos). This project aims to provide a transparent, reproducible, and extensible version for research, validation, and innovation in short-term electricity market optimization.

### Key Features

- 🏗️ **Entity-Driven Architecture** - Model dynamically builds itself from system entities
- 💾 **Database-Ready** - Native PostgreSQL support with SQLite for development
- 🔧 **Modular Constraints** - Pluggable constraint system for extensibility
- 🌊 **Full Hydro Modeling** - Cascade reservoirs with time delays and spillage
- 🔥 **Thermal Unit Commitment** - Complete UC with ramp rates and min up/down times
- ⚡ **Network Model** - DC-OPF and AC-OPF using PowerModels.jl (proven formulations)
- 📊 **Renewable Integration** - Wind, solar, and hybrid plants with forecasting
- 🎯 **Brazilian Market Compatible** - PLD calculation and CCEE output formats

## Quick Start

### Installation

```julia
# Clone the repository
git clone https://github.com/your-org/openDESSEM.git
cd openDESSEM

# Install Julia dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Basic Usage

```julia
using OpenDESSEM

# Load system from database
loader = DatabaseLoader(
    connection = LibPQ.Connection("dbname=opendessem"),
    scenario_id = "deterministic",
    base_date = Date("2024-01-15")
)
system = load_system(loader)

# Create optimization model
model = DessemModel(system, time_periods=168, discretization=:hourly)

# Add constraints
add_constraint!(model, EnergyBalanceConstraint(...))
add_constraint!(model, ThermalUnitCommitmentConstraint(...))
add_constraint!(model, HydroWaterBalanceConstraint(...))
add_constraint!(model, PowerModelsDCOPFConstraint(...))  # Using PowerModels.jl

# Build and solve
create_variables!(model)
build_objective!(model)
solution = optimize!(model, HiGHS.Optimizer)

# Extract results
dispatch = extract_dispatch(solution)
prices = calculate_marginal_costs(solution)  # PLD
```

## Documentation

- [**Quick Reference**](docs/QUICK_REFERENCE.md) - Essential commands and workflows
- [**Technical Plan**](docs/01_DETAILED_TECHNICAL_PLAN.md) - Complete architecture and implementation plan
- [**Original Planning Document**](docs/DESSEM_Planning_Document.md) - Background and problem definition
- [**Development Guidelines**](.claude/claude.md) - Development rules and best practices

## Project Structure

```
openDESSEM/
├── src/               # Source code
│   ├── core/          # Core model structures
│   ├── entities/      # Entity type definitions
│   ├── constraints/   # Constraint implementations
│   ├── data/          # Data loading (database, files)
│   ├── solvers/       # Solver interfaces
│   └── analysis/      # Results and visualization
├── test/              # Test suites (TDD)
├── database/          # Database schema and migrations
├── examples/          # Example scripts
├── docs/              # Documentation
└── scripts/           # Development utilities
```

## Development Status

### Phase 1: Foundation (Planned)
- [ ] Entity type system
- [ ] Database schema
- [ ] Variable manager
- [ ] Basic constraints

### Phase 2: Core Model (Planned)
- [ ] Thermal unit commitment
- [ ] Hydro water balance
- [ ] Energy balance
- [ ] DC-OPF network model

### Phase 3: Advanced Features (Planned)
- [ ] Combined-cycle plants
- [ ] AC-OPF with MILP relaxation
- [ ] Renewable integration
- [ ] Stochastic programming

## Technology Stack

- **Language**: Julia 1.10+
- **Optimization**: JuMP.jl
- **Network Constraints**: PowerModels.jl (DC-OPF, AC-OPF formulations)
- **Data Parsing**: PWF.jl (Brazilian .pwf file support)
- **Solvers**: HiGHS.jl (open-source), Gurobi.jl (optional)
- **Database**: PostgreSQL (production), SQLite (development)
- **Testing**: Test.jl
- **Documentation**: Documenter.jl

## Background

DESSEM is Brazil's official day-ahead hydrothermal dispatch model, operated by ONS (Operador Nacional do Sistema Elétrico) and CCEE (Câmara de Comercialização de Energia Elétrica) since January 2020. It solves the daily energy dispatch problem for:

- **Temporal scope**: 1-14 days with hourly/half-hourly discretization
- **Spatial scope**: Brazilian Interconnected System (SIN)
  - ~158 hydro plants
  - ~109 thermal plants
  - 4 submarkets (N, NE, SE/CO, S)
  - ~6,450 buses
  - ~8,850 transmission lines

For more details, see the [planning document](docs/DESSEM_Planning_Document.md).

## Contributing

We welcome contributions! Please see:

1. [Development Guidelines](.claude/claude.md) - TDD, commit conventions, code style
2. [Quick Reference](docs/QUICK_REFERENCE.md) - Essential commands
3. [Technical Plan](docs/01_DETAILED_TECHNICAL_PLAN.md) - Architecture overview

### Development Workflow

```bash
# 1. Write tests first (TDD)
# 2. Implement feature
# 3. Run tests
julia --project=test test/runtests.jl

# 4. Clean and check
./scripts/clean_before_commit.sh
julia scripts/pre_commit_check.jl

# 5. Commit
git commit -m "feat(scope): description"
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **ONS** - Operador Nacional do Sistema Elétrico (Brazilian System Operator)
- **CCEE** - Câmara de Comercialização de Energia Elétrica (Electricity Trading Chamber)
- **CEPEL** - Centro de Pesquisas de Energia Elétrica (original DESSEM developers)
- **JuMP.dev** - Optimization modeling in Julia

## References

- Diniz, A.L., et al. (2020). "Hourly pricing and day-ahead dispatch setting in Brazil: The DESSEM model". *Electric Power Systems Research*.
- [Official DESSEM Documentation](https://www.ons.org.br/)
- [CCEE Market Rules](https://www.ccee.org.br/)

## Contact

- **Issues**: [GitHub Issues](https://github.com/your-org/openDESSEM/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/openDESSEM/discussions)

---

**Status**: 🚧 Under Active Development

**Note**: This is an independent open-source project and is not affiliated with or endorsed by ONS, CCEE, or CEPEL.
