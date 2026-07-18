import { router, window, promptAction, MeasureOptions } from '@kit.ArkUI';
import { common, ConfigurationConstant, WantAgent, wantAgent } from '@kit.AbilityKit';
import { inputConsumer, KeyCode, Action, KeyEvent } from '@kit.InputKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import { notificationManager } from '@kit.NotificationKit';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import graphicsText from '@ohos.graphics.text';
import deviceInfo from '@ohos.deviceInfo';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { Book, BookChapter, Bookmark, BookSource, SearchBook, HttpTTS } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { ReadBookEngine } from '../core/book/ReadBookEngine';
import { LocalBookService } from '../core/book/LocalBookService';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { WebBookService } from '../core/book/WebBookService';
import { VerificationSupport } from '../core/http/VerificationSupport';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { SystemTtsReader, TtsChunk, TtsVoiceOption } from '../utils/SystemTtsReader';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderReplaceRule, ReaderReplaceRuleStore } from '../utils/ReaderReplaceRuleStore';
import { ReaderThemeHelper, ReaderThemeItem } from '../utils/ReaderThemeHelper';
import { ReaderCustomThemeData, ReaderCustomThemeHelper, ReaderCustomThemeScheme } from '../utils/ReaderCustomThemeHelper';
import { ReaderBackgroundImageStore } from '../utils/ReaderBackgroundImageStore';
import { ColorCodePicker } from '../components/ColorCodePicker';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { BookFieldSanitizer } from '../utils/BookFieldSanitizer';
import { CoverUrlNormalizer } from '../utils/CoverUrlNormalizer';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { ChangeSourceResultCache } from '../utils/ChangeSourceResultCache';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { BookCoverCache } from '../utils/BookCoverCache';
import { CoverGallerySettings } from '../utils/CoverGallerySettings';
import { AppThemeModeStore } from '../utils/AppThemeModeStore';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderRegexFontCodec,
  ReaderRegexFontRule,
  ReaderRegexLegacySettings,
  ReaderResolvedRegexEmphasis
} from '../model/reader/ReaderRegexFontRule';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';

const TOC_WINDOW_PAGE_SIZE = 72;

interface ReadTextSlice {
  text: string;
  start: number;
  end: number;
  highlighted: boolean;
  ruleIndex: number;
  ttsHighlighted?: boolean;
  key: string;
}

interface ReaderTextParagraph {
  text: string;
  start: number;
  end: number;
  index: number;
  isLast: boolean;
  key: string;
}

interface ReaderPaginationResult {
  source: string;
  pages: string[];
  starts: number[];
  ends: number[];
}

interface ReaderParagraphMeasureFallback {
  fontSize: number;
  fontFamily: string;
}

class ReaderCustomFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class ReaderCustomFontData {
  fonts: ReaderCustomFontItem[] = [];
}

interface PageTurnPreview {
  text: string;
  secondaryText?: string;
  pageIndex: number;
  chapterIndex: number;
}

@Entry
@Component
struct ReadBookPage {
  @State bookUrl: string = '';
  @State book: Book | null = null;
  @State chapters: BookChapter[] = [];
  @State tocVisibleChapters: BookChapter[] = [];
  @State tocWindowStart: number = 0;
  @State tocQuickJumpArmed: boolean = false;
  @State tocQuickJumpInputVisible: boolean = false;
  @State tocQuickJumpDraft: string = '';
  @State currentChapterIndex: number = 0;
  @State menuChapterPreviewIndex: number = 0;
  @State menuChapterSliderActive: boolean = false;
  @State menuChapterTooltipVisible: boolean = false;
  @State menuChapterConfirming: boolean = false;
  @State content: string = '';
  @State readerReplaceRules: ReaderReplaceRule[] = [];
  @State isLoading: boolean = true;
  @State showMenu: boolean = false;
  @State showReaderActionMenu: boolean = false;
  @State showToc: boolean = false;
  @State tocPanelTab: number = 0;
  @State bookmarks: Bookmark[] = [];
  @State bookmarkMultiSelectMode: boolean = false;
  @State selectedBookmarkIds: number[] = [];
  @State showBookmarkActionMenu: boolean = false;
  @State pendingBookmarkAction: Bookmark | null = null;
  @State bookmarkActionMenuX: number = 16;
  @State bookmarkActionMenuY: number = 96;
  @State showSettings: boolean = false;
  @State showTapZoneSettings: boolean = false;
  @State settingsPanelTab: number = 0;
  @State quickTypographySettingIndex: number = 0;
  @State showQuickTypographyValueInput: boolean = false;
  @State quickTypographyValueDraft: string = '';
  @State loadStatus: string = '正在加载...';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '网页验证';
  @State showChangeSourceDialog: boolean = false;
  @State changeSourceResults: SearchBook[] = [];
  @State isChangingSource: boolean = false;
  @State isSwitchingSource: boolean = false;
  @State changeSourceStatus: string = '';
  @State contentPages: string[] = [];
  @State currentPageIndex: number = 0;
  @State currentPageText: string = '';
  @State displayPageText: string = '';
  @State displayPageChapterIndex: number = 0;
  @State displayPageIndex: number = 0;
  @State displayPageRenderKey: number = 0;
  @State pageRenderVersion: number = 0;
  @State chapterJumpRenderGeneration: number = 0;
  @State pageViewWidth: number = 0;
  @State pageViewHeight: number = 0;
  @State readerInitialPageReady: boolean = false;
  @State statusBarSafeHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State isTtsSpeaking: boolean = false;
  @State ttsMediaControlsExpanded: boolean = false;
  @State ttsMediaImage: string = '';
  @State ttsDisplayText: string = '';
  @State ttsHighlightStart: number = -1;
  @State ttsHighlightEnd: number = -1;
  @State ttsHighlightRenderVersion: number = 0;
  @State ttsSleepTimerMinutes: number = 0;
  @State ttsSleepTimerRemainingSeconds: number = 0;
  private pendingRestorePageIndex: number = -1;
  private tocScroller: Scroller = new Scroller();
  private tocLoadingPreviousPage: boolean = false;
  private tocLoadingNextPage: boolean = false;
  private bookmarkScroller: ListScroller = new ListScroller();
  private ttsReader: SystemTtsReader = new SystemTtsReader();
  private ttsAutoContinue: boolean = false;
  private ttsReadToken: number = 0;
  private ttsTextStartOffset: number = 0;
  private ttsLastFocusChunk: TtsChunk | null = null;
  private ttsLastFocusPageIndex: number = -1;
  private ttsResumeSyncSerial: number = 0;
  private ttsAutoTurningPage: boolean = false;
  private ttsPageTurnSerial: number = 0;
  private ttsPendingTargetPageIndex: number = -1;
  private ttsPendingHighlightChunk: TtsChunk | null = null;
  private ttsBackgroundRunning: boolean = false;
  private ttsBackgroundRequesting: boolean = false;
  private ttsBackgroundDesired: boolean = false;
  private ttsBackgroundHeartbeatId: number = -1;
  private ttsBackgroundLastLogAt: number = 0;
  private ttsAvSession: avSession.AVSession | null = null;
  private ttsAvSessionRequesting: boolean = false;
  private ttsSpeedSaveTimerId: number = -1;
  private ttsSpeedAvSessionTimerId: number = -1;
  private ttsSleepTimerId: number = -1;
  private ttsSleepTimerEndAt: number = 0;
  private ttsMediaImageRefreshSerial: number = 0;
  private ttsMediaImageRaw: string = '';
  private ttsMediaPixelMap: image.PixelMap | null = null;
  private contentPageStarts: number[] = [];
  private contentPageEnds: number[] = [];
  private pagedContentText: string = '';
  private readerPaginationCache: Map<string, ReaderPaginationResult> = new Map();
  private cachedRegexRulesKey: string = '';
  private cachedRegexRules: ReaderRegexFontRule[] = [];
  private cachedDocumentRegexSource: string = '';
  private cachedDocumentRegexRulesKey: string = '';
  private cachedDocumentRegexSlices: ReadTextSlice[] = [];
  private adjacentPaginationPreloadSerial: number = 0;
  private pageTurnPreviewKey: string = '';
  private pageTurnPreviewLoadingKey: string = '';
  @State pageTransitionX: number = 0;
  @State pageTransitionOpacity: number = 1;
  @State pageSlideOffsetX: number = 0;
  @State pageSlideOffsetY: number = 0;
  @State bookmarkPullOffsetY: number = 0;
  @State bookmarkPullActive: boolean = false;
  @State bookmarkPullReady: boolean = false;
  @State pageSlideDirection: number = 0;
  @State pageTurnAnimating: boolean = false;
  @State pageTurnIncomingText: string = '';
  @State pageTurnIncomingSecondaryText: string = '';
  @State pageTurnIncomingX: number = 0;
  @State pageTurnIncomingOpacity: number = 1;
  @State pageTurnIncomingPageIndex: number = 0;
  @State pageTurnIncomingChapterIndex: number = 0;
  @State pageTurnIncomingRenderVersion: number = 0;
  private bookLoadSerial: number = 0;
  private contentLoadSerial: number = 0;
  private isPageTurning: boolean = false;
  private changeSourceSessionId: number = 0;
  private activeChangeSourceCoordinator: SearchCoordinator | null = null;
  private lastRecentReadCardReloadAt: number = 0;
  private lastRecentReadCardChapterIndex: number = -1;
  private readerTouchStartX: number = 0;
  private readerTouchStartY: number = 0;
  private readerTouchLastX: number = 0;
  private readerTouchLastY: number = 0;
  private readerTouchActive: boolean = false;
  private readerTouchMoved: boolean = false;
  private suppressReaderTapClick: boolean = false;
  private readerTapSlop: number = 12;
  private readerPanActive: boolean = false;
  private slideResetSerial: number = 0;
  @StorageLink('readerFontSize') @Watch('onReadLayoutChanged') readerFontSize: number = 20;
  @StorageLink('readerLineHeight') @Watch('onReadLayoutChanged') readerLineHeight: number = 12;
  @StorageLink('readerParagraphSpacing') @Watch('onReadLayoutChanged') readerParagraphSpacing: number = 10;
  @StorageLink('readerMarginLeft') @Watch('onReadLayoutChanged') readerMarginLeft: number = 18;
  @StorageLink('readerMarginRight') @Watch('onReadLayoutChanged') readerMarginRight: number = 18;
  @StorageLink('readerMarginTop') @Watch('onReadLayoutChanged') readerMarginTop: number = 18;
  @StorageLink('readerMarginBottom') @Watch('onReadLayoutChanged') readerMarginBottom: number = 18;
  @StorageLink('readerLightThemeIndex') @Watch('onReaderThemeChanged') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') @Watch('onReaderThemeChanged') readerDarkThemeIndex: number = 0;
  @StorageLink('readerLightCustomThemeBackgroundColor') @Watch('onReaderThemeChanged') readerLightCustomThemeBackgroundColor: string = ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerLightCustomThemeTextColor') @Watch('onReaderThemeChanged') readerLightCustomThemeTextColor: string = ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR;
  @StorageLink('readerDarkCustomThemeBackgroundColor') @Watch('onReaderThemeChanged') readerDarkCustomThemeBackgroundColor: string = ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerDarkCustomThemeTextColor') @Watch('onReaderThemeChanged') readerDarkCustomThemeTextColor: string = ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR;
  @StorageLink('readerCustomThemesRaw') @Watch('onReaderThemeChanged') readerCustomThemesRaw: string = '';
  @State customThemeNameDraft: string = '';
  @StorageLink('readerPageTurnMode') readerPageTurnMode: number = 1;
  @StorageLink('readerPageTurnAnimationType') @Watch('onReaderPageTurnAnimationChanged') readerPageTurnAnimationType: number = ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
  @StorageLink('readerLandscapeDoublePage') @Watch('onReaderLandscapeDoublePageChanged') readerLandscapeDoublePage: boolean = false;
  @StorageLink('readerTapZoneActions') readerTapZoneActions: string = '3,3,3,3,1,2,2,2,2';
  @StorageLink('readerVolumeTurnPage') @Watch('onReaderVolumeTurnPageChanged') readerVolumeTurnPage: boolean = false;
  @StorageLink('readerKeepScreenOn') readerKeepScreenOn: boolean = true;
  @StorageLink('readerExtendToStatusBar') @Watch('onReaderExtendToStatusBarChanged') readerExtendToStatusBar: boolean = false;
  @StorageLink('readerPreloadEnabled') @Watch('onReaderPreloadChanged') readerPreloadEnabled: boolean = true;
  @StorageLink('readerPreloadChapterCount') @Watch('onReaderPreloadChanged') readerPreloadChapterCount: number = 1;
  @StorageLink('readerReplaceRulesUpdateTime') @Watch('onReaderReplaceRulesChanged') readerReplaceRulesUpdateTime: number = 0;
  @StorageLink('readerFontFamily') @Watch('onReaderFontChanged') readerFontFamily: string = '';
  @StorageLink('readerFontFilePath') @Watch('onReaderFontChanged') readerFontFilePath: string = '';
  @StorageLink('readerSystemFontFamily') @Watch('onReaderActiveFontChanged') readerSystemFontFamily: string = '';
  @StorageLink('readerActiveFontFamily') @Watch('onReaderActiveFontChanged') readerActiveFontFamily: string = '';
  @StorageLink('readerFontRegistered') @Watch('onReaderActiveFontChanged') readerStoredFontRegistered: boolean = false;
  @StorageLink('readerBodyFontMode') @Watch('onReaderFontStyleChanged') readerBodyFontMode: string = 'global';
  @StorageLink('readerBodyFontFamily') @Watch('onReaderFontStyleChanged') readerBodyFontFamily: string = '';
  @StorageLink('readerTitleFontMode') @Watch('onReaderFontStyleChanged') readerTitleFontMode: string = 'global';
  @StorageLink('readerTitleFontFamily') @Watch('onReaderFontStyleChanged') readerTitleFontFamily: string = '';
  @StorageLink('readerTitleFontSize') @Watch('onReaderFontStyleChanged') readerTitleFontSize: number = 22;
  @StorageLink('readerRegexFontEnabled') @Watch('onReaderFontStyleChanged') readerRegexFontEnabled: boolean = false;
  @StorageLink('readerRegexFontPattern') @Watch('onReaderFontStyleChanged') readerRegexFontPattern: string = '';
  @StorageLink('readerRegexFontMode') @Watch('onReaderFontStyleChanged') readerRegexFontMode: string = 'global';
  @StorageLink('readerRegexFontFamily') @Watch('onReaderFontStyleChanged') readerRegexFontFamily: string = '';
  @StorageLink('readerRegexFontSize') @Watch('onReaderFontStyleChanged') readerRegexFontSize: number = 20;
  @StorageLink('readerRegexShadowColor') @Watch('onReaderFontStyleChanged') readerRegexShadowColor: string = '';
  @StorageLink('readerRegexFontRulesRaw') @Watch('onReaderFontStyleChanged') readerRegexFontRulesRaw: string = '';
  @State activeReaderFontFamily: string = '';
  @State readerFontRegistered: boolean = false;
  @State readerFontRenderReady: boolean = false;
  @StorageLink('appDarkMode') @Watch('onReaderThemeChanged') appDarkMode: boolean = false;
  @StorageLink('appThemeMode') appThemeMode: string = 'system';
  @StorageLink('themeRevision') @Watch('onReaderThemeChanged') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageLink('bookshelfCoverAlbums') @Watch('onTtsCoverSettingsChanged') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') @Watch('onTtsCoverSettingsChanged') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') @Watch('onTtsCoverSettingsChanged') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverApplyScope') @Watch('onTtsCoverSettingsChanged') bookshelfCoverApplyScope: string = 'all';
  @StorageLink('bookshelfCoverTargetBooks') @Watch('onTtsCoverSettingsChanged') bookshelfCoverTargetBooks: string = '';
  @StorageLink('bookshelfIgnoreSourceCover') @Watch('onTtsCoverSettingsChanged') bookshelfIgnoreSourceCover: boolean = false;
  @StorageLink('bookshelfCoverMode') @Watch('onTtsCoverSettingsChanged') bookshelfCoverMode: string = 'sequence';
  @StorageLink('coverGalleryUpdateTime') @Watch('onTtsCoverSettingsChanged') coverGalleryUpdateTime: number = 0;
  @StorageLink('ttsPerson') ttsPerson: number = 0;
  @StorageLink('ttsOnline') ttsOnline: number = 1;
  @StorageLink('ttsStyle') ttsStyle: string = '';
  @StorageLink('ttsLanguage') ttsLanguage: string = 'zh-CN';
  @StorageLink('ttsSpeed') ttsSpeed: number = 1;
  @StorageLink('ttsInstalledVoiceKeys') ttsInstalledVoiceKeys: string = '';
  @StorageLink('ttsCustomVoiceId') ttsCustomVoiceId: string = '';
  @StorageLink('ttsCustomVoices') @Watch('onTtsCustomVoicesChanged') ttsCustomVoices: string = '';
  @StorageLink('launchShortcutNonce') @Watch('onLaunchShortcutChanged') launchShortcutNonce: number = 0;
  @StorageLink('fullTextCacheCancelNonce') @Watch('onFullTextCacheCancelNonceChanged') fullTextCacheCancelNonce: number = 0;
  @State ttsVoices: TtsVoiceOption[] = [ReadBookPage.defaultTtsVoice()];
  @State ttsCustomVoiceOptions: HttpTTS[] = [];
  @State ttsSelectedVoiceKey: string = '';
  @State ttsVoicesLoading: boolean = false;
  @State fullTextCaching: boolean = false;
  @State fullTextCacheDone: number = 0;
  @State fullTextCacheTotal: number = 0;
  @State fullTextCacheStatus: string = '';
  private fullTextCacheTaskId: number = 0;
  private fullTextCacheCancelRequested: boolean = false;
  private fullTextCacheCancelSeenNonce: number = 0;
  private fullTextCacheNotificationLastAt: number = 0;
  private fullTextCacheBackgroundRunning: boolean = false;
  private fullTextCacheCancelAgent: WantAgent | null = null;
  private volumeUpCallback?: (event: KeyEvent) => void;
  private volumeDownCallback?: (event: KeyEvent) => void;
  private lastLoggedReaderFontFamily: string = '';
  private readerFontChangeSerial: number = 0;
  private readingProgressSaveQueue: Promise<void> = Promise.resolve();
  private readerExitProgressSaved: boolean = false;
  private openedFromShortcut: boolean = false;
  private shortcutReplacedPreviousPage: boolean = false;
  private shortcutRoutingActive: boolean = false;
  private readerEntryInitializing: boolean = true;
  private readerSettingsReloadSerial: number = 0;
  @State shelfOpeningEntryOpacity: number = 1;
  @State shelfOpeningEntryScale: number = 1;
  private shelfOpeningEntryTimer: number = -1;
  private openedWithShelfAnimation: boolean = false;

  async aboutToAppear() {
    this.shortcutRoutingActive = true;
    this.readerEntryInitializing = true;
    this.enterReaderImmersive();
    this.updateVolumeKeySubscription();
    const params = router.getParams() as Record<string, string>;
    this.openedWithShelfAnimation = !!params && params['shelfBookOpening'] === 'true';
    this.openedFromShortcut = !!params && params['shortcutEntry'] === 'true';
    this.shortcutReplacedPreviousPage = !!params && params['shortcutReplace'] === 'true';
    if (this.openedWithShelfAnimation) {
      this.shelfOpeningEntryOpacity = 0.86;
      this.shelfOpeningEntryScale = 0.985;
      this.shelfOpeningEntryTimer = setTimeout(() => {
        this.shelfOpeningEntryTimer = -1;
        animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
          this.shelfOpeningEntryOpacity = 1;
          this.shelfOpeningEntryScale = 1;
        });
      }, 20);
    }
    if (params && params['bookUrl']) {
      this.bookUrl = params['bookUrl'];
      this.isLoading = true;
      this.loadStatus = '正在加载...';
      this.resetReaderStateForBookLoad();
    }
    try {
      await this.loadReaderSettings();
      this.readerReplaceRules = await ReaderReplaceRuleStore.load(getContext(this), true);
      this.loadTtsSettingsAndVoices();
      if (this.bookUrl) {
        await this.loadBook();
        await this.loadBookmarks();
      }
    } finally {
      this.readerEntryInitializing = false;
    }
  }

  onPageShow(): void {
    this.shortcutRoutingActive = true;
    if (!this.readerEntryInitializing) {
      this.reloadReaderSettingsAfterPageShow().catch((error: Error) => {
        console.warn('恢复阅读设置失败:', error);
      });
      this.reloadReaderReplaceRules(true).catch((error: Error) => {
        console.warn('恢复替换净化规则失败:', error);
      });
    }
    this.reregisterReaderFontAfterShow(0);
    this.reregisterReaderFontAfterShow(120);
    this.syncTtsFocusAfterResumeLater(0);
    this.syncTtsFocusAfterResumeLater(180);
  }

  onBackPress(): boolean {
    if (this.showBookmarkActionMenu) {
      this.closeBookmarkActionMenu();
      return true;
    }
    if (this.showChangeSourceDialog) {
      this.showChangeSourceDialog = false;
      return true;
    }
    if (this.showTapZoneSettings) {
      this.showTapZoneSettings = false;
      return true;
    }
    if (this.showToc || this.showSettings || this.showMenu) {
      this.showToc = false;
      this.hideReaderPanels();
      return true;
    }
    this.exitReaderPage();
    return true;
  }

  async reloadReaderSettingsAfterPageShow(): Promise<void> {
    const reloadSerial = ++this.readerSettingsReloadSerial;
    const settings = await ReaderSettingsStore.reload(getContext(this));
    if (reloadSerial !== this.readerSettingsReloadSerial) {
      return;
    }
    ReaderSettingsStore.applyToStorage(settings);
    this.applyLoadedReaderSettings(settings);
    this.cachedRegexRulesKey = '';
    this.cachedRegexRules = [];
    this.readerPaginationCache.clear();
    this.refreshReaderTextRender();
    this.paginateContent(this.content);
  }

  reregisterReaderFontAfterShow(delayMs: number): void {
    setTimeout(() => {
      if (!this.readerFontFilePath) {
        this.readerSystemFontFamily = ReaderSystemFontHelper.applyToStorage(this.getUIContext());
      }
      this.registerReaderFont();
    }, delayMs);
  }

  aboutToDisappear() {
    this.shortcutRoutingActive = false;
    if (this.shelfOpeningEntryTimer >= 0) {
      clearTimeout(this.shelfOpeningEntryTimer);
      this.shelfOpeningEntryTimer = -1;
    }
    this.flushPendingTtsSpeedSettings();
    this.stopTtsReading();
    this.ttsReader.shutdown();
    if (!this.readerExitProgressSaved) {
      this.saveReadingProgress().catch((error: Error) => {
        console.error('离开阅读页保存进度失败:', error);
      });
    }
    this.unregisterVolumeKeyTurn();
    this.exitReaderImmersive();
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

  async openPendingShortcut(): Promise<void> {
    if (!RecentReadShortcut.isPending()) {
      return;
    }
    this.saveReadingProgress().catch((error: Error) => {
      console.warn('快捷入口切换前保存进度失败:', error);
    });
    try {
      await RecentReadShortcut.openPending(getContext(this), true);
    } catch (e) {
      console.error('打开最近阅读快捷项失败:', e);
    }
  }

  enterReaderImmersive() {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      const bg = this.getBackgroundColor();
      const useLightIcons = this.isReaderThemeDark();
      const systemTextColor = useLightIcons ? '#D8D8D8' : '#2F261D';
      mainWindow.setWindowBackgroundColor(bg);
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarEnable(this.readerExtendToStatusBar ? ['navigation'] : ['navigation', 'status']);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        isStatusBarLightIcon: useLightIcons,
        statusBarContentColor: systemTextColor,
        navigationBarColor: bg,
        isNavigationBarLightIcon: useLightIcons,
        navigationBarContentColor: systemTextColor
      });
      this.updateStatusBarSafeHeight(mainWindow);
    }).catch((err: Error) => {
      console.error('进入阅读沉浸模式失败:', err);
    });
  }

  exitReaderImmersive() {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
      this.statusBarSafeHeight = 0;
    }).catch((err: Error) => {
      console.error('退出阅读沉浸模式失败:', err);
    });
  }

  updateStatusBarSafeHeight(mainWindow: window.Window): void {
    try {
      const avoidArea = mainWindow.getWindowAvoidAreaIgnoringVisibility(window.AvoidAreaType.TYPE_SYSTEM);
      const topHeight = px2vp(Math.max(0, avoidArea.topRect.height));
      this.statusBarSafeHeight = topHeight > 0 ? topHeight : 32;
    } catch (err) {
      console.error('获取状态栏安全区失败:', err);
      this.statusBarSafeHeight = 32;
    }
  }

  async loadBook() {
    const loadSerial = ++this.bookLoadSerial;
    this.isLoading = true;
    this.loadStatus = '正在加载...';
    this.resetReaderStateForBookLoad();
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      
      this.book = await db.getBook(this.bookUrl);
      if (loadSerial !== this.bookLoadSerial) {
        return;
      }
      if (!this.book) {
        this.setReaderContent('书籍不存在，请先从搜索结果加入书架。');
        this.isLoading = false;
        return;
      }
      if (this.book.origin === LocalBookService.ORIGIN) {
        this.loadStatus = '正在优化本地书籍...';
        const rebuilt = await LocalBookService.ensureTxtParserCurrent(getContext(this), this.book);
        if (rebuilt) {
          const rebuiltBook = await db.getBook(this.bookUrl);
          if (rebuiltBook) this.book = rebuiltBook;
        }
      }
      if (loadSerial !== this.bookLoadSerial) {
        return;
      }
      if (Book.hasStartedReading(this.book)) {
        await this.markBookRecentlyRead();
      }

      const engine = ReadBookEngine.get();
      await engine.openBook(this.book);
      if (loadSerial !== this.bookLoadSerial) {
        return;
      }
      this.book = engine.book || this.book;
      this.chapters = engine.chapters;
      const savedChapterIndex = engine.curIdx;
      this.currentChapterIndex = this.clampChapterIndex(savedChapterIndex);
      const savedPosition = this.currentChapterIndex === savedChapterIndex ? Math.max(0, engine.curPos) : 0;
      this.pendingRestorePageIndex = savedPosition;
      this.readerLightThemeIndex = ReaderThemeHelper.normalizeIndex(this.readerLightThemeIndex);
      this.readerDarkThemeIndex = ReaderThemeHelper.normalizeIndex(this.readerDarkThemeIndex);

      if (this.chapters.length > 0) {
        await this.loadContent();
      } else if (this.book.origin !== 'local' && this.book.origin) {
        this.setReaderContent(`《${this.book.name}》\n\n作者：${this.book.author || '未知'}\n来源：${this.book.originName || this.book.origin}\n\n正在尝试解析目录...`);
        this.loadStatus = '正在获取目录...';
        await this.retryFetchChapters();
      } else {
        this.setReaderContent(this.buildBookPreview());
        this.isLoading = false;
      }
    } catch (e) {
      console.error('加载书籍失败:', e);
      this.setReaderContent('书籍或目录加载失败。请点击右上角“更多操作”，选择“重试”重新加载。');
      this.isLoading = false;
    } finally {
      this.updatePendingVerification();
    }
  }

  async retryFetchChapters() {
    try {
      const engine = ReadBookEngine.get();
      await engine.refreshToc();
      this.book = engine.book || this.book;
      this.chapters = engine.chapters;
      if (this.chapters.length > 0) {
        this.loadStatus = '';
        await this.loadContent();
      } else {
        this.updatePendingVerification();
        this.setReaderContent(this.buildBookPreview());
        this.isLoading = false;
      }
    } catch (e) {
      console.error('重试获取目录失败:', e);
      this.updatePendingVerification();
      this.setReaderContent(this.buildBookPreview());
      this.isLoading = false;
    }
  }

  resetReaderStateForBookLoad(): void {
    this.contentLoadSerial++;
    this.content = '';
    this.chapters = [];
    this.tocVisibleChapters = [];
    this.tocWindowStart = 0;
    this.currentChapterIndex = 0;
    this.contentPages = [];
    this.contentPageStarts = [];
    this.contentPageEnds = [];
    this.pagedContentText = '';
    this.readerPaginationCache.clear();
    this.adjacentPaginationPreloadSerial++;
    this.currentPageIndex = 0;
    this.currentPageText = '';
    this.displayPageText = '';
    this.displayPageChapterIndex = 0;
    this.displayPageIndex = 0;
    this.displayPageRenderKey = 0;
    this.chapterJumpRenderGeneration = 0;
    this.pageViewWidth = 0;
    this.pageViewHeight = 0;
    this.readerInitialPageReady = false;
    this.pendingRestorePageIndex = -1;
    this.pageTransitionX = 0;
    this.pageTransitionOpacity = 1;
    this.pageSlideOffsetX = 0;
    this.pageSlideOffsetY = 0;
    this.pageSlideDirection = 0;
    this.bookmarkPullOffsetY = 0;
    this.bookmarkPullActive = false;
    this.bookmarkPullReady = false;
    this.pageTurnAnimating = false;
    this.pageTurnIncomingText = '';
    this.pageTurnIncomingSecondaryText = '';
    this.pageTurnIncomingX = 0;
    this.pageTurnIncomingOpacity = 1;
    this.pageTurnIncomingPageIndex = 0;
    this.pageTurnIncomingChapterIndex = 0;
    this.pageTurnIncomingRenderVersion = 0;
    this.isPageTurning = false;
    this.clearPageTurnPreviewState();
    this.clearTtsHighlight();
    this.pageRenderVersion++;
  }

  async loadContent(silent: boolean = false, targetChapterIndex: number = this.currentChapterIndex) {
    if (this.chapters.length === 0) {
      this.setReaderContent(this.buildBookPreview());
      this.isLoading = false;
      return;
    }
    
    const engine = ReadBookEngine.get();
    const chapterIndex = this.clampChapterIndex(targetChapterIndex);
    const loadSerial = ++this.contentLoadSerial;
    const showLoading = !silent && !engine.hasCachedContent(chapterIndex);
    if (showLoading) {
      this.isLoading = true;
      this.loadStatus = '正在加载章节内容...';
    }
    try {
      const body = await engine.loadContent(chapterIndex);
      if (loadSerial !== this.contentLoadSerial) {
        return;
      }
      this.currentChapterIndex = chapterIndex;
      let loadedContent = this.applyReaderContentRules(body);
      if (body) {
        this.content = loadedContent;
        this.chapters = [...engine.chapters];
      } else {
        this.updatePendingVerification();
        const c = this.chapters[chapterIndex];
        loadedContent = this.verificationUrl ? `${c ? c.title : '当前章节'}\n\n该书源需要先完成网页验证。请点击右上角“更多操作”，选择“登录”，完成后返回，再从该菜单选择“重试”。` :
          (c ? `${c.title}\n\n章节正文加载失败。请点击右上角“刷新本章”或“换源”。` :
            '章节正文加载失败。请点击右上角“更多操作”，选择“重试”。');
        this.content = loadedContent;
      }
      this.paginateContent(loadedContent, chapterIndex);
      this.preloadReaderContent();
    } catch (e) {
      console.error('加载内容失败:', e);
    } finally {
      if (loadSerial === this.contentLoadSerial && !silent) {
        this.isLoading = false;
        this.loadStatus = '';
      }
      this.updatePendingVerification();
    }
  }

  async refreshCurrentChapter(): Promise<void> {
    if (this.chapters.length === 0) {
      return;
    }

    const engine = ReadBookEngine.get();
    this.isLoading = true;
    this.loadStatus = '正在刷新本章...';
    try {
      const body = await engine.reloadContent(this.currentChapterIndex);
      if (body) {
        const processedBody = this.applyReaderContentRules(body);
        this.content = processedBody;
        this.chapters = [...engine.chapters];
        this.pendingRestorePageIndex = 0;
        this.currentPageIndex = 0;
        this.paginateContent(processedBody);
        this.preloadReaderContent();
        await this.saveReadingProgress();
        promptAction.showToast({ message: '本章已刷新' });
      } else {
        this.updatePendingVerification();
        const chapter = this.chapters[this.currentChapterIndex];
        const loadedContent = this.verificationUrl ? `${chapter ? chapter.title : '当前章节'}\n\n该书源需要先完成网页验证。请点击右上角“更多操作”，选择“登录”，完成后返回，再从该菜单选择“重试”。` :
          (chapter ? `${chapter.title}\n\n章节正文刷新失败。请再次点击右上角“刷新本章”或“换源”。` :
            '章节正文刷新失败。请点击右上角“更多操作”，选择“重试”。');
        this.content = loadedContent;
        this.paginateContent(loadedContent);
        promptAction.showToast({ message: '刷新本章失败' });
      }
    } catch (e) {
      console.error('刷新本章失败:', e);
      promptAction.showToast({ message: '刷新本章失败' });
    } finally {
      this.isLoading = false;
      this.loadStatus = '';
      this.updatePendingVerification();
    }
  }

  onFullTextCacheCancelNonceChanged(): void {
    const nonce = this.fullTextCacheCancelNonce || 0;
    if (this.fullTextCaching && nonce > 0 && nonce !== this.fullTextCacheCancelSeenNonce) {
      this.fullTextCacheCancelRequested = true;
      this.fullTextCacheCancelSeenNonce = nonce;
    }
  }

  startFullTextCache(): void {
    if (this.fullTextCaching) {
      promptAction.showToast({ message: this.fullTextCacheStatus || '全文缓存正在后台进行' });
      return;
    }
    if (!this.book || this.chapters.length === 0 || !this.book.origin || this.book.origin === 'local') {
      promptAction.showToast({ message: '当前书籍暂无可缓存章节' });
      return;
    }

    this.hideReaderPanels();
    promptAction.showToast({ message: '已转入后台缓存，可在通知栏取消' });
    this.runFullTextCache(++this.fullTextCacheTaskId).catch((error: Error) => {
      console.error('全文缓存任务失败:', error);
      this.fullTextCaching = false;
      this.fullTextCacheStatus = '全文缓存失败';
      promptAction.showToast({ message: '全文缓存失败' });
      this.publishFullTextCacheNotification('全文缓存失败', this.fullTextCacheProgressText(), false).catch((e: Error) => {
        console.warn('更新全文缓存失败通知失败:', e);
      });
      this.stopFullTextCacheBackgroundRunning().catch((e: Error) => {
        console.warn('停止全文缓存后台任务失败:', e);
      });
    });
  }

  async runFullTextCache(taskId: number): Promise<void> {
    const engine = ReadBookEngine.get();
    if (!engine.book || engine.chapters.length === 0) {
      return;
    }

    this.fullTextCaching = true;
    this.fullTextCacheCancelRequested = false;
    this.fullTextCacheCancelSeenNonce = AppStorage.get<number>('fullTextCacheCancelNonce') || 0;
    this.fullTextCacheNotificationLastAt = 0;
    this.fullTextCacheCancelAgent = null;
    await engine.syncChapterCacheDates();
    this.chapters = [...engine.chapters];
    this.fullTextCacheTotal = engine.chapters.length;
    this.fullTextCacheDone = this.countCachedChapters(engine.chapters);
    this.fullTextCacheStatus = '全文缓存后台进行中';

    await this.requestFullTextCacheNotificationEnabled();
    await this.startFullTextCacheBackgroundRunning();
    await this.publishFullTextCacheProgress(true);

    for (let index = 0; index < engine.chapters.length; index++) {
      if (taskId !== this.fullTextCacheTaskId || this.shouldCancelFullTextCache()) {
        break;
      }
      const chapter = engine.chapters[index];
      if (!chapter || chapter.cacheDate > 0) {
        continue;
      }

      const title = chapter.title || `第${index + 1}章`;
      this.fullTextCacheStatus = `正在缓存：${title}`;
      await this.publishFullTextCacheProgress(false);
      const ok = await engine.cacheChapter(index);
      if (taskId !== this.fullTextCacheTaskId) {
        break;
      }
      if (ok) {
        this.fullTextCacheDone = this.countCachedChapters(engine.chapters);
        this.chapters = [...engine.chapters];
      }
      await this.publishFullTextCacheProgress(true);
      await this.sleep(0);
    }

    if (taskId !== this.fullTextCacheTaskId) {
      return;
    }

    const canceled = this.shouldCancelFullTextCache();
    await engine.syncChapterCacheDates();
    this.chapters = [...engine.chapters];
    this.fullTextCacheDone = this.countCachedChapters(engine.chapters);
    this.fullTextCaching = false;
    this.fullTextCacheStatus = canceled ? '全文缓存已取消' : '全文缓存完成';
    this.fullTextCacheCancelRequested = false;
    await this.publishFullTextCacheNotification(
      canceled ? '缓存已停止' : '全文缓存完成',
      this.fullTextCacheProgressText(),
      false
    );
    if (canceled) {
      promptAction.showToast({ message: '缓存已停止' });
    } else {
      promptAction.showToast({ message: '全文缓存完成' });
    }
    await this.stopFullTextCacheBackgroundRunning();
  }

  shouldCancelFullTextCache(): boolean {
    if (this.fullTextCacheCancelRequested) {
      return true;
    }
    const nonce = AppStorage.get<number>('fullTextCacheCancelNonce') || 0;
    if (nonce > 0 && nonce !== this.fullTextCacheCancelSeenNonce) {
      this.fullTextCacheCancelRequested = true;
      this.fullTextCacheCancelSeenNonce = nonce;
      return true;
    }
    return false;
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

  fullTextCacheProgressText(): string {
    const total = Math.max(this.fullTextCacheTotal, 0);
    if (total === 0) {
      return '正在准备缓存章节';
    }
    const done = Math.max(0, Math.min(this.fullTextCacheDone, total));
    const percent = Math.floor((done / total) * 100);
    return `已缓存 ${done}/${total} 章（${percent}%）`;
  }

  async publishFullTextCacheProgress(force: boolean): Promise<void> {
    const now = Date.now();
    if (!force && now - this.fullTextCacheNotificationLastAt < 1200) {
      return;
    }
    this.fullTextCacheNotificationLastAt = now;
    await this.publishFullTextCacheNotification(this.fullTextCacheStatus || '全文缓存后台进行中',
      this.fullTextCacheProgressText(), true);
  }

  async publishFullTextCacheNotification(text: string, additionalText: string, ongoing: boolean): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: 2601,
        label: 'full_text_cache',
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: ongoing,
        tapDismissed: false,
        isAlertOnce: true,
        autoDeletedTime: ongoing ? undefined : Date.now() + 5000,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: this.book?.name ? `缓存全文：${this.book.name}` : '缓存全文',
            text: text,
            additionalText: additionalText
          }
        }
      };
      if (ongoing) {
        request.actionButtons = [{
          title: '×',
          wantAgent: await this.getFullTextCacheCancelWantAgent()
        }];
      }
      await notificationManager.publish(request);
    } catch (error) {
      console.warn('发布全文缓存通知失败:', error);
    }
  }

  async requestFullTextCacheNotificationEnabled(): Promise<void> {
    try {
      if (await notificationManager.isNotificationEnabled()) {
        return;
      }
      await notificationManager.requestEnableNotification(getContext(this) as common.UIAbilityContext);
    } catch (error) {
      console.warn('请求通知权限失败:', error);
    }
  }

  async getFullTextCacheCancelWantAgent(): Promise<WantAgent> {
    if (this.fullTextCacheCancelAgent) {
      return this.fullTextCacheCancelAgent;
    }
    const context = getContext(this) as common.UIAbilityContext;
    this.fullTextCacheCancelAgent = await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          cacheAction: 'cancelFullTextCache',
          cacheTaskId: this.fullTextCacheTaskId
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 2602,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    return this.fullTextCacheCancelAgent;
  }

  async startFullTextCacheBackgroundRunning(): Promise<void> {
    if (this.fullTextCacheBackgroundRunning) {
      return;
    }
    try {
      const agent = await this.createFullTextCacheOpenWantAgent();
      await backgroundTaskManager.startBackgroundRunning(getContext(this), ['dataTransfer'], agent);
      this.fullTextCacheBackgroundRunning = true;
    } catch (error) {
      console.warn('启动全文缓存后台任务失败:', error);
    }
  }

  async stopFullTextCacheBackgroundRunning(): Promise<void> {
    if (!this.fullTextCacheBackgroundRunning) {
      return;
    }
    this.fullTextCacheBackgroundRunning = false;
    if (this.ttsBackgroundRunning || this.ttsBackgroundRequesting) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(getContext(this));
    } catch (error) {
      console.warn('停止全文缓存后台任务失败:', error);
    }
  }

  async createFullTextCacheOpenWantAgent(): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          bookUrl: this.bookUrl || ''
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 2603,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  sleep(ms: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  shouldRenderPrimaryReaderContent(): boolean {
    return !this.isLoading || !!this.content;
  }

  isPagedReaderAwaitingPagination(): boolean {
    return !!this.content && this.contentPages.length === 0;
  }

  shouldShowReaderLoadingOverlay(): boolean {
    return this.shouldRenderPrimaryReaderContent() &&
      (this.isLoading || this.isPagedReaderAwaitingPagination() || !this.readerInitialPageReady);
  }

  shouldBlockReaderInteraction(): boolean {
    return this.isLoading || this.isPagedReaderAwaitingPagination() || !this.readerInitialPageReady;
  }

  getReaderLoadingText(): string {
    if (this.isPagedReaderAwaitingPagination() && !this.isLoading) {
      return '正在排版...';
    }
    return this.loadStatus || '加载中...';
  }

  @Builder
  readerLoadingPanel() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
      Text(this.getReaderLoadingText())
        .fontSize(14)
        .fontColor('#999')
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.readerContentLayerColor())
  }

  build() {
    Stack() {
      if (this.hasBackgroundImage()) {
        Image(this.getBackgroundImage())
          .width('100%')
          .height('100%')
          .objectFit(this.getBackgroundImageFit())
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .hitTestBehavior(HitTestMode.None)
      }
      Column() {
        if (!this.shouldRenderPrimaryReaderContent()) {
          this.readerLoadingPanel()
        } else {
          Stack() {
            ForEach(this.currentReaderSurfaceKeys(), (_surfaceKey: string) => {
              if (this.currentReaderSurfaceIndex() === 0) {
                if (this.isPageTurnAnimationEnabled()) {
                  this.readerSlidingPageTurnSurface(this.visibleCurrentPageText(), this.pageRenderVersion,
                    this.ttsHighlightRenderVersion)
                } else {
                  this.readerCurrentPageSurface(this.pageRenderVersion, this.visibleCurrentPageText(),
                    this.ttsHighlightRenderVersion)
                }
              } else {
                if (this.isPageTurnAnimationEnabled()) {
                  this.readerSlidingPageTurnSurfaceAlternate(this.visibleCurrentPageText(), this.pageRenderVersion,
                    this.ttsHighlightRenderVersion)
                } else {
                  this.readerCurrentPageSurfaceAlternate(this.pageRenderVersion, this.visibleCurrentPageText(),
                    this.ttsHighlightRenderVersion)
                }
              }
            }, (surfaceKey: string) => surfaceKey)
            Column() {
              Blank()
                .layoutWeight(1)
              this.readerBottomInfoBar()
            }
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .height('100%')
          .clip(true)
          .opacity(this.readerInitialPageReady ? 1 : 0)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.updatePagedReaderArea(newValue);
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getReaderTopSafePadding() })
      .backgroundColor(this.readerContentLayerColor())
      .onClick(() => {
        if (this.showToc || this.showSettings) {
          return;
        }
        if (this.showMenu) {
          this.hideReaderPanels();
          return;
        }
      })

      if (this.shouldShowReaderLoadingOverlay()) {
        this.readerLoadingPanel()
      }

      if (!this.showMenu && !this.showToc && !this.showSettings &&
        !this.shouldBlockReaderInteraction()) {
        this.readerTapLayer()
      }

      if (this.bookmarkPullActive) {
        this.readerBookmarkPullHint()
      }

      if (this.isCurrentPageBookmarked() && !this.showMenu && !this.showToc && !this.showSettings) {
        this.readerCurrentPageBookmarkMarker()
      }

      if (this.showMenu && !this.showToc && !this.showSettings) {
        this.menuDismissLayer()
      }

      if (this.showSettings) {
        this.settingsDismissLayer()
      }

      if (this.showMenu) {
        this.readerFloatingTopMenu()
      }

      if (this.showMenu && this.showReaderActionMenu && !this.showToc && !this.showSettings) {
        this.readerActionMenu()
      }

      if (this.showMenu && !this.showToc && !this.showSettings && this.chapters.length > 0) {
        if (this.supportsReaderImmersiveMaterial()) {
          this.readerHdsFloatingBottomMenu()
        } else {
          this.readerFloatingBottomMenu()
        }
        if (!this.ttsMediaControlsExpanded) {
          this.readerTtsQuickActionButton()
        }
        if (this.shouldShowTtsMediaControls()) {
          this.ttsExpandedMediaControlsBar()
        }
      }

      if (this.showToc) {
        this.readerFloatingTocPanel()
        if (this.supportsReaderImmersiveMaterial()) {
          this.readerHdsFloatingActionBar(true)
        }
      }

      if (this.showSettings) {
        this.settingsPanel()
        if (this.supportsReaderImmersiveMaterial()) {
          this.readerHdsFloatingActionBar(false, true)
        }
      }

      if (this.showBookmarkActionMenu && this.pendingBookmarkAction) {
        this.bookmarkActionMenu()
      }

      if (this.showTapZoneSettings) {
        this.tapZoneSettingsDialog()
      }

      if (this.showChangeSourceDialog) {
        this.changeSourceDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.readerContentLayerColor())
    .opacity(this.shelfOpeningEntryOpacity)
    .scale({ x: this.shelfOpeningEntryScale, y: this.shelfOpeningEntryScale })
    .expandSafeArea([SafeAreaType.SYSTEM], this.getReaderSafeAreaEdges())
  }

  @Builder
  readerFloatingTopMenu() {
    Row() {
      ImmersiveBackButton({
        iconColor: this.getTextColor(),
        darkMode: this.isReaderThemeDark(),
        buttonSize: 46,
        containerWidth: 46,
        containerHeight: 64,
        startInset: 0,
        onBack: () => this.exitReaderPage()
      })

      Blank()
        .layoutWeight(1)

      Row({ space: -6 }) {
        if (this.book && !LocalBookService.isLocalBook(this.book) && this.chapters.length > 0) {
          this.readerRoundMenuButton($r('sys.symbol.arrow_clockwise'), '刷新本章', () => {
            this.hideReaderPanels();
            this.refreshCurrentChapter();
          })
        }
        if (this.book && !LocalBookService.isLocalBook(this.book)) {
          this.readerRoundMenuButton($r('sys.symbol.arrow_left_arrow_right'), '换源', () => {
            this.openChangeSourceDialog();
          })
        }
        this.readerRoundMenuButton($r('sys.symbol.more'), '更多操作', () => {
          this.showReaderActionMenu = !this.showReaderActionMenu;
        })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 0, top: this.getTopControlSafePadding() + 10 })
    .position({ x: 0, y: 0 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  readerRoundMenuButton(icon: Resource, accessibilityText: string, action: () => void) {
    ImmersiveBackButton({
      icon: icon,
      iconColor: this.getTextColor(),
      darkMode: this.isReaderThemeDark(),
      buttonSize: 46,
      containerWidth: 46,
      containerHeight: 64,
      startInset: 0,
      accessibilityLabel: accessibilityText,
      onBack: action
    })
  }

  supportsReaderImmersiveMaterial(): boolean {
    return deviceInfo.sdkApiVersion >= 23;
  }

  @Builder
  readerHdsFloatingBottomMenu() {
    Column({ space: 4 }) {
      this.readerHdsChapterTabBar()
      this.readerHdsActionBar(false)
    }
    .width('100%')
    .height(this.readerBottomMenuOverlayHeight())
    .padding({ bottom: this.readerFloatingBarBottomMargin() })
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
    .position({ x: 0, y: '100%' })
    .translate({ y: -this.readerBottomMenuOverlayHeight() })
  }

  @Builder
  readerHdsChapterTabBar() {
    Stack({ alignContent: Alignment.Center }) {
      HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
        TabContent() {
          Column()
        }
        .height(56)
        .tabBar(this.readerHdsChapterBarContent())
      }
      .barMode(BarMode.Fixed)
      .barHeight(48)
      .barOverlap(true)
      .barFloatingStyle({
        barWidth: {
          smallWidth: this.readerFloatingBarWidth(),
          mediumWidth: this.readerFloatingBarWidth(),
          largeWidth: this.readerFloatingBarWidth()
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        barSideMargin: 0,
        barBottomMargin: 4,
        gradientMask: {
          maskColor: '#00000000',
          maskHeight: 56
        },
        adaptToHandedness: false,
        thermoCtrl: true,
        barOpacity: 1
      })
      .scrollable(false)
      .width('100%')
      .height(56)

      if (this.menuChapterTooltipVisible) {
        Column({ space: 2 }) {
          Text(this.getChapterTitle(this.getMenuChapterDisplayIndex()))
            .fontSize(12)
            .fontColor('#FFFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.getMenuChapterDisplayIndex() + 1}/${this.chapters.length}`)
            .fontSize(11)
            .fontColor('#CCFFFFFF')
        }
        .width('62%')
        .height(44)
        .padding({ left: 14, right: 14, top: 5, bottom: 5 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(22)
        .backgroundColor(this.isReaderThemeDark() ? '#E63A3C40' : '#D94B4D52')
        .shadow({ radius: 10, color: '#50000000', offsetX: 0, offsetY: 3 })
        .position({ x: '19%', y: -48 })
      }
    }
    .width('100%')
    .height(56)
  }

  @Builder
  readerHdsChapterBarContent() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(25)
          .fontColor([this.currentChapterIndex > 0 && !this.isLoading ?
            this.getTextColor() : this.getSubTextColor()])
      }
        .width(46)
        .height(48)
        .enabled(this.currentChapterIndex > 0 && !this.isLoading)
        .onClick(async () => {
          await this.jumpToAdjacentChapterFromMenu(-1);
        })

      Slider({
        value: this.getMenuChapterDisplayIndex(),
        min: 0,
        max: Math.max(0, this.chapters.length - 1),
        step: 1,
        style: SliderStyle.InSet
      })
        .layoutWeight(1)
        .height(48)
        .trackThickness(30)
        .blockSize({ width: 30, height: 30 })
        .selectedColor(this.accentColor())
        .trackColor(this.readerChapterTrackColor())
        .blockColor(this.readerSolidPanelColor())
        .showSteps(false)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.handleMenuChapterSliderChange(value, mode);
        })

      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.arrow_right'))
          .fontSize(25)
          .fontColor([this.currentChapterIndex < this.chapters.length - 1 && !this.isLoading ?
            this.getTextColor() : this.getSubTextColor()])
      }
        .width(46)
        .height(48)
        .enabled(this.currentChapterIndex < this.chapters.length - 1 && !this.isLoading)
        .onClick(async () => {
          await this.jumpToAdjacentChapterFromMenu(1);
        })
    }
    .width('100%')
    .height(48)
    .padding({ left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
    .translate({ y: -2 })
  }

  @Builder
  readerHdsFloatingActionBar(fromToc: boolean, fromSettings: boolean = false) {
    Column() {
      this.readerHdsActionBar(fromToc, fromSettings)
    }
    .width('100%')
    .height(this.readerBottomActionOverlayHeight())
    .padding({ bottom: this.readerFloatingBarBottomMargin() })
    .justifyContent(FlexAlign.End)
    .position({ x: 0, y: '100%' })
    .translate({ y: -this.readerBottomActionOverlayHeight() })
  }

  @Builder
  readerHdsActionBar(fromToc: boolean, fromSettings: boolean = false) {
    HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
      TabContent() {
        Column()
      }
      .height(56)
      .tabBar(this.readerHdsMenuItem($r('sys.symbol.list_bullet'), fromToc))

      TabContent() {
        Column()
      }
      .height(56)
      .tabBar(this.readerHdsMenuItem($r('sys.symbol.textformat'),
        fromSettings && this.settingsPanelTab === 0))

      TabContent() {
        Column()
      }
      .height(56)
      .tabBar(this.readerHdsMenuItem($r('sys.symbol.speaker_wave_3'),
        this.isTtsSpeaking || (fromSettings && this.settingsPanelTab === 1)))

      TabContent() {
        Column()
      }
      .height(56)
      .tabBar(this.readerHdsMenuItem(this.readerDayNightIcon(), false))
    }
    .barMode(BarMode.Fixed)
    .barHeight(48)
    .barOverlap(true)
    .barFloatingStyle({
      barWidth: {
        smallWidth: this.readerFloatingBarWidth(),
        mediumWidth: this.readerFloatingBarWidth(),
        largeWidth: this.readerFloatingBarWidth()
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      barSideMargin: 0,
      barBottomMargin: 4,
      gradientMask: {
        maskColor: '#00000000',
        maskHeight: 56
      },
      adaptToHandedness: false,
      thermoCtrl: true,
      barOpacity: 1
    })
    .scrollable(false)
    .onContentWillChange(() => false)
    .onTabBarClick((index: number) => {
      this.handleReaderHdsAction(index, fromToc, fromSettings);
    })
    .width('100%')
    .height(56)
  }

  @Builder
  readerHdsMenuItem(icon: Resource, active: boolean, showAddBadge: boolean = false) {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([this.getSubTextColor()])

        if (showAddBadge) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.getSubTextColor()])
            .position({ x: 20, y: 0 })
        }
      }
      .width(32)
      .height(32)
    }
    .width('100%')
    .height(48)
    .translate({ y: -2 })
  }

  handleReaderHdsAction(index: number, fromToc: boolean, fromSettings: boolean = false): void {
    if (index === 0) {
      if (fromToc) {
        this.cancelBookmarkMultiSelect();
        this.showToc = false;
        this.showMenu = true;
      } else if (fromSettings) {
        this.showSettings = false;
        this.openTocPanel();
      } else {
        this.openTocPanel();
      }
      return;
    }
    if (index === 3) {
      this.toggleReaderDayNightMode();
      return;
    }
    if (fromToc) {
      this.showToc = false;
    }
    if (index === 1) {
      if (fromSettings && this.settingsPanelTab === 0) {
        this.closeSettingsPanelKeepMenu();
      } else {
        this.openSettingsPanel();
      }
      return;
    }
    if (index === 2) {
      if (fromSettings && this.settingsPanelTab === 1) {
        this.closeSettingsPanelKeepMenu();
      } else {
        this.openTtsSettingsPanel();
      }
      return;
    }
  }

  readerDayNightIcon(): Resource {
    const mode = AppThemeModeStore.normalizeMode(this.appThemeMode);
    if (mode === 'system') {
      return $r('sys.symbol.circle_lefthalf_inset_filled');
    }
    return mode === 'dark' ? $r('sys.symbol.moon') : $r('sys.symbol.sun_max');
  }

  toggleReaderDayNightMode(): void {
    const currentMode = AppThemeModeStore.normalizeMode(this.appThemeMode);
    const nextMode = currentMode === 'light' ? 'dark' : (currentMode === 'dark' ? 'system' : 'light');
    this.appThemeMode = nextMode;
    if (nextMode === 'dark') {
      this.appDarkMode = true;
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (nextMode === 'light') {
      this.appDarkMode = false;
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
    AppThemeModeStore.save(getContext(this), nextMode).catch((e: Error) => {
      console.warn('保存日间/夜间/自动模式失败:', e);
    });
    this.saveReaderThemeSettings();
    promptAction.showToast({
      message: nextMode === 'light' ? '已切换至日间模式' :
        (nextMode === 'dark' ? '已切换至夜间模式' : '已切换至自动模式')
    });
  }

  @Builder
  readerFloatingBottomMenu() {
    Column({ space: 10 }) {
      Row() {
        Text('‹')
          .fontSize(30)
          .fontColor(this.currentChapterIndex > 0 && !this.isLoading ? this.getTextColor() : this.getSubTextColor())
          .width(46)
          .height(54)
          .textAlign(TextAlign.Center)
          .enabled(this.currentChapterIndex > 0 && !this.isLoading)
          .onClick(async () => {
            await this.jumpToAdjacentChapterFromMenu(-1);
          })

        Column({ space: 1 }) {
          Row() {
            Text(this.getChapterTitle(this.getMenuChapterDisplayIndex()))
              .fontSize(12)
              .fontColor(this.getSubTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(`${this.getMenuChapterDisplayIndex() + 1}/${this.chapters.length}`)
              .fontSize(11)
              .fontColor(this.getSubTextColor())
              .margin({ left: 8 })
          }
          .width('100%')

          Slider({
            value: this.getMenuChapterDisplayIndex(),
            min: 0,
            max: Math.max(0, this.chapters.length - 1),
            step: 1,
            style: SliderStyle.InSet
          })
            .width('100%')
            .height(24)
            .selectedColor(this.accentColor())
            .trackColor(this.readerChapterTrackColor())
            .blockColor(this.readerSolidPanelColor())
            .showSteps(false)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.handleMenuChapterSliderChange(value, mode);
            })
        }
        .layoutWeight(1)

        Text('›')
          .fontSize(30)
          .fontColor(this.currentChapterIndex < this.chapters.length - 1 && !this.isLoading ?
            this.getTextColor() : this.getSubTextColor())
          .width(46)
          .height(54)
          .textAlign(TextAlign.Center)
          .enabled(this.currentChapterIndex < this.chapters.length - 1 && !this.isLoading)
          .onClick(async () => {
            await this.jumpToAdjacentChapterFromMenu(1);
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 4, right: 4 })
      .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
      .backgroundColor(this.readerGlassPanelColor())
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })

      Row() {
        this.readerFloatingIconMenuItem($r('sys.symbol.list_bullet'), false, () => {
          this.openTocPanel();
        })
        this.readerFloatingIconMenuItem($r('sys.symbol.textformat'), false, () => {
          this.openSettingsPanel();
        })
        this.readerFloatingIconMenuItem($r('sys.symbol.speaker_wave_3'), this.isTtsSpeaking, () => {
          this.openTtsSettingsPanel();
        })
        this.readerFloatingIconMenuItem(this.readerDayNightIcon(), false, () => {
          this.toggleReaderDayNightMode();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
      .backgroundColor(this.readerGlassPanelColor())
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
    }
    .width('94%')
    .padding({ bottom: 14 })
    .position({ x: '3%', y: '100%' })
    .translate({ y: '-100%' })
  }

  @Builder
  readerFloatingIconMenuItem(icon: Resource, active: boolean, action: () => void,
    showAddBadge: boolean = false) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([this.getSubTextColor()])

        if (showAddBadge) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.getSubTextColor()])
            .position({ x: 20, y: 0 })
        }
      }
      .width(32)
      .height(32)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(28)
    .onClick(action)
  }

  @Builder
  readerFloatingTocPanel() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.isReaderThemeDark() ? '#52000000' : '#1AFFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('button', 12))
        .onClick(() => {
          this.showToc = false;
        })

      Column() {
        Row({ space: 14 }) {
          if (this.getTocCover()) {
            Image(this.getTocCover())
              .width(52)
              .height(68)
              .borderRadius(8)
              .objectFit(ImageFit.Cover)
          } else {
            Text(this.getTocBookInitial())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .textAlign(TextAlign.Center)
              .width(52)
              .height(68)
              .borderRadius(8)
              .backgroundColor(this.accentColor())
          }

          Column({ space: 5 }) {
            Text(this.book?.name || '目录')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.book?.author || '未知作者')
              .fontSize(12)
              .fontColor(this.getSubTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text('×')
            .fontSize(28)
            .fontColor(this.getTextColor())
            .textAlign(TextAlign.Center)
            .width(46)
            .height(46)
            .borderRadius(23)
            .backgroundColor(this.isReaderThemeDark() ? '#24FFFFFF' : '#0D000000')
            .accessibilityText('关闭目录')
            .onClick(() => {
              this.showToc = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 16, top: 12, bottom: 10 })
        .alignItems(VerticalAlign.Center)

        Row() {
          Text('目录')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tocPanelTab === 0 ? this.getTextColor() : this.getSubTextColor())
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(42)
            .borderRadius(21)
            .backgroundColor(this.tocPanelTab === 0 ? this.readerSolidPanelColor() : Color.Transparent)
            .shadow({ radius: this.tocPanelTab === 0 ? 8 : 0,
              color: this.readerGlassShadowColor(), offsetX: 0, offsetY: 2 })
            .onClick(() => {
              this.tocPanelTab = 0;
              this.cancelBookmarkMultiSelect();
              this.scrollTocToCurrentChapter(false);
            })
          Text('书签')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tocPanelTab === 1 ? this.getTextColor() : this.getSubTextColor())
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(42)
            .borderRadius(21)
            .backgroundColor(this.tocPanelTab === 1 ? this.readerSolidPanelColor() : Color.Transparent)
            .shadow({ radius: this.tocPanelTab === 1 ? 8 : 0,
              color: this.readerGlassShadowColor(), offsetX: 0, offsetY: 2 })
            .onClick(() => {
              this.tocPanelTab = 1;
              this.loadBookmarks();
            })
        }
        .width('100%')
        .height(46)
        .padding(2)
        .borderRadius(23)
        .backgroundColor(this.isReaderThemeDark() ? '#1FFFFFFF' : '#0D000000')
        .margin({ left: 20, right: 20 })

        if (this.tocPanelTab === 0) {
          this.tocPanelSummary()
          this.tocChapterList()
        } else {
          this.bookmarkPanelSummary()
          this.bookmarkList()
        }
      }
      .width('92%')
      .height('81%')
      .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
      .clip(true)
      .backgroundColor(this.readerGlassPanelColor())
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: '4%', y: '8%' })

      if (!this.supportsReaderImmersiveMaterial()) {
        Row() {
          this.readerFloatingIconMenuItem($r('sys.symbol.list_bullet'), true, () => {
            this.tocPanelTab = 0;
          })
          this.readerFloatingIconMenuItem($r('sys.symbol.textformat'), false, () => {
            this.showToc = false;
            this.openSettingsPanel();
          })
          this.readerFloatingIconMenuItem($r('sys.symbol.speaker_wave_3'), this.isTtsSpeaking, () => {
            this.showToc = false;
            this.openTtsSettingsPanel();
          })
          this.readerFloatingIconMenuItem(this.readerDayNightIcon(), false, () => {
            this.toggleReaderDayNightMode();
          })
        }
        .width('94%')
        .height(56)
        .padding({ left: 8, right: 8 })
        .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
        .backgroundColor(this.readerGlassPanelColor())
        .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
        .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
        .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
        .position({ x: '3%', y: '100%' })
        .translate({ y: -70 })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tocPanelSummary() {
    Row() {
      Text(`共 ${this.chapters.length} 章`)
        .fontSize(14)
        .fontColor(this.getSubTextColor())
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_up'))
        .fontSize(20)
        .fontColor([this.getTextColor()])
        .width(32)
        .height(36)
        .accessibilityText('跳到目录开头')
        .onClick(() => {
          this.scrollTocToChapter(0, ScrollAlign.START);
        })
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(20)
        .fontColor([this.getTextColor()])
        .width(32)
        .height(36)
        .accessibilityText('跳到目录末尾')
        .onClick(() => {
          this.scrollTocToChapter(this.chapters.length - 1, ScrollAlign.END);
        })
      if (this.tocQuickJumpInputVisible) {
        TextInput({ text: this.tocQuickJumpDraft, placeholder: `1-${this.chapters.length}` })
          .type(InputType.Number)
          .enterKeyType(EnterKeyType.Go)
          .key('tocQuickJumpChapterInput')
          .defaultFocus(true)
          .fontSize(13)
          .fontColor(this.getTextColor())
          .textAlign(TextAlign.Center)
          .width(92)
          .height(34)
          .padding({ left: 8, right: 8 })
          .borderRadius(17)
          .backgroundColor(this.isReaderThemeDark() ? '#2BFFFFFF' : '#14000000')
          .accessibilityText('输入目标章节序号，按回车定位')
          .onChange((value: string) => {
            this.tocQuickJumpDraft = value.replace(/[^0-9]/g, '').substring(0, 6);
          })
          .onSubmit(() => {
            this.submitTocQuickJump();
          })
      } else {
        Text(`当前 ${Math.min(this.currentChapterIndex + 1, this.chapters.length)}/${this.chapters.length}`)
          .fontSize(12)
          .fontColor(this.getTextColor())
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(this.isReaderThemeDark() ? '#1FFFFFFF' : '#0D000000')
          .accessibilityText(this.tocQuickJumpArmed ? '再次点击输入目标章节' : '回到当前章节')
          .onClick(() => {
            this.handleTocCurrentPositionClick();
          })
      }
      ImmersiveBackButton({
        icon: $r('sys.symbol.arrow_clockwise'),
        iconColor: this.getTextColor(),
        darkMode: this.isReaderThemeDark(),
        buttonSize: 34,
        containerWidth: 44,
        containerHeight: 44,
        startInset: 0,
        materialScale: 0.72,
        accessibilityLabel: '刷新目录',
        onBack: () => {
          this.refreshTocFromPanel();
        }
      })
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: 20, right: 16, top: 18, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  tocChapterList() {
    List({ space: 0, scroller: this.tocScroller }) {
      ForEach(this.tocVisibleChapters, (chapter: BookChapter, localIndex: number) => {
        ListItem() {
          Row({ space: 10 }) {
            Text(this.tocGlobalIndex(localIndex) === this.currentChapterIndex ? '•' : '·')
              .fontSize(this.tocGlobalIndex(localIndex) === this.currentChapterIndex ? 22 : 18)
              .fontColor(this.tocGlobalIndex(localIndex) === this.currentChapterIndex ?
                this.accentColor() : this.getSubTextColor())
              .width(18)
              .textAlign(TextAlign.Center)

            Text(this.getChapterTitle(this.tocGlobalIndex(localIndex)))
              .fontSize(15)
              .fontWeight(this.tocGlobalIndex(localIndex) === this.currentChapterIndex ?
                FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.getTocTitleColor(chapter, this.tocGlobalIndex(localIndex)))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            if (this.book?.origin !== 'local' && chapter.cacheDate > 0) {
              Text('已缓存')
                .fontSize(10)
                .fontColor(this.isReaderThemeDark() ? '#7CC7A0' : '#1F8F55')
                .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                .backgroundColor(this.isReaderThemeDark() ? '#24382F' : '#E6F4EC')
                .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ left: 14, right: 16, top: 14, bottom: 14 })
          .backgroundColor(this.tocGlobalIndex(localIndex) === this.currentChapterIndex ?
            this.tocSelectedBackgroundColor() : Color.Transparent)
          .border({ width: { bottom: 0.5 }, color: this.isReaderThemeDark() ? '#1FFFFFFF' : '#0D000000' })
          .onClick(async () => {
            const targetChapterIndex = this.tocGlobalIndex(localIndex);
            this.currentPageIndex = 0;
            this.pendingRestorePageIndex = 0;
            this.showToc = false;
            this.showMenu = false;
            await this.loadContent(false, targetChapterIndex);
            await this.saveReadingProgress();
          })
        }
      }, (chapter: BookChapter, localIndex: number) =>
        `${this.tocWindowStart + localIndex}_${chapter.url || chapter.title}`)
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Auto)
    .scrollBarColor(this.isReaderThemeDark() ? '#668A8F98' : '#667A6F63')
    .onReachStart(() => this.loadPreviousTocPage())
    .onReachEnd(() => this.loadNextTocPage())
  }

  @Builder
  bookmarkPanelSummary() {
    if (this.bookmarkMultiSelectMode) {
      Row({ space: 16 }) {
        Text(`已选 ${this.selectedBookmarkIds.length} 项`)
          .fontSize(14)
          .fontColor(this.getTextColor())
          .layoutWeight(1)
        Text(this.selectedBookmarkIds.length === this.bookmarks.length ? '取消全选' : '全选')
          .fontSize(13)
          .fontColor(this.accentColor())
          .onClick(() => {
            this.toggleSelectAllBookmarks();
          })
        Text('删除')
          .fontSize(13)
          .fontColor(this.selectedBookmarkIds.length > 0 ? '#D94841' : this.getSubTextColor())
          .enabled(this.selectedBookmarkIds.length > 0)
          .onClick(() => {
            this.deleteSelectedBookmarks();
          })
        Text('取消')
          .fontSize(13)
          .fontColor(this.getSubTextColor())
          .onClick(() => {
            this.cancelBookmarkMultiSelect();
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
    } else {
      Row() {
        Text(`${this.bookmarks.length} 条书签`)
          .fontSize(14)
          .fontColor(this.getSubTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 10 })
    }
  }

  @Builder
  bookmarkList() {
    if (this.bookmarks.length === 0) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(34)
          .fontColor([this.getSubTextColor()])
        Text('暂无书签')
          .fontSize(15)
          .fontColor(this.getSubTextColor())
        Text('可使用底栏最右侧按钮添加当前阅读位置')
          .fontSize(12)
          .fontColor(this.getSubTextColor())
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      List({ space: 0, scroller: this.bookmarkScroller }) {
        ForEach(this.bookmarks, (bookmark: Bookmark) => {
          ListItem() {
            Column({ space: 5 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.bookmark'))
                  .fontSize(18)
                  .fontColor([this.accentColor()])
                  .width(26)
                Text(bookmark.chapterName || `第 ${bookmark.chapterIndex + 1} 章`)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(`第 ${bookmark.pageIndex + 1} 页`)
                  .fontSize(11)
                  .fontColor(this.getSubTextColor())
                if (this.bookmarkMultiSelectMode) {
                  if (this.isBookmarkSelected(bookmark.id)) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle'))
                      .fontSize(21)
                      .fontColor([this.accentColor()])
                      .margin({ left: 10 })
                  } else {
                    Circle()
                      .width(19)
                      .height(19)
                      .fill(Color.Transparent)
                      .stroke(this.getSubTextColor())
                      .strokeWidth(1.5)
                      .margin({ left: 10 })
                  }
                }
              }
              .width('100%')

              Text(bookmark.content || '已保存阅读位置')
                .fontSize(12)
                .fontColor(this.getSubTextColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(this.formatBookmarkTime(bookmark.createTime))
                .fontSize(10)
                .fontColor(this.getSubTextColor())
                .width('100%')
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .backgroundColor(this.isBookmarkSelected(bookmark.id) ? this.tocSelectedBackgroundColor() : Color.Transparent)
            .border({ width: { bottom: 0.5 }, color: this.isReaderThemeDark() ? '#1FFFFFFF' : '#0D000000' })
            .onClick(() => {
              if (this.bookmarkMultiSelectMode) {
                this.toggleBookmarkSelection(bookmark.id);
              } else {
                this.jumpToBookmark(bookmark);
              }
            })
            .gesture(
              LongPressGesture({ repeat: false })
                .onAction((event: GestureEvent) => {
                  if (!this.bookmarkMultiSelectMode) {
                    this.showBookmarkActions(bookmark, event);
                  }
                })
            )
          }
          .swipeAction({
            start: {
              builder: this.bookmarkMultiSelectAction.bind(this, bookmark),
              actionAreaDistance: 64,
              onAction: () => {
                this.enterBookmarkMultiSelect(bookmark.id);
              }
            },
            end: {
              builder: this.bookmarkDeleteAction.bind(this, bookmark),
              actionAreaDistance: 64,
              onAction: () => {
                this.deleteBookmark(bookmark);
              }
            },
            edgeEffect: SwipeEdgeEffect.Spring
          })
        }, (bookmark: Bookmark) => `${bookmark.id}`)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .scrollBarColor(this.isReaderThemeDark() ? '#668A8F98' : '#667A6F63')
    }
  }

  @Builder
  bookmarkDeleteAction(bookmark: Bookmark) {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#D94841')
    .onClick(() => {
      this.deleteBookmark(bookmark);
    })
  }

  @Builder
  readerActionMenu() {
    Column() {
      this.readerActionMenuItem(
        $r('sys.symbol.bookmark'),
        this.isCurrentPageBookmarked() ? '删除书签' : '添加书签',
        () => this.toggleCurrentPageBookmark()
      )
      this.readerActionMenuItem(
        this.isTtsSpeaking ? $r('sys.symbol.pause') : $r('sys.symbol.play'),
        this.isTtsSpeaking ? '停止朗读' : '开始朗读',
        () => this.toggleTtsReading()
      )
      if (this.book && !LocalBookService.isLocalBook(this.book)) {
        this.readerActionMenuItem(
          $r('sys.symbol.arrow_clockwise'),
          '刷新本章',
          () => this.refreshCurrentChapter(),
          this.chapters.length > 0
        )
        this.readerActionMenuItem(
          $r('sys.symbol.arrow_left_arrow_right'),
          '换源',
          () => this.openChangeSourceDialog()
        )
      }
      if (this.readerSourceNeedsLogin()) {
        this.readerActionMenuItem(
          $r('sys.symbol.checkmark_shield'),
          '登录',
          () => this.openReaderSourceLogin()
        )
      }
      if (this.readerCanRetry()) {
        this.readerActionMenuItem(
          $r('sys.symbol.exclamationmark_circle'),
          '重试',
          () => this.retryReaderContent()
        )
      }
      this.readerActionMenuItem(
        $r('sys.symbol.textformat'),
        '阅读设置',
        () => this.openSettingsPanel()
      )
      this.readerActionMenuItem(
        $r('sys.symbol.speaker_wave_3'),
        '朗读设置',
        () => this.openTtsSettingsPanel(),
        true,
        false
      )
    }
    .width(220)
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor(this.readerGlassPanelColor())
    .borderRadius(ThemeRuntime.glassCornerRadius(22, 'panel'))
    .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
    .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
    .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
    .position({ x: '100%', y: 0 })
    .translate({ x: -232, y: this.getTopControlSafePadding() + 72 })
    .onClick(() => {
    })
  }

  @Builder
  readerActionMenuItem(icon: Resource, label: string, action: () => void,
    enabled: boolean = true, showDivider: boolean = true) {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph(icon)
          .fontSize(21)
          .fontColor([this.getTextColor()])
          .width(24)

        Text(label)
          .fontSize(16)
          .fontColor(this.getTextColor())
          .maxLines(1)
          .layoutWeight(1)
      }
      .width('100%')
      .height(46)
      .padding({ left: 10, right: 10 })

      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(this.readerGlassBorderColor())
          .margin({ left: 46, right: 8 })
      }
    }
    .width('100%')
    .opacity(enabled ? 1 : 0.38)
    .enabled(enabled)
    .onClick(() => {
      if (!enabled) return;
      this.showReaderActionMenu = false;
      action();
    })
  }

  currentReaderSource(): BookSource | null {
    return ReadBookEngine.get().source;
  }

  readerSourceNeedsLogin(): boolean {
    const source = this.currentReaderSource();
    if (!source) return false;
    if (this.verificationUrl) return true;
    const loginUrl = String(source.loginUrl || '').trim();
    const loginUi = String(source.loginUi || '').trim();
    const loginCheckJs = String(source.loginCheckJs || '').trim();
    const loginHeader = String(source.loginHeader || '').trim();
    if (loginUrl || loginUi || loginCheckJs || loginHeader) return true;
    const rules = `${source.jsLib || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}\n` +
      `${source.bookInfoRule?.init || ''}\n${source.tocRule?.chapterList || ''}\n${source.contentRule?.content || ''}`;
    return /loginCheck|loginUrl|loginUi|book-source-login|请先登[录陆]|需要登[录陆]|账号登[录陆]|网页登录|登[录陆]后/i.test(rules);
  }

  readerSourceUsesEditorLogin(source: BookSource): boolean {
    const raw = `${source.bookSourceName || ''}\n${source.bookSourceUrl || ''}\n${source.loginUrl || ''}\n${source.jsLib || ''}`.toLowerCase();
    return raw.includes('书山') || raw.includes('shushan');
  }

  openReaderSourceLogin(): void {
    const source = this.currentReaderSource();
    if (!source || !this.readerSourceNeedsLogin()) return;
    this.showReaderActionMenu = false;
    this.showMenu = false;
    if (this.readerSourceUsesEditorLogin(source)) {
      router.pushUrl({
        url: 'pages/BookSourceEdit',
        params: { bookSourceUrl: source.bookSourceUrl }
      });
      return;
    }
    const loginEntryUrl = this.verificationUrl || VerificationSupport.resolveBookSourceLoginUrl(source) ||
      VerificationSupport.pickVerificationUrl(source, source.bookSourceUrl);
    if (!loginEntryUrl || !/^https?:\/\//i.test(loginEntryUrl)) {
      promptAction.showToast({ message: '未找到可用的网页登录地址，请检查书源登录配置' });
      return;
    }
    VerificationSupport.requestVerification(loginEntryUrl, `${source.bookSourceName || '书源'} 登录`, source);
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: loginEntryUrl,
        title: `${source.bookSourceName || '书源'} 登录`,
        requireLoginCookie: 'true'
      }
    });
  }

  readerCanRetry(): boolean {
    return (this.chapters.length === 0 && this.book?.origin !== 'local') || !!this.verificationUrl;
  }

  retryReaderContent(): void {
    this.hideReaderPanels();
    if (this.chapters.length === 0) {
      this.retryFetchChapters();
    } else {
      this.loadContent();
    }
  }

  @Builder
  readerTtsQuickActionButton() {
    Stack({ alignContent: Alignment.Center }) {
      ImmersiveBackButton({
        icon: $r('sys.symbol.play'),
        iconColor: this.getTextColor(),
        darkMode: this.isReaderThemeDark(),
        buttonSize: 48,
        containerWidth: 56,
        containerHeight: 48,
        startInset: 0,
        accessibilityLabel: this.isTtsSpeaking ? '展开朗读控制' : '开始朗读',
        onBack: () => {
          if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
            this.ttsMediaControlsExpanded = !this.ttsMediaControlsExpanded;
            this.syncTtsSystemMediaControls();
          } else {
            this.toggleTtsReading();
          }
        }
      })

      if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
        Circle()
          .width(9)
          .height(9)
          .fill(this.accentColor())
          .stroke(this.readerContentLayerColor())
          .strokeWidth(2)
          .position({ x: 47, y: 6 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(64)
    .height(48)
    .position({ x: '100%', y: '100%' })
    .translate({
      x: -(64 + this.readerFloatingBarSideInset()),
      y: -(this.readerBottomMenuOverlayHeight() + 62)
    })
  }

  @Builder
  bookmarkMultiSelectAction(bookmark: Bookmark) {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('多选')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.accentColor())
    .onClick(() => {
      this.enterBookmarkMultiSelect(bookmark.id);
    })
  }

  showBookmarkActions(bookmark: Bookmark, event: GestureEvent): void {
    if (event.fingerList.length > 0) {
      const finger = event.fingerList[0];
      this.bookmarkActionMenuX = finger.globalX;
      this.bookmarkActionMenuY = finger.globalY;
    }
    this.pendingBookmarkAction = bookmark;
    this.showBookmarkActionMenu = true;
  }

  closeBookmarkActionMenu(): void {
    this.showBookmarkActionMenu = false;
    this.pendingBookmarkAction = null;
  }

  bookmarkActionMenuLeft(menuWidth: number): number {
    const viewportWidth = this.pageViewWidth > 0 ? this.pageViewWidth : 360;
    return Math.max(12, Math.min(this.bookmarkActionMenuX - 18, viewportWidth - menuWidth - 12));
  }

  bookmarkActionMenuTop(menuHeight: number): number {
    const viewportHeight = this.pageViewHeight > 0 ? this.pageViewHeight : 720;
    const below = this.bookmarkActionMenuY + 12;
    if (below + menuHeight <= viewportHeight - 12) {
      return below;
    }
    return Math.max(this.getReaderTopSafePadding() + 8, this.bookmarkActionMenuY - menuHeight - 12);
  }

  @Builder
  bookmarkActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.isReaderThemeDark() ? '#52000000' : '#26FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
        .onClick(() => {
          this.closeBookmarkActionMenu();
        })

      Column() {
        this.bookmarkContextActionItem($r('sys.symbol.checkmark_circle'), '多选', this.getTextColor(), () => {
          if (this.pendingBookmarkAction) {
            const bookmarkId = this.pendingBookmarkAction.id;
            this.closeBookmarkActionMenu();
            this.enterBookmarkMultiSelect(bookmarkId);
          }
        })
        this.bookmarkContextActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => {
          if (this.pendingBookmarkAction) {
            const bookmark = this.pendingBookmarkAction;
            this.closeBookmarkActionMenu();
            this.deleteBookmark(bookmark);
          }
        })
      }
      .width(148)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(this.readerGlassPanelColor())
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.bookmarkActionMenuLeft(148), y: this.bookmarkActionMenuTop(100) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  bookmarkContextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([color])
        .width(26)
      Text(label)
        .fontSize(15)
        .fontColor(color)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  getTocCover(): string {
    return this.book ? this.book.getDisplayCover() : '';
  }

  getTocBookInitial(): string {
    const name = (this.book?.name || '书').trim();
    return name.length > 0 ? name.substring(0, 1) : '书';
  }

  getChapterTitle(chapterIndex: number = this.currentChapterIndex): string {
    if (this.chapters.length === 0) return '暂无目录';
    const chapter = this.chapters[this.clampChapterIndex(chapterIndex)];
    const title = chapter ? this.cleanChapterTitle(chapter.title) : '';
    return ReaderReplaceRuleStore.applyTitle(title, this.readerReplaceRules, this.book);
  }

  applyReaderContentRules(content: string): string {
    return ReaderReplaceRuleStore.applyContent(content, this.readerReplaceRules, this.book);
  }

  onReaderReplaceRulesChanged(): void {
    if (this.readerEntryInitializing) {
      return;
    }
    this.reloadReaderReplaceRules(true).catch((error: Error) => {
      console.warn('更新替换净化规则失败:', error);
    });
  }

  async reloadReaderReplaceRules(repaginate: boolean): Promise<void> {
    this.readerReplaceRules = await ReaderReplaceRuleStore.load(getContext(this), true);
    this.readerPaginationCache.clear();
    this.adjacentPaginationPreloadSerial++;
    this.pageTurnPreviewKey = '';
    this.pageTurnPreviewLoadingKey = '';
    if (!repaginate || !this.book || this.chapters.length === 0) {
      return;
    }
    const raw = ReadBookEngine.get().getCachedContent(this.currentChapterIndex);
    if (!raw) {
      return;
    }
    const processed = this.applyReaderContentRules(raw);
    this.content = processed;
    this.paginateContent(processed, this.currentChapterIndex);
    this.refreshReaderTextRender();
  }

  cleanChapterTitle(title: string): string {
    const original = (title || '').trim();
    const cleaned = original
      .replace(/\s+/g, ' ')
      .replace(/[\s·|｜/／-]*上次(?:阅读|閱讀)(?:[\s:：，,。]*.*)?$/g, '')
      .replace(/^上次(?:阅读|閱讀)[\s:：，,。]*/g, '')
      .trim();
    return cleaned || original;
  }

  updatePendingVerification(): void {
    this.verificationUrl = AppStorage.get<string>('pendingVerificationUrl') || '';
    this.verificationTitle = AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
  }

  openVerificationPage(): void {
    const url = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
    if (!url) return;
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: this.verificationTitle || '网页验证'
      }
    });
  }

  getProgressText(): string {
    if (this.chapters.length === 0) return '';
    if (this.contentPages.length === 0) {
      return `${this.currentChapterIndex + 1}/${this.chapters.length}`;
    }
    const pageText = this.isLandscapeDoublePageActive() ?
      `${this.currentPageIndex + 1}-${Math.min(this.currentPageIndex + 2, this.contentPages.length)}` :
      `${this.currentPageIndex + 1}`;
    return `${this.currentChapterIndex + 1}/${this.chapters.length} · ${pageText}/${this.contentPages.length}`;
  }

  getChapterInfoText(): string {
    if (this.chapters.length === 0) {
      return this.book?.name || '暂无目录';
    }
    const index = this.clampChapterIndex(this.currentChapterIndex);
    const chapter = this.chapters[index];
    return `${index + 1}/${this.chapters.length} ${chapter ? this.getChapterTitle(index) : this.getChapterTitle()}`;
  }

  getPageInfoText(): string {
    if (this.contentPages.length === 0) {
      return '1/1';
    }
    const index = Math.max(0, Math.min(this.currentPageIndex, this.contentPages.length - 1));
    if (this.isLandscapeDoublePageActive()) {
      const end = Math.min(index + 2, this.contentPages.length);
      return `${index + 1}-${end}/${this.contentPages.length}`;
    }
    return `${index + 1}/${this.contentPages.length}`;
  }

  getPageText(pageIndex: number): string {
    if (this.contentPages.length === 0) {
      if (this.content && !this.hasPagedReaderArea()) {
        return '';
      }
      return this.content;
    }
    const index = Math.max(0, Math.min(pageIndex, this.contentPages.length - 1));
    return this.contentPages[index];
  }

  getCurrentPageText(): string {
    return this.getPageText(this.currentPageIndex);
  }

  isLandscapeDoublePageActive(): boolean {
    return this.readerLandscapeDoublePage &&
      (this.pageViewWidth > this.pageViewHeight || this.pageViewWidth >= 600);
  }

  getReaderPageTurnStep(): number {
    return this.isLandscapeDoublePageActive() ? 2 : 1;
  }

  normalizeReaderSpreadPageIndex(pageIndex: number): number {
    const safeIndex = Math.max(0, Math.round(pageIndex));
    return this.isLandscapeDoublePageActive() ? Math.floor(safeIndex / 2) * 2 : safeIndex;
  }

  getSecondaryPageText(pageIndex: number = this.currentPageIndex): string {
    if (!this.isLandscapeDoublePageActive() || pageIndex + 1 >= this.contentPages.length) {
      return '';
    }
    return this.getPageText(pageIndex + 1);
  }

  currentReaderSurfaceIndex(): number {
    return Math.abs(this.currentChapterIndex + this.currentPageIndex) % 2;
  }

  currentReaderSurfaceKeys(): string[] {
    return [this.currentReaderPageRenderIdentity(this.pageRenderVersion, this.ttsHighlightRenderVersion)];
  }

  visibleCurrentPageText(): string {
    if (!this.shouldRenderSlidingPageTurn()) {
      const pageText = this.getCurrentPageText();
      return pageText || this.currentPageText || this.displayPageText;
    }
    if (this.displayPageChapterIndex === this.currentChapterIndex &&
      this.displayPageIndex === this.currentPageIndex && this.displayPageText) {
      return this.displayPageText;
    }
    const pageText = this.getCurrentPageText();
    return pageText || this.currentPageText;
  }

  syncCurrentPageText(): void {
    this.setCurrentPageText(this.getCurrentPageText());
  }

  setCurrentPageText(text: string): void {
    const nextText = text || '';
    if (this.currentPageText !== nextText) {
      this.chapterJumpRenderGeneration++;
    }
    this.currentPageText = nextText;
    this.displayPageText = nextText;
    this.displayPageChapterIndex = this.currentChapterIndex;
    this.displayPageIndex = this.currentPageIndex;
    this.displayPageRenderKey++;
    this.pageRenderVersion++;
  }

  parseAreaDimension(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value !== 'string') {
      return 0;
    }
    const text = String(value || '').trim();
    const match = text.match(/-?\d+(\.\d+)?/);
    if (!match) {
      return 0;
    }
    const parsed = Number(match[0]);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  updatePagedReaderArea(area: Area): void {
    const width = this.parseAreaDimension(area.width);
    const height = Math.max(1, this.parseAreaDimension(area.height) - this.getReaderPageContentTopPadding());
    if (width <= 0 || height <= 0) {
      return;
    }
    if (Math.abs(this.pageViewWidth - width) < 0.5 && Math.abs(this.pageViewHeight - height) < 0.5) {
      return;
    }
    const shouldRestoreSavedPage = this.pendingRestorePageIndex >= 0;
    const readingOffset = this.getCurrentPageStartOffset();
    this.pageViewWidth = width;
    this.pageViewHeight = height;
    this.paginateContent(this.content);
    if (!shouldRestoreSavedPage) {
      this.currentPageIndex = this.normalizeReaderSpreadPageIndex(this.findPageIndexByOffset(readingOffset));
    }
    this.syncCurrentPageText();
    this.preloadNextChapterPaginationLater();
  }

  hasPagedReaderArea(): boolean {
    return this.pageViewWidth > 0 && this.pageViewHeight > 0;
  }

  getCurrentPageStartOffset(): number {
    return this.getPageStartOffset(this.currentPageIndex);
  }

  getPageStartOffset(pageIndex: number): number {
    if (this.contentPageStarts.length === 0) {
      return 0;
    }
    const index = Math.max(0, Math.min(pageIndex, this.contentPageStarts.length - 1));
    return Math.max(0, this.contentPageStarts[index]);
  }

  getPageEndOffset(pageIndex: number): number {
    if (this.contentPageEnds.length === 0) {
      return this.content.length;
    }
    const index = Math.max(0, Math.min(pageIndex, this.contentPageEnds.length - 1));
    return Math.max(this.getPageStartOffset(index), this.contentPageEnds[index]);
  }

  findPageIndexByOffset(offset: number): number {
    if (this.contentPageStarts.length === 0) {
      return Math.max(0, Math.min(this.currentPageIndex, Math.max(0, this.contentPages.length - 1)));
    }
    const sourceLength = this.pagedContentText ? this.pagedContentText.length : this.content.length;
    const clampedOffset = Math.max(0, Math.min(offset, Math.max(0, sourceLength - 1)));
    for (let i = 0; i < this.contentPageStarts.length; i++) {
      if (clampedOffset >= this.contentPageStarts[i] && clampedOffset < this.contentPageEnds[i]) {
        return i;
      }
      if (i < this.contentPageStarts.length - 1 &&
        clampedOffset >= this.contentPageEnds[i] && clampedOffset < this.contentPageStarts[i + 1]) {
        return i + 1;
      }
    }
    return Math.max(0, this.contentPageStarts.length - 1);
  }

  getBackgroundColor(): string {
    return this.currentReaderTheme().backgroundColor;
  }

  getBackgroundAssetId(): string {
    return this.currentReaderTheme().backgroundAssetId || '';
  }

  getBackgroundImage(): ResourceStr {
    return this.currentReaderTheme().backgroundImageUri || ThemeAssetRegistry.readerBackground(this.getBackgroundAssetId());
  }

  getBackgroundImageSize(): ImageSize {
    const fit = this.currentReaderTheme().backgroundImageFit;
    if (fit === 'contain') {
      return ImageSize.Contain;
    }
    if (fit === 'fill') {
      return ImageSize.FILL;
    }
    return ImageSize.Cover;
  }

  getBackgroundImageFit(): ImageFit {
    const fit = this.currentReaderTheme().backgroundImageFit;
    if (fit === 'contain') {
      return ImageFit.Contain;
    }
    if (fit === 'fill') {
      return ImageFit.Fill;
    }
    return ImageFit.Cover;
  }

  hasBackgroundImage(): boolean {
    return !!this.currentReaderTheme().backgroundImageUri || !!this.getBackgroundAssetId();
  }

  readerContentLayerColor(): string {
    return this.hasBackgroundImage() ? '#00000000' : this.getBackgroundColor();
  }

  getTextColor(): string {
    return this.currentReaderTheme().textColor;
  }

  currentReaderThemeIndex(): number {
    return this.appDarkMode ? this.readerDarkThemeIndex : this.readerLightThemeIndex;
  }

  currentReaderThemes(): ReaderThemeItem[] {
    const custom = this.currentCustomThemeScheme();
    return ReaderThemeHelper.themes(
      this.appDarkMode,
      custom.backgroundColor,
      custom.textColor,
      this.currentCustomThemeBackgroundImageUri(),
      custom.backgroundImageFit
    );
  }

  currentReaderTheme(): ReaderThemeItem {
    return ReaderThemeHelper.themeAt(
      this.appDarkMode,
      this.currentReaderThemeIndex(),
      this.currentCustomThemeBackgroundColor(),
      this.currentCustomThemeTextColor(),
      this.currentCustomThemeBackgroundImageUri(),
      this.currentCustomThemeScheme().backgroundImageFit
    );
  }

  currentCustomThemeBackgroundColor(): string {
    return this.currentCustomThemeScheme().backgroundColor;
  }

  currentCustomThemeTextColor(): string {
    return this.currentCustomThemeScheme().textColor;
  }

  currentCustomThemeBackgroundImageUri(): string {
    const current = this.currentCustomThemeScheme();
    return current.backgroundType === 'image' ? current.backgroundImageUri : '';
  }

  currentCustomThemeBackgroundTypeIndex(): number {
    return this.currentCustomThemeScheme().backgroundType === 'image' ? 1 : 0;
  }

  customThemeData(): ReaderCustomThemeData {
    return ReaderCustomThemeHelper.parse(
      this.readerCustomThemesRaw,
      this.readerLightCustomThemeBackgroundColor,
      this.readerLightCustomThemeTextColor,
      this.readerDarkCustomThemeBackgroundColor,
      this.readerDarkCustomThemeTextColor
    );
  }

  currentCustomThemeScheme(): ReaderCustomThemeScheme {
    return ReaderCustomThemeHelper.selected(this.customThemeData(), this.appDarkMode);
  }

  currentCustomThemeSchemes(): ReaderCustomThemeScheme[] {
    return ReaderCustomThemeHelper.schemesForMode(this.customThemeData(), this.appDarkMode);
  }

  currentCustomThemeSelectedIndex(): number {
    const schemes = this.currentCustomThemeSchemes();
    const selectedId = this.currentCustomThemeScheme().id;
    const index = schemes.findIndex((item: ReaderCustomThemeScheme) => item.id === selectedId);
    return Math.max(0, index);
  }

  customThemeOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const item of this.currentCustomThemeSchemes()) {
      const option: SelectOption = { value: item.name };
      options.push(option);
    }
    return options;
  }

  customThemeFitSelectedIndex(): number {
    const fit = this.currentCustomThemeScheme().backgroundImageFit;
    return fit === 'contain' ? 1 : (fit === 'fill' ? 2 : 0);
  }

  normalizeColor(color: string, fallback: string): string {
    const trimmed = (color || '').trim();
    const normalized = trimmed.startsWith('#') ? trimmed : `#${trimmed}`;
    if (/^#[0-9a-fA-F]{6}$/.test(normalized)) {
      return normalized.toUpperCase();
    }
    const fallbackTrimmed = (fallback || '').trim();
    const normalizedFallback = fallbackTrimmed.startsWith('#') ? fallbackTrimmed : `#${fallbackTrimmed}`;
    return /^#[0-9a-fA-F]{6}$/.test(normalizedFallback) ? normalizedFallback.toUpperCase() : '#333333';
  }

  isReaderThemeDark(): boolean {
    const tone = this.currentReaderTheme().contentTone;
    if (tone === 'dark' || tone === 'light') {
      return tone === 'dark';
    }
    return this.isDarkHexColor(this.getBackgroundColor());
  }

  isDarkHexColor(color: string): boolean {
    const normalized = (color || '').trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(normalized)) {
      return this.appDarkMode;
    }
    const red = parseInt(normalized.substring(1, 3), 16);
    const green = parseInt(normalized.substring(3, 5), 16);
    const blue = parseInt(normalized.substring(5, 7), 16);
    return red * 0.299 + green * 0.587 + blue * 0.114 < 128;
  }

  getReaderFontFamily(): string {
    const family = this.resolveReaderFontFamily();
    if (family !== this.lastLoggedReaderFontFamily) {
      this.lastLoggedReaderFontFamily = family;
      console.info(`阅读正文使用字体: ${family}`);
    }
    return family;
  }

  getBodyReaderFontFamily(): string {
    return this.resolveStyledReaderFontFamily(this.readerBodyFontMode, this.readerBodyFontFamily);
  }

  getTitleReaderFontFamily(): string {
    if (this.readerTitleFontMode === 'global' && !this.readerTitleFontFamily) {
      return this.getReaderFontFamily();
    }
    return this.resolveStyledReaderFontFamily(this.readerTitleFontMode, this.readerTitleFontFamily);
  }

  getRegexReaderFontFamily(): string {
    return this.resolveStyledReaderFontFamily(this.readerRegexFontMode, this.readerRegexFontFamily);
  }

  resolveStyledReaderFontFamily(mode: string, family: string): string {
    if (mode === 'system') {
      return this.getSystemReaderFontFamily();
    }
    if (mode === 'custom' && family) {
      return this.resolveCustomReaderFontFamily(family);
    }
    return this.getReaderFontFamily();
  }

  resolveCustomReaderFontFamily(family: string): string {
    if (!family) {
      return '';
    }
    const raw = AppStorage.get<string>('readerCustomFontsRaw') || '';
    if (!raw.trim()) {
      return family;
    }
    try {
      const parsed = JSON.parse(raw) as ReaderCustomFontData | ReaderCustomFontItem[];
      const source = Array.isArray(parsed) ? parsed as ReaderCustomFontItem[] : ((parsed as ReaderCustomFontData).fonts || []);
      for (const item of source) {
        if (!item || !item.filePath) {
          continue;
        }
        const stableFamily = ReaderFontHelper.normalizeFontFamily(item.filePath);
        if (item.familyName === family || stableFamily === family) {
          return stableFamily;
        }
      }
    } catch (e) {
      console.warn('解析阅读自定义字体失败:', e);
    }
    return family;
  }

  registerCustomReaderFontFamily(family: string): void {
    if (!family) {
      return;
    }
    const raw = AppStorage.get<string>('readerCustomFontsRaw') || '';
    if (!raw.trim()) {
      return;
    }
    try {
      const parsed = JSON.parse(raw) as ReaderCustomFontData | ReaderCustomFontItem[];
      const source = Array.isArray(parsed) ? parsed as ReaderCustomFontItem[] : ((parsed as ReaderCustomFontData).fonts || []);
      for (const item of source) {
        if (!item || !item.filePath) {
          continue;
        }
        const stableFamily = ReaderFontHelper.normalizeFontFamily(item.filePath);
        if (item.familyName !== family && stableFamily !== family) {
          continue;
        }
        const fontItem = new ReaderFontItem();
        fontItem.familyName = stableFamily;
        fontItem.filePath = item.filePath;
        fontItem.sourceName = item.sourceName || this.fileNameFromPath(item.filePath);
        ReaderFontHelper.registerFont(this.getUIContext(), fontItem);
        return;
      }
    } catch (e) {
      console.warn('解析阅读自定义字体失败:', e);
    }
  }

  registerStyledCustomReaderFonts(): void {
    if (this.readerBodyFontMode === 'custom') {
      this.registerCustomReaderFontFamily(this.readerBodyFontFamily);
    }
    if (this.readerTitleFontMode === 'custom') {
      this.registerCustomReaderFontFamily(this.readerTitleFontFamily);
    }
    if (this.readerRegexFontMode === 'custom') {
      this.registerCustomReaderFontFamily(this.readerRegexFontFamily);
    }
    const rules = this.getRegexRules();
    for (const rule of rules) {
      if (rule.fontMode === 'custom') {
        this.registerCustomReaderFontFamily(rule.fontFamily);
      }
    }
  }

  resolveReaderFontFamily(): string {
    if (this.activeReaderFontFamily) {
      return this.activeReaderFontFamily;
    }
    if (this.readerActiveFontFamily) {
      return this.readerActiveFontFamily;
    }
    return this.readerFontFamily || ThemeRuntime.fontFamily() || this.getSystemReaderFontFamily();
  }

  getSystemReaderFontFamily(): string {
    return this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext());
  }

  isReaderFontReady(): boolean {
    return !!this.activeReaderFontFamily || !!this.readerActiveFontFamily;
  }

  clearReaderFontState(): void {
    this.activeReaderFontFamily = '';
    this.readerFontRegistered = false;
    this.readerActiveFontFamily = '';
    this.readerStoredFontRegistered = false;
    this.readerFontRenderReady = false;
    this.applyReaderApplicationFont(this.getSystemReaderFontFamily());
  }

  async registerReaderFont(): Promise<boolean> {
    if (!this.readerFontFilePath) {
      this.clearReaderFontState();
      return false;
    }
    return await this.registerReaderFontAsync('readbook-sync-request');
  }

  async registerReaderFontBySettings(fontFamily: string, fontFilePath: string, fontSourceName: string): Promise<boolean> {
    if (!fontFilePath) {
      this.clearReaderFontState();
      return false;
    }
    this.readerFontFamily = fontFamily || ReaderFontHelper.normalizeFontFamily(fontFilePath);
    this.readerFontFilePath = fontFilePath;
    AppStorage.setOrCreate<string>('readerFontSourceName', fontSourceName || this.fileNameFromPath(fontFilePath));
    return await this.registerReaderFontAsync('readbook-register-by-settings');
  }

  async registerReaderFontAsync(source: string): Promise<boolean> {
    if (!this.readerFontFilePath) {
      this.clearReaderFontState();
      return false;
    }
    const requestedPath = this.readerFontFilePath;
    const registered = await ReaderFontBootstrap.registerFromSettings(getContext(this), this.getUIContext(), source);
    if (!this.readerFontFilePath) {
      this.clearReaderFontState();
      return false;
    }
    if (requestedPath !== this.readerFontFilePath) {
      return false;
    }
    if (!registered) {
      if (this.readerFontFilePath) {
        this.readerFontRegistered = false;
        this.readerStoredFontRegistered = false;
        this.readerActiveFontFamily = '';
        this.activeReaderFontFamily = '';
        this.readerFontRenderReady = false;
      }
      return false;
    }
    const activeFamily = AppStorage.get<string>('readerActiveFontFamily') || '';
    const activePath = AppStorage.get<string>('readerFontFilePath') || this.readerFontFilePath;
    if (activePath && activePath !== this.readerFontFilePath) {
      this.replaceReaderCustomFontPath(this.readerFontFilePath, activePath, ReaderFontHelper.normalizeFontFamily(activePath));
      this.readerFontFilePath = activePath;
    }
    const stableFamily = activePath ? ReaderFontHelper.normalizeFontFamily(activePath) : this.readerFontFamily;
    if (stableFamily && this.readerFontFamily !== stableFamily) {
      this.readerFontFamily = stableFamily;
    }
    this.activateRegisteredReaderFont(activeFamily);
    this.refreshReaderTextRender();
    this.paginateContent(this.content);
    return true;
  }

  activateRegisteredReaderFont(familyName: string): void {
    if (this.readerFontRegistered && this.activeReaderFontFamily === familyName) {
      this.readerFontRenderReady = false;
      this.refreshRegisteredReaderFontLater(familyName, 80);
      this.refreshRegisteredReaderFontLater(familyName, 240);
      return;
    }
    this.readerActiveFontFamily = familyName;
    this.readerStoredFontRegistered = true;
    this.readerFontRegistered = true;
    this.activeReaderFontFamily = familyName;
    this.readerFontRenderReady = false;
    setTimeout(() => {
      this.activeReaderFontFamily = familyName;
      this.readerFontRegistered = true;
      this.readerActiveFontFamily = familyName;
      this.readerStoredFontRegistered = true;
      this.refreshReaderTextRender();
      this.paginateContent(this.content);
    }, 0);
    this.refreshRegisteredReaderFontLater(familyName, 80);
    this.refreshRegisteredReaderFontLater(familyName, 240);
  }

  refreshRegisteredReaderFontLater(familyName: string, delayMs: number): void {
    setTimeout(() => {
      if (!familyName || this.activeReaderFontFamily !== familyName) {
        return;
      }
      this.readerFontRenderReady = true;
      console.info(`阅读字体延迟刷新: family=${familyName}, delay=${delayMs}`);
      this.refreshReaderTextRender();
      this.paginateContent(this.content);
    }, delayMs);
  }

  applyLoadedReaderSettings(settings: ReaderSettings): void {
    this.readerFontSize = settings.fontSize;
    this.readerLineHeight = settings.lineHeight;
    this.readerParagraphSpacing = settings.paragraphSpacing;
    this.readerMarginLeft = settings.marginLeft;
    this.readerMarginRight = settings.marginRight;
    this.readerMarginTop = settings.marginTop;
    this.readerMarginBottom = settings.marginBottom;
    this.readerLightThemeIndex = settings.lightThemeIndex;
    this.readerDarkThemeIndex = settings.darkThemeIndex;
    this.readerLightCustomThemeBackgroundColor = settings.lightCustomThemeBackgroundColor;
    this.readerLightCustomThemeTextColor = settings.lightCustomThemeTextColor;
    this.readerDarkCustomThemeBackgroundColor = settings.darkCustomThemeBackgroundColor;
    this.readerDarkCustomThemeTextColor = settings.darkCustomThemeTextColor;
    this.readerCustomThemesRaw = settings.customThemesRaw || '';
    this.customThemeNameDraft = this.currentCustomThemeScheme().name;
    this.readerPageTurnMode = settings.pageTurnMode;
    this.readerPageTurnAnimationType = settings.pageTurnAnimationType;
    this.readerLandscapeDoublePage = settings.landscapeDoublePage;
    this.readerTapZoneActions = settings.tapZoneActions;
    this.readerVolumeTurnPage = settings.volumeTurnPage;
    this.readerKeepScreenOn = settings.keepScreenOn;
    this.readerExtendToStatusBar = settings.extendToStatusBar;
    this.readerPreloadEnabled = settings.preloadEnabled;
    this.readerPreloadChapterCount = settings.preloadChapterCount;
    this.readerFontFamily = settings.fontFamily || '';
    this.readerFontFilePath = settings.fontFilePath || '';
    AppStorage.setOrCreate<string>('readerFontSourceName', settings.fontSourceName || '系统默认');
    AppStorage.setOrCreate<string>('readerFontMode', settings.fontMode || (settings.fontFilePath ? 'custom' : 'system'));
    this.readerSystemFontFamily = settings.systemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext());
    AppStorage.setOrCreate<string>('readerSystemFontFamily', this.readerSystemFontFamily);
    AppStorage.setOrCreate<string>('readerCustomFontsRaw', settings.customFontsRaw || '');
    this.readerBodyFontMode = settings.bodyFontMode || 'global';
    this.readerBodyFontFamily = settings.bodyFontFamily || '';
    this.readerTitleFontMode = settings.titleFontMode || 'global';
    this.readerTitleFontFamily = settings.titleFontFamily || '';
    this.readerTitleFontSize = settings.titleFontSize || 22;
    this.readerRegexFontEnabled = settings.regexFontEnabled;
    this.readerRegexFontPattern = settings.regexFontPattern || '';
    this.readerRegexFontMode = settings.regexFontMode || 'global';
    this.readerRegexFontFamily = settings.regexFontFamily || '';
    this.readerRegexFontSize = settings.regexFontSize || 20;
    this.readerRegexShadowColor = settings.regexShadowColor || '';
    this.readerRegexFontRulesRaw = settings.regexFontRulesRaw || '';
    this.registerStyledCustomReaderFonts();
  }

  onReaderFontStyleChanged(): void {
    this.cachedRegexRulesKey = '';
    this.cachedRegexRules = [];
    this.readerPaginationCache.clear();
    this.pageTurnPreviewKey = '';
    this.registerStyledCustomReaderFonts();
    this.refreshReaderTextRender();
    this.paginateContent(this.content);
    this.preloadNextChapterPaginationLater();
  }

  replaceReaderCustomFontPath(oldPath: string, newPath: string, familyName: string): void {
    const raw = AppStorage.get<string>('readerCustomFontsRaw') || '';
    if (!raw.trim()) {
      return;
    }
    try {
      const parsed = JSON.parse(raw) as ReaderCustomFontData | ReaderCustomFontItem[];
      const source = Array.isArray(parsed) ? parsed as ReaderCustomFontItem[] : ((parsed as ReaderCustomFontData).fonts || []);
      const data = new ReaderCustomFontData();
      for (const item of source) {
        if (!item || !item.filePath) {
          continue;
        }
        const next = new ReaderCustomFontItem();
        next.filePath = item.filePath === oldPath ? newPath : item.filePath;
        next.familyName = item.filePath === oldPath ? familyName : (item.familyName || ReaderFontHelper.normalizeFontFamily(next.filePath));
        next.sourceName = item.sourceName || this.fileNameFromPath(next.filePath);
        data.fonts.push(next);
      }
      AppStorage.setOrCreate<string>('readerCustomFontsRaw', JSON.stringify(data));
    } catch (e) {
      console.warn('更新阅读字体列表失败:', e);
    }
  }

  fileNameFromPath(path: string): string {
    return ReaderFontHelper.fileNameFromPath(path);
  }

  applyReaderApplicationFont(familyName: string): void {
    try {
      getContext(this).getApplicationContext().setFont(familyName || '');
    } catch (e) {
      console.warn('应用阅读字体失败:', e);
    }
  }

  saveReaderFontSettings(): void {
    ReaderSettingsStore.saveFontSettings(
      getContext(this),
      this.readerFontFamily,
      this.readerFontFilePath,
      AppStorage.get<string>('readerFontSourceName') || '系统默认',
      AppStorage.get<string>('readerFontMode') || (this.readerFontFilePath ? 'custom' : 'system'),
      AppStorage.get<string>('readerSystemFontFamily') || this.getSystemReaderFontFamily(),
      AppStorage.get<string>('readerCustomFontsRaw') || ''
    ).catch((e: Error) => {
      console.warn('保存阅读字体设置失败:', e);
    });
  }

  getTocTitleColor(chapter: BookChapter, index: number): string {
    if (index === this.currentChapterIndex) {
      return this.accentColor();
    }
    if (chapter.cacheDate > 0) {
      return this.isReaderThemeDark() ? '#DDEFE5' : '#244B35';
    }
    return this.isReaderThemeDark() ? '#B8BDC7' : '#333333';
  }

  setReaderContent(text: string): void {
    this.content = text;
    this.paginateContent(text);
  }

  openTocPanel(): void {
    this.tocPanelTab = 0;
    this.tocQuickJumpArmed = false;
    this.tocQuickJumpInputVisible = false;
    this.tocQuickJumpDraft = '';
    this.cancelBookmarkMultiSelect();
    this.setTocWindowAround(this.currentChapterIndex, ScrollAlign.CENTER);
    this.showToc = true;
    this.showMenu = false;
    this.scrollTocToCurrentChapter(false);
    this.loadBookmarks();
  }

  async refreshTocFromPanel(): Promise<void> {
    await this.retryFetchChapters();
    this.setTocWindowAround(this.currentChapterIndex, ScrollAlign.CENTER);
    this.scrollTocToCurrentChapter(false);
    promptAction.showToast({ message: '目录已刷新' });
  }

  async loadBookmarks(): Promise<void> {
    const bookUrl = this.book?.bookUrl || this.bookUrl;
    if (!bookUrl) {
      this.bookmarks = [];
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.bookmarks = await db.getBookmarks(bookUrl);
    } catch (e) {
      console.warn('加载书签失败:', e);
      this.bookmarks = [];
    }
  }

  currentPageBookmark(): Bookmark | undefined {
    return this.bookmarks.find((bookmark: Bookmark) =>
      bookmark.chapterIndex === this.currentChapterIndex && bookmark.pageIndex === this.currentPageIndex);
  }

  isCurrentPageBookmarked(): boolean {
    return this.currentPageBookmark() !== undefined;
  }

  async toggleCurrentPageBookmark(): Promise<void> {
    const existing = this.currentPageBookmark();
    if (existing) {
      await this.deleteBookmark(existing);
      return;
    }
    await this.addCurrentBookmark();
  }

  bookmarkPullHintText(): string {
    if (this.isCurrentPageBookmarked()) {
      return this.bookmarkPullReady ? '松开删除书签' : '下拉删除书签';
    }
    return this.bookmarkPullReady ? '松开添加书签' : '下拉添加书签';
  }

  bookmarkPullHintColor(): string {
    return this.bookmarkPullReady ? this.accentColor() : this.getTextColor();
  }

  @Builder
  readerCurrentPageBookmarkMarker() {
    Stack({ alignContent: Alignment.Top }) {
      SymbolGlyph($r('sys.symbol.bookmark_fill'))
        .fontSize(32)
        .fontColor([this.accentColor()])
    }
    .width(46)
    .height(40)
    .position({ x: '100%', y: 0 })
    .translate({
      x: -62,
      y: this.readerBookmarkMarkerTopOffset() + this.bookmarkPullOffsetY
    })
    .hitTestBehavior(HitTestMode.None)
  }

  readerBookmarkMarkerTopOffset(): number {
    if (this.readerExtendToStatusBar) return 0;
    return this.hasBackgroundImage() || this.isStackPageTurnAnimation() ? this.statusBarSafeHeight : 0;
  }

  @Builder
  readerBookmarkPullHint() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.bookmark'))
        .fontSize(19)
        .fontColor([this.bookmarkPullHintColor()])
      Text(this.bookmarkPullHintText())
        .fontSize(14)
        .fontWeight(this.bookmarkPullReady ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.bookmarkPullHintColor())
    }
    .height(40)
    .padding({ left: 14, right: 14 })
    .borderRadius(20)
    .backgroundColor(this.readerGlassPanelColor())
    .border({ width: ThemeRuntime.glassBorderWidth(), color: this.readerGlassBorderColor() })
    .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
    .position({ x: '50%', y: 0 })
    .translate({ x: -90, y: this.getTopControlSafePadding() + 8 })
    .opacity(Math.min(1, this.bookmarkPullOffsetY / 36))
    .hitTestBehavior(HitTestMode.None)
  }

  async addCurrentBookmark(): Promise<void> {
    if (!this.book || this.chapters.length === 0) {
      promptAction.showToast({ message: '当前没有可添加的阅读位置' });
      return;
    }
    const pageIndex = Math.max(0, this.currentPageIndex);
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const existing = await db.getBookmarkAt(this.book.bookUrl, this.currentChapterIndex, pageIndex);
      if (existing) {
        promptAction.showToast({ message: '当前阅读位置已添加书签' });
        return;
      }
      const bookmark = new Bookmark();
      bookmark.bookUrl = this.book.bookUrl;
      bookmark.bookName = this.book.name;
      bookmark.bookAuthor = this.book.author;
      bookmark.chapterIndex = this.currentChapterIndex;
      bookmark.chapterName = this.getChapterTitle(this.currentChapterIndex);
      bookmark.pageIndex = pageIndex;
      bookmark.startPos = this.getPageStartOffset(pageIndex);
      bookmark.endPos = this.getPageEndOffset(pageIndex);
      bookmark.content = this.bookmarkContentPreview(pageIndex);
      bookmark.createTime = Date.now();
      bookmark.id = await db.insertBookmark(bookmark);
      await this.loadBookmarks();
      promptAction.showToast({ message: '书签已添加' });
    } catch (e) {
      console.error('添加书签失败:', e);
      promptAction.showToast({ message: '添加书签失败' });
    }
  }

  bookmarkContentPreview(pageIndex: number): string {
    const text = this.getPageText(pageIndex).replace(/\s+/g, ' ').trim();
    return text.length > 90 ? `${text.substring(0, 90)}…` : text;
  }

  async deleteBookmark(bookmark: Bookmark): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBookmark(bookmark.id);
      this.bookmarks = this.bookmarks.filter((item: Bookmark) => item.id !== bookmark.id);
      this.selectedBookmarkIds = this.selectedBookmarkIds.filter((id: number) => id !== bookmark.id);
      if (this.bookmarkMultiSelectMode && this.bookmarks.length === 0) {
        this.cancelBookmarkMultiSelect();
      }
      promptAction.showToast({ message: '书签已删除' });
    } catch (e) {
      console.error('删除书签失败:', e);
      promptAction.showToast({ message: '删除书签失败' });
    }
  }

  enterBookmarkMultiSelect(bookmarkId: number): void {
    this.bookmarkMultiSelectMode = true;
    if (!this.selectedBookmarkIds.includes(bookmarkId)) {
      this.selectedBookmarkIds = [...this.selectedBookmarkIds, bookmarkId];
    }
    setTimeout(() => {
      try {
        this.bookmarkScroller.closeAllSwipeActions();
      } catch (error) {
        console.warn('关闭书签滑动操作失败:', error);
      }
    }, 0);
  }

  isBookmarkSelected(bookmarkId: number): boolean {
    return this.selectedBookmarkIds.includes(bookmarkId);
  }

  toggleBookmarkSelection(bookmarkId: number): void {
    if (this.selectedBookmarkIds.includes(bookmarkId)) {
      this.selectedBookmarkIds = this.selectedBookmarkIds.filter((id: number) => id !== bookmarkId);
    } else {
      this.selectedBookmarkIds = [...this.selectedBookmarkIds, bookmarkId];
    }
  }

  toggleSelectAllBookmarks(): void {
    if (this.selectedBookmarkIds.length === this.bookmarks.length) {
      this.selectedBookmarkIds = [];
    } else {
      this.selectedBookmarkIds = this.bookmarks.map((bookmark: Bookmark) => bookmark.id);
    }
  }

  cancelBookmarkMultiSelect(): void {
    this.bookmarkMultiSelectMode = false;
    this.selectedBookmarkIds = [];
  }

  async deleteSelectedBookmarks(): Promise<void> {
    const ids = [...this.selectedBookmarkIds];
    if (ids.length === 0) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBookmarks(ids);
      this.bookmarks = this.bookmarks.filter((bookmark: Bookmark) => !ids.includes(bookmark.id));
      this.cancelBookmarkMultiSelect();
      promptAction.showToast({ message: `已删除 ${ids.length} 条书签` });
    } catch (e) {
      console.error('批量删除书签失败:', e);
      promptAction.showToast({ message: '批量删除书签失败' });
    }
  }

  async jumpToBookmark(bookmark: Bookmark): Promise<void> {
    const targetChapterIndex = this.clampChapterIndex(bookmark.chapterIndex);
    this.currentPageIndex = Math.max(0, bookmark.pageIndex);
    this.pendingRestorePageIndex = this.currentPageIndex;
    this.showToc = false;
    this.showMenu = false;
    await this.loadContent(false, targetChapterIndex);
    await this.saveReadingProgress();
  }

  formatBookmarkTime(timestamp: number): string {
    if (timestamp <= 0) return '';
    const date = new Date(timestamp);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${month}-${day} ${hour}:${minute}`;
  }

  openSettingsPanel(): void {
    this.showReaderActionMenu = false;
    this.settingsPanelTab = 0;
    this.showToc = false;
    this.showSettings = true;
    this.showMenu = false;
  }

  openTtsSettingsPanel(): void {
    this.showReaderActionMenu = false;
    this.settingsPanelTab = 1;
    this.showToc = false;
    this.showSettings = true;
    this.showMenu = false;
    this.loadTtsSettingsAndVoices();
  }

  closeSettingsPanelKeepMenu(): void {
    this.showSettings = false;
    this.showQuickTypographyValueInput = false;
    this.showMenu = true;
  }

  static defaultTtsVoice(): TtsVoiceOption {
    const option = new TtsVoiceOption();
    option.id = 0;
    option.name = '默认音色';
    option.online = 1;
    option.status = 'default';
    option.language = 'zh-CN';
    option.available = true;
    return option;
  }

  async loadTtsSettingsAndVoices(): Promise<void> {
    try {
      const settings = await TtsSettingsStore.load(getContext(this));
      this.applyLoadedTtsSettings(settings);
    } catch (e) {
      console.warn('读取朗读设置失败:', e);
    }
    this.normalizeDefaultTtsVoice();
    this.ttsSelectedVoiceKey = this.currentTtsVoiceKey();
    this.loadTtsVoices();
  }

  applyLoadedTtsSettings(settings: TtsSettings): void {
    this.ttsPerson = settings.person;
    this.ttsOnline = settings.online;
    this.ttsStyle = settings.style;
    this.ttsLanguage = settings.language;
    this.ttsSpeed = settings.speed;
    this.ttsInstalledVoiceKeys = settings.installedVoiceKeys;
    this.ttsCustomVoiceId = settings.customVoiceId;
    this.ttsCustomVoices = settings.customVoices;
    this.ttsCustomVoiceOptions = SystemTtsReader.parseCustomVoices(settings.customVoices);
  }

  onTtsCustomVoicesChanged(): void {
    this.ttsCustomVoiceOptions = SystemTtsReader.parseCustomVoices(this.ttsCustomVoices);
    this.ttsSelectedVoiceKey = this.currentTtsVoiceKey();
  }

  normalizeDefaultTtsVoice(): void {
    if (this.ttsOnline === 0 && this.ttsPerson === 0 && !this.ttsStyle &&
      this.sameTtsLanguage(this.ttsLanguage || 'zh-CN', 'zh-CN')) {
      this.ttsOnline = 1;
      this.saveTtsSettings();
    }
  }

  currentTtsSettings(): TtsSettings {
    const settings = new TtsSettings();
    settings.person = this.ttsPerson;
    settings.online = this.ttsOnline;
    settings.style = this.ttsStyle;
    settings.language = this.ttsLanguage;
    settings.speed = this.ttsSpeed;
    settings.installedVoiceKeys = this.ttsInstalledVoiceKeys;
    settings.customVoiceId = this.ttsCustomVoiceId;
    settings.customVoices = this.ttsCustomVoices;
    return settings;
  }

  saveTtsSettings(): void {
    const settings = this.currentTtsSettings();
    TtsSettingsStore.applyToStorage(settings);
    TtsSettingsStore.save(getContext(this), settings).catch((e: Error) => {
      console.warn('保存朗读设置失败:', e);
    });
  }

  async loadTtsVoices(): Promise<void> {
    if (this.ttsVoicesLoading) {
      return;
    }
    this.ttsVoicesLoading = true;
    try {
      const voices = await SystemTtsReader.listAvailableVoices();
      this.ttsVoices = this.applyInstalledTtsVoiceOverrides(this.mergeWithDefaultTtsVoice(voices));
      const currentCustomVoice = this.findCurrentCustomTtsVoice();
      if (currentCustomVoice) {
        this.ttsSelectedVoiceKey = this.ttsCustomVoiceKey(currentCustomVoice);
        return;
      }
      const currentVoice = this.findCurrentTtsVoice();
      if (currentVoice && currentVoice.available) {
        this.ttsSelectedVoiceKey = this.ttsVoiceKey(currentVoice);
      } else {
        this.applyTtsVoice(this.firstAvailableTtsVoice(), false);
      }
    } catch (e) {
      this.ttsVoices = [ReadBookPage.defaultTtsVoice()];
      this.ttsPerson = 0;
      this.ttsOnline = 1;
      this.ttsStyle = '';
      this.ttsLanguage = 'zh-CN';
      this.ttsCustomVoiceId = '';
      this.saveTtsSettings();
      this.ttsSelectedVoiceKey = this.currentTtsVoiceKey();
      console.warn('加载朗读音色失败:', e);
    } finally {
      this.ttsVoicesLoading = false;
    }
  }

  mergeWithDefaultTtsVoice(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [ReadBookPage.defaultTtsVoice()];
    for (const voice of voices) {
      const existingIndex = options.findIndex((item: TtsVoiceOption) =>
        this.isSameTtsVoiceOption(item, voice) || this.isSameTtsDisplayVoice(item, voice));
      if (existingIndex < 0) {
        options.push(voice);
      } else if (this.shouldPreferTtsVoiceOption(voice, options[existingIndex])) {
        options[existingIndex] = voice;
      }
    }
    return options;
  }

  firstAvailableTtsVoice(): TtsVoiceOption {
    return this.ttsVoices.find((voice: TtsVoiceOption) => voice.available) || this.ttsVoices[0] ||
      ReadBookPage.defaultTtsVoice();
  }

  applyInstalledTtsVoiceOverrides(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [];
    for (const voice of voices) {
      options.push(this.isLocallyInstalledTtsVoice(voice) ? this.markTtsVoiceOptionInstalled(voice) : voice);
    }
    return options;
  }

  markTtsVoiceOptionInstalled(voice: TtsVoiceOption): TtsVoiceOption {
    const option = new TtsVoiceOption();
    option.id = voice.id;
    option.name = voice.name;
    option.online = voice.online;
    option.status = 'INSTALLED';
    option.systemStatus = 'INSTALLED';
    option.style = voice.style;
    option.language = voice.language;
    option.downloadLanguage = voice.downloadLanguage;
    option.gender = voice.gender;
    option.available = true;
    option.downloadable = false;
    return option;
  }

  isLocallyInstalledTtsVoice(voice: TtsVoiceOption): boolean {
    const key = this.installedTtsVoiceKey(voice);
    return !!key && this.ttsInstalledVoiceKeys.split('\n').includes(key);
  }

  installedTtsVoiceKey(voice: TtsVoiceOption): string {
    const style = this.isKnownTtsVoiceId(voice.id) ? '' : (voice.style || '');
    return `${voice.id}_${voice.online}_${this.normalizeTtsLanguage(voice.language || 'zh-CN')}_${style}`;
  }

  isSameTtsVoiceOption(left: TtsVoiceOption, right: TtsVoiceOption): boolean {
    if (left.id !== right.id || left.online !== right.online ||
      !this.sameTtsLanguage(left.language || 'zh-CN', right.language || 'zh-CN')) {
      return false;
    }
    if (this.isKnownTtsVoiceId(left.id)) {
      return true;
    }
    return (left.style || '') === (right.style || '');
  }

  isSameTtsDisplayVoice(left: TtsVoiceOption, right: TtsVoiceOption): boolean {
    if (this.ttsVoiceTitle(left) === this.ttsVoiceTitle(right)) {
      return true;
    }
    return (left.name || '') === (right.name || '') && left.online === right.online &&
      this.sameTtsLanguage(left.language || 'zh-CN', right.language || 'zh-CN');
  }

  shouldPreferTtsVoiceOption(candidate: TtsVoiceOption, current: TtsVoiceOption): boolean {
    if (candidate.available !== current.available) {
      return candidate.available;
    }
    if (this.isKnownTtsVoiceId(candidate.id) !== this.isKnownTtsVoiceId(current.id)) {
      return this.isKnownTtsVoiceId(candidate.id);
    }
    if (candidate.downloadable !== current.downloadable) {
      return candidate.downloadable;
    }
    return !current.style && !!candidate.style;
  }

  isKnownTtsVoiceId(id: number): boolean {
    return id === 0 || id === 8 || id === 13 || id === 21;
  }

  applyTtsVoice(voice: TtsVoiceOption, restartSpeaking: boolean): void {
    if (!voice.available) {
      promptAction.showToast({ message: voice.downloadable ? '请到朗读设置下载该音色' : '该系统音色当前不可用' });
      return;
    }
    const shouldResume = restartSpeaking && (this.isTtsSpeaking || this.ttsReader.isSpeaking());
    if (shouldResume) {
      this.stopTtsReading();
    }
    this.ttsPerson = voice.id;
    this.ttsOnline = voice.online;
    this.ttsStyle = voice.style;
    this.ttsLanguage = voice.language;
    this.ttsCustomVoiceId = '';
    this.ttsSelectedVoiceKey = this.ttsVoiceKey(voice);
    this.saveTtsSettings();
    if (shouldResume) {
      this.startTtsReadingFromCurrentPosition(false).catch((e: Error) => {
        console.warn('切换朗读音色后恢复朗读失败:', e);
      });
    }
  }

  applyTtsSpeed(value: number): void {
    const nextSpeed = Math.max(0.5, Math.min(2, Math.round(value * 10) / 10));
    if (Math.abs(this.ttsSpeed - nextSpeed) < 0.01) {
      return;
    }
    this.ttsSpeed = nextSpeed;
    this.scheduleTtsSpeedSettingsSave();
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      this.scheduleTtsSpeedAvSessionUpdate();
    }
  }

  scheduleTtsSpeedSettingsSave(): void {
    if (this.ttsSpeedSaveTimerId >= 0) {
      clearTimeout(this.ttsSpeedSaveTimerId);
    }
    this.ttsSpeedSaveTimerId = setTimeout(() => {
      this.ttsSpeedSaveTimerId = -1;
      this.saveTtsSettings();
    }, 300);
  }

  scheduleTtsSpeedAvSessionUpdate(): void {
    if (this.ttsSpeedAvSessionTimerId >= 0) {
      clearTimeout(this.ttsSpeedAvSessionTimerId);
    }
    this.ttsSpeedAvSessionTimerId = setTimeout(() => {
      this.ttsSpeedAvSessionTimerId = -1;
      if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
        this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY).catch((e: Error) => {
          console.warn('更新朗读倍速媒体状态失败:', e);
        });
      }
    }, 300);
  }

  flushPendingTtsSpeedSettings(): void {
    if (this.ttsSpeedSaveTimerId >= 0) {
      clearTimeout(this.ttsSpeedSaveTimerId);
      this.ttsSpeedSaveTimerId = -1;
      this.saveTtsSettings();
    }
    if (this.ttsSpeedAvSessionTimerId >= 0) {
      clearTimeout(this.ttsSpeedAvSessionTimerId);
      this.ttsSpeedAvSessionTimerId = -1;
    }
  }

  currentTtsVoiceKey(): string {
    const customVoice = this.findCurrentCustomTtsVoice();
    if (customVoice) {
      return this.ttsCustomVoiceKey(customVoice);
    }
    const matched = this.findCurrentTtsVoice();
    return matched ? this.ttsVoiceKey(matched) :
      `${this.ttsPerson}_${this.ttsOnline}_${this.ttsLanguage || 'zh-CN'}_${this.ttsStyle || ''}_`;
  }

  findCurrentTtsVoice(): TtsVoiceOption | undefined {
    return this.ttsVoices.find((voice: TtsVoiceOption) => this.isCurrentTtsVoice(voice));
  }

  isCurrentTtsVoice(voice: TtsVoiceOption): boolean {
    if (this.ttsCustomVoiceId) {
      return false;
    }
    return voice.id === this.ttsPerson && voice.online === this.ttsOnline &&
      (voice.style || '') === (this.ttsStyle || '') &&
      this.sameTtsLanguage(voice.language || 'zh-CN', this.ttsLanguage || 'zh-CN');
  }

  applyCustomTtsVoice(voice: HttpTTS, restartSpeaking: boolean): void {
    if (voice.enabled === false) {
      promptAction.showToast({ message: '该自定义音色已禁用' });
      return;
    }
    const shouldResume = restartSpeaking && (this.isTtsSpeaking || this.ttsReader.isSpeaking());
    if (shouldResume) {
      this.stopTtsReading();
    }
    this.ttsCustomVoiceId = String(voice.id);
    this.ttsSelectedVoiceKey = this.ttsCustomVoiceKey(voice);
    this.saveTtsSettings();
    if (shouldResume) {
      this.startTtsReadingFromCurrentPosition(false).catch((e: Error) => {
        console.warn('切换自定义朗读音色后恢复朗读失败:', e);
      });
    }
  }

  findCurrentCustomTtsVoice(): HttpTTS | undefined {
    const selectedId = (this.ttsCustomVoiceId || '').trim();
    if (!selectedId) {
      return undefined;
    }
    return this.ttsCustomVoiceOptions.find((voice: HttpTTS) => String(voice.id) === selectedId);
  }

  ttsCustomVoiceKey(voice: HttpTTS): string {
    return `custom_${voice.id}_${voice.name || ''}`;
  }

  isCurrentCustomTtsVoice(voice: HttpTTS): boolean {
    return (this.ttsCustomVoiceId || '') === String(voice.id);
  }

  ttsCustomVoiceTitle(voice: HttpTTS): string {
    const state = voice.enabled === false ? ' · 已禁用' : '';
    return `${voice.name || '未命名音色'} · 自定义${state}`;
  }

  ttsVoiceKey(voice: TtsVoiceOption): string {
    return `${voice.id}_${voice.online}_${voice.language || 'zh-CN'}_${voice.style || ''}_${voice.name || ''}`;
  }

  ttsVoiceTitle(voice: TtsVoiceOption): string {
    if (voice.status === 'default') {
      return `${voice.name} · 系统默认`;
    }
    const suffix = voice.online === 0 ? '在线' : '离线';
    const gender = this.ttsVoiceGenderText(voice);
    const state = voice.available ? '' : (voice.downloadable ? ' · 需下载' : ' · 不可用');
    return `${voice.name} · ${suffix}${gender}${state}`;
  }

  ttsVoiceGenderText(voice: TtsVoiceOption): string {
    const value = (voice.gender || '').toLowerCase();
    if (value === 'male' || value === '男' || value === '男声') {
      return ' · 男声';
    }
    if (value === 'female' || value === '女' || value === '女声') {
      return ' · 女声';
    }
    return '';
  }

  sameTtsLanguage(left: string, right: string): boolean {
    return this.normalizeTtsLanguage(left) === this.normalizeTtsLanguage(right);
  }

  normalizeTtsLanguage(language: string): string {
    const value = (language || 'zh-CN').trim().replace(/_/g, '-').toLowerCase();
    if (value === 'zh' || value === 'zh-cn' || value.startsWith('zh-hans')) {
      return 'zh-CN';
    }
    if (value === 'en' || value === 'en-us') {
      return 'en-US';
    }
    return value || 'zh-CN';
  }

  tocGlobalIndex(localIndex: number): number {
    return this.tocWindowStart + localIndex;
  }

  setTocWindowAround(index: number, align: ScrollAlign): number {
    this.tocLoadingPreviousPage = false;
    this.tocLoadingNextPage = false;
    if (this.chapters.length === 0) {
      this.tocWindowStart = 0;
      this.tocVisibleChapters = [];
      return 0;
    }
    const target = Math.max(0, Math.min(index, this.chapters.length - 1));
    let start = target - Math.floor(TOC_WINDOW_PAGE_SIZE / 2);
    if (align === ScrollAlign.START) {
      start = target;
    } else if (align === ScrollAlign.END) {
      start = target - TOC_WINDOW_PAGE_SIZE + 1;
    }
    start = Math.max(0, Math.min(start, Math.max(0, this.chapters.length - TOC_WINDOW_PAGE_SIZE)));
    const end = Math.min(this.chapters.length, start + TOC_WINDOW_PAGE_SIZE);
    this.tocWindowStart = start;
    this.tocVisibleChapters = this.chapters.slice(start, end);
    return target - start;
  }

  loadNextTocPage(): void {
    if (this.tocLoadingNextPage) {
      return;
    }
    const loadedEnd = this.tocWindowStart + this.tocVisibleChapters.length;
    if (loadedEnd >= this.chapters.length) {
      return;
    }
    this.tocLoadingNextPage = true;
    const nextEnd = Math.min(this.chapters.length, loadedEnd + TOC_WINDOW_PAGE_SIZE);
    this.tocVisibleChapters = this.tocVisibleChapters.concat(this.chapters.slice(loadedEnd, nextEnd));
    setTimeout(() => {
      this.tocLoadingNextPage = false;
    }, 0);
  }

  loadPreviousTocPage(): void {
    if (this.tocLoadingPreviousPage || this.tocWindowStart <= 0) {
      return;
    }
    this.tocLoadingPreviousPage = true;
    const oldStart = this.tocWindowStart;
    const nextStart = Math.max(0, oldStart - TOC_WINDOW_PAGE_SIZE);
    const added = oldStart - nextStart;
    this.tocWindowStart = nextStart;
    this.tocVisibleChapters = this.chapters.slice(nextStart, oldStart).concat(this.tocVisibleChapters);
    setTimeout(() => {
      try {
        this.tocScroller.scrollToIndex(added, false, ScrollAlign.START);
      } catch (e) {
        console.warn('向前加载目录失败:', e);
      } finally {
        this.tocLoadingPreviousPage = false;
      }
    }, 0);
  }

  scrollTocToCurrentChapter(smooth: boolean = true): void {
    if (this.chapters.length === 0) {
      return;
    }
    const index = Math.max(0, Math.min(this.currentChapterIndex, this.chapters.length - 1));
    this.scrollTocToChapter(index, ScrollAlign.CENTER, smooth);
  }

  scrollTocToChapter(index: number, align: ScrollAlign, smooth: boolean = true): void {
    if (this.chapters.length === 0) {
      return;
    }
    const targetIndex = Math.max(0, Math.min(index, this.chapters.length - 1));
    const localIndex = this.setTocWindowAround(targetIndex, align);
    setTimeout(() => {
      try {
        this.tocScroller.scrollToIndex(localIndex, smooth, align);
      } catch (e) {
        console.warn('定位目录章节失败:', e);
      }
    }, 50);
  }

  getSubTextColor(): string {
    return this.currentReaderTheme().subTextColor;
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  tocSelectedBackgroundColor(): string {
    const color = this.accentColor();
    if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
      return `#11${color.substring(1)}`;
    }
    return this.appDarkMode ? '#112A6FCC' : '#11007DFF';
  }

  readerGlassPanelColor(): string {
    return ThemeRuntime.glassPanelColor(this.isReaderThemeDark(), this.getBackgroundColor());
  }

  readerGlassBorderColor(): string {
    return ThemeRuntime.glassBorderColor(this.isReaderThemeDark());
  }

  readerGlassShadowColor(): string {
    return ThemeRuntime.glassShadowColor(this.isReaderThemeDark());
  }

  readerSolidPanelColor(): string {
    return this.isReaderThemeDark() ? '#191B1F' : '#FFFFFF';
  }

  getReaderSafeAreaEdges(): SafeAreaEdge[] {
    return this.readerExtendToStatusBar || this.hasBackgroundImage() || this.isStackPageTurnAnimation() ?
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM] : [SafeAreaEdge.BOTTOM];
  }

  getReaderTopSafePadding(): number {
    return this.readerExtendToStatusBar || this.isStackPageTurnAnimation() ? 0 : this.statusBarSafeHeight;
  }

  getReaderPageContentTopPadding(): number {
    return !this.readerExtendToStatusBar && this.isStackPageTurnAnimation() ? this.statusBarSafeHeight : 0;
  }

  getTopControlSafePadding(): number {
    return Math.max(this.statusBarSafeHeight, 32);
  }

  getTopOverlayHeight(): number {
    return 56 + this.getTopControlSafePadding();
  }

  getReaderContentBottomReserve(): number {
    return 0;
  }

  getReaderBottomInfoBarHeight(): number {
    return 24;
  }

  readerFloatingBarBottomMargin(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 8;
  }

  readerFloatingBarWidth(): number {
    const viewportWidth = this.pageViewWidth > 0 ? this.pageViewWidth : 360;
    return Math.max(240, viewportWidth * 0.88);
  }

  readerChapterTrackColor(): string {
    return this.isReaderThemeDark() ? '#2EFFFFFF' : '#1F000000';
  }

  readerFloatingBarSideInset(): number {
    const viewportWidth = this.pageViewWidth > 0 ? this.pageViewWidth : 360;
    return Math.max(0, (viewportWidth - this.readerFloatingBarWidth()) / 2);
  }

  readerBottomMenuOverlayHeight(): number {
    return 120 + this.readerFloatingBarBottomMargin();
  }

  readerBottomActionOverlayHeight(): number {
    return 56 + this.readerFloatingBarBottomMargin();
  }

  getReaderContentBottomPadding(): number {
    return Math.max(0, this.readerMarginBottom + this.getReaderContentBottomReserve());
  }

  getEffectiveReaderLineHeight(): number {
    return this.readerFontSize + Math.max(0, this.readerLineHeight);
  }

  onReadLayoutChanged(): void {
    this.paginateContent(this.content);
    this.preloadNextChapterPaginationLater();
    this.saveReadingProgress();
  }

  refreshReaderTextRender(): void {
    this.pageRenderVersion++;
    this.pageTurnIncomingRenderVersion++;
  }

  forceCurrentReaderPageRender(): void {
    this.chapterJumpRenderGeneration++;
    this.pageRenderVersion++;
    this.pageTurnIncomingRenderVersion++;
  }

  onReaderFontChanged(): void {
    const serial = ++this.readerFontChangeSerial;
    if (!this.readerFontFilePath) {
      this.clearReaderFontState();
      this.refreshReaderTextRender();
      this.onReadLayoutChanged();
      return;
    }
    this.registerReaderFont().then((registered: boolean) => {
      if (serial !== this.readerFontChangeSerial) {
        return;
      }
      if (registered || !this.readerFontFilePath) {
        this.refreshReaderTextRender();
      }
      this.onReadLayoutChanged();
    });
  }

  onReaderActiveFontChanged(): void {
    if (!this.readerFontFilePath && !this.readerActiveFontFamily && !this.readerStoredFontRegistered) {
      this.clearReaderFontState();
      this.refreshReaderTextRender();
      this.onReadLayoutChanged();
    }
  }

  onReaderExtendToStatusBarChanged(): void {
    this.enterReaderImmersive();
    this.paginateContent(this.content);
    this.saveReadingProgress();
  }

  onReaderThemeChanged(): void {
    this.enterReaderImmersive();
    this.refreshReaderTextRender();
    this.paginateContent(this.content);
    this.saveReadingProgress();
    this.onTtsCoverSettingsChanged();
  }

  onTtsCoverSettingsChanged(): void {
    if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking() && !this.ttsAvSession) {
      this.refreshTtsMediaImage().catch((e: Error) => {
        console.warn('刷新朗读媒体封面失败:', e);
      });
      return;
    }
    this.refreshTtsMediaImage().then(() => {
      return this.updateTtsAvSessionPlaybackState(
        this.isTtsSpeaking || this.ttsReader.isSpeaking() ?
          avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_STOP
      );
    }).catch((e: Error) => {
      console.warn('同步朗读媒体封面失败:', e);
    });
  }

  onReaderVolumeTurnPageChanged(): void {
    this.updateVolumeKeySubscription();
    this.saveReadConfig();
  }

  onReaderPageTurnAnimationChanged(): void {
    this.resetSlidePageEffect();
    this.saveReadConfig();
  }

  onReaderPreloadChanged(): void {
    this.preloadReaderContentLater();
    this.saveReadConfig();
  }

  updateVolumeKeySubscription(): void {
    this.unregisterVolumeKeyTurn();
    if (!this.readerVolumeTurnPage) {
      return;
    }
    this.registerVolumeKeyTurn();
  }

  registerVolumeKeyTurn(): void {
    this.volumeUpCallback = (_event: KeyEvent) => {
      this.handleVolumeKeyTurn(-1);
    };
    this.volumeDownCallback = (_event: KeyEvent) => {
      this.handleVolumeKeyTurn(1);
    };
    try {
      inputConsumer.on('keyPressed', {
        key: KeyCode.KEYCODE_VOLUME_UP,
        action: Action.DOWN,
        isRepeat: false
      }, this.volumeUpCallback);
      inputConsumer.on('keyPressed', {
        key: KeyCode.KEYCODE_VOLUME_DOWN,
        action: Action.DOWN,
        isRepeat: false
      }, this.volumeDownCallback);
    } catch (err) {
      console.error('注册音量键翻页失败:', err);
      this.volumeUpCallback = undefined;
      this.volumeDownCallback = undefined;
    }
  }

  unregisterVolumeKeyTurn(): void {
    try {
      if (this.volumeUpCallback) {
        inputConsumer.off('keyPressed', this.volumeUpCallback);
      }
      if (this.volumeDownCallback) {
        inputConsumer.off('keyPressed', this.volumeDownCallback);
      }
    } catch (err) {
      console.error('取消音量键翻页失败:', err);
    }
    this.volumeUpCallback = undefined;
    this.volumeDownCallback = undefined;
  }

  handleVolumeKeyTurn(direction: number): void {
    if (!this.readerVolumeTurnPage || this.showMenu || this.showToc || this.showSettings || this.isLoading || this.chapters.length === 0) {
      return;
    }
    if (direction > 0) {
      this.turnNext();
    } else {
      this.turnPrev();
    }
  }

  clampChapterIndex(index: number): number {
    if (this.chapters.length === 0) return 0;
    return Math.max(0, Math.min(index, this.chapters.length - 1));
  }

  getMenuChapterDisplayIndex(): number {
    return this.menuChapterSliderActive ? this.menuChapterPreviewIndex : this.currentChapterIndex;
  }

  handleMenuChapterSliderChange(value: number, mode: SliderChangeMode): void {
    this.menuChapterPreviewIndex = this.clampChapterIndex(Math.round(value));
    this.menuChapterSliderActive = true;
    this.menuChapterTooltipVisible = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.menuChapterTooltipVisible = false;
      this.confirmMenuChapterJump(this.menuChapterPreviewIndex);
    }
  }

  async confirmMenuChapterJump(targetIndex: number): Promise<void> {
    if (this.menuChapterConfirming) {
      return;
    }
    const normalizedIndex = this.clampChapterIndex(targetIndex);
    if (normalizedIndex === this.currentChapterIndex) {
      this.resetMenuChapterPreview();
      return;
    }
    this.menuChapterConfirming = true;
    try {
      const result = await promptAction.showDialog({
        title: '确认跳转章节',
        message: `是否跳转到「${this.getChapterTitle(normalizedIndex)}」？`,
        buttons: [
          { text: '取消', color: this.getSubTextColor() },
          { text: '跳转', color: this.accentColor() }
        ]
      });
      if (result.index === 1) {
        await this.jumpToMenuChapter(normalizedIndex);
      } else {
        this.resetMenuChapterPreview();
      }
    } catch (error) {
      console.error('确认跳转章节失败:', error);
      this.resetMenuChapterPreview();
    } finally {
      this.menuChapterConfirming = false;
    }
  }

  resetMenuChapterPreview(): void {
    this.menuChapterPreviewIndex = this.currentChapterIndex;
    this.menuChapterSliderActive = false;
    this.menuChapterTooltipVisible = false;
  }

  async jumpToMenuChapter(targetIndex: number): Promise<void> {
    const normalizedIndex = this.clampChapterIndex(targetIndex);
    if (normalizedIndex === this.currentChapterIndex) {
      this.menuChapterPreviewIndex = this.currentChapterIndex;
      this.menuChapterSliderActive = false;
      this.menuChapterTooltipVisible = false;
      return;
    }
    this.currentPageIndex = 0;
    this.pendingRestorePageIndex = 0;
    try {
      await this.loadContent(false, normalizedIndex);
      await this.saveReadingProgress();
    } finally {
      this.menuChapterPreviewIndex = this.currentChapterIndex;
      this.menuChapterSliderActive = false;
      this.menuChapterTooltipVisible = false;
    }
  }

  async jumpToAdjacentChapterFromMenu(direction: number): Promise<void> {
    await this.jumpToAdjacentChapterFirstPage(direction);
    this.menuChapterPreviewIndex = this.currentChapterIndex;
    this.menuChapterSliderActive = false;
    this.menuChapterTooltipVisible = false;
  }

  restorePendingPageIndex(): void {
    if (this.pendingRestorePageIndex < 0) {
      return;
    }
    const maxPage = Math.max(0, this.contentPages.length - 1);
    this.currentPageIndex = this.normalizeReaderSpreadPageIndex(
      Math.max(0, Math.min(this.pendingRestorePageIndex, maxPage))
    );
    this.pendingRestorePageIndex = -1;
  }

  canSaveReadingProgress(): boolean {
    if (this.isLoading || this.isPagedReaderAwaitingPagination()) {
      return false;
    }
    return this.pageViewWidth > 0 && this.pageViewHeight > 0 && this.contentPages.length > 0;
  }

  @Builder
  changeSourceDialog() {
    Column() {
      Column() {
        Row() {
          Text('选择新书源')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getTextColor())
            .layoutWeight(1)

          if (this.isChangingSource) {
            LoadingProgress()
              .width(24)
              .height(24)
              .margin({ right: 8 })
          } else {
            ImmersiveBackButton({
              icon: $r('sys.symbol.arrow_clockwise'),
              iconColor: this.getTextColor(),
              darkMode: this.isReaderThemeDark(),
              buttonSize: 34,
              containerWidth: 44,
              containerHeight: 44,
              startInset: 0,
              materialScale: 0.72,
              accessibilityLabel: '刷新书源',
              onBack: () => {
                this.refreshChangeSourceResults();
              }
            })
              .margin({ right: 2 })
          }

          Text('×')
            .fontSize(24)
            .fontColor(this.getSubTextColor())
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.closeChangeSourceDialog();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.changeSourceStatus || '将使用当前书名进行全词匹配搜索')
          .fontSize(13)
          .fontColor(this.getSubTextColor())
          .width('100%')
          .margin({ top: 6, bottom: 10 })

        if (this.isChangingSource && this.changeSourceResults.length === 0) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
            Text('正在搜索可用书源...')
              .fontSize(13)
              .fontColor(this.getSubTextColor())
              .margin({ top: 8 })
          }
          .width('100%')
          .height(220)
          .justifyContent(FlexAlign.Center)
        } else if (this.changeSourceResults.length === 0) {
          Column() {
            Text('暂无可切换书源')
              .fontSize(15)
              .fontColor(this.getSubTextColor())
          }
          .width('100%')
          .height(220)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.changeSourceResults, (book: SearchBook) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(book.originName || book.origin)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.getTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(`${book.author || '作者未知'} ${book.latestChapterTitle || ''}`)
                      .fontSize(12)
                      .fontColor(this.getSubTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 4 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Button('切换')
                    .width(64)
                    .height(32)
                    .fontSize(13)
                    .borderRadius(16)
                    .backgroundColor(this.buttonColor())
                    .fontColor('#FFFFFF')
                    .enabled(!this.isSwitchingSource)
                    .onClick(() => {
                      this.switchToSearchBook(book);
                    })
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.readerSolidPanelColor())
                .borderRadius(8)
                .onClick(() => {
                  this.switchToSearchBook(book);
                })
              }
            }, (book: SearchBook) => `${book.origin}|${book.bookUrl}`)

            if (this.isChangingSource) {
              ListItem() {
                Row() {
                  LoadingProgress()
                    .width(20)
                    .height(20)
                  Text('继续搜索中...')
                    .fontSize(13)
                    .fontColor(this.getSubTextColor())
                    .margin({ left: 8 })
                }
                .width('100%')
                .height(42)
                .justifyContent(FlexAlign.Center)
              }
            }
          }
          .width('100%')
          .height(320)
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(ThemeRuntime.glassCornerRadius(12, 'panel'))
      .clip(true)
      .backgroundColor(this.readerGlassPanelColor())
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
  }

  async openChangeSourceDialog(): Promise<void> {
    if (!this.book || !this.book.name) {
      promptAction.showToast({ message: '当前书籍信息不完整' });
      return;
    }
    this.cancelActiveChangeSourceSearch();
    const sessionId = ++this.changeSourceSessionId;
    this.showChangeSourceDialog = true;
    this.showMenu = false;
    this.showToc = false;
    this.showSettings = false;
    this.changeSourceResults = [];
    this.changeSourceStatus = '正在读取历史换源结果...';
    this.isChangingSource = true;
    this.isSwitchingSource = false;
    try {
      const cachedResults = await ChangeSourceResultCache.load(getContext(this), this.book.name);
      if (!this.isChangeSourceSessionActive(sessionId) || !this.book) {
        return;
      }
      this.changeSourceResults = this.filterChangeSourceResults(
        cachedResults, this.book.bookUrl, this.book.origin
      );
      if (this.changeSourceResults.length > 0) {
        this.isChangingSource = false;
        this.changeSourceStatus = `已显示历史结果，共 ${this.changeSourceResults.length} 个；点击刷新可重新搜索`;
        return;
      }
    } catch (e) {
      console.warn('读取换源历史结果失败:', e);
    }
    if (this.isChangeSourceSessionActive(sessionId)) {
      this.searchChangeSource(sessionId);
    }
  }

  refreshChangeSourceResults(): void {
    if (!this.book || this.isSwitchingSource) {
      return;
    }
    this.cancelActiveChangeSourceSearch();
    const sessionId = ++this.changeSourceSessionId;
    this.changeSourceStatus = '正在刷新可用书源...';
    this.isChangingSource = true;
    this.searchChangeSource(sessionId);
  }

  closeChangeSourceDialog(): void {
    this.changeSourceSessionId++;
    this.cancelActiveChangeSourceSearch();
    this.showChangeSourceDialog = false;
    this.changeSourceResults = [];
    this.changeSourceStatus = '';
    this.isChangingSource = false;
    this.isSwitchingSource = false;
  }

  async searchChangeSource(sessionId: number): Promise<void> {
    if (!this.book) {
      return;
    }
    const cacheBookName = this.book.name;
    this.isChangingSource = true;
    this.changeSourceStatus = '正在搜索可用书源...';
    const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
    this.activeChangeSourceCoordinator = coordinator;
    try {
      const currentBookUrl = this.book.bookUrl;
      const currentOrigin = this.book.origin;
      const results = await coordinator.search(this.book.name, (progress: SearchProgress) => {
        if (!this.isChangeSourceSessionActive(sessionId)) {
          return;
        }
        if (progress.finished) {
          this.changeSourceResults = this.filterChangeSourceResults(progress.results, currentBookUrl, currentOrigin);
        } else if (progress.deltaResults && progress.deltaResults.length > 0) {
          this.changeSourceResults = this.filterChangeSourceResults(
            this.changeSourceResults.concat(progress.deltaResults),
            currentBookUrl,
            currentOrigin
          );
        }
        this.changeSourceStatus = progress.status;
        if (progress.finished) {
          this.isChangingSource = false;
        }
      }, { exactMatch: true });
      if (!this.isChangeSourceSessionActive(sessionId)) {
        return;
      }
      this.changeSourceResults = this.filterChangeSourceResults(results, currentBookUrl, currentOrigin);
      this.changeSourceStatus = this.changeSourceResults.length > 0 ?
        `搜索完成，找到 ${this.changeSourceResults.length} 个可切换书源` : '搜索完成，未找到可切换书源';
      try {
        // 缓存完整搜索结果；展示时再排除当前书源，确保切换后仍可换回原书源。
        await ChangeSourceResultCache.save(getContext(this), cacheBookName, results);
      } catch (e) {
        console.warn('保存换源结果缓存失败:', e);
      }
    } catch (e) {
      if (!this.isChangeSourceSessionActive(sessionId)) {
        return;
      }
      console.error('搜索换源失败:', e);
      this.changeSourceStatus = '搜索换源失败';
    } finally {
      if (this.activeChangeSourceCoordinator === coordinator) {
        this.activeChangeSourceCoordinator = null;
      }
      if (this.isChangeSourceSessionActive(sessionId)) {
        this.isChangingSource = false;
      }
    }
  }

  isChangeSourceSessionActive(sessionId: number): boolean {
    return this.showChangeSourceDialog && sessionId === this.changeSourceSessionId;
  }

  cancelActiveChangeSourceSearch(): void {
    if (this.activeChangeSourceCoordinator) {
      this.activeChangeSourceCoordinator.cancel();
      this.activeChangeSourceCoordinator = null;
    }
  }

  filterChangeSourceResults(results: SearchBook[], currentBookUrl: string, currentOrigin: string): SearchBook[] {
    const filtered: SearchBook[] = [];
    for (const result of results) {
      if (!result.bookUrl || (result.bookUrl === currentBookUrl && result.origin === currentOrigin)) {
        continue;
      }
      if (!filtered.some((item: SearchBook) => item.bookUrl === result.bookUrl && item.origin === result.origin)) {
        filtered.push(result);
      }
    }
    return filtered;
  }

  async switchToSearchBook(searchBook: SearchBook): Promise<void> {
    if (!this.book || this.isSwitchingSource) {
      return;
    }
    this.cancelActiveChangeSourceSearch();
    this.isChangingSource = false;
    const sessionId = ++this.changeSourceSessionId;
    this.isSwitchingSource = true;
    this.changeSourceStatus = '正在切换书源...';
    await this.saveReadingProgress();
    const oldBook = this.book;
    const oldBookUrl = oldBook.bookUrl;
    const chapterIndex = this.clampChapterIndex(this.currentChapterIndex);
    const pageIndex = Math.max(0, this.currentPageIndex);
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const source = searchBook.origin ? await db.getBookSource(searchBook.origin) : null;
      if (!source) {
        promptAction.showToast({ message: '书源不存在或已删除' });
        return;
      }
      if (!this.isChangeSourceSessionActive(sessionId)) {
        return;
      }

      const nextBook = this.buildBookFromSearchResult(searchBook, oldBook, chapterIndex, pageIndex);
      const service = new WebBookService();
      const fullBook = await service.getBookInfo(source, nextBook);
      if (!this.isChangeSourceSessionActive(sessionId)) {
        return;
      }
      this.preserveSwitchBookState(fullBook, nextBook, oldBook, chapterIndex, pageIndex);
      const chapters = await service.getChapterList(source, fullBook);
      if (!this.isChangeSourceSessionActive(sessionId)) {
        return;
      }
      fullBook.totalChapterNum = chapters.length;
      if (chapters.length > 0) {
        const safeIndex = Math.max(0, Math.min(chapterIndex, chapters.length - 1));
        fullBook.durChapterIndex = safeIndex;
        fullBook.durChapterTitle = chapters[safeIndex].title;
        fullBook.latestChapterTitle = chapters[chapters.length - 1].title;
      }

      if (oldBookUrl !== fullBook.bookUrl) {
        await db.deleteBook(oldBookUrl);
        const existing = await db.getBook(fullBook.bookUrl);
        if (existing) {
          await db.deleteBook(existing.bookUrl);
        }
        await db.insertBook(fullBook);
      } else {
        await db.updateBook(fullBook);
        await db.deleteBookChapters(fullBook.bookUrl);
        await db.deleteBookCachedContent(fullBook.bookUrl);
      }
      if (chapters.length > 0) {
        await db.insertBookChapters(chapters);
      }

      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      this.bookUrl = fullBook.bookUrl;
      this.book = fullBook;
      this.closeChangeSourceDialog();
      promptAction.showToast({ message: `已切换至 ${fullBook.originName || searchBook.originName}` });
      await this.loadBook();
    } catch (e) {
      if (!this.isChangeSourceSessionActive(sessionId)) {
        return;
      }
      console.error('切换书源失败:', e);
      promptAction.showToast({ message: '切换书源失败' });
    } finally {
      if (sessionId === this.changeSourceSessionId) {
        this.isSwitchingSource = false;
      }
    }
  }

  buildBookFromSearchResult(searchBook: SearchBook, oldBook: Book, chapterIndex: number, pageIndex: number): Book {
    const book = new Book();
    book.bookUrl = searchBook.bookUrl;
    book.tocUrl = searchBook.tocUrl;
    book.origin = searchBook.origin;
    book.originName = searchBook.originName;
    book.name = searchBook.name || oldBook.name;
    book.author = searchBook.author || oldBook.author;
    book.kind = BookFieldSanitizer.prefer(searchBook.kind, oldBook.kind);
    book.coverUrl = CoverUrlNormalizer.prefer(searchBook.coverUrl, oldBook.coverUrl);
    book.customCoverUrl = oldBook.customCoverUrl;
    book.intro = BookFieldSanitizer.prefer(searchBook.intro, oldBook.intro);
    book.customIntro = oldBook.customIntro;
    book.latestChapterTitle = BookFieldSanitizer.prefer(searchBook.latestChapterTitle, oldBook.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.prefer(searchBook.wordCount, oldBook.wordCount);
    book.variable = searchBook.variable || '';
    book.group = oldBook.group;
    book.order = oldBook.order;
    book.originOrder = oldBook.originOrder;
    book.readConfig = oldBook.readConfig;
    book.canUpdate = oldBook.canUpdate;
    book.durChapterIndex = chapterIndex;
    book.durChapterPos = pageIndex;
    book.durChapterTitle = oldBook.durChapterTitle;
    book.durChapterTime = Date.now();
    book.putVariable('lastReadTime', `${Date.now()}`);
    return book;
  }

  preserveSwitchBookState(target: Book, source: Book, oldBook: Book, chapterIndex: number, pageIndex: number): void {
    target.origin = source.origin;
    target.originName = source.originName;
    target.coverUrl = CoverUrlNormalizer.prefer(source.coverUrl, target.coverUrl);
    target.group = oldBook.group;
    target.order = oldBook.order;
    target.originOrder = oldBook.originOrder;
    target.customCoverUrl = oldBook.customCoverUrl;
    target.customIntro = oldBook.customIntro;
    target.readConfig = oldBook.readConfig;
    target.canUpdate = oldBook.canUpdate;
    target.durChapterIndex = chapterIndex;
    target.durChapterPos = pageIndex;
    target.durChapterTitle = oldBook.durChapterTitle;
    target.durChapterTime = Date.now();
    target.syncTime = oldBook.syncTime;
    target.putVariable('lastReadTime', `${Date.now()}`);
  }

  async saveReadingProgress(): Promise<void> {
    if (!this.book || this.chapters.length === 0) {
      return;
    }
    if (!this.canSaveReadingProgress()) {
      return;
    }
    const engine = ReadBookEngine.get();
    const chapterIndex = this.clampChapterIndex(this.currentChapterIndex);
    const pageIndex = Math.max(0, Math.min(this.currentPageIndex, Math.max(0, this.contentPages.length - 1)));
    if (!Book.hasStartedReading(this.book) && chapterIndex <= 0 && pageIndex <= 0) {
      engine.curIdx = chapterIndex;
      engine.curPos = pageIndex;
      return;
    }
    this.currentChapterIndex = chapterIndex;
    this.currentPageIndex = pageIndex;
    this.book.durChapterIndex = chapterIndex;
    this.book.durChapterPos = pageIndex;
    const now = Date.now();
    this.book.durChapterTitle = this.getChapterTitle();
    this.book.durChapterTime = now;
    this.book.putVariable('readStarted', '1');
    this.book.putVariable('lastReadTime', `${now}`);
    engine.curIdx = chapterIndex;
    engine.curPos = pageIndex;
    engine.book = this.book;
    const bookUrl = this.book.bookUrl;
    const chapterTitle = this.book.durChapterTitle;
    const variable = this.book.variable;
    const shouldRefreshRecentCard = chapterIndex !== this.lastRecentReadCardChapterIndex;
    this.lastRecentReadCardChapterIndex = chapterIndex;
    const previous = this.readingProgressSaveQueue.catch(() => {
    });
    const next = previous.then(async () => {
      const db = AppDatabase.getInstance();
      await db.updateBookReadingProgress(bookUrl, chapterTitle, chapterIndex, pageIndex, now, variable);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      this.reloadRecentReadCardLater(shouldRefreshRecentCard);
    });
    this.readingProgressSaveQueue = next;
    try {
      await next;
    } catch (e) {
      console.error('保存阅读进度失败:', e);
    }
  }

  async markBookRecentlyRead() {
    if (!this.book) {
      return;
    }
    const now = Date.now();
    this.book.durChapterTime = now;
    this.book.putVariable('readStarted', '1');
    this.book.putVariable('lastReadTime', `${now}`);
    try {
      const db = AppDatabase.getInstance();
      await db.updateBook(this.book);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      this.lastRecentReadCardChapterIndex = this.currentChapterIndex;
      this.reloadRecentReadCardLater(true);
    } catch (e) {
      console.error('更新最近阅读时间失败:', e);
    }
  }

  reloadRecentReadCardLater(force: boolean = false): void {
    const now = Date.now();
    if (!force && now - this.lastRecentReadCardReloadAt < 30000) {
      return;
    }
    this.lastRecentReadCardReloadAt = now;
    const context = getContext(this) as common.UIAbilityContext;
    setTimeout(() => {
      RecentReadCardUpdater.reload(context).catch((err: Error) => {
        console.error('刷新最近阅读卡片失败:', err);
      });
    }, 0);
  }

  async saveReadConfig() {
    if (!this.book) return;
    this.book.setPageAnim(this.currentReaderThemeIndex());
    try {
      const db = AppDatabase.getInstance();
      await db.updateBook(this.book);
    } catch (e) {
      console.error('保存阅读设置失败:', e);
    }
  }

  @Builder
  readerBottomInfoBar() {
    Row() {
      Text(this.getChapterInfoText())
        .fontSize(12)
        .fontColor(this.getSubTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(this.getPageInfoText())
        .fontSize(12)
        .fontColor(this.getSubTextColor())
        .textAlign(TextAlign.End)
        .margin({ left: 12 })
    }
    .width('100%')
    .height(this.getReaderBottomInfoBarHeight())
    .padding({ left: 18, right: 18, top: 0, bottom: 0 })
    .alignItems(VerticalAlign.Top)
    .backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  onReaderLandscapeDoublePageChanged(): void {
    const readingOffset = this.getCurrentPageStartOffset();
    this.finishPageTurnAnimation();
    this.readerPaginationCache.clear();
    this.paginateContent(this.content);
    this.currentPageIndex = this.normalizeReaderSpreadPageIndex(this.findPageIndexByOffset(readingOffset));
    this.syncCurrentPageText();
    this.refreshReaderTextRender();
    this.saveReadingProgress();
    this.saveReadConfig();
  }

  @Builder
  ttsMediaControlsBar() {
    if (this.ttsMediaControlsExpanded) {
      this.ttsExpandedMediaControlsBar()
    } else {
      this.ttsCollapsedMediaControlButton()
    }
  }

  @Builder
  ttsCollapsedMediaControlButton() {
    Row() {
      SymbolGlyph($r('sys.symbol.speaker_wave_3'))
        .fontSize(17)
        .fontColor(['#FFFFFF'])

      Text('朗读')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)

      if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
        Text(this.ttsSpeed.toFixed(1) + 'x')
          .fontSize(11)
          .fontColor('#EAF2FF')
          .margin({ left: 4 })
      }
    }
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(22)
    .backgroundColor(this.accentColor())
    .alignItems(VerticalAlign.Center)
    .shadow({
      radius: 10,
      color: this.isReaderThemeDark() ? '#66000000' : '#26000000',
      offsetX: 0,
      offsetY: 3
    })
    .position({ x: '100%', y: '100%' })
    .translate({ x: -104, y: -96 })
    .onClick(() => {
      if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
        this.ttsMediaControlsExpanded = true;
        this.syncTtsSystemMediaControls();
      } else {
        this.toggleTtsReading();
      }
    })
  }

  @Builder
  ttsExpandedMediaControlsBar() {
    HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
      TabContent() {
        Column()
      }
      .height(48)
      .tabBar(this.ttsMediaTimerControl())

      TabContent() {
        Column()
      }
      .height(48)
      .tabBar(this.ttsMediaSymbolControl($r('sys.symbol.arrow_left'),
        this.canPlayPreviousTtsChapter(), '上一章'))

      TabContent() {
        Column()
      }
      .height(48)
      .tabBar(this.ttsMediaSymbolControl($r('sys.symbol.pause'), true, '停止朗读'))

      TabContent() {
        Column()
      }
      .height(48)
      .tabBar(this.ttsMediaSymbolControl($r('sys.symbol.arrow_right'),
        this.canPlayNextTtsChapter(), '下一章'))

      TabContent() {
        Column()
      }
      .height(48)
      .tabBar(this.ttsMediaSpeedControl())

      TabContent() {
        Column()
      }
      .height(48)
      .tabBar(this.ttsMediaSymbolControl($r('sys.symbol.xmark'), true, '关闭朗读控制'))
    }
    .barMode(BarMode.Fixed)
    .barHeight(48)
    .barOverlap(true)
    .barFloatingStyle({
      barWidth: {
        smallWidth: this.readerTtsExpandedControlWidth(),
        mediumWidth: this.readerTtsExpandedControlWidth(),
        largeWidth: this.readerTtsExpandedControlWidth()
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      barSideMargin: 0,
      barBottomMargin: 4,
      gradientMask: {
        maskColor: '#00000000',
        maskHeight: 56
      },
      adaptToHandedness: false,
      thermoCtrl: true,
      barOpacity: 1
    })
    .scrollable(false)
    .onContentWillChange(() => false)
    .onTabBarClick((index: number) => {
      this.handleTtsExpandedControl(index);
    })
    .width(this.readerTtsExpandedControlWidth())
    .height(56)
    .position({ x: '100%', y: '100%' })
    .translate({
      x: -(this.readerTtsExpandedControlWidth() + this.readerFloatingBarSideInset()),
      y: -(this.readerBottomMenuOverlayHeight() + 66)
    })
  }

  @Builder
  ttsMediaTimerControl() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.timer'))
        .fontSize(22)
        .fontColor([this.getTextColor()])

      if (this.ttsSleepTimerMinutes > 0) {
        Text(`${Math.max(1, Math.ceil(this.ttsSleepTimerRemainingSeconds / 60))}`)
          .fontSize(8)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width(16)
          .height(16)
          .borderRadius(8)
          .backgroundColor(this.accentColor())
          .position({ x: 25, y: 2 })
      }
    }
    .width('100%')
    .height(48)
    .accessibilityText(this.ttsSleepTimerMinutes > 0 ?
      `朗读定时剩余 ${Math.max(1, Math.ceil(this.ttsSleepTimerRemainingSeconds / 60))} 分钟` : '设置朗读定时')
    .translate({ y: -2 })
  }

  @Builder
  ttsMediaSymbolControl(icon: Resource, enabled: boolean, accessibilityLabel: string) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([enabled ? this.getTextColor() : this.getSubTextColor()])
    }
    .width('100%')
    .height(48)
    .opacity(enabled ? 1 : 0.45)
    .accessibilityText(accessibilityLabel)
    .translate({ y: -2 })
  }

  @Builder
  ttsMediaSpeedControl() {
    Text(`${this.ttsSpeed.toFixed(1)}x`)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.getTextColor())
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(48)
      .translate({ y: -2 })
  }

  readerTtsExpandedControlWidth(): number {
    return 264;
  }

  handleTtsExpandedControl(index: number): void {
    if (index === 0) {
      this.cycleTtsSleepTimer();
    } else if (index === 1 && this.canPlayPreviousTtsChapter()) {
      this.playPreviousChapterFromMediaSession();
    } else if (index === 2) {
      this.toggleTtsReading();
      this.showMenu = true;
    } else if (index === 3 && this.canPlayNextTtsChapter()) {
      this.playNextChapterFromMediaSession();
    } else if (index === 4) {
      this.cycleTtsSpeed();
    } else if (index === 5) {
      this.ttsMediaControlsExpanded = false;
      this.showMenu = true;
      this.syncTtsSystemMediaControls();
    }
  }

  cycleTtsSleepTimer(): void {
    const options: number[] = [0, 15, 30, 60, 90, 120];
    const currentIndex = options.indexOf(this.ttsSleepTimerMinutes);
    const nextMinutes = options[(currentIndex + 1) % options.length];
    this.setTtsSleepTimer(nextMinutes);
  }

  setTtsSleepTimer(minutes: number): void {
    this.clearTtsSleepTimer();
    if (minutes <= 0) {
      promptAction.showToast({ message: '已关闭朗读定时' });
      return;
    }
    this.ttsSleepTimerMinutes = minutes;
    this.ttsSleepTimerRemainingSeconds = minutes * 60;
    this.ttsSleepTimerEndAt = Date.now() + minutes * 60 * 1000;
    this.ttsSleepTimerId = setInterval(() => {
      const remaining = Math.max(0, Math.ceil((this.ttsSleepTimerEndAt - Date.now()) / 1000));
      this.ttsSleepTimerRemainingSeconds = remaining;
      if (remaining <= 0) {
        this.clearTtsSleepTimer();
        this.stopTtsReading();
        promptAction.showToast({ message: '朗读定时结束，已停止朗读' });
      }
    }, 1000);
    promptAction.showToast({ message: `将在 ${minutes} 分钟后停止朗读` });
  }

  clearTtsSleepTimer(): void {
    if (this.ttsSleepTimerId >= 0) {
      clearInterval(this.ttsSleepTimerId);
      this.ttsSleepTimerId = -1;
    }
    this.ttsSleepTimerEndAt = 0;
    this.ttsSleepTimerMinutes = 0;
    this.ttsSleepTimerRemainingSeconds = 0;
  }

  cycleTtsSpeed(): void {
    const speeds: number[] = [0.8, 1.0, 1.2, 1.5, 2.0];
    let nextIndex = speeds.findIndex((speed: number) => speed > this.ttsSpeed + 0.01);
    if (nextIndex < 0) {
      nextIndex = 0;
    }
    this.applyTtsSpeed(speeds[nextIndex]);
    promptAction.showToast({ message: `朗读倍速 ${speeds[nextIndex].toFixed(1)}x` });
  }

  shouldShowTtsMediaControls(): boolean {
    return this.ttsMediaControlsExpanded && (this.isTtsSpeaking || this.ttsReader.isSpeaking()) &&
      this.showMenu && !this.showToc && !this.showSettings && !this.shouldBlockReaderInteraction();
  }

  canPlayPreviousTtsChapter(): boolean {
    return this.chapters.length > 0 && this.currentChapterIndex > 0;
  }

  canPlayNextTtsChapter(): boolean {
    return this.chapters.length > 0 && this.currentChapterIndex < this.chapters.length - 1;
  }

  disabledButtonColor(): string {
    return this.isReaderThemeDark() ? '#44515A66' : '#C8CDD4';
  }

  @Builder
  readerTapLayer() {
    if (this.readerPageTurnMode === 2) {
      Column() {
        ForEach([0, 1, 2], (row: number) => {
          Row() {
            ForEach([0, 1, 2], (column: number) => {
              Blank()
                .height('100%')
                .layoutWeight(1)
                .onClick(() => {
                  if (this.consumeSuppressedReaderTapClick()) {
                    return;
                  }
                  this.commitReaderTapZone(row * 3 + column);
                })
            }, (column: number) => `${row}_${column}`)
          }
          .width('100%')
          .layoutWeight(1)
        }, (row: number) => `${row}`)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .onTouch((event: TouchEvent) => {
        this.handleReaderTouch(event);
      })
      .parallelGesture(
        PanGesture({ direction: PanDirection.All, distance: 1 })
          .onActionStart((event: GestureEvent) => {
            this.handleReaderPanStart(event);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.handleReaderPanUpdate(event);
          })
          .onActionEnd((event: GestureEvent) => {
            this.handleReaderPanEnd(event);
          })
          .onActionCancel(() => {
            this.handleReaderPanCancel();
          })
      )
    } else if (this.readerPageTurnMode === 0) {
      Column() {
        Blank()
          .width('100%')
          .layoutWeight(3)
          .onClick(() => {
            if (this.consumeSuppressedReaderTapClick()) {
              return;
            }
            this.turnPrev();
          })

        Row() {
          Blank()
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              if (this.consumeSuppressedReaderTapClick()) {
                return;
              }
              this.turnPrev();
            })
          Blank()
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              if (this.consumeSuppressedReaderTapClick()) {
                return;
              }
              this.showMenu = true;
            })
          Blank()
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              if (this.consumeSuppressedReaderTapClick()) {
                return;
              }
              this.turnNext();
            })
        }
        .width('100%')
        .layoutWeight(4)

        Blank()
          .width('100%')
          .layoutWeight(3)
          .onClick(() => {
            if (this.consumeSuppressedReaderTapClick()) {
              return;
            }
            this.turnNext();
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .onTouch((event: TouchEvent) => {
        this.handleReaderTouch(event);
      })
      .parallelGesture(
        PanGesture({ direction: this.readerPageTurnMode === 0 ? PanDirection.Vertical : PanDirection.Horizontal, distance: 1 })
          .onActionStart((event: GestureEvent) => {
            this.handleReaderPanStart(event);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.handleReaderPanUpdate(event);
          })
          .onActionEnd((event: GestureEvent) => {
            this.handleReaderPanEnd(event);
          })
          .onActionCancel(() => {
            this.handleReaderPanCancel();
          })
      )
    } else {
      Blank()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.consumeSuppressedReaderTapClick()) {
            return;
          }
          if (this.readerPageTurnMode === 1 && !this.showMenu && !this.showToc && !this.showSettings) {
            this.showMenu = true;
          }
        })
        .onTouch((event: TouchEvent) => {
          this.handleReaderTouch(event);
        })
        .parallelGesture(
          PanGesture({ direction: PanDirection.All, distance: 1 })
            .onActionStart((event: GestureEvent) => {
              this.handleReaderPanStart(event);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.handleReaderPanUpdate(event);
            })
            .onActionEnd((event: GestureEvent) => {
              this.handleReaderPanEnd(event);
            })
            .onActionCancel(() => {
              this.handleReaderPanCancel();
            })
        )
    }
  }

  canHandleReaderPageTurnPan(): boolean {
    return !this.showMenu && !this.showToc && !this.showSettings &&
      this.chapters.length > 0 && !this.isPageTurning;
  }

  handleReaderPanStart(_event: GestureEvent): void {
    if (!this.canHandleReaderPageTurnPan()) {
      return;
    }
    this.readerPanActive = true;
    this.readerTouchMoved = false;
    this.suppressReaderTapClick = false;
    this.slideResetSerial++;
  }

  canHandleBookmarkPull(offsetX: number, offsetY: number): boolean {
    return this.readerPageTurnMode !== 0 && offsetY > 0 &&
      Math.abs(offsetY) > Math.abs(offsetX) * 1.25;
  }

  updateBookmarkPullEffect(offsetY: number): void {
    this.bookmarkPullActive = true;
    this.bookmarkPullOffsetY = Math.min(128, Math.max(0, offsetY * 0.52));
    this.bookmarkPullReady = offsetY >= 112;
    this.readerTouchMoved = true;
    this.suppressReaderTapClick = true;
    this.pageSlideOffsetX = 0;
    this.pageSlideOffsetY = 0;
    this.pageSlideDirection = 0;
  }

  finishBookmarkPull(commit: boolean): void {
    const shouldToggle = commit && this.bookmarkPullReady;
    this.bookmarkPullReady = false;
    this.bookmarkPullActive = false;
    animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.bookmarkPullOffsetY = 0;
    });
    if (shouldToggle) {
      this.toggleCurrentPageBookmark();
    }
  }

  handleReaderPanUpdate(event: GestureEvent): void {
    if (!this.canHandleReaderPageTurnPan()) {
      return;
    }
    if (!this.readerPanActive) {
      this.handleReaderPanStart(event);
    }
    const offsetX = event.offsetX;
    const offsetY = event.offsetY;
    if (this.bookmarkPullActive || this.canHandleBookmarkPull(offsetX, offsetY)) {
      this.updateBookmarkPullEffect(offsetY);
      return;
    }
    if (!this.isPageTurnAnimationEnabled()) {
      return;
    }
    if (this.isReaderTouchMoved(offsetX, offsetY)) {
      this.readerTouchMoved = true;
      this.suppressReaderTapClick = true;
    }
    this.updateSlidePageEffect(this.getReaderPageTurnGestureOffset(offsetX, offsetY));
  }

  handleReaderPanEnd(event: GestureEvent): void {
    if (!this.readerPanActive) {
      return;
    }
    this.readerPanActive = false;
    if (this.bookmarkPullActive) {
      this.readerTouchMoved = true;
      this.suppressReaderTapClick = true;
      this.finishBookmarkPull(true);
      return;
    }
    const offsetX = event.offsetX;
    const offsetY = event.offsetY;
    if (this.isReaderPageTurnCommitGesture(offsetX, offsetY)) {
      this.readerTouchMoved = true;
      this.suppressReaderTapClick = true;
      this.commitReaderMove(offsetX, offsetY);
      return;
    }
    if (this.readerTouchMoved || this.isReaderTouchMoved(offsetX, offsetY)) {
      this.suppressReaderTapClick = true;
      this.rollbackSlidePageEffect();
      return;
    }
    this.resetSlidePageEffect();
  }

  handleReaderPanCancel(): void {
    if (!this.readerPanActive) {
      return;
    }
    this.readerPanActive = false;
    if (this.bookmarkPullActive) {
      this.suppressReaderTapClick = true;
      this.finishBookmarkPull(false);
      return;
    }
    if (Math.abs(this.getPageSlideAxisOffset()) > 0.5) {
      this.suppressReaderTapClick = true;
      this.rollbackSlidePageEffect();
      return;
    }
    this.resetSlidePageEffect();
  }

  handleReaderTouch(event: TouchEvent): void {
    if (this.showMenu || this.showToc || this.showSettings || this.chapters.length === 0) {
      return;
    }
    const point = event.changedTouches && event.changedTouches.length > 0 ? event.changedTouches[0] :
      (event.touches && event.touches.length > 0 ? event.touches[0] : null);
    if (!point) {
      return;
    }
    const x = point.x;
    const y = point.y;
    if (event.type === TouchType.Down) {
      this.readerTouchStartX = x;
      this.readerTouchStartY = y;
      this.readerTouchLastX = x;
      this.readerTouchLastY = y;
      this.readerTouchActive = true;
      this.readerTouchMoved = false;
      this.suppressReaderTapClick = false;
      this.slideResetSerial++;
      return;
    }
    if (!this.readerTouchActive) {
      return;
    }
    if (event.type === TouchType.Move) {
      this.readerTouchLastX = x;
      this.readerTouchLastY = y;
      const offsetX = x - this.readerTouchStartX;
      const offsetY = y - this.readerTouchStartY;
      if (!this.isPageTurnAnimationEnabled()) {
        return;
      }
      if (this.isReaderTouchMoved(offsetX, offsetY)) {
        this.readerTouchMoved = true;
        this.suppressReaderTapClick = true;
      }
      this.updateSlidePageEffect(this.getReaderPageTurnGestureOffset(offsetX, offsetY));
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.readerTouchLastX = x;
      this.readerTouchLastY = y;
      this.readerTouchActive = false;
      this.finishReaderHorizontalTouch(event.type === TouchType.Up);
    }
  }

  finishReaderHorizontalTouch(canCommitTap: boolean = true): void {
    const offsetX = this.readerTouchLastX - this.readerTouchStartX;
    const offsetY = this.readerTouchLastY - this.readerTouchStartY;
    if (this.isReaderPageTurnCommitGesture(offsetX, offsetY)) {
      this.readerTouchMoved = true;
      this.suppressReaderTapClick = true;
      this.commitReaderMove(offsetX, offsetY);
      return;
    }
    if (this.readerTouchMoved || this.isReaderTouchMoved(offsetX, offsetY)) {
      this.suppressReaderTapClick = true;
      this.rollbackSlidePageEffect();
      return;
    }
    if (canCommitTap && !this.isPageTurnAnimationEnabled() && this.commitReaderTapByPoint(this.readerTouchLastX,
      this.readerTouchLastY)) {
      this.suppressReaderTapClick = true;
      this.resetSlidePageEffect();
      return;
    }
    this.resetSlidePageEffect();
  }

  commitReaderTapByPoint(x: number, y: number): boolean {
    if (this.isPageTurnAnimationEnabled() && this.readerPageTurnMode !== 0 && this.readerPageTurnMode !== 2) {
      return false;
    }
    const width = Math.max(1, this.pageViewWidth || this.getPageTurnWidth());
    const height = Math.max(1, this.pageViewHeight || this.getPageTurnHeight());
    if (this.readerPageTurnMode === 2) {
      return this.commitReaderTapZone(this.getTapZoneIndex(x, y, width, height));
    }
    if (y < height * 0.3) {
      this.turnPrev();
      return true;
    }
    if (y > height * 0.7) {
      this.turnNext();
      return true;
    }
    if (x < width / 3) {
      this.turnPrev();
      return true;
    }
    if (x > width * 2 / 3) {
      this.turnNext();
      return true;
    }
    this.showMenu = true;
    return true;
  }

  getTapZoneIndex(x: number, y: number, width: number, height: number): number {
    const column = Math.max(0, Math.min(2, Math.floor(Math.max(0, x) / Math.max(1, width / 3))));
    const row = Math.max(0, Math.min(2, Math.floor(Math.max(0, y) / Math.max(1, height / 3))));
    return row * 3 + column;
  }

  commitReaderTapZone(index: number): boolean {
    return this.commitReaderTapAction(this.readerTapZoneActionAt(index));
  }

  commitReaderTapAction(action: number): boolean {
    switch (action) {
      case 1:
        this.showMenu = true;
        return true;
      case 2:
        this.turnNext();
        return true;
      case 3:
        this.turnPrev();
        return true;
      case 0:
      default:
        return true;
    }
  }

  readerTapZoneActionsList(): number[] {
    const fallback = [3, 3, 3, 3, 1, 2, 2, 2, 2];
    const parts = (this.readerTapZoneActions || '').split(',');
    const result: number[] = [];
    for (let i = 0; i < 9; i++) {
      const parsed = Number(parts[i]);
      result.push(Number.isFinite(parsed) && parsed >= 0 && parsed <= 3 ? Math.round(parsed) : fallback[i]);
    }
    return result;
  }

  readerTapZoneActionAt(index: number): number {
    const actions = this.readerTapZoneActionsList();
    const safeIndex = Math.max(0, Math.min(8, Math.round(index)));
    return actions[safeIndex];
  }

  cycleTapZoneAction(index: number): void {
    const actions = this.readerTapZoneActionsList();
    const safeIndex = Math.max(0, Math.min(8, Math.round(index)));
    actions[safeIndex] = (actions[safeIndex] + 1) % 4;
    this.setTapZoneActions(actions.join(','));
  }

  setTapZoneActions(actions: string): void {
    const normalized = this.normalizeTapZoneActions(actions);
    this.readerTapZoneActions = normalized;
    ReaderSettingsStore.saveTapZoneActions(getContext(this), normalized).catch((e: Error) => {
      console.error('保存点击区域动作失败:', e);
    });
  }

  normalizeTapZoneActions(actions: string): string {
    const fallback = [3, 3, 3, 3, 1, 2, 2, 2, 2];
    const parts = (actions || '').split(',');
    const result: number[] = [];
    for (let i = 0; i < 9; i++) {
      const parsed = Number(parts[i]);
      result.push(Number.isFinite(parsed) && parsed >= 0 && parsed <= 3 ? Math.round(parsed) : fallback[i]);
    }
    return result.join(',');
  }

  tapActionLabel(action: number): string {
    switch (action) {
      case 1:
        return '菜单';
      case 2:
        return '下一页';
      case 3:
        return '上一页';
      case 0:
      default:
        return '无动作';
    }
  }

  tapZoneCellColor(action: number): string {
    if (action === 1) {
      return '#332A6FCC';
    }
    if (action === 2) {
      return '#2239A86B';
    }
    if (action === 3) {
      return '#22A85C39';
    }
    return '#14000000';
  }

  tapZoneSummaryText(): string {
    const actions = this.readerTapZoneActionsList();
    let menuCount = 0;
    let nextCount = 0;
    let prevCount = 0;
    let noneCount = 0;
    for (const action of actions) {
      if (action === 1) {
        menuCount++;
      } else if (action === 2) {
        nextCount++;
      } else if (action === 3) {
        prevCount++;
      } else {
        noneCount++;
      }
    }
    return `菜单${menuCount} · 下一页${nextCount} · 上一页${prevCount} · 无动作${noneCount}`;
  }

  isReaderTouchMoved(offsetX: number, offsetY: number): boolean {
    return Math.abs(offsetX) > this.readerTapSlop || Math.abs(offsetY) > this.readerTapSlop;
  }

  consumeSuppressedReaderTapClick(): boolean {
    if (!this.suppressReaderTapClick) {
      return false;
    }
    this.suppressReaderTapClick = false;
    return true;
  }

  getReaderPageTurnGestureOffset(offsetX: number, offsetY: number): number {
    return this.isVerticalPageTurnAnimation() ? offsetY : offsetX;
  }

  isReaderPageTurnCommitGesture(offsetX: number, offsetY: number): boolean {
    if (this.isVerticalPageTurnAnimation()) {
      return Math.abs(offsetY) >= 48 && Math.abs(offsetY) > Math.abs(offsetX) * 1.2;
    }
    return Math.abs(offsetX) >= 48 && Math.abs(offsetX) > Math.abs(offsetY) * 1.2;
  }

  commitReaderMove(offsetX: number, offsetY: number): void {
    if (this.isVerticalPageTurnAnimation()) {
      this.commitReaderVerticalMove(offsetY);
      return;
    }
    this.commitReaderHorizontalMove(offsetX);
  }

  commitReaderVerticalMove(offsetY: number): void {
    if (!this.isVerticalPageTurnAnimation() || this.showToc || this.showSettings ||
      this.chapters.length === 0) {
      return;
    }
    if (offsetY < -48) {
      this.runPageTurnAnimation(1, 'gesture');
    } else if (offsetY > 48) {
      this.runPageTurnAnimation(-1, 'gesture');
    } else {
      this.resetSlidePageEffect();
    }
  }

  commitReaderHorizontalMove(offsetX: number): void {
    if ((this.readerPageTurnMode !== 1 && this.readerPageTurnMode !== 2) || this.showToc || this.showSettings ||
      this.chapters.length === 0) {
      return;
    }
    if (offsetX < -48) {
      this.runPageTurnAnimation(1, 'gesture');
    } else if (offsetX > 48) {
      this.runPageTurnAnimation(-1, 'gesture');
    } else {
      this.resetSlidePageEffect();
    }
  }

  @Builder
  settingsPanel() {
    Column({ space: 12 }) {
      Row() {
        Text(this.settingsPanelTab === 0 ? '阅读设置' : '朗读设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getTextColor())

        Blank()
          .layoutWeight(1)

        Text('×')
          .fontSize(28)
          .fontColor(this.getTextColor())
          .textAlign(TextAlign.Center)
          .width(46)
          .height(46)
          .borderRadius(23)
          .backgroundColor(this.isReaderThemeDark() ? '#24FFFFFF' : '#0D000000')
          .accessibilityText('关闭设置')
          .onClick(() => {
            this.closeSettingsPanelKeepMenu();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 14 }) {
          if (this.settingsPanelTab === 0) {
            this.readerQuickSettingsPanel()
          } else {
            this.ttsQuickSettingsPanel()
          }
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .scrollBarColor(this.isReaderThemeDark() ? '#668A8F98' : '#667A6F63')
    }
    .width('94%')
    .height(520)
    .padding({ left: 20, right: 20, top: 16, bottom: 22 })
    .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
    .backgroundColor(this.readerGlassPanelColor())
    .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
    .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
    .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
    .position({ x: '3%', y: '100%' })
    .translate({ y: -(524 + this.readerBottomActionOverlayHeight()) })
  }

  @Builder
  settingsTabToggle() {
    Row() {
      Text('阅读')
        .fontSize(14)
        .fontWeight(this.settingsPanelTab === 0 ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.settingsPanelTab === 0 ? '#FFFFFF' : this.getTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(34)
        .borderRadius(17)
        .backgroundColor(this.settingsPanelTab === 0 ? this.accentColor() : Color.Transparent)
        .onClick(() => {
          this.settingsPanelTab = 0;
        })
      Text('朗读')
        .fontSize(14)
        .fontWeight(this.settingsPanelTab === 1 ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.settingsPanelTab === 1 ? '#FFFFFF' : this.getTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(34)
        .borderRadius(17)
        .backgroundColor(this.settingsPanelTab === 1 ? this.accentColor() : Color.Transparent)
        .onClick(() => {
          this.settingsPanelTab = 1;
          this.loadTtsSettingsAndVoices();
        })
    }
    .width(156)
    .padding(2)
    .borderRadius(19)
    .backgroundColor(this.isReaderThemeDark() ? '#24272D' : '#EEF0F3')
  }

  @Builder
  readerQuickTypographyStepper() {
    Row({ space: 8 }) {
      Select(this.quickTypographySettingOptions())
        .selected(this.quickTypographySettingIndex)
        .value(this.quickTypographySettingTitle())
        .font({ size: 15 })
        .fontColor(this.getSubTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.START)
        .padding({ left: 0, right: 0 })
        .borderRadius(0)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.getTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.isReaderThemeDark()))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor()))
        .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onSelect((index: number) => {
          this.showQuickTypographyValueInput = false;
          this.quickTypographySettingIndex = Math.max(0,
            Math.min(index, this.quickTypographySettingOptions().length - 1));
        })
      Blank()
        .layoutWeight(1)
      Button('-')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.adjustQuickTypographySetting(-1);
        })
      if (this.showQuickTypographyValueInput) {
        TextInput({ text: this.quickTypographyValueDraft,
          placeholder: `${this.currentQuickTypographySettingValue()}` })
          .type(InputType.Number)
          .defaultFocus(true)
          .fontSize(15)
          .fontColor(this.getTextColor())
          .width(52)
          .height(36)
          .padding(0)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.isReaderThemeDark() ? '#24272D' : '#EEF0F3')
          .borderRadius(6)
          .onChange((value: string) => {
            this.quickTypographyValueDraft = value.replace(/[^0-9]/g, '').substring(0, 3);
          })
          .onSubmit(() => {
            this.applyQuickTypographyValueInput();
          })
          .onBlur(() => {
            this.applyQuickTypographyValueInput();
          })
      } else {
        Text(`${this.currentQuickTypographySettingValue()}`)
          .fontSize(15)
          .fontColor(this.getTextColor())
          .width(52)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openQuickTypographyValueInput();
          })
      }
      Button('+')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.adjustQuickTypographySetting(1);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  readerQuickSettingsPanel() {
    Column({ space: 14 }) {
      this.readerQuickTypographyStepper()

      this.readerFontEntryItem()

      this.readerReplaceRulesEntryItem()

      this.readerSelectSettingItem('翻页方式', '选择滚动、滑动或点击翻页',
        this.pageTurnModeOptions(), this.pageTurnModeSelectedIndex(), (index: number) => {
          this.switchPageTurnMode(index);
        })

      if (this.readerPageTurnMode === 2) {
        this.readerTapZoneSettingItem()
      }

      this.readerSelectSettingItem('翻页动画', '选择滑动或点击翻页时使用的页面切换效果',
        this.pageTurnAnimationOptions(), this.pageTurnAnimationSelectedIndex(), (index: number) => {
          this.setReaderPageTurnAnimationType(index);
        })

      this.readerSwitchSettingItem('使用双翻页', '横屏或折叠屏展开等宽屏状态下同时显示左右两页',
        this.readerLandscapeDoublePage, (checked: boolean) => {
          this.setReaderLandscapeDoublePage(checked);
        })

      this.readerSwitchSettingItem('音量键翻页', '阅读页获得焦点时使用音量上/下键翻页', this.readerVolumeTurnPage,
        (checked: boolean) => {
          this.setReaderVolumeTurnPage(checked);
        })

      Row({ space: 10 }) {
        ForEach(this.currentReaderThemes(), (theme: ReaderThemeItem, index: number) => {
          Text(index === ReaderThemeHelper.CUSTOM_THEME_INDEX ? '自' :
            (index === ReaderThemeHelper.APP_THEME_INDEX ? '主' : ''))
            .width(42)
            .height(42)
            .borderRadius(21)
            .fontSize(13)
            .fontColor(theme.textColor)
            .textAlign(TextAlign.Center)
            .backgroundColor(theme.backgroundColor)
            .backgroundImage(theme.backgroundImageUri || '', ImageRepeat.NoRepeat)
            .backgroundImageSize(ImageSize.Cover)
            .border({
              width: this.currentReaderThemeIndex() === index ? 3 : 1,
              color: this.currentReaderThemeIndex() === index ? this.accentColor() : '#22000000'
            })
            .onClick(() => {
              this.applyReaderThemeIndex(index);
            })
        })
      }
      .width('100%')

      if (this.currentReaderThemeIndex() === ReaderThemeHelper.CUSTOM_THEME_INDEX) {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Select(this.customThemeOptions())
              .selected(this.currentCustomThemeSelectedIndex())
              .value(this.currentCustomThemeScheme().name)
              .font({ size: 14 })
              .fontColor(this.getTextColor())
              .backgroundColor(this.appDarkMode ? '#24FFFFFF' : '#12000000')
              .layoutWeight(1)
              .optionBgColor(Color.Transparent)
              .optionFontColor(this.getTextColor())
              .selectedOptionFontColor(this.accentColor())
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.isReaderThemeDark()))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor()))
              .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
              .onSelect((index: number) => {
                this.selectCustomTheme(index);
              })
            Button('新增')
              .height(36)
              .fontSize(13)
              .backgroundColor(this.accentColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.addCustomTheme();
              })
            Button('删除')
              .height(36)
              .fontSize(13)
              .backgroundColor(this.appDarkMode ? '#24FFFFFF' : '#12000000')
              .fontColor(this.getTextColor())
              .onClick(() => {
                this.deleteCurrentCustomTheme();
              })
          }
          .width('100%')
          TextInput({ text: this.customThemeNameDraft, placeholder: '输入方案名称' })
            .fontSize(14)
            .fontColor(this.getTextColor())
            .height(36)
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.appDarkMode ? '#24FFFFFF' : '#12000000')
            .borderRadius(8)
            .onChange((value: string) => {
              this.customThemeNameDraft = value.substring(0, 20);
            })
            .onSubmit(() => {
              this.renameCurrentCustomTheme(this.customThemeNameDraft);
            })
            .onBlur(() => {
              this.renameCurrentCustomTheme(this.customThemeNameDraft);
            })
          Row() {
            Text('背景设置')
              .fontSize(14)
              .fontColor(this.getTextColor())
            Blank()
            Select([{ value: '背景色' }, { value: '背景图片' }])
              .selected(this.currentCustomThemeBackgroundTypeIndex())
              .value(this.currentCustomThemeBackgroundTypeIndex() === 1 ? '背景图片' : '背景色')
              .font({ size: 14 })
              .fontColor(this.getTextColor())
              .backgroundColor(this.appDarkMode ? '#24FFFFFF' : '#12000000')
              .optionBgColor(Color.Transparent)
              .optionFontColor(this.getTextColor())
              .selectedOptionFontColor(this.accentColor())
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.isReaderThemeDark()))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor()))
              .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
              .onSelect((index: number) => {
                this.setCurrentCustomThemeBackgroundType(index);
              })
          }
          .width('100%')
          if (this.currentCustomThemeBackgroundTypeIndex() === 0) {
            ColorCodePicker({
              value: this.currentCustomThemeBackgroundColor(),
              placeholder: this.currentCustomThemeBackgroundColor(),
              appDarkMode: this.appDarkMode,
              accentColor: this.accentColor(),
              optionTitle: '背景颜色',
              onColorChange: (value: string) => {
                this.setCurrentThemeBackgroundColor(value);
              }
            })
          } else {
            Row({ space: 8 }) {
              Button(this.currentCustomThemeScheme().backgroundImageUri ? '更换背景图片' : '选择背景图片')
                .height(36)
                .fontSize(13)
                .backgroundColor(this.accentColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.chooseCurrentCustomThemeImage();
                })
              if (this.currentCustomThemeScheme().backgroundImageUri) {
                Button('移除图片')
                  .height(36)
                  .fontSize(13)
                  .backgroundColor(this.appDarkMode ? '#24FFFFFF' : '#12000000')
                  .fontColor(this.getTextColor())
                  .onClick(() => {
                    this.clearCurrentCustomThemeImage();
                  })
                Select([{ value: '裁剪填充' }, { value: '完整显示' }, { value: '拉伸铺满' }])
                  .selected(this.customThemeFitSelectedIndex())
                  .value(['裁剪填充', '完整显示', '拉伸铺满'][this.customThemeFitSelectedIndex()])
                  .font({ size: 13 })
                  .fontColor(this.getTextColor())
                  .backgroundColor(this.appDarkMode ? '#24FFFFFF' : '#12000000')
                  .layoutWeight(1)
                  .optionBgColor(Color.Transparent)
                  .optionFontColor(this.getTextColor())
                  .selectedOptionFontColor(this.accentColor())
                  .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.isReaderThemeDark()))
                  .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor()))
                  .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
                  .onSelect((index: number) => {
                    this.setCurrentCustomThemeImageFit(index);
                  })
              }
            }
            .width('100%')
          }
          ColorCodePicker({
            value: this.currentCustomThemeTextColor(),
            placeholder: this.currentCustomThemeTextColor(),
            appDarkMode: this.appDarkMode,
            accentColor: this.accentColor(),
            optionTitle: '文字颜色',
            onColorChange: (value: string) => {
              this.setCurrentThemeTextColor(value);
            }
          })
        }
        .width('100%')
      }

      this.readerSwitchSettingItem('正文扩展至状态栏', '开启后正文阅读区域会延伸到顶部状态栏安全区', this.readerExtendToStatusBar,
        (checked: boolean) => {
          this.setReaderExtendToStatusBar(checked);
        })

      this.readerPreloadSettingItem()
    }
    .width('100%')
  }

  @Builder
  readerFontEntryItem() {
    Row() {
      Column() {
        Text('阅读字体')
          .fontSize(15)
          .fontColor(this.getTextColor())
        Text('正文 / 标题 / 正则样式设置')
          .fontSize(12)
          .fontColor(this.getSubTextColor())
          .margin({ top: 4 })
      }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.getSubTextColor()])
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ReaderFontSettings' });
    })
  }

  @Builder
  readerReplaceRulesEntryItem() {
    Row() {
      Column() {
        Text('替换净化')
          .fontSize(15)
          .fontColor(this.getTextColor())
        Text('管理正文与章节标题的替换规则')
          .fontSize(12)
          .fontColor(this.getSubTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.getSubTextColor()])
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ReaderReplaceRules' });
    })
  }

  @Builder
  ttsQuickSettingsPanel() {
    Column({ space: 14 }) {
      Row() {
        Text('朗读倍速')
          .fontSize(15)
          .fontColor(this.getTextColor())
          .layoutWeight(1)
        Text(`${this.ttsSpeed.toFixed(1)}x`)
          .fontSize(14)
          .fontColor(this.getSubTextColor())
      }
      .width('100%')

      Slider({ value: this.ttsSpeed, min: 0.5, max: 2, step: 0.1 })
        .width('100%')
        .selectedColor(this.accentColor())
        .onChange((value: number) => {
          this.applyTtsSpeed(value);
        })

      Row({ space: 8 }) {
        this.ttsSpeedChip(0.8)
        this.ttsSpeedChip(1.0)
        this.ttsSpeedChip(1.2)
        this.ttsSpeedChip(1.5)
        this.ttsSpeedChip(2.0)
      }
      .width('100%')

      Row() {
        Text('朗读音色')
          .fontSize(15)
          .fontColor(this.getTextColor())
          .layoutWeight(1)
        if (this.ttsVoicesLoading) {
          Text('加载中')
            .fontSize(12)
            .fontColor(this.getSubTextColor())
        }
      }
      .width('100%')

      Column({ space: 8 }) {
        ForEach(this.ttsCustomVoiceOptions, (voice: HttpTTS) => {
          this.ttsCustomVoiceRow(voice)
        }, (voice: HttpTTS) => this.ttsCustomVoiceKey(voice))
        ForEach(this.ttsVoices, (voice: TtsVoiceOption) => {
          this.ttsVoiceRow(voice)
        }, (voice: TtsVoiceOption) => this.ttsVoiceKey(voice))
      }
      .width('100%')

      Button(this.isTtsSpeaking ? '停止朗读' : '开始朗读')
        .width('100%')
        .height(40)
        .backgroundColor(this.isTtsSpeaking ? '#E53935' : this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.toggleTtsReading();
        })
    }
    .width('100%')
  }

  @Builder
  ttsSpeedChip(value: number) {
    Text(`${value.toFixed(1)}x`)
      .fontSize(13)
      .fontColor(Math.abs(this.ttsSpeed - value) < 0.01 ? '#FFFFFF' : this.getTextColor())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(32)
      .borderRadius(16)
      .backgroundColor(Math.abs(this.ttsSpeed - value) < 0.01 ? this.accentColor() :
        (this.isReaderThemeDark() ? '#24272D' : '#EEF0F3'))
      .onClick(() => {
        this.applyTtsSpeed(value);
      })
  }

  @Builder
  ttsVoiceRow(voice: TtsVoiceOption) {
    Row() {
      Text(this.ttsVoiceTitle(voice))
        .fontSize(14)
        .fontColor(voice.available ? this.getTextColor() : this.getSubTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.isCurrentTtsVoice(voice) ? '✓' : (voice.downloadable ? '下载' : ''))
        .fontSize(voice.downloadable && !voice.available ? 13 : 18)
        .fontColor(this.accentColor())
        .width(44)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .borderRadius(8)
    .backgroundColor(this.isCurrentTtsVoice(voice) ? this.tocSelectedBackgroundColor() :
      (this.isReaderThemeDark() ? '#202329' : '#F6F7F9'))
    .onClick(() => {
      this.applyTtsVoice(voice, true);
    })
  }

  @Builder
  ttsCustomVoiceRow(voice: HttpTTS) {
    Row() {
      Text(this.ttsCustomVoiceTitle(voice))
        .fontSize(14)
        .fontColor(this.getTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.isCurrentCustomTtsVoice(voice) ? '✓' : '')
        .fontSize(18)
        .fontColor(this.accentColor())
        .width(44)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .borderRadius(8)
    .backgroundColor(this.isCurrentCustomTtsVoice(voice) ? this.tocSelectedBackgroundColor() :
      (this.isReaderThemeDark() ? '#202329' : '#F6F7F9'))
    .onClick(() => {
      this.applyCustomTtsVoice(voice, true);
    })
  }

  pageTurnModeOptions(): SelectOption[] {
    return [
      { value: '滚动阅读' },
      { value: '滑动翻页' },
      { value: '点击翻页' }
    ];
  }

  pageTurnModeSelectedIndex(): number {
    return this.readerPageTurnMode >= 0 && this.readerPageTurnMode <= 2 ? this.readerPageTurnMode : 0;
  }

  pageTurnAnimationOptions(): SelectOption[] {
    return [
      { value: '无动画' },
      { value: '平移' },
      { value: '淡入' },
      { value: '叠页' }
    ];
  }

  pageTurnAnimationTypes(): number[] {
    return [
      ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE,
      ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE,
      ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE,
      ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK
    ];
  }

  pageTurnAnimationSelectedIndex(): number {
    const types = this.pageTurnAnimationTypes();
    const value = this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType);
    for (let i = 0; i < types.length; i++) {
      if (types[i] === value) {
        return i;
      }
    }
    return 0;
  }

  pageTurnAnimationValue(): string {
    const options = this.pageTurnAnimationOptions();
    const index = this.pageTurnAnimationSelectedIndex();
    const option = options[index];
    return option && typeof option.value === 'string' ? option.value : '无动画';
  }

  @Builder
  readerTapZoneSettingItem() {
    Row() {
      Column() {
        Text('点击区域动作')
          .fontSize(15)
          .fontColor(this.getTextColor())
        Text(this.tapZoneSummaryText())
          .fontSize(12)
          .fontColor(this.getSubTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('配置')
        .height(34)
        .fontSize(13)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .margin({ left: 12 })
        .onClick(() => {
          this.showTapZoneSettings = true;
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  tapZoneSettingsDialog() {
    Column() {
      Column({ space: 14 }) {
        Row() {
          Text('点击区域动作')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(1)

          Button('×')
            .fontSize(26)
            .fontColor('#FFFFFF')
            .width(48)
            .height(48)
            .backgroundColor('#00000000')
            .padding(0)
            .onClick(() => {
              this.showTapZoneSettings = false;
            })
        }
        .width('calc(100% - 40vp)')
        .height(52)
        .alignItems(VerticalAlign.Center)

        Column() {
          ForEach([0, 1, 2], (row: number) => {
            Row() {
              ForEach([0, 1, 2], (column: number) => {
                this.tapZoneCell(row * 3 + column)
              }, (column: number) => `${row}_${column}`)
            }
            .width('100%')
            .layoutWeight(1)
            .clip(true)
          }, (row: number) => `${row}`)
        }
        .width('calc(100% - 40vp)')
        .layoutWeight(1)
        .border({ width: 1, color: '#33FFFFFF' })
        .clip(true)

        Row({ space: 12 }) {
          Button('重置默认')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor('#33383E')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.setTapZoneActions('3,3,3,3,1,2,2,2,2');
            })

          Button('完成')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor(this.accentColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.showTapZoneSettings = false;
            })
        }
        .width('calc(100% - 40vp)')
      }
      .width('100%')
      .height('100%')
      .padding({ top: 18, bottom: 22 })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#D9000000')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
  }

  @Builder
  tapZoneCell(index: number) {
    Text(this.tapActionLabel(this.readerTapZoneActionAt(index)))
      .fontSize(18)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .textAlign(TextAlign.Center)
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .backgroundColor(this.tapZoneCellColor(this.readerTapZoneActionAt(index)))
      .border({ width: 0.5, color: '#33FFFFFF' })
      .clip(true)
      .onClick(() => {
        this.cycleTapZoneAction(index);
      })
  }

  @Builder
  readerSelectSettingItem(title: string, description: string, options: SelectOption[], selected: number,
    onSelect: (index: number) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor(this.getTextColor())
        Text(description)
          .fontSize(12)
          .fontColor(this.getSubTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Select(options)
        .selected(selected)
        .value(this.readerSelectOptionValue(options, selected))
        .font({ size: 14 })
        .fontColor(this.getSubTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(0)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.getTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.isReaderThemeDark()))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor()))
        .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onSelect((index: number) => {
          onSelect(index);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
  }

  readerSelectOptionValue(options: SelectOption[], index: number): ResourceStr {
    if (index >= 0 && index < options.length) {
      return options[index].value;
    }
    return options.length > 0 ? options[0].value : '';
  }

  @Builder
  readerSwitchSettingItem(title: string, description: string, checked: boolean, onChange: (checked: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor(this.getTextColor())
        Text(description)
          .fontSize(12)
          .fontColor(this.getSubTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(this.buttonColor())
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  readerPreloadSettingItem() {
    Column() {
      Row() {
        Column() {
          Text('预缓存设置')
            .fontSize(15)
            .fontColor(this.getTextColor())
          Text(this.readerPreloadEnabled ? '阅读过程中提前缓存后续章节' : '已关闭自动预缓存')
            .fontSize(12)
            .fontColor(this.getSubTextColor())
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.readerPreloadEnabled })
          .selectedColor(this.buttonColor())
          .onChange((value: boolean) => {
            this.setReaderPreloadEnabled(value);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.readerPreloadEnabled) {
        Row() {
          Text('下一章节数')
            .fontSize(13)
            .fontColor(this.getTextColor())
            .layoutWeight(1)
          Text(`${this.readerPreloadChapterCount}章`)
            .fontSize(13)
            .fontColor(this.getSubTextColor())
        }
        .width('100%')
        .margin({ top: 10 })

        Slider({ value: this.readerPreloadChapterCount, min: 1, max: 10, step: 1 })
          .width('100%')
          .margin({ top: 6 })
          .selectedColor(this.accentColor())
          .onChange((sliderValue: number) => {
            this.setReaderPreloadChapterCount(sliderValue);
          })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
  }

  switchPageTurnMode(mode: number) {
    if (this.readerPageTurnMode === mode) {
      return;
    }
    this.stopTtsReading();
    this.readerPageTurnMode = mode;
    ReaderSettingsStore.savePageTurnMode(getContext(this), mode).catch((e: Error) => {
      console.error('保存翻页方式失败:', e);
    });
    this.currentPageIndex = 0;
    this.pendingRestorePageIndex = 0;
    this.paginateContent(this.content);
    this.saveReadingProgress();
    this.saveReadConfig();
  }

  setReaderPageTurnAnimationType(index: number): void {
    const types = this.pageTurnAnimationTypes();
    const type = index >= 0 && index < types.length ? types[index] : ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
    this.readerPageTurnAnimationType = this.normalizePageTurnAnimationType(type);
    this.resetSlidePageEffect();
    ReaderSettingsStore.savePageTurnAnimationType(getContext(this), this.readerPageTurnAnimationType).catch((e: Error) => {
      console.error('保存翻页动画失败:', e);
    });
    this.saveReadConfig();
  }

  normalizePageTurnAnimationType(type: number): number {
    const value = Math.round(type);
    if (value === ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return value;
    }
    return ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
  }

  isPageTurnAnimationEnabled(): boolean {
    return this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType) !== ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE;
  }

  saveReaderLayoutSettings(): void {
    ReaderSettingsStore.saveLayoutSettings(
      getContext(this),
      this.readerFontSize,
      this.readerLineHeight,
      this.readerParagraphSpacing,
      this.readerMarginLeft,
      this.readerMarginRight,
      this.readerMarginTop,
      this.readerMarginBottom
    ).catch((e: Error) => {
      console.warn('保存阅读排版设置失败:', e);
    });
  }

  setReaderLandscapeDoublePage(enabled: boolean): void {
    this.readerLandscapeDoublePage = enabled;
    ReaderSettingsStore.saveLandscapeDoublePage(getContext(this), enabled).catch((e: Error) => {
      console.error('保存双翻页设置失败:', e);
    });
  }

  quickTypographySettingOptions(): SelectOption[] {
    return [
      { value: '字号' },
      { value: '行距' },
      { value: '段落间距' },
      { value: '左边距' },
      { value: '右边距' },
      { value: '上边距' },
      { value: '下边距' }
    ];
  }

  quickTypographySettingTitle(): string {
    const titles: string[] = ['字号', '行距', '段落间距', '左边距', '右边距', '上边距', '下边距'];
    const index = Math.max(0, Math.min(this.quickTypographySettingIndex, titles.length - 1));
    return titles[index];
  }

  currentQuickTypographySettingValue(): number {
    switch (this.quickTypographySettingIndex) {
      case 1:
        return this.readerLineHeight;
      case 2:
        return this.readerParagraphSpacing;
      case 3:
        return this.readerMarginLeft;
      case 4:
        return this.readerMarginRight;
      case 5:
        return this.readerMarginTop;
      case 6:
        return this.readerMarginBottom;
      default:
        return this.readerFontSize;
    }
  }

  adjustQuickTypographySetting(delta: number): void {
    const next = this.currentQuickTypographySettingValue() + delta;
    switch (this.quickTypographySettingIndex) {
      case 1:
        this.applyReaderLineHeight(next);
        return;
      case 2:
        this.applyReaderParagraphSpacing(next);
        return;
      case 3:
      case 4:
      case 5:
      case 6:
        this.applyReaderMargin(this.quickTypographySettingIndex, next);
        return;
      default:
        this.applyReaderFontSize(next);
    }
  }

  openQuickTypographyValueInput(): void {
    this.quickTypographyValueDraft = '';
    this.showQuickTypographyValueInput = true;
  }

  applyQuickTypographyValueInput(): void {
    if (!this.showQuickTypographyValueInput) {
      return;
    }
    const value = Number(this.quickTypographyValueDraft);
    if (!this.quickTypographyValueDraft.trim() || !Number.isFinite(value)) {
      this.showQuickTypographyValueInput = false;
      return;
    }
    switch (this.quickTypographySettingIndex) {
      case 1:
        this.applyReaderLineHeight(value);
        break;
      case 2:
        this.applyReaderParagraphSpacing(value);
        break;
      case 3:
      case 4:
      case 5:
      case 6:
        this.applyReaderMargin(this.quickTypographySettingIndex, value);
        break;
      default:
        this.applyReaderFontSize(value);
    }
    this.showQuickTypographyValueInput = false;
  }

  applyReaderMargin(settingIndex: number, margin: number): void {
    const next = Math.max(0, Math.min(Math.round(margin), 300));
    if ((settingIndex === 3 && next === this.readerMarginLeft) ||
      (settingIndex === 4 && next === this.readerMarginRight) ||
      (settingIndex === 5 && next === this.readerMarginTop) ||
      (settingIndex === 6 && next === this.readerMarginBottom)) {
      return;
    }
    if (settingIndex === 3) {
      this.readerMarginLeft = next;
    } else if (settingIndex === 4) {
      this.readerMarginRight = next;
    } else if (settingIndex === 5) {
      this.readerMarginTop = next;
    } else {
      this.readerMarginBottom = next;
    }
    this.onReadLayoutChanged();
    this.saveReaderLayoutSettings();
    this.saveReadConfig();
  }

  applyReaderFontSize(fontSize: number): void {
    const nextFontSize = Math.max(14, Math.min(Math.round(fontSize), 50));
    if (nextFontSize === this.readerFontSize) {
      return;
    }
    this.readerFontSize = nextFontSize;
    this.onReadLayoutChanged();
    this.saveReaderLayoutSettings();
    this.saveReadConfig();
  }

  applyReaderLineHeight(lineHeight: number): void {
    const nextLineHeight = Math.max(0, Math.min(Math.round(lineHeight), 52));
    if (nextLineHeight === this.readerLineHeight) {
      return;
    }
    this.readerLineHeight = nextLineHeight;
    this.onReadLayoutChanged();
    this.saveReaderLayoutSettings();
    this.saveReadConfig();
  }

  applyReaderParagraphSpacing(paragraphSpacing: number): void {
    const nextParagraphSpacing = Math.max(0, Math.min(Math.round(paragraphSpacing), 32));
    if (nextParagraphSpacing === this.readerParagraphSpacing) {
      return;
    }
    this.readerParagraphSpacing = nextParagraphSpacing;
    this.onReadLayoutChanged();
    this.saveReaderLayoutSettings();
    this.saveReadConfig();
  }

  applyReaderThemeIndex(index: number): void {
    const nextThemeIndex = ReaderThemeHelper.normalizeIndex(index);
    if (nextThemeIndex === this.currentReaderThemeIndex()) {
      return;
    }
    if (this.appDarkMode) {
      this.readerDarkThemeIndex = nextThemeIndex;
    } else {
      this.readerLightThemeIndex = nextThemeIndex;
    }
    this.saveReaderThemeSettings();
    this.saveReadConfig();
  }

  saveReaderThemeSettings(): void {
    ReaderSettingsStore.saveThemeSettings(
      getContext(this),
      this.readerLightThemeIndex,
      this.readerDarkThemeIndex,
      this.readerLightCustomThemeBackgroundColor,
      this.readerLightCustomThemeTextColor,
      this.readerDarkCustomThemeBackgroundColor,
      this.readerDarkCustomThemeTextColor,
      this.appDarkMode,
      this.readerCustomThemesRaw
    ).catch((e: Error) => {
      console.warn('保存阅读配色设置失败:', e);
    });
  }

  setCurrentThemeBackgroundColor(color: string): void {
    const value = this.normalizeColor(color, this.currentCustomThemeBackgroundColor());
    const data = this.customThemeData();
    ReaderCustomThemeHelper.selected(data, this.appDarkMode).backgroundColor = value;
    this.persistCustomThemeData(data);
  }

  setCurrentThemeTextColor(color: string): void {
    const value = this.normalizeColor(color, this.currentCustomThemeTextColor());
    const data = this.customThemeData();
    ReaderCustomThemeHelper.selected(data, this.appDarkMode).textColor = value;
    this.persistCustomThemeData(data);
  }

  persistCustomThemeData(data: ReaderCustomThemeData): void {
    const selected = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    if (this.appDarkMode) {
      this.readerDarkCustomThemeBackgroundColor = selected.backgroundColor;
      this.readerDarkCustomThemeTextColor = selected.textColor;
    } else {
      this.readerLightCustomThemeBackgroundColor = selected.backgroundColor;
      this.readerLightCustomThemeTextColor = selected.textColor;
    }
    this.readerCustomThemesRaw = ReaderCustomThemeHelper.stringify(data);
    this.saveReaderThemeSettings();
    this.saveReadConfig();
  }

  addCustomTheme(): void {
    const data = this.customThemeData();
    const item = ReaderCustomThemeHelper.add(data, this.appDarkMode);
    this.customThemeNameDraft = item.name;
    this.persistCustomThemeData(data);
  }

  deleteCurrentCustomTheme(): void {
    const data = this.customThemeData();
    if (ReaderCustomThemeHelper.schemesForMode(data, this.appDarkMode).length <= 1) {
      promptAction.showToast({ message: '至少保留一套自定义背景' });
      return;
    }
    ReaderCustomThemeHelper.removeSelected(data, this.appDarkMode);
    this.customThemeNameDraft = ReaderCustomThemeHelper.selected(data, this.appDarkMode).name;
    this.persistCustomThemeData(data);
  }

  selectCustomTheme(index: number): void {
    const data = this.customThemeData();
    const schemes = ReaderCustomThemeHelper.schemesForMode(data, this.appDarkMode);
    if (index < 0 || index >= schemes.length) {
      return;
    }
    ReaderCustomThemeHelper.select(data, this.appDarkMode, schemes[index].id);
    this.customThemeNameDraft = schemes[index].name;
    this.persistCustomThemeData(data);
  }

  renameCurrentCustomTheme(name: string): void {
    const data = this.customThemeData();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    const value = (name || '').trim().substring(0, 20);
    if (!value) {
      this.customThemeNameDraft = current.name;
      return;
    }
    current.name = value;
    this.customThemeNameDraft = value;
    this.persistCustomThemeData(data);
  }

  async chooseCurrentCustomThemeImage(): Promise<void> {
    const data = this.customThemeData();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    try {
      const imageUri = await ReaderBackgroundImageStore.pickAndSave(getContext(this), current.id);
      if (!imageUri) {
        return;
      }
      current.backgroundImageUri = imageUri;
      current.backgroundType = 'image';
      this.persistCustomThemeData(data);
    } catch (e) {
      console.error('选择阅读背景图片失败:', e);
      promptAction.showToast({ message: '选择背景图片失败' });
    }
  }

  clearCurrentCustomThemeImage(): void {
    const data = this.customThemeData();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    current.backgroundImageUri = '';
    current.backgroundType = 'color';
    this.persistCustomThemeData(data);
  }

  setCurrentCustomThemeBackgroundType(index: number): void {
    const data = this.customThemeData();
    ReaderCustomThemeHelper.selected(data, this.appDarkMode).backgroundType = index === 1 ? 'image' : 'color';
    this.persistCustomThemeData(data);
  }

  setCurrentCustomThemeImageFit(index: number): void {
    const fits = ['cover', 'contain', 'fill'];
    const data = this.customThemeData();
    ReaderCustomThemeHelper.selected(data, this.appDarkMode).backgroundImageFit = fits[index] || 'cover';
    this.persistCustomThemeData(data);
  }

  saveReaderInteractionSettings(): void {
    ReaderSettingsStore.saveReadingInteractionSettings(
      getContext(this),
      this.readerVolumeTurnPage,
      this.readerKeepScreenOn,
      this.readerExtendToStatusBar
    ).catch((e: Error) => {
      console.error('保存阅读交互设置失败:', e);
    });
  }

  setReaderVolumeTurnPage(enabled: boolean): void {
    this.readerVolumeTurnPage = enabled;
    this.updateVolumeKeySubscription();
    this.saveReaderInteractionSettings();
    this.saveReadConfig();
  }

  setReaderExtendToStatusBar(enabled: boolean): void {
    this.readerExtendToStatusBar = enabled;
    this.enterReaderImmersive();
    this.paginateContent(this.content);
    this.saveReaderInteractionSettings();
    this.saveReadingProgress();
    this.saveReadConfig();
  }

  setReaderPreloadEnabled(enabled: boolean): void {
    this.readerPreloadEnabled = enabled;
    ReaderSettingsStore.savePreloadEnabled(getContext(this), enabled).catch((e: Error) => {
      console.error('保存预缓存开关失败:', e);
    });
    if (enabled) {
      this.preloadReaderContentLater();
    }
    this.saveReadConfig();
  }

  setReaderPreloadChapterCount(count: number): void {
    const value = Math.max(1, Math.min(Math.round(count), 10));
    this.readerPreloadChapterCount = value;
    ReaderSettingsStore.savePreloadChapterCount(getContext(this), value).catch((e: Error) => {
      console.error('保存预缓存章节数失败:', e);
    });
    this.preloadReaderContentLater();
    this.saveReadConfig();
  }

  async toggleTtsReading(): Promise<void> {
    if (this.isTtsSpeaking) {
      this.stopTtsReading();
      promptAction.showToast({ message: '已停止朗读' });
      return;
    }
    this.ttsMediaControlsExpanded = true;
    await this.startTtsReadingFromCurrentPosition(true);
  }

  async startTtsReadingFromCurrentPosition(showToast: boolean): Promise<void> {
    const text = this.getTtsReadingText();
    if (!text) {
      this.finishTtsReading();
      if (showToast) {
        promptAction.showToast({ message: '当前没有可朗读内容' });
      }
      return;
    }
    const token = ++this.ttsReadToken;
    this.ttsAutoContinue = true;
    this.ttsDisplayText = this.currentPageText;
    this.ttsHighlightStart = -1;
    this.ttsHighlightEnd = -1;
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
    try {
      this.isTtsSpeaking = true;
      this.preloadReaderContent();
      const backgroundStarted = await this.startTtsBackgroundRunning();
      if (!backgroundStarted && showToast) {
        promptAction.showToast({ message: '后台朗读任务启动失败，息屏后可能中断' });
      }
      if (token !== this.ttsReadToken || !this.ttsAutoContinue) {
        this.stopTtsReading(false);
        return;
      }
      await this.ttsReader.start(text, {
        onFinished: () => {
          this.continueTtsReading(token).catch((e: Error) => {
            console.warn('连续朗读续播失败:', e);
            if (token === this.ttsReadToken) {
              this.finishTtsReading();
            }
          });
        },
        onError: (message: string) => {
          if (token !== this.ttsReadToken) {
            return;
          }
          this.finishTtsReading();
          promptAction.showToast({ message: message || '系统朗读失败' });
        },
        onChunkStart: (chunk: TtsChunk) => {
          if (token !== this.ttsReadToken) {
            return;
          }
          this.followTtsChunk(chunk);
        },
        onAudioStart: () => {
          if (token !== this.ttsReadToken) {
            return;
          }
          this.onTtsAudioStarted();
        }
      });
      if (showToast) {
        promptAction.showToast({ message: '开始连续朗读' });
      }
    } catch (error) {
      if (token !== this.ttsReadToken) {
        return;
      }
      this.finishTtsReading();
      promptAction.showToast({ message: '当前系统不支持朗读或 TTS 初始化失败' });
      console.error('启动系统 TTS 失败:', error);
    }
  }

  stopTtsReading(userCancelled: boolean = true): void {
    this.clearTtsSleepTimer();
    if (userCancelled) {
      this.ttsAutoContinue = false;
      this.ttsReadToken++;
    }
    this.ttsAutoTurningPage = false;
    this.ttsPendingTargetPageIndex = -1;
    this.ttsPendingHighlightChunk = null;
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
    this.ttsMediaControlsExpanded = false;
    this.ttsPageTurnSerial++;
    this.stopTtsBackgroundRunning();
    if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking()) {
      this.clearTtsHighlight();
      return;
    }
    this.ttsReader.stop();
    this.isTtsSpeaking = false;
    this.ttsPageTurnSerial++;
    this.clearTtsHighlight();
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
  }

  stopTtsReaderForChapterSwitch(): void {
    this.ttsAutoContinue = false;
    this.ttsReadToken++;
    this.ttsAutoTurningPage = false;
    this.ttsPendingTargetPageIndex = -1;
    this.ttsPendingHighlightChunk = null;
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
    this.ttsPageTurnSerial++;
    this.ttsReader.stop();
    this.isTtsSpeaking = false;
    this.clearTtsHighlight();
  }

  async continueTtsReading(token: number): Promise<void> {
    if (token !== this.ttsReadToken || !this.ttsAutoContinue) {
      return;
    }
    const advanced = await this.advanceTtsReadingToNextChapter();
    if (token !== this.ttsReadToken || !this.ttsAutoContinue) {
      return;
    }
    if (!advanced) {
      this.finishTtsReading();
      return;
    }
    await this.startTtsReadingFromCurrentPosition(false);
  }

  async advanceTtsReadingToNextChapter(): Promise<boolean> {
    if (this.chapters.length === 0 || this.currentChapterIndex >= this.chapters.length - 1) {
      return false;
    }
    this.ttsAutoTurningPage = false;
    this.ttsPendingTargetPageIndex = -1;
    this.ttsPendingHighlightChunk = null;
    this.ttsPageTurnSerial++;
    this.currentPageIndex = 0;
    this.pendingRestorePageIndex = 0;
    await this.loadContent(true, this.currentChapterIndex + 1);
    await this.saveReadingProgress();
    await this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
    return true;
  }

  async advanceTtsReadingTarget(): Promise<boolean> {
    if (this.chapters.length === 0) {
      return false;
    }
    if (this.canTurnPage(1)) {
      await this.runTtsPageTurnAnimation(1);
      return true;
    }
    return false;
  }

  finishTtsReading(): void {
    this.clearTtsSleepTimer();
    this.ttsAutoContinue = false;
    this.isTtsSpeaking = false;
    this.ttsMediaControlsExpanded = false;
    this.ttsReader.stop();
    this.stopTtsBackgroundRunning();
    this.ttsPageTurnSerial++;
    this.clearTtsHighlight();
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
  }

  async loadReaderSettings(): Promise<void> {
    try {
      const settings = await ReaderSettingsStore.load(getContext(this));
      ReaderSettingsStore.applyToStorage(settings);
      this.applyLoadedReaderSettings(settings);
      const registered = await this.registerReaderFontBySettings(
        settings.fontFamily,
        settings.fontFilePath,
        settings.fontSourceName
      );
      if (registered || !this.readerFontFilePath) {
        this.refreshReaderTextRender();
      }
      this.paginateContent(this.content);
    } catch (e) {
      console.warn('读取阅读设置失败:', e);
    }
  }

  async startTtsBackgroundRunning(): Promise<boolean> {
    this.ttsBackgroundDesired = true;
    if (this.ttsBackgroundRunning) {
      await this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
      this.startTtsBackgroundHeartbeat();
      return true;
    }
    if (this.ttsBackgroundRequesting) {
      return this.ttsBackgroundRunning;
    }
    this.ttsBackgroundRequesting = true;
    try {
      const agent = await this.createTtsBackgroundWantAgent();
      await this.startTtsAvSession(agent);
      await backgroundTaskManager.startBackgroundRunning(
        getContext(this),
        ['audioPlayback'],
        agent
      );
      if (this.ttsBackgroundDesired) {
        this.ttsBackgroundRunning = true;
        this.startTtsBackgroundHeartbeat();
        console.info(`[TTS-BG] background audio task started: ${this.ttsBackgroundDebugState()}`);
      } else {
        await backgroundTaskManager.stopBackgroundRunning(getContext(this));
      }
      return this.ttsBackgroundRunning;
    } catch (error) {
      this.ttsBackgroundRunning = false;
      this.stopTtsBackgroundHeartbeat();
      console.warn(`[TTS-BG] start background audio task failed: ${this.formatTtsBackgroundError(error as Object)}; ${this.ttsBackgroundDebugState()}`, error);
      return false;
    } finally {
      this.ttsBackgroundRequesting = false;
    }
  }

  async stopTtsBackgroundRunning(): Promise<void> {
    this.ttsBackgroundDesired = false;
    this.stopTtsBackgroundHeartbeat();
    await this.stopTtsAvSession();
    if (!this.ttsBackgroundRunning && !this.ttsBackgroundRequesting) {
      return;
    }
    if (this.ttsBackgroundRequesting && !this.ttsBackgroundRunning) {
      return;
    }
    this.ttsBackgroundRunning = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(getContext(this));
      console.info(`[TTS-BG] background audio task stopped: ${this.ttsBackgroundDebugState()}`);
    } catch (error) {
      console.warn(`[TTS-BG] stop background audio task failed: ${this.formatTtsBackgroundError(error as Object)}; ${this.ttsBackgroundDebugState()}`, error);
    }
  }

  startTtsBackgroundHeartbeat(): void {
    if (this.ttsBackgroundHeartbeatId >= 0) {
      return;
    }
    this.ttsBackgroundHeartbeatId = setInterval(() => {
      this.keepTtsBackgroundAlive().catch((error: Error) => {
        console.warn(`[TTS-BG] heartbeat failed: ${this.formatTtsBackgroundError(error as Object)}; ${this.ttsBackgroundDebugState()}`, error);
      });
    }, 30000);
  }

  stopTtsBackgroundHeartbeat(): void {
    if (this.ttsBackgroundHeartbeatId < 0) {
      return;
    }
    clearInterval(this.ttsBackgroundHeartbeatId);
    this.ttsBackgroundHeartbeatId = -1;
  }

  async keepTtsBackgroundAlive(): Promise<void> {
    if (!this.ttsBackgroundDesired || (!this.isTtsSpeaking && !this.ttsReader.isSpeaking())) {
      this.stopTtsBackgroundHeartbeat();
      return;
    }
    if (!this.ttsBackgroundRunning && !this.ttsBackgroundRequesting) {
      await this.startTtsBackgroundRunning();
      return;
    }
    await this.syncTtsSystemMediaControls();
    const now = Date.now();
    if (now - this.ttsBackgroundLastLogAt >= 120000) {
      this.ttsBackgroundLastLogAt = now;
      console.info(`[TTS-BG] heartbeat: ${this.ttsBackgroundDebugState()}`);
    }
  }

  onTtsAudioStarted(): void {
    console.info(`[TTS-BG] audio started: ${this.ttsBackgroundDebugState()}`);
    this.refreshTtsBackgroundAfterAudioStarted().catch((error: Error) => {
      console.warn(`[TTS-BG] refresh after audio started failed: ${this.formatTtsBackgroundError(error as Object)}; ${this.ttsBackgroundDebugState()}`, error);
    });
  }

  async refreshTtsBackgroundAfterAudioStarted(): Promise<void> {
    if (!this.ttsBackgroundRunning && !this.ttsBackgroundRequesting) {
      await this.startTtsBackgroundRunning();
      return;
    }
    await this.syncTtsSystemMediaControls();
  }

  async startTtsAvSession(agent: WantAgent): Promise<void> {
    if (this.ttsAvSessionRequesting) {
      return;
    }
    this.ttsAvSessionRequesting = true;
    try {
      if (!this.ttsAvSession) {
        this.ttsAvSession = await avSession.createAVSession(getContext(this), 'LegadoReaderTts', 'audio');
        this.registerTtsAvSessionCommands(this.ttsAvSession);
      }
      await this.ttsAvSession.setLaunchAbility(agent);
      await this.ttsAvSession.setAVQueueTitle(this.book?.name || '听书');
      await this.refreshTtsMediaImage();
      await this.ttsAvSession.setAVMetadata(this.getTtsAvMetadata());
      await this.ttsAvSession.setExtras({
        bookUrl: this.bookUrl || '',
        chapterIndex: this.currentChapterIndex,
        chapterTitle: this.getChapterTitle()
      });
      await this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
      await this.ttsAvSession.activate();
      await this.syncTtsSystemMediaControls();
      console.info(`[TTS-BG] AVSession activated: ${this.ttsBackgroundDebugState()}`);
    } catch (error) {
      console.warn(`[TTS-BG] start AVSession failed: ${this.formatTtsBackgroundError(error as Object)}; ${this.ttsBackgroundDebugState()}`, error);
    } finally {
      this.ttsAvSessionRequesting = false;
    }
  }

  registerTtsAvSessionCommands(session: avSession.AVSession): void {
    session.on('play', () => {
      if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking()) {
        this.startTtsReadingFromCurrentPosition(false);
      }
    });
    session.on('pause', () => {
      this.stopTtsReading();
    });
    session.on('stop', () => {
      this.stopTtsReading();
    });
    session.on('playNext', () => {
      this.playNextChapterFromMediaSession();
    });
    session.on('playPrevious', () => {
      this.playPreviousChapterFromMediaSession();
    });
    session.on('setSpeed', (speed: number) => {
      this.applyTtsSpeed(speed);
    });
  }

  async playNextChapterFromMediaSession(): Promise<void> {
    if (!this.canPlayNextTtsChapter()) {
      return;
    }
    const shouldResume = this.isTtsSpeaking || this.ttsReader.isSpeaking();
    if (shouldResume) {
      this.stopTtsReaderForChapterSwitch();
      await this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING);
    } else {
      this.stopTtsReading();
    }
    await this.loadNextChapter();
    if (shouldResume) {
      await this.startTtsReadingFromCurrentPosition(false);
    } else {
      await this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP);
    }
  }

  async playPreviousChapterFromMediaSession(): Promise<void> {
    if (!this.canPlayPreviousTtsChapter()) {
      return;
    }
    const shouldResume = this.isTtsSpeaking || this.ttsReader.isSpeaking();
    if (shouldResume) {
      this.stopTtsReaderForChapterSwitch();
      await this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING);
    } else {
      this.stopTtsReading();
    }
    await this.loadPrevChapter();
    if (shouldResume) {
      await this.startTtsReadingFromCurrentPosition(false);
    } else {
      await this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP);
    }
  }

  async updateTtsAvSessionPlaybackState(state: avSession.PlaybackState): Promise<void> {
    if (!this.ttsAvSession) {
      return;
    }
    try {
      await this.refreshTtsMediaImage();
      await this.ttsAvSession.setAVMetadata(this.getTtsAvMetadata());
      await this.ttsAvSession.setAVPlaybackState({
        state: state,
        speed: AppStorage.get<number>('ttsSpeed') || 1,
        position: {
          elapsedTime: this.getTtsPlaybackElapsedTime(),
          updateTime: Date.now()
        },
        bufferedTime: this.getTtsPlaybackDuration(),
        loopMode: avSession.LoopMode.LOOP_MODE_SEQUENCE,
        activeItemId: this.currentChapterIndex
      });
      if (state === avSession.PlaybackState.PLAYBACK_STATE_PLAY ||
        state === avSession.PlaybackState.PLAYBACK_STATE_BUFFERING) {
        await this.ttsAvSession.activate();
      }
    } catch (error) {
      console.warn(`[TTS-BG] update AVSession playback state failed: ${this.formatTtsBackgroundError(error as Object)}; ${this.ttsBackgroundDebugState()}`, error);
    }
  }

  async syncTtsSystemMediaControls(): Promise<void> {
    if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking()) {
      return;
    }
    try {
      if (!this.ttsAvSession) {
        await this.startTtsBackgroundRunning();
        return;
      }
      await this.ttsAvSession.activate();
      await this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
    } catch (error) {
      console.warn(`[TTS-BG] sync media controls failed: ${this.formatTtsBackgroundError(error as Object)}; ${this.ttsBackgroundDebugState()}`, error);
    }
  }

  getTtsAvMetadata(): avSession.AVMetadata {
    const metadata: avSession.AVMetadata = {
      assetId: this.getTtsAvAssetId(),
      title: this.book?.name || '朗读',
      subtitle: this.getTtsAvSubtitle(),
      artist: this.book?.author || '阅读',
      author: this.book?.author || '阅读',
      album: this.book?.name || '听书',
      duration: this.getTtsPlaybackDuration(),
      previousAssetId: this.canPlayPreviousTtsChapter() ? this.getTtsChapterAssetId(this.currentChapterIndex - 1) : '',
      nextAssetId: this.canPlayNextTtsChapter() ? this.getTtsChapterAssetId(this.currentChapterIndex + 1) : '',
      avQueueName: this.book?.name || '听书',
      avQueueId: this.bookUrl || 'reader_tts'
    };
    if (this.ttsMediaPixelMap) {
      metadata.mediaImage = this.ttsMediaPixelMap;
      metadata.avQueueImage = this.ttsMediaPixelMap;
    } else if (this.ttsMediaImage) {
      metadata.mediaImage = this.ttsMediaImage;
      metadata.avQueueImage = this.ttsMediaImage;
    }
    return metadata;
  }

  async refreshTtsMediaImage(): Promise<void> {
    const serial = ++this.ttsMediaImageRefreshSerial;
    const raw = this.getBookshelfDisplayCoverRaw();
    if (raw && raw === this.ttsMediaImageRaw && this.ttsMediaPixelMap) {
      return;
    }
    if (!raw) {
      if (serial === this.ttsMediaImageRefreshSerial) {
        this.ttsMediaImage = '';
        this.ttsMediaImageRaw = '';
        this.releaseTtsMediaPixelMap();
      }
      return;
    }
    let resolved = raw;
    let pixelMap: image.PixelMap | null = null;
    try {
      const context = getContext(this);
      const coverPath = await BookCoverCache.prepareCoverFile(context, raw);
      if (coverPath) {
        pixelMap = await this.createTtsMediaPixelMap(coverPath);
        resolved = pixelMap ? coverPath : await BookCoverCache.resolveCover(context, raw);
      } else {
        resolved = await BookCoverCache.resolveCover(context, raw);
      }
    } catch (error) {
      console.warn('解析朗读媒体封面失败:', error);
    }
    if (serial === this.ttsMediaImageRefreshSerial) {
      this.releaseTtsMediaPixelMap();
      this.ttsMediaImage = resolved || raw;
      this.ttsMediaImageRaw = raw;
      this.ttsMediaPixelMap = pixelMap;
    } else if (pixelMap) {
      pixelMap.release().catch((e: Error) => {
        console.warn('释放过期朗读媒体封面失败:', e);
      });
    }
  }

  async createTtsMediaPixelMap(path: string): Promise<image.PixelMap | null> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      return await source.createPixelMap({
        desiredSize: {
          width: 512,
          height: 512
        }
      });
    } catch (error) {
      console.warn('创建朗读媒体封面 PixelMap 失败:', error);
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

  releaseTtsMediaPixelMap(): void {
    if (!this.ttsMediaPixelMap) {
      return;
    }
    try {
      this.ttsMediaPixelMap.release().catch((e: Error) => {
        console.warn('释放朗读媒体封面失败:', e);
      });
    } catch (e) {
      console.warn('释放朗读媒体封面失败:', e);
    }
    this.ttsMediaPixelMap = null;
  }

  getBookshelfDisplayCoverRaw(): string {
    if (!this.book) {
      return '';
    }
    const albumCover = this.getTtsGalleryCoverRaw();
    if (albumCover) {
      return albumCover;
    }
    const covers = CoverGallerySettings.getDisplayCoverList(
      this.book,
      this.appDarkMode,
      this.bookshelfCoverAlbums,
      this.bookshelfLightCoverAlbumId,
      this.bookshelfDarkCoverAlbumId,
      this.bookshelfCoverApplyScope,
      this.bookshelfCoverTargetBooks,
      this.bookshelfIgnoreSourceCover,
      this.bookshelfCoverMode
    );
    return this.pickStableTtsCover(covers);
  }

  getTtsGalleryCoverRaw(): string {
    if (!this.book) {
      return '';
    }
    if (this.bookshelfCoverApplyScope === 'books' &&
      !CoverGallerySettings.parseTargetBooks(this.bookshelfCoverTargetBooks).includes(this.book.bookUrl)) {
      return '';
    }
    const albumId = CoverGallerySettings.selectedAlbumId(
      this.appDarkMode,
      this.bookshelfLightCoverAlbumId,
      this.bookshelfDarkCoverAlbumId
    );
    const album = CoverGallerySettings.getAlbum(CoverGallerySettings.parseAlbums(this.bookshelfCoverAlbums), albumId);
    return album ? this.pickStableTtsCover(album.covers) : '';
  }

  pickStableTtsCover(covers: string[]): string {
    const cleaned: string[] = [];
    for (const cover of covers) {
      const value = (cover || '').trim();
      if (value && !cleaned.includes(value)) {
        cleaned.push(value);
      }
    }
    if (cleaned.length === 0) {
      return '';
    }
    if (cleaned.length === 1) {
      return cleaned[0];
    }
    const seed = `${this.bookUrl || this.book?.bookUrl || ''}_${this.book?.name || ''}_` +
      `${this.appDarkMode}_${this.bookshelfLightCoverAlbumId}_${this.bookshelfDarkCoverAlbumId}_` +
      `${this.bookshelfCoverMode}`;
    return cleaned[Math.abs(this.hashTtsText(seed)) % cleaned.length];
  }

  hashTtsText(value: string): number {
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = value.charCodeAt(i) + ((hash << 5) - hash);
    }
    return hash;
  }

  getTtsPlaybackElapsedTime(): number {
    const pageCount = Math.max(this.contentPages.length, 1);
    const clampedPageIndex = Math.max(0, Math.min(this.currentPageIndex, pageCount - 1));
    return Math.round((clampedPageIndex / pageCount) * this.getTtsPlaybackDuration());
  }

  getTtsPlaybackDuration(): number {
    const charCount = Math.max((this.content || this.currentPageText || '').length, 1);
    const charsPerMinute = 260 * Math.max(this.ttsSpeed || 1, 0.5);
    return Math.max(60000, Math.round((charCount / charsPerMinute) * 60000));
  }

  getTtsAvAssetId(): string {
    return `${this.getTtsChapterAssetId(this.currentChapterIndex)}_${this.currentPageIndex}_${this.getTtsMediaImageIdentity()}`;
  }

  getTtsChapterAssetId(chapterIndex: number): string {
    return `${this.bookUrl || 'reader_tts'}_${chapterIndex}`;
  }

  getTtsMediaImageIdentity(): string {
    const value = this.ttsMediaImageRaw || this.ttsMediaImage || 'cover';
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = value.charCodeAt(i) + ((hash << 5) - hash);
    }
    return Math.abs(hash).toString(16);
  }

  getTtsAvSubtitle(): string {
    const progress = this.getProgressText();
    const chapter = this.getChapterTitle();
    return progress ? `${chapter} · ${progress}` : chapter;
  }

  async stopTtsAvSession(): Promise<void> {
    if (!this.ttsAvSession) {
      return;
    }
    const session = this.ttsAvSession;
    this.ttsAvSession = null;
    try {
      await session.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_STOP
      });
      await session.deactivate();
      await session.destroy();
      console.info('[TTS-BG] AVSession destroyed');
    } catch (error) {
      console.warn(`[TTS-BG] stop AVSession failed: ${this.formatTtsBackgroundError(error as Object)}`, error);
    } finally {
      this.ttsMediaImage = '';
      this.ttsMediaImageRaw = '';
      this.releaseTtsMediaPixelMap();
    }
  }

  async createTtsBackgroundWantAgent(): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility'
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1001,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  ttsBackgroundDebugState(): string {
    return `desired=${this.ttsBackgroundDesired},running=${this.ttsBackgroundRunning},requesting=${this.ttsBackgroundRequesting},speaking=${this.isTtsSpeaking},readerSpeaking=${this.ttsReader.isSpeaking()},avSession=${this.ttsAvSession ? 'yes' : 'no'},audio=${this.ttsReader.audioDebugState()}`;
  }

  formatTtsBackgroundError(error: Object | null | undefined): string {
    if (!error) {
      return 'unknown';
    }
    const record = error as Record<string, Object>;
    const code = record['code'];
    const message = record['message'];
    const parts: string[] = [];
    if (code !== undefined) {
      parts.push(`code=${String(code)}`);
    }
    if (message !== undefined) {
      parts.push(`message=${String(message)}`);
    }
    return parts.length > 0 ? parts.join(',') : String(error);
  }

  clearTtsHighlight(): void {
    this.ttsDisplayText = '';
    this.ttsHighlightStart = -1;
    this.ttsHighlightEnd = -1;
    this.ttsTextStartOffset = 0;
    this.ttsHighlightRenderVersion++;
    this.chapterJumpRenderGeneration++;
    this.pageRenderVersion++;
  }

  getTtsReadingText(): string {
    const start = this.getCurrentPageStartOffset();
    this.ttsTextStartOffset = start;
    const source = this.pagedContentText || this.getPagedSourceText();
    return source.substring(start);
  }

  normalizeReaderText(text: string): string {
    return this.trimReaderContentText((text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\u00A0/g, ' ')
      .replace(/\n{3,}/g, '\n\n'));
  }

  getPagedSourceText(): string {
    return this.buildPagedSourceText(this.currentChapterIndex, this.content || '');
  }

  buildPagedSourceText(chapterIndex: number, content: string): string {
    const title = this.getChapterTitle(chapterIndex).trim();
    const sourceBody = this.stripDuplicatedChapterTitle(this.normalizeChapterBody(content || ''), title);
    const body = this.buildIndentedChapterBody(sourceBody);
    if (!title) {
      return body;
    }
    return `${title}\n\n${body}`;
  }

  normalizeChapterBody(text: string): string {
    return this.mergeSoftWrappedChapterLines(this.trimReaderContentText((text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\u00A0/g, ' ')
      .replace(/\n{3,}/g, '\n\n')));
  }

  mergeSoftWrappedChapterLines(text: string): string {
    if (!text || text.indexOf('\n') < 0) {
      return text;
    }
    const rawLines = text.split('\n');
    const result: string[] = [];
    let current = '';
    for (const rawLine of rawLines) {
      const line = rawLine.trim();
      if (!line) {
        if (current) {
          result.push(current);
          current = '';
        }
        if (result.length > 0 && result[result.length - 1] !== '') {
          result.push('');
        }
        continue;
      }
      if (!current) {
        current = line;
        continue;
      }
      if (this.shouldMergeReaderSoftLine(current, rawLine)) {
        current += line;
      } else {
        result.push(current);
        current = line;
      }
    }
    if (current) {
      result.push(current);
    }
    return result.join('\n').replace(/\n{3,}/g, '\n\n').trim();
  }

  shouldMergeReaderSoftLine(previous: string, nextRaw: string): boolean {
    const prev = (previous || '').trim();
    const next = (nextRaw || '').trim();
    if (!prev || !next) {
      return false;
    }
    if (/^[　\s]/.test(nextRaw)) {
      return false;
    }
    if (/^[第卷章节回番外序楔引]\s*[\d一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾]/.test(next)) {
      return false;
    }
    if (/^[，,。！？!?；;：:、」』”）)]/.test(next)) {
      return true;
    }
    if (/[。！？!?；;」』”）)]$/.test(prev)) {
      return false;
    }
    return prev.length < 48 && next.length < 48;
  }

  buildIndentedChapterBody(text: string): string {
    const normalized = this.normalizeChapterBody(text);
    if (!normalized) {
      return '';
    }
    return normalized
      .split('\n')
      .map((line: string) => this.indentReaderLine(line))
      .join('\n');
  }

  indentReaderLine(line: string): string {
    if (!line || line.trim().length === 0) {
      return line;
    }
    if (line.startsWith('　　')) {
      return line;
    }
    return `　　${line.replace(/^[　\s]+/g, '')}`;
  }

  stripDuplicatedChapterTitle(body: string, title: string): string {
    if (!body || !title) {
      return body;
    }
    const lines = body.split('\n');
    const firstLine = (lines[0] || '').replace(/^[　\s]+/g, '').trim();
    if (firstLine !== title) {
      return body;
    }
    return this.trimReaderContentText(lines.slice(1).join('\n').replace(/^\n+/, ''));
  }

  isReaderTrimChar(value: string): boolean {
    return value === ' ' || value === '\t' || value === '\n' || value === '\r' ||
      value === '\u00A0' || value === '\uFEFF' || value === '\u200B' ||
      value === '\u200C' || value === '\u200D' || value === '\u2060';
  }

  isReaderEdgeTrimChar(value: string): boolean {
    return this.isReaderTrimChar(value) || value === '\u3000';
  }

  trimReaderContentText(text: string): string {
    const source = text || '';
    let start = 0;
    let end = source.length;
    while (start < end && this.isReaderEdgeTrimChar(source.charAt(start))) {
      start++;
    }
    while (end > start && this.isReaderEdgeTrimChar(source.charAt(end - 1))) {
      end--;
    }
    return source.substring(start, end);
  }

  pushReaderPage(source: string, rawStart: number, rawEnd: number, pages: string[], starts: number[], ends: number[]): void {
    let pageStart = Math.max(0, Math.min(rawStart, source.length));
    let pageEnd = Math.max(pageStart, Math.min(rawEnd, source.length));
    while (pageStart < pageEnd && this.isReaderTrimChar(source.charAt(pageStart))) {
      pageStart++;
    }
    while (pageEnd > pageStart && this.isReaderTrimChar(source.charAt(pageEnd - 1))) {
      pageEnd--;
    }
    const pageText = source.substring(pageStart, pageEnd);
    if (!pageText) {
      return;
    }
    pages.push(pageText);
    starts.push(pageStart);
    ends.push(pageEnd);
  }

  findMeasuredPageEnd(source: string, start: number, availableWidth: number, availableHeight: number,
    chapterIndex: number = this.currentChapterIndex): number {
    let safeStart = Math.max(0, Math.min(start, source.length));
    while (safeStart < source.length && this.isReaderTrimChar(source.charAt(safeStart))) {
      safeStart++;
    }
    if (safeStart >= source.length) {
      return source.length;
    }

    const paragraphEnd = this.findParagraphLayoutPageEnd(source, safeStart, availableWidth, availableHeight,
      chapterIndex);
    if (paragraphEnd > safeStart) {
      return this.refineMeasuredPageEnd(source, safeStart, paragraphEnd, availableWidth, availableHeight,
        chapterIndex);
    }

    let low = safeStart + 1;
    let high = source.length;
    let best = low;
    while (low <= high) {
      const mid = Math.floor((low + high) / 2);
      const candidate = source.substring(safeStart, mid);
      if (this.measureReaderTextHeight(candidate, availableWidth, chapterIndex) <= availableHeight) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    const end = this.chooseReaderPageBreak(source, safeStart, best);
    return Math.max(safeStart + 1, end);
  }

  refineMeasuredPageEnd(source: string, start: number, initialEnd: number, availableWidth: number,
    availableHeight: number, chapterIndex: number = this.currentChapterIndex): number {
    let best = Math.max(start + 1, Math.min(initialEnd, source.length));
    if (best >= source.length) {
      return source.length;
    }
    if (!this.doesMeasuredReaderPageFit(source, start, best, availableWidth, availableHeight, chapterIndex)) {
      return best;
    }

    let step = Math.max(16, Math.min(512, best - start));
    let upper = Math.min(source.length, best + step);
    while (upper < source.length &&
      this.doesMeasuredReaderPageFit(source, start, upper, availableWidth, availableHeight, chapterIndex)) {
      best = upper;
      step = Math.min(step * 2, 4096);
      upper = Math.min(source.length, best + step);
    }
    if (upper === source.length &&
      this.doesMeasuredReaderPageFit(source, start, upper, availableWidth, availableHeight, chapterIndex)) {
      return source.length;
    }

    let low = best + 1;
    let high = Math.max(low, upper - 1);
    while (low <= high) {
      const mid = Math.floor((low + high) / 2);
      if (this.doesMeasuredReaderPageFit(source, start, mid, availableWidth, availableHeight, chapterIndex)) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    const end = this.chooseReaderPageBreak(source, start, best);
    return Math.max(start + 1, end);
  }

  doesMeasuredReaderPageFit(source: string, start: number, end: number, availableWidth: number,
    availableHeight: number, chapterIndex: number = this.currentChapterIndex): boolean {
    const safeEnd = Math.max(start + 1, Math.min(end, source.length));
    return this.measureReaderTextHeight(source.substring(start, safeEnd), availableWidth, chapterIndex) <=
      availableHeight;
  }

  findParagraphLayoutPageEnd(source: string, start: number, availableWidth: number, availableHeight: number,
    chapterIndex: number = this.currentChapterIndex): number {
    const windowEnd = Math.min(source.length, start + this.getReaderLayoutWindowSize(availableWidth, availableHeight));
    const layoutText = source.substring(start, windowEnd);
    if (!layoutText) {
      return -1;
    }
    if (this.readerParagraphSpacing > 0 && /\n/.test(layoutText)) {
      return -1;
    }

    try {
      const paragraph = this.buildMeasuredReaderParagraph(layoutText, availableWidth, chapterIndex);
      const metrics = paragraph.getLineMetrics();
      if (metrics.length === 0) {
        return -1;
      }

      const safeHeight = Math.max(1, availableHeight - 1);
      const lineHeightPx = this.toMeasurePx(this.getEffectiveReaderLineHeight());
      let end = -1;
      for (let i = 0; i < metrics.length; i++) {
        const metric = metrics[i];
        if ((i + 1) * lineHeightPx > safeHeight) {
          break;
        }
        end = Math.max(end, metric.endIndex);
      }

      if (end <= 0) {
        const firstRange = paragraph.getActualTextRange(0, true);
        end = Math.max(1, firstRange.end);
      }
      if (end >= layoutText.length && windowEnd < source.length) {
        return -1;
      }
      return Math.max(start + 1, Math.min(source.length, start + end));
    } catch (error) {
      console.error('官方段落布局分页失败，回退到文本测量分页:', error);
      return -1;
    }
  }

  getReaderLayoutWindowSize(availableWidth: number, availableHeight: number): number {
    const charsPerLine = Math.max(8, Math.floor(availableWidth / Math.max(1, this.readerFontSize * 0.95)));
    const visibleLines = Math.max(1, Math.ceil(availableHeight / this.getEffectiveReaderLineHeight()));
    return Math.min(12000, Math.max(800, charsPerLine * (visibleLines + 6) * 2));
  }

  getReaderPaginationHeightTolerancePx(): number {
    return 1;
  }

  getReaderTextParagraphs(text: string): ReaderTextParagraph[] {
    const source = (text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n');
    const paragraphs: ReaderTextParagraph[] = [];
    const separatorRegex = /\n+/g;
    let start = 0;
    let index = 0;
    let match = separatorRegex.exec(source);
    while (match) {
      if (match.index > start) {
        const paragraphText = source.substring(start, match.index);
        paragraphs.push({
          text: paragraphText,
          start: start,
          end: match.index,
          index: index,
          isLast: false,
          key: `paragraph_${index}_${start}_${match.index}_${this.buildTextSliceKey(paragraphText)}`
        });
        index++;
      }
      start = match.index + match[0].length;
      match = separatorRegex.exec(source);
    }
    if (start < source.length) {
      const paragraphText = source.substring(start);
      paragraphs.push({
        text: paragraphText,
        start: start,
        end: source.length,
        index: index,
        isLast: false,
        key: `paragraph_${index}_${start}_${source.length}_${this.buildTextSliceKey(paragraphText)}`
      });
    }
    if (paragraphs.length === 0) {
      paragraphs.push({
        text: source,
        start: 0,
        end: source.length,
        index: 0,
        isLast: true,
        key: `paragraph_empty_${this.buildTextSliceKey(source)}`
      });
      return paragraphs;
    }
    const lastIndex = paragraphs.length - 1;
    for (let i = 0; i < paragraphs.length; i++) {
      paragraphs[i].isLast = i === lastIndex;
      paragraphs[i].index = i;
    }
    return paragraphs;
  }

  measureReaderTextHeight(text: string, availableWidth: number,
    chapterIndex: number = this.currentChapterIndex): number {
    if (!text) {
      return 0;
    }
    const paragraphs = this.getReaderTextParagraphs(text);
    if (paragraphs.length > 1) {
      let totalHeight = 0;
      for (const paragraph of paragraphs) {
        totalHeight += this.measureReaderSingleParagraphHeight(paragraph.text, availableWidth, chapterIndex);
        if (!paragraph.isLast) {
          totalHeight += this.toMeasurePx(this.readerParagraphSpacing);
        }
      }
      return totalHeight;
    }
    return this.measureReaderSingleParagraphHeight(text, availableWidth, chapterIndex);
  }

  measureReaderSingleParagraphHeight(text: string, availableWidth: number,
    chapterIndex: number = this.currentChapterIndex): number {
    if (!text) {
      return 0;
    }
    try {
      const paragraph = this.buildMeasuredReaderParagraph(text, availableWidth, chapterIndex);
      const metrics = paragraph.getLineMetrics();
      if (metrics.length > 0) {
        const height = this.toMeasurePx(metrics.length * this.getEffectiveReaderLineHeight());
        if (height > 0) {
          return height;
        }
      }
    } catch (error) {
      console.error('官方段落布局测量阅读文本高度失败，回退到组件测量:', error);
    }
    const fallbackStyle = this.getParagraphFallbackMeasureStyle(text, chapterIndex);
    const options: MeasureOptions = {
        textContent: text,
        constraintWidth: Math.max(1, availableWidth),
        fontSize: fallbackStyle.fontSize,
        fontFamily: fallbackStyle.fontFamily,
        lineHeight: this.getEffectiveReaderLineHeight(),
      fontWeight: FontWeight.Normal,
      textAlign: TextAlign.JUSTIFY,
      wordBreak: WordBreak.BREAK_ALL
    };
    try {
      const size = this.getUIContext().getMeasureUtils().measureTextSize(options);
      const height = Number(size.height);
      if (height > 0) {
        return height;
      }
    } catch (error) {
      console.error('测量阅读文本高度失败:', error);
    }
    const charsPerLine = Math.max(8, Math.floor(availableWidth / Math.max(1, this.readerFontSize * 1.08)));
    const lines = Math.max(1, Math.ceil(text.length / charsPerLine));
    return this.toMeasurePx(lines * this.getEffectiveReaderLineHeight());
  }

  buildReaderMeasureTextStyle(fontSize: number, fontFamily: string): graphicsText.TextStyle {
    const lineHeightPx = this.toMeasurePx(this.getEffectiveReaderLineHeight());
    return {
      fontSize: this.toMeasurePx(fontSize),
      fontFamilies: [fontFamily || this.getBodyReaderFontFamily()],
      fontWeight: graphicsText.FontWeight.W400,
      lineHeightMinimum: lineHeightPx,
      lineHeightMaximum: lineHeightPx,
      halfLeading: true,
      heightOnly: false,
      locale: 'zh-Hans'
    };
  }

  buildMeasuredReaderParagraph(text: string, availableWidth: number,
    chapterIndex: number = this.currentChapterIndex): graphicsText.Paragraph {
    const bodyStyle = this.buildReaderMeasureTextStyle(this.readerFontSize, this.getBodyReaderFontFamily());
    const paragraphStyle: graphicsText.ParagraphStyle = {
      textStyle: bodyStyle,
      align: graphicsText.TextAlign.JUSTIFY,
      textDirection: graphicsText.TextDirection.LTR,
      wordBreak: graphicsText.WordBreak.BREAK_ALL,
      breakStrategy: graphicsText.BreakStrategy.GREEDY,
      trailingSpaceOptimized: true,
      includeFontPadding: false
    };
    const builder = new graphicsText.ParagraphBuilder(paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
    this.addMeasuredReaderText(builder, text || '', chapterIndex, bodyStyle);
    const paragraph = builder.build();
    paragraph.layoutSync(this.toMeasurePx(availableWidth));
    return paragraph;
  }

  addMeasuredReaderText(builder: graphicsText.ParagraphBuilder, text: string, chapterIndex: number,
    bodyStyle: graphicsText.TextStyle): void {
    if (this.shouldUseTitleStyle(text, chapterIndex)) {
      const title = this.getChapterTitle(chapterIndex).trim();
      const titleLength = Math.min(title.length, text.length);
      const titleStyle = this.buildReaderMeasureTextStyle(this.readerTitleFontSize, this.getTitleReaderFontFamily());
      builder.pushStyle(titleStyle);
      builder.addText(text.substring(0, titleLength));
      builder.popStyle();
      const rest = text.substring(titleLength);
      if (rest) {
        this.addMeasuredRegexReaderText(builder, rest, bodyStyle);
      }
      return;
    }
    this.addMeasuredRegexReaderText(builder, text, bodyStyle);
  }

  addMeasuredRegexReaderText(builder: graphicsText.ParagraphBuilder, text: string,
    bodyStyle: graphicsText.TextStyle): void {
    if (!this.readerRegexFontEnabled) {
      builder.pushStyle(bodyStyle);
      builder.addText(text);
      builder.popStyle();
      return;
    }
    const slices = this.getRegexTextSlices(text);
    for (const slice of slices) {
      const style = slice.highlighted ?
        this.buildReaderMeasureTextStyle(this.getRegexSliceFontSize(slice), this.getRegexSliceFontFamily(slice)) :
        bodyStyle;
      builder.pushStyle(style);
      builder.addText(slice.text);
      builder.popStyle();
    }
  }

  getParagraphFallbackMeasureStyle(text: string, chapterIndex: number): ReaderParagraphMeasureFallback {
    if (this.shouldUseTitleStyle(text, chapterIndex)) {
      return {
        fontSize: this.readerTitleFontSize,
        fontFamily: this.getTitleReaderFontFamily()
      };
    }
    if (this.readerRegexFontEnabled) {
      const slices = this.getRegexTextSlices(text);
      for (const slice of slices) {
        if (slice.highlighted) {
          return {
            fontSize: this.getRegexSliceFontSize(slice),
            fontFamily: this.getRegexSliceFontFamily(slice)
          };
        }
      }
    }
    return {
      fontSize: this.readerFontSize,
      fontFamily: this.getBodyReaderFontFamily()
    };
  }

  toMeasurePx(value: number): number {
    try {
      return Math.max(1, vp2px(value));
    } catch (_) {
      return Math.max(1, value);
    }
  }

  chooseReaderPageBreak(source: string, start: number, best: number): number {
    if (best >= source.length) {
      return source.length;
    }
    const safeBest = Math.max(start + 1, Math.min(best, source.length));
    if (safeBest > start && safeBest < source.length) {
      const previousCode = source.charCodeAt(safeBest - 1);
      const nextCode = source.charCodeAt(safeBest);
      const splitsSurrogatePair = previousCode >= 0xD800 && previousCode <= 0xDBFF &&
        nextCode >= 0xDC00 && nextCode <= 0xDFFF;
      if (splitsSurrogatePair && safeBest - 1 > start) {
        return safeBest - 1;
      }
    }
    return safeBest;
  }

  followTtsChunk(chunk: TtsChunk): void {
    setTimeout(() => {
      if (!this.isTtsSpeaking || !this.ttsAutoContinue) {
        return;
      }
      this.applyTtsChunkFocus(chunk);
    }, 0);
  }

  applyTtsChunkFocus(chunk: TtsChunk): void {
    const pageIndex = this.resolveTtsChunkPageIndex(chunk);
    const spreadPageIndex = this.normalizeReaderSpreadPageIndex(pageIndex);
    this.ttsLastFocusChunk = chunk;
    this.ttsLastFocusPageIndex = pageIndex;
    if (spreadPageIndex !== this.currentPageIndex) {
      this.animateTtsToPage(spreadPageIndex, chunk);
      return;
    }
    this.updateTtsChunkHighlight(chunk, pageIndex);
  }

  syncTtsFocusAfterResumeLater(delayMs: number): void {
    const serial = ++this.ttsResumeSyncSerial;
    setTimeout(() => {
      if (serial < this.ttsResumeSyncSerial - 1) {
        return;
      }
      this.syncTtsFocusAfterResume();
    }, delayMs);
  }

  syncTtsFocusAfterResume(): void {
    if (!this.isTtsSpeaking || !this.ttsAutoContinue || !this.ttsLastFocusChunk ||
      this.contentPages.length === 0) {
      return;
    }
    const pageIndex = this.resolveTtsChunkPageIndex(this.ttsLastFocusChunk);
    if (pageIndex < 0 || pageIndex >= this.contentPages.length) {
      return;
    }
    this.ttsLastFocusPageIndex = pageIndex;
    this.ttsPendingTargetPageIndex = -1;
    this.ttsPendingHighlightChunk = null;
    this.ttsAutoTurningPage = false;
    this.ttsPageTurnSerial++;
    this.finishPageTurnAnimation();
    const spreadPageIndex = this.normalizeReaderSpreadPageIndex(pageIndex);
    if (spreadPageIndex !== this.currentPageIndex) {
      this.currentPageIndex = spreadPageIndex;
      this.saveReadingProgress().catch((error: Error) => {
        console.warn('同步朗读恢复页码失败:', error);
      });
    }
    this.syncCurrentPageText();
    this.updateTtsChunkHighlight(this.ttsLastFocusChunk, pageIndex);
    console.info(`[TTS] resume focus synced: page=${pageIndex},highlight=${this.ttsHighlightStart}-${this.ttsHighlightEnd}`);
  }

  resolveTtsChunkPageIndex(chunk: TtsChunk): number {
    const absoluteStart = this.ttsTextStartOffset + chunk.start;
    return this.findPageIndexByOffset(absoluteStart);
  }

  updateTtsChunkHighlight(chunk: TtsChunk, pageIndex: number): void {
    const absoluteStart = this.ttsTextStartOffset + chunk.start;
    const absoluteEnd = this.ttsTextStartOffset + chunk.end;
    const pageStart = this.getPageStartOffset(pageIndex);
    const pageEnd = this.getPageEndOffset(pageIndex);
    const pageText = this.getPageText(pageIndex);
    this.ttsDisplayText = pageText;
    if (pageIndex === this.currentPageIndex) {
      this.setCurrentPageText(pageText);
    }
    this.ttsHighlightStart = Math.max(0, Math.min(absoluteStart - pageStart, pageText.length));
    this.ttsHighlightEnd = Math.max(this.ttsHighlightStart, Math.min(absoluteEnd, pageEnd) - pageStart);
    this.ttsHighlightRenderVersion++;
    this.chapterJumpRenderGeneration++;
    this.pageRenderVersion++;
  }

  animateTtsToPage(targetPageIndex: number, chunk: TtsChunk): void {
    const target = this.normalizeReaderSpreadPageIndex(
      Math.max(0, Math.min(targetPageIndex, Math.max(0, this.contentPages.length - 1)))
    );
    if (target <= this.currentPageIndex) {
      this.updateTtsChunkHighlight(chunk, this.resolveTtsChunkPageIndex(chunk));
      return;
    }
    this.ttsPendingTargetPageIndex = Math.max(this.ttsPendingTargetPageIndex, target);
    this.ttsPendingHighlightChunk = chunk;
    if (this.ttsAutoTurningPage) {
      return;
    }
    this.runPendingTtsPageTurn();
  }

  async runPendingTtsPageTurn(): Promise<void> {
    this.ttsAutoTurningPage = true;
    const turnSerial = this.ttsPageTurnSerial;
    try {
      if (this.isTtsSpeaking && this.ttsAutoContinue &&
        this.ttsPendingTargetPageIndex > this.currentPageIndex && this.canTurnPage(1)) {
        await this.runTtsPageTurnAnimation(1, turnSerial);
        if (turnSerial !== this.ttsPageTurnSerial) {
          return;
        }
      }
      if (turnSerial === this.ttsPageTurnSerial && this.isTtsSpeaking && this.ttsPendingHighlightChunk) {
        this.updateTtsChunkHighlight(this.ttsPendingHighlightChunk,
          this.resolveTtsChunkPageIndex(this.ttsPendingHighlightChunk));
      }
    } finally {
      if (turnSerial === this.ttsPageTurnSerial) {
        this.ttsAutoTurningPage = false;
        this.ttsPendingTargetPageIndex = -1;
        this.ttsPendingHighlightChunk = null;
      }
    }
  }

  async runTtsPageTurnAnimation(direction: number, turnSerial: number = this.ttsPageTurnSerial): Promise<void> {
    if (this.isPageTurning || !this.canTurnPage(direction)) {
      return;
    }
    this.isPageTurning = true;
    try {
      if (!this.isPageTurnAnimationEnabled()) {
        await this.applyTtsPageTurn(direction, turnSerial);
        const targetText = this.getCurrentPageText();
        this.commitVisibleCurrentPageText(targetText);
        this.finishPageTurnAnimation();
        this.commitCurrentPageTextLater(this.currentChapterIndex, this.currentPageIndex, targetText);
      } else if (this.readerPageTurnMode === 1) {
        await this.runTtsSlidePageTurn(direction, turnSerial);
      } else {
        await this.runTtsTapPageTurn(direction, turnSerial);
      }
    } finally {
      this.isPageTurning = false;
    }
  }

  async runTtsTapPageTurn(direction: number, turnSerial: number): Promise<void> {
    const distance = this.getPageTurnDistance();
    this.prepareSlidePageTurn(direction, 0);
    animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.setPageSlideAxisOffset(direction > 0 ? -distance : distance);
      this.pageTransitionOpacity = 1;
    });
    await this.delay(230);
    await this.applyTtsPageTurn(direction, turnSerial);
    this.finishAnimatedPageTurn();
  }

  async runTtsSlidePageTurn(direction: number, turnSerial: number): Promise<void> {
    const distance = this.getPageTurnDistance();
    this.prepareSlidePageTurn(direction, this.getPageSlideAxisOffset());
    animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.setPageSlideAxisOffset(direction > 0 ? -distance : distance);
      this.pageTransitionOpacity = 1;
    });
    await this.delay(250);
    await this.applyTtsPageTurn(direction, turnSerial);
    this.finishAnimatedPageTurn();
  }

  async applyTtsPageTurn(direction: number, turnSerial: number): Promise<void> {
    if (turnSerial !== this.ttsPageTurnSerial || !this.isTtsSpeaking || !this.ttsAutoContinue) {
      return;
    }
    if (direction > 0) {
      const localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
      if (localPageIndex >= 0) {
        this.currentPageIndex = localPageIndex;
        this.syncCurrentPageText();
        if (this.contentPages.length - this.currentPageIndex <= 3) {
          this.preloadReaderContent();
        }
        await this.saveReadingProgress();
      } else {
        await this.loadNextChapter();
      }
      return;
    }

    const localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
    if (localPageIndex >= 0) {
      this.currentPageIndex = localPageIndex;
      this.syncCurrentPageText();
      await this.saveReadingProgress();
    } else {
      await this.loadPrevChapter(true);
    }
  }

  delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }

  @Builder
  readerSlidingPageTurnSurface(currentText: string, currentRenderVersion: number, ttsRenderVersion: number) {
    Stack() {
      if (this.shouldRenderSlidingPageTurn()) {
        if (this.isStackPageTurnAnimation()) {
          this.readerCurrentPageSurface(currentRenderVersion, currentText, ttsRenderVersion)
          this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion, this.getVisiblePageTurnIncomingText())
        } else {
          this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion, this.getVisiblePageTurnIncomingText())
          this.readerCurrentPageSurface(currentRenderVersion, currentText, ttsRenderVersion)
        }
      } else {
        this.readerCurrentPageSurface(currentRenderVersion, currentText, ttsRenderVersion)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.readerContentLayerColor())
    .clip(true)
  }

  @Builder
  readerSlidingPageTurnSurfaceAlternate(currentText: string, currentRenderVersion: number, ttsRenderVersion: number) {
    Stack() {
      if (this.shouldRenderSlidingPageTurn()) {
        if (this.isStackPageTurnAnimation()) {
          this.readerCurrentPageSurfaceAlternate(currentRenderVersion, currentText, ttsRenderVersion)
          this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion, this.getVisiblePageTurnIncomingText())
        } else {
          this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion, this.getVisiblePageTurnIncomingText())
          this.readerCurrentPageSurfaceAlternate(currentRenderVersion, currentText, ttsRenderVersion)
        }
      } else {
        this.readerCurrentPageSurfaceAlternate(currentRenderVersion, currentText, ttsRenderVersion)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.readerContentLayerColor())
    .clip(true)
  }

  @Builder
  readerCurrentPageSurface(renderVersion: number, text: string, ttsRenderVersion: number) {
    Column() {
      this.readerCurrentPageLayer(renderVersion, text, ttsRenderVersion)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.getReaderPageContentTopPadding() })
    .id(`reader_current_${this.currentChapterIndex}_${this.currentPageIndex}_${this.displayPageRenderKey}_${renderVersion}_${ttsRenderVersion}`)
    .backgroundColor(this.readerContentLayerColor())
    .translate({ x: this.getCurrentPageTurnX(), y: this.getCurrentPageTurnY() + this.bookmarkPullOffsetY })
    .opacity(this.getCurrentPageTurnOpacity())
  }

  @Builder
  readerCurrentPageSurfaceAlternate(renderVersion: number, text: string, ttsRenderVersion: number) {
    Column() {
      this.readerCurrentPageLayer(renderVersion, text, ttsRenderVersion)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.getReaderPageContentTopPadding() })
    .id(`reader_current_alt_${this.currentChapterIndex}_${this.currentPageIndex}_${this.displayPageRenderKey}_${renderVersion}_${ttsRenderVersion}`)
    .backgroundColor(this.readerContentLayerColor())
    .translate({ x: this.getCurrentPageTurnX(), y: this.getCurrentPageTurnY() + this.bookmarkPullOffsetY })
    .opacity(this.getCurrentPageTurnOpacity())
  }

  @Builder
  readerIncomingPageSurface(renderVersion: number, text: string) {
    Stack() {
      if (this.isStackPageTurnAnimation()) {
        this.readerIncomingPageBackground()
      }
      Column() {
        this.readerIncomingPageLayer(renderVersion, text)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getReaderPageContentTopPadding() })
    }
    .width('100%')
    .height('100%')
    .id(`reader_incoming_${this.pageTurnIncomingChapterIndex}_${this.pageTurnIncomingPageIndex}_${renderVersion}`)
    .backgroundColor(this.readerContentLayerColor())
    .translate({ x: this.getIncomingSlideX(), y: this.getIncomingSlideY() })
    .opacity(this.getVisiblePageTurnIncomingOpacity())
    .clip(true)
  }

  @Builder
  readerIncomingPageBackground() {
    if (this.hasBackgroundImage()) {
      Image(this.getBackgroundImage())
        .width('100%')
        .height('100%')
        .objectFit(this.getBackgroundImageFit())
        .hitTestBehavior(HitTestMode.None)
    } else {
      Blank()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getBackgroundColor())
    }
  }

  @Builder
  readerCurrentPageLayer(renderVersion: number, text: string, ttsRenderVersion: number) {
    if (this.isLandscapeDoublePageActive()) {
      Row() {
        Column() {
          this.styledCurrentReaderText(text, this.getReaderContentBottomPadding(), this.currentChapterIndex,
            ttsRenderVersion, renderVersion,
            `${this.currentReaderPageRenderIdentity(renderVersion, ttsRenderVersion)}_left`, this.currentPageIndex)
        }
        .layoutWeight(1)
        .height('100%')

        Blank()
          .width(1)
          .height('88%')
          .backgroundColor(this.getSubTextColor())
          .opacity(0.22)

        Column() {
          this.styledCurrentReaderText(this.getSecondaryPageText(), this.getReaderContentBottomPadding(),
            this.currentChapterIndex, ttsRenderVersion, renderVersion,
            `${this.currentReaderPageRenderIdentity(renderVersion, ttsRenderVersion)}_right`, this.currentPageIndex + 1)
        }
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.readerContentLayerColor())
    } else {
      Column() {
        this.styledCurrentReaderText(text, this.getReaderContentBottomPadding(),
          this.currentChapterIndex,
          ttsRenderVersion, renderVersion, this.currentReaderPageRenderIdentity(renderVersion, ttsRenderVersion),
          this.currentPageIndex)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.readerContentLayerColor())
      .id(`reader_layer_${this.currentReaderPageRenderIdentity(renderVersion, ttsRenderVersion)}`)
    }
  }

  @Builder
  readerIncomingPageLayer(renderVersion: number, text: string) {
    if (this.isLandscapeDoublePageActive()) {
      Row() {
        Column() {
          this.styledReaderText(text, this.getReaderContentBottomPadding(), this.pageTurnIncomingChapterIndex, 0,
            renderVersion, `${this.incomingReaderPageRenderIdentity(renderVersion, text)}_left`,
            this.pageTurnIncomingPageIndex)
        }
        .layoutWeight(1)
        .height('100%')

        Blank()
          .width(1)
          .height('88%')
          .backgroundColor(this.getSubTextColor())
          .opacity(0.22)

        Column() {
          this.styledReaderText(this.pageTurnIncomingSecondaryText, this.getReaderContentBottomPadding(),
            this.pageTurnIncomingChapterIndex, 0, renderVersion,
            `${this.incomingReaderPageRenderIdentity(renderVersion, text)}_right`, this.pageTurnIncomingPageIndex + 1)
        }
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.readerContentLayerColor())
    } else {
      Column() {
        this.styledReaderText(text, this.getReaderContentBottomPadding(),
          this.pageTurnIncomingChapterIndex, 0,
          renderVersion, this.incomingReaderPageRenderIdentity(renderVersion, text), this.pageTurnIncomingPageIndex)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.readerContentLayerColor())
      .id(`reader_incoming_layer_${this.incomingReaderPageRenderIdentity(renderVersion, text)}`)
    }
  }

  currentReaderPageRenderIdentity(renderVersion: number = this.pageRenderVersion,
    ttsRenderVersion: number = this.ttsHighlightRenderVersion): string {
    return this.readerPageRenderIdentity(
      'current',
      this.displayPageChapterIndex,
      this.displayPageIndex,
      renderVersion,
      ttsRenderVersion,
      this.visibleCurrentPageText(),
      this.displayPageRenderKey
    );
  }

  incomingReaderPageRenderIdentity(renderVersion: number, text: string): string {
    return this.readerPageRenderIdentity(
      'incoming',
      this.pageTurnIncomingChapterIndex,
      this.pageTurnIncomingPageIndex,
      renderVersion,
      0,
      text,
      this.pageTurnIncomingRenderVersion
    );
  }

  readerPageRenderIdentity(prefix: string, chapterIndex: number, pageIndex: number, renderVersion: number,
    ttsRenderVersion: number, text: string, displayKey: number = 0): string {
    return `${prefix}_${chapterIndex}_${pageIndex}_${displayKey}_${renderVersion}_${ttsRenderVersion}_` +
      `${this.buildTextSliceKey(text || '')}`;
  }

  effectiveReaderPageRenderIdentity(pageRenderIdentity: string, chapterIndex: number, renderVersion: number,
    ttsRenderVersion: number, text: string): string {
    return pageRenderIdentity || this.readerPageRenderIdentity(
      'paragraph',
      chapterIndex,
      this.currentPageIndex,
      renderVersion,
      ttsRenderVersion,
      text
    );
  }

  @Builder
  readingText(text: string, bottomPadding: number) {
    Column() {
      ForEach(this.getReaderTextParagraphs(this.getReadingRenderText(text)), (paragraph: ReaderTextParagraph) => {
        if (this.hasActiveTtsHighlight(text)) {
          Text() {
            ForEach(this.getReadingTextSlicesInRange(
              paragraph.text,
              this.ttsHighlightStart - paragraph.start,
              this.ttsHighlightEnd - paragraph.start
            ), (slice: ReadTextSlice) => {
              Span(slice.text)
                .fontColor(slice.highlighted ? this.getTtsHighlightTextColor() : this.getTextColor())
                .textBackgroundStyle(slice.highlighted ? {
                  color: this.getTtsHighlightColor(),
                  radius: 4
                } : {})
            }, (slice: ReadTextSlice) => `${paragraph.key}_${slice.key}`)
          }
          .fontSize(this.readerFontSize)
          .fontFamily(this.getBodyReaderFontFamily())
          .lineHeight(this.getEffectiveReaderLineHeight())
          .fontColor(this.getTextColor())
          .textAlign(TextAlign.JUSTIFY)
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
        } else {
          this.styledReaderParagraph(paragraph, this.currentChapterIndex)
        }
        this.readerParagraphGap(paragraph)
      }, (paragraph: ReaderTextParagraph) => paragraph.key)
    }
    .width('100%')
    .padding({
      left: this.readerMarginLeft,
      right: this.readerMarginRight,
      top: this.readerMarginTop,
      bottom: bottomPadding
    })
  }

  @Builder
  styledCurrentReaderText(text: string, bottomPadding: number, chapterIndex: number = this.currentChapterIndex,
    ttsRenderVersion: number = this.ttsHighlightRenderVersion, contentRenderVersion: number = this.pageRenderVersion,
    pageRenderIdentity: string = this.currentReaderPageRenderIdentity(contentRenderVersion, ttsRenderVersion),
    pageIndex: number = this.currentPageIndex) {
    Column() {
      ForEach(this.getReaderTextParagraphs(text), (paragraph: ReaderTextParagraph) => {
        this.styledReaderParagraph(paragraph, chapterIndex, this.hasActiveTtsHighlight(text),
          ttsRenderVersion, contentRenderVersion, pageRenderIdentity, this.getPageStartOffset(pageIndex))
        this.readerParagraphGap(paragraph)
      }, (paragraph: ReaderTextParagraph) =>
        `${pageRenderIdentity}_${paragraph.key}`)
    }
    .width('100%')
    .id(`reader_text_${pageRenderIdentity}`)
    .padding({
      left: this.readerMarginLeft,
      right: this.readerMarginRight,
      top: this.readerMarginTop,
      bottom: bottomPadding
    })
  }

  @Builder
  styledReaderText(text: string, bottomPadding: number, chapterIndex: number = this.currentChapterIndex,
    ttsRenderVersion: number = this.ttsHighlightRenderVersion, contentRenderVersion: number = this.pageRenderVersion,
    pageRenderIdentity: string = this.readerPageRenderIdentity('text', chapterIndex, this.currentPageIndex,
      contentRenderVersion, ttsRenderVersion, text), pageIndex: number = this.currentPageIndex) {
    Column() {
      ForEach(this.getReaderTextParagraphs(text), (paragraph: ReaderTextParagraph) => {
        this.styledReaderParagraph(paragraph, chapterIndex, this.hasActiveTtsHighlight(text), ttsRenderVersion,
          contentRenderVersion, pageRenderIdentity,
          chapterIndex === this.currentChapterIndex ? this.getPageStartOffset(pageIndex) : -1)
        this.readerParagraphGap(paragraph)
      }, (paragraph: ReaderTextParagraph) => `${pageRenderIdentity}_${paragraph.key}`)
    }
    .width('100%')
    .id(`reader_text_${pageRenderIdentity}`)
    .padding({
      left: this.readerMarginLeft,
      right: this.readerMarginRight,
      top: this.readerMarginTop,
      bottom: bottomPadding
    })
  }

  @Builder
  styledReaderParagraph(paragraph: ReaderTextParagraph, chapterIndex: number = this.currentChapterIndex,
    ttsHighlightActive: boolean = true, ttsRenderVersion: number = this.ttsHighlightRenderVersion,
    contentRenderVersion: number = this.pageRenderVersion, pageRenderIdentity: string = '', pageStart: number = -1) {
    if (this.shouldUseTitleStyle(paragraph.text, chapterIndex)) {
      Text() {
        ForEach(this.getTitleTextSlices(paragraph, chapterIndex, ttsHighlightActive), (slice: ReadTextSlice) => {
          Span(slice.text)
            .fontSize(this.readerTitleFontSize)
            .fontFamily(this.getTitleReaderFontFamily())
            .fontColor(slice.ttsHighlighted ? this.getTtsHighlightTextColor() : this.getTextColor())
            .textBackgroundStyle(slice.ttsHighlighted ? {
              color: this.getTtsHighlightColor(),
              radius: 4
            } : {})
        }, (slice: ReadTextSlice) =>
          `title_${this.effectiveReaderPageRenderIdentity(pageRenderIdentity, chapterIndex, contentRenderVersion,
            ttsRenderVersion, paragraph.text)}_${paragraph.key}_${slice.key}`)
        ForEach(this.getTitleBodyTextSlices(paragraph, chapterIndex, ttsHighlightActive, pageStart),
          (slice: ReadTextSlice) => {
          Span(slice.text)
            .fontSize(slice.highlighted ? this.getRegexSliceFontSize(slice) : this.readerFontSize)
            .fontFamily(slice.highlighted ? this.getRegexSliceFontFamily(slice) : this.getBodyReaderFontFamily())
            .fontColor(this.getStyledSliceFontColor(slice))
            .textBackgroundStyle(this.getStyledSliceBackgroundStyle(slice))
            .textShadow(this.getStyledSliceTextShadow(slice))
        }, (slice: ReadTextSlice) =>
          `title_body_${this.effectiveReaderPageRenderIdentity(pageRenderIdentity, chapterIndex, contentRenderVersion,
            ttsRenderVersion, paragraph.text)}_${paragraph.key}_${slice.key}`)
      }
      .lineHeight(this.getEffectiveReaderLineHeight())
      .fontColor(this.getTextColor())
      .width('100%')
      .id(`reader_title_${this.effectiveReaderPageRenderIdentity(pageRenderIdentity, chapterIndex, contentRenderVersion,
        ttsRenderVersion, paragraph.text)}_${paragraph.key}`)
    } else if (this.readerRegexFontEnabled) {
      this.regexReaderText(paragraph, ttsHighlightActive, ttsRenderVersion, contentRenderVersion,
        this.effectiveReaderPageRenderIdentity(pageRenderIdentity, chapterIndex, contentRenderVersion,
          ttsRenderVersion, paragraph.text), pageStart)
    } else {
      Text() {
        ForEach(this.getStyledParagraphTextSlices(paragraph, ttsHighlightActive, pageStart), (slice: ReadTextSlice) => {
          Span(slice.text)
            .fontSize(this.readerFontSize)
            .fontFamily(this.getBodyReaderFontFamily())
            .fontColor(this.getStyledSliceFontColor(slice))
            .textBackgroundStyle(this.getStyledSliceBackgroundStyle(slice))
            .textShadow(this.getStyledSliceTextShadow(slice))
        }, (slice: ReadTextSlice) =>
          `${this.effectiveReaderPageRenderIdentity(pageRenderIdentity, chapterIndex, contentRenderVersion,
            ttsRenderVersion, paragraph.text)}_${paragraph.key}_${slice.key}`)
      }
        .lineHeight(this.getEffectiveReaderLineHeight())
        .fontColor(this.getTextColor())
        .textAlign(TextAlign.JUSTIFY)
        .wordBreak(WordBreak.BREAK_ALL)
        .width('100%')
        .id(`reader_plain_${this.effectiveReaderPageRenderIdentity(pageRenderIdentity, chapterIndex,
          contentRenderVersion, ttsRenderVersion, paragraph.text)}_${paragraph.key}`)
    }
  }

  @Builder
  readerParagraphGap(paragraph: ReaderTextParagraph) {
    if (!paragraph.isLast && this.readerParagraphSpacing > 0) {
      Blank()
        .height(this.readerParagraphSpacing)
        .width('100%')
    }
  }

  @Builder
  regexReaderText(paragraph: ReaderTextParagraph, ttsHighlightActive: boolean = true,
    ttsRenderVersion: number = this.ttsHighlightRenderVersion, contentRenderVersion: number = this.pageRenderVersion,
    pageRenderIdentity: string = '', pageStart: number = -1) {
    Text() {
      ForEach(this.getStyledParagraphTextSlices(paragraph, ttsHighlightActive, pageStart), (slice: ReadTextSlice) => {
        Span(slice.text)
          .fontSize(slice.highlighted ? this.getRegexSliceFontSize(slice) : this.readerFontSize)
          .fontFamily(slice.highlighted ? this.getRegexSliceFontFamily(slice) : this.getBodyReaderFontFamily())
          .fontColor(this.getStyledSliceFontColor(slice))
          .textBackgroundStyle(this.getStyledSliceBackgroundStyle(slice))
          .textShadow(this.getStyledSliceTextShadow(slice))
      }, (slice: ReadTextSlice) =>
        `${this.effectiveReaderPageRenderIdentity(pageRenderIdentity, this.currentChapterIndex, contentRenderVersion,
          ttsRenderVersion, paragraph.text)}_${paragraph.key}_${slice.key}`)
    }
    .lineHeight(this.getEffectiveReaderLineHeight())
    .fontColor(this.getTextColor())
    .textAlign(TextAlign.JUSTIFY)
    .wordBreak(WordBreak.BREAK_ALL)
    .width('100%')
    .id(`reader_regex_${this.effectiveReaderPageRenderIdentity(pageRenderIdentity, this.currentChapterIndex,
      contentRenderVersion, ttsRenderVersion, paragraph.text)}_${paragraph.key}`)
  }

  getTitleTextSlices(paragraph: ReaderTextParagraph, chapterIndex: number,
    ttsHighlightActive: boolean = true): ReadTextSlice[] {
    const title = this.getChapterTitle(chapterIndex);
    const titleText = paragraph.text.substring(0, Math.min(title.length, paragraph.text.length));
    return this.splitSliceByTtsHighlight({
      text: titleText,
      start: 0,
      end: titleText.length,
      highlighted: false,
      ruleIndex: -1,
      key: `title_plain_${this.buildTextSliceKey(titleText)}`
    }, paragraph.start, 0, ttsHighlightActive);
  }

  getTitleBodyTextSlices(paragraph: ReaderTextParagraph, chapterIndex: number,
    ttsHighlightActive: boolean = true, pageStart: number = -1): ReadTextSlice[] {
    const titleLength = Math.min(this.getChapterTitle(chapterIndex).length, paragraph.text.length);
    const bodyText = paragraph.text.substring(titleLength);
    return this.splitSlicesByTtsHighlight(
      this.getRegexTextSlicesAt(bodyText, pageStart < 0 ? -1 : pageStart + paragraph.start + titleLength),
      paragraph.start, titleLength,
      ttsHighlightActive);
  }

  handleTocCurrentPositionClick(): void {
    if (this.tocQuickJumpArmed) {
      this.tocQuickJumpDraft = '';
      this.tocQuickJumpInputVisible = true;
      this.tocQuickJumpArmed = false;
      setTimeout(() => {
        focusControl.requestFocus('tocQuickJumpChapterInput');
      }, 50);
      return;
    }
    this.scrollTocToCurrentChapter();
    this.tocQuickJumpArmed = true;
  }

  submitTocQuickJump(): void {
    if (this.chapters.length === 0) {
      promptAction.showToast({ message: '暂无可定位的章节' });
      return;
    }
    const chapterNumber = Number.parseInt(this.tocQuickJumpDraft, 10);
    if (!Number.isFinite(chapterNumber) || chapterNumber < 1 || chapterNumber > this.chapters.length) {
      promptAction.showToast({ message: `章节序号范围为 1～${this.chapters.length}，请重新输入` });
      setTimeout(() => {
        focusControl.requestFocus('tocQuickJumpChapterInput');
      }, 50);
      return;
    }
    this.tocQuickJumpInputVisible = false;
    this.tocQuickJumpDraft = '';
    this.tocQuickJumpArmed = false;
    this.scrollTocToChapter(chapterNumber - 1, ScrollAlign.CENTER);
  }

  getStyledParagraphTextSlices(paragraph: ReaderTextParagraph, ttsHighlightActive: boolean = true,
    pageStart: number = -1): ReadTextSlice[] {
    return this.splitSlicesByTtsHighlight(
      this.getRegexTextSlicesAt(paragraph.text, pageStart < 0 ? -1 : pageStart + paragraph.start), paragraph.start, 0,
      ttsHighlightActive);
  }

  splitSlicesByTtsHighlight(slices: ReadTextSlice[], paragraphStart: number, segmentOffset: number,
    ttsHighlightActive: boolean = true): ReadTextSlice[] {
    const result: ReadTextSlice[] = [];
    for (const slice of slices) {
      result.push(...this.splitSliceByTtsHighlight(slice, paragraphStart, segmentOffset, ttsHighlightActive));
    }
    return result;
  }

  splitSliceByTtsHighlight(slice: ReadTextSlice, paragraphStart: number, segmentOffset: number,
    ttsHighlightActive: boolean = true): ReadTextSlice[] {
    const sliceStart = segmentOffset + slice.start;
    const sliceEnd = segmentOffset + slice.end;
    const localHighlightStart = this.ttsHighlightStart - paragraphStart;
    const localHighlightEnd = this.ttsHighlightEnd - paragraphStart;
    if (!ttsHighlightActive || !this.isTtsSpeaking || this.ttsHighlightStart < 0 ||
      this.ttsHighlightEnd <= this.ttsHighlightStart || localHighlightEnd <= sliceStart ||
      localHighlightStart >= sliceEnd) {
      return [this.cloneStyledSlice(slice, sliceStart, sliceEnd, slice.text, false, 'plain')];
    }

    const overlapStart = Math.max(sliceStart, localHighlightStart);
    const overlapEnd = Math.min(sliceEnd, localHighlightEnd);
    const result: ReadTextSlice[] = [];
    if (overlapStart > sliceStart) {
      const beforeText = slice.text.substring(0, overlapStart - sliceStart);
      result.push(this.cloneStyledSlice(slice, sliceStart, overlapStart, beforeText, false, 'before_tts'));
    }
    const highlightText = slice.text.substring(overlapStart - sliceStart, overlapEnd - sliceStart);
    result.push(this.cloneStyledSlice(slice, overlapStart, overlapEnd, highlightText, true, 'tts'));
    if (overlapEnd < sliceEnd) {
      const afterText = slice.text.substring(overlapEnd - sliceStart);
      result.push(this.cloneStyledSlice(slice, overlapEnd, sliceEnd, afterText, false, 'after_tts'));
    }
    return result;
  }

  cloneStyledSlice(source: ReadTextSlice, start: number, end: number, text: string, ttsHighlighted: boolean,
    keyPrefix: string): ReadTextSlice {
    return {
      text: text,
      start: start,
      end: end,
      highlighted: source.highlighted,
      ruleIndex: source.ruleIndex,
      ttsHighlighted: ttsHighlighted,
      key: `${keyPrefix}_${start}_${end}_${source.ruleIndex}_${this.buildTextSliceKey(text)}`
    };
  }

  getStyledSliceFontColor(slice: ReadTextSlice): string {
    if (slice.ttsHighlighted) {
      return this.getTtsHighlightTextColor();
    }
    if (slice.highlighted) {
      return this.resolvedRegexEmphasis(this.getRegexRuleBySlice(slice)).textColor;
    }
    return this.getTextColor();
  }

  getStyledSliceBackgroundStyle(slice: ReadTextSlice): TextBackgroundStyle {
    if (slice.ttsHighlighted) {
      return { color: this.getTtsHighlightColor(), radius: 4 };
    }
    if (!slice.highlighted) {
      return {};
    }
    const style = this.resolvedRegexEmphasis(this.getRegexRuleBySlice(slice));
    if (!style.backgroundEnabled) {
      return {};
    }
    return {
      color: style.backgroundColor,
      radius: {
        topLeft: style.radiusTopLeft,
        topRight: style.radiusTopRight,
        bottomLeft: style.radiusBottomLeft,
        bottomRight: style.radiusBottomRight
      }
    };
  }

  getStyledSliceTextShadow(slice: ReadTextSlice): ShadowOptions {
    if (slice.ttsHighlighted || !slice.highlighted) {
      return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
    }
    const style = this.resolvedRegexEmphasis(this.getRegexRuleBySlice(slice));
    return {
      radius: style.textShadowRadius,
      color: style.textShadowColor,
      offsetX: style.textShadowOffsetX,
      offsetY: style.textShadowOffsetY
    };
  }

  shouldUseTitleStyle(text: string, chapterIndex: number = this.currentChapterIndex): boolean {
    const title = this.getChapterTitle(chapterIndex).trim();
    return !!title && (text || '').startsWith(title);
  }

  shouldUseRegexStyle(text: string): boolean {
    return this.hasRegexMatch(text);
  }

  hasRegexMatch(text: string): boolean {
    if (!this.readerRegexFontEnabled) {
      return false;
    }
    const rules = this.getRegexRules();
    for (const rule of rules) {
      if (!rule.pattern.trim()) {
        continue;
      }
      try {
        if (new RegExp(rule.pattern).test(text || '')) {
          return true;
        }
      } catch (e) {
      }
    }
    return false;
  }

  getRegexRules(): ReaderRegexFontRule[] {
    const key = `${this.readerRegexFontRulesRaw}\n${this.readerRegexFontPattern}\n${this.readerRegexFontMode}\n` +
      `${this.readerRegexFontFamily}\n${this.readerRegexFontSize}\n${this.readerRegexShadowColor}`;
    if (key === this.cachedRegexRulesKey) {
      return this.cachedRegexRules;
    }
    const legacy = new ReaderRegexLegacySettings();
    legacy.pattern = this.readerRegexFontPattern;
    legacy.fontMode = this.readerRegexFontMode;
    legacy.fontFamily = this.readerRegexFontFamily;
    legacy.fontSize = this.readerRegexFontSize;
    legacy.shadowColor = this.readerRegexShadowColor;
    this.cachedRegexRules = ReaderRegexFontCodec.decode(this.readerRegexFontRulesRaw, legacy);
    this.cachedRegexRulesKey = key;
    return this.cachedRegexRules;
  }

  themeRegexEmphasisMode(): string {
    return ThemeRuntime.regexEmphasisMode();
  }

  themeRegexBubbleStyleId(): string {
    return ThemeRuntime.regexBubbleStyle();
  }

  themeRegexEmphasisColor(): string {
    return ThemeRuntime.regexEmphasisColor(this.appDarkMode);
  }

  readerRegexEmphasisContext(): ReaderRegexEmphasisContext {
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = this.themeRegexEmphasisMode();
    context.inheritedBubbleStyleId = this.themeRegexBubbleStyleId();
    context.inheritedColor = this.themeRegexEmphasisColor();
    context.inheritedTextColor = ThemeRuntime.regexEmphasisTextColor(this.appDarkMode);
    context.accentColor = this.accentColor();
    context.surfaceColor = this.getBackgroundColor();
    context.normalTextColor = this.getTextColor();
    context.darkMode = this.isReaderThemeDark();
    return context;
  }

  resolvedRegexEmphasis(rule: ReaderRegexFontRule | null): ReaderResolvedRegexEmphasis {
    return ReaderRegexBubbleStyleResolver.resolve(rule, this.readerRegexEmphasisContext());
  }

  getRegexTextSlices(text: string): ReadTextSlice[] {
    const displayText = text || '';
    const rules = this.getRegexRules();
    if (!this.readerRegexFontEnabled || rules.length === 0) {
      return [{
        text: displayText,
        start: 0,
        end: displayText.length,
        highlighted: false,
        ruleIndex: -1,
        key: `plain_regex_${this.buildTextSliceKey(displayText)}`
      }];
    }
    try {
      const matched: ReadTextSlice[] = [];
      for (let ruleIndex = 0; ruleIndex < rules.length; ruleIndex++) {
        const rule = rules[ruleIndex];
        if (!rule.pattern.trim()) {
          continue;
        }
        let regex: RegExp;
        try {
          regex = new RegExp(rule.pattern, 'g');
        } catch (e) {
          continue;
        }
        let match = regex.exec(displayText);
        while (match && match.index >= 0) {
          const start = Math.max(0, match.index);
          const end = Math.max(start, Math.min(displayText.length, match.index + (match[0] || '').length));
          if (end <= start) {
            if (start >= displayText.length || regex.lastIndex >= displayText.length) {
              break;
            }
            regex.lastIndex = Math.max(regex.lastIndex + 1, start + 1);
            match = regex.exec(displayText);
            continue;
          }
          if (!this.hasOverlappedRegexSlice(matched, start, end)) {
            const matchText = displayText.substring(start, end);
            matched.push({
              text: matchText,
              start: start,
              end: end,
              highlighted: true,
              ruleIndex: ruleIndex,
              key: `regex_hit_${ruleIndex}_${start}_${end}_${this.buildTextSliceKey(matchText)}`
            });
          }
          regex.lastIndex = Math.max(regex.lastIndex, end);
          match = regex.exec(displayText);
        }
      }
      if (matched.length === 0) {
        return [{
          text: displayText,
          start: 0,
          end: displayText.length,
          highlighted: false,
          ruleIndex: -1,
          key: `plain_regex_${this.buildTextSliceKey(displayText)}`
        }];
      }
      matched.sort((a: ReadTextSlice, b: ReadTextSlice) => a.start - b.start);
      const slices: ReadTextSlice[] = [];
      let cursor = 0;
      for (const item of matched) {
        const start = Math.max(cursor, item.start);
        const end = Math.max(start, item.end);
        if (start > cursor) {
          const beforeText = displayText.substring(cursor, start);
          slices.push({
            text: beforeText,
            start: cursor,
            end: start,
            highlighted: false,
            ruleIndex: -1,
            key: `regex_plain_${cursor}_${start}_${this.buildTextSliceKey(beforeText)}`
          });
        }
        const matchText = displayText.substring(start, end);
        slices.push({
          text: matchText,
          start: start,
          end: end,
          highlighted: true,
          ruleIndex: item.ruleIndex,
          key: `regex_hit_${item.ruleIndex}_${start}_${end}_${this.buildTextSliceKey(matchText)}`
        });
        cursor = end;
      }
      if (cursor < displayText.length) {
        const afterText = displayText.substring(cursor);
        slices.push({
          text: afterText,
          start: cursor,
          end: displayText.length,
          highlighted: false,
          ruleIndex: -1,
          key: `regex_plain_${cursor}_${displayText.length}_${this.buildTextSliceKey(afterText)}`
        });
      }
      return slices;
    } catch (e) {
      return [{
        text: displayText,
        start: 0,
        end: displayText.length,
        highlighted: false,
        ruleIndex: -1,
        key: `plain_regex_error_${this.buildTextSliceKey(displayText)}`
      }];
    }
  }

  /**
   * 从整章的正则匹配结果中截取当前页面/段落。这样匹配范围即使跨过分页点，
   * 两页上的可见部分也会保持同一条高亮规则。
   */
  getRegexTextSlicesAt(text: string, absoluteStart: number): ReadTextSlice[] {
    const displayText = text || '';
    if (absoluteStart < 0 || !this.pagedContentText) {
      return this.getRegexTextSlices(displayText);
    }
    this.getRegexRules();
    const documentRulesKey = `${this.readerRegexFontEnabled ? '1' : '0'}_${this.cachedRegexRulesKey}`;
    if (this.cachedDocumentRegexSource !== this.pagedContentText ||
      this.cachedDocumentRegexRulesKey !== documentRulesKey) {
      this.cachedDocumentRegexSource = this.pagedContentText;
      this.cachedDocumentRegexRulesKey = documentRulesKey;
      this.cachedDocumentRegexSlices = this.getRegexTextSlices(this.pagedContentText);
    }
    const absoluteEnd = Math.min(this.pagedContentText.length, absoluteStart + displayText.length);
    const result: ReadTextSlice[] = [];
    for (const slice of this.cachedDocumentRegexSlices) {
      if (slice.end <= absoluteStart) continue;
      if (slice.start >= absoluteEnd) break;
      const overlapStart = Math.max(slice.start, absoluteStart);
      const overlapEnd = Math.min(slice.end, absoluteEnd);
      if (overlapEnd <= overlapStart) continue;
      const localStart = overlapStart - absoluteStart;
      const localEnd = overlapEnd - absoluteStart;
      const sliceText = displayText.substring(localStart, localEnd);
      result.push({
        text: sliceText,
        start: localStart,
        end: localEnd,
        highlighted: slice.highlighted,
        ruleIndex: slice.ruleIndex,
        key: `document_regex_${slice.ruleIndex}_${overlapStart}_${overlapEnd}_${this.buildTextSliceKey(sliceText)}`
      });
    }
    return result.length > 0 ? result : this.getRegexTextSlices(displayText);
  }

  hasOverlappedRegexSlice(slices: ReadTextSlice[], start: number, end: number): boolean {
    for (const slice of slices) {
      if (start < slice.end && end > slice.start) {
        return true;
      }
    }
    return false;
  }

  getRegexRuleBySlice(slice: ReadTextSlice): ReaderRegexFontRule | null {
    const rules = this.getRegexRules();
    if (!slice.highlighted || slice.ruleIndex < 0 || slice.ruleIndex >= rules.length) {
      return null;
    }
    return rules[slice.ruleIndex];
  }

  getRegexSliceFontSize(slice: ReadTextSlice): number {
    const rule = this.getRegexRuleBySlice(slice);
    return rule ? rule.fontSize : this.readerRegexFontSize;
  }

  getRegexSliceFontFamily(slice: ReadTextSlice): string {
    const rule = this.getRegexRuleBySlice(slice);
    return rule ? this.resolveStyledReaderFontFamily(rule.fontMode, rule.fontFamily) : this.getRegexReaderFontFamily();
  }

  getReadingTextSlices(text: string): ReadTextSlice[] {
    const displayText = this.getReadingRenderText(text);
    const start = this.ttsHighlightStart;
    const end = this.ttsHighlightEnd;
    if (!this.isTtsSpeaking || !this.ttsDisplayText || start < 0 || end <= start || displayText !== this.ttsDisplayText) {
      return [{
        text: displayText,
        start: 0,
        end: displayText.length,
        highlighted: false,
        ruleIndex: -1,
        key: `plain_${this.buildTextSliceKey(displayText)}`
      }];
    }
    const clampedStart = Math.max(0, Math.min(start, displayText.length));
    const clampedEnd = Math.max(clampedStart, Math.min(end, displayText.length));
    const slices: ReadTextSlice[] = [];
    if (clampedStart > 0) {
      slices.push({
        text: displayText.substring(0, clampedStart),
        start: 0,
        end: clampedStart,
        highlighted: false,
        ruleIndex: -1,
        key: `before_${clampedStart}_${this.buildTextSliceKey(displayText.substring(0, clampedStart))}`
      });
    }
    const highlightedText = displayText.substring(clampedStart, clampedEnd);
    slices.push({
      text: highlightedText,
      start: clampedStart,
      end: clampedEnd,
      highlighted: true,
      ruleIndex: -1,
      key: `highlight_${clampedStart}_${clampedEnd}_${this.buildTextSliceKey(highlightedText)}`
    });
    if (clampedEnd < displayText.length) {
      const afterText = displayText.substring(clampedEnd);
      slices.push({
        text: afterText,
        start: clampedEnd,
        end: displayText.length,
        highlighted: false,
        ruleIndex: -1,
        key: `after_${clampedEnd}_${this.buildTextSliceKey(afterText)}`
      });
    }
    return slices;
  }

  getReadingTextSlicesInRange(text: string, start: number, end: number): ReadTextSlice[] {
    const displayText = text || '';
    if (!this.isTtsSpeaking || start < 0 || end <= start) {
      return [{
        text: displayText,
        start: 0,
        end: displayText.length,
        highlighted: false,
        ruleIndex: -1,
        key: `plain_${this.buildTextSliceKey(displayText)}`
      }];
    }
    const clampedStart = Math.max(0, Math.min(start, displayText.length));
    const clampedEnd = Math.max(clampedStart, Math.min(end, displayText.length));
    const slices: ReadTextSlice[] = [];
    if (clampedStart > 0) {
      const beforeText = displayText.substring(0, clampedStart);
      slices.push({
        text: beforeText,
        start: 0,
        end: clampedStart,
        highlighted: false,
        ruleIndex: -1,
        key: `before_${clampedStart}_${this.buildTextSliceKey(beforeText)}`
      });
    }
    const highlightedText = displayText.substring(clampedStart, clampedEnd);
    slices.push({
      text: highlightedText,
      start: clampedStart,
      end: clampedEnd,
      highlighted: true,
      ruleIndex: -1,
      key: `highlight_${clampedStart}_${clampedEnd}_${this.buildTextSliceKey(highlightedText)}`
    });
    if (clampedEnd < displayText.length) {
      const afterText = displayText.substring(clampedEnd);
      slices.push({
        text: afterText,
        start: clampedEnd,
        end: displayText.length,
        highlighted: false,
        ruleIndex: -1,
        key: `after_${clampedEnd}_${this.buildTextSliceKey(afterText)}`
      });
    }
    return slices;
  }

  hasActiveTtsHighlight(text: string): boolean {
    const displayText = this.getReadingRenderText(text);
    return this.isTtsSpeaking && !!this.ttsDisplayText &&
      this.ttsHighlightStart >= 0 && this.ttsHighlightEnd > this.ttsHighlightStart &&
      displayText === this.ttsDisplayText;
  }

  getReadingRenderText(text: string): string {
    const normalized = (text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    if (this.isTtsSpeaking && this.ttsDisplayText && normalized === this.ttsDisplayText) {
      return this.ttsDisplayText;
    }
    return text || '';
  }

  buildTextSliceKey(text: string): string {
    const value = text || '';
    const first = value.substring(0, Math.min(12, value.length));
    const last = value.substring(Math.max(0, value.length - 12));
    return `${value.length}_${this.hashText(first + last)}`;
  }

  hashText(text: string): number {
    let hash = 0;
    for (let i = 0; i < text.length; i++) {
      hash = ((hash * 31) + text.charCodeAt(i)) & 0x7fffffff;
    }
    return hash;
  }

  getTtsHighlightColor(): string {
    return this.isReaderThemeDark() ? '#5A4A24' : '#FFE58A';
  }

  getTtsHighlightTextColor(): string {
    return this.isReaderThemeDark() ? '#FFF4BF' : '#2F261D';
  }

  @Builder
  menuDismissLayer() {
    Blank()
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.hideReaderPanels();
      })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionStart(() => {
            this.hideReaderPanels();
          })
      )
  }

  @Builder
  settingsDismissLayer() {
    Column() {
      Blank()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.closeSettingsPanelKeepMenu();
        })
      Blank()
        .width('100%')
        .height(520)
    }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
  }

  hideReaderPanels() {
    this.menuChapterPreviewIndex = this.currentChapterIndex;
    this.menuChapterSliderActive = false;
    this.menuChapterTooltipVisible = false;
    this.showReaderActionMenu = false;
    this.showMenu = false;
    this.showSettings = false;
    this.showQuickTypographyValueInput = false;
  }

  async exitReaderPage(): Promise<void> {
    if (this.readerExitProgressSaved) {
      return;
    }
    this.hideReaderPanels();
    this.stopTtsReading();
    if (this.openedFromShortcut) {
      this.readerExitProgressSaved = true;
      this.saveReadingProgress().catch((error: Error) => {
        console.error('快捷入口返回时保存进度失败:', error);
      });
      try {
        if (this.shortcutReplacedPreviousPage) {
          await router.replaceUrl({ url: 'pages/Index' });
        } else {
          router.back();
        }
      } catch (e) {
        console.error('快捷入口返回书架失败:', e);
      }
      return;
    }
    try {
      await this.saveReadingProgress();
      this.readerExitProgressSaved = true;
    } catch (e) {
      console.error('返回阅读页时保存进度失败:', e);
    }
    if (this.openedWithShelfAnimation) {
      AppStorage.setOrCreate('shelfBookCloseAnimationUrl', this.bookUrl);
      AppStorage.setOrCreate('shelfBookCloseAnimationNonce', Date.now());
    }
    router.back();
  }

  paginateReaderSourceText(source: string, chapterIndex: number = this.currentChapterIndex): ReaderPaginationResult {
    const text = source || '';
    if (!text || this.pageViewWidth <= 0 || this.pageViewHeight <= 0) {
      return {
        source: text,
        pages: text ? [text] : [],
        starts: text ? [0] : [],
        ends: text ? [text.length] : []
      };
    }

    const horizontalPadding = this.readerMarginLeft + this.readerMarginRight;
    const verticalPadding = this.readerMarginTop + this.getReaderContentBottomPadding() +
      this.getReaderBottomInfoBarHeight();
    const columnWidth = this.isLandscapeDoublePageActive() ? this.pageViewWidth / 2 : this.pageViewWidth;
    const availableWidth = Math.max(1, columnWidth - horizontalPadding);
    const availableHeight = Math.max(1, this.pageViewHeight - verticalPadding);
    const measuredAvailableHeight = this.toMeasurePx(availableHeight) + this.getReaderPaginationHeightTolerancePx();
    const pages: string[] = [];
    const starts: number[] = [];
    const ends: number[] = [];
    let cursor = 0;

    while (cursor < text.length) {
      const end = this.findMeasuredPageEnd(text, cursor, availableWidth, measuredAvailableHeight, chapterIndex);
      if (end <= cursor) {
        break;
      }
      this.pushReaderPage(text, cursor, end, pages, starts, ends);
      cursor = end;
    }

    return {
      source: text,
      pages: pages.length > 0 ? pages : [text],
      starts: starts.length > 0 ? starts : [0],
      ends: ends.length > 0 ? ends : [text.length]
    };
  }

  buildReaderPaginationCacheKey(chapterIndex: number, source: string): string {
    return `reader_page_v6_${chapterIndex}_${this.pageViewWidth}_${this.pageViewHeight}_` +
      `${this.isLandscapeDoublePageActive()}_${this.readerTypographyCacheIdentity()}_` +
      `${source.length}_${this.hashText(source)}`;
  }

  readerTypographyCacheIdentity(): string {
    const regexIdentity = `${this.readerRegexFontEnabled}_${this.readerRegexFontRulesRaw}_` +
      `${this.readerRegexFontPattern}_${this.readerRegexFontMode}_${this.readerRegexFontFamily}_` +
      `${this.readerRegexFontSize}_${this.readerRegexShadowColor}`;
    return `${this.readerFontSize}_${this.readerLineHeight}_${this.readerParagraphSpacing}_` +
      `${this.readerMarginLeft}_${this.readerMarginRight}_${this.readerMarginTop}_${this.readerMarginBottom}_` +
      `${this.readerBodyFontMode}_${this.readerBodyFontFamily}_${this.getBodyReaderFontFamily()}_` +
      `${this.readerTitleFontSize}_${this.readerTitleFontMode}_${this.readerTitleFontFamily}_` +
      `${this.getTitleReaderFontFamily()}_${this.getReaderFontFamily()}_${this.hashText(regexIdentity)}`;
  }

  getCachedReaderPagination(chapterIndex: number, source: string): ReaderPaginationResult | null {
    const key = this.buildReaderPaginationCacheKey(chapterIndex, source);
    return this.readerPaginationCache.get(key) || null;
  }

  getOrCreateReaderPagination(chapterIndex: number, source: string): ReaderPaginationResult {
    const key = this.buildReaderPaginationCacheKey(chapterIndex, source);
    const cached = this.readerPaginationCache.get(key);
    if (cached) {
      return cached;
    }
    const result = this.paginateReaderSourceText(source, chapterIndex);
    this.readerPaginationCache.set(key, result);
    while (this.readerPaginationCache.size > 6) {
      const oldestKey = this.readerPaginationCache.keys().next().value as string | undefined;
      if (!oldestKey) {
        break;
      }
      this.readerPaginationCache.delete(oldestKey);
    }
    return result;
  }

  preloadNextChapterPaginationLater(delayMs: number = 800): void {
    if (!this.readerPreloadEnabled || !this.hasPagedReaderArea() ||
      this.currentChapterIndex >= this.chapters.length - 1) {
      return;
    }
    const sourceChapterIndex = this.currentChapterIndex;
    const targetChapterIndex = sourceChapterIndex + 1;
    const serial = ++this.adjacentPaginationPreloadSerial;
    setTimeout(() => {
      if (serial !== this.adjacentPaginationPreloadSerial ||
        this.currentChapterIndex !== sourceChapterIndex) {
        return;
      }
      ReadBookEngine.get().peekContent(targetChapterIndex)
        .then((body: string) => {
          if (!body || serial !== this.adjacentPaginationPreloadSerial ||
            this.currentChapterIndex !== sourceChapterIndex) {
            return;
          }
          const source = this.buildPagedSourceText(targetChapterIndex, this.applyReaderContentRules(body));
          if (!this.getCachedReaderPagination(targetChapterIndex, source)) {
            this.getOrCreateReaderPagination(targetChapterIndex, source);
          }
        })
        .catch((err: Error) => {
          console.error('预排版下一章失败:', err);
        });
    }, Math.max(0, delayMs));
  }

  paginateContent(sourceContent?: string, chapterIndex: number = this.currentChapterIndex) {
    const content = sourceContent !== undefined ? sourceContent : this.content;
    if (!content) {
      this.contentPages = [];
      this.pagedContentText = '';
      this.contentPageStarts = [];
      this.contentPageEnds = [];
      this.setCurrentPageText('');
      return;
    }

    if (!this.hasPagedReaderArea()) {
      this.contentPages = [];
      this.pagedContentText = '';
      this.contentPageStarts = [];
      this.contentPageEnds = [];
      this.setCurrentPageText(content);
      return;
    }

    const safeChapterIndex = this.clampChapterIndex(chapterIndex);
    const pagedSource = this.buildPagedSourceText(safeChapterIndex, content);
    const result = this.getOrCreateReaderPagination(safeChapterIndex, pagedSource);
    const pages: string[] = result.pages.length > 0 ? result.pages : [content];
    this.pagedContentText = result.source;
    this.contentPages = pages;
    this.contentPageStarts = result.starts.length > 0 ? result.starts : [0];
    this.contentPageEnds = result.ends.length > 0 ? result.ends : [this.pagedContentText.length];
    this.restorePendingPageIndex();
    if (this.currentPageIndex >= pages.length) {
      this.currentPageIndex = Math.max(0, pages.length - 1);
    }
    const pageIndex = this.normalizeReaderSpreadPageIndex(
      Math.max(0, Math.min(this.currentPageIndex, Math.max(0, pages.length - 1)))
    );
    this.currentPageIndex = pageIndex;
    this.setCurrentPageText(pages[pageIndex] || '');
    this.readerInitialPageReady = true;
  }

  async turnNext() {
    await this.runPageTurnAnimation(1, this.readerPageTurnMode === 1 ? 'slide' : 'tap');
  }

  async turnPrev() {
    await this.runPageTurnAnimation(-1, this.readerPageTurnMode === 1 ? 'slide' : 'tap');
  }

  preloadReaderContent(): void {
    if (this.chapters.length === 0 || !this.readerPreloadEnabled) {
      return;
    }
    const engine = ReadBookEngine.get();
    engine.preloadAround(this.currentChapterIndex, this.normalizePreloadChapterCount(this.readerPreloadChapterCount), 0);
    this.preloadNextChapterPaginationLater();
  }

  normalizePreloadChapterCount(count: number): number {
    return Math.max(1, Math.min(Math.round(count), 10));
  }

  preloadReaderContentLater(): void {
    setTimeout(() => {
      this.preloadReaderContent();
    }, 0);
  }

  canTurnPage(direction: number): boolean {
    if (this.chapters.length === 0) {
      return false;
    }
    if (direction > 0) {
      return this.currentPageIndex + this.getReaderPageTurnStep() < this.contentPages.length ||
        this.currentChapterIndex < this.chapters.length - 1;
    }
    return this.currentPageIndex > 0 || this.currentChapterIndex > 0;
  }

  async applyPageTurn(direction: number, targetPreview: PageTurnPreview | null = null,
    commitText: boolean = true): Promise<void> {
    const localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
    if (direction > 0) {
      if (localPageIndex >= 0) {
        this.applyLocalPageTurnTarget(localPageIndex, targetPreview, commitText);
        if (this.contentPages.length - this.currentPageIndex <= 3) {
          this.preloadReaderContentLater();
          this.preloadNextChapterPaginationLater(0);
        }
        this.saveReadingProgress();
      } else {
        await this.loadNextChapter();
      }
      return;
    }

    if (localPageIndex >= 0) {
      this.applyLocalPageTurnTarget(localPageIndex, targetPreview, commitText);
      if (this.currentPageIndex <= 2) {
        this.preloadReaderContentLater();
      }
      this.saveReadingProgress();
    } else {
      await this.loadPrevChapter(true);
    }
  }

  applyLocalPageTurnTarget(targetPageIndex: number, targetPreview: PageTurnPreview | null = null,
    commitText: boolean = true): void {
    const safePageIndex = Math.max(0, Math.min(targetPageIndex, Math.max(0, this.contentPages.length - 1)));
    this.currentPageIndex = safePageIndex;
    if (!commitText) {
      return;
    }
    if (targetPreview && targetPreview.chapterIndex === this.currentChapterIndex &&
      targetPreview.pageIndex === safePageIndex && targetPreview.text) {
      this.setCurrentPageText(targetPreview.text);
      this.refreshReaderTextRender();
      return;
    }
    if (this.pageTurnIncomingChapterIndex === this.currentChapterIndex &&
      this.pageTurnIncomingPageIndex === safePageIndex && this.pageTurnIncomingText) {
      this.setCurrentPageText(this.pageTurnIncomingText);
      this.refreshReaderTextRender();
      return;
    }
    this.syncCurrentPageText();
    this.refreshReaderTextRender();
  }

  capturePageTurnCommitTarget(direction: number): PageTurnPreview | null {
    const localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
    if (localPageIndex >= 0) {
      return {
        text: this.getPageText(localPageIndex),
        secondaryText: this.getSecondaryPageText(localPageIndex),
        pageIndex: localPageIndex,
        chapterIndex: this.currentChapterIndex
      };
    }
    if (this.pageTurnIncomingText) {
      return {
        text: this.pageTurnIncomingText,
        secondaryText: this.pageTurnIncomingSecondaryText,
        pageIndex: this.pageTurnIncomingPageIndex,
        chapterIndex: this.pageTurnIncomingChapterIndex
      };
    }
    return null;
  }
  async runPageTurnAnimation(direction: number, style: string): Promise<void> {
    if (this.ttsAutoTurningPage || this.isPageTurning) {
      return;
    }
    if (!this.canTurnPage(direction)) {
      this.resetSlidePageEffect();
      if (direction > 0 && this.chapters.length > 0 &&
        this.currentChapterIndex >= this.chapters.length - 1 &&
        this.getLocalPageTurnTargetPageIndex(1) < 0) {
        promptAction.showToast({ message: '本书已阅读完成' });
      }
      return;
    }
    const resumeTtsAfterTurn = this.isTtsSpeaking || this.ttsReader.isSpeaking();
    if (resumeTtsAfterTurn) {
      this.stopTtsReading();
      await this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING);
    }
    this.isPageTurning = true;
    let turnCompleted = false;
    try {
      if (!this.isPageTurnAnimationEnabled()) {
        await this.runNoAnimationPageTurn(direction);
      } else if (style === 'slide' || style === 'gesture') {
        await this.runSlidePageTurn(direction);
      } else {
        await this.runTapPageTurn(direction);
      }
      turnCompleted = true;
    } finally {
      this.isPageTurning = false;
    }
    if (resumeTtsAfterTurn && turnCompleted) {
      await this.startTtsReadingFromCurrentPosition(false);
    }
  }

  async runNoAnimationPageTurn(direction: number): Promise<void> {
    this.readerTouchActive = false;
    this.readerPanActive = false;
    this.resetSlidePageState();
    const localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
    if (localPageIndex >= 0) {
      this.currentPageIndex = localPageIndex;
      const targetText = this.getPageText(localPageIndex);
      this.commitVisibleCurrentPageText(targetText);
      this.finishPageTurnAnimation();
      if (direction > 0 && this.contentPages.length - this.currentPageIndex <= 3) {
        this.preloadReaderContentLater();
        this.preloadNextChapterPaginationLater(0);
      } else if (direction < 0 && this.currentPageIndex <= 2) {
        this.preloadReaderContentLater();
      }
      this.saveReadingProgress();
      this.commitCurrentPageTextLater(this.currentChapterIndex, this.currentPageIndex, targetText);
      return;
    }

    if (direction > 0) {
      await this.loadNextChapter();
    } else {
      await this.loadPrevChapter(true);
    }
    const targetText = this.getCurrentPageText();
    this.finishPageTurnAnimation();
    this.commitVisibleCurrentPageText(targetText, true);
    this.commitCurrentPageTextLater(this.currentChapterIndex, this.currentPageIndex, targetText);
  }

  commitVisibleCurrentPageText(text: string = this.visibleCurrentPageText(), forceRender: boolean = false): void {
    const nextText = text || '';
    if (!forceRender && this.currentPageText === nextText && this.displayPageText === nextText &&
      this.displayPageChapterIndex === this.currentChapterIndex && this.displayPageIndex === this.currentPageIndex) {
      return;
    }
    this.currentPageText = nextText;
    this.displayPageText = nextText;
    this.displayPageChapterIndex = this.currentChapterIndex;
    this.displayPageIndex = this.currentPageIndex;
    this.displayPageRenderKey++;
    this.forceCurrentReaderPageRender();
  }

  commitVisibleCurrentPageTextLater(chapterIndex: number, pageIndex: number): void {
    this.commitCurrentPageTextLater(chapterIndex, pageIndex, '');
  }

  commitCurrentPageTextLater(chapterIndex: number, pageIndex: number, expectedText: string): void {
    this.commitCurrentPageTextAfterDelay(chapterIndex, pageIndex, expectedText, 0);
  }

  commitCurrentPageTextAfterDelay(chapterIndex: number, pageIndex: number, expectedText: string, delayMs: number): void {
    setTimeout(() => {
      if (this.currentChapterIndex === chapterIndex && this.currentPageIndex === pageIndex) {
        const liveText = this.getCurrentPageText();
        const pageText = liveText || expectedText;
        this.commitVisibleCurrentPageText(pageText);
      }
    }, delayMs);
  }

  async runLegacyPageTurn(direction: number): Promise<void> {
    const subtleOffset = direction > 0 ? -10 : 10;
    this.pageSlideDirection = 0;
    this.pageTransitionOpacity = 1;
    this.pageTurnIncomingOpacity = 1;
    this.setPageTurnIncomingState(this.currentPageIndex, '', false);
    this.clearPageTurnPreviewState();
    animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.setPageSlideAxisOffset(subtleOffset);
    });
    await this.delay(130);
    await this.applyPageTurn(direction, null, false);
    this.finishAnimatedPageTurn();
  }

  async runTapPageTurn(direction: number): Promise<void> {
    const distance = this.getPageTurnDistance();
    this.prepareSlidePageTurn(direction, 0);
    const targetPreview = this.capturePageTurnCommitTarget(direction);
    animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.setPageSlideAxisOffset(direction > 0 ? -distance : distance);
      this.pageTransitionOpacity = 1;
    });
    await this.delay(230);
    await this.applyPageTurn(direction, targetPreview, false);
    this.finishAnimatedPageTurn();
  }

  async runSlidePageTurn(direction: number): Promise<void> {
    const distance = this.getPageTurnDistance();
    this.prepareSlidePageTurn(direction, this.getPageSlideAxisOffset());
    const targetPreview = this.capturePageTurnCommitTarget(direction);
    const targetOffset = direction > 0 ? -distance : distance;
    const remaining = Math.abs(targetOffset - this.getPageSlideAxisOffset());
    const duration = Math.max(90, Math.min(240, Math.round(240 * remaining / distance)));
    animateTo({ duration: duration, curve: Curve.EaseOut }, () => {
      this.setPageSlideAxisOffset(targetOffset);
      this.pageTransitionOpacity = 1;
    });
    await this.delay(duration + 10);
    await this.applyPageTurn(direction, targetPreview, false);
    this.finishAnimatedPageTurn();
  }

  finishAnimatedPageTurn(): void {
    const chapterIndex = this.currentChapterIndex;
    const pageIndex = this.currentPageIndex;
    const targetText = this.getCurrentPageText();
    this.finishPageTurnAnimation();
    this.commitVisibleCurrentPageText(targetText, true);
    this.commitCurrentPageTextLater(chapterIndex, pageIndex, targetText);
  }

  prepareIncomingPageTurn(direction: number): void {
    this.updatePageTurnIncomingForDirection(direction);
    this.pageTurnIncomingX = 0;
    this.pageTurnIncomingOpacity = 1;
  }

  prepareSlidePageTurn(direction: number, offset: number): void {
    const distance = this.getPageTurnDistance();
    const clampedOffset = Math.max(-distance, Math.min(distance, offset));
    this.pageSlideDirection = direction;
    this.setPageSlideAxisOffset(clampedOffset);
    this.pageTransitionOpacity = 1;
    this.pageTurnIncomingOpacity = 1;
    this.prepareIncomingPageTurn(direction);
  }

  finishPageTurnAnimation(): void {
    this.pageTransitionX = 0;
    this.pageTransitionOpacity = 1;
    this.pageSlideOffsetX = 0;
    this.pageSlideOffsetY = 0;
    this.pageSlideDirection = 0;
    this.pageTurnIncomingX = 0;
    this.pageTurnIncomingOpacity = 1;
    this.setPageTurnIncomingState(this.currentPageIndex, '', false);
    this.clearPageTurnPreviewState();
    this.isPageTurning = false;
  }

  finishPageTurnAnimationLater(): void {
    const serial = ++this.slideResetSerial;
    setTimeout(() => {
      if (serial === this.slideResetSerial) {
        this.finishPageTurnAnimation();
        this.refreshReaderTextRender();
      }
    }, 0);
  }

  setPageTurnIncomingState(pageIndex: number, text: string, animating: boolean = true,
    chapterIndex: number = this.currentChapterIndex, secondaryText: string = ''): void {
    const safeText = text || '';
    const safeSecondaryText = secondaryText || '';
    const nextAnimating = animating && !!safeText;
    if (this.pageTurnIncomingPageIndex !== pageIndex || this.pageTurnIncomingChapterIndex !== chapterIndex ||
      this.pageTurnIncomingText !== safeText || this.pageTurnIncomingSecondaryText !== safeSecondaryText ||
      this.pageTurnAnimating !== nextAnimating) {
      this.pageTurnIncomingRenderVersion++;
    }
    this.pageTurnIncomingPageIndex = pageIndex;
    this.pageTurnIncomingChapterIndex = chapterIndex;
    this.pageTurnIncomingText = safeText;
    this.pageTurnIncomingSecondaryText = safeSecondaryText;
    this.pageTurnAnimating = nextAnimating;
  }

  getPageTurnTargetText(direction: number): string {
    const localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
    if (localPageIndex >= 0) {
      return this.getPageText(localPageIndex);
    }

    const targetChapterIndex = this.getAdjacentPageTurnChapterIndex(direction);
    if (targetChapterIndex >= 0) {
      const preview = this.buildCachedAdjacentPageTurnPreview(direction, targetChapterIndex);
      return preview.text || this.getPageTurnLoadingText(targetChapterIndex);
    }
    return '';
  }

  getPageTurnTargetPageIndex(direction: number = 0): number {
    const localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
    if (localPageIndex >= 0) {
      return localPageIndex;
    }
    return direction === 0 ? this.currentPageIndex : this.pageTurnIncomingPageIndex;
  }

  getLocalPageTurnTargetPageIndex(direction: number): number {
    const step = this.getReaderPageTurnStep();
    if (direction > 0 && this.currentPageIndex + step < this.contentPages.length) {
      return this.currentPageIndex + step;
    }
    if (direction < 0 && this.currentPageIndex > 0) {
      return Math.max(0, this.currentPageIndex - step);
    }
    return -1;
  }

  getAdjacentPageTurnChapterIndex(direction: number): number {
    if (direction > 0 && this.currentPageIndex + this.getReaderPageTurnStep() >= this.contentPages.length &&
      this.currentChapterIndex < this.chapters.length - 1) {
      return this.currentChapterIndex + 1;
    }
    if (direction < 0 && this.currentPageIndex <= 0 && this.currentChapterIndex > 0) {
      return this.currentChapterIndex - 1;
    }
    return -1;
  }

  updatePageTurnIncomingForDirection(direction: number): void {
    const localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
    if (localPageIndex >= 0) {
      this.pageTurnPreviewKey = `local_${localPageIndex}`;
      this.setPageTurnIncomingState(localPageIndex, this.getPageText(localPageIndex), true,
        this.currentChapterIndex, this.getSecondaryPageText(localPageIndex));
      return;
    }

    const targetChapterIndex = this.getAdjacentPageTurnChapterIndex(direction);
    if (targetChapterIndex < 0) {
      this.setPageTurnIncomingState(this.currentPageIndex, '', false);
      return;
    }

    const key = this.buildPageTurnPreviewKey(direction, targetChapterIndex);
    if (this.pageTurnPreviewKey === key && this.pageTurnIncomingText &&
      this.pageTurnIncomingChapterIndex === targetChapterIndex) {
      return;
    }
    if (this.pageTurnPreviewKey !== key) {
      this.pageTurnPreviewKey = key;
    }

    const preview = this.buildCachedAdjacentPageTurnPreview(direction, targetChapterIndex);
    if (preview.text) {
      this.applyPageTurnPreview(preview);
      return;
    }

    this.setPageTurnIncomingState(0, this.getPageTurnLoadingText(targetChapterIndex), true, targetChapterIndex);
    this.loadAdjacentPageTurnPreview(direction, targetChapterIndex, key);
  }

  buildPageTurnPreviewKey(direction: number, chapterIndex: number): string {
    return `${direction}_${chapterIndex}_${this.pageViewWidth}_${this.pageViewHeight}_` +
      `${this.isLandscapeDoublePageActive()}_${this.readerTypographyCacheIdentity()}`;
  }

  buildCachedAdjacentPageTurnPreview(direction: number, chapterIndex: number): PageTurnPreview {
    const body = ReadBookEngine.get().getCachedContent(chapterIndex);
    if (!body) {
      return { text: '', pageIndex: 0, chapterIndex: chapterIndex };
    }
    return this.buildAdjacentPageTurnPreview(direction, chapterIndex, body);
  }

  buildAdjacentPageTurnPreview(direction: number, chapterIndex: number, body: string): PageTurnPreview {
    const source = this.buildPagedSourceText(chapterIndex, this.applyReaderContentRules(body));
    const result = this.getOrCreateReaderPagination(chapterIndex, source);
    if (result.pages.length === 0) {
      return { text: '', pageIndex: 0, chapterIndex: chapterIndex };
    }
    const pageIndex = direction > 0 ? 0 : this.normalizeReaderSpreadPageIndex(result.pages.length - 1);
    return {
      text: result.pages[pageIndex],
      secondaryText: this.isLandscapeDoublePageActive() ? (result.pages[pageIndex + 1] || '') : '',
      pageIndex: pageIndex,
      chapterIndex: chapterIndex
    };
  }

  getPageTurnLoadingText(chapterIndex: number): string {
    const title = this.getChapterTitle(chapterIndex).trim();
    return title ? `${title}\n\n正在加载章节内容...` : '正在加载章节内容...';
  }

  applyPageTurnPreview(preview: PageTurnPreview): void {
    this.setPageTurnIncomingState(preview.pageIndex, preview.text, true, preview.chapterIndex,
      preview.secondaryText || '');
    this.pageTurnIncomingOpacity = 1;
  }

  loadAdjacentPageTurnPreview(direction: number, chapterIndex: number, key: string): void {
    if (this.pageTurnPreviewLoadingKey === key) {
      return;
    }
    this.pageTurnPreviewLoadingKey = key;
    ReadBookEngine.get().peekContent(chapterIndex)
      .then((body: string) => {
        if (this.pageTurnPreviewKey !== key || this.pageSlideDirection !== direction) {
          return;
        }
        const preview = this.buildAdjacentPageTurnPreview(direction, chapterIndex, body);
        if (preview.text) {
          this.applyPageTurnPreview(preview);
        }
      })
      .catch((err: Error) => {
        console.error('加载翻页预览失败:', err);
      })
      .finally(() => {
        if (this.pageTurnPreviewLoadingKey === key) {
          this.pageTurnPreviewLoadingKey = '';
        }
      });
  }

  updateSlidePageEffect(offset: number): void {
    if (this.isPageTurning) {
      return;
    }
    if (!this.isPageTurnAnimationEnabled()) {
      this.resetSlidePageState();
      return;
    }
    const distance = this.getPageTurnDistance();
    const clamped = Math.max(-distance, Math.min(distance, offset));
    if (Math.abs(clamped) < 1) {
      this.resetSlidePageState();
      return;
    }
    const direction = clamped < 0 ? 1 : -1;
    if (!this.canTurnPage(direction)) {
      this.resetSlidePageState();
      return;
    }
    this.pageSlideDirection = direction;
    this.setPageSlideAxisOffset(clamped);
    this.pageTransitionOpacity = 1;
    this.pageTurnIncomingOpacity = 1;
    this.updatePageTurnIncomingForDirection(direction);
  }

  updateLegacySlidePageEffect(offset: number): void {
    const distance = this.getPageTurnDistance();
    const clamped = Math.max(-distance, Math.min(distance, offset));
    if (Math.abs(clamped) < 1) {
      this.resetSlidePageState();
      return;
    }
    const direction = clamped < 0 ? 1 : -1;
    if (!this.canTurnPage(direction)) {
      this.resetSlidePageState();
      return;
    }
    const subtleOffset = Math.min(10, Math.max(2, Math.abs(clamped) * 0.08));
    this.pageSlideDirection = 0;
    this.setPageSlideAxisOffset(direction > 0 ? -subtleOffset : subtleOffset);
    this.pageTransitionOpacity = 1;
    this.pageTurnIncomingOpacity = 1;
    this.setPageTurnIncomingState(this.currentPageIndex, '', false);
    this.clearPageTurnPreviewState();
  }

  rollbackSlidePageEffect(): void {
    const offset = Math.abs(this.getPageSlideAxisOffset());
    if (offset < 0.5) {
      this.resetSlidePageState();
      return;
    }
    const distance = this.getPageTurnDistance();
    const duration = Math.max(80, Math.min(180, Math.round(180 * offset / distance)));
    const serial = ++this.slideResetSerial;
    animateTo({ duration: duration, curve: Curve.EaseOut }, () => {
      this.setPageSlideAxisOffset(0);
      this.pageTransitionOpacity = 1;
      this.pageTurnIncomingOpacity = 1;
    });
    setTimeout(() => {
      if (this.slideResetSerial === serial && !this.isPageTurning) {
        this.resetSlidePageState();
      }
    }, duration + 20);
  }

  resetSlidePageEffect(): void {
    this.resetSlidePageState();
  }

  getVisiblePageTurnIncomingText(): string {
    if (!this.shouldRenderSlidingPageTurn()) {
      return '';
    }
    if (this.pageTurnIncomingText) {
      return this.pageTurnIncomingText;
    }
    if (this.pageSlideDirection === 0) {
      return '';
    }
    return this.getPageTurnTargetText(this.pageSlideDirection);
  }

  getVisiblePageTurnIncomingOpacity(): number {
    if (!this.shouldRenderSlidingPageTurn()) {
      return 0;
    }
    const type = this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType);
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE) {
      return Math.max(0, Math.min(1, this.pageTurnIncomingOpacity * this.getPageTurnProgress()));
    }
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return this.pageTurnIncomingOpacity;
    }
    return this.pageTurnIncomingOpacity;
  }

  getPageTurnWidth(): number {
    return Math.max(1, this.pageViewWidth > 0 ? this.pageViewWidth : 360);
  }

  getPageTurnHeight(): number {
    const contentHeight = this.pageViewHeight > 0 ? this.pageViewHeight : 640;
    return Math.max(1, contentHeight + this.getReaderPageContentTopPadding());
  }

  isVerticalPageTurnAnimation(): boolean {
    return this.readerPageTurnMode === 0;
  }

  isStackPageTurnAnimation(): boolean {
    return this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType) ===
      ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK;
  }

  getPageTurnDistance(): number {
    return this.isVerticalPageTurnAnimation() ? this.getPageTurnHeight() : this.getPageTurnWidth();
  }

  getPageSlideAxisOffset(): number {
    return this.isVerticalPageTurnAnimation() ? this.pageSlideOffsetY : this.pageSlideOffsetX;
  }

  setPageSlideAxisOffset(offset: number): void {
    if (this.isVerticalPageTurnAnimation()) {
      this.pageSlideOffsetX = 0;
      this.pageSlideOffsetY = offset;
      return;
    }
    this.pageSlideOffsetX = offset;
    this.pageSlideOffsetY = 0;
  }

  shouldRenderSlidingPageTurn(): boolean {
    return this.isPageTurnAnimationEnabled() && this.pageSlideDirection !== 0 &&
      this.canTurnPage(this.pageSlideDirection);
  }

  getPageTurnProgress(): number {
    const distance = this.getPageTurnDistance();
    if (distance <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(1, Math.abs(this.getPageSlideAxisOffset()) / distance));
  }

  getCurrentPageTurnX(): number {
    if (!this.shouldRenderSlidingPageTurn()) {
      return this.pageTransitionX + this.pageSlideOffsetX;
    }
    if (this.isVerticalPageTurnAnimation()) {
      return 0;
    }
    const type = this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType);
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE) {
      return 0;
    }
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return 0;
    }
    return this.pageTransitionX + this.pageSlideOffsetX;
  }

  getCurrentPageTurnY(): number {
    if (!this.shouldRenderSlidingPageTurn()) {
      return this.pageSlideOffsetY;
    }
    if (!this.isVerticalPageTurnAnimation()) {
      return 0;
    }
    const type = this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType);
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE) {
      return 0;
    }
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return 0;
    }
    return this.pageSlideOffsetY;
  }

  getCurrentPageTurnOpacity(): number {
    if (!this.shouldRenderSlidingPageTurn()) {
      return this.pageTransitionOpacity;
    }
    const type = this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType);
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE) {
      return Math.max(0.12, 1 - this.getPageTurnProgress());
    }
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return 1;
    }
    return this.pageTransitionOpacity;
  }

  getSlideIncomingX(direction: number, offsetX: number, width: number = this.getPageTurnWidth()): number {
    const type = this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType);
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE) {
      return 0;
    }
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return direction > 0 ? width + offsetX : offsetX - width;
    }
    return direction > 0 ? width + offsetX : offsetX - width;
  }

  getIncomingSlideX(): number {
    if (this.pageSlideDirection === 0 || this.isVerticalPageTurnAnimation()) {
      return 0;
    }
    return this.getSlideIncomingX(this.pageSlideDirection, this.pageSlideOffsetX);
  }

  getSlideIncomingY(direction: number, offsetY: number, height: number = this.getPageTurnHeight()): number {
    const type = this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType);
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE) {
      return 0;
    }
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return direction > 0 ? height + offsetY : offsetY - height;
    }
    return direction > 0 ? height + offsetY : offsetY - height;
  }

  getIncomingSlideY(): number {
    if (this.pageSlideDirection === 0 || !this.isVerticalPageTurnAnimation()) {
      return 0;
    }
    return this.getSlideIncomingY(this.pageSlideDirection, this.pageSlideOffsetY);
  }

  resetSlidePageState(): void {
    this.pageSlideOffsetX = 0;
    this.pageSlideOffsetY = 0;
    this.pageSlideDirection = 0;
    this.pageTransitionOpacity = 1;
    this.pageTurnIncomingX = 0;
    this.pageTurnIncomingOpacity = 1;
    this.setPageTurnIncomingState(this.currentPageIndex, '', false);
    this.clearPageTurnPreviewState();
  }

  clearPageTurnPreviewState(): void {
    this.pageTurnPreviewKey = '';
    this.pageTurnPreviewLoadingKey = '';
  }

  buildBookPreview(): string {
    if (!this.book) return '';

    let text = `${this.book.name}\n\n作者：${this.book.author || '未知'}\n来源：${this.book.originName || this.book.origin}`;
    if (this.book.latestChapterTitle) {
      text += `\n最新章节：${this.book.latestChapterTitle}`;
    }
    if (this.book.intro) {
      text += `\n\n简介：${this.book.intro}`;
    }
    if (this.book.origin !== 'local') {
      this.updatePendingVerification();
      if (this.verificationUrl) {
        text += '\n\n当前书源需要先完成网页验证。请点击右上角“更多操作”，选择“登录”，完成后返回，再从该菜单选择“重试”。';
      } else {
        text += '\n\n当前书源暂未解析出目录。请点击右上角“更多操作”，选择“重试”重新获取，或在书源管理中为该书源补充目录规则。';
      }
    }
    return text;
  }

  async jumpToAdjacentChapterFirstPage(direction: number): Promise<void> {
    const targetChapterIndex = this.currentChapterIndex + (direction > 0 ? 1 : -1);
    if (targetChapterIndex < 0) {
      promptAction.showToast({ message: '已经是第一章' });
      return;
    }
    if (targetChapterIndex >= this.chapters.length) {
      promptAction.showToast({ message: '本书已阅读完成' });
      return;
    }

    this.stopTtsReading();
    this.finishPageTurnAnimation();
    this.isLoading = true;
    this.loadStatus = '正在切换章节...';
    await this.delay(0);
    try {
      this.currentPageIndex = 0;
      this.pendingRestorePageIndex = 0;
      await this.loadContent(true, targetChapterIndex);
      if (this.currentChapterIndex !== targetChapterIndex) {
        return;
      }

      this.currentPageIndex = 0;
      this.pendingRestorePageIndex = -1;
      const targetPageText = this.contentPages[0] || this.content || '';
      this.setCurrentPageText(targetPageText);
      this.finishPageTurnAnimation();
      this.refreshReaderTextRender();
      await this.delay(16);
    } finally {
      this.isLoading = false;
      this.loadStatus = '';
    }
    this.saveReadingProgress();
  }

  async loadNextChapter(showLoading: boolean = false, showBoundaryToast: boolean = false): Promise<void> {
    if (this.currentChapterIndex >= this.chapters.length - 1) {
      if (showBoundaryToast) {
        promptAction.showToast({ message: '本书已阅读完成' });
      }
      return;
    }
    const targetChapterIndex = this.currentChapterIndex + 1;
    this.currentPageIndex = 0;
    this.pendingRestorePageIndex = 0;
    await this.loadContent(!showLoading, targetChapterIndex);
    this.saveReadingProgress();
  }

  async loadPrevChapter(toLastPage: boolean = false, showLoading: boolean = false,
    showBoundaryToast: boolean = false): Promise<void> {
    if (this.currentChapterIndex <= 0) {
      if (showBoundaryToast) {
        promptAction.showToast({ message: '已经是第一章' });
      }
      return;
    }
    const targetChapterIndex = this.currentChapterIndex - 1;
    this.currentPageIndex = 0;
    this.pendingRestorePageIndex = toLastPage ? Number.MAX_SAFE_INTEGER : 0;
    await this.loadContent(!showLoading, targetChapterIndex);
    this.saveReadingProgress();
  }
}
