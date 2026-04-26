@echo off
if "%1%" == "run" (
    "%~dp0bin\bash.exe" --login -i "%~dp0bin\menu.sh"
) else (
    "%~dp0bin\elevator.exe" "%~f0" run
)
