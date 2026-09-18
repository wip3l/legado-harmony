import { BookSource, ExploreRule, SearchBook } from '../../model/data/Book';
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
import { BookSourceScriptRunner } from './BookSourceScriptRunner';
import { BookSourceMetadataSupport } from './BookSourceMetadataSupport';
import { BookTypeSupport } from './BookTypeSupport';
import { BookSourceRuntimeRouter, SourceRuntimeStage } from './BookSourceRuntimeRouter';
import { BookSourceStageWebRuntime, StageWebRuntimeRequest } from './BookSourceStageWebRuntime';
import { BookSourceStageRuleSupport } from './BookSourceStageRuleSupport';
import { RuleExecutionService } from '../rule/RuleExecutionService';
import { RuleBatchExecutionRequest, RuleBatchExecutionResult, RuleFieldRequest } from '../rule/RuleExecutionModels';
import { CooperativeScheduler } from '../concurrency/CooperativeScheduler';
import { BookFieldSanitizer } from '../../utils/BookFieldSanitizer';
import { QuickJsObservationContext } from '../script/QuickJsRuntimeStatus';
import { RuleExecutionTarget, RuleValue } from '../rule/RuleValue';
import { BookSourceDebugContext } from './BookSourceDebugModels';

export interface ExploreEntry {
  title: string;
  url: string;
  sourceUrl: string;
  sourceName: string;
  groupTitle?: string;
}

export interface ExploreSourceOption {
  sourceName: string;
  sourceUrl: string;
  sourceGroup: string;
  platforms: string[];
}

export interface ExploreFilterGroup {
  title: string;
  options: string[];
  selected: string;
}

interface ExploreUrlItem {
  title?: string;
  url?: string;
  name?: string;
  type?: string;
  chars?: Object[];
  default?: Object;
  action?: string;
}

class ExplorePlatformSelector {
  labels: string[] = [];
  values: string[] = [];
  actions: string[] = [];
  parameter: string = '';
  mode: string = '';
  currentLabel: string = '';
}

export class ExploreCoordinator {
  private http: HttpClient = new HttpClient(10000);
  private noticeMessage: string = '';
  private platformSelectors: Record<string, ExplorePlatformSelector> = {};
  private filterSelectors: Record<string, ExplorePlatformSelector[]> = {};
  // Menu scripts run 2-8 network requests each through the serial script runtime. The explore
  // tab re-derives entries on every tab switch and source switch, so cache the parsed menu per
  // source + platform + variable state; the cache only skips the script, not content loading.
  private menuCache: Record<string, { entries: ExploreEntry[]; cachedAt: number }> = {};
  private menuCacheRevision: number = 0;

  getNoticeMessage(): string {
    return this.noticeMessage;
  }

  /** Drops cached explore menus (source saved, filter mutated, manual refresh). */
  clearExploreMenuCache(): void {
    this.menuCache = {};
    this.menuCacheRevision++;
  }

  private menuCacheKey(source: BookSource, platform: string): string {
    return `${source.bookSourceUrl}|${platform || ''}|r${this.menuCacheRevision}` +
      `|v${this.stringHash(source.variable || '')}|e${this.stringHash(source.exploreUrl || '')}`;
  }

  private stringHash(value: string): string {
    let hash = 5381;
    for (let index = 0; index < value.length; index++) {
      hash = ((hash << 5) + hash + value.charCodeAt(index)) | 0;
    }
    return `${hash >>> 0}`;
  }

  private storeMenuCache(key: string, entries: ExploreEntry[]): void {
    const keys = Object.keys(this.menuCache);
    // Small LRU cap: each entry list is a few hundred bytes.
    while (keys.length >= 24) {
      const oldest = keys.shift();
      if (!oldest) break;
      delete this.menuCache[oldest];
    }
    this.menuCache[key] = { entries: entries, cachedAt: Date.now() };
  }

  async getExploreSources(): Promise<ExploreSourceOption[]> {
    const sources = await appDb.getEnabledBookSourcesForExplore();
    const options: ExploreSourceOption[] = [];
    for (const source of sources) {
      if (!source.enabledExplore || !source.exploreUrl) continue;
      let platforms: string[] = [];
      const loginSelector = this.parseLoginPlatformSelector(source);
      if (!this.usesNativeExploreFilters(source) && loginSelector.labels.length > 0) {
        this.platformSelectors[source.bookSourceUrl] = loginSelector;
        platforms = loginSelector.labels;
      } else if (BookSourceDataUrlSupport.sourceUsesGyExplore(source)) {
        platforms = await BookSourceDataUrlSupport.getExplorePlatforms(this.http, source);
      }
      options.push({
        sourceName: source.bookSourceName,
        sourceUrl: source.bookSourceUrl,
        sourceGroup: (source.bookSourceGroup || '').trim(),
        platforms: platforms
      });
    }
    return options;
  }

  async getEntries(platform: string = '', sourceUrl: string = '',
    debugContext: BookSourceDebugContext | null = null): Promise<ExploreEntry[]> {
    this.noticeMessage = '';
    const sources = await appDb.getEnabledBookSourcesForExplore();
    const entries: ExploreEntry[] = [];
    for (const source of sources) {
      if (!source.enabledExplore || !source.exploreUrl) continue;
      if (sourceUrl && source.bookSourceUrl !== sourceUrl) continue;
      if (!source.variable && this.requiresSourceVariable(source)) {
        const hint = (source.variableComment || '').trim();
        this.noticeMessage = hint ? `请先在书源编辑中填写书源变量：${hint}` :
          '请先在书源编辑中填写书源变量（共享 Token）';
        continue;
      }
      const exploreRule = this.effectiveExploreRule(source);
      if (!exploreRule.bookList || !exploreRule.name || !exploreRule.bookUrl) {
        console.warn('[ExploreCoordinator] skip source without explore rules:', source.bookSourceName);
        continue;
      }
      const parsed = await this.parseExploreUrl(source, platform, debugContext);
      entries.push(...parsed);
    }
    return entries;
  }

  async explore(entry: ExploreEntry, page: number = 1, maxItems: number = 0,
    debugContext: BookSourceDebugContext | null = null): Promise<SearchBook[]> {
    this.noticeMessage = '';
    const source = await appDb.getBookSource(entry.sourceUrl);
    if (!source) return [];
    try {
      VerificationSupport.clearVerification();
      const au = new AnalyzeUrl(source, this.http);
      const reqUrl = await this.buildUrl(source, entry.url, page, debugContext);
      if (!reqUrl || /^\s*@?js:/i.test(reqUrl) ||
        (!/^https?:\/\//i.test(reqUrl) && !/^data:/i.test(reqUrl))) {
        console.warn('[ExploreCoordinator] invalid explore request:', source.bookSourceName,
          'entry:', (entry.url || '').substring(0, 600), 'built:', (reqUrl || '').substring(0, 600));
        this.noticeMessage = '发现地址脚本未能生成有效请求地址';
        return [];
      }
      console.info('[ExploreCoordinator] explore:', `${entry.sourceName}/${entry.title}`, reqUrl);
      let resp = EncodedSourceUrl.canHandle(reqUrl) ?
        await this.fetchEncodedDataUrl(reqUrl, source) : await au.fetch(reqUrl, undefined, debugContext);
      const bodyJs = au.getConfig().bodyJs || '';
      if (bodyJs) {
        const scriptedBody = await this.executeResponseBodyScript(source, bodyJs, resp.body || '',
          resp.url || reqUrl, page, debugContext);
        if (scriptedBody) {
          resp = { ...resp, body: scriptedBody, success: true, statusCode: 200 };
        }
      }
      console.info('[ExploreCoordinator] response:', resp.statusCode, 'len:', resp.body?.length || 0, 'url:', resp.url);
      if (VerificationSupport.shouldRequestBrowserVerification(source, resp.body, resp.statusCode, entry.url)) {
        const verifyUrl = VerificationSupport.pickVerificationUrl(source, reqUrl, entry.url);
        VerificationSupport.requestVerification(verifyUrl, `${source.bookSourceName} 验证`, source);
        console.warn('[ExploreCoordinator] source needs browser verification:', source.bookSourceName, verifyUrl);
        return [];
      }
      if (!resp.success || !resp.body) {
        console.warn('[ExploreCoordinator] empty response:', resp.statusCode, resp.error || '');
        this.noticeMessage = !resp.success ? (resp.statusCode > 0 ?
          `发现接口请求失败（HTTP ${resp.statusCode}）` : `发现接口请求失败：${resp.error || '网络异常'}`) :
          '发现接口返回空响应';
        return [];
      }

      const declaredFailure = this.responseFailureMessage(resp.body);
      if (declaredFailure) {
        const loginHint = (source.loginUrl || source.loginUi || '').trim() ? '，可能需要重新登录' : '';
        this.noticeMessage = `发现接口返回失败${loginHint}：${declaredFailure}`;
        console.warn('[ExploreCoordinator] response declared failure:', source.bookSourceName, declaredFailure);
        return [];
      }

      const baseUrl = BookUrlResolver.effectiveBase(resp, reqUrl, source.bookSourceUrl);
      const rule = new AnalyzeRule(resp.body, baseUrl);
      this.seedSourceVariables(rule.getContext(), source);
      const encodedVariables = EncodedSourceUrl.scalarVariables(reqUrl);
      for (const key in encodedVariables) rule.getContext().put(key, encodedVariables[key]);
      const exploreRule = this.effectiveExploreRule(source);
      const stageItems = await BookSourceStageRuleSupport.getElements(source, resp.body, baseUrl,
        exploreRule.bookList || '', SourceRuntimeStage.EXPLORE, '', 8 * 1024 * 1024,
        16 * 1024 * 1024, encodedVariables);
      const typedItems = stageItems === null ?
        rule.execute(exploreRule.bookList || '', RuleExecutionTarget.ELEMENTS) :
        stageItems.map((item: string): RuleValue => RuleValue.fromExternal(item));
      const items = typedItems.map((item: RuleValue): string => item.asString());
      if (items.length === 0) this.noticeMessage = '发现接口已有响应，但列表规则未匹配到内容';
      console.info('[ExploreCoordinator] parsed list:', source.bookSourceName, 'rule:', exploreRule.bookList, 'count:', items.length);
      // Capability validation only needs a representative book. Avoid parsing a 100+ item page
      // synchronously when the caller explicitly supplies a small validation limit.
      const parseTypedItems = maxItems > 0 ? typedItems.slice(0, Math.max(1, maxItems)) : typedItems;
      const parseItems = parseTypedItems.map((item: RuleValue): string => item.asString());
      const books: SearchBook[] = [];
      const sourceBackendHost = BookSourceDataUrlSupport.sourceBackendHost(source);
      const fieldRequest = new RuleBatchExecutionRequest();
      fieldRequest.source = source;
      fieldRequest.stage = SourceRuntimeStage.EXPLORE;
      fieldRequest.ownerId = `explore_${Date.now()}_${source.bookSourceUrl}`;
      fieldRequest.typedContents = parseTypedItems;
      fieldRequest.contents = parseItems;
      fieldRequest.baseUrl = baseUrl || source.bookSourceUrl;
      fieldRequest.fields = [
        new RuleFieldRequest('name', exploreRule.name || ''),
        new RuleFieldRequest('author', exploreRule.author || ''),
        new RuleFieldRequest('bookUrl', this.applySimpleSourceUrlConstants(exploreRule.bookUrl || '', source.jsLib || ''), true),
        new RuleFieldRequest('coverUrl', this.applySimpleSourceUrlConstants(exploreRule.coverUrl || '', source.jsLib || '')),
        new RuleFieldRequest('intro', exploreRule.intro || ''),
        new RuleFieldRequest('kind', exploreRule.kind || ''),
        new RuleFieldRequest('status', exploreRule.status || ''),
        new RuleFieldRequest('lastChapter', exploreRule.lastChapter || ''),
        new RuleFieldRequest('wordCount', exploreRule.wordCount || ''),
        new RuleFieldRequest('updateTime', exploreRule.updateTime || '')
      ];
      if (sourceBackendHost) {
        fieldRequest.contextValues['host'] = sourceBackendHost;
        fieldRequest.contextValues['backend'] = sourceBackendHost;
      }
      for (const key in encodedVariables) fieldRequest.contextValues[key] = encodedVariables[key];
      fieldRequest.timeoutMs = 30000;
      fieldRequest.debugContext = debugContext;
      let fieldBatch = new RuleBatchExecutionResult();
      try {
        fieldBatch = await RuleExecutionService.get().executeBatch(fieldRequest);
      } finally {
        RuleExecutionService.get().clearOwner(fieldRequest.ownerId);
      }
      if (fieldBatch.cancelled) return [];
      if (fieldBatch.errors.length > 0) {
        console.warn('[ExploreCoordinator] unified field errors:', source.bookSourceName,
          fieldBatch.errors.join('; '));
      }
      // Sources declare a page's media type from their own bookUrl scripts (source.put('type',…)
      // per explore category). Honor that decision so audio/comic categories open in the right
      // reader mode instead of defaulting to text until some later rule happens to set it.
      const runtimeMediaType = this.readSourceRuntimeMediaType(source);
      const parsingSlice = CooperativeScheduler.createTimeSlice();

      for (let itemIndex = 0; itemIndex < parseItems.length; itemIndex++) {
        if (itemIndex > 0) await parsingSlice.checkpoint();
        const item = parseItems[itemIndex];
        const ir = new AnalyzeRule(item, baseUrl);
        this.seedSourceVariables(ir.getContext(), source);
        if (sourceBackendHost) {
          ir.getContext().put('host', sourceBackendHost);
          ir.getContext().put('backend', sourceBackendHost);
        }
        const book = new SearchBook();
        const fieldValues = itemIndex < fieldBatch.values.length ? fieldBatch.values[itemIndex] : {};
        const sourceApiRecord = this.parseExploreJsonRecord(item);
        book.name = BookFieldSanitizer.clean(fieldValues['name'] || '');
        if (!book.name && sourceApiRecord) {
          book.name = BookFieldSanitizer.clean(this.exploreRecordValue(sourceApiRecord,
            ['name', 'bookName', 'book_name', 'novelName', 'novel_name', 'title']));
        }
        book.author = BookFieldSanitizer.clean(fieldValues['author'] || '');
        if (!book.author && sourceApiRecord) {
          book.author = BookFieldSanitizer.clean(this.exploreRecordValue(sourceApiRecord,
            ['author', 'authorName', 'author_name', 'writer']));
        }
        book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrlFromItem(source,
          fieldValues['coverUrl'] || '', item, baseUrl);
        book.intro = BookFieldSanitizer.clean(fieldValues['intro'] || '');
        if (!book.intro && sourceApiRecord) {
          book.intro = BookFieldSanitizer.clean(this.exploreRecordValue(sourceApiRecord,
            ['desc', 'intro', 'description', 'abstract', 'summary', 'book_desc', 'book_intro',
              'bookDesc', 'bookIntro', 'bookAbstract', 'bookDescription', 'book_abstract',
              'book_description', 'introduction', 'synopsis', 'remark', 'content_desc', 'brief']));
        }
        book.kind = BookFieldSanitizer.clean(fieldValues['kind'] || '');
        if (!book.kind && sourceApiRecord) {
          book.kind = [
            this.exploreRecordValue(sourceApiRecord, ['category', 'categoryName', 'category_name']),
            this.exploreRecordValue(sourceApiRecord, ['subCategory', 'subcategory'])
          ].map((value: string): string => value.trim()).filter((value: string): boolean => !!value).join(' ');
        }
        book.status = BookFieldSanitizer.clean(fieldValues['status'] || '');
        if (!book.status && sourceApiRecord) {
          book.status = BookFieldSanitizer.clean(this.exploreRecordValue(sourceApiRecord,
            ['status', 'state', 'serialStatus']));
        }
        book.latestChapterTitle = BookFieldSanitizer.clean(fieldValues['lastChapter'] || '');
        if (!book.latestChapterTitle && sourceApiRecord) {
          book.latestChapterTitle = BookFieldSanitizer.clean(this.exploreRecordValue(sourceApiRecord,
            ['lastChapter', 'lastChapterName', 'latestChapterTitle', 'latestChapter', 'lastChapterTitle']));
        }
        book.wordCount = BookFieldSanitizer.clean(fieldValues['wordCount'] || '');
        if (!book.wordCount && sourceApiRecord) {
          book.wordCount = BookFieldSanitizer.clean(this.exploreRecordValue(sourceApiRecord,
            ['wordsCount', 'wordCount', 'word_count']));
        }
        book.updateTime = BookFieldSanitizer.clean(fieldValues['updateTime'] || '');
        if (!book.updateTime && sourceApiRecord) {
          book.updateTime = BookFieldSanitizer.clean(this.exploreRecordValue(sourceApiRecord,
            ['updateTime', 'updatedAt', 'lastUpdateTime', 'lastUpdated']));
        }
        book.bookUrl = BookUrlResolver.resolveScalar(fieldValues['bookUrl'] || '', baseUrl);
        // Explore rules use the same Legado field grammar as search rules. Some sources (notably
        // API-backed sources such as 企点小说) return a JSONPath/result expression from the batch
        // evaluator on the first pass; do the same scalar/fallback repair used by search so the
        // detail route never receives an unevaluated expression.
        book.bookUrl = this.repairExploreBookUrl(exploreRule.bookUrl || '', ir, item, book.bookUrl, baseUrl);
        book.variable = itemIndex < fieldBatch.contextValues.length ? fieldBatch.contextValues[itemIndex] :
          ir.getContext().toPersistentJson();
        book.origin = source.bookSourceUrl;
        BookSourceMetadataSupport.applySearchBook(source, book, [book.bookUrl]);
        if (!Number(book.type) && runtimeMediaType) book.type = runtimeMediaType;
        this.sanitizeExploreBook(book);

        if (book.name && book.bookUrl && !books.some(b => b.bookUrl === book.bookUrl && b.origin === book.origin)) {
          books.push(book);
        }
      }
      if (books.length > 0) {
        console.info('[ExploreCoordinator] first book:', books[0].name, books[0].bookUrl);
      } else if (parseItems.length > 0) {
        this.noticeMessage = '发现列表已匹配，但书名或详情地址解析失败';
        console.warn('[ExploreCoordinator] list matched but no valid book:', source.bookSourceName,
          'nameRule:', exploreRule.name, 'urlRule:', exploreRule.bookUrl,
          'firstItem:', parseItems[0].substring(0, Math.min(parseItems[0].length, 240)));
      }
      return books;
    } catch (e) {
      console.error('[ExploreCoordinator] explore failed:', e);
      const message = e instanceof Error ? e.message : String(e || '');
      this.noticeMessage = message ? `发现解析异常：${message}` : '发现解析异常';
      return [];
    }
  }

  private parseExploreJsonRecord(value: string): Record<string, Object> | null {
    let current: Object;
    try {
      current = JSON.parse(value || '{}') as Object;
    } catch (_) {
      return null;
    }
    // API-backed explore rules may emit each item as a quoted JSON object.
    for (let depth = 0; depth < 2 && typeof current === 'string'; depth++) {
      try {
        current = JSON.parse(current as string) as Object;
      } catch (_) {
        return null;
      }
    }
    if (!current || typeof current !== 'object' || Array.isArray(current)) return null;
    return current as Record<string, Object>;
  }

  private exploreRecordValue(value: Object | null | undefined, keys: string[], depth: number = 0): string {
    if (!value || typeof value !== 'object' || depth > 5) return '';
    if (Array.isArray(value)) {
      for (const item of value as Object[]) {
        const found = this.exploreRecordValue(item, keys, depth + 1);
        if (found) return found;
      }
      return '';
    }
    const record = value as Record<string, Object>;
    const wanted = keys.map((key: string): string => key.toLowerCase());
    for (const key of Object.keys(record)) {
      if (!wanted.includes(key.toLowerCase())) continue;
      const candidate = record[key];
      if (candidate === undefined || candidate === null || typeof candidate === 'object') continue;
      const text = String(candidate).trim();
      if (text) return text;
    }
    for (const key of Object.keys(record)) {
      const found = this.exploreRecordValue(record[key], keys, depth + 1);
      if (found) return found;
    }
    return '';
  }

  private sanitizeExploreBook(book: SearchBook): void {
    book.name = this.cleanExploreText(book.name, 120);
    book.author = this.cleanExploreText(book.author, 120);
    book.kind = this.cleanExploreText(book.kind, 240);
    book.status = this.cleanExploreText(book.status, 120);
    // Keep the route payload bounded just like search results. Long API descriptions can otherwise
    // be dropped by router parameter serialization, which appears in the detail page as an empty intro.
    book.intro = this.cleanExploreText(book.intro, 1200);
    book.latestChapterTitle = this.cleanExploreText(book.latestChapterTitle, 160);
    book.wordCount = this.cleanExploreText(book.wordCount, 80);
    book.updateTime = this.cleanExploreText(book.updateTime, 80);
    book.bookUrl = BookUrlResolver.scalar(book.bookUrl);
    book.tocUrl = BookUrlResolver.scalar(book.tocUrl);
    book.coverUrl = BookUrlResolver.scalar(book.coverUrl);
    book.origin = BookUrlResolver.scalar(book.origin);
    book.originName = this.cleanExploreText(book.originName, 160);
    book.bookSourceComment = this.cleanExploreText(book.bookSourceComment, 1200);
  }

  private cleanExploreText(value: string, maxLength: number): string {
    const cleaned = BookFieldSanitizer.clean(value || '');
    return cleaned.length > maxLength ? cleaned.substring(0, maxLength) : cleaned;
  }

  /** Resolve URL constants declared by a source's jsLib without executing unrelated library code. */
  /**
   * The runtime state a source script wrote for the current page (type=audio/comic/novel/…)
   * survives in the source's persisted login-info bucket; the batch evaluator above has already
   * run the bookUrl script that produced it.
   */
  private readSourceRuntimeMediaType(source: BookSource): number {
    try {
      const loginInfo = JSON.parse(source.loginInfo || '{}') as Record<string, Object>;
      let runtime = loginInfo['__legadoHarmonyRuntime'];
      if (typeof runtime === 'string') runtime = JSON.parse(runtime) as Object;
      const state = runtime && typeof runtime === 'object' && !Array.isArray(runtime) ?
        (runtime as Record<string, Object>)['source'] : null;
      const value = state && typeof state === 'object' && !Array.isArray(state) ?
        String((state as Record<string, Object>)['type'] || '') : '';
      return BookTypeSupport.typeFromTab(value);
    } catch (_) {
      return 0;
    }
  }

  private applySimpleSourceUrlConstants(url: string, jsLib: string): string {
    if (!url.includes('{{') || !jsLib) return url;
    const constants: Record<string, string> = {};
    const declaration = /(?:^|[\r\n])\s*(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(['"])(https?:\/\/[^'"\r\n]+)\2\s*;?/g;
    let match: RegExpExecArray | null;
    while ((match = declaration.exec(jsLib)) !== null) {
      const name = match[1] || '';
      const value = match[3] || '';
      if (name && value) constants[name] = value;
    }
    return url.replace(/\{\{\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\}\}/g,
      (placeholder: string, name: string): string => constants[name] || placeholder);
  }

  private repairExploreBookUrl(rule: string, ir: AnalyzeRule, item: string,
    currentUrl: string, baseUrl: string): string {
    let value = BookUrlResolver.resolveScalar(currentUrl || '', baseUrl);
    const unresolved = !value || BookFieldSanitizer.isUnresolved(value) ||
      /["']\s*\+\s*result|result\s*\+\s*["']|@js:/i.test(value);
    if (!unresolved) return value;

    // Preserve source-defined URL composition (prefix + result, result + suffix) before trying
    // generic JSON field fallbacks; otherwise a raw numeric book id could be mistaken for a path.
    const composed = this.repairExploreConcatUrl(rule, ir, baseUrl);
    if (composed) return composed;

    const candidates: string[] = [
      ir.analyzeFirst('bookUrl'), ir.analyzeFirst('url'), ir.analyzeFirst('link'),
      ir.analyzeFirst('href'), ir.analyzeFirst('_id'), ir.analyzeFirst('id'),
      ir.getString('a@href', true), ir.getString('[href]@href', true)
    ];
    for (const candidate of candidates) {
      const repaired = BookUrlResolver.resolveScalar(candidate || '', baseUrl);
      if (repaired && !BookFieldSanitizer.isUnresolved(repaired)) {
        value = repaired;
        break;
      }
    }
    if (!value || BookFieldSanitizer.isUnresolved(value)) {
      try {
        const raw = JSON.parse(item || '{}') as Record<string, Object>;
        for (const key of ['bookUrl', 'url', 'link', 'href', 'book_id', 'bookId', 'id', 'nid', 'enid']) {
          const candidate = BookUrlResolver.resolveScalar(String(raw[key] || ''), baseUrl);
          if (candidate && !BookFieldSanitizer.isUnresolved(candidate)) {
            value = candidate;
            break;
          }
        }
      } catch (_) {
      }
    }
    return BookUrlResolver.resolveScalar(value || '', baseUrl);
  }

  private repairExploreConcatUrl(rule: string, ir: AnalyzeRule, baseUrl: string): string {
    const jsIndex = String(rule || '').indexOf('@js:');
    if (jsIndex < 0) return '';
    const baseExpr = String(rule || '').substring(0, jsIndex).trim();
    const jsExpr = String(rule || '').substring(jsIndex + 4).trim();
    const baseValue = ir.analyzeFirst(baseExpr, false);
    if (!baseValue) return '';
    const prefixMatch = jsExpr.match(/^["']([\s\S]*?)["']\s*\+\s*result(?:\s*\+\s*["']([\s\S]*?)["'])?$/);
    const suffixMatch = jsExpr.match(/^result\s*\+\s*["']([\s\S]*?)["']$/);
    const headMatch = jsExpr.match(/^["']([\s\S]*?)["']\s*\+\s*result$/);
    if (prefixMatch) return BookUrlResolver.resolve(prefixMatch[1] + baseValue + (prefixMatch[2] || ''), baseUrl);
    if (suffixMatch) return BookUrlResolver.resolve(baseValue + suffixMatch[1], baseUrl);
    if (headMatch) return BookUrlResolver.resolve(headMatch[1] + baseValue, baseUrl);
    return '';
  }

  getDiscoveredPlatforms(sourceUrl: string): string[] {
    const selector = this.platformSelectors[sourceUrl];
    return selector ? selector.labels.slice() : [];
  }

  getDiscoveredFilters(sourceUrl: string): ExploreFilterGroup[] {
    const selectors = this.filterSelectors[sourceUrl] || [];
    return selectors.map((selector: ExplorePlatformSelector): ExploreFilterGroup => ({
      title: selector.parameter || '',
      options: selector.labels.slice(),
      selected: selector.currentLabel
    }));
  }

  async applyExploreFilter(sourceUrl: string, title: string, selection: string): Promise<boolean> {
    const source = await appDb.getBookSource(sourceUrl);
    if (!source) return false;
    const selectors = this.filterSelectors[sourceUrl] || [];
    const selector = selectors.find((item: ExplorePlatformSelector): boolean => item.parameter === title);
    if (!selector || !selection || selector.currentLabel === selection) return !!selector;
    return await this.executeExploreSelector(source, selector, selection);
  }

  private async parseExploreUrl(source: BookSource, platform: string = '',
    debugContext: BookSourceDebugContext | null = null): Promise<ExploreEntry[]> {
    const entries: ExploreEntry[] = [];
    const raw = source.exploreUrl.trim();
    if (!raw) return entries;

    if (raw.startsWith('@js:') || raw.startsWith('js:') || /^<js>[\s\S]*<\/js>$/i.test(raw)) {
      const menuKey = this.menuCacheKey(source, platform);
      const cached = this.menuCache[menuKey];
      if (cached && Date.now() - cached.cachedAt < 5 * 60 * 1000) {
        return cached.entries.slice();
      }
      await this.applyExplorePlatform(source, platform);
      const scriptItems = await this.evaluateExploreScript(raw, source, debugContext);
      if (scriptItems.length > 0) {
        this.captureExploreSelectors(source, scriptItems);
        this.appendExploreItems(entries, scriptItems, source);
        this.storeMenuCache(menuKey, entries);
        return entries;
      }
      const embeddedItems = this.parseEmbeddedExploreDsl(raw);
      if (embeddedItems.length > 0) {
        this.appendExploreItems(entries, embeddedItems, source);
      }
      return entries;
    }

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
        sourceName: source.bookSourceName,
        groupTitle: ''
      });
    }
    return entries;
  }

  private effectiveExploreRule(source: BookSource): ExploreRule {
    const candidate = source.exploreRule;
    if (candidate && !Array.isArray(candidate) && candidate.bookList && candidate.name && candidate.bookUrl) {
      return candidate;
    }
    return source.searchRule as ExploreRule;
  }

  private async evaluateExploreScript(raw: string, source: BookSource,
    debugContext: BookSourceDebugContext | null = null): Promise<ExploreUrlItem[]> {
    const code = raw.trim()
      .replace(/^\s*@?js:\s*/i, '')
      .replace(/^<js>\s*|\s*<\/js>$/gi, '');
    const runtime = BookSourceStageWebRuntime.get();
    // The Explore tab can start loading immediately after activation, while the hidden
    // ArkWeb host is still between controller-attached and page-end.  Treat that as a
    // normal startup window instead of turning a transient race into a permanent empty
    // result.  Keep this in line with the response-script path below.
    if (!runtime.isAvailable()) await runtime.waitUntilAvailable(8000);
    if (runtime.isAvailable()) {
      const request = new StageWebRuntimeRequest();
      request.applyStageBudget(SourceRuntimeStage.EXPLORE);
      request.source = source;
      request.code = code;
      request.baseUrl = source.bookSourceUrl;
      request.variables = { page: '1', pageIndex: '1' };
      request.debugContext = debugContext;
      try {
        const runtimeResult = await runtime.execute(request);
        if (runtimeResult.toastMessage) this.noticeMessage = runtimeResult.toastMessage.trim();
        const parsed = this.parseExploreScriptResult(runtimeResult.value || '');
        if (parsed.length > 0 || this.noticeMessage) return parsed;
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error || '');
        if (message) this.noticeMessage = `发现脚本执行失败：${message}`;
        console.warn('[ExploreCoordinator] stage runtime menu failed:', source.bookSourceName, error);
      }
    } else {
      this.noticeMessage = '发现脚本运行环境未就绪';
    }
    return [];
  }

  private parseExploreScriptResult(value: string): ExploreUrlItem[] {
    const raw = (value || '').trim();
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw) as Object;
      if (Array.isArray(parsed)) return parsed as ExploreUrlItem[];
      if (!parsed || typeof parsed !== 'object') return [];
      const record = parsed as Record<string, Object>;
      const message = String(record['message'] || record['msg'] || record['error'] || '').trim();
      const code = String(record['code'] || record['status'] || '').trim();
      if (message && (code === '401' ||
        /请先登[录陆]|需要登[录陆]|未登[录陆]|令牌|token|无权限/i.test(message))) {
        this.noticeMessage = message;
        return [];
      }
      const data = record['data'];
      if (Array.isArray(data)) return data as ExploreUrlItem[];
      if (message && !this.noticeMessage) this.noticeMessage = message;
    } catch (_) {
      // 非 JSON 返回仍交给后续旧版 DSL 降级解析。
    }
    return [];
  }

  private parseEmbeddedExploreDsl(raw: string): ExploreUrlItem[] {
    const blocks = raw.match(/`[\s\S]*?`/g) || [];
    for (const block of blocks) {
      const content = block.substring(1, block.length - 1);
      if (!content.includes('::')) continue;
      const items: ExploreUrlItem[] = [];
      for (const rawLine of content.split(/[\n\r]+/)) {
        const line = rawLine.trim();
        if (!line) continue;
        const index = line.indexOf('::');
        if (index > 0) {
          items.push({
            title: line.substring(0, index).trim(),
            url: line.substring(index + 2).trim()
          });
        } else {
          items.push({ title: line, url: '' });
        }
      }
      if (items.length > 0) return items;
    }
    return [];
  }

  private appendExploreItems(entries: ExploreEntry[], items: ExploreUrlItem[], source: BookSource): void {
    let groupTitle = '';
    for (const item of items) {
      const title = String(item.title || '').trim();
      const url = String(item.url || '').trim();
      if (!url) {
        if (this.isExploreNotice(title)) {
          this.noticeMessage = title;
        } else {
          groupTitle = this.cleanExploreGroupTitle(title) || groupTitle;
        }
        continue;
      }
      if (!title || this.isPersonalExploreUrl(title, url)) continue;
      const entryTitle = groupTitle ? `${groupTitle} · ${title}` : title;
      if (entries.some(entry => entry.title === entryTitle && entry.url === url && entry.sourceUrl === source.bookSourceUrl)) {
        continue;
      }
      entries.push({
        title: groupTitle ? title : entryTitle,
        url: url,
        sourceUrl: source.bookSourceUrl,
        sourceName: source.bookSourceName,
        groupTitle: groupTitle
      });
    }
  }

  private captureExploreSelectors(source: BookSource, items: ExploreUrlItem[]): void {
    const discovered: ExplorePlatformSelector[] = [];
    for (const item of items) {
      const title = String(item.title || item.name || '').trim();
      if (String(item.type || '').toLowerCase() !== 'select' || !title) continue;
      const chars = Array.isArray(item.chars) ? item.chars : [];
      const selector = new ExplorePlatformSelector();
      for (const rawValue of chars) {
        let label = '';
        let value = '';
        if (rawValue && typeof rawValue === 'object' && !Array.isArray(rawValue)) {
          const record = rawValue as Record<string, Object>;
          label = String(record['name'] || record['title'] || record['label'] || record['value'] || '').trim();
          value = String(record['value'] || record['key'] || label).trim();
        } else {
          label = String(rawValue || '').trim();
          value = label;
        }
        if (!label || selector.labels.includes(label)) continue;
        selector.labels.push(label);
        selector.values.push(value);
        selector.actions.push('');
      }
      if (selector.labels.length === 0) continue;
      const action = String(item.action || '');
      const parameter = action.match(/show\s*\([^,]+,\s*['"]([^'"]+)['"]\s*\)/i);
      // parameter is the persistent source-variable key. The visible title is retained
      // separately in `actions` so native UI can show the same hierarchy as the source.
      selector.parameter = title;
      if (parameter) {
        selector.mode = 'show';
        selector.actions = [parameter[1]];
      } else if (action.trim()) {
        // Legado select controls commonly ship a self-contained action script that reads the
        // chosen value from infoMap[<control name>] (often via source.setVariable + refresh).
        // Keep the script verbatim; executeExploreSelector pre-fills infoMap before running it.
        selector.mode = 'script';
        selector.actions = [action];
      } else {
        continue;
      }
      const defaultValue = String(item.default || '').trim();
      const defaultIndex = selector.values.indexOf(defaultValue);
      selector.currentLabel = defaultIndex >= 0 ? selector.labels[defaultIndex] : defaultValue;
      if (!selector.actions[0]) continue;
      discovered.push(selector);
      if (/平台|来源|源站/.test(title)) this.platformSelectors[source.bookSourceUrl] = selector;
    }
    if (discovered.length > 0) this.filterSelectors[source.bookSourceUrl] = discovered;
  }

  private parseLoginPlatformSelector(source: BookSource): ExplorePlatformSelector {
    const selector = new ExplorePlatformSelector();
    const loginCode = source.loginUrl || '';
    const block = loginCode.match(/(?:var|let|const)\s+sourceList\s*=\s*\[([\s\S]*?)\]\s*;/);
    if (!block) return selector;
    const objects = block[1].match(/\{[^{}]*\}/g) || [];
    for (const raw of objects) {
      const action = this.looseProperty(raw, 'n');
      const value = this.looseProperty(raw, 'v');
      const label = this.looseProperty(raw, 'm') || value;
      if (!/^sou\d+$/i.test(action) || !value || !label) continue;
      selector.labels.push(label);
      selector.values.push(value);
      selector.actions.push(action);
    }
    if (selector.labels.length === 0) return selector;
    selector.mode = 'loginAction';
    try {
      const parsed = JSON.parse(source.variable || '[]') as Object;
      const config = Array.isArray(parsed) ? parsed[0] as Record<string, Object> : parsed as Record<string, Object>;
      const currentValue = config ? String(config['source'] || '') : '';
      const currentIndex = selector.values.indexOf(currentValue);
      selector.currentLabel = currentIndex >= 0 ? selector.labels[currentIndex] : selector.labels[0];
    } catch (_) {
      selector.currentLabel = selector.labels[0];
    }
    return selector;
  }

  private looseProperty(raw: string, key: string): string {
    // Imported source lists commonly use unquoted keys immediately after the opening brace,
    // for example `{n:"sou1",v:"番茄小说",m:"番茄小说"}`.
    const match = raw.match(new RegExp(`(?:^|[,{\\s])${key}\\s*:\\s*(["'])([\\s\\S]*?)\\1`));
    return match ? (match[2] || '').trim() : '';
  }

  private async applyExplorePlatform(source: BookSource, platform: string): Promise<void> {
    const selector = this.platformSelectors[source.bookSourceUrl];
    if (!selector || !platform || selector.currentLabel === platform) return;
    await this.executeExploreSelector(source, selector, platform);
  }

  private async executeExploreSelector(source: BookSource, selector: ExplorePlatformSelector,
    selection: string): Promise<boolean> {
    const index = selector.labels.indexOf(selection);
    if (index < 0) return false;
    const runtime = BookSourceStageWebRuntime.get();
    if (!runtime.isAvailable() && !await runtime.waitUntilAvailable(8000)) return false;
    const request = new StageWebRuntimeRequest();
    request.applyStageBudget(SourceRuntimeStage.EXPLORE);
    request.source = source;
    request.baseUrl = source.bookSourceUrl;
    const variableKey = selector.actions.length > 0 ? selector.actions[0] : '';
    if (selector.mode === 'show' && variableKey) {
      request.code = `if(typeof show==='function'){show(${JSON.stringify(selector.values[index])},` +
        `${JSON.stringify(variableKey)});}'';`;
    } else if (selector.mode === 'loginAction' && selector.actions[index]) {
      const action = selector.actions[index];
      // 登录动作库同样必须剥掉 loginUrl 的 <js> 包装，否则函数无法进入作用域。
      const loginLib = (source.loginUrl || '').trim()
        .replace(/^<js>\s*/i, '').replace(/\s*<\/js>$/i, '')
        .replace(/^@?js:\s*/i, '');
      request.code = `${loginLib}\n;if(typeof globalThis[${JSON.stringify(action)}]==='function')` +
        `{globalThis[${JSON.stringify(action)}]();}'';`;
    } else if (selector.mode === 'script' && variableKey) {
      // Generic Legado select action: the script reads the chosen value from
      // infoMap[<control name>] and typically persists it via source.setVariable().
      request.code = `infoMap.put(${JSON.stringify(selector.parameter || '')},` +
        ` ${JSON.stringify(selector.values[index])});\n${variableKey}\n;'';`;
    } else {
      return false;
    }
    try {
      const result = await runtime.execute(request);
      selector.currentLabel = selection;
      if (!this.noticeMessage && result.toastMessage && result.toastMessage.trim()) {
        this.noticeMessage = result.toastMessage.trim();
      }
      console.info('[ExploreCoordinator] native explore filter switched:', source.bookSourceName,
        selector.parameter, selection);
      // The selector script usually persisted new state into the source variable; drop cached
      // menus so the next parseExploreUrl re-runs the script with the updated state.
      this.clearExploreMenuCache();
      return true;
    } catch (error) {
      console.warn('[ExploreCoordinator] native explore filter switch failed:', source.bookSourceName,
        selector.parameter, selection, error);
      return false;
    }
  }

  private usesNativeExploreFilters(source: BookSource): boolean {
    const script = `${source.exploreUrl || ''}\n${source.jsLib || ''}`;
    return /createFilter\s*\([\s\S]{0,80}(?:模式|类型|平台|来源|源站)/.test(script) ||
      /type\s*:\s*['"]select['"]/.test(source.exploreUrl || '');
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

  private isExploreNotice(title: string): boolean {
    return /请先|需要登录|未登录|token|失败|错误|异常|失效|过期|无权限/i.test(title || '');
  }

  private requiresSourceVariable(source: BookSource): boolean {
    const script = `${source.jsLib || ''}\n${source.exploreUrl || ''}`;
    return /authorization[\s\S]{0,160}getVariable\s*\(|Bearer[\s\S]{0,120}getVariable\s*\(/i.test(script);
  }

  private isPersonalExploreUrl(title: string, url: string): boolean {
    const value = `${title || ''}\n${url || ''}`.toLowerCase();
    return value.includes('个人中心') || value.includes('我的书架') || value.includes('bookshelf') ||
      value.includes('book_shelf') || value.includes('/user/') || value.includes('/login');
  }

  private async buildUrl(source: BookSource, url: string, page: number,
    debugContext: BookSourceDebugContext | null = null): Promise<string> {
    url = this.applyLegacyPageAlternative(url, page);
    const decision = BookSourceRuntimeRouter.decide(SourceRuntimeStage.URL,
      `${source.jsLib || ''}\n${url || ''}`);
    const isFullJsUrl = /^\s*@?js:/i.test(url || '') || /^\s*<js>[\s\S]*<\/js>\s*$/i.test(url || '');
    const requiresStageRuntime = isFullJsUrl || (url.includes('{{') && decision.runtime === 'arkweb');
    const runtime = BookSourceStageWebRuntime.get();
    if (requiresStageRuntime && !runtime.isAvailable()) await runtime.waitUntilAvailable(8000);
    if (requiresStageRuntime && runtime.isAvailable()) {
      const request = new StageWebRuntimeRequest();
      request.applyStageBudget(SourceRuntimeStage.EXPLORE);
      request.source = source;
      request.baseUrl = source.bookSourceUrl;
      request.variables = { page: String(page), pageIndex: String(page) };
      request.debugContext = debugContext;
      if (isFullJsUrl) {
        request.code = (url || '').trim()
          .replace(/^@?js:\s*/i, '')
          .replace(/^<js>\s*|\s*<\/js>$/gi, '');
      } else {
        const template = JSON.stringify(url || '');
        request.code = `const __exploreTemplate=${template};result=__exploreTemplate.replace(/\\{\\{([\\s\\S]*?)\\}\\}/g,` +
          `function(_,expr){try{return String(eval(expr));}catch(e){return '';}});result;`;
      }
      try {
        const result = await runtime.execute(request);
        if (result.value) {
          const evaluated = this.applyLegacyPageAlternative(result.value, page);
          // Stage scripts commonly return the same root-relative address that an ordinary
          // Legado template would produce. Resolve it before the caller applies its absolute-URL
          // safety check; otherwise a successfully evaluated `/api/...` request is rejected as
          // invalid solely because it used the full JavaScript runtime.
          return BookUrlResolver.resolve(evaluated, source.bookSourceUrl) || evaluated;
        }
      } catch (error) {
        console.warn('[ExploreCoordinator] stage runtime URL failed:', source.bookSourceName, error);
      }
    }
    if (requiresStageRuntime) return '';
    const built = BookSourceDataUrlSupport.buildRequestUrl(source, url, String(page));
    if (built) return built;
    // Ordinary Legado explore entries are very often relative URLs. Keep them on the lightweight
    // runner, which evaluates page expressions and resolves the result against the selected source
    // host before the caller performs its absolute-URL validity check.
    const observation = new QuickJsObservationContext();
    observation.sourceUrl = source.bookSourceUrl || '';
    observation.sourceName = source.bookSourceName || observation.sourceUrl;
    observation.stage = SourceRuntimeStage.EXPLORE;
    observation.field = 'exploreUrl';
    const templated = BookSourceScriptRunner.evaluateUrl(source, url, '', String(page), observation);
    if (templated.handled && templated.value) return templated.value;
    const js = new JsRuntime();
    js.setQuickJsObservation(observation);
    js.setVar('page', String(page));
    js.setVar('pageIndex', String(page));
    const fallback = js.evalTemplate(this.applySourceTemplate(url, source))
      .replace(/\{\{[^}]+\}\}/g, String(page));
    return BookUrlResolver.resolve(fallback, source.bookSourceUrl) || fallback;
  }

  /** Legado page-one shorthand: `<first-page,following-pages>`. */
  private applyLegacyPageAlternative(url: string, page: number): string {
    return (url || '').replace(/<([^<>]*),([^<>]*)>/g,
      (match: string, firstPage: string, followingPages: string): string => {
        if (match.includes('(') || !/\{\{\s*page(?:Index)?\b/i.test(match)) return match;
        return page <= 1 ? firstPage : followingPages;
      });
  }

  private async executeResponseBodyScript(source: BookSource, code: string, body: string,
    baseUrl: string, page: number, debugContext: BookSourceDebugContext | null = null): Promise<string> {
    const runtime = BookSourceStageWebRuntime.get();
    if (!runtime.isAvailable()) await runtime.waitUntilAvailable(8000);
    if (!runtime.isAvailable()) {
      this.noticeMessage = '发现响应脚本运行环境未就绪';
      return '';
    }
    const request = new StageWebRuntimeRequest();
    request.applyStageBudget(SourceRuntimeStage.EXPLORE);
    request.source = source;
    request.code = code || '';
    request.content = body || '';
    request.baseUrl = baseUrl || source.bookSourceUrl;
    request.variables = { page: String(page), pageIndex: String(page) };
    request.debugContext = debugContext;
    try {
      const result = await runtime.execute(request);
      return result.value || '';
    } catch (error) {
      console.warn('[ExploreCoordinator] bodyJs failed:', source.bookSourceName, error);
      this.noticeMessage = `发现响应脚本执行失败：${error instanceof Error ? error.message : String(error)}`;
      return '';
    }
  }

  /** Avoid treating a small API error object as a one-item book list. */
  private responseFailureMessage(body: string): string {
    const value = (body || '').trim();
    if (!value.startsWith('{') || value.length > 4096) return '';
    try {
      const record = JSON.parse(value) as Record<string, Object>;
      const message = String(record['msg'] || record['message'] || record['error'] || '').trim();
      if (!message || !/失败|错误|异常|未登录|请登录|无权限|拒绝|invalid|error|fail/i.test(message)) return '';
      const meaningfulKeys = ['data', 'list', 'records', 'items', 'books', 'result'];
      for (const key of meaningfulKeys) {
        const field = record[key];
        if (Array.isArray(field) && field.length > 0) return '';
        if (field && typeof field === 'object' && !Array.isArray(field) && Object.keys(field as Record<string, Object>).length > 0) {
          return '';
        }
      }
      return message.substring(0, 160);
    } catch (_) {
      return '';
    }
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
    if (!ctx.has('source.variable')) ctx.put('source.variable', source.variable || '');
  }

  private async fetchEncodedDataUrl(url: string, source: BookSource): Promise<{ url: string, statusCode: number, headers: Record<string, string>, body: string, success: boolean, error?: string }> {
    const root = await EncodedSourceUrl.requestJsonForDataUrl(this.http, url, source);
    if (!root) {
      return { url: url, statusCode: 0, headers: {}, body: '', success: false, error: 'encoded data url request failed' };
    }
    return { url: url, statusCode: 200, headers: {}, body: JSON.stringify(root), success: true };
  }
}
