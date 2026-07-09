import { router } from '@kit.ArkUI';
import { Context } from '@kit.AbilityKit';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book } from '../model/data/Book';
import { BookshelfSortHelper } from './BookshelfSortHelper';
import { SearchExplorePendingBook } from './SearchExplorePendingBook';

export const RECENT_READ_SHORTCUT_ACTION = 'recent_read';
export const OPEN_BOOK_SHORTCUT_ACTION = 'open_book';

class RecentReadRouteParams {
  bookUrl: string = '';

  constructor(bookUrl: string) {
    this.bookUrl = bookUrl;
  }
}

class RouteTarget {
  url: string = '';
  params?: RecentReadRouteParams;

  constructor(url: string, params?: RecentReadRouteParams) {
    this.url = url;
    this.params = params;
  }
}

export class RecentReadShortcut {
  static isPending(): boolean {
    const action = AppStorage.get<string>('launchShortcutAction') || '';
    return action === RECENT_READ_SHORTCUT_ACTION || action === OPEN_BOOK_SHORTCUT_ACTION;
  }

  static request(): void {
    AppStorage.setOrCreate('launchShortcutAction', RECENT_READ_SHORTCUT_ACTION);
    AppStorage.setOrCreate('launchShortcutBookUrl', '');
    AppStorage.setOrCreate('launchShortcutNonce', Date.now());
  }

  static requestBook(bookUrl: string): void {
    AppStorage.setOrCreate('launchShortcutAction', OPEN_BOOK_SHORTCUT_ACTION);
    AppStorage.setOrCreate('launchShortcutBookUrl', bookUrl);
    AppStorage.setOrCreate('launchShortcutNonce', Date.now());
  }

  static consume(): void {
    AppStorage.setOrCreate('launchShortcutAction', '');
    AppStorage.setOrCreate('launchShortcutBookUrl', '');
  }

  static async openPending(context: Context, replaceWhenFallback: boolean = false): Promise<boolean> {
    const action = AppStorage.get<string>('launchShortcutAction') || '';
    const bookUrl = AppStorage.get<string>('launchShortcutBookUrl') || '';
    if (action === OPEN_BOOK_SHORTCUT_ACTION && bookUrl) {
      return await RecentReadShortcut.openBook(bookUrl, replaceWhenFallback);
    }
    if (action === RECENT_READ_SHORTCUT_ACTION) {
      return await RecentReadShortcut.openRecentRead(context, replaceWhenFallback);
    }
    return false;
  }

  static async openRecentRead(context: Context, replaceWhenFallback: boolean = false): Promise<boolean> {
    const book = await RecentReadShortcut.getRecentReadBook(context);
    if (!book) {
      if (replaceWhenFallback) {
        await RecentReadShortcut.navigate(new RouteTarget('pages/Index'), true);
      }
      return false;
    }

    const target = new RouteTarget('pages/ReadBook', new RecentReadRouteParams(book.bookUrl));
    return await RecentReadShortcut.navigate(target, replaceWhenFallback);
  }

  static async openBook(bookUrl: string, replaceWhenFallback: boolean = false): Promise<boolean> {
    if (!bookUrl) {
      return false;
    }
    const target = new RouteTarget('pages/ReadBook', new RecentReadRouteParams(bookUrl));
    return await RecentReadShortcut.navigate(target, replaceWhenFallback);
  }

  private static async getRecentReadBook(context: Context): Promise<Book | null> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const books = BookshelfSortHelper.sortByRecentRead(SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks()));
    return books.length > 0 ? books[0] : null;
  }

  private static async navigate(target: RouteTarget, replace: boolean): Promise<boolean> {
    try {
      if (replace) {
        await router.replaceUrl(target);
      } else {
        await router.pushUrl(target);
      }
      return true;
    } catch (e) {
      console.error('打开最近阅读路由失败:', e);
      return false;
    }
  }
}
