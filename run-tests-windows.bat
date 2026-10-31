@echo off
cd /d "%~dp0"
if not exist .venv\Scripts\python.exe (
  echo Run start-windows.bat once to set up Python first.
  pause
  exit /b 1
)
.venv\Scripts\python.exe -m pytest -q --junitxml=docs/test-results.xml
pause
