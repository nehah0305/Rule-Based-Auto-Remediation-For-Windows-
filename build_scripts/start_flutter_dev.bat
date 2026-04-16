@echo off
echo ============================================================
echo   Flutter Dev Mode (Hot Reload)
echo ============================================================
echo.
echo Starting Flutter web dev server on http://localhost:8080
echo Make sure Flask is already running on port 5000 in another terminal.
echo.
set PATH=C:\flutter\bin;C:\Windows\System32;C:\Windows\System32\WindowsPowerShell\v1.0;%PATH%
cd /d "%~dp0frontend"
flutter run -d web-server --web-port=8080 --web-hostname=localhost
