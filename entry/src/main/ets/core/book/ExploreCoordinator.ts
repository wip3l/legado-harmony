import { BookSource, SearchBook } from '../../model/data/Book';
import { appDb } from '../../model/data/AppDatabase';
import { HttpClient } from '../http/HttpClient';
import { AnalyzeUrl } from '../rule/AnalyzeUrl';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { JsRuntime } from '../rule/JsRuntime';
import { VerificationSupport } from '../http/VerificationSupport';
import { EncodedSourceUrl } from './EncodedSourceUrl';
import { BookSourceDataUrlSupport } from './BookSourceDataUrlSupport';
import { BookUrlResolver } from './BookUrlResolver';

export interface ExploreEntry {
  title: string;
  url: string;
  sourceUrl: string;
  sourceName: string;
}

export interface ExploreSourceOption {
  sourceName: string;
  sourceUrl: string;
  platforms: string[];
}

interface ExploreUrlItem {
  title?: string;
  url?: string;
}

export class ExploreCoordinator {
  private http: HttpClient = new HttpClient(10000);

  async getExploreSources(): Promise<ExploreSourceOption[]> {
    const sources = await appDb.getEnabledBookSources();
    const options: ExploreSourceOption[] = [];
    for (const source of sources) {
      if (!source.enabledExplore || !source.exploreUrl) continue;
      options.push({
        sourceName: source.bookSourceName,
        sourceUrl: source.bookSourceUrl,
        platforms: BookSourceDataUrlSupport.sourceUsesGyExplore(source) ?
          await BookSourceDataUrlSupport.getExplorePlatforms(this.http, source) :
          []
      });
    }
    return options;
  }

  async getEntries(platform: string = '番茄', sourceUrl: string = ''): Promise<ExploreEntry[]> {
    const sources = await appDb.getEnabledBookSources();
    const entries: ExploreEntry[] = [];
    for (const source of sources) {
      if (!source.enabledExplore || !source.exploreUrl) continue;
      if (sourceUrl && source.bookSourceUrl !== sourceUrl) continue;
      if (BookSourceDataUrlSupport.sourceUsesGyExplore(source)) {
        const dataUrlEntries = await BookSourceDataUrlSupport.getExploreEntries(this.http, platform);
        for (const item of dataUrlEntries) {
          entries.push({
            title: item.title,
            url: item.url,
            sourceUrl: source.bookSourceUrl,
            sourceName: source.bookSourceName
          });
        }
        continue;
      }
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
      VerificationSupport.clearVerification();
      if (BookSourceDataUrlSupport.sourceUsesGyExplore(source)) {
        return await BookSourceDataUrlSupport.explore(this.http, source, entry.url, page);
      }
      const au = new AnalyzeUrl(source, this.http);
      const reqUrl = this.buildUrl(source, entry.url, page);
      console.info('[ExploreCoordinator] explore:', `${entry.sourceName}/${entry.title}`, reqUrl);
      const resp = EncodedSourceUrl.canHandle(reqUrl) ?
        await this.fetchEncodedDataUrl(reqUrl) : await au.fetch(reqUrl);
      console.info('[ExploreCoordinator] response:', resp.statusCode, 'len:', resp.body?.length || 0, 'url:', resp.url);
      if (VerificationSupport.shouldRequestBrowserVerification(source, resp.body, resp.statusCode, entry.url)) {
        const verifyUrl = VerificationSupport.pickVerificationUrl(source, reqUrl, entry.url);
        VerificationSupport.requestVerification(verifyUrl, `${source.bookSourceName} 验证`);
        console.warn('[ExploreCoordinator] source needs browser verification:', source.bookSourceName, verifyUrl);
        return [];
      }
      if (!resp.success || !resp.body) {
        console.warn('[ExploreCoordinator] empty response:', resp.statusCode, resp.error || '');
        return [];
      }

      const baseUrl = BookUrlResolver.effectiveBase(resp, reqUrl, source.bookSourceUrl);
      const rule = new AnalyzeRule(resp.body, baseUrl);
      const exploreRule = source.exploreRule;
      const items = rule.getElements(exploreRule.bookList || '');
      console.info('[ExploreCoordinator] parsed list:', source.bookSourceName, 'rule:', exploreRule.bookList, 'count:', items.length);
      const books: SearchBook[] = [];

      for (const item of items) {
        const ir = new AnalyzeRule(item, baseUrl);
        const book = new SearchBook();
        book.name = ir.analyzeFirst(exploreRule.name) || '';
        book.author = ir.analyzeFirst(exploreRule.author) || '';
        book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source, ir.analyzeFirst(exploreRule.coverUrl), baseUrl);
        book.intro = ir.analyzeFirst(exploreRule.intro) || '';
        book.kind = ir.analyzeFirst(exploreRule.kind) || '';
        book.latestChapterTitle = ir.analyzeFirst(exploreRule.lastChapter) || '';
        book.wordCount = ir.analyzeFirst(exploreRule.wordCount) || '';
        book.bookUrl = BookUrlResolver.resolve(ir.analyzeFirst(exploreRule.bookUrl), baseUrl);
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

  private buildUrl(source: BookSource, url: string, page: number): string {
    const built = BookSourceDataUrlSupport.buildRequestUrl(source, url, String(page));
    if (built) return built;
    const js = new JsRuntime();
    js.setVar('page', String(page));
    js.setVar('pageIndex', String(page));
    return js.evalTemplate(url).replace(/\{\{[^}]+\}\}/g, String(page));
  }

  private async fetchEncodedDataUrl(url: string): Promise<{ url: string, statusCode: number, headers: Record<string, string>, body: string, success: boolean, error?: string }> {
    const root = await EncodedSourceUrl.requestJsonForDataUrl(this.http, url);
    if (!root) {
      return { url: url, statusCode: 0, headers: {}, body: '', success: false, error: 'encoded data url request failed' };
    }
    return { url: url, statusCode: 200, headers: {}, body: JSON.stringify(root), success: true };
  }
}
