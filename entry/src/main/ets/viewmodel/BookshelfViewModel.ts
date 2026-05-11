import { Book } from '../../model/data/Book';
import { appDb } from '../../model/data/AppDatabase';
import { LocalBook } from '../../model/localBook/LocalBook';
import picker from '@ohos.file.picker';

export class BookshelfViewModel {
  private books: Book[] = [];
  private isLoading: boolean = false;
  private onUpdate: ((books: Book[]) => void) | null = null;

  setUpdateCallback(callback: (books: Book[]) => void) {
    this.onUpdate = callback;
  }

  async loadBooks() {
    this.isLoading = true;
    try {
      this.books = await appDb.getAllBooks();
      this.onUpdate?.(this.books);
    } catch (e) {
      console.error('加载书籍失败:', e);
    } finally {
      this.isLoading = false;
    }
  }

  async importBook(): Promise<Book | null> {
    try {
      const pickerResult = await new picker.FilePicker().select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.txt', '.epub', '.umd', '.mobi', '.pdf']
      });

      if (pickerResult && pickerResult.length > 0) {
        const filePath = pickerResult[0];
        const book = await LocalBook.importBook(filePath);
        if (book) {
          await this.loadBooks();
        }
        return book;
      }
    } catch (e) {
      console.error('导入书籍失败:', e);
    }
    return null;
  }

  async deleteBook(book: Book) {
    try {
      await appDb.deleteBook(book.bookUrl);
      await this.loadBooks();
    } catch (e) {
      console.error('删除书籍失败:', e);
    }
  }

  getBooks(): Book[] {
    return this.books;
  }

  isLoadingBooks(): boolean {
    return this.isLoading;
  }

  async refreshBook(book: Book): Promise<boolean> {
    if (book.origin === 'local') {
      return false;
    }

    try {
      // 这里需要实现网络书籍更新逻辑
      return false;
    } catch (e) {
      console.error('更新书籍失败:', e);
      return false;
    }
  }

  async refreshAllBooks() {
    const books = this.books.filter(b => b.canUpdate && b.origin !== 'local');
    
    for (const book of books) {
      await this.refreshBook(book);
    }
    
    await this.loadBooks();
  }

  async updateBookGroup(book: Book, group: number) {
    book.group = group;
    await appDb.updateBook(book);
    await this.loadBooks();
  }

  async updateBookOrder(book: Book, order: number) {
    book.order = order;
    await appDb.updateBook(book);
    await this.loadBooks();
  }

  getBooksByGroup(group: number): Book[] {
    if (group === -2147483648) { // BookGroup.ID_ALL
      return this.books;
    }
    return this.books.filter(b => b.group === group);
  }

  searchBooks(keyword: string): Book[] {
    if (!keyword) {
      return this.books;
    }
    
    const lowerKeyword = keyword.toLowerCase();
    return this.books.filter(b => 
      b.name.toLowerCase().includes(lowerKeyword) ||
      b.author.toLowerCase().includes(lowerKeyword)
    );
  }

  getUnreadCount(): number {
    return this.books.reduce((sum, book) => sum + book.getUnreadChapterNum(), 0);
  }

  getRecentBooks(count: number): Book[] {
    return [...this.books]
      .sort((a, b) => b.durChapterTime - a.durChapterTime)
      .slice(0, count);
  }

  getLocalBooks(): Book[] {
    return this.books.filter(b => b.origin === 'local');
  }

  getNetworkBooks(): Book[] {
    return this.books.filter(b => b.origin !== 'local');
  }

  getAudioBooks(): Book[] {
    return this.books.filter(b => b.type === 2); // BOOK_TYPE_AUDIO
  }

  getImageBooks(): Book[] {
    return this.books.filter(b => b.type === 1); // BOOK_TYPE_IMAGE
  }

  clearCache() {
    this.books = [];
    this.onUpdate?.([]);
  }
}

export const bookshelfViewModel = new BookshelfViewModel();