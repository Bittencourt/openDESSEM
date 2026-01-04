@echo off
REM stop_droids.bat
REM Stop all OpenDESSEM droids on Windows

echo ============================================
echo Stopping OpenDESSEM Droids
echo ============================================
echo.

cd /d "%~dp0.."

REM Kill droid processes
echo Stopping instruction-set-synchronizer...
taskkill /F /FI "WINDOWTITLE eq InstructionSetSync*" >nul 2>&1
echo   Stopped

echo Stopping code-quality-evaluator...
taskkill /F /FI "WINDOWTITLE eq CodeQualityEval*" >nul 2>&1
echo   Stopped

echo Stopping git-branch-manager...
taskkill /F /FI "WINDOWTITLE eq GitBranchManager*" >nul 2>&1
echo   Stopped

REM Clean up PID files
if exist ".factory\pids\*.pid" del /Q ".factory\pids\*.pid"

echo.
echo ============================================
echo All droids stopped!
echo ============================================
echo.
