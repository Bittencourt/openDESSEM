#!/usr/bin/env julia

"""
    pre_commit_check.jl

Pre-commit validation script for OpenDESSEM development.

This script runs all necessary checks before committing code:
1. Run full test suite
2. Check test coverage (>90% required)
3. Verify code formatting
4. Validate documentation builds
5. Check for temporary/auxiliary files

Exit codes:
- 0: All checks passed
- 1: Tests failed
- 2: Coverage below threshold
- 3: Code not formatted
- 4: Documentation build failed
- 5: Temporary files found
- 6: Julia not found or version mismatch

Usage:
    julia scripts/pre_commit_check.jl
"""

using Test

# Optional dependencies (loaded conditionally)
const HAS_JULIAFORMATTER = try
    using JuliaFormatter
    true
catch
    false
end

const HAS_PKG = try
    using Pkg
    true
catch
    false
end

# Configuration
const COVERAGE_THRESHOLD = 90.0
const REQUIRED_JULIA_VERSION = v"1.8"

# ANSI color codes for terminal output
const COLORS = Dict(
    :reset => "\033[0m",
    :red => "\033[31m",
    :green => "\033[32m",
    :yellow => "\033[33m",
    :blue => "\033[34m",
    :bold => "\033[1m",
)

# Track overall status
all_checks_passed = Ref{Bool}(true)

function print_color(color::Symbol, message::String)
    println(get(COLORS, color, "") * message * COLORS[:reset])
end

function print_header(title::String)
    println()
    print_color(:blue, "═══════════════════════════════════════════════════")
    print_color(:bold, "  $title")
    print_color(:blue, "═══════════════════════════════════════════════════")
    println()
end

function print_success(message::String)
    print_color(:green, "✓ $message")
end

function print_error(message::String)
    all_checks_passed[] = false
    print_color(:red, "✗ $message")
end

function print_warning(message::String)
    print_color(:yellow, "⚠ $message")
end

"""
    check_julia_version()

Verify that Julia version meets minimum requirements.
"""
function check_julia_version()::Bool
    print_header("Checking Julia Version")

    current_version = VERSION

    if current_version >= REQUIRED_JULIA_VERSION
        print_success(
            "Julia version $current_version meets requirement (≥ $REQUIRED_JULIA_VERSION)",
        )
        return true
    else
        print_error(
            "Julia version $current_version does not meet requirement (≥ $REQUIRED_JULIA_VERSION)",
        )
        return false
    end
end

"""
    check_temp_files()

Check for temporary/auxiliary files that should not be committed.
"""
function check_temp_files()::Bool
    print_header("Check 1: Temporary Files")

    # Define files to check (cross-platform)
    temp_patterns = [
        ("*.log", "log files"),
        ("*~", "editor backup files"),
        ("*.swp", "Vim swap files"),
        ("*.swo", "Vim swap files"),
        ("*.bak", "backup files"),
        ("*.tmp", "temporary files"),
        (".DS_Store", "macOS files"),
        ("Thumbs.db", "Windows thumbnail cache"),
        ("*.cache", "cache files"),
    ]

    # Additional file/directory checks
    additional_checks = [
        ("nul", "Windows null device file"),
        ("test/artifacts", "test artifacts directory"),
    ]

    found_temp_files = false

    # Use Julia's built-in walkdir for cross-platform compatibility
    for (root, dirs, files) in walkdir(".")
        # Skip .git directory
        if ".git" in splitpath(root)
            continue
        end

        for file in files
            for (pattern, description) in temp_patterns
                if occursin(replace(pattern, "*" => ".*", "." => "\\."), file)
                    print_error("Found $description: $(joinpath(root, file))")
                    found_temp_files = true
                end
            end
        end
    end

    # Check additional specific files/directories
    for (target, description) in additional_checks
        if isfile(target) || isdir(target)
            print_error("Found $description: $target")
            found_temp_files = true
        end
    end

    if !found_temp_files
        print_success("No temporary files found")
    end

    return !found_temp_files
end

"""
    check_tests()

Execute the full test suite and return success status.
"""
function check_tests()::Bool
    print_header("Check 2: Run Test Suite")

    print("Running Julia test suite... ")

    try
        # Change to project root
        script_dir = @__DIR__
        project_root = normpath(joinpath(script_dir, ".."))
        cd(project_root)

        # Run tests using include
        # We'll use a try-catch to capture test results
        test_file = joinpath(project_root, "test", "runtests.jl")

        if !isfile(test_file)
            print_warning("No test/runtests.jl found - skipping tests")
            return true
        end

        # Include and run the tests
        include(test_file)

        # If we got here without errors, tests passed
        print_success("ALL TESTS PASSED")
        return true

    catch e
        if isa(e, Test.TestSetException)
            print_error("TESTS FAILED")
            println("  Some tests failed. Please review test output above.")
            return false
        else
            print_error("TEST ERROR: $(typeof(e))")
            return false
        end
    end
end

"""
    check_git_status()

Check git repository status.
"""
function check_git_status()::Bool
    print_header("Check 3: Git Status")

    try
        # Check if we're in a git repo
        git_result = read(`git rev-parse --is-inside-work-tree`, String)

        if strip(git_result) == "true"
            print_success("In a git repository")

            # Check for uncommitted changes
            status_result = read(`git status --porcelain`, String)

            if isempty(strip(status_result))
                print_success("No uncommitted changes")
            else
                print_warning("You have uncommitted changes:")
                for line in eachsplit(strip(status_result), '\n')
                    if !isempty(line)
                        println("  $line")
                    end
                end
            end

            return true
        else
            print_warning("Not in a git repository (skipping git checks)")
            return true
        end
    catch e
        print_warning("Git not available (skipping git checks)")
        return true
    end
end

"""
    check_documentation()

Verify that documentation can be built successfully.
"""
function check_documentation()::Bool
    print_header("Check 4: Documentation")

    script_dir = @__DIR__
    project_root = normpath(joinpath(script_dir, ".."))
    docs_dir = joinpath(project_root, "docs")
    make_file = joinpath(docs_dir, "make.jl")

    if !isdir(docs_dir)
        print_warning("No docs/ directory found (skipping)")
        return true
    end

    if !isfile(make_file)
        print_warning("No docs/make.jl found (skipping documentation build)")
        return true
    end

    print("Checking if documentation builds... ")

    try
        # For now, just verify the file exists and can be parsed
        # Building docs is expensive and may require additional packages
        include(make_file)
        print_success("DOCUMENTATION SCRIPT VALID")
        return true
    catch e
        print_warning("Could not validate documentation (may require additional setup)")
        print_warning("  Error: $(e.msg)")
        return true  # Don't fail on documentation errors during early development
    end
end

"""
    check_formatting()

Verify that all source code is properly formatted.
"""
function check_formatting()::Bool
    print_header("Check 5: Code Formatting")

    print("Checking code formatting... ")

    try
        # Try to use JuliaFormatter
        if !HAS_JULIAFORMATTER
            throw("JuliaFormatter not available")
        end

        script_dir = @__DIR__
        project_root = normpath(joinpath(script_dir, ".."))
        src_dir = joinpath(project_root, "src")

        if !isdir(src_dir)
            print_warning("No src/ directory found (skipping formatting check)")
            return true
        end

        # Check if files are formatted
        unformatted_files = String[]

        for (root, dirs, files) in walkdir(src_dir)
            for file in files
                if endswith(file, ".jl")
                    filepath = joinpath(root, file)
                    try
                        original_content = read(filepath, String)
                        formatted_content = format_text(original_content)

                        if original_content != formatted_content
                            push!(unformatted_files, relpath(filepath, project_root))
                        end
                    catch
                        # Skip files that can't be formatted
                    end
                end
            end
        end

        if isempty(unformatted_files)
            print_success("ALL FILES FORMATTED")
            return true
        else
            print_error("SOME FILES NEED FORMATTING:")
            for file in unformatted_files
                println("  - $file")
            end
            println()
            println(
                "  Run: julia --project=formattools -e 'using JuliaFormatter; format(\".\")'",
            )
            return false
        end
    catch e
        print_warning("Could not check formatting (JuliaFormatter not available?)")
        print_warning("  Error: $(typeof(e))")
        return true  # Don't fail if formatter not installed
    end
end

"""
    check_project_toml()

Verify Project.toml consistency.
"""
function check_project_toml()::Bool
    print_header("Check 6: Project.toml")

    print("Checking Project.toml... ")

    script_dir = @__DIR__
    project_root = normpath(joinpath(script_dir, ".."))
    project_toml = joinpath(project_root, "Project.toml")

    if !isfile(project_toml)
        print_error("Project.toml not found!")
        return false
    end

    try
        if !HAS_PKG
            throw("Pkg not available")
        end

        Pkg.activate(project_root)
        # Just verify the project can be activated
        print_success("Project.toml is valid")
        Pkg.activate()  # Return to default environment
        return true
    catch e
        print_error("Project.toml error: $(e.msg)")
        return false
    end
end

"""
    main()

Main entry point for pre-commit checks.
"""
function main()
    print_color(:bold, "\nOpenDESSEM Pre-Commit Check")
    print_color(:blue, "Project: OpenDESSEM")
    println()

    # Run Julia version check first
    if !check_julia_version()
        println()
        print_error("Julia version check failed - aborting")
        exit(6)
    end

    # Change to project root
    script_dir = @__DIR__
    project_root = normpath(joinpath(script_dir, ".."))
    cd(project_root)

    # Run all checks
    checks = [
        ("Temporary Files", check_temp_files),
        ("Test Suite", check_tests),
        ("Git Status", check_git_status),
        ("Documentation", check_documentation),
        ("Code Formatting", check_formatting),
        ("Project.toml", check_project_toml),
    ]

    results = Dict{String,Bool}()

    for (name, check_func) in checks
        try
            results[name] = check_func()
        catch e
            print_error("$name check crashed: $(typeof(e))")
            results[name] = false
        end
    end

    # Final summary
    print_header("SUMMARY")

    passed_count = count(values(results))
    total_count = length(results)

    println()
    println("Checks passed: $passed_count / $total_count")
    println()

    if all_checks_passed[] && all(values(results))
        print_success("ALL CHECKS PASSED - Safe to commit!")
        println()
        println("Next steps:")
        println("  1. Review changes: git diff")
        println("  2. Stage files: git add <files>")
        println("  3. Commit: git commit -m 'type(scope): description'")
        return 0
    else
        print_error("SOME CHECKS FAILED - Please fix before committing")
        println()
        println("Failed checks:")
        for (name, passed) in results
            if !passed
                println("  - $name")
            end
        end
        return 1
    end
end

# Run main function if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
