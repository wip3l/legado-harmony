import { promptAction } from '@kit.ArkUI';
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

export class SearchBookShelfChange {
  requestKey: string = '';
  shelfKey: string = '';

  constructor(requestKey: string = '', shelfKey: string = '') {
    this.requestKey = requestKey;
    this.shelfKey = shelfKey;
  }
}

export class SearchBookShelfHelper {
  static keyOf(book: SearchBook): string {
    return BookIdentity.keyOfSearchBook(book);
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
    const shelfBooks = SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks());
    const shelfKeySet = new Set<string>();
    for (const book of shelfBooks) {
      const key = BookIdentity.keyOfBook(book);
      if (key) {
        shelfKeySet.add(key);
      }
    }
    const keys: string[] = [];
    for (const book of books) {
      const key = SearchBookShelfHelper.keyOf(book);
      if (key && shelfKeySet.has(key) && !keys.includes(key)) {
        keys.push(key);
      }
    }
    return keys;
  }

  static async addToShelf(context: Context, searchBook: SearchBook): Promise<SearchBookShelfChange> {
    if (!searchBook.bookUrl) {
      promptAction.showToast({ message: '书籍地址为空' });
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
      existing.intro = BookFieldSanitizer.prefer(searchBook.intro, existing.intro);
      existing.latestChapterTitle = BookFieldSanitizer.prefer(searchBook.latestChapterTitle, existing.latestChapterTitle);
      existing.wordCount = BookFieldSanitizer.prefer(searchBook.wordCount, existing.wordCount);
      SearchExplorePendingBook.clearPendingAddToShelf(existing);
      await db.updateBook(existing);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      promptAction.showToast({ message: '已在书架' });
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
      book.coverUrl = CoverUrlNormalizer.prefer(fallbackCoverUrl, fullBook.coverUrl || book.coverUrl);
      book.intro = BookFieldSanitizer.prefer(fullBook.intro, book.intro);
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
        resolvedExisting.intro = BookFieldSanitizer.prefer(book.intro, resolvedExisting.intro);
        resolvedExisting.latestChapterTitle = BookFieldSanitizer.prefer(book.latestChapterTitle, resolvedExisting.latestChapterTitle);
        resolvedExisting.wordCount = BookFieldSanitizer.prefer(book.wordCount, resolvedExisting.wordCount);
        SearchExplorePendingBook.clearPendingAddToShelf(resolvedExisting);
        await db.updateBook(resolvedExisting);
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        promptAction.showToast({ message: '已在书架' });
        return new SearchBookShelfChange(searchKey, resolvedKey);
      }
    }

    await db.insertBook(book);
    const shelfKey = resolvedKey || searchKey;
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    promptAction.showToast({ message: '已加入书架' });
    return new SearchBookShelfChange(searchKey, shelfKey);
  }

  static async removeFromShelf(context: Context, searchBook: SearchBook): Promise<SearchBookShelfChange> {
    if (!searchBook.bookUrl) {
      promptAction.showToast({ message: '书籍地址为空' });
      return new SearchBookShelfChange();
    }

    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const key = SearchBookShelfHelper.keyOf(searchBook);
    const existing = await SearchBookShelfHelper.findShelfBookByKey(key, true);
    if (existing) {
      SearchBookShelfHelper.deleteBookCoverCache(context, existing);
    }
    await db.deleteBook(existing?.bookUrl || searchBook.bookUrl);
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    promptAction.showToast({ message: '已移出书架' });
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
    book.coverUrl = CoverUrlNormalizer.normalize(searchBook.coverUrl);
    book.intro = BookFieldSanitizer.clean(searchBook.intro);
    book.latestChapterTitle = BookFieldSanitizer.clean(searchBook.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.clean(searchBook.wordCount);
    book.variable = searchBook.variable;
    book.group = -2147483645;
    book.type = 0;
    book.canUpdate = true;
    book.lastCheckTime = Date.now();
    book.latestChapterTime = Date.now();
    return book;
  }

  private static async findShelfBookByKey(bookKey: string, includePending: boolean = false): Promise<Book | null> {
    if (!bookKey) {
      return null;
    }
    const db = AppDatabase.getInstance();
    const books = await db.getAllBooks();
    for (const book of books) {
      if (BookIdentity.keyOfBook(book) === bookKey &&
        (includePending || !SearchExplorePendingBook.isPendingAddToShelf(book))) {
        return book;
      }
    }
    return null;
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
