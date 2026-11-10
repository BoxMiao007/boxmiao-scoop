@echo off
rem Run scripts\excavator-local.ps1 (local replica of the Excavator workflow).
rem Usage: excavator-local.bat [-App <name>] [-NoPush] [-ThrowError] [-Remote <name>] [-Branch <branch>]
rem All arguments are forwarded to the PowerShell script.
rem Set EXCAVATOR_PAUSE=1 to keep the window open after the run (useful for double-click).
setlocal
set "SCRIPT=%~dp0scripts\excavator-local.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: script not found: %SCRIPT%
    if /i "%EXCAVATOR_PAUSE%"=="1" pause
    exit /b 1
)

set "PS_EXE="
where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
if not defined PS_EXE (
    where powershell.exe >nul 2>nul && set "PS_EXE=powershell.exe"
)
if not defined PS_EXE (
    echo ERROR: neither pwsh.exe nor powershell.exe found in PATH.
    if /i "%EXCAVATOR_PAUSE%"=="1" pause
    exit /b 1
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "CODE=%ERRORLEVEL%"

if not "%CODE%"=="0" echo [excavator-local] failed with exit code %CODE%
if /i "%EXCAVATOR_PAUSE%"=="1" pause
exit /b %CODE%
