import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book } from '@legado/sourceengine';
import { CoverAlbum, CoverGallerySettings } from '../utils/CoverGallerySettings';
import { CoverGalleryStore, CoverGallerySnapshot } from '../utils/CoverGalleryStore';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { BookshelfDisplaySettings, BookshelfDisplaySettingsStore } from '../utils/BookshelfDisplaySettingsStore';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { PrivateShelfStore } from '../utils/PrivateShelfStore';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { HdsFeedback } from '../utils/HdsFeedback';
import { LocalBookService } from '../core/book/LocalBookService';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { BookCoverCache } from '../utils/BookCoverCache';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';

@Entry
@Component
struct BookshelfSettingsPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('bookshelfShowTags') bookshelfShowTags: boolean = true;
  @StorageLink('bookshelfShowSource') bookshelfShowSource: boolean = true;
  @StorageLink('bookshelfShowIntro') bookshelfShowIntro: boolean = true;
  @StorageLink('bookshelfShowFullIntro') bookshelfShowFullIntro: boolean = false;
  @StorageLink('bookshelfShowProgressBar') bookshelfShowProgressBar: boolean = false;
  @StorageLink('bookshelfShowLastReadTime') bookshelfShowLastReadTime: boolean = true;
  @StorageLink('bookshelfShowLastReadChapter') bookshelfShowLastReadChapter: boolean = false;
  @StorageLink('bookshelfShowTypeBadge') bookshelfShowTypeBadge: boolean = true;
  @StorageLink('bookshelfLayoutMode') bookshelfLayoutMode: string = 'compact';
  @StorageLink('bookshelfLastReadLeafMode') bookshelfLastReadLeafMode: string = 'adaptive';
  @StorageLink('bookshelfLastReadPinMode') bookshelfLastReadPinMode: string = 'medium';
  @StorageLink('bookshelfBookOpenAnimation') bookshelfBookOpenAnimation: boolean = true;
  @StorageLink('bookshelfCoverAlbums') @Watch('onCoverAlbumsChanged') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverApplyScope') bookshelfCoverApplyScope: string = 'all';
  @StorageLink('bookshelfCoverTargetBooks') bookshelfCoverTargetBooks: string = '';
  @StorageLink('bookshelfIgnoreSourceCover') bookshelfIgnoreSourceCover: boolean = false;
  @StorageLink('bookshelfCoverMode') bookshelfCoverMode: string = 'sequence';
  @StorageLink('coverGalleryUpdateTime') @Watch('onCoverGalleryUpdateTimeChanged') coverGalleryUpdateTime: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';

  @State albums: CoverAlbum[] = [];
  @State albumSelectOptions: SelectOption[] = [{ value: '不使用图集' }];
  @State books: Book[] = [];
  @State targetBookUrls: string[] = [];
  @State targetBooksLoading: boolean = false;
  @State showTargetBookList: boolean = false;
  @State settingsRenderTick: number = 0;
  @StorageLink('privateShelfEnabled') @Watch('onPrivateShelfEnabledChanged') privateShelfEnabled: boolean = false;
  @StorageLink('privateShelfHasPassword') privateShelfHasPassword: boolean = false;
  // 开关的显示值。关闭需要先验证密码，验证期间它与真实状态可以暂时不一致。
  @State privateShelfSwitchOn: boolean = false;
  // 'disable'：关闭隐私书架前验证密码；'password'：设置、修改或清除密码。
  @State privatePasswordDialogMode: string = 'password';
  @State privatePasswordCurrent: string = '';
  @State privatePasswordNew: string = '';
  @State privatePasswordConfirm: string = '';
  @State privatePasswordError: string = '';
  @State privateShelfBusy: boolean = false;
  private privatePasswordDialogSession: SystemDialogSession = new SystemDialogSession();
  private skipNextCoverGalleryReload: boolean = false;

  aboutToAppear(): void {
    this.reloadCoverSettings();
    this.reloadDisplaySettings();
    this.reloadPrivateShelfSettings();
    this.syncBars();
  }

  aboutToDisappear(): void {
    this.privatePasswordDialogSession.close(this.getUIContext());
  }

  onPageShow(): void {
    this.reloadCoverSettings();
    this.reloadDisplaySettings();
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '书架设置', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    this.sectionTitle('书籍信息')
    Column() {
    SettingSwitchRow({
      title: '书籍打开动画',
      description: '点击书籍时播放封面展开动画',
      isOn: this.bookshelfBookOpenAnimation,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfBookOpenAnimation = value;
        this.onDisplaySettingChanged();
      }
    })
    this.itemDivider()
    SettingSwitchRow({
      title: '类型标识',
      description: '书名前标注“书／漫／声”',
      isOn: this.bookshelfShowTypeBadge,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfShowTypeBadge = value;
        this.onDisplaySettingChanged();
      }
    })
    this.itemDivider()
    SettingSwitchRow({
      title: '书籍标签',
      description: '在书架卡片上显示标签',
      isOn: this.bookshelfShowTags,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfShowTags = value;
        this.onDisplaySettingChanged();
      }
    })
    this.itemDivider()
    SettingSwitchRow({
      title: '书籍来源',
      description: '在书架卡片上显示来源',
      isOn: this.bookshelfShowSource,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfShowSource = value;
        this.onDisplaySettingChanged();
      }
    })
    this.itemDivider()
    SettingSwitchRow({
      title: '书籍简介',
      description: '在书架卡片上显示简介',
      isOn: this.bookshelfShowIntro,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfShowIntro = value;
        this.onDisplaySettingChanged();
      }
    })
    if (this.bookshelfShowIntro) {
      this.itemDivider()
      SettingSwitchRow({
        title: '显示全部简介',
        description: '简介不截断，完整显示',
        isOn: this.bookshelfShowFullIntro,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfShowFullIntro = value;
          this.onDisplaySettingChanged();
        }
      })
    }
    this.itemDivider()
    SettingSwitchRow({
      title: '使用阅读进度条',
      description: '在卡片底部显示阅读百分比和阅读信息',
      isOn: this.bookshelfShowProgressBar,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfShowProgressBar = value;
        this.onDisplaySettingChanged();
      }
    })
    if (this.bookshelfShowProgressBar) {
      this.itemDivider()
      SettingSwitchRow({
        title: '显示最后阅读时间',
        description: '在进度条旁显示上次阅读时间',
        isOn: this.bookshelfShowLastReadTime,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfShowLastReadTime = value;
          this.onDisplaySettingChanged();
        }
      })
      this.itemDivider()
      SettingSwitchRow({
        title: '显示最后阅读章节',
        description: '在进度条旁显示上次阅读章节',
        isOn: this.bookshelfShowLastReadChapter,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfShowLastReadChapter = value;
          this.onDisplaySettingChanged();
        }
      })
    }
    this.itemDivider()
    this.selectItem('书架布局', '列表疏密或封面平铺',
      this.bookshelfLayoutOptions(), this.bookshelfLayoutSelectedIndex(), (index: number) => {
        this.bookshelfLayoutMode = index === 2 ? 'tile' : (index === 1 ? 'loose' : 'compact');
        this.onDisplaySettingChanged();
      })
    if (this.bookshelfLayoutMode === 'tile') {
      this.itemDivider()
      this.selectItem('上次阅读置顶', '最近阅读的书排在最前的样式',
        this.lastReadPinOptions(), this.lastReadPinSelectedIndex(), (index: number) => {
          this.bookshelfLastReadPinMode = index === 0 ? 'off' : (index === 2 ? 'large' : 'medium');
          this.onDisplaySettingChanged();
        })
    }
    if (this.bookshelfLayoutMode === 'tile' && this.bookshelfLastReadPinMode === 'medium') {
      this.itemDivider()
      this.selectItem('上次阅读扉页设置', '最近阅读书籍封面右侧的展示内容',
        this.lastReadLeafOptions(), this.lastReadLeafSelectedIndex(), (index: number) => {
          this.bookshelfLastReadLeafMode = index === 0 ? 'bookInfo' :
            (index === 1 ? 'contentPreview' : 'adaptive');
          this.onDisplaySettingChanged();
        })
    }

    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('隐私书架')
    Column() {
      this.privateShelfSwitchItem()
      if (this.privateShelfEnabled) {
        this.itemDivider()
        this.actionItem('隐私书架密码',
          this.privateShelfHasPassword ? '已设置，进入时需输入' : '未设置',
          this.primaryTextColor(), () => {
            this.openPrivatePasswordDialog('password');
          })
        this.itemDivider()
        this.actionItem('重置隐私书架', '删除全部隐私书籍并关闭，忘记密码时使用', ThemeRuntime.dangerColor(this.appDarkMode), () => {
          this.confirmResetPrivateShelf();
        })
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('封面设置')
    Column() {
    SettingSwitchRow({
      title: '忽略原始封面',
      description: '书架封面只用应用内的封面图集',
      isOn: this.bookshelfIgnoreSourceCover,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfIgnoreSourceCover = value;
        this.onCoverSettingChanged();
      }
    })
    this.itemDivider()
    this.selectItem('封面模式', '多张封面的展示顺序',
      this.modeOptions(), this.modeSelectedIndex(), (index: number) => {
        this.bookshelfCoverMode = index === 1 ? 'random' : 'sequence';
        this.onCoverSettingChanged();
      })
    this.itemDivider()
    this.albumSelectItem('浅色配色图集', '浅色模式下使用的封面图集', false)
    this.itemDivider()
    this.albumSelectItem('深色配色图集', '深色模式下使用的封面图集', true)
    this.itemDivider()
    this.selectItem('图集应用范围', '作用于全部书籍或指定书籍',
      this.scopeOptions(), this.scopeSelectedIndex(), (index: number) => {
        this.setCoverApplyScope(index === 1 ? 'books' : 'all');
      })

    if (this.showTargetBookList) {
      this.itemDivider()
      this.targetBooksPanel()
    }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('封面图集')
    Column() {
      this.navItem('图集管理', '新建、导入图片、重命名、预览', 'pages/CoverGalleryManager')
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
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
      this.bookshelfShowTypeBadge = settings.showTypeBadge;
      this.bookshelfLayoutMode = settings.layoutMode;
      this.bookshelfLastReadLeafMode = settings.lastReadLeafMode;
      this.bookshelfLastReadPinMode = settings.lastReadPinMode;
      this.bookshelfBookOpenAnimation = settings.bookOpenAnimation;
    } catch (e) {
      console.warn('重新加载书架显示设置失败:', e);
    }
  }

  async reloadPrivateShelfSettings(): Promise<void> {
    try {
      await PrivateShelfStore.load(getContext(this));
    } catch (e) {
      console.warn('加载隐私书架设置失败:', e);
    }
    this.privateShelfSwitchOn = this.privateShelfEnabled;
  }

  onPrivateShelfEnabledChanged(): void {
    this.privateShelfSwitchOn = this.privateShelfEnabled;
  }

  onPrivateShelfSwitchChanged(value: boolean): void {
    if (value === this.privateShelfEnabled) return;
    this.privateShelfSwitchOn = value;
    if (!value && this.privateShelfHasPassword) {
      this.openPrivatePasswordDialog('disable');
      return;
    }
    this.applyPrivateShelfEnabled(value);
  }

  async applyPrivateShelfEnabled(enabled: boolean): Promise<void> {
    try {
      await PrivateShelfStore.setEnabled(getContext(this), enabled);
    } catch (e) {
      console.warn('保存隐私书架开关失败:', e);
      HdsFeedback.showToast('保存失败');
    }
    this.privateShelfSwitchOn = this.privateShelfEnabled;
  }

  openPrivatePasswordDialog(mode: string): void {
    this.privatePasswordDialogMode = mode;
    this.privatePasswordCurrent = '';
    this.privatePasswordNew = '';
    this.privatePasswordConfirm = '';
    this.privatePasswordError = '';
    // 只能用按钮关闭：点蒙层关掉的话，“关闭隐私书架”的开关会停在错误的位置。
    this.privatePasswordDialogSession.open(this.getUIContext(), (): void => {
      this.privatePasswordDialogContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示隐私书架密码弹窗失败:'
    });
  }

  closePrivatePasswordDialog(): void {
    this.privatePasswordDialogSession.close(this.getUIContext());
    this.privatePasswordCurrent = '';
    this.privatePasswordNew = '';
    this.privatePasswordConfirm = '';
    this.privatePasswordError = '';
    this.privateShelfSwitchOn = this.privateShelfEnabled;
  }

  async submitPrivatePasswordDialog(): Promise<void> {
    if (this.privateShelfBusy) return;
    this.privateShelfBusy = true;
    try {
      const context = getContext(this);
      if (this.privateShelfHasPassword &&
        !(await PrivateShelfStore.verifyPassword(context, this.privatePasswordCurrent))) {
        this.privatePasswordError = '当前密码不正确';
        return;
      }
      if (this.privatePasswordDialogMode === 'disable') {
        await PrivateShelfStore.setEnabled(context, false);
        this.closePrivatePasswordDialog();
        return;
      }
      if (this.privatePasswordNew !== this.privatePasswordConfirm) {
        this.privatePasswordError = '两次输入的新密码不一致';
        return;
      }
      if (!this.privatePasswordNew && !this.privateShelfHasPassword) {
        this.privatePasswordError = '请输入密码';
        return;
      }
      const cleared = !this.privatePasswordNew;
      await PrivateShelfStore.setPassword(context, this.privatePasswordNew);
      this.closePrivatePasswordDialog();
      HdsFeedback.showToast(cleared ? '已清除隐私书架密码' : '隐私书架密码已设置');
    } catch (e) {
      console.warn('保存隐私书架密码失败:', e);
      this.privatePasswordError = '保存失败，请重试';
    } finally {
      this.privateShelfBusy = false;
    }
  }

  async confirmResetPrivateShelf(): Promise<void> {
    const confirmation = await promptAction.showDialog({
      title: '重置隐私书架',
      message: '该操作会删除所有隐私书籍，包括进度、书签等，并关闭隐私书架选项',
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '确认', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
    });
    if (confirmation.index !== 1 || this.privateShelfBusy) return;
    this.privateShelfBusy = true;
    try {
      const context = getContext(this);
      const db = AppDatabase.getInstance();
      await db.initWithContext(context);
      const privateBooks = (await db.getAllBooks()).filter((book: Book) => book.isPrivate);
      for (const book of privateBooks) {
        const covers = [
          ...BookDisplayHelper.decodeCoverList(book.customCoverUrl),
          ...BookDisplayHelper.decodeCoverList(book.coverUrl)
        ];
        for (const cover of covers) {
          BookCoverCache.deleteCachedCover(context, cover);
        }
        LocalBookService.deleteLocalBookFiles(context, book);
        await db.deleteBook(book.bookUrl, 'private_shelf_reset');
        // 阅读时长的 dayKey 形如 2026-10-10，这个区间覆盖全部日期。
        await db.deleteReadStatsForBook(book.bookUrl, '0000-00-00', '9999-99-99');
      }
      await PrivateShelfStore.reset(context);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('隐私书架已重置');
    } catch (e) {
      console.error('重置隐私书架失败:', e);
      HdsFeedback.showToast('重置失败');
    } finally {
      this.privateShelfBusy = false;
      this.privateShelfSwitchOn = this.privateShelfEnabled;
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
    settings.showTypeBadge = this.bookshelfShowTypeBadge;
    settings.layoutMode = this.bookshelfLayoutMode;
    settings.lastReadLeafMode = this.bookshelfLastReadLeafMode;
    settings.lastReadPinMode = this.bookshelfLastReadPinMode;
    settings.bookOpenAnimation = this.bookshelfBookOpenAnimation;
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
      this.books = PrivateShelfStore.publicBooks(
        SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks())).slice();
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

  lastReadPinOptions(): SelectOption[] {
    return [{ value: '关闭' }, { value: '中' }, { value: '大' }];
  }

  lastReadPinSelectedIndex(): number {
    return this.bookshelfLastReadPinMode === 'off' ? 0 : (this.bookshelfLastReadPinMode === 'large' ? 2 : 1);
  }

  lastReadLeafOptions(): SelectOption[] {
    return [{ value: '书籍信息' }, { value: '内容预览' }, { value: '自适应' }];
  }

  lastReadLeafSelectedIndex(): number {
    return this.bookshelfLastReadLeafMode === 'bookInfo' ? 0 :
      (this.bookshelfLastReadLeafMode === 'contentPreview' ? 1 : 2);
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
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  itemDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(ThemeRuntime.hairlineColor(this.appDarkMode))
      .width('calc(100% - 32vp)')
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
  }

  @Builder
  selectItem(title: string, desc: string, options: SelectOption[], selected: number, onSelect: (index: number) => void) {
    SettingRow({ title: title, description: desc, showDivider: false }) {
      Select(options)
        .selected(selected)
        .value(this.optionValue(options, selected))
        .font({ size: AppFontSize.BODY })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => {
          onSelect(index);
        })
    }
  }

  @Builder
  albumSelectItem(title: string, desc: string, dark: boolean) {
    Row() {
      Column() {
        Text(title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Select(this.albumOptions())
        .selected(this.albumSelectedIndex(dark))
        .value(this.optionValue(this.albumOptions(), this.albumSelectedIndex(dark)))
        .font({ size: AppFontSize.BODY })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
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
    .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  targetBooksPanel() {
    Column({ space: AppSpacing.XXS }) {
      if (this.targetBooksLoading) {
        Text('正在加载书籍...')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .height(48)
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
          .textAlign(TextAlign.Start)
      } else if (this.books.length === 0) {
        Text('暂无可选择书籍')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .height(48)
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
          .textAlign(TextAlign.Start)
      } else {
        ForEach(this.books, (book: Book) => {
          Row() {
            Text(book.name || '未命名书籍')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            this.targetBookSwitch(book, this.isTargetBook(book))
          }
          .width('100%')
          .height(48)
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        }, (book: Book) => this.targetBookKey(book))
      }
    }
    .width('100%')
    .backgroundColor(this.cardColor())
  }

  @Builder
  targetBookSwitch(book: Book, selected: boolean) {
    AdaptiveSwitch({
      isOn: selected,
      onChange: (checked: boolean) => {
        this.toggleTargetBook(book, checked);
      }
    })
  }

  // 取消关闭时开关要能弹回去，所以 isOn 绑定单独的 privateShelfSwitchOn 状态。
  @Builder
  privateShelfSwitchItem() {
    SettingSwitchRow({
      title: '隐私书架',
      description: '在书架最后一个分类继续左滑进入，顶部不显示入口；关闭后隐私书籍仍隐藏',
      isOn: this.privateShelfSwitchOn,
      showDivider: false,
      onChange: (checked: boolean) => {
        this.onPrivateShelfSwitchChanged(checked);
      }
    })
  }

  @Builder
  actionItem(title: string, desc: string, titleColor: string, onClick: () => void) {
    SettingNavRow({ title: title, description: desc, titleColor: titleColor, showDivider: false, onTap: onClick })
  }

  @Builder
  privatePasswordField(placeholder: string, value: string, onChange: (value: string) => void) {
    TextInput({ placeholder: placeholder, text: value })
      .type(InputType.Password)
      .width('100%')
      .height(44)
      .fontColor(this.primaryTextColor())
      .placeholderColor(this.subTextColor())
      .backgroundColor(this.inputColor())
      .borderRadius(ThemeRuntime.mediumRadius())
      .margin({ bottom: AppSpacing.MD })
      .onChange((text: string) => {
        onChange(text);
      })
  }

  @Builder
  privatePasswordDialogContent() {
    Column() {
      Text(this.privatePasswordDialogMode === 'disable' ? '关闭隐私书架' : '隐私书架密码')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.XL })

      if (this.privateShelfHasPassword) {
        this.privatePasswordField('当前密码', this.privatePasswordCurrent, (value: string) => {
          this.privatePasswordCurrent = value;
          this.privatePasswordError = '';
        })
      }
      if (this.privatePasswordDialogMode !== 'disable') {
        this.privatePasswordField(this.privateShelfHasPassword ? '新密码（留空则清除密码）' : '密码',
          this.privatePasswordNew, (value: string) => {
            this.privatePasswordNew = value;
            this.privatePasswordError = '';
          })
        this.privatePasswordField(this.privateShelfHasPassword ? '再次输入新密码' : '再次输入密码',
          this.privatePasswordConfirm, (value: string) => {
            this.privatePasswordConfirm = value;
            this.privatePasswordError = '';
          })
      }

      if (this.privatePasswordError) {
        Text(this.privatePasswordError)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .width('100%')
      }

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closePrivatePasswordDialog())

        Button(this.privatePasswordDialogMode === 'disable' ? '关闭' : '保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.submitPrivatePasswordDialog();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.LG })
    }
    .padding(AppSpacing.XXL)
  }

  @Builder
  navItem(title: string, desc: string, url: string) {
    SettingNavRow({
      title: title,
      description: desc,
      showDivider: false,
      onTap: () => {
        router.pushUrl({ url });
      }
    })
  }
}
