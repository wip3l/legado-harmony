export class CoverUrlNormalizer {
  static normalize(raw: string): string {
    const value = (raw || '').trim();
    if (!value) {
      return '';
    }
    return CoverUrlNormalizer.normalizeQingtianDownloadProxy(value);
  }

  static prefer(primary: string, fallback: string): string {
    const preferred = CoverUrlNormalizer.normalize(primary);
    if (preferred) {
      return preferred;
    }
    return CoverUrlNormalizer.normalize(fallback);
  }

  static downloadCandidates(raw: string): string[] {
    const value = (raw || '').trim();
    if (!value) {
      return [];
    }
    const normalized = CoverUrlNormalizer.normalize(value);
    if (normalized && normalized !== value) {
      return [normalized, value];
    }
    return [value];
  }

  private static normalizeQingtianDownloadProxy(value: string): string {
    const match = value.match(/^https?:\/\/([a-z0-9-]+)\.qingtian618\.com(\/downloadImg\?[\s\S]*)$/i);
    if (!match || !match[1] || !match[2]) {
      return value;
    }
    return `http://${match[1]}.gyks.cf${match[2]}`;
  }
}
