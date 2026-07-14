@echo off
title Rebuild All — Mod Manager + Installer + Loader Kit
cd /d "%~dp0"

echo ============================================
echo  Out of Ore — Rebuild Manager + Installer + Kit
echo  (Loader only — NO gameplay mods packaged)
echo ============================================
echo.

echo [1/3] Building OutOfOreModManager.exe ...
python -m pip install --upgrade pyinstaller -q
python -m PyInstaller --noconfirm --clean --onefile --windowed --name OutOfOreModManager --distpath dist --workpath build --specpath build ooo_mod_manager.py
if errorlevel 1 goto fail

echo.
echo [2/3] Building Install Out of Ore Mods.exe ...
python -m PyInstaller --noconfirm --clean --onefile --windowed --name "Install Out of Ore Mods" --distpath dist --workpath build --specpath build ooo_mod_installer.py
if errorlevel 1 goto fail

echo.
echo [3/3] Assembling loader-only kit zip ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0assemble_kit.ps1"
if errorlevel 1 goto fail

echo.
echo Copying manager EXE to this folder...
copy /Y "%~dp0dist\OutOfOreModManager.exe" "%~dp0OutOfOreModManager.exe" >nul

echo.
echo ============================================
echo  DONE
echo  EXEs:  dist\OutOfOreModManager.exe
echo         dist\Install Out of Ore Mods.exe
echo  Kit:   dist\OutOfOre-Modding-Kit-v1.1.0.zip
echo ============================================
pause
exit /b 0

:fail
echo.
echo FAILED — see errors above.
pause
exit /b 1
