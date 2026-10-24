import { router } from '@kit.ArkUI';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import deviceInfo from '@ohos.deviceInfo';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { Book, BookChapter, BookGroup, SearchBook, BookTypeSupport, sleepMs } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { SearchCoordinator, SearchProgress } from '../../core/book/SearchCoordinator';
import { ReadBookEngine } from '../../core/book/ReadBookEngine';
import { ImmersiveBackButton } from '../../components/ImmersiveBackButton';
import { ImmersiveMaterialSurface } from '../../components/ImmersiveMaterialSurface';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { CollapsingHeader } from '../../utils/CollapsingHeader';
import { StatusBarScrim } from '../common/StatusBarScrim';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { BookDisplayHelper } from '../../utils/BookDisplayHelper';
import { BookCoverCache } from '../../utils/BookCoverCache';
import { CoverGallerySettings } from '../../utils/CoverGallerySettings';
import { BookshelfDisplaySettingsStore } from '../../utils/BookshelfDisplaySettingsStore';
import { BookshelfStateStore } from '../../utils/BookshelfStateStore';
import { SearchExplorePendingBook } from '../../utils/SearchExplorePendingBook';
import { BookshelfSortHelper } from '../../utils/BookshelfSortHelper';
import { SearchExploreSettingsStore } from '../../utils/SearchExploreSettingsStore';
import { AppThemeSettingsStore } from '../../utils/AppThemeSettingsStore';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { ThemeBookCoverSettings } from '../../utils/ThemeBookCoverSettings';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { LocalBookService } from '../../core/book/LocalBookService';
import { BookChangeSourceDialog } from '../../components/BookChangeSourceDialog';
import { SystemDialogSession } from '../../utils/SystemDialogSession';
import { ReaderOpenTrace } from '../../utils/ReaderOpenTrace';
import { FullTextCacheCancelCoordinator, FullTextCacheCancelSignal } from '../../utils/FullTextCacheCancelCoordinator';
import { ShelfTileSortEntry, ShelfBookDataSource, ShelfTileEntryDataSource } from '../../core/book/ShelfDataSources';
import { PrivateShelfStore } from '../../utils/PrivateShelfStore';
import { RecentReadCardUpdater } from '../../utils/RecentReadCardUpdater';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { CloudAutoSync } from '../../account/CloudAutoSync';
import { PopupMenuAction } from '../common/PopupMenuAction';

const SHELF_FULL_TEXT_CACHE_NOTIFICATION_INTERVAL_MS: number = 5000;
const SHELF_COVER_INITIAL_PREFETCH_COUNT: number = 16;
const SHELF_COVER_UPDATE_BATCH_MS: number = 48;
const SHELF_UPDATE_BADGE_VARIABLE: string = 'shelfHasUpdate';
const SHELF_SEARCH_INPUT_KEY: string = 'bookshelf_search_input';
/** 下拉偏移回退超过这个距离（vp）才算往回推，避免手指抖动时提示闪烁。 */
const SHELF_REFRESH_PULL_DIRECTION_SLOP: number = 2;
/** 输入停顿这么久才按新关键词重新筛选，连续打字时不必每个字都重建列表。 */
const SHELF_SEARCH_APPLY_DELAY_MS: number = 200;
/** 标签、书源筛选键的前缀，后面跟 encodeURIComponent 过的名字，避免名字里的逗号打乱键列表。 */
const SHELF_FILTER_TAG_PREFIX: string = 'tag:';
const SHELF_FILTER_ORIGIN_PREFIX: string = 'src:';
const SHELF_DAY_MS: number = 24 * 60 * 60 * 1000;
let bookshelfColdStartRefreshStarted: boolean = false;

/** 标签、书源筛选子页里的一项：筛选键、显示名与当前书架里的本数。 */
class ShelfFilterOption {
  key: string = '';
  label: string = '';
  count: number = 0;
}

interface ShelfFullTextCacheTask {
  taskId: number;
  bookUrl: string;
  bookName: string;
  taskKey: string;
  createdAt: number;
  cancelRequested: boolean;
  cancelSeenNonce: number;
  notificationLastAt: number;
  cancelAgent: WantAgent | null;
  done: number;
  total: number;
  status: string;
  coverPixelMap: image.PixelMap | null;
  notificationFailureHintShown: boolean;
  engine: ReadBookEngine | null;
  stoppingNotificationTask: Promise<void> | null;
  /** Chapter indexes to cache, in order. Empty means the whole book. */
  chapterIndexes: number[];
  /** Shown in the notification title: 全文 or 章节. */
  scopeLabel: string;
}

/** 首页"书架"页签：书架展示、分组与排序、封面加载、更新检查、全文缓存与书籍操作。 */
@Component
export struct BookshelfPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  /** 标题下方“全部 / 网络 / 本地”胶囊的高度。 */
  static readonly SCOPE_TABS_HEIGHT: number = 44;
  static readonly SCOPE_TABS_PADDING: number = 6;
  static readonly SCOPE_TAB_INDICATOR_WIDTH: number = 18;
  /** 分类栏按书籍类型切换，没有书的类型不显示；隐私书架不在栏里，从最后一项继续左滑进入。 */
  static readonly TYPE_TAB_IDS: string[] = ['all', 'text', 'image', 'audio', 'video'];
  /**
   * 弹窗里直接列出的筛选组：来源、状态、阅读进度、最近阅读与更新。
   * 标签和书源的选项随书架内容变化，键带前缀，放在弹窗的二级页里。
   */
  static readonly FILTER_SOURCE_KEYS: string[] = ['network', 'local'];
  static readonly FILTER_STATUS_KEYS: string[] = ['finished', 'ongoing'];
  static readonly FILTER_PROGRESS_KEYS: string[] = ['unread', 'reading', 'readDone'];
  static readonly FILTER_READ_TIME_KEYS: string[] = ['read7d', 'read30d', 'stale90d'];
  static readonly FILTER_UPDATE_KEYS: string[] = ['updated'];
  static readonly FILTER_GROUPS: string[][] = [BookshelfPage.FILTER_SOURCE_KEYS, BookshelfPage.FILTER_STATUS_KEYS,
    BookshelfPage.FILTER_PROGRESS_KEYS, BookshelfPage.FILTER_READ_TIME_KEYS, BookshelfPage.FILTER_UPDATE_KEYS];
  static readonly FILTER_GROUP_LABELS: string[] = ['来源', '状态', '进度', '最近阅读', '更新'];
  /** 标签、书源二级页里选项区域的最大高度，超出后在区域内滚动。 */
  static readonly FILTER_SUBPAGE_MAX_HEIGHT: number = 360;
  /** 标题行下方书架搜索栏的高度。 */
  static readonly SEARCH_BAR_HEIGHT: number = 40;
  /** 顶部排序胶囊、筛选和布局圆形按钮的高度。 */
  static readonly HEADER_CONTROL_SIZE: number = 40;
  /** 顶部下拉菜单（沉浸光感弹出层）的圆角、内边距和菜单项高度。 */
  static readonly MENU_RADIUS: number = ImmersiveMaterialRuntime.POPUP_MENU_RADIUS;
  static readonly MENU_PADDING: number = ImmersiveMaterialRuntime.POPUP_MENU_PADDING;
  static readonly MENU_ITEM_HEIGHT: number = 44;
  // 加密的书源封面解密完成后递增，读取它的封面会重新取到本地文件地址。
  @StorageProp('sourceCoverRevision') sourceCoverRevision: number = 0;
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Link isBookMultiSelect: boolean;
  @Link @Watch('onActiveShelfGroupChanged') activeShelfGroupId: number;
  @StorageLink('appThemeBookCoverEnabled') themeBookCoverEnabled: boolean = false;
  @StorageLink('appThemeId') appThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appCustomBaseThemeId') appCustomBaseThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @State books: Book[] = [];
  @State downloadingCloudBookUrl: string = '';
  @State allBooks: Book[] = [];
  private shelfListBooksSource: ShelfBookDataSource = new ShelfBookDataSource();
  private shelfTileBooksSource: ShelfBookDataSource = new ShelfBookDataSource();
  private shelfTileEntriesSource: ShelfTileEntryDataSource = new ShelfTileEntryDataSource();
  private shelfTileEntriesCacheKey: string = '';
  private shelfTileEntriesCache: ShelfTileSortEntry[] = [];
  /** 'all' 为普通书架，'private' 为隐私书架。 */
  @State shelfScope: string = 'all';
  /** 分类栏上已经点中、书籍列表还在切换动画里的目标页（类型或 'private'）；空串表示跟随当前页。 */
  @State shelfScopeTabSelection: string = '';
  /** 当前有书的类型，决定分类栏显示哪几项；“全部”总在第一位。 */
  @State shelfTypeTabIds: string[] = ['all'];
  /** 分类栏的实际宽度：沉浸材质底板需要具体数值。 */
  @State shelfScopeTabsWidth: number = 0;
  @StorageLink('privateShelfEnabled') @Watch('onPrivateShelfEnabledChanged') privateShelfEnabled: boolean = false;
  @StorageLink('privateShelfHasPassword') privateShelfHasPassword: boolean = false;
  @State privateShelfPasswordInput: string = '';
  @State privateShelfPasswordError: string = '';
  private privateShelfUnlockDialogSession: SystemDialogSession = new SystemDialogSession();
  private changeSourceDialogSession: SystemDialogSession = new SystemDialogSession();
  @State showShelfSortMenu: boolean = false;
  @State showShelfLayoutMenu: boolean = false;
  @State showShelfFilterMenu: boolean = false;
  /** 筛选弹窗当前页：空串为主页，'tag' / 'origin' 为标签、书源二级页。 */
  @State shelfFilterMenuPage: string = '';
  /** 分类栏选中的书籍类型，只在本次运行内保留（切换页签不丢，重启后回到“全部”）。 */
  @StorageLink('bookshelfTypeTab') shelfTypeTab: string = 'all';
  /** 筛选条件（FILTER_GROUPS 里的键）逗号分隔，同样只在本次运行内保留。 */
  @StorageLink('bookshelfFilterKeys') shelfFilterKeys: string = '';
  /** 书架搜索栏是否展开、框里的原始输入；同样只在本次运行内保留，主页返回键会先收起它。 */
  @StorageLink('bookshelfSearchActive') shelfSearchActive: boolean = false;
  @StorageLink('bookshelfSearchKeyword') @Watch('onShelfSearchKeywordChanged') shelfSearchKeyword: string = '';
  /** 实际参与筛选的关键词（转小写、空白归一），输入停顿后才从 shelfSearchKeyword 同步过来。 */
  @State shelfAppliedSearchKeyword: string = '';
  private shelfSearchApplyTimer: number = -1;
  /** 标题下拉的分组菜单。 */
  @State showShelfGroupMenu: boolean = false;
  @State shelfGroups: BookGroup[] = [];
  @State shelfScopeTransitionX: number = 0;
  @State shelfScopeTransitionScale: number = 1;
  @State shelfScopeTransitionOpacity: number = 1;
  @State tileGroupTransitionX: number = 0;
  @State tileGroupTransitionScale: number = 1;
  @State tileGroupTransitionOpacity: number = 1;
  @State openingBook: Book | null = null;
  @State openingBookScale: number = 0.28;
  @State openingBookTranslateX: number = 0;
  @State openingBookTranslateY: number = 0;
  @State openingBookOpacity: number = 0;
  @State openingBookBackdropOpacity: number = 0;
  @State openingBookCoverAngle: number = 0;
  @State openingBookWaiting: boolean = false;
  @State selectedBookUrls: string[] = [];
  @State showMultiSelectMoreMenu: boolean = false;
  private batchExportDialogSession: SystemDialogSession = new SystemDialogSession();
  @State showBookGroupPicker: boolean = false;
  @State groupPickerSingleBookUrl: string = '';
  private addBookGroupDialogSession: SystemDialogSession = new SystemDialogSession();
  private renameBookGroupDialogSession: SystemDialogSession = new SystemDialogSession();
  private deleteBookGroupDialogSession: SystemDialogSession = new SystemDialogSession();
  private batchDeleteDialogSession: SystemDialogSession = new SystemDialogSession();
  private deleteBookDialogSession: SystemDialogSession = new SystemDialogSession();
  private editBookInfoDialogSession: SystemDialogSession = new SystemDialogSession();
  private tagDialogSession: SystemDialogSession = new SystemDialogSession();
  private customCoverDialogSession: SystemDialogSession = new SystemDialogSession();
  @State showAddBookGroupDialog: boolean = false;
  @State newBookGroupName: string = '';
  @State showBookGroupActionMenu: boolean = false;
  @State showRenameBookGroupDialog: boolean = false;
  @State renameBookGroupName: string = '';
  @State pendingBookGroup: BookGroup | null = null;
  @State showDeleteBookGroupDialog: boolean = false;
  @State pendingDeleteBookGroup: BookGroup | null = null;
  @State showBatchDeleteDialog: boolean = false;
  @State isLoading: boolean = false;
  @State showDeleteDialog: boolean = false;
  @State showActionDialog: boolean = false;
  @State showEditBookInfoDialog: boolean = false;
  @State editingBookName: string = '';
  @State editingBookAuthor: string = '';
  @State showTagDialog: boolean = false;
  private cacheDialogSession: SystemDialogSession = new SystemDialogSession();
  private chapterCacheDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onBookshelfSystemDialogFlagChanged') showCacheDialog: boolean = false;
  @State @Watch('onBookshelfSystemDialogFlagChanged') showChapterCacheDialog: boolean = false;
  @State showNetworkCoverDialog: boolean = false;
  @State networkCoverTargetBook: Book | null = null;
  @State networkCoverCandidates: SearchBook[] = [];
  @State networkCoverSearching: boolean = false;
  @State networkCoverStatus: string = '';
  @State showCustomNetworkCoverDialog: boolean = false;
  @State customNetworkCoverUrl: string = '';
  @State pendingDeleteBook: Book | null = null;
  @State pendingActionBook: Book | null = null;
  @State @Watch('syncChangeSourceDialog') showShelfChangeSourceDialog: boolean = false;
  private shelfChangeSourceTarget: Book | null = null;
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State shelfTileViewportWidth: number = 360;
  @State cacheTargetBook: Book | null = null;
  @State cacheChapters: BookChapter[] = [];
  @State cacheStatus: string = '';
  @State cacheRangeDraft: string = '';
  @State isCaching: boolean = false;
  @State activeFullTextCacheBookUrls: string[] = [];
  @State isCacheTocLoading: boolean = false;
  @State isShelfRefreshing: boolean = false;
  @State shelfRefreshStatus: RefreshStatus = RefreshStatus.Inactive;
  @State shelfRefreshPrompt: string = '下拉刷新书架';
  /** 下拉途中手指往回推时收起提示，再往下拉才重新显示。 */
  @State shelfRefreshPullRetracting: boolean = false;
  private shelfRefreshPullPeak: number = 0;
  private shelfRefreshPullTrough: number = 0;
  @State editingTags: string[] = [];
  @State tagInput: string = '';
  @State shelfCoverMap: Map<string, string> = new Map();
  @State shelfCoverRenderVersions: Map<string, number> = new Map();
  private shelfCoverRawUrls: Map<string, string> = new Map();
  private shelfCoverCacheRevision: number = 0;
  private shelfCoverBookTasks: Set<string> = new Set();
  private pendingShelfCoverUpdates: Map<string, string> = new Map();
  private shelfCoverUpdateTimer: number = -1;
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('bookshelfSortMode') sortMode: string = 'recentRead';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
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
  @StorageLink('bookshelfLastReadPinMode') @Watch('onLastReadPinModeChanged') bookshelfLastReadPinMode: string = 'medium';
  @StorageLink('bookshelfBookOpenAnimation') bookshelfBookOpenAnimation: boolean = true;
  @StorageLink('bookshelfCoverAlbums') @Watch('onShelfCoverSettingsChanged') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') @Watch('onShelfCoverSettingsChanged') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') @Watch('onShelfCoverSettingsChanged') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverApplyScope') @Watch('onShelfCoverSettingsChanged') bookshelfCoverApplyScope: string = 'all';
  @StorageLink('bookshelfCoverTargetBooks') @Watch('onShelfCoverSettingsChanged') bookshelfCoverTargetBooks: string = '';
  @StorageLink('bookshelfIgnoreSourceCover') @Watch('onShelfCoverSettingsChanged') bookshelfIgnoreSourceCover: boolean = false;
  @StorageLink('bookshelfCoverMode') @Watch('onShelfCoverSettingsChanged') bookshelfCoverMode: string = 'sequence';
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageLink('fullTextCacheCancelNonce') @Watch('onFullTextCacheCancelNonceChanged') fullTextCacheCancelNonce: number = 0;
  @StorageLink('fullTextCacheCancelSignal') @Watch('onFullTextCacheCancelSignalChanged') fullTextCacheCancelSignal: string = '';
  @StorageLink('shelfBookCloseAnimationNonce') @Watch('onShelfBookCloseAnimationRequested')
  shelfBookCloseAnimationNonce: number = 0;
  @StorageLink('shelfBookCloseAnimationUrl') shelfBookCloseAnimationUrl: string = '';
  private loadTimer: number = -1;
  private cacheTocLoadToken: number = 0;
  private cacheTocLoadBookUrl: string = '';
  private cacheTocLoadPromise: Promise<boolean> | null = null;
  private cacheDialogOpenedAt: number = 0;
  private fullTextCacheTasks: Map<string, ShelfFullTextCacheTask> = new Map();
  private shelfRefreshRunning: boolean = false;
  private fullTextCacheTaskId: number = 0;
  private fullTextCacheCancelRequested: boolean = false;
  private fullTextCacheCancelSeenNonce: number = 0;
  private fullTextCacheNotificationLastAt: number = 0;
  private fullTextCacheBackgroundRunning: boolean = false;
  private fullTextCacheCancelAgent: WantAgent | null = null;
  private fullTextCacheDone: number = 0;
  private fullTextCacheTotal: number = 0;
  private fullTextCacheStatus: string = '';
  private fullTextCacheBookName: string = '';
  private fullTextCacheNotificationSlotReady: boolean = false;
  private fullTextCacheNotificationFailureHintShown: boolean = false;
  private openingBookGrowTimer: number = -1;
  private openingBookTurnTimer: number = -1;
  private openingBookRouteTimer: number = -1;
  private shelfScopeSwapTimer: number = -1;
  private shelfScopeFinishTimer: number = -1;
  private shelfScopeSwitchAnimating: boolean = false;
  private suppressShelfBookClickUntil: number = 0;
  private pendingShelfSortTimer: number = -1;
  private pendingShelfSortMode: string = '';
  private openingBookOriginX: number = 0;
  private openingBookOriginY: number = 0;
  private networkCoverCoordinator: SearchCoordinator | null = null;
  private networkCoverSearchToken: number = 0;
  private shelfLoadSerial: number = 0;
  private activeShelfGroupRestored: boolean = false;
  private localBookIntroMigrationQueue: Book[] = [];
  private localBookIntroMigrationRunning: boolean = false;
  private localBookIntroMigrationGeneration: number = 0;
  private shelfComponentActive: boolean = false;
  private shelfUpdateAcknowledgedAt: Map<string, number> = new Map();

  aboutToAppear() {
    this.shelfComponentActive = true;
    this.shelfAppliedSearchKeyword = BookshelfPage.normalizeShelfSearchText(this.shelfSearchKeyword);
    this.reloadDisplaySettings();
    this.restoreSortModeAndLoad();
  }

  aboutToDisappear(): void {
    this.shelfComponentActive = false;
    this.cancelShelfBookOpening();
    this.cancelNetworkCoverSearch();
    this.clearShelfScopeTransition();
    this.shelfCoverCacheRevision++;
    this.localBookIntroMigrationGeneration++;
    this.localBookIntroMigrationQueue = [];
    this.shelfCoverBookTasks.clear();
    this.pendingShelfCoverUpdates.clear();
    if (this.shelfCoverUpdateTimer >= 0) {
      clearTimeout(this.shelfCoverUpdateTimer);
      this.shelfCoverUpdateTimer = -1;
    }
    if (this.pendingShelfSortTimer >= 0) {
      clearTimeout(this.pendingShelfSortTimer);
      this.pendingShelfSortTimer = -1;
    }
    this.pendingShelfSortMode = '';
    if (this.shelfSearchApplyTimer >= 0) {
      clearTimeout(this.shelfSearchApplyTimer);
      this.shelfSearchApplyTimer = -1;
    }
  }

  onActiveShelfGroupChanged(): void {
    this.applyShelfScope();
    // A group switch changes the visible snapshot while the shelf's LazyForEach data sources
    // are retained.  Replacing them here (and forcing a reload) prevents a retained list/grid
    // from continuing to render the books from the previous group, especially on the tile group
    // page where the source is shared across group transitions.
    this.reloadShelfDataSources(true);
    if (this.activeShelfGroupRestored) {
      BookshelfStateStore.saveActiveGroupId(getContext(this), this.activeShelfGroupId).catch((e: Error) => {
        console.warn('保存书架分组状态失败:', e);
      });
    }
    if (!this.isTileLayout()) {
      return;
    }
    this.tileGroupTransitionX = this.activeShelfGroupId > 0 ? 34 : -34;
    this.tileGroupTransitionScale = 0.965;
    this.tileGroupTransitionOpacity = 0.2;
    animateTo({ duration: 300, curve: Curve.Friction }, () => {
      this.tileGroupTransitionX = 0;
      this.tileGroupTransitionScale = 1;
      this.tileGroupTransitionOpacity = 1;
    });
  }

  onShelfBookCloseAnimationRequested(): void {
    if (!this.shelfBookCloseAnimationUrl) {
      return;
    }
    this.closeShelfBook(this.shelfBookCloseAnimationUrl);
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
      console.warn('恢复书架显示设置失败:', e);
    }
  }

  onShelfChanged(): void {
    this.scheduleLoadBooks();
  }

  // 置顶开关决定平铺数据源里是否剔除上次阅读的书，切换后立即重建，避免同一本书出现两次或消失。
  onLastReadPinModeChanged(): void {
    this.reloadShelfDataSources(true);
  }

  onPrivateShelfEnabledChanged(): void {
    if (!this.privateShelfEnabled && this.shelfScope === 'private') {
      this.setShelfPage(this.shelfTypeTab);
    }
  }

  onShelfCoverSettingsChanged(): void {
    this.shelfCoverMap = new Map();
    this.shelfCoverRawUrls.clear();
    this.refreshShelfCoverCache(this.books);
  }

  async loadBooks(forceDataSourceReload: boolean = false): Promise<void> {
    const loadSerial = ++this.shelfLoadSerial;
    // Returning from the reader refreshes shelf metadata. Do not cover an already-rendered shelf
    // with the initial loading placeholder; that one-frame replacement is perceived as a flash.
    const needsInitialPlaceholder = this.allBooks.length === 0;
    if (needsInitialPlaceholder) this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await PrivateShelfStore.load(getContext(this));
      const loadedBooks = SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks());
      const loadedGroups = await db.getCustomBookGroups();
      if (loadSerial !== this.shelfLoadSerial) return;
      if (!this.activeShelfGroupRestored) {
        try {
          this.activeShelfGroupId = await BookshelfStateStore.loadActiveGroupId(getContext(this));
        } catch (e) {
          console.warn('恢复书架分组状态失败:', e);
        }
        if (loadSerial !== this.shelfLoadSerial) return;
        this.activeShelfGroupRestored = true;
      }
      // Commit the complete snapshot together. In particular, never expose a new expanded card while the retained
      // LazyForEach data source still contains entries from the previous shelf generation.
      this.allBooks = loadedBooks;
      this.shelfGroups = loadedGroups;
      if (this.activeShelfGroupId > 0 && !this.shelfGroups.some((group: BookGroup) => group.groupId === this.activeShelfGroupId)) {
        this.activeShelfGroupId = 0;
      }
      this.applyShelfScope();
      this.reloadShelfDataSources(forceDataSourceReload);
      this.refreshShelfCoverCache(this.books);
      this.scheduleLocalBookIntroMigration(loadedBooks);
      this.scheduleColdStartBookshelfRefresh(loadedBooks);
    } catch (e) {
      if (loadSerial === this.shelfLoadSerial) console.error('加载书籍失败:', e);
    } finally {
      if (needsInitialPlaceholder && loadSerial === this.shelfLoadSerial) this.isLoading = false;
    }
  }

  reloadShelfDataSources(force: boolean = false): void {
    this.shelfTileEntriesCacheKey = '';
    this.shelfTileEntriesCache = [];
    this.shelfListBooksSource.replace(this.books, force);
    this.shelfTileBooksSource.replace(this.getTileBooksWithoutLatest(this.books), force);
    this.shelfTileEntriesSource.replace(this.getSortedTileRootEntries(this.books), force);
  }

  scheduleLoadBooks(): void {
    if (this.loadTimer >= 0) {
      clearTimeout(this.loadTimer);
    }
    this.loadTimer = setTimeout(() => {
      this.loadTimer = -1;
      this.loadBooks();
    }, 80);
  }

  scheduleColdStartBookshelfRefresh(loadedBooks: Book[]): void {
    if (bookshelfColdStartRefreshStarted || loadedBooks.length === 0) {
      return;
    }
    bookshelfColdStartRefreshStarted = true;
    // Run once per process after the first local shelf snapshot is visible. The refresh deliberately
    // has no spinner or toast so cold startup remains responsive.
    setTimeout(() => {
      console.info('[ShelfRefresh] cold-start silent refresh started');
      this.refreshBookshelfToc(true).then(() => {
        console.info('[ShelfRefresh] cold-start silent refresh finished');
      }).catch((e: Error) => {
        console.error('[ShelfRefresh] cold-start silent refresh failed:', e);
      });
    }, 600);
  }

  async deleteBook(book: Book) {
    try {
      const db = AppDatabase.getInstance();
      this.deleteBookCoverCache(book);
      CloudAutoSync.onBookRemoved(getContext(this), book).catch(() => undefined);
      LocalBookService.deleteLocalBookFiles(getContext(this), book);
      await db.deleteBook(book.bookUrl, 'bookshelf_user_delete');
      HdsFeedback.showToast(`已删除《${book.name}》`);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      await this.loadBooks();
    } catch (e) {
      console.error('删除书籍失败:', e);
      HdsFeedback.showToast('删除失败');
    }
  }

  showDeleteConfirm(book: Book) {
    this.pendingDeleteBook = book;
    this.openDeleteBookDialog();
  }

  showBookActions(book: Book, event?: GestureEvent): void {
    this.captureContextMenuAnchor(event);
    this.pendingActionBook = book;
    this.showActionDialog = true;
  }

  async saveLocalBookSource(book: Book): Promise<void> {
    try {
      const savedUri = await LocalBookService.exportSourceFile(getContext(this), book);
      if (savedUri) {
        HdsFeedback.showToast(`已保存《${book.name}》源文件`);
      }
    } catch (e) {
      console.error('保存本地书籍源文件失败:', e);
      HdsFeedback.showToast(`保存失败：${e instanceof Error ? e.message : String(e)}`);
    }
  }

  async toggleBookPinned(book: Book): Promise<void> {
    const nextPinned = !book.isPinned;
    const modifiedTime = Date.now();
    try {
      await AppDatabase.getInstance().setBookPinned(book.bookUrl, nextPinned, modifiedTime);
      book.isPinned = nextPinned;
      book.shelfModifiedTime = modifiedTime;
      this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
      this.applyShelfScope();
      this.reloadShelfDataSources(true);
      HdsFeedback.showToast(nextPinned ? `已置顶《${book.name}》` : `已取消置顶《${book.name}》`);
    } catch (e) {
      console.error('更新书籍置顶状态失败:', e);
      HdsFeedback.showToast(nextPinned ? '置顶失败' : '取消置顶失败');
    }
  }

  async toggleBookPrivate(book: Book): Promise<void> {
    const nextPrivate = !book.isPrivate;
    try {
      await AppDatabase.getInstance().setBookPrivate(book.bookUrl, nextPrivate);
      book.isPrivate = nextPrivate;
      this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
      this.applyShelfScope();
      this.reloadShelfDataSources(true);
      // 桌面“最近阅读”卡片不应再展示刚移入隐私书架的书。
      RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext).catch((e: Error) => {
        console.warn('刷新最近阅读卡片失败:', e);
      });
      HdsFeedback.showToast(nextPrivate ? `已将《${book.name}》移入隐私书架` : `已将《${book.name}》移出隐私书架`);
    } catch (e) {
      console.error('更新书籍隐私状态失败:', e);
      HdsFeedback.showToast(nextPrivate ? '标记为隐私失败' : '取消隐私失败');
    }
  }

  private async restoreSortModeAndLoad(): Promise<void> {
    try {
      // Use the current AppStorage value as a migration fallback for installations that
      // previously relied only on PersistentStorage before the explicit Preferences key existed.
      const storageMode = AppStorage.get<string>('bookshelfSortMode');
      const fallbackMode = BookshelfStateStore.normalizeSortMode(storageMode || this.sortMode);
      const mode = await BookshelfStateStore.loadSortMode(getContext(this), fallbackMode);
      if (this.shelfComponentActive) {
        this.sortMode = mode;
      }
    } catch (e) {
      console.warn('恢复书架排序设置失败:', e);
    } finally {
      if (this.shelfComponentActive) {
        this.scheduleLoadBooks();
      }
    }
  }

  scheduleLocalBookIntroMigration(books: Book[]): void {
    this.localBookIntroMigrationQueue = books.filter((book: Book) =>
      LocalBookService.isLocalBook(book) &&
      (book.getVariable('localContentIntroVersion') !== '6' || !book.intro.trim()));
    if (!this.shelfComponentActive || this.localBookIntroMigrationQueue.length === 0 ||
      this.localBookIntroMigrationRunning) return;
    const generation = ++this.localBookIntroMigrationGeneration;
    this.localBookIntroMigrationRunning = true;
    setTimeout(() => this.runLocalBookIntroMigration(generation), 120);
  }

  async runLocalBookIntroMigration(generation: number): Promise<void> {
    try {
      while (generation === this.localBookIntroMigrationGeneration &&
        this.localBookIntroMigrationQueue.length > 0) {
        const book = this.localBookIntroMigrationQueue.shift();
        if (!book) break;
        try {
          const changed = await LocalBookService.ensureContentIntro(book);
          if (changed && generation === this.localBookIntroMigrationGeneration) {
            this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
            this.applyShelfScope();
          }
        } catch (e) {
          console.warn('后台生成本地书籍简介失败:', book.name, e);
        }
        // Keep migrations behind user input and list animation work.
        await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 16));
      }
    } finally {
      this.localBookIntroMigrationRunning = false;
      if (this.shelfComponentActive && this.localBookIntroMigrationQueue.length > 0) {
        this.scheduleLocalBookIntroMigration(this.localBookIntroMigrationQueue);
      }
    }
  }

  closeBookActions(): void {
    this.showActionDialog = false;
    this.pendingActionBook = null;
  }

  openShelfBookDetail(book: Book): void {
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
        status: book.status,
        coverUrl: book.customCoverUrl || book.coverUrl,
        intro: book.customIntro || book.intro,
        latestChapterTitle: book.latestChapterTitle,
        updateTime: book.updateTime,
        wordCount: book.wordCount,
        type: `${book.type}`,
        variable: book.variable,
        promptAddToShelfOnBack: 'false'
      }
    });
  }

  openShelfChangeSource(book: Book): void {
    if (!book.name.trim() || LocalBookService.isLocalBook(book)) {
      HdsFeedback.showToast('当前书籍不支持换源');
      return;
    }
    this.shelfChangeSourceTarget = book;
    this.showShelfChangeSourceDialog = true;
  }

  async openNetworkCoverPicker(book: Book): Promise<void> {
    const keyword = (book.name || '').trim();
    if (!keyword) {
      HdsFeedback.showToast('书名为空，无法搜索封面');
      return;
    }
    this.cancelNetworkCoverSearch();
    this.networkCoverTargetBook = book;
    this.networkCoverCandidates = [];
    this.networkCoverSearching = true;
    this.networkCoverStatus = '正在从启用的书源中搜索...';
    this.showNetworkCoverDialog = true;
    const token = this.networkCoverSearchToken;
    const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
    this.networkCoverCoordinator = coordinator;
    try {
      await AppDatabase.getInstance().initWithContext(getContext(this));
      const results = await coordinator.search(keyword, (progress: SearchProgress) => {
        if (token !== this.networkCoverSearchToken || this.networkCoverCoordinator !== coordinator) return;
        const incoming = progress.finished ? progress.results : (progress.deltaResults || []);
        if (incoming.length > 0) {
          this.appendNetworkCoverCandidates(incoming);
        }
        this.networkCoverStatus = progress.finished ?
          `搜索完成，找到 ${this.networkCoverCandidates.length} 个可选封面` :
          `${progress.status}，可选封面 ${this.networkCoverCandidates.length} 个`;
        if (progress.finished) this.networkCoverSearching = false;
      }, {
        exactMatch: true,
        exactMatchAuthor: false
      });
      if (token !== this.networkCoverSearchToken || this.networkCoverCoordinator !== coordinator) return;
      this.appendNetworkCoverCandidates(results);
      this.networkCoverSearching = false;
      this.networkCoverStatus = this.networkCoverCandidates.length > 0 ?
        `搜索完成，找到 ${this.networkCoverCandidates.length} 个可选封面` : '搜索完成，未找到带封面的书籍';
    } catch (e) {
      if (token !== this.networkCoverSearchToken) return;
      console.error('搜索网络封面失败:', e);
      this.networkCoverSearching = false;
      this.networkCoverStatus = '搜索网络封面失败，请稍后重试';
    } finally {
      if (token === this.networkCoverSearchToken && this.networkCoverCoordinator === coordinator) {
        this.networkCoverCoordinator = null;
      }
    }
  }

  appendNetworkCoverCandidates(results: SearchBook[]): void {
    const merged = this.networkCoverCandidates.slice();
    const coverUrls = new Set<string>(merged.map((item: SearchBook) => item.coverUrl));
    for (const result of results) {
      const coverUrl = (result.coverUrl || '').trim();
      if (!/^https?:\/\//i.test(coverUrl) || coverUrls.has(coverUrl)) continue;
      result.coverUrl = coverUrl;
      merged.push(result);
      coverUrls.add(coverUrl);
      if (merged.length >= 90) break;
    }
    this.networkCoverCandidates = merged;
  }

  async applyNetworkCover(candidate: SearchBook): Promise<void> {
    const target = this.networkCoverTargetBook;
    const coverUrl = (candidate.coverUrl || '').trim();
    if (!target || !coverUrl) return;
    try {
      const db = AppDatabase.getInstance();
      const current = await db.getBook(target.bookUrl);
      if (!current) {
        HdsFeedback.showToast('书籍已不在书架中');
        this.closeNetworkCoverPicker();
        return;
      }
      current.customCoverUrl = coverUrl;
      await db.updateBook(current);
      this.applyShelfBookCoverState(current);
      this.closeNetworkCoverPicker();
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('网络封面已启用');
    } catch (e) {
      console.error('应用网络封面失败:', e);
      HdsFeedback.showToast('应用网络封面失败');
    }
  }

  async restoreDefaultBookCover(book: Book): Promise<void> {
    if (!book.customCoverUrl) return;
    try {
      const db = AppDatabase.getInstance();
      const current = await db.getBook(book.bookUrl);
      if (!current) {
        HdsFeedback.showToast('书籍已不在书架中');
        return;
      }
      current.customCoverUrl = '';
      await db.updateBook(current);
      this.applyShelfBookCoverState(current);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('已恢复默认封面');
    } catch (e) {
      console.error('恢复默认封面失败:', e);
      HdsFeedback.showToast('恢复默认封面失败');
    }
  }

  applyShelfBookCoverState(current: Book): void {
    this.allBooks = this.allBooks.map((book: Book) => book.bookUrl === current.bookUrl ? current : book);
    this.applyShelfScope();
    this.bumpShelfBookCoverRenderVersion(current.bookUrl);
    this.shelfCoverMap = new Map();
    this.shelfCoverRawUrls.clear();
    this.refreshShelfCoverCache(this.books);
  }

  bumpShelfBookCoverRenderVersion(bookUrl: string): void {
    const versions = new Map<string, number>(this.shelfCoverRenderVersions);
    versions.set(bookUrl, (versions.get(bookUrl) || 0) + 1);
    this.shelfCoverRenderVersions = versions;
  }

  shelfBookRenderKey(book: Book, prefix: string): string {
    // LazyForEach keeps an item node when its key is unchanged. Reading progress is persisted into a fresh Book
    // snapshot while the URL/pin/cover identity remains stable, so include the progress checkpoint in the key or
    // the retained card keeps rendering the old percentage until the whole bookshelf is recreated.
    const progressChapterIndex = book.getVariable('readProgressChapterIndex');
    const progressPageCount = book.getVariable('readProgressPageCount');
    return `${prefix}_${book.bookUrl}_pin_${book.isPinned ? '1' : '0'}_` +
      `read_${book.durChapterTime}_${book.durChapterIndex}_${book.durChapterPos}_` +
      `${progressChapterIndex}_${progressPageCount}_cover_${this.shelfCoverRenderVersions.get(book.bookUrl) || 0}`;
  }

  openCustomNetworkCoverDialog(): void {
    if (!this.networkCoverTargetBook) return;
    this.customNetworkCoverUrl = this.networkCoverTargetBook.customCoverUrl || '';
    this.showNetworkCoverDialog = false;
    this.openCustomCoverDialog();
  }

  async applyCustomNetworkCover(): Promise<void> {
    const target = this.networkCoverTargetBook;
    const coverUrl = (this.customNetworkCoverUrl || '').trim();
    if (!target) return;
    if (!/^https?:\/\/[^\s]+$/i.test(coverUrl)) {
      HdsFeedback.showToast('请输入有效的 http 或 https 图片链接');
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      const current = await db.getBook(target.bookUrl);
      if (!current) {
        HdsFeedback.showToast('书籍已不在书架中');
        this.closeNetworkCoverPicker();
        return;
      }
      current.customCoverUrl = coverUrl;
      await db.updateBook(current);
      this.applyShelfBookCoverState(current);
      this.closeNetworkCoverPicker();
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('自定义封面已启用');
    } catch (e) {
      console.error('应用自定义封面失败:', e);
      HdsFeedback.showToast('应用自定义封面失败');
    }
  }

  closeNetworkCoverPicker(): void {
    this.cancelNetworkCoverSearch();
    this.showNetworkCoverDialog = false;
    this.closeCustomCoverDialog();
    this.networkCoverTargetBook = null;
    this.networkCoverCandidates = [];
    this.networkCoverStatus = '';
    this.networkCoverSearching = false;
    this.customNetworkCoverUrl = '';
  }

  cancelNetworkCoverSearch(): void {
    this.networkCoverSearchToken++;
    this.networkCoverCoordinator?.cancel();
    this.networkCoverCoordinator = null;
    this.networkCoverSearching = false;
  }

  networkCoverColumnCount(): number {
    const horizontalPadding = 32;
    const targetCardWidth = 108;
    const preferredColumnGap = 8;
    const contentWidth = Math.max(1, this.contextViewportWidth - horizontalPadding);
    const fittedCount = Math.round(
      (contentWidth + preferredColumnGap) / (targetCardWidth + preferredColumnGap)
    );
    return Math.max(3, Math.min(24, fittedCount));
  }

  networkCoverColumnsTemplate(): string {
    const columnCount = this.networkCoverColumnCount();
    let template = '1fr';
    for (let index = 1; index < columnCount; index++) {
      template += ' 1fr';
    }
    return template;
  }

  networkCoverColumnGap(): number {
    const horizontalPadding = 32;
    const targetCardWidth = 108;
    const columnCount = this.networkCoverColumnCount();
    const contentWidth = Math.max(1, this.contextViewportWidth - horizontalPadding);
    const fittedGap = columnCount > 1 ?
      (contentWidth - targetCardWidth * columnCount) / (columnCount - 1) : 8;
    return Math.max(8, Math.min(12, fittedGap));
  }

  networkCoverRowGap(): number {
    return this.networkCoverColumnGap() + 2;
  }

  captureContextMenuAnchor(event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
  }

  updateContextViewport(area: Area): void {
    const width = this.areaDimension(area.width);
    const height = this.areaDimension(area.height);
    if (width > 0) {
      this.contextViewportWidth = width;
      this.shelfTileViewportWidth = width;
    }
    if (height > 0) this.contextViewportHeight = height;
  }

  areaDimension(value: Length): number {
    if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  deleteBookCoverCache(book: Book): void {
    const context = getContext(this);
    const covers = [
      ...BookDisplayHelper.decodeCoverList(book.customCoverUrl),
      ...BookDisplayHelper.decodeCoverList(book.coverUrl)
    ];
    for (const cover of covers) {
      BookCoverCache.deleteCachedCover(context, cover);
    }
    const nextMap: Map<string, string> = new Map(this.shelfCoverMap);
    const coverCount = Math.max(1, BookDisplayHelper.getCoverList(book).length);
    for (let i = 0; i < coverCount; i++) {
      const key = this.shelfCoverKey(book, i);
      nextMap.delete(key);
      this.shelfCoverRawUrls.delete(key);
    }
    this.shelfCoverMap = nextMap;
  }

  async refreshShelfCoverCache(books: Book[]): Promise<void> {
    const revision = ++this.shelfCoverCacheRevision;
    this.shelfCoverBookTasks.clear();
    this.pendingShelfCoverUpdates.clear();
    if (this.shelfCoverUpdateTimer >= 0) {
      clearTimeout(this.shelfCoverUpdateTimer);
      this.shelfCoverUpdateTimer = -1;
    }
    // Only warm the initial viewport. Remaining covers are scheduled from coverView.onAppear.
    const initialBooks = books.slice(0, SHELF_COVER_INITIAL_PREFETCH_COUNT);
    const tasks: Promise<void>[] = initialBooks.map(async (book: Book): Promise<void> => {
      const taskKey = `${revision}:${book.bookUrl}`;
      this.shelfCoverBookTasks.add(taskKey);
      try {
        const updates = await this.resolveShelfBookCoverUpdates(book, revision);
        this.queueShelfCoverUpdates(updates, revision);
      } finally {
        this.shelfCoverBookTasks.delete(taskKey);
      }
    });
    try {
      await Promise.all(tasks);
    } catch (e) {
      console.warn('预缓存首屏书架封面失败:', e);
    }
  }

  ensureShelfBookCoverCache(book: Book): void {
    const revision = this.shelfCoverCacheRevision;
    const taskKey = `${revision}:${book.bookUrl}`;
    if (this.shelfCoverBookTasks.has(taskKey)) return;
    this.shelfCoverBookTasks.add(taskKey);
    this.resolveShelfBookCoverUpdates(book, revision)
      .then((updates: Map<string, string>) => this.queueShelfCoverUpdates(updates, revision))
      .catch((e: Error) => console.warn('缓存可见书籍封面失败:', e))
      .finally(() => this.shelfCoverBookTasks.delete(taskKey));
  }

  async resolveShelfBookCoverUpdates(book: Book, revision: number): Promise<Map<string, string>> {
    const updates: Map<string, string> = new Map();
    if (revision !== this.shelfCoverCacheRevision) return updates;
    const covers = CoverGallerySettings.getDisplayCoverList(
      book,
      this.appDarkMode,
      this.bookshelfCoverAlbums,
      this.bookshelfLightCoverAlbumId,
      this.bookshelfDarkCoverAlbumId,
      this.bookshelfCoverApplyScope,
      this.bookshelfCoverTargetBooks,
      this.bookshelfIgnoreSourceCover,
      this.bookshelfCoverMode
    );
    const context = getContext(this);
    for (let i = 0; i < covers.length; i++) {
      if (revision !== this.shelfCoverCacheRevision) return new Map();
      const raw = covers[i];
      if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) continue;
      const key = this.shelfCoverKey(book, i);
      if (this.shelfCoverMap.get(key) && this.shelfCoverRawUrls.get(key) === raw) continue;
      try {
        const local = await BookCoverCache.resolveCachedCoverAsync(context, raw) ||
          await BookCoverCache.resolveCover(context, raw);
        if (revision !== this.shelfCoverCacheRevision) return new Map();
        if (local && local !== raw) {
          this.shelfCoverRawUrls.set(key, raw);
          updates.set(key, local);
        }
      } catch (e) {
        console.warn('缓存书架封面失败:', e);
      }
    }
    return updates;
  }

  queueShelfCoverUpdates(updates: Map<string, string>, revision: number): void {
    if (revision !== this.shelfCoverCacheRevision || updates.size === 0) return;
    updates.forEach((value: string, key: string) => this.pendingShelfCoverUpdates.set(key, value));
    if (this.shelfCoverUpdateTimer >= 0) return;
    this.shelfCoverUpdateTimer = setTimeout(() => {
      this.shelfCoverUpdateTimer = -1;
      if (revision !== this.shelfCoverCacheRevision || this.pendingShelfCoverUpdates.size === 0) return;
      const nextMap = new Map(this.shelfCoverMap);
      this.pendingShelfCoverUpdates.forEach((value: string, key: string) => nextMap.set(key, value));
      this.pendingShelfCoverUpdates.clear();
      this.shelfCoverMap = nextMap;
    }, SHELF_COVER_UPDATE_BATCH_MS);
  }

  /** 标题行收起量，0 为完整显示，CollapsingHeader.DISTANCE 为完全收起；类型页签不收起。 */
  @State shelfHeaderCollapse: number = 0;
  onHeaderCollapseChange: (progress: number) => void = () => {};
  private shelfListScroller: ListScroller = new ListScroller();
  private shelfTileScroller: Scroller = new Scroller();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Column() {
        // 列表上滑时标题行收起：外层按收起量变矮并裁剪，标题行贴底上移并淡出。
        Stack({ alignContent: Alignment.Bottom }) {
          Row() {
            if (this.isTileGroupPage() && !this.isBookMultiSelect) {
              ImmersiveBackButton({
                iconColor: this.primaryTextColor(),
                darkMode: this.appDarkMode,
                buttonSize: 40,
                containerWidth: 56,
                materialScale: 0.83,
                compactLayout: true,
                onBack: () => this.exitTileGroupPage()
              })
              Text(this.activeShelfGroupName())
                .fontSize(AppFontSize.TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Blank()
              if (this.books.length > 0) {
                this.shelfSortButton()
              }
              Text(this.books.length > 0 ? `${this.books.length}本` : '')
                .fontSize(AppFontSize.BODY)
                .fontColor('#999')
            } else {
              if (this.isBookMultiSelect) {
                Text('书架')
                  .fontSize(AppFontSize.DISPLAY)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.primaryTextColor())
              } else {
                this.shelfGroupSwitcher()
              }

              if (this.isBookMultiSelect) {
                Blank()
                Text('取消')
                  .fontSize(AppFontSize.BODY_LARGE)
                  .fontColor(this.primaryTextColor())
                  .width(52)
                  .height(56)
                  .textAlign(TextAlign.Center)
                  .onClick(() => this.exitBookMultiSelect())
              } else {
                Blank()

                if (this.books.length > 0) {
                  this.shelfSortButton()
                }

                this.shelfFilterButton()
                this.shelfLayoutButton()
              }
            }
          }
          .width('100%')
          .height(56 + this.statusBarHeight)
          .padding({
            left: this.isTileGroupPage() && !this.isBookMultiSelect ? 0 : AppSpacing.XL,
            right: AppSpacing.XL,
            top: this.statusBarHeight
          })
          .alignItems(VerticalAlign.Center)
          .opacity(CollapsingHeader.contentOpacity(this.shelfHeaderCollapseValue()))
          .hitTestBehavior(CollapsingHeader.acceptsTouch(this.shelfHeaderCollapseValue()) ? HitTestMode.Default : HitTestMode.None)
        }
        .width('100%')
        .height(56 + this.statusBarHeight - this.shelfHeaderCollapseValue())
        .clip(true)
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.onHeaderCollapseChange((56 + this.statusBarHeight - Number(newArea.height)) /
            CollapsingHeader.DISTANCE);
        })

        if (this.shelfSearchActive) {
          this.shelfSearchBar()
        }

        if (this.showsShelfScopeTabs()) {
          this.shelfScopeTabs()
        }

        if (this.isBookMultiSelect) {
          this.bookSelectionStatusBar()
        }

        }
        .width('100%')
        .position({ x: 0, y: 0 })
        .zIndex(4)

        StatusBarScrim({ statusBarHeight: this.statusBarHeight, pageColor: this.pageColor(),
          scrimOpacity: CollapsingHeader.scrimOpacity(this.shelfHeaderCollapseValue()) })
          .width('100%')
          .position({ x: 0, y: 0 })
          .zIndex(3)

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
            Text('加载中...')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .margin({ top: AppSpacing.MD })
          }
          .width('100%')
          .height('100%')
          .padding({ top: this.bookshelfTopOverlayHeight() })
          .justifyContent(FlexAlign.Center)
          .translate({ x: this.shelfScopeTransitionX })
          .scale({ x: this.shelfScopeTransitionScale, y: this.shelfScopeTransitionScale })
          .opacity(this.shelfScopeTransitionOpacity)
          .priorityGesture(
            PanGesture({ direction: PanDirection.Horizontal, distance: 24 })
              .onActionStart(() => {
                this.markShelfScopePanGesture(500);
              })
              .onActionUpdate(() => {
                this.markShelfScopePanGesture(240);
              })
              .onActionEnd((event: GestureEvent) => {
                this.switchShelfScopeBySwipe(event.offsetX);
              })
          )
        } else if (this.books.length === 0) {
          Column() {
            SymbolGlyph($r('sys.symbol.bookshelf'))
              .fontSize(56)
              .fontColor([this.subTextColor()])
              .opacity(0.5)
              .margin({ bottom: AppSpacing.XL })
            Text('暂无书籍')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.subTextColor())
            Text(this.shelfScopeEmptyHint())
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .margin({ top: AppSpacing.MD })
          }
          .width('100%')
          .height('100%')
          .padding({ top: this.bookshelfTopOverlayHeight() })
          .justifyContent(FlexAlign.Center)
          .translate({ x: this.shelfScopeTransitionX })
          .scale({ x: this.shelfScopeTransitionScale, y: this.shelfScopeTransitionScale })
          .opacity(this.shelfScopeTransitionOpacity)
          .priorityGesture(
            PanGesture({ direction: PanDirection.Horizontal, distance: 24 })
              .onActionStart(() => {
                this.markShelfScopePanGesture(500);
              })
              .onActionUpdate(() => {
                this.markShelfScopePanGesture(240);
              })
              .onActionEnd((event: GestureEvent) => {
                this.switchShelfScopeBySwipe(event.offsetX);
              })
          )
        } else {
          Refresh({ refreshing: $$this.isShelfRefreshing, builder: this.shelfRefreshBuilder }) {
            if (this.isTileLayout()) {
              this.shelfTileGrid()
            } else {
              List({ scroller: this.shelfListScroller, space: AppSpacing.MD }) {
              ListItem() {
                Row()
                  .height(this.bookshelfTopOverlayHeight())
              }

              LazyForEach(this.shelfListBookDataSource(), (book: Book) => {
                ListItem() {
                  Row() {
                    if (this.isBookMultiSelect) {
                      Toggle({ type: ToggleType.Checkbox, isOn: this.isBookSelected(book.bookUrl) })
                        .selectedColor(this.buttonColor())
                        .margin({ right: AppSpacing.LG })
                        .onChange((isOn: boolean) => {
                          this.setBookSelected(book.bookUrl, isOn);
                        })
                    }
                    Column() {
                      if (this.isCompactLayout()) {
                        this.compactBookContent(book)
                      } else {
                        this.looseBookContent(book)
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .backgroundColor(this.glassCardColor())
                    .borderRadius(ThemeRuntime.mediumRadius())
                    .clip(true)
                    .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
                    .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
                    .gesture(
                      LongPressGesture({ repeat: false })
                        .onAction((event: GestureEvent) => {
                          if (!this.isBookMultiSelect) {
                            this.showBookActions(book, event);
                          }
                        })
                    )
                    .onClick((event: ClickEvent) => {
                      if (this.consumeShelfSwipeClick()) {
                        return;
                      }
                      if (this.isBookMultiSelect) {
                        this.toggleSelectedBook(book.bookUrl);
                        return;
                      }
                      this.openShelfBook(book, event.windowX, event.windowY);
                    })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
              }, (book: Book) => this.shelfBookRenderKey(book, `list_${this.shelfViewKey()}`))

              ListItem() {
                Column()
                  .height(this.bookshelfListBottomInset())
              }
            }
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .width('100%')
            .height('100%')
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
            .backgroundColor(this.pageColor())
            .onDidScroll((delta: number) => {
              this.onShelfListScroll(delta, this.shelfListScroller.currentOffset().yOffset);
            })
            .onScrollStop(() => {
              this.onShelfListScrollStop(this.shelfListScroller.currentOffset().yOffset);
            })
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
            }
          }
          .layoutWeight(1)
          .backgroundColor(this.pageColor())
          .refreshOffset(64)
          .onStateChange((state: RefreshStatus) => {
            this.updateShelfRefreshPrompt(state);
          })
          .onOffsetChange((offset: number) => {
            this.trackShelfRefreshPullOffset(offset);
          })
          .onRefreshing(() => {
            this.refreshBookshelfToc();
          })
          .translate({ x: this.shelfScopeTransitionX })
          .scale({ x: this.shelfScopeTransitionScale, y: this.shelfScopeTransitionScale })
          .opacity(this.shelfScopeTransitionOpacity)
          .priorityGesture(
            PanGesture({ direction: PanDirection.Horizontal, distance: 24 })
              .onActionStart(() => {
                this.markShelfScopePanGesture(500);
              })
              .onActionUpdate(() => {
                this.markShelfScopePanGesture(240);
              })
              .onActionEnd((event: GestureEvent) => {
                this.switchShelfScopeBySwipe(event.offsetX);
              })
          )
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .bindSheet(this.showBookGroupPicker, this.bookGroupPickerDialog(), this.bookGroupPickerSheetOptions())

      if (this.books.length > 0 && this.shouldShowShelfRefreshStatus()) {
        this.shelfRefreshStatusOverlay()
      }

      // 长按菜单的锚点：放在手指位置的 1×1 节点，弹出层贴着它弹出。
      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showActionDialog, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.bookActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          if (this.showActionDialog) this.closeBookActions();
        }))

      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showBookGroupActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.bookGroupActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          if (this.showBookGroupActionMenu) this.closeBookGroupActionMenu();
        }))

      if (this.isBookMultiSelect) {
        this.bookMultiSelectBar()
      }
      if (this.openingBook) {
        this.shelfBookOpeningOverlay(this.openingBook)
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => this.updateContextViewport(newValue))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.showNetworkCoverDialog, this.networkCoverSheet(), this.networkCoverSheetOptions())
  }

  /** 换源：系统对话框，API 26+ 是沉浸光感表面。 */
  @Builder
  changeSourceDialogContent() {
    BookChangeSourceDialog({
      targetBook: this.shelfChangeSourceTarget,
      onSwitched: (switched: Book): void => {
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        this.loadBooks();
      },
      onClosed: (): void => {
        this.showShelfChangeSourceDialog = false;
        this.shelfChangeSourceTarget = null;
      }
    })
  }

  syncChangeSourceDialog(): void {
    this.changeSourceDialogSession.sync(this.getUIContext(), this.showShelfChangeSourceDialog, (): void => {
      this.changeSourceDialogContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示换源弹窗失败:'
    });
  }

  /** 标题即分组切换：显示当前分组名，点开下拉选分组，旁边是当前视图的本数。 */
  @Builder
  shelfGroupSwitcher() {
    Row({ space: AppSpacing.XS }) {
      Text(this.shelfGroupTitle())
        .fontSize(AppFontSize.DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
      SymbolGlyph(this.showShelfGroupMenu ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.showShelfGroupMenu ? this.accentColor() : this.secondaryTextColor()])
      Text(this.shelfHeaderCountText())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
        .maxLines(1)
        .margin({ left: AppSpacing.XS })
    }
    // 窄屏上右侧按钮放不下时，标题这一段先收缩（分组名省略）。
    .flexShrink(1)
    .height(44)
    .alignItems(VerticalAlign.Center)
    .bindPopup(this.showShelfGroupMenu, this.shelfMenuPopupOptions((): void => {
      this.shelfGroupDropdown()
    }, Placement.BottomLeft, () => {
      this.showShelfGroupMenu = false;
    }))
    .accessibilityText(`${this.shelfGroupTitle()}，切换分组`)
    .onClick(() => {
      this.showShelfGroupMenu = !this.showShelfGroupMenu;
      this.showShelfSortMenu = false;
      this.showShelfLayoutMenu = false;
      this.showShelfFilterMenu = false;
    })
  }

  shelfGroupTitle(): string {
    if (this.activeShelfGroupId === 0) {
      return '书架';
    }
    if (this.activeShelfGroupId === -1) {
      return '未分组';
    }
    return this.activeShelfGroupName();
  }

  @Builder
  shelfGroupDropdown() {
    Column() {
      Scroll() {
        Column({ space: AppSpacing.XXS }) {
          this.shelfGroupMenuItem('全部书籍', 0)
          ForEach(this.shelfGroups, (group: BookGroup) => {
            this.shelfGroupMenuItem(group.groupName, group.groupId, group)
          }, (group: BookGroup) => `${group.groupId}_${group.groupName}`)
          this.shelfGroupMenuItem('未分组', -1)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.appDarkMode))
        .margin({ top: AppSpacing.XS, bottom: AppSpacing.XS, left: 12, right: 12 })

      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([this.accentColor()])
        Text('新建分组')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.accentColor())
      }
      .width('100%')
      .height(BookshelfPage.MENU_ITEM_HEIGHT)
      .padding({ left: 12, right: 12 })
      .borderRadius(this.shelfMenuItemRadius())
      .onClick(() => {
        this.showShelfGroupMenu = false;
        this.openAddBookGroupDialog();
      })

      if (this.shelfGroups.length > 0) {
        Text('长按分组可重命名或删除')
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .padding({ left: 12, top: AppSpacing.XXS, bottom: AppSpacing.XS })
      }
    }
    .width(220)
    .padding(BookshelfPage.MENU_PADDING)
  }

  @Builder
  shelfGroupMenuItem(label: string, groupId: number, group?: BookGroup) {
    Row({ space: AppSpacing.SM }) {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.activeShelfGroupId === groupId ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.activeShelfGroupId === groupId ? this.accentColor() : this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`${this.shelfGroupBookCount(groupId)}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
      if (this.activeShelfGroupId === groupId) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(BookshelfPage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.shelfMenuItemRadius())
    .backgroundColor(this.activeShelfGroupId === groupId ? this.selectedSoftBackgroundColor() : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.showShelfGroupMenu = false;
      this.selectShelfGroup(groupId);
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (!group) {
            return;
          }
          this.captureContextMenuAnchor(event);
          this.showShelfGroupMenu = false;
          this.pendingBookGroup = group;
          this.showBookGroupActionMenu = true;
        })
    )
  }

  /** 菜单里每个分组的本数：只看当前是普通还是隐私书架，不受类型和筛选影响。 */
  shelfGroupBookCount(groupId: number): number {
    const privateScope = this.shelfScope === 'private';
    let count = 0;
    for (const book of this.allBooks) {
      if (book.isPrivate !== privateScope) continue;
      if (groupId === 0 || (groupId === -1 ? book.group <= 0 : book.group === groupId)) {
        count++;
      }
    }
    return count;
  }

  @Builder
  bookSelectionStatusBar() {
    Row() {
      Text(this.areAllBooksSelected() ? '☑' : '☐')
        .fontSize(AppFontSize.TITLE)
        .fontColor(this.accentColor())
        .width(28)
        .textAlign(TextAlign.Center)
        .onClick(() => this.toggleAllBooks())

      Text(`已选择 ${this.selectedBookUrls.length}/${this.books.length}`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .margin({ left: AppSpacing.MD })
        .layoutWeight(1)

      Text(this.areAllBooksSelected() ? '取消全选' : '全选')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .padding({ left: AppSpacing.LG, right: AppSpacing.XS, top: AppSpacing.MD, bottom: AppSpacing.MD })
        .onClick(() => this.toggleAllBooks())
    }
    .width('100%')
    .height(42)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  bookMultiSelectBar() {
    Row({ space: 10 }) {
      Button('删除', { type: ButtonType.Normal })
        .layoutWeight(1)
        .height(42)
        .fontSize(AppFontSize.BODY)
        .borderRadius(ThemeRuntime.buttonRadius())
        .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .fontColor(ThemeRuntime.onAccentColor())
        .enabled(this.selectedBookUrls.length > 0)
        .onClick(() => {
          if (this.selectedBookUrls.length > 0) this.openBatchDeleteDialog();
        })
      Button('分组', { type: ButtonType.Normal })
        .layoutWeight(1)
        .height(42)
        .fontSize(AppFontSize.BODY)
        .borderRadius(ThemeRuntime.buttonRadius())
        .backgroundColor(this.buttonColor())
        .fontColor(ThemeRuntime.onAccentColor())
        .enabled(this.selectedBookUrls.length > 0)
        .onClick(() => {
          if (this.selectedBookUrls.length > 0) {
            this.groupPickerSingleBookUrl = '';
            this.showBookGroupPicker = true;
          }
        })
      Button('更多', { type: ButtonType.Normal })
        .layoutWeight(1)
        .height(42)
        .fontSize(AppFontSize.BODY)
        .borderRadius(ThemeRuntime.buttonRadius())
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .enabled(this.selectedBookUrls.length > 0)
        .onClick(() => {
          if (this.selectedBookUrls.length > 0) this.showMultiSelectMoreMenu = true;
        })
        .bindPopup(this.isBookMultiSelect && this.showMultiSelectMoreMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.multiSelectMoreMenu()
        }, Placement.TopRight, this.appDarkMode, this.accentColor(), () => {
          this.showMultiSelectMoreMenu = false;
        }))
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: 10, bottom: this.multiSelectBottomPadding() })
    .backgroundColor(this.glassCardColor())
    .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
    .alignSelf(ItemAlign.End)
  }

  /** 多选底栏“更多”菜单：系统菜单贴着按钮向上弹出。 */
  @Builder
  multiSelectMoreMenu() {
    Scroll() {
      Column() {
        if (this.privateShelfEnabled) {
          this.contextActionItem(this.shelfScope === 'private' ? $r('sys.symbol.lock_open') : $r('sys.symbol.lock'),
            this.shelfScope === 'private' ? '取消隐私' : '标记为隐私', this.primaryTextColor(), () => {
              this.showMultiSelectMoreMenu = false;
              this.setSelectedBooksPrivate(this.shelfScope !== 'private');
            })
        }
        // 选中的书里没有本地书籍时置灰且不可点。
        this.contextActionItem($r('sys.symbol.arrow_right_up_and_square'), '保存源文件',
          this.selectedLocalBooks().length > 0 ? this.primaryTextColor() : this.subTextColor(), () => {
            if (this.selectedLocalBooks().length === 0) return;
            this.showMultiSelectMoreMenu = false;
            this.openBatchExportDialog();
          })

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  /** 书籍长按菜单：系统菜单，API 26+ 挂沉浸光感材质。 */
  @Builder
  bookActionMenu() {
    Scroll() {
      Column() {
        if (this.pendingActionBook) {
          this.contextActionItem($r('sys.symbol.info_circle'), '查看书籍详情', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              const book = this.pendingActionBook;
              this.closeBookActions();
              this.openShelfBookDetail(book);
            }
          })
          this.contextActionItem($r('sys.symbol.pin'), this.pendingActionBook.isPinned ? '取消置顶' : '置顶',
            this.primaryTextColor(), () => {
              if (this.pendingActionBook) {
                const book = this.pendingActionBook;
                this.closeBookActions();
                this.toggleBookPinned(book);
              }
            })
          if (!LocalBookService.isLocalBook(this.pendingActionBook)) {
            this.contextActionItem($r('sys.symbol.arrow_left_arrow_right'), '换源', this.primaryTextColor(), () => {
              if (this.pendingActionBook) {
                const book = this.pendingActionBook;
                this.closeBookActions();
                this.openShelfChangeSource(book);
              }
            })
          }
          if (!LocalBookService.isLocalBook(this.pendingActionBook)) {
            this.contextActionItem($r('sys.symbol.download'), '缓存', this.primaryTextColor(), () => {
              if (this.pendingActionBook) {
                const book = this.pendingActionBook;
                this.showActionDialog = false;
                setTimeout(() => {
                  this.openCacheDialog(book);
                }, 0);
              }
            })
          }
          this.contextActionItem($r('sys.symbol.picture_badge_arrow_down'), '获取网络封面', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              const book = this.pendingActionBook;
              this.showActionDialog = false;
              this.pendingActionBook = null;
              this.openNetworkCoverPicker(book);
            }
          })
          if (this.pendingActionBook.customCoverUrl) {
            this.contextActionItem($r('sys.symbol.minus_circle'), '恢复默认封面',
              this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  const book = this.pendingActionBook;
                  this.closeBookActions();
                  this.restoreDefaultBookCover(book);
                }
              })
          }
          if (LocalBookService.isLocalBook(this.pendingActionBook)) {
            this.contextActionItem($r('sys.symbol.square_and_pencil'), '编辑书籍信息',
              this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  this.editingBookName = this.pendingActionBook.name;
                  this.editingBookAuthor = this.pendingActionBook.author;
                  this.showActionDialog = false;
                  this.openEditBookInfoDialog();
                }
              })
          }
          if (LocalBookService.isLocalBook(this.pendingActionBook)) {
            this.contextActionItem($r('sys.symbol.arrow_right_up_and_square'), '保存源文件',
              this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  const book = this.pendingActionBook;
                  this.showActionDialog = false;
                  setTimeout(() => {
                    this.saveLocalBookSource(book);
                  }, 0);
                }
              })
          }
          this.contextActionItem($r('sys.symbol.folder'), '移动分组', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              const bookUrl = this.pendingActionBook.bookUrl;
              this.showActionDialog = false;
              this.pendingActionBook = null;
              this.groupPickerSingleBookUrl = bookUrl;
              this.showBookGroupPicker = true;
            }
          })
          if (this.privateShelfEnabled) {
            this.contextActionItem(this.pendingActionBook.isPrivate ? $r('sys.symbol.lock_open') : $r('sys.symbol.lock'),
              this.pendingActionBook.isPrivate ? '取消隐私' : '标记为隐私', this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  const book = this.pendingActionBook;
                  this.closeBookActions();
                  this.toggleBookPrivate(book);
                }
              })
          }
          this.contextActionItem($r('sys.symbol.bookmark'), '自定义标签', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              this.editingTags = BookDisplayHelper.getBookTags(this.pendingActionBook);
              this.tagInput = '';
            }
            this.showActionDialog = false;
            this.openTagDialog();
          })
          this.contextActionItem($r('sys.symbol.checkmark_circle'), '多选', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              const bookUrl = this.pendingActionBook.bookUrl;
              this.closeBookActions();
              this.enterBookMultiSelect(bookUrl);
            }
          })
          this.contextActionItem($r('sys.symbol.trash'), '移出书架', ThemeRuntime.dangerColor(this.appDarkMode), () => {
            if (this.pendingActionBook) {
              const book = this.pendingActionBook;
              this.closeBookActions();
              this.showDeleteConfirm(book);
            }
          })
        }

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  /** 获取网络封面：半模态弹层，API 26+ 挂沉浸光感材质。 */
  @Builder
  networkCoverSheet() {
    Column() {
      Row() {
        Column() {
          Text('获取网络封面')
            .fontSize(AppFontSize.SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(`《${this.networkCoverTargetBook?.name || ''}》`)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: AppSpacing.MD }) {
          Button('自定义链接')
            .height(36)
            .fontSize(AppFontSize.CAPTION)
            .backgroundColor(this.buttonColor())
            .fontColor(ThemeRuntime.onAccentColor())
            .onClick(() => this.openCustomNetworkCoverDialog())
          Button('取消')
            .height(36)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeNetworkCoverPicker())
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: AppSpacing.MD }) {
        if (this.networkCoverSearching) {
          LoadingProgress()
            .width(18)
            .height(18)
        }
        Text(this.networkCoverStatus || '正在准备搜索...')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(2)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: AppSpacing.LG, bottom: 10 })

      if (this.networkCoverCandidates.length === 0 && !this.networkCoverSearching) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(42)
            .fontColor([this.subTextColor()])
          Text('未找到可用的网络封面')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.secondaryTextColor())
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.networkCoverCandidates, (candidate: SearchBook) => {
            GridItem() {
              Column() {
                Stack() {
                  Column() {
                    Text((candidate.name || '书').substring(0, 1))
                      .fontSize(28)
                      .fontColor('#FFFFFF')
                  }
                  .width('100%')
                  .aspectRatio(0.72)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(this.accentColor())

                  Image(this.imageCover(candidate.coverUrl))
                    .width('100%')
                    .height('100%')
                    .objectFit(ImageFit.Cover)
                }
                .width('100%')
                .aspectRatio(0.72)
                .borderRadius(7)
                .clip(true)
                .backgroundColor(this.inputColor())

                Text(candidate.name || '未知书名')
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(this.primaryTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: AppSpacing.SM })
                Text(candidate.originName || candidate.author || '启用书源')
                  .fontSize(AppFontSize.MICRO)
                  .fontColor(this.subTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: AppSpacing.XXS })
              }
              .width('100%')
              .padding(5)
              .borderRadius(ThemeRuntime.mediumRadius())
              .backgroundColor(this.glassCardColor())
              .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
              .onClick(() => this.applyNetworkCover(candidate))
            }
          }, (candidate: SearchBook) => candidate.coverUrl)
          GridItem() {
            Column()
              .height(68)
          }
          .columnStart(0)
          .columnEnd(this.networkCoverColumnCount() - 1)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .columnsTemplate(this.networkCoverColumnsTemplate())
        .columnsGap(this.networkCoverColumnGap())
        .rowsGap(this.networkCoverRowGap())
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: Math.max(this.navBarHeight, 12) + 12 })
  }

  networkCoverSheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      detents: ['72%', SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      // 只有下滑、点遮罩或返回才走这里；切到自定义链接弹窗是页面主动收起，不清空目标书籍。
      onWillDismiss: (): void => this.closeNetworkCoverPicker(),
      onWillSpringBackWhenDismiss: (): void => {}
    }, this.appDarkMode, this.accentColor());
  }

  /** 移动到分组：内容高度的半模态弹层。 */
  bookGroupPickerSheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      onWillDismiss: (): void => this.closeBookGroupPicker(),
      onWillSpringBackWhenDismiss: (): void => {}
    }, this.appDarkMode, this.accentColor());
  }

  @Builder
  batchExportDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('保存源文件').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      Text(`只能保存本地书籍的源文件，缓存书籍无法保存。将导出选中的 ${this.selectedLocalBooks().length} 本本地书籍。`)
        .fontSize(AppFontSize.BODY).fontColor(this.secondaryTextColor()).textAlign(TextAlign.Center)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeBatchExportDialog())
        Button('确认', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.buttonColor()).fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.closeBatchExportDialog();
            this.exportSelectedLocalBooks();
          })
      }.width('100%')
    }
    .padding(22)
  }

  openBatchExportDialog(): void {
    this.batchExportDialogSession.open(this.getUIContext(), (): void => {
      this.batchExportDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示保存源文件弹窗失败:'
    });
  }

  closeBatchExportDialog(): void {
    this.batchExportDialogSession.close(this.getUIContext());
  }

  @Builder
  bookGroupPickerDialog() {
    Column({ space: AppSpacing.SM }) {
      Text('移动到分组')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .height(32)
        .textAlign(TextAlign.Center)
      Scroll() {
        Column({ space: AppSpacing.XS }) {
          this.bookGroupPickerItem('未分组', 0)
          ForEach(this.shelfGroups, (group: BookGroup) => {
            this.bookGroupPickerItem(group.groupName, group.groupId)
          }, (group: BookGroup) => `picker_${group.groupId}`)
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .constraintSize({ maxHeight: 360 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: Math.max(this.navBarHeight, 12) + 12 })
  }

  @Builder
  bookGroupPickerItem(label: string, groupId: number) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.primaryTextColor())
      .width('100%')
      .height(38)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(this.glassCardColor())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .onClick(() => this.assignSelectedBooksToGroup(groupId))
  }

  @Builder
  addBookGroupDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('新增书籍分组').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      TextInput({ placeholder: '输入分组名称', text: this.newBookGroupName })
        .width('100%').height(42).backgroundColor(this.inputColor()).fontColor(this.primaryTextColor())
        .borderRadius(ThemeRuntime.mediumRadius()).onChange((value: string) => this.newBookGroupName = value)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeAddBookGroupDialog())
        Button('新增', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.buttonColor()).fontColor(ThemeRuntime.onAccentColor()).enabled(!!this.newBookGroupName.trim())
          .onClick(() => this.addShelfBookGroup())
      }.width('100%')
    }    .padding(22)
  }

  openAddBookGroupDialog(): void {
    this.newBookGroupName = '';
    this.showAddBookGroupDialog = true;
    this.addBookGroupDialogSession.open(this.getUIContext(), (): void => {
      this.addBookGroupDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示新增分组弹窗失败:'
    });
  }

  closeAddBookGroupDialog(): void {
    this.showAddBookGroupDialog = false;
    this.addBookGroupDialogSession.close(this.getUIContext());
  }


  @Builder
  bookGroupActionMenu() {
    Scroll() {
      Column() {
        this.contextActionItem($r('sys.symbol.square_and_pencil'), '重命名', this.primaryTextColor(), () => {
          this.renameBookGroupName = this.pendingBookGroup?.groupName || '';
          this.showBookGroupActionMenu = false;
          this.openRenameBookGroupDialog();
        })
        this.contextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
          this.pendingDeleteBookGroup = this.pendingBookGroup;
          this.showBookGroupActionMenu = false;
          this.openDeleteBookGroupDialog();
        })

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  renameBookGroupDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('重命名分组').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      TextInput({ placeholder: '输入分组名称', text: this.renameBookGroupName })
        .width('100%').height(42).backgroundColor(this.inputColor()).fontColor(this.primaryTextColor())
        .borderRadius(ThemeRuntime.mediumRadius()).onChange((value: string) => this.renameBookGroupName = value)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeRenameBookGroupDialog())
        Button('保存', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.buttonColor()).fontColor(ThemeRuntime.onAccentColor()).enabled(!!this.renameBookGroupName.trim())
          .onClick(() => this.renameShelfBookGroup())
      }.width('100%')
    }    .padding(22)
  }

  openRenameBookGroupDialog(): void {
    this.showRenameBookGroupDialog = true;
    this.renameBookGroupDialogSession.open(this.getUIContext(), (): void => {
      this.renameBookGroupDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示重命名分组弹窗失败:'
    });
  }


  @Builder
  deleteBookGroupDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('删除分组').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      Text(`删除“${this.pendingDeleteBookGroup?.groupName || ''}”后，分组内书籍将移到未分组。`)
        .fontSize(AppFontSize.BODY).fontColor(this.secondaryTextColor()).textAlign(TextAlign.Center)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeDeleteBookGroupDialog())
        Button('删除', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode)).fontColor(ThemeRuntime.onAccentColor()).onClick(() => this.deleteShelfBookGroup())
      }.width('100%')
    }    .padding(22)
  }

  openDeleteBookGroupDialog(): void {
    this.showDeleteBookGroupDialog = true;
    this.deleteBookGroupDialogSession.open(this.getUIContext(), (): void => {
      this.deleteBookGroupDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示删除分组弹窗失败:'
    });
  }


  @Builder
  batchDeleteBooksDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('批量删除').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      Text(`确定从书架移除选中的 ${this.selectedBookUrls.length} 本书吗？`)
        .fontSize(AppFontSize.BODY).fontColor(this.secondaryTextColor()).textAlign(TextAlign.Center)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeBatchDeleteDialog())
        Button('删除', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode)).fontColor(ThemeRuntime.onAccentColor()).onClick(() => this.deleteSelectedBooks())
      }.width('100%')
    }    .padding(22)
  }

  openBatchDeleteDialog(): void {
    this.showBatchDeleteDialog = true;
    this.batchDeleteDialogSession.open(this.getUIContext(), (): void => {
      this.batchDeleteBooksDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示批量删除弹窗失败:'
    });
  }

  closeBatchDeleteDialog(): void {
    this.showBatchDeleteDialog = false;
    this.batchDeleteDialogSession.close(this.getUIContext());
  }

  @Builder
  deleteBookDialogContent() {
    Column() {
      Text('确认删除')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.LG })

      Text(`确定要将《${this.pendingDeleteBook?.name || ''}》从书架移除吗？`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.XXL })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeDeleteBookDialog())

        Button('删除')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            if (this.pendingDeleteBook) {
              const book = this.pendingDeleteBook;
              this.closeDeleteBookDialog();
              this.pendingDeleteBook = null;
              this.deleteBook(book);
            }
          })
      }
      .width('100%')
    }
    .padding(AppSpacing.XXXL)
  }

  openDeleteBookDialog(): void {
    this.showDeleteDialog = true;
    this.deleteBookDialogSession.open(this.getUIContext(), (): void => {
      this.deleteBookDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示删除确认弹窗失败:'
    });
  }

  closeDeleteBookDialog(): void {
    this.showDeleteDialog = false;
    this.deleteBookDialogSession.close(this.getUIContext());
  }

  @Builder
  editBookInfoDialogContent() {
    Column() {
      Text('编辑书籍信息')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 18 })

      Text('书名')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .margin({ bottom: AppSpacing.SM })

      TextInput({ placeholder: '请输入书名', text: this.editingBookName })
        .width('100%')
        .height(44)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.editingBookName = value;
        })

      Text('作者')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .margin({ top: 14, bottom: AppSpacing.SM })

      TextInput({ placeholder: '请输入作者（可留空）', text: this.editingBookAuthor })
        .width('100%')
        .height(44)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.editingBookAuthor = value;
        })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeEditBookInfoDialog())

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(!!this.editingBookName.trim())
          .opacity(this.editingBookName.trim() ? 1 : 0.45)
          .onClick(() => this.saveLocalBookInfo())
      }
      .width('100%')
      .margin({ top: 22 })
    }
    .padding(AppSpacing.XXL)
  }

  openEditBookInfoDialog(): void {
    this.showEditBookInfoDialog = true;
    this.editBookInfoDialogSession.open(this.getUIContext(), (): void => {
      this.editBookInfoDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示编辑书籍信息弹窗失败:'
    });
  }

  @Builder
  tagDialogContent() {
    Column() {
      Text('自定义标签')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 14 })

      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.editingTags, (tag: string, index: number) => {
            Row() {
              Text(tag)
                .fontSize(AppFontSize.BODY)
                .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
              Text('×')
                .fontSize(AppFontSize.BODY)
                .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
                .margin({ left: AppSpacing.SM })
            }
            .padding({ left: 10, right: AppSpacing.MD, top: 5, bottom: 5 })
            .attributeModifier(BookDisplayHelper.getTagModifier(index, this.appDarkMode))
            .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
            .onClick(() => {
              this.removeEditingTag(tag);
            })
          })
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .width('100%')
      .constraintSize({ minHeight: 40, maxHeight: 220 })
      .margin({ bottom: AppSpacing.LG })

      Row() {
        TextInput({ placeholder: '输入标签', text: this.tagInput })
          .height(40)
          .layoutWeight(1)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.tagInput = value;
          })

        Button('添加')
          .height(40)
          .margin({ left: AppSpacing.MD })
          .onClick(() => {
            this.addEditingTag();
          })
      }
      .width('100%')
      .margin({ bottom: 18 })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.closeTagDialog();
          })

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.saveCustomTags();
          })
      }
      .width('100%')
    }
    .padding(18)
  }

  openTagDialog(): void {
    this.showTagDialog = true;
    this.tagDialogSession.open(this.getUIContext(), (): void => {
      this.tagDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示自定义标签弹窗失败:'
    });
  }

  closeTagDialog(): void {
    this.showTagDialog = false;
    this.pendingActionBook = null;
    this.tagDialogSession.close(this.getUIContext());
  }

  @Builder
  customCoverDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('使用自定义链接')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text(`《${this.networkCoverTargetBook?.name || ''}》`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      TextInput({ placeholder: '请输入图片 URL', text: this.customNetworkCoverUrl })
        .type(InputType.Normal)
        .width('100%')
        .height(44)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.customNetworkCoverUrl = value;
        })
      Text('仅支持 http 或 https 图片链接，图片是否可用由网络资源决定。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.closeCustomCoverDialog();
            this.showNetworkCoverDialog = true;
          })
        Button('设为封面', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(/^https?:\/\/[^\s]+$/i.test(this.customNetworkCoverUrl.trim()))
          .onClick(() => this.applyCustomNetworkCover())
      }
      .width('100%')
    }
    .padding(AppSpacing.XXL)
  }

  openCustomCoverDialog(): void {
    this.showCustomNetworkCoverDialog = true;
    // 取消按钮需回退到封面选择面板，蒙层关闭无对应流程，禁用 autoCancel。
    this.customCoverDialogSession.open(this.getUIContext(), (): void => {
      this.customCoverDialogContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示自定义封面弹窗失败:'
    });
  }

  closeCustomCoverDialog(): void {
    this.showCustomNetworkCoverDialog = false;
    this.customCoverDialogSession.close(this.getUIContext());
  }


  selectShelfGroup(groupId: number): void {
    if (this.activeShelfGroupId === groupId) {
      this.applyShelfScope();
      return;
    }
    if (this.shelfScopeSwitchAnimating) {
      return;
    }
    if (this.isTileLayout()) {
      this.activeShelfGroupId = groupId;
      return;
    }
    const currentIndex = this.shelfGroupOrderIndex(this.activeShelfGroupId);
    const nextIndex = this.shelfGroupOrderIndex(groupId);
    const outgoingX = nextIndex >= currentIndex ? -36 : 36;
    this.animateShelfContentUpdate(() => {
      this.activeShelfGroupId = groupId;
    }, outgoingX);
  }

  shelfGroupOrderIndex(groupId: number): number {
    if (groupId === 0) {
      return 0;
    }
    if (groupId === -1) {
      return this.shelfGroups.length + 1;
    }
    const index = this.shelfGroups.findIndex((group: BookGroup) => group.groupId === groupId);
    return index >= 0 ? index + 1 : 0;
  }

  isTileGroupPage(): boolean {
    return this.isTileLayout() && this.activeShelfGroupId > 0;
  }

  activeShelfGroupName(): string {
    const group = this.shelfGroups.find((item: BookGroup) => item.groupId === this.activeShelfGroupId);
    return group ? group.groupName : '书籍分组';
  }

  enterTileGroupPage(groupId: number): void {
    this.showShelfGroupMenu = false;
    this.showShelfSortMenu = false;
    this.showShelfLayoutMenu = false;
    this.showShelfFilterMenu = false;
    this.selectShelfGroup(groupId);
  }

  exitTileGroupPage(): void {
    this.showShelfGroupMenu = false;
    this.showShelfSortMenu = false;
    this.selectShelfGroup(0);
  }

  enterBookMultiSelect(initialBookUrl: string): void {
    this.isBookMultiSelect = true;
    this.selectedBookUrls = initialBookUrl ? [initialBookUrl] : [];
    this.showShelfSortMenu = false;
    this.showShelfLayoutMenu = false;
    this.showShelfFilterMenu = false;
    this.showShelfGroupMenu = false;
  }

  exitBookMultiSelect(): void {
    this.isBookMultiSelect = false;
    this.selectedBookUrls = [];
    this.showBookGroupPicker = false;
    this.groupPickerSingleBookUrl = '';
    this.showMultiSelectMoreMenu = false;
    this.closeBatchDeleteDialog();
    this.closeBatchExportDialog();
  }

  selectedLocalBooks(): Book[] {
    return this.allBooks.filter((book: Book) =>
      this.selectedBookUrls.includes(book.bookUrl) && LocalBookService.isLocalBook(book));
  }

  async setSelectedBooksPrivate(nextPrivate: boolean): Promise<void> {
    const urls = [...this.selectedBookUrls];
    const targets = this.allBooks.filter((book: Book) =>
      urls.includes(book.bookUrl) && book.isPrivate !== nextPrivate);
    const db = AppDatabase.getInstance();
    let changed = 0;
    for (const book of targets) {
      try {
        await db.setBookPrivate(book.bookUrl, nextPrivate);
        book.isPrivate = nextPrivate;
        changed++;
      } catch (e) {
        console.error('批量更新书籍隐私状态失败:', book.name, e);
      }
    }
    this.exitBookMultiSelect();
    await this.loadBooks(true);
    RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext).catch((e: Error) => {
      console.warn('刷新最近阅读卡片失败:', e);
    });
    const failed = targets.length - changed;
    const summary = nextPrivate ? `已将 ${changed} 本书移入隐私书架` : `已将 ${changed} 本书移出隐私书架`;
    HdsFeedback.showToast(failed > 0 ? `${summary}，${failed} 本失败` : summary);
  }

  async exportSelectedLocalBooks(): Promise<void> {
    const targets = this.selectedLocalBooks();
    if (targets.length === 0) return;
    try {
      const result = await LocalBookService.exportSourceFiles(getContext(this), targets);
      if (!result) return;
      this.exitBookMultiSelect();
      const failed = result.failedNames.length;
      if (result.savedCount === 0) {
        HdsFeedback.showToast('保存失败：源文件不存在或已被清理');
      } else {
        HdsFeedback.showToast(failed > 0 ?
          `已保存 ${result.savedCount} 本书的源文件，${failed} 本失败` :
          `已保存 ${result.savedCount} 本书的源文件`);
      }
    } catch (e) {
      console.error('批量保存本地书籍源文件失败:', e);
      HdsFeedback.showToast(`保存失败：${e instanceof Error ? e.message : String(e)}`);
    }
  }

  closeBookGroupPicker(): void {
    this.showBookGroupPicker = false;
    this.groupPickerSingleBookUrl = '';
  }

  toggleSelectedBook(bookUrl: string): void {
    this.setBookSelected(bookUrl, !this.isBookSelected(bookUrl));
  }

  isBookSelected(bookUrl: string): boolean {
    return this.selectedBookUrls.includes(bookUrl);
  }

  setBookSelected(bookUrl: string, selected: boolean): void {
    if (selected) {
      if (!this.isBookSelected(bookUrl)) {
        this.selectedBookUrls = this.selectedBookUrls.concat([bookUrl]);
      }
      return;
    }
    this.selectedBookUrls = this.selectedBookUrls.filter((url: string) => url !== bookUrl);
  }

  areAllBooksSelected(): boolean {
    return this.books.length > 0 && this.books.every((book: Book) => this.isBookSelected(book.bookUrl));
  }

  toggleAllBooks(): void {
    if (this.areAllBooksSelected()) {
      const visibleUrls = this.books.map((book: Book) => book.bookUrl);
      this.selectedBookUrls = this.selectedBookUrls.filter((url: string) => !visibleUrls.includes(url));
      return;
    }
    this.selectedBookUrls = this.books.map((book: Book) => book.bookUrl);
  }

  async addShelfBookGroup(): Promise<void> {
    const name = this.newBookGroupName.trim();
    if (!name) return;
    const db = AppDatabase.getInstance();
    const group = await db.addBookGroup(name);
    if (!group) {
      HdsFeedback.showToast('分组名称已存在');
      return;
    }
    this.closeAddBookGroupDialog();
    this.newBookGroupName = '';
    this.shelfGroups = await db.getCustomBookGroups();
    this.selectShelfGroup(group.groupId);
  }

  closeBookGroupActionMenu(): void {
    this.showBookGroupActionMenu = false;
    this.pendingBookGroup = null;
  }

  closeRenameBookGroupDialog(): void {
    this.showRenameBookGroupDialog = false;
    this.renameBookGroupDialogSession.close(this.getUIContext());
    this.renameBookGroupName = '';
    this.pendingBookGroup = null;
  }

  async renameShelfBookGroup(): Promise<void> {
    const group = this.pendingBookGroup;
    const name = this.renameBookGroupName.trim();
    if (!group || !name) return;
    const renamed = await AppDatabase.getInstance().renameBookGroup(group.groupId, name);
    if (!renamed) {
      HdsFeedback.showToast('分组名称已存在');
      return;
    }
    this.closeRenameBookGroupDialog();
    await this.loadBooks();
    HdsFeedback.showToast('分组已重命名');
  }

  closeDeleteBookGroupDialog(): void {
    this.showDeleteBookGroupDialog = false;
    this.deleteBookGroupDialogSession.close(this.getUIContext());
    this.pendingDeleteBookGroup = null;
    this.pendingBookGroup = null;
  }

  async deleteShelfBookGroup(): Promise<void> {
    const group = this.pendingDeleteBookGroup;
    if (!group) return;
    const db = AppDatabase.getInstance();
    await db.deleteBookGroup(group.groupId);
    if (this.activeShelfGroupId === group.groupId) this.activeShelfGroupId = -1;
    this.closeDeleteBookGroupDialog();
    await this.loadBooks();
    HdsFeedback.showToast('分组已删除，书籍已移到未分组');
  }

  async assignSelectedBooksToGroup(groupId: number): Promise<void> {
    const singleBookUrl = this.groupPickerSingleBookUrl;
    const targetUrls = singleBookUrl ? [singleBookUrl] : [...this.selectedBookUrls];
    if (targetUrls.length === 0) return;
    const count = targetUrls.length;
    const db = AppDatabase.getInstance();
    await db.updateBooksGroup(targetUrls, groupId);
    if (this.isBookMultiSelect) {
      this.exitBookMultiSelect();
    } else {
      this.closeBookGroupPicker();
    }
    await this.loadBooks();
    const groupName = groupId === 0 ? '未分组' :
      (this.shelfGroups.find((group: BookGroup) => group.groupId === groupId)?.groupName || '指定分组');
    HdsFeedback.showToast(count === 1 ? `已移动到“${groupName}”` : `已将 ${count} 本书移动到“${groupName}”`);
  }

  async deleteSelectedBooks(): Promise<void> {
    const urls = [...this.selectedBookUrls];
    const targets = this.allBooks.filter((book: Book) => urls.includes(book.bookUrl));
    const db = AppDatabase.getInstance();
    for (const book of targets) {
      this.deleteBookCoverCache(book);
      await CloudAutoSync.onBookRemoved(getContext(this), book).catch(() => undefined);
      LocalBookService.deleteLocalBookFiles(getContext(this), book);
      await db.deleteBook(book.bookUrl, 'bookshelf_batch_delete');
    }
    this.exitBookMultiSelect();
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    await this.loadBooks();
    HdsFeedback.showToast(`已删除 ${targets.length} 本书`);
  }


  /** 实际生效的标题行收起量：没有可滚动的列表时标题行始终完整显示。 */
  shelfHeaderCollapseValue(): number {
    return !this.isLoading && this.books.length > 0 && !this.isBookMultiSelect && !this.isTileGroupPage() ? this.shelfHeaderCollapse : 0;
  }

  onShelfListScroll(delta: number, offset: number): void {
    const next = CollapsingHeader.next(this.shelfHeaderCollapse, delta, offset);
    if (next !== this.shelfHeaderCollapse) {
      this.shelfHeaderCollapse = next;
    }
  }

  onShelfListScrollStop(offset: number): void {
    const target = CollapsingHeader.settle(this.shelfHeaderCollapse, offset);
    if (target !== this.shelfHeaderCollapse) {
      animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
        this.shelfHeaderCollapse = target;
      });
    }
  }

  /** 列表顶部留白按标题行完整显示时的高度预留，不随收起变化，避免滚动中列表跳动。 */
  bookshelfTopOverlayHeight(): number {
    let height = this.statusBarHeight + 56;
    if (this.shelfSearchActive) {
      height += BookshelfPage.SEARCH_BAR_HEIGHT + AppSpacing.MD;
    }
    if (this.showsShelfScopeTabs()) {
      height += BookshelfPage.SCOPE_TABS_HEIGHT + AppSpacing.MD;
    }
    if (this.isBookMultiSelect) {
      height += 42;
    }
    return height;
  }

  bookshelfTileTopSpacerHeight(): number {
    const gridTopPadding = 10;
    const comfortableGap = 12;
    // Grid 会在顶部占位项与首行之间继续添加 rowsGap，需要从占位高度中抵消。
    return Math.max(0, this.bookshelfTopOverlayHeight() + comfortableGap -
      gridTopPadding - this.shelfTileRowGap());
  }

  bookshelfListBottomInset(): number {
    const comfortableGap = 20;
    const multiSelectBarHeight = this.isBookMultiSelect ? 104 : 0;
    if (deviceInfo.sdkApiVersion < 23) {
      return comfortableGap + multiSelectBarHeight;
    }
    if (this.isBookMultiSelect) {
      return Math.max(this.navBarHeight, 8) + comfortableGap + multiSelectBarHeight;
    }
    const floatingTabHeight = 56;
    return floatingTabHeight + Math.max(this.navBarHeight, 8) + comfortableGap;
  }

  getBookColor(name: string): string {
    if (!name) return '#007DFF';
    const colors = ['#007DFF', '#E53935', '#43A047', '#EF6C00', '#8E24AA', '#00ACC1', '#D81B60', '#5E35B1'];
    let hash = 0;
    for (let i = 0; i < name.length; i++) {
      hash = name.charCodeAt(i) + ((hash << 5) - hash);
    }
    return colors[Math.abs(hash) % colors.length];
  }

  getDisplayTags(book: Book): string[] {
    const tags = BookDisplayHelper.getBookTags(book);
    return tags;
  }

  getShelfAuthorText(book: Book): string {
    return book.author || '作者未知';
  }

  /**
   * Second info line of the compact/loose shelf row: "<x小时前> · <最新章节名>".
   * The old "作者 · 最后更新 xxx" single line is split so the update time gets its own row and
   * can carry the latest chapter title. It shares the author line's font and colour.
   */
  getShelfUpdateLineText(book: Book): string {
    const timeText = BookDisplayHelper.getLastUpdateRelativeText(book);
    const chapterText = (book.latestChapterTitle || '').trim();
    if (timeText && chapterText) {
      return `${timeText} · ${chapterText}`;
    }
    return timeText || chapterText;
  }

  // --- 书架行排版尺寸 ---------------------------------------------------------
  // 封面需要「顶部对齐书名、底部对齐最后一行文字」，所以下面这些行高必须是确定值：
  // 先用它们算出信息块总高度，再把封面高度设成同一个值，两端自然像素对齐。
  // 信息块内部恒有一个 Blank()，所以某本书没有更新行时，尾部仍会被顶到底部。

  shelfRowSpace(): number {
    return 4;
  }

  shelfTitleLineHeight(): number {
    return 20;
  }

  /** 作者名、更新时间行、宽松布局的「xx章未读」：字号 14。 */
  shelfTextLineHeight(): number {
    return 19;
  }

  /** 紧凑布局在关闭进度条时显示的「xx章未读」：字号 12。 */
  shelfSmallTextLineHeight(): number {
    return 16;
  }

  shelfProgressPanelHeight(): number {
    return this.shelfSmallTextLineHeight() + 4 + 3;
  }

  /** 信息块最后一行的高度——封面底部与它对齐。 */
  shelfInfoTailHeight(): number {
    return this.bookshelfShowProgressBar ? this.shelfProgressPanelHeight() : this.shelfSmallTextLineHeight();
  }

  /** 紧凑布局信息块高度 = 标题行 + 作者行 + 更新行 + 尾部行 + 4 个行间距。 */
  shelfCompactInfoHeight(): number {
    return this.shelfTitleLineHeight() + this.shelfTextLineHeight() + this.shelfTextLineHeight() +
      this.shelfInfoTailHeight() + this.shelfRowSpace() * 4;
  }

  /** 宽松布局信息块高度，尾部是「xx章未读」那一行。 */
  shelfLooseInfoHeight(): number {
    return this.shelfTitleLineHeight() + this.shelfTextLineHeight() + this.shelfTextLineHeight() +
      this.shelfTextLineHeight() + this.shelfRowSpace() * 4;
  }

  /** 封面沿用 7:9 的书籍比例，高度跟随信息块，宽度按比例推导。 */
  shelfCoverWidth(infoHeight: number): number {
    return Math.round(infoHeight * 7 / 9);
  }

  isCompactLayout(): boolean {
    return this.bookshelfLayoutMode !== 'loose';
  }

  isTileLayout(): boolean {
    return this.bookshelfLayoutMode === 'tile';
  }

  /** 搜索时把分组文件夹摊开，命中的书直接排出来，不会被折进文件夹里。 */
  shouldUseTileGroupFolders(): boolean {
    return this.isTileLayout() && this.activeShelfGroupId === 0 && !this.isBookMultiSelect &&
      !this.shelfAppliedSearchKeyword;
  }

  getUngroupedTileBooks(): Book[] {
    return this.books.filter((book: Book) => book.group <= 0 ||
      !this.shelfGroups.some((group: BookGroup) => group.groupId === book.group));
  }

  getLatestReadTileBook(books: Book[] = this.books): Book | null {
    let latest: Book | null = null;
    let latestReadTime = 0;
    books.forEach((book: Book) => {
      const readTime = this.getBookReadTime(book);
      if (readTime > latestReadTime) {
        latest = book;
        latestReadTime = readTime;
      }
    });
    return latest;
  }

  getLatestReadTileBooks(books: Book[] = this.books): Book[] {
    const latest = this.getLatestReadTileBook(books);
    return latest ? [latest] : [];
  }

  shouldShowLatestExpandedTileBook(): boolean {
    return this.isTileLayout() && this.bookshelfLastReadPinMode !== 'off' && this.activeShelfGroupId === 0 &&
      !this.isBookMultiSelect && !this.shelfAppliedSearchKeyword;
  }

  isLatestTileCardLarge(): boolean {
    return this.bookshelfLastReadPinMode === 'large';
  }

  getTileBooksWithoutLatest(books: Book[], latest: Book | null = this.getLatestReadTileBook(books)): Book[] {
    const uniqueBooks: Book[] = [];
    const seenBookUrls = new Set<string>();
    books.forEach((book: Book) => {
      const bookUrl = (book.bookUrl || '').trim();
      if (bookUrl && seenBookUrls.has(bookUrl)) return;
      if (bookUrl) seenBookUrls.add(bookUrl);
      uniqueBooks.push(book);
    });
    if (!this.shouldShowLatestExpandedTileBook()) {
      return uniqueBooks;
    }
    const latestBookUrl = (latest?.bookUrl || '').trim();
    return latestBookUrl ?
      uniqueBooks.filter((book: Book) => (book.bookUrl || '').trim() !== latestBookUrl) : uniqueBooks;
  }

  getTileFolderGroups(books: Book[] = this.books): BookGroup[] {
    const visibleGroupIds = new Set<number>();
    books.forEach((book: Book) => {
      if (book.group > 0) {
        visibleGroupIds.add(book.group);
      }
    });
    return this.shelfGroups.filter((group: BookGroup) => visibleGroupIds.has(group.groupId));
  }

  getSortedTileRootEntries(books: Book[] = this.books, mode: string = this.sortMode): ShelfTileSortEntry[] {
    // The expanded recent-read card and the ordinary grid must be derived from the same snapshot.
    // Reading-page return updates allBooks/books in separate reactive assignments; consulting allBooks here used
    // to let the new expanded card coexist with the old ordinary entry for one retained data-source generation.
    const latestBook = this.getLatestReadTileBook(books);
    const latestBookUrl = (latestBook?.bookUrl || '').trim();
    const cacheKey = `${mode}_${this.shelfViewKey()}_${this.activeShelfGroupId}_${this.isBookMultiSelect ? '1' : '0'}_` +
      `${this.shouldShowLatestExpandedTileBook() ? latestBookUrl : ''}_` +
      `${books.map((book: Book) => `${book.bookUrl}:${book.name}:${this.getBookReadTime(book)}:${this.getBookAddTime(book)}:` +
        `${book.group}:${book.isPinned ? '1' : '0'}`).join('|')}_` +
      `${this.shelfGroups.map((group: BookGroup) => `${group.groupId}:${group.groupName}`).join('|')}`;
    if (cacheKey === this.shelfTileEntriesCacheKey) {
      return this.shelfTileEntriesCache;
    }
    const entries: ShelfTileSortEntry[] = [];
    // 置顶书籍在“全部”平铺页作为根级快捷项展示；它仍保留原分组归属，进入分组后也可找到。
    const ungroupedBooks = this.getTileBooksWithoutLatest(books.filter((book: Book) => book.isPinned ||
      book.group <= 0 || !this.shelfGroups.some((group: BookGroup) => group.groupId === book.group)), latestBook);
    ungroupedBooks.forEach((book: Book, index: number) => {
      const entry = new ShelfTileSortEntry();
      entry.kind = 'book';
      entry.key = `book_${this.shelfViewKey()}_${book.bookUrl}`;
      entry.book = book;
      entry.readTime = this.getBookReadTime(book);
      entry.addTime = this.getBookAddTime(book);
      entry.name = this.normalizeBookName(book.name);
      entry.pinned = book.isPinned;
      entry.originalOrder = index;
      entries.push(entry);
    });

    const bookOffset = ungroupedBooks.length;
    this.getTileFolderGroups(books).forEach((group: BookGroup, index: number) => {
      const groupBooks = books.filter((book: Book) => book.group === group.groupId);
      const entry = new ShelfTileSortEntry();
      entry.kind = 'group';
      entry.key = `group_${this.shelfViewKey()}_${group.groupId}`;
      entry.group = group;
      entry.readTime = this.latestTileGroupReadTime(groupBooks);
      entry.addTime = this.latestTileGroupAddTime(groupBooks);
      entry.name = this.normalizeBookName(group.groupName);
      entry.originalOrder = bookOffset + index;
      entries.push(entry);
    });

    entries.sort((a: ShelfTileSortEntry, b: ShelfTileSortEntry) => this.compareTileRootEntry(a, b, mode));
    this.shelfTileEntriesCacheKey = cacheKey;
    this.shelfTileEntriesCache = entries;
    return entries;
  }

  shelfListBookDataSource(): ShelfBookDataSource {
    this.shelfListBooksSource.replace(this.books);
    return this.shelfListBooksSource;
  }

  shelfTileBookDataSource(): ShelfBookDataSource {
    this.shelfTileBooksSource.replace(this.getTileBooksWithoutLatest(this.books));
    return this.shelfTileBooksSource;
  }

  shelfTileEntryDataSource(): ShelfTileEntryDataSource {
    this.shelfTileEntriesSource.replace(this.getSortedTileRootEntries());
    return this.shelfTileEntriesSource;
  }

  latestTileGroupReadTime(books: Book[]): number {
    let latest = 0;
    books.forEach((book: Book) => {
      latest = Math.max(latest, this.getBookReadTime(book));
    });
    return latest;
  }

  latestTileGroupAddTime(books: Book[]): number {
    let latest = 0;
    books.forEach((book: Book) => {
      latest = Math.max(latest, this.getBookAddTime(book));
    });
    return latest;
  }

  compareTileRootEntry(a: ShelfTileSortEntry, b: ShelfTileSortEntry, mode: string = this.sortMode): number {
    if (a.pinned !== b.pinned) {
      return a.pinned ? -1 : 1;
    }
    if (mode === 'name') {
      const nameDiff = a.name.localeCompare(b.name, 'zh-Hans-CN-u-co-pinyin');
      return nameDiff !== 0 ? nameDiff : a.originalOrder - b.originalOrder;
    }
    const timeDiff = mode === 'recentAdd' ? b.addTime - a.addTime : b.readTime - a.readTime;
    if (timeDiff !== 0) {
      return timeDiff;
    }
    const nameDiff = a.name.localeCompare(b.name, 'zh-Hans-CN-u-co-pinyin');
    return nameDiff !== 0 ? nameDiff : a.originalOrder - b.originalOrder;
  }

  getTileGroupBooks(groupId: number): Book[] {
    return this.books.filter((book: Book) => book.group === groupId);
  }

  getTileGroupPreviewBooks(groupId: number): Book[] {
    return this.getTileGroupBooks(groupId).slice(0, 4);
  }

  shelfTileColumnCount(): number {
    const horizontalPadding = 40;
    const targetCoverWidth = 104;
    const preferredColumnGap = 20;
    const contentWidth = Math.max(1, this.shelfTileViewportWidth - horizontalPadding);
    // 以当前手机端约 104vp 的封面宽度为视觉基准，展开屏增加列数而不是放大封面。
    const fittedCount = Math.round(
      (contentWidth + preferredColumnGap) / (targetCoverWidth + preferredColumnGap)
    );
    return Math.max(3, Math.min(24, fittedCount));
  }

  shelfTileColumnsTemplate(): string {
    const columnCount = this.shelfTileColumnCount();
    let template = '1fr';
    for (let index = 1; index < columnCount; index++) {
      template += ' 1fr';
    }
    return template;
  }

  shelfTileColumnGap(): number {
    const horizontalPadding = 40;
    const targetCoverWidth = 104;
    const columnCount = this.shelfTileColumnCount();
    const contentWidth = Math.max(1, this.shelfTileViewportWidth - horizontalPadding);
    const fittedGap = columnCount > 1 ?
      (contentWidth - targetCoverWidth * columnCount) / (columnCount - 1) : 20;
    // 只在原 20vp 附近微调间距，避免宽屏上书籍过散或挤在一起。
    return Math.max(16, Math.min(24, fittedGap));
  }

  shelfTileRowGap(): number {
    return Math.max(24, Math.min(30, this.shelfTileColumnGap() + 8));
  }

  shelfTileExpandedCoverAspectRatio(): number {
    const columnCount = this.shelfTileColumnCount();
    const horizontalPadding = 40;
    const columnGap = this.shelfTileColumnGap();
    const contentWidth = Math.max(1, this.shelfTileViewportWidth - horizontalPadding);
    const columnWidth = Math.max(1, (contentWidth - columnGap * (columnCount - 1)) / columnCount);
    const expandedWidth = columnWidth * 2 + columnGap;
    // 普通封面的宽高比为 0.735；跨两列后根据实际列宽换算，确保上下边缘完全对齐。
    return expandedWidth * 0.735 / columnWidth;
  }

  @Builder
  shelfTileGrid() {
    Grid(this.shelfTileScroller) {
      GridItem() {
        Row()
          .height(this.bookshelfTileTopSpacerHeight())
      }
      .columnStart(0)
      .columnEnd(this.shelfTileColumnCount() - 1)

      if (this.shouldShowLatestExpandedTileBook()) {
        if (this.isLatestTileCardLarge()) {
          ForEach(this.getLatestReadTileBooks(this.books), (book: Book) => {
          GridItem() {
            this.shelfTileLatestCard(book)
          }
          // 占满整行：宽屏列数多于三列时，旁边若再排一本书，卡片与封面高度对不齐。
          .columnStart(0)
          .columnEnd(this.shelfTileColumnCount() - 1)
          }, (book: Book) => this.shelfBookRenderKey(book, `latest_card_${this.shelfViewKey()}`))
        } else {
          ForEach(this.getLatestReadTileBooks(this.books), (book: Book) => {
          GridItem() {
            this.shelfTileExpandedBook(book)
          }
          .columnStart(0)
          .columnEnd(1)
          }, (book: Book) => this.shelfBookRenderKey(book, `expanded_${this.shelfViewKey()}`))
        }
      }

      if (this.shouldUseTileGroupFolders()) {
        LazyForEach(this.shelfTileEntryDataSource(), (entry: ShelfTileSortEntry) => {
          GridItem() {
            if (entry.kind === 'group' && entry.group) {
              this.shelfTileGroupFolder(entry.group)
            } else if (entry.book) {
              this.shelfTileBook(entry.book)
            }
          }
        }, (entry: ShelfTileSortEntry) => entry.book ?
          this.shelfBookRenderKey(entry.book, entry.key) : entry.key)
      } else {
        LazyForEach(this.shelfTileBookDataSource(), (book: Book) => {
          GridItem() {
            this.shelfTileBook(book)
          }
        }, (book: Book) => this.shelfBookRenderKey(book, `tile_${this.shelfViewKey()}`))
      }

      GridItem() {
        Column()
          .height(this.bookshelfListBottomInset())
      }
      .columnStart(0)
      .columnEnd(this.shelfTileColumnCount() - 1)
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height('100%')
    .columnsTemplate(this.shelfTileColumnsTemplate())
    .columnsGap(this.shelfTileColumnGap())
    .rowsGap(this.shelfTileRowGap())
    .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: 10 })
    .backgroundColor(this.pageColor())
    .scrollBar(BarState.Off)
    .cachedCount(4)
    .onDidScroll((delta: number) => {
      this.onShelfListScroll(delta, this.shelfTileScroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      this.onShelfListScrollStop(this.shelfTileScroller.currentOffset().yOffset);
    })
    .translate({ x: this.tileGroupTransitionX })
    .scale({ x: this.tileGroupTransitionScale, y: this.tileGroupTransitionScale })
    .opacity(this.tileGroupTransitionOpacity)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = this.areaDimension(newValue.width);
      if (width > 0 && Math.abs(width - this.shelfTileViewportWidth) >= 1) {
        this.shelfTileViewportWidth = width;
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  shelfTileExpandedBook(book: Book) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row({ space: AppSpacing.XXS }) {
          Stack({ alignContent: Alignment.TopStart }) {
            this.coverView(book, '100%', '100%', ImageFit.Fill)
            if (!this.isBookMultiSelect) {
              this.bookPinnedCoverIndicator(book)
            }
            this.bookTypeCoverBadge(book)
          }
          .layoutWeight(1)
          .height('100%')
          .borderRadius({ topLeft: 7, bottomLeft: 7 })
          .clip(true)

          Column() {
            this.shelfLastReadLeaf(book)
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ left: 7, right: 7, top: 7, bottom: AppSpacing.SM })
          .backgroundColor(this.shelfTilePageColor())
          .borderRadius({ topRight: 7, bottomRight: 7 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
        .borderRadius(7)
        .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
        .clip(true)

        if (this.isBookMultiSelect) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.isBookSelected(book.bookUrl)) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(12)
                .fontColor(['#FFFFFF'])
            }
          }
          .width(22)
          .height(22)
          .backgroundColor(this.isBookSelected(book.bookUrl) ? this.buttonColor() :
            ThemeRuntime.glassPanelColor(this.appDarkMode))
          .border({ width: 1, color: this.isBookSelected(book.bookUrl) ? this.buttonColor() : this.glassBorderColor() })
          .borderRadius(11)
          .margin({ left: AppSpacing.SM, top: AppSpacing.SM })
        }
      }
      .width('100%')
      .aspectRatio(this.shelfTileExpandedCoverAspectRatio())
      .border({ width: this.isBookSelected(book.bookUrl) ? 2 : 0, color: this.accentColor() })
      .borderRadius(7)

      Row({ space: AppSpacing.XS }) {
        Text(this.shelfTileBookDisplayName(book))
          .fontSize(AppFontSize.CAPTION)
          .lineHeight(18)
          .height(36)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_WORD)
          .layoutWeight(1)
      }
      .width('100%')
      .height(36)
      .alignItems(VerticalAlign.Center)

      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(13)
          .fontColor([this.subTextColor()])
        Text(this.bookshelfShowProgressBar ? this.getReadProgressPercentText(book) : this.getShelfProgressText(book))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(18)
      .alignItems(VerticalAlign.Bottom)

      if (this.bookshelfShowProgressBar) {
        Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(3)
          .color(this.accentColor())
          .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false })
          .onAction((event: GestureEvent) => {
            if (!this.isBookMultiSelect) {
              this.showBookActions(book, event);
            }
          }),
        TapGesture()
          .onAction((event: GestureEvent) => {
            if (this.consumeShelfSwipeClick()) {
              return;
            }
            if (this.isBookMultiSelect) {
              this.toggleSelectedBook(book.bookUrl);
              return;
            }
            const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
            this.openShelfBook(book, finger ? finger.globalX : this.contextViewportWidth / 2,
              finger ? finger.globalY : this.contextViewportHeight / 2);
          })
      ),
      GestureMask.IgnoreInternal
    )
  }

  // “大”样式：占满一整行的继续阅读卡片，左侧书名与进度，右侧封面。
  @Builder
  shelfTileLatestCard(book: Book) {
    Row({ space: AppSpacing.LG }) {
      Column() {
        Text('继续阅读')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
          .maxLines(1)

        Text(this.shelfTileBookDisplayName(book))
          .width('100%')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_WORD)
          .margin({ top: AppSpacing.SM })

        Text(this.getReadChapterText(book) || this.getLastReadChapterText(book))
          .width('100%')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: AppSpacing.SM })

        Blank()
          .layoutWeight(1)

        Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(this.accentColor())
          .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
      .alignItems(HorizontalAlign.Start)

      Stack({ alignContent: Alignment.TopStart }) {
        this.coverView(book, '100%', '100%', ImageFit.Cover)
        this.bookTypeCoverBadge(book)
      }
      .height('100%')
      .aspectRatio(0.735)
      .borderRadius(6)
      .clip(true)
      .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
    }
    .width('100%')
    .height(this.shelfTileLatestCardHeight())
    .padding(AppSpacing.XL)
    .backgroundColor(this.glassCardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
    .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(),
      offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false })
          .onAction((event: GestureEvent) => {
            this.showBookActions(book, event);
          }),
        TapGesture()
          .onAction((event: GestureEvent) => {
            if (this.consumeShelfSwipeClick()) {
              return;
            }
            const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
            this.openShelfBook(book, finger ? finger.globalX : this.contextViewportWidth / 2,
              finger ? finger.globalY : this.contextViewportHeight / 2);
          })
      ),
      GestureMask.IgnoreInternal
    )
  }

  shelfTileLatestCardHeight(): number {
    const horizontalPadding = 40;
    const columnCount = this.shelfTileColumnCount();
    const columnGap = this.shelfTileColumnGap();
    const contentWidth = Math.max(1, this.shelfTileViewportWidth - horizontalPadding);
    const columnWidth = Math.max(1, (contentWidth - columnGap * (columnCount - 1)) / columnCount);
    // 封面约占一列宽度的七成，卡片高度随之换算，宽屏多列时也不会被拉得过高。
    return Math.round(columnWidth * 0.7 / 0.735) + AppSpacing.XL * 2;
  }

  @Builder
  shelfTileGroupFolder(group: BookGroup) {
    Column({ space: AppSpacing.XS }) {
      // Use one outer surface for both the themed folder artwork and the
      // four-cover preview so folders carry the same radius, border and shadow
      // weight as ordinary shelf cards.
      Stack() {
        if (this.shouldUseThemeBookCover()) {
          Image(this.activeThemeShelfFolder())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
        } else {
          Grid() {
            ForEach(this.getTileGroupPreviewBooks(group.groupId), (book: Book) => {
              GridItem() {
                this.coverView(book, '100%', '100%', ImageFit.Cover)
              }
            }, (book: Book) => this.shelfBookRenderKey(book, `group_${group.groupId}`))
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%')
          .height('100%')
          .columnsTemplate('1fr 1fr')
          .rowsTemplate('1fr 1fr')
          .columnsGap(AppSpacing.SM)
          .rowsGap(AppSpacing.SM)
          .padding(AppSpacing.MD)
          .backgroundColor(this.glassCardColor())
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .aspectRatio(0.735)
      .borderRadius(7)
      .clip(true)
      .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
      .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(),
        offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })

      Text(group.groupName)
        .width('100%')
        .height(36)
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(13)
          .fontColor([this.subTextColor()])
        Text(`共 ${this.getTileGroupBooks(group.groupId).length} 本`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      .height(18)
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false })
          .onAction((event: GestureEvent) => {
            this.captureContextMenuAnchor(event);
            this.pendingBookGroup = group;
            this.showBookGroupActionMenu = true;
          }),
        TapGesture()
          .onAction(() => {
            this.enterTileGroupPage(group.groupId);
          })
      ),
      GestureMask.IgnoreInternal
    )
  }

  @Builder
  shelfTileBook(book: Book) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.coverView(book, '100%', '100%', ImageFit.Cover)

        if (!this.isBookMultiSelect) {
          this.bookPinnedCoverIndicator(book)
        }
        this.bookTypeCoverBadge(book)

        if (this.isBookMultiSelect) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.isBookSelected(book.bookUrl)) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(12)
                .fontColor(['#FFFFFF'])
            }
          }
            .width(22)
            .height(22)
            .backgroundColor(this.isBookSelected(book.bookUrl) ? this.buttonColor() :
              ThemeRuntime.glassPanelColor(this.appDarkMode))
            .border({ width: 1, color: this.isBookSelected(book.bookUrl) ? this.buttonColor() : this.glassBorderColor() })
            .borderRadius(11)
            .margin({ left: AppSpacing.SM, top: AppSpacing.SM })
        }

        if (this.shouldShowBookSource(book)) {
          Text(this.getBookSourceText(book))
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.sourceTagTextColor())
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 3, bottom: 3 })
            .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode))
            .borderRadius(ThemeRuntime.mediumRadius())
            .position({ x: '100%', y: 0 })
            .translate({ x: -58, y: 7 })
            .constraintSize({ maxWidth: 52 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .aspectRatio(0.735)
      .border({
        width: this.isBookSelected(book.bookUrl) ? 2 : ThemeRuntime.glassBorderWidth(),
        color: this.isBookSelected(book.bookUrl) ? this.accentColor() : this.glassBorderColor()
      })
      .borderRadius(8)
      .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(),
        offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })

      Row({ space: AppSpacing.XS }) {
        Text(this.shelfTileBookDisplayName(book))
          .fontSize(AppFontSize.CAPTION)
          .lineHeight(18)
          .height(36)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_WORD)
          .layoutWeight(1)
      }
      .width('100%')
      .height(36)
      .alignItems(VerticalAlign.Center)

      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(13)
          .fontColor([this.subTextColor()])
        Text(this.bookshelfShowProgressBar ? this.getReadProgressPercentText(book) : this.getShelfProgressText(book))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(18)
      .alignItems(VerticalAlign.Bottom)

      if (this.bookshelfShowProgressBar) {
        Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(3)
          .color(this.accentColor())
          .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false })
          .onAction((event: GestureEvent) => {
            if (!this.isBookMultiSelect) {
              this.showBookActions(book, event);
            }
          }),
        TapGesture()
          .onAction((event: GestureEvent) => {
            if (this.consumeShelfSwipeClick()) {
              return;
            }
            if (this.isBookMultiSelect) {
              this.toggleSelectedBook(book.bookUrl);
              return;
            }
            const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
            this.openShelfBook(book, finger ? finger.globalX : this.contextViewportWidth / 2,
              finger ? finger.globalY : this.contextViewportHeight / 2);
          })
      ),
      GestureMask.IgnoreInternal
    )
  }

  /** 云端占位书：下载导入后照常打开，书架位置、分组与阅读进度都保留。 */
  async openCloudPlaceholder(book: Book, touchX: number, touchY: number): Promise<void> {
    if (this.downloadingCloudBookUrl) return;
    this.downloadingCloudBookUrl = book.bookUrl;
    try {
      const ready = await CloudAutoSync.ensureBookDownloaded(getContext(this), book);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      await this.loadBooks();
      this.downloadingCloudBookUrl = '';
      this.openShelfBook(ready, touchX, touchY);
    } catch (e) {
      const message = e instanceof Error ? e.message : '';
      HdsFeedback.showToast(message || '云端书籍下载失败，请稍后重试');
    } finally {
      this.downloadingCloudBookUrl = '';
    }
  }

  openShelfBook(book: Book, touchX: number, touchY: number): void {
    if (this.openingBook) {
      return;
    }
    if (CloudAutoSync.isPlaceholder(book)) {
      this.openCloudPlaceholder(book, touchX, touchY);
      return;
    }
    this.acknowledgeShelfBookUpdate(book);
    ReaderOpenTrace.begin(book.bookUrl);
    if (!this.bookshelfBookOpenAnimation) {
      AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', true);
      ReaderOpenTrace.mark(book.bookUrl, 'direct-open');
      ReaderOpenTrace.mark(book.bookUrl, 'route-requested');
      router.pushUrl({
        url: 'pages/ReadBook',
        params: {
          bookUrl: book.bookUrl,
          shelfBookOpening: 'false'
        }
      }).catch((error: Error) => {
        AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
        console.error('打开阅读页失败:', error);
        ReaderOpenTrace.cancel(book.bookUrl, 'route-failed');
      });
      return;
    }
    const centerX = this.contextViewportWidth / 2;
    const centerY = this.contextViewportHeight / 2;
    this.openingBookOriginX = touchX - centerX;
    this.openingBookOriginY = touchY - centerY;
    this.openingBookScale = 0.28;
    this.openingBookTranslateX = this.openingBookOriginX;
    this.openingBookTranslateY = this.openingBookOriginY;
    this.openingBookOpacity = 0;
    this.openingBookBackdropOpacity = 0;
    this.openingBookCoverAngle = 0;
    this.openingBookWaiting = false;
    this.openingBook = book;

    this.openingBookGrowTimer = setTimeout(() => {
      this.openingBookGrowTimer = -1;
      animateTo({ duration: 260, curve: Curve.Friction }, () => {
        this.openingBookScale = 1;
        this.openingBookTranslateX = 0;
        this.openingBookTranslateY = 0;
        this.openingBookOpacity = 1;
        this.openingBookBackdropOpacity = 0.82;
      });
    }, 16);

    this.openingBookTurnTimer = setTimeout(() => {
      this.openingBookTurnTimer = -1;
      animateTo({ duration: 330, curve: Curve.EaseInOut }, () => {
        this.openingBookScale = 1.08;
        this.openingBookCoverAngle = -118;
        this.openingBookBackdropOpacity = 1;
      });
    }, 210);

    this.openingBookRouteTimer = setTimeout(() => {
      this.openingBookWaiting = true;
      AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', true);
      ReaderOpenTrace.mark(book.bookUrl, 'shelf-animation-finished');
      // Commit a neutral surface before route creation can occupy the UI thread. The single loading prompt
      // belongs to the reader page, so navigation cannot split it into two separate visual stages.
      this.openingBookRouteTimer = setTimeout(() => {
        this.openingBookRouteTimer = -1;
        ReaderOpenTrace.mark(book.bookUrl, 'route-requested');
        router.pushUrl({
          url: 'pages/ReadBook',
          params: {
            bookUrl: book.bookUrl,
            shelfBookOpening: 'true'
          }
        }).catch((error: Error) => {
          AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
          console.error('打开阅读页失败:', error);
          ReaderOpenTrace.cancel(book.bookUrl, 'route-failed');
          this.cancelShelfBookOpening();
        });
      }, 96);
    }, 560);
  }

  hasShelfBookUpdate(book: Book): boolean {
    return book.getVariable(SHELF_UPDATE_BADGE_VARIABLE) === '1';
  }

  acknowledgeShelfBookUpdate(book: Book): void {
    if (!book.bookUrl) {
      return;
    }
    // Remember the click while a background refresh may still be in flight, so that refresh cannot
    // write the badge back after the user has already entered this book.
    this.shelfUpdateAcknowledgedAt.set(book.bookUrl, Date.now());
    if (!this.hasShelfBookUpdate(book)) {
      return;
    }
    book.putVariable(SHELF_UPDATE_BADGE_VARIABLE, '');
    this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
    this.applyShelfScope();
    this.reloadShelfDataSources(true);
    this.persistShelfBookUpdateAcknowledgement(book.bookUrl).catch((e: Error) => {
      console.error('清除书架更新标记失败:', book.name, e);
    });
  }

  async persistShelfBookUpdateAcknowledgement(bookUrl: string): Promise<void> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    const current = await db.getBook(bookUrl);
    if (!current || !this.hasShelfBookUpdate(current)) {
      return;
    }
    current.putVariable(SHELF_UPDATE_BADGE_VARIABLE, '');
    await db.updateBook(current, false, 'shelf_update_badge_acknowledged');
  }

  closeShelfBook(bookUrl: string): void {
    const targetBook = this.openingBook && this.openingBook.bookUrl === bookUrl ? this.openingBook :
      this.allBooks.find((book: Book) => book.bookUrl === bookUrl);
    if (!targetBook) {
      this.cancelShelfBookOpening();
      return;
    }
    this.clearShelfBookAnimationTimers();
    this.openingBook = targetBook;
    this.openingBookWaiting = false;
    this.openingBookScale = 1.08;
    this.openingBookTranslateX = 0;
    this.openingBookTranslateY = 0;
    this.openingBookOpacity = 1;
    this.openingBookBackdropOpacity = 1;
    this.openingBookCoverAngle = -118;

    // The bookshelf route is retained under the reader. Refresh its database snapshot while the opaque close-book
    // animation is covering the grid, then force retained LazyForEach sources to adopt that snapshot. No loading
    // placeholder or empty list is shown, so the user sees one continuous return animation instead of a shelf flash.
    if (this.loadTimer >= 0) {
      clearTimeout(this.loadTimer);
      this.loadTimer = -1;
    }
    this.loadBooks(true).catch((error: Error) => {
      console.warn('返回书架时无感刷新失败:', error);
    });

    this.openingBookTurnTimer = setTimeout(() => {
      this.openingBookTurnTimer = -1;
      animateTo({ duration: 280, curve: Curve.EaseInOut }, () => {
        this.openingBookScale = 1;
        this.openingBookCoverAngle = 0;
        this.openingBookBackdropOpacity = 0.82;
      });
    }, 80);

    this.openingBookGrowTimer = setTimeout(() => {
      this.openingBookGrowTimer = -1;
      animateTo({ duration: 250, curve: Curve.Friction }, () => {
        this.openingBookScale = 0.28;
        this.openingBookTranslateX = this.openingBookOriginX;
        this.openingBookTranslateY = this.openingBookOriginY;
        this.openingBookOpacity = 0;
        this.openingBookBackdropOpacity = 0;
      });
    }, 320);

    this.openingBookRouteTimer = setTimeout(() => {
      this.openingBookRouteTimer = -1;
      // The reader serializes its final progress checkpoint before routing back, but the retained bookshelf can
      // still be rendering the pre-reader Book objects during the close animation. Reload once after the overlay
      // is fully dismissed so the visible cards use the committed database snapshot without requiring a tab switch.
      this.loadBooks(true).catch((error: Error) => {
        console.warn('关闭阅读页后刷新书架进度失败:', error);
      });
      this.cancelShelfBookOpening();
    }, 600);
  }

  clearShelfBookAnimationTimers(): void {
    if (this.openingBookGrowTimer >= 0) {
      clearTimeout(this.openingBookGrowTimer);
      this.openingBookGrowTimer = -1;
    }
    if (this.openingBookTurnTimer >= 0) {
      clearTimeout(this.openingBookTurnTimer);
      this.openingBookTurnTimer = -1;
    }
    if (this.openingBookRouteTimer >= 0) {
      clearTimeout(this.openingBookRouteTimer);
      this.openingBookRouteTimer = -1;
    }
  }

  cancelShelfBookOpening(): void {
    this.clearShelfBookAnimationTimers();
    this.openingBook = null;
    this.openingBookScale = 0.28;
    this.openingBookTranslateX = 0;
    this.openingBookTranslateY = 0;
    this.openingBookOpacity = 0;
    this.openingBookBackdropOpacity = 0;
    this.openingBookCoverAngle = 0;
    this.openingBookWaiting = false;
    this.openingBookOriginX = 0;
    this.openingBookOriginY = 0;
  }

  openingBookWidth(): number {
    return Math.min(228, Math.max(184, this.contextViewportWidth * 0.58));
  }

  openingBookHeight(): number {
    return this.openingBookWidth() / 0.735;
  }

  @Builder
  shelfBookOpeningOverlay(book: Book) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.pageColor())
        .opacity(this.openingBookBackdropOpacity)

      if (this.openingBookWaiting) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.accentColor())
          Text('正在打开书籍…')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.secondaryTextColor())
            .margin({ top: 10 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Column() {
            Text(book.name)
              .fontSize(AppFontSize.TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(2)
              .textAlign(TextAlign.Center)
              .margin({ left: 22, right: 22, top: 34, bottom: 28 })

            ForEach([0, 1, 2, 3, 4, 5, 6], (_line: number) => {
              Divider()
                .width('72%')
                .color(this.appDarkMode ? '#24FFFFFF' : '#18000000')
                .margin({ bottom: 17 })
            })
          }
          .width(this.openingBookWidth())
          .height(this.openingBookHeight())
          .backgroundColor(this.inputColor())
          .borderRadius(ThemeRuntime.mediumRadius())
          .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
          .shadow({ radius: 24, color: this.appDarkMode ? '#90000000' : '#38000000', offsetX: 8, offsetY: 10 })

          Stack({ alignContent: Alignment.Center }) {
            this.coverView(book, '100%', '100%', ImageFit.Cover)

            Column()
              .width(8)
              .height('100%')
              .linearGradient({
                angle: 0,
                colors: [[this.appDarkMode ? '#66000000' : '#44000000', 0], ['#00000000', 1]]
              })
              .position({ x: 0, y: 0 })
          }
          .width(this.openingBookWidth())
          .height(this.openingBookHeight())
          .borderRadius(8)
          .rotate({
            x: 0,
            y: 1,
            z: 0,
            angle: this.openingBookCoverAngle,
            centerX: 0,
            centerY: '50%',
            perspective: 900
          })
          .shadow({ radius: 20, color: '#55000000', offsetX: 5, offsetY: 8 })
        }
        .width(this.openingBookWidth())
        .height(this.openingBookHeight())
        .clip(false)
        .scale({ x: this.openingBookScale, y: this.openingBookScale })
        .translate({ x: this.openingBookTranslateX, y: this.openingBookTranslateY })
        .opacity(this.openingBookOpacity)
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(100)
    .hitTestBehavior(HitTestMode.Block)
  }

  @Builder
  compactBookContent(book: Book) {
    Column({ space: AppSpacing.MD }) {
      Row() {
        // 封面高度 = 信息块高度，顶部对齐书名行、底部对齐进度条底部。
        this.coverView(book, this.shelfCoverWidth(this.shelfCompactInfoHeight()),
          this.shelfCompactInfoHeight(), ImageFit.Cover)

        Column({ space: this.shelfRowSpace() }) {
          Row({ space: AppSpacing.SM }) {
            this.bookTypeNameBadge(book, true)
            Text(this.shelfTileBookDisplayName(book))
              .fontSize(AppFontSize.BODY_LARGE)
              .lineHeight(this.shelfTitleLineHeight())
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            this.bookPinnedIndicator(book)

            if (this.shouldShowBookSource(book)) {
              Text(this.getBookSourceText(book))
                .fontSize(AppFontSize.CAPTION)
                .lineHeight(14)
                .fontColor(this.sourceTagTextColor())
                .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
                .backgroundColor(this.sourceTagBackgroundColor())
                .borderRadius(ThemeRuntime.smallRadius())
                .margin({ left: AppSpacing.MD })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 104 })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.getShelfAuthorText(book))
            .fontSize(AppFontSize.BODY)
            .lineHeight(this.shelfTextLineHeight())
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.getShelfUpdateLineText(book)) {
            Text(this.getShelfUpdateLineText(book))
              .fontSize(AppFontSize.BODY)
              .lineHeight(this.shelfTextLineHeight())
              .fontColor(this.secondaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          // 恒定的 Blank：某本书没有更新行时由它吸收多余空间，尾部仍被顶到底部。
          Blank()

          if (this.bookshelfShowProgressBar) {
            this.readProgressPanel(book)
          } else {
            Row() {
              Text(this.getShelfProgressText(book))
                .fontSize(AppFontSize.CAPTION)
                .lineHeight(this.shelfSmallTextLineHeight())
                .fontColor(this.subTextColor())
            }
          }
        }
        .layoutWeight(1)
        .height(this.shelfCompactInfoHeight())
        .margin({ left: AppSpacing.LG })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.bookExtraContent(book)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.LG)
  }

  @Builder
  looseBookContent(book: Book) {
    Column({ space: AppSpacing.MD }) {
      Row() {
        // 封面高度 = 信息块高度，顶部对齐书名行、底部对齐「xx章未读」那一行。
        this.coverView(book, this.shelfCoverWidth(this.shelfLooseInfoHeight()),
          this.shelfLooseInfoHeight(), ImageFit.Cover)

        Column({ space: this.shelfRowSpace() }) {
          Row({ space: AppSpacing.SM }) {
            this.bookTypeNameBadge(book, true)
            Text(this.shelfTileBookDisplayName(book))
              .fontSize(AppFontSize.BODY_LARGE)
              .lineHeight(this.shelfTitleLineHeight())
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            this.bookPinnedIndicator(book)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.getShelfAuthorText(book))
            .fontSize(AppFontSize.BODY)
            .lineHeight(this.shelfTextLineHeight())
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.getShelfUpdateLineText(book)) {
            Text(this.getShelfUpdateLineText(book))
              .fontSize(AppFontSize.BODY)
              .lineHeight(this.shelfTextLineHeight())
              .fontColor(this.secondaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          // 恒定的 Blank：某本书没有更新行时由它吸收多余空间，尾部仍被顶到底部。
          Blank()

          Row() {
            if (this.shouldShowBookSource(book)) {
              Text(this.getBookSourceText(book))
                .fontSize(AppFontSize.CAPTION)
                .lineHeight(14)
                .fontColor(this.sourceTagTextColor())
                .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
                .backgroundColor(this.sourceTagBackgroundColor())
                .borderRadius(ThemeRuntime.smallRadius())
                .margin({ right: AppSpacing.MD })
            }

            // 与作者名保持一致的格式（字号 14 + 次级文字色）。
            Text(this.getShelfProgressText(book))
              .fontSize(AppFontSize.BODY)
              .lineHeight(this.shelfTextLineHeight())
              .fontColor(this.secondaryTextColor())
          }
        }
        .layoutWeight(1)
        .height(this.shelfLooseInfoHeight())
        .margin({ left: AppSpacing.LG })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.bookExtraContent(book)

      if (this.bookshelfShowProgressBar) {
        this.looseReadProgressPanel(book)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.LG)
  }

  @Builder
  bookExtraContent(book: Book) {
    if (this.bookshelfShowIntro && this.getBookIntroText(book)) {
      Text(this.getBookIntroText(book))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .lineHeight(18)
        .maxLines(LocalBookService.isLocalBook(book) ? 2 : (this.bookshelfShowFullIntro ? 999 : 2))
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxHeight: LocalBookService.isLocalBook(book) ? 36 : 10000 })
        .clip(true)
        .width('100%')
    }

    if (this.bookshelfShowTags && this.getDisplayTags(book).length > 0) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.getDisplayTags(book), (tag: string, index: number) => {
          this.tagChip(tag, index, 11)
        })
      }
      .width('100%')
    }
  }

  shouldShowBookSource(book: Book): boolean {
    return this.bookshelfShowSource && book.origin !== 'local' && this.getBookSourceText(book).length > 0;
  }

  getBookSourceText(book: Book): string {
    return (book.originName || book.origin || '').trim();
  }

  getBookIntroText(book: Book): string {
    const rawIntro = LocalBookService.isLocalBook(book) ? book.intro : book.getDisplayIntro();
    const intro = (rawIntro || '')
      .replace(/\s+/g, ' ')
      .trim();
    if (LocalBookService.isLocalBook(book) && intro.length > 52) {
      return `${intro.substring(0, 52).trim()}…`;
    }
    return intro;
  }

  @Builder
  coverView(book: Book, width: Length, height: Length, imageFit: ImageFit) {
    Stack() {
      if (this.shouldUseThemeBookCover()) {
        if (this.activeThemeBookCovers(book).length === 1) {
          Image(this.activeThemeBookCovers(book)[0])
            .width(width)
            .height(height)
            .objectFit(ImageFit.Fill)
        } else {
          Swiper() {
            ForEach(this.activeThemeBookCovers(book), (cover: ResourceStr, index: number) => {
              Image(cover)
                .width(width)
                .height(height)
                .objectFit(ImageFit.Fill)
            }, (_cover: ResourceStr, index: number) => `${book.bookUrl}_theme_${index}`)
          }
          .width(width)
          .height(height)
          .autoPlay(true)
          .interval(this.themeBookCoverInterval(book))
          .indicator(false)
          .loop(true)
        }
        Image(this.activeThemeShelfFrame())
          .width(width)
          .height(height)
          .objectFit(ImageFit.Fill)
      } else if (this.getShelfCoverList(book).length === 0) {
        Column() {
          Text(book.name ? book.name.substring(0, 1) : '书')
            .fontSize(28)
            .fontColor('#FFFFFF')
        }
        .width(width)
        .height(height)
        .backgroundColor(this.getBookColor(book.name))
        .justifyContent(FlexAlign.Center)
      } else if (this.getShelfCoverList(book).length === 1) {
        Image(this.imageCover(this.getShelfCover(book)))
          .width(width)
          .height(height)
          .objectFit(imageFit)
      } else {
        Swiper() {
          ForEach(this.getShelfCoverList(book), (cover: string) => {
            Image(this.imageCover(cover))
              .width(width)
              .height(height)
              .objectFit(imageFit)
          }, (cover: string) => cover)
        }
        .width(width)
        .height(height)
        .autoPlay(true)
        .interval(3500)
        .indicator(false)
        .loop(true)
      }
      if (CloudAutoSync.isPlaceholder(book)) {
        // 仅在云端、尚未下载：置灰并标出云端，点击即下载打开。
        Stack({ alignContent: Alignment.Center }) {
          if (this.downloadingCloudBookUrl === book.bookUrl) {
            LoadingProgress()
              .width(24)
              .height(24)
              .color('#FFFFFF')
          } else {
            SymbolGlyph($r('sys.symbol.download'))
              .fontSize(16)
              .fontColor(['#FFFFFF'])
          }
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor('#73000000')
        .accessibilityText(`${book.name}在云端，点击下载`)
      }
      if (this.hasShelfBookUpdate(book)) {
        Text('新')
          .fontSize(AppFontSize.MICRO)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width(21)
          .height(21)
          .borderRadius(11)
          .backgroundColor('#F04B45')
          .border({ width: 2, color: '#FFFFFF' })
          .position({ x: '100%', y: '100%' })
          .translate({ x: -24, y: -24 })
          .shadow({ radius: 5, color: '#55000000', offsetX: 0, offsetY: 2 })
          .accessibilityText(`${book.name}有更新`)
      }
    }
    .width(width)
    .height(height)
    .borderRadius(8)
    .clip(true)
    .backgroundColor(this.inputColor())
    .grayscale(CloudAutoSync.isPlaceholder(book) ? 1 : 0)
    .opacity(CloudAutoSync.isPlaceholder(book) ? 0.6 : 1)
    .onAppear(() => this.ensureShelfBookCoverCache(book))
  }

  @Builder
  bookPinnedIndicator(book: Book, compact: boolean = false) {
    if (book.isPinned) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.pin'))
          .fontSize(compact ? 12 : 14)
          .fontColor([this.accentColor()])
      }
      .width(compact ? 18 : 22)
      .height(compact ? 18 : 22)
      .borderRadius(compact ? 9 : 11)
      .backgroundColor(this.inputColor())
      .accessibilityText(`${book.name}已置顶`)
    }
  }

  @Builder
  bookPinnedCoverIndicator(book: Book) {
    if (book.isPinned) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.pin'))
          .fontSize(10)
          .fontColor([this.accentColor()])
      }
      .width(16)
      .height(16)
      .borderRadius(8)
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, this.inputColor(), 'button'))
      .margin({ left: 5, top: 5 })
      .shadow({ radius: 3, color: '#55000000', offsetX: 0, offsetY: 1 })
      .accessibilityText(`${book.name}已置顶`)
    }
  }

  @Builder
  bookTypeCoverBadge(book: Book) {
    if (this.bookshelfShowTypeBadge) {
      Text(this.bookTypeBadgeText(book))
      .fontSize(9)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .textAlign(TextAlign.Center)
      .width(18)
      .height(16)
      .borderRadius(ThemeRuntime.smallRadius())
      .backgroundColor(this.bookTypeBadgeColor(book))
      .opacity(0.92)
      .border({ width: 1, color: '#66FFFFFF' })
      .position({ x: 5, y: '100%' })
      .translate({ x: 0, y: -21 })
      .shadow({ radius: 3, color: '#55000000', offsetX: 0, offsetY: 1 })
        .accessibilityText(`${book.name}${this.bookTypeBadgeText(book)}类型`)
    }
  }

  @Builder
  bookTypeNameBadge(book: Book, compact: boolean = false) {
    if (this.bookshelfShowTypeBadge) {
      Text(this.bookTypeBadgeText(book))
        .fontSize(compact ? 8 : 9)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width(compact ? 16 : 18)
        .height(compact ? 14 : 16)
        .borderRadius(compact ? 4 : 5)
        .backgroundColor(this.bookTypeBadgeColor(book))
    }
  }

  bookTypeBadgeText(book: Book): string {
    if (BookTypeSupport.isVideo(book)) return '视';
    if (BookTypeSupport.isAudio(book)) return '声';
    if (BookTypeSupport.isImage(book)) return '漫';
    return '书';
  }

  bookTypeBadgeColor(book: Book): string {
    if (BookTypeSupport.isVideo(book)) return '#D64560';
    if (BookTypeSupport.isAudio(book)) return '#D9822B';
    if (BookTypeSupport.isImage(book)) return '#8B5CF6';
    return '#3978C5';
  }

  activeThemeBookCovers(book: Book): ResourceStr[] {
    return ThemeBookCoverSettings.covers(book, this.appDarkMode);
  }

  shouldUseThemeBookCover(): boolean {
    return ThemeBookCoverSettings.enabled(this.appDarkMode, this.themeBookCoverEnabled);
  }

  themeBookCoverInterval(book: Book): number {
    return ThemeBookCoverSettings.interval(book);
  }

  activeThemeShelfFrame(): ResourceStr {
    return ThemeBookCoverSettings.frame(this.appDarkMode);
  }

  activeThemeShelfFolder(): ResourceStr {
    return ThemeAssetRegistry.themeShelfFolder(ThemeRuntime.bookTokens(this.appDarkMode).shelfFolderAssetId);
  }

  /** Image 能直接加载的封面地址；加密的书源封面在解密完成前为空。 */
  imageCover(raw: string): string {
    return this.sourceCoverRevision >= 0 ? BookCoverCache.displayCover(getContext(this), raw) : raw;
  }

  getShelfCover(book: Book): string {
    const covers = this.getShelfCoverList(book);
    return covers.length > 0 ? BookDisplayHelper.pickCover(covers) : '';
  }

  getShelfCoverList(book: Book): string[] {
    const covers = CoverGallerySettings.getDisplayCoverList(
      book,
      this.appDarkMode,
      this.bookshelfCoverAlbums,
      this.bookshelfLightCoverAlbumId,
      this.bookshelfDarkCoverAlbumId,
      this.bookshelfCoverApplyScope,
      this.bookshelfCoverTargetBooks,
      this.bookshelfIgnoreSourceCover,
      this.bookshelfCoverMode
    );
    const displayCovers: string[] = [];
    for (let i = 0; i < covers.length; i++) {
      const raw = covers[i];
      const key = this.shelfCoverKey(book, i);
      const cached = this.shelfCoverRawUrls.get(key) === raw ? (this.shelfCoverMap.get(key) || '') : '';
      displayCovers.push(cached || raw);
    }
    return displayCovers;
  }

  shelfCoverKey(book: Book, index: number): string {
    return `${book.bookUrl}#${index}`;
  }

  @Builder
  tagChip(tag: string, index: number, fontSize: number) {
    Text(tag)
      .fontSize(fontSize)
      .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 3, bottom: 3 })
      .attributeModifier(BookDisplayHelper.getTagModifier(index, this.appDarkMode))
      .margin({ left: AppSpacing.XS, bottom: AppSpacing.SM })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  actionItem(label: string, color: string, action: () => void) {
    Button(label)
      .width('100%')
      .height(44)
      .margin({ top: AppSpacing.SM })
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      .fontColor(color)
      .onClick(action)
  }


  onBookshelfSystemDialogFlagChanged(): void {
    if (!this.showCacheDialog) this.cacheDialogSession.close(this.getUIContext());
    if (!this.showChapterCacheDialog) this.chapterCacheDialogSession.close(this.getUIContext());
  }

  @Builder
  cacheDialogContent() {
    Column() {
      Text(`缓存《${this.cacheTargetBook?.name || '当前书籍'}》`)
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.MD })

      if (this.cacheStatus) {
        Text(this.cacheStatus)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: AppSpacing.MD })
      }

      this.actionItem(this.isCacheTargetBookCaching() ? '正在缓存...' : '缓存全文', this.primaryTextColor(), () => {
        this.cacheWholeBook();
      })
      this.actionItem('缓存指定章节', this.primaryTextColor(), () => {
        this.showCacheDialog = false;
        this.showChapterCacheDialog = true;
        if (this.cacheTargetBook) {
          this.loadCacheChapters(this.cacheTargetBook);
        }
        this.chapterCacheDialogSession.open(this.getUIContext(), (): void => {
          this.chapterCacheDialogContent();
        }, {
          autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
          warnTag: '显示章节缓存弹窗失败:'
        });
      })
      this.actionItem('清除已缓存章节', ThemeRuntime.dangerColor(this.appDarkMode), () => {
        this.clearCachedChapters();
      })

      Button('取消')
        .width('100%')
        .height(44)
        .margin({ top: 10 })
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .fontColor(this.primaryTextColor())
        .onClick(() => {
          this.closeCacheDialog();
        })
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
  }

  @Builder
  chapterCacheDialogContent() {
    Column() {
      Row() {
        Text('选择章节缓存')
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.primaryTextColor(),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          materialScale: 0.83,
          compactLayout: true,
          accessibilityLabel: '关闭',
          onBack: () => this.closeCacheDialog()
        })
      }
      .width('100%')
      .height(46)
      .alignItems(VerticalAlign.Center)

      if (this.cacheStatus) {
        Text(this.cacheStatus)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .margin({ bottom: AppSpacing.MD })
      }

      Row({ space: AppSpacing.MD }) {
        TextInput({ placeholder: '章节范围，如 1-10、1,3,5-8', text: this.cacheRangeDraft })
          .type(InputType.Normal)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .layoutWeight(1)
          .height(42)
          .padding({ left: 10, right: 10 })
          .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .enabled(!this.isCacheTocLoading)
          .onChange((value: string) => {
            this.cacheRangeDraft = value;
          })
        Button('缓存')
          .width(96)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(this.buttonColor())
          .enabled(this.cacheChapters.length > 0)
          .onClick(() => this.cacheChapterRange())
      }
      .width('100%')
      .margin({ bottom: AppSpacing.MD })

      List({ space: AppSpacing.XXS }) {
        ForEach(this.cacheChapters, (chapter: BookChapter, index: number) => {
          ListItem() {
            Row({ space: AppSpacing.MD }) {
              Text(chapter.title)
                .fontSize(AppFontSize.BODY_LARGE)
                .fontColor(chapter.cacheDate > 0 ? this.cachedChapterTextColor() : this.primaryTextColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (chapter.cacheDate > 0) {
                Text('已缓存')
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(ThemeRuntime.successColor(this.appDarkMode))
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
                  .backgroundColor(ThemeRuntime.successSurfaceColor(this.appDarkMode))
                  .borderRadius(ThemeRuntime.smallRadius())
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.XXS, right: AppSpacing.XXS, top: AppSpacing.LG, bottom: AppSpacing.LG })
            .onClick(() => {
              this.cacheSingleChapter(index);
            })
          }
        })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height(380)
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
  }

  @Builder
  contextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    PopupMenuAction(icon, label, color, action)
  }

  multiSelectBottomPadding(): number {
    return Math.max(this.navBarHeight, 8) + 6;
  }

  addEditingTag(): void {
    const tag = this.tagInput.trim();
    if (!tag || this.editingTags.includes(tag)) {
      this.tagInput = '';
      return;
    }
    this.editingTags = [...this.editingTags, tag];
    this.tagInput = '';
  }

  removeEditingTag(tag: string): void {
    this.editingTags = this.editingTags.filter(item => item !== tag);
  }

  async saveCustomTags(): Promise<void> {
    if (!this.pendingActionBook) return;
    this.addEditingTag();
    const book = this.pendingActionBook;
    const sourceTags = BookDisplayHelper.splitTags(book.kind, '');
    const customTags = this.editingTags.filter(tag => !sourceTags.includes(tag));
    const hiddenTags = sourceTags
      .filter(tag => !this.editingTags.includes(tag))
      .map(tag => `!${tag}`);
    book.customTag = BookDisplayHelper.joinTags([...customTags, ...hiddenTags]);
    await this.updateShelfBook(book);
    this.closeTagDialog();
    HdsFeedback.showToast('标签已保存');
  }

  closeEditBookInfoDialog(): void {
    this.showEditBookInfoDialog = false;
    this.editBookInfoDialogSession.close(this.getUIContext());
    this.editingBookName = '';
    this.editingBookAuthor = '';
    this.pendingActionBook = null;
  }

  async saveLocalBookInfo(): Promise<void> {
    const target = this.pendingActionBook;
    const name = this.editingBookName.trim();
    const author = this.editingBookAuthor.trim();
    if (!target || !LocalBookService.isLocalBook(target)) {
      this.closeEditBookInfoDialog();
      return;
    }
    if (!name) {
      HdsFeedback.showToast('书名不能为空');
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const book = await db.getBook(target.bookUrl);
      if (!book || !LocalBookService.isLocalBook(book)) {
        HdsFeedback.showToast('书籍已不在书架中');
        this.closeEditBookInfoDialog();
        return;
      }
      book.name = name;
      book.author = author;
      book.putVariable('localMetadataCustomized', '1');
      book.putVariable('localCustomName', name);
      book.putVariable('localCustomAuthor', author);
      await db.updateBook(book);
      await db.updateBookBookmarkMetadata(book.bookUrl, name, author);
      this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
      this.applyShelfScope();
      this.closeEditBookInfoDialog();
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('书籍信息已保存');
    } catch (e) {
      console.error('保存本地书籍信息失败:', e);
      HdsFeedback.showToast('保存失败');
    }
  }

  private showCacheFeedback(message: string): void {
    HdsFeedback.showToast(message);
  }

  async openCacheDialog(book: Book): Promise<void> {
    this.cacheTargetBook = book;
    this.cacheChapters = [];
    this.cacheStatus = this.isBookCaching(book) ? this.currentFullTextCacheDialogStatus(book) : '正在加载目录...';
    this.cacheRangeDraft = '';
    this.cacheDialogOpenedAt = Date.now();
    this.showCacheDialog = true;
    this.cacheDialogSession.open(this.getUIContext(), (): void => {
      this.cacheDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示缓存弹窗失败:'
    });
    // The catalog is loaded even while a background task runs so the panel can show which chapters
    // are already cached; the task uses its own engine, so this cannot disturb it.
    this.loadCacheChapters(book);
  }

  applyShelfScope(): void {
    this.refreshShelfTypeTabs();
    this.books = this.sortBooks(this.booksForShelfScope(this.shelfScope));
    if (this.books.length === 0) {
      this.showShelfSortMenu = false;
    }
  }

  /** 按普通书架（当前分组）里实际有的类型重建分类栏；当前类型没书了就回到“全部”。 */
  refreshShelfTypeTabs(): void {
    const present: boolean[] = BookshelfPage.TYPE_TAB_IDS.map((): boolean => false);
    for (const book of this.allBooks) {
      if (!book.isPrivate && this.matchesShelfGroup(book)) {
        present[BookshelfPage.TYPE_TAB_IDS.indexOf(this.shelfBookType(book))] = true;
      }
    }
    const ids: string[] = BookshelfPage.TYPE_TAB_IDS.filter((_id: string, index: number) => index === 0 || present[index]);
    if (ids.join(',') !== this.shelfTypeTabIds.join(',')) {
      this.shelfTypeTabIds = ids;
    }
    if (ids.indexOf(this.shelfTypeTab) < 0) {
      this.shelfTypeTab = 'all';
    }
  }

  /** 标题旁的书本数；隐私书架不在分类栏里，在这里标出当前位置。 */
  shelfHeaderCountText(): string {
    const count = this.books.length > 0 ? `${this.books.length}本` : '分组';
    return this.shelfScope === 'private' ? `隐私 · ${count}` : count;
  }

  shelfScopeEmptyHint(): string {
    if (this.shelfAppliedSearchKeyword) {
      const hint = `没有找到与“${this.shelfSearchKeyword.trim()}”相关的书籍`;
      return this.shelfFilterKeyList().length > 0 ? `${hint}，也可以清除筛选条件再试` : hint;
    }
    if (this.shelfScope === 'private') {
      return '长按书籍并选择“标记为隐私”，即可移入隐私书架';
    }
    if (this.shelfFilterKeyList().length > 0) {
      return '没有符合筛选条件的书籍，可在右上角筛选里调整';
    }
    return '搜索书籍或添加本地书籍吧';
  }

  booksForShelfScope(scope: string): Book[] {
    return this.allBooks.filter((book: Book) => this.isInShelfView(book, scope) &&
      this.matchesShelfFilters(book) && this.matchesShelfSearch(book));
  }

  /** 当前书架页（普通/隐私、分组、分类栏类型）里的书，不看筛选和关键词。 */
  isInShelfView(book: Book, scope: string): boolean {
    const privateScope = scope === 'private';
    // 隐私书籍只出现在隐私书架里；隐私书架关闭后它们继续隐藏。
    if (book.isPrivate !== privateScope || !this.matchesShelfGroup(book)) return false;
    return privateScope || this.shelfTypeTab === 'all' || this.shelfBookType(book) === this.shelfTypeTab;
  }

  matchesShelfGroup(book: Book): boolean {
    return this.activeShelfGroupId === 0 ||
      (this.activeShelfGroupId === -1 ? book.group <= 0 : book.group === this.activeShelfGroupId);
  }

  /** 与书籍角标同一优先级：视频 > 有声 > 漫画 > 小说。 */
  shelfBookType(book: Book): string {
    if (BookTypeSupport.isVideo(book)) return 'video';
    if (BookTypeSupport.isAudio(book)) return 'audio';
    if (BookTypeSupport.isImage(book)) return 'image';
    return 'text';
  }

  shelfTypeTabLabel(type: string): string {
    if (type === 'text') return '小说';
    if (type === 'image') return '漫画';
    if (type === 'audio') return '有声书';
    if (type === 'video') return '视频';
    return '全部';
  }

  shelfFilterKeyList(): string[] {
    if (!this.shelfFilterKeys) {
      return [];
    }
    return BookshelfPage.canonicalShelfFilterKeys(this.shelfFilterKeys.split(','));
  }

  /** 固定键按 FILTER_GROUPS 的顺序排在前，标签、书源键按选中先后排在后，去重并丢掉不认识的键。 */
  static canonicalShelfFilterKeys(keys: string[]): string[] {
    const result: string[] = [];
    BookshelfPage.FILTER_GROUPS.forEach((group: string[]) => {
      group.forEach((key: string) => {
        if (keys.indexOf(key) >= 0) result.push(key);
      });
    });
    keys.forEach((key: string) => {
      if (BookshelfPage.isDynamicShelfFilterKey(key) && result.indexOf(key) < 0) result.push(key);
    });
    return result;
  }

  static isDynamicShelfFilterKey(key: string): boolean {
    return (key.startsWith(SHELF_FILTER_TAG_PREFIX) && key.length > SHELF_FILTER_TAG_PREFIX.length) ||
      (key.startsWith(SHELF_FILTER_ORIGIN_PREFIX) && key.length > SHELF_FILTER_ORIGIN_PREFIX.length);
  }

  static shelfFilterKeyFor(prefix: string, value: string): string {
    return `${prefix}${encodeURIComponent(value)}`;
  }

  /** 标签、书源键里的名字；固定键原样返回。 */
  static shelfFilterKeyValue(key: string): string {
    const prefix = key.startsWith(SHELF_FILTER_TAG_PREFIX) ? SHELF_FILTER_TAG_PREFIX :
      (key.startsWith(SHELF_FILTER_ORIGIN_PREFIX) ? SHELF_FILTER_ORIGIN_PREFIX : '');
    if (!prefix) return key;
    try {
      return decodeURIComponent(key.substring(prefix.length));
    } catch (e) {
      return key.substring(prefix.length);
    }
  }

  /** 键所属的组：固定组用下标，标签为 'tag'，书源为 'origin'。 */
  static shelfFilterGroupOf(key: string): string {
    if (key.startsWith(SHELF_FILTER_TAG_PREFIX)) return 'tag';
    if (key.startsWith(SHELF_FILTER_ORIGIN_PREFIX)) return 'origin';
    const index = BookshelfPage.FILTER_GROUPS.findIndex((group: string[]) => group.indexOf(key) >= 0);
    return `${index}`;
  }

  /**
   * 同一组里选的多项取并集，各组之间取交集；某组一项都没选就不按这组限制。
   * 例：网络 + 已完结 = 网络书里已完结的；网络 + 本地 = 不限来源；标签选“玄幻”“都市”= 带其中任一个标签。
   */
  matchesShelfFilters(book: Book): boolean {
    const keys = this.shelfFilterKeyList();
    if (keys.length === 0) {
      return true;
    }
    const groups: string[] = [];
    keys.forEach((key: string) => {
      const group = BookshelfPage.shelfFilterGroupOf(key);
      if (groups.indexOf(group) < 0) groups.push(group);
    });
    const now = Date.now();
    return groups.every((group: string) => keys.some((key: string) =>
      BookshelfPage.shelfFilterGroupOf(key) === group && this.matchesShelfFilterKey(key, book, now)));
  }

  matchesShelfFilterKey(key: string, book: Book, now: number): boolean {
    if (key.startsWith(SHELF_FILTER_TAG_PREFIX)) {
      return BookDisplayHelper.getBookTags(book).indexOf(BookshelfPage.shelfFilterKeyValue(key)) >= 0;
    }
    if (key.startsWith(SHELF_FILTER_ORIGIN_PREFIX)) {
      return this.shelfBookOriginName(book) === BookshelfPage.shelfFilterKeyValue(key);
    }
    if (key === 'network' || key === 'local') return (LocalBookService.isLocalBook(book) ? 'local' : 'network') === key;
    if (key === 'finished' || key === 'ongoing') return (this.isShelfBookFinished(book) ? 'finished' : 'ongoing') === key;
    if (BookshelfPage.FILTER_PROGRESS_KEYS.indexOf(key) >= 0) return this.shelfReadProgressKey(book) === key;
    if (key === 'updated') return this.hasShelfBookUpdate(book);
    const readTime = this.getBookReadTime(book);
    if (key === 'read7d') return readTime > 0 && now - readTime <= 7 * SHELF_DAY_MS;
    if (key === 'read30d') return readTime > 0 && now - readTime <= 30 * SHELF_DAY_MS;
    if (key === 'stale90d') {
      // 从没打开过的书按加入书架的时间算，方便一起清理放了很久没看的书。
      const lastTouched = readTime > 0 ? readTime : this.getBookAddTime(book);
      return lastTouched <= 0 || now - lastTouched > 90 * SHELF_DAY_MS;
    }
    return false;
  }

  /** 书源筛选只看网络书，按书源名归并；本地书的书源名是文件来源，不参与。 */
  shelfBookOriginName(book: Book): string {
    if (LocalBookService.isLocalBook(book)) return '';
    return (book.originName || book.origin || '').trim();
  }

  /** 当前书架页里出现过的标签，按本数从多到少；已选但当前页没有的标签也留着，方便取消。 */
  shelfTagFilterOptions(): ShelfFilterOption[] {
    return this.buildShelfFilterOptions(SHELF_FILTER_TAG_PREFIX, (book: Book) => BookDisplayHelper.getBookTags(book));
  }

  shelfOriginFilterOptions(): ShelfFilterOption[] {
    return this.buildShelfFilterOptions(SHELF_FILTER_ORIGIN_PREFIX, (book: Book) => {
      const name = this.shelfBookOriginName(book);
      return name ? [name] : [];
    });
  }

  buildShelfFilterOptions(prefix: string, valuesOf: (book: Book) => string[]): ShelfFilterOption[] {
    const counts: Map<string, number> = new Map();
    this.allBooks.forEach((book: Book) => {
      if (!this.isInShelfView(book, this.shelfScope)) return;
      const seen: string[] = [];
      valuesOf(book).forEach((raw: string) => {
        const value = raw.trim();
        if (!value || seen.indexOf(value) >= 0) return;
        seen.push(value);
        counts.set(value, (counts.get(value) || 0) + 1);
      });
    });
    this.shelfFilterKeyList().forEach((key: string) => {
      if (key.startsWith(prefix)) {
        const value = BookshelfPage.shelfFilterKeyValue(key);
        if (!counts.has(value)) counts.set(value, 0);
      }
    });
    const options: ShelfFilterOption[] = [];
    counts.forEach((count: number, value: string) => {
      const option = new ShelfFilterOption();
      option.key = BookshelfPage.shelfFilterKeyFor(prefix, value);
      option.label = value;
      option.count = count;
      options.push(option);
    });
    options.sort((a: ShelfFilterOption, b: ShelfFilterOption) => b.count !== a.count ? b.count - a.count :
      a.label.localeCompare(b.label, 'zh-Hans-CN-u-co-pinyin'));
    return options;
  }

  /** 与书籍卡片上的“未读 / N章未读 / 已读完”一致。 */
  shelfReadProgressKey(book: Book): string {
    if (!book.totalChapterNum || book.totalChapterNum <= 0 || !Book.hasStartedReading(book)) {
      return 'unread';
    }
    return book.getUnreadChapterNum() > 0 ? 'reading' : 'readDone';
  }

  /** 转小写、去掉首尾空白、中间连续空白并成一个空格；空格分开的每个词都要命中。 */
  static normalizeShelfSearchText(text: string): string {
    return (text || '').trim().toLowerCase().split(/\s+/).filter((term: string) => term.length > 0).join(' ');
  }

  /** 关键词按书名、作者、书源名和标签（含自定义标签）匹配，不区分大小写，忽略字段里的空白。 */
  matchesShelfSearch(book: Book): boolean {
    const keyword = this.shelfAppliedSearchKeyword;
    if (!keyword) {
      return true;
    }
    const fields: string[] = [book.name || '', book.author || '', book.originName || '',
      ...BookDisplayHelper.getBookTags(book)];
    const text = fields.join('|').toLowerCase().replace(/\s+/g, '');
    return keyword.split(' ').every((term: string) => text.indexOf(term) >= 0);
  }

  onShelfSearchKeywordChanged(): void {
    if (this.shelfSearchApplyTimer >= 0) {
      clearTimeout(this.shelfSearchApplyTimer);
      this.shelfSearchApplyTimer = -1;
    }
    // 清空时立即恢复全部书籍；打字时等输入停顿再筛。
    if (!this.shelfSearchKeyword.trim()) {
      this.applyShelfSearchKeyword();
      return;
    }
    this.shelfSearchApplyTimer = setTimeout(() => {
      this.shelfSearchApplyTimer = -1;
      this.applyShelfSearchKeyword();
    }, SHELF_SEARCH_APPLY_DELAY_MS);
  }

  applyShelfSearchKeyword(): void {
    const next = BookshelfPage.normalizeShelfSearchText(this.shelfSearchKeyword);
    if (next === this.shelfAppliedSearchKeyword) {
      return;
    }
    this.shelfAppliedSearchKeyword = next;
    this.applyShelfScope();
    this.reloadShelfDataSources(true);
    this.refreshShelfCoverCache(this.books);
    this.scrollShelfToTop();
  }

  scrollShelfToTop(): void {
    try {
      if (this.isTileLayout()) {
        this.shelfTileScroller.scrollEdge(Edge.Top);
      } else {
        this.shelfListScroller.scrollEdge(Edge.Top);
      }
    } catch (e) {
      // 筛完没有书时列表不在，滚动控制器没挂上，不需要滚。
    }
  }

  openShelfSearch(): void {
    this.showShelfFilterMenu = false;
    this.shelfSearchActive = true;
    setTimeout(() => {
      if (this.shelfComponentActive && this.shelfSearchActive) {
        focusControl.requestFocus(SHELF_SEARCH_INPUT_KEY);
      }
    }, 120);
  }

  closeShelfSearch(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.shelfSearchKeyword = '';
    this.shelfSearchActive = false;
  }

  /** 来源只筛了本地时，下拉刷新改为重新扫描本地书。 */
  shelfShowsLocalOnly(): boolean {
    const keys = this.shelfFilterKeyList();
    return this.shelfScope !== 'private' && keys.indexOf('local') >= 0 && keys.indexOf('network') < 0;
  }

  /** 书架当前视图的标识，列表项和平铺缓存的键里带上它，切换后不会复用上一视图的条目。 */
  shelfViewKey(): string {
    return `${this.shelfScope}-${this.shelfTypeTab}-${this.shelfFilterKeys}-${this.shelfAppliedSearchKeyword}`;
  }

  /** 当前所在页：分类栏里的类型，或隐私书架 'private'。 */
  shelfPageKey(): string {
    return this.shelfScope === 'private' ? 'private' : this.shelfTypeTab;
  }

  /** 左右滑动的页序：分类栏里显示的类型，隐私书架开启时接在最后。 */
  shelfPageOrder(): string[] {
    const pages: string[] = [...this.shelfTypeTabIds];
    if (this.privateShelfEnabled) {
      pages.push('private');
    }
    return pages;
  }

  setShelfPage(page: string): void {
    const toPrivate = page === 'private' && this.privateShelfEnabled;
    const nextScope = toPrivate ? 'private' : 'all';
    const nextType = toPrivate ? this.shelfTypeTab : (this.shelfTypeTabIds.indexOf(page) >= 0 ? page : 'all');
    this.shelfScopeTabSelection = '';
    if (this.shelfScope === nextScope && this.shelfTypeTab === nextType) return;
    this.shelfScope = nextScope;
    this.shelfTypeTab = nextType;
    this.showShelfSortMenu = false;
    this.showShelfLayoutMenu = false;
    this.showShelfFilterMenu = false;
    this.applyShelfScope();
    this.reloadShelfDataSources(true);
    this.refreshShelfCoverCache(this.books);
  }

  switchShelfScopeBySwipe(offsetX: number): void {
    this.markShelfScopePanGesture(160);
    if (this.isBookMultiSelect || this.isTileGroupPage() || this.shelfScopeSwitchAnimating ||
      Math.abs(offsetX) < 56) {
      return;
    }
    const pages: string[] = this.shelfPageOrder();
    const currentIndex = pages.indexOf(this.shelfPageKey());
    const nextIndex = offsetX < 0 ? currentIndex + 1 : currentIndex - 1;
    if (currentIndex < 0 || nextIndex < 0 || nextIndex >= pages.length) {
      return;
    }
    // 隐私书架不在顶部分类栏里，只能从最后一个分类继续左滑进入；设了密码先输密码。
    if (pages[nextIndex] === 'private' && this.privateShelfHasPassword) {
      this.openPrivateShelfUnlockDialog();
      return;
    }
    this.animateShelfScopeSwitch(pages[nextIndex], offsetX < 0 ? -1 : 1);
  }

  markShelfScopePanGesture(durationMs: number): void {
    this.suppressShelfBookClickUntil = Date.now() + durationMs;
  }

  consumeShelfSwipeClick(): boolean {
    if (Date.now() > this.suppressShelfBookClickUntil) {
      this.suppressShelfBookClickUntil = 0;
      return false;
    }
    this.suppressShelfBookClickUntil = 0;
    return true;
  }

  switchShelfScopeBySelection(page: string): void {
    if (this.shelfScopeSwitchAnimating) {
      return;
    }
    const pages: string[] = this.shelfPageOrder();
    const currentIndex = pages.indexOf(this.shelfPageKey());
    const nextIndex = pages.indexOf(page);
    if (currentIndex < 0 || nextIndex < 0 || currentIndex === nextIndex) {
      return;
    }
    if (page === 'private' && this.privateShelfHasPassword) {
      this.openPrivateShelfUnlockDialog();
      return;
    }
    this.animateShelfScopeSwitch(page, nextIndex > currentIndex ? -1 : 1);
  }

  @Builder
  privateShelfUnlockDialogContent() {
    Column() {
      Text('隐私书架')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 18 })

      TextInput({ placeholder: '请输入隐私书架密码', text: this.privateShelfPasswordInput })
        .type(InputType.Password)
        .width('100%')
        .height(44)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.privateShelfPasswordInput = value;
          this.privateShelfPasswordError = '';
        })
        .onSubmit(() => this.submitPrivateShelfUnlock())

      if (this.privateShelfPasswordError) {
        Text(this.privateShelfPasswordError)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .width('100%')
          .margin({ top: AppSpacing.MD })
      }

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closePrivateShelfUnlockDialog())

        Button('确定')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(this.privateShelfPasswordInput.length > 0)
          .opacity(this.privateShelfPasswordInput.length > 0 ? 1 : 0.45)
          .onClick(() => this.submitPrivateShelfUnlock())
      }
      .width('100%')
      .margin({ top: 22 })
    }
    .padding(AppSpacing.XXL)
  }

  openPrivateShelfUnlockDialog(): void {
    this.privateShelfPasswordInput = '';
    this.privateShelfPasswordError = '';
    this.privateShelfUnlockDialogSession.open(this.getUIContext(), (): void => {
      this.privateShelfUnlockDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示隐私书架密码弹窗失败:'
    });
  }

  closePrivateShelfUnlockDialog(): void {
    this.privateShelfUnlockDialogSession.close(this.getUIContext());
    this.privateShelfPasswordInput = '';
    this.privateShelfPasswordError = '';
  }

  async submitPrivateShelfUnlock(): Promise<void> {
    const input = this.privateShelfPasswordInput;
    if (!input) return;
    let passed = false;
    try {
      passed = await PrivateShelfStore.verifyPassword(getContext(this), input);
    } catch (e) {
      console.warn('校验隐私书架密码失败:', e);
    }
    if (!passed) {
      this.privateShelfPasswordError = '密码不正确';
      return;
    }
    this.closePrivateShelfUnlockDialog();
    if (this.privateShelfEnabled && this.shelfScope !== 'private' && !this.shelfScopeSwitchAnimating) {
      this.animateShelfScopeSwitch('private', -1);
    }
  }

  animateShelfScopeSwitch(scope: string, outgoingDirection: number): void {
    this.clearShelfScopeTransition(false);
    this.shelfScopeSwitchAnimating = true;
    this.shelfScopeTabSelection = scope;
    animateTo({ duration: 130, curve: Curve.EaseIn }, () => {
      this.shelfScopeTransitionX = outgoingDirection * 48;
      this.shelfScopeTransitionScale = 0.985;
      this.shelfScopeTransitionOpacity = 0.12;
    });
    this.shelfScopeSwapTimer = setTimeout(() => {
      this.shelfScopeSwapTimer = -1;
      this.setShelfPage(scope);
      this.shelfScopeTransitionX = outgoingDirection * -48;
      this.shelfScopeTransitionScale = 0.985;
      this.shelfScopeTransitionOpacity = 0.12;
      animateTo({ duration: 230, curve: Curve.Friction }, () => {
        this.shelfScopeTransitionX = 0;
        this.shelfScopeTransitionScale = 1;
        this.shelfScopeTransitionOpacity = 1;
      });
      this.shelfScopeFinishTimer = setTimeout(() => {
        this.shelfScopeFinishTimer = -1;
        this.shelfScopeSwitchAnimating = false;
      }, 250);
    }, 135);
  }

  animateShelfContentUpdate(update: () => void, outgoingX: number): void {
    this.clearShelfScopeTransition(false);
    this.shelfScopeSwitchAnimating = true;
    animateTo({ duration: 110, curve: Curve.EaseIn }, () => {
      this.shelfScopeTransitionX = outgoingX;
      this.shelfScopeTransitionScale = 0.988;
      this.shelfScopeTransitionOpacity = 0.16;
    });
    this.shelfScopeSwapTimer = setTimeout(() => {
      this.shelfScopeSwapTimer = -1;
      update();
      this.shelfScopeTransitionX = -outgoingX;
      this.shelfScopeTransitionScale = 0.988;
      this.shelfScopeTransitionOpacity = 0.16;
      animateTo({ duration: 210, curve: Curve.Friction }, () => {
        this.shelfScopeTransitionX = 0;
        this.shelfScopeTransitionScale = 1;
        this.shelfScopeTransitionOpacity = 1;
      });
      this.shelfScopeFinishTimer = setTimeout(() => {
        this.shelfScopeFinishTimer = -1;
        this.shelfScopeSwitchAnimating = false;
      }, 230);
    }, 115);
  }

  clearShelfScopeTransition(resetVisuals: boolean = true): void {
    if (this.shelfScopeSwapTimer >= 0) {
      clearTimeout(this.shelfScopeSwapTimer);
      this.shelfScopeSwapTimer = -1;
    }
    if (this.shelfScopeFinishTimer >= 0) {
      clearTimeout(this.shelfScopeFinishTimer);
      this.shelfScopeFinishTimer = -1;
    }
    this.shelfScopeSwitchAnimating = false;
    this.shelfScopeTabSelection = '';
    if (resetVisuals) {
      this.shelfScopeTransitionX = 0;
      this.shelfScopeTransitionScale = 1;
      this.shelfScopeTransitionOpacity = 1;
    }
  }

  /**
   * Closing the panel never stops a running cache task. Range and single-chapter caching now run as
   * background tasks, so the panel is only a launcher and can always be dismissed.
   */
  closeCacheDialog(): void {
    this.showCacheDialog = false;
    this.showChapterCacheDialog = false;
    this.cacheTargetBook = null;
    this.cacheChapters = [];
    this.cacheStatus = '';
    this.cacheRangeDraft = '';
    this.isCacheTocLoading = false;
    this.cacheTocLoadToken++;
    this.cacheTocLoadBookUrl = '';
    this.cacheTocLoadPromise = null;
    this.pendingActionBook = null;
  }

  isCacheTargetBookCaching(): boolean {
    return this.isBookCaching(this.cacheTargetBook);
  }

  isBookCaching(book: Book | null): boolean {
    const bookUrl = book?.bookUrl || '';
    return !!bookUrl && this.fullTextCacheTasks.has(bookUrl);
  }

  currentFullTextCacheDialogStatus(book: Book): string {
    const task = this.getShelfFullTextCacheTask(book.bookUrl);
    if (task) {
      return task.status || this.shelfFullTextCacheProgressText(task);
    }
    return '正在加载目录...';
  }

  setFullTextCacheStatus(task: ShelfFullTextCacheTask, status: string): void {
    task.status = status;
    if (this.cacheTargetBook?.bookUrl && this.cacheTargetBook.bookUrl === task.bookUrl) {
      this.cacheStatus = status;
    }
  }

  onFullTextCacheCancelNonceChanged(): void {
    const nonce = this.fullTextCacheCancelNonce || 0;
    if (!this.isCaching || nonce <= 0) {
      return;
    }
    const signal = this.parseFullTextCacheCancelSignal();
    if (signal) {
      const task = this.findShelfFullTextCacheTaskBySignal(signal);
      if (!task || task.cancelSeenNonce === signal.nonce) {
        return;
      }
      this.beginStoppingShelfFullTextCache(task, signal.nonce, true);
      return;
    }
    let stopped = false;
    this.fullTextCacheTasks.forEach((task: ShelfFullTextCacheTask) => {
      if (task.cancelSeenNonce !== nonce) {
        this.beginStoppingShelfFullTextCache(task, nonce, false);
        stopped = true;
      }
    });
    if (stopped) {
      HdsFeedback.showToast('正在停止缓存…');
    }
  }

  onFullTextCacheCancelSignalChanged(): void {
    const signal = this.parseFullTextCacheCancelSignal();
    if (!signal || !this.isCaching) {
      return;
    }
    const task = this.findShelfFullTextCacheTaskBySignal(signal);
    if (!task || task.cancelSeenNonce === signal.nonce) {
      return;
    }
    this.beginStoppingShelfFullTextCache(task, signal.nonce, true);
  }

  async loadCacheChapters(book: Book, forceRefresh: boolean = false): Promise<boolean> {
    if (!book.bookUrl) {
      this.cacheStatus = '书籍地址为空';
      return false;
    }
    if (!forceRefresh && this.cacheTocLoadPromise && this.cacheTocLoadBookUrl === book.bookUrl) {
      return await this.cacheTocLoadPromise;
    }
    if (!forceRefresh && this.cacheTargetBook?.bookUrl === book.bookUrl && this.cacheChapters.length > 0) {
      return true;
    }
    const token = ++this.cacheTocLoadToken;
    this.cacheTocLoadBookUrl = book.bookUrl;
    this.isCacheTocLoading = true;
    if (this.cacheChapters.length === 0) {
      this.cacheStatus = '正在加载目录...';
    }
    const task = this.loadCacheChaptersInternal(book, token);
    this.cacheTocLoadPromise = task;
    try {
      return await task;
    } finally {
      if (token === this.cacheTocLoadToken) {
        this.isCacheTocLoading = false;
        this.cacheTocLoadPromise = null;
      }
    }
  }

  async loadCacheChaptersInternal(book: Book, token: number): Promise<boolean> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const engine = ReadBookEngine.createBackgroundWorker();
      await engine.openBook(book);
      await engine.syncChapterCacheDates();
      if (token !== this.cacheTocLoadToken || this.cacheTargetBook?.bookUrl !== book.bookUrl ||
        engine.book?.bookUrl !== book.bookUrl) {
        return false;
      }
      const chapters = [...engine.chapters];
      this.cacheChapters = chapters;
      // A running background task owns the status line; its per-chapter progress is more useful
      // than the catalog summary, and the list already marks every cached chapter.
      if (this.isBookCaching(book)) {
        return chapters.length > 0;
      }
      if (chapters.length > 0) {
        const cachedCount = this.countCachedChapters(chapters);
        this.cacheStatus = `${cachedCount}章已缓存 ${chapters.length - cachedCount}章待缓存`;
      } else {
        this.cacheStatus = '暂未获取到目录';
      }
      return chapters.length > 0;
    } catch (e) {
      console.error('加载缓存目录失败:', e);
      if (token === this.cacheTocLoadToken && this.cacheTargetBook?.bookUrl === book.bookUrl &&
        !this.isBookCaching(book)) {
        this.cacheStatus = '目录加载失败，请稍后重试';
        HdsFeedback.showToast('目录加载失败');
      }
      return false;
    }
  }

  async cacheWholeBook(): Promise<void> {
    if (!this.cacheTargetBook || this.isCacheTargetBookCaching()) {
      return;
    }
    if (Date.now() - this.cacheDialogOpenedAt < 300) {
      return;
    }
    const book = this.cacheTargetBook;
    if (!book.origin || book.origin === 'local') {
      HdsFeedback.showToast('本地书籍无需缓存');
      return;
    }
    this.closeCacheDialog();
    this.showCacheFeedback('已转入后台缓存，可在通知栏取消');
    const task = this.createShelfFullTextCacheTask(book, ++this.fullTextCacheTaskId);
    this.runShelfFullTextCache(book, task).catch((error: Error) => {
      console.error('书架全文缓存任务失败:', error);
      this.setFullTextCacheStatus(task, '全文缓存失败');
      this.showCacheFeedback('全文缓存失败');
      this.publishShelfFullTextCacheNotification(task, '全文缓存失败', this.shelfFullTextCacheProgressText(task), false)
        .catch((e: Error) => {
          console.warn('更新书架缓存失败通知失败:', e);
        });
      this.finishShelfFullTextCacheTask(task);
      this.stopShelfFullTextCacheBackgroundRunning().catch((e: Error) => {
        console.warn('停止书架全文缓存后台任务失败:', e);
      });
    });
  }

  async runShelfFullTextCache(book: Book, task: ShelfFullTextCacheTask): Promise<void> {
    this.registerShelfFullTextCacheTask(task);
    this.setFullTextCacheStatus(task, `${task.scopeLabel}缓存后台进行中`);
    try {
      await this.startShelfFullTextCacheBackgroundRunning(book);
      await this.refreshFullTextCacheCover(book, task);
      if (await this.prepareShelfFullTextCacheNotification()) {
        await this.publishShelfFullTextCacheNotification(task, '准备缓存章节',
          this.shelfFullTextCacheProgressText(task), true);
      }
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const freshBook = await db.getBook(book.bookUrl) || book;
      const engine = ReadBookEngine.createBackgroundWorker();
      task.engine = engine;
      if (this.shouldCancelShelfFullTextCache(task)) {
        this.setFullTextCacheStatus(task, '缓存已取消');
        if (task.stoppingNotificationTask) await task.stoppingNotificationTask;
        await this.publishShelfFullTextCacheNotification(task, '缓存已停止',
          this.shelfFullTextCacheProgressText(task), false);
        return;
      }
      await engine.openBook(freshBook);
      await engine.syncChapterCacheDates();
      if (!this.isShelfFullTextCacheTaskActive(task)) {
        return;
      }
      if (this.shouldCancelShelfFullTextCache(task)) {
        this.setFullTextCacheStatus(task, '缓存已取消');
        if (task.stoppingNotificationTask) await task.stoppingNotificationTask;
        await this.publishShelfFullTextCacheNotification(task, '缓存已停止',
          this.shelfFullTextCacheProgressText(task), false);
        return;
      }
      const total = engine.chapters.length;
      if (total === 0) {
        task.total = 0;
        task.done = 0;
        this.setFullTextCacheStatus(task, '暂无可缓存章节');
        await this.publishShelfFullTextCacheNotification(task, '暂无可缓存章节',
          this.shelfFullTextCacheProgressText(task), false);
        return;
      }
      // A scoped task caches only the requested chapters but still reports progress against that
      // subset, so the notification percentage matches what the user asked for.
      const targets = this.shelfFullTextCacheTargetIndexes(task, total);
      task.total = targets.length;
      task.done = this.countCachedChaptersIn(engine.chapters, targets);
      if (targets.length === 0) {
        this.setFullTextCacheStatus(task, '所选章节均已缓存');
        await this.publishShelfFullTextCacheNotification(task, '所选章节均已缓存',
          this.shelfFullTextCacheProgressText(task), false);
        return;
      }

      await this.publishShelfFullTextCacheProgress(task, true);

      for (let position = 0; position < targets.length; position++) {
        const i = targets[position];
        if (!this.isShelfFullTextCacheTaskActive(task) || this.shouldCancelShelfFullTextCache(task)) {
          break;
        }
        const chapter = engine.chapters[i];
        if (!chapter || chapter.cacheDate > 0) {
          continue;
        }
        this.setFullTextCacheStatus(task, `正在缓存 ${position + 1}/${targets.length}`);
        try {
          if (await engine.cacheChapter(i, (): boolean => this.shouldCancelShelfFullTextCache(task))) {
            task.done = this.countCachedChaptersIn(engine.chapters, targets);
          }
        } catch (e) {
          if (!this.shouldCancelShelfFullTextCache(task)) console.error('缓存章节失败:', i, e);
        }
        this.syncCacheDialogChapterState(task, engine.chapters);
        if (this.shouldCancelShelfFullTextCache(task)) break;
        await this.publishShelfFullTextCacheProgress(task, false);
        await sleepMs(0);
      }

      if (!this.isShelfFullTextCacheTaskActive(task)) {
        return;
      }
      const canceled = this.shouldCancelShelfFullTextCache(task);
      await engine.syncChapterCacheDates();
      task.done = this.countCachedChaptersIn(engine.chapters, targets);
      this.setFullTextCacheStatus(task, canceled ? '缓存已取消' : `缓存完成：${task.done}/${task.total}`);
      this.syncCacheDialogChapterState(task, engine.chapters);
      this.finishCacheDialogSummary(task);
      if (canceled && task.stoppingNotificationTask) await task.stoppingNotificationTask;
      await this.publishShelfFullTextCacheNotification(
        task,
        canceled ? '缓存已停止' : `${task.scopeLabel}缓存完成`,
        this.shelfFullTextCacheProgressText(task),
        false
      );
      this.showCacheFeedback(canceled ? '缓存已停止' : `缓存完成 ${task.done}/${task.total}`);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (error) {
      if (!task.cancelRequested) {
        const message = error instanceof Error ? error.message : '缓存任务执行失败';
        throw new Error(message);
      }
      if (task.stoppingNotificationTask) await task.stoppingNotificationTask;
      this.setFullTextCacheStatus(task, '缓存已取消');
      await this.publishShelfFullTextCacheNotification(task, '缓存已停止',
        this.shelfFullTextCacheProgressText(task), false);
      HdsFeedback.showToast('缓存已停止');
    } finally {
      this.finishShelfFullTextCacheTask(task);
      await this.stopShelfFullTextCacheBackgroundRunning();
    }
  }

  /**
   * Whole-book tasks cache every chapter; scoped tasks cache only the requested indexes and skip
   * out-of-range entries that no longer exist after a catalog refresh.
   */
  shelfFullTextCacheTargetIndexes(task: ShelfFullTextCacheTask, total: number): number[] {
    if (task.chapterIndexes.length === 0) {
      const all: number[] = [];
      for (let i = 0; i < total; i++) all.push(i);
      return all;
    }
    const result: number[] = [];
    for (const index of task.chapterIndexes) {
      if (index >= 0 && index < total) result.push(index);
    }
    return result;
  }

  countCachedChaptersIn(chapters: BookChapter[], indexes: number[]): number {
    let count = 0;
    for (const index of indexes) {
      const chapter = chapters[index];
      if (chapter && chapter.cacheDate > 0) {
        count++;
      }
    }
    return count;
  }

  /**
   * Mirrors the background task's progress into an open chapter panel. The task owns a separate
   * engine, so its chapter objects are not the ones the panel renders.
   */
  syncCacheDialogChapterState(task: ShelfFullTextCacheTask, taskChapters: BookChapter[]): void {
    if (!this.showChapterCacheDialog || this.cacheTargetBook?.bookUrl !== task.bookUrl ||
      this.cacheChapters.length === 0) {
      return;
    }
    let changed = false;
    for (const chapter of this.cacheChapters) {
      const taskChapter = taskChapters[chapter.index];
      if (!taskChapter || taskChapter.cacheDate <= 0 || chapter.cacheDate > 0) continue;
      chapter.cacheDate = taskChapter.cacheDate;
      changed = true;
    }
    if (changed) {
      this.cacheChapters = [...this.cacheChapters];
    }
  }

  /** Hands the status line back to the catalog summary once the background task has finished. */
  finishCacheDialogSummary(task: ShelfFullTextCacheTask): void {
    if (!this.showChapterCacheDialog || this.cacheTargetBook?.bookUrl !== task.bookUrl ||
      this.cacheChapters.length === 0) {
      return;
    }
    const cachedCount = this.countCachedChapters(this.cacheChapters);
    this.cacheStatus = `${cachedCount}章已缓存 ${this.cacheChapters.length - cachedCount}章待缓存`;
  }

  createShelfFullTextCacheTask(book: Book, taskId: number, chapterIndexes: number[] = [],
    scopeLabel: string = '全文'): ShelfFullTextCacheTask {
    const bookUrl = book.bookUrl || '';
    return {
      taskId: taskId,
      bookUrl: bookUrl,
      bookName: book.name || '书籍',
      taskKey: this.buildFullTextCacheTaskKey(book, taskId),
      createdAt: Date.now(),
      cancelRequested: false,
      cancelSeenNonce: AppStorage.get<number>('fullTextCacheCancelNonce') || 0,
      notificationLastAt: 0,
      cancelAgent: null,
      done: 0,
      total: 0,
      status: '',
      coverPixelMap: null,
      notificationFailureHintShown: false,
      engine: null,
      stoppingNotificationTask: null,
      chapterIndexes: chapterIndexes,
      scopeLabel: scopeLabel
    };
  }

  registerShelfFullTextCacheTask(task: ShelfFullTextCacheTask): void {
    this.fullTextCacheTasks.set(task.bookUrl, task);
    FullTextCacheCancelCoordinator.register(task.taskKey, task.bookUrl,
      (signal: FullTextCacheCancelSignal): void => {
        if (FullTextCacheCancelCoordinator.matches(signal, task.taskKey, task.bookUrl)) {
          this.beginStoppingShelfFullTextCache(task, signal.nonce, true);
        }
      });
    this.syncShelfFullTextCacheTaskState();
  }

  finishShelfFullTextCacheTask(task: ShelfFullTextCacheTask): void {
    FullTextCacheCancelCoordinator.unregister(task.taskKey);
    const current = this.fullTextCacheTasks.get(task.bookUrl);
    if (current && current.taskKey === task.taskKey) {
      this.fullTextCacheTasks.delete(task.bookUrl);
    }
    task.engine = null;
    task.stoppingNotificationTask = null;
    this.releaseFullTextCacheCover(task);
    this.syncShelfFullTextCacheTaskState();
  }

  syncShelfFullTextCacheTaskState(): void {
    this.activeFullTextCacheBookUrls = Array.from(this.fullTextCacheTasks.keys());
    this.isCaching = this.activeFullTextCacheBookUrls.length > 0;
  }

  getShelfFullTextCacheTask(bookUrl: string): ShelfFullTextCacheTask | null {
    return bookUrl ? this.fullTextCacheTasks.get(bookUrl) || null : null;
  }

  isShelfFullTextCacheTaskActive(task: ShelfFullTextCacheTask): boolean {
    const current = this.fullTextCacheTasks.get(task.bookUrl);
    return !!current && current.taskKey === task.taskKey;
  }

  findShelfFullTextCacheTaskBySignal(signal: FullTextCacheCancelSignal): ShelfFullTextCacheTask | null {
    if (signal.taskKey) {
      for (const task of this.fullTextCacheTasks.values()) {
        if (task.taskKey === signal.taskKey) {
          return task;
        }
      }
    }
    return signal.bookUrl ? this.getShelfFullTextCacheTask(signal.bookUrl) : null;
  }

  beginStoppingShelfFullTextCache(task: ShelfFullTextCacheTask, nonce: number, showHint: boolean): void {
    if (!this.isShelfFullTextCacheTaskActive(task) || task.cancelRequested) return;
    task.cancelRequested = true;
    task.cancelSeenNonce = nonce;
    this.setFullTextCacheStatus(task, '正在停止缓存…');
    task.engine?.cancelPendingRequests();
    task.stoppingNotificationTask = this.publishShelfFullTextCacheNotification(task, '正在停止缓存…',
      this.shelfFullTextCacheProgressText(task), true).catch((error: Error) => {
      console.warn('更新正在停止缓存通知失败:', error);
    });
    if (showHint) HdsFeedback.showToast('正在停止缓存…');
  }

  shouldCancelShelfFullTextCache(task: ShelfFullTextCacheTask): boolean {
    if (task.cancelRequested) {
      return true;
    }
    const nonce = AppStorage.get<number>('fullTextCacheCancelNonce') || 0;
    if (nonce > 0 && nonce !== task.cancelSeenNonce) {
      const signal = this.parseFullTextCacheCancelSignal();
      if (signal && !this.isCurrentFullTextCacheSignal(task, signal)) {
        task.cancelSeenNonce = signal.nonce;
        return false;
      }
      if (!signal || this.isCurrentFullTextCacheSignal(task, signal)) {
        this.beginStoppingShelfFullTextCache(task, signal ? signal.nonce : nonce, false);
        return true;
      }
    }
    return false;
  }

  parseFullTextCacheCancelSignal(): FullTextCacheCancelSignal | null {
    const raw = this.fullTextCacheCancelSignal || AppStorage.get<string>('fullTextCacheCancelSignal') || '';
    if (!raw.trim()) {
      return null;
    }
    return FullTextCacheCancelCoordinator.parse(raw);
  }

  isCurrentFullTextCacheSignal(task: ShelfFullTextCacheTask, signal: FullTextCacheCancelSignal): boolean {
    if (signal.taskKey && task.taskKey && signal.taskKey === task.taskKey) {
      return true;
    }
    return !!signal.bookUrl && signal.bookUrl === task.bookUrl;
  }

  countCachedChapters(chapters: BookChapter[]): number {
    let count = 0;
    for (const chapter of chapters) {
      if (chapter.cacheDate > 0) {
        count++;
      }
    }
    return count;
  }

  shelfFullTextCacheProgressText(task: ShelfFullTextCacheTask): string {
    const total = Math.max(task.total, 0);
    if (total === 0) {
      return '正在准备缓存章节（0%）';
    }
    const done = Math.max(0, Math.min(task.done, total));
    const percent = Math.floor((done / total) * 100);
    return `已缓存 ${done}/${total} 章（${percent}%）`;
  }

  shelfFullTextCacheNotificationTitle(task: ShelfFullTextCacheTask): string {
    return `缓存${task.scopeLabel}：${task.bookName || '书籍'}`;
  }

  shelfFullTextCacheDisplayText(text: string, additionalText: string, ongoing: boolean): string {
    if (!ongoing || !additionalText || text.includes(additionalText)) {
      return text;
    }
    return `${text} · ${additionalText}`;
  }

  shelfFullTextCacheNormalContent(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): notificationManager.NotificationBasicContent {
    const normalContent: notificationManager.NotificationBasicContent = {
      title: this.shelfFullTextCacheNotificationTitle(task),
      text: this.shelfFullTextCacheDisplayText(text, additionalText, ongoing),
      additionalText: additionalText
    };
    if (task.coverPixelMap) {
      normalContent.lockscreenPicture = task.coverPixelMap;
    }
    return normalContent;
  }

  applyShelfFullTextCacheCoverToRequest(task: ShelfFullTextCacheTask,
    request: notificationManager.NotificationRequest): void {
    if (!task.coverPixelMap) {
      return;
    }
    request.smallIcon = task.coverPixelMap;
    request.largeIcon = task.coverPixelMap;
  }

  async publishShelfFullTextCacheProgress(task: ShelfFullTextCacheTask, force: boolean): Promise<void> {
    const now = Date.now();
    if (!force && now - task.notificationLastAt < SHELF_FULL_TEXT_CACHE_NOTIFICATION_INTERVAL_MS) {
      return;
    }
    task.notificationLastAt = now;
    await this.publishShelfFullTextCacheNotification(task, '全文缓存后台进行中',
      this.shelfFullTextCacheProgressText(task), true);
  }

  async publishShelfFullTextCacheNotification(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: this.fullTextCacheNotificationId(task.bookUrl),
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: ongoing,
        tapDismissed: false,
        isAlertOnce: true,
        deliveryTime: task.createdAt,
        showDeliveryTime: false,
        wantAgent: await this.getShelfFullTextCacheOpenWantAgent(task),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: this.shelfFullTextCacheNormalContent(task, text, additionalText, ongoing)
        }
      };
      if (!ongoing) {
        request.autoDeletedTime = Date.now() + 5000;
      }
      request.label = this.fullTextCacheNotificationLabel(task.bookUrl);
      this.applyShelfFullTextCacheCoverToRequest(task, request);
      if (ongoing) {
        request.actionButtons = [{
          title: '停止缓存',
          wantAgent: await this.getShelfFullTextCacheCancelWantAgent(task)
        }];
      }
      await notificationManager.publish(request);
    } catch (error) {
      console.warn('发布书架全文缓存通知失败:', error);
      try {
        await this.publishBasicShelfFullTextCacheNotification(task, text, additionalText, ongoing);
      } catch (fallbackError) {
        console.warn('发布书架全文缓存基础通知失败:', fallbackError);
        try {
          await this.publishMinimalShelfFullTextCacheNotification(task, text, additionalText, ongoing);
        } catch (minimalError) {
          console.warn('发布书架全文缓存最小通知失败:', minimalError);
          this.showShelfFullTextCacheNotificationFailureHint(task, minimalError);
        }
      }
    }
  }

  async publishBasicShelfFullTextCacheNotification(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: this.fullTextCacheNotificationId(task.bookUrl),
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: ongoing,
      tapDismissed: false,
      isAlertOnce: true,
      deliveryTime: task.createdAt,
      showDeliveryTime: false,
      wantAgent: await this.getShelfFullTextCacheOpenWantAgent(task),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: this.shelfFullTextCacheNormalContent(task, text, additionalText, ongoing)
      }
    };
    if (!ongoing) {
      request.autoDeletedTime = Date.now() + 5000;
    }
    request.label = this.fullTextCacheNotificationLabel(task.bookUrl);
    if (ongoing) {
      request.actionButtons = [{
        title: '停止缓存',
        wantAgent: await this.getShelfFullTextCacheCancelWantAgent(task)
      }];
    }
    this.applyShelfFullTextCacheCoverToRequest(task, request);
    await notificationManager.publish(request);
  }

  async publishMinimalShelfFullTextCacheNotification(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: this.fullTextCacheNotificationId(task.bookUrl),
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: ongoing,
      tapDismissed: false,
      isAlertOnce: true,
      deliveryTime: task.createdAt,
      showDeliveryTime: false,
      wantAgent: await this.getShelfFullTextCacheOpenWantAgent(task),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: this.shelfFullTextCacheNormalContent(task, text, additionalText, ongoing)
      }
    };
    if (!ongoing) {
      request.autoDeletedTime = Date.now() + 5000;
    }
    request.label = this.fullTextCacheNotificationLabel(task.bookUrl);
    this.applyShelfFullTextCacheCoverToRequest(task, request);
    await notificationManager.publish(request);
  }

  async refreshFullTextCacheCover(book: Book, task: ShelfFullTextCacheTask): Promise<void> {
    this.releaseFullTextCacheCover(task);
    const raw = this.getShelfCover(book);
    if (!raw) {
      return;
    }
    try {
      const coverPath = await BookCoverCache.prepareCoverFile(getContext(this), raw);
      if (!coverPath) {
        return;
      }
      task.coverPixelMap = await this.createFullTextCacheCoverPixelMap(coverPath);
    } catch (error) {
      console.warn('解析缓存通知封面失败:', error);
    }
  }

  async createFullTextCacheCoverPixelMap(path: string): Promise<image.PixelMap | null> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      return await source.createPixelMap({
        desiredSize: {
          width: 128,
          height: 128
        }
      });
    } catch (error) {
      console.warn('创建缓存通知封面 PixelMap 失败:', error);
      return null;
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (e) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (e) {
        }
      }
    }
  }

  releaseFullTextCacheCover(task: ShelfFullTextCacheTask): void {
    if (!task.coverPixelMap) {
      return;
    }
    try {
      task.coverPixelMap.release().catch((e: Error) => {
        console.warn('释放缓存通知封面失败:', e);
      });
    } catch (e) {
      console.warn('释放缓存通知封面失败:', e);
    }
    task.coverPixelMap = null;
  }

  async prepareShelfFullTextCacheNotification(): Promise<boolean> {
    try {
      if (!await notificationManager.isNotificationEnabled()) {
        try {
          await notificationManager.requestEnableNotification(getContext(this) as common.UIAbilityContext);
        } catch (error) {
          console.warn('请求通知权限失败:', error);
          HdsFeedback.showToast('通知权限未开启，缓存仍会继续');
          return false;
        }
      }
      if (!await notificationManager.isNotificationEnabled()) {
        HdsFeedback.showToast('通知权限未开启，缓存仍会继续');
        return false;
      }
      if (!this.fullTextCacheNotificationSlotReady) {
        await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
        this.fullTextCacheNotificationSlotReady = true;
      }
      return true;
    } catch (error) {
      console.warn('准备书架缓存通知失败:', error);
      this.showShelfFullTextCacheNotificationFailureHint(null, error);
      return false;
    }
  }

  showShelfFullTextCacheNotificationFailureHint(task: ShelfFullTextCacheTask | null, error: Object): void {
    if (task) {
      if (task.notificationFailureHintShown) {
        return;
      }
      task.notificationFailureHintShown = true;
    } else if (this.fullTextCacheNotificationFailureHintShown) {
      return;
    } else {
      this.fullTextCacheNotificationFailureHintShown = true;
    }
    console.warn('书架缓存通知不可用:', error);
    HdsFeedback.showToast(this.shelfFullTextCacheNotificationFailureMessage(error));
  }

  shelfFullTextCacheNotificationFailureMessage(error: Object): string {
    const code = this.notificationErrorCode(error);
    if (code === 1600004 || code === 1600020) {
      return '通知权限未开启，缓存仍会继续';
    }
    if (code === 1600005) {
      return '通知类别已关闭，请检查应用通知设置';
    }
    if (code === 1600009) {
      return '通知发送过快，缓存仍会继续';
    }
    return code > 0 ? `通知发布失败(${code})` : '通知发布失败，请检查应用通知权限';
  }

  notificationErrorCode(error: Object): number {
    const record = error as Record<string, Object>;
    const code = record['code'];
    return typeof code === 'number' ? code as number : 0;
  }

  async getShelfFullTextCacheCancelWantAgent(task: ShelfFullTextCacheTask): Promise<WantAgent> {
    if (task.cancelAgent) {
      return task.cancelAgent;
    }
    const context = getContext(this) as common.UIAbilityContext;
    task.cancelAgent = await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          cacheAction: 'cancelFullTextCache',
          cacheTaskId: task.taskId,
          cacheTaskKey: task.taskKey,
          bookUrl: task.bookUrl
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.fullTextCacheCancelRequestCode(task.bookUrl),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    return task.cancelAgent;
  }

  async getShelfFullTextCacheOpenWantAgent(task: ShelfFullTextCacheTask): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          bookUrl: task.bookUrl
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.fullTextCacheOpenRequestCode(task.bookUrl),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  async startShelfFullTextCacheBackgroundRunning(book: Book): Promise<void> {
    if (this.fullTextCacheBackgroundRunning) {
      return;
    }
    try {
      const agent = await this.createShelfFullTextCacheOpenWantAgent(book);
      await backgroundTaskManager.startBackgroundRunning(getContext(this), ['dataTransfer'], agent);
      this.fullTextCacheBackgroundRunning = true;
    } catch (error) {
      console.warn('启动书架全文缓存后台任务失败:', error);
    }
  }

  async stopShelfFullTextCacheBackgroundRunning(): Promise<void> {
    if (!this.fullTextCacheBackgroundRunning || this.fullTextCacheTasks.size > 0) {
      return;
    }
    this.fullTextCacheBackgroundRunning = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(getContext(this));
    } catch (error) {
      console.warn('停止书架全文缓存后台任务失败:', error);
    }
  }

  async createShelfFullTextCacheOpenWantAgent(book: Book): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          bookUrl: book.bookUrl || ''
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.fullTextCacheOpenRequestCode(book.bookUrl || ''),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  buildFullTextCacheTaskKey(book: Book, taskId: number): string {
    return `${this.fullTextCacheHash(book.bookUrl || book.name || 'book')}_${taskId}`;
  }

  fullTextCacheNotificationId(bookUrl: string): number {
    return 260100 + (this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book') % 100000);
  }

  fullTextCacheCancelRequestCode(bookUrl: string): number {
    return 360100 + (this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book') % 100000);
  }

  fullTextCacheOpenRequestCode(bookUrl: string): number {
    return 460100 + (this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book') % 100000);
  }

  fullTextCacheNotificationLabel(bookUrl: string): string {
    return `full_text_cache_${this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book')}`;
  }

  fullTextCacheHash(value: string): number {
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(i);
      hash |= 0;
    }
    return Math.abs(hash);
  }

  parseChapterRange(raw: string, total: number): number[] {
    const value = (raw || '').trim();
    if (!value || total <= 0) return [];
    const normalized = value.replace(/[，、；;]/g, ',').replace(/[～至]/g, '-');
    const result = new Set<number>();
    for (const part of normalized.split(/[\s,]+/)) {
      if (!part) continue;
      const range = part.match(/^(\d+)\s*-\s*(\d+)$/);
      if (range) {
        const start = Number.parseInt(range[1], 10);
        const end = Number.parseInt(range[2], 10);
        if (start < 1 || end < 1 || start > total || end > total) return [];
        const low = Math.min(start, end);
        const high = Math.max(start, end);
        for (let chapterNumber = low; chapterNumber <= high; chapterNumber++) {
          result.add(chapterNumber - 1);
        }
        continue;
      }
      if (!/^\d+$/.test(part)) return [];
      const chapterNumber = Number.parseInt(part, 10);
      if (chapterNumber < 1 || chapterNumber > total) return [];
      result.add(chapterNumber - 1);
    }
    return Array.from(result).sort((left: number, right: number) => left - right);
  }

  /**
   * Range and single-chapter caching both run as background tasks. They used to await every chapter
   * on the UI thread, which blocked the panel and made it unclosable for the whole download.
   */
  async cacheChapterRange(): Promise<void> {
    const total = this.cacheChapters.length;
    const indexes = this.parseChapterRange(this.cacheRangeDraft, total);
    if (indexes.length === 0) {
      HdsFeedback.showToast(`请输入有效章节范围（1-${total}）`);
      return;
    }
    await this.startScopedShelfCache(indexes, '章节');
  }

  async cacheSingleChapter(index: number): Promise<void> {
    await this.startScopedShelfCache([index], '章节');
  }

  async startScopedShelfCache(indexes: number[], scopeLabel: string): Promise<void> {
    const book = this.cacheTargetBook;
    if (!book || indexes.length === 0) {
      return;
    }
    if (this.isBookCaching(book)) {
      this.showCacheFeedback('该书正在后台缓存，请稍候');
      return;
    }
    if (!book.origin || book.origin === 'local') {
      HdsFeedback.showToast('本地书籍无需缓存');
      return;
    }
    // The panel stays open so progress and the "已缓存" marks stay visible; closing it is the
    // user's choice and never interrupts the task.
    this.showCacheFeedback(`已转入后台缓存 ${indexes.length} 章，可在通知栏取消`);
    const task = this.createShelfFullTextCacheTask(book, ++this.fullTextCacheTaskId, indexes, scopeLabel);
    this.runShelfFullTextCache(book, task).catch((error: Error) => {
      console.error('书架指定章节缓存任务失败:', error);
      this.setFullTextCacheStatus(task, '缓存失败');
      this.showCacheFeedback('缓存失败');
      this.publishShelfFullTextCacheNotification(task, '缓存失败',
        this.shelfFullTextCacheProgressText(task), false).catch((e: Error) => {
        console.warn('更新书架缓存失败通知失败:', e);
      });
      this.finishShelfFullTextCacheTask(task);
      this.stopShelfFullTextCacheBackgroundRunning().catch((e: Error) => {
        console.warn('停止书架缓存后台任务失败:', e);
      });
    });
  }

  async clearCachedChapters(): Promise<void> {
    if (!this.cacheTargetBook) {
      return;
    }
    if (this.isCacheTargetBookCaching()) {
      HdsFeedback.showToast('缓存进行中，稍后再清除');
      return;
    }
    const book = this.cacheTargetBook;
    if (!book.bookUrl) {
      HdsFeedback.showToast('书籍地址为空');
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBookCachedContent(book.bookUrl);
      const engine = ReadBookEngine.get();
      if (engine.book?.bookUrl === book.bookUrl) {
        engine.clearCurrentBookMemoryCache();
        await engine.syncChapterCacheDates();
        this.cacheChapters = [...engine.chapters];
      } else {
        for (const chapter of this.cacheChapters) {
          chapter.cacheDate = 0;
        }
        this.cacheChapters = [...this.cacheChapters];
      }
      this.cacheStatus = '已清除缓存章节';
      this.showCacheFeedback('已清除缓存章节');
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('清除缓存章节失败:', e);
      this.cacheStatus = '清除缓存失败';
      this.showCacheFeedback('清除缓存失败');
    }
  }

  async refreshBookshelfToc(silent: boolean = false): Promise<void> {
    if (this.shelfRefreshRunning) {
      if (!silent) {
        this.shelfRefreshPrompt = '书架刷新中';
        this.isShelfRefreshing = true;
      }
      return;
    }
    if (!silent && this.shelfShowsLocalOnly()) {
      await this.refreshLocalBooks();
      return;
    }
    const shelfBooks = silent ? [...this.allBooks] : [...this.books];
    if (shelfBooks.length === 0) {
      if (!silent) this.isShelfRefreshing = false;
      return;
    }
    this.shelfRefreshRunning = true;
    const refreshStartedAt = Date.now();
    if (!silent) {
      this.isShelfRefreshing = true;
      HdsFeedback.showToast('正在刷新书架...');
    }
    let attempted = 0;
    let skippedFinished = 0;
    let updated = 0;
    let failed = 0;
    let taskFailed = false;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const engine = ReadBookEngine.createBackgroundWorker();
      for (const shelfBook of shelfBooks) {
        if (!shelfBook.bookUrl || LocalBookService.isLocalBook(shelfBook) || !shelfBook.canUpdate) {
          continue;
        }
        if (this.isFinishedBook(shelfBook)) {
          skippedFinished++;
          continue;
        }
        attempted++;
        try {
          const freshBook = await db.getBook(shelfBook.bookUrl) || shelfBook;
          const beforeCount = freshBook.totalChapterNum;
          const beforeLatest = freshBook.latestChapterTitle;
          const hadPendingUpdate = this.hasShelfBookUpdate(freshBook);
          await engine.openBook(freshBook);
          await engine.refreshToc();
          const refreshedBook = await db.getBook(shelfBook.bookUrl);
          if (refreshedBook) {
            refreshedBook.lastCheckTime = Date.now();
            refreshedBook.lastCheckCount = engine.chapters.length;
            if (engine.chapters.length > 0) {
              refreshedBook.totalChapterNum = engine.chapters.length;
              refreshedBook.latestChapterTitle = engine.chapters[engine.chapters.length - 1].title;
            }
            const hasNewUpdate = refreshedBook.totalChapterNum > beforeCount ||
              refreshedBook.latestChapterTitle !== beforeLatest;
            const acknowledgedAt = this.shelfUpdateAcknowledgedAt.get(refreshedBook.bookUrl) || 0;
            const keepPendingUpdate = hadPendingUpdate && acknowledgedAt === 0;
            const keepNewUpdate = hasNewUpdate && acknowledgedAt < refreshStartedAt;
            refreshedBook.putVariable(SHELF_UPDATE_BADGE_VARIABLE,
              keepPendingUpdate || keepNewUpdate ? '1' : '');
            await db.updateBook(refreshedBook);
            if (hasNewUpdate) {
              updated++;
            }
          }
        } catch (e) {
          failed++;
          console.error('刷新书架目录失败:', shelfBook.name, e);
        }
      }
      if (attempted > 0) {
        await this.loadBooks();
        if (!silent) {
          const skippedText = skippedFinished > 0 ? `，跳过${skippedFinished}本完结` : '';
          const message = failed > 0 ?
            `书架刷新完成：${updated}本有更新，${failed}本失败${skippedText}` :
            `书架刷新完成：${updated}本有更新${skippedText}`;
          HdsFeedback.showToast(message);
        }
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }
    } catch (e) {
      taskFailed = true;
      console.error('刷新书架失败:', e);
      if (!silent) HdsFeedback.showToast('书架刷新失败');
    } finally {
      this.shelfRefreshRunning = false;
      this.isShelfRefreshing = false;
      this.shelfRefreshStatus = RefreshStatus.Inactive;
      this.shelfRefreshPrompt = '下拉刷新书架';
      if (!silent && !taskFailed && attempted === 0) {
        const message = skippedFinished > 0 ? `没有可刷新的连载书籍，已跳过${skippedFinished}本完结` : '没有可刷新的网络书籍';
        HdsFeedback.showToast(message);
      }
    }
  }

  async refreshLocalBooks(): Promise<void> {
    this.shelfRefreshRunning = true;
    this.isShelfRefreshing = true;
    this.shelfRefreshPrompt = '正在刷新本地书籍...';
    try {
      await this.loadBooks();
      HdsFeedback.showToast('本地书架已刷新');
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('刷新本地书籍失败:', e);
      HdsFeedback.showToast('本地书架刷新失败');
    } finally {
      this.shelfRefreshRunning = false;
      this.isShelfRefreshing = false;
      this.shelfRefreshStatus = RefreshStatus.Inactive;
      this.shelfRefreshPrompt = '下拉刷新书架';
    }
  }

  isFinishedBook(book: Book): boolean {
    return this.shelfBookStatusMarker(book) === 'finished';
  }

  /** 从分类、书源状态和自定义标签里读出的完结标记：'finished'、'ongoing'，读不出时为空串。 */
  shelfBookStatusMarker(book: Book): string {
    const text = `${book.kind || ''},${book.status || ''},${book.customTag || ''}`.replace(/\s+/g, '');
    if (!text.replace(/,/g, '')) {
      return '';
    }
    if (/(连载中|連載中|连载|連載|未完结|未完結|更新中|ongoing|serializing)/i.test(text)) {
      return 'ongoing';
    }
    return /(已完结|已完結|完结|完結|完本|全本|完$|completed|complete|finished)/i.test(text) ? 'finished' : '';
  }

  /** 书源标了完结算已完结；本地书是完整文件，除非标了连载也算已完结；其余都算连载中。 */
  isShelfBookFinished(book: Book): boolean {
    const marker = this.shelfBookStatusMarker(book);
    if (marker) {
      return marker === 'finished';
    }
    return LocalBookService.isLocalBook(book);
  }

  trackShelfRefreshPullOffset(offset: number): void {
    if (this.shelfRefreshRunning || this.isShelfRefreshing) {
      return;
    }
    if (this.shelfRefreshStatus !== RefreshStatus.Drag && this.shelfRefreshStatus !== RefreshStatus.OverDrag) {
      return;
    }
    if (this.shelfRefreshPullRetracting) {
      if (offset > this.shelfRefreshPullTrough + SHELF_REFRESH_PULL_DIRECTION_SLOP) {
        this.shelfRefreshPullRetracting = false;
        this.shelfRefreshPullPeak = offset;
      } else {
        this.shelfRefreshPullTrough = Math.min(this.shelfRefreshPullTrough, offset);
      }
    } else if (this.shelfRefreshStatus === RefreshStatus.Drag &&
      offset < this.shelfRefreshPullPeak - SHELF_REFRESH_PULL_DIRECTION_SLOP) {
      // 只收起“下拉刷新书架”；“松手刷新书架”阶段往回推仍会刷新，提示要留着。
      this.shelfRefreshPullRetracting = true;
      this.shelfRefreshPullTrough = offset;
    } else {
      this.shelfRefreshPullPeak = Math.max(this.shelfRefreshPullPeak, offset);
    }
  }

  resetShelfRefreshPullTracking(): void {
    this.shelfRefreshPullPeak = 0;
    this.shelfRefreshPullTrough = 0;
    this.shelfRefreshPullRetracting = false;
  }

  updateShelfRefreshPrompt(state: RefreshStatus): void {
    if (state === RefreshStatus.Inactive || state === RefreshStatus.Done || state === RefreshStatus.Refresh) {
      this.resetShelfRefreshPullTracking();
    }
    this.shelfRefreshStatus = state;
    if (this.shelfRefreshRunning) {
      this.shelfRefreshPrompt = '书架刷新中';
      return;
    }
    if (state === RefreshStatus.OverDrag) {
      this.shelfRefreshPrompt = '松手刷新书架';
    } else if (state === RefreshStatus.Refresh) {
      this.shelfRefreshPrompt = '正在刷新书架...';
    } else if (state === RefreshStatus.Done) {
      // Done is the native rebound/settled phase. Keeping a fixed sibling visible here makes
      // the prompt overlap the first shelf item after the books have already returned to place.
      this.shelfRefreshPrompt = '下拉刷新书架';
    } else {
      this.shelfRefreshPrompt = '下拉刷新书架';
    }
  }

  shouldShowShelfRefreshStatus(): boolean {
    if (this.isShelfRefreshing) return true;
    if (this.shelfRefreshPullRetracting) return false;
    return this.shelfRefreshStatus === RefreshStatus.Drag ||
      this.shelfRefreshStatus === RefreshStatus.OverDrag ||
      this.shelfRefreshStatus === RefreshStatus.Refresh;
  }

  async updateShelfBook(book: Book): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.updateBook(book);
      this.books = this.books.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('更新书籍失败:', e);
      HdsFeedback.showToast('保存失败');
    }
  }

  cachedChapterTextColor(): string {
    return this.appDarkMode ? '#DDEFE5' : '#244B35';
  }

  @Builder
  shelfRefreshBuilder() {
    // Refresh translates its builder back to y=0 during Done. The bookshelf header is an
    // immersive glass overlay, so a visible builder would travel through that overlay. Keep the
    // layout placeholder here and render the status in a fixed sibling below the full header.
    Row()
      .height(48)
      .width('100%')
      .opacity(0)
  }

  @Builder
  shelfRefreshStatusOverlay() {
    Row({ space: AppSpacing.MD }) {
      if (this.isShelfRefreshing) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.accentColor())
      }
      Text(this.shelfRefreshPrompt)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
    }
    .height(48)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .position({ x: 0, y: this.bookshelfTopOverlayHeight() + 4 })
    .zIndex(3)
    .hitTestBehavior(HitTestMode.None)
  }

  /** 从筛选菜单的“搜索书架”展开，边输入边筛当前书架；“取消”清空关键词并收起。 */
  @Builder
  shelfSearchBar() {
    Row({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
        TextInput({ text: this.shelfSearchKeyword, placeholder: '书名、作者、书源或标签' })
          .key(SHELF_SEARCH_INPUT_KEY)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .caretColor(this.accentColor())
          .layoutWeight(1)
          .height(BookshelfPage.SEARCH_BAR_HEIGHT)
          .padding({ left: 0, right: 0 })
          .backgroundColor(Color.Transparent)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string): void => {
            this.shelfSearchKeyword = value;
          })
          .onSubmit((): void => {
            this.getUIContext().getFocusController().clearFocus();
          })
        if (this.shelfSearchKeyword) {
          Text('×')
            .fontSize(AppFontSize.TITLE)
            .fontColor(this.subTextColor())
            .width(32)
            .height(BookshelfPage.SEARCH_BAR_HEIGHT)
            .textAlign(TextAlign.Center)
            .accessibilityText('清空关键词')
            .onClick((): void => {
              this.shelfSearchKeyword = '';
              focusControl.requestFocus(SHELF_SEARCH_INPUT_KEY);
            })
        }
      }
      .layoutWeight(1)
      .height(BookshelfPage.SEARCH_BAR_HEIGHT)
      .padding({ left: AppSpacing.LG, right: AppSpacing.SM })
      .borderRadius(BookshelfPage.SEARCH_BAR_HEIGHT / 2)
      .backgroundColor(this.cardColor())

      Text('取消')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .height(BookshelfPage.SEARCH_BAR_HEIGHT)
        .accessibilityText('取消搜索书架')
        .onClick(() => this.closeShelfSearch())
    }
    .width('100%')
    .height(BookshelfPage.SEARCH_BAR_HEIGHT)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .margin({ bottom: AppSpacing.MD })
    .alignItems(VerticalAlign.Center)
  }

  showsShelfScopeTabs(): boolean {
    return !this.isBookMultiSelect && !this.isTileGroupPage();
  }

  @Builder
  shelfScopeTabs() {
    Row() {
      if (this.shelfScopeTabsWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.shelfScopeTabsWidth,
          surfaceHeight: BookshelfPage.SCOPE_TABS_HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: this.accentGlowColor()
        }) {
          Stack({ alignContent: Alignment.BottomStart }) {
            Row() {
              ForEach(this.shelfTypeTabIds, (id: string) => {
                Text(this.shelfTypeTabLabel(id))
                  .fontSize(AppFontSize.BODY_LARGE)
                  .fontWeight(this.isShelfTypeTabSelected(id) ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.isShelfTypeTabSelected(id) ? this.accentColor() : this.secondaryTextColor())
                  .animation({ duration: 180, curve: Curve.Friction })
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height('100%')
                  .accessibilityText(this.shelfTypeTabLabel(id))
                  .accessibilitySelected(this.isShelfTypeTabSelected(id))
                  .onClick(() => this.switchShelfScopeBySelection(id))
              }, (id: string) => id)
            }
            .width('100%')
            .height('100%')
            .padding({ left: BookshelfPage.SCOPE_TABS_PADDING, right: BookshelfPage.SCOPE_TABS_PADDING })

            // 选中指示条：在选中项文字下方滑动，停在隐私书架时隐藏。
            Row()
              .width(BookshelfPage.SCOPE_TAB_INDICATOR_WIDTH)
              .height(3)
              .borderRadius(1.5)
              .backgroundColor(this.accentColor())
              .opacity(this.shelfScopeTabHighlighted() ? 1 : 0)
              .translate({ x: this.shelfScopeTabIndicatorX(), y: -5 })
              .animation({ duration: 280, curve: Curve.Friction })
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .height('100%')
        }
      }
    }
    .width(`calc(100% - ${AppSpacing.XL * 2}vp)`)
    .height(BookshelfPage.SCOPE_TABS_HEIGHT)
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.shelfScopeTabsWidth) {
        this.shelfScopeTabsWidth = width;
      }
    })
  }

  /** 切换动画进行中时先让分类栏跳到目标项，书籍列表的淡出淡入随后跟上。 */
  shelfScopeTabIndex(): number {
    const index = this.shelfTypeTabIds.indexOf(this.shelfScopeTabSelection || this.shelfPageKey());
    return index >= 0 ? index : 0;
  }

  shelfScopeTabHighlighted(): boolean {
    return this.shelfTypeTabIds.indexOf(this.shelfScopeTabSelection || this.shelfPageKey()) >= 0;
  }

  isShelfTypeTabSelected(id: string): boolean {
    return this.shelfScopeTabHighlighted() && this.shelfTypeTabIds[this.shelfScopeTabIndex()] === id;
  }

  /** 指示条居中在选中项下方；各项等宽平分分类栏去掉两侧留白后的宽度。 */
  shelfScopeTabIndicatorX(): number {
    const count = Math.max(1, this.shelfTypeTabIds.length);
    const itemWidth = (this.shelfScopeTabsWidth - BookshelfPage.SCOPE_TABS_PADDING * 2) / count;
    return BookshelfPage.SCOPE_TABS_PADDING + itemWidth * this.shelfScopeTabIndex() +
      (itemWidth - BookshelfPage.SCOPE_TAB_INDICATOR_WIDTH) / 2;
  }

  /** 顶部沉浸控件的触摸光晕。 */
  accentGlowColor(): string {
    return `#40${this.accentColor().substring(1)}`;
  }

  @Builder
  shelfHeaderCircleButton(icon: Resource, active: boolean, label: string, onTap: () => void) {
    ImmersiveMaterialSurface({
      surfaceWidth: BookshelfPage.HEADER_CONTROL_SIZE,
      surfaceHeight: BookshelfPage.HEADER_CONTROL_SIZE,
      darkMode: this.appDarkMode,
      fallbackColor: this.cardColor(),
      glowColor: this.accentGlowColor()
    }) {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([active ? this.accentColor() : this.primaryTextColor()])
      }
      .width('100%')
      .height('100%')
      .accessibilityText(label)
      .onClick(() => onTap())
    }
  }

  @Builder
  shelfFilterButton() {
    Row() {
      this.shelfHeaderCircleButton($r('sys.symbol.funnel'),
        this.showShelfFilterMenu || this.shelfFilterKeyList().length > 0, this.shelfFilterAccessibilityText(), () => {
          this.showShelfFilterMenu = !this.showShelfFilterMenu;
          this.shelfFilterMenuPage = '';
          this.showShelfSortMenu = false;
          this.showShelfLayoutMenu = false;
          this.showShelfGroupMenu = false;
        })
    }
    .margin({ right: 10 })
    .bindPopup(this.showShelfFilterMenu, this.shelfMenuPopupOptions((): void => {
      this.shelfFilterDropdown()
    }, Placement.BottomRight, () => {
      this.showShelfFilterMenu = false;
      this.shelfFilterMenuPage = '';
    }))
  }

  shelfFilterAccessibilityText(): string {
    const keys = this.shelfFilterKeyList();
    return keys.length === 0 ? '筛选' :
      `筛选，当前${keys.map((key: string) => this.shelfFilterLabel(key)).join('、')}`;
  }

  @Builder
  shelfFilterDropdown() {
    if (this.shelfFilterMenuPage === 'tag') {
      this.shelfFilterSubpage('标签', SHELF_FILTER_TAG_PREFIX, this.shelfTagFilterOptions(), '当前书架的书没有标签')
    } else if (this.shelfFilterMenuPage === 'origin') {
      this.shelfFilterSubpage('书源', SHELF_FILTER_ORIGIN_PREFIX, this.shelfOriginFilterOptions(), '当前书架没有网络书籍')
    } else {
      this.shelfFilterMainPage()
    }
  }

  @Builder
  shelfFilterMainPage() {
    Column({ space: AppSpacing.XXS }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17)
          .fontColor([this.shelfSearchActive ? this.accentColor() : this.secondaryTextColor()])
        Text('搜索书架')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.shelfSearchActive ? this.accentColor() : this.primaryTextColor())
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([this.secondaryTextColor()])
      }
      .width('100%')
      .height(BookshelfPage.MENU_ITEM_HEIGHT)
      .padding({ left: 12, right: 12 })
      .borderRadius(this.shelfMenuItemRadius())
      .alignItems(VerticalAlign.Center)
      .accessibilityText('搜索书架')
      .onClick(() => this.openShelfSearch())

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.appDarkMode))
        .margin({ top: AppSpacing.XXS, left: 12, right: 12 })

      ForEach(BookshelfPage.FILTER_GROUP_LABELS, (label: string, index: number) => {
        this.filterSectionLabel(label)
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(BookshelfPage.FILTER_GROUPS[index], (key: string) => {
            this.filterChip(key)
          }, (key: string) => key)
        }
        .width('100%')
        .padding({ left: 12, right: 4 })
      }, (label: string) => label)

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.appDarkMode))
        .margin({ left: 12, right: 12 })
      this.filterSubpageEntry('标签', 'tag', SHELF_FILTER_TAG_PREFIX)
      this.filterSubpageEntry('书源', 'origin', SHELF_FILTER_ORIGIN_PREFIX)

      if (this.shelfFilterKeyList().length > 0) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.hairlineColor(this.appDarkMode))
          .margin({ top: AppSpacing.XS, bottom: AppSpacing.XS, left: 12, right: 12 })
        Text('清除筛选')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .height(BookshelfPage.MENU_ITEM_HEIGHT)
          .textAlign(TextAlign.Center)
          .borderRadius(this.shelfMenuItemRadius())
          .onClick(() => this.setShelfFilterKeys([]))
      }
    }
    .width(248)
    .padding(BookshelfPage.MENU_PADDING)
  }

  /** 主页上的“标签 ›”“书源 ›”：右侧显示已选的名字，点进二级页。 */
  @Builder
  filterSubpageEntry(title: string, page: string, prefix: string) {
    Row({ space: AppSpacing.SM }) {
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
      Text(this.shelfFilterSelectedSummary(prefix))
        .fontSize(AppFontSize.BODY)
        .fontColor(this.shelfFilterSelectedSummary(prefix) === '不限' ? this.secondaryTextColor() : this.accentColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([this.secondaryTextColor()])
    }
    .width('100%')
    .height(BookshelfPage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.shelfMenuItemRadius())
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`${title}筛选，${this.shelfFilterSelectedSummary(prefix)}`)
    .onClick(() => {
      this.shelfFilterMenuPage = page;
    })
  }

  @Builder
  shelfFilterSubpage(title: string, prefix: string, options: ShelfFilterOption[], emptyText: string) {
    Column({ space: AppSpacing.XXS }) {
      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(16)
          .fontColor([this.primaryTextColor()])
        Text(title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .height(BookshelfPage.MENU_ITEM_HEIGHT)
      .padding({ left: 12, right: 12 })
      .borderRadius(this.shelfMenuItemRadius())
      .alignItems(VerticalAlign.Center)
      .accessibilityText(`返回筛选，当前为${title}`)
      .onClick(() => {
        this.shelfFilterMenuPage = '';
      })

      if (options.length === 0) {
        Text(emptyText)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: AppSpacing.LG, bottom: AppSpacing.LG })
      } else {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(options, (option: ShelfFilterOption) => {
              this.filterCountChip(option)
            }, (option: ShelfFilterOption) => option.key)
          }
          .width('100%')
          .padding({ left: 12, right: 4, top: AppSpacing.XS })
        }
        .width('100%')
        .constraintSize({ maxHeight: BookshelfPage.FILTER_SUBPAGE_MAX_HEIGHT })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
      }

      if (this.shelfFilterKeysWithPrefix(prefix).length > 0) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.hairlineColor(this.appDarkMode))
          .margin({ top: AppSpacing.XS, bottom: AppSpacing.XS, left: 12, right: 12 })
        Text(`清除${title}筛选`)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .height(BookshelfPage.MENU_ITEM_HEIGHT)
          .textAlign(TextAlign.Center)
          .borderRadius(this.shelfMenuItemRadius())
          .onClick(() => this.setShelfFilterKeys(this.shelfFilterKeyList()
            .filter((key: string) => !key.startsWith(prefix))))
      }
    }
    .width(248)
    .padding(BookshelfPage.MENU_PADDING)
  }

  /** 标签、书源小块：名字后跟本数。 */
  @Builder
  filterCountChip(option: ShelfFilterOption) {
    Text() {
      Span(option.label)
      Span(` ${option.count}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
        .fontWeight(FontWeight.Regular)
    }
    .fontSize(AppFontSize.BODY)
    .fontWeight(this.isShelfFilterSelected(option.key) ? FontWeight.Medium : FontWeight.Regular)
    .fontColor(this.isShelfFilterSelected(option.key) ? this.accentColor() : this.primaryTextColor())
    .maxLines(1)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .constraintSize({ maxWidth: 216 })
    .height(32)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(16)
    .backgroundColor(this.isShelfFilterSelected(option.key) ? this.selectedSoftBackgroundColor() :
      ThemeRuntime.softFillColor(this.appDarkMode))
    .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
    .accessibilityText(`${option.label}，${option.count}本`)
    .accessibilitySelected(this.isShelfFilterSelected(option.key))
    .onClick(() => this.toggleShelfFilter(option.key))
  }

  shelfFilterKeysWithPrefix(prefix: string): string[] {
    return this.shelfFilterKeyList().filter((key: string) => key.startsWith(prefix));
  }

  shelfFilterSelectedSummary(prefix: string): string {
    const keys = this.shelfFilterKeysWithPrefix(prefix);
    return keys.length === 0 ? '不限' : keys.map((key: string) => BookshelfPage.shelfFilterKeyValue(key)).join('、');
  }

  @Builder
  filterSectionLabel(label: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.secondaryTextColor())
      .width('100%')
      .padding({ left: 12, top: AppSpacing.SM, bottom: AppSpacing.XXS })
  }

  /** 多选：点一项切换选中，菜单保持打开。 */
  @Builder
  filterChip(key: string) {
    Text(this.shelfFilterLabel(key))
      .fontSize(AppFontSize.BODY)
      .fontWeight(this.isShelfFilterSelected(key) ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.isShelfFilterSelected(key) ? this.accentColor() : this.primaryTextColor())
      .maxLines(1)
      .height(32)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(16)
      .backgroundColor(this.isShelfFilterSelected(key) ? this.selectedSoftBackgroundColor() :
        ThemeRuntime.softFillColor(this.appDarkMode))
      .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
      .accessibilityText(this.shelfFilterLabel(key))
      .accessibilitySelected(this.isShelfFilterSelected(key))
      .onClick(() => this.toggleShelfFilter(key))
  }

  shelfFilterLabel(key: string): string {
    if (key === 'network') return '网络';
    if (key === 'local') return '本地';
    if (key === 'finished') return '已完结';
    if (key === 'ongoing') return '连载中';
    if (key === 'unread') return '未读';
    if (key === 'reading') return '在读';
    if (key === 'readDone') return '已读完';
    if (key === 'updated') return '有更新';
    if (key === 'read7d') return '一周内';
    if (key === 'read30d') return '一月内';
    if (key === 'stale90d') return '三个月没读';
    return BookshelfPage.shelfFilterKeyValue(key);
  }

  isShelfFilterSelected(key: string): boolean {
    return this.shelfFilterKeyList().indexOf(key) >= 0;
  }

  toggleShelfFilter(key: string): void {
    const keys = this.shelfFilterKeyList();
    const index = keys.indexOf(key);
    if (index >= 0) {
      keys.splice(index, 1);
    } else {
      keys.push(key);
    }
    this.setShelfFilterKeys(keys);
  }

  setShelfFilterKeys(keys: string[]): void {
    const next = BookshelfPage.canonicalShelfFilterKeys(keys).join(',');
    if (next === this.shelfFilterKeys) {
      return;
    }
    this.shelfFilterKeys = next;
    this.applyShelfScope();
    this.reloadShelfDataSources(true);
    this.refreshShelfCoverCache(this.books);
  }

  @Builder
  shelfLayoutButton() {
    Row() {
      this.shelfHeaderCircleButton($r('sys.symbol.square_grid_2x2'), this.showShelfLayoutMenu, '布局切换', () => {
        this.showShelfLayoutMenu = !this.showShelfLayoutMenu;
        this.showShelfSortMenu = false;
        this.showShelfFilterMenu = false;
        this.showShelfGroupMenu = false;
      })
    }
    .bindPopup(this.showShelfLayoutMenu, this.shelfMenuPopupOptions((): void => {
      this.shelfLayoutDropdown()
    }, Placement.BottomRight, () => {
      this.showShelfLayoutMenu = false;
    }))
  }

  shelfMenuPopupOptions(builder: CustomBuilder, placement: Placement, onHidden: () => void): CustomPopupOptions {
    return ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, builder, placement, this.appDarkMode, this.accentColor(), onHidden);
  }

  shelfMenuItemRadius(): number {
    return BookshelfPage.MENU_RADIUS - BookshelfPage.MENU_PADDING;
  }

  @Builder
  shelfLayoutDropdown() {
    Column({ space: AppSpacing.XXS }) {
      this.layoutDropdownItem('紧凑', 'compact', $r('sys.symbol.list_bullet'))
      this.layoutDropdownItem('宽松', 'loose', $r('sys.symbol.bookshelf'))
      this.layoutDropdownItem('平铺', 'tile', $r('sys.symbol.square_grid_2x2'))
    }
    .width(168)
    .padding(BookshelfPage.MENU_PADDING)
  }

  @Builder
  layoutDropdownItem(label: string, mode: string, icon: Resource) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([this.bookshelfLayoutMode === mode ? this.accentColor() : this.secondaryTextColor()])
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.bookshelfLayoutMode === mode ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.bookshelfLayoutMode === mode ? this.accentColor() : this.primaryTextColor())
        .layoutWeight(1)

      if (this.bookshelfLayoutMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(BookshelfPage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.shelfMenuItemRadius())
    .backgroundColor(this.bookshelfLayoutMode === mode ? this.selectedSoftBackgroundColor() : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.applyBookshelfLayoutMode(mode))
  }

  applyBookshelfLayoutMode(mode: string): void {
    const next = mode === 'loose' || mode === 'tile' ? mode : 'compact';
    this.bookshelfLayoutMode = next;
    // The tile data source excludes the expanded recent-read book only in tile mode.
    // Rebuild it immediately when switching layouts so a compact-mode cache entry
    // cannot be rendered alongside the expanded tile card.
    this.reloadShelfDataSources(true);
    this.showShelfLayoutMenu = false;
    this.showShelfFilterMenu = false;
    const settings = BookshelfDisplaySettingsStore.fromStorage();
    settings.layoutMode = next;
    BookshelfDisplaySettingsStore.applyToStorage(settings);
    BookshelfDisplaySettingsStore.save(getContext(this), settings).catch((e: Error) => {
      console.warn('保存书架布局失败:', e);
      HdsFeedback.showToast('布局保存失败');
    });
  }

  @Builder
  shelfSortButton() {
    Row() {
      ImmersiveMaterialSurface({
        surfaceWidth: this.shelfSortButtonWidth(),
        surfaceHeight: BookshelfPage.HEADER_CONTROL_SIZE,
        darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(),
        glowColor: this.accentGlowColor()
      }) {
        Row({ space: 5 }) {
          Text('⇅')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.accentColor())
          Text(this.sortModeLabel())
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.showShelfSortMenu ? this.accentColor() : this.primaryTextColor())
          SymbolGlyph(this.showShelfSortMenu ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([this.secondaryTextColor()])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .accessibilityText(`排序：${this.sortModeLabel()}`)
        .onClick(() => {
          this.showShelfSortMenu = !this.showShelfSortMenu;
          this.showShelfLayoutMenu = false;
          this.showShelfFilterMenu = false;
          this.showShelfGroupMenu = false;
        })
      }
    }
    .margin({ right: 10 })
    .bindPopup(this.showShelfSortMenu && this.books.length > 0, this.shelfMenuPopupOptions((): void => {
      this.shelfSortDropdown()
    }, Placement.BottomRight, () => {
      this.showShelfSortMenu = false;
    }))
  }

  /** 沉浸材质底板要具体宽度：两侧留白 26、⇅ 与箭头各 14、两处间隔 5，加上 2～3 个汉字。 */
  shelfSortButtonWidth(): number {
    return 64 + this.sortModeLabel().length * AppFontSize.BODY;
  }

  @Builder
  shelfSortDropdown() {
    Column({ space: AppSpacing.XXS }) {
      this.sortDropdownItem('新阅读', 'recentRead')
      this.sortDropdownItem('新加入', 'recentAdd')
      this.sortDropdownItem('名称', 'name')
    }
    .width(160)
    .padding(BookshelfPage.MENU_PADDING)
  }

  @Builder
  sortDropdownItem(label: string, mode: string) {
    Row() {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.sortMode === mode ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.sortMode === mode ? this.accentColor() : this.primaryTextColor())
        .layoutWeight(1)

      if (this.sortMode === mode) {
        Text('✓')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.accentColor())
      }
    }
    .width('100%')
    .height(BookshelfPage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.shelfMenuItemRadius())
    .backgroundColor(this.sortMode === mode ? this.selectedSoftBackgroundColor() : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.applyShelfSortMode(mode);
    })
  }

  sortModeLabel(): string {
    if (this.sortMode === 'recentAdd') {
      return '新加入';
    }
    if (this.sortMode === 'name') {
      return '名称';
    }
    return '新阅读';
  }

  selectedSoftBackgroundColor(): string {
    const color = this.accentColor();
    return `#1A${color.substring(1)}`;
  }

  applyShelfSortMode(mode: string): void {
    const next = mode === 'recentAdd' || mode === 'name' ? mode : 'recentRead';
    this.showShelfSortMenu = false;
    if (this.sortMode === next) {
      // Migrate installations that previously kept this value only in AppStorage.
      this.persistShelfSortMode(next);
      if (this.pendingShelfSortTimer >= 0) {
        clearTimeout(this.pendingShelfSortTimer);
        this.pendingShelfSortTimer = -1;
      }
      this.pendingShelfSortMode = '';
      // 'recentRead' is the default and therefore the mode the user re-taps most often. Re-selecting
      // the already-active mode must still visibly re-sort: a silent return made "点了排序没反应" look
      // like the sort itself was broken whenever the retained snapshot was stale for any reason.
      this.reorderShelfForSortMode(next);
      this.scheduleLoadBooks();
      return;
    }
    if (this.shelfScopeSwitchAnimating) {
      this.pendingShelfSortMode = next;
      if (this.pendingShelfSortTimer >= 0) {
        clearTimeout(this.pendingShelfSortTimer);
      }
      this.pendingShelfSortTimer = setTimeout(() => {
        this.pendingShelfSortTimer = -1;
        const pending = this.pendingShelfSortMode;
        this.pendingShelfSortMode = '';
        if (pending) {
          this.applyShelfSortMode(pending);
        }
      }, 280);
      return;
    }
    if (this.pendingShelfSortTimer >= 0) {
      clearTimeout(this.pendingShelfSortTimer);
      this.pendingShelfSortTimer = -1;
    }
    this.pendingShelfSortMode = '';
    this.persistShelfSortMode(next);
    this.reorderShelfForSortMode(next);
    // The synchronous reorder only re-sorts the snapshot the shelf already holds. Follow it with a
    // DB-backed reload so a snapshot that went stale (e.g. a missed progress notification while the
    // shelf was covered by the reader) cannot keep rendering yesterday's order.
    this.scheduleLoadBooks();
  }

  /**
   * Re-derive the visible shelf order for the newly selected sort mode.
   *
   * This deliberately does not go through animateShelfContentUpdate(): that helper drives the
   * scope-switch slide transition, so reusing it for sorting routed a plain reorder through a
   * 115ms delay plus a second animation frame, and re-entrant selections landed in the
   * shelfScopeSwitchAnimating branch instead of applying. A sort is a one-shot content swap,
   * it must be applied synchronously to both rendered layouts (compact/loose list + tile grid).
   */
  private reorderShelfForSortMode(mode: string): void {
    this.sortMode = mode;
    const source = this.booksForShelfScope(this.shelfScope);
    const sorted = this.sortBooks(source, mode);
    this.books = sorted;
    // Both layouts read from their own LazyForEach source, and the tile grid additionally caches
    // its root entries. Invalidate the cache before rebuilding so the tile layout cannot render a
    // stale entry order produced by the previous sort mode.
    this.shelfTileEntriesCacheKey = '';
    this.shelfTileEntriesCache = [];
    this.shelfListBooksSource.replace(sorted, true);
    this.shelfTileBooksSource.replace(this.getTileBooksWithoutLatest(sorted), true);
    this.shelfTileEntriesSource.replace(this.getSortedTileRootEntries(sorted, mode), true);
  }

  private persistShelfSortMode(mode: string): void {
    BookshelfStateStore.saveSortMode(getContext(this), mode).catch((e: Error) => {
      console.warn('保存书架排序设置失败:', e);
    });
  }

  sortBooks(books: Book[], mode: string = this.sortMode): Book[] {
    const sorted = [...books];
    sorted.sort((a: Book, b: Book) => {
      if (a.isPinned !== b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      if (mode === 'recentRead') {
        return BookshelfSortHelper.compareRecentRead(a, b);
      }
      if (mode === 'name') {
        return this.compareBookName(a, b);
      }
      return this.getBookAddTime(b) - this.getBookAddTime(a);
    });
    return sorted;
  }

  compareBookName(a: Book, b: Book): number {
    const nameA = this.normalizeBookName(a.name);
    const nameB = this.normalizeBookName(b.name);
    const nameDiff = nameA.localeCompare(nameB, 'zh-Hans-CN-u-co-pinyin');
    if (nameDiff !== 0) {
      return nameDiff;
    }
    return this.getBookAddTime(b) - this.getBookAddTime(a);
  }

  normalizeBookName(name?: string): string {
    if (!name) {
      return '';
    }
    return name
      .trim()
      .replace(/^[《〈「『“"'(\[【\s]+/g, '')
      .replace(/[》〉」』”"')\]】\s]+$/g, '');
  }

  shelfTileBookDisplayName(book: Book): string {
    const title = (book?.name || '').trim();
    if (title) {
      return title;
    }
    const bookUrl = (book?.bookUrl || '').trim();
    if (!bookUrl) {
      return '未知书名';
    }
    const candidate = bookUrl.split(/[/?#]/).filter((part: string) => part).pop() || '';
    if (!candidate) {
      return '未知书名';
    }
    const rawTitle = (() => {
      try {
        return decodeURIComponent(candidate);
      } catch (_error) {
        return candidate;
      }
    })();
    return rawTitle.replace(/\.[^./\\]*$/, '').trim() || '未知书名';
  }

  getBookAddTime(book: Book): number {
    return BookshelfSortHelper.getBookAddTime(book);
  }

  getBookReadTime(book: Book): number {
    return BookshelfSortHelper.getBookReadTime(book);
  }

  parseBookTime(value: string): number {
    return BookshelfSortHelper.parseBookTime(value);
  }

  getShelfProgressText(book: Book): string {
    if (!book.totalChapterNum || book.totalChapterNum <= 0) {
      return '未读';
    }
    if (!Book.hasStartedReading(book)) {
      return '未读';
    }
    const unread = book.getUnreadChapterNum();
    return unread > 0 ? `${unread}章未读` : '已读完';
  }

  getReadProgressValue(book: Book): number {
    if (!book.totalChapterNum || book.totalChapterNum <= 0) {
      return 0;
    }
    if (!Book.hasStartedReading(book)) {
      return 0;
    }
    const chapterIndex = Math.min(Math.max(book.durChapterIndex, 0), book.totalChapterNum - 1);
    const progressChapterIndex = Number.parseInt(book.getVariable('readProgressChapterIndex'));
    const currentChapterPageCount = Number.parseInt(book.getVariable('readProgressPageCount'));
    let currentChapterProgress = 1;
    if (progressChapterIndex === chapterIndex && currentChapterPageCount > 0) {
      const currentPageNumber = Math.min(Math.max(book.durChapterPos + 1, 1), currentChapterPageCount);
      currentChapterProgress = currentPageNumber / currentChapterPageCount;
    }
    const readChapterCount = Math.min(chapterIndex + currentChapterProgress, book.totalChapterNum);
    return Math.floor(readChapterCount * 1000 / book.totalChapterNum) / 10;
  }

  getReadProgressPercentText(book: Book): string {
    const progress = this.getReadProgressValue(book);
    if (progress <= 0) {
      return '已读0%';
    }
    if (progress >= 100) {
      return '已读100%';
    }
    return progress % 1 === 0 ? `已读${progress.toFixed(0)}%` : `已读${progress.toFixed(1)}%`;
  }

  getLastReadTimeText(book: Book): string {
    const readTime = this.getBookReadTime(book);
    if (readTime <= 0) {
      return '未读';
    }
    return this.formatShelfTime(readTime);
  }

  formatShelfTime(time: number): string {
    const date = new Date(time);
    if (Number.isNaN(date.getTime())) {
      return '未知';
    }
    const now = new Date();
    const dateStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const nowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const dayDiff = Math.floor((nowStart - dateStart) / 86400000);
    const timeText = `${this.padTime(date.getHours())}:${this.padTime(date.getMinutes())}`;
    if (dayDiff === 0) {
      return `今天 ${timeText}`;
    }
    if (dayDiff === 1) {
      return `昨天 ${timeText}`;
    }
    if (date.getFullYear() === now.getFullYear()) {
      return `${date.getMonth() + 1}-${this.padTime(date.getDate())} ${timeText}`;
    }
    return `${date.getFullYear()}-${this.padTime(date.getMonth() + 1)}-${this.padTime(date.getDate())} ${timeText}`;
  }

  padTime(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  @Builder
  readProgressPanel(book: Book) {
    Column({ space: AppSpacing.XS }) {
      Text(this.getReadProgressInfoText(book))
        .fontSize(AppFontSize.CAPTION)
        // 行高固定，shelfProgressPanelHeight() 才能算出与封面一致的高度。
        .lineHeight(this.shelfSmallTextLineHeight())
        .fontColor(this.subTextColor())
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .color(this.accentColor())
        .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')
    }
    .width('100%')
  }

  @Builder
  looseReadProgressPanel(book: Book) {
    Column({ space: AppSpacing.XS }) {
      Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .color(this.accentColor())
        .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')

      Text(this.getReadProgressInfoText(book))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  getReadProgressInfoText(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return '未读';
    }
    const parts: string[] = [this.getReadProgressPercentText(book)];
    if (this.bookshelfShowLastReadTime) {
      parts.push(this.getLastReadTimeText(book));
    }
    if (this.bookshelfShowLastReadChapter) {
      const chapterText = this.getReadChapterText(book);
      if (chapterText) {
        parts.push(chapterText);
      }
    }
    return parts.join(' · ');
  }

  getReadChapterText(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return '';
    }
    return (book.durChapterTitle || '').trim();
  }

  getLastReadChapterText(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return '尚未阅读';
    }
    const chapterNumber = book.durChapterIndex >= 0 ? book.durChapterIndex + 1 : -1;
    const chapterTitle = this.getReadChapterText(book);
    if (chapterNumber > 0 && chapterTitle) {
      return `第${chapterNumber}章 · ${chapterTitle}`;
    }
    if (chapterNumber > 0) {
      return `第${chapterNumber}章`;
    }
    return chapterTitle || '尚未记录章节';
  }

  getLastReadChapterNumberText(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return '尚未阅读';
    }
    return book.durChapterIndex >= 0 ? `第${book.durChapterIndex + 1}章` : '章节号未知';
  }

  getLastReadChapterNameText(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return '尚未记录章节';
    }
    const originalTitle = this.getReadChapterText(book).replace(/\s+/g, ' ').trim();
    if (!originalTitle) {
      return '章节名未知';
    }
    let title = originalTitle;
    const chineseChapterPrefix =
      /^第\s*[0-9０-９零〇○一二三四五六七八九十百千万亿两壹贰叁肆伍陆柒捌玖拾佰仟]+\s*(?:章|回|节|話|话|集|篇|幕)\s*(?:[·•:：、.．\-—]+\s*)?/;
    const englishChapterPrefix =
      /^(?:chapter|chap\.?|ch\.?)\s*[0-9０-９]+\s*(?:[·•:：、.．\-—]+\s*)?/i;
    // Some sources return duplicated prefixes such as “第233章 第233章 寒山奇石”.
    // Strip at most a few leading ordinals while preserving the stored chapter title itself.
    for (let index = 0; index < 3; index++) {
      const stripped = title.replace(chineseChapterPrefix, '').replace(englishChapterPrefix, '').trim();
      if (stripped === title) break;
      title = stripped;
      if (!title) break;
    }
    return title || '章节名未知';
  }

  getLastReadPagePreviewText(book: Book): string {
    const text = book.getVariable('lastReadPageText').trim();
    return text || '再次阅读后，将在这里显示上次阅读页的正文内容。';
  }

  getLastReadPageNumberText(book: Book): string {
    const pageCount = Number.parseInt(book.getVariable('readProgressPageCount'));
    const pageNumber = Math.max(1, book.durChapterPos + 1);
    return pageCount > 0 ? `${Math.min(pageNumber, pageCount)}/${pageCount}` : `${pageNumber}`;
  }

  getLastReadLeafContentMode(book: Book): string {
    if (this.bookshelfLastReadLeafMode === 'bookInfo' || this.bookshelfLastReadLeafMode === 'contentPreview') {
      return this.bookshelfLastReadLeafMode;
    }
    // 有声与视频没有可预览的正文。
    if (BookTypeSupport.isAudio(book) || BookTypeSupport.isVideo(book)) {
      return 'bookInfo';
    }
    if (this.isShelfComicBook(book) && this.getLastReadPageImage(book)) {
      return 'comicPreview';
    }
    return 'contentPreview';
  }

  isShelfComicBook(book: Book): boolean {
    if (book.origin === 'local') {
      return BookTypeSupport.isImage(book);
    }
    return BookTypeSupport.isImage(book) || book.getVariable('readerComicManualMode') === 'comic' ||
      book.getVariable('readerComicAutoDetected') === '1' || book.getVariable('readerComicMode') === '1';
  }

  getLastReadPageImage(book: Book): string {
    const source = book.getVariable('lastReadPageImage').trim();
    if (!source || /^(?:https?:|data:|file:)/i.test(source)) {
      return source;
    }
    try {
      return fileUri.getUriFromPath(source);
    } catch (_) {
      return source;
    }
  }

  @Builder
  shelfLastReadLeaf(book: Book) {
    if (this.getLastReadLeafContentMode(book) === 'bookInfo') {
      this.shelfLastReadBookInfo(book)
    } else if (this.getLastReadLeafContentMode(book) === 'comicPreview') {
      Image(this.getLastReadPageImage(book))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .draggable(false)
    } else {
      Text(this.getLastReadPagePreviewText(book))
        .width('100%')
        .layoutWeight(1)
        .fontSize(4.8)
        .lineHeight(7.5)
        .fontColor(this.shelfTilePageTextColor())
        .textAlign(TextAlign.JUSTIFY)
        .wordBreak(WordBreak.BREAK_WORD)
        .maxLines(16)
        .textOverflow({ overflow: TextOverflow.Clip })
        .margin({ top: AppSpacing.XS })

      Text(this.getLastReadPageNumberText(book))
        .width('100%')
        .fontSize(5)
        .fontColor(this.shelfTilePageSubTextColor())
        .textAlign(TextAlign.End)
    }
  }

  @Builder
  shelfLastReadBookInfo(book: Book) {
    Column() {
      Text(this.shelfTileBookDisplayName(book))
        .width('100%')
        .fontSize(AppFontSize.MICRO)
        .lineHeight(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.shelfTilePageTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text((book.author || '').trim() || '作者未知')
        .width('100%')
        .fontSize(7)
        .lineHeight(10)
        .fontColor(this.shelfTilePageSubTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 5 })

      Blank()
        .layoutWeight(1)

      Text(this.getLastReadChapterNumberText(book))
        .width('100%')
        .fontSize(8)
        .lineHeight(11)
        .fontColor(this.shelfTilePageTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.getLastReadChapterNameText(book))
        .width('100%')
        .fontSize(8)
        .lineHeight(11)
        .fontColor(this.shelfTilePageTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 1 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  shelfTilePageColor(): string {
    return this.appDarkMode ? '#242321' : '#F8F4E9';
  }

  shelfTilePageTextColor(): string {
    return this.appDarkMode ? '#D8D3C8' : '#3E3A33';
  }

  shelfTilePageSubTextColor(): string {
    return this.appDarkMode ? '#8F8A82' : '#8A8378';
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

  glassCardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  glassShadowColor(): string {
    return '#00000000';
  }

  sourceTagBackgroundColor(): string {
    return this.selectedSoftBackgroundColor();
  }

  sourceTagTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : this.accentColor();
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

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }
}
