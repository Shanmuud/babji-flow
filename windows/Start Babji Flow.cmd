@echo off
cd /d "%~dp0"
if not exist "node_modules\electron\dist\electron.exe" (
  echo Installing Babji Flow dependencies...
  call npm.cmd ci --no-audit --no-fund
  if errorlevel 1 (
    pause
    exit /b 1
  )
)
set ELECTRON_RUN_AS_NODE=
start "Babji Flow" "node_modules\electron\dist\electron.exe" .
