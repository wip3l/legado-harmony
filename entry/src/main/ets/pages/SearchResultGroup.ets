import { promptAction, router } from '@kit.ArkUI';
import { SearchBook } from '../model/data/Book';
import { SearchBookResultList } from '../components/book/SearchBookResultList';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { SearchResultAggregationStore, SearchResultGroupSnapshot } from '../utils/SearchResultAggregationStore';
import { SearchBookShelfChange, SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct SearchResultGroupPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('searchExploreShowResultCover') showResultCover: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') useBookshelfCoverGallery: boolean = false;
  @StorageLink('searchExploreShowResultTags') showResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') promptAddToShelfOnBack: boolean = true;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State books: SearchBook[] = [];
  @State groupTitle: string = '同名书籍';
  @State shelfBookKeys: string[] = [];
  @State busyBookKeys: string[] = [];
  private token: string = '';
  private scroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.token = params['token'] || '';
    const snapshot = SearchResultAggregationStore.get(this.token);
    if (snapshot) this.applySnapshot(snapshot);
    else this.groupTitle = params['title'] || '同名书籍';
    this.syncBars();
    this.refreshShelfKeys();
  }

  onPageShow(): void {
    this.syncBars();
    this.refreshShelfKeys();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.books.length > 0) {
        SearchBookResultList({
          books: this.books,
          scroller: this.scroller,
          shelfBookKeys: this.shelfBookKeys,
          busyBookKeys: this.busyBookKeys,
          showResultCover: this.showResultCover,
          useBookshelfCoverGallery: this.useBookshelfCoverGallery,
          showResultTags: this.showResultTags,
          pageColor: this.pageColor(),
          cardColor: this.cardColor(),
          itemBorderColor: this.groupBorderColor(),
          itemBorderWidth: 1,
          shadowColor: '#00000000',
          primaryTextColor: this.primaryTextColor(),
          secondaryTextColor: this.subTextColor(),
          subTextColor: this.subTextColor(),
          topPadding: 56 + this.statusBarHeight,
          bottomPadding: 20 + this.navBarHeight,
          onOpenBook: (book: SearchBook) => this.openBook(book),
          onReadBook: (book: SearchBook) => this.readBook(book),
          onToggleShelf: (book: SearchBook) => this.toggleShelf(book)
        })
      } else {
        Column({ space: 10 }) {
          Text('聚合结果已失效，请返回重新搜索')
            .fontSize(15)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      Row() {
        ImmersiveBackButton({
          icon: $r('sys.symbol.chevron_left'),
          iconOffsetX: 0,
          iconColor: this.primaryTextColor(),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 48,
          containerHeight: 48,
          startInset: 0,
          materialScale: 0.83,
          accessibilityLabel: '返回',
          onBack: () => router.back()
        })

        Column({ space: 2 }) {
          Text(this.groupTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.books.length} 个同名结果`)
            .fontSize(11)
            .fontColor(this.subTextColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 4, right: 16, top: this.statusBarHeight })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
      .backdropBlur(ThemeRuntime.topBarBlur())
      .zIndex(2)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  applySnapshot(snapshot: SearchResultGroupSnapshot): void {
    this.groupTitle = snapshot.title || '同名书籍';
    this.books = snapshot.books.slice();
  }

  async refreshShelfKeys(): Promise<void> {
    try {
      this.shelfBookKeys = await SearchBookShelfHelper.syncShelfKeys(getContext(this), this.books);
    } catch (e) {
      console.warn('同步聚合搜索结果书架状态失败:', e);
    }
  }

  async toggleShelf(book: SearchBook): Promise<void> {
    const key = SearchBookShelfHelper.keyOf(book);
    if (!key || this.busyBookKeys.includes(key)) return;
    this.busyBookKeys = SearchBookShelfHelper.withAddedKey(this.busyBookKeys, key);
    try {
      let change: SearchBookShelfChange;
      if (SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys)) {
        change = await SearchBookShelfHelper.removeFromShelf(getContext(this), book);
        this.shelfBookKeys = SearchBookShelfHelper.withoutKey(this.shelfBookKeys, change.requestKey);
      } else {
        change = await SearchBookShelfHelper.addToShelf(getContext(this), book);
        this.shelfBookKeys = SearchBookShelfHelper.withAddedKey(
          this.shelfBookKeys, change.shelfKey || change.requestKey);
      }
    } catch (e) {
      console.error('更新聚合搜索结果书架状态失败:', e);
      promptAction.showToast({ message: '操作失败' });
    } finally {
      this.busyBookKeys = SearchBookShelfHelper.withoutKey(this.busyBookKeys, key);
    }
  }

  async readBook(book: SearchBook): Promise<void> {
    const key = SearchBookShelfHelper.keyOf(book);
    if (!key || this.busyBookKeys.includes(key)) return;
    if (!SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys)) {
      this.busyBookKeys = SearchBookShelfHelper.withAddedKey(this.busyBookKeys, key);
      try {
        const change = await SearchBookShelfHelper.addToShelf(getContext(this), book);
        this.shelfBookKeys = SearchBookShelfHelper.withAddedKey(
          this.shelfBookKeys, change.shelfKey || change.requestKey);
      } catch (e) {
        console.error('准备阅读书籍失败:', e);
        promptAction.showToast({ message: '书籍准备失败，请稍后重试' });
        return;
      } finally {
        this.busyBookKeys = SearchBookShelfHelper.withoutKey(this.busyBookKeys, key);
      }
    }
    const shelfBook = await SearchBookShelfHelper.findShelfBookByKey(key, true);
    if (!shelfBook?.bookUrl) {
      promptAction.showToast({ message: '书籍准备失败，请稍后重试' });
      return;
    }
    router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: shelfBook.bookUrl } });
  }

  openBook(book: SearchBook): void {
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
        status: book.status,
        coverUrl: book.coverUrl,
        intro: book.intro,
        latestChapterTitle: book.latestChapterTitle,
        wordCount: book.wordCount,
        updateTime: book.updateTime,
        type: String(book.type || 0),
        variable: book.variable || '',
        promptAddToShelfOnBack: this.promptAddToShelfOnBack ? 'true' : 'false'
      }
    });
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  groupBorderColor(): string { return this.appDarkMode ? '#262A31' : '#FFFFFF'; }
}
