import { Book, BookChapter, BookSource } from '../../model/data/Book';
import { HttpClient } from '../http/HttpClient';
import { AnalyzeUrl } from '../rule/AnalyzeUrl';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { RuleContext } from '../rule/RuleContext';
import { util } from '@kit.ArkTS';
import { VerificationSupport } from '../http/VerificationSupport';
import { EncodedSourceUrl } from './EncodedSourceUrl';
import { BookSourceDataUrlSupport } from './BookSourceDataUrlSupport';
import { BookUrlResolver } from './BookUrlResolver';
import { BookFieldSanitizer } from '../../utils/BookFieldSanitizer';
import { AjaxRuleCompat } from '../rule/AjaxRuleCompat';
import { ReaderImageMarker } from './ReaderImageMarker';
import { JsRuntime } from '../rule/JsRuntime';
import { ScriptEngine, ScriptEngineContext } from '../rule/ScriptEngine';
import { ComicImagePipeline } from './ComicImagePipeline';
import { BookSourceRuntimeRouter, SourceRuntimeStage } from './BookSourceRuntimeRouter';
import { BookSourceStageWebRuntime, StageWebRuntimeRequest } from './BookSourceStageWebRuntime';
import { ReaderActionMarker } from './ReaderActionMarker';
import { BookSourceInteractionPostProcessor } from './BookSourceInteractionPostProcessor';
import { CookieStore } from '../http/CookieStore';
import { RuleExecutionService } from '../rule/RuleExecutionService';
import { RuleBatchExecutionRequest, RuleFieldRequest } from '../rule/RuleExecutionModels';
import { CooperativeScheduler } from '../concurrency/CooperativeScheduler';
import { BookSourceAudioWebRuntime } from './BookSourceAudioWebRuntime';
import { BookSourceMetadataSupport } from './BookSourceMetadataSupport';
import { RuleExecutionTarget, RuleValue } from '../rule/RuleValue';
import { BookSourceDebugContext } from './BookSourceDebugModels';

class ContentPageData {
  content: string = '';
  nextUrl: string = '';
}

export class WebBookService {
  static readonly GENERIC_TOC_FALLBACK_KEY: string = '__genericTocFallback';
  private http: HttpClient;
  private activeContentRuleOwners: Set<string> = new Set();

  constructor() {
    this.http = new HttpClient(10000);
  }

  cancelPendingRequests(): void {
    this.http.cancelAll();
    for (const ownerId of this.activeContentRuleOwners) {
      RuleExecutionService.get().cancelOwner(ownerId);
    }
  }

  private contentRequestCanceled(shouldCancel: (() => boolean) | null): boolean {
    return shouldCancel ? shouldCancel() : false;
  }

  async getBookInfo(source: BookSource, book: Book,
    debugContext: BookSourceDebugContext | null = null): Promise<Book> {
    // Imported rules may build the virtual detail URL while the field batch is still executing.
    // Preserve its request data and bridge the SearchBook identity that is already known.
    book.bookUrl = EncodedSourceUrl.repairBookName(book.bookUrl, book.name, 'details');
    BookSourceMetadataSupport.applyBook(source, book, [book.bookUrl]);
    if (BookSourceDataUrlSupport.isEncodedSource(book.bookUrl)) {
      return await BookSourceDataUrlSupport.getBookInfo(this.http, source, book);
    }
    console.log('[WS] getBookInfo');
    const au = new AnalyzeUrl(source, this.http);
    const resp = EncodedSourceUrl.canHandle(book.bookUrl) ?
      await this.fetchEncodedDataUrl(book.bookUrl, source) : await au.fetch(book.bookUrl, undefined, debugContext);
    console.log('[WS] getBookInfo resp:', resp.success, 'len:', resp.body.length);
    if (this.requestVerificationIfNeeded(source, book.bookUrl, resp.body, resp.statusCode, source.bookInfoRule.init)) {
      return book;
    }
    if (!resp.success || !resp.body) return book;
    const baseUrl = BookUrlResolver.effectiveBase(resp, book.bookUrl, source.bookSourceUrl);

    const ctx = new RuleContext();
    ctx.loadFromJson(book.variable);
    this.seedBookVariables(ctx, book.bookUrl);

    // init 规则
    let content = resp.body;
    const infoRule = source.bookInfoRule;
    if (infoRule.init) {
      // Data URLs are virtual rule payloads. Their scripts often branch on baseUrl before
      // requesting the real detail endpoint, so preserve that virtual URL for the script.
      const stageBaseUrl = EncodedSourceUrl.decode(book.bookUrl) ? book.bookUrl : baseUrl;
      let initResult = await this.runStageRule(source, book, infoRule.init, content, stageBaseUrl,
        SourceRuntimeStage.BOOK_INFO, null, {}, debugContext);
      if (!initResult && !this.stageRuleCode(infoRule.init)) {
        const ir = new AnalyzeRule(content, baseUrl, ctx);
        this.seedSourceVariables(ctx, source);
        initResult = ir.getString(infoRule.init);
      }
      if (initResult) content = initResult;
    }

    this.seedSourceVariables(ctx, source);
    const fieldRequest = new RuleBatchExecutionRequest();
    fieldRequest.source = source;
    fieldRequest.book = book;
    fieldRequest.stage = SourceRuntimeStage.BOOK_INFO;
    fieldRequest.ownerId = `book_info_${Date.now()}_${book.bookUrl}`;
    fieldRequest.typedContents = [RuleValue.fromExternal(content)];
    fieldRequest.contents = [content];
    fieldRequest.baseUrl = baseUrl;
    fieldRequest.contextValues = ctx.toPersistentRecord();
    fieldRequest.fields = [
      new RuleFieldRequest('name', infoRule.name || ''),
      new RuleFieldRequest('author', infoRule.author || ''),
      new RuleFieldRequest('coverUrl', infoRule.coverUrl || ''),
      new RuleFieldRequest('intro', infoRule.intro || ''),
      new RuleFieldRequest('kind', infoRule.kind || ''),
      new RuleFieldRequest('status', infoRule.status || ''),
      new RuleFieldRequest('lastChapter', infoRule.lastChapter || ''),
      new RuleFieldRequest('wordCount', infoRule.wordCount || ''),
      new RuleFieldRequest('updateTime', infoRule.updateTime || ''),
      new RuleFieldRequest('tocUrl', infoRule.tocUrl || '', true)
    ];
    fieldRequest.timeoutMs = 20000;
    fieldRequest.debugContext = debugContext;
    let fieldValues: Record<string, string> = {};
    try {
      const batch = await RuleExecutionService.get().executeBatch(fieldRequest);
      if (batch.errors.length > 0) {
        console.warn('[WS] book info field errors:', source.bookSourceName, batch.errors.join('; '));
      }
      if (batch.values.length > 0) fieldValues = batch.values[0];
      if (batch.contextValues.length > 0) ctx.loadFromJson(batch.contextValues[0]);
    } finally {
      RuleExecutionService.get().clearOwner(fieldRequest.ownerId);
    }
    book.name = BookFieldSanitizer.prefer(fieldValues['name'] || '', book.name);
    book.author = BookFieldSanitizer.prefer(fieldValues['author'] || '', book.author);
    const infoCoverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source,
      fieldValues['coverUrl'] || '', baseUrl);
    book.coverUrl = book.coverUrl || infoCoverUrl;
    book.intro = BookFieldSanitizer.prefer(fieldValues['intro'] || '', book.intro);
    if (!book.intro) {
      book.intro = BookFieldSanitizer.clean(this.detailFallbackText(content,
        ['desc', 'intro', 'description', 'abstract', 'summary', 'book_desc', 'book_intro',
          'book_abstract', 'book_description', 'content_desc', 'brief']));
    }
    book.kind = BookFieldSanitizer.prefer(fieldValues['kind'] || '', book.kind);
    book.status = BookFieldSanitizer.prefer(fieldValues['status'] || '', book.status);
    book.latestChapterTitle = BookFieldSanitizer.prefer(fieldValues['lastChapter'] || '', book.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.prefer(fieldValues['wordCount'] || '', book.wordCount);
    book.updateTime = BookFieldSanitizer.prefer(fieldValues['updateTime'] || '', book.updateTime);

    // A few source-defined detail scripts build the catalog data URL in the same field batch
    // that updates book metadata. Their script runtime mutates the shared Book object, while the
    // per-field result object remains the original detail JSON. If that yields an incomplete
    // virtual catalog identity, merge only the missing scalar metadata from the source-defined
    // detail payload. Endpoints and request behavior remain entirely owned by the imported rule.
    const bridgedTocUrl = this.bridgeVirtualCatalogMetadata(fieldValues['tocUrl'] || '', book.bookUrl,
      ['book_id', 'item_id', 'source', 'sources', 'tab', 'url', 'toc_url', 'book_name', 'author',
        'abstract', 'thumb_url']);
    const tocUrl = EncodedSourceUrl.repairCatalogBookName(bridgedTocUrl, book.name);
    if (tocUrl) book.tocUrl = this.repairUrlWithBookId(tocUrl, book.bookUrl);

    // 保存变量
    book.variable = ctx.toPersistentJson();

    // 如果 tocUrl 为空，尝试从 bookUrl 构造
    if (!book.tocUrl) {
      book.tocUrl = this.fallbackTocUrl(book.bookUrl, infoRule.tocUrl, baseUrl);
    }

    // Detail rules commonly add the definitive tab only to their catalog URL. Apply it after the
    // rule has finished so the details page and the following reader route agree on media type.
    BookSourceMetadataSupport.applyBook(source, book, [book.bookUrl, book.tocUrl]);

    return book;
  }

  private detailFallbackText(content: string, keys: string[]): string {
    const value = (content || '').trim();
    if (!value || (!value.startsWith('{') && !value.startsWith('['))) return '';
    try {
      const parsed = JSON.parse(value) as Object;
      const record = Array.isArray(parsed) ?
        (parsed.length > 0 && parsed[0] && typeof parsed[0] === 'object' ?
          parsed[0] as Record<string, Object> : null) :
        (parsed && typeof parsed === 'object' ? parsed as Record<string, Object> : null);
      if (!record) return '';
      const wanted = keys.map((key: string): string => key.toLowerCase());
      const find = (node: Object, depth: number): string => {
        if (!node || depth > 5) return '';
        if (Array.isArray(node)) {
          for (const item of node as Object[]) {
            const found = item && typeof item === 'object' ? find(item, depth + 1) : '';
            if (found) return found;
          }
          return '';
        }
        const current = node as Record<string, Object>;
        // API-backed sources commonly nest metadata under data/book/result. Search the requested
        // keys at every object level instead of assuming the first JSON object is the detail record.
        for (const key of Object.keys(current)) {
          if (!wanted.includes(key.toLowerCase())) continue;
          const field = current[key];
          if (field !== undefined && field !== null && typeof field !== 'object') {
            const text = String(field).trim();
            if (text) return text;
          }
        }
        for (const key of Object.keys(current)) {
          const field = current[key];
          if (field && typeof field === 'object') {
            const found = find(field, depth + 1);
            if (found) return found;
          }
        }
        return '';
      };
      return find(record, 0);
    } catch (_) {
    }
    return '';
  }

  private fallbackTocUrl(bookUrl: string, tocRule: string, baseUrl: string): string {
    // 从 bookUrl 提取 novelId
    let novelId = this.extractQueryParam(bookUrl, 'book_id') || this.extractQueryParam(bookUrl, 'bookid') ||
      this.extractQueryParam(bookUrl, 'bookId') || this.extractQueryParam(bookUrl, 'id');
    const segs = bookUrl.replace(/\?.*$/, '').split('/').filter(s => s.length > 0);
    if (!novelId) {
      for (let i = segs.length - 1; i >= 0; i--) {
        if (segs[i].match(/^[a-zA-Z0-9_-]{3,40}$/)) { novelId = segs[i]; break; }
      }
    }
    if (!novelId || !tocRule) return bookUrl;
    const url = tocRule
      .replace(/\{\{\s*\$\.\.?\w+\s*\}\}/g, novelId)
      .replace(/\{\{\s*\w+\s*\}\}/g, novelId);
    if (url.startsWith('http')) return url;
    return BookUrlResolver.resolve(url, baseUrl);
  }

  private resolveTocUrl(source: BookSource, book: Book): string {
    return book.tocUrl || book.bookUrl;
  }

  private repairUrlWithBookId(url: string, bookUrl: string): string {
    if (!url || !bookUrl) return url;
    if (!url.includes('/book/chapters') && !url.includes('/book//')) return url;
    const bookId = this.extractBookId(bookUrl);
    if (!bookId) return url;

    return url
      .replace(/\/{2,}/g, '/')
      .replace(/^http:\//, 'http://')
      .replace(/^https:\//, 'https://')
      .replace(/\/book\/chapters/g, `/book/${bookId}/chapters`)
      .replace(/\/book\/\//g, `/book/${bookId}/`);
  }

  private extractBookId(bookUrl: string): string {
    const clean = bookUrl.replace(/\?.*$/, '');
    const match = clean.match(/\/book\/([^/]+)$/);
    if (match) return match[1];

    const segs = clean.split('/').filter(s => s.length > 0);
    for (let i = segs.length - 1; i >= 0; i--) {
      if (/^[a-zA-Z0-9_-]{3,40}$/.test(segs[i])) return segs[i];
    }
    return '';
  }

  async getChapterList(source: BookSource, book: Book, maxChapters: number = 0,
    allowGenericFallback: boolean = true,
    debugContext: BookSourceDebugContext | null = null): Promise<BookChapter[]> {
    AppStorage.setOrCreate('bookSourceStageLastError', '');
    BookSourceMetadataSupport.applyBook(source, book, [book.bookUrl, book.tocUrl]);
    const chapterLimit = maxChapters > 0 ? Math.max(1, Math.round(maxChapters)) : 0;
    if (BookSourceDataUrlSupport.isEncodedSource(book.tocUrl) || BookSourceDataUrlSupport.isEncodedSource(book.bookUrl)) {
      const encodedChapters = await BookSourceDataUrlSupport.getChapterList(this.http, source, book);
      return chapterLimit > 0 ? encodedChapters.slice(0, chapterLimit) : encodedChapters;
    }
    console.log('[WS] getChapterList');
    const tocUrl = this.resolveTocUrl(source, book);
    const au = new AnalyzeUrl(source, this.http);
    let resp = EncodedSourceUrl.canHandle(tocUrl) ?
      await this.fetchEncodedDataUrl(tocUrl, source) : await au.fetch(tocUrl, undefined, debugContext);
    if (!resp.success || !resp.body) return [];
    const ctx = new RuleContext();
    ctx.loadFromJson(book.variable);
    this.seedBookVariables(ctx, book.bookUrl);
    this.seedSourceVariables(ctx, source);
    const tocRule = source.tocRule;
    const chapters: BookChapter[] = [];
    const seenChapterUrls = new Set<string>();
    const seenPageUrls = new Set<string>();
    let currentUrl = resp.url || tocUrl;
    let currentResp = resp;
    let firstBody = resp.body;
    let firstBaseUrl = BookUrlResolver.effectiveBase(resp, tocUrl, book.bookUrl || source.bookSourceUrl);
    // Pagination is already protected by seenPageUrls and the optional chapterLimit. The old
    // 100-page ceiling truncated long novels at roughly 2,000 chapters (20 chapters/page).
    // Keep a generous abuse guard while allowing common 4,000–10,000 chapter catalogs.
    for (let page = 0; page < 1000; page++) {
      if (!currentResp.success || !currentResp.body) break;
      const pageKey = this.urlWithoutFragment(currentResp.url || currentUrl);
      if (seenPageUrls.has(pageKey)) break;
      seenPageUrls.add(pageKey);
      if (this.requestVerificationIfNeeded(source, currentUrl, currentResp.body, currentResp.statusCode, tocRule.chapterList)) {
        break;
      }
      const baseUrl = BookUrlResolver.effectiveBase(currentResp, currentUrl, book.bookUrl || source.bookSourceUrl);
      if (page === 0) {
        firstBody = currentResp.body;
        firstBaseUrl = baseUrl;
        const runtimeInput = this.stageDataUrlInput(tocRule.chapterList, currentUrl, currentResp.body);
        const stageBaseUrl = EncodedSourceUrl.decode(currentUrl) ? currentUrl : baseUrl;
        const runtimeList = await this.runStageRule(source, book, tocRule.chapterList,
          runtimeInput, stageBaseUrl, SourceRuntimeStage.TOC, null,
          EncodedSourceUrl.scalarVariables(currentUrl), debugContext);
        if (runtimeList) {
            const runtimeChapters = await this.parseStageChapterList(source, book, runtimeList, baseUrl,
              chapterLimit, debugContext);
          if (runtimeChapters.length > 0) {
            return runtimeChapters;
          }
          AppStorage.setOrCreate('bookSourceStageLastError',
            `目录脚本已返回内容，但没有转换出章节（返回 ${runtimeList.length} 字符）`);
        } else if (this.stageRuleCode(tocRule.chapterList || '')) {
          const lastError = AppStorage.get<string>('bookSourceStageLastError') || '';
          if (!lastError) AppStorage.setOrCreate('bookSourceStageLastError', '目录脚本返回空结果');
        }
      }
      const remainingLimit = chapterLimit > 0 ? Math.max(0, chapterLimit - chapters.length) : 0;
      if (chapterLimit > 0 && remainingLimit === 0) break;
      const pageChapters = await this.parseChapterPage(source, book, currentResp.body, baseUrl, ctx,
        chapters.length, remainingLimit, debugContext);
      for (const chapter of pageChapters) {
        const chapterKey = this.urlWithoutFragment(chapter.url);
        if (seenChapterUrls.has(chapterKey)) continue;
        seenChapterUrls.add(chapterKey);
        chapter.index = chapters.length;
        chapters.push(chapter);
        if (chapterLimit > 0 && chapters.length >= chapterLimit) break;
      }
      if (chapterLimit > 0 && chapters.length >= chapterLimit) break;
      if (!tocRule.nextTocUrl) break;
      const nextUrl = await this.executeSingleRuleField(source, book, null, tocRule.nextTocUrl,
        currentResp.body, baseUrl, SourceRuntimeStage.TOC, ctx, true, debugContext);
      const nextKey = this.urlWithoutFragment(nextUrl);
      if (!nextUrl || seenPageUrls.has(nextKey)) break;
      currentUrl = nextUrl;
      currentResp = EncodedSourceUrl.canHandle(currentUrl) ?
        await this.fetchEncodedDataUrl(currentUrl, source) : await au.fetch(currentUrl, undefined, debugContext);
    }

    book.variable = ctx.toPersistentJson();
    if (chapters.length > 0) return chapters;

    if (!allowGenericFallback) return chapters;

    const fallbackChapters = this.tryBuildGenericChapterList(book, firstBody, firstBaseUrl);
    if (fallbackChapters.length > 0) {
      AppStorage.setOrCreate('bookSourceStageLastError', '正式目录规则未匹配，当前使用临时通用目录');
      return chapterLimit > 0 ? fallbackChapters.slice(0, chapterLimit) : fallbackChapters;
    }
    return chapters;
  }

  private bridgeVirtualCatalogMetadata(tocUrl: string, detailUrl: string, allowedKeys: string[]): string {
    const tocPayload = EncodedSourceUrl.decode(tocUrl || '');
    const detailPayload = EncodedSourceUrl.decode(detailUrl || '');
    if (!tocPayload || !detailPayload || !tocPayload.type || !/catalog/i.test(tocPayload.type)) return tocUrl;
    let changed = false;
    for (const key of allowedKeys) {
      const current = tocPayload.data[key];
      const fallback = detailPayload.data[key];
      if ((current === undefined || current === null || String(current).trim() === '') &&
        fallback !== undefined && fallback !== null && typeof fallback !== 'object' && String(fallback).trim()) {
        tocPayload.data[key] = fallback;
        changed = true;
      }
    }
    if (!changed) return tocUrl;
    const type = tocPayload.type || String(tocPayload.options['type'] || 'catalog');
    return EncodedSourceUrl.encode(tocPayload.data, type);
  }

  private async parseChapterPage(source: BookSource, book: Book, body: string, baseUrl: string,
    ctx: RuleContext, startIndex: number, maxItems: number = 0,
    debugContext: BookSourceDebugContext | null = null): Promise<BookChapter[]> {
    const tocRule = source.tocRule;
    // A complete list script has already been attempted through ArkWeb by getChapterList. Never
    // retry it synchronously when it returned no usable chapters.
    if (this.stageRuleCode(tocRule.chapterList || '')) return [];
    const rule = new AnalyzeRule(body, baseUrl, ctx);
    const matchedValues = rule.execute(tocRule.chapterList || '', RuleExecutionTarget.ELEMENTS);
    const itemValues = maxItems > 0 ? matchedValues.slice(0, maxItems) : matchedValues;
    const matchedItems = matchedValues.map((item: RuleValue): string => item.asString());
    const items = itemValues.map((item: RuleValue): string => item.asString());
    console.log('[WS] getChapterList page items:', matchedItems.length, 'processing:', items.length,
      'from resp:', body.length);
    const chapters: BookChapter[] = [];
    if (items.length === 0) return chapters;
    const fieldRequest = new RuleBatchExecutionRequest();
    fieldRequest.source = source;
    fieldRequest.book = book;
    fieldRequest.stage = SourceRuntimeStage.TOC;
    fieldRequest.ownerId = `toc_fields_${Date.now()}_${book.bookUrl}`;
    fieldRequest.typedContents = itemValues;
    fieldRequest.contents = items;
    fieldRequest.baseUrl = baseUrl;
    fieldRequest.contextValues = ctx.toPersistentRecord();
    fieldRequest.fields = [
      new RuleFieldRequest('chapterName', tocRule.chapterName || ''),
      new RuleFieldRequest('chapterUrl', tocRule.chapterUrl || ''),
      new RuleFieldRequest('isVip', tocRule.isVip || ''),
      new RuleFieldRequest('isPay', tocRule.isPay || ''),
      new RuleFieldRequest('updateTime', tocRule.updateTime || '')
    ];
    fieldRequest.timeoutMs = 30000;
    fieldRequest.debugContext = debugContext;
    let fieldValues: Record<string, string>[] = [];
    let contextValues: string[] = [];
    try {
      const batch = await RuleExecutionService.get().executeBatch(fieldRequest);
      fieldValues = batch.values;
      contextValues = batch.contextValues;
      if (batch.errors.length > 0) {
        console.warn('[WS] toc field errors:', source.bookSourceName, batch.errors.join('; '));
      }
    } finally {
      RuleExecutionService.get().clearOwner(fieldRequest.ownerId);
    }
    const parsingSlice = CooperativeScheduler.createTimeSlice();
    for (let i = 0; i < items.length; i++) {
      if (i > 0) await parsingSlice.checkpoint();
      const values = i < fieldValues.length ? fieldValues[i] : {};
      const chap = new BookChapter();
      chap.title = this.cleanChapterTitle(values['chapterName'] || `第${startIndex + i + 1}章`);
      let rawUrl = values['chapterUrl'] || '';
      if (rawUrl && (rawUrl.startsWith('@js:') || rawUrl.includes('$..') || rawUrl.includes('$.'))) {
        let itemData: Record<string, Object> | null = null;
        try { itemData = JSON.parse(items[i]) as Record<string, Object>; } catch (_) {}
        let tocData: Record<string, Object> | null = null;
        try { tocData = JSON.parse(body) as Record<string, Object>; } catch (_) {}
        rawUrl = rawUrl.replace(/^@js:\s*/, '').replace(/\s*,\s*\{[^}]*\}\s*$/, '');
        rawUrl = rawUrl.replace(/\$\.\.(\w+)/g, (_: string, key: string) => {
          return this.resolveJsonKey(itemData, tocData, key, true) || '';
        });
        rawUrl = rawUrl.replace(/\$\.(\w+)/g, (_: string, key: string) => {
          return this.resolveJsonKey(itemData, tocData, key, false) || '';
        });
        rawUrl = rawUrl.replace(/\s*\+\s*/g, '').replace(/^['"]|['"]$/g, '').trim();
      }
      const virtualPayload = this.ruleExpectsHexDataUrlInput(source.contentRule.content || '') ?
        this.extractVirtualChapterPayload(rawUrl) : '';
      const resolvedChapterUrl = this.resolveVars(virtualPayload || BookUrlResolver.resolve(rawUrl, baseUrl), ctx);
      chap.url = this.repairUrlWithBookId(resolvedChapterUrl, book.bookUrl);
      chap.bookUrl = book.bookUrl;
      chap.index = startIndex + i;
      chap.isVip = this.ruleBoolean(values['isVip'] || '');
      chap.isPay = this.ruleBoolean(values['isPay'] || '');
      chap.variable = BookUrlResolver.setVariableJson(chap.variable, 'baseUrl', baseUrl);
      const updateTime = values['updateTime'] || '';
      if (updateTime) {
        chap.variable = BookUrlResolver.setVariableJson(chap.variable, 'updateTime', updateTime);
      }
      if (chap.title && chap.url) chapters.push(chap);
    }
    if (contextValues.length > 0) ctx.loadFromJson(contextValues[contextValues.length - 1]);
    return chapters;
  }

  async getContent(source: BookSource, book: Book, chapter: BookChapter,
    shouldCancel: (() => boolean) | null = null,
    debugContext: BookSourceDebugContext | null = null): Promise<string> {
    if (this.contentRequestCanceled(shouldCancel)) return '';
    // Validation and reader diagnostics must describe the current content request, not a
    // stale error left by a previous catalog/script stage.
    AppStorage.setOrCreate('bookSourceStageLastError', '');
    if (BookSourceDataUrlSupport.isEncodedSource(chapter.url)) {
      const shortcutContent = await BookSourceDataUrlSupport.getContent(this.http, source, book, chapter);
      if (this.contentRequestCanceled(shouldCancel)) return '';
      const shortcutAudio = source.bookSourceType === 1 || (Number(book.type) & 32) !== 0;
      if (!shortcutContent || shortcutAudio) return shortcutContent.trim();
      const interactiveContent = await BookSourceInteractionPostProcessor.process(source, book, chapter,
        shortcutContent);
      if (this.contentRequestCanceled(shouldCancel)) return '';
      const shortcutContext = new RuleContext();
      shortcutContext.loadFromJson(book.variable);
      this.seedBookVariables(shortcutContext, book.bookUrl);
      this.seedSourceVariables(shortcutContext, source);
      this.seedChapterVariables(shortcutContext, chapter);
      return await this.normalizeReaderContent(source,
        this.applyContentReplaceRule(interactiveContent, source.contentRule.replaceRegex, shortcutContext, chapter,
          debugContext),
        chapter.url || book.bookUrl || source.bookSourceUrl);
    }
    const isAudioContent = source.bookSourceType === 1 || (Number(book.type) & 32) !== 0;
    if (isAudioContent) {
      const audioRule = (source.contentRule.content || '').trim();
      const directAudioUrl = this.resolvedAudioChapterUrl(source, book, chapter);
      // In Legado an empty audio content rule means that the catalog's chapterUrl is already
      // the playable address. It does not need a filename extension (signed streams commonly do not).
      if (!audioRule || this.isPureAudioBaseUrlRule(audioRule)) return directAudioUrl;
      const webViewAudioUrl = await this.tryResolveAudioWebViewUrl(source, chapter, directAudioUrl);
      if (webViewAudioUrl) return webViewAudioUrl;
    }
    const stageContent = await this.tryGetStageContent(source, book, chapter, debugContext);
    if (this.contentRequestCanceled(shouldCancel)) return '';
    if (stageContent) {
      if (isAudioContent) return stageContent.trim();
      const interactiveContent = await BookSourceInteractionPostProcessor.process(source, book, chapter,
        stageContent);
      if (this.contentRequestCanceled(shouldCancel)) return '';
      return await this.normalizeReaderContent(source,
        this.applyContentReplaceRule(interactiveContent, source.contentRule.replaceRegex,
          new RuleContext(), chapter, debugContext), chapter.url);
    }
    if (this.stageRuleCode(source.contentRule.content || '')) {
      // The complete content script was already executed in ArkWeb. Retrying an empty/error result
      // with the synchronous compatibility engine is precisely the path that can trigger AppFreeze.
      return '';
    }
    console.log('[WS] getContent');
    if (this.contentRequestCanceled(shouldCancel)) return '';
    const au = new AnalyzeUrl(source, this.http);
    let resp = EncodedSourceUrl.canHandle(chapter.url) ?
      await this.fetchEncodedDataUrl(chapter.url, source) : await au.fetch(chapter.url, undefined, debugContext);
    if (this.contentRequestCanceled(shouldCancel)) return '';
    console.log('[WS] getContent resp:', resp.success, 'len:', resp.body.length);
    if (!resp.success) {
      const status = Number(resp.statusCode || 0);
      const detail = String(resp.error || '').trim();
      if (status === 401 || status === 403) {
        AppStorage.setOrCreate('bookSourceStageLastError', `正文请求需要登录、验证或授权（HTTP ${status}）`);
      } else if (status === 408 || status === 425 || status === 429 || status >= 500 || status === 0) {
        AppStorage.setOrCreate('bookSourceStageLastError',
          `正文网络请求暂时失败${status > 0 ? `（HTTP ${status}）` : ''}${detail ? `：${detail}` : ''}`);
      } else {
        AppStorage.setOrCreate('bookSourceStageLastError',
          `正文请求失败（HTTP ${status}）${detail ? `：${detail}` : ''}`);
      }
      return '';
    }
    if (!resp.body) return '';
    const ctx = new RuleContext();
    ctx.loadFromJson(book.variable);
    this.seedBookVariables(ctx, book.bookUrl);
    this.seedSourceVariables(ctx, source);
    this.seedChapterVariables(ctx, chapter);
    const contentRule = source.contentRule;
    const parts: string[] = [];
    const seenPageUrls = new Set<string>();
    let currentUrl = resp.url || chapter.url;
    let currentResp = resp;
    let totalLength = 0;
    for (let page = 0; page < 50; page++) {
      if (this.contentRequestCanceled(shouldCancel)) return '';
      if (!currentResp.success || !currentResp.body) break;
      const pageKey = this.urlWithoutFragment(currentResp.url || currentUrl);
      if (seenPageUrls.has(pageKey)) break;
      seenPageUrls.add(pageKey);
      if (this.requestVerificationIfNeeded(source, currentUrl, currentResp.body, currentResp.statusCode, contentRule.content)) {
        break;
      }
      const baseUrl = BookUrlResolver.effectiveBase(currentResp,
        page === 0 ? this.getChapterBaseUrl(chapter, book, source) : currentUrl,
        book.bookUrl || source.bookSourceUrl);
      const pageData = await this.parseContentPage(source, book, chapter, currentResp.body, baseUrl, ctx,
        shouldCancel, debugContext);
      if (this.contentRequestCanceled(shouldCancel)) return '';
      if (pageData.content) {
        totalLength += pageData.content.length;
        if (totalLength > 8 * 1024 * 1024) break;
        parts.push(pageData.content);
      }
      if (!contentRule.nextContentUrl || !pageData.nextUrl) break;
      const nextKey = this.urlWithoutFragment(pageData.nextUrl);
      if (seenPageUrls.has(nextKey)) break;
      currentUrl = pageData.nextUrl;
      currentResp = EncodedSourceUrl.canHandle(currentUrl) ?
        await this.fetchEncodedDataUrl(currentUrl, source) : await au.fetch(currentUrl, undefined, debugContext);
      if (this.contentRequestCanceled(shouldCancel)) return '';
    }
    book.variable = ctx.toPersistentJson();
    return parts.join('\n\n');
  }

  private async parseContentPage(source: BookSource, book: Book, chapter: BookChapter, body: string,
    baseUrl: string, ctx: RuleContext, shouldCancel: (() => boolean) | null = null,
    debugContext: BookSourceDebugContext | null = null): Promise<ContentPageData> {
    const data = new ContentPageData();
    if (this.contentRequestCanceled(shouldCancel)) return data;
    const contentRule = source.contentRule;
    const isAudioContent = source.bookSourceType === 1 || (Number(book.type) & 32) !== 0;
    const directContent = await this.tryGetDirectAjaxRuleContent(source, body, baseUrl, ctx, contentRule.content);
    if (this.contentRequestCanceled(shouldCancel)) return data;
    const fieldRequest = new RuleBatchExecutionRequest();
    fieldRequest.source = source;
    fieldRequest.book = book;
    fieldRequest.chapter = chapter;
    fieldRequest.readerActionMode = true;
    fieldRequest.stage = SourceRuntimeStage.CONTENT;
    fieldRequest.ownerId = `content_fields_${Date.now()}_${chapter.url}`;
    fieldRequest.typedContents = [RuleValue.fromExternal(body)];
    fieldRequest.contents = [body];
    fieldRequest.baseUrl = baseUrl;
    fieldRequest.contextValues = ctx.toPersistentRecord();
    fieldRequest.fields = [
      // A text chapter selector commonly matches one node per paragraph. Content is the one
      // scalar field where all matches are meaningful; ordinary title/URL fields still use the
      // first match exactly as before.
      new RuleFieldRequest('content', directContent ? '' : (contentRule.content || ''), false, false, true),
      new RuleFieldRequest('nextContentUrl', contentRule.nextContentUrl || '', true),
      new RuleFieldRequest('images', contentRule.images || '', false, true)
    ];
    fieldRequest.timeoutMs = 20000;
    fieldRequest.debugContext = debugContext;
    let values: Record<string, string> = {};
    this.activeContentRuleOwners.add(fieldRequest.ownerId);
    try {
      const batch = await RuleExecutionService.get().executeBatch(fieldRequest);
      if (this.contentRequestCanceled(shouldCancel)) return data;
      if (batch.values.length > 0) values = batch.values[0];
      if (batch.contextValues.length > 0) ctx.loadFromJson(batch.contextValues[0]);
      if (batch.errors.length > 0) {
        console.warn('[WS] content field errors:', source.bookSourceName, batch.errors.join('; '));
      }
    } finally {
      this.activeContentRuleOwners.delete(fieldRequest.ownerId);
      RuleExecutionService.get().clearOwner(fieldRequest.ownerId);
    }
    data.nextUrl = values['nextContentUrl'] || '';
    let imageRuleValues = this.parseStringListValue(values['images'] || '');
    if (imageRuleValues.length === 0) {
      imageRuleValues = this.tryExtractScriptedComicImages(body);
    }
    let content = directContent || values['content'] || '';
    // Audio rules return a media address (or JSON/HTML containing one), not reader text.
    // Preserve that value so the audio page can resolve relative, escaped and tagged URLs.
    if (isAudioContent) {
      if (!content) return data;
      data.content = this.applyContentReplaceRule(content, contentRule.replaceRegex, ctx, chapter,
        debugContext).trim();
      return data;
    }
    if (!content || this.isBadExtractedContent(content)) {
      const fallbackContent = this.tryExtractReadableContentFromHtml(body);
      if (fallbackContent) content = fallbackContent;
    }
    if (!content && imageRuleValues.length === 0) return data;
    content = this.applyContentReplaceRule(content, contentRule.replaceRegex, ctx, chapter, debugContext);
    if (this.contentRequestCanceled(shouldCancel)) return data;
    data.content = await this.normalizeReaderContent(source, content, baseUrl, imageRuleValues);
    if (this.contentRequestCanceled(shouldCancel)) data.content = '';
    return data;
  }

  /**
   * Some lightweight comic sites create their image tags in an inline script
   * instead of including them in the returned HTML.  The common shape is a
   * base path plus a page count.  Supporting that shape here avoids executing
   * arbitrary imported JavaScript while still allowing the chapter to stream
   * through the normal reader image pipeline.
   */
  private tryExtractScriptedComicImages(body: string): string[] {
    if (!body) return [];
    const pathMatch = body.match(/\b(?:pasd|imagePath|image_path)\s*=\s*["']([^"']+)["']/i);
    const countMatch = body.match(/\b(?:num|imageCount|image_count)\s*=\s*(?:eval\s*\(\s*)?["']?(\d{1,4})/i);
    if (!pathMatch || !pathMatch[1] || !countMatch || !countMatch[1]) return [];

    const count = Math.min(parseInt(countMatch[1]), 500);
    if (!Number.isFinite(count) || count <= 0) return [];
    const extensionMatch = body.match(/(?:pasd|imagePath|image_path)\s*\+\s*[^+;]+\+\s*["'](\.(?:avif|gif|jpe?g|png|webp))["']/i);
    const extension = extensionMatch && extensionMatch[1] ? extensionMatch[1] : '.webp';
    const images: string[] = [];
    for (let index = 1; index <= count; index++) {
      images.push(`${pathMatch[1]}${index}${extension}`);
    }
    return images;
  }

  private async tryGetDirectAjaxRuleContent(source: BookSource, body: string, baseUrl: string,
    ctx: RuleContext, contentRule: string): Promise<string> {
    const plan = AjaxRuleCompat.directResultPlan(contentRule);
    if (!plan) return '';

    const urlAnalyze = new AnalyzeRule(body, baseUrl, ctx);
    const requestUrl = urlAnalyze.getString(plan.urlRule, true);
    if (!requestUrl || !/^https?:\/\//.test(requestUrl)) return '';

    const response = await new AnalyzeUrl(source, this.http).fetch(requestUrl);
    if (!response.success || !response.body) return '';

    return AjaxRuleCompat.applyReplaceChain(response.body, plan.jsCode);
  }

  private async fetchEncodedDataUrl(url: string, source: BookSource): Promise<{ url: string, statusCode: number, headers: Record<string, string>, body: string, success: boolean, error?: string }> {
    const root = await EncodedSourceUrl.requestJsonForDataUrl(this.http, url, source);
    if (!root) {
      return { url: url, statusCode: 0, headers: {}, body: '', success: false, error: 'encoded data url request failed' };
    }
    return { url: url, statusCode: 200, headers: {}, body: JSON.stringify(root), success: true };
  }

  private requestVerificationIfNeeded(source: BookSource, requestUrl: string, body: string, statusCode: number, rule: string): boolean {
    if (!VerificationSupport.shouldRequestBrowserVerification(source, body, statusCode, rule)) {
      return false;
    }
    const verifyUrl = VerificationSupport.pickVerificationUrl(source, requestUrl, rule);
    VerificationSupport.requestVerification(verifyUrl, `${source.bookSourceName} 验证`, source);
    console.warn('[WS] source needs browser verification:', source.bookSourceName, verifyUrl);
    return true;
  }

  private isBadExtractedContent(content: string): boolean {
    if (!content) return false;
    const sample = content.substring(0, Math.min(content.length, 1200));
    // A failed combined extraction rule must never become chapter text. Require several strong
    // script markers together so ordinary novels that merely mention code are not rejected.
    const leakedRuleScript = /(?:result\s*\.\s*match|\.match\s*\(\s*\/\^https?)/i.test(sample) &&
      /java\s*\.\s*ajax\s*\(/i.test(sample) && /java\s*\.\s*base64Decode\s*\(/i.test(sample);
    return leakedRuleScript || sample.includes('font-family:') || sample.includes('-webkit-text-size-adjust') ||
      sample.includes('.nuxt-progress') || sample.includes('box-sizing:border-box') ||
      sample.includes('<!doctype html') || sample.includes('<html');
  }

  private tryBuildGenericChapterList(book: Book, body: string, baseUrl: string): BookChapter[] {
    if (!body) return [];
    const bookKey = this.extractGenericBookKey(book.tocUrl || book.bookUrl || baseUrl);
    const catalogHtml = this.pickGenericCatalogBlock(body, baseUrl, bookKey);
    let links = this.collectGenericChapterLinks(catalogHtml, baseUrl, bookKey, catalogHtml !== body);
    if (catalogHtml !== body) {
      const bodyLinks = this.collectGenericChapterLinks(body, baseUrl, bookKey, false);
      // A named catalog container can itself be the short "latest chapters" widget. Prefer the
      // full-page candidate when it contains substantially more chapter-like links.
      if (links.length < 3 || bodyLinks.length > links.length * 2) links = bodyLinks;
    }
    links = this.normalizeGenericChapterLinks(links);
    if (links.length < 3) return [];

    const chapters: BookChapter[] = [];
    for (const link of links) {
      const chapter = new BookChapter();
      chapter.title = this.cleanChapterTitle(link['title'] || `第${chapters.length + 1}章`);
      chapter.url = link['url'] || '';
      chapter.bookUrl = book.bookUrl;
      chapter.index = chapters.length;
      chapter.variable = BookUrlResolver.setVariableJson(chapter.variable, 'baseUrl', chapter.url || baseUrl);
      chapter.variable = BookUrlResolver.setVariableJson(chapter.variable,
        WebBookService.GENERIC_TOC_FALLBACK_KEY, 'true');
      if (chapter.title && chapter.url) chapters.push(chapter);
    }
    console.log('[WS] 通用目录兜底:', chapters.length);
    return chapters;
  }

  private tryExtractReadableContentFromHtml(body: string): string {
    if (!body) return '';
    const names = [
      'nr1',
      'chaptercontent',
      'chapter-content',
      'chapter_content',
      'reader-content',
      'read-content',
      'article-content',
      'article_content',
      'TxtContent',
      'txtcontent',
      'word_read',
      'readtxt',
      'booktext',
      'BookText',
      'content',
      'post'
    ];
    const blocks: string[] = [];
    for (const name of names) {
      blocks.push(this.extractIdBlock(body, name));
      blocks.push(this.extractClassBlock(body, name));
    }
    blocks.push(this.extractTagBlock(body, 'article'));

    let best = '';
    let bestScore = 0;
    for (const block of blocks) {
      const text = this.cleanReadableContentText(block);
      const score = this.scoreReadableContent(text);
      if (score > bestScore) {
        best = text;
        bestScore = score;
      }
    }

    if (!best) {
      const text = this.cleanReadableContentText(body);
      if (this.isUsableReadableContent(text)) best = text;
    }
    return best;
  }

  private pickGenericCatalogBlock(body: string, baseUrl: string, bookKey: string): string {
    const names = [
      'book-list',
      'chapter-list',
      'chapterlist',
      'catalog-list',
      'catalog',
      'directory',
      'book-chapter-list',
      'chapters',
      'listmain',
      'list',
      'play_0',
      'volume-list',
      'chapter'
    ];
    let best = '';
    let bestCount = 0;
    for (const name of names) {
      const block = this.extractClassBlock(body, name) || this.extractIdBlock(body, name);
      if (!block) continue;
      const count = this.collectGenericChapterLinks(block, baseUrl, bookKey, true).length;
      if (count > bestCount) {
        best = block;
        bestCount = count;
      }
    }
    return bestCount >= 3 ? best : body;
  }

  private collectGenericChapterLinks(html: string, baseUrl: string, bookKey: string, inCatalogBlock: boolean):
    Record<string, string>[] {
    const links: Record<string, string>[] = [];
    const re = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
    let match: RegExpExecArray | null;
    while ((match = re.exec(html || '')) !== null) {
      const attrs = match[1] || '';
      const hrefMatch = attrs.match(/\shref\s*=\s*["']([^"']+)["']/i);
      if (!hrefMatch || !hrefMatch[1]) continue;
      const url = BookUrlResolver.resolve(this.decodeHtmlEntities(hrefMatch[1]), baseUrl);
      const chapterKey = this.normalizeChapterLinkKey(url);
      if (!chapterKey) continue;
      const titleMatch = attrs.match(/\stitle\s*=\s*["']([^"']+)["']/i);
      const title = this.cleanInlineText(titleMatch && titleMatch[1] ? titleMatch[1] : match[2]);
      if (!title || this.isNavigationTitle(title)) continue;
      const likelyChapter = this.isLikelyChapterTitle(title) || this.isLikelyChapterUrl(url, baseUrl, bookKey);
      if (!inCatalogBlock && !likelyChapter) continue;
      links.push({
        title: title,
        url: url,
        key: chapterKey,
        likely: likelyChapter ? 'true' : 'false'
      });
      if (links.length > 20000) break;
    }
    return links;
  }

  private normalizeGenericChapterLinks(links: Record<string, string>[]): Record<string, string>[] {
    // Pages commonly render a short "latest chapters" block before the complete catalog. Keep
    // duplicate URLs until this point so trimming the leading teaser cannot also discard the same
    // chapters from the complete list.
    const withoutTeaser = this.trimLeadingTeaserLinks(links);
    const unique: Record<string, string>[] = [];
    const seen = new Set<string>();
    for (const link of withoutTeaser) {
      const key = link['key'] || this.normalizeChapterLinkKey(link['url'] || '');
      if (!key || seen.has(key)) continue;
      seen.add(key);
      unique.push(link);
    }
    if (unique.length < 3) return [];

    let likelyCount = 0;
    for (const link of unique) {
      if (link['likely'] === 'true') likelyCount++;
    }
    if (likelyCount < 3 && unique.length > likelyCount * 2) return [];
    return this.normalizeGenericChapterOrder(unique);
  }

  private normalizeGenericChapterOrder(links: Record<string, string>[]): Record<string, string>[] {
    const ordinals: number[] = [];
    for (const link of links) {
      const ordinal = this.extractGenericChapterOrdinal(link['title'] || '');
      if (ordinal >= 0) ordinals.push(ordinal);
    }
    if (ordinals.length < 4) return links;
    let ascending = 0;
    let descending = 0;
    for (let index = 1; index < ordinals.length; index++) {
      if (ordinals[index] > ordinals[index - 1]) ascending++;
      if (ordinals[index] < ordinals[index - 1]) descending++;
    }
    // Only reverse when the evidence is strong. Volume resets and numbered side stories can create
    // occasional decreases in an otherwise ascending catalog and must not flip the whole book.
    if (descending >= 3 && descending > ascending * 2 && ordinals[0] > ordinals[ordinals.length - 1]) {
      return links.slice().reverse();
    }
    return links;
  }

  private extractGenericChapterOrdinal(title: string): number {
    const compact = (title || '').replace(/\s+/g, '').toLowerCase();
    const chineseStyle = compact.match(/^第(\d+)[章节節回卷]/);
    if (chineseStyle) return parseInt(chineseStyle[1]);
    const westernStyle = compact.match(/^(?:chapter|ch\.?)(\d+)/);
    if (westernStyle) return parseInt(westernStyle[1]);
    return -1;
  }

  private trimLeadingTeaserLinks(links: Record<string, string>[]): Record<string, string>[] {
    if (links.length < 6) return links;
    for (let i = 0; i < links.length; i++) {
      if (this.isLikelyFirstChapterTitle(links[i]['title'] || '')) {
        const remain = links.length - i;
        if (i > 0 && remain >= 3) return links.slice(i);
        return links;
      }
    }
    return links;
  }

  private isLikelyFirstChapterTitle(title: string): boolean {
    const compact = (title || '').replace(/\s+/g, '').toLowerCase();
    return /^chapter0/.test(compact) || /^chapter1/.test(compact) ||
      /^第(一|1|１|壹)[章节節回]/.test(compact) || /^第0[章节節回]/.test(compact) ||
      compact.startsWith('序章') || compact.startsWith('楔子') ||
      compact.startsWith('引子') || compact.startsWith('前言');
  }

  private isLikelyChapterTitle(title: string): boolean {
    const compact = (title || '').replace(/\s+/g, '').toLowerCase();
    return /^chapter\d+/.test(compact) || /^ch\.\d+/.test(compact) ||
      /^第[\d一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾兩两]+[章节節回卷]/.test(compact) ||
      compact.startsWith('序章') || compact.startsWith('楔子') || compact.startsWith('引子') ||
      compact.startsWith('前言') || compact.startsWith('番外');
  }

  private isNavigationTitle(title: string): boolean {
    const compact = (title || '').replace(/\s+/g, '');
    return !compact || compact === '開始閱讀' || compact === '开始阅读' || compact === '最近閱讀' ||
      compact === '最近阅读' || compact === '上次閱讀' || compact === '上次阅读' ||
      compact === '阅读记录' || compact === '書頁/目錄' || compact === '书页/目录' ||
      compact === '上一章' || compact === '下一章' || compact === '上一頁' || compact === '下一頁' ||
      compact === '上一页' || compact === '下一页' || compact === '首頁' || compact === '首页' ||
      compact === '返回目录' || compact === '返回目錄' || compact === '書庫' || compact === '书库' ||
      compact === '作者' || compact === '目录' || compact === '目錄' || compact === '首页';
  }

  private cleanChapterTitle(title: string): string {
    const original = this.cleanInlineText(title || '');
    const cleaned = original
      .replace(/\s+/g, ' ')
      .replace(/[\s·|｜/／-]*上次(?:阅读|閱讀)(?:[\s:：，,。]*.*)?$/g, '')
      .replace(/^上次(?:阅读|閱讀)[\s:：，,。]*/g, '')
      .trim();
    return cleaned || original;
  }

  private extractGenericBookKey(url: string): string {
    const clean = (url || '').replace(/[?#].*$/, '').replace(/\.html?$/i, '');
    const segments = clean.split('/').filter(part => part.length > 0);
    if (segments.length === 0) return '';
    const last = segments[segments.length - 1];
    if (/^[A-Za-z0-9_-]{2,60}$/.test(last)) return last;
    return '';
  }

  private normalizeChapterLinkKey(url: string): string {
    const clean = (url || '').replace(/#[\s\S]*$/, '').replace(/[?&](?:from|spm|utm_[^=]+)=[^&]*/g, '');
    return clean.replace(/[?&]$/g, '').replace(/\/$/g, '');
  }

  private isLikelyChapterUrl(url: string, baseUrl: string, bookKey: string): boolean {
    const clean = (url || '').replace(/[?#].*$/, '').toLowerCase();
    if (!clean || clean === (baseUrl || '').replace(/[?#].*$/, '').toLowerCase()) return false;
    if (bookKey && clean.includes(`/${bookKey.toLowerCase()}/`)) return true;
    if (/\/(?:chapter|read|content|book)\/[^/]+\/[^/]+/.test(clean)) return true;
    const last = clean.split('/').filter(part => part.length > 0).pop() || '';
    return /^(?:\d+|chapter[_-]?\d+|ch[_-]?\d+|read[_-]?\d+)\.html?$/.test(last);
  }

  private cleanInlineText(value: string): string {
    return this.decodeHtmlEntities(value || '')
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<[^>]+>/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private cleanReadableContentText(html: string): string {
    if (!html) return '';
    const raw = this.decodeHtmlEntities(html)
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<iframe[\s\S]*?<\/iframe>/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      // A number of novel sites use one <div> per paragraph. Keep a blank line
      // so the reader's soft-line normalizer cannot merge adjacent paragraphs.
      .replace(/<\/div>/gi, '\n\n')
      .replace(/<\/li>/gi, '\n')
      .replace(/<h[1-6][^>]*>[\s\S]*?<\/h[1-6]>/gi, '\n')
      .replace(/<[^>]+>/g, '\n')
      .replace(/\r\n?/g, '\n');
    const lines: string[] = [];
    for (const sourceLine of raw.split('\n')) {
      let line = sourceLine.replace(/\s+/g, ' ').trim();
      if (!line || this.isNoiseLine(line)) continue;
      line = this.repairReversedLine(line);
      if (line && !this.isNoiseLine(line)) lines.push(line);
      if (lines.length > 4000) break;
    }
    return lines.join('\n\n')
      .replace(/\(本章完\)/g, '')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private repairReversedLine(line: string): string {
    const value = line.trim();
    if (!/^[。！？!?，,、；;：:）」』”]/.test(value)) return value;
    let reversed = '';
    for (let i = value.length - 1; i >= 0; i--) {
      reversed += value.charAt(i);
    }
    return reversed
      .replace(/([\u3400-\u9fff])\s+(?=[\u3400-\u9fff])/g, '$1')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private isNoiseLine(line: string): boolean {
    const compact = (line || '').replace(/\s+/g, '');
    return !compact || compact === 'A-AA+' || compact === '默認米黃護眼' || compact === '默认米黄护眼' ||
      compact.includes('檢舉本章錯誤') || compact.includes('检举本章错误') ||
      compact.includes('猜你喜歡') || compact.includes('猜你喜欢') ||
      compact.includes('確認檢舉') || compact.includes('确认检举') ||
      compact.includes('請選擇檢舉原因') || compact.includes('请选择检举原因') ||
      compact.includes('版權所有') || compact.includes('版权所有') ||
      compact.includes('如果被转码') || compact.includes('如果被轉碼') ||
      compact.includes('阅读模式') || compact.includes('閱讀模式') ||
      compact.includes('本章没完') || compact.includes('本章未完') ||
      compact.includes('继续阅读') || compact.includes('繼續閱讀') ||
      compact.includes('上一章') || compact.includes('下一章') ||
      compact.includes('上一頁') || compact.includes('下一頁') ||
      compact.includes('书页/目录') || compact.includes('書頁/目錄');
  }

  private scoreReadableContent(text: string): number {
    if (!this.isUsableReadableContent(text)) return 0;
    const lines = text.split('\n').filter(line => line.trim().length > 0).length;
    return text.length + lines * 80;
  }

  private isUsableReadableContent(text: string): boolean {
    if (!text || text.length < 30) return false;
    const compact = text.replace(/\s+/g, '');
    if (compact.includes('搜尋書名或作者') && compact.length < 200) return false;
    if (compact.includes('請輸入書名') && compact.length < 300) return false;
    if (compact.includes('请输入书名') && compact.length < 300) return false;
    return true;
  }

  private extractClassBlock(html: string, className: string): string {
    return this.extractAttrBlock(html, 'class', className);
  }

  private extractIdBlock(html: string, id: string): string {
    return this.extractAttrBlock(html, 'id', id);
  }

  private extractAttrBlock(html: string, attrName: string, attrValue: string): string {
    const re = new RegExp(`<([a-zA-Z][\\w-]*)([^>]*\\s${attrName}=["'][^"']*\\b` +
      `${this.escapeRegex(attrValue)}\\b[^"']*["'][^>]*)>`, 'i');
    const m = re.exec(html);
    if (!m) return '';
    const start = m.index;
    const tag = m[1];
    const tagRe = new RegExp(`<\\/?${this.escapeRegex(tag)}(?:\\s[^>]*)?>`, 'gi');
    tagRe.lastIndex = start;
    let depth = 0;
    let tm: RegExpExecArray | null;
    while ((tm = tagRe.exec(html)) !== null) {
      if (tm[0].startsWith('</')) {
        depth--;
        if (depth === 0) return html.substring(start, tagRe.lastIndex);
      } else if (!tm[0].endsWith('/>')) {
        depth++;
      }
    }
    return html.substring(start);
  }

  private extractTagBlock(html: string, tagName: string): string {
    if (!html || !tagName) return '';
    const tag = this.escapeRegex(tagName);
    const re = new RegExp(`<${tag}(?:\\s[^>]*)?>`, 'i');
    const m = re.exec(html);
    if (!m) return '';
    const start = m.index;
    const tagRe = new RegExp(`<\\/?${tag}(?:\\s[^>]*)?>`, 'gi');
    tagRe.lastIndex = start;
    let depth = 0;
    let tm: RegExpExecArray | null;
    while ((tm = tagRe.exec(html)) !== null) {
      if (tm[0].startsWith('</')) {
        depth--;
        if (depth === 0) return html.substring(start, tagRe.lastIndex);
      } else if (!tm[0].endsWith('/>')) {
        depth++;
      }
    }
    return html.substring(start);
  }

  private decodeHtmlEntities(value: string): string {
    return (value || '')
      .replace(/&#x([0-9a-fA-F]+);/g, (_: string, hex: string) => String.fromCharCode(parseInt(hex, 16)))
      .replace(/&#(\d+);/g, (_: string, num: string) => String.fromCharCode(parseInt(num, 10)))
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&#39;/g, "'");
  }

  private async normalizeReaderContent(source: BookSource, content: string, baseUrl: string,
    imageRuleValues: string[] = []): Promise<string> {
    const explicitImages = this.collectReaderImageUrls(imageRuleValues, baseUrl, true);
    if (explicitImages.length > 0) {
      return await this.materializeReaderImageMarkers(source,
        explicitImages.map((url: string): string => ReaderImageMarker.create(url)).join('\n\n'));
    }

    let value = content || '';
    value = this.convertReaderNativeActions(source, value, baseUrl);
    value = value.replace(/<(?:img|image)\b[^>]*>/gi, (tag: string): string => {
      const images = this.collectReaderImageUrls([tag], baseUrl, false);
      return images.length > 0 ? `\n\n${ReaderImageMarker.create(images[0])}\n\n` : ' ';
    });
    value = value.replace(/!\[[^\]]*\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g,
      (_all: string, rawUrl: string): string => {
        const url = this.normalizeReaderImageUrl(rawUrl, baseUrl, true);
        return url ? `\n\n${ReaderImageMarker.create(url)}\n\n` : ' ';
      });

    const lines: string[] = [];
    for (const rawLine of value.replace(/\r\n?/g, '\n').split('\n')) {
      const line = rawLine.trim();
      const imageUrl = this.normalizeReaderImageUrl(line, baseUrl, false);
      if (imageUrl && this.isLikelyReaderImageUrl(line)) {
        lines.push(ReaderImageMarker.create(imageUrl));
      } else {
        lines.push(rawLine);
      }
    }

    const normalized = lines.join('\n')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n\n')
      // Preserve block-level paragraph boundaries from div-based chapter HTML.
      .replace(/<\/div>/gi, '\n\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/[ \t]{2,}/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    return await this.materializeReaderImageMarkers(source, ReaderActionMarker.limit(normalized));
  }

  private convertReaderNativeActions(_source: BookSource, content: string, _baseUrl: string): string {
    if (!content) return content;
    let value = this.convertReaderImageScriptActions(content);
    value = value.replace(/<p\b[^>]*>\s*<img\b([^>]*\bident\s*=\s*["'][^"']+["'][^>]*)\/?\s*>\s*<\/p>/gi,
      (_all: string, attrs: string): string => {
        const identMatch = /\bident\s*=\s*["']([^"']+)["']/i.exec(attrs || '');
        const url = this.decodeHtmlEntities(identMatch && identMatch[1] ? identMatch[1] : '');
        const marker = ReaderActionMarker.create('神评论', url, '神评论');
        return marker ? `${marker}\n` : '';
      });
    value = value.replace(/<p\b[^>]*>([\s\S]*?)<comment\b([^>]*)\/?>([\s\S]*?)<\/p>/gi,
      (_all: string, before: string, attrs: string, after: string): string => {
        const text = this.decodeHtmlEntities(`${before || ''}${after || ''}`.replace(/<[^>]+>/g, '')).trim();
        const marker = this.readerActionMarkerFromCommentAttributes(attrs || '');
        return `${text}${marker}\n`;
      });
    if (!/<(?:div|span)\b[^>]*\brs-native\b/i.test(value)) return value;
    return value.replace(/<(div|span)\b[^>]*\brs-native\b[^>]*>([\s\S]*?)<\/\1>/gi,
      (_all: string, _tagName: string, inner: string): string => {
        const comment = /<comment\b([^>]*)>/i.exec(inner || '');
        const text = this.decodeHtmlEntities((inner || '').replace(/<comment\b[^>]*>/gi, '')
          .replace(/<[^>]+>/g, '')).trim();
        if (!comment) return text ? `${text}\n` : '';
        const marker = this.readerActionMarkerFromCommentAttributes(comment[1] || '');
        return `${text}${marker}\n`;
      });
  }

  /**
   * Android-style Legado sources can render a clickable data-image whose trailing source options
   * contain a click/js expression. Convert that expression into a deferred reader action. The
   * expression is executed only after the user taps it, in the same bounded source runtime.
   */
  private convertReaderImageScriptActions(content: string): string {
    return (content || '').replace(/<img\b[^>]*>/gi, (tag: string): string => {
      const data = /data:image\/[A-Za-z0-9.+-]+;base64,([A-Za-z0-9+/=]+),(\{[\s\S]*\})/i.exec(tag);
      if (!data || !data[2]) return tag;
      const action = /["'](?:click|js)["']\s*:\s*(["'])([\s\S]*?)\1(?:\s*,|\s*})/i.exec(data[2]);
      if (!action || !action[2]) return tag;
      const count = this.readerDataImageLabel(data[1] || '');
      const label = count ? `段评 ${count}` : '段评';
      const marker = ReaderActionMarker.createSourceScript(label, this.decodeHtmlEntities(action[2]), '段评');
      // This data-image is an interaction control, not正文 artwork. If its imported click script exceeds the
      // bounded action budget, drop the control instead of passing the enormous base64/options tag into the
      // ordinary image pipeline (the latter can exhaust memory while opening the chapter).
      return marker ? `${marker}\n` : '';
    });
  }

  private readerDataImageLabel(encoded: string): string {
    try {
      const bytes = new util.Base64Helper().decodeSync(encoded || '');
      const svg = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
      const labels = svg.match(/<text\b[^>]*>([^<]{1,24})<\/text>/gi) || [];
      for (const item of labels) {
        const text = this.decodeHtmlEntities(item.replace(/<[^>]+>/g, '')).trim();
        if (/^(?:\d+|99\+)$/.test(text)) return text;
      }
    } catch (_) {
    }
    return '';
  }

  private readerActionMarkerFromCommentAttributes(attrs: string): string {
    const countMatch = /\bcount\s*=\s*["']([^"']*)["']/i.exec(attrs || '');
    const identMatch = /\bident\s*=\s*["']([^"']*)["']/i.exec(attrs || '');
    const pressMatch = /\b(?:onPress|onClick|click)\s*=\s*(["'])([\s\S]*?)\1/i.exec(attrs || '');
    const actionMatch = pressMatch ?
      /java\.(?:showReadingBrowser|startBrowserDp|startBrowser|showBrowser)\(\s*(["'])([\s\S]*?)\1(?:\s*,\s*(["'])([\s\S]*?)\3)?/i.exec(pressMatch[2]) : null;
    const url = this.decodeHtmlEntities(actionMatch && actionMatch[2] ? actionMatch[2] :
      (identMatch && identMatch[1] ? identMatch[1] : ''));
    if (!url) return '';
    const rawTitle = this.decodeHtmlEntities(actionMatch && actionMatch[4] ? actionMatch[4] : '');
    const count = this.decodeHtmlEntities(countMatch && countMatch[1] ? countMatch[1] : '');
    const isComment = /\/comments(?:[/?#]|$)|\/idea_comment(?:[/?#]|$)|\/get_review(?:[/?#]|$)/i.test(url);
    const title = isComment ? (rawTitle ? `段评 · ${rawTitle}` : '段评') : (rawTitle || '打开');
    const label = isComment ? (count ? `段评 ${count}` : '段评') : (count ? `${title} ${count}` : title);
    return ReaderActionMarker.create(label, url, title);
  }

  private async materializeReaderImageMarkers(source: BookSource, content: string): Promise<string> {
    if (!content || !content.includes(ReaderImageMarker.PREFIX)) return content;
    const pattern = new RegExp(`${this.escapeRegex(ReaderImageMarker.PREFIX)}([^\\]]+)` +
      `${this.escapeRegex(ReaderImageMarker.SUFFIX)}`, 'g');
    const values: string[] = [];
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(content)) !== null) {
      try {
        const raw = decodeURIComponent(match[1]);
        if (raw && !values.includes(raw)) values.push(raw);
      } catch (_) {
      }
    }
    if (values.length === 0) return content;
    const resolved: Record<string, string> = {};
    for (let start = 0; start < values.length; start += 4) {
      const batch = values.slice(start, start + 4);
      const paths = await Promise.all(batch.map((value: string): Promise<string> =>
        ComicImagePipeline.materialize(this.http, source, value)));
      for (let index = 0; index < batch.length; index++) {
        resolved[batch[index]] = paths[index] || batch[index];
      }
    }
    return content.replace(pattern, (_all: string, encoded: string): string => {
      try {
        const raw = decodeURIComponent(encoded);
        return ReaderImageMarker.create(resolved[raw] || raw);
      } catch (_) {
        return _all;
      }
    });
  }

  private collectReaderImageUrls(values: string[], baseUrl: string, trustPlainValue: boolean): string[] {
    const result: string[] = [];
    const seen = new Set<string>();
    for (const rawValue of values) {
      const value = this.decodeHtmlEntities(rawValue || '').trim();
      if (!value) continue;
      const tags = value.match(/<(?:img|image|source|object)\b[^>]*>/gi) || [];
      for (const tag of tags) {
        const attrValue = this.findReaderImageAttribute(tag);
        this.appendReaderImageUrl(result, seen, attrValue, baseUrl, true);
      }
      const markdown = /!\[[^\]]*\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g;
      let markdownMatch: RegExpExecArray | null;
      while ((markdownMatch = markdown.exec(value)) !== null) {
        this.appendReaderImageUrl(result, seen, markdownMatch[1], baseUrl, true);
      }
      if (tags.length === 0 && trustPlainValue) {
        const parts = this.splitReaderImageRuleValue(value);
        for (const part of parts) {
          this.appendReaderImageUrl(result, seen, part, baseUrl, true);
        }
      }
    }
    return result;
  }

  private appendReaderImageUrl(result: string[], seen: Set<string>, rawUrl: string, baseUrl: string,
    trustValue: boolean): void {
    const url = this.normalizeReaderImageUrl(rawUrl, baseUrl, trustValue);
    if (!url || seen.has(url)) return;
    seen.add(url);
    result.push(url);
  }

  private findReaderImageAttribute(tag: string): string {
    const protectedSource = /(?:^|\s)(?:src|data-r-src|data-src)\s*=\s*["']([\s\S]*,\s*\{[\s\S]*\})["']/i.exec(tag);
    if (protectedSource && protectedSource[1]) return protectedSource[1];
    const names = ['data-original', 'data-src', 'data-url', 'data-lazy-src', 'data-echo', 'src',
      'data-r-src', 'xlink:href', 'href', 'srcset'];
    for (const name of names) {
      const escaped = name.replace(':', '\\:');
      const quoted = new RegExp(`(?:^|\\s)${escaped}\\s*=\\s*["']([^"']+)["']`, 'i').exec(tag);
      if (quoted && quoted[1]) return name === 'srcset' ? quoted[1].split(',')[0].trim().split(/\s+/)[0] : quoted[1];
      const unquoted = new RegExp(`(?:^|\\s)${escaped}\\s*=\\s*([^\\s>]+)`, 'i').exec(tag);
      if (unquoted && unquoted[1]) return name === 'srcset' ? unquoted[1].split(',')[0].trim().split(/\s+/)[0] : unquoted[1];
    }
    return '';
  }

  private splitReaderImageRuleValue(value: string): string[] {
    const trimmed = value.trim().replace(/^\[|\]$/g, '');
    if (!trimmed) return [];
    return trimmed.split(/(?:\r?\n|\|\||,\s*(?=["']?(?:https?:|\/|\.\.?\/)))/)
      .map((item: string): string => item.trim().replace(/^['"]|['"]$/g, ''))
      .filter((item: string): boolean => item.length > 0);
  }

  private normalizeReaderImageUrl(rawUrl: string, baseUrl: string, trustValue: boolean): string {
    let value = this.decodeHtmlEntities(rawUrl || '').trim()
      .replace(/^url\(\s*|\s*\)$/gi, '')
      .replace(/^['"]|['"]$/g, '');
    if (!value || /^(?:javascript:|about:|#)/i.test(value)) return '';
    const optionIndex = this.readerImageOptionIndex(value);
    const options = optionIndex >= 0 ? value.substring(optionIndex) : '';
    if (optionIndex >= 0) value = value.substring(0, optionIndex).trim();
    if (!trustValue && !this.isLikelyReaderImageUrl(value)) return '';
    if (/^data:image\//i.test(value)) return value;
    if (/^(?:https?:)?\/\//i.test(value) || /^\.?\.?\//.test(value)) {
      const resolved = BookUrlResolver.resolve(value, baseUrl);
      return resolved ? `${resolved}${options}` : '';
    }
    if (trustValue && !/\s/.test(value) && !value.startsWith('<') && !value.startsWith('{')) {
      const resolved = BookUrlResolver.resolve(value, baseUrl);
      return resolved ? `${resolved}${options}` : '';
    }
    return '';
  }

  private readerImageOptionIndex(value: string): number {
    for (let index = value.length - 1; index >= 0; index--) {
      if (value.charAt(index) !== ',') continue;
      const tail = value.substring(index + 1).trim();
      if (tail.startsWith('{') && tail.endsWith('}')) return index;
    }
    return -1;
  }

  private isLikelyReaderImageUrl(value: string): boolean {
    const clean = (value || '').trim();
    return /^data:image\//i.test(clean) ||
      /\.(?:avif|bmp|gif|jpe?g|png|svg|webp)(?:[?#].*)?$/i.test(clean);
  }

  private escapeRegex(value: string): string {
    return (value || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  private applyContentReplaceRule(content: string, replaceRule: string, ctx: RuleContext,
    chapter: BookChapter, debugContext: BookSourceDebugContext | null = null): string {
    if (!content) return content;
    let value = content
      .replace(/<\/p>\s*<p/gi, '</p>\n<p')
      .replace(/<br\s*\/?>/gi, (match: string) => `${match}\n`);
    const beforeReplace = value;
    if (!replaceRule) {
      if (debugContext) debugContext.recordContentReplaceComparison(beforeReplace, value);
      return value;
    }
    const jsIndex = replaceRule.indexOf('@js:');
    const regexPart = (jsIndex >= 0 ? replaceRule.substring(0, jsIndex) : replaceRule).trim();
    const jsPart = jsIndex >= 0 ? replaceRule.substring(jsIndex + 4).trim() : '';
    if (regexPart) {
      let pattern = '';
      let replacement = '';
      if (regexPart.startsWith('##')) {
        pattern = regexPart.substring(2);
      } else {
        const delimiter = this.findUnescapedDoubleHash(regexPart);
        if (delimiter >= 0) {
          pattern = regexPart.substring(0, delimiter);
          replacement = regexPart.substring(delimiter + 2);
        } else {
          pattern = regexPart;
        }
      }
      pattern = this.expandRuleTemplate(pattern.replace(/\\##/g, '##'), ctx);
      replacement = this.expandRuleTemplate(replacement.replace(/\\##/g, '##'), ctx);
      if (pattern) {
        try {
          value = value.replace(new RegExp(pattern, 'g'), replacement);
        } catch (_) {
        }
      }
    }
    if (jsPart) {
      const env = new ScriptEngineContext();
      env.content = value;
      env.baseUrl = chapter.url;
      env.ctx = ctx;
      const result = new ScriptEngine(new JsRuntime()).evalResultJs(jsPart, value, env);
      if (result.handled) value = result.value;
    }
    if (debugContext) debugContext.recordContentReplaceComparison(beforeReplace, value);
    return value;
  }

  private findUnescapedDoubleHash(value: string): number {
    for (let i = 0; i < value.length - 1; i++) {
      if (value.charAt(i) === '#' && value.charAt(i + 1) === '#' && value.charAt(i - 1) !== '\\') {
        return i;
      }
    }
    return -1;
  }

  private expandRuleTemplate(value: string, ctx: RuleContext): string {
    return (value || '').replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_: string, key: string) => {
      return ctx.get(key.trim());
    });
  }

  private async runStageRule(source: BookSource, book: Book, rawRule: string, content: string,
    baseUrl: string, stage: string, chapter: BookChapter | null = null,
    variables: Record<string, string> = {}, debugContext: BookSourceDebugContext | null = null): Promise<string> {
    const code = this.stageRuleCode(rawRule);
    if (!code) return '';
    const decision = BookSourceRuntimeRouter.decide(stage, `${source.jsLib || ''}\n${code}`);
    if (decision.runtime !== 'arkweb') {
      AppStorage.setOrCreate('bookSourceStageLastError', `${stage} 阶段未路由到完整脚本运行层`);
      return '';
    }
    const runtime = BookSourceStageWebRuntime.get();
    if (!await runtime.waitUntilAvailable()) {
      AppStorage.setOrCreate('bookSourceStageLastError', `${stage} 阶段脚本运行环境未就绪`);
      return '';
    }
    const request = new StageWebRuntimeRequest();
    request.applyStageBudget(stage);
    request.source = source;
    request.book = book;
    request.chapter = chapter;
    request.readerActionMode = stage === SourceRuntimeStage.CONTENT;
    request.code = code;
    request.content = content || '';
    request.contextContent = '';
    request.baseUrl = baseUrl || book.bookUrl || source.bookSourceUrl;
    request.variables = { ...variables, ...(chapter ? EncodedSourceUrl.scalarVariables(chapter.url) : {}) };
    request.debugContext = debugContext;
    try {
      const result = await runtime.execute(request);
      let value = result.value || '';
      const trailingRule = this.stageTrailingRule(rawRule);
      if (value && trailingRule) {
        const transformed = this.applyStageTrailingRule(value, trailingRule, request.baseUrl);
        console.info('[WS] stage trailing rule:', stage, trailingRule,
          'input:', value.length, 'output:', transformed.length);
        value = transformed;
      }
      return value;
    } catch (error) {
      console.warn('[WS] stage runtime failed:', source.bookSourceName, stage, error);
      const message = error instanceof Error ? error.message : String(error || '');
      AppStorage.setOrCreate('bookSourceStageLastError', `${stage} 阶段：${message || '脚本执行失败'}`);
      return '';
    }
  }

  private async executeSingleRuleField(source: BookSource, book: Book, chapter: BookChapter | null,
    rawRule: string, content: string, baseUrl: string, stage: string, ctx: RuleContext,
    resolveUrl: boolean = false, debugContext: BookSourceDebugContext | null = null): Promise<string> {
    if (!rawRule) return '';
    const request = new RuleBatchExecutionRequest();
    request.source = source;
    request.book = book;
    request.chapter = chapter;
    request.readerActionMode = stage === SourceRuntimeStage.CONTENT;
    request.stage = stage;
    request.ownerId = `${stage}_field_${Date.now()}_${book.bookUrl}`;
    request.typedContents = [RuleValue.fromExternal(content)];
    request.contents = [content];
    request.baseUrl = baseUrl;
    request.contextValues = ctx.toPersistentRecord();
    request.fields = [new RuleFieldRequest('value', rawRule, resolveUrl)];
    request.timeoutMs = 15000;
    request.debugContext = debugContext;
    try {
      const batch = await RuleExecutionService.get().executeBatch(request);
      if (batch.contextValues.length > 0) ctx.loadFromJson(batch.contextValues[0]);
      if (batch.errors.length > 0) {
        console.warn('[WS] single field error:', source.bookSourceName, stage, batch.errors.join('; '));
      }
      return batch.values.length > 0 ? batch.values[0]['value'] || '' : '';
    } finally {
      RuleExecutionService.get().clearOwner(request.ownerId);
    }
  }

  private parseStringListValue(value: string): string[] {
    if (!value) return [];
    try {
      const parsed = JSON.parse(value) as Object;
      if (!Array.isArray(parsed)) return [];
      return (parsed as Object[]).map((item: Object): string => String(item || ''))
        .filter((item: string): boolean => !!item);
    } catch (_) {
      return [];
    }
  }

  private stageRuleCode(rawRule: string): string {
    const raw = (rawRule || '').trim();
    if (/^@?js:/i.test(raw)) return raw.replace(/^@?js:\s*/i, '');
    const leadingBlock = raw.match(/^<js>\s*([\s\S]*?)<\/js>/i);
    if (leadingBlock) return leadingBlock[1] || '';
    return '';
  }

  private stageTrailingRule(rawRule: string): string {
    const raw = (rawRule || '').trim();
    if (!raw.toLowerCase().startsWith('<js>')) return '';
    const closeIndex = raw.toLowerCase().indexOf('</js>');
    if (closeIndex < 0) return '';
    const trailing = raw.substring(closeIndex + 5).trim();
    if (!trailing || trailing.startsWith('##') || /^@?js:/i.test(trailing)) return '';
    return trailing;
  }

  private applyStageTrailingRule(value: string, trailingRule: string, baseUrl: string): string {
    // Scalar extraction normally returns the first match, but a stage pipeline must preserve
    // an array selected by a simple JSONPath (for example a complete catalog in $.data or
    // $.[*]). AnalyzeRule#getString joins wildcard matches as text, which removes the outer
    // JSON array and makes the following stage unable to deserialize the item list.
    const normalizedRule = trailingRule.replace(/\.\[\*\]$/, '[*]');
    const preserveArray = normalizedRule.endsWith('[*]');
    const propertyRule = preserveArray ? normalizedRule.substring(0, normalizedRule.length - 3) : normalizedRule;
    if (propertyRule === '$' || /^\$(?:\.[A-Za-z_$][A-Za-z0-9_$-]*)+$/.test(propertyRule)) {
      try {
        let current = JSON.parse(value || '{}') as Object;
        const parts = propertyRule === '$' ? [] : propertyRule.substring(2).split('.');
        for (const part of parts) {
          if (!current || typeof current !== 'object' || Array.isArray(current)) return '';
          current = (current as Record<string, Object>)[part];
        }
        if (current === undefined || current === null) return '';
        if (preserveArray && !Array.isArray(current)) return '';
        return typeof current === 'string' ? current as string : JSON.stringify(current);
      } catch (_) {
      }
    }
    return new AnalyzeRule(value, baseUrl).getString(trailingRule);
  }

  private async parseStageChapterList(source: BookSource, book: Book, raw: string,
    baseUrl: string, maxItems: number = 0,
    debugContext: BookSourceDebugContext | null = null): Promise<BookChapter[]> {
    let values: Object[] = [];
    try {
      const parsed = JSON.parse(raw || '[]') as Object;
      if (Array.isArray(parsed)) values = parsed;
    } catch (_) {
      return [];
    }
    const chapters: BookChapter[] = [];
    const tocRule = source.tocRule;
    const records: Record<string, Object>[] = [];
    const items: string[] = [];
    for (const value of values) {
      if (!value || typeof value !== 'object' || Array.isArray(value)) continue;
      records.push(value as Record<string, Object>);
      items.push(JSON.stringify(value));
      if (maxItems > 0 && items.length >= maxItems) break;
    }
    if (items.length === 0) return chapters;
    const ctx = new RuleContext();
    ctx.loadFromJson(book.variable);
    this.seedBookVariables(ctx, book.bookUrl);
    this.seedSourceVariables(ctx, source);
    const fieldRequest = new RuleBatchExecutionRequest();
    fieldRequest.source = source;
    fieldRequest.book = book;
    fieldRequest.stage = SourceRuntimeStage.TOC;
    fieldRequest.ownerId = `stage_toc_fields_${Date.now()}_${book.bookUrl}`;
    fieldRequest.typedContents = records.map((record: Record<string, Object>, index: number): RuleValue => {
      return RuleValue.jsonValue(record, items[index] || JSON.stringify(record));
    });
    fieldRequest.contents = items;
    fieldRequest.baseUrl = baseUrl;
    fieldRequest.contextValues = ctx.toPersistentRecord();
    fieldRequest.fields = [
      new RuleFieldRequest('chapterName', tocRule.chapterName || ''),
      new RuleFieldRequest('chapterUrl', tocRule.chapterUrl || ''),
      new RuleFieldRequest('isVip', tocRule.isVip || ''),
      new RuleFieldRequest('updateTime', tocRule.updateTime || '')
    ];
    fieldRequest.timeoutMs = 30000;
    fieldRequest.debugContext = debugContext;
    let parsedFields: Record<string, string>[] = [];
    try {
      const batch = await RuleExecutionService.get().executeBatch(fieldRequest);
      parsedFields = batch.values;
      if (batch.contextValues.length > 0) ctx.loadFromJson(batch.contextValues[batch.contextValues.length - 1]);
      if (batch.errors.length > 0) {
        console.warn('[WS] stage toc field errors:', source.bookSourceName, batch.errors.join('; '));
      }
    } finally {
      RuleExecutionService.get().clearOwner(fieldRequest.ownerId);
    }
    const parsingSlice = CooperativeScheduler.createTimeSlice();
    for (let index = 0; index < records.length; index++) {
      if (index > 0) await parsingSlice.checkpoint();
      const record = records[index];
      const fields = index < parsedFields.length ? parsedFields[index] : {};
      const isVolume = record['isVolume'] === true || String(record['isVolume'] || '') === 'true';
      const title = this.cleanChapterTitle(fields['chapterName'] || String(record['title'] || ''));
      let url = fields['chapterUrl'] || String(record['url'] || '');
      if (!title || isVolume || !url) continue;
      const virtualPayload = this.ruleExpectsHexDataUrlInput(source.contentRule.content || '') ?
        this.extractVirtualChapterPayload(url) : '';
      if (virtualPayload) url = virtualPayload;
      else if (!url.startsWith('data:')) url = BookUrlResolver.resolve(url, baseUrl);
      const chapter = new BookChapter();
      chapter.title = title;
      chapter.url = url;
      chapter.bookUrl = book.bookUrl;
      chapter.index = chapters.length;
      chapter.isVip = fields['isVip'] === 'true' || record['v'] === true;
      chapter.variable = BookUrlResolver.setVariableJson(chapter.variable, 'baseUrl', baseUrl);
      const updateTime = fields['updateTime'] || String(record['t'] || '');
      if (updateTime) chapter.variable = BookUrlResolver.setVariableJson(chapter.variable, 'updateTime', updateTime);
      chapters.push(chapter);
    }
    book.variable = ctx.toPersistentJson();
    return chapters;
  }

  private async tryGetStageContent(source: BookSource, book: Book, chapter: BookChapter,
    debugContext: BookSourceDebugContext | null = null): Promise<string> {
    const rawRule = source.contentRule.content || '';
    const code = this.stageRuleCode(rawRule);
    if (!code) return '';
    const decision = BookSourceRuntimeRouter.decide(SourceRuntimeStage.CONTENT,
      `${source.jsLib || ''}\n${code}`);
    if (decision.runtime !== 'arkweb') return '';
    const runtime = BookSourceStageWebRuntime.get();
    if (!await runtime.waitUntilAvailable()) return '';
    let content = '';
    let baseUrl = chapter.url || book.bookUrl || source.bookSourceUrl;
    const virtualChapterPayload = this.extractVirtualChapterPayload(chapter.url);
    console.info('[WS] stage content input:', source.bookSourceName,
      virtualChapterPayload ? `virtual(${virtualChapterPayload.length})` : `url(${(chapter.url || '').length})`);
    const payload = EncodedSourceUrl.decode(chapter.url);
    if (payload && this.ruleExpectsHexDataUrlInput(rawRule)) {
      content = this.textToHex(payload.text);
    } else if (payload) {
      // A source-defined data URL is an opaque chapter descriptor. Legado exposes its decoded
      // identity to the content script; it must never be sent to the native HTTP client as if it
      // were a remote URL. Keep baseUrl unchanged so scripts can still read the full descriptor.
      content = payload.text || virtualChapterPayload || chapter.url;
    } else if (this.ruleExpectsHexDataUrlInput(rawRule) && virtualChapterPayload) {
      // Aggregating sources often return a chapter identity such as
      // `book_id=...&item_id=...`. It is rule input, not a relative web address. Legado exposes
      // this value to the content script as bytes; mirror that contract without interpreting it.
      content = this.textToHex(virtualChapterPayload);
    } else {
      const response = await new AnalyzeUrl(source, this.http).fetch(chapter.url, undefined, debugContext);
      if (!response.success || !response.body) return '';
      content = response.body;
      baseUrl = BookUrlResolver.effectiveBase(response, chapter.url, book.bookUrl || source.bookSourceUrl);
      if (source.bookSourceType === 1 || (Number(book.type) & 32) !== 0) {
        const mediaUrl = this.extractAudioSourceRegexUrl(source.contentRule.sourceRegex || '',
          response.url || baseUrl, content, baseUrl);
        if (mediaUrl) return mediaUrl;
      }
    }
    return await this.runStageRule(source, book, rawRule, content, baseUrl,
      SourceRuntimeStage.CONTENT, chapter, {}, debugContext);
  }

  private resolvedAudioChapterUrl(source: BookSource, book: Book, chapter: BookChapter): string {
    const analyzer = new AnalyzeUrl(source, this.http);
    const config = analyzer.parse(chapter.url || '');
    const value = config.url || chapter.url || '';
    return BookUrlResolver.resolve(value, book.bookUrl || source.bookSourceUrl);
  }

  private isPureAudioBaseUrlRule(rawRule: string): boolean {
    const normalized = (rawRule || '').trim()
      .replace(/^<js>\s*|\s*<\/js>$/gi, '')
      .replace(/^@?js:\s*/i, '')
      .replace(/;\s*$/, '')
      .trim();
    return normalized === 'baseUrl' || normalized === 'String(baseUrl)';
  }

  private async tryResolveAudioWebViewUrl(source: BookSource, chapter: BookChapter,
    resolvedChapterUrl: string): Promise<string> {
    const sourceRegex = source.contentRule.sourceRegex || '';
    if (!sourceRegex || !this.audioChapterRuleUsesWebView(source)) return '';
    const runtime = BookSourceAudioWebRuntime.get();
    if (!await runtime.waitUntilAvailable()) return '';
    try {
      return await runtime.resolveAudioUrl(resolvedChapterUrl, sourceRegex,
        this.audioSourceUserAgent(source), 15000);
    } catch (error) {
      console.warn('[WS] audio WebView source interception failed, fallback HTTP:',
        source.bookSourceName, chapter.title, error);
      return '';
    }
  }

  private audioChapterRuleUsesWebView(source: BookSource): boolean {
    const raw = source.tocRule.chapterUrl || '';
    return /["'“”]?webView["'“”]?\s*:\s*["'“”]?true["'“”]?/i.test(raw);
  }

  private audioSourceUserAgent(source: BookSource): string {
    const raw = source.header || '';
    try {
      const parsed = JSON.parse(raw.replace(/[“”]/g, '"').replace(/'/g, '"')) as Record<string, Object>;
      for (const key of Object.keys(parsed)) {
        if (key.toLowerCase() === 'user-agent') return String(parsed[key] || '');
      }
    } catch (_) {
      const match = raw.match(/["']?User-Agent["']?\s*:\s*["']([^"']+)["']/i);
      if (match && match[1]) return match[1].trim();
    }
    return '';
  }

  private extractAudioSourceRegexUrl(rawRegex: string, responseUrl: string,
    body: string, baseUrl: string): string {
    const pattern = (rawRegex || '').trim();
    if (!pattern) return '';
    const matches = (candidate: string): boolean => {
      try {
        const literal = pattern.match(/^\/([\s\S]+)\/([dgimsuvy]*)$/);
        const regex = literal ? new RegExp(literal[1], literal[2]) : new RegExp(pattern, 'i');
        return regex.test(candidate);
      } catch (_) {
        return /\.(?:aac|flac|m3u8|m4a|mp3|mp4|ogg|opus|wav)(?:[?#]|$)/i.test(candidate);
      }
    };
    const candidates: string[] = [];
    const append = (value: string): void => {
      const decoded = String(value || '').replace(/&amp;/gi, '&').replace(/\\\//g, '/').trim();
      if (!decoded) return;
      const resolved = BookUrlResolver.resolve(decoded, baseUrl);
      if (resolved && !candidates.includes(resolved)) candidates.push(resolved);
    };
    append(responseUrl);
    const tagPattern = /<(?:audio|source|video)\b[^>]*(?:src|data-src|data-url)\s*=\s*["']([^"']+)["']/gi;
    let tagMatch: RegExpExecArray | null;
    while ((tagMatch = tagPattern.exec(body || '')) !== null && candidates.length < 512) {
      append(tagMatch[1] || '');
    }
    const urlPattern = /(?:https?:)?\/\/[^\s"'<>\\]+/gi;
    let urlMatch: RegExpExecArray | null;
    while ((urlMatch = urlPattern.exec(body || '')) !== null && candidates.length < 1024) {
      append(urlMatch[0] || '');
    }
    for (const candidate of candidates) {
      if (matches(candidate)) return candidate;
    }
    return '';
  }

  private stageDataUrlInput(rawRule: string, url: string, fallback: string): string {
    if (!this.ruleExpectsHexDataUrlInput(rawRule)) return fallback;
    const payload = EncodedSourceUrl.decode(url);
    return payload ? this.textToHex(payload.text) : fallback;
  }

  private ruleExpectsHexDataUrlInput(rawRule: string): boolean {
    const rule = rawRule || '';
    if (/\bjava\s*\.\s*hexDecodeToString\s*\(\s*(?:String\s*\(\s*)?result\b/.test(rule)) return true;
    // Packed source scripts commonly rename `result` before calling the decoder. The content
    // field still receives the same Legado byte-string contract, so presence of the decoder in
    // an executable JS content rule is the reliable capability signal.
    return /\bhexDecodeToString\b/.test(rule) &&
      /(?:<js>|@js:|\beval\s*\()/i.test(rule);
  }

  private extractVirtualChapterPayload(url: string): string {
    const value = (url || '').trim();
    if (!value) return '';
    // A data URL is already a complete virtual chapter descriptor. Its Base64 payload may contain
    // `/`, and the suffix after that slash can coincidentally look like `name=value`. Running the
    // generic relative-query matcher over it truncates the descriptor and makes the content rule
    // parse a Base64 tail instead of the decoded chapter JSON. Keep compatibility only for the old
    // cached form that appended a real query string after the trailing options object.
    if (EncodedSourceUrl.isEncodedDataUrl(value)) {
      const legacyAppended = /}\s*((?:[A-Za-z_$][\w$.-]*=[^&\s]*)(?:&[A-Za-z_$][\w$.-]*=[^&\s]*)*)$/.exec(value);
      return legacyAppended && legacyAppended[1] ? legacyAppended[1] : '';
    }
    // Recover legacy cached values produced by concatenating a virtual data: base directly with
    // the chapter payload (there may be no slash between the metadata object and the first key).
    const appended = /(?:^|[}\/])((?:[A-Za-z_$][\w$.-]*=[^&\s]*)(?:&[A-Za-z_$][\w$.-]*=[^&\s]*)*)$/.exec(value);
    if (appended && appended[1]) return appended[1];
    let candidate = value;
    const slash = value.lastIndexOf('/');
    const tail = slash >= 0 ? value.substring(slash + 1) : '';
    if (/^(?:[A-Za-z_$][\w$.-]*=[^\s]*)(?:&[A-Za-z_$][\w$.-]*=[^\s]*)*$/.test(tail)) return tail;
    if (/^https?:/i.test(value)) candidate = tail;
    if (/^(?:[A-Za-z_$][\w$.-]*=[^\s]*)(?:&[A-Za-z_$][\w$.-]*=[^\s]*)*$/.test(candidate)) {
      return candidate;
    }
    if (!/^(?:https?:|data:|\/|\.\/|\.\.\/)/i.test(candidate) &&
      ((candidate.startsWith('{') && candidate.endsWith('}')) ||
        (candidate.startsWith('[') && candidate.endsWith(']')))) return candidate;
    return '';
  }

  private textToHex(value: string): string {
    const bytes = new util.TextEncoder().encodeInto(value || '');
    let result = '';
    for (const byte of bytes) result += Number(byte).toString(16).padStart(2, '0');
    return result;
  }

  private resolveVars(url: string, ctx: RuleContext): string {
    // 替换 @get:{key} 模式
    return url.replace(/@get:\{(\w+)\}/g, (_: string, key: string) => {
      return ctx.get(key);
    });
  }

  private ruleBoolean(value: string): boolean {
    const normalized = String(value || '').trim().toLowerCase();
    return normalized === 'true' || normalized === '1' || normalized === 'yes' ||
      normalized === 'vip' || normalized === 'pay' || normalized === 'paid' ||
      normalized === '付费' || normalized === '收费';
  }

  private getChapterBaseUrl(chapter: BookChapter, book: Book, source: BookSource): string {
    return BookUrlResolver.getVariableJson(chapter.variable, 'baseUrl') || chapter.url || book.tocUrl || book.bookUrl || source.bookSourceUrl;
  }

  private seedBookVariables(ctx: RuleContext, bookUrl: string): void {
    if (!bookUrl) return;
    ctx.put('book.bookUrl', bookUrl);
    ctx.put('bookUrl', bookUrl);
    const id = this.extractQueryParam(bookUrl, 'book_id') || this.extractQueryParam(bookUrl, 'bookid') ||
      this.extractQueryParam(bookUrl, 'id') || this.extractBookId(bookUrl);
    if (id) {
      if (!ctx.get('book')) ctx.put('book', id);
      if (!ctx.get('book_id')) ctx.put('book_id', id);
      if (!ctx.get('id')) ctx.put('id', id);
    }
  }

  private seedChapterVariables(ctx: RuleContext, chapter: BookChapter): void {
    ctx.put('chapter.title', chapter.title || '');
    ctx.put('chapter.url', chapter.url || '');
    ctx.put('chapter.index', String(chapter.index));
    ctx.put('chapterTitle', chapter.title || '');
    const encodedVariables = EncodedSourceUrl.scalarVariables(chapter.url);
    for (const key in encodedVariables) ctx.put(key, encodedVariables[key]);
  }

  private urlWithoutFragment(url: string): string {
    const index = (url || '').indexOf('#');
    return index >= 0 ? url.substring(0, index) : (url || '');
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
    if (!ctx.has('source.variable')) ctx.put('source.variable', source.variable || '');
  }

  private extractQueryParam(url: string, key: string): string {
    const re = new RegExp(`[?&]${key}=([^&]+)`, 'i');
    const m = url.match(re);
    return m ? decodeURIComponent(m[1]) : '';
  }

  private resolveJsonKey(itemData: Record<string, Object> | null, tocData: Record<string, Object> | null, key: string, deep: boolean): string {
    // 优先从 item 数据查找
    if (itemData) {
      const v = deep ? this.deepSearch(itemData, key) : String(itemData[key] ?? '');
      if (v) return v;
    }
    // 回退到 TOC 完整数据
    if (tocData) {
      const v = deep ? this.deepSearch(tocData, key) : String(tocData[key] ?? '');
      if (v) return v;
    }
    return '';
  }

  private deepSearch(obj: Object, key: string): string {
    if (!obj || typeof obj !== 'object') return '';
    if (Array.isArray(obj)) {
      for (const item of obj) {
        const r = this.deepSearch(item as Object, key);
        if (r) return r;
      }
    } else {
      const rec = obj as Record<string, Object>;
      if (rec[key] !== undefined) return String(rec[key]);
      for (const k in rec) {
        const r = this.deepSearch(rec[k] as Object, key);
        if (r) return r;
      }
    }
    return '';
  }
}
