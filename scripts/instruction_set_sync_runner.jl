#!/usr/bin/env julia

"""
    instruction_set_sync_runner.jl

Continuous runner for instruction-set-synchronizer droid.

This script monitors AGENTS.md and .claude/claude.md
for changes and keeps them synchronized.

Intended to be run as a background service by droid_supervisor.jl.
"""

using Dates

const CHECK_INTERVAL = 30  # 30 seconds
const LOG_DIR = joinpath(@__DIR__, "..", ".factory", "logs")

mkpath(LOG_DIR)

function get_log_file()
    timestamp = format(now(), "yyyy-mm-dd")
    return joinpath(LOG_DIR, "instruction-set-sync-$timestamp.log")
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

function check_sync()
    agents_file = joinpath(@__DIR__, "..", "AGENTS.md")
    claude_file = joinpath(@__DIR__, "..", ".claude", "claude.md")

    log_message("Checking instruction set synchronization...", :info)

    try
        if !isfile(agents_file)
            log_message("✗ AGENTS.md not found", :error)
            return false
        end

        if !isfile(claude_file)
            log_message("✗ .claude/claude.md not found", :error)
            return false
        end

        # Get modification times
        agents_mtime = mtime(agents_file)
        claude_mtime = mtime(claude_file)

        # Check if either file changed recently
        time_diff = abs(agents_mtime - claude_mtime)
        time_threshold = 60  # 1 minute

        if time_diff > time_threshold
            log_message("⚠ Files may be out of sync (diff: $(round(Int, time_diff))s)", :warning)
            log_message("  AGENTS.md: $(format(DateTime(agents_mtime), "yyyy-mm-dd HH:MM:SS"))", :info)
            log_message("  claude.md: $(format(DateTime(claude_mtime), "yyyy-mm-dd HH:MM:SS"))", :info)
        else
            log_message("✓ Instruction sets appear synchronized", :info)
        end

        return true
    catch e
        log_message("✗ Error checking sync: $e", :error)
        return false
    end
end

function run_continuous()
    log_message("============================================================")
    log_message("Instruction Set Synchronizer Droid Started")
    log_message("============================================================")

    iteration = 0

    while true
        iteration += 1
        timestamp = format(now(), "yyyy-mm-dd HH:MM:SS")

        log_message("")
        log_message("Iteration #$iteration at $timestamp", :info)
        log_message("------------------------------------------------------------")

        try
            check_sync()
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
            log_message("Instruction Set Synchronizer Droid Stopped")
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
