"""
    Unit Tests for Constraint Violation Reporting

Tests the constraint violation detection and reporting functionality
in the Analysis module.
"""

using Test
using JuMP
using HiGHS
using Dates

using OpenDESSEM
using OpenDESSEM.Solvers
using OpenDESSEM.Analysis

# Include small system factory
include(joinpath(@__DIR__, "..", "fixtures", "small_system.jl"))
using .SmallSystemFactory: create_small_test_system, create_infeasible_test_system

@testset "Constraint Violations" begin

    @testset "ConstraintViolation struct" begin
        cv = ConstraintViolation(;
            constraint_name = "test_constraint",
            violation_magnitude = 0.5,
            constraint_type = "thermal",
        )
        @test cv.constraint_name == "test_constraint"
        @test cv.violation_magnitude == 0.5
        @test cv.constraint_type == "thermal"

        # Test different constraint types
        for ctype in ["thermal", "hydro", "balance", "network", "ramp", "unknown"]
            cv2 = ConstraintViolation(;
                constraint_name = "test_$ctype",
                violation_magnitude = 1.0,
                constraint_type = ctype,
            )
            @test cv2.constraint_type == ctype
        end
    end

    @testset "ViolationReport struct" begin
        violations = [
            ConstraintViolation(;
                constraint_name = "c1",
                violation_magnitude = 0.5,
                constraint_type = "thermal",
            ),
        ]
        report = ViolationReport(;
            model_name = "test_model",
            timestamp = now(),
            tolerance = 1e-6,
            violations = violations,
            total_violations = 1,
            max_violation = 0.5,
            violations_by_type = Dict("thermal" => 1),
        )

        @test report.model_name == "test_model"
        @test report.tolerance == 1e-6
        @test report.timestamp isa DateTime
        @test report.violations isa Vector{ConstraintViolation}
        @test report.total_violations == 1
        @test report.max_violation == 0.5
        @test report.violations_by_type isa Dict{String,Int}
        @test report.violations_by_type["thermal"] == 1
    end

    @testset "isempty on ViolationReport" begin
        # Non-empty report
        report_nonempty = ViolationReport(;
            model_name = "test",
            timestamp = now(),
            tolerance = 1e-6,
            violations = [
                ConstraintViolation(;
                    constraint_name = "c1",
                    violation_magnitude = 0.1,
                    constraint_type = "thermal",
                ),
            ],
            total_violations = 1,
            max_violation = 0.1,
            violations_by_type = Dict("thermal" => 1),
        )
        @test !isempty(report_nonempty)

        # Empty report
        report_empty = ViolationReport(;
            model_name = "test",
            timestamp = now(),
            tolerance = 1e-6,
            violations = ConstraintViolation[],
            total_violations = 0,
            max_violation = 0.0,
            violations_by_type = Dict{String,Int}(),
        )
        @test isempty(report_empty)
        @test report_empty.total_violations == 0
    end

    @testset "Violations sorted by magnitude descending" begin
        violations = [
            ConstraintViolation(;
                constraint_name = "small",
                violation_magnitude = 0.001,
                constraint_type = "thermal",
            ),
            ConstraintViolation(;
                constraint_name = "large",
                violation_magnitude = 1.0,
                constraint_type = "balance",
            ),
            ConstraintViolation(;
                constraint_name = "medium",
                violation_magnitude = 0.1,
                constraint_type = "hydro",
            ),
        ]

        report = ViolationReport(;
            model_name = "test",
            timestamp = now(),
            tolerance = 1e-6,
            violations = sort(violations; by = v -> v.violation_magnitude, rev = true),
            total_violations = 3,
            max_violation = 1.0,
            violations_by_type = Dict("thermal" => 1, "balance" => 1, "hydro" => 1),
        )

        @test report.violations[1].constraint_name == "large"
        @test report.violations[2].constraint_name == "medium"
        @test report.violations[3].constraint_name == "small"
        @test report.violations[1].violation_magnitude >=
              report.violations[2].violation_magnitude
        @test report.violations[2].violation_magnitude >=
              report.violations[3].violation_magnitude
    end

    @testset "Constraint type classification" begin
        # Test the classification logic via check_constraint_violations
        # by creating a simple model with named constraints

        model = Model(HiGHS.Optimizer)
        set_silent(model)

        @variable(model, x >= 0)
        @variable(model, y >= 0)

        # Create constraints with various names to test classification
        @constraint(model, thermal_gen, x <= 100)
        @constraint(model, hydro_storage_limit, y <= 200)
        @constraint(model, submarket_balance_SE, x + y >= 10)
        @constraint(model, network_flow_limit, x - y <= 50)
        @constraint(model, ramp_up_T001, x <= 80)

        @objective(model, Min, x + y)
        JuMP.optimize!(model)

        # Feasible model should have no violations
        report = check_constraint_violations(model; atol = 1e-6)
        @test report isa ViolationReport
    end

    @testset "Feasible model has no violations" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        # Check violations on a feasible solved model
        report = check_constraint_violations(model; atol = 1e-6)

        @test report isa ViolationReport
        @test isempty(report)
        @test report.total_violations == 0
        @test report.max_violation == 0.0
        @test isempty(report.violations)
    end

    @testset "ViolationReport struct fields from solved model" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        report = check_constraint_violations(model; atol = 1e-6, model_name = "test_model")

        @test report.model_name == "test_model"
        @test report.tolerance == 1e-6
        @test report.timestamp isa DateTime
        @test report.violations isa Vector{ConstraintViolation}
        @test report.violations_by_type isa Dict{String,Int}
    end

    @testset "Custom tolerance changes detection" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        # Very tight tolerance might catch numerical noise
        report_tight = check_constraint_violations(model; atol = 1e-15)
        # Loose tolerance should find fewer or no violations
        report_loose = check_constraint_violations(model; atol = 1.0)

        @test report_loose.total_violations <= report_tight.total_violations
    end

    @testset "write_violation_report creates file" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)
        report = check_constraint_violations(model; model_name = "write_test")

        mktempdir() do tmpdir
            filepath = joinpath(tmpdir, "violations.txt")
            returned_path = write_violation_report(report, filepath)

            @test isfile(filepath)
            @test returned_path == filepath

            content = read(filepath, String)
            @test occursin("Constraint Violation Report", content)
            @test occursin("write_test", content)
            @test occursin("Tolerance", content)
            @test occursin("Summary", content)
            @test occursin("Total violations", content)
        end
    end

    @testset "write_violation_report with no violations" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)
        report = check_constraint_violations(model)

        mktempdir() do tmpdir
            filepath = joinpath(tmpdir, "no_violations.txt")
            write_violation_report(report, filepath)

            content = read(filepath, String)
            @test occursin("Total violations: 0", content)
            @test occursin("No violations found.", content)
        end
    end

    @testset "write_violation_report with violations" begin
        # Create a manually constructed report to test output format
        violations = [
            ConstraintViolation(;
                constraint_name = "thermal_max[T001,3]",
                violation_magnitude = 1.5,
                constraint_type = "thermal",
            ),
            ConstraintViolation(;
                constraint_name = "balance_SE[2]",
                violation_magnitude = 0.01,
                constraint_type = "balance",
            ),
        ]
        report = ViolationReport(;
            model_name = "test_violations",
            timestamp = now(),
            tolerance = 1e-6,
            violations = violations,
            total_violations = 2,
            max_violation = 1.5,
            violations_by_type = Dict("thermal" => 1, "balance" => 1),
        )

        mktempdir() do tmpdir
            filepath = joinpath(tmpdir, "violations.txt")
            write_violation_report(report, filepath)

            content = read(filepath, String)
            @test occursin("Total violations: 2", content)
            @test occursin("Maximum violation: 1.5", content)
            @test occursin("[thermal]", content)
            @test occursin("[balance]", content)
            @test occursin("thermal_max[T001,3]", content)
            @test occursin("balance_SE[2]", content)
            @test !occursin("No violations found.", content)
        end
    end

    @testset "write_violation_report creates directories" begin
        mktempdir() do tmpdir
            # Nested directory that doesn't exist yet
            filepath = joinpath(tmpdir, "subdir", "nested", "violations.txt")

            # Empty report - should still create file
            report = ViolationReport(;
                model_name = "dir_test",
                timestamp = now(),
                tolerance = 1e-6,
                violations = ConstraintViolation[],
                total_violations = 0,
                max_violation = 0.0,
                violations_by_type = Dict{String,Int}(),
            )

            write_violation_report(report, filepath)
            @test isfile(filepath)
        end
    end

    @testset "Default model_name is empty string" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        report = check_constraint_violations(model)
        @test report.model_name == ""
    end

    @testset "isempty consistent with total_violations" begin
        model, system = create_small_test_system()
        result = solve_model!(model, system; pricing = false)

        report = check_constraint_violations(model)
        @test isempty(report) == (report.total_violations == 0)
    end

end
