import { BookSource, SearchBook } from '../../model/data/Book';
import { appDb } from '../../model/data/AppDatabase';
import { HttpClient } from '../http/HttpClient';
import { AnalyzeUrl } from '../rule/AnalyzeUrl';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { JsRuntime } from '../rule/JsRuntime';
import { VerificationSupport } from '../http/VerificationSupport';

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

export class SearchCoordinator {
  private http: HttpClient;
  private concurrency: number;
  private cancelled: boolean = false;

  constructor(concurrency: number = 4) {
    this.http = new HttpClient(8000);
    this.concurrency = concurrency;
  }

  cancel(): void {
    this.cancelled = true;
  }

  async search(keyword: string, callback: SearchCallback): Promise<SearchBook[]> {
    this.cancelled = false;
    VerificationSupport.clearVerification();
    const sources = await appDb.getEnabledBookSources();
    if (sources.length === 0) {
      callback({ done: 0, total: 0, results: [], finished: true, status: '没有启用的书源' });
      return [];
    }

    const all: SearchBook[] = [];
    let done = 0;

    // 分批并发
    for (let i = 0; i < sources.length; i += this.concurrency) {
      if (this.cancelled) break;
      const batch = sources.slice(i, i + this.concurrency);
      const tasks = batch.map(s => this.searchOne(s, keyword));

      const batchResults = await Promise.all(tasks);
      for (const books of batchResults) {
        done++;
        all.push(...books);
        const verifyUrl = AppStorage.get<string>('pendingVerificationUrl') || '';
        callback({
          done: done, total: sources.length, results: [...all],
          finished: done >= sources.length,
          status: verifyUrl ? `已搜索 ${done}/${sources.length}，找到 ${all.length} 本；有书源需要网页验证` :
            `已搜索 ${done}/${sources.length}，找到 ${all.length} 本`,
          needVerification: verifyUrl.length > 0,
          verificationUrl: verifyUrl,
          verificationTitle: AppStorage.get<string>('pendingVerificationTitle') || '网页验证'
        });
      }
    }

    return all;
  }

  private async searchOne(source: BookSource, keyword: string): Promise<SearchBook[]> {
    try {
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
      const urlTemplate = this.evalAndBuild(js, source.searchUrl, source.bookSourceUrl);
      console.log('[SC] search source:', source.bookSourceName, 'url:', urlTemplate);
      const resp = await au.fetch(urlTemplate);

      console.log('[SC] response:', source.bookSourceName, resp.statusCode, 'len:', resp.body?.length || 0);
      if (VerificationSupport.isChallengeResponse(resp.body) ||
        resp.statusCode === 401 || resp.statusCode === 403) {
        const verifyUrl = VerificationSupport.pickVerificationUrl(source, urlTemplate, source.searchUrl);
        VerificationSupport.requestVerification(verifyUrl, `${source.bookSourceName} 验证`);
        console.warn('[SC] source needs browser verification:', source.bookSourceName, verifyUrl);
        return [];
      }
      if (!resp.success || !resp.body) return [];

      // 防止超大响应导致 OOM
      if (resp.body.length > 500000) return [];

      const rule = new AnalyzeRule(resp.body, source.bookSourceUrl);
      const searchRule = source.searchRule;
      const items = rule.getElements(searchRule.bookList || '');
      console.log('[SC] parsed list:', source.bookSourceName, 'rule:', searchRule.bookList, 'count:', items.length);

      const books: SearchBook[] = [];
      for (const item of items) {
        const ir = new AnalyzeRule(item, source.bookSourceUrl);
        const book = new SearchBook();
        book.name = ir.analyzeFirst(searchRule.name) || '';
        book.author = ir.analyzeFirst(searchRule.author) || '';
        book.coverUrl = ir.analyzeFirst(searchRule.coverUrl) || '';
        book.intro = ir.analyzeFirst(searchRule.intro) || '';
        book.kind = ir.analyzeFirst(searchRule.kind) || '';
        book.latestChapterTitle = ir.analyzeFirst(searchRule.lastChapter) || '';
        book.bookUrl = this.resolve(ir.analyzeFirst(searchRule.bookUrl), source.bookSourceUrl);
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
          if (book.bookUrl && book.bookUrl.startsWith('/')) {
            book.bookUrl = this.resolve(book.bookUrl, source.bookSourceUrl);
          }
        }
        book.origin = source.bookSourceUrl;
        book.originName = source.bookSourceName;

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

  private evalAndBuild(js: JsRuntime, searchUrl: string, baseUrl: string): string {
    if (!searchUrl) return `${baseUrl}/search?q={{key}}`;
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
    url = js.evalTemplate(url);
    // 清理残留模板
    url = url.replace(/\{\{[^}]+\}\}/g, '');
    return url;
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
