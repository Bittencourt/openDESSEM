# OpenDESSEM Droid System

Automated background droids for OpenDESSEM development workflow.

---

## Overview

The droid system provides continuous monitoring and automation for:
- **Code Quality**: Tests, coverage, and linting checks
- **Git Workflow**: Branch protection, PR validation, and merge control
- **Instruction Synchronization**: Keeping documentation files in sync

Droids run as background processes with configurable check intervals.

---

## Available Droids

### 1. code-quality-evaluator
**Description**: Monitors code quality, runs tests, checks coverage, and validates linting
**Check Interval**: 5 minutes (300 seconds)
**Log File**: `.factory/logs/code-quality-evaluator-YYYY-MM-DD.log`
**Runner Script**: `scripts/code_quality_runner.jl`

### 2. git-branch-manager
**Description**: Manages git workflow, validates PRs, enforces branch protection
**Check Interval**: 1 minute (60 seconds)
**Log File**: `.factory/logs/git-branch-manager-YYYY-MM-DD.log`
**Runner Script**: `scripts/git_branch_manager_runner.jl`

### 3. instruction-set-synchronizer
**Description**: Keeps AGENTS.md and .claude/claude.md synchronized
**Check Interval**: 30 seconds
**Log File**: `.factory/logs/instruction-set-sync-YYYY-MM-DD.log`
**Runner Script**: `scripts/instruction_set_sync_runner.jl`

---

## Quick Start (Windows)

### Start All Droids
```batch
scripts\start_droids.bat
```

This will:
- Create necessary directories (logs, pids)
- Start all three droids in minimized background windows
- Display status and log file locations

### Stop All Droids
```batch
scripts\stop_droids.bat
```

### Check Droid Status
```batch
scripts\droids_status.bat
```

Shows:
- Running status of each droid
- PIDs if running
- Log file locations and sizes
- Recent log files

---

## Manual Control

### Start Individual Droid

**Windows Command Prompt**:
```batch
start /MIN "InstructionSetSync" julia scripts\instruction_set_sync_runner.jl
start /MIN "CodeQualityEval" julia scripts\code_quality_runner.jl
start /MIN "GitBranchManager" julia scripts\git_branch_manager_runner.jl
```

**PowerShell**:
```powershell
Start-Process julia -ArgumentList "scripts\instruction_set_sync_runner.jl" -WindowStyle Minimized
Start-Process julia -ArgumentList "scripts\code_quality_runner.jl" -WindowStyle Minimized
Start-Process julia -ArgumentList "scripts\git_branch_manager_runner.jl" -WindowStyle Minimized
```

**Julia Supervisor** (Cross-platform):
```bash
julia scripts/droid_supervisor.jl start
julia scripts/droid_supervisor.jl start <droid-name>
```

### Stop Individual Droid

**Windows**:
```batch
taskkill /F /PID <PID>
```

Or use `scripts\stop_droids.bat` to stop all.

---

## Directory Structure

```
.factory/
├── droids/
│   ├── code-quality-evaluator.md          # Droid specification
│   ├── git-branch-manager.md           # Droid specification
│   └── instruction-set-synchronizer.md # Droid specification
├── logs/                              # Droid log files
│   ├── code-quality-evaluator-2026-01-04.log
│   ├── git-branch-manager-2026-01-04.log
│   └── instruction-set-sync-2026-01-04.log
└── pids/                              # Process ID files (Unix only)

scripts/
├── start_droids.bat                    # Start all droids (Windows)
├── stop_droids.bat                     # Stop all droids (Windows)
├── droids_status.bat                   # Check droid status (Windows)
├── droid_supervisor.jl                # Supervisor (Cross-platform)
├── code_quality_runner.jl              # Code quality droid runner
├── git_branch_manager_runner.jl         # Git branch manager runner
└── instruction_set_sync_runner.jl     # Instruction sync runner
```

---

## Configuration

### Modify Check Intervals

Edit the `const CHECK_INTERVAL` value in each runner script:

**code_quality_runner.jl**:
```julia
const CHECK_INTERVAL = 300  # seconds (default: 5 minutes)
```

**git_branch_manager_runner.jl**:
```julia
const CHECK_INTERVAL = 60  # seconds (default: 1 minute)
```

**instruction_set_sync_runner.jl**:
```julia
const CHECK_INTERVAL = 30  # seconds (default: 30 seconds)
```

### Pass Custom Interval at Runtime

```bash
julia scripts/code_quality_runner.jl 120  # 2 minutes
julia scripts/git_branch_manager_runner.jl 30  # 30 seconds
```

---

## Monitoring

### View Logs in Real-Time

**Windows (using PowerShell)**:
```powershell
Get-Content .factory\logs\git-branch-manager-2026-01-04.log -Wait -Tail 20
```

**Git Bash/Cygwin**:
```bash
tail -f .factory/logs/git-branch-manager-2026-01-04.log
```

### Check Specific Droid Status

```batch
tasklist /FI "WINDOWTITLE eq GitBranchManager*"
```

---

## Troubleshooting

### Droids Not Starting

1. **Check Julia is in PATH**:
   ```batch
   julia --version
   ```

2. **Verify runner scripts exist**:
   ```batch
   dir scripts\*_runner.jl
   ```

3. **Check log files for errors**:
   ```batch
   type .factory\logs\*.log
   ```

### High Memory Usage

If droids consume too much memory:

1. **Stop droids**:
   ```batch
   scripts\stop_droids.bat
   ```

2. **Increase check intervals** in runner scripts
   - Larger intervals = fewer runs = lower memory usage

3. **Restart droids**:
   ```batch
   scripts\start_droids.bat
   ```

### Julia Process Won't Stop

```batch
# Force kill all Julia processes (use carefully!)
taskkill /F /IM julia.exe
```

---

## Integration with Development Workflow

### Automatic Validation

With git-branch-manager droid running:
- Automatic branch validation every 60 seconds
- Remote sync checks
- Branch protection enforcement
- PR readiness monitoring

### Continuous Code Quality

With code-quality-evaluator droid running:
- Automated test execution every 5 minutes
- Coverage tracking
- Linting checks
- CRITICAL_EVALUATION.md updates

### Documentation Sync

With instruction-set-synchronizer droid running:
- Automatic sync monitoring every 30 seconds
- Detection of out-of-sync files
- Timestamp comparison

---

## Advanced Usage

### Create Windows Service

For production use, consider creating a Windows service:

1. Use **NSSM** (Non-Sucking Service Manager):
   ```batch
   nssm install OpenDESSEM-Droids C:\path\to\julia.exe
   nssm set OpenDESSEM-Droids AppDirectory C:\Users\pedro\programming\DSc\openDESSEM
   nssm set OpenDESSEM-Droids AppParameters scripts\code_quality_runner.jl
   nssm set OpenDESSEM-Droids DisplayName "OpenDESSEM Code Quality Droid"
   nssm start OpenDESSEM-Droids
   ```

2. Repeat for each droid with different service names.

### Create Startup Shortcut

For automatic launch on system startup:

1. Create shortcut to `scripts\start_droids.bat`
2. Copy shortcut to:
   `C:\Users\<username>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`

---

## Best Practices

1. **Start droids at beginning of development session**
2. **Review logs regularly** (daily)
3. **Stop droids before system shutdown**
4. **Keep log files small** (rotate or delete old logs)
5. **Monitor memory usage** during long sessions
6. **Update droid specs** when workflow changes

---

## Support

For issues or questions:
- Check log files in `.factory/logs/`
- Review droid specifications in `.factory/droids/`
- Refer to `AGENTS.md` for project guidelines

---

**Last Updated**: 2026-01-04
**Version**: 1.0
