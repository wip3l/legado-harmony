import { Book } from '../model/data/Book';

export class BookshelfSortHelper {
  static sortByRecentRead(books: Book[]): Book[] {
    return [...books].sort((a: Book, b: Book) => BookshelfSortHelper.compareRecentRead(a, b));
  }

  static getRecentReadBooks(books: Book[], count: number): Book[] {
    return BookshelfSortHelper.sortByRecentRead(books).slice(0, Math.max(0, count));
  }

  static compareRecentRead(a: Book, b: Book): number {
    const readDiff = BookshelfSortHelper.getBookReadTime(b) - BookshelfSortHelper.getBookReadTime(a);
    if (readDiff !== 0) {
      return readDiff;
    }
    return BookshelfSortHelper.getBookAddTime(b) - BookshelfSortHelper.getBookAddTime(a);
  }

  static getBookAddTime(book: Book): number {
    return book.latestChapterTime || book.lastCheckTime || book.durChapterTime || 0;
  }

  static getBookReadTime(book: Book): number {
    const lastReadTime = BookshelfSortHelper.parseBookTime(book.getVariable('lastReadTime'));
    if (lastReadTime > 0) {
      return lastReadTime;
    }
    if (!book.durChapterTitle && book.durChapterIndex <= 0 && book.durChapterPos <= 0) {
      return 0;
    }
    return book.durChapterTime || 0;
  }

  static parseBookTime(value: string): number {
    const time = Number(value);
    return time > 0 ? time : 0;
  }
}
