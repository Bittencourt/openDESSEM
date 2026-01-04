@echo off
REM run_droid_bg.bat
REM Windows batch wrapper to run droids in background

REM Check arguments
if "%~1"=="" (
    echo Usage: run_droid_bg.bat ^<droid_name^> ^<script_path^> ^<log_file^>
    exit /b 1
)

set DROID_NAME=%~1
set SCRIPT_PATH=%~2
set LOG_FILE=%~3

echo Starting %DROID_NAME% droid in background...
echo Script: %SCRIPT_PATH%
echo Log: %LOG_FILE%

REM Start Julia process in background using START /B
start /B julia "%SCRIPT_PATH%" >> "%LOG_FILE%" 2>&1

echo %DROID_NAME% started successfully.
