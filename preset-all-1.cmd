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
--wf-tcp-out=80,443,1024-65535 --wf-udp-out=443,500,1024-65535 ^
--lua-init=@"%~dp0lua\zapret-lib.lua" --lua-init=@"%~dp0lua\zapret-antidpi.lua" ^
--blob=tls_google:@"%~dp0fakes\tls_clienthello_www_google_com.bin" ^
--blob=quic_google:@"%~dp0fakes\quic_initial_www_google_com.bin" ^
--template=tpl_http_tls_base ^
  --filter-tcp=80,443 --filter-l7=http,tls ^
  --out-range=-d10 ^
    --payload=http_req,tls_client_hello ^
--new ^
--template=tpl_tls_obfuscation ^
  --lua-desync=multidisorder:pos=1,midsld ^
  --lua-desync=multisplit:pos=1,midsld:seqovl=461:seqovl_pattern=tls_google ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-akamai-as16625.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.microsoft.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-akamai-as20940.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.nvidia.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-akamai-as63949.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=kernel.org:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-aquaray-as41653.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.aquaray.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-aws-as14618.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=nvidia.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-aws-as16509.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.opera.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-cdn77-as60068.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=docs.plesk.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-cdn77-as212238.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=packagist.org:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-cdnvideo-as57363.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=i0.photo.2gis.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-cloudflare-as13335.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.broadcom.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-ddosguard-as57724.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=tile0.maps.2gis.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-digitalocean-as14061.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.aida64.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-fastly-as54113.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.firefox.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-google-as15169.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.google.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-gthost-as63023.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=postimages.org:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-hetzner-as24940.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=7-zip.org:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-hosteurope-as21499.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.secureserver.net:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-hosteurope-as34011.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=hosteurope.de:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-iqweb-as59692.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=ddos-guard.net:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-oracle-as31898.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=mysql.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset="%~dp0lists\ipset-ovh-as16276.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=www.win-rar.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--import tpl_http_tls_base --ipset-exclude="%~dp0lists\ipset-special.txt" ^
  --lua-desync=fake:blob=tls_google:tls_mod=rnd,sni=googleapis.com:tcp_ts=-100000 ^
  --import tpl_tls_obfuscation ^
--new ^
--filter-tcp=2100-2110 --filter-l3=ipv4 ^
  --out-range=d1-d1 ^
  --ipset="%~dp0lists\ipset-asteriosgame.txt" ^
    --lua-desync=fake:payload=all:blob=tls_google:tls_mod=rnd,sni=www.win-rar.com:tcp_ts=-100000 ^
  --new ^
--filter-tcp=1024-65535 ^
  --out-range=d1-d1 ^
  --ipset-exclude="%~dp0lists\ipset-special.txt" ^
    --lua-desync=fake:payload=all:blob=tls_google:tls_mod=rnd,sni=googleapis.com:tcp_ts=-100000 ^
  --new ^
--filter-udp=443 --filter-l7=quic ^
  --out-range=-d10 ^
  --payload=quic_initial ^
  --ipset-exclude="%~dp0lists\ipset-special.txt" ^
    --lua-desync=fake:blob=quic_google:tcp_ts=-100000 ^
  --new ^
--filter-udp=500,1024-65535 ^
  --out-range=d1-d1 ^
  --ipset-exclude="%~dp0lists\ipset-special.txt" ^
    --lua-desync=fake:payload=all:blob=quic_google:tcp_ts=-100000
