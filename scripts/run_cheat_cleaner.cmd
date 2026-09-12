@echo off
setlocal
cd /d "%~dp0\.."
set PYTHONPATH=%CD%\src
py -3.13 -m valheim_cheat_flag_cleaner.valheim_cheat_cleaner %*
endlocal
