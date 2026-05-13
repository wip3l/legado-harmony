import { router } from '@kit.ArkUI';
import { Book, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { promptAction } from '@kit.ArkUI';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { WebBookService } from '../core/book/WebBookService';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct SearchPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @State keyword: string = '';
  @State searchResults: SearchBook[] = [];
  @State shelfBookUrls: string[] = [];
  @State isSearching: boolean = false;
  @State searchHistory: string[] = [];
  @State hotKeywords: string[] = ['斗破苍穹', '完美世界', '遮天', '凡人修仙传', '诛仙'];
  @State showResult: boolean = false;
  @State statusMessage: string = '';

  aboutToAppear() {
    this.syncBars();
    this.initPage();
  }

  onPageShow(): void {
    this.syncBars();
  }

  async initPage() {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const keywords = await db.getSearchKeywords();
      this.searchHistory = keywords.map(k => k.keyword);
      console.log('页面初始化完成');
    } catch (e) {
      console.error('初始化失败:', e);
    }
  }

  build() {
    Column() {
      // 搜索栏
      Row() {
        TextInput({ placeholder: '搜索书籍', text: this.keyword })
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.keyword = value;
          })

        Button('搜索')
          .height(40)
          .margin({ left: 8 })
          .borderRadius(20)
          .onClick(() => {
            console.log('搜索按钮被点击, keyword:', this.keyword);
            promptAction.showToast({ message: `搜索: ${this.keyword}` });
            this.doSearch();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.pageColor())
      .alignItems(VerticalAlign.Center)

      // 状态消息
      if (this.statusMessage) {
        Text(this.statusMessage)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .height(36)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.statusMessageColor())
      }

      // 内容区域
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

                  Text(book.author)
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
        .padding({ left: 16, right: 16 })
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
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.showResult && this.searchResults.length === 0) {
        Column() {
          Text('未找到相关书籍')
            .fontSize(16)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 搜索历史和热门搜索
        Column() {
          if (this.searchHistory.length > 0) {
            Column() {
              Text('搜索历史')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .width('100%')

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.searchHistory, (keyword: string) => {
                  Text(keyword)
                    .fontSize(14)
                    .fontColor(this.secondaryTextColor())
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.cardColor())
                    .borderRadius(16)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.keyword = keyword;
                      this.doSearch();
                    })
                })
              }
              .width('100%')
              .margin({ top: 12 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.cardColor())
            .borderRadius(8)
            .margin({ left: 16, right: 16, top: 16 })
          }

          Column() {
            Text('热门搜索')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.hotKeywords, (keyword: string) => {
                Text(keyword)
                  .fontSize(14)
                  .fontColor(this.secondaryTextColor())
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.cardColor())
                  .borderRadius(16)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.keyword = keyword;
                    this.doSearch();
                  })
              })
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.cardColor())
          .borderRadius(8)
          .margin({ left: 16, right: 16, top: 16 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  async doSearch() {
    console.log('doSearch 方法被调用');

    if (!this.keyword || this.keyword.trim() === '') {
      promptAction.showToast({ message: '请输入搜索关键词' });
      return;
    }

    this.isSearching = true;
    this.showResult = true;
    this.statusMessage = '正在搜索...';
    this.searchResults = [];

    try {
      const db = AppDatabase.getInstance();
      const coordinator = new SearchCoordinator(6);
      const keyword = this.keyword.trim();
      const allBooks = await coordinator.search(keyword, (progress: SearchProgress) => {
        this.searchResults = progress.results;
        this.statusMessage = progress.status;
        this.syncSearchShelfStatus(progress.results);
        if (progress.finished) {
          this.isSearching = false;
        }
      });

      this.statusMessage = allBooks.length > 0 ? `搜索完成，共找到 ${allBooks.length} 本书` : '搜索完成，未找到相关书籍';
      console.log('搜索完成, 总结果:', allBooks.length);

      // 保存搜索历史
      await db.saveSearchKeyword(keyword);
      const keywords = await db.getSearchKeywords();
      this.searchHistory = keywords.map(k => k.keyword);
    } catch (e) {
      console.error('搜索失败:', e);
      this.statusMessage = '搜索失败';
    } finally {
      this.isSearching = false;
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

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F5F5F5';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  secondaryTextColor(): string {
    return this.appDarkMode ? '#C6CBD2' : '#666666';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#999999';
  }

  statusMessageColor(): string {
    return this.appDarkMode ? '#14251B' : '#E8F5E9';
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
