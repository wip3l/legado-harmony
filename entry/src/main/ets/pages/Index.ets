import { router, window } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import deviceInfo from '@ohos.deviceInfo';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import commonEventManager from '@ohos.commonEventManager';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { Book, BookChapter, BookSource, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchCoordinator, SearchCallback, SearchProgress } from '../core/book/SearchCoordinator';
import { ExploreCoordinator, ExploreEntry, ExploreSourceOption } from '../core/book/ExploreCoordinator';
import { ReadBookEngine } from '../core/book/ReadBookEngine';
import { SearchBookResultList } from '../components/book/SearchBookResultList';
import { syncSystemSafeAreas } from '../utils/SystemBars';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { BookCoverCache } from '../utils/BookCoverCache';
import { CoverGallerySettings } from '../utils/CoverGallerySettings';
import { BookshelfDisplaySettingsStore } from '../utils/BookshelfDisplaySettingsStore';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';
import { BookshelfSortHelper } from '../utils/BookshelfSortHelper';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';

const SHELF_FULL_TEXT_CACHE_CANCEL_EVENT: string = 'com.legado.harmony.action.SHELF_FULL_TEXT_CACHE_CANCEL';

interface FullTextCacheCancelSignal {
  nonce: number;
  taskKey: string;
  bookUrl: string;
}

interface ShelfFullTextCacheTask {
  taskId: number;
  bookUrl: string;
  bookName: string;
  taskKey: string;
  createdAt: number;
  cancelRequested: boolean;
  cancelSeenNonce: number;
  notificationLastAt: number;
  cancelAgent: WantAgent | null;
  done: number;
  total: number;
  status: string;
  coverPixelMap: image.PixelMap | null;
  notificationFailureHintShown: boolean;
}

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('appDarkMode') @Watch('onAppDarkModeChanged') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('launchShortcutNonce') @Watch('onLaunchShortcutChanged') launchShortcutNonce: number = 0;

  aboutToAppear() {
    hilog.info(0x0000, 'testTag', 'StartupTrace Index aboutToAppear %{public}d', Date.now());
    this.syncHomeSystemBars();
    this.openPendingShortcut();
  }

  onPageShow(): void {
    hilog.info(0x0000, 'testTag', 'StartupTrace Index onPageShow %{public}d', Date.now());
    this.syncHomeSystemBars();
  }

  onAppDarkModeChanged(): void {
    this.syncHomeSystemBars();
  }

  onLaunchShortcutChanged(): void {
    this.openPendingShortcut();
  }

  async openPendingShortcut(): Promise<void> {
    if (!RecentReadShortcut.isPending()) {
      return;
    }
    try {
      await RecentReadShortcut.openPending(getContext(this));
      RecentReadShortcut.consume();
    } catch (e) {
      RecentReadShortcut.consume();
      console.error('打开最近阅读快捷项失败:', e);
    }
  }

  build() {
    if (this.supportsImmersiveTabs()) {
      this.immersiveTabs()
    } else {
      this.compatTabs()
    }
  }

  supportsImmersiveTabs(): boolean {
    return deviceInfo.sdkApiVersion >= 23;
  }

  @Builder
  immersiveTabs() {
    HdsTabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
      TabContent() {
        if (this.currentIndex === 0) {
          BookshelfPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar($r('app.media.ic_tab_bookshelf'), '书架'))

      TabContent() {
        if (this.currentIndex === 1) {
          ExplorePage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isActive: true
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar($r('app.media.ic_tab_explore'), '发现'))

      TabContent() {
        if (this.currentIndex === 2) {
          SearchPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isActive: true
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar($r('app.media.ic_tab_search'), '搜索'))

      TabContent() {
        if (this.currentIndex === 3) {
          SettingsPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar($r('app.media.ic_tab_mine'), '我的'))
    }
    .barMode(BarMode.Fixed)
    .barOverlap(true)
    .barFloatingStyle({
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      barBottomMargin: this.floatingBarBottomMargin(),
      gradientMask: {
        maskColor: '#00000000',
        maskHeight: 96
      },
      adaptToHandedness: true,
      thermoCtrl: true,
      barOpacity: 1
    })
    .scrollable(false)
    .onChange((index: number) => {
      this.currentIndex = index;
      this.syncHomeSystemBars();
    })
    .width('100%')
    .height('100%')
    .backgroundColor(this.appDarkMode ? '#101113' : '#F5F5F5')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  compatTabs() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
      TabContent() {
        if (this.currentIndex === 0) {
          BookshelfPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar($r('app.media.ic_tab_bookshelf'), '书架', 0))

      TabContent() {
        if (this.currentIndex === 1) {
          ExplorePage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isActive: true
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar($r('app.media.ic_tab_explore'), '发现', 1))

      TabContent() {
        if (this.currentIndex === 2) {
          SearchPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isActive: true
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar($r('app.media.ic_tab_search'), '搜索', 2))

      TabContent() {
        if (this.currentIndex === 3) {
          SettingsPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar($r('app.media.ic_tab_mine'), '我的', 3))
    }
    .barMode(BarMode.Fixed)
    .barHeight(56 + this.compatTabSafeHeight())
    .barBackgroundColor(this.appDarkMode ? '#191B1F' : '#FFFFFF')
    .scrollable(false)
    .onChange((index: number) => {
      this.currentIndex = index;
      this.syncHomeSystemBars();
    })
    .width('100%')
    .height('100%')
    .backgroundColor(this.appDarkMode ? '#101113' : '#F5F5F5')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  bottomTabBar(icon: Resource, title: string): BottomTabBarStyle {
    return BottomTabBarStyle.of(icon, title)
      .labelStyle({
        font: { size: 11 },
        selectedColor: this.tabBarActiveColor(),
        unselectedColor: this.tabBarTextColor()
      })
      .iconStyle({
        selectedColor: this.tabBarActiveColor(),
        unselectedColor: this.tabBarTextColor()
      })
      .padding({ left: 4, right: 4, top: 0, bottom: 0 })
      .layoutMode(LayoutMode.VERTICAL)
      .verticalAlign(VerticalAlign.Center);
  }

  @Builder
  compatTabBar(icon: Resource, title: string, index: number) {
    Column() {
      Column({ space: 2 }) {
        Column() {
          Image(icon)
            .width(22)
            .height(22)
            .fillColor(this.currentIndex === index ? this.tabBarActiveColor() : this.tabBarTextColor())
        }
        .width(24)
        .height(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text(title)
          .fontSize(11)
          .lineHeight(14)
          .height(14)
          .fontColor(this.currentIndex === index ? this.tabBarActiveColor() : this.tabBarTextColor())
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height(56 + this.compatTabSafeHeight())
    .padding({ bottom: this.compatTabSafeHeight() })
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  syncHomeSystemBars(): void {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      const bg = this.appDarkMode ? '#101113' : '#F5F5F5';
      mainWindow.setWindowBackgroundColor(bg);
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
      syncSystemSafeAreas(mainWindow);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        isStatusBarLightIcon: this.appDarkMode,
        statusBarContentColor: this.appDarkMode ? '#FFFFFF' : '#1F1F1F',
        navigationBarColor: '#00000000',
        isNavigationBarLightIcon: this.appDarkMode,
        navigationBarContentColor: this.appDarkMode ? '#FFFFFF' : '#1F1F1F'
      });
    }).catch((err: Error) => {
      console.error('同步首页系统栏颜色失败:', err);
    });
  }

  tabBarActiveColor(): string {
    return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  tabBarTextColor(): string {
    return this.appDarkMode ? '#E7E9ED' : '#5F6670';
  }

  floatingBarBottomMargin(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 8;
  }

  compatTabSafeHeight(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 24;
  }

}

@Component
struct FastBookshelfShell {
  @Prop statusBarHeight: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;

  build() {
    Column() {
      Row() {
        Text('书架')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Column({ space: 10 }) {
        this.placeholderCard(0.92)
        this.placeholderCard(0.78)
        this.placeholderCard(0.86)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  placeholderCard(widthRatio: number) {
    Row() {
      Column()
        .width(56)
        .height(72)
        .borderRadius(6)
        .backgroundColor(this.appDarkMode ? '#24272D' : '#E6E9EE')

      Column({ space: 8 }) {
        Column()
          .width(`${Math.floor(widthRatio * 100)}%`)
          .height(16)
          .borderRadius(8)
          .backgroundColor(this.appDarkMode ? '#24272D' : '#E2E5EA')
        Column()
          .width('48%')
          .height(12)
          .borderRadius(6)
          .backgroundColor(this.appDarkMode ? '#202329' : '#ECEEF2')
        Column()
          .width('34%')
          .height(12)
          .borderRadius(6)
          .backgroundColor(this.appDarkMode ? '#202329' : '#ECEEF2')
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor(this.appDarkMode ? '#191B1F' : '#FFFFFF')
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }
}

@Component
struct BlankTabPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(this.appDarkMode ? '#101113' : '#F5F5F5')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}

@Component
struct BookshelfPage {
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @State books: Book[] = [];
  @State isLoading: boolean = false;
  @State showDeleteDialog: boolean = false;
  @State showActionDialog: boolean = false;
  @State showTagDialog: boolean = false;
  @State showCacheDialog: boolean = false;
  @State showChapterCacheDialog: boolean = false;
  @State pendingDeleteBook: Book | null = null;
  @State pendingActionBook: Book | null = null;
  @State cacheTargetBook: Book | null = null;
  @State cacheChapters: BookChapter[] = [];
  @State cacheStatus: string = '';
  @State isCaching: boolean = false;
  @State activeFullTextCacheBookUrls: string[] = [];
  @State isCacheTocLoading: boolean = false;
  @State isShelfRefreshing: boolean = false;
  @State shelfRefreshPrompt: string = '下拉刷新书架';
  @State editingTags: string[] = [];
  @State tagInput: string = '';
  @State shelfCoverMap: Map<string, string> = new Map();
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('bookshelfSortMode') sortMode: string = 'recentRead';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('bookshelfShowTags') bookshelfShowTags: boolean = true;
  @StorageLink('bookshelfShowSource') bookshelfShowSource: boolean = true;
  @StorageLink('bookshelfShowIntro') bookshelfShowIntro: boolean = true;
  @StorageLink('bookshelfShowFullIntro') bookshelfShowFullIntro: boolean = false;
  @StorageLink('bookshelfShowProgressBar') bookshelfShowProgressBar: boolean = false;
  @StorageLink('bookshelfShowLastReadTime') bookshelfShowLastReadTime: boolean = true;
  @StorageLink('bookshelfShowLastReadChapter') bookshelfShowLastReadChapter: boolean = false;
  @StorageLink('bookshelfLayoutMode') bookshelfLayoutMode: string = 'compact';
  @StorageLink('bookshelfCoverAlbums') @Watch('onShelfCoverSettingsChanged') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') @Watch('onShelfCoverSettingsChanged') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') @Watch('onShelfCoverSettingsChanged') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverApplyScope') @Watch('onShelfCoverSettingsChanged') bookshelfCoverApplyScope: string = 'all';
  @StorageLink('bookshelfCoverTargetBooks') @Watch('onShelfCoverSettingsChanged') bookshelfCoverTargetBooks: string = '';
  @StorageLink('bookshelfIgnoreSourceCover') @Watch('onShelfCoverSettingsChanged') bookshelfIgnoreSourceCover: boolean = false;
  @StorageLink('bookshelfCoverMode') @Watch('onShelfCoverSettingsChanged') bookshelfCoverMode: string = 'sequence';
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageLink('fullTextCacheCancelNonce') @Watch('onFullTextCacheCancelNonceChanged') fullTextCacheCancelNonce: number = 0;
  @StorageLink('fullTextCacheCancelSignal') @Watch('onFullTextCacheCancelSignalChanged') fullTextCacheCancelSignal: string = '';
  private loadTimer: number = -1;
  private cacheTocLoadToken: number = 0;
  private cacheTocLoadBookUrl: string = '';
  private cacheTocLoadPromise: Promise<boolean> | null = null;
  private cacheDialogOpenedAt: number = 0;
  private fullTextCacheTasks: Map<string, ShelfFullTextCacheTask> = new Map();
  private fullTextCacheCancelSubscriber: commonEventManager.CommonEventSubscriber | null = null;
  private activeCacheBookUrl: string = '';
  private shelfRefreshRunning: boolean = false;
  private fullTextCacheTaskId: number = 0;
  private fullTextCacheCancelRequested: boolean = false;
  private fullTextCacheCancelSeenNonce: number = 0;
  private fullTextCacheNotificationLastAt: number = 0;
  private fullTextCacheBackgroundRunning: boolean = false;
  private fullTextCacheCancelAgent: WantAgent | null = null;
  private fullTextCacheDone: number = 0;
  private fullTextCacheTotal: number = 0;
  private fullTextCacheStatus: string = '';
  private fullTextCacheBookName: string = '';
  private fullTextCacheTaskKey: string = '';
  private fullTextCacheBookUrl: string = '';
  private fullTextCacheCoverPixelMap: image.PixelMap | null = null;
  private fullTextCacheContinuousNotificationId: number = 0;
  private fullTextCacheContinuousSlotType: notificationManager.SlotType = notificationManager.SlotType.SERVICE_INFORMATION;
  private fullTextCacheNotificationSlotReady: boolean = false;
  private fullTextCacheNotificationFailureHintShown: boolean = false;

  aboutToAppear() {
    this.reloadDisplaySettings();
    this.scheduleLoadBooks();
    this.ensureShelfFullTextCacheCancelSubscriber();
  }

  aboutToDisappear(): void {
    this.releaseShelfFullTextCacheCancelSubscriber();
  }

  async reloadDisplaySettings(): Promise<void> {
    try {
      const settings = await BookshelfDisplaySettingsStore.load(getContext(this));
      this.bookshelfShowTags = settings.showTags;
      this.bookshelfShowSource = settings.showSource;
      this.bookshelfShowIntro = settings.showIntro;
      this.bookshelfShowFullIntro = settings.showFullIntro;
      this.bookshelfShowProgressBar = settings.showProgressBar;
      this.bookshelfShowLastReadTime = settings.showLastReadTime;
      this.bookshelfShowLastReadChapter = settings.showLastReadChapter;
      this.bookshelfLayoutMode = settings.layoutMode;
    } catch (e) {
      console.warn('恢复书架显示设置失败:', e);
    }
  }

  onShelfChanged(): void {
    this.scheduleLoadBooks();
  }

  onShelfCoverSettingsChanged(): void {
    this.shelfCoverMap = new Map();
    this.refreshShelfCoverCache(this.books);
  }

  async loadBooks() {
    this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.books = this.sortBooks(SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks()));
      this.refreshShelfCoverCache(this.books);
    } catch (e) {
      console.error('加载书籍失败:', e);
    } finally {
      this.isLoading = false;
    }
  }

  scheduleLoadBooks(): void {
    if (this.loadTimer >= 0) {
      clearTimeout(this.loadTimer);
    }
    this.loadTimer = setTimeout(() => {
      this.loadTimer = -1;
      this.loadBooks();
    }, 80);
  }

  async deleteBook(book: Book) {
    try {
      const db = AppDatabase.getInstance();
      this.deleteBookCoverCache(book);
      await db.deleteBook(book.bookUrl);
      promptAction.showToast({ message: `已删除《${book.name}》` });
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      await this.loadBooks();
    } catch (e) {
      console.error('删除书籍失败:', e);
      promptAction.showToast({ message: '删除失败' });
    }
  }

  showDeleteConfirm(book: Book) {
    this.pendingDeleteBook = book;
    this.showDeleteDialog = true;
  }

  showBookActions(book: Book): void {
    this.pendingActionBook = book;
    this.showActionDialog = true;
  }

  closeBookActions(): void {
    this.showActionDialog = false;
    this.pendingActionBook = null;
  }

  deleteBookCoverCache(book: Book): void {
    const context = getContext(this);
    const covers = [
      ...BookDisplayHelper.decodeCoverList(book.customCoverUrl),
      ...BookDisplayHelper.decodeCoverList(book.coverUrl)
    ];
    for (const cover of covers) {
      BookCoverCache.deleteCachedCover(context, cover);
    }
    const nextMap: Map<string, string> = new Map(this.shelfCoverMap);
    const coverCount = Math.max(1, BookDisplayHelper.getCoverList(book).length);
    for (let i = 0; i < coverCount; i++) {
      nextMap.delete(this.shelfCoverKey(book, i));
    }
    this.shelfCoverMap = nextMap;
  }

  async refreshShelfCoverCache(books: Book[]): Promise<void> {
    const context = getContext(this);
    const nextMap: Map<string, string> = new Map(this.shelfCoverMap);
    const pending: Array<[string, string]> = [];
    let hasCachedChange = false;
    for (const book of books) {
      const covers = CoverGallerySettings.getDisplayCoverList(
        book,
        this.appDarkMode,
        this.bookshelfCoverAlbums,
        this.bookshelfLightCoverAlbumId,
        this.bookshelfDarkCoverAlbumId,
        this.bookshelfCoverApplyScope,
        this.bookshelfCoverTargetBooks,
        this.bookshelfIgnoreSourceCover,
        this.bookshelfCoverMode
      );
      for (let i = 0; i < covers.length; i++) {
        const raw = covers[i];
        if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) {
          continue;
        }
        const key = this.shelfCoverKey(book, i);
        const cached = BookCoverCache.resolveCachedCover(context, raw);
        if (cached && nextMap.get(key) !== cached) {
          nextMap.set(key, cached);
          hasCachedChange = true;
          continue;
        }
        pending.push([key, raw]);
      }
    }
    if (hasCachedChange) {
      this.shelfCoverMap = new Map(nextMap);
    }
    for (const item of pending) {
      const key = item[0];
      const raw = item[1];
      if (nextMap.get(key)) {
        continue;
      }
        try {
          const cached = await BookCoverCache.resolveCover(context, raw);
          if (cached && cached !== raw && nextMap.get(key) !== cached) {
            nextMap.set(key, cached);
            this.shelfCoverMap = new Map(nextMap);
          }
        } catch (e) {
          console.warn('缓存书架封面失败:', e);
        }
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('书架')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)

          if (this.books.length > 0) {
            Row({ space: 6 }) {
              this.sortChip('新阅读', 'recentRead')
              this.sortChip('新加入', 'recentAdd')
              this.sortChip('名称', 'name')
            }
            .margin({ right: 10 })
          }

          Text(this.books.length > 0 ? `${this.books.length}本` : '')
            .fontSize(14)
            .fontColor('#999')
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

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
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.books.length === 0) {
          Column() {
            Text('📚')
              .fontSize(48)
              .margin({ bottom: 16 })
            Text('暂无书籍')
              .fontSize(16)
              .fontColor(this.subTextColor())
            Text('搜索并加入喜欢的书籍吧')
              .fontSize(14)
              .fontColor(this.subTextColor())
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.isShelfRefreshing, builder: this.shelfRefreshBuilder }) {
            List({ space: 8 }) {
              ForEach(this.books, (book: Book) => {
                ListItem() {
                  Column() {
                    if (this.isCompactLayout()) {
                      this.compactBookContent(book)
                    } else {
                      this.looseBookContent(book)
                    }
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .backgroundColor(this.glassCardColor())
                  .borderRadius(8)
                  .border({ width: 1, color: this.glassBorderColor() })
                  .shadow({ radius: 10, color: this.glassShadowColor(), offsetX: 0, offsetY: 4 })
                  .gesture(
                    LongPressGesture({ repeat: false })
                      .onAction(() => {
                        this.showBookActions(book);
                      })
                  )
                  .onClick(() => {
                    router.pushUrl({
                      url: 'pages/ReadBook',
                      params: { bookUrl: book.bookUrl }
                    });
                  })
                }
              })

              ListItem() {
                Column()
                  .height(this.bookshelfListBottomInset())
              }
            }
            .width('100%')
            .height('100%')
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.pageColor())
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
          }
          .layoutWeight(1)
          .backgroundColor(this.pageColor())
          .refreshOffset(64)
          .onStateChange((state: RefreshStatus) => {
            this.updateShelfRefreshPrompt(state);
          })
          .onRefreshing(() => {
            this.refreshBookshelfToc();
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight })
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      if (this.showActionDialog && this.pendingActionBook) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.closeBookActions();
            })

          Column() {
            Text(this.pendingActionBook.name)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            this.actionItem('移出书架', '#E53935', () => {
              if (this.pendingActionBook) {
                const book = this.pendingActionBook;
                this.closeBookActions();
                this.showDeleteConfirm(book);
              }
            })
            this.actionItem('缓存', this.primaryTextColor(), () => {
              if (this.pendingActionBook) {
                const book = this.pendingActionBook;
                this.showActionDialog = false;
                setTimeout(() => {
                  this.openCacheDialog(book);
                }, 0);
              }
            })
            this.actionItem('自定义标签', this.primaryTextColor(), () => {
              if (this.pendingActionBook) {
                this.editingTags = BookDisplayHelper.getBookTags(this.pendingActionBook);
                this.tagInput = '';
              }
              this.showActionDialog = false;
              this.showTagDialog = true;
            })

            Button('取消')
              .width('100%')
              .height(44)
              .margin({ top: 10 })
              .backgroundColor(this.appDarkMode ? '#24272D' : '#F5F5F5')
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.closeBookActions();
              })
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 18, bottom: 18 })
          .backgroundColor(this.cardColor())
          .borderRadius({ topLeft: 18, topRight: 18 })
          .margin({ bottom: this.actionSheetBottomMargin() })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
      }

      if (this.showCacheDialog && this.cacheTargetBook) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              if (!this.isCacheTargetBookCaching()) {
                this.closeCacheDialog();
              }
            })

          Column() {
            Text(`缓存《${this.cacheTargetBook.name}》`)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 8 })

            if (this.cacheStatus) {
              Text(this.cacheStatus)
                .fontSize(13)
                .fontColor(this.subTextColor())
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ bottom: 8 })
            }

            this.actionItem(this.isCacheTargetBookCaching() ? '正在缓存...' : '缓存全文', this.primaryTextColor(), () => {
              this.cacheWholeBook();
            })
            this.actionItem('缓存指定章节', this.primaryTextColor(), () => {
              if (!this.isCacheTargetBookCaching()) {
                this.showCacheDialog = false;
                this.showChapterCacheDialog = true;
                if (this.cacheTargetBook) {
                  this.loadCacheChapters(this.cacheTargetBook);
                }
              }
            })
            this.actionItem('清除已缓存章节', '#E53935', () => {
              this.clearCachedChapters();
            })

            Button('取消')
              .width('100%')
              .height(44)
              .margin({ top: 10 })
              .backgroundColor(this.appDarkMode ? '#24272D' : '#F5F5F5')
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.closeCacheDialog(false);
              })
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 18, bottom: 18 })
          .backgroundColor(this.cardColor())
          .borderRadius({ topLeft: 18, topRight: 18 })
          .margin({ bottom: this.actionSheetBottomMargin() })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
      }

      if (this.showChapterCacheDialog && this.cacheTargetBook) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              if (!this.isCacheTargetBookCaching()) {
                this.closeCacheDialog();
              }
            })

          Column() {
            Row() {
              Text('选择章节缓存')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .layoutWeight(1)
              Button('关闭')
                .height(34)
                .fontSize(13)
                .borderRadius(17)
                .onClick(() => {
                  if (!this.isCacheTargetBookCaching()) {
                    this.closeCacheDialog();
                  }
                })
            }
            .width('100%')
            .height(46)

            if (this.cacheStatus) {
              Text(this.cacheStatus)
                .fontSize(13)
                .fontColor(this.subTextColor())
                .width('100%')
                .margin({ bottom: 8 })
            }

            List({ space: 2 }) {
              ForEach(this.cacheChapters, (chapter: BookChapter, index: number) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Text(chapter.title)
                      .fontSize(15)
                      .fontColor(chapter.cacheDate > 0 ? this.cachedChapterTextColor() : this.primaryTextColor())
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (chapter.cacheDate > 0) {
                      Text('已缓存')
                        .fontSize(11)
                        .fontColor(this.appDarkMode ? '#7CC7A0' : '#1F8F55')
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor(this.appDarkMode ? '#24382F' : '#E6F4EC')
                        .borderRadius(4)
                    }
                  }
                  .width('100%')
                  .padding({ left: 2, right: 2, top: 12, bottom: 12 })
                  .onClick(() => {
                    if (!this.isCacheTargetBookCaching()) {
                      this.cacheSingleChapter(index);
                    }
                  })
                }
              })
            }
            .width('100%')
            .height(420)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 18, bottom: 18 })
          .backgroundColor(this.cardColor())
          .borderRadius({ topLeft: 18, topRight: 18 })
          .margin({ bottom: this.actionSheetBottomMargin() })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
      }

      if (this.showTagDialog && this.pendingActionBook) {
        Column() {
          Column() {
            Text('自定义标签')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 14 })

            Scroll() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.editingTags, (tag: string, index: number) => {
                  Row() {
                    Text(tag)
                      .fontSize(13)
                      .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
                    Text('×')
                      .fontSize(14)
                      .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
                      .margin({ left: 6 })
                  }
                  .padding({ left: 10, right: 8, top: 5, bottom: 5 })
                  .backgroundColor(BookDisplayHelper.getTagBackgroundColor(index, this.appDarkMode))
                  .borderRadius(14)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.removeEditingTag(tag);
                  })
                })
              }
              .width('100%')
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
            .width('100%')
            .constraintSize({ minHeight: 40, maxHeight: 220 })
            .margin({ bottom: 12 })

            Row() {
              TextInput({ placeholder: '输入标签', text: this.tagInput })
                .height(40)
                .layoutWeight(1)
                .backgroundColor(this.inputColor())
                .fontColor(this.primaryTextColor())
                .placeholderColor(this.subTextColor())
                .borderRadius(8)
                .onChange((value: string) => {
                  this.tagInput = value;
                })

              Button('添加')
                .height(40)
                .margin({ left: 8 })
                .onClick(() => {
                  this.addEditingTag();
                })
            }
            .width('100%')
            .margin({ bottom: 18 })

            Row() {
              Button('取消')
                .width('45%')
                .height(44)
                .backgroundColor(this.appDarkMode ? '#24272D' : '#F5F5F5')
                .fontColor(this.primaryTextColor())
                .onClick(() => {
                  this.showTagDialog = false;
                  this.pendingActionBook = null;
                })

              Button('保存')
                .width('45%')
                .height(44)
                .onClick(() => {
                  this.saveCustomTags();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('85%')
          .padding(22)
          .backgroundColor(this.cardColor())
          .borderRadius(12)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
      }

      // 删除确认弹窗
      if (this.showDeleteDialog && this.pendingDeleteBook) {
        Column() {
          Column() {
            Text('确认删除')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            Text(`确定要将《${this.pendingDeleteBook.name}》从书架移除吗？`)
              .fontSize(15)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 20 })

            Row() {
              Button('取消')
                .width('45%')
                .height(44)
                .backgroundColor(this.appDarkMode ? '#24272D' : '#F5F5F5')
                .fontColor(this.primaryTextColor())
                .onClick(() => {
                  this.showDeleteDialog = false;
                  this.pendingDeleteBook = null;
                })

              Button('删除')
                .width('45%')
                .height(44)
                .backgroundColor('#E53935')
                .onClick(() => {
                  if (this.pendingDeleteBook) {
                    const book = this.pendingDeleteBook;
                    this.showDeleteDialog = false;
                    this.pendingDeleteBook = null;
                    this.deleteBook(book);
                  }
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('85%')
          .padding(24)
          .backgroundColor(this.cardColor())
          .borderRadius(12)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showDeleteDialog = false;
          this.pendingDeleteBook = null;
        })
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  bookshelfListBottomInset(): number {
    const comfortableGap = 20;
    if (deviceInfo.sdkApiVersion < 23) {
      return comfortableGap;
    }
    const floatingTabHeight = 56;
    return floatingTabHeight + Math.max(this.navBarHeight, 8) + comfortableGap;
  }

  getBookColor(name: string): string {
    if (!name) return '#007DFF';
    const colors = ['#007DFF', '#E53935', '#43A047', '#EF6C00', '#8E24AA', '#00ACC1', '#D81B60', '#5E35B1'];
    let hash = 0;
    for (let i = 0; i < name.length; i++) {
      hash = name.charCodeAt(i) + ((hash << 5) - hash);
    }
    return colors[Math.abs(hash) % colors.length];
  }

  getDisplayTags(book: Book): string[] {
    const tags = BookDisplayHelper.getBookTags(book);
    return tags;
  }

  getAuthorAndUpdateText(book: Book): string {
    const author = book.author || '作者未知';
    const updateText = BookDisplayHelper.getLastUpdateText(book);
    return updateText ? `${author} · 最后更新 ${updateText}` : author;
  }

  isCompactLayout(): boolean {
    return this.bookshelfLayoutMode !== 'loose';
  }

  @Builder
  compactBookContent(book: Book) {
    Column({ space: 8 }) {
      Row() {
        this.coverView(book, 56, 72)

        Column({ space: 4 }) {
          Row() {
            Text(book.name)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            if (this.shouldShowBookSource(book)) {
              Text(this.getBookSourceText(book))
                .fontSize(11)
                .fontColor(this.sourceTagTextColor())
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(this.sourceTagBackgroundColor())
                .borderRadius(4)
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.getAuthorAndUpdateText(book))
            .fontSize(14)
            .fontColor(this.secondaryTextColor())

          if (this.bookshelfShowProgressBar) {
            Blank()
            this.readProgressPanel(book)
          } else {
            Row() {
              Text(this.getShelfProgressText(book))
                .fontSize(12)
                .fontColor(this.subTextColor())
            }
          }
        }
        .layoutWeight(1)
        .height(72)
        .margin({ left: 12 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.bookExtraContent(book)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
  }

  @Builder
  looseBookContent(book: Book) {
    Column({ space: 8 }) {
      Row() {
        this.coverView(book, 56, 72)

        Column({ space: 4 }) {
          Text(book.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getAuthorAndUpdateText(book))
            .fontSize(14)
            .fontColor(this.secondaryTextColor())

          Row() {
            if (this.shouldShowBookSource(book)) {
              Text(this.getBookSourceText(book))
                .fontSize(12)
                .fontColor(this.sourceTagTextColor())
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor(this.sourceTagBackgroundColor())
                .borderRadius(4)
                .margin({ right: 8 })
            }

            Text(this.getShelfProgressText(book))
              .fontSize(12)
              .fontColor(this.subTextColor())
          }
        }
        .layoutWeight(1)
        .margin({ left: 12 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.bookExtraContent(book)

      if (this.bookshelfShowProgressBar) {
        this.looseReadProgressPanel(book)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
  }

  @Builder
  bookExtraContent(book: Book) {
    if (this.bookshelfShowIntro && this.getBookIntroText(book)) {
      Text(this.getBookIntroText(book))
        .fontSize(12)
        .fontColor(this.subTextColor())
        .lineHeight(18)
        .maxLines(this.bookshelfShowFullIntro ? 999 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }

    if (this.bookshelfShowTags && this.getDisplayTags(book).length > 0) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.getDisplayTags(book), (tag: string, index: number) => {
          this.tagChip(tag, index, 11)
        })
      }
      .width('100%')
    }
  }

  shouldShowBookSource(book: Book): boolean {
    return this.bookshelfShowSource && book.origin !== 'local' && this.getBookSourceText(book).length > 0;
  }

  getBookSourceText(book: Book): string {
    return (book.originName || book.origin || '').trim();
  }

  getBookIntroText(book: Book): string {
    return (book.getDisplayIntro() || '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  @Builder
  coverView(book: Book, width: number, height: number) {
    Stack() {
      if (this.getShelfCoverList(book).length === 0) {
        Column() {
          Text(book.name ? book.name.substring(0, 1) : '书')
            .fontSize(28)
            .fontColor('#FFFFFF')
        }
        .width(width)
        .height(height)
        .backgroundColor(this.getBookColor(book.name))
        .justifyContent(FlexAlign.Center)
      } else if (this.getShelfCoverList(book).length === 1) {
        Image(this.getShelfCover(book))
          .width(width)
          .height(height)
          .objectFit(ImageFit.Cover)
      } else {
        Swiper() {
          ForEach(this.getShelfCoverList(book), (cover: string) => {
            Image(cover)
              .width(width)
              .height(height)
              .objectFit(ImageFit.Cover)
          }, (cover: string) => cover)
        }
        .width(width)
        .height(height)
        .autoPlay(true)
        .interval(3500)
        .indicator(false)
        .loop(true)
      }
    }
    .width(width)
    .height(height)
    .borderRadius(6)
    .clip(true)
    .backgroundColor(this.inputColor())
  }

  getShelfCover(book: Book): string {
    const covers = this.getShelfCoverList(book);
    return covers.length > 0 ? BookDisplayHelper.pickCover(covers) : '';
  }

  getShelfCoverList(book: Book): string[] {
    const covers = CoverGallerySettings.getDisplayCoverList(
      book,
      this.appDarkMode,
      this.bookshelfCoverAlbums,
      this.bookshelfLightCoverAlbumId,
      this.bookshelfDarkCoverAlbumId,
      this.bookshelfCoverApplyScope,
      this.bookshelfCoverTargetBooks,
      this.bookshelfIgnoreSourceCover,
      this.bookshelfCoverMode
    );
    const displayCovers: string[] = [];
    const context = getContext(this);
    for (let i = 0; i < covers.length; i++) {
      const raw = covers[i];
      const cached = this.shelfCoverMap.get(this.shelfCoverKey(book, i)) || BookCoverCache.resolveCachedCover(context, raw);
      displayCovers.push(cached || raw);
    }
    return displayCovers;
  }

  shelfCoverKey(book: Book, index: number): string {
    return `${book.bookUrl}#${index}`;
  }

  @Builder
  tagChip(tag: string, index: number, fontSize: number) {
    Text(tag)
      .fontSize(fontSize)
      .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(BookDisplayHelper.getTagBackgroundColor(index, this.appDarkMode))
      .borderRadius(12)
      .margin({ left: 4, bottom: 6 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  actionItem(label: string, color: string, action: () => void) {
    Button(label)
      .width('100%')
      .height(44)
      .margin({ top: 6 })
      .backgroundColor(this.appDarkMode ? '#24272D' : '#F5F5F5')
      .fontColor(color)
      .onClick(action)
  }

  actionSheetBottomMargin(): number {
    return 82 + (this.navBarHeight > 0 ? this.navBarHeight : 0);
  }

  addEditingTag(): void {
    const tag = this.tagInput.trim();
    if (!tag || this.editingTags.includes(tag)) {
      this.tagInput = '';
      return;
    }
    this.editingTags = [...this.editingTags, tag];
    this.tagInput = '';
  }

  removeEditingTag(tag: string): void {
    this.editingTags = this.editingTags.filter(item => item !== tag);
  }

  async saveCustomTags(): Promise<void> {
    if (!this.pendingActionBook) return;
    this.addEditingTag();
    const book = this.pendingActionBook;
    const sourceTags = BookDisplayHelper.splitTags(book.kind, '');
    const customTags = this.editingTags.filter(tag => !sourceTags.includes(tag));
    const hiddenTags = sourceTags
      .filter(tag => !this.editingTags.includes(tag))
      .map(tag => `!${tag}`);
    book.customTag = BookDisplayHelper.joinTags([...customTags, ...hiddenTags]);
    await this.updateShelfBook(book);
    this.showTagDialog = false;
    this.pendingActionBook = null;
    promptAction.showToast({ message: '标签已保存' });
  }

  async openCacheDialog(book: Book): Promise<void> {
    this.cacheTargetBook = book;
    this.cacheChapters = [];
    this.cacheStatus = this.isBookCaching(book) ? this.currentFullTextCacheDialogStatus(book) : '正在加载目录...';
    this.cacheDialogOpenedAt = Date.now();
    this.showCacheDialog = true;
    if (!this.isBookCaching(book)) {
      this.loadCacheChapters(book);
    }
  }

  closeCacheDialog(resetCaching: boolean = true): void {
    this.showCacheDialog = false;
    this.showChapterCacheDialog = false;
    this.cacheTargetBook = null;
    this.cacheChapters = [];
    this.cacheStatus = '';
    this.isCacheTocLoading = false;
    this.cacheTocLoadToken++;
    this.cacheTocLoadBookUrl = '';
    this.cacheTocLoadPromise = null;
    this.pendingActionBook = null;
  }

  isCacheTargetBookCaching(): boolean {
    return this.isBookCaching(this.cacheTargetBook);
  }

  isBookCaching(book: Book | null): boolean {
    const bookUrl = book?.bookUrl || '';
    return !!bookUrl && this.fullTextCacheTasks.has(bookUrl);
  }

  currentFullTextCacheDialogStatus(book: Book): string {
    const task = this.getShelfFullTextCacheTask(book.bookUrl);
    if (task) {
      return task.status || this.shelfFullTextCacheProgressText(task);
    }
    return '正在加载目录...';
  }

  setFullTextCacheStatus(task: ShelfFullTextCacheTask, status: string): void {
    task.status = status;
    if (this.cacheTargetBook?.bookUrl && this.cacheTargetBook.bookUrl === task.bookUrl) {
      this.cacheStatus = status;
    }
  }

  onFullTextCacheCancelNonceChanged(): void {
    const nonce = this.fullTextCacheCancelNonce || 0;
    if (!this.isCaching || nonce <= 0) {
      return;
    }
    const signal = this.parseFullTextCacheCancelSignal();
    if (signal) {
      const task = this.findShelfFullTextCacheTaskBySignal(signal);
      if (!task || task.cancelSeenNonce === signal.nonce) {
        return;
      }
      task.cancelRequested = true;
      task.cancelSeenNonce = signal.nonce;
      promptAction.showToast({ message: '缓存已停止' });
      return;
    }
    let stopped = false;
    this.fullTextCacheTasks.forEach((task: ShelfFullTextCacheTask) => {
      if (task.cancelSeenNonce !== nonce) {
        task.cancelRequested = true;
        task.cancelSeenNonce = nonce;
        stopped = true;
      }
    });
    if (stopped) {
      promptAction.showToast({ message: '缓存已停止' });
    }
  }

  onFullTextCacheCancelSignalChanged(): void {
    const signal = this.parseFullTextCacheCancelSignal();
    if (!signal || !this.isCaching) {
      return;
    }
    const task = this.findShelfFullTextCacheTaskBySignal(signal);
    if (!task || task.cancelSeenNonce === signal.nonce) {
      return;
    }
    task.cancelRequested = true;
    task.cancelSeenNonce = signal.nonce;
    promptAction.showToast({ message: '缓存已停止' });
  }

  async loadCacheChapters(book: Book, forceRefresh: boolean = false): Promise<boolean> {
    if (!book.bookUrl) {
      this.cacheStatus = '书籍地址为空';
      return false;
    }
    if (!forceRefresh && this.cacheTocLoadPromise && this.cacheTocLoadBookUrl === book.bookUrl) {
      return await this.cacheTocLoadPromise;
    }
    if (!forceRefresh && this.cacheTargetBook?.bookUrl === book.bookUrl && this.cacheChapters.length > 0) {
      return true;
    }
    const token = ++this.cacheTocLoadToken;
    this.cacheTocLoadBookUrl = book.bookUrl;
    this.isCacheTocLoading = true;
    if (this.cacheChapters.length === 0) {
      this.cacheStatus = '正在加载目录...';
    }
    const task = this.loadCacheChaptersInternal(book, token);
    this.cacheTocLoadPromise = task;
    try {
      return await task;
    } finally {
      if (token === this.cacheTocLoadToken) {
        this.isCacheTocLoading = false;
        this.cacheTocLoadPromise = null;
      }
    }
  }

  async loadCacheChaptersInternal(book: Book, token: number): Promise<boolean> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const engine = ReadBookEngine.get();
      await engine.openBook(book);
      await engine.syncChapterCacheDates();
      if (token !== this.cacheTocLoadToken || this.cacheTargetBook?.bookUrl !== book.bookUrl) {
        return false;
      }
      const chapters = [...engine.chapters];
      this.cacheChapters = chapters;
      if (chapters.length > 0) {
        const cachedCount = this.countCachedChapters(chapters);
        this.cacheStatus = `${cachedCount}章已缓存 ${chapters.length - cachedCount}章待缓存`;
      } else {
        this.cacheStatus = '暂未获取到目录';
      }
      return chapters.length > 0;
    } catch (e) {
      console.error('加载缓存目录失败:', e);
      if (token === this.cacheTocLoadToken && this.cacheTargetBook?.bookUrl === book.bookUrl) {
        this.cacheStatus = '目录加载失败，请稍后重试';
        promptAction.showToast({ message: '目录加载失败' });
      }
      return false;
    }
  }

  async cacheWholeBook(): Promise<void> {
    if (!this.cacheTargetBook || this.isCacheTargetBookCaching()) {
      return;
    }
    if (Date.now() - this.cacheDialogOpenedAt < 300) {
      return;
    }
    const book = this.cacheTargetBook;
    if (!book.origin || book.origin === 'local') {
      promptAction.showToast({ message: '本地书籍无需缓存' });
      return;
    }
    this.closeCacheDialog();
    promptAction.showToast({ message: '已转入后台缓存，可在通知栏取消' });
    const task = this.createShelfFullTextCacheTask(book, ++this.fullTextCacheTaskId);
    this.runShelfFullTextCache(book, task).catch((error: Error) => {
      console.error('书架全文缓存任务失败:', error);
      this.setFullTextCacheStatus(task, '全文缓存失败');
      promptAction.showToast({ message: '全文缓存失败' });
      this.publishShelfFullTextCacheNotification(task, '全文缓存失败', this.shelfFullTextCacheProgressText(task), false)
        .catch((e: Error) => {
          console.warn('更新书架缓存失败通知失败:', e);
        });
      this.finishShelfFullTextCacheTask(task);
      this.stopShelfFullTextCacheBackgroundRunning().catch((e: Error) => {
        console.warn('停止书架全文缓存后台任务失败:', e);
      });
    });
  }

  async runShelfFullTextCache(book: Book, task: ShelfFullTextCacheTask): Promise<void> {
    this.registerShelfFullTextCacheTask(task);
    this.setFullTextCacheStatus(task, '全文缓存后台进行中');
    try {
      await this.refreshFullTextCacheCover(book, task);
      if (await this.prepareShelfFullTextCacheNotification()) {
        await this.publishShelfFullTextCacheNotification(task, '准备缓存章节',
          this.shelfFullTextCacheProgressText(task), true);
      }
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const freshBook = await db.getBook(book.bookUrl) || book;
      const engine = ReadBookEngine.createBackgroundWorker();
      await engine.openBook(freshBook);
      await engine.syncChapterCacheDates();
      if (!this.isShelfFullTextCacheTaskActive(task)) {
        return;
      }
      const total = engine.chapters.length;
      task.total = total;
      task.done = this.countCachedChapters(engine.chapters);
      if (total === 0) {
        this.setFullTextCacheStatus(task, '暂无可缓存章节');
        await this.publishShelfFullTextCacheNotification(task, '暂无可缓存章节',
          this.shelfFullTextCacheProgressText(task), false);
        return;
      }

      await this.startShelfFullTextCacheBackgroundRunning(book);
      await this.publishShelfFullTextCacheProgress(task, true);

      for (let i = 0; i < total; i++) {
        if (!this.isShelfFullTextCacheTaskActive(task) || this.shouldCancelShelfFullTextCache(task)) {
          break;
        }
        const chapter = engine.chapters[i];
        if (!chapter || chapter.cacheDate > 0) {
          continue;
        }
        this.setFullTextCacheStatus(task, `正在缓存 ${i + 1}/${total}`);
        try {
          const title = chapter.title || `第${i + 1}章`;
          await this.publishShelfFullTextCacheNotification(task, `正在缓存：${title}`,
            this.shelfFullTextCacheProgressText(task), true);
          if (await engine.cacheChapter(i)) {
            task.done = this.countCachedChapters(engine.chapters);
          }
        } catch (e) {
          console.error('缓存章节失败:', i, e);
        }
        await this.publishShelfFullTextCacheProgress(task, true);
        await this.sleep(0);
      }

      if (!this.isShelfFullTextCacheTaskActive(task)) {
        return;
      }
      const canceled = this.shouldCancelShelfFullTextCache(task);
      await engine.syncChapterCacheDates();
      task.done = this.countCachedChapters(engine.chapters);
      this.setFullTextCacheStatus(task, canceled ? '全文缓存已取消' : `缓存完成：${task.done}/${total}`);
      await this.publishShelfFullTextCacheNotification(
        task,
        canceled ? '缓存已停止' : '全文缓存完成',
        this.shelfFullTextCacheProgressText(task),
        false
      );
      promptAction.showToast({ message: canceled ? '缓存已停止' : `缓存完成 ${task.done}/${total}` });
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } finally {
      this.finishShelfFullTextCacheTask(task);
      await this.stopShelfFullTextCacheBackgroundRunning();
    }
  }

  createShelfFullTextCacheTask(book: Book, taskId: number): ShelfFullTextCacheTask {
    const bookUrl = book.bookUrl || '';
    return {
      taskId: taskId,
      bookUrl: bookUrl,
      bookName: book.name || '书籍',
      taskKey: this.buildFullTextCacheTaskKey(book, taskId),
      createdAt: Date.now(),
      cancelRequested: false,
      cancelSeenNonce: AppStorage.get<number>('fullTextCacheCancelNonce') || 0,
      notificationLastAt: 0,
      cancelAgent: null,
      done: 0,
      total: 0,
      status: '',
      coverPixelMap: null,
      notificationFailureHintShown: false
    };
  }

  registerShelfFullTextCacheTask(task: ShelfFullTextCacheTask): void {
    this.fullTextCacheTasks.set(task.bookUrl, task);
    this.syncShelfFullTextCacheTaskState();
  }

  async ensureShelfFullTextCacheCancelSubscriber(): Promise<void> {
    if (this.fullTextCacheCancelSubscriber) {
      return;
    }
    try {
      const subscriber = await commonEventManager.createSubscriber({
        events: [SHELF_FULL_TEXT_CACHE_CANCEL_EVENT]
      });
      this.fullTextCacheCancelSubscriber = subscriber;
      commonEventManager.subscribe(subscriber, (error: Error | null, data: commonEventManager.CommonEventData) => {
        if (error) {
          console.warn('接收书架缓存取消事件失败:', error);
          return;
        }
        this.handleShelfFullTextCacheCancelEvent(data);
      });
    } catch (error) {
      console.warn('注册书架缓存取消事件失败:', error);
    }
  }

  releaseShelfFullTextCacheCancelSubscriber(): void {
    if (!this.fullTextCacheCancelSubscriber) {
      return;
    }
    const subscriber = this.fullTextCacheCancelSubscriber;
    this.fullTextCacheCancelSubscriber = null;
    commonEventManager.unsubscribe(subscriber, (error: Error | null) => {
      if (error) {
        console.warn('注销书架缓存取消事件失败:', error);
      }
    });
  }

  handleShelfFullTextCacheCancelEvent(data: commonEventManager.CommonEventData): void {
    const params = data.parameters || {};
    const taskKey = typeof params['cacheTaskKey'] === 'string' ? params['cacheTaskKey'] as string : '';
    const bookUrl = typeof params['bookUrl'] === 'string' ? params['bookUrl'] as string : '';
    this.requestShelfFullTextCacheCancel({
      nonce: Date.now(),
      taskKey: taskKey,
      bookUrl: bookUrl
    });
  }

  finishShelfFullTextCacheTask(task: ShelfFullTextCacheTask): void {
    const current = this.fullTextCacheTasks.get(task.bookUrl);
    if (current && current.taskKey === task.taskKey) {
      this.fullTextCacheTasks.delete(task.bookUrl);
    }
    task.cancelRequested = false;
    this.releaseFullTextCacheCover(task);
    this.syncShelfFullTextCacheTaskState();
  }

  syncShelfFullTextCacheTaskState(): void {
    this.activeFullTextCacheBookUrls = Array.from(this.fullTextCacheTasks.keys());
    this.isCaching = this.activeFullTextCacheBookUrls.length > 0;
  }

  getShelfFullTextCacheTask(bookUrl: string): ShelfFullTextCacheTask | null {
    return bookUrl ? this.fullTextCacheTasks.get(bookUrl) || null : null;
  }

  isShelfFullTextCacheTaskActive(task: ShelfFullTextCacheTask): boolean {
    const current = this.fullTextCacheTasks.get(task.bookUrl);
    return !!current && current.taskKey === task.taskKey;
  }

  findShelfFullTextCacheTaskBySignal(signal: FullTextCacheCancelSignal): ShelfFullTextCacheTask | null {
    if (signal.taskKey) {
      for (const task of this.fullTextCacheTasks.values()) {
        if (task.taskKey === signal.taskKey) {
          return task;
        }
      }
    }
    return signal.bookUrl ? this.getShelfFullTextCacheTask(signal.bookUrl) : null;
  }

  requestShelfFullTextCacheCancel(signal: FullTextCacheCancelSignal): void {
    const task = this.findShelfFullTextCacheTaskBySignal(signal);
    if (!task || task.cancelSeenNonce === signal.nonce) {
      return;
    }
    task.cancelRequested = true;
    task.cancelSeenNonce = signal.nonce;
    AppStorage.setOrCreate('fullTextCacheCancelSignal', JSON.stringify(signal));
    AppStorage.setOrCreate('fullTextCacheCancelNonce', signal.nonce);
    promptAction.showToast({ message: '缓存已停止' });
  }

  shouldCancelShelfFullTextCache(task: ShelfFullTextCacheTask): boolean {
    if (task.cancelRequested) {
      return true;
    }
    const nonce = AppStorage.get<number>('fullTextCacheCancelNonce') || 0;
    if (nonce > 0 && nonce !== task.cancelSeenNonce) {
      const signal = this.parseFullTextCacheCancelSignal();
      if (signal && !this.isCurrentFullTextCacheSignal(task, signal)) {
        task.cancelSeenNonce = signal.nonce;
        return false;
      }
      if (!signal || this.isCurrentFullTextCacheSignal(task, signal)) {
        task.cancelRequested = true;
        task.cancelSeenNonce = signal ? signal.nonce : nonce;
        return true;
      }
    }
    return false;
  }

  parseFullTextCacheCancelSignal(): FullTextCacheCancelSignal | null {
    const raw = this.fullTextCacheCancelSignal || AppStorage.get<string>('fullTextCacheCancelSignal') || '';
    if (!raw.trim()) {
      return null;
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const signal: FullTextCacheCancelSignal = {
        nonce: typeof parsed['nonce'] === 'number' ? parsed['nonce'] as number : 0,
        taskKey: typeof parsed['taskKey'] === 'string' ? parsed['taskKey'] as string : '',
        bookUrl: typeof parsed['bookUrl'] === 'string' ? parsed['bookUrl'] as string : ''
      };
      return signal.nonce > 0 ? signal : null;
    } catch (e) {
      return null;
    }
  }

  isCurrentFullTextCacheSignal(task: ShelfFullTextCacheTask, signal: FullTextCacheCancelSignal): boolean {
    if (signal.taskKey && task.taskKey && signal.taskKey === task.taskKey) {
      return true;
    }
    return !!signal.bookUrl && signal.bookUrl === task.bookUrl;
  }

  countCachedChapters(chapters: BookChapter[]): number {
    let count = 0;
    for (const chapter of chapters) {
      if (chapter.cacheDate > 0) {
        count++;
      }
    }
    return count;
  }

  shelfFullTextCacheProgressText(task: ShelfFullTextCacheTask): string {
    const total = Math.max(task.total, 0);
    if (total === 0) {
      return '正在准备缓存章节（0%）';
    }
    const done = Math.max(0, Math.min(task.done, total));
    const percent = Math.floor((done / total) * 100);
    return `已缓存 ${done}/${total} 章（${percent}%）`;
  }

  shelfFullTextCachePercent(task: ShelfFullTextCacheTask): number {
    const total = Math.max(task.total, 0);
    if (total === 0) {
      return 0;
    }
    const done = Math.max(0, Math.min(task.done, total));
    return Math.floor((done / total) * 100);
  }

  shelfFullTextCacheNotificationTitle(task: ShelfFullTextCacheTask): string {
    return `缓存全文：${task.bookName || '书籍'}`;
  }

  shelfFullTextCacheDisplayText(text: string, additionalText: string, ongoing: boolean): string {
    if (!ongoing || !additionalText || text.includes(additionalText)) {
      return text;
    }
    return `${text} · ${additionalText}`;
  }

  shelfFullTextCacheNormalContent(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): notificationManager.NotificationBasicContent {
    const normalContent: notificationManager.NotificationBasicContent = {
      title: this.shelfFullTextCacheNotificationTitle(task),
      text: this.shelfFullTextCacheDisplayText(text, additionalText, ongoing),
      additionalText: additionalText
    };
    if (task.coverPixelMap) {
      normalContent.lockscreenPicture = task.coverPixelMap;
    }
    return normalContent;
  }

  applyShelfFullTextCacheCoverToRequest(task: ShelfFullTextCacheTask,
    request: notificationManager.NotificationRequest): void {
    if (!task.coverPixelMap) {
      return;
    }
    request.smallIcon = task.coverPixelMap;
    request.largeIcon = task.coverPixelMap;
  }

  async publishShelfFullTextCacheProgress(task: ShelfFullTextCacheTask, force: boolean): Promise<void> {
    const now = Date.now();
    if (!force && now - task.notificationLastAt < 1200) {
      return;
    }
    task.notificationLastAt = now;
    await this.publishShelfFullTextCacheNotification(task, task.status || '全文缓存后台进行中',
      this.shelfFullTextCacheProgressText(task), true);
  }

  async publishShelfFullTextCacheNotification(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: this.fullTextCacheNotificationId(task.bookUrl),
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: ongoing,
        tapDismissed: false,
        isAlertOnce: true,
        deliveryTime: task.createdAt,
        showDeliveryTime: false,
        wantAgent: await this.getShelfFullTextCacheOpenWantAgent(task),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: this.shelfFullTextCacheNormalContent(task, text, additionalText, ongoing)
        }
      };
      if (!ongoing) {
        request.autoDeletedTime = Date.now() + 5000;
      }
      request.label = this.fullTextCacheNotificationLabel(task.bookUrl);
      this.applyShelfFullTextCacheCoverToRequest(task, request);
      if (ongoing) {
        request.actionButtons = [{
          title: '停止缓存',
          wantAgent: await this.getShelfFullTextCacheCancelWantAgent(task)
        }];
      }
      await notificationManager.publish(request);
    } catch (error) {
      console.warn('发布书架全文缓存通知失败:', error);
      try {
        await this.publishBasicShelfFullTextCacheNotification(task, text, additionalText, ongoing);
      } catch (fallbackError) {
        console.warn('发布书架全文缓存基础通知失败:', fallbackError);
        try {
          await this.publishMinimalShelfFullTextCacheNotification(task, text, additionalText, ongoing);
        } catch (minimalError) {
          console.warn('发布书架全文缓存最小通知失败:', minimalError);
          this.showShelfFullTextCacheNotificationFailureHint(task, minimalError);
        }
      }
    }
  }

  async publishBasicShelfFullTextCacheNotification(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: this.fullTextCacheNotificationId(task.bookUrl),
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: ongoing,
      tapDismissed: false,
      isAlertOnce: true,
      deliveryTime: task.createdAt,
      showDeliveryTime: false,
      wantAgent: await this.getShelfFullTextCacheOpenWantAgent(task),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: this.shelfFullTextCacheNormalContent(task, text, additionalText, ongoing)
      }
    };
    if (!ongoing) {
      request.autoDeletedTime = Date.now() + 5000;
    }
    request.label = this.fullTextCacheNotificationLabel(task.bookUrl);
    if (ongoing) {
      request.actionButtons = [{
        title: '停止缓存',
        wantAgent: await this.getShelfFullTextCacheCancelWantAgent(task)
      }];
    }
    this.applyShelfFullTextCacheCoverToRequest(task, request);
    await notificationManager.publish(request);
  }

  async publishMinimalShelfFullTextCacheNotification(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: this.fullTextCacheNotificationId(task.bookUrl),
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: ongoing,
      tapDismissed: false,
      isAlertOnce: true,
      deliveryTime: task.createdAt,
      showDeliveryTime: false,
      wantAgent: await this.getShelfFullTextCacheOpenWantAgent(task),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: this.shelfFullTextCacheNormalContent(task, text, additionalText, ongoing)
      }
    };
    if (!ongoing) {
      request.autoDeletedTime = Date.now() + 5000;
    }
    request.label = this.fullTextCacheNotificationLabel(task.bookUrl);
    this.applyShelfFullTextCacheCoverToRequest(task, request);
    await notificationManager.publish(request);
  }

  async refreshFullTextCacheCover(book: Book, task: ShelfFullTextCacheTask): Promise<void> {
    this.releaseFullTextCacheCover(task);
    const raw = this.getShelfCover(book);
    if (!raw) {
      return;
    }
    try {
      const coverPath = await BookCoverCache.prepareCoverFile(getContext(this), raw);
      if (!coverPath) {
        return;
      }
      task.coverPixelMap = await this.createFullTextCacheCoverPixelMap(coverPath);
    } catch (error) {
      console.warn('解析缓存通知封面失败:', error);
    }
  }

  async createFullTextCacheCoverPixelMap(path: string): Promise<image.PixelMap | null> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      return await source.createPixelMap({
        desiredSize: {
          width: 128,
          height: 128
        }
      });
    } catch (error) {
      console.warn('创建缓存通知封面 PixelMap 失败:', error);
      return null;
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (e) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (e) {
        }
      }
    }
  }

  releaseFullTextCacheCover(task: ShelfFullTextCacheTask): void {
    if (!task.coverPixelMap) {
      return;
    }
    try {
      task.coverPixelMap.release().catch((e: Error) => {
        console.warn('释放缓存通知封面失败:', e);
      });
    } catch (e) {
      console.warn('释放缓存通知封面失败:', e);
    }
    task.coverPixelMap = null;
  }

  async prepareShelfFullTextCacheNotification(): Promise<boolean> {
    try {
      if (!await notificationManager.isNotificationEnabled()) {
        try {
          await notificationManager.requestEnableNotification(getContext(this) as common.UIAbilityContext);
        } catch (error) {
          console.warn('请求通知权限失败:', error);
          promptAction.showToast({ message: '通知权限未开启，缓存仍会继续' });
          return false;
        }
      }
      if (!await notificationManager.isNotificationEnabled()) {
        promptAction.showToast({ message: '通知权限未开启，缓存仍会继续' });
        return false;
      }
      if (!this.fullTextCacheNotificationSlotReady) {
        await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
        this.fullTextCacheNotificationSlotReady = true;
      }
      return true;
    } catch (error) {
      console.warn('准备书架缓存通知失败:', error);
      this.showShelfFullTextCacheNotificationFailureHint(null, error);
      return false;
    }
  }

  showShelfFullTextCacheNotificationFailureHint(task: ShelfFullTextCacheTask | null, error: Object): void {
    if (task) {
      if (task.notificationFailureHintShown) {
        return;
      }
      task.notificationFailureHintShown = true;
    } else if (this.fullTextCacheNotificationFailureHintShown) {
      return;
    } else {
      this.fullTextCacheNotificationFailureHintShown = true;
    }
    console.warn('书架缓存通知不可用:', error);
    promptAction.showToast({ message: this.shelfFullTextCacheNotificationFailureMessage(error) });
  }

  shelfFullTextCacheNotificationFailureMessage(error: Object): string {
    const code = this.notificationErrorCode(error);
    if (code === 1600004 || code === 1600020) {
      return '通知权限未开启，缓存仍会继续';
    }
    if (code === 1600005) {
      return '通知类别已关闭，请检查应用通知设置';
    }
    if (code === 1600009) {
      return '通知发送过快，缓存仍会继续';
    }
    return code > 0 ? `通知发布失败(${code})` : '通知发布失败，请检查应用通知权限';
  }

  notificationErrorCode(error: Object): number {
    const record = error as Record<string, Object>;
    const code = record['code'];
    return typeof code === 'number' ? code as number : 0;
  }

  async getShelfFullTextCacheCancelWantAgent(task: ShelfFullTextCacheTask): Promise<WantAgent> {
    if (task.cancelAgent) {
      return task.cancelAgent;
    }
    const context = getContext(this) as common.UIAbilityContext;
    task.cancelAgent = await wantAgent.getWantAgent({
      wants: [{
        action: SHELF_FULL_TEXT_CACHE_CANCEL_EVENT,
        parameters: {
          cacheAction: 'cancelFullTextCache',
          cacheTaskId: task.taskId,
          cacheTaskKey: task.taskKey,
          bookUrl: task.bookUrl
        }
      }],
      actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
      requestCode: this.fullTextCacheCancelRequestCode(task.bookUrl),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    return task.cancelAgent;
  }

  async getShelfFullTextCacheOpenWantAgent(task: ShelfFullTextCacheTask): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          bookUrl: task.bookUrl
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.fullTextCacheOpenRequestCode(task.bookUrl),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  async startShelfFullTextCacheBackgroundRunning(book: Book): Promise<void> {
    if (this.fullTextCacheBackgroundRunning) {
      return;
    }
    this.fullTextCacheBackgroundRunning = false;
  }

  async stopShelfFullTextCacheBackgroundRunning(): Promise<void> {
    if (!this.fullTextCacheBackgroundRunning) {
      return;
    }
    this.fullTextCacheBackgroundRunning = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(getContext(this));
    } catch (error) {
      console.warn('停止书架全文缓存后台任务失败:', error);
    }
  }

  async createShelfFullTextCacheOpenWantAgent(book: Book): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          bookUrl: book.bookUrl || ''
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.fullTextCacheOpenRequestCode(book.bookUrl || ''),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  buildFullTextCacheTaskKey(book: Book, taskId: number): string {
    return `${this.fullTextCacheHash(book.bookUrl || book.name || 'book')}_${taskId}`;
  }

  fullTextCacheNotificationId(bookUrl: string): number {
    return 260100 + (this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book') % 100000);
  }

  currentFullTextCacheNotificationId(ongoing: boolean): number {
    if (ongoing && this.fullTextCacheContinuousNotificationId > 0) {
      return this.fullTextCacheContinuousNotificationId;
    }
    return this.fullTextCacheNotificationId(this.fullTextCacheBookUrl);
  }

  currentFullTextCacheNotificationSlotType(ongoing: boolean): notificationManager.SlotType {
    if (ongoing && this.fullTextCacheContinuousNotificationId > 0) {
      return this.fullTextCacheContinuousSlotType;
    }
    return notificationManager.SlotType.SERVICE_INFORMATION;
  }

  fullTextCacheCancelRequestCode(bookUrl: string): number {
    return 360100 + (this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book') % 100000);
  }

  fullTextCacheOpenRequestCode(bookUrl: string): number {
    return 460100 + (this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book') % 100000);
  }

  fullTextCacheNotificationLabel(bookUrl: string): string {
    return `full_text_cache_${this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book')}`;
  }

  fullTextCacheHash(value: string): number {
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(i);
      hash |= 0;
    }
    return Math.abs(hash);
  }

  sleep(ms: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  async cacheSingleChapter(index: number): Promise<void> {
    if (!this.cacheTargetBook || this.isCacheTargetBookCaching()) {
      return;
    }
    if (this.isCaching) {
      promptAction.showToast({ message: '其他书籍正在缓存，请稍后再试' });
      return;
    }
    if (this.cacheTargetBook.origin === 'local') {
      promptAction.showToast({ message: '本地书籍无需缓存' });
      return;
    }
    this.activeCacheBookUrl = this.cacheTargetBook.bookUrl || '';
    this.isCaching = true;
    try {
      const engine = ReadBookEngine.get();
      if (engine.book?.bookUrl !== this.cacheTargetBook.bookUrl) {
        await engine.openBook(this.cacheTargetBook);
      }
      const chapter = this.cacheChapters[index];
      this.cacheStatus = chapter ? `正在缓存：${chapter.title}` : '正在缓存章节...';
      const ok = await engine.cacheChapter(index);
      await engine.syncChapterCacheDates();
      this.cacheChapters = [...engine.chapters];
      this.cacheStatus = ok ? '章节已缓存' : '章节缓存失败';
      promptAction.showToast({ message: ok ? '章节已缓存' : '章节缓存失败' });
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('缓存指定章节失败:', e);
      this.cacheStatus = '章节缓存失败';
      promptAction.showToast({ message: '章节缓存失败' });
    } finally {
      if (this.activeCacheBookUrl === (this.cacheTargetBook?.bookUrl || '')) {
        this.activeCacheBookUrl = '';
      }
      this.isCaching = false;
    }
  }

  async clearCachedChapters(): Promise<void> {
    if (!this.cacheTargetBook) {
      return;
    }
    if (this.isCacheTargetBookCaching()) {
      promptAction.showToast({ message: '缓存进行中，稍后再清除' });
      return;
    }
    const book = this.cacheTargetBook;
    if (!book.bookUrl) {
      promptAction.showToast({ message: '书籍地址为空' });
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBookCachedContent(book.bookUrl);
      const engine = ReadBookEngine.get();
      if (engine.book?.bookUrl === book.bookUrl) {
        engine.clearCurrentBookMemoryCache();
        await engine.syncChapterCacheDates();
        this.cacheChapters = [...engine.chapters];
      } else {
        for (const chapter of this.cacheChapters) {
          chapter.cacheDate = 0;
        }
        this.cacheChapters = [...this.cacheChapters];
      }
      this.cacheStatus = '已清除缓存章节';
      promptAction.showToast({ message: '已清除缓存章节' });
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('清除缓存章节失败:', e);
      this.cacheStatus = '清除缓存失败';
      promptAction.showToast({ message: '清除缓存失败' });
    }
  }

  async refreshBookshelfToc(): Promise<void> {
    if (this.shelfRefreshRunning) {
      this.shelfRefreshPrompt = '书架刷新中';
      this.isShelfRefreshing = true;
      return;
    }
    if (this.books.length === 0) {
      this.isShelfRefreshing = false;
      return;
    }
    this.shelfRefreshRunning = true;
    this.isShelfRefreshing = true;
    promptAction.showToast({ message: '正在刷新书架...' });
    let attempted = 0;
    let skippedFinished = 0;
    let updated = 0;
    let failed = 0;
    let taskFailed = false;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const engine = ReadBookEngine.get();
      const shelfBooks = [...this.books];
      for (const shelfBook of shelfBooks) {
        if (!shelfBook.bookUrl || shelfBook.origin === 'local' || !shelfBook.canUpdate) {
          continue;
        }
        if (this.isFinishedBook(shelfBook)) {
          skippedFinished++;
          continue;
        }
        attempted++;
        const beforeCount = shelfBook.totalChapterNum;
        const beforeLatest = shelfBook.latestChapterTitle;
        try {
          const freshBook = await db.getBook(shelfBook.bookUrl) || shelfBook;
          await engine.openBook(freshBook);
          await engine.refreshToc();
          const refreshedBook = await db.getBook(shelfBook.bookUrl);
          if (refreshedBook) {
            refreshedBook.lastCheckTime = Date.now();
            refreshedBook.lastCheckCount = engine.chapters.length;
            if (engine.chapters.length > 0) {
              refreshedBook.totalChapterNum = engine.chapters.length;
              refreshedBook.latestChapterTitle = engine.chapters[engine.chapters.length - 1].title;
            }
            await db.updateBook(refreshedBook);
            if (refreshedBook.totalChapterNum > beforeCount || refreshedBook.latestChapterTitle !== beforeLatest) {
              updated++;
            }
          }
        } catch (e) {
          failed++;
          console.error('刷新书架目录失败:', shelfBook.name, e);
        }
      }
      if (attempted > 0) {
        await this.loadBooks();
        const skippedText = skippedFinished > 0 ? `，跳过${skippedFinished}本完结` : '';
        const message = failed > 0 ?
          `书架刷新完成：${updated}本有更新，${failed}本失败${skippedText}` :
          `书架刷新完成：${updated}本有更新${skippedText}`;
        promptAction.showToast({ message });
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }
    } catch (e) {
      taskFailed = true;
      console.error('刷新书架失败:', e);
      promptAction.showToast({ message: '书架刷新失败' });
    } finally {
      this.shelfRefreshRunning = false;
      this.isShelfRefreshing = false;
      this.shelfRefreshPrompt = '下拉刷新书架';
      if (!taskFailed && attempted === 0) {
        const message = skippedFinished > 0 ? `没有可刷新的连载书籍，已跳过${skippedFinished}本完结` : '没有可刷新的网络书籍';
        promptAction.showToast({ message });
      }
    }
  }

  isFinishedBook(book: Book): boolean {
    const text = `${book.kind || ''},${book.customTag || ''}`.replace(/\s+/g, '');
    if (!text) {
      return false;
    }
    if (/(连载中|連載中|连载|連載|未完结|未完結|更新中|ongoing|serializing)/i.test(text)) {
      return false;
    }
    return /(已完结|已完結|完结|完結|完本|全本|完$|completed|complete|finished)/i.test(text);
  }

  updateShelfRefreshPrompt(state: RefreshStatus): void {
    if (this.shelfRefreshRunning) {
      this.shelfRefreshPrompt = '书架刷新中';
      return;
    }
    if (state === RefreshStatus.OverDrag) {
      this.shelfRefreshPrompt = '松手刷新书架';
    } else if (state === RefreshStatus.Refresh) {
      this.shelfRefreshPrompt = '正在刷新书架...';
    } else if (state === RefreshStatus.Done) {
      this.shelfRefreshPrompt = '刷新完成';
    } else {
      this.shelfRefreshPrompt = '下拉刷新书架';
    }
  }

  async updateShelfBook(book: Book): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.updateBook(book);
      this.books = this.books.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('更新书籍失败:', e);
      promptAction.showToast({ message: '保存失败' });
    }
  }

  cachedChapterTextColor(): string {
    return this.appDarkMode ? '#DDEFE5' : '#244B35';
  }

  @Builder
  shelfRefreshBuilder() {
    Row({ space: 8 }) {
      if (this.isShelfRefreshing) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.accentColor())
      }
      Text(this.shelfRefreshPrompt)
        .fontSize(13)
        .fontColor(this.secondaryTextColor())
    }
    .height(48)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sortChip(label: string, mode: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.sortMode === mode ? '#FFFFFF' : this.secondaryTextColor())
      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .backgroundColor(this.sortMode === mode ? this.accentColor() : this.glassCardColor())
      .borderRadius(16)
      .border({ width: this.sortMode === mode ? 0 : 1, color: this.glassBorderColor() })
      .onClick(() => {
        this.sortMode = mode;
        this.books = this.sortBooks(this.books);
      })
  }

  sortBooks(books: Book[]): Book[] {
    if (this.sortMode === 'recentRead') {
      return BookshelfSortHelper.sortByRecentRead(books);
    }
    const sorted = [...books];
    if (this.sortMode === 'name') {
      sorted.sort((a: Book, b: Book) => this.compareBookName(a, b));
    } else {
      sorted.sort((a: Book, b: Book) => this.getBookAddTime(b) - this.getBookAddTime(a));
    }
    return sorted;
  }

  compareBookName(a: Book, b: Book): number {
    const nameA = this.normalizeBookName(a.name);
    const nameB = this.normalizeBookName(b.name);
    const nameDiff = nameA.localeCompare(nameB, 'zh-Hans-CN-u-co-pinyin');
    if (nameDiff !== 0) {
      return nameDiff;
    }
    return this.getBookAddTime(b) - this.getBookAddTime(a);
  }

  normalizeBookName(name?: string): string {
    if (!name) {
      return '';
    }
    return name
      .trim()
      .replace(/^[《〈「『“"'(\[【\s]+/g, '')
      .replace(/[》〉」』”"')\]】\s]+$/g, '');
  }

  getBookAddTime(book: Book): number {
    return BookshelfSortHelper.getBookAddTime(book);
  }

  getBookReadTime(book: Book): number {
    return BookshelfSortHelper.getBookReadTime(book);
  }

  parseBookTime(value: string): number {
    return BookshelfSortHelper.parseBookTime(value);
  }

  getShelfProgressText(book: Book): string {
    if (!book.totalChapterNum || book.totalChapterNum <= 0) {
      return '未读';
    }
    if (!book.durChapterTitle && book.durChapterIndex <= 0 && book.durChapterPos <= 0) {
      return '未读';
    }
    const unread = book.getUnreadChapterNum();
    return unread > 0 ? `${unread}章未读` : '已读完';
  }

  getReadProgressValue(book: Book): number {
    if (!book.totalChapterNum || book.totalChapterNum <= 0) {
      return 0;
    }
    if (!book.durChapterTitle && book.durChapterIndex <= 0 && book.durChapterPos <= 0) {
      return 0;
    }
    const readChapterCount = Math.min(Math.max(book.durChapterIndex + 1, 0), book.totalChapterNum);
    return Math.floor(readChapterCount * 1000 / book.totalChapterNum) / 10;
  }

  getReadProgressPercentText(book: Book): string {
    const progress = this.getReadProgressValue(book);
    if (progress <= 0) {
      return '已读0%';
    }
    if (progress >= 100) {
      return '已读100%';
    }
    return progress % 1 === 0 ? `已读${progress.toFixed(0)}%` : `已读${progress.toFixed(1)}%`;
  }

  getLastReadTimeText(book: Book): string {
    const readTime = this.getBookReadTime(book);
    if (readTime <= 0) {
      return '未读';
    }
    return this.formatShelfTime(readTime);
  }

  formatShelfTime(time: number): string {
    const date = new Date(time);
    if (Number.isNaN(date.getTime())) {
      return '未知';
    }
    const now = new Date();
    const dateStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const nowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const dayDiff = Math.floor((nowStart - dateStart) / 86400000);
    const timeText = `${this.padTime(date.getHours())}:${this.padTime(date.getMinutes())}`;
    if (dayDiff === 0) {
      return `今天 ${timeText}`;
    }
    if (dayDiff === 1) {
      return `昨天 ${timeText}`;
    }
    if (date.getFullYear() === now.getFullYear()) {
      return `${date.getMonth() + 1}-${this.padTime(date.getDate())} ${timeText}`;
    }
    return `${date.getFullYear()}-${this.padTime(date.getMonth() + 1)}-${this.padTime(date.getDate())} ${timeText}`;
  }

  padTime(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  @Builder
  readProgressPanel(book: Book) {
    Column({ space: 4 }) {
      Text(this.getReadProgressInfoText(book))
        .fontSize(12)
        .fontColor(this.subTextColor())
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .color(this.accentColor())
        .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')
    }
    .width('100%')
  }

  @Builder
  looseReadProgressPanel(book: Book) {
    Column({ space: 4 }) {
      Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .color(this.accentColor())
        .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')

      Text(this.getReadProgressInfoText(book))
        .fontSize(12)
        .fontColor(this.subTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  getReadProgressInfoText(book: Book): string {
    const parts: string[] = [this.getReadProgressPercentText(book)];
    if (this.bookshelfShowLastReadTime) {
      parts.push(this.getLastReadTimeText(book));
    }
    if (this.bookshelfShowLastReadChapter) {
      const chapterText = this.getReadChapterText(book);
      if (chapterText) {
        parts.push(chapterText);
      }
    }
    return parts.join(' · ');
  }

  getReadChapterText(book: Book): string {
    return (book.durChapterTitle || '').trim();
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F2F2F2';
  }

  glassCardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  glassShadowColor(): string {
    return '#00000000';
  }

  sourceTagBackgroundColor(): string {
    return this.appDarkMode ? '#24272D' : '#E8F0FE';
  }

  sourceTagTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : this.accentColor();
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  secondaryTextColor(): string {
    return this.appDarkMode ? '#C6CBD2' : '#666';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#999';
  }

  accentColor(): string {
    return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  buttonColor(): string {
    return this.appDarkMode ? this.appDarkButtonColor : this.appLightButtonColor;
  }
}

@Component
struct ExplorePage {
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Prop @Watch('onActiveChanged') isActive: boolean = false;
  @State entries: ExploreEntry[] = [];
  @State sourceOptions: ExploreSourceOption[] = [];
  @State platformNames: string[] = [];
  @State sourceNames: string[] = [];
  @State selectedSourceName: string = '';
  @State selectedIndex: number = 0;
  @State showExploreSourcePicker: boolean = false;
  @State books: SearchBook[] = [];
  @State shelfBookKeys: string[] = [];
  @State addingShelfBookKeys: string[] = [];
  @State isLoading: boolean = false;
  @State status: string = '';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '';
  @StorageLink('explorePlatform') selectedPlatform: string = '番茄';
  @StorageLink('exploreSourceUrl') selectedSourceUrl: string = '';
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('searchExploreSourceSort') searchExploreSourceSort: string = '';
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageLink('readerActiveFontFamily') readerActiveFontFamily: string = '';
  private coordinator: ExploreCoordinator = new ExploreCoordinator();
  private hasLoaded: boolean = false;
  private hasRestoredExploreSelection: boolean = false;
  private shelfStatusVersion: number = 0;
  private exploreLoadVersion: number = 0;

  aboutToAppear() {
    if (this.isActive) {
      this.ensureLoaded();
    }
  }

  onActiveChanged(): void {
    if (this.isActive) {
      this.ensureLoaded();
    }
  }

  ensureLoaded(): void {
    if (!this.hasLoaded && !this.isLoading) {
      this.loadEntries();
    }
  }

  onShelfChanged(): void {
    this.syncExploreShelfStatus(this.books);
  }

  async loadEntries(platformOverride: string = '') {
    const loadVersion = this.beginExploreLoad();
    this.hasLoaded = true;
    this.status = '正在加载发现分类...';
    this.verificationUrl = '';
    this.verificationTitle = '';
    try {
      if (!this.hasRestoredExploreSelection) {
        this.hasRestoredExploreSelection = true;
        await this.restoreExploreSelectionFromSettings();
        if (!this.isCurrentExploreLoad(loadVersion)) return;
      }
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      const previousSourceName = this.selectedSourceName;
      const previousSourceUrl = this.selectedSourceUrl;
      const sourceOptions = await this.coordinator.getExploreSources();
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      this.sourceOptions = this.sortExploreSourceOptions(sourceOptions);
      this.sourceNames = this.sourceOptions.map((option: ExploreSourceOption) => option.sourceName);
      const restoredOption = this.sourceOptions.find((option: ExploreSourceOption) =>
        option.sourceUrl === previousSourceUrl) ||
        this.sourceOptions.find((option: ExploreSourceOption) => option.sourceName === previousSourceName) ||
        (this.sourceOptions.length > 0 ? this.sourceOptions[0] : null);
      this.selectedSourceName = restoredOption ? restoredOption.sourceName : '';
      this.selectedSourceUrl = restoredOption ? restoredOption.sourceUrl : '';
      this.platformNames = this.getSelectedSourcePlatforms();
      if (platformOverride && this.platformNames.includes(platformOverride)) {
        this.selectedPlatform = platformOverride;
      }
      this.normalizeSelectedPlatform();
      const entries = await this.coordinator.getEntries(this.selectedPlatform, this.getSelectedSourceUrl());
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      this.entries = entries;
      if (this.entries.length > 0) {
        this.selectedIndex = 0;
        await this.loadBooks(loadVersion);
      } else {
        this.books = [];
        this.status = `${this.getSelectedSiteLabel()} 暂无可用发现分类`;
      }
    } catch (e) {
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      console.error('加载发现失败:', e);
      this.status = '发现加载失败';
    } finally {
      this.finishExploreLoad(loadVersion);
    }
  }

  async loadBooks(loadVersion?: number) {
    const currentLoadVersion = loadVersion ?? this.beginExploreLoad();
    const activeEntries = this.getActiveEntries();
    if (activeEntries.length === 0) {
      this.finishExploreLoad(currentLoadVersion);
      return;
    }
    this.status = '正在获取发现内容...';
    this.verificationUrl = '';
    this.verificationTitle = '';
    try {
      const entry = activeEntries[Math.min(this.selectedIndex, activeEntries.length - 1)];
      const books = await this.coordinator.explore(entry, 1);
      if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
      this.books = books;
      const shelfStatusVersion = this.shelfStatusVersion;
      const shelfKeys = await this.loadExploreShelfKeys(books);
      if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
      if (shelfStatusVersion === this.shelfStatusVersion) {
        this.shelfBookKeys = shelfKeys;
      }
      this.verificationUrl = AppStorage.get<string>('pendingVerificationUrl') || '';
      this.verificationTitle = AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
      this.status = this.books.length > 0 ?
        `${this.getSelectedSiteLabel()} · ${entry.sourceName} · ${entry.title} · ${this.books.length} 本` :
        (this.verificationUrl ? `${entry.sourceName} 可能需要网页验证` :
          `${this.getSelectedSiteLabel()} 当前分类暂无结果`);
    } catch (e) {
      if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
      console.error('获取发现内容失败:', e);
      this.status = '发现内容获取失败';
    } finally {
      this.finishExploreLoad(currentLoadVersion);
    }
  }

  build() {
    Column() {
      Row() {
        Row() {
          Text(this.selectedSourceName || '发现')
            .fontSize(16)
            .fontFamily(this.readerActiveFontFamily)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(this.showExploreSourcePicker ? '⌃' : '⌄')
            .fontSize(18)
            .fontFamily(this.readerActiveFontFamily)
            .fontColor(this.secondaryTextColor())
            .margin({ left: 6 })
        }
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .shadow({ radius: 8, color: this.glassShadowColor(), offsetX: 0, offsetY: 3 })
          .padding({ left: 16, right: 14 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            if (this.sourceOptions.length > 0) {
              this.showExploreSourcePicker = !this.showExploreSourcePicker;
            }
          })
          .bindPopup(this.showExploreSourcePicker, {
            builder: this.exploreSourcePopup,
            placement: Placement.Bottom,
            popupColor: this.cardColor(),
            enableArrow: false,
            autoCancel: true,
            onStateChange: (event) => {
              if (!event.isVisible) {
                this.showExploreSourcePicker = false;
              }
            }
          })

        Button('刷新')
          .height(36)
          .fontSize(14)
          .borderRadius(18)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .margin({ left: 8 })
          .onClick(() => {
            this.loadEntries();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (this.platformNames.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.platformNames, (name: string) => {
              Text(name)
                .fontSize(13)
                .fontColor(this.selectedPlatform === name ? '#FFFFFF' : this.primaryTextColor())
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.selectedPlatform === name ? this.accentColor() : this.glassCardColor())
                .borderRadius(18)
                .border({ width: this.selectedPlatform === name ? 0 : 1, color: this.glassBorderColor() })
                .onClick(() => {
                  this.switchExplorePlatform(name);
                })
            })
          }
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .height(48)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }

      if (this.getActiveEntries().length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.getActiveEntries(), (entry: ExploreEntry, index: number) => {
              Text(entry.title)
                .fontSize(13)
                .fontColor(this.selectedIndex === index ? '#FFFFFF' : this.secondaryTextColor())
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(this.selectedIndex === index ? this.accentColor() : this.glassCardColor())
                .borderRadius(17)
                .border({ width: this.selectedIndex === index ? 0 : 1, color: this.glassBorderColor() })
                .onClick(() => {
                  this.selectedIndex = index;
                  this.loadBooks();
                })
            })
          }
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .height(44)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }

      if (this.shouldShowExploreStatus()) {
        Row() {
          Text(this.status)
            .fontSize(13)
            .fontColor(this.secondaryTextColor())
            .layoutWeight(1)

          if (this.verificationUrl) {
            Button('去验证')
              .height(28)
              .fontSize(12)
              .borderRadius(14)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .margin({ left: 12 })
              .onClick(() => {
                this.openVerification();
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .alignItems(VerticalAlign.Center)
      }

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.subTextColor())
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.books.length > 0) {
        SearchBookResultList({
          books: this.books,
          shelfBookKeys: this.shelfBookKeys,
          busyBookKeys: this.addingShelfBookKeys,
          showKind: true,
          showResultCover: this.searchExploreShowResultCover,
          useBookshelfCoverGallery: this.searchExploreUseBookshelfCoverGallery,
          showResultTags: this.searchExploreShowResultTags,
          showSourceLine: false,
          pageColor: this.pageColor(),
          cardColor: this.glassCardColor(),
          itemBorderColor: this.glassBorderColor(),
          itemBorderWidth: 1,
          shadowColor: this.glassShadowColor(),
          primaryTextColor: this.primaryTextColor(),
          secondaryTextColor: this.secondaryTextColor(),
          subTextColor: this.subTextColor(),
          bottomPadding: this.resultListBottomInset(),
          onOpenBook: (book: SearchBook) => {
            this.openSearchBookDetail(book);
          },
          onToggleShelf: (book: SearchBook) => {
            this.toggleSearchBookShelf(book);
          }
        })
      } else {
        Column() {
          Text('没有发现内容')
            .fontSize(16)
            .fontColor(this.subTextColor())
          Text(this.verificationUrl ? '当前书源可能需要网页验证' : '请切换书源或网站，或检查已启用书源的发现地址')
            .fontSize(14)
            .fontColor(this.subTextColor())
            .margin({ top: 8 })
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32 })
          if (this.verificationUrl) {
            Button('去验证')
              .height(36)
              .fontSize(14)
              .borderRadius(18)
              .margin({ top: 14 })
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.openVerification();
              })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  openSearchBookDetail(book: SearchBook) {
    router.pushUrl({
      url: 'pages/SearchBookDetail',
      params: {
        bookUrl: book.bookUrl,
        tocUrl: book.tocUrl,
        origin: book.origin,
        originName: book.originName,
        name: book.name,
        author: book.author,
        kind: book.kind,
        coverUrl: book.coverUrl,
        intro: book.intro,
        latestChapterTitle: book.latestChapterTitle,
        wordCount: book.wordCount,
        promptAddToShelfOnBack: this.searchExplorePromptAddToShelfOnBack ? 'true' : 'false'
      }
    });
  }

  @Builder
  exploreSourcePopup() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.sourceOptions, (option: ExploreSourceOption) => {
            Row() {
              Text(option.sourceName || '未命名书源')
                .fontSize(16)
                .fontFamily(this.readerActiveFontFamily)
                .fontColor(option.sourceUrl === this.selectedSourceUrl ? this.accentColor() : this.primaryTextColor())
                .fontWeight(option.sourceUrl === this.selectedSourceUrl ? FontWeight.Medium : FontWeight.Regular)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (option.sourceUrl === this.selectedSourceUrl) {
                Text('✓')
                  .fontSize(15)
                  .fontFamily(this.readerActiveFontFamily)
                  .fontColor(this.accentColor())
                  .margin({ left: 10 })
              }
            }
            .width('100%')
            .height(44)
            .padding({ left: 14, right: 14 })
            .borderRadius(12)
            .backgroundColor(option.sourceUrl === this.selectedSourceUrl ? this.exploreSelectedBackgroundColor() : '#00000000')
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.showExploreSourcePicker = false;
              this.switchExploreSource(option);
            })
          })
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Auto)
    }
    .width(260)
    .padding(8)
    .borderRadius(16)
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: this.glassBorderColor() })
    .shadow({ radius: 14, color: this.glassShadowColor(), offsetX: 0, offsetY: 6 })
  }

  async addSearchBookToShelf(searchBook: SearchBook): Promise<void> {
    const searchKey = SearchBookShelfHelper.keyOf(searchBook);
    this.markSearchBookJoining(searchKey);
    try {
      const change = await SearchBookShelfHelper.addToShelf(getContext(this), searchBook);
      this.markSearchBookInShelf(change.shelfKey || change.requestKey);
    } catch (e) {
      console.error('加入书架失败:', e);
      promptAction.showToast({ message: '加入书架失败' });
    } finally {
      this.unmarkSearchBookJoining(searchKey);
    }
  }

  switchExplorePlatform(platform: string): void {
    if (this.selectedPlatform === platform) {
      return;
    }
    this.selectedPlatform = platform;
    this.selectedIndex = 0;
    this.books = [];
    this.status = `正在切换到 ${platform}...`;
    AppStorage.setOrCreate('explorePlatform', platform);
    this.saveExploreSelection();
    this.loadEntries(platform);
  }

  switchExploreSource(option: ExploreSourceOption): void {
    if (this.selectedSourceUrl === option.sourceUrl) {
      return;
    }
    this.selectedSourceName = option.sourceName;
    this.selectedSourceUrl = option.sourceUrl;
    this.platformNames = this.getSelectedSourcePlatforms();
    this.normalizeSelectedPlatform();
    this.selectedIndex = 0;
    this.books = [];
    this.status = `正在切换到 ${option.sourceName}...`;
    AppStorage.setOrCreate('exploreSourceUrl', option.sourceUrl);
    this.saveExploreSelection();
    this.loadEntries();
  }

  beginExploreLoad(): number {
    this.exploreLoadVersion++;
    this.isLoading = true;
    return this.exploreLoadVersion;
  }

  isCurrentExploreLoad(loadVersion: number): boolean {
    return loadVersion === this.exploreLoadVersion;
  }

  finishExploreLoad(loadVersion: number): void {
    if (this.isCurrentExploreLoad(loadVersion)) {
      this.isLoading = false;
    }
  }

  normalizeSelectedPlatform(): void {
    if (this.platformNames.length === 0) {
      return;
    }
    if (!this.platformNames.includes(this.selectedPlatform)) {
      this.selectedPlatform = this.platformNames.length > 0 ? this.platformNames[0] : '番茄';
      AppStorage.setOrCreate('explorePlatform', this.selectedPlatform);
      this.saveExploreSelection();
    }
  }

  async restoreExploreSelectionFromSettings(): Promise<void> {
    try {
      const settings = await SearchExploreSettingsStore.load(getContext(this));
      const storedSourceUrl = settings.exploreSourceUrl || AppStorage.get<string>('exploreSourceUrl') || '';
      const storedPlatform = settings.explorePlatform || AppStorage.get<string>('explorePlatform') || '';
      if (storedSourceUrl) {
        this.selectedSourceUrl = storedSourceUrl;
        settings.exploreSourceUrl = storedSourceUrl;
      }
      if (storedPlatform) {
        this.selectedPlatform = storedPlatform;
        settings.explorePlatform = storedPlatform;
      }
      SearchExploreSettingsStore.applyToStorage(settings);
    } catch (e) {
      console.warn('恢复发现页选择失败:', e);
    }
  }

  saveExploreSelection(): void {
    AppStorage.setOrCreate('exploreSourceUrl', this.selectedSourceUrl);
    AppStorage.setOrCreate('explorePlatform', this.selectedPlatform);
    SearchExploreSettingsStore.saveExploreSelection(
      getContext(this),
      this.selectedSourceUrl,
      this.selectedPlatform
    ).catch((e: Error) => {
      console.warn('保存发现页选择失败:', e);
    });
  }

  async syncExploreShelfStatus(books: SearchBook[]): Promise<void> {
    try {
      const version = this.shelfStatusVersion;
      const keys = await this.loadExploreShelfKeys(books);
      if (version === this.shelfStatusVersion) {
        this.shelfBookKeys = keys;
      }
    } catch (e) {
      console.error('同步发现书架状态失败:', e);
    }
  }

  async loadExploreShelfKeys(books: SearchBook[]): Promise<string[]> {
    return await SearchBookShelfHelper.syncShelfKeys(getContext(this), books);
  }

  isSearchBookInShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys);
  }

  isSearchBookJoiningShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isBusy(book, this.addingShelfBookKeys);
  }

  async toggleSearchBookShelf(searchBook: SearchBook): Promise<void> {
    if (this.isSearchBookJoiningShelf(searchBook)) {
      return;
    }

    if (this.isSearchBookInShelf(searchBook)) {
      await this.removeSearchBookFromShelf(searchBook);
    } else {
      await this.addSearchBookToShelf(searchBook);
    }
  }

  async removeSearchBookFromShelf(searchBook: SearchBook): Promise<void> {
    try {
      const change = await SearchBookShelfHelper.removeFromShelf(getContext(this), searchBook);
      this.shelfStatusVersion++;
      this.shelfBookKeys = SearchBookShelfHelper.withoutKey(this.shelfBookKeys, change.requestKey);
    } catch (e) {
      console.error('移出书架失败:', e);
      promptAction.showToast({ message: '移出书架失败' });
    }
  }

  markSearchBookInShelf(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.shelfBookKeys, bookKey);
    if (next !== this.shelfBookKeys) {
      this.shelfStatusVersion++;
      this.shelfBookKeys = next;
    }
  }

  markSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  unmarkSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withoutKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  buildSourceNames(): string[] {
    const names: string[] = [];
    for (const entry of this.entries) {
      if (entry.sourceName && !names.includes(entry.sourceName)) {
        names.push(entry.sourceName);
      }
    }
    return names;
  }

  sortExploreSourceOptions(sourceOptions: ExploreSourceOption[]): ExploreSourceOption[] {
    const order = (this.searchExploreSourceSort || '').split('\n')
      .map((url: string) => url.trim())
      .filter((url: string) => !!url);
    if (order.length === 0) {
      return sourceOptions;
    }
    const result: ExploreSourceOption[] = [];
    for (const url of order) {
      const option = sourceOptions.find((item: ExploreSourceOption) => item.sourceUrl === url);
      if (option && !result.some((item: ExploreSourceOption) => item.sourceUrl === option.sourceUrl)) {
        result.push(option);
      }
    }
    for (const option of sourceOptions) {
      if (!result.some((item: ExploreSourceOption) => item.sourceUrl === option.sourceUrl)) {
        result.push(option);
      }
    }
    return result;
  }

  exploreSourceSelectOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    if (this.sourceNames.length === 0) {
      const option: SelectOption = { value: '发现' };
      options.push(option);
      return options;
    }
    for (const name of this.sourceNames) {
      const option: SelectOption = { value: name };
      options.push(option);
    }
    return options;
  }

  selectedExploreSourceIndex(): number {
    const index = this.sourceOptions.findIndex((option: ExploreSourceOption) =>
      option.sourceUrl === this.selectedSourceUrl);
    return index >= 0 ? index : 0;
  }

  shouldShowExploreStatus(): boolean {
    if (!this.status) {
      return false;
    }
    if (this.verificationUrl) {
      return true;
    }
    return this.books.length === 0;
  }

  getSelectedSourcePlatforms(): string[] {
    const option = this.getSelectedSourceOption();
    return option ? option.platforms : [];
  }

  getSelectedSourceUrl(): string {
    const option = this.getSelectedSourceOption();
    return option ? option.sourceUrl : '';
  }

  getSelectedSourceOption(): ExploreSourceOption | null {
    for (const option of this.sourceOptions) {
      if (option.sourceUrl === this.selectedSourceUrl) return option;
    }
    return null;
  }

  getSelectedSiteLabel(): string {
    return this.platformNames.length > 0 ? this.selectedPlatform : this.selectedSourceName;
  }

  openVerification(): void {
    const url = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
    if (!url) {
      promptAction.showToast({ message: '暂无需要验证的网页' });
      return;
    }
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: this.verificationTitle || '网页验证'
      }
    });
  }

  getActiveEntries(): ExploreEntry[] {
    if (!this.selectedSourceUrl) return this.entries;
    return this.entries.filter(entry => entry.sourceUrl === this.selectedSourceUrl);
  }

  resultListBottomInset(): number {
    const comfortableGap = 20;
    if (deviceInfo.sdkApiVersion < 23) {
      return comfortableGap;
    }
    const floatingTabHeight = 56;
    return floatingTabHeight + Math.max(this.navBarHeight, 8) + comfortableGap;
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  glassCardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  glassShadowColor(): string {
    return '#00000000';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  secondaryTextColor(): string {
    return this.appDarkMode ? '#C6CBD2' : '#666';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#999';
  }

  accentColor(): string {
    return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  buttonColor(): string {
    return this.appDarkMode ? this.appDarkButtonColor : this.appLightButtonColor;
  }

  exploreSelectedBackgroundColor(): string {
    const color = this.accentColor();
    if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
      return `#11${color.substring(1)}`;
    }
    return this.appDarkMode ? '#112A6FCC' : '#11007DFF';
  }
}

@Component
struct SearchPage {
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Prop @Watch('onActiveChanged') isActive: boolean = false;
  @State keyword: string = '';
  @State searchResults: SearchBook[] = [];
  @State shelfBookKeys: string[] = [];
  @State addingShelfBookKeys: string[] = [];
  @State isSearching: boolean = false;
  @State showResult: boolean = false;
  @State statusMessage: string = '';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '';
  @State showSearchSettingsDialog: boolean = false;
  @State sourceGroups: string[] = [];
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('searchExploreExactSearch') exactSearch: boolean = false;
  @StorageLink('searchExploreExactSearchMatchAuthor') exactSearchMatchAuthor: boolean = true;
  @StorageLink('searchExploreShowSearchProgress') showSearchProgress: boolean = true;
  @StorageLink('searchExploreSearchConcurrency') searchConcurrency: number = 8;
  @StorageLink('searchExploreSelectedSourceGroups') selectedSourceGroupsRaw: string = '';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  private coordinator: SearchCoordinator | null = null;
  private hasInitialized: boolean = false;
  private shelfStatusVersion: number = 0;
  private shelfSyncRunning: boolean = false;
  private pendingShelfSyncBooks: SearchBook[] = [];
  private searchResultKeySet: Set<string> = new Set<string>();
  private searchSessionId: number = 0;
  private readonly NO_SOURCE_GROUPS_SELECTED: string = '__NO_SOURCE_GROUPS_SELECTED__';

  aboutToAppear() {
    if (this.isActive) {
      this.initPage();
    }
  }

  onActiveChanged(): void {
    if (this.isActive) {
      this.initPage();
      this.refreshSearchShelfStatus();
    }
  }

  async initPage() {
    if (this.hasInitialized) {
      return;
    }
    this.hasInitialized = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await this.loadSourceGroups(db);
    } catch (e) {
      console.error('初始化搜索页失败:', e);
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Row() {
            TextInput({ placeholder: '搜索书籍', text: this.keyword })
              .layoutWeight(1)
              .height(40)
              .backgroundColor('#00000000')
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.subTextColor())
              .padding({ left: 16, right: 4 })
              .onChange((value: string) => {
                this.keyword = value;
              })

            this.searchSettingIcon()
          }
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .shadow({ radius: 8, color: this.glassShadowColor(), offsetX: 0, offsetY: 3 })
          .alignItems(VerticalAlign.Center)

          Button(this.isSearching ? '停止' : '搜索')
            .height(36)
            .fontSize(14)
            .margin({ left: 8 })
            .borderRadius(18)
            .backgroundColor(this.isSearching ? '#E53935' : this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              if (this.isSearching) {
                this.searchSessionId++;
                this.coordinator?.cancel();
                this.coordinator = null;
                this.isSearching = false;
                this.statusMessage = '搜索已停止';
              } else {
                this.hideKeyboard();
                this.doSearch();
              }
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        if (this.statusMessage) {
          Row() {
            Text(this.statusMessage)
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .layoutWeight(1)
              .textAlign(TextAlign.Center)

            if (this.verificationUrl) {
              Button('去验证')
                .height(28)
                .fontSize(12)
                .borderRadius(14)
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .margin({ right: 12 })
                .onClick(() => {
                  this.openVerification();
                })
            }
          }
          .width('100%')
          .height(40)
          .backgroundColor(this.statusMessageColor())
          .alignItems(VerticalAlign.Center)
        }

        if (this.showResult && this.searchResults.length > 0) {
          SearchBookResultList({
            books: this.searchResults,
            shelfBookKeys: this.shelfBookKeys,
            busyBookKeys: this.addingShelfBookKeys,
            showLoadingMore: this.isSearching,
            showResultCover: this.searchExploreShowResultCover,
            useBookshelfCoverGallery: this.searchExploreUseBookshelfCoverGallery,
            showResultTags: this.searchExploreShowResultTags,
            pageColor: this.pageColor(),
            cardColor: this.glassCardColor(),
            itemBorderColor: this.glassBorderColor(),
            itemBorderWidth: 1,
            shadowColor: this.glassShadowColor(),
            primaryTextColor: this.primaryTextColor(),
            secondaryTextColor: this.secondaryTextColor(),
            subTextColor: this.subTextColor(),
            bottomPadding: this.resultListBottomInset(),
            onOpenBook: (book: SearchBook) => {
              this.openSearchBookDetail(book);
            },
            onToggleShelf: (book: SearchBook) => {
              this.toggleSearchBookShelf(book);
            }
          })
        } else if (this.isSearching) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
            Text('搜索中...')
              .fontSize(14)
              .fontColor(this.subTextColor())
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.showResult && this.searchResults.length === 0) {
          Column() {
            Text('未找到相关书籍')
              .fontSize(16)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
            Text('输入关键词搜索书籍')
              .fontSize(16)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight })
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      if (this.showSearchSettingsDialog) {
        this.searchSettingsDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  async doSearch() {
    const keyword = this.keyword.trim();
    if (!keyword) {
      promptAction.showToast({ message: '请输入搜索关键词' });
      return;
    }

    let sessionId = 0;
    let activeCoordinator: SearchCoordinator | null = null;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));

      this.isSearching = true;
      this.showResult = true;
      this.searchResults = [];
      this.searchResultKeySet.clear();
      this.statusMessage = '正在搜索...';
      this.verificationUrl = '';
      this.verificationTitle = '';
      this.coordinator?.cancel();
      sessionId = ++this.searchSessionId;
      const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
      activeCoordinator = coordinator;
      this.coordinator = coordinator;

      const callback: SearchCallback = (p: SearchProgress) => {
        if (sessionId !== this.searchSessionId || this.coordinator !== coordinator) {
          return;
        }
        if (p.finished) {
          this.searchResults = p.results;
          this.rebuildSearchResultKeys(p.results);
        } else if (p.deltaResults && p.deltaResults.length > 0) {
          this.searchResults = this.appendSearchResults(this.searchResults, p.deltaResults);
        }
        if (this.showSearchProgress) {
          this.statusMessage = p.status;
        }
        this.verificationUrl = p.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
        this.verificationTitle = p.verificationTitle || AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
        if (p.finished) {
          this.requestSearchShelfStatusSync(this.searchResults);
        } else if (p.deltaResults && p.deltaResults.length > 0) {
          this.requestSearchShelfStatusSync(p.deltaResults);
        }
        if (p.finished) {
          this.isSearching = false;
        }
      };

      const allBooks = await coordinator.search(keyword, callback, {
        exactMatch: this.exactSearch,
        exactMatchAuthor: this.exactSearchMatchAuthor,
        sourceGroups: this.searchSourceGroups()
      });
      if (sessionId !== this.searchSessionId || this.coordinator !== coordinator) {
        return;
      }
      const verifyUrl = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
      if (!this.showSearchProgress || !this.isSearching) {
        const resultText = allBooks.length > 0 ? `搜索完成，共找到 ${allBooks.length} 本书` : '搜索完成，未找到相关书籍';
        this.statusMessage = verifyUrl ? `${resultText}；有书源需要网页验证` : resultText;
      }
      await db.saveSearchKeyword(keyword);
    } catch (e) {
      if (sessionId !== this.searchSessionId || this.coordinator !== activeCoordinator) {
        return;
      }
      console.error('搜索失败:', e);
      this.isSearching = false;
      this.statusMessage = '搜索失败';
    } finally {
      if (sessionId === this.searchSessionId && this.coordinator === activeCoordinator && !this.isSearching) {
        this.coordinator = null;
      }
    }
  }

  hideKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
    }
  }

  onShelfChanged(): void {
    this.refreshSearchShelfStatus();
  }

  refreshSearchShelfStatus(): void {
    if (this.searchResults.length > 0) {
      this.requestSearchShelfStatusSync(this.searchResults);
    }
  }

  requestSearchShelfStatusSync(books: SearchBook[]): void {
    this.pendingShelfSyncBooks = books;
    if (!this.shelfSyncRunning) {
      this.drainSearchShelfStatusSync();
    }
  }

  appendSearchResults(existing: SearchBook[], incoming: SearchBook[]): SearchBook[] {
    const merged = existing.slice();
    for (const book of incoming) {
      const key = `${book.origin || ''}::${book.bookUrl || ''}`;
      if (!book.name || !book.bookUrl) continue;
      if (this.searchResultKeySet.has(key)) continue;
      this.searchResultKeySet.add(key);
      merged.push(book);
    }
    return merged;
  }

  rebuildSearchResultKeys(books: SearchBook[]): void {
    this.searchResultKeySet.clear();
    for (const book of books) {
      if (!book.name || !book.bookUrl) continue;
      this.searchResultKeySet.add(`${book.origin || ''}::${book.bookUrl || ''}`);
    }
  }

  async drainSearchShelfStatusSync(): Promise<void> {
    this.shelfSyncRunning = true;
    while (this.pendingShelfSyncBooks.length > 0) {
      const books = this.pendingShelfSyncBooks;
      this.pendingShelfSyncBooks = [];
      await this.syncSearchShelfStatus(books);
    }
    this.shelfSyncRunning = false;
  }

  async syncSearchShelfStatus(books: SearchBook[]): Promise<void> {
    try {
      const version = this.shelfStatusVersion;
      const keys = await SearchBookShelfHelper.syncShelfKeys(getContext(this), books);
      if (version === this.shelfStatusVersion) {
        this.shelfBookKeys = keys;
      }
    } catch (e) {
      console.error('同步搜索书架状态失败:', e);
    }
  }

  isSearchBookInShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys);
  }

  isSearchBookJoiningShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isBusy(book, this.addingShelfBookKeys);
  }

  async toggleSearchBookShelf(searchBook: SearchBook): Promise<void> {
    if (this.isSearchBookJoiningShelf(searchBook)) {
      return;
    }

    if (this.isSearchBookInShelf(searchBook)) {
      await this.removeSearchBookFromShelf(searchBook);
    } else {
      await this.addSearchBookToShelf(searchBook);
    }
  }

  async addSearchBookToShelf(searchBook: SearchBook): Promise<void> {
    const searchKey = SearchBookShelfHelper.keyOf(searchBook);
    this.markSearchBookJoining(searchKey);

    try {
      const change = await SearchBookShelfHelper.addToShelf(getContext(this), searchBook);
      this.markSearchBookInShelf(change.shelfKey || change.requestKey);
    } catch (e) {
      console.error('加入书架失败:', e);
      promptAction.showToast({ message: '加入书架失败' });
    } finally {
      this.unmarkSearchBookJoining(searchKey);
    }
  }

  async removeSearchBookFromShelf(searchBook: SearchBook): Promise<void> {
    try {
      const change = await SearchBookShelfHelper.removeFromShelf(getContext(this), searchBook);
      this.shelfStatusVersion++;
      this.shelfBookKeys = SearchBookShelfHelper.withoutKey(this.shelfBookKeys, change.requestKey);
    } catch (e) {
      console.error('移出书架失败:', e);
      promptAction.showToast({ message: '移出书架失败' });
    }
  }

  markSearchBookInShelf(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.shelfBookKeys, bookKey);
    if (next !== this.shelfBookKeys) {
      this.shelfStatusVersion++;
      this.shelfBookKeys = next;
    }
  }

  markSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  unmarkSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withoutKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  openSearchBookDetail(book: SearchBook) {
    router.pushUrl({
      url: 'pages/SearchBookDetail',
      params: {
        bookUrl: book.bookUrl,
        tocUrl: book.tocUrl,
        origin: book.origin,
        originName: book.originName,
        name: book.name,
        author: book.author,
        kind: book.kind,
        coverUrl: book.coverUrl,
        intro: book.intro,
        latestChapterTitle: book.latestChapterTitle,
        wordCount: book.wordCount,
        promptAddToShelfOnBack: this.searchExplorePromptAddToShelfOnBack ? 'true' : 'false'
      }
    });
  }

  async loadSourceGroups(db: AppDatabase = AppDatabase.getInstance()): Promise<void> {
    const sources = await db.getAllBookSources();
    const groups: string[] = [];
    for (const source of sources) {
      const group = this.normalizeSourceGroup(source);
      if (!groups.includes(group)) {
        groups.push(group);
      }
    }
    this.sourceGroups = groups.sort((a: string, b: string) => a.localeCompare(b));
    if (!this.isAllSourceGroupsSelected() && !this.isNoSourceGroupsSelected()) {
      this.saveSelectedSourceGroups(this.selectedSourceGroups().filter((group: string) => this.sourceGroups.includes(group)));
    }
  }

  normalizeSourceGroup(source: BookSource): string {
    const group = (source.bookSourceGroup || '').trim();
    return group || '未分组';
  }

  isAllSourceGroupsSelected(): boolean {
    const selectedGroups = this.selectedSourceGroups();
    return !this.isNoSourceGroupsSelected() &&
      (this.selectedSourceGroupsRaw.trim() === '' || selectedGroups.length >= this.sourceGroups.length);
  }

  isNoSourceGroupsSelected(): boolean {
    return this.selectedSourceGroupsRaw.trim() === this.NO_SOURCE_GROUPS_SELECTED;
  }

  isSourceGroupSelected(group: string): boolean {
    return !this.isNoSourceGroupsSelected() &&
      (this.isAllSourceGroupsSelected() || this.selectedSourceGroups().includes(group));
  }

  setSourceGroupSelected(group: string, selected: boolean): void {
    const selectedGroups = this.isAllSourceGroupsSelected() ? this.sourceGroups : this.selectedSourceGroups();
    if (selected) {
      if (!selectedGroups.includes(group)) {
        this.saveSelectedSourceGroups(selectedGroups.concat([group]));
      }
      return;
    }
    this.saveSelectedSourceGroups(selectedGroups.filter((item: string) => item !== group));
  }

  searchSourceGroupSummary(): string {
    if (this.isAllSourceGroupsSelected()) {
      return '全部书源';
    }
    if (this.isNoSourceGroupsSelected()) {
      return '未选择书源';
    }
    return `已选 ${this.selectedSourceGroups().length} 个分组`;
  }

  selectedSourceGroups(): string[] {
    const raw = this.selectedSourceGroupsRaw.trim();
    if (!raw || raw === this.NO_SOURCE_GROUPS_SELECTED) {
      return [];
    }
    return raw.split('\n').map((group: string) => group.trim()).filter((group: string) => group);
  }

  searchSourceGroups(): string[] {
    if (this.isNoSourceGroupsSelected()) {
      return [this.NO_SOURCE_GROUPS_SELECTED];
    }
    return this.isAllSourceGroupsSelected() ? [] : this.selectedSourceGroups();
  }

  saveSelectedSourceGroups(groups: string[]): void {
    const normalized: string[] = [];
    for (const group of groups) {
      const value = (group || '').trim();
      if (value && !normalized.includes(value)) {
        normalized.push(value);
      }
    }
    this.selectedSourceGroupsRaw = normalized.length > 0 ? normalized.join('\n') : this.NO_SOURCE_GROUPS_SELECTED;
    if (normalized.length >= this.sourceGroups.length) {
      this.selectedSourceGroupsRaw = '';
    }
    this.saveSearchExploreSettings();
  }

  saveAllSourceGroupsSelected(selected: boolean): void {
    this.selectedSourceGroupsRaw = selected ? '' : this.NO_SOURCE_GROUPS_SELECTED;
    this.saveSearchExploreSettings();
  }

  saveSearchExploreSettings(): void {
    SearchExploreSettingsStore.load(getContext(this)).then((settings: SearchExploreSettings) => {
      settings.showResultCover = this.searchExploreShowResultCover;
      settings.useBookshelfCoverGallery = this.searchExploreUseBookshelfCoverGallery;
      settings.showResultTags = this.searchExploreShowResultTags;
      settings.promptAddToShelfOnBack = this.searchExplorePromptAddToShelfOnBack;
      settings.exactSearch = this.exactSearch;
      settings.exactSearchMatchAuthor = this.exactSearchMatchAuthor;
      settings.showSearchProgress = this.showSearchProgress;
      settings.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(this.searchConcurrency);
      settings.selectedSourceGroupsRaw = this.selectedSourceGroupsRaw;
      settings.sourceSortRaw = AppStorage.get<string>('searchExploreSourceSort') || '';
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(getContext(this), settings);
    }).catch((e: Error) => {
      console.warn('保存搜索设置失败:', e);
    });
  }

  @Builder
  searchSettingsDialog() {
    Column() {
      Column() {
        Text('搜索设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 16 })

        this.switchSettingRow('精准搜索', this.exactSearch, (checked: boolean) => {
          this.exactSearch = checked;
          this.saveSearchExploreSettings();
        })

        this.switchSettingRow('匹配作者', this.exactSearchMatchAuthor, (checked: boolean) => {
          this.exactSearchMatchAuthor = checked;
          this.saveSearchExploreSettings();
        })

        this.switchSettingRow('显示搜索进度', this.showSearchProgress, (checked: boolean) => {
          this.showSearchProgress = checked;
          this.saveSearchExploreSettings();
        })

        this.numberSettingRow('搜索并发数', this.searchConcurrency, 1, 32, (value: number) => {
          this.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(value);
          this.saveSearchExploreSettings();
        })

        Row() {
          Text('搜索书源设置')
            .fontSize(15)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)

          Text(this.searchSourceGroupSummary())
            .fontSize(13)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .height(42)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })

        Row() {
          Toggle({ type: ToggleType.Checkbox, isOn: this.isAllSourceGroupsSelected() })
            .selectedColor(this.buttonColor())
            .onChange((isOn: boolean) => {
              this.saveAllSourceGroupsSelected(isOn);
            })
          Text('全部书源')
            .fontSize(14)
            .fontColor(this.secondaryTextColor())
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .height(38)
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            ForEach(this.sourceGroups, (group: string) => {
              Row() {
                Toggle({ type: ToggleType.Checkbox, isOn: this.isSourceGroupSelected(group) })
                  .selectedColor(this.buttonColor())
                  .onChange((isOn: boolean) => {
                    if (this.isAllSourceGroupsSelected() && !isOn) {
                      this.saveSelectedSourceGroups(this.sourceGroups.filter((item: string) => item !== group));
                      return;
                    }
                    this.setSourceGroupSelected(group, isOn);
                  })
                Text(group)
                  .fontSize(14)
                  .fontColor(this.secondaryTextColor())
                  .margin({ left: 8 })
                  .layoutWeight(1)
              }
              .width('100%')
              .height(36)
              .alignItems(VerticalAlign.Center)
            })
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 180 })
        .margin({ top: 4 })

        Button('完成')
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.showSearchSettingsDialog = false;
          })
      }
      .width('88%')
      .padding(24)
      .backgroundColor(this.cardColor())
      .borderRadius(12)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showSearchSettingsDialog = false;
    })
  }

  @Builder
  searchSettingIcon() {
    Text('⋮')
      .fontSize(24)
      .fontColor(this.buttonColor())
      .fontWeight(FontWeight.Medium)
      .width(36)
      .height(36)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.buttonBackgroundColor())
      .borderRadius(18)
      .margin({ right: 2 })
      .onClick(() => {
        this.hideKeyboard();
        this.loadSourceGroups().catch((e: Error) => {
          console.warn('加载搜索书源分组失败:', e);
        });
        this.showSearchSettingsDialog = true;
      })
  }

  @Builder
  switchSettingRow(title: string, checked: boolean, onChange: (checked: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(this.buttonColor())
        .onChange(onChange)
    }
    .width('100%')
    .height(42)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  numberSettingRow(title: string, value: number, minValue: number, maxValue: number, onChange: (value: number) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Row() {
        Text('−')
          .fontSize(18)
          .fontColor(this.primaryTextColor())
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onChange(Math.max(minValue, this.searchConcurrency - 1));
          })
        Text(`${this.searchConcurrency}`)
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .width(42)
          .textAlign(TextAlign.Center)
        Text('+')
          .fontSize(18)
          .fontColor(this.primaryTextColor())
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onChange(Math.min(maxValue, this.searchConcurrency + 1));
          })
      }
      .height(30)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(42)
    .alignItems(VerticalAlign.Center)
  }

  openVerification(): void {
    const url = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
    if (!url) {
      promptAction.showToast({ message: '暂无需要验证的网页' });
      return;
    }
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: this.verificationTitle || '网页验证'
      }
    });
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  glassCardColor(): string {
    return this.cardColor();
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  glassShadowColor(): string {
    return '#00000000';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  secondaryTextColor(): string {
    return this.appDarkMode ? '#C6CBD2' : '#666';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#999';
  }

  statusMessageColor(): string {
    return this.appDarkMode ? '#14251B' : '#E8F5E9';
  }

  buttonColor(): string {
    return this.appDarkMode ? this.appDarkButtonColor : this.appLightButtonColor;
  }

  buttonBackgroundColor(): string {
    const normalized = AppThemeSettingsStore.normalizeColor(this.buttonColor(), AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR);
    return `#${this.appDarkMode ? '33' : '1A'}${normalized.substring(1)}`;
  }

  resultListBottomInset(): number {
    const comfortableGap = 20;
    if (deviceInfo.sdkApiVersion < 23) {
      return comfortableGap;
    }
    const floatingTabHeight = 56;
    return floatingTabHeight + Math.max(this.navBarHeight, 8) + comfortableGap;
  }
}

@Component
struct SettingsPage {
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';

  build() {
    Column() {
      Row() {
        Text('我的')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.appDarkMode ? '#F2F3F5' : '#1F1F1F')
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16 })
      .alignItems(VerticalAlign.Center)

      List({ space: 1 }) {
        ListItem() {
          Row() {
            Column() {
              Text('书源管理')
                .fontSize(16)
                .fontColor(this.appDarkMode ? '#F2F3F5' : '#1F1F1F')
              Text('导入、编辑、启用和调试书源')
                .fontSize(12)
                .fontColor(this.appDarkMode ? '#8A8F98' : '#999')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('>')
              .fontSize(16)
              .fontColor(this.appDarkMode ? '#777D87' : '#999')
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .onClick(() => {
            router.pushUrl({ url: 'pages/BookSource' });
          })
        }

        ListItem() {
          Row() {
            Column() {
              Text('阅读设置')
                .fontSize(16)
                .fontColor(this.appDarkMode ? '#F2F3F5' : '#1F1F1F')
              Text('字号、行距、背景与阅读偏好')
                .fontSize(12)
                .fontColor(this.appDarkMode ? '#8A8F98' : '#999')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('>')
              .fontSize(16)
              .fontColor(this.appDarkMode ? '#777D87' : '#999')
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
        }

        ListItem() {
          Row() {
            Column() {
              Text('朗读设置')
                .fontSize(16)
                .fontColor(this.appDarkMode ? '#F2F3F5' : '#1F1F1F')
              Text('音色与朗读倍速')
                .fontSize(12)
                .fontColor(this.appDarkMode ? '#8A8F98' : '#999')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('>')
              .fontSize(16)
              .fontColor(this.appDarkMode ? '#777D87' : '#999')
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .onClick(() => {
            router.pushUrl({ url: 'pages/TtsSettings' });
          })
        }

        ListItem() {
          Row() {
            Column() {
              Text('书架设置')
                .fontSize(16)
                .fontColor(this.appDarkMode ? '#F2F3F5' : '#1F1F1F')
              Text('标签、简介与封面图集')
                .fontSize(12)
                .fontColor(this.appDarkMode ? '#8A8F98' : '#999')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('>')
              .fontSize(16)
              .fontColor(this.appDarkMode ? '#777D87' : '#999')
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .onClick(() => {
            router.pushUrl({ url: 'pages/BookshelfSettings' });
          })
        }

        ListItem() {
          Row() {
            Column() {
              Text('搜索/发现配置')
                .fontSize(16)
                .fontColor(this.appDarkMode ? '#F2F3F5' : '#1F1F1F')
              Text('封面、标签与阅读后加入书架提示')
                .fontSize(12)
                .fontColor(this.appDarkMode ? '#8A8F98' : '#999')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('>')
              .fontSize(16)
              .fontColor(this.appDarkMode ? '#777D87' : '#999')
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .onClick(() => {
            router.pushUrl({ url: 'pages/SearchExploreSettings' });
          })
        }

        ListItem() {
          Row() {
            Column() {
              Text('其他设置')
                .fontSize(16)
                .fontColor(this.appDarkMode ? '#F2F3F5' : '#1F1F1F')
              Text('主题色、按钮色与通用偏好')
                .fontSize(12)
                .fontColor(this.appDarkMode ? '#8A8F98' : '#999')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('>')
              .fontSize(16)
              .fontColor(this.accentColor())
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .onClick(() => {
            router.pushUrl({ url: 'pages/OtherSettings' });
          })
        }

        ListItem() {
          Row() {
            Column() {
              Text('关于')
                .fontSize(16)
                .fontColor(this.appDarkMode ? '#F2F3F5' : '#1F1F1F')
              Text('版本、说明、开源许可与致谢')
                .fontSize(12)
                .fontColor(this.appDarkMode ? '#8A8F98' : '#999')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('>')
              .fontSize(16)
              .fontColor(this.appDarkMode ? '#777D87' : '#999')
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .onClick(() => {
            router.pushUrl({ url: 'pages/About' });
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.appDarkMode ? '#101113' : '#F5F5F5')
      .padding({ bottom: 96 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.appDarkMode ? '#101113' : '#F5F5F5')
  }

  glassCardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  accentColor(): string {
    return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor;
  }
}
