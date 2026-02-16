"""
    OpenDESSEM Test Suite

Runs all tests for the OpenDESSEM project.
"""

# Import OpenDESSEM without polluting Main with re-exported DESSEM2Julia names.
# Individual test files import from specific submodules (Entities, Constraints, etc.)
# to avoid name ambiguity between OpenDESSEM and DESSEM2Julia.
import OpenDESSEM
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

    # End-to-end integration tests
    include("integration/test_solver_end_to_end.jl")

end
