import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book } from '../model/data/Book';
import { CoverAlbum, CoverGallerySettings } from '../utils/CoverGallerySettings';
import { CoverGalleryStore, CoverGallerySnapshot } from '../utils/CoverGalleryStore';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { BookshelfDisplaySettings, BookshelfDisplaySettingsStore } from '../utils/BookshelfDisplaySettingsStore';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';
import { ThemeRuntime } from '../theme/ThemeRuntime';

@Entry
@Component
struct BookshelfSettingsPage {
  @StorageLink('bookshelfShowTags') bookshelfShowTags: boolean = true;
  @StorageLink('bookshelfShowSource') bookshelfShowSource: boolean = true;
  @StorageLink('bookshelfShowIntro') bookshelfShowIntro: boolean = true;
  @StorageLink('bookshelfShowFullIntro') bookshelfShowFullIntro: boolean = false;
  @StorageLink('bookshelfShowProgressBar') bookshelfShowProgressBar: boolean = false;
  @StorageLink('bookshelfShowLastReadTime') bookshelfShowLastReadTime: boolean = true;
  @StorageLink('bookshelfShowLastReadChapter') bookshelfShowLastReadChapter: boolean = false;
  @StorageLink('bookshelfLayoutMode') bookshelfLayoutMode: string = 'compact';
  @StorageLink('bookshelfCoverAlbums') @Watch('onCoverAlbumsChanged') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverApplyScope') bookshelfCoverApplyScope: string = 'all';
  @StorageLink('bookshelfCoverTargetBooks') bookshelfCoverTargetBooks: string = '';
  @StorageLink('bookshelfIgnoreSourceCover') bookshelfIgnoreSourceCover: boolean = false;
  @StorageLink('bookshelfCoverMode') bookshelfCoverMode: string = 'sequence';
  @StorageLink('coverGalleryUpdateTime') @Watch('onCoverGalleryUpdateTimeChanged') coverGalleryUpdateTime: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State albums: CoverAlbum[] = [];
  @State albumSelectOptions: SelectOption[] = [{ value: '不使用图集' }];
  @State books: Book[] = [];
  @State targetBookUrls: string[] = [];
  @State targetBooksLoading: boolean = false;
  @State showTargetBookList: boolean = false;
  @State settingsRenderTick: number = 0;
  private skipNextCoverGalleryReload: boolean = false;

  aboutToAppear(): void {
    this.reloadCoverSettings();
    this.reloadDisplaySettings();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadCoverSettings();
    this.reloadDisplaySettings();
    this.syncBars();
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('书籍信息')
          Column() {
          this.switchItem('书籍标签', '控制书架卡片是否显示书籍标签', this.bookshelfShowTags, (value: boolean) => {
            this.bookshelfShowTags = value;
            this.onDisplaySettingChanged();
          })
          this.itemDivider()
          this.switchItem('书籍来源', '控制书架卡片是否显示书籍来源', this.bookshelfShowSource, (value: boolean) => {
            this.bookshelfShowSource = value;
            this.onDisplaySettingChanged();
          })
          this.itemDivider()
          this.switchItem('书籍简介', '开启后显示书源抓取的简介内容', this.bookshelfShowIntro, (value: boolean) => {
            this.bookshelfShowIntro = value;
            this.onDisplaySettingChanged();
          })
          if (this.bookshelfShowIntro) {
            this.itemDivider()
            this.switchItem('显示全部简介', '开启后书架卡片显示完整简介内容', this.bookshelfShowFullIntro, (value: boolean) => {
              this.bookshelfShowFullIntro = value;
              this.onDisplaySettingChanged();
            })
          }
          this.itemDivider()
          this.switchItem('使用阅读进度条', '开启后在书架卡片底部显示阅读百分比和阅读信息', this.bookshelfShowProgressBar, (value: boolean) => {
            this.bookshelfShowProgressBar = value;
            this.onDisplaySettingChanged();
          })
          if (this.bookshelfShowProgressBar) {
            this.itemDivider()
            this.switchItem('显示最后阅读时间', '开启后阅读进度条旁显示最近一次阅读时间', this.bookshelfShowLastReadTime, (value: boolean) => {
              this.bookshelfShowLastReadTime = value;
              this.onDisplaySettingChanged();
            })
            this.itemDivider()
            this.switchItem('显示最后阅读章节', '开启后阅读进度条旁显示最近一次阅读章节', this.bookshelfShowLastReadChapter, (value: boolean) => {
              this.bookshelfShowLastReadChapter = value;
              this.onDisplaySettingChanged();
            })
          }
          this.itemDivider()
          this.selectItem('书架布局', '切换列表信息密度或封面平铺展示',
            this.bookshelfLayoutOptions(), this.bookshelfLayoutSelectedIndex(), (index: number) => {
              this.bookshelfLayoutMode = index === 2 ? 'tile' : (index === 1 ? 'loose' : 'compact');
              this.onDisplaySettingChanged();
            })

          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('本地书籍')
          Column() {
            this.navItem('添加书籍', '选择并导入 TXT 和 EPUB 书籍文件', 'pages/LocalBookSettings')
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('封面设置')
          Column() {
          this.switchItem('忽略原始封面', '开启后书架封面只使用当前应用的封面图集', this.bookshelfIgnoreSourceCover, (value: boolean) => {
            this.bookshelfIgnoreSourceCover = value;
            this.onCoverSettingChanged();
          })
          this.itemDivider()
          this.selectItem('封面模式', '控制多张封面的展示顺序',
            this.modeOptions(), this.modeSelectedIndex(), (index: number) => {
              this.bookshelfCoverMode = index === 1 ? 'random' : 'sequence';
              this.onCoverSettingChanged();
            })
          this.itemDivider()
          this.albumSelectItem('浅色配色图集', '浅色模式下使用的封面图集', false)
          this.itemDivider()
          this.albumSelectItem('深色配色图集', '深色模式下使用的封面图集', true)
          this.itemDivider()
          this.selectItem('图集应用范围', '选择图集作用于全部书籍或指定书籍',
            this.scopeOptions(), this.scopeSelectedIndex(), (index: number) => {
              this.setCoverApplyScope(index === 1 ? 'books' : 'all');
            })

          if (this.showTargetBookList) {
            this.itemDivider()
            this.targetBooksPanel()
          }
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('封面图集')
          Column() {
            this.navItem('图集管理', '新建图集、导入图片、重命名和预览封面', 'pages/CoverGalleryManager')
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())
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
    if (this.skipNextCoverGalleryReload) {
      this.skipNextCoverGalleryReload = false;
      return;
    }
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
      this.bookshelfShowSource = settings.showSource;
      this.bookshelfShowIntro = settings.showIntro;
      this.bookshelfShowFullIntro = settings.showFullIntro;
      this.bookshelfShowProgressBar = settings.showProgressBar;
      this.bookshelfShowLastReadTime = settings.showLastReadTime;
      this.bookshelfShowLastReadChapter = settings.showLastReadChapter;
      this.bookshelfLayoutMode = settings.layoutMode;
    } catch (e) {
      console.warn('重新加载书架显示设置失败:', e);
    }
  }

  onDisplaySettingChanged(): void {
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    const settings = new BookshelfDisplaySettings();
    settings.showTags = this.bookshelfShowTags;
    settings.showSource = this.bookshelfShowSource;
    settings.showIntro = this.bookshelfShowIntro;
    settings.showFullIntro = this.bookshelfShowFullIntro;
    settings.showProgressBar = this.bookshelfShowProgressBar;
    settings.showLastReadTime = this.bookshelfShowLastReadTime;
    settings.showLastReadChapter = this.bookshelfShowLastReadChapter;
    settings.layoutMode = this.bookshelfLayoutMode;
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
    this.showTargetBookList = snapshot.applyScope === 'books';
    this.bookshelfCoverTargetBooks = snapshot.targetBooksRaw;
    this.targetBookUrls = CoverGallerySettings.parseTargetBooks(snapshot.targetBooksRaw);
    this.bookshelfIgnoreSourceCover = snapshot.ignoreSourceCover;
    this.bookshelfCoverMode = snapshot.coverMode;
    this.syncAlbums(albumsRaw);
    this.bumpSettingsRender();
    if (this.showTargetBookList) {
      this.loadBooks();
    } else {
      this.books = [];
      this.targetBooksLoading = false;
    }
  }

  async loadBooks(): Promise<void> {
    this.targetBooksLoading = true;
    this.bumpSettingsRender();
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.books = SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks()).slice();
    } catch (e) {
      console.warn('加载书籍列表失败:', e);
      this.books = [];
    } finally {
      this.targetBooksLoading = false;
      this.bumpSettingsRender();
    }
  }

  setCoverApplyScope(scope: string): void {
    const nextScope = scope === 'books' ? 'books' : 'all';
    this.showTargetBookList = nextScope === 'books';
    this.bookshelfCoverApplyScope = nextScope;
    this.bumpSettingsRender();
    if (this.showTargetBookList) {
      this.loadBooks();
    } else {
      this.books = [];
      this.targetBooksLoading = false;
    }
    this.onCoverSettingChanged();
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
    const targets = this.targetBookUrls.slice();
    if (selected && !targets.includes(bookUrl)) {
      targets.push(bookUrl);
    }
    if (!selected) {
      const index = targets.indexOf(bookUrl);
      if (index >= 0) {
        targets.splice(index, 1);
      }
    }
    this.targetBookUrls = targets.slice();
    this.bookshelfCoverTargetBooks = CoverGallerySettings.encodeTargetBooks(this.targetBookUrls);
    this.bumpSettingsRender();
    this.onCoverSettingChanged();
  }

  bumpSettingsRender(): void {
    this.settingsRenderTick++;
  }

  onCoverSettingChanged(): void {
    const snapshot = this.currentSnapshot();
    CoverGalleryStore.applyToStorage(snapshot);
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    this.skipNextCoverGalleryReload = true;
    AppStorage.setOrCreate('coverGalleryUpdateTime', Date.now());
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
    snapshot.applyScope = this.showTargetBookList ? 'books' : 'all';
    snapshot.targetBooksRaw = this.bookshelfCoverTargetBooks;
    snapshot.ignoreSourceCover = this.bookshelfIgnoreSourceCover;
    snapshot.coverMode = this.bookshelfCoverMode;
    return snapshot;
  }

  isTargetBook(book: Book): boolean {
    return this.isTargetBookUrl(book.bookUrl);
  }

  isTargetBookUrl(bookUrl: string): boolean {
    return !!bookUrl && this.targetBookUrls.includes(bookUrl);
  }

  targetBookKey(book: Book): string {
    const bookUrl = book.bookUrl || `${book.origin}_${book.name}_${book.author}`;
    return `${bookUrl}_${this.settingsRenderTick}_${this.isTargetBookUrl(book.bookUrl) ? 'on' : 'off'}`;
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

  refreshAlbumOptionsForMenu(): void {
    const latestRaw = AppStorage.get<string>('bookshelfCoverAlbums');
    const raw = latestRaw !== undefined ? latestRaw : this.bookshelfCoverAlbums;
    if (raw !== this.bookshelfCoverAlbums) {
      this.bookshelfCoverAlbums = raw;
    }
    this.syncAlbums(raw);
    this.bumpSettingsRender();
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

  bookshelfLayoutOptions(): SelectOption[] {
    return [{ value: '紧凑' }, { value: '宽松' }, { value: '平铺' }];
  }

  bookshelfLayoutSelectedIndex(): number {
    return this.bookshelfLayoutMode === 'tile' ? 2 : (this.bookshelfLayoutMode === 'loose' ? 1 : 0);
  }

  scopeSelectedIndex(): number {
    return this.showTargetBookList ? 1 : 0;
  }

  optionValue(options: SelectOption[], index: number): ResourceStr {
    if (index >= 0 && index < options.length) {
      return options[index].value;
    }
    return '';
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        onBack: () => router.back() })
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
  itemDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(this.appDarkMode ? '#24FFFFFF' : '#14000000')
      .width('calc(100% - 32vp)')
      .margin({ left: 16, right: 16 })
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
        .selectedColor(this.buttonColor())
        .onChange((checked: boolean) => {
          onChange(checked);
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
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
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(0)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onSelect((index: number) => {
          onSelect(index);
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 66 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  albumSelectItem(title: string, desc: string, dark: boolean) {
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

      Select(this.albumOptions())
        .selected(this.albumSelectedIndex(dark))
        .value(this.optionValue(this.albumOptions(), this.albumSelectedIndex(dark)))
        .font({ size: 14 })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(0)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.refreshAlbumOptionsForMenu();
          }
        })
        .onSelect((index: number) => {
          this.setThemeAlbum(dark, this.albumIdByIndex(index));
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 66 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  targetBooksPanel() {
    Column({ space: 2 }) {
      if (this.targetBooksLoading) {
        Text('正在加载书籍...')
          .fontSize(13)
          .fontColor(this.subTextColor())
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .textAlign(TextAlign.Start)
      } else if (this.books.length === 0) {
        Text('暂无可选择书籍')
          .fontSize(13)
          .fontColor(this.subTextColor())
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .textAlign(TextAlign.Start)
      } else {
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
    }
    .width('100%')
    .backgroundColor(this.cardColor())
  }

  @Builder
  targetBookSwitch(book: Book, selected: boolean) {
    Toggle({ type: ToggleType.Switch, isOn: selected })
      .selectedColor(this.buttonColor())
      .onChange((checked: boolean) => {
        this.toggleTargetBook(book, checked);
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

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
        .width(24)
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 66 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url });
    })
  }
}
