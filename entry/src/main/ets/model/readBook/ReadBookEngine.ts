import { Book, BookChapter, BookSource } from '../data/Book';
import { appDb } from '../data/AppDatabase';
import { httpHelper } from '../http/HttpHelper';
import { AnalyzeRule, AnalyzeUrl } from '../analyzeRule/AnalyzeRule';
import { webBook } from '../webBook/WebBook';

export class ReadBookEngine {
  private static instance: ReadBookEngine | null = null;
  
  book: Book | null = null;
  bookSource: BookSource | null = null;
  chapters: BookChapter[] = [];
  currentChapterIndex: number = 0;
  currentChapterPos: number = 0;
  isLoading: boolean = false;
  isLocalBook: boolean = false;
  
  private contentCache: Map<string, string> = new Map();
  private chapterCache: Map<number, string> = new Map();

  private constructor() {}

  static getInstance(): ReadBookEngine {
    if (!ReadBookEngine.instance) {
      ReadBookEngine.instance = new ReadBookEngine();
    }
    return ReadBookEngine.instance;
  }

  async openBook(book: Book): Promise<void> {
    this.book = book;
    this.currentChapterIndex = book.durChapterIndex;
    this.currentChapterPos = book.durChapterPos;
    this.isLocalBook = book.origin === 'local';
    this.chapterCache.clear();
    this.contentCache.clear();
    
    // 加载书源
    if (!this.isLocalBook && book.origin) {
      this.bookSource = await appDb.getBookSource(book.origin);
    }
    
    // 加载章节列表
    await this.loadChapters();
  }

  async loadChapters(): Promise<void> {
    if (!this.book) return;
    
    this.isLoading = true;
    
    try {
      // 从数据库加载章节
      this.chapters = await appDb.getBookChapters(this.book.bookUrl);
      
      // 如果没有章节，尝试获取
      if (this.chapters.length === 0 && !this.isLocalBook && this.bookSource) {
        await this.fetchChapters();
      }
      
      // 如果是本地书，解析本地文件
      if (this.isLocalBook && this.chapters.length === 0) {
        await this.parseLocalBook();
      }
    } finally {
      this.isLoading = false;
    }
  }

  private async fetchChapters(): Promise<void> {
    if (!this.book || !this.bookSource) return;
    
    try {
      console.log('[ReadBook] 开始获取章节, bookUrl:', this.book.bookUrl, 'tocUrl:', this.book.tocUrl, 'origin:', this.book.origin);

      // 始终先获取书籍详情，确保 tocUrl 正确
      console.log('[ReadBook] 先获取书籍详情以提取正确的 tocUrl');
      this.book = await webBook.getBookInfo(this.bookSource, this.book);
      console.log('[ReadBook] getBookInfo完成, name:', this.book.name, 'tocUrl:', this.book.tocUrl, 'variable:', this.book.variable.substring(0, 100));
      await appDb.updateBook(this.book);

      console.log('[ReadBook] 开始获取章节目录, tocUrl:', this.book.tocUrl);
      const chapterList = await webBook.getChapterList(this.bookSource, this.book);
      console.log('[ReadBook] 获取到章节数量:', chapterList.length);
      
      if (chapterList.length > 0) {
        console.log('[ReadBook] 第一条章节:', chapterList[0].title, chapterList[0].url);
        await appDb.deleteBookChapters(this.book.bookUrl);
        await appDb.insertBookChapters(chapterList);
        this.chapters = chapterList;
        this.book.totalChapterNum = chapterList.length;
        this.book.latestChapterTitle = chapterList[chapterList.length - 1].title || this.book.latestChapterTitle;
        await appDb.updateBook(this.book);
        console.log('[ReadBook] 章节保存完成');
      } else {
        console.warn('[ReadBook] 章节目录为空! bookUrl:', this.book.bookUrl, 'tocUrl:', this.book.tocUrl);
      }
    } catch (e) {
      console.error('[ReadBook] 获取章节失败:', e);
    }
  }

  private async parseLocalBook(): Promise<void> {
    if (!this.book) return;
    
    // 这里需要实现本地书籍解析
    // 暂时使用简化实现
  }

  async getContent(chapterIndex: number): Promise<string> {
    if (chapterIndex < 0 || chapterIndex >= this.chapters.length) {
      return '';
    }
    
    const chapter = this.chapters[chapterIndex];
    
    // 检查缓存
    if (this.chapterCache.has(chapterIndex)) {
      return this.chapterCache.get(chapterIndex)!;
    }
    
    // 检查本地缓存
    const cached = await this.getFromCache(chapterIndex);
    if (cached) {
      this.chapterCache.set(chapterIndex, cached);
      return cached;
    }
    
    // 获取内容
    let content = '';
    
    if (this.isLocalBook) {
      content = await this.getLocalContent(chapter);
    } else {
      content = await this.getRemoteContent(chapter);
    }
    
    // 处理内容
    content = this.processContent(content);
    
    // 缓存内容
    this.chapterCache.set(chapterIndex, content);
    await this.saveToCache(chapterIndex, content);
    
    return content;
  }

  private async getLocalContent(chapter: BookChapter): Promise<string> {
    // 这里需要实现本地内容读取
    // 暂时返回空字符串
    return '';
  }

  private async getRemoteContent(chapter: BookChapter): Promise<string> {
    if (!this.bookSource) return '';
    
    try {
      return await webBook.getContent(this.bookSource, this.book!, chapter);
    } catch (e) {
      console.error('获取内容失败:', e);
      return '';
    }
  }

  private processContent(content: string): string {
    if (!content) return '';
    
    // 应用替换规则
    // 这里需要实现替换规则逻辑
    
    // 清理HTML标签
    content = content.replace(/<br\s*\/?>/gi, '\n');
    content = content.replace(/<\/p>/gi, '\n\n');
    content = content.replace(/<[^>]+>/g, '');
    
    // 清理多余空白
    content = content.replace(/\n\s*\n\s*\n/g, '\n\n');
    content = content.trim();
    
    return content;
  }

  private async getFromCache(chapterIndex: number): Promise<string | null> {
    if (!this.book) return null;
    
    // 检查数据库缓存
    // 这里需要实现缓存读取逻辑
    return null;
  }

  private async saveToCache(chapterIndex: number, content: string): Promise<void> {
    if (!this.book) return;
    
    // 保存到数据库缓存
    // 这里需要实现缓存保存逻辑
  }

  async moveToNextPage(): Promise<boolean> {
    // 这里需要实现翻页逻辑
    // 暂时返回false
    return false;
  }

  async moveToPrevPage(): Promise<boolean> {
    // 这里需要实现翻页逻辑
    // 暂时返回false
    return false;
  }

  async moveToNextChapter(): Promise<boolean> {
    if (this.currentChapterIndex < this.chapters.length - 1) {
      this.currentChapterIndex++;
      this.currentChapterPos = 0;
      await this.saveProgress();
      return true;
    }
    return false;
  }

  async moveToPrevChapter(): Promise<boolean> {
    if (this.currentChapterIndex > 0) {
      this.currentChapterIndex--;
      this.currentChapterPos = 0;
      await this.saveProgress();
      return true;
    }
    return false;
  }

  async saveProgress(): Promise<void> {
    if (!this.book) return;
    
    this.book.durChapterIndex = this.currentChapterIndex;
    this.book.durChapterPos = this.currentChapterPos;
    this.book.durChapterTime = Date.now();
    
    await appDb.updateBook(this.book);
  }

  getCurrentChapter(): BookChapter | null {
    if (this.chapters.length === 0) return null;
    return this.chapters[this.currentChapterIndex] || null;
  }

  getChapterCount(): number {
    return this.chapters.length;
  }

  getCurrentChapterTitle(): string {
    const chapter = this.getCurrentChapter();
    return chapter ? chapter.title : '';
  }

  getProgress(): number {
    if (this.chapters.length === 0) return 0;
    return this.currentChapterIndex / this.chapters.length;
  }

  async searchContent(keyword: string): Promise<number[]> {
    // 这里需要实现正文搜索逻辑
    // 暂时返回空数组
    return [];
  }

  async clearCache(): Promise<void> {
    this.contentCache.clear();
    this.chapterCache.clear();
  }

  async preloadNextChapter(): Promise<void> {
    const nextIndex = this.currentChapterIndex + 1;
    if (nextIndex < this.chapters.length && !this.chapterCache.has(nextIndex)) {
      // 预加载下一章
      await this.getContent(nextIndex);
    }
  }

  async preloadPrevChapter(): Promise<void> {
    const prevIndex = this.currentChapterIndex - 1;
    if (prevIndex >= 0 && !this.chapterCache.has(prevIndex)) {
      // 预加载上一章
      await this.getContent(prevIndex);
    }
  }
}

export const readBookEngine = ReadBookEngine.getInstance();
