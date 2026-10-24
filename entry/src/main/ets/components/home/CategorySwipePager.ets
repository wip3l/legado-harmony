/** 只保留当前页及相邻页的节点，发现分类较多时也不一次创建所有结果列表。 */
class CategoryPageDataSource implements IDataSource {
  private keys: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.keys.length; }
  getData(index: number): string { return this.keys[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(keys: string[]): void {
    // 搜索结果数量变化不会改变页序，不要因此打断正在进行的手势。
    if (keys.length === this.keys.length && keys.every((key: string, index: number) => key === this.keys[index])) return;
    this.keys = keys.slice();
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

/** 原生横向翻页：跟手拖动、相邻页同时滑动、松手吸附及首尾回弹。 */
@Component
export struct CategorySwipePager {
  @Prop @Watch('onPagesChanged') pageKeys: string[] = [];
  @Prop selectedIndex: number = 0;
  /** 翻页内容整体放在当前可见顶栏下方，各分类不再各自预留完整顶栏的空白。 */
  @Prop topInset: number = 0;
  @BuilderParam pageContent: (key: string) => void;
  onSelect: (key: string) => void = (_key: string) => {};
  private dataSource: CategoryPageDataSource = new CategoryPageDataSource();

  aboutToAppear(): void {
    this.onPagesChanged();
  }

  onPagesChanged(): void {
    this.dataSource.replace(this.pageKeys);
  }

  build() {
    Column() {
      Swiper() {
        LazyForEach(this.dataSource, (key: string) => {
          Column() {
            this.pageContent(key)
          }
          .width('100%')
          .height('100%')
          .clip(true)
        }, (key: string) => key)
      }
      .width('100%')
      .layoutWeight(1)
      .index(this.selectedIndex)
      .loop(false)
      .indicator(false)
      .cachedCount(1)
      .duration(300)
      .curve(Curve.EaseOut)
      .effectMode(EdgeEffect.Spring)
      .clip(true)
      .onChange((index: number) => {
        if (index >= 0 && index < this.pageKeys.length && index !== this.selectedIndex) {
          this.onSelect(this.pageKeys[index]);
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset })
  }
}
