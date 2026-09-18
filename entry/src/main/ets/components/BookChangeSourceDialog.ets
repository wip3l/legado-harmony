import { Book, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { WebBookService } from '../core/book/WebBookService';
import { ChangeSourceResultCache } from '../utils/ChangeSourceResultCache';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { BookFieldSanitizer } from '../utils/BookFieldSanitizer';
import { CoverUrlNormalizer } from '../utils/CoverUrlNormalizer';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemeRuntime } from '../theme/ThemeRuntime';

/**
 * 换源面板（书架长按"换源"与书籍详情页"换源"共用）。
 * 打开后先读历史结果，再按书名全词匹配搜索其它书源；选中结果后拉取详情与目录并切换。
 * 目标书在书库中已存在时提交换源并保留阅读进度与临时书标记；
 * 仅存在于搜索结果（未入库）时只把结果交给宿主页面，不落库。
 */
@Component
export struct BookChangeSourceDialog {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  targetBook: Book | null = null;
  onSwitched: (book: Book) => void = (_book: Book): void => {
  };
  onClosed: () => void = (): void => {
  };
  /** 切换提交前回调（宿主可先落盘阅读进度），完成后再开始切换。 */
  onBeforeSwitch: (() => Promise<void>) | null = null;
  /** 阅读器换源时标记阅读状态变量，避免章节 0/页 0 的切换被书架视为未读。 */
  markReadOnSwitch: boolean = false;

  @State results: SearchBook[] = [];
  @State status: string = '';
  @State searching: boolean = false;
  @State switching: boolean = false;
  private sessionId: number = 0;
  private activeCoordinator: SearchCoordinator | null = null;

  aboutToAppear(): void {
    if (!this.targetBook) {
      this.onClosed();
      return;
    }
    this.startSession();
  }

  aboutToDisappear(): void {
    this.sessionId++;
    this.cancelActiveSearch();
  }

  startSession(): void {
    if (!this.targetBook) return;
    this.cancelActiveSearch();
    this.results = [];
    this.status = '正在读取历史换源结果...';
    this.searching = true;
    this.switching = false;
    const sessionId = ++this.sessionId;
    this.loadHistoryThenSearch(sessionId);
  }

  async loadHistoryThenSearch(sessionId: number): Promise<void> {
    const book = this.targetBook;
    if (!book) return;
    try {
      const cached = await ChangeSourceResultCache.load(getContext(this), book.name, book.author);
      if (!this.isSessionActive(sessionId)) return;
      this.results = this.filterResults(cached, book.bookUrl, book.origin);
      if (this.results.length > 0) {
        this.searching = false;
        this.status = `已显示历史结果，共 ${this.results.length} 个；点击刷新可重新搜索`;
        return;
      }
    } catch (e) {
      console.warn('读取换源历史结果失败:', e);
    }
    if (this.isSessionActive(sessionId)) {
      this.search(sessionId);
    }
  }

  refreshResults(): void {
    if (!this.targetBook || this.switching) return;
    this.cancelActiveSearch();
    const sessionId = ++this.sessionId;
    this.searching = true;
    this.status = '正在刷新可用书源...';
    this.search(sessionId);
  }

  requestClose(): void {
    if (this.switching) return;
    this.sessionId++;
    this.cancelActiveSearch();
    this.onClosed();
  }

  async search(sessionId: number): Promise<void> {
    const target = this.targetBook;
    if (!target) return;
    const cacheBookName = target.name;
    const coordinator = new SearchCoordinator(Math.min(2, SearchExploreSettingsStore.getSearchConcurrency()));
    this.activeCoordinator = coordinator;
    this.searching = true;
    this.status = '正在搜索可用书源...';
    try {
      const results = await coordinator.search(target.name, (progress: SearchProgress) => {
        if (!this.isSessionActive(sessionId)) return;
        if (progress.finished) {
          this.results = this.filterResults(progress.results, target.bookUrl, target.origin);
        } else if (progress.deltaResults && progress.deltaResults.length > 0) {
          this.results = this.filterResults(
            this.results.concat(progress.deltaResults), target.bookUrl, target.origin);
        }
        this.status = progress.status;
        if (progress.finished) this.searching = false;
      }, {
        exactMatch: true,
        leanResult: true,
        excludeSourceUrls: [target.origin],
        maxResultsPerSource: 1,
        maxTotalResults: 60,
        stopAfterResults: 20,
        maxCandidatesPerSource: 32
      });
      if (!this.isSessionActive(sessionId)) return;
      this.results = this.filterResults(results, target.bookUrl, target.origin);
      this.status = this.results.length > 0 ?
        `搜索完成，找到 ${this.results.length} 个可切换书源` : '搜索完成，未找到可切换书源';
      try {
        await ChangeSourceResultCache.save(getContext(this), cacheBookName, results, target.author);
      } catch (e) {
        console.warn('保存换源结果失败:', e);
      }
    } catch (e) {
      if (!this.isSessionActive(sessionId)) return;
      console.error('搜索换源失败:', e);
      this.status = '搜索换源失败';
    } finally {
      if (this.activeCoordinator === coordinator) {
        this.activeCoordinator = null;
      }
      if (this.isSessionActive(sessionId)) {
        this.searching = false;
      }
    }
  }

  async switchSource(searchBook: SearchBook): Promise<void> {
    const target = this.targetBook;
    if (!target || this.switching) return;
    this.cancelActiveSearch();
    this.searching = false;
    const sessionId = ++this.sessionId;
    this.switching = true;
    this.status = '正在切换书源...';
    if (this.onBeforeSwitch) {
      await this.onBeforeSwitch();
    }
    const oldBookUrl = target.bookUrl;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const oldBook = await db.getBook(oldBookUrl);
      const source = searchBook.origin ? await db.getBookSource(searchBook.origin) : null;
      if (!source) {
        HdsFeedback.showToast('书源不存在或已删除');
        return;
      }
      if (!this.isSessionActive(sessionId)) return;

      const nextBook = this.buildSourceBook(searchBook, oldBook || target);
      const service = new WebBookService();
      const fullBook = await service.getBookInfo(source, nextBook);
      if (!this.isSessionActive(sessionId)) return;
      this.preserveSourceBookState(fullBook, nextBook, oldBook || target);
      const chapters = await service.getChapterList(source, fullBook, 0, false);
      if (!this.isSessionActive(sessionId)) return;
      if (chapters.length === 0) throw new Error('新书源目录为空，已保留原书源');
      fullBook.totalChapterNum = chapters.length;
      const safeIndex = Math.max(0, Math.min((oldBook || target).durChapterIndex, chapters.length - 1));
      fullBook.durChapterIndex = safeIndex;
      fullBook.durChapterTitle = chapters[safeIndex].title;
      fullBook.latestChapterTitle = chapters[chapters.length - 1].title;

      // 只有书库中已存在该书的持久化行时才提交换源；纯搜索结果只把新源书籍交还宿主展示。
      if (oldBook) {
        await db.commitBookSourceSwitch(oldBookUrl, fullBook, chapters);
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }

      HdsFeedback.showToast(`已切换至 ${fullBook.originName || searchBook.originName}`);
      this.sessionId++;
      this.cancelActiveSearch();
      this.onSwitched(fullBook);
      this.onClosed();
    } catch (e) {
      if (!this.isSessionActive(sessionId)) return;
      console.error('切换书源失败:', e);
      HdsFeedback.showToast('切换书源失败');
    } finally {
      if (sessionId === this.sessionId) {
        this.switching = false;
      }
    }
  }

  isSessionActive(sessionId: number): boolean {
    return sessionId === this.sessionId;
  }

  cancelActiveSearch(): void {
    if (this.activeCoordinator) {
      this.activeCoordinator.cancel();
      this.activeCoordinator = null;
    }
  }

  filterResults(results: SearchBook[], currentBookUrl: string, currentOrigin: string): SearchBook[] {
    const filtered: SearchBook[] = [];
    const seen = new Set<string>();
    for (const result of results) {
      if (!result.bookUrl || SearchBookShelfHelper.isNavigationResult(result) ||
        (result.bookUrl === currentBookUrl && result.origin === currentOrigin)) continue;
      const key = `${result.origin || ''}\n${result.bookUrl}`;
      if (seen.has(key)) continue;
      seen.add(key);
      filtered.push(result);
    }
    return filtered;
  }

  buildSourceBook(searchBook: SearchBook, oldBook: Book): Book {
    const book = new Book();
    book.bookUrl = searchBook.bookUrl;
    book.tocUrl = searchBook.tocUrl;
    book.origin = searchBook.origin;
    book.originName = searchBook.originName;
    book.name = searchBook.name || oldBook.name;
    book.author = searchBook.author || oldBook.author;
    book.kind = BookFieldSanitizer.prefer(searchBook.kind, oldBook.kind);
    book.status = BookFieldSanitizer.prefer(searchBook.status, oldBook.status);
    book.coverUrl = CoverUrlNormalizer.prefer(searchBook.coverUrl, oldBook.coverUrl);
    book.customCoverUrl = oldBook.customCoverUrl;
    book.intro = BookFieldSanitizer.prefer(searchBook.intro, oldBook.intro);
    book.customIntro = oldBook.customIntro;
    book.latestChapterTitle = BookFieldSanitizer.prefer(searchBook.latestChapterTitle, oldBook.latestChapterTitle);
    book.updateTime = BookFieldSanitizer.prefer(searchBook.updateTime, oldBook.updateTime);
    book.wordCount = BookFieldSanitizer.prefer(searchBook.wordCount, oldBook.wordCount);
    book.variable = searchBook.variable || '';
    book.group = oldBook.group;
    book.isPinned = oldBook.isPinned;
    book.order = oldBook.order;
    book.originOrder = oldBook.originOrder;
    book.readConfig = oldBook.readConfig;
    book.canUpdate = oldBook.canUpdate;
    book.type = oldBook.type;
    book.durChapterIndex = oldBook.durChapterIndex;
    book.durChapterPos = oldBook.durChapterPos;
    book.durChapterTitle = oldBook.durChapterTitle;
    book.durChapterTime = oldBook.durChapterTime;
    book.pendingAddToShelf = oldBook.pendingAddToShelf;
    if (this.markReadOnSwitch) {
      book.putVariable('readStarted', '1');
      book.putVariable('lastReadTime', `${Date.now()}`);
    }
    return book;
  }

  preserveSourceBookState(target: Book, source: Book, oldBook: Book): void {
    target.origin = source.origin;
    target.originName = source.originName;
    target.coverUrl = CoverUrlNormalizer.prefer(source.coverUrl, target.coverUrl);
    target.group = oldBook.group;
    target.isPinned = oldBook.isPinned;
    target.order = oldBook.order;
    target.originOrder = oldBook.originOrder;
    target.customCoverUrl = oldBook.customCoverUrl;
    target.customIntro = oldBook.customIntro;
    target.readConfig = oldBook.readConfig;
    target.canUpdate = oldBook.canUpdate;
    target.durChapterIndex = oldBook.durChapterIndex;
    target.durChapterPos = oldBook.durChapterPos;
    target.durChapterTitle = oldBook.durChapterTitle;
    target.durChapterTime = oldBook.durChapterTime;
    target.syncTime = oldBook.syncTime;
    target.pendingAddToShelf = oldBook.pendingAddToShelf;
    if (this.markReadOnSwitch) {
      target.putVariable('readStarted', '1');
      target.putVariable('lastReadTime', `${Date.now()}`);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.requestClose();
        })

      Column() {
        Row() {
          Column({ space: 3 }) {
            Text('换源')
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
            Text(`《${this.targetBook?.name || ''}》`)
              .fontSize(12)
              .fontColor(this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.searching) {
            LoadingProgress()
              .width(26)
              .height(26)
              .margin({ right: 14 })
          } else {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(21)
              .fontColor([this.primaryTextColor()])
              .width(40)
              .height(40)
              .margin({ right: 4 })
              .onClick(() => this.refreshResults())
          }
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([this.primaryTextColor()])
            .width(40)
            .height(40)
            .onClick(() => {
              this.requestClose();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.status || '将使用当前书名进行全词匹配搜索')
          .fontSize(13)
          .fontColor(this.subTextColor())
          .width('100%')
          .margin({ top: 8, bottom: 10 })

        if (this.searching && this.results.length === 0) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36)
            Text('正在搜索可用书源...')
              .fontSize(13)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .height(260)
          .justifyContent(FlexAlign.Center)
        } else if (this.results.length === 0) {
          Text('暂无可切换书源')
            .fontSize(15)
            .fontColor(this.subTextColor())
            .width('100%')
            .height(260)
            .textAlign(TextAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.results, (book: SearchBook) => {
              ListItem() {
                Row() {
                  Column({ space: 4 }) {
                    Text(book.originName || book.origin)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.primaryTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`作者：${book.author || '未知'}`)
                      .fontSize(12)
                      .fontColor(this.subTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`最新：${book.latestChapterTitle || '书源未提供'}`)
                      .fontSize(12)
                      .fontColor(this.subTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Button(this.switching ? '切换中' : '切换')
                    .width(68)
                    .height(32)
                    .fontSize(13)
                    .borderRadius(16)
                    .backgroundColor(this.buttonColor())
                    .fontColor('#FFFFFF')
                    .enabled(!this.switching)
                    .onClick(() => this.switchSource(book))
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.inputColor())
                .borderRadius(10)
              }
            }, (book: SearchBook) => `${book.origin}|${book.bookUrl}`)

            if (this.searching) {
              ListItem() {
                Row({ space: 8 }) {
                  LoadingProgress().width(20).height(20)
                  Text('继续加载中...').fontSize(13).fontColor(this.subTextColor())
                }
                .width('100%')
                .height(42)
                .justifyContent(FlexAlign.Center)
              }
            }
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%')
          .height(340)
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .clip(true)
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
    }
    .width('100%')
    .height('100%')
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }
}
