import { BookSource } from '../../model/data/Book';
import { SourceRuntimeStage } from './BookSourceRuntimeRouter';
import { BookSourceStageWebRuntime, StageWebRuntimeRequest } from './BookSourceStageWebRuntime';

interface BookSourceHeaderRuntimeEntry {
  headers: Record<string, string>;
  expiresAt: number;
}

/**
 * Resolves a source's `@js:` header rule in the bounded stage runtime so dynamic header values
 * (for example `"Referer": sourceUrl + '/'` or a Cookie assembled from source variables) reach
 * native AnalyzeUrl requests. The static literal-only extraction in AnalyzeUrl remains the
 * fallback whenever the runtime is unavailable.
 *
 * The script only reads source state (getVariable/getLoginHeader/...), so results are cached per
 * source URL + source variable and refreshed on a short TTL. Callers must still scope the result
 * to trusted hosts (AnalyzeUrl.isTrustedRequestHost) — a source's dynamic Cookie must never leak
 * to third-party content or image hosts.
 */
export class BookSourceHeaderRuntime {
  private static readonly TTL_MS: number = 5 * 60 * 1000;
  private static readonly MAX_ENTRIES: number = 32;
  private static cache: Record<string, BookSourceHeaderRuntimeEntry> = {};

  static async resolve(source: BookSource): Promise<Record<string, string>> {
    const raw = (source.header || '').trim();
    if (!raw || !/^@?js\s*:/i.test(raw)) return {};
    const cacheKey = `${source.bookSourceUrl || ''}\n${source.variable || ''}`;
    const cached = BookSourceHeaderRuntime.cache[cacheKey];
    if (cached && cached.expiresAt > Date.now()) return cached.headers;
    const headers = await BookSourceHeaderRuntime.evaluate(source, raw);
    BookSourceHeaderRuntime.store(cacheKey, headers);
    return headers;
  }

  /** Test hook: drops every cached header resolution. */
  static clearCache(): void {
    BookSourceHeaderRuntime.cache = {};
  }

  private static async evaluate(source: BookSource, raw: string): Promise<Record<string, string>> {
    const runtime = BookSourceStageWebRuntime.get();
    if (!runtime.isAvailable() && !await runtime.waitUntilAvailable(1500)) return {};
    const request = new StageWebRuntimeRequest();
    request.applyStageBudget(SourceRuntimeStage.URL);
    request.source = source;
    request.baseUrl = source.bookSourceUrl || '';
    request.code = raw.replace(/^@?js\s*:/i, '');
    try {
      const result = await runtime.execute(request);
      return BookSourceHeaderRuntime.parseHeaderJson(result.value || '');
    } catch (_) {
      return {};
    }
  }

  /** Accepts either a JSON object or a JSON-encoded object string (the common script shape). */
  private static parseHeaderJson(value: string): Record<string, string> {
    let current: Object = value;
    for (let depth = 0; depth < 2; depth++) {
      const text = String(current ?? '').trim();
      if (!text.startsWith('{')) {
        if (depth === 0 && text.startsWith('"')) {
          try {
            current = JSON.parse(text);
            continue;
          } catch (_) {
          }
        }
        return {};
      }
      try {
        const parsed = JSON.parse(text) as Record<string, Object>;
        const headers: Record<string, string> = {};
        for (const key of Object.keys(parsed)) {
          const item = parsed[key];
          if (!key || item === undefined || item === null || typeof item === 'object') continue;
          headers[key] = String(item);
        }
        return headers;
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  private static store(cacheKey: string, headers: Record<string, string>): void {
    BookSourceHeaderRuntime.cache[cacheKey] = { headers: headers, expiresAt: Date.now() + BookSourceHeaderRuntime.TTL_MS };
    const keys = Object.keys(BookSourceHeaderRuntime.cache);
    if (keys.length <= BookSourceHeaderRuntime.MAX_ENTRIES) return;
    keys.sort((left: string, right: string): number =>
      (BookSourceHeaderRuntime.cache[left]?.expiresAt || 0) - (BookSourceHeaderRuntime.cache[right]?.expiresAt || 0));
    while (keys.length > BookSourceHeaderRuntime.MAX_ENTRIES) {
      const oldest = keys.shift();
      if (oldest === undefined) break;
      delete BookSourceHeaderRuntime.cache[oldest];
    }
  }
}
