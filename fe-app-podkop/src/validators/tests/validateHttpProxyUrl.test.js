import { describe, expect, it } from 'vitest';
import { validateHttpProxyUrl } from '../validateHttpProxyUrl';

const validUrls = [
  ['http ipv4', 'http://127.0.0.1:80'],
  ['http domain', 'http://proxy.example.com:8080'],
  ['https auth', 'https://user:pass@example.com:443'],
  ['uppercase auth and host', 'https://USER:PASSWORD@Example.COM:8443'],
];

const invalidUrls = [
  ['missing port', 'http://example.com'],
  ['missing host', 'http://:8080'],
  ['invalid port', 'http://example.com:99999'],
  ['path present', 'https://example.com:443/path'],
  ['query present', 'https://example.com:443?token=abc'],
  ['space present', 'http://exa mple.com:80'],
  ['empty username', 'http://:pass@example.com:80'],
  ['unsupported scheme', 'socks5://example.com:1080'],
];

describe('validateHttpProxyUrl', () => {
  describe.each(validUrls)('valid URL: %s', (_desc, url) => {
    it('returns valid=true', () => {
      expect(validateHttpProxyUrl(url).valid).toBe(true);
    });
  });

  describe.each(invalidUrls)('invalid URL: %s', (_desc, url) => {
    it('returns valid=false', () => {
      expect(validateHttpProxyUrl(url).valid).toBe(false);
    });
  });
});
