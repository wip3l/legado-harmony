export class ReaderComicPageDataSource implements IDataSource {
  private pages: string[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.pages.length; }
  getData(index: number): string { return this.pages[index] || ''; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const index = this.listeners.indexOf(listener); if (index >= 0) this.listeners.splice(index, 1); }
  replace(pages: string[]): void {
    const previousCount = this.pages.length;
    let appendsExistingPrefix = pages.length >= previousCount;
    if (appendsExistingPrefix) for (let index = 0; index < previousCount; index++) if (this.pages[index] !== pages[index]) { appendsExistingPrefix = false; break; }
    if (appendsExistingPrefix && pages.length === previousCount) return;
    this.pages = [...pages];
    for (const listener of this.listeners) {
      if (appendsExistingPrefix) for (let index = previousCount; index < pages.length; index++) listener.onDataAdd(index);
      else listener.onDataReloaded();
    }
  }
  notifyChanged(index: number): void { if (index < 0 || index >= this.pages.length) return; for (const listener of this.listeners) listener.onDataChange(index); }
}

export class ReaderFloatingCatalogDataSource implements IDataSource {
  private titles: string[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.titles.length; }
  getData(index: number): string { return this.titles[index] || ''; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const index = this.listeners.indexOf(listener); if (index >= 0) this.listeners.splice(index, 1); }
  replace(titles: string[]): void { this.titles = titles.slice(); for (const listener of this.listeners) listener.onDataReloaded(); }
}
