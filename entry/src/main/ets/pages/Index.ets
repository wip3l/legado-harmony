import { router, window } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { Book, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchCoordinator, SearchCallback, SearchProgress } from '../core/book/SearchCoordinator';
import { ExploreCoordinator, ExploreEntry } from '../core/book/ExploreCoordinator';
import { WebBookService } from '../core/book/WebBookService';
import { syncSystemSafeAreas } from '../utils/SystemBars';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('appDarkMode') @Watch('onAppDarkModeChanged') appDarkMode: boolean = false;

  aboutToAppear() {
    this.syncHomeSystemBars();
  }

  onPageShow(): void {
    this.syncHomeSystemBars();
  }

  onAppDarkModeChanged(): void {
    this.syncHomeSystemBars();
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
        BookshelfPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar($r('app.media.ic_tab_bookshelf'), '书架'))

      TabContent() {
        ExplorePage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar($r('app.media.ic_tab_explore'), '发现'))

      TabContent() {
        SearchPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar($r('app.media.ic_tab_search'), '搜索'))

      TabContent() {
        SettingsPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
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
        BookshelfPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar($r('app.media.ic_tab_bookshelf'), '书架', 0))

      TabContent() {
        ExplorePage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar($r('app.media.ic_tab_explore'), '发现', 1))

      TabContent() {
        SearchPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar($r('app.media.ic_tab_search'), '搜索', 2))

      TabContent() {
        SettingsPage({ statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight })
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
    return '#007DFF';
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
struct BookshelfPage {
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @State books: Book[] = [];
  @State isLoading: boolean = false;
  @State showDeleteDialog: boolean = false;
  @State pendingDeleteBook: Book | null = null;
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('bookshelfSortMode') sortMode: string = 'recentRead';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;

  aboutToAppear() {
    this.loadBooks();
  }

  onShelfChanged(): void {
    this.loadBooks();
  }

  async loadBooks() {
    this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.books = this.sortBooks(await db.getAllBooks());
    } catch (e) {
      console.error('加载书籍失败:', e);
    } finally {
      this.isLoading = false;
    }
  }

  async deleteBook(book: Book) {
    try {
      const db = AppDatabase.getInstance();
      await db.deleteBook(book.bookUrl);
      promptAction.showToast({ message: `已删除《${book.name}》` });
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
                Row() {
                  // 封面占位
                  Column() {
                    Text(book.name ? book.name.substring(0, 1) : '书')
                      .fontSize(28)
                      .fontColor('#FFFFFF')
                  }
                  .width(56)
                  .height(72)
                  .borderRadius(6)
                  .backgroundColor(this.getBookColor(book.name))
                  .justifyContent(FlexAlign.Center)

                  Column() {
                    Text(book.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.primaryTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(book.author || '作者未知')
                      .fontSize(14)
                      .fontColor(this.secondaryTextColor())
                      .margin({ top: 4 })

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
                    .margin({ top: 4 })
                  }
                  .layoutWeight(1)
                  .margin({ left: 12 })
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.glassCardColor())
                .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
                .borderRadius(8)
                .border({ width: 1, color: this.glassBorderColor() })
                .shadow({ radius: 10, color: this.glassShadowColor(), offsetX: 0, offsetY: 4 })
                .gesture(
                  LongPressGesture({ repeat: false })
                    .onAction(() => {
                      this.showDeleteConfirm(book);
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

  getBookColor(name: string): string {
    if (!name) return '#007DFF';
    const colors = ['#007DFF', '#E53935', '#43A047', '#EF6C00', '#8E24AA', '#00ACC1', '#D81B60', '#5E35B1'];
    let hash = 0;
    for (let i = 0; i < name.length; i++) {
      hash = name.charCodeAt(i) + ((hash << 5) - hash);
    }
    return colors[Math.abs(hash) % colors.length];
  }

  @Builder
  sortChip(label: string, mode: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.sortMode === mode ? '#FFFFFF' : this.secondaryTextColor())
      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .backgroundColor(this.sortMode === mode ? '#007DFF' : this.glassCardColor())
      .backgroundBlurStyle(this.sortMode === mode ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
      .borderRadius(16)
      .border({ width: this.sortMode === mode ? 0 : 1, color: this.glassBorderColor() })
      .onClick(() => {
        this.sortMode = mode;
        this.books = this.sortBooks(this.books);
      })
  }

  sortBooks(books: Book[]): Book[] {
    const sorted = [...books];
    if (this.sortMode === 'recentRead') {
      sorted.sort((a: Book, b: Book) => {
        const readDiff = this.getBookReadTime(b) - this.getBookReadTime(a);
        return readDiff !== 0 ? readDiff : this.getBookAddTime(b) - this.getBookAddTime(a);
      });
    } else if (this.sortMode === 'name') {
      sorted.sort((a: Book, b: Book) => (a.name || '').localeCompare(b.name || ''));
    } else {
      sorted.sort((a: Book, b: Book) => this.getBookAddTime(b) - this.getBookAddTime(a));
    }
    return sorted;
  }

  getBookAddTime(book: Book): number {
    return book.latestChapterTime || book.lastCheckTime || book.durChapterTime || 0;
  }

  getBookReadTime(book: Book): number {
    const lastReadTime = this.parseBookTime(book.getVariable('lastReadTime'));
    if (lastReadTime > 0) {
      return lastReadTime;
    }
    if (!book.durChapterTitle && book.durChapterIndex <= 0 && book.durChapterPos <= 0) {
      return 0;
    }
    return book.durChapterTime || 0;
  }

  parseBookTime(value: string): number {
    const time = Number(value);
    return time > 0 ? time : 0;
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

  glassCardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#38FFFFFF';
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#00000000' : '#99FFFFFF';
  }

  glassShadowColor(): string {
    return this.appDarkMode ? '#00000000' : '#10000000';
  }

  sourceTagBackgroundColor(): string {
    return this.appDarkMode ? '#24272D' : '#E8F0FE';
  }

  sourceTagTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#007DFF';
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
}

@Component
struct ExplorePage {
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @State entries: ExploreEntry[] = [];
  @State sourceNames: string[] = [];
  @State selectedSourceName: string = '';
  @State selectedIndex: number = 0;
  @State books: SearchBook[] = [];
  @State shelfBookUrls: string[] = [];
  @State isLoading: boolean = false;
  @State status: string = '';
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  private coordinator: ExploreCoordinator = new ExploreCoordinator();

  aboutToAppear() {
    this.loadEntries();
  }

  onShelfChanged(): void {
    this.syncExploreShelfStatus(this.books);
  }

  async loadEntries() {
    this.isLoading = true;
    this.status = '正在加载发现分类...';
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.entries = await this.coordinator.getEntries();
      this.sourceNames = this.buildSourceNames();
      if (this.entries.length > 0) {
        this.selectedSourceName = this.sourceNames.length > 0 ? this.sourceNames[0] : '';
        this.selectedIndex = 0;
        await this.loadBooks();
      } else {
        this.books = [];
        this.status = '暂无可用发现分类，请检查书源的发现地址';
      }
    } catch (e) {
      console.error('加载发现失败:', e);
      this.status = '发现加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async loadBooks() {
    const activeEntries = this.getActiveEntries();
    if (activeEntries.length === 0) return;
    this.isLoading = true;
    this.status = '正在获取发现内容...';
    try {
      const entry = activeEntries[Math.min(this.selectedIndex, activeEntries.length - 1)];
      this.books = await this.coordinator.explore(entry, 1);
      await this.syncExploreShelfStatus(this.books);
      this.status = this.books.length > 0 ? `${entry.sourceName} · ${entry.title} · ${this.books.length} 本` : '当前分类暂无结果';
    } catch (e) {
      console.error('获取发现内容失败:', e);
      this.status = '发现内容获取失败';
    } finally {
      this.isLoading = false;
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
          .backgroundColor('#007DFF')
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
                .backgroundColor(this.selectedSourceName === name ? '#007DFF' : this.glassCardColor())
                .backgroundBlurStyle(this.selectedSourceName === name ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
                .borderRadius(18)
                .border({ width: this.selectedSourceName === name ? 0 : 1, color: this.glassBorderColor() })
                .onClick(() => {
                  this.selectedSourceName = name;
                  this.selectedIndex = 0;
                  this.loadBooks();
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
                .backgroundColor(this.selectedIndex === index ? '#007DFF' : this.glassCardColor())
                .backgroundBlurStyle(this.selectedIndex === index ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
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
        Text(this.status)
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
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
        List({ space: 8 }) {
          ForEach(this.books, (book: SearchBook) => {
            ListItem() {
              Row() {
                Column() {
                  Text(book.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.primaryTextColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(book.author || '作者未知')
                    .fontSize(14)
                    .fontColor(this.secondaryTextColor())
                    .margin({ top: 4 })

                  Text(`${book.originName}${book.kind ? ' · ' + book.kind : ''}`)
                    .fontSize(12)
                    .fontColor(this.subTextColor())
                    .margin({ top: 4 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button(this.isSearchBookInShelf(book) ? '移除' : '加入')
                  .height(32)
                  .fontSize(13)
                  .borderRadius(16)
                  .backgroundColor(this.isSearchBookInShelf(book) ? '#E53935' : '#007DFF')
                  .fontColor('#FFFFFF')
                  .margin({ left: 12 })
                  .onClick(() => {
                    this.toggleSearchBookShelf(book);
                  })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.glassCardColor())
              .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
              .borderRadius(8)
              .border({ width: 1, color: this.glassBorderColor() })
              .shadow({ radius: 10, color: this.glassShadowColor(), offsetX: 0, offsetY: 4 })
              .onClick(() => {
                this.openSearchBookDetail(book);
              })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 12 })
        .backgroundColor(this.pageColor())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      } else {
        Column() {
          Text('没有发现内容')
            .fontSize(16)
            .fontColor(this.subTextColor())
          Text('请导入带 exploreUrl 的书源，或在书源编辑中补充发现地址')
            .fontSize(14)
            .fontColor(this.subTextColor())
            .margin({ top: 8 })
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32 })
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
        wordCount: book.wordCount
      }
    });
  }

  async addSearchBookToShelf(searchBook: SearchBook): Promise<void> {
    if (!searchBook.bookUrl) {
      promptAction.showToast({ message: '书籍地址为空' });
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const existing = await db.getBook(searchBook.bookUrl);
      if (existing) {
        this.markSearchBookInShelf(searchBook.bookUrl);
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        promptAction.showToast({ message: '已在书架' });
        return;
      }

      const book = new Book();
      book.bookUrl = searchBook.bookUrl;
      book.tocUrl = searchBook.tocUrl;
      book.origin = searchBook.origin;
      book.originName = searchBook.originName;
      book.name = searchBook.name;
      book.author = searchBook.author;
      book.kind = searchBook.kind;
      book.coverUrl = searchBook.coverUrl;
      book.intro = searchBook.intro;
      book.latestChapterTitle = searchBook.latestChapterTitle;
      book.wordCount = searchBook.wordCount;
      book.variable = searchBook.variable;
      book.group = -2147483645;
      book.type = 0;
      book.canUpdate = true;
      book.lastCheckTime = Date.now();
      book.latestChapterTime = Date.now();

      const source = book.origin ? await db.getBookSource(book.origin) : null;
      if (source) {
        const service = new WebBookService();
        const fullBook = await service.getBookInfo(source, book);
        book.tocUrl = fullBook.tocUrl;
        book.name = fullBook.name;
        book.author = fullBook.author;
        book.kind = fullBook.kind;
        book.coverUrl = fullBook.coverUrl;
        book.intro = fullBook.intro;
        book.latestChapterTitle = fullBook.latestChapterTitle;
        book.wordCount = fullBook.wordCount;
        book.variable = fullBook.variable;
      }

      await db.insertBook(book);
      this.markSearchBookInShelf(book.bookUrl);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      promptAction.showToast({ message: '已加入书架' });
    } catch (e) {
      console.error('加入书架失败:', e);
      promptAction.showToast({ message: '加入书架失败' });
    }
  }

  async syncExploreShelfStatus(books: SearchBook[]): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const urls: string[] = [];
      for (const book of books) {
        if (book.bookUrl && await db.getBook(book.bookUrl)) {
          urls.push(book.bookUrl);
        }
      }
      this.shelfBookUrls = urls;
    } catch (e) {
      console.error('同步发现书架状态失败:', e);
    }
  }

  isSearchBookInShelf(book: SearchBook): boolean {
    return !!book.bookUrl && this.shelfBookUrls.includes(book.bookUrl);
  }

  async toggleSearchBookShelf(searchBook: SearchBook): Promise<void> {
    if (this.isSearchBookInShelf(searchBook)) {
      await this.removeSearchBookFromShelf(searchBook);
    } else {
      await this.addSearchBookToShelf(searchBook);
    }
  }

  async removeSearchBookFromShelf(searchBook: SearchBook): Promise<void> {
    if (!searchBook.bookUrl) {
      promptAction.showToast({ message: '书籍地址为空' });
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBook(searchBook.bookUrl);
      this.shelfBookUrls = this.shelfBookUrls.filter(url => url !== searchBook.bookUrl);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      promptAction.showToast({ message: '已移出书架' });
    } catch (e) {
      console.error('移出书架失败:', e);
      promptAction.showToast({ message: '移出书架失败' });
    }
  }

  markSearchBookInShelf(bookUrl: string): void {
    if (bookUrl && !this.shelfBookUrls.includes(bookUrl)) {
      this.shelfBookUrls = [...this.shelfBookUrls, bookUrl];
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

  getActiveEntries(): ExploreEntry[] {
    if (!this.selectedSourceName) return this.entries;
    return this.entries.filter(entry => entry.sourceName === this.selectedSourceName);
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  glassCardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#38FFFFFF';
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#00000000' : '#99FFFFFF';
  }

  glassShadowColor(): string {
    return this.appDarkMode ? '#00000000' : '#10000000';
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
}

@Component
struct SearchPage {
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @State keyword: string = '';
  @State searchResults: SearchBook[] = [];
  @State shelfBookUrls: string[] = [];
  @State isSearching: boolean = false;
  @State showResult: boolean = false;
  @State statusMessage: string = '';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  private coordinator: SearchCoordinator | null = null;

  aboutToAppear() {
    this.initPage();
  }

  async initPage() {
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
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
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
          .backgroundColor(this.isSearching ? '#E53935' : '#007DFF')
          .onClick(() => {
            if (this.isSearching) {
              this.coordinator?.cancel();
              this.isSearching = false;
              this.statusMessage = '搜索已停止';
            } else {
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
        List({ space: 8 }) {
          ForEach(this.searchResults, (book: SearchBook) => {
            ListItem() {
              Row() {
                Column() {
                  Text(book.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.primaryTextColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(book.author || '作者未知')
                    .fontSize(14)
                    .fontColor(this.secondaryTextColor())
                    .margin({ top: 4 })

                  Text(book.originName)
                    .fontSize(12)
                    .fontColor(this.subTextColor())
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button(this.isSearchBookInShelf(book) ? '移除' : '加入')
                  .height(32)
                  .fontSize(13)
                  .borderRadius(16)
                  .backgroundColor(this.isSearchBookInShelf(book) ? '#E53935' : '#007DFF')
                  .fontColor('#FFFFFF')
                  .margin({ left: 12 })
                  .onClick(() => {
                    this.toggleSearchBookShelf(book);
                  })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.glassCardColor())
              .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
              .borderRadius(8)
              .border({ width: 1, color: this.glassBorderColor() })
              .shadow({ radius: 10, color: this.glassShadowColor(), offsetX: 0, offsetY: 4 })
              .onClick(() => {
                this.openSearchBookDetail(book);
              })
            }
          })

          if (this.isSearching) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                Text('继续搜索中...')
                  .fontSize(13)
                  .fontColor(this.subTextColor())
                  .margin({ left: 8 })
              }
              .width('100%')
              .height(44)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 12 })
        .backgroundColor(this.pageColor())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
        this.syncSearchShelfStatus(p.results);
        if (p.finished) {
          this.isSearching = false;
        }
      };

      this.coordinator = new SearchCoordinator(4);
      await this.coordinator.search(keyword, callback);
      await db.saveSearchKeyword(keyword);
    } catch (e) {
      console.error('搜索失败:', e);
      this.isSearching = false;
      this.statusMessage = '搜索失败';
    }
  }

  async syncSearchShelfStatus(books: SearchBook[]): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const urls: string[] = [];
      for (const book of books) {
        if (book.bookUrl && await db.getBook(book.bookUrl)) {
          urls.push(book.bookUrl);
        }
      }
      this.shelfBookUrls = urls;
    } catch (e) {
      console.error('同步搜索书架状态失败:', e);
    }
  }

  isSearchBookInShelf(book: SearchBook): boolean {
    return !!book.bookUrl && this.shelfBookUrls.includes(book.bookUrl);
  }

  async toggleSearchBookShelf(searchBook: SearchBook): Promise<void> {
    if (this.isSearchBookInShelf(searchBook)) {
      await this.removeSearchBookFromShelf(searchBook);
    } else {
      await this.addSearchBookToShelf(searchBook);
    }
  }

  async addSearchBookToShelf(searchBook: SearchBook): Promise<void> {
    if (!searchBook.bookUrl) {
      promptAction.showToast({ message: '书籍地址为空' });
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const existing = await db.getBook(searchBook.bookUrl);
      if (existing) {
        this.markSearchBookInShelf(searchBook.bookUrl);
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        promptAction.showToast({ message: '已在书架' });
        return;
      }

      const book = new Book();
      book.bookUrl = searchBook.bookUrl;
      book.tocUrl = searchBook.tocUrl;
      book.origin = searchBook.origin;
      book.originName = searchBook.originName;
      book.name = searchBook.name;
      book.author = searchBook.author;
      book.kind = searchBook.kind;
      book.coverUrl = searchBook.coverUrl;
      book.intro = searchBook.intro;
      book.latestChapterTitle = searchBook.latestChapterTitle;
      book.wordCount = searchBook.wordCount;
      book.variable = searchBook.variable;
      book.group = -2147483645;
      book.type = 0;
      book.canUpdate = true;
      book.lastCheckTime = Date.now();
      book.latestChapterTime = Date.now();

      const source = book.origin ? await db.getBookSource(book.origin) : null;
      if (source) {
        const service = new WebBookService();
        const fullBook = await service.getBookInfo(source, book);
        book.tocUrl = fullBook.tocUrl;
        book.name = fullBook.name;
        book.author = fullBook.author;
        book.kind = fullBook.kind;
        book.coverUrl = fullBook.coverUrl;
        book.intro = fullBook.intro;
        book.latestChapterTitle = fullBook.latestChapterTitle;
        book.wordCount = fullBook.wordCount;
        book.variable = fullBook.variable;
      }

      await db.insertBook(book);
      this.markSearchBookInShelf(book.bookUrl);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      promptAction.showToast({ message: '已加入书架' });
    } catch (e) {
      console.error('加入书架失败:', e);
      promptAction.showToast({ message: '加入书架失败' });
    }
  }

  async removeSearchBookFromShelf(searchBook: SearchBook): Promise<void> {
    if (!searchBook.bookUrl) {
      promptAction.showToast({ message: '书籍地址为空' });
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBook(searchBook.bookUrl);
      this.shelfBookUrls = this.shelfBookUrls.filter(url => url !== searchBook.bookUrl);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      promptAction.showToast({ message: '已移出书架' });
    } catch (e) {
      console.error('移出书架失败:', e);
      promptAction.showToast({ message: '移出书架失败' });
    }
  }

  markSearchBookInShelf(bookUrl: string): void {
    if (bookUrl && !this.shelfBookUrls.includes(bookUrl)) {
      this.shelfBookUrls = [...this.shelfBookUrls, bookUrl];
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
        wordCount: book.wordCount
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
    return this.appDarkMode ? '#191B1F' : '#38FFFFFF';
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#00000000' : '#99FFFFFF';
  }

  glassShadowColor(): string {
    return this.appDarkMode ? '#00000000' : '#10000000';
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
}

@Component
struct SettingsPage {
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;

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
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
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
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
          .border({ width: 1, color: this.glassBorderColor() })
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
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
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
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
    return this.appDarkMode ? '#191B1F' : '#38FFFFFF';
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#00000000' : '#99FFFFFF';
  }
}
