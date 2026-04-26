@echo off
:: Устанавливаем кодировку UTF-8 для корректного отображения символов.
chcp 65001 >nul

:: Переходим в директорию скрипта, чтобы все пути были относительно неё
cd /d "%~dp0"

:: Проверяем наличие прав администратора. Если права есть, то переходим к основному коду, иначе перезапускаем скрипт с правами администратора.
net session >nul 2>&1
if %errorLevel% == 0 goto :main

:run_as_admin

:: Проверяем существование elevator.exe и запускаем с помощью него этот batch-скрипт от имени администратора.
if exist "bin\elevator.exe" (
    "bin\elevator.exe" "%~f0"
) else (
    echo [Ошибка] Файл elevator.exe не найден по пути: "bin\elevator.exe"
    pause
)

exit /b

:main

:: Очищаем кэш DNS
ipconfig /flushdns

:: Включаем TCP timestamps (временные метки TCP), необходимые для работы функции фулинга - tcp_ts
netsh int tcp set global timestamps=enable

:: Проверяем существование winws2.exe
if not exist "bin\winws2.exe" (
    echo [Ошибка] Файл winws2.exe не найден по пути: "bin\winws2.exe"
    pause
    exit /b
)

:: Запускаем наш zapret2 в свернутом окне
start "zapret2 %~n0" /min "bin\winws2.exe" @configs\all-1.txt
