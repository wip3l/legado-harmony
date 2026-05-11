import { Book, BookChapter, BookSource } from '../../model/data/Book';
import { HttpClient } from '../http/HttpClient';
import { AnalyzeUrl } from '../rule/AnalyzeUrl';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { RuleContext } from '../rule/RuleContext';

export class WebBookService {
  private http: HttpClient;

  constructor() {
    this.http = new HttpClient(10000);
  }

  async getBookInfo(source: BookSource, book: Book): Promise<Book> {
    console.log('[WS] getBookInfo, URL:', book.bookUrl);
    const au = new AnalyzeUrl(source, this.http);
    const resp = await au.fetch(book.bookUrl);
    console.log('[WS] getBookInfo resp:', resp.success, 'len:', resp.body.length);
    if (!resp.success || !resp.body) return book;

    const ctx = new RuleContext();
    ctx.loadFromJson(book.variable);

    // init 规则
    let content = resp.body;
    const infoRule = source.bookInfoRule;
    if (infoRule.init) {
      const ir = new AnalyzeRule(content, book.bookUrl, ctx);
      const initResult = ir.getString(infoRule.init);
      if (initResult) content = initResult;
    }

    const ir = new AnalyzeRule(content, book.bookUrl, ctx);
    book.name = ir.getString(infoRule.name) || book.name;
    book.author = ir.getString(infoRule.author) || book.author;
    book.coverUrl = ir.getString(infoRule.coverUrl) || book.coverUrl;
    book.intro = ir.getString(infoRule.intro) || book.intro;
    book.kind = ir.getString(infoRule.kind) || book.kind;
    book.latestChapterTitle = ir.getString(infoRule.lastChapter) || book.latestChapterTitle;
    book.wordCount = ir.getString(infoRule.wordCount) || book.wordCount;

    const tocUrl = ir.getString(infoRule.tocUrl, true);
    if (tocUrl) book.tocUrl = this.repairUrlWithBookId(tocUrl, book.bookUrl);

    // 保存变量
    book.variable = ctx.toJson();

    // 如果 tocUrl 为空，尝试从 bookUrl 构造
    if (!book.tocUrl) {
      book.tocUrl = this.fallbackTocUrl(book.bookUrl, infoRule.tocUrl, source.bookSourceUrl);
    }

    return book;
  }

  private fallbackTocUrl(bookUrl: string, tocRule: string, baseUrl: string): string {
    // 从 bookUrl 提取 novelId
    const segs = bookUrl.replace(/\?.*$/, '').split('/').filter(s => s.length > 0);
    let novelId = '';
    for (let i = segs.length - 1; i >= 0; i--) {
      if (segs[i].match(/^[a-zA-Z0-9_-]{3,30}$/)) { novelId = segs[i]; break; }
    }
    if (!novelId || !tocRule) return bookUrl;
    const url = tocRule.replace(/\{\{\$\.\w+\}\}/g, novelId).replace(/\{\{\w+\}\}/g, novelId);
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) {
      const m = baseUrl.match(/^(https?:\/\/[^/]+)/);
      return m ? m[0] + url : baseUrl + url;
    }
    return baseUrl + '/' + url;
  }

  private repairUrlWithBookId(url: string, bookUrl: string): string {
    if (!url || !bookUrl) return url;
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
    console.log('[WS] getChapterList, tocUrl:', book.tocUrl);
    const tocUrl = book.tocUrl || book.bookUrl;
    const au = new AnalyzeUrl(source, this.http);
    const resp = await au.fetch(tocUrl);
    if (!resp.success || !resp.body) return [];

    const ctx = new RuleContext();
    ctx.loadFromJson(book.variable);

    const rule = new AnalyzeRule(resp.body, book.origin || source.bookSourceUrl, ctx);
    const tocRule = source.tocRule;
    const items = rule.getElements(tocRule.chapterList || '');
    console.log('[WS] getChapterList items:', items.length, 'from resp:', resp.body.length);

    const chapters: BookChapter[] = [];
    for (let i = 0; i < items.length; i++) {
      const ir = new AnalyzeRule(items[i], book.origin || source.bookSourceUrl, ctx);
      const chap = new BookChapter();
      chap.title = ir.getString(tocRule.chapterName) || `第${i + 1}章`;
      let rawUrl = ir.getString(tocRule.chapterUrl);

      // 如果 URL 含 @js: 或未解析的 JSONPath，从 item/TOC 数据解析
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

      const resolvedChapterUrl = this.resolveVars(this.resolveUrl(rawUrl, book.origin || source.bookSourceUrl), ctx);
      chap.url = this.repairUrlWithBookId(resolvedChapterUrl, book.bookUrl);
      chap.bookUrl = book.bookUrl;
      chap.index = i;
      chap.isVip = ir.getString(tocRule.isVip) === 'true';
      if (chap.title && chap.url) chapters.push(chap);
    }

    // 保存变量回 book
    book.variable = ctx.toJson();
    return chapters;
  }

  async getContent(source: BookSource, book: Book, chapter: BookChapter): Promise<string> {
    console.log('[WS] getContent, url:', chapter.url);
    const au = new AnalyzeUrl(source, this.http);
    const resp = await au.fetch(chapter.url);
    console.log('[WS] getContent resp:', resp.success, 'len:', resp.body.length);
    if (!resp.success || !resp.body) return '';

    const ctx = new RuleContext();
    ctx.loadFromJson(book.variable);

    const rule = new AnalyzeRule(resp.body, book.origin || source.bookSourceUrl, ctx);
    const contentRule = source.contentRule;

    let content = rule.getString(contentRule.content);
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

  private resolveUrl(url: string, base: string): string {
    if (!url || url.startsWith('http')) return url;
    if (url.startsWith('/')) {
      const m = base.match(/^(https?:\/\/[^/]+)/);
      return m ? m[0] + url : base + url;
    }
    const b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return b + '/' + url;
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
