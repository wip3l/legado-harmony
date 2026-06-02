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

class CardRefreshParams {
  action: string = 'refresh';
}

class CardRefreshAction {
  action: string = 'message';
  params: CardRefreshParams = new CardRefreshParams();
}

let storage = new LocalStorage();

@Entry(storage)
@Component
struct RecentReadCard {
  @LocalStorageProp('dimension') dimension: number = 2;
  @LocalStorageProp('darkMode') darkMode: boolean = false;
  @LocalStorageProp('count') count: number = 0;
  @LocalStorageProp('emptyText') emptyText: string = '暂无最近阅读';
  @LocalStorageProp('updatedAt') updatedAt: string = '';
  @LocalStorageProp('book0Name') book0Name: string = '';
  @LocalStorageProp('book0Author') book0Author: string = '';
  @LocalStorageProp('book0Progress') book0Progress: string = '';
  @LocalStorageProp('book0Url') book0Url: string = '';
  @LocalStorageProp('book1Name') book1Name: string = '';
  @LocalStorageProp('book1Author') book1Author: string = '';
  @LocalStorageProp('book1Progress') book1Progress: string = '';
  @LocalStorageProp('book1Url') book1Url: string = '';
  @LocalStorageProp('book2Name') book2Name: string = '';
  @LocalStorageProp('book2Author') book2Author: string = '';
  @LocalStorageProp('book2Progress') book2Progress: string = '';
  @LocalStorageProp('book2Url') book2Url: string = '';

  build() {
    Column() {
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
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('↻')
          .fontSize(18)
          .fontColor('#007DFF')
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            postCardAction(this, new CardRefreshAction());
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.count <= 0) {
        Column() {
          Text(this.emptyText)
            .fontSize(14)
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
          Text('打开应用添加书籍后会显示在这里')
            .fontSize(11)
            .fontColor(this.tertiaryTextColor())
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
      } else {
        Row({ space: 10 }) {
          if (this.book0Url) {
            this.bookCover(this.book0Name, this.book0Progress, this.book0Url, 0)
          }
          if (this.book1Url) {
            this.bookCover(this.book1Name, this.book1Progress, this.book1Url, 1)
          }
          if (this.book2Url) {
            this.bookCover(this.book2Name, this.book2Progress, this.book2Url, 2)
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
    .padding(14)
    .backgroundColor(this.cardBackgroundColor())
  }

  @Builder
  bookCover(name: string, progress: string, bookUrl: string, index: number) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column() {
        Text('阅读')
          .fontSize(10)
          .fontColor('#DDEBFF')
          .opacity(0.8)
          .margin({ top: 9, left: 9 })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.coverColor(index))

      Column() {
        Text(name || '未命名书籍')
          .fontSize(13)
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
      .padding({ left: 8, right: 8, top: 7, bottom: 7 })
      .backgroundColor('#66000000')
      .alignItems(HorizontalAlign.Start)
    }
    .width('31%')
    .height(96)
    .borderRadius(8)
    .clip(true)
    .onClick(() => {
      postCardAction(this, new CardRouteAction(bookUrl));
    })
  }

  private coverColor(index: number): string {
    if (index === 0) {
      return '#007DFF';
    }
    if (index === 1) {
      return '#627287';
    }
    return '#2E7D68';
  }

  private cardBackgroundColor(): string {
    return this.darkMode ? '#191B1F' : '#F7F8FA';
  }

  private primaryTextColor(): string {
    return this.darkMode ? '#F2F3F5' : '#1F1F1F';
  }

  private secondaryTextColor(): string {
    return this.darkMode ? '#8A8F98' : '#7C858F';
  }

  private tertiaryTextColor(): string {
    return this.darkMode ? '#6F7480' : '#A0A7B0';
  }
}
