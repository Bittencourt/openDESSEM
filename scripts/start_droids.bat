@echo off
REM start_droids.bat
REM Start all OpenDESSEM droids in background on Windows

echo ============================================
echo Starting OpenDESSEM Droids
echo ============================================
echo.

cd /d "%~dp0.."

REM Create logs directory
if not exist ".factory\logs" mkdir .factory\logs
if not exist ".factory\pids" mkdir .factory\pids

REM Start instruction-set-synchronizer
echo Starting instruction-set-synchronizer...
start /MIN "InstructionSetSync" julia scripts\instruction_set_sync_runner.jl
timeout /t 2 /nobreak >nul
echo   Started in background
echo.

REM Start code-quality-evaluator
echo Starting code-quality-evaluator...
start /MIN "CodeQualityEval" julia scripts\code_quality_runner.jl
timeout /t 2 /nobreak >nul
echo   Started in background
echo.

REM Start git-branch-manager
echo Starting git-branch-manager...
start /MIN "GitBranchManager" julia scripts\git_branch_manager_runner.jl
timeout /t 2 /nobreak >nul
echo   Started in background
echo.

echo ============================================
echo All droids started!
echo ============================================
echo.
echo Check logs: .factory\logs\
echo.

REM Option: Keep window open
echo Press any key to close this window (droids will continue running)...
pause >nul
