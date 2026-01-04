@echo off
REM droids_status.bat
REM Check status of OpenDESSEM droids on Windows

echo ============================================
echo OpenDESSEM Droid Status
echo ============================================
echo.

cd /d "%~dp0.."

REM Check instruction-set-synchronizer
echo [?] instruction-set-synchronizer
tasklist /FI "WINDOWTITLE eq InstructionSetSync*" 2>nul | find "julia.exe" >nul
if %errorlevel% equ 0 (
    echo     Status: RUNNING
) else (
    echo     Status: STOPPED
)
echo.

REM Check code-quality-evaluator
echo [?] code-quality-evaluator
tasklist /FI "WINDOWTITLE eq CodeQualityEval*" 2>nul | find "julia.exe" >nul
if %errorlevel% equ 0 (
    echo     Status: RUNNING
) else (
    echo     Status: STOPPED
)
echo.

REM Check git-branch-manager
echo [?] git-branch-manager
tasklist /FI "WINDOWTITLE eq GitBranchManager*" 2>nul | find "julia.exe" >nul
if %errorlevel% equ 0 (
    echo     Status: RUNNING
) else (
    echo     Status: STOPPED
)
echo.

REM Show recent log files
if exist ".factory\logs" (
    echo ============================================
    echo Recent Log Files:
    echo ============================================
    dir /B /O-D ".factory\logs\*.log" 2>nul | more
    echo.
)

echo ============================================
