@ECHO off
REM Build Flutter web without requiring WHERE command
SETLOCAL

REM Set paths explicitly
SET FLUTTER_ROOT=C:\flutter
SET DART_EXE=%FLUTTER_ROOT%\bin\dart.bat

REM Change to frontend directory  
cd /d "%~dp0frontend"

REM Run pub get
echo Getting dependencies...
call "%DART_EXE%" pub get
if %ERRORLEVEL% NEQ 0 (
  echo Failed to get dependencies
  exit /b 1
)

REM Build web
echo Building Flutter web...
call "%FLUTTER_ROOT%\bin\flutter.bat" build web --release
if %ERRORLEVEL% NEQ 0 (
  echo Failed to build web
  exit /b 1
)

echo Build complete!
