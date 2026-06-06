import { SearchBook } from '../../model/data/Book';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';

export type SearchBookAction = (book: SearchBook) => void;

@Component
export struct SearchBookResultList {
  @Prop books: SearchBook[] = [];
  @Prop shelfBookKeys: string[] = [];
  @Prop busyBookKeys: string[] = [];
  @Prop showLoadingMore: boolean = false;
  @Prop showKind: boolean = false;
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
            Column() {
              Text(book.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(book.author || '作者未知')
                .fontSize(14)
                .fontColor(this.secondaryTextColor)
                .margin({ top: 4 })

              Text(this.sourceLine(book))
                .fontSize(12)
                .fontColor(this.subTextColor)
                .margin({ top: 4 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Button(SearchBookShelfHelper.buttonText(book, this.shelfBookKeys, this.busyBookKeys))
              .enabled(!SearchBookShelfHelper.isBusy(book, this.busyBookKeys))
              .width(64)
              .height(32)
              .fontSize(13)
              .borderRadius(16)
              .backgroundColor(SearchBookShelfHelper.buttonColor(book, this.shelfBookKeys, this.busyBookKeys))
              .fontColor('#FFFFFF')
              .margin({ left: 12 })
              .onClick(() => {
                this.onToggleShelf(book);
              })
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
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, bottom: this.bottomPadding })
    .backgroundColor(this.pageColor)
  }

  sourceLine(book: SearchBook): string {
    if (!this.showKind) {
      return book.originName;
    }
    return `${book.originName}${book.kind ? ' · ' + book.kind : ''}`;
  }

  itemKey(book: SearchBook): string {
    const key = SearchBookShelfHelper.keyOf(book);
    return `${key}|${book.originName}|${book.name}`;
  }
}
