import { Book, SearchBook } from '../model/data/Book';
import { EncodedSourceUrl } from '../core/book/EncodedSourceUrl';

export class BookIdentity {
  private static queryValue(url: string, names: string[]): string {
    const queryIndex = (url || '').indexOf('?');
    if (queryIndex < 0) return '';
    const hashIndex = url.indexOf('#', queryIndex + 1);
    const query = url.substring(queryIndex + 1, hashIndex >= 0 ? hashIndex : url.length);
    for (const pair of query.split('&')) {
      if (!pair) continue;
      const equalIndex = pair.indexOf('=');
      const rawName = equalIndex >= 0 ? pair.substring(0, equalIndex) : pair;
      let name = rawName;
      try {
        name = decodeURIComponent(rawName.replace(/\+/g, ' '));
      } catch (_) {
      }
      if (!names.includes(name)) continue;
      const rawValue = equalIndex >= 0 ? pair.substring(equalIndex + 1) : '';
      try {
        return decodeURIComponent(rawValue.replace(/\+/g, ' ')).trim();
      } catch (_) {
        return rawValue.trim();
      }
    }
    return '';
  }

  private static stableUrlKey(url: string): string {
    const clean = (url || '').trim();
    if (!clean) return '';
    const payload = EncodedSourceUrl.decode(clean);
    if (payload) {
      const bookId = EncodedSourceUrl.str(payload.data['book_id']) || EncodedSourceUrl.str(payload.data['bookId']);
      const source = EncodedSourceUrl.str(payload.data['source']) || EncodedSourceUrl.str(payload.data['sources']);
      const tab = EncodedSourceUrl.str(payload.data['tab']);
      if (bookId && source) return `encoded:${bookId}|${source}|${tab}`;
    }

    // Dynamic aggregation sources rotate their API host while keeping the logical detail endpoint.
    // Only canonicalise recognizable detail/book URLs; generic `id` parameters may be page-local.
    const path = clean.split(/[?#]/, 1)[0].toLowerCase();
    const looksLikeBookDetail = /\/(detail|book|bookinfo)(?:\/|$)/.test(path);
    const bookId = BookIdentity.queryValue(clean, ['bookId', 'book_id', 'bid']);
    if (looksLikeBookDetail && bookId) {
      const source = BookIdentity.queryValue(clean, ['source', 'sources']);
      const tab = BookIdentity.queryValue(clean, ['tab']);
      return `detail:${bookId}|${source}|${tab}`;
    }
    return clean;
  }

  static keyOfUrl(url: string, origin: string = ''): string {
    const stable = BookIdentity.stableUrlKey(url);
    if (!stable) return '';
    return origin ? `${origin}\n${stable}` : stable;
  }

  static hasLogicalIdentity(url: string): boolean {
    const payload = EncodedSourceUrl.decode(url);
    if (payload) {
      const bookId = EncodedSourceUrl.str(payload.data['book_id']) || EncodedSourceUrl.str(payload.data['bookId']);
      const source = EncodedSourceUrl.str(payload.data['source']) || EncodedSourceUrl.str(payload.data['sources']);
      if (bookId && source) return true;
    }
    const path = (url || '').split(/[?#]/, 1)[0].toLowerCase();
    return /\/(detail|book|bookinfo)(?:\/|$)/.test(path) &&
      !!BookIdentity.queryValue(url, ['bookId', 'book_id', 'bid']);
  }

  static keyOfBook(book: Book): string {
    return BookIdentity.keyOfUrl(book.bookUrl, book.origin);
  }

  static keyOfSearchBook(book: SearchBook): string {
    return BookIdentity.keyOfUrl(book.bookUrl, book.origin);
  }

  /** Keeps legacy cloud IDs for ordinary sources and switches only host-volatile logical URLs to v2. */
  static cloudIdentityValue(book: Book): string {
    // A local source URI is device-specific (picker providers and sandbox paths
    // differ across devices). Use the imported file's content fingerprint when
    // available so progress entities can match the same local edition remotely.
    if (book.origin === 'local') {
      const contentHash = book.getVariable('localContentHash').trim();
      if (contentHash) return `local-content-v1\n${contentHash}`;
    }
    if (!BookIdentity.hasLogicalIdentity(book.bookUrl)) {
      return `${book.origin}\n${book.bookUrl}`;
    }
    return `stable-v2\n${BookIdentity.keyOfBook(book)}`;
  }
}
