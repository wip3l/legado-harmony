import { Book, SearchBook } from '../../model/data/Book';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { BookDisplayHelper } from '../../utils/BookDisplayHelper';
import { CoverGallerySettings } from '../../utils/CoverGallerySettings';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';

export type SearchBookAction = (book: SearchBook) => void;

@Component
export struct SearchBookResultList {
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('bookshelfCoverAlbums') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverMode') bookshelfCoverMode: string = 'sequence';
  @Prop books: SearchBook[] = [];
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
  @Prop bottomPadding: number = 12;
  onOpenBook: SearchBookAction = (_book: SearchBook) => {};
  onToggleShelf: SearchBookAction = (_book: SearchBook) => {};

  build() {
    List({ space: 8 }) {
      ForEach(this.books, (book: SearchBook) => {
        ListItem() {
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

            this.shelfActionButton(book)
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
        }
      }, (book: SearchBook) => this.itemKey(book))

      if (this.showLoadingMore) {
        ListItem() {
          Row() {
            LoadingProgress()
              .width(20)
              .height(20)
            Text('继续搜索中...')
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
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.pageColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  shelfActionButton(book: SearchBook) {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      this.shelfActionGlyph(book)
    }
      .enabled(!SearchBookShelfHelper.isBusy(book, this.busyBookKeys))
      .width(64)
      .height(36)
      .borderRadius(18)
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.isDarkMode(), this.cardColor))
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, {
        colorMode: this.isDarkMode() ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
        adaptiveColor: AdaptiveColor.AVERAGE,
        scale: 1
      })
      .border({ width: 0.5, color: ThemeRuntime.glassBorderColor(this.isDarkMode()) })
      .shadow({ radius: 9, color: ThemeRuntime.glassShadowColor(this.isDarkMode()), offsetX: 0, offsetY: 3 })
      .accessibilityText(SearchBookShelfHelper.buttonText(book, this.shelfBookKeys, this.busyBookKeys))
      .margin({ left: 12 })
      .opacity(SearchBookShelfHelper.isBusy(book, this.busyBookKeys) ? 0.58 : 1)
      .onClick(() => {
        this.onToggleShelf(book);
      })
  }

  @Builder
  shelfActionGlyph(book: SearchBook) {
    if (SearchBookShelfHelper.isBusy(book, this.busyBookKeys)) {
      SymbolGlyph($r('sys.symbol.hourglass'))
        .fontSize(21)
        .fontWeight(FontWeight.Medium)
        .fontColor([SearchBookShelfHelper.buttonColor(book, this.shelfBookKeys, this.busyBookKeys)])
    } else if (SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys)) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.bookshelf'))
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor([SearchBookShelfHelper.buttonColor(book, this.shelfBookKeys, this.busyBookKeys)])

        SymbolGlyph($r('sys.symbol.minus_circle_fill'))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor([SearchBookShelfHelper.buttonColor(book, this.shelfBookKeys, this.busyBookKeys)])
          .position({ x: 17, y: 0 })
      }
      .width(28)
      .height(24)
    } else {
      SymbolGlyph($r('sys.symbol.bookshelf_badge_plus'))
        .fontSize(21)
        .fontWeight(FontWeight.Medium)
        .fontColor([SearchBookShelfHelper.buttonColor(book, this.shelfBookKeys, this.busyBookKeys)])
    }
  }

  sourceLine(book: SearchBook): string {
    return this.safeText(book.originName, '');
  }

  getTags(book: SearchBook): string[] {
    if (!this.showResultTags) {
      return [];
    }
    return BookDisplayHelper.splitTags(this.safeText(book.kind, ''), '');
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
    if (this.useBookshelfCoverGallery) {
      const galleryCover = this.bookshelfGalleryCover(book);
      if (galleryCover) {
        return galleryCover;
      }
    }
    return this.safeText(book.coverUrl, '');
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
    const key = SearchBookShelfHelper.keyOf(book);
    return `${key || this.safeText(book.bookUrl, '')}|${this.safeText(book.originName, '')}|${this.safeText(book.name, '')}`;
  }

  safeText(value: string, fallback: string): string {
    const text = (value || '').trim();
    return text || fallback;
  }
}
