import { Book } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { BookIdentity } from '../../utils/BookIdentity';
import { BookCoverCache } from '../../utils/BookCoverCache';
import { CoverGallerySettings } from '../../utils/CoverGallerySettings';
import { CoverUrlNormalizer } from '../../utils/CoverUrlNormalizer';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';
import { ThemeBookCoverSettings } from '../../utils/ThemeBookCoverSettings';

/** 所有书籍展示入口共用书架的封面选择规则和多图轮播。 */
@Component
export struct BookCover {
  @Prop @Watch('onBookChanged') bookUrl: string = '';
  @Prop @Watch('onBookChanged') origin: string = '';
  @Prop @Watch('refreshCovers') coverUrl: string = '';
  @Prop @Watch('refreshCovers') customCoverUrl: string = '';
  @Prop @Watch('refreshCovers') name: string = '';
  @Prop @Watch('refreshCovers') author: string = '';
  @Prop @Watch('onBookChanged') useBookshelfCover: boolean = true;
  @Prop placeholderColor: ResourceColor = '#007DFF';
  @Prop cornerRadius: number = 6;
  @Prop decodeWidth: number = 360;
  @Prop decodeHeight: number = 480;
  @StorageProp('appDarkMode') @Watch('refreshCovers') appDarkMode: boolean = false;
  @StorageProp('bookshelfCoverAlbums') @Watch('refreshCovers') albums: string = '';
  @StorageProp('bookshelfLightCoverAlbumId') @Watch('refreshCovers') lightAlbum: string = '';
  @StorageProp('bookshelfDarkCoverAlbumId') @Watch('refreshCovers') darkAlbum: string = '';
  @StorageProp('bookshelfCoverApplyScope') @Watch('refreshCovers') applyScope: string = 'all';
  @StorageProp('bookshelfCoverTargetBooks') @Watch('refreshCovers') targetBooks: string = '';
  @StorageProp('bookshelfIgnoreSourceCover') @Watch('refreshCovers') ignoreSource: boolean = false;
  @StorageProp('bookshelfCoverMode') @Watch('refreshCovers') coverMode: string = 'sequence';
  @StorageProp('appThemeBookCoverEnabled') @Watch('refreshCovers') themeCoverEnabled: boolean = false;
  @StorageProp('themeRevision') @Watch('refreshCovers') themeRevision: number = 0;
  @StorageProp('shelfUpdateTime') @Watch('onBookChanged') shelfUpdateTime: number = 0;
  @StorageProp('sourceCoverRevision') @Watch('notifyReadyCover') sourceCoverRevision: number = 0;
  @State covers: ResourceStr[] = [];
  @State themeFrame: ResourceStr = '';
  @State interval: number = 3500;
  @State activeIndex: number = 0;
  @State loadedRevision: number = 0;
  private shelfBook: Book | null = null;
  private loadedUrls: Set<string> = new Set();
  private requestSerial: number = 0;
  private mounted: boolean = false;
  onReadyCover: (url: ResourceStr) => void = (_url: ResourceStr): void => {};

  aboutToAppear(): void {
    this.mounted = true;
    this.onBookChanged();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.requestSerial++;
  }

  onBookChanged(): void {
    const serial = ++this.requestSerial;
    this.shelfBook = null;
    this.refreshCovers();
    if (!this.mounted || !this.useBookshelfCover || !this.bookUrl) return;
    this.loadShelfBook(serial);
  }

  private async loadShelfBook(serial: number): Promise<void> {
    try {
      await AppDatabase.getInstance().initWithContext(getContext(this));
      let book = await SearchBookShelfHelper.findShelfBookByKey(BookIdentity.keyOfUrl(this.bookUrl, this.origin));
      // 全局播放面板和统计记录只有 bookUrl；普通搜索结果不逐本查询数据库。
      if (!book && !this.origin) book = await AppDatabase.getInstance().getBook(this.bookUrl);
      if (!this.mounted || serial !== this.requestSerial) return;
      this.shelfBook = book;
      this.refreshCovers();
    } catch (error) {
      console.warn('读取书架封面失败:', error);
    }
  }

  coverBook(): Book {
    const book = this.shelfBook || new Book();
    if (!this.shelfBook) {
      book.bookUrl = this.bookUrl;
      book.origin = this.origin;
      book.coverUrl = this.coverUrl;
      book.customCoverUrl = this.customCoverUrl;
      book.name = this.name;
      book.author = this.author;
    }
    return book;
  }

  rawCoverList(): string[] {
    if (!this.useBookshelfCover) {
      const cover = CoverUrlNormalizer.normalize(this.coverUrl);
      return cover ? [cover] : [];
    }
    const book = this.coverBook();
    return CoverGallerySettings.getDisplayCoverList(book, this.appDarkMode, this.albums,
      this.lightAlbum, this.darkAlbum, this.applyScope, this.targetBooks, this.ignoreSource, this.coverMode);
  }

  refreshCovers(): void {
    const themeCover = this.useBookshelfCover && ThemeBookCoverSettings.enabled(this.appDarkMode, this.themeCoverEnabled);
    const covers: ResourceStr[] = themeCover ? ThemeBookCoverSettings.covers(this.coverBook(), this.appDarkMode) : this.rawCoverList();
    this.themeFrame = themeCover ? ThemeBookCoverSettings.frame(this.appDarkMode) : '';
    this.interval = themeCover ? ThemeBookCoverSettings.interval(this.coverBook()) : 3500;
    if (JSON.stringify(covers) !== JSON.stringify(this.covers)) {
      this.covers = covers;
      this.activeIndex = 0;
    }
    this.notifyReadyCover();
  }

  imageCover(raw: ResourceStr): ResourceStr {
    return typeof raw === 'string' && this.sourceCoverRevision >= 0 ? BookCoverCache.displayCover(getContext(this), raw) : raw;
  }

  activeCover(): ResourceStr {
    return this.covers.length > 0 ? this.imageCover(this.covers[this.activeIndex] || this.covers[0]) : '';
  }

  isActiveCoverReady(): boolean {
    return this.loadedRevision >= 0 && this.loadedUrls.has(JSON.stringify(this.activeCover()));
  }

  notifyReadyCover(): void {
    if (this.mounted) this.onReadyCover(this.isActiveCoverReady() ? this.activeCover() : '');
  }

  markLoaded(url: ResourceStr): void {
    if (!url) return;
    const key = JSON.stringify(url);
    if (!this.loadedUrls.has(key)) {
      if (this.loadedUrls.size > 200) this.loadedUrls.clear();
      this.loadedUrls.add(key);
      this.loadedRevision++;
    }
    this.notifyReadyCover();
  }

  @Builder
  coverImage(url: ResourceStr) {
    Image(url)
      .width('100%')
      .height('100%')
      .objectFit(this.themeFrame ? ImageFit.Fill : ImageFit.Cover)
      .sourceSize({ width: this.decodeWidth, height: this.decodeHeight })
      .borderRadius(this.cornerRadius)
      .onComplete(() => this.markLoaded(url))
  }

  build() {
    Stack() {
      if (!this.isActiveCoverReady()) {
        Column() {
          Text((this.name || '书').substring(0, 1))
            .fontSize(24)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.placeholderColor)
      }
      if (this.covers.length === 1) {
        this.coverImage(this.imageCover(this.covers[0]))
      } else if (this.covers.length > 1) {
        Swiper() {
          ForEach(this.covers, (cover: ResourceStr) => {
            this.coverImage(this.imageCover(cover))
          }, (cover: ResourceStr) => JSON.stringify(cover))
        }
        .width('100%')
        .height('100%')
        .index(this.activeIndex)
        .autoPlay(true)
        .interval(this.interval)
        .indicator(false)
        .loop(true)
        .disableSwipe(true)
        .onChange((index: number) => {
          this.activeIndex = index;
          this.notifyReadyCover();
        })
      }
      if (this.themeFrame) {
        Image(this.themeFrame)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.cornerRadius)
    .clip(true)
  }
}
