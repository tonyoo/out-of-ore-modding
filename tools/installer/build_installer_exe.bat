@echo off
title Build Out of Ore Mod Installer EXE
cd /d "%~dp0"

echo Ensuring PyInstaller...
python -m pip install --upgrade pyinstaller -q

echo Building Install Out of Ore Mods.exe ...
python -m PyInstaller --noconfirm --clean --onefile --windowed --name "Install Out of Ore Mods" ^
  --distpath "%~dp0dist" --workpath "%~dp0build" --specpath "%~dp0build" ^
  ooo_mod_installer.py
if errorlevel 1 (
  echo Build failed
  pause
  exit /b 1
)

echo.
echo OK: %~dp0dist\Install Out of Ore Mods.exe
echo Note: ship this EXE next to a payload\ folder (see assemble_kit.ps1)
pause
