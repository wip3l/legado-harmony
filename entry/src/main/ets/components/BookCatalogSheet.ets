import { Book, BookChapter, BookTypeSupport } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from './ImmersiveBackButton';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ReaderMaterialPanel } from './reader/ReaderFloatingMaterialBar';

const LOAD_LOADING: string = 'loading';
const LOAD_READY: string = 'ready';
const LOAD_EMPTY: string = 'empty';
const LOAD_ERROR: string = 'error';
const CATALOG_SEARCH_INPUT_KEY: string = 'book_catalog_sheet_search_input';

class CatalogSheetDataSource implements IDataSource {
  private chapters: BookChapter[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.chapters.length;
  }

  getData(index: number): BookChapter {
    return this.chapters[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(chapters: BookChapter[]): void {
    this.chapters = [...chapters];
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

/**
 * 书籍详情页的目录面板，作为半模态（bindSheet）的内容使用。
 * 版式与阅读器内的目录面板（ReaderTocPanel）保持一致：圆形操作按钮、章节行的圆点与"已缓存"标记、
 * 当前章节高亮。详情页上方已经露出封面和作者，这里不再重复；也没有书签页签和按序号跳转。
 * 只负责取目录、搜索、排序与展示；点中章节后交给宿主页面落库并跳转，
 * 这样临时阅读书的写入与"加入书架"提示仍走详情页自己的那一套。
 * 宿主页面必须挂着 WebBookFetchRuntimeHost，否则需要 Web 通道的书源取不到目录。
 */
@Component
export struct BookCatalogSheet {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  /** 宿主按当前详情拼出的书籍；目录规则可能依赖其中的 variable。 */
  book: Book = new Book();
  onChapterSelected: (chapter: BookChapter) => void = (_chapter: BookChapter): void => {
  };
  onLoaded: (count: number) => void = (_count: number): void => {
  };
  onClose: () => void = (): void => {
  };

  @State loadState: string = LOAD_LOADING;
  @State errorMessage: string = '';
  @State chapters: BookChapter[] = [];
  @State displayedCount: number = 0;
  @State reverseOrder: boolean = false;
  @State currentIndex: number = -1;
  @State keyword: string = '';
  @State searchVisible: boolean = false;
  @State panelWidth: number = 320;
  @State panelHeight: number = 400;
  private alive: boolean = true;
  private dataSource: CatalogSheetDataSource = new CatalogSheetDataSource();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.alive = true;
    this.loadChapters();
  }

  aboutToDisappear(): void {
    // The source runtime keeps its own request lifecycle. Only guard against a late response
    // writing into a sheet the user already dismissed.
    this.alive = false;
  }

  build() {
    Column() {
      ReaderMaterialPanel({
        panelWidth: this.panelWidth,
        panelHeight: this.panelHeight,
        cornerRadius: 28,
        darkMode: this.appDarkMode,
        fallbackColor: ThemeRuntime.cardColor(this.appDarkMode)
      }) {
        this.panelBody()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, area: Area) => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width > 0 && width !== this.panelWidth) this.panelWidth = width;
      if (height > 0 && height !== this.panelHeight) this.panelHeight = height;
    })
  }

  @Builder
  panelBody() {
    Column() {
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.XS }) {
          Text(this.isEpisodic() ? '选集' : '目录')
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(this.subtitleText())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
          accessibilityLabel: '关闭目录',
          onBack: () => this.onClose()
        })
      }
      .width('100%')
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.MD })
      .alignItems(VerticalAlign.Center)

      this.summaryBar()

      if (this.loadState === LOAD_LOADING) {
        this.statusView(this.isEpisodic() ? '正在获取选集…' : '正在获取该书源的目录…', '')
      } else if (this.loadState === LOAD_ERROR) {
        this.statusView(this.errorMessage || '目录加载失败', '重试')
      } else if (this.loadState === LOAD_EMPTY) {
        this.statusView(this.errorMessage || '该书源未解析出章节', '重试')
      } else if (this.displayedCount === 0) {
        this.statusView(this.isEpisodic() ? '未找到匹配选集' : '未找到匹配章节', '')
      } else {
        this.chapterList()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  summaryBar() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Text(this.countText())
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .height(34)
          .textAlign(TextAlign.Center)
          .margin({ left: AppSpacing.SM })

        if (this.loadState === LOAD_READY) {
          Stack({ alignContent: Alignment.Center }) {
            Column({ space: 0 }) {
              SymbolGlyph($r('sys.symbol.chevron_up'))
                .fontSize(11)
                .fontColor([this.reverseOrder ? this.accentColor() : this.primaryTextColor()])
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(11)
                .fontColor([this.reverseOrder ? this.accentColor() : this.primaryTextColor()])
            }
            .alignItems(HorizontalAlign.Center)
          }
          .width(34)
          .height(34)
          .borderRadius(17)
          .backgroundColor(this.reverseOrder ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) :
            ThemeRuntime.softFillColor(this.appDarkMode))
          .accessibilityText(this.reverseOrder ? '切换为正序目录' : '切换为倒序目录')
          .onClick((): void => {
            this.toggleOrder();
          })
          .margin({ left: AppSpacing.MD })
        }

        Blank()
          .layoutWeight(1)

        if (this.loadState === LOAD_READY) {
          ImmersiveBackButton({
            icon: $r('sys.symbol.magnifyingglass'),
            iconOffsetX: 0,
            iconColor: this.searchVisible ? this.accentColor() : this.primaryTextColor(),
            darkMode: this.appDarkMode,
            buttonSize: 34,
            containerWidth: 34,
            containerHeight: 34,
            startInset: 0,
            materialScale: 0.7,
            compactLayout: true,
            accessibilityLabel: '搜索目录',
            onBack: () => this.toggleSearch()
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.searchVisible) {
        Row({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([this.subTextColor()])
          TextInput({ text: this.keyword, placeholder: this.isEpisodic() ? '搜索选集名称' : '搜索章节名称' })
            .key(CATALOG_SEARCH_INPUT_KEY)
            .defaultFocus(true)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .placeholderColor(this.subTextColor())
            .layoutWeight(1)
            .height(38)
            .padding({ left: 0, right: 0 })
            .backgroundColor(Color.Transparent)
            .enterKeyType(EnterKeyType.Search)
            .onChange((value: string): void => {
              this.keyword = value;
              this.rebuildDisplayList();
            })
          if (this.keyword) {
            Text('×')
              .fontSize(AppFontSize.TITLE)
              .fontColor(this.subTextColor())
              .width(32)
              .height(38)
              .textAlign(TextAlign.Center)
              .accessibilityText('清空目录搜索')
              .onClick((): void => {
                this.keyword = '';
                this.rebuildDisplayList();
                this.focusSearchInput();
              })
          }
        }
        .width('100%')
        .height(40)
        .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
        .borderRadius(20)
        .backgroundColor(ThemeRuntime.hairlineColor(this.appDarkMode))
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statusView(message: string, action: string) {
    Column({ space: AppSpacing.LG }) {
      if (this.loadState === LOAD_LOADING) {
        LoadingProgress()
          .width(34)
          .height(34)
          .color(this.accentColor())
      }

      Text(message)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
        .lineHeight(22)
        .padding({ left: 32, right: 32 })

      if (action) {
        Button(action)
          .height(38)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick((): void => {
            this.loadChapters();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 60 })
  }

  @Builder
  chapterList() {
    List({ scroller: this.scroller }) {
      LazyForEach(this.dataSource, (chapter: BookChapter) => {
        ListItem() {
          Column() {
            if (BookChapter.volumeTitleOf(chapter)) {
              Text(BookChapter.volumeTitleOf(chapter))
                .fontSize(AppFontSize.BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.subTextColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.SM })
            }
            Row({ space: AppSpacing.MD }) {
              Text(chapter.index === this.currentIndex ? '•' : '·')
                .fontSize(chapter.index === this.currentIndex ? 22 : 18)
                .fontColor(chapter.index === this.currentIndex ? this.accentColor() : this.subTextColor())
                .width(18)
                .textAlign(TextAlign.Center)

              Text(chapter.title || `第${chapter.index + 1}${this.unitText()}`)
                .fontSize(AppFontSize.BODY_LARGE)
                .fontWeight(chapter.index === this.currentIndex ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(chapter.index === this.currentIndex ? this.accentColor() : this.primaryTextColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (chapter.cacheDate > 0) {
                Text('已缓存')
                  .fontSize(AppFontSize.MICRO)
                  .fontColor(ThemeRuntime.successColor(this.appDarkMode))
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
                  .backgroundColor(ThemeRuntime.successSurfaceColor(this.appDarkMode))
                  .borderRadius(ThemeRuntime.mediumRadius())
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.LG, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
            .backgroundColor(chapter.index === this.currentIndex ?
              ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
            .border({ width: { bottom: 0.5 }, color: ThemeRuntime.softFillColor(this.appDarkMode) })
            .onClick((): void => {
              this.onChapterSelected(chapter);
            })
          }
        }
      }, (chapter: BookChapter): string => `${chapter.index}_${chapter.url || chapter.title}`)
    }
    .width('100%')
    .layoutWeight(1)
    .contentEndOffset(this.navBarHeight + 16)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .cachedCount(6)
  }

  private async loadChapters(): Promise<void> {
    const bookUrl = this.book.bookUrl;
    if (!bookUrl || !this.book.origin) {
      this.loadState = LOAD_ERROR;
      this.errorMessage = '书籍信息不完整，无法加载目录';
      return;
    }
    this.loadState = LOAD_LOADING;
    this.errorMessage = '';
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      if (!this.alive) return;

      const cached = await db.getBookChapters(bookUrl);
      if (!this.alive) return;
      if (cached.length > 0) {
        this.applyChapters(cached);
        await this.resolveCurrentIndex(db);
        return;
      }

      const source = await db.getBookSource(this.book.origin);
      if (!this.alive) return;
      if (!source) {
        this.loadState = LOAD_ERROR;
        this.errorMessage = '该书源已被删除或未启用，无法获取目录';
        return;
      }

      BookTypeSupport.applyBookType(this.book, source);
      // maxChapters = 0 keeps the whole catalog; the reader needs a full index anyway.
      const fetched = await new WebBookService().getChapterList(source, this.book, 0, false);
      if (!this.alive) return;
      if (fetched.length === 0) {
        this.loadState = LOAD_EMPTY;
        this.errorMessage = AppStorage.get<string>('bookSourceStageLastError') ||
          '该书源未解析出章节，可能需要在该书源中补充目录规则';
        return;
      }

      for (const chapter of fetched) {
        chapter.bookUrl = bookUrl;
      }
      await db.insertBookChapters(fetched);
      await this.persistChapterCount(db, fetched.length);
      if (!this.alive) return;

      this.applyChapters(fetched);
      await this.resolveCurrentIndex(db);
    } catch (e) {
      if (!this.alive) return;
      this.loadState = LOAD_ERROR;
      this.errorMessage = `目录加载失败：${e}`;
    }
  }

  private applyChapters(list: BookChapter[]): void {
    this.chapters = list;
    this.loadState = LOAD_READY;
    this.rebuildDisplayList();
    this.onLoaded(list.length);
  }

  private rebuildDisplayList(): void {
    const keyword = this.keyword.trim();
    const matched: BookChapter[] = keyword.length > 0 ?
      this.chapters.filter((chapter: BookChapter): boolean => chapter.title.includes(keyword)) : this.chapters;
    const display: BookChapter[] = this.reverseOrder ? [...matched].reverse() : matched;
    this.displayedCount = display.length;
    this.dataSource.replace(display);
  }

  private toggleOrder(): void {
    this.reverseOrder = !this.reverseOrder;
    this.rebuildDisplayList();
    this.scrollToCurrentChapter();
  }

  private toggleSearch(): void {
    this.searchVisible = !this.searchVisible;
    if (this.searchVisible) {
      this.focusSearchInput();
      return;
    }
    if (this.keyword) {
      this.keyword = '';
      this.rebuildDisplayList();
      this.scrollToCurrentChapter();
    }
  }

  private focusSearchInput(): void {
    setTimeout((): void => {
      if (!this.alive || !this.searchVisible) return;
      focusControl.requestFocus(CATALOG_SEARCH_INPUT_KEY);
    }, 60);
  }

  private async resolveCurrentIndex(db: AppDatabase): Promise<void> {
    try {
      const stored = await db.getBook(this.book.bookUrl);
      this.currentIndex = stored ? stored.durChapterIndex : -1;
    } catch (e) {
      this.currentIndex = -1;
    }
    this.scrollToCurrentChapter();
  }

  private scrollToCurrentChapter(): void {
    if (this.currentIndex < 0 || this.keyword.trim().length > 0) return;
    const total = this.chapters.length;
    const displayIndex = this.reverseOrder ? total - 1 - this.currentIndex : this.currentIndex;
    if (displayIndex < 0 || displayIndex >= total) return;
    // Let the list finish its first layout pass before scrolling; index scrolling on a
    // just-attached List is otherwise a no-op.
    setTimeout((): void => {
      if (!this.alive) return;
      try {
        this.scroller.scrollToIndex(displayIndex, false, ScrollAlign.CENTER);
      } catch (e) {
        console.warn('定位当前章节失败:', e);
      }
    }, 120);
  }

  private async persistChapterCount(db: AppDatabase, count: number): Promise<void> {
    try {
      const stored = await db.getBook(this.book.bookUrl);
      if (!stored || stored.totalChapterNum === count) return;
      stored.totalChapterNum = count;
      await db.updateBook(stored, true, 'catalog_sheet_count_sync');
    } catch (e) {
      console.warn('回写章节总数失败:', e);
    }
  }

  private isEpisodic(): boolean {
    return BookTypeSupport.isVideo(this.book) || BookTypeSupport.isAudio(this.book);
  }

  private unitText(): string {
    return this.isEpisodic() ? '集' : '章';
  }

  private countText(): string {
    if (this.loadState !== LOAD_READY) return this.isEpisodic() ? '选集' : '章节';
    if (this.keyword.trim().length > 0) return `找到 ${this.displayedCount} ${this.unitText()}`;
    return `共 ${this.chapters.length} ${this.unitText()}`;
  }

  private subtitleText(): string {
    const name = this.book.name || '';
    const source = this.book.originName || '';
    return name && source ? `${name} · ${source}` : (name || source);
  }

  private primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  private subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  private buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  private accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }
}
