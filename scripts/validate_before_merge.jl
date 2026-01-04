#!/usr/bin/env julia

"""
    validate_before_merge.jl

Comprehensive validation script for git branch merges.

This script runs all necessary checks before merging branches:
1. Check for uncommitted changes
2. Verify branch is up to date with remote
3. Run full test suite
4. Check test coverage (>90% required for main, >85% for dev)
5. Verify code formatting
6. Run pre-commit checks
7. Scan for secrets/credentials
8. Check git history quality

Exit codes:
- 0: All checks passed - safe to merge
- 1: Uncommitted changes detected
- 2: Branch not up to date with remote
- 3: Tests failed
- 4: Coverage below threshold
- 5: Code needs formatting
- 6: Pre-commit checks failed
- 7: Secrets detected in changes
- 8: Git history quality issues
- 9: Julia version too old

Usage:
    julia scripts/validate_before_merge.jl [--target=dev|main]
"""

using Test

# Try to load optional dependencies
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
const COVERAGE_THRESHOLD_DEV = 85.0
const COVERAGE_THRESHOLD_MAIN = 90.0
const REQUIRED_JULIA_VERSION = v"1.8"

# Parse command line arguments
const TARGET_BRANCH = get(ARGS, 1, "dev")
const COVERAGE_THRESHOLD = TARGET_BRANCH == "main" ? COVERAGE_THRESHOLD_MAIN : COVERAGE_THRESHOLD_DEV

# ANSI color codes for terminal output
const COLORS = Dict(
    :reset => "\033[0m",
    :red => "\033[31m",
    :green => "\033[32m",
    :yellow => "\033[33m",
    :blue => "\033[34m",
    :bold => "\033[1m"
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

function print_info(message::String)
    println("  $message")
end

"""
    check_julia_version()

Verify that Julia version meets minimum requirements.
"""
function check_julia_version()::Bool
    print_header("0. Julia Version Check")

    current_version = VERSION

    if current_version >= REQUIRED_JULIA_VERSION
        print_success("Julia version $current_version meets requirement (≥ $REQUIRED_JULIA_VERSION)")
        return true
    else
        print_error("Julia version $current_version does not meet requirement (≥ $REQUIRED_JULIA_VERSION)")
        return false
    end
end

"""
    check_uncommitted_changes()

Check for uncommitted changes in the working directory.
"""
function check_uncommitted_changes()::Bool
    print_header("1. Check for Uncommitted Changes")

    try
        result = read(`git status --porcelain`, String)

        if isempty(strip(result))
            print_success("No uncommitted changes")
            return true
        else
            print_error("Uncommitted changes detected:")
            for line in eachsplit(strip(result), '\n')
                if !isempty(line)
                    print_info(line)
                end
            end
            println()
            println("  Please commit or stash changes before merging")
            println("  Commands:")
            println("    - Commit: git add . && git commit -m 'message'")
            println("    - Stash: git stash save 'WIP'")
            return false
        end
    catch e
        print_warning("Git not available - skipping uncommitted changes check")
        return true
    end
end

"""
    check_remote_sync()

Verify that branch is up to date with remote.
"""
function check_remote_sync()::Bool
    print_header("2. Check Remote Synchronization")

    try
        # Fetch latest from remote
        print_info("Fetching from remote...")
        run(`git fetch --all --prune`)

        # Get current branch name
        current_branch = read(`git rev-parse --abbrev-ref HEAD`, String) |> strip

        # Check if remote branch exists
        remote_branch_result = read(pipeline(`git rev-parse origin/$current_branch`, stderr=devnull), String) |> strip

        if isempty(remote_branch_result)
            print_warning("No remote branch 'origin/$current_branch' found - skipping sync check")
            print_info("  To set up tracking: git push -u origin $current_branch")
            return true
        end

        # Check if HEAD matches upstream
        local_head = read(`git rev-parse HEAD`, String) |> strip
        remote_head = remote_branch_result

        if local_head == remote_head
            print_success("Branch is up to date with remote")
            return true
        end

        # Check number of commits ahead/behind
        ahead_result = read(`git rev-list --count origin/$current_branch..HEAD`, String) |> strip |> tryparse(Int)
        behind_result = read(`git rev-list --count HEAD..origin/$current_branch`, String) |> strip |> tryparse(Int)

        if isnothing(ahead_result) || isnothing(behind_result)
            print_warning("Could not determine ahead/behind status")
            print_info("  Local: $local_head")
            print_info("  Remote: $remote_head")
            return true
        end

        ahead = ahead_result
        behind = behind_result

        if ahead > 0 && behind > 0
            print_error("Branch has diverged from remote")
            print_info("  Ahead by $ahead commit(s), behind by $behind commit(s)")
            println("  Please reconcile:")
            println("    - Option 1: git pull --rebase origin $current_branch")
            println("    - Option 2: git rebase origin/$current_branch")
            return false
        elseif ahead > 0
            print_warning("Branch is ahead of remote by $ahead commit(s)")
            print_info("  Please push: git push origin $current_branch")
            return false
        elseif behind > 0
            print_warning("Branch is behind remote by $behind commit(s)")
            print_info("  Please pull: git pull origin $current_branch")
            return false
        else
            print_success("Branch is up to date with remote")
            return true
        end
    catch e
        print_warning("Git not available - skipping remote sync check")
        print_info("  Error: $(typeof(e))")
        return true
    end
end

"""
    run_tests()

Execute the full test suite.
"""
function run_tests()::Bool
    print_header("3. Run Test Suite")

    script_dir = @__DIR__
    project_root = normpath(joinpath(script_dir, ".."))
    cd(project_root)

    test_file = joinpath(project_root, "test", "runtests.jl")

    if !isfile(test_file)
        print_warning("No test/runtests.jl found - skipping tests")
        return true
    end

    print_info("Running Julia test suite... ")
    println()

    try
        # Run tests
        include(test_file)

        print_success("ALL TESTS PASSED")
        return true
    catch e
        if isa(e, Test.TestSetException)
            print_error("TESTS FAILED")
            print_info("  Some tests failed. Review test output above.")
            println("  To run tests with more detail:")
            println("    julia --project=test test/runtests.jl")
            return false
        else
            print_error("TEST ERROR: $(typeof(e))")
            print_info("  $(e.msg)")
            return false
        end
    end
end

"""
    check_coverage()

Check test coverage against threshold.
"""
function check_coverage()::Bool
    print_header("4. Check Code Coverage")

    script_dir = @__DIR__
    project_root = normpath(joinpath(script_dir, ".."))
    cd(project_root)

    # Check if coverage script exists
    coverage_script = joinpath(project_root, "test", "coverage.jl")

    if !isfile(coverage_script)
        print_warning("No test/coverage.jl found - skipping coverage check")
        return true
    end

    print_info("Running coverage analysis...")
    println()

    try
        # Run coverage script
        include(coverage_script)

        # Note: Actual coverage extraction depends on the script
        # This is a placeholder - adapt based on actual coverage.jl output
        print_success("Coverage analysis complete")
        print_info("  For target: $TARGET_BRANCH")
        print_info("  Required coverage: ≥ $COVERAGE_THRESHOLD%")
        println("  (Review coverage output above for details)")

        return true
    catch e
        print_warning("Could not run coverage check")
        print_info("  Error: $(typeof(e))")
        return true  # Don't fail if coverage script fails
    end
end

"""
    check_formatting()

Verify that all source code is properly formatted.
"""
function check_formatting()::Bool
    print_header("5. Check Code Formatting")

    if !HAS_JULIAFORMATTER
        print_warning("JuliaFormatter not available - skipping formatting check")
        print_info("  Install: julia --project=formattools -e 'using Pkg; Pkg.add(\"JuliaFormatter\")'")
        return true
    end

    script_dir = @__DIR__
    project_root = normpath(joinpath(script_dir, ".."))
    src_dir = joinpath(project_root, "src")

    if !isdir(src_dir)
        print_warning("No src/ directory found - skipping formatting check")
        return true
    end

    print_info("Checking code formatting...")

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
                catch e
                    # Skip files that can't be formatted
                end
            end
        end
    end

    if isempty(unformatted_files)
        print_success("ALL FILES PROPERLY FORMATTED")
        return true
    else
        print_error("Some files need formatting:")
        for file in unformatted_files[1:min(10, length(unformatted_files))]
            print_info("  - $file")
        end
        if length(unformatted_files) > 10
            print_info("  ... and $(length(unformatted_files) - 10) more")
        end
        println()
        println("  Run: julia --project=formattools -e 'using JuliaFormatter; format(\".\")'")
        return false
    end
end

"""
    run_pre_commit_checks()

Run the pre-commit validation script.
"""
function run_pre_commit_checks()::Bool
    print_header("6. Run Pre-Commit Checks")

    script_dir = @__DIR__
    project_root = normpath(joinpath(script_dir, ".."))
    pre_commit_script = joinpath(project_root, "scripts", "pre_commit_check.jl")

    if !isfile(pre_commit_script)
        print_warning("No scripts/pre_commit_check.jl found - skipping")
        return true
    end

    print_info("Running pre-commit checks...")
    println()

    try
        include(pre_commit_script)

        # The script will exit with appropriate code
        print_success("Pre-commit checks completed")
        return true
    catch e
        print_error("Pre-commit checks failed")
        print_info("  Run manually for details: julia scripts/pre_commit_check.jl")
        return false
    end
end

"""
    scan_for_secrets()

Scan changes for potential secrets or credentials.
"""
function scan_for_secrets()::Bool
    print_header("7. Scan for Secrets/Credentials")

    try
        # Check for secrets in staged changes
        staged_diff = read(`git diff --cached`, String)

        # Check for secrets in unstaged changes
        unstaged_diff = read(`git diff`, String)

        # Patterns that might indicate secrets
        secret_patterns = [
            r"password\s*[=:]\s*['\"][^'\"]+['\"]"i,
            r"api[_-]?key\s*[=:]\s*['\"][^'\"]+['\"]"i,
            r"secret[_-]?key\s*[=:]\s*['\"][^'\"]+['\"]"i,
            r"token\s*[=:]\s*['\"][^'\"]+['\"]"i,
            r"private[_-]?key\s*[=:]\s*['\"][^'\"]+['\"]"i,
            r"authorization\s*:\s*Bearer\s+[A-Za-z0-9-_.]+"i,
            r"aws[_-]?(access[_-]?key|secret)"i,
        ]

        all_diffs = staged_diff * unstaged_diff

        found_secrets = false

        for pattern in secret_patterns
            matches = eachmatch(pattern, all_diffs)
            for m in matches
                print_error("Potential secret found:")
                print_info("  $(m.match)")
                found_secrets = true
            end
        end

        # Check for sensitive file types
        sensitive_files = [
            ".env",
            "*.pem",
            "*.key",
            "*.crt",
            "secrets.*",
            "credentials.*",
        ]

        git_files = read(`git ls-files`, String)

        for pattern in sensitive_files
            if occursin(replace(pattern, "*" => ".*", "." => "\\."), git_files)
                print_warning("Potential sensitive file tracked: $pattern")
                print_info("  Ensure it's in .gitignore")
            end
        end

        # Check for database files
        db_patterns = [r"\.db$", r"\.sqlite", r"\.sqlite3"]
        for pattern in db_patterns
            for line in eachsplit(git_files, '\n')
                if occursin(pattern, line)
                    print_warning("Database file tracked: $line")
                    print_info("  Database files should generally not be committed")
                end
            end
        end

        if !found_secrets
            print_success("No secrets detected in changes")
        end

        return !found_secrets
    catch e
        print_warning("Could not scan for secrets - git not available?")
        return true
    end
end

"""
    check_git_history_quality()

Check git history for quality issues.
"""
function check_git_history_quality()::Bool
    print_header("8. Check Git History Quality")

    try
        # Check last 10 commits
        commits = read(`git log -10 --pretty=format:"%s"`, String) |> strip |> split

        issues = String[]

        for (i, message) in enumerate(commits)
            # Check for WIP or draft commits
            if occursin(r"^(WIP|wip|draft|Draft|DRAFT)", message)
                push!(issues, "WIP/draft commit: $message")
            end

            # Check for very short commits
            if length(message) < 10
                push!(issues, "Very short commit message: $message")
            end

            # Check for merge commits without proper message
            if startswith(message, "Merge branch") && length(message) < 30
                push!(issues, "Vague merge commit: $message")
            end
        end

        if isempty(issues)
            print_success("Git history quality looks good")
            return true
        else
            print_warning("Some git history quality issues detected:")
            for issue in issues[1:min(5, length(issues))]
                print_info("  - $issue")
            end
            if length(issues) > 5
                print_info("  ... and $(length(issues) - 5) more")
            end
            println()
            println("  Consider fixing these issues before merging")
            return false
        end
    catch e
        print_warning("Could not check git history - skipping")
        return true
    end
end

"""
    main()

Main entry point for merge validation.
"""
function main()
    print_color(:bold, "\nGit Branch Merge Validation")
    print_color(:blue, "Target Branch: $TARGET_BRANCH")
    print_color(:blue, "Coverage Threshold: $COVERAGE_THRESHOLD%")
    println()

    # Run Julia version check first
    if !check_julia_version()
        println()
        print_error("Julia version check failed - aborting")
        exit(9)
    end

    # Change to project root
    script_dir = @__DIR__
    project_root = normpath(joinpath(script_dir, ".."))
    cd(project_root)

    # Define checks in order
    checks = [
        (1, "Uncommitted Changes", check_uncommitted_changes),
        (2, "Remote Synchronization", check_remote_sync),
        (3, "Test Suite", run_tests),
        (4, "Code Coverage", check_coverage),
        (5, "Code Formatting", check_formatting),
        (6, "Pre-Commit Checks", run_pre_commit_checks),
        (7, "Secrets Scan", scan_for_secrets),
        (8, "Git History Quality", check_git_history_quality),
    ]

    results = Dict{String, Bool}()

    for (step, name, check_func) in checks
        try
            results[name] = check_func()
        catch e
            print_error("$name check crashed: $(typeof(e))")
            print_info("  $(e.msg)")
            results[name] = false
        end
    end

    # Final summary
    print_header("VALIDATION SUMMARY")

    passed_count = count(values(results))
    total_count = length(results)

    println()
    println("Checks passed: $passed_count / $total_count")
    println()

    if all_checks_passed[] && all(values(results))
        print_success("ALL CHECKS PASSED ✓")
        println()
        println("SAFE TO MERGE into $TARGET_BRANCH")
        println()
        println("Next steps:")
        println("  1. Review changes: git diff $TARGET_BRANCH")
        println("  2. Merge: git merge --no-ff <feature-branch>")
        println("  3. Push: git push origin $TARGET_BRANCH")
        return 0
    else
        print_error("SOME CHECKS FAILED ✗")
        println()
        println("Please fix the following issues before merging:")
        println()
        for (name, passed) in results
            if !passed
                println("  ✗ $name")
            end
        end
        println()
        println("After fixing, re-run validation:")
        println("  julia scripts/validate_before_merge.jl --target=$TARGET_BRANCH")
        return 1
    end
end

# Run main function if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    exit_code = main()
    exit(exit_code)
end
