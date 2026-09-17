import { router, promptAction } from '@kit.ArkUI';
import { Book } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { syncSystemBars } from '../utils/SystemBars';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverUrlNormalizer } from '../utils/CoverUrlNormalizer';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { CoverGallerySettings } from '../utils/CoverGallerySettings';
import { BookFieldSanitizer } from '../utils/BookFieldSanitizer';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { BookTypeSupport } from '../core/book/BookTypeSupport';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { BookSourceStageRuntimeHost } from '../components/BookSourceStageRuntimeHost';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';
import { BookUrlResolver } from '../core/book/BookUrlResolver';

@Entry
@Component
struct SearchBookDetailPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageLink('bookshelfCoverAlbums') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverMode') bookshelfCoverMode: string = 'sequence';
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State bookUrl: string = '';
  @State tocUrl: string = '';
  @State origin: string = '';
  @State originName: string = '';
  @State name: string = '';
  @State author: string = '';
  @State kind: string = '';
  @State status: string = '';
  @State coverUrl: string = '';
  @State intro: string = '';
  @State latestChapterTitle: string = '';
  @State totalChapterNum: number = 0;
  @State wordCount: string = '';
  @State updateTime: string = '';
  @State bookType: number = 0;
  private bookVariable: string = '';
  private autoStartRead: boolean = false;
  private autoStartReadTriggered: boolean = false;
  @State isInShelf: boolean = false;
  @State isSaving: boolean = false;
  @State isLoadingBookInfo: boolean = false;
  @State bookInfoRenderVersion: number = 0;
  private hasLoadedBookInfo: boolean = false;
  private resolvedBookInfo: Book | null = null;
  private bookInfoPromise: Promise<Book | null> | null = null;
  private bookInfoRetryTimerId: number = -1;
  private bookInfoRetryCount: number = 0;
  private shelfCheckPromise: Promise<void> | null = null;
  private shelfCheckKey: string = '';
  private shelfCheckVersion: number = -1;
  @State promptAddToShelfOnBackFromResult: boolean = false;
  @State promptAddToShelfAfterRead: boolean = false;
  @State pendingAddToShelfBookUrl: string = '';
  @State showAddToShelfOnBackDialog: boolean = false;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;

  aboutToAppear() {
    this.syncBars();
    this.bookInfoRetryCount = 0;
    const params = router.getParams() as Record<string, string>;
    if (params) {
      // Heal result caches produced by older builds that joined every matching descendant URL.
      // Keeping this at the detail boundary also prevents malformed values from becoming shelf IDs.
      this.bookUrl = BookUrlResolver.scalar(params['bookUrl'] || '');
      this.tocUrl = BookUrlResolver.scalar(params['tocUrl'] || '');
      this.origin = params['origin'] || '';
      this.originName = params['originName'] || '';
      this.name = params['name'] || '';
      this.author = params['author'] || '';
      this.kind = params['kind'] || '';
      this.status = params['status'] || '';
      this.coverUrl = params['coverUrl'] || '';
      this.intro = BookFieldSanitizer.clean(params['intro'] || '');
      this.latestChapterTitle = params['latestChapterTitle'] || '';
      this.wordCount = params['wordCount'] || '';
      this.updateTime = params['updateTime'] || '';
      this.bookType = Number(params['type'] || 0) || 0;
      this.bookVariable = params['variable'] || '';
      this.promptAddToShelfOnBackFromResult = params['promptAddToShelfOnBack'] === 'true';
      this.autoStartRead = params['autoStartRead'] === 'true';
      // Both operations initialize/read the same AppDatabase instance. Starting them at the
      // same time can make getBookSource() observe the store before initialization has completed,
      // leaving the detail page with an empty intro until the reader opens the book again.
      // Serialize the source-detail request behind the shelf check so the first page visit uses
      // the same initialized database path as the reader.
      this.checkShelf().then((): void => {
        this.loadBookInfo();
        this.triggerAutoStartRead();
      });
    }
  }

  onPageShow(): void {
    this.syncBars();
    this.checkShelf().then(() => {
      if (this.shouldPromptAddToShelfOnBack()) {
        this.showAddToShelfOnBackPrompt();
      }
    });
    this.refreshChapterCount();
    // Some source runtimes need one UI turn after the detail route is mounted (especially when the
    // hidden Web transport is still attaching). Do not keep an empty first response cached forever.
    if (!this.intro && !this.isLoadingBookInfo && this.bookUrl && this.origin) {
      this.scheduleBookInfoRetry();
    }
  }

  aboutToDisappear(): void {
    if (this.bookInfoRetryTimerId >= 0) {
      clearTimeout(this.bookInfoRetryTimerId);
      this.bookInfoRetryTimerId = -1;
    }
  }

  build() {
    Stack() {
      WebBookFetchRuntimeHost()
      Column() {
        Scroll() {
          Column() {
            Row({ space: 16 }) {
              this.coverView(this.name, this.displayCoverUrl(), 96, 128)

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
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .backgroundColor(this.cardColor())
            .borderRadius(8)
            .alignItems(VerticalAlign.Center)

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

              if (this.updateTime) {
                Text(`更新：${this.updateTime}`)
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

            // The catalog is the only entry point to the chapter list, so this card must stay
            // visible even when the source returned no latest-chapter title.
            Column() {
              Row() {
                Text('目录')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.primaryTextColor())
                  .layoutWeight(1)

                if (this.totalChapterNum > 0) {
                  Text(`共 ${this.totalChapterNum} 章`)
                    .fontSize(13)
                    .fontColor(this.subTextColor())
                }

                Text('›')
                  .fontSize(18)
                  .fontColor(this.subTextColor())
                  .margin({ left: 6 })
              }
              .width('100%')

              Text(this.latestChapterTitle || '点击查看该书源的完整章节列表')
                .fontSize(14)
                .fontColor(this.secondaryTextColor())
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 8 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.cardColor())
            .borderRadius(8)
            .margin({ top: 12 })
            .onClick(() => {
              this.openChapterList();
            })

            Column() {
              Text('简介')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .width('100%')
                .textAlign(TextAlign.Center)

              Text(this.intro || (this.isLoadingBookInfo ? '简介加载中...' : '暂无简介'))
                .fontSize(16)
                .fontColor(this.secondaryTextColor())
                .lineHeight(26)
                .copyOption(CopyOptions.LocalDevice)
                .width('100%')
                .id(`book_detail_intro_${this.bookInfoRenderVersion}`)
                .margin({ top: 12 })
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 18, bottom: 22 })
            .backgroundColor(this.cardColor())
            .borderRadius(8)
            .margin({ top: 12 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 72 + this.statusBarHeight, bottom: 96 })
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(this.pageColor())

        Row({ space: 10 }) {
          Button(this.isInShelf ? '已加入书架' : '加入书架')
            .enabled(!this.isInShelf && !this.isSaving)
            .height(44)
            .fontSize(15)
            .layoutWeight(1)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.addToShelf();
            })

          Button('目录')
            .height(44)
            .fontSize(15)
            .layoutWeight(1)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.openChapterList();
            })

          Button(BookTypeSupport.isAudio(this.detailTypeProbe()) ? '开始听书' : '开始阅读')
            .height(44)
            .fontSize(15)
            .layoutWeight(1)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.startRead();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 + this.navBarHeight })
        .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
        .backdropBlur(ThemeRuntime.topBarBlur())
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      this.titleBar()

      if (this.showAddToShelfOnBackDialog) {
        this.addToShelfOnBackDialog()
      }
      BookSourceStageRuntimeHost()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        onBack: () => this.handleBack() })

      Text('书籍详情')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ right: 16, top: this.statusBarHeight })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
    .position({ x: 0, y: 0 })
  }

  onBackPress(): boolean {
    if (this.shouldPromptAddToShelfOnBack()) {
      this.showAddToShelfOnBackPrompt();
      return true;
    }
    return false;
  }

  async checkShelf(): Promise<void> {
    const key = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
    const version = AppStorage.get<number>('shelfUpdateTime') || 0;
    if (this.shelfCheckPromise) return this.shelfCheckPromise;
    if (key && key === this.shelfCheckKey && version === this.shelfCheckVersion) return;
    const task = this.performShelfCheck();
    this.shelfCheckPromise = task;
    try {
      await task;
      this.shelfCheckKey = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
      this.shelfCheckVersion = AppStorage.get<number>('shelfUpdateTime') || 0;
    } finally {
      if (this.shelfCheckPromise === task) this.shelfCheckPromise = null;
    }
  }

  private async performShelfCheck(): Promise<void> {
    if (!this.bookUrl || this.bookUrl.trim() === '') {
      this.isInShelf = false;
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const existing = await db.getBook(this.bookUrl) ||
        await this.findShelfBookByKey(BookIdentity.keyOfUrl(this.bookUrl, this.origin));
      if (existing) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
          await db.updateBook(existing, true, 'detail_check_cover_update');
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
      }
      if (existing) {
        this.syncStateFromBook(existing);
      }
      this.isInShelf = existing !== null && !SearchExplorePendingBook.isPendingAddToShelf(existing);
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
      const requestKey = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
      const existing = await db.getBook(this.bookUrl) || await this.findShelfBookByKey(requestKey);
      if (existing) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
        }
        existing.kind = BookFieldSanitizer.prefer(this.kind, existing.kind);
        existing.status = BookFieldSanitizer.prefer(this.status, existing.status);
        existing.intro = BookFieldSanitizer.prefer(this.intro, existing.intro);
        existing.latestChapterTitle = BookFieldSanitizer.prefer(this.latestChapterTitle, existing.latestChapterTitle);
        existing.wordCount = BookFieldSanitizer.prefer(this.wordCount, existing.wordCount);
        existing.updateTime = BookFieldSanitizer.prefer(this.updateTime, existing.updateTime);
        SearchExplorePendingBook.clearPendingAddToShelf(existing);
        await db.updateBook(existing, true, 'explicit_add_existing');
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        this.syncStateFromBook(existing);
        this.isInShelf = true;
        this.promptAddToShelfAfterRead = false;
        this.pendingAddToShelfBookUrl = '';
        return true;
      }

      const book = new Book();
      book.bookUrl = this.bookUrl;
      book.tocUrl = this.tocUrl;
      book.origin = this.origin;
      book.originName = this.originName;
      book.name = this.name;
      book.author = this.author;
      book.kind = BookFieldSanitizer.clean(this.kind);
      book.status = BookFieldSanitizer.clean(this.status);
      book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
      book.intro = BookFieldSanitizer.clean(this.intro);
      book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
      book.wordCount = BookFieldSanitizer.clean(this.wordCount);
      book.updateTime = BookFieldSanitizer.clean(this.updateTime);
      book.group = -2147483645;
      book.type = this.bookType;
      book.variable = this.bookVariable;
      BookTypeSupport.applyBookType(book);
      book.canUpdate = true;
      book.lastCheckTime = Date.now();
      book.latestChapterTime = Date.now();
      const fallbackCoverUrl = book.coverUrl;
      const fullBook = await this.resolveBookInfo();
      if (fullBook) {
        book.bookUrl = fullBook.bookUrl || book.bookUrl;
        book.tocUrl = fullBook.tocUrl || book.tocUrl;
        book.name = fullBook.name || book.name;
        book.author = fullBook.author || book.author;
        book.kind = BookFieldSanitizer.prefer(fullBook.kind, book.kind);
        book.status = BookFieldSanitizer.prefer(fullBook.status, book.status);
        book.coverUrl = CoverUrlNormalizer.prefer(fallbackCoverUrl, fullBook.coverUrl || book.coverUrl);
        book.intro = BookFieldSanitizer.prefer(fullBook.intro, book.intro);
        book.latestChapterTitle = BookFieldSanitizer.prefer(fullBook.latestChapterTitle, book.latestChapterTitle);
        book.updateTime = BookFieldSanitizer.prefer(fullBook.updateTime, book.updateTime);
        book.wordCount = BookFieldSanitizer.prefer(fullBook.wordCount, book.wordCount);
        book.variable = fullBook.variable || book.variable;
        book.type = fullBook.type || book.type;
      }

      const resolvedExisting = await this.findShelfBookByKey(BookIdentity.keyOfBook(book));
      if (resolvedExisting) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(book.coverUrl, resolvedExisting.coverUrl);
        if (nextCoverUrl && resolvedExisting.coverUrl !== nextCoverUrl) {
          resolvedExisting.coverUrl = nextCoverUrl;
        }
        resolvedExisting.kind = BookFieldSanitizer.prefer(book.kind, resolvedExisting.kind);
        resolvedExisting.status = BookFieldSanitizer.prefer(book.status, resolvedExisting.status);
        resolvedExisting.intro = BookFieldSanitizer.prefer(book.intro, resolvedExisting.intro);
        resolvedExisting.latestChapterTitle = BookFieldSanitizer.prefer(book.latestChapterTitle, resolvedExisting.latestChapterTitle);
        resolvedExisting.updateTime = BookFieldSanitizer.prefer(book.updateTime, resolvedExisting.updateTime);
        resolvedExisting.wordCount = BookFieldSanitizer.prefer(book.wordCount, resolvedExisting.wordCount);
        SearchExplorePendingBook.clearPendingAddToShelf(resolvedExisting);
        await db.updateBook(resolvedExisting, true, 'explicit_add_resolved_existing');
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        this.syncStateFromBook(resolvedExisting);
        this.isInShelf = true;
        this.promptAddToShelfAfterRead = false;
        this.pendingAddToShelfBookUrl = '';
        return true;
      }

      SearchExplorePendingBook.clearPendingAddToShelf(book);
      await db.insertBook(book, 'explicit_add_from_detail');
      this.syncStateFromBook(book);

      this.isInShelf = true;
      this.promptAddToShelfAfterRead = false;
      this.pendingAddToShelfBookUrl = '';
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

  async loadBookInfo(): Promise<void> {
    try {
      const fullBook = await this.resolveBookInfo();
      if (fullBook) this.syncStateFromBook(fullBook);
      if (!this.intro) this.scheduleBookInfoRetry();
    } catch (e) {
      console.warn('加载书籍详情失败:', e);
      this.scheduleBookInfoRetry();
    }
  }

  private scheduleBookInfoRetry(): void {
    if (this.intro || !this.bookUrl || !this.origin || this.bookInfoRetryCount >= 4) return;
    if (this.bookInfoRetryTimerId >= 0) return;
    const retry = this.bookInfoRetryCount++;
    const delay = retry === 0 ? 500 : (retry === 1 ? 1200 : (retry === 2 ? 2500 : 5000));
    this.bookInfoRetryTimerId = setTimeout((): void => {
      this.bookInfoRetryTimerId = -1;
      if (this.intro || !this.bookUrl || !this.origin || this.isLoadingBookInfo) return;
      // WebBookService returns the original Book instance when a request or rule yields no fields. Clear
      // that incomplete cache so the next attempt can observe a newly attached runtime/session.
      this.resolvedBookInfo = null;
      this.hasLoadedBookInfo = false;
      this.loadBookInfo();
    }, delay);
  }

  private async resolveBookInfo(): Promise<Book | null> {
    if (this.resolvedBookInfo) return this.resolvedBookInfo;
    if (this.bookInfoPromise) return this.bookInfoPromise;
    if (this.hasLoadedBookInfo || !this.bookUrl || !this.origin) return null;
    this.hasLoadedBookInfo = true;
    this.isLoadingBookInfo = true;
    const task = this.fetchBookInfo();
    this.bookInfoPromise = task;
    try {
      const fullBook = await task;
      if (fullBook) {
        fullBook.lastCheckTime = Date.now();
        this.resolvedBookInfo = fullBook;
        this.syncStateFromBook(fullBook);
      }
      return fullBook;
    } finally {
      if (this.bookInfoPromise === task) this.bookInfoPromise = null;
      this.isLoadingBookInfo = false;
    }
  }

  private async fetchBookInfo(): Promise<Book | null> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    const source = await db.getBookSource(this.origin);
    if (!source) return null;
    const book = this.buildCurrentBook();
    BookTypeSupport.applyBookType(book, source);
    return new WebBookService().getBookInfo(source, book);
  }

  private buildCurrentBook(): Book {
    const book = new Book();
    book.bookUrl = this.bookUrl;
    book.tocUrl = this.tocUrl;
    book.origin = this.origin;
    book.originName = this.originName;
    book.name = this.name;
    book.author = this.author;
    book.kind = BookFieldSanitizer.clean(this.kind);
    book.status = BookFieldSanitizer.clean(this.status);
    book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
    book.intro = BookFieldSanitizer.clean(this.intro);
    book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.clean(this.wordCount);
    book.updateTime = BookFieldSanitizer.clean(this.updateTime);
    book.type = this.bookType;
    book.variable = this.bookVariable;
    return book;
  }

  handleBack(): void {
    if (this.shouldPromptAddToShelfOnBack()) {
      this.showAddToShelfOnBackPrompt();
      return;
    }
    router.back();
  }

  shouldPromptAddToShelfOnBack(): boolean {
    return this.promptAddToShelfOnBackFromResult && this.searchExplorePromptAddToShelfOnBack &&
      this.promptAddToShelfAfterRead && !this.isSaving && !this.showAddToShelfOnBackDialog &&
      !!this.bookUrl && this.bookUrl === this.pendingAddToShelfBookUrl;
  }

  showAddToShelfOnBackPrompt(): void {
    this.showAddToShelfOnBackDialog = true;
  }

  dismissAddToShelfOnBackPrompt(): void {
    this.showAddToShelfOnBackDialog = false;
    this.removePendingReadBook().finally(() => {
      router.back();
    });
  }

  async removePendingReadBook(): Promise<void> {
    if (!this.pendingAddToShelfBookUrl) {
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const pendingBook = await db.getBook(this.pendingAddToShelfBookUrl);
      if (SearchExplorePendingBook.isPendingAddToShelf(pendingBook)) {
        await db.deleteBook(this.pendingAddToShelfBookUrl, 'temporary_read_declined');
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }
    } catch (e) {
      console.error('移除临时阅读书籍失败:', e);
    }
    this.promptAddToShelfAfterRead = false;
    this.pendingAddToShelfBookUrl = '';
    this.isInShelf = false;
  }

  async keepPendingReadBookInShelf(): Promise<boolean> {
    if (!this.pendingAddToShelfBookUrl) {
      return await this.addToShelf();
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const pendingBook = await db.getBook(this.pendingAddToShelfBookUrl);
      if (pendingBook) {
        SearchExplorePendingBook.clearPendingAddToShelf(pendingBook);
        await db.updateBook(pendingBook, true, 'temporary_read_kept');
        this.syncStateFromBook(pendingBook);
        this.isInShelf = true;
        this.promptAddToShelfAfterRead = false;
        this.pendingAddToShelfBookUrl = '';
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        promptAction.showToast({ message: '已加入书架' });
        return true;
      }
    } catch (e) {
      console.error('加入书架失败:', e);
      promptAction.showToast({ message: '加入书架失败' });
      return false;
    }
    return await this.addToShelf();
  }

  async confirmAddToShelfOnBack(): Promise<void> {
    this.showAddToShelfOnBackDialog = false;
    const ok = await this.keepPendingReadBookInShelf();
    if (ok) {
      router.back();
    }
  }

  async prepareBookForReading(): Promise<boolean> {
    if (!this.bookUrl) {
      promptAction.showToast({ message: '书籍地址为空' });
      return false;
    }

    this.isSaving = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const requestKey = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
      const existing = await db.getBook(this.bookUrl) || await this.findShelfBookByKey(requestKey, true);
      if (existing) {
        let bookChanged = false;
        const inferredType = this.bookType || BookTypeSupport.typeFromVariable(this.bookVariable);
        if (inferredType && existing.type !== inferredType) {
          existing.type = inferredType;
          bookChanged = true;
        }
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
          bookChanged = true;
        }
        if (this.mergeResolvedDetailIntoBook(existing)) {
          bookChanged = true;
        }
        if (bookChanged) {
          await db.updateBook(existing, true, 'prepare_read_update_existing');
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
        this.syncStateFromBook(existing);
        if (SearchExplorePendingBook.isPendingAddToShelf(existing)) {
          this.isInShelf = false;
          this.promptAddToShelfAfterRead = this.promptAddToShelfOnBackFromResult;
          this.pendingAddToShelfBookUrl = existing.bookUrl;
        } else {
          this.isInShelf = true;
          this.promptAddToShelfAfterRead = false;
          this.pendingAddToShelfBookUrl = '';
        }
        return true;
      }

      const book = await this.buildBookForShelf();
      const resolvedExisting = await this.findShelfBookByKey(BookIdentity.keyOfBook(book), true);
      if (resolvedExisting) {
        if (this.mergeResolvedDetailIntoBook(resolvedExisting)) {
          await db.updateBook(resolvedExisting, true, 'prepare_read_update_resolved');
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
        this.syncStateFromBook(resolvedExisting);
        if (SearchExplorePendingBook.isPendingAddToShelf(resolvedExisting)) {
          this.isInShelf = false;
          this.promptAddToShelfAfterRead = this.promptAddToShelfOnBackFromResult;
          this.pendingAddToShelfBookUrl = resolvedExisting.bookUrl;
        } else {
          this.isInShelf = true;
          this.promptAddToShelfAfterRead = false;
          this.pendingAddToShelfBookUrl = '';
        }
        return true;
      }
      SearchExplorePendingBook.markPendingAddToShelf(book);
      await db.insertBook(book, 'temporary_read_insert');
      this.syncStateFromBook(book);
      this.isInShelf = false;
      this.promptAddToShelfAfterRead = this.promptAddToShelfOnBackFromResult;
      this.pendingAddToShelfBookUrl = book.bookUrl;
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      return true;
    } catch (e) {
      console.error('准备阅读失败:', e);
      promptAction.showToast({ message: '打开阅读失败' });
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  private mergeResolvedDetailIntoBook(book: Book): boolean {
    let changed = false;
    const kind = BookFieldSanitizer.prefer(this.kind, book.kind);
    const status = BookFieldSanitizer.prefer(this.status, book.status);
    const intro = BookFieldSanitizer.prefer(this.intro, book.intro);
    const latestChapterTitle = BookFieldSanitizer.prefer(this.latestChapterTitle, book.latestChapterTitle);
    const wordCount = BookFieldSanitizer.prefer(this.wordCount, book.wordCount);
    const updateTime = BookFieldSanitizer.prefer(this.updateTime, book.updateTime);
    if (kind !== book.kind) {
      book.kind = kind;
      changed = true;
    }
    if (status !== book.status) {
      book.status = status;
      changed = true;
    }
    if (intro !== book.intro) {
      book.intro = intro;
      changed = true;
    }
    if (latestChapterTitle !== book.latestChapterTitle) {
      book.latestChapterTitle = latestChapterTitle;
      changed = true;
    }
    if (wordCount !== book.wordCount) {
      book.wordCount = wordCount;
      changed = true;
    }
    if (updateTime !== book.updateTime) {
      book.updateTime = updateTime;
      changed = true;
    }
    if (this.tocUrl && this.tocUrl !== book.tocUrl) {
      book.tocUrl = this.tocUrl;
      changed = true;
    }
    if (this.bookVariable && this.bookVariable !== book.variable) {
      book.variable = this.bookVariable;
      changed = true;
    }
    return changed;
  }

  async buildBookForShelf(): Promise<Book> {
    const book = new Book();
    book.bookUrl = this.bookUrl;
    book.tocUrl = this.tocUrl;
    book.origin = this.origin;
    book.originName = this.originName;
    book.name = this.name;
    book.author = this.author;
    book.kind = BookFieldSanitizer.clean(this.kind);
    book.status = BookFieldSanitizer.clean(this.status);
    book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
    book.intro = BookFieldSanitizer.clean(this.intro);
    book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.clean(this.wordCount);
    book.group = -2147483645;
    book.type = this.bookType;
    book.variable = this.bookVariable;
    BookTypeSupport.applyBookType(book);
    book.canUpdate = true;
    book.lastCheckTime = Date.now();
    book.latestChapterTime = Date.now();
    const fallbackCoverUrl = book.coverUrl;
    const fullBook = await this.resolveBookInfo();
    if (fullBook) {
      book.bookUrl = fullBook.bookUrl || book.bookUrl;
      book.tocUrl = fullBook.tocUrl || book.tocUrl;
      book.name = fullBook.name || book.name;
      book.author = fullBook.author || book.author;
      book.kind = BookFieldSanitizer.prefer(fullBook.kind, book.kind);
      book.status = BookFieldSanitizer.prefer(fullBook.status, book.status);
      book.coverUrl = CoverUrlNormalizer.prefer(fallbackCoverUrl, fullBook.coverUrl || book.coverUrl);
      book.intro = BookFieldSanitizer.prefer(fullBook.intro, book.intro);
      book.latestChapterTitle = BookFieldSanitizer.prefer(fullBook.latestChapterTitle, book.latestChapterTitle);
      book.updateTime = BookFieldSanitizer.prefer(fullBook.updateTime, book.updateTime);
      book.wordCount = BookFieldSanitizer.prefer(fullBook.wordCount, book.wordCount);
      book.variable = fullBook.variable || book.variable;
      book.type = fullBook.type || book.type;
    }
    return book;
  }

  @Builder
  addToShelfOnBackDialog() {
    Column() {
      Column() {
        Text('加入书架')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 12 })

        Text(`是否将《${this.name || '这本书'}》加入书架？`)
          .fontSize(15)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 20 })

        Row() {
          Button('不加入')
            .width('45%')
            .height(44)
            .backgroundColor(this.appDarkMode ? '#24272D' : '#F5F5F5')
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.dismissAddToShelfOnBackPrompt();
            })

          Button('加入书架')
            .width('45%')
            .height(44)
            .backgroundColor(this.buttonColor())
            .onClick(() => {
              this.confirmAddToShelfOnBack();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('85%')
      .padding(24)
      .backgroundColor(this.cardColor())
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (!this.isSaving) {
        this.dismissAddToShelfOnBackPrompt();
      }
    })
  }

  async findShelfBookByKey(bookKey: string, includePending: boolean = false): Promise<Book | null> {
    return SearchBookShelfHelper.findShelfBookByKey(bookKey, includePending);
  }

  syncStateFromBook(book: Book): void {
    this.bookUrl = book.bookUrl || this.bookUrl;
    this.tocUrl = book.tocUrl || this.tocUrl;
    this.origin = book.origin || this.origin;
    this.originName = book.originName || this.originName;
    this.name = book.name || this.name;
    this.author = book.author || this.author;
    this.kind = book.kind || this.kind;
    this.status = book.status || this.status;
    this.coverUrl = CoverUrlNormalizer.prefer(book.coverUrl, this.coverUrl);
    this.intro = book.intro || this.intro;
    this.latestChapterTitle = book.latestChapterTitle || this.latestChapterTitle;
    this.wordCount = book.wordCount || this.wordCount;
    this.updateTime = book.updateTime || this.updateTime;
    this.bookType = book.type || this.bookType;
    this.bookVariable = book.variable || this.bookVariable;
    this.bookInfoRenderVersion++;
  }

  detailTypeProbe(): Book {
    const book = new Book();
    book.origin = this.origin;
    book.originName = this.originName;
    book.kind = this.kind;
    book.type = this.bookType;
    book.variable = this.bookVariable;
    return book;
  }

  /**
   * The catalog card shows a chapter count that only exists after the catalog has been fetched at
   * least once. Prefer the stored column and fall back to counting the cached chapter rows.
   */
  private async refreshChapterCount(): Promise<void> {
    if (!this.bookUrl) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const book = await db.getBook(this.bookUrl);
      const stored = book ? book.totalChapterNum : 0;
      this.totalChapterNum = stored > 0 ? stored : await db.getBookChapterCount(this.bookUrl);
    } catch (e) {
      console.warn('读取章节总数失败:', e);
    }
  }

  openChapterList(): void {
    if (!this.bookUrl || !this.origin) {
      promptAction.showToast({ message: '书籍信息不完整，暂时无法查看目录' });
      return;
    }
    router.pushUrl({
      url: 'pages/BookChapterList',
      params: {
        bookUrl: this.bookUrl,
        tocUrl: this.tocUrl,
        origin: this.origin,
        originName: this.originName,
        name: this.name,
        author: this.author,
        kind: this.kind,
        status: this.status,
        coverUrl: this.coverUrl,
        intro: this.intro,
        latestChapterTitle: this.latestChapterTitle,
        wordCount: this.wordCount,
        updateTime: this.updateTime,
        type: `${this.bookType}`,
        // Directory rules that carry an init script write back into book.variable; without it the
        // catalog comes back empty for those sources.
        variable: this.bookVariable
      }
    });
  }

  async startRead() {
    const ok = await this.prepareBookForReading();
    if (!ok) return;

    router.pushUrl({
      url: 'pages/ReadBook',
      params: { bookUrl: this.bookUrl }
    });
  }

  triggerAutoStartRead(): void {
    if (!this.autoStartRead || this.autoStartReadTriggered || !this.bookUrl) return;
    this.autoStartReadTriggered = true;
    // Let the detail page mount before preparing the transient reader record and routing to ReadBook.
    setTimeout((): void => {
      this.startRead();
    }, 0);
  }

  getTags(): string[] {
    return BookDisplayHelper.splitTags(this.kind, this.status);
  }

  displayCoverUrl(): string {
    if (this.searchExploreUseBookshelfCoverGallery) {
      const galleryCover = this.bookshelfGalleryCoverUrl();
      if (galleryCover) {
        return galleryCover;
      }
    }
    return this.coverUrl;
  }

  bookshelfGalleryCoverUrl(): string {
    const book = new Book();
    book.name = this.name;
    book.author = this.author;
    book.bookUrl = this.bookUrl;
    book.coverUrl = this.coverUrl;
    const covers = CoverGallerySettings.getDisplayCoverList(
      book,
      this.appDarkMode,
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
      .backgroundColor(this.accentColor())

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
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
