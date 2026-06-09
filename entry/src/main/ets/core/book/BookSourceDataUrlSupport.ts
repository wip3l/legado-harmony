import { Book, BookChapter, BookSource, SearchBook } from '../../model/data/Book';
import { HttpClient, HttpResponse } from '../http/HttpClient';
import { VerificationSupport } from '../http/VerificationSupport';
import { JsRuntime } from '../rule/JsRuntime';
import { EncodedJsonMap, EncodedSourcePayload, EncodedSourceUrl } from './EncodedSourceUrl';
import { BookUrlResolver } from './BookUrlResolver';
import { CoverUrlNormalizer } from '../../utils/CoverUrlNormalizer';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

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
    if (BookSourceDataUrlSupport.sourceUsesShushan(source)) return true;
    return (source.searchUrl || '').includes('gysearch') || (source.searchUrl || '').includes('gycatalog') ||
      (source.searchUrl || '').includes('gycontent');
  }

  static sourceUsesGyExplore(source: BookSource): boolean {
    if (BookSourceDataUrlSupport.sourceUsesShushan(source)) return true;
    return (source.exploreUrl || '').includes('discovestyle') || (source.searchUrl || '').includes('gysearch');
  }

  static async getExplorePlatforms(http: HttpClient, source: BookSource, tab: string = '小说'): Promise<string[]> {
    if (BookSourceDataUrlSupport.sourceUsesShushan(source)) {
      return BookSourceDataUrlSupport.getShushanPlatforms(source);
    }
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
    if (BookSourceDataUrlSupport.sourceUsesShushan(source)) {
      const host = BookSourceDataUrlSupport.shushanHost(source);
      const secretKey = BookSourceDataUrlSupport.shushanSecretKey(source);
      if (!secretKey) {
        VerificationSupport.requestVerification(BookSourceDataUrlSupport.shushanLoginUrl(source, host), '书山聚合 登录', source);
      }
      const query = BookSourceDataUrlSupport.parseShushanSearchKeyword(keyword);
      const selectedSource = query.source || BookSourceDataUrlSupport.shushanSelectedSource(source);
      const path = `/search?login=search&key=${encodeURIComponent(query.keyword)}&page=${page}` +
        (selectedSource ? `&source=${encodeURIComponent(selectedSource)}` : '');
      const root = await BookSourceDataUrlSupport.requestShushanJson(http, host, path);
      return root ? BookSourceDataUrlSupport.parseShushanBookList(root, source, host) : [];
    }
    const host = BookSourceDataUrlSupport.firstHostFromSource(source);
    const url = EncodedSourceUrl.buildSearchUrl(keyword, page);
    const root = await EncodedSourceUrl.requestJsonForDataUrl(http, url, host);
    if (!root) return [];
    return BookSourceDataUrlSupport.parseBookList(root, source, host);
  }

  static async getExploreEntries(http: HttpClient, platform: string = '番茄', tab: string = '小说',
    sourceType: string = '男频', bookSource?: BookSource): Promise<ExploreDataUrlEntry[]> {
    if (bookSource && BookSourceDataUrlSupport.sourceUsesShushan(bookSource)) {
      return await BookSourceDataUrlSupport.getShushanExploreEntries(http, bookSource, platform, sourceType);
    }
    const source = BookSourceDataUrlSupport.normalizeExplorePlatform(platform);
    const host = bookSource ? BookSourceDataUrlSupport.firstHostFromSource(bookSource) : '';
    const root = await EncodedSourceUrl.requestJson(http,
      `/discovestyle?source=${encodeURIComponent(source)}&source_type=${encodeURIComponent(sourceType)}` +
        `&tab=${encodeURIComponent(tab)}`,
      'GET', undefined, host);
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
    if (BookSourceDataUrlSupport.sourceUsesShushan(source)) {
      const reqUrl = BookSourceDataUrlSupport.buildShushanPagedUrl(url, page);
      const host = BookSourceDataUrlSupport.hostFromUrl(reqUrl) || BookSourceDataUrlSupport.shushanHost(source);
      const path = BookSourceDataUrlSupport.pathFromUrl(reqUrl);
      if (!path) return [];
      const root = await BookSourceDataUrlSupport.requestShushanJson(http, host, path);
      return root ? BookSourceDataUrlSupport.parseShushanBookList(root, source, host) : [];
    }
    const reqUrl = BookSourceDataUrlSupport.buildPagedUrl(url, page);
    const path = BookSourceDataUrlSupport.pathFromUrl(reqUrl);
    const host = BookSourceDataUrlSupport.hostFromUrl(reqUrl) || BookSourceDataUrlSupport.firstHostFromSource(source);
    if (!path) return [];
    const root = await EncodedSourceUrl.requestJson(http, path, 'GET', undefined, host);
    if (!root) return [];
    return BookSourceDataUrlSupport.parseBookList(root, source, host);
  }

  static async getBookInfo(http: HttpClient, source: BookSource, book: Book): Promise<Book> {
    const payload = EncodedSourceUrl.decode(book.bookUrl);
    if (payload?.type === 'shushanDetail') {
      return await BookSourceDataUrlSupport.getShushanBookInfo(http, source, book, payload);
    }
    if (payload?.type === 'mybxs') {
      return await BookSourceDataUrlSupport.getMyBxBookInfo(http, source, book, payload);
    }
    const meta = BookSourceDataUrlSupport.getMeta(book);
    if (!meta.host) meta.host = BookSourceDataUrlSupport.firstHostFromSource(source);
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
    if (myBxPayload?.type === 'shushanDetail' || myBxPayload?.type === 'shushanCatalog') {
      return await BookSourceDataUrlSupport.getShushanChapterList(http, source, book, myBxPayload);
    }
    if (myBxPayload?.type === 'mybxs') {
      return await BookSourceDataUrlSupport.getMyBxChapterList(http, source, book, myBxPayload);
    }
    const meta = BookSourceDataUrlSupport.getMeta(book);
    if (!meta.host) meta.host = BookSourceDataUrlSupport.firstHostFromSource(source);
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
    if (payload?.type === 'shushanContent') {
      return await BookSourceDataUrlSupport.getShushanContent(http, source, chapter, payload);
    }
    if (payload?.type === 'mybxc') {
      return await BookSourceDataUrlSupport.getMyBxContent(http, source, book, chapter, payload);
    }
    const info = BookSourceDataUrlSupport.getChapterInfo(chapter, source);
    const root = await EncodedSourceUrl.requestJsonForDataUrl(http, chapter.url, info['host']);
    if (!root) return '';
    const content = BookSourceDataUrlSupport.readContent(root);
    if (BookSourceDataUrlSupport.needsLogin(root, content)) {
      VerificationSupport.requestVerification(BookSourceDataUrlSupport.loginUrlForContent(info), '登录', source);
      return '';
    }
    return BookSourceDataUrlSupport.cleanContentText(content);
  }

  private static async getShushanBookInfo(http: HttpClient, source: BookSource, book: Book,
    payload: EncodedSourcePayload): Promise<Book> {
    const data = payload.data;
    const host = EncodedSourceUrl.str(data['host']) || BookSourceDataUrlSupport.shushanHost(source);
    const sourceName = EncodedSourceUrl.str(data['source']) || EncodedSourceUrl.str(data['sources']);
    const name = EncodedSourceUrl.str(data['name']);
    let rawUrl = EncodedSourceUrl.str(data['url']) || EncodedSourceUrl.str(data['toc_url']) ||
      EncodedSourceUrl.str(data['book_url']);
    const payloadBookId = EncodedSourceUrl.str(data['book_id']) || EncodedSourceUrl.str(data['bookId']);
    if (!rawUrl && BookSourceDataUrlSupport.isShushanFanqieBookId(payloadBookId)) {
      rawUrl = BookSourceDataUrlSupport.shushanFanqieDetailUrl(payloadBookId);
    }
    let root: EncodedJsonMap | null = null;
    if (sourceName && rawUrl) {
      const path = `/details?source=${encodeURIComponent(sourceName)}&url=${encodeURIComponent(rawUrl)}` +
        `&name=${encodeURIComponent(name)}`;
      root = await BookSourceDataUrlSupport.requestShushanJson(http, host, path);
    }
    const detail = root ? EncodedSourceUrl.asMap(root['data']) : {};
    book.name = EncodedSourceUrl.str(detail['title']) || EncodedSourceUrl.str(detail['book_name']) || name || book.name;
    book.author = EncodedSourceUrl.str(detail['author']) || book.author;
    book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source,
      EncodedSourceUrl.str(detail['cover']) || EncodedSourceUrl.str(detail['thumb_url'])) || book.coverUrl;
    book.intro = EncodedSourceUrl.str(detail['desc']) || EncodedSourceUrl.str(detail['abstract']) || book.intro;
    book.kind = EncodedSourceUrl.str(detail['tags']) || EncodedSourceUrl.str(detail['category']) || book.kind;
    book.latestChapterTitle = EncodedSourceUrl.str(detail['latestChapterTitle']) ||
      EncodedSourceUrl.str(detail['last_chapter_title']) || book.latestChapterTitle;
    book.wordCount = EncodedSourceUrl.str(detail['wordCount']) || EncodedSourceUrl.str(detail['word_number']) || book.wordCount;
    const finalUrl = EncodedSourceUrl.str(detail['book_url']) || rawUrl;
    const tab = EncodedSourceUrl.str(detail['tab']) || EncodedSourceUrl.str(data['tab']) || 'novel';
    const bookId = EncodedSourceUrl.str(detail['book_id']) || EncodedSourceUrl.str(detail['bookId']) || payloadBookId;
    book.tocUrl = EncodedSourceUrl.encode({
      name: book.name,
      source: sourceName,
      tab: tab,
      url: finalUrl,
      book_id: bookId,
      host: host
    }, 'shushanCatalog');
    book.origin = source.bookSourceUrl;
    book.originName = sourceName ? `${source.bookSourceName} · ${sourceName}` : source.bookSourceName;
    book.variable = JSON.stringify({ name: book.name, source: sourceName, tab: tab, url: finalUrl, book_id: bookId, host: host });
    return book;
  }

  private static async getShushanChapterList(http: HttpClient, source: BookSource, book: Book,
    payload: EncodedSourcePayload): Promise<BookChapter[]> {
    const data = payload.data;
    const host = EncodedSourceUrl.str(data['host']) || BookSourceDataUrlSupport.shushanHost(source);
    const sourceName = EncodedSourceUrl.str(data['source']) || EncodedSourceUrl.str(data['sources']);
    let rawUrl = EncodedSourceUrl.str(data['url']) || EncodedSourceUrl.str(data['toc_url']) ||
      EncodedSourceUrl.str(data['book_url']);
    const bookId = EncodedSourceUrl.str(data['book_id']) || EncodedSourceUrl.str(data['bookId']);
    if (!rawUrl && BookSourceDataUrlSupport.isShushanFanqieBookId(bookId)) {
      rawUrl = BookSourceDataUrlSupport.shushanFanqieDetailUrl(bookId);
    }
    if (!sourceName || !rawUrl) return [];
    const root = await BookSourceDataUrlSupport.requestShushanPostJson(http, host, '/catalog', {
      source: sourceName,
      url: rawUrl,
      name: EncodedSourceUrl.str(data['name']) || book.name,
      tab: EncodedSourceUrl.str(data['tab']) || 'novel'
    });
    if (!root) return [];
    if (BookSourceDataUrlSupport.needsLogin(root, JSON.stringify(root)) || EncodedSourceUrl.str(root['error']).includes('访问被拒绝')) {
      VerificationSupport.requestVerification(BookSourceDataUrlSupport.shushanLoginUrl(source, host), '书山聚合 登录', source);
      return [];
    }
    const list = EncodedSourceUrl.asArray(root['data']);
    const chapters: BookChapter[] = [];
    for (const item of list) {
      const rec = EncodedSourceUrl.asMap(item);
      const title = EncodedSourceUrl.str(rec['title']);
      if (!title || EncodedSourceUrl.str(rec['isVolume']) === 'true') continue;
      const cid = EncodedSourceUrl.str(rec['cid']);
      const itemUrl = EncodedSourceUrl.str(rec['url']);
      const chapter = new BookChapter();
      chapter.title = title;
      chapter.url = EncodedSourceUrl.encode({
        cid: cid,
        url: itemUrl,
        catalogUrl: rawUrl,
        book_id: bookId,
        source: sourceName,
        tab: EncodedSourceUrl.str(data['tab']) || 'novel',
        host: host
      }, 'shushanContent');
      chapter.bookUrl = book.bookUrl;
      chapter.index = chapters.length;
      chapter.isVip = EncodedSourceUrl.str(rec['isVip']) === 'true';
      chapters.push(chapter);
    }
    return chapters;
  }

  private static async getShushanContent(http: HttpClient, source: BookSource, chapter: BookChapter,
    payload: EncodedSourcePayload): Promise<string> {
    const data = payload.data;
    const host = EncodedSourceUrl.str(data['host']) || BookSourceDataUrlSupport.shushanHost(source);
    const sourceName = EncodedSourceUrl.str(data['source']) || EncodedSourceUrl.str(data['sources']);
    const rawUrl = EncodedSourceUrl.str(data['url']) || EncodedSourceUrl.str(data['toc_url']) ||
      EncodedSourceUrl.str(data['book_url']);
    const catalogUrl = EncodedSourceUrl.str(data['catalogUrl']) || EncodedSourceUrl.str(data['tocUrl']) ||
      EncodedSourceUrl.str(data['catalog_url']);
    const cid = EncodedSourceUrl.str(data['cid']) ||
      BookSourceDataUrlSupport.extractQueryValue(rawUrl, 'item_id') ||
      BookSourceDataUrlSupport.extractQueryValue(rawUrl, 'itemId');
    let path = rawUrl && rawUrl.startsWith('chapter?') ? `/${rawUrl}` : '';
    if (!path && cid && sourceName) {
      path = `/chapter?cid=${encodeURIComponent(cid)}&source=${encodeURIComponent(sourceName)}&device=android`;
      if (BookSourceDataUrlSupport.isShushanFanqieSource(sourceName)) {
        const bookId = BookSourceDataUrlSupport.extractQueryValue(rawUrl || catalogUrl, 'book_id') ||
          EncodedSourceUrl.str(data['book_id']) || EncodedSourceUrl.str(data['bookId']);
        const itemId = BookSourceDataUrlSupport.extractQueryValue(rawUrl, 'item_id') ||
          BookSourceDataUrlSupport.extractQueryValue(rawUrl, 'itemId') || cid;
        if (bookId) path += `&book_id=${encodeURIComponent(bookId)}`;
        if (itemId) path += `&item_id=${encodeURIComponent(itemId)}`;
        if (BookSourceDataUrlSupport.isShushanFanqieListenSource(sourceName)) {
          const toneId = EncodedSourceUrl.str(data['tone_id']) ||
            BookSourceDataUrlSupport.extractQueryValue(rawUrl, 'tone_id') ||
            BookSourceDataUrlSupport.extractQueryValue(catalogUrl, 'tone_id') || '1';
          path += `&tone_id=${encodeURIComponent(toneId)}`;
        }
      } else if (catalogUrl) {
        path += `&url=${encodeURIComponent(catalogUrl)}`;
      }
      if ((sourceName === '企鹅看书' || sourceName === 'QQ阅读') && rawUrl) {
        const bookId = BookSourceDataUrlSupport.extractQueryValue(rawUrl, 'bookid');
        const chapterId = BookSourceDataUrlSupport.extractQueryValue(rawUrl, 'chapterid');
        if (bookId && chapterId) {
          const finalBookId = sourceName === '企鹅看书' && bookId.length > 2 ? bookId.substring(2) : bookId;
          path += `&bookid=${encodeURIComponent(finalBookId)}&chapterid=${encodeURIComponent(chapterId)}`;
        }
      } else if (sourceName === '七猫' && rawUrl) {
        path += `&${rawUrl.replace(/^\?+|^&+/, '')}`;
      }
    }
    if (!path) return '';
    const secretKey = BookSourceDataUrlSupport.shushanSecretKey(source);
    if (!secretKey) {
      VerificationSupport.requestVerification(BookSourceDataUrlSupport.shushanLoginUrl(source, host), '书山聚合 登录', source);
      return '';
    }
    const root = await BookSourceDataUrlSupport.requestShushanJson(http, host,
      `${path}${path.includes('?') ? '&' : '?'}key=${encodeURIComponent(secretKey)}&l=11`);
    if (!root) return '';
    const content = EncodedSourceUrl.str(root['content']) || EncodedSourceUrl.str(EncodedSourceUrl.asMap(root['data'])['content']);
    if (BookSourceDataUrlSupport.needsLogin(root, content) || BookSourceDataUrlSupport.needsLogin(root, JSON.stringify(root))) {
      const loginText = `${content}\n${JSON.stringify(root)}`;
      if (BookSourceDataUrlSupport.isShushanFanqieSource(sourceName) &&
        BookSourceDataUrlSupport.needsFanqieWebLogin(loginText)) {
        VerificationSupport.requestVerification(BookSourceDataUrlSupport.shushanFanqieWebLoginUrl(), '番茄网页登录', source);
      } else {
        VerificationSupport.requestVerification(BookSourceDataUrlSupport.shushanLoginUrl(source, host), '书山聚合 登录', source);
      }
      return '';
    }
    const decoded = BookSourceDataUrlSupport.decodeShushanContent(content);
    if (!decoded && BookSourceDataUrlSupport.looksLikeBase64Text(content)) {
      VerificationSupport.requestVerification(BookSourceDataUrlSupport.shushanLoginUrl(source, host), '书山聚合 登录', source);
      return '';
    }
    return BookSourceDataUrlSupport.cleanContentText(decoded || content);
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

  private static sourceUsesShushan(source: BookSource): boolean {
    const raw = `${source.bookSourceUrl || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}\n` +
      `${source.jsLib || ''}\n${source.loginUrl || ''}\n${source.header || ''}`;
    return raw.includes('vossc.com') || raw.includes('SHUSAN_READ_2025');
  }

  private static shushanHost(source: BookSource): string {
    const raw = `${source.bookSourceUrl || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}\n` +
      `${source.jsLib || ''}\n${source.loginUrl || ''}\n${source.header || ''}`;
    const configHost = BookSourceDataUrlSupport.extractSourceVariableValue(source, 'host');
    if (configHost) return configHost;
    const match = raw.match(/https?:\/\/[^'"`\s,)]+vossc\.com/i);
    return match ? match[0] : 'https://v1.vossc.com';
  }

  private static shushanSelectedSource(source: BookSource): string {
    return BookSourceDataUrlSupport.extractSourceVariableValue(source, 'source');
  }

  private static parseShushanSearchKeyword(keyword: string): Record<string, string> {
    const raw = (keyword || '').trim();
    const atIndex = raw.lastIndexOf('@');
    if (atIndex <= 0 || atIndex >= raw.length - 1) {
      return { keyword: raw, source: '' };
    }
    const source = raw.substring(atIndex + 1).trim().replace(/，/g, ',');
    return {
      keyword: raw.substring(0, atIndex).trim(),
      source: source
    };
  }

  private static extractSourceVariableValue(source: BookSource, key: string): string {
    try {
      const parsed = JSON.parse(source.variableComment || '[]') as Object;
      const data = EncodedSourceUrl.asArray(parsed);
      const first = data.length > 0 ? EncodedSourceUrl.asMap(data[0]) : EncodedSourceUrl.asMap(parsed);
      return EncodedSourceUrl.str(first[key]);
    } catch (_) {
      return '';
    }
  }

  private static async requestShushanJson(http: HttpClient, host: string, path: string): Promise<EncodedJsonMap | null> {
    const isFullUrl = path.startsWith('http://') || path.startsWith('https://');
    const hosts = isFullUrl ? [''] : BookSourceDataUrlSupport.shushanHostCandidates(host);
    let deniedRoot: EncodedJsonMap | null = null;
    for (const candidate of hosts) {
      const url = isFullUrl ? path : `${candidate}${path}`;
      const resp = await http.execute({
        url: url,
        method: 'GET',
        headers: BookSourceDataUrlSupport.shushanHeaders()
      });
      const root = BookSourceDataUrlSupport.parseShushanResponse(resp);
      if (root && BookSourceDataUrlSupport.isShushanAccessDenied(root)) {
        deniedRoot = root;
        continue;
      }
      if (root && !BookSourceDataUrlSupport.isShushanAccessDenied(root)) return root;
    }
    return deniedRoot;
  }

  private static async requestShushanPostJson(http: HttpClient, host: string, path: string,
    body: Record<string, Object | string | number | boolean>): Promise<EncodedJsonMap | null> {
    let deniedRoot: EncodedJsonMap | null = null;
    for (const candidate of BookSourceDataUrlSupport.shushanHostCandidates(host)) {
      const resp = await http.execute({
        url: `${candidate}${path}`,
        method: 'POST',
        headers: {
          ...BookSourceDataUrlSupport.shushanHeaders(),
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(body)
      });
      const root = BookSourceDataUrlSupport.parseShushanResponse(resp);
      if (root && BookSourceDataUrlSupport.isShushanAccessDenied(root)) {
        deniedRoot = root;
        continue;
      }
      if (root && !BookSourceDataUrlSupport.isShushanAccessDenied(root)) return root;
    }
    return deniedRoot;
  }

  private static parseShushanResponse(resp: HttpResponse): EncodedJsonMap | null {
    if (!resp.success || !resp.body) return null;
    try {
      return EncodedSourceUrl.asMap(JSON.parse(resp.body) as Object);
    } catch (_) {
      return null;
    }
  }

  private static isShushanAccessDenied(root: EncodedJsonMap): boolean {
    return EncodedSourceUrl.str(root['error']).includes('访问被拒绝');
  }

  private static shushanHostCandidates(host: string): string[] {
    const primary = host || 'https://v1.vossc.com';
    const fixed = [
      'http://1.94.248.5:7001',
      'https://v1.vossc.com',
      'https://v2.vossc.com',
      'https://v3.vossc.com',
      'https://v4.vossc.com'
    ];
    const result: string[] = [];
    if (primary && !result.includes(primary)) result.push(primary);
    if (primary.includes('vossc.com') || primary.includes('1.94.248.5')) {
      for (const item of fixed) {
        if (!result.includes(item)) result.push(item);
      }
    }
    return result;
  }

  private static shushanHeaders(): Record<string, string> {
    return {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.7151.104 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'X-Novel-Token': 'SHUSAN_READ_2025'
    };
  }

  private static isShushanFanqieSource(sourceName: string): boolean {
    const value = (sourceName || '').trim();
    return value === '番茄小说' || value === '番茄短剧' || value === '番茄听书' || value === '番茄畅听';
  }

  private static isShushanFanqieListenSource(sourceName: string): boolean {
    const value = (sourceName || '').trim();
    return value === '番茄听书' || value === '番茄畅听';
  }

  private static extractQueryValue(url: string, key: string): string {
    if (!url || !key) return '';
    const match = url.match(new RegExp(`(?:^|[?&#])${key}=([^&#]+)`));
    if (!match || !match[1]) return '';
    try {
      return decodeURIComponent(match[1]);
    } catch (_) {
      return match[1];
    }
  }

  private static shushanLoginUrl(source: BookSource, _host: string): string {
    return VerificationSupport.buildBookSourceLoginUrl(source);
  }

  private static shushanFanqieWebLoginUrl(): string {
    return 'https://fanqienovel.com/';
  }

  private static needsFanqieWebLogin(text: string): boolean {
    const value = text || '';
    return value.includes('番茄登录') || value.includes('fanqienovel') ||
      value.includes('sessionid') || value.includes('session_id') ||
      value.includes('登录已过期') || value.includes('登录过期');
  }

  private static shushanSecretKey(source: BookSource): string {
    const apiKey = (source.loginHeader || '').trim();
    if (!apiKey) return '';
    return BookSourceDataUrlSupport.base64EncodeText(apiKey);
  }

  private static base64EncodeText(value: string): string {
    if (!value) return '';
    try {
      const base64 = new util.Base64Helper();
      const textEncoder = new util.TextEncoder();
      return base64.encodeToStringSync(textEncoder.encodeInto(value));
    } catch (_) {
      return '';
    }
  }

  private static decodeShushanContent(content: string): string {
    const value = (content || '').trim();
    if (!value) return '';
    const decoded = BookSourceDataUrlSupport.desCbcBase64Decode(value, 'K7bM2nXy', 'tQ5v9rS1');
    return decoded || BookSourceDataUrlSupport.base64DecodeUtf8(value);
  }

  private static desCbcBase64Decode(data: string, key: string, iv: string): string {
    try {
      const textEncoder = new util.TextEncoder();
      const textDecoder = util.TextDecoder.create('utf-8');
      const base64 = new util.Base64Helper();
      const dataBytes = base64.decodeSync(data);
      const keyBytes = BookSourceDataUrlSupport.fixedBytes(textEncoder.encodeInto(key), 8);
      const tripleDesKeyBytes = BookSourceDataUrlSupport.repeatBytes(keyBytes, 3);
      const ivBytes = BookSourceDataUrlSupport.fixedBytes(textEncoder.encodeInto(iv), 8);
      const ivParams: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: ivBytes }
      };
      const algorithms: Object[] = [
        { cipher: '3DES192|CBC|PKCS7', keyAlg: '3DES192', keyData: tripleDesKeyBytes },
        { cipher: '3DES192|CBC|PKCS5', keyAlg: '3DES192', keyData: tripleDesKeyBytes },
        { cipher: 'DES/CBC/PKCS5Padding', keyAlg: 'DES', keyData: keyBytes },
        { cipher: 'DES64|CBC|PKCS5', keyAlg: 'DES64', keyData: keyBytes },
        { cipher: 'DES|CBC|PKCS5', keyAlg: 'DES', keyData: keyBytes },
        { cipher: 'DES64|CBC|PKCS7', keyAlg: 'DES64', keyData: keyBytes },
        { cipher: 'DES|CBC|PKCS7', keyAlg: 'DES', keyData: keyBytes }
      ];
      for (const item of algorithms) {
        const spec = EncodedSourceUrl.asMap(item);
        const keyAlg = EncodedSourceUrl.str(spec['keyAlg']);
        const cipherAlg = EncodedSourceUrl.str(spec['cipher']);
        const keyData = (spec['keyData'] as Uint8Array) || keyBytes;
        try {
          const keyGen = cryptoFramework.createSymKeyGenerator(keyAlg);
          const symKey = keyGen.convertKeySync({ data: keyData });
          const cipher = cryptoFramework.createCipher(cipherAlg);
          cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivParams);
          const outBlob = cipher.doFinalSync({ data: dataBytes });
          const text = textDecoder.decodeWithStream(outBlob.data, { stream: false });
          if (text) return text;
        } catch (_) {
        }
      }
    } catch (e) {
      console.error('[BookSourceDataUrlSupport] 书山正文解密失败:', JSON.stringify(e));
    }
    return '';
  }

  private static base64DecodeUtf8(data: string): string {
    try {
      if (!BookSourceDataUrlSupport.looksLikeBase64Text(data)) return '';
      const textDecoder = util.TextDecoder.create('utf-8');
      const base64 = new util.Base64Helper();
      const out = textDecoder.decodeWithStream(base64.decodeSync(data), { stream: false });
      return BookSourceDataUrlSupport.looksLikeReadableContent(out) ? out : '';
    } catch (_) {
      return '';
    }
  }

  private static looksLikeBase64Text(value: string): boolean {
    const text = (value || '').trim();
    return text.length >= 16 && text.length % 4 === 0 && /^[A-Za-z0-9+/]+={0,2}$/.test(text);
  }

  private static looksLikeReadableContent(value: string): boolean {
    const text = (value || '').trim();
    if (!text) return false;
    const sample = text.substring(0, Math.min(text.length, 200));
    return /[\u4e00-\u9fa5]/.test(sample) || sample.includes('\n') || /[A-Za-z]{8,}/.test(sample);
  }

  private static fixedBytes(bytes: Uint8Array, length: number): Uint8Array {
    const out = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
      out[i] = i < bytes.length ? bytes[i] : 0;
    }
    return out;
  }

  private static repeatBytes(bytes: Uint8Array, times: number): Uint8Array {
    const out = new Uint8Array(bytes.length * times);
    for (let i = 0; i < out.length; i++) {
      out[i] = bytes[i % bytes.length];
    }
    return out;
  }

  private static getShushanPlatforms(source: BookSource): string[] {
    const raw = `${source.loginUrl || ''}\n${source.jsLib || ''}\n${source.exploreUrl || ''}`;
    const names: string[] = [];
    const re = /\bv\s*:\s*(?:"([^"]+)"|'([^']+)')\s*,\s*m\s*:\s*(?:"([^"]+)"|'([^']+)')/g;
    let match: RegExpExecArray | null;
    while ((match = re.exec(raw)) !== null) {
      const value = (match[1] || match[2] || '').trim();
      const label = (match[3] || match[4] || value).replace(/^[^\u4e00-\u9fa5A-Za-z0-9]+/, '').trim();
      const name = value || label;
      if (name && !names.includes(name)) names.push(name);
    }
    if (names.length > 0) return names;
    const fallback = ['番茄小说', '书旗', '七猫', '起点', '企鹅看书', 'QQ阅读', '69书吧', '笔趣阁', '小说', '听书', '漫画'];
    for (const item of fallback) {
      if (!names.includes(item)) names.push(item);
    }
    return names;
  }

  private static async getShushanExploreEntries(http: HttpClient, source: BookSource, platform: string,
    sourceType: string): Promise<ExploreDataUrlEntry[]> {
    const host = BookSourceDataUrlSupport.shushanHost(source);
    const selected = (platform || '').trim();
    const gender = sourceType.includes('女') ? 'girl' : 'boy';
    if (selected && !BookSourceDataUrlSupport.isShushanDefaultExplorePlatform(selected)) {
      const root = await BookSourceDataUrlSupport.requestShushanJson(http, host,
        `/type_api?source=${encodeURIComponent(selected)}&gender=${gender}`);
      const found = root ? EncodedSourceUrl.asArray(EncodedSourceUrl.asMap(root['data'])['found']) : [];
      const sourceEntries: ExploreDataUrlEntry[] = [];
      for (const item of found) {
        const rec = EncodedSourceUrl.asMap(item);
        const title = EncodedSourceUrl.str(rec['title']);
        const url = EncodedSourceUrl.str(rec['url']);
        if (!title || !url) continue;
        BookSourceDataUrlSupport.addShushanEntry(sourceEntries, title,
          `${host}/type_api?source=${encodeURIComponent(selected)}&page={{page}}&url=${encodeURIComponent(url)}` +
            `&gender=${gender}`);
      }
      if (sourceEntries.length > 0) return sourceEntries;
      return [];
    }

    const entries: ExploreDataUrlEntry[] = [];
    BookSourceDataUrlSupport.addShushanEntry(entries, '个性推荐', `${host}/read_recommend?session=`);
    BookSourceDataUrlSupport.addShushanEntry(entries, '巅峰榜单',
      `${host}/style_top?rank_list_type=3&offset={{(page-1)*10}}&limit=10&category_id=7&gender=1&rankMold=2`);
    BookSourceDataUrlSupport.addShushanEntry(entries, '出版榜单',
      `${host}/type_style?category_id=0&genre_type=0&gender=1&offset={{(page-1)*100}}&selected_items=`);

    const genderCode = sourceType.includes('女') ? '0' : '1';
    const root = await BookSourceDataUrlSupport.requestShushanJson(http, host, `/type_style?new_category_tab=${genderCode}`);
    const groups = root ? EncodedSourceUrl.asArray(root['data']) : [];
    for (const groupItem of groups) {
      const group = EncodedSourceUrl.asMap(groupItem);
      const categories = EncodedSourceUrl.asArray(group['data']);
      for (const categoryItem of categories) {
        const category = EncodedSourceUrl.asMap(categoryItem);
        const title = EncodedSourceUrl.str(category['name']);
        const id = EncodedSourceUrl.str(category['category_id']);
        if (!title || !id) continue;
        BookSourceDataUrlSupport.addShushanEntry(entries, title,
          `${host}/type_style?category_id=${encodeURIComponent(id)}&genre_type=0&gender=${genderCode}` +
            `&offset={{(page-1)*100}}&selected_items=`);
      }
    }
    return entries;
  }

  private static isShushanDefaultExplorePlatform(platform: string): boolean {
    const value = (platform || '').trim();
    return !value || value === '番茄小说' || value === '小说' || value === '听书' || value === '漫画' ||
      value === '视频' || value === '短剧' || value === '音频' || value === '聚合搜索';
  }

  private static addShushanEntry(entries: ExploreDataUrlEntry[], title: string, url: string): void {
    if (!title || !url || entries.some((entry: ExploreDataUrlEntry) => entry.title === title && entry.url === url)) {
      return;
    }
    const entry = new ExploreDataUrlEntry();
    entry.title = title;
    entry.url = url;
    entries.push(entry);
  }

  private static buildShushanPagedUrl(url: string, page: number): string {
    const js = new JsRuntime();
    js.setVar('page', String(page));
    js.setVar('pageIndex', String(page));
    let value = js.evalTemplate(url || '');
    value = value.replace(/\{\{\s*page\s*\}\}/g, String(page))
      .replace(/\{\{\s*\(page-1\)\*10\s*\}\}/g, String((page - 1) * 10))
      .replace(/\{\{\s*\(page-1\)\*100\s*\}\}/g, String((page - 1) * 100))
      .replace(/\{\{[^}]+\}\}/g, String(page));
    if (/[?&](?:page|offset)=/.test(value)) return value;
    return `${value}${value.includes('?') ? '&' : '?'}page=${page}`;
  }

  private static parseShushanBookList(root: EncodedJsonMap, source: BookSource, host: string): SearchBook[] {
    const data = BookSourceDataUrlSupport.shushanDataArray(root);
    const books: SearchBook[] = [];
    for (const item of data) {
      const rec = EncodedSourceUrl.asMap(item);
      const name = EncodedSourceUrl.str(rec['title']) || EncodedSourceUrl.str(rec['book_name']) ||
        EncodedSourceUrl.str(rec['bookName']);
      let bookUrl = EncodedSourceUrl.str(rec['book_url']) || EncodedSourceUrl.str(rec['url']) ||
        EncodedSourceUrl.str(rec['toc_url']);
      const itemSource = EncodedSourceUrl.str(rec['source']) || '番茄小说';
      const tab = EncodedSourceUrl.str(rec['tab']) || 'novel';
      const bookId = EncodedSourceUrl.str(rec['book_id']) || EncodedSourceUrl.str(rec['bookId']);
      if (!bookUrl && BookSourceDataUrlSupport.isShushanFanqieBookId(bookId)) {
        bookUrl = BookSourceDataUrlSupport.shushanFanqieDetailUrl(bookId);
      }
      if (!name || (!bookUrl && !bookId)) continue;
      const book = new SearchBook();
      book.name = name;
      book.author = EncodedSourceUrl.str(rec['author']);
      book.coverUrl = BookSourceDataUrlSupport.normalizeCoverUrl(source,
        EncodedSourceUrl.str(rec['cover']) || EncodedSourceUrl.str(rec['thumb_url']) ||
          EncodedSourceUrl.str(rec['audio_thumb_uri']));
      book.intro = EncodedSourceUrl.str(rec['desc']) || EncodedSourceUrl.str(rec['abstract']) ||
        EncodedSourceUrl.str(rec['recommend_reason']);
      book.kind = EncodedSourceUrl.str(rec['tags']) || EncodedSourceUrl.str(rec['category']);
      book.latestChapterTitle = EncodedSourceUrl.str(rec['latestChapterTitle']) ||
        EncodedSourceUrl.str(rec['last_chapter_title']);
      book.wordCount = EncodedSourceUrl.str(rec['wordCount']) || EncodedSourceUrl.str(rec['word_number']);
      book.bookUrl = BookSourceDataUrlSupport.buildShushanDetailUrl(name, itemSource, tab, bookUrl, bookId, host);
      book.tocUrl = book.bookUrl;
      book.variable = JSON.stringify({ name: name, source: itemSource, tab: tab, url: bookUrl, bookId: bookId, host: host });
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

  private static shushanDataArray(root: EncodedJsonMap): Object[] {
    const data = root['data'];
    if (Array.isArray(data)) return data as Object[];
    const dataMap = EncodedSourceUrl.asMap(data as Object);
    const candidates: Object[] = [
      dataMap['book_info'] as Object,
      dataMap['book_list'] as Object,
      dataMap['data_list'] as Object,
      dataMap['list'] as Object,
      EncodedSourceUrl.asMap(dataMap['cell_view'] as Object)['book_data'] as Object,
      root['book_info'] as Object,
      root['book_list'] as Object,
      root['list'] as Object,
      root['result'] as Object
    ];
    for (const candidate of candidates) {
      if (Array.isArray(candidate)) return candidate as Object[];
    }
    return [];
  }

  private static buildShushanDetailUrl(name: string, source: string, tab: string, url: string, bookId: string,
    host: string): string {
    let detailSource = source;
    let detailUrl = url;
    if (!detailUrl && BookSourceDataUrlSupport.isShushanFanqieBookId(bookId)) {
      detailSource = '番茄小说';
      detailUrl = BookSourceDataUrlSupport.shushanFanqieDetailUrl(bookId);
    }
    return EncodedSourceUrl.encode({
      name: name,
      source: detailSource,
      tab: tab,
      url: detailUrl,
      book_id: bookId,
      host: host
    }, 'shushanDetail');
  }

  private static isShushanFanqieBookId(bookId: string): boolean {
    return /^\d{19}$/.test(bookId || '');
  }

  private static shushanFanqieDetailUrl(bookId: string): string {
    const raw = `https://api5-normal-sinfonlineb.fqnovel.com/reading/bookapi/multi-detail/v/?aid=1967&iid=1&version_code=999&book_id=${bookId}`;
    return BookSourceDataUrlSupport.base64EncodeText(raw);
  }

  private static parseBookList(root: EncodedJsonMap, source: BookSource, fallbackHost: string = ''): SearchBook[] {
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
      const host = EncodedSourceUrl.hostFromData(rec) || fallbackHost || BookSourceDataUrlSupport.firstHostFromSource(source);
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

  private static getChapterInfo(chapter: BookChapter, source?: BookSource): Record<string, string> {
    const info: Record<string, string> = {};
    const sourceHost = source ? BookSourceDataUrlSupport.firstHostFromSource(source) : '';
    const payload = EncodedSourceUrl.decode(chapter.url);
    if (payload) {
      info['itemId'] = EncodedSourceUrl.str(payload.data['item_id']) || EncodedSourceUrl.str(payload.data['itemId']);
      info['source'] = EncodedSourceUrl.str(payload.data['source']) || EncodedSourceUrl.str(payload.data['sources']);
      info['tab'] = EncodedSourceUrl.str(payload.data['tab']) || '小说';
      info['host'] = EncodedSourceUrl.str(payload.data['host']) || sourceHost || EncodedSourceUrl.DEFAULT_HOSTS[0];
      info['tocUrl'] = EncodedSourceUrl.str(payload.data['toc_url']) || EncodedSourceUrl.str(payload.data['url']);
    }
    try {
      const raw = EncodedSourceUrl.asMap(JSON.parse(chapter.variable || '{}') as Object);
      info['itemId'] = EncodedSourceUrl.str(raw['itemId']) || EncodedSourceUrl.str(raw['item_id']) || info['itemId'];
      info['source'] = EncodedSourceUrl.str(raw['source']) || EncodedSourceUrl.str(raw['sources']) || info['source'];
      info['tab'] = EncodedSourceUrl.str(raw['tab']) || info['tab'] || '小说';
      info['host'] = EncodedSourceUrl.str(raw['host']) || info['host'] || sourceHost || EncodedSourceUrl.DEFAULT_HOSTS[0];
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
    const msg = EncodedSourceUrl.str(root['msg']) || EncodedSourceUrl.str(root['error']) ||
      EncodedSourceUrl.str(root['errorMsg']);
    const text = `${msg}\n${content}`;
    return (code === '-1' && (text.includes('登录') || text.includes('登陆') || text.includes('访问次数'))) ||
      text.includes('免登录访问次数已达上限') || text.includes('继续阅读请登录') ||
      text.includes('请登录后刷新') || text.includes('今日免登录访问次数') ||
      text.includes('请先登录') || text.includes('请先登陆') ||
      text.includes('登录信息已失效') || text.includes('账号信息异常') ||
      text.includes('请重新登录') || text.includes('请重新登陆') ||
      text.includes('访问被拒绝') || text.includes('密钥不存在') ||
      text.includes('密钥无效') || text.includes('密钥已失效') ||
      text.includes('密钥错误') || text.includes('未获取到密钥') ||
      text.includes('版本不受支持') || text.includes('请更新书源');
  }

  private static loginUrlForContent(info: Record<string, string>): string {
    return EncodedSourceUrl.getLoginUrl(info['host'] || EncodedSourceUrl.DEFAULT_HOSTS[0]);
  }

  static normalizeCoverUrl(source: BookSource, url: string, baseUrl: string = ''): string {
    const resolved = BookUrlResolver.resolve(url, baseUrl || source.bookSourceUrl);
    return BookSourceDataUrlSupport.normalizeMirroredAssetUrl(source, resolved);
  }

  static normalizeCoverUrlFromItem(source: BookSource, primaryUrl: string, itemJson: string, baseUrl: string = ''): string {
    const primary = BookSourceDataUrlSupport.normalizeCoverUrl(source, primaryUrl, baseUrl);
    const fallback = BookSourceDataUrlSupport.normalizeCoverUrl(source,
      BookSourceDataUrlSupport.pickCoverFallback(itemJson), baseUrl);
    if (fallback && (BookSourceDataUrlSupport.isBadCoverUrl(primary) ||
      BookSourceDataUrlSupport.isUnstableFanqieCover(primary))) {
      return fallback;
    }
    return primary || fallback;
  }

  static normalizeCoverUrlFromResponse(source: BookSource, responseBody: string, bookId: string,
    baseUrl: string = ''): string {
    const raw = BookSourceDataUrlSupport.pickCoverForBookId(responseBody, bookId);
    return BookSourceDataUrlSupport.normalizeCoverUrl(source, raw, baseUrl);
  }

  private static pickCoverFallback(itemJson: string): string {
    try {
      const data = EncodedSourceUrl.asMap(JSON.parse(itemJson || '{}') as Object);
      return BookSourceDataUrlSupport.pickFirstDeepString(data, BookSourceDataUrlSupport.coverCandidateKeys());
    } catch (_) {
      return '';
    }
  }

  private static pickCoverForBookId(responseBody: string, bookId: string): string {
    const id = (bookId || '').trim();
    if (!responseBody || !id) return '';
    try {
      const data = JSON.parse(responseBody) as Object;
      const matched = BookSourceDataUrlSupport.findObjectByBookId(data, id);
      if (matched) {
        return BookSourceDataUrlSupport.pickFirstDeepString(matched, BookSourceDataUrlSupport.coverCandidateKeys());
      }
    } catch (_) {}
    return '';
  }

  private static coverCandidateKeys(): string[] {
    return [
      'audio_thumb_uri',
      'audio_thumb_url_hd',
      'thumb_url',
      'detail_page_thumb_url',
      'expand_thumb_url',
      'thumb_uri',
      'cover',
      'cover_url',
      'coverUrl'
    ];
  }

  private static findObjectByBookId(data: Object, bookId: string): Object | null {
    if (!data || typeof data !== 'object') return null;
    if (Array.isArray(data)) {
      for (const item of data as Object[]) {
        const found = BookSourceDataUrlSupport.findObjectByBookId(item, bookId);
        if (found) return found;
      }
      return null;
    }
    const rec = data as Record<string, Object>;
    const id = EncodedSourceUrl.str(rec['book_id']) || EncodedSourceUrl.str(rec['bookId']) ||
      EncodedSourceUrl.str(rec['id']);
    if (id === bookId) return data;
    for (const childKey in rec) {
      const found = BookSourceDataUrlSupport.findObjectByBookId(rec[childKey] as Object, bookId);
      if (found) return found;
    }
    return null;
  }

  private static pickFirstDeepString(data: Object, keys: string[]): string {
    for (const key of keys) {
      const direct = EncodedSourceUrl.str((data as Record<string, Object>)[key]);
      if (direct) return direct;
    }
    for (const key of keys) {
      const deep = BookSourceDataUrlSupport.deepFindString(data, key);
      if (deep) return deep;
    }
    return '';
  }

  private static deepFindString(data: Object, key: string): string {
    if (!data || typeof data !== 'object') return '';
    if (Array.isArray(data)) {
      for (const item of data as Object[]) {
        const value = BookSourceDataUrlSupport.deepFindString(item, key);
        if (value) return value;
      }
      return '';
    }
    const rec = data as Record<string, Object>;
    const direct = EncodedSourceUrl.str(rec[key]);
    if (direct) return direct;
    for (const childKey in rec) {
      const value = BookSourceDataUrlSupport.deepFindString(rec[childKey] as Object, key);
      if (value) return value;
    }
    return '';
  }

  private static isBadCoverUrl(url: string): boolean {
    const value = (url || '').trim();
    if (!value) return true;
    if (value === 'thumb_url' || value === 'cover' || value === 'audio_thumb_uri') return true;
    if (value.includes('{{') || value.includes('}}') || value.includes('$..') || value.includes('$.')) return true;
    return /\/(?:thumb_url|cover|audio_thumb_uri)$/.test(value);
  }

  private static isUnstableFanqieCover(url: string): boolean {
    const value = (url || '').toLowerCase();
    return (value.includes('bytecdn.cn/') && value.includes('~tplv-shrink')) ||
      value.includes('.heic') || value.includes('reading-sign.fqnovelpic.com');
  }

  private static normalizeMirroredAssetUrl(source: BookSource, url: string): string {
    const value = CoverUrlNormalizer.normalize(url);
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
    const hostBlock = raw.match(/\bhosts?\s*=\s*\[([\s\S]*?)\]/);
    const body = hostBlock ? hostBlock[1] : raw;
    const hostMatch = body.match(/https?:\/\/[^'"`\s,)]+/);
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
    const hostBlock = raw.match(/\bhosts?\s*=\s*\[([\s\S]*?)\]/);
    const body = hostBlock ? hostBlock[1] : raw;
    const match = body.match(/https?:\/\/[^'",\]\s]+/);
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
