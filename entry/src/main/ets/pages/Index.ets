import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { Book, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchCoordinator, SearchCallback, SearchProgress } from '../core/book/SearchCoordinator';
import { ExploreCoordinator, ExploreEntry } from '../core/book/ExploreCoordinator';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.currentIndex === 0) {
        BookshelfPage()
      }
      if (this.currentIndex === 1) {
        ExplorePage()
      }
      if (this.currentIndex === 2) {
        SearchPage()
      }
      if (this.currentIndex === 3) {
        SettingsPage()
      }

      Row() {
        this.tabBarBuilder('书架', 0, '📖')
        this.tabBarBuilder('发现', 1, '🌐')
        this.tabBarBuilder('搜索', 2, '🔍')
        this.tabBarBuilder('我的', 3, '👤')
      }
      .width('88%')
      .height(64)
      .margin({ bottom: Math.max(this.navBarHeight + 8, 16) })
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .borderRadius(32)
      .clip(true)
      .backgroundEffect({
        radius: 28,
        saturation: 1.2,
        brightness: this.appDarkMode ? 0.9 : 1.08,
        color: this.tabBarMaterialColor(),
        adaptiveColor: AdaptiveColor.DEFAULT,
        blurOptions: { grayscale: [0, 0] },
        policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
        inactiveColor: this.tabBarMaterialColor()
      }, { disableSystemAdaptation: false })
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, {
        colorMode: ThemeColorMode.SYSTEM,
        adaptiveColor: AdaptiveColor.DEFAULT,
        scale: 0.85,
        policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
        blurOptions: { grayscale: [0, 0] }
      }, { disableSystemAdaptation: false })
      .backgroundColor(this.tabBarFallbackColor())
      .border({ width: 0.8, color: this.tabBarBorderColor() })
      .shadow({ radius: 24, color: this.appDarkMode ? '#66000000' : '#24000000', offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.appDarkMode ? '#101113' : '#F5F5F5')
  }

  @Builder
  tabBarBuilder(title: string, index: number, icon: string) {
    Column() {
      Text(icon)
        .fontSize(22)
        .margin({ bottom: 2 })
      Text(title)
        .fontSize(11)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? this.tabBarActiveColor() : this.tabBarTextColor())
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius(28)
    .backgroundColor(this.currentIndex === index ? this.tabBarActiveBackgroundColor() : Color.Transparent)
    .onClick(() => {
      this.currentIndex = index;
    })
  }

  tabBarMaterialColor(): string {
    return this.appDarkMode ? '#A81B1D22' : '#B8FFFFFF';
  }

  tabBarFallbackColor(): string {
    return this.appDarkMode ? '#731B1D22' : '#80FFFFFF';
  }

  tabBarBorderColor(): string {
    return this.appDarkMode ? '#33FFFFFF' : '#99FFFFFF';
  }

  tabBarActiveColor(): string {
    return this.appDarkMode ? '#68D6C3' : '#007DFF';
  }

  tabBarTextColor(): string {
    return this.appDarkMode ? '#E7E9ED' : '#5F6670';
  }

  tabBarActiveBackgroundColor(): string {
    return this.appDarkMode ? '#2B68D6C3' : '#24007DFF';
  }
}

@Component
struct BookshelfPage {
  @Prop statusBarHeight: number = 0;
  @State books: Book[] = [];
  @State isLoading: boolean = false;
  @State showDeleteDialog: boolean = false;
  @State pendingDeleteBook: Book | null = null;
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
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
      this.books = await db.getAllBooks();
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
                          .fontColor('#007DFF')
                          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                          .backgroundColor('#E8F0FE')
                          .borderRadius(4)
                          .margin({ right: 8 })
                      }

                      Text(book.getUnreadChapterNum() > 0 ? `${book.getUnreadChapterNum()}章未读` : '已读完')
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
                .backgroundColor(this.cardColor())
                .borderRadius(8)
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
          .padding({ left: 16, right: 16, bottom: 96 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor())

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
              .fontColor('#555')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 20 })

            Row() {
              Button('取消')
                .width('45%')
                .height(44)
                .backgroundColor('#F5F5F5')
                .fontColor('#333')
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
          .backgroundColor('#FFFFFF')
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

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
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
  @State entries: ExploreEntry[] = [];
  @State sourceNames: string[] = [];
  @State selectedSourceName: string = '';
  @State selectedIndex: number = 0;
  @State books: SearchBook[] = [];
  @State isLoading: boolean = false;
  @State status: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  private coordinator: ExploreCoordinator = new ExploreCoordinator();

  aboutToAppear() {
    this.loadEntries();
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
                .backgroundColor(this.selectedSourceName === name ? '#007DFF' : this.cardColor())
                .borderRadius(18)
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
                .fontColor(this.selectedIndex === index ? '#007DFF' : this.secondaryTextColor())
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(this.selectedIndex === index ? (this.appDarkMode ? '#1C3558' : '#E8F0FE') : this.cardColor())
                .borderRadius(17)
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
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.cardColor())
              .borderRadius(8)
              .onClick(() => {
                this.openSearchBookDetail(book);
              })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 96 })
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
    .backgroundColor(this.pageColor())
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
  @State keyword: string = '';
  @State searchResults: SearchBook[] = [];
  @State isSearching: boolean = false;
  @State showResult: boolean = false;
  @State statusMessage: string = '';
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
          .backgroundColor(this.cardColor())
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
        Text(this.statusMessage)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .height(36)
          .textAlign(TextAlign.Center)
          .backgroundColor('#E8F5E9')
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
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.cardColor())
              .borderRadius(8)
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
        .padding({ left: 16, right: 16, bottom: 96 })
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
    .backgroundColor(this.pageColor())
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

      const callback: SearchCallback = (p: SearchProgress) => {
        this.searchResults = p.results;
        this.statusMessage = p.status;
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

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
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
struct SettingsPage {
  @Prop statusBarHeight: number = 0;
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
          .backgroundColor(this.appDarkMode ? '#191B1F' : '#FFFFFF')
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
          .backgroundColor(this.appDarkMode ? '#191B1F' : '#FFFFFF')
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
          .backgroundColor(this.appDarkMode ? '#191B1F' : '#FFFFFF')
          .onClick(() => {
            router.pushUrl({ url: 'pages/About' });
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.appDarkMode ? '#191B1F' : '#FFFFFF')
      .padding({ bottom: 96 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.appDarkMode ? '#101113' : '#F5F5F5')
  }
}
