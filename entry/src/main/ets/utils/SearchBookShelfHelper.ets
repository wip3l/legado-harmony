import { promptAction } from '@kit.ArkUI';
import { Context } from '@kit.AbilityKit';
import { Book, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { BookCoverCache } from './BookCoverCache';
import { BookDisplayHelper } from './BookDisplayHelper';
import { BookIdentity } from './BookIdentity';

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
    return SearchBookShelfHelper.isInShelf(book, shelfBookKeys) ? '#E53935' : '#007DFF';
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
    const shelfBooks = await db.getAllBooks();
    const shelfKeys = shelfBooks.map((book: Book) => BookIdentity.keyOfBook(book));
    const keys: string[] = [];
    for (const book of books) {
      const key = SearchBookShelfHelper.keyOf(book);
      if (key && shelfKeys.includes(key)) {
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
    const existing = await SearchBookShelfHelper.findShelfBookByKey(searchKey);
    if (existing) {
      if (!existing.coverUrl && searchBook.coverUrl) {
        existing.coverUrl = searchBook.coverUrl;
        await db.updateBook(existing);
      }
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
      book.tocUrl = fullBook.tocUrl;
      book.name = fullBook.name;
      book.author = fullBook.author;
      book.kind = fullBook.kind;
      book.coverUrl = fullBook.coverUrl || fallbackCoverUrl;
      book.intro = fullBook.intro;
      book.latestChapterTitle = fullBook.latestChapterTitle;
      book.wordCount = fullBook.wordCount;
      book.variable = fullBook.variable;
    }

    await db.insertBook(book);
    const shelfKey = BookIdentity.keyOfBook(book) || searchKey;
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
    const existing = await SearchBookShelfHelper.findShelfBookByKey(key);
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
    book.kind = searchBook.kind;
    book.coverUrl = searchBook.coverUrl;
    book.intro = searchBook.intro;
    book.latestChapterTitle = searchBook.latestChapterTitle;
    book.wordCount = searchBook.wordCount;
    book.variable = searchBook.variable;
    book.group = -2147483645;
    book.type = 0;
    book.canUpdate = true;
    book.lastCheckTime = Date.now();
    book.latestChapterTime = Date.now();
    return book;
  }

  private static async findShelfBookByKey(bookKey: string): Promise<Book | null> {
    if (!bookKey) {
      return null;
    }
    const db = AppDatabase.getInstance();
    const books = await db.getAllBooks();
    for (const book of books) {
      if (BookIdentity.keyOfBook(book) === bookKey) {
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
