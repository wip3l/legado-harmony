import { Book, BookChapter, BookSource } from '../../model/data/Book';
import { HttpClient } from '../http/HttpClient';
import { AnalyzeUrl } from '../rule/AnalyzeUrl';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { RuleContext } from '../rule/RuleContext';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { VerificationSupport } from '../http/VerificationSupport';
import { EncodedSourceUrl } from './EncodedSourceUrl';
import { BookSourceDataUrlSupport } from './BookSourceDataUrlSupport';
import { BookUrlResolver } from './BookUrlResolver';
import { BookFieldSanitizer } from '../../utils/BookFieldSanitizer';
import { AjaxRuleCompat } from '../rule/AjaxRuleCompat';

export class WebBookService {
  private http: HttpClient;

  constructor() {
    this.http = new HttpClient(10000);
  }

  async getBookInfo(source: BookSource, book: Book): Promise<Book> {
    if (BookSourceDataUrlSupport.isEncodedSource(book.bookUrl)) {
      return await BookSourceDataUrlSupport.getBookInfo(this.http, source, book);
    }
    console.log('[WS] getBookInfo, URL:', book.bookUrl);
    const au = new AnalyzeUrl(source, this.http);
    const resp = EncodedSourceUrl.canHandle(book.bookUrl) ?
      await this.fetchEncodedDataUrl(book.bookUrl, source) : await au.fetch(book.bookUrl);
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
      const ir = new AnalyzeRule(content, baseUrl, ctx);
      this.seedSourceVariables(ctx, source);
      const initResult = ir.getString(infoRule.init);
      if (initResult) content = initResult;
    }

    const ir = new AnalyzeRule(content, baseUrl, ctx);
    this.seedSourceVariables(ctx, source);
    book.name = ir.getString(infoRule.name) || book.name;
    book.author = ir.getString(infoRule.author) || book.author;
    const infoCoverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source, ir.getString(infoRule.coverUrl), baseUrl);
    book.coverUrl = book.coverUrl || infoCoverUrl;
    book.intro = BookFieldSanitizer.prefer(ir.getString(infoRule.intro), book.intro);
    book.kind = BookFieldSanitizer.prefer(ir.getString(infoRule.kind), book.kind);
    book.latestChapterTitle = BookFieldSanitizer.prefer(ir.getString(infoRule.lastChapter), book.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.prefer(ir.getString(infoRule.wordCount), book.wordCount);

    const tocUrl = ir.getString(infoRule.tocUrl, true);
    if (tocUrl) book.tocUrl = this.repairUrlWithBookId(tocUrl, book.bookUrl);

    // 保存变量
    book.variable = ctx.toJson();

    // 如果 tocUrl 为空，尝试从 bookUrl 构造
    if (!book.tocUrl) {
      book.tocUrl = this.fallbackTocUrl(book.bookUrl, infoRule.tocUrl, baseUrl);
    }

    return book;
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
    const current = book.tocUrl || book.bookUrl;
    const fanqieUrl = this.buildFanqieDirectoryUrl(source, book);
    if (!fanqieUrl) return current;
    if (!current || this.isBookInfoUrl(current) || this.isBadFanqieDirectoryUrl(current)) {
      book.tocUrl = fanqieUrl;
      return fanqieUrl;
    }
    return current;
  }

  private buildFanqieDirectoryUrl(source: BookSource, book: Book): string {
    const chapterListRule = source.tocRule?.chapterList || '';
    const infoTocRule = source.bookInfoRule?.tocUrl || '';
    if (!chapterListRule.includes('chapterListWithVolume') && !infoTocRule.includes('fanqienovel.com/api/reader/directory/detail')) {
      return '';
    }
    const id = this.extractQueryParam(book.tocUrl || '', 'bookId') || this.extractQueryParam(book.tocUrl || '', 'book_id') ||
      this.extractQueryParam(book.bookUrl || '', 'book_id') || this.extractQueryParam(book.bookUrl || '', 'bookId') ||
      this.extractQueryParam(book.bookUrl || '', 'id') || this.extractBookId(book.bookUrl || '');
    if (!id) return '';
    return `https://fanqienovel.com/api/reader/directory/detail?bookId=${encodeURIComponent(id)}`;
  }

  private isBookInfoUrl(url: string): boolean {
    if (!url) return false;
    return /\/info(?:[?#]|$)/.test(url) && (!!this.extractQueryParam(url, 'book_id') || !!this.extractQueryParam(url, 'bookId'));
  }

  private isBadFanqieDirectoryUrl(url: string): boolean {
    if (!url.includes('fanqienovel.com/api/reader/directory/detail')) return false;
    const bookId = this.extractQueryParam(url, 'bookId') || this.extractQueryParam(url, 'book_id');
    return !bookId || bookId.includes('{{') || bookId.includes('$');
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

  async getChapterList(source: BookSource, book: Book): Promise<BookChapter[]> {
    if (BookSourceDataUrlSupport.isEncodedSource(book.tocUrl) || BookSourceDataUrlSupport.isEncodedSource(book.bookUrl)) {
      return await BookSourceDataUrlSupport.getChapterList(this.http, source, book);
    }
    console.log('[WS] getChapterList, tocUrl:', book.tocUrl);
    const tocUrl = this.resolveTocUrl(source, book);
    const au = new AnalyzeUrl(source, this.http);
    let resp = EncodedSourceUrl.canHandle(tocUrl) ?
      await this.fetchEncodedDataUrl(tocUrl, source) : await au.fetch(tocUrl);
    if ((resp.statusCode >= 400 || !resp.success || !resp.body) && this.shouldFallbackChaoxingToc(source, tocUrl, book.bookUrl)) {
      console.warn('[WS] Chaoxing toc api failed, fallback to detail page:', tocUrl);
      resp = await au.fetch(book.bookUrl);
    }
    if (this.requestVerificationIfNeeded(source, tocUrl, resp.body, resp.statusCode, source.tocRule.chapterList)) {
      return [];
    }
    if (!resp.success || !resp.body) return [];
    const baseUrl = BookUrlResolver.effectiveBase(resp, tocUrl, book.bookUrl || source.bookSourceUrl);

    const ctx = new RuleContext();
    ctx.loadFromJson(book.variable);
    this.seedBookVariables(ctx, book.bookUrl);
    this.seedSourceVariables(ctx, source);

    const rule = new AnalyzeRule(resp.body, baseUrl, ctx);
    const tocRule = source.tocRule;
    const specialChapters = await this.tryBuildSpecialChapterList(source, book, resp.body);
    if (specialChapters.length > 0) {
      book.variable = ctx.toJson();
      return specialChapters;
    }
    const items = rule.getElements(tocRule.chapterList || '');
    console.log('[WS] getChapterList items:', items.length, 'from resp:', resp.body.length);

    const chapters: BookChapter[] = [];
    for (let i = 0; i < items.length; i++) {
      const ir = new AnalyzeRule(items[i], baseUrl, ctx);
      this.seedSourceVariables(ctx, source);
      const chap = new BookChapter();
      chap.title = ir.getString(tocRule.chapterName) || `第${i + 1}章`;
      let rawUrl = ir.getString(tocRule.chapterUrl);

      // 如果规则引擎没有完整处理 URL，再从 item/TOC 数据兜底修复。
      if (rawUrl && (rawUrl.startsWith('@js:') || rawUrl.includes('$..') || rawUrl.includes('$.'))) {
        const repairedUrl = ir.getString(tocRule.chapterUrl, true);
        if (repairedUrl && !repairedUrl.includes('@js:') && !repairedUrl.includes('$..') && !repairedUrl.includes('$.')) {
          rawUrl = repairedUrl;
        }
      }

      // 如果 URL 仍含 @js: 或未解析的 JSONPath，从 item/TOC 数据解析
      if (rawUrl && (rawUrl.startsWith('@js:') || rawUrl.includes('$..') || rawUrl.includes('$.'))) {
        // 解析 item 为 JSON（通常 chapterList 提取的是 JSON 片段）
        let itemData: Record<string, Object> | null = null;
        try { itemData = JSON.parse(items[i]) as Record<string, Object>; } catch (_) {}
        // 同时尝试解析完整 TOC 响应
        let tocData: Record<string, Object> | null = null;
        try { tocData = JSON.parse(resp.body) as Record<string, Object>; } catch (_) {}

        // 去除 @js: 前缀
        rawUrl = rawUrl.replace(/^@js:\s*/, '');
        // 去除尾部配置对象 ,{'webView':true} 等
        rawUrl = rawUrl.replace(/\s*,\s*\{[^}]*\}\s*$/, '');

        // 解析 $..key（深层搜索）
        rawUrl = rawUrl.replace(/\$\.\.(\w+)/g, (_: string, key: string) => {
          return this.resolveJsonKey(itemData, tocData, key, true) || '';
        });
        // 解析 $.key（根层搜索）
        rawUrl = rawUrl.replace(/\$\.(\w+)/g, (_: string, key: string) => {
          return this.resolveJsonKey(itemData, tocData, key, false) || '';
        });

        // 移除字符串拼接符 + 和多余引号
        rawUrl = rawUrl
          .replace(/\s*\+\s*/g, '')
          .replace(/^['"]|['"]$/g, '')
          .trim();
        console.warn('[WS] chapterUrl 修复后:', rawUrl.substring(0, 100));
      }

      const resolvedChapterUrl = this.resolveVars(BookUrlResolver.resolve(rawUrl, baseUrl), ctx);
      chap.url = this.normalizeChaoxingUrl(source, this.repairUrlWithBookId(resolvedChapterUrl, book.bookUrl));
      chap.bookUrl = book.bookUrl;
      chap.index = i;
      chap.isVip = ir.getString(tocRule.isVip) === 'true';
      chap.variable = BookUrlResolver.setVariableJson(chap.variable, 'baseUrl', baseUrl);
      if (chap.title && chap.url) chapters.push(chap);
    }

    // 保存变量回 book
    book.variable = ctx.toJson();
    if (chapters.length > 0) return chapters;

    const chaoxingDetailChapter = this.tryBuildChaoxingDetailChapter(source, book, resp.body, baseUrl);
    if (chaoxingDetailChapter.length > 0) return chaoxingDetailChapter;

    const fallbackChapters = this.tryBuildGenericChapterList(book, resp.body, baseUrl);
    if (fallbackChapters.length > 0) return fallbackChapters;
    return chapters;
  }

  async getContent(source: BookSource, book: Book, chapter: BookChapter): Promise<string> {
    if (BookSourceDataUrlSupport.isEncodedSource(chapter.url)) {
      return await BookSourceDataUrlSupport.getContent(this.http, source, book, chapter);
    }
    const normalizedContentUrl = this.normalizeChaoxingUrl(source, chapter.url);
    if (normalizedContentUrl !== chapter.url) {
      chapter.url = normalizedContentUrl;
    }
    console.log('[WS] getContent, url:', chapter.url);
    const specialContent = await this.tryGetSpecialContent(source, chapter);
    if (specialContent) {
      return this.applyReplaceRegex(specialContent, source.contentRule.replaceRegex)
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/p>/gi, '\n\n')
        .replace(/<[^>]+>/g, '')
        .replace(/&nbsp;/g, ' ')
        .replace(/&amp;/g, '&')
        .replace(/\n{3,}/g, '\n\n')
        .trim();
    }
    const au = new AnalyzeUrl(source, this.http);
    let resp = EncodedSourceUrl.canHandle(chapter.url) ?
      await this.fetchEncodedDataUrl(chapter.url, source) : await au.fetch(chapter.url);
    if ((!resp.success || !resp.body) && this.shouldRetryChaoxingHttps(source, chapter.url)) {
      const httpsUrl = this.normalizeChaoxingUrl(source, chapter.url);
      console.warn('[WS] Chaoxing content http failed, retry https:', httpsUrl);
      resp = await au.fetch(httpsUrl);
      chapter.url = httpsUrl;
    }
    console.log('[WS] getContent resp:', resp.success, 'len:', resp.body.length);
    if (this.requestVerificationIfNeeded(source, chapter.url, resp.body, resp.statusCode, source.contentRule.content)) {
      return '';
    }
    if (!resp.success || !resp.body) return '';
    const baseUrl = BookUrlResolver.effectiveBase(resp, this.getChapterBaseUrl(chapter, book, source), book.bookUrl || source.bookSourceUrl);

    const ctx = new RuleContext();
    ctx.loadFromJson(book.variable);
    this.seedBookVariables(ctx, book.bookUrl);
    this.seedSourceVariables(ctx, source);

    const rule = new AnalyzeRule(resp.body, baseUrl, ctx);
    const contentRule = source.contentRule;

    let content = await this.tryGetDirectAjaxRuleContent(source, resp.body, baseUrl, ctx, contentRule.content);
    if (!content) content = rule.getString(contentRule.content);
    if (!content || this.isBadExtractedContent(content)) {
      const fallbackContent = this.tryExtractReadableContentFromHtml(resp.body);
      if (fallbackContent) content = fallbackContent;
    }
    if ((!content || this.isBadExtractedContent(content)) && this.isChaoxingSource(source, chapter.url)) {
      const chaoxingContent = this.tryExtractChaoxingDetailContent(book, resp.body);
      if (chaoxingContent) content = chaoxingContent;
    }
    if (!content) return '';

    // 替换净化: contentRule.replaceRegex
    content = this.applyReplaceRegex(content, contentRule.replaceRegex);

    // 基本 HTML 净化
    content = content
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/\n{3,}/g, '\n\n')
      .trim();

    book.variable = ctx.toJson();
    return content;
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
    const root = await EncodedSourceUrl.requestJsonForDataUrl(this.http, url,
      BookSourceDataUrlSupport.sourceBackendHost(source));
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

  private shouldFallbackChaoxingToc(source: BookSource, tocUrl: string, bookUrl: string): boolean {
    if (!bookUrl || !this.isChaoxingSource(source, tocUrl || bookUrl)) return false;
    return (tocUrl || '').includes('/api/book/getChapters');
  }

  private isChaoxingSource(source: BookSource, requestUrl: string): boolean {
    const raw = `${requestUrl || ''}\n${source.bookSourceUrl || ''}\n${source.loginUrl || ''}\n` +
      `${source.searchUrl || ''}\n${source.exploreUrl || ''}`.toLowerCase();
    return raw.includes('chaoxing.com');
  }

  private normalizeChaoxingUrl(source: BookSource, url: string): string {
    if (!url || !this.isChaoxingSource(source, url)) return url;
    return url.replace(/^http:\/\/((?:qikan|www)\.chaoxing\.com)(?=\/)/i, 'https://$1');
  }

  private shouldRetryChaoxingHttps(source: BookSource, url: string): boolean {
    return /^http:\/\/(?:qikan|www)\.chaoxing\.com\//i.test(url || '') && this.isChaoxingSource(source, url);
  }

  private tryBuildChaoxingDetailChapter(source: BookSource, book: Book, body: string, baseUrl: string): BookChapter[] {
    if (!this.isChaoxingSource(source, book.bookUrl || baseUrl) || !body || !book.bookUrl.includes('/detail_')) return [];
    if (!this.looksLikeChaoxingDetailPage(body)) return [];
    const chapter = new BookChapter();
    chapter.title = book.latestChapterTitle || book.name || '详情';
    chapter.url = this.normalizeChaoxingUrl(source, book.bookUrl);
    chapter.bookUrl = book.bookUrl;
    chapter.index = 0;
    chapter.variable = BookUrlResolver.setVariableJson(chapter.variable, 'baseUrl', chapter.url);
    console.log('[WS] Chaoxing detail fallback chapter:', chapter.title, chapter.url);
    return chapter.title && chapter.url ? [chapter] : [];
  }

  private looksLikeChaoxingDetailPage(body: string): boolean {
    const sample = (body || '').substring(0, Math.min(body.length, 200000));
    return sample.includes('qikan.chaoxing.com') || sample.includes('chaoxing.com') ||
      sample.includes('超星') || sample.includes('读秀') || sample.includes('文献') ||
      /\/detail_[A-Za-z0-9]+/.test(sample);
  }

  private tryExtractChaoxingDetailContent(book: Book, body: string): string {
    if (!body) return '';
    const title = this.cleanInlineText(book.name || this.extractFirstMetaContent(body, ['citation_title', 'DC.title']) ||
      this.extractTitleText(body));
    const author = this.cleanInlineText(book.author || this.extractFirstMetaContent(body, ['citation_author', 'DC.creator']));
    const abstractText = this.cleanInlineText(this.extractChaoxingField(body, ['摘要', '简介', '内容提要']) ||
      this.extractFirstMetaContent(body, ['description', 'DC.description']));
    const keywords = this.cleanInlineText(this.extractChaoxingField(body, ['关键词', '关键字']) ||
      this.extractFirstMetaContent(body, ['keywords', 'citation_keywords']));
    const sourceName = this.cleanInlineText(this.extractChaoxingField(body, ['来源', '刊名', '期刊']) ||
      this.extractFirstMetaContent(body, ['citation_journal_title']));
    const year = this.cleanInlineText(this.extractChaoxingField(body, ['年份', '出版日期']) ||
      this.extractFirstMetaContent(body, ['citation_publication_date', 'DC.date']));

    const lines: string[] = [];
    if (title) lines.push(title);
    if (author) lines.push(`作者：${author}`);
    if (sourceName) lines.push(`来源：${sourceName}`);
    if (year) lines.push(`日期：${year}`);
    if (keywords) lines.push(`关键词：${keywords}`);
    if (abstractText) lines.push(`摘要：${abstractText}`);
    if (lines.length <= 1) return '';
    lines.push('该超星条目未解析到可直接阅读的全文，已显示详情页信息。');
    return lines.join('\n\n');
  }

  private extractFirstMetaContent(body: string, names: string[]): string {
    for (const name of names) {
      const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const re = new RegExp(`<meta\\b[^>]*(?:name|property)\\s*=\\s*["']${escaped}["'][^>]*content\\s*=\\s*["']([\\s\\S]*?)["'][^>]*>`, 'i');
      const match = body.match(re);
      if (match && match[1]) return this.decodeHtmlEntities(match[1]);
    }
    return '';
  }

  private extractTitleText(body: string): string {
    const match = (body || '').match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    return match && match[1] ? this.decodeHtmlEntities(match[1]).replace(/[-_].*$/, '') : '';
  }

  private extractChaoxingField(body: string, labels: string[]): string {
    for (const label of labels) {
      const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const re = new RegExp(`${escaped}\\s*[：:]\\s*</?[^>]*>??\\s*([\\s\\S]{0,800}?)(?:</p>|</li>|</div>|<br\\s*/?>|\\n)`, 'i');
      const match = (body || '').match(re);
      if (match && match[1]) return this.decodeHtmlEntities(match[1].replace(/<[^>]+>/g, ' '));
    }
    return '';
  }

  private isBadExtractedContent(content: string): boolean {
    if (!content) return false;
    const sample = content.substring(0, Math.min(content.length, 1200));
    return sample.includes('font-family:') || sample.includes('-webkit-text-size-adjust') ||
      sample.includes('.nuxt-progress') || sample.includes('box-sizing:border-box') ||
      sample.includes('<!doctype html') || sample.includes('<html');
  }

  private tryBuildGenericChapterList(book: Book, body: string, baseUrl: string): BookChapter[] {
    if (!body) return [];
    const bookKey = this.extractGenericBookKey(book.tocUrl || book.bookUrl || baseUrl);
    const catalogHtml = this.pickGenericCatalogBlock(body, baseUrl, bookKey);
    let links = this.collectGenericChapterLinks(catalogHtml, baseUrl, bookKey, catalogHtml !== body);
    if (links.length < 3 && catalogHtml !== body) {
      links = this.collectGenericChapterLinks(body, baseUrl, bookKey, false);
    }
    links = this.trimLeadingTeaserLinks(links);
    if (links.length < 3) return [];

    const chapters: BookChapter[] = [];
    for (const link of links) {
      const chapter = new BookChapter();
      chapter.title = link['title'] || `第${chapters.length + 1}章`;
      chapter.url = link['url'] || '';
      chapter.bookUrl = book.bookUrl;
      chapter.index = chapters.length;
      chapter.variable = BookUrlResolver.setVariableJson(chapter.variable, 'baseUrl', chapter.url || baseUrl);
      if (chapter.title && chapter.url) chapters.push(chapter);
    }
    console.log('[WS] 通用目录兜底:', chapters.length, 'from:', book.name || book.bookUrl);
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
    const seen: string[] = [];
    const re = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
    let match: RegExpExecArray | null;
    while ((match = re.exec(html || '')) !== null) {
      const attrs = match[1] || '';
      const hrefMatch = attrs.match(/\shref\s*=\s*["']([^"']+)["']/i);
      if (!hrefMatch || !hrefMatch[1]) continue;
      const url = BookUrlResolver.resolve(this.decodeHtmlEntities(hrefMatch[1]), baseUrl);
      const chapterKey = this.normalizeChapterLinkKey(url);
      if (!chapterKey || seen.includes(chapterKey)) continue;
      const titleMatch = attrs.match(/\stitle\s*=\s*["']([^"']+)["']/i);
      const title = this.cleanInlineText(titleMatch && titleMatch[1] ? titleMatch[1] : match[2]);
      if (!title || this.isNavigationTitle(title)) continue;
      const likelyChapter = this.isLikelyChapterTitle(title) || this.isLikelyChapterUrl(url, baseUrl, bookKey);
      if (!inCatalogBlock && !likelyChapter) continue;
      seen.push(chapterKey);
      links.push({
        title: title,
        url: url,
        key: chapterKey
      });
      if (links.length > 20000) break;
    }
    return links;
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
      compact === '阅读记录' || compact === '書頁/目錄' || compact === '书页/目录' ||
      compact === '上一章' || compact === '下一章' || compact === '上一頁' || compact === '下一頁' ||
      compact === '上一页' || compact === '下一页' || compact === '首頁' || compact === '首页' ||
      compact === '返回目录' || compact === '返回目錄' || compact === '書庫' || compact === '书库' ||
      compact === '作者' || compact === '目录' || compact === '目錄' || compact === '首页';
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
      .replace(/<\/div>/gi, '\n')
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

  private escapeRegex(value: string): string {
    return (value || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  private applyReplaceRegex(content: string, replaceRegex: string): string {
    if (!content || !replaceRegex) return content;
    try {
      if (replaceRegex.startsWith('##')) {
        return content.replace(new RegExp(replaceRegex.substring(2), 'g'), '');
      }
      const parts = replaceRegex.split('##');
      if (parts.length >= 2) {
        return content.replace(new RegExp(parts[0], 'g'), parts[1] || '');
      }
      return content.replace(new RegExp(replaceRegex, 'g'), '');
    } catch (_) {
      return content;
    }
  }

  private resolveVars(url: string, ctx: RuleContext): string {
    // 替换 @get:{key} 模式
    return url.replace(/@get:\{(\w+)\}/g, (_: string, key: string) => {
      return ctx.get(key);
    });
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

  private async tryBuildSpecialChapterList(source: BookSource, book: Book, body: string): Promise<BookChapter[]> {
    const fanqieVolumeChapters = this.tryBuildFanqieVolumeChapterList(source, book, body);
    if (fanqieVolumeChapters.length > 0) return fanqieVolumeChapters;

    if (!source.tocRule.chapterList.includes('allItemIds') && !source.tocRule.chapterList.includes('directory/detail')) {
      return [];
    }
    try {
      const root = JSON.parse(body) as Record<string, Object>;
      const data = root['data'] as Record<string, Object>;
      const ids = data?.['allItemIds'] as Object[];
      if (!Array.isArray(ids) || ids.length === 0) return [];

      const chapters: BookChapter[] = [];
      for (let i = 0; i < ids.length; i += 100) {
        const part = ids.slice(i, Math.min(i + 100, ids.length)).map(v => String(v)).join(',');
        const detailUrl = `https://novel.snssdk.com/api/novel/book/directory/detail/v1/?item_ids=${part}`;
        const detailHeaders: Record<string, string> = {};
        const detailCookie = VerificationSupport.sourceCookieHeader(source, detailUrl);
        if (detailCookie) detailHeaders['Cookie'] = detailCookie;
        const resp = await this.http.execute({
          url: detailUrl,
          method: 'GET',
          headers: detailHeaders
        });
        if (this.requestVerificationIfNeeded(source, resp.url || source.bookSourceUrl, resp.body, resp.statusCode, source.tocRule.chapterList)) {
          return [];
        }
        if (!resp.success || !resp.body) continue;
        const detail = JSON.parse(resp.body) as Record<string, Object>;
        const list = detail['data'] as Object[];
        if (!Array.isArray(list)) continue;
        for (const item of list) {
          const rec = item as Record<string, Object>;
          const itemId = String(rec['item_id'] || rec['id'] || '');
          if (!itemId) continue;
          const chapter = new BookChapter();
          chapter.title = String(rec['title'] || `第${chapters.length + 1}章`);
          chapter.url = `data:;base64,${this.base64Encode(itemId)},{"type":"pyfqc"}`;
          chapter.bookUrl = book.bookUrl;
          chapter.index = chapters.length;
          chapters.push(chapter);
        }
      }
      return chapters;
    } catch (e) {
      console.warn('[WS] 特殊目录拼装失败:', e);
      return [];
    }
  }

  private tryBuildFanqieVolumeChapterList(source: BookSource, book: Book, body: string): BookChapter[] {
    if (!source.tocRule.chapterList.includes('chapterListWithVolume')) return [];
    try {
      const root = JSON.parse(body) as Record<string, Object>;
      const data = root['data'] as Record<string, Object>;
      const volumeList = data?.['chapterListWithVolume'] as Object[];
      if (!Array.isArray(volumeList) || volumeList.length === 0) return [];

      const chapters: BookChapter[] = [];
      const base = BookUrlResolver.cleanBaseUrl(source.bookSourceUrl);
      for (const volume of volumeList) {
        if (!Array.isArray(volume)) continue;
        for (const item of volume) {
          const rec = item as Record<string, Object>;
          const itemId = String(rec['itemId'] || rec['item_id'] || rec['id'] || '');
          if (!itemId) continue;
          const chapter = new BookChapter();
          chapter.title = String(rec['title'] || `第${chapters.length + 1}章`);
          chapter.url = `${base}/content?item_id=${encodeURIComponent(itemId)}`;
          chapter.bookUrl = book.bookUrl;
          chapter.index = chapters.length;
          chapter.isVip = String(rec['isVip'] || rec['is_vip'] || '') === 'true';
          chapter.variable = BookUrlResolver.setVariableJson(chapter.variable, 'baseUrl', chapter.url);
          chapters.push(chapter);
        }
      }
      if (chapters.length > 0) {
        console.log('[WS] 番茄卷目录拼装:', chapters.length, 'from:', book.name || book.bookUrl);
      }
      return chapters;
    } catch (e) {
      console.warn('[WS] 番茄卷目录拼装失败:', e);
      return [];
    }
  }

  private async tryGetSpecialContent(source: BookSource, chapter: BookChapter): Promise<string> {
    const signedContent = await this.tryGetJsLibSignedContent(source, chapter);
    if (signedContent) return signedContent;
    if (!chapter.url.startsWith('data:;base64,') || !source.contentRule.content.includes('item_id')) {
      return '';
    }
    try {
      const idPart = chapter.url.substring('data:;base64,'.length).split(',')[0];
      const itemId = this.base64Decode(idPart);
      const contentUrl = `${source.bookSourceUrl.replace(/##[\s\S]*$/, '')}/content?item_id=${encodeURIComponent(itemId)}&key=`;
      const headers: Record<string, string> = {
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json'
      };
      const cookie = VerificationSupport.sourceCookieHeader(source, contentUrl);
      if (cookie) headers['Cookie'] = cookie;
      const resp = await this.http.execute({
        url: contentUrl,
        method: 'GET',
        headers: headers
      });
      if (this.requestVerificationIfNeeded(source, resp.url || chapter.url, resp.body, resp.statusCode, source.contentRule.content)) {
        return '';
      }
      if (!resp.success || !resp.body) return '';
      const json = JSON.parse(resp.body) as Record<string, Object>;
      const data = json['data'] as Record<string, Object>;
      return String(data?.['content'] || '');
    } catch (e) {
      console.warn('[WS] 特殊正文获取失败:', e);
      return '';
    }
  }

  private async tryGetJsLibSignedContent(source: BookSource, chapter: BookChapter): Promise<string> {
    const script = source.jsLib || '';
    if (!chapter.url.includes('chapter_ids=') || !chapter.url.includes('nid=') ||
      !script.includes('requestKey') || !script.includes('digestHex')) return '';
    try {
      const nid = this.extractQueryParam(chapter.url, 'nid');
      const chapterIds = this.extractQueryParam(chapter.url, 'chapter_ids');
      if (!nid || !chapterIds) return '';
      const version = this.extractJsLiteral(script, 'ver') || 'android_02050803';
      const salt = this.extractJsLiteral(script, 'f');
      if (!salt) return '';
      const timestamp = String(Math.floor(Date.now() / 1000));
      const digest = this.digestHex(`chapter_ids=${chapterIds}&nid=${nid}${timestamp}${version}${salt}`, 'SHA256');
      const range = script.match(/digestHex\([\s\S]*?\)\.substring\(\s*(\d+)\s*,\s*(\d+)\s*\)/);
      const start = range ? parseInt(range[1]) : 10;
      const end = range ? parseInt(range[2]) : 42;
      const requestKey = digest.substring(start, end);
      if (!requestKey) return '';

      const token = this.extractLoginToken(source.loginHeader || '');
      const headers: Record<string, string> = {
        'User-Agent': this.extractHeaderLiteral(script, 'User-Agent') ||
          'chang pei yue du/2.5.8.3 (Android 13; HarmonyOS; Mobile)',
        'randStr': timestamp,
        'version': version,
        'requestKey': requestKey,
        'client': this.extractHeaderLiteral(script, 'client') || 'android',
        'imei': this.extractHeaderLiteral(script, 'imei') || '455321005bc9cd38',
        'referer': this.extractHeaderLiteral(script, 'referer') || source.bookSourceUrl,
        'token': token
      };
      const response = await this.http.execute({ url: chapter.url, method: 'GET', headers: headers });
      if (!response.success || !response.body) return '';
      const root = JSON.parse(response.body) as Object;
      return this.deepStringValue(root, 'content');
    } catch (e) {
      console.warn('[WS] JS 签名正文请求失败:', e);
      return '';
    }
  }

  private extractJsLiteral(script: string, name: string): string {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const match = script.match(new RegExp(`\\b${escaped}\\s*=\\s*(["'])([\\s\\S]*?)\\1`));
    return match ? match[2] : '';
  }

  private extractHeaderLiteral(script: string, name: string): string {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const match = script.match(new RegExp(`["']?${escaped}["']?\\s*:\\s*(["'])([\\s\\S]*?)\\1`, 'i'));
    return match ? match[2] : '';
  }

  private extractLoginToken(loginHeader: string): string {
    const value = (loginHeader || '').trim().replace(/^&/, '');
    if (!value) return '';
    try {
      const data = JSON.parse(value) as Record<string, Object>;
      return String(data['token'] || '');
    } catch (_) {
      return '';
    }
  }

  private digestHex(input: string, algorithm: string): string {
    const digest = cryptoFramework.createMd(algorithm);
    digest.updateSync({ data: new util.TextEncoder().encodeInto(input) });
    const result = digest.digestSync().data;
    let hex = '';
    for (let i = 0; i < result.length; i++) hex += result[i].toString(16).padStart(2, '0');
    return hex;
  }

  private deepStringValue(value: Object, key: string): string {
    if (!value || typeof value !== 'object') return '';
    if (Array.isArray(value)) {
      for (const item of value) {
        const found = this.deepStringValue(item as Object, key);
        if (found) return found;
      }
      return '';
    }
    const record = value as Record<string, Object>;
    if (record[key] !== undefined && record[key] !== null) return String(record[key]);
    for (const name in record) {
      const found = this.deepStringValue(record[name], key);
      if (found) return found;
    }
    return '';
  }

  private base64Encode(input: string): string {
    try {
      const e = new util.TextEncoder();
      return new util.Base64Helper().encodeToStringSync(e.encodeInto(input));
    } catch (_) {
      return input;
    }
  }

  private base64Decode(input: string): string {
    try {
      const data = new util.Base64Helper().decodeSync(input);
      return util.TextDecoder.create('utf-8').decodeWithStream(data, { stream: false });
    } catch (_) {
      return input;
    }
  }
}
