import { BookSource, SearchBook } from '../../model/data/Book';
import { appDb } from '../../model/data/AppDatabase';
import { HttpClient } from '../http/HttpClient';
import { AnalyzeUrl } from '../rule/AnalyzeUrl';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { JsRuntime } from '../rule/JsRuntime';

export interface ExploreEntry {
  title: string;
  url: string;
  sourceUrl: string;
  sourceName: string;
}

interface ExploreUrlItem {
  title?: string;
  url?: string;
}

export class ExploreCoordinator {
  private http: HttpClient = new HttpClient(10000);

  async getEntries(): Promise<ExploreEntry[]> {
    const sources = await appDb.getEnabledBookSources();
    const entries: ExploreEntry[] = [];
    for (const source of sources) {
      if (!source.enabledExplore || !source.exploreUrl) continue;
      if (!source.exploreRule?.bookList || !source.exploreRule?.name || !source.exploreRule?.bookUrl) {
        console.warn('[ExploreCoordinator] skip source without explore rules:', source.bookSourceName);
        continue;
      }
      const parsed = this.parseExploreUrl(source);
      entries.push(...parsed);
    }
    return entries;
  }

  async explore(entry: ExploreEntry, page: number = 1): Promise<SearchBook[]> {
    const source = await appDb.getBookSource(entry.sourceUrl);
    if (!source) return [];
    try {
      const au = new AnalyzeUrl(source, this.http);
      const reqUrl = this.buildUrl(entry.url, page);
      console.info('[ExploreCoordinator] explore:', `${entry.sourceName}/${entry.title}`, reqUrl);
      const resp = await au.fetch(reqUrl);
      console.info('[ExploreCoordinator] response:', resp.statusCode, 'len:', resp.body?.length || 0, 'url:', resp.url);
      if (!resp.success || !resp.body) {
        console.warn('[ExploreCoordinator] empty response:', resp.statusCode, resp.error || '');
        return [];
      }

      const rule = new AnalyzeRule(resp.body, source.bookSourceUrl);
      const exploreRule = source.exploreRule;
      const items = rule.getElements(exploreRule.bookList || '');
      console.info('[ExploreCoordinator] parsed list:', source.bookSourceName, 'rule:', exploreRule.bookList, 'count:', items.length);
      const books: SearchBook[] = [];

      for (const item of items) {
        const ir = new AnalyzeRule(item, source.bookSourceUrl);
        const book = new SearchBook();
        book.name = ir.analyzeFirst(exploreRule.name) || '';
        book.author = ir.analyzeFirst(exploreRule.author) || '';
        book.coverUrl = ir.analyzeFirst(exploreRule.coverUrl) || '';
        book.intro = ir.analyzeFirst(exploreRule.intro) || '';
        book.kind = ir.analyzeFirst(exploreRule.kind) || '';
        book.latestChapterTitle = ir.analyzeFirst(exploreRule.lastChapter) || '';
        book.wordCount = ir.analyzeFirst(exploreRule.wordCount) || '';
        book.bookUrl = this.resolve(ir.analyzeFirst(exploreRule.bookUrl), source.bookSourceUrl);
        book.origin = source.bookSourceUrl;
        book.originName = source.bookSourceName;

        if (book.name && book.bookUrl && !books.some(b => b.bookUrl === book.bookUrl && b.origin === book.origin)) {
          books.push(book);
        }
      }
      if (books.length > 0) {
        console.info('[ExploreCoordinator] first book:', books[0].name, books[0].bookUrl);
      } else if (items.length > 0) {
        console.warn('[ExploreCoordinator] list matched but no valid book:', source.bookSourceName,
          'nameRule:', exploreRule.name, 'urlRule:', exploreRule.bookUrl,
          'firstItem:', items[0].substring(0, Math.min(items[0].length, 240)));
      }
      return books;
    } catch (e) {
      console.error('[ExploreCoordinator] explore failed:', e);
      return [];
    }
  }

  private parseExploreUrl(source: BookSource): ExploreEntry[] {
    const entries: ExploreEntry[] = [];
    const raw = source.exploreUrl.trim();
    if (!raw) return entries;

    try {
      const parsed = JSON.parse(raw) as ExploreUrlItem[];
      if (Array.isArray(parsed)) {
        for (const item of parsed) {
          const title = String(item.title || '').trim();
          const url = String(item.url || '').trim();
          if (!title || !url) continue;
          entries.push({
            title: title,
            url: url,
            sourceUrl: source.bookSourceUrl,
            sourceName: source.bookSourceName
          });
        }
        return entries;
      }
    } catch (_) {
    }

    const lines = source.exploreUrl
      .split(/[\n\r]+/)
      .map(line => line.trim())
      .filter(line => line.length > 0);

    for (const line of lines) {
      const idx = line.indexOf('::');
      const title = idx > 0 ? line.substring(0, idx).trim() : source.bookSourceName;
      const url = idx > 0 ? line.substring(idx + 2).trim() : line;
      if (!url) continue;
      entries.push({
        title: title,
        url: url,
        sourceUrl: source.bookSourceUrl,
        sourceName: source.bookSourceName
      });
    }
    return entries;
  }

  private buildUrl(url: string, page: number): string {
    const js = new JsRuntime();
    js.setVar('page', String(page));
    js.setVar('pageIndex', String(page));
    return js.evalTemplate(url).replace(/\{\{[^}]+\}\}/g, String(page));
  }

  private resolve(url: string, base: string): string {
    if (!url || url.startsWith('http')) return url;
    if (url.startsWith('/')) {
      const m = base.match(/^(https?:\/\/[^/]+)/);
      return m ? m[0] + url : base + url;
    }
    const b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return b + '/' + url;
  }
}
