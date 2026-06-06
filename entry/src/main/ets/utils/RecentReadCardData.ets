import { Context } from '@kit.AbilityKit';
import { Book } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { CoverGallerySettings } from './CoverGallerySettings';
import { CoverGalleryStore, CoverGallerySnapshot } from './CoverGalleryStore';
import { BookDisplayHelper } from './BookDisplayHelper';

export const RECENT_READ_FORM_NAME = 'RecentReadForm';
export const RECENT_READ_FORM_ABILITY = 'RecentReadFormAbility';

export class RecentReadCardData {
  dimension: number = 2;
  darkMode: boolean = false;
  count: number = 0;
  emptyText: string = '暂无最近阅读';
  updatedAt: string = '';
  book0Name: string = '';
  book0Author: string = '';
  book0Progress: string = '';
  book0Tag0: string = '';
  book0Tag1: string = '';
  book0Url: string = '';
  book0Cover0: string = '';
  book0Cover1: string = '';
  book0Cover2: string = '';
  book0Cover0Raw: string = '';
  book0Cover1Raw: string = '';
  book0Cover2Raw: string = '';
  book1Name: string = '';
  book1Author: string = '';
  book1Progress: string = '';
  book1Tag0: string = '';
  book1Tag1: string = '';
  book1Url: string = '';
  book1Cover0: string = '';
  book1Cover1: string = '';
  book1Cover2: string = '';
  book1Cover0Raw: string = '';
  book1Cover1Raw: string = '';
  book1Cover2Raw: string = '';
  book2Name: string = '';
  book2Author: string = '';
  book2Progress: string = '';
  book2Tag0: string = '';
  book2Tag1: string = '';
  book2Url: string = '';
  book2Cover0: string = '';
  book2Cover1: string = '';
  book2Cover2: string = '';
  book2Cover0Raw: string = '';
  book2Cover1Raw: string = '';
  book2Cover2Raw: string = '';
  formImages: Record<string, number> = {};
}

export class RecentReadCardDataProvider {
  static empty(dimension: number = 3, darkMode: boolean = false): RecentReadCardData {
    const data = new RecentReadCardData();
    data.dimension = dimension;
    data.darkMode = darkMode;
    data.updatedAt = RecentReadCardDataProvider.formatTime(Date.now());
    return data;
  }

  static async load(context: Context, dimension: number = 3, darkMode: boolean = false): Promise<RecentReadCardData> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const books = await db.getAllBooks();
    let coverSettings = new CoverGallerySnapshot();
    try {
      coverSettings = await CoverGalleryStore.load(context);
    } catch (e) {
      console.warn('加载卡片封面图集设置失败:', e);
    }
    return RecentReadCardDataProvider.fromBooks(books.slice(0, 3), dimension, darkMode, coverSettings);
  }

  private static fromBooks(books: Book[], dimension: number, darkMode: boolean, coverSettings: CoverGallerySnapshot): RecentReadCardData {
    const data = new RecentReadCardData();
    data.dimension = dimension;
    data.darkMode = darkMode;
    data.count = books.length;
    data.emptyText = books.length > 0 ? '' : '暂无最近阅读';
    data.updatedAt = RecentReadCardDataProvider.formatTime(Date.now());

    if (books.length > 0) {
      RecentReadCardDataProvider.fillBook(data, 0, books[0], darkMode, coverSettings);
    }
    if (books.length > 1) {
      RecentReadCardDataProvider.fillBook(data, 1, books[1], darkMode, coverSettings);
    }
    if (books.length > 2) {
      RecentReadCardDataProvider.fillBook(data, 2, books[2], darkMode, coverSettings);
    }
    return data;
  }

  private static fillBook(data: RecentReadCardData, index: number, book: Book, darkMode: boolean, coverSettings: CoverGallerySnapshot): void {
    const progress = RecentReadCardDataProvider.progressText(book);
    const tags = RecentReadCardDataProvider.bookTags(book);
    const covers = RecentReadCardDataProvider.getCoverList(book, darkMode, coverSettings);
    if (index === 0) {
      data.book0Name = book.name || '未命名书籍';
      data.book0Author = book.author || '作者未知';
      data.book0Progress = progress;
      data.book0Tag0 = tags.length > 0 ? tags[0] : '';
      data.book0Tag1 = tags.length > 1 ? tags[1] : '';
      data.book0Url = book.bookUrl;
      RecentReadCardDataProvider.fillCovers(data, 0, covers);
      return;
    }
    if (index === 1) {
      data.book1Name = book.name || '未命名书籍';
      data.book1Author = book.author || '作者未知';
      data.book1Progress = progress;
      data.book1Tag0 = tags.length > 0 ? tags[0] : '';
      data.book1Tag1 = tags.length > 1 ? tags[1] : '';
      data.book1Url = book.bookUrl;
      RecentReadCardDataProvider.fillCovers(data, 1, covers);
      return;
    }
    data.book2Name = book.name || '未命名书籍';
    data.book2Author = book.author || '作者未知';
    data.book2Progress = progress;
    data.book2Tag0 = tags.length > 0 ? tags[0] : '';
    data.book2Tag1 = tags.length > 1 ? tags[1] : '';
    data.book2Url = book.bookUrl;
    RecentReadCardDataProvider.fillCovers(data, 2, covers);
  }

  private static fillCovers(data: RecentReadCardData, index: number, covers: string[]): void {
    const cover0 = covers.length > 0 ? covers[0] : '';
    const cover1 = covers.length > 1 ? covers[1] : '';
    const cover2 = covers.length > 2 ? covers[2] : '';
    if (index === 0) {
      data.book0Cover0 = RecentReadCardDataProvider.memoryCover(index, 0, cover0);
      data.book0Cover1 = RecentReadCardDataProvider.memoryCover(index, 1, cover1);
      data.book0Cover2 = RecentReadCardDataProvider.memoryCover(index, 2, cover2);
      data.book0Cover0Raw = cover0;
      data.book0Cover1Raw = cover1;
      data.book0Cover2Raw = cover2;
      return;
    }
    if (index === 1) {
      data.book1Cover0 = RecentReadCardDataProvider.memoryCover(index, 0, cover0);
      data.book1Cover1 = RecentReadCardDataProvider.memoryCover(index, 1, cover1);
      data.book1Cover2 = RecentReadCardDataProvider.memoryCover(index, 2, cover2);
      data.book1Cover0Raw = cover0;
      data.book1Cover1Raw = cover1;
      data.book1Cover2Raw = cover2;
      return;
    }
    data.book2Cover0 = RecentReadCardDataProvider.memoryCover(index, 0, cover0);
    data.book2Cover1 = RecentReadCardDataProvider.memoryCover(index, 1, cover1);
    data.book2Cover2 = RecentReadCardDataProvider.memoryCover(index, 2, cover2);
    data.book2Cover0Raw = cover0;
    data.book2Cover1Raw = cover1;
    data.book2Cover2Raw = cover2;
  }

  private static memoryCover(bookIndex: number, coverIndex: number, raw: string): string {
    return raw ? `memory://book${bookIndex}Cover${coverIndex}` : '';
  }

  private static getCoverList(book: Book, darkMode: boolean, coverSettings: CoverGallerySnapshot): string[] {
    return CoverGallerySettings.getDisplayCoverList(
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
  }

  private static progressText(book: Book): string {
    if (book.durChapterTitle) {
      return book.durChapterTitle;
    }
    if (book.totalChapterNum > 0) {
      return `第${book.durChapterIndex + 1}/${book.totalChapterNum}章`;
    }
    return '继续阅读';
  }

  private static bookTags(book: Book): string[] {
    const tags = BookDisplayHelper.getBookTags(book);
    return tags.slice(0, 2);
  }

  private static formatTime(time: number): string {
    const date = new Date(time);
    const hour = RecentReadCardDataProvider.pad2(date.getHours());
    const minute = RecentReadCardDataProvider.pad2(date.getMinutes());
    return `${hour}:${minute}`;
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
