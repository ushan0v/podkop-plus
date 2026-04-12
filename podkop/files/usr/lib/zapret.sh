has_enabled_zapret_rules() {
    local count

    count="$(get_zapret_rule_count)"
    [ "${count:-0}" -gt 0 ]
}

_count_zapret_rule_handler() {
    local section="$1"

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret" ] || return 0

    ZAPRET_RULE_COUNT=$((ZAPRET_RULE_COUNT + 1))
}

get_zapret_rule_count() {
    ZAPRET_RULE_COUNT=0
    config_foreach _count_zapret_rule_handler "rule"
    echo "$ZAPRET_RULE_COUNT"
}

_find_zapret_rule_index_handler() {
    local section="$1"
    local target_section="$2"

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret" ] || return 0

    ZAPRET_RULE_INDEX_WALK=$((ZAPRET_RULE_INDEX_WALK + 1))
    if [ "$section" = "$target_section" ]; then
        ZAPRET_RULE_INDEX_RESULT="$ZAPRET_RULE_INDEX_WALK"
    fi
}

get_zapret_rule_index() {
    local section="$1"

    ZAPRET_RULE_INDEX_WALK=0
    ZAPRET_RULE_INDEX_RESULT=0
    config_foreach _find_zapret_rule_index_handler "rule" "$section"

    echo "$ZAPRET_RULE_INDEX_RESULT"
}

format_mark_hex() {
    local mark_value="$1"

    printf '0x%08x\n' "$mark_value"
}

get_zapret_rule_mark_value() {
    local index="$1"

    echo $((ZAPRET_ROUTE_MARK_BASE + index))
}

get_zapret_rule_mark_hex() {
    local index="$1"

    format_mark_hex "$(get_zapret_rule_mark_value "$index")"
}

get_zapret_rule_queue_number() {
    local index="$1"

    echo $((ZAPRET_QUEUE_BASE + index - 1))
}

get_rule_nfqws_opt() {
    local section="$1"
    local nfqws_opt

    config_get nfqws_opt "$section" "nfqws_opt"
    if [ -n "$nfqws_opt" ]; then
        normalize_nfqws_strategy_whitespace "$nfqws_opt"
    else
        normalize_nfqws_strategy_whitespace "$ZAPRET_DEFAULT_NFQWS_OPT"
    fi
}

normalize_nfqws_strategy_whitespace() {
    printf '%s' "$1" | tr '\t\r\n' '   ' | tr -s ' ' | sed 's/^ //; s/ $//'
}

nfqws_option_argument_mode() {
    case "$1" in
    --debug | --comment | --synack-split | --ctrack-disable | --ipcache-hostname | \
        --dup-autottl | --dup-autottl6 | --dup-tcp-flags-set | --dup-tcp-flags-unset | \
        --dup-replace | --orig-autottl | --orig-autottl6 | --orig-tcp-flags-set | \
        --orig-tcp-flags-unset | --dpi-desync-autottl | --dpi-desync-autottl6 | \
        --dpi-desync-tcp-flags-set | --dpi-desync-tcp-flags-unset | \
        --dpi-desync-skip-nosni | --dpi-desync-any-protocol)
        echo "optional"
        ;;
    --dry-run | --version | --daemon | --hostcase | --hostnospace | --domcase | \
        --methodeol | --new | --skip | --bind-fix4 | --bind-fix6)
        echo "none"
        ;;
    --qnum | --pidfile | --user | --uid | --wsize | --wssize | --wssize-cutoff | \
        --wssize-forced-cutoff | --ctrack-timeouts | --ipcache-lifetime | \
        --hostspell | --ip-id | --dpi-desync | --dpi-desync-fwmark | --dup | \
        --dup-ttl | --dup-ttl6 | --dup-fooling | --dup-ts-increment | \
        --dup-badseq-increment | --dup-badack-increment | --dup-ip-id | \
        --dup-start | --dup-cutoff | --orig-ttl | --orig-ttl6 | \
        --orig-mod-start | --orig-mod-cutoff | --dpi-desync-ttl | \
        --dpi-desync-ttl6 | --dpi-desync-fooling | --dpi-desync-repeats | \
        --dpi-desync-split-pos | --dpi-desync-split-http-req | \
        --dpi-desync-split-tls | --dpi-desync-split-seqovl | \
        --dpi-desync-split-seqovl-pattern | --dpi-desync-fakedsplit-pattern | \
        --dpi-desync-fakedsplit-mod | --dpi-desync-hostfakesplit-midhost | \
        --dpi-desync-hostfakesplit-mod | --dpi-desync-ipfrag-pos-tcp | \
        --dpi-desync-ipfrag-pos-udp | --dpi-desync-ts-increment | \
        --dpi-desync-badseq-increment | --dpi-desync-badack-increment | \
        --dpi-desync-fake-tcp-mod | --dpi-desync-fake-http | \
        --dpi-desync-fake-tls | --dpi-desync-fake-tls-mod | \
        --dpi-desync-fake-unknown | --dpi-desync-fake-syndata | \
        --dpi-desync-fake-quic | --dpi-desync-fake-wireguard | \
        --dpi-desync-fake-dht | --dpi-desync-fake-discord | \
        --dpi-desync-fake-stun | --dpi-desync-fake-unknown-udp | \
        --dpi-desync-udplen-increment | --dpi-desync-udplen-pattern | \
        --dpi-desync-cutoff | --dpi-desync-start | --hostlist | \
        --hostlist-domains | --hostlist-exclude | --hostlist-exclude-domains | \
        --hostlist-auto | --hostlist-auto-fail-threshold | \
        --hostlist-auto-fail-time | --hostlist-auto-retrans-threshold | \
        --hostlist-auto-debug | --filter-l3 | --filter-tcp | --filter-udp | \
        --filter-l7 | --ipset | --ipset-ip | --ipset-exclude | \
        --ipset-exclude-ip)
        echo "required"
        ;;
    *)
        echo "unknown"
        ;;
    esac
}

clear_nfqws_validation_state() {
    NFQWS_VALIDATE_ERROR=""
    NFQWS_VALIDATE_NEEDLE=""
    NFQWS_VALIDATE_NEEDLES=""
}

append_nfqws_validation_needle() {
    local needle="$1"

    [ -n "$needle" ] || return 0

    case "
$NFQWS_VALIDATE_NEEDLES
" in
    *"
$needle
"*)
        return 0
        ;;
    esac

    if [ -n "$NFQWS_VALIDATE_NEEDLES" ]; then
        NFQWS_VALIDATE_NEEDLES="${NFQWS_VALIDATE_NEEDLES}
$needle"
    else
        NFQWS_VALIDATE_NEEDLES="$needle"
    fi

    [ -n "$NFQWS_VALIDATE_NEEDLE" ] || NFQWS_VALIDATE_NEEDLE="$needle"
}

set_nfqws_validation_failure() {
    NFQWS_VALIDATE_ERROR="$1"
    NFQWS_VALIDATE_NEEDLE=""
    NFQWS_VALIDATE_NEEDLES=""
    shift

    while [ "$#" -gt 0 ]; do
        append_nfqws_validation_needle "$1"
        shift
    done

    return 1
}

get_nfqws_unsupported_token_reason() {
    local token="$1"

    case "$token" in
    "<HOSTLIST>" | "<HOSTLIST_NOAUTO>")
        echo "Podkop Plus does not expand zapret hostlist templates in per-rule strategies because sing-box already selects the resources before NFQUEUE."
        return 0
        ;;
    --hostlist | --hostlist=* | --hostlist-domains | --hostlist-domains=* | \
        --hostlist-exclude | --hostlist-exclude=* | --hostlist-exclude-domains | --hostlist-exclude-domains=* | \
        --hostlist-auto | --hostlist-auto=* | --hostlist-auto-fail-threshold | --hostlist-auto-fail-threshold=* | \
        --hostlist-auto-fail-time | --hostlist-auto-fail-time=* | \
        --hostlist-auto-retrans-threshold | --hostlist-auto-retrans-threshold=* | \
        --hostlist-auto-debug | --hostlist-auto-debug=*)
        echo "Hostname-based selection inside nfqws is incompatible with the Podkop Plus architecture because sing-box already chooses which resources enter action=zapret."
        return 0
        ;;
    --ipset | --ipset=* | --ipset-ip | --ipset-ip=* | --ipset-exclude | --ipset-exclude=* | --ipset-exclude-ip | --ipset-exclude-ip=*)
        echo "IP or CIDR selection inside nfqws is incompatible with the Podkop Plus architecture because sing-box already chooses which resources enter action=zapret."
        return 0
        ;;
    --qnum | --qnum=*)
        echo "The NFQUEUE number is assigned by Podkop Plus per rule and must not be overridden in the strategy."
        return 0
        ;;
    --dpi-desync-fwmark | --dpi-desync-fwmark=*)
        echo "The desync fwmark is managed by Podkop Plus for loop prevention and must not be overridden in the strategy."
        return 0
        ;;
    --daemon)
        echo "Podkop Plus manages the nfqws process lifecycle itself. The strategy must not daemonize nfqws."
        return 0
        ;;
    --dry-run)
        echo "The strategy must launch a working nfqws process. --dry-run exits immediately and is not allowed."
        return 0
        ;;
    --version)
        echo "The strategy must launch a working nfqws process. --version exits immediately and is not allowed."
        return 0
        ;;
    esac

    return 1
}

normalize_nfqws_validation_output() {
    printf '%s\n' "$1" | sed 's/\r$//'
}

extract_nfqws_validation_summary() {
    local output="$1"
    local summary

    summary="$(normalize_nfqws_validation_output "$output" | grep -m1 -E 'unrecognized option:|option requires an argument:|option does not take an argument:|[Ii]nvalid |bad [^ ]|must be |fooling allowed values|incompatible|only one |No such file|not found|cannot |failed to |unable to |should be |Too much splits|out of memory|not supported|value error' | sed 's#^.*/nfqws: ##; s/^nfqws: //')"
    if [ -n "$summary" ]; then
        printf '%s\n' "$summary"
        return 0
    fi

    normalize_nfqws_validation_output "$output" | awk '
        /^github version / { next }
        /^we have [0-9]+ user defined desync profile/ { next }
        /^Running as UID=/ { next }
        /^command line parameters verified$/ { next }
        /^[[:space:]]*$/ { next }
        {
            sub(/^.*\/nfqws:[[:space:]]*/, "", $0)
            sub(/^nfqws:[[:space:]]*/, "", $0)
            print
            exit
        }
    '
}

extract_nfqws_validation_value_hint() {
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

extract_nfqws_validation_option_hint() {
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

collect_nfqws_validation_needles() {
    local summary="$1"
    local option value

    option="$(extract_nfqws_validation_option_hint "$summary")"
    value="$(extract_nfqws_validation_value_hint "$summary")"

    [ -n "$option" ] && printf '%s\n' "$option"
    [ -n "$value" ] && printf '%s\n' "$value"
}

run_nfqws_dry_run_validation() {
    local raw_opt="$1"
    local old_ifs output_file output summary needles rc

    if ! is_zapret_installed; then
        return 0
    fi

    if ! prepare_zapret_runtime; then
        set_nfqws_validation_failure \
            "The Podkop Plus zapret runtime is unavailable. Install the upstream zapret package so $ZAPRET_SOURCE_NFQWS_BIN exists."
        return 1
    fi

    raw_opt="$(expand_zapret_nfqws_opt "$raw_opt")"
    raw_opt="$(normalize_nfqws_strategy_whitespace "$raw_opt")"
    [ -n "$raw_opt" ] || return 0

    output_file="$(mktemp)"

    set -f
    old_ifs="$IFS"
    IFS=' '
    set -- $raw_opt
    IFS="$old_ifs"

    "$ZAPRET_NFQWS_BIN" --dry-run --qnum="$ZAPRET_QUEUE_BASE" --dpi-desync-fwmark="$ZAPRET_DESYNC_MARK" "$@" >"$output_file" 2>&1
    rc=$?
    output="$(cat "$output_file")"
    rm -f "$output_file"
    set +f

    [ "$rc" -eq 0 ] && return 0

    summary="$(extract_nfqws_validation_summary "$output")"
    [ -n "$summary" ] || summary="nfqws rejected the strategy during syntax validation."

    needles="$(collect_nfqws_validation_needles "$summary")"
    if [ -n "$needles" ]; then
        # shellcheck disable=SC2086
        set_nfqws_validation_failure "nfqws syntax check failed: $summary" $needles
    else
        set_nfqws_validation_failure "nfqws syntax check failed: $summary"
    fi
}

check_nfqws_strategy() {
    local raw_opt="$1"
    local old_ifs token base_token mode reason display next_token token_count=0

    clear_nfqws_validation_state
    raw_opt="$(normalize_nfqws_strategy_whitespace "$raw_opt")"

    if [ "$raw_opt" = "$ZAPRET_LEGACY_DEFAULT_NFQWS_OPT" ]; then
        return 0
    fi

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
                set_nfqws_validation_failure \
                    "Unsupported NFQWS token '$token': External nfqws config files bypass Podkop Plus validation and queue management." \
                    "$token"
                return 1
                ;;
            esac
        fi

        if reason="$(get_nfqws_unsupported_token_reason "$token")"; then
            display="$token"
            mode="$(nfqws_option_argument_mode "$base_token")"
            if [ "$base_token" = "$token" ] && [ "$mode" = "required" ] && [ "$#" -gt 1 ] && [ "${next_token#--}" = "$next_token" ]; then
                display="$display $next_token"
                set_nfqws_validation_failure "Unsupported NFQWS token '$display': $reason" "$base_token" "$next_token"
                return 1
            fi

            set_nfqws_validation_failure "Unsupported NFQWS token '$display': $reason" "$base_token"
            return 1
        fi

        case "$token" in
        --*)
            mode="$(nfqws_option_argument_mode "$base_token")"
            case "$mode" in
            unknown)
                set_nfqws_validation_failure \
                    "Unknown NFQWS flag '$token'." \
                    "$base_token"
                return 1
                ;;
            none)
                if [ "$base_token" != "$token" ]; then
                    set_nfqws_validation_failure \
                        "NFQWS flag '$base_token' does not accept a value." \
                        "$base_token"
                    return 1
                fi
                shift
                token_count=$((token_count + 1))
                ;;
            optional)
                if [ "$base_token" = "$token" ] && [ "$#" -gt 1 ] && [ "${next_token#--}" = "$next_token" ]; then
                    set_nfqws_validation_failure \
                        "Optional value for '$base_token' must be attached as '$base_token=value'. Separate tokens are ignored by nfqws here." \
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
                    set_nfqws_validation_failure \
                        "NFQWS option '$base_token' requires a value." \
                        "$base_token"
                    return 1
                fi

                shift 2
                token_count=$((token_count + 2))
                ;;
            esac
            ;;
        *)
            set_nfqws_validation_failure \
                "Unexpected standalone NFQWS token '$token'. Use explicit flags such as --name or --name=value." \
                "$token"
            return 1
            ;;
        esac
    done

    set +f

    run_nfqws_dry_run_validation "$raw_opt"
}

validate_nfqws_strategy() {
    local raw_opt="$1"
    local context="$2"

    if ! check_nfqws_strategy "$raw_opt"; then
        log "$context uses invalid NFQWS strategy: $NFQWS_VALIDATE_ERROR Aborted." "fatal"
        exit 1
    fi
}

validate_rule_nfqws_opt() {
    local section="$1"
    local raw_opt

    raw_opt="$(get_rule_nfqws_opt "$section")"
    validate_nfqws_strategy "$raw_opt" "Zapret rule '$section'"
}

_find_zapret_optional_file() {
    local base_path="$1"

    if [ -f "${base_path}.gz" ]; then
        echo "${base_path}.gz"
        return 0
    fi

    if [ -f "$base_path" ]; then
        echo "$base_path"
        return 0
    fi

    echo ""
}

build_zapret_hostlist_params() {
    echo ""
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

prepare_zapret_runtime_dir() {
    local source_dir="$1"
    local target_dir="$2"

    [ -d "$source_dir" ] || return 0

    mkdir -p "$target_dir" || return 1
    cp -R "$source_dir"/. "$target_dir"/ >/dev/null 2>&1 || return 1
}

prepare_zapret_runtime() {
    mkdir -p "$ZAPRET_STATE_DIR" "$ZAPRET_PID_DIR" "$ZAPRET_LOG_DIR" "$ZAPRET_HOSTLIST_DIR" || return 1

    [ -x "$ZAPRET_SOURCE_NFQWS_BIN" ] || return 1

    mkdir -p "$ZAPRET_RUNTIME_BASE_DIR/nfq" "$ZAPRET_RUNTIME_FILES_DIR" "$ZAPRET_RUNTIME_IPSET_DIR" || return 1
    cp -f "$ZAPRET_SOURCE_NFQWS_BIN" "$ZAPRET_NFQWS_BIN" >/dev/null 2>&1 || return 1
    chmod 0755 "$ZAPRET_NFQWS_BIN" >/dev/null 2>&1 || true

    prepare_zapret_runtime_dir "$ZAPRET_SOURCE_FILES_DIR" "$ZAPRET_RUNTIME_FILES_DIR" || return 1
    prepare_zapret_runtime_dir "$ZAPRET_SOURCE_IPSET_DIR" "$ZAPRET_RUNTIME_IPSET_DIR" || return 1

    return 0
}

is_zapret_installed() {
    [ -x "$ZAPRET_SOURCE_NFQWS_BIN" ]
}

rewrite_zapret_runtime_paths() {
    local source_path runtime_path

    source_path="$(escape_sed_replacement "$ZAPRET_SOURCE_BASE_DIR")"
    runtime_path="$(escape_sed_replacement "$ZAPRET_RUNTIME_BASE_DIR")"

    printf '%s' "$1" | sed "s#${source_path}#${runtime_path}#g"
}

expand_zapret_nfqws_opt() {
    rewrite_zapret_runtime_paths "$1"
}

get_zapret_rule_hostlist_path() {
    local section="$1"

    echo "$ZAPRET_HOSTLIST_DIR/$section.hostlist"
}

get_zapret_community_hostlist_url() {
    local reference="$1"

    case "$reference" in
    russia_inside)
        echo "$GITHUB_RAW_URL/Russia/inside-raw.lst"
        ;;
    russia_outside)
        echo "$GITHUB_RAW_URL/Russia/outside-raw.lst"
        ;;
    ukraine_inside)
        echo "$GITHUB_RAW_URL/Ukraine/inside-raw.lst"
        ;;
    *)
        echo "$GITHUB_RAW_URL/Services/$reference.lst"
        ;;
    esac
}

normalize_zapret_hostlist_line() {
    local line="$1"
    local normalized

    line="$(printf '%s' "$line" | sed 's/\r$//; s/#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$line" ] || return 1

    normalized="${line#.}"
    is_domain_suffix "$normalized" || return 1

    printf '%s\n' "$normalized"
}

append_zapret_hostlist_line() {
    local line="$1"
    local output_file="$2"
    local normalized

    normalized="$(normalize_zapret_hostlist_line "$line")" || return 0
    printf '%s\n' "$normalized" >>"$output_file"
}

_append_zapret_uci_hostlist_item_handler() {
    local value="$1"
    local output_file="$2"

    append_zapret_hostlist_line "$value" "$output_file"
}

append_zapret_hostlist_from_plain_file() {
    local input_file="$1"
    local output_file="$2"
    local line

    [ -f "$input_file" ] || return 0

    while IFS= read -r line; do
        append_zapret_hostlist_line "$line" "$output_file"
    done <"$input_file"
}

append_zapret_hostlist_from_json_ruleset() {
    local json_file="$1"
    local output_file="$2"
    local tmpfile

    [ -f "$json_file" ] || return 0

    tmpfile="$(mktemp)"
    if ! extract_domains_from_json_ruleset_to_file "$json_file" "$tmpfile"; then
        rm -f "$tmpfile"
        return 1
    fi

    append_zapret_hostlist_from_plain_file "$tmpfile" "$output_file"
    rm -f "$tmpfile"
}

append_zapret_hostlist_from_url() {
    local url="$1"
    local output_file="$2"
    local http_proxy_address tmpfile json_tmpfile extension

    http_proxy_address="$(get_service_proxy_address)"
    tmpfile="$(mktemp)"

    if ! download_to_file "$url" "$tmpfile" "$http_proxy_address" || [ ! -s "$tmpfile" ]; then
        log "Failed to download Zapret hostlist source: $url" "warn"
        rm -f "$tmpfile"
        return 0
    fi

    convert_crlf_to_lf "$tmpfile"
    extension="$(url_get_file_extension "$url")"

    case "$extension" in
    srs)
        json_tmpfile="$(mktemp)"
        if decompile_binary_ruleset "$tmpfile" "$json_tmpfile"; then
            append_zapret_hostlist_from_json_ruleset "$json_tmpfile" "$output_file"
        else
            log "Failed to decompile Zapret hostlist ruleset: $url" "warn"
        fi
        rm -f "$json_tmpfile"
        ;;
    json)
        append_zapret_hostlist_from_json_ruleset "$tmpfile" "$output_file"
        ;;
    *)
        append_zapret_hostlist_from_plain_file "$tmpfile" "$output_file"
        ;;
    esac

    rm -f "$tmpfile"
}

append_zapret_hostlist_from_reference() {
    local reference="$1"
    local output_file="$2"
    local community_url json_tmpfile

    if printf '%s\n' "$COMMUNITY_SERVICES" | tr ' ' '\n' | grep -Fxq "$reference"; then
        community_url="$(get_zapret_community_hostlist_url "$reference")"
        append_zapret_hostlist_from_url "$community_url" "$output_file"
        return 0
    fi

    case "$reference" in
    http://* | https://*)
        append_zapret_hostlist_from_url "$reference" "$output_file"
        ;;
    *.srs)
        if [ -f "$reference" ]; then
            json_tmpfile="$(mktemp)"
            if decompile_binary_ruleset "$reference" "$json_tmpfile"; then
                append_zapret_hostlist_from_json_ruleset "$json_tmpfile" "$output_file"
            fi
            rm -f "$json_tmpfile"
        fi
        ;;
    *.json)
        append_zapret_hostlist_from_json_ruleset "$reference" "$output_file"
        ;;
    *)
        append_zapret_hostlist_from_plain_file "$reference" "$output_file"
        ;;
    esac
}

_append_zapret_hostlist_reference_handler() {
    local reference="$1"
    local output_file="$2"

    append_zapret_hostlist_from_reference "$reference" "$output_file"
}

append_zapret_hostlist_from_inline_domains() {
    local items="$1"
    local output_file="$2"
    local item

    printf '%s' "$items" | tr ', \t' '\n\n\n' | while IFS= read -r item; do
        append_zapret_hostlist_line "$item" "$output_file"
    done
}

build_generated_zapret_hostlist() {
    local section="$1"
    local hostlist_path tmpfile user_domain_list_type items

    hostlist_path="$(get_zapret_rule_hostlist_path "$section")"
    tmpfile="$(mktemp)"

    : >"$hostlist_path"

    config_list_foreach "$section" "domain" _append_zapret_uci_hostlist_item_handler "$tmpfile"
    config_list_foreach "$section" "domain_suffix" _append_zapret_uci_hostlist_item_handler "$tmpfile"
    config_list_foreach "$section" "community_lists" _append_zapret_hostlist_reference_handler "$tmpfile"
    config_list_foreach "$section" "local_domain_lists" _append_zapret_hostlist_reference_handler "$tmpfile"
    config_list_foreach "$section" "remote_domain_lists" _append_zapret_hostlist_reference_handler "$tmpfile"
    config_list_foreach "$section" "rule_set" _append_zapret_hostlist_reference_handler "$tmpfile"
    config_list_foreach "$section" "domain_ip_lists" _append_zapret_hostlist_reference_handler "$tmpfile"

    config_get user_domain_list_type "$section" "user_domain_list_type" "disabled"
    case "$user_domain_list_type" in
    dynamic) config_get items "$section" "user_domains" ;;
    text) config_get items "$section" "user_domains_text" ;;
    *) items="" ;;
    esac
    [ -n "$items" ] && append_zapret_hostlist_from_inline_domains "$items" "$tmpfile"

    if [ -s "$tmpfile" ]; then
        sort -u "$tmpfile" >"$hostlist_path"
    fi

    rm -f "$tmpfile"
    echo "$hostlist_path"
}

check_zapret_requirements() {
    has_enabled_zapret_rules || return 0

    if ! is_zapret_installed; then
        log "Zapret package is not installed. Rules with action 'zapret' will be skipped until zapret is installed." "error"
        return 0
    fi

    if ! prepare_zapret_runtime; then
        log "Failed to prepare the Podkop Plus zapret runtime in $ZAPRET_RUNTIME_BASE_DIR. Aborted." "fatal"
        exit 1
    fi
}

get_zapret_package_version() {
    local version=""

    if command -v apk >/dev/null 2>&1 && apk info -e zapret >/dev/null 2>&1; then
        version="$(apk info -v zapret 2>/dev/null | awk 'NR == 1 { sub(/^zapret-/, "", $0); print; exit }')"
    elif command -v opkg >/dev/null 2>&1; then
        version="$(opkg list-installed 2>/dev/null | awk '$1 == "zapret" { print $3; exit }')"
    fi

    if [ -z "$version" ] && [ -x "$ZAPRET_SOURCE_NFQWS_BIN" ]; then
        version="$("$ZAPRET_SOURCE_NFQWS_BIN" --version 2>/dev/null | sed -n '1s/^.*version[[:space:]]*//p' | awk '{ print $1; exit }')"
    fi

    echo "$version"
}

is_zapret_standalone_service_enabled() {
    [ -x /etc/init.d/zapret ] || return 1
    /etc/init.d/zapret enabled >/dev/null 2>&1
}

is_zapret_standalone_service_running() {
    [ -x /etc/init.d/zapret ] || return 1
    /etc/init.d/zapret status >/dev/null 2>&1
}

zapret_standalone_uci_config_present() {
    [ -f /etc/config/zapret ] || return 1
    uci -q get zapret.config >/dev/null 2>&1
}

zapret_standalone_defaults_active() {
    local run_on_boot nfqws_enable

    if is_zapret_standalone_service_running || is_zapret_standalone_service_enabled; then
        return 0
    fi

    if ! zapret_standalone_uci_config_present; then
        return 1
    fi

    run_on_boot="$(uci -q get zapret.config.run_on_boot)"
    nfqws_enable="$(uci -q get zapret.config.NFQWS_ENABLE)"

    [ "${run_on_boot:-0}" != "0" ] || [ "${nfqws_enable:-0}" != "0" ]
}

sync_zapret_standalone_config() {
    if [ -x "$ZAPRET_SOURCE_BASE_DIR/sync_config.sh" ]; then
        "$ZAPRET_SOURCE_BASE_DIR/sync_config.sh" >/dev/null 2>&1
        return $?
    fi

    if [ -x "$ZAPRET_SOURCE_BASE_DIR/renew-cfg.sh" ]; then
        "$ZAPRET_SOURCE_BASE_DIR/renew-cfg.sh" sync >/dev/null 2>&1
        return $?
    fi

    return 0
}

neutralize_zapret_standalone_defaults() {
    local config_dirty=0
    local run_on_boot nfqws_enable

    # remittor/zapret-openwrt enables and starts the main standalone profile
    # in postinst. Podkop Plus only needs the package payload on fresh install,
    # so make that default profile dormant until the user explicitly enables it.
    if zapret_standalone_uci_config_present; then
        run_on_boot="$(uci -q get zapret.config.run_on_boot)"
        if [ "${run_on_boot:-0}" != "0" ]; then
            uci -q set zapret.config.run_on_boot='0'
            config_dirty=1
        fi

        nfqws_enable="$(uci -q get zapret.config.NFQWS_ENABLE)"
        if [ "${nfqws_enable:-0}" != "0" ]; then
            uci -q set zapret.config.NFQWS_ENABLE='0'
            config_dirty=1
        fi

        if [ "$config_dirty" -eq 1 ]; then
            log "Neutralizing the default standalone zapret NFQWS profile installed alongside Podkop Plus"
            uci commit zapret >/dev/null 2>&1 || {
                log "Failed to commit /etc/config/zapret while neutralizing the default standalone zapret profile. Aborted." "fatal"
                return 1
            }

            sync_zapret_standalone_config || {
                log "Failed to synchronize /opt/zapret/config after updating /etc/config/zapret. Aborted." "fatal"
                return 1
            }
        fi
    fi

    if is_zapret_standalone_service_running; then
        log "Stopping the default standalone zapret service installed alongside Podkop Plus"
        /etc/init.d/zapret stop >/dev/null 2>&1 || true
    fi

    if is_zapret_standalone_service_enabled; then
        log "Disabling the default standalone zapret autostart installed alongside Podkop Plus"
        /etc/init.d/zapret disable >/dev/null 2>&1 || true
    fi

    if is_zapret_standalone_service_running || is_zapret_standalone_service_enabled; then
        log "The standalone zapret service is still active after Podkop Plus tried to neutralize its default auto-started profile. Aborted." "fatal"
        return 1
    fi

    if zapret_standalone_uci_config_present; then
        run_on_boot="$(uci -q get zapret.config.run_on_boot)"
        nfqws_enable="$(uci -q get zapret.config.NFQWS_ENABLE)"

        if [ "${run_on_boot:-0}" != "0" ] || [ "${nfqws_enable:-0}" != "0" ]; then
            log "The default standalone zapret profile remains active in /etc/config/zapret after Podkop Plus tried to neutralize it. Aborted." "fatal"
            return 1
        fi
    fi

    return 0
}

ensure_zapret_standalone_conflict_resolved() {
    return 0
}

get_zapret_nfqws_process_count() {
    local count=0 pidfile pid

    [ -d "$ZAPRET_PID_DIR" ] || {
        echo 0
        return 0
    }

    for pidfile in "$ZAPRET_PID_DIR"/*.pid; do
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

zapret_rule_outbound_present() {
    local section="$1"
    local routing_mark="$2"
    local outbound_tag

    [ -f "$ZAPRET_SINGBOX_CONFIG_PATH" ] || return 1

    outbound_tag="$(get_outbound_tag_by_section "$section")"

    jq -e \
        --arg tag "$outbound_tag" \
        --argjson routing_mark "$routing_mark" \
        '.outbounds[]? |
            select(.type == "direct" and .tag == $tag and (.routing_mark // empty) == $routing_mark)' \
        "$ZAPRET_SINGBOX_CONFIG_PATH" >/dev/null 2>&1
}

zapret_rule_route_rule_present() {
    local section="$1"
    local outbound_tag

    [ -f "$ZAPRET_SINGBOX_CONFIG_PATH" ] || return 1

    outbound_tag="$(get_outbound_tag_by_section "$section")"

    jq -e \
        --arg inbound "$SB_TPROXY_INBOUND_TAG" \
        --arg outbound "$outbound_tag" \
        '.route.rules[]? |
            select(.action == "route" and .inbound == $inbound and .outbound == $outbound)' \
        "$ZAPRET_SINGBOX_CONFIG_PATH" >/dev/null 2>&1
}

_collect_zapret_runtime_status_handler() {
    local section="$1"
    local index mark_value

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret" ] || return 0

    ZAPRET_RUNTIME_RULES_CONFIGURED=1
    index="$(get_zapret_rule_index "$section")"
    mark_value="$(get_zapret_rule_mark_value "$index")"

    if ! zapret_rule_outbound_present "$section" "$mark_value"; then
        ZAPRET_RUNTIME_OUTBOUNDS_CONFIGURED=0
    fi

    if ! zapret_rule_route_rule_present "$section"; then
        ZAPRET_RUNTIME_ROUTES_CONFIGURED=0
    fi
}

collect_zapret_runtime_status() {
    local sing_box_config_path

    ZAPRET_RUNTIME_RULES_CONFIGURED=0
    ZAPRET_RUNTIME_OUTBOUNDS_CONFIGURED=1
    ZAPRET_RUNTIME_ROUTES_CONFIGURED=1

    config_get sing_box_config_path "settings" "config_path"
    ZAPRET_SINGBOX_CONFIG_PATH="$sing_box_config_path"
    config_foreach _collect_zapret_runtime_status_handler "rule"

    if [ "$ZAPRET_RUNTIME_RULES_CONFIGURED" -eq 0 ]; then
        ZAPRET_RUNTIME_OUTBOUNDS_CONFIGURED=0
        ZAPRET_RUNTIME_ROUTES_CONFIGURED=0
    fi
}

get_zapret_status_json() {
    local installed=0 configured=0 standalone_service_enabled=0 standalone_service_running=0 ready=0 conflict=0
    local enabled_rule_count expected_process_count running_process_count version
    local outbounds_configured=0 routes_configured=0

    enabled_rule_count="$(get_zapret_rule_count)"
    expected_process_count="${enabled_rule_count:-0}"
    running_process_count="$(get_zapret_nfqws_process_count)"
    version="not installed"

    if [ "${enabled_rule_count:-0}" -gt 0 ]; then
        configured=1
    fi

    if [ -x "$ZAPRET_SOURCE_NFQWS_BIN" ]; then
        installed=1
        version="$(get_zapret_package_version)"
        [ -n "$version" ] || version="unknown"
    fi

    if is_zapret_standalone_service_enabled; then
        standalone_service_enabled=1
    fi

    if is_zapret_standalone_service_running; then
        standalone_service_running=1
    fi

    collect_zapret_runtime_status
    outbounds_configured="${ZAPRET_RUNTIME_OUTBOUNDS_CONFIGURED:-0}"
    routes_configured="${ZAPRET_RUNTIME_ROUTES_CONFIGURED:-0}"

    if [ "${running_process_count:-0}" -gt "${expected_process_count:-0}" ]; then
        conflict=1
    fi

    if [ "$configured" -eq 1 ] &&
        [ "$installed" -eq 1 ] &&
        [ "$conflict" -eq 0 ] &&
        [ "$outbounds_configured" -eq 1 ] &&
        [ "$routes_configured" -eq 1 ] &&
        [ "${expected_process_count:-0}" -gt 0 ] &&
        [ "${running_process_count:-0}" -eq "${expected_process_count:-0}" ]; then
        ready=1
    fi

    jq -cn \
        --arg version "$version" \
        --argjson installed "$installed" \
        --argjson configured "$configured" \
        --argjson enabled_rule_count "${enabled_rule_count:-0}" \
        --argjson expected_process_count "${expected_process_count:-0}" \
        --argjson running_process_count "${running_process_count:-0}" \
        --argjson standalone_service_enabled "$standalone_service_enabled" \
        --argjson standalone_service_running "$standalone_service_running" \
        --argjson ready "$ready" \
        --argjson conflict "$conflict" \
        '{
            installed: $installed,
            version: $version,
            configured: $configured,
            enabled_rule_count: $enabled_rule_count,
            expected_process_count: $expected_process_count,
            running_process_count: $running_process_count,
            standalone_service_enabled: $standalone_service_enabled,
            standalone_service_running: $standalone_service_running,
            ready: $ready,
            conflict: $conflict
        }'
}

check_zapret_runtime_json() {
    local installed=0

    if [ -x "$ZAPRET_SOURCE_NFQWS_BIN" ]; then
        installed=1
    fi

    jq -cn \
        --argjson zapret_installed "$installed" \
        '{
            zapret_installed: $zapret_installed
        }'
}

_create_zapret_nft_rule_handler() {
    local section="$1"
    local index mark_hex queue_number

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret" ] || return 0

    index="$(get_zapret_rule_index "$section")"
    mark_hex="$(get_zapret_rule_mark_hex "$index")"
    queue_number="$(get_zapret_rule_queue_number "$index")"

    nft add rule inet "$NFT_TABLE_NAME" mangle_output meta mark "$mark_hex" meta l4proto tcp \
        counter queue num "$queue_number" bypass
    nft add rule inet "$NFT_TABLE_NAME" mangle_output meta mark "$mark_hex" meta l4proto udp \
        counter queue num "$queue_number" bypass
}

create_zapret_nft_rules() {
    has_enabled_zapret_rules || return 0
    is_zapret_installed || return 0

    nft add rule inet "$NFT_TABLE_NAME" mangle_output meta mark \& "$ZAPRET_DESYNC_MARK" == "$ZAPRET_DESYNC_MARK" return
    nft add rule inet "$NFT_TABLE_NAME" mangle_output meta mark \& "$ZAPRET_DESYNC_MARK_POSTNAT" == "$ZAPRET_DESYNC_MARK_POSTNAT" return
    config_foreach _create_zapret_nft_rule_handler "rule"
}

stop_zapret_runtime() {
    local pidfile pid

    if [ -d "$ZAPRET_PID_DIR" ]; then
        for pidfile in "$ZAPRET_PID_DIR"/*.pid; do
            [ -f "$pidfile" ] || continue
            pid="$(cat "$pidfile" 2>/dev/null)"
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
            fi
        done
    fi

    rm -rf "$ZAPRET_PID_DIR" "$ZAPRET_LOG_DIR" "$ZAPRET_HOSTLIST_DIR" "$ZAPRET_RUNTIME_BASE_DIR"
}

_start_zapret_runtime_handler() {
    local section="$1"
    local index queue_number mark_hex raw_opt expanded_opt pidfile logfile pid

    rule_is_enabled "$section" || return 0
    [ "$(get_rule_action "$section")" = "zapret" ] || return 0

    index="$(get_zapret_rule_index "$section")"
    queue_number="$(get_zapret_rule_queue_number "$index")"
    mark_hex="$(get_zapret_rule_mark_hex "$index")"
    raw_opt="$(get_rule_nfqws_opt "$section")"
    expanded_opt="$(expand_zapret_nfqws_opt "$raw_opt" "$section")"
    pidfile="$ZAPRET_PID_DIR/$section.pid"
    logfile="$ZAPRET_LOG_DIR/$section.log"

    log "Starting nfqws for rule '$section' on queue $queue_number with mark $mark_hex"
    (
        close_inherited_service_lock_fd
        # Split NFQWS_OPT into argv explicitly so shell environment changes do
        # not break comma-separated option values such as fake,multisplit.
        set -f
        IFS=' '
        set -- $expanded_opt
        exec "$ZAPRET_NFQWS_BIN" --qnum="$queue_number" --dpi-desync-fwmark="$ZAPRET_DESYNC_MARK" "$@"
    ) >>"$logfile" 2>&1 &
    pid="$!"
    echo "$pid" > "$pidfile"
    sleep 1

    if ! kill -0 "$pid" 2>/dev/null; then
        log "nfqws failed to start for rule '$section'. Check $logfile. Aborted." "fatal"
        exit 1
    fi
}

start_zapret_runtime() {
    has_enabled_zapret_rules || return 0
    is_zapret_installed || return 0

    stop_zapret_runtime
    check_zapret_requirements
    mkdir -p "$ZAPRET_PID_DIR" "$ZAPRET_LOG_DIR" "$ZAPRET_HOSTLIST_DIR"
    config_foreach _start_zapret_runtime_handler "rule"
}
