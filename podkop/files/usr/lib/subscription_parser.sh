# shellcheck shell=ash

subscription_url_get_fragment() {
    subscription_parser_ucode url-fragment "$1"
}

subscription_extract_ui_metadata() {
    local headers_file="$1"
    local body_file="$2"
    local output="$3"

    if subscription_parser_ucode metadata-extract-ui-json "$headers_file" "$body_file" > "$output" && [ -s "$output" ]; then
        return 0
    fi

    rm -f "$output"
    return 1
}

subscription_parser_ucode() {
    ucode "${PODKOP_LIB:-/usr/lib/podkop-plus}/subscription_parser.uc" "$@"
}

subscription_validate_normalized_file() {
    local output="$1"

    subscription_parser_ucode validate-subscription "$output" >/dev/null 2>&1
}

subscription_log_normalized_skipped() {
    local output="$1"

    local message
    message="$(subscription_parser_ucode normalized-skipped-warning "$output" 2>/dev/null)"
    [ -n "$message" ] || return 0
    log "$message" "warn"
}

subscription_gzip_decode_file() {
    local input="$1"
    local output="$2"

    [ -s "$input" ] || return 1

    if command -v gzip >/dev/null 2>&1; then
        if gzip -dc "$input" > "$output" 2>/dev/null && [ -s "$output" ]; then
            return 0
        fi
        rm -f "$output"
    fi

    if command -v gunzip >/dev/null 2>&1; then
        if gunzip -c "$input" > "$output" 2>/dev/null && [ -s "$output" ]; then
            return 0
        fi
        rm -f "$output"
    fi

    if command -v zcat >/dev/null 2>&1; then
        if zcat "$input" > "$output" 2>/dev/null && [ -s "$output" ]; then
            return 0
        fi
        rm -f "$output"
    fi

    return 1
}

subscription_try_decode_gzip_content_file() {
    local input="$1"
    local tmpfile

    tmpfile="$(mktemp)" || return 1
    if subscription_gzip_decode_file "$input" "$tmpfile"; then
        mv "$tmpfile" "$input" || {
            rm -f "$tmpfile"
            return 1
        }
        return 0
    fi

    rm -f "$tmpfile"
    return 1
}

subscription_normalize_content_file() {
    local input="$1"
    local output="$2"
    local normalize_input="$input"
    local decoded_tmpfile status

    decoded_tmpfile="$(mktemp)" || decoded_tmpfile=""
    if [ -n "$decoded_tmpfile" ]; then
        if subscription_gzip_decode_file "$input" "$decoded_tmpfile"; then
            normalize_input="$decoded_tmpfile"
        else
            rm -f "$decoded_tmpfile"
            decoded_tmpfile=""
        fi
    fi

    if subscription_parser_ucode normalize-content "$normalize_input" "$output"; then
        subscription_log_normalized_skipped "$output"
        subscription_validate_normalized_file "$output"
        status=$?
    else
        status=1
    fi

    [ -n "$decoded_tmpfile" ] && rm -f "$decoded_tmpfile"
    return "$status"
}

subscription_runtime_outbounds_equal() {
    local left="$1"
    local right="$2"

    subscription_parser_ucode runtime-outbounds-equal "$left" "$right" >/dev/null 2>&1
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
