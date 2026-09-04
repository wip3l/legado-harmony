import { Book, SearchBook } from '../../model/data/Book';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { BookDisplayHelper } from '../../utils/BookDisplayHelper';
import { CoverGallerySettings } from '../../utils/CoverGallerySettings';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';

export type SearchBookAction = (book: SearchBook) => void;

class SearchBookResultDataSource implements IDataSource {
  private books: SearchBook[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.books.length; }

  getData(index: number): SearchBook { return this.books[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(books: SearchBook[]): void {
    this.books = books.slice();
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

@Component
export struct SearchBookResultList {
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('bookshelfCoverAlbums') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverMode') bookshelfCoverMode: string = 'sequence';
  @Prop @Watch('onBooksChanged') books: SearchBook[] = [];
  @Prop shelfBookKeys: string[] = [];
  @Prop busyBookKeys: string[] = [];
  @Prop showLoadingMore: boolean = false;
  @Prop showKind: boolean = false;
  @Prop showResultCover: boolean = true;
  @Prop useBookshelfCoverGallery: boolean = false;
  @Prop showResultTags: boolean = true;
  @Prop showSourceLine: boolean = true;
  @Prop pageColor: string = '#F5F5F5';
  @Prop cardColor: string = '#FFFFFF';
  @Prop itemBorderColor: string = '#00000000';
  @Prop itemBorderWidth: number = 0;
  @Prop shadowColor: string = '#00000000';
  @Prop primaryTextColor: string = '#1F1F1F';
  @Prop secondaryTextColor: string = '#666666';
  @Prop subTextColor: string = '#999999';
  @Prop topPadding: number = 0;
  @Prop bottomPadding: number = 12;
  scroller: ListScroller = new ListScroller();
  private dataSource: SearchBookResultDataSource = new SearchBookResultDataSource();
  private tagCache: Map<string, string[]> = new Map<string, string[]>();
  private coverCache: Map<string, string> = new Map<string, string>();
  onOpenBook: SearchBookAction = (_book: SearchBook) => {};
  onReadBook: SearchBookAction = (_book: SearchBook) => {};
  onToggleShelf: SearchBookAction = (_book: SearchBook) => {};
  onNeedMetadata: SearchBookAction = (_book: SearchBook) => {};
  onReachEnd: () => void = () => {};

  aboutToAppear(): void {
    this.onBooksChanged();
  }

  onBooksChanged(): void {
    this.dataSource.replace(this.books);
    this.tagCache.clear();
    this.coverCache.clear();
  }

  build() {
    List({ scroller: this.scroller, space: 8 }) {
      if (this.topPadding > 0) {
        ListItem() {
          Row()
            .height(this.topPadding)
        }
      }

      LazyForEach(this.dataSource, (book: SearchBook) => {
        this.searchResultItem(book)
      }, (book: SearchBook) => this.itemKey(book))

      if (this.showLoadingMore) {
        ListItem() {
          Row() {
            LoadingProgress()
              .width(20)
              .height(20)
            Text('继续加载中...')
              .fontSize(13)
              .fontColor(this.subTextColor)
              .margin({ left: 8 })
          }
          .width('100%')
          .height(44)
          .justifyContent(FlexAlign.Center)
        }
      }

      ListItem() {
        Column()
          .height(this.bottomPadding)
      }
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.pageColor)
    .scrollBar(BarState.Auto)
    .onReachEnd(() => {
      this.onReachEnd();
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  private supportsHdsListItem(): boolean {
    return deviceInfo.sdkApiVersion >= 26;
  }

  @Builder
  searchResultItem(book: SearchBook) {
    if (this.supportsHdsListItem()) {
      HdsListItem({
        customItemBuilder: () => {
          this.searchResultCard(book)
        },
        // 聚合项只是进入同名结果页，不能直接执行某个来源书籍的操作。
        swipeActionOptions: book.aggregationCount > 1 ? undefined : this.searchResultSwipeActions(book)
      })
    } else {
      // API 25 及以下保留原生 ListItem，避免加载 HDS 滑动容器。
      ListItem() {
        this.searchResultCard(book)
      }
    }
  }

  @Builder
  searchResultCard(book: SearchBook) {
    Row() {
      if (this.showResultCover) {
        this.coverView(book)
      }

      Column() {
        Text(this.safeText(book.name, '未知书名'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.safeText(book.author, '作者未知'))
          .fontSize(14)
          .fontColor(this.secondaryTextColor)
          .margin({ top: 4 })

        if (this.showResultTags && this.getTags(book).length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.getTags(book), (tag: string, index: number) => {
              this.tagChip(tag, index)
            })
          }
          .width('100%')
          .margin({ top: 7 })
        }

        if (this.metadataLine(book)) {
          Text(this.metadataLine(book))
            .fontSize(12)
            .fontColor(this.subTextColor)
            .margin({ top: 3 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (this.showSourceLine) {
          Text(this.sourceLine(book))
            .fontSize(12)
            .fontColor(this.subTextColor)
            .margin({ top: this.showResultTags && this.getTags(book).length > 0 ? 6 : 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .margin({ left: this.showResultCover ? 12 : 0 })
      .alignItems(HorizontalAlign.Start)

      if (book.aggregationCount > 1) {
        this.aggregationIndicator(book)
      } else if (!this.supportsHdsListItem()) {
        // API 25 及以下没有 HDS 滑动容器，直接显示等价操作按钮。
        Column({ space: 6 }) {
          Button(SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys) ? '移出' : '加入')
            .fontSize(11)
            .width(64).height(32)
            .fontColor('#FFFFFF').backgroundColor(ThemeRuntime.buttonColor(this.isDarkMode()))
            .onClick(() => this.onToggleShelf(book))
          Button('阅读')
            .fontSize(11)
            .width(64).height(32)
            .fontColor('#FFFFFF').backgroundColor(ThemeRuntime.accentColor(this.isDarkMode()))
            .onClick(() => this.onReadBook(book))
        }
        .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.cardColor)
    .borderRadius(8)
    .border({ width: this.itemBorderWidth, color: this.itemBorderColor })
    .shadow({ radius: 10, color: this.shadowColor, offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.onOpenBook(book);
    })
    .onAppear(() => {
      if (book.aggregationCount <= 1 &&
        (!this.safeText(book.author, '') || (this.showResultCover && !this.safeText(book.coverUrl, '')))) {
        this.onNeedMetadata(book);
      }
    })
  }

  private searchResultSwipeActions(book: SearchBook): HdsSwipeActionOptions {
    const options: HdsSwipeActionOptions = {
      icons: [
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.bookshelf_badge_plus')),
          // 使用主题按钮色，随当前主题保持一致并确保图标有足够对比度。
          backgroundColor: ThemeRuntime.buttonColor(this.isDarkMode()),
          iconOptions: {
            accessibilityText: SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys) ? '移出书架' : '加入书架'
          },
          onAction: () => {
            this.onToggleShelf(book);
          }
        },
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.book')),
          backgroundColor: ThemeRuntime.accentColor(this.isDarkMode()),
          iconOptions: {
            accessibilityText: '阅读'
          },
          onAction: () => {
            this.onReadBook(book);
          }
        }
      ]
    };
    return options;
  }

  @Builder
  aggregationIndicator(book: SearchBook) {
    Column({ space: 3 }) {
      Text(`${book.aggregationCount}`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
      Text('结果')
        .fontSize(11)
        .fontColor(this.subTextColor)
    }
    .width(64)
    .height(44)
    .margin({ left: 12 })
    .justifyContent(FlexAlign.Center)
  }


  sourceLine(book: SearchBook): string {
    if (book.aggregationCount > 1) {
      return `已聚合 ${book.aggregationCount} 个同名结果，点击展开`;
    }
    return this.safeText(book.originName, '');
  }

  getTags(book: SearchBook): string[] {
    if (!this.showResultTags) {
      return [];
    }
    const key = `${this.itemKey(book)}\n${book.kind || ''}\n${book.status || ''}`;
    const cached = this.tagCache.get(key);
    if (cached) return cached;
    const tags = BookDisplayHelper.splitTags(this.safeText(book.kind, ''), this.safeText(book.status, ''));
    this.tagCache.set(key, tags);
    return tags;
  }

  @Builder
  tagChip(tag: string, index: number) {
    Text(tag)
      .fontSize(11)
      .fontColor(BookDisplayHelper.getTagTextColor(index, this.isDarkMode()))
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(BookDisplayHelper.getTagBackgroundColor(index, this.isDarkMode()))
      .borderRadius(10)
      .margin({ right: 6, bottom: 4 })
  }

  @Builder
  coverView(book: SearchBook) {
    Stack() {
      Column() {
        Text(this.safeText(book.name, '书').substring(0, 1))
          .fontSize(22)
          .fontColor('#FFFFFF')
      }
      .width(54)
      .height(72)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.accentColor())

      if (this.displayCover(book)) {
        Image(this.displayCover(book))
          .width(54)
          .height(72)
          .objectFit(ImageFit.Cover)
      }
    }
    .width(54)
    .height(72)
    .borderRadius(6)
    .clip(true)
    .backgroundColor(this.subTextColor)
  }

  isDarkMode(): boolean {
    return this.pageColor === '#101113' || this.cardColor === '#191B1F';
  }

  accentColor(): string {
    return this.isDarkMode() ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  displayCover(book: SearchBook): string {
    const key = `${this.itemKey(book)}\n${book.coverUrl || ''}`;
    const cached = this.coverCache.get(key);
    if (cached !== undefined) return cached;
    let result = '';
    if (this.useBookshelfCoverGallery) {
      const galleryCover = this.bookshelfGalleryCover(book);
      if (galleryCover) {
        result = galleryCover;
      }
    }
    if (!result) result = this.safeText(book.coverUrl, '');
    this.coverCache.set(key, result);
    return result;
  }

  metadataLine(book: SearchBook): string {
    const parts: string[] = [];
    if (this.safeText(book.wordCount, '')) parts.push(`字数：${this.safeText(book.wordCount, '')}`);
    if (this.safeText(book.latestChapterTitle, '')) parts.push(`最新：${this.safeText(book.latestChapterTitle, '')}`);
    if (this.safeText(book.updateTime, '')) parts.push(`更新：${this.safeText(book.updateTime, '')}`);
    return parts.join(' · ');
  }

  bookshelfGalleryCover(searchBook: SearchBook): string {
    const book = new Book();
    book.name = this.safeText(searchBook.name, '');
    book.author = this.safeText(searchBook.author, '');
    book.bookUrl = this.safeText(searchBook.bookUrl, '');
    book.coverUrl = this.safeText(searchBook.coverUrl, '');
    const covers = CoverGallerySettings.getDisplayCoverList(
      book,
      this.isDarkMode(),
      this.bookshelfCoverAlbums,
      this.bookshelfLightCoverAlbumId,
      this.bookshelfDarkCoverAlbumId,
      'all',
      '',
      true,
      this.bookshelfCoverMode
    );
    return BookDisplayHelper.pickCover(covers);
  }

  itemKey(book: SearchBook): string {
    if (book.aggregationCount > 1 && book.aggregationKey) {
      // LazyForEach reuses a child when its key is unchanged. Search results arrive incrementally,
      // so include the current member count to rebuild the card when a group grows.
      return `aggregation:${book.aggregationKey}:${book.aggregationCount}`;
    }
    const key = SearchBookShelfHelper.keyOf(book);
    return `${key || this.safeText(book.bookUrl, '')}|${this.safeText(book.originName, '')}|${this.safeText(book.name, '')}`;
  }

  safeText(value: string, fallback: string): string {
    const text = (value || '').trim();
    return text || fallback;
  }
}
