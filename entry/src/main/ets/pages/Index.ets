import { router, window } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import deviceInfo from '@ohos.deviceInfo';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { Book, BookChapter, SearchBook } from '../model/data/Book';
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
  @State isCacheTocLoading: boolean = false;
  @State editingTags: string[] = [];
  @State tagInput: string = '';
  @State shelfCoverMap: Map<string, string> = new Map();
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('bookshelfSortMode') sortMode: string = 'recentRead';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('bookshelfShowTags') bookshelfShowTags: boolean = true;
  @StorageLink('bookshelfShowIntro') bookshelfShowIntro: boolean = true;
  @StorageLink('bookshelfShowFullIntro') bookshelfShowFullIntro: boolean = false;
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
  private loadTimer: number = -1;
  private cacheTocLoadToken: number = 0;
  private cacheTocLoadBookUrl: string = '';
  private cacheTocLoadPromise: Promise<boolean> | null = null;

  aboutToAppear() {
    this.reloadDisplaySettings();
    this.scheduleLoadBooks();
  }

  async reloadDisplaySettings(): Promise<void> {
    try {
      const settings = await BookshelfDisplaySettingsStore.load(getContext(this));
      this.bookshelfShowTags = settings.showTags;
      this.bookshelfShowIntro = settings.showIntro;
      this.bookshelfShowFullIntro = settings.showFullIntro;
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
          this.shelfCoverMap = new Map(nextMap);
          continue;
        }
        pending.push([key, raw]);
      }
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
          List({ space: 8 }) {
            ForEach(this.books, (book: Book) => {
              ListItem() {
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
                        if (book.origin !== 'local') {
                          Text(book.originName || book.origin)
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
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(12)
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
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.pageColor())
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
                this.openCacheDialog(book);
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
              if (!this.isCaching) {
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

            this.actionItem(this.isCaching ? '正在缓存...' : '缓存全文', this.primaryTextColor(), () => {
              this.cacheWholeBook();
            })
            this.actionItem('缓存指定章节', this.primaryTextColor(), () => {
              if (!this.isCaching) {
                this.showCacheDialog = false;
                this.showChapterCacheDialog = true;
                if (this.cacheTargetBook) {
                  this.loadCacheChapters(this.cacheTargetBook);
                }
              }
            })

            Button('取消')
              .width('100%')
              .height(44)
              .margin({ top: 10 })
              .backgroundColor(this.appDarkMode ? '#24272D' : '#F5F5F5')
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                if (!this.isCaching) {
                  this.closeCacheDialog();
                }
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
              if (!this.isCaching) {
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
                  if (!this.isCaching) {
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
                    if (!this.isCaching) {
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

  getBookIntroText(book: Book): string {
    return (book.getDisplayIntro() || '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  @Builder
  coverView(book: Book, width: number, height: number) {
    Stack() {
      Column() {
        Text(book.name ? book.name.substring(0, 1) : '书')
          .fontSize(28)
          .fontColor('#FFFFFF')
      }
      .width(width)
      .height(height)
      .backgroundColor(this.getBookColor(book.name))
      .justifyContent(FlexAlign.Center)

      if (this.getShelfCoverList(book).length > 1) {
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
      } else if (this.getShelfCoverList(book).length === 1) {
        Image(this.getShelfCover(book))
          .width(width)
          .height(height)
          .objectFit(ImageFit.Cover)
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
    for (let i = 0; i < covers.length; i++) {
      displayCovers.push(this.shelfCoverMap.get(this.shelfCoverKey(book, i)) || covers[i]);
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
    this.cacheStatus = '正在加载目录...';
    this.showCacheDialog = true;
    this.loadCacheChapters(book);
  }

  closeCacheDialog(): void {
    this.showCacheDialog = false;
    this.showChapterCacheDialog = false;
    this.cacheTargetBook = null;
    this.cacheChapters = [];
    this.cacheStatus = '';
    this.isCaching = false;
    this.isCacheTocLoading = false;
    this.cacheTocLoadToken++;
    this.cacheTocLoadBookUrl = '';
    this.cacheTocLoadPromise = null;
    this.pendingActionBook = null;
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
      this.cacheStatus = chapters.length > 0 ? `${chapters.length} 章可缓存` : '暂未获取到目录';
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
    if (!this.cacheTargetBook || this.isCaching) {
      return;
    }
    if (this.cacheTargetBook.origin === 'local') {
      promptAction.showToast({ message: '本地书籍无需缓存' });
      return;
    }
    this.isCaching = true;
    try {
      if (!await this.loadCacheChapters(this.cacheTargetBook)) {
        return;
      }
      const engine = ReadBookEngine.get();
      const total = this.cacheChapters.length;
      if (total === 0) {
        this.cacheStatus = '暂无可缓存章节';
        return;
      }
      let success = 0;
      for (let i = 0; i < total; i++) {
        this.cacheStatus = `正在缓存 ${i + 1}/${total}`;
        try {
          if (await engine.cacheChapter(i)) {
            success++;
          }
        } catch (e) {
          console.error('缓存章节失败:', i, e);
        }
        this.cacheChapters = [...engine.chapters];
      }
      this.cacheStatus = `缓存完成：${success}/${total}`;
      promptAction.showToast({ message: `缓存完成 ${success}/${total}` });
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } finally {
      this.isCaching = false;
    }
  }

  async cacheSingleChapter(index: number): Promise<void> {
    if (!this.cacheTargetBook || this.isCaching) {
      return;
    }
    if (this.cacheTargetBook.origin === 'local') {
      promptAction.showToast({ message: '本地书籍无需缓存' });
      return;
    }
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
      this.isCaching = false;
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
  @State books: SearchBook[] = [];
  @State shelfBookKeys: string[] = [];
  @State addingShelfBookKeys: string[] = [];
  @State isLoading: boolean = false;
  @State status: string = '';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '';
  @StorageLink('explorePlatform') selectedPlatform: string = '番茄';
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  private coordinator: ExploreCoordinator = new ExploreCoordinator();
  private hasLoaded: boolean = false;
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
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      const previousSourceName = this.selectedSourceName;
      const sourceOptions = await this.coordinator.getExploreSources();
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      this.sourceOptions = sourceOptions;
      this.sourceNames = sourceOptions.map((option: ExploreSourceOption) => option.sourceName);
      this.selectedSourceName = previousSourceName && this.sourceNames.includes(previousSourceName) ?
        previousSourceName : (this.sourceNames.length > 0 ? this.sourceNames[0] : '');
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
        Text('发现')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)

        Button('刷新')
          .height(36)
          .fontSize(14)
          .borderRadius(18)
          .backgroundColor(this.buttonColor())
          .onClick(() => {
            this.loadEntries();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (this.sourceNames.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.sourceNames, (name: string) => {
              Text(name)
                .fontSize(13)
                .fontColor(this.selectedSourceName === name ? '#FFFFFF' : this.primaryTextColor())
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.selectedSourceName === name ? this.accentColor() : this.glassCardColor())
                .borderRadius(18)
                .border({ width: this.selectedSourceName === name ? 0 : 1, color: this.glassBorderColor() })
                .onClick(() => {
                  this.switchExploreSource(name);
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

      if (this.status) {
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
    this.loadEntries(platform);
  }

  switchExploreSource(sourceName: string): void {
    if (this.selectedSourceName === sourceName) {
      return;
    }
    this.selectedSourceName = sourceName;
    this.platformNames = this.getSelectedSourcePlatforms();
    this.normalizeSelectedPlatform();
    this.selectedIndex = 0;
    this.books = [];
    this.status = `正在切换到 ${sourceName}...`;
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
    }
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
      if (option.sourceName === this.selectedSourceName) return option;
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
    if (!this.selectedSourceName) return this.entries;
    return this.entries.filter(entry => entry.sourceName === this.selectedSourceName);
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
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  private coordinator: SearchCoordinator | null = null;
  private hasInitialized: boolean = false;
  private shelfStatusVersion: number = 0;
  private shelfSyncRunning: boolean = false;
  private pendingShelfSyncBooks: SearchBook[] = [];

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
    } catch (e) {
      console.error('初始化搜索页失败:', e);
    }
  }

  build() {
    Column() {
      Row() {
        TextInput({ placeholder: '搜索书籍', text: this.keyword })
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .shadow({ radius: 8, color: this.glassShadowColor(), offsetX: 0, offsetY: 3 })
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.keyword = value;
          })

        Button(this.isSearching ? '停止' : '搜索')
          .height(40)
          .margin({ left: 8 })
          .borderRadius(20)
          .backgroundColor(this.isSearching ? '#E53935' : this.buttonColor())
          .onClick(() => {
            if (this.isSearching) {
              this.coordinator?.cancel();
              this.isSearching = false;
              this.statusMessage = '搜索已停止';
            } else {
              this.hideKeyboard();
              this.doSearch();
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

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
  }

  async doSearch() {
    const keyword = this.keyword.trim();
    if (!keyword) {
      promptAction.showToast({ message: '请输入搜索关键词' });
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));

      this.isSearching = true;
      this.showResult = true;
      this.searchResults = [];
      this.statusMessage = '正在搜索...';
      this.verificationUrl = '';
      this.verificationTitle = '';

      const callback: SearchCallback = (p: SearchProgress) => {
        this.searchResults = p.results;
        this.statusMessage = p.status;
        this.verificationUrl = p.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
        this.verificationTitle = p.verificationTitle || AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
        this.requestSearchShelfStatusSync(p.results);
        if (p.finished) {
          this.isSearching = false;
        }
      };

      this.coordinator = new SearchCoordinator(10);
      await this.coordinator.search(keyword, callback);
      await db.saveSearchKeyword(keyword);
    } catch (e) {
      console.error('搜索失败:', e);
      this.isSearching = false;
      this.statusMessage = '搜索失败';
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
