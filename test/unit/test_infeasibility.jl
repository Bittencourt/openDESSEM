"""
    Tests for Infeasibility Diagnostics Module

Tests for IIS (Irreducible Inconsistent Subsystem) computation and reporting.

# Test Coverage
1. IISConflict struct construction and validation
2. IISResult struct construction and validation
3. compute_iis!() on infeasible models
4. compute_iis!() on non-infeasible models (warning, no error)
5. write_iis_report() generates correct files
6. Report content validation
"""

using Test
using JuMP
using HiGHS
import MathOptInterface as MOI
using Dates

using OpenDESSEM.Solvers
using OpenDESSEM.Solvers: IISConflict, IISResult, compute_iis!, write_iis_report,
    _get_solver_name, _constraint_to_string

@testset "Infeasibility Diagnostics Tests" begin
    
    @testset "IISConflict Struct Tests" begin
        
        @testset "Constructor with all fields" begin
            # Create a simple model for testing constraint refs
            model = Model(HiGHS.Optimizer)
            @variable(model, x >= 0)
            @constraint(model, con, x <= 10)
            
            conflict = IISConflict(
                constraint_ref = con,
                constraint_name = "test_constraint",
                expression = "x <= 10",
                lower_bound = nothing,
                upper_bound = 10.0
            )
            
            @test conflict.constraint_ref !== nothing
            @test conflict.constraint_name == "test_constraint"
            @test conflict.expression == "x <= 10"
            @test conflict.lower_bound === nothing
            @test conflict.upper_bound == 10.0
        end
        
        @testset "Constructor with variable bound conflict" begin
            conflict = IISConflict(
                constraint_ref = nothing,
                constraint_name = "variable_bounds[x]",
                expression = "0 <= x <= -5",
                lower_bound = 0.0,
                upper_bound = -5.0
            )
            
            @test conflict.constraint_ref === nothing
            @test conflict.constraint_name == "variable_bounds[x]"
            @test conflict.lower_bound == 0.0
            @test conflict.upper_bound == -5.0
        end
        
        @testset "Default values for bounds" begin
            conflict = IISConflict(
                constraint_ref = nothing,
                constraint_name = "equality_constraint",
                expression = "x == 5"
            )
            
            @test conflict.lower_bound === nothing
            @test conflict.upper_bound === nothing
        end
        
        @testset "Equality constraint bounds" begin
            conflict = IISConflict(
                constraint_ref = nothing,
                constraint_name = "eq_con",
                expression = "x == 5",
                lower_bound = 5.0,
                upper_bound = 5.0
            )
            
            @test conflict.lower_bound == 5.0
            @test conflict.upper_bound == 5.0
        end
    end
    
    @testset "IISResult Struct Tests" begin
        
        @testset "Constructor with default values" begin
            result = IISResult(status = MOI.NO_CONFLICT_FOUND)
            
            @test result.status == MOI.NO_CONFLICT_FOUND
            @test isempty(result.conflicts)
            @test result.computation_time == 0.0
            @test result.solver_used == "unknown"
            @test result.report_file === nothing
        end
        
        @testset "Constructor with all fields" begin
            conflicts = [
                IISConflict(
                    constraint_ref = nothing,
                    constraint_name = "c1",
                    expression = "x <= 5"
                )
            ]
            
            result = IISResult(
                status = MOI.CONFLICT_FOUND,
                conflicts = conflicts,
                computation_time = 0.5,
                solver_used = "Gurobi",
                report_file = "logs/iis_report.txt"
            )
            
            @test result.status == MOI.CONFLICT_FOUND
            @test length(result.conflicts) == 1
            @test result.computation_time == 0.5
            @test result.solver_used == "Gurobi"
            @test result.report_file == "logs/iis_report.txt"
        end
        
        @testset "Empty conflicts vector" begin
            result = IISResult(
                status = MOI.CONFLICT_FOUND,
                conflicts = IISConflict[]
            )
            
            @test isempty(result.conflicts)
        end
        
        @testset "Multiple conflicts" begin
            conflicts = [
                IISConflict(constraint_ref = nothing, constraint_name = "c1", expression = "x >= 10"),
                IISConflict(constraint_ref = nothing, constraint_name = "c2", expression = "x <= 5"),
                IISConflict(constraint_ref = nothing, constraint_name = "bounds[y]", expression = "0 <= y <= -1")
            ]
            
            result = IISResult(
                status = MOI.CONFLICT_FOUND,
                conflicts = conflicts
            )
            
            @test length(result.conflicts) == 3
        end
    end
    
    @testset "compute_iis! Function Tests" begin
        
        @testset "Returns IISResult on any model" begin
            model = Model(HiGHS.Optimizer)
            @variable(model, x >= 0)
            @objective(model, Min, x)
            
            # Should return IISResult even on unsolved model (with warning)
            result = compute_iis!(model; auto_report = false)
            
            @test result isa IISResult
            @test result.solver_used isa String
            @test result.computation_time >= 0.0
        end
        
        @testset "Non-infeasible model warning" begin
            model = Model(HiGHS.Optimizer)
            @variable(model, 0 <= x <= 10)
            @objective(model, Min, x)
            
            # This should log a warning but not error
            result = compute_iis!(model; auto_report = false)
            
            @test result isa IISResult
        end
        
        @testset "Trivially infeasible model" begin
            # Create a model that is clearly infeasible
            model = Model(HiGHS.Optimizer)
            set_silent(model)
            @variable(model, 10 <= x <= 5)  # lower > upper = infeasible
            @objective(model, Min, x)
            
            JuMP.optimize!(model)
            
            # Model should be infeasible
            @test termination_status(model) in [MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED]
            
            # Call compute_iis! - should work (though HiGHS has limited IIS support)
            result = compute_iis!(model; auto_report = false)
            
            @test result isa IISResult
            @test result.status isa MOI.ConflictStatusCode
        end
        
        @testset "Auto-report disabled" begin
            model = Model(HiGHS.Optimizer)
            set_silent(model)
            @variable(model, 0 <= x <= 10)
            @objective(model, Min, x)
            JuMP.optimize!(model)
            
            result = compute_iis!(model; auto_report = false)
            
            # With auto_report=false, no report file should be generated
            @test result.report_file === nothing
        end
    end
    
    @testset "write_iis_report Function Tests" begin
        
        @testset "Creates report file" begin
            result = IISResult(
                status = MOI.CONFLICT_FOUND,
                conflicts = [
                    IISConflict(
                        constraint_ref = nothing,
                        constraint_name = "c1",
                        expression = "x >= 10"
                    ),
                    IISConflict(
                        constraint_ref = nothing,
                        constraint_name = "c2",
                        expression = "x <= 5"
                    )
                ],
                computation_time = 0.123,
                solver_used = "Gurobi"
            )
            
            output_dir = mktempdir()
            report_path = write_iis_report(result; output_dir = output_dir)
            
            @test isfile(report_path)
            @test startswith(report_path, output_dir)
            
            # Read and verify content
            content = read(report_path, String)
            @test contains(content, "IIS Report")
            @test contains(content, "Gurobi")
            @test contains(content, "c1")
            @test contains(content, "c2")
            @test contains(content, "x >= 10")
            @test contains(content, "x <= 5")
            
            # Cleanup
            rm(output_dir; recursive = true)
        end
        
        @testset "Auto-generated filename with timestamp" begin
            result = IISResult(status = MOI.CONFLICT_FOUND)
            
            output_dir = mktempdir()
            report_path = write_iis_report(result; output_dir = output_dir)
            
            # Check filename contains timestamp pattern
            filename = basename(report_path)
            @test startswith(filename, "iis_report_")
            @test endswith(filename, ".txt")
            @test contains(filename, r"\d{8}_\d{6}")  # YYYYMMDD_HHMMSS pattern
            
            rm(output_dir; recursive = true)
        end
        
        @testset "Custom filename" begin
            result = IISResult(status = MOI.CONFLICT_FOUND)
            
            output_dir = mktempdir()
            custom_name = "my_custom_report.txt"
            report_path = write_iis_report(result; output_dir = output_dir, filename = custom_name)
            
            @test basename(report_path) == custom_name
            
            rm(output_dir; recursive = true)
        end
        
        @testset "Not found status report" begin
            result = IISResult(
                status = MOI.NO_CONFLICT_FOUND,
                solver_used = "HiGHS"
            )
            
            output_dir = mktempdir()
            report_path = write_iis_report(result; output_dir = output_dir)
            
            content = read(report_path, String)
            @test contains(content, "NO_CONFLICT_FOUND")
            
            rm(output_dir; recursive = true)
        end
        
        @testset "Creates output directory" begin
            result = IISResult(status = MOI.CONFLICT_FOUND)
            
            output_dir = joinpath(mktempdir(), "new_subdir")
            @test !isdir(output_dir)
            
            report_path = write_iis_report(result; output_dir = output_dir)
            
            @test isdir(output_dir)
            @test isfile(report_path)
            
            rm(dirname(output_dir); recursive = true)
        end
        
        @testset "Report contains troubleshooting guide" begin
            result = IISResult(
                status = MOI.CONFLICT_FOUND,
                conflicts = [
                    IISConflict(constraint_ref = nothing, constraint_name = "test", expression = "test")
                ]
            )
            
            output_dir = mktempdir()
            report_path = write_iis_report(result; output_dir = output_dir)
            
            content = read(report_path, String)
            @test contains(content, "TROUBLESHOOTING GUIDE")
            @test contains(content, "CAPACITY MISMATCH")
            @test contains(content, "DEMAND IMBALANCE")
            @test contains(content, "NETWORK CONSTRAINTS")
            @test contains(content, "HYDRO CASCADE")
            @test contains(content, "UNIT COMMITMENT")
            
            rm(output_dir; recursive = true)
        end
        
        @testset "Report with no conflicts" begin
            result = IISResult(
                status = MOI.CONFLICT_FOUND,
                conflicts = IISConflict[]
            )
            
            output_dir = mktempdir()
            report_path = write_iis_report(result; output_dir = output_dir)
            
            content = read(report_path, String)
            @test contains(content, "Number of conflicting elements: 0")
            
            rm(output_dir; recursive = true)
        end
    end
    
    @testset "Helper Function Tests" begin
        
        @testset "_get_solver_name extracts solver name" begin
            model = Model(HiGHS.Optimizer)
            solver_name = _get_solver_name(model)
            
            @test solver_name isa String
            @test solver_name != "unknown"
        end
        
        @testset "_constraint_to_string handles simple constraints" begin
            model = Model()
            @variable(model, x)
            @constraint(model, con, x <= 10)
            
            expr_str = _constraint_to_string(con)
            
            @test expr_str isa String
            @test !isempty(expr_str)
        end
        
        @testset "_constraint_to_string handles equality constraints" begin
            model = Model()
            @variable(model, x)
            @constraint(model, con, x == 5)
            
            expr_str = _constraint_to_string(con)
            
            @test expr_str isa String
            @test contains(expr_str, "==")
        end
        
        @testset "_constraint_to_string handles greater than constraints" begin
            model = Model()
            @variable(model, x)
            @constraint(model, con, x >= 3)
            
            expr_str = _constraint_to_string(con)
            
            @test expr_str isa String
            @test contains(expr_str, ">=")
        end
    end
    
    @testset "Integration Tests" begin
        
        @testset "End-to-end with infeasible LP" begin
            model = Model(HiGHS.Optimizer)
            set_silent(model)
            
            @variable(model, x >= 0)
            @variable(model, y >= 0)
            @constraint(model, c1, x + y >= 10)
            @constraint(model, c2, x <= 3)
            @constraint(model, c3, y <= 3)
            @objective(model, Min, x + y)
            
            JuMP.optimize!(model)
            
            # This should be infeasible (can't have x+y >= 10 when both <= 3)
            @test termination_status(model) in [MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED]
            
            # Compute IIS
            result = compute_iis!(model; auto_report = false)
            
            @test result isa IISResult
            @test result.computation_time >= 0.0
            @test result.solver_used isa String
        end
        
        @testset "Report auto-generation with compute_iis!" begin
            model = Model(HiGHS.Optimizer)
            set_silent(model)
            
            @variable(model, 0 <= x <= 10)
            @objective(model, Min, x)
            JuMP.optimize!(model)
            
            output_dir = mktempdir()
            
            # Even though not infeasible, test the auto_report mechanism
            result = compute_iis!(model; auto_report = true)
            
            # Should not generate report for non-infeasible model
            # or for models where IIS not supported and no conflicts
            @test result isa IISResult
            
            rm(output_dir; recursive = true, force = true)
        end
    end
    
    @testset "Edge Cases" begin
        
        @testset "Empty model" begin
            model = Model(HiGHS.Optimizer)
            
            result = compute_iis!(model; auto_report = false)
            
            @test result isa IISResult
        end
        
        @testset "Model with no constraints" begin
            model = Model(HiGHS.Optimizer)
            @variable(model, x >= 0)
            @objective(model, Min, x)
            
            result = compute_iis!(model; auto_report = false)
            
            @test result isa IISResult
        end
        
        @testset "Large number of conflicts" begin
            # Create result with many conflicts
            conflicts = [
                IISConflict(
                    constraint_ref = nothing,
                    constraint_name = "constraint_$i",
                    expression = "x[$i] >= 0"
                ) for i in 1:100
            ]
            
            result = IISResult(
                status = MOI.CONFLICT_FOUND,
                conflicts = conflicts
            )
            
            output_dir = mktempdir()
            report_path = write_iis_report(result; output_dir = output_dir)
            
            @test isfile(report_path)
            content = read(report_path, String)
            @test contains(content, "constraint_1")
            @test contains(content, "constraint_100")
            @test contains(content, "Number of conflicting elements: 100")
            
            rm(output_dir; recursive = true)
        end
    end
end
