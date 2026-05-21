#!/usr/bin/env lua

local jsonc_ok, jsonc = pcall(require, "luci.jsonc")
local nixio_ok, nixio = pcall(require, "nixio")

local JSON_ARRAY_MT = { __jsontype = "array" }

local function json_array(t)
    return setmetatable(t or {}, JSON_ARRAY_MT)
end

local function is_json_array(t)
    return type(t) == "table" and getmetatable(t) == JSON_ARRAY_MT
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function starts_with(value, prefix)
    return value:sub(1, #prefix) == prefix
end

local function split_csv(value)
    local result = json_array()
    value = tostring(value or "")
    for item in (value .. ","):gmatch("(.-),") do
        if item ~= "" then
            result[#result + 1] = item
        end
    end
    return result
end

local function is_true(value)
    if value == nil then
        return false
    end

    local normalized = tostring(value):lower()
    return normalized == "1" or normalized == "true" or normalized == "yes" or normalized == "on"
end

local function is_integer_string(value)
    return type(value) == "string" and value:match("^%d+$") ~= nil
end

local function json_escape(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub("\"", "\\\"")
    value = value:gsub("\b", "\\b")
    value = value:gsub("\f", "\\f")
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")
    value = value:gsub("[%z\1-\31]", function(c)
        return string.format("\\u%04x", c:byte())
    end)
    return value
end

local function table_is_array(value)
    if is_json_array(value) then
        return true
    end

    local max = 0
    local count = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        if key > max then
            max = key
        end
        count = count + 1
    end

    return max == count and count > 0
end

local function json_encode(value)
    if jsonc_ok then
        local encoded = jsonc.stringify(value)
        if encoded then
            return encoded
        end
    end

    local value_type = type(value)
    if value == nil then
        return "null"
    elseif value_type == "string" then
        return "\"" .. json_escape(value) .. "\""
    elseif value_type == "number" then
        return tostring(value)
    elseif value_type == "boolean" then
        return value and "true" or "false"
    elseif value_type ~= "table" then
        return "null"
    end

    if table_is_array(value) then
        local parts = {}
        for index = 1, #value do
            parts[#parts + 1] = json_encode(value[index])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local keys = {}
    for key, _ in pairs(value) do
        if type(key) == "string" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = "\"" .. json_escape(key) .. "\":" .. json_encode(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function utf8_char(codepoint)
    if codepoint <= 0x7f then
        return string.char(codepoint)
    elseif codepoint <= 0x7ff then
        return string.char(
            0xc0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0xffff then
        return string.char(
            0xe0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    return string.char(
        0xf0 + math.floor(codepoint / 0x40000),
        0x80 + (math.floor(codepoint / 0x1000) % 0x40),
        0x80 + (math.floor(codepoint / 0x40) % 0x40),
        0x80 + (codepoint % 0x40)
    )
end

local function json_decode(input)
    if jsonc_ok then
        return jsonc.parse(tostring(input or ""))
    end

    local text = tostring(input or "")
    local pos = 1

    local function skip_ws()
        while true do
            local char = text:sub(pos, pos)
            if char == " " or char == "\n" or char == "\r" or char == "\t" then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parse_value

    local function parse_string()
        if text:sub(pos, pos) ~= "\"" then
            error("expected string")
        end
        pos = pos + 1
        local result = {}

        while pos <= #text do
            local char = text:sub(pos, pos)
            if char == "\"" then
                pos = pos + 1
                return table.concat(result)
            elseif char == "\\" then
                local escape = text:sub(pos + 1, pos + 1)
                pos = pos + 2
                if escape == "\"" or escape == "\\" or escape == "/" then
                    result[#result + 1] = escape
                elseif escape == "b" then
                    result[#result + 1] = "\b"
                elseif escape == "f" then
                    result[#result + 1] = "\f"
                elseif escape == "n" then
                    result[#result + 1] = "\n"
                elseif escape == "r" then
                    result[#result + 1] = "\r"
                elseif escape == "t" then
                    result[#result + 1] = "\t"
                elseif escape == "u" then
                    local hex = text:sub(pos, pos + 3)
                    local codepoint = tonumber(hex, 16)
                    if not codepoint then
                        error("invalid unicode escape")
                    end
                    pos = pos + 4
                    if codepoint >= 0xd800 and codepoint <= 0xdbff and text:sub(pos, pos + 1) == "\\u" then
                        local low = tonumber(text:sub(pos + 2, pos + 5), 16)
                        if low and low >= 0xdc00 and low <= 0xdfff then
                            codepoint = 0x10000 + ((codepoint - 0xd800) * 0x400) + (low - 0xdc00)
                            pos = pos + 6
                        end
                    end
                    result[#result + 1] = utf8_char(codepoint)
                else
                    error("invalid string escape")
                end
            else
                result[#result + 1] = char
                pos = pos + 1
            end
        end

        error("unterminated string")
    end

    local function parse_number()
        local start = pos
        local char = text:sub(pos, pos)
        if char == "-" then
            pos = pos + 1
        end
        while text:sub(pos, pos):match("%d") do
            pos = pos + 1
        end
        if text:sub(pos, pos) == "." then
            pos = pos + 1
            while text:sub(pos, pos):match("%d") do
                pos = pos + 1
            end
        end
        char = text:sub(pos, pos)
        if char == "e" or char == "E" then
            pos = pos + 1
            char = text:sub(pos, pos)
            if char == "+" or char == "-" then
                pos = pos + 1
            end
            while text:sub(pos, pos):match("%d") do
                pos = pos + 1
            end
        end

        local number = tonumber(text:sub(start, pos - 1))
        if number == nil then
            error("invalid number")
        end
        return number
    end

    local function parse_array()
        pos = pos + 1
        skip_ws()
        local result = json_array()
        if text:sub(pos, pos) == "]" then
            pos = pos + 1
            return result
        end

        while true do
            result[#result + 1] = parse_value()
            skip_ws()
            local char = text:sub(pos, pos)
            if char == "]" then
                pos = pos + 1
                return result
            elseif char ~= "," then
                error("expected array separator")
            end
            pos = pos + 1
            skip_ws()
        end
    end

    local function parse_object()
        pos = pos + 1
        skip_ws()
        local result = {}
        if text:sub(pos, pos) == "}" then
            pos = pos + 1
            return result
        end

        while true do
            skip_ws()
            local key = parse_string()
            skip_ws()
            if text:sub(pos, pos) ~= ":" then
                error("expected object separator")
            end
            pos = pos + 1
            skip_ws()
            result[key] = parse_value()
            skip_ws()
            local char = text:sub(pos, pos)
            if char == "}" then
                pos = pos + 1
                return result
            elseif char ~= "," then
                error("expected object comma")
            end
            pos = pos + 1
        end
    end

    function parse_value()
        skip_ws()
        local char = text:sub(pos, pos)
        if char == "\"" then
            return parse_string()
        elseif char == "{" then
            return parse_object()
        elseif char == "[" then
            return parse_array()
        elseif char == "-" or char:match("%d") then
            return parse_number()
        elseif text:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif text:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif text:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end

        error("unexpected JSON token")
    end

    local ok, result = pcall(function()
        local value = parse_value()
        skip_ws()
        if pos <= #text then
            error("trailing JSON input")
        end
        return value
    end)

    if ok then
        return result
    end
    return nil, result
end

local base64_map = {}
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for index = 1, #alphabet do
        base64_map[alphabet:sub(index, index)] = index - 1
    end
end

local function base64_decode(value)
    value = tostring(value or ""):gsub("%s+", ""):gsub("-", "+"):gsub("_", "/")
    if value == "" then
        return nil
    end

    local remainder = #value % 4
    if remainder == 1 then
        return nil
    elseif remainder > 1 then
        value = value .. string.rep("=", 4 - remainder)
    end

    if nixio_ok and nixio.bin and nixio.bin.b64decode then
        local decoded = nixio.bin.b64decode(value)
        if decoded then
            return decoded
        end
    end

    local output = {}
    local buffer = 0
    local bits = 0
    for index = 1, #value do
        local char = value:sub(index, index)
        if char == "=" then
            break
        end
        local decoded = base64_map[char]
        if decoded == nil then
            return nil
        end

        buffer = buffer * 64 + decoded
        bits = bits + 6
        while bits >= 8 do
            bits = bits - 8
            local factor = 2 ^ bits
            local byte = math.floor(buffer / factor)
            buffer = buffer % factor
            output[#output + 1] = string.char(byte)
        end
    end

    return table.concat(output)
end

local function urldecode(value)
    value = tostring(value or ""):gsub("+", " ")
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function parse_query(query)
    local params = {}
    query = tostring(query or "")
    if query == "" then
        return params
    end

    for pair in (query .. "&"):gmatch("(.-)&") do
        if pair ~= "" then
            local key, value = pair:match("^([^=]*)=(.*)$")
            if not key then
                key = pair
                value = ""
            end
            key = urldecode(key)
            if key ~= "" then
                params[key] = urldecode(value or "")
            end
        end
    end

    return params
end

local function parse_host_port(value)
    value = tostring(value or "")
    value = value:gsub("/$", "")
    if starts_with(value, "[") then
        local host, port = value:match("^%[([^%]]+)%]:(%d+)$")
        return host, tonumber(port)
    end

    local host, port = value:match("^(.-):(%d+)$")
    return host, tonumber(port)
end

local function parse_url(url)
    local scheme, rest = url:match("^([%w%+%.%-]+)://(.*)$")
    if not scheme then
        return nil
    end

    local fragment = ""
    local hash = rest:find("#", 1, true)
    if hash then
        fragment = urldecode(rest:sub(hash + 1))
        rest = rest:sub(1, hash - 1)
    end

    local query = ""
    local question = rest:find("?", 1, true)
    if question then
        query = rest:sub(question + 1)
        rest = rest:sub(1, question - 1)
    end

    local authority = rest:match("^([^/]*)") or rest
    local userinfo = ""
    local hostport = authority
    local at = authority:match("^.*()@")
    if at then
        userinfo = urldecode(authority:sub(1, at - 1))
        hostport = authority:sub(at + 1)
    end

    local host, port = parse_host_port(hostport)
    return {
        scheme = scheme:lower(),
        userinfo = userinfo,
        host = host or "",
        port = port,
        query = parse_query(query),
        fragment = fragment
    }
end

local function normalize_utls_fingerprint(value)
    local allowed = {
        [""] = true,
        chrome = true,
        firefox = true,
        edge = true,
        safari = true,
        ["360"] = true,
        ios = true,
        android = true,
        randomized = true,
        randomizedalpn = true,
        randomizednoalpn = true
    }

    value = tostring(value or "")
    if allowed[value] then
        return value
    end
    return "chrome"
end

local function add_tls(url, security, default_tls)
    local query = url.query or {}
    local sni = query.sni or query.peer or ""
    local insecure = query.allowInsecure or query.insecure or ""
    local alpn = query.alpn or ""
    local transport = query.type or ""
    if transport == "xhttp" and alpn == "" then
        alpn = "h2,http/1.1"
    end

    local fingerprint = normalize_utls_fingerprint(query.fp or "")
    local public_key = query.pbk or ""
    local short_id = query.sid or ""

    if security == "reality" and public_key == "" then
        return nil, false
    end
    if (security == "reality" or public_key ~= "") and fingerprint == "" then
        fingerprint = "chrome"
    end

    local tls_enabled = false
    if security == "tls" or security == "xtls" or security == "reality" then
        tls_enabled = true
    elseif security == nil or security == "" then
        tls_enabled = default_tls or sni ~= "" or alpn ~= "" or fingerprint ~= "" or public_key ~= ""
    end

    if not tls_enabled then
        return nil, true
    end

    local tls = { enabled = true }
    if sni ~= "" then
        tls.server_name = sni
    end
    if is_true(insecure) then
        tls.insecure = true
    end
    if alpn ~= "" then
        tls.alpn = split_csv(alpn)
    end
    if fingerprint ~= "" then
        tls.utls = { enabled = true, fingerprint = fingerprint }
    end
    if security == "reality" or public_key ~= "" then
        tls.reality = { enabled = true }
        if public_key ~= "" then
            tls.reality.public_key = public_key
        end
        if short_id ~= "" then
            tls.reality.short_id = short_id
        end
    end

    return tls, true
end

local function add_transport(url)
    local query = url.query or {}
    local transport = query.type or ""
    local path = query.path or ""
    local host = query.host or ""
    local early_data = query.ed or ""
    local grpc_service_name = query.serviceName or ""
    local xhttp_mode = query.mode or "auto"
    local sni = query.sni or ""

    if xhttp_mode ~= "auto" and xhttp_mode ~= "packet-up" and xhttp_mode ~= "stream-up" and xhttp_mode ~= "stream-one" then
        xhttp_mode = "auto"
    end

    if transport == "ws" then
        local result = { type = "ws", path = path ~= "" and path or "/" }
        if host ~= "" then
            result.headers = { Host = host }
        end
        if is_integer_string(early_data) then
            result.max_early_data = tonumber(early_data)
        end
        return result
    elseif transport == "grpc" then
        local result = { type = "grpc" }
        if grpc_service_name ~= "" then
            result.service_name = grpc_service_name
        end
        return result
    elseif transport == "http" or transport == "h2" then
        local result = { type = "http" }
        if path ~= "" then
            result.path = path
        end
        if host ~= "" then
            result.host = split_csv(host)
        end
        return result
    elseif transport == "httpupgrade" then
        local result = { type = "httpupgrade" }
        if path ~= "" then
            result.path = path
        end
        if host ~= "" then
            result.host = host
        end
        return result
    elseif transport == "xhttp" then
        if path == "" then
            path = "/"
        end
        if host == "" then
            host = sni
        end

        local result = {
            type = "xhttp",
            mode = xhttp_mode,
            path = path,
            x_padding_bytes = "100-1000",
            no_grpc_header = false,
            sc_max_each_post_bytes = 1000000,
            sc_min_posts_interval_ms = 30
        }
        if host ~= "" then
            result.host = host
        end
        return result
    end

    return nil
end

local function valid_port(port)
    return type(port) == "number" and port >= 1 and port <= 65535 and math.floor(port) == port
end

local function process_vless(raw, url)
    if url.host == "" or not valid_port(url.port) or url.userinfo == "" then
        return nil
    end

    local flow = url.query.flow or ""
    if flow ~= "" and flow ~= "xtls-rprx-vision" then
        return nil
    end

    local packet_encoding = url.query.packetEncoding or ""
    if packet_encoding ~= "xudp" and packet_encoding ~= "packetaddr" then
        packet_encoding = ""
    end

    local outbound = {
        type = "vless",
        tag = url.fragment ~= "" and url.fragment or (url.host .. ":" .. tostring(url.port)),
        share_link = raw,
        server = url.host,
        server_port = url.port,
        uuid = url.userinfo
    }
    if flow ~= "" then
        outbound.flow = flow
    end
    if packet_encoding ~= "" then
        outbound.packet_encoding = packet_encoding
    end

    local tls, ok = add_tls(url, url.query.security or "", false)
    if not ok then
        return nil
    end
    if tls then
        outbound.tls = tls
    end

    local transport = add_transport(url)
    if transport then
        outbound.transport = transport
    end
    return outbound
end

local function process_trojan(raw, url)
    if url.host == "" or not valid_port(url.port) or url.userinfo == "" then
        return nil
    end

    local outbound = {
        type = "trojan",
        tag = url.fragment ~= "" and url.fragment or (url.host .. ":" .. tostring(url.port)),
        share_link = raw,
        server = url.host,
        server_port = url.port,
        password = url.userinfo
    }

    local tls, ok = add_tls(url, url.query.security or "", true)
    if not ok then
        return nil
    end
    if tls then
        outbound.tls = tls
    end

    local transport = add_transport(url)
    if transport then
        outbound.transport = transport
    end
    return outbound
end

local function process_socks(raw, url)
    if url.host == "" or not valid_port(url.port) then
        return nil
    end

    local username = ""
    local password = ""
    if url.userinfo ~= "" then
        local colon = url.userinfo:find(":", 1, true)
        if colon then
            username = urldecode(url.userinfo:sub(1, colon - 1))
            password = urldecode(url.userinfo:sub(colon + 1))
            if username == password then
                password = ""
            end
        else
            username = urldecode(url.userinfo)
        end
    end

    local outbound = {
        type = "socks",
        tag = url.fragment ~= "" and url.fragment or (url.host .. ":" .. tostring(url.port)),
        share_link = raw,
        server = url.host,
        server_port = url.port
    }
    local version = url.scheme:sub(6)
    if version ~= "" then
        outbound.version = version
    end
    if username ~= "" then
        outbound.username = username
    end
    if password ~= "" then
        outbound.password = password
    end
    return outbound
end

local function is_shadowsocks_userinfo_format(value)
    return type(value) == "string" and value:match("^[^:]+:[^:]+:?[^:]*$") ~= nil
end

local function process_shadowsocks(raw)
    local body = raw:match("^ss://(.*)$")
    if not body then
        return nil
    end

    local fragment = ""
    local hash = body:find("#", 1, true)
    if hash then
        fragment = urldecode(body:sub(hash + 1))
        body = body:sub(1, hash - 1)
    end

    local query = ""
    local question = body:find("?", 1, true)
    if question then
        query = body:sub(question + 1)
        body = body:sub(1, question - 1)
    end

    local userinfo
    local hostport
    local at = body:match("^.*()@")
    if at then
        userinfo = body:sub(1, at - 1)
        hostport = body:sub(at + 1)
    else
        local decoded = base64_decode(body)
        if not decoded then
            return nil
        end
        at = decoded:match("^.*()@")
        if not at then
            return nil
        end
        userinfo = decoded:sub(1, at - 1)
        hostport = decoded:sub(at + 1)
    end

    userinfo = urldecode(userinfo)
    if not is_shadowsocks_userinfo_format(userinfo) then
        local decoded = base64_decode(userinfo)
        if not decoded then
            return nil
        end
        userinfo = decoded
    end

    local method, password = userinfo:match("^([^:]+):(.*)$")
    local host, port = parse_host_port(hostport)
    if not method or method == "" or method == "ss" or not password or password == "" or host == "" or not valid_port(port) then
        return nil
    end

    local params = parse_query(query)
    local plugin = params.plugin or ""
    local plugin_opts = params["plugin-opts"] or ""
    if plugin ~= "" and plugin_opts == "" then
        local parsed_plugin, parsed_opts = plugin:match("^([^;]+);(.*)$")
        if parsed_plugin then
            plugin = parsed_plugin
            plugin_opts = parsed_opts
        end
    end

    local outbound = {
        type = "shadowsocks",
        tag = fragment ~= "" and fragment or (host .. ":" .. tostring(port)),
        share_link = raw,
        server = host,
        server_port = port,
        method = method,
        password = password
    }
    if plugin ~= "" then
        outbound.plugin = plugin
    end
    if plugin_opts ~= "" then
        outbound.plugin_opts = plugin_opts
    end
    return outbound
end

local function process_hysteria2(raw, url)
    if url.host == "" or not valid_port(url.port) or url.userinfo == "" then
        return nil
    end

    local password = url.userinfo
    local colon = password:find(":", 1, true)
    if colon then
        password = password:sub(colon + 1)
    end
    if password == "" then
        return nil
    end

    local tls = { enabled = true }
    if (url.query.sni or "") ~= "" then
        tls.server_name = url.query.sni
    end
    if is_true(url.query.insecure) then
        tls.insecure = true
    end
    if (url.query.alpn or "") ~= "" then
        tls.alpn = split_csv(url.query.alpn)
    end

    local outbound = {
        type = "hysteria2",
        tag = url.fragment ~= "" and url.fragment or (url.host .. ":" .. tostring(url.port)),
        share_link = raw,
        server = url.host,
        server_port = url.port,
        password = password,
        tls = tls
    }
    if (url.query.network or "") ~= "" then
        outbound.network = url.query.network
    end
    if is_integer_string(url.query.upmbps or "") then
        outbound.up_mbps = tonumber(url.query.upmbps)
    end
    if is_integer_string(url.query.downmbps or "") then
        outbound.down_mbps = tonumber(url.query.downmbps)
    end
    if (url.query.obfs or "") ~= "" and url.query.obfs ~= "none" then
        outbound.obfs = { type = url.query.obfs }
        if (url.query["obfs-password"] or "") ~= "" then
            outbound.obfs.password = url.query["obfs-password"]
        end
    end
    return outbound
end

local function string_value(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function process_vmess_json(raw, decoded)
    local vmess = json_decode(decoded)
    if type(vmess) ~= "table" then
        return nil
    end

    local server = string_value(vmess.add)
    local port = tonumber(vmess.port)
    local uuid = string_value(vmess.id)
    if server == "" or not valid_port(port) or uuid == "" then
        return nil
    end

    local outbound = {
        type = "vmess",
        tag = string_value(vmess.ps) ~= "" and string_value(vmess.ps) or (server .. ":" .. tostring(port)),
        share_link = raw,
        server = server,
        server_port = port,
        uuid = uuid,
        security = string_value(vmess.scy) ~= "" and string_value(vmess.scy) or "auto"
    }

    local alter_id = tonumber(vmess.aid)
    if alter_id then
        outbound.alter_id = alter_id
    end

    if vmess.tls == true or vmess.tls == "tls" or vmess.tls == "true" then
        local fingerprint = normalize_utls_fingerprint(string_value(vmess.fp))
        local tls = { enabled = true }
        if string_value(vmess.sni) ~= "" then
            tls.server_name = string_value(vmess.sni)
        end
        if string_value(vmess.alpn) ~= "" then
            tls.alpn = split_csv(string_value(vmess.alpn))
        end
        if fingerprint ~= "" then
            tls.utls = { enabled = true, fingerprint = fingerprint }
        end
        outbound.tls = tls
    end

    local network = string_value(vmess.net)
    if network == "ws" then
        outbound.transport = {
            type = "ws",
            path = string_value(vmess.path) ~= "" and string_value(vmess.path) or "/"
        }
        if string_value(vmess.host) ~= "" then
            outbound.transport.headers = { Host = string_value(vmess.host) }
        end
    elseif network == "grpc" then
        outbound.transport = { type = "grpc" }
        if string_value(vmess.path) ~= "" then
            outbound.transport.service_name = string_value(vmess.path)
        end
    elseif network == "http" or network == "h2" then
        outbound.transport = { type = "http" }
        if string_value(vmess.path) ~= "" then
            outbound.transport.path = string_value(vmess.path)
        end
        if string_value(vmess.host) ~= "" then
            outbound.transport.host = split_csv(string_value(vmess.host))
        end
    end

    return outbound
end

local function process_vmess(raw)
    local encoded = raw:match("^vmess://(.*)$")
    if not encoded then
        return nil
    end

    encoded = encoded:gsub("#.*$", "")
    local decoded = base64_decode(encoded)
    if not decoded then
        return nil
    end
    decoded = decoded:gsub("[\r\n]", "")
    if not decoded:match("^%s*{.*}%s*$") then
        return nil
    end
    return process_vmess_json(raw, decoded)
end

local function parse_share_link(line)
    if starts_with(line, "vmess://") then
        return process_vmess(line)
    elseif starts_with(line, "ss://") then
        return process_shadowsocks(line)
    end

    local url = parse_url(line)
    if not url then
        return nil
    end

    if url.scheme == "vless" then
        return process_vless(line, url)
    elseif url.scheme == "trojan" then
        return process_trojan(line, url)
    elseif url.scheme == "hysteria2" or url.scheme == "hy2" then
        return process_hysteria2(line, url)
    elseif url.scheme:match("^socks") then
        return process_socks(line, url)
    end

    return nil
end

local function normalize_uri_list(input_file, output_file)
    local input = assert(io.open(input_file, "r"))
    local output = assert(io.open(output_file, "w"))
    local added = 0
    local skipped = 0

    output:write("{\"version\":1,\"format\":\"uri-list\",\"outbounds\":[")

    for line in input:lines() do
        line = trim(line:gsub("\r", ""))
        if line ~= "" and not starts_with(line, "#") then
            local outbound = parse_share_link(line)
            if outbound then
                if added > 0 then
                    output:write(",")
                end
                output:write(json_encode(outbound))
                added = added + 1
            else
                skipped = skipped + 1
            end
        end
    end
    input:close()
    output:write("],\"skipped\":", tostring(skipped), "}\n")
    output:close()

    if added == 0 then
        os.remove(output_file)
        return false
    end
    return true
end

local function read_file(path)
    local file = assert(io.open(path, "r"))
    local data = file:read("*a")
    file:close()
    return data
end

local function non_empty_string(value)
    return type(value) == "string" and value ~= ""
end

local function valid_server_port(value)
    return type(value) == "number" and value >= 1 and value <= 65535 and math.floor(value) == value
end

local function type_requires_server(proxy_type)
    return proxy_type == "vless" or proxy_type == "vmess" or proxy_type == "trojan" or
        proxy_type == "shadowsocks" or proxy_type == "socks" or proxy_type == "hysteria2"
end

local function supported_flow(flow)
    return flow == nil or flow == "" or flow == "xtls-rprx-vision"
end

local function supported_transport_type(transport)
    return transport == "http" or transport == "ws" or transport == "quic" or transport == "grpc" or
        transport == "httpupgrade" or transport == "xhttp" or transport == "kcp"
end

local supported_shadowsocks_methods = {
    ["none"] = true,
    ["aes-128-gcm"] = true,
    ["aes-192-gcm"] = true,
    ["aes-256-gcm"] = true,
    ["chacha20-ietf-poly1305"] = true,
    ["xchacha20-ietf-poly1305"] = true,
    ["2022-blake3-aes-128-gcm"] = true,
    ["2022-blake3-aes-256-gcm"] = true,
    ["2022-blake3-chacha20-poly1305"] = true,
    ["aes-128-cfb"] = true,
    ["aes-192-cfb"] = true,
    ["aes-256-cfb"] = true,
    ["aes-128-ctr"] = true,
    ["aes-192-ctr"] = true,
    ["aes-256-ctr"] = true,
    ["chacha20"] = true,
    ["chacha20-ietf"] = true,
    ["xchacha20"] = true,
    ["salsa20"] = true,
    ["rc4-md5"] = true
}

local function plugin_name(plugin)
    return tostring(plugin or ""):match("^([^;]*)")
end

local function reality_enabled(outbound)
    return type(outbound.tls) == "table" and type(outbound.tls.reality) == "table" and
        (outbound.tls.reality.enabled == nil or outbound.tls.reality.enabled == true)
end

local function prefilter_skip_reason(outbound, supports_xhttp, plugin_supports)
    if type(outbound) ~= "table" then
        return "outbound must be an object"
    end

    local proxy_type = outbound.type
    if proxy_type == nil or tostring(proxy_type) == "" then
        return "missing outbound type"
    elseif type(proxy_type) ~= "string" then
        return "outbound type must be a string"
    elseif type_requires_server(proxy_type) and not non_empty_string(outbound.server) then
        return "missing or empty server"
    elseif type_requires_server(proxy_type) and not valid_server_port(outbound.server_port) then
        return "missing or invalid server_port"
    elseif (proxy_type == "vless" or proxy_type == "vmess") and not non_empty_string(outbound.uuid) then
        return "missing uuid"
    elseif (proxy_type == "trojan" or proxy_type == "hysteria2") and not non_empty_string(outbound.password) then
        return "missing password"
    elseif proxy_type == "shadowsocks" and not non_empty_string(outbound.method) then
        return "missing shadowsocks method"
    elseif proxy_type == "shadowsocks" and not non_empty_string(outbound.password) then
        return "missing shadowsocks password"
    elseif proxy_type == "shadowsocks" and not supported_shadowsocks_methods[outbound.method] then
        return "unsupported shadowsocks method: " .. tostring(outbound.method)
    elseif proxy_type == "shadowsocks" and non_empty_string(outbound.plugin) and not plugin_supports[plugin_name(outbound.plugin)] then
        return "shadowsocks plugin is not installed: " .. plugin_name(outbound.plugin)
    elseif reality_enabled(outbound) and not non_empty_string(outbound.tls.reality.public_key) then
        return "reality public_key is missing"
    elseif proxy_type == "vless" and not supported_flow(outbound.flow or "") then
        return "unsupported vless flow: " .. tostring(outbound.flow)
    elseif type(outbound.transport) == "table" and tostring(outbound.transport.type or "") == "" then
        return "missing transport type"
    elseif type(outbound.transport) == "table" and not supported_transport_type(tostring(outbound.transport.type or "")) then
        return "unknown transport type: " .. tostring(outbound.transport.type)
    elseif type(outbound.transport) == "table" and tostring(outbound.transport.type or "") == "xhttp" and not supports_xhttp then
        return "transport xhttp requires sing-box-extended"
    elseif proxy_type == "shadowsocks" and type(outbound.tls) == "table" and outbound.tls.enabled == true then
        return "shadowsocks with TLS is not supported"
    end

    return ""
end

local function safe_string(value, fallback)
    local result = value == nil and fallback or tostring(value)
    if result == "" or result == "null" then
        return fallback
    end
    return result
end

local function unique_tag(base, taken)
    if not taken[base] then
        return base
    end

    for suffix = 1, 99999 do
        local candidate = base .. "-" .. tostring(suffix)
        if not taken[candidate] then
            return candidate
        end
    end
    return base .. "-overflow"
end

local function copy_outbound(outbound)
    local copy = {}
    for key, value in pairs(outbound) do
        if key ~= "tag" and key ~= "remark" and key ~= "share_link" then
            copy[key] = value
        end
    end
    return copy
end

local function prepare_subscription(config_file, outbounds_file, output_file, supports_xhttp_arg, plugin_supports_file)
    local config = json_decode(read_file(config_file))
    local outbounds = json_decode(read_file(outbounds_file))
    local plugin_supports = {}
    if plugin_supports_file and plugin_supports_file ~= "" then
        plugin_supports = json_decode(read_file(plugin_supports_file)) or {}
    end

    if type(config) ~= "table" or type(outbounds) ~= "table" then
        return false
    end

    local supports_xhttp = supports_xhttp_arg == "true" or supports_xhttp_arg == "1"
    local taken = {}
    if type(config.outbounds) == "table" then
        for _, outbound in ipairs(config.outbounds) do
            if type(outbound) == "table" and non_empty_string(outbound.tag) then
                taken[outbound.tag] = true
            end
        end
    end

    local tags = json_array()
    local names = json_array()
    local servers = json_array()
    local links = json_array()
    local skipped = 0
    local skipped_reason_counts = {}
    local output = assert(io.open(output_file, "w"))
    local added = 0

    output:write("{\"outbounds\":[")

    for _, outbound in ipairs(outbounds) do
        local index = added + 1
        local display_name = safe_string(outbound and (outbound.remark or outbound.tag), "server-" .. tostring(index))
        local skip_reason = prefilter_skip_reason(outbound, supports_xhttp, plugin_supports)
        if skip_reason ~= "" then
            skipped = skipped + 1
            skipped_reason_counts[skip_reason] = (skipped_reason_counts[skip_reason] or 0) + 1
        else
            local base_tag = safe_string(outbound.tag or outbound.remark, "server-" .. tostring(index))
            local tag = unique_tag(base_tag, taken)
            local outbound_copy = copy_outbound(outbound)
            outbound_copy.tag = tag
            if added > 0 then
                output:write(",")
            end
            output:write(json_encode(outbound_copy))
            added = added + 1
            tags[#tags + 1] = tag
            names[#names + 1] = display_name
            servers[#servers + 1] = outbound.server or ""
            links[#links + 1] = outbound.share_link or ""
            taken[tag] = true
        end
    end

    output:write("],\"links\":", json_encode(links))
    output:write(",\"names\":", json_encode(names))
    output:write(",\"servers\":", json_encode(servers))
    output:write(",\"skipped\":", tostring(skipped))
    output:write(",\"skipped_reason_counts\":", json_encode(skipped_reason_counts))
    output:write(",\"tags\":", json_encode(tags))
    output:write("}\n")
    output:close()
    return true
end

local mode = arg[1]
local ok = false

if mode == "normalize-uri-list" then
    ok = normalize_uri_list(arg[2], arg[3])
elseif mode == "prepare" then
    ok = prepare_subscription(arg[2], arg[3], arg[4], arg[5], arg[6])
elseif arg[1] and arg[2] then
    ok = normalize_uri_list(arg[1], arg[2])
else
    io.stderr:write("Usage: subscription_parser.lua normalize-uri-list <input> <output>\n")
    io.stderr:write("       subscription_parser.lua prepare <config> <outbounds> <output> <supports_xhttp> <plugin_supports>\n")
    os.exit(2)
end

if not ok then
    os.exit(1)
end
