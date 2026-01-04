#!/usr/bin/env julia
# =====================================================
# pre_commit_check.jl
# =====================================================
# Pre-commit verification script for OpenDESSEM
# Usage: julia scripts/pre_commit_check.jl
# =====================================================

using Test

# Colors for terminal output
const GREEN = "\033[0;32m"
const RED = "\033[0;31m"
const YELLOW = "\033[1;33m"
const BLUE = "\033[0;34m"
const NC = "\033[0m"  # No Color

# Track overall status
all_checks_passed = true

# =====================================================
# Helper Functions
# =====================================================

function print_header(title::String)
    println()
    println("="^60)
    println(BLUE * title * NC)
    println("="^60)
end

function print_success(message::String)
    println(GREEN * "✓ $message" * NC)
end

function print_error(message::String)
    global all_checks_passed = false
    println(RED * "✗ $message" * NC)
end

function print_warning(message::String)
    println(YELLOW * "⚠ $message" * NC)
end

function run_command(cmd::String, description::String)
    println()
    print("Running: $description... ")

    try
        result = read(cmd, String)
        if success(result)
            print_success("PASSED")
            return true
        else
            print_error("FAILED")
            println("Output:")
            println(result)
            return false
        end
    catch e
        print_error("ERROR: $(e.msg)")
        return false
    end
end

# =====================================================
# Check 1: No temporary files
# =====================================================

function check_temp_files()
    print_header("Check 1: Temporary Files")

    temp_patterns = [
        ("*.log", "log files"),
        ("*~", "editor backup files"),
        ("*.swp", "Vim swap files"),
        ("*.bak", "backup files"),
        ("*.tmp", "temporary files"),
        (".DS_Store", "macOS files"),
        ("Thumbs.db", "Windows files")
    ]

    found_temp_files = false

    for (pattern, description) in temp_patterns
        try
            result = read(`find . -name "$pattern" -type f`, String)
            if !isempty(strip(result))
                print_error("Found $description matching $pattern:")
                println(result)
                found_temp_files = true
            end
        catch
            # find command failed, skip
        end
    end

    if !found_temp_files
        print_success("No temporary files found")
    end

    return !found_temp_files
end

# =====================================================
# Check 2: Run tests
# =====================================================

function check_tests()
    print_header("Check 2: Run Test Suite")

    print("Running Julia test suite... ")

    try
        # Run tests and capture output
        test_result = Test.@testset "All Tests" begin
            include("../test/runtests.jl")
        end

        if Test.get_testset().nfail == 0 && Test.get_testset().nerror == 0
            print_success("ALL TESTS PASSED")
            println("  Tests passed: $(Test.get_testset().npass)")
            return true
        else
            print_error("TESTS FAILED")
            println("  Failures: $(Test.get_testset().nfail)")
            println("  Errors: $(Test.get_testset().nerror)")
            return false
        end
    catch e
        print_error("TEST ERROR: $(e.msg)")
        return false
    end
end

# =====================================================
# Check 3: Check if running from git repo
# =====================================================

function check_git_status()
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
                println(status_result)
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

# =====================================================
# Check 4: Verify documentation builds
# =====================================================

function check_documentation()
    print_header("Check 4: Documentation")

    if !isdir("docs")
        print_warning("No docs/ directory found (skipping)")
        return true
    end

    print("Checking if documentation builds... ")

    try
        # Try to build docs
        run(`julia --project=docs docs/make.jl`)
        print_success("DOCUMENTATION BUILDS")
        return true
    catch e
        print_error("DOCUMENTATION BUILD FAILED")
        println("  Error: $(e.msg)")
        return false
    end
end

# =====================================================
# Check 5: Code formatting
# =====================================================

function check_formatting()
    print_header("Check 5: Code Formatting")

    print("Checking code formatting... ")

    try
        # Check if JuliaFormatter is available
        using JuliaFormatter

        # Check if files are formatted (don't auto-format, just check)
        unformatted_files = String[]

        for (root, dirs, files) in walkdir("src")
            for file in files
                if endswith(file, ".jl")
                    filepath = joinpath(root, file)
                    original_content = read(filepath, String)
                    formatted_content = format_text(original_content)

                    if original_content != formatted_content
                        push!(unformatted_files, filepath)
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
            println("  Run: julia -e 'using JuliaFormatter; format(\".\")'")
            return false
        end
    catch e
        print_warning("Could not check formatting (JuliaFormatter not available?)")
        return true  # Don't fail if formatter not installed
    end
end

# =====================================================
# Check 6: Verify Project.toml consistency
# =====================================================

function check_project_toml()
    print_header("Check 6: Project.toml")

    print("Checking Project.toml... ")

    if !isfile("Project.toml")
        print_error("Project.toml not found!")
        return false
    end

    try
        # Try to load the project
        using Pkg
        Pkg.activate(".")
        Pkg.instantiate()

        print_success("Project.toml is valid")
        return true
    catch e
        print_error("Project.toml error: $(e.msg)")
        return false
    end
end

# =====================================================
# Main execution
# =====================================================

function main()
    print_header("OpenDESSEM Pre-Commit Check")
    println("Running verification checks before commit...")
    println()

    # Change to project root
    script_dir = @__DIR__
    cd(joinpath(script_dir, ".."))

    # Run all checks
    checks = [
        ("Temporary Files", check_temp_files),
        ("Test Suite", check_tests),
        ("Git Status", check_git_status),
        ("Documentation", check_documentation),
        ("Code Formatting", check_formatting),
        ("Project.toml", check_project_toml)
    ]

    results = Bool[]

    for (name, check_func) in checks
        try
            push!(results, check_func())
        catch e
            print_error("$name check crashed: $(e.msg)")
            push!(results, false)
        end
    end

    # Final summary
    print_header("SUMMARY")

    passed_count = count(results)
    total_count = length(results)

    println()
    println("Checks passed: $passed_count / $total_count")
    println()

    if all_checks_passed && all(results)
        println(GREEN * "✓ ALL CHECKS PASSED - Safe to commit!" * NC)
        println()
        println("Next steps:")
        println("  1. Review changes: git diff")
        println("  2. Stage files: git add <files>")
        println("  3. Commit: git commit -m 'type(scope): description'")
        return 0
    else
        println(RED * "✗ SOME CHECKS FAILED - Please fix before committing" * NC)
        println()
        println("Failed checks:")
        for (i, (name, _)) in enumerate(checks)
            if !results[i]
                println("  - $name")
            end
        end
        return 1
    end
end

# Run main function
exit(main())
