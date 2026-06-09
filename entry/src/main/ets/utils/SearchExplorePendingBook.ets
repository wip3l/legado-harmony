import { Book } from '../model/data/Book';

export class SearchExplorePendingBook {
  private static readonly KEY_PENDING_ADD_TO_SHELF: string = 'searchExplorePendingAddToShelf';

  static isPendingAddToShelf(book: Book | null): boolean {
    return !!book && book.getVariable(SearchExplorePendingBook.KEY_PENDING_ADD_TO_SHELF) === 'true';
  }

  static markPendingAddToShelf(book: Book): void {
    book.putVariable(SearchExplorePendingBook.KEY_PENDING_ADD_TO_SHELF, 'true');
  }

  static clearPendingAddToShelf(book: Book): void {
    book.putVariable(SearchExplorePendingBook.KEY_PENDING_ADD_TO_SHELF, 'false');
  }

  static filterShelfBooks(books: Book[]): Book[] {
    return books.filter((book: Book) => !SearchExplorePendingBook.isPendingAddToShelf(book));
  }
}
