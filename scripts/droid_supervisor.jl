#!/usr/bin/env julia

"""
    droid_supervisor.jl

Supervisor for running OpenDESSEM droids in the background.

This script manages multiple droids as continuous processes,
monitoring their status, restarting them if they fail,
and providing unified logging and status reporting.

Usage:
    # Start all droids in background
    julia scripts/droid_supervisor.jl start

    # Stop all droids
    julia scripts/droid_supervisor.jl stop

    # Restart all droids
    julia scripts/droid_supervisor.jl restart

    # Check status
    julia scripts/droid_supervisor.jl status

    # Start specific droid
    julia scripts/droid_supervisor.jl start <droid-name>

    # Stop specific droid
    julia scripts/droid_supervisor.jl stop <droid-name>
"""

using Dates
import Dates.format

# Configuration
const LOG_DIR = joinpath(@__DIR__, "..", ".factory", "logs")
const PID_DIR = joinpath(@__DIR__, "..", ".factory", "pids")

# Droid definitions
const DROIDS = Dict(
    "code-quality-evaluator" => Dict(
        "script" => joinpath(@__DIR__, "code_quality_evaluator.jl"),
        "interval" => 300,  # 5 minutes
        "description" => "Monitors code quality, tests, coverage, and linting",
    ),
    "git-branch-manager" => Dict(
        "script" => joinpath(@__DIR__, "git_branch_manager_runner.jl"),
        "interval" => 60,  # 1 minute
        "description" => "Manages git workflow, PR validation, and merges",
    ),
    "instruction-set-synchronizer" => Dict(
        "script" => joinpath(@__DIR__, "instruction_set_sync_runner.jl"),
        "interval" => 30,  # 30 seconds
        "description" => "Keeps AGENTS.md and .claude/claude.md synchronized",
    ),
)

# ANSI color codes
const COLORS = Dict(
    :reset => "\033[0m",
    :red => "\033[31m",
    :green => "\033[32m",
    :yellow => "\033[33m",
    :blue => "\033[34m",
    :bold => "\033[1m",
)

function print_color(color::Symbol, message::String)
    println(get(COLORS, color, "") * message * COLORS[:reset])
end

function ensure_directories()
    mkpath(LOG_DIR)
    mkpath(PID_DIR)
end

function get_pid_file(droid_name::String)
    return joinpath(PID_DIR, "$droid_name.pid")
end

function get_log_file(droid_name::String)
    timestamp = format(now(), "yyyy-mm-dd")
    return joinpath(LOG_DIR, "$droid_name-$timestamp.log")
end

function is_running(droid_name::String)
    pid_file = get_pid_file(droid_name)

    if !isfile(pid_file)
        return false
    end

    pid_str = read(pid_file, String) |> strip
    pid = tryparse(Int, pid_str)

    if isnothing(pid)
        return false
    end

    # Check if process is actually running
    try
        # Windows: use tasklist
        if Sys.iswindows()
            result = read(`tasklist /FI "PID eq $pid" /NH`, String)
            return occursin(string(pid), result)
        else
            # Unix/Linux/Mac: use ps
            result = read(`ps -p $pid`, String)
            return !occursin("not found", result)
        end
    catch
        return false
    end
end

function start_droid(droid_name::String)
    if !(droid_name in keys(DROIDS))
        print_color(:red, "Unknown droid: $droid_name")
        print_color(:yellow, "Available droids: $(join(keys(DROIDS), ", "))")
        return false
    end

    if is_running(droid_name)
        print_color(:yellow, "Droid '$droid_name' is already running")
        return false
    end

    droid = DROIDS[droid_name]
    script = droid["script"]
    interval = droid["interval"]
    description = droid["description"]

    if !isfile(script)
        print_color(:red, "Script not found: $script")
        return false
    end

    print_color(:blue, "Starting droid: $droid_name")
    print_color(:yellow, "  Description: $description")
    print_color(:yellow, "  Interval: $(interval)s")
    print_color(:yellow, "  Script: $script")

    # Start the droid in background
    log_file = get_log_file(droid_name)

    try
        if Sys.iswindows()
            # Windows: use start /B
            pid = run(
                pipeline(`start /B julia $script`, stdout = log_file, stderr = log_file);
                wait = false,
            )

            # Get PID from the started process
            # On Windows, we need a different approach
            # For now, we'll use a wrapper approach
            pid = nothing
        else
            # Unix: use nohup and get PID
            process = run(
                pipeline(`nohup julia $script`, stdout = log_file, stderr = log_file);
                wait = false,
            )
            pid = process.pid
        end

        if !isnothing(pid)
            # Save PID
            open(get_pid_file(droid_name), "w") do io
                println(io, pid)
            end

            print_color(:green, "✓ Started '$droid_name' (PID: $pid)")
            print_color(:yellow, "  Logs: $log_file")
            return true
        else
            print_color(:red, "✗ Failed to start '$droid_name'")
            return false
        end
    catch e
        print_color(:red, "✗ Error starting '$droid_name': $e")
        return false
    end
end

function stop_droid(droid_name::String)
    if !is_running(droid_name)
        print_color(:yellow, "Droid '$droid_name' is not running")
        return false
    end

    pid_file = get_pid_file(droid_name)
    pid_str = read(pid_file, String) |> strip
    pid = tryparse(Int, pid_str)

    if isnothing(pid)
        print_color(:red, "Invalid PID in pid file")
        rm(pid_file)
        return false
    end

    print_color(:blue, "Stopping droid: $droid_name (PID: $pid)")

    try
        if Sys.iswindows()
            # Windows
            run(`taskkill /F /PID $pid`, wait = true)
        else
            # Unix
            run(`kill $pid`, wait = true)
        end

        rm(pid_file)
        print_color(:green, "✓ Stopped '$droid_name'")
        return true
    catch e
        print_color(:red, "✗ Error stopping '$droid_name': $e")
        return false
    end
end

function status()
    print_color(:bold, "\nOpenDESSEM Droid Status")
    print_color(:blue, string("=", 60))
    println()

    for (name, droid) in DROIDS
        running = is_running(name)
        status_str = running ? "[RUNNING]" : "[STOPPED]"
        status_color = running ? :green : :yellow

        print_color(status_color, "$status_str $name")
        println("  $(droid["description"])")

        if running
            pid_file = get_pid_file(name)
            if isfile(pid_file)
                pid = read(pid_file, String) |> strip
                println("  PID: $pid")
            end

            log_file = get_log_file(name)
            if isfile(log_file)
                log_size = filesize(log_file)
                println("  Log: $log_file ($(log_size) bytes)")
            end
        else
            println("  Not running")
        end

        println()
    end
end

function start_all()
    print_color(:bold, "Starting all droids...")
    println()

    for droid_name in keys(DROIDS)
        start_droid(droid_name)
        println()
    end
end

function stop_all()
    print_color(:bold, "Stopping all droids...")
    println()

    for droid_name in keys(DROIDS)
        stop_droid(droid_name)
    end
end

function restart_all()
    stop_all()
    sleep(2)
    start_all()
end

function main()
    ensure_directories()

    if isempty(ARGS)
        println("Usage: julia scripts/droid_supervisor.jl <command> [droid-name]")
        println()
        println("Commands:")
        println("  start [droid]     - Start all or specific droid")
        println("  stop [droid]      - Stop all or specific droid")
        println("  restart [droid]   - Restart all or specific droid")
        println("  status            - Show status of all droids")
        println()
        println("Droids:")
        for (name, droid) in DROIDS
            println("  - $name: $(droid["description"])")
        end
        return 0
    end

    command = lowercase(ARGS[1])

    if command == "start"
        if length(ARGS) >= 2
            start_droid(ARGS[2])
        else
            start_all()
        end

    elseif command == "stop"
        if length(ARGS) >= 2
            stop_droid(ARGS[2])
        else
            stop_all()
        end

    elseif command == "restart"
        if length(ARGS) >= 2
            stop_droid(ARGS[2])
            sleep(1)
            start_droid(ARGS[2])
        else
            restart_all()
        end

    elseif command == "status"
        status()

    else
        print_color(:red, "Unknown command: $command")
        return 1
    end

    return 0
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
