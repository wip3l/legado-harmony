import { Context } from '@kit.AbilityKit';
import { Book, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { BookCoverCache } from './BookCoverCache';
import { BookDisplayHelper } from './BookDisplayHelper';
import { BookIdentity } from './BookIdentity';
import { CoverUrlNormalizer } from './CoverUrlNormalizer';
import { BookFieldSanitizer } from './BookFieldSanitizer';
import { SearchExplorePendingBook } from './SearchExplorePendingBook';
import { AppThemeSettingsStore } from './AppThemeSettingsStore';
import { BookTypeSupport } from '../core/book/BookTypeSupport';
import { HdsFeedback } from './HdsFeedback';

export class SearchBookShelfChange {
  requestKey: string = '';
  shelfKey: string = '';

  constructor(requestKey: string = '', shelfKey: string = '') {
    this.requestKey = requestKey;
    this.shelfKey = shelfKey;
  }
}

export class SearchBookShelfHelper {
  private static shelfLookupVersion: number = -1;
  private static shelfLookupLoaded: boolean = false;
  private static shelfLookup: Map<string, Book[]> = new Map();

  static keyOf(book: SearchBook): string {
    return BookIdentity.keyOfSearchBook(book);
  }

  /**
   * Search pages often expose pagination links outside the actual result cards. A broad
   * bookList rule can turn one of those links into a fake candidate (for example “下一页”),
   * which must not be offered as a book when changing source.
   */
  static isNavigationResult(book: SearchBook): boolean {
    const compact = (book.name || '').replace(/\s+/g, '')
      .replace(/[»›>→…。]+$/g, '').toLowerCase();
    return /^(?:下一页|下一頁|下页|下頁|上一页|上一頁|上页|上頁|首页|首頁|尾页|尾頁|末页|末頁|加载更多|載入更多|next|nextpage|previous|prev|home|more)$/.test(compact);
  }

  static isInShelf(book: SearchBook, shelfBookKeys: string[]): boolean {
    const key = SearchBookShelfHelper.keyOf(book);
    return !!key && shelfBookKeys.includes(key);
  }

  static isBusy(book: SearchBook, busyBookKeys: string[]): boolean {
    const key = SearchBookShelfHelper.keyOf(book);
    return !!key && busyBookKeys.includes(key);
  }

  static buttonText(book: SearchBook, shelfBookKeys: string[], busyBookKeys: string[]): string {
    if (SearchBookShelfHelper.isBusy(book, busyBookKeys)) {
      return '加入中';
    }
    return SearchBookShelfHelper.isInShelf(book, shelfBookKeys) ? '移除' : '加入';
  }

  static buttonColor(book: SearchBook, shelfBookKeys: string[], busyBookKeys: string[]): string {
    if (SearchBookShelfHelper.isBusy(book, busyBookKeys)) {
      return '#8A8F98';
    }
    return SearchBookShelfHelper.isInShelf(book, shelfBookKeys) ? '#E53935' :
      AppThemeSettingsStore.buttonColor(AppStorage.get<boolean>('appDarkMode') || false);
  }

  static withAddedKey(keys: string[], key: string): string[] {
    if (!key || keys.includes(key)) {
      return keys;
    }
    return [...keys, key];
  }

  static withoutKey(keys: string[], key: string): string[] {
    if (!key || !keys.includes(key)) {
      return keys;
    }
    return keys.filter((item: string) => item !== key);
  }

  static async syncShelfKeys(context: Context, books: SearchBook[]): Promise<string[]> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const lookup = await SearchBookShelfHelper.getShelfLookup();
    const keys: string[] = [];
    const added = new Set<string>();
    for (const book of books) {
      const key = SearchBookShelfHelper.keyOf(book);
      if (!key || added.has(key)) continue;
      const matches = lookup.get(key) || [];
      if (!matches.some((item: Book): boolean => !SearchExplorePendingBook.isPendingAddToShelf(item))) continue;
      added.add(key);
      keys.push(key);
    }
    return keys;
  }

  static async addToShelf(context: Context, searchBook: SearchBook): Promise<SearchBookShelfChange> {
    if (!searchBook.bookUrl) {
      HdsFeedback.showToast('书籍地址为空');
      return new SearchBookShelfChange();
    }

    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const searchKey = SearchBookShelfHelper.keyOf(searchBook);
    const existing = await SearchBookShelfHelper.findShelfBookByKey(searchKey, true);
    if (existing) {
      const nextCoverUrl = CoverUrlNormalizer.prefer(searchBook.coverUrl, existing.coverUrl);
      if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
        existing.coverUrl = nextCoverUrl;
      }
      existing.kind = BookFieldSanitizer.prefer(searchBook.kind, existing.kind);
      existing.status = BookFieldSanitizer.prefer(searchBook.status, existing.status);
      existing.intro = BookFieldSanitizer.prefer(searchBook.intro, existing.intro);
      existing.updateTime = BookFieldSanitizer.prefer(searchBook.updateTime, existing.updateTime);
      existing.latestChapterTitle = BookFieldSanitizer.prefer(searchBook.latestChapterTitle, existing.latestChapterTitle);
      existing.wordCount = BookFieldSanitizer.prefer(searchBook.wordCount, existing.wordCount);
      SearchExplorePendingBook.clearPendingAddToShelf(existing);
      await db.updateBook(existing, true, 'search_result_explicit_add_existing');
      SearchBookShelfHelper.markShelfChanged();
      HdsFeedback.showToast('已在书架');
      return new SearchBookShelfChange(searchKey, searchKey);
    }

    const book = SearchBookShelfHelper.toBook(searchBook);
    const fallbackCoverUrl = book.coverUrl;
    const source = book.origin ? await db.getBookSource(book.origin) : null;
    if (source) {
      const service = new WebBookService();
      const fullBook = await service.getBookInfo(source, book);
      book.bookUrl = fullBook.bookUrl || book.bookUrl;
      book.tocUrl = fullBook.tocUrl || book.tocUrl;
      book.name = fullBook.name || book.name;
      book.author = fullBook.author || book.author;
      book.kind = BookFieldSanitizer.prefer(fullBook.kind, book.kind);
      book.status = BookFieldSanitizer.prefer(fullBook.status, book.status);
      book.coverUrl = CoverUrlNormalizer.prefer(fallbackCoverUrl, fullBook.coverUrl || book.coverUrl);
      book.intro = BookFieldSanitizer.prefer(fullBook.intro, book.intro);
      book.updateTime = BookFieldSanitizer.prefer(fullBook.updateTime, book.updateTime);
      book.latestChapterTitle = BookFieldSanitizer.prefer(fullBook.latestChapterTitle, book.latestChapterTitle);
      book.wordCount = BookFieldSanitizer.prefer(fullBook.wordCount, book.wordCount);
      book.variable = fullBook.variable || book.variable;
    }

    const resolvedKey = BookIdentity.keyOfBook(book);
    if (resolvedKey && resolvedKey !== searchKey) {
      const resolvedExisting = await SearchBookShelfHelper.findShelfBookByKey(resolvedKey, true);
      if (resolvedExisting) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(book.coverUrl, resolvedExisting.coverUrl);
        if (nextCoverUrl && resolvedExisting.coverUrl !== nextCoverUrl) {
          resolvedExisting.coverUrl = nextCoverUrl;
        }
        resolvedExisting.kind = BookFieldSanitizer.prefer(book.kind, resolvedExisting.kind);
        resolvedExisting.status = BookFieldSanitizer.prefer(book.status, resolvedExisting.status);
        resolvedExisting.intro = BookFieldSanitizer.prefer(book.intro, resolvedExisting.intro);
        resolvedExisting.updateTime = BookFieldSanitizer.prefer(book.updateTime, resolvedExisting.updateTime);
        resolvedExisting.latestChapterTitle = BookFieldSanitizer.prefer(book.latestChapterTitle, resolvedExisting.latestChapterTitle);
        resolvedExisting.wordCount = BookFieldSanitizer.prefer(book.wordCount, resolvedExisting.wordCount);
        SearchExplorePendingBook.clearPendingAddToShelf(resolvedExisting);
        await db.updateBook(resolvedExisting, true, 'search_result_explicit_add_resolved');
        SearchBookShelfHelper.markShelfChanged();
        HdsFeedback.showToast('已在书架');
        return new SearchBookShelfChange(searchKey, resolvedKey);
      }
    }

    await db.insertBook(book, 'search_result_explicit_add');
    const shelfKey = resolvedKey || searchKey;
    SearchBookShelfHelper.markShelfChanged();
    HdsFeedback.showToast('已加入书架');
    return new SearchBookShelfChange(searchKey, shelfKey);
  }

  static async removeFromShelf(context: Context, searchBook: SearchBook): Promise<SearchBookShelfChange> {
    if (!searchBook.bookUrl) {
      HdsFeedback.showToast('书籍地址为空');
      return new SearchBookShelfChange();
    }

    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const key = SearchBookShelfHelper.keyOf(searchBook);
    const existing = await SearchBookShelfHelper.findShelfBookByKey(key, true);
    if (existing) {
      SearchBookShelfHelper.deleteBookCoverCache(context, existing);
    }
    await db.deleteBook(existing?.bookUrl || searchBook.bookUrl, 'search_result_explicit_remove');
    SearchBookShelfHelper.markShelfChanged();
    HdsFeedback.showToast('已移出书架');
    return new SearchBookShelfChange(key, key);
  }

  private static toBook(searchBook: SearchBook): Book {
    const book = new Book();
    book.bookUrl = searchBook.bookUrl;
    book.tocUrl = searchBook.tocUrl;
    book.origin = searchBook.origin;
    book.originName = searchBook.originName;
    book.name = searchBook.name;
    book.author = searchBook.author;
    book.kind = BookFieldSanitizer.clean(searchBook.kind);
    book.status = BookFieldSanitizer.clean(searchBook.status);
    book.coverUrl = CoverUrlNormalizer.normalize(searchBook.coverUrl);
    book.intro = BookFieldSanitizer.clean(searchBook.intro);
    book.updateTime = BookFieldSanitizer.clean(searchBook.updateTime);
    book.latestChapterTitle = BookFieldSanitizer.clean(searchBook.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.clean(searchBook.wordCount);
    book.variable = searchBook.variable;
    book.group = -2147483645;
    book.type = searchBook.type || 0;
    BookTypeSupport.applyBookType(book);
    book.canUpdate = true;
    book.lastCheckTime = Date.now();
    book.latestChapterTime = Date.now();
    return book;
  }

  static async findShelfBookByKey(bookKey: string, includePending: boolean = false): Promise<Book | null> {
    if (!bookKey) {
      return null;
    }
    const lookup = await SearchBookShelfHelper.getShelfLookup();
    const books = lookup.get(bookKey) || [];
    for (const book of books) {
      if (includePending || !SearchExplorePendingBook.isPendingAddToShelf(book)) {
        return book;
      }
    }
    return null;
  }

  private static async getShelfLookup(): Promise<Map<string, Book[]>> {
    const version = AppStorage.get<number>('shelfUpdateTime') || 0;
    if (SearchBookShelfHelper.shelfLookupLoaded && version === SearchBookShelfHelper.shelfLookupVersion) {
      return SearchBookShelfHelper.shelfLookup;
    }
    const books = await AppDatabase.getInstance().getAllBooks();
    SearchBookShelfHelper.cacheShelfBooks(books, version);
    return SearchBookShelfHelper.shelfLookup;
  }

  private static cacheShelfBooks(books: Book[], version: number = AppStorage.get<number>('shelfUpdateTime') || 0): void {
    const lookup: Map<string, Book[]> = new Map();
    for (const book of books) {
      const key = BookIdentity.keyOfBook(book);
      if (!key) continue;
      const matches = lookup.get(key) || [];
      matches.push(book);
      lookup.set(key, matches);
    }
    SearchBookShelfHelper.shelfLookup = lookup;
    SearchBookShelfHelper.shelfLookupVersion = version;
    SearchBookShelfHelper.shelfLookupLoaded = true;
  }

  private static markShelfChanged(): void {
    SearchBookShelfHelper.shelfLookupLoaded = false;
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
  }

  private static deleteBookCoverCache(context: Context, book: Book): void {
    const covers = [
      ...BookDisplayHelper.decodeCoverList(book.customCoverUrl),
      ...BookDisplayHelper.decodeCoverList(book.coverUrl)
    ];
    for (const cover of covers) {
      BookCoverCache.deleteCachedCover(context, cover);
    }
  }
}
