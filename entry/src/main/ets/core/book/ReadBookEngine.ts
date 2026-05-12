import { Book, BookChapter, BookSource } from '../../model/data/Book';
import { appDb } from '../../model/data/AppDatabase';
import { WebBookService } from './WebBookService';

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
    this.source = null;

    if (book.origin && book.origin !== 'local') {
      this.source = await appDb.getBookSource(book.origin);
      console.log('[RE] source loaded:', this.source ? this.source.bookSourceName : 'none');
    }

    this.chapters = await appDb.getBookChapters(book.bookUrl);
    console.log('[RE] cached chapters:', this.chapters.length);

    // 检查缓存章节是否有未解析的变量（旧版本残留）
    const hasBrokenUrls = this.chapters.some(c =>
      c.url.includes('@get:') || c.url.includes('{{') || c.url.includes('//')
    );

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
      this.book = await this.webBook.getBookInfo(this.source, this.book);
      console.log('[RE] getBookInfo done, tocUrl:', this.book.tocUrl);
      await appDb.updateBook(this.book);

      const chapters = await this.webBook.getChapterList(this.source, this.book);
      console.log('[RE] getChapterList done, count:', chapters.length);
      if (chapters.length > 0) {
        await appDb.deleteBookChapters(this.book.bookUrl);
        await appDb.insertBookChapters(chapters);
        this.chapters = chapters;
        this.book.totalChapterNum = chapters.length;
        this.book.latestChapterTitle = chapters[chapters.length - 1].title;
        await appDb.updateBook(this.book);
      }
    } finally {
      this.isLoading = false;
    }
  }

  async loadContent(idx: number): Promise<string> {
    if (idx < 0 || idx >= this.chapters.length || !this.book || !this.source) return '';

    const chapter = this.chapters[idx];
    this.curIdx = idx;
    if (this.chapterCache.has(idx)) return this.chapterCache.get(idx)!;

    const text = await this.webBook.getContent(this.source, this.book, chapter);
    if (text) {
      this.chapterCache.set(idx, text);
    }
    return text;
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
    this.book.durChapterIndex = this.curIdx;
    this.book.durChapterPos = this.curPos;
    this.book.durChapterTime = Date.now();
    await appDb.updateBook(this.book);
  }

  getChapterTitle(): string {
    const c = this.chapters[this.curIdx];
    return c ? c.title : '';
  }
}
