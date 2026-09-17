import { Book, BookGroup, SearchBook } from '../../model/data/Book';
import { ExploreSourceOption } from './ExploreCoordinator';

export class ShelfTileSortEntry {
  kind: string = 'book'; key: string = ''; book: Book | null = null; group: BookGroup | null = null;
  readTime: number = 0; addTime: number = 0; name: string = ''; pinned: boolean = false; originalOrder: number = 0;
}
export class ShelfBookDataSource implements IDataSource {
  private books: Book[] = []; private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.books.length; }
  getData(index: number): Book { return this.books[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const i = this.listeners.indexOf(listener); if (i >= 0) this.listeners.splice(i, 1); }
  replace(books: Book[], force: boolean = false): void {
    if (!force && this.books.length === books.length && this.books.every((b, i) => b === books[i])) return;
    this.books = [...books]; for (const listener of this.listeners) listener.onDataReloaded();
  }
}
export class ShelfTileEntryDataSource implements IDataSource {
  private entries: ShelfTileSortEntry[] = []; private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.entries.length; } getData(index: number): ShelfTileSortEntry { return this.entries[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const i = this.listeners.indexOf(listener); if (i >= 0) this.listeners.splice(i, 1); }
  replace(entries: ShelfTileSortEntry[], force: boolean = false): void {
    if (!force && this.entries.length === entries.length && this.entries.every((e, i) => e.key === entries[i].key && e.book === entries[i].book && e.group === entries[i].group)) return;
    this.entries = [...entries]; for (const listener of this.listeners) listener.onDataReloaded();
  }
}
export class ExploreSourceOptionDataSource implements IDataSource {
  private options: ExploreSourceOption[] = []; private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.options.length; } getData(index: number): ExploreSourceOption { return this.options[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const i = this.listeners.indexOf(listener); if (i >= 0) this.listeners.splice(i, 1); }
  replace(options: ExploreSourceOption[]): void { this.options = options.slice(); for (const listener of this.listeners) listener.onDataReloaded(); }
}
export class ExploreMetadataTask { book: SearchBook = new SearchBook(); loadVersion: number = 0; }
