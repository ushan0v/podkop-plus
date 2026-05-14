export function normalizeCompiledVersion(version: string) {
  if (version.includes('COMPILED')) {
    return 'dev';
  }

  return version.replace(/^(\d+(?:\.\d+)*)-r(\d+)$/i, '$1-$2');
}
