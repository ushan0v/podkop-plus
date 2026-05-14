export type ReleaseVersionCompareResult = -1 | 0 | 1 | null;

function normalizeReleaseVersion(version: string) {
  return version
    .trim()
    .replace(/^v/i, '')
    .replace(/-r(\d+)$/i, '-$1');
}

function parseReleaseVersion(version: string): number[] | null {
  const normalized = normalizeReleaseVersion(version);
  const match = normalized.match(/^(\d+(?:\.\d+)*)(?:-(\d+))?$/);

  if (!match) {
    return null;
  }

  const baseParts = match[1].split('.').map((part) => Number(part));
  const releasePart = match[2] ? Number(match[2]) : 0;
  const parts = [...baseParts, releasePart];

  return parts.every((part) => Number.isSafeInteger(part)) ? parts : null;
}

export function compareReleaseVersions(
  currentVersion: string,
  latestVersion: string,
): ReleaseVersionCompareResult {
  const currentParts = parseReleaseVersion(currentVersion);
  const latestParts = parseReleaseVersion(latestVersion);

  if (!currentParts || !latestParts) {
    return null;
  }

  const length = Math.max(currentParts.length, latestParts.length);

  for (let index = 0; index < length; index += 1) {
    const currentPart = currentParts[index] ?? 0;
    const latestPart = latestParts[index] ?? 0;

    if (currentPart < latestPart) {
      return -1;
    }

    if (currentPart > latestPart) {
      return 1;
    }
  }

  return 0;
}

export function isDevVersion(version: string): boolean {
  return (
    version === 'dev' ||
    /(?:^|[.+-])dev(?:$|[.+-])/i.test(version) ||
    version.includes('COMPILED')
  );
}
