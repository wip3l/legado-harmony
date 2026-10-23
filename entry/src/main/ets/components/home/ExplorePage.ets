import { router } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { Book, BookSource, SearchBook, BookFieldSanitizer } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import {
  ExploreCoordinator,
  ExploreEntry,
  ExploreFilterGroup,
  ExploreSourceOption
} from '../../core/book/ExploreCoordinator';
import { SearchBookResultList } from '../../components/book/SearchBookResultList';
import { ImmersiveMaterialSurface } from '../../components/ImmersiveMaterialSurface';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { CollapsingHeader } from '../../utils/CollapsingHeader';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';
import { SearchExploreSettingsStore } from '../../utils/SearchExploreSettingsStore';
import { ExploreCategoryHistoryStore } from '../../utils/ExploreCategoryHistoryStore';
import { ExploreCategoryItem, ExploreCategorySheet } from './ExploreCategorySheet';
import { ExploreCacheHit, ExploreResultCache } from '../../utils/ExploreResultCache';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { WebBookService } from '../../core/book/WebBookService';
import { SourceActionKind, SourceActionMenuList, SourceActionRunner, SourceDeleteConfirm, SourceDeleteDialogParams,
  SourceGroupTag, SourcePickerKit, SourcePickerSearchField, SourceVariableDialogParams, SourceVariableEditor
} from './SourcePickerKit';
import { CoverUrlNormalizer } from '../../utils/CoverUrlNormalizer';
import { ExploreSourceOptionDataSource, ExploreMetadataTask } from '../../core/book/ShelfDataSources';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/** 首页"发现"页签：发现源、筛选条件与结果列表。 */
@Component
export struct ExplorePage {
  /** 顶部书源标签、筛选与刷新按钮的高度。 */
  static readonly HEADER_CONTROL_SIZE: number = 40;
  /** 标题下方频道栏的高度。 */
  static readonly CHANNEL_BAR_HEIGHT: number = 44;
  static readonly MENU_ITEM_HEIGHT: number = 44;
  /** 分类达到这个数量才在频道栏右端显示“全部分类”按钮，少量分类横滑就能看完。 */
  static readonly CATEGORY_SHEET_MIN_COUNT: number = 6;
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Prop @Watch('onActiveChanged') isActive: boolean = false;
  @State entries: ExploreEntry[] = [];
  @State sourceOptions: ExploreSourceOption[] = [];
  private exploreSourceDataSource: ExploreSourceOptionDataSource = new ExploreSourceOptionDataSource();
  @State exploreSourceGroups: string[] = [];
  @State activeExploreSourceGroup: string = '__all__';
  @State platformNames: string[] = [];
  @State exploreFilters: ExploreFilterGroup[] = [];
  @State exploreFilterDrafts: ExploreFilterGroup[] = [];
  @State showExploreFilterPanel: boolean = false;
  @State sourceNames: string[] = [];
  @State selectedSourceName: string = '';
  @State selectedIndex: number = 0;
  @State showExploreSourcePicker: boolean = false;
  /** 频道栏左侧“模式”的下拉。 */
  @State showExplorePlatformMenu: boolean = false;
  @State showExploreCategorySheet: boolean = false;
  /** 频道栏的实际宽度：沉浸材质底板需要具体数值。 */
  @State exploreChannelBarWidth: number = 0;
  @State showExploreSourceActionMenu: boolean = false;
  @State actionExploreSourceUrl: string = '';
  @State actionExploreSourceNative: boolean = false;
  /** 书源地址到显示名（同名书源补地址）的对照，书源列表加载时重算。 */
  private exploreSourceDisplayNames: Map<string, string> = new Map<string, string>();
  @State exploreContextMenuX: number = 16;
  @State exploreContextMenuY: number = 96;
  @State exploreSourceFilterInput: string = '';
  @State exploreSourceFilterKeyword: string = '';
  @State exploreViewportWidth: number = 360;
  @State exploreViewportHeight: number = 720;
  @State books: SearchBook[] = [];
  @State shelfBookKeys: string[] = [];
  @State addingShelfBookKeys: string[] = [];
  @State isLoading: boolean = false;
  @State isLoadingMore: boolean = false;
  @State hasMoreExploreBooks: boolean = true;
  @State status: string = '';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '';
  @StorageLink('explorePlatform') selectedPlatform: string = '';
  /** 结果布局：'list' 卡片列表，'grid' 封面平铺（列数随宽度自适应）；持久保存。 */
  @StorageLink('exploreResultLayout') exploreResultLayout: string = 'list';
  @StorageLink('exploreSourceUrl') selectedSourceUrl: string = '';
  @StorageLink('bookSourceExploreRefreshNonce') @Watch('onExploreRefreshRequested')
  bookSourceExploreRefreshNonce: number = 0;
  @StorageProp('exploreSourceCacheRevision') @Watch('onExploreSourceCacheInvalidated')
  exploreSourceCacheRevision: number = 0;
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('bookSourceOrderRevision') @Watch('onBookSourceOrderChanged') bookSourceOrderRevision: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreShowResultCoverBackground') searchExploreShowResultCoverBackground: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  private coordinator: ExploreCoordinator = new ExploreCoordinator();
  private exploreSourceScroller: Scroller = new Scroller();
  private exploreChannelScroller: Scroller = new Scroller();
  /** 标题行收起量，0 为完整显示，CollapsingHeader.DISTANCE 为完全收起。 */
  @State exploreHeaderCollapse: number = 0;
  onHeaderCollapseChange: (progress: number) => void = () => {};
  private hasLoaded: boolean = false;
  private hasRestoredExploreSelection: boolean = false;
  private shelfStatusVersion: number = 0;
  private exploreLoadVersion: number = 0;
  private exploreContentLoadedAt: number = 0;
  private explorePage: number = 1;
  private exploreMetadataQueue: ExploreMetadataTask[] = [];
  private exploreMetadataQueued: Set<string> = new Set<string>();
  private exploreMetadataInFlight: Set<string> = new Set<string>();
  private exploreMetadataUnavailable: Set<string> = new Set<string>();
  private exploreMetadataActive: number = 0;

  aboutToAppear() {
    if (this.isActive) {
      this.ensureLoaded();
    }
  }

  onActiveChanged(): void {
    if (this.isActive) {
      this.ensureLoaded();
    } else {
      this.closeExploreFilterPanel();
      this.showExplorePlatformMenu = false;
      if (this.showExploreSourcePicker) {
        this.showExploreSourcePicker = false;
        this.clearExploreSourceFilter();
      }
      this.closeExploreSourceActions();
      SourceActionRunner.closeVariableEditor(this.getUIContext());
    }
  }

  ensureLoaded(): void {
    if ((!this.hasLoaded || !ExploreResultCache.isFresh(this.exploreContentLoadedAt)) && !this.isLoading) {
      this.loadEntries();
    }
  }

  onShelfChanged(): void {
    this.syncExploreShelfStatus(this.books);
  }

  onBookSourceOrderChanged(): void {
    if (this.isActive && this.hasLoaded && !this.isLoading) {
      this.loadEntries();
    } else if (this.hasLoaded) {
      // 页面常驻但不在前台：标记过期，下次切回发现页时按新顺序重新加载书源列表。
      this.exploreContentLoadedAt = 0;
    }
  }

  onExploreRefreshRequested(): void {
    if (this.bookSourceExploreRefreshNonce <= 0) return;
    const sourceUrl = AppStorage.get<string>('bookSourceExploreRefreshSourceUrl') || '';
    if (sourceUrl) this.selectedSourceUrl = sourceUrl;
    this.exploreContentLoadedAt = 0;
    this.coordinator.clearExploreMenuCache();
    if (this.isActive && !this.isLoading) {
      this.loadEntries('', true);
    }
  }

  onExploreSourceCacheInvalidated(): void {
    // 书源在书源管理中被删除、导入或编辑：已加载的分类和列表不再可信，下次进入发现页时重新加载。
    this.exploreContentLoadedAt = 0;
    this.coordinator.clearExploreMenuCache();
    if (this.isActive && this.hasLoaded) {
      this.loadEntries();
    }
  }

  async loadEntries(platformOverride: string = '', forceRefresh: boolean = false) {
    const loadVersion = this.beginExploreLoad();
    const previousActiveEntries = this.getActiveEntries();
    const previousEntry = previousActiveEntries.length > 0 ?
      previousActiveEntries[Math.min(this.selectedIndex, previousActiveEntries.length - 1)] : null;
    const previousEntryKey = previousEntry ? `${previousEntry.title}\n${previousEntry.url}` : '';
    this.hasLoaded = true;
    this.exploreContentLoadedAt = 0;
    this.status = '正在加载发现分类...';
    this.verificationUrl = '';
    this.verificationTitle = '';
    try {
      if (!this.hasRestoredExploreSelection) {
        this.hasRestoredExploreSelection = true;
        await this.restoreExploreSelectionFromSettings();
        if (!this.isCurrentExploreLoad(loadVersion)) return;
      }
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      const previousSourceName = this.selectedSourceName;
      const previousSourceUrl = this.selectedSourceUrl;
      const sourceOptions = await this.coordinator.getExploreSources();
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      // 数据库查询已经按书源管理中的 customOrder 排序，同时只会返回已启用的书源。
      this.sourceOptions = sourceOptions;
      this.rebuildExploreSourceDisplayNames(sourceOptions);
      this.exploreSourceGroups = this.buildExploreSourceGroups();
      if (this.activeExploreSourceGroup !== '__all__' &&
        !this.exploreSourceGroups.includes(this.activeExploreSourceGroup)) {
        this.activeExploreSourceGroup = '__all__';
      }
      this.sourceNames = this.sourceOptions.map((option: ExploreSourceOption) => option.sourceName);
      this.refreshExploreSourceDataSource();
      const restoredOption = this.sourceOptions.find((option: ExploreSourceOption) =>
        option.sourceUrl === previousSourceUrl) ||
        this.sourceOptions.find((option: ExploreSourceOption) => option.sourceName === previousSourceName) ||
        (this.sourceOptions.length > 0 ? this.sourceOptions[0] : null);
      this.selectedSourceName = restoredOption ? restoredOption.sourceName : '';
      this.selectedSourceUrl = restoredOption ? restoredOption.sourceUrl : '';
      this.platformNames = this.getSelectedSourcePlatforms();
      if (platformOverride && this.platformNames.includes(platformOverride)) {
        this.selectedPlatform = platformOverride;
      }
      this.normalizeSelectedPlatform();
      const entries = await this.coordinator.getEntries(
        this.platformNames.length > 0 ? this.selectedPlatform : '', this.getSelectedSourceUrl());
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      this.entries = entries;
      const dynamicPlatforms = this.coordinator.getDiscoveredPlatforms(this.selectedSourceUrl);
      const inferredGroups = this.getEntryGroupNames(entries);
      const activeOption = this.getSelectedSourceOption();
      this.exploreFilters = this.coordinator.getDiscoveredFilters(this.selectedSourceUrl);
      if (activeOption && this.exploreFilters.length > 0) {
        activeOption.platforms = [];
      } else if (activeOption && dynamicPlatforms.length > 0) {
        activeOption.platforms = dynamicPlatforms;
      } else if (activeOption && activeOption.platforms.length === 0 && inferredGroups.length > 1) {
        activeOption.platforms = inferredGroups;
      }
      this.platformNames = this.getSelectedSourcePlatforms();
      this.normalizeSelectedPlatform();
      if (this.entries.length > 0) {
        // Keep the group that was visible before refresh. Resetting to index 0 made a refresh
        // from (for example) “玄幻” reload the first group and leave the visible group stale.
        const refreshedActiveEntries = this.getActiveEntries();
        let restoredIndex = previousEntryKey ? refreshedActiveEntries.findIndex((entry: ExploreEntry): boolean =>
          `${entry.title}\n${entry.url}` === previousEntryKey) : -1;
        if (restoredIndex < 0 && !previousEntryKey) {
          // 首次进入或刚切换到这个书源：回到上次在该书源停留的分类。
          await ExploreCategoryHistoryStore.load(getContext(this));
          if (!this.isCurrentExploreLoad(loadVersion)) return;
          const lastKey = ExploreCategoryHistoryStore.last(this.selectedSourceUrl);
          restoredIndex = lastKey ? refreshedActiveEntries.findIndex((entry: ExploreEntry): boolean =>
            ExploreCategoryHistoryStore.entryKey(entry.title, entry.url) === lastKey) : -1;
        }
        this.selectedIndex = restoredIndex >= 0 ? restoredIndex : 0;
        if (this.selectedIndex > 0) {
          this.scrollExploreChannelToSelected();
        }
        await this.loadBooks(loadVersion, forceRefresh);
      } else {
        this.books = [];
        this.status = this.coordinator.getNoticeMessage() ||
          `${this.getSelectedSiteLabel()} 暂无可用发现分类`;
      }
    } catch (e) {
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      console.error('加载发现失败:', e);
      this.status = '发现加载失败';
    } finally {
      this.finishExploreLoad(loadVersion);
    }
  }

  async loadBooks(loadVersion?: number, forceRefresh: boolean = false) {
    const currentLoadVersion = loadVersion ?? this.beginExploreLoad();
    this.exploreContentLoadedAt = 0;
    this.explorePage = 1;
    this.hasMoreExploreBooks = true;
    this.isLoadingMore = false;
    const activeEntries = this.getActiveEntries();
    if (activeEntries.length === 0) {
      this.finishExploreLoad(currentLoadVersion);
      return;
    }
    this.status = '';
    this.verificationUrl = '';
    this.verificationTitle = '';
    try {
      const entry = activeEntries[Math.min(this.selectedIndex, activeEntries.length - 1)];
      if (forceRefresh) {
        // A manual refresh must not leave a failed request able to resurrect stale discovery
        // results on the next normal load. Clear the source cache before requesting new data.
        this.coordinator.clearExploreMenuCache();
        await ExploreResultCache.clearSource(getContext(this), entry.sourceUrl);
      }
      if (!forceRefresh) {
        try {
          const cached: ExploreCacheHit | null = await ExploreResultCache.load(
            getContext(this), entry.sourceUrl, this.selectedPlatform, entry.title, entry.url);
          if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
          if (cached) {
            this.exploreContentLoadedAt = cached.updatedAt;
            this.explorePage = cached.pageCount;
            this.hasMoreExploreBooks = cached.hasMore;
            await this.applyExploreBooks(cached.books, entry, currentLoadVersion, true);
            return;
          }
        } catch (cacheError) {
          console.warn('读取发现内容缓存失败，改用网络加载:', cacheError);
        }
      }
      const books = await this.coordinator.explore(entry, 1);
      if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
      this.hasMoreExploreBooks = books.length > 0;
      await this.applyExploreBooks(books, entry, currentLoadVersion, false);
      if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
      if (books.length > 0) {
        this.exploreContentLoadedAt = Date.now();
        try {
          await ExploreResultCache.save(getContext(this), entry.sourceUrl, this.selectedPlatform,
            entry.title, entry.url, books, this.explorePage, this.hasMoreExploreBooks);
        } catch (cacheError) {
          console.warn('保存发现内容缓存失败:', cacheError);
        }
      }
    } catch (e) {
      if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
      console.error('获取发现内容失败:', e);
      this.status = '发现内容获取失败';
    } finally {
      this.finishExploreLoad(currentLoadVersion);
    }
  }

  async loadMoreExploreBooks(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || !this.hasMoreExploreBooks || this.books.length === 0) return;
    const activeEntries = this.getActiveEntries();
    if (activeEntries.length === 0) return;
    const entry = activeEntries[Math.min(this.selectedIndex, activeEntries.length - 1)];
    const loadVersion = this.exploreLoadVersion;
    const nextPage = this.explorePage + 1;
    this.isLoadingMore = true;
    try {
      const nextBooks = await this.coordinator.explore(entry, nextPage);
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      const merged = this.mergeExploreBooks(this.books, nextBooks);
      const addedCount = merged.length - this.books.length;
      if (nextBooks.length === 0 || addedCount === 0) {
        const notice = this.coordinator.getNoticeMessage();
        // Network/verification failures should remain retryable; a genuinely empty or duplicate
        // next page means the source has reached its end (or does not implement pagination).
        this.hasMoreExploreBooks = nextBooks.length === 0 && this.isRetryableExploreNotice(notice);
        this.status = notice || `${this.getSelectedSiteLabel()} · ${entry.sourceName} · ${entry.title} · 已加载全部`;
      } else {
        this.books = merged;
        this.explorePage = nextPage;
        this.status = `${this.getSelectedSiteLabel()} · ${entry.sourceName} · ${entry.title} · ${this.books.length} 本`;
        await this.syncExploreShelfStatus(this.books);
      }
      this.exploreContentLoadedAt = Date.now();
      await ExploreResultCache.save(getContext(this), entry.sourceUrl, this.selectedPlatform,
        entry.title, entry.url, this.books, this.explorePage, this.hasMoreExploreBooks);
    } catch (e) {
      if (this.isCurrentExploreLoad(loadVersion)) {
        console.error('加载更多发现内容失败:', e);
        this.status = '加载更多发现内容失败，可继续上滑重试';
      }
    } finally {
      if (this.isCurrentExploreLoad(loadVersion)) this.isLoadingMore = false;
    }
  }

  mergeExploreBooks(current: SearchBook[], incoming: SearchBook[]): SearchBook[] {
    const merged = current.slice();
    for (const book of incoming) {
      if (!merged.some((item: SearchBook): boolean =>
        item.origin === book.origin && item.bookUrl === book.bookUrl)) {
        merged.push(book);
      }
    }
    return merged;
  }

  isRetryableExploreNotice(notice: string): boolean {
    return /请求失败|网络|超时|timeout|HTTP|网页验证|需要验证|接口返回空响应/i.test(notice || '');
  }

  shouldOfferExploreSourceLogin(): boolean {
    return !!this.selectedSourceUrl &&
      /请先登[录陆]|需要登[录陆]|未登[录陆]|令牌|token|无权限|登录设备数已达上限|设备管理/i.test(this.status || '');
  }

  exploreSourceLoginButtonLabel(): string {
    return /登录设备数已达上限|设备管理/i.test(this.status || '') ? '管理登录设备' : '登录书源';
  }

  openExploreSourceLogin(): void {
    if (!this.selectedSourceUrl) return;
    router.pushUrl({
      url: 'pages/BookSource',
      params: {
        openLoginSourceUrl: this.selectedSourceUrl
      }
    });
  }

  async applyExploreBooks(books: SearchBook[], entry: ExploreEntry, loadVersion: number,
    fromCache: boolean): Promise<void> {
    this.books = books;
    const shelfStatusVersion = this.shelfStatusVersion;
    const shelfKeys = await this.loadExploreShelfKeys(books);
    if (!this.isCurrentExploreLoad(loadVersion)) return;
    if (shelfStatusVersion === this.shelfStatusVersion) {
      this.shelfBookKeys = shelfKeys;
    }
    if (fromCache) {
      this.verificationUrl = '';
      this.verificationTitle = '';
    } else {
      this.verificationUrl = AppStorage.get<string>('pendingVerificationUrl') || '';
      this.verificationTitle = AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
    }
    this.status = this.books.length > 0 ?
      `${this.getSelectedSiteLabel()} · ${entry.sourceName} · ${entry.title} · ${this.books.length} 本${fromCache ? ' · 缓存' : ''}` :
      (this.verificationUrl ? `${entry.sourceName} 可能需要网页验证` :
        (this.coordinator.getNoticeMessage() || `${this.getSelectedSiteLabel()} 当前分类暂无结果`));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Column() {
          // 列表上滑时标题行收起：外层按收起量变矮并裁剪，标题行贴底上移并淡出。
          Stack({ alignContent: Alignment.Bottom }) {
            Row() {
              Text('发现')
                .fontSize(AppFontSize.DISPLAY)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .flexShrink(0)

              Blank()

              this.exploreSourceLabel()

              if (this.exploreFilters.length > 0) {
                this.exploreFilterButton()
              }

              Row() {
                // 显式分支重建按钮，避免嵌套 Builder 按值参数保留旧图标和提示。
                if (this.exploreResultLayout === 'grid') {
                  this.exploreHeaderCircleButton($r('sys.symbol.list_bullet'), false,
                    '当前为平铺，切换为列表', () => {
                      this.applyResultLayout('list');
                    })
                } else {
                  this.exploreHeaderCircleButton($r('sys.symbol.square_grid_2x2'), false,
                    '当前为列表，切换为平铺', () => {
                      this.applyResultLayout('grid');
                    })
                }
              }
              .margin({ right: 10 })

              this.exploreHeaderCircleButton($r('sys.symbol.arrow_clockwise'), false, '刷新发现内容', () => {
                this.loadEntries('', true);
              })
            }
            .width('100%')
            .height(56 + this.statusBarHeight)
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: this.statusBarHeight })
            .alignItems(VerticalAlign.Center)
            .opacity(CollapsingHeader.contentOpacity(this.exploreHeaderCollapseValue()))
            .hitTestBehavior(CollapsingHeader.acceptsTouch(this.exploreHeaderCollapseValue()) ? HitTestMode.Default : HitTestMode.None)
          }
          .width('100%')
          .height(56 + this.statusBarHeight - this.exploreHeaderCollapseValue())
          .clip(true)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.onHeaderCollapseChange((56 + this.statusBarHeight - Number(newArea.height)) /
              CollapsingHeader.DISTANCE);
          })

          if (this.showsExploreChannelBar()) {
            this.exploreChannelBar()
          }

          if (this.shouldShowExploreStatus()) {
            Row() {
              Text(this.status)
                .fontSize(AppFontSize.BODY)
                .fontColor(this.secondaryTextColor())
                .layoutWeight(1)

              if (this.verificationUrl) {
                Button('去验证')
                  .height(28)
                  .fontSize(AppFontSize.CAPTION)
                  .borderRadius(14)
                  .backgroundColor(this.buttonColor())
                  .fontColor(ThemeRuntime.onAccentColor())
                  .margin({ left: AppSpacing.LG })
                  .onClick(() => {
                    this.openVerification();
                  })
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
            .alignItems(VerticalAlign.Center)
          }
        }
        .width('100%')
        .position({ x: 0, y: 0 })
        .zIndex(4)

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('加载中...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .margin({ top: AppSpacing.MD })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ top: this.exploreTopOverlayHeight() })
        .justifyContent(FlexAlign.Center)
      } else if (this.books.length > 0) {
        SearchBookResultList({
          books: this.books,
          layoutMode: this.exploreResultLayout,
          shelfBookKeys: this.shelfBookKeys,
          busyBookKeys: this.addingShelfBookKeys,
          showLoadingMore: this.isLoadingMore,
          showKind: true,
          showResultCover: this.searchExploreShowResultCover,
          showResultCoverBackground: this.searchExploreShowResultCoverBackground,
          useBookshelfCoverGallery: this.searchExploreUseBookshelfCoverGallery,
          showResultTags: this.searchExploreShowResultTags,
          showSourceLine: false,
          pageColor: this.pageColor(),
          cardColor: this.glassCardColor(),
          itemBorderColor: this.glassBorderColor(),
          itemBorderWidth: 1,
          shadowColor: this.glassShadowColor(),
          primaryTextColor: this.primaryTextColor(),
          secondaryTextColor: this.secondaryTextColor(),
          subTextColor: this.subTextColor(),
          topPadding: this.exploreTopOverlayHeight(),
          bottomPadding: this.resultListBottomInset(),
          onOpenBook: (book: SearchBook) => {
            this.openSearchBookDetail(book);
          },
          onReadBook: (book: SearchBook) => {
            this.readSearchBook(book);
          },
          onToggleShelf: (book: SearchBook) => {
            this.toggleSearchBookShelf(book);
          },
          onNeedMetadata: (book: SearchBook) => {
            this.requestExploreMetadata(book);
          },
          onReachEnd: () => {
            this.loadMoreExploreBooks();
          },
          onListScroll: (delta: number, offset: number) => {
            this.onExploreListScroll(delta, offset);
          },
          onListScrollStop: (offset: number) => {
            this.onExploreListScrollStop(offset);
          }
        })
      } else {
        Column() {
          Text('没有发现内容')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.subTextColor())
          Text(this.verificationUrl ? '当前书源可能需要网页验证' : '请切换书源或网站，或检查已启用书源的发现地址')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .margin({ top: AppSpacing.MD })
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32 })
          if (this.verificationUrl) {
            Button('去验证')
              .height(36)
              .fontSize(AppFontSize.BODY)
              .borderRadius(18)
              .margin({ top: AppSpacing.LG })
              .backgroundColor(this.buttonColor())
              .fontColor(ThemeRuntime.onAccentColor())
              .onClick(() => {
                this.openVerification();
              })
          }
          if (this.shouldOfferExploreSourceLogin()) {
            Button(this.exploreSourceLoginButtonLabel())
              .height(36)
              .fontSize(AppFontSize.BODY)
              .borderRadius(18)
              .margin({ top: AppSpacing.LG })
              .backgroundColor(this.buttonColor())
              .fontColor(ThemeRuntime.onAccentColor())
              .onClick(() => {
                this.openExploreSourceLogin();
              })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ top: this.exploreTopOverlayHeight() })
        .justifyContent(FlexAlign.Center)
      }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      if (this.showExploreSourceActionMenu) {
        this.exploreSourceActionMenu()
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = typeof newValue.width === 'number' ? newValue.width : Number.parseFloat(`${newValue.width}`);
      if (Number.isFinite(width) && width > 0) {
        this.exploreViewportWidth = width;
      }
      const height = typeof newValue.height === 'number' ? newValue.height : Number.parseFloat(`${newValue.height}`);
      if (Number.isFinite(height) && height > 0) {
        this.exploreViewportHeight = height;
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showExploreCategorySheet, this.exploreCategorySheet(), this.exploreCategorySheetOptions())
  }

  /** 全部分类面板：与详情页目录同一种半模态，停 60% 与全屏两档。 */
  exploreCategorySheetOptions(): SheetOptions {
    const material = ImmersiveMaterialRuntime.sheetMaterial(this.accentColor());
    const options: SheetOptions = {
      detents: ['60%', SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onDisappear: () => {
        this.showExploreCategorySheet = false;
      }
    };
    if (material !== undefined) {
      options.backgroundColor = Color.Transparent;
      options.systemMaterial = material;
    } else {
      options.blurStyle = BlurStyle.COMPONENT_THICK;
      options.backgroundColor = ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel');
    }
    return options;
  }

  @Builder
  exploreCategorySheet() {
    ExploreCategorySheet({
      items: this.exploreCategoryItems(),
      recentKeys: ExploreCategoryHistoryStore.recent(this.selectedSourceUrl),
      selectedKey: this.currentExploreEntryKey(),
      onSelect: (key: string): void => {
        this.selectExploreCategory(key);
      },
      onClose: (): void => {
        this.showExploreCategorySheet = false;
      }
    })
  }

  openSearchBookDetail(book: SearchBook, autoStartRead: boolean = false) {
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
        coverUrl: book.coverUrl,
        intro: book.intro,
        latestChapterTitle: book.latestChapterTitle,
        updateTime: book.updateTime,
        wordCount: book.wordCount,
        type: String(book.type || 0),
        variable: book.variable || '',
        promptAddToShelfOnBack: !autoStartRead && this.searchExplorePromptAddToShelfOnBack ? 'true' : 'false',
        autoStartRead: autoStartRead ? 'true' : 'false'
      }
    });
  }

  /** 书源选择弹出层：顶部搜索框，下面是分组小标签和书源列表；长按书源打开操作菜单。 */
  @Builder
  exploreSourcePickerContent() {
    Column({ space: AppSpacing.XS }) {
      SourcePickerSearchField({
        text: this.exploreSourceFilterInput,
        onTextChange: (value: string): void => {
          this.exploreSourceFilterInput = value;
          this.applyExploreSourceFilter();
        }
      })

      if (this.exploreSourceGroups.length > 1) {
        this.exploreSourceGroupTabs()
      }

      if (this.getFilteredExploreSourceOptions().length === 0) {
        Text(this.activeExploreSourceGroup === '__all__' ? '没有匹配的书源' : '当前分组没有匹配的书源')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .height(52)
          .textAlign(TextAlign.Center)
      } else {
        List({ scroller: this.exploreSourceScroller, space: 0 }) {
          LazyForEach(this.exploreSourceDataSource, (option: ExploreSourceOption) => {
            ListItem() {
              Row() {
                Text(this.exploreSourceDisplayName(option))
                  .fontSize(AppFontSize.BODY_LARGE)
                  .fontColor(option.sourceUrl === this.selectedSourceUrl ? this.accentColor() : this.primaryTextColor())
                  .fontWeight(option.sourceUrl === this.selectedSourceUrl ? FontWeight.Medium : FontWeight.Regular)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                if (this.activeExploreSourceGroup === '__all__') {
                  SourceGroupTag({ label: this.exploreSourceGroupLabel(option.sourceGroup) })
                    .margin({ left: AppSpacing.MD })
                }

                if (option.sourceUrl === this.selectedSourceUrl) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(18)
                    .fontColor([this.accentColor()])
                    .margin({ left: AppSpacing.MD })
                }
              }
              .width('100%')
              .height(ExplorePage.MENU_ITEM_HEIGHT)
              .padding({ left: 12, right: 12 })
              .borderRadius(this.exploreMenuItemRadius())
              .backgroundColor(option.sourceUrl === this.selectedSourceUrl ? this.exploreSelectedBackgroundColor() : '#00000000')
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                if (this.showExploreSourceActionMenu) return;
                this.showExploreSourcePicker = false;
                this.clearExploreSourceFilter();
                this.switchExploreSource(option);
              })
              .gesture(
                LongPressGesture({ repeat: false })
                  .onAction((event: GestureEvent) => {
                    this.openExploreSourceActions(option, event);
                  })
              )
            }
          }, (option: ExploreSourceOption): string => option.sourceUrl || option.sourceName)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .constraintSize({ maxHeight: 320 })
        .scrollBar(BarState.Auto)
        .cachedCount(8)
        .onAppear(() => { setTimeout(() => this.scrollExploreSourceToCurrent(), 0); })
      }
    }
    .width(this.exploreSourceDropdownWidth())
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
    .parallelGesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          this.switchExploreSourceGroupBySwipe(event.offsetX);
        })
    )
  }

  @Builder
  exploreSourceActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#52000000' : '#26FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
        .onClick(() => this.closeExploreSourceActions())

      Column() {
        SourceActionMenuList({
          isNative: this.actionExploreSourceNative,
          onAction: (kind: string): void => {
            this.runExploreSourceAction(kind);
          }
        })
      }
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.exploreContextMenuLeft(SourceActionMenuList.WIDTH),
        y: this.exploreContextMenuTop(SourceActionMenuList.menuHeight(this.actionExploreSourceNative)) })
    }
    .width('100%')
    .height('100%')
    .zIndex(12)
  }

  @Builder
  exploreSourceGroupTabs() {
    Scroll() {
      Row() {
        this.exploreSourceGroupTab('全部', '__all__')
        ForEach(this.exploreSourceGroups, (group: string) => {
          this.exploreSourceGroupTab(group, group)
        }, (group: string) => group)
      }
      .constraintSize({ minWidth: '100%' })
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height(ExplorePage.MENU_ITEM_HEIGHT)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  /** 字号与下面的书源列表、书架分类栏一致，选中项强调色加下划线。 */
  @Builder
  exploreSourceGroupTab(label: string, groupKey: string) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.activeExploreSourceGroup === groupKey ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.activeExploreSourceGroup === groupKey ? this.accentColor() : this.secondaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 128 })
      Row()
        .width(16)
        .height(3)
        .borderRadius(1.5)
        .backgroundColor(this.accentColor())
        .opacity(this.activeExploreSourceGroup === groupKey ? 1 : 0)
    }
    .height('100%')
    .padding({ left: 12, right: 12, top: 6 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.selectExploreSourceGroup(groupKey))
  }

  /** 标题右侧的书源名标签：按名称估宽，最多占屏宽 45%，点开书源选择弹出层。 */
  @Builder
  exploreSourceLabel() {
    Row() {
      ImmersiveMaterialSurface({
        surfaceWidth: this.exploreSourceLabelWidth(),
        surfaceHeight: ExplorePage.HEADER_CONTROL_SIZE,
        darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(),
        glowColor: this.accentGlowColor()
      }) {
        Row({ space: AppSpacing.XS }) {
          Text(this.selectedSourceName || '选择书源')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          SymbolGlyph(this.showExploreSourcePicker ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([this.secondaryTextColor()])
        }
        .width('100%')
        .height('100%')
        .padding({ left: 14, right: 10 })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .accessibilityText(`当前书源${this.selectedSourceName}，切换书源`)
        .onClick(() => {
          this.showExploreFilterPanel = false;
          this.showExplorePlatformMenu = false;
          this.toggleExploreSourcePicker();
        })
      }
    }
    .margin({ left: AppSpacing.MD, right: 10 })
    .bindPopup(this.showExploreSourcePicker, ImmersiveMaterialRuntime.popupMenuOptions((): void => {
      this.exploreSourcePickerContent()
    }, Placement.BottomRight, this.appDarkMode, this.accentColor(), () => {
      this.showExploreSourcePicker = false;
      this.clearExploreSourceFilter();
    }))
  }

  exploreSourceLabelWidth(): number {
    const name = this.selectedSourceName || '选择书源';
    let textWidth = 0;
    for (let index = 0; index < name.length; index++) {
      textWidth += name.charCodeAt(index) > 0x2E80 ? AppFontSize.BODY : AppFontSize.BODY * 0.6;
    }
    // 左右留白 24、箭头 14、间隔 4。
    const desired = Math.ceil(textWidth) + 42;
    // 右侧还有布局、刷新（以及可选的筛选）按钮，各 40 加 10 间隔；标题约 56，页边距 32。
    const buttonsWidth = (this.exploreFilters.length > 0 ? 3 : 2) * (ExplorePage.HEADER_CONTROL_SIZE + 10);
    const available = this.exploreViewportWidth - 32 - 56 - AppSpacing.MD - buttonsWidth;
    return Math.max(72, Math.min(desired, Math.floor(Math.min(this.exploreViewportWidth * 0.45, available))));
  }

  @Builder
  exploreHeaderCircleButton(icon: Resource, active: boolean, label: string, onTap: () => void) {
    ImmersiveMaterialSurface({
      surfaceWidth: ExplorePage.HEADER_CONTROL_SIZE,
      surfaceHeight: ExplorePage.HEADER_CONTROL_SIZE,
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
  exploreFilterButton() {
    Row() {
      this.exploreHeaderCircleButton($r('sys.symbol.funnel'), this.showExploreFilterPanel,
        `筛选条件：${this.exploreFilterSummary()}`, () => {
          this.showExploreSourcePicker = false;
          this.showExplorePlatformMenu = false;
          this.toggleExploreFilterPanel();
        })
    }
    .margin({ right: 10 })
    .bindPopup(this.showExploreFilterPanel, ImmersiveMaterialRuntime.popupMenuOptions((): void => {
      this.exploreFilterPopupContent()
    }, Placement.BottomRight, this.appDarkMode, this.accentColor(), () => {
      this.closeExploreFilterPanel();
    }))
  }

  exploreFilterSummary(): string {
    return this.exploreFilters.map((filter: ExploreFilterGroup) => `${filter.title}${filter.selected || '未选'}`)
      .join('，');
  }

  /** 书源提供的筛选条件（分类、状态、排序等）：分组排列，选好后点“完成”一次生效。 */
  @Builder
  exploreFilterPopupContent() {
    Column() {
      Row() {
        Text('筛选条件')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text('完成')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor())
          .padding({ left: AppSpacing.LG, right: AppSpacing.XS, top: AppSpacing.MD, bottom: AppSpacing.MD })
          .onClick(() => {
            this.applyExploreFilterDrafts();
          })
      }
      .width('100%')
      .height(ExplorePage.MENU_ITEM_HEIGHT)
      .padding({ left: 12, right: 8 })

      Scroll() {
        Column({ space: AppSpacing.LG }) {
          ForEach(this.exploreFilterDrafts, (filter: ExploreFilterGroup) => {
            Column({ space: AppSpacing.SM }) {
              Text(filter.title)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.secondaryTextColor())
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(filter.options, (name: string) => {
                  this.exploreFilterDraftOptionChip(filter, name)
                }, (name: string): string => `${filter.title}:${name}`)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (filter: ExploreFilterGroup): string =>
            `${filter.title}:${filter.selected}:${filter.options.join('|')}`)
        }
        .width('100%')
        .padding({ left: 12, right: 4, top: AppSpacing.XS, bottom: AppSpacing.LG })
      }
      .width('100%')
      .constraintSize({ maxHeight: Math.min(420, Math.floor(this.exploreViewportHeight * 0.6)) })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width(Math.min(340, Math.max(1, this.exploreViewportWidth - 32)))
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  showsExploreChannelBar(): boolean {
    return this.getActiveEntries().length > 0 || this.showsExplorePlatformSelector();
  }

  /** 书源有多个模式（站点）时，频道栏左侧固定显示当前模式；有筛选条件的书源不走模式。 */
  showsExplorePlatformSelector(): boolean {
    return this.exploreFilters.length === 0 && this.platformNames.length > 1;
  }

  /** 标题下方唯一的一行：左侧可选的模式，右侧横滑频道，选中项强调色加下划线。 */
  @Builder
  exploreChannelBar() {
    Row() {
      if (this.exploreChannelBarWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.exploreChannelBarWidth,
          surfaceHeight: ExplorePage.CHANNEL_BAR_HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: this.accentGlowColor()
        }) {
          Row() {
            if (this.showsExplorePlatformSelector()) {
              Row({ space: AppSpacing.XXS }) {
                Text(this.selectedPlatform || this.platformNames[0])
                  .fontSize(AppFontSize.BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.primaryTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 96 })
                SymbolGlyph(this.showExplorePlatformMenu ? $r('sys.symbol.chevron_up') :
                  $r('sys.symbol.chevron_down'))
                  .fontSize(12)
                  .fontColor([this.secondaryTextColor()])
              }
              .height('100%')
              .padding({ left: 16, right: 10 })
              .alignItems(VerticalAlign.Center)
              .accessibilityText(`当前模式${this.selectedPlatform}，切换模式`)
              .bindPopup(this.showExplorePlatformMenu, ImmersiveMaterialRuntime.popupMenuOptions((): void => {
                this.explorePlatformMenuContent()
              }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
                this.showExplorePlatformMenu = false;
              }))
              .onClick(() => {
                this.showExploreSourcePicker = false;
                this.showExploreFilterPanel = false;
                this.showExplorePlatformMenu = !this.showExplorePlatformMenu;
              })

              Divider()
                .vertical(true)
                .height(18)
                .strokeWidth(1)
                .color(ThemeRuntime.hairlineColor(this.appDarkMode))
            }

            List({ scroller: this.exploreChannelScroller }) {
              ForEach(this.getActiveEntries(), (entry: ExploreEntry, index: number) => {
                ListItem() {
                  Column({ space: 3 }) {
                    Text(entry.title)
                      .fontSize(AppFontSize.BODY_LARGE)
                      .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Regular)
                      .fontColor(this.selectedIndex === index ? this.accentColor() : this.secondaryTextColor())
                      .maxLines(1)
                    Row()
                      .width(16)
                      .height(3)
                      .borderRadius(1.5)
                      .backgroundColor(this.accentColor())
                      .opacity(this.selectedIndex === index ? 1 : 0)
                      .scale({ x: this.selectedIndex === index ? 1 : 0.4, y: 1 })
                      .animation({ duration: 220, curve: Curve.Friction })
                  }
                  .height('100%')
                  .padding({ left: 10, right: 10, top: 6 })
                  .justifyContent(FlexAlign.Center)
                  .accessibilityText(entry.title)
                  .accessibilitySelected(this.selectedIndex === index)
                  .onClick(() => this.selectExploreEntry(index))
                }
              }, (entry: ExploreEntry, index: number): string => `${index}_${entry.title}`)
            }
            .listDirection(Axis.Horizontal)
            .layoutWeight(1)
            .height('100%')
            .padding({ left: this.showsExplorePlatformSelector() ? 2 : 6, right: 6 })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

            // 固定在右端、不随频道横滑：打开全部分类面板。图标与标题行的布局切换按钮区分开。
            if (this.showsExploreCategoryButton()) {
              Divider()
                .vertical(true)
                .height(18)
                .strokeWidth(1)
                .color(ThemeRuntime.hairlineColor(this.appDarkMode))

              Row() {
                SymbolGlyph($r('sys.symbol.chevron_down_circle'))
                  .fontSize(20)
                  .fontColor([this.showExploreCategorySheet ? this.accentColor() : this.primaryTextColor()])
              }
              .width(46)
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .accessibilityText('全部分类')
              .onClick(() => this.openExploreCategorySheet())
            }
          }
          .width('100%')
          .height('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
    }
    .width(`calc(100% - ${AppSpacing.XL * 2}vp)`)
    .height(ExplorePage.CHANNEL_BAR_HEIGHT)
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.exploreChannelBarWidth) {
        this.exploreChannelBarWidth = width;
      }
    })
  }

  selectExploreEntry(index: number): void {
    this.selectedIndex = index;
    const entry = this.getActiveEntries()[index];
    if (entry) {
      ExploreCategoryHistoryStore.record(getContext(this), this.selectedSourceUrl,
        ExploreCategoryHistoryStore.entryKey(entry.title, entry.url));
    }
    this.loadBooks();
    try {
      this.exploreChannelScroller.scrollToIndex(index, true, ScrollAlign.CENTER);
    } catch (error) {
      console.warn('定位当前发现频道失败:', error);
    }
  }

  @Builder
  explorePlatformMenuContent() {
    Column({ space: AppSpacing.XXS }) {
      ForEach(this.platformNames, (name: string) => {
        Row() {
          Text(name)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(this.selectedPlatform === name ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.selectedPlatform === name ? this.accentColor() : this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.selectedPlatform === name) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(14)
              .fontColor([this.accentColor()])
          }
        }
        .width('100%')
        .height(ExplorePage.MENU_ITEM_HEIGHT)
        .padding({ left: 12, right: 12 })
        .borderRadius(this.exploreMenuItemRadius())
        .backgroundColor(this.selectedPlatform === name ? this.exploreSelectedBackgroundColor() : '#00000000')
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.showExplorePlatformMenu = false;
          this.switchExplorePlatform(name);
        })
      }, (name: string) => name)
    }
    .width(180)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  exploreMenuItemRadius(): number {
    return ImmersiveMaterialRuntime.POPUP_MENU_RADIUS - ImmersiveMaterialRuntime.POPUP_MENU_PADDING;
  }

  accentGlowColor(): string {
    return `#40${this.accentColor().substring(1)}`;
  }

  exploreSourceDropdownWidth(): number {
    // 常规设备保持稳定的 320vp；窄屏只按安全边距收窄，不再随书源或分组内容变化。
    return Math.min(320, Math.max(1, this.exploreViewportWidth - 32));
  }

  async addSearchBookToShelf(searchBook: SearchBook): Promise<void> {
    const searchKey = SearchBookShelfHelper.keyOf(searchBook);
    this.markSearchBookJoining(searchKey);
    try {
      const change = await SearchBookShelfHelper.addToShelf(getContext(this), searchBook);
      this.markSearchBookInShelf(change.shelfKey || change.requestKey);
    } catch (e) {
      console.error('加入书架失败:', e);
      HdsFeedback.showToast('加入书架失败');
    } finally {
      this.unmarkSearchBookJoining(searchKey);
    }
  }

  async readSearchBook(searchBook: SearchBook): Promise<void> {
    if (this.isSearchBookJoiningShelf(searchBook)) return;
    if (!this.isSearchBookInShelf(searchBook)) {
      // Use the transient reader flow; reading a search result must not add it to the shelf.
      this.openSearchBookDetail(searchBook, true);
      return;
    }
    const shelfBook = await SearchBookShelfHelper.findShelfBookByKey(
      SearchBookShelfHelper.keyOf(searchBook), true);
    if (!shelfBook?.bookUrl) {
      HdsFeedback.showToast('书籍准备失败，请稍后重试');
      return;
    }
    router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: shelfBook.bookUrl } });
  }

  openExploreSourcePicker(): void {
    if (this.sourceOptions.length === 0) {
      return;
    }
    this.exploreSourceFilterInput = '';
    this.exploreSourceFilterKeyword = '';
    this.activeExploreSourceGroup = '__all__';
    this.refreshExploreSourceDataSource();
    this.showExploreSourcePicker = true;
  }

  scrollExploreSourceToCurrent(): void {
    if (!this.showExploreSourcePicker || !this.selectedSourceUrl) return;
    const options = this.getFilteredExploreSourceOptions();
    const selectedIndex = options.findIndex((option: ExploreSourceOption) =>
      option.sourceUrl === this.selectedSourceUrl);
    if (selectedIndex < 0) return;
    const rowHeight = 44;
    const visibleHeight = 320;
    const targetOffset = Math.max(0, selectedIndex * rowHeight - (visibleHeight - rowHeight) / 2);
    try {
      this.exploreSourceScroller.scrollTo({ xOffset: 0, yOffset: targetOffset, animation: false });
    } catch (error) {
      console.warn('定位当前发现书源失败:', error);
    }
  }

  toggleExploreSourcePicker(): void {
    if (this.showExploreSourcePicker) {
      this.showExploreSourcePicker = false;
      this.clearExploreSourceFilter();
      return;
    }
    this.openExploreSourcePicker();
  }

  applyExploreSourceFilter(): void {
    this.exploreSourceFilterKeyword = this.exploreSourceFilterInput.trim().toLowerCase();
    this.refreshExploreSourceDataSource();
    if (this.sourceOptions.length > 0) {
      this.showExploreSourcePicker = true;
    }
  }

  clearExploreSourceFilter(): void {
    this.exploreSourceFilterInput = '';
    this.exploreSourceFilterKeyword = '';
    this.refreshExploreSourceDataSource();
  }

  openExploreSourceActions(option: ExploreSourceOption, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.exploreContextMenuX = finger.globalX;
      this.exploreContextMenuY = finger.globalY;
    }
    this.actionExploreSourceUrl = option.sourceUrl;
    this.actionExploreSourceNative = option.isNative === true;
    // 操作菜单画在页面上，书源弹出层在系统浮层里，先收起弹出层免得挡住菜单。
    this.showExploreSourcePicker = false;
    this.showExploreSourceActionMenu = true;
  }

  closeExploreSourceActions(): void {
    this.showExploreSourceActionMenu = false;
    this.actionExploreSourceUrl = '';
    this.actionExploreSourceNative = false;
  }

  /** 长按菜单的源变量与删除确认框内容；在本组件里创建，系统对话框才有父节点。 */
  @Builder
  sourceVariableDialog(params: SourceVariableDialogParams) {
    SourceVariableEditor({ params: params })
  }

  @Builder
  sourceDeleteDialog(params: SourceDeleteDialogParams) {
    SourceDeleteConfirm({ params: params })
  }

  /** 长按菜单的执行与搜索范围面板共用；这里只管发现页自己的刷新。 */
  runExploreSourceAction(kind: string): void {
    const sourceUrl = this.actionExploreSourceUrl;
    const isNative = this.actionExploreSourceNative;
    this.closeExploreSourceActions();
    if (!sourceUrl) return;
    if (SourceActionRunner.isNavigation(kind)) {
      SourceActionRunner.navigate(kind, sourceUrl, isNative);
    } else if (kind === SourceActionKind.VARIABLE) {
      SourceActionRunner.openVariableEditor(this.getUIContext(), sourceUrl,
        (dialogParams: SourceVariableDialogParams): CustomBuilder => (): void => {
          this.sourceVariableDialog(dialogParams);
        }, (): void => {
        if (this.isActive && !this.isLoading && this.selectedSourceUrl === sourceUrl) {
          this.loadEntries('', true);
        }
      });
    } else if (kind === SourceActionKind.DELETE) {
      SourceActionRunner.confirmDelete(this.getUIContext(), sourceUrl,
        (dialogParams: SourceDeleteDialogParams): CustomBuilder => (): void => {
          this.sourceDeleteDialog(dialogParams);
        }, (): void => {
        // 删除后重载发现页：若删的是当前源，loadEntries 会自动回退到首个可用源。
        if (this.isActive) {
          this.loadEntries('', true);
        }
      });
    }
  }

  exploreContextMenuLeft(menuWidth: number): number {
    return Math.max(12, Math.min(this.exploreContextMenuX - 18,
      this.exploreViewportWidth - menuWidth - 12));
  }

  exploreContextMenuTop(menuHeight: number): number {
    const below = this.exploreContextMenuY + 12;
    if (below + menuHeight <= this.exploreViewportHeight - 12) return below;
    return Math.max(this.statusBarHeight + 8, this.exploreContextMenuY - menuHeight - 12);
  }

  getFilteredExploreSourceOptions(): ExploreSourceOption[] {
    let options = this.sourceOptions;
    if (this.activeExploreSourceGroup !== '__all__') {
      options = options.filter((option: ExploreSourceOption) =>
        this.exploreSourceGroupLabel(option.sourceGroup) === this.activeExploreSourceGroup);
    }
    const keyword = this.exploreSourceFilterKeyword;
    if (!keyword) {
      return options;
    }
    return options.filter((option: ExploreSourceOption) => {
      const searchable = `${option.sourceName || ''}\n${option.sourceUrl || ''}\n${option.sourceGroup || ''}\n${(option.platforms || []).join(' ')}`
        .toLowerCase();
      return searchable.includes(keyword);
    });
  }

  refreshExploreSourceDataSource(): void {
    this.exploreSourceDataSource.replace(this.getFilteredExploreSourceOptions());
  }

  rebuildExploreSourceDisplayNames(options: ExploreSourceOption[]): void {
    const names = SourcePickerKit.displayNames(
      options.map((option: ExploreSourceOption): string => option.sourceName),
      options.map((option: ExploreSourceOption): string => option.sourceUrl));
    const result: Map<string, string> = new Map<string, string>();
    options.forEach((option: ExploreSourceOption, index: number): void => {
      result.set(option.sourceUrl || option.sourceName, names[index]);
    });
    this.exploreSourceDisplayNames = result;
  }

  exploreSourceDisplayName(option: ExploreSourceOption): string {
    return this.exploreSourceDisplayNames.get(option.sourceUrl || option.sourceName) ||
      option.sourceName || '未命名书源';
  }

  buildExploreSourceGroups(): string[] {
    const groups: Set<string> = new Set<string>();
    for (const option of this.sourceOptions) {
      groups.add(this.exploreSourceGroupLabel(option.sourceGroup));
    }
    return SourcePickerKit.sortGroups(Array.from(groups));
  }

  exploreSourceGroupLabel(group: string): string {
    return SourcePickerKit.groupLabel(group);
  }

  selectExploreSourceGroup(groupKey: string): void {
    if (groupKey === '__all__' || this.exploreSourceGroups.includes(groupKey)) {
      this.activeExploreSourceGroup = groupKey;
      this.refreshExploreSourceDataSource();
    }
  }

  switchExploreSourceGroupBySwipe(offsetX: number): void {
    if (Math.abs(offsetX) < 36) return;
    const groups = ['__all__'].concat(this.exploreSourceGroups);
    const currentIndex = Math.max(0, groups.indexOf(this.activeExploreSourceGroup));
    const direction = offsetX < 0 ? 1 : -1;
    const targetIndex = Math.max(0, Math.min(groups.length - 1, currentIndex + direction));
    if (targetIndex !== currentIndex) {
      this.activeExploreSourceGroup = groups[targetIndex];
      this.refreshExploreSourceDataSource();
    }
  }

  switchExplorePlatform(platform: string): void {
    if (this.selectedPlatform === platform) {
      return;
    }
    this.selectedPlatform = platform;
    this.selectedIndex = 0;
    this.books = [];
    this.status = `正在切换到 ${platform}...`;
    AppStorage.setOrCreate('explorePlatform', platform);
    this.saveExploreSelection();
    this.loadEntries(platform);
  }

  switchExploreSource(option: ExploreSourceOption): void {
    if (this.selectedSourceUrl === option.sourceUrl) {
      return;
    }
    this.selectedSourceName = option.sourceName;
    this.closeExploreFilterPanel();
    this.selectedSourceUrl = option.sourceUrl;
    this.platformNames = this.getSelectedSourcePlatforms();
    this.normalizeSelectedPlatform();
    this.selectedIndex = 0;
    this.books = [];
    this.status = `正在切换到 ${option.sourceName}...`;
    AppStorage.setOrCreate('exploreSourceUrl', option.sourceUrl);
    this.saveExploreSelection();
    this.loadEntries();
  }

  beginExploreLoad(): number {
    this.exploreLoadVersion++;
    this.exploreMetadataQueue = [];
    this.exploreMetadataQueued.clear();
    this.exploreMetadataUnavailable.clear();
    this.isLoading = true;
    return this.exploreLoadVersion;
  }

  requestExploreMetadata(book: SearchBook): void {
    if (!book || (!book.bookUrl || !book.origin) || (book.author && book.coverUrl)) return;
    const key = this.exploreMetadataKey(book);
    if (!key || this.exploreMetadataQueued.has(key) || this.exploreMetadataInFlight.has(key) ||
      this.exploreMetadataUnavailable.has(key)) return;
    const task = new ExploreMetadataTask();
    task.book = book;
    task.loadVersion = this.exploreLoadVersion;
    this.exploreMetadataQueue.push(task);
    this.exploreMetadataQueued.add(key);
    this.drainExploreMetadataQueue();
  }

  private drainExploreMetadataQueue(): void {
    while (this.exploreMetadataActive < 3 && this.exploreMetadataQueue.length > 0) {
      const task = this.exploreMetadataQueue.shift();
      if (!task) return;
      const key = this.exploreMetadataKey(task.book);
      this.exploreMetadataQueued.delete(key);
      if (!key || task.loadVersion !== this.exploreLoadVersion || this.exploreMetadataInFlight.has(key)) continue;
      this.exploreMetadataInFlight.add(key);
      this.exploreMetadataActive++;
      this.enrichExploreMetadata(task).catch((error: Object): void => {
        console.warn('[ExploreMetadata] detail enrichment failed:', task.book.originName || task.book.origin,
          error instanceof Error ? error.message : String(error || 'unknown error'));
      }).finally((): void => {
        this.exploreMetadataInFlight.delete(key);
        this.exploreMetadataActive = Math.max(0, this.exploreMetadataActive - 1);
        this.drainExploreMetadataQueue();
      });
    }
  }

  private async enrichExploreMetadata(task: ExploreMetadataTask): Promise<void> {
    if (task.loadVersion !== this.exploreLoadVersion) return;
    const source = await AppDatabase.getInstance().getBookSource(task.book.origin);
    if (!source || task.loadVersion !== this.exploreLoadVersion) return;
    const needsAuthor = !task.book.author && !!(source.bookInfoRule.author || '').trim();
    const needsCover = !task.book.coverUrl && !!(source.bookInfoRule.coverUrl || '').trim();
    const key = this.exploreMetadataKey(task.book);
    if (!needsAuthor && !needsCover) {
      this.exploreMetadataUnavailable.add(key);
      return;
    }

    const detail = new Book();
    detail.bookUrl = task.book.bookUrl;
    detail.tocUrl = task.book.tocUrl;
    detail.origin = task.book.origin;
    detail.originName = task.book.originName;
    detail.name = task.book.name;
    detail.author = task.book.author;
    detail.kind = task.book.kind;
    detail.status = task.book.status;
    detail.coverUrl = task.book.coverUrl;
    detail.intro = task.book.intro;
    detail.latestChapterTitle = task.book.latestChapterTitle;
    detail.updateTime = task.book.updateTime;
    detail.wordCount = task.book.wordCount;
    detail.type = task.book.type;
    detail.variable = task.book.variable;
    const enriched = await new WebBookService().getBookInfo(source, detail);
    if (task.loadVersion !== this.exploreLoadVersion) return;
    const index = this.books.findIndex((item: SearchBook): boolean =>
      item.origin === task.book.origin && item.bookUrl === task.book.bookUrl);
    if (index < 0) return;
    const current = this.books[index];
    let changed = false;
    if (!current.author && enriched.author) {
      current.author = BookFieldSanitizer.clean(enriched.author);
      changed = !!current.author || changed;
    }
    if (!current.coverUrl && enriched.coverUrl) {
      current.coverUrl = CoverUrlNormalizer.normalize(enriched.coverUrl);
      changed = !!current.coverUrl || changed;
    }
    if (!current.status && enriched.status) {
      current.status = BookFieldSanitizer.clean(enriched.status);
      changed = !!current.status || changed;
    }
    if (!current.updateTime && enriched.updateTime) {
      current.updateTime = BookFieldSanitizer.clean(enriched.updateTime);
      changed = !!current.updateTime || changed;
    }
    if (changed) this.books = this.books.slice();
    if ((!needsAuthor || !!current.author) && (!needsCover || !!current.coverUrl)) {
      this.exploreMetadataUnavailable.add(key);
    }
  }

  private exploreMetadataKey(book: SearchBook): string {
    return `${book.origin || ''}|${book.bookUrl || ''}`;
  }

  isCurrentExploreLoad(loadVersion: number): boolean {
    return loadVersion === this.exploreLoadVersion;
  }

  finishExploreLoad(loadVersion: number): void {
    if (this.isCurrentExploreLoad(loadVersion)) {
      this.isLoading = false;
    }
  }

  normalizeSelectedPlatform(): void {
    if (this.platformNames.length === 0) {
      return;
    }
    if (!this.platformNames.includes(this.selectedPlatform)) {
      this.selectedPlatform = this.platformNames.length > 0 ? this.platformNames[0] : '';
      AppStorage.setOrCreate('explorePlatform', this.selectedPlatform);
      this.saveExploreSelection();
    }
  }

  async restoreExploreSelectionFromSettings(): Promise<void> {
    try {
      const settings = await SearchExploreSettingsStore.load(getContext(this));
      const storedSourceUrl = settings.exploreSourceUrl || AppStorage.get<string>('exploreSourceUrl') || '';
      const storedPlatform = settings.explorePlatform || AppStorage.get<string>('explorePlatform') || '';
      if (storedSourceUrl) {
        this.selectedSourceUrl = storedSourceUrl;
        settings.exploreSourceUrl = storedSourceUrl;
      }
      if (storedPlatform) {
        this.selectedPlatform = storedPlatform;
        settings.explorePlatform = storedPlatform;
      }
      SearchExploreSettingsStore.applyToStorage(settings);
    } catch (e) {
      console.warn('恢复发现页选择失败:', e);
    }
  }

  applyResultLayout(layout: string): void {
    this.exploreResultLayout = layout;
    SearchExploreSettingsStore.saveResultLayout(
      getContext(this), SearchExploreSettingsStore.KEY_EXPLORE_RESULT_LAYOUT, layout
    ).catch((e: Error) => {
      console.warn('保存发现结果布局失败:', e);
    });
  }

  saveExploreSelection(): void {
    AppStorage.setOrCreate('exploreSourceUrl', this.selectedSourceUrl);
    AppStorage.setOrCreate('explorePlatform', this.selectedPlatform);
    SearchExploreSettingsStore.saveExploreSelection(
      getContext(this),
      this.selectedSourceUrl,
      this.selectedPlatform
    ).catch((e: Error) => {
      console.warn('保存发现页选择失败:', e);
    });
  }

  async syncExploreShelfStatus(books: SearchBook[]): Promise<void> {
    try {
      const version = this.shelfStatusVersion;
      const keys = await this.loadExploreShelfKeys(books);
      if (version === this.shelfStatusVersion) {
        this.shelfBookKeys = keys;
      }
    } catch (e) {
      console.error('同步发现书架状态失败:', e);
    }
  }

  async loadExploreShelfKeys(books: SearchBook[]): Promise<string[]> {
    return await SearchBookShelfHelper.syncShelfKeys(getContext(this), books);
  }

  isSearchBookInShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys);
  }

  isSearchBookJoiningShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isBusy(book, this.addingShelfBookKeys);
  }

  async toggleSearchBookShelf(searchBook: SearchBook): Promise<void> {
    if (this.isSearchBookJoiningShelf(searchBook)) {
      return;
    }

    if (this.isSearchBookInShelf(searchBook)) {
      await this.removeSearchBookFromShelf(searchBook);
    } else {
      await this.addSearchBookToShelf(searchBook);
    }
  }

  async removeSearchBookFromShelf(searchBook: SearchBook): Promise<void> {
    try {
      const change = await SearchBookShelfHelper.removeFromShelf(getContext(this), searchBook);
      this.shelfStatusVersion++;
      this.shelfBookKeys = SearchBookShelfHelper.withoutKey(this.shelfBookKeys, change.requestKey);
    } catch (e) {
      console.error('移出书架失败:', e);
      HdsFeedback.showToast('移出书架失败');
    }
  }

  markSearchBookInShelf(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.shelfBookKeys, bookKey);
    if (next !== this.shelfBookKeys) {
      this.shelfStatusVersion++;
      this.shelfBookKeys = next;
    }
  }

  markSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  unmarkSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withoutKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  shouldShowExploreStatus(): boolean {
    if (!this.status) {
      return false;
    }
    if (this.verificationUrl) {
      return true;
    }
    return this.books.length === 0;
  }

  getSelectedSourcePlatforms(): string[] {
    const option = this.getSelectedSourceOption();
    return option ? option.platforms : [];
  }

  getSelectedSourceUrl(): string {
    const option = this.getSelectedSourceOption();
    return option ? option.sourceUrl : '';
  }

  getSelectedSourceOption(): ExploreSourceOption | null {
    for (const option of this.sourceOptions) {
      if (option.sourceUrl === this.selectedSourceUrl) return option;
    }
    return null;
  }

  getSelectedSiteLabel(): string {
    return this.platformNames.length > 0 ? this.selectedPlatform : this.selectedSourceName;
  }

  openVerification(): void {
    const url = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
    if (!url) {
      HdsFeedback.showToast('暂无需要验证的网页');
      return;
    }
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: this.verificationTitle || '网页验证'
      }
    });
  }

  getActiveEntries(): ExploreEntry[] {
    const sourceEntries = !this.selectedSourceUrl ? this.entries :
      this.entries.filter(entry => entry.sourceUrl === this.selectedSourceUrl);
    if (!this.selectedPlatform) return sourceEntries;
    const hasSelectedGroup = sourceEntries.some((entry: ExploreEntry): boolean =>
      (entry.groupTitle || '') === this.selectedPlatform);
    return hasSelectedGroup ? sourceEntries.filter((entry: ExploreEntry): boolean =>
      (entry.groupTitle || '') === this.selectedPlatform) : sourceEntries;
  }

  /** 当前书源已加载的全部分类（不按模式过滤），供全部分类面板分组展示。 */
  exploreCategoryEntries(): ExploreEntry[] {
    return !this.selectedSourceUrl ? this.entries :
      this.entries.filter((entry: ExploreEntry): boolean => entry.sourceUrl === this.selectedSourceUrl);
  }

  showsExploreCategoryButton(): boolean {
    return this.exploreCategoryEntries().length >= ExplorePage.CATEGORY_SHEET_MIN_COUNT;
  }

  exploreCategoryItems(): ExploreCategoryItem[] {
    const items: ExploreCategoryItem[] = [];
    const seen: Set<string> = new Set<string>();
    for (const entry of this.exploreCategoryEntries()) {
      const key = ExploreCategoryHistoryStore.entryKey(entry.title, entry.url);
      if (seen.has(key)) continue;
      seen.add(key);
      items.push({ key: key, title: entry.title, groupTitle: entry.groupTitle || '' });
    }
    return items;
  }

  currentExploreEntryKey(): string {
    const entries = this.getActiveEntries();
    if (entries.length === 0) return '';
    const entry = entries[Math.min(Math.max(0, this.selectedIndex), entries.length - 1)];
    return ExploreCategoryHistoryStore.entryKey(entry.title, entry.url);
  }

  async openExploreCategorySheet(): Promise<void> {
    this.showExploreSourcePicker = false;
    this.showExploreFilterPanel = false;
    this.showExplorePlatformMenu = false;
    // “最近”要在面板创建时就有数据，先确保本机记录已读入。
    await ExploreCategoryHistoryStore.load(getContext(this));
    this.showExploreCategorySheet = true;
  }

  /**
   * 面板里点选分类。分类属于另一个已加载的分组（左侧模式）时先切到该分组，分组内容已在内存里，不必重新加载。
   */
  selectExploreCategory(key: string): void {
    this.showExploreCategorySheet = false;
    const matches = (entry: ExploreEntry): boolean =>
      ExploreCategoryHistoryStore.entryKey(entry.title, entry.url) === key;
    const entry = this.exploreCategoryEntries().find(matches);
    if (!entry) return;
    const group = (entry.groupTitle || '').trim();
    let platformChanged = false;
    if (group && group !== this.selectedPlatform && this.platformNames.includes(group)) {
      this.selectedPlatform = group;
      this.saveExploreSelection();
      platformChanged = true;
    }
    const index = this.getActiveEntries().findIndex(matches);
    if (index < 0) return;
    if (!platformChanged && index === this.selectedIndex) {
      ExploreCategoryHistoryStore.record(getContext(this), this.selectedSourceUrl, key);
      return;
    }
    this.selectExploreEntry(index);
    // 切换分组后频道栏会重建，等它布局完再滚到选中项。
    this.scrollExploreChannelToSelected();
  }

  scrollExploreChannelToSelected(): void {
    setTimeout(() => {
      try {
        this.exploreChannelScroller.scrollToIndex(this.selectedIndex, true, ScrollAlign.CENTER);
      } catch (error) {
        console.warn('定位当前发现频道失败:', error);
      }
    }, 0);
  }

  getEntryGroupNames(entries: ExploreEntry[]): string[] {
    const names: string[] = [];
    for (const entry of entries) {
      const name = (entry.groupTitle || '').trim();
      if (name && !names.includes(name)) names.push(name);
    }
    return names;
  }

  /** 实际生效的标题行收起量：没有可滚动的列表时标题行始终完整显示。 */
  exploreHeaderCollapseValue(): number {
    return !this.isLoading && this.books.length > 0 ? this.exploreHeaderCollapse : 0;
  }

  onExploreListScroll(delta: number, offset: number): void {
    const next = CollapsingHeader.next(this.exploreHeaderCollapse, delta, offset);
    if (next !== this.exploreHeaderCollapse) {
      this.exploreHeaderCollapse = next;
    }
  }

  onExploreListScrollStop(offset: number): void {
    const target = CollapsingHeader.settle(this.exploreHeaderCollapse, offset);
    if (target !== this.exploreHeaderCollapse) {
      animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
        this.exploreHeaderCollapse = target;
      });
    }
  }

  /** 列表顶部留白按标题行完整显示时的高度预留，不随收起变化，避免滚动中列表跳动。 */
  exploreTopOverlayHeight(): number {
    let height = this.statusBarHeight + 56;
    if (this.showsExploreChannelBar()) {
      height += ExplorePage.CHANNEL_BAR_HEIGHT + AppSpacing.MD;
    }
    if (this.shouldShowExploreStatus()) {
      height += 40;
    }
    return height;
  }

  copyExploreFilterGroups(filters: ExploreFilterGroup[]): ExploreFilterGroup[] {
    const copies: ExploreFilterGroup[] = [];
    for (const filter of filters) {
      copies.push({
        title: filter.title,
        options: filter.options.slice(),
        selected: filter.selected
      });
    }
    return copies;
  }

  openExploreFilterPanel(): void {
    this.exploreFilterDrafts = this.copyExploreFilterGroups(this.exploreFilters);
    this.showExploreFilterPanel = true;
  }

  closeExploreFilterPanel(): void {
    this.showExploreFilterPanel = false;
    this.exploreFilterDrafts = [];
  }

  toggleExploreFilterPanel(): void {
    if (this.showExploreFilterPanel) {
      this.closeExploreFilterPanel();
    } else {
      this.openExploreFilterPanel();
    }
  }

  selectExploreFilterDraft(title: string, selection: string): void {
    const next: ExploreFilterGroup[] = [];
    for (const filter of this.exploreFilterDrafts) {
      next.push({
        title: filter.title,
        options: filter.options.slice(),
        selected: filter.title === title ? selection : filter.selected
      });
    }
    this.exploreFilterDrafts = next;
  }

  async applyExploreFilterDrafts(): Promise<void> {
    const drafts = this.copyExploreFilterGroups(this.exploreFilterDrafts);
    const changed: ExploreFilterGroup[] = [];
    for (const draft of drafts) {
      const applied = this.exploreFilters.find((filter: ExploreFilterGroup): boolean =>
        filter.title === draft.title);
      if (applied && applied.selected !== draft.selected) changed.push(draft);
    }
    this.closeExploreFilterPanel();
    if (changed.length === 0 || this.isLoading || !this.selectedSourceUrl) return;

    this.status = '正在应用筛选条件...';
    this.books = [];
    this.isLoading = true;
    const failedTitles: string[] = [];
    for (const filter of changed) {
      const applied = await this.coordinator.applyExploreFilter(
        this.selectedSourceUrl, filter.title, filter.selected);
      if (!applied) failedTitles.push(filter.title);
    }
    this.isLoading = false;
    this.selectedPlatform = '';
    await this.loadEntries('', true);
    if (failedTitles.length > 0) {
      this.status = `${failedTitles.join('、')}筛选条件应用失败`;
    }
  }

  @Builder
  exploreFilterDraftOptionChip(filter: ExploreFilterGroup, name: string) {
    Text(name)
      .fontSize(AppFontSize.BODY)
      .fontWeight(filter.selected === name ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(filter.selected === name ? this.accentColor() : this.primaryTextColor())
      .height(32)
      .maxLines(1)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .backgroundColor(filter.selected === name ? this.exploreSelectedBackgroundColor() :
        ThemeRuntime.softFillColor(this.appDarkMode))
      .borderRadius(16)
      .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
      .onClick(() => {
        if (filter.selected !== name) this.selectExploreFilterDraft(filter.title, name);
      })
  }

  resultListBottomInset(): number {
    const comfortableGap = 20;
    if (deviceInfo.sdkApiVersion < 23) {
      return comfortableGap;
    }
    const floatingTabHeight = 56;
    return floatingTabHeight + Math.max(this.navBarHeight, 8) + comfortableGap;
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

  exploreSelectedBackgroundColor(): string {
    const color = this.accentColor();
    if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
      return `#11${color.substring(1)}`;
    }
    return this.appDarkMode ? '#112A6FCC' : '#11007DFF';
  }
}
