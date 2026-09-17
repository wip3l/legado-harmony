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

  /**
   * Add-to-shelf timestamp. This must never fall back to a reading timestamp:
   * durChapterTime is rewritten on every page turn, so using it here made "新加入"
   * and the recent-read tie-breaker silently degrade into a second read-time sort.
   */
  static getBookAddTime(book: Book): number {
    return book.shelfModifiedTime || book.latestChapterTime || book.lastCheckTime || 0;
  }

  /**
   * Last-read timestamp used as the "新阅读" sort key.
   *
   * This intentionally does NOT gate on Book.hasStartedReading(). That gate answers a display
   * question ("should the card say 未读?"), and it can be false for a book that was genuinely just
   * read: the readStarted/lastReadTime entries live in the variable JSON, which older importers and
   * repairOversizedImportedBookData() can reset to '{}', and durChapterIndex/durChapterPos are both
   * 0 for anyone still on the first page. Gating the sort on it forced such a book to readTime 0 and
   * sank it to the bottom of 新阅读 even though its durChapterTime was the newest on the shelf.
   *
   * A never-opened book still has durChapterTime > 0 because the Book constructor seeds it, so an
   * explicit lastReadTime is preferred and durChapterTime is the fallback evidence of a real read.
   */
  static getBookReadTime(book: Book): number {
    const lastReadTime = BookshelfSortHelper.parseBookTime(book.getVariable('lastReadTime'));
    if (lastReadTime > 0) {
      return lastReadTime;
    }
    if (!Book.hasStartedReading(book)) {
      // No explicit read marker and no chapter/page progress: treat as never read so it stays
      // below books the user actually opened, even though the constructor seeded durChapterTime.
      return 0;
    }
    return book.durChapterTime || 0;
  }

  static parseBookTime(value: string): number {
    const time = Number(value);
    return time > 0 ? time : 0;
  }
}
