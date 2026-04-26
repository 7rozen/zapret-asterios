-- https://github.com/7rozen/zapret-asterios

local target_dns_ip = nil
local dns_conn_table = {}

local hosts_table = {}

local DNS_HEADER_LEN = 12

local QTYPE_A = "\x00\x01"
local QTYPE_AAAA = "\x00\x1c"

local function print_hosts()
    if next(hosts_table) == nil then
        DLOG_CONDUP("custom_dns: hosts_table is empty")
        return
    end

    for host, records in pairs(hosts_table) do
        for _, ip in ipairs(records.v4) do
            DLOG_CONDUP("custom_dns: " .. ntop(ip) .. " " .. host)
        end

        for _, ip in ipairs(records.v6) do
            DLOG_CONDUP("custom_dns: " .. ntop(ip) .. " " .. host)
        end
    end
end

local function load_hosts()
    local path = "/usr/bin/hosts"
    local f = io.open(path, "r")
    if f then
        local count = 0
        for line in f:lines() do
            local clean_line = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
            local ip_str, host = clean_line:match("^([%x%.%:]+)%s+([%w%.%-]+)$")
            if ip_str and host then
                local ip = pton(ip_str)
                if ip then
                    host = host:lower()
                    if not hosts_table[host] then
                        hosts_table[host] = { v4 = {}, v6 = {} }
                    end

                    if #ip == 4 then
                        table.insert(hosts_table[host].v4, ip)
                    else
                        table.insert(hosts_table[host].v6, ip)
                    end
                    count = count + 1
                end
            end
        end
        f:close()
        DLOG_CONDUP("custom_dns: loaded " .. count .. " records from hosts file")
    else
        DLOG_CONDUP("custom_dns: hosts file not found at " .. path)
    end
end

load_hosts()
-- print_hosts()

local function get_dns_qname(payload)
    local labels = {}
    local i = DNS_HEADER_LEN + 1
    while i <= #payload do
        local len = payload:byte(i)
        if len == 0 then break end
        table.insert(labels, payload:sub(i + 1, i + len))
        i = i + len + 1
    end
    return table.concat(labels, "."):lower()
end

local function get_dns_qtype(payload)
    return payload:sub(-4, -3)
end

local function build_dns_response(payload, ips, qtype)
    local id = payload:sub(1, 2)         -- Идентификатор запроса
    local flags = "\x81\x80"             -- Флаги: стандартный ответ, авторитетный ответ, без ошибок
    local qdcount = payload:sub(5, 6)    -- Количество вопросов
    local ancount = string.char(0, #ips) -- Количество ответов (равно количеству IP-адресов)
    local nscount = "\x00\x00"           -- Количество NS-записей
    local arcount = "\x00\x00"           -- Количество дополнительных записей
    local questions = payload:sub(13)    -- Вопросы

    local response = id .. flags .. qdcount .. ancount .. nscount .. arcount .. questions
    for _, ip in ipairs(ips) do
        if qtype == QTYPE_A then
            response = response .. "\xC0\x0C\x00\x01\x00\x01\x00\x00\x01\x2C\x00\x04" .. ip
        elseif qtype == QTYPE_AAAA then
            response = response .. "\xC0\x0C\x00\x1C\x00\x01\x00\x00\x01\x2C\x00\x10" .. ip
        end
    end
    return response
end

--[[ 
Пример использования:

--wf-udp-out=53
--wf-udp-in=53
--wf-filter-lan=0

--new
--filter-udp=53
--filter-l7=dns
--in-range=a
--payload=dns_query,dns_response
--lua-desync=custom_dns:ip=83.220.169.155

# Comss DNS: 83.220.169.155 195.133.25.16 212.109.195.93
# Google DNS: 8.8.8.8 8.8.4.4
# Cloudflare DNS: 1.1.1.1 1.0.0.1
# Quad9 DNS: 9.9.9.9 149.112.112.112
]]

-- args: ip - IP-адрес, на который будут перенаправляться DNS-запросы. Если не указан, будет использоваться Comss DNS (83.220.169.155)
function custom_dns(ctx, desync)
    if not desync.dis.ip or not desync.dis.udp or desync.l7proto ~= "dns" then
        return VERDICT_PASS
    end

    if desync.l7payload == "dns_query" then

        if next(hosts_table) then
            local payload = desync.dis.payload
            if #payload > DNS_HEADER_LEN and payload:sub(5, 6) == "\x00\x01" then
                local host = get_dns_qname(payload)
                local entry = host and hosts_table[host] or nil
                if entry then
                    local qtype = get_dns_qtype(payload)
                    local ips = (qtype == QTYPE_A) and entry.v4 or (qtype == QTYPE_AAAA and entry.v6 or nil)
                    if ips then
                        local response = build_dns_response(payload, ips, qtype)
                        desync.dis.payload = response
                        dis_reverse(desync.dis)
                        desync.track, desync.outgoing = conntrack_feed(desync.dis)
                        rawsend_dissect(desync.dis)

                        if b_debug then 
                            DLOG("custom_dns: responded to " .. host .. " with " .. #ips .. " record(s)")
                            for _, ip in ipairs(ips) do
                                DLOG("custom_dns: " .. host .. " -> " .. ntop(ip))
                            end
                        end

                        return VERDICT_DROP
                    end
                end
            end
        end

        if not target_dns_ip then
            target_dns_ip = pton(desync.arg.ip) or "\x53\xDC\xA9\x9B"
            DLOG_CONDUP("custom_dns: DNS queries will be redirected to " .. ntop(target_dns_ip))
        end

        local key = desync.dis.ip.ip_src .. desync.dis.udp.uh_sport
        dns_conn_table[key] = desync.dis.ip.ip_dst

        if b_debug then 
            DLOG("custom_dns: redirecting " .. ntop(desync.dis.ip.ip_dst) .. " -> " .. ntop(target_dns_ip)) 
        end

        desync.dis.ip.ip_dst = target_dns_ip
        desync.track, desync.outgoing = conntrack_feed(desync.dis)

        return VERDICT_MODIFY
    end

    -- TODO: Придумать механизм очистки таблицы dns_conn_table на случай если DNS-ответ не придёт
    if desync.l7payload == "dns_response" then
        local key = desync.dis.ip.ip_dst .. desync.dis.udp.uh_dport
        local original_ip = dns_conn_table[key]

        if original_ip then
            if b_debug then 
                DLOG("custom_dns: restoring source " .. ntop(desync.dis.ip.ip_src) .. " -> " .. ntop(original_ip)) 
            end

            desync.dis.ip.ip_src = original_ip
            dns_conn_table[key] = nil 
            desync.track, desync.outgoing = conntrack_feed(desync.dis)

            return VERDICT_MODIFY
        end
    end

    return VERDICT_PASS
end
