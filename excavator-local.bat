@echo off
rem 本地运行 scripts\excavator-local.ps1（Excavator 工作流的本地复现）。
rem 用法：excavator-local.bat [-App <名称>] [-NoPush] [-ThrowError] [-Remote <远端>] [-Branch <分支>]
rem 所有参数原样转发给 PowerShell 脚本。
rem 运行结束后按回车键关闭窗口；自动化调用时可先 set EXCAVATOR_NO_PAUSE=1 跳过等待。
chcp 65001 >nul
setlocal
rem 未显式设置代理时，读取 Windows 系统代理，供 git/checkver 使用。
if not defined HTTP_PROXY if not defined HTTPS_PROXY (
    for /f "usebackq delims=" %%P in (`powershell.exe -NoProfile -Command "$p=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'; if ($p.ProxyEnable -eq 1 -and $p.ProxyServer) { $s=$p.ProxyServer; if ($s -match '=') { $s=$s -replace '^.*?https?=',''; $s=$s -replace ';.*$','' }; if ($s -notmatch '^[a-z]+://') { $s='http://'+$s }; $s }"`) do set "HTTP_PROXY=%%P"
)
if defined HTTP_PROXY if not defined HTTPS_PROXY set "HTTPS_PROXY=%HTTP_PROXY%"
if defined HTTPS_PROXY if not defined HTTP_PROXY set "HTTP_PROXY=%HTTPS_PROXY%"
if defined HTTP_PROXY set "http_proxy=%HTTP_PROXY%"
if defined HTTPS_PROXY set "https_proxy=%HTTPS_PROXY%"
set "SCRIPT=%~dp0scripts\excavator-local.ps1"
set "CODE=1"

if not exist "%SCRIPT%" (
    echo ERROR: script not found: %SCRIPT%
    goto :finish
)

rem 优先使用 PowerShell 7（pwsh），没有时回退到 Windows PowerShell 5.1
set "PS_EXE="
where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
if not defined PS_EXE (
    where powershell.exe >nul 2>nul && set "PS_EXE=powershell.exe"
)
if not defined PS_EXE (
    echo ERROR: neither pwsh.exe nor powershell.exe found in PATH.
    goto :finish
)

rem -NoProfile 避免加载用户配置影响输出；-ExecutionPolicy Bypass 允许运行本地脚本
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" echo [excavator-local] failed with exit code %CODE%

:finish
if /i "%EXCAVATOR_NO_PAUSE%"=="1" exit /b %CODE%
echo.
rem 等待用户按回车后结束，避免双击运行时窗口一闪而过
set /p "_=请按回车键结束..."
exit /b %CODE%
