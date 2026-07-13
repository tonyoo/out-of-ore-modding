@echo off
title Build OutOfOreModManager.exe
cd /d "%~dp0"

echo Installing/ensuring PyInstaller...
python -m pip install --upgrade pyinstaller -q
if errorlevel 1 (
  echo pip failed
  pause
  exit /b 1
)

echo Building OutOfOreModManager.exe ...
python -m PyInstaller --noconfirm --clean --onefile --windowed --name OutOfOreModManager ^
  --distpath "%~dp0dist" --workpath "%~dp0build" --specpath "%~dp0build" ^
  ooo_mod_manager.py
if errorlevel 1 (
  echo Build failed
  pause
  exit /b 1
)

echo.
echo OK: %~dp0dist\OutOfOreModManager.exe
pause
