@echo off
setlocal
cd /d "%~dp0"

where bash >nul 2>nul
if errorlevel 1 (
  echo [ERROR] bash not found.
  echo Install Git for Windows and make sure "bash" is on PATH,
  echo or run this from a Git Bash window: bash run.sh
  pause
  exit /b 2
)

bash run.sh %*
set RC=%ERRORLEVEL%

echo.
if not "%RC%"=="0" echo [FAILED] exit code %RC%
pause
exit /b %RC%
