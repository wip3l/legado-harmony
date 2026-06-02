import { Context } from '@kit.AbilityKit';
import { Book } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';

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
  book0Url: string = '';
  book1Name: string = '';
  book1Author: string = '';
  book1Progress: string = '';
  book1Url: string = '';
  book2Name: string = '';
  book2Author: string = '';
  book2Progress: string = '';
  book2Url: string = '';
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
    return RecentReadCardDataProvider.fromBooks(books.slice(0, 3), dimension, darkMode);
  }

  private static fromBooks(books: Book[], dimension: number, darkMode: boolean): RecentReadCardData {
    const data = new RecentReadCardData();
    data.dimension = dimension;
    data.darkMode = darkMode;
    data.count = books.length;
    data.emptyText = books.length > 0 ? '' : '暂无最近阅读';
    data.updatedAt = RecentReadCardDataProvider.formatTime(Date.now());

    if (books.length > 0) {
      RecentReadCardDataProvider.fillBook(data, 0, books[0]);
    }
    if (books.length > 1) {
      RecentReadCardDataProvider.fillBook(data, 1, books[1]);
    }
    if (books.length > 2) {
      RecentReadCardDataProvider.fillBook(data, 2, books[2]);
    }
    return data;
  }

  private static fillBook(data: RecentReadCardData, index: number, book: Book): void {
    const progress = RecentReadCardDataProvider.progressText(book);
    if (index === 0) {
      data.book0Name = book.name || '未命名书籍';
      data.book0Author = book.author || '作者未知';
      data.book0Progress = progress;
      data.book0Url = book.bookUrl;
      return;
    }
    if (index === 1) {
      data.book1Name = book.name || '未命名书籍';
      data.book1Author = book.author || '作者未知';
      data.book1Progress = progress;
      data.book1Url = book.bookUrl;
      return;
    }
    data.book2Name = book.name || '未命名书籍';
    data.book2Author = book.author || '作者未知';
    data.book2Progress = progress;
    data.book2Url = book.bookUrl;
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
