import { router } from '@kit.ArkUI';
import { SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { promptAction } from '@kit.ArkUI';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';

@Entry
@Component
struct SearchPage {
  @State keyword: string = '';
  @State searchResults: SearchBook[] = [];
  @State isSearching: boolean = false;
  @State searchHistory: string[] = [];
  @State hotKeywords: string[] = ['斗破苍穹', '完美世界', '遮天', '凡人修仙传', '诛仙'];
  @State showResult: boolean = false;
  @State statusMessage: string = '';

  aboutToAppear() {
    this.initPage();
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
          .backgroundColor('#F5F5F5')
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
      .backgroundColor('#FFFFFF')
      .alignItems(VerticalAlign.Center)

      // 状态消息
      if (this.statusMessage) {
        Text(this.statusMessage)
          .fontSize(14)
          .fontColor('#666')
          .width('100%')
          .height(36)
          .textAlign(TextAlign.Center)
          .backgroundColor('#E8F5E9')
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
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(book.author)
                    .fontSize(14)
                    .fontColor('#666')
                    .margin({ top: 4 })

                  Text(book.originName)
                    .fontSize(12)
                    .fontColor('#999')
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#FFFFFF')
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
                  .fontColor('#999')
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
            .fontColor('#999')
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.showResult && this.searchResults.length === 0) {
        Column() {
          Text('未找到相关书籍')
            .fontSize(16)
            .fontColor('#999')
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
                .width('100%')

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.searchHistory, (keyword: string) => {
                  Text(keyword)
                    .fontSize(14)
                    .fontColor('#666')
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor('#FFFFFF')
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
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .margin({ left: 16, right: 16, top: 16 })
          }

          Column() {
            Text('热门搜索')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .width('100%')

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.hotKeywords, (keyword: string) => {
                Text(keyword)
                  .fontSize(14)
                  .fontColor('#666')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor('#FFFFFF')
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
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .margin({ left: 16, right: 16, top: 16 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
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
}
