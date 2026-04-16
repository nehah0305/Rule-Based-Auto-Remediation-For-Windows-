@echo off
echo ============================================================
echo   Auto-Remediation Control Center - Flutter UI
echo ============================================================
echo.
echo Starting Flask backend (serving Flutter Web frontend)...
echo The app will be available at: http://localhost:5000
echo.
cd /d "%~dp0backend"
python app.py
