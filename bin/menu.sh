#!/bin/bash

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

WINDOW_TITLE="ZAPRET-ASTERIOS"
UI_COLS=101
UI_LINES=31

printf "\x1B]2;%s\a" "${WINDOW_TITLE}"
mode.com con cols="${UI_COLS}" lines="${UI_LINES}"

BIN_DIR="/usr/bin"
export PATH="${BIN_DIR}:${PATH}"
BIN_DIR_M="$(cygpath -a -m "${BIN_DIR}")"
ROOT_DIR="${BIN_DIR_M%/*}"
cd "${ROOT_DIR}" || exit 1

PRESETS_DIR="./presets"
CONFIGS_DIR="${BIN_DIR}/configs"

STATE_FILE="${CONFIGS_DIR}/state"
DNS_FILE="${CONFIGS_DIR}/dns"
DNS_LIST_FILE="${CONFIGS_DIR}/dns_list"
REDIRECT_FILE="${CONFIGS_DIR}/redirect"
SERVERS_FILE="${CONFIGS_DIR}/servers"

C_GRAY=$'\x1B[38;2;100;100;100m'
C_WHITE=$'\x1B[38;2;240;240;240m'
C_RED=$'\x1B[38;2;230;50;50m'
C_GREEN=$'\x1B[38;2;50;200;50m'
C_YELLOW=$'\x1B[38;2;240;180;20m'
C_RESET=$'\x1B[0m'

C_SELECTED_TEXT=$'\x1B[38;2;0;230;255m'
C_SELECTED_MARKER=$'\x1B[48;2;0;150;180m\x1B[38;2;255;255;255m'

CURSOR_HIDE=$'\x1B[?25l'
CURSOR_SHOW=$'\x1B[?25h'

KEY_ESCAPE=$'\x1B'
KEY_UP=$'\x1B[A'
KEY_DOWN=$'\x1B[B'
KEY_ENTER=''
KEY_BACKSPACE=$'\x7F'

HEADER_LINES=5
FOOTER_LINES=5
FOOTER_TEXT_LINES=3
BODY_LINES=$(( UI_LINES - HEADER_LINES - FOOTER_LINES - 1 ))

AUTHOR="7rozen"
VERSION="2026.06.27"
UPDATE="Ошибка проверки обновлений"

CURRENT_PRESET_NAME="Не выбран"
CURRENT_PRESET_FILE=""
CURRENT_SERVER="Не выбран"
CURRENT_DNS="Не выбран"

CURRENT_SCREEN="MAIN"
CURSOR=0
LAST_CURSOR=-1
LIST_SCROLL=0
DESCRIPTION=""
TOTAL_ITEMS=0
USED_BODY_LINES=0

PRESET_FILES=()
PRESET_NAMES=()
PRESET_DESCS=()

SERVER_IPS=()
SERVER_TYPES=()
SERVER_CITIES=()
SERVER_DESCS=()

DNS_IPS=()
DNS_NAMES=()
DNS_DESCS=()

SERVICES=(zapret redirect dns)

declare -A SERVICE_PID_FILE=(
    [zapret]="${CONFIGS_DIR}/zapret.pid"
    [redirect]="${CONFIGS_DIR}/redirect.pid"
    [dns]="${CONFIGS_DIR}/dns.pid"
)

declare -A SERVICE_STATUS=(
    [zapret]=""
    [redirect]=""
    [dns]=""
)
declare -A SERVICE_RUNNING

printf -v border_filler '%*s' "$(( UI_COLS - 3 ))" ''
BORDER_TOP="┌${border_filler// /─}┐"
BORDER_MID="├${border_filler// /─}┤"
BORDER_BOT="└${border_filler// /─}┘"
unset border_filler

check_update() {
    local latest_version
    latest_version=$(powershell.exe -NoProfile -Command "
        try {
            \$req = [System.Net.WebRequest]::Create('https://api.github.com/repos/7rozen/zapret-asterios/releases/latest');
            \$req.Timeout = 3000;
            \$req.UserAgent = 'Mozilla/5.0';

            \$res = \$req.GetResponse();
            \$stream = \$res.GetResponseStream();
            \$reader = New-Object System.IO.StreamReader(\$stream);
            \$json = \$reader.ReadToEnd();

            \$reader.Close(); \$stream.Close(); \$res.Close();

            if (\$json -match '\"tag_name\":\s*\"([^\"]+)\"') { \$Matches[1] }
        } catch {
            exit 1
        }
    " 2>/dev/null)

    if [[ $? -ne 0 ]] || [[ -z "$latest_version" ]]; then
        UPDATE="${C_RED}(Ошибка проверки обновлений)${C_RESET}"
        return 1
    fi

    latest_version="${latest_version//$'\r'/}"

    if [[ "$latest_version" > "$VERSION" ]]; then
        UPDATE="${C_YELLOW}(Доступно обновление: $latest_version)${C_RESET}"
    else
        UPDATE="${C_GREEN}(Обновлений нет)${C_RESET}"
    fi
}

save_state() {
    {
        printf "CURRENT_PRESET_NAME=%s\n" "${CURRENT_PRESET_NAME}"
        printf "CURRENT_PRESET_FILE=%s\n" "${CURRENT_PRESET_FILE}"
        printf "CURRENT_SERVER=%s\n" "${CURRENT_SERVER}"
        printf "CURRENT_DNS=%s\n" "${CURRENT_DNS}"
        printf "ZAPRET_RUNNING=%s\n" "${SERVICE_RUNNING[zapret]}"
        printf "REDIRECT_RUNNING=%s\n" "${SERVICE_RUNNING[redirect]}"
        printf "DNS_RUNNING=%s\n" "${SERVICE_RUNNING[dns]}"
    } > "${STATE_FILE}"
}

load_state() {
    local key value
    if [[ -f "${STATE_FILE}" ]]; then
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue

            key="${key// /}"

            case "$key" in
                CURRENT_PRESET_NAME) CURRENT_PRESET_NAME="$value" ;;
                CURRENT_PRESET_FILE) CURRENT_PRESET_FILE="$value" ;;
                CURRENT_SERVER) CURRENT_SERVER="$value" ;;
                CURRENT_DNS)    CURRENT_DNS="$value" ;;
                ZAPRET_RUNNING) SERVICE_RUNNING[zapret]="$value" ;;
                REDIRECT_RUNNING) SERVICE_RUNNING[redirect]="$value" ;;
                DNS_RUNNING) SERVICE_RUNNING[dns]="$value" ;;
            esac
        done < "${STATE_FILE}"

        local svc
        for svc in "${SERVICES[@]}"; do
            if [[ "${SERVICE_RUNNING[$svc]}" == "1" ]] && ! service_is_running "$svc"; then
                service_start "$svc"
            fi
        done
    fi
}

load_presets() {
    local file filename preset_name preset_desc line lines_count

    PRESET_FILES=()
    PRESET_NAMES=()
    PRESET_DESCS=()

    shopt -s nullglob
    for file in "${PRESETS_DIR}"/*.txt; do
        filename="${file##*/}"
        PRESET_FILES+=("${filename}")

        preset_name=""
        preset_desc="Описание к данному пресету отсутствует."
        lines_count=0

        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            [[ "$line" =~ ^#[[:space:]]* ]] && (( ++lines_count <= 20 )) || break

            if [[ "$line" =~ ^#[[:space:]]*[Nn]ame[[:space:]]*:[[:space:]]*(.*) ]]; then
                preset_name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^#[[:space:]]*[Dd]escription[[:space:]]*:[[:space:]]*(.*) ]]; then
                preset_desc="${BASH_REMATCH[1]}"
            fi
        done < "$file"

        [[ -z "$preset_name" ]] && preset_name="$filename"

        PRESET_NAMES+=("$preset_name")
        PRESET_DESCS+=("$preset_desc")
    done
    shopt -u nullglob

    if [[ ${#PRESET_FILES[@]} -gt 0 ]] && [[ "${CURRENT_PRESET_NAME}" = "Не выбран" ]]; then
        CURRENT_PRESET_NAME="${PRESET_NAMES[0]}"
        CURRENT_PRESET_FILE="${PRESET_FILES[0]}"
    fi
}

load_servers() {
    local line ip type city desc

    SERVER_IPS=()
    SERVER_TYPES=()
    SERVER_CITIES=()
    SERVER_DESCS=()

    [[ -f "${SERVERS_FILE}" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        IFS='|' read -r ip type city desc <<< "$line"

        SERVER_IPS+=("$ip")
        SERVER_TYPES+=("$type")
        SERVER_CITIES+=("$city")
        SERVER_DESCS+=("$desc")
    done < "${SERVERS_FILE}"
}

load_dns() {
    local line ip name desc

    DNS_IPS=()
    DNS_NAMES=()
    DNS_DESCS=()

    [[ -f "${DNS_LIST_FILE}" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        IFS='|' read -r ip name desc <<< "$line"

        DNS_IPS+=("$ip")
        DNS_NAMES+=("$name")
        DNS_DESCS+=("$desc")
    done < "${DNS_LIST_FILE}"
}

apply_dns() {
    local ip="$1"

    printf '%s\n' "$ip" > "${DNS_FILE}"

    if service_is_running dns; then
        service_restart dns
        service_status_update dns
    fi
}

apply_server() {
    local ip="$1"

    printf '%s\n' "$ip" > "${REDIRECT_FILE}"

    if service_is_running redirect; then
        service_restart redirect
        service_status_update redirect
    fi
}

service_is_running() {
    local svc="$1"
    local _out="${2:-}"
    local _pid
    local pidfile="${SERVICE_PID_FILE[$svc]}"

    [[ -f "$pidfile" ]] || return 1

    read -r _pid < "$pidfile" 2>/dev/null
    [[ "$_pid" =~ ^[0-9]+$ ]] || return 1

    if kill -0 "$_pid" 2>/dev/null; then
        [[ -n "$_out" ]] && printf -v "$_out" '%s' "$_pid"
        return 0
    fi

    return 1
}

service_status_update() {
    local svc="$1"
    local status_running="${2:-ЗАПУЩЕН}"
    local status_stopped="${3:-ОСТАНОВЛЕН}"
    local pid wpid

    if service_is_running "$svc" pid; then
        [[ -f "/proc/$pid/winpid" ]] && read -r wpid < "/proc/$pid/winpid" 2>/dev/null
        SERVICE_STATUS[$svc]="${C_GREEN}${status_running} (PID: $pid${wpid:+, WPID: $wpid})${C_RESET}"
        SERVICE_RUNNING[$svc]=1
    else
        SERVICE_STATUS[$svc]="${C_GRAY}${status_stopped}${C_RESET}"
        SERVICE_RUNNING[$svc]=0
    fi
}

services_status_update_all() {
    local svc
    for svc in "${SERVICES[@]}"; do
        service_status_update "$svc"
    done
}

service_stop() {
    local svc="$1"
    local pid

    service_is_running "$svc" pid || return 1

    kill -TERM "$pid" 2>/dev/null

    local i
    for (( i=0; i<30; i++ )); do
        sleep 0.1
        kill -0 "$pid" 2>/dev/null || break
    done

    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null

    return 0
}

service_start() {
    local svc="$1"
    local preset

    case "$svc" in
        zapret)   preset="${PRESETS_DIR}/${CURRENT_PRESET_FILE}" ;;
        redirect) preset="${PRESETS_DIR}/.custom-redirect.txt" ;;
        dns)      preset="${PRESETS_DIR}/.custom-dns.txt" ;;
        *)        return 1 ;;
    esac

    [[ -f "$preset" ]] || return 1

    local attempt
    for (( attempt=1; attempt<=3; attempt++ )); do
        [[ "$svc" == "dns" ]] && cygstart --hide ipconfig /flushdns
        cygstart --hide winws2.exe --daemon --pidfile="${SERVICE_PID_FILE[$svc]}" @"$preset"

        local i
        for (( i=0; i<30; i++ )); do
            service_is_running "$svc" && return 0
            sleep 0.1
        done
    done

    return 1
}

service_toggle() {
    local svc="$1"
    service_stop "$svc" || service_start "$svc"
}

service_restart() {
    local svc="$1"
    service_stop "$svc"
    service_start "$svc"
}

service_button_label() {
    local svc="$1"
    local _out="$2"
    local _label="[ Запустить  ]"

    [[ "${SERVICE_RUNNING[$svc]}" == "1" ]] && _label="[ Остановить ]"

    printf -v "$_out" '%s' "$_label"
}

draw_row() {
    local idx=$1
    local label=$2
    local info=${3:-}

    local pad=$(( UI_COLS * 40 / 100 ))

    local label_len=${#label}
    local pad_len=$((pad - label_len))
    if [[ $pad_len -lt 0 ]]; then pad_len=0; fi
    local spaces
    printf -v spaces '%*s' "$pad_len" ''

    if [[ $CURSOR -eq $idx ]]; then
        printf " ${C_SELECTED_MARKER}>${C_RESET} ${C_SELECTED_TEXT}%s%s${C_RESET} %s\x1B[K\n" "$label" "$spaces" "$info"
    else
        printf "   ${C_WHITE}%s%s${C_RESET} %s\x1B[K\n" "$label" "$spaces" "$info"
    fi

    ((USED_BODY_LINES++))
}

draw_category() {
    local title=$1
    local title_len=${#title}
    local dash_len=$((UI_COLS - title_len - 6))
    if [[ $dash_len -lt 0 ]]; then dash_len=0; fi

    local dashes
    printf -v dashes '%*s' "$dash_len" ''
    dashes="${dashes// /─}"

    printf "${C_GRAY}┌─${C_RESET} ${C_GRAY}${title}${C_RESET} ${C_GRAY}%s┐${C_RESET}\x1B[K\n" "$dashes"

    ((USED_BODY_LINES++))
}

draw_category_end() {
    printf "${C_GRAY}%s${C_RESET}\x1B[K\n" "$BORDER_BOT"

    ((USED_BODY_LINES++))
}

strip_ansi() {
    local _out="$1"
    local text="$2"

    shopt -s extglob
    printf -v "$_out" '%s' "${text//$'\x1B'\[*([0-9;])m/}"
    shopt -u extglob
}

get_padding_spaces() {
    local _out="$1"
    local text="$2"
    local width="$3"

    local visible_text
    strip_ansi visible_text "$text"

    local pad_len=$(( width - ${#visible_text} ))
    (( pad_len < 0 )) && pad_len=0

    printf -v "$_out" '%*s' "$pad_len" ''
}

draw_header() {
    local width=$(( UI_COLS - 5 ))
    local line1 line2 spaces spaces2

    line1="${WINDOW_TITLE} ${C_GRAY}│${C_RESET} Автор: ${AUTHOR} ${C_GRAY}│${C_RESET} Версия: ${VERSION} ${UPDATE}"
    line2="Управление: Стрелки [↑] [↓] ${C_GRAY}│${C_RESET} Выбор: [Enter] ${C_GRAY}│${C_RESET} Назад: [Backspace]"

    get_padding_spaces spaces  "$line1" "$width"
    get_padding_spaces spaces2 "$line2" "$width"

    printf "${C_GRAY}%s${C_RESET}\x1B[K\n" "$BORDER_TOP"
    printf "${C_GRAY}│${C_RESET} %s%s ${C_GRAY}│${C_RESET}\x1B[K\n" "$line1" "$spaces"
    printf "${C_GRAY}%s${C_RESET}\x1B[K\n" "$BORDER_MID"
    printf "${C_GRAY}│${C_RESET} %s%s ${C_GRAY}│${C_RESET}\x1B[K\n" "$line2" "$spaces2"
    printf "${C_GRAY}%s${C_RESET}\x1B[K\n" "$BORDER_BOT"
}

draw_footer() {
    local desc_text="$1"
    local max_width=$(( UI_COLS - 5 ))
    local max_lines=${FOOTER_TEXT_LINES}
    local i line padding spaces

    printf "${C_GRAY}%s${C_RESET}\x1B[K\n" "$BORDER_TOP"

    for ((i=0; i<max_lines; i++)); do
        line=""
        if [[ -n "$desc_text" ]]; then
            if [[ ${#desc_text} -le $max_width ]]; then
                line="$desc_text"
                desc_text=""
            else
                local chunk="${desc_text:0:$max_width}"
                if [[ "${desc_text:$max_width:1}" == " " ]]; then
                    line="$chunk"
                    desc_text="${desc_text:$((max_width + 1))}"
                else
                    local wrapped="${chunk% *}"
                    if [[ -z "$wrapped" || "$wrapped" == "$chunk" ]]; then
                        line="$chunk"
                        desc_text="${desc_text:$max_width}"
                    else
                        line="$wrapped"
                        desc_text="${desc_text:$(( ${#line} + 1 ))}"
                    fi
                fi
            fi
        fi

        padding=$(( max_width - ${#line} ))
        spaces=""
        (( padding > 0 )) && printf -v spaces "%*s" "$padding" ""

        printf "${C_GRAY}│${C_RESET} ${C_YELLOW}%s%s${C_RESET} ${C_GRAY}│${C_RESET}\x1B[K\n" "$line" "$spaces"
    done

    printf "${C_GRAY}%s${C_RESET}\x1B[K\n" "$BORDER_BOT"
}

draw_screen_main() {
    TOTAL_ITEMS=10

    local btn_zapret btn_redirect btn_dns
    service_button_label zapret    btn_zapret
    service_button_label redirect  btn_redirect
    service_button_label dns       btn_dns

    draw_category "ZAPRET (ОБХОД DPI)"
    draw_row 0 "[ Выбрать пресет ]" "Текущий: ${CURRENT_PRESET_NAME}"
    draw_row 1 "$btn_zapret"        "Статус:  ${SERVICE_STATUS[zapret]}"
    draw_category_end

    draw_category "ПЕРЕНАПРАВЛЕНИЕ ИГРОВОГО ТРАФИКА"
    draw_row 2 "[ Выбрать сервер ]" "Текущий: ${CURRENT_SERVER}"
    draw_row 3 "$btn_redirect"      "Статус:  ${SERVICE_STATUS[redirect]}"
    draw_category_end

    draw_category "ПЕРЕХВАТ DNS"
    draw_row 4 "[ Выбрать DNS ]" "Текущий: ${CURRENT_DNS}"
    draw_row 5 "$btn_dns"        "Статус:  ${SERVICE_STATUS[dns]}"
    draw_category_end

    draw_category "ПРОЧЕЕ"
    draw_row 6 "[ Выгрузить драйвер WinDivert ]"
    draw_row 7 "[ Открыть репозиторий GitHub ]"
    draw_row 8 "[ Поддержать проект ]"
    draw_row 9 "[ Выход ]"
    draw_category_end

    local i
    local empty_rows=$(( BODY_LINES - USED_BODY_LINES ))
    for ((i=0; i<empty_rows; i++)); do
        printf " \x1B[K\n"
    done

    case $CURSOR in
        0) DESCRIPTION="Выбор конфигурационного файла (пресета) с параметрами для обхода блокировок DPI." ;;
        1)
            if [[ "${SERVICE_RUNNING[zapret]}" == "0" ]]; then
                DESCRIPTION="Запустить zapret с выбранным пресетом."
            else
                DESCRIPTION="Остановить zapret."
            fi
            ;;
        2) DESCRIPTION="Выбор игрового сервера или прокси для подключения к игре." ;;
        3)
            if [[ "${SERVICE_RUNNING[redirect]}" == "0" ]]; then
                DESCRIPTION="Запустить сервис перенаправления трафика."
            else
                DESCRIPTION="Остановить сервис перенаправления трафика."
            fi
            ;;
        4) DESCRIPTION="Выбрать DNS-сервер, на который будут перенаправляться DNS-запросы." ;;
        5)
            if [[ "${SERVICE_RUNNING[dns]}" == "0" ]]; then
                DESCRIPTION="Запустить сервис перехвата DNS-запросов."
            else
                DESCRIPTION="Остановить сервис перехвата DNS-запросов."
            fi
            ;;
        6) DESCRIPTION="Закрыть все процессы winws.exe и winws2.exe и выгрузить драйвер WinDivert из системы." ;;
        7) DESCRIPTION="Открыть официальную страницу проекта zapret-asterios на GitHub." ;;
        8) DESCRIPTION="Открыть страницу поддержки проекта. В первую очередь пожертвования пойдут на новые прокси для игры с хорошим пингом." ;;
        9) DESCRIPTION="После закрытия меню запущенные сервисы продолжат работать до перезагрузки компьютера." ;;
        *) DESCRIPTION="" ;;
    esac
}

draw_screen_preset() {
    local items_count=${#PRESET_FILES[@]}
    TOTAL_ITEMS=$(( items_count + 1 ))
    local max_visible=$(( BODY_LINES - 4 ))

    if [[ $CURSOR -eq 0 ]]; then
        LIST_SCROLL=0
    else
        local active_idx=$((CURSOR - 1))
        if [[ $active_idx -lt $LIST_SCROLL ]]; then
            LIST_SCROLL=$active_idx
        elif [[ $active_idx -ge $((LIST_SCROLL + max_visible)) ]]; then
            LIST_SCROLL=$((active_idx - max_visible + 1))
        fi
    fi

    draw_category "ВЫБОР ПРЕСЕТА"
    draw_row 0 "<-- Вернуться в главное меню"

    local g
    for ((g=0; g<max_visible; g++)); do
        local i=$((LIST_SCROLL + g))
        if [[ $i -lt $items_count ]]; then
            draw_row $((i + 1)) "${PRESET_NAMES[i]}"
        else
            printf " \x1B[K\n"
        fi
    done

    if [[ $items_count -gt $max_visible ]]; then
        local current_max=$((LIST_SCROLL + max_visible))
        if [[ $current_max -gt $items_count ]]; then current_max=$items_count; fi
        printf "   ${C_GRAY}Отображено $((LIST_SCROLL + 1))-$current_max из $items_count ${C_RESET}\x1B[K\n"
    else
        printf " \x1B[K\n"
    fi

    if [[ $items_count -eq 0 ]]; then
        printf "    ${C_YELLOW}(В папке presets/ нет .txt файлов)${C_RESET}\x1B[K\n"
    fi
    draw_category_end

    if [[ $CURSOR -gt 0 ]] && [[ $items_count -gt 0 ]]; then
        local selected_idx=$((CURSOR - 1))
        DESCRIPTION="${PRESET_DESCS[selected_idx]}"
    else
        DESCRIPTION="Вернуться в главное меню."
    fi
}

draw_screen_server() {
    local items_count=${#SERVER_IPS[@]}
    TOTAL_ITEMS=$(( items_count + 1 ))
    local max_visible=$(( BODY_LINES - 4 ))

    if [[ $CURSOR -eq 0 ]]; then
        LIST_SCROLL=0
    else
        local active_idx=$((CURSOR - 1))
        if [[ $active_idx -lt $LIST_SCROLL ]]; then
            LIST_SCROLL=$active_idx
        elif [[ $active_idx -ge $((LIST_SCROLL + max_visible)) ]]; then
            LIST_SCROLL=$((active_idx - max_visible + 1))
        fi
    fi

    draw_category "ВЫБОР ИГРОВОГО ИЛИ ПРОКСИ СЕРВЕРА"
    draw_row 0 "<-- Вернуться в главное меню"

    local g
    for ((g=0; g<max_visible; g++)); do
        local i=$((LIST_SCROLL + g))
        if [[ $i -lt $items_count ]]; then
            draw_row $((i + 1)) "${SERVER_IPS[i]} (${SERVER_TYPES[i]}, ${SERVER_CITIES[i]})"
        else
            printf " \x1B[K\n"
        fi
    done

    if [[ $items_count -gt $max_visible ]]; then
        local current_max=$((LIST_SCROLL + max_visible))
        [[ $current_max -gt $items_count ]] && current_max=$items_count
        printf "   ${C_GRAY}Отображено $((LIST_SCROLL + 1))-$current_max из $items_count ${C_RESET}\x1B[K\n"
    else
        printf " \x1B[K\n"
    fi

    if [[ $items_count -eq 0 ]]; then
        printf "    ${C_YELLOW}(Список игровых и прокси серверов пуст)${C_RESET}\x1B[K\n"
    fi
    draw_category_end

    if [[ $CURSOR -gt 0 && $items_count -gt 0 ]]; then
        local selected_idx=$((CURSOR - 1))
        DESCRIPTION="${SERVER_DESCS[selected_idx]}"
    else
        DESCRIPTION="Вернуться в главное меню."
    fi
}

draw_screen_dns() {
    local items_count=${#DNS_IPS[@]}
    TOTAL_ITEMS=$(( items_count + 1 ))
    local max_visible=$(( BODY_LINES - 4 ))

    if [[ $CURSOR -eq 0 ]]; then
        LIST_SCROLL=0
    else
        local active_idx=$((CURSOR - 1))
        if [[ $active_idx -lt $LIST_SCROLL ]]; then
            LIST_SCROLL=$active_idx
        elif [[ $active_idx -ge $((LIST_SCROLL + max_visible)) ]]; then
            LIST_SCROLL=$((active_idx - max_visible + 1))
        fi
    fi

    draw_category "ВЫБОР DNS-СЕРВЕРА"
    draw_row 0 "<-- Вернуться в главное меню"

    local g
    for ((g=0; g<max_visible; g++)); do
        local i=$((LIST_SCROLL + g))
        if [[ $i -lt $items_count ]]; then
            draw_row $((i + 1)) "${DNS_IPS[i]} (${DNS_NAMES[i]})"
        else
            printf " \x1B[K\n"
        fi
    done

    if [[ $items_count -gt $max_visible ]]; then
        local current_max=$((LIST_SCROLL + max_visible))
        [[ $current_max -gt $items_count ]] && current_max=$items_count
        printf "   ${C_GRAY}Отображено $((LIST_SCROLL + 1))-$current_max из $items_count ${C_RESET}\x1B[K\n"
    else
        printf " \x1B[K\n"
    fi

    if [[ $items_count -eq 0 ]]; then
        printf "    ${C_YELLOW}(Список DNS-серверов пуст)${C_RESET}\x1B[K\n"
    fi
    draw_category_end

    if [[ $CURSOR -gt 0 && $items_count -gt 0 ]]; then
        local selected_idx=$((CURSOR - 1))
        DESCRIPTION="${DNS_DESCS[selected_idx]}"
    else
        DESCRIPTION="Вернуться в главное меню."
    fi
}

draw_ui() {
    if [[ $CURSOR -eq $LAST_CURSOR ]]; then
        return
    fi
    printf "${CURSOR_HIDE}"
    printf "\x1B[H"

    draw_header
    case "$CURRENT_SCREEN" in
        "MAIN") draw_screen_main ;;
        "PRESET") draw_screen_preset ;;
        "SERVER") draw_screen_server ;;
        "DNS") draw_screen_dns ;;
    esac
    draw_footer "${DESCRIPTION}"

    printf "\x1B[J"

    LAST_CURSOR=$CURSOR
}

main_loop() {
    local key extension
    local selected_idx
    while true; do
        USED_BODY_LINES=0
        draw_ui

        IFS= read -rsn1 key
        if [[ $key == "$KEY_ESCAPE" ]]; then
            read -rsn2 -t 0.02 extension
            key+="$extension"
        fi

        case "$key" in
            "$KEY_BACKSPACE")
                if [[ "$CURRENT_SCREEN" != "MAIN" ]]; then
                    CURRENT_SCREEN="MAIN"; CURSOR=0; LAST_CURSOR=-1
                fi
                ;;
            "$KEY_UP")
                ((CURSOR--))
                if [[ $CURSOR -lt 0 ]]; then CURSOR=$((TOTAL_ITEMS - 1)); fi
                ;;
            "$KEY_DOWN")
                ((CURSOR++))
                if [[ $CURSOR -ge $TOTAL_ITEMS ]]; then CURSOR=0; fi
                ;;
            "$KEY_ENTER")
                case $CURRENT_SCREEN in
                    "MAIN")
                        case $CURSOR in
                            0)
                                load_presets
                                CURRENT_SCREEN="PRESET"; CURSOR=0; LAST_CURSOR=-1
                                ;;
                            1)
                                service_toggle zapret
                                service_status_update zapret
                                save_state
                                LAST_CURSOR=-1
                                ;;
                            2)
                                load_servers
                                CURRENT_SCREEN="SERVER"; CURSOR=0; LAST_CURSOR=-1
                                ;;
                            3)
                                service_toggle redirect
                                service_status_update redirect
                                save_state
                                LAST_CURSOR=-1
                                ;;
                            4)
                                load_dns
                                CURRENT_SCREEN="DNS"; CURSOR=0; LAST_CURSOR=-1
                                ;;
                            5)
                                service_toggle dns
                                service_status_update dns
                                save_state
                                LAST_CURSOR=-1
                                ;;
                            6)
                                cygstart --hide taskkill /f /im winws.exe
                                cygstart --hide taskkill /f /im winws2.exe
                                cygstart --hide sc delete windivert
                                cygstart --hide sc stop windivert
                                cygstart --hide sc delete monkey
                                cygstart --hide sc stop monkey
                                services_status_update_all
                                save_state
                                LAST_CURSOR=-1
                                ;;
                            7)  cygstart https://github.com/7rozen/zapret-asterios
                                ;;
                            8)  cygstart https://yoomoney.ru/fundraise/1IHOUSVDI1R.260621
                                ;;
                            9)
                                break
                                ;;
                        esac
                        ;;
                    "PRESET")
                        case $CURSOR in
                            0)
                                CURRENT_SCREEN="MAIN"; CURSOR=0; LAST_CURSOR=-1
                                ;;
                            *)
                                selected_idx=$((CURSOR - 1))
                                CURRENT_PRESET_NAME="${PRESET_NAMES[selected_idx]}"
                                CURRENT_PRESET_FILE="${PRESET_FILES[selected_idx]}"

                                if service_is_running zapret; then
                                    service_restart zapret
                                fi
                                service_status_update zapret
                                save_state

                                CURRENT_SCREEN="MAIN"; CURSOR=0; LAST_CURSOR=-1
                                ;;
                        esac
                        ;;
                    "SERVER")
                        case $CURSOR in
                            0)
                                CURRENT_SCREEN="MAIN"; CURSOR=0; LAST_CURSOR=-1
                                ;;
                            *)
                                selected_idx=$((CURSOR - 1))
                                CURRENT_SERVER="${SERVER_IPS[selected_idx]} (${SERVER_TYPES[selected_idx]}, ${SERVER_CITIES[selected_idx]})"
                                apply_server "${SERVER_IPS[selected_idx]}"
                                service_status_update redirect
                                save_state
                                CURRENT_SCREEN="MAIN"; CURSOR=0; LAST_CURSOR=-1
                                ;;
                        esac
                        ;;
                    "DNS")
                        case $CURSOR in
                            0)
                                CURRENT_SCREEN="MAIN"; CURSOR=0; LAST_CURSOR=-1
                                ;;
                            *)
                                selected_idx=$((CURSOR - 1))
                                CURRENT_DNS="${DNS_IPS[selected_idx]} (${DNS_NAMES[selected_idx]})"
                                if [[ "${DNS_IPS[selected_idx]}" == "Системный" ]]; then
                                    CURRENT_DNS_IP=""
                                else
                                    CURRENT_DNS_IP="${DNS_IPS[selected_idx]}"
                                fi
                                apply_dns "${CURRENT_DNS_IP}"
                                service_status_update dns
                                save_state
                                CURRENT_SCREEN="MAIN"; CURSOR=0; LAST_CURSOR=-1
                                ;;
                        esac
                        ;;
                esac
                ;;
        esac
    done
}

main() {
    printf "Инициализация: Проверка обновлений...\n"
    check_update
    printf "\x1B]2;%s\a" "${WINDOW_TITLE}"
    printf "Инициализация: Загрузка сохраненного состояния и запуск сервисов...\n"
    load_state
    services_status_update_all
    cygstart --hide netsh int tcp set global timestamps=enable

    main_loop
}

main
