@echo off
chcp 65001 >nul
if defined __EXCAVATOR_UPDATE_UTF8__ goto :main
set "__EXCAVATOR_UPDATE_UTF8__=1"
"%ComSpec%" /d /c ""%~f0" %*"
exit /b %ERRORLEVEL%

:main
setlocal
set "CODE=1"

rem 先运行本地 Excavator：更新清单、提交并推送。
set "EXCAVATOR_NO_PAUSE=1"
call "%~dp0excavator-local.bat" %*
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
    echo 本地 Excavator 失败，跳过 Scoop 更新流程。
    goto :finish
)

rem 最后更新 Scoop、magpie，并清理旧版本与缓存；不结束正在运行的 Magpie 进程。
tasklist /FI "IMAGENAME eq magpie.exe" /NH 2>nul | find /I "magpie.exe" >nul
if errorlevel 1 (
    echo 未检测到 Magpie 进程在运行。
) else (
    echo 检测到 Magpie 正在运行，本脚本不会结束该进程。
)

call scoop update && call scoop status && call scoop update magpie && call scoop cleanup -a && call scoop cache rm -a
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" echo Scoop 更新流程失败，退出码：%CODE%

:finish
echo.
echo 执行结束。
timeout /t 0 /nobreak >nul 2>&1
if errorlevel 1 exit /b %CODE%
echo 按任意键关闭窗口……
pause < CON >nul
exit /b %CODE%
