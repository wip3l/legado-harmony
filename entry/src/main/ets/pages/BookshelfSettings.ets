import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book } from '../model/data/Book';
import { CoverAlbum, CoverGallerySettings } from '../utils/CoverGallerySettings';
import { CoverGalleryStore, CoverGallerySnapshot } from '../utils/CoverGalleryStore';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { BookshelfDisplaySettings, BookshelfDisplaySettingsStore } from '../utils/BookshelfDisplaySettingsStore';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';

@Entry
@Component
struct BookshelfSettingsPage {
  @StorageLink('bookshelfShowTags') bookshelfShowTags: boolean = true;
  @StorageLink('bookshelfShowIntro') bookshelfShowIntro: boolean = true;
  @StorageLink('bookshelfShowFullIntro') bookshelfShowFullIntro: boolean = false;
  @StorageLink('bookshelfCoverAlbums') @Watch('onCoverAlbumsChanged') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverApplyScope') bookshelfCoverApplyScope: string = 'all';
  @StorageLink('bookshelfCoverTargetBooks') bookshelfCoverTargetBooks: string = '';
  @StorageLink('bookshelfIgnoreSourceCover') bookshelfIgnoreSourceCover: boolean = false;
  @StorageLink('bookshelfCoverMode') bookshelfCoverMode: string = 'sequence';
  @StorageLink('coverGalleryUpdateTime') @Watch('onCoverGalleryUpdateTimeChanged') coverGalleryUpdateTime: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State albums: CoverAlbum[] = [];
  @State albumSelectOptions: SelectOption[] = [{ value: '不使用图集' }];
  @State books: Book[] = [];

  aboutToAppear(): void {
    this.reloadCoverSettings();
    this.reloadDisplaySettings();
    this.loadBooks();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadCoverSettings();
    this.reloadDisplaySettings();
    this.loadBooks();
    this.syncBars();
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('书籍信息')
          this.switchItem('书籍标签', '控制书架卡片是否显示书籍标签', this.bookshelfShowTags, (value: boolean) => {
            this.bookshelfShowTags = value;
            this.onDisplaySettingChanged();
          })
          this.switchItem('书籍简介', '开启后显示书源抓取的简介内容', this.bookshelfShowIntro, (value: boolean) => {
            this.bookshelfShowIntro = value;
            this.onDisplaySettingChanged();
          })
          if (this.bookshelfShowIntro) {
            this.switchItem('显示全部简介', '开启后书架卡片显示完整简介内容', this.bookshelfShowFullIntro, (value: boolean) => {
              this.bookshelfShowFullIntro = value;
              this.onDisplaySettingChanged();
            })
          }

          this.sectionTitle('封面设置')
          this.switchItem('忽略书源封面', '开启后书架封面只使用当前应用的封面图集', this.bookshelfIgnoreSourceCover, (value: boolean) => {
            this.bookshelfIgnoreSourceCover = value;
            this.onCoverSettingChanged();
          })
          this.selectItem('封面模式', '控制多张封面的展示顺序',
            this.modeOptions(), this.modeSelectedIndex(), (index: number) => {
              this.bookshelfCoverMode = index === 1 ? 'random' : 'sequence';
              this.onCoverSettingChanged();
            })
          this.selectItem('浅色配色图集', '浅色模式下使用的封面图集',
            this.albumOptions(), this.albumSelectedIndex(false), (index: number) => {
              this.setThemeAlbum(false, this.albumIdByIndex(index));
            })
          this.selectItem('深色配色图集', '深色模式下使用的封面图集',
            this.albumOptions(), this.albumSelectedIndex(true), (index: number) => {
              this.setThemeAlbum(true, this.albumIdByIndex(index));
            })
          this.selectItem('图集应用范围', '选择图集作用于全部书籍或指定书籍',
            this.scopeOptions(), this.scopeSelectedIndex(), (index: number) => {
              this.bookshelfCoverApplyScope = index === 1 ? 'books' : 'all';
              this.onCoverSettingChanged();
            })

          if (this.bookshelfCoverApplyScope === 'books') {
            this.targetBooksPanel()
          }

          this.sectionTitle('封面图集')
          this.navItem('图集管理', '新建图集、导入图片、重命名和预览封面', 'pages/CoverGalleryManager')
        }
        .width('100%')
        .padding({ bottom: 32 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  loadAlbums(): void {
    this.syncAlbums(this.bookshelfCoverAlbums);
  }

  onCoverAlbumsChanged(): void {
    this.loadAlbums();
  }

  onCoverGalleryUpdateTimeChanged(): void {
    this.reloadCoverSettings();
  }

  async reloadCoverSettings(): Promise<void> {
    try {
      const snapshot = await CoverGalleryStore.load(getContext(this));
      this.applySnapshot(snapshot);
    } catch (e) {
      console.warn('重新加载封面图集设置失败:', e);
      this.loadAlbums();
    }
  }

  async reloadDisplaySettings(): Promise<void> {
    try {
      const settings = await BookshelfDisplaySettingsStore.load(getContext(this));
      this.bookshelfShowTags = settings.showTags;
      this.bookshelfShowIntro = settings.showIntro;
      this.bookshelfShowFullIntro = settings.showFullIntro;
    } catch (e) {
      console.warn('重新加载书架显示设置失败:', e);
    }
  }

  onDisplaySettingChanged(): void {
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    const settings = new BookshelfDisplaySettings();
    settings.showTags = this.bookshelfShowTags;
    settings.showIntro = this.bookshelfShowIntro;
    settings.showFullIntro = this.bookshelfShowFullIntro;
    BookshelfDisplaySettingsStore.applyToStorage(settings);
    BookshelfDisplaySettingsStore.save(getContext(this), settings).catch((e: Error) => {
      console.warn('保存书架显示设置失败:', e);
    });
  }

  applySnapshot(snapshot: CoverGallerySnapshot): void {
    const localAlbumsRaw = this.bookshelfCoverAlbums;
    const albumsRaw = this.hasAlbumPayload(snapshot.albumsRaw) || !this.hasAlbumPayload(localAlbumsRaw) ?
      snapshot.albumsRaw : localAlbumsRaw;
    this.bookshelfCoverAlbums = albumsRaw;
    this.bookshelfLightCoverAlbumId = snapshot.lightAlbumId;
    this.bookshelfDarkCoverAlbumId = snapshot.darkAlbumId;
    this.bookshelfCoverApplyScope = snapshot.applyScope;
    this.bookshelfCoverTargetBooks = snapshot.targetBooksRaw;
    this.bookshelfIgnoreSourceCover = snapshot.ignoreSourceCover;
    this.bookshelfCoverMode = snapshot.coverMode;
    this.syncAlbums(albumsRaw);
  }

  async loadBooks(): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.books = SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks());
    } catch (e) {
      console.warn('加载书籍列表失败:', e);
      this.books = [];
    }
  }

  setThemeAlbum(dark: boolean, albumId: string): void {
    if (dark) {
      this.bookshelfDarkCoverAlbumId = albumId;
    } else {
      this.bookshelfLightCoverAlbumId = albumId;
    }
    this.onCoverSettingChanged();
  }

  toggleTargetBook(book: Book, selected: boolean): void {
    this.toggleTargetBookUrl(book.bookUrl, selected);
  }

  toggleTargetBookUrl(bookUrl: string, selected: boolean): void {
    if (!bookUrl) {
      return;
    }
    const targets = CoverGallerySettings.parseTargetBooks(this.bookshelfCoverTargetBooks);
    if (selected && !targets.includes(bookUrl)) {
      targets.push(bookUrl);
    }
    if (!selected) {
      const index = targets.indexOf(bookUrl);
      if (index >= 0) {
        targets.splice(index, 1);
      }
    }
    this.bookshelfCoverTargetBooks = CoverGallerySettings.encodeTargetBooks(targets);
    this.onCoverSettingChanged();
  }

  onCoverSettingChanged(): void {
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    AppStorage.setOrCreate('coverGalleryUpdateTime', Date.now());
    const snapshot = this.currentSnapshot();
    CoverGalleryStore.applyToStorage(snapshot);
    CoverGalleryStore.save(getContext(this), snapshot).then(() => {
      RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext);
    }).catch((e: Error) => {
      console.warn('保存封面图集设置失败:', e);
    });
  }

  currentSnapshot(): CoverGallerySnapshot {
    const snapshot = new CoverGallerySnapshot();
    snapshot.albumsRaw = this.bookshelfCoverAlbums;
    snapshot.lightAlbumId = this.bookshelfLightCoverAlbumId;
    snapshot.darkAlbumId = this.bookshelfDarkCoverAlbumId;
    snapshot.applyScope = this.bookshelfCoverApplyScope;
    snapshot.targetBooksRaw = this.bookshelfCoverTargetBooks;
    snapshot.ignoreSourceCover = this.bookshelfIgnoreSourceCover;
    snapshot.coverMode = this.bookshelfCoverMode;
    return snapshot;
  }

  isTargetBook(book: Book): boolean {
    return this.isTargetBookUrl(book.bookUrl);
  }

  isTargetBookUrl(bookUrl: string): boolean {
    return !!bookUrl && CoverGallerySettings.parseTargetBooks(this.bookshelfCoverTargetBooks).includes(bookUrl);
  }

  targetBookKey(book: Book): string {
    return book.bookUrl || `${book.origin}_${book.name}_${book.author}`;
  }

  modeOptions(): SelectOption[] {
    return [{ value: '顺序' }, { value: '随机' }];
  }

  modeSelectedIndex(): number {
    return this.bookshelfCoverMode === 'random' ? 1 : 0;
  }

  albumOptions(): SelectOption[] {
    return this.albumSelectOptions;
  }

  syncAlbums(raw: string): void {
    this.albums = CoverGallerySettings.parseAlbums(raw);
    const options: SelectOption[] = [{ value: '不使用图集' }];
    for (const album of this.albums) {
      options.push({ value: `${album.name}(${album.covers.length})` });
    }
    this.albumSelectOptions = options;
  }

  hasAlbumPayload(raw: string): boolean {
    return (raw || '').trim().length > 0;
  }

  albumSelectedIndex(dark: boolean): number {
    const selectedId = dark ? this.bookshelfDarkCoverAlbumId : this.bookshelfLightCoverAlbumId;
    for (let i = 0; i < this.albums.length; i++) {
      if (this.albums[i].id === selectedId) {
        return i + 1;
      }
    }
    return 0;
  }

  albumIdByIndex(index: number): string {
    if (index <= 0 || index - 1 >= this.albums.length) {
      return '';
    }
    return this.albums[index - 1].id;
  }

  scopeOptions(): SelectOption[] {
    return [{ value: '全部应用' }, { value: '指定书籍' }];
  }

  scopeSelectedIndex(): number {
    return this.bookshelfCoverApplyScope === 'books' ? 1 : 0;
  }

  optionValue(options: SelectOption[], index: number): ResourceStr {
    if (index >= 0 && index < options.length) {
      return options[index].value;
    }
    return '';
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#888';
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F0F2F5';
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleBar() {
    Row() {
      Text('<')
        .fontSize(24)
        .fontColor(this.primaryTextColor())
        .width(40)
        .height(56)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Text('书架设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }

  @Builder
  switchItem(title: string, desc: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange((checked: boolean) => {
          onChange(checked);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  selectItem(title: string, desc: string, options: SelectOption[], selected: number, onSelect: (index: number) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Select(options)
        .selected(selected)
        .value(this.optionValue(options, selected))
        .font({ size: 14 })
        .fontColor(this.primaryTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(8)
        .onSelect((index: number) => {
          onSelect(index);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 66 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  targetBooksPanel() {
    Column({ space: 2 }) {
      ForEach(this.books, (book: Book) => {
        Row() {
          Text(book.name || '未命名书籍')
            .fontSize(14)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          this.targetBookSwitch(book, this.isTargetBook(book))
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
      }, (book: Book) => this.targetBookKey(book))
    }
    .width('100%')
    .backgroundColor(this.cardColor())
  }

  @Builder
  targetBookSwitch(book: Book, selected: boolean) {
    Row() {
      Circle()
        .width(22)
        .height(22)
        .fill('#FFFFFF')
        .shadow({ radius: 2, color: '#33000000', offsetX: 0, offsetY: 1 })
    }
    .width(48)
    .height(28)
    .padding(3)
    .borderRadius(14)
    .backgroundColor(selected ? '#007DFF' : (this.appDarkMode ? '#3A3D44' : '#D8DCE3'))
    .justifyContent(selected ? FlexAlign.End : FlexAlign.Start)
    .onClick(() => {
      this.toggleTargetBook(book, !selected);
    })
  }

  @Builder
  navItem(title: string, desc: string, url: string) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('>')
        .fontSize(18)
        .fontColor(this.subTextColor())
        .width(24)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: 66 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url });
    })
  }
}
