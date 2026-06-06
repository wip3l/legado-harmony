import { router } from '@kit.ArkUI';
import { SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { promptAction } from '@kit.ArkUI';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { SearchBookResultList } from '../components/book/SearchBookResultList';
import { syncSystemBars } from '../utils/SystemBars';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';

@Entry
@Component
struct SearchPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State keyword: string = '';
  @State searchResults: SearchBook[] = [];
  @State shelfBookKeys: string[] = [];
  @State addingShelfBookKeys: string[] = [];
  @State isSearching: boolean = false;
  @State searchHistory: string[] = [];
  @State hotKeywords: string[] = ['斗破苍穹', '完美世界', '遮天', '凡人修仙传', '诛仙'];
  @State showResult: boolean = false;
  @State statusMessage: string = '';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '';
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  private shelfStatusVersion: number = 0;

  aboutToAppear() {
    this.syncBars();
    this.initPage();
  }

  onPageShow(): void {
    this.syncBars();
    this.refreshSearchShelfStatus();
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
            this.hideKeyboard();
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

      // 内容区域
      if (this.showResult && this.searchResults.length > 0) {
        SearchBookResultList({
          books: this.searchResults,
          shelfBookKeys: this.shelfBookKeys,
          busyBookKeys: this.addingShelfBookKeys,
          showLoadingMore: this.isSearching,
          pageColor: this.pageColor(),
          cardColor: this.cardColor(),
          primaryTextColor: this.primaryTextColor(),
          secondaryTextColor: this.secondaryTextColor(),
          subTextColor: this.subTextColor(),
          bottomPadding: 0,
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
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
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
        this.verificationUrl = progress.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
        this.verificationTitle = progress.verificationTitle || AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
        this.syncSearchShelfStatus(progress.results);
        if (progress.finished) {
          this.isSearching = false;
        }
      });

      const verifyUrl = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
      this.statusMessage = verifyUrl ? `搜索完成，共找到 ${allBooks.length} 本书；有书源需要网页验证` :
        allBooks.length > 0 ? `搜索完成，共找到 ${allBooks.length} 本书` : '搜索完成，未找到相关书籍';
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
      this.syncSearchShelfStatus(this.searchResults);
    }
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
