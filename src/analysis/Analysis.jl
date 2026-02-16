"""
    Analysis Module for OpenDESSEM

Provides solution export and analysis capabilities.

# Components
- `SolutionExporter`: Export results to CSV, JSON, and database formats
- Constraint violation reporting: Detect, classify, and report constraint violations

# Example
```julia
using OpenDESSEM.Analysis

# Export to CSV
files = export_csv(result, "results/"; time_periods=1:24)

# Export to JSON
filepath = export_json(result, "results/solution.json"; time_periods=1:24)

# Check constraint violations
report = check_constraint_violations(model; atol=1e-6)
if !isempty(report)
    write_violation_report(report, "violations.txt")
end
```
"""

module Analysis

using JuMP

# Import SolverResult from parent module's Solvers submodule
# This is available because OpenDESSEM.jl includes Solvers before Analysis
import ..Solvers: SolverResult

include("solution_exporter.jl")

using .SolutionExporter

# Constraint violation reporting (defined at Analysis module level, not a submodule)
include("constraint_violations.jl")

export
    # Main export functions
    export_csv,
    export_json,
    export_database,

    # Types
    ExportResult,

    # Constraint violation types and functions
    ConstraintViolation,
    ViolationReport,
    check_constraint_violations,
    write_violation_report

end # module
