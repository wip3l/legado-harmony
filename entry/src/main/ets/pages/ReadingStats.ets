import { router, promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { appDb } from '../model/data/AppDatabase';
import { ReadStatsTracker, readStatsTracker } from '../core/stats/ReadStatsTracker';
import { HdsFeedback } from '../utils/HdsFeedback';
import { BookCover } from '../components/book/BookCover';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';

const STATS_MODES: string[] = ['day', 'week', 'month'];
const STATS_MODE_LABELS: string[] = ['日', '周', '月'];
const WEEKDAY_LABELS: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const DAY_MS: number = 86400000;

class StatsRange {
  startTs: number = 0;
  endTs: number = 0;
}

class StatBookItem {
  bookUrl: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  durationMs: number = 0;
  percent: number = 0;
}

@Entry
@Component
struct ReadingStatsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State mode: string = 'week';
  @State anchorTs: number = Date.now();
  @State loading: boolean = true;
  @State totalMs: number = 0;
  @State activeDays: number = 0;
  @State items: StatBookItem[] = [];
  @State showItemActionMenu: boolean = false;
  @State actionBookUrl: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;

  aboutToAppear(): void {
    // 用户可能正听着书进本页，先结算一次未落库的时长再查询。
    readStatsTracker.flush();
    this.loadStats();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  onBackPress(): boolean {
    if (this.showItemActionMenu) {
      this.closeItemActions();
      return true;
    }
    return false;
  }

  async loadStats(silent: boolean = false): Promise<void> {
    if (!silent) this.loading = true;
    try {
      await appDb.init(getContext(this));
      const range = this.currentRange();
      const startKey = ReadStatsTracker.dayKeyOf(range.startTs);
      const endKey = ReadStatsTracker.dayKeyOf(range.endTs);
      const rows = await appDb.getReadStatsByDayRange(startKey, endKey);

      const durationByBook = new Map<string, number>();
      const activeDayKeys = new Set<string>();
      let total = 0;
      rows.forEach((row) => {
        if (row.durationMs <= 0) return;
        durationByBook.set(row.bookUrl, (durationByBook.get(row.bookUrl) || 0) + row.durationMs);
        activeDayKeys.add(row.dayKey);
        total += row.durationMs;
      });

      const items: StatBookItem[] = [];
      durationByBook.forEach((duration: number, bookUrl: string) => {
        const item = new StatBookItem();
        item.bookUrl = bookUrl;
        item.durationMs = duration;
        item.percent = total > 0 ? Math.max(1, Math.round(duration * 100 / total)) : 0;
        items.push(item);
      });
      items.sort((a: StatBookItem, b: StatBookItem): number => b.durationMs - a.durationMs);

      const bookUrls: string[] = [];
      durationByBook.forEach((_duration: number, bookUrl: string) => {
        bookUrls.push(bookUrl);
      });
      if (bookUrls.length > 0) {
        const metaMap = await appDb.getReadStatsBookMeta(bookUrls);
        items.forEach((item: StatBookItem) => {
          const meta = metaMap.get(item.bookUrl);
          if (meta) {
            item.name = meta.name || '未命名书籍';
            item.author = meta.author || '';
            item.coverUrl = meta.coverUrl || '';
          } else {
            item.name = '已删除书籍';
            item.author = '';
            item.coverUrl = '';
          }
        });
      }

      this.totalMs = total;
      this.activeDays = activeDayKeys.size;
      this.items = items;
    } catch (e) {
      console.warn('读取阅读统计失败:', e);
      this.totalMs = 0;
      this.activeDays = 0;
      this.items = [];
    } finally {
      this.loading = false;
    }
  }


  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '阅读统计', content: () => {
        this.pageContent()
      } })

      if (this.showItemActionMenu) {
        this.itemActionMenu()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .onAreaChange((_oldValue: Area, newValue: Area) => this.updateContextViewport(newValue))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Column() {
      this.summaryCard()

      this.sectionTitle('书籍排行')
      if (this.loading) {
        this.loadingCard()
      } else if (this.items.length === 0) {
        this.emptyCard()
      } else {
        // 行需要侧滑，所以用 List；高度随内容撑开，滚动仍交给外层 Scroll。
        List() {
          ForEach(this.items, (item: StatBookItem) => {
            if (deviceInfo.sdkApiVersion >= 26) {
              HdsListItem({
                customItemBuilder: (): void => {
                  this.bookRow(item)
                },
                swipeActionOptions: this.itemSwipeActions(item)
              })
            }
            if (deviceInfo.sdkApiVersion < 26) {
              ListItem() {
                this.bookRow(item)
              }
              .swipeAction({
                end: {
                  builder: (): void => {
                    this.itemDeleteSwipeButton(item)
                  },
                  actionAreaDistance: 64,
                  onAction: (): void => {
                    this.confirmDeleteItem(item);
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
            }
          }, (item: StatBookItem) => `${item.bookUrl}_${item.durationMs}_${item.percent}`)
        }
        .divider({ strokeWidth: 0.5, color: this.dividerColor(), startMargin: 68, endMargin: 16 })
        .edgeEffect(EdgeEffect.None)
        .scrollBar(BarState.Off)
        .enableScrollInteraction(false)
        .width('calc(100% - 24vp)')
        .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(ThemeRuntime.cardRadius())
        .clip(true)
        .backgroundColor(this.cardColor())
      }
    }
    .width('100%')
  }

  @Builder
  summaryCard() {
    Column({ space: AppSpacing.LG }) {
      Row() {
        Row({ space: AppSpacing.XS }) {
          ForEach(STATS_MODES, (value: string, index: number) => {
            Text(STATS_MODE_LABELS[index])
              .fontSize(AppFontSize.BODY)
              .fontWeight(this.mode === value ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.mode === value ? Color.White : this.subTextColor())
              .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
              .borderRadius(ThemeRuntime.buttonRadius())
              .backgroundColor(this.mode === value ? this.accentColor() : Color.Transparent)
              .onClick(() => {
                if (this.mode === value) return;
                this.mode = value;
                this.loadStats();
              })
          }, (value: string) => value)
        }
        .padding(AppSpacing.XXS)
        .borderRadius(17)
        .backgroundColor(this.softColor())
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
          .padding(AppSpacing.MD)
          .onClick(() => {
            this.shiftPeriod(-1);
          })

        Text(this.periodTitle())
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.canGoForward()) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([this.subTextColor()])
            .padding(AppSpacing.MD)
            .onClick(() => {
              this.shiftPeriod(1);
            })
        } else {
          Row()
            .width(34)
            .height(34)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: AppSpacing.SM }) {
        Text(this.formatDuration(this.totalMs))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Text(this.summarySubtitle())
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('calc(100% - 24vp)')
    .padding(AppSpacing.XL)
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  bookRow(item: StatBookItem) {
    Row({ space: AppSpacing.LG }) {
      BookCover({ bookUrl: item.bookUrl, name: item.name, author: item.author,
        coverUrl: item.coverUrl, placeholderColor: this.accentColor() })
        .width(40)
        .height(56)

      Column({ space: AppSpacing.SM }) {
        Row({ space: AppSpacing.MD }) {
          Text(item.name)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.formatDuration(item.durationMs))
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
        }
        .width('100%')

        Row() {
          Text(`${item.percent}%`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .layoutWeight(1)
          if (item.author) {
            Text(item.author)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')

        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(4)
            .borderRadius(2)
            .backgroundColor(this.softColor())
          Row()
            .width(`${item.percent}%`)
            .height(4)
            .borderRadius(2)
            .backgroundColor(this.accentColor())
        }
        .width('100%')
        .clip(true)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Top)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          this.openItemActions(item, event);
        })
    )
  }

  private itemSwipeActions(item: StatBookItem): HdsSwipeActionOptions {
    return { icons: [
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode),
        iconOptions: { accessibilityText: '删除记录' },
        onAction: () => this.confirmDeleteItem(item) }
    ] };
  }

  @Builder
  itemDeleteSwipeButton(item: StatBookItem) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
    .onClick(() => {
      this.confirmDeleteItem(item);
    })
  }

  @Builder
  itemActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#38000000' : '#18FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('button', 12))
        .onClick(() => this.closeItemActions())
      Column() {
        Row({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([ThemeRuntime.dangerColor(this.appDarkMode)])
            .width(24)
          Text('删除')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
            .layoutWeight(1)
        }
        .width('100%')
        .height(44)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.confirmDeleteActionItem())
      }
      .width(148)
      .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.contextMenuLeft(148), y: this.contextMenuTop(56) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  loadingCard() {
    Row({ space: AppSpacing.MD }) {
      LoadingProgress()
        .width(22)
        .height(22)
        .color(this.accentColor())
      Text('正在统计阅读时长')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
    }
    .width('calc(100% - 24vp)')
    .height(88)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  emptyCard() {
    Column({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.timer'))
        .fontSize(28)
        .fontColor([this.subTextColor()])
      Text('该时段暂无阅读记录')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
    }
    .width('calc(100% - 24vp)')
    .constraintSize({ minHeight: 120 })
    .padding({ top: AppSpacing.XXL, bottom: AppSpacing.XXL })
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .justifyContent(FlexAlign.Center)
  }

  openItemActions(item: StatBookItem, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionBookUrl = item.bookUrl;
    this.showItemActionMenu = true;
  }

  closeItemActions(): void {
    this.showItemActionMenu = false;
    this.actionBookUrl = '';
  }

  confirmDeleteActionItem(): void {
    const item = this.items.find((value: StatBookItem): boolean => value.bookUrl === this.actionBookUrl);
    this.closeItemActions();
    if (item) this.confirmDeleteItem(item);
  }

  async confirmDeleteItem(item: StatBookItem): Promise<void> {
    const confirmation = await promptAction.showDialog({
      title: '删除阅读记录',
      message: `确定删除“${item.name}”在 ${this.periodTitle()} 的阅读时长记录吗？不会影响书籍本身。`,
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
    });
    if (confirmation.index !== 1) return;
    try {
      const range = this.currentRange();
      await appDb.deleteReadStatsForBook(item.bookUrl,
        ReadStatsTracker.dayKeyOf(range.startTs), ReadStatsTracker.dayKeyOf(range.endTs));
      await this.loadStats(true);
      HdsFeedback.showToast('记录已删除');
    } catch (e) {
      console.warn('删除阅读统计失败:', e);
      HdsFeedback.showToast('删除失败');
    }
  }

  updateContextViewport(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
    if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
  }

  contextMenuLeft(menuWidth: number): number {
    return Math.max(12, Math.min(this.contextMenuX - 18, this.contextViewportWidth - menuWidth - 12));
  }

  contextMenuTop(menuHeight: number): number {
    const below = this.contextMenuY + 12;
    if (below + menuHeight <= this.contextViewportHeight - this.navBarHeight - 12) return below;
    return Math.max(this.statusBarHeight + 8, this.contextMenuY - menuHeight - 12);
  }

  private shiftPeriod(direction: number): void {
    const d = new Date(this.anchorTs);
    if (this.mode === 'day') {
      this.anchorTs = new Date(d.getFullYear(), d.getMonth(), d.getDate() + direction).getTime();
    } else if (this.mode === 'week') {
      this.anchorTs = new Date(d.getFullYear(), d.getMonth(), d.getDate() + direction * 7).getTime();
    } else {
      this.anchorTs = new Date(d.getFullYear(), d.getMonth() + direction, 1).getTime();
    }
    this.loadStats();
  }

  private currentRange(): StatsRange {
    const range = new StatsRange();
    const d = new Date(this.anchorTs);
    if (this.mode === 'day') {
      range.startTs = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
      range.endTs = range.startTs;
    } else if (this.mode === 'week') {
      const mondayOffset = (d.getDay() + 6) % 7;
      range.startTs = new Date(d.getFullYear(), d.getMonth(), d.getDate() - mondayOffset).getTime();
      range.endTs = range.startTs + 6 * DAY_MS;
    } else {
      range.startTs = new Date(d.getFullYear(), d.getMonth(), 1).getTime();
      range.endTs = new Date(d.getFullYear(), d.getMonth() + 1, 0).getTime();
    }
    return range;
  }

  private canGoForward(): boolean {
    const d = new Date(this.anchorTs);
    let nextStart = 0;
    if (this.mode === 'day') {
      nextStart = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime();
    } else if (this.mode === 'week') {
      const mondayOffset = (d.getDay() + 6) % 7;
      nextStart = new Date(d.getFullYear(), d.getMonth(), d.getDate() - mondayOffset + 7).getTime();
    } else {
      nextStart = new Date(d.getFullYear(), d.getMonth() + 1, 1).getTime();
    }
    const todayStart = new Date().setHours(0, 0, 0, 0);
    return nextStart <= todayStart;
  }

  private periodTitle(): string {
    const d = new Date(this.anchorTs);
    if (this.mode === 'day') {
      const isToday = ReadStatsTracker.dayKeyOf(this.anchorTs) === ReadStatsTracker.dayKeyOf(Date.now());
      return `${isToday ? '今天 · ' : ''}${d.getMonth() + 1}月${d.getDate()}日 ${WEEKDAY_LABELS[d.getDay()]}`;
    }
    if (this.mode === 'week') {
      const range = this.currentRange();
      const s = new Date(range.startTs);
      const e = new Date(range.endTs);
      return `${s.getMonth() + 1}月${s.getDate()}日 - ${e.getMonth() + 1}月${e.getDate()}日`;
    }
    return `${d.getFullYear()}年${d.getMonth() + 1}月`;
  }

  private summarySubtitle(): string {
    if (this.mode === 'day') {
      if (this.totalMs > 0) {
        return `共阅读 ${this.items.length} 本书`;
      }
      const isToday = ReadStatsTracker.dayKeyOf(this.anchorTs) === ReadStatsTracker.dayKeyOf(Date.now());
      return isToday ? '今天还没有开始阅读' : '当日没有阅读记录';
    }
    const days = this.elapsedDays();
    const avg = this.formatDuration(Math.round(this.totalMs / days));
    return `日均 ${avg} · 有阅读 ${this.activeDays} 天`;
  }

  private elapsedDays(): number {
    const range = this.currentRange();
    const todayStart = new Date().setHours(0, 0, 0, 0);
    if (range.endTs <= todayStart) {
      return Math.round((range.endTs - range.startTs) / DAY_MS) + 1;
    }
    return Math.max(1, Math.round((todayStart - range.startTs) / DAY_MS) + 1);
  }

  private formatDuration(ms: number): string {
    const totalMinutes = Math.floor(ms / 60000);
    if (totalMinutes <= 0) {
      return '0分钟';
    }
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    if (hours <= 0) {
      return `${minutes}分钟`;
    }
    if (minutes === 0) {
      return `${hours}小时`;
    }
    return `${hours}小时${minutes}分钟`;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  softColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  dividerColor(): string {
    return ThemeRuntime.hairlineColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

}
