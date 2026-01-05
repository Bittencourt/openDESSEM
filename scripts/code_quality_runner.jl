#!/usr/bin/env julia

"""
    code_quality_runner.jl

Continuous runner for code-quality-evaluator droid.

This script runs code quality checks periodically,
monitoring test results, coverage, and linting.

Intended to be run as a background service by droid_supervisor.jl.
"""

using Dates

const CHECK_INTERVAL = 300  # 5 minutes
const LOG_DIR = joinpath(@__DIR__, "..", ".factory", "logs")

mkpath(LOG_DIR)

function get_log_file()
    timestamp = format(now(), "yyyy-mm-dd")
    return joinpath(LOG_DIR, "code-quality-evaluator-$timestamp.log")
end

function log_message(message::String, level::Symbol = :info)
    timestamp = format(now(), "yyyy-mm-dd HH:MM:SS")
    level_str = uppercase(string(level))
    log_line = "[$timestamp] [$level_str] $message"

    if level == :error
        println(stderr, log_line)
    else
        println(log_line)
    end

    try
        open(get_log_file(), "a") do io
            println(io, log_line)
        end
    catch e
        println(stderr, "Error writing to log: $e")
    end
end

function run_quality_check()
    log_message("Running code quality evaluation...", :info)

    try
        result = run(
            pipeline(
                `julia $(joinpath(@__DIR__, "code_quality_evaluator.jl"))`,
                stdout = get_log_file(),
                stderr = get_log_file(),
            ),
        )

        if result.exitcode == 0
            log_message("✓ Code quality evaluation completed", :info)
        else
            log_message("✗ Code quality evaluation failed", :warning)
        end
    catch e
        log_message("✗ Error running quality check: $e", :error)
    end
end

function run_continuous()
    log_message("============================================================")
    log_message("Code Quality Evaluator Droid Started")
    log_message("============================================================")

    iteration = 0

    while true
        iteration += 1
        timestamp = format(now(), "yyyy-mm-dd HH:MM:SS")

        log_message("")
        log_message("Iteration #$iteration at $timestamp", :info)
        log_message("------------------------------------------------------------")

        try
            run_quality_check()
            log_message("------------------------------------------------------------")
            log_message("Iteration #$iteration completed", :info)
        catch e
            log_message("✗ Error in iteration #$iteration: $e", :error)
        end

        log_message("Sleeping for $CHECK_INTERVAL seconds...", :info)
        sleep(CHECK_INTERVAL)
    end
end

function main()
    try
        run_continuous()
    catch e
        if isa(e, InterruptException)
            log_message("")
            log_message("============================================================")
            log_message("Code Quality Evaluator Droid Stopped")
            log_message("============================================================")
        else
            log_message("✗ Fatal error: $e", :error)
            return 1
        end
    end

    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
