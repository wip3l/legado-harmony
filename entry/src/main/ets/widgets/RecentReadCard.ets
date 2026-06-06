class CardRouteParams {
  shortcutAction: string = 'open_book';
  bookUrl: string = '';

  constructor(bookUrl: string) {
    this.bookUrl = bookUrl;
  }
}

class CardRouteAction {
  action: string = 'router';
  abilityName: string = 'EntryAbility';
  params: CardRouteParams;

  constructor(bookUrl: string) {
    this.params = new CardRouteParams(bookUrl);
  }
}

let storage = new LocalStorage();

@Entry(storage)
@Component
struct RecentReadCard {
  @LocalStorageProp('version') version: number = 0;
  @LocalStorageProp('orderSignature') orderSignature: string = '';
  @LocalStorageProp('darkMode') darkMode: boolean = false;
  @LocalStorageProp('count') count: number = 0;
  @LocalStorageProp('updatedAt') updatedAt: string = '';
  @LocalStorageProp('emptyTitle') emptyTitle: string = '暂无最近阅读';
  @LocalStorageProp('emptySubtitle') emptySubtitle: string = '打开书架阅读后会显示在这里';

  @LocalStorageProp('book0Name') book0Name: string = '';
  @LocalStorageProp('book0Meta') book0Meta: string = '';
  @LocalStorageProp('book0Progress') book0Progress: string = '';
  @LocalStorageProp('book0Url') book0Url: string = '';
  @LocalStorageProp('book0Cover') book0Cover: string = '';
  @LocalStorageProp('book0Accent') book0Accent: string = '#007DFF';

  @LocalStorageProp('book1Name') book1Name: string = '';
  @LocalStorageProp('book1Meta') book1Meta: string = '';
  @LocalStorageProp('book1Progress') book1Progress: string = '';
  @LocalStorageProp('book1Url') book1Url: string = '';
  @LocalStorageProp('book1Cover') book1Cover: string = '';
  @LocalStorageProp('book1Accent') book1Accent: string = '#2E7D68';

  @LocalStorageProp('book2Name') book2Name: string = '';
  @LocalStorageProp('book2Meta') book2Meta: string = '';
  @LocalStorageProp('book2Progress') book2Progress: string = '';
  @LocalStorageProp('book2Url') book2Url: string = '';
  @LocalStorageProp('book2Cover') book2Cover: string = '';
  @LocalStorageProp('book2Accent') book2Accent: string = '#7A5AF8';

  build() {
    Column() {
      Text(`${this.version}|${this.orderSignature}`)
        .height(0)
        .opacity(0)
        .fontSize(1)

      this.header()

      if (this.count <= 0) {
        this.emptyState()
      } else {
        Row({ space: 8 }) {
          if (this.book0Url) {
            this.bookTile(this.book0Name, this.book0Progress, this.book0Url, this.book0Cover, this.book0Accent)
          }
          if (this.book1Url) {
            this.bookTile(this.book1Name, this.book1Progress, this.book1Url, this.book1Cover, this.book1Accent)
          }
          if (this.book2Url) {
            this.bookTile(this.book2Name, this.book2Progress, this.book2Url, this.book2Cover, this.book2Accent)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 8 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.cardBackgroundColor())
  }

  @Builder
  header() {
    Row() {
      Column() {
        Text('最近阅读')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
        Text(this.updatedAt ? `更新 ${this.updatedAt}` : '轻页书架')
          .fontSize(11)
          .fontColor(this.secondaryTextColor())
          .margin({ top: 2 })
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('刷新', { type: ButtonType.Capsule })
        .fontSize(12)
        .fontColor('#007DFF')
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor(this.darkMode ? '#253041' : '#E7F0FF')
        .stateEffect(true)
        .onClick(() => {
          postCardAction(this, {
            action: 'message',
            params: {
              action: 'refresh',
              nonce: Date.now()
            }
          });
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  emptyState() {
    Column() {
      Text(this.emptyTitle || '暂无最近阅读')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
      Text(this.emptySubtitle || '打开书架阅读后会显示在这里')
        .fontSize(11)
        .fontColor(this.secondaryTextColor())
        .margin({ top: 5 })
        .maxLines(1)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  bookTile(name: string, progress: string, bookUrl: string, cover: string, accent: string) {
    Stack({ alignContent: Alignment.BottomStart }) {
      this.coverBackground(name, cover, accent)

      Column() {
        Text(name || '未命名书籍')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(progress || '继续阅读')
          .fontSize(9)
          .fontColor('#E8EEF7')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .width('100%')
      .padding({ left: 7, right: 7, top: 7, bottom: 7 })
      .backgroundColor('#66000000')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .height(104)
    .borderRadius(8)
    .clip(true)
    .onClick(() => {
      postCardAction(this, new CardRouteAction(bookUrl));
    })
  }

  @Builder
  coverBackground(name: string, cover: string, accent: string) {
    Stack() {
      Column() {
        Text(name ? name.substring(0, 1) : '书')
          .fontSize(26)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(accent || '#007DFF')

      if (cover) {
        Image(cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
    }
    .width('100%')
    .height('100%')
  }

  private cardBackgroundColor(): string {
    return this.darkMode ? '#191B1F' : '#F7F8FA';
  }

  private primaryTextColor(): string {
    return this.darkMode ? '#F2F3F5' : '#1F1F1F';
  }

  private secondaryTextColor(): string {
    return this.darkMode ? '#8A8F98' : '#69717A';
  }
}
