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
        await this.fetchEncodedDataUrl(urlTemplate) : await au.fetch(urlTemplate);

      console.log('[SC] response:', source.bookSourceName, resp.statusCode, 'len:', resp.body?.length || 0);
      if (VerificationSupport.shouldRequestBrowserVerification(source, resp.body, resp.statusCode, source.searchUrl)) {
        const verifyUrl = VerificationSupport.pickVerificationUrl(source, urlTemplate, source.searchUrl);
        VerificationSupport.requestVerification(verifyUrl, `${source.bookSourceName} 验证`);
        console.warn('[SC] source needs browser verification:', source.bookSourceName, verifyUrl);
        return [];
      }
      if (!resp.success || !resp.body) return [];

      // 防止超大响应导致 OOM
      if (resp.body.length > 500000) return [];

      const baseUrl = BookUrlResolver.effectiveBase(resp, urlTemplate, source.bookSourceUrl);
      const rule = new AnalyzeRule(resp.body, baseUrl);
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
        if (sourceBackendHost) {
          ir.getContext().put('host', sourceBackendHost);
          ir.getContext().put('backend', sourceBackendHost);
        }
        const book = new SearchBook();
        book.name = ir.analyzeFirst(searchRule.name) || '';
        book.author = ir.analyzeFirst(searchRule.author) || '';
        book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source, ir.analyzeFirst(searchRule.coverUrl), baseUrl);
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
    url = js.evalTemplate(url);
    // 清理残留模板
    url = url.replace(/\{\{[^}]+\}\}/g, '');
    return url;
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

  private async fetchEncodedDataUrl(url: string): Promise<{ url: string, statusCode: number, headers: Record<string, string>, body: string, success: boolean, error?: string }> {
    const root = await EncodedSourceUrl.requestJsonForDataUrl(this.http, url);
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
