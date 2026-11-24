@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
pushd "%~dp0" || exit /b 1
rem 局域网联机：在命令提示符先执行 set HOST=0.0.0.0，再运行 start.bat。
where /q node
if errorlevel 1 goto need_node
node -e "process.exit(Number(process.versions.node.split('.')[0]) >= 24 ? 0 : 1)" >nul 2>&1
if errorlevel 1 goto need_node
node server/launch.mjs
set "launch_status=%errorlevel%"
popd
exit /b %launch_status%

:need_node
echo 需要 Node.js 24 或更新版本。请到 nodejs.org 下载安装，再重新双击 start.bat。
set /p "answer=按回车退出。"
popd
exit /b 1
