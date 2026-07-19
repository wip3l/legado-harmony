import { router, promptAction } from '@kit.ArkUI';
import { BookSource } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';

@Entry
@Component
struct ExploreSourceSortPage {
  @StorageLink('searchExploreSourceSort') searchExploreSourceSort: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State sources: BookSource[] = [];
  @State isLoading: boolean = false;
  @State draggingIndex: number = -1;

  aboutToAppear(): void {
    this.syncBars();
    this.loadSources();
  }

  onPageShow(): void {
    this.syncBars();
    this.loadSources();
  }

  async loadSources(): Promise<void> {
    this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const allSources = await db.getAllBookSources();
      const enabledExploreSources = allSources.filter((source: BookSource) =>
        source.enabledExplore && !!(source.exploreUrl || '').trim());
      this.sources = this.applySavedOrder(enabledExploreSources);
      this.saveOrder(false);
    } catch (e) {
      console.error('加载发现书源排序失败:', e);
      promptAction.showToast({ message: '加载书源失败' });
    } finally {
      this.isLoading = false;
    }
  }

  applySavedOrder(sourceList: BookSource[]): BookSource[] {
    const order = this.sortedSourceUrls();
    if (order.length === 0) {
      return sourceList;
    }
    const result: BookSource[] = [];
    for (const url of order) {
      const source = sourceList.find((item: BookSource) => item.bookSourceUrl === url);
      if (source && !result.some((item: BookSource) => item.bookSourceUrl === source.bookSourceUrl)) {
        result.push(source);
      }
    }
    for (const source of sourceList) {
      if (!result.some((item: BookSource) => item.bookSourceUrl === source.bookSourceUrl)) {
        result.push(source);
      }
    }
    return result;
  }

  sortedSourceUrls(): string[] {
    return (this.searchExploreSourceSort || '').split('\n')
      .map((url: string) => url.trim())
      .filter((url: string) => !!url);
  }

  build() {
    Column() {
      this.titleBar()

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.subTextColor())
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.sources.length === 0) {
        Column() {
          Text('暂无启用发现的书源')
            .fontSize(16)
            .fontColor(this.subTextColor())
          Text('请先在书源管理中启用发现')
            .fontSize(14)
            .fontColor(this.subTextColor())
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.sources, (source: BookSource, index: number) => {
            ListItem() {
              Row() {
                Text('☰')
                  .fontSize(18)
                  .fontColor(this.subTextColor())
                  .width(24)
                  .textAlign(TextAlign.Center)
                  .margin({ right: 4 })

                Text(`${index + 1}`)
                  .fontSize(13)
                  .fontColor(this.subTextColor())
                  .width(28)
                  .textAlign(TextAlign.Center)

                Column() {
                  Text(source.bookSourceName || '未命名书源')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.primaryTextColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(source.bookSourceUrl)
                    .fontSize(12)
                    .fontColor(this.subTextColor())
                    .margin({ top: 4 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text('↑')
                  .width(36)
                  .height(32)
                  .fontSize(18)
                  .fontColor(index > 0 ? this.primaryTextColor() : this.disabledTextColor())
                  .textAlign(TextAlign.Center)
                  .backgroundColor(index > 0 ? this.inputColor() : this.disabledButtonColor())
                  .borderRadius(16)
                  .onClick(() => {
                    if (index > 0) {
                      this.moveSource(index, -1);
                    }
                  })

                Text('↓')
                  .width(36)
                  .height(32)
                  .fontSize(18)
                  .margin({ left: 6 })
                  .fontColor(index < this.sources.length - 1 ? this.primaryTextColor() : this.disabledTextColor())
                  .textAlign(TextAlign.Center)
                  .backgroundColor(index < this.sources.length - 1 ? this.inputColor() : this.disabledButtonColor())
                  .borderRadius(16)
                  .onClick(() => {
                    if (index < this.sources.length - 1) {
                      this.moveSource(index, 1);
                    }
                  })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.cardColor())
              .borderRadius(8)
            }
          }, (source: BookSource) => source.bookSourceUrl)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
          this.draggingIndex = itemIndex;
          return this.sourceDragPreview;
        })
        .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
          if (isSuccess) {
            this.moveSourceTo(itemIndex, insertIndex);
          }
          this.draggingIndex = -1;
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  moveSource(index: number, direction: number): void {
    const target = index + direction;
    if (index < 0 || index >= this.sources.length || target < 0 || target >= this.sources.length) {
      return;
    }
    const next = this.sources.slice();
    const current = next[index];
    next[index] = next[target];
    next[target] = current;
    this.sources = next;
    this.saveOrder(true);
  }

  moveSourceTo(from: number, to: number): boolean {
    if (from < 0 || from >= this.sources.length || to < 0 || to >= this.sources.length || from === to) {
      return false;
    }
    const next = this.sources.slice();
    const moved = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.sources = next;
    this.saveOrder(false);
    return true;
  }

  saveOrder(showToast: boolean): void {
    this.searchExploreSourceSort = this.sources
      .map((source: BookSource) => source.bookSourceUrl)
      .filter((url: string) => !!url)
      .join('\n');
    SearchExploreSettingsStore.load(getContext(this)).then((settings: SearchExploreSettings) => {
      settings.sourceSortRaw = this.searchExploreSourceSort;
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(getContext(this), settings);
    }).then(() => {
      if (showToast) {
        promptAction.showToast({ message: '排序已保存' });
      }
    }).catch((e: Error) => {
      console.warn('保存发现书源排序失败:', e);
      if (showToast) {
        promptAction.showToast({ message: '保存排序失败' });
      }
    });
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  disabledTextColor(): string {
    return this.appDarkMode ? '#5D626B' : '#C0C4CC';
  }

  disabledButtonColor(): string {
    return this.appDarkMode ? '#202329' : '#ECEFF3';
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  sourceDragPreview() {
    Row() {
      Text('☰')
        .fontSize(18)
        .fontColor(this.subTextColor())
        .width(24)
        .textAlign(TextAlign.Center)
        .margin({ right: 8 })
      Column() {
        Text(this.draggingTitle())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.draggingUrl())
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(280)
    .padding(12)
    .backgroundColor(this.cardColor())
    .borderRadius(8)
    .shadow({ radius: 12, color: this.appDarkMode ? '#66000000' : '#22000000', offsetX: 0, offsetY: 4 })
  }

  draggingTitle(): string {
    if (this.draggingIndex < 0 || this.draggingIndex >= this.sources.length) {
      return '';
    }
    return this.sources[this.draggingIndex].bookSourceName || '未命名书源';
  }

  draggingUrl(): string {
    if (this.draggingIndex < 0 || this.draggingIndex >= this.sources.length) {
      return '';
    }
    return this.sources[this.draggingIndex].bookSourceUrl;
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('书源排序')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Blank()
        .width(52)
        .height(56)
    }
    .width('100%')
    .height(56)
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }
}
