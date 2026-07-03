import { router, window, promptAction, MeasureOptions } from '@kit.ArkUI';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { inputConsumer, KeyCode, Action, KeyEvent } from '@kit.InputKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import graphicsText from '@ohos.graphics.text';
import { Book, BookChapter, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { ReadBookEngine } from '../core/book/ReadBookEngine';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { WebBookService } from '../core/book/WebBookService';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { SystemTtsReader, TtsChunk, TtsVoiceOption } from '../utils/SystemTtsReader';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderThemeHelper, ReaderThemeItem } from '../utils/ReaderThemeHelper';
import { ColorCodePicker } from '../components/ColorCodePicker';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { BookFieldSanitizer } from '../utils/BookFieldSanitizer';
import { CoverUrlNormalizer } from '../utils/CoverUrlNormalizer';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { BookCoverCache } from '../utils/BookCoverCache';
import { CoverGallerySettings } from '../utils/CoverGallerySettings';

interface ReadTextSlice {
  text: string;
  start: number;
  end: number;
  highlighted: boolean;
  ruleIndex: number;
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

class ReaderRegexFontRule {
  id: string = '';
  name: string = '';
  pattern: string = '';
  fontMode: string = 'global';
  fontFamily: string = '';
  fontSize: number = 20;
  highlightColorEnabled: boolean = false;
  shadowColor: string = '';
  expanded: boolean = true;
}

class ReaderRegexFontRulesData {
  rules: ReaderRegexFontRule[] = [];
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
  pageIndex: number;
  chapterIndex: number;
}

@Entry
@Component
struct ReadBookPage {
  @State bookUrl: string = '';
  @State book: Book | null = null;
  @State chapters: BookChapter[] = [];
  @State currentChapterIndex: number = 0;
  @State content: string = '';
  @State isLoading: boolean = false;
  @State showMenu: boolean = false;
  @State showToc: boolean = false;
  @State showSettings: boolean = false;
  @State settingsPanelTab: number = 0;
  @State loadStatus: string = '';
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
  @State pageRenderVersion: number = 0;
  @State chapterJumpRenderGeneration: number = 0;
  @State pageViewWidth: number = 0;
  @State pageViewHeight: number = 0;
  @State statusBarSafeHeight: number = 0;
  @State isTtsSpeaking: boolean = false;
  @State ttsMediaControlsExpanded: boolean = false;
  @State ttsMediaImage: string = '';
  @State ttsDisplayText: string = '';
  @State ttsHighlightStart: number = -1;
  @State ttsHighlightEnd: number = -1;
  private pendingRestorePageIndex: number = -1;
  private tocScroller: Scroller = new Scroller();
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
  private ttsMediaImageRefreshSerial: number = 0;
  private ttsMediaImageRaw: string = '';
  private ttsMediaPixelMap: image.PixelMap | null = null;
  private contentPageStarts: number[] = [];
  private contentPageEnds: number[] = [];
  private pagedContentText: string = '';
  private readerPaginationCache: Map<string, ReaderPaginationResult> = new Map();
  private adjacentPaginationPreloadSerial: number = 0;
  private pageTurnPreviewKey: string = '';
  private pageTurnPreviewLoadingKey: string = '';
  @State pageTransitionX: number = 0;
  @State pageTransitionOpacity: number = 1;
  @State pageSlideOffsetX: number = 0;
  @State pageSlideOffsetY: number = 0;
  @State pageSlideDirection: number = 0;
  @State pageTurnAnimating: boolean = false;
  @State pageTurnIncomingText: string = '';
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
  @StorageLink('readerLightThemeIndex') @Watch('onReaderThemeChanged') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') @Watch('onReaderThemeChanged') readerDarkThemeIndex: number = 0;
  @StorageLink('readerLightCustomThemeBackgroundColor') @Watch('onReaderThemeChanged') readerLightCustomThemeBackgroundColor: string = ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerLightCustomThemeTextColor') @Watch('onReaderThemeChanged') readerLightCustomThemeTextColor: string = ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR;
  @StorageLink('readerDarkCustomThemeBackgroundColor') @Watch('onReaderThemeChanged') readerDarkCustomThemeBackgroundColor: string = ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerDarkCustomThemeTextColor') @Watch('onReaderThemeChanged') readerDarkCustomThemeTextColor: string = ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR;
  @StorageLink('readerPageTurnMode') readerPageTurnMode: number = 1;
  @StorageLink('readerPageTurnAnimation') @Watch('onReaderPageTurnAnimationChanged') readerPageTurnAnimation: boolean = true;
  @StorageLink('readerVolumeTurnPage') @Watch('onReaderVolumeTurnPageChanged') readerVolumeTurnPage: boolean = false;
  @StorageLink('readerKeepScreenOn') readerKeepScreenOn: boolean = true;
  @StorageLink('readerExtendToStatusBar') @Watch('onReaderExtendToStatusBarChanged') readerExtendToStatusBar: boolean = false;
  @StorageLink('readerPreloadEnabled') @Watch('onReaderPreloadChanged') readerPreloadEnabled: boolean = true;
  @StorageLink('readerPreloadChapterCount') @Watch('onReaderPreloadChanged') readerPreloadChapterCount: number = 1;
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
  @StorageLink('launchShortcutNonce') @Watch('onLaunchShortcutChanged') launchShortcutNonce: number = 0;
  @State ttsVoices: TtsVoiceOption[] = [ReadBookPage.defaultTtsVoice()];
  @State ttsSelectedVoiceKey: string = '';
  @State ttsVoicesLoading: boolean = false;
  private volumeUpCallback?: (event: KeyEvent) => void;
  private volumeDownCallback?: (event: KeyEvent) => void;
  private lastLoggedReaderFontFamily: string = '';
  private readerFontChangeSerial: number = 0;

  async aboutToAppear() {
    this.enterReaderImmersive();
    this.updateVolumeKeySubscription();
    await this.loadReaderSettings();
    this.loadTtsSettingsAndVoices();
    const params = router.getParams() as Record<string, string>;
    if (params && params['bookUrl']) {
      this.bookUrl = params['bookUrl'];
      this.loadBook();
    }
  }

  onPageShow(): void {
    this.loadReaderSettings().catch((error: Error) => {
      console.warn('恢复阅读设置失败:', error);
    });
    this.reregisterReaderFontAfterShow(0);
    this.reregisterReaderFontAfterShow(120);
    this.syncTtsFocusAfterResumeLater(0);
    this.syncTtsFocusAfterResumeLater(180);
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
    if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking()) {
      this.ttsReader.shutdown();
    }
    this.saveReadingProgress();
    this.unregisterVolumeKeyTurn();
    this.exitReaderImmersive();
  }

  onLaunchShortcutChanged(): void {
    this.openPendingShortcut();
  }

  async openPendingShortcut(): Promise<void> {
    if (!RecentReadShortcut.isPending()) {
      return;
    }
    await this.saveReadingProgress();
    try {
      await RecentReadShortcut.openPending(getContext(this));
      RecentReadShortcut.consume();
    } catch (e) {
      RecentReadShortcut.consume();
      console.error('打开最近阅读快捷项失败:', e);
    }
  }

  enterReaderImmersive() {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      const bg = this.getBackgroundColor();
      const useLightIcons = this.isReaderThemeDark();
      const systemTextColor = useLightIcons ? '#D8D8D8' : '#2F261D';
      mainWindow.setWindowBackgroundColor(bg);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        isStatusBarLightIcon: useLightIcons,
        statusBarContentColor: systemTextColor,
        navigationBarColor: bg,
        isNavigationBarLightIcon: useLightIcons,
        navigationBarContentColor: systemTextColor
      });
      if (this.readerExtendToStatusBar) {
        mainWindow.setWindowLayoutFullScreen(true);
        mainWindow.setWindowSystemBarEnable(['navigation']);
        this.updateStatusBarSafeHeight(mainWindow);
      } else {
        mainWindow.setWindowLayoutFullScreen(true);
        mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
        this.updateStatusBarSafeHeight(mainWindow);
      }
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
      await this.markBookRecentlyRead();

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
      this.setReaderContent('加载失败,请重试');
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
    this.currentChapterIndex = 0;
    this.contentPages = [];
    this.contentPageStarts = [];
    this.contentPageEnds = [];
    this.pagedContentText = '';
    this.readerPaginationCache.clear();
    this.adjacentPaginationPreloadSerial++;
    this.currentPageIndex = 0;
    this.currentPageText = '';
    this.chapterJumpRenderGeneration = 0;
    this.pageViewWidth = 0;
    this.pageViewHeight = 0;
    this.pendingRestorePageIndex = -1;
    this.pageTransitionX = 0;
    this.pageTransitionOpacity = 1;
    this.pageSlideOffsetX = 0;
    this.pageSlideOffsetY = 0;
    this.pageSlideDirection = 0;
    this.pageTurnAnimating = false;
    this.pageTurnIncomingText = '';
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
      let loadedContent = body;
      if (body) {
        this.content = body;
        this.chapters = [...engine.chapters];
      } else {
        this.updatePendingVerification();
        const c = this.chapters[chapterIndex];
        loadedContent = this.verificationUrl ? `${c ? c.title : '当前章节'}\n\n该书源需要先完成网页验证。请点击阅读菜单里的「验证」，完成后返回并重试。` :
          (c ? `${c.title}\n\n章节内容加载失败，请稍后重试或尝试换源。` : '加载失败');
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
        this.content = body;
        this.chapters = [...engine.chapters];
        this.pendingRestorePageIndex = 0;
        this.currentPageIndex = 0;
        this.paginateContent(body);
        this.preloadReaderContent();
        await this.saveReadingProgress();
        promptAction.showToast({ message: '本章已刷新' });
      } else {
        this.updatePendingVerification();
        const chapter = this.chapters[this.currentChapterIndex];
        const loadedContent = this.verificationUrl ? `${chapter ? chapter.title : '当前章节'}\n\n该书源需要先完成网页验证。请点击阅读菜单里的「验证」，完成后返回并重试。` :
          (chapter ? `${chapter.title}\n\n章节内容刷新失败，请稍后重试或尝试换源。` : '刷新失败');
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

  shouldRenderPrimaryReaderContent(): boolean {
    return !this.isLoading || !!this.content;
  }

  isPagedReaderAwaitingPagination(): boolean {
    return !!this.content && this.contentPages.length === 0;
  }

  shouldShowReaderLoadingOverlay(): boolean {
    return this.shouldRenderPrimaryReaderContent() && (this.isLoading || this.isPagedReaderAwaitingPagination());
  }

  shouldBlockReaderInteraction(): boolean {
    return this.isLoading || this.isPagedReaderAwaitingPagination();
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
    .backgroundColor(this.getBackgroundColor())
  }

  build() {
    Stack() {
      Column() {
        if (!this.shouldRenderPrimaryReaderContent()) {
          this.readerLoadingPanel()
        } else {
          Column() {
            Stack() {
              if (this.chapterJumpRenderGeneration % 2 === 0) {
                if (this.readerPageTurnAnimation) {
                  this.readerSlidingPageTurnSurface(this.currentPageText, this.pageRenderVersion)
                } else {
                  this.readerCurrentPageSurface(this.pageRenderVersion, this.currentPageText)
                }
              } else {
                if (this.readerPageTurnAnimation) {
                  this.readerSlidingPageTurnSurfaceAlternate(this.currentPageText, this.pageRenderVersion)
                } else {
                  this.readerCurrentPageSurfaceAlternate(this.pageRenderVersion, this.currentPageText)
                }
              }
            }
            .width('100%')
            .layoutWeight(1)
            .clip(true)
            .onAreaChange((oldValue: Area, newValue: Area) => {
              this.updatePagedReaderArea(newValue);
            })

            this.readerBottomInfoBar()
          }
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getReaderTopSafePadding() })
      .backgroundColor(this.getBackgroundColor())
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

      if (this.shouldShowTtsMediaControls()) {
        this.ttsMediaControlsBar()
      }

      if (this.showMenu && !this.showToc && !this.showSettings) {
        this.menuDismissLayer()
      }

      if (this.showSettings) {
        this.settingsDismissLayer()
      }

      if (this.showMenu) {
        Column() {
          Row() {
            Row() {
              Text('<')
                .fontSize(24)
                .textAlign(TextAlign.Center)
            }
              .width(40)
              .height(56)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.exitReaderPage();
              })

            Text(this.book?.name || '')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.chapters.length > 0) {
              Button('刷新本章')
                .height(36)
                .fontSize(14)
                .margin({ right: 8 })
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.hideReaderPanels();
                  this.refreshCurrentChapter();
                })
            }

            if (this.book && this.book.origin !== 'local') {
              Button('换源')
                .height(36)
                .fontSize(14)
                .margin({ right: 8 })
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.openChangeSourceDialog();
                })
            }

            if (this.verificationUrl) {
              Button('验证')
                .height(36)
                .fontSize(14)
                .margin({ right: 8 })
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.openVerificationPage();
                })
            }

            if ((this.chapters.length === 0 && this.book?.origin !== 'local') || this.verificationUrl) {
              Button('重试')
                .height(36)
                .fontSize(14)
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.hideReaderPanels();
                  if (this.chapters.length === 0) {
                    this.retryFetchChapters();
                  } else {
                    this.loadContent();
                  }
                })
            }
          }
          .width('100%')
          .height(this.getTopOverlayHeight())
          .padding({ left: 16, right: 16, top: this.getTopControlSafePadding() })
          .backgroundColor(this.readerSolidPanelColor())
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .position({ x: 0, y: 0 })
      }

      if (this.showMenu && this.chapters.length > 0) {
        Column() {
          Row() {
            Text(this.getChapterTitle())
              .fontSize(14)
              .fontColor('#666')
              .layoutWeight(1)

            Text(`${this.currentChapterIndex + 1}/${this.chapters.length}`)
              .fontSize(14)
              .fontColor('#999')
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row() {
            Button('上一章')
              .fontSize(14)
              .layoutWeight(1)
              .margin({ right: 8 })
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(async () => {
                this.hideReaderPanels();
                await this.jumpToAdjacentChapterFirstPage(-1);
              })

            Button('目录')
              .fontSize(14)
              .layoutWeight(1)
              .margin({ right: 8 })
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.openTocPanel();
              })

            Button('下一章')
              .fontSize(14)
              .layoutWeight(1)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(async () => {
                this.hideReaderPanels();
                await this.jumpToAdjacentChapterFirstPage(1);
              })
          }
          .width('100%')
          .margin({ top: 16 })

          Row() {
            Button('设置')
              .fontSize(14)
              .layoutWeight(1)
              .margin({ right: 8 })
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.openSettingsPanel();
              })

            Button(this.isTtsSpeaking ? '停止朗读' : '朗读')
              .fontSize(14)
              .layoutWeight(1)
              .margin({ right: 8 })
              .backgroundColor(this.isTtsSpeaking ? '#E53935' : this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.toggleTtsReading();
              })

            Button('刷新目录')
              .fontSize(14)
              .layoutWeight(1)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.hideReaderPanels();
                this.retryFetchChapters();
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.readerSolidPanelColor())
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
      }

      if (this.showToc) {
        Row() {
          Column() {
            Row() {
              Text('目录')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)
              Button('关闭')
                .height(34)
                .fontSize(13)
                .borderRadius(17)
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.showToc = false;
                })
            }
            .width('100%')
            .height(this.getTopOverlayHeight())
            .padding({ left: 16, right: 16, top: this.getTopControlSafePadding() })

            List({ space: 2, scroller: this.tocScroller, initialIndex: this.getTocInitialIndex() }) {
              ForEach(this.chapters, (chapter: BookChapter, index: number) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Text(chapter.title)
                      .fontSize(15)
                      .fontColor(this.getTocTitleColor(chapter, index))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)

                    if (chapter.cacheDate > 0) {
                      Text('已缓存')
                        .fontSize(11)
                        .fontColor(this.isReaderThemeDark() ? '#7CC7A0' : '#1F8F55')
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor(this.isReaderThemeDark() ? '#24382F' : '#E6F4EC')
                        .borderRadius(4)
                    }
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                  .backgroundColor(index === this.currentChapterIndex ? this.tocSelectedBackgroundColor() : '#00000000')
                    .onClick(async () => {
                      const targetChapterIndex = index;
                      this.currentPageIndex = 0;
                      this.pendingRestorePageIndex = 0;
                      this.showToc = false;
                      this.showMenu = false;
                      await this.loadContent(false, targetChapterIndex);
                      await this.saveReadingProgress();
                    })
                }
              })
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.On)
            .scrollBarWidth(16)
            .scrollBarColor(this.isReaderThemeDark() ? '#668A8F98' : '#667A6F63')
          }
          .width('82%')
          .height('100%')
          .backgroundColor(this.readerSolidPanelColor())

          Blank()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.showToc = false;
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
      }

      if (this.showSettings) {
        this.settingsPanel()
      }

      if (this.showChangeSourceDialog) {
        this.changeSourceDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getBackgroundColor())
    .expandSafeArea([SafeAreaType.SYSTEM], this.getReaderSafeAreaEdges())
  }

  getChapterTitle(chapterIndex: number = this.currentChapterIndex): string {
    if (this.chapters.length === 0) return '暂无目录';
    const chapter = this.chapters[this.clampChapterIndex(chapterIndex)];
    return chapter ? chapter.title : '';
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
    return `${this.currentChapterIndex + 1}/${this.chapters.length} · ${this.currentPageIndex + 1}/${this.contentPages.length}`;
  }

  getChapterInfoText(): string {
    if (this.chapters.length === 0) {
      return this.book?.name || '暂无目录';
    }
    const index = this.clampChapterIndex(this.currentChapterIndex);
    const chapter = this.chapters[index];
    return `${index + 1}/${this.chapters.length} ${chapter?.title || this.getChapterTitle()}`;
  }

  getPageInfoText(): string {
    if (this.contentPages.length === 0) {
      return '1/1';
    }
    const index = Math.max(0, Math.min(this.currentPageIndex, this.contentPages.length - 1));
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

  syncCurrentPageText(): void {
    this.setCurrentPageText(this.getCurrentPageText());
  }

  setCurrentPageText(text: string): void {
    const nextText = text || '';
    if (this.currentPageText !== nextText) {
      this.chapterJumpRenderGeneration++;
    }
    this.currentPageText = nextText;
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
    const height = this.parseAreaDimension(area.height);
    if (width <= 0 || height <= 0) {
      return;
    }
    if (Math.abs(this.pageViewWidth - width) < 0.5 && Math.abs(this.pageViewHeight - height) < 0.5) {
      return;
    }
    this.pageViewWidth = width;
    this.pageViewHeight = height;
    this.paginateContent(this.content);
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

  getTextColor(): string {
    return this.currentReaderTheme().textColor;
  }

  currentReaderThemeIndex(): number {
    return this.appDarkMode ? this.readerDarkThemeIndex : this.readerLightThemeIndex;
  }

  currentReaderThemes(): ReaderThemeItem[] {
    return ReaderThemeHelper.themes(
      this.appDarkMode,
      this.currentCustomThemeBackgroundColor(),
      this.currentCustomThemeTextColor()
    );
  }

  currentReaderTheme(): ReaderThemeItem {
    return ReaderThemeHelper.themeAt(
      this.appDarkMode,
      this.currentReaderThemeIndex(),
      this.currentCustomThemeBackgroundColor(),
      this.currentCustomThemeTextColor()
    );
  }

  currentCustomThemeBackgroundColor(): string {
    return this.appDarkMode ? this.readerDarkCustomThemeBackgroundColor : this.readerLightCustomThemeBackgroundColor;
  }

  currentCustomThemeTextColor(): string {
    return this.appDarkMode ? this.readerDarkCustomThemeTextColor : this.readerLightCustomThemeTextColor;
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
      return this.getSystemReaderFontFamily();
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
    return this.readerFontFamily || this.getSystemReaderFontFamily();
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
    this.readerLightThemeIndex = settings.lightThemeIndex;
    this.readerDarkThemeIndex = settings.darkThemeIndex;
    this.readerLightCustomThemeBackgroundColor = settings.lightCustomThemeBackgroundColor;
    this.readerLightCustomThemeTextColor = settings.lightCustomThemeTextColor;
    this.readerDarkCustomThemeBackgroundColor = settings.darkCustomThemeBackgroundColor;
    this.readerDarkCustomThemeTextColor = settings.darkCustomThemeTextColor;
    this.readerPageTurnMode = settings.pageTurnMode;
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
    this.showToc = true;
    this.showMenu = false;
    this.scrollTocToCurrentChapter(false);
  }

  openSettingsPanel(): void {
    this.settingsPanelTab = 0;
    this.showSettings = true;
    this.showMenu = false;
    this.loadTtsSettingsAndVoices();
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
    this.ttsSelectedVoiceKey = this.ttsVoiceKey(voice);
    this.saveTtsSettings();
    if (shouldResume) {
      this.startTtsReadingFromCurrentPosition(false).catch((e: Error) => {
        console.warn('切换朗读音色后恢复朗读失败:', e);
      });
    }
  }

  applyTtsSpeed(value: number): void {
    this.ttsSpeed = Math.max(0.5, Math.min(2, Math.round(value * 10) / 10));
    this.saveTtsSettings();
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      this.updateTtsAvSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY).catch((e: Error) => {
        console.warn('更新朗读倍速媒体状态失败:', e);
      });
    }
  }

  currentTtsVoiceKey(): string {
    const matched = this.findCurrentTtsVoice();
    return matched ? this.ttsVoiceKey(matched) :
      `${this.ttsPerson}_${this.ttsOnline}_${this.ttsLanguage || 'zh-CN'}_${this.ttsStyle || ''}_`;
  }

  findCurrentTtsVoice(): TtsVoiceOption | undefined {
    return this.ttsVoices.find((voice: TtsVoiceOption) => this.isCurrentTtsVoice(voice));
  }

  isCurrentTtsVoice(voice: TtsVoiceOption): boolean {
    return voice.id === this.ttsPerson && voice.online === this.ttsOnline &&
      (voice.style || '') === (this.ttsStyle || '') &&
      this.sameTtsLanguage(voice.language || 'zh-CN', this.ttsLanguage || 'zh-CN');
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

  getTocInitialIndex(): number {
    if (this.chapters.length === 0) {
      return 0;
    }
    return Math.max(0, Math.min(this.currentChapterIndex - 4, this.chapters.length - 1));
  }

  scrollTocToCurrentChapter(smooth: boolean = true): void {
    if (this.chapters.length === 0) {
      return;
    }
    const index = Math.max(0, Math.min(this.currentChapterIndex, this.chapters.length - 1));
    setTimeout(() => {
      try {
        this.tocScroller.scrollToIndex(index, smooth, ScrollAlign.CENTER);
      } catch (e) {
        console.warn('定位目录当前章节失败:', e);
      }
    }, 50);
  }

  getSubTextColor(): string {
    return this.currentReaderTheme().subTextColor;
  }

  accentColor(): string {
    return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  buttonColor(): string {
    return this.appDarkMode ? this.appDarkButtonColor : this.appLightButtonColor;
  }

  tocSelectedBackgroundColor(): string {
    const color = this.accentColor();
    if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
      return `#11${color.substring(1)}`;
    }
    return this.appDarkMode ? '#112A6FCC' : '#11007DFF';
  }

  readerGlassPanelColor(): string {
    return this.readerSolidPanelColor();
  }

  readerSolidPanelColor(): string {
    return this.isReaderThemeDark() ? '#191B1F' : '#FFFFFF';
  }

  getReaderSafeAreaEdges(): SafeAreaEdge[] {
    return this.readerExtendToStatusBar ? [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM] : [SafeAreaEdge.BOTTOM];
  }

  getReaderTopSafePadding(): number {
    return this.readerExtendToStatusBar ? 0 : this.statusBarSafeHeight;
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

  restorePendingPageIndex(): void {
    if (this.pendingRestorePageIndex < 0) {
      return;
    }
    const maxPage = Math.max(0, this.contentPages.length - 1);
    this.currentPageIndex = Math.max(0, Math.min(this.pendingRestorePageIndex, maxPage));
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
      .backgroundColor(this.getBackgroundColor())
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
  }

  openChangeSourceDialog(): void {
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
    this.isSwitchingSource = false;
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

  async saveReadingProgress() {
    if (!this.book || this.chapters.length === 0) {
      return;
    }
    if (!this.canSaveReadingProgress()) {
      return;
    }
    const engine = ReadBookEngine.get();
    const chapterIndex = this.clampChapterIndex(this.currentChapterIndex);
    const pageIndex = Math.max(0, Math.min(this.currentPageIndex, Math.max(0, this.contentPages.length - 1)));
    this.currentChapterIndex = chapterIndex;
    this.currentPageIndex = pageIndex;
    this.book.durChapterIndex = chapterIndex;
    this.book.durChapterPos = pageIndex;
    const now = Date.now();
    this.book.durChapterTitle = this.getChapterTitle();
    this.book.durChapterTime = now;
    this.book.putVariable('lastReadTime', `${now}`);
    engine.curIdx = chapterIndex;
    engine.curPos = pageIndex;
    engine.book = this.book;
    const shouldRefreshRecentCard = chapterIndex !== this.lastRecentReadCardChapterIndex;
    this.lastRecentReadCardChapterIndex = chapterIndex;
    try {
      const db = AppDatabase.getInstance();
      await db.updateBook(this.book);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      this.reloadRecentReadCardLater(shouldRefreshRecentCard);
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
    .height(44)
    .padding({ left: 18, right: 18, top: 4, bottom: 0 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.getBackgroundColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
      Text('朗读')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
      Text(this.ttsSpeed.toFixed(1) + 'x')
        .fontSize(11)
        .fontColor('#EAF2FF')
        .margin({ left: 6 })
    }
    .height(38)
    .padding({ left: 14, right: 14 })
    .borderRadius(19)
    .backgroundColor(this.accentColor())
    .shadow({
      radius: 10,
      color: this.isReaderThemeDark() ? '#66000000' : '#26000000',
      offsetX: 0,
      offsetY: 3
    })
    .position({ x: '100%', y: '100%' })
    .translate({ x: -94, y: -92 })
    .onClick(() => {
      this.ttsMediaControlsExpanded = true;
      this.syncTtsSystemMediaControls();
    })
  }

  @Builder
  ttsExpandedMediaControlsBar() {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 2 }) {
          Text(this.book?.name || '朗读')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.getChapterTitle()} · ${this.ttsSpeed.toFixed(1)}x`)
            .fontSize(12)
            .fontColor(this.getSubTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)

        Button('上一章')
          .height(34)
          .fontSize(13)
          .backgroundColor(this.canPlayPreviousTtsChapter() ? this.buttonColor() : this.disabledButtonColor())
          .fontColor('#FFFFFF')
          .enabled(this.canPlayPreviousTtsChapter())
          .onClick(() => {
            this.playPreviousChapterFromMediaSession();
          })

        Button(this.isTtsSpeaking ? '停止' : '朗读')
          .height(34)
          .fontSize(13)
          .margin({ left: 8 })
          .backgroundColor(this.isTtsSpeaking ? '#E53935' : this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.toggleTtsReading();
          })

        Button('下一章')
          .height(34)
          .fontSize(13)
          .margin({ left: 8 })
          .backgroundColor(this.canPlayNextTtsChapter() ? this.buttonColor() : this.disabledButtonColor())
          .fontColor('#FFFFFF')
          .enabled(this.canPlayNextTtsChapter())
          .onClick(() => {
            this.playNextChapterFromMediaSession();
          })

        Button('收起')
          .height(34)
          .fontSize(13)
          .margin({ left: 8 })
          .backgroundColor(this.isReaderThemeDark() ? '#343941' : '#EEF0F3')
          .fontColor(this.getTextColor())
          .onClick(() => {
            this.ttsMediaControlsExpanded = false;
            this.syncTtsSystemMediaControls();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.readerSolidPanelColor())
    .border({
      width: { top: 1 },
      color: this.isReaderThemeDark() ? '#33404752' : '#22000000'
    })
    .position({ x: 0, y: '100%' })
    .translate({ y: -98 })
  }

  shouldShowTtsMediaControls(): boolean {
    return !this.showMenu && !this.showToc && !this.showSettings &&
      !this.shouldBlockReaderInteraction() && (this.isTtsSpeaking || this.ttsReader.isSpeaking());
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
    if (this.readerPageTurnMode === 0 || this.readerPageTurnMode === 2) {
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
          PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
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

  handleReaderPanUpdate(event: GestureEvent): void {
    if (!this.canHandleReaderPageTurnPan()) {
      return;
    }
    if (!this.readerPanActive) {
      this.handleReaderPanStart(event);
    }
    const offsetX = event.offsetX;
    const offsetY = event.offsetY;
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
      this.finishReaderHorizontalTouch();
    }
  }

  finishReaderHorizontalTouch(): void {
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
    this.resetSlidePageEffect();
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
    return this.readerPageTurnMode === 0 ? offsetY : offsetX;
  }

  isReaderPageTurnCommitGesture(offsetX: number, offsetY: number): boolean {
    if (this.readerPageTurnMode === 0) {
      return Math.abs(offsetY) >= 48 && Math.abs(offsetY) > Math.abs(offsetX) * 1.2;
    }
    return Math.abs(offsetX) >= 48 && Math.abs(offsetX) > Math.abs(offsetY) * 1.2;
  }

  commitReaderMove(offsetX: number, offsetY: number): void {
    if (this.readerPageTurnMode === 0) {
      this.commitReaderVerticalMove(offsetY);
      return;
    }
    this.commitReaderHorizontalMove(offsetX);
  }

  commitReaderVerticalMove(offsetY: number): void {
    if (this.readerPageTurnMode !== 0 || this.showToc || this.showSettings ||
      this.chapters.length === 0) {
      return;
    }
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      this.stopTtsReading();
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
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      this.stopTtsReading();
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
        this.settingsTabToggle()
      }
      .width('100%')

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
      .height(430)
      .scrollBar(BarState.Auto)
      .scrollBarColor(this.isReaderThemeDark() ? '#668A8F98' : '#667A6F63')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 22 })
    .backgroundColor(this.readerSolidPanelColor())
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
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
  readerQuickSettingsPanel() {
    Column({ space: 14 }) {
      Row() {
        Text('字号')
          .fontSize(15)
          .fontColor(this.getTextColor())
          .layoutWeight(1)
        Button('-')
          .width(44)
          .height(36)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.applyReaderFontSize(this.readerFontSize - 1);
          })
        Text(`${this.readerFontSize}`)
          .fontSize(15)
          .fontColor(this.getTextColor())
          .width(48)
          .textAlign(TextAlign.Center)
        Button('+')
          .width(44)
          .height(36)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.applyReaderFontSize(this.readerFontSize + 1);
          })
      }
      .width('100%')

      Row() {
        Text('行距')
          .fontSize(15)
          .fontColor(this.getTextColor())
          .layoutWeight(1)
        Button('-')
          .width(44)
          .height(36)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.applyReaderLineHeight(this.readerLineHeight - 1);
          })
        Text(`${this.readerLineHeight}`)
          .fontSize(15)
          .fontColor(this.getTextColor())
          .width(48)
          .textAlign(TextAlign.Center)
        Button('+')
          .width(44)
          .height(36)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.applyReaderLineHeight(this.readerLineHeight + 1);
          })
      }
      .width('100%')

      Row() {
        Text('段落间距')
          .fontSize(15)
          .fontColor(this.getTextColor())
          .layoutWeight(1)
        Button('-')
          .width(44)
          .height(36)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.applyReaderParagraphSpacing(this.readerParagraphSpacing - 1);
          })
        Text(`${this.readerParagraphSpacing}`)
          .fontSize(15)
          .fontColor(this.getTextColor())
          .width(48)
          .textAlign(TextAlign.Center)
        Button('+')
          .width(44)
          .height(36)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.applyReaderParagraphSpacing(this.readerParagraphSpacing + 1);
          })
      }
      .width('100%')

      this.readerFontEntryItem()

      Row({ space: 8 }) {
        this.pageTurnModeButton('滚动', 0)
        this.pageTurnModeButton('滑动', 1)
        this.pageTurnModeButton('点击', 2)
      }
      .width('100%')

      this.readerSwitchSettingItem('翻页动画', '开启后滑动或点击翻页会预览上一页/下一页', this.readerPageTurnAnimation,
        (checked: boolean) => {
          this.readerPageTurnAnimation = checked;
        })

      this.readerSwitchSettingItem('音量键翻页', '阅读页获得焦点时使用音量上/下键翻页', this.readerVolumeTurnPage,
        (checked: boolean) => {
          this.setReaderVolumeTurnPage(checked);
        })

      Row({ space: 10 }) {
        ForEach(this.currentReaderThemes(), (theme: ReaderThemeItem, index: number) => {
          Text(index === ReaderThemeHelper.CUSTOM_THEME_INDEX ? '自' : '')
            .width(42)
            .height(42)
            .borderRadius(21)
            .fontSize(13)
            .fontColor(theme.textColor)
            .textAlign(TextAlign.Center)
            .backgroundColor(theme.backgroundColor)
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
      Text('阅读字体')
        .fontSize(15)
        .fontColor(this.getTextColor())
        .layoutWeight(1)
      Text('正文 / 标题 / 正则')
        .fontSize(13)
        .fontColor(this.getSubTextColor())
        .margin({ right: 8 })
      Text('>')
        .fontSize(18)
        .fontColor(this.getSubTextColor())
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ReaderFontSettings' });
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
  pageTurnModeButton(title: string, mode: number) {
    Text(title)
      .fontSize(13)
      .fontColor(this.readerPageTurnMode === mode ? '#FFFFFF' : '#333333')
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.readerPageTurnMode === mode ? this.accentColor() : '#EEF0F3')
      .onClick(() => {
        this.switchPageTurnMode(mode);
      })
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

  saveReaderLayoutSettings(): void {
    ReaderSettingsStore.saveLayoutSettings(
      getContext(this),
      this.readerFontSize,
      this.readerLineHeight,
      this.readerParagraphSpacing
    ).catch((e: Error) => {
      console.warn('保存阅读排版设置失败:', e);
    });
  }

  applyReaderFontSize(fontSize: number): void {
    const nextFontSize = Math.max(14, Math.min(Math.round(fontSize), 30));
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
      this.appDarkMode
    ).catch((e: Error) => {
      console.warn('保存阅读配色设置失败:', e);
    });
  }

  setCurrentThemeBackgroundColor(color: string): void {
    const value = this.normalizeColor(color, this.currentCustomThemeBackgroundColor());
    if (this.appDarkMode) {
      this.readerDarkCustomThemeBackgroundColor = value;
    } else {
      this.readerLightCustomThemeBackgroundColor = value;
    }
    this.saveReaderThemeSettings();
  }

  setCurrentThemeTextColor(color: string): void {
    const value = this.normalizeColor(color, this.currentCustomThemeTextColor());
    if (this.appDarkMode) {
      this.readerDarkCustomThemeTextColor = value;
    } else {
      this.readerLightCustomThemeTextColor = value;
    }
    this.saveReaderThemeSettings();
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
    this.ttsMediaControlsExpanded = false;
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
    if (this.currentPageIndex < this.contentPages.length - 1) {
      await this.runTtsPageTurnAnimation(1);
      return true;
    }
    if (this.currentChapterIndex < this.chapters.length - 1) {
      await this.runTtsPageTurnAnimation(1);
      return true;
    }
    return false;
  }

  finishTtsReading(): void {
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
    return covers.length > 0 ? BookDisplayHelper.pickCover(covers) : '';
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
  }

  getTtsReadingText(): string {
    const start = this.getCurrentPageStartOffset();
    this.ttsTextStartOffset = start;
    const source = this.pagedContentText || this.getPagedSourceText();
    return source.substring(start);
  }

  normalizeReaderText(text: string): string {
    return (text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
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
    return (text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
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
    return lines.slice(1).join('\n').replace(/^\n+/, '').trim();
  }

  isReaderTrimChar(value: string): boolean {
    return value === ' ' || value === '\t' || value === '\n' || value === '\r';
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

  findMeasuredPageEnd(source: string, start: number, availableWidth: number, availableHeight: number): number {
    let safeStart = Math.max(0, Math.min(start, source.length));
    while (safeStart < source.length && this.isReaderTrimChar(source.charAt(safeStart))) {
      safeStart++;
    }
    if (safeStart >= source.length) {
      return source.length;
    }

    const paragraphEnd = this.findParagraphLayoutPageEnd(source, safeStart, availableWidth, availableHeight);
    if (paragraphEnd > safeStart) {
      return paragraphEnd;
    }

    let low = safeStart + 1;
    let high = source.length;
    let best = low;
    while (low <= high) {
      const mid = Math.floor((low + high) / 2);
      const candidate = source.substring(safeStart, mid);
      if (this.measureReaderTextHeight(candidate, availableWidth) <= availableHeight) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    const end = this.chooseReaderPageBreak(source, safeStart, best);
    return Math.max(safeStart + 1, end);
  }

  findParagraphLayoutPageEnd(source: string, start: number, availableWidth: number, availableHeight: number): number {
    const windowEnd = Math.min(source.length, start + this.getReaderLayoutWindowSize(availableWidth, availableHeight));
    const layoutText = source.substring(start, windowEnd);
    if (!layoutText) {
      return -1;
    }
    if (this.readerParagraphSpacing > 0 && /\n/.test(layoutText)) {
      return -1;
    }

    try {
      const fontSizePx = this.toMeasurePx(this.readerFontSize);
      const lineHeightPx = this.toMeasurePx(this.getEffectiveReaderLineHeight());
      const textStyle: graphicsText.TextStyle = {
        fontSize: fontSizePx,
        fontFamilies: [this.getReaderFontFamily()],
        fontWeight: graphicsText.FontWeight.W400,
        lineHeightMinimum: lineHeightPx,
        lineHeightMaximum: lineHeightPx,
        halfLeading: true,
        heightOnly: false,
        locale: 'zh-Hans'
      };
      const paragraphStyle: graphicsText.ParagraphStyle = {
        textStyle: textStyle,
        align: graphicsText.TextAlign.START,
        textDirection: graphicsText.TextDirection.LTR,
        wordBreak: graphicsText.WordBreak.BREAK_ALL,
        breakStrategy: graphicsText.BreakStrategy.GREEDY,
        trailingSpaceOptimized: true,
        includeFontPadding: false
      };
      const builder = new graphicsText.ParagraphBuilder(paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
      builder.pushStyle(textStyle);
      builder.addText(layoutText);
      builder.popStyle();
      const paragraph = builder.build();
      paragraph.layoutSync(this.toMeasurePx(availableWidth));
      const metrics = paragraph.getLineMetrics();
      if (metrics.length === 0) {
        return -1;
      }

      const safeHeight = Math.max(1, availableHeight - 1);
      let end = -1;
      for (let i = 0; i < metrics.length; i++) {
        const metric = metrics[i];
        if (metric.topHeight + metric.height > safeHeight) {
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

  measureReaderTextHeight(text: string, availableWidth: number): number {
    if (!text) {
      return 0;
    }
    const paragraphs = this.getReaderTextParagraphs(text);
    if (paragraphs.length > 1) {
      let totalHeight = 0;
      for (const paragraph of paragraphs) {
        totalHeight += this.measureReaderSingleParagraphHeight(paragraph.text, availableWidth);
        if (!paragraph.isLast) {
          totalHeight += this.toMeasurePx(this.readerParagraphSpacing);
        }
      }
      return totalHeight;
    }
    return this.measureReaderSingleParagraphHeight(text, availableWidth);
  }

  measureReaderSingleParagraphHeight(text: string, availableWidth: number): number {
    if (!text) {
      return 0;
    }
    try {
      const fontSizePx = this.toMeasurePx(this.readerFontSize);
      const lineHeightPx = this.toMeasurePx(this.getEffectiveReaderLineHeight());
      const textStyle: graphicsText.TextStyle = {
        fontSize: fontSizePx,
        fontFamilies: [this.getReaderFontFamily()],
        fontWeight: graphicsText.FontWeight.W400,
        lineHeightMinimum: lineHeightPx,
        lineHeightMaximum: lineHeightPx,
        halfLeading: true,
        heightOnly: false,
        locale: 'zh-Hans'
      };
      const paragraphStyle: graphicsText.ParagraphStyle = {
        textStyle: textStyle,
        align: graphicsText.TextAlign.START,
        textDirection: graphicsText.TextDirection.LTR,
        wordBreak: graphicsText.WordBreak.BREAK_ALL,
        breakStrategy: graphicsText.BreakStrategy.GREEDY,
        trailingSpaceOptimized: true,
        includeFontPadding: false
      };
      const builder = new graphicsText.ParagraphBuilder(paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
      builder.pushStyle(textStyle);
      builder.addText(text);
      builder.popStyle();
      const paragraph = builder.build();
      paragraph.layoutSync(this.toMeasurePx(availableWidth));
      const metrics = paragraph.getLineMetrics();
      if (metrics.length > 0) {
        const lastMetric = metrics[metrics.length - 1];
        const height = Number(lastMetric.topHeight + lastMetric.height);
        if (height > 0) {
          return height;
        }
      }
    } catch (error) {
      console.error('官方段落布局测量阅读文本高度失败，回退到组件测量:', error);
    }
    const options: MeasureOptions = {
        textContent: text,
        constraintWidth: Math.max(1, availableWidth),
        fontSize: this.readerFontSize,
        fontFamily: this.getReaderFontFamily(),
        lineHeight: this.getEffectiveReaderLineHeight(),
      fontWeight: FontWeight.Normal,
      textAlign: TextAlign.Start,
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
    const minBreak = start + Math.max(24, Math.floor((best - start) * 0.96));
    let newline = source.lastIndexOf('\n', best);
    if (newline >= minBreak) {
      return newline + 1;
    }
    let sentence = Math.max(
      source.lastIndexOf('。', best),
      source.lastIndexOf('！', best),
      source.lastIndexOf('？', best),
      source.lastIndexOf('；', best),
      source.lastIndexOf(';', best)
    );
    if (sentence >= minBreak) {
      return sentence + 1;
    }
    return best;
  }

  followTtsChunk(chunk: TtsChunk): void {
    const pageIndex = this.resolveTtsChunkPageIndex(chunk);
    this.ttsLastFocusChunk = chunk;
    this.ttsLastFocusPageIndex = pageIndex;
    if (pageIndex !== this.currentPageIndex) {
      this.animateTtsToPage(pageIndex, chunk);
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
    if (pageIndex !== this.currentPageIndex) {
      this.currentPageIndex = pageIndex;
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
    this.ttsHighlightStart = Math.max(0, Math.min(absoluteStart - pageStart, pageText.length));
    this.ttsHighlightEnd = Math.max(this.ttsHighlightStart, Math.min(absoluteEnd, pageEnd) - pageStart);
    this.pageRenderVersion++;
  }

  animateTtsToPage(targetPageIndex: number, chunk: TtsChunk): void {
    const target = Math.max(0, Math.min(targetPageIndex, Math.max(0, this.contentPages.length - 1)));
    if (target <= this.currentPageIndex) {
      this.updateTtsChunkHighlight(chunk, this.currentPageIndex);
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
        this.updateTtsChunkHighlight(this.ttsPendingHighlightChunk, this.currentPageIndex);
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
      if (!this.readerPageTurnAnimation) {
        await this.applyTtsPageTurn(direction, turnSerial);
        this.finishPageTurnAnimation();
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
    this.finishPageTurnAnimation();
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
    this.finishPageTurnAnimation();
  }

  async applyTtsPageTurn(direction: number, turnSerial: number): Promise<void> {
    if (turnSerial !== this.ttsPageTurnSerial || !this.isTtsSpeaking || !this.ttsAutoContinue) {
      return;
    }
    if (direction > 0) {
      if (this.currentPageIndex < this.contentPages.length - 1) {
        this.currentPageIndex++;
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

    if (this.currentPageIndex > 0) {
      this.currentPageIndex--;
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
  readerSlidingPageTurnSurface(currentText: string, currentRenderVersion: number) {
    Stack() {
      if (this.shouldRenderSlidingPageTurn()) {
        this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion, this.getVisiblePageTurnIncomingText())
        this.readerCurrentPageSurface(currentRenderVersion, currentText)
      } else {
        this.readerCurrentPageSurface(currentRenderVersion, currentText)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getBackgroundColor())
    .clip(true)
  }

  @Builder
  readerSlidingPageTurnSurfaceAlternate(currentText: string, currentRenderVersion: number) {
    Stack() {
      if (this.shouldRenderSlidingPageTurn()) {
        this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion, this.getVisiblePageTurnIncomingText())
        this.readerCurrentPageSurfaceAlternate(currentRenderVersion, currentText)
      } else {
        this.readerCurrentPageSurfaceAlternate(currentRenderVersion, currentText)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getBackgroundColor())
    .clip(true)
  }

  @Builder
  readerCurrentPageSurface(renderVersion: number, text: string) {
    Column() {
      this.readerCurrentPageLayer(renderVersion, text)
    }
    .width('100%')
    .height('100%')
    .id(`reader_current_${this.currentChapterIndex}_${this.currentPageIndex}_${renderVersion}`)
    .backgroundColor(this.getBackgroundColor())
    .translate({ x: this.pageTransitionX + this.pageSlideOffsetX, y: this.pageSlideOffsetY })
    .opacity(this.pageTransitionOpacity)
  }

  @Builder
  readerCurrentPageSurfaceAlternate(renderVersion: number, text: string) {
    Column() {
      this.readerCurrentPageLayer(renderVersion, text)
    }
    .width('100%')
    .height('100%')
    .id(`reader_current_alt_${this.currentChapterIndex}_${this.currentPageIndex}_${renderVersion}`)
    .backgroundColor(this.getBackgroundColor())
    .translate({ x: this.pageTransitionX + this.pageSlideOffsetX, y: this.pageSlideOffsetY })
    .opacity(this.pageTransitionOpacity)
  }

  @Builder
  readerIncomingPageSurface(renderVersion: number, text: string) {
    Column() {
      this.readerIncomingPageLayer(renderVersion, text)
    }
    .width('100%')
    .height('100%')
    .id(`reader_incoming_${this.pageTurnIncomingChapterIndex}_${this.pageTurnIncomingPageIndex}_${renderVersion}`)
    .backgroundColor(this.getBackgroundColor())
    .translate({ x: this.getIncomingSlideX(), y: this.getIncomingSlideY() })
    .opacity(this.getVisiblePageTurnIncomingOpacity())
  }

  @Builder
  readerCurrentPageLayer(renderVersion: number, text: string) {
    Column() {
      if (this.hasActiveTtsHighlight(text)) {
        this.readingText(text, 18 + this.getReaderContentBottomReserve())
      } else if (renderVersion % 2 === 0) {
        this.styledReaderText(text, 18 + this.getReaderContentBottomReserve())
      } else {
        this.styledReaderText(text, 18 + this.getReaderContentBottomReserve())
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.getBackgroundColor())
  }

  @Builder
  readerIncomingPageLayer(renderVersion: number, text: string) {
    Column() {
      if (this.hasActiveTtsHighlight(text)) {
        this.readingText(text, 18 + this.getReaderContentBottomReserve())
      } else if (renderVersion % 2 === 0) {
        this.styledReaderText(text, 18 + this.getReaderContentBottomReserve(), this.pageTurnIncomingChapterIndex)
      } else {
        this.styledReaderText(text, 18 + this.getReaderContentBottomReserve(), this.pageTurnIncomingChapterIndex)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.getBackgroundColor())
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
          .width('100%')
        } else {
          this.styledReaderParagraph(paragraph, this.currentChapterIndex)
        }
        this.readerParagraphGap(paragraph)
      }, (paragraph: ReaderTextParagraph) => paragraph.key)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: bottomPadding })
  }

  @Builder
  styledReaderText(text: string, bottomPadding: number, chapterIndex: number = this.currentChapterIndex) {
    Column() {
      ForEach(this.getReaderTextParagraphs(text), (paragraph: ReaderTextParagraph) => {
        this.styledReaderParagraph(paragraph, chapterIndex)
        this.readerParagraphGap(paragraph)
      }, (paragraph: ReaderTextParagraph) => paragraph.key)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: bottomPadding })
  }

  @Builder
  styledReaderParagraph(paragraph: ReaderTextParagraph, chapterIndex: number = this.currentChapterIndex) {
    if (this.shouldUseTitleStyle(paragraph.text, chapterIndex)) {
      Text() {
        Span(this.getChapterTitle(chapterIndex))
          .fontSize(this.readerTitleFontSize)
          .fontFamily(this.getTitleReaderFontFamily())
          .fontColor(this.getTextColor())
        ForEach(this.getRegexTextSlices(paragraph.text.substring(this.getChapterTitle(chapterIndex).length)), (slice: ReadTextSlice) => {
          Span(slice.text)
            .fontSize(slice.highlighted ? this.getRegexSliceFontSize(slice) : this.readerFontSize)
            .fontFamily(slice.highlighted ? this.getRegexSliceFontFamily(slice) : this.getBodyReaderFontFamily())
            .fontColor(slice.highlighted && this.shouldUseRegexHighlight(this.getRegexRuleBySlice(slice)) ? this.getRegexHighlightTextColor() : this.getTextColor())
            .textBackgroundStyle(slice.highlighted && this.shouldUseRegexHighlight(this.getRegexRuleBySlice(slice)) ? {
              color: this.readerRegexHighlightColor(this.getRegexRuleBySlice(slice)),
              radius: 4
            } : {})
        }, (slice: ReadTextSlice) => `title_body_${slice.key}`)
      }
      .lineHeight(this.getEffectiveReaderLineHeight())
      .fontColor(this.getTextColor())
      .width('100%')
    } else if (this.shouldUseRegexStyle(paragraph.text)) {
      this.regexReaderText(paragraph)
    } else {
      Text(paragraph.text)
        .fontSize(this.readerFontSize)
        .fontFamily(this.getBodyReaderFontFamily())
        .lineHeight(this.getEffectiveReaderLineHeight())
        .fontColor(this.getTextColor())
        .width('100%')
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
  regexReaderText(paragraph: ReaderTextParagraph) {
    Text() {
      ForEach(this.getRegexTextSlices(paragraph.text), (slice: ReadTextSlice) => {
        Span(slice.text)
          .fontSize(slice.highlighted ? this.getRegexSliceFontSize(slice) : this.readerFontSize)
          .fontFamily(slice.highlighted ? this.getRegexSliceFontFamily(slice) : this.getBodyReaderFontFamily())
          .fontColor(slice.highlighted && this.shouldUseRegexHighlight(this.getRegexRuleBySlice(slice)) ? this.getRegexHighlightTextColor() : this.getTextColor())
          .textBackgroundStyle(slice.highlighted && this.shouldUseRegexHighlight(this.getRegexRuleBySlice(slice)) ? {
            color: this.readerRegexHighlightColor(this.getRegexRuleBySlice(slice)),
            radius: 4
          } : {})
      }, (slice: ReadTextSlice) => slice.key)
    }
    .lineHeight(this.getEffectiveReaderLineHeight())
    .fontColor(this.getTextColor())
    .width('100%')
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
    const raw = (this.readerRegexFontRulesRaw || '').trim();
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as ReaderRegexFontRulesData | ReaderRegexFontRule[];
        const source = Array.isArray(parsed) ? parsed as ReaderRegexFontRule[] : ((parsed as ReaderRegexFontRulesData).rules || []);
        const result: ReaderRegexFontRule[] = [];
        for (const item of source) {
          if (!item) {
            continue;
          }
          const rule = new ReaderRegexFontRule();
          rule.id = item.id || '';
          rule.name = item.name || '';
          rule.pattern = item.pattern || '';
          rule.fontMode = item.fontMode || 'global';
          rule.fontFamily = item.fontFamily || '';
          rule.fontSize = Math.max(14, Math.min(Math.round(item.fontSize || 20), 30));
          rule.highlightColorEnabled = item.highlightColorEnabled === true;
          rule.shadowColor = item.shadowColor || '';
          rule.expanded = item.expanded !== false;
          result.push(rule);
        }
        return result;
      } catch (e) {
      }
    }
    if ((this.readerRegexFontPattern || '').trim()) {
      const rule = new ReaderRegexFontRule();
      rule.pattern = this.readerRegexFontPattern;
      rule.fontMode = this.readerRegexFontMode;
      rule.fontFamily = this.readerRegexFontFamily;
      rule.fontSize = this.readerRegexFontSize;
      rule.highlightColorEnabled = !!this.readerRegexShadowColor;
      rule.shadowColor = this.readerRegexShadowColor;
      rule.expanded = true;
      return [rule];
    }
    return [];
  }

  readerRegexHighlightColor(rule: ReaderRegexFontRule | null): string {
    return rule ? (rule.highlightColorEnabled ? ((rule.shadowColor || '').trim() || this.accentColor()) : this.accentColor()) :
      (this.readerRegexShadowColor.trim() || this.accentColor());
  }

  shouldUseRegexHighlight(rule: ReaderRegexFontRule | null): boolean {
    return rule ? rule.highlightColorEnabled : !!this.readerRegexShadowColor.trim();
  }

  getRegexHighlightTextColor(): string {
    return this.getTtsHighlightTextColor();
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
            regex.lastIndex = Math.min(displayText.length, Math.max(regex.lastIndex + 1, start + 1));
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
          this.showSettings = false;
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
    this.showMenu = false;
    this.showSettings = false;
  }

  exitReaderPage(): void {
    this.hideReaderPanels();
    this.stopTtsReading();
    this.saveReadingProgress().catch((e: Error) => {
      console.error('返回阅读页时保存进度失败:', e);
    });
    router.back();
  }

  paginateReaderSourceText(source: string): ReaderPaginationResult {
    const text = source || '';
    if (!text || this.pageViewWidth <= 0 || this.pageViewHeight <= 0) {
      return {
        source: text,
        pages: text ? [text] : [],
        starts: text ? [0] : [],
        ends: text ? [text.length] : []
      };
    }

    const horizontalPadding = 36;
    const verticalPadding = 36 + this.getReaderContentBottomReserve();
    const availableWidth = Math.max(1, this.pageViewWidth - horizontalPadding);
    const availableHeight = Math.max(1, this.pageViewHeight - verticalPadding);
    const measuredAvailableHeight = this.toMeasurePx(availableHeight);
    const pages: string[] = [];
    const starts: number[] = [];
    const ends: number[] = [];
    let cursor = 0;

    while (cursor < text.length) {
      const end = this.findMeasuredPageEnd(text, cursor, availableWidth, measuredAvailableHeight);
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
    return `${chapterIndex}_${this.pageViewWidth}_${this.pageViewHeight}_${this.readerFontSize}_` +
      `${this.readerLineHeight}_${this.getReaderFontFamily()}_${source.length}_${this.hashText(source)}`;
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
    const result = this.paginateReaderSourceText(source);
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
          const source = this.buildPagedSourceText(targetChapterIndex, body);
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
    const pageIndex = Math.max(0, Math.min(this.currentPageIndex, Math.max(0, pages.length - 1)));
    this.currentPageIndex = pageIndex;
    this.setCurrentPageText(pages[pageIndex] || '');
  }

  async turnNext() {
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      this.stopTtsReading();
    }
    await this.runPageTurnAnimation(1, this.readerPageTurnMode === 1 ? 'slide' : 'tap');
  }

  async turnPrev() {
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      this.stopTtsReading();
    }
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
      return this.currentPageIndex < this.contentPages.length - 1 || this.currentChapterIndex < this.chapters.length - 1;
    }
    return this.currentPageIndex > 0 || this.currentChapterIndex > 0;
  }

  async applyPageTurn(direction: number): Promise<void> {
    this.stopTtsReading();
    if (direction > 0) {
      if (this.currentPageIndex < this.contentPages.length - 1) {
        this.currentPageIndex++;
        this.syncCurrentPageText();
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

    if (this.currentPageIndex > 0) {
      this.currentPageIndex--;
      this.syncCurrentPageText();
      if (this.currentPageIndex <= 2) {
        this.preloadReaderContentLater();
      }
      this.saveReadingProgress();
    } else {
      await this.loadPrevChapter(true);
    }
  }

  async runPageTurnAnimation(direction: number, style: string): Promise<void> {
    if (this.ttsAutoTurningPage || this.isPageTurning) {
      return;
    }
    if (!this.canTurnPage(direction)) {
      this.resetSlidePageEffect();
      if (direction > 0 && this.chapters.length > 0 &&
        this.currentChapterIndex >= this.chapters.length - 1 &&
        this.currentPageIndex >= this.contentPages.length - 1) {
        promptAction.showToast({ message: '本书已阅读完成' });
      }
      return;
    }

    this.isPageTurning = true;
    try {
      if (!this.readerPageTurnAnimation) {
        await this.runLegacyPageTurn(direction);
      } else if (style === 'slide' || style === 'gesture') {
        await this.runSlidePageTurn(direction);
      } else {
        await this.runTapPageTurn(direction);
      }
    } finally {
      this.isPageTurning = false;
    }
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
    await this.applyPageTurn(direction);
    this.finishPageTurnAnimation();
  }

  async runTapPageTurn(direction: number): Promise<void> {
    const distance = this.getPageTurnDistance();
    this.prepareSlidePageTurn(direction, 0);
    animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.setPageSlideAxisOffset(direction > 0 ? -distance : distance);
      this.pageTransitionOpacity = 1;
    });
    await this.delay(230);
    await this.applyPageTurn(direction);
    this.finishPageTurnAnimation();
  }

  async runSlidePageTurn(direction: number): Promise<void> {
    const distance = this.getPageTurnDistance();
    this.prepareSlidePageTurn(direction, this.getPageSlideAxisOffset());
    const targetOffset = direction > 0 ? -distance : distance;
    const remaining = Math.abs(targetOffset - this.getPageSlideAxisOffset());
    const duration = Math.max(90, Math.min(240, Math.round(240 * remaining / distance)));
    animateTo({ duration: duration, curve: Curve.EaseOut }, () => {
      this.setPageSlideAxisOffset(targetOffset);
      this.pageTransitionOpacity = 1;
    });
    await this.delay(duration + 10);
    await this.applyPageTurn(direction);
    this.finishPageTurnAnimation();
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

  setPageTurnIncomingState(pageIndex: number, text: string, animating: boolean = true,
    chapterIndex: number = this.currentChapterIndex): void {
    const safeText = text || '';
    const nextAnimating = animating && !!safeText;
    if (this.pageTurnIncomingPageIndex !== pageIndex || this.pageTurnIncomingChapterIndex !== chapterIndex ||
      this.pageTurnIncomingText !== safeText ||
      this.pageTurnAnimating !== nextAnimating) {
      this.pageTurnIncomingRenderVersion++;
    }
    this.pageTurnIncomingPageIndex = pageIndex;
    this.pageTurnIncomingChapterIndex = chapterIndex;
    this.pageTurnIncomingText = safeText;
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
    if (direction > 0 && this.currentPageIndex < this.contentPages.length - 1) {
      return this.currentPageIndex + 1;
    }
    if (direction < 0 && this.currentPageIndex > 0) {
      return this.currentPageIndex - 1;
    }
    return -1;
  }

  getAdjacentPageTurnChapterIndex(direction: number): number {
    if (direction > 0 && this.currentPageIndex >= this.contentPages.length - 1 &&
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
      this.setPageTurnIncomingState(localPageIndex, this.getPageText(localPageIndex));
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
    return `${direction}_${chapterIndex}_${this.pageViewWidth}_${this.pageViewHeight}_${this.readerFontSize}_` +
      `${this.readerLineHeight}_${this.readerParagraphSpacing}_${this.getReaderFontFamily()}`;
  }

  buildCachedAdjacentPageTurnPreview(direction: number, chapterIndex: number): PageTurnPreview {
    const body = ReadBookEngine.get().getCachedContent(chapterIndex);
    if (!body) {
      return { text: '', pageIndex: 0, chapterIndex: chapterIndex };
    }
    return this.buildAdjacentPageTurnPreview(direction, chapterIndex, body);
  }

  buildAdjacentPageTurnPreview(direction: number, chapterIndex: number, body: string): PageTurnPreview {
    const source = this.buildPagedSourceText(chapterIndex, body);
    const result = this.getOrCreateReaderPagination(chapterIndex, source);
    if (result.pages.length === 0) {
      return { text: '', pageIndex: 0, chapterIndex: chapterIndex };
    }
    const pageIndex = direction > 0 ? 0 : result.pages.length - 1;
    return {
      text: result.pages[pageIndex],
      pageIndex: pageIndex,
      chapterIndex: chapterIndex
    };
  }

  getPageTurnLoadingText(chapterIndex: number): string {
    const title = this.getChapterTitle(chapterIndex).trim();
    return title ? `${title}\n\n正在加载章节内容...` : '正在加载章节内容...';
  }

  applyPageTurnPreview(preview: PageTurnPreview): void {
    this.setPageTurnIncomingState(preview.pageIndex, preview.text, true, preview.chapterIndex);
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
    if (!this.readerPageTurnAnimation) {
      this.updateLegacySlidePageEffect(offset);
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
    return this.shouldRenderSlidingPageTurn() ? this.pageTurnIncomingOpacity : 0;
  }

  getPageTurnWidth(): number {
    return Math.max(1, this.pageViewWidth > 0 ? this.pageViewWidth : 360);
  }

  getPageTurnHeight(): number {
    return Math.max(1, this.pageViewHeight > 0 ? this.pageViewHeight : 640);
  }

  isVerticalPageTurnAnimation(): boolean {
    return this.readerPageTurnMode === 0;
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
    return this.readerPageTurnAnimation && this.pageSlideDirection !== 0 &&
      this.canTurnPage(this.pageSlideDirection);
  }

  getSlideIncomingX(direction: number, offsetX: number, width: number = this.getPageTurnWidth()): number {
    return direction > 0 ? width + offsetX : offsetX - width;
  }

  getIncomingSlideX(): number {
    if (this.pageSlideDirection === 0 || this.isVerticalPageTurnAnimation()) {
      return 0;
    }
    return this.getSlideIncomingX(this.pageSlideDirection, this.pageSlideOffsetX);
  }

  getSlideIncomingY(direction: number, offsetY: number, height: number = this.getPageTurnHeight()): number {
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
        text += '\n\n当前书源需要先完成网页验证。请点击标题栏的「验证」按钮，完成后返回并点击「重试」。';
      } else {
        text += '\n\n当前书源暂未解析出目录，可以尝试点击标题栏的「重试」按钮重新获取，或在书源管理中为该书源补充目录规则。';
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
