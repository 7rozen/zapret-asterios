@echo off
if "%~1" == "run" (
    if not exist "%~dp0.unblocked" (
        for /R "%~dp0" %%i in (*) do @echo. > "%%i:Zone.Identifier" 2>nul
        echo. > "%~dp0.unblocked"
    )

    "%~dp0bin\bash.exe" --login -i "%~dp0bin\menu.sh"
    goto :EOF
) else (
    powershell -NoProfile -Command "Start-Process '%~f0' -ArgumentList 'run' -Verb RunAs"
)
