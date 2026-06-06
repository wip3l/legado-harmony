import { Book, BookChapter, BookSource, SearchBook } from '../../model/data/Book';
import { HttpClient, HttpResponse } from '../http/HttpClient';
import { VerificationSupport } from '../http/VerificationSupport';
import { JsRuntime } from '../rule/JsRuntime';
import { EncodedJsonMap, EncodedSourcePayload, EncodedSourceUrl } from './EncodedSourceUrl';
import { BookUrlResolver } from './BookUrlResolver';

class DataUrlMeta {
  host: string = '';
  bookId: string = '';
  source: string = '';
  tab: string = '小说';
  tocUrl: string = '';
}

export class ExploreDataUrlEntry {
  title: string = '';
  url: string = '';
}

export class BookSourceDataUrlSupport {
  static isEncodedSource(url: string): boolean {
    return EncodedSourceUrl.canHandle(url);
  }

  static sourceUsesGySearch(source: BookSource): boolean {
    return (source.searchUrl || '').includes('gysearch') || (source.searchUrl || '').includes('gycatalog') ||
      (source.searchUrl || '').includes('gycontent');
  }

  static sourceUsesGyExplore(source: BookSource): boolean {
    return (source.exploreUrl || '').includes('discovestyle') || (source.searchUrl || '').includes('gysearch');
  }

  static async getExplorePlatforms(http: HttpClient, source: BookSource, tab: string = '小说'): Promise<string[]> {
    const cloudPlatforms = await BookSourceDataUrlSupport.getCloudExplorePlatforms(http, source, tab);
    if (cloudPlatforms.length > 0) return cloudPlatforms;

    const scriptPlatforms = BookSourceDataUrlSupport.getScriptExplorePlatforms(source.exploreUrl || '', tab);
    if (scriptPlatforms.length > 0) return scriptPlatforms;

    const groupPlatforms = BookSourceDataUrlSupport.getGroupExplorePlatforms(source.bookSourceGroup || '');
    if (groupPlatforms.length > 0) return groupPlatforms;

    const defaultPlatform = BookSourceDataUrlSupport.defaultExplorePlatform(source);
    return defaultPlatform ? [defaultPlatform] : [];
  }

  static getSingleSitePlatformName(source: BookSource): string {
    const group = (source.bookSourceGroup || '').split(',')
      .map((item: string) => item.trim())
      .filter((item: string) => item && item !== '聚合')[0];
    if (group) return group;
    const name = (source.bookSourceName || '').replace(/^[^\u4e00-\u9fa5A-Za-z0-9]+/, '').trim();
    if (name) return name;
    const host = (source.bookSourceUrl || '').replace(/^https?:\/\//, '').replace(/\/[\s\S]*$/, '');
    return host || '默认站点';
  }

  static buildRequestUrl(source: BookSource, rawUrl: string, page: string = '1', keyword: string = ''): string {
    const value = (rawUrl || '').trim();
    if (!value.includes('buildRequest')) return '';
    const match = value.match(/buildRequest\(\s*`([^`]+)`\s*\)/) ||
      value.match(/buildRequest\(\s*["']([^"']+)["']\s*\)/);
    if (!match || !match[1]) return '';
    const backend = BookSourceDataUrlSupport.backendHost(source);
    let url = match[1].replace(/\$\{backend\}/g, backend);
    const js = new JsRuntime();
    const encodedKey = encodeURIComponent(keyword || '');
    js.setVar('key', encodedKey);
    js.setVar('searchKey', encodedKey);
    js.setVar('keyword', encodedKey);
    js.setVar('page', page || '1');
    js.setVar('pageIndex', page || '1');
    url = js.evalTemplate(url);
    url = url.replace(/\{\{key\}\}/g, encodedKey)
      .replace(/\{\{searchKey\}\}/g, encodedKey)
      .replace(/\{\{keyword\}\}/g, encodedKey)
      .replace(/\{\{page\}\}/g, page || '1')
      .replace(/\{\{pageIndex\}\}/g, page || '1')
      .replace(/\{\{[^}]+\}\}/g, '');
    return url;
  }

  static sourceBackendHost(source: BookSource): string {
    return BookSourceDataUrlSupport.backendHost(source);
  }

  static async search(http: HttpClient, source: BookSource, keyword: string, page: number = 1): Promise<SearchBook[]> {
    const url = EncodedSourceUrl.buildSearchUrl(keyword, page);
    const root = await EncodedSourceUrl.requestJsonForDataUrl(http, url);
    if (!root) return [];
    return BookSourceDataUrlSupport.parseBookList(root, source);
  }

  static async getExploreEntries(http: HttpClient, platform: string = '番茄', tab: string = '小说',
    sourceType: string = '男频'): Promise<ExploreDataUrlEntry[]> {
    const source = BookSourceDataUrlSupport.normalizeExplorePlatform(platform);
    const root = await EncodedSourceUrl.requestJson(http,
      `/discovestyle?source=${encodeURIComponent(source)}&source_type=${encodeURIComponent(sourceType)}` +
        `&tab=${encodeURIComponent(tab)}`,
      'GET');
    if (!root) return [];
    const data = EncodedSourceUrl.asArray(root['data']);
    if (data.length === 0) return [];
    const entries: ExploreDataUrlEntry[] = [];
    const excludedTitles = ['点击登录可切换来源', '切换后长按刷新即可'];
    for (const item of data) {
      const rec = EncodedSourceUrl.asMap(item);
      const title = EncodedSourceUrl.str(rec['title']);
      const url = EncodedSourceUrl.str(rec['url']);
      if (!title || !url || excludedTitles.includes(title) || url.startsWith('{')) continue;
      const entry = new ExploreDataUrlEntry();
      entry.title = title;
      entry.url = url;
      entries.push(entry);
    }
    return entries;
  }

  static normalizeExplorePlatform(platform: string): string {
    const value = (platform || '').trim();
    if (!value) return '番茄';
    return value;
  }

  static async explore(http: HttpClient, source: BookSource, url: string, page: number): Promise<SearchBook[]> {
    const reqUrl = BookSourceDataUrlSupport.buildPagedUrl(url, page);
    const path = BookSourceDataUrlSupport.pathFromUrl(reqUrl);
    const host = BookSourceDataUrlSupport.hostFromUrl(reqUrl);
    if (!path) return [];
    const root = await EncodedSourceUrl.requestJson(http, path, 'GET', undefined, host);
    if (!root) return [];
    return BookSourceDataUrlSupport.parseBookList(root, source);
  }

  static async getBookInfo(http: HttpClient, source: BookSource, book: Book): Promise<Book> {
    const payload = EncodedSourceUrl.decode(book.bookUrl);
    if (payload?.type === 'mybxs') {
      return await BookSourceDataUrlSupport.getMyBxBookInfo(http, source, book, payload);
    }
    const meta = BookSourceDataUrlSupport.getMeta(book);
    if (!meta.bookId || !meta.source) return book;
    const root = await EncodedSourceUrl.requestJsonForDataUrl(http,
      EncodedSourceUrl.buildDetailUrl(meta.bookId, meta.source, meta.tab, meta.tocUrl, meta.host), meta.host);
    if (!root) return book;
    let data = EncodedSourceUrl.asMap(root['data']);
    if (Object.keys(data).length === 0) {
      data = root;
    }
    book.name = EncodedSourceUrl.str(data['book_name']) || book.name;
    book.author = EncodedSourceUrl.str(data['author']) || book.author;
    book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source,
      EncodedSourceUrl.str(data['thumb_url'])) || book.coverUrl;
    book.intro = EncodedSourceUrl.str(data['abstract']) || book.intro;
    book.kind = BookSourceDataUrlSupport.buildKind(data) || book.kind;
    book.latestChapterTitle = EncodedSourceUrl.str(data['last_chapter_title']) || book.latestChapterTitle;
    book.wordCount = EncodedSourceUrl.str(data['word_number']) || book.wordCount;
    book.origin = source.bookSourceUrl;
    book.originName = book.originName || source.bookSourceName;
    meta.tocUrl = EncodedSourceUrl.str(data['toc_url']) || meta.tocUrl;
    book.bookUrl = EncodedSourceUrl.buildDetailUrl(meta.bookId, meta.source, meta.tab, meta.tocUrl, meta.host);
    book.tocUrl = BookSourceDataUrlSupport.catalogUrl(meta);
    book.variable = JSON.stringify(meta);
    return book;
  }

  static async getChapterList(http: HttpClient, source: BookSource, book: Book): Promise<BookChapter[]> {
    const myBxPayload = EncodedSourceUrl.decode(book.tocUrl) || EncodedSourceUrl.decode(book.bookUrl);
    if (myBxPayload?.type === 'mybxs') {
      return await BookSourceDataUrlSupport.getMyBxChapterList(http, source, book, myBxPayload);
    }
    const meta = BookSourceDataUrlSupport.getMeta(book);
    if (!meta.bookId || !meta.source) return [];
    const root = await EncodedSourceUrl.requestJsonForDataUrl(http, BookSourceDataUrlSupport.catalogUrl(meta), meta.host);
    if (!root) return [];
    const data = EncodedSourceUrl.asArray(root['data']);
    if (data.length === 0) return [];
    const chapters: BookChapter[] = [];
    for (let i = 0; i < data.length; i++) {
      const rec = EncodedSourceUrl.asMap(data[i]);
      const itemId = EncodedSourceUrl.str(rec['item_id']);
      if (!itemId) continue;
      const source = EncodedSourceUrl.str(rec['source']) || meta.source;
      const tab = EncodedSourceUrl.str(rec['tab']) || meta.tab;
      const chapter = new BookChapter();
      chapter.title = EncodedSourceUrl.str(rec['title']) || `第${chapters.length + 1}章`;
      chapter.url = EncodedSourceUrl.buildContentUrl({
        book_id: meta.bookId,
        item_id: itemId,
        title: chapter.title,
        sources: source,
        source: source,
        tab: tab,
        url: EncodedSourceUrl.str(rec['toc_url']),
        toc_url: EncodedSourceUrl.str(rec['toc_url'])
      }, meta.host);
      chapter.bookUrl = book.bookUrl;
      chapter.index = chapters.length;
      chapter.isPay = EncodedSourceUrl.str(rec['is_pay']) === 'true' || EncodedSourceUrl.str(rec['is_pay']) === '1';
      chapter.variable = JSON.stringify({
        itemId: itemId,
        source: source,
        tab: tab,
        host: meta.host,
        tocUrl: EncodedSourceUrl.str(rec['toc_url'])
      });
      chapters.push(chapter);
    }
    return chapters;
  }

  static async getContent(http: HttpClient, source: BookSource, book: Book, chapter: BookChapter): Promise<string> {
    const payload = EncodedSourceUrl.decode(chapter.url);
    if (payload?.type === 'mybxc') {
      return await BookSourceDataUrlSupport.getMyBxContent(http, source, book, chapter, payload);
    }
    const info = BookSourceDataUrlSupport.getChapterInfo(chapter);
    const root = await EncodedSourceUrl.requestJsonForDataUrl(http, chapter.url, info['host']);
    if (!root) return '';
    const content = BookSourceDataUrlSupport.readContent(root);
    if (BookSourceDataUrlSupport.needsLogin(root, content)) {
      VerificationSupport.requestVerification(BookSourceDataUrlSupport.loginUrlForContent(info), '登录');
      return '';
    }
    return BookSourceDataUrlSupport.cleanContentText(content);
  }

  private static async getMyBxBookInfo(http: HttpClient, source: BookSource, book: Book,
    payload: EncodedSourcePayload): Promise<Book> {
    const host = BookSourceDataUrlSupport.myBxHost(source, book, payload);
    const bookId = payload.text;
    if (!host || !bookId) return book;
    const root = await BookSourceDataUrlSupport.requestMyBxBackendJson(http,
      `/bx/detail?book_id=${encodeURIComponent(bookId)}`, host);
    if (!root) {
      return await BookSourceDataUrlSupport.getMyBxBookInfoFromSite(http, source, book, bookId, host);
    }
    const list = EncodedSourceUrl.asArray(root['list']);
    const data = list.length > 0 ? EncodedSourceUrl.asMap(list[0]) : root;
    if (Object.keys(data).length === 0) {
      return await BookSourceDataUrlSupport.getMyBxBookInfoFromSite(http, source, book, bookId, host);
    }
    book.name = EncodedSourceUrl.str(data['articlename']) || book.name;
    book.author = EncodedSourceUrl.str(data['author']) || book.author;
    book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source,
      BookSourceDataUrlSupport.resolveSourceUrl(host, EncodedSourceUrl.str(data['imgUrl']))) || book.coverUrl;
    book.intro = EncodedSourceUrl.str(data['intro']) || book.intro;
    book.kind = BookSourceDataUrlSupport.joinTextArray(data['keywords']) || book.kind;
    book.latestChapterTitle = EncodedSourceUrl.str(data['lastchapter']) || book.latestChapterTitle;
    book.wordCount = EncodedSourceUrl.str(data['words']) || book.wordCount;
    book.bookUrl = EncodedSourceUrl.encodeRaw(bookId, 'mybxs', host);
    book.tocUrl = book.bookUrl;
    book.origin = source.bookSourceUrl;
    book.originName = book.originName || source.bookSourceName;
    book.variable = JSON.stringify({ bookId: bookId, host: host, type: 'mybxs' });
    return book;
  }

  private static async getMyBxChapterList(http: HttpClient, source: BookSource, book: Book,
    payload: EncodedSourcePayload): Promise<BookChapter[]> {
    const host = BookSourceDataUrlSupport.myBxHost(source, book, payload);
    const bookId = payload.text;
    if (!host || !bookId) return [];
    const root = await BookSourceDataUrlSupport.requestMyBxBackendJson(http,
      `/bx/catalog?book_id=${encodeURIComponent(bookId)}`, host);
    if (!root) {
      return await BookSourceDataUrlSupport.getMyBxChapterListFromSite(http, source, book, bookId, host);
    }
    const list = EncodedSourceUrl.asArray(root['list']);
    if (list.length === 0) {
      return await BookSourceDataUrlSupport.getMyBxChapterListFromSite(http, source, book, bookId, host);
    }
    const chapters: BookChapter[] = [];
    for (const item of list) {
      const rec = EncodedSourceUrl.asMap(item);
      const articleId = EncodedSourceUrl.str(rec['articleid']) || bookId;
      const chapterId = EncodedSourceUrl.str(rec['chapterid']);
      if (!chapterId) continue;
      const chapter = new BookChapter();
      chapter.title = EncodedSourceUrl.str(rec['chaptername']) || `第${chapters.length + 1}章`;
      chapter.url = EncodedSourceUrl.encodeRaw(`${articleId}/${chapterId}`, 'mybxc', host);
      chapter.bookUrl = book.bookUrl;
      chapter.index = chapters.length;
      chapter.variable = JSON.stringify({ bookId: articleId, chapterId: chapterId, host: host, type: 'mybxc' });
      chapters.push(chapter);
    }
    return chapters;
  }

  private static async getMyBxContent(http: HttpClient, source: BookSource, book: Book, chapter: BookChapter,
    payload: EncodedSourcePayload): Promise<string> {
    const host = BookSourceDataUrlSupport.myBxHost(source, book, payload, chapter);
    const parts = (payload.text || '').split('/');
    const bookId = parts[0] || EncodedSourceUrl.str(payload.data['book_id']) || EncodedSourceUrl.str(payload.data['bookId']);
    const chapterId = parts[1] || EncodedSourceUrl.str(payload.data['chapter_id']) ||
      EncodedSourceUrl.str(payload.data['chapterId']);
    const root = bookId && chapterId ? await BookSourceDataUrlSupport.requestMyBxBackendJson(http,
      `/bx/content?book_id=${encodeURIComponent(bookId)}&chapter_id=${encodeURIComponent(chapterId)}`, host) : null;
    if (!root) {
      return await BookSourceDataUrlSupport.getMyBxContentFromSite(http, source, chapter, payload);
    }
    const content = BookSourceDataUrlSupport.cleanContentText(EncodedSourceUrl.str(root['data']) ||
      EncodedSourceUrl.str(root['content']));
    if (content) return content;
    return await BookSourceDataUrlSupport.getMyBxContentFromSite(http, source, chapter, payload);
  }

  private static async getMyBxBookInfoFromSite(http: HttpClient, source: BookSource, book: Book, bookId: string,
    backendHost: string): Promise<Book> {
    const siteHost = BookSourceDataUrlSupport.myBxSiteHost(source);
    if (!siteHost) return book;
    const resp = await BookSourceDataUrlSupport.fetchMyBxSite(http, `${siteHost}/books/${encodeURIComponent(bookId)}.html`);
    if (!resp.success || !resp.body) return book;
    const html = resp.body;
    const describeBlock = BookSourceDataUrlSupport.extractElementBlockByClass(html, 'book-describe');
    book.name = BookSourceDataUrlSupport.cleanContentText(BookSourceDataUrlSupport.extractFirst(describeBlock,
      /<h1[^>]*>([\s\S]*?)<\/h1>/i)) || book.name;
    book.author = BookSourceDataUrlSupport.cleanContentText(BookSourceDataUrlSupport.extractFirst(describeBlock,
      /作者[︰:]\s*<a[^>]*>([\s\S]*?)<\/a>/i)) || book.author;
    book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source,
      BookSourceDataUrlSupport.extractFirst(html, /<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i) ||
        BookSourceDataUrlSupport.extractFirst(html, /<img[^>]+data-original=["']([^"']+)["']/i)) || book.coverUrl;
    book.kind = BookSourceDataUrlSupport.joinNonEmpty([
      BookSourceDataUrlSupport.cleanContentText(BookSourceDataUrlSupport.extractFirst(describeBlock,
        /類型[︰:]\s*([\s\S]*?)<\/p>/i)),
      BookSourceDataUrlSupport.cleanContentText(BookSourceDataUrlSupport.extractFirst(describeBlock,
        /狀態[︰:]\s*([\s\S]*?)<\/p>/i))
    ], ',') || book.kind;
    book.latestChapterTitle = BookSourceDataUrlSupport.cleanContentText(BookSourceDataUrlSupport.extractFirst(describeBlock,
      /最新章節[︰:]\s*<a[^>]*>([\s\S]*?)<\/a>/i)) || book.latestChapterTitle;
    const introBlock = BookSourceDataUrlSupport.extractElementBlockByClass(html, 'describe-html');
    book.intro = BookSourceDataUrlSupport.cleanContentText(introBlock) || book.intro;
    book.bookUrl = EncodedSourceUrl.encodeRaw(bookId, 'mybxs', backendHost);
    book.tocUrl = book.bookUrl;
    book.origin = source.bookSourceUrl;
    book.originName = book.originName || source.bookSourceName;
    book.variable = JSON.stringify({ bookId: bookId, host: backendHost, type: 'mybxs' });
    return book;
  }

  private static async getMyBxChapterListFromSite(http: HttpClient, source: BookSource, book: Book, bookId: string,
    backendHost: string): Promise<BookChapter[]> {
    const siteHost = BookSourceDataUrlSupport.myBxSiteHost(source);
    if (!siteHost) return [];
    const resp = await BookSourceDataUrlSupport.fetchMyBxSite(http, `${siteHost}/books/${encodeURIComponent(bookId)}.html`);
    if (!resp.success || !resp.body) return [];
    const block = BookSourceDataUrlSupport.extractElementBlockByClass(resp.body, 'book-list') || resp.body;
    const re = /<a\b[^>]*href=["']([^"']*\/books\/(\d+)\/(\d+)\.html?)["'][^>]*>([\s\S]*?)<\/a>/gi;
    const chapters: BookChapter[] = [];
    const seen: string[] = [];
    let match: RegExpExecArray | null;
    while ((match = re.exec(block)) !== null) {
      const articleId = match[2] || bookId;
      const chapterId = match[3] || '';
      if (!chapterId || (articleId !== bookId && bookId)) continue;
      const key = `${articleId}/${chapterId}`;
      if (seen.includes(key)) continue;
      seen.push(key);
      const chapter = new BookChapter();
      chapter.title = BookSourceDataUrlSupport.cleanContentText(match[4]) || `第${chapters.length + 1}章`;
      chapter.url = EncodedSourceUrl.encodeRaw(key, 'mybxc', backendHost);
      chapter.bookUrl = book.bookUrl;
      chapter.index = chapters.length;
      chapter.variable = JSON.stringify({
        bookId: articleId,
        chapterId: chapterId,
        host: backendHost,
        type: 'mybxc',
        siteHost: siteHost
      });
      chapters.push(chapter);
      if (chapters.length > 10000) break;
    }
    return chapters;
  }

  private static async getMyBxContentFromSite(http: HttpClient, source: BookSource, chapter: BookChapter,
    payload: EncodedSourcePayload): Promise<string> {
    const parts = (payload.text || '').split('/');
    const bookId = parts[0] || BookSourceDataUrlSupport.variableValue(chapter.variable, 'bookId');
    const chapterId = parts[1] || BookSourceDataUrlSupport.variableValue(chapter.variable, 'chapterId');
    if (!bookId || !chapterId) return '';
    const siteHost = BookSourceDataUrlSupport.variableValue(chapter.variable, 'siteHost') ||
      BookSourceDataUrlSupport.myBxSiteHost(source);
    if (!siteHost) return '';
    const resp = await BookSourceDataUrlSupport.fetchMyBxSite(http,
      `${siteHost}/books/${encodeURIComponent(bookId)}/${encodeURIComponent(chapterId)}.html`);
    if (!resp.success || !resp.body) return '';
    const block = BookSourceDataUrlSupport.extractElementBlockById(resp.body, 'nr1');
    const content = BookSourceDataUrlSupport.cleanContentText(block);
    if (content) return content;
    return BookSourceDataUrlSupport.cleanContentText(BookSourceDataUrlSupport.extractElementBlockByClass(resp.body,
      'post'));
  }

  private static parseBookList(root: EncodedJsonMap, source: BookSource): SearchBook[] {
    const data = EncodedSourceUrl.asArray(root['data']);
    if (data.length === 0) return [];
    const books: SearchBook[] = [];
    for (const item of data) {
      const rec = EncodedSourceUrl.asMap(item);
      const bookId = EncodedSourceUrl.str(rec['book_id']);
      const itemSource = EncodedSourceUrl.str(rec['source']);
      const tab = EncodedSourceUrl.str(rec['tab']) || '小说';
      const name = EncodedSourceUrl.str(rec['book_name']);
      if (!name || !bookId || bookId === 'vip' || bookId === 'svip' || !itemSource) continue;
      const tocUrl = EncodedSourceUrl.str(rec['toc_url']);
      const host = EncodedSourceUrl.hostFromData(rec);
      const book = new SearchBook();
      book.name = name;
      book.author = EncodedSourceUrl.str(rec['author']);
      book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source, EncodedSourceUrl.str(rec['thumb_url']));
      book.intro = EncodedSourceUrl.str(rec['abstract']);
      book.kind = BookSourceDataUrlSupport.buildKind(rec);
      book.latestChapterTitle = EncodedSourceUrl.str(rec['last_chapter_title']);
      book.wordCount = EncodedSourceUrl.str(rec['word_number']);
      book.bookUrl = EncodedSourceUrl.buildDetailUrl(bookId, itemSource, tab, tocUrl, host);
      book.tocUrl = BookSourceDataUrlSupport.catalogUrlFromValues(bookId, itemSource, tab, tocUrl, host);
      book.variable = JSON.stringify({ bookId: bookId, source: itemSource, tab: tab, tocUrl: tocUrl, host: host });
      book.origin = source.bookSourceUrl;
      book.originName = `${source.bookSourceName} · ${itemSource}`;
      book.bookSourceComment = source.bookSourceComment;
      book.customOrder = source.customOrder;
      book.weight = source.weight;
      if (!books.some((bookItem: SearchBook) => bookItem.bookUrl === book.bookUrl && bookItem.origin === book.origin)) {
        books.push(book);
      }
    }
    return books;
  }

  private static getMeta(book: Book): DataUrlMeta {
    const meta = new DataUrlMeta();
    BookSourceDataUrlSupport.fillMetaFromPayload(meta, EncodedSourceUrl.decode(book.bookUrl));
    BookSourceDataUrlSupport.fillMetaFromPayload(meta, EncodedSourceUrl.decode(book.tocUrl));
    try {
      const raw = EncodedSourceUrl.asMap(JSON.parse(book.variable || '{}') as Object);
      meta.host = EncodedSourceUrl.str(raw['host']) || EncodedSourceUrl.str(raw['gyHost']) || meta.host;
      meta.bookId = EncodedSourceUrl.str(raw['bookId']) || EncodedSourceUrl.str(raw['book_id']) || meta.bookId;
      meta.source = EncodedSourceUrl.str(raw['source']) || EncodedSourceUrl.str(raw['sources']) || meta.source;
      meta.tab = EncodedSourceUrl.str(raw['tab']) || meta.tab;
      meta.tocUrl = EncodedSourceUrl.str(raw['tocUrl']) || EncodedSourceUrl.str(raw['toc_url']) || meta.tocUrl;
    } catch (_) {
    }
    return meta;
  }

  private static fillMetaFromPayload(meta: DataUrlMeta, payload: EncodedSourcePayload | null): void {
    if (!payload) return;
    const data = payload.data;
    meta.host = EncodedSourceUrl.str(data['host']) || EncodedSourceUrl.str(data['gyHost']) || meta.host;
    meta.bookId = EncodedSourceUrl.str(data['bookId']) || EncodedSourceUrl.str(data['book_id']) || meta.bookId;
    meta.source = EncodedSourceUrl.str(data['source']) || EncodedSourceUrl.str(data['sources']) || meta.source;
    meta.tab = EncodedSourceUrl.str(data['tab']) || meta.tab;
    meta.tocUrl = EncodedSourceUrl.str(data['tocUrl']) || EncodedSourceUrl.str(data['toc_url']) ||
      EncodedSourceUrl.str(data['url']) || meta.tocUrl;
  }

  private static getChapterInfo(chapter: BookChapter): Record<string, string> {
    const info: Record<string, string> = {};
    const payload = EncodedSourceUrl.decode(chapter.url);
    if (payload) {
      info['itemId'] = EncodedSourceUrl.str(payload.data['item_id']) || EncodedSourceUrl.str(payload.data['itemId']);
      info['source'] = EncodedSourceUrl.str(payload.data['source']) || EncodedSourceUrl.str(payload.data['sources']);
      info['tab'] = EncodedSourceUrl.str(payload.data['tab']) || '小说';
      info['host'] = EncodedSourceUrl.str(payload.data['host']) || EncodedSourceUrl.DEFAULT_HOSTS[0];
      info['tocUrl'] = EncodedSourceUrl.str(payload.data['toc_url']) || EncodedSourceUrl.str(payload.data['url']);
    }
    try {
      const raw = EncodedSourceUrl.asMap(JSON.parse(chapter.variable || '{}') as Object);
      info['itemId'] = EncodedSourceUrl.str(raw['itemId']) || EncodedSourceUrl.str(raw['item_id']) || info['itemId'];
      info['source'] = EncodedSourceUrl.str(raw['source']) || EncodedSourceUrl.str(raw['sources']) || info['source'];
      info['tab'] = EncodedSourceUrl.str(raw['tab']) || info['tab'] || '小说';
      info['host'] = EncodedSourceUrl.str(raw['host']) || info['host'] || EncodedSourceUrl.DEFAULT_HOSTS[0];
      info['tocUrl'] = EncodedSourceUrl.str(raw['tocUrl']) || EncodedSourceUrl.str(raw['toc_url']) || info['tocUrl'];
    } catch (_) {
    }
    return info;
  }

  private static catalogUrl(meta: DataUrlMeta): string {
    return BookSourceDataUrlSupport.catalogUrlFromValues(meta.bookId, meta.source, meta.tab, meta.tocUrl, meta.host);
  }

  private static catalogUrlFromValues(bookId: string, source: string, tab: string, tocUrl: string, host: string): string {
    return EncodedSourceUrl.buildCatalogUrl({
      book_id: bookId,
      sources: source,
      source: source,
      tab: tab || '小说',
      url: tocUrl,
      toc_url: tocUrl
    }, host);
  }

  private static buildKind(rec: EncodedJsonMap): string {
    const values = [
      EncodedSourceUrl.str(rec['status']),
      EncodedSourceUrl.str(rec['category']),
      EncodedSourceUrl.str(rec['tags']),
      EncodedSourceUrl.str(rec['score']),
      EncodedSourceUrl.str(rec['last_chapter_update_time']) ? `最后更新 ${EncodedSourceUrl.str(rec['last_chapter_update_time'])}` : ''
    ];
    const result: string[] = [];
    for (const value of values) {
      for (const item of value.split(',')) {
        const tag = item.trim();
        if (tag && !result.includes(tag)) result.push(tag);
      }
    }
    return result.join(',');
  }

  private static readContent(root: EncodedJsonMap): string {
    const data = EncodedSourceUrl.asMap(root['data']);
    const content = EncodedSourceUrl.str(root['content']) || EncodedSourceUrl.str(data['content']);
    if (content) return content;
    const contents = BookSourceDataUrlSupport.joinTextArray(root['contents']) ||
      BookSourceDataUrlSupport.joinTextArray(data['contents']);
    if (contents) return contents;
    return EncodedSourceUrl.str(root['msg']);
  }

  private static joinTextArray(value: Object | string | number | boolean | null | undefined): string {
    if (!Array.isArray(value)) return '';
    const result: string[] = [];
    for (const item of value as Object[]) {
      const text = EncodedSourceUrl.str(item);
      if (text) result.push(text);
    }
    return result.join('\n');
  }

  private static needsLogin(root: EncodedJsonMap, content: string): boolean {
    const code = EncodedSourceUrl.str(root['code']);
    const msg = EncodedSourceUrl.str(root['msg']);
    const text = `${msg}\n${content}`;
    return (code === '-1' && (text.includes('登录') || text.includes('登陆') || text.includes('访问次数'))) ||
      text.includes('免登录访问次数已达上限') || text.includes('继续阅读请登录') ||
      text.includes('请登录后刷新') || text.includes('今日免登录访问次数') ||
      text.includes('请先登录') || text.includes('请先登陆') ||
      text.includes('登录信息已失效') || text.includes('账号信息异常') ||
      text.includes('请重新登录') || text.includes('请重新登陆');
  }

  private static loginUrlForContent(info: Record<string, string>): string {
    return EncodedSourceUrl.getLoginUrl(info['host'] || EncodedSourceUrl.DEFAULT_HOSTS[0]);
  }

  static normalizeCoverUrl(source: BookSource, url: string, baseUrl: string = ''): string {
    const resolved = BookUrlResolver.resolve(url, baseUrl || source.bookSourceUrl);
    return BookSourceDataUrlSupport.normalizeMirroredAssetUrl(source, resolved);
  }

  private static normalizeMirroredAssetUrl(source: BookSource, url: string): string {
    const value = (url || '').trim();
    if (!value) return '';
    if (value.includes('/bx/files/')) {
      const assetOrigin = BookSourceDataUrlSupport.preferredAssetOrigin(source);
      if (assetOrigin) {
        return value.replace(/^https?:\/\/[^/]+\/bx\/files\//i, `${assetOrigin}/files/`);
      }
    }
    return value;
  }

  private static myBxHost(source: BookSource, book: Book, payload: EncodedSourcePayload,
    chapter?: BookChapter): string {
    const fromPayload = EncodedSourceUrl.str(payload.options['host']) || EncodedSourceUrl.str(payload.data['host']);
    if (fromPayload) return fromPayload;
    const fromBook = BookSourceDataUrlSupport.variableValue(book.variable, 'host');
    if (fromBook) return fromBook;
    const fromChapter = chapter ? BookSourceDataUrlSupport.variableValue(chapter.variable, 'host') : '';
    if (fromChapter) return fromChapter;
    return BookSourceDataUrlSupport.backendHost(source);
  }

  private static variableValue(raw: string, key: string): string {
    try {
      const data = EncodedSourceUrl.asMap(JSON.parse(raw || '{}') as Object);
      return EncodedSourceUrl.str(data[key]);
    } catch (_) {
      return '';
    }
  }

  private static async fetchMyBxSite(http: HttpClient, url: string): Promise<HttpResponse> {
    const referer = BookSourceDataUrlSupport.originFromUrl(url);
    return await http.execute({
      url: url,
      method: 'GET',
      headers: {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Referer': referer
      }
    });
  }

  private static async requestMyBxBackendJson(http: HttpClient, path: string, host: string):
    Promise<EncodedJsonMap | null> {
    if (!host || !path) return null;
    const resp = await http.execute({
      url: `${host}${path}`,
      method: 'GET',
      headers: {
        'Accept': 'application/json, text/plain, */*'
      }
    });
    if (!resp.success || !resp.body) return null;
    try {
      return EncodedSourceUrl.asMap(JSON.parse(resp.body) as Object);
    } catch (_) {
      return null;
    }
  }

  private static myBxSiteHost(source: BookSource | null): string {
    if (!source) return '';
    const raw = BookSourceDataUrlSupport.sourceRaw(source);
    const bookUrlMatch = raw.match(/https?:\/\/[^'"`\s#)]+\/books?\//i);
    if (bookUrlMatch && bookUrlMatch[0]) return BookSourceDataUrlSupport.originFromUrl(bookUrlMatch[0]);
    const sourceOrigin = BookSourceDataUrlSupport.originFromUrl(source.bookSourceUrl || '');
    if (sourceOrigin) return sourceOrigin;
    const assetOrigin = BookSourceDataUrlSupport.preferredAssetOrigin(source);
    const assetHostMatch = assetOrigin.match(/^(https?:\/\/)([^/]+)$/i);
    if (assetHostMatch && assetHostMatch[1] && assetHostMatch[2]) {
      const host = assetHostMatch[2].replace(/^(?:image|img|pic|static|assets?|files?)[.-]/i, 'www.');
      if (host !== assetHostMatch[2]) return `${assetHostMatch[1]}${host}`;
    }
    return '';
  }

  private static extractFirst(text: string, regex: RegExp): string {
    const match = (text || '').match(regex);
    return match && match[1] ? match[1] : '';
  }

  private static extractElementBlockById(html: string, id: string): string {
    return BookSourceDataUrlSupport.extractElementBlock(html, 'id', id);
  }

  private static extractElementBlockByClass(html: string, className: string): string {
    return BookSourceDataUrlSupport.extractElementBlock(html, 'class', className);
  }

  private static extractElementBlock(html: string, attrName: string, attrValue: string): string {
    if (!html || !attrName || !attrValue) return '';
    const re = new RegExp(`<([a-zA-Z][\\w-]*)([^>]*\\s${BookSourceDataUrlSupport.escapeRegExp(attrName)}` +
      `=["'][^"']*\\b${BookSourceDataUrlSupport.escapeRegExp(attrValue)}\\b[^"']*["'][^>]*)>`, 'i');
    const match = re.exec(html);
    if (!match) return '';
    const start = match.index;
    const tag = match[1];
    const tagRe = new RegExp(`<\\/?${BookSourceDataUrlSupport.escapeRegExp(tag)}(?:\\s[^>]*)?>`, 'gi');
    tagRe.lastIndex = start;
    let depth = 0;
    let tagMatch: RegExpExecArray | null;
    while ((tagMatch = tagRe.exec(html)) !== null) {
      if (tagMatch[0].startsWith('</')) {
        depth--;
        if (depth === 0) return html.substring(start, tagRe.lastIndex);
      } else if (!tagMatch[0].endsWith('/>')) {
        depth++;
      }
    }
    return html.substring(start);
  }

  private static joinNonEmpty(values: string[], separator: string): string {
    const result: string[] = [];
    for (const value of values) {
      const item = (value || '').trim();
      if (item && !result.includes(item)) result.push(item);
    }
    return result.join(separator);
  }

  private static cleanContentText(value: string): string {
    return BookSourceDataUrlSupport.decodeHtmlEntities(value || '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n\n')
      .replace(/<\/div>/gi, '\n')
      .replace(/<\/li>/gi, '\n')
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<iframe[\s\S]*?<\/iframe>/gi, '')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/\(本章完\)/g, '')
      .replace(/\r\n?/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private static decodeHtmlEntities(value: string): string {
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

  private static backendHost(source: BookSource): string {
    const raw = `${source.jsLib || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}\n${source.bookSourceUrl || ''}`;
    const backendMatch = raw.match(/\bbackend\s*=\s*["']([^"']+)["']/);
    if (backendMatch && backendMatch[1]) return backendMatch[1];
    const bxMatch = raw.match(/(https?:\/\/[^'"`\s,)]+)\/bx\//);
    if (bxMatch && bxMatch[1]) return bxMatch[1];
    const hostMatch = raw.match(/https?:\/\/[^'"`\s,)]+/);
    return hostMatch ? hostMatch[0] : '';
  }

  private static resolveSourceUrl(host: string, url: string): string {
    if (!url) return '';
    if (/^http:\/\/[^/]+\/(?:bx\/)?files\//i.test(url)) {
      return url.replace(/^http:\/\//i, 'https://');
    }
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return `${host}${url}`;
    return `${host}/${url}`;
  }

  private static sourceRaw(source: BookSource): string {
    return `${source.bookSourceUrl || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}\n${source.jsLib || ''}`
      .replace(/\\\//g, '/');
  }

  private static preferredAssetOrigin(source: BookSource): string {
    const raw = BookSourceDataUrlSupport.sourceRaw(source);
    const urls = raw.match(/https?:\/\/[^'"`\s#),]+/g) || [];
    for (const url of urls) {
      const origin = BookSourceDataUrlSupport.originFromUrl(url);
      const host = origin.replace(/^https?:\/\//i, '');
      if (/^(?:image|img|pic|static|assets?|files?)[.-]/i.test(host)) return origin;
      if (/(?:^|[.-])(?:image|img|pic|static|assets?|files?)(?:[.-]|$)/i.test(host)) return origin;
    }
    return '';
  }

  private static originFromUrl(url: string): string {
    const match = (url || '').match(/^https?:\/\/[^/]+/i);
    return match && match[0] ? match[0].replace(/^http:\/\//i, 'https://') : '';
  }

  private static buildPagedUrl(url: string, page: number): string {
    const value = url || '';
    if (value.includes('{{page}}')) return value.replace(/\{\{page\}\}/g, String(page));
    if (/[?&]page=/.test(value)) return value.replace(/([?&]page=)[^&]*/, `$1${page}`);
    return `${value}${value.includes('?') ? '&' : '?'}page=${page}`;
  }

  private static hostFromUrl(url: string): string {
    const match = (url || '').match(/^(https?:\/\/[^/]+)/);
    return match ? match[1] : '';
  }

  private static pathFromUrl(url: string): string {
    const value = url || '';
    if (value.startsWith('/')) return value;
    const match = value.match(/^https?:\/\/[^/]+([\s\S]*)$/);
    return match ? match[1] : '';
  }

  private static async getCloudExplorePlatforms(http: HttpClient, source: BookSource, tab: string): Promise<string[]> {
    if (!(source.exploreUrl || '').includes('云端配置') && !(source.jsLib || '').includes('source_config')) return [];
    const root = await EncodedSourceUrl.requestJson(http, '/static/source_config/config.json', 'GET',
      undefined, BookSourceDataUrlSupport.firstHostFromSource(source));
    if (!root) return [];
    const items = EncodedSourceUrl.asArray(root[tab || '小说']);
    return BookSourceDataUrlSupport.uniqueStrings(items.map((item: Object) => EncodedSourceUrl.str(item)));
  }

  private static getScriptExplorePlatforms(script: string, tab: string): string[] {
    const tabList = BookSourceDataUrlSupport.findSourceListNearTab(script, tab || '小说');
    if (tabList.length > 0) return tabList;
    const regex = /source_list\s*=\s*(\[[\s\S]*?\])/g;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(script)) !== null) {
      const items = BookSourceDataUrlSupport.parseStringArrayLiteral(match[1]);
      if (items.length > 0) return items;
    }
    return [];
  }

  private static findSourceListNearTab(script: string, tab: string): string[] {
    const tabPattern = BookSourceDataUrlSupport.escapeRegExp(tab);
    const regex = new RegExp(`if\\s*\\([^)]*tab\\s*==\\s*['"]${tabPattern}['"][\\s\\S]*?source_list\\s*=\\s*(\\[[\\s\\S]*?\\])`);
    const match = regex.exec(script);
    if (!match) return [];
    return BookSourceDataUrlSupport.parseStringArrayLiteral(match[1]);
  }

  private static parseStringArrayLiteral(literal: string): string[] {
    const items: string[] = [];
    const regex = /['"]([^'"]+)['"]/g;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(literal)) !== null) {
      const value = (match[1] || '').trim();
      if (value && !items.includes(value)) items.push(value);
    }
    return items;
  }

  private static getGroupExplorePlatforms(group: string): string[] {
    const excluded = ['聚合', '大灰狼聚合', '轻小说'];
    const items = group.split(',')
      .map((item: string) => item.trim())
      .filter((item: string) => item && !excluded.includes(item));
    return BookSourceDataUrlSupport.uniqueStrings(items);
  }

  private static defaultExplorePlatform(source: BookSource): string {
    const raw = `${source.exploreUrl || ''}\n${source.jsLib || ''}`;
    const keys = ['发现页来源', 'find_source', 'sources'];
    for (const key of keys) {
      const regex = new RegExp(`${BookSourceDataUrlSupport.escapeRegExp(key)}["']?\\s*[:=]\\s*["']([^"']+)["']`);
      const match = regex.exec(raw);
      if (match && match[1]) return match[1].trim();
    }
    return '';
  }

  private static firstHostFromSource(source: BookSource): string {
    const raw = `${source.jsLib || ''}\n${source.exploreUrl || ''}`;
    const match = raw.match(/https?:\/\/[^'",\]\s]+/);
    return match ? match[0] : '';
  }

  private static uniqueStrings(items: string[]): string[] {
    const result: string[] = [];
    for (const item of items) {
      const value = (item || '').trim();
      if (value && !result.includes(value)) result.push(value);
    }
    return result;
  }

  private static escapeRegExp(value: string): string {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
}
