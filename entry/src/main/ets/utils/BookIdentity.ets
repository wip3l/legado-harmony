import { Book, SearchBook } from '../model/data/Book';
import { EncodedSourceUrl } from '../core/book/EncodedSourceUrl';

export class BookIdentity {
  static keyOfUrl(url: string): string {
    const payload = EncodedSourceUrl.decode(url);
    if (!payload) return url || '';
    const bookId = EncodedSourceUrl.str(payload.data['book_id']) || EncodedSourceUrl.str(payload.data['bookId']);
    const source = EncodedSourceUrl.str(payload.data['source']) || EncodedSourceUrl.str(payload.data['sources']);
    const tab = EncodedSourceUrl.str(payload.data['tab']);
    if (!bookId || !source) return url || '';
    return `encoded:${bookId}|${source}|${tab}`;
  }

  static keyOfBook(book: Book): string {
    return BookIdentity.keyOfUrl(book.bookUrl);
  }

  static keyOfSearchBook(book: SearchBook): string {
    return BookIdentity.keyOfUrl(book.bookUrl);
  }
}
