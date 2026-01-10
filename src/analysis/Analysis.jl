"""
    Analysis Module for OpenDESSEM

Provides solution export and analysis capabilities.

# Components
- `SolutionExporter`: Export results to CSV, JSON, and database formats

# Example
```julia
using OpenDESSEM.Analysis

# Export to CSV
files = export_csv(result, "results/"; time_periods=1:24)

# Export to JSON
filepath = export_json(result, "results/solution.json"; time_periods=1:24)
```
"""

module Analysis

# Import SolverResult from parent module's Solvers submodule
# This is available because OpenDESSEM.jl includes Solvers before Analysis
import ..Solvers: SolverResult

include("solution_exporter.jl")

using .SolutionExporter

export
    # Main export functions
    export_csv,
    export_json,
    export_database,

    # Types
    ExportResult

end # module
