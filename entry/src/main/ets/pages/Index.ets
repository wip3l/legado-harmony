import { router, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { WebRuntimeAvailability } from '../utils/WebRuntimeAvailability';
import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { Book, BookChapter, BookSourceStageWebRuntime } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';
import { syncSystemSafeAreas } from '../utils/SystemBars';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { ReaderOpenTrace } from '../utils/ReaderOpenTrace';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { CloudSyncCoordinator } from '../account/CloudSyncCoordinator';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { ReaderTtsPlayerPanel } from '../components/ReaderTtsPlayerPanel';
import { TtsCatalogSheet, CatalogTitleDataSource } from '../components/TtsCatalogSheet';
import { BlankTabPage } from '../components/home/HomeTabShells';
import { BookshelfPage } from '../components/home/BookshelfPage';
import { ExplorePage } from '../components/home/ExplorePage';
import { SearchPage } from '../components/home/SearchPage';
import { SettingsPage } from '../components/home/SettingsTabPage';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

@Entry
@Component
struct Index {
  /** 底部页签切换时新页面滑入的距离和时长。 */
  static readonly TAB_ENTER_DISTANCE: number = 32;
  static readonly TAB_ENTER_DURATION: number = 260;
  private stageRuntimeController: webview.WebviewController = new webview.WebviewController();
  @State stageRuntimeMounted: boolean = true;
  private stageRuntimeResetScheduled: boolean = false;
  private stageRuntimeDisappearing: boolean = false;
  private stageRuntimeAttachRetryId: number = -1;
  private shortcutRoutingActive: boolean = false;
  private cloudSyncDebounceTimer: number = -1;
  @State @Watch('onCurrentIndexChanged') currentIndex: number = 0;
  /** 发现页第一次打开后常驻，切走只停用不销毁，回来时直接显示已加载的分类和列表。 */
  @State exploreTabMounted: boolean = false;
  /** 新页签从哪一侧滑入：往右边的页签切换时从右侧进入，反之从左侧。 */
  @State homeTabEnterOffset: number = Index.TAB_ENTER_DISTANCE;
  @State hdsMaterialRenderBranch: boolean = false;
  @State bookshelfMultiSelectActive: boolean = false;
  @State bookshelfActiveGroupId: number = 0;
  private immersiveTabsController: HdsTabsController = new HdsTabsController();
  private compatTabsController: TabsController = new TabsController();
  // 每页单独保存进度，常驻的搜索/发现页不能改变当前页的底栏。
  private tabHeaderCollapseProgress: number[] = [0, 0, 0, 0];
  @State bottomBarCollapseProgress: number = 0;
  @StorageLink('themeRevision') @Watch('onThemeRevisionChanged') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('appDarkMode') @Watch('onAppDarkModeChanged') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('launchShortcutNonce') @Watch('onLaunchShortcutChanged') launchShortcutNonce: number = 0;
  @StorageLink('singleSourceSearchNonce') @Watch('onSingleSourceSearchRequested') singleSourceSearchNonce: number = 0;
  @StorageLink('globalSearchPendingNonce') @Watch('onGlobalSearchRequested') globalSearchPendingNonce: number = 0;
  @StorageLink('bookSourceExploreRefreshNonce') @Watch('onBookSourceExploreRefreshRequested')
  bookSourceExploreRefreshNonce: number = 0;
  @StorageLink('cloudSyncDataChangeRevision') @Watch('onCloudSyncDataChanged')
  cloudSyncDataRevision: number = 0;
  @StorageLink('cloudSyncPreferenceChangeRevision') @Watch('onCloudSyncDataChanged')
  cloudSyncPreferenceRevision: number = 0;
  @StorageLink('cloudSyncApplicationPreferenceChangeRevision') @Watch('onCloudSyncDataChanged')
  cloudSyncApplicationPreferenceRevision: number = 0;
  @StorageLink('cloudSyncBookSourceChangeRevision') @Watch('onCloudSyncDataChanged')
  cloudSyncBookSourceRevision: number = 0;
  @StorageLink('globalTtsActive') @Watch('onGlobalTtsActiveChanged') globalTtsActive: boolean = false;
  @StorageLink('globalTtsPaused') globalTtsPaused: boolean = false;
  @StorageLink('globalTtsBookName') globalTtsBookName: string = '';
  @StorageProp('globalTtsBookUrl') globalTtsBookUrl: string = '';
  @StorageLink('globalTtsCover') globalTtsCover: ResourceStr = '';
  @StorageLink('globalTtsChapterTitle') globalTtsChapterTitle: string = '';
  @StorageLink('globalTtsMode') globalTtsMode: string = '';
  @StorageLink('globalTtsChapterProgress') globalTtsChapterProgress: string = '';
  @StorageLink('globalTtsBusy') globalTtsBusy: boolean = false;
  @State showGlobalTtsPanel: boolean = false;
  @State showGlobalTtsCatalog: boolean = false;
  @StorageLink('globalTtsAudioCatalogReverseOrder') @Watch('onGlobalTtsCatalogOrderChanged')
  globalTtsCatalogReverseOrder: boolean = false;
  @State globalTtsViewportWidth: number = 360;
  @State globalTtsViewportHeight: number = 720;
  @StorageLink('globalTtsCapsulePositionX') globalTtsCapsulePositionX: number = 16;
  @StorageLink('globalTtsCapsulePositionY') globalTtsCapsulePositionY: number = -1;
  private globalTtsDragOriginX: number = 0;
  private globalTtsDragOriginY: number = 0;
  private globalTtsCatalogScroller: ListScroller = new ListScroller();
  private globalTtsCatalogSource: CatalogTitleDataSource = new CatalogTitleDataSource();

  aboutToAppear() {
    this.shortcutRoutingActive = true;
    this.stageRuntimeDisappearing = false;
    this.scheduleStageRuntimeAttachFallback(0);
    BookSourceStageWebRuntime.get().setResetHandler((): void => this.resetStageRuntimeHost(),
      this.stageRuntimeController);
    hilog.info(0x0000, 'testTag', 'StartupTrace Index aboutToAppear %{public}d', Date.now());
    this.syncHomeSystemBars();
    this.openPendingShortcut();
  }

  onPageShow(): void {
    this.shortcutRoutingActive = true;
    // 从后台被桌面卡片/快捷方式唤起时，onNewWant 先于 onPageShow 写入 launchShortcutNonce，
    // 那时页面仍处于隐藏状态，@Watch 会把请求忽略掉，所以页面重新可见时要再检查一次。
    this.openPendingShortcut();
    hilog.info(0x0000, 'testTag', 'StartupTrace Index onPageShow %{public}d', Date.now());
    this.syncHomeSystemBars();
    // ReadBook is pushed over the retained Index route. Its final progress notification can arrive while the
    // bookshelf component is covered, so the storage watcher may already have been consumed before the route is
    // visible again. Publish a strictly monotonic refresh revision on page-show to force the retained shelf to
    // reload the committed Book snapshot without requiring a tab switch.
    if (this.currentIndex === 0) {
      const previousShelfUpdate = AppStorage.get<number>('shelfUpdateTime') || 0;
      AppStorage.setOrCreate('shelfUpdateTime', Math.max(Date.now(), previousShelfUpdate + 1));
    }
  }

  onAppDarkModeChanged(): void {
    this.hdsMaterialRenderBranch = !this.hdsMaterialRenderBranch;
    this.syncHomeSystemBars();
  }

  onLaunchShortcutChanged(): void {
    if (!this.shortcutRoutingActive) {
      return;
    }
    this.openPendingShortcut();
  }

  onPageHide(): void {
    this.shortcutRoutingActive = false;
  }

  aboutToDisappear(): void {
    this.stageRuntimeDisappearing = true;
    if (this.stageRuntimeAttachRetryId >= 0) clearTimeout(this.stageRuntimeAttachRetryId);
    this.stageRuntimeAttachRetryId = -1;
    BookSourceStageWebRuntime.get().clearResetHandler(this.stageRuntimeController);
    BookSourceStageWebRuntime.get().detach(this.stageRuntimeController);
  }

  private adoptStageRuntimeController(): void {
    if (this.stageRuntimeDisappearing) return;
    if (this.stageRuntimeAttachRetryId >= 0) clearTimeout(this.stageRuntimeAttachRetryId);
    this.stageRuntimeAttachRetryId = -1;
    BookSourceStageWebRuntime.get().attach(this.stageRuntimeController);
    BookSourceStageWebRuntime.get().setResetHandler((): void => this.resetStageRuntimeHost(),
      this.stageRuntimeController);
  }

  private scheduleStageRuntimeAttachFallback(attempt: number): void {
    if (this.stageRuntimeDisappearing) return;
    this.stageRuntimeAttachRetryId = setTimeout((): void => {
      if (this.stageRuntimeDisappearing) return;
      try {
        // A successful getWebId proves the controller is associated with a Web component. On
        // some routed/hidden Web nodes ArkWeb omits onControllerAttached — including nodes
        // rebuilt by resetStageRuntimeHost() — so treat this poll as the authoritative attach path.
        this.stageRuntimeController.getWebId();
        this.adoptStageRuntimeController();
        return;
      } catch (_) {}
      if (attempt < 100) this.scheduleStageRuntimeAttachFallback(attempt + 1);
    }, attempt === 0 ? 0 : 100);
  }

  resetStageRuntimeHost(): void {
    if (this.stageRuntimeResetScheduled) return;
    this.stageRuntimeResetScheduled = true;
    if (this.stageRuntimeAttachRetryId >= 0) clearTimeout(this.stageRuntimeAttachRetryId);
    this.stageRuntimeAttachRetryId = -1;
    const previous = this.stageRuntimeController;
    BookSourceStageWebRuntime.get().detach(previous);
    this.stageRuntimeMounted = false;
    // Let ArkUI commit the unmounted branch before constructing the replacement controller.
    setTimeout(() => {
      this.stageRuntimeController = new webview.WebviewController();
      this.stageRuntimeMounted = true;
      this.stageRuntimeResetScheduled = false;
      this.scheduleStageRuntimeAttachFallback(0);
    }, 50);
  }

  onSingleSourceSearchRequested(): void {
    const sourceUrl = AppStorage.get<string>('singleSourceSearchUrl') || '';
    if (!sourceUrl) {
      return;
    }
    this.bookshelfMultiSelectActive = false;
    this.currentIndex = 2;
    this.syncHomeSystemBars();
  }

  onGlobalSearchRequested(): void {
    const keyword = AppStorage.get<string>('globalSearchPendingKeyword') || '';
    if (!keyword.trim()) {
      return;
    }
    this.bookshelfMultiSelectActive = false;
    this.currentIndex = 2;
    this.syncHomeSystemBars();
  }

  onCurrentIndexChanged(): void {
    if (this.currentIndex === 1) {
      this.exploreTabMounted = true;
    }
    // 书架和“我的”在切走后销毁，重新进入时标题和底栏都从展开状态开始。
    if (this.currentIndex === 0 || this.currentIndex === 3) {
      this.tabHeaderCollapseProgress[this.currentIndex] = 0;
    }
    this.syncBottomBarCollapse();
  }

  onTabHeaderCollapseChange(index: number, progress: number): void {
    if (!Number.isFinite(progress)) return;
    this.tabHeaderCollapseProgress[index] = Math.max(0, Math.min(1, progress));
    if (index === this.currentIndex) {
      this.syncBottomBarCollapse();
    }
  }

  syncBottomBarCollapse(): void {
    this.bottomBarCollapseProgress = this.tabHeaderCollapseProgress[this.currentIndex] || 0;
    // 只移动导航栏，不改变内容区高度，避免列表在收起/展开时跳动。
    if (this.supportsImmersiveTabs()) {
      this.immersiveTabsController.setTabBarTranslate({
        y: (56 + this.floatingBarBottomMargin() + 16) * this.bottomBarCollapseProgress
      });
    } else {
      this.compatTabsController.setTabBarTranslate({
        y: (56 + this.compatTabSafeHeight()) * this.bottomBarCollapseProgress
      });
      this.compatTabsController.setTabBarOpacity(1 - this.bottomBarCollapseProgress);
    }
  }

  onBookSourceExploreRefreshRequested(): void {
    if (this.bookSourceExploreRefreshNonce <= 0) return;
    this.bookshelfMultiSelectActive = false;
    this.currentIndex = 1;
    this.syncHomeSystemBars();
  }

  onThemeRevisionChanged(): void {
    this.hdsMaterialRenderBranch = !this.hdsMaterialRenderBranch;
    this.syncHomeSystemBars();
  }

  onCloudSyncDataChanged(): void {
    if (this.cloudSyncDebounceTimer >= 0) {
      clearTimeout(this.cloudSyncDebounceTimer);
    }
    this.cloudSyncDebounceTimer = setTimeout(() => {
      this.cloudSyncDebounceTimer = -1;
      CloudSyncCoordinator.syncAutomatically(
        getContext(this), CloudSyncCoordinator.TRIGGER_CHANGE).catch((error: Error) => {
        console.warn('数据变更后自动同步失败:', error);
      });
    }, 15 * 1000);
  }

  onGlobalTtsActiveChanged(): void {
    if (!this.globalTtsActive) {
      this.showGlobalTtsPanel = false;
    }
  }

  onBackPress(): boolean {
    if (this.showGlobalTtsCatalog) {
      this.closeGlobalTtsCatalog();
      return true;
    }
    if (this.showGlobalTtsPanel) {
      this.closeGlobalTtsPanel();
      return true;
    }
    // 书架搜索栏开着时，返回键先清空关键词并收起它。
    if (this.currentIndex === 0 && AppStorage.get<boolean>('bookshelfSearchActive')) {
      AppStorage.setOrCreate('bookshelfSearchKeyword', '');
      AppStorage.setOrCreate('bookshelfSearchActive', false);
      return true;
    }
    if (this.currentIndex !== 0) {
      this.bookshelfMultiSelectActive = false;
      this.currentIndex = 0;
      this.syncHomeSystemBars();
      return true;
    }
    if (this.currentIndex === 0 && this.bookshelfActiveGroupId > 0) {
      this.bookshelfActiveGroupId = 0;
      return true;
    }
    return false;
  }

  openGlobalTtsPanel(): void {
    animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.showGlobalTtsPanel = true;
    });
  }

  closeGlobalTtsPanel(): void {
    this.showGlobalTtsCatalog = false;
    animateTo({ duration: 190, curve: Curve.EaseIn }, () => {
      this.showGlobalTtsPanel = false;
    });
  }

  /**
   * 后台朗读的阅读页已离开路由栈，这里按书架直接打开的方式重新进入正文；
   * 新阅读页会作为镜像接上正在进行的朗读。
   */
  openGlobalTtsReader(): void {
    const bookUrl = AppStorage.get<string>('globalTtsBookUrl') || '';
    if (!bookUrl) {
      HdsFeedback.showToast('暂未获取到朗读中的书籍');
      return;
    }
    this.closeGlobalTtsPanel();
    ReaderOpenTrace.begin(bookUrl);
    AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', true);
    ReaderOpenTrace.mark(bookUrl, 'direct-open');
    ReaderOpenTrace.mark(bookUrl, 'route-requested');
    router.pushUrl({
      url: 'pages/ReadBook',
      params: {
        bookUrl: bookUrl,
        shelfBookOpening: 'false'
      }
    }).catch((error: Error) => {
      AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
      console.error('从朗读面板回到正文失败:', error);
      ReaderOpenTrace.cancel(bookUrl, 'route-failed');
    });
  }

  openGlobalTtsCatalog(): void {
    const titles = ReaderTtsFloatingSession.catalogTitles();
    if (titles.length === 0) {
      HdsFeedback.showToast('暂未获取到听书目录');
      return;
    }
    this.globalTtsCatalogSource.replace(this.globalTtsCatalogReverseOrder ? titles.slice().reverse() : titles);
    this.openGlobalTtsCatalogWithFreshCacheFlags();
  }

  /**
   * The shelf holds no chapter list of its own, so the cache snapshot is rebuilt
   * from the database before the sheet appears — otherwise the chips would show
   * whatever the publishing page last reported.
   */
  private openGlobalTtsCatalogWithFreshCacheFlags(): void {
    const ownerId = ReaderTtsFloatingSession.currentOwnerId();
    const bookUrl = AppStorage.get<string>('globalTtsBookUrl') || '';
    if (!ownerId || !bookUrl) {
      this.presentGlobalTtsCatalog();
      return;
    }
    AppDatabase.getInstance().getBookChapters(bookUrl)
      .then((chapters: BookChapter[]): void => {
        ReaderTtsFloatingSession.updateCatalogCachedFlags(ownerId, this.chapterCachedFlagsOf(chapters));
        this.presentGlobalTtsCatalog();
      })
      .catch((error: Error) => {
        console.warn('刷新听书目录缓存标记失败:', error);
        this.presentGlobalTtsCatalog();
      });
  }

  private presentGlobalTtsCatalog(): void {
    animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.showGlobalTtsCatalog = true;
    });
    setTimeout(() => {
      if (!this.showGlobalTtsCatalog) return;
      try {
        this.globalTtsCatalogScroller.scrollToIndex(
          this.globalTtsCatalogDisplayIndex(ReaderTtsFloatingSession.catalogIndex()), false, ScrollAlign.CENTER);
      } catch (_) {}
    }, 0);
  }

  /**
   * Positional, to line up with how every publisher builds the titles array
   * (`chapters.map(title)`) — the rest of the reader treats array position as the
   * canonical chapter index too.
   */
  private chapterCachedFlagsOf(chapters: BookChapter[]): boolean[] {
    const flags: boolean[] = [];
    for (let index = 0; index < chapters.length; index++) {
      flags.push(chapters[index].cacheDate > 0);
    }
    return flags;
  }

  closeGlobalTtsCatalog(): void {
    animateTo({ duration: 210, curve: Curve.EaseIn }, () => {
      this.showGlobalTtsCatalog = false;
    });
  }

  onGlobalTtsCatalogOrderChanged(): void {
    const titles = ReaderTtsFloatingSession.catalogTitles();
    if (titles.length === 0) return;
    this.globalTtsCatalogSource.replace(this.globalTtsCatalogReverseOrder ? titles.slice().reverse() : titles);
    this.scrollGlobalTtsCatalogToCurrent();
  }

  selectGlobalTtsCatalog(index: number): void {
    this.closeGlobalTtsCatalog();
    ReaderTtsFloatingSession.selectCatalogIndex(this.globalTtsCatalogCanonicalIndex(index));
  }

  globalTtsCatalogCanonicalIndex(displayIndex: number): number {
    const count = ReaderTtsFloatingSession.catalogCount();
    return this.globalTtsCatalogReverseOrder ? count - 1 - displayIndex : displayIndex;
  }

  globalTtsCatalogDisplayIndex(canonicalIndex: number): number {
    const count = ReaderTtsFloatingSession.catalogCount();
    return this.globalTtsCatalogReverseOrder ? count - 1 - canonicalIndex : canonicalIndex;
  }

  toggleGlobalTtsCatalogOrder(): void {
    this.globalTtsCatalogReverseOrder = !this.globalTtsCatalogReverseOrder;
  }

  scrollGlobalTtsCatalogToCurrent(): void {
    setTimeout(() => {
      if (!this.showGlobalTtsCatalog) return;
      try {
        this.globalTtsCatalogScroller.scrollToIndex(
          this.globalTtsCatalogDisplayIndex(ReaderTtsFloatingSession.catalogIndex()), false, ScrollAlign.CENTER);
      } catch (_) {}
    }, 0);
  }

  globalTtsCapsuleTransition(): TransitionEffect {
    const appear = TransitionEffect.scale({ x: 0.84, y: 0.84, centerX: '50%', centerY: '50%' })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 240, curve: Curve.Friction });
    const disappear = TransitionEffect.scale({ x: 0.9, y: 0.9, centerX: '50%', centerY: '50%' })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 170, curve: Curve.EaseIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  globalTtsPanelTransition(): TransitionEffect {
    const appear = TransitionEffect.translate({ y: 52 })
      .combine(TransitionEffect.scale({ x: 0.985, y: 0.985, centerX: '50%', centerY: '100%' }))
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 300, curve: Curve.Friction });
    const disappear = TransitionEffect.translate({ y: 28 })
      .combine(TransitionEffect.scale({ x: 0.99, y: 0.99, centerX: '50%', centerY: '100%' }))
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 190, curve: Curve.EaseIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  async openPendingShortcut(): Promise<void> {
    if (!RecentReadShortcut.isPending()) {
      return;
    }
    try {
      await RecentReadShortcut.openPending(getContext(this));
    } catch (e) {
      console.error('打开最近阅读快捷项失败:', e);
    }
  }

  pageTransition() {
    if (AppStorage.get<boolean>('shelfReaderDirectTransition') === true) {
      PageTransitionExit({ type: RouteType.Push, duration: 0 })
    }
  }

  build() {
    Stack() {
      if (this.supportsImmersiveTabs()) {
        if (this.hdsMaterialRenderBranch) {
          this.immersiveTabs()
        } else {
          this.immersiveTabs()
        }
      } else {
        this.compatTabs()
      }
      if (this.globalTtsActive && !this.showGlobalTtsPanel) {
        this.globalTtsMiniPlayer()
      }
      if (this.globalTtsActive && this.showGlobalTtsPanel) {
        ReaderTtsPlayerPanel({
          darkMode: this.appDarkMode,
          accentColor: this.tabBarActiveColor(),
          playButtonColor: ThemeRuntime.buttonColor(this.appDarkMode),
          primaryTextColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
          subTextColor: ThemeRuntime.subTextColor(this.appDarkMode),
          panelColor: ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'),
          backgroundThemeId: ThemeRuntime.ttsPanelThemeId(this.appDarkMode),
          topInset: this.statusBarHeight,
          bottomInset: this.navBarHeight,
          viewportHeight: this.globalTtsViewportHeight,
          onClose: () => this.closeGlobalTtsPanel(),
          onOpenCatalog: () => this.openGlobalTtsCatalog(),
          showOpenReader: this.globalTtsMode !== 'audio',
          onOpenReader: () => this.openGlobalTtsReader()
        })
      }
      if (this.globalTtsActive && this.showGlobalTtsPanel && this.showGlobalTtsCatalog) {
        this.globalTtsCatalogOverlay()
      }
      if (this.stageRuntimeMounted && WebRuntimeAvailability.isAvailable()) {
        Web({ src: 'about:blank', controller: this.stageRuntimeController })
          .width(1)
          .height(1)
          .opacity(0.01)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .mixedMode(MixedMode.All)
          .onControllerAttached(() => {
            this.adoptStageRuntimeController();
          })
          .onPageBegin(() => {
            BookSourceStageWebRuntime.get().setReady(false, this.stageRuntimeController);
          })
          .onPageEnd(() => {
            BookSourceStageWebRuntime.get().setReady(true, this.stageRuntimeController);
          })
      }
      WebBookFetchRuntimeHost()
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = typeof newValue.width === 'number' ? newValue.width : Number.parseFloat(`${newValue.width}`);
      const height = typeof newValue.height === 'number' ? newValue.height : Number.parseFloat(`${newValue.height}`);
      if (Number.isFinite(width) && width > 0) this.globalTtsViewportWidth = width;
      if (Number.isFinite(height) && height > 0) this.globalTtsViewportHeight = height;
    })
  }

  @Builder
  globalTtsMiniPlayer() {
    Row({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.SM }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle().width(30).height(30).fill(this.tabBarActiveColor())
          SymbolGlyph($r('sys.symbol.speaker_wave_3'))
            .fontSize(15)
            .fontColor(['#FFFFFF'])
        }
        Column({ space: 1 }) {
          Text(this.globalTtsBusy ? '加载中' :
            (this.globalTtsPaused ? '已暂停' : (this.globalTtsMode === 'audio' ? '听书中' : '朗读中')))
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          Text(this.globalTtsChapterProgress || (this.globalTtsMode === 'audio' ? '后台听书' : '后台朗读'))
            .fontSize(9)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .onClick(() => this.openGlobalTtsPanel())
      SymbolGlyph(this.globalTtsPaused ? $r('sys.symbol.play') : $r('sys.symbol.pause'))
        .id(`global_tts_capsule_playback_${this.globalTtsPaused}`)
        .fontSize(17)
        .fontColor([ThemeRuntime.primaryTextColor(this.appDarkMode)])
        .width(28)
        .height(34)
        .onClick(() => ReaderTtsFloatingSession.toggle())
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(14)
        .fontColor([ThemeRuntime.subTextColor(this.appDarkMode)])
        .width(24)
        .height(34)
        .onClick(() => {
          this.closeGlobalTtsPanel();
          ReaderTtsFloatingSession.stop();
        })
    }
    .width(184)
    .height(46)
    .padding({ left: AppSpacing.MD, right: AppSpacing.XS })
    .borderRadius(23)
    .clip(true)
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
    .border({ width: 0.5, color: this.appDarkMode ? '#30FFFFFF' : '#18000000' })
    .shadow({ radius: 18, color: this.appDarkMode ? '#50000000' : '#26000000', offsetY: 6 })
    .position({ x: 0, y: 0 })
    .translate({
      x: this.globalTtsCapsuleLeft(),
      y: this.globalTtsCapsuleTop()
    })
    .parallelGesture(
      PanGesture({ direction: PanDirection.All, distance: 4 })
        .onActionStart(() => {
          this.globalTtsDragOriginX = this.globalTtsCapsuleLeft();
          this.globalTtsDragOriginY = this.globalTtsCapsuleTop();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.globalTtsCapsulePositionX = this.clampGlobalTtsPositionX(
            this.globalTtsDragOriginX + event.offsetX);
          this.globalTtsCapsulePositionY = this.clampGlobalTtsPositionY(
            this.globalTtsDragOriginY + event.offsetY);
        })
    )
    .transition(this.globalTtsCapsuleTransition())
  }

  globalTtsCapsuleLeft(): number {
    return this.clampGlobalTtsPositionX(this.globalTtsCapsulePositionX);
  }

  globalTtsCapsuleTop(): number {
    const defaultTop = this.globalTtsViewportHeight - this.navBarHeight - 118;
    return this.clampGlobalTtsPositionY(this.globalTtsCapsulePositionY < 0 ?
      defaultTop : this.globalTtsCapsulePositionY);
  }

  clampGlobalTtsPositionX(position: number): number {
    const minLeft = 8;
    const maxLeft = Math.max(minLeft, this.globalTtsViewportWidth - 184 - 8);
    return Math.max(minLeft, Math.min(position, maxLeft));
  }

  clampGlobalTtsPositionY(position: number): number {
    const minTop = this.statusBarHeight + 8;
    const maxTop = Math.max(minTop, this.globalTtsViewportHeight - this.navBarHeight - 110);
    return Math.max(minTop, Math.min(position, maxTop));
  }

  @Builder
  globalTtsCatalogOverlay() {
    TtsCatalogSheet({
      bookUrl: this.globalTtsBookUrl,
      darkMode: this.appDarkMode,
      accentColor: this.tabBarActiveColor(),
      primaryTextColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
      subTextColor: ThemeRuntime.subTextColor(this.appDarkMode),
      controlIconColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
      panelColor: ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'),
      bookName: this.globalTtsBookName,
      bookInitial: this.globalTtsCatalogInitial(),
      cover: this.globalTtsCover,
      // The shelf only receives the book name and cover with the TTS session, so the
      // subtitle falls back to the chapter being played instead of the author.
      bookSubtitle: this.globalTtsChapterTitle,
      count: ReaderTtsFloatingSession.catalogCount(),
      currentDisplayIndex: this.globalTtsCatalogDisplayIndex(ReaderTtsFloatingSession.catalogIndex()),
      reverseOrder: this.globalTtsCatalogReverseOrder,
      progressText: `${ReaderTtsFloatingSession.catalogIndex() + 1} / ` +
        `${ReaderTtsFloatingSession.catalogCount()}`,
      bottomInset: this.navBarHeight,
      viewportHeight: this.globalTtsViewportHeight,
      zIndexValue: 80,
      scroller: this.globalTtsCatalogScroller,
      source: this.globalTtsCatalogSource,
      isCached: (displayIndex: number): boolean => this.isGlobalTtsCatalogChapterCached(displayIndex),
      onToggleOrder: () => this.toggleGlobalTtsCatalogOrder(),
      onSelect: (displayIndex: number) => this.selectGlobalTtsCatalog(displayIndex),
      onClose: () => this.closeGlobalTtsCatalog()
    })
  }

  globalTtsCatalogInitial(): string {
    const name = (this.globalTtsBookName || '书').trim();
    return name.length > 0 ? name.substring(0, 1) : '书';
  }

  isGlobalTtsCatalogChapterCached(displayIndex: number): boolean {
    return ReaderTtsFloatingSession.catalogCachedFlag(this.globalTtsCatalogCanonicalIndex(displayIndex));
  }

  /** 页签内容的进入转场：淡入并从切换方向一侧轻微滑入；离开时直接隐藏。 */
  homeTabEnterTransition(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.opacity(0)
        .combine(TransitionEffect.translate({ x: this.homeTabEnterOffset }))
        .animation({ duration: Index.TAB_ENTER_DURATION, curve: Curve.Friction }),
      TransitionEffect.IDENTITY
    );
  }

  supportsImmersiveTabs(): boolean {
    return ImmersiveMaterialRuntime.supportsHdsTabs();
  }

  immersiveTabsBarBackgroundColor(): ResourceColor {
    return this.supportsImmersiveTabs() ? Color.Transparent :
      ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel');
  }

  @Builder
  immersiveTabs() {
    HdsTabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.immersiveTabsController }) {
      TabContent() {
        if (this.currentIndex === 0) {
          BookshelfPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isBookMultiSelect: $bookshelfMultiSelectActive,
            activeShelfGroupId: $bookshelfActiveGroupId,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(0, progress)
          })
            .transition(this.homeTabEnterTransition())
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar(this.navigationIcon('bookshelf'), '书架'))

      TabContent() {
        if (this.exploreTabMounted) {
          ExplorePage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isActive: this.currentIndex === 1,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(1, progress)
          })
            .transition(this.homeTabEnterTransition())
            // 常驻后切回来不会再触发出现转场，与搜索页一样用隐式动画做进入效果。
            .opacity(this.currentIndex === 1 ? 1 : 0)
            .translate({ x: this.currentIndex === 1 ? 0 : this.homeTabEnterOffset })
            .animation({ duration: Index.TAB_ENTER_DURATION, curve: Curve.Friction })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar(this.navigationIcon('explore'), '发现'))

      TabContent() {
        SearchPage({
          statusBarHeight: this.statusBarHeight,
          navBarHeight: this.navBarHeight,
          isActive: this.currentIndex === 2,
          onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(2, progress)
        })
          // 搜索页常驻不重建，没有出现转场，用透明度和位移的隐式动画做同样的进入效果。
          .opacity(this.currentIndex === 2 ? 1 : 0)
          .translate({ x: this.currentIndex === 2 ? 0 : this.homeTabEnterOffset })
          .animation({ duration: Index.TAB_ENTER_DURATION, curve: Curve.Friction })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar(this.navigationIcon('search'), '搜索'))

      TabContent() {
        if (this.currentIndex === 3) {
          SettingsPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(3, progress)
          })
            .transition(this.homeTabEnterTransition())
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .align(Alignment.TopStart)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar(this.navigationIcon('mine'), '我的'))
    }
    .key(`home_immersive_tabs_${this.themeRevision}_${this.appDarkMode ? 'dark' : 'light'}`)
    .barBackgroundColor(this.immersiveTabsBarBackgroundColor())
    .barMode(BarMode.Fixed)
    .barHeight(this.bookshelfMultiSelectActive ? 0 : 56)
    .barOverlap(true)
    .borderRadius(30)
    .clip(true)
    .barFloatingStyle({
      systemMaterialEffect: {
        materialType: ImmersiveMaterialRuntime.materialType(),
        materialLevel: ImmersiveMaterialRuntime.materialLevel()
      },
      barBottomMargin: this.floatingBarBottomMargin(),
      gradientMask: {
        maskColor: Color.Transparent,
        maskHeight: 96
      },
      adaptToHandedness: true,
      thermoCtrl: true,
      barOpacity: this.bookshelfMultiSelectActive ? 0 : 1 - this.bottomBarCollapseProgress
    })
    .scrollable(false)
    .onAppear(() => this.syncBottomBarCollapse())
    .onChange((index: number) => {
      this.homeTabEnterOffset = index >= this.currentIndex ? Index.TAB_ENTER_DISTANCE : -Index.TAB_ENTER_DISTANCE;
      this.currentIndex = index;
      this.syncHomeSystemBars();
    })
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  compatTabs() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.compatTabsController }) {
      TabContent() {
        if (this.currentIndex === 0) {
          BookshelfPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isBookMultiSelect: $bookshelfMultiSelectActive,
            activeShelfGroupId: $bookshelfActiveGroupId,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(0, progress)
          })
            .transition(this.homeTabEnterTransition())
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar(this.navigationIcon('bookshelf'), '书架', 0))

      TabContent() {
        if (this.exploreTabMounted) {
          ExplorePage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isActive: this.currentIndex === 1,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(1, progress)
          })
            .transition(this.homeTabEnterTransition())
            // 常驻后切回来不会再触发出现转场，与搜索页一样用隐式动画做进入效果。
            .opacity(this.currentIndex === 1 ? 1 : 0)
            .translate({ x: this.currentIndex === 1 ? 0 : this.homeTabEnterOffset })
            .animation({ duration: Index.TAB_ENTER_DURATION, curve: Curve.Friction })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar(this.navigationIcon('explore'), '发现', 1))

      TabContent() {
        SearchPage({
          statusBarHeight: this.statusBarHeight,
          navBarHeight: this.navBarHeight,
          isActive: this.currentIndex === 2,
          onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(2, progress)
        })
          // 搜索页常驻不重建，没有出现转场，用透明度和位移的隐式动画做同样的进入效果。
          .opacity(this.currentIndex === 2 ? 1 : 0)
          .translate({ x: this.currentIndex === 2 ? 0 : this.homeTabEnterOffset })
          .animation({ duration: Index.TAB_ENTER_DURATION, curve: Curve.Friction })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar(this.navigationIcon('search'), '搜索', 2))

      TabContent() {
        if (this.currentIndex === 3) {
          SettingsPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(3, progress)
          })
            .transition(this.homeTabEnterTransition())
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .align(Alignment.TopStart)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar(this.navigationIcon('mine'), '我的', 3))
    }
    .barMode(BarMode.Fixed)
    .barHeight(this.bookshelfMultiSelectActive ? 0 : 56 + this.compatTabSafeHeight())
    .barBackgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
    .scrollable(false)
    .onAppear(() => this.syncBottomBarCollapse())
    .onChange((index: number) => {
      this.homeTabEnterOffset = index >= this.currentIndex ? Index.TAB_ENTER_DISTANCE : -Index.TAB_ENTER_DISTANCE;
      this.currentIndex = index;
      this.syncHomeSystemBars();
    })
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  bottomTabBar(icon: Resource, title: string): BottomTabBarStyle {
    return BottomTabBarStyle.of(icon, title)
      .labelStyle({
        font: { size: 11 },
        selectedColor: this.tabBarActiveColor(),
        unselectedColor: this.tabBarTextColor()
      })
      .iconStyle({
        selectedColor: this.tabBarActiveColor(),
        unselectedColor: this.tabBarTextColor()
      })
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: 0, bottom: 0 })
      .layoutMode(LayoutMode.VERTICAL)
      .verticalAlign(VerticalAlign.Center);
  }

  @Builder
  compatTabBar(icon: Resource, title: string, index: number) {
    Column() {
      Column({ space: AppSpacing.XXS }) {
        Column() {
          Image(icon)
            .width(22)
            .height(22)
            .fillColor(this.currentIndex === index ? this.tabBarActiveColor() : this.tabBarTextColor())
        }
        .width(24)
        .height(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text(title)
          .fontSize(AppFontSize.MICRO)
          .lineHeight(14)
          .height(14)
          .fontColor(this.currentIndex === index ? this.tabBarActiveColor() : this.tabBarTextColor())
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height(56 + this.compatTabSafeHeight())
    .padding({ bottom: this.compatTabSafeHeight() })
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  syncHomeSystemBars(): void {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      const bg = ThemeRuntime.pageColor(this.appDarkMode);
      mainWindow.setWindowBackgroundColor(bg);
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
      syncSystemSafeAreas(mainWindow);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        isStatusBarLightIcon: this.appDarkMode,
        statusBarContentColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
        navigationBarColor: '#00000000',
        isNavigationBarLightIcon: this.appDarkMode,
        navigationBarContentColor: ThemeRuntime.primaryTextColor(this.appDarkMode)
      });
    }).catch((err: Error) => {
      console.error('同步首页系统栏颜色失败:', err);
    });
  }

  tabBarActiveColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  tabBarTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  navigationIcon(tabId: string): Resource {
    return ThemeAssetRegistry.navigationIcon(ThemeRuntime.iconPackId(), tabId);
  }

  floatingBarBottomMargin(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 8;
  }

  compatTabSafeHeight(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 24;
  }

}
