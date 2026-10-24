import { SearchBook, BookTypeSupport } from '@legado/sourceengine';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { BookDisplayHelper } from '../../utils/BookDisplayHelper';
import { BookCover } from './BookCover';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { CoverBackdropCard } from './CoverBackdropCard';

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
  /** 平铺时每列封面的最小、最大宽度，列数由可用宽度按最小列宽算出。 */
  static readonly GRID_MIN_ITEM_WIDTH: number = 100;
  static readonly GRID_MAX_ITEM_WIDTH: number = 150;
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @Prop @Watch('onBooksChanged') books: SearchBook[] = [];
  @Prop @Watch('onShelfBookKeysChanged') shelfBookKeys: string[] = [];
  @Prop busyBookKeys: string[] = [];
  @Prop showLoadingMore: boolean = false;
  @Prop showKind: boolean = false;
  @Prop showResultCover: boolean = true;
  @Prop showResultCoverBackground: boolean = true;
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
  /** 'list' 为卡片列表，'grid' 为封面平铺（列数随宽度自适应）。 */
  @Prop layoutMode: string = 'list';
  /** 分类翻页的顶栏只响应真实纵向滚动，忽略新页布局、回顶等产生的空闲滚动回调。 */
  @Prop userScrollOnly: boolean = false;
  private gridUserScrolled: boolean = false;
  scroller: ListScroller = new ListScroller();
  private dataSource: SearchBookResultDataSource = new SearchBookResultDataSource();
  private tagCache: Map<string, string[]> = new Map<string, string[]>();
  /** 只对当前已加载的封面显示氛围背景，轮播切图时同步更新。 */
  @State readyCoverUrls: Map<string, ResourceStr> = new Map();
  onOpenBook: SearchBookAction = (_book: SearchBook) => {};
  onReadBook: SearchBookAction = (_book: SearchBook) => {};
  onToggleShelf: SearchBookAction = (_book: SearchBook) => {};
  onNeedMetadata: SearchBookAction = (_book: SearchBook) => {};
  onReachEnd: () => void = () => {};
  /** 列表滚动：本次位移和当前滚动距离，首页据此收起或展开标题行。 */
  onListScroll: (delta: number, offset: number) => void = (_delta: number, _offset: number) => {};
  onListScrollStop: (offset: number) => void = (_offset: number) => {};

  aboutToAppear(): void {
    this.onBooksChanged();
  }

  onBooksChanged(): void {
    this.dataSource.replace(this.books);
    this.tagCache.clear();
    const keys = new Set(this.books.map((book: SearchBook): string => this.itemKey(book)));
    this.readyCoverUrls.forEach((_url: ResourceStr, key: string): void => {
      if (!keys.has(key)) this.readyCoverUrls.delete(key);
    });
  }

  onShelfBookKeysChanged(): void {
    // HdsListItem caches its swipe action options when the item is created.
    // Rebuild the data source when shelf membership changes so the action icon
    // and accessibility label are regenerated from the current state.
    this.dataSource.replace(this.books);
  }

  build() {
    if (this.layoutMode === 'grid') {
      this.resultGrid()
    } else {
      this.resultList()
    }
  }

  /** 封面平铺：多列 List 保留懒加载，列数随宽度自适应；顶部留白与底部加载提示放在分组页眉页脚里，不占格子。 */
  @Builder
  resultGrid() {
    List({ scroller: this.scroller }) {
      ListItemGroup({ header: this.gridHeader(), footer: this.gridFooter(), space: AppSpacing.LG }) {
        LazyForEach(this.dataSource, (book: SearchBook) => {
          ListItem() {
            this.searchResultGridItem(book)
          }
        }, (book: SearchBook) => `grid_${this.listItemKey(book)}`)
      }
    }
    // 按可用宽度自动算列数：竖屏手机约 3 列，横屏、平板、电脑宽窗口随宽度增加，窗口缩放时实时调整。
    .lanes({ minLength: SearchBookResultList.GRID_MIN_ITEM_WIDTH, maxLength: SearchBookResultList.GRID_MAX_ITEM_WIDTH },
      AppSpacing.MD)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(this.pageColor)
    .scrollBar(BarState.Auto)
    .onReachEnd(() => {
      this.onReachEnd();
    })
    .onDidScroll((delta: number, state: ScrollState) => {
      if (this.userScrollOnly && (state === ScrollState.Idle || delta === 0)) return;
      this.gridUserScrolled = true;
      this.onListScroll(delta, this.scroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      if (this.userScrollOnly && !this.gridUserScrolled) return;
      this.gridUserScrolled = false;
      this.onListScrollStop(this.scroller.currentOffset().yOffset);
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  gridHeader() {
    Row()
      .width('100%')
      .height(this.topPadding + AppSpacing.XS)
  }

  @Builder
  gridFooter() {
    Column() {
      if (this.showLoadingMore) {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)
          Text('继续加载中...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor)
            .margin({ left: AppSpacing.MD })
        }
        .width('100%')
        .height(44)
        .justifyContent(FlexAlign.Center)
      }
      Column()
        .height(this.bottomPadding)
    }
    .width('100%')
  }

  @Builder
  searchResultGridItem(book: SearchBook) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Stack() {
          Column() {
            Text(this.safeText(book.name, '书').substring(0, 1))
              .fontSize(AppFontSize.HEADLINE)
              .fontColor(this.showResultCover && this.backdropCover(book) ? this.secondaryTextColor : '#FFFFFF')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          // 有封面时使用中性底色，避免圆角抗锯齿边缘透出主题色。
          .backgroundColor(this.showResultCover && this.backdropCover(book) ? this.cardColor : this.accentColor())

          if (this.showResultCover) {
            this.resultCover(book, 8, 360, 480)
          }
        }
        .width('100%')
        .aspectRatio(0.75)
        .borderRadius(8)
        .clip(true)

        if (book.aggregationCount > 1) {
          Text(`${book.aggregationCount} 个结果`)
            .fontSize(AppFontSize.MICRO)
            .fontColor('#FFFFFF')
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
            .backgroundColor('#99000000')
            .borderRadius(8)
            .margin({ top: AppSpacing.XS, right: AppSpacing.XS })
        } else if (this.mediaBadge(book)) {
          Text(this.mediaBadge(book))
            .fontSize(AppFontSize.MICRO)
            .fontColor('#FFFFFF')
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
            .backgroundColor(this.accentColor())
            .borderRadius(8)
            .margin({ top: AppSpacing.XS, right: AppSpacing.XS })
        }
      }
      .width('100%')
      // 阴影与内层裁切使用相同圆角；外层不裁切，以保留圆角外的柔和阴影。
      .borderRadius(8)
      .backgroundColor(this.cardColor)
      .shadow({ radius: 8, color: this.isDarkMode() ? '#55000000' : '#22000000', offsetX: 0, offsetY: 3 })

      Text(this.safeText(book.name, '未知书名'))
        .fontSize(AppFontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: AppSpacing.XS })
      Text(this.safeText(book.author, '作者未知'))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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

  @Builder
  resultList() {
    List({ scroller: this.scroller, space: AppSpacing.MD }) {
      if (this.topPadding > 0) {
        ListItem() {
          Row()
            .height(this.topPadding)
        }
      }

      LazyForEach(this.dataSource, (book: SearchBook) => {
        this.searchResultItem(book)
      }, (book: SearchBook) => this.listItemKey(book))

      if (this.showLoadingMore) {
        ListItem() {
          Row() {
            LoadingProgress()
              .width(20)
              .height(20)
            Text('继续加载中...')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor)
              .margin({ left: AppSpacing.MD })
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
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(this.pageColor)
    .scrollBar(BarState.Auto)
    .onReachEnd(() => {
      this.onReachEnd();
    })
    .onDidScroll((delta: number) => {
      this.onListScroll(delta, this.scroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      this.onListScrollStop(this.scroller.currentOffset().yOffset);
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
      .swipeAction(book.aggregationCount > 1 ? {} : {
        end: {
          builder: () => {
            this.searchResultFallbackSwipeActions(book)
          },
          actionAreaDistance: 128,
          onAction: () => this.onReadBook(book)
        },
        edgeEffect: SwipeEdgeEffect.Spring
      })
    }
  }

  @Builder
  searchResultCard(book: SearchBook) {
    // 尾随闭包形式的自定义组件后面不能再接属性，圆角、边框、点击等挂在外层 Column 上。
    Column() {
      CoverBackdropCard({
        cover: this.showResultCover && this.showResultCoverBackground ? this.backdropCover(book) : '',
        showBackdrop: this.showResultCoverBackground,
        accentColor: this.accentColor(),
        cardColor: this.cardColor,
        darkMode: this.isDarkMode()
      }) {
        Row() {
          if (this.showResultCover) {
            this.coverView(book)
          }

          Column() {
            Row({ space: AppSpacing.SM }) {
              Text(this.safeText(book.name, '未知书名'))
                .fontSize(AppFontSize.BODY_LARGE)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)

              if (this.mediaBadge(book)) {
                Text(this.mediaBadge(book))
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(this.accentColor())
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 1, bottom: 1 })
                  .border({ width: 1, color: this.accentColor() })
                  .borderRadius(ThemeRuntime.mediumRadius())
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Text(this.safeText(book.author, '作者未知'))
              .fontSize(AppFontSize.BODY)
              .fontColor(this.secondaryTextColor)
              .margin({ top: AppSpacing.XS })

            if (this.showResultTags && this.getTags(book).length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.getTags(book), (tag: string, index: number) => {
                  this.tagChip(tag, index)
                })
              }
              .width('100%')
              .margin({ top: AppSpacing.SM })
            }

            if (this.metadataLine(book)) {
              Text(this.metadataLine(book))
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor)
                .margin({ top: AppSpacing.XXS })
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }

            if (this.showSourceLine) {
              Text(this.sourceLine(book))
                .fontSize(AppFontSize.CAPTION)
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
          }
        }
        .width('100%')
        .padding(AppSpacing.LG)
      }
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
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

  private toggleShelfFromSwipe(book: SearchBook): void {
    if (SearchBookShelfHelper.isBusy(book, this.busyBookKeys)) return;
    // 先收起横滑菜单，避免菜单一直停留到入架完成。
    this.scroller.closeAllSwipeActions();
    this.onToggleShelf(book);
  }

  private searchResultSwipeActions(book: SearchBook): HdsSwipeActionOptions {
    const options: HdsSwipeActionOptions = {
      icons: [
        {
          icon: new SymbolGlyphModifier(this.searchResultShelfActionIcon(book)),
          // 使用主题按钮色，随当前主题保持一致并确保图标有足够对比度。
          backgroundColor: ThemeRuntime.buttonColor(this.isDarkMode()),
          iconOptions: {
            accessibilityText: SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys) ? '移出书架' : '加入书架'
          },
          onAction: () => {
            this.toggleShelfFromSwipe(book);
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

  searchResultShelfActionIcon(book: SearchBook): Resource {
    return SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys) ?
      $r('sys.symbol.bookshelf_badge_checkmark') : $r('sys.symbol.bookshelf_badge_plus');
  }

  @Builder
  searchResultFallbackSwipeActions(book: SearchBook) {
    Row() {
      Column({ space: AppSpacing.XS }) {
        SymbolGlyph(this.searchResultShelfActionIcon(book))
          .fontSize(22)
          .fontColor(['#FFFFFF'])
        Text(SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys) ? '移出书架' : '加入书架')
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFF')
      }
      .width(82)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeRuntime.buttonColor(this.isDarkMode()))
      .onClick(() => this.toggleShelfFromSwipe(book))

      Column({ space: AppSpacing.XS }) {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(22)
          .fontColor(['#FFFFFF'])
        Text('阅读')
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFF')
      }
      .width(64)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeRuntime.accentColor(this.isDarkMode()))
      .onClick(() => this.onReadBook(book))
    }
    .height('100%')
  }

  @Builder
  aggregationIndicator(book: SearchBook) {
    Column({ space: AppSpacing.XXS }) {
      Text(`${book.aggregationCount}`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
      Text('结果')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
    }
    .width(64)
    .height(44)
    .margin({ left: AppSpacing.LG })
    .justifyContent(FlexAlign.Center)
  }


  // 小说是默认类型，不加角标。
  mediaBadge(book: SearchBook): string {
    const category = BookTypeSupport.mediaCategoryOf(book);
    if (category === BookTypeSupport.CATEGORY_COMIC) return '漫画';
    if (category === BookTypeSupport.CATEGORY_AUDIO) return '有声';
    if (category === BookTypeSupport.CATEGORY_VIDEO) return '视频';
    return '';
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
      .fontSize(AppFontSize.CAPTION)
      .fontColor(BookDisplayHelper.getTagTextColor(index, this.isDarkMode()))
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 3, bottom: 3 })
      .attributeModifier(BookDisplayHelper.getGlassTagModifier(index, this.isDarkMode()))
      .margin({ right: AppSpacing.SM, bottom: AppSpacing.XS })
  }

  @Builder
  resultCover(book: SearchBook, radius: number, decodeWidth: number, decodeHeight: number) {
    BookCover({
      bookUrl: book.bookUrl, origin: book.origin, coverUrl: book.coverUrl, name: book.name, author: book.author,
      useBookshelfCover: this.useBookshelfCoverGallery,
      placeholderColor: this.accentColor(), cornerRadius: radius, decodeWidth, decodeHeight,
      onReadyCover: (url: ResourceStr): void => {
        const key = this.itemKey(book);
        if (this.readyCoverUrls.get(key) !== url) this.readyCoverUrls.set(key, url);
      }
    })
  }

  @Builder
  coverView(book: SearchBook) {
    Stack() {
      this.resultCover(book, 6, 180, 240)
    }
    .width(54)
    .height(72)
    .borderRadius(6)
    .clip(true)
  }

  isDarkMode(): boolean {
    return this.appDarkMode;
  }

  backdropCover(book: SearchBook): ResourceStr {
    return this.readyCoverUrls.get(this.itemKey(book)) || '';
  }

  accentColor(): string {
    return this.isDarkMode() ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  metadataLine(book: SearchBook): string {
    const parts: string[] = [];
    if (this.safeText(book.wordCount, '')) parts.push(`字数：${this.safeText(book.wordCount, '')}`);
    if (this.safeText(book.latestChapterTitle, '')) parts.push(`最新：${this.safeText(book.latestChapterTitle, '')}`);
    if (this.safeText(book.updateTime, '')) parts.push(`更新：${this.safeText(book.updateTime, '')}`);
    return parts.join(' · ');
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

  listItemKey(book: SearchBook): string {
    const baseKey = this.itemKey(book);
    if (book.aggregationCount > 1) return baseKey;
    const shelfState = SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys) ? 'shelf' : 'not_shelf';
    return `${baseKey}|${shelfState}`;
  }

  safeText(value: string, fallback: string): string {
    const text = (value || '').trim();
    return text || fallback;
  }
}
