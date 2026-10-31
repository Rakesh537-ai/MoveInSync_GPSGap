@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
  echo Python was not found. Install Python 3.12 from python.org and reopen this file.
  pause
  exit /b 1
)
if not exist .venv\Scripts\python.exe py -3.12 -m venv .venv
if not exist .venv\Scripts\python.exe (
  echo Could not create the environment. Install Python 3.12 first.
  pause
  exit /b 1
)
.venv\Scripts\python.exe -m pip install -r requirements.txt
if errorlevel 1 (
  echo Installation failed. Check your internet connection and retry.
  pause
  exit /b 1
)
echo Open http://127.0.0.1:8000/docs in your browser.
echo Keep this window open. Press Ctrl+C to stop the server.
.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
pause
