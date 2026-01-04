#!/usr/bin/env julia

"""
    git_branch_manager_runner.jl

Continuous runner for git-branch-manager droid.

This script runs git branch manager checks periodically,
monitoring for PR validation needs, branch protection, and
remote synchronization requirements.

Intended to be run as a background service by droid_supervisor.jl.

Configuration:
    - Check interval: 60 seconds (configurable)
    - Logs to: .factory/logs/git-branch-manager-YYYY-MM-DD.log
    - PID file: .factory/pids/git-branch-manager.pid
"""

using Dates

# Configuration
const CHECK_INTERVAL = 60  # seconds (default, can be overridden)
const LOG_DIR = joinpath(@__DIR__, "..", ".factory", "logs")

# Setup logging
mkpath(LOG_DIR)

function get_log_file()
    timestamp = format(now(), "yyyy-mm-dd")
    return joinpath(LOG_DIR, "git-branch-manager-$timestamp.log")
end

function log_message(message::String, level::Symbol = :info)
    timestamp = format(now(), "yyyy-mm-dd HH:MM:SS")
    level_str = uppercase(string(level))

    log_line = "[$timestamp] [$level_str] $message"

    # Print to stdout
    if level == :error
        println(stderr, log_line)
    else
        println(log_line)
    end

    # Append to log file
    try
        open(get_log_file(), "a") do io
            println(io, log_line)
        end
    catch e
        println(stderr, "Error writing to log file: $e")
    end
end

function validate_branch(target::String = "dev")
    """
    Validate current branch against target branch quality gates.
    """
    log_message("Validating branch for target: $target", :info)

    try
        # Run validation script
        result = run(pipeline(
            `julia $(joinpath(@__DIR__, "validate_before_merge.jl")) --target=$target`,
            stdout = devnull,
            stderr = devnull
        ))

        if result.exitcode == 0
            log_message("✓ Branch validation passed for target: $target", :info)
            return true
        else
            log_message("✗ Branch validation failed for target: $target", :warning)
            return false
        end
    catch e
        log_message("✗ Error validating branch: $e", :error)
        return false
    end
end

function check_remote_sync()
    """
    Check if local and remote repositories are in sync.
    """
    log_message("Checking remote synchronization...", :info)

    try
        # Fetch latest
        run(pipeline(`git fetch --all --prune`, stdout = devnull, stderr = devnull))

        # Get current branch
        branch = read(`git rev-parse --abbrev-ref HEAD`, String) |> strip

        # Check if branch has unpushed commits
        result = read(pipeline(`git status --short --branch`, stderr = devnull), String)

        has_unpushed = contains(result, r"Ahead \d+")
        has_uncommitted = !isempty(strip(result)) && !has_unpushed

        if has_unpushed
            log_message("⚠ Branch '$branch' has unpushed commits", :warning)
        end

        if has_uncommitted
            log_message("⚠ Branch '$branch' has uncommitted changes", :warning)
        end

        if !has_unpushed && !has_uncommitted
            log_message("✓ Branch '$branch' is synchronized with remote", :info)
        end

        return !has_uncommitted && !has_unpushed
    catch e
        log_message("✗ Error checking remote sync: $e", :error)
        return false
    end
end

function check_branch_protection()
    """
    Verify branch protection rules are followed.
    """
    log_message("Checking branch protection...", :info)

    current_branch = read(`git rev-parse --abbrev-ref HEAD`, String) |> strip

    # Protected branches
    protected_branches = ["main", "master", "dev", "develop"]

    if current_branch in protected_branches
        log_message("⚠ On protected branch: $current_branch", :info)

        # Check if branch is clean
        status = read(`git status --porcelain`, String) |> strip

        if !isempty(status)
            log_message("✗ Protected branch '$current_branch' has uncommitted changes", :warning)
        else
            log_message("✓ Protected branch '$current_branch' is clean", :info)
        end
    else
        log_message("✓ On feature branch: $current_branch (no protection needed)", :info)
    end
end

function check_pr_validation()
    """
    Check for open PRs that need validation.
    """
    log_message("Checking for PR validation needs...", :info)

    try
        # Use GitHub CLI if available
        pr_result = read(`gh pr list --state open`, String)

        if !isempty(strip(pr_result))
            pr_lines = split(strip(pr_result), '\n')
            log_message("Found $(length(pr_lines)) open PR(s)", :info)

            # Get current branch
            current_branch = read(`git rev-parse --abbrev-ref HEAD`, String) |> strip

            # Check if current branch has an open PR
            for line in pr_lines
                if contains(line, current_branch)
                    log_message("Current branch '$current_branch' has an open PR", :info)

                    # Run validation
                    if validate_branch("dev")
                        log_message("✓ PR ready for merge to dev", :info)
                    else
                        log_message("✗ PR not ready for merge", :warning)
                    end
                    break
                end
            end
        else
            log_message("No open PRs found", :info)
        end
    catch e
        log_message("⚠ GitHub CLI not available or no PRs: $e", :warning)
    end
end

function run_continuous()
    """
    Main loop for continuous execution.
    """
    log_message("============================================================")
    log_message("Git Branch Manager Droid Started")
    log_message("============================================================")

    iteration = 0

    while true
        iteration += 1
        timestamp = format(now(), "yyyy-mm-dd HH:MM:SS")

        log_message("")
        log_message("Iteration #$iteration at $timestamp", :info)
        log_message("------------------------------------------------------------")

        try
            # Run checks
            check_remote_sync()
            check_branch_protection()
            check_pr_validation()

            log_message("------------------------------------------------------------")
            log_message("Iteration #$iteration completed", :info)

        catch e
            log_message("✗ Error in iteration #$iteration: $e", :error)
        end

        # Sleep until next check
        log_message("Sleeping for $CHECK_INTERVAL seconds...", :info)
        sleep(CHECK_INTERVAL)
    end
end

function main()
    """
    Main entry point.
    """
    # Parse command line arguments for interval override
    if length(ARGS) > 0
        try
            interval = parse(Int, ARGS[1])
            if interval > 0
                global const CHECK_INTERVAL = interval
                log_message("Check interval set to $CHECK_INTERVAL seconds", :info)
            end
        catch
            log_message("Invalid interval argument, using default", :warning)
        end
    end

    # Run continuous loop
    try
        run_continuous()
    catch e
        if isa(e, InterruptException)
            log_message("")
            log_message("============================================================")
            log_message("Git Branch Manager Droid Stopped")
            log_message("============================================================")
        else
            log_message("✗ Fatal error: $e", :error)
            return 1
        end
    end

    return 0
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
