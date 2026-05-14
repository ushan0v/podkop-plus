import { describe, expect, it } from 'vitest';
import {
  compareReleaseVersions,
  isDevVersion,
} from '../compareReleaseVersions';

describe('compareReleaseVersions', () => {
  it('detects equal versions with and without v prefix', () => {
    expect(compareReleaseVersions('0.7.14-3', 'v0.7.14-3')).toBe(0);
  });

  it('treats OpenWrt package release suffix as the same fork release', () => {
    expect(compareReleaseVersions('0.7.17-4', '0.7.17-r4')).toBe(0);
    expect(compareReleaseVersions('0.7.17-r4', '0.7.17-4')).toBe(0);
  });

  it('detects outdated versions', () => {
    expect(compareReleaseVersions('0.7.14-2', '0.7.14-3')).toBe(-1);
  });

  it('detects versions newer than the latest release', () => {
    expect(compareReleaseVersions('0.7.14-4', '0.7.14-3')).toBe(1);
  });

  it('compares base version before fork release', () => {
    expect(compareReleaseVersions('0.7.15-1', '0.7.14-3')).toBe(1);
  });

  it('returns null for non-release versions', () => {
    expect(compareReleaseVersions('0.7.14-dev+abc123', '0.7.14-3')).toBeNull();
  });
});

describe('isDevVersion', () => {
  it('detects placeholder and dev builds', () => {
    expect(isDevVersion('dev')).toBe(true);
    expect(isDevVersion('__COMPILED_VERSION_VARIABLE__')).toBe(true);
    expect(isDevVersion('0.7.14-dev+abc123')).toBe(true);
  });
});
