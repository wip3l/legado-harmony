import { ThemeRuntime } from '../theme/ThemeRuntime';
import { VirtualListScrollbar } from '../utils/VirtualListScrollbar';
import { ImmersiveBackButton } from './ImmersiveBackButton';

/**
 * The catalog list feeds on chapter *titles*, not chapter records. Declaring the
 * narrowed return type here makes a mismatched data source a compile error
 * instead of a silently blank list — `LazyForEach` cannot check it for us
 * because `IDataSource.getData()` is typed `any`.
 */
export interface CatalogTitleSource extends IDataSource {
  getData(index: number): string;
}

/** The one title data source every caller of this sheet should use. */
export class CatalogTitleDataSource implements CatalogTitleSource {
  private titles: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.titles.length; }

  getData(index: number): string { return this.titles[index] || ''; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(titles: string[]): void {
    this.titles = titles.slice();
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

const CATALOG_SCROLLBAR_MIN_SCROLL_INTERVAL_MS = 90;
const CATALOG_COVER_WIDTH = 52;
const CATALOG_COVER_HEIGHT = 68;

/**
 * The single catalog sheet behind every TTS / audio-book entry point: the reader's
 * floating player, the standalone audio-book page and the shelf. It deliberately
 * mirrors the reader's own table of contents
 * (ReadBook.readerFloatingTocPanel / tocPanelSummary / tocChapterList):
 *   - glass panel surface, 28vp corner radius, glass border + shadow
 *   - cover + book name (+ optional subtitle) header with a circular close button
 *   - summary row carrying "共 N 章", the order toggle and the chapter progress
 *   - list rows with a `•` / `·` leader, hairline separators and a cache chip
 *
 * The caller keeps the data source in *display order*, so every index this
 * component receives and emits is a display index; the caller converts it back
 * to a canonical chapter index.
 */
@Component
export struct TtsCatalogSheet {
  @Prop darkMode: boolean = false;
  @Prop accentColor: string = '#007DFF';
  @Prop primaryTextColor: string = '#18191C';
  @Prop subTextColor: string = '#8A8A8E';
  @Prop controlIconColor: string = '#FF202124';
  @Prop panelColor: string = '#FFFFFF';
  @Prop bookName: string = '';
  @Prop bookInitial: string = '书';
  @Prop cover: ResourceStr = '';
  @Prop bookSubtitle: string = '';
  @Prop count: number = 0;
  @Prop currentDisplayIndex: number = 0;
  @Prop reverseOrder: boolean = false;
  @Prop progressText: string = '';
  @Prop bottomInset: number = 0;
  @Prop viewportHeight: number = 720;
  @Prop zIndexValue: number = 20;
  @State listViewportHeight: number = 0;
  @State firstVisibleIndex: number = 0;
  @State visibleItemCount: number = 1;
  @State scrollbarDragging: boolean = false;
  @State dragOffset: number = 0;
  scroller: ListScroller = new ListScroller();
  source: CatalogTitleSource = new CatalogTitleDataSource();
  isCached: (displayIndex: number) => boolean = () => false;
  onToggleOrder: () => void = () => {};
  onSelect: (displayIndex: number) => void = () => {};
  onClose: () => void = () => {};
  private pointerAnchor: number = 0;
  private lastScrollbarScrollAt: number = 0;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#78000000')
        .onClick(() => this.onClose())

      Column() {
        this.catalogHeader()
        this.catalogSummary()
        this.catalogChapterList()
      }
      .width('100%')
      .height(this.panelHeight())
      .padding({ left: 0, right: 0, top: 0, bottom: this.bottomInset + 12 })
      .borderRadius({ topLeft: this.panelCornerRadius(), topRight: this.panelCornerRadius() })
      .clip(true)
      .backgroundColor(this.panelColor)
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: {
          left: ThemeRuntime.glassBorderWidth('panel'),
          right: ThemeRuntime.glassBorderWidth('panel'),
          top: ThemeRuntime.glassBorderWidth('panel')
        },
        color: ThemeRuntime.glassBorderColor(this.darkMode)
      })
      .shadow({
        radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.darkMode),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'),
        offsetY: ThemeRuntime.glassShadowOffsetY('panel')
      })
      .transition(TransitionEffect.translate({ y: 520 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 280, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
    .zIndex(this.zIndexValue)
  }

  @Builder
  catalogHeader() {
    Row({ space: 14 }) {
      if (this.cover !== '') {
        Image(this.cover)
          .width(CATALOG_COVER_WIDTH)
          .height(CATALOG_COVER_HEIGHT)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
      } else {
        Text(this.bookInitial || '书')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width(CATALOG_COVER_WIDTH)
          .height(CATALOG_COVER_HEIGHT)
          .borderRadius(8)
          .backgroundColor(this.accentColor)
      }

      Column({ space: 5 }) {
        Text(this.bookName || '目录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // Optional: entries that cannot reach the author (e.g. the shelf, whose
        // TTS session only publishes book name + cover) render a single line
        // instead of a misleading "未知作者".
        if (this.bookSubtitle) {
          Text(this.bookSubtitle)
            .fontSize(12)
            .fontColor(this.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      ImmersiveBackButton({
        icon: $r('sys.symbol.xmark'),
        iconOffsetX: 0,
        iconColor: this.controlIconColor,
        darkMode: this.darkMode,
        buttonSize: 40,
        containerWidth: 40,
        containerHeight: 40,
        startInset: 0,
        materialScale: 0.83,
        compactLayout: true,
        accessibilityLabel: '关闭目录',
        onBack: () => this.onClose()
      })
        .alignSelf(ItemAlign.Start)
        .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 20, right: 16, top: 12, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  catalogSummary() {
    Column({ space: 8 }) {
      Row() {
        Text(`共 ${this.count} 章`)
          .fontSize(14)
          .fontColor(this.subTextColor)
          .margin({ left: 6 })
          .padding({ left: 8, right: 8 })
          .height(34)
          .textAlign(TextAlign.Center)

        Stack({ alignContent: Alignment.Center }) {
          Column({ space: 0 }) {
            SymbolGlyph($r('sys.symbol.chevron_up'))
              .fontSize(11)
              .fontColor([this.reverseOrder ? this.accentColor : this.primaryTextColor])
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(11)
              .fontColor([this.reverseOrder ? this.accentColor : this.primaryTextColor])
          }
          .alignItems(HorizontalAlign.Center)
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(this.orderToggleBackground())
        .accessibilityText(this.reverseOrder ? '切换为正序目录' : '切换为倒序目录')
        .onClick(() => this.onToggleOrder())
        .margin({ left: 4 })

        Blank()
          .layoutWeight(1)

        Text(this.progressText)
          .fontSize(12)
          .fontColor(this.subTextColor)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 16, top: 18, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  catalogChapterList() {
    Stack({ alignContent: Alignment.TopEnd }) {
      List({ space: 0, scroller: this.scroller }) {
        LazyForEach(this.source, (title: string, index: number) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(index === this.currentDisplayIndex ? '•' : '·')
                .fontSize(index === this.currentDisplayIndex ? 22 : 18)
                .fontColor(index === this.currentDisplayIndex ? this.accentColor : this.subTextColor)
                .width(18)
                .textAlign(TextAlign.Center)

              Text(title || `第${this.canonicalIndex(index) + 1}章`)
                .fontSize(15)
                .fontWeight(index === this.currentDisplayIndex ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.catalogTitleColor(index))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (this.isCached(index)) {
                Text('已缓存')
                  .fontSize(10)
                  .fontColor(this.darkMode ? '#7CC7A0' : '#1F8F55')
                  .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                  .backgroundColor(this.darkMode ? '#24382F' : '#E6F4EC')
                  .borderRadius(10)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 16, top: 14, bottom: 14 })
            .backgroundColor(index === this.currentDisplayIndex ?
              this.selectedRowBackgroundColor() : Color.Transparent)
            .border({ width: { bottom: 0.5 },
              color: this.darkMode ? '#1FFFFFFF' : '#0D000000' })
            .onClick(() => this.onSelect(index))
          }
        }, (title: string, index: number) => `${index}_${title}`)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .onScrollIndex((start: number, end: number) => {
        this.firstVisibleIndex = Math.max(0, start);
        this.visibleItemCount = Math.max(1, end - start + 1);
      })

      this.catalogScrollbar()
    }
    .layoutWeight(1)
    .width('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.listViewportHeight = Number(newValue.height);
    })
  }

  @Builder
  catalogScrollbar() {
    if (this.shouldShowScrollbar()) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column()
          .width(3)
          .height(this.listViewportHeight)
          .borderRadius(2)
          .backgroundColor(this.darkMode ? '#18FFFFFF' : '#14000000')
          .margin({ right: 3 })
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(this.scrollbarDragging ? 6 : 4)
          .height(this.thumbLength())
          .borderRadius(3)
          .backgroundColor(this.darkMode ? '#BFD5D8DE' : '#A87A6F63')
          .margin({ right: 2 })
          .translate({ y: this.displayedThumbOffset() })
          .hitTestBehavior(HitTestMode.None)
      }
      .width(24)
      .height(this.listViewportHeight)
      .zIndex(10)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.Vertical, distance: 1 })
            .onActionStart((event: GestureEvent) => this.beginScrollbarDrag(event))
            .onActionUpdate((event: GestureEvent) => this.updateScrollbarDrag(event))
            .onActionEnd((event: GestureEvent) => this.endScrollbarDrag(event))
            .onActionCancel(() => this.cancelScrollbarDrag()),
          TapGesture().onAction((event: GestureEvent) => this.jumpScrollbarToPointer(event))
        )
      )
    }
  }

  panelHeight(): number {
    const viewport = this.viewportHeight > 0 ? this.viewportHeight : 720;
    const availableHeight = Math.max(1, viewport - 12);
    const minimumHeight = Math.min(280, availableHeight);
    return Math.min(availableHeight, Math.max(minimumHeight, viewport * 0.81));
  }

  panelCornerRadius(): number {
    return ThemeRuntime.glassCornerRadius(28, 'panel');
  }

  canonicalIndex(displayIndex: number): number {
    return this.reverseOrder ? this.count - 1 - displayIndex : displayIndex;
  }

  catalogTitleColor(displayIndex: number): string {
    if (displayIndex === this.currentDisplayIndex) return this.accentColor;
    if (this.isCached(displayIndex)) return this.darkMode ? '#DDEFE5' : '#244B35';
    return this.darkMode ? '#B8BDC7' : '#333333';
  }

  selectedRowBackgroundColor(): string {
    return this.accentTint('11');
  }

  orderToggleBackground(): string {
    if (!this.reverseOrder) return this.darkMode ? '#1FFFFFFF' : '#0D000000';
    return this.accentTint(this.darkMode ? '33' : '1F');
  }

  private accentTint(alpha: string): string {
    const color = this.accentColor;
    if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
      return `#${alpha}${color.substring(1)}`;
    }
    return this.darkMode ? '#112A6FCC' : '#11007DFF';
  }

  shouldShowScrollbar(): boolean {
    return this.listViewportHeight > 0 && this.count > this.visibleItemCount;
  }

  thumbLength(): number {
    return VirtualListScrollbar.thumbLength(this.listViewportHeight, this.count, this.visibleItemCount);
  }

  thumbOffset(): number {
    return VirtualListScrollbar.thumbOffset(this.listViewportHeight, this.thumbLength(),
      this.count, this.firstVisibleIndex, this.visibleItemCount);
  }

  displayedThumbOffset(): number {
    return this.scrollbarDragging ? this.dragOffset : this.thumbOffset();
  }

  scrollbarPointerY(event: GestureEvent): number {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    return finger ? finger.localY : 0;
  }

  beginScrollbarDrag(event: GestureEvent): void {
    const thumbLength = this.thumbLength();
    const currentOffset = this.thumbOffset();
    const pointerY = this.scrollbarPointerY(event);
    this.scrollbarDragging = true;
    this.dragOffset = currentOffset;
    if (pointerY >= currentOffset && pointerY <= currentOffset + thumbLength) {
      this.pointerAnchor = pointerY - currentOffset;
    } else {
      this.pointerAnchor = thumbLength / 2;
      this.scrollToPointer(pointerY);
    }
  }

  updateScrollbarDrag(event: GestureEvent): void {
    if (!this.scrollbarDragging) return;
    this.scrollToPointer(this.scrollbarPointerY(event));
  }

  endScrollbarDrag(event: GestureEvent): void {
    if (!this.scrollbarDragging) return;
    this.scrollToPointer(this.scrollbarPointerY(event));
    this.scrollbarDragging = false;
  }

  cancelScrollbarDrag(): void {
    this.scrollbarDragging = false;
  }

  jumpScrollbarToPointer(event: GestureEvent): void {
    this.pointerAnchor = this.thumbLength() / 2;
    this.scrollToPointer(this.scrollbarPointerY(event));
  }

  scrollToPointer(pointerY: number): void {
    const thumbLength = this.thumbLength();
    const offset = VirtualListScrollbar.clampThumbOffset(this.listViewportHeight, thumbLength,
      pointerY - this.pointerAnchor);
    this.dragOffset = offset;
    const targetIndex = VirtualListScrollbar.firstVisibleIndex(this.listViewportHeight, thumbLength,
      this.count, this.visibleItemCount, offset);
    this.firstVisibleIndex = targetIndex;
    const now = Date.now();
    if (this.scrollbarDragging && now - this.lastScrollbarScrollAt < CATALOG_SCROLLBAR_MIN_SCROLL_INTERVAL_MS) {
      return;
    }
    this.lastScrollbarScrollAt = now;
    try {
      this.scroller.scrollToIndex(targetIndex, false, ScrollAlign.START);
    } catch (_) {}
  }
}
