import { router } from '@kit.ArkUI';
import { Context } from '@kit.AbilityKit';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book } from '../model/data/Book';

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
      return RecentReadShortcut.openBook(bookUrl, replaceWhenFallback);
    }
    if (action === RECENT_READ_SHORTCUT_ACTION) {
      return RecentReadShortcut.openRecentRead(context, replaceWhenFallback);
    }
    return false;
  }

  static async openRecentRead(context: Context, replaceWhenFallback: boolean = false): Promise<boolean> {
    const book = await RecentReadShortcut.getRecentReadBook(context);
    if (!book) {
      if (replaceWhenFallback) {
        router.replaceUrl(new RouteTarget('pages/Index'));
      }
      return false;
    }

    const target = new RouteTarget('pages/ReadBook', new RecentReadRouteParams(book.bookUrl));
    if (replaceWhenFallback) {
      router.replaceUrl(target);
    } else {
      router.pushUrl(target);
    }
    return true;
  }

  static openBook(bookUrl: string, replaceWhenFallback: boolean = false): boolean {
    if (!bookUrl) {
      return false;
    }
    const target = new RouteTarget('pages/ReadBook', new RecentReadRouteParams(bookUrl));
    if (replaceWhenFallback) {
      router.replaceUrl(target);
    } else {
      router.pushUrl(target);
    }
    return true;
  }

  private static async getRecentReadBook(context: Context): Promise<Book | null> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const books = await db.getAllBooks();
    return books.length > 0 ? books[0] : null;
  }
}
