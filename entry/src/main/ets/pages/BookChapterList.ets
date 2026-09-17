import { router, promptAction } from '@kit.ArkUI';
import { Book, BookChapter } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { BookUrlResolver } from '../core/book/BookUrlResolver';
import { BookTypeSupport } from '../core/book/BookTypeSupport';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { BookFieldSanitizer } from '../utils/BookFieldSanitizer';
import { CoverUrlNormalizer } from '../utils/CoverUrlNormalizer';
import { BookIdentity } from '../utils/BookIdentity';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { BookSourceStageRuntimeHost } from '../components/BookSourceStageRuntimeHost';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';

/** 未分组书架条目的分组 ID，必须与 SearchBookShelfHelper 里临时阅读书的写入值一致。 */
const TEMP_SHELF_GROUP: number = -2147483645;

const LOAD_LOADING: string = 'loading';
const LOAD_READY: string = 'ready';
const LOAD_EMPTY: string = 'empty';
const LOAD_ERROR: string = 'error';

class ChapterListDataSource implements IDataSource {
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

@Entry
@Component
struct BookChapterListPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State bookUrl: string = '';
  @State tocUrl: string = '';
  @State origin: string = '';
  @State originName: string = '';
  @State name: string = '';
  @State author: string = '';
  @State kind: string = '';
  @State status: string = '';
  @State coverUrl: string = '';
  @State intro: string = '';
  @State latestChapterTitle: string = '';
  @State wordCount: string = '';
  @State updateTime: string = '';
  @State bookType: number = 0;
  @State loadState: string = LOAD_LOADING;
  @State errorMessage: string = '';
  @State chapters: BookChapter[] = [];
  @State displayedCount: number = 0;
  @State reverseOrder: boolean = false;
  @State currentIndex: number = -1;
  @State keyword: string = '';
  @State fromCache: boolean = false;
  @State openingChapter: boolean = false;
  private bookVariable: string = '';
  private pageAlive: boolean = true;
  private dataSource: ChapterListDataSource = new ChapterListDataSource();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.syncBars();
    this.pageAlive = true;
    const params = router.getParams() as Record<string, string>;
    if (params) {
      this.bookUrl = BookUrlResolver.scalar(params['bookUrl'] || '');
      this.tocUrl = BookUrlResolver.scalar(params['tocUrl'] || '');
      this.origin = params['origin'] || '';
      this.originName = params['originName'] || '';
      this.name = params['name'] || '';
      this.author = params['author'] || '';
      this.kind = params['kind'] || '';
      this.status = params['status'] || '';
      this.coverUrl = params['coverUrl'] || '';
      this.intro = BookFieldSanitizer.clean(params['intro'] || '');
      this.latestChapterTitle = params['latestChapterTitle'] || '';
      this.wordCount = params['wordCount'] || '';
      this.updateTime = params['updateTime'] || '';
      this.bookType = Number(params['type'] || 0) || 0;
      this.bookVariable = params['variable'] || '';
    }
    this.loadChapters();
  }

  onPageShow(): void {
    this.syncBars();
  }

  aboutToDisappear(): void {
    // The source runtime keeps its own request lifecycle. Only guard against a late response
    // writing into a page instance the user already left.
    this.pageAlive = false;
  }

  build() {
    Stack() {
      WebBookFetchRuntimeHost()

      Column() {
        this.catalogToolbar()

        if (this.loadState === LOAD_LOADING) {
          this.statusView('正在获取该书源的目录…', '')
        } else if (this.loadState === LOAD_ERROR) {
          this.statusView(this.errorMessage || '目录加载失败', '重试')
        } else if (this.loadState === LOAD_EMPTY) {
          this.statusView(this.errorMessage || '该书源未解析出章节', '重试')
        } else {
          this.chapterList()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      this.titleBar()
      BookSourceStageRuntimeHost()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        onBack: () => this.handleBack() })

      Column() {
        Text(this.name || '目录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.subtitleText())
          .fontSize(12)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ right: 16, top: this.statusBarHeight })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
    .position({ x: 0, y: 0 })
  }

  @Builder
  catalogToolbar() {
    Row({ space: 10 }) {
      TextInput({ placeholder: '搜索章节名', text: this.keyword })
        .layoutWeight(1)
        .height(38)
        .borderRadius(8)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .fontSize(14)
        .padding({ left: 14, right: 14 })
        .onChange((value: string): void => {
          this.keyword = value;
          this.rebuildDisplayList();
        })

      Text(this.reverseOrder ? '倒序' : '正序')
        .fontSize(14)
        .fontColor(this.accentColor())
        .padding({ left: 13, right: 13, top: 10, bottom: 10 })
        .backgroundColor(this.inputColor())
        .borderRadius(8)
        .onClick((): void => {
          this.reverseOrder = !this.reverseOrder;
          this.rebuildDisplayList();
          this.scrollToCurrentChapter();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 66 + this.statusBarHeight, bottom: 10 })
  }

  @Builder
  statusView(message: string, action: string) {
    Column({ space: 14 }) {
      if (!action) {
        LoadingProgress()
          .width(34)
          .height(34)
          .color(this.accentColor())
      }

      Text(message)
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .textAlign(TextAlign.Center)
        .lineHeight(22)
        .padding({ left: 32, right: 32 })

      if (action) {
        Button(action)
          .height(38)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick((): void => {
            this.loadChapters();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 60 })
    .backgroundColor(this.pageColor())
  }

  @Builder
  chapterList() {
    if (this.displayedCount === 0) {
      Column() {
        Text('没有匹配的章节')
          .fontSize(14)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 80 })
      .backgroundColor(this.pageColor())
    } else {
      List({ scroller: this.scroller }) {
        LazyForEach(this.dataSource, (chapter: BookChapter) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(`${chapter.index + 1}`)
                .fontSize(12)
                .fontColor(this.subTextColor())
                .width(40)
                .textAlign(TextAlign.End)

              Text(chapter.title || `第${chapter.index + 1}章`)
                .fontSize(15)
                .fontWeight(chapter.index === this.currentIndex ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(chapter.index === this.currentIndex ? this.accentColor() : this.primaryTextColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (chapter.cacheDate > 0) {
                Text('已缓存')
                  .fontSize(10)
                  .fontColor(this.appDarkMode ? '#7CC7A0' : '#1F8F55')
                  .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                  .backgroundColor(this.appDarkMode ? '#24382F' : '#E6F4EC')
                  .borderRadius(10)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 16, top: 14, bottom: 14 })
            .backgroundColor(chapter.index === this.currentIndex ? this.inputColor() : Color.Transparent)
            .border({ width: { bottom: 0.5 }, color: this.dividerColor() })
            .onClick((): void => {
              this.openChapter(chapter);
            })
          }
        }, (chapter: BookChapter): string => `${chapter.index}_${chapter.url || chapter.title}`)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: this.navBarHeight + 8 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .cachedCount(6)
      .backgroundColor(this.pageColor())
    }
  }

  private async loadChapters(): Promise<void> {
    if (!this.bookUrl || !this.origin) {
      this.loadState = LOAD_ERROR;
      this.errorMessage = '书籍信息不完整，无法加载目录';
      return;
    }
    this.loadState = LOAD_LOADING;
    this.errorMessage = '';
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      if (!this.pageAlive) return;

      const cached = await db.getBookChapters(this.bookUrl);
      if (!this.pageAlive) return;
      if (cached.length > 0) {
        this.fromCache = true;
        this.applyChapters(cached);
        await this.resolveCurrentIndex(db);
        return;
      }

      const source = await db.getBookSource(this.origin);
      if (!this.pageAlive) return;
      if (!source) {
        this.loadState = LOAD_ERROR;
        this.errorMessage = '该书源已被删除或未启用，无法获取目录';
        return;
      }

      const book = this.buildBook();
      BookTypeSupport.applyBookType(book, source);
      // maxChapters = 0 keeps the whole catalog; the reader needs a full index anyway.
      const fetched = await new WebBookService().getChapterList(source, book, 0, false);
      if (!this.pageAlive) return;
      if (fetched.length === 0) {
        this.loadState = LOAD_EMPTY;
        this.errorMessage = AppStorage.get<string>('bookSourceStageLastError') ||
          '该书源未解析出章节，可能需要在该书源中补充目录规则';
        return;
      }

      for (const chapter of fetched) {
        chapter.bookUrl = this.bookUrl;
      }
      await db.insertBookChapters(fetched);
      await this.persistChapterCount(db, fetched.length);
      if (!this.pageAlive) return;

      this.fromCache = false;
      this.applyChapters(fetched);
      await this.resolveCurrentIndex(db);
    } catch (e) {
      if (!this.pageAlive) return;
      this.loadState = LOAD_ERROR;
      this.errorMessage = `目录加载失败：${e}`;
    }
  }

  private applyChapters(list: BookChapter[]): void {
    this.chapters = list;
    this.loadState = LOAD_READY;
    this.rebuildDisplayList();
  }

  private rebuildDisplayList(): void {
    const keyword = this.keyword.trim();
    const matched: BookChapter[] = keyword.length > 0 ?
      this.chapters.filter((chapter: BookChapter): boolean => chapter.title.includes(keyword)) : this.chapters;
    const display: BookChapter[] = this.reverseOrder ? [...matched].reverse() : matched;
    this.displayedCount = display.length;
    this.dataSource.replace(display);
  }

  private async resolveCurrentIndex(db: AppDatabase): Promise<void> {
    try {
      const book = await db.getBook(this.bookUrl);
      this.currentIndex = book ? book.durChapterIndex : -1;
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
      if (!this.pageAlive) return;
      try {
        this.scroller.scrollToIndex(displayIndex, true, ScrollAlign.CENTER);
      } catch (e) {
        console.warn('定位当前章节失败:', e);
      }
    }, 120);
  }

  private async persistChapterCount(db: AppDatabase, count: number): Promise<void> {
    try {
      const book = await db.getBook(this.bookUrl);
      if (!book || book.totalChapterNum === count) return;
      book.totalChapterNum = count;
      await db.updateBook(book, true, 'chapter_list_count_sync');
    } catch (e) {
      console.warn('回写章节总数失败:', e);
    }
  }

  private async openChapter(chapter: BookChapter): Promise<void> {
    if (this.openingChapter || chapter.index < 0) return;
    this.openingChapter = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      let book = await db.getBook(this.bookUrl);
      if (!book) {
        const key = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
        book = await SearchBookShelfHelper.findShelfBookByKey(key, true);
      }
      if (!book) {
        // Not on the shelf yet. Mirror the detail page's temporary-read record so the reader can
        // open the book, and so leaving it still offers the add-to-shelf prompt.
        book = this.buildBook();
        SearchExplorePendingBook.markPendingAddToShelf(book);
        await db.insertBook(book, 'chapter_list_insert');
      }
      // The reader derives its opening chapter from durChapterIndex alone (see
      // ReadBookEngine.openBookFresh / applyLatestReadingProgress). durChapterPos must be reset
      // too: savedReaderProgressOffset only matches on chapter, so a stale page would land
      // somewhere inside the target chapter.
      book.durChapterIndex = chapter.index;
      book.durChapterPos = 0;
      book.durChapterTitle = chapter.title;
      await db.updateBook(book, true, 'open_chapter_from_chapter_list');
      await router.pushUrl({
        url: 'pages/ReadBook',
        params: { bookUrl: book.bookUrl }
      });
    } catch (e) {
      console.error('打开章节失败:', e);
      promptAction.showToast({ message: '打开章节失败' });
    } finally {
      this.openingChapter = false;
    }
  }

  private buildBook(): Book {
    const book = new Book();
    book.bookUrl = this.bookUrl;
    book.tocUrl = this.tocUrl;
    book.origin = this.origin;
    book.originName = this.originName;
    book.name = this.name;
    book.author = this.author;
    book.kind = BookFieldSanitizer.clean(this.kind);
    book.status = BookFieldSanitizer.clean(this.status);
    book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
    book.intro = BookFieldSanitizer.clean(this.intro);
    book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.clean(this.wordCount);
    book.updateTime = BookFieldSanitizer.clean(this.updateTime);
    book.group = TEMP_SHELF_GROUP;
    book.type = this.bookType;
    book.variable = this.bookVariable;
    BookTypeSupport.applyBookType(book);
    book.canUpdate = true;
    book.lastCheckTime = Date.now();
    book.latestChapterTime = Date.now();
    return book;
  }

  private subtitleText(): string {
    const source = this.originName || this.origin;
    if (this.loadState !== LOAD_READY) return source;
    const keyword = this.keyword.trim();
    if (keyword.length > 0) {
      return `${source} · 匹配 ${this.displayedCount} / ${this.chapters.length} 章`;
    }
    return `${source} · 共 ${this.chapters.length} 章${this.fromCache ? ' · 本地缓存' : ''}`;
  }

  private handleBack(): void {
    router.back();
  }

  private dividerColor(): string {
    return this.appDarkMode ? '#1FFFFFFF' : '#0D000000';
  }

  private pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  private inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  private primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  private secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
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

  private syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
