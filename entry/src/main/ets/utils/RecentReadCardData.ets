import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { Book } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { BookDisplayHelper } from './BookDisplayHelper';
import { BookCoverCache } from './BookCoverCache';
import { BookshelfSortHelper } from './BookshelfSortHelper';
import { CoverGallerySettings } from './CoverGallerySettings';
import { CoverGallerySnapshot, CoverGalleryStore } from './CoverGalleryStore';

export const RECENT_READ_FORM_NAME = 'RecentReadForm';
export const RECENT_READ_FORM_ABILITY = 'RecentReadFormAbility';
export const RECENT_READ_FORM_MODULE = 'entry';
export const RECENT_READ_DEFAULT_DIMENSION = 3;

export class RecentReadCardData {
  version: number = 0;
  orderSignature: string = '';
  dimension: number = RECENT_READ_DEFAULT_DIMENSION;
  darkMode: boolean = false;
  count: number = 0;
  updatedAt: string = '';
  emptyTitle: string = '暂无最近阅读';
  emptySubtitle: string = '打开书架阅读后会显示在这里';

  book0Name: string = '';
  book0Meta: string = '';
  book0Progress: string = '';
  book0Url: string = '';
  book0Cover: string = '';
  book0ReadTime: number = 0;
  book0Accent: string = '#007DFF';

  book1Name: string = '';
  book1Meta: string = '';
  book1Progress: string = '';
  book1Url: string = '';
  book1Cover: string = '';
  book1ReadTime: number = 0;
  book1Accent: string = '#2E7D68';

  book2Name: string = '';
  book2Meta: string = '';
  book2Progress: string = '';
  book2Url: string = '';
  book2Cover: string = '';
  book2ReadTime: number = 0;
  book2Accent: string = '#7A5AF8';
  formImages: Record<string, number> = {};
}

export class RecentReadCardDataProvider {
  static empty(
    dimension: number = RECENT_READ_DEFAULT_DIMENSION,
    darkMode: boolean = false
  ): RecentReadCardData {
    const data = new RecentReadCardData();
    data.version = Date.now();
    data.dimension = RecentReadCardDataProvider.normalizeDimension(dimension);
    data.darkMode = darkMode;
    data.updatedAt = RecentReadCardDataProvider.formatTime(data.version);
    return data;
  }

  static async load(
    context: Context,
    dimension: number = RECENT_READ_DEFAULT_DIMENSION,
    darkMode: boolean = false
  ): Promise<RecentReadCardData> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const books = BookshelfSortHelper.getRecentReadBooks(await db.getAllBooks(), 3);
    let coverSettings = new CoverGallerySnapshot();
    try {
      coverSettings = await CoverGalleryStore.load(context);
    } catch (e) {
      console.warn('加载卡片封面图集设置失败:', e);
    }
    return await RecentReadCardDataProvider.fromBooks(context, books, dimension, darkMode, coverSettings);
  }

  private static async fromBooks(
    context: Context,
    books: Book[],
    dimension: number,
    darkMode: boolean,
    coverSettings: CoverGallerySnapshot
  ): Promise<RecentReadCardData> {
    const data = RecentReadCardDataProvider.empty(dimension, darkMode);
    data.count = books.length;
    data.orderSignature = books
      .map((book: Book) => `${book.bookUrl}#${BookshelfSortHelper.getBookReadTime(book)}`)
      .join('|');
    if (books.length > 0) {
      data.emptyTitle = '';
      data.emptySubtitle = '';
      await RecentReadCardDataProvider.fillBook(context, data, 0, books[0], darkMode, coverSettings);
    }
    if (books.length > 1) {
      await RecentReadCardDataProvider.fillBook(context, data, 1, books[1], darkMode, coverSettings);
    }
    if (books.length > 2) {
      await RecentReadCardDataProvider.fillBook(context, data, 2, books[2], darkMode, coverSettings);
    }
    return data;
  }

  private static async fillBook(
    context: Context,
    data: RecentReadCardData,
    index: number,
    book: Book,
    darkMode: boolean,
    coverSettings: CoverGallerySnapshot
  ): Promise<void> {
    const name = book.name || '未命名书籍';
    const meta = RecentReadCardDataProvider.bookMeta(book);
    const progress = RecentReadCardDataProvider.progressText(book);
    const url = book.bookUrl;
    const cover = await RecentReadCardDataProvider.resolveCover(context, data, book, index, darkMode, coverSettings);
    const accent = RecentReadCardDataProvider.accentColor(index);
    const readTime = BookshelfSortHelper.getBookReadTime(book);

    if (index === 0) {
      data.book0Name = name;
      data.book0Meta = meta;
      data.book0Progress = progress;
      data.book0Url = url;
      data.book0Cover = cover;
      data.book0ReadTime = readTime;
      data.book0Accent = accent;
      return;
    }
    if (index === 1) {
      data.book1Name = name;
      data.book1Meta = meta;
      data.book1Progress = progress;
      data.book1Url = url;
      data.book1Cover = cover;
      data.book1ReadTime = readTime;
      data.book1Accent = accent;
      return;
    }
    data.book2Name = name;
    data.book2Meta = meta;
    data.book2Progress = progress;
    data.book2Url = url;
    data.book2Cover = cover;
    data.book2ReadTime = readTime;
    data.book2Accent = accent;
  }

  private static async resolveCover(
    context: Context,
    data: RecentReadCardData,
    book: Book,
    index: number,
    darkMode: boolean,
    coverSettings: CoverGallerySnapshot
  ): Promise<string> {
    const covers = CoverGallerySettings.getDisplayCoverList(
      book,
      darkMode,
      coverSettings.albumsRaw,
      coverSettings.lightAlbumId,
      coverSettings.darkAlbumId,
      coverSettings.applyScope,
      coverSettings.targetBooksRaw,
      coverSettings.ignoreSourceCover,
      coverSettings.coverMode
    );
    const raw = covers.length > 0 ? BookDisplayHelper.pickCover(covers) : '';
    if (!raw) {
      return '';
    }
    try {
      const coverPath = await BookCoverCache.prepareCoverFile(context, raw);
      if (coverPath) {
        const imageKey = RecentReadCardDataProvider.coverImageKey(index, data.version);
        const file = fs.openSync(coverPath, fs.OpenMode.READ_ONLY);
        data.formImages[imageKey] = file.fd;
        return `memory://${imageKey}`;
      }
      return await BookCoverCache.resolveCover(context, raw);
    } catch (e) {
      console.warn('解析最近阅读卡片封面失败:', e);
      return raw;
    }
  }

  private static bookMeta(book: Book): string {
    const author = book.author || '作者未知';
    const tags = BookDisplayHelper.getBookTags(book);
    if (tags.length > 0) {
      return `${author} · ${tags[0]}`;
    }
    if (book.originName) {
      return `${author} · ${book.originName}`;
    }
    return author;
  }

  private static progressText(book: Book): string {
    if (book.durChapterTitle) {
      return book.durChapterTitle;
    }
    if (book.totalChapterNum > 0) {
      return `第${Math.max(1, book.durChapterIndex + 1)}/${book.totalChapterNum}章`;
    }
    if (BookshelfSortHelper.getBookReadTime(book) <= 0) {
      return '未读';
    }
    return '继续阅读';
  }

  private static accentColor(index: number): string {
    const colors = ['#007DFF', '#2E7D68', '#7A5AF8'];
    return colors[index % colors.length];
  }

  private static coverImageKey(index: number, version: number): string {
    return `book${index}Cover${version}`;
  }

  private static normalizeDimension(dimension: number): number {
    return dimension > 0 ? dimension : RECENT_READ_DEFAULT_DIMENSION;
  }

  private static formatTime(time: number): string {
    const date = new Date(time);
    const hour = RecentReadCardDataProvider.pad2(date.getHours());
    const minute = RecentReadCardDataProvider.pad2(date.getMinutes());
    const second = RecentReadCardDataProvider.pad2(date.getSeconds());
    return `${hour}:${minute}:${second}`;
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
