# shellcheck shell=ash

subscription_content_has_share_links() {
    grep -Eq '^[[:space:]]*(ss|vmess|vless|trojan|hysteria2|hy2|socks|socks4|socks4a|socks5)://' "$1"
}

subscription_content_is_clash_yaml() {
    grep -Eq '^[[:space:]]*proxies:[[:space:]]*($|#)' "$1"
}

subscription_url_decode() {
    case "$1" in
    *%* | *+*) url_decode "$1" ;;
    *) printf '%s\n' "$1" ;;
    esac
}

subscription_url_get_fragment() {
    local url="$1"

    case "$url" in
    *'#'*) subscription_url_decode "${url#*#}" ;;
    *) printf '\n' ;;
    esac
}

subscription_bool_is_true() {
    case "$1" in
    1 | true | TRUE | True | yes | YES | on | ON)
        return 0
        ;;
    esac

    return 1
}

subscription_bool_json() {
    if subscription_bool_is_true "$1"; then
        printf 'true'
    else
        printf 'false'
    fi
}

subscription_normalize_utls_fingerprint() {
    case "$1" in
    "" | chrome | firefox | edge | safari | 360 | ios | android | randomized | randomizedalpn | randomizednoalpn)
        printf '%s' "$1"
        ;;
    *)
        printf 'chrome'
        ;;
    esac
}

subscription_base64_decode_string() {
    local raw="$1"
    local normalized remainder padding

    normalized="$(printf '%s' "$raw" | tr -d '\r\n\t ' | tr '_-' '/+')"
    remainder=$(( ${#normalized} % 4 ))
    padding=""
    case "$remainder" in
    2) padding="==" ;;
    3) padding="=" ;;
    1) return 1 ;;
    esac

    printf '%s' "${normalized}${padding}" | base64 -d 2>/dev/null
}

subscription_try_base64_decode_file() {
    local input="$1"
    local output="$2"
    local compact decoded_tmp

    compact="$(tr -d '\r\n\t ' < "$input")"
    [ -n "$compact" ] || return 1

    decoded_tmp="$(mktemp)" || return 1
    if subscription_base64_decode_string "$compact" > "$decoded_tmp" && [ -s "$decoded_tmp" ]; then
        mv "$decoded_tmp" "$output"
        return 0
    fi

    rm -f "$decoded_tmp"
    return 1
}

subscription_metadata_headers_json() {
    local input="$1"

    [ -s "$input" ] || {
        printf '{}\n'
        return 0
    }

    awk '
    function trim(s) {
        gsub(/^[ \t\r\n]+/, "", s)
        gsub(/[ \t\r\n]+$/, "", s)
        return s
    }
    function allowed(k) {
        return k == "profile-title" ||
            k == "subscription-userinfo" ||
            k == "profile-web-page-url" ||
            k == "support-url" ||
            k == "announce" ||
            k == "announce-url" ||
            k == "subscription-refill-date" ||
            k == "content-disposition"
    }
    function json_escape(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        gsub(/\t/, "\\t", s)
        gsub(/\r/, "", s)
        return s
    }
    {
        line = trim($0)
        colon = index(line, ":")
        if (colon <= 1) {
            next
        }

        key = tolower(trim(substr(line, 1, colon - 1)))
        value = trim(substr(line, colon + 1))
        if (!allowed(key) || value == "") {
            next
        }

        if (!(key in seen)) {
            order[++count] = key
        }
        seen[key] = 1
        values[key] = value
    }
    END {
        printf "{"
        sep = ""
        for (i = 1; i <= count; i++) {
            key = order[i]
            if (key in values) {
                printf "%s\"%s\":\"%s\"", sep, key, json_escape(values[key])
                sep = ","
            }
        }
        printf "}\n"
    }
    ' "$input"
}

subscription_metadata_body_json_from_file() {
    local input="$1"

    [ -s "$input" ] || {
        printf '{}\n'
        return 0
    }

    awk '
    function trim(s) {
        gsub(/^[ \t\r\n]+/, "", s)
        gsub(/[ \t\r\n]+$/, "", s)
        return s
    }
    function allowed(k) {
        return k == "profile-title" ||
            k == "subscription-userinfo" ||
            k == "profile-web-page-url" ||
            k == "support-url" ||
            k == "announce" ||
            k == "announce-url" ||
            k == "subscription-refill-date" ||
            k == "content-disposition"
    }
    function json_escape(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        gsub(/\t/, "\\t", s)
        gsub(/\r/, "", s)
        return s
    }
    NR > 20 {
        exit
    }
    {
        line = trim($0)
        if (line ~ /^#/) {
            sub(/^#[ \t]*/, "", line)
        } else if (line ~ /^\/\//) {
            sub(/^\/\/[ \t]*/, "", line)
        } else {
            next
        }

        colon = index(line, ":")
        if (colon <= 1) {
            next
        }

        key = tolower(trim(substr(line, 1, colon - 1)))
        value = trim(substr(line, colon + 1))
        if (!allowed(key) || value == "") {
            next
        }

        if (!(key in seen)) {
            order[++count] = key
        }
        seen[key] = 1
        values[key] = value
    }
    END {
        printf "{"
        sep = ""
        for (i = 1; i <= count; i++) {
            key = order[i]
            if (key in values) {
                printf "%s\"%s\":\"%s\"", sep, key, json_escape(values[key])
                sep = ","
            }
        }
        printf "}\n"
    }
    ' "$input"
}

subscription_metadata_body_json() {
    local input="$1"
    local raw_json decoded_tmp decoded_json

    raw_json="$(subscription_metadata_body_json_from_file "$input")"
    if [ "$raw_json" != "{}" ]; then
        printf '%s\n' "$raw_json"
        return 0
    fi

    decoded_tmp="$(mktemp)" || {
        printf '{}\n'
        return 0
    }

    if subscription_try_base64_decode_file "$input" "$decoded_tmp"; then
        decoded_json="$(subscription_metadata_body_json_from_file "$decoded_tmp")"
        rm -f "$decoded_tmp"
        printf '%s\n' "$decoded_json"
        return 0
    fi

    rm -f "$decoded_tmp"
    printf '{}\n'
}

subscription_metadata_trim() {
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

subscription_metadata_lower() {
    awk '{ print tolower($0) }'
}

subscription_metadata_clean_text() {
    local value="$1"
    local max="$2"
    local mode="${3:-plain}"
    local prefix cleaned

    if [ "$mode" = "base64" ]; then
        prefix="$(printf '%s' "$value" | cut -c 1-7 | subscription_metadata_lower)"
        if [ "$prefix" = "base64:" ]; then
            value="$(subscription_base64_decode_string "$(printf '%s' "$value" | cut -c 8-)" 2>/dev/null || printf '')"
        fi
    fi

    cleaned="$(
        printf '%s' "$value" |
            tr '\000-\037\177' ' ' |
            sed 's/[[:space:]][[:space:]]*/ /g;s/^[[:space:]]*//;s/[[:space:]]*$//'
    )"

    [ -n "$cleaned" ] || return 1
    if [ "${#cleaned}" -gt "$max" ]; then
        cleaned="$(printf '%s' "$cleaned" | cut -c "1-$max")"
    fi

    printf '%s\n' "$cleaned"
}

subscription_metadata_clean_url() {
    local value cleaned

    value="$1"
    cleaned="$(printf '%s' "$value" | subscription_metadata_trim)"
    [ -n "$cleaned" ] || return 1
    [ "${#cleaned}" -le 2048 ] || return 1

    case "$cleaned" in
    http://* | https://*) ;;
    *) return 1 ;;
    esac

    if printf '%s' "$cleaned" | grep -q '[[:cntrl:][:space:]]'; then
        return 1
    fi

    printf '%s\n' "$cleaned"
}

subscription_metadata_clean_number() {
    local value

    value="$(printf '%s' "$1" | subscription_metadata_trim)"
    case "$value" in
    "" | *[!0-9]*) return 1 ;;
    esac

    printf '%s\n' "$value"
}

subscription_metadata_content_disposition_filename() {
    local value filename

    value="$1"
    case "$value" in
    *filename=\"*)
        filename="${value#*filename=\"}"
        filename="${filename%%\"*}"
        ;;
    *filename=*)
        filename="${value#*filename=}"
        filename="${filename%%;*}"
        filename="${filename#\"}"
        filename="${filename%\"}"
        ;;
    *)
        return 1
        ;;
    esac

    filename="$(subscription_metadata_clean_text "$filename" 120 plain)" || return 1
    filename="$(printf '%s' "$filename" | tr '/\\' '__')"
    [ -n "$filename" ] || return 1
    printf '%s\n' "$filename"
}

subscription_metadata_raw_value() {
    local raw_json="$1"
    local key="$2"

    printf '%s\n' "$raw_json" | jq -r --arg key "$key" '.[$key] // empty' 2>/dev/null
}

subscription_normalize_ui_metadata_json() {
    local raw_json="$1"
    local title web_page_url support_url announce announce_url refill_date file_name
    local userinfo item key value upload download total expire has_traffic used remaining is_unlimited
    local upload_json download_json total_json expire_json refill_date_json remaining_json

    title="$(subscription_metadata_clean_text "$(subscription_metadata_raw_value "$raw_json" "profile-title")" 120 base64 2>/dev/null || true)"
    web_page_url="$(subscription_metadata_clean_url "$(subscription_metadata_raw_value "$raw_json" "profile-web-page-url")" 2>/dev/null || true)"
    support_url="$(subscription_metadata_clean_url "$(subscription_metadata_raw_value "$raw_json" "support-url")" 2>/dev/null || true)"
    announce="$(subscription_metadata_clean_text "$(subscription_metadata_raw_value "$raw_json" "announce")" 500 base64 2>/dev/null || true)"
    announce_url="$(subscription_metadata_clean_url "$(subscription_metadata_raw_value "$raw_json" "announce-url")" 2>/dev/null || true)"
    refill_date="$(subscription_metadata_clean_number "$(subscription_metadata_raw_value "$raw_json" "subscription-refill-date")" 2>/dev/null || true)"
    file_name="$(subscription_metadata_content_disposition_filename "$(subscription_metadata_raw_value "$raw_json" "content-disposition")" 2>/dev/null || true)"

    userinfo="$(subscription_metadata_raw_value "$raw_json" "subscription-userinfo")"
    upload=""
    download=""
    total=""
    expire=""

    while IFS= read -r item || [ -n "$item" ]; do
        item="$(printf '%s' "$item" | subscription_metadata_trim)"
        case "$item" in
        *=*) ;;
        *) continue ;;
        esac

        key="$(printf '%s' "${item%%=*}" | subscription_metadata_trim | subscription_metadata_lower)"
        value="$(subscription_metadata_clean_number "${item#*=}" 2>/dev/null || true)"
        [ -n "$value" ] || continue

        case "$key" in
        upload) upload="$value" ;;
        download) download="$value" ;;
        total) total="$value" ;;
        expire) expire="$value" ;;
        esac
    done <<EOF
$(printf '%s' "$userinfo" | tr ';' '\n')
EOF

    has_traffic=false
    [ -n "$upload$download$total$expire" ] && has_traffic=true

    upload_json="${upload:-null}"
    download_json="${download:-null}"
    total_json="${total:-null}"
    expire_json="${expire:-null}"
    refill_date_json="${refill_date:-null}"

    used=$(( ${upload:-0} + ${download:-0} ))
    remaining_json="null"
    is_unlimited=true
    if [ -n "$total" ] && [ "$total" -gt 0 ]; then
        is_unlimited=false
        remaining=$((total - used))
        [ "$remaining" -lt 0 ] && remaining=0
        remaining_json="$remaining"
    fi

    jq -cn \
        --arg title "$title" \
        --arg webPageUrl "$web_page_url" \
        --arg supportUrl "$support_url" \
        --arg announce "$announce" \
        --arg announceUrl "$announce_url" \
        --arg fileName "$file_name" \
        --argjson hasTraffic "$has_traffic" \
        --argjson upload "$upload_json" \
        --argjson download "$download_json" \
        --argjson used "$used" \
        --argjson total "$total_json" \
        --argjson remaining "$remaining_json" \
        --argjson isUnlimited "$is_unlimited" \
        --argjson expire "$expire_json" \
        --argjson refillDate "$refill_date_json" '
        {
            version: 1
        }
        + (if $title != "" then {title: $title} else {} end)
        + (if $hasTraffic then
            {
                traffic: (
                    {}
                    + (if $upload != null then {upload: $upload} else {} end)
                    + (if $download != null then {download: $download} else {} end)
                    + {used: $used, isUnlimited: $isUnlimited}
                    + (if $total != null and $total > 0 then {total: $total, remaining: $remaining} else {} end)
                )
            }
          else {} end)
        + (if $expire != null and $expire > 0 then {expire: $expire} else {} end)
        + (if $refillDate != null and $refillDate > 0 then {refillDate: $refillDate} else {} end)
        + (if $webPageUrl != "" then {webPageUrl: $webPageUrl} else {} end)
        + (if $supportUrl != "" then {supportUrl: $supportUrl} else {} end)
        + (if $announce != "" then {announce: $announce} else {} end)
        + (if $announceUrl != "" then {announceUrl: $announceUrl} else {} end)
        + (if $fileName != "" then {fileName: $fileName} else {} end)
        | if (keys | length) > 1 then . else empty end
    '
}

subscription_extract_ui_metadata() {
    local headers_file="$1"
    local body_file="$2"
    local output="$3"
    local headers_json body_json raw_json metadata_json

    headers_json="$(subscription_metadata_headers_json "$headers_file")" || headers_json="{}"
    body_json="$(subscription_metadata_body_json "$body_file")" || body_json="{}"

    raw_json="$(jq -cn --argjson body "$body_json" --argjson headers "$headers_json" '$body + $headers')" || {
        rm -f "$output"
        return 1
    }

    metadata_json="$(subscription_normalize_ui_metadata_json "$raw_json")" || metadata_json=""
    if [ -n "$metadata_json" ] && printf '%s\n' "$metadata_json" | jq -e 'type == "object" and (keys | length > 1)' >/dev/null 2>&1; then
        printf '%s\n' "$metadata_json" > "$output"
        return 0
    fi

    rm -f "$output"
    return 1
}

subscription_strip_metadata_preamble_file() {
    local input="$1"
    local tmpfile

    [ -s "$input" ] || return 0

    tmpfile="$(mktemp)" || return 0
    awk '
    function allowed(k) {
        return k == "profile-title" ||
            k == "subscription-userinfo" ||
            k == "profile-web-page-url" ||
            k == "support-url" ||
            k == "announce" ||
            k == "announce-url" ||
            k == "subscription-refill-date" ||
            k == "content-disposition"
    }
    NR <= 20 {
        line = $0
        sub(/\r$/, "", line)
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line ~ /^(#|\/\/)[ \t]*[A-Za-z0-9][A-Za-z0-9_-]*[ \t]*:/) {
            key = line
            sub(/^(#|\/\/)[ \t]*/, "", key)
            sub(/[ \t]*:.*/, "", key)
            key = tolower(key)
            if (!allowed(key)) {
                print
                next
            }
            next
        }
    }
    {
        print
    }
    ' "$input" > "$tmpfile" && mv "$tmpfile" "$input" || rm -f "$tmpfile"
}

subscription_validate_normalized_file() {
    local output="$1"

    jq -e '
        type == "object" and
        (.outbounds | type == "array") and
        ((.outbounds | length) > 0)
    ' "$output" >/dev/null 2>&1
}

subscription_normalize_sing_box_json_file() {
    local input="$1"
    local output="$2"

    jq -ce '
        def candidate_outbounds:
            if type == "object" and (.outbounds | type == "array") then
                .outbounds
            elif type == "array" then
                .
            elif type == "object" and (.type? | type == "string") then
                [.]
            else
                []
            end;

        {
            version: 1,
            format: "sing-box-json",
            outbounds: (candidate_outbounds | map(select(type == "object")))
        }
    ' "$input" > "$output" 2>/dev/null
}

subscription_normalize_uri_list_file() {
    local input="$1"
    local output="$2"

    subscription_normalize_uri_list_file_lua "$input" "$output"
}

subscription_normalize_uri_list_file_lua() {
    local input="$1"
    local output="$2"
    local parser_path="${PODKOP_LIB:-/usr/lib/podkop-plus}/subscription_parser.lua"
    local tmp_output skipped

    command -v lua >/dev/null 2>&1 || {
        log "Lua interpreter is required to parse URI subscription links" "error"
        return 1
    }
    [ -r "$parser_path" ] || {
        log "Lua subscription parser not found: $parser_path" "error"
        return 1
    }

    tmp_output="$(mktemp)" || return 1
    if lua "$parser_path" normalize-uri-list "$input" "$tmp_output"; then
        skipped="$(jq -r '.skipped // 0' "$tmp_output" 2>/dev/null)"
        case "$skipped" in
        '' | *[!0-9]*) skipped=0 ;;
        esac
        if [ "$skipped" -gt 0 ]; then
            log "Skipped $skipped invalid or unsupported subscription links" "warn"
        fi
        mv "$tmp_output" "$output"
        return 0
    fi

    rm -f "$tmp_output"
    log "Lua subscription parser failed" "error"
    return 1
}

subscription_clash_yaml_records() {
    local input="$1"

    awk '
    function trim(s) {
        gsub(/^[ \t\r\n]+/, "", s)
        gsub(/[ \t\r\n]+$/, "", s)
        return s
    }
    function json_escape(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        gsub(/\t/, "\\t", s)
        gsub(/\r/, "", s)
        return s
    }
    function clean_scalar(s) {
        s = trim(s)
        if ((substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") ||
            (substr(s, 1, 1) == "'"'"'" && substr(s, length(s), 1) == "'"'"'")) {
            s = substr(s, 2, length(s) - 2)
        }
        return s
    }
    function clear_fields(    k) {
        for (k in fields) {
            delete fields[k]
        }
        field_count = 0
        ctx = ""
        ctx_indent = -1
    }
    function set_field(k, v) {
        k = clean_scalar(k)
        v = clean_scalar(v)
        if (k == "") {
            return
        }
        if (!(k in fields)) {
            keys[++field_count] = k
        }
        fields[k] = v
    }
    function emit_record(    i,k,sep) {
        if (field_count <= 0) {
            return
        }
        printf "{"
        sep = ""
        for (i = 1; i <= field_count; i++) {
            k = keys[i]
            if (k in fields) {
                printf "%s\"%s\":\"%s\"", sep, json_escape(k), json_escape(fields[k])
                sep = ","
            }
        }
        printf "}\n"
        clear_fields()
    }
    function parse_pair(part, prefix,    i,c,depth,quote,esc,colon,key,value) {
        part = trim(part)
        depth = 0
        quote = ""
        esc = 0
        colon = 0
        for (i = 1; i <= length(part); i++) {
            c = substr(part, i, 1)
            if (quote != "") {
                if (esc) {
                    esc = 0
                } else if (c == "\\") {
                    esc = 1
                } else if (c == quote) {
                    quote = ""
                }
                continue
            }
            if (c == "\"" || c == "'"'"'") {
                quote = c
                continue
            }
            if (c == "{" || c == "[") {
                depth++
            } else if (c == "}" || c == "]") {
                depth--
            } else if (c == ":" && depth == 0) {
                colon = i
                break
            }
        }
        if (colon <= 0) {
            return
        }
        key = clean_scalar(substr(part, 1, colon - 1))
        value = trim(substr(part, colon + 1))
        if (substr(value, 1, 1) == "{" && substr(value, length(value), 1) == "}") {
            parse_map(value, prefix key ".")
        } else {
            set_field(prefix key, value)
        }
    }
    function parse_map(s, prefix,    i,c,depth,quote,esc,start,part) {
        s = trim(s)
        if (substr(s, 1, 1) == "{") {
            s = substr(s, 2)
        }
        if (substr(s, length(s), 1) == "}") {
            s = substr(s, 1, length(s) - 1)
        }
        depth = 0
        quote = ""
        esc = 0
        start = 1
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (quote != "") {
                if (esc) {
                    esc = 0
                } else if (c == "\\") {
                    esc = 1
                } else if (c == quote) {
                    quote = ""
                }
                continue
            }
            if (c == "\"" || c == "'"'"'") {
                quote = c
                continue
            }
            if (c == "{" || c == "[") {
                depth++
            } else if (c == "}" || c == "]") {
                depth--
            } else if (c == "," && depth == 0) {
                part = substr(s, start, i - start)
                parse_pair(part, prefix)
                start = i + 1
            }
        }
        part = substr(s, start)
        parse_pair(part, prefix)
    }
    function leading_indent(s,    i,c) {
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c != " " && c != "\t") {
                return i - 1
            }
        }
        return length(s)
    }
    function parse_block_line(line,    indent,t,key,value,colon,fullkey) {
        indent = leading_indent(line)
        t = trim(line)
        if (t == "") {
            return
        }
        colon = index(t, ":")
        if (colon <= 0) {
            return
        }
        key = clean_scalar(substr(t, 1, colon - 1))
        value = trim(substr(t, colon + 1))

        if (ctx != "" && indent <= ctx_indent) {
            ctx = ""
            ctx_indent = -1
        }

        if (value == "") {
            if (key == "ws-opts" || key == "grpc-opts" || key == "reality-opts" || key == "obfs-opts" || key == "headers") {
                if (ctx != "" && indent > ctx_indent) {
                    ctx = ctx "." key
                } else {
                    ctx = key
                }
                ctx_indent = indent
            }
            return
        }

        fullkey = key
        if (ctx != "" && indent > ctx_indent) {
            fullkey = ctx "." key
        }
        set_field(fullkey, value)
    }
    BEGIN {
        in_proxies = 0
        clear_fields()
    }
    /^[^ \t]/ {
        if (in_proxies && $0 !~ /^proxies:[ \t]*($|#)/ && $0 !~ /^-[ \t]*/) {
            emit_record()
            in_proxies = 0
        }
    }
    /^[ \t]*proxies:[ \t]*($|#)/ {
        emit_record()
        in_proxies = 1
        next
    }
    {
        if (!in_proxies) {
            next
        }
        line = $0
        if (line ~ /^[ \t]*-[ \t]*\{/) {
            emit_record()
            clear_fields()
            sub(/^[ \t]*-[ \t]*/, "", line)
            parse_map(line, "")
            emit_record()
            next
        }
        if (line ~ /^[ \t]*-[ \t]*/) {
            emit_record()
            clear_fields()
            sub(/^[ \t]*-[ \t]*/, "", line)
            if (trim(line) != "") {
                parse_block_line(line)
            }
            next
        }
        if (field_count > 0) {
            parse_block_line(line)
        }
    }
    END {
        emit_record()
    }
    ' "$input"
}

subscription_clash_value() {
    local record="$1"
    local key="$2"
    local rest value

    case "$record" in
    *\"$key\":\"*)
        rest="${record#*\"$key\":\"}"
        value="${rest%%\"*}"
        value="$(printf '%s' "$value" | sed 's/\\"/"/g;s/\\\\/\\/g')"
        printf '%s\n' "$value"
        ;;
    *)
        printf '\n'
        ;;
    esac
}

subscription_parse_clash_record() {
    local record="$1"
    local type name server port tls skip_verify sni network ws_path ws_host grpc_service_name \
        reality_public_key reality_short_id alpn fingerprint password uuid cipher alter_id flow packet_encoding \
        obfs obfs_password username

    type="$(subscription_clash_value "$record" "type" | tr '[:upper:]' '[:lower:]')"
    name="$(subscription_clash_value "$record" "name")"
    server="$(subscription_clash_value "$record" "server")"
    port="$(subscription_clash_value "$record" "port")"
    tls="$(subscription_clash_value "$record" "tls")"
    skip_verify="$(subscription_clash_value "$record" "skip-cert-verify")"
    sni="$(subscription_clash_value "$record" "sni")"
    [ -n "$sni" ] || sni="$(subscription_clash_value "$record" "servername")"
    network="$(subscription_clash_value "$record" "network" | tr '[:upper:]' '[:lower:]')"
    ws_path="$(subscription_clash_value "$record" "ws-opts.path")"
    ws_host="$(subscription_clash_value "$record" "ws-opts.headers.Host")"
    grpc_service_name="$(subscription_clash_value "$record" "grpc-opts.grpc-service-name")"
    reality_public_key="$(subscription_clash_value "$record" "reality-opts.public-key")"
    reality_short_id="$(subscription_clash_value "$record" "reality-opts.short-id")"
    alpn="$(subscription_clash_value "$record" "alpn" | sed 's/^\[//;s/\]$//;s/[[:space:]]//g')"
    fingerprint="$(subscription_clash_value "$record" "client-fingerprint")"
    [ -n "$fingerprint" ] || fingerprint="$(subscription_clash_value "$record" "fingerprint")"
    fingerprint="$(subscription_normalize_utls_fingerprint "$fingerprint")"
    [ -n "$name" ] || name="$server:$port"

    [ -n "$type" ] && [ -n "$server" ] && [ -n "$port" ] || return 1

    case "$type" in
    ss | shadowsocks)
        cipher="$(subscription_clash_value "$record" "cipher")"
        password="$(subscription_clash_value "$record" "password")"
        [ -n "$cipher" ] && [ -n "$password" ] || return 1
        [ "$cipher" = "ss" ] && return 1
        jq -cn --arg tag "$name" --arg server "$server" --arg port "$port" --arg method "$cipher" --arg password "$password" '
            {type:"shadowsocks", tag:$tag, server:$server, server_port:($port|tonumber), method:$method, password:$password}'
        ;;
    vmess)
        uuid="$(subscription_clash_value "$record" "uuid")"
        alter_id="$(subscription_clash_value "$record" "alterId")"
        [ -n "$alter_id" ] || alter_id="$(subscription_clash_value "$record" "alter-id")"
        cipher="$(subscription_clash_value "$record" "cipher")"
        [ -n "$cipher" ] || cipher="auto"
        [ -n "$uuid" ] || return 1
        jq -cn \
            --arg type "vmess" --arg tag "$name" --arg server "$server" --arg port "$port" \
            --arg uuid "$uuid" --arg alter_id "$alter_id" --arg security "$cipher" \
            --arg tls "$(subscription_bool_json "$tls")" \
            --arg skip_verify "$(subscription_bool_json "$skip_verify")" \
            --arg sni "$sni" --arg alpn "$alpn" --arg fingerprint "$fingerprint" \
            --arg network "$network" --arg ws_path "$ws_path" --arg ws_host "$ws_host" --arg grpc_service_name "$grpc_service_name" '
            {
                type:$type, tag:$tag, server:$server, server_port:($port|tonumber), uuid:$uuid, security:$security
            }
            + (if $alter_id != "" then {alter_id:($alter_id|tonumber)} else {} end)
            + (if $tls == "true" or $sni != "" or $fingerprint != "" then
                {tls: ({enabled:true}
                    + (if $sni != "" then {server_name:$sni} else {} end)
                    + (if $skip_verify == "true" then {insecure:true} else {} end)
                    + (if $alpn != "" then {alpn:($alpn|split(","))} else {} end)
                    + (if $fingerprint != "" then {utls:{enabled:true,fingerprint:$fingerprint}} else {} end))}
            else {} end)
            + (if $network == "ws" then {transport:({type:"ws", path:(if $ws_path != "" then $ws_path else "/" end)} + (if $ws_host != "" then {headers:{Host:$ws_host}} else {} end))}
               elif $network == "grpc" then {transport:({type:"grpc"} + (if $grpc_service_name != "" then {service_name:$grpc_service_name} else {} end))}
               else {} end)'
        ;;
    vless)
        uuid="$(subscription_clash_value "$record" "uuid")"
        flow="$(subscription_clash_value "$record" "flow")"
        packet_encoding="$(subscription_clash_value "$record" "packet-encoding")"
        [ -n "$packet_encoding" ] || packet_encoding="$(subscription_clash_value "$record" "packetEncoding")"
        packet_encoding="$(subscription_normalize_packet_encoding "$packet_encoding")"
        [ -n "$uuid" ] || return 1
        subscription_vless_flow_is_supported "$flow" || return 1
        jq -cn \
            --arg tag "$name" --arg server "$server" --arg port "$port" --arg uuid "$uuid" \
            --arg flow "$flow" --arg packet_encoding "$packet_encoding" \
            --arg tls "$(subscription_bool_json "$tls")" \
            --arg skip_verify "$(subscription_bool_json "$skip_verify")" \
            --arg sni "$sni" --arg alpn "$alpn" --arg fingerprint "$fingerprint" \
            --arg reality_public_key "$reality_public_key" --arg reality_short_id "$reality_short_id" \
            --arg network "$network" --arg ws_path "$ws_path" --arg ws_host "$ws_host" --arg grpc_service_name "$grpc_service_name" '
            {
                type:"vless", tag:$tag, server:$server, server_port:($port|tonumber), uuid:$uuid
            }
            + (if $flow != "" then {flow:$flow} else {} end)
            + (if $packet_encoding != "" then {packet_encoding:$packet_encoding} else {} end)
            + (if $tls == "true" or $sni != "" or $fingerprint != "" or $reality_public_key != "" then
                {tls: ({enabled:true}
                    + (if $sni != "" then {server_name:$sni} else {} end)
                    + (if $skip_verify == "true" then {insecure:true} else {} end)
                    + (if $alpn != "" then {alpn:($alpn|split(","))} else {} end)
                    + (if $reality_public_key != "" then
                        {utls:{enabled:true,fingerprint:(if $fingerprint != "" then $fingerprint else "chrome" end)}}
                    elif $fingerprint != "" then
                        {utls:{enabled:true,fingerprint:$fingerprint}}
                    else {} end)
                    + (if $reality_public_key != "" then {reality:({enabled:true, public_key:$reality_public_key} + (if $reality_short_id != "" then {short_id:$reality_short_id} else {} end))} else {} end))}
            else {} end)
            + (if $network == "ws" then {transport:({type:"ws", path:(if $ws_path != "" then $ws_path else "/" end)} + (if $ws_host != "" then {headers:{Host:$ws_host}} else {} end))}
               elif $network == "grpc" then {transport:({type:"grpc"} + (if $grpc_service_name != "" then {service_name:$grpc_service_name} else {} end))}
               else {} end)'
        ;;
    trojan)
        password="$(subscription_clash_value "$record" "password")"
        [ -n "$password" ] || return 1
        jq -cn \
            --arg tag "$name" --arg server "$server" --arg port "$port" --arg password "$password" \
            --arg tls "$(subscription_bool_json "$tls")" \
            --arg skip_verify "$(subscription_bool_json "$skip_verify")" \
            --arg sni "$sni" --arg alpn "$alpn" --arg fingerprint "$fingerprint" \
            --arg reality_public_key "$reality_public_key" --arg reality_short_id "$reality_short_id" \
            --arg network "$network" --arg ws_path "$ws_path" --arg ws_host "$ws_host" --arg grpc_service_name "$grpc_service_name" '
            {
                type:"trojan", tag:$tag, server:$server, server_port:($port|tonumber), password:$password
            }
            + {tls: ({enabled:true}
                + (if $sni != "" then {server_name:$sni} else {} end)
                + (if $skip_verify == "true" then {insecure:true} else {} end)
                + (if $alpn != "" then {alpn:($alpn|split(","))} else {} end)
                + (if $reality_public_key != "" then
                    {utls:{enabled:true,fingerprint:(if $fingerprint != "" then $fingerprint else "chrome" end)}}
                elif $fingerprint != "" then
                    {utls:{enabled:true,fingerprint:$fingerprint}}
                else {} end)
                + (if $reality_public_key != "" then {reality:({enabled:true, public_key:$reality_public_key} + (if $reality_short_id != "" then {short_id:$reality_short_id} else {} end))} else {} end))}
            + (if $network == "ws" then {transport:({type:"ws", path:(if $ws_path != "" then $ws_path else "/" end)} + (if $ws_host != "" then {headers:{Host:$ws_host}} else {} end))}
               elif $network == "grpc" then {transport:({type:"grpc"} + (if $grpc_service_name != "" then {service_name:$grpc_service_name} else {} end))}
               else {} end)'
        ;;
    hysteria2 | hy2)
        password="$(subscription_clash_value "$record" "password")"
        obfs="$(subscription_clash_value "$record" "obfs")"
        obfs_password="$(subscription_clash_value "$record" "obfs-password")"
        [ -n "$obfs_password" ] || obfs_password="$(subscription_clash_value "$record" "obfs-opts.password")"
        [ -n "$password" ] || return 1
        jq -cn \
            --arg tag "$name" --arg server "$server" --arg port "$port" --arg password "$password" \
            --arg skip_verify "$(subscription_bool_json "$skip_verify")" \
            --arg sni "$sni" --arg alpn "$alpn" --arg obfs "$obfs" --arg obfs_password "$obfs_password" '
            {
                type:"hysteria2", tag:$tag, server:$server, server_port:($port|tonumber), password:$password,
                tls: ({enabled:true}
                    + (if $sni != "" then {server_name:$sni} else {} end)
                    + (if $skip_verify == "true" then {insecure:true} else {} end)
                    + (if $alpn != "" then {alpn:($alpn|split(","))} else {} end))
            }
            + (if $obfs != "" and $obfs != "none" then {obfs:({type:$obfs} + (if $obfs_password != "" then {password:$obfs_password} else {} end))} else {} end)'
        ;;
    socks5 | socks)
        username="$(subscription_clash_value "$record" "username")"
        password="$(subscription_clash_value "$record" "password")"
        jq -cn --arg tag "$name" --arg server "$server" --arg port "$port" --arg username "$username" --arg password "$password" '
            {type:"socks", tag:$tag, server:$server, server_port:($port|tonumber), version:"5"}
            + (if $username != "" then {username:$username} else {} end)
            + (if $password != "" then {password:$password} else {} end)'
        ;;
    *)
        return 1
        ;;
    esac
}

subscription_normalize_clash_yaml_file() {
    local input="$1"
    local output="$2"
    local records jsonl record added skipped

    records="$(mktemp)" || return 1
    jsonl="$(mktemp)" || {
        rm -f "$records"
        return 1
    }

    subscription_clash_yaml_records "$input" > "$records"

    added=0
    skipped=0
    while IFS= read -r record || [ -n "$record" ]; do
        [ -n "$record" ] || continue
        if subscription_parse_clash_record "$record" >> "$jsonl"; then
            added=$((added + 1))
        else
            skipped=$((skipped + 1))
            log "Skip unsupported or invalid Clash proxy entry" "warn"
        fi
    done < "$records"

    rm -f "$records"

    if [ "$added" -eq 0 ]; then
        rm -f "$jsonl"
        return 1
    fi

    jq -s --argjson skipped "$skipped" '{
        version: 1,
        format: "clash-yaml",
        skipped: $skipped,
        outbounds: .
    }' "$jsonl" > "$output"
    rm -f "$jsonl"
}

subscription_normalize_content_file() {
    local input="$1"
    local output="$2"
    local depth="${3:-0}"
    local decoded_tmp

    convert_crlf_to_lf "$input"
    subscription_strip_metadata_preamble_file "$input"

    if jq -e . "$input" >/dev/null 2>&1; then
        subscription_normalize_sing_box_json_file "$input" "$output" || return 1
        subscription_validate_normalized_file "$output"
        return $?
    fi

    if subscription_content_is_clash_yaml "$input"; then
        subscription_normalize_clash_yaml_file "$input" "$output" || return 1
        subscription_validate_normalized_file "$output"
        return $?
    fi

    if subscription_content_has_share_links "$input"; then
        subscription_normalize_uri_list_file "$input" "$output" || return 1
        subscription_validate_normalized_file "$output"
        return $?
    fi

    if [ "$depth" -lt 1 ]; then
        decoded_tmp="$(mktemp)" || return 1
        if subscription_try_base64_decode_file "$input" "$decoded_tmp"; then
            if subscription_normalize_content_file "$decoded_tmp" "$output" $((depth + 1)); then
                rm -f "$decoded_tmp"
                return 0
            fi
        fi
        rm -f "$decoded_tmp"
    fi

    return 1
}

normalize_subscription_file() {
    local input="$1"
    local output="$2"
    local section="$3"
    local tmp_output

    tmp_output="$(mktemp)" || return 1
    if ! subscription_normalize_content_file "$input" "$tmp_output"; then
        log "Subscription for rule '$section' has no supported proxy entries" "error"
        rm -f "$tmp_output"
        return 1
    fi

    mv "$tmp_output" "$output"
}
