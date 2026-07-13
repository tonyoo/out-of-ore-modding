@echo off
title Out of Ore Mod Manager
cd /d "%~dp0"

where py >nul 2>&1 && (
  py -3 "%~dp0ooo_mod_manager.py" %*
  goto :eof
)
where python >nul 2>&1 && (
  python "%~dp0ooo_mod_manager.py" %*
  goto :eof
)

echo Python was not found. Install Python 3 from https://www.python.org/downloads/
echo Make sure "Add python.exe to PATH" is checked.
pause
