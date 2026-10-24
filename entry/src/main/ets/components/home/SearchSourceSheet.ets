import { promptAction } from '@kit.ArkUI';
import { BookSource, NativeSourceService } from '@legado/sourceengine';
import { SearchSourceIndexDataSource } from '../../core/book/ShelfDataSources';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { SourceActionKind, SourceActionMenu, SourceActionRunner, SourceDeleteConfirm, SourceDeleteDialogParams,
  SourceGroupTag, SourcePickerKit, SourcePickerSearchField, SourceVariableDialogParams, SourceVariableEditor
} from './SourcePickerKit';

/** 搜索页与面板共享的会话：下滑、点遮罩或返回收起时，搜索页靠它判断有没有没保存的勾选。 */
export class SearchSourceSheetSession {
  dirty: boolean = false;
}

/** 有没保存的勾选时先问一句，返回 true 表示放弃修改。 */
export async function confirmDiscardSearchSourceChanges(): Promise<boolean> {
  try {
    const result = await promptAction.showDialog({
      title: '放弃本次修改？',
      message: '搜索范围的勾选还没有保存。',
      buttons: [{ text: '继续编辑', color: ThemeRuntime.subTextColor(AppStorage.get<boolean>('appDarkMode') === true) },
        { text: '放弃', color: ThemeRuntime.dangerColor(AppStorage.get<boolean>('appDarkMode') === true) }]
    });
    return result.index === 1;
  } catch (e) {
    console.warn('显示放弃修改确认失败:', e);
    return true;
  }
}

/**
 * 搜索范围面板，作为半模态（bindSheet）的内容使用。
 * 左栏是“全部”“已选”和各分组，带三态勾选和计数，点勾选框整组选或取消，点名称在右栏查看；
 * 右栏懒加载列出书源，书源上千时也只画屏幕上的几行。勾选只在面板里改，点“完成”才交给搜索页。
 */
@Component
export struct SearchSourceSheet {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  static readonly ALL_KEY: string = '__all__';
  static readonly SELECTED_KEY: string = '__selected__';
  static readonly GROUP_PANE_WIDTH: number = 124;
  /** 左栏勾选框所在列宽，勾选框居中后与右栏书源行的勾选框左边距接近。 */
  static readonly CHECK_COLUMN_WIDTH: number = 44;
  static readonly ROW_HEIGHT: number = 48;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  /** 可搜索的书源与各自的分组名（下标一一对应），以及排好序的分组。 */
  sources: BookSource[] = [];
  sourceGroupOf: string[] = [];
  groups: string[] = [];
  initialSelectedUrls: string[] = [];
  session: SearchSourceSheetSession = new SearchSourceSheetSession();
  onDone: (urls: string[]) => void = (_urls: string[]): void => {
  };
  onCancel: () => void = (): void => {
  };
  /** 长按菜单删掉书源后通知搜索页重新加载书源。 */
  onSourcesChanged: () => void = (): void => {
  };
  @State keyword: string = '';
  /** 左栏分组；删掉书源后可能少一组，所以是状态变量。 */
  @State groupList: string[] = [];
  @State activeKey: string = SearchSourceSheet.ALL_KEY;
  /** 勾选集合不是状态变量，改动后加一，让读到它的勾选框和计数跟着刷新。 */
  @State selectionVersion: number = 0;
  @State visibleCount: number = 0;
  private selected: Set<string> = new Set<string>();
  private searchTexts: string[] = [];
  private displayNames: string[] = [];
  private matched: boolean[] = [];
  private visibleIndexes: number[] = [];
  /** 进“已选”时记下当时选中的书源，取消勾选后这一行还留着，方便再勾回来。 */
  private selectedSnapshot: Set<string> = new Set<string>();
  private totalSelected: number = 0;
  private scopeTotal: number = 0;
  private scopeSelected: number = 0;
  private groupTotals: Map<string, number> = new Map<string, number>();
  private groupSelected: Map<string, number> = new Map<string, number>();
  private dataSource: SearchSourceIndexDataSource = new SearchSourceIndexDataSource();
  private listScroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    this.groupList = this.groups.slice();
    this.rebuildSourceTexts();
    this.selected = new Set<string>(this.initialSelectedUrls);
    this.session.dirty = false;
    this.computeMatches();
    this.recount();
    this.refreshVisible();
  }

  rebuildSourceTexts(): void {
    const texts: string[] = [];
    for (let index = 0; index < this.sources.length; index++) {
      const source = this.sources[index];
      texts.push(`${source.bookSourceName}\n${source.bookSourceUrl}\n${this.sourceGroupOf[index] || ''}`
        .toLowerCase().replace(/\s+/g, ''));
    }
    this.searchTexts = texts;
    this.displayNames = SourcePickerKit.displayNames(
      this.sources.map((source: BookSource): string => source.bookSourceName),
      this.sources.map((source: BookSource): string => source.bookSourceUrl));
  }

  build() {
    Column() {
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.XS }) {
          Text('搜索范围')
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(`已选 ${this.selectedCount()} / ${this.sources.length} 个书源`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.primaryTextColor(),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          materialScale: 0.83,
          compactLayout: true,
          accessibilityLabel: '关闭搜索范围',
          onBack: () => {
            this.cancel();
          }
        })
      }
      .width('100%')
      // 半模态已在拖动条下方留出位置，这里只留很小的上边距。
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.XS, bottom: AppSpacing.MD })
      .alignItems(VerticalAlign.Center)

      SourcePickerSearchField({
        text: this.keyword,
        onTextChange: (value: string): void => {
          this.applyKeyword(value);
        }
      })
        .margin({ left: AppSpacing.XXL, right: AppSpacing.XL, bottom: AppSpacing.MD })

      Row() {
        this.groupPane()
        this.sourcePane()
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Top)
      .border({ width: { top: 0.5 }, color: ThemeRuntime.hairlineColor(this.appDarkMode) })

      this.bottomBar()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  groupPane() {
    List() {
      ListItem() {
        this.groupRow('全部', SearchSourceSheet.ALL_KEY)
      }
      ListItem() {
        this.groupRow('已选', SearchSourceSheet.SELECTED_KEY)
      }
      ForEach(this.groupList, (group: string) => {
        ListItem() {
          this.groupRow(group, group)
        }
      }, (group: string): string => group)
    }
    .width(SearchSourceSheet.GROUP_PANE_WIDTH)
    .height('100%')
    .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    // 上滑先把面板拉到全屏再滚动，下滑先滚回顶部再收起面板。
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
    // 底部留白放在内容末尾，用内边距会把列表可视区裁短一截，像多出一块安全区。
    .contentEndOffset(AppSpacing.LG)
  }

  /** 左栏一行：勾选框整组选或取消（“已选”没有勾选框），点其余部分切换右栏。 */
  @Builder
  groupRow(label: string, key: string) {
    Row() {
      if (key === SearchSourceSheet.SELECTED_KEY) {
        Stack() {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(18)
            .fontColor([this.activeKey === key ? this.accentColor() : this.subTextColor()])
        }
        .width(SearchSourceSheet.CHECK_COLUMN_WIDTH)
        .height('100%')
      } else {
        Stack() {
          this.groupCheck(key)
        }
        .width(SearchSourceSheet.CHECK_COLUMN_WIDTH)
        .height('100%')
        .accessibilityText(`${label}，${this.groupStateLabel(key)}，点按整组切换`)
        .onClick(() => this.toggleGroup(key))
      }

      Column({ space: 2 }) {
        Text(label)
          .fontSize(AppFontSize.BODY)
          .fontWeight(this.activeKey === key ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.activeKey === key ? this.accentColor() : this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.groupCountText(key))
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.subTextColor())
          .maxLines(1)
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .padding({ right: AppSpacing.SM })
      .onClick(() => this.selectKey(key))
    }
    .width('100%')
    .height(52)
    .opacity(this.groupDimmed(key) ? 0.45 : 1)
    .backgroundColor(this.activeKey === key ? this.activeRowColor() : Color.Transparent)
  }

  @Builder
  groupCheck(key: string) {
    Stack() {
      if (this.groupState(key) === 2) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(13)
          .fontColor(['#FFFFFF'])
      } else if (this.groupState(key) === 1) {
        Row()
          .width(10)
          .height(2)
          .borderRadius(1)
          .backgroundColor('#FFFFFF')
      }
    }
    .width(18)
    .height(18)
    .borderRadius(5)
    .backgroundColor(this.groupState(key) > 0 ? this.accentColor() : Color.Transparent)
    .border({ width: this.groupState(key) > 0 ? 0 : 1.5, color: this.subTextColor() })
  }

  @Builder
  sourcePane() {
    Column() {
      Row() {
        Text(this.sourcePaneTitle())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.visibleCount > 0) {
          Text(this.visibleState() === 2 ? '取消全选' : '全选')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.accentColor())
            .height('100%')
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
            .onClick(() => this.toggleVisible())
          Text('反选')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.accentColor())
            .height('100%')
            .padding({ left: AppSpacing.MD, right: AppSpacing.LG })
            .onClick(() => this.invertVisible())
        }
      }
      .width('100%')
      .height(40)
      .padding({ left: AppSpacing.LG })
      .alignItems(VerticalAlign.Center)

      if (this.visibleCount === 0) {
        Text(this.emptyText())
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: AppSpacing.XXL, left: AppSpacing.LG, right: AppSpacing.LG })
      } else {
        List({ scroller: this.listScroller }) {
          LazyForEach(this.dataSource, (index: number) => {
            ListItem() {
              this.sourceRow(index)
            }
          }, (index: number): string => `${index}\n${this.sources[index].bookSourceUrl}`)
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(10)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
      }
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  sourceRow(index: number) {
    Row() {
      this.sourceCheck(this.sources[index].bookSourceUrl)
      Text(this.displayNames[index] || this.sources[index].bookSourceUrl)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: AppSpacing.MD })
      // 跨分组的列表里标出所属分组，单个分组里不重复显示；样式与发现页书源下拉一致。
      if (this.activeKey === SearchSourceSheet.ALL_KEY || this.activeKey === SearchSourceSheet.SELECTED_KEY) {
        SourceGroupTag({ label: this.sourceGroupOf[index] || '' })
          .margin({ left: AppSpacing.MD })
      }
    }
    .width('100%')
    .height(SearchSourceSheet.ROW_HEIGHT)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(this.displayNames[index] || this.sources[index].bookSourceUrl)
    .accessibilitySelected(this.isSelected(this.sources[index].bookSourceUrl))
    .onClick(() => this.toggleSource(index))
    .bindContextMenu(this.sourceActionMenu(index), ResponseType.LongPress,
      ImmersiveMaterialRuntime.contextMenuOptions(this.immersiveLightLevel, this.accentColor(), () => {}))
  }

  /** 长按书源的操作菜单，条目和执行与发现页书源下拉共用。 */
  @Builder
  sourceActionMenu(index: number) {
    SourceActionMenu(NativeSourceService.isNative(this.sources[index]), this.appDarkMode, (kind: string): void => {
      ContextMenu.close();
      this.runSourceAction(index, kind);
    })
  }

  @Builder
  sourceCheck(url: string) {
    Stack() {
      if (this.isSelected(url)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(13)
          .fontColor(['#FFFFFF'])
      }
    }
    .width(18)
    .height(18)
    .borderRadius(5)
    .backgroundColor(this.isSelected(url) ? this.accentColor() : Color.Transparent)
    .border({ width: this.isSelected(url) ? 0 : 1.5, color: this.subTextColor() })
  }

  @Builder
  bottomBar() {
    Row() {
      Text('清空')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .height(40)
        .padding({ left: AppSpacing.SM, right: AppSpacing.LG })
        .opacity(this.selectedCount() > 0 ? 1 : 0.45)
        .onClick(() => this.clearAll())
      Blank()
      Text('完成')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .height(40)
        .padding({ left: 32, right: 32 })
        .borderRadius(20)
        .backgroundColor(this.accentColor())
        .onClick(() => this.done())
    }
    .width('100%')
    // 面板贴到屏幕底边，手势条只占导航区最下面一小段；按钮让开手势条即可，不必再垫满整个导航区高度。
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD,
      bottom: Math.max(AppSpacing.MD, this.navBarHeight - AppSpacing.LG) })
    .border({ width: { top: 0.5 }, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
    .alignItems(VerticalAlign.Center)
  }

  // ---- 状态读取：都先读一次 selectionVersion，勾选变化时界面才会刷新 ----

  isSelected(url: string): boolean {
    return this.selectionVersion >= 0 && this.selected.has(url);
  }

  selectedCount(): number {
    return this.selectionVersion >= 0 ? this.totalSelected : 0;
  }

  groupState(key: string): number {
    if (this.selectionVersion < 0) return 0;
    const total = key === SearchSourceSheet.ALL_KEY ? this.scopeTotal : (this.groupTotals.get(key) || 0);
    const selected = key === SearchSourceSheet.ALL_KEY ? this.scopeSelected : (this.groupSelected.get(key) || 0);
    if (total === 0 || selected === 0) return 0;
    return selected >= total ? 2 : 1;
  }

  groupStateLabel(key: string): string {
    const state = this.groupState(key);
    return state === 2 ? '已全选' : (state === 1 ? '部分已选' : '未选');
  }

  groupCountText(key: string): string {
    if (this.selectionVersion < 0) return '';
    if (key === SearchSourceSheet.SELECTED_KEY) return `${this.totalSelected} 个`;
    if (key === SearchSourceSheet.ALL_KEY) return `${this.scopeSelected}/${this.scopeTotal}`;
    return `${this.groupSelected.get(key) || 0}/${this.groupTotals.get(key) || 0}`;
  }

  /** 搜索时没有匹配书源的分组变淡。 */
  groupDimmed(key: string): boolean {
    if (!this.keyword.trim() || key === SearchSourceSheet.ALL_KEY || key === SearchSourceSheet.SELECTED_KEY) {
      return false;
    }
    return this.selectionVersion >= 0 && (this.groupTotals.get(key) || 0) === 0;
  }

  /** 已选数量在标题和左栏都有，这里只写当前列表是什么、有几个。 */
  sourcePaneTitle(): string {
    if (this.activeKey === SearchSourceSheet.SELECTED_KEY) return `已选 · ${this.visibleCount} 个`;
    const name = this.activeKey === SearchSourceSheet.ALL_KEY ? (this.keyword.trim() ? '匹配' : '全部') : this.activeKey;
    return `${name} · ${this.visibleCount} 个`;
  }

  emptyText(): string {
    if (this.sources.length === 0) return '没有可搜索的书源';
    if (this.activeKey === SearchSourceSheet.SELECTED_KEY) {
      return this.keyword.trim() ? '已选书源里没有匹配的' : '还没有选择书源';
    }
    return this.keyword.trim() ? '没有匹配的书源' : '这个分组没有书源';
  }

  visibleSelectedCount(): number {
    if (this.selectionVersion < 0) return 0;
    let count = 0;
    for (const index of this.visibleIndexes) {
      if (this.selected.has(this.sources[index].bookSourceUrl)) count++;
    }
    return count;
  }

  visibleState(): number {
    const selected = this.visibleSelectedCount();
    if (this.visibleCount === 0 || selected === 0) return 0;
    return selected >= this.visibleCount ? 2 : 1;
  }

  // ---- 计算 ----

  computeMatches(): void {
    const keyword = this.keyword.trim().toLowerCase().replace(/\s+/g, '');
    const matched: boolean[] = [];
    for (const text of this.searchTexts) {
      matched.push(!keyword || text.includes(keyword));
    }
    this.matched = matched;
  }

  /** 一次遍历重算总数和各分组计数；书源上千也只是一趟循环。 */
  recount(): void {
    const totals: Map<string, number> = new Map<string, number>();
    const selectedCounts: Map<string, number> = new Map<string, number>();
    let totalSelected = 0;
    let scopeTotal = 0;
    let scopeSelected = 0;
    for (let index = 0; index < this.sources.length; index++) {
      const isSelected = this.selected.has(this.sources[index].bookSourceUrl);
      if (isSelected) totalSelected++;
      if (!this.matched[index]) continue;
      const group = this.sourceGroupOf[index] || '';
      totals.set(group, (totals.get(group) || 0) + 1);
      scopeTotal++;
      if (isSelected) {
        selectedCounts.set(group, (selectedCounts.get(group) || 0) + 1);
        scopeSelected++;
      }
    }
    this.groupTotals = totals;
    this.groupSelected = selectedCounts;
    this.totalSelected = totalSelected;
    this.scopeTotal = scopeTotal;
    this.scopeSelected = scopeSelected;
    this.selectionVersion++;
  }

  scopeIndexes(key: string): number[] {
    const result: number[] = [];
    for (let index = 0; index < this.sources.length; index++) {
      if (!this.matched[index]) continue;
      if (key === SearchSourceSheet.SELECTED_KEY) {
        if (!this.selectedSnapshot.has(this.sources[index].bookSourceUrl)) continue;
      } else if (key !== SearchSourceSheet.ALL_KEY && this.sourceGroupOf[index] !== key) {
        continue;
      }
      result.push(index);
    }
    return result;
  }

  refreshVisible(): void {
    this.visibleIndexes = this.scopeIndexes(this.activeKey);
    this.dataSource.replace(this.visibleIndexes);
    this.visibleCount = this.visibleIndexes.length;
    try {
      this.listScroller.scrollToIndex(0);
    } catch (e) {
      // 列表还没挂上时滚动会抛错，忽略即可。
    }
  }

  // ---- 交互 ----

  applyKeyword(value: string): void {
    if (value === this.keyword) return;
    const wasEmpty = !this.keyword.trim();
    this.keyword = value;
    // 开始搜索时切到“全部”，跨分组列出匹配的书源。
    if (wasEmpty && value.trim() && this.activeKey !== SearchSourceSheet.SELECTED_KEY) {
      this.activeKey = SearchSourceSheet.ALL_KEY;
    }
    this.computeMatches();
    this.recount();
    this.refreshVisible();
  }

  selectKey(key: string): void {
    if (key === SearchSourceSheet.SELECTED_KEY) {
      this.selectedSnapshot = new Set<string>(this.selected);
    } else if (key === this.activeKey) {
      return;
    }
    this.activeKey = key;
    this.refreshVisible();
  }

  markChanged(): void {
    this.session.dirty = true;
    this.recount();
  }

  setSelected(indexes: number[], selected: boolean): void {
    for (const index of indexes) {
      const url = this.sources[index].bookSourceUrl;
      if (!url) continue;
      if (selected) {
        this.selected.add(url);
      } else {
        this.selected.delete(url);
      }
    }
  }

  toggleSource(index: number): void {
    const url = this.sources[index].bookSourceUrl;
    if (!url) return;
    this.setSelected([index], !this.selected.has(url));
    this.markChanged();
  }

  /** 勾选框选的是当前关键字下这一组列出的书源，和右栏、计数看到的一致。 */
  toggleGroup(key: string): void {
    const indexes = this.scopeIndexes(key);
    if (indexes.length === 0) return;
    this.setSelected(indexes, this.groupState(key) !== 2);
    this.markChanged();
  }

  toggleVisible(): void {
    this.setSelected(this.visibleIndexes, this.visibleState() !== 2);
    this.markChanged();
  }

  invertVisible(): void {
    for (const index of this.visibleIndexes) {
      const url = this.sources[index].bookSourceUrl;
      if (!url) continue;
      if (this.selected.has(url)) {
        this.selected.delete(url);
      } else {
        this.selected.add(url);
      }
    }
    this.markChanged();
  }

  clearAll(): void {
    if (this.selected.size === 0) return;
    this.selected.clear();
    this.markChanged();
  }

  /** 长按菜单的源变量与删除确认框内容；在本组件里创建，系统对话框才有父节点。 */
  @Builder
  sourceVariableDialog(params: SourceVariableDialogParams) {
    SourceVariableEditor({ params: params })
  }

  @Builder
  sourceDeleteDialog(params: SourceDeleteDialogParams) {
    SourceDeleteConfirm({ params: params })
  }

  runSourceAction(index: number, kind: string): void {
    const source = this.sources[index];
    if (!source || !source.bookSourceUrl) return;
    const sourceUrl = source.bookSourceUrl;
    if (SourceActionRunner.isNavigation(kind)) {
      // 跳到别的页面前先按“完成”收起面板，勾选不会丢，回来也不会留着一个过时的面板。
      this.done();
      SourceActionRunner.navigate(kind, sourceUrl, NativeSourceService.isNative(source));
    } else if (kind === SourceActionKind.VARIABLE) {
      SourceActionRunner.openVariableEditor(this.getUIContext(), sourceUrl,
        (dialogParams: SourceVariableDialogParams): CustomBuilder => (): void => {
          this.sourceVariableDialog(dialogParams);
        }, (): void => {
      });
    } else if (kind === SourceActionKind.DELETE) {
      SourceActionRunner.confirmDelete(this.getUIContext(), sourceUrl,
        (dialogParams: SourceDeleteDialogParams): CustomBuilder => (): void => {
          this.sourceDeleteDialog(dialogParams);
        }, (url: string): void => {
        this.removeSource(url);
        this.onSourcesChanged();
      });
    }
  }

  /** 删掉的书源从面板里移除：重建下标对应的各数组，分组没了就回到“全部”。 */
  removeSource(url: string): void {
    const keep: number[] = [];
    for (let index = 0; index < this.sources.length; index++) {
      if (this.sources[index].bookSourceUrl !== url) keep.push(index);
    }
    if (keep.length === this.sources.length) return;
    this.sources = keep.map((index: number): BookSource => this.sources[index]);
    this.sourceGroupOf = keep.map((index: number): string => this.sourceGroupOf[index]);
    this.groupList = SourcePickerKit.sortGroups(Array.from(new Set<string>(this.sourceGroupOf)));
    this.selected.delete(url);
    this.selectedSnapshot.delete(url);
    if (this.activeKey !== SearchSourceSheet.ALL_KEY && this.activeKey !== SearchSourceSheet.SELECTED_KEY &&
      !this.groupList.includes(this.activeKey)) {
      this.activeKey = SearchSourceSheet.ALL_KEY;
    }
    this.rebuildSourceTexts();
    this.computeMatches();
    this.recount();
    this.refreshVisible();
  }

  done(): void {
    if (!this.session.dirty) {
      this.onCancel();
      return;
    }
    const urls: string[] = [];
    for (const source of this.sources) {
      if (source.bookSourceUrl && this.selected.has(source.bookSourceUrl)) urls.push(source.bookSourceUrl);
    }
    this.session.dirty = false;
    this.onDone(urls);
  }

  async cancel(): Promise<void> {
    if (this.session.dirty && !(await confirmDiscardSearchSourceChanges())) return;
    this.session.dirty = false;
    this.onCancel();
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

  activeRowColor(): string {
    const color = this.accentColor();
    return /^#[0-9A-Fa-f]{6}$/.test(color) ? `#1F${color.substring(1)}` : color;
  }
}
