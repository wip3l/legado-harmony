import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { SearchBook } from '../model/data/Book';

class ChangeSourceCacheEntry {
  key: string = '';
  updatedAt: number = 0;
  results: SearchBook[] = [];
}

class ChangeSourceCachePayload {
  entries: ChangeSourceCacheEntry[] = [];
}

export class ChangeSourceResultCache {
  private static readonly STORE_NAME: string = 'change_source_result_cache';
  private static readonly CACHE_KEY: string = 'entries';
  private static readonly MAX_BOOKS: number = 30;
  private static readonly MAX_RESULTS_PER_BOOK: number = 200;

  static async load(context: Context, bookName: string): Promise<SearchBook[]> {
    const payload = await ChangeSourceResultCache.loadPayload(context);
    const key = ChangeSourceResultCache.buildBookKey(bookName);
    const entry = payload.entries.find((item: ChangeSourceCacheEntry) => item.key === key);
    if (!entry || !Array.isArray(entry.results)) {
      return [];
    }
    return entry.results.map((item: SearchBook) => ChangeSourceResultCache.cloneSearchBook(item));
  }

  static async save(context: Context, bookName: string, results: SearchBook[]): Promise<void> {
    const key = ChangeSourceResultCache.buildBookKey(bookName);
    if (!key) {
      return;
    }
    const payload = await ChangeSourceResultCache.loadPayload(context);
    const entry = new ChangeSourceCacheEntry();
    entry.key = key;
    entry.updatedAt = Date.now();
    entry.results = results.slice(0, ChangeSourceResultCache.MAX_RESULTS_PER_BOOK)
      .map((item: SearchBook) => ChangeSourceResultCache.cloneSearchBook(item));
    payload.entries = [entry].concat(
      payload.entries.filter((item: ChangeSourceCacheEntry) => item.key !== key)
    ).slice(0, ChangeSourceResultCache.MAX_BOOKS);

    const store = await preferences.getPreferences(context, ChangeSourceResultCache.STORE_NAME);
    await store.put(ChangeSourceResultCache.CACHE_KEY, JSON.stringify(payload));
    await store.flush();
  }

  private static async loadPayload(context: Context): Promise<ChangeSourceCachePayload> {
    const store = await preferences.getPreferences(context, ChangeSourceResultCache.STORE_NAME);
    const value = await store.get(ChangeSourceResultCache.CACHE_KEY, '');
    if (typeof value !== 'string' || !value) {
      return new ChangeSourceCachePayload();
    }
    try {
      const payload = JSON.parse(value) as ChangeSourceCachePayload;
      if (payload && Array.isArray(payload.entries)) {
        return payload;
      }
    } catch (e) {
      console.warn('读取换源结果缓存失败:', e);
    }
    return new ChangeSourceCachePayload();
  }

  private static buildBookKey(bookName: string): string {
    return (bookName || '').trim().replace(/\s+/g, '').toLowerCase();
  }

  private static cloneSearchBook(source: SearchBook): SearchBook {
    const target = new SearchBook();
    target.bookUrl = source.bookUrl || '';
    target.origin = source.origin || '';
    target.originName = source.originName || '';
    target.type = source.type || 0;
    target.name = source.name || '';
    target.author = source.author || '';
    target.kind = source.kind || '';
    target.coverUrl = source.coverUrl || '';
    target.intro = source.intro || '';
    target.latestChapterTitle = source.latestChapterTitle || '';
    target.wordCount = source.wordCount || '';
    target.tocUrl = source.tocUrl || '';
    target.variable = source.variable || '';
    target.bookSourceComment = source.bookSourceComment || '';
    target.customOrder = source.customOrder || 0;
    target.weight = source.weight || 0;
    return target;
  }
}
