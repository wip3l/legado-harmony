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
import { BookFieldSanitizer } from '../../utils/BookFieldSanitizer';

export interface SearchProgress {
  done: number;
  total: number;
  results: SearchBook[];
  deltaResults?: SearchBook[];
  finished: boolean;
  status: string;
  needVerification?: boolean;
  verificationUrl?: string;
  verificationTitle?: string;
}

export type SearchCallback = (progress: SearchProgress) => void;

const MAX_SEARCH_CONCURRENCY = 32;
const SEARCH_PROGRESS_EMIT_INTERVAL_MS = 250;
const MAX_SEARCH_RESPONSE_BYTES = 4 * 1024 * 1024;
const ENABLE_SEARCH_DEBUG_LOG = false;

export interface SearchOptions {
  exactMatch?: boolean;
  exactMatchAuthor?: boolean;
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
    const safeCallback = (progress: SearchProgress): void => {
      try {
        callback(progress);
      } catch (e) {
        console.error('[SC] search progress callback failed:', e);
      }
    };
    const enabledSources = await appDb.getEnabledBookSources();
    const selectedGroups = this.normalizeSelectedGroups(options.sourceGroups || []);
    const sources = selectedGroups.length > 0 ?
      enabledSources.filter((source: BookSource) => selectedGroups.includes(this.normalizeGroupName(source.bookSourceGroup))) :
      enabledSources;
    if (sources.length === 0) {
      safeCallback({ done: 0, total: 0, results: [], finished: true, status: '没有符合设置的启用书源' });
      return [];
    }

    const all: SearchBook[] = [];
    let displayResultCount = 0;
    let done = 0;
    let nextIndex = 0;
    let lastProgressEmitAt = 0;
    let currentSourceLabel = '';
    let pendingDeltaResults: SearchBook[] = [];
    const workerCount = Math.min(this.concurrency, sources.length);

    const emitProgress = (force: boolean = false): void => {
      const now = Date.now();
      const hasDeltaResults = pendingDeltaResults.length > 0;
      if (!force && !hasDeltaResults && done < sources.length &&
        now - lastProgressEmitAt < SEARCH_PROGRESS_EMIT_INTERVAL_MS) {
        return;
      }
      lastProgressEmitAt = now;
      const verifyUrl = AppStorage.get<string>('pendingVerificationUrl') || '';
      const finished = done >= sources.length;
      const deltaResults = finished ? [] : pendingDeltaResults;
      pendingDeltaResults = [];
      safeCallback({
        done: done, total: sources.length,
        results: finished ? this.filterAndSortSearchResults(all, keyword, options) : [],
        deltaResults: deltaResults,
        finished: finished,
        status: verifyUrl ?
          `已搜索 ${done}/${sources.length}，当前：${currentSourceLabel || '准备中'}，找到 ${displayResultCount} 本；有书源需要网页验证` :
          `已搜索 ${done}/${sources.length}，当前：${currentSourceLabel || '准备中'}，找到 ${displayResultCount} 本`,
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

        currentSourceLabel = sources[sourceIndex].bookSourceName || `书源 ${sourceIndex + 1}`;
        AppStorage.setOrCreate('searchLastSource', currentSourceLabel);
        AppStorage.setOrCreate('searchLastSourceIndex', sourceIndex + 1);
        const books = await this.searchOne(sources[sourceIndex], keyword, options);
        if (this.cancelled) break;
        const displayBooks = this.filterSearchResults(books, keyword, options);

        done++;
        displayResultCount += displayBooks.length;
        pendingDeltaResults.push(...displayBooks);
        all.push(...books);
        emitProgress();
      }
    };

    const workers: Promise<void>[] = [];
    for (let i = 0; i < workerCount; i++) {
      workers.push(runWorker());
    }
    await Promise.all(workers);
    emitProgress(true);

    return this.filterAndSortSearchResults(all, keyword, options);
  }

  private async searchOne(source: BookSource, keyword: string, options: SearchOptions): Promise<SearchBook[]> {
    try {
      if (this.cancelled) return [];
      if (BookSourceDataUrlSupport.sourceUsesGySearch(source)) {
        const books = await BookSourceDataUrlSupport.search(this.http, source, keyword, 1, MAX_SEARCH_RESPONSE_BYTES);
        return this.sanitizeSearchBooks(books);
      }
      if (this.cancelled) return [];
      if (!source.searchUrl || !source.searchRule?.bookList || !source.searchRule?.name || !source.searchRule?.bookUrl) {
        if (ENABLE_SEARCH_DEBUG_LOG) {
          console.warn('[SC] skip source without search rules:', source.bookSourceName);
        }
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
      if (ENABLE_SEARCH_DEBUG_LOG) {
        console.log('[SC] search source:', source.bookSourceName, 'url:', urlTemplate);
      }
      const resp = EncodedSourceUrl.canHandle(urlTemplate) ?
        await this.fetchEncodedDataUrl(urlTemplate, source) : await au.fetch(urlTemplate, MAX_SEARCH_RESPONSE_BYTES);
      if (this.cancelled) return [];

      if (ENABLE_SEARCH_DEBUG_LOG) {
        console.log('[SC] response:', source.bookSourceName, resp.statusCode, 'len:', resp.body?.length || 0);
      }
      if (VerificationSupport.shouldRequestBrowserVerification(source, resp.body, resp.statusCode, source.searchUrl)) {
        const verifyUrl = VerificationSupport.pickVerificationUrl(source, urlTemplate, source.searchUrl);
        VerificationSupport.requestVerification(verifyUrl, `${source.bookSourceName} 验证`, source);
        if (ENABLE_SEARCH_DEBUG_LOG) {
          console.warn('[SC] source needs browser verification:', source.bookSourceName, verifyUrl);
        }
        return [];
      }
      if (!resp.success || !resp.body) return [];

      const baseUrl = BookUrlResolver.effectiveBase(resp, urlTemplate, source.bookSourceUrl);
      const rule = new AnalyzeRule(resp.body, baseUrl);
      this.seedSourceVariables(rule.getContext(), source);
      rule.setJsVar('key', encodeURIComponent(keyword));
      rule.setJsVar('searchKey', encodeURIComponent(keyword));
      rule.setJsVar('keyword', encodeURIComponent(keyword));
      rule.setJsVar('page', '1');
      const searchRule = source.searchRule;
      const items = rule.getElements(searchRule.bookList || '');
      if (this.cancelled) return [];
      if (ENABLE_SEARCH_DEBUG_LOG) {
        console.log('[SC] parsed list:', source.bookSourceName, 'rule:', searchRule.bookList, 'count:', items.length);
      }

      const books: SearchBook[] = [];
      const seenBookKeys = new Set<string>();
      const normalizedKeyword = this.normalizeSearchText(keyword);
      const sourceBackendHost = BookSourceDataUrlSupport.sourceBackendHost(source);
      for (const item of items) {
        if (this.cancelled) return [];
        const ir = new AnalyzeRule(item, baseUrl);
        this.seedSourceVariables(ir.getContext(), source);
        if (sourceBackendHost) {
          ir.getContext().put('host', sourceBackendHost);
          ir.getContext().put('backend', sourceBackendHost);
        }
        const book = new SearchBook();
        book.name = ir.analyzeFirst(searchRule.name) || '';
        book.author = ir.analyzeFirst(searchRule.author) || '';
        book.bookUrl = BookUrlResolver.resolve(ir.analyzeFirst(searchRule.bookUrl), baseUrl);
        this.fillSearchFallbackFields(source, ir, book, baseUrl, item);
        if (options.exactMatch) {
          if (!this.matchesExactSearch(this.normalizeSearchText(book.name), this.normalizeSearchText(book.author),
            normalizedKeyword, options)) {
            continue;
          }
        }

        book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrlFromItem(source,
          ir.analyzeFirst(searchRule.coverUrl), item, baseUrl);
        book.intro = ir.analyzeFirst(searchRule.intro) || '';
        book.kind = ir.analyzeFirst(searchRule.kind) || '';
        book.latestChapterTitle = ir.analyzeFirst(searchRule.lastChapter) || '';
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
        if (!book.bookUrl || /["']\s*\+\s*result|\bresult\s*\+\s*["']|@js:/.test(book.bookUrl) ||
          (/result/.test(searchRule.bookUrl || '') && /\+/.test(searchRule.bookUrl || ''))) {
          const repaired = this.repairResultConcatUrl(searchRule.bookUrl || '', ir, baseUrl);
          if (repaired) book.bookUrl = repaired;
        }
        const searchBookId = this.extractBookId(ir, item, book.bookUrl);
        const responseCoverUrl = BookSourceDataUrlSupport.normalizeCoverUrlFromResponse(source, resp.body, searchBookId,
          baseUrl);
        if (responseCoverUrl && this.shouldReplaceCover(book.coverUrl)) {
          book.coverUrl = responseCoverUrl;
          if (ENABLE_SEARCH_DEBUG_LOG) {
            console.log('[SC] cover from response:', source.bookSourceName, book.name, searchBookId);
          }
        }
        book.origin = source.bookSourceUrl;
        book.originName = source.bookSourceName;
        book.bookSourceComment = source.bookSourceComment;
        book.customOrder = source.customOrder;
        book.weight = source.weight;

        this.sanitizeSearchBook(book);
        const bookKey = `${book.origin || ''}::${book.bookUrl || ''}`;
        if (book.name && book.bookUrl && !seenBookKeys.has(bookKey)) {
          seenBookKeys.add(bookKey);
          if (ENABLE_SEARCH_DEBUG_LOG && books.length === 0) {
            console.log('[SC] 第一条结果:', book.name, book.bookUrl, 'from:', source.bookSourceName);
          }
          books.push(book);
        }
      }
      if (books.length === 0 && items.length > 0) {
        if (ENABLE_SEARCH_DEBUG_LOG) {
          console.warn('[SC] list matched but no valid book:', source.bookSourceName,
            'nameRule:', searchRule.name, 'urlRule:', searchRule.bookUrl,
            'firstItem:', items[0].substring(0, Math.min(items[0].length, 240)));
        }
      }
      return books;
    } catch (e) {
      if (ENABLE_SEARCH_DEBUG_LOG) {
        console.error('[SC] search failed:', source.bookSourceName, e);
      }
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

  private sanitizeSearchBook(book: SearchBook): void {
    book.name = this.cleanTextField(book.name, 120);
    book.author = this.cleanTextField(book.author, 120);
    book.kind = this.cleanTextField(book.kind, 240);
    book.intro = this.cleanTextField(book.intro, 1200);
    book.latestChapterTitle = this.cleanTextField(book.latestChapterTitle, 160);
    book.wordCount = this.cleanTextField(book.wordCount, 80);
    book.bookUrl = this.cleanUrlField(book.bookUrl, 2048);
    book.tocUrl = this.cleanUrlField(book.tocUrl, 2048);
    book.coverUrl = this.cleanUrlField(book.coverUrl, 4096);
    book.origin = this.cleanUrlField(book.origin, 2048);
    book.originName = this.cleanTextField(book.originName, 160);
    book.bookSourceComment = this.cleanTextField(book.bookSourceComment, 1200);
    book.variable = this.cleanJsonField(book.variable, 8192);
  }

  private sanitizeSearchBooks(books: SearchBook[]): SearchBook[] {
    const cleaned: SearchBook[] = [];
    const seen = new Set<string>();
    for (const book of books || []) {
      this.sanitizeSearchBook(book);
      if (!book.name || !book.bookUrl) continue;
      const key = `${book.origin || ''}::${book.bookUrl || ''}`;
      if (seen.has(key)) continue;
      seen.add(key);
      cleaned.push(book);
    }
    return cleaned;
  }

  private fillSearchFallbackFields(source: BookSource, ir: AnalyzeRule, book: SearchBook, baseUrl: string,
    item: string): void {
    const isChaoxing = this.isChaoxingSource(source);
    if (!book.name) {
      book.name = this.cleanFallbackTitle(ir.analyzeFirst('a@title') || ir.analyzeFirst('a@text') ||
        ir.analyzeFirst('span.sr-only@text') || ir.analyzeFirst('.sr-only@text'));
    }
    if (!book.name && isChaoxing) {
      book.name = this.cleanFallbackTitle(this.extractChaoxingTitle(item));
    }
    if (!book.bookUrl) {
      book.bookUrl = BookUrlResolver.resolve(ir.analyzeFirst('a@href') || ir.analyzeFirst('[href]@href'), baseUrl);
    }
    if (!book.bookUrl && isChaoxing) {
      const rawUrl = this.extractChaoxingUrl(item);
      if (rawUrl) {
        book.bookUrl = BookUrlResolver.resolve(rawUrl, baseUrl || source.bookSourceUrl);
      }
    }
    if (!book.bookUrl && isChaoxing) {
      const id = ir.analyzeFirst('input.save@value') || ir.analyzeFirst('input[name=checkDxidName]@value') ||
        this.extractChaoxingId(item);
      if (id) {
        book.bookUrl = BookUrlResolver.resolve(`/detail_${id}`, baseUrl || source.bookSourceUrl);
      }
    }
  }

  private cleanFallbackTitle(value: string): string {
    return (value || '')
      .replace(/^复选框\s*/, '')
      .replace(/Html|PDF下载|评审材料/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private isChaoxingSource(source: BookSource): boolean {
    const raw = `${source.bookSourceUrl || ''}\n${source.loginUrl || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}`.toLowerCase();
    return raw.includes('chaoxing.com');
  }

  private extractChaoxingTitle(item: string): string {
    const title = this.firstRegexGroup(item, /<a\b[^>]*\btitle\s*=\s*(["'])([\s\S]*?)\1/i, 2) ||
      this.firstRegexGroup(item, /<span\b[^>]*class\s*=\s*(["'])[^"']*\bsr-only\b[^"']*\1[^>]*>([\s\S]*?)<\/span>/i, 2) ||
      this.firstRegexGroup(item, /<a\b[^>]*>([\s\S]*?)<\/a>/i, 1);
    return this.decodeHtmlEntities(title.replace(/<[^>]+>/g, ' '));
  }

  private extractChaoxingUrl(item: string): string {
    return this.decodeHtmlEntities(this.firstRegexGroup(item, /<a\b[^>]*\bhref\s*=\s*(["'])([\s\S]*?)\1/i, 2));
  }

  private extractChaoxingId(item: string): string {
    return this.firstRegexGroup(item,
      /<input\b[^>]*(?:\bclass\s*=\s*(["'])[^"']*\bsave\b[^"']*\1|\bname\s*=\s*(["'])checkDxidName\2)[^>]*\bvalue\s*=\s*(["'])([\s\S]*?)\3/i, 4) ||
      this.firstRegexGroup(item,
        /<input\b[^>]*\bvalue\s*=\s*(["'])([\s\S]*?)\1[^>]*(?:\bclass\s*=\s*(["'])[^"']*\bsave\b[^"']*\3|\bname\s*=\s*(["'])checkDxidName\4)/i, 2);
  }

  private firstRegexGroup(text: string, pattern: RegExp, groupIndex: number): string {
    const match = (text || '').match(pattern);
    return match ? (match[groupIndex] || '').trim() : '';
  }

  private decodeHtmlEntities(value: string): string {
    return (value || '')
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/g, "'")
      .replace(/&#(\d+);/g, (_: string, code: string) => String.fromCharCode(parseInt(code)))
      .replace(/&#x([0-9a-f]+);/gi, (_: string, code: string) => String.fromCharCode(parseInt(code, 16)));
  }

  private cleanTextField(value: string, maxLength: number): string {
    const text = BookFieldSanitizer.clean(this.safeString(value));
    return text.length > maxLength ? text.substring(0, maxLength) : text;
  }

  private cleanUrlField(value: string, maxLength: number): string {
    const text = this.safeString(value).trim();
    if (!text || BookFieldSanitizer.isUnresolved(text)) return '';
    return text.length > maxLength ? text.substring(0, maxLength) : text;
  }

  private cleanJsonField(value: string, maxLength: number): string {
    const text = this.safeString(value).trim();
    return text.length > maxLength ? text.substring(0, maxLength) : text;
  }

  private safeString(value: Object | string | null | undefined): string {
    if (value === null || value === undefined) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    try {
      return JSON.stringify(value);
    } catch (_) {
      return '';
    }
  }

  private repairResultConcatUrl(rule: string, ir: AnalyzeRule, baseUrl: string): string {
    const jsIndex = String(rule || '').indexOf('@js:');
    if (jsIndex < 0) return '';
    const baseExpr = String(rule || '').substring(0, jsIndex).trim();
    const jsExpr = String(rule || '').substring(jsIndex + 4).trim();
    const baseValue = ir.analyzeFirst(baseExpr);
    if (!baseValue) return '';
    const prefixMatch = jsExpr.match(/^["']([\s\S]*?)["']\s*\+\s*result(?:\s*\+\s*["']([\s\S]*?)["'])?$/);
    const suffixMatch = jsExpr.match(/^result\s*\+\s*["']([\s\S]*?)["']$/);
    const headMatch = jsExpr.match(/^["']([\s\S]*?)["']\s*\+\s*result$/);
    if (prefixMatch) return BookUrlResolver.resolve(prefixMatch[1] + baseValue + (prefixMatch[2] || ''), baseUrl);
    if (suffixMatch) return BookUrlResolver.resolve(baseValue + suffixMatch[1], baseUrl);
    if (headMatch) return BookUrlResolver.resolve(headMatch[1] + baseValue, baseUrl);
    return '';
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
    const sorted = this.sortSearchResults(this.filterSearchResults(results, keyword, options), keyword);
    return sorted;
  }

  private filterSearchResults(results: SearchBook[], keyword: string, options: SearchOptions): SearchBook[] {
    if (!options.exactMatch) {
      return results;
    }
    const normalizedKeyword = this.normalizeSearchText(keyword);
    return results.filter((book: SearchBook) => {
      if (this.normalizeSearchText(book.name) === normalizedKeyword) {
        return true;
      }
      return options.exactMatchAuthor === true &&
        this.normalizeSearchText(book.author) === normalizedKeyword;
    });
  }

  private matchesExactSearch(normalizedName: string, normalizedAuthor: string, normalizedKeyword: string,
    options: SearchOptions): boolean {
    if (normalizedName === normalizedKeyword) {
      return true;
    }
    return options.exactMatchAuthor === true && normalizedAuthor === normalizedKeyword;
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
    ctx.put('source.jsLib', source.jsLib || '');
    ctx.put('jsLib', source.jsLib || '');
    if (!ctx.has('source.variable')) ctx.put('source.variable', source.variableComment || '');
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
      BookSourceDataUrlSupport.sourceBackendHost(source), MAX_SEARCH_RESPONSE_BYTES);
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
