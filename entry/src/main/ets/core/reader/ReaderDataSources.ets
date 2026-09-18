export class ReaderComicPageDataSource implements IDataSource {
  private pages: string[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.pages.length; }
  getData(index: number): string { return this.pages[index] || ''; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const index = this.listeners.indexOf(listener); if (index >= 0) this.listeners.splice(index, 1); }
  /** 返回本次是否触发了 onDataReloaded（而非尾部追加）：reload 后 LazyForEach 可能丢失滚动位置，调用方需要重新锚定。 */
  replace(pages: string[]): boolean {
    const previousCount = this.pages.length;
    let appendsExistingPrefix = pages.length >= previousCount;
    if (appendsExistingPrefix) for (let index = 0; index < previousCount; index++) if (this.pages[index] !== pages[index]) { appendsExistingPrefix = false; break; }
    if (appendsExistingPrefix && pages.length === previousCount) return false;
    this.pages = [...pages];
    for (const listener of this.listeners) {
      if (appendsExistingPrefix) for (let index = previousCount; index < pages.length; index++) listener.onDataAdd(index);
      else listener.onDataReloaded();
    }
    return !appendsExistingPrefix;
  }
  notifyChanged(index: number): void { if (index < 0 || index >= this.pages.length) return; for (const listener of this.listeners) listener.onDataChange(index); }
}
