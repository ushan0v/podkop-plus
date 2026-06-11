#!/usr/bin/env ucode

let fs = require("fs");

function as_string(value) {
    return value == null ? "" : "" + value;
}

function read_json_file(path) {
    let data = fs.readfile(path);
    if (data == null)
        return null;

    try {
        return json(data);
    }
    catch (e) {
        return null;
    }
}

function read_stdin() {
    let input = fs.open("/dev/stdin", "r");
    if (!input)
        return "";
    let data = input.read("all");
    input.close();
    return data == null ? "" : data;
}

function read_stdin_json() {
    let data = read_stdin();
    try {
        return json(data);
    }
    catch (e) {
        return null;
    }
}

function write_json(value) {
    print(sprintf("%J", value), "\n");
}

function write_compact_string_array(values) {
    print("[");
    for (let i = 0; i < length(values); i++) {
        if (i > 0)
            print(",");
        print(sprintf("%J", as_string(values[i])));
    }
    print("]\n");
}

function csv_to_json_array(value) {
    value = as_string(value);
    write_compact_string_array(value == "" ? [] : split(value, ","));
}

function write_file_json(path, value) {
    return fs.writefile(path, sprintf("%J", value) + "\n");
}

function array_or_empty(value) {
    return type(value) == "array" ? value : [];
}

function object_or_empty(value) {
    return type(value) == "object" ? value : {};
}

function merge_object_values(target, source) {
    target = object_or_empty(target);
    for (let key, value in object_or_empty(source))
        target[key] = value;
    return target;
}

function stdin_length() {
    let value = read_stdin_json();
    if (type(value) == "array" || type(value) == "object")
        print(length(value), "\n");
    else
        print("0\n");
}

function stdin_contains(needle) {
    return index(read_stdin(), as_string(needle)) >= 0;
}

function stdin_regex_matches(pattern) {
    pattern = as_string(pattern);
    if (pattern == "")
        return false;

    try {
        return match(read_stdin(), regexp(pattern)) != null;
    }
    catch (e) {
        return false;
    }
}

function file_line_count(path) {
    let data = fs.readfile(path);
    let count = 0;

    if (data == null) {
        print("0\n");
        return;
    }

    for (let i = 0; i < length(data); i++)
        if (substr(data, i, 1) == "\n")
            count++;

    print(count, "\n");
}

function ip_addr_first_inet4() {
    for (let line in split(read_stdin(), "\n")) {
        let fields = split(trim(as_string(line)), /[ \t]+/);
        if (length(fields) < 2 || fields[0] != "inet")
            continue;

        let slash = index(fields[1], "/");
        print(slash >= 0 ? substr(fields[1], 0, slash) : fields[1], "\n");
        return;
    }
}

function stdin_first_dns_a_address() {
    for (let line in split(read_stdin(), "\n")) {
        line = as_string(line);
        if (match(line, /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) != null) {
            print(line, "\n");
            return;
        }
    }
}

function stdin_first_dns_aaaa_address() {
    for (let line in split(read_stdin(), "\n")) {
        line = as_string(line);
        if (match(line, /^[0-9A-Fa-f:]+$/) != null) {
            print(line, "\n");
            return;
        }
    }
}

function stdin_first_nslookup_address() {
    for (let line in split(read_stdin(), "\n")) {
        line = as_string(line);
        if (match(line, /^Address[ \t]*[0-9]*:[ \t]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) == null &&
            match(line, /^Address[ \t]*[0-9]*:[ \t]*[0-9A-Fa-f:]+$/) == null)
            continue;

        let fields = split(trim(line), /[ \t]+/);
        if (length(fields) > 0)
            print(fields[length(fields) - 1], "\n");
        return;
    }
}

function valid_ipv6_literal(value) {
    value = as_string(value);
    return index(value, ":") >= 0 && match(value, /^[0-9A-Fa-f:.]+$/) != null;
}

function stdin_first_field() {
    let data = read_stdin();
    let newline = index(data, "\n");
    let line = newline >= 0 ? substr(data, 0, newline) : data;
    let fields = split(trim(as_string(line)), /[ \t\r\n]+/);

    if (length(fields) > 0 && fields[0] != "")
        print(fields[0], "\n");
}

function normalize_country_server_key(value) {
    print(lc(trim(as_string(value))), "\n");
}

function array_item(index) {
    let value = read_stdin_json();
    index = int(index || 0);
    if (type(value) == "array" && index >= 0 && index < length(value) && value[index] != null)
        print(as_string(value[index]), "\n");
}

function array_append_string(value) {
    let result = array_or_empty(read_stdin_json());
    push(result, as_string(value));
    write_json(result);
}

function merge_proxy_group_subscription_state(tags_path, link_refs_path, names_path, servers_path,
    subscription_tags_path, subscription_link_refs_path, subscription_names_path, subscription_servers_path) {
    let tags = array_or_empty(read_json_file(tags_path));
    for (let tag in array_or_empty(read_json_file(subscription_tags_path)))
        push(tags, tag);

    if (!write_file_json(tags_path, tags) ||
        !write_file_json(link_refs_path, merge_object_values(read_json_file(link_refs_path), read_json_file(subscription_link_refs_path))) ||
        !write_file_json(names_path, merge_object_values(read_json_file(names_path), read_json_file(subscription_names_path))) ||
        !write_file_json(servers_path, merge_object_values(read_json_file(servers_path), read_json_file(subscription_servers_path))))
        exit(1);
}

function append_proxy_group_outbound_state(tags_path, links_path, names_path, servers_path, tag, link, display_name, server) {
    tag = as_string(tag);
    link = as_string(link);
    display_name = as_string(display_name);
    server = as_string(server);

    let tags = array_or_empty(read_json_file(tags_path));
    let links = object_or_empty(read_json_file(links_path));
    let names = object_or_empty(read_json_file(names_path));
    let servers = object_or_empty(read_json_file(servers_path));

    push(tags, tag);
    names[tag] = display_name;
    if (link != "")
        links[tag] = link;
    if (server != "")
        servers[tag] = server;

    if (!write_file_json(tags_path, tags) ||
        !write_file_json(links_path, links) ||
        !write_file_json(names_path, names) ||
        !write_file_json(servers_path, servers))
        exit(1);
}

function contains(values, needle) {
    for (let value in values) {
        if (value == needle)
            return true;
    }
    return false;
}

function regex_matches(value, pattern) {
    pattern = as_string(pattern);
    if (pattern == "")
        return false;

    try {
        return match(as_string(value), regexp(pattern)) != null;
    }
    catch (e) {
        return false;
    }
}

function normalized_country_list() {
    let result = [];
    for (let value in array_or_empty(read_stdin_json())) {
        value = uc(as_string(value));
        if (length(value) == 2)
            push(result, value);
    }
    write_json(result);
}

function byte_at(value, index) {
    return ord(substr(value, index, 1));
}

function regional_indicator_letter(value, index) {
    if (index + 3 >= length(value))
        return "";

    if (byte_at(value, index) != 240 ||
        byte_at(value, index + 1) != 159 ||
        byte_at(value, index + 2) != 135)
        return "";

    let letter = byte_at(value, index + 3) - 166;
    if (letter < 0 || letter > 25)
        return "";

    return chr(65 + letter);
}

function country_from_flag_emoji(value) {
    value = as_string(value);

    for (let i = 0; i + 7 < length(value); i++) {
        let first = regional_indicator_letter(value, i);
        if (first == "")
            continue;

        let second = regional_indicator_letter(value, i + 4);
        if (second != "")
            return first + second;
    }

    return "";
}

function countries_from_flag_names(path) {
    let names = object_or_empty(read_json_file(path));
    let result = {};

    for (let tag, name in names) {
        let country = country_from_flag_emoji(name);
        if (country != "")
            result[tag] = country;
    }

    write_json(result);
}

function urltest_regex_matching_tag_array(tags, names, regexes) {
    let result = [];

    for (let tag in tags) {
        let name = names[tag];
        name = name == null || as_string(name) == "" ? tag : as_string(name);

        for (let pattern in regexes) {
            if (regex_matches(name, pattern)) {
                push(result, tag);
                break;
            }
        }
    }

    return result;
}

function urltest_regex_matching_tags(tags_path, names_path, regex_path) {
    let tags = array_or_empty(read_json_file(tags_path));
    let names = object_or_empty(read_json_file(names_path));
    let regexes = array_or_empty(read_json_file(regex_path));

    write_json(urltest_regex_matching_tag_array(tags, names, regexes));
}

function urltest_filter_array(mode, tags, names, countries, name_filter, regex_tags, country_filter) {
    let result = [];

    for (let tag in tags) {
        let name = as_string(names[tag] || tag);
        let country = uc(as_string(countries[tag] || ""));
        let matched = contains(name_filter, name) ||
            contains(name_filter, tag) ||
            (country != "" && contains(country_filter, country)) ||
            contains(regex_tags, tag);

        if ((mode == "include" && matched) || (mode == "exclude" && !matched))
            push(result, tag);
    }

    return result;
}

function urltest_filter(mode, tags_path, names_path, countries_path, names_filter_path, regex_tags_path, countries_filter_path) {
    let tags = array_or_empty(read_json_file(tags_path));
    let names = object_or_empty(read_json_file(names_path));
    let countries = object_or_empty(read_json_file(countries_path));
    let name_filter = array_or_empty(read_json_file(names_filter_path));
    let regex_tags = array_or_empty(read_json_file(regex_tags_path));
    let country_filter = array_or_empty(read_json_file(countries_filter_path));

    write_json(urltest_filter_array(mode, tags, names, countries, name_filter, regex_tags, country_filter));
}

function urltest_filter_mode(mode, tags_path, names_path, countries_path, include_names_path, include_regex_path, include_countries_path, exclude_names_path, exclude_regex_path, exclude_countries_path) {
    let tags = array_or_empty(read_json_file(tags_path));
    let names = object_or_empty(read_json_file(names_path));
    let countries = object_or_empty(read_json_file(countries_path));
    let include_names = array_or_empty(read_json_file(include_names_path));
    let include_regexes = array_or_empty(read_json_file(include_regex_path));
    let include_countries = array_or_empty(read_json_file(include_countries_path));
    let exclude_names = array_or_empty(read_json_file(exclude_names_path));
    let exclude_regexes = array_or_empty(read_json_file(exclude_regex_path));
    let exclude_countries = array_or_empty(read_json_file(exclude_countries_path));
    let include_regex_tags = urltest_regex_matching_tag_array(tags, names, include_regexes);
    let exclude_regex_tags = urltest_regex_matching_tag_array(tags, names, exclude_regexes);
    let result;

    if (mode == "include")
        result = urltest_filter_array("include", tags, names, countries, include_names, include_regex_tags, include_countries);
    else if (mode == "exclude")
        result = urltest_filter_array("exclude", tags, names, countries, exclude_names, exclude_regex_tags, exclude_countries);
    else if (mode == "mixed") {
        let included = urltest_filter_array("include", tags, names, countries, include_names, include_regex_tags, include_countries);
        result = urltest_filter_array("exclude", included, names, countries, exclude_names, exclude_regex_tags, exclude_countries);
    }
    else {
        result = tags;
    }

    write_json(result);
}

function final_urltest_outbounds(config_path, tags_path) {
    let config = object_or_empty(read_json_file(config_path));
    let tags = array_or_empty(read_json_file(tags_path));
    let outbounds_by_tag = {};
    let skipped_types = {
        selector: true,
        urltest: true,
        direct: true,
        dns: true,
        block: true
    };
    let result = [];

    for (let outbound in array_or_empty(config.outbounds)) {
        if (type(outbound) != "object")
            continue;

        let tag = as_string(outbound.tag || "");
        if (tag != "")
            outbounds_by_tag[tag] = outbound;
    }

    for (let tag in tags) {
        tag = as_string(tag);
        let outbound = outbounds_by_tag[tag];
        if (type(outbound) != "object")
            continue;

        let proxy_type = lc(as_string(outbound.type || ""));
        if (skipped_types[proxy_type])
            continue;

        push(result, tag);
    }

    write_json(result);
}

function section_countries(path) {
    let cache = object_or_empty(read_json_file(path));
    write_json(object_or_empty(cache.outboundMetadata && cache.outboundMetadata.countries));
}

function cached_country_object_for_servers(servers_path, cache_path) {
    let servers = object_or_empty(read_json_file(servers_path));
    let cache = object_or_empty(read_json_file(cache_path));
    let result = {};

    for (let tag, _ in servers) {
        let country = as_string(cache[tag] || "");
        if (country != "")
            result[tag] = country;
    }

    return result;
}

function cached_countries_for_servers(servers_path, cache_path) {
    write_json(cached_country_object_for_servers(servers_path, cache_path));
}

function missing_servers_tsv(servers_path, cache_path) {
    let servers = object_or_empty(read_json_file(servers_path));
    let cache = object_or_empty(read_json_file(cache_path));

    for (let tag, server in servers) {
        server = as_string(server);
        if (server != "" && as_string(cache[tag] || "") == "")
            print(tag, "\t", server, "\n");
    }
}

function body_error(path) {
    let body = read_json_file(path);
    let result = "";

    if (type(body) == "object")
        result = as_string((body.error && body.error.code) || body.code || body.error || "");

    print(result, "\n");
}

function ip_country_tsv(path) {
    for (let item in array_or_empty(read_json_file(path))) {
        if (type(item) != "object")
            continue;
        let ip = as_string(item.ip || "");
        let country = as_string(item.country || "");
        if (ip != "" && country != "")
            print(ip, "\t", country, "\n");
    }
}

function tsv_to_object(path) {
    let result = {};
    let data = fs.readfile(path);
    if (data != null) {
        for (let line in split(data, "\n")) {
            if (line == "")
                continue;
            let parts = split(line, "\t");
            if (length(parts) >= 2)
                result[parts[0]] = parts[1];
        }
    }
    write_json(result);
}

function tsv_second_column_array(path) {
    let seen = {};
    let result = [];
    let data = fs.readfile(path);

    if (data != null) {
        for (let line in split(data, "\n")) {
            if (line == "")
                continue;
            let parts = split(line, "\t");
            if (length(parts) >= 2 && parts[1] != "" && !seen[parts[1]]) {
                seen[parts[1]] = true;
                push(result, parts[1]);
            }
        }
    }

    sort(result, function(first, second) {
        return first == second ? 0 : (first < second ? -1 : 1);
    });
    write_json(result);
}

function array_slice_file(path, start, end) {
    write_json(slice(array_or_empty(read_json_file(path)), int(start || 0), int(end || 0)));
}

function object_nonempty_stdin() {
    let value = read_stdin_json();
    return (type(value) == "array" || type(value) == "object") && length(value) > 0;
}

function resolved_country_object_from_tsv(resolved_path, ip_country_path) {
    let ip_country = object_or_empty(read_json_file(ip_country_path));
    let result = {};
    let data = fs.readfile(resolved_path);

    if (data != null) {
        for (let line in split(data, "\n")) {
            if (line == "")
                continue;
            let parts = split(line, "\t");
            if (length(parts) < 2)
                continue;
            let country = as_string(ip_country[parts[1]] || "");
            if (country != "")
                result[parts[0]] = country;
        }
    }

    return result;
}

function server_countries_result(servers_path, cache_path, resolved_path, ip_country_path) {
    let result = cached_country_object_for_servers(servers_path, cache_path);

    for (let tag, country in resolved_country_object_from_tsv(resolved_path, ip_country_path))
        result[tag] = country;

    write_json(result);
}

function outbound_server_by_tag(tag) {
    let config = object_or_empty(read_stdin_json());
    for (let outbound in array_or_empty(config.outbounds)) {
        if (type(outbound) == "object" && outbound.tag == tag) {
            print(as_string(outbound.server || ""), "\n");
            return;
        }
    }
}

function dns_route_rule_exists(service_tag, tag) {
    let config = object_or_empty(read_stdin_json());
    for (let rule in array_or_empty(config.dns && config.dns.rules)) {
        if (type(rule) == "object" && rule[service_tag] == tag)
            return true;
    }
    return false;
}

function route_rule_has_resolve_matchers(service_tag, tag) {
    let config = object_or_empty(read_stdin_json());
    for (let rule in array_or_empty(config.route && config.route.rules)) {
        if (type(rule) != "object" || rule[service_tag] != tag)
            continue;
        if (rule.domain != null || rule.domain_suffix != null || rule.domain_keyword != null ||
            rule.domain_regex != null || rule.rule_set != null)
            return true;
    }
    return false;
}

let mode = ARGV[0] || "";

if (mode == "stdin-length")
    stdin_length();
else if (mode == "stdin-contains")
    exit(stdin_contains(ARGV[1]) ? 0 : 1);
else if (mode == "stdin-regex-matches")
    exit(stdin_regex_matches(ARGV[1]) ? 0 : 1);
else if (mode == "csv-to-json-array")
    csv_to_json_array(ARGV[1]);
else if (mode == "file-line-count")
    file_line_count(ARGV[1]);
else if (mode == "ip-addr-first-inet4")
    ip_addr_first_inet4();
else if (mode == "stdin-first-dns-a-address")
    stdin_first_dns_a_address();
else if (mode == "stdin-first-dns-aaaa-address")
    stdin_first_dns_aaaa_address();
else if (mode == "valid-ipv6-literal")
    exit(valid_ipv6_literal(ARGV[1]) ? 0 : 1);
else if (mode == "stdin-first-nslookup-address")
    stdin_first_nslookup_address();
else if (mode == "stdin-first-field")
    stdin_first_field();
else if (mode == "normalize-country-server-key")
    normalize_country_server_key(ARGV[1]);
else if (mode == "array-item")
    array_item(ARGV[1]);
else if (mode == "array-append-string")
    array_append_string(ARGV[1]);
else if (mode == "merge-proxy-group-subscription-state")
    merge_proxy_group_subscription_state(ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5], ARGV[6], ARGV[7], ARGV[8]);
else if (mode == "append-proxy-group-outbound-state")
    append_proxy_group_outbound_state(ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5], ARGV[6], ARGV[7], ARGV[8]);
else if (mode == "normalized-country-list")
    normalized_country_list();
else if (mode == "countries-from-flag-names")
    countries_from_flag_names(ARGV[1]);
else if (mode == "urltest-regex-matching-tags")
    urltest_regex_matching_tags(ARGV[1], ARGV[2], ARGV[3]);
else if (mode == "urltest-filter")
    urltest_filter(ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5], ARGV[6], ARGV[7]);
else if (mode == "urltest-filter-mode")
    urltest_filter_mode(ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5], ARGV[6], ARGV[7], ARGV[8], ARGV[9], ARGV[10]);
else if (mode == "final-urltest-outbounds")
    final_urltest_outbounds(ARGV[1], ARGV[2]);
else if (mode == "section-countries")
    section_countries(ARGV[1]);
else if (mode == "cached-countries-for-servers")
    cached_countries_for_servers(ARGV[1], ARGV[2]);
else if (mode == "missing-servers-tsv")
    missing_servers_tsv(ARGV[1], ARGV[2]);
else if (mode == "body-error")
    body_error(ARGV[1]);
else if (mode == "ip-country-tsv")
    ip_country_tsv(ARGV[1]);
else if (mode == "tsv-to-object")
    tsv_to_object(ARGV[1]);
else if (mode == "tsv-second-column-array")
    tsv_second_column_array(ARGV[1]);
else if (mode == "array-slice-file")
    array_slice_file(ARGV[1], ARGV[2], ARGV[3]);
else if (mode == "object-nonempty")
    exit(object_nonempty_stdin() ? 0 : 1);
else if (mode == "server-countries-result")
    server_countries_result(ARGV[1], ARGV[2], ARGV[3], ARGV[4]);
else if (mode == "outbound-server-by-tag")
    outbound_server_by_tag(ARGV[1]);
else if (mode == "dns-route-rule-exists")
    exit(dns_route_rule_exists(ARGV[1], ARGV[2]) ? 0 : 1);
else if (mode == "route-rule-has-resolve-matchers")
    exit(route_rule_has_resolve_matchers(ARGV[1], ARGV[2]) ? 0 : 1);
else {
    warn("Usage: sing_box_runtime.uc <operation> ...\n");
    exit(1);
}
