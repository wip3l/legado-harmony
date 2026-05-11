import { Book, BookChapter, BookSource, SearchBook, BookListRule, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from '../data/Book';
import { appDb } from '../data/AppDatabase';
import { httpHelper } from '../http/HttpHelper';
import { AnalyzeRule, AnalyzeUrl } from '../analyzeRule/AnalyzeRule';

export class WebBook {
  private static instance: WebBook | null = null;

  private constructor() {}

  static getInstance(): WebBook {
    if (!WebBook.instance) {
      WebBook.instance = new WebBook();
    }
    return WebBook.instance;
  }

  async searchBook(
    source: BookSource,
    keyword: string,
    page: number = 1
  ): Promise<SearchBook[]> {
    try {
      const searchUrl = this.buildSearchUrl(source, keyword, page);
      const analyzeUrl = new AnalyzeUrl(searchUrl);
      const html = await analyzeUrl.fetch();

      if (!html) return [];

      const analyzeRule = new AnalyzeRule(source.bookSourceUrl, html, searchUrl);
      const searchRule = source.getSearchRule();

      return this.parseBookList(analyzeRule, searchRule, source);
    } catch (e) {
      console.error('搜索书籍失败:', e);
      return [];
    }
  }

  async exploreBook(
    source: BookSource,
    url: string,
    page: number = 1
  ): Promise<SearchBook[]> {
    try {
      const analyzeUrl = new AnalyzeUrl(url);
      const html = await analyzeUrl.fetch();

      if (!html) return [];

      const analyzeRule = new AnalyzeRule(source.bookSourceUrl, html, url);
      const exploreRule = source.getExploreRule();

      return this.parseBookList(analyzeRule, exploreRule, source);
    } catch (e) {
      console.error('发现书籍失败:', e);
      return [];
    }
  }

  async getBookInfo(source: BookSource, book: Book): Promise<Book> {
    try {
      console.log('[WebBook] getBookInfo, URL:', book.bookUrl);
      const analyzeUrl = new AnalyzeUrl(book.bookUrl, book, source);
      const html = await analyzeUrl.fetch();
      console.log('[WebBook] getBookInfo 响应长度:', html.length);

      if (!html) {
        console.warn('[WebBook] getBookInfo 响应为空,尝试从搜索数据构造');
        return this.fallbackBookInfo(source, book);
      }

      // 检查是否API返回错误
      if (html.includes('"code"') && (html.includes('4004') || html.includes('4003') || html.includes('"msg"'))) {
        console.warn('[WebBook] API返回错误,尝试从搜索数据构造:', html.substring(0, 100));
        return this.fallbackBookInfo(source, book);
      }

      const bookInfoRule = source.getBookInfoRule();
      let content = html;
      if (bookInfoRule.init) {
        console.log('[WebBook] 执行 init 规则:', bookInfoRule.init.substring(0, 80));
        const initRule = new AnalyzeRule(source.bookSourceUrl, html, book.bookUrl, source, book);
        const initValue = initRule.analyzeFirst(bookInfoRule.init);
        if (initValue) {
          content = initValue;
          console.log('[WebBook] init 完成, 内容长度:', content.length);
        }
      }

      const analyzeRule = new AnalyzeRule(source.bookSourceUrl, content, book.bookUrl, source, book);
      const result = this.parseBookInfo(analyzeRule, bookInfoRule, book);
      console.log('[WebBook] getBookInfo 完成, name:', result.name, 'tocUrl:', result.tocUrl);
      return result;
    } catch (e) {
      console.error('[WebBook] 获取书籍信息失败:', e);
      return book;
    }
  }

  async getChapterList(source: BookSource, book: Book): Promise<BookChapter[]> {
    try {
      const tocUrl = book.tocUrl || book.bookUrl;
      console.log('[WebBook] getChapterList, tocUrl:', tocUrl);
      const analyzeUrl = new AnalyzeUrl(tocUrl, book, source);
      const html = await analyzeUrl.fetch();
      console.log('[WebBook] getChapterList 响应长度:', html.length);

      if (!html) return [];

      const analyzeRule = new AnalyzeRule(source.bookSourceUrl, html, tocUrl, source, book);
      const tocRule = source.getTocRule();
      console.log('[WebBook] getChapterList, tocRule.chapterList:', tocRule.chapterList, 'chapterName:', tocRule.chapterName, 'chapterUrl:', tocRule.chapterUrl);

      const chapters = this.parseChapterList(analyzeRule, tocRule, book, source);
      console.log('[WebBook] getChapterList 解析完成, 章节数:', chapters.length);
      return chapters;
    } catch (e) {
      console.error('获取章节列表失败:', e);
      return [];
    }
  }

  async getContent(
    source: BookSource,
    book: Book,
    chapter: BookChapter
  ): Promise<string> {
    try {
      const analyzeUrl = new AnalyzeUrl(chapter.url, book, source);
      const html = await analyzeUrl.fetch();

      if (!html) return '';

      const analyzeRule = new AnalyzeRule(source.bookSourceUrl, html, chapter.url, source, book);
      const contentRule = source.getContentRule();

      return this.parseContent(analyzeRule, contentRule);
    } catch (e) {
      console.error('获取章节内容失败:', e);
      return '';
    }
  }

  private buildSearchUrl(source: BookSource, keyword: string, page: number): string {
    const baseUrl = this.cleanBaseUrl(source.bookSourceUrl);
    let url = source.searchUrl || `${baseUrl}/search?q={{key}}&page={{page}}`;
    const encodedKeyword = encodeURIComponent(keyword);

    url = url
      .replace(/\{\{key\}\}/g, encodedKeyword)
      .replace(/\{\{searchKey\}\}/g, encodedKeyword)
      .replace(/\{key\}/g, encodedKeyword)
      .replace(/\{searchKey\}/g, encodedKeyword)
      .replace(/\{\{page\}\}/g, String(page))
      .replace(/\{page\}/g, String(page));

    const optionIndex = url.indexOf(",{");
    if (optionIndex >= 0) {
      url = url.substring(0, optionIndex);
    }

    return this.resolveUrl(url, baseUrl);
  }

  private parseBookList(
    analyzeRule: AnalyzeRule,
    rule: BookListRule | SearchRule | ExploreRule,
    source: BookSource
  ): SearchBook[] {
    const books: SearchBook[] = [];

    try {
      const bookList = analyzeRule.analyze(rule.bookList);

      for (const item of bookList) {
        const itemRule = new AnalyzeRule(source.bookSourceUrl, item, source.bookSourceUrl);

        const book = new SearchBook();
        book.name = itemRule.analyzeFirst(rule.name);
        book.author = itemRule.analyzeFirst(rule.author);
        book.coverUrl = itemRule.analyzeFirst(rule.coverUrl);
        book.intro = itemRule.analyzeFirst(rule.intro);
        book.kind = itemRule.analyzeFirst(rule.kind);
        book.latestChapterTitle = itemRule.analyzeFirst(rule.lastChapter);
        book.bookUrl = this.resolveUrl(itemRule.analyzeFirst(rule.bookUrl), source.bookSourceUrl);
        book.wordCount = itemRule.analyzeFirst(rule.wordCount);
        book.origin = source.bookSourceUrl;
        book.originName = source.bookSourceName;

        if (book.name && book.bookUrl) {
          books.push(book);
        }
      }
    } catch (e) {
      console.error('解析书籍列表失败:', e);
    }

    return books;
  }

  private parseBookInfo(
    analyzeRule: AnalyzeRule,
    rule: BookInfoRule,
    book: Book
  ): Book {
    try {
      console.log('[WebBook] parseBookInfo, rule.tocUrl:', rule.tocUrl, 'rule.name:', rule.name);
      book.name = analyzeRule.analyzeFirst(rule.name) || book.name;
      book.author = analyzeRule.analyzeFirst(rule.author) || book.author;
      book.coverUrl = analyzeRule.analyzeFirst(rule.coverUrl) || book.coverUrl;
      book.intro = analyzeRule.analyzeFirst(rule.intro) || book.intro;
      book.kind = analyzeRule.analyzeFirst(rule.kind) || book.kind;
      book.latestChapterTitle = analyzeRule.analyzeFirst(rule.lastChapter) || book.latestChapterTitle;
      book.wordCount = analyzeRule.analyzeFirst(rule.wordCount) || book.wordCount;

      let tocUrl = analyzeRule.analyzeFirst(rule.tocUrl);
      if (tocUrl && tocUrl.includes('//')) {
        // 双斜杠说明有变量为空，从 bookUrl 路径中提取 ID 作为后备
        const pathMatch = book.bookUrl.match(/\/([a-zA-Z0-9_-]{3,30})(?:\/|$|\?)/);
        if (pathMatch) {
          const novelId = pathMatch[1];
          tocUrl = tocUrl.replace(/\/\//g, `/${novelId}/`);
          console.log('[WebBook] 从 bookUrl 提取 novelId:', novelId, '修复后 tocUrl:', tocUrl);
        }
      }
      if (tocUrl) {
        book.tocUrl = this.resolveUrl(tocUrl, book.origin);
        console.log('[WebBook] parseBookInfo, 最终tocUrl:', book.tocUrl);
      }
    } catch (e) {
      console.error('解析书籍信息失败:', e);
    }

    return book;
  }

  private parseChapterList(
    analyzeRule: AnalyzeRule,
    rule: TocRule,
    book: Book,
    source: BookSource
  ): BookChapter[] {
    const chapters: BookChapter[] = [];

    try {
      const chapterList = analyzeRule.analyze(rule.chapterList);

      for (let i = 0; i < chapterList.length; i++) {
        const item = chapterList[i];
        const itemRule = new AnalyzeRule(book.origin, item, book.tocUrl || book.bookUrl, source, book);

        const chapter = new BookChapter();
        chapter.title = itemRule.analyzeFirst(rule.chapterName);
        chapter.url = this.resolveUrl(itemRule.analyzeFirst(rule.chapterUrl), book.origin);
        chapter.bookUrl = book.bookUrl;
        chapter.index = i;
        chapter.isVip = itemRule.analyzeFirst(rule.isVip) === 'true';
        chapter.isPay = itemRule.analyzeFirst(rule.isPay) === 'true';

        if (chapter.title && chapter.url) {
          chapters.push(chapter);
        }
      }
    } catch (e) {
      console.error('解析章节列表失败:', e);
    }

    return chapters;
  }

  private parseContent(analyzeRule: AnalyzeRule, rule: ContentRule): string {
    try {
      let content = analyzeRule.analyzeFirst(rule.content);

      if (rule.images) {
        const images = analyzeRule.analyze(rule.images);
        for (const img of images) {
          content += `\n<img src="${img}"/>`;
        }
      }

      if (rule.replaceRegex) {
        content = this.applyReplaceRegex(content, rule.replaceRegex);
      }

      return content;
    } catch (e) {
      console.error('解析内容失败:', e);
      return '';
    }
  }

  private resolveUrl(url: string, baseUrl: string): string {
    baseUrl = this.cleanBaseUrl(baseUrl);
    if (!url || url.startsWith('http') || url.startsWith('data:')) {
      return url;
    }
    if (url.startsWith('//')) {
      return `https:${url}`;
    }
    if (url.startsWith('/')) {
      const match = baseUrl.match(/^(https?:\/\/[^/]+)/);
      return match ? `${match[1]}${url}` : `${baseUrl}${url}`;
    }
    const cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return `${cleanBase}/${url}`;
  }

  private cleanBaseUrl(baseUrl: string): string {
    const commentIndex = baseUrl.indexOf('##');
    return commentIndex >= 0 ? baseUrl.substring(0, commentIndex) : baseUrl;
  }

  private applyReplaceRegex(content: string, replaceRegex: string): string {
    if (!content || !replaceRegex) return content;

    let rule = replaceRegex;
    if (rule.startsWith('##')) {
      rule = rule.substring(2);
    }

    try {
      return content.replace(new RegExp(rule, 'g'), '');
    } catch (e) {
      return content;
    }
  }

  private fallbackBookInfo(source: BookSource, book: Book): Book {
    console.log('[WebBook] fallbackBookInfo, bookUrl:', book.bookUrl);
    // 从 bookUrl 路径中提取最后一个有效小说ID段
    const pathSegments = book.bookUrl.replace(/\?.*$/, '').split('/').filter(s => s.length > 0);
    let novelId = '';
    // 从后往前找第一个长度3-30的字母数字段
    for (let i = pathSegments.length - 1; i >= 0; i--) {
      const seg = pathSegments[i];
      if (seg.match(/^[a-zA-Z0-9_-]{3,30}$/)) {
        novelId = seg;
        break;
      }
    }
    console.log('[WebBook] 提取 novelId:', novelId, 'from segments:', pathSegments.join(','));
    if (!novelId) {
      return book;
    }

    const tocUrlRule = source.bookInfoRule.tocUrl;
    if (tocUrlRule) {
      const tocUrl = tocUrlRule
        .replace(/\{\{\$\.novelId\}\}/g, novelId)
        .replace(/\{\{novelId\}\}/g, novelId);
      book.tocUrl = this.resolveUrl(tocUrl, book.origin || source.bookSourceUrl);
      console.log('[WebBook] 构造 tocUrl:', book.tocUrl);
    } else {
      book.tocUrl = `${book.bookUrl.replace(/\?.*$/, '')}/chapters`;
    }

    return book;
  }

  async preciseSearch(
    keyword: string,
    author: string = '',
    sources?: BookSource[]
  ): Promise<SearchBook[]> {
    const allSources = sources || await appDb.getEnabledBookSources();
    const results: SearchBook[] = [];

    for (const source of allSources) {
      try {
        const books = await this.searchBook(source, keyword);
        for (const book of books) {
          if (author && book.author && !book.author.includes(author)) {
            continue;
          }
          results.push(book);
        }
      } catch (e) {
        // 忽略单个源的错误
      }
    }

    return results;
  }
}

export const webBook = WebBook.getInstance();
