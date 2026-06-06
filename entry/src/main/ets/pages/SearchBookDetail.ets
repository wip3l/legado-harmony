import { router, promptAction } from '@kit.ArkUI';
import { Book } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { syncSystemBars } from '../utils/SystemBars';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverUrlNormalizer } from '../utils/CoverUrlNormalizer';

@Entry
@Component
struct SearchBookDetailPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State bookUrl: string = '';
  @State tocUrl: string = '';
  @State origin: string = '';
  @State originName: string = '';
  @State name: string = '';
  @State author: string = '';
  @State kind: string = '';
  @State coverUrl: string = '';
  @State intro: string = '';
  @State latestChapterTitle: string = '';
  @State wordCount: string = '';
  @State isInShelf: boolean = false;
  @State isSaving: boolean = false;

  aboutToAppear() {
    this.syncBars();
    const params = router.getParams() as Record<string, string>;
    if (params) {
      this.bookUrl = params['bookUrl'] || '';
      this.tocUrl = params['tocUrl'] || '';
      this.origin = params['origin'] || '';
      this.originName = params['originName'] || '';
      this.name = params['name'] || '';
      this.author = params['author'] || '';
      this.kind = params['kind'] || '';
      this.coverUrl = params['coverUrl'] || '';
      this.intro = params['intro'] || '';
      this.latestChapterTitle = params['latestChapterTitle'] || '';
      this.wordCount = params['wordCount'] || '';
      this.checkShelf();
    }
  }

  onPageShow(): void {
    this.syncBars();
    this.checkShelf();
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(28)
          .fontColor(this.primaryTextColor())
          .width(40)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back();
          })

        Text('书籍详情')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.cardColor())

      Scroll() {
        Column() {
          Row() {
            Column() {
              Text(this.name || '未知书名')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.author || '作者未知')
                .fontSize(15)
                .fontColor(this.secondaryTextColor())
                .margin({ top: 8 })

              Text(this.originName || this.origin)
                .fontSize(13)
                .fontColor(this.subTextColor())
                .margin({ top: 8 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.cardColor())
          .borderRadius(8)

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.getTags(), (tag: string, index: number) => {
              this.tagChip(tag, index)
            })

            if (this.wordCount) {
              Text(this.wordCount)
                .fontSize(13)
                .fontColor(this.secondaryTextColor())
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor(this.inputColor())
                .borderRadius(14)
                .margin({ right: 8, bottom: 8 })
            }

            if (this.isInShelf) {
              Text('已在书架')
                .fontSize(13)
                .fontColor(this.appDarkMode ? '#7DD89B' : '#0A7D36')
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor(this.appDarkMode ? '#173B24' : '#E8F5E9')
                .borderRadius(14)
                .margin({ right: 8, bottom: 8 })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16 })

          if (this.latestChapterTitle) {
            Column() {
              Text('最新章节')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .width('100%')
              Text(this.latestChapterTitle)
                .fontSize(14)
                .fontColor(this.secondaryTextColor())
                .width('100%')
                .margin({ top: 8 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.cardColor())
            .borderRadius(8)
            .margin({ top: 12 })
          }

          Row({ space: 14 }) {
            this.coverView(this.name, this.coverUrl, 88, 118)

            Column() {
              Text('简介')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .width('100%')
              Text(this.intro || '暂无简介')
                .fontSize(14)
                .fontColor(this.secondaryTextColor())
                .lineHeight(22)
                .width('100%')
                .maxLines(8)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 8 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.cardColor())
          .borderRadius(8)
          .margin({ top: 12 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 96 })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.pageColor())

      Row() {
        Button(this.isInShelf ? '已加入书架' : '加入书架')
          .enabled(!this.isInShelf && !this.isSaving)
          .height(44)
          .layoutWeight(1)
          .margin({ right: 10 })
          .onClick(() => {
            this.addToShelf();
          })

        Button('开始阅读')
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            this.startRead();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(this.cardColor())
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  async checkShelf() {
    if (!this.bookUrl || this.bookUrl.trim() === '') {
      this.isInShelf = false;
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const existing = await db.getBook(this.bookUrl) ||
        await this.findShelfBookByKey(BookIdentity.keyOfUrl(this.bookUrl));
      if (existing) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
          await db.updateBook(existing);
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
      }
      if (existing) {
        this.syncStateFromBook(existing);
      }
      this.isInShelf = existing !== null;
    } catch (e) {
      console.error('检查书架失败:', e);
      this.isInShelf = false;
    }
  }

  async addToShelf(): Promise<boolean> {
    if (!this.bookUrl) {
      promptAction.showToast({ message: '书籍地址为空' });
      return false;
    }

    this.isSaving = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const requestKey = BookIdentity.keyOfUrl(this.bookUrl);
      const existing = await db.getBook(this.bookUrl) || await this.findShelfBookByKey(requestKey);
      if (existing) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
          await db.updateBook(existing);
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
        this.syncStateFromBook(existing);
        this.isInShelf = true;
        return true;
      }

      const book = new Book();
      book.bookUrl = this.bookUrl;
      book.tocUrl = this.tocUrl;
      book.origin = this.origin;
      book.originName = this.originName;
      book.name = this.name;
      book.author = this.author;
      book.kind = this.kind;
      book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
      book.intro = this.intro;
      book.latestChapterTitle = this.latestChapterTitle;
      book.wordCount = this.wordCount;
      book.group = -2147483645;
      book.type = 0;
      book.canUpdate = true;
      book.lastCheckTime = Date.now();
      book.latestChapterTime = Date.now();
      const fallbackCoverUrl = book.coverUrl;
      const source = book.origin ? await db.getBookSource(book.origin) : null;
      if (source) {
        const service = new WebBookService();
        const fullBook = await service.getBookInfo(source, book);
        book.bookUrl = fullBook.bookUrl || book.bookUrl;
        book.tocUrl = fullBook.tocUrl || book.tocUrl;
        book.name = fullBook.name || book.name;
        book.author = fullBook.author || book.author;
        book.kind = fullBook.kind || book.kind;
        book.coverUrl = CoverUrlNormalizer.prefer(fallbackCoverUrl, fullBook.coverUrl || book.coverUrl);
        book.intro = fullBook.intro || book.intro;
        book.latestChapterTitle = fullBook.latestChapterTitle || book.latestChapterTitle;
        book.wordCount = fullBook.wordCount || book.wordCount;
        book.variable = fullBook.variable || book.variable;
      }

      const resolvedExisting = await this.findShelfBookByKey(BookIdentity.keyOfBook(book));
      if (resolvedExisting) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(book.coverUrl, resolvedExisting.coverUrl);
        if (nextCoverUrl && resolvedExisting.coverUrl !== nextCoverUrl) {
          resolvedExisting.coverUrl = nextCoverUrl;
          await db.updateBook(resolvedExisting);
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
        this.syncStateFromBook(resolvedExisting);
        this.isInShelf = true;
        return true;
      }

      await db.insertBook(book);
      this.syncStateFromBook(book);

      this.isInShelf = true;
      this.isSaving = false;
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      promptAction.showToast({ message: '已加入书架' });
      return true;
    } catch (e) {
      console.error('加入书架失败:', e);
      promptAction.showToast({ message: '加入书架失败' });
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async findShelfBookByKey(bookKey: string): Promise<Book | null> {
    if (!bookKey) {
      return null;
    }
    const db = AppDatabase.getInstance();
    const books = await db.getAllBooks();
    for (const book of books) {
      if (BookIdentity.keyOfBook(book) === bookKey) {
        return book;
      }
    }
    return null;
  }

  syncStateFromBook(book: Book): void {
    this.bookUrl = book.bookUrl || this.bookUrl;
    this.tocUrl = book.tocUrl || this.tocUrl;
    this.origin = book.origin || this.origin;
    this.originName = book.originName || this.originName;
    this.name = book.name || this.name;
    this.author = book.author || this.author;
    this.kind = book.kind || this.kind;
    this.coverUrl = CoverUrlNormalizer.prefer(book.coverUrl, this.coverUrl);
    this.intro = book.intro || this.intro;
    this.latestChapterTitle = book.latestChapterTitle || this.latestChapterTitle;
    this.wordCount = book.wordCount || this.wordCount;
  }

  async startRead() {
    const ok = await this.addToShelf();
    if (!ok) return;

    router.pushUrl({
      url: 'pages/ReadBook',
      params: { bookUrl: this.bookUrl }
    });
  }

  getTags(): string[] {
    return BookDisplayHelper.splitTags(this.kind, '');
  }

  @Builder
  tagChip(tag: string, index: number) {
    Text(tag)
      .fontSize(13)
      .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(BookDisplayHelper.getTagBackgroundColor(index, this.appDarkMode))
      .borderRadius(14)
      .margin({ right: 8, bottom: 8 })
  }

  @Builder
  coverView(name: string, coverUrl: string, width: number, height: number) {
    Stack() {
      Column() {
        Text(name ? name.substring(0, 1) : '书')
          .fontSize(30)
          .fontColor('#FFFFFF')
      }
      .width(width)
      .height(height)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#6B50B6')

      if (coverUrl) {
        Image(coverUrl)
          .width(width)
          .height(height)
          .objectFit(ImageFit.Cover)
      }
    }
    .width(width)
    .height(height)
    .borderRadius(8)
    .clip(true)
    .backgroundColor(this.inputColor())
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F2F2F2';
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

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
