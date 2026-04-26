-- Name        : custom-redirect.lua
-- Author      : 7rozen
-- Date        : 2026.06.21
-- GitHub      : https://github.com/7rozen/zapret-asterios
-- Description : Lua модуль для перенаправления трафика на заданный IP-адрес.

local target_ip = nil
local has_target_ip = false
local conn_table = {}

local function setup_target_ip(ip_or_path)
    has_target_ip = true

    local is_path = string.find(ip_or_path, "/usr/bin/") or string.find(ip_or_path, "/bin/")
    local ip = nil

    if is_path then
        local f = io.open(ip_or_path, "r")
        if f then
            local line = f:read("*l")
            f:close()
            if line then
                ip = pton(line)
            end
        end
    else
        ip = pton(ip_or_path)
    end

    if ip and #ip == 4 then
        target_ip = ip
        DLOG_CONDUP("custom_redirect: Target IP set to " .. ntop(target_ip))
    end
end

function custom_redirect(ctx, desync)
    if not desync.arg.ip or not desync.dis.ip or not desync.dis.tcp then
        return VERDICT_PASS
    end

    if not has_target_ip then
        setup_target_ip(desync.arg.ip)
    end

    local modified = false
    if desync.outgoing then
        if desync.dis.ip.ip_dst ~= target_ip then
            local key = desync.dis.ip.ip_src .. desync.dis.tcp.th_sport
            if bitand(desync.dis.tcp.th_flags, TH_SYN + TH_ACK) == TH_SYN then
                conn_table[key] = desync.dis.ip.ip_dst
            end

            if conn_table[key] then
                desync.dis.ip.ip_dst = target_ip
                desync.track, desync.outgoing = conntrack_feed(desync.dis)
                modified = true
            end
        end
    else
        if desync.dis.ip.ip_src == target_ip then
            local key = desync.dis.ip.ip_dst .. desync.dis.tcp.th_dport
            if conn_table[key] then
                desync.dis.ip.ip_src = conn_table[key]
                desync.track, desync.outgoing = conntrack_feed(desync.dis)
                modified = true
            end
        end
    end

    if bitand(desync.dis.tcp.th_flags, TH_FIN + TH_RST) ~= 0 then
        local key = desync.dis.ip.ip_src .. desync.dis.tcp.th_sport
        conn_table[key] = nil

        key = desync.dis.ip.ip_dst .. desync.dis.tcp.th_dport
        conn_table[key] = nil
    end

    if modified then
        return VERDICT_MODIFY
    end

    return VERDICT_PASS
end
