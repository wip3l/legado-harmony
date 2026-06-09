import { BookSource, SearchBook } from '../../model/data/Book';
import { appDb } from '../../model/data/AppDatabase';
import { HttpClient } from '../http/HttpClient';
import { AnalyzeUrl } from '../rule/AnalyzeUrl';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { RuleContext } from '../rule/RuleContext';
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
        const dataUrlEntries = await BookSourceDataUrlSupport.getExploreEntries(this.http, platform, '小说', '男频', source);
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
        await this.fetchEncodedDataUrl(reqUrl, source) : await au.fetch(reqUrl);
      console.info('[ExploreCoordinator] response:', resp.statusCode, 'len:', resp.body?.length || 0, 'url:', resp.url);
      if (VerificationSupport.shouldRequestBrowserVerification(source, resp.body, resp.statusCode, entry.url)) {
        const verifyUrl = VerificationSupport.pickVerificationUrl(source, reqUrl, entry.url);
        VerificationSupport.requestVerification(verifyUrl, `${source.bookSourceName} 验证`, source);
        console.warn('[ExploreCoordinator] source needs browser verification:', source.bookSourceName, verifyUrl);
        return [];
      }
      if (!resp.success || !resp.body) {
        console.warn('[ExploreCoordinator] empty response:', resp.statusCode, resp.error || '');
        return [];
      }

      const baseUrl = BookUrlResolver.effectiveBase(resp, reqUrl, source.bookSourceUrl);
      const rule = new AnalyzeRule(resp.body, baseUrl);
      this.seedSourceVariables(rule.getContext(), source);
      const exploreRule = source.exploreRule;
      const items = rule.getElements(exploreRule.bookList || '');
      console.info('[ExploreCoordinator] parsed list:', source.bookSourceName, 'rule:', exploreRule.bookList, 'count:', items.length);
      const books: SearchBook[] = [];
      const sourceBackendHost = BookSourceDataUrlSupport.sourceBackendHost(source);

      for (const item of items) {
        const ir = new AnalyzeRule(item, baseUrl);
        this.seedSourceVariables(ir.getContext(), source);
        if (sourceBackendHost) {
          ir.getContext().put('host', sourceBackendHost);
          ir.getContext().put('backend', sourceBackendHost);
        }
        const book = new SearchBook();
        book.name = ir.analyzeFirst(exploreRule.name) || '';
        book.author = ir.analyzeFirst(exploreRule.author) || '';
        book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrlFromItem(source,
          ir.analyzeFirst(exploreRule.coverUrl), item, baseUrl);
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
        this.appendExploreItems(entries, parsed, source);
        return entries;
      }
    } catch (_) {
    }

    const looseItems = this.parseLooseExploreItems(raw);
    if (looseItems.length > 0) {
      this.appendExploreItems(entries, looseItems, source);
      if (entries.length > 0) return entries;
    }

    const lines = source.exploreUrl
      .split(/[\n\r]+/)
      .map(line => line.trim())
      .filter(line => line.length > 0);

    for (const line of lines) {
      const idx = line.indexOf('::');
      const title = idx > 0 ? line.substring(0, idx).trim() : source.bookSourceName;
      const url = idx > 0 ? line.substring(idx + 2).trim() : line;
      if (!url || this.isPersonalExploreUrl(title, url)) continue;
      entries.push({
        title: title,
        url: url,
        sourceUrl: source.bookSourceUrl,
        sourceName: source.bookSourceName
      });
    }
    return entries;
  }

  private appendExploreItems(entries: ExploreEntry[], items: ExploreUrlItem[], source: BookSource): void {
    let groupTitle = '';
    for (const item of items) {
      const title = String(item.title || '').trim();
      const url = String(item.url || '').trim();
      if (!url) {
        groupTitle = this.cleanExploreGroupTitle(title) || groupTitle;
        continue;
      }
      if (!title || this.isPersonalExploreUrl(title, url)) continue;
      const entryTitle = groupTitle ? `${groupTitle} · ${title}` : title;
      if (entries.some(entry => entry.title === entryTitle && entry.url === url && entry.sourceUrl === source.bookSourceUrl)) {
        continue;
      }
      entries.push({
        title: entryTitle,
        url: url,
        sourceUrl: source.bookSourceUrl,
        sourceName: source.bookSourceName
      });
    }
  }

  private parseLooseExploreItems(raw: string): ExploreUrlItem[] {
    const items: ExploreUrlItem[] = [];
    const blocks = this.extractLooseObjectBlocks(raw);
    for (const block of blocks) {
      const title = this.readLooseObjectValue(block, 'title');
      const url = this.readLooseObjectValue(block, 'url');
      if (title || url) {
        items.push({ title: title, url: url });
      }
    }
    return items;
  }

  private extractLooseObjectBlocks(raw: string): string[] {
    const blocks: string[] = [];
    let depth = 0;
    let quote = '';
    let start = -1;
    for (let i = 0; i < raw.length; i++) {
      const ch = raw.charAt(i);
      if (quote) {
        if (ch === quote && raw.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === '{') {
        if (depth === 0) start = i;
        depth++;
      } else if (ch === '}') {
        if (depth > 0) depth--;
        if (depth === 0 && start >= 0) {
          blocks.push(raw.substring(start, i + 1));
          start = -1;
        }
      }
    }
    return blocks;
  }

  private readLooseObjectValue(block: string, key: string): string {
    const keyIndex = block.search(new RegExp(`["']?${key}["']?\\s*:`));
    if (keyIndex < 0) return '';
    const afterKey = block.substring(keyIndex);
    const colonIndex = afterKey.indexOf(':');
    if (colonIndex < 0) return '';
    let valueStart = keyIndex + colonIndex + 1;
    while (valueStart < block.length && /\s/.test(block.charAt(valueStart))) {
      valueStart++;
    }
    if (valueStart >= block.length) return '';

    const first = block.charAt(valueStart);
    if (first === '"' || first === "'") {
      let value = '';
      for (let i = valueStart + 1; i < block.length; i++) {
        const ch = block.charAt(i);
        if (ch === first && block.charAt(i - 1) !== '\\') {
          return value.trim();
        }
        value += ch;
      }
      return value.trim();
    }

    let valueEnd = block.length;
    const commaIndex = block.indexOf(',', valueStart);
    const braceIndex = block.indexOf('}', valueStart);
    if (commaIndex >= 0) valueEnd = Math.min(valueEnd, commaIndex);
    if (braceIndex >= 0) valueEnd = Math.min(valueEnd, braceIndex);
    return block.substring(valueStart, valueEnd)
      .replace(/^['"]|['"]$/g, '')
      .trim();
  }

  private cleanExploreGroupTitle(title: string): string {
    return (title || '')
      .replace(/[༺༻ˇ»«`´ʚɞ]/g, '')
      .replace(/[^\u4e00-\u9fa5A-Za-z0-9]+/g, '')
      .trim();
  }

  private isPersonalExploreUrl(title: string, url: string): boolean {
    const value = `${title || ''}\n${url || ''}`.toLowerCase();
    return value.includes('我的书架') || value.includes('bookshelf') || value.includes('/user/') ||
      value.includes('/login');
  }

  private buildUrl(source: BookSource, url: string, page: number): string {
    const built = BookSourceDataUrlSupport.buildRequestUrl(source, url, String(page));
    if (built) return built;
    const js = new JsRuntime();
    js.setVar('page', String(page));
    js.setVar('pageIndex', String(page));
    return js.evalTemplate(this.applySourceTemplate(url, source)).replace(/\{\{[^}]+\}\}/g, String(page));
  }

  private applySourceTemplate(url: string, source: BookSource): string {
    return (url || '')
      .replace(/\{\{\s*source\.bookSourceUrl\s*\}\}/g, source.bookSourceUrl || '')
      .replace(/\{\{\s*source\.bookSourceName\s*\}\}/g, source.bookSourceName || '')
      .replace(/\{\{\s*source\.bookSourceGroup\s*\}\}/g, source.bookSourceGroup || '');
  }

  private seedSourceVariables(ctx: RuleContext, source: BookSource): void {
    ctx.put('source.bookSourceUrl', source.bookSourceUrl || '');
    ctx.put('bookSourceUrl', source.bookSourceUrl || '');
    ctx.put('source.bookSourceName', source.bookSourceName || '');
    ctx.put('bookSourceName', source.bookSourceName || '');
    ctx.put('source.bookSourceGroup', source.bookSourceGroup || '');
    ctx.put('bookSourceGroup', source.bookSourceGroup || '');
    ctx.put('source.bookSourceComment', source.bookSourceComment || '');
    ctx.put('bookSourceComment', source.bookSourceComment || '');
    ctx.put('source.variable', source.variableComment || '');
  }

  private async fetchEncodedDataUrl(url: string, source: BookSource): Promise<{ url: string, statusCode: number, headers: Record<string, string>, body: string, success: boolean, error?: string }> {
    const root = await EncodedSourceUrl.requestJsonForDataUrl(this.http, url,
      BookSourceDataUrlSupport.sourceBackendHost(source));
    if (!root) {
      return { url: url, statusCode: 0, headers: {}, body: '', success: false, error: 'encoded data url request failed' };
    }
    return { url: url, statusCode: 200, headers: {}, body: JSON.stringify(root), success: true };
  }
}
