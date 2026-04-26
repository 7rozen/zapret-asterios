@echo off
:: Устанавливаем кодировку UTF-8 для корректного отображения символов.
chcp 65001 >nul

:: Проверяем наличие прав администратора. Если права есть, то переходим к основному коду, иначе перезапускаем скрипт с правами администратора.
net session >nul 2>&1
if %errorLevel% == 0 goto :main

:run_as_admin

:: Проверяем существование elevator.exe и запускаем с помощью него этот batch-скрипт от имени администратора.
if exist "%~dp0bin\elevator.exe" (
    "%~dp0bin\elevator.exe" "%~f0"
) else (
    echo [Ошибка] Файл elevator.exe не найден по пути: "%~dp0bin\elevator.exe"
    pause
)

exit /b

:main

:: Очищаем кэш DNS
ipconfig /flushdns

:: Включаем TCP timestamps (временные метки TCP), необходимые для работы функции фулинга - tcp_ts
netsh int tcp set global timestamps=enable

:: Проверяем существование winws2.exe
if not exist "%~dp0bin\winws2.exe" (
    echo [Ошибка] Файл winws2.exe не найден по пути: "%~dp0bin\winws2.exe"
    pause
    exit /b
)

:: Запускаем наш zapret2 в свернутом окне
start "zapret2 %~n0" /min "%~dp0bin\winws2.exe" ^
--wf-tcp-out=80,443,2100-2110 --wf-udp-out=443 ^
--lua-init=@"%~dp0lua\zapret-lib.lua" --lua-init=@"%~dp0lua\zapret-antidpi.lua" ^
--blob=tls_google:@"%~dp0fakes\tls_clienthello_www_google_com.bin" ^
--blob=quic_google:@"%~dp0fakes\quic_initial_www_google_com.bin" ^
--filter-tcp=80,443 ^
  --out-range=-d0 ^
  --ipset="%~dp0lists\ipset-asterios.txt" ^
    --lua-desync=send ^
    --lua-desync=syndata:blob=tls_google:tls_mod=rnd,sni=www.broadcom.com:tcp_ts=-100000 ^
  --new ^
--filter-udp=443 --filter-l7=quic ^
  --out-range=-d10 ^
  --payload=quic_initial ^
  --ipset="%~dp0lists\ipset-asterios.txt" ^
    --lua-desync=fake:blob=quic_google:tcp_ts=-100000 ^
  --new ^
--filter-tcp=2100-2110 --filter-l3=ipv4 ^
  --out-range=d1-d1 ^
  --ipset="%~dp0lists\ipset-asteriosgame.txt" ^
    --lua-desync=fake:payload=all:blob=tls_google:tls_mod=rnd,sni=www.win-rar.com:tcp_ts=-100000
