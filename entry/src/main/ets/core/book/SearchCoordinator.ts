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

export interface SearchProgress {
  done: number;
  total: number;
  results: SearchBook[];
  finished: boolean;
  status: string;
  needVerification?: boolean;
  verificationUrl?: string;
  verificationTitle?: string;
}

export type SearchCallback = (progress: SearchProgress) => void;

const MAX_SEARCH_CONCURRENCY = 12;

export interface SearchOptions {
  exactMatch?: boolean;
  sourceGroups?: string[];
}

interface ScoredSearchBook {
  book: SearchBook;
  index: number;
  score: number;
}

export class SearchCoordinator {
  private http: HttpClient;
  private concurrency: number;
  private cancelled: boolean = false;

  constructor(concurrency: number = 8) {
    this.http = new HttpClient(8000);
    this.concurrency = Math.max(1, Math.min(Math.floor(concurrency), MAX_SEARCH_CONCURRENCY));
  }

  cancel(): void {
    this.cancelled = true;
  }

  async search(keyword: string, callback: SearchCallback, options: SearchOptions = {}): Promise<SearchBook[]> {
    this.cancelled = false;
    VerificationSupport.clearVerification();
    const enabledSources = await appDb.getEnabledBookSources();
    const selectedGroups = this.normalizeSelectedGroups(options.sourceGroups || []);
    const sources = selectedGroups.length > 0 ?
      enabledSources.filter((source: BookSource) => selectedGroups.includes(this.normalizeGroupName(source.bookSourceGroup))) :
      enabledSources;
    if (sources.length === 0) {
      callback({ done: 0, total: 0, results: [], finished: true, status: '没有符合设置的启用书源' });
      return [];
    }

    const all: SearchBook[] = [];
    let done = 0;
    let nextIndex = 0;
    const workerCount = Math.min(this.concurrency, sources.length);

    const emitProgress = (): void => {
      const verifyUrl = AppStorage.get<string>('pendingVerificationUrl') || '';
      callback({
        done: done, total: sources.length, results: this.filterAndSortSearchResults(all, keyword, options),
        finished: done >= sources.length,
        status: verifyUrl ? `已搜索 ${done}/${sources.length}，找到 ${all.length} 本；有书源需要网页验证` :
          `已搜索 ${done}/${sources.length}，找到 ${all.length} 本`,
        needVerification: verifyUrl.length > 0,
        verificationUrl: verifyUrl,
        verificationTitle: AppStorage.get<string>('pendingVerificationTitle') || '网页验证'
      });
    };

    const runWorker = async (): Promise<void> => {
      while (!this.cancelled) {
        const sourceIndex = nextIndex;
        nextIndex++;
        if (sourceIndex >= sources.length) break;

        const books = await this.searchOne(sources[sourceIndex], keyword);
        if (this.cancelled) break;

        done++;
        all.push(...books);
        emitProgress();
      }
    };

    const workers: Promise<void>[] = [];
    for (let i = 0; i < workerCount; i++) {
      workers.push(runWorker());
    }
    await Promise.all(workers);

    return this.filterAndSortSearchResults(all, keyword, options);
  }

  private async searchOne(source: BookSource, keyword: string): Promise<SearchBook[]> {
    try {
      if (BookSourceDataUrlSupport.sourceUsesGySearch(source)) {
        return await BookSourceDataUrlSupport.search(this.http, source, keyword);
      }
      if (!source.searchUrl || !source.searchRule?.bookList || !source.searchRule?.name || !source.searchRule?.bookUrl) {
        console.warn('[SC] skip source without search rules:', source.bookSourceName);
        return [];
      }
      const js = new JsRuntime();
      js.setVar('key', encodeURIComponent(keyword));
      js.setVar('searchKey', encodeURIComponent(keyword));
      js.setVar('keyword', encodeURIComponent(keyword));
      js.setVar('searchKeyRaw', keyword);
      js.setVar('page', '1');

      const au = new AnalyzeUrl(source, this.http);
      let urlTemplate = await this.evalAndBuild(js, source, keyword);
      if (!urlTemplate && source.searchUrl.includes('gysearch')) {
        urlTemplate = EncodedSourceUrl.buildSearchUrl(keyword);
      }
      console.log('[SC] search source:', source.bookSourceName, 'url:', urlTemplate);
      const resp = EncodedSourceUrl.canHandle(urlTemplate) ?
        await this.fetchEncodedDataUrl(urlTemplate, source) : await au.fetch(urlTemplate);

      console.log('[SC] response:', source.bookSourceName, resp.statusCode, 'len:', resp.body?.length || 0);
      if (VerificationSupport.shouldRequestBrowserVerification(source, resp.body, resp.statusCode, source.searchUrl)) {
        const verifyUrl = VerificationSupport.pickVerificationUrl(source, urlTemplate, source.searchUrl);
        VerificationSupport.requestVerification(verifyUrl, `${source.bookSourceName} 验证`, source);
        console.warn('[SC] source needs browser verification:', source.bookSourceName, verifyUrl);
        return [];
      }
      if (!resp.success || !resp.body) return [];

      // 防止超大响应导致 OOM
      if (resp.body.length > 500000) return [];

      const baseUrl = BookUrlResolver.effectiveBase(resp, urlTemplate, source.bookSourceUrl);
      const rule = new AnalyzeRule(resp.body, baseUrl);
      this.seedSourceVariables(rule.getContext(), source);
      rule.setJsVar('key', encodeURIComponent(keyword));
      rule.setJsVar('searchKey', encodeURIComponent(keyword));
      rule.setJsVar('keyword', encodeURIComponent(keyword));
      rule.setJsVar('page', '1');
      const searchRule = source.searchRule;
      const items = rule.getElements(searchRule.bookList || '');
      console.log('[SC] parsed list:', source.bookSourceName, 'rule:', searchRule.bookList, 'count:', items.length);

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
        book.name = ir.analyzeFirst(searchRule.name) || '';
        book.author = ir.analyzeFirst(searchRule.author) || '';
        book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrlFromItem(source,
          ir.analyzeFirst(searchRule.coverUrl), item, baseUrl);
        book.intro = ir.analyzeFirst(searchRule.intro) || '';
        book.kind = ir.analyzeFirst(searchRule.kind) || '';
        book.latestChapterTitle = ir.analyzeFirst(searchRule.lastChapter) || '';
        book.bookUrl = BookUrlResolver.resolve(ir.analyzeFirst(searchRule.bookUrl), baseUrl);
        book.variable = ir.getContext().toJson();
        // 如果解析后仍含 JSONPath 表达式，直接从 item 提取
        if (!book.bookUrl || book.bookUrl.startsWith('$') || book.bookUrl.includes('$._id') || book.bookUrl.includes('$..')) {
          // 尝试常见字段
          book.bookUrl = ir.analyzeFirst('bookUrl') || ir.analyzeFirst('url') || ir.analyzeFirst('link') ||
            ir.analyzeFirst('_id') || ir.analyzeFirst('id') || ir.analyzeFirst('nid') || ir.analyzeFirst('enid') || '';
          // 如果还是路径表达式，直接从原始 JSON 提取
          if (book.bookUrl && (book.bookUrl.startsWith('$') || book.bookUrl.includes('$..'))) {
            try {
              const raw = JSON.parse(item) as Record<string, Object>;
              book.bookUrl = String(raw['url'] || raw['bookUrl'] || raw['link'] || raw['href'] || raw['nid'] || '');
            } catch (_) {}
          }
          book.bookUrl = BookUrlResolver.resolve(book.bookUrl, baseUrl);
        }
        const searchBookId = this.extractBookId(ir, item, book.bookUrl);
        const responseCoverUrl = BookSourceDataUrlSupport.normalizeCoverUrlFromResponse(source, resp.body, searchBookId,
          baseUrl);
        if (responseCoverUrl && this.shouldReplaceCover(book.coverUrl)) {
          book.coverUrl = responseCoverUrl;
          console.log('[SC] cover from response:', source.bookSourceName, book.name, searchBookId);
        }
        book.origin = source.bookSourceUrl;
        book.originName = source.bookSourceName;
        book.bookSourceComment = source.bookSourceComment;
        book.customOrder = source.customOrder;
        book.weight = source.weight;

        if (book.name && book.bookUrl && !books.some(b => b.bookUrl === book.bookUrl && b.origin === book.origin)) {
          if (books.length === 0) {
            console.log('[SC] 第一条结果:', book.name, book.bookUrl, 'from:', source.bookSourceName);
          }
          books.push(book);
        }
      }
      if (books.length === 0 && items.length > 0) {
        console.warn('[SC] list matched but no valid book:', source.bookSourceName,
          'nameRule:', searchRule.name, 'urlRule:', searchRule.bookUrl,
          'firstItem:', items[0].substring(0, Math.min(items[0].length, 240)));
      }
      return books;
    } catch (e) {
      console.error('[SC] search failed:', source.bookSourceName, e);
      return [];
    }
  }

  private sortSearchResults(results: SearchBook[], keyword: string): SearchBook[] {
    const normalizedKeyword = this.normalizeSearchText(keyword);
    if (!normalizedKeyword) return [...results];
    const scored: ScoredSearchBook[] = results.map((book: SearchBook, index: number): ScoredSearchBook => {
      return {
        book: book,
        index: index,
        score: this.searchRelevanceScore(book, normalizedKeyword)
      };
    });
    scored.sort((a: ScoredSearchBook, b: ScoredSearchBook): number => {
      const scoreDiff = b.score - a.score;
      if (scoreDiff !== 0) return scoreDiff;
      const weightDiff = (b.book.weight || 0) - (a.book.weight || 0);
      if (weightDiff !== 0) return weightDiff;
      const orderDiff = (a.book.customOrder || 0) - (b.book.customOrder || 0);
      if (orderDiff !== 0) return orderDiff;
      return a.index - b.index;
    });
    return scored.map((item: ScoredSearchBook): SearchBook => item.book);
  }

  private searchRelevanceScore(book: SearchBook, normalizedKeyword: string): number {
    let score = 0;
    score += this.fieldMatchScore(this.normalizeSearchText(book.name), normalizedKeyword, 1200, 900, 700, 240);
    score += this.fieldMatchScore(this.normalizeSearchText(book.author), normalizedKeyword, 260, 220, 180, 70);
    score += this.fieldMatchScore(this.normalizeSearchText(book.kind), normalizedKeyword, 90, 70, 50, 20);
    score += this.fieldMatchScore(this.normalizeSearchText(book.latestChapterTitle), normalizedKeyword, 50, 40, 30, 0);
    score += this.fieldMatchScore(this.normalizeSearchText(book.intro), normalizedKeyword, 40, 30, 20, 0);
    return score;
  }

  private fieldMatchScore(value: string, keyword: string, exactScore: number, startsScore: number,
    containsScore: number, looseScore: number): number {
    if (!value || !keyword) return 0;
    if (value === keyword) return exactScore;
    if (value.startsWith(keyword)) return startsScore + this.shortTextBonus(value, keyword);
    const index = value.indexOf(keyword);
    if (index >= 0) {
      return containsScore + Math.max(0, 80 - index) + this.shortTextBonus(value, keyword);
    }
    return this.looseKeywordScore(value, keyword, looseScore);
  }

  private shortTextBonus(value: string, keyword: string): number {
    return Math.max(0, Math.min(80, 80 - Math.max(0, value.length - keyword.length) * 4));
  }

  private looseKeywordScore(value: string, keyword: string, maxScore: number): number {
    if (keyword.length <= 1 || maxScore <= 0) return 0;
    let hitCount = 0;
    for (let i = 0; i < keyword.length; i++) {
      if (value.includes(keyword.charAt(i))) hitCount++;
    }
    const ratio = hitCount / keyword.length;
    if (ratio >= 0.8) return Math.floor(maxScore * ratio);
    if (ratio >= 0.5) return Math.floor(maxScore * ratio * 0.5);
    return 0;
  }

  private normalizeSearchText(value: string): string {
    return (value || '').trim().toLowerCase()
      .replace(/\s+/g, '')
      .replace(/[《》【】\[\]（）()「」『』"“”'‘’.,，。:：;；!！?？、·_\-]/g, '');
  }

  private filterAndSortSearchResults(results: SearchBook[], keyword: string, options: SearchOptions): SearchBook[] {
    const sorted = this.sortSearchResults(results, keyword);
    if (!options.exactMatch) {
      return sorted;
    }
    const normalizedKeyword = this.normalizeSearchText(keyword);
    return sorted.filter((book: SearchBook) => this.normalizeSearchText(book.name) === normalizedKeyword);
  }

  private normalizeSelectedGroups(groups: string[]): string[] {
    const result: string[] = [];
    for (const group of groups) {
      const normalized = this.normalizeGroupName(group);
      if (normalized && !result.includes(normalized)) {
        result.push(normalized);
      }
    }
    return result;
  }

  private normalizeGroupName(group: string): string {
    const value = (group || '').trim();
    return value || '未分组';
  }

  private extractBookId(ir: AnalyzeRule, itemJson: string, bookUrl: string): string {
    const fromContext = ir.getContext().get('book_id') || ir.getContext().get('bookId') || ir.getContext().get('id');
    if (fromContext) return fromContext;
    const fromUrl = this.extractQueryValue(bookUrl, 'book_id') || this.extractQueryValue(bookUrl, 'bookId') ||
      this.extractQueryValue(bookUrl, 'bookid') || this.extractQueryValue(bookUrl, 'id');
    if (fromUrl) return fromUrl;
    try {
      const item = JSON.parse(itemJson || '{}') as Record<string, Object>;
      return String(item['book_id'] || item['bookId'] || item['id'] || '');
    } catch (_) {
      return '';
    }
  }

  private extractQueryValue(url: string, key: string): string {
    if (!url || !key) return '';
    const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const match = url.match(new RegExp(`[?&]${escaped}=([^&#]+)`, 'i'));
    return match && match[1] ? decodeURIComponent(match[1]) : '';
  }

  private shouldReplaceCover(url: string): boolean {
    const value = (url || '').trim().toLowerCase();
    return !value || value === 'thumb_url' || value === 'cover' || value === 'audio_thumb_uri' ||
      value.includes('{{') || value.includes('}}') || value.includes('$..') || value.includes('$.') ||
      value.includes('.heic') || value.includes('reading-sign.fqnovelpic.com') ||
      /\/(?:thumb_url|cover|audio_thumb_uri)$/.test(value);
  }

  private async evalAndBuild(js: JsRuntime, source: BookSource, keyword: string): Promise<string> {
    const searchUrl = source.searchUrl;
    const baseUrl = source.bookSourceUrl;
    if (!searchUrl) return `${baseUrl}/search?q={{key}}`;
    const scriptedFormUrl = await this.tryBuildScriptedFormSearchUrl(source, keyword);
    if (scriptedFormUrl) return scriptedFormUrl;
    const buildRequestUrl = BookSourceDataUrlSupport.buildRequestUrl(source, searchUrl, '1', keyword);
    if (buildRequestUrl) return buildRequestUrl;
    const qingtianUrl = this.buildQingtianSearchUrl(source, keyword, '1');
    if (qingtianUrl) return qingtianUrl;
    let url = searchUrl;
    url = this.stripLeadingJsUrl(url);
    if (url.startsWith('@js:')) {
      const fanqieMatch = url.match(/return\s+`([^`]*bookapi\/search\/page\/v\/[^`]*)`/);
      if (fanqieMatch) {
        url = fanqieMatch[1];
      }
      const assignMatch = url.match(/\burl\s*=\s*(["'])([\s\S]*?)\1\s*;/);
      if (assignMatch) {
        url = assignMatch[2];
      }
      const baseJoin = url.match(/baseUrl\s*\+\s*(".*?"|'.*?')/);
      if (baseJoin) {
        url = baseUrl + baseJoin[1].substring(1, baseJoin[1].length - 1);
        const optionMatch = searchUrl.match(/,\{[\s\S]*\}/);
        if (optionMatch && !url.includes(',{')) url += optionMatch[0];
      } else if (url.startsWith('@js:')) {
        const resultMatch = url.match(/result\s*=\s*["']([^"']+)["']/);
        const directUrlMatch = url.match(/["'](https?:\/\/[^"']+)["']/);
        const relativeOptionMatch = url.match(/["'](\/[^"']+,\{[\s\S]*?\})["']/);
        url = resultMatch ? resultMatch[1] : (relativeOptionMatch ? relativeOptionMatch[1] : (directUrlMatch ? directUrlMatch[1] : ''));
      }
    }
    url = this.applySourceTemplate(url, source);
    url = js.evalTemplate(url);
    // 清理残留模板
    url = url.replace(/\{\{[^}]+\}\}/g, '');
    return url;
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

  private async tryBuildScriptedFormSearchUrl(source: BookSource, keyword: string): Promise<string> {
    const script = source.searchUrl || '';
    if (!script.startsWith('@js:') || !script.includes('java.ajax') || !script.includes('input[name=act]')) {
      return '';
    }
    const baseUrl = BookUrlResolver.cleanBaseUrl(source.bookSourceUrl);
    const formBaseUrl = this.extractScriptBaseUrl(script, baseUrl);
    const appendPath = this.extractAppendedPath(script);
    if (!formBaseUrl || !appendPath) return '';

    const resp = await this.http.execute({
      url: formBaseUrl,
      method: 'GET',
      headers: this.parseSourceHeaders(source.header)
    });
    if (!resp.success || !resp.body) return '';

    const act = this.extractInputValue(resp.body, 'act');
    if (!act) return '';
    const submit = /\/www/i.test(formBaseUrl) ? '搜索 ' : '快速搜书';
    const body = `act=${encodeURIComponent(act)}&q=${encodeURIComponent(keyword)}&submit=${encodeURIComponent(submit)}`;
    const targetUrl = BookUrlResolver.resolve(appendPath, formBaseUrl);
    const option = JSON.stringify({
      body: body,
      method: 'POST',
      charset: 'GBK',
      headers: { Referer: formBaseUrl }
    });
    return `${targetUrl},${option}`;
  }

  private extractScriptBaseUrl(script: string, fallbackUrl: string): string {
    if (script.includes('source.key') || script.includes('source.getKey()')) return fallbackUrl;
    const literalMatch = script.match(/\burl\s*=\s*["'](https?:\/\/[^"']+)["']/);
    if (literalMatch && literalMatch[1]) return literalMatch[1];
    if (script.includes('baseUrl')) return fallbackUrl;
    return fallbackUrl;
  }

  private extractAppendedPath(script: string): string {
    const appendMatch = script.match(/\burl\s*\+=\s*["']([^"']+)["']/);
    if (appendMatch && appendMatch[1]) return appendMatch[1];
    const pathMatch = script.match(/["'](\/[^"']*search[^"']*)["']/i) ||
      script.match(/["'](\/[^"']*ss[^"']*)["']/i);
    return pathMatch && pathMatch[1] ? pathMatch[1] : '';
  }

  private extractInputValue(html: string, name: string): string {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const nameFirst = new RegExp(`<input\\b[^>]*\\bname=["']${escaped}["'][^>]*\\bvalue=["']([^"']*)["'][^>]*>`, 'i');
    const valueFirst = new RegExp(`<input\\b[^>]*\\bvalue=["']([^"']*)["'][^>]*\\bname=["']${escaped}["'][^>]*>`, 'i');
    const match = html.match(nameFirst) || html.match(valueFirst);
    return match && match[1] ? match[1] : '';
  }

  private parseSourceHeaders(header: string): Record<string, string> {
    if (!header) return {};
    try {
      return JSON.parse(header.replace(/'/g, '"')) as Record<string, string>;
    } catch (_) {
      const result: Record<string, string> = {};
      for (const line of header.split(/[\n\r]+/)) {
        const idx = line.indexOf(':');
        if (idx > 0) result[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
      return result;
    }
  }

  private buildQingtianSearchUrl(source: BookSource, keyword: string, page: string): string {
    const searchUrl = source.searchUrl || '';
    if (!searchUrl.includes('/search?title=${key}') || !searchUrl.includes('getArguments(source.getVariable()')) {
      return '';
    }
    const hosts = this.parseHostList(source.jsLib || searchUrl);
    const baseUrl = hosts.length > 0 ? hosts[0] : 'http://219.154.201.122:5006';
    const parsed = this.parseQingtianKeyword(keyword);
    const disabled = '0';
    return `${baseUrl}/search?title=${encodeURIComponent(parsed.title)}&tab=${encodeURIComponent(parsed.tab)}` +
      `&source=${encodeURIComponent(parsed.source)}&page=${encodeURIComponent(page)}&disabled_sources=${encodeURIComponent(disabled)}`;
  }

  private parseQingtianKeyword(keyword: string): { title: string, tab: string, source: string } {
    let title = keyword || '';
    let tab = '小说';
    let source = '全部';
    const prefix = title.length >= 2 ? title.substring(0, 2) : '';
    if (prefix === 'm:' || prefix === 'm：') {
      tab = '漫画';
      title = title.substring(2);
    } else if (prefix === 't:' || prefix === 't：') {
      tab = '听书';
      title = title.substring(2);
    } else if (prefix === 'd:' || prefix === 'd：') {
      tab = '短剧';
      title = title.substring(2);
    } else if (prefix === 'x:' || prefix === 'x：') {
      tab = '小说';
      title = title.substring(2);
    }
    const at = title.indexOf('@');
    if (at >= 0) {
      const nextSource = title.substring(at + 1).trim();
      title = title.substring(0, at);
      if (nextSource) source = nextSource;
    }
    return { title: title.trim(), tab: tab, source: source };
  }

  private parseHostList(jsLib: string): string[] {
    const hosts: string[] = [];
    const hostBlock = (jsLib || '').match(/\bhost\s*=\s*\[([\s\S]*?)\]/);
    const body = hostBlock ? hostBlock[1] : jsLib;
    const re = /["'](https?:\/\/[^"']+)["']/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(body)) !== null) {
      if (!hosts.includes(m[1])) hosts.push(m[1]);
    }
    return hosts;
  }

  private async fetchEncodedDataUrl(url: string, source: BookSource): Promise<{ url: string, statusCode: number, headers: Record<string, string>, body: string, success: boolean, error?: string }> {
    const root = await EncodedSourceUrl.requestJsonForDataUrl(this.http, url,
      BookSourceDataUrlSupport.sourceBackendHost(source));
    if (!root) {
      return { url: url, statusCode: 0, headers: {}, body: '', success: false, error: 'encoded data url request failed' };
    }
    return { url: url, statusCode: 200, headers: {}, body: JSON.stringify(root), success: true };
  }

  private stripLeadingJsUrl(url: string): string {
    const end = url.lastIndexOf('</js>');
    if (end >= 0) {
      const tail = url.substring(end + 5).trim();
      if (tail) return tail;
      const head = url.substring(0, end);
      const pathWithOption = head.match(/(\/[^"'`;]+,\{[\s\S]*?\})/);
      if (pathWithOption) return pathWithOption[1];
      const path = head.match(/(\/[A-Za-z0-9_./?=&%{}-]+)/);
      if (path) return path[1];
    }
    return url.replace(/<js>[\s\S]*?<\/js>/gi, '').trim();
  }

}
