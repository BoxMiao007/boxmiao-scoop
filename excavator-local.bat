@echo off
rem 本地运行 scripts\excavator-local.ps1（Excavator 工作流的本地复现）。
rem 用法：excavator-local.bat [-App <名称>] [-NoPush] [-ThrowError] [-Remote <远端>] [-Branch <分支>]
rem 所有参数原样转发给 PowerShell 脚本。
rem 设置 EXCAVATOR_PAUSE=1 可在运行结束后暂停窗口，方便双击运行后查看输出。
chcp 65001 >nul
setlocal
set "SCRIPT=%~dp0scripts\excavator-local.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: script not found: %SCRIPT%
    if /i "%EXCAVATOR_PAUSE%"=="1" pause
    exit /b 1
)

rem 优先使用 PowerShell 7（pwsh），没有时回退到 Windows PowerShell 5.1
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

rem -NoProfile 避免加载用户配置影响输出；-ExecutionPolicy Bypass 允许运行本地脚本
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "CODE=%ERRORLEVEL%"

if not "%CODE%"=="0" echo [excavator-local] failed with exit code %CODE%
if /i "%EXCAVATOR_PAUSE%"=="1" pause
exit /b %CODE%
