"""
    OpenDESSEM Test Suite

Runs all tests for the OpenDESSEM project.
"""

# Import OpenDESSEM and Solvers to make exports available for included test files
using OpenDESSEM
using OpenDESSEM.Solvers
using Test

# Run all test files
@testset "OpenDESSEM Tests" begin

    # Entity tests
    include("unit/test_entities_base.jl")
    include("unit/test_thermal_entities.jl")
    include("unit/test_hydro_entities.jl")
    include("unit/test_renewable_entities.jl")
    include("unit/test_network_entities.jl")
    include("unit/test_market_entities.jl")

    # Core tests
    include("unit/test_electricity_system.jl")

    # Utility tests
    include("unit/test_cascade_topology.jl")

    # Integration tests
    include("unit/test_powermodels_adapter.jl")
    # include("integration/test_simple_system.jl")

    # Variable manager tests
    include("unit/test_variable_manager.jl")

    # DESSEM loader tests
    include("unit/test_dessem_loader.jl")

    # Database loader tests
    include("integration/test_database_loader.jl")

    # Constraint tests
    include("unit/test_constraints.jl")
    include("unit/test_hydro_water_balance.jl")

    # Integration tests for constraints
    include("integration/test_constraint_system.jl")

    # Objective function tests
    include("unit/test_production_cost_objective.jl")

    # Solver interface tests
    include("unit/test_solver_interface.jl")

    # Infeasibility diagnostics tests
    include("unit/test_infeasibility.jl")

    # Solution extraction and export tests
    include("unit/test_solution_extraction.jl")
    include("unit/test_solution_exporter.jl")

    # End-to-end integration tests
    include("integration/test_solver_end_to_end.jl")

    # Constraint violation reporting tests
    include("unit/test_constraint_violations.jl")

end
