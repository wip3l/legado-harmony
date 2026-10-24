import { LocalBookService } from '../../core/book/LocalBookService';
import { ReaderComicColorSession, ComicColorCandidate } from '../../core/reader/ReaderComicColorSession';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderImageMarker } from '../../core/book/ReaderImageMarker';
import {
  ReaderComicImageItem, ReaderComicImageSizes, ReaderComicInfoBadge, ReaderComicRetryRegistry, ReaderPendingImageHint
} from './ReaderComicView';

/** 阅读页向翻页视图发出的指令（点击翻页、音量键）；视图挂载时填入实现。 */
export class ReaderComicPagedController {
  turn: (direction: number) => void = () => {};
  /** 跨章切换没有成功：从停住的相邻章节退回本话。 */
  cancelCross: () => void = () => {};
}

/**
 * 漫画单页翻页视图。宽屏时两页并排为一个跨页；右→左模式下“下一页”在左边。
 * 只渲染当前跨页和左右各一个。越过本章首尾时：阅读页已预先切好相邻章节的页，那一格直接显示
 * 下一话第一个跨页或上一话最后一个跨页，翻过去后停在那里等阅读页把它设为当前章（onCrossChapter）；
 * 相邻章节还没准备好时那一格显示章节提示卡，松手后由阅读页正常切章（onBoundary）。
 * 相邻格与切换后的当前格使用同一个键，切换前后图片组件原样保留，不会重新加载。
 * 当前页码以阅读页的 pageIndex 为准，视图翻完一页后通过 onPageChanged 回报跨页首页。
 */
@Component
export struct ReaderComicPagedView {
  colorSession: ReaderComicColorSession | null = null;
  private colorTimer: number = -1;
  private colorSpread: string = '';

  private updateColorViewport(): void {
    if (!this.colorSession?.foreground) return;
    if (this.animating || this.dragOffset !== 0) this.colorSession.motion();
    const key = `${this.chapterIndex}_${this.spreadIndex}`;
    if (key !== this.colorSpread) {
      this.colorSpread = key;
      this.colorSession.clearCompare();
    }
    const candidates: ComicColorCandidate[] = [];
    const start = this.spreadIndex * this.spreadSize();
    for (let i = start; i < Math.min(this.pages.length, start + this.spreadSize() * 3); i++) {
      candidates.push(new ComicColorCandidate(ReaderComicColorSession.source(this.pages[i]),
        i < start + this.spreadSize(), i - start, `${i + 1}`));
    }
    this.colorSession.update(candidates);
  }
  controller: ReaderComicPagedController = new ReaderComicPagedController();
  @Prop @Watch('onLayoutChanged') pages: string[] = [];
  @Prop @Watch('onPageIndexChanged') pageIndex: number = 0;
  @Prop @Watch('onLayoutChanged') chapterIndex: number = 0;
  @Prop @Watch('onLayoutChanged') viewWidth: number = 0;
  @Prop viewHeight: number = 0;
  @Prop @Watch('onLayoutChanged') dualPage: boolean = false;
  @Prop rightToLeft: boolean = false;
  @Prop doubleTapZoom: boolean = true;
  /** 漫画超分（会员功能）。 */
  @Prop superResolution: boolean = false;
  /** 本书繁→简。 */
  @Prop textConvert: boolean = false;
  @Prop surfaceColor: string = '#000000';
  @Prop textColor: string = '#E6E6E6';
  @Prop hintColor: string = '#99FFFFFF';
  @Prop interactive: boolean = true;
  @Prop panDistance: number = 12;
  @Prop transitionOpacity: number = 1;
  /** 相邻章节标题；空串表示该方向没有章节。 */
  @Prop prevChapterTitle: string = '';
  @Prop nextChapterTitle: string = '';
  /** 阅读页预先切好的相邻章节分页；空数组表示还没准备好。 */
  @Prop prevChapterPages: string[] = [];
  @Prop nextChapterPages: string[] = [];
  @Prop infoVisible: boolean = false;
  @Prop infoChapter: string = '';
  @Prop infoPage: string = '';
  @Prop infoTime: string = '';
  @Prop infoBattery: number = -1;
  @Prop infoBottomInset: number = 6;
  /** 网络图片向后预先加载的页数。 */
  @Prop preloadCount: number = 5;
  onImageLongPress: (source: string, reload: () => void, snapshotId: string) => void = () => {};
  onImageDenied: (chapterIndex: number) => void = () => {};
  onPageChanged: (pageIndex: number) => void = () => {};
  /** 越过本章首尾且相邻章节没准备好：1 为下一话，-1 为上一话，由阅读页正常切章。 */
  onBoundary: (direction: number) => void = () => {};
  /** 已翻到预先装好的相邻章节并停在那里：阅读页把它设为当前章。 */
  onCrossChapter: (direction: number) => void = () => {};
  /** 坐标相对视图左上角。 */
  onTap: (x: number, y: number, width: number, height: number) => void = () => {};
  static readonly MAX_ZOOM: number = 4;
  static readonly DOUBLE_TAP_ZOOM: number = 2;
  @State private spreadIndex: number = 0;
  @State private dragOffset: number = 0;
  @State private zoomScale: number = 1;
  @State private zoomX: number = 0;
  @State private zoomY: number = 0;
  private retryRegistry: ReaderComicRetryRegistry = new ReaderComicRetryRegistry();
  private animating: boolean = false;
  private touchDragged: boolean = false;
  private pinching: boolean = false;
  private pinchBaseScale: number = 1;
  private pinchBaseX: number = 0;
  private pinchBaseY: number = 0;
  private pinchFocusX: number = 0;
  private pinchFocusY: number = 0;
  private zoomPanActive: boolean = false;
  private panLastX: number = 0;
  private panLastY: number = 0;
  private panResync: boolean = false;

  aboutToAppear(): void {
    this.colorTimer = setInterval((): void => this.updateColorViewport(), 250);
    this.spreadIndex = this.spreadOf(this.pageIndex);
    this.controller.turn = (direction: number): void => this.turn(direction);
    this.controller.cancelCross = (): void => {
      this.animating = false;
      this.settleBack();
    };
  }

  aboutToDisappear(): void {
    clearInterval(this.colorTimer);
    this.colorSession?.update([]);
    this.colorSession?.touch(false);
    this.controller.turn = () => {};
    this.controller.cancelCross = () => {};
  }

  onLayoutChanged(): void {
    // 章节或分页变了（包括跨章停住后阅读页发布了新章）：停住的位移归零，按新页码重新定位。
    this.animating = false;
    this.dragOffset = 0;
    this.applyZoom(1, 0, 0);
    this.spreadIndex = this.spreadOf(this.pageIndex);
  }

  onPageIndexChanged(): void {
    if (this.animating) return;
    const target = this.spreadOf(this.pageIndex);
    if (target === this.spreadIndex) return;
    this.dragOffset = 0;
    this.applyZoom(1, 0, 0);
    this.spreadIndex = target;
  }

  private spreadSize(): number {
    return this.dualPage ? 2 : 1;
  }

  private spreadCount(): number {
    return Math.ceil(this.pages.length / this.spreadSize());
  }

  private spreadOf(pageIndex: number): number {
    const count = this.spreadCount();
    if (count <= 0) return 0;
    return Math.max(0, Math.min(count - 1, Math.floor(Math.max(0, pageIndex) / this.spreadSize())));
  }

  /** 跨页内的页码，按屏幕从左到右排列。 */
  private spreadPages(spread: number): number[] {
    const result: number[] = [];
    const first = spread * this.spreadSize();
    for (let page = first; page < Math.min(this.pages.length, first + this.spreadSize()); page++) {
      result.push(page);
    }
    return this.rightToLeft ? result.reverse() : result;
  }

  /** 越出本章的那一格能否直接显示相邻章节。 */
  private hasNeighbor(direction: number): boolean {
    return direction > 0 ? this.hasChapter(1) && this.nextChapterPages.length > 0 :
      this.hasChapter(-1) && this.prevChapterPages.length > 0;
  }

  /** 相邻章节在这一格显示的跨页序号：下一话第一个，上一话最后一个。 */
  private neighborSpread(direction: number): number {
    if (direction > 0) return 0;
    return Math.max(0, Math.ceil(this.prevChapterPages.length / this.spreadSize()) - 1);
  }

  private neighborSpreadPages(direction: number): number[] {
    const pages = direction > 0 ? this.nextChapterPages : this.prevChapterPages;
    const result: number[] = [];
    const first = this.neighborSpread(direction) * this.spreadSize();
    for (let page = first; page < Math.min(pages.length, first + this.spreadSize()); page++) result.push(page);
    return this.rightToLeft ? result.reverse() : result;
  }

  /** 格子的键：相邻章节格与它成为当前章后的格子同键，切换时组件得以保留。 */
  private slotKey(spread: number): string {
    if (spread >= 0 && spread < this.spreadCount()) return `${this.chapterIndex}_${this.spreadSize()}_${spread}`;
    const direction = spread < 0 ? -1 : 1;
    if (this.hasNeighbor(direction)) {
      return `${this.chapterIndex + direction}_${this.spreadSize()}_${this.neighborSpread(direction)}`;
    }
    return `card_${this.chapterIndex}_${direction}`;
  }

  private viewW(): number {
    return Math.max(1, this.viewWidth);
  }

  private viewH(): number {
    return Math.max(1, this.viewHeight);
  }

  /** 第 k 个相邻跨页（k = 跨页序号 − 当前序号）在屏幕上的横向位置。 */
  private slotX(spread: number): number {
    const k = spread - this.spreadIndex;
    return (this.rightToLeft ? -k : k) * this.viewW() + this.dragOffset;
  }

  /** 翻到 direction 方向时当前跨页要移到的位置。 */
  private turnOffset(direction: number): number {
    return (this.rightToLeft ? direction : -direction) * this.viewW();
  }

  /** 手指横向位移对应的阅读方向：左→右模式向左拖是下一页，右→左模式相反。 */
  private dragDirection(offsetX: number): number {
    if (offsetX === 0) return 0;
    const leftward = offsetX < 0;
    return this.rightToLeft ? (leftward ? -1 : 1) : (leftward ? 1 : -1);
  }

  private hasChapter(direction: number): boolean {
    return direction > 0 ? !!this.nextChapterTitle : !!this.prevChapterTitle;
  }

  private turn(direction: number): void {
    if (this.animating || this.pages.length === 0 || direction === 0) return;
    const target = this.spreadIndex + direction;
    if (target < 0 || target >= this.spreadCount()) {
      if (this.hasNeighbor(direction)) {
        this.applyZoom(1, 0, 0);
        this.animateCross(direction);
      } else {
        this.onBoundary(direction);
      }
      return;
    }
    this.applyZoom(1, 0, 0);
    this.animateTurn(direction);
  }

  /** 翻进预先装好的相邻章节后停住，等阅读页发布新章（onLayoutChanged）或取消（cancelCross）。 */
  private animateCross(direction: number): void {
    this.animating = true;
    animateTo({
      duration: 240,
      curve: Curve.Friction,
      onFinish: () => this.onCrossChapter(direction)
    }, () => {
      this.dragOffset = this.turnOffset(direction);
    });
  }

  private animateTurn(direction: number): void {
    this.animating = true;
    animateTo({
      duration: 240,
      curve: Curve.Friction,
      onFinish: () => this.finishTurn(direction)
    }, () => {
      this.dragOffset = this.turnOffset(direction);
    });
  }

  private finishTurn(direction: number): void {
    // 先换当前序号再归零位移：相邻格按新序号重新定位后恰好落在动画终点，不会闪动。
    this.spreadIndex = Math.max(0, Math.min(this.spreadCount() - 1, this.spreadIndex + direction));
    this.dragOffset = 0;
    this.animating = false;
    this.onPageChanged(this.spreadIndex * this.spreadSize());
  }

  private settleBack(): void {
    if (this.dragOffset === 0) return;
    this.animating = true;
    animateTo({
      duration: 200,
      curve: Curve.Friction,
      onFinish: () => {
        this.animating = false;
      }
    }, () => {
      this.dragOffset = 0;
    });
  }

  private zoomed(): boolean {
    return this.zoomScale > 1.001;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private applyZoom(scale: number, x: number, y: number): void {
    let nextScale = this.clamp(scale, 1, ReaderComicPagedView.MAX_ZOOM);
    if (nextScale <= 1.001) nextScale = 1;
    const boundX = (nextScale - 1) * this.viewW() / 2;
    const boundY = (nextScale - 1) * this.viewH() / 2;
    this.zoomScale = nextScale;
    this.zoomX = this.clamp(x, -boundX, boundX);
    this.zoomY = this.clamp(y, -boundY, boundY);
  }

  /** 把缩放前位于 origin 的点放到 focus 处，同时从 base 状态缩放到 nextScale。 */
  private zoomAround(focusX: number, focusY: number, originX: number, originY: number, baseScale: number,
    baseX: number, baseY: number, nextScale: number): void {
    const scale = this.clamp(nextScale, 1, ReaderComicPagedView.MAX_ZOOM);
    const ratio = scale / Math.max(0.001, baseScale);
    const centerX = this.viewW() / 2;
    const centerY = this.viewH() / 2;
    this.applyZoom(scale, focusX - centerX - ratio * (originX - centerX - baseX),
      focusY - centerY - ratio * (originY - centerY - baseY));
  }

  private tapPoint(event: GestureEvent): number[] {
    const finger = event.fingerList && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    return finger ? [finger.localX, finger.localY] : [this.viewW() / 2, this.viewH() / 2];
  }

  private retryKey(pageIndex: number): string {
    return `${this.chapterIndex}_${pageIndex}`;
  }

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) this.colorSession?.touch(true);
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.colorSession?.touch(false);
    if (event.type === TouchType.Down && event.touches.length <= 1) this.touchDragged = false;
  }

  private handleDoubleTap(event: GestureEvent): void {
    if (this.touchDragged || this.animating) return;
    if (this.zoomed()) {
      animateTo({ duration: 220, curve: Curve.Friction }, () => this.applyZoom(1, 0, 0));
      return;
    }
    const point = this.tapPoint(event);
    animateTo({ duration: 220, curve: Curve.Friction }, () => {
      this.zoomAround(point[0], point[1], point[0], point[1], 1, 0, 0, ReaderComicPagedView.DOUBLE_TAP_ZOOM);
    });
  }

  /** 按阅读方向排在当前跨页之后、需要预先下载的网络图片地址。 */
  private prefetchSources(): string[] {
    return this.prefetchMarkerSources().filter((source: string): boolean => ReaderComicImageSizes.isRemote(source));
  }

  /** 预加载范围里还在渐进加载的图片：登记为屏幕附近，先于本章其余图片处理。 */
  private prefetchPendingRaws(): string[] {
    return this.prefetchMarkerSources().map((source: string): string => ReaderImageMarker.pendingRaw(source))
      .filter((raw: string): boolean => !!raw);
  }

  private prefetchMarkerSources(): string[] {
    const result: string[] = [];
    const first = (this.spreadIndex + 2) * this.spreadSize();
    // 本话剩下的页不够时接着预取下一话（第一个跨页已在相邻格里显示，从它之后开始）。
    const nextStart = this.spreadSize();
    const total = this.pages.length + Math.max(0, this.nextChapterPages.length - nextStart);
    for (let page = first; page < Math.min(total, first + this.preloadCount); page++) {
      const text = (page < this.pages.length ? this.pages[page] :
        this.nextChapterPages[nextStart + page - this.pages.length] || '').trim();
      if (!LocalBookService.isEpubImageMarker(text)) continue;
      result.push(ReaderImageMarker.parse(text).source);
    }
    return result;
  }

  private handleLongPress(event: GestureEvent): void {
    if (this.pinching || this.animating) return;
    this.touchDragged = true;
    const point = this.tapPoint(event);
    const centerX = this.viewW() / 2;
    const slotX = centerX + (point[0] - centerX - this.zoomX) / this.zoomScale;
    const pages = this.spreadPages(this.spreadIndex);
    if (pages.length === 0) return;
    const boxWidth = this.viewW() / pages.length;
    const pageIndex = pages[Math.max(0, Math.min(pages.length - 1, Math.floor(slotX / boxWidth)))];
    const text = (this.pages[pageIndex] || '').trim();
    if (!LocalBookService.isEpubImageMarker(text)) return;
    const key = this.retryKey(pageIndex);
    this.onImageLongPress(ReaderImageMarker.parse(text).source, (): void => this.retryRegistry.reload(key),
      ReaderComicImageItem.snapshotId(key));
  }

  private handleSingleTap(event: GestureEvent): void {
    if (this.touchDragged || this.animating) return;
    const point = this.tapPoint(event);
    // 失败提示被交互层盖住：点中某页居中的提示文字才重试，其余位置交给阅读页翻页或呼出菜单。
    const centerX = this.viewW() / 2;
    const centerY = this.viewH() / 2;
    const slotX = centerX + (point[0] - centerX - this.zoomX) / this.zoomScale;
    const slotY = centerY + (point[1] - centerY - this.zoomY) / this.zoomScale;
    const pages = this.spreadPages(this.spreadIndex);
    if (pages.length > 0 && Math.abs(slotY - centerY) <= 44) {
      const boxWidth = this.viewW() / pages.length;
      const column = Math.max(0, Math.min(pages.length - 1, Math.floor(slotX / boxWidth)));
      const nearHint = Math.abs(slotX - (column + 0.5) * boxWidth) <= boxWidth * 0.35;
      if (nearHint && this.retryRegistry.retry(this.retryKey(pages[column]))) return;
    }
    this.onTap(point[0], point[1], this.viewW(), this.viewH());
  }

  private handlePinchStart(event: GestureEvent): void {
    if (this.animating) return;
    this.pinching = true;
    this.touchDragged = true;
    this.panResync = true;
    if (this.dragOffset !== 0) {
      this.dragOffset = 0;
    }
    this.zoomPanActive = true;
    this.pinchBaseScale = this.zoomScale;
    this.pinchBaseX = this.zoomX;
    this.pinchBaseY = this.zoomY;
    this.pinchFocusX = event.pinchCenterX;
    this.pinchFocusY = event.pinchCenterY;
  }

  private handlePinchUpdate(event: GestureEvent): void {
    if (!this.pinching) return;
    this.zoomAround(event.pinchCenterX, event.pinchCenterY, this.pinchFocusX, this.pinchFocusY,
      this.pinchBaseScale, this.pinchBaseX, this.pinchBaseY, this.pinchBaseScale * event.scale);
  }

  private handlePinchEnd(): void {
    if (!this.pinching) return;
    this.pinching = false;
    this.panResync = true;
    if (this.zoomScale < 1.05) {
      animateTo({ duration: 200, curve: Curve.Friction }, () => this.applyZoom(1, 0, 0));
    }
  }

  private handlePanStart(): void {
    this.touchDragged = true;
    this.panLastX = 0;
    this.panLastY = 0;
    this.panResync = false;
    this.zoomPanActive = this.zoomed() || this.pinching;
  }

  private handlePanUpdate(event: GestureEvent): void {
    if (this.animating) return;
    if (!this.zoomPanActive) {
      // 本章首尾外没有章节可去时加阻尼，提示卡只露出一部分。
      const direction = this.dragDirection(event.offsetX);
      const target = this.spreadIndex + direction;
      const outside = target < 0 || target >= this.spreadCount();
      this.dragOffset = outside && !this.hasChapter(direction) ? event.offsetX * 0.3 : event.offsetX;
      return;
    }
    if (this.pinching || this.panResync) {
      this.panLastX = event.offsetX;
      this.panLastY = event.offsetY;
      this.panResync = this.pinching;
      return;
    }
    const boundX = (this.zoomScale - 1) * this.viewW() / 2;
    const boundY = (this.zoomScale - 1) * this.viewH() / 2;
    this.zoomX = this.clamp(this.zoomX + event.offsetX - this.panLastX, -boundX, boundX);
    this.zoomY = this.clamp(this.zoomY + event.offsetY - this.panLastY, -boundY, boundY);
    this.panLastX = event.offsetX;
    this.panLastY = event.offsetY;
  }

  private handlePanEnd(event: GestureEvent): void {
    const zoomPan = this.zoomPanActive;
    this.zoomPanActive = false;
    if (zoomPan || this.animating) return;
    const offset = this.dragOffset;
    const direction = this.dragDirection(offset);
    const flung = Math.abs(event.velocityX) > 500 && Math.sign(event.velocityX) === Math.sign(offset);
    if (direction === 0 || (Math.abs(offset) < this.viewW() * 0.18 && !flung)) {
      this.settleBack();
      return;
    }
    const target = this.spreadIndex + direction;
    if (target >= 0 && target < this.spreadCount()) {
      this.animateTurn(direction);
      return;
    }
    if (this.hasNeighbor(direction)) {
      this.animateCross(direction);
      return;
    }
    this.settleBack();
    if (this.hasChapter(direction)) this.onBoundary(direction);
  }

  private handlePanCancel(): void {
    const zoomPan = this.zoomPanActive;
    this.zoomPanActive = false;
    if (!zoomPan) this.settleBack();
  }

  @Builder
  pageView(pages: string[], chapterIndex: number, pageIndex: number, boxWidth: number) {
    if (LocalBookService.isEpubImageMarker((pages[pageIndex] || '').trim())) {
      ReaderComicImageItem({
        marker: (pages[pageIndex] || '').trim(),
        colorSession: this.colorSession,
        viewWidth: boxWidth,
        viewHeight: this.viewH(),
        boxWidth: boxWidth,
        boxHeight: this.viewH(),
        pageLabel: `${pageIndex + 1}`,
        hintColor: this.hintColor,
        retryKey: `${chapterIndex}_${pageIndex}`,
        superResolution: this.superResolution,
        textConvert: this.textConvert,
        retryRegistry: this.retryRegistry,
        onDenied: (): void => this.onImageDenied(chapterIndex)
      })
    } else {
      Text(LocalBookService.stripEpubImageMarkers(pages[pageIndex] || '').trim())
        .fontSize(AppFontSize.BODY_LARGE)
        .lineHeight(AppFontSize.BODY_LARGE * 1.7)
        .fontColor(this.textColor)
        .width(boxWidth)
        .height(this.viewH())
        .padding({ left: AppSpacing.XXXL, right: AppSpacing.XXXL, top: 56, bottom: 56 })
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  boundaryCard(direction: number) {
    Column({ space: AppSpacing.LG }) {
      Text(direction > 0 ? '本话完' : '本话开头')
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor)
      if (this.hasChapter(direction)) {
        Text(direction > 0 ? '继续翻页进入下一话' : '继续翻页回到上一话')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.hintColor)
        Text(direction > 0 ? this.nextChapterTitle : this.prevChapterTitle)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      } else {
        Text(direction > 0 ? '已经是最后一话' : '已经是第一话')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.hintColor)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 40, right: 40 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  slot(spread: number) {
    Stack() {
      if (spread >= 0 && spread < this.spreadCount()) {
        Row() {
          ForEach(this.spreadPages(spread), (pageIndex: number) => {
            this.pageView(this.pages, this.chapterIndex, pageIndex, this.viewW() / this.spreadPages(spread).length)
          }, (pageIndex: number) => `${pageIndex}_${this.spreadPages(spread).length}`)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.hasNeighbor(spread < 0 ? -1 : 1)) {
        Row() {
          ForEach(this.neighborSpreadPages(spread < 0 ? -1 : 1), (pageIndex: number) => {
            this.pageView(spread < 0 ? this.prevChapterPages : this.nextChapterPages,
              this.chapterIndex + (spread < 0 ? -1 : 1), pageIndex,
              this.viewW() / this.neighborSpreadPages(spread < 0 ? -1 : 1).length)
          }, (pageIndex: number) => `${pageIndex}_${this.neighborSpreadPages(spread < 0 ? -1 : 1).length}`)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        this.boundaryCard(spread < 0 ? -1 : 1)
      }
    }
    .width(this.viewW())
    .height(this.viewH())
    .position({ x: this.slotX(spread), y: 0 })
    .scale(spread === this.spreadIndex ? { x: this.zoomScale, y: this.zoomScale } : { x: 1, y: 1 })
    .translate(spread === this.spreadIndex ? { x: this.zoomX, y: this.zoomY } : { x: 0, y: 0 })
  }

  @Builder
  interactionLayer(doubleTap: boolean) {
    if (doubleTap) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
        .gesture(
          GestureGroup(GestureMode.Parallel,
            GestureGroup(GestureMode.Exclusive,
              TapGesture({ count: 2, distanceThreshold: this.panDistance })
                .onAction((event: GestureEvent) => this.handleDoubleTap(event)),
              TapGesture({ count: 1, distanceThreshold: this.panDistance })
                .onAction((event: GestureEvent) => this.handleSingleTap(event))
            ),
            LongPressGesture({ duration: 500 })
              .onAction((event: GestureEvent) => this.handleLongPress(event)),
            PinchGesture({ fingers: 2 })
              .onActionStart((event: GestureEvent) => this.handlePinchStart(event))
              .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
              .onActionEnd(() => this.handlePinchEnd())
              .onActionCancel(() => this.handlePinchEnd()),
            PanGesture({ direction: PanDirection.All, distance: this.panDistance })
              .onActionStart(() => this.handlePanStart())
              .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
              .onActionEnd((event: GestureEvent) => this.handlePanEnd(event))
              .onActionCancel(() => this.handlePanCancel())
          )
        )
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
        .gesture(
          GestureGroup(GestureMode.Parallel,
            TapGesture({ count: 1, distanceThreshold: this.panDistance })
              .onAction((event: GestureEvent) => this.handleSingleTap(event)),
            LongPressGesture({ duration: 500 })
              .onAction((event: GestureEvent) => this.handleLongPress(event)),
            PinchGesture({ fingers: 2 })
              .onActionStart((event: GestureEvent) => this.handlePinchStart(event))
              .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
              .onActionEnd(() => this.handlePinchEnd())
              .onActionCancel(() => this.handlePinchEnd()),
            PanGesture({ direction: PanDirection.All, distance: this.panDistance })
              .onActionStart(() => this.handlePanStart())
              .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
              .onActionEnd((event: GestureEvent) => this.handlePanEnd(event))
              .onActionCancel(() => this.handlePanCancel())
          )
        )
    }
  }

  build() {
    Stack() {
      Stack() {
        ForEach([this.spreadIndex - 1, this.spreadIndex, this.spreadIndex + 1], (spread: number) => {
          this.slot(spread)
        }, (spread: number) => this.slotKey(spread))
      }
      .width('100%')
      .height('100%')
      .opacity(this.transitionOpacity)

      // 预先下载后面几页的网络图片：1px 透明图片只为触发下载与缓存，autoResize 让解码也按 1px 进行。
      ForEach(this.prefetchSources(), (source: string) => {
        Image(source)
          .width(1)
          .height(1)
          .opacity(0)
          .autoResize(true)
          .position({ x: 0, y: 0 })
          .hitTestBehavior(HitTestMode.None)
      }, (source: string) => source)

      ForEach(this.prefetchPendingRaws(), (raw: string) => {
        ReaderPendingImageHint({ raw: raw })
      }, (raw: string) => raw)

      if (this.infoVisible) {
        ReaderComicInfoBadge({
          chapterText: this.infoChapter,
          pageText: this.infoPage,
          timeText: this.infoTime,
          battery: this.infoBattery
        })
          .position({ right: 10, bottom: this.infoBottomInset })
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.interactive) {
        this.interactionLayer(this.doubleTapZoom)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfaceColor)
    .clip(true)
  }
}
