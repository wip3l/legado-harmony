import { Book, BookChapter, BookSource } from '../../model/data/Book';
import { appDb } from '../../model/data/AppDatabase';
import { WebBookService } from './WebBookService';
import { CoverUrlNormalizer } from '../../utils/CoverUrlNormalizer';

export class ReadBookEngine {
  private static inst: ReadBookEngine | null = null;
  private webBook: WebBookService;

  book: Book | null = null;
  source: BookSource | null = null;
  chapters: BookChapter[] = [];
  curIdx: number = 0;
  curPos: number = 0;
  content: string = '';
  isLoading: boolean = false;

  private chapterCache: Map<number, string> = new Map();
  private chapterLoading: Map<number, Promise<string>> = new Map();

  private constructor() { this.webBook = new WebBookService(); }

  static get(): ReadBookEngine {
    if (!ReadBookEngine.inst) ReadBookEngine.inst = new ReadBookEngine();
    return ReadBookEngine.inst;
  }

  async openBook(book: Book): Promise<void> {
    console.log('[RE] openBook:', book.name, 'origin:', book.origin);
    this.book = book;
    this.curIdx = book.durChapterIndex;
    this.curPos = book.durChapterPos;
    this.content = '';
    this.chapterCache.clear();
    this.chapterLoading.clear();
    this.source = null;

    if (book.origin && book.origin !== 'local') {
      this.source = await appDb.getBookSource(book.origin);
      console.log('[RE] source loaded:', this.source ? this.source.bookSourceName : 'none');
    }

    this.chapters = await appDb.getBookChapters(book.bookUrl);
    console.log('[RE] cached chapters:', this.chapters.length);

    // 检查缓存章节是否有未解析的变量（旧版本残留）
    const hasBrokenUrls = this.chapters.some(c => this.isBrokenChapterUrl(c.url));

    if (hasBrokenUrls || (this.chapters.length === 0 && this.source && book.origin !== 'local')) {
      if (hasBrokenUrls) {
        console.log('[RE] 检测到过期缓存，清除并重新获取');
        await appDb.deleteBookChapters(book.bookUrl);
        this.chapters = [];
      }
      console.log('[RE] no valid chapters, refreshing toc...');
      await this.refreshToc();
    }
  }

  async refreshToc(): Promise<void> {
    if (!this.book || !this.source) return;
    console.log('[RE] refreshToc start');
    this.isLoading = true;
    try {
      const oldBook = this.book;
      const oldTocUrl = oldBook.tocUrl;
      const oldLatestChapter = oldBook.latestChapterTitle;
      const oldCoverUrl = oldBook.coverUrl;
      const infoBook = await this.webBook.getBookInfo(this.source, this.book);
      this.book = infoBook;
      this.book.coverUrl = CoverUrlNormalizer.prefer(oldCoverUrl, this.book.coverUrl);
      this.preserveReadingState(this.book, oldBook);
      console.log('[RE] getBookInfo done, tocUrl:', this.book.tocUrl);
      if (!this.book.tocUrl && oldTocUrl) {
        this.book.tocUrl = oldTocUrl;
      }

      const chapters = await this.webBook.getChapterList(this.source, this.book);
      console.log('[RE] getChapterList done, count:', chapters.length);
      if (chapters.length > 0) {
        await appDb.updateBook(this.book);
        await appDb.deleteBookChapters(this.book.bookUrl);
        await appDb.insertBookChapters(chapters);
        this.chapters = chapters;
        this.chapterCache.clear();
        this.chapterLoading.clear();
        await this.syncChapterCacheDates();
        this.book.totalChapterNum = chapters.length;
        this.book.latestChapterTitle = chapters[chapters.length - 1].title;
        await appDb.updateBook(this.book);
      } else {
        this.book.latestChapterTitle = this.book.latestChapterTitle || oldLatestChapter;
        this.book.tocUrl = this.book.tocUrl || oldTocUrl;
        console.warn('[RE] refreshToc returned no chapters, keep existing chapters:', this.chapters.length);
      }
    } finally {
      this.isLoading = false;
    }
  }

  private preserveReadingState(target: Book, source: Book): void {
    target.bookUrl = source.bookUrl;
    target.origin = target.origin || source.origin;
    target.originName = target.originName || source.originName;
    target.group = source.group;
    target.order = source.order;
    target.originOrder = source.originOrder;
    target.durChapterIndex = source.durChapterIndex;
    target.durChapterPos = source.durChapterPos;
    target.durChapterTitle = source.durChapterTitle;
    target.durChapterTime = source.durChapterTime;
    target.readConfig = source.readConfig;
    target.syncTime = source.syncTime;
    this.preserveVariableTime(target, source, 'lastReadTime');
  }

  private preserveVariableTime(target: Book, source: Book, key: string): void {
    const sourceTime = this.parsePositiveTime(source.getVariable(key));
    const targetTime = this.parsePositiveTime(target.getVariable(key));
    if (sourceTime > targetTime) {
      target.putVariable(key, `${sourceTime}`);
    }
  }

  private parsePositiveTime(value: string): number {
    const time = Number(value);
    return time > 0 ? time : 0;
  }

  private isBrokenChapterUrl(url: string): boolean {
    if (!url) return true;
    if (url.includes('@get:') || url.includes('{{')) return true;
    if (url.includes('@js:') || url.includes('java.')) return true;
    if (url.startsWith('data:')) return false;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return true;
    return /https?:\/\/[^/]+\/{2,}/.test(url);
  }

  async loadContent(idx: number): Promise<string> {
    if (idx < 0 || idx >= this.chapters.length || !this.book) return '';

    this.curIdx = idx;
    return await this.fetchContent(idx);
  }

  async peekContent(idx: number): Promise<string> {
    if (idx < 0 || idx >= this.chapters.length || !this.book) return '';

    return await this.fetchContent(idx);
  }

  getCachedContent(idx: number): string {
    if (idx < 0 || idx >= this.chapters.length) return '';

    return this.chapterCache.get(idx) || '';
  }

  async reloadContent(idx: number): Promise<string> {
    if (idx < 0 || idx >= this.chapters.length || !this.book) return '';

    this.curIdx = idx;
    this.chapterCache.delete(idx);
    this.chapterLoading.delete(idx);
    await appDb.deleteCachedChapterContent(this.book.bookUrl, idx);
    const chapter = this.chapters[idx];
    if (chapter) {
      chapter.cacheDate = 0;
    }
    return await this.fetchContent(idx);
  }

  private async fetchContent(idx: number): Promise<string> {
    if (idx < 0 || idx >= this.chapters.length || !this.book) return '';

    const chapter = this.chapters[idx];
    if (this.chapterCache.has(idx)) return this.chapterCache.get(idx)!;
    if (this.chapterLoading.has(idx)) return await this.chapterLoading.get(idx)!;

    const cached = await appDb.getCachedChapterContent(this.book.bookUrl, idx);
    if (cached && !this.isInvalidChapterContent(cached)) {
      this.chapterCache.set(idx, cached);
      chapter.cacheDate = chapter.cacheDate || Date.now();
      return cached;
    }

    if (!this.source) {
      return '';
    }

    await this.refreshSourceForContent();
    const task = this.webBook.getContent(this.source, this.book, chapter)
      .then((text: string) => {
        if (text) {
          if (!this.isInvalidChapterContent(text)) {
            this.chapterCache.set(idx, text);
            chapter.cacheDate = Date.now();
            appDb.saveCachedChapterContent(this.book!.bookUrl, chapter, text).catch((err: Error) => {
              console.error('[RE] save chapter cache failed:', idx, err);
            });
          }
        }
        return text;
      })
      .finally(() => {
        this.chapterLoading.delete(idx);
      });
    this.chapterLoading.set(idx, task);
    return await task;
  }

  private async refreshSourceForContent(): Promise<void> {
    if (!this.book || !this.source || !this.book.origin || this.book.origin === 'local') {
      return;
    }
    const latestSource = await appDb.getBookSource(this.book.origin);
    if (latestSource) {
      this.source = latestSource;
    }
  }

  hasCachedContent(idx: number): boolean {
    return this.chapterCache.has(idx);
  }

  private isInvalidChapterContent(text: string): boolean {
    if (!text) return false;
    return text.includes('免登录访问次数已达上限') || text.includes('继续阅读请登录') ||
      text.includes('请登录后刷新') || text.includes('今日免登录访问次数') ||
      text.includes('当前书源需要登录') || text.includes('该书源需要先完成网页验证') ||
      text.includes('登录信息已失效') || text.includes('账号信息异常') ||
      text.includes('请重新登录') || text.includes('请重新登陆') ||
      text.includes('访问速度过快') || text.includes('普通用户限制') ||
      text.includes('升级VIP可享受不限速访问');
  }

  async cacheChapter(idx: number): Promise<boolean> {
    const text = await this.fetchContent(idx);
    return !!text;
  }

  async syncChapterCacheDates(): Promise<void> {
    if (!this.book || this.chapters.length === 0) {
      return;
    }
    const cacheDates = await appDb.getBookChapterCacheDateMap(this.book.bookUrl);
    for (const chapter of this.chapters) {
      chapter.cacheDate = cacheDates.get(chapter.index) || 0;
    }
  }

  preloadAround(idx: number, forwardCount: number = 2, backwardCount: number = 1): void {
    if (this.chapters.length === 0 || !this.book || !this.source) {
      return;
    }
    for (let offset = 1; offset <= forwardCount; offset++) {
      this.preloadContent(idx + offset);
    }
    for (let offset = 1; offset <= backwardCount; offset++) {
      this.preloadContent(idx - offset);
    }
  }

  private preloadContent(idx: number): void {
    if (idx < 0 || idx >= this.chapters.length) {
      return;
    }
    if (this.chapterCache.has(idx) || this.chapterLoading.has(idx)) {
      return;
    }
    this.fetchContent(idx).catch((err: Error) => {
      console.error('[RE] preload chapter failed:', idx, err);
    });
  }

  async loadNextChapter(): Promise<string> {
    if (this.curIdx < this.chapters.length - 1) {
      this.curIdx++;
      return this.loadContent(this.curIdx);
    }
    return '';
  }

  async loadPrevChapter(): Promise<string> {
    if (this.curIdx > 0) {
      this.curIdx--;
      return this.loadContent(this.curIdx);
    }
    return '';
  }

  async saveProgress(): Promise<void> {
    if (!this.book) return;
    const now = Date.now();
    this.book.durChapterIndex = this.curIdx;
    this.book.durChapterPos = this.curPos;
    this.book.durChapterTime = now;
    this.book.putVariable('lastReadTime', `${now}`);
    await appDb.updateBook(this.book);
  }

  getChapterTitle(): string {
    const c = this.chapters[this.curIdx];
    return c ? c.title : '';
  }
}
