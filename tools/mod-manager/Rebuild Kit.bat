@echo off
title Rebuild Out of Ore Modding Kit
cd /d "%~dp0"
echo Building Mod Manager EXE...
python -m PyInstaller --noconfirm --clean --onefile --windowed --name OutOfOreModManager --distpath dist --workpath build --specpath build ooo_mod_manager.py
if errorlevel 1 goto fail
echo Building Installer EXE...
python -m PyInstaller --noconfirm --clean --onefile --windowed --name "Install Out of Ore Mods" --distpath dist --workpath build --specpath build ooo_mod_installer.py
if errorlevel 1 goto fail
echo Assembling kit zip...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0assemble_kit.ps1"
if errorlevel 1 goto fail
echo.
echo Done. Zip is in dist\
pause
exit /b 0
:fail
echo FAILED
pause
exit /b 1
