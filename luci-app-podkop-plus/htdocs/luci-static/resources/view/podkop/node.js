"use strict";
"require form";
"require baseclass";
"require tools.widgets as widgets";
"require view.podkop_plus.main as main";

function createNodeContent(section) {
  let o = section.option(form.Flag, "enabled", _("Enable"));
  o.default = "1";
  o.rmempty = false;
  o.editable = true;

  o = section.option(
    form.ListValue,
    "proxy_config_type",
    _("Node Type"),
    _("Choose how this outbound should be configured"),
  );
  o.value("url", _("Connection URL"));
  o.value("selector", "Selector");
  o.value("urltest", "URLTest");
  o.value("outbound", _("Outbound JSON"));
  o.value("interface", _("Interface"));
  o.default = "url";
  o.rmempty = false;
  o.editable = true;

  o = section.option(
    form.TextValue,
    "proxy_string",
    _("Proxy Configuration URL"),
    _("vless://, ss://, trojan://, socks4/5://, hy2/hysteria2:// links"),
  );
  o.depends("proxy_config_type", "url");
  o.rows = 5;
  o.wrap = "soft";
  o.textarea = true;
  o.modalonly = true;
  o.validate = function (_section_id, value) {
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateProxyUrl(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    form.TextValue,
    "outbound_json",
    _("Outbound JSON"),
    _("Enter a complete sing-box outbound object"),
  );
  o.depends("proxy_config_type", "outbound");
  o.rows = 10;
  o.modalonly = true;
  o.validate = function (_section_id, value) {
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateOutboundJson(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    form.DynamicList,
    "selector_proxy_links",
    _("Selector Links"),
    _("A manual group of proxy URLs for this node"),
  );
  o.depends("proxy_config_type", "selector");
  o.modalonly = true;
  o.validate = function (_section_id, value) {
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateProxyUrl(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    form.DynamicList,
    "urltest_proxy_links",
    _("URLTest Links"),
    _("A latency-tested group of proxy URLs for this node"),
  );
  o.depends("proxy_config_type", "urltest");
  o.modalonly = true;
  o.validate = function (_section_id, value) {
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateProxyUrl(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(form.ListValue, "urltest_check_interval", _("URLTest Interval"));
  o.value("30s", _("Every 30 seconds"));
  o.value("1m", _("Every minute"));
  o.value("3m", _("Every 3 minutes"));
  o.value("5m", _("Every 5 minutes"));
  o.default = "3m";
  o.rmempty = false;
  o.depends("proxy_config_type", "urltest");
  o.modalonly = true;

  o = section.option(
    form.Value,
    "urltest_tolerance",
    _("URLTest Tolerance"),
    _("Maximum response time delta in milliseconds"),
  );
  o.default = "50";
  o.rmempty = false;
  o.depends("proxy_config_type", "urltest");
  o.modalonly = true;
  o.validate = function (_section_id, value) {
    if (!value || value.length === 0) {
      return true;
    }

    const parsed = parseFloat(value);
    if (
      /^[0-9]+$/.test(value) &&
      !isNaN(parsed) &&
      isFinite(parsed) &&
      parsed >= 50 &&
      parsed <= 1000
    ) {
      return true;
    }

    return _("Must be a number in the range of 50 - 1000");
  };

  o = section.option(form.Value, "urltest_testing_url", _("URLTest URL"));
  o.value(
    "https://www.gstatic.com/generate_204",
    "https://www.gstatic.com/generate_204 (Google)",
  );
  o.value(
    "https://cp.cloudflare.com/generate_204",
    "https://cp.cloudflare.com/generate_204 (Cloudflare)",
  );
  o.value("https://captive.apple.com", "https://captive.apple.com (Apple)");
  o.value(
    "https://connectivity-check.ubuntu.com",
    "https://connectivity-check.ubuntu.com (Ubuntu)",
  );
  o.default = "https://www.gstatic.com/generate_204";
  o.rmempty = false;
  o.depends("proxy_config_type", "urltest");
  o.modalonly = true;
  o.validate = function (_section_id, value) {
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateUrl(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    form.Flag,
    "enable_udp_over_tcp",
    _("UDP over TCP"),
    _("Applicable for SOCKS and Shadowsocks links"),
  );
  o.default = "0";
  o.rmempty = false;
  o.modalonly = true;

  o = section.option(
    widgets.DeviceSelect,
    "interface",
    _("Interface"),
    _("Use a network interface as the outbound for this node"),
  );
  o.noaliases = true;
  o.nobridges = false;
  o.noinactive = false;
  o.depends("proxy_config_type", "interface");
  o.modalonly = true;
  o.filter = function (_section_id, value) {
    const blockedInterfaces = [
      "br-lan",
      "eth0",
      "eth1",
      "wan",
      "phy0-ap0",
      "phy1-ap0",
      "pppoe-wan",
      "lan",
    ];

    if (blockedInterfaces.includes(value)) {
      return false;
    }

    const device = this.devices.find((dev) => dev.getName() === value);
    if (!device) {
      return true;
    }

    const type = device.getType();
    const isWireless =
      type === "wifi" || type === "wireless" || type.indexOf("wlan") >= 0;

    return !isWireless;
  };

  o = section.option(
    form.Flag,
    "domain_resolver_enabled",
    _("Resolver For Interface Outbound"),
    _("Enable a dedicated DNS resolver when this node uses an interface"),
  );
  o.default = "0";
  o.rmempty = false;
  o.depends("proxy_config_type", "interface");
  o.modalonly = true;

  o = section.option(form.ListValue, "domain_resolver_dns_type", _("DNS Protocol"));
  o.value("doh", _("DNS over HTTPS (DoH)"));
  o.value("dot", _("DNS over TLS (DoT)"));
  o.value("udp", "UDP");
  o.default = "udp";
  o.rmempty = false;
  o.depends({
    proxy_config_type: "interface",
    domain_resolver_enabled: "1",
  });
  o.modalonly = true;

  o = section.option(form.Value, "domain_resolver_dns_server", _("DNS Server"));
  Object.entries(main.DNS_SERVER_OPTIONS).forEach(([key, label]) => {
    o.value(key, _(label));
  });
  o.default = "8.8.8.8";
  o.rmempty = false;
  o.depends({
    proxy_config_type: "interface",
    domain_resolver_enabled: "1",
  });
  o.modalonly = true;
  o.validate = function (_section_id, value) {
    const validation = main.validateDNS(value);
    return validation.valid ? true : validation.message;
  };
}

const EntryPoint = {
  createNodeContent,
};

return baseclass.extend(EntryPoint);
