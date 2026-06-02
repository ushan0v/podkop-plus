# shellcheck shell=ash

has_enabled_zapret2_rules() {
    local count

    count="$(get_zapret2_rule_count)"
    [ "${count:-0}" -gt 0 ]
}

_count_zapret2_rule_handler() {
    local section="$1"

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret2" ] || return 0

    ZAPRET2_RULE_COUNT=$((ZAPRET2_RULE_COUNT + 1))
}

get_zapret2_rule_count() {
    ZAPRET2_RULE_COUNT=0
    config_foreach _count_zapret2_rule_handler "section"
    echo "$ZAPRET2_RULE_COUNT"
}

_find_zapret2_rule_index_handler() {
    local section="$1"
    local target_section="$2"

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret2" ] || return 0

    ZAPRET2_RULE_INDEX_WALK=$((ZAPRET2_RULE_INDEX_WALK + 1))
    if [ "$section" = "$target_section" ]; then
        ZAPRET2_RULE_INDEX_RESULT="$ZAPRET2_RULE_INDEX_WALK"
    fi
}

get_zapret2_rule_index() {
    local section="$1"

    ZAPRET2_RULE_INDEX_WALK=0
    ZAPRET2_RULE_INDEX_RESULT=0
    config_foreach _find_zapret2_rule_index_handler "section" "$section"

    echo "$ZAPRET2_RULE_INDEX_RESULT"
}

format_zapret2_mark_hex() {
    local mark_value="$1"

    printf '0x%08x\n' "$mark_value"
}

get_zapret2_rule_mark_value() {
    local index="$1"

    echo $((ZAPRET2_ROUTE_MARK_BASE + index))
}

get_zapret2_rule_mark_hex() {
    local index="$1"

    format_zapret2_mark_hex "$(get_zapret2_rule_mark_value "$index")"
}

get_zapret2_rule_queue_number() {
    local index="$1"

    echo $((ZAPRET2_QUEUE_BASE + index - 1))
}

get_rule_nfqws2_opt() {
    local section="$1"
    local nfqws2_opt

    config_get nfqws2_opt "$section" "nfqws2_opt"
    if [ -n "$nfqws2_opt" ]; then
        normalize_nfqws2_strategy_whitespace "$nfqws2_opt"
    else
        normalize_nfqws2_strategy_whitespace "$ZAPRET2_DEFAULT_NFQWS2_OPT"
    fi
}

normalize_nfqws2_strategy_whitespace() {
    printf '%s' "$1" | tr '\t\r\n' '   ' | tr -s ' ' | sed 's/^ //; s/ $//'
}

nfqws2_option_argument_mode() {
    case "$1" in
    --debug | --comment | --intercept | --chdir | --ctrack-disable | --payload-disable | \
        --server | --ipcache-hostname | --reasm-disable | --writeable | --new | --template | \
        --hostlist-auto-retrans-reset)
        echo "optional"
        ;;
    --dry-run | --version | --daemon | --skip | --bind-fix4 | --bind-fix6)
        echo "none"
        ;;
    --qnum | --pidfile | --user | --uid | --ctrack-timeouts | --ipcache-lifetime | \
        --fwmark | --fuzz | --blob | --lua-init | --lua-gc | --hostlist | \
        --hostlist-domains | --hostlist-exclude | --hostlist-exclude-domains | \
        --hostlist-auto | --hostlist-auto-fail-threshold | --hostlist-auto-fail-time | \
        --hostlist-auto-retrans-threshold | --hostlist-auto-retrans-maxseq | \
        --hostlist-auto-incoming-maxseq | --hostlist-auto-udp-in | --hostlist-auto-udp-out | \
        --hostlist-auto-debug | --name | --import | --cookie | --filter-l3 | --filter-tcp | \
        --filter-udp | --filter-icmp | --filter-ipp | --filter-l7 | --filter-ssid | \
        --ipset | --ipset-ip | --ipset-exclude | --ipset-exclude-ip | \
        --payload | --in-range | --out-range | --lua-desync)
        echo "required"
        ;;
    *)
        echo "unknown"
        ;;
    esac
}

clear_nfqws2_validation_state() {
    NFQWS2_VALIDATE_ERROR=""
    NFQWS2_VALIDATE_NEEDLE=""
    NFQWS2_VALIDATE_NEEDLES=""
}

append_nfqws2_validation_needle() {
    local needle="$1"

    [ -n "$needle" ] || return 0

    case "
$NFQWS2_VALIDATE_NEEDLES
" in
    *"
$needle
"*)
        return 0
        ;;
    esac

    if [ -n "$NFQWS2_VALIDATE_NEEDLES" ]; then
        NFQWS2_VALIDATE_NEEDLES="${NFQWS2_VALIDATE_NEEDLES}
$needle"
    else
        NFQWS2_VALIDATE_NEEDLES="$needle"
    fi

    [ -n "$NFQWS2_VALIDATE_NEEDLE" ] || NFQWS2_VALIDATE_NEEDLE="$needle"
}

set_nfqws2_validation_failure() {
    NFQWS2_VALIDATE_ERROR="$1"
    NFQWS2_VALIDATE_NEEDLE=""
    NFQWS2_VALIDATE_NEEDLES=""
    shift

    while [ "$#" -gt 0 ]; do
        append_nfqws2_validation_needle "$1"
        shift
    done

    return 1
}

get_nfqws2_unsupported_token_reason() {
    local token="$1"

    case "$token" in
    "<HOSTLIST>" | "<HOSTLIST_NOAUTO>")
        echo "Podkop Plus does not expand zapret2 hostlist templates in per-rule strategies because sing-box already selects the resources before NFQUEUE."
        return 0
        ;;
    --hostlist | --hostlist=* | --hostlist-domains | --hostlist-domains=* | \
        --hostlist-exclude | --hostlist-exclude=* | --hostlist-exclude-domains | --hostlist-exclude-domains=* | \
        --hostlist-auto | --hostlist-auto=* | --hostlist-auto-fail-threshold | --hostlist-auto-fail-threshold=* | \
        --hostlist-auto-fail-time | --hostlist-auto-fail-time=* | \
        --hostlist-auto-retrans-threshold | --hostlist-auto-retrans-threshold=* | \
        --hostlist-auto-retrans-maxseq | --hostlist-auto-retrans-maxseq=* | \
        --hostlist-auto-retrans-reset | --hostlist-auto-retrans-reset=* | \
        --hostlist-auto-incoming-maxseq | --hostlist-auto-incoming-maxseq=* | \
        --hostlist-auto-udp-in | --hostlist-auto-udp-in=* | --hostlist-auto-udp-out | --hostlist-auto-udp-out=* | \
        --hostlist-auto-debug | --hostlist-auto-debug=*)
        echo "Hostname-based selection inside nfqws2 is incompatible with the Podkop Plus architecture because sing-box already chooses which resources enter action=zapret2."
        return 0
        ;;
    --ipset | --ipset=* | --ipset-ip | --ipset-ip=* | --ipset-exclude | --ipset-exclude=* | --ipset-exclude-ip | --ipset-exclude-ip=*)
        echo "IP or CIDR selection inside nfqws2 is incompatible with the Podkop Plus architecture because sing-box already chooses which resources enter action=zapret2."
        return 0
        ;;
    --qnum | --qnum=*)
        echo "The NFQUEUE number is assigned by Podkop Plus per rule and must not be overridden in the strategy."
        return 0
        ;;
    --fwmark | --fwmark=* | --dpi-desync-fwmark | --dpi-desync-fwmark=*)
        echo "The nfqws2 fwmark is managed by Podkop Plus for loop prevention and must not be overridden in the strategy."
        return 0
        ;;
    --fuzz | --fuzz=*)
        echo "nfqws2 fuzz mode disables normal interception and is incompatible with Podkop Plus-managed action=zapret2 rules."
        return 0
        ;;
    --intercept=0)
        echo "nfqws2 interception must stay enabled for Podkop Plus-managed action=zapret2 rules."
        return 0
        ;;
    --daemon)
        echo "Podkop Plus manages the nfqws2 process lifecycle itself. The strategy must not daemonize nfqws2."
        return 0
        ;;
    --dry-run)
        echo "The strategy must launch a working nfqws2 process. --dry-run exits immediately and is not allowed."
        return 0
        ;;
    --version)
        echo "The strategy must launch a working nfqws2 process. --version exits immediately and is not allowed."
        return 0
        ;;
    esac

    return 1
}

normalize_nfqws2_validation_output() {
    printf '%s\n' "$1" | sed 's/\r$//'
}

extract_nfqws2_validation_summary() {
    local output="$1"
    local summary

    summary="$(normalize_nfqws2_validation_output "$output" | grep -m1 -E 'unrecognized option:|option requires an argument:|option does not take an argument:|[Ii]nvalid |bad [^ ]|must be |fooling allowed values|incompatible|only one |No such file|not found|cannot |failed to |unable to |should be |Too much splits|out of memory|not supported|value error' | sed 's#^.*/nfqws2: ##; s/^nfqws2: //')"
    if [ -n "$summary" ]; then
        printf '%s\n' "$summary"
        return 0
    fi

    normalize_nfqws2_validation_output "$output" | awk '
        /^github version / { next }
        /^we have [0-9]+ user defined desync profile/ { next }
        /^Running as UID=/ { next }
        /^command line parameters verified$/ { next }
        /^[[:space:]]*$/ { next }
        {
            sub(/^.*\/nfqws2:[[:space:]]*/, "", $0)
            sub(/^nfqws2:[[:space:]]*/, "", $0)
            print
            exit
        }
    '
}

extract_nfqws2_validation_value_hint() {
    local summary="$1"
    local value=""

    case "$summary" in
    *"Invalid port filter :"* | *"Invalid l7 filter :"* | *"invalid debug mode :"* | \
        *"invalid ip_id mode :"* | *"Invalid fakedsplit mod :"* | \
        *"Invalid hostfakesplit mod :"* | *"Invalid tcp mod :"* | \
        *"Invalid tls mod :"* | *"invalid dup ip_id mode :"*)
        value="$(printf '%s\n' "$summary" | sed -n 's/.*:[[:space:]]*\([^[:space:]]\+\).*/\1/p' | head -n 1)"
        ;;
    esac

    printf '%s\n' "$value"
}

extract_nfqws2_validation_option_hint() {
    local summary="$1"
    local option=""

    option="$(printf '%s\n' "$summary" | grep -oE -- '--[[:alnum:]][[:alnum:]-]*' | head -n 1)"
    if [ -n "$option" ]; then
        printf '%s\n' "$option"
        return 0
    fi

    case "$summary" in
    *"unrecognized option:"*)
        option="$(printf '%s\n' "$summary" | sed -n 's/.*unrecognized option:[[:space:]]*\([^[:space:]]\+\).*/\1/p' | head -n 1)"
        case "$option" in
        "") ;;
        --*) ;;
        -*) option="-$option" ;;
        *) option="--$option" ;;
        esac
        ;;
    *"option requires an argument:"*)
        option="$(printf '%s\n' "$summary" | sed -n 's/.*option requires an argument:[[:space:]]*\([^[:space:]]\+\).*/--\1/p' | head -n 1)"
        ;;
    *"option does not take an argument:"*)
        option="$(printf '%s\n' "$summary" | sed -n 's/.*option does not take an argument:[[:space:]]*\([^[:space:]]\+\).*/--\1/p' | head -n 1)"
        ;;
    *"invalid debug mode :"*)
        option="--debug"
        ;;
    *"hostspell must be exactly 4 chars long"*)
        option="--hostspell"
        ;;
    *"invalid ip_id mode :"*)
        option="--ip-id"
        ;;
    *"invalid dup ip_id mode :"*)
        option="--dup-ip-id"
        ;;
    *"dup-autottl value error"*)
        option="--dup-autottl"
        ;;
    *"dup-autottl6 value error"*)
        option="--dup-autottl6"
        ;;
    *"dpi-desync-autottl value error"*)
        option="--dpi-desync-autottl"
        ;;
    *"dpi-desync-autottl6 value error"*)
        option="--dpi-desync-autottl6"
        ;;
    *"orig-autottl value error"*)
        option="--orig-autottl"
        ;;
    *"orig-autottl6 value error"*)
        option="--orig-autottl6"
        ;;
    *"invalid dpi-desync mode"* | *"invalid desync combo :"*)
        option="--dpi-desync"
        ;;
    *"invalid wssize-cutoff value"*)
        option="--wssize-cutoff"
        ;;
    *"invalid synack-split value"*)
        option="--synack-split"
        ;;
    *"invalid ctrack-timeouts value"*)
        option="--ctrack-timeouts"
        ;;
    *"invalid ipcache-lifetime value"*)
        option="--ipcache-lifetime"
        ;;
    *"dpi-desync-repeats must be within "*)
        option="--dpi-desync-repeats"
        ;;
    *"dup-repeats must be within "*)
        option="--dup"
        ;;
    *"invalid desync-cutoff value"*)
        option="--dpi-desync-cutoff"
        ;;
    *"invalid desync-start value"*)
        option="--dpi-desync-start"
        ;;
    *"Invalid fakedsplit mod :"*)
        option="--dpi-desync-fakedsplit-mod"
        ;;
    *"Invalid hostfakesplit mod :"*)
        option="--dpi-desync-hostfakesplit-mod"
        ;;
    *"Invalid tcp mod :"*)
        option="--dpi-desync-fake-tcp-mod"
        ;;
    *"Invalid tls mod :"*)
        option="--dpi-desync-fake-tls-mod"
        ;;
    *"Invalid argument for dpi-desync-split-http-req"*)
        option="--dpi-desync-split-http-req"
        ;;
    *"Invalid argument for dpi-desync-split-tls"*)
        option="--dpi-desync-split-tls"
        ;;
    *"Invalid argument for dpi-desync-split-seqovl"*)
        option="--dpi-desync-split-seqovl"
        ;;
    *"Invalid argument for dpi-desync-hostfakesplit-midhost"*)
        option="--dpi-desync-hostfakesplit-midhost"
        ;;
    *"dpi-desync-ipfrag-pos-tcp must be within "* | *"dpi-desync-ipfrag-pos-tcp must be multiple of 8"*)
        option="--dpi-desync-ipfrag-pos-tcp"
        ;;
    *"dpi-desync-ipfrag-pos-udp must be within "* | *"dpi-desync-ipfrag-pos-udp must be multiple of 8"*)
        option="--dpi-desync-ipfrag-pos-udp"
        ;;
    *"dpi-desync-ts-increment should be "*)
        option="--dpi-desync-ts-increment"
        ;;
    *"dpi-desync-badseq-increment should be "*)
        option="--dpi-desync-badseq-increment"
        ;;
    *"dpi-desync-badack-increment should be "*)
        option="--dpi-desync-badack-increment"
        ;;
    *"dup-ts-increment should be "*)
        option="--dup-ts-increment"
        ;;
    *"dup-badseq-increment should be "*)
        option="--dup-badseq-increment"
        ;;
    *"dup-badack-increment should be "*)
        option="--dup-badack-increment"
        ;;
    *"bad value for --filter-l3"*)
        option="--filter-l3"
        ;;
    *"auto hostlist fail time is not valid"*)
        option="--hostlist-auto-fail-time"
        ;;
    *"auto hostlist fail threshold must be within 1..20"*)
        option="--hostlist-auto-fail-threshold"
        ;;
    *"auto hostlist fail threshold must be within 2..10"*)
        option="--hostlist-auto-retrans-threshold"
        ;;
    *"dpi-desync-udplen-increment must be integer within "*)
        option="--dpi-desync-udplen-increment"
        ;;
    esac

    printf '%s\n' "$option"
}

collect_nfqws2_validation_needles() {
    local summary="$1"
    local option value

    option="$(extract_nfqws2_validation_option_hint "$summary")"
    value="$(extract_nfqws2_validation_value_hint "$summary")"

    [ -n "$option" ] && printf '%s\n' "$option"
    [ -n "$value" ] && printf '%s\n' "$value"
}

run_nfqws2_dry_run_validation() {
    local raw_opt="$1"
    local old_ifs output_file output summary needles rc

    if ! is_zapret2_provider_available; then
        return 0
    fi

    raw_opt="$(expand_zapret2_nfqws2_opt "$raw_opt")"
    raw_opt="$(normalize_nfqws2_strategy_whitespace "$raw_opt")"
    [ -n "$raw_opt" ] || return 0

    output_file="$(mktemp)"

    set -f
    old_ifs="$IFS"
    IFS=' '
    set -- $raw_opt
    IFS="$old_ifs"

    "$ZAPRET2_NFQWS2_BIN" --dry-run --qnum="$ZAPRET2_QUEUE_BASE" $(get_zapret2_base_args) "$@" >"$output_file" 2>&1
    rc=$?
    output="$(cat "$output_file")"
    rm -f "$output_file"
    set +f

    [ "$rc" -eq 0 ] && return 0

    summary="$(extract_nfqws2_validation_summary "$output")"
    [ -n "$summary" ] || summary="nfqws2 rejected the strategy during syntax validation."

    needles="$(collect_nfqws2_validation_needles "$summary")"
    if [ -n "$needles" ]; then
        # shellcheck disable=SC2086
        set_nfqws2_validation_failure "nfqws2 syntax check failed: $summary" $needles
    else
        set_nfqws2_validation_failure "nfqws2 syntax check failed: $summary"
    fi
}

check_nfqws2_strategy() {
    local raw_opt="$1"
    local old_ifs token base_token mode reason display next_token token_count=0

    clear_nfqws2_validation_state
    raw_opt="$(normalize_nfqws2_strategy_whitespace "$raw_opt")"

    set -f
    old_ifs="$IFS"
    IFS=' '
    set -- $raw_opt
    IFS="$old_ifs"

    while [ "$#" -gt 0 ]; do
        token="$1"
        next_token="$2"
        base_token="${token%%=*}"

        if [ "$token_count" -eq 0 ]; then
            case "$token" in
            @* | \$*)
                set_nfqws2_validation_failure \
                    "Unsupported NFQWS2 token '$token': External nfqws2 config files bypass Podkop Plus validation and queue management." \
                    "$token"
                return 1
                ;;
            esac
        fi

        if reason="$(get_nfqws2_unsupported_token_reason "$token")"; then
            display="$token"
            mode="$(nfqws2_option_argument_mode "$base_token")"
            if [ "$base_token" = "$token" ] && [ "$mode" = "required" ] && [ "$#" -gt 1 ] && [ "${next_token#--}" = "$next_token" ]; then
                display="$display $next_token"
                set_nfqws2_validation_failure "Unsupported NFQWS2 token '$display': $reason" "$base_token" "$next_token"
                return 1
            fi

            set_nfqws2_validation_failure "Unsupported NFQWS2 token '$display': $reason" "$base_token"
            return 1
        fi

        case "$token" in
        --*)
            mode="$(nfqws2_option_argument_mode "$base_token")"
            case "$mode" in
            unknown)
                set_nfqws2_validation_failure \
                    "Unknown NFQWS2 flag '$token'." \
                    "$base_token"
                return 1
                ;;
            none)
                if [ "$base_token" != "$token" ]; then
                    set_nfqws2_validation_failure \
                        "NFQWS2 flag '$base_token' does not accept a value." \
                        "$base_token"
                    return 1
                fi
                shift
                token_count=$((token_count + 1))
                ;;
            optional)
                if [ "$base_token" = "$token" ] && [ "$#" -gt 1 ] && [ "${next_token#--}" = "$next_token" ]; then
                    set_nfqws2_validation_failure \
                        "Optional value for '$base_token' must be attached as '$base_token=value'. Separate tokens are ignored by nfqws2 here." \
                        "$base_token" "$next_token"
                    return 1
                fi
                shift
                token_count=$((token_count + 1))
                ;;
            required)
                if [ "$base_token" != "$token" ]; then
                    shift
                    token_count=$((token_count + 1))
                    continue
                fi

                if [ "$#" -lt 2 ] || [ "${next_token#--}" != "$next_token" ]; then
                    set_nfqws2_validation_failure \
                        "NFQWS2 option '$base_token' requires a value." \
                        "$base_token"
                    return 1
                fi

                shift 2
                token_count=$((token_count + 2))
                ;;
            esac
            ;;
        *)
            set_nfqws2_validation_failure \
                "Unexpected standalone NFQWS2 token '$token'. Use explicit flags such as --name or --name=value." \
                "$token"
            return 1
            ;;
        esac
    done

    set +f

    run_nfqws2_dry_run_validation "$raw_opt"
}

validate_nfqws2_strategy() {
    local raw_opt="$1"
    local context="$2"

    if ! check_nfqws2_strategy "$raw_opt"; then
        log "$context uses invalid NFQWS2 strategy: $NFQWS2_VALIDATE_ERROR Aborted." "fatal"
        exit 1
    fi
}

validate_rule_nfqws2_opt() {
    local section="$1"
    local raw_opt

    raw_opt="$(get_rule_nfqws2_opt "$section")"
    validate_nfqws2_strategy "$raw_opt" "Zapret2 rule '$section'"
}

prepare_zapret2_runtime() {
    mkdir -p "$ZAPRET2_STATE_DIR" "$ZAPRET2_PID_DIR" "$ZAPRET2_CHILD_PID_DIR" "$ZAPRET2_LOG_DIR"
}

get_zapret2_base_args() {
    printf '%s\n' \
        "--fwmark=$ZAPRET2_DESYNC_MARK" \
        "--lua-init=@$ZAPRET2_PROVIDER_LUA_DIR/zapret-lib.lua" \
        "--lua-init=@$ZAPRET2_PROVIDER_LUA_DIR/zapret-antidpi.lua" \
        "--lua-init=@$ZAPRET2_PROVIDER_LUA_DIR/zapret-auto.lua"
}

is_zapret2_provider_available() {
    [ -x "$ZAPRET2_PROVIDER_NFQWS2_BIN" ]
}

is_zapret2_installed() {
    is_zapret2_provider_available
}

zapret2_package_installed() {
    if command -v apk >/dev/null 2>&1 && apk info -e zapret2 >/dev/null 2>&1; then
        return 0
    fi

    if command -v opkg >/dev/null 2>&1 && opkg list-installed 2>/dev/null | grep -Eq '^zapret2[[:space:]-]'; then
        return 0
    fi

    return 1
}

luci_app_zapret2_installed() {
    if command -v apk >/dev/null 2>&1 && apk info -e luci-app-zapret2 >/dev/null 2>&1; then
        return 0
    fi

    if command -v opkg >/dev/null 2>&1 && opkg list-installed 2>/dev/null | grep -Eq '^luci-app-zapret2[[:space:]-]'; then
        return 0
    fi

    [ -f /usr/share/luci/menu.d/luci-app-zapret2.json ] ||
        [ -f /usr/share/rpcd/acl.d/luci-app-zapret2.json ]
}

expand_zapret2_nfqws2_opt() {
    printf '%s' "$1"
}

check_zapret2_requirements() {
    has_enabled_zapret2_rules || return 0

    if ! is_zapret2_provider_available; then
        log "Zapret2 provider is not available at $ZAPRET2_PROVIDER_NFQWS2_BIN. Rules with action 'zapret2' will be skipped until the zapret2 provider is installed." "error"
        return 0
    fi

    if ! prepare_zapret2_runtime; then
        log "Failed to prepare the Podkop Plus zapret2 state directory in $ZAPRET2_STATE_DIR. Aborted." "fatal"
        exit 1
    fi
}

get_zapret2_package_version() {
    local version=""

    if command -v apk >/dev/null 2>&1 && apk info -e zapret2 >/dev/null 2>&1; then
        version="$(get_apk_installed_package_version "zapret2")"
    elif command -v opkg >/dev/null 2>&1; then
        version="$(opkg list-installed 2>/dev/null | awk '$1 == "zapret2" { print $3; exit }')"
    fi

    if [ -z "$version" ] && [ -x "$ZAPRET2_PROVIDER_NFQWS2_BIN" ]; then
        version="$("$ZAPRET2_PROVIDER_NFQWS2_BIN" --version 2>/dev/null | sed -n '1s/^.*version[[:space:]]*//p' | awk '{ print $1; exit }')"
    fi

    echo "$version"
}

is_zapret2_standalone_service_enabled() {
    [ -x /etc/init.d/zapret2 ] || return 1
    /etc/init.d/zapret2 enabled >/dev/null 2>&1
}

is_zapret2_standalone_service_running() {
    [ -x /etc/init.d/zapret2 ] || return 1
    /etc/init.d/zapret2 status >/dev/null 2>&1
}

zapret2_standalone_uci_config_present() {
    [ -f /etc/config/zapret2 ] || return 1
    uci -q get zapret2.config >/dev/null 2>&1
}

get_zapret2_nfqws2_process_count() {
    local count=0 pidfile pid

    [ -d "$ZAPRET2_CHILD_PID_DIR" ] || {
        echo 0
        return 0
    }

    for pidfile in "$ZAPRET2_CHILD_PID_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        pid="$(cat "$pidfile" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            count=$((count + 1))
        else
            rm -f "$pidfile"
        fi
    done

    echo "$count"
}

get_zapret2_supervisor_process_count() {
    local count=0 pidfile pid

    [ -d "$ZAPRET2_PID_DIR" ] || {
        echo 0
        return 0
    }

    for pidfile in "$ZAPRET2_PID_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        pid="$(cat "$pidfile" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            count=$((count + 1))
        else
            rm -f "$pidfile"
        fi
    done

    echo "$count"
}

get_zapret2_queue_range_end() {
    echo $((ZAPRET2_QUEUE_BASE + ZAPRET2_QUEUE_RANGE_SIZE - 1))
}

zapret2_external_queue_overlap_present() {
    local range_end

    range_end="$(get_zapret2_queue_range_end)"
    nft list ruleset 2>/dev/null | awk \
        -v own_table="$NFT_TABLE_NAME" \
        -v range_start="$ZAPRET2_QUEUE_BASE" \
        -v range_end="$range_end" '
        function token_queue_overlap(token, first, last, parts) {
            gsub(/[{},;]/, "", token)
            if (token !~ /^[0-9]+(-[0-9]+)?$/) {
                return 0
            }

            split(token, parts, "-")
            first = parts[1] + 0
            last = (parts[2] == "" ? first : parts[2] + 0)

            return first <= range_end && last >= range_start
        }
        $1 == "table" {
            in_own_table = ($2 == "inet" && $3 == own_table)
        }
        !in_own_table {
            for (i = 1; i <= NF; i++) {
                if ($i != "queue") {
                    continue
                }

                for (j = i + 1; j <= NF; j++) {
                    if (($j == "num" || $j == "to") && token_queue_overlap($(j + 1))) {
                        found = 1
                    } else if (token_queue_overlap($j)) {
                        found = 1
                    }
                }
            }
        }
        END { exit(found ? 0 : 1) }
    '
}

zapret2_standalone_conflict_present() {
    has_enabled_zapret2_rules || return 1
    is_zapret2_standalone_service_running
}

zapret2_rule_outbound_present() {
    local section="$1"
    local routing_mark="$2"
    local outbound_tag

    [ -f "$ZAPRET2_SINGBOX_CONFIG_PATH" ] || return 1

    outbound_tag="$(get_outbound_tag_by_section "$section")"

    provider_status_ucode has-direct-mark-outbound "$ZAPRET2_SINGBOX_CONFIG_PATH" "$outbound_tag" "$routing_mark" >/dev/null 2>&1
}

zapret2_rule_route_rule_present() {
    local section="$1"
    local outbound_tag

    [ -f "$ZAPRET2_SINGBOX_CONFIG_PATH" ] || return 1

    outbound_tag="$(get_outbound_tag_by_section "$section")"

    provider_status_ucode has-route-rule "$ZAPRET2_SINGBOX_CONFIG_PATH" "$SB_TPROXY_INBOUND_TAG" "$outbound_tag" >/dev/null 2>&1
}

_collect_zapret2_runtime_status_handler() {
    local section="$1"
    local index mark_value

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret2" ] || return 0

    ZAPRET2_RUNTIME_RULES_CONFIGURED=1
    index="$(get_zapret2_rule_index "$section")"
    mark_value="$(get_zapret2_rule_mark_value "$index")"

    if ! zapret2_rule_outbound_present "$section" "$mark_value"; then
        ZAPRET2_RUNTIME_OUTBOUNDS_CONFIGURED=0
    fi

    if ! zapret2_rule_route_rule_present "$section"; then
        ZAPRET2_RUNTIME_ROUTES_CONFIGURED=0
    fi
}

collect_zapret2_runtime_status() {
    local sing_box_config_path

    ZAPRET2_RUNTIME_RULES_CONFIGURED=0
    ZAPRET2_RUNTIME_OUTBOUNDS_CONFIGURED=1
    ZAPRET2_RUNTIME_ROUTES_CONFIGURED=1

    config_get sing_box_config_path "settings" "config_path"
    ZAPRET2_SINGBOX_CONFIG_PATH="$sing_box_config_path"
    config_foreach _collect_zapret2_runtime_status_handler "section"

    if [ "$ZAPRET2_RUNTIME_RULES_CONFIGURED" -eq 0 ]; then
        ZAPRET2_RUNTIME_OUTBOUNDS_CONFIGURED=0
        ZAPRET2_RUNTIME_ROUTES_CONFIGURED=0
    fi
}

get_zapret2_status_json() {
    local installed=0 package_installed=0 provider_available=0 files_available=0 ipset_available=0 configured=0
    local standalone_service_enabled=0 standalone_service_running=0 standalone_config_present=0 ready=0 conflict=0
    local queue_overlap=0 standalone_conflict=0 luci_app_installed=0
    local enabled_rule_count expected_process_count running_process_count supervisor_process_count version queue_range_end status_message
    local outbounds_configured=0 routes_configured=0

    enabled_rule_count="$(get_zapret2_rule_count)"
    expected_process_count="${enabled_rule_count:-0}"
    running_process_count="$(get_zapret2_nfqws2_process_count)"
    supervisor_process_count="$(get_zapret2_supervisor_process_count)"
    queue_range_end="$(get_zapret2_queue_range_end)"
    version="not installed"
    status_message=""

    if [ "${enabled_rule_count:-0}" -gt 0 ]; then
        configured=1
    fi

    if zapret2_package_installed; then
        package_installed=1
        version="$(get_zapret2_package_version)"
        [ -n "$version" ] || version="unknown"
    fi

    if [ -d "$ZAPRET2_PROVIDER_FILES_DIR" ]; then
        files_available=1
    fi

    if [ -d "$ZAPRET2_PROVIDER_IPSET_DIR" ]; then
        ipset_available=1
    fi

    if is_zapret2_provider_available; then
        provider_available=1
        installed=1
        if [ "$package_installed" -eq 0 ]; then
            version="$(get_zapret2_package_version)"
            [ -n "$version" ] || version="unknown"
        fi
    fi

    if is_zapret2_standalone_service_enabled; then
        standalone_service_enabled=1
    fi

    if is_zapret2_standalone_service_running; then
        standalone_service_running=1
    fi

    if zapret2_standalone_uci_config_present; then
        standalone_config_present=1
    fi

    if zapret2_external_queue_overlap_present; then
        queue_overlap=1
    fi

    if zapret2_standalone_conflict_present; then
        standalone_conflict=1
    fi

    if luci_app_zapret2_installed; then
        luci_app_installed=1
    fi

    collect_zapret2_runtime_status
    outbounds_configured="${ZAPRET2_RUNTIME_OUTBOUNDS_CONFIGURED:-0}"
    routes_configured="${ZAPRET2_RUNTIME_ROUTES_CONFIGURED:-0}"

    if [ "${running_process_count:-0}" -gt "${expected_process_count:-0}" ] ||
        [ "$queue_overlap" -eq 1 ]; then
        conflict=1
    fi

    if [ "$configured" -eq 1 ] &&
        [ "$provider_available" -eq 1 ] &&
        [ "$conflict" -eq 0 ] &&
        [ "$outbounds_configured" -eq 1 ] &&
        [ "$routes_configured" -eq 1 ] &&
        [ "${expected_process_count:-0}" -gt 0 ] &&
        [ "${running_process_count:-0}" -eq "${expected_process_count:-0}" ]; then
        ready=1
    fi

    if [ "$configured" -eq 1 ] && [ "$provider_available" -eq 0 ]; then
        status_message="action=zapret2 is configured, but zapret2 provider is not available at $ZAPRET2_PROVIDER_NFQWS2_BIN"
    elif [ "$queue_overlap" -eq 1 ]; then
        status_message="external NFQUEUE rules overlap with the Podkop Plus zapret2 range $ZAPRET2_QUEUE_BASE-$queue_range_end"
    elif [ "${running_process_count:-0}" -gt "${expected_process_count:-0}" ] ||
        [ "${supervisor_process_count:-0}" -gt "${expected_process_count:-0}" ]; then
        status_message="unexpected Podkop Plus-managed nfqws2 processes are running without matching action=zapret2 rules"
    elif [ "$configured" -eq 1 ] && [ "$ready" -eq 0 ]; then
        status_message="action=zapret2 is configured, but the Podkop Plus-managed nfqws2 runtime is not ready"
    elif [ "$standalone_conflict" -eq 1 ]; then
        status_message="standalone zapret2 is active together with Podkop Plus action=zapret2; queues are separate, but packet-level policy overlap is possible"
    elif [ "$configured" -eq 0 ] && [ "$provider_available" -eq 0 ] && [ "$package_installed" -eq 1 ]; then
        status_message="zapret2 package is installed, but the provider binary is not available at $ZAPRET2_PROVIDER_NFQWS2_BIN"
    elif [ "$configured" -eq 0 ] && [ "$provider_available" -eq 0 ]; then
        status_message="zapret2 provider is not installed; action=zapret2 is unavailable"
    else
        status_message="zapret2 provider status is normal"
    fi

    provider_status_ucode zapret2-status \
        "$installed" \
        "$package_installed" \
        "$provider_available" \
        "$ZAPRET2_PROVIDER_NFQWS2_BIN" \
        "$files_available" \
        "$ipset_available" \
        "$version" \
        "$configured" \
        "${enabled_rule_count:-0}" \
        "${expected_process_count:-0}" \
        "${running_process_count:-0}" \
        "${supervisor_process_count:-0}" \
        "$standalone_service_enabled" \
        "$standalone_service_running" \
        "$standalone_config_present" \
        "$standalone_conflict" \
        "$luci_app_installed" \
        "$ZAPRET2_QUEUE_BASE" \
        "$queue_range_end" \
        "$queue_overlap" \
        "$ready" \
        "$conflict" \
        "$outbounds_configured" \
        "$routes_configured" \
        "$status_message"
}

check_zapret2_runtime_json() {
    local installed=0 package_installed=0

    if is_zapret2_provider_available; then
        installed=1
    fi

    if zapret2_package_installed; then
        package_installed=1
    fi

    provider_status_ucode zapret2-check "$installed" "$package_installed" "$ZAPRET2_PROVIDER_NFQWS2_BIN"
}

_create_zapret2_nft_rule_handler() {
    local section="$1"
    local index mark_hex queue_number

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret2" ] || return 0

    index="$(get_zapret2_rule_index "$section")"
    mark_hex="$(get_zapret2_rule_mark_hex "$index")"
    queue_number="$(get_zapret2_rule_queue_number "$index")"

    nft add rule inet "$NFT_TABLE_NAME" mangle_output meta mark "$mark_hex" meta l4proto tcp \
        counter queue num "$queue_number" bypass
    nft add rule inet "$NFT_TABLE_NAME" mangle_output meta mark "$mark_hex" meta l4proto udp \
        counter queue num "$queue_number" bypass
}

create_zapret2_nft_rules() {
    has_enabled_zapret2_rules || return 0
    is_zapret2_installed || return 0

    nft add rule inet "$NFT_TABLE_NAME" mangle_output meta mark \& "$ZAPRET2_DESYNC_MARK" == "$ZAPRET2_DESYNC_MARK" return
    nft add rule inet "$NFT_TABLE_NAME" mangle_output meta mark \& "$ZAPRET2_DESYNC_MARK_POSTNAT" == "$ZAPRET2_DESYNC_MARK_POSTNAT" return
    config_foreach _create_zapret2_nft_rule_handler "section"
}

stop_zapret2_pidfile_process() {
    local pidfile="$1"
    local pid

    [ -f "$pidfile" ] || return 0
    pid="$(cat "$pidfile" 2>/dev/null)"
    [ -n "$pid" ] || return 0
    kill "$pid" 2>/dev/null || true
}

kill_zapret2_pidfile_process() {
    local pidfile="$1"
    local pid

    [ -f "$pidfile" ] || return 0
    pid="$(cat "$pidfile" 2>/dev/null)"
    [ -n "$pid" ] || return 0
    kill -0 "$pid" 2>/dev/null || return 0
    kill -9 "$pid" 2>/dev/null || true
}

stop_zapret2_runtime() {
    local pidfile

    if [ -d "$ZAPRET2_PID_DIR" ]; then
        for pidfile in "$ZAPRET2_PID_DIR"/*.pid; do
            stop_zapret2_pidfile_process "$pidfile"
        done
    fi

    if [ -d "$ZAPRET2_CHILD_PID_DIR" ]; then
        for pidfile in "$ZAPRET2_CHILD_PID_DIR"/*.pid; do
            stop_zapret2_pidfile_process "$pidfile"
        done
    fi

    sleep 1

    if [ -d "$ZAPRET2_PID_DIR" ]; then
        for pidfile in "$ZAPRET2_PID_DIR"/*.pid; do
            kill_zapret2_pidfile_process "$pidfile"
        done
    fi

    if [ -d "$ZAPRET2_CHILD_PID_DIR" ]; then
        for pidfile in "$ZAPRET2_CHILD_PID_DIR"/*.pid; do
            kill_zapret2_pidfile_process "$pidfile"
        done
    fi

    rm -rf "$ZAPRET2_PID_DIR" "$ZAPRET2_CHILD_PID_DIR" "$ZAPRET2_LOG_DIR"
}

run_zapret2_nfqws2_supervisor() {
    local section="$1"
    local queue_number="$2"
    local expanded_opt="$3"
    local child_pidfile="$4"
    local child_pid="" old_ifs rc

    trap 'rm -f "$child_pidfile"; [ -n "$child_pid" ] && kill "$child_pid" 2>/dev/null; [ -n "$child_pid" ] && wait "$child_pid" 2>/dev/null; exit 0' TERM INT

    while :; do
        if [ ! -x "$ZAPRET2_NFQWS2_BIN" ]; then
            printf '%s Provider %s is not executable; retrying in %s seconds\n' \
                "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$ZAPRET2_NFQWS2_BIN" "$ZAPRET2_NFQWS2_RESPAWN_DELAY"
            sleep "$ZAPRET2_NFQWS2_RESPAWN_DELAY" &
            child_pid="$!"
            wait "$child_pid"
            child_pid=""
            continue
        fi

        set -f
        old_ifs="$IFS"
        IFS=' '
        set -- $expanded_opt
        IFS="$old_ifs"

        "$ZAPRET2_NFQWS2_BIN" --qnum="$queue_number" $(get_zapret2_base_args) "$@" &
        child_pid="$!"
        echo "$child_pid" > "$child_pidfile"
        wait "$child_pid"
        rc="$?"
        rm -f "$child_pidfile"
        child_pid=""
        set +f

        printf '%s nfqws2 for rule %s exited with code %s; respawning in %s seconds\n' \
            "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$section" "$rc" "$ZAPRET2_NFQWS2_RESPAWN_DELAY"
        sleep "$ZAPRET2_NFQWS2_RESPAWN_DELAY" &
        child_pid="$!"
        wait "$child_pid"
        child_pid=""
    done
}

_start_zapret2_runtime_handler() {
    local section="$1"
    local index queue_number mark_hex raw_opt expanded_opt pidfile child_pidfile logfile pid child_pid

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret2" ] || return 0

    index="$(get_zapret2_rule_index "$section")"
    queue_number="$(get_zapret2_rule_queue_number "$index")"
    mark_hex="$(get_zapret2_rule_mark_hex "$index")"
    raw_opt="$(get_rule_nfqws2_opt "$section")"
    expanded_opt="$(expand_zapret2_nfqws2_opt "$raw_opt" "$section")"
    pidfile="$ZAPRET2_PID_DIR/$section.pid"
    child_pidfile="$ZAPRET2_CHILD_PID_DIR/$section.pid"
    logfile="$ZAPRET2_LOG_DIR/$section.log"

    log "Starting nfqws2 for rule '$section' on queue $queue_number with mark $mark_hex"
    (close_inherited_service_lock_fd; run_zapret2_nfqws2_supervisor "$section" "$queue_number" "$expanded_opt" "$child_pidfile") >>"$logfile" 2>&1 &
    pid="$!"
    echo "$pid" > "$pidfile"
    sleep 1

    if ! kill -0 "$pid" 2>/dev/null; then
        log "nfqws2 failed to start for rule '$section'. Check $logfile. Aborted." "fatal"
        exit 1
    fi

    child_pid="$(cat "$child_pidfile" 2>/dev/null)"
    if [ -z "$child_pid" ] || ! kill -0 "$child_pid" 2>/dev/null; then
        log "nfqws2 supervisor started for rule '$section', but nfqws2 is not running yet. Check $logfile." "warn"
    fi
}

start_zapret2_runtime() {
    stop_zapret2_runtime

    has_enabled_zapret2_rules || return 0
    is_zapret2_provider_available || return 0

    check_zapret2_requirements
    mkdir -p "$ZAPRET2_PID_DIR" "$ZAPRET2_CHILD_PID_DIR" "$ZAPRET2_LOG_DIR"
    config_foreach _start_zapret2_runtime_handler "section"
}
