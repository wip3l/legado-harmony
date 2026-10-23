import { BookCover } from '../components/book/BookCover';
import { router, promptAction } from '@kit.ArkUI';
import { Book } from '@legado/sourceengine';
import { appDb } from '../model/data/AppDatabase';
import { LocalBookService } from '../core/book/LocalBookService';
import { OpdsBookService } from '../opds/OpdsBookService';
import { OpdsClient, OpdsDownloadHandle } from '../opds/OpdsClient';
import { OpdsError } from '../opds/OpdsError';
import {
  OpdsEntry,
  OpdsFacetGroup,
  OpdsFeed,
  OpdsFeedCacheEntry,
  OpdsLink,
  OpdsSearchTemplate,
  OpdsServerConfig
} from '../opds/OpdsModels';
import { OpdsSecretStore } from '../opds/OpdsSecretStore';
import { OpdsSettingsStore } from '../opds/OpdsSettingsStore';
import { BookCoverCache } from '../utils/BookCoverCache';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

class OpdsNavFrame {
  url: string = '';
  title: string = '';
}

class OpdsDownloadRow {
  key: string = '';
  link: OpdsLink = new OpdsLink();
  formatLabel: string = '';
  sizeText: string = '';
  kind: string = '';
  kindLabel: string = '';
  downloadable: boolean = false;
  exists: boolean = false;
  downloading: boolean = false;
  received: number = 0;
  total: number = 0;
}

class OpdsEntryDataSource implements IDataSource {
  private entries: OpdsEntry[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.entries.length;
  }

  getData(index: number): OpdsEntry {
    return this.entries[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(entries: OpdsEntry[]): void {
    this.entries = entries.slice();
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

@Entry
@Component
struct OpdsBrowsePage {
  private static readonly FEED_TTL_MS: number = 5 * 60 * 1000;
  private static readonly MAX_PAGES: number = 50;
  private static readonly MAX_COVER_BYTES: number = 5 * 1024 * 1024;

  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @StorageProp('searchExploreUseBookshelfCoverGallery') useBookshelfCover: boolean = false;
  @State server: OpdsServerConfig = new OpdsServerConfig();
  @State serverMissing: boolean = false;
  @State stack: OpdsNavFrame[] = [];
  @State @Watch('onEntriesChanged') entries: OpdsEntry[] = [];
  @State facets: OpdsFacetGroup[] = [];
  @State loading: boolean = false;
  @State loadingMore: boolean = false;
  @State hasMore: boolean = false;
  @State errorCode: string = '';
  @State errorMessage: string = '';
  @State emptyHint: string = '这个书库还是空的';
  @State searchAvailable: boolean = false;
  @State searchMode: boolean = false;
  @State searchInput: string = '';
  @State searchLabel: string = '';
  @State coverMap: Map<string, string> = new Map();
  @State @Watch('onDetailFlagChanged') showDetail: boolean = false;
  @State detailEntry: OpdsEntry = new OpdsEntry();
  @State detailText: string = '';
  @State detailTextLong: boolean = false;
  @State detailTextExpanded: boolean = false;
  @State downloadRows: OpdsDownloadRow[] = [];
  @State downloadBusy: boolean = false;
  @State downloadText: string = '';
  @State downloadProgress: number = 0;

  private password: string = '';
  private client: OpdsClient | null = null;
  private searchTemplate: OpdsSearchTemplate | null = null;
  private feedCache: Map<string, OpdsFeedCacheEntry> = new Map();
  private pendingCovers: Set<string> = new Set();
  private readonly entrySource: OpdsEntryDataSource = new OpdsEntryDataSource();
  private requestSeq: number = 0;
  private nextUrl: string = '';
  private pageCount: number = 0;
  private lastSearchQuery: string = '';
  private activeDownload: OpdsDownloadHandle | null = null;
  private keepDownloadOnDetailClose: boolean = false;
  private detailBestRow: OpdsDownloadRow | null = null;
  private detailImportedBook: Book | null = null;
  private pendingPreviewBook: Book | null = null;
  private retryOnPageShow: boolean = false;
  private initialized: boolean = false;
  private readonly detailDialogSession: SystemDialogSession = new SystemDialogSession();
  private readonly searchController: TextInputController = new TextInputController();

  aboutToAppear(): void {
    this.syncBars();
    if (this.initialized) return;
    this.initialized = true;
    this.bootstrap();
  }

  onPageShow(): void {
    this.syncBars();
    if (this.pendingPreviewBook) {
      const book = this.pendingPreviewBook;
      this.pendingPreviewBook = null;
      this.confirmPreviewShelf(book);
    }
    if (!this.retryOnPageShow) return;
    this.retryOnPageShow = false;
    this.retry();
  }

  onBackPress(): boolean {
    if (this.searchMode) {
      this.exitSearch();
      return true;
    }
    if (this.stack.length > 1) {
      this.goBack();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.serverMissing || this.errorMessage) {
          this.errorView();
        } else {
          this.browseBody();
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 56 + this.statusBarHeight })

      this.titleBar()

      if (this.downloadBusy) {
        Column({ space: AppSpacing.LG }) {
          Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.accentColor())
          Text(this.downloadText || '正在下载...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .maxLines(2)
            .textAlign(TextAlign.Center)
          Button('取消')
            .height(36)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.cancelActiveDownload())
        }
        .width('78%')
        .padding(AppSpacing.XXL)
        .borderRadius(ThemeRuntime.cardRadius())
        .backgroundColor(this.cardColor())
        .shadow({ radius: 18, color: this.appDarkMode ? '#66000000' : '#28000000' })
        .position({ x: '11%', y: '42%' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => this.goBack() })
      if (this.searchMode) {
        this.searchBar()
      } else {
        Text(this.currentTitle())
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20)
          .fontColor([this.searchAvailable ? this.accentColor() : this.subTextColor()])
          .padding(AppSpacing.MD)
          .onClick(() => this.toggleSearch())
      }
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ top: this.statusBarHeight, right: AppSpacing.SM })
    .alignItems(VerticalAlign.Center)
    .position({ x: 0, y: 0 })
    .zIndex(3)
  }

  @Builder
  searchBar() {
    if (this.searchLabel) {
      Row({ space: AppSpacing.MD }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([this.accentColor()])
        Text(this.searchLabel)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('修改')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.accentColor())
          .padding(AppSpacing.MD)
          .onClick(() => {
            this.searchLabel = '';
          })
      }
      .layoutWeight(1)
      .height(40)
    } else {
      Row({ space: AppSpacing.MD }) {
        TextInput({ text: this.searchInput, placeholder: '输入书名或作者',
          controller: this.searchController })
          .layoutWeight(1)
          .height(38)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.softColor())
          .borderRadius(19)
          .defaultFocus(true)
          .onChange((value: string) => {
            this.searchInput = value;
          })
          .onSubmit(() => {
            this.submitSearch();
          })
        Text('取消')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .padding(AppSpacing.MD)
          .onClick(() => this.exitSearch())
      }
      .layoutWeight(1)
      .height(40)
    }
  }

  @Builder
  browseBody() {
    Column() {
      if (this.facets.length > 0) {
        this.facetBar();
      }
      if (this.loading && this.entries.length === 0) {
        Column({ space: AppSpacing.MD }) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.accentColor())
          Text('加载中...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.entries.length === 0) {
        Column({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.book'))
            .fontSize(40)
            .fontColor([this.subTextColor()])
          Text(this.emptyHint)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        this.feedList();
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  facetBar() {
    Column({ space: AppSpacing.XXS }) {
      ForEach(this.facets, (group: OpdsFacetGroup) => {
        Scroll() {
          Row({ space: AppSpacing.MD }) {
            ForEach(group.links, (link: OpdsLink) => {
              Text(this.facetLabel(group, link))
                .fontSize(AppFontSize.CAPTION)
                .fontColor(link.activeFacet ? '#FFFFFF' : this.primaryTextColor())
                .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
                .backgroundColor(link.activeFacet ? this.accentColor() : this.softColor())
                .borderRadius(ThemeRuntime.buttonRadius())
                .onClick(() => this.openFacet(link))
            }, (link: OpdsLink) => `${group.group}:${link.href}`)
          }
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(34)
        .align(Alignment.Start)
      }, (group: OpdsFacetGroup) => group.group)
    }
    .width('100%')
    .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
  }

  @Builder
  feedList() {
    List({ space: AppSpacing.MD }) {
      LazyForEach(this.entrySource, (entry: OpdsEntry) => {
        ListItem() {
          this.feedItem(entry)
        }
      }, (entry: OpdsEntry, index: number) => this.entryKey(entry, index))

      if (this.loadingMore) {
        ListItem() {
          Row({ space: AppSpacing.MD }) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(this.accentColor())
            Text('加载中...')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .height(40)
          .justifyContent(FlexAlign.Center)
        }
      } else if (!this.hasMore) {
        ListItem() {
          Text('没有更多了')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .width('100%')
            .height(40)
            .textAlign(TextAlign.Center)
        }
      }

      ListItem() {
        Column()
          .height(Math.max(12, this.navBarHeight))
      }
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .onReachEnd(() => this.onListReachEnd())
  }

  @Builder
  feedItem(entry: OpdsEntry) {
    if (entry.isPublication()) {
      this.bookItem(entry)
    } else {
      this.navItem(entry)
    }
  }

  @Builder
  navItem(entry: OpdsEntry) {
    Row({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(26)
        .fontColor([this.accentColor()])
      Column({ space: AppSpacing.XS }) {
        Text(entry.title || '未命名目录')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.navSubtitle(entry)) {
          Text(this.navSubtitle(entry))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(17)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(60)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .onClick(() => this.openEntryLink(entry))
  }

  @Builder
  bookItem(entry: OpdsEntry) {
    Row({ space: AppSpacing.LG }) {
      this.entryCover(entry)
      Column({ space: AppSpacing.XS }) {
        Text(entry.title || '未命名')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(entry.displayAuthor() || entry.publisher || '作者未知')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.bookFormatLabel(entry)) {
        Text(this.bookFormatLabel(entry))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
          .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
          .backgroundColor(this.softColor())
          .borderRadius(ThemeRuntime.mediumRadius())
      }
    }
    .width('100%')
    .height(84)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .onClick(() => this.openDetail(entry))
  }

  @Builder
  entryCover(entry: OpdsEntry) {
    BookCover({ bookUrl: entry.id, origin: 'opds', name: entry.title, author: entry.authors.join('、'),
      coverUrl: this.coverOf(entry.artworkThumbnail()), useBookshelfCover: this.useBookshelfCover,
      placeholderColor: this.accentColor() })
      .width(48)
      .height(64)
    .onAppear(() => this.ensureEntryCover(entry))
  }

  @Builder
  errorView() {
    Column({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(42)
        .fontColor([this.subTextColor()])
      Text(this.errorMessage || '服务器配置不存在')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
      if (this.serverMissing) {
        Button('返回')
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => router.back())
      } else {
        Button('重试')
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => this.retry())
        if (this.errorCode === 'auth') {
          Button('网页登录')
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.openWebLogin())
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(36)
  }

  @Builder
  detailDialogContent() {
    Scroll() {
      Column({ space: AppSpacing.LG }) {
        Row({ space: AppSpacing.LG }) {
          this.detailCoverView()
          Column({ space: AppSpacing.SM }) {
            Text(this.detailEntry.title || '未命名')
              .fontSize(AppFontSize.SUBTITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
            if (this.detailEntry.displayAuthor()) {
              Text(this.detailEntry.displayAuthor())
                .fontSize(AppFontSize.BODY)
                .fontColor(this.subTextColor())
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.detailEntry.publisher) {
              Text(`出版社：${this.detailEntry.publisher}`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.detailEntry.series) {
              Text(`系列：${this.detailEntry.series}`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.detailEntry.language) {
              Text(`语言：${this.detailEntry.language}`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        if (this.detailText) {
          Column({ space: AppSpacing.SM }) {
            Text(this.detailText)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .maxLines(this.detailTextExpanded ? 100 : 8)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.detailTextLong) {
              Text(this.detailTextExpanded ? '收起' : '展开')
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.accentColor())
                .width('100%')
                .onClick(() => {
                  this.detailTextExpanded = !this.detailTextExpanded;
                })
            }
          }
          .width('100%')
          .padding(AppSpacing.LG)
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(this.softColor())
        }

        this.detailPrimaryActions()

        if (this.downloadRows.length > 0) {
          Text('获取本书')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .width('100%')
          ForEach(this.downloadRows, (row: OpdsDownloadRow) => {
            this.downloadRowView(row)
          }, (row: OpdsDownloadRow) => row.key)
        } else {
          Text('该书库没有提供获取链接')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .width('100%')
        }
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: 460 })
    .padding(AppSpacing.XXL)
  }

  @Builder
  detailCoverView() {
    BookCover({ bookUrl: this.detailEntry.id, origin: 'opds', name: this.detailEntry.title, author: this.detailEntry.authors.join('、'),
      coverUrl: this.coverOf(this.detailArtworkRaw()), useBookshelfCover: this.useBookshelfCover,
      placeholderColor: this.accentColor(), cornerRadius: 8 })
      .width(96)
      .height(128)
  }

  @Builder
  detailPrimaryActions() {
    Row({ space: AppSpacing.MD }) {
      if (this.detailImportedBook) {
        Button('立即阅读')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(this.accentColor())
          .onClick(() => this.readDetailBook())
        Button('移出书架')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .backgroundColor(this.softColor())
          .onClick(() => this.removeDetailBook())
      } else if (this.detailBestRow && this.detailBestRow.downloadable) {
        Button('在线预览')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .backgroundColor(this.softColor())
          .onClick(() => this.startBestPreview())
        Button('加入书架')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(this.accentColor())
          .onClick(() => this.addBestToShelf())
      } else if (this.downloadRows.length > 0) {
        Text('该获取方式暂不支持，请到书库网页端操作')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
  }

  addBestToShelf(): void {
    const row = this.detailBestRow;
    if (!row) return;
    this.startDownload(row);
  }

  startBestPreview(): void {
    const row = this.detailBestRow;
    if (!row || row.downloading || this.downloadBusy || this.activeDownload) return;
    row.downloading = true;
    row.received = 0;
    row.total = 0;
    this.refreshDownloadRows();
    this.downloadBusy = true;
    this.downloadProgress = 0;
    this.downloadText = `正在下载《${this.detailEntry.title}》...`;
    this.keepDownloadOnDetailClose = true;
    this.showDetail = false;
    let lastUpdate = 0;
    const onProgress = (received: number, total: number): void => {
      row.received = received;
      row.total = total;
      const now = Date.now();
      if (now - lastUpdate > 200 || (total > 0 && received >= total)) {
        lastUpdate = now;
        this.updateDownloadFeedback(received, total);
      }
    };
    OpdsBookService.downloadAndImport(getContext(this), this.server, this.password, row.link,
      this.detailEntry.title, onProgress, (handle: OpdsDownloadHandle): void => {
        this.activeDownload = handle;
      }).then((book: Book): void => {
        row.downloading = false;
        row.exists = true;
        this.activeDownload = null;
        this.downloadBusy = false;
        this.pendingPreviewBook = book;
        this.refreshDownloadRows();
        router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: book.bookUrl } })
          .catch((error: Error) => {
            HdsFeedback.showToast(`打开阅读失败：${OpdsError.message(error)}`);
          });
      }).catch((error: Object): void => {
        row.downloading = false;
        this.activeDownload = null;
        this.downloadBusy = false;
        this.refreshDownloadRows();
        if (error instanceof OpdsError && error.code === 'cancelled') return;
        HdsFeedback.showToast(`下载失败：${OpdsError.message(error)}`);
      });
  }

  readDetailBook(): void {
    const book = this.detailImportedBook;
    if (!book) return;
    router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: book.bookUrl } })
      .catch((error: Error) => {
        HdsFeedback.showToast(`打开阅读失败：${OpdsError.message(error)}`);
      });
  }

  removeDetailBook(): void {
    const book = this.detailImportedBook;
    if (!book) return;
    const run = async (): Promise<void> => {
      try {
        await LocalBookService.deleteBookWithFiles(getContext(this), book.bookUrl);
        this.detailImportedBook = null;
        const row = this.detailBestRow;
        if (row) row.exists = false;
        this.refreshDownloadRows();
        HdsFeedback.showToast('已移出书架');
      } catch (error) {
        HdsFeedback.showToast(`移出失败：${OpdsError.message(error as Object)}`);
      }
    };
    run();
  }

  private confirmPreviewShelf(book: Book): void {
    promptAction.showDialog({
      title: '是否加入书架',
      message: `《${book.name}》已下载到本地缓存`,
      buttons: [
        { text: '移出', color: this.primaryTextColor() },
        { text: '加入书架', color: this.accentColor() }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse): void => {
      if (data.index === 1) {
        HdsFeedback.showToast('已加入书架');
        return;
      }
      const run = async (): Promise<void> => {
        try {
          await LocalBookService.deleteBookWithFiles(getContext(this), book.bookUrl);
          HdsFeedback.showToast('已移出书架');
        } catch (error) {
          HdsFeedback.showToast(`移出失败：${OpdsError.message(error as Object)}`);
        }
      };
      run();
    }).catch(() => {});
  }

  @Builder
  downloadRowView(row: OpdsDownloadRow) {
    Row({ space: AppSpacing.MD }) {
      Text(row.formatLabel)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.accentColor())
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
        .backgroundColor(this.softColor())
        .borderRadius(ThemeRuntime.mediumRadius())
      if (row.sizeText) {
        Text(row.sizeText)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      Text(row.kindLabel)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
  }

  async bootstrap(): Promise<void> {
    const params = router.getParams() as Record<string, string>;
    const serverId = params?.['serverId'] || '';
    const pageTitle = (params?.['title'] || '').trim();
    const context = getContext(this);
    let servers: OpdsServerConfig[] = [];
    try {
      servers = await OpdsSettingsStore.loadServers(context);
    } catch (error) {
      this.errorMessage = OpdsError.message(error, '读取服务器配置失败');
      return;
    }
    const found = servers.find((item: OpdsServerConfig): boolean => item.id === serverId);
    if (!found) {
      this.serverMissing = true;
      this.errorMessage = '服务器配置不存在';
      return;
    }
    this.server = found;
    try {
      this.password = await OpdsSecretStore.password(context, found.id);
    } catch (_) {
      this.password = '';
    }
    this.client = new OpdsClient(found, this.password);
    const root = new OpdsNavFrame();
    root.url = found.baseUrl;
    root.title = pageTitle || found.name;
    this.stack = [root];
    this.loadBrowseFeed(found.baseUrl, true);
  }

  loadBrowseFeed(url: string, useCache: boolean): void {
    const client = this.client;
    if (!client || this.serverMissing) return;
    const seq = ++this.requestSeq;
    this.loading = true;
    this.errorCode = '';
    this.errorMessage = '';
    this.emptyHint = '这个书库还是空的';
    const run = async (): Promise<void> => {
      let catalogUrl = url;
      try {
        let feed: OpdsFeed | null = useCache ? this.cachedFeed(url) : null;
        if (!feed) {
          if (this.stack.length === 1 && url === this.server.baseUrl) {
            const catalog = await client.fetchCatalog(url);
            feed = catalog.feed;
            catalogUrl = catalog.url;
          } else {
            feed = await client.fetchFeed(url);
          }
          this.rememberFeed(url, feed);
        }
        if (seq !== this.requestSeq) return;
        if (catalogUrl !== url && this.stack.length === 1) {
          // 入口地址被自动纠正（尾斜杠、/opds）：后续相对链接、搜索都以实际地址为准，
          // 并存回配置，下次打开不用再试错
          this.rememberFeed(catalogUrl, feed);
          this.stack[0].url = catalogUrl;
          this.server.baseUrl = catalogUrl;
          OpdsSettingsStore.saveServer(getContext(this), this.server).catch((): void => {});
        }
        this.applyFeed(feed);
        if (this.stack.length === 1 && !this.searchTemplate) {
          this.resolveSearchTemplate(catalogUrl, feed, seq);
        }
      } catch (error) {
        if (seq !== this.requestSeq) return;
        this.entries = [];
        this.facets = [];
        this.hasMore = false;
        this.nextUrl = '';
        this.setError(error);
      } finally {
        if (seq === this.requestSeq) this.loading = false;
      }
    };
    run();
  }

  resolveSearchTemplate(feedUrl: string, feed: OpdsFeed, seq: number): void {
    const client = this.client;
    if (!client) return;
    const run = async (): Promise<void> => {
      const template = await client.resolveSearchTemplate(feedUrl, feed);
      if (seq !== this.requestSeq) return;
      if (template) {
        this.searchTemplate = template;
        this.searchAvailable = true;
      }
    };
    run();
  }

  applyFeed(feed: OpdsFeed): void {
    this.entries = feed.entries.slice();
    this.facets = feed.facetGroups();
    this.pageCount = 1;
    const next = feed.nextLink();
    this.nextUrl = next ? next.href : '';
    this.hasMore = !!next && this.pageCount < OpdsBrowsePage.MAX_PAGES;
  }

  cachedFeed(url: string): OpdsFeed | null {
    const hit = this.feedCache.get(url);
    if (!hit) return null;
    if (Date.now() - hit.fetchedAt > OpdsBrowsePage.FEED_TTL_MS) {
      this.feedCache.delete(url);
      return null;
    }
    return hit.feed;
  }

  rememberFeed(url: string, feed: OpdsFeed): void {
    const entry = new OpdsFeedCacheEntry();
    entry.feed = feed;
    entry.fetchedAt = Date.now();
    this.feedCache.set(url, entry);
  }

  openEntryLink(entry: OpdsEntry): void {
    const link = entry.navigationLink();
    if (!link) return;
    const frame = new OpdsNavFrame();
    frame.url = link.href;
    frame.title = entry.title || link.title || '目录';
    this.stack = [...this.stack, frame];
    this.loadBrowseFeed(frame.url, true);
  }

  openFacet(link: OpdsLink): void {
    if (this.stack.length === 0) return;
    const top = this.stack[this.stack.length - 1];
    top.url = link.href;
    if (link.title) top.title = link.title;
    this.stack = this.stack.slice();
    this.loadBrowseFeed(link.href, true);
  }

  goBack(): void {
    if (this.searchMode) {
      this.exitSearch();
      return;
    }
    if (this.stack.length > 1) {
      this.stack = this.stack.slice(0, this.stack.length - 1);
      const top = this.stack[this.stack.length - 1];
      this.loadBrowseFeed(top.url, true);
      return;
    }
    router.back();
  }

  onListReachEnd(): void {
    if (this.loading || this.loadingMore || !this.hasMore) return;
    if (this.pageCount >= OpdsBrowsePage.MAX_PAGES) {
      this.hasMore = false;
      return;
    }
    this.loadNextPage();
  }

  loadNextPage(): void {
    const client = this.client;
    const url = this.nextUrl;
    if (!client || !url) return;
    const seq = this.requestSeq;
    this.loadingMore = true;
    const run = async (): Promise<void> => {
      try {
        const feed = await client.fetchFeed(url);
        if (seq !== this.requestSeq) return;
        this.rememberFeed(url, feed);
        this.pageCount++;
        this.entries = [...this.entries, ...feed.entries];
        const next = feed.nextLink();
        this.nextUrl = next ? next.href : '';
        this.hasMore = !!next && this.pageCount < OpdsBrowsePage.MAX_PAGES;
      } catch (error) {
        if (seq !== this.requestSeq) return;
        HdsFeedback.showToast(`加载失败：${OpdsError.message(error)}`);
      } finally {
        if (seq === this.requestSeq) this.loadingMore = false;
      }
    };
    run();
  }

  toggleSearch(): void {
    if (!this.searchAvailable || !this.searchTemplate) {
      HdsFeedback.showToast('该书库不支持搜索');
      return;
    }
    this.searchMode = true;
    this.searchLabel = '';
  }

  submitSearch(): void {
    const query = this.searchInput.trim();
    const template = this.searchTemplate;
    if (!query) {
      HdsFeedback.showToast('请输入搜索关键词');
      return;
    }
    if (!template) return;
    this.searchController.stopEditing();
    this.runSearch(query, template);
  }

  runSearch(query: string, template: OpdsSearchTemplate): void {
    const client = this.client;
    if (!client) return;
    const seq = ++this.requestSeq;
    this.lastSearchQuery = query;
    this.searchLabel = `搜索：${query}`;
    this.loading = true;
    this.errorCode = '';
    this.errorMessage = '';
    this.emptyHint = '没有找到相关书籍';
    const run = async (): Promise<void> => {
      try {
        const feed = await client.search(template, query);
        if (seq !== this.requestSeq) return;
        this.applyFeed(feed);
      } catch (error) {
        if (seq !== this.requestSeq) return;
        HdsFeedback.showToast(OpdsError.message(error));
      } finally {
        if (seq === this.requestSeq) this.loading = false;
      }
    };
    run();
  }

  exitSearch(): void {
    this.searchMode = false;
    this.searchLabel = '';
    this.requestSeq++;
    if (this.stack.length > 0) {
      this.loadBrowseFeed(this.stack[this.stack.length - 1].url, true);
    }
  }

  retry(): void {
    if (this.serverMissing) return;
    if (!this.client) {
      this.bootstrap();
      return;
    }
    if (this.searchMode && this.lastSearchQuery && this.searchTemplate) {
      this.runSearch(this.lastSearchQuery, this.searchTemplate);
      return;
    }
    if (this.stack.length > 0) {
      this.loadBrowseFeed(this.stack[this.stack.length - 1].url, false);
    }
  }

  openWebLogin(): void {
    const url = this.stack.length > 0 ? this.stack[this.stack.length - 1].url : this.server.baseUrl;
    this.retryOnPageShow = true;
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: this.server.name,
        requireLoginCookie: 'false'
      }
    });
  }

  async openDetail(entry: OpdsEntry): Promise<void> {
    this.detailEntry = entry;
    this.detailText = this.computeDetailText(entry);
    this.detailTextLong = this.detailText.length > 160;
    this.detailTextExpanded = false;
    this.downloadRows = this.buildDownloadRows(entry);
    const best = this.downloadRows.find((item: OpdsDownloadRow): boolean => item.downloadable) || null;
    this.detailBestRow = best;
    this.detailImportedBook = null;
    if (best) {
      try {
        const identity = OpdsBookService.bookIdentityUrl(this.server.id, best.link.href);
        this.detailImportedBook = await appDb.getBook(identity);
      } catch (_) {
        this.detailImportedBook = null;
      }
    }
    this.showDetail = true;
    this.detailDialogSession.open(this.getUIContext(), (): void => {
      this.detailDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示书籍详情弹窗失败:',
      onDismiss: (): void => {
        this.showDetail = false;
      }
    });
    this.ensureCover(this.detailArtworkRaw());
    this.prefetchImportedStates();
  }

  onDetailFlagChanged(): void {
    if (this.showDetail) return;
    this.detailDialogSession.close(this.getUIContext());
    if (this.keepDownloadOnDetailClose) {
      this.keepDownloadOnDetailClose = false;
      return;
    }
    if (this.activeDownload) {
      this.activeDownload.cancel();
      this.activeDownload = null;
    }
  }

  buildDownloadRows(entry: OpdsEntry): OpdsDownloadRow[] {
    const rows: OpdsDownloadRow[] = [];
    const links = entry.acquisitionLinks();
    for (let i = 0; i < links.length; i++) {
      const link = links[i];
      const row = new OpdsDownloadRow();
      row.key = `${entry.id}|${link.href}`;
      row.link = link;
      const format = OpdsBookService.formatOfLink(link);
      row.formatLabel = (format || '文件').toUpperCase();
      row.sizeText = link.length > 0 ? this.formatSize(link.length) : '';
      row.kind = link.acquisitionKind();
      row.kindLabel = this.acquisitionKindLabel(link);
      row.downloadable = OpdsBookService.isDownloadableFormat(format) &&
        (row.kind === 'open-access' || row.kind === 'generic' || row.kind === '');
      rows.push(row);
    }
    return rows;
  }

  prefetchImportedStates(): void {
    const run = async (): Promise<void> => {
      const rows = this.downloadRows;
      for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        if (!row.downloadable) continue;
        try {
          const exists = await OpdsBookService.isAlreadyImported(this.server.id, row.link.href);
          if (exists) row.exists = true;
        } catch (_) {}
      }
      if (this.showDetail) this.downloadRows = this.downloadRows.slice();
    };
    run();
  }

  startDownload(row: OpdsDownloadRow): void {
    if (row.downloading) return;
    if (this.activeDownload || this.downloadBusy) {
      HdsFeedback.showToast('已有下载在进行中，请先完成或取消');
      return;
    }
    row.downloading = true;
    row.received = 0;
    row.total = 0;
    this.refreshDownloadRows();
    this.downloadBusy = true;
    this.downloadProgress = 0;
    this.downloadText = `正在下载《${this.detailEntry.title}》...`;
    // 系统弹窗盖在页面层之上，进度浮层会被遮挡；开始下载时收起详情弹窗
    this.keepDownloadOnDetailClose = true;
    this.showDetail = false;
    let lastUpdate = 0;
    const onProgress = (received: number, total: number): void => {
      row.received = received;
      row.total = total;
      const now = Date.now();
      if (now - lastUpdate > 200 || (total > 0 && received >= total)) {
        lastUpdate = now;
        this.refreshDownloadRows();
        this.updateDownloadFeedback(received, total);
      }
    };
    OpdsBookService.downloadAndImport(getContext(this), this.server, this.password, row.link,
      this.detailEntry.title, onProgress, (handle: OpdsDownloadHandle): void => {
        this.activeDownload = handle;
      }).then((_book: Book): void => {
        row.downloading = false;
        row.exists = true;
        this.activeDownload = null;
        this.downloadBusy = false;
        this.refreshDownloadRows();
        HdsFeedback.showToast('已加入书架');
      }).catch((error: Object): void => {
        row.downloading = false;
        this.activeDownload = null;
        this.downloadBusy = false;
        this.refreshDownloadRows();
        if (error instanceof OpdsError && error.code === 'cancelled') return;
        HdsFeedback.showToast(`下载失败：${OpdsError.message(error)}`);
      });
  }

  private updateDownloadFeedback(received: number, total: number): void {
    if (total > 0) {
      this.downloadProgress = Math.min(100, Math.floor(received / total * 100));
      this.downloadText = `正在下载《${this.detailEntry.title}》... ${this.downloadProgress}%`;
    } else {
      this.downloadText = `正在下载《${this.detailEntry.title}》... ${(received / 1024 / 1024).toFixed(1)} MB`;
    }
  }

  cancelActiveDownload(): void {
    const handle = this.activeDownload;
    if (handle) handle.cancel();
  }

  refreshDownloadRows(): void {
    this.downloadRows = this.downloadRows.slice();
  }

  computeDetailText(entry: OpdsEntry): string {
    const raw = entry.displayText();
    if (!raw) return '';
    if (entry.contentIsHtml || entry.summaryIsHtml) return OpdsBrowsePage.stripHtml(raw);
    return raw.trim();
  }

  ensureEntryCover(entry: OpdsEntry): void {
    const raw = entry.artworkThumbnail();
    if (!raw) return;
    this.ensureCover(raw);
  }

  ensureCover(raw: string): void {
    if (!raw) return;
    if (this.coverMap.has(raw) || this.pendingCovers.has(raw)) return;
    this.pendingCovers.add(raw);
    const run = async (): Promise<void> => {
      try {
        const context = getContext(this);
        const local = await BookCoverCache.resolveCachedCoverAsync(context, raw) ||
          await this.fetchProtectedCover(raw) ||
          await BookCoverCache.resolveCover(context, raw);
        if (!local) return;
        const next = new Map(this.coverMap);
        next.set(raw, local);
        this.coverMap = next;
      } catch (_) {
      } finally {
        this.pendingCovers.delete(raw);
      }
    };
    run();
  }

  // 开启登录的书库（如 Calibre）封面也要带凭据，通用封面缓存不带认证头取不到
  async fetchProtectedCover(raw: string): Promise<string> {
    const client = this.client;
    if (!client || !client.usesCredentialsFor(raw)) return '';
    try {
      const data = await client.fetchBinary(raw, OpdsBrowsePage.MAX_COVER_BYTES);
      return await BookCoverCache.storeCover(getContext(this), raw, data);
    } catch (_) {
      return '';
    }
  }

  coverOf(raw: string): string {
    const hit = this.coverMap.get(raw);
    return hit || '';
  }

  detailArtworkRaw(): string {
    const image = this.detailEntry.artworkImage();
    return image ? image : this.detailEntry.artworkThumbnail();
  }

  currentTitle(): string {
    if (this.stack.length === 0) return '';
    return this.stack[this.stack.length - 1].title;
  }

  entryKey(entry: OpdsEntry, index: number): string {
    return entry.id || `${index}_${entry.title}`;
  }

  navSubtitle(entry: OpdsEntry): string {
    const raw = entry.displayText();
    if (!raw) return '';
    const text = entry.contentIsHtml || entry.summaryIsHtml ? OpdsBrowsePage.stripHtml(raw) : raw;
    return text.trim();
  }

  bookFormatLabel(entry: OpdsEntry): string {
    const links = entry.acquisitionLinks();
    if (links.length === 0) return '';
    const format = OpdsBookService.formatOfLink(links[0]);
    const label = (format || '文件').toUpperCase();
    const sizeText = links[0].length > 0 ? ` · ${this.formatSize(links[0].length)}` : '';
    return `${label}${sizeText}`;
  }

  facetLabel(group: OpdsFacetGroup, link: OpdsLink): string {
    const base = link.title || group.group || '筛选';
    return link.facetCount > 0 ? `${base}（${link.facetCount}）` : base;
  }

  acquisitionKindLabel(link: OpdsLink): string {
    const kind = link.acquisitionKind();
    if (kind === 'buy') {
      if (!link.price) return '购买';
      const currency = link.priceCurrency ? ` ${link.priceCurrency}` : '';
      return `购买 · ${link.price}${currency}`;
    }
    if (kind === 'borrow') return '借阅';
    if (kind === 'sample') return '试读';
    if (kind === 'subscribe') return '订阅';
    if (kind === 'open-access' || kind === '') return '免费获取';
    return '获取';
  }

  formatSize(size: number): string {
    if (size < 1024) return `${size} B`;
    if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
    if (size < 1024 * 1024 * 1024) return `${(size / 1024 / 1024).toFixed(1)} MB`;
    return `${(size / 1024 / 1024 / 1024).toFixed(2)} GB`;
  }

  setError(error: Object): void {
    if (error instanceof OpdsError) {
      this.errorCode = error.code;
      this.errorMessage = error.userMessage;
    } else {
      this.errorCode = 'unknown';
      this.errorMessage = OpdsError.message(error);
    }
  }

  onEntriesChanged(): void {
    this.entrySource.replace(this.entries);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  static stripHtml(input: string): string {
    let text = (input || '').replace(/<[^>]+>/g, ' ');
    text = text.split('&amp;').join('&')
      .split('&lt;').join('<')
      .split('&gt;').join('>')
      .split('&quot;').join('"')
      .split('&apos;').join("'");
    return text.replace(/[ \t\r\n]+/g, ' ').trim();
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
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

  softColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }
}
