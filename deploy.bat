@echo off
rem i2tn — FTSC11 factory deploy, Windows. Double-click or run from cmd with options,
rem e.g.:  deploy.bat --fw app -p COM5
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 (
    echo Python 3 not found. Install it from https://www.python.org/downloads/
    echo and tick "Add python.exe to PATH" during setup.
    pause
    exit /b 1
)
python -m pip install -q -r requirements.txt || exit /b 1
python deploy.py %*
pause
