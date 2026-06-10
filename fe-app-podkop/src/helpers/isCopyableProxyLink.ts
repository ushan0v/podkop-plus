const COPYABLE_PROXY_URI_RE =
  /^(vless|vmess|trojan|ss|ssr|hysteria2|hy2|tuic|socks4|socks4a|socks5):\/\//i;
const HTTP_PROXY_URI_RE =
  /^https?:\/\/(?:[^/@\s]+(?::[^/@\s]*)?@)?[^:/?#@\s]+:(\d{1,5})$/i;

const COPYABLE_PROXY_OUTBOUND_TYPES = new Set([
  'vless',
  'vmess',
  'trojan',
  'shadowsocks',
  'ss',
  'shadowsocksr',
  'ssr',
  'hysteria2',
  'hy2',
  'tuic',
  'socks',
  'socks4',
  'socks4a',
  'socks5',
  'http',
]);

export function isCopyableProxyLink(link?: string) {
  const value = (link || '').trim();
  if (COPYABLE_PROXY_URI_RE.test(value)) {
    return true;
  }

  const httpProxy = value.match(HTTP_PROXY_URI_RE);
  if (!httpProxy) {
    return false;
  }

  const port = Number(httpProxy[1]);
  return Number.isInteger(port) && port >= 1 && port <= 65535;
}

export function isCopyableProxyOutboundType(type?: string) {
  return COPYABLE_PROXY_OUTBOUND_TYPES.has((type || '').trim().toLowerCase());
}
