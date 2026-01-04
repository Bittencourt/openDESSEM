"""
    OpenDESSEM Test Suite

Runs all tests for the OpenDESSEM project.
"""

using OpenDESSEM
using Test

# Run all test files
@testset "OpenDESSEM Tests" begin

    # Entity tests
    include("unit/test_entities_base.jl")
    include("unit/test_thermal_entities.jl")
    include("unit/test_hydro_entities.jl")
    include("unit/test_renewable_entities.jl")
    include("unit/test_network_entities.jl")

    # More tests will be added as we implement:
    # include("unit/test_market_entities.jl")

    # Integration tests
    # include("integration/test_simple_system.jl")

end
