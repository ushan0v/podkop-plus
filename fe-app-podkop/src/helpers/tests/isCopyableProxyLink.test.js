import { describe, expect, it } from 'vitest';
import {
  isCopyableProxyLink,
  isCopyableProxyOutboundType,
} from '../isCopyableProxyLink';

const copyableLinks = [
  'vless://uuid@example.com:443',
  'vmess://encoded',
  'trojan://password@example.com:443',
  'ss://encoded@example.com:443',
  'ssr://encoded',
  'hysteria2://password@example.com:443',
  'hy2://password@example.com:443',
  'tuic://uuid:password@example.com:443',
  'socks4://example.com:1080',
  'socks4a://example.com:1080',
  'socks5://user:pass@example.com:1080',
  'http://example.com:80',
  'https://user:pass@example.com:443',
];

const nonCopyableLinks = [
  '',
  'direct',
  'block',
  'urltest',
  'https://example.com/subscription',
  'https://example.com',
  'http://example.com:99999',
  'wireguard://example.com',
];

describe('isCopyableProxyLink', () => {
  describe.each(copyableLinks)('copyable proxy URI %s', (link) => {
    it('returns true', () => {
      expect(isCopyableProxyLink(link)).toBe(true);
    });
  });

  describe.each(nonCopyableLinks)('non-copyable value %s', (link) => {
    it('returns false', () => {
      expect(isCopyableProxyLink(link)).toBe(false);
    });
  });
});

describe('isCopyableProxyOutboundType', () => {
  it('accepts protocol outbound types from imported proxy links', () => {
    expect(isCopyableProxyOutboundType('VLESS')).toBe(true);
    expect(isCopyableProxyOutboundType('shadowsocks')).toBe(true);
    expect(isCopyableProxyOutboundType('hysteria2')).toBe(true);
    expect(isCopyableProxyOutboundType('socks')).toBe(true);
    expect(isCopyableProxyOutboundType('http')).toBe(true);
  });

  it('rejects group, service and routing-only outbound types', () => {
    expect(isCopyableProxyOutboundType('urltest')).toBe(false);
    expect(isCopyableProxyOutboundType('selector')).toBe(false);
    expect(isCopyableProxyOutboundType('direct')).toBe(false);
    expect(isCopyableProxyOutboundType('block')).toBe(false);
  });
});
