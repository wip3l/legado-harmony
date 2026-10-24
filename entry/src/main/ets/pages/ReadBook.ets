import { BookCoverResolver } from '../utils/BookCoverResolver';
import { ThemeBookCoverSettings } from '../utils/ThemeBookCoverSettings';
import { NativeSourceService, HttpClient, Book, BookChapter, Bookmark, BookSource, HttpTTS, BookTypeSupport, VerificationSupport, ReaderActionData, ReaderActionMarker, ReaderActionMatch, BookSourceStageWebRuntime, StageWebRuntimeRequest, WebBookFetchRuntime, SourceRuntimeStage, CooperativeScheduler, sleepMs } from '@legado/sourceengine';
import { router, window, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { inputConsumer, KeyCode, Action, KeyEvent } from '@kit.InputKit';
import { avSession } from '@kit.AVSessionKit';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import graphicsText from '@ohos.graphics.text';
import { LengthMetrics } from '@ohos.arkui.node';
import deviceInfo from '@ohos.deviceInfo';
import display from '@ohos.display';
import Animator, { AnimatorResult } from '@ohos.animator';
import { HdsTabs } from '@kit.UIDesignKit';
import { ARView } from '@kit.AREngine';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { CloudSyncCoordinator } from '../account/CloudSyncCoordinator';
import { TtsVoiceInfo } from '../account/AccountCommerceModels';
import { AppDatabase } from '../model/data/AppDatabase';
import { ReadBookEngine } from '../core/book/ReadBookEngine';
import { ReaderImageMarker } from '../core/book/ReaderImageMarker';
import { readStatsTracker } from '../core/stats/ReadStatsTracker';
import { LocalBookService } from '../core/book/LocalBookService';
import { WebDavBookService } from '../webdav/WebDavBookService';
import { BookSourceRuntimeSnapshotStore, BookSourceSettingValue } from '../core/book/BookSourceRuntimeSnapshot';
import { ReaderInteractionProviderRegistry } from '../core/book/ReaderInteractionProvider';
import { ReaderCommentWebTheme } from '../core/reader/ReaderCommentWebTheme';
import { HdsFeedback } from '../utils/HdsFeedback';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { SystemTtsReader, TtsChunk, TtsVoiceOption } from '../utils/SystemTtsReader';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { ReaderProgressCheckpoint } from '../utils/ReaderProgressCheckpoint';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderReplaceRule, ReaderReplaceRuleStore } from '../utils/ReaderReplaceRuleStore';
import { ReaderThemeHelper, ReaderThemeItem } from '../utils/ReaderThemeHelper';
import { ReaderCustomThemeData, ReaderCustomThemeHelper, ReaderCustomThemeScheme } from '../utils/ReaderCustomThemeHelper';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ReaderThemeBackground } from '../components/ReaderThemeBackground';
import { ReaderPageCurlPainter } from '../components/ReaderPageCurlPainter';
import { ReaderEmulationFlipPainter, ReaderEmulationFlipRegion } from '../components/ReaderEmulationFlipPainter';
import { ReaderTtsPlayerPanel } from '../components/ReaderTtsPlayerPanel';
import { TtsCatalogSheet, CatalogTitleDataSource } from '../components/TtsCatalogSheet';
import { BookSourceStageRuntimeHost } from '../components/BookSourceStageRuntimeHost';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { BookChangeSourceDialog } from '../components/BookChangeSourceDialog';
import { TapZoneSettingsDialogContent } from '../components/TapZoneSettingsDialog';
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
import { ThemeRegexEmphasisModes } from '../theme/ThemeModels';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ReaderContentPreprocessor } from '../core/concurrency/ReaderContentPreprocessor';
import {
  ReaderV2Document,
  ReaderV2DocumentParser,
  ReaderV2HeadingHint,
  ReaderV2SpeechText
} from '../core/reader/ReaderV2Document';
import { ReaderV2LayoutInput, ReaderV2LayoutSnapshot } from '../core/reader/ReaderV2LayoutSnapshot';
import {
  ReaderV2PageFragment,
  ReaderV2PageLayout,
  ReaderV2PageSet,
  ReaderV2RegexBubbleSegment
} from '../core/reader/ReaderV2PageLayout';
import { ReaderV2PaginationSession, ReaderV2Paginator } from '../core/reader/ReaderV2Paginator';
import { ReaderV2Color, ReaderV2SpanStyleRange } from '../core/reader/ReaderV2Style';
import { ReaderCommentBubbleStyle, ReaderCommentBubbleStyles } from '../core/reader/ReaderCommentBubble';
import { ReaderV2PageNodeController } from '../core/reader/ReaderV2RenderNode';
import { ReaderV2GestureRouter, ReaderV2TapResult } from '../core/reader/ReaderV2Interaction';
import { ReaderOpenTrace } from '../utils/ReaderOpenTrace';
import { ReaderEyeTurnCoordinator, ReaderEyeTurnViewState } from '../core/reader/ReaderEyeTurnCoordinator';
import { ReaderEyeCalibrationPanel, ReaderEyeTurnCalibrationSettingItem } from '../components/reader/ReaderEyeTurnViews';
import { ReaderFullTextCacheController } from '../core/reader/ReaderFullTextCacheController';
import { ReaderTtsMediaInfo, ReaderTtsMediaSession } from '../core/reader/ReaderTtsMediaSession';
import { TtsVoiceCatalog } from '../utils/TtsVoiceCatalog';
import { ReaderTtsQuickSettingsPanel, ReaderTtsVoicePickerPanel } from '../components/reader/ReaderTtsSettingsPanels';
import { ReaderCustomThemeEditor } from '../components/reader/ReaderCustomThemeEditor';
import { ReaderTtsCapsule } from '../components/reader/ReaderTtsControls';
import { ReaderHeaderFooterSettings, ReaderTypographyField, ReaderTypographyStepper } from '../components/reader/ReaderLayoutSettings';
import { ReaderCacheDialogContent } from '../components/reader/ReaderCacheDialogContent';
import { ReaderTxtCharsetDialogContent, ReaderTxtCharsets } from '../components/reader/ReaderTxtCharsetDialogContent';
import { ReaderLayoutElementSettingsPanel } from '../components/reader/ReaderLayoutElementSettingsPanel';
import { ReaderTocPanel, ReaderTocPanelController } from '../components/reader/ReaderTocPanel';
import { ReaderFloatingMaterialBar } from '../components/reader/ReaderFloatingMaterialBar';
import { ReaderContinuousDataSource, ReaderScrollItem, ReaderScrollSegment } from '../core/reader/ReaderDataSources';
import { ReaderComicImageItem, ReaderComicView } from '../components/reader/ReaderComicView';
import { ReaderComicPagedController, ReaderComicPagedView } from '../components/reader/ReaderComicPagedView';
import { ReaderComicImageActions } from '../core/reader/ReaderComicImageActions';
import { ReaderComicStyle } from '../core/reader/ReaderComicStyle';
import { ReaderNeighborChapterLoader } from '../core/reader/ReaderNeighborChapterLoader';
import {
  READER_COMIC_TEXT_MODE,
  ReaderComicDisplaySettingsPanel,
  ReaderComicModeSettingsPanel,
  ReaderComicPanelColors
} from '../components/reader/ReaderComicSettingsPanels';
import { ReaderSettingActionRow, ReaderSettingSelectRow, ReaderSettingSwitchRow } from '../components/reader/ReaderSettingRows';
import {
  ReaderComicBackground,
  ReaderComicFit,
  ReaderComicMode,
  ReaderComicSettings,
  ReaderComicSettingsStore
} from '../core/reader/ReaderComicSettings';
import {
  ReaderComicSuperResolution,
  ReaderComicSuperResolutionAccess
} from '../core/reader/ReaderComicSuperResolution';
import { ComicChineseConverter } from '../core/reader/ComicChineseConverter';
import { ReaderCustomFontItem, ReaderCustomFontData } from '../core/reader/ReaderSettingsModels';
import {
  PageTurnPreview,
  ReaderParagraphMetrics,
  ReaderInlineActionBoundsTask,
  ReaderMergedActionBoundsTask,
  ReaderTextParagraph,
  ReadTextSlice,
  ReaderPaginationResult,
  ReaderViewportSize,
  ReaderV2HighlightRect
} from '../core/reader/ReaderPageModels';
import { ReaderTextNormalizer } from '../core/reader/ReaderTextNormalizer';
import { ReaderParagraphIndent } from '../core/reader/ReaderParagraphIndent';
import { ReaderImageSizeResolver } from '../core/reader/ReaderImageSizeResolver';
import { ReaderImageBitmapCache } from '../core/reader/ReaderImageBitmapCache';
import { ReaderChunkPagination, ReaderChunkResult } from '../core/reader/ReaderChunkPagination';
import { ReaderPageOffsets } from '../core/reader/ReaderPageOffsets';
import { ReaderPageTurnQueue } from '../core/reader/ReaderPageTurnQueue';
import {
  ReaderInfoBarConfig, ReaderInfoBarContext, ReaderInfoBarText, ReaderInfoProgressBar
} from '../core/reader/ReaderInfoBarModel';
import { ReaderInfoBarClock } from '../core/reader/ReaderInfoBarClock';
import { ReaderInfoBarRow } from '../components/reader/ReaderInfoBar';
import { EpubChapterPlanner } from '../core/book/EpubChapterPlanner';
import { EpubHeading } from '../core/book/EpubHtmlConverter';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CloudAutoSync } from '../account/CloudAutoSync';

const READER_CURRENT_PAGINATION_AHEAD_PAGE_COUNT = 4;
const READER_ADJACENT_PAGINATION_PREVIEW_PAGE_COUNT = 2;
const READER_PAGINATION_BATCH_DELAY_MS = 64;
const READER_INTERACTIVE_PAGINATION_BATCH_DELAY_MS = 56;
const READER_PAGINATION_BUSY_RETRY_DELAY_MS = 48;
const READER_DOUBLE_PAGE_DIVIDER_WIDTH = 1;
// 正文选中菜单里的自定义“替换”项 ID，用于与系统菜单项（复制/全选/翻译等）区分。
const READER_REPLACE_MENU_ITEM_ID: string = 'reader_replace_rule';
// Page-curl textures are transient animation rasters, not the settled正文 surface. Capturing a full 2080x3120
// page and sampling it through every mesh triangle can block the ArkUI thread for several seconds on tablets.
// A 0.42 raster remains sharp while moving on high-density screens and reduces texture fill by another 29%
// compared with the previous half-resolution capture. This matters most on dialogue-heavy pages.
const READER_PAGE_CURL_SNAPSHOT_SCALE = 0.42;
// 3D 仿真每帧只画两三次整页贴图，不像网格卷曲那样反复采样，可以用更高的快照分辨率换取清晰的文字。
const READER_PAGE_3D_SNAPSHOT_SCALE = 0.75;
const READER_CURL_REGION_UNSET = -1;
// 一次拖动的意图：越过点击阈值时按方向判定一次，之后不再在翻页与下拉书签之间切换。
const READER_PAN_INTENT_NONE = 0;
const READER_PAN_INTENT_TURN = 1;
const READER_PAN_INTENT_BOOKMARK = 2;
const READER_PROGRESS_OFFSET_KEY = 'readProgressCharOffsetV2';
const READER_V2_NO_FRAGMENTS: ReaderV2PageFragment[] = [];
const READER_V2_IMAGE_LOADING_SIZE = 32;
// 当前页前后各提前解码几页的插图。
const READER_V2_IMAGE_PREWARM_PAGES = 2;
const READER_V2_CONTINUOUS_ROLE = 'continuous';
const READER_CONTINUOUS_LIST_ID = 'reader_continuous_list';
const READER_CONTINUOUS_TTS_FOLLOW_GRACE_MS = 2500;
const READER_PROGRESS_OFFSET_CHAPTER_KEY = 'readProgressCharOffsetChapterV2';

/** 评论网页只获得返回/关闭能力，不暴露书源运行时或其它宿主权限。 */
class ReaderCommentNavigationBridge {
  private readonly navigateBack: () => void;
  private readonly dismiss: () => void;

  constructor(navigateBack: () => void, dismiss: () => void) {
    this.navigateBack = navigateBack;
    this.dismiss = dismiss;
  }

  back(): void { this.navigateBack(); }
  close(): void { this.dismiss(); }
}

@Entry
@Component
struct ReadBookPage {
  @State bookUrl: string = '';
  @State book: Book | null = null;
  @State chapters: BookChapter[] = [];
  @State tocReverseOrder: boolean = false;
  private tocPanelController: ReaderTocPanelController = new ReaderTocPanelController();
  private openingBookDetail: boolean = false;
  @State currentChapterIndex: number = 0;
  @State menuChapterPreviewIndex: number = 0;
  @State menuChapterSliderActive: boolean = false;
  @State menuChapterTooltipVisible: boolean = false;
  @State menuChapterConfirming: boolean = false;
  @State content: string = '';
  @State readerReplaceRules: ReaderReplaceRule[] = [];
  @State isLoading: boolean = true;
  @State showMenu: boolean = false;
  @State readerDayNightLongPressHandled: boolean = false;
  // 展开屏上记住用户本次唤起菜单的手指侧：-1 左侧，1 右侧。
  @State readerMenuAnchorSide: number = 1;
  @State showReaderActionMenu: boolean = false;
  @State showLayoutElementSettings: boolean = false;
  private txtCharsetDialogSession: SystemDialogSession = new SystemDialogSession();
  private readerCacheDialogSession: SystemDialogSession = new SystemDialogSession();
  private chapterCacheDialogSession: SystemDialogSession = new SystemDialogSession();
  private tapZoneDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showTxtCharsetDialog: boolean = false;
  // Mirrors the charset dialog's "re-parsing" flag so the page does not dismiss it midway.
  private txtCharsetApplying: boolean = false;
  @State showReaderCommentPanel: boolean = false;
  @State readerCommentPanelTitle: string = '段评';
  @State readerCommentPanelUrl: string = '';
  @State readerCommentPanelProgress: number = 0;
  @State readerCommentPanelLoading: boolean = false;
  @State readerCommentPanelError: boolean = false;
  @State readerCommentPanelHeight: number = 0;
  private readerCommentPanelHtml: string = '';
  private readerCommentPanelBaseUrl: string = '';
  private readerCommentPanelHtmlLoaded: boolean = false;
  private readerCommentPanelLoadSerial: number = 0;
  private readerCommentPanelReadyTimerId: number = -1;
  @State showToc: boolean = false;
  @State bookmarks: Bookmark[] = [];
  @State showBookmarkActionMenu: boolean = false;
  @State pendingBookmarkAction: Bookmark | null = null;
  @State bookmarkActionMenuX: number = 16;
  @State bookmarkActionMenuY: number = 96;
  @State showSettings: boolean = false;
  @State @Watch('onSystemDialogFlagChanged') showTapZoneSettings: boolean = false;
  @State settingsPanelTab: number = 0;
  @State loadStatus: string = '正在加载...';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '网页验证';
  @State showChangeSourceDialog: boolean = false;
  @State pendingSwitchedBook: Book | null = null;
  @State contentPages: string[] = [];
  @State currentPageIndex: number = 0;
  @State currentPageText: string = '';
  @State displayPageText: string = '';
  @State displayPageChapterIndex: number = 0;
  @State displayPageIndex: number = 0;
  @State displayPageRenderKey: number = 0;
  @State pageRenderVersion: number = 0;
  @State chapterJumpRenderGeneration: number = 0;
  @State readerV2SurfaceGeneration: number = 0;
  @State pageViewWidth: number = 0;
  @State pageViewHeight: number = 0;
  @State readerBottomInfoBarMeasuredHeight: number = 0;
  @State readerInitialPageReady: boolean = false;
  @State readerInitialOpening: boolean = true;
  @State readerWebFetchRuntimeNeeded: boolean = false;
  @State readerComicMode: boolean = false;
  @State readerComicSettings: ReaderComicSettings = new ReaderComicSettings();
  @State readerComicTitleCapsuleWidth: number = 0;
  /** 本书单独选的漫画阅读方式（书籍变量 readerComicReadingMode）；空串跟随全局默认。 */
  @State readerComicBookMode: string = '';
  /** 本书漫画图片繁→简（书籍变量 readerComicTextConvert = t2s）。 */
  @State readerComicTextConvert: boolean = false;
  /** 翻页模式预先切好的相邻章节分页，翻过本话首尾时直接显示；章节号为 -1 表示没有。 */
  @State readerComicPagedPrevPages: string[] = [];
  @State readerComicPagedNextPages: string[] = [];
  private readerComicPagedPrevChapter: number = -1;
  private readerComicPagedNextChapter: number = -1;
  @State comicPageSliderActive: boolean = false;
  @State comicPageSliderPreview: number = 0;
  @State comicPageTooltipVisible: boolean = false;
  @State readerComicPaginationParsing: boolean = false;
  @State readerComicPaginationParsedPages: number = 0;
  @State readerComicPaginationTotalPages: number = 0;
  @State readerComicChapterSwitching: boolean = false;
  @State readerComicBoundaryDirection: number = 0;
  @State readerComicBoundaryPullDistance: number = 0;
  @State readerComicBoundaryReady: boolean = false;
  @State readerComicChapterTransitionY: number = 0;
  @State readerComicChapterTransitionOpacity: number = 1;
  private readerComicPaginationSource: string = '';
  @State statusBarSafeHeight: number = 0;
  @StorageProp('statusBarHeight') @Watch('onStoredStatusBarHeightChanged') storedStatusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  /** 会员档位变化（登录、开通、到期）时刷新漫画超分、繁→简的可用状态。 */
  @StorageProp('accountMembershipSku') readerMembershipSku: string = '';
  // 加密的书源封面解密完成后递增，朗读面板等处的封面重新取到本地文件地址。
  @StorageProp('sourceCoverRevision') sourceCoverRevision: number = 0;
  @State isTtsSpeaking: boolean = false;
  @State isTtsPaused: boolean = false;
  @State showTtsQuickPlayer: boolean = false;
  @StorageLink('globalTtsCapsulePositionX') ttsMiniPlayerPositionX: number = 16;
  @StorageLink('globalTtsCapsulePositionY') ttsMiniPlayerPositionY: number = -1;
  @State ttsDisplayText: string = '';
  @State ttsHighlightStart: number = -1;
  @State ttsHighlightEnd: number = -1;
  @State ttsHighlightRenderVersion: number = 0;
  @State readerV2TtsPaintVersion: number = 0;
  @State readerV2BrokenImageSources: string[] = [];
  // 已加载完成的图片：未完成时在图片位置显示加载动画，完成后图片淡入。
  @State readerV2LoadedImageSources: string[] = [];
  // 本地插图解码进缓存后加一，让已挂着文件地址的 Image 换成 PixelMap。
  @State readerV2ImageBitmapVersion: number = 0;
  @State readerV2SelectionPaintVersion: number = 0;
  @State ttsSleepTimerMinutes: number = 0;
  @State ttsSleepTimerRemainingSeconds: number = 0;
  @StorageLink('globalTtsActive') @Watch('onGlobalTtsActiveChanged') globalTtsActive: boolean = false;
  @StorageLink('globalTtsPaused') globalTtsPaused: boolean = false;
  @StorageLink('globalTtsBookName') globalTtsBookName: string = '';
  @StorageLink('globalTtsChapterTitle') globalTtsChapterTitle: string = '';
  @StorageLink('globalTtsMode') globalTtsMode: string = '';
  @StorageLink('globalTtsChapterProgress') globalTtsChapterProgress: string = '';
  @StorageLink('globalTtsCanPrevious') globalTtsCanPrevious: boolean = false;
  @StorageLink('globalTtsCanNext') globalTtsCanNext: boolean = false;
  @StorageLink('globalTtsBookUrl') globalTtsBookUrl: string = '';
  @StorageLink('globalTtsChapterIndex') globalTtsChapterIndex: number = -1;
  @StorageLink('globalTtsOffsetStart') globalTtsOffsetStart: number = -1;
  @StorageLink('globalTtsOffsetEnd') globalTtsOffsetEnd: number = -1;
  @StorageLink('globalTtsRevision') @Watch('onGlobalTtsRevisionChanged') globalTtsRevision: number = 0;
  @State showGlobalTtsQuickPlayer: boolean = false;
  @State showGlobalTtsCatalog: boolean = false;
  @State globalTtsCatalogReverseOrder: boolean = false;
  private ttsFloatingSessionOwnerId: string = `reader_${Date.now()}_${Math.random()}`;
  private ttsMiniPlayerDragOriginX: number = 0;
  private ttsMiniPlayerDragOriginY: number = 0;
  private pendingRestorePageIndex: number = -1;
  private readerRestoreWatchdogRunning: boolean = false;
  private globalTtsCatalogScroller: ListScroller = new ListScroller();
  private globalTtsCatalogSource: CatalogTitleDataSource = new CatalogTitleDataSource();
  private readerComicScroller: ListScroller = new ListScroller();
  private readerComicPageDataSource: ReaderContinuousDataSource = new ReaderContinuousDataSource();
  /** 滚动越过章节边界、正在把列表里已有的这一章提升为当前章；-1 表示没有。 */
  private readerContinuousCommitChapter: number = -1;
  /** 最近一次列表可见区（列表序号，含相邻章节与分隔项）。 */
  private readerContinuousLastListStart: number = 0;
  private readerContinuousLastListEnd: number = 0;
  private readerNeighborLoaderInstance: ReaderNeighborChapterLoader | null = null;
  private readerComicImageActionsInstance: ReaderComicImageActions | null = null;
  private readerComicScrollRestoreSerial: number = 0;
  private readerComicScrollRestoring: boolean = false;
  private readerComicReanchorSerial: number = 0;
  private readerComicProgressSaveTimerId: number = -1;
  private readerPagedProgressSaveTimerId: number = -1;
  private readerComicPanLastOffsetY: number = 0;
  private readerComicPanMoved: boolean = false;
  /** 点击翻屏的逐帧滚动：定时器与尚未滚完的距离。 */
  private readerComicScreenScrollTimerId: number = -1;
  private readerComicScreenScrollRemaining: number = 0;
  // isAtEnd()/currentOffset() 是同步跨线程查询，手势更新事件频率高于刷新率；
  // 边界方向探测按时间片取样，提示徽标晚一两帧出现无感知。
  private readerComicBoundaryProbeNotUntil: number = 0;
  private readerComicBoundaryPullOriginY: number = 0;
  private readerContinuousScrollOffsetMemoAt: number = 0;
  private readerContinuousScrollOffsetMemo: number = 0;
  private readerComicSuppressClickUntil: number = 0;
  /** 条漫当前缩放倍数，按屏翻动时换算成列表内的滚动距离。 */
  private readerComicZoomScale: number = 1;
  private readerComicPagedController: ReaderComicPagedController = new ReaderComicPagedController();
  private ttsReader: SystemTtsReader = new SystemTtsReader();
  private ttsAutoContinue: boolean = false;
  private ttsReadToken: number = 0;
  private ttsChapterSwitching: boolean = false;
  private ttsChapterAdvanceError: string = '';
  private ttsLastMediaChapterCommandAt: number = 0;
  private ttsTextStartOffset: number = 0;
  // The speech engine reports completion independently from the reader's page state. Keep the expected source
  // tail so a premature onFinished callback cannot advance to the next chapter while trailing chunks are pending.
  private ttsReadingExpectedSourceEnd: number = -1;
  private ttsChapterCompletionRetryCount: number = 0;
  private ttsLastFocusChunk: TtsChunk | null = null;
  private ttsLastFocusPageIndex: number = -1;
  private ttsFocusGeneration: number = 0;
  private ttsFocusChapterIndex: number = -1;
  private ttsFocusSourceIdentity: string = '';
  private ttsFocusContentLoadSerial: number = -1;
  private ttsLastAppliedSourceOffset: number = -1;
  private ttsSurfaceFocusSyncSerial: number = 0;
  private ttsPaginationFocusSyncSerial: number = 0;
  private ttsResumeSyncSerial: number = 0;
  private mirroredTtsFocusSyncSerial: number = 0;
  @State mirroredTtsFocusActive: boolean = false;
  private mirroredTtsManualTurnPending: boolean = false;
  private mirroredTtsManualTurnTimerId: number = -1;
  private mirroredTtsManualTurnSerial: number = 0;
  private ttsProgressSaveTimerId: number = -1;
  private ttsAutoTurningPage: boolean = false;
  private ttsPageTurnSerial: number = 0;
  private ttsPendingTargetPageIndex: number = -1;
  private ttsPendingHighlightChunk: TtsChunk | null = null;
  private ttsManualPageTurnResumePending: boolean = false;
  private ttsManualPageTurnResumeTimerId: number = -1;
  private ttsManualPageTurnResumeSerial: number = 0;
  private ttsManualPageTurnStartedAt: number = 0;
  private ttsMedia: ReaderTtsMediaSession | null = null;
  private ttsSpeedSaveTimerId: number = -1;
  private ttsSpeedAvSessionTimerId: number = -1;
  private ttsSpeedRestartTimerId: number = -1;
  private ttsSpeedRestartSerial: number = 0;
  private ttsSleepTimerId: number = -1;
  private ttsSleepTimerEndAt: number = 0;
  private contentPageStarts: number[] = [];
  private contentPageEnds: number[] = [];
  private pagedContentText: string = '';
  private readerPaginationCache: Map<string, ReaderPaginationResult> = new Map();
  private readerV2PageSetCache: Map<string, ReaderV2PageSet> = new Map<string, ReaderV2PageSet>();
  private readerV2DocumentCache: Map<string, ReaderV2Document> = new Map<string, ReaderV2Document>();
  private readerContinuousV2Layouts: Map<string, ReaderV2PageLayout> = new Map<string, ReaderV2PageLayout>();
  // layout.identity -> [chunk start in the chapter source, parsed chunk document]
  private readerContinuousV2Sources: Map<string, number> = new Map<string, number>();
  private readerContinuousV2Documents: Map<string, ReaderV2Document> = new Map<string, ReaderV2Document>();
  private readerContinuousV2Controllers: Map<string, ReaderV2PageNodeController> =
    new Map<string, ReaderV2PageNodeController>();
  private readerV2SelectionExtraGaps: Map<string, number> = new Map<string, number>();
  private readerV2SelectionShownHostVersion: number = -1;
  private readerV2ImageBitmaps: ReaderImageBitmapCache = new ReaderImageBitmapCache();
  private readerV2Controllers: Map<string, ReaderV2PageNodeController> =
    new Map<string, ReaderV2PageNodeController>();
  private readerV2SelectionStyledTextCache: Map<string, MutableStyledString> =
    new Map<string, MutableStyledString>();
  private readerV2ActiveDocument: ReaderV2Document | null = null;
  private readerV2ActiveSnapshot: ReaderV2LayoutSnapshot | null = null;
  private readerV2ActiveSpeechText: ReaderV2SpeechText | null = null;
  private readerV2TtsSourceStart: number = -1;
  private readerV2TtsSourceEnd: number = -1;
  private readerPreparedContentCache: Map<string, string> = new Map();
  private readerParagraphMetricsCache: Map<string, ReaderParagraphMetrics> = new Map();
  private readerAdaptiveLineHeightCache: Map<string, number> = new Map();
  // 滚动模式下每个分块的正文解析在选择层、渲染层、测量层被反复调用；按块文本缓存切分结果，
  // 避免快速滑动时每个新 LazyForEach 项重复做整块正则归一化与逐段切分。
  private readerTextParagraphsCache: Map<string, ReaderTextParagraph[]> = new Map();
  private readerPaginationBottomFitTimerId: number = -1;
  private cachedRegexRulesKey: string = '';
  private cachedRegexRules: ReaderRegexFontRule[] = [];
  private adjacentPaginationPreloadSerial: number = 0;
  private previousPaginationPreloadSerial: number = 0;
  private adjacentPaginationPreloadActiveSerial: number = -1;
  private adjacentPaginationPreloadActiveKey: string = '';
  private previousPaginationPreloadActiveSerial: number = -1;
  private previousPaginationPreloadActiveKey: string = '';
  private readerPaginationWorkSerial: number = 0;
  private readerPaginationInteractionIdleUntil: number = 0;
  private pageTurnPreviewKey: string = '';
  private pageTurnPreviewLoadingKey: string = '';
  private readerPageCurlPainter: ReaderPageCurlPainter = new ReaderPageCurlPainter();
  private readerEmulationFlipPainter: ReaderEmulationFlipPainter = new ReaderEmulationFlipPainter();
  // 拖动翻页时记录手指落点所在的区域；READER_CURL_REGION_UNSET 表示本次翻页不是由拖动发起的。
  private readerCurlStartRegion: number = READER_CURL_REGION_UNSET;
  private readerPageCurlContext: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private readerPageCurlFront: image.PixelMap | null = null;
  private readerPageCurlBack: image.PixelMap | null = null;
  private readerPageCurlSnapshotHeight: number = 0;
  private readerPageCurlCaptureKey: string = '';
  private readerPageCurlCaptureSerial: number = 0;
  private readerPageCurlCapturePending: boolean = false;
  private readerPageCurlCanvasReady: boolean = false;
  private readerPageCurlOffset: number = 0;
  private readerPageCurlAnimator: AnimatorResult | null = null;
  private readerPageCurlAnimationSerial: number = 0;
  @State readerPageCurlSnapshotReady: boolean = false;
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
  @State pageTurnIncomingPageStart: number = -1;
  @State pageTurnIncomingSecondaryPageStart: number = -1;
  @State pageTurnIncomingDocumentSource: string = '';
  @State pageTurnIncomingRenderVersion: number = 0;
  private bookLoadSerial: number = 0;
  private contentLoadSerial: number = 0;
  private isPageTurning: boolean = false;
  private pageTurnQueue: ReaderPageTurnQueue = new ReaderPageTurnQueue();
  private readerFontRefreshSerial: number = 0;
  private pendingScrollPreviousChapterTurn: boolean = false;
  private pageTurnCrossChapterHandoff: boolean = false;

  private lastRecentReadCardReloadAt: number = 0;
  private lastRecentReadCardChapterIndex: number = -1;
  private readerTouchStartX: number = 0;
  private readerTouchStartY: number = 0;
  private readerTouchLastX: number = 0;
  private readerTouchLastY: number = 0;
  private readerTouchActive: boolean = false;
  private readerTouchMoved: boolean = false;
  private suppressReaderTapClick: boolean = false;
  private readerInteractiveActionUntil: number = 0;
  private readerSourceActionOpenedAt: number = 0;
  private readerTouchActionMarker: string = '';
  private readerInlineTouchActionMarker: string = '';
  private readerSourceActionAreas: Map<string, number[]> = new Map<string, number[]>();
  private readerSourceActionScrollOffsets: Map<string, number[]> = new Map<string, number[]>();
  private readerPendingInlineActionBounds: Map<string, ReaderInlineActionBoundsTask> =
    new Map<string, ReaderInlineActionBoundsTask>();
  private readerPendingMergedActionBounds: Map<string, ReaderMergedActionBoundsTask> =
    new Map<string, ReaderMergedActionBoundsTask>();
  private readerActionMatchCache: Map<string, ReaderActionMatch> = new Map<string, ReaderActionMatch>();
  private readerSourceSettingCacheKey: string = '';
  private readerSourceSettingCacheRevision: string = '';
  private readerSourceSettingCacheContentRule: string = '';
  private readerSourceSettingCacheJsLib: string = '';
  private readerSourceHasCommentBubbleScript: boolean = false;
  private readerSourceActionBoundsFlushPending: boolean = false;
  private readerInlineActionTextControllers: Map<string, TextController> = new Map<string, TextController>();
  private readerSelectableTextControllers: Map<string, TextController> = new Map<string, TextController>();
  private readerSelectableTextAreas: Map<string, number[]> = new Map<string, number[]>();
  private readerSelectableTextScrollOffsets: Map<string, number> = new Map<string, number>();
  private readerSelectableTextValues: Map<string, string> = new Map<string, string>();
  @State private readerTextSelectionActive: boolean = false;
  private readerTextSelectionUntil: number = 0;
  private readerTextSelectionSerial: number = 0;
  private readerV2SelectionChapterIndex: number = -1;
  private readerV2SelectionPageIndex: number = -1;
  private readerV2SelectionDisplayStart: number = -1;
  private readerV2SelectionDisplayEnd: number = -1;
  @State private readerV2NativeSelectionHostVersion: number = 0;
  private readerV2NativeSelectionChapterIndex: number = -1;
  private readerV2NativeSelectionPageIndex: number = -1;
  private readerV2NativeSelectionFragmentIndex: number = -1;
  private readerV2NativeSelectionRole: string = '';
  private readerV2NativeSelectionPendingStart: number = -1;
  private readerV2NativeSelectionPendingEnd: number = -1;
  private readerV2NativeSelectionPendingSerial: number = -1;
  @State private readerV2NativeSelectionOffsetX: number = 0;
  @State private readerV2NativeSelectionOffsetY: number = 0;
  private readerContinuousVisibleStart: number = 0;
  private readerContinuousVisibleEnd: number = 0;
  private readerContinuousReachedEnd: boolean = false;
  private readerContinuousPointerGlobalX: number = -1;
  private readerContinuousPointerGlobalY: number = -1;
  private readerContinuousPointerAt: number = 0;
  private readerContinuousSelectionTimerId: number = -1;
  private readerContinuousSelectionDownX: number = -1;
  private readerContinuousSelectionDownY: number = -1;
  private readerContinuousSelectionDownAt: number = 0;
  private readerContinuousSelectionMoved: boolean = false;
  // A tap outside a live selection dismisses it. The pointer is tracked separately from the page-turn
  // gesture state because a selection owns the stream: no page turn, menu or scroll may run.
  private readerSelectionDismissDownX: number = -1;
  private readerSelectionDismissDownY: number = -1;
  private readerSelectionDismissDownAt: number = 0;
  private readerSelectionDismissMoved: boolean = false;
  // True only for a pointer stream whose Down began while a selection was already live. The release of
  // the long press that CREATES a selection also ends a stream; that stream must never dismiss it.
  private readerSelectionDismissArmed: boolean = false;
  private readerTextSelectionClearPending: boolean = false;
  private readerTapLayerGlobalX: number = 0;
  private readerTapLayerGlobalY: number = 0;
  // Paragraph-comment pills are visually small, but their interaction target should be close to the platform
  // 44vp recommendation. Expansion remains geometry-only and never changes pagination or painted bubble size.
  private readerSourceActionHitSlopX: number = 20;
  private readerSourceActionHitSlopY: number = 16;
  private readerTapSlop: number = 12;
  // 翻页提交距离下限；实际阈值按页面尺寸比例计算，避免手指只动一点点就把整页翻过去。
  private readerPageTurnCommitDistance: number = 18;
  private readerPageTurnDirectionRatio: number = 0.8;
  private readerPageTurnCommitRatio: number = 0.2;
  private readerPageTurnFlickRatio: number = 0.06;
  private readerPageTurnFlickVelocity: number = 800;
  private readerBookmarkPullStartDistance: number = 48;
  private readerBookmarkPullDirectionRatio: number = 1.5;
  private readerPanActive: boolean = false;
  private readerPanIntent: number = READER_PAN_INTENT_NONE;
  private readerPageTurnGestureCommitted: boolean = false;
  private readerGestureTurnGuardUntil: number = 0;
  private readerGestureTurnAllowance: number = 0;
  private slideResetSerial: number = 0;
  @StorageLink('readerFontWeight') @Watch('onReadLayoutChanged') readerFontWeight: number = 400;
  @StorageLink('readerFontSize') @Watch('onReadLayoutChanged') readerFontSize: number = 20;
  @StorageLink('readerLetterSpacing') @Watch('onReadLayoutChanged') readerLetterSpacing: number = 0;
  @StorageLink('readerTextAlign') @Watch('onReadLayoutChanged') readerTextAlign: string = 'justify';
  @StorageLink('readerLineHeight') @Watch('onReadLayoutChanged') readerLineHeight: number = 12;
  @StorageLink('readerParagraphSpacing') @Watch('onReadLayoutChanged') readerParagraphSpacing: number = 0;
  @StorageLink('readerParagraphIndent') @Watch('onReadLayoutChanged') readerParagraphIndent: number = 2;
  @StorageLink('readerMarginLeft') @Watch('onReadLayoutChanged') readerMarginLeft: number = 18;
  @StorageLink('readerMarginRight') @Watch('onReadLayoutChanged') readerMarginRight: number = 18;
  @StorageLink('readerMarginTop') @Watch('onReadLayoutChanged') readerMarginTop: number = 18;
  @StorageLink('readerMarginBottom') @Watch('onReadLayoutChanged') readerMarginBottom: number = 18;
  @StorageLink('readerCommentBubbleSize') @Watch('onReadLayoutChanged') readerCommentBubbleSize: number = 100;
  @StorageLink('readerLightThemeIndex') @Watch('onReaderThemeChanged') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') @Watch('onReaderThemeChanged') readerDarkThemeIndex: number = 0;
  @StorageLink('readerLightCustomThemeBackgroundColor') @Watch('onReaderThemeChanged') readerLightCustomThemeBackgroundColor: string = ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerLightCustomThemeTextColor') @Watch('onReaderThemeChanged') readerLightCustomThemeTextColor: string = ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR;
  @StorageLink('readerDarkCustomThemeBackgroundColor') @Watch('onReaderThemeChanged') readerDarkCustomThemeBackgroundColor: string = ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerDarkCustomThemeTextColor') @Watch('onReaderThemeChanged') readerDarkCustomThemeTextColor: string = ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR;
  @StorageLink('readerCustomThemesRaw') @Watch('onReaderThemeChanged') readerCustomThemesRaw: string = '';
  @StorageLink('readerPageTurnMode') readerPageTurnMode: number = 1;
  @StorageLink('readerPageTurnAnimationType') @Watch('onReaderPageTurnAnimationChanged') readerPageTurnAnimationType: number = ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
  @StorageLink('readerLandscapeDoublePage') @Watch('onReaderLandscapeDoublePageChanged') readerLandscapeDoublePage: boolean = false;
  @StorageLink('readerScreenOrientation') @Watch('onReaderScreenOrientationChanged') readerScreenOrientation: string =
    ReaderSettingsStore.SCREEN_ORIENTATION_SYSTEM;
  @StorageLink('readerTapZoneActions') readerTapZoneActions: string = '3,3,3,3,1,2,2,2,2';
  @StorageLink('readerVolumeTurnPage') @Watch('onReaderVolumeTurnPageChanged') readerVolumeTurnPage: boolean = false;
  @StorageLink('readerEyeTurnEnabled') readerEyeTurnEnabled: boolean = false;
  @StorageLink('readerEyeTurnPortraitCalibration') readerEyeTurnPortraitCalibration: string = '';
  @StorageLink('readerEyeTurnLandscapeCalibration') readerEyeTurnLandscapeCalibration: string = '';
  @StorageLink('readerEyeTurnPreviousEnabled') readerEyeTurnPreviousEnabled: boolean = false;
  @StorageLink('readerEyeTurnNextEnabled') readerEyeTurnNextEnabled: boolean = true;
  @StorageLink('readerEyeTurnPreviousDwellMs') readerEyeTurnPreviousDwellMs: number = 850;
  @StorageLink('readerEyeTurnNextDwellMs') readerEyeTurnNextDwellMs: number = 650;
  @StorageLink('readerScreenTimeoutMinutes') readerScreenTimeoutMinutes: number =
    ReaderSettingsStore.SCREEN_TIMEOUT_ALWAYS_ON;
  @StorageLink('readerExtendToStatusBar') @Watch('onReaderExtendToStatusBarChanged') readerExtendToStatusBar: boolean = false;
  @StorageLink('readerPreloadEnabled') @Watch('onReaderPreloadChanged') readerPreloadEnabled: boolean = true;
  @StorageLink('readerPreloadChapterCount') @Watch('onReaderPreloadChanged') readerPreloadChapterCount: number = 1;
  @StorageLink('readerUseTtsQuickAction') readerUseTtsQuickAction: boolean = true;
  @StorageLink('readerUseChapterQuickJump') readerUseChapterQuickJump: boolean = true;
  @StorageLink('readerQuickBookmarkEnabled') readerQuickBookmarkEnabled: boolean = true;
  @StorageLink('readerHeaderEnabled') @Watch('onReaderChromeChanged') readerHeaderEnabled: boolean = false;
  @StorageLink('readerFooterEnabled') @Watch('onReaderChromeChanged') readerFooterEnabled: boolean = true;
  // 页眉页脚的槽位与外观，ReaderInfoBarConfig 的 JSON；解析结果缓存在 readerInfoBarConfigCache。
  @StorageLink('readerInfoBarConfig') @Watch('onReaderChromeChanged') readerInfoBarConfigRaw: string = '';
  @State readerInfoTimeText: string = '';
  @State readerInfoBatteryPercent: number = -1;
  private readerInfoBarConfigCache: ReaderInfoBarConfig = new ReaderInfoBarConfig();
  private readerInfoBarConfigCacheRaw: string = '';
  private readerInfoBarLayoutIdentity: string = '';
  private readerInfoBarClock: ReaderInfoBarClock | null = null;
  // 分页区域下缘到窗口下缘的实测距离（vp）。窗口为全屏布局时分页区域本身就铺到窗口底部，该值为 0；
  // 只有系统仍为导航条保留了布局安全区时才大于 0。-1 表示尚未测量。
  private readerPageAreaBottomGap: number = -1;
  // 重新排版（改排版设置、折叠屏展开合上、窗口尺寸变化）后，新的分页会话可能还没排到当前页，
  // 可见页面此时挂载的是纯文本兜底。等当前页排出来后需要重新挂载一次页面宿主。
  private readerRelayoutRepaintPending: boolean = false;
  @StorageLink('readerReplaceRulesUpdateTime') @Watch('onReaderReplaceRulesChanged') readerReplaceRulesUpdateTime: number = 0;
  @StorageLink('readerFontFamily') @Watch('onReaderFontChanged') readerFontFamily: string = '';
  @StorageLink('readerFontFilePath') @Watch('onReaderFontChanged') readerFontFilePath: string = '';
  @StorageLink('readerSystemFontFamily') @Watch('onReaderActiveFontChanged') readerSystemFontFamily: string = '';
  // 全局字体模式：跟随系统或跟随主题会改变没选自定义字体时的正文字体。
  @StorageLink('readerFontMode') @Watch('onReaderActiveFontChanged') readerGlobalFontMode: string = 'device';
  @StorageLink('readerActiveFontFamily') @Watch('onReaderActiveFontChanged') readerActiveFontFamily: string = '';
  @StorageLink('readerFontRegistered') @Watch('onReaderActiveFontChanged') readerStoredFontRegistered: boolean = false;
  // 手机换了系统字体时由 EntryAbility 加一；字体名可能不变（sans-serif），所以单独计入排版缓存键。
  @StorageLink('systemFontRevision') @Watch('onSystemFontRevisionChanged') systemFontRevision: number = 0;
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
  @StorageLink('appDarkMode') @Watch('onReaderColorModeChanged') appDarkMode: boolean = false;
  @StorageLink('appThemeMode') appThemeMode: string = 'system';
  @StorageLink('appThemeBookCoverEnabled') themeBookCoverEnabled: boolean = false;
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
  @StorageLink('ttsCloudVoiceId') ttsCloudVoiceId: string = '';
  @StorageLink('launchShortcutNonce') @Watch('onLaunchShortcutChanged') launchShortcutNonce: number = 0;
  @StorageLink('fullTextCacheCancelNonce') @Watch('onFullTextCacheCancelNonceChanged') fullTextCacheCancelNonce: number = 0;
  @State ttsVoices: TtsVoiceOption[] = [TtsVoiceCatalog.defaultVoice()];
  @State ttsCustomVoiceOptions: HttpTTS[] = [];
  @State ttsCloudVoices: TtsVoiceInfo[] = [];
  @State ttsSelectedVoiceKey: string = '';
  @State ttsVoicesLoading: boolean = false;
  @State showTtsVoiceDropdown: boolean = false;
  @State fullTextCaching: boolean = false;
  @State fullTextCacheDone: number = 0;
  @State fullTextCacheTotal: number = 0;
  @State fullTextCacheStatus: string = '';
  @State @Watch('onSystemDialogFlagChanged') showReaderCacheDialog: boolean = false;
  @State @Watch('onSystemDialogFlagChanged') showReaderChapterCacheDialog: boolean = false;
  private fullTextCache: ReaderFullTextCacheController | null = null;
  private volumeUpCallback?: (event: KeyEvent) => void;
  private volumeDownCallback?: (event: KeyEvent) => void;
  private lastLoggedReaderFontFamily: string = '';
  private readerFontChangeSerial: number = 0;
  private readerLayoutApplyTimerId: number = -1;
  private readerLayoutStabilizeTimerId: number = -1;
  private readerExtendLayoutRefreshTimerId: number = -1;
  private readerBottomInfoBarMeasureTimerId: number = -1;
  private readerBottomInfoBarPendingHeight: number = 0;
  private readerExtendLayoutReadingOffset: number = -1;
  private readerTypographyRestoreOffset: number = -1;
  // Theme changes can publish appDarkMode and themeRevision in the same frame. Keep a single
  // re-pagination transaction for that pair so the visible page does not jump twice.
  private readerThemeRefreshTimerId: number = -1;
  private readerThemeRefreshOffset: number = -1;
  private readerPageContentTopPaddingSnapshot: number = -1;
  private readerLayoutCommitInProgress: boolean = false;
  private readerTypographyDraftPending: boolean = false;
  private readerTypographyDraft: number[] = [];
  private readingProgressSaveQueue: Promise<void> = Promise.resolve();
  private readerProgressAnchorChapterIndex: number = -1;
  private readerProgressAnchorPageIndex: number = 0;
  private readerProgressAnchorOffset: number = -1;
  private readerProgressAnchorPageCount: number = 1;
  private readerProgressAnchorPageText: string = '';
  private readerProgressAnchorPageImage: string = '';
  // A freshly mounted reader can publish the first incremental pages before the saved offset/page is restored.
  // Until that restore is confirmed, lifecycle saves must keep using the immutable database snapshot below.
  private readerProgressRestoreConfirmed: boolean = false;
  private readerExitProgressSaved: boolean = false;
  private readerPageDetachedFromRoute: boolean = false;
  private detachedReaderEngine: ReadBookEngine | null = null;
  private detachedReaderEngineReady: Promise<void> | null = null;
  private openedFromShortcut: boolean = false;
  private shortcutReplacedPreviousPage: boolean = false;
  private shortcutRoutingActive: boolean = false;
  private readerEntryInitializing: boolean = true;
  private readerSettingsReloadSerial: number = 0;
  private returningFromReaderReplaceRules: boolean = false;
  private openedWithShelfAnimation: boolean = false;
  private readerScreenTimeoutTimerId: number = -1;
  private readerScreenTimeoutSerial: number = 0;
  private readerScreenOrientationSerial: number = 0;
  private readerObservedBackgroundRevision: number = 0;
  private readerPageVisible: boolean = false;
  private readerCommentPanelMarker: string = '';
  private readerCommentPanelAnchorBottom: number = -1;
  private readerCommentPageAreaTop: number = -1;
  private readerCommentPageAreaHeight: number = 0;
  private readerCommentPanelController: webview.WebviewController = new webview.WebviewController();
  private readerCommentNavigationBridge: ReaderCommentNavigationBridge = new ReaderCommentNavigationBridge(
    () => this.backReaderCommentPanel(), () => this.closeReaderCommentPanel());
  @State eyeTurnState: ReaderEyeTurnViewState = new ReaderEyeTurnViewState();
  private eyeTurnCoordinator?: ReaderEyeTurnCoordinator;
  private readerEyeTurnSurfaceController: XComponentController = new XComponentController();

  async aboutToAppear() {
    ReaderProgressCheckpoint.attach(this.ttsFloatingSessionOwnerId,
      (): Promise<void> => this.flushReadingProgressCheckpoint(), (): string => this.bookUrl);
    this.readerPageVisible = true;
    this.readerObservedBackgroundRevision = AppStorage.get<number>('appLifecycleBackgroundRevision') || 0;
    this.applyReaderStatusBarSafeHeight(this.storedStatusBarHeight);
    this.applyReaderScreenOrientation();
    this.shortcutRoutingActive = true;
    this.readerEntryInitializing = true;
    this.enterReaderImmersive();
    this.updateVolumeKeySubscription();
    const params = router.getParams() as Record<string, string>;
    this.openedWithShelfAnimation = !!params && params['shelfBookOpening'] === 'true';
    this.openedFromShortcut = !!params && params['shortcutEntry'] === 'true';
    this.shortcutReplacedPreviousPage = !!params && params['shortcutReplace'] === 'true';
    if (params && params['bookUrl']) {
      this.bookUrl = params['bookUrl'];
      ReaderOpenTrace.beginIfNeeded(this.bookUrl);
      ReaderOpenTrace.mark(this.bookUrl, 'reader-page-appear');
      this.isLoading = true;
      this.loadStatus = '正在加载...';
      this.resetReaderStateForBookLoad();
      this.readerEngine().prewarmOpen(this.bookUrl).catch((error: Error) => {
        console.warn('[ReaderOpen] reader prewarm failed:', error);
      });
    }
    try {
      let initialReplaceRules: ReaderReplaceRule[] = [];
      await Promise.all([
        this.loadReaderSettings(),
        ReaderReplaceRuleStore.load(getContext(this)).then((rules: ReaderReplaceRule[]): void => {
          initialReplaceRules = rules;
        })
      ]);
      this.readerReplaceRules = initialReplaceRules;
      ReaderOpenTrace.mark(this.bookUrl, 'reader-settings-ready', `replaceRules=${initialReplaceRules.length}`);
      this.loadTtsSettingsAndVoices();
      if (this.bookUrl) {
        await this.loadBook();
        this.loadBookmarks().catch((error: Error) => {
          console.warn('读取书签失败:', error);
        });
    }
    } catch (error) {
      console.error('[ReaderOpen] reader entry initialization failed:', error);
      if (!this.content) {
        this.setReaderContent('打开书籍失败。请返回书架后重试。');
      }
      this.isLoading = false;
    } finally {
      this.readerEntryInitializing = false;
    }
  }

  onPageShow(): void {
    this.readerPageVisible = true;
    this.syncReaderInfoBarClock();
    readStatsTracker.setReadingActive(this.bookUrl);
    const backgroundRevision = AppStorage.get<number>('appLifecycleBackgroundRevision') || 0;
    const returningFromBackground = backgroundRevision > this.readerObservedBackgroundRevision;
    this.readerObservedBackgroundRevision = backgroundRevision;
    this.resumeReaderPaginationWorkAfterPageShow();
    if (this.pagedContentText && this.shouldUseReaderLayoutV2(this.pagedContentText) &&
      !this.readerV2PageSet(this.currentChapterIndex, this.pagedContentText)) {
      this.readerInitialPageReady = false;
      this.pendingRestorePageIndex = Math.max(this.pendingRestorePageIndex, this.currentPageIndex);
      this.paginateContent(this.content);
    }
    if (returningFromBackground) {
      // The chapter-scoped V2 ForEach host can be retained from the page on which the chapter was first mounted.
      // Give a real foreground resume a fresh host so ArkUI cannot replay that old subtree after the controller has
      // already been rebound to the current page. Ordinary page turns still reuse one native node.
      this.readerV2SurfaceGeneration++;
      this.republishCurrentReaderPageAfterBackground();
    }
    this.applyReaderScreenOrientation();
    this.applyReaderScreenTimeout();
    this.shortcutRoutingActive = true;
    // onNewWant 先于 onPageShow 写入快捷项，那时 @Watch 因页面隐藏而忽略，这里补一次。
    this.openPendingShortcut();
    const returningFromReplaceRules = this.returningFromReaderReplaceRules;
    this.returningFromReaderReplaceRules = false;
    if (!this.readerEntryInitializing && !returningFromBackground) {
      if (returningFromReplaceRules) {
        // 规则页只会改变替换净化配置，返回时仅重载规则并重排一次。
        this.reloadReaderReplaceRules(true).catch((error: Error) => {
          console.warn('恢复替换净化规则失败:', error);
        });
      } else {
        this.reloadReaderSettingsAfterPageShow().catch((error: Error) => {
          console.warn('恢复阅读设置失败:', error);
        });
        this.reloadReaderReplaceRules(true).catch((error: Error) => {
          console.warn('恢复替换净化规则失败:', error);
        });
        this.reloadSourceInteractionsAfterPageShow().catch((error: Error) => {
          console.warn('恢复书源交互设置失败:', error);
        });
      }
    }
    if (!returningFromReplaceRules) {
      this.reregisterReaderFontAfterShow(0);
      this.reregisterReaderFontAfterShow(120);
    }
    this.syncTtsFocusAfterResumeLater(0);
    this.syncTtsFocusAfterResumeLater(180);
    this.eyeTurn().startIfReady();
  }

  onGlobalTtsActiveChanged(): void {
    if (!this.globalTtsActive) {
      this.showGlobalTtsQuickPlayer = false;
      this.clearMirroredTtsFocus();
    }
  }

  onGlobalTtsRevisionChanged(): void {
    if (!this.isMirroringActiveTtsForCurrentBook()) {
      return;
    }
    // The hidden owner can still publish the outgoing sentence while this mirror is animating a
    // manual turn. Applying it here would snap the visible page back before the target is committed.
    if (this.mirroredTtsManualTurnPending) return;
    this.syncMirroredTtsFocus().catch((error: Error) => {
      console.warn('同步后台朗读正文焦点失败:', error);
    });
  }

  onBackPress(): boolean {
    if (this.eyeTurnState.showCalibration) {
      this.eyeTurn().cancelCalibration();
      return true;
    }
    if (this.showReaderCommentPanel) {
      this.closeReaderCommentPanel();
      return true;
    }
    if (this.showGlobalTtsCatalog) {
      this.closeGlobalTtsCatalog();
      return true;
    }
    if (this.showTtsQuickPlayer) {
      this.closeTtsQuickPlayer();
      return true;
    }
    if (this.showGlobalTtsQuickPlayer) {
      this.closeGlobalTtsQuickPlayer();
      return true;
    }
    if (this.showTtsVoiceDropdown) {
      this.showTtsVoiceDropdown = false;
      return true;
    }
    if (this.showTxtCharsetDialog) {
      if (!this.txtCharsetApplying) this.showTxtCharsetDialog = false;
      return true;
    }
    if (this.showTapZoneSettings) {
      this.showTapZoneSettings = false;
      return true;
    }
    if (this.showLayoutElementSettings) {
      this.showLayoutElementSettings = false;
      return true;
    }
    if (this.showBookmarkActionMenu) {
      this.closeBookmarkActionMenu();
      return true;
    }
    if (this.showChangeSourceDialog) {
      this.showChangeSourceDialog = false;
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
    const paginationSource = this.pagedContentText;
    const previousPaginationKey = paginationSource ?
      this.buildReaderPaginationCacheKey(this.currentChapterIndex, paginationSource) : '';
    const settings = await ReaderSettingsStore.reload(getContext(this));
    if (reloadSerial !== this.readerSettingsReloadSerial) {
      return;
    }
    ReaderSettingsStore.applyToStorage(settings);
    this.applyLoadedReaderSettings(settings);
    this.loadReaderComicSettings();
    this.cachedRegexRulesKey = '';
    this.cachedRegexRules = [];
    this.refreshReaderTextRender();
    const nextPaginationKey = paginationSource ?
      this.buildReaderPaginationCacheKey(this.currentChapterIndex, paginationSource) : '';
    const missingV2Pagination = !!paginationSource && this.shouldUseReaderLayoutV2(paginationSource) &&
      !this.readerV2PageSet(this.currentChapterIndex, paginationSource);
    if (previousPaginationKey && previousPaginationKey === nextPaginationKey && !missingV2Pagination) {
      return;
    }
    this.pendingRestorePageIndex = Math.max(this.pendingRestorePageIndex, this.currentPageIndex);
    this.readerPaginationCache.clear();
    this.paginateContent(this.content);
  }

  async reloadSourceInteractionsAfterPageShow(): Promise<void> {
    if (!this.book || this.book.origin === 'local' || this.chapters.length === 0) return;
    const engine = this.readerEngine();
    const changed = await engine.refreshSourceInteractionState();
    if (!changed) return;
    this.book = engine.book || this.book;
    this.chapters = [...engine.chapters];
    this.pendingRestorePageIndex = this.currentPageIndex;
    this.readerPaginationCache.clear();
    this.readerPreparedContentCache.clear();
    this.readerPaginationWorkSerial++;
    this.adjacentPaginationPreloadSerial++;
    this.previousPaginationPreloadSerial++;
    await this.loadContent(true, this.currentChapterIndex, true);
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
    AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
    // 离开阅读页后不再为它在后台补图片；回来时没补完的章节重新获取。
    this.readerEngine().setReaderImagesDeferred(false);
    this.resetReaderScreenOrientation();
    this.readerPageVisible = false;
    this.syncReaderInfoBarClock();
    readStatsTracker.setReadingActive('');
    this.eyeTurn().release('reader disappear release');
    this.setReaderTextSelectionActive(false);
    this.cancelReaderPaginationWork(true);
    this.resetReaderPageCurl();
    this.stopReaderComicScreenScroll();
    if (this.readerExtendLayoutRefreshTimerId >= 0) {
      clearTimeout(this.readerExtendLayoutRefreshTimerId);
      this.readerExtendLayoutRefreshTimerId = -1;
    }
    if (this.readerLayoutStabilizeTimerId >= 0) {
      clearTimeout(this.readerLayoutStabilizeTimerId);
      this.readerLayoutStabilizeTimerId = -1;
    }
    if (this.readerBottomInfoBarMeasureTimerId >= 0) {
      clearTimeout(this.readerBottomInfoBarMeasureTimerId);
      this.readerBottomInfoBarMeasureTimerId = -1;
    }
    if (this.readerPaginationBottomFitTimerId >= 0) {
      clearTimeout(this.readerPaginationBottomFitTimerId);
      this.readerPaginationBottomFitTimerId = -1;
    }
    if (this.readerThemeRefreshTimerId >= 0) {
      clearTimeout(this.readerThemeRefreshTimerId);
      this.readerThemeRefreshTimerId = -1;
    }
    this.readerThemeRefreshOffset = -1;
    this.readerBottomInfoBarPendingHeight = 0;
    this.readerExtendLayoutReadingOffset = -1;
    this.readerTypographyRestoreOffset = -1;
    this.flushPendingReaderLayoutChange(false);
    this.releaseReaderScreenTimeout();
    this.shortcutRoutingActive = false;
    this.flushPendingTtsSpeedSettings();
    this.cancelMirroredTtsManualPageTurn();
    const finalProgressSave = this.flushReadingProgressCheckpoint();
    this.readerPageDetachedFromRoute = true;
    if (!ReaderTtsFloatingSession.isOwner(this.ttsFloatingSessionOwnerId)) {
      this.stopTtsReading();
      this.ttsReader.shutdown();
    } else {
      // This page keeps reading aloud after it leaves the route stack. Without a retained write permission every
      // later sentence/chapter save was dropped and reopening the book returned to the exit position.
      ReaderProgressCheckpoint.retainBackground(this.ttsFloatingSessionOwnerId, (): string => this.bookUrl);
      this.detachReaderEngineForBackgroundTts();
    }
    if (!this.readerExitProgressSaved) {
      finalProgressSave.then(() => {
        return CloudSyncCoordinator.syncAutomatically(
          getContext(this), CloudSyncCoordinator.TRIGGER_CHANGE);
      }).catch((error: Error) => {
        console.error('离开阅读页保存进度失败:', error);
      });
    }
    // Keep this owner valid until its final serialized checkpoint settles. A newly attached reader replaces the
    // owner immediately, which invalidates this old write; detach(ownerId) cannot detach that newer owner.
    finalProgressSave.finally(() => {
      ReaderProgressCheckpoint.detach(this.ttsFloatingSessionOwnerId);
    });
    this.unregisterVolumeKeyTurn();
    this.exitReaderImmersive();
  }

  readerEngine(): ReadBookEngine {
    return this.detachedReaderEngine || ReadBookEngine.get();
  }

  detachReaderEngineForBackgroundTts(): void {
    if (this.detachedReaderEngine || !this.book) return;
    // The shared engine follows whichever reader page is visible. Reading aloud behind the bookshelf must keep
    // loading its own chapters after another book is opened, so it continues on a private engine.
    const fork = ReadBookEngine.forkSession(this.book.bookUrl);
    if (fork) {
      this.detachedReaderEngine = fork;
      return;
    }
    // A replacement reader page already took the shared engine; open this book again on a private one.
    const worker = ReadBookEngine.createBackgroundWorker();
    this.detachedReaderEngine = worker;
    this.detachedReaderEngineReady = worker.openBook(this.book).catch((error: Error) => {
      console.warn('[TTS] 后台朗读独立引擎打开书籍失败:', error);
    });
  }

  onLaunchShortcutChanged(): void {
    if (!this.shortcutRoutingActive) {
      return;
    }
    this.openPendingShortcut();
  }

  onPageHide(): void {
    this.shortcutRoutingActive = false;
    this.readerPageVisible = false;
    this.syncReaderInfoBarClock();
    readStatsTracker.setReadingActive('');
    this.eyeTurn().release('reader background release');
    this.setReaderTextSelectionActive(false);
    // Capture the authoritative visible page before pausing background workers. Clearing the retained V2
    // document here made canSaveReadingProgress() reject the checkpoint, then forced a full repagination on
    // foreground. Apart from losing progress, the freshly rebuilt page surface visibly jumped on the next turn.
    this.flushReadingProgressCheckpoint().catch((error: Error) => {
      console.warn('阅读页退到后台时保存进度失败:', error);
    });
    this.suspendReaderPaginationWork();
    this.releaseReaderScreenTimeout();
  }

  async openPendingShortcut(): Promise<void> {
    if (!RecentReadShortcut.isPending()) {
      return;
    }
    this.saveReadingProgress(true).catch((error: Error) => {
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
      const comicMode = this.isReaderComicModeActive();
      const bg = comicMode ? this.readerComicWindowColor() : this.getBackgroundColor();
      const useLightIcons = comicMode ? this.isReaderComicSurfaceDark() : this.isReaderThemeDark();
      const systemTextColor = useLightIcons ? '#D8D8D8' : '#2F261D';
      mainWindow.setWindowBackgroundColor(bg);
      mainWindow.setWindowLayoutFullScreen(true);
      // 漫画铺满全屏，时间与电量改由角落信息条显示。
      mainWindow.setWindowSystemBarEnable(comicMode || this.readerExtendToStatusBar ?
        ['navigation'] : ['navigation', 'status']);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        isStatusBarLightIcon: useLightIcons,
        statusBarContentColor: systemTextColor,
        navigationBarColor: comicMode ? '#00000000' : bg,
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
      this.applyReaderStatusBarSafeHeight(topHeight);
    } catch (err) {
      console.error('获取状态栏安全区失败:', err);
      this.applyReaderStatusBarSafeHeight(this.storedStatusBarHeight);
    }
  }

  onStoredStatusBarHeightChanged(): void {
    this.applyReaderStatusBarSafeHeight(this.storedStatusBarHeight);
  }

  applyReaderStatusBarSafeHeight(height: number): void {
    const previousHeight = this.statusBarSafeHeight;
    this.statusBarSafeHeight = Number.isFinite(height) ? Math.max(0, height) : 0;
    if (Math.abs(previousHeight - this.statusBarSafeHeight) >= 0.5 && this.hasPagedReaderArea() && this.content) {
      // The status-bar avoid area arrives asynchronously. In extended mode the reader area's
      // layout size itself does not change, so onAreaChange cannot trigger the required repagination.
      this.readerPaginationCache.clear();
      this.pageTurnPreviewKey = '';
      this.paginateContent(this.content);
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
      ReaderOpenTrace.mark(this.bookUrl, 'database-ready');

      const engine = this.readerEngine();
      const preparedBook = engine.getPreparedBook(this.bookUrl);
      // The retained engine is valuable for chapters/content, but its Book object can lag behind the serialized
      // exit checkpoint while the shelf close animation is refreshing. Always take progress metadata (including
      // the character-offset variable) from the database; ReadBookEngine will merge it into the retained session.
      const storedBook = await db.getBook(this.bookUrl);
      this.book = storedBook || preparedBook;
      ReaderOpenTrace.mark(this.bookUrl, 'book-record-ready',
        preparedBook ? 'sessionReused=true' : 'sessionReused=false');
      if (loadSerial !== this.bookLoadSerial) {
        return;
      }
      if (!this.book) {
        this.setReaderContent('书籍不存在，请先从搜索结果加入书架。');
        this.isLoading = false;
        return;
      }
      const sourceForType = this.book.origin && this.book.origin !== 'local' ?
        (engine.getPreparedSource(this.book.bookUrl, this.book.origin) || await db.getBookSource(this.book.origin)) :
        null;
      await this.prepareReaderWebFetchRuntime(sourceForType);
      BookTypeSupport.applyBookType(this.book, sourceForType);
      if (BookTypeSupport.isVideo(this.book)) {
        // 视频类书籍没有阅读形态：从书架等入口进来时直接转到播放页。
        ReaderOpenTrace.finish(this.bookUrl, 'redirect-video-player');
        await router.replaceUrl({
          url: 'pages/VideoPlayer',
          params: {
            bookUrl: this.book.bookUrl,
            chapterIndex: '',
            shelfBookOpening: this.openedWithShelfAnimation ? 'true' : 'false'
          }
        });
        return;
      }
      if (BookTypeSupport.isAudio(this.book)) {
        await db.updateBook(this.book, false);
        ReaderOpenTrace.finish(this.bookUrl, 'redirect-audio-reader');
        await router.replaceUrl({
          url: 'pages/AudioBook',
          params: {
            bookUrl: this.book.bookUrl,
            shelfBookOpening: this.openedWithShelfAnimation ? 'true' : 'false',
            shortcutEntry: this.openedFromShortcut ? 'true' : 'false',
            shortcutReplace: this.shortcutReplacedPreviousPage ? 'true' : 'false'
          }
        });
        return;
      }
      if (CloudAutoSync.isPlaceholder(this.book)) {
        // Opened from elsewhere than the shelf (e.g. a recent-read shortcut): fetch it first.
        this.loadStatus = '正在从云端下载书籍...';
        this.book = await CloudAutoSync.ensureBookDownloaded(getContext(this), this.book);
      }
      if (LocalBookService.isWebDavBook(this.book)) {
        this.loadStatus = '正在检查 WebDAV 书籍...';
        this.book = await WebDavBookService.ensureCached(getContext(this), this.book,
          (message: string): void => {
            this.loadStatus = message;
          });
      }
      if (this.book.origin === LocalBookService.ORIGIN) {
        this.loadStatus = '正在优化本地书籍...';
        const rebuilt = await LocalBookService.ensureLocalParserCurrent(getContext(this), this.book);
        if (rebuilt) {
          const rebuiltBook = await db.getBook(this.bookUrl);
          if (rebuiltBook) this.book = rebuiltBook;
        }
      }
      if (loadSerial !== this.bookLoadSerial) {
        return;
      }
      if (Book.hasStartedReading(this.book)) {
        this.markBookRecentlyRead().catch((error: Error) => {
          console.warn('更新最近阅读时间失败:', error);
        });
      }

      const requestedBookUrl = this.book.bookUrl;
      await engine.openBook(this.book, sourceForType);
      ReaderOpenTrace.mark(this.bookUrl, 'reader-engine-ready', `chapters=${engine.chapters.length}`);
      if (loadSerial !== this.bookLoadSerial || engine.book?.bookUrl !== requestedBookUrl) {
        return;
      }
      this.book = engine.book || this.book;
      this.chapters = engine.chapters;
      this.initializeReaderComicMode();
      const activeTtsChapterIndex = this.activeMirroredTtsChapterIndex();
      const savedChapterIndex = activeTtsChapterIndex >= 0 ? activeTtsChapterIndex : engine.curIdx;
      this.currentChapterIndex = this.clampChapterIndex(savedChapterIndex);
      const savedPosition = this.currentChapterIndex === savedChapterIndex ? Math.max(0, engine.curPos) : 0;
      const savedOffset = activeTtsChapterIndex < 0 ?
        this.savedReaderProgressOffset(this.book, this.currentChapterIndex) : -1;
      if (savedOffset >= 0) {
        this.readerTypographyRestoreOffset = savedOffset;
        this.pendingRestorePageIndex = -1;
      } else {
        this.pendingRestorePageIndex = savedPosition;
      }
      // 打开恢复可能卡在 DB 分页缓存读取或死掉的排版链上：挂一个有界看门狗，
      // 任何路径都不会把用户永久留在“正在恢复阅读进度”遮罩。
      this.armReaderRestoreWatchdog();
      const restoringStoredProgress = activeTtsChapterIndex < 0 && Book.hasStartedReading(this.book);
      this.readerProgressRestoreConfirmed = !restoringStoredProgress;
      if (restoringStoredProgress) {
        // Seed the exit checkpoint before pagination starts. If the user immediately backs out, the transient
        // first incremental spread must never replace the last position that was already durable in the database.
        this.readerProgressAnchorChapterIndex = this.currentChapterIndex;
        this.readerProgressAnchorPageIndex = savedPosition;
        this.readerProgressAnchorOffset = savedOffset;
        const storedPageCount = Number(this.book.getVariable('readProgressPageCount'));
        this.readerProgressAnchorPageCount = Number.isFinite(storedPageCount) && storedPageCount > 0 ?
          Math.round(storedPageCount) : Math.max(1, savedPosition + 1);
        this.readerProgressAnchorPageText = this.book.getVariable('lastReadPageText') || '';
        this.readerProgressAnchorPageImage = this.book.getVariable('lastReadPageImage') || '';
      }
      this.readerLightThemeIndex = ReaderThemeHelper.normalizeIndex(this.readerLightThemeIndex);
      this.readerDarkThemeIndex = ReaderThemeHelper.normalizeIndex(this.readerDarkThemeIndex);

      if (this.chapters.length > 0) {
        await this.loadContent();
        ReaderOpenTrace.mark(this.bookUrl, 'reader-content-ready', `chapter=${this.currentChapterIndex}`);
        await this.syncMirroredTtsFocus();
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

  private async prepareReaderWebFetchRuntime(source: BookSource | null): Promise<void> {
    const needed = this.sourceUsesWebFetchRuntime(source);
    this.readerWebFetchRuntimeNeeded = needed;
    if (!needed) return;
    const attached = await WebBookFetchRuntime.get().waitUntilAttached(3000);
    if (!attached) {
      console.warn('[ReaderOpen] WebView fetch runtime did not attach before book loading');
    }
  }

  private sourceUsesWebFetchRuntime(source: BookSource | null): boolean {
    if (!source) return false;
    let serialized = '';
    try {
      serialized = JSON.stringify(source) || '';
    } catch (_) {
      serialized = source.rawSourceJson || '';
    }
    return /["']?webView["']?\s*:\s*(?:true|["']true["']|1)(?:\s*[,}])?/i.test(serialized);
  }

  async retryFetchChapters() {
    try {
      const engine = this.readerEngine();
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

  initialReaderViewportSize(): ReaderViewportSize {
    const storedWidth = Math.max(0, AppStorage.get<number>('readerLastPageViewWidth') || 0);
    const storedHeight = Math.max(0, AppStorage.get<number>('readerLastPageViewHeight') || 0);
    try {
      const currentDisplay = display.getDefaultDisplaySync();
      const screenWidth = Math.max(1, px2vp(currentDisplay.width));
      const screenHeight = Math.max(1, px2vp(currentDisplay.height));
      const currentLandscape = screenWidth > screenHeight;
      const storedLandscape = storedWidth > storedHeight;
      if (storedWidth > 0 && storedHeight > 0 && currentLandscape === storedLandscape) {
        return { width: storedWidth, height: storedHeight };
      }
      // The exact content area is published by onAreaChange after mount. This display-sized estimate lets the
      // current chapter start pagination before that callback, which otherwise leaves a blank opening panel for
      // several seconds on large devices. A later geometry correction preserves the character offset and reflows.
      const topInset = this.readerExtendToStatusBar ? 0 : Math.max(0, this.statusBarSafeHeight);
      return { width: screenWidth, height: Math.max(1, screenHeight - topInset) };
    } catch (_error) {
      return { width: storedWidth, height: storedHeight };
    }
  }

  resetReaderStateForBookLoad(): void {
    this.contentLoadSerial++;
    this.cancelReaderPaginationWork(true);
    this.readerWebFetchRuntimeNeeded = false;
    this.content = '';
    this.chapters = [];
    this.currentChapterIndex = 0;
    this.contentPages = [];
    this.contentPageStarts = [];
    this.contentPageEnds = [];
    this.pagedContentText = '';
    this.readerParagraphMetricsCache.clear();
    this.readerTextParagraphsCache.clear();
    if (this.readerExtendLayoutRefreshTimerId >= 0) {
      clearTimeout(this.readerExtendLayoutRefreshTimerId);
      this.readerExtendLayoutRefreshTimerId = -1;
    }
    this.readerExtendLayoutReadingOffset = -1;
    this.readerTypographyRestoreOffset = -1;
    this.resetReaderPageCurl();
    this.currentPageIndex = 0;
    this.currentPageText = '';
    this.readerSourceActionAreas.clear();
    this.readerSourceActionScrollOffsets.clear();
    this.readerSelectableTextAreas.clear();
    this.readerSelectableTextScrollOffsets.clear();
    this.readerSelectableTextValues.clear();
    this.readerSelectableTextControllers.clear();
    this.setReaderTextSelectionActive(false);
    this.readerContinuousVisibleStart = 0;
    this.readerContinuousVisibleEnd = 0;
    this.readerContinuousReachedEnd = false;
    this.displayPageText = '';
    this.displayPageChapterIndex = 0;
    this.displayPageIndex = 0;
    this.displayPageRenderKey = 0;
    this.chapterJumpRenderGeneration = 0;
    this.readerCommentPanelMarker = '';
    this.readerCommentPanelAnchorBottom = -1;
    this.readerCommentPageAreaTop = -1;
    this.readerCommentPageAreaHeight = 0;
    const initialViewport = this.initialReaderViewportSize();
    this.pageViewWidth = initialViewport.width;
    this.pageViewHeight = initialViewport.height;
    this.readerInitialPageReady = false;
    this.readerInitialOpening = true;
    this.readerComicMode = false;
    this.syncReaderImageDeferral();
    this.clearReaderComicPaginationProgress();
    this.readerComicChapterSwitching = false;
    this.readerComicBoundaryDirection = 0;
    this.readerComicBoundaryPullDistance = 0;
    this.readerComicBoundaryReady = false;
    this.readerComicChapterTransitionY = 0;
    this.readerComicChapterTransitionOpacity = 1;
    this.readerComicBoundaryPullOriginY = 0;
    this.readerComicScrollRestoreSerial++;
    this.readerComicScrollRestoring = false;
    this.clearReaderComicProgressSaveTimer();
    this.readerComicPageDataSource.reset();
    this.readerContinuousCommitChapter = -1;
    this.readerContinuousLastListStart = 0;
    this.readerContinuousLastListEnd = 0;
    this.neighborLoader().reset();
    this.comicImageActions().reset();
    this.readerComicPagedPrevPages = [];
    this.readerComicPagedNextPages = [];
    this.readerComicPagedPrevChapter = -1;
    this.readerComicPagedNextChapter = -1;
    this.pendingRestorePageIndex = -1;
    this.readerProgressAnchorChapterIndex = -1;
    this.readerProgressAnchorPageIndex = 0;
    this.readerProgressAnchorOffset = -1;
    this.readerProgressAnchorPageCount = 1;
    this.readerProgressAnchorPageText = '';
    this.readerProgressAnchorPageImage = '';
    this.readerProgressRestoreConfirmed = false;
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
    this.pageTurnIncomingPageStart = -1;
    this.pageTurnIncomingSecondaryPageStart = -1;
    this.pageTurnIncomingDocumentSource = '';
    this.pageTurnIncomingRenderVersion = 0;
    this.isPageTurning = false;
    this.pageTurnQueue.reset();
    this.pageTurnCrossChapterHandoff = false;
    this.clearPageTurnPreviewState();
    this.clearTtsHighlight();
    this.pageRenderVersion++;
  }

  async loadContent(silent: boolean = false, targetChapterIndex: number = this.currentChapterIndex,
    preferImmediatePagination: boolean = false): Promise<boolean> {
    if (this.chapters.length === 0) {
      this.setReaderContent(this.buildBookPreview());
      this.isLoading = false;
      return false;
    }

    if (this.detachedReaderEngineReady) await this.detachedReaderEngineReady;
    const engine = this.readerEngine();
    if (engine.book?.bookUrl !== (this.book?.bookUrl || this.bookUrl)) return false;
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
        return false;
      }
      let loadedContent = await this.prepareReaderContentRules(body, chapterIndex);
      ReaderOpenTrace.mark(this.bookUrl, 'content-preprocessed', `length=${loadedContent.length}`);
      if (loadSerial !== this.contentLoadSerial) {
        return false;
      }
      // 正文被预处理掏空（空白字符串）时不能继续分页：空白正文会产出 0 页并留下一张永白的阅读页。
      const usableContent = !!body && !!loadedContent && loadedContent.trim().length > 0;
      if (body && !usableContent) {
        console.error(`[Reader] 章节正文为空 chapter=${chapterIndex} rawLength=${body.length} ` +
          `preparedLength=${loadedContent.length}`);
      }
      // Commit the chapter identity only after the asynchronous fetch and preprocessing both
      // succeeded. A rejected/stale load must not leave the reader pointing at a new chapter
      // while it still owns the previous chapter's content.
      const chapterChanged = this.currentChapterIndex !== chapterIndex;
      this.currentChapterIndex = chapterIndex;
      if (chapterChanged) this.readerContinuousReachedEnd = false;
      this.closeReaderCommentPanel();
      if (usableContent) {
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
      this.detectReaderComicMode(loadedContent);
      // 直接从预处理后的正文开始分页：同步首屏 + 恢复突发排版（见 scheduleReaderPaginationCompletion）
      // 能在毫秒级完成落页。旧的持久分页缓存读取要 await 关系型数据库查询（部分 HarmonyOS 构建上
      // 带有数秒级同步前缀且无法超时），放在首屏前反而让每次跳章都“迟迟等待排版”，已不再使用。
      const restoredPagination = body ?
        this.applyPreparedReaderPagination(loadedContent, chapterIndex, preferImmediatePagination) : false;
      if (loadSerial !== this.contentLoadSerial) {
        return false;
      }
      if (!restoredPagination) {
        this.paginateContent(loadedContent, chapterIndex);
      }
      ReaderOpenTrace.mark(this.bookUrl, 'pagination-published',
        `pages=${this.contentPages.length} restored=${restoredPagination}`);
      // Let the restored/current page win the first frame before network and native-Paragraph work for
      // neighbouring chapters starts competing for the UI thread.
      this.preloadReaderContentLater(720);
      const publishedSource = this.pagedContentText || this.getPagedSourceText();
      return !!body && this.currentChapterIndex === chapterIndex && publishedSource.length > 0;
    } catch (e) {
      console.error('加载内容失败:', e);
      return false;
    } finally {
      if (loadSerial === this.contentLoadSerial && !silent) {
        this.isLoading = false;
        this.loadStatus = '';
      }
      this.updatePendingVerification();
    }
  }

  /** restorePageIndex：刷新后停留的页（默认回到本章开头）；quiet：不弹“本章已刷新”。 */
  async refreshCurrentChapter(restorePageIndex: number = 0, quiet: boolean = false): Promise<void> {
    if (this.chapters.length === 0) {
      return;
    }

    const engine = this.readerEngine();
    const chapterIndex = this.currentChapterIndex;
    // Treat an explicit reload as a new content generation. Previously reloadContent() replaced `content` while
    // the old incremental pagination session, retained V2 document and TTS source mapping remained alive. When the
    // source happened to keep the same cache identity,正文 could reset to page one but TTS rectangles were still
    // resolved through the detached document and stayed invisible even after a page turn.
    const refreshSerial = ++this.contentLoadSerial;
    this.isLoading = true;
    this.loadStatus = '正在刷新本章...';
    // Mark the refresh busy before stopping TTS so its delayed sentence checkpoint cannot race the explicit
    // page-one progress written after the replacement pagination has been published.
    this.stopTtsReading();
    this.readerPreparedContentCache.clear();
    try {
      const body = await engine.reloadContent(chapterIndex);
      if (refreshSerial !== this.contentLoadSerial || chapterIndex !== this.currentChapterIndex) return;
      if (body) {
        const processedBody = await this.prepareReaderContentRules(body, chapterIndex);
        if (refreshSerial !== this.contentLoadSerial || chapterIndex !== this.currentChapterIndex) return;
        // Cancel every producer and retained consumer derived from the previous正文 before publishing the new one.
        // The surface generation is necessary because NodeContainer may retain the old controller even after the
        // controller map has been cleared; a remount keeps正文、分页边界 and TTS source offsets on one generation.
        this.finishPageTurnAnimation(false);
        this.clearQueuedReaderPageTurns();
        this.cancelReaderPaginationWork(true);
        this.readerV2SurfaceGeneration++;
        this.readerV2ActiveSpeechText = null;
        this.readerTypographyRestoreOffset = -1;
        this.readerInitialPageReady = false;
        this.contentPages = [];
        this.contentPageStarts = [];
        this.contentPageEnds = [];
        this.pagedContentText = '';
        this.content = processedBody;
        this.detectReaderComicMode(processedBody);
        this.chapters = [...engine.chapters];
        this.pendingRestorePageIndex = Math.max(0, restorePageIndex);
        this.currentPageIndex = 0;
        this.paginateContent(processedBody, chapterIndex);
        this.forceCurrentReaderPageRender();
        this.refreshCurrentReaderV2RetainedPages(true);
        this.preloadReaderContentLater(720);
        await this.saveReadingProgress();
        if (refreshSerial !== this.contentLoadSerial || chapterIndex !== this.currentChapterIndex) return;
        if (!quiet) HdsFeedback.showToast('本章已刷新');
      } else {
        if (refreshSerial !== this.contentLoadSerial || chapterIndex !== this.currentChapterIndex) return;
        this.updatePendingVerification();
        const chapter = this.chapters[chapterIndex];
        const loadedContent = this.verificationUrl ? `${chapter ? chapter.title : '当前章节'}\n\n该书源需要先完成网页验证。请点击右上角“更多操作”，选择“登录”，完成后返回，再从该菜单选择“重试”。` :
          (chapter ? `${chapter.title}\n\n章节正文刷新失败。请再次点击右上角“刷新本章”或“换源”。` :
            '章节正文刷新失败。请点击右上角“更多操作”，选择“重试”。');
        this.content = loadedContent;
        this.paginateContent(loadedContent);
        HdsFeedback.showToast('刷新本章失败');
      }
    } catch (e) {
      console.error('刷新本章失败:', e);
      HdsFeedback.showToast('刷新本章失败');
    } finally {
      if (refreshSerial === this.contentLoadSerial) {
        this.isLoading = false;
        this.loadStatus = '';
        this.updatePendingVerification();
      }
    }
  }

  onFullTextCacheCancelNonceChanged(): void {
    this.fullTextCacheController().onCancelNonceChanged(this.fullTextCacheCancelNonce || 0);
  }

  // Background task behind "缓存全文". The page only mirrors its progress into @State for the dialog.
  fullTextCacheController(): ReaderFullTextCacheController {
    if (!this.fullTextCache) {
      this.fullTextCache = new ReaderFullTextCacheController({
        abilityContext: (): common.UIAbilityContext => getContext(this) as common.UIAbilityContext,
        bookUrl: (): string => this.book?.bookUrl || this.bookUrl,
        bookName: (): string => this.book?.name || '',
        ttsBackgroundRunning: (): boolean => this.ttsMediaSession().backgroundRunning,
        ttsBackgroundBusy: (): boolean =>
          this.ttsMediaSession().backgroundRunning || this.ttsMediaSession().backgroundRequesting,
        onStateChanged: (): void => {
          const controller = this.fullTextCacheController();
          this.fullTextCaching = controller.caching;
          this.fullTextCacheDone = controller.done;
          this.fullTextCacheTotal = controller.total;
          this.fullTextCacheStatus = controller.status;
        },
        onChaptersChanged: (chapters: BookChapter[]): void => {
          this.chapters = chapters;
        }
      });
    }
    return this.fullTextCache;
  }

  openReaderCacheDialog(): void {
    if (!this.book || LocalBookService.isLocalBook(this.book)) {
      HdsFeedback.showToast('当前书籍暂无可缓存章节');
      return;
    }
    this.showReaderActionMenu = false;
    this.showMenu = false;
    this.showReaderChapterCacheDialog = false;
    this.showReaderCacheDialog = true;
    this.readerCacheDialogSession.open(this.getUIContext(), (): void => {
      this.readerCacheDialogContent(false);
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示全文缓存弹窗失败:'
    });
  }

  openReaderChapterCacheDialog(): void {
    if (!this.book || LocalBookService.isLocalBook(this.book) || this.fullTextCaching) {
      return;
    }
    this.showReaderCacheDialog = false;
    this.showReaderChapterCacheDialog = true;
    this.chapterCacheDialogSession.open(this.getUIContext(), (): void => {
      this.readerCacheDialogContent(true);
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示章节缓存弹窗失败:',
      onDismiss: (): void => {
        this.showReaderChapterCacheDialog = false;
      }
    });
  }

  // Caching runs in the background, so the dialog can always be closed.
  closeReaderCacheDialog(): void {
    this.showReaderCacheDialog = false;
    this.showReaderChapterCacheDialog = false;
  }

  startFullTextCache(): void {
    if (this.fullTextCaching) {
      HdsFeedback.showToast(this.fullTextCacheStatus || '全文缓存正在后台进行');
      return;
    }
    if (!this.book || this.chapters.length === 0 || !this.book.origin || this.book.origin === 'local') {
      HdsFeedback.showToast('当前书籍暂无可缓存章节');
      return;
    }

    this.hideReaderPanels();
    HdsFeedback.showToast('已转入后台缓存，可在通知栏取消');
    this.fullTextCacheController().start();
  }

  clearReaderScreenTimeoutTimer(): void {
    if (this.readerScreenTimeoutTimerId >= 0) {
      clearTimeout(this.readerScreenTimeoutTimerId);
      this.readerScreenTimeoutTimerId = -1;
    }
  }

  applyReaderScreenTimeout(): void {
    this.clearReaderScreenTimeoutTimer();
    const serial = ++this.readerScreenTimeoutSerial;
    if (!this.readerPageVisible) {
      this.setReaderWindowKeepScreenOn(false, serial);
      return;
    }
    const minutes = ReaderSettingsStore.normalizeScreenTimeoutMinutes(this.readerScreenTimeoutMinutes);
    if (minutes === ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM) {
      this.setReaderWindowKeepScreenOn(false, serial);
      return;
    }
    this.setReaderWindowKeepScreenOn(true, serial);
    if (minutes > 0) {
      this.readerScreenTimeoutTimerId = setTimeout(() => {
        if (serial !== this.readerScreenTimeoutSerial) {
          return;
        }
        this.readerScreenTimeoutTimerId = -1;
        this.setReaderWindowKeepScreenOn(false, serial);
      }, minutes * 60 * 1000);
    }
  }

  refreshReaderScreenTimeout(): void {
    if (this.readerPageVisible && this.readerScreenTimeoutMinutes > 0) {
      this.applyReaderScreenTimeout();
    }
  }

  releaseReaderScreenTimeout(): void {
    this.clearReaderScreenTimeoutTimer();
    const serial = ++this.readerScreenTimeoutSerial;
    this.setReaderWindowKeepScreenOn(false, serial);
  }

  setReaderWindowKeepScreenOn(enabled: boolean, serial: number): void {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      if (serial !== this.readerScreenTimeoutSerial) {
        return;
      }
      mainWindow.setWindowKeepScreenOn(enabled).catch((error: Error) => {
        console.warn('设置阅读页亮屏状态失败:', error);
      });
    }).catch((error: Error) => {
      console.warn('获取阅读页窗口失败:', error);
    });
  }

  finishReaderInitialOpening(): void {
    this.readerInitialOpening = false;
    AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
  }

  shouldRenderPrimaryReaderContent(): boolean {
    return !this.isLoading || !!this.content;
  }

  isPagedReaderAwaitingPagination(): boolean {
    return !!this.content && this.contentPages.length === 0;
  }

  shouldShowReaderLoadingOverlay(): boolean {
    // 翻页进行中由翻页提示页（上一章排版中/加载中）负责覆盖屏幕；恢复进度遮罩若在动画期间浮现，
    // 会盖住提示页并造成“提交后又闪加载框”的割裂感。
    if (this.isPageTurning) return false;
    return this.shouldRenderPrimaryReaderContent() &&
      !this.readerComicChapterSwitching &&
      (this.isLoading || this.isPagedReaderAwaitingPagination() || !this.readerInitialPageReady);
  }

  shouldBlockReaderInteraction(): boolean {
    return this.isLoading || this.isPagedReaderAwaitingPagination() || !this.readerInitialPageReady ||
      this.readerComicPaginationParsing;
  }

  getReaderLoadingText(): string {
    if (this.readerInitialOpening) {
      return '正在打开书籍…';
    }
    if (this.pendingRestorePageIndex >= 0) {
      return '正在恢复阅读进度...';
    }
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
        .color(this.accentColor())
      Text(this.getReaderLoadingText())
        .fontSize(AppFontSize.BODY)
        .fontColor(this.isReaderLoadingSurfaceDark() ? '#AEB4BE' : '#777777')
        .margin({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.readerLoadingSurfaceColor())
  }

  @Builder
  readerComicPaginationPanel() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(44)
        .height(44)
        .color(this.accentColor())
      Text('正在解析漫画')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isReaderLoadingSurfaceDark() ? '#E6E6E6' : '#333333')
      Text(`已解析 ${this.readerComicPaginationParsedPages} / ${this.readerComicPaginationTotalPages} 页`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.isReaderLoadingSurfaceDark() ? '#AEB4BE' : '#777777')
      Progress({
        value: this.readerComicPaginationParsedPages,
        total: Math.max(1, this.readerComicPaginationTotalPages),
        type: ProgressType.Linear
      })
        .width(196)
        .height(4)
        .color(this.accentColor())
        .backgroundColor(this.isReaderLoadingSurfaceDark() ? '#3A3D43' : '#DDD8D0')
      Text('解析完成后自动开始阅读')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.isReaderLoadingSurfaceDark() ? '#858B94' : '#999999')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.readerLoadingSurfaceColor())
  }

  @Builder
  readerComicScrollSurface() {
    Stack() {
      List({ space: 0, scroller: this.readerComicScroller }) {
        LazyForEach(this.readerComicPageDataSource, (item: ReaderScrollItem, index: number) => {
          ListItem() {
            if (!item.isPage()) {
              this.readerContinuousChapterSeparator(item)
            } else if (this.isReaderImageOnlyPage(item.text)) {
              ReaderComicImageItem({
                marker: item.text.trim(),
                viewWidth: this.pageViewWidth,
                viewHeight: this.pageViewHeight,
                seamOverlap: item.pageIndex > 0 &&
                  this.isReaderImageOnlyPage(this.readerComicPageDataSource.getData(index - 1).text),
                hintColor: this.getSubTextColor()
              })
            } else if (this.usesReaderContinuousV2()) {
              this.readerContinuousV2Item(item.chapterIndex, item.pageIndex, item.text, this.pageRenderVersion)
            } else {
              Column() {
                this.readerPlainTextLeaf(item.text)
              }
              .width('100%')
              .constraintSize({ minHeight: this.pageViewHeight })
            }
          }
          .width('100%')
        }, (item: ReaderScrollItem) => item.key)
      }
      .id(READER_CONTINUOUS_LIST_ID)
      // 上一章装到列表前面、远处的章节从前面移除时，正在读的内容保持不动。
      .maintainVisibleContentPosition(true)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      // In continuous reading the configured vertical margins describe the viewport, not only the first and
      // last pagination fragment. Keep every scrolled line inside those edges and avoid adding a second reserve.
      // 上下内边距都包含页眉/页脚的占位：List 只在内容区内绘制，正文滚到页眉页脚处即被裁掉，不会从文字下方透出。
      .padding({
        top: this.isReaderNovelContinuousScrollModeActive() ? this.getEffectiveReaderMarginTop() : 0,
        bottom: this.isReaderNovelContinuousScrollModeActive() ? this.getReaderContinuousScrollBottomPadding() : 0
      })
      .enableScrollInteraction(!this.readerTextSelectionActive)
      .scrollBar(BarState.Off)
      // 每个滚动块都是整屏正文（可见 Text + 透明选择 Text 两次排版）。默认只在进入视口时才构建，
      // 快速滑动时会临时排版掉帧；预构建视口外 2 块把排版开销挪到滑动间隙的空闲帧。
      // 漫画模式条目是带显式高度的图片，保持原有时序以隔离行为差异。
      .cachedCount(this.isReaderNovelContinuousScrollModeActive() ? 2 : 0)
      .translate({ y: this.readerComicChapterTransitionY })
      .opacity(this.readerComicChapterTransitionOpacity)
      .onScrollIndex((start: number, end: number) => {
        this.onReaderComicScrollIndexChanged(start, end);
      })
      .onReachEnd(() => {
        this.onReaderContinuousReachEnd();
      })
      .onAppear(() => {
        // A persisted deep/last-page restore can be published before the newly created List has completed its
        // first layout. scrollToIndex() is then accepted but has no visual effect, and the first index callback
        // used to overwrite the durable page with zero. Retry from the mounted surface while the restore guard
        // still owns the authoritative target.
        if (this.readerComicScrollRestoring) this.scheduleReaderComicScrollRestore();
      })

      Column() {
        if (this.isReaderHeaderVisible()) {
          this.readerHeaderInfoBar()
        }
        Blank()
          .layoutWeight(1)
        if (this.readerFooterEnabled && !this.isReaderComicModeActive()) {
          this.readerBottomInfoBar()
        }
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)

      if (this.readerComicBoundaryDirection !== 0 || this.readerComicChapterSwitching) {
        this.readerComicBoundaryHint()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .opacity(this.readerInitialPageReady ? 1 : 0)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updatePagedReaderArea(newValue);
      this.rememberReaderTapLayerArea(newValue);
    })
    .onTouch((event: TouchEvent) => this.rememberContinuousReaderPointer(event))
    .parallelGesture(
      PanGesture({ direction: PanDirection.Vertical, distance: Math.max(18, this.readerTapSlop * 1.5) })
          .onActionStart(() => {
            if (!this.isReaderNovelContinuousScrollModeActive() || this.readerTextSelectionActive) return;
            this.beginReaderComicPan();
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.isReaderNovelContinuousScrollModeActive() || this.readerTextSelectionActive) return;
            this.updateReaderComicPan(event);
          })
          .onActionEnd((event: GestureEvent) => {
            if (!this.isReaderNovelContinuousScrollModeActive()) return;
            if (this.readerTextSelectionActive) {
              this.cancelReaderComicPan();
              return;
            }
            this.finishReaderComicPan(event);
          })
          .onActionCancel(() => {
            this.cancelReaderComicPan();
          }),
      // Track chapter-boundary pans alongside the List and selectable Text instead of taking priority over them.
      // A priority pan makes ArkUI cancel the child's native long press before it can create selection handles.
      GestureMask.Normal
    )
  }

  @Builder
  readerComicBoundaryHint() {
    Column() {
      if (this.readerComicBoundaryDirection < 0) {
        this.readerComicBoundaryHintContent()
      }
      // HitTestMode.None 只让容器自身不参与触摸测试，子节点照常参与；铺满的占位必须单独排除，
      // 否则提示出现期间会截走下面列表的点击和拖动。
      Blank()
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)
      if (this.readerComicBoundaryDirection > 0) {
        this.readerComicBoundaryHintContent()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.readerComicBoundaryHintTopPadding(), bottom: 54 })
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  readerComicBoundaryHintTopPadding(): number {
    // The continuous surface is already inset when body content does not extend into the status bar;
    // extended and comic layouts are not.
    // Add only the unconsumed safe-area height so the top hint never sits underneath status-bar content.
    const consumedTopInset = this.getReaderTopSafePadding();
    return Math.max(14, this.statusBarSafeHeight - consumedTopInset + 12);
  }

  @Builder
  readerComicBoundaryHintContent() {
    Row({ space: AppSpacing.MD }) {
      if (this.readerComicChapterSwitching) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.accentColor())
      } else {
        SymbolGlyph(this.readerComicBoundaryDirection < 0 ?
          $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_up'))
          .fontSize(17)
          .fontColor([this.readerComicBoundaryReady ? this.accentColor() : this.getTextColor()])
      }
      Text(this.readerComicBoundaryHintText())
        .fontSize(AppFontSize.BODY)
        .fontWeight(this.readerComicBoundaryReady || this.readerComicChapterSwitching ? FontWeight.Medium :
          FontWeight.Regular)
        .fontColor(this.readerComicBoundaryReady || this.readerComicChapterSwitching ?
          this.accentColor() : this.getTextColor())
    }
    .padding({ left: 14, right: 14, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .borderRadius(18)
    .backgroundColor(this.isReaderThemeDark() ? '#E61B1D20' : '#E6FFFFFF')
    .shadow({ radius: 10, color: this.isReaderThemeDark() ? '#66000000' : '#26000000', offsetY: 3 })
    .opacity(this.readerComicChapterSwitching ? 1 :
      Math.min(1, 0.35 + this.readerComicBoundaryPullDistance / 56))
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerComicSurface() {
    Stack() {
      ReaderComicView({
        scroller: this.readerComicScroller,
        dataSource: this.readerComicPageDataSource,
        chapterTitle: (chapterIndex: number): string => this.getChapterTitle(chapterIndex),
        preloadCount: this.readerComicSettings.preloadCount,
        onImageLongPress: (source: string, reload: () => void, snapshotId: string): void => {
          this.handleReaderComicImageLongPress(source, reload, snapshotId);
        },
        onImageDenied: (chapterIndex: number): void => this.handleReaderComicImageDenied(chapterIndex),
        viewWidth: this.pageViewWidth,
        viewHeight: this.pageViewHeight,
        surfaceColor: this.readerComicSurfaceColor(),
        textColor: this.readerComicSurfaceTextColor(),
        hintColor: this.readerComicSurfaceHintColor(),
        pageGap: this.readerComicSettings.pageGap,
        fitScreen: this.readerComicSettings.fit === ReaderComicFit.SCREEN,
        doubleTapZoom: this.readerComicSettings.doubleTapZoom,
        superResolution: this.isReaderComicSuperResolutionActive(),
        textConvert: this.isReaderComicTextConvertActive(),
        interactive: this.isReaderComicInteractionEnabled(),
        panDistance: this.readerTapSlop,
        transitionY: this.readerComicChapterTransitionY,
        transitionOpacity: this.readerComicChapterTransitionOpacity,
        infoVisible: this.shouldShowReaderComicInfoBadge(),
        infoChapter: this.getChapterTitle(),
        infoPage: this.readerComicPageText(),
        infoTime: this.readerInfoTimeText,
        infoBattery: this.readerInfoBatteryPercent,
        infoBottomInset: this.readerComicInfoBadgeBottomInset(),
        onVisibleRangeChange: (start: number, end: number): void => this.onReaderComicScrollIndexChanged(start, end),
        onReachEnd: (): void => this.onReaderContinuousReachEnd(),
        onListAppear: (): void => {
          // 深度/末页恢复可能在列表首次布局前发布，那时 scrollToIndex 不生效；挂载后按恢复目标再补一次。
          if (this.readerComicScrollRestoring) this.scheduleReaderComicScrollRestore();
        },
        onTap: (x: number, y: number, width: number, height: number): void =>
          this.handleReaderComicTap(x, y, width, height),
        onPanStart: (): void => {
          if (this.isReaderInteractiveActionActive()) return;
          this.beginReaderComicPan();
        },
        onPanUpdate: (event: GestureEvent): void => {
          if (this.isReaderInteractiveActionActive()) return;
          this.updateReaderComicPan(event);
        },
        onPanEnd: (event: GestureEvent): void => {
          if (this.isReaderInteractiveActionActive()) {
            this.cancelReaderComicPan();
            return;
          }
          this.finishReaderComicPan(event);
        },
        onPanCancel: (): void => this.cancelReaderComicPan(),
        onZoomChanged: (scale: number): void => {
          this.readerComicZoomScale = scale;
        }
      })

      if (this.readerComicBoundaryDirection !== 0 || this.readerComicChapterSwitching) {
        this.readerComicBoundaryHint()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .opacity(this.readerInitialPageReady ? 1 : 0)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updatePagedReaderArea(newValue);
      this.rememberReaderTapLayerArea(newValue);
    })
  }

  @Builder
  readerComicPagedSurface() {
    Stack() {
      ReaderComicPagedView({
        controller: this.readerComicPagedController,
        pages: this.contentPages,
        pageIndex: this.currentPageIndex,
        chapterIndex: this.currentChapterIndex,
        viewWidth: this.pageViewWidth,
        viewHeight: this.pageViewHeight,
        dualPage: this.isReaderComicDualPageActive(),
        rightToLeft: this.isReaderComicRightToLeft(),
        doubleTapZoom: this.readerComicSettings.doubleTapZoom,
        superResolution: this.isReaderComicSuperResolutionActive(),
        textConvert: this.isReaderComicTextConvertActive(),
        surfaceColor: this.readerComicSurfaceColor(),
        textColor: this.readerComicSurfaceTextColor(),
        hintColor: this.readerComicSurfaceHintColor(),
        interactive: this.isReaderComicInteractionEnabled(),
        panDistance: this.readerTapSlop,
        transitionOpacity: this.readerComicChapterTransitionOpacity,
        prevChapterTitle: this.currentChapterIndex > 0 ? this.getChapterTitle(this.currentChapterIndex - 1) : '',
        nextChapterTitle: this.currentChapterIndex < this.chapters.length - 1 ?
          this.getChapterTitle(this.currentChapterIndex + 1) : '',
        prevChapterPages: this.readerComicPagedPrevChapter === this.currentChapterIndex - 1 ?
          this.readerComicPagedPrevPages : [],
        nextChapterPages: this.readerComicPagedNextChapter === this.currentChapterIndex + 1 ?
          this.readerComicPagedNextPages : [],
        onCrossChapter: (direction: number): void => {
          this.commitReaderComicPagedChapter(direction).catch((error: Error) => {
            console.warn('翻页模式跨章失败:', error);
            this.readerComicPagedController.cancelCross();
          });
        },
        infoVisible: this.shouldShowReaderComicInfoBadge(),
        infoChapter: this.getChapterTitle(),
        infoPage: this.readerComicPageText(),
        infoTime: this.readerInfoTimeText,
        infoBattery: this.readerInfoBatteryPercent,
        infoBottomInset: this.readerComicInfoBadgeBottomInset(),
        preloadCount: this.readerComicSettings.preloadCount,
        onImageLongPress: (source: string, reload: () => void, snapshotId: string): void => {
          this.handleReaderComicImageLongPress(source, reload, snapshotId);
        },
        onImageDenied: (chapterIndex: number): void => this.handleReaderComicImageDenied(chapterIndex),
        onPageChanged: (pageIndex: number): void => this.onReaderComicPagedPageChanged(pageIndex),
        onBoundary: (direction: number): void => this.crossReaderComicChapterBoundary(direction),
        onTap: (x: number, y: number, width: number, height: number): void =>
          this.handleReaderComicTap(x, y, width, height)
      })

      if (this.readerComicChapterSwitching) {
        this.readerComicBoundaryHint()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .opacity(this.readerInitialPageReady ? 1 : 0)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updatePagedReaderArea(newValue);
      this.rememberReaderTapLayerArea(newValue);
    })
  }

  readerComicEffectiveMode(): string {
    return this.readerComicBookMode || this.readerComicSettings.defaultMode;
  }

  isReaderComicPagedMode(): boolean {
    return this.isReaderComicModeActive() && ReaderComicMode.isPaged(this.readerComicEffectiveMode());
  }

  isReaderComicRightToLeft(): boolean {
    return this.readerComicEffectiveMode() === ReaderComicMode.RTL;
  }

  isReaderComicDualPageActive(): boolean {
    return this.isReaderComicPagedMode() && this.readerComicSettings.dualPage &&
      this.pageViewWidth > this.pageViewHeight;
  }

  onReaderComicPagedPageChanged(pageIndex: number): void {
    if (!this.readerPageVisible || this.contentPages.length === 0) return;
    const target = Math.max(0, Math.min(pageIndex, this.contentPages.length - 1));
    const lastShown = target + (this.isReaderComicDualPageActive() ? 1 : 0);
    this.readerContinuousReachedEnd = lastShown >= this.contentPages.length - 1;
    if (target === this.currentPageIndex) return;
    this.currentPageIndex = target;
    this.currentPageText = this.contentPages[target] || '';
    if (this.contentPages.length - target <= 4) {
      this.preloadReaderContentLater();
      this.preloadNextChapterPaginationLater(0);
    }
    if (target <= 3) this.preloadPreviousChapterPaginationLater(0);
    this.scheduleReaderComicProgressSave();
    this.ensureReaderComicPagedNeighbors();
  }

  /** 本书改用另一种漫画阅读方式；当前页码不变。 */
  setReaderComicBookMode(mode: string): void {
    if (!this.book) return;
    const next = ReaderComicMode.normalize(mode);
    if (next === this.readerComicEffectiveMode() && this.readerComicBookMode) return;
    this.readerComicBookMode = next;
    this.readerComicZoomScale = 1;
    this.book.putVariable('readerComicReadingMode', next);
    AppDatabase.getInstance().updateBook(this.book, false).catch((error: Error) => {
      console.warn('保存漫画阅读方式失败:', error);
    });
    // 条漫列表重新挂载后按当前页恢复滚动位置；翻页视图直接以 currentPageIndex 定位。
    this.scheduleReaderComicScrollRestore();
  }

  handleReaderComicImageLongPress(source: string, reload: () => void, snapshotId: string): void {
    this.comicImageActions().showMenu(source, reload, snapshotId).catch((error: Error) => {
      console.warn('漫画图片菜单失败:', error);
    });
  }

  handleReaderComicImageDenied(chapterIndex: number): void {
    this.comicImageActions().onImageDenied(chapterIndex);
  }

  isReaderComicInteractionEnabled(): boolean {
    return !this.showMenu && !this.showToc && !this.showSettings && !this.shouldBlockReaderInteraction() &&
      !this.readerComicChapterSwitching;
  }

  shouldShowReaderComicInfoBadge(): boolean {
    return this.readerComicSettings.infoBar && this.readerInitialPageReady && this.contentPages.length > 0 &&
      !this.showMenu && !this.showToc && !this.showSettings;
  }

  readerComicInfoBadgeBottomInset(): number {
    // 只让开手势横线（贴在导航区最底部、约 5vp 高），不必让出整个导航区。
    return Math.max(4, Math.max(0, this.navBarHeight) - 18);
  }

  /** 增量排版期间 contentPages 还没有全部页，总页数取图片标记计数。 */
  readerComicTotalPageCount(): number {
    return Math.max(this.contentPages.length, this.readerComicPaginationTotalPages);
  }

  readerComicPageText(): string {
    const total = this.readerComicTotalPageCount();
    if (total <= 0) return '';
    const first = Math.min(total, Math.max(0, this.currentPageIndex) + 1);
    if (this.isReaderComicDualPageActive() && first < total) return `${first}-${first + 1}/${total}`;
    return `${first}/${total}`;
  }

  handleReaderComicTap(x: number, y: number, width: number, height: number): void {
    if (this.consumeSuppressedReaderTapClick()) return;
    if (Date.now() < this.readerComicSuppressClickUntil || this.showMenu || this.showToc || this.showSettings) {
      return;
    }
    if (!this.readerComicSettings.tapTurn) {
      this.updateReaderMenuAnchorByPoint(x);
      this.showMenu = true;
      return;
    }
    // 日漫翻页时“下一页”在左边，点击区域左右镜像。
    const mirroredX = this.isReaderComicPagedMode() && this.isReaderComicRightToLeft() ? width - x : x;
    const zone = this.getTapZoneIndex(mirroredX, y, width, height);
    const actions = this.readerTapZoneActionsList();
    // 点击区域里一个“菜单”都没有时保留中间区域呼出菜单，否则漫画页再也打不开菜单。
    const action = zone === 4 && !actions.includes(1) ? 1 : actions[zone];
    if (action === 1) {
      this.updateReaderMenuAnchorByPoint(x);
      this.showMenu = true;
    } else if (action === 2) {
      this.scrollReaderComicByScreen(1);
    } else if (action === 3) {
      this.scrollReaderComicByScreen(-1);
    }
  }

  /** 条漫按屏翻动：滚动约 0.8 屏保留上下文；已到章首/章末时切到相邻章节。 */
  scrollReaderComicByScreen(direction: number): void {
    if (!this.isReaderComicModeActive() || this.contentPages.length === 0 || this.readerComicChapterSwitching) {
      return;
    }
    if (this.isReaderComicPagedMode()) {
      this.readerComicPagedController.turn(direction);
      return;
    }
    let offset = 0;
    let atEnd = false;
    try {
      offset = Number(this.readerComicScroller.currentOffset().yOffset) || 0;
      atEnd = this.readerComicScroller.isAtEnd();
    } catch (error) {
      console.warn('读取漫画滚动位置失败:', error);
      return;
    }
    if ((direction > 0 && atEnd) || (direction < 0 && offset <= 1)) {
      this.stopReaderComicScreenScroll();
      this.crossReaderComicChapterBoundary(direction);
      return;
    }
    // 放大后屏幕只显示列表的 1/倍数，翻一屏对应的列表距离同比缩短。
    const step = Math.max(120, this.pageViewHeight * 0.8) / Math.max(1, this.readerComicZoomScale) *
      (direction > 0 ? 1 : -1);
    this.startReaderComicScreenScroll(step);
  }

  /**
   * 点击翻屏的滚动动画。不用 scrollTo(绝对位置)：列表的绝对位置是按已量过的项估算的，滚进相邻章节时
   * 上方会去掉一章（或接上一章、图片加载后变高），估算值随之跳变，动画仍奔向旧目标，就会一下冲到下一章末尾。
   * 这里每帧按相对距离 scrollBy，列表怎么增删都只滚这一屏。连点时把没滚完的距离并进下一次。
   */
  startReaderComicScreenScroll(distance: number): void {
    const total = this.readerComicScreenScrollRemaining + distance;
    this.stopReaderComicScreenScroll();
    const durationMs = 260;
    const startedAt = Date.now();
    let applied = 0;
    this.readerComicScreenScrollRemaining = total;
    const tick = (): void => {
      this.readerComicScreenScrollTimerId = -1;
      if (!this.readerPageVisible || !this.isReaderComicModeActive() || this.isReaderComicPagedMode()) {
        this.readerComicScreenScrollRemaining = 0;
        return;
      }
      const t = Math.min(1, (Date.now() - startedAt) / durationMs);
      const eased = 1 - Math.pow(1 - t, 3);
      const target = total * eased;
      const delta = target - applied;
      applied = target;
      this.readerComicScreenScrollRemaining = total - applied;
      if (Math.abs(delta) >= 0.01) {
        try {
          this.readerComicScroller.scrollBy(0, delta);
        } catch (error) {
          console.warn('漫画点击翻屏滚动失败:', error);
          this.readerComicScreenScrollRemaining = 0;
          return;
        }
      }
      if (t < 1) this.readerComicScreenScrollTimerId = setTimeout(tick, 16);
    };
    tick();
  }

  stopReaderComicScreenScroll(): void {
    if (this.readerComicScreenScrollTimerId >= 0) {
      clearTimeout(this.readerComicScreenScrollTimerId);
      this.readerComicScreenScrollTimerId = -1;
    }
    this.readerComicScreenScrollRemaining = 0;
  }

  /** 已在本章首尾再往外翻：切到相邻一话。 */
  crossReaderComicChapterBoundary(direction: number): void {
    if (this.readerComicChapterSwitching) return;
    if (direction > 0) {
      // contentPages 是增量快照；排版尚未完成时尾部不是章末，先补齐后续页再继续翻。
      if (!this.isCurrentReaderPaginationComplete()) {
        this.ensureCurrentReaderPaginationAhead(this.contentPages.length + 1);
        return;
      }
      if (this.currentChapterIndex >= this.chapters.length - 1) {
        HdsFeedback.showToast('已经是最后一话');
        return;
      }
    } else if (this.currentChapterIndex <= 0) {
      HdsFeedback.showToast('已经是第一话');
      return;
    }
    this.switchComicBoundaryChapter(direction);
  }

  comicMenuPageIndex(): number {
    return this.comicPageSliderActive ? this.comicPageSliderPreview : this.currentPageIndex;
  }

  canStepReaderComicChapter(direction: number): boolean {
    if (this.isLoading || this.readerComicChapterSwitching) return false;
    return direction < 0 ? this.currentChapterIndex > 0 : this.currentChapterIndex < this.chapters.length - 1;
  }

  handleComicPageSliderChange(value: number, mode: SliderChangeMode): void {
    const lastIndex = Math.max(0, this.readerComicTotalPageCount() - 1);
    this.comicPageSliderPreview = Math.max(0, Math.min(Math.round(value), lastIndex));
    this.comicPageSliderActive = true;
    this.comicPageTooltipVisible = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.comicPageTooltipVisible = false;
      this.comicPageSliderActive = false;
      this.jumpToReaderComicPage(this.comicPageSliderPreview);
    }
  }

  jumpToReaderComicPage(index: number): void {
    if (this.contentPages.length === 0) return;
    if (index >= this.contentPages.length) this.ensureCurrentReaderPaginationAhead(index + 1);
    const target = Math.max(0, Math.min(index, this.contentPages.length - 1));
    if (!this.isReaderComicPagedMode()) {
      try {
        this.readerComicScroller.scrollToIndex(this.readerContinuousListIndex(target), false, ScrollAlign.START);
      } catch (error) {
        console.warn('跳转漫画页失败:', error);
        return;
      }
    }
    this.currentPageIndex = target;
    this.currentPageText = this.contentPages[target] || '';
    this.readerContinuousReachedEnd = target === this.contentPages.length - 1;
    this.scheduleReaderComicProgressSave();
  }

  @Builder
  readerComicTitleCapsule() {
    Stack({ alignContent: Alignment.Start }) {
      if (ImmersiveMaterialRuntime.supportsHdsTabs() && this.readerComicTitleCapsuleWidth > 0) {
        this.readerComicTitleCapsuleMaterial()
      }
      Column({ space: 1 }) {
        Text(this.getChapterTitle())
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.book?.name) {
          Text(this.book.name)
            .fontSize(AppFontSize.MICRO + 1)
            .fontColor(this.getSubTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 14 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .hitTestBehavior(HitTestMode.None)
    }
    .layoutWeight(1)
    .height(40)
    .margin({ left: AppSpacing.MD, right: AppSpacing.MD })
    .borderRadius(20)
    // With HDS material the capsule shares the round buttons' untinted system glass; older systems keep the
    // themed glass panel because their round buttons have no surface to match.
    .backgroundColor(ImmersiveMaterialRuntime.supportsHdsTabs() ? Color.Transparent : this.readerGlassPanelColor())
    .backdropBlur(ImmersiveMaterialRuntime.supportsHdsTabs() ? 0 : ThemeRuntime.glassBlur('panel', 22))
    .border({
      width: ImmersiveMaterialRuntime.supportsHdsTabs() ? 0 : ThemeRuntime.glassBorderWidth('panel'),
      color: this.readerGlassBorderColor()
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = Math.round(Number(newArea.width));
      if (width !== this.readerComicTitleCapsuleWidth) this.readerComicTitleCapsuleWidth = width;
    })
  }

  @Builder
  readerComicTitleCapsuleMaterial() {
    // Same HdsTabs material trick as ImmersiveBackButton so the capsule and the round buttons render one surface.
    HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
      TabContent() {
        Column()
      }
      .height(40)
      .tabBar(this.readerComicTitleCapsuleMaterialTab())
    }
    .barMode(BarMode.Fixed)
    .barHeight(40)
    .barOverlap(true)
    .barFloatingStyle({
      barWidth: {
        smallWidth: this.readerComicTitleCapsuleWidth,
        mediumWidth: this.readerComicTitleCapsuleWidth,
        largeWidth: this.readerComicTitleCapsuleWidth
      },
      systemMaterialEffect: {
        materialType: ImmersiveMaterialRuntime.materialType(),
        materialLevel: ImmersiveMaterialRuntime.materialLevel()
      },
      barSideMargin: 0,
      barBottomMargin: 0,
      gradientMask: {
        maskColor: Color.Transparent,
        maskHeight: 40
      },
      adaptToHandedness: false,
      thermoCtrl: true,
      barOpacity: 1
    })
    .scrollable(false)
    .onContentWillChange(() => false)
    .width(this.readerComicTitleCapsuleWidth)
    .height(40)
    .borderRadius(20, RenderStrategy.OFFSCREEN)
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerComicTitleCapsuleMaterialTab() {
    Stack()
      .width('100%')
      .height('100%')
  }

  /** Floating bottom bars use the same untinted material as the top round buttons in every reading mode. */
  readerFloatingBarTintColor(): ResourceColor {
    return Color.Transparent;
  }

  readerComicSurfaceColor(): string {
    return ReaderComicStyle.surfaceColor(this.readerComicSettings.background);
  }

  readerComicWindowColor(): string {
    return ReaderComicStyle.windowColor(this.readerComicSettings.background, this.getBackgroundColor());
  }

  isReaderComicSurfaceDark(): boolean {
    return ReaderComicStyle.isDark(this.readerComicSettings.background, this.isReaderThemeDark());
  }

  readerComicSurfaceTextColor(): string {
    return ReaderComicStyle.textColor(this.readerComicSettings.background, this.getTextColor(), this.isReaderThemeDark());
  }

  readerComicSurfaceHintColor(): string {
    return ReaderComicStyle.hintColor(this.readerComicSettings.background, this.getSubTextColor(),
      this.isReaderThemeDark());
  }

  readerLoadingSurfaceColor(): string {
    return this.isReaderComicModeActive() ? this.readerComicWindowColor() : this.getBackgroundColor();
  }

  isReaderLoadingSurfaceDark(): boolean {
    return this.isReaderComicModeActive() ? this.isReaderComicSurfaceDark() : this.isReaderThemeDark();
  }

  loadReaderComicSettings(): void {
    ReaderComicSettingsStore.load(getContext(this)).then((settings: ReaderComicSettings): void => {
      this.readerComicSettings = settings;
      this.syncReaderInfoBarClock();
      if (this.isReaderComicModeActive() && this.readerPageVisible) this.enterReaderImmersive();
    }).catch((error: Error) => {
      console.warn('读取漫画设置失败:', error);
    });
  }

  readerComicSuperResolutionAccess(): string {
    // 读取会员档位只为让档位变化时界面重算；是否有效以账号快照按服务端时间推算为准。
    const sku = this.readerMembershipSku;
    return sku !== undefined ? ReaderComicSuperResolution.access() : ReaderComicSuperResolutionAccess.MEMBER_REQUIRED;
  }

  isReaderComicSuperResolutionActive(): boolean {
    return this.readerComicSettings.superResolution &&
      this.readerComicSuperResolutionAccess() === ReaderComicSuperResolutionAccess.READY;
  }

  readerComicTextConvertAccess(): string {
    // 读取会员档位只为让档位变化时界面重算，口径同超分。
    const sku = this.readerMembershipSku;
    return sku !== undefined ? ComicChineseConverter.access() : ReaderComicSuperResolutionAccess.MEMBER_REQUIRED;
  }

  isReaderComicTextConvertActive(): boolean {
    return this.readerComicTextConvert &&
      this.readerComicTextConvertAccess() === ReaderComicSuperResolutionAccess.READY;
  }

  setReaderComicTextConvert(enabled: boolean): void {
    if (!this.book || enabled === this.readerComicTextConvert) return;
    this.readerComicTextConvert = enabled;
    this.book.putVariable('readerComicTextConvert', enabled ? 't2s' : '');
    AppDatabase.getInstance().updateBook(this.book, false).catch((error: Error) => {
      console.warn('保存漫画繁→简设置失败:', error);
    });
  }

  updateReaderComicSettings(mutate: (settings: ReaderComicSettings) => void): void {
    const next = this.readerComicSettings.copy();
    mutate(next);
    const backgroundChanged = next.background !== this.readerComicSettings.background;
    this.readerComicSettings = next;
    ReaderComicSettingsStore.save(getContext(this), next).catch((error: Error) => {
      console.warn('保存漫画设置失败:', error);
    });
    if (backgroundChanged) this.enterReaderImmersive();
    this.syncReaderInfoBarClock();
  }

  @Builder
  readerComicModeSettingsPanel() {
    ReaderComicModeSettingsPanel({
      mode: this.readerComicEffectiveMode(),
      defaultMode: this.readerComicSettings.defaultMode,
      tapTurn: this.readerComicSettings.tapTurn,
      dualPage: this.readerComicSettings.dualPage,
      volumeTurnPage: this.readerVolumeTurnPage,
      tapZoneSummary: this.tapZoneSummaryText(),
      orientationOptions: this.screenOrientationOptions(),
      orientationSelected: this.screenOrientationSelectedIndex(),
      colors: this.readerComicPanelColors(),
      onSelectMode: (mode: string): void => {
        if (mode === READER_COMIC_TEXT_MODE) {
          if (this.isReaderComicModeActive()) this.toggleReaderComicReadingMode();
        } else {
          this.setReaderComicBookMode(mode);
        }
      },
      onSetDefaultMode: (): void => {
        const mode = this.readerComicEffectiveMode();
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.defaultMode = mode;
        });
        HdsFeedback.showToast(`默认阅读方式已设为${ReaderComicMode.label(mode)}`);
      },
      onTapTurnChange: (checked: boolean): void => {
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.tapTurn = checked;
        });
      },
      onConfigureTapZones: (): void => this.presentTapZoneSettings(),
      onVolumeTurnChange: (checked: boolean): void => this.setReaderVolumeTurnPage(checked),
      onOrientationChange: (index: number): void => this.setReaderScreenOrientationByIndex(index),
      onDualPageChange: (checked: boolean): void => {
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.dualPage = checked;
        });
      }
    })
  }

  @Builder
  readerComicDisplaySettingsPanel() {
    ReaderComicDisplaySettingsPanel({
      surface: this.readerComicSettings.background,
      pageGap: this.readerComicSettings.pageGap,
      fit: this.readerComicSettings.fit,
      preloadCount: this.readerComicSettings.preloadCount,
      infoBar: this.readerComicSettings.infoBar,
      doubleTapZoom: this.readerComicSettings.doubleTapZoom,
      superResolution: this.readerComicSettings.superResolution,
      superResolutionAccess: this.readerComicSuperResolutionAccess(),
      textConvert: this.readerComicTextConvert,
      textConvertAccess: this.readerComicTextConvertAccess(),
      themeBackground: this.getBackgroundColor(),
      colors: this.readerComicPanelColors(),
      onBackgroundChange: (value: string): void => {
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.background = ReaderComicBackground.normalize(value);
        });
      },
      onPageGapChange: (value: number): void => {
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.pageGap = value;
        });
      },
      onFitChange: (value: string): void => {
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.fit = ReaderComicFit.normalize(value);
        });
      },
      onPreloadCountChange: (value: number): void => {
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.preloadCount = value;
        });
      },
      onInfoBarChange: (checked: boolean): void => {
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.infoBar = checked;
        });
      },
      onDoubleTapZoomChange: (checked: boolean): void => {
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.doubleTapZoom = checked;
        });
      },
      onSuperResolutionChange: (checked: boolean): void => {
        this.updateReaderComicSettings((settings: ReaderComicSettings): void => {
          settings.superResolution = checked;
        });
      },
      onTextConvertChange: (checked: boolean): void => this.setReaderComicTextConvert(checked),
      onOpenMembership: (): void => {
        this.hideReaderPanels();
        router.pushUrl({ url: 'pages/AccountCenter' });
      }
    })
  }

  readerComicPanelColors(): ReaderComicPanelColors {
    const colors = new ReaderComicPanelColors();
    colors.textColor = this.getTextColor();
    colors.subTextColor = this.getSubTextColor();
    colors.accentColor = this.accentColor();
    colors.dark = this.isReaderThemeDark();
    colors.menuColor = ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor());
    colors.buttonColor = this.buttonColor();
    colors.buttonTextColor = ThemeRuntime.onAccentColor();
    return colors;
  }

  pageTransition() {
    if (this.openedWithShelfAnimation || AppStorage.get<boolean>('shelfReaderDirectTransition') === true) {
      PageTransitionEnter({ type: RouteType.Push, duration: 0 })
    }
  }

  build() {
    Stack() {
      BookSourceStageRuntimeHost()
      if (this.readerWebFetchRuntimeNeeded) {
        WebBookFetchRuntimeHost()
      }
      if (this.readerEyeTurnEnabled) {
        // The camera Surface stays behind the opaque reader background. It is never shown or persisted; only a
        // throttled local PixelMap is sampled while this page is in the foreground.
        XComponent({
          id: 'reader_eye_turn_camera_surface',
          type: XComponentType.SURFACE,
          controller: this.readerEyeTurnSurfaceController
        })
          // Never resize the live camera Surface to 1x1. Some camera drivers use the component's layout viewport
          // as the producer crop even when setXComponentSurfaceRect keeps a 640x480 buffer; shrinking it after
          // calibration then yielded faceNum=0 for every reading-page frame. The opaque theme hides this stable
          // Surface in normal reading mode.
          .width(this.eyeTurnState.previewWidthVp(this.pageViewWidth, this.pageViewHeight))
          .height(this.eyeTurnState.previewHeightVp(this.pageViewWidth, this.pageViewHeight))
          .position({
            x: this.eyeTurnState.showCalibration ?
            this.eyeTurnState.previewLeftVp(this.pageViewWidth, this.pageViewHeight) : 0,
            y: this.eyeTurnState.showCalibration ? ReaderEyeTurnViewState.PREVIEW_TOP_VP : 0
          })
          // Keep the surface fully rendered even while reading: with a near-zero opacity some
          // builds stop drawing this node, the camera preview stops delivering frames, and the
          // face detector then reports "no face" for the whole reading session. It stays hidden
          // because the opaque reader background is drawn above it (zIndex -1).
          .opacity(1)
          .borderRadius(this.eyeTurnState.showCalibration ? 20 : 0)
          .clip(true)
          .zIndex(this.eyeTurnState.showCalibration ? 3 : -1)
          .hitTestBehavior(HitTestMode.None)
          .onLoad((): void => {
            this.readerEyeTurnSurfaceController.setXComponentSurfaceRect({
              surfaceWidth: 640,
              surfaceHeight: 480
            });
            this.eyeTurn().onSurfaceLoaded(this.readerEyeTurnSurfaceController.getXComponentSurfaceId());
          })
          .onDestroy((): void => {
            this.eyeTurn().onSurfaceDestroyed();
          })
        if (this.eyeTurnState.arHostMounted && this.eyeTurn().arHost) {
          // Keep the ARView rendered (a fully transparent node never reaches
          // TRACKING) but clamp it to a single pixel behind the page content.
          NodeContainer(this.eyeTurn().arHost!.controller)
            .width(1).height(1)
            .position({ x: 0, y: 0 })
            .zIndex(-1)
            .hitTestBehavior(HitTestMode.None)
        }
      }
      ReaderThemeBackground({
        surfaceColor: this.getBackgroundColor(),
        backgroundAssetId: this.getBackgroundAssetId(),
        customImage: this.currentReaderTheme().backgroundImageUri,
        customImageFit: this.getBackgroundImageFit(),
        viewportWidthHint: this.pageViewWidth,
        viewportHeightHint: this.getReaderBackgroundViewportHeight()
      })
        .id('reader_theme_background_root')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .hitTestBehavior(HitTestMode.None)

      Column() {
        if (!this.shouldRenderPrimaryReaderContent()) {
          this.readerLoadingPanel()
        } else if (this.isReaderComicPagedMode()) {
          this.readerComicPagedSurface()
        } else if (this.isReaderComicModeActive()) {
          this.readerComicSurface()
        } else if (this.isReaderContinuousScrollSurfaceActive()) {
          this.readerComicScrollSurface()
        } else {
          Stack() {
            if (this.shouldUseReaderLayoutV2(this.pagedContentText)) {
              // Keep the native paragraph node mounted across sequential turns inside one chapter, but give every
              // chapter its own keyed host. Some ArkUI versions retain the old NodeContainer when only its
              // NodeController argument changes; the footer then advances while the canvas keeps painting the
              // previous chapter forever. A chapter-scoped key remounts only at the boundary, while the already
              // prepared incoming leaf remains on top for the short handoff.
              ForEach(this.currentReaderV2ChapterSurfaceKeys(), (_surfaceKey: string) => {
                this.readerActiveCurrentPageSurface(this.pageRenderVersion, this.visibleCurrentPageText(),
                  this.ttsHighlightRenderVersion)
              }, (surfaceKey: string) => surfaceKey)
            } else {
              ForEach(this.currentReaderSurfaceKeys(), (_surfaceKey: string) => {
                this.readerActiveCurrentPageSurface(this.pageRenderVersion, this.visibleCurrentPageText(),
                  this.ttsHighlightRenderVersion)
              }, (surfaceKey: string) => surfaceKey)
            }
            // Keep the V2 TTS focus outside the chapter-scoped正文 host. That host deliberately preserves its
            // native Paragraph node across same-page updates, and some ArkUI builds consequently skip nested
            // ForEach evaluation. Rekey only this lightweight rectangle layer for every audible chunk.
            ForEach(this.currentReaderV2TtsOverlayKeys(this.readerV2TtsPaintVersion), (_focusKey: string) => {
              this.readerCurrentV2TtsOverlay(this.readerV2TtsPaintVersion)
            }, (focusKey: string) => focusKey)
            // Native Text supplies selection handles and the system menu, but its line boxes do not exactly match
            // the Paragraph glyph boxes used to paint正文. Paint the range from Paragraph geometry so text stays
            // vertically centered in the blue selection in every page-turn mode.
            ForEach(this.currentReaderV2SelectionOverlayKeys(this.readerV2SelectionPaintVersion),
              (_selectionPaintKey: string) => {
              this.readerCurrentV2SelectionOverlay(this.readerV2SelectionPaintVersion)
            }, (selectionPaintKey: string) => selectionPaintKey)
            // The retained V2 host above only updates its native canvas during same-chapter turns. Selection Text
            // must be page-keyed outside that host; otherwise its content advances while its paragraph coordinates
            // remain those of the first mounted page, and long-press handles appear on another line.
            ForEach(this.currentReaderV2SelectionSurfaceKeys(this.readerV2NativeSelectionHostVersion),
              (_selectionKey: string) => {
              this.readerCurrentV2SelectionSurface(this.readerV2NativeSelectionHostVersion,
                this.readerV2NativeSelectionOffsetX, this.readerV2NativeSelectionOffsetY)
            }, (selectionKey: string) => selectionKey)
            // Legacy rich text is keyed by page; V2 updates its retained node in place. Keep the simulation
            // overlay outside both paths so the destination can settle behind the captured leaf without
            // destroying the active Canvas.
            if (this.isPageTurnAnimationEnabled() && this.usesReaderPageCurlCanvas() &&
              this.shouldRenderSlidingPageTurn()) {
              this.readerSimulationPageTurnSurface(this.pageRenderVersion, this.visibleCurrentPageText(),
                this.ttsHighlightRenderVersion, 'overlay')
            }
            // Keep the simulation Canvas mounted for the lifetime of the selected turn mode. Destroying and
            // recreating it at every completed curl races the RenderService submission of the last textured
            // frame (SubmitCanvasPreAllocatedBuffer) and can expose a one-frame handoff shake. The capture
            // surfaces above remain transient; the inexpensive Canvas is merely hidden while it is idle.
            if (this.isPageTurnAnimationEnabled() && this.usesReaderPageCurlCanvas()) {
              this.readerSimulationCurlCanvas()
            }
            Column() {
              if (this.isReaderHeaderVisible()) {
                this.readerHeaderInfoBar()
              }
              Blank()
                .layoutWeight(1)
              if (this.readerFooterEnabled) {
                this.readerBottomInfoBar()
              }
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
            this.rememberReaderTapLayerArea(newValue);
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getReaderTopSafePadding() })
      // 正文未就绪时整列充当加载遮罩。列顶部的状态栏内边距会让遮罩上缘缩进状态栏高度，
      // 主题带背景画时该缝隙会露出 ReaderThemeBackground 的装饰图，因此遮罩期间强制铺不透明底色。
      .backgroundColor(this.shouldRenderPrimaryReaderContent() ? this.readerContentLayerColor() :
        this.getBackgroundColor())
      .hitTestBehavior(HitTestMode.Default)

      if (!this.isReaderContinuousScrollSurfaceActive() && !this.showMenu && !this.showToc && !this.showSettings &&
        !this.shouldBlockReaderInteraction()) {
        this.readerTapLayer()
      }

      if (this.readerComicPaginationParsing) {
        this.readerComicPaginationPanel()
      } else if (this.shouldShowReaderLoadingOverlay()) {
        this.readerLoadingPanel()
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

      if (this.showLayoutElementSettings) {
        this.readerLayoutElementSettingsDialog()
      }

      if (this.showMenu && !this.showToc && !this.showSettings && this.chapters.length > 0) {
        if (this.supportsReaderImmersiveMaterial()) {
          this.readerMaterialFloatingBottomMenu()
        } else {
          this.readerFloatingBottomMenu()
        }
        if (this.readerUseTtsQuickAction && !this.isReaderComicModeActive() &&
          !this.isTtsSpeaking && !this.ttsReader.isSpeaking() && !this.globalTtsActive) {
          this.readerTtsQuickActionButton()
        }
      }

      if (this.showToc) {
        this.readerFloatingTocPanel()
        if (this.supportsReaderImmersiveMaterial()) {
          this.readerMaterialFloatingActionBar(true)
        }
      }

      if (this.showSettings) {
        this.settingsPanel()
        if (this.showTtsVoiceDropdown) {
          this.ttsVoiceDropdownPanel()
        }
        if (this.supportsReaderImmersiveMaterial()) {
          this.readerMaterialFloatingActionBar(false, true)
        }
      }

      if (this.readerUseTtsQuickAction && this.shouldShowTtsMiniPlayer()) {
        this.ttsMiniPlayer()
      } else if (this.readerUseTtsQuickAction && this.shouldShowGlobalTtsMiniPlayer()) {
        this.globalTtsMiniPlayer()
      }

      if (this.showTtsQuickPlayer) {
        this.sharedTtsPlayerPanel(true)
      }

      if (this.globalTtsActive && this.showGlobalTtsQuickPlayer) {
        this.sharedTtsPlayerPanel(false)
      }

      // The catalog overlay serves both panel owners: the reader's own quick player
      // and the floating panel published while another page is in front.
      if (this.showGlobalTtsCatalog &&
        (this.showTtsQuickPlayer || (this.globalTtsActive && this.showGlobalTtsQuickPlayer))) {
        this.globalTtsCatalogOverlay()
      }

      if (this.showBookmarkActionMenu && this.pendingBookmarkAction) {
        this.bookmarkActionMenu()
      }

      if (this.showChangeSourceDialog) {
        BookChangeSourceDialog({
          targetBook: this.book,
          markReadOnSwitch: true,
          onBeforeSwitch: (): Promise<void> => {
            return this.saveReadingProgress();
          },
          onSwitched: (fullBook: Book): void => {
            this.pendingSwitchedBook = fullBook;
          },
          onClosed: (): void => {
            this.showChangeSourceDialog = false;
            if (this.pendingSwitchedBook) {
              const fullBook = this.pendingSwitchedBook;
              this.pendingSwitchedBook = null;
              this.bookUrl = fullBook.bookUrl;
              this.book = fullBook;
              this.loadBook();
              this.loadBookmarks();
            }
          }
        })
      }

      if (this.readerEyeTurnEnabled && this.readerInitialPageReady && !this.eyeTurnState.showCalibration &&
        !this.showMenu && !this.showToc && !this.showReaderCommentPanel) {
        this.readerEyeTurnPrompt()
      }

      if (this.eyeTurnState.showCalibration) {
        this.readerEyeCalibrationPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.readerContentLayerColor())
    .expandSafeArea([SafeAreaType.SYSTEM], this.getReaderSafeAreaEdges())
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.refreshReaderScreenTimeout();
      }
    })
    .bindSheet($$this.showReaderCommentPanel, this.readerCommentPanel(), this.readerCommentSheetOptions())
  }

  /**
   * 段评弹层停 60% 与全屏两档，仅顶部拖动区调整高度，网页手势只滚动评论。
   */
  readerCommentSheetOptions(): SheetOptions {
    return {
      detents: ['60%', SheetSize.LARGE],
      // 使用系统拖动条承接弹层手势；普通 Row 命中区不会自动驱动弹层高度。
      dragBar: true,
      showClose: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      // 底色与评论页一致，拖动到网页尚未铺满的位置时也看不出接缝。
      backgroundColor: this.readerCommentPanelWebBackground(),
      onDisappear: () => {
        if (!this.showReaderCommentPanel) {
          this.resetReaderCommentPanelState();
        }
      }
    };
  }

  /** 评论页（含注入的反色样式）在深浅色下的大致底色，用作网页默认底色与弹层底色。 */
  readerCommentPanelWebBackground(): string {
    return this.appDarkMode ? '#131313' : '#FFFFFF';
  }

  updateReaderCommentPanelHeight(height: number): void {
    // onSizeChange 返回内容区的 vp 高度，已扣除系统拖动条，不能再按整张弹层高度布局 Web。
    if (!this.showReaderCommentPanel || !Number.isFinite(height) || height <= 0) return;
    if (Math.abs(height - this.readerCommentPanelHeight) >= 0.5) this.readerCommentPanelHeight = height;
  }

  @Builder
  readerCommentPanel() {
    Stack({ alignContent: Alignment.Top }) {
      // 与弹层同步合成，避免独立 Web surface 在连续扩容时底部露出未绘制的白条。
      Web({ src: this.readerCommentPanelUrl, controller: this.readerCommentPanelController,
        renderMode: RenderMode.SYNC_RENDER })
        .width('100%')
        .height(this.readerCommentPanelHeight > 0 ? this.readerCommentPanelHeight : '100%')
        .backgroundColor(this.readerCommentPanelWebBackground())
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .darkMode(this.appDarkMode ? WebDarkMode.On : WebDarkMode.Off)
        // 强制深色在部分 ArkWeb 版本上不生效，生效时又会和下面的注入样式叠加反色；
        // 没有深色样式的评论页统一由 syncReaderCommentPanelWebTheme 注入反色样式。
        .forceDarkAccess(false)
        .javaScriptProxy({
          object: this.readerCommentNavigationBridge,
          name: 'LegadoCommentHost',
          methodList: ['back', 'close'],
          controller: this.readerCommentPanelController
        })
        .onWindowExit(() => this.closeReaderCommentPanel())
        .javaScriptOnDocumentStart([{
          script: ReaderCommentWebTheme.bootstrap(this.appDarkMode), scriptRules: ['*']
        }])
        // 网页滚动不传递给弹层，高度只由顶部拖动区调整。
        .nestedScroll({
          scrollForward: NestedScrollMode.SELF_ONLY,
          scrollBackward: NestedScrollMode.SELF_ONLY
        })
        .onControllerAttached(() => {
          this.readerCommentPanelHtmlLoaded = false;
          setTimeout(() => this.loadReaderCommentPanelHtmlIfNeeded(), 0);
        })
        .onPageBegin(() => {
          this.readerCommentPanelLoadSerial++;
          if (this.readerCommentPanelReadyTimerId >= 0) clearTimeout(this.readerCommentPanelReadyTimerId);
          this.readerCommentPanelReadyTimerId = -1;
          this.readerCommentPanelLoading = true;
          this.readerCommentPanelError = false;
          if (this.readerCommentPanelHtmlLoaded) this.scheduleReaderCommentPanelHostReady(180);
        })
        .onPageEnd(() => {
          if (this.readerCommentPanelError) return;
          if (this.loadReaderCommentPanelHtmlIfNeeded()) return;
          this.scheduleReaderCommentPanelHostReady(0);
        })
        .onErrorReceive((event) => {
          if (event.request.isMainFrame()) this.failReaderCommentPanelLoad();
        })

      if (this.readerCommentPanelLoading) {
        Column({ space: 10 }) {
          if (!this.readerCommentPanelError) {
            LoadingProgress()
              .width(38)
              .height(38)
              .color(this.accentColor())
          }
          Text(this.readerCommentPanelError ? '评论显示失败，请重试' : '评论加载中…')
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          if (this.readerCommentPanelError) {
            Button('重试')
              .onClick(() => this.retryReaderCommentPanelLoad())
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.readerCommentPanelWebBackground())
      }

    }
    .width('100%')
    .height('100%')
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.updateReaderCommentPanelHeight(Number(newValue.height));
    })
    .backgroundColor(this.readerCommentPanelWebBackground())
    .clip(true)
  }

  @Builder
  readerFloatingTopMenu() {
    Row() {
      ImmersiveBackButton({
        iconColor: this.readerControlIconColor(),
        darkMode: this.isReaderThemeDark(),
        buttonSize: 40,
        containerWidth: 40,
        containerHeight: 56,
        startInset: 0,
        materialScale: 0.83,
        compactLayout: true,
        onBack: () => this.exitReaderPage()
      })

      if (this.isReaderComicModeActive()) {
        this.readerComicTitleCapsule()
      } else {
        Blank()
          .layoutWeight(1)
      }

      Row({ space: AppSpacing.SM }) {
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
    .padding({ left: 18, right: 18, top: this.getTopControlSafePadding() + 10 })
    .position({ x: 0, y: 0 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  readerRoundMenuButton(icon: Resource, accessibilityText: string, action: () => void) {
    ImmersiveBackButton({
      icon: icon,
      iconOffsetX: 0,
      iconColor: this.readerControlIconColor(),
      darkMode: this.isReaderThemeDark(),
      buttonSize: 40,
      containerWidth: 40,
      containerHeight: 56,
      startInset: 0,
      materialScale: 0.83,
      compactLayout: true,
      accessibilityLabel: accessibilityText,
      onBack: action
    })
  }

  supportsReaderImmersiveMaterial(): boolean {
    return ImmersiveMaterialRuntime.supportsHds() || ImmersiveMaterialRuntime.supportsHdsMaterial();
  }

  @Builder
  readerMaterialFloatingBottomMenu() {
    Column({ space: AppSpacing.XS }) {
      if (this.isReaderComicModeActive()) {
        this.readerMaterialChapterBar(true)
      } else if (this.readerUseChapterQuickJump) {
        this.readerMaterialChapterBar()
      }
      this.readerMaterialActionBar(false)
    }
    .width('100%')
    .height(this.readerBottomMenuOverlayHeight())
    .padding({ bottom: this.readerFloatingBarBottomMargin() })
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
    .position({ x: 0, y: '100%' })
    .translate({
      x: this.readerFloatingBarTranslateX(),
      y: -this.readerBottomMenuOverlayHeight()
    })
  }

  @Builder
  readerMaterialChapterBar(comicPages: boolean = false) {
    Stack({ alignContent: Alignment.Center }) {
      if (ImmersiveMaterialRuntime.supportsHds()) {
        ReaderFloatingMaterialBar({
          barWidth: this.readerFloatingBarWidth(),
          tintColor: this.readerFloatingBarTintColor()
        }) {
          this.readerHdsProgressBarContent(comicPages)
        }
      } else {
        this.readerHdsChapterTabBar(comicPages)
      }

      this.readerChapterTooltip(comicPages)
    }
    .width('100%')
    .height(56)
  }

  @Builder
  readerHdsChapterTabBar(comicPages: boolean) {
    HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
      TabContent() {
        Column()
      }
      .height(56)
      .tabBar(this.readerHdsProgressBarContent(comicPages))
    }
    .key(`reader_hds_chapter_bar_${comicPages ? 'comic' : 'chapter'}_${this.themeRevision}_` +
      `${this.isReaderThemeDark() ? 'dark' : 'light'}`)
    .barBackgroundColor(this.readerFloatingBarTintColor())
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
        materialType: ImmersiveMaterialRuntime.materialType(),
        materialLevel: ImmersiveMaterialRuntime.materialLevel()
      },
      barSideMargin: 0,
      barBottomMargin: 4,
      gradientMask: {
        maskColor: Color.Transparent,
        maskHeight: 56
      },
      adaptToHandedness: false,
      thermoCtrl: true,
      barOpacity: 1
    })
    .scrollable(false)
    .width('100%')
    .height(56)
  }

  @Builder
  readerChapterTooltip(comicPages: boolean) {
    if (comicPages ? this.comicPageTooltipVisible : this.menuChapterTooltipVisible) {
      Column({ space: AppSpacing.XXS }) {
        Text(this.getChapterTitle(comicPages ? this.currentChapterIndex : this.getMenuChapterDisplayIndex()))
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(comicPages ? `第 ${this.comicMenuPageIndex() + 1} / ${this.readerComicTotalPageCount()} 页` :
          `${this.getMenuChapterDisplayIndex() + 1}/${this.chapters.length}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#CCFFFFFF')
      }
      .width(this.readerChapterTooltipWidth())
      .height(44)
      .padding({ left: 14, right: 14, top: 5, bottom: 5 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(22)
      .backgroundColor(this.isReaderThemeDark() ? '#E63A3C40' : '#D94B4D52')
      .shadow({ radius: 10, color: '#50000000', offsetX: 0, offsetY: 3 })
      .position({ x: this.readerChapterTooltipCenteredLeft(), y: -48 })
    }
  }

  @Builder
  readerHdsProgressBarContent(comicPages: boolean) {
    if (comicPages) {
      this.readerHdsComicPageBarContent()
    } else {
      this.readerHdsChapterBarContent()
    }
  }

  @Builder
  readerHdsComicPageBarContent() {
    Row() {
      this.readerComicChapterStepButton(-1)
      this.readerComicPageSlider(48, 30)
      this.readerComicChapterStepButton(1)
    }
    .width('100%')
    .height(48)
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    .alignItems(VerticalAlign.Center)
    .translate({ y: ImmersiveMaterialRuntime.supportsHds() ? 0 : -2 })
  }

  @Builder
  readerComicChapterStepButton(direction: number) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(direction < 0 ? $r('sys.symbol.chevron_left') : $r('sys.symbol.chevron_right'))
        .fontSize(25)
        .fontColor([this.canStepReaderComicChapter(direction) ? this.getTextColor() : this.getSubTextColor()])
    }
    .width(46)
    .height(48)
    .enabled(this.canStepReaderComicChapter(direction))
    .accessibilityText(direction < 0 ? '上一话' : '下一话')
    .onClick(async () => {
      await this.jumpToAdjacentChapterFromMenu(direction);
    })
  }

  @Builder
  readerComicPageSlider(height: number, thickness: number) {
    Slider({
      value: this.comicMenuPageIndex(),
      min: 0,
      max: Math.max(1, this.readerComicTotalPageCount() - 1),
      step: 1,
      style: SliderStyle.InSet
    })
      .layoutWeight(1)
      .height(height)
      .trackThickness(thickness)
      .blockSize({ width: thickness, height: thickness })
      .selectedColor(this.accentColor())
      .trackColor(this.readerChapterTrackColor())
      .blockColor(this.readerSolidPanelColor())
      .showSteps(false)
      .enabled(this.readerComicTotalPageCount() > 1)
      .onChange((value: number, mode: SliderChangeMode) => {
        this.handleComicPageSliderChange(value, mode);
      })
  }

  @Builder
  readerHdsChapterBarContent() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
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
        SymbolGlyph($r('sys.symbol.chevron_right'))
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
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    .alignItems(VerticalAlign.Center)
    .translate({ y: ImmersiveMaterialRuntime.supportsHds() ? 0 : -2 })
  }

  @Builder
  readerMaterialFloatingActionBar(fromToc: boolean, fromSettings: boolean = false) {
    Column() {
      this.readerMaterialActionBar(fromToc, fromSettings)
    }
    .width('100%')
    .height(this.readerBottomActionOverlayHeight())
    .padding({ bottom: this.readerFloatingBarBottomMargin() })
    .justifyContent(FlexAlign.End)
    .position({ x: 0, y: '100%' })
    .translate({
      x: this.readerFloatingBarTranslateX(),
      y: -this.readerBottomActionOverlayHeight()
    })
  }

  @Builder
  readerMaterialActionBar(fromToc: boolean, fromSettings: boolean = false) {
    if (ImmersiveMaterialRuntime.supportsHds()) {
      Stack({ alignContent: Alignment.Center }) {
        ReaderFloatingMaterialBar({
          barWidth: this.readerFloatingBarWidth(),
          tintColor: this.readerFloatingBarTintColor()
        }) {
          this.readerMaterialActionBarContent(fromToc, fromSettings)
        }
      }
      .width('100%')
      .height(56)
    } else {
      this.readerHdsActionBar(fromToc, fromSettings)
    }
  }

  @Builder
  readerMaterialActionBarContent(fromToc: boolean, fromSettings: boolean) {
    Row() {
      ForEach([0, 1, 2], (index: number) => {
        Stack({ alignContent: Alignment.Center }) {
          this.readerHdsMenuItem(index === 0 ? $r('sys.symbol.list_bullet') : this.readerMenuActionIcon(index),
            index === 0 ? fromToc :
              fromSettings && this.settingsPanelTab === this.readerMenuActionSettingsTab(index))
        }
        .layoutWeight(1)
        .height(48)
        .accessibilityText(index === 0 ? '目录' : (index === 1 ?
          (this.isReaderComicModeActive() ? '阅读方式' : '阅读设置') :
          (this.isReaderComicModeActive() ? '画面设置' : '排版设置')))
        .onClick(() => this.handleReaderHdsAction(index, this.showToc, this.showSettings))
      }, (index: number) => `${index}`)

      Stack() {
        this.readerHdsDayNightMenuItem()
      }
      .layoutWeight(1)
      .height(48)
      .accessibilityText('切换日间或夜间模式，长按跟随系统')
    }
    .width('100%')
    .height(48)
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
      .tabBar(this.readerHdsMenuItem(this.readerMenuActionIcon(1),
        fromSettings && this.settingsPanelTab === this.readerMenuActionSettingsTab(1)))

      TabContent() {
        Column()
      }
      .height(56)
      .tabBar(this.readerHdsMenuItem(this.readerMenuActionIcon(2),
        fromSettings && this.settingsPanelTab === this.readerMenuActionSettingsTab(2)))

      TabContent() {
        Column()
      }
      .height(56)
      .tabBar(this.readerHdsDayNightMenuItem())
    }
    .key(`reader_hds_action_bar_${this.isReaderComicModeActive() ? 'comic' : 'text'}_${this.themeRevision}_` +
      `${this.isReaderThemeDark() ? 'dark' : 'light'}`)
    .barBackgroundColor(this.readerFloatingBarTintColor())
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
        materialType: ImmersiveMaterialRuntime.materialType(),
        materialLevel: ImmersiveMaterialRuntime.materialLevel()
      },
      barSideMargin: 0,
      barBottomMargin: 4,
      gradientMask: {
        maskColor: Color.Transparent,
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
  readerHdsMenuItem(icon: Resource, active: boolean, showAddBadge: boolean = false, enabled: boolean = true) {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([this.readerControlIconColor()])

        if (showAddBadge) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.readerControlIconColor()])
            .position({ x: 20, y: 0 })
        }
      }
      .width(32)
      .height(32)
    }
    .width('100%')
    .height(48)
    .opacity(enabled ? 1 : 0.32)
    .enabled(enabled)
    .translate({ y: ImmersiveMaterialRuntime.supportsHds() ? 0 : -2 })
  }

  @Builder
  readerHdsDayNightMenuItem() {
    Stack() {
      this.readerHdsMenuItem(this.readerDayNightIcon(), false)
    }
    .width('100%')
    .height(48)
    .onClick(() => this.handleReaderDayNightClick())
    .gesture(
      LongPressGesture({ duration: 600, repeat: false })
        .onAction(() => this.handleReaderDayNightLongPress())
    )
  }

  handleReaderHdsAction(index: number, fromToc: boolean, fromSettings: boolean = false): void {
    if (index === 0) {
      if (fromToc) {
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
      // 日夜项由其自身的点击/长按手势处理，避免 HdsTabs 再次触发导致双重切换。
      return;
    }
    if (fromToc) {
      this.showToc = false;
    }
    if (index === 1 || index === 2) {
      const tab = this.readerMenuActionSettingsTab(index);
      if (fromSettings && this.settingsPanelTab === tab) {
        this.closeSettingsPanelKeepMenu();
      } else {
        this.openReaderSettingsTab(tab);
      }
    }
  }

  /** 底部操作栏第 1、2 项：普通阅读为阅读设置与排版，漫画为阅读方式与画面设置。 */
  readerMenuActionIcon(slot: number): Resource {
    if (this.isReaderComicModeActive()) {
      return slot === 1 ? $r('sys.symbol.book_pages') : $r('sys.symbol.picture');
    }
    return slot === 1 ? $r('sys.symbol.gearshape') : $r('sys.symbol.textformat');
  }

  readerMenuActionSettingsTab(slot: number): number {
    if (this.isReaderComicModeActive()) return slot === 1 ? 3 : 4;
    return slot === 1 ? 0 : 2;
  }

  openReaderSettingsTab(tab: number): void {
    if (tab === 3 || tab === 4) {
      this.openReaderComicSettingsPanel(tab);
    } else if (tab === 2) {
      this.openTypographySettingsPanel();
    } else {
      this.openSettingsPanel();
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
    const currentDark = currentMode === 'dark' || (currentMode === 'system' && this.appDarkMode);
    this.applyReaderThemeMode(currentDark ? 'light' : 'dark');
  }

  setReaderAutoMode(): void {
    this.applyReaderThemeMode('system');
  }

  handleReaderDayNightClick(): void {
    if (this.readerDayNightLongPressHandled) {
      this.readerDayNightLongPressHandled = false;
      return;
    }
    this.toggleReaderDayNightMode();
  }

  handleReaderDayNightLongPress(): void {
    this.readerDayNightLongPressHandled = true;
    this.setReaderAutoMode();
  }

  applyReaderThemeMode(nextMode: string): void {
    // 先提交面板草稿，再触发系统配色更新；不依赖关闭面板或稍后的 Watch 通知。
    this.flushPendingReaderLayoutChange(false);
    const context = getContext(this) as common.UIAbilityContext;
    const systemDarkMode =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const nextDarkMode = nextMode === 'dark' || (nextMode === 'system' && systemDarkMode);
    const colorMode = nextMode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      (nextMode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);

    // 先同步模式来源，避免 setColorMode 触发的 ConfigurationUpdate 读到旧值，
    // 又把刚选择的浅色模式覆盖回系统深色模式。
    AppThemeModeStore.applyToStorage(nextMode);
    if (this.appDarkMode !== nextDarkMode) {
      this.appDarkMode = nextDarkMode;
    }
    context.getApplicationContext().setColorMode(colorMode);

    AppThemeModeStore.save(context, nextMode).catch((e: Error) => {
      console.warn('保存日间/夜间/自动模式失败:', e);
    });
    HdsFeedback.showToast(nextMode === 'light' ? '已切换至日间模式' : (nextMode === 'dark' ? '已切换至夜间模式' : '已切换至自动模式'));
  }

  @Builder
  readerFloatingBottomMenu() {
    Column({ space: 10 }) {
      if (this.isReaderComicModeActive()) {
        this.readerFloatingComicPageRow()
      } else if (this.readerUseChapterQuickJump) {
        Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([this.currentChapterIndex > 0 && !this.isLoading ? this.getTextColor() : this.getSubTextColor()])
          .width(46)
          .height(54)
          .enabled(this.currentChapterIndex > 0 && !this.isLoading)
          .onClick(async () => {
            await this.jumpToAdjacentChapterFromMenu(-1);
          })

        Column({ space: 1 }) {
          Row() {
            Text(this.getChapterTitle(this.getMenuChapterDisplayIndex()))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.getSubTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(`${this.getMenuChapterDisplayIndex() + 1}/${this.chapters.length}`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.getSubTextColor())
              .margin({ left: AppSpacing.MD })
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

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(24)
          .fontColor([this.currentChapterIndex < this.chapters.length - 1 && !this.isLoading ?
            this.getTextColor() : this.getSubTextColor()])
          .width(46)
          .height(54)
          .enabled(this.currentChapterIndex < this.chapters.length - 1 && !this.isLoading)
          .onClick(async () => {
            await this.jumpToAdjacentChapterFromMenu(1);
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
        .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
        .backgroundColor(this.readerGlassPanelColor())
        .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
        .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
        .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      }

      Row() {
        this.readerFloatingIconMenuItem($r('sys.symbol.list_bullet'), false, () => {
          this.openTocPanel();
        })
        this.readerFloatingIconMenuItem(this.readerMenuActionIcon(1), false, () => {
          this.openReaderSettingsTab(this.readerMenuActionSettingsTab(1));
        })
        this.readerFloatingIconMenuItem(this.readerMenuActionIcon(2), false, () => {
          this.openReaderSettingsTab(this.readerMenuActionSettingsTab(2));
        })
        this.readerFloatingDayNightMenuItem()
      }
      .width('100%')
      .height(56)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
      .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
      .backgroundColor(this.readerGlassPanelColor())
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
    }
    .width(this.readerFloatingBarWidth())
    .padding({ bottom: 14 })
    .position({ x: this.readerFloatingBarLeft(), y: '100%' })
    .translate({ y: '-100%' })
  }

  @Builder
  readerFloatingComicPageRow() {
    Row() {
      this.readerComicChapterStepButton(-1)
      Column({ space: 1 }) {
        Row() {
          Text(this.getChapterTitle())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.getSubTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(`${this.comicMenuPageIndex() + 1}/${this.readerComicTotalPageCount()}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.getSubTextColor())
            .margin({ left: AppSpacing.MD })
        }
        .width('100%')

        Row() {
          this.readerComicPageSlider(24, 24)
        }
        .width('100%')
      }
      .layoutWeight(1)
      this.readerComicChapterStepButton(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
    .backgroundColor(this.readerGlassPanelColor())
    .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
    .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
    .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
  }

  @Builder
  readerFloatingIconMenuItem(icon: Resource, active: boolean, action: () => void,
    showAddBadge: boolean = false, enabled: boolean = true) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([this.readerControlIconColor()])

        if (showAddBadge) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.readerControlIconColor()])
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
    .opacity(enabled ? 1 : 0.32)
    .enabled(enabled)
    .onClick(action)
  }

  @Builder
  readerFloatingDayNightMenuItem() {
    Row() {
      this.readerFloatingIconMenuItem(this.readerDayNightIcon(), false, () => {})
    }
    .layoutWeight(1)
    .height(56)
    .onClick(() => this.handleReaderDayNightClick())
    .gesture(
      LongPressGesture({ duration: 600, repeat: false })
        .onAction(() => this.handleReaderDayNightLongPress())
    )
  }

  @Builder
  readerFloatingTocPanel() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showToc = false;
        })

      ReaderTocPanel({
        chapters: $chapters,
        bookmarks: $bookmarks,
        reverseOrder: $tocReverseOrder,
        currentChapterIndex: this.currentChapterIndex,
        dark: this.isReaderThemeDark(),
        textColor: this.getTextColor(),
        subTextColor: this.getSubTextColor(),
        accentColor: this.accentColor(),
        swipeButtonColor: this.buttonColor(),
        panelColor: this.readerGlassPanelColor(),
        solidPanelColor: this.readerSolidPanelColor(),
        panelBorderColor: this.readerGlassBorderColor(),
        panelShadowColor: this.readerGlassShadowColor(),
        selectedColor: this.tocSelectedBackgroundColor(),
        panelWidth: this.readerFloatingBarWidth(),
        panelHeight: this.readerTocPanelHeight(),
        book: this.book,
        controller: this.tocPanelController,
        chapterTitle: (chapterIndex: number): string => this.getChapterTitle(chapterIndex),
        onClose: (): void => {
          this.showToc = false;
        },
        onOpenBookDetail: (): void => {
          this.openCurrentBookDetail();
        },
        onJumpToChapter: (chapterIndex: number): void => {
          this.showToc = false;
          this.showMenu = false;
          this.jumpToReaderPositionKeepingTts(chapterIndex, 0);
        },
        onJumpToBookmark: (bookmark: Bookmark): void => {
          this.jumpToBookmark(bookmark);
        },
        onRefreshToc: (): Promise<void> => this.retryFetchChapters(),
        onLoadBookmarks: (): void => {
          this.loadBookmarks();
        },
        onShowBookmarkActions: (bookmark: Bookmark, globalX: number, globalY: number): void =>
          this.showBookmarkActions(bookmark, globalX, globalY)
      })
        .position({ x: this.readerFloatingBarLeft(), y: '100%' })
        .translate({ y: -(this.readerTocPanelHeight() + this.readerFloatingPanelBottomInset()) })
        .transition(this.readerPanelTransition())

      if (!this.supportsReaderImmersiveMaterial()) {
        Row() {
          this.readerFloatingIconMenuItem($r('sys.symbol.list_bullet'), true, () => {
            this.tocPanelController.showTocTab();
          })
          this.readerFloatingIconMenuItem($r('sys.symbol.gearshape'), false, () => {
            this.showToc = false;
            this.openSettingsPanel();
          })
          this.readerFloatingIconMenuItem($r('sys.symbol.textformat'), false, () => {
            this.showToc = false;
            this.openTypographySettingsPanel();
          })
          this.readerFloatingDayNightMenuItem()
        }
        .width(this.readerFloatingBarWidth())
        .height(56)
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
        .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
        .backgroundColor(this.readerGlassPanelColor())
        .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
        .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
        .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
        .position({ x: this.readerFloatingBarLeft(), y: '100%' })
        .translate({ y: -70 })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  readerActionMenu() {
    Column() {
      if (this.readerSourceNeedsLogin() || this.readerCanRetry() || !this.isReaderComicModeActive()) {
        this.readerActionMenuItem(
          $r('sys.symbol.bookmark'),
          this.isCurrentPageBookmarked() ? '删除书签' : '添加书签',
          () => this.toggleCurrentPageBookmark(),
          true,
          true
        )
      }
      if (this.book && !LocalBookService.isLocalBook(this.book)) {
        this.readerActionMenuItem(
          $r('sys.symbol.download'),
          '缓存',
          () => this.openReaderCacheDialog()
        )
      }
      if (!this.isReaderComicModeActive()) {
        this.readerActionMenuItem(
          this.isTtsSpeaking && !this.isTtsPaused ? $r('sys.symbol.pause') : $r('sys.symbol.play'),
          this.isTtsSpeaking ? (this.isTtsPaused ? '继续朗读' : '暂停朗读') : '开始朗读',
          () => this.toggleTtsReading()
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
      if (!this.isReaderComicModeActive()) {
        this.readerActionMenuItem(
          $r('sys.symbol.gearshape'),
          '阅读设置',
          () => this.openSettingsPanel()
        )
        this.readerActionMenuItem(
          $r('sys.symbol.speaker_wave_3'),
          '朗读设置',
          () => this.openTtsSettingsPanel(),
          true,
          true
        )
      }
      if (this.canSelectTxtCharset()) {
        this.readerActionMenuItem(
          $r('sys.symbol.textformat'),
          `字符编码 · ${this.txtCharsetMenuLabel()}`,
          () => this.openTxtCharsetDialog()
        )
      }
      this.readerActionMenuItem(
        this.isReaderComicModeActive() ? $r('sys.symbol.book') : $r('sys.symbol.rectangle_3_group'),
        this.isReaderComicModeActive() ? '切换为普通阅读' : '切换为漫画阅读',
        () => this.toggleReaderComicReadingMode()
      )
      this.readerActionMenuItem(
        $r('sys.symbol.square_grid_2x2'),
        '布局元素设置',
        () => this.openLayoutElementSettings()
      )
      this.readerActionMenuItem(
        $r('sys.symbol.arrow_left_arrow_right'),
        '替换净化配置',
        () => this.openCurrentReaderReplaceRules(),
        true,
        false
      )
    }
    .width(220)
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
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
      Row({ space: AppSpacing.LG }) {
        SymbolGlyph(icon)
          .fontSize(21)
          .fontColor([this.getTextColor()])
          .width(24)

        Text(label)
          .fontSize(AppFontSize.BODY_LARGE)
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
          .margin({ left: 46, right: AppSpacing.MD })
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

  onSystemDialogFlagChanged(): void {
    if (!this.showTxtCharsetDialog) this.txtCharsetDialogSession.close(this.getUIContext());
    if (!this.showReaderCacheDialog) this.readerCacheDialogSession.close(this.getUIContext());
    if (!this.showReaderChapterCacheDialog) this.chapterCacheDialogSession.close(this.getUIContext());
    if (!this.showTapZoneSettings) this.tapZoneDialogSession.close(this.getUIContext());
  }

  presentTapZoneSettings(): void {
    this.showTapZoneSettings = true;
    this.tapZoneDialogSession.open(this.getUIContext(), (): void => {
      this.tapZoneSettingsContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.isReaderThemeDark()),
      warnTag: '显示点击区域设置弹窗失败:'
    });
  }

  @Builder
  tapZoneSettingsContent() {
    TapZoneSettingsDialogContent({
      onDone: (): void => {
        this.showTapZoneSettings = false;
        this.tapZoneDialogSession.close(this.getUIContext());
      }
    })
  }

  async openChangeSourceDialog(): Promise<void> {
    if (!this.book || !this.book.name) {
      HdsFeedback.showToast('当前书籍信息不完整');
      return;
    }
    this.showMenu = false;
    this.showToc = false;
    this.showSettings = false;
    this.showChangeSourceDialog = true;
  }

  @Builder
  readerCacheDialogContent(chapterMode: boolean) {
    ReaderCacheDialogContent({
      chapterMode: chapterMode,
      book: this.book,
      controller: this.fullTextCacheController(),
      onStartFullTextCache: (): void => this.startFullTextCache(),
      onOpenChapterMode: (): void => this.openReaderChapterCacheDialog(),
      onClose: (): void => this.closeReaderCacheDialog(),
      onChaptersChanged: (chapters: BookChapter[]): void => {
        this.chapters = chapters;
      }
    })
  }

  openLayoutElementSettings(): void {
    this.showReaderActionMenu = false;
    this.showLayoutElementSettings = true;
  }

  canSelectTxtCharset(): boolean {
    const currentBook = this.book;
    return currentBook !== null && LocalBookService.isLocalBook(currentBook) &&
      currentBook.type === LocalBookService.TYPE_TXT;
  }

  txtCharsetMenuLabel(): string {
    if (!this.book) return '自动';
    const charsetOverride = LocalBookService.getTxtCharsetOverride(this.book);
    return charsetOverride ? ReaderTxtCharsets.label(charsetOverride) : '自动';
  }

  openTxtCharsetDialog(): void {
    if (!this.canSelectTxtCharset()) return;
    this.showReaderActionMenu = false;
    this.showTxtCharsetDialog = true;
    this.txtCharsetDialogSession.open(this.getUIContext(), (): void => {
      this.readerTxtCharsetDialogContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示字符编码弹窗失败:'
    });
  }

  async applyTxtCharsetSelection(selectedCharset: string): Promise<void> {
    if (!this.book || !this.canSelectTxtCharset()) return;
    const targetBook: Book = this.book;
    if (selectedCharset === LocalBookService.getTxtCharsetOverride(targetBook)) {
      this.showTxtCharsetDialog = false;
      return;
    }
    try {
      await this.saveReadingProgress();
      this.stopTtsReading();
      await LocalBookService.setTxtCharsetOverride(getContext(this), targetBook, selectedCharset);
      this.showTxtCharsetDialog = false;
      this.showMenu = false;
      await this.loadBook();
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      const applied = selectedCharset ? ReaderTxtCharsets.label(selectedCharset) :
        `自动识别（${ReaderTxtCharsets.label(this.book?.charset || '')}）`;
      HdsFeedback.showToast(`已使用 ${applied} 重新解析`);
    } catch (e) {
      console.error('切换 TXT 字符编码失败:', e);
      HdsFeedback.showToast('切换字符编码失败，请尝试其他编码');
    }
  }

  @Builder
  readerTxtCharsetDialogContent() {
    ReaderTxtCharsetDialogContent({
      selectedCharset: LocalBookService.getTxtCharsetOverride(this.book),
      parsedCharset: this.book?.charset || '',
      listHeight: Math.min(440, Math.max(160, this.pageViewHeight - 190)),
      onApply: (charset: string): Promise<void> => this.applyTxtCharsetSelection(charset),
      onClose: (): void => {
        this.showTxtCharsetDialog = false;
      },
      onApplyingChanged: (applying: boolean): void => {
        this.txtCharsetApplying = applying;
      }
    })
  }

  openCurrentReaderReplaceRules(): void {
    this.prepareReaderReplaceRulesContext();
    this.returningFromReaderReplaceRules = true;
    this.hideReaderPanels();
    router.pushUrl({ url: 'pages/ReaderReplaceRules', params: { previewCurrentChapter: 'true' } });
  }

  async openCurrentBookDetail(): Promise<void> {
    if (!this.book || this.openingBookDetail) return;
    this.openingBookDetail = true;
    try {
      await this.flushReadingProgressCheckpoint();
      const book = this.book;
      this.hideReaderPanels();
      await router.pushUrl({
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
          readerBookUrl: book.bookUrl,
          promptAddToShelfOnBack: 'false'
        }
      });
    } catch (error) {
      console.error('打开书籍详情失败:', error);
      HdsFeedback.showToast('打开书籍详情失败');
    } finally {
      this.openingBookDetail = false;
    }
  }

  prepareReaderReplaceRulesContext(): void {
    const chapter = this.chapters.length > 0 ?
      this.chapters[this.clampChapterIndex(this.currentChapterIndex)] : null;
    const rawTitle = chapter ? this.cleanChapterTitle(chapter.title || '') : '';
    const cached = this.chapters.length > 0 ?
      this.readerEngine().getCachedContent(this.currentChapterIndex) : '';
    const rawContent = cached || this.content || '';
    AppStorage.setOrCreate('readerReplacePreviewTitle', rawTitle);
    AppStorage.setOrCreate('readerReplacePreviewContent', rawContent.substring(0, 20000));
    AppStorage.setOrCreate('readerReplacePreviewBookName', this.book?.name || '');
    AppStorage.setOrCreate('readerReplacePreviewBookAuthor', this.book?.author || '');
    AppStorage.setOrCreate('readerReplacePreviewBookOriginName', this.book?.originName || '');
    AppStorage.setOrCreate('readerReplacePreviewBookOrigin', this.book?.origin || '');
    AppStorage.setOrCreate('readerReplacePreviewBookUrl', this.book?.bookUrl || this.bookUrl);
  }

  openReaderReplaceRuleWithSelection(selectedText: string): void {
    // 选中内容常带首尾空白与换行，作为字面匹配规则前先去掉，需要精确空白时可在编辑器里手动改回。
    const pattern = (selectedText || '').trim();
    if (!pattern) return;
    this.prepareReaderReplaceRulesContext();
    AppStorage.setOrCreate('readerReplaceRulePrefillPattern', pattern);
    this.returningFromReaderReplaceRules = true;
    this.hideReaderPanels();
    router.pushUrl({
      url: 'pages/ReaderReplaceRules',
      params: { previewCurrentChapter: 'true', prefillReplacePattern: 'true' }
    });
  }

  @Builder
  readerLayoutElementSettingsDialog() {
    ReaderLayoutElementSettingsPanel({
      dark: this.isReaderThemeDark(),
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      accentColor: this.accentColor(),
      panelColor: this.readerGlassPanelColor(),
      panelBorderColor: this.readerGlassBorderColor(),
      panelShadowColor: this.readerGlassShadowColor(),
      panelWidth: Math.max(1, Math.min(420, this.pageViewWidth - 36)),
      onClose: (): void => {
        this.showLayoutElementSettings = false;
      },
      onChapterQuickJumpChanged: (enabled: boolean): void => {
        if (!enabled) this.resetMenuChapterPreview();
      }
    })
  }

  currentReaderSource(): BookSource | null {
    return this.readerEngine().source;
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

  openReaderSourceLogin(): void {
    const source = this.currentReaderSource();
    if (!source || !this.readerSourceNeedsLogin()) return;
    this.showReaderActionMenu = false;
    this.showMenu = false;
    if (String(source.loginUi || '').trim()) {
      router.pushUrl({
        url: 'pages/BookSource',
        params: { openLoginSourceUrl: source.bookSourceUrl }
      });
      return;
    }
    const loginEntryUrl = this.verificationUrl || VerificationSupport.resolveBookSourceLoginUrl(source) ||
      VerificationSupport.pickVerificationUrl(source, source.bookSourceUrl);
    if (!loginEntryUrl || !/^https?:\/\//i.test(loginEntryUrl)) {
      HdsFeedback.showToast('未找到可用的网页登录地址，请检查书源登录配置');
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
        iconOffsetX: 0,
        iconColor: this.readerControlIconColor(),
        darkMode: this.isReaderThemeDark(),
        buttonSize: 48,
        containerWidth: 48,
        containerHeight: 48,
        startInset: 0,
        compactLayout: true,
        accessibilityLabel: this.isTtsSpeaking ? '展开朗读控制' : '开始朗读',
        onBack: () => {
          this.openTtsQuickPlayer();
        }
      })

      if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
        Circle()
          .width(9)
          .height(9)
          .fill(this.accentColor())
          .stroke(this.readerContentLayerColor())
          .strokeWidth(2)
          .position({ x: 38, y: 3 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(48)
    .height(48)
    .position({ x: this.readerTtsQuickActionLeft(), y: '100%' })
    .translate({
      y: -(this.readerBottomMenuOverlayHeight() + 62)
    })
  }

  async openTtsQuickPlayer(): Promise<void> {
    if (this.isReaderComicModeActive()) return;
    // The quick-action tap is above the page-turn layer. Consume its trailing click and discard
    // page turns queued while the menu was animating, otherwise they can execute many seconds
    // later between TTS focus turns and move the reader to an older chapter.
    this.suppressReaderTapClick = true;
    this.clearQueuedReaderPageTurns();
    this.showMenu = false;
    this.showToc = false;
    this.showSettings = false;
    animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.showTtsQuickPlayer = true;
    });
    this.loadTtsSettingsAndVoices();
    if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking()) {
      await this.startTtsReadingFromCurrentPosition(true);
    }
  }

  shouldShowTtsMiniPlayer(): boolean {
    return this.showMenu && !this.showTtsQuickPlayer && !this.isReaderComicModeActive() &&
      (this.isTtsSpeaking || this.ttsReader.isSpeaking()) && !this.shouldBlockReaderInteraction();
  }

  shouldShowGlobalTtsMiniPlayer(): boolean {
    return this.showMenu && this.globalTtsActive && !this.showGlobalTtsQuickPlayer &&
      !ReaderTtsFloatingSession.isOwner(this.ttsFloatingSessionOwnerId) &&
      !this.isReaderComicModeActive() && !this.shouldBlockReaderInteraction();
  }

  closeTtsQuickPlayer(): void {
    this.showGlobalTtsCatalog = false;
    animateTo({ duration: 190, curve: Curve.EaseIn }, () => {
      this.showTtsQuickPlayer = false;
    });
  }

  openGlobalTtsQuickPlayer(): void {
    animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.showGlobalTtsQuickPlayer = true;
    });
  }

  closeGlobalTtsQuickPlayer(): void {
    this.showGlobalTtsCatalog = false;
    animateTo({ duration: 190, curve: Curve.EaseIn }, () => {
      this.showGlobalTtsQuickPlayer = false;
    });
  }

  openGlobalTtsCatalog(): void {
    const titles = ReaderTtsFloatingSession.catalogTitles();
    if (titles.length === 0) {
      HdsFeedback.showToast('暂未获取到听书目录');
      return;
    }
    this.globalTtsCatalogSource.replace(this.globalTtsCatalogReverseOrder ? titles.slice().reverse() : titles);
    // Re-snapshot at open time so the cache chip reflects chapters cached while this
    // session has been running, instead of the state at session publish time.
    ReaderTtsFloatingSession.updateCatalogCachedFlags(
      this.ttsFloatingSessionOwnerId, this.readerChapterCachedFlags());
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

  closeGlobalTtsCatalog(): void {
    animateTo({ duration: 210, curve: Curve.EaseIn }, () => {
      this.showGlobalTtsCatalog = false;
    });
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

  /**
   * The chip is read from the published session catalog so that the catalog opened
   * from the shelf renders identically to the one opened inside the reader.
   */
  isGlobalTtsCatalogChapterCached(displayIndex: number): boolean {
    return ReaderTtsFloatingSession.catalogCachedFlag(this.globalTtsCatalogCanonicalIndex(displayIndex));
  }

  /** Canonical-order cache flags published with the floating TTS session catalog. */
  readerChapterCachedFlags(): boolean[] {
    const flags: boolean[] = [];
    for (let index = 0; index < this.chapters.length; index++) {
      flags.push(this.book !== null && this.book.origin !== 'local' &&
        this.chapters[index].cacheDate > 0);
    }
    return flags;
  }

  toggleGlobalTtsCatalogOrder(): void {
    this.globalTtsCatalogReverseOrder = !this.globalTtsCatalogReverseOrder;
    const titles = ReaderTtsFloatingSession.catalogTitles();
    this.globalTtsCatalogSource.replace(this.globalTtsCatalogReverseOrder ? titles.slice().reverse() : titles);
    setTimeout(() => {
      if (!this.showGlobalTtsCatalog) return;
      try {
        this.globalTtsCatalogScroller.scrollToIndex(
          this.globalTtsCatalogDisplayIndex(ReaderTtsFloatingSession.catalogIndex()), false, ScrollAlign.CENTER);
      } catch (_) {}
    }, 0);
  }

  ttsMiniPlayerLeft(): number {
    return this.clampTtsMiniPlayerPositionX(this.ttsMiniPlayerPositionX);
  }

  ttsMiniPlayerTop(): number {
    const viewportHeight = this.pageViewHeight > 0 ? this.pageViewHeight : 720;
    const capsuleHeight = ReaderTtsCapsule.HEIGHT;
    const menuGap = 8;
    // The capsule is only shown while the reader menu is open. Keep its default anchor above the
    // whole bottom menu (including the optional chapter quick-jump track), instead of merely
    // clearing the system navigation bar. A non-negative stored position is user-controlled and
    // remains untouched.
    const defaultTop = viewportHeight - this.readerBottomMenuOverlayHeight() - capsuleHeight - menuGap;
    return this.clampTtsMiniPlayerPositionY(this.ttsMiniPlayerPositionY < 0 ?
      defaultTop : this.ttsMiniPlayerPositionY);
  }

  clampTtsMiniPlayerPositionX(position: number): number {
    const viewportWidth = this.pageViewWidth > 0 ? this.pageViewWidth : 360;
    const capsuleWidth = ReaderTtsCapsule.WIDTH;
    const edgeInset = 8;
    const minLeft = edgeInset;
    const maxLeft = Math.max(minLeft, viewportWidth - capsuleWidth - edgeInset);
    return Math.max(minLeft, Math.min(position, maxLeft));
  }

  clampTtsMiniPlayerPositionY(position: number): number {
    const viewportHeight = this.pageViewHeight > 0 ? this.pageViewHeight : 720;
    const minTop = this.getReaderTopSafePadding() + 8;
    const maxTop = Math.max(minTop, viewportHeight - this.navBarHeight - 54);
    return Math.max(minTop, Math.min(position, maxTop));
  }

  ttsMiniPlayerTransition(): TransitionEffect {
    const appear = TransitionEffect.scale({ x: 0.84, y: 0.84, centerX: '50%', centerY: '50%' })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 240, curve: Curve.Friction });
    const disappear = TransitionEffect.scale({ x: 0.9, y: 0.9, centerX: '50%', centerY: '50%' })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 170, curve: Curve.EaseIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  @Builder
  ttsMiniPlayer() {
    ReaderTtsCapsule({
      title: this.isTtsPaused ? '已暂停' : '朗读中',
      subtitle: `${this.currentChapterIndex + 1}/${Math.max(1, this.chapters.length)}章`,
      paused: this.isTtsPaused,
      playbackKey: `tts_capsule_playback_${this.isTtsSpeaking}_${this.isTtsPaused}`,
      panelColor: this.readerGlassPanelColor(),
      panelBorderColor: this.readerGlassBorderColor(),
      panelShadowColor: this.readerGlassShadowColor(),
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      accentColor: this.accentColor(),
      onCapsuleDragStart: (): void => this.beginTtsMiniPlayerDrag(),
      onCapsuleDragMove: (offsetX: number, offsetY: number): void => this.moveTtsMiniPlayer(offsetX, offsetY),
      onOpen: (): void => {
        this.openTtsQuickPlayer();
      },
      onToggle: (): void => {
        this.toggleTtsReading();
      },
      onClose: (): void => {
        this.stopTtsReading();
      }
    })
      .position({ x: 0, y: 0 })
      .translate({
        x: this.ttsMiniPlayerLeft(),
        y: this.ttsMiniPlayerTop()
      })
      .transition(this.ttsMiniPlayerTransition())
  }

  @Builder
  globalTtsMiniPlayer() {
    ReaderTtsCapsule({
      title: this.globalTtsPaused ? '已暂停' : (this.globalTtsMode === 'audio' ? '听书中' : '朗读中'),
      subtitle: this.globalTtsChapterProgress || (this.globalTtsMode === 'audio' ? '后台听书' : '后台朗读'),
      paused: this.globalTtsPaused,
      playbackKey: `global_tts_capsule_playback_${this.globalTtsPaused}`,
      panelColor: this.readerGlassPanelColor(),
      panelBorderColor: this.readerGlassBorderColor(),
      panelShadowColor: this.readerGlassShadowColor(),
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      accentColor: this.accentColor(),
      onCapsuleDragStart: (): void => this.beginTtsMiniPlayerDrag(),
      onCapsuleDragMove: (offsetX: number, offsetY: number): void => this.moveTtsMiniPlayer(offsetX, offsetY),
      onOpen: (): void => this.openGlobalTtsQuickPlayer(),
      onToggle: (): void => {
        ReaderTtsFloatingSession.toggle();
      },
      onClose: (): void => {
        this.closeGlobalTtsQuickPlayer();
        ReaderTtsFloatingSession.stop();
      }
    })
      .position({ x: 0, y: 0 })
      .translate({
        x: this.ttsMiniPlayerLeft(),
        y: this.ttsMiniPlayerTop()
      })
      .transition(this.ttsMiniPlayerTransition())
  }

  beginTtsMiniPlayerDrag(): void {
    this.ttsMiniPlayerDragOriginX = this.ttsMiniPlayerLeft();
    this.ttsMiniPlayerDragOriginY = this.ttsMiniPlayerTop();
  }

  moveTtsMiniPlayer(offsetX: number, offsetY: number): void {
    this.ttsMiniPlayerPositionX = this.clampTtsMiniPlayerPositionX(this.ttsMiniPlayerDragOriginX + offsetX);
    this.ttsMiniPlayerPositionY = this.clampTtsMiniPlayerPositionY(this.ttsMiniPlayerDragOriginY + offsetY);
  }

  // The panel wears the reader's colours, so the app theme's artwork only fits
  // while the reader itself is on the "应用主题" scheme.
  ttsPanelBackgroundThemeId(): string {
    return this.currentReaderThemeIndex() === ReaderThemeHelper.APP_THEME_INDEX ?
      ThemeRuntime.ttsPanelThemeId(this.appDarkMode) : '';
  }

  @Builder
  sharedTtsPlayerPanel(localOwner: boolean) {
    ReaderTtsPlayerPanel({
      darkMode: this.isReaderThemeDark(),
      accentColor: this.accentColor(),
      playButtonColor: this.buttonColor(),
      primaryTextColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      panelColor: this.readerGlassPanelColor(),
      backgroundThemeId: this.ttsPanelBackgroundThemeId(),
      topInset: this.statusBarSafeHeight,
      bottomInset: this.navBarHeight,
      viewportHeight: this.pageViewHeight > 0 ? this.pageViewHeight : 720,
      onClose: () => localOwner ? this.closeTtsQuickPlayer() : this.closeGlobalTtsQuickPlayer(),
      onOpenCatalog: () => this.openGlobalTtsCatalog()
    })
  }

  @Builder
  globalTtsCatalogOverlay() {
    TtsCatalogSheet({
      bookUrl: this.bookUrl,
      darkMode: this.isReaderThemeDark(),
      accentColor: this.accentColor(),
      primaryTextColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      controlIconColor: this.readerControlIconColor(),
      panelColor: this.readerGlassPanelColor(),
      bookName: this.book?.name || '',
      bookInitial: this.getTocBookInitial(),
      cover: this.getTocCover(),
      bookSubtitle: this.book?.author || '',
      count: ReaderTtsFloatingSession.catalogCount(),
      currentDisplayIndex: this.globalTtsCatalogDisplayIndex(ReaderTtsFloatingSession.catalogIndex()),
      reverseOrder: this.globalTtsCatalogReverseOrder,
      progressText: `${ReaderTtsFloatingSession.catalogIndex() + 1} / ` +
        `${ReaderTtsFloatingSession.catalogCount()}`,
      bottomInset: this.navBarHeight,
      viewportHeight: this.pageViewHeight,
      zIndexValue: 90,
      scroller: this.globalTtsCatalogScroller,
      source: this.globalTtsCatalogSource,
      isCached: (displayIndex: number): boolean => this.isGlobalTtsCatalogChapterCached(displayIndex),
      onToggleOrder: () => this.toggleGlobalTtsCatalogOrder(),
      onSelect: (displayIndex: number) => this.selectGlobalTtsCatalog(displayIndex),
      onClose: () => this.closeGlobalTtsCatalog()
    })
  }

  ttsCurrentSentence(): string {
    if (this.ttsHighlightStart < 0 || this.ttsHighlightEnd <= this.ttsHighlightStart || !this.ttsDisplayText) {
      return '';
    }
    const source = this.ttsPanelOffsetSource();
    return this.cleanTtsPanelSlice(source.substring(this.ttsHighlightStart, this.ttsHighlightEnd));
  }

  ttsQuickSentencePreview(): string {
    const source = this.cleanTtsPanelSlice(this.ttsPanelOffsetSource());
    if (source) {
      return source;
    }
    const sentence = this.ttsCurrentSentence();
    const fallback = this.cleanTtsPanelSlice(this.ttsOffsetSanitizedText(this.content)).substring(0, 3000);
    return sentence || fallback || '正在准备当前页的朗读内容…';
  }

  ttsPanelTextBefore(): string {
    const source = this.ttsPanelOffsetSource();
    if (this.ttsHighlightStart <= 0) return '';
    return this.cleanTtsPanelSlice(
      source.substring(Math.max(0, this.ttsHighlightStart - 600), this.ttsHighlightStart));
  }

  ttsPanelTextAfter(): string {
    const source = this.ttsPanelOffsetSource();
    const start = this.ttsHighlightEnd > this.ttsHighlightStart ? this.ttsHighlightEnd : 0;
    return this.cleanTtsPanelSlice(source.substring(start, Math.min(source.length, start + 900)));
  }

  ttsPanelOffsetSource(): string {
    return this.ttsOffsetSanitizedText(this.ttsDisplayText || this.currentPageText || '');
  }

  ttsOffsetSanitizedText(text: string): string {
    let source = ReaderActionMarker.strip(LocalBookService.stripEpubImageMarkers(text || '', true), true);
    for (const prefix of [ReaderActionMarker.PREFIX, ReaderActionMarker.LEGACY_PREFIX,
      ReaderActionMarker.ORIGINAL_PREFIX]) {
      let start = source.indexOf(prefix);
      while (start >= 0) {
        const lineEnd = source.indexOf('\n', start);
        const end = lineEnd >= 0 ? lineEnd : source.length;
        source = `${source.substring(0, start)}${' '.repeat(end - start)}${source.substring(end)}`;
        start = source.indexOf(prefix, end);
      }
    }
    return source;
  }

  cleanTtsPanelSlice(text: string): string {
    return (text || '')
      .replace(/[ \t]{2,}/g, ' ')
      .replace(/[ \t]*\n[ \t]*/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  ttsPanelFollowingText(): string {
    const before = this.ttsPanelTextBefore();
    const current = this.ttsCurrentSentence();
    const after = this.ttsPanelTextAfter();
    return [before, current, after].filter((value: string): boolean => !!value).join('\n');
  }

  ttsQuickProgress(): number {
    const chapterCount = Math.max(1, this.chapters.length);
    const pageCount = Math.max(1, this.contentPages.length);
    return Math.max(0, Math.min(100,
      ((this.currentChapterIndex + (this.currentPageIndex + 1) / pageCount) / chapterCount) * 100));
  }

  showBookmarkActions(bookmark: Bookmark, globalX: number, globalY: number): void {
    this.bookmarkActionMenuX = globalX;
    this.bookmarkActionMenuY = globalY;
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
            this.tocPanelController.enterBookmarkMultiSelect(bookmarkId);
          }
        })
        this.bookmarkContextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
          if (this.pendingBookmarkAction) {
            const bookmark = this.pendingBookmarkAction;
            this.closeBookmarkActionMenu();
            this.tocPanelController.deleteBookmark(bookmark);
          }
        })
      }
      .width(148)
      .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
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
    Row({ space: AppSpacing.LG }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([color])
        .width(26)
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(color)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  getTocCover(): ResourceStr {
    return BookCoverResolver.first(this.book, this.appDarkMode);
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

  readerPreparedContentKey(content: string, chapterIndex: number): string {
    return `${chapterIndex}_${content.length}_${this.hashText(content)}_${this.readerReplaceRules.length}_` +
      `${this.readerReplaceRulesUpdateTime}`;
  }

  getPreparedReaderContent(content: string, chapterIndex: number): string {
    return this.readerPreparedContentCache.get(this.readerPreparedContentKey(content, chapterIndex)) || '';
  }

  // Whether the raw chapter body differs from what pagination consumes. Synchronous callers must not
  // paginate the raw body in that case: its cache key would never match the prepared chapter.
  readerContentNeedsPreparation(content: string): boolean {
    return ReaderContentPreprocessor.hasActiveContentRules(this.readerReplaceRules) ||
      (!this.isReaderComicModeActive() && ReaderImageSizeResolver.needsSizes(content));
  }

  async prepareReaderContentRules(content: string, chapterIndex: number): Promise<string> {
    if (!content) return '';
    const key = this.readerPreparedContentKey(content, chapterIndex);
    const cached = this.readerPreparedContentCache.get(key);
    if (cached !== undefined) return cached;
    const startedAt = Date.now();
    const replaced = ReaderActionMarker.limit(
      await ReaderContentPreprocessor.apply(content, this.readerReplaceRules, this.book));
    // Comic chapters size their images from the decoded bitmap; probing every file up front only delays opening.
    const processed = this.isReaderComicModeActive() ? replaced : await ReaderImageSizeResolver.annotate(replaced);
    const elapsedMs = Math.max(0, Date.now() - startedAt);
    if (elapsedMs >= CooperativeScheduler.DANGEROUS_OPERATION_MS) {
      console.info(`[ReaderPreprocessor] worker elapsed=${elapsedMs}ms input=${content.length}`);
    }
    this.readerPreparedContentCache.set(key, processed);
    while (this.readerPreparedContentCache.size > 8) {
      const oldestKey = this.readerPreparedContentCache.keys().next().value as string | undefined;
      if (!oldestKey) break;
      this.readerPreparedContentCache.delete(oldestKey);
    }
    // Do not begin native paragraph measurement in the same event-loop turn that publishes a
    // potentially large TaskPool result.
    await CooperativeScheduler.yieldToEventLoop();
    return processed;
  }

  onReaderReplaceRulesChanged(): void {
    if (this.readerEntryInitializing || !this.readerPageVisible) {
      return;
    }
    this.reloadReaderReplaceRules(true).catch((error: Error) => {
      console.warn('更新替换净化规则失败:', error);
    });
  }

  async reloadReaderReplaceRules(repaginate: boolean): Promise<void> {
    const nextRules = await ReaderReplaceRuleStore.load(getContext(this), true);
    const rulesChanged = JSON.stringify(nextRules) !== JSON.stringify(this.readerReplaceRules);
    this.readerReplaceRules = nextRules;
    if (!rulesChanged) {
      return;
    }
    this.readerPaginationCache.clear();
    this.readerPreparedContentCache.clear();
    this.adjacentPaginationPreloadSerial++;
    this.pageTurnPreviewKey = '';
    this.pageTurnPreviewLoadingKey = '';
    if (!repaginate || !this.book || this.chapters.length === 0) {
      return;
    }
    this.pendingRestorePageIndex = Math.max(this.pendingRestorePageIndex, this.currentPageIndex);
    const raw = this.readerEngine().getCachedContent(this.currentChapterIndex);
    if (!raw) {
      return;
    }
    const processed = await this.prepareReaderContentRules(raw, this.currentChapterIndex);
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

  getReaderInfoBarConfig(): ReaderInfoBarConfig {
    if (this.readerInfoBarConfigCacheRaw !== this.readerInfoBarConfigRaw) {
      this.readerInfoBarConfigCacheRaw = this.readerInfoBarConfigRaw;
      this.readerInfoBarConfigCache = ReaderInfoBarConfig.parse(this.readerInfoBarConfigRaw) ??
        new ReaderInfoBarConfig();
    }
    return this.readerInfoBarConfigCache;
  }

  isReaderHeaderVisible(): boolean {
    return this.readerHeaderEnabled && this.getReaderInfoBarConfig().headerVisible() &&
      !this.isReaderComicModeActive();
  }

  getReaderInfoBarContext(): ReaderInfoBarContext {
    const context = new ReaderInfoBarContext();
    context.bookName = this.book?.name || '';
    context.author = this.book?.author || '';
    context.chapterCount = this.chapters.length;
    context.chapterIndex = this.clampChapterIndex(this.currentChapterIndex);
    context.chapterTitle = this.getChapterTitle(context.chapterIndex);
    context.pageIndex = this.currentPageIndex;
    context.pageCount = this.contentPages.length;
    context.doublePage = this.isLandscapeDoublePageActive();
    context.timeText = this.readerInfoTimeText;
    context.batteryPercent = this.readerInfoBatteryPercent;
    return context;
  }

  getReaderInfoSlotText(item: string): string {
    return ReaderInfoBarText.leading(item, this.getReaderInfoBarContext());
  }

  getReaderInfoSlotBattery(item: string): number {
    return ReaderInfoBarText.battery(item, this.getReaderInfoBarContext());
  }

  getReaderInfoProgressValue(): number {
    const context = this.getReaderInfoBarContext();
    return this.getReaderInfoBarConfig().progressScope === ReaderInfoProgressBar.SCOPE_BOOK ?
      ReaderInfoBarText.bookPercent(context) : ReaderInfoBarText.chapterPercent(context);
  }

  getReaderInfoBarSidePadding(header: boolean, left: boolean): number {
    return this.getReaderInfoBarConfig().sidePadding(header, left,
      this.getEffectiveReaderMarginLeft(), this.getEffectiveReaderMarginRight(), this.pageViewWidth);
  }

  /** 时间和电量只在阅读页可见、且有槽位用到时才每分钟刷新。 */
  syncReaderInfoBarClock(): void {
    const needed = this.readerPageVisible &&
      (this.getReaderInfoBarConfig().usesClock(this.readerHeaderEnabled, this.readerFooterEnabled) ||
        (this.isReaderComicModeActive() && this.readerComicSettings.infoBar));
    if (!needed) {
      this.readerInfoBarClock?.stop();
      return;
    }
    if (!this.readerInfoBarClock) {
      this.readerInfoBarClock = new ReaderInfoBarClock((): void => {
        this.readerInfoTimeText = ReaderInfoBarClock.timeText();
        this.readerInfoBatteryPercent = ReaderInfoBarClock.batteryPercent();
      });
    }
    this.readerInfoBarClock.start();
  }

  currentReaderInfoBarLayoutIdentity(): string {
    return `${this.readerHeaderEnabled}_${this.readerFooterEnabled}_${this.getReaderInfoBarConfig().layoutIdentity()}`;
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
      this.pageViewWidth > this.pageViewHeight &&
      !this.isReaderContinuousScrollSurfaceActive();
  }

  initializeReaderComicMode(): void {
    const manualMode = this.book?.getVariable('readerComicManualMode') || '';
    const autoDetected = this.book?.getVariable('readerComicAutoDetected') === '1';
    this.readerComicMode = manualMode === 'comic' ||
      (manualMode !== 'text' && (autoDetected || this.readerSourceIndicatesComic()));
    this.syncReaderImageDeferral();
    const bookMode = this.book?.getVariable('readerComicReadingMode') || '';
    this.readerComicBookMode = bookMode ? ReaderComicMode.normalize(bookMode) : '';
    this.readerComicTextConvert = this.book?.getVariable('readerComicTextConvert') === 't2s';
    this.readerComicZoomScale = 1;
    if (this.readerComicMode) {
      this.stopTtsReading();
      this.showSettings = false;
    }
    this.enterReaderImmersive();
    this.syncReaderInfoBarClock();
  }

  readerSourceIndicatesComic(): boolean {
    const source = this.currentReaderSource();
    if (BookTypeSupport.isImage(this.book)) {
      return true;
    }
    // Legado's "full" imageStyle only controls how inline illustrations fill the
    // reader width. Text sources such as 神魔小说 use it as well, so it must not
    // switch the whole book to the continuous comic renderer.
    if (source && (source.bookSourceType === 2 ||
      /^(?:comic|manga|webtoon)$/i.test(source.contentRule?.imageStyle || ''))) {
      return true;
    }
    const bookIdentity = `${this.book?.kind || ''}\n${this.book?.customTag || ''}`;
    const sourceIdentity = source ? `${source.bookSourceGroup || ''}\n${source.bookSourceName || ''}` : '';
    return /漫画|漫話|条漫|條漫|コミック|comic|manga|manhua|webtoon/i.test(
      `${bookIdentity}\n${sourceIdentity}`);
  }

  detectReaderComicMode(_source: string): void {
    if (this.readerComicMode || !this.readerSourceIndicatesComic() ||
      this.book?.getVariable('readerComicManualMode') === 'text') return;
    this.readerComicMode = true;
    this.syncReaderImageDeferral();
    this.showSettings = false;
    this.stopTtsReading();
    this.enterReaderImmersive();
    this.syncReaderInfoBarClock();
  }

  toggleReaderComicReadingMode(): void {
    if (!this.book) return;
    const next = !this.isReaderComicModeActive();
    this.stopTtsReading();
    this.readerComicMode = next;
    this.syncReaderImageDeferral();
    this.book.putVariable('readerComicManualMode', next ? 'comic' : 'text');
    // 继续写入旧字段，兼容已有导入导出数据；实际判定优先读取手动模式字段。
    this.book.putVariable('readerComicMode', next ? '1' : '0');
    AppDatabase.getInstance().updateBook(this.book, false).catch((error: Error) => {
      console.warn('保存阅读模式失败:', error);
    });
    this.showReaderActionMenu = false;
    this.showSettings = false;
    this.resetSlidePageEffect();
    this.syncReaderComicPageDataSource();
    if (next) {
      this.scheduleReaderComicScrollRestore();
    }
    this.enterReaderImmersive();
    this.syncReaderInfoBarClock();
    HdsFeedback.showToast(next ? '已切换为漫画阅读' : '已切换为普通阅读');
    // 漫画模式下渐进加载的本章图片还没补完：普通阅读按本地图片排版，重新获取整章。
    if (!next && ReaderImageMarker.hasPending(this.content)) {
      this.refreshCurrentChapter(this.currentPageIndex, true).catch((error: Error) => {
        console.warn('切换普通阅读后重新获取本章失败:', error);
      });
    }
  }

  /** 漫画模式下正文图片渐进加载：章节先显示，图片逐张补上（见 ReadBookEngine.setReaderImagesDeferred）。 */
  syncReaderImageDeferral(): void {
    this.readerEngine().setReaderImagesDeferred(this.isReaderComicModeActive());
  }

  isReaderComicModeActive(): boolean {
    return this.readerComicMode;
  }

  isReaderNovelContinuousScrollModeActive(): boolean {
    return !this.isReaderComicModeActive() && this.readerPageTurnMode === 3;
  }

  isReaderContinuousScrollSurfaceActive(): boolean {
    return this.isReaderComicModeActive() || this.isReaderNovelContinuousScrollModeActive();
  }

  readerEffectivePageTurnMode(): number {
    return this.readerPageTurnMode;
  }

  comicBoundaryChapterSwipeDirection(offsetY: number): number {
    if (!this.isReaderContinuousScrollSurfaceActive() || this.readerComicChapterSwitching || Math.abs(offsetY) < 2) {
      return 0;
    }
    try {
      if (offsetY < 0 && this.currentChapterIndex < this.chapters.length - 1 &&
        this.readerComicScroller.isAtEnd()) {
        return 1;
      }
      if (offsetY > 0 && this.currentChapterIndex > 0 &&
        this.readerComicScroller.currentOffset().yOffset <= 1) {
        return -1;
      }
    } catch (error) {
      console.warn('判断漫画章节滚动边界失败:', error);
    }
    return 0;
  }

  beginReaderComicPan(): void {
    this.stopReaderComicScreenScroll();
    if (this.readerComicChapterSwitching) return;
    this.readerComicPanLastOffsetY = 0;
    this.readerComicPanMoved = false;
    this.readerComicBoundaryProbeNotUntil = 0;
    this.readerComicBoundaryPullOriginY = 0;
    this.resetReaderComicBoundaryFeedback(false);
  }

  updateReaderComicPan(event: GestureEvent): void {
    if (this.readerComicChapterSwitching) return;
    const previousOffsetY = this.readerComicPanLastOffsetY;
    const deltaY = event.offsetY - previousOffsetY;
    this.readerComicPanLastOffsetY = event.offsetY;
    if (Math.abs(event.offsetY) > 3) this.readerComicPanMoved = true;
    this.readerComicScroller.scrollBy(0, -deltaY);

    // 边界探测需要读取滚动器状态（同步原生调用）；已处于边界拉动状态时保持逐事件更新，
    // 否则每 24ms 探测一次即可。
    const now = Date.now();
    if (this.readerComicBoundaryDirection === 0 && now < this.readerComicBoundaryProbeNotUntil) {
      return;
    }
    this.readerComicBoundaryProbeNotUntil = now + 24;
    const direction = this.comicBoundaryChapterSwipeDirection(event.offsetY);
    if (direction === 0) {
      if (this.readerComicBoundaryDirection !== 0) this.resetReaderComicBoundaryFeedback(true);
      return;
    }
    if (direction !== this.readerComicBoundaryDirection) {
      this.readerComicBoundaryDirection = direction;
      this.readerComicBoundaryPullOriginY = previousOffsetY;
    }
    const distance = Math.min(88, Math.abs(event.offsetY - this.readerComicBoundaryPullOriginY));
    this.readerComicBoundaryPullDistance = distance;
    this.readerComicBoundaryReady = distance >= 48;
    this.readerComicChapterTransitionY = (direction < 0 ? 1 : -1) * Math.min(20, distance * 0.3);
    this.readerComicChapterTransitionOpacity = 1;
  }

  finishReaderComicPan(event: GestureEvent): void {
    if (this.readerComicChapterSwitching) return;
    const chapterDirection = this.readerComicBoundaryReady ? this.readerComicBoundaryDirection : 0;
    const hadBoundaryPull = this.readerComicBoundaryDirection !== 0;
    if (chapterDirection !== 0) {
      this.readerComicSuppressClickUntil = Date.now() + 360;
      this.switchComicBoundaryChapter(chapterDirection);
    } else {
      if (this.readerComicPanMoved && !hadBoundaryPull) {
        this.readerComicSuppressClickUntil = Date.now() + 220;
        this.readerComicScroller.fling(event.velocityY);
      }
      this.resetReaderComicBoundaryFeedback(true);
    }
    this.readerComicPanLastOffsetY = 0;
    this.readerComicPanMoved = false;
    this.readerComicBoundaryPullOriginY = 0;
  }

  cancelReaderComicPan(): void {
    this.readerComicPanLastOffsetY = 0;
    this.readerComicPanMoved = false;
    this.readerComicBoundaryPullOriginY = 0;
    this.resetReaderComicBoundaryFeedback(true);
  }

  resetReaderComicBoundaryFeedback(animated: boolean): void {
    this.readerComicBoundaryDirection = 0;
    this.readerComicBoundaryPullDistance = 0;
    this.readerComicBoundaryReady = false;
    if (this.readerComicChapterSwitching) return;
    if (animated) {
      animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
        this.readerComicChapterTransitionY = 0;
        this.readerComicChapterTransitionOpacity = 1;
      });
    } else {
      this.readerComicChapterTransitionY = 0;
      this.readerComicChapterTransitionOpacity = 1;
    }
  }

  readerComicBoundaryHintText(): string {
    const previous = this.readerComicBoundaryDirection < 0;
    if (this.readerComicChapterSwitching) return previous ? '正在加载上一章…' : '正在加载下一章…';
    if (this.readerComicBoundaryReady) return previous ? '松开加载上一章' : '松开加载下一章';
    return previous ? '下拉加载上一章' : '上滑加载下一章';
  }

  switchComicBoundaryChapter(direction: number): void {
    if (direction === 0 || this.readerComicChapterSwitching) return;
    this.runReaderComicChapterTransition(direction).catch((error: Error) => {
      console.error('滚动切换漫画章节失败:', error);
    });
  }

  async runReaderComicChapterTransition(direction: number): Promise<void> {
    if (direction === 0 || this.readerComicChapterSwitching) return;
    const startedAt = Date.now();
    const sourceChapterIndex = this.currentChapterIndex;
    // A manual chapter switch replaces the text the speech engine is still holding. Stop that session now and
    // read on from wherever the reader lands; a paused session simply ends. A session mirrored from the
    // floating player is moved instead of restarted.
    const mirroredTts = this.isMirroringActiveTtsForCurrentBook();
    const ownTtsActive = !mirroredTts && (this.isTtsSpeaking || this.ttsReader.isSpeaking());
    const resumeTtsAfterSwitch = ownTtsActive && !this.isTtsPaused;
    if (resumeTtsAfterSwitch) {
      this.stopTtsReaderForChapterSwitch();
    } else if (ownTtsActive) {
      this.stopTtsReading();
    }
    this.readerComicChapterSwitching = true;
    this.readerComicBoundaryDirection = direction;
    this.readerComicBoundaryPullDistance = Math.max(48, this.readerComicBoundaryPullDistance);
    this.readerComicBoundaryReady = true;
    animateTo({ duration: 90, curve: Curve.EaseIn }, () => {
      this.readerComicChapterTransitionY = direction > 0 ? -34 : 34;
      this.readerComicChapterTransitionOpacity = 0.18;
    });
    // Cached fetch, content preprocessing and pagination can run while the outgoing chapter
    // performs its short transition. Waiting for the animation first added a fixed stall to
    // every boundary switch even when the previous chapter tail was already prepared.
    const chapterLoad = direction > 0 ? this.loadNextChapter(false, false) :
      this.loadPrevChapter(true, false, false);
    await sleepMs(72);
    try {
      await chapterLoad;
      // loadContent publishes the first incremental V2 page before a deep/last-page restore has necessarily
      // reached its target. Keep the compact boundary hint (rather than exposing the full-screen restore panel)
      // until that authoritative target is ready. The common previous-chapter tail is completed synchronously
      // from the durable page boundaries below, so this normally resolves in the same frame.
      await this.waitForReaderComicBoundaryRestore();
      const switched = this.currentChapterIndex !== sourceChapterIndex;
      this.readerComicChapterTransitionY = switched ? (direction > 0 ? 28 : -28) :
        (direction > 0 ? -20 : 20);
      this.readerComicChapterTransitionOpacity = switched ? 0 : 0.35;
      await sleepMs(8);
      await this.runReaderAnimation(150, Curve.Friction, () => {
        this.readerComicChapterTransitionY = 0;
        this.readerComicChapterTransitionOpacity = 1;
      });
      console.info(`[ReaderBoundary] direction=${direction} switched=${switched} elapsed=${Date.now() - startedAt}ms`);
    } finally {
      this.readerComicSuppressClickUntil = Date.now() + 320;
      this.suppressReaderTapClick = true;
      this.readerComicChapterSwitching = false;
      this.readerComicBoundaryDirection = 0;
      this.readerComicBoundaryPullDistance = 0;
      this.readerComicBoundaryReady = false;
      this.readerComicBoundaryPullOriginY = 0;
      this.readerComicChapterTransitionY = 0;
      this.readerComicChapterTransitionOpacity = 1;
    }
    if (!this.readerPageVisible) return;
    if (resumeTtsAfterSwitch) {
      await this.startTtsReadingFromCurrentPosition(false);
    } else if (mirroredTts && this.currentChapterIndex !== sourceChapterIndex) {
      try {
        await ReaderTtsFloatingSession.jumpToPosition(this.currentChapterIndex, this.currentPageIndex,
          this.getPageStartOffset(this.currentPageIndex));
        await this.syncMirroredTtsFocus();
      } catch (error) {
        console.warn('滚动切换章节后同步后台朗读位置失败:', error);
      }
    }
  }

  /**
   * 把当前章发布到滚动列表。列表里已有这一章（滚动越过边界后提升为当前章）时分块不变、列表不动；
   * 否则列表换成只含这一章，相邻章节在读者滚到本章首尾附近时再接上。
   */
  syncReaderComicPageDataSource(): void {
    const segment = new ReaderScrollSegment();
    segment.chapterIndex = this.currentChapterIndex;
    segment.pages = this.contentPages;
    segment.starts = this.contentPageStarts;
    segment.ends = this.contentPageEnds;
    segment.source = this.pagedContentText;
    const nextChapter = this.currentChapterIndex < this.chapters.length - 1 ? this.currentChapterIndex + 1 : -1;
    const reloaded = this.readerComicPageDataSource.setCurrent(segment, nextChapter);
    this.reanchorContinuousReaderScrollAfterReload(reloaded);
  }

  /** 当前章第 pageIndex 块在列表里的序号。 */
  readerContinuousListIndex(pageIndex: number): number {
    return Math.max(0, this.readerComicPageDataSource.offsetOf(this.currentChapterIndex)) + Math.max(0, pageIndex);
  }

  /** 读到本章末尾附近接上下一章，开头附近接上上一章；列表里最多保留当前章前后各一章。 */
  ensureReaderContinuousNeighbors(listStart: number, listEnd: number, eager: boolean = false): void {
    if (this.readerContinuousCommitChapter >= 0) return;
    this.neighborLoader().ensureScrollNeighbors(listStart, listEnd, this.contentPages.length, eager);
  }

  neighborLoader(): ReaderNeighborChapterLoader {
    if (!this.readerNeighborLoaderInstance) {
      this.readerNeighborLoaderInstance = new ReaderNeighborChapterLoader({
        visible: (): boolean => this.readerPageVisible,
        bookUrl: (): string => this.book?.bookUrl || this.bookUrl,
        isCurrentBook: (bookUrl: string): boolean => this.isCurrentReaderEngineBook(bookUrl),
        currentChapter: (): number => this.currentChapterIndex,
        chapterCount: (): number => this.chapters.length,
        isComic: (): boolean => this.isReaderComicModeActive(),
        isScrollList: (): boolean => this.isReaderContinuousScrollSurfaceActive(),
        isPagedComic: (): boolean => this.isReaderComicPagedMode(),
        scrollWindow: (): ReaderContinuousDataSource => this.readerComicPageDataSource,
        mayPrefetch: (chapterIndex: number): boolean => chapterIndex >= 0 && chapterIndex < this.chapters.length &&
          (this.readerPreloadEnabled || this.readerEngine().hasCachedContent(chapterIndex)),
        prepare:(chapterIndex: number): Promise<ReaderScrollSegment | null> =>
          this.prepareReaderNeighborSegment(chapterIndex),
        publishPagedNeighbor: (chapterIndex: number, pages: string[]): void => {
          if (chapterIndex > this.currentChapterIndex) {
            this.readerComicPagedNextChapter = chapterIndex;
            this.readerComicPagedNextPages = pages;
          } else {
            this.readerComicPagedPrevChapter = chapterIndex;
            this.readerComicPagedPrevPages = pages;
          }
        }
      });
    }
    return this.readerNeighborLoaderInstance;
  }

  comicImageActions(): ReaderComicImageActions {
    if (!this.readerComicImageActionsInstance) {
      this.readerComicImageActionsInstance = new ReaderComicImageActions({
        uiContext: (): UIContext => this.getUIContext(),
        abilityContext: (): common.UIAbilityContext => getContext(this) as common.UIAbilityContext,
        accentColor: (): string => this.accentColor(),
        isLocalBook: (): boolean => !this.book || LocalBookService.isLocalBook(this.book),
        currentChapter: (): number => this.currentChapterIndex,
        busy: (): boolean => this.isLoading || this.readerContinuousCommitChapter >= 0,
        refreshCurrentChapter: (): void => {
          this.refreshCurrentChapter(this.currentPageIndex, true).catch((error: Error) => {
            console.warn('图片地址过期后刷新本章失败:', error);
          });
        }
      });
    }
    return this.readerComicImageActionsInstance;
  }

  /**
   * 取相邻章节正文并按当前模式切块。切块方式与正式加载这一章完全相同，所以它成为当前章时分页一致。
   * 不走分页缓存：缓存只留三项，挤掉当前章的分页会让章末判断失去依据。正文为空或没切出页时返回 null。
   */
  async prepareReaderNeighborSegment(chapterIndex: number): Promise<ReaderScrollSegment | null> {
    const body = await this.readerEngine().peekContent(chapterIndex);
    if (!body) return null;
    const processed = await this.prepareReaderContentRules(body, chapterIndex);
    const source = this.buildPagedSourceText(chapterIndex, processed);
    const result = this.createChunkReaderPagination(source);
    if (result.pages.length === 0) return null;
    const segment = new ReaderScrollSegment();
    segment.chapterIndex = chapterIndex;
    segment.pages = result.pages;
    segment.starts = result.starts;
    segment.ends = result.ends;
    segment.source = result.source;
    return segment;
  }

  /** 漫画翻页模式：读到本话首尾附近时预先切好相邻章节，翻过去不必等待；不再相邻的旧结果丢掉。 */
  ensureReaderComicPagedNeighbors(): void {
    if (!this.isReaderComicPagedMode()) return;
    const current = this.currentChapterIndex;
    if (this.readerComicPagedPrevChapter !== current - 1 && this.readerComicPagedPrevChapter >= 0) {
      this.readerComicPagedPrevChapter = -1;
      this.readerComicPagedPrevPages = [];
    }
    if (this.readerComicPagedNextChapter !== current + 1 && this.readerComicPagedNextChapter >= 0) {
      this.readerComicPagedNextChapter = -1;
      this.readerComicPagedNextPages = [];
    }
    if (this.contentPages.length === 0 || !this.isCurrentReaderPaginationComplete()) return;
    const spread = this.isReaderComicDualPageActive() ? 2 : 1;
    if (this.readerComicPagedNextChapter < 0 && current < this.chapters.length - 1 &&
      this.contentPages.length - this.currentPageIndex <= 4 + spread) {
      this.neighborLoader().loadPagedNeighbor(current + 1);
    }
    if (this.readerComicPagedPrevChapter < 0 && current > 0 && this.currentPageIndex <= 3) {
      this.neighborLoader().loadPagedNeighbor(current - 1);
    }
  }

  /**
   * 翻页视图已翻进预先切好的相邻章节并停在那里：把它设为当前章（下一话停在第一页，上一话停在最后一页）。
   * 刚离开的这一话正好成了反方向的相邻章节，直接留用。失败时让视图退回本话。
   */
  async commitReaderComicPagedChapter(direction: number): Promise<void> {
    const sourceChapterIndex = this.currentChapterIndex;
    const targetChapterIndex = sourceChapterIndex + direction;
    if (direction === 0 || targetChapterIndex < 0 || targetChapterIndex >= this.chapters.length) {
      this.readerComicPagedController.cancelCross();
      return;
    }
    const leavingPages = this.contentPages;
    this.pendingRestorePageIndex = direction > 0 ? 0 : Number.MAX_SAFE_INTEGER;
    try {
      await this.loadContent(true, targetChapterIndex);
    } catch (error) {
      console.warn('翻页模式跨章失败:', error);
    }
    if (this.currentChapterIndex !== targetChapterIndex) {
      if (this.pendingRestorePageIndex >= 0) this.pendingRestorePageIndex = -1;
      this.readerComicPagedController.cancelCross();
      return;
    }
    if (direction > 0) {
      this.readerComicPagedPrevChapter = sourceChapterIndex;
      this.readerComicPagedPrevPages = leavingPages;
    } else {
      this.readerComicPagedNextChapter = sourceChapterIndex;
      this.readerComicPagedNextPages = leavingPages;
    }
    this.scheduleReaderComicProgressSave();
    this.ensureReaderComicPagedNeighbors();
  }

  commitReaderContinuousChapter(chapterIndex: number, pageIndex: number): void {
    if (this.readerContinuousCommitChapter >= 0 || this.readerComicChapterSwitching) return;
    this.runReaderContinuousChapterCommit(chapterIndex, pageIndex).catch((error: Error) => {
      console.error('滚动跨章切换当前章失败:', error);
    });
  }

  /**
   * 视口顶部已经是另一章：按正常加载流程把它设为当前章（进度、目录、朗读、书签等都跟着切换），
   * 但列表里这一章的分块已经在了，发布时不改数据、不重新对齐滚动位置。
   */
  async runReaderContinuousChapterCommit(chapterIndex: number, pageIndex: number): Promise<void> {
    const sourceChapterIndex = this.currentChapterIndex;
    // 手动越过章节时朗读改从新位置继续，与上下拉切章一致；后台浮窗朗读则移到新位置。
    const mirroredTts = this.isMirroringActiveTtsForCurrentBook();
    const ownTtsActive = !mirroredTts && (this.isTtsSpeaking || this.ttsReader.isSpeaking());
    const resumeTtsAfterSwitch = ownTtsActive && !this.isTtsPaused;
    if (resumeTtsAfterSwitch) {
      this.stopTtsReaderForChapterSwitch();
    } else if (ownTtsActive) {
      this.stopTtsReading();
    }
    this.readerContinuousCommitChapter = chapterIndex;
    this.pendingRestorePageIndex = Math.max(0, pageIndex);
    let switched = false;
    try {
      switched = await this.loadContent(true, chapterIndex);
    } finally {
      this.readerContinuousCommitChapter = -1;
      if (this.currentChapterIndex !== chapterIndex && this.pendingRestorePageIndex >= 0) {
        this.pendingRestorePageIndex = -1;
      }
    }
    if (!this.readerPageVisible || this.currentChapterIndex !== chapterIndex) return;
    console.info(`[ReaderContinuous] chapter ${sourceChapterIndex} -> ${chapterIndex} switched=${switched}`);
    this.scheduleReaderComicProgressSave();
    this.comicImageActions().onChapterBecameCurrent(chapterIndex);
    const top = this.readerComicPageDataSource.itemAt(this.readerContinuousLastListStart);
    if (top && top.isPage() && top.chapterIndex !== chapterIndex) {
      // 提交期间读者又滚进了另一章，按最新可见区继续切换。
      this.onReaderComicScrollIndexChanged(this.readerContinuousLastListStart, this.readerContinuousLastListEnd);
    } else {
      this.readerComicPageDataSource.trim(chapterIndex - 1, chapterIndex + 1);
      // 继续往同一方向读时下一个相邻章节马上就要用到，趁读者还在这一章就接上。
      this.ensureReaderContinuousNeighbors(this.readerContinuousLastListStart, this.readerContinuousLastListEnd, true);
    }
    if (resumeTtsAfterSwitch) {
      await this.startTtsReadingFromCurrentPosition(false);
    } else if (mirroredTts) {
      try {
        await ReaderTtsFloatingSession.jumpToPosition(this.currentChapterIndex, this.currentPageIndex,
          this.getPageStartOffset(this.currentPageIndex));
        await this.syncMirroredTtsFocus();
      } catch (error) {
        console.warn('滚动跨章后同步后台朗读位置失败:', error);
      }
    }
  }

  /** 小说滚动模式两章之间的分隔：章节标题由下一章第一块自己排出，这里只留间隔或加载提示。 */
  @Builder
  readerContinuousChapterSeparator(item: ReaderScrollItem) {
    Column({ space: AppSpacing.MD }) {
      if (item.pending) {
        Row({ space: AppSpacing.MD }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.getSubTextColor())
          Text('正在加载下一章')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.getSubTextColor())
        }
      } else if (item.failed) {
        Text('下一章加载失败，继续上拉重试')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.getSubTextColor())
      } else {
        Row()
          .width(48)
          .height(1)
          .backgroundColor(this.getSubTextColor())
          .opacity(0.35)
      }
    }
    .width('100%')
    .height(item.pending || item.failed ? 120 : 64)
    .justifyContent(FlexAlign.Center)
  }


  /**
   * onDataReloaded 会重建 LazyForEach 的挂载项，部分系统版本会把 List 打回索引 0，表现为
   * "阅读中偶发回到本章开头"。发布分页时 currentPageIndex 仍是权威位置，延迟一帧校验并把
   * List 拉回该页；位置未被破坏时 scrollToIndex 等价于无操作。
   */
  reanchorContinuousReaderScrollAfterReload(reloaded: boolean): void {
    // 只作用于小说滚动模式：漫画模式有自己的章节切换/恢复时序，且本地漫画分页是单次同步发布，
    // 不会出现阅读中 reload，保持其原有行为以隔离变量。
    if (!reloaded || !this.isReaderNovelContinuousScrollModeActive() || !this.readerInitialPageReady ||
      !this.readerProgressRestoreConfirmed || this.pendingRestorePageIndex >= 0 ||
      this.readerComicScrollRestoring || this.contentPages.length === 0) {
      return;
    }
    const serial = ++this.readerComicReanchorSerial;
    const chapterIndex = this.currentChapterIndex;
    const targetIndex = Math.max(0, Math.min(this.currentPageIndex, this.contentPages.length - 1));
    setTimeout(() => {
      if (serial !== this.readerComicReanchorSerial || chapterIndex !== this.currentChapterIndex ||
        !this.readerPageVisible || this.readerComicScrollRestoring || this.pendingRestorePageIndex >= 0) {
        return;
      }
      try {
        this.readerComicScroller.scrollToIndex(this.readerContinuousListIndex(targetIndex), false, ScrollAlign.START);
      } catch (_) {
      }
    }, 48);
  }

  scheduleReaderComicScrollRestore(): void {
    if (this.isReaderComicPagedMode()) {
      this.readerComicScrollRestoreSerial++;
      this.readerComicScrollRestoring = false;
      this.readerContinuousReachedEnd = this.contentPages.length > 0 &&
        this.currentPageIndex >= this.contentPages.length - 1;
      this.ensureReaderComicPagedNeighbors();
      return;
    }
    if (this.readerContinuousCommitChapter >= 0 && this.readerContinuousCommitChapter === this.currentChapterIndex) {
      // 滚动越过章节边界提升当前章：列表本来就停在读者看的位置，不能再按页首对齐。
      this.readerComicScrollRestoreSerial++;
      this.readerComicScrollRestoring = false;
      return;
    }
    if (!this.isReaderContinuousScrollSurfaceActive() || this.contentPages.length === 0) return;
    const serial = ++this.readerComicScrollRestoreSerial;
    const chapterIndex = this.currentChapterIndex;
    const pageIndex = Math.max(0, Math.min(this.currentPageIndex, this.contentPages.length - 1));
    this.readerComicScrollRestoring = true;
    let attempt = 0;
    const maxAttempts = 5;
    const restore = (): void => {
      if (serial !== this.readerComicScrollRestoreSerial || chapterIndex !== this.currentChapterIndex ||
        !this.isReaderContinuousScrollSurfaceActive()) {
        return;
      }
      try {
        this.readerComicScroller.scrollToIndex(this.readerContinuousListIndex(pageIndex), false, ScrollAlign.START);
      } catch (error) {
        console.warn('恢复漫画滚动位置失败:', error);
      }
      setTimeout(() => {
        if (serial !== this.readerComicScrollRestoreSerial || chapterIndex !== this.currentChapterIndex) return;
        const visiblePageIndex = Math.max(0,
          Math.min(this.readerContinuousVisibleStart, this.contentPages.length - 1));
        const lastPagePinnedToBottom = pageIndex === this.contentPages.length - 1 &&
          this.readerContinuousVisibleEnd >= pageIndex;
        if (visiblePageIndex !== pageIndex && !lastPagePinnedToBottom && attempt < maxAttempts) {
          attempt++;
          setTimeout(restore, Math.min(160, 24 + attempt * 24));
          return;
        }
        // Do not let a provisional index callback replace the durable target. Even on devices that do not emit
        // onScrollIndex for an immediate jump, keep the logical page authoritative; the final retry above has
        // already aligned the List as closely as the current viewport permits.
        this.currentPageIndex = pageIndex;
        this.currentPageText = this.contentPages[pageIndex] || '';
        this.readerContinuousReachedEnd = pageIndex === this.contentPages.length - 1;
        this.readerComicScrollRestoring = false;
        if (visiblePageIndex !== pageIndex && !lastPagePinnedToBottom) {
          console.warn(`[ReaderProgress] continuous restore settled without index callback: ` +
            `chapter=${chapterIndex},target=${pageIndex},visible=${visiblePageIndex}`);
        }
        // 停在章首时列表已到顶，往上拉不会再回报可见区；就位后立即接上前后章节，向上跨章才与向下一样无缝。
        if (this.pendingRestorePageIndex < 0) {
          this.ensureReaderContinuousNeighbors(this.readerContinuousLastListStart,
            this.readerContinuousLastListEnd, true);
        }
      }, attempt === 0 ? 96 : 128);
    };
    setTimeout(restore, 16);
  }

  onReaderComicScrollIndexChanged(start: number, end: number): void {
    // ArkUI can publish one final List index while the route is being detached. That callback describes the
    // shrinking/unmounted viewport, not a user scroll, and must not replace the page captured by exit/background.
    if (!this.readerPageVisible) return;
    const listStart = Math.max(0, Math.round(start));
    const listEnd = Math.max(listStart, Math.round(end));
    this.readerContinuousLastListStart = listStart;
    this.readerContinuousLastListEnd = listEnd;
    // 列表里还有相邻章节与分隔项；可见区换算成当前章内的序号，越出本章的部分夹到本章首尾。
    const offset = Math.max(0, this.readerComicPageDataSource.offsetOf(this.currentChapterIndex));
    const lastLocal = Math.max(0, this.contentPages.length - 1);
    this.readerContinuousVisibleStart = Math.max(0, Math.min(listStart - offset, lastLocal));
    this.readerContinuousVisibleEnd = Math.max(this.readerContinuousVisibleStart,
      Math.min(listEnd - offset, lastLocal));
    if (listEnd - offset < this.contentPages.length - 1) {
      this.readerContinuousReachedEnd = false;
    }
    this.pruneContinuousReaderSelectionAreas();
    if (!this.isReaderContinuousScrollSurfaceActive() || this.readerComicScrollRestoring ||
      this.pendingRestorePageIndex >= 0 || this.contentPages.length === 0) {
      return;
    }
    this.ensureReaderContinuousNeighbors(listStart, listEnd);
    const top = this.readerComicPageDataSource.itemAt(listStart);
    if (top && top.isPage() && top.chapterIndex !== this.currentChapterIndex) {
      this.commitReaderContinuousChapter(top.chapterIndex, top.pageIndex);
      return;
    }
    const pageIndex = this.readerContinuousReachedEnd &&
      this.readerContinuousVisibleEnd >= lastLocal ? lastLocal : this.readerContinuousVisibleStart;
    if (pageIndex === this.currentPageIndex) return;
    this.currentPageIndex = pageIndex;
    this.currentPageText = this.contentPages[pageIndex] || '';
    if (this.contentPages.length - pageIndex <= 4) {
      this.preloadReaderContentLater();
      this.preloadNextChapterPaginationLater(0);
    }
    if (pageIndex <= 3) this.preloadPreviousChapterPaginationLater(0);
    this.scheduleReaderComicProgressSave();
  }

  onReaderContinuousReachEnd(): void {
    if (!this.readerPageVisible || !this.isReaderContinuousScrollSurfaceActive() ||
      this.contentPages.length === 0) return;
    // 列表末尾属于后面的章节时，本章并没有读到底；那一章被提升为当前章时会再判断。
    if (this.readerComicPageDataSource.lastChapter() !== this.currentChapterIndex) return;
    this.readerContinuousReachedEnd = true;
    if (this.readerComicScrollRestoring || this.pendingRestorePageIndex >= 0) return;
    const lastPageIndex = this.contentPages.length - 1;
    if (this.currentPageIndex === lastPageIndex) return;
    this.currentPageIndex = lastPageIndex;
    this.currentPageText = this.contentPages[lastPageIndex] || '';
    this.preloadReaderContentLater();
    this.preloadNextChapterPaginationLater(0);
    this.scheduleReaderComicProgressSave();
  }

  pruneContinuousReaderSelectionAreas(): void {
    const keepStart = Math.max(0, this.readerContinuousVisibleStart - 1);
    const keepEnd = this.readerContinuousVisibleEnd + 1;
    this.pruneReaderContinuousV2Controllers(this.readerContinuousLastListStart - 4,
      this.readerContinuousLastListEnd + 4);
    for (const key of Array.from(this.readerSelectableTextAreas.keys())) {
      // 原生选中键与可见段键都要按窗口清理：懒挂载后原生键只在挂载瞬间登记一次，
      // 残留的旧几何会把下一次选择窗口锚到过期位置。
      if (!key.startsWith('reader_continuous_native_') && !key.includes('reader_vertical_scroll_')) continue;
      const pageIndex = this.continuousSelectionPageIndexForKey(key);
      if (pageIndex < 0) continue;
      if (pageIndex >= keepStart && pageIndex <= keepEnd) continue;
      this.readerSelectableTextAreas.delete(key);
      this.readerSelectableTextValues.delete(key);
      this.readerSelectableTextControllers.delete(key);
      this.readerSelectableTextScrollOffsets.delete(key);
    }
  }

  scheduleReaderComicProgressSave(): void {
    this.clearReaderComicProgressSaveTimer();
    this.readerComicProgressSaveTimerId = setTimeout(() => {
      this.readerComicProgressSaveTimerId = -1;
      this.saveReadingProgress();
    }, 350);
  }

  clearReaderComicProgressSaveTimer(): void {
    if (this.readerComicProgressSaveTimerId < 0) return;
    clearTimeout(this.readerComicProgressSaveTimerId);
    this.readerComicProgressSaveTimerId = -1;
  }

  scheduleReaderPagedProgressSave(): void {
    this.clearReaderPagedProgressSaveTimer();
    this.readerPagedProgressSaveTimerId = setTimeout(() => {
      this.readerPagedProgressSaveTimerId = -1;
      this.saveReadingProgress();
    }, 300);
  }

  clearReaderPagedProgressSaveTimer(): void {
    if (this.readerPagedProgressSaveTimerId < 0) return;
    clearTimeout(this.readerPagedProgressSaveTimerId);
    this.readerPagedProgressSaveTimerId = -1;
  }

  isReaderImageOnlySource(source: string): boolean {
    const text = source || '';
    if (!LocalBookService.hasEpubImageMarkers(text)) return false;
    return LocalBookService.stripEpubImageMarkers(text).trim().length === 0;
  }

  countReaderImageMarkers(source: string): number {
    const text = source || '';
    const prefix = LocalBookService.EPUB_IMAGE_MARKER_PREFIX;
    let count = 0;
    let cursor = 0;
    while (cursor < text.length) {
      const markerStart = text.indexOf(prefix, cursor);
      if (markerStart < 0) break;
      count++;
      cursor = markerStart + prefix.length;
    }
    return count;
  }

  clearReaderComicPaginationProgress(): void {
    this.readerComicPaginationParsing = false;
    this.readerComicPaginationParsedPages = 0;
    this.readerComicPaginationTotalPages = 0;
    this.readerComicPaginationSource = '';
  }

  updateReaderComicPaginationProgress(chapterIndex: number, result: ReaderPaginationResult): void {
    if (chapterIndex !== this.currentChapterIndex) return;
    if (!this.isReaderComicModeActive()) {
      this.clearReaderComicPaginationProgress();
      return;
    }
    let total = this.readerComicPaginationTotalPages;
    if (this.readerComicPaginationSource !== result.source) {
      if (!this.isReaderImageOnlySource(result.source)) {
        this.clearReaderComicPaginationProgress();
        return;
      }
      this.readerComicPaginationSource = result.source;
      total = this.countReaderImageMarkers(result.source);
    }
    total = Math.max(total, result.pages.length);
    this.readerComicPaginationTotalPages = total;
    this.readerComicPaginationParsedPages = Math.min(total, result.pages.length);
    this.readerComicPaginationParsing = result.complete !== true &&
      this.readerComicPaginationParsedPages < total;
  }

  isReaderImageOnlyPage(text: string): boolean {
    return LocalBookService.isEpubImageMarker((text || '').trim());
  }

  getEffectiveReaderMarginLeft(): number {
    return this.getEffectiveReaderHorizontalMargin(true);
  }

  getEffectiveReaderMarginRight(): number {
    return this.getEffectiveReaderHorizontalMargin(false);
  }

  getEffectiveReaderHorizontalMargin(left: boolean): number {
    const rawLeft = Math.max(0, this.readerMarginLeft);
    const rawRight = Math.max(0, this.readerMarginRight);
    const total = rawLeft + rawRight;
    if (total <= 0) return 0;
    const columnWidth = this.getReaderPageColumnWidth();
    // Keep enough room for a useful Chinese text line in compact split-screen and double-page
    // layouts. Stored settings remain untouched and automatically recover on a wider viewport.
    const minimumTextWidth = Math.min(columnWidth, Math.max(96, this.readerFontSize * 4.8));
    const allowedTotal = Math.max(0, columnWidth - minimumTextWidth);
    const scale = total > allowedTotal ? allowedTotal / total : 1;
    return (left ? rawLeft : rawRight) * scale;
  }

  getEffectiveReaderMarginTop(): number {
    return this.getEffectiveReaderVerticalMargin(true) + this.getReaderHeaderContentReserve();
  }

  getReaderHeaderInfoBarHeight(): number {
    // 页眉高度只由字号推算，避免首次测量后再次触发整章分页。
    return this.getReaderInfoBarConfig().headerLineHeight();
  }

  getReaderHeaderOverlayTopInset(): number {
    // 普通阅读容器已经通过 getReaderTopSafePadding() 避让状态栏；叠页/仿真为了让纸张
    // 覆盖全屏而不消费顶部安全区，需要在页眉自身补回这段高度。
    return (this.getReaderTopSafePadding() <= 0 ? this.getReaderPageContentTopPadding() : 0) +
      this.getReaderHeaderTopGap();
  }

  getReaderHeaderTopGap(): number {
    // 扩展模式下状态栏已隐藏，页眉从屏幕顶端开始；留一小段间距，避免文字紧贴屏幕边缘和圆角。
    // 再加上用户设置的页眉下移距离。正文的页眉预留同步增加，页眉下移不会压住首行。
    return (this.readerExtendToStatusBar ? 8 : 0) + this.getReaderInfoBarConfig().headerOffset;
  }

  getReaderHeaderContentReserve(): number {
    return this.isReaderHeaderVisible() ?
      this.getReaderHeaderInfoBarHeight() + this.getReaderInfoBarConfig().headerExtraHeight() +
        this.readerVerticalGapWithinMargin(4, true) + this.getReaderHeaderTopGap() : 0;
  }

  /**
   * 页眉、页脚和手势条与正文之间原本写死的间隙。用户边距不小于它时照旧留出，已有排版不变；
   * 边距调得更小时间隙随之收缩，边距为 0 时正文紧贴页眉、页脚或手势条上沿。
   */
  readerVerticalGapWithinMargin(gap: number, top: boolean): number {
    return Math.min(Math.max(0, gap), this.getEffectiveReaderVerticalMargin(top));
  }

  getEffectiveReaderMarginBottom(): number {
    return this.getEffectiveReaderVerticalMargin(false);
  }

  getReaderContinuousScrollBottomPadding(): number {
    // 与顶部的页眉占位对应：滚动模式下把页脚占位并入列表底部内边距。用按字号推算的固定高度，
    // 页脚首次测量不会改变列表视口。
    return this.getEffectiveReaderMarginBottom() + this.getReaderV2BottomGuard();
  }

  getEffectiveReaderVerticalMargin(top: boolean): number {
    const rawTop = Math.max(0, this.readerMarginTop);
    const rawBottom = Math.max(0, this.readerMarginBottom);
    const total = rawTop + rawBottom;
    if (total <= 0) return 0;
    const viewportHeight = this.getReaderPaginationViewportHeight();
    const minimumTextHeight = Math.min(viewportHeight, Math.max(96, this.getEffectiveReaderLineHeight() * 2));
    // The footer is an overlay and therefore does not reduce the range available to user margins.
    const availableForMargins = Math.max(0, viewportHeight - minimumTextHeight);
    const scale = total > availableForMargins ? availableForMargins / total : 1;
    return (top ? rawTop : rawBottom) * scale;
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
    // V2 paints the page through one retained native FrameNode. Alternating the whole ArkUI subtree on every
    // page destroys that node just before the simulation overlay is removed, so a rapid turn can expose one
    // layout frame from the newly-created paragraph tree. Keep one stable V2 surface and only update its page.
    if (this.shouldUseReaderLayoutV2(this.pagedContentText)) return 0;
    return Math.abs(this.currentChapterIndex + this.currentPageIndex) % 2;
  }

  currentReaderSurfaceKeys(): string[] {
    // Page/chapter and TTS focus changes must publish a fresh declarative subtree. Reusing one fixed ForEach item
    // leaves ArkUI holding the previous chapter or the previous set of highlighted spans.
    return [this.currentReaderPageRenderIdentity(this.pageRenderVersion, this.ttsHighlightRenderVersion)];
  }

  currentReaderV2ChapterSurfaceKeys(): string[] {
    // Keep the native canvas stable during an animation, but remount it after the settled page index changes.
    // ArkUI can retain a NodeContainer even after updatePage() receives a new page object; keying by the settled
    // page makes the declarative host and the retained FrameNode advance atomically instead of leaving old正文.
    return [`reader_v2_chapter_${this.currentChapterIndex}_${this.currentPageIndex}_` +
      `${this.readerV2SurfaceGeneration}`];
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
    this.readerTextSelectionSerial++;
    this.clearReaderV2SelectionOverlay();
    if (this.currentPageText !== nextText) {
      this.chapterJumpRenderGeneration++;
    }
    this.readerSourceActionAreas.clear();
    this.readerSourceActionScrollOffsets.clear();
    this.clearPendingReaderSourceActionBounds();
    this.currentPageText = nextText;
    this.displayPageText = nextText;
    this.displayPageChapterIndex = this.currentChapterIndex;
    this.displayPageIndex = this.currentPageIndex;
    this.displayPageRenderKey++;
    this.pageRenderVersion++;
    this.refreshCurrentReaderV2RetainedPages();
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

  /**
   * 量出分页区域下缘离窗口下缘还有多远。分页区域从正文容器的顶部内边距之后开始、占满剩余高度，
   * 所以它的下缘就是"顶部内边距 + 区域高度"。结果限制在导航条高度以内，量不到时保持原值。
   */
  measureReaderPageAreaBottomGap(areaHeight: number): number {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const windowRect = context.windowStage.getMainWindowSync().getWindowProperties().windowRect;
      const windowHeight = px2vp(windowRect.height);
      if (windowHeight <= 0 || areaHeight <= 0) return this.readerPageAreaBottomGap;
      const gap = windowHeight - (this.getReaderTopSafePadding() + areaHeight);
      // 亚像素误差按贴底处理，避免来回触发重新分页。
      if (gap < 1) return 0;
      return Math.min(Math.max(0, this.navBarHeight), Math.round(gap * 2) / 2);
    } catch (_) {
      return this.readerPageAreaBottomGap;
    }
  }

  /** 分页区域之下、仍属于本窗口的那段系统导航条区域的高度；阅读表面的纸张会延伸进这段区域。 */
  getReaderBottomSystemExtension(): number {
    return Math.max(0, this.readerPageAreaBottomGap);
  }

  /**
   * 正文为避让底部导航条需要在分页区域内留出的高度，与"正文扩展至状态栏"无关。
   * 分页区域贴到窗口底部时是整个导航条高度；系统已经把导航条排除在分页区域之外时为 0。
   */
  getReaderNavigationBottomReserve(): number {
    if (this.isReaderComicModeActive()) return 0;
    return Math.max(0, Math.max(0, this.navBarHeight) - this.getReaderBottomSystemExtension());
  }

  updatePagedReaderArea(area: Area): void {
    const width = this.parseAreaDimension(area.width);
    const contentTopPadding = this.getReaderPageContentTopPadding();
    const height = this.parseAreaDimension(area.height) - contentTopPadding;
    const previousNavigationReserve = this.getReaderNavigationBottomReserve();
    this.readerPageAreaBottomGap = this.measureReaderPageAreaBottomGap(this.parseAreaDimension(area.height));
    const navigationReserveChanged =
      Math.abs(this.getReaderNavigationBottomReserve() - previousNavigationReserve) >= 0.5;
    this.readerPageContentTopPaddingSnapshot = contentTopPadding;
    if (width <= 0 || height <= 0) {
      return;
    }
    // A theme rebuild can move the page without changing its size. Keep the measured origin current even when
    // pagination itself does not need to run again, otherwise V2 action hit testing uses a stale vertical offset.
    const globalY: Length = area.globalPosition?.y ?? 0;
    this.readerCommentPageAreaTop = this.parseAreaDimension(globalY);
    this.readerCommentPageAreaHeight = height;
    if (Math.abs(this.pageViewWidth - width) < 0.5 && Math.abs(this.pageViewHeight - height) < 0.5 &&
      !(navigationReserveChanged && !this.readerFooterEnabled)) {
      return;
    }
    const preservingStoredOffset = !this.readerProgressRestoreConfirmed &&
      (this.readerTypographyRestoreOffset >= 0 ||
        (this.readerProgressAnchorChapterIndex === this.currentChapterIndex &&
          this.readerProgressAnchorOffset >= 0));
    const shouldRestoreSavedPage = this.pendingRestorePageIndex >= 0 || preservingStoredOffset;
    const readingOffset = this.getReaderStableReflowOffset();
    if (!shouldRestoreSavedPage && this.readerInitialPageReady && this.contentPages.length > 0) {
      // Window foreground/rotation can briefly report several sizes. Keep the completed visible snapshot and
      // remap this source offset only when the replacement pagination session is complete.
      this.readerTypographyRestoreOffset = readingOffset;
    }
    this.pageViewWidth = width;
    this.pageViewHeight = height;
    // 旧视口下还在排的相邻章节会话作废，下面按新视口重新预排。
    this.adjacentPaginationPreloadSerial++;
    this.previousPaginationPreloadSerial++;
    this.eyeTurn().refreshForViewport();
    AppStorage.setOrCreate<number>('readerLastPageViewWidth', width);
    AppStorage.setOrCreate<number>('readerLastPageViewHeight', height);
    this.paginateContent(this.content);
    if (!shouldRestoreSavedPage) {
      this.currentPageIndex = this.normalizeReaderSpreadPageIndex(this.findPageIndexByOffset(readingOffset));
    }
    this.syncCurrentPageText();
    this.preloadNextChapterPaginationLater();
    this.preloadPreviousChapterPaginationLater();
  }

  rememberReaderBottomInfoBarHeight(area: Area): void {
    const measuredHeight = this.normalizeReaderBottomInfoBarHeight(this.parseAreaDimension(area.height));
    if (measuredHeight <= 0 ||
      Math.abs(measuredHeight - this.getReaderBottomInfoBarHeight()) < 0.25) {
      return;
    }
    this.readerBottomInfoBarPendingHeight = measuredHeight;
    if (this.readerBottomInfoBarMeasureTimerId >= 0) return;
    // Coalesce the two footer labels and apply the measurement outside ArkUI's layout callback.
    this.readerBottomInfoBarMeasureTimerId = setTimeout(() => {
      this.readerBottomInfoBarMeasureTimerId = -1;
      const height = this.readerBottomInfoBarPendingHeight;
      this.readerBottomInfoBarPendingHeight = 0;
      this.applyReaderBottomInfoBarMeasuredHeight(height);
    }, 0);
  }

  normalizeReaderBottomInfoBarHeight(height: number): number {
    if (!Number.isFinite(height) || height <= 0) return 0;
    try {
      // ArkUI ultimately lays the line box on physical pixels. Quantizing here avoids tiny decimal
      // area fluctuations creating a layout/repagination loop on fractional-density displays.
      return px2vp(Math.max(1, Math.round(vp2px(height))));
    } catch (_) {
      return Math.round(height * 100) / 100;
    }
  }

  applyReaderBottomInfoBarMeasuredHeight(height: number): void {
    if (!Number.isFinite(height) || height <= 0 ||
      Math.abs(height - this.getReaderBottomInfoBarHeight()) < 0.25) {
      return;
    }
    const previousPaginationHeight = this.getReaderContentBottomReserve() +
      this.getReaderPaginationBottomInfoBarHeight();
    const readingOffset = this.getReaderStableReflowOffset();
    this.readerBottomInfoBarMeasuredHeight = height;
    // Reader V2 paints chapter/page metadata as an overlay and owns a bottom guard computed without measuring it.
    // The first real footer measurement therefore cannot change any V2 page boundary. Rebuilding the retained
    // Paragraph session here used to measure the opening page twice and kept the loading mask visible for seconds.
    if (this.shouldUseReaderLayoutV2(this.pagedContentText || this.getPagedSourceText())) {
      return;
    }
    const nextPaginationHeight = this.getReaderContentBottomReserve() +
      this.getReaderPaginationBottomInfoBarHeight();
    if (Math.abs(previousPaginationHeight - nextPaginationHeight) < 0.25 ||
      !this.hasPagedReaderArea() || !this.content) {
      return;
    }

    this.finishPageTurnAnimation(false);
    this.readerPaginationWorkSerial++;
    this.adjacentPaginationPreloadSerial++;
    this.previousPaginationPreloadSerial++;
    this.readerPaginationCache.clear();
    this.pageTurnPreviewKey = '';
    this.pageTurnPreviewLoadingKey = '';
    this.paginateContent(this.content);
    this.currentPageIndex = this.normalizeReaderSpreadPageIndex(this.findPageIndexByOffset(readingOffset));
    this.syncCurrentPageText();
    this.preloadNextChapterPaginationLater();
    this.preloadPreviousChapterPaginationLater();
  }

  hasPagedReaderArea(): boolean {
    return this.pageViewWidth > 0 && this.pageViewHeight > 0;
  }

  getCurrentPageStartOffset(): number {
    return this.getPageStartOffset(this.currentPageIndex);
  }

  getReaderStableReflowOffset(): number {
    // Opening-time viewport/font calibration can repaginate immediately after TTS has started. The spoken
    // sentence is the authoritative visible position in that state; anchoring the reflow to the old page start
    // can put the rebuilt surface on the neighbouring page and leave the still-valid focus range off-screen.
    if (this.shouldRenderTtsFocus() && this.readerV2TtsSourceStart >= 0) {
      return this.readerV2TtsSourceStart;
    }
    // Initial V2 pagination deliberately publishes only a small window. Until the persisted character offset has
    // been mapped onto authoritative page boundaries, page zero is merely a render placeholder and must never
    // become the anchor of a geometry/calibration repagination.
    if (!this.readerProgressRestoreConfirmed) {
      if (this.readerTypographyRestoreOffset >= 0) return this.readerTypographyRestoreOffset;
      if (this.readerProgressAnchorChapterIndex === this.currentChapterIndex &&
        this.readerProgressAnchorOffset >= 0) {
        return this.readerProgressAnchorOffset;
      }
    }
    return this.getCurrentPageStartOffset();
  }

  getPageStartOffset(pageIndex: number): number {
    return ReaderPageOffsets.startOf(this.contentPageStarts, pageIndex);
  }

  getPageEndOffset(pageIndex: number): number {
    return ReaderPageOffsets.endOf(this.contentPageStarts, this.contentPageEnds, pageIndex, this.content.length);
  }

  findPageIndexByOffset(offset: number): number {
    if (this.contentPageStarts.length === 0) {
      return Math.max(0, Math.min(this.currentPageIndex, Math.max(0, this.contentPages.length - 1)));
    }
    const sourceLength = this.pagedContentText ? this.pagedContentText.length : this.content.length;
    return ReaderPageOffsets.pageIndexOf(this.contentPageStarts, this.contentPageEnds, offset, sourceLength);
  }

  restoreReaderTypographyOffsetIfAvailable(paginationComplete: boolean): boolean {
    if (this.readerTypographyRestoreOffset < 0 || this.contentPageEnds.length === 0) return false;
    const targetOffset = this.readerTypographyRestoreOffset;
    const lastEnd = this.contentPageEnds[this.contentPageEnds.length - 1];
    if (!paginationComplete && targetOffset >= lastEnd) return false;
    const pageIndex = this.normalizeReaderSpreadPageIndex(this.findPageIndexByOffset(targetOffset));
    this.currentPageIndex = Math.max(0, Math.min(pageIndex, Math.max(0, this.contentPages.length - 1)));
    this.pendingRestorePageIndex = -1;
    this.readerTypographyRestoreOffset = -1;
    // The persisted character offset has now been mapped to an authoritative page. From this point on,
    // checkpoints may follow the visible page instead of the immutable database anchor captured at open time.
    this.readerProgressRestoreConfirmed = true;
    this.readerInitialPageReady = true;
    this.finishReaderInitialOpening();
    this.setCurrentPageText(this.contentPages[this.currentPageIndex] || '');
    return true;
  }

  getBackgroundColor(): string {
    return this.currentReaderTheme().backgroundColor;
  }

  getBackgroundAssetId(): string {
    return this.currentReaderTheme().backgroundAssetId || '';
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
        fontItem.sourceName = ReaderFontHelper.resolveDisplayName(item.sourceName, item.filePath);
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
    return this.readerFontFamily ||
      ReaderFontBootstrap.defaultFontFamily(this.readerGlobalFontMode, this.getSystemReaderFontFamily());
  }

  getSystemReaderFontFamily(): string {
    return this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext());
  }

  clearReaderFontState(): void {
    this.activeReaderFontFamily = '';
    this.readerFontRegistered = false;
    this.readerActiveFontFamily = '';
    this.readerStoredFontRegistered = false;
    this.readerFontRenderReady = false;
    ReaderFontBootstrap.applyApplicationFont(getContext(this), 'readbook-clear-font');
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
      this.scheduleRegisteredReaderFontRefresh(familyName);
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
    this.scheduleRegisteredReaderFontRefresh(familyName);
  }

  // The engine picks a newly registered font up some frames later, so the text is refreshed twice. Activations can
  // overlap (page show registers twice); only the timers of the latest activation run, so they do not multiply.
  scheduleRegisteredReaderFontRefresh(familyName: string): void {
    const serial = ++this.readerFontRefreshSerial;
    this.refreshRegisteredReaderFontLater(familyName, 80, serial);
    this.refreshRegisteredReaderFontLater(familyName, 240, serial);
  }

  refreshRegisteredReaderFontLater(familyName: string, delayMs: number, serial: number): void {
    setTimeout(() => {
      if (!familyName || this.activeReaderFontFamily !== familyName || serial !== this.readerFontRefreshSerial) {
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
    this.readerFontWeight = settings.fontWeight;
    this.readerLetterSpacing = settings.letterSpacing;
    this.readerTextAlign = settings.textAlign;
    this.readerLineHeight = settings.lineHeight;
    this.readerParagraphSpacing = settings.paragraphSpacing;
    this.readerParagraphIndent = settings.paragraphIndent;
    this.readerMarginLeft = settings.marginLeft;
    this.readerMarginRight = settings.marginRight;
    this.readerMarginTop = settings.marginTop;
    this.readerMarginBottom = settings.marginBottom;
    this.readerCommentBubbleSize = settings.commentBubbleSize;
    this.readerLightThemeIndex = settings.lightThemeIndex;
    this.readerDarkThemeIndex = settings.darkThemeIndex;
    this.readerLightCustomThemeBackgroundColor = settings.lightCustomThemeBackgroundColor;
    this.readerLightCustomThemeTextColor = settings.lightCustomThemeTextColor;
    this.readerDarkCustomThemeBackgroundColor = settings.darkCustomThemeBackgroundColor;
    this.readerDarkCustomThemeTextColor = settings.darkCustomThemeTextColor;
    this.readerCustomThemesRaw = settings.customThemesRaw || '';
    this.readerPageTurnMode = settings.pageTurnMode;
    this.readerPageTurnAnimationType = settings.pageTurnAnimationType;
    this.readerLandscapeDoublePage = settings.landscapeDoublePage;
    this.readerScreenOrientation = settings.screenOrientation;
    this.readerTapZoneActions = settings.tapZoneActions;
    this.readerVolumeTurnPage = settings.volumeTurnPage;
    this.readerEyeTurnEnabled = settings.eyeTurnEnabled;
    this.readerEyeTurnPortraitCalibration = settings.eyeTurnPortraitCalibration || '';
    this.readerEyeTurnLandscapeCalibration = settings.eyeTurnLandscapeCalibration || '';
    this.readerEyeTurnPreviousEnabled = settings.eyeTurnPreviousEnabled;
    this.readerEyeTurnNextEnabled = settings.eyeTurnNextEnabled;
    this.readerEyeTurnPreviousDwellMs = settings.eyeTurnPreviousDwellMs || 850;
    this.readerEyeTurnNextDwellMs = settings.eyeTurnNextDwellMs || 650;
    this.readerScreenTimeoutMinutes = settings.screenTimeoutMinutes;
    this.applyReaderScreenTimeout();
    this.readerExtendToStatusBar = settings.extendToStatusBar;
    this.readerPreloadEnabled = settings.preloadEnabled;
    this.readerPreloadChapterCount = settings.preloadChapterCount;
    this.readerUseTtsQuickAction = settings.useTtsQuickAction;
    this.readerUseChapterQuickJump = settings.useChapterQuickJump;
    this.readerQuickBookmarkEnabled = settings.quickBookmarkEnabled;
    this.readerHeaderEnabled = settings.readerHeaderEnabled;
    this.readerFooterEnabled = settings.readerFooterEnabled;
    this.readerInfoBarConfigRaw = settings.readerInfoBarConfig;
    this.readerInfoBarLayoutIdentity = this.currentReaderInfoBarLayoutIdentity();
    this.syncReaderInfoBarClock();
    this.readerFontFamily = settings.fontFamily || '';
    this.readerFontFilePath = settings.fontFilePath || '';
    AppStorage.setOrCreate<string>('readerFontSourceName', settings.fontSourceName || '系统默认');
    AppStorage.setOrCreate<string>('readerFontMode', settings.fontMode || (settings.fontFilePath ? 'custom' : 'device'));
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
        next.sourceName = ReaderFontHelper.resolveDisplayName(item.sourceName, next.filePath);
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

  setReaderContent(text: string): void {
    this.content = text;
    this.paginateContent(text);
  }

  // The panel is created each time it opens and positions itself on the current chapter.
  openTocPanel(): void {
    this.showToc = true;
    this.showMenu = false;
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
    return this.hasBackgroundImage() || this.isStackPageTurnAnimation() ||
      this.is3DPageTurnAnimation() ? this.statusBarSafeHeight : 0;
  }

  @Builder
  readerBookmarkPullHint() {
    Row() {
      Row({ space: AppSpacing.MD }) {
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(19)
          .fontColor([this.bookmarkPullHintColor()])
        Text(this.bookmarkPullHintText())
          .fontSize(AppFontSize.BODY)
          .fontWeight(this.bookmarkPullReady ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.bookmarkPullHintColor())
      }
      .height(40)
      .padding({ left: 14, right: 14 })
      .borderRadius(20)
      .backgroundColor(this.readerGlassPanelColor())
      .border({ width: ThemeRuntime.glassBorderWidth(), color: this.readerGlassBorderColor() })
      .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
    }
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.Center)
    .position({ x: 0, y: 0 })
    .translate({ y: this.getTopControlSafePadding() + 8 })
    .opacity(Math.min(1, this.bookmarkPullOffsetY / 36))
    .hitTestBehavior(HitTestMode.None)
  }

  async addCurrentBookmark(): Promise<void> {
    if (!this.book || this.chapters.length === 0) {
      HdsFeedback.showToast('当前没有可添加的阅读位置');
      return;
    }
    const pageIndex = Math.max(0, this.currentPageIndex);
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const existing = await db.getBookmarkAt(this.book.bookUrl, this.currentChapterIndex, pageIndex);
      if (existing) {
        HdsFeedback.showToast('当前阅读位置已添加书签');
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
      HdsFeedback.showToast('书签已添加');
    } catch (e) {
      console.error('添加书签失败:', e);
      HdsFeedback.showToast('添加书签失败');
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
      HdsFeedback.showToast('书签已删除');
    } catch (e) {
      console.error('删除书签失败:', e);
      HdsFeedback.showToast('删除书签失败');
    }
  }

  async jumpToBookmark(bookmark: Bookmark): Promise<void> {
    const targetChapterIndex = this.clampChapterIndex(bookmark.chapterIndex);
    this.showToc = false;
    this.showMenu = false;
    await this.jumpToReaderPositionKeepingTts(targetChapterIndex, Math.max(0, bookmark.pageIndex));
  }

  openSettingsPanel(): void {
    if (this.isReaderComicModeActive()) return;
    this.showReaderActionMenu = false;
    this.settingsPanelTab = 0;
    this.showToc = false;
    this.showTtsVoiceDropdown = false;
    this.showSettings = true;
    this.showMenu = false;
  }

  openReaderComicSettingsPanel(tab: number): void {
    if (!this.isReaderComicModeActive()) return;
    this.showReaderActionMenu = false;
    this.settingsPanelTab = tab;
    this.showToc = false;
    this.showTtsVoiceDropdown = false;
    this.showSettings = true;
    this.showMenu = false;
  }

  openTtsSettingsPanel(): void {
    if (this.isReaderComicModeActive()) return;
    this.showReaderActionMenu = false;
    this.settingsPanelTab = 1;
    this.showToc = false;
    this.showTtsVoiceDropdown = false;
    this.showSettings = true;
    this.showMenu = false;
    this.loadTtsSettingsAndVoices();
  }

  openTypographySettingsPanel(): void {
    if (this.isReaderComicModeActive()) return;
    this.showReaderActionMenu = false;
    this.settingsPanelTab = 2;
    this.showToc = false;
    this.showTtsVoiceDropdown = false;
    this.showSettings = true;
    this.showMenu = false;
  }

  closeSettingsPanelKeepMenu(): void {
    this.flushPendingReaderLayoutChange(true);
    this.showTtsVoiceDropdown = false;
    this.showSettings = false;
    this.showMenu = true;
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
    this.ttsCloudVoiceId = settings.cloudVoiceId;
    this.ttsCustomVoiceOptions = SystemTtsReader.parseCustomVoices(settings.customVoices);
  }

  onTtsCustomVoicesChanged(): void {
    this.ttsCustomVoiceOptions = SystemTtsReader.parseCustomVoices(this.ttsCustomVoices);
    this.ttsSelectedVoiceKey = this.currentTtsVoiceKey();
  }

  normalizeDefaultTtsVoice(): void {
    if (this.ttsOnline === 0 && this.ttsPerson === 0 && !this.ttsStyle &&
      TtsVoiceCatalog.sameLanguage(this.ttsLanguage || 'zh-CN', 'zh-CN')) {
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
    settings.cloudVoiceId = this.ttsCloudVoiceId;
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
      const voiceResults = await Promise.all([
        SystemTtsReader.listAvailableVoices(),
        AccountCommerceApi.fetchTtsCatalog().catch(() => null)
      ]);
      const voices = voiceResults[0] as TtsVoiceOption[];
      const catalog = voiceResults[1];
      this.ttsCloudVoices = catalog ? catalog.voices : [];
      if (catalog && this.ttsCloudVoiceId && !this.findCurrentCloudTtsVoice()) {
        const previousVoiceId = this.ttsCloudVoiceId;
        const fallbackVoice = this.ttsCloudVoices.find((voice: TtsVoiceInfo) => voice.id === 'xiaoyan') ||
          this.ttsCloudVoices[0];
        this.ttsCloudVoiceId = fallbackVoice ? fallbackVoice.id : '';
        console.warn(`[TTS] unsupported cloud voice migrated: ${previousVoiceId} -> ${this.ttsCloudVoiceId}`);
        this.saveTtsSettings();
      }
      if (!catalog && this.ttsCloudVoiceId) {
        const fallbackCloudVoice = new TtsVoiceInfo();
        fallbackCloudVoice.id = this.ttsCloudVoiceId;
        fallbackCloudVoice.name = '云端音色';
        this.ttsCloudVoices = [fallbackCloudVoice];
      }
      this.ttsVoices = TtsVoiceCatalog.applyInstalledOverrides(TtsVoiceCatalog.mergeWithDefault(voices),
        this.ttsInstalledVoiceKeys);
      const currentCloudVoice = this.findCurrentCloudTtsVoice();
      if (currentCloudVoice) {
        this.ttsSelectedVoiceKey = TtsVoiceCatalog.cloudVoiceKey(currentCloudVoice);
        return;
      }
      const currentCustomVoice = this.findCurrentCustomTtsVoice();
      if (currentCustomVoice) {
        this.ttsSelectedVoiceKey = TtsVoiceCatalog.customVoiceKey(currentCustomVoice);
        return;
      }
      const currentVoice = this.findCurrentTtsVoice();
      if (currentVoice && currentVoice.available) {
        this.ttsSelectedVoiceKey = TtsVoiceCatalog.voiceKey(currentVoice);
      } else {
        this.applyTtsVoice(this.firstAvailableTtsVoice(), false);
      }
    } catch (e) {
      this.ttsVoices = [TtsVoiceCatalog.defaultVoice()];
      this.ttsPerson = 0;
      this.ttsOnline = 1;
      this.ttsStyle = '';
      this.ttsLanguage = 'zh-CN';
      this.ttsCustomVoiceId = '';
      this.ttsCloudVoiceId = '';
      this.saveTtsSettings();
      this.ttsSelectedVoiceKey = this.currentTtsVoiceKey();
      console.warn('加载朗读音色失败:', e);
    } finally {
      this.ttsVoicesLoading = false;
      this.publishTtsFloatingVoices();
    }
  }

  firstAvailableTtsVoice(): TtsVoiceOption {
    return this.ttsVoices.find((voice: TtsVoiceOption) => voice.available) || this.ttsVoices[0] ||
      TtsVoiceCatalog.defaultVoice();
  }

  applyTtsVoice(voice: TtsVoiceOption, restartSpeaking: boolean): void {
    if (!voice.available) {
      HdsFeedback.showToast(voice.downloadable ? '请到朗读设置下载该音色' : '该系统音色当前不可用');
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
    this.ttsCloudVoiceId = '';
    this.ttsSelectedVoiceKey = TtsVoiceCatalog.voiceKey(voice);
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
    // Keep the retained/global control panel in sync in the same UI turn. updateDetails() also
    // publishes this value, but that call can be skipped while a mirrored reader page is visible.
    AppStorage.setOrCreate('globalTtsSpeed', nextSpeed);
    this.scheduleTtsSpeedSettingsSave();
    this.updateTtsFloatingSession();
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      this.scheduleTtsSpeedAvSessionUpdate();
      this.scheduleActiveTtsSpeedRestart();
    }
  }

  scheduleActiveTtsSpeedRestart(): void {
    if (this.ttsSpeedRestartTimerId >= 0) {
      clearTimeout(this.ttsSpeedRestartTimerId);
    }
    const serial = ++this.ttsSpeedRestartSerial;
    this.ttsSpeedRestartTimerId = setTimeout(() => {
      this.ttsSpeedRestartTimerId = -1;
      if (serial !== this.ttsSpeedRestartSerial || this.isTtsPaused || this.ttsReader.isPaused() ||
        (!this.isTtsSpeaking && !this.ttsReader.isSpeaking())) {
        return;
      }
      const focusStart = this.readerV2TtsSourceStart >= 0 ? this.readerV2TtsSourceStart :
        (this.ttsLastFocusChunk ? this.readerV2TtsSourceOffset(this.ttsLastFocusChunk.start) :
          this.getCurrentPageStartOffset());
      this.ttsAutoContinue = false;
      this.ttsReadToken++;
      this.ttsReader.stop();
      this.startTtsReadingFromCurrentPosition(false, false, -1, focusStart, true).catch((error: Error) => {
        if (serial !== this.ttsSpeedRestartSerial) return;
        console.warn('实时应用朗读倍速失败:', error);
        this.finishTtsReading();
      });
    }, 100);
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
        this.ttsMediaSession().updatePlaybackState(this.ttsMediaSession().playbackState()).catch((e: Error) => {
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
    if (this.ttsSpeedRestartTimerId >= 0) {
      clearTimeout(this.ttsSpeedRestartTimerId);
      this.ttsSpeedRestartTimerId = -1;
    }
    this.ttsSpeedRestartSerial++;
  }

  currentTtsVoiceKey(): string {
    const cloudVoice = this.findCurrentCloudTtsVoice();
    if (cloudVoice) {
      return TtsVoiceCatalog.cloudVoiceKey(cloudVoice);
    }
    const customVoice = this.findCurrentCustomTtsVoice();
    if (customVoice) {
      return TtsVoiceCatalog.customVoiceKey(customVoice);
    }
    const matched = this.findCurrentTtsVoice();
    return matched ? TtsVoiceCatalog.voiceKey(matched) :
      `${this.ttsPerson}_${this.ttsOnline}_${this.ttsLanguage || 'zh-CN'}_${this.ttsStyle || ''}_`;
  }

  findCurrentTtsVoice(): TtsVoiceOption | undefined {
    return this.ttsVoices.find((voice: TtsVoiceOption) => this.isCurrentTtsVoice(voice));
  }

  isCurrentTtsVoice(voice: TtsVoiceOption): boolean {
    if (this.ttsCustomVoiceId || this.ttsCloudVoiceId) {
      return false;
    }
    return voice.id === this.ttsPerson && voice.online === this.ttsOnline &&
      (voice.style || '') === (this.ttsStyle || '') &&
      TtsVoiceCatalog.sameLanguage(voice.language || 'zh-CN', this.ttsLanguage || 'zh-CN');
  }

  applyCustomTtsVoice(voice: HttpTTS, restartSpeaking: boolean): void {
    if (voice.enabled === false) {
      HdsFeedback.showToast('该自定义音色已禁用');
      return;
    }
    const shouldResume = restartSpeaking && (this.isTtsSpeaking || this.ttsReader.isSpeaking());
    if (shouldResume) {
      this.stopTtsReading();
    }
    this.ttsCustomVoiceId = String(voice.id);
    this.ttsCloudVoiceId = '';
    this.ttsSelectedVoiceKey = TtsVoiceCatalog.customVoiceKey(voice);
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

  isCurrentCustomTtsVoice(voice: HttpTTS): boolean {
    return (this.ttsCustomVoiceId || '') === String(voice.id);
  }

  applyCloudTtsVoice(voice: TtsVoiceInfo, restartSpeaking: boolean): void {
    if (!AccountSessionStore.isLoggedIn()) {
      HdsFeedback.showToast('请先登录华为账号后使用在线音色');
      return;
    }
    const shouldResume = restartSpeaking && (this.isTtsSpeaking || this.ttsReader.isSpeaking());
    if (shouldResume) {
      this.stopTtsReading();
    }
    this.ttsCloudVoiceId = voice.id;
    this.ttsCustomVoiceId = '';
    this.ttsSelectedVoiceKey = TtsVoiceCatalog.cloudVoiceKey(voice);
    this.saveTtsSettings();
    if (shouldResume) {
      this.startTtsReadingFromCurrentPosition(false).catch((e: Error) => {
        console.warn('切换在线朗读音色后恢复失败:', e);
      });
    }
  }

  findCurrentCloudTtsVoice(): TtsVoiceInfo | undefined {
    const selectedId = (this.ttsCloudVoiceId || '').trim();
    if (!selectedId) return undefined;
    return this.ttsCloudVoices.find((voice: TtsVoiceInfo) => voice.id === selectedId);
  }

  isCurrentCloudTtsVoice(voice: TtsVoiceInfo): boolean {
    return (this.ttsCloudVoiceId || '') === voice.id;
  }

  selectableCustomTtsVoices(): HttpTTS[] {
    return this.ttsCustomVoiceOptions.filter((voice: HttpTTS) => voice.enabled !== false);
  }

  selectableSystemTtsVoices(): TtsVoiceOption[] {
    return this.ttsVoices.filter((voice: TtsVoiceOption) => voice.available);
  }

  selectedTtsVoiceTitle(): string {
    const cloudVoice = this.findCurrentCloudTtsVoice();
    if (cloudVoice) {
      return TtsVoiceCatalog.cloudVoiceTitle(cloudVoice);
    }
    const customVoice = this.findCurrentCustomTtsVoice();
    if (customVoice && customVoice.enabled !== false) {
      return TtsVoiceCatalog.customVoiceTitle(customVoice);
    }
    const systemVoice = this.findCurrentTtsVoice();
    if (systemVoice && systemVoice.available) {
      return TtsVoiceCatalog.voiceTitle(systemVoice);
    }
    const customVoices = this.selectableCustomTtsVoices();
    if (this.ttsCloudVoices.length > 0) {
      return TtsVoiceCatalog.cloudVoiceTitle(this.ttsCloudVoices[0]);
    }
    if (customVoices.length > 0) {
      return TtsVoiceCatalog.customVoiceTitle(customVoices[0]);
    }
    const systemVoices = this.selectableSystemTtsVoices();
    return systemVoices.length > 0 ? TtsVoiceCatalog.voiceTitle(systemVoices[0]) : '暂无可用音色';
  }

  ttsQuickVoiceOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const voice of this.ttsCloudVoices) {
      options.push({ value: TtsVoiceCatalog.cloudVoiceTitle(voice) });
    }
    for (const voice of this.selectableCustomTtsVoices()) {
      options.push({ value: TtsVoiceCatalog.customVoiceTitle(voice) });
    }
    for (const voice of this.selectableSystemTtsVoices()) {
      options.push({ value: TtsVoiceCatalog.voiceTitle(voice) });
    }
    if (options.length === 0) {
      options.push({ value: '暂无可用音色' });
    }
    return options;
  }

  ttsQuickVoiceLabels(): string[] {
    return this.ttsQuickVoiceOptions().map((option: SelectOption): string => `${option.value}`);
  }

  ttsQuickVoiceSelectedIndex(): number {
    const cloudIndex = this.ttsCloudVoices.findIndex((voice: TtsVoiceInfo) =>
      this.isCurrentCloudTtsVoice(voice));
    if (cloudIndex >= 0) return cloudIndex;
    const customVoices = this.selectableCustomTtsVoices();
    const customIndex = customVoices.findIndex((voice: HttpTTS) => this.isCurrentCustomTtsVoice(voice));
    if (customIndex >= 0) return this.ttsCloudVoices.length + customIndex;
    const systemVoices = this.selectableSystemTtsVoices();
    const systemIndex = systemVoices.findIndex((voice: TtsVoiceOption) => this.isCurrentTtsVoice(voice));
    if (systemIndex >= 0) return this.ttsCloudVoices.length + customVoices.length + systemIndex;
    return 0;
  }

  selectTtsQuickVoice(index: number): void {
    if (index < 0) return;
    if (index < this.ttsCloudVoices.length) {
      this.applyCloudTtsVoice(this.ttsCloudVoices[index], true);
      return;
    }
    const customVoices = this.selectableCustomTtsVoices();
    const customIndex = index - this.ttsCloudVoices.length;
    if (customIndex < customVoices.length) {
      this.applyCustomTtsVoice(customVoices[customIndex], true);
      return;
    }
    const systemVoices = this.selectableSystemTtsVoices();
    const systemIndex = customIndex - customVoices.length;
    if (systemIndex >= 0 && systemIndex < systemVoices.length) {
      this.applyTtsVoice(systemVoices[systemIndex], true);
    }
  }

  getSubTextColor(): string {
    return this.currentReaderTheme().subTextColor;
  }

  // Reader controls (floating top menu, panels, toolbars) sit on their own
  // light/dark material surface rather than directly on the page, so they need
  // a fixed high-contrast icon color instead of the theme's reader text color.
  readerControlIconColor(): string {
    return this.isReaderThemeDark() ? '#FFFFFFFF' : '#FF202124';
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
    // Keep one stable full-screen coordinate system for every theme. Background artwork may cover the system
    // bars, but its presence must never decide where正文 starts. Dynamically adding/removing TOP here left
    // ArkUI with retained safe-area geometry after a theme switch (plain themes then painted under the status
    // bar). The content column below owns the text inset explicitly.
    return [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM];
  }

  getReaderPageTurnSurfaceSafeAreaEdges(): SafeAreaEdge[] {
    // Simulation and stack paper always animate in the full-screen coordinate system. Their text layer owns
    // the status-bar inset separately, so expanding the paper never changes正文 pagination.
    return (this.isStackPageTurnAnimation() || this.isSimulationPageTurnAnimation() ||
      this.is3DPageTurnAnimation()) &&
      !this.readerExtendToStatusBar ?
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM] : [SafeAreaEdge.BOTTOM];
  }

  getReaderTopSafePadding(): number {
    if (this.isReaderComicModeActive()) {
      return 0;
    }
    // 扩展模式会隐藏状态栏，正文直接从屏幕顶部起算，不为已隐藏的状态栏保留高度。
    if (this.readerExtendToStatusBar) {
      return 0;
    }
    // 仿真与叠页纸张都需要贯穿整个屏幕，因此只由动画页内部补偿文字坐标。普通、滑动和淡入
    // 翻页则在正文容器上统一避让状态栏。
    if (!this.isReaderContinuousScrollSurfaceActive() &&
      (this.isStackPageTurnAnimation() || this.isSimulationPageTurnAnimation() ||
        this.is3DPageTurnAnimation())) {
      return 0;
    }
    return this.statusBarSafeHeight;
  }

  getReaderPageContentTopPadding(): number {
    return !this.isReaderContinuousScrollSurfaceActive() && !this.readerExtendToStatusBar &&
      (this.isStackPageTurnAnimation() || this.isSimulationPageTurnAnimation() ||
        this.is3DPageTurnAnimation()) ?
      this.statusBarSafeHeight : 0;
  }

  getTopControlSafePadding(): number {
    return Math.max(this.statusBarSafeHeight, 32);
  }

  getReaderContentBottomReserve(): number {
    // The reader surface extends through the system navigation area. Reserve the footer line plus its visual
    // lift so the last正文 row cannot be painted underneath metadata moved above the gesture indicator.
    // The footer itself is painted inside the navigation area, just above the gesture indicator. With the
    // footer on,正文 only has to clear the footer; the navigation reserve applies only when there is no footer.
    if (this.isReaderComicModeActive()) return 0;
    if (!this.readerFooterEnabled) return this.getReaderFooterlessBottomReserve();
    return Math.max(8, this.getReaderBottomInfoBarHeight() +
      this.getReaderBottomInfoBarBottomInset() + this.getReaderBottomInfoBarContentGap());
  }

  getReaderBottomInfoBarHeight(): number {
    const infoBarConfig = this.getReaderInfoBarConfig();
    const fallbackHeight = infoBarConfig.footerFontSize + infoBarConfig.footerExtraHeight();
    if (this.readerBottomInfoBarMeasuredHeight > 0) {
      return Math.max(this.readerBottomInfoBarMeasuredHeight, fallbackHeight);
    }
    // Used only for the first layout pass. The rendered Text reports its real one-line box below,
    // including the current device's font scale, and immediately replaces this conversion.
    try {
      return px2vp(Math.max(1, fp2px(fallbackHeight)));
    } catch (_) {
      return fallbackHeight;
    }
  }

  getReaderBottomInfoBarBottomInset(): number {
    // Only lift the footer enough to sit immediately above the gesture indicator. Use half of the reported
    // navigation inset and keep the result in a narrow range so large three-button areas cannot create a gap.
    // 用户设置的页脚上移距离加在这段上抬之上；正文的页脚预留用的是同一个值，页脚上移不会压住末行。
    return this.getReaderGestureIndicatorLift() + this.getReaderInfoBarConfig().footerOffset;
  }

  getReaderGestureIndicatorLift(): number {
    return Math.max(6, Math.min(8, Math.max(0, this.navBarHeight) * 0.5));
  }

  getReaderBottomInfoBarContentGap(): number {
    return this.readerVerticalGapWithinMargin(8, false);
  }

  /**
   * 关闭页脚时正文的底部避让。手势条上方固定留出与页脚相同的上抬距离，导航区其余高度并入下边距，
   * 边距调小时正文可以压进手势区，直到正文末行停在页脚原本的位置。
   */
  getReaderFooterlessBottomReserve(): number {
    const navigationReserve = this.getReaderNavigationBottomReserve();
    if (navigationReserve <= 0) return 0;
    const lift = Math.min(navigationReserve, this.getReaderGestureIndicatorLift());
    return lift + this.readerVerticalGapWithinMargin(navigationReserve - lift, false);
  }

  getReaderV2BottomGuard(): number {
    // Native Paragraph pagination is created before the footer's first area callback. Use the deterministic
    // fallback line height here so measuring the real Text never invalidates a retained pagination session.
    if (this.isReaderComicModeActive()) return 0;
    // 页脚开启时正文只需让开页脚（页脚已经画在手势条上方）；没有页脚时才按导航条高度避让。
    if (!this.readerFooterEnabled) return this.getReaderFooterlessBottomReserve();
    const infoBarConfig = this.getReaderInfoBarConfig();
    let footerHeight = infoBarConfig.footerFontSize;
    try {
      footerHeight = px2vp(Math.max(1, fp2px(infoBarConfig.footerFontSize)));
    } catch (_) {
      footerHeight = infoBarConfig.footerFontSize;
    }
    footerHeight += infoBarConfig.footerExtraHeight();
    return Math.max(8, footerHeight + this.getReaderBottomInfoBarBottomInset() +
      this.getReaderBottomInfoBarContentGap());
  }

  getReaderPaginationBottomInfoBarHeight(): number {
    // Chapter/page metadata is painted as an overlay. Its complete footprint is already included in
    // getReaderContentBottomReserve(), so it must not be added to pagination a second time.
    return 0;
  }

  getReaderBottomInfoBarVisualOffsetY(): number {
    // Lift metadata completely above the gesture-navigation indicator. The matching pagination guard keeps正文
    // clear of the footer at its new visual position.
    return -this.getReaderBottomInfoBarBottomInset();
  }

  readerFloatingBarBottomMargin(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 8;
  }

  readerFloatingBarWidth(): number {
    const viewportWidth = this.pageViewWidth > 0 ? this.pageViewWidth : 360;
    const availableWidth = Math.max(0, viewportWidth - this.readerFloatingBarEdgeInset() * 2);
    if (this.readerUsesSideAnchoredControls()) {
      return Math.min(availableWidth, Math.min(520, Math.max(320, viewportWidth * 0.52)));
    }
    return Math.min(viewportWidth, Math.max(240, availableWidth));
  }

  readerSettingsPanelHeight(): number {
    const viewportHeight = this.pageViewHeight > 0 ? this.pageViewHeight : 720;
    return Math.max(1, Math.min(520, viewportHeight - this.readerFloatingPanelBottomInset() - 12));
  }

  readerChapterTrackColor(): string {
    return this.isReaderThemeDark() ? '#2EFFFFFF' : '#1F000000';
  }

  readerFloatingBarEdgeInset(): number {
    return 18;
  }

  readerUsesSideAnchoredControls(): boolean {
    const viewportWidth = this.pageViewWidth > 0 ? this.pageViewWidth : 360;
    return viewportWidth >= 600;
  }

  readerFloatingBarLeft(): number {
    const viewportWidth = this.pageViewWidth > 0 ? this.pageViewWidth : 360;
    const barWidth = this.readerFloatingBarWidth();
    if (!this.readerUsesSideAnchoredControls()) {
      return Math.max(0, (viewportWidth - barWidth) / 2);
    }
    if (this.readerMenuAnchorSide < 0) {
      return this.readerFloatingBarEdgeInset();
    }
    return Math.max(this.readerFloatingBarEdgeInset(),
      viewportWidth - this.readerFloatingBarEdgeInset() - barWidth);
  }

  readerFloatingBarRight(): number {
    return this.readerFloatingBarLeft() + this.readerFloatingBarWidth();
  }

  readerFloatingBarTranslateX(): number {
    const viewportWidth = this.pageViewWidth > 0 ? this.pageViewWidth : 360;
    const centeredLeft = (viewportWidth - this.readerFloatingBarWidth()) / 2;
    return this.readerFloatingBarLeft() - centeredLeft;
  }

  readerChapterTooltipWidth(): number {
    return Math.min(320, this.readerFloatingBarWidth() * 0.62);
  }

  readerChapterTooltipCenteredLeft(): number {
    const viewportWidth = this.pageViewWidth > 0 ? this.pageViewWidth : 360;
    return (viewportWidth - this.readerChapterTooltipWidth()) / 2;
  }

  readerTtsQuickActionLeft(): number {
    if (this.readerUsesSideAnchoredControls() && this.readerMenuAnchorSide < 0) {
      return this.readerFloatingBarLeft();
    }
    return this.readerFloatingBarRight() - 48;
  }

  readerBottomMenuOverlayHeight(): number {
    return (this.readerUseChapterQuickJump || this.isReaderComicModeActive() ? 120 : 56) +
      this.readerFloatingBarBottomMargin();
  }

  readerBottomActionOverlayHeight(): number {
    return 56 + this.readerFloatingBarBottomMargin();
  }

  readerFloatingPanelBottomInset(): number {
    // 面板底边统一停在底部操作栏上方 4vp。
    return this.readerBottomActionOverlayHeight() + 4;
  }

  readerPanelTransition(): TransitionEffect {
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

  readerSettingsContentTransition(direction: number): TransitionEffect {
    const horizontalOffset = direction < 0 ? -28 : 28;
    const appear = TransitionEffect.translate({ x: horizontalOffset })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 260, curve: Curve.Friction });
    const disappear = TransitionEffect.translate({ x: horizontalOffset * 0.65 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 160, curve: Curve.EaseIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  readerTocPanelHeight(): number {
    const viewportHeight = this.pageViewHeight > 0 ? this.pageViewHeight : 720;
    const availableHeight = Math.max(1, viewportHeight - this.readerFloatingPanelBottomInset() - 12);
    const minimumHeight = Math.min(280, availableHeight);
    return Math.min(availableHeight, Math.max(minimumHeight, viewportHeight * 0.81));
  }

  getReaderContentBottomPadding(): number {
    return Math.max(0, this.getEffectiveReaderMarginBottom() + this.getReaderContentBottomReserve());
  }

  getReaderPaginationViewportHeight(): number {
    // 正文始终避让底部导航条，"正文扩展至状态栏"只影响顶部，所以分页视口就是实测的分页区域。
    // 导航条那一段由 getReaderNavigationBottomReserve() 在视口内部预留；纸张背景仍会铺到屏幕底部。
    return Math.max(1, this.pageViewHeight);
  }

  getReaderBackgroundViewportHeight(): number {
    // pageViewHeight excludes the explicit text-only status-bar inset when extension is disabled,
    // but already includes it in extended mode. Reuse the page-turn viewport calculation so the
    // static paper, simulation snapshots and curl canvas always fit the exact same full-screen rect.
    return Math.max(1, this.getPageTurnHeight());
  }

  getEffectiveReaderLineHeight(): number {
    return this.readerFontSize + Math.max(0, this.readerLineHeight);
  }

  getReaderPageColumnWidth(): number {
    if (!this.isLandscapeDoublePageActive()) return Math.max(1, this.pageViewWidth);
    // The divider participates in Row layout. Measuring each leaf as exactly half of the spread makes
    // pagination up to 0.5vp wider than the real Text node and can wrap one extra line at render time.
    return Math.max(1, (this.pageViewWidth - READER_DOUBLE_PAGE_DIVIDER_WIDTH) / 2);
  }

  getReaderDoublePageRightOrigin(): number {
    return this.getReaderPageColumnWidth() + READER_DOUBLE_PAGE_DIVIDER_WIDTH;
  }

  readerTextAlignValue(): TextAlign {
    if (this.readerTextAlign === 'start') return TextAlign.Start;
    if (this.readerTextAlign === 'end') return TextAlign.End;
    return TextAlign.JUSTIFY;
  }

  getReaderAdaptiveLetterSpacing(): number {
    const availableWidth = Math.max(1,
      this.getReaderPageColumnWidth() - this.getEffectiveReaderMarginLeft() - this.getEffectiveReaderMarginRight());
    try {
      const widthPx = vp2px(availableWidth);
      // ArkUI ultimately lays a component out on physical pixels, while graphics.text accepts a floating
      // constraint. Distribute only the discarded sub-pixel fraction across a typical line. JUSTIFY still
      // performs the visible horizontal alignment; this tiny non-positive correction keeps both breakers
      // on the same line without changing the user's chosen font size.
      const snappedWidthPx = Math.floor(widthPx);
      const charsPerLine = Math.max(8, Math.floor(availableWidth / Math.max(1, this.readerFontSize)));
      const adaptiveCorrection = Math.max(-0.08, Math.min(0, px2fp((snappedWidthPx - widthPx) / charsPerLine)));
      return this.readerLetterSpacing + adaptiveCorrection;
    } catch (_) {
      return this.readerLetterSpacing;
    }
  }

  onReadLayoutChanged(): void {
    if (this.readerEntryInitializing || this.readerLayoutCommitInProgress) return;
    this.scheduleReaderLayoutChange();
  }

  onReaderChromeChanged(): void {
    const layoutIdentity = this.currentReaderInfoBarLayoutIdentity();
    const layoutChanged = layoutIdentity !== this.readerInfoBarLayoutIdentity;
    this.readerInfoBarLayoutIdentity = layoutIdentity;
    this.syncReaderInfoBarClock();
    if (this.readerEntryInitializing) return;
    if (!layoutChanged) {
      // 只换了显示内容或颜色、边距等不占正文高度的外观，不需要重新分页。
      return;
    }
    const readingOffset = this.getReaderStableReflowOffset();
    this.readerTypographyRestoreOffset = readingOffset;
    this.invalidateReaderTypographyLayout();
    this.refreshReaderTextRender();
    if (this.content) {
      this.paginateContent(this.content);
      if (this.hasPagedReaderArea() && this.pagedContentText) {
        this.currentPageIndex = this.normalizeReaderSpreadPageIndex(
          this.findPageIndexByOffset(readingOffset));
        this.syncCurrentPageText();
        // 页眉/页脚设置会清空 V2 的 retained controller。强制发布当前页，避免 NodeContainer
        // 在下一次翻页前继续绘制设置变更前的旧正文。
        this.forceCurrentReaderPageRender();
        this.refreshCurrentReaderV2RetainedPages(true);
      }
    }
    this.preloadNextChapterPaginationLater();
    this.preloadPreviousChapterPaginationLater();
    this.saveReadingProgress();
  }

  scheduleReaderLayoutChange(): void {
    if (this.readerLayoutApplyTimerId >= 0) {
      clearTimeout(this.readerLayoutApplyTimerId);
    }
    this.readerLayoutApplyTimerId = setTimeout(() => {
      this.readerLayoutApplyTimerId = -1;
      this.applyPendingReaderLayoutChange();
    }, 1000);
  }

  scheduleReaderTypographyChange(): void {
    if (this.readerLayoutApplyTimerId >= 0) {
      clearTimeout(this.readerLayoutApplyTimerId);
    }
    this.readerLayoutApplyTimerId = setTimeout(() => {
      this.readerLayoutApplyTimerId = -1;
      this.commitReaderTypographyDraft();
      this.applyPendingReaderLayoutChange();
    }, 120);
  }

  applyPendingReaderLayoutChange(): void {
    const readingOffset = ReaderParagraphIndent.remapOffset(
      this.pagedContentText, this.getPagedSourceText(), this.getReaderStableReflowOffset());
    this.readerTypographyRestoreOffset = readingOffset;
    this.invalidateReaderTypographyLayout();
    this.refreshReaderTextRender();
    this.paginateContent(this.content);
    this.scheduleReaderLayoutStabilization(readingOffset);
    this.preloadNextChapterPaginationLater();
    this.saveReaderLayoutSettings();
    this.saveReadConfig();
    this.saveReadingProgress();
  }

  scheduleReaderLayoutStabilization(readingOffset: number): void {
    if (this.readerLayoutStabilizeTimerId >= 0) clearTimeout(this.readerLayoutStabilizeTimerId);
    const chapterIndex = this.currentChapterIndex;
    const bookUrl = this.book?.bookUrl || this.bookUrl;
    const identity = `${this.readerTypographyCacheIdentity()}_${this.pageViewWidth}_` +
      `${this.getReaderPaginationViewportHeight()}_${this.readerExtendToStatusBar}`;
    this.readerLayoutStabilizeTimerId = setTimeout(() => {
      this.readerLayoutStabilizeTimerId = -1;
      const currentIdentity = `${this.readerTypographyCacheIdentity()}_${this.pageViewWidth}_` +
        `${this.getReaderPaginationViewportHeight()}_${this.readerExtendToStatusBar}`;
      if (!this.readerPageVisible || this.currentChapterIndex !== chapterIndex ||
        (this.book?.bookUrl || this.bookUrl) !== bookUrl || currentIdentity !== identity) return;
      this.readerTypographyRestoreOffset = readingOffset;
      this.invalidateReaderTypographyLayout();
      this.refreshReaderTextRender();
      this.paginateContent(this.content);
      this.preloadNextChapterPaginationLater();
      this.preloadPreviousChapterPaginationLater();
    }, 80);
  }

  invalidateReaderTypographyLayout(): void {
    // A typography update changes both wrapping and component heights. Invalidate every derived layer and stop
    // cooperative batches created with the previous settings; otherwise an old background batch can publish its
    // page array after the live preview has already switched to the new geometry.
    this.finishPageTurnAnimation(false);
    // The retained NodeContainer does not reliably adopt a replacement NodeController while its keyed ForEach
    // host stays unchanged. Since the controllers below are deliberately detached, remount that host as part of
    // the same transaction; otherwise a theme/background change can leave the visible node bound to the cleared
    // controller until the next page turn publishes another surface.
    this.readerV2SurfaceGeneration++;
    this.readerPaginationWorkSerial++;
    this.adjacentPaginationPreloadSerial++;
    this.previousPaginationPreloadSerial++;
    this.readerPaginationCache.clear();
    this.readerV2PageSetCache.clear();
    this.readerV2DocumentCache.clear();
    this.readerV2SelectionStyledTextCache.clear();
    this.readerV2ActiveDocument = null;
    this.readerV2ActiveSnapshot = null;
    for (const controller of this.readerV2Controllers.values()) controller.updatePage(null);
    this.readerV2Controllers.clear();
    const selectableKeys = Array.from(this.readerSelectableTextControllers.keys());
    for (const key of selectableKeys) {
      if (key.startsWith('reader_v2_native_page_')) this.readerSelectableTextControllers.delete(key);
    }
    this.readerParagraphMetricsCache.clear();
    this.readerAdaptiveLineHeightCache.clear();
    this.readerTextParagraphsCache.clear();
    this.pageTurnPreviewKey = '';
    this.pageTurnPreviewLoadingKey = '';
    this.clearPendingReaderSourceActionBounds();
    this.readerSourceActionAreas.clear();
    this.readerSourceActionScrollOffsets.clear();
  }

  flushPendingReaderLayoutChange(repaginate: boolean = true): void {
    if (this.readerLayoutApplyTimerId < 0 && !this.readerTypographyDraftPending) return;
    if (this.readerLayoutApplyTimerId >= 0) clearTimeout(this.readerLayoutApplyTimerId);
    this.readerLayoutApplyTimerId = -1;
    this.commitReaderTypographyDraft();
    if (repaginate && this.readerPageVisible) {
      this.applyPendingReaderLayoutChange();
      return;
    }
    this.saveReaderLayoutSettings();
    this.saveReadConfig();
  }

  refreshReaderTextRender(): void {
    this.pageRenderVersion++;
    this.pageTurnIncomingRenderVersion++;
  }

  forceCurrentReaderPageRender(): void {
    this.chapterJumpRenderGeneration++;
    this.pageRenderVersion++;
  }

  private cancelReaderPaginationWork(releaseNativeCaches: boolean): void {
    this.readerPaginationWorkSerial++;
    this.adjacentPaginationPreloadSerial++;
    this.previousPaginationPreloadSerial++;
    this.readerPaginationCache.clear();
    if (!releaseNativeCaches) return;
    this.readerV2PageSetCache.clear();
    this.readerV2DocumentCache.clear();
    this.readerV2SelectionStyledTextCache.clear();
    this.readerV2ActiveDocument = null;
    this.readerV2ActiveSnapshot = null;
    for (const controller of this.readerV2Controllers.values()) controller.updatePage(null);
    this.readerV2Controllers.clear();
    const selectableKeys = Array.from(this.readerSelectableTextControllers.keys());
    for (const key of selectableKeys) {
      if (key.startsWith('reader_v2_native_page_')) this.readerSelectableTextControllers.delete(key);
    }
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

  onSystemFontRevisionChanged(): void {
    this.refreshReaderTextRender();
    this.onReadLayoutChanged();
  }

  onReaderExtendToStatusBarChanged(): void {
    this.scheduleReaderExtendLayoutRefresh();
  }

  onReaderScreenOrientationChanged(): void {
    if (this.readerPageVisible) this.applyReaderScreenOrientation();
  }

  applyReaderScreenOrientation(orientation: string = this.readerScreenOrientation): void {
    const normalized = ReaderSettingsStore.normalizeScreenOrientation(orientation);
    const serial = ++this.readerScreenOrientationSerial;
    // “跟随系统”需要显式启用自动旋转；UNSPECIFIED 在直板手机上通常固定竖屏。
    let preferred = window.Orientation.AUTO_ROTATION_RESTRICTED;
    if (normalized === ReaderSettingsStore.SCREEN_ORIENTATION_PORTRAIT) {
      preferred = window.Orientation.PORTRAIT;
    } else if (normalized === ReaderSettingsStore.SCREEN_ORIENTATION_LANDSCAPE) {
      preferred = window.Orientation.LANDSCAPE;
    }
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      if (serial !== this.readerScreenOrientationSerial) return;
      return mainWindow.setPreferredOrientation(preferred);
    }).catch((error: Error) => {
      console.warn('应用阅读屏幕方向失败:', error);
    });
  }

  resetReaderScreenOrientation(): void {
    this.applyReaderScreenOrientation(ReaderSettingsStore.SCREEN_ORIENTATION_SYSTEM);
  }

  syncReaderPageHeightForContentTopPadding(): void {
    const nextTopPadding = this.getReaderPageContentTopPadding();
    // The system-bar switch itself changes the reader area's measured height. Do not pre-add/subtract the
    // same inset here: onAreaChange will publish the new text viewport, and applying both adjustments makes
    // extended mode exactly one status-bar too tall (causing the last paragraph to be clipped).
    this.readerPageContentTopPaddingSnapshot = nextTopPadding;
  }

  scheduleReaderExtendLayoutRefresh(readingOffset: number = -1): void {
    if (readingOffset >= 0 && this.readerExtendLayoutReadingOffset < 0) {
      this.readerExtendLayoutReadingOffset = readingOffset;
    }
    this.enterReaderImmersive();
    this.syncReaderPageHeightForContentTopPadding();
    if (this.readerEntryInitializing || !this.content || !this.hasPagedReaderArea()) return;

    // A system-bar mode change rebuilds the safe-area geometry asynchronously. Stop and invalidate
    // every old curl surface immediately; otherwise a gesture started before the new area arrives can
    // combine the old wallpaper snapshot with the new text viewport for one visibly jumping frame.
    this.invalidateReaderTypographyLayout();
    this.refreshReaderTextRender();

    if (this.readerExtendLayoutRefreshTimerId >= 0) {
      clearTimeout(this.readerExtendLayoutRefreshTimerId);
    }
    this.readerExtendLayoutRefreshTimerId = setTimeout(() => {
      this.readerExtendLayoutRefreshTimerId = -1;
      if (!this.readerPageVisible || !this.content) {
        this.readerExtendLayoutReadingOffset = -1;
        return;
      }
      const restoreOffset = this.readerExtendLayoutReadingOffset >= 0 ?
        this.readerExtendLayoutReadingOffset : this.getReaderStableReflowOffset();
      this.readerExtendLayoutReadingOffset = -1;
      this.readerTypographyRestoreOffset = restoreOffset;
      this.invalidateReaderTypographyLayout();
      this.refreshReaderTextRender();
      this.paginateContent(this.content);
      this.currentPageIndex = this.normalizeReaderSpreadPageIndex(this.findPageIndexByOffset(restoreOffset));
      this.syncCurrentPageText();
      this.scheduleReaderLayoutStabilization(restoreOffset);
      this.preloadNextChapterPaginationLater();
      this.preloadPreviousChapterPaginationLater();
      this.saveReadingProgress();
    }, 80);
  }

  onReaderThemeChanged(): void {
    this.scheduleReaderThemeRefresh();
  }

  onReaderColorModeChanged(): void {
    if (!this.readerEntryInitializing) this.flushPendingReaderLayoutChange(false);
    this.scheduleReaderThemeRefresh();
  }

  private scheduleReaderThemeRefresh(): void {
    if (this.readerThemeRefreshOffset < 0) {
      this.readerThemeRefreshOffset = this.getReaderStableReflowOffset();
    }
    if (this.readerThemeRefreshTimerId >= 0) {
      clearTimeout(this.readerThemeRefreshTimerId);
    }
    // EntryAbility republishes appDarkMode and themeRevision as two observable updates while applying
    // a color mode. Debounce one frame so both updates share one pagination and one retained-page rebuild.
    this.readerThemeRefreshTimerId = setTimeout(() => {
      this.readerThemeRefreshTimerId = -1;
      const readingOffset = this.readerThemeRefreshOffset >= 0 ?
        this.readerThemeRefreshOffset : this.getReaderStableReflowOffset();
      this.readerThemeRefreshOffset = -1;
      if (!this.readerPageVisible || !this.content) {
        return;
      }
      this.enterReaderImmersive();
      this.readerTypographyRestoreOffset = readingOffset;
      this.invalidateReaderTypographyLayout();
      this.refreshReaderTextRender();
      this.paginateContent(this.content);
      this.scheduleReaderLayoutStabilization(readingOffset);
      this.saveReadingProgress();
      if (this.showReaderCommentPanel) {
        this.readerCommentPanelLoadSerial++;
        this.readerCommentPanelLoading = true;
        this.readerCommentPanelError = false;
        this.scheduleReaderCommentPanelHostReady(0);
      }
      this.onTtsCoverSettingsChanged();
    }, 32);
  }

  onTtsCoverSettingsChanged(): void {
    if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking() && !this.ttsMediaSession().hasSession()) {
      this.ttsMediaSession().refreshMediaImage().catch((e: Error) => {
        console.warn('刷新朗读媒体封面失败:', e);
      });
      return;
    }
    this.ttsMediaSession().refreshMediaImage().then(() => {
      return this.ttsMediaSession().updatePlaybackState(
        this.isTtsSpeaking || this.ttsReader.isSpeaking() ?
          this.ttsMediaSession().playbackState() : avSession.PlaybackState.PLAYBACK_STATE_STOP
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
    if (!this.readerVolumeTurnPage || !this.readerPageVisible || this.isTtsSpeaking ||
      this.ttsReader.isSpeaking() || ReaderTtsFloatingSession.isActive()) {
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
    if (!this.readerVolumeTurnPage || !this.readerPageVisible || this.isTtsSpeaking ||
      this.ttsReader.isSpeaking() || ReaderTtsFloatingSession.isActive() || this.showMenu || this.showToc ||
      this.showSettings || this.isLoading || this.chapters.length === 0) {
      return;
    }
    if (this.isReaderContinuousScrollSurfaceActive()) {
      this.scrollReaderComicByPage(direction);
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
    try {
      await this.jumpToReaderPositionKeepingTts(normalizedIndex, 0);
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

  restorePendingPageIndex(paginationComplete: boolean = true): void {
    if (this.pendingRestorePageIndex < 0) {
      return;
    }
    const maxPage = Math.max(0, this.contentPages.length - 1);
    if (!paginationComplete && this.pendingRestorePageIndex > maxPage) {
      return;
    }
    this.currentPageIndex = this.normalizeReaderSpreadPageIndex(
      Math.max(0, Math.min(this.pendingRestorePageIndex, maxPage))
    );
    this.pendingRestorePageIndex = -1;
    this.readerProgressRestoreConfirmed = true;
  }

  canSaveReadingProgress(): boolean {
    if (this.isLoading || this.isPagedReaderAwaitingPagination() || this.pendingRestorePageIndex >= 0) {
      return false;
    }
    return this.pageViewWidth > 0 && this.pageViewHeight > 0 && this.contentPages.length > 0;
  }

  savedReaderProgressOffset(book: Book | null, chapterIndex: number): number {
    if (!book) return -1;
    const chapterRaw = book.getVariable(READER_PROGRESS_OFFSET_CHAPTER_KEY);
    const offsetRaw = book.getVariable(READER_PROGRESS_OFFSET_KEY);
    if (!chapterRaw || !offsetRaw) return -1;
    const storedChapter = Number(chapterRaw);
    const storedOffset = Number(offsetRaw);
    if (!Number.isFinite(storedChapter) || Math.round(storedChapter) !== chapterIndex ||
      !Number.isFinite(storedOffset) || storedOffset < 0) {
      return -1;
    }
    return Math.round(storedOffset);
  }

  committedLocalPageTurnCheckpointPageIndex(): number {
    // During an animated turn the incoming page is already the committed visual destination, while
    // currentPageIndex is intentionally updated only after the motion finishes. Home can freeze that handoff for
    // long enough that a lifecycle checkpoint would otherwise persist the page behind the animation (often page
    // zero). Only trust a same-chapter target owned by the current immutable pagination snapshot.
    if (!this.isPageTurning || !this.pageTurnIncomingText ||
      this.pageTurnIncomingChapterIndex !== this.currentChapterIndex) {
      return -1;
    }
    if (this.pageTurnIncomingDocumentSource &&
      this.pageTurnIncomingDocumentSource !== this.pagedContentText) {
      return -1;
    }
    const pageIndex = this.normalizeReaderSpreadPageIndex(this.pageTurnIncomingPageIndex);
    if (pageIndex < 0 || pageIndex >= this.contentPages.length) {
      return -1;
    }
    return pageIndex;
  }

  settleCommittedLocalPageTurnForCheckpoint(): void {
    const targetPageIndex = this.committedLocalPageTurnCheckpointPageIndex();
    if (targetPageIndex < 0) return;
    // Backgrounding may suspend the animation timer indefinitely. Settle the already-accepted local turn now so
    // both a retained reader surface and a cold restart agree with the lifecycle checkpoint. The suspended async
    // turn can safely apply the same captured target again when the app resumes.
    this.currentPageIndex = targetPageIndex;
    this.readerProgressRestoreConfirmed = true;
    this.commitVisibleCurrentPageText(this.getPageText(targetPageIndex));
    this.finishPageTurnAnimation(false);
  }

  async saveReadingProgress(notifyShelf: boolean = false): Promise<void> {
    if (!this.book || this.chapters.length === 0) {
      return;
    }
    // A retained reader page can receive aboutToDisappear after its replacement has already attached. Its
    // snapshot belongs to the old visual page even when both instances opened the same book URL.
    if (!ReaderProgressCheckpoint.canWrite(this.ttsFloatingSessionOwnerId)) {
      console.info('[ReaderProgress] ignored save from superseded reader page');
      return;
    }
    const engine = this.readerEngine();
    const stableVisibleProgress = this.canSaveReadingProgress();
    let chapterIndex = this.clampChapterIndex(this.currentChapterIndex);
    let pageIndex = Math.max(0, Math.min(this.currentPageIndex, Math.max(0, this.contentPages.length - 1)));
    let characterOffset = Math.max(0, this.getPageStartOffset(pageIndex));
    let progressPageCount = this.currentChapterProgressPageCount();
    let lastReadPageText = this.getShelfLastReadPageText(pageIndex);
    let lastReadPageImage = this.getShelfLastReadPageImage(pageIndex);
    const completedVisibleProgress = stableVisibleProgress && this.readerInitialPageReady &&
      this.pendingRestorePageIndex < 0 && this.readerTypographyRestoreOffset < 0 &&
      this.isCurrentReaderPaginationComplete();
    if (stableVisibleProgress && (this.readerProgressRestoreConfirmed || completedVisibleProgress)) {
      // Keep an immutable visible-position anchor. During a typography/source-interaction rebuild the incremental
      // paginator temporarily owns only its first pages and marks pendingRestorePageIndex. A lifecycle checkpoint
      // in that window must save the page the user actually saw, not zero or an older database value.
      this.readerProgressAnchorChapterIndex = chapterIndex;
      this.readerProgressAnchorPageIndex = pageIndex;
      this.readerProgressAnchorOffset = characterOffset;
      this.readerProgressAnchorPageCount = progressPageCount;
      this.readerProgressAnchorPageText = lastReadPageText;
      this.readerProgressAnchorPageImage = lastReadPageImage;
    } else if (this.readerProgressAnchorChapterIndex >= 0) {
      chapterIndex = this.clampChapterIndex(this.readerProgressAnchorChapterIndex);
      pageIndex = Math.max(0, this.readerProgressAnchorPageIndex);
      characterOffset = this.readerProgressAnchorOffset;
      progressPageCount = Math.max(1, this.readerProgressAnchorPageCount);
      lastReadPageText = this.readerProgressAnchorPageText;
      lastReadPageImage = this.readerProgressAnchorPageImage;
    } else {
      return;
    }
    if (!Book.hasStartedReading(this.book) && chapterIndex <= 0 && pageIndex <= 0) {
      if (engine.book?.bookUrl === this.book.bookUrl) {
        engine.curIdx = chapterIndex;
        engine.curPos = pageIndex;
      }
      return;
    }
    this.book.durChapterIndex = chapterIndex;
    this.book.durChapterPos = pageIndex;
    const now = Date.now();
    this.book.durChapterTitle = this.chapters[chapterIndex]?.title || this.book.durChapterTitle;
    this.book.durChapterTime = now;
    this.book.putVariable('readStarted', '1');
    this.book.putVariable('lastReadTime', `${now}`);
    this.book.putVariable('readProgressChapterIndex', `${chapterIndex}`);
    this.book.putVariable('readProgressPageCount', `${progressPageCount}`);
    if (characterOffset >= 0) {
      this.book.putVariable(READER_PROGRESS_OFFSET_KEY, `${characterOffset}`);
      this.book.putVariable(READER_PROGRESS_OFFSET_CHAPTER_KEY, `${chapterIndex}`);
    }
    this.book.putVariable('lastReadPageText', lastReadPageText);
    this.book.putVariable('lastReadPageImage', lastReadPageImage);
    // The old reader page can finish an asynchronous save after the next book has
    // already opened. Never let that stale page replace the singleton engine's book.
    if (engine.book?.bookUrl === this.book.bookUrl) {
      engine.curIdx = chapterIndex;
      engine.curPos = pageIndex;
      engine.book = this.book;
    }
    const bookUrl = this.book.bookUrl;
    const chapterTitle = this.book.durChapterTitle;
    const variable = this.book.variable;
    const syncRelevant = !!this.book.origin && this.book.origin !== 'local';
    const shouldRefreshRecentCard = chapterIndex !== this.lastRecentReadCardChapterIndex;
    this.lastRecentReadCardChapterIndex = chapterIndex;
    const previous = this.readingProgressSaveQueue.catch(() => {
    });
    const next = previous.then(async () => {
      if (!ReaderProgressCheckpoint.canWrite(this.ttsFloatingSessionOwnerId)) {
        console.info('[ReaderProgress] ignored queued save from superseded reader page');
        return;
      }
      const db = AppDatabase.getInstance();
      await db.updateBookReadingProgress(
        bookUrl, chapterTitle, chapterIndex, pageIndex, now, variable, syncRelevant);
      // Page turns are saved frequently, while the retained bookshelf page is still alive underneath the reader.
      // Publishing shelfUpdateTime here would rebuild every hidden shelf card and decode all theme cover fallbacks on
      // every turn. Persist the progress immediately, but notify the shelf only when leaving the reader.
      if (notifyShelf) AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      if (notifyShelf || shouldRefreshRecentCard) {
        this.reloadRecentReadCardLater(shouldRefreshRecentCard);
      }
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
      await db.updateBook(this.book, false);
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
  readerInfoBarAccentLine(progress: boolean) {
    if (progress) {
      Progress({ value: this.getReaderInfoProgressValue(), total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(2)
        .color(this.accentColor())
        .backgroundColor(this.readerChapterTrackColor())
    } else {
      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor(this.getSubTextColor())
        .opacity(0.35)
    }
  }

  @Builder
  readerBottomInfoBar() {
    Column({ space: 3 }) {
      if (this.getReaderInfoBarConfig().progressBar === ReaderInfoProgressBar.FOOTER) {
        this.readerInfoBarAccentLine(true)
      } else if (this.getReaderInfoBarConfig().footerDivider) {
        this.readerInfoBarAccentLine(false)
      }
      ReaderInfoBarRow({
        leftText: this.getReaderInfoSlotText(this.getReaderInfoBarConfig().footerLeft),
        centerText: this.getReaderInfoSlotText(this.getReaderInfoBarConfig().footerCenter),
        rightText: this.getReaderInfoSlotText(this.getReaderInfoBarConfig().footerRight),
        leftBattery: this.getReaderInfoSlotBattery(this.getReaderInfoBarConfig().footerLeft),
        centerBattery: this.getReaderInfoSlotBattery(this.getReaderInfoBarConfig().footerCenter),
        rightBattery: this.getReaderInfoSlotBattery(this.getReaderInfoBarConfig().footerRight),
        textSize: this.getReaderInfoBarConfig().footerFontSize,
        textColor: this.getReaderInfoBarConfig().textColor(false, this.getSubTextColor()),
        textOpacity: this.getReaderInfoBarConfig().footerOpacity / 100
      })
    }
    .width('100%')
    .padding({
      left: this.getReaderInfoBarSidePadding(false, true),
      right: this.getReaderInfoBarSidePadding(false, false),
      top: 0,
      bottom: 0
    })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Transparent)
    .translate({ y: this.getReaderBottomInfoBarVisualOffsetY() })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.rememberReaderBottomInfoBarHeight(newValue);
    })
  }

  @Builder
  readerHeaderInfoBar() {
    Column({ space: 3 }) {
      Row() {
        ReaderInfoBarRow({
          leftText: this.getReaderInfoSlotText(this.getReaderInfoBarConfig().headerLeft),
          centerText: this.getReaderInfoSlotText(this.getReaderInfoBarConfig().headerCenter),
          rightText: this.getReaderInfoSlotText(this.getReaderInfoBarConfig().headerRight),
          leftBattery: this.getReaderInfoSlotBattery(this.getReaderInfoBarConfig().headerLeft),
          centerBattery: this.getReaderInfoSlotBattery(this.getReaderInfoBarConfig().headerCenter),
          rightBattery: this.getReaderInfoSlotBattery(this.getReaderInfoBarConfig().headerRight),
          textSize: this.getReaderInfoBarConfig().headerFontSize,
          textColor: this.getReaderInfoBarConfig().textColor(true, this.getSubTextColor()),
          textOpacity: this.getReaderInfoBarConfig().headerOpacity / 100
        })
      }
      .width('100%')
      .height(this.getReaderHeaderInfoBarHeight())
      .alignItems(VerticalAlign.Center)

      if (this.getReaderInfoBarConfig().progressBar === ReaderInfoProgressBar.HEADER) {
        this.readerInfoBarAccentLine(true)
      } else if (this.getReaderInfoBarConfig().headerDivider) {
        this.readerInfoBarAccentLine(false)
      }
    }
    .width('100%')
    .padding({
      top: this.getReaderHeaderOverlayTopInset(),
      left: this.getReaderInfoBarSidePadding(true, true),
      right: this.getReaderInfoBarSidePadding(true, false)
    })
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.None)
  }

  currentChapterProgressPageCount(): number {
    if (this.contentPages.length === 0) {
      return 0;
    }
    if (this.hasPagedReaderArea() && this.pagedContentText) {
      const pagination = this.getCachedReaderPagination(this.currentChapterIndex, this.pagedContentText);
      if (pagination && !pagination.complete) {
        // 增量分页尚未完成时，总页数并不可靠；下一次翻页或离开页面时会重新保存。
        return 0;
      }
    }
    return this.contentPages.length;
  }

  getShelfLastReadPageText(pageIndex: number): string {
    const pageText = ReaderActionMarker.strip(
      LocalBookService.stripEpubImageMarkers(this.getPageText(pageIndex) || '', false), false
    )
      .replace(/\r\n?/g, '\n')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    return (pageText || '（图片页）').substring(0, 1600);
  }

  getShelfLastReadPageImage(pageIndex: number): string {
    const page = (this.getPageText(pageIndex) || '').trim();
    return this.isReaderImageOnlyPage(page) ? this.getReaderEpubImageUri(page) : '';
  }

  onReaderLandscapeDoublePageChanged(): void {
    const readingOffset = this.getReaderStableReflowOffset();
    this.finishPageTurnAnimation();
    this.readerPaginationCache.clear();
    this.paginateContent(this.content);
    this.currentPageIndex = this.normalizeReaderSpreadPageIndex(this.findPageIndexByOffset(readingOffset));
    this.syncCurrentPageText();
    this.refreshReaderTextRender();
    this.saveReadingProgress();
    this.saveReadConfig();
  }

  setTtsSleepTimer(minutes: number): void {
    this.clearTtsSleepTimer();
    if (minutes <= 0) {
      HdsFeedback.showToast('已关闭朗读定时');
      return;
    }
    this.ttsSleepTimerMinutes = minutes;
    this.ttsSleepTimerRemainingSeconds = minutes * 60;
    this.updateTtsFloatingSession();
    this.ttsSleepTimerEndAt = Date.now() + minutes * 60 * 1000;
    this.ttsSleepTimerId = setInterval(() => {
      const remaining = Math.max(0, Math.ceil((this.ttsSleepTimerEndAt - Date.now()) / 1000));
      this.ttsSleepTimerRemainingSeconds = remaining;
      ReaderTtsFloatingSession.updateTimer(
        this.ttsFloatingSessionOwnerId, this.ttsSleepTimerMinutes, remaining);
      if (remaining <= 0) {
        this.clearTtsSleepTimer();
        this.stopTtsReading();
        HdsFeedback.showToast('朗读定时结束，已停止朗读');
      }
    }, 1000);
    HdsFeedback.showToast(`将在 ${minutes} 分钟后停止朗读`);
  }

  clearTtsSleepTimer(): void {
    if (this.ttsSleepTimerId >= 0) {
      clearInterval(this.ttsSleepTimerId);
      this.ttsSleepTimerId = -1;
    }
    this.ttsSleepTimerEndAt = 0;
    this.ttsSleepTimerMinutes = 0;
    this.ttsSleepTimerRemainingSeconds = 0;
    this.updateTtsFloatingSession();
  }

  canPlayPreviousTtsChapter(): boolean {
    return this.chapters.length > 0 && this.currentChapterIndex > 0;
  }

  canPlayNextTtsChapter(): boolean {
    return this.chapters.length > 0 && this.currentChapterIndex < this.chapters.length - 1;
  }

  @Builder
  readerTapLayer() {
    if (this.readerEffectivePageTurnMode() === 2) {
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
      .onAreaChange((_oldValue: Area, newValue: Area) => this.rememberReaderTapLayerArea(newValue))
      .onTouch((event: TouchEvent) => {
        this.handleReaderTouch(event);
      })
      .parallelGesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.All, distance: this.readerTapSlop })
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
            }),
          LongPressGesture({ duration: 600 })
            .onAction((event: GestureEvent) => {
              this.selectReaderTextAtGlobalPoint(event);
            })
        )
      )
    } else if (this.readerEffectivePageTurnMode() === 0) {
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
      .onAreaChange((_oldValue: Area, newValue: Area) => this.rememberReaderTapLayerArea(newValue))
      .onTouch((event: TouchEvent) => {
        this.handleReaderTouch(event);
      })
      .parallelGesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: this.isVerticalPageTurnAnimation() ?
            PanDirection.Vertical : PanDirection.Horizontal, distance: this.readerTapSlop })
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
            }),
          LongPressGesture({ duration: 600 })
            .onAction((event: GestureEvent) => {
              this.selectReaderTextAtGlobalPoint(event);
            })
        )
      )
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onAreaChange((_oldValue: Area, newValue: Area) => this.rememberReaderTapLayerArea(newValue))
        .onClick(() => {
          if (this.consumeSuppressedReaderTapClick()) {
            return;
          }
          if (this.readerEffectivePageTurnMode() === 1 && !this.showMenu && !this.showToc && !this.showSettings) {
            this.showMenu = true;
          }
        })
        .onTouch((event: TouchEvent) => {
          this.handleReaderTouch(event);
        })
        .parallelGesture(
          GestureGroup(GestureMode.Exclusive,
            PanGesture({ direction: PanDirection.All, distance: this.readerTapSlop })
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
              }),
            LongPressGesture({ duration: 600 })
              .onAction((event: GestureEvent) => {
                this.selectReaderTextAtGlobalPoint(event);
              })
          )
        )
    }
  }

  canHandleReaderPageTurnPan(): boolean {
    return !this.showMenu && !this.showToc && !this.showSettings &&
      this.chapters.length > 0 && !this.isReaderInteractiveActionActive();
  }

  handleReaderPanStart(event: GestureEvent): void {
    if (this.readerPageTurnGestureCommitted) {
      return;
    }
    if (!this.canHandleReaderPageTurnPan()) {
      return;
    }
    this.captureReaderCurlStartRegion(event);
    this.updateReaderCurlFinger(event);
    this.readerPanActive = true;
    this.readerPanIntent = READER_PAN_INTENT_NONE;
    this.deferReaderPaginationForInteraction();
    this.readerTouchMoved = false;
    this.suppressReaderTapClick = false;
    this.slideResetSerial++;
  }

  // 拖动一开始就明显朝下时才算下拉书签；起手偏横向的拖动整个过程都按翻页处理。
  isBookmarkPullDirection(offsetX: number, offsetY: number): boolean {
    return this.readerQuickBookmarkEnabled && this.readerEffectivePageTurnMode() !== 0 && offsetY > 0 &&
      offsetY > Math.abs(offsetX) * this.readerBookmarkPullDirectionRatio;
  }

  canHandleBookmarkPull(offsetX: number, offsetY: number): boolean {
    return this.readerQuickBookmarkEnabled && this.readerEffectivePageTurnMode() !== 0 &&
      offsetY >= this.readerBookmarkPullStartDistance &&
      offsetY > Math.abs(offsetX) * this.readerBookmarkPullDirectionRatio;
  }

  bookmarkPullCommitDistance(): number {
    const viewportHeight = this.pageViewHeight > 0 ? this.pageViewHeight : 640;
    return Math.max(160, Math.min(220, viewportHeight * 0.24));
  }

  canCommitBookmarkPull(offsetX: number, offsetY: number): boolean {
    return this.readerQuickBookmarkEnabled && this.readerEffectivePageTurnMode() !== 0 &&
      offsetY >= this.bookmarkPullCommitDistance() &&
      offsetY > Math.abs(offsetX) * this.readerBookmarkPullDirectionRatio;
  }

  updateBookmarkPullEffect(offsetX: number, offsetY: number): void {
    this.bookmarkPullActive = true;
    const effectiveOffset = Math.max(0, offsetY - this.readerBookmarkPullStartDistance);
    this.bookmarkPullOffsetY = Math.min(128, effectiveOffset * 0.65);
    this.bookmarkPullReady = this.canCommitBookmarkPull(offsetX, offsetY);
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
    if (this.readerPageTurnGestureCommitted) {
      return;
    }
    if (!this.canHandleReaderPageTurnPan()) {
      return;
    }
    if (!this.readerPanActive) {
      this.handleReaderPanStart(event);
    }
    const offsetX = event.offsetX;
    const offsetY = event.offsetY;
    if (this.isPageTurning) {
      if (this.isReaderTouchMoved(offsetX, offsetY)) {
        this.readerTouchMoved = true;
        this.suppressReaderTapClick = true;
      }
      return;
    }
    if (this.readerPanIntent === READER_PAN_INTENT_NONE) {
      if (!this.isReaderTouchMoved(offsetX, offsetY)) {
        return;
      }
      // 原先每帧都重新判断：斜向下的拖动先按翻页卷起/滑动了页面、准备了目标页，下移到 48vp 后又被
      // 下拉书签接管，翻页状态没有清理就直接置零，松手时还会切换书签而不是翻页。这里只判定一次。
      this.readerPanIntent = this.isBookmarkPullDirection(offsetX, offsetY) ?
        READER_PAN_INTENT_BOOKMARK : READER_PAN_INTENT_TURN;
    }
    if (this.readerPanIntent === READER_PAN_INTENT_BOOKMARK) {
      this.readerTouchMoved = true;
      this.suppressReaderTapClick = true;
      if (this.bookmarkPullActive || this.canHandleBookmarkPull(offsetX, offsetY)) {
        this.updateBookmarkPullEffect(offsetX, offsetY);
      }
      return;
    }
    if (!this.isPageTurnAnimationEnabled()) {
      return;
    }
    if (this.isReaderTouchMoved(offsetX, offsetY)) {
      this.readerTouchMoved = true;
      this.suppressReaderTapClick = true;
    }
    this.updateReaderCurlFinger(event);
    this.updateSlidePageEffect(this.getReaderPageTurnGestureOffset(offsetX, offsetY));
  }

  handleReaderPanEnd(event: GestureEvent): void {
    if (!this.readerPanActive) {
      return;
    }
    this.readerPanActive = false;
    this.readerEmulationFlipPainter.releaseCorner();
    this.deferReaderPaginationForInteraction();
    if (this.bookmarkPullActive) {
      this.readerTouchMoved = true;
      this.suppressReaderTapClick = true;
      this.finishBookmarkPull(this.canCommitBookmarkPull(event.offsetX, event.offsetY));
      return;
    }
    if (this.readerPanIntent === READER_PAN_INTENT_BOOKMARK) {
      // 朝下拉了但没拉到书签起始距离：既不翻页也不当作点击。
      this.readerTouchMoved = true;
      this.suppressReaderTapClick = true;
      return;
    }
    const offsetX = event.offsetX;
    const offsetY = event.offsetY;
    const axisVelocity = this.isVerticalPageTurnAnimation() ? event.velocityY : event.velocityX;
    const releasedVelocity = Number.isFinite(axisVelocity) ? Math.abs(axisVelocity) : 0;
    if (this.isReaderPageTurnCommitGesture(offsetX, offsetY, releasedVelocity)) {
      this.readerTouchMoved = true;
      this.suppressReaderTapClick = true;
      this.commitReaderMove(offsetX, offsetY, releasedVelocity);
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
    this.readerEmulationFlipPainter.releaseCorner();
    this.deferReaderPaginationForInteraction();
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
    if (Date.now() < this.readerTextSelectionUntil) {
      this.readerTouchActive = false;
      this.readerPanActive = false;
      this.suppressReaderTapClick = true;
      return;
    }
    const x = point.x;
    const y = point.y;
    const globalX: number = Number(point.x) + this.readerTapLayerGlobalX;
    const globalY: number = Number(point.y) + this.readerTapLayerGlobalY;
    // TouchObject.x/y are reported in window coordinates on current HarmonyOS devices even when the listener is
    // attached to the full-page interaction layer. V2 geometry is page-local, so derive that coordinate from the
    // explicit window point and the measured interaction-layer origin. This also remains correct in split screen.
    const readerLocalX = Number(point.windowX) - this.readerTapLayerGlobalX;
    const readerLocalY = Number(point.windowY) - this.readerTapLayerGlobalY - this.readerV2SurfaceTopOffset();
    if (event.type === TouchType.Down) {
      this.deferReaderPaginationForInteraction();
      // A fresh pointer stream must not inherit the short click guard from the previous source action.
      this.readerInteractiveActionUntil = 0;
      this.readerTouchActionMarker = '';
      this.readerInlineTouchActionMarker = '';
      this.updateReaderMenuAnchorByPoint(x);
      this.readerTouchStartX = x;
      this.readerTouchStartY = y;
      this.readerTouchLastX = x;
      this.readerTouchLastY = y;
      this.readerTouchActive = true;
      this.readerPanIntent = READER_PAN_INTENT_NONE;
      this.readerPageTurnGestureCommitted = false;
      this.readerGestureTurnGuardUntil = 0;
      this.readerGestureTurnAllowance = 0;
      this.readerTouchMoved = false;
      this.suppressReaderTapClick = false;
      this.readerSelectionDismissArmed = this.hasReaderTextSelection();
      this.slideResetSerial++;
      // An explicitly rendered action owns its exact hit region. Page-turn tap zones only run
      // when no action was hit, so justified line-end comments remain accessible near an edge.
      const actionMarker = this.readerV2ActionAtLocalPoint(readerLocalX, readerLocalY);
      if (actionMarker) {
        this.readerTouchActionMarker = actionMarker;
        this.beginReaderInteractiveAction();
        return;
      }
      return;
    }
    const sourceActionTouchActive = !!this.readerTouchActionMarker || !!this.readerInlineTouchActionMarker;
    if (this.isReaderInteractiveActionActive() && !sourceActionTouchActive) {
      this.readerTouchActive = false;
      this.suppressReaderTapClick = true;
      this.resetSlidePageEffect();
      return;
    }
    if (sourceActionTouchActive && event.type === TouchType.Move) {
      this.readerTouchLastX = x;
      this.readerTouchLastY = y;
      const offsetX = x - this.readerTouchStartX;
      const offsetY = y - this.readerTouchStartY;
      if (this.isReaderTouchMoved(offsetX, offsetY)) {
        this.readerTouchActionMarker = '';
        this.readerInlineTouchActionMarker = '';
        this.readerInteractiveActionUntil = 0;
        this.readerTouchActive = true;
        this.readerTouchMoved = true;
        this.suppressReaderTapClick = true;
        if (!this.readerPanActive && this.canHandleReaderPageTurnPan()) {
          this.readerPanActive = true;
          this.slideResetSerial++;
        }
      }
      return;
    }
    if (this.readerTouchActionMarker) {
      if (event.type === TouchType.Up) {
        const marker = this.readerTouchActionMarker;
        this.readerTouchActionMarker = '';
        this.beginReaderInteractiveAction();
        // The action already claimed this pointer on Down. Move handling above clears that claim once the
        // gesture exceeds the page tap slop, so requiring a second exact hit on Up only makes small comment
        // pills intermittently fail when a real finger drifts by a few pixels. Commit the surviving owner.
        this.openReaderSourceAction(marker);
      } else if (event.type === TouchType.Cancel) {
        this.readerTouchActionMarker = '';
      }
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
      // PanGesture owns page-turn progress. Drawing from Touch.Move too rendered every
      // physical move twice and let Touch.Up race PanGesture.onActionEnd.
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.readerTouchLastX = x;
      this.readerTouchLastY = y;
      this.readerTouchActive = false;
      this.deferReaderPaginationForInteraction();
      if (this.isPageTurnAnimationEnabled()) {
        return;
      }
      this.finishReaderHorizontalTouch(event.type === TouchType.Up);
    }
  }

  async jumpToReaderPositionKeepingTts(targetChapterIndex: number, targetPageIndex: number): Promise<void> {
    if (this.isMirroringActiveTtsForCurrentBook()) {
      await ReaderTtsFloatingSession.jumpToPosition(
        this.clampChapterIndex(targetChapterIndex), Math.max(0, Math.round(targetPageIndex)));
      return;
    }
    const shouldResume = this.isTtsSpeaking || this.ttsReader.isSpeaking();
    if (shouldResume) {
      this.stopTtsReaderForChapterSwitch();
      await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING);
    }
    this.currentPageIndex = Math.max(0, targetPageIndex);
    this.pendingRestorePageIndex = this.currentPageIndex;
    await this.loadContent(false, this.clampChapterIndex(targetChapterIndex));
    await this.saveReadingProgress();
    if (shouldResume) {
      await this.startTtsReadingFromCurrentPosition(false);
    }
  }

  updateReaderMenuAnchorByPoint(x: number): void {
    if (!this.readerUsesSideAnchoredControls()) {
      return;
    }
    const viewportWidth = Math.max(1, this.pageViewWidth || this.getPageTurnWidth());
    this.readerMenuAnchorSide = x < viewportWidth / 2 ? -1 : 1;
  }

  finishReaderHorizontalTouch(canCommitTap: boolean = true): void {
    const offsetX = this.readerTouchLastX - this.readerTouchStartX;
    const offsetY = this.readerTouchLastY - this.readerTouchStartY;
    // 已判定为下拉书签的拖动由 PanGesture 收尾，触摸抬起不能再按横向位移补一次翻页。
    if (this.readerPanIntent === READER_PAN_INTENT_BOOKMARK) {
      this.suppressReaderTapClick = true;
      return;
    }
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
    if (this.isReaderInteractiveActionActive()) {
      return true;
    }
    if (this.hasReaderTextSelection()) {
      // Same arming rule as consumeSuppressedReaderTapClick: only a press that started on an existing
      // selection may dismiss it. The release of the press that created the selection ends here
      // untouched, so holding the long press longer than the 900ms guard still keeps the menu alive.
      if (this.readerSelectionDismissArmed) {
        this.scheduleReaderTextSelectionClear();
      }
      return true;
    }
    if (this.isPageTurnAnimationEnabled() && this.readerEffectivePageTurnMode() !== 0 &&
      this.readerEffectivePageTurnMode() !== 2) {
      return false;
    }
    const width = Math.max(1, this.pageViewWidth || this.getPageTurnWidth());
    const height = Math.max(1, this.pageViewHeight || this.getPageTurnHeight());
    if (this.readerEffectivePageTurnMode() === 2) {
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
    this.updateReaderMenuAnchorByPoint(x);
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
    if (this.isReaderInteractiveActionActive()) {
      return true;
    }
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

  /**
   * Dismisses a live text selection without performing the action the tap would otherwise trigger.
   * Every tap path funnels through here before turning a page, opening the menu or firing a tap zone,
   * so consuming the click here is enough to cancel the selection. Drag events are never touched, which
   * keeps the native selection handles working.
   */
  consumeSuppressedReaderTapClick(): boolean {
    if (this.isReaderInteractiveActionActive()) {
      this.suppressReaderTapClick = false;
      return true;
    }
    if (this.hasReaderTextSelection()) {
      // A stream whose Down began on an existing selection (armed) dismisses it. The release of the
      // press that created the selection also lands here and must only be swallowed — clearing it
      // would close the freshly shown menu the moment the finger lifts.
      if (this.readerSelectionDismissArmed) {
        this.scheduleReaderTextSelectionClear();
        // Keep suppressing until the selection actually clears, so a repeated tap cannot fall through
        // to a page turn while the highlight is still visible.
        this.suppressReaderTapClick = true;
      }
      return true;
    }
    if (!this.suppressReaderTapClick) {
      return false;
    }
    this.suppressReaderTapClick = false;
    return true;
  }

  getReaderPageTurnGestureOffset(offsetX: number, offsetY: number): number {
    return this.isVerticalPageTurnAnimation() ? offsetY : offsetX;
  }

  // 拖动达到页面尺寸的一定比例才提交；快速甩动允许用更短的距离提交，但仍需明确位移。
  isPageTurnCommitOffset(axisOffset: number, axisVelocity: number): boolean {
    const dimension = this.isVerticalPageTurnAnimation() ? this.getPageTurnHeight() : this.getPageTurnWidth();
    const commitDistance = Math.max(this.readerPageTurnCommitDistance, dimension * this.readerPageTurnCommitRatio);
    const total = Math.abs(axisOffset);
    if (total >= commitDistance) {
      return true;
    }
    const flickDistance = Math.max(this.readerPageTurnCommitDistance, dimension * this.readerPageTurnFlickRatio);
    return Math.abs(axisVelocity) >= this.readerPageTurnFlickVelocity && total >= flickDistance;
  }

  isReaderPageTurnCommitGesture(offsetX: number, offsetY: number, axisVelocity: number = 0): boolean {
    const directionRatio = this.readerPageTurnDirectionRatio;
    if (this.isVerticalPageTurnAnimation()) {
      return Math.abs(offsetY) > Math.abs(offsetX) * directionRatio &&
        this.isPageTurnCommitOffset(offsetY, axisVelocity);
    }
    return Math.abs(offsetX) > Math.abs(offsetY) * directionRatio &&
      this.isPageTurnCommitOffset(offsetX, axisVelocity);
  }

  commitReaderMove(offsetX: number, offsetY: number, releaseVelocity: number = 0): void {
    if (this.readerPageTurnGestureCommitted) {
      return;
    }
    this.readerPageTurnGestureCommitted = true;
    this.readerGestureTurnGuardUntil = Date.now() + 2500;
    this.readerGestureTurnAllowance = 1;
    // Touch and PanGesture both observe the same pointer stream. Closing both sides here makes
    // whichever callback arrives second a no-op instead of committing a second page.
    this.readerTouchActive = false;
    this.readerPanActive = false;
    if (this.isVerticalPageTurnAnimation()) {
      this.commitReaderVerticalMove(offsetY, releaseVelocity);
      return;
    }
    this.commitReaderHorizontalMove(offsetX, releaseVelocity);
  }

  commitReaderVerticalMove(offsetY: number, releaseVelocity: number = 0): void {
    if (!this.isVerticalPageTurnAnimation() || this.showToc || this.showSettings ||
      this.chapters.length === 0) {
      return;
    }
    if (offsetY < 0 && this.isPageTurnCommitOffset(offsetY, releaseVelocity)) {
      this.runPageTurnAnimation(1, 'gesture', false, releaseVelocity);
    } else if (offsetY > 0 && this.isPageTurnCommitOffset(offsetY, releaseVelocity)) {
      this.runPageTurnAnimation(-1, 'gesture', false, releaseVelocity);
    } else {
      this.resetSlidePageEffect();
    }
  }

  commitReaderHorizontalMove(offsetX: number, releaseVelocity: number = 0): void {
    if ((this.readerEffectivePageTurnMode() !== 1 && this.readerEffectivePageTurnMode() !== 2) ||
      this.showToc || this.showSettings ||
      this.chapters.length === 0) {
      return;
    }
    if (offsetX < 0 && this.isPageTurnCommitOffset(offsetX, releaseVelocity)) {
      this.runPageTurnAnimation(1, 'gesture', false, releaseVelocity);
    } else if (offsetX > 0 && this.isPageTurnCommitOffset(offsetX, releaseVelocity)) {
      this.runPageTurnAnimation(-1, 'gesture', false, releaseVelocity);
    } else {
      this.resetSlidePageEffect();
    }
  }

  @Builder
  settingsPanel() {
    Column({ space: AppSpacing.LG }) {
      Row() {
        Text(this.settingsPanelTitle())
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getTextColor())

        Blank()
          .layoutWeight(1)

        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.readerControlIconColor(),
          darkMode: this.isReaderThemeDark(),
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          materialScale: 0.83,
          compactLayout: true,
          accessibilityLabel: '关闭设置',
          onBack: () => this.closeSettingsPanelKeepMenu()
        })
      }
      .width('100%')
      .padding({ right: this.readerSettingsContentRightPadding() })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 14 }) {
          if (this.settingsPanelTab === 0) {
            Column() {
              this.readerQuickSettingsPanel()
            }
            .width('100%')
            .transition(this.readerSettingsContentTransition(-1))
          } else if (this.settingsPanelTab === 1) {
            Column() {
              this.ttsQuickSettingsPanel()
            }
            .width('100%')
            .transition(this.readerSettingsContentTransition(1))
          } else if (this.settingsPanelTab === 3) {
            Column() {
              this.readerComicModeSettingsPanel()
            }
            .width('100%')
            .transition(this.readerSettingsContentTransition(-1))
          } else if (this.settingsPanelTab === 4) {
            Column() {
              this.readerComicDisplaySettingsPanel()
            }
            .width('100%')
            .transition(this.readerSettingsContentTransition(1))
          } else {
            Column() {
              this.readerTypographySettingsPanel()
            }
            .width('100%')
            .transition(this.readerSettingsContentTransition(1))
          }
        }
        .width('100%')
        .padding({ right: this.readerSettingsContentRightPadding() })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .scrollBarColor(this.isReaderThemeDark() ? '#668A8F98' : '#667A6F63')
    }
    .width(this.readerFloatingBarWidth())
    .height(this.readerSettingsPanelHeight())
    .padding({ left: AppSpacing.XXL, right: this.readerSettingsScrollBarRightInset(), top: AppSpacing.XL, bottom: 0 })
    .borderRadius(ThemeRuntime.glassCornerRadius(28, 'panel'))
    .clip(true)
    .backgroundColor(this.readerGlassPanelColor())
    .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
    .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: this.readerGlassBorderColor() })
    .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: this.readerGlassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
    .position({ x: this.readerFloatingBarLeft(), y: '100%' })
    .translate({ y: -(this.readerSettingsPanelHeight() + this.readerFloatingPanelBottomInset()) })
    .transition(this.readerPanelTransition())
  }

  settingsPanelTitle(): string {
    if (this.settingsPanelTab === 3) return '阅读方式';
    if (this.settingsPanelTab === 4) return '画面设置';
    if (this.settingsPanelTab === 1) return '朗读设置';
    if (this.settingsPanelTab === 2) return '排版设置';
    return '阅读设置';
  }

  readerSettingsScrollBarRightInset(): number {
    // 目录、设置面板与底部操作栏现在共用同一宽度和边缘，不再需要百分比补偿。
    return 0;
  }

  readerSettingsContentRightPadding(): number {
    return Math.max(0, 20 - this.readerSettingsScrollBarRightInset());
  }

  @Builder
  readerTypographySettingsPanel() {
    Column({ space: AppSpacing.XS }) {
      // 正文排版作为面板首项，统一调整字号、字距、行距、段距及四侧边距。
      this.readerTypographyCombinedSettings()
      this.readerSelectSettingItem('段首缩进', '正文每段首行的缩进字符数',
        this.readerParagraphIndentOptions(), this.readerParagraphIndent, (index: number) => {
          this.readerParagraphIndent = index;
          this.saveReaderLayoutSettings();
        }, 'reader_paragraph_indent_select')
      this.readerSelectSettingItem('正文对齐方式', '正文段落的水平对齐',
        this.readerTextAlignOptions(), this.readerTextAlignSelectedIndex(), (index: number) => {
          this.setReaderTextAlignByIndex(index);
        }, 'reader_text_align_select')
      this.readerHeaderFooterSettingsPanel()
      this.readerFontEntryItem()

      ReaderSettingSwitchRow({
        title: '正文扩展至状态栏', description: '隐藏状态栏，正文延伸到屏幕顶部',
        checked: this.readerExtendToStatusBar, textColor: this.getTextColor(), subTextColor: this.getSubTextColor(),
        onChange: (checked: boolean) => {
          this.setReaderExtendToStatusBar(checked);
        }
      })

    }
    .width('100%')
  }

  readerParagraphIndentOptions(): SelectOption[] {
    return [{ value: '0字符' }, { value: '1字符' }, { value: '2字符' }, { value: '3字符' }, { value: '4字符' }];
  }

  readerTextAlignOptions(): SelectOption[] {
    return [{ value: '两端对齐' }, { value: '左对齐' }, { value: '右对齐' }];
  }

  readerTextAlignValues(): string[] {
    return ['justify', 'start', 'end'];
  }

  readerTextAlignSelectedIndex(): number {
    const index = this.readerTextAlignValues().indexOf(this.readerTextAlign);
    return index >= 0 ? index : 0;
  }

  setReaderTextAlignByIndex(index: number): void {
    const values = this.readerTextAlignValues();
    this.readerTextAlign = index >= 0 && index < values.length ? values[index] : 'justify';
    this.saveReaderLayoutSettings();
  }

  @Builder
  readerTypographyCombinedSettings() {
    ReaderTypographyStepper({
      initialValues: this.readerTypographyInitialValues(),
      dark: this.isReaderThemeDark(),
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      accentColor: this.accentColor(),
      inputColor: this.readerSolidPanelColor(),
      menuColor: ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor()),
      onChange: (values: number[]): void => this.onReaderTypographyDraftChange(values)
    })
  }

  @Builder
  readerHeaderFooterSettingsPanel() {
    ReaderHeaderFooterSettings({
      dark: this.isReaderThemeDark(),
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      accentColor: this.accentColor(),
      switchColor: this.buttonColor(),
      menuColor: ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor()),
      onChanged: (headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string): void => {
        this.saveReaderChromeSettings(headerEnabled, footerEnabled, infoBarConfig);
      }
    })
  }

  // The stepper edits a draft; nothing is laid out until the short debounce below commits the whole set at once.
  readerTypographyInitialValues(): number[] {
    if (this.readerTypographyDraftPending && this.readerTypographyDraft.length === ReaderTypographyField.COUNT) {
      return [...this.readerTypographyDraft];
    }
    return [this.readerFontSize, this.readerFontWeight, this.readerLetterSpacing, this.readerLineHeight, this.readerParagraphSpacing,
      this.readerMarginLeft, this.readerMarginRight, this.readerMarginTop, this.readerMarginBottom, this.readerCommentBubbleSize];
  }

  onReaderTypographyDraftChange(values: number[]): void {
    if (values.length !== ReaderTypographyField.COUNT) return;
    this.readerTypographyDraft = values;
    this.readerTypographyDraftPending = true;
    this.scheduleReaderTypographyChange();
  }

  commitReaderTypographyDraft(): void {
    if (!this.readerTypographyDraftPending) return;
    const draft = this.readerTypographyDraft;
    this.readerTypographyDraftPending = false;
    if (draft.length !== ReaderTypographyField.COUNT) return;
    this.readerLayoutCommitInProgress = true;
    this.readerFontSize = draft[ReaderTypographyField.FONT_SIZE];
    this.readerFontWeight = draft[ReaderTypographyField.FONT_WEIGHT];
    this.readerLetterSpacing = draft[ReaderTypographyField.LETTER_SPACING];
    this.readerLineHeight = draft[ReaderTypographyField.LINE_HEIGHT];
    this.readerParagraphSpacing = draft[ReaderTypographyField.PARAGRAPH_SPACING];
    this.readerMarginLeft = draft[ReaderTypographyField.MARGIN_LEFT];
    this.readerMarginRight = draft[ReaderTypographyField.MARGIN_RIGHT];
    this.readerMarginTop = draft[ReaderTypographyField.MARGIN_TOP];
    this.readerMarginBottom = draft[ReaderTypographyField.MARGIN_BOTTOM];
    this.readerCommentBubbleSize = draft[ReaderTypographyField.COMMENT_BUBBLE_SIZE];
    this.readerLayoutCommitInProgress = false;
  }

  @Builder
  readerQuickSettingsPanel() {
    Column({ space: 14 }) {
      this.readerReplaceRulesEntryItem()

      this.readerSelectSettingItem('翻页方式', '上下滑动、横向滑动或滚动阅读',
        this.pageTurnModeOptions(), this.pageTurnModeSelectedIndex(), (index: number) => {
          this.switchPageTurnMode(this.pageTurnModeByIndex(index));
        }, 'reader_page_turn_mode_select')

      if (this.readerPageTurnMode === 2) {
        this.readerTapZoneSettingItem()
      }

      if (this.readerPageTurnMode === 2) {
        this.readerSelectSettingItem('翻页动画', '翻页时的切换效果',
          this.pageTurnAnimationOptions(), this.pageTurnAnimationSelectedIndex(), (index: number) => {
            this.setReaderPageTurnAnimationType(index);
          }, 'reader_page_turn_animation_select_horizontal')
      } else if (this.readerPageTurnMode === 0) {
        this.readerSelectSettingItem('翻页动画', '翻页时的切换效果',
          this.pageTurnAnimationOptions(), this.pageTurnAnimationSelectedIndex(), (index: number) => {
            this.setReaderPageTurnAnimationType(index);
          }, 'reader_page_turn_animation_select_vertical')
      }

      this.readerSwitchSettingItem('使用双翻页', '横屏、折叠屏展开等宽屏下并排显示两页',
        this.readerLandscapeDoublePage, (checked: boolean) => {
          this.setReaderLandscapeDoublePage(checked);
        })

      this.readerSelectSettingItem('屏幕方向', '阅读正文时的屏幕方向',
        this.screenOrientationOptions(), this.screenOrientationSelectedIndex(), (index: number) => {
          this.setReaderScreenOrientationByIndex(index);
        }, 'reader_screen_orientation_select')

      this.readerSwitchSettingItem('音量键翻页', '音量上/下键翻到上一页/下一页', this.readerVolumeTurnPage,
        (checked: boolean) => {
          this.setReaderVolumeTurnPage(checked);
        })

      this.readerSwitchSettingItem('快速添加书签', '下拉正文添加或删除当前页书签', this.readerQuickBookmarkEnabled,
        (checked: boolean) => {
          this.setReaderQuickBookmarkEnabled(checked);
        })

      this.readerSwitchSettingItem('眼动翻页（beta）', '看到页底后向上看即翻页；摄像头图像仅在本机处理',
        this.readerEyeTurnEnabled, (checked: boolean) => {
          this.eyeTurn().setEnabled(checked);
        })

      if (this.readerEyeTurnEnabled) {
        this.readerEyeTurnCalibrationSettingItem()
      }

      this.readerSelectSettingItem('亮屏时间设置', '无操作达到所选时长后恢复系统息屏',
        this.screenTimeoutOptions(), this.screenTimeoutSelectedIndex(), (index: number) => {
          this.setReaderScreenTimeoutByIndex(index);
        }, 'reader_screen_timeout_select')

      Row({ space: 10 }) {
        ForEach(this.currentReaderThemes(), (theme: ReaderThemeItem, index: number) => {
          Text(index === ReaderThemeHelper.CUSTOM_THEME_INDEX ? '自' :
            (index === ReaderThemeHelper.APP_THEME_INDEX ? '主' : ''))
            .width(42)
            .height(42)
            .borderRadius(21)
            .fontSize(AppFontSize.BODY)
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
        ReaderCustomThemeEditor({
          dark: this.isReaderThemeDark(),
          textColor: this.getTextColor(),
          accentColor: this.accentColor(),
          menuColor: ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor()),
          onChanged: (): void => {
            this.saveReadConfig();
          }
        })
      }

      this.readerPreloadSettingItem()
    }
    .width('100%')
  }

  @Builder
  readerFontEntryItem() {
    Row() {
      Column() {
        Text('阅读字体')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.getTextColor())
        Text('正文、标题、正则样式')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.getSubTextColor())
          .margin({ top: AppSpacing.XS })
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
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.getTextColor())
        Text('正文与章节标题的替换规则')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.getSubTextColor())
          .margin({ top: AppSpacing.XS })
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
      this.returningFromReaderReplaceRules = true;
      router.pushUrl({ url: 'pages/ReaderReplaceRules' });
    })
  }

  @Builder
  ttsQuickSettingsPanel() {
    ReaderTtsQuickSettingsPanel({
      speed: this.ttsSpeed,
      voicesLoading: this.ttsVoicesLoading,
      voiceTitle: this.selectedTtsVoiceTitle(),
      sleepTimerMinutes: this.ttsSleepTimerMinutes,
      sleepTimerRemainingSeconds: this.ttsSleepTimerRemainingSeconds,
      speaking: this.isTtsSpeaking,
      dark: this.isReaderThemeDark(),
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      accentColor: this.accentColor(),
      actionColor: this.buttonColor(),
      onSpeedChange: (speed: number): void => this.applyTtsSpeed(speed),
      onOpenVoicePicker: (): void => {
        this.showTtsVoiceDropdown = true;
      },
      onSleepTimerChange: (minutes: number): void => this.setTtsSleepTimer(minutes),
      onToggleReading: (): void => {
        if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
          this.stopTtsReading();
        } else {
          this.toggleTtsReading();
        }
      }
    })
  }

  @Builder
  ttsVoiceDropdownPanel() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showTtsVoiceDropdown = false;
        })

      ReaderTtsVoicePickerPanel({
        cloudVoices: this.ttsCloudVoices,
        customVoices: this.selectableCustomTtsVoices(),
        systemVoices: this.selectableSystemTtsVoices(),
        selectedKey: this.currentTtsVoiceKey(),
        dark: this.isReaderThemeDark(),
        textColor: this.getTextColor(),
        subTextColor: this.getSubTextColor(),
        accentColor: this.accentColor(),
        panelColor: this.readerGlassPanelColor(),
        panelBorderColor: this.readerGlassBorderColor(),
        panelShadowColor: this.readerGlassShadowColor(),
        selectedColor: this.tocSelectedBackgroundColor(),
        panelWidth: this.readerFloatingBarWidth(),
        panelHeight: this.readerTocPanelHeight(),
        onClose: (): void => {
          this.showTtsVoiceDropdown = false;
        },
        onSelectCloudVoice: (voice: TtsVoiceInfo): void => {
          this.showTtsVoiceDropdown = false;
          this.applyCloudTtsVoice(voice, true);
        },
        onSelectCustomVoice: (voice: HttpTTS): void => {
          this.showTtsVoiceDropdown = false;
          this.applyCustomTtsVoice(voice, true);
        },
        onSelectSystemVoice: (voice: TtsVoiceOption): void => {
          this.showTtsVoiceDropdown = false;
          this.applyTtsVoice(voice, true);
        }
      })
        .position({ x: this.readerFloatingBarLeft(), y: '100%' })
        .translate({ y: -(this.readerTocPanelHeight() + this.readerFloatingPanelBottomInset()) })
        .transition(this.readerPanelTransition())
    }
    .width('100%')
    .height('100%')
  }

  pageTurnModeOptions(): SelectOption[] {
    return [
      { value: '上下滑动' },
      { value: '横向滑动' },
      { value: '滚动阅读' }
    ];
  }

  pageTurnModeTypes(): number[] {
    return [0, 2, 3];
  }

  pageTurnModeByIndex(index: number): number {
    const types = this.pageTurnModeTypes();
    return index >= 0 && index < types.length ? types[index] : 2;
  }

  pageTurnModeSelectedIndex(): number {
    const index = this.pageTurnModeTypes().indexOf(this.readerPageTurnMode);
    return index >= 0 ? index : 1;
  }

  pageTurnAnimationOptions(): SelectOption[] {
    const options: SelectOption[] = [
      { value: '无动画' },
      { value: '平移' },
      { value: '淡入' },
      { value: '叠页' }
    ];
    if (this.readerPageTurnMode === 2) {
      options.push({ value: '仿真' });
      options.push({ value: '3D仿真' });
    }
    return options;
  }

  pageTurnAnimationTypes(): number[] {
    const types: number[] = [
      ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE,
      ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE,
      ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE,
      ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK
    ];
    if (this.readerPageTurnMode === 2) {
      types.push(ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION);
      types.push(ReaderSettingsStore.PAGE_TURN_ANIMATION_3D);
    }
    return types;
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

  screenTimeoutOptions(): SelectOption[] {
    return [
      { value: '跟随系统' },
      { value: '1分钟' },
      { value: '5分钟' },
      { value: '10分钟' },
      { value: '常亮' }
    ];
  }

  screenTimeoutValues(): number[] {
    return [
      ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM,
      1,
      5,
      10,
      ReaderSettingsStore.SCREEN_TIMEOUT_ALWAYS_ON
    ];
  }

  screenTimeoutSelectedIndex(): number {
    const values = this.screenTimeoutValues();
    const current = ReaderSettingsStore.normalizeScreenTimeoutMinutes(this.readerScreenTimeoutMinutes);
    for (let i = 0; i < values.length; i++) {
      if (values[i] === current) {
        return i;
      }
    }
    return 0;
  }

  screenOrientationOptions(): SelectOption[] {
    return [
      { value: '跟随系统' },
      { value: '强制竖屏' },
      { value: '强制横屏' }
    ];
  }

  screenOrientationValues(): string[] {
    return [
      ReaderSettingsStore.SCREEN_ORIENTATION_SYSTEM,
      ReaderSettingsStore.SCREEN_ORIENTATION_PORTRAIT,
      ReaderSettingsStore.SCREEN_ORIENTATION_LANDSCAPE
    ];
  }

  screenOrientationSelectedIndex(): number {
    const value = ReaderSettingsStore.normalizeScreenOrientation(this.readerScreenOrientation);
    const values = this.screenOrientationValues();
    for (let i = 0; i < values.length; i++) {
      if (values[i] === value) return i;
    }
    return 0;
  }

  @Builder
  readerTapZoneSettingItem() {
    ReaderSettingActionRow({
      title: '点击区域动作',
      description: this.tapZoneSummaryText(),
      actionText: '配置',
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      buttonColor: this.buttonColor(),
      buttonTextColor: ThemeRuntime.onAccentColor(),
      onAction: (): void => this.presentTapZoneSettings()
    })
  }

  @Builder
  readerSelectSettingItem(title: string, description: string, options: SelectOption[], selected: number,
    onSelect: (index: number) => void, controlId: string) {
    ReaderSettingSelectRow({
      title: title,
      description: description,
      options: options,
      selected: selected,
      controlId: controlId,
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      accentColor: this.accentColor(),
      dark: this.isReaderThemeDark(),
      menuColor: ThemeRuntime.dropdownPanelColor(this.isReaderThemeDark(), this.getBackgroundColor()),
      onSelect: onSelect
    })
  }

  readerPreloadChapterOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let index = 1; index <= 10; index++) {
      options.push({ value: `${index}章` });
    }
    return options;
  }

  @Builder
  readerSwitchSettingItem(title: string, description: string, checked: boolean, onChange: (checked: boolean) => void) {
    ReaderSettingSwitchRow({
      title: title,
      description: description,
      checked: checked,
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      onChange: onChange
    })
  }

  @Builder
  readerEyeTurnCalibrationSettingItem() {
    ReaderEyeTurnCalibrationSettingItem({
      state: this.eyeTurnState,
      coordinator: this.eyeTurn(),
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      accentColor: this.accentColor()
    })
  }

  readerEyeTurnPromptTop(): number {
    const viewportHeight = this.pageViewHeight > 0 ? this.pageViewHeight : 720;
    return Math.max(48, viewportHeight - this.getReaderContentBottomReserve() -
      this.getEffectiveReaderMarginBottom() - 48);
  }

  @Builder
  readerEyeTurnPrompt() {
    if (this.eyeTurnState.promptVisible()) {
      Row() {
        Text('向上看，翻下一页')
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F8FFFFFF')
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor('#B35C7569')
          .shadow({ radius: 12, color: '#45000000', offsetX: 0, offsetY: 4 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .position({ x: 0, y: this.readerEyeTurnPromptTop() })
      // Above the reader settings panel (zIndex 90) so the prompt stays visible while the
      // eye-turn settings status is being watched.
      .zIndex(95)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  readerEyeCalibrationPanel() {
    ReaderEyeCalibrationPanel({
      state: this.eyeTurnState,
      coordinator: this.eyeTurn(),
      dark: this.isReaderThemeDark(),
      textColor: this.getTextColor(),
      subTextColor: this.getSubTextColor(),
      accentColor: this.accentColor(),
      panelColor: this.readerGlassPanelColor(),
      panelBorderColor: this.readerGlassBorderColor(),
      viewportWidth: this.pageViewWidth,
      viewportHeight: this.pageViewHeight,
      statusBarHeight: this.statusBarSafeHeight,
      navBarHeight: this.navBarHeight
    })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .zIndex(4)
  }

  // Camera permission, gaze signal source and calibration live in the coordinator; the page decides when a gaze
  // turn is allowed and performs it.
  eyeTurn(): ReaderEyeTurnCoordinator {
    if (!this.eyeTurnCoordinator) {
      this.eyeTurnCoordinator = new ReaderEyeTurnCoordinator(this.eyeTurnState, {
        abilityContext: (): common.UIAbilityContext => getContext(this) as common.UIAbilityContext,
        enabled: (): boolean => this.readerEyeTurnEnabled,
        setEnabled: (enabled: boolean): void => {
          this.readerEyeTurnEnabled = enabled;
        },
        calibration: (landscape: boolean): string =>
          landscape ? this.readerEyeTurnLandscapeCalibration : this.readerEyeTurnPortraitCalibration,
        setCalibration: (landscape: boolean, raw: string): void => {
          if (landscape) this.readerEyeTurnLandscapeCalibration = raw;
          else this.readerEyeTurnPortraitCalibration = raw;
        },
        nextDwellMs: (): number => this.readerEyeTurnNextDwellMs,
        saveSettings: (): void => this.saveReaderEyeTurnSettings(),
        pageVisible: (): boolean => this.readerPageVisible,
        viewportWidth: (): number => this.pageViewWidth,
        viewportHeight: (): number => this.pageViewHeight,
        canTurn: (): boolean => this.readerEyeTurnCanTrigger(),
        blockReason: (): string => this.readerEyeTurnBlockReason(),
        turnNext: (): void => {
          this.runPageTurnAnimation(1, 'tap').catch((error: Error): void => {
            console.warn('[EyeTurn] page turn failed:', error.message);
          });
        },
        closePanels: (): void => {
          this.showMenu = false;
          this.showSettings = false;
        }
      });
    }
    return this.eyeTurnCoordinator;
  }

  @Builder
  readerPreloadSettingItem() {
    // Keep the dependent chapter-count selector separated from the toggle by the
    // same spacing used between the other reading settings.
    Column({ space: 14 }) {
      Row() {
        Column() {
          Text('预缓存设置')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.getTextColor())
          Text('阅读时提前缓存后续章节')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.getSubTextColor())
            .margin({ top: AppSpacing.XS })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        AdaptiveSwitch({
          isOn: this.readerPreloadEnabled,
          onChange: (value: boolean) => {
            this.setReaderPreloadEnabled(value);
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.readerPreloadEnabled) {
        this.readerSelectSettingItem('下一章节数', '预缓存的后续章节数',
          this.readerPreloadChapterOptions(), this.readerPreloadChapterCount - 1,
          (index: number) => this.setReaderPreloadChapterCount(index + 1),
          'reader_preload_chapter_count_select')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
  }

  switchPageTurnMode(mode: number) {
    if (this.readerPageTurnMode === mode) {
      return;
    }
    this.setReaderTextSelectionActive(false);
    this.stopTtsReading();
    this.readerPageTurnMode = mode;
    if (mode === 0 && (Math.round(this.readerPageTurnAnimationType) ===
      ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION ||
      Math.round(this.readerPageTurnAnimationType) === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D)) {
      this.readerPageTurnAnimationType = ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK;
      this.resetSlidePageEffect();
      ReaderSettingsStore.savePageTurnAnimationType(getContext(this), this.readerPageTurnAnimationType)
        .catch((e: Error) => {
          console.error('降级上下滑动翻页动画失败:', e);
        });
    }
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
    if (this.readerPageTurnMode === 0 && (value === ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D)) {
      return ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK;
    }
    if (value === ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D) {
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
      this.readerMarginBottom,
      this.readerLetterSpacing,
      this.readerTextAlign,
      this.readerFontWeight,
      this.readerParagraphIndent,
      this.readerCommentBubbleSize
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

  setReaderScreenOrientationByIndex(index: number): void {
    const values = this.screenOrientationValues();
    this.readerScreenOrientation = index >= 0 && index < values.length ? values[index] :
      ReaderSettingsStore.SCREEN_ORIENTATION_SYSTEM;
    this.applyReaderScreenOrientation();
    ReaderSettingsStore.saveScreenOrientation(getContext(this), this.readerScreenOrientation).catch((e: Error) => {
      console.error('保存阅读屏幕方向失败:', e);
    });
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

  saveReaderInteractionSettings(): void {
    ReaderSettingsStore.saveReadingInteractionSettings(
      getContext(this),
      this.readerVolumeTurnPage,
      this.readerScreenTimeoutMinutes,
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

  saveReaderEyeTurnSettings(): void {
    ReaderSettingsStore.saveEyeTurnSettings(
      getContext(this),
      this.readerEyeTurnEnabled,
      this.readerEyeTurnPortraitCalibration,
      this.readerEyeTurnLandscapeCalibration,
      this.readerEyeTurnPreviousEnabled,
      this.readerEyeTurnNextEnabled,
      this.readerEyeTurnPreviousDwellMs,
      this.readerEyeTurnNextDwellMs
    ).catch((error: Error): void => {
      console.warn('[EyeTurn] save settings failed:', error.message);
    });
    this.saveReadConfig();
  }

  readerEyeTurnCanTrigger(): boolean {
    // Any reader overlay pauses eye-turning: menus, the settings/action panels and the
    // comment panel all sit above the text, so a gaze turn there would act on content the
    // reader cannot see.
    return this.readerEyeTurnEnabled && this.readerPageVisible && !this.eyeTurnState.showCalibration &&
      !this.showMenu && !this.showToc && !this.showSettings && !this.showReaderActionMenu &&
      !this.showBookmarkActionMenu && !this.showTapZoneSettings && !this.showChangeSourceDialog &&
      !this.showReaderCommentPanel && !this.readerTextSelectionActive && !this.isLoading &&
      this.readerInitialPageReady && this.readerEffectivePageTurnMode() !== 3 &&
      !this.isReaderPaginationInteractionBusy();
  }

  /** Which condition currently blocks an eye-turn, for diagnostics only. */
  private readerEyeTurnBlockReason(): string {
    if (!this.readerEyeTurnEnabled) return 'disabled';
    if (!this.readerPageVisible) return 'pageHidden';
    if (this.eyeTurnState.showCalibration) return 'calibration';
    if (this.showMenu) return 'menu';
    if (this.showToc) return 'toc';
    if (this.showSettings) return 'settings';
    if (this.showReaderActionMenu) return 'actionMenu';
    if (this.showBookmarkActionMenu) return 'bookmarkMenu';
    if (this.showTapZoneSettings) return 'tapZone';
    if (this.showChangeSourceDialog) return 'changeSource';
    if (this.readerTextSelectionActive) return 'textSelection';
    if (this.isLoading) return 'loading';
    if (!this.readerInitialPageReady) return 'pageNotReady';
    if (this.readerEffectivePageTurnMode() === 3) return 'scrollMode';
    if (this.showReaderCommentPanel) return 'commentPanel';
    if (this.isPageTurning) return 'isPageTurning';
    if (this.pageTurnAnimating) return 'pageTurnAnimating';
    if (this.readerPanActive) return 'readerPanActive';
    if (this.readerTouchActive) return 'readerTouchActive';
    if (this.readerComicChapterSwitching) return 'comicSwitching';
    if (this.pageSlideDirection !== 0) return 'pageSlide';
    if (this.pageTurnQueue.hasPending()) return 'queuedTurn';
    if (Date.now() < this.readerPaginationInteractionIdleUntil) return 'interactionIdle';
    if (this.isReaderPaginationInteractionBusy()) return 'paginationBusy';
    return 'ok';
  }

  setReaderScreenTimeoutByIndex(index: number): void {
    const values = this.screenTimeoutValues();
    this.readerScreenTimeoutMinutes = index >= 0 && index < values.length ?
      values[index] :
      ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM;
    this.applyReaderScreenTimeout();
    this.saveReaderInteractionSettings();
    this.saveReadConfig();
  }

  setReaderExtendToStatusBar(enabled: boolean): void {
    if (this.readerExtendToStatusBar === enabled) return;
    const readingOffset = this.getReaderStableReflowOffset();
    this.readerExtendLayoutReadingOffset = readingOffset;
    this.readerExtendToStatusBar = enabled;
    this.syncReaderPageHeightForContentTopPadding();
    // StorageLink watchers can be delivered in a later UI task. Calling the coalesced refresh here
    // makes the switch responsive, while a subsequent watch notification only restarts the same timer.
    this.scheduleReaderExtendLayoutRefresh(readingOffset);
    this.saveReaderInteractionSettings();
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

  setReaderQuickBookmarkEnabled(enabled: boolean): void {
    this.readerQuickBookmarkEnabled = enabled;
    if (!enabled && this.bookmarkPullActive) {
      this.finishBookmarkPull(false);
    }
    ReaderSettingsStore.saveQuickBookmarkEnabled(getContext(this), enabled).catch((e: Error) => {
      console.error('保存快速添加书签设置失败:', e);
    });
    this.saveReadConfig();
  }

  publishTtsFloatingSession(): void {
    ReaderTtsFloatingSession.attach(
      this.ttsFloatingSessionOwnerId,
      this.bookUrl,
      this.book?.name || '正在朗读',
      this.getChapterTitle(),
      this.isTtsPaused,
      () => this.toggleTtsReading(),
      () => this.isTtsPaused || this.ttsReader.isPaused(),
      () => this.stopTtsFloatingSession()
    );
    // A voice/speed change restarts reading through stop + start; the stop released the background permission.
    if (this.readerPageDetachedFromRoute) {
      ReaderProgressCheckpoint.retainBackground(this.ttsFloatingSessionOwnerId, (): string => this.bookUrl);
    }
    ReaderTtsFloatingSession.configureControls(
      this.ttsFloatingSessionOwnerId,
      () => { this.playPreviousChapterFromMediaSession(); },
      () => { this.playNextChapterFromMediaSession(); },
      (value: number) => this.applyTtsSpeed(value),
      (minutes: number) => this.setTtsSleepTimer(minutes)
    );
    ReaderTtsFloatingSession.configurePositionControl(
      this.ttsFloatingSessionOwnerId,
      (chapterIndex: number, pageIndex: number, sourceOffset: number): Promise<void> =>
        this.playPositionFromFloatingSession(chapterIndex, pageIndex, sourceOffset)
    );
    ReaderTtsFloatingSession.configureCatalog(
      this.ttsFloatingSessionOwnerId,
      this.chapters.map((chapter: BookChapter) => chapter.title),
      this.currentChapterIndex,
      (index: number) => {
        this.playPositionFromFloatingSession(index, 0).catch(
          (error: Error) => console.warn('朗读目录跳转失败:', error));
      },
      this.readerChapterCachedFlags()
    );
    this.publishTtsFloatingVoices();
    this.updateTtsFloatingSession();
  }

  publishTtsFloatingVoices(): void {
    if (!ReaderTtsFloatingSession.isOwner(this.ttsFloatingSessionOwnerId)) return;
    ReaderTtsFloatingSession.configureTtsVoices(
      this.ttsFloatingSessionOwnerId,
      this.ttsQuickVoiceLabels(),
      this.ttsQuickVoiceSelectedIndex(),
      (index: number) => {
        this.selectTtsQuickVoice(index);
        setTimeout(() => this.publishTtsFloatingVoices(), 0);
      }
    );
  }

  updateTtsFloatingSession(): void {
    ReaderTtsFloatingSession.update(
      this.ttsFloatingSessionOwnerId,
      this.book?.name || '正在朗读',
      this.getChapterTitle(),
      this.isTtsPaused
    );
    // Keeps the floating catalog highlight on the chapter being read. Availability
    // published here is recomputed identically by updateDetails below.
    ReaderTtsFloatingSession.updateCatalogIndex(this.ttsFloatingSessionOwnerId, this.currentChapterIndex);
    ReaderTtsFloatingSession.updateDetails(
      this.ttsFloatingSessionOwnerId,
      this.ttsPanelFollowingText() || this.ttsQuickSentencePreview(),
      this.ttsPanelTextBefore(),
      this.ttsCurrentSentence(),
      this.ttsPanelTextAfter(),
      this.getTtsFloatingCover(),
      this.shouldUseTtsThemeBookCover() ? this.activeTtsThemeShelfFrame() : '',
      `${this.currentChapterIndex + 1}/${Math.max(1, this.chapters.length)}章`,
      this.ttsSpeed,
      this.ttsSleepTimerMinutes,
      this.ttsSleepTimerRemainingSeconds,
      this.canPlayPreviousTtsChapter(),
      this.canPlayNextTtsChapter(),
      this.ttsQuickProgress()
    );
  }

  stopTtsFloatingSession(): void {
    this.stopTtsReading();
    if (!this.readerPageVisible) {
      this.ttsReader.shutdown();
    }
  }

  async toggleTtsReading(): Promise<void> {
    if (this.isReaderComicModeActive()) return;
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      try {
        if (this.isTtsPaused || this.ttsReader.isPaused()) {
          this.isTtsPaused = false;
          if (await this.ttsReader.resume()) {
            this.isTtsSpeaking = true;
            this.updateTtsFloatingSession();
            await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
            HdsFeedback.showToast('继续朗读');
          } else {
            this.isTtsPaused = true;
          }
        } else {
          this.isTtsPaused = true;
          if (await this.ttsReader.pause()) {
            this.updateTtsFloatingSession();
            await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
            HdsFeedback.showToast('已暂停朗读');
          } else {
            this.isTtsPaused = false;
          }
        }
      } catch (error) {
        this.isTtsPaused = this.ttsReader.isPaused();
        this.updateTtsFloatingSession();
        console.warn('切换朗读暂停状态失败:', error);
        HdsFeedback.showToast('切换朗读状态失败');
      }
      return;
    }
    await this.startTtsReadingFromCurrentPosition(true);
  }

  async startTtsReadingFromCurrentPosition(showToast: boolean,
    manualPageTurnResume: boolean = false, manualPageTurnResumeSerial: number = -1,
    readingStartOffset: number = -1, preserveExistingFocus: boolean = false): Promise<void> {
    if (!manualPageTurnResume) {
      this.cancelManualPageTurnTtsResume();
      this.clearQueuedReaderPageTurns();
    } else if (!this.isManualPageTurnTtsResumeCurrent(manualPageTurnResumeSerial)) {
      return;
    }
    if (this.isReaderComicModeActive()) {
      this.finishTtsReading();
      return;
    }
    // A scrolling chunk spans several screens, so its start can be far above what is on screen. Begin with
    // the first visible line instead.
    const visibleOffset = readingStartOffset < 0 && this.usesReaderContinuousV2() ?
      this.readerContinuousV2FirstVisibleSourceOffset() : -1;
    const text = this.getTtsReadingText(readingStartOffset >= 0 ? readingStartOffset : visibleOffset);
    if (!text) {
      this.finishTtsReading();
      if (showToast) {
        HdsFeedback.showToast('当前没有可朗读内容');
      }
      return;
    }
    if (readingStartOffset < 0) {
      this.ttsChapterCompletionRetryCount = 0;
    }
    // A source may end in image/action markers which are stripped before synthesis. The chunk splitter also
    // trims whitespace at every boundary, so using text.length here can point past the final audible chunk
    // (especially when a chapter ends with several newlines). That makes the completion guard replay the last
    // sentence twice and then stop with "chapter tail not confirmed". Keep the same trim semantics as the
    // splitter when calculating the source endpoint that must be confirmed.
    const speechTextEnd = this.ttsSpeechTextEnd(text);
    const speechEnd = speechTextEnd <= 0 ? this.ttsTextStartOffset : (this.readerV2ActiveSpeechText ?
      this.readerV2ActiveSpeechText.sourceOffsetAt(speechTextEnd) :
      this.ttsTextStartOffset + speechTextEnd);
    this.ttsReadingExpectedSourceEnd = Math.max(this.ttsTextStartOffset, speechEnd);
    const token = ++this.ttsReadToken;
    const focusGeneration = ++this.ttsFocusGeneration;
    const focusChapterIndex = this.currentChapterIndex;
    const focusSourceIdentity = this.currentTtsSourceIdentity();
    this.ttsFocusChapterIndex = focusChapterIndex;
    this.ttsFocusSourceIdentity = focusSourceIdentity;
    this.ttsFocusContentLoadSerial = this.contentLoadSerial;
    this.ttsLastAppliedSourceOffset = Math.max(-1, this.ttsTextStartOffset - 1);
    await ReaderTtsFloatingSession.stopOther(this.ttsFloatingSessionOwnerId);
    // A later page turn or explicit stop supersedes this async start. The stale task must not
    // restore auto-continue or tear down the newer page-turn resume that replaced it.
    if (token !== this.ttsReadToken ||
      (manualPageTurnResume && !this.isManualPageTurnTtsResumeCurrent(manualPageTurnResumeSerial))) {
      return;
    }
    this.ttsAutoContinue = true;
    this.isTtsPaused = false;
    if (!preserveExistingFocus) {
      this.ttsDisplayText = this.currentPageText;
      this.ttsHighlightStart = -1;
      this.ttsHighlightEnd = -1;
      this.ttsLastFocusChunk = null;
      this.ttsLastFocusPageIndex = -1;
      this.readerV2TtsSourceStart = -1;
      this.readerV2TtsSourceEnd = -1;
      this.refreshReaderV2TtsOverlay();
      this.publishTtsHighlightRenderChange();
    }
    this.persistTtsReadPosition(this.ttsTextStartOffset, this.ttsTextStartOffset);
    try {
      this.isTtsSpeaking = true;
      this.updateVolumeKeySubscription();
      // Adjacent-page/chapter preloading competes with the first audio buffer on the UI thread,
      // which is audible as a stutter in the first sentence after a chapter handoff. The page-turn
      // path already scheduled it; every other start defers it past that first buffer.
      this.preloadReaderContentLater(manualPageTurnResume ? 240 : 720);
      const backgroundStarted = await this.ttsMediaSession().startBackgroundRunning();
      if (!backgroundStarted && showToast) {
        HdsFeedback.showToast('后台朗读任务启动失败，息屏后可能中断');
      }
      if (token !== this.ttsReadToken ||
        (manualPageTurnResume && !this.isManualPageTurnTtsResumeCurrent(manualPageTurnResumeSerial))) {
        return;
      }
      if (!this.ttsAutoContinue) {
        if (!manualPageTurnResume) this.stopTtsReading(false);
        return;
      }
      this.publishTtsFloatingSession();
      const cloudVoice = this.findCurrentCloudTtsVoice();
      await this.ttsReader.start(text, {
        onFinished: () => {
          this.continueTtsReading(token).catch((e: Error) => {
            console.warn('连续朗读续播失败:', e);
            if (token === this.ttsReadToken) {
              this.finishTtsReading();
            }
          });
        },
        onSpeechless: () => {
          if (token !== this.ttsReadToken) {
            return;
          }
          // The remaining page/chapter has no audible content (punctuation or
          // whitespace only), so no chunk will ever confirm the tail. Clear the
          // expected end before onFinished fires; otherwise continueTtsReading
          // sees zero focus chunks and retries the same speechless range until
          // it stops the whole read with "chapter tail not confirmed".
          this.ttsReadingExpectedSourceEnd = -1;
          this.ttsChapterCompletionRetryCount = 0;
        },
        onError: (message: string) => {
          if (token !== this.ttsReadToken) {
            return;
          }
          this.finishTtsReading();
          HdsFeedback.showToast(message || '系统朗读失败');
        },
        onChunkStart: (chunk: TtsChunk) => {
          if (!this.isCurrentTtsFocusSession(token, focusGeneration,
            focusChapterIndex, focusSourceIdentity)) {
            return;
          }
          this.followTtsChunk(chunk, token, focusGeneration, focusChapterIndex, focusSourceIdentity);
        },
        onAudioStart: () => {
          if (token !== this.ttsReadToken) {
            return;
          }
          this.ttsMediaSession().onAudioStarted();
        },
        cloudVoiceId: cloudVoice?.id || '',
        cloudVoiceName: cloudVoice?.name || '',
        cloudVoiceTier: cloudVoice?.tier || 'STANDARD',
        person: this.ttsPerson,
        online: this.ttsOnline,
        style: this.ttsStyle,
        language: this.ttsLanguage,
        speed: this.ttsSpeed,
        focusBreakOffsets: this.getTtsFocusBreakOffsets(text.length),
        // Continuous reading should keep one renderer/audio route across
        // chapter boundaries; explicit stop/pause paths still release it.
        keepAudioOutputOnFinish: true
      });
      if (showToast && token === this.ttsReadToken) {
        HdsFeedback.showToast('开始连续朗读');
      }
    } catch (error) {
      if (token !== this.ttsReadToken ||
        (manualPageTurnResume && !this.isManualPageTurnTtsResumeCurrent(manualPageTurnResumeSerial))) {
        return;
      }
      this.finishTtsReading();
      HdsFeedback.showToast('当前系统不支持朗读或 TTS 初始化失败');
      console.error('启动系统 TTS 失败:', error);
    }
  }

  /**
   * Return the last source position that can belong to an audible TTS chunk. The reader engine owns the
   * answer: it blanks decorative lines (a lone ">", "***", "---" ...) before splitting, so a chapter ending
   * in one would otherwise leave a tail the completion guard waits for but nothing ever speaks.
   */
  ttsSpeechTextEnd(text: string): number {
    return this.ttsReader.speechTextEnd(text);
  }

  stopTtsReading(userCancelled: boolean = true): void {
    this.cancelManualPageTurnTtsResume();
    this.flushTtsReadPosition();
    this.clearTtsSleepTimer();
    this.isTtsPaused = false;
    ReaderTtsFloatingSession.clear(this.ttsFloatingSessionOwnerId);
    this.releaseBackgroundProgressWriterAfterTtsStop();
    if (userCancelled) {
      this.ttsAutoContinue = false;
      this.ttsReadToken++;
    }
    this.invalidateTtsFocusSession();
    this.ttsAutoTurningPage = false;
    this.ttsPendingTargetPageIndex = -1;
    this.ttsPendingHighlightChunk = null;
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
    this.ttsReadingExpectedSourceEnd = -1;
    this.ttsChapterCompletionRetryCount = 0;
    this.ttsPageTurnSerial++;
    this.ttsMediaSession().stopBackgroundRunning();
    if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking()) {
      this.isTtsSpeaking = false;
      this.updateVolumeKeySubscription();
      this.clearTtsHighlight();
      return;
    }
    this.ttsReader.stop();
    this.isTtsSpeaking = false;
    this.updateVolumeKeySubscription();
    this.ttsPageTurnSerial++;
    this.clearTtsHighlight();
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
  }

  stopTtsReaderForChapterSwitch(): void {
    this.cancelManualPageTurnTtsResume();
    this.flushTtsReadPosition();
    this.ttsAutoContinue = false;
    this.isTtsPaused = false;
    this.ttsReadToken++;
    this.invalidateTtsFocusSession();
    this.ttsAutoTurningPage = false;
    this.ttsPendingTargetPageIndex = -1;
    this.ttsPendingHighlightChunk = null;
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
    this.ttsReadingExpectedSourceEnd = -1;
    this.ttsChapterCompletionRetryCount = 0;
    this.ttsPageTurnSerial++;
    this.ttsReader.stop();
    this.isTtsSpeaking = false;
    this.clearTtsHighlight();
  }

  clearManualPageTurnTtsResumeTimer(): void {
    if (this.ttsManualPageTurnResumeTimerId < 0) return;
    clearTimeout(this.ttsManualPageTurnResumeTimerId);
    this.ttsManualPageTurnResumeTimerId = -1;
  }

  cancelManualPageTurnTtsResume(): void {
    this.clearManualPageTurnTtsResumeTimer();
    this.ttsManualPageTurnResumeSerial++;
    this.ttsManualPageTurnResumePending = false;
    this.ttsManualPageTurnStartedAt = 0;
  }

  deferManualPageTurnTtsResume(): void {
    this.clearManualPageTurnTtsResumeTimer();
    this.ttsManualPageTurnResumeSerial++;
  }

  isManualPageTurnTtsResumeCurrent(serial: number): boolean {
    return serial >= 0 && this.ttsManualPageTurnResumePending &&
      serial === this.ttsManualPageTurnResumeSerial;
  }

  prepareTtsForManualPageTurn(): void {
    this.deferManualPageTurnTtsResume();
    if (!this.ttsManualPageTurnResumePending) {
      this.ttsManualPageTurnResumePending = true;
      this.ttsManualPageTurnStartedAt = Date.now();
      this.flushTtsReadPosition();
    }
    // This also cancels a deferred start that already passed its debounce window. Previously the
    // early return left that start alive; once it noticed its stale token it performed a full stop
    // and accidentally removed the newest resume timer.
    this.ttsAutoContinue = false;
    this.isTtsPaused = false;
    this.ttsReadToken++;
    this.invalidateTtsFocusSession();
    this.ttsAutoTurningPage = false;
    this.ttsPendingTargetPageIndex = -1;
    this.ttsPendingHighlightChunk = null;
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
    this.ttsPageTurnSerial++;
    // Preserve the visible speaking/highlight state while the outgoing page animates. Clearing it
    // here used to rebuild the whole reader subtree immediately before the page-turn animation.
    this.ttsReader.stop();
  }

  scheduleTtsResumeAfterManualPageTurn(): void {
    if (!this.ttsManualPageTurnResumePending) return;
    this.deferManualPageTurnTtsResume();
    const serial = this.ttsManualPageTurnResumeSerial;
    this.ttsManualPageTurnResumeTimerId = setTimeout(() => {
      this.ttsManualPageTurnResumeTimerId = -1;
      if (serial !== this.ttsManualPageTurnResumeSerial || !this.ttsManualPageTurnResumePending) return;
      if (this.isPageTurning || this.pageTurnQueue.hasPending() ||
        !this.isReaderPageTurnPositionReadyForTts()) {
        this.scheduleTtsResumeAfterManualPageTurn();
        return;
      }
      const startedAt = this.ttsManualPageTurnStartedAt;
      const chapterIndex = this.currentChapterIndex;
      const pageIndex = this.currentPageIndex;
      this.syncTtsStateToVisiblePage();
      this.startTtsReadingFromCurrentPosition(false, true, serial)
        .then(() => {
          if (!this.isManualPageTurnTtsResumeCurrent(serial)) return;
          this.ttsManualPageTurnResumePending = false;
          // A fast engine may deliver its first chunk while the final incoming page still owns the
          // temporary turn surface. Republish once more from this deterministic resume-complete
          // boundary so the focus cannot remain attached to the discarded surface.
          this.scheduleCurrentTtsFocusRepublishAfterPageTurn();
          console.info(`[TTS-Turn] resumed chapter=${chapterIndex},page=${pageIndex},` +
            `elapsed=${Math.max(0, Date.now() - startedAt)}ms`);
          this.ttsManualPageTurnStartedAt = 0;
        })
        .catch((error: Error) => {
          if (serial !== this.ttsManualPageTurnResumeSerial) return;
          console.warn('[TTS-Turn] deferred resume failed:', error);
          this.finishTtsReading();
        });
    }, 48);
  }

  isReaderPageTurnPositionReadyForTts(): boolean {
    if (this.pendingRestorePageIndex >= 0 || this.readerTypographyRestoreOffset >= 0 ||
      !this.readerInitialPageReady || this.contentPages.length === 0 ||
      this.currentPageIndex < 0 || this.currentPageIndex >= this.contentPages.length) return false;
    return this.displayPageChapterIndex === this.currentChapterIndex &&
      this.displayPageIndex === this.currentPageIndex &&
      this.displayPageText === this.getCurrentPageText();
  }

  syncTtsStateToVisiblePage(): void {
    const pageText = this.getCurrentPageText();
    if (this.currentPageText !== pageText || this.displayPageText !== pageText ||
      this.displayPageChapterIndex !== this.currentChapterIndex || this.displayPageIndex !== this.currentPageIndex) {
      this.commitVisibleCurrentPageText(pageText);
    }
    const pageStart = this.getCurrentPageStartOffset();
    this.ttsTextStartOffset = pageStart;
    this.ttsDisplayText = pageText;
    this.ttsHighlightStart = -1;
    this.ttsHighlightEnd = -1;
    this.readerV2TtsSourceStart = -1;
    this.readerV2TtsSourceEnd = -1;
    this.refreshReaderV2TtsOverlay();
    this.publishTtsHighlightRenderChange();
    this.persistTtsReadPosition(pageStart, pageStart);
    this.updateTtsFloatingSession();
  }

  async continueTtsReading(token: number): Promise<void> {
    if (token !== this.ttsReadToken || !this.ttsAutoContinue) {
      return;
    }
    if (this.ttsChapterSwitching) {
      return;
    }
    // onFinished is not a sufficient chapter-boundary proof on every TTS route. A delayed/early completion event
    // can arrive while the final synthesized chunks are still absent from the audible queue. Replay from the last
    // confirmed chunk instead of discarding the unspoken tail and entering the next chapter.
    if (!this.isTtsReadingAtExpectedEnd()) {
      if (this.ttsChapterCompletionRetryCount < 2) {
        this.ttsChapterCompletionRetryCount++;
        const resumeOffset = this.ttsLastFocusChunk ?
          this.readerV2TtsSourceOffset(this.ttsLastFocusChunk.start) : this.ttsTextStartOffset;
        console.warn(`[TTS] completion before chapter tail: chapter=${this.currentChapterIndex},` +
          `resume=${resumeOffset},expected=${this.ttsReadingExpectedSourceEnd},` +
          `retry=${this.ttsChapterCompletionRetryCount}`);
        await this.startTtsReadingFromCurrentPosition(false, false, -1, resumeOffset, false);
        return;
      }
      console.warn(`[TTS] chapter tail still not confirmed after retries: chapter=${this.currentChapterIndex},` +
        `expected=${this.ttsReadingExpectedSourceEnd}`);
      // Do not silently consume a chapter when the last focus cue never reached its tail. Stopping here
      // leaves the reader on the current chapter so the user can retry/resume from the last confirmed chunk.
      this.ttsChapterAdvanceError = '当前章节末尾朗读未确认，朗读已暂停';
      this.finishTtsReading();
      HdsFeedback.showToast(this.ttsChapterAdvanceError);
      return;
    }
    const advanced = await this.advanceTtsReadingToNextChapter();
    if (token !== this.ttsReadToken || !this.ttsAutoContinue) {
      return;
    }
    if (!advanced) {
      const errorMessage = this.ttsChapterAdvanceError;
      this.finishTtsReading();
      if (errorMessage) {
        HdsFeedback.showToast(errorMessage);
      }
      return;
    }
    await this.startTtsReadingFromCurrentPosition(false);
  }

  isTtsReadingAtExpectedEnd(): boolean {
    if (this.ttsReadingExpectedSourceEnd < 0) return true;
    const chunk = this.ttsLastFocusChunk;
    if (!chunk) return false;
    const spokenEnd = this.readerV2TtsSourceOffset(chunk.end);
    // Chunk boundaries trim only whitespace; tolerate that small non-audible suffix but never a missing paragraph.
    return spokenEnd >= this.ttsReadingExpectedSourceEnd - 4;
  }

  async advanceTtsReadingToNextChapter(): Promise<boolean> {
    this.ttsChapterAdvanceError = '';
    if (this.chapters.length === 0 || this.currentChapterIndex >= this.chapters.length - 1) {
      return false;
    }
    if (this.ttsChapterSwitching) {
      return false;
    }
    const sourceChapterIndex = this.currentChapterIndex;
    const sourcePageIndex = this.currentPageIndex;
    const sourcePendingRestorePageIndex = this.pendingRestorePageIndex;
    const targetChapterIndex = sourceChapterIndex + 1;
    const handoffReadToken = this.ttsReadToken;
    this.ttsChapterSwitching = true;
    try {
      // The completed chapter can still have a queued UI focus callback. Invalidate it before
      // loading the next chapter so an old offset cannot be interpreted against the new page set.
      this.invalidateTtsFocusSession();
      this.ttsLastFocusChunk = null;
      this.ttsLastFocusPageIndex = -1;
      this.ttsAutoTurningPage = false;
      this.ttsPendingTargetPageIndex = -1;
      this.ttsPendingHighlightChunk = null;
      this.ttsPageTurnSerial++;
      this.pendingRestorePageIndex = 0;
      const loaded = await this.loadContent(true, targetChapterIndex);
      if (!loaded || this.currentChapterIndex !== targetChapterIndex) {
        // Roll back only while this automatic handoff still owns the TTS token. A concurrent
        // explicit navigation owns its own chapter state and must not be overwritten here.
        if (handoffReadToken === this.ttsReadToken) {
          if (this.currentChapterIndex !== sourceChapterIndex) {
            this.currentPageIndex = sourcePageIndex;
            this.pendingRestorePageIndex = sourcePageIndex;
            const restored = await this.loadContent(true, sourceChapterIndex);
            if (!restored) {
              console.warn(`[TTS] failed to restore source chapter after handoff failure: ` +
                `source=${sourceChapterIndex}`);
            }
          }
          if (this.currentChapterIndex === sourceChapterIndex) {
            this.currentPageIndex = this.normalizeReaderSpreadPageIndex(
              Math.min(sourcePageIndex, Math.max(0, this.contentPages.length - 1)));
            this.pendingRestorePageIndex = sourcePendingRestorePageIndex;
            this.syncCurrentPageText();
          }
        }
        this.ttsChapterAdvanceError = '下一章正文加载失败，朗读已停止';
        console.warn(`[TTS] automatic chapter handoff failed: source=${sourceChapterIndex},` +
          `target=${targetChapterIndex},actual=${this.currentChapterIndex},loaded=${loaded}`);
        return false;
      }
      this.currentPageIndex = 0;
      this.pendingRestorePageIndex = -1;
      this.syncCurrentPageText();
      this.persistTtsReadPosition(0, 0);
      await this.saveReadingProgress();
      this.updateTtsFloatingSession();
      await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
      return true;
    } finally {
      this.ttsChapterSwitching = false;
    }
  }

  finishTtsReading(): void {
    this.cancelManualPageTurnTtsResume();
    this.flushTtsReadPosition();
    this.clearTtsSleepTimer();
    this.ttsAutoContinue = false;
    this.isTtsSpeaking = false;
    this.isTtsPaused = false;
    ReaderTtsFloatingSession.clear(this.ttsFloatingSessionOwnerId);
    this.releaseBackgroundProgressWriterAfterTtsStop();
    this.updateVolumeKeySubscription();
    this.ttsReader.stop();
    this.invalidateTtsFocusSession();
    this.ttsMediaSession().stopBackgroundRunning();
    this.ttsPageTurnSerial++;
    this.clearTtsHighlight();
    this.ttsLastFocusChunk = null;
    this.ttsLastFocusPageIndex = -1;
    this.ttsReadingExpectedSourceEnd = -1;
    this.ttsChapterCompletionRetryCount = 0;
    if (!this.readerPageVisible) {
      this.ttsReader.shutdown();
    }
  }

  async loadReaderSettings(): Promise<void> {
    try {
      const settings = await ReaderSettingsStore.load(getContext(this));
      ReaderSettingsStore.applyToStorage(settings);
      this.applyLoadedReaderSettings(settings);
      this.loadReaderComicSettings();
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

  // Background audio task, AVSession card and media keys for read-aloud. The page supplies the reading state
  // and executes the commands the system controls send back.
  ttsMediaSession(): ReaderTtsMediaSession {
    if (!this.ttsMedia) {
      this.ttsMedia = new ReaderTtsMediaSession({
        abilityContext: (): common.UIAbilityContext => getContext(this) as common.UIAbilityContext,
        isSpeaking: (): boolean => this.isTtsSpeaking || this.ttsReader.isSpeaking(),
        isPaused: (): boolean => this.isTtsPaused || this.ttsReader.isPaused(),
        audioDebugState: (): string => this.ttsReader.audioDebugState(),
        mediaInfo: (): ReaderTtsMediaInfo => {
          const info: ReaderTtsMediaInfo = {
            bookUrl: this.bookUrl || '',
            bookName: this.book?.name || '',
            author: this.book?.author || '',
            chapterIndex: this.currentChapterIndex,
            chapterTitle: this.getChapterTitle(),
            subtitle: this.getTtsAvSubtitle(),
            pageIndex: this.currentPageIndex,
            elapsedTime: this.getTtsPlaybackElapsedTime(),
            duration: this.getTtsPlaybackDuration(),
            canPlayPrevious: this.canPlayPreviousTtsChapter(),
            canPlayNext: this.canPlayNextTtsChapter()
          };
          return info;
        },
        coverRaw: (): ResourceStr => this.getBookshelfDisplayCoverRaw(),
        onPlay: (): void => {
          if (this.isTtsPaused || this.ttsReader.isPaused()) {
            this.toggleTtsReading();
          } else if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking()) {
            this.startTtsReadingFromCurrentPosition(false);
          }
        },
        onPause: (): void => {
          if (!this.isTtsPaused && (this.isTtsSpeaking || this.ttsReader.isSpeaking())) {
            this.toggleTtsReading();
          }
        },
        onStop: (): void => this.stopTtsReading(),
        onPlayNext: (): void => {
          this.playNextChapterFromMediaSession();
        },
        onPlayPrevious: (): void => {
          this.playPreviousChapterFromMediaSession();
        },
        onSetSpeed: (speed: number): void => this.applyTtsSpeed(speed),
        cacheTaskRunning: (): boolean => this.fullTextCaching,
        cacheHoldsBackground: (): boolean => this.fullTextCacheController().backgroundRunning,
        handBackgroundToCache: (): void => {
          this.fullTextCacheController().backgroundRunning = true;
        }
      });
    }
    return this.ttsMedia;
  }

  async playNextChapterFromMediaSession(): Promise<void> {
    if (!this.canPlayNextTtsChapter()) {
      return;
    }
    const sourceChapterIndex = this.currentChapterIndex;
    const sourcePageIndex = this.currentPageIndex;
    const targetChapterIndex = sourceChapterIndex + 1;
    const now = Date.now();
    if (this.ttsChapterSwitching || now - this.ttsLastMediaChapterCommandAt < 1000) {
      return;
    }
    this.ttsLastMediaChapterCommandAt = now;
    this.ttsChapterSwitching = true;
    try {
      const shouldResume = this.isTtsSpeaking || this.ttsReader.isSpeaking() ||
        ReaderTtsFloatingSession.isOwner(this.ttsFloatingSessionOwnerId);
      console.info(`[TTS] media next chapter: source=${sourceChapterIndex},target=${targetChapterIndex},` +
        `resume=${shouldResume}`);
      if (shouldResume) {
        this.stopTtsReaderForChapterSwitch();
        await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING);
      } else {
        this.stopTtsReading();
      }
      this.currentPageIndex = 0;
      this.pendingRestorePageIndex = 0;
      const loaded = await this.loadContent(true, targetChapterIndex);
      const switched = loaded && this.currentChapterIndex === targetChapterIndex;
      if (switched) {
        await this.saveReadingProgress();
      } else {
        this.currentPageIndex = sourcePageIndex;
        this.pendingRestorePageIndex = sourcePageIndex;
        if (this.currentChapterIndex !== sourceChapterIndex) {
          await this.loadContent(true, sourceChapterIndex);
        } else {
          this.syncCurrentPageText();
        }
        console.warn(`[TTS] next chapter switch did not reach target: target=${targetChapterIndex},` +
          `actual=${this.currentChapterIndex}`);
        HdsFeedback.showToast('下一章加载失败，已保留当前朗读位置');
      }
      if (shouldResume) {
        await this.startTtsReadingFromCurrentPosition(false);
      } else {
        await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP);
      }
    } finally {
      this.ttsChapterSwitching = false;
    }
  }

  async playPreviousChapterFromMediaSession(): Promise<void> {
    if (!this.canPlayPreviousTtsChapter()) {
      return;
    }
    const sourceChapterIndex = this.currentChapterIndex;
    const sourcePageIndex = this.currentPageIndex;
    const targetChapterIndex = sourceChapterIndex - 1;
    const now = Date.now();
    if (this.ttsChapterSwitching || now - this.ttsLastMediaChapterCommandAt < 1000) {
      return;
    }
    this.ttsLastMediaChapterCommandAt = now;
    this.ttsChapterSwitching = true;
    try {
      const shouldResume = this.isTtsSpeaking || this.ttsReader.isSpeaking() ||
        ReaderTtsFloatingSession.isOwner(this.ttsFloatingSessionOwnerId);
      console.info(`[TTS] media previous chapter: source=${sourceChapterIndex},target=${targetChapterIndex},` +
        `resume=${shouldResume}`);
      if (shouldResume) {
        this.stopTtsReaderForChapterSwitch();
        await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING);
      } else {
        this.stopTtsReading();
      }
      this.currentPageIndex = 0;
      this.pendingRestorePageIndex = 0;
      const loaded = await this.loadContent(true, targetChapterIndex);
      const switched = loaded && this.currentChapterIndex === targetChapterIndex;
      if (switched) {
        await this.saveReadingProgress();
      } else {
        this.currentPageIndex = sourcePageIndex;
        this.pendingRestorePageIndex = sourcePageIndex;
        if (this.currentChapterIndex !== sourceChapterIndex) {
          await this.loadContent(true, sourceChapterIndex);
        } else {
          this.syncCurrentPageText();
        }
        console.warn(`[TTS] previous chapter switch did not reach target: target=${targetChapterIndex},` +
          `actual=${this.currentChapterIndex}`);
        HdsFeedback.showToast('上一章加载失败，已保留当前朗读位置');
      }
      if (shouldResume) {
        await this.startTtsReadingFromCurrentPosition(false);
      } else {
        await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP);
      }
    } finally {
      this.ttsChapterSwitching = false;
    }
  }

  async playPositionFromFloatingSession(targetChapterIndex: number, targetPageIndex: number,
    targetSourceOffset: number = -1): Promise<void> {
    const normalizedChapterIndex = this.clampChapterIndex(targetChapterIndex);
    const normalizedPageIndex = Math.max(0, Math.round(targetPageIndex));
    if (normalizedChapterIndex === this.currentChapterIndex && normalizedPageIndex === this.currentPageIndex) {
      return;
    }
    const sourceChapterIndex = this.currentChapterIndex;
    const sourcePageIndex = this.currentPageIndex;
    const now = Date.now();
    if (this.ttsChapterSwitching || now - this.ttsLastMediaChapterCommandAt < 500) {
      return;
    }
    this.ttsLastMediaChapterCommandAt = now;
    this.ttsChapterSwitching = true;
    try {
      const shouldResume = this.isTtsSpeaking || this.ttsReader.isSpeaking() ||
        ReaderTtsFloatingSession.isOwner(this.ttsFloatingSessionOwnerId);
      console.info(`[TTS] floating position: source=${sourceChapterIndex}/${sourcePageIndex},` +
        `target=${normalizedChapterIndex}/${normalizedPageIndex},resume=${shouldResume}`);
      if (shouldResume) {
        this.stopTtsReaderForChapterSwitch();
        await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING);
      }
      this.currentPageIndex = normalizedPageIndex;
      this.pendingRestorePageIndex = normalizedPageIndex;
      const loaded = await this.loadContent(true, normalizedChapterIndex);
      const switched = loaded && this.currentChapterIndex === normalizedChapterIndex;
      if (switched) {
        this.currentPageIndex = this.normalizeReaderSpreadPageIndex(
          Math.min(normalizedPageIndex, Math.max(0, this.contentPages.length - 1)));
        this.pendingRestorePageIndex = -1;
        this.syncCurrentPageText();
        await this.saveReadingProgress();
      } else {
        this.currentPageIndex = sourcePageIndex;
        this.pendingRestorePageIndex = sourcePageIndex;
        if (this.currentChapterIndex !== sourceChapterIndex) {
          await this.loadContent(true, sourceChapterIndex);
        } else {
          this.syncCurrentPageText();
        }
        HdsFeedback.showToast('章节加载失败，已保留当前朗读位置');
      }
      if (shouldResume) {
        const sourceLength = (this.pagedContentText || this.getPagedSourceText()).length;
        const resumeOffset = targetSourceOffset >= 0 ?
          Math.max(0, Math.min(Math.round(targetSourceOffset), sourceLength)) : -1;
        // A retained owner may have only the first cooperative pagination window while the visible
        // mirror already knows the target page. The absolute page start keeps speech on that exact
        // visible page without synchronously rebuilding every preceding native Paragraph.
        await this.startTtsReadingFromCurrentPosition(false, false, -1, resumeOffset);
      }
    } finally {
      this.ttsChapterSwitching = false;
    }
  }

  shouldUseTtsThemeBookCover(): boolean {
    return ThemeBookCoverSettings.enabled(this.appDarkMode, this.themeBookCoverEnabled);
  }

  activeTtsThemeBookCovers(): ResourceStr[] {
    return this.book ? ThemeBookCoverSettings.covers(this.book, this.appDarkMode) : [];
  }

  activeTtsThemeShelfFrame(): ResourceStr {
    return ThemeBookCoverSettings.frame(this.appDarkMode);
  }

  getTtsPanelCoverList(): string[] {
    if (!this.book) {
      return [];
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
    const displayCovers: string[] = [];
    const context = getContext(this);
    for (const raw of covers) {
      const cached = BookCoverCache.resolveCachedCover(context, raw);
      // 加密的书源封面不能直接交给 Image：解密完成前为空，完成后随 sourceCoverRevision 刷新。
      displayCovers.push(cached || (this.sourceCoverRevision >= 0 ? BookCoverCache.displayCover(context, raw) : raw));
    }
    return displayCovers;
  }

  getTtsFloatingCover(): ResourceStr {
    if (this.shouldUseTtsThemeBookCover()) {
      const themeCovers = this.activeTtsThemeBookCovers();
      return themeCovers.length > 0 ? themeCovers[0] : '';
    }
    const covers = this.getTtsPanelCoverList();
    return covers.length > 0 ? covers[0] : '';
  }

  getBookshelfDisplayCoverRaw(): ResourceStr {
    return BookCoverResolver.first(this.book, this.appDarkMode);
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

  getTtsAvSubtitle(): string {
    const progress = this.getProgressText();
    const chapter = this.getChapterTitle();
    return progress ? `${chapter} · ${progress}` : chapter;
  }

  clearTtsHighlight(): void {
    if (!this.ttsDisplayText && this.ttsHighlightStart < 0 && this.ttsHighlightEnd < 0 &&
      this.ttsTextStartOffset === 0 && this.readerV2TtsSourceStart < 0) {
      return;
    }
    this.ttsDisplayText = '';
    this.ttsHighlightStart = -1;
    this.ttsHighlightEnd = -1;
    this.ttsTextStartOffset = 0;
    this.readerV2ActiveSpeechText = null;
    this.readerV2TtsSourceStart = -1;
    this.readerV2TtsSourceEnd = -1;
    this.refreshReaderV2TtsOverlay();
    this.publishTtsHighlightRenderChange();
  }

  publishTtsHighlightRenderChange(): void {
    // V2 owns a root-level lightweight focus layer. Its key observes readerV2TtsPaintVersion directly, so the
    // retained正文 page stays mounted while only the yellow rectangles are replaced.
    if (this.shouldUseReaderLayoutV2(this.pagedContentText) || this.usesReaderContinuousV2()) {
      this.readerV2TtsPaintVersion++;
    } else {
      this.ttsHighlightRenderVersion++;
    }
  }

  currentTtsSourceIdentity(): string {
    const source = this.pagedContentText || this.getPagedSourceText();
    return `${this.currentChapterIndex}_${source.length}_${this.hashText(source)}`;
  }

  invalidateTtsFocusSession(): void {
    this.ttsFocusGeneration++;
    this.ttsFocusChapterIndex = -1;
    this.ttsFocusSourceIdentity = '';
    this.ttsFocusContentLoadSerial = -1;
    this.ttsLastAppliedSourceOffset = -1;
  }

  isCurrentTtsFocusSession(token: number, generation: number,
    chapterIndex: number, sourceIdentity: string): boolean {
    return token === this.ttsReadToken && generation === this.ttsFocusGeneration &&
      chapterIndex === this.ttsFocusChapterIndex && chapterIndex === this.currentChapterIndex &&
      !!sourceIdentity && sourceIdentity === this.ttsFocusSourceIdentity &&
      this.ttsFocusContentLoadSerial === this.contentLoadSerial && this.isTtsSpeaking && this.ttsAutoContinue;
  }

  getTtsReadingText(startOffset: number = -1): string {
    const source = this.pagedContentText || this.getPagedSourceText();
    const pageStart = this.getCurrentPageStartOffset();
    let start = startOffset >= pageStart ? Math.min(Math.round(startOffset), source.length) : pageStart;
    const containingMarker = ReaderActionMarker.findRawRangeContaining(source, start);
    if (containingMarker.length >= 2) start = containingMarker[1];
    this.ttsTextStartOffset = start;
    if (this.shouldUseReaderLayoutV2(source)) {
      const document = this.readerV2Document(this.currentChapterIndex, source);
      if (document) {
        this.readerV2ActiveSpeechText = ReaderV2SpeechText.build(document, start);
        return this.readerV2ActiveSpeechText.text;
      }
    }
    this.readerV2ActiveSpeechText = null;
    return ReaderActionMarker.strip(LocalBookService.stripEpubImageMarkers(source.substring(start), true), true);
  }

  getTtsFocusBreakOffsets(textLength: number): number[] {
    const result: number[] = [];
    for (const pageStart of this.contentPageStarts) {
      const offset = this.readerV2ActiveSpeechText ? this.readerV2ActiveSpeechText.speechOffsetAt(pageStart) :
        pageStart - this.ttsTextStartOffset;
      if (offset > 0 && offset < textLength) {
        result.push(offset);
      }
    }
    return result;
  }

  getPagedSourceText(): string {
    return this.buildPagedSourceText(this.currentChapterIndex, this.content || '');
  }

  buildPagedSourceText(chapterIndex: number, content: string): string {
    const title = this.getChapterTitle(chapterIndex).trim();
    // Paragraph comments change both measured line width and paragraph grouping. Build pagination from the
    // effective source state: when the source switch is explicitly off, remove only comment actions while
    // retaining images, videos and unrelated source-provided actions.
    const effectiveContent = this.readerParagraphCommentsEnabledForPagination() ?
      (content || '') : this.stripReaderParagraphCommentActions(content || '');
    const leadingAction = ReaderActionMarker.findFirst(effectiveContent);
    const titleAction = leadingAction && leadingAction.start === 0 && leadingAction.data.title === '章评' ?
      leadingAction.marker : '';
    const contentBody = titleAction && leadingAction ?
      effectiveContent.substring(leadingAction.end).replace(/^\s+/, '') :
      effectiveContent;
    const sourceBody = this.stripDuplicatedChapterTitle(this.normalizeChapterBody(contentBody), title);
    const body = this.buildIndentedChapterBody(sourceBody);
    if (LocalBookService.hasEpubImageMarkers(body) &&
      !LocalBookService.stripEpubImageMarkers(body).trim()) {
      return body;
    }
    if (!title) {
      return body;
    }
    const heading = titleAction ? `${title}${titleAction}` : title;
    const volumeTitle = this.readerVolumeTitle(chapterIndex);
    if (!volumeTitle) {
      return `${heading}\n\n${body}`;
    }
    // A volume's first chapter: the volume name becomes a heading, and cover images the source puts at the start
    // of the chapter move under it. Unsized covers fill the rest of that page, so the chapter title starts a new one.
    const parts = ReaderTextNormalizer.splitLeadingImages(body);
    return parts[0] ? `${volumeTitle}\n\n${parts[0]}\n\n${heading}\n\n${parts[1]}` :
      `${volumeTitle}\n\n${heading}\n\n${body}`;
  }

  normalizeChapterBody(text: string): string {
    return ReaderTextNormalizer.normalizeChapterBody(text);
  }

  buildIndentedChapterBody(text: string): string {
    return ReaderTextNormalizer.indentChapterBody(text, this.readerParagraphIndent);
  }

  stripDuplicatedChapterTitle(body: string, title: string): string {
    return ReaderTextNormalizer.stripDuplicatedTitle(body, title);
  }

  toMeasurePx(value: number): number {
    try {
      return Math.max(1, vp2px(value));
    } catch (_) {
      return Math.max(1, value);
    }
  }

  toMeasureNonNegativePx(value: number): number {
    if (!Number.isFinite(value) || value <= 0) return 0;
    try {
      return Math.max(0, vp2px(value));
    } catch (_) {
      return Math.max(0, value);
    }
  }

  toMeasureFontPx(value: number): number {
    try {
      return Math.max(1, fp2px(value));
    } catch (_) {
      return this.toMeasurePx(value);
    }
  }

  toMeasureFontOffsetPx(value: number): number {
    if (!Number.isFinite(value) || value === 0) return 0;
    try {
      return fp2px(value);
    } catch (_) {
      return value;
    }
  }

  followTtsChunk(chunk: TtsChunk, token: number, generation: number,
    chapterIndex: number, sourceIdentity: string): void {
    // Playback cues already arrive on the ArkTS event loop at the audible segment boundary. Deferring them through
    // another timer lets pagination/layout work overtake the focus update, so the previous sentence can remain
    // highlighted after the next sentence is already audible.
    if (!this.isCurrentTtsFocusSession(token, generation, chapterIndex, sourceIdentity)) {
      return;
    }
    this.applyTtsChunkFocus(chunk);
    this.updateTtsFloatingSession();
  }

  applyTtsChunkFocus(chunk: TtsChunk): void {
    const absoluteStart = this.readerV2TtsSourceOffset(chunk.start);
    // Cloud/custom audio may finish a cancelled prefetch after the replacement session has
    // already advanced. Never allow an older focus cue to move the visible reader backwards.
    if (this.ttsLastAppliedSourceOffset >= 0 && absoluteStart < this.ttsLastAppliedSourceOffset) return;
    this.ttsLastAppliedSourceOffset = absoluteStart;
    const pageIndex = this.findPageIndexByOffset(absoluteStart);
    const spreadPageIndex = this.normalizeReaderSpreadPageIndex(pageIndex);
    const firstFocusInSession = !this.ttsLastFocusChunk;
    this.ttsLastFocusChunk = chunk;
    this.ttsLastFocusPageIndex = pageIndex;
    // Publish the destination range before mounting the incoming page. Both legacy text and V2 rectangles filter
    // the range by page, so it cannot leak onto the outgoing leaf; it does let the new sentence appear highlighted
    // during the turn instead of waiting until the animation has finished while audio continues playing.
    this.updateTtsChunkHighlight(chunk, pageIndex);
    if (this.usesReaderContinuousV2()) {
      this.followReaderContinuousTtsFocus(firstFocusInSession);
      return;
    }
    if (spreadPageIndex !== this.currentPageIndex) {
      this.animateTtsToPage(spreadPageIndex, chunk);
      return;
    }
    if (firstFocusInSession) {
      // Starting TTS can replace the continuous-scroll reader with the paged surface in this same UI turn.
      // Republish the first cue after that new surface has mounted instead of relying on the pre-mount frame.
      this.scheduleTtsFocusRepublishAfterPageTurn(this.currentChapterIndex, pageIndex,
        this.readerV2TtsSourceStart, this.readerV2TtsSourceEnd);
    }
  }

  saveReaderChromeSettings(headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string): void {
    ReaderSettingsStore.saveReaderChromeSettings(
      getContext(this),
      headerEnabled,
      footerEnabled,
      infoBarConfig
    ).catch((e: Error) => {
      console.warn('保存阅读页眉页脚设置失败:', e);
    });
  }

  syncTtsFocusAfterResumeLater(delayMs: number): void {
    const serial = ++this.ttsResumeSyncSerial;
    const focusGeneration = this.ttsFocusGeneration;
    const readToken = this.ttsReadToken;
    setTimeout(() => {
      if (serial < this.ttsResumeSyncSerial - 1) {
        return;
      }
      if (focusGeneration !== this.ttsFocusGeneration || readToken !== this.ttsReadToken) return;
      this.syncTtsFocusAfterResume();
    }, delayMs);
  }

  syncTtsFocusAfterResume(): void {
    if (!this.isTtsSpeaking || !this.ttsAutoContinue || this.contentPages.length === 0) {
      return;
    }
    if (this.ttsManualPageTurnResumePending || this.isPageTurning || this.ttsAutoTurningPage ||
      this.ttsChapterSwitching) return;
    if (!this.ttsLastFocusChunk && !this.restorePersistedTtsFocus()) return;
    if (!this.ttsLastFocusChunk) return;
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
    if (this.usesReaderContinuousV2()) {
      this.updateTtsChunkHighlight(this.ttsLastFocusChunk, pageIndex);
      this.followReaderContinuousTtsFocus(true);
      return;
    }
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
    const absoluteStart = this.readerV2TtsSourceOffset(chunk.start);
    return this.findPageIndexByOffset(absoluteStart);
  }

  updateTtsChunkHighlight(chunk: TtsChunk, pageIndex: number, persistPosition: boolean = true): void {
    const absoluteStart = this.readerV2TtsSourceOffset(chunk.start);
    const absoluteEnd = this.readerV2TtsSourceOffset(chunk.end);
    const pageStart = this.getPageStartOffset(pageIndex);
    const pageEnd = this.getPageEndOffset(pageIndex);
    const pageText = this.getPageText(pageIndex);
    this.ttsDisplayText = pageText;
    if (pageIndex === this.currentPageIndex &&
      (this.currentPageText !== pageText || this.displayPageText !== pageText ||
        this.displayPageChapterIndex !== this.currentChapterIndex || this.displayPageIndex !== this.currentPageIndex)) {
      this.setCurrentPageText(pageText);
    }
    this.ttsHighlightStart = Math.max(0, Math.min(absoluteStart - pageStart, pageText.length));
    this.ttsHighlightEnd = Math.max(this.ttsHighlightStart, Math.min(absoluteEnd, pageEnd) - pageStart);
    this.readerV2TtsSourceStart = absoluteStart;
    this.readerV2TtsSourceEnd = absoluteEnd;
    this.refreshReaderV2TtsOverlay();
    if (persistPosition) this.persistTtsReadPosition(absoluteStart, absoluteEnd);
    this.publishTtsHighlightRenderChange();
    if (this.isPageTurning || this.ttsAutoTurningPage || this.ttsManualPageTurnResumePending) {
      this.scheduleTtsFocusRepublishAfterPageTurn(this.currentChapterIndex, pageIndex,
        absoluteStart, absoluteEnd);
    }
  }

  scheduleTtsFocusRepublishAfterPageTurn(chapterIndex: number, pageIndex: number,
    absoluteStart: number, absoluteEnd: number): void {
    const serial = ++this.ttsSurfaceFocusSyncSerial;
    this.republishTtsFocusAfterPageTurn(serial, chapterIndex, pageIndex, absoluteStart, absoluteEnd, 0);
  }

  scheduleCurrentTtsFocusRepublishAfterPageTurn(): void {
    if (this.readerV2TtsSourceStart < 0 || this.readerV2TtsSourceEnd <= this.readerV2TtsSourceStart ||
      !this.shouldRenderTtsFocus()) return;
    const pageIndex = this.findPageIndexByOffset(this.readerV2TtsSourceStart);
    if (pageIndex < 0 || pageIndex >= this.contentPages.length) return;
    this.scheduleTtsFocusRepublishAfterPageTurn(this.currentChapterIndex, pageIndex,
      this.readerV2TtsSourceStart, this.readerV2TtsSourceEnd);
  }

  republishTtsFocusAfterPageTurn(serial: number, chapterIndex: number, pageIndex: number,
    absoluteStart: number, absoluteEnd: number, attempt: number): void {
    setTimeout(() => {
      if (serial !== this.ttsSurfaceFocusSyncSerial || chapterIndex !== this.currentChapterIndex ||
        this.normalizeReaderSpreadPageIndex(pageIndex) !== this.currentPageIndex ||
        absoluteStart !== this.readerV2TtsSourceStart || absoluteEnd !== this.readerV2TtsSourceEnd ||
        !this.shouldRenderTtsFocus()) return;
      if (this.isPageTurning || this.ttsAutoTurningPage || this.ttsManualPageTurnResumePending ||
        this.mirroredTtsManualTurnPending) {
        if (attempt < 3) {
          this.republishTtsFocusAfterPageTurn(serial, chapterIndex, pageIndex,
            absoluteStart, absoluteEnd, attempt + 1);
        }
        return;
      }
      // The current/incoming reader surfaces alternate during rapid turns. Republish only the
      // lightweight rectangle layer after the final surface owns the page.
      this.publishTtsHighlightRenderChange();
    }, attempt === 0 ? 32 : 64);
  }

  scheduleTtsFocusSyncAfterPagination(): void {
    const serial = ++this.ttsPaginationFocusSyncSerial;
    const chapterIndex = this.currentChapterIndex;
    const source = this.pagedContentText;
    // Pagination is commonly followed by a synchronous current-page restore. Reconcile on the next UI task so
    // that restore has settled and the replacement ArkUI/V2 surface exists before its focus layer is republished.
    setTimeout(() => {
      if (serial !== this.ttsPaginationFocusSyncSerial || chapterIndex !== this.currentChapterIndex ||
        source !== this.pagedContentText) return;
      this.syncActiveTtsFocusAfterPagination();
    }, 0);
  }

  syncActiveTtsFocusAfterPagination(): void {
    if (!this.readerInitialPageReady || this.pendingRestorePageIndex >= 0 ||
      this.readerTypographyRestoreOffset >= 0 || this.contentPages.length === 0) return;
    if (this.isMirroringActiveTtsForCurrentBook()) {
      this.syncMirroredTtsFocus().then(() => {
        this.scheduleCurrentTtsFocusRepublishAfterPageTurn();
      }).catch((error: Error) => {
        console.warn('分页更新后同步后台朗读焦点失败:', error);
      });
      return;
    }
    const chunk = this.ttsLastFocusChunk;
    if (!chunk || !this.isTtsSpeaking || !this.ttsAutoContinue ||
      this.ttsFocusChapterIndex !== this.currentChapterIndex ||
      this.ttsFocusContentLoadSerial !== this.contentLoadSerial ||
      this.ttsFocusSourceIdentity !== this.currentTtsSourceIdentity()) return;
    const absoluteStart = this.readerV2TtsSourceOffset(chunk.start);
    const lastKnownEnd = this.contentPageEnds.length > 0 ?
      this.contentPageEnds[this.contentPageEnds.length - 1] : 0;
    if (absoluteStart >= lastKnownEnd && lastKnownEnd < this.pagedContentText.length) return;
    const pageIndex = this.findPageIndexByOffset(absoluteStart);
    if (pageIndex < 0 || pageIndex >= this.contentPages.length) return;
    const targetPageIndex = this.normalizeReaderSpreadPageIndex(pageIndex);
    if (this.usesReaderContinuousV2()) {
      this.ttsLastFocusPageIndex = pageIndex;
      this.updateTtsChunkHighlight(chunk, pageIndex, false);
      return;
    }
    if (this.isPageTurning || this.ttsAutoTurningPage || this.ttsManualPageTurnResumePending) {
      this.scheduleCurrentTtsFocusRepublishAfterPageTurn();
      return;
    }
    if (targetPageIndex !== this.currentPageIndex) {
      this.finishPageTurnAnimation();
      this.currentPageIndex = targetPageIndex;
      this.syncCurrentPageText();
    } else if (this.displayPageChapterIndex !== this.currentChapterIndex ||
      this.displayPageIndex !== this.currentPageIndex || this.displayPageText !== this.getCurrentPageText()) {
      this.syncCurrentPageText();
    }
    this.ttsLastFocusPageIndex = pageIndex;
    this.updateTtsChunkHighlight(chunk, pageIndex, false);
    this.scheduleCurrentTtsFocusRepublishAfterPageTurn();
  }

  persistTtsReadPosition(absoluteStart: number, absoluteEnd: number): void {
    if (!this.book) return;
    const sourceLength = (this.pagedContentText || this.getPagedSourceText()).length;
    const start = Math.max(0, Math.min(Math.round(absoluteStart), sourceLength));
    const end = Math.max(start, Math.min(Math.round(absoluteEnd), sourceLength));
    this.book.putVariable('ttsReadChapterIndex', `${this.currentChapterIndex}`);
    this.book.putVariable('ttsReadOffsetStart', `${start}`);
    this.book.putVariable('ttsReadOffsetEnd', `${end}`);
    ReaderTtsFloatingSession.updatePosition(
      this.ttsFloatingSessionOwnerId, this.currentChapterIndex, start, end);
    if (this.ttsProgressSaveTimerId >= 0) return;
    this.ttsProgressSaveTimerId = setTimeout(() => {
      this.ttsProgressSaveTimerId = -1;
      this.saveReadingProgress().catch((error: Error) => {
        console.warn('保存朗读句子位置失败:', error);
      });
    }, 3000);
  }

  flushTtsReadPosition(): void {
    if (this.ttsProgressSaveTimerId < 0) return;
    clearTimeout(this.ttsProgressSaveTimerId);
    this.ttsProgressSaveTimerId = -1;
    // When reading stops behind the bookshelf, the shelf is the visible page and must pick up the new position.
    this.saveReadingProgress(!this.readerPageVisible).catch((error: Error) => {
      console.warn('立即保存朗读句子位置失败:', error);
    });
  }

  releaseBackgroundProgressWriterAfterTtsStop(): void {
    // The stop-time save is queued; keep the permission until it settles. A chapter switch re-attaches the
    // floating session right away, in which case this page is still the reader and keeps its permission.
    this.readingProgressSaveQueue.finally(() => {
      if (ReaderTtsFloatingSession.isOwner(this.ttsFloatingSessionOwnerId)) return;
      ReaderProgressCheckpoint.releaseBackground(this.ttsFloatingSessionOwnerId);
    });
  }

  async flushReadingProgressCheckpoint(): Promise<void> {
    // Normal page turns are debounced. Cancel every delayed writer and persist the current chapter/page snapshot
    // immediately before Harmony freezes the UI in Home or lock-screen background transitions.
    this.settleCommittedLocalPageTurnForCheckpoint();
    this.clearReaderComicProgressSaveTimer();
    this.clearReaderPagedProgressSaveTimer();
    if (this.ttsProgressSaveTimerId >= 0) {
      clearTimeout(this.ttsProgressSaveTimerId);
      this.ttsProgressSaveTimerId = -1;
    }
    await this.saveReadingProgress(true);
  }

  restorePersistedTtsFocus(): boolean {
    if (!this.book) return false;
    const chapterRaw = this.book.getVariable('ttsReadChapterIndex');
    const startRaw = this.book.getVariable('ttsReadOffsetStart');
    const endRaw = this.book.getVariable('ttsReadOffsetEnd');
    if (!chapterRaw || !startRaw) return false;
    const chapterIndex = Number(chapterRaw);
    const absoluteStart = Number(startRaw);
    const absoluteEnd = Number(endRaw);
    if (!Number.isFinite(chapterIndex) || chapterIndex !== this.currentChapterIndex ||
      !Number.isFinite(absoluteStart) || absoluteStart < this.ttsTextStartOffset) {
      return false;
    }
    const source = this.pagedContentText || this.getPagedSourceText();
    const start = Math.max(this.ttsTextStartOffset, Math.min(Math.round(absoluteStart), source.length));
    const end = Math.max(start, Math.min(Number.isFinite(absoluteEnd) ? Math.round(absoluteEnd) : start,
      source.length));
    const chunkStart = this.readerV2ActiveSpeechText ?
      this.readerV2ActiveSpeechText.speechOffsetAt(start) : start - this.ttsTextStartOffset;
    const chunkEnd = this.readerV2ActiveSpeechText ?
      this.readerV2ActiveSpeechText.speechOffsetAt(end) : end - this.ttsTextStartOffset;
    this.ttsLastFocusChunk = {
      text: source.substring(start, end),
      start: chunkStart,
      end: chunkEnd
    };
    return true;
  }

  activeMirroredTtsChapterIndex(): number {
    if (!this.globalTtsActive || ReaderTtsFloatingSession.isOwner(this.ttsFloatingSessionOwnerId) ||
      !this.bookUrl || this.globalTtsBookUrl !== this.bookUrl || !Number.isFinite(this.globalTtsChapterIndex)) {
      return -1;
    }
    const chapterIndex = Math.round(this.globalTtsChapterIndex);
    return chapterIndex >= 0 && chapterIndex < this.chapters.length ? chapterIndex : -1;
  }

  isMirroringActiveTtsForCurrentBook(): boolean {
    return this.globalTtsActive && this.globalTtsMode === 'tts' && !!this.bookUrl &&
      this.globalTtsBookUrl === this.bookUrl &&
      !ReaderTtsFloatingSession.isOwner(this.ttsFloatingSessionOwnerId);
  }

  async syncMirroredTtsFocus(): Promise<void> {
    if (this.mirroredTtsManualTurnPending) return;
    const serial = ++this.mirroredTtsFocusSyncSerial;
    const chapterIndex = this.activeMirroredTtsChapterIndex();
    if (chapterIndex < 0 || !this.book || this.contentPages.length === 0) {
      this.clearMirroredTtsFocus();
      return;
    }
    if (chapterIndex !== this.currentChapterIndex) {
      const loaded = await this.loadContent(true, chapterIndex);
      if (serial !== this.mirroredTtsFocusSyncSerial) return;
      if (!loaded || this.currentChapterIndex !== chapterIndex) {
        this.clearMirroredTtsFocus();
        return;
      }
    }
    const source = this.pagedContentText || this.getPagedSourceText();
    if (!source || !Number.isFinite(this.globalTtsOffsetStart)) {
      this.clearMirroredTtsFocus();
      return;
    }
    const absoluteStart = Math.max(0, Math.min(Math.round(this.globalTtsOffsetStart), source.length));
    const absoluteEnd = Math.max(absoluteStart,
      Math.min(Number.isFinite(this.globalTtsOffsetEnd) ? Math.round(this.globalTtsOffsetEnd) : absoluteStart,
        source.length));
    if (absoluteEnd <= absoluteStart) {
      this.clearMirroredTtsFocus();
      return;
    }
    const pageIndex = this.findPageIndexByOffset(absoluteStart);
    if (pageIndex < 0 || pageIndex >= this.contentPages.length) {
      this.clearMirroredTtsFocus();
      return;
    }
    const pageStart = this.getPageStartOffset(pageIndex);
    const pageEnd = this.getPageEndOffset(pageIndex);
    const pageText = this.getPageText(pageIndex);
    this.mirroredTtsFocusActive = true;
    const targetPageIndex = this.normalizeReaderSpreadPageIndex(pageIndex);
    if (this.usesReaderContinuousV2()) {
      this.readerV2TtsSourceStart = absoluteStart;
      this.readerV2TtsSourceEnd = absoluteEnd;
      this.publishTtsHighlightRenderChange();
      this.followReaderContinuousTtsFocus(false);
      return;
    }
    if (targetPageIndex !== this.currentPageIndex) {
      this.finishPageTurnAnimation();
      this.currentPageIndex = targetPageIndex;
      this.syncCurrentPageText();
    } else if (this.displayPageChapterIndex !== this.currentChapterIndex ||
      this.displayPageIndex !== this.currentPageIndex || !this.displayPageText) {
      this.syncCurrentPageText();
    }
    this.ttsDisplayText = pageText;
    this.ttsHighlightStart = Math.max(0, Math.min(absoluteStart - pageStart, pageText.length));
    this.ttsHighlightEnd = Math.max(this.ttsHighlightStart,
      Math.min(absoluteEnd, pageEnd) - pageStart);
    this.readerV2TtsSourceStart = absoluteStart;
    this.readerV2TtsSourceEnd = absoluteEnd;
    this.refreshReaderV2TtsOverlay();
    this.publishTtsHighlightRenderChange();
  }

  clearMirroredTtsFocus(): void {
    if (!this.mirroredTtsFocusActive) return;
    this.mirroredTtsFocusActive = false;
    this.clearTtsHighlight();
  }

  shouldRenderTtsFocus(): boolean {
    return this.isTtsSpeaking || this.mirroredTtsFocusActive;
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
      while (turnSerial === this.ttsPageTurnSerial && this.isTtsSpeaking && this.ttsAutoContinue &&
        this.ttsPendingTargetPageIndex > this.currentPageIndex && this.canTurnPage(1)) {
        const targetPageIndex = this.normalizeReaderSpreadPageIndex(Math.min(
          this.ttsPendingTargetPageIndex, Math.max(0, this.contentPages.length - 1)));
        if (targetPageIndex <= this.currentPageIndex) break;
        if (targetPageIndex > this.currentPageIndex + this.getReaderPageTurnStep()) {
          await this.runTtsPageTurnAnimationTo(targetPageIndex, turnSerial);
        } else {
          await this.runTtsPageTurnAnimation(1, turnSerial);
        }
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
        // The incoming animation surface is gone at this boundary. Publish the current chunk once
        // more to the stable page overlay so focus never remains owned only by that temporary leaf.
        this.scheduleCurrentTtsFocusRepublishAfterPageTurn();
      }
      // A user turn can arrive while the automatic TTS page animation is in
      // progress. It is queued by runPageTurnAnimation and must run as soon as
      // the automatic animation releases the page-turn lock.
      if (!this.ttsAutoTurningPage && !this.isPageTurning) {
        this.runQueuedPageTurnLater();
      }
    }
  }

  async runTtsPageTurnAnimationTo(targetPageIndex: number, turnSerial: number): Promise<void> {
    const target = this.normalizeReaderSpreadPageIndex(Math.max(0,
      Math.min(targetPageIndex, Math.max(0, this.contentPages.length - 1))));
    if (this.isPageTurning || target <= this.currentPageIndex) return;
    this.isPageTurning = true;
    try {
      if (!this.isPageTurnAnimationEnabled()) {
        this.applyTtsPageTarget(target, turnSerial);
        const targetText = this.getCurrentPageText();
        this.commitVisibleCurrentPageText(targetText);
        this.finishPageTurnAnimation();
        this.commitCurrentPageTextLater(this.currentChapterIndex, this.currentPageIndex, targetText);
        return;
      }
      const distance = this.getPageTurnDistance();
      this.prepareSlidePageTurn(1, 0);
      this.pageTurnCrossChapterHandoff = false;
      this.setPageTurnIncomingState(target, this.getPageText(target), true, this.currentChapterIndex,
        this.getSecondaryPageText(target), this.getPageStartOffset(target),
        this.isLandscapeDoublePageActive() ? this.getPageStartOffset(target + 1) : -1,
        this.pagedContentText);
      this.requestReaderPageCurlCapture();
      if (this.usesReaderPageCurlCanvas()) {
        await this.completeSimulationPageTurnMotion(1);
      } else {
        const duration = 140;
        await this.runReaderAnimation(duration, this.pageTurnAnimationCurve(), () => {
          this.setPageSlideAxisOffset(-distance);
          this.pageTransitionOpacity = 1;
        });
      }
      this.applyTtsPageTarget(target, turnSerial);
      await this.finishAnimatedPageTurn();
    } finally {
      this.isPageTurning = false;
    }
  }

  applyTtsPageTarget(targetPageIndex: number, turnSerial: number): void {
    if (turnSerial !== this.ttsPageTurnSerial || !this.isTtsSpeaking || !this.ttsAutoContinue) return;
    const target = this.normalizeReaderSpreadPageIndex(Math.max(this.currentPageIndex,
      Math.min(targetPageIndex, Math.max(0, this.contentPages.length - 1))));
    this.currentPageIndex = target;
    this.syncCurrentPageText();
    if (this.contentPages.length - target <= 3) this.preloadReaderContent();
    this.scheduleReaderPagedProgressSave();
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
      } else if (this.readerEffectivePageTurnMode() === 1) {
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
    if (this.isSimulationPageTurnAnimation()) {
      await this.completeSimulationPageTurnMotion(direction);
    } else {
      const duration = 140;
      await this.runReaderAnimation(duration, this.pageTurnAnimationCurve(), () => {
        this.setPageSlideAxisOffset(direction > 0 ? -distance : distance);
        this.pageTransitionOpacity = 1;
      });
    }
    await this.applyTtsPageTurn(direction, turnSerial);
    await this.finishAnimatedPageTurn();
  }

  async runTtsSlidePageTurn(direction: number, turnSerial: number): Promise<void> {
    const distance = this.getPageTurnDistance();
    this.prepareSlidePageTurn(direction, this.getPageSlideAxisOffset());
    if (this.isSimulationPageTurnAnimation()) {
      await this.completeSimulationPageTurnMotion(direction);
    } else {
      const duration = 150;
      await this.runReaderAnimation(duration, this.pageTurnAnimationCurve(), () => {
        this.setPageSlideAxisOffset(direction > 0 ? -distance : distance);
        this.pageTransitionOpacity = 1;
      });
    }
    await this.applyTtsPageTurn(direction, turnSerial);
    await this.finishAnimatedPageTurn();
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
        // Keep speech focus responsive; the existing debounce persists the latest page without
        // blocking every automatic animation on a database transaction.
        this.scheduleReaderPagedProgressSave();
      } else {
        await this.loadNextChapter();
      }
      return;
    }

    const localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
    if (localPageIndex >= 0) {
      this.currentPageIndex = localPageIndex;
      this.syncCurrentPageText();
      this.scheduleReaderPagedProgressSave();
    } else {
      await this.loadPrevChapter(true);
    }
  }

  // Resolves when the property animation has actually finished. A fixed timer drifts from the real end on a
  // busy frame: firing early commits the page under a still-moving leaf, firing late leaves the finished leaf
  // idle. The bounded fallback only covers a lost finish callback, e.g. the app is backgrounded mid-animation.
  runReaderAnimation(duration: number, curve: Curve | ICurve, apply: () => void): Promise<void> {
    return new Promise<void>((resolve) => {
      let settled = false;
      let fallbackTimerId = -1;
      const settle = (): void => {
        if (settled) return;
        settled = true;
        if (fallbackTimerId >= 0) clearTimeout(fallbackTimerId);
        resolve();
      };
      fallbackTimerId = setTimeout(settle, Math.max(0, duration) + 120);
      animateTo({ duration: duration, curve: curve, onFinish: settle }, apply);
    });
  }

  private suspendReaderPaginationWork(): void {
    // Stop scheduled closures without invalidating the immutable page snapshot currently owned by ArkUI.
    // onPageShow can continue the retained pagination session instead of rebuilding its Paragraph objects.
    this.readerPaginationWorkSerial++;
    this.adjacentPaginationPreloadSerial++;
    this.previousPaginationPreloadSerial++;
  }

  private resumeReaderPaginationWorkAfterPageShow(): void {
    this.resumeCurrentReaderPaginationCompletion();
    this.preloadReaderContentLater();
  }

  // 本章分页会话的后台补排链在页面不可见、被别的会话顶掉序号时会静默退出，这里按当前键重新挂上。
  resumeCurrentReaderPaginationCompletion(): void {
    if (!this.pagedContentText || !this.hasPagedReaderArea()) return;
    const key = this.buildReaderPaginationCacheKey(this.currentChapterIndex, this.pagedContentText);
    const result = this.readerPaginationCache.get(key);
    if (result && !result.complete) {
      this.scheduleReaderPaginationCompletion(this.currentChapterIndex, key, result);
    }
  }

  @Builder
  readerActiveCurrentPageSurface(currentRenderVersion: number, currentText: string,
    ttsRenderVersion: number) {
    if (this.currentReaderSurfaceIndex() === 0) {
      if (this.isPageTurnAnimationEnabled() && !this.usesReaderPageCurlCanvas()) {
        this.readerSlidingPageTurnSurface(currentText, currentRenderVersion, ttsRenderVersion)
      } else {
        this.readerCurrentPageSurface(currentRenderVersion, currentText, ttsRenderVersion)
      }
    } else {
      if (this.isPageTurnAnimationEnabled() && !this.usesReaderPageCurlCanvas()) {
        this.readerSlidingPageTurnSurfaceAlternate(currentText, currentRenderVersion, ttsRenderVersion)
      } else {
        this.readerCurrentPageSurfaceAlternate(currentRenderVersion, currentText, ttsRenderVersion)
      }
    }
  }

  async waitForReaderComicBoundaryRestore(timeoutMs: number = 1800): Promise<void> {
    const deadline = Date.now() + Math.max(0, timeoutMs);
    while (Date.now() < deadline &&
      (this.pendingRestorePageIndex >= 0 || this.readerTypographyRestoreOffset >= 0 ||
        this.isPagedReaderAwaitingPagination() || !this.readerInitialPageReady)) {
      await sleepMs(16);
    }
  }

  @Builder
  readerSlidingPageTurnSurface(currentText: string, currentRenderVersion: number, ttsRenderVersion: number) {
    Stack() {
      if (this.shouldRenderSlidingPageTurn()) {
        if (this.isSimulationPageTurnAnimation()) {
          this.readerSimulationPageTurnSurface(currentRenderVersion, currentText, ttsRenderVersion, 'primary')
        } else if (this.isStackPageTurnAnimation()) {
          this.readerCurrentPageSurface(currentRenderVersion, currentText, ttsRenderVersion)
          this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion,
            this.getVisiblePageTurnIncomingText(), 'incoming_primary')
        } else {
          this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion,
            this.getVisiblePageTurnIncomingText(), 'incoming_primary')
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
    .expandSafeArea([SafeAreaType.SYSTEM], this.getReaderPageTurnSurfaceSafeAreaEdges())
  }

  @Builder
  readerSlidingPageTurnSurfaceAlternate(currentText: string, currentRenderVersion: number, ttsRenderVersion: number) {
    Stack() {
      if (this.shouldRenderSlidingPageTurn()) {
        if (this.isSimulationPageTurnAnimation()) {
          this.readerSimulationPageTurnSurface(currentRenderVersion, currentText, ttsRenderVersion, 'alternate')
        } else if (this.isStackPageTurnAnimation()) {
          this.readerCurrentPageSurfaceAlternate(currentRenderVersion, currentText, ttsRenderVersion)
          this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion,
            this.getVisiblePageTurnIncomingText(), 'incoming_alternate')
        } else {
          this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion,
            this.getVisiblePageTurnIncomingText(), 'incoming_alternate')
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
    .expandSafeArea([SafeAreaType.SYSTEM], this.getReaderPageTurnSurfaceSafeAreaEdges())
  }

  @Builder
  readerSimulationPageTurnSurface(currentRenderVersion: number, currentText: string, ttsRenderVersion: number,
    surfaceRole: string) {
    if (this.isLandscapeDoublePageActive()) {
      this.readerSimulationDoublePageTurnSurface(currentRenderVersion, currentText, ttsRenderVersion, surfaceRole)
    } else {
      this.readerSimulationSinglePageTurnSurface(currentRenderVersion, currentText, ttsRenderVersion, surfaceRole)
    }
  }

  @Builder
  readerSimulationSinglePageTurnSurface(currentRenderVersion: number, currentText: string,
    ttsRenderVersion: number, surfaceRole: string) {
    Stack() {
      Stack() {
        this.readerSimulationPaperBackground()
        Column() {
          this.readerIncomingPageLayer(this.pageTurnIncomingRenderVersion,
            this.getVisiblePageTurnIncomingText(), `${surfaceRole}_simulation_back`)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.getReaderPageContentTopPadding() })
      }
      .width('100%')
      .height('100%')
      // Snapshot can capture an off-screen component by id. Keeping this duplicate out of the viewport avoids
      // replacing the already-visible Paragraph tree for the one or two frames before capture completes.
      .position({ x: -this.getPageTurnWidth() * 2, y: 0 })
      .id('reader_page_curl_back_single')
      .renderGroup(true)

      Stack() {
        this.readerSimulationPaperBackground()
        this.readerIncomingPageSurface(this.pageTurnIncomingRenderVersion,
          this.getVisiblePageTurnIncomingText(), `${surfaceRole}_simulation_base`)
      }
      .width('100%')
      .height('100%')
      // Until both textures are ready the stable current surface below remains the only visible正文.
      .opacity(this.readerPageCurlSnapshotReady ? 1 : 0)

    }
    .width('100%')
    .height('100%')
    // The overlay is mounted as soon as the drag direction is known, one frame before the asynchronous front/back
    // snapshots become ready. An opaque outer paper therefore covered the still-valid live page with an empty sheet
    // for that frame. The ready-gated destination surface above already paints its own paper, so keep this host clear.
    .backgroundColor(Color.Transparent)
    .clip(true)
  }

  @Builder
  readerSimulationDoublePageTurnSurface(currentRenderVersion: number, currentText: string,
    ttsRenderVersion: number, surfaceRole: string) {
    Stack() {
      Stack() {
        // The back of the turning leaf belongs to the opposite half of the target spread.
        // Crop it from one spread-sized background instead of fitting a second wallpaper
        // inside this half-width snapshot.
        this.readerSimulationHalfPaperBackground(this.pageSlideDirection < 0)
        if (this.pageSlideDirection > 0) {
          this.readerSimulationIncomingHalfPage(this.pageTurnIncomingText, this.pageTurnIncomingPageIndex,
            this.pageTurnIncomingPageStart, this.pageTurnIncomingRenderVersion,
            `${surfaceRole}_leaf_back_capture`)
        } else {
          this.readerSimulationIncomingHalfPage(this.pageTurnIncomingSecondaryText,
            this.pageTurnIncomingPageIndex + 1, this.pageTurnIncomingSecondaryPageStart,
            this.pageTurnIncomingRenderVersion, `${surfaceRole}_leaf_back_capture`)
        }
      }
      .width(this.getReaderPageColumnWidth())
      .height('100%')
      .position({ x: -this.getPageTurnWidth() * 2, y: 0 })
      .id('reader_page_curl_back_double')
      .renderGroup(true)

      // Keep the non-turning half on the stable正文 surface below this overlay. Rebuilding that half with a
      // second native Paragraph controller made it jump by a fractional layout pixel whenever the snapshot
      // became ready. Only the destination half that really changes needs an opaque paper and正文 layer here.
      Stack() {
        this.readerSimulationHalfPaperBackground(this.pageSlideDirection > 0)
        if (this.pageSlideDirection > 0) {
          this.readerSimulationIncomingHalfPage(this.pageTurnIncomingSecondaryText,
            this.pageTurnIncomingPageIndex + 1, this.pageTurnIncomingSecondaryPageStart,
            this.pageTurnIncomingRenderVersion, `${surfaceRole}_base_right`)
        } else {
          this.readerSimulationIncomingHalfPage(this.pageTurnIncomingText, this.pageTurnIncomingPageIndex,
            this.pageTurnIncomingPageStart, this.pageTurnIncomingRenderVersion,
            `${surfaceRole}_base_left`)
        }
      }
      .width(this.getReaderPageColumnWidth())
      .height('100%')
      .position({ x: this.pageSlideDirection > 0 ? this.getReaderDoublePageRightOrigin() : 0, y: 0 })
      .opacity(this.readerPageCurlSnapshotReady ? 1 : 0)

      Column()
        .width(2)
        .height('94%')
        .position({ x: this.getReaderPageColumnWidth(), y: '3%' })
        .linearGradient({
          angle: 0,
          colors: [['#00000000', 0], [this.getSimulationSpineColor(), 0.5], ['#00000000', 1]]
        })
        .opacity(this.readerPageCurlSnapshotReady ? 1 : 0)

    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .clip(true)
  }

  @Builder
  readerSimulationCurlCanvas() {
    Canvas(this.readerPageCurlContext)
      .width('100%')
      .height('100%')
      .opacity(this.readerPageCurlSnapshotReady ? 1 : 0)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.readerPageCurlCanvasReady = true;
        this.drawReaderPageCurl();
      })
  }

  @Builder
  readerSimulationPaperBackground() {
    ReaderThemeBackground({
      surfaceColor: this.getBackgroundColor(),
      backgroundAssetId: this.getBackgroundAssetId(),
      customImage: this.currentReaderTheme().backgroundImageUri,
      customImageFit: this.getBackgroundImageFit(),
      viewportWidthHint: this.getPageTurnWidth(),
      viewportHeightHint: this.getReaderBackgroundViewportHeight()
    })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerSimulationHalfPaperBackground(rightHalf: boolean) {
    Stack() {
      ReaderThemeBackground({
        surfaceColor: this.getBackgroundColor(),
        backgroundAssetId: this.getBackgroundAssetId(),
        customImage: this.currentReaderTheme().backgroundImageUri,
        customImageFit: this.getBackgroundImageFit(),
        viewportWidthHint: this.getPageTurnWidth(),
        viewportHeightHint: this.getReaderBackgroundViewportHeight()
      })
        .width(this.getPageTurnWidth())
        .height('100%')
        .position({ x: rightHalf ? -this.getReaderDoublePageRightOrigin() : 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerSimulationIncomingHalfPage(text: string, pageIndex: number, pageStart: number,
    renderVersion: number, identity: string, halfWidth: boolean = false) {
    Column() {
      if (this.shouldUseReaderLayoutV2(this.pageTurnIncomingDocumentSource) &&
        this.readerV2Page(this.pageTurnIncomingChapterIndex, pageIndex, this.pageTurnIncomingDocumentSource)) {
        this.readerV2PageSurface(`simulation_incoming_${identity}`, this.pageTurnIncomingChapterIndex,
          pageIndex, this.pageTurnIncomingDocumentSource)
      } else {
        this.readerPlainTextLeaf(text)
      }
    }
    .width(halfWidth ? this.getReaderPageColumnWidth() : '100%')
    .height('100%')
    .padding({ top: this.getReaderPageContentTopPadding() })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  currentReaderSurfaceId(alternate: boolean, renderVersion: number, ttsRenderVersion: number): string {
    if (this.shouldUseReaderLayoutV2(this.pagedContentText)) {
      return alternate ? 'reader_current_v2_alternate' : 'reader_current_v2_primary';
    }
    const prefix = alternate ? 'reader_current_alt' : 'reader_current';
    return `${prefix}_${this.currentChapterIndex}_${this.currentPageIndex}_${this.displayPageRenderKey}_` +
      `${renderVersion}_${ttsRenderVersion}`;
  }

  currentReaderSnapshotComponentId(): string {
    return this.currentReaderSurfaceId(this.currentReaderSurfaceIndex() !== 0,
      this.pageRenderVersion, this.ttsHighlightRenderVersion);
  }

  @Builder
  readerCurrentPageSurface(renderVersion: number, text: string, ttsRenderVersion: number) {
    Stack() {
      if (this.isStackPageTurnAnimation() || this.isSimulationPageTurnAnimation() ||
        this.is3DPageTurnAnimation()) {
        // Stack and simulation animate/snapshot a full-screen sheet, so their page must own the paper artwork.
        // Slide and fade live below the status-bar inset: painting the same Cover image here would restart its
        // crop at the content origin and create a visible seam against the full-screen root background.
        this.readerSimulationPaperBackground()
      }
      Column() {
        this.readerCurrentPageLayer(renderVersion, text, ttsRenderVersion, 'current_primary')
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getReaderPageContentTopPadding() })
    }
    .width('100%')
    .height('100%')
    .id(this.currentReaderSurfaceId(false, renderVersion, ttsRenderVersion))
    .backgroundColor(this.readerContentLayerColor())
    .translate({ x: this.getCurrentPageTurnX(), y: this.getCurrentPageTurnY() + this.bookmarkPullOffsetY })
    .opacity(this.getCurrentPageTurnOpacity())
  }

  @Builder
  readerCurrentPageSurfaceAlternate(renderVersion: number, text: string, ttsRenderVersion: number) {
    Stack() {
      if (this.isStackPageTurnAnimation() || this.isSimulationPageTurnAnimation() ||
        this.is3DPageTurnAnimation()) {
        this.readerSimulationPaperBackground()
      }
      Column() {
        this.readerCurrentPageLayer(renderVersion, text, ttsRenderVersion, 'current_alternate')
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getReaderPageContentTopPadding() })
    }
    .width('100%')
    .height('100%')
    .id(this.currentReaderSurfaceId(true, renderVersion, ttsRenderVersion))
    .backgroundColor(this.readerContentLayerColor())
    .translate({ x: this.getCurrentPageTurnX(), y: this.getCurrentPageTurnY() + this.bookmarkPullOffsetY })
    .opacity(this.getCurrentPageTurnOpacity())
  }

  @Builder
  readerIncomingPageSurface(renderVersion: number, text: string, controllerRole: string = 'incoming') {
    Stack() {
      if (this.isStackPageTurnAnimation() || this.is3DPageTurnAnimation()) {
        this.readerIncomingPageBackground()
      }
      Column() {
        this.readerIncomingPageLayer(renderVersion, text, controllerRole)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getReaderPageContentTopPadding() })
    }
    .width('100%')
    .height('100%')
    .id(`reader_incoming_${this.pageTurnIncomingChapterIndex}_${this.pageTurnIncomingPageIndex}_${renderVersion}`)
    .backgroundColor(this.readerContentLayerColor())
    .renderGroup(true)
    .translate({ x: this.getIncomingSlideX(), y: this.getIncomingSlideY() })
    .opacity(this.getVisiblePageTurnIncomingOpacity())
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerIncomingPageBackground() {
    ReaderThemeBackground({
      surfaceColor: this.getBackgroundColor(),
      backgroundAssetId: this.getBackgroundAssetId(),
      customImage: this.currentReaderTheme().backgroundImageUri,
      customImageFit: this.getBackgroundImageFit(),
      viewportWidthHint: this.pageViewWidth,
      viewportHeightHint: this.getReaderBackgroundViewportHeight()
    })
      .id('reader_incoming_theme_background')
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerCurrentPageLayer(renderVersion: number, text: string, ttsRenderVersion: number,
    controllerRole: string = 'current') {
    if (this.shouldUseReaderLayoutV2(this.pagedContentText) &&
      this.readerV2Page(this.currentChapterIndex, this.currentPageIndex, this.pagedContentText)) {
      if (this.isLandscapeDoublePageActive()) {
        Row() {
          this.readerV2PageSurface(`${controllerRole}_left`, this.currentChapterIndex,
            this.currentPageIndex, this.pagedContentText, true)
          Blank()
            .width(READER_DOUBLE_PAGE_DIVIDER_WIDTH)
            .height('88%')
            .backgroundColor(this.getSubTextColor())
            .opacity(0.22)
          this.readerV2PageSurface(`${controllerRole}_right`, this.currentChapterIndex,
            this.currentPageIndex + 1, this.pagedContentText, true)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        this.readerV2PageSurface(`${controllerRole}_single`, this.currentChapterIndex,
          this.currentPageIndex, this.pagedContentText)
      }
    } else {
      this.readerPlainTextLeaf(text)
    }
  }

  @Builder
  readerIncomingPageLayer(renderVersion: number, text: string, controllerRole: string = 'incoming') {
    if (this.shouldUseReaderLayoutV2(this.pageTurnIncomingDocumentSource) &&
      this.readerV2Page(this.pageTurnIncomingChapterIndex, this.pageTurnIncomingPageIndex,
        this.pageTurnIncomingDocumentSource)) {
      if (this.isLandscapeDoublePageActive()) {
        Row() {
          this.readerV2PageSurface(`${controllerRole}_left`, this.pageTurnIncomingChapterIndex,
            this.pageTurnIncomingPageIndex, this.pageTurnIncomingDocumentSource, true)
          Blank()
            .width(READER_DOUBLE_PAGE_DIVIDER_WIDTH)
            .height('88%')
            .backgroundColor(this.getSubTextColor())
            .opacity(0.22)
          this.readerV2PageSurface(`${controllerRole}_right`, this.pageTurnIncomingChapterIndex,
            this.pageTurnIncomingPageIndex + 1, this.pageTurnIncomingDocumentSource, true)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        this.readerV2PageSurface(`${controllerRole}_single`, this.pageTurnIncomingChapterIndex,
          this.pageTurnIncomingPageIndex, this.pageTurnIncomingDocumentSource)
      }
    } else {
      this.readerPlainTextLeaf(text)
    }
  }

  // Text shown where no V2 page exists yet: loading and error placeholders, and the brief moment before an
  // adjacent chapter has been paginated. Markers are stripped; nothing here is selectable or interactive.
  @Builder
  readerPlainTextLeaf(text: string) {
    Text(ReaderActionMarker.strip(LocalBookService.stripEpubImageMarkers(text || '', false), false))
      .fontSize(this.readerFontSize)
      .fontWeight(this.readerFontWeight, { enableVariableFontWeight: true })
      .fontFamily(this.getBodyReaderFontFamily())
      .fontColor(this.getTextColor())
      .lineSpacing(LengthMetrics.vp(Math.max(0, this.readerLineHeight)))
      .textAlign(this.readerTextAlignValue())
      .width('100%')
      .padding({
        left: this.getEffectiveReaderMarginLeft(),
        right: this.getEffectiveReaderMarginRight(),
        top: this.getEffectiveReaderMarginTop(),
        bottom: this.getReaderContentBottomPadding()
      })
      .hitTestBehavior(HitTestMode.None)
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

  readerPageRenderIdentity(prefix: string, chapterIndex: number, pageIndex: number, renderVersion: number,
    ttsRenderVersion: number, text: string, displayKey: number = 0): string {
    return `${prefix}_${chapterIndex}_${pageIndex}_${displayKey}_${renderVersion}_${ttsRenderVersion}_` +
      `${this.buildTextSliceKey(text || '')}`;
  }

  registerMergedReaderInlineSourceActionBounds(task: ReaderMergedActionBoundsTask, visibleText: string): boolean {
    let hasVisibleMarker = false;
    for (const paragraph of task.paragraphs) {
      const match = this.readerInlineSourceActionMatch(paragraph.text);
      if (match && visibleText.includes(match.marker)) {
        hasVisibleMarker = true;
        break;
      }
    }
    if (!hasVisibleMarker) return true;
    try {
      const manager = this.readerSelectableTextController(task.selectableKey).getLayoutManager();
      if (!manager) {
        if (task.attempts >= 7) console.warn('合并正文段评布局尚未就绪，点击区域注册失败');
        return false;
      }
      let cursor = 0;
      for (let paragraphIndex = 0; paragraphIndex < task.paragraphs.length; paragraphIndex++) {
        const paragraph = task.paragraphs[paragraphIndex];
        const bodyText = this.hasInlineReaderSourceAction(paragraph.text) ?
          this.readerInlineSourceActionText(paragraph.text) : paragraph.text;
        const label = this.hasInlineReaderSourceAction(paragraph.text) ?
          this.readerInlineSourceActionLabel(paragraph.text) : '';
        if (label) {
          const match = this.readerInlineSourceActionMatch(paragraph.text);
          if (match && visibleText.includes(match.marker)) {
            const labelStart = cursor + bodyText.length;
            const labelEnd = labelStart + label.length;
            const boxes: graphicsText.TextBox[] = manager.getRectsForRange({ start: labelStart, end: labelEnd },
              graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.MAX);
            for (const box of boxes) {
              const localLeft = px2vp(box.rect.left);
              const localTop = px2vp(box.rect.top);
              const localRight = px2vp(box.rect.right);
              const localBottom = px2vp(box.rect.bottom);
              this.rememberReaderSourceActionBounds(match.marker, task.left + localLeft, task.top + localTop,
                task.left + localRight, task.top + localBottom);
            }
          }
        }
        cursor += bodyText.length + label.length;
        if (paragraphIndex < task.paragraphs.length - 1) cursor++;
      }
      return true;
    } catch (error) {
      if (task.attempts >= 7) console.warn('合并正文段评点击区域计算失败:', error);
      return false;
    }
  }

  hasInlineReaderSourceAction(text: string): boolean {
    const match = this.readerInlineSourceActionMatch(text);
    return !!match && (match.start > 0 || match.end < (text || '').length);
  }

  readerInlineSourceActionMatch(text: string): ReaderActionMatch | null {
    const source = text || '';
    const cached = this.readerActionMatchCache.get(source);
    if (cached) return cached;
    const match = ReaderActionMarker.findFirst(source);
    if (!match) return null;
    this.readerActionMatchCache.set(source, match);
    while (this.readerActionMatchCache.size > 192) {
      const oldest = this.readerActionMatchCache.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      this.readerActionMatchCache.delete(oldest);
    }
    return match;
  }

  readerInlineActionTextController(text: string): TextController {
    const match = this.readerInlineSourceActionMatch(text);
    const key = match ? match.marker : text;
    let controller = this.readerInlineActionTextControllers.get(key);
    if (!controller) {
      controller = new TextController();
      this.readerInlineActionTextControllers.set(key, controller);
      while (this.readerInlineActionTextControllers.size > 80) {
        const oldest = this.readerInlineActionTextControllers.keys().next().value as string | undefined;
        if (!oldest) break;
        this.readerInlineActionTextControllers.delete(oldest);
      }
    }
    return controller;
  }

  readerInlineActionExpectedWidth(): number {
    const spreadWidth = this.getReaderPageColumnWidth();
    return Math.max(1, spreadWidth - this.getEffectiveReaderMarginLeft() - this.getEffectiveReaderMarginRight());
  }

  readerInlineActionLocalBounds(text: string, componentWidth: number, componentHeight: number): number[] {
    const match = this.readerInlineSourceActionMatch(text);
    if (!match) return [];
    try {
      const manager = this.readerInlineActionTextController(text).getLayoutManager();
      const lineCount = manager.getLineCount();
      if (lineCount <= 0) return [];
      const lastMetric = manager.getLineMetrics(lineCount - 1);
      const layoutEnd = lastMetric.endIndex;
      const labelLength = this.readerInlineSourceActionLabel(text).length;
      const labelStart = Math.max(0, layoutEnd - labelLength);
      const boxes: graphicsText.TextBox[] = manager.getRectsForRange({ start: labelStart, end: layoutEnd },
        graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.MAX);
      const rawBounds: number[] = [];
      for (const box of boxes) {
        if (box.rect.right > box.rect.left && box.rect.bottom > box.rect.top) {
          rawBounds.push(box.rect.left, box.rect.top, box.rect.right, box.rect.bottom);
        }
      }
      if (rawBounds.length === 0) {
        const estimatedWidth = Math.min(lastMetric.width,
          this.toMeasurePx(Math.max(28, labelLength * this.readerInlineSourceActionFontSize(text) * 0.58)));
        const top = Math.max(0, lastMetric.baseline - lastMetric.ascent);
        rawBounds.push(Math.max(lastMetric.left, lastMetric.left + lastMetric.width - estimatedWidth), top,
          lastMetric.left + lastMetric.width, top + lastMetric.height);
      }
      let maxRight = 0;
      let maxBottom = 0;
      for (let index = 0; index + 3 < rawBounds.length; index += 4) {
        maxRight = Math.max(maxRight, rawBounds[index + 2]);
        maxBottom = Math.max(maxBottom, rawBounds[index + 3]);
      }
      const pxCoordinates = (componentWidth > 0 && maxRight > componentWidth * 1.5) ||
        (componentHeight > 0 && maxBottom > componentHeight * 1.5);
      if (!pxCoordinates) return rawBounds;
      const bounds: number[] = [];
      for (const value of rawBounds) {
        try {
          bounds.push(px2vp(value));
        } catch (_) {
          bounds.push(value);
        }
      }
      return bounds;
    } catch (_) {
      return [];
    }
  }

  clearPendingReaderSourceActionBounds(): void {
    this.readerPendingInlineActionBounds.clear();
    this.readerPendingMergedActionBounds.clear();
  }

  scheduleReaderSourceActionBoundsFlush(delayMs: number = 0): void {
    if (this.readerSourceActionBoundsFlushPending) return;
    this.readerSourceActionBoundsFlushPending = true;
    setTimeout(() => {
      this.readerSourceActionBoundsFlushPending = false;
      this.flushPendingReaderSourceActionBounds();
    }, delayMs);
  }

  flushPendingReaderSourceActionBounds(): void {
    if (this.isPageTurning || this.pageTurnAnimating || this.pageSlideDirection !== 0) {
      this.scheduleReaderSourceActionBoundsFlush(72);
      return;
    }
    const visibleText = this.visibleCurrentPageText();
    const actionDocumentText = this.isReaderNovelContinuousScrollModeActive() ?
      (this.pagedContentText || this.content) : visibleText;
    const inlineRetries: ReaderInlineActionBoundsTask[] = [];
    const mergedRetries: ReaderMergedActionBoundsTask[] = [];
    let remainingBudget = 6;
    for (const entry of this.readerPendingInlineActionBounds.entries()) {
      if (remainingBudget <= 0) break;
      const marker = entry[0];
      const task = entry[1];
      this.readerPendingInlineActionBounds.delete(marker);
      if (actionDocumentText.includes(marker)) {
        const registered = this.registerReaderInlineSourceActionBounds(task.text, task.marker, task.left, task.top,
          task.width, task.height);
        if (!registered && task.attempts < 8) {
          task.attempts++;
          inlineRetries.push(task);
        } else if (!registered) {
          console.warn('正文段评布局尚未就绪，点击区域注册失败');
        }
      }
      remainingBudget--;
    }
    if (remainingBudget > 0) {
      for (const entry of this.readerPendingMergedActionBounds.entries()) {
        if (remainingBudget <= 0) break;
        const selectableKey = entry[0];
        const task = entry[1];
        this.readerPendingMergedActionBounds.delete(selectableKey);
        const registered = this.registerMergedReaderInlineSourceActionBounds(task, actionDocumentText);
        if (!registered && task.attempts < 8) {
          task.attempts++;
          mergedRetries.push(task);
        }
        remainingBudget--;
      }
    }
    for (const task of inlineRetries) this.readerPendingInlineActionBounds.set(task.marker, task);
    for (const task of mergedRetries) this.readerPendingMergedActionBounds.set(task.selectableKey, task);
    if (this.readerPendingInlineActionBounds.size > 0 || this.readerPendingMergedActionBounds.size > 0) {
      this.scheduleReaderSourceActionBoundsFlush(16);
    }
  }

  registerReaderInlineSourceActionBounds(text: string, marker: string, left: number, top: number,
    width: number, height: number): boolean {
    if (!marker || !Number.isFinite(left) || !Number.isFinite(top)) return true;
    const localBounds = this.readerInlineActionLocalBounds(text,
      width > 0 ? width : this.readerInlineActionExpectedWidth(), height > 0 ? height : this.pageViewHeight);
    if (localBounds.length < 4) return false;
    const globalBounds: number[] = [];
    for (let index = 0; index + 3 < localBounds.length; index += 4) {
      globalBounds.push(left + localBounds[index], top + localBounds[index + 1],
        left + localBounds[index + 2], top + localBounds[index + 3]);
    }
    this.readerSourceActionAreas.set(marker, globalBounds);
    return true;
  }

  readerInlineSourceActionText(text: string): string {
    const match: ReaderActionMatch | null = this.readerInlineSourceActionMatch(text);
    if (!match) return text || '';
    return `${text.substring(0, match.start)}${text.substring(match.end)}`;
  }

  readerInlineSourceActionLabel(text: string): string {
    const match: ReaderActionMatch | null = this.readerInlineSourceActionMatch(text);
    if (!match) return '';
    const count = (match.data.label || '').match(/(99\+|\d+)\s*$/);
    // Counts use their actual 1/2/3-cell width inside the paragraph. Values above 99 are capped at 99+
    // so large provider counts remain bounded without forcing every smaller pill to the largest width.
    const prefix = '\u2060\u00A0\u00A0◌\u00A0';
    const suffix = '\u00A0\u00A0';
    if (count && count[1]) {
      const rawCount = count[1];
      const numericCount = rawCount === '99+' ? 100 : Number.parseInt(rawCount, 10);
      const label = !Number.isFinite(numericCount) || numericCount <= 0 ? '0' :
        (numericCount > 99 ? '99+' : `${Math.round(numericCount)}`);
      return `${prefix}${label}${suffix}`;
    }
    if (/本章说/.test(match.data.label || '')) return `${prefix}本章说${suffix}`;
    return /段评|评论/.test(match.data.label || '') ? `${prefix}段评${suffix}` : `${prefix}${suffix}`;
  }

  readerInlineSourceActionFontSize(text: string): number {
    if (!this.readerUsesConfiguredCommentBubble(text)) return Math.max(10, this.readerFontSize - 5);
    return this.readerSourceSettingEnabled('气泡增大') ? Math.max(12, this.readerFontSize - 2) :
      Math.max(10, this.readerFontSize - 5);
  }

  readerUsesConfiguredCommentBubble(text: string): boolean {
    const match = this.readerInlineSourceActionMatch(text);
    if (!match || !/段评|评论|本章说/.test(match.data.label || '')) return false;
    const source = this.currentReaderSource();
    if (!source) return false;
    this.ensureReaderSourceSettingCache(source);
    return this.readerSourceHasCommentBubbleScript || !!this.readerSourceSettingValue('段评样式');
  }

  readerSourceSettingValue(key: string): string {
    const source = this.currentReaderSource();
    if (!source || !key) return '';
    this.ensureReaderSourceSettingCache(source);
    return BookSourceRuntimeSnapshotStore.get(source).getString(key);
  }

  ensureReaderSourceSettingCache(source: BookSource): void {
    const snapshot = BookSourceRuntimeSnapshotStore.get(source);
    const sourceKey = source.bookSourceUrl || source.bookSourceName || '__anonymous_source__';
    const contentRule = source.contentRule?.content || '';
    const jsLib = source.jsLib || '';
    if (this.readerSourceSettingCacheKey === sourceKey &&
      this.readerSourceSettingCacheRevision === snapshot.signature &&
      this.readerSourceSettingCacheContentRule === contentRule &&
      this.readerSourceSettingCacheJsLib === jsLib) {
      return;
    }
    this.readerSourceSettingCacheKey = sourceKey;
    this.readerSourceSettingCacheRevision = snapshot.signature;
    this.readerSourceSettingCacheContentRule = contentRule;
    this.readerSourceSettingCacheJsLib = jsLib;
    this.readerSourceHasCommentBubbleScript = contentRule.includes('段评样式') || jsLib.includes('段评样式');
  }

  readerSourceSettingEnabled(key: string): boolean {
    return BookSourceSettingValue.state(this.readerSourceSettingValue(key)) > 0;
  }

  readerSourceColorSetting(key: string, fallback: string): string {
    const value = this.readerSourceSettingValue(key).trim();
    if (!value) return fallback;
    if (value.toLowerCase() === 'transparent') return '#00000000';
    return /^#[0-9a-f]{3,8}$/i.test(value) ? value : fallback;
  }

  beginReaderInteractiveAction(): void {
    this.readerInteractiveActionUntil = Date.now() + 700;
    this.deferReaderPaginationForInteraction(700);
    this.suppressReaderTapClick = true;
    this.readerTouchActive = false;
    this.readerPanActive = false;
  }

  setReaderTextSelectionActive(active: boolean): void {
    const next = active && this.isReaderNovelContinuousScrollModeActive();
    if (this.readerTextSelectionActive === next) return;
    this.readerTextSelectionActive = next;
    if (!next) return;
    // Once long press owns the pointer, neither the List nor the parallel chapter-boundary pan may consume handle
    // drags. Cancel any partial boundary feedback produced before the long-press threshold was reached.
    this.cancelReaderComicPan();
    this.readerTouchActive = false;
    this.readerPanActive = false;
    this.suppressReaderTapClick = true;
  }

  /**
   * A selection can be live in three shapes: the continuous-scroll flag, the V2 native selection host
   * mounted over the page, and the V2 painted overlay. All three must be treated as "selecting" so a
   * tap outside the selection dismisses instead of turning the page or opening the menu.
   */
  hasReaderTextSelection(): boolean {
    return this.readerTextSelectionActive ||
      this.readerV2NativeSelectionFragmentIndex >= 0 ||
      this.readerV2SelectionDisplayStart >= 0;
  }

  /**
   * Dismisses an active selection without running the action the tap would otherwise perform, so a tap
   * outside the selection cancels it instead of turning the page or opening the reader menu. Handle drags
   * (movement) are left to the native selection so the range can still be adjusted. Dismissal only arms
   * for a pointer whose Down began while the selection was already live; the release of the press that
   * created the selection passes through here on Up and must never clear it.
   */
  handleReaderSelectionDismissTouch(event: TouchEvent): boolean {
    if (!this.hasReaderTextSelection()) {
      return false;
    }
    const point = event.changedTouches && event.changedTouches.length > 0 ? event.changedTouches[0] :
      (event.touches && event.touches.length > 0 ? event.touches[0] : null);
    if (!point) {
      return false;
    }
    const windowX = Number(point.windowX);
    const windowY = Number(point.windowY);
    const globalX = Number.isFinite(windowX) ? windowX : Number(point.x) + this.readerTapLayerGlobalX;
    const globalY = Number.isFinite(windowY) ? windowY : Number(point.y) + this.readerTapLayerGlobalY;
    if (!Number.isFinite(globalX) || !Number.isFinite(globalY)) {
      return false;
    }
    if (event.type === TouchType.Down) {
      this.readerSelectionDismissDownX = globalX;
      this.readerSelectionDismissDownY = globalY;
      this.readerSelectionDismissDownAt = Date.now();
      this.readerSelectionDismissMoved = false;
      this.readerSelectionDismissArmed = true;
      return true;
    }
    if (event.type === TouchType.Move) {
      if (Math.abs(globalX - this.readerSelectionDismissDownX) > this.readerTapSlop ||
        Math.abs(globalY - this.readerSelectionDismissDownY) > this.readerTapSlop) {
        this.readerSelectionDismissMoved = true;
      }
      return true;
    }
    if (event.type === TouchType.Up) {
      const moved = this.readerSelectionDismissMoved;
      const armed = this.readerSelectionDismissArmed;
      const duration = Date.now() - this.readerSelectionDismissDownAt;
      this.readerSelectionDismissDownX = -1;
      this.readerSelectionDismissDownY = -1;
      this.readerSelectionDismissMoved = false;
      this.readerSelectionDismissArmed = false;
      if (armed && !moved && duration < 380) {
        this.scheduleReaderTextSelectionClear();
      }
      return true;
    }
    this.readerSelectionDismissArmed = false;
    return true;
  }

  isReaderInteractiveActionActive(): boolean {
    return Date.now() < this.readerInteractiveActionUntil;
  }

  rememberReaderSourceActionBounds(marker: string, left: number, top: number, right: number, bottom: number): void {
    if (!marker || !Number.isFinite(left) || !Number.isFinite(top) || !Number.isFinite(right) ||
      !Number.isFinite(bottom) || right <= left || bottom <= top) return;
    const values = this.readerSourceActionAreas.get(marker) || [];
    for (let index = 0; index + 3 < values.length; index += 4) {
      if (Math.abs(values[index] - left) < 1 && Math.abs(values[index + 1] - top) < 1 &&
        Math.abs(values[index + 2] - right) < 1 && Math.abs(values[index + 3] - bottom) < 1) return;
    }
    values.push(left, top, right, bottom);
    const scrollOffsets = this.readerSourceActionScrollOffsets.get(marker) || [];
    scrollOffsets.push(this.currentContinuousReaderScrollOffset());
    while (values.length > 48) {
      values.splice(0, 4);
      if (scrollOffsets.length > 0) scrollOffsets.shift();
    }
    this.readerSourceActionAreas.set(marker, values);
    this.readerSourceActionScrollOffsets.set(marker, scrollOffsets);
    // A comment-heavy chapter can expose well over 40 actions at once. Evicting the earliest
    // registrations here makes the still-visible comments at the beginning of the chapter untappable.
    // The map is cleared with the reader document/chapter lifecycle, so retain a full practical chapter.
    while (this.readerSourceActionAreas.size > 512) {
      const oldest = this.readerSourceActionAreas.keys().next().value as string | undefined;
      if (!oldest) break;
      this.readerSourceActionAreas.delete(oldest);
      this.readerSourceActionScrollOffsets.delete(oldest);
    }
  }

  rememberReaderTapLayerArea(area: Area): void {
    this.readerTapLayerGlobalX = Number(area.globalPosition.x);
    this.readerTapLayerGlobalY = Number(area.globalPosition.y);
  }

  currentContinuousReaderScrollOffset(): number {
    if (!this.isReaderNovelContinuousScrollModeActive()) return 0;
    // onAreaChange 在滚动期间随位置变化逐帧触发，可见块的两个 Text 每帧都会记录区域。
    // currentOffset() 是同步原生查询；同一帧内的回调共享一次读取即可，8ms 窗口内复用。
    const now = Date.now();
    if (now - this.readerContinuousScrollOffsetMemoAt < 8) {
      return this.readerContinuousScrollOffsetMemo;
    }
    try {
      const offset = Number(this.readerComicScroller.currentOffset().yOffset);
      this.readerContinuousScrollOffsetMemo = Number.isFinite(offset) ? offset : 0;
    } catch (_) {
      this.readerContinuousScrollOffsetMemo = 0;
    }
    this.readerContinuousScrollOffsetMemoAt = now;
    return this.readerContinuousScrollOffsetMemo;
  }

  rememberContinuousReaderPointer(event: TouchEvent): void {
    const point = event.changedTouches && event.changedTouches.length > 0 ? event.changedTouches[0] :
      (event.touches && event.touches.length > 0 ? event.touches[0] : null);
    if (!point) return;
    const windowX = Number(point.windowX);
    const windowY = Number(point.windowY);
    const globalX = Number.isFinite(windowX) ? windowX : Number(point.x) + this.readerTapLayerGlobalX;
    const globalY = Number.isFinite(windowY) ? windowY : Number(point.y) + this.readerTapLayerGlobalY;
    if (!Number.isFinite(globalX) || !Number.isFinite(globalY)) return;
    this.readerContinuousPointerGlobalX = globalX;
    this.readerContinuousPointerGlobalY = globalY;
    this.readerContinuousPointerAt = Date.now();
    if (!this.isReaderNovelContinuousScrollModeActive()) return;
    if (this.hasReaderTextSelection()) {
      this.readerContinuousSelectionMoved = true;
      this.cancelContinuousReaderSelectionTimer();
      // The selection owns this pointer stream: a short tap dismisses it, a drag adjusts the native
      // range. Neither may reach the List, the chapter-boundary pan or the tap zones.
      this.handleReaderSelectionDismissTouch(event);
      return;
    }
    if (event.type === TouchType.Down) {
      this.readerSelectionDismissArmed = false;
      this.cancelContinuousReaderSelectionTimer();
      this.readerContinuousSelectionDownX = globalX;
      this.readerContinuousSelectionDownY = globalY;
      this.readerContinuousSelectionDownAt = Date.now();
      this.readerContinuousSelectionMoved = false;
      this.readerContinuousSelectionTimerId = setTimeout(() => {
        this.readerContinuousSelectionTimerId = -1;
        if (!this.readerPageVisible || !this.isReaderNovelContinuousScrollModeActive()) return;
        this.selectReaderTextAtPoint(this.readerContinuousSelectionDownX, this.readerContinuousSelectionDownY);
      }, 420);
      return;
    }
    if (event.type === TouchType.Move &&
      (Math.abs(globalX - this.readerContinuousSelectionDownX) > this.readerTapSlop ||
       Math.abs(globalY - this.readerContinuousSelectionDownY) > this.readerTapSlop)) {
      this.readerContinuousSelectionMoved = true;
      this.cancelContinuousReaderSelectionTimer();
      return;
    }
    if (event.type === TouchType.Up) {
      this.cancelContinuousReaderSelectionTimer();
      const duration = Date.now() - this.readerContinuousSelectionDownAt;
      if (!this.readerContinuousSelectionMoved && duration < 380) {
        this.handleContinuousReaderShortTap(globalX, globalY);
      }
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.readerContinuousSelectionMoved = true;
      this.cancelContinuousReaderSelectionTimer();
    }
  }

  handleContinuousReaderShortTap(globalX: number, globalY: number): void {
    if (this.hasReaderTextSelection()) {
      this.scheduleReaderTextSelectionClear();
      return;
    }
    const marker = this.readerSourceActionAtPoint(globalX, globalY);
    if (marker) {
      this.beginReaderInteractiveAction();
      this.openReaderSourceAction(marker);
      return;
    }
    if (this.consumeSuppressedReaderTapClick()) return;
    if (Date.now() >= this.readerComicSuppressClickUntil &&
      !this.showMenu && !this.showToc && !this.showSettings) {
      this.showMenu = true;
    }
  }

  cancelContinuousReaderSelectionTimer(): void {
    if (this.readerContinuousSelectionTimerId < 0) return;
    clearTimeout(this.readerContinuousSelectionTimerId);
    this.readerContinuousSelectionTimerId = -1;
  }

  readerContinuousGesturePoint(event: GestureEvent): number[] {
    if (Date.now() - this.readerContinuousPointerAt <= 1200 &&
      Number.isFinite(this.readerContinuousPointerGlobalX) && Number.isFinite(this.readerContinuousPointerGlobalY)) {
      return [this.readerContinuousPointerGlobalX, this.readerContinuousPointerGlobalY];
    }
    if (event.fingerList && event.fingerList.length > 0) {
      const finger = event.fingerList[0];
      const x = Number(finger.globalX);
      const y = Number(finger.globalY);
      if (Number.isFinite(x) && Number.isFinite(y)) return [x, y];
    }
    return [];
  }

  // Source action under a window point of the scrolling list. The paged reader hit-tests its own layout.
  readerSourceActionAtPoint(globalX: number, globalY: number): string {
    return this.usesReaderContinuousV2() ? this.readerContinuousV2ActionAtPoint(globalX, globalY) : '';
  }

  openReaderSourceAction(marker: string): void {
    const now = Date.now();
    if (now - this.readerSourceActionOpenedAt < 500) return;
    const action: ReaderActionData | null = ReaderActionMarker.parse(marker);
    const source = this.currentReaderSource();
    if (action && source) {
      action.url = ReaderInteractionProviderRegistry.expandAction(source, action.url);
    }
    if (action && source && NativeSourceService.isReaderAction(action.url)) {
      // 原生书源正文里的请求按钮：发出书源声明的请求，把结果提示出来。
      this.readerSourceActionOpenedAt = now;
      NativeSourceService.runReaderAction(source, new HttpClient(10000), action.url).then((message: string): void => {
        HdsFeedback.showToast(message);
      }).catch((error: Error): void => {
        HdsFeedback.showToast(`操作失败：${error.message || '未知错误'}`);
      });
      return;
    }
    if (action && source && ReaderActionMarker.sourceScript(action.url)) {
      this.openReaderSourceScriptAction(source, action, marker);
      return;
    }
    if (!action || !/^https?:\/\//i.test(action.url)) {
      HdsFeedback.showToast('书源操作地址无效');
      return;
    }
    this.readerSourceActionOpenedAt = now;
    const title = action.title || action.label || '网页内容';
    const commentMode = this.isReaderCommentAction(action);
    if (commentMode) {
      if (source) {
        VerificationSupport.requestVerification(action.url, title, source);
      }
      this.openReaderCommentPanel(action.url, title, marker);
      return;
    }
    if (source) {
      VerificationSupport.requestVerification(action.url, title, source);
    }
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: action.url,
        title: title,
        requireLoginCookie: 'false',
        readerCommentMode: 'false'
      }
    }).catch((error: Error) => {
      this.readerSourceActionOpenedAt = 0;
      console.error('打开网页失败:', error);
      HdsFeedback.showToast(`打开失败：${error.message || '路由跳转异常'}`);
    });
  }

  readerParagraphCommentSettingState(): number {
    const source = this.currentReaderSource();
    if (!source) return 0;
    return BookSourceRuntimeSnapshotStore.get(source).settingState([
      '段评开关', 'fqpara', 'yunpara', 'paras', '评论开关', '章评开关'
    ]);
  }

  readerParagraphCommentsEnabledForPagination(): boolean {
    // An absent setting means the source has no user-facing switch (or uses comments by default), so retain
    // markers. Only an explicit disabled value is allowed to remove source content.
    return this.readerParagraphCommentSettingState() >= 0;
  }

  readerParagraphCommentPaginationIdentity(): string {
    const state = this.readerParagraphCommentSettingState();
    return state > 0 ? 'comment_on' : (state < 0 ? 'comment_off' : 'comment_auto');
  }

  isReaderParagraphCommentAction(data: ReaderActionData): boolean {
    const identity = `${data.label || ''}\n${data.title || ''}\n${data.url || ''}`;
    return /段评|章评|本章说|评论|comment|review|para_idea|idea_comment|legado-provider-action/i.test(identity);
  }

  stripReaderParagraphCommentActions(value: string): string {
    const source = value || '';
    if (!ReaderActionMarker.has(source)) return source;
    let cursor = 0;
    let result = '';
    while (cursor < source.length) {
      let markerStart = -1;
      for (const prefix of [ReaderActionMarker.PREFIX, ReaderActionMarker.LEGACY_PREFIX,
        ReaderActionMarker.ORIGINAL_PREFIX]) {
        const index = source.indexOf(prefix, cursor);
        if (index >= 0 && (markerStart < 0 || index < markerStart)) markerStart = index;
      }
      if (markerStart < 0) break;
      const suffixStart = source.indexOf(ReaderActionMarker.SUFFIX, markerStart);
      if (suffixStart < 0) break;
      const markerEnd = suffixStart + ReaderActionMarker.SUFFIX.length;
      const marker = source.substring(markerStart, markerEnd);
      const action = ReaderActionMarker.parse(marker);
      result += source.substring(cursor, markerStart);
      if (!action || !this.isReaderParagraphCommentAction(action)) result += marker;
      cursor = markerEnd;
    }
    return cursor > 0 ? `${result}${source.substring(cursor)}` : source;
  }

  async openReaderSourceScriptAction(source: BookSource, action: ReaderActionData, marker: string): Promise<void> {
    const code = ReaderActionMarker.sourceScript(action.url);
    if (!code || !this.book) {
      HdsFeedback.showToast('书源操作无效');
      return;
    }
    const runtime = BookSourceStageWebRuntime.get();
    if (!await runtime.waitUntilAvailable(8000)) {
      HdsFeedback.showToast('书源脚本运行环境未就绪');
      return;
    }
    const request = new StageWebRuntimeRequest();
    // Reader action scripts communicate through side effects (java.showBrowser setting the
    // requestedUrl) and legitimately return nothing. The CONTENT stage treats an empty script
    // result as a failed content extraction and throws, so run actions in their own stage that
    // keeps the same request budget without that rule.
    request.applyStageBudget(SourceRuntimeStage.READER_ACTION);
    request.source = source;
    request.book = this.book;
    request.chapter = this.chapters.length > 0 ? this.chapters[this.clampChapterIndex(this.currentChapterIndex)] : null;
    request.baseUrl = request.chapter?.url || this.book.bookUrl || source.bookSourceUrl;
    request.code = code;
    request.readerActionMode = true;
    request.maxRequestCount = 3;
    request.maxResponseBytes = 2 * 1024 * 1024;
    request.maxTotalResponseBytes = 3 * 1024 * 1024;
    this.readerSourceActionOpenedAt = Date.now();
    try {
      const result = await runtime.execute(request);
      const target = (result.requestedUrl || '').trim();
      if (!/^https?:\/\//i.test(target)) {
        HdsFeedback.showToast('书源操作未返回有效地址');
        this.readerSourceActionOpenedAt = 0;
        return;
      }
      VerificationSupport.requestVerification(target, action.title || action.label || '段评', source);
      this.openReaderCommentPanel(target, action.title || action.label || '段评', marker,
        result.requestedHtml || '');
    } catch (error) {
      this.readerSourceActionOpenedAt = 0;
      const message = error instanceof Error ? error.message : String(error || '');
      // Content cached by an older app version can carry markers whose embedded script was
      // truncated by the old extraction regex. The runtime then fails at parse time; point the
      // reader at the chapter refresh instead of a bare script error.
      const staleScript = /SyntaxError|Unexpected|invalid|未终止|脚本执行失败/i.test(message);
      HdsFeedback.showToast(`评论加载失败${message ? `：${message}` : ''}` + (staleScript ? '\n本章正文可能是旧版缓存，请在目录中刷新本章后重试' : ''));
    }
  }

  isReaderCommentAction(action: ReaderActionData): boolean {
    const metadata = `${action.label || ''}\n${action.title || ''}`;
    if (/段评|章评|神评论|评论|本章说/.test(metadata)) return true;
    return /\/(?:get_review|get_para_review|para_idea)(?:[/?#]|$)|[?&](?:review|comment)=/i.test(action.url || '');
  }

  openReaderCommentPanel(url: string, title: string, marker: string, sourceHtml: string = ''): void {
    const normalizedUrl = (url || '').trim();
    if (!/^https?:\/\//i.test(normalizedUrl)) {
      HdsFeedback.showToast('评论地址无效');
      return;
    }
    this.readerSourceActionOpenedAt = Date.now();
    this.readerCommentPanelLoadSerial++;
    if (this.readerCommentPanelReadyTimerId >= 0) {
      clearTimeout(this.readerCommentPanelReadyTimerId);
      this.readerCommentPanelReadyTimerId = -1;
    }
    this.readerCommentPanelTitle = title || '段评';
    const providerPanel = ReaderInteractionProviderRegistry.buildPanel(normalizedUrl);
    if (sourceHtml) {
      this.readerCommentPanelHtmlLoaded = false;
      this.readerCommentPanelHtml = sourceHtml;
      this.readerCommentPanelBaseUrl = normalizedUrl;
      this.readerCommentPanelUrl = 'about:blank';
    } else if (providerPanel) {
      this.readerCommentPanelHtmlLoaded = false;
      this.readerCommentPanelHtml = providerPanel.html;
      this.readerCommentPanelBaseUrl = providerPanel.baseUrl;
      this.readerCommentPanelUrl = 'about:blank';
    } else {
      this.readerCommentPanelHtml = '';
      this.readerCommentPanelBaseUrl = '';
      this.readerCommentPanelUrl = normalizedUrl;
    }
    this.readerCommentPanelMarker = marker;
    this.readerCommentPanelProgress = 0;
    this.readerCommentPanelLoading = true;
    this.readerCommentPanelError = false;
    this.readerCommentPanelHeight = 0;
    const markerBottom = this.getReaderSourceActionAnchorBottom(marker);
    this.readerCommentPanelAnchorBottom = markerBottom > 0 ? markerBottom :
      (this.readerCommentPageAreaTop >= 0 ? (this.readerCommentPageAreaTop + this.readerCommentPageAreaHeight) : -1);
    this.showReaderCommentPanel = true;
  }

  loadReaderCommentPanelHtmlIfNeeded(): boolean {
    if (!this.showReaderCommentPanel || !this.readerCommentPanelHtml || this.readerCommentPanelHtmlLoaded) {
      return false;
    }
    this.readerCommentPanelHtmlLoaded = true;
    try {
      const baseUrl = this.readerCommentPanelBaseUrl || 'about:blank';
      const html = ReaderCommentWebTheme.prepareHtml(this.readerCommentPanelHtml, this.appDarkMode);
      this.readerCommentPanelController.loadData(html, 'text/html', 'UTF-8', baseUrl, baseUrl);
      // Some ArkWeb versions do not emit a second onPageEnd for loadData. The embedded page owns its
      // network loading state. Poll the actual document/theme readiness rather than revealing a blank document.
      this.scheduleReaderCommentPanelHostReady(180);
      return true;
    } catch (error) {
      this.readerCommentPanelHtmlLoaded = false;
      console.warn('加载原生评论面板失败:', error);
      this.failReaderCommentPanelLoad();
      return false;
    }
  }

  scheduleReaderCommentPanelHostReady(delayMs: number, attempt: number = 0): void {
    if (this.readerCommentPanelReadyTimerId >= 0) clearTimeout(this.readerCommentPanelReadyTimerId);
    const serial = this.readerCommentPanelLoadSerial;
    this.readerCommentPanelReadyTimerId = setTimeout(() => {
      this.readerCommentPanelReadyTimerId = -1;
      if (!this.showReaderCommentPanel || serial !== this.readerCommentPanelLoadSerial) return;
      this.syncReaderCommentPanelWebTheme().then((ready: boolean): void => {
        if (!this.showReaderCommentPanel || serial !== this.readerCommentPanelLoadSerial) return;
        if (ready) {
          this.readerCommentPanelError = false;
          this.readerCommentPanelLoading = false;
        } else if (attempt < 60) {
          this.scheduleReaderCommentPanelHostReady(100, attempt + 1);
        } else {
          this.failReaderCommentPanelLoad();
        }
      });
    }, Math.max(0, delayMs));
  }

  failReaderCommentPanelLoad(): void {
    if (!this.showReaderCommentPanel) return;
    this.readerCommentPanelLoadSerial++;
    if (this.readerCommentPanelReadyTimerId >= 0) clearTimeout(this.readerCommentPanelReadyTimerId);
    this.readerCommentPanelReadyTimerId = -1;
    this.readerCommentPanelLoading = true;
    this.readerCommentPanelError = true;
  }

  retryReaderCommentPanelLoad(): void {
    this.readerCommentPanelLoading = true;
    this.readerCommentPanelError = false;
    if (this.readerCommentPanelHtml) {
      this.readerCommentPanelHtmlLoaded = false;
      this.loadReaderCommentPanelHtmlIfNeeded();
    } else {
      try {
        this.readerCommentPanelController.refresh();
      } catch (error) {
        this.failReaderCommentPanelLoad();
      }
    }
  }

  backReaderCommentPanel(): void {
    if (!this.showReaderCommentPanel) return;
    try {
      const history = this.readerCommentPanelController.getBackForwardEntries();
      if (history.currentIndex > 0) {
        const previousUrl = history.getItemAtIndex(history.currentIndex - 1).historyUrl;
        // loadData 前的启动空白页不是用户可返回的评论页面。
        if (previousUrl && previousUrl !== 'about:blank') {
          this.readerCommentPanelController.backward();
          return;
        }
      }
    } catch (_) {
      // 控制器尚未就绪也应允许用户退出面板。
    }
    this.closeReaderCommentPanel();
  }

  closeReaderCommentPanel(): void {
    this.readerCommentPanelLoadSerial++;
    if (this.readerCommentPanelReadyTimerId >= 0) {
      clearTimeout(this.readerCommentPanelReadyTimerId);
      this.readerCommentPanelReadyTimerId = -1;
    }
    // 弹层收起动画期间网页仍挂着，等 onDisappear 再清地址和换控制器，避免收起时闪白。
    this.showReaderCommentPanel = false;
  }

  resetReaderCommentPanelState(): void {
    this.readerCommentPanelLoadSerial++;
    if (this.readerCommentPanelReadyTimerId >= 0) {
      clearTimeout(this.readerCommentPanelReadyTimerId);
      this.readerCommentPanelReadyTimerId = -1;
    }
    this.readerCommentPanelUrl = '';
    this.readerCommentPanelMarker = '';
    this.readerCommentPanelAnchorBottom = -1;
    this.readerCommentPanelProgress = 0;
    this.readerCommentPanelLoading = false;
    this.readerCommentPanelError = false;
    this.readerCommentPanelHeight = 0;
    this.readerCommentPanelHtml = '';
    this.readerCommentPanelBaseUrl = '';
    this.readerCommentPanelHtmlLoaded = false;
    this.readerCommentPanelController = new webview.WebviewController();
    this.readerSourceActionOpenedAt = 0;
  }

  async syncReaderCommentPanelWebTheme(): Promise<boolean> {
    if (!this.showReaderCommentPanel || !this.readerCommentPanelUrl) return false;
    try {
      const result = await this.readerCommentPanelController.runJavaScript(
        ReaderCommentWebTheme.apply(this.appDarkMode, !!this.readerCommentPanelHtml));
      return Number(result) === 1;
    } catch (error) {
      console.warn('同步评论面板深浅色模式失败:', error);
      return false;
    }
  }

  getReaderSourceActionAnchorBottom(marker: string): number {
    const bounds = this.readerSourceActionAreas.get(marker) || [];
    if (bounds.length < 4) return -1;
    const offsets = this.readerSourceActionScrollOffsets.get(marker) || [];
    const registeredOffset = offsets.length > 0 ? offsets[offsets.length - 1] : 0;
    return bounds[bounds.length - 1] - (this.currentContinuousReaderScrollOffset() - registeredOffset);
  }

  getReaderEpubImageUri(marker: string): string {
    return this.readerImageUriForSource(LocalBookService.epubImagePathFromMarker(marker));
  }

  readerImageUriForSource(path: string): string {
    // 获取正文时就失败的图片（ReaderImageMarker.FAILURE_SCHEME）没有可加载的地址。
    if (!path || path.startsWith('legado-image-error:')) return '';
    if (/^(?:https?:|data:|file:)/i.test(path)) return path;
    try {
      return fileUri.getUriFromPath(path);
    } catch (_) {
      return path;
    }
  }

  readerSelectableTextController(key: string): TextController {
    let controller = this.readerSelectableTextControllers.get(key);
    if (!controller) {
      controller = new TextController();
      this.readerSelectableTextControllers.set(key, controller);
      // A continuous chapter may mount several rich Text nodes while the two retained paged
      // surfaces still own native selection controllers. Evicting at the old 160-entry limit
      // could drop a controller that was still attached to a visible Text. Looking it up again
      // then created a detached controller whose LayoutManager was undefined, so long-press
      // selection silently failed. Chapter/layout lifecycles clear these maps; keep enough live
      // controllers for the mounted window and prune them together with their measured areas.
      while (this.readerSelectableTextControllers.size > 1024) {
        const oldest = this.readerSelectableTextControllers.keys().next().value as string | undefined;
        if (!oldest) break;
        this.readerSelectableTextControllers.delete(oldest);
      }
    }
    return controller;
  }

  selectReaderTextAtGlobalPoint(event: GestureEvent): void {
    const point = this.readerContinuousGesturePoint(event);
    if (point.length < 2) return;
    this.selectReaderTextAtPoint(point[0], point[1]);
  }

  selectReaderTextAtPoint(globalX: number, globalY: number): void {
    // A recognised long press must never fall through to a tap-zone page turn, even if the
    // system selection menu needs a later layout retry.
    this.readerTextSelectionUntil = Date.now() + 900;
    this.suppressReaderTapClick = true;
    this.readerTouchActive = false;
    this.readerPanActive = false;
    this.setReaderTextSelectionActive(this.isReaderNovelContinuousScrollModeActive());
    const serial = ++this.readerTextSelectionSerial;
    if (!this.isReaderNovelContinuousScrollModeActive() && this.shouldUseReaderLayoutV2(this.pagedContentText)) {
      this.selectReaderV2TextAtGlobalPoint(globalX, globalY, serial, 0);
      return;
    }
    if (this.usesReaderContinuousV2()) {
      this.selectReaderContinuousV2TextAtPoint(globalX, globalY, serial, 0);
      return;
    }
    // Comics have no selectable text.
    this.setReaderTextSelectionActive(false);
  }

  retryReaderTextSelection(serial: number, attempt: number, action: (attempt: number) => void): void {
    if (attempt >= 3) {
      this.setReaderTextSelectionActive(false);
      return;
    }
    const delayMs = attempt === 0 ? 16 : 40;
    setTimeout(() => {
      if (serial !== this.readerTextSelectionSerial || !this.readerPageVisible) return;
      action(attempt + 1);
    }, delayMs);
  }

  continuousSelectionPageIndexForKey(key: string): number {
    const nativePrefix = `reader_continuous_native_${this.currentChapterIndex}_`;
    if (key.startsWith(nativePrefix)) {
      const suffix = key.substring(nativePrefix.length);
      const separator = suffix.indexOf('_');
      const value = Number(separator >= 0 ? suffix.substring(0, separator) : suffix);
      return Number.isFinite(value) ? Math.round(value) : -1;
    }
    const legacyPrefix = `reader_vertical_scroll_${this.currentChapterIndex}_`;
    const start = key.indexOf(legacyPrefix);
    if (start < 0) return -1;
    const suffix = key.substring(start + legacyPrefix.length);
    const match = suffix.match(/^\d+/);
    return match ? Number(match[0]) : -1;
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

  /** The theme's emphasis bubble, always in bubble form even when the theme emphasises dialogue another way. */
  readerCommentBubbleTheme(): ReaderResolvedRegexEmphasis {
    const context = this.readerRegexEmphasisContext();
    context.inheritedMode = ThemeRegexEmphasisModes.BUBBLE;
    return ReaderRegexBubbleStyleResolver.resolve(null, context);
  }

  /**
   * Comment / 本章说 bubbles take their shape, colours and ornament from the theme's emphasis-bubble style. Colours
   * and the corner style a source sets explicitly still win.
   */
  readerCommentBubbleStyle(): ReaderCommentBubbleStyle {
    const style = ReaderCommentBubbleStyles.resolve(this.readerCommentBubbleTheme().bubbleStyleId,
      this.isReaderThemeDark());
    const sourceTextColor = this.readerSourceColorSetting('段评字体颜色', '');
    const sourceFillColor = this.readerSourceColorSetting('段评填充颜色', '');
    if (sourceTextColor) style.text = ReaderV2Color.parse(sourceTextColor, style.text);
    if (sourceFillColor) {
      style.fill = ReaderV2Color.parse(sourceFillColor, style.fill);
      style.stroke = 0;
    }
    if (this.readerSourceSettingValue('段评样式')) style.radiusPx = this.toMeasurePx(this.readerV2CommentRadius());
    return style;
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
        .height(this.readerSettingsPanelHeight())
    }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
  }

  hideReaderPanels() {
    this.flushPendingReaderLayoutChange(true);
    this.menuChapterPreviewIndex = this.currentChapterIndex;
    this.menuChapterSliderActive = false;
    this.menuChapterTooltipVisible = false;
    this.showReaderActionMenu = false;
    this.showReaderCacheDialog = false;
    this.showReaderChapterCacheDialog = false;
    this.showLayoutElementSettings = false;
    if (!this.txtCharsetApplying) this.showTxtCharsetDialog = false;
    this.showMenu = false;
    this.showTtsVoiceDropdown = false;
    this.showSettings = false;
    if (this.showReaderCommentPanel) {
      this.closeReaderCommentPanel();
    }
  }

  // Every paged chapter is laid out by V2, with or without images. Comics and continuous scrolling keep
  // their own list surface.
  shouldUseReaderLayoutV2(source: string = this.pagedContentText || this.content): boolean {
    return !!source && !this.isReaderContinuousScrollSurfaceActive() && !this.isReaderComicModeActive();
  }

  // In-chapter headings recorded when the EPUB was imported, plus the volume heading that buildPagedSourceText
  // puts before a volume's first chapter. V2 styles the matching paragraphs as headings.
  readerV2HeadingHints(chapterIndex: number): ReaderV2HeadingHint[] {
    if (!this.book || chapterIndex < 0 || chapterIndex >= this.chapters.length) {
      return [];
    }
    const volumeTitle = this.readerVolumeTitle(chapterIndex);
    const volumeHints = volumeTitle ? [new ReaderV2HeadingHint(1, volumeTitle)] : [];
    if (this.book.origin !== LocalBookService.ORIGIN || this.book.type !== LocalBookService.TYPE_EPUB) {
      return volumeHints;
    }
    return volumeHints.concat(EpubChapterPlanner.decodeHeadings(this.chapters[chapterIndex].variable)
      .map((heading: EpubHeading): ReaderV2HeadingHint => new ReaderV2HeadingHint(heading.level, heading.text)));
  }

  /** 该章是某一卷第一章时的卷名（与章节名相同时不重复显示）。 */
  readerVolumeTitle(chapterIndex: number): string {
    if (chapterIndex < 0 || chapterIndex >= this.chapters.length) return '';
    const volumeTitle = BookChapter.volumeTitleOf(this.chapters[chapterIndex]);
    return volumeTitle && !ReaderTextNormalizer.sameTitle(volumeTitle, this.getChapterTitle(chapterIndex)) ?
      volumeTitle : '';
  }

  // continuous: one unbounded column for scrolling. The list supplies the vertical margins as padding, and
  // no footer guard applies, so the column starts at y=0.
  buildReaderV2Snapshot(continuous: boolean = false): ReaderV2LayoutSnapshot {
    const input = new ReaderV2LayoutInput();
    input.viewportWidthPx = this.toMeasurePx(this.getReaderPageColumnWidth());
    input.viewportHeightPx = this.toMeasurePx(this.getReaderPaginationViewportHeight());
    // The measured reader viewport already begins below the status bar in normal mode. Immersive mode begins at
    // screen y=0. Therefore both modes use local y=0 and must not subtract the status inset a second time.
    input.safeTopPx = 0;
    input.safeBottomPx = 0;
    input.extendToStatusBar = this.readerExtendToStatusBar;
    input.marginLeftPx = this.toMeasurePx(this.getEffectiveReaderMarginLeft());
    input.marginRightPx = this.toMeasurePx(this.getEffectiveReaderMarginRight());
    input.marginTopPx = continuous ? 0 : this.toMeasurePx(this.getEffectiveReaderMarginTop());
    input.marginBottomPx = continuous ? 0 : this.toMeasurePx(this.getEffectiveReaderMarginBottom());
    // Footer metadata is an overlay, but it is lifted above the gesture indicator. Reserve the same deterministic
    // footprint in native Paragraph pagination so the final正文 line stays clear of the raised footer.
    input.bottomGuardPx = continuous ? 0 : this.toMeasurePx(this.getReaderV2BottomGuard());
    input.columnCount = 1;
    input.columnGapPx = 0;
    input.fontSizePx = this.toMeasureFontPx(this.readerFontSize);
    input.fontWeight = this.readerFontWeight;
    input.titleFontSizePx = this.toMeasureFontPx(this.readerTitleFontSize);
    input.lineSpacingPx = this.toMeasureNonNegativePx(this.readerLineHeight);
    input.paragraphSpacingPx = this.toMeasureNonNegativePx(this.readerParagraphSpacing);
    input.letterSpacingPx = this.toMeasureFontOffsetPx(this.getReaderAdaptiveLetterSpacing());
    input.textAlign = this.readerTextAlign;
    input.bodyFontFamily = this.getBodyReaderFontFamily();
    input.titleFontFamily = this.getTitleReaderFontFamily();
    input.textColor = ReaderV2Color.parse(this.getTextColor(), 0xFF202124);
    input.commentBubble = this.readerCommentBubbleStyle();
    input.commentBubbleSize = this.readerCommentBubbleSize;
    const commentLarge = this.readerSourceSettingEnabled('气泡增大');
    input.commentFontSizePx = this.toMeasureFontPx(commentLarge ?
      Math.max(12, this.readerFontSize - 2) : Math.max(10, this.readerFontSize - 5));
    input.commentHitSlopXPx = this.toMeasurePx(this.readerSourceActionHitSlopX);
    input.commentHitSlopYPx = this.toMeasurePx(this.readerSourceActionHitSlopY);
    input.commentsEnabled = true;
    input.regexEnabled = this.readerRegexFontEnabled;
    input.imagePxPerVp = this.toMeasurePx(1);
    input.imageMinHeightPx = this.getReaderMixedImageMinHeightPx();
    input.styleIdentity = `${this.readerTypographyCacheIdentity()}_${this.readerParagraphCommentPaginationIdentity()}_` +
      `${this.getBackgroundColor()}_${this.getTextColor()}${continuous ? '_continuous' : ''}`;
    return ReaderV2LayoutSnapshot.create(input);
  }

  readerV2CommentRadius(): number {
    const style = this.readerSourceSettingValue('段评样式') || '0';
    if (style === '3' || style === '4') return 3;
    if (style === '0' || style === '2') return 6;
    return 9;
  }

  buildReaderV2RegexStyles(document: ReaderV2Document): ReaderV2SpanStyleRange[] {
    if (!this.readerRegexFontEnabled || !document.displayText) return [];
    const startedAt = Date.now();
    const slices = this.getRegexTextSlices(document.displayText);
    const result: ReaderV2SpanStyleRange[] = [];
    // Every hit of one rule shares the same resolved style. Resolving the theme emphasis per hit cost
    // about 1 ms each on the UI thread (300 ms for a dialogue-heavy chapter), so it is done once per rule.
    const templates: Map<number, ReaderV2SpanStyleRange> = new Map<number, ReaderV2SpanStyleRange>();
    for (const slice of slices) {
      if (!slice.highlighted || slice.end <= slice.start) continue;
      let template = templates.get(slice.ruleIndex);
      if (!template) {
        template = this.buildReaderV2RegexStyleTemplate(slice);
        templates.set(slice.ruleIndex, template);
      }
      const style = new ReaderV2SpanStyleRange(slice.start, slice.end);
      style.fontSizePx = template.fontSizePx;
      style.fontFamily = template.fontFamily;
      style.color = template.color;
      style.backgroundEnabled = template.backgroundEnabled;
      style.backgroundColor = template.backgroundColor;
      style.radiusTopLeftPx = template.radiusTopLeftPx;
      style.radiusTopRightPx = template.radiusTopRightPx;
      style.radiusBottomRightPx = template.radiusBottomRightPx;
      style.radiusBottomLeftPx = template.radiusBottomLeftPx;
      style.shadowEnabled = template.shadowEnabled;
      style.shadowColor = template.shadowColor;
      style.shadowRadiusPx = template.shadowRadiusPx;
      style.shadowOffsetXPx = template.shadowOffsetXPx;
      style.shadowOffsetYPx = template.shadowOffsetYPx;
      style.decorationEnabled = template.decorationEnabled;
      style.decorationStyleId = template.decorationStyleId;
      style.decorationSizePx = template.decorationSizePx;
      result.push(style);
    }
    CooperativeScheduler.reportSynchronousOperation('reader/v2-regex-styles', Date.now() - startedAt,
      `chapter=${document.chapterIndex},chars=${document.displayText.length},hits=${result.length}`);
    return result;
  }

  // The style shared by every hit of the rule that produced `slice`; its range is left empty.
  buildReaderV2RegexStyleTemplate(slice: ReadTextSlice): ReaderV2SpanStyleRange {
    const resolved = this.resolvedRegexEmphasis(this.getRegexRuleBySlice(slice));
    const style = new ReaderV2SpanStyleRange();
    style.fontSizePx = this.toMeasureFontPx(this.getRegexSliceFontSize(slice));
    style.fontFamily = this.getRegexSliceFontFamily(slice);
    style.color = ReaderV2Color.parse(this.getStyledSliceFontColor(slice),
      ReaderV2Color.parse(this.getTextColor(), 0xFF202124));
    style.backgroundEnabled = resolved.backgroundEnabled;
    style.backgroundColor = ReaderV2Color.parse(resolved.backgroundColor, 0x00000000);
    style.radiusTopLeftPx = this.toMeasurePx(resolved.radiusTopLeft);
    style.radiusTopRightPx = this.toMeasurePx(resolved.radiusTopRight);
    style.radiusBottomRightPx = this.toMeasurePx(resolved.radiusBottomRight);
    style.radiusBottomLeftPx = this.toMeasurePx(resolved.radiusBottomLeft);
    style.shadowEnabled = resolved.textShadowRadius > 0;
    style.shadowColor = ReaderV2Color.parse(resolved.textShadowColor, 0x00000000);
    style.shadowRadiusPx = this.toMeasurePx(Math.max(0, resolved.textShadowRadius));
    style.shadowOffsetXPx = this.toMeasurePx(Math.max(0, resolved.textShadowOffsetX));
    style.shadowOffsetYPx = this.toMeasurePx(Math.max(0, resolved.textShadowOffsetY));
    style.decorationEnabled = resolved.bubbleDecorationEnabled &&
      ThemeAssetRegistry.hasRegexBubbleCap(resolved.bubbleStyleId);
    style.decorationStyleId = style.decorationEnabled ? resolved.bubbleStyleId : '';
    style.decorationSizePx = style.decorationEnabled ?
      this.toMeasurePx(Math.max(15, Math.min(22, this.getRegexSliceFontSize(slice) * 0.72))) : 0;
    return style;
  }

  createIncrementalReaderV2Pagination(source: string, chapterIndex: number,
    initialPageCount: number): ReaderPaginationResult {
    const snapshot = this.buildReaderV2Snapshot();
    const document = ReaderV2DocumentParser.parse(source, chapterIndex, this.getChapterTitle(chapterIndex),
      this.readerV2HeadingHints(chapterIndex));
    const session = ReaderV2Paginator.start(document, snapshot, this.buildReaderV2RegexStyles(document));
    const result: ReaderPaginationResult = {
      source: source,
      pages: [],
      starts: [],
      ends: [],
      cursor: 0,
      complete: session.pageSet.complete,
      v2Session: session
    };
    this.registerReaderV2PaginationSession(source, chapterIndex, session);
    const visibleSpreadSize = this.isLandscapeDoublePageActive() ? 2 : 1;
    // Never rebuild synchronously from the chapter start to a deep saved position. A single V2 page can include
    // native paragraph measurement, so restoring hundreds of pages in this lifecycle call can trip the UI watchdog.
    // Publish only the first visible spread here; the retained session restores the saved position cooperatively.
    const requestedPageCount = Math.min(Math.max(1, initialPageCount), visibleSpreadSize);
    const rawTargetOffset = chapterIndex === this.currentChapterIndex ? this.readerTypographyRestoreOffset : -1;
    const targetOffset = rawTargetOffset < 0 ? -1 : Math.min(source.length, Math.max(0, rawTargetOffset));
    if (chapterIndex === this.currentChapterIndex && rawTargetOffset >= 0) {
      this.readerTypographyRestoreOffset = targetOffset;
    }
    while (!result.complete && result.pages.length < requestedPageCount) {
      const previousPageCount = result.pages.length;
      this.appendReaderV2PaginationBatch(result, chapterIndex, 1);
      if (result.pages.length <= previousPageCount) break;
    }
    ReaderOpenTrace.mark(this.bookUrl, 'v2-initial-window-ready',
      `pages=${result.pages.length} complete=${result.complete} offset=${targetOffset}`);
    return result;
  }

  registerReaderV2PaginationSession(source: string, chapterIndex: number,
    session: ReaderV2PaginationSession): void {
    const key = this.buildReaderPaginationCacheKey(chapterIndex, source);
    this.readerV2PageSetCache.set(key, session.pageSet);
    this.readerV2DocumentCache.set(key, session.document);
    while (this.readerV2PageSetCache.size > 3) {
      const oldest = this.readerV2PageSetCache.keys().next().value as string | undefined;
      if (!oldest) break;
      this.readerV2PageSetCache.delete(oldest);
      this.readerV2DocumentCache.delete(oldest);
    }
    if (chapterIndex === this.currentChapterIndex) {
      this.readerV2ActiveDocument = session.document;
      this.readerV2ActiveSnapshot = session.snapshot;
    }
  }

  appendReaderV2PaginationBatch(result: ReaderPaginationResult, chapterIndex: number, maxPages: number): void {
    const session = result.v2Session;
    if (!session || result.complete || maxPages <= 0) return;
    const startedAt = Date.now();
    const appended = ReaderV2Paginator.appendPages(session, maxPages);
    this.syncReaderV2PaginationResult(result);
    CooperativeScheduler.reportSynchronousOperation('reader/v2-pagination-batch', Date.now() - startedAt,
      `chapter=${chapterIndex},pages=${appended},total=${result.pages.length}`);
  }

  syncReaderV2PaginationResult(result: ReaderPaginationResult): void {
    const session = result.v2Session;
    if (!session) return;
    const pageSet = session.pageSet;
    const pages: string[] = [];
    const starts: number[] = [];
    const ends: number[] = [];
    for (let index = 0; index < pageSet.pages.length; index++) {
      const page = pageSet.pages[index];
      const start = index === 0 ? 0 : Math.max(starts[index - 1], page.sourceStart);
      const nextStart = index + 1 < pageSet.pages.length ? pageSet.pages[index + 1].sourceStart :
        (pageSet.complete ? result.source.length : page.sourceEnd);
      const end = Math.max(start, Math.min(result.source.length, nextStart > start ? nextStart : page.sourceEnd));
      page.sourceStart = start;
      page.sourceEnd = end;
      starts.push(start);
      ends.push(end);
      pages.push(result.source.substring(start, end));
    }
    if (pages.length === 0 && result.source && pageSet.complete) {
      pages.push(result.source);
      starts.push(0);
      ends.push(result.source.length);
    }
    result.pages = pages;
    result.starts = starts;
    result.ends = ends;
    result.cursor = ends.length > 0 ? ends[ends.length - 1] : 0;
    result.complete = pageSet.complete;
  }

  readerV2PageSet(chapterIndex: number, source: string): ReaderV2PageSet | null {
    if (!source) return null;
    const key = this.buildReaderPaginationCacheKey(chapterIndex, source);
    const cached = this.readerV2PageSetCache.get(key);
    if (cached) return cached;
    // The pagination result owns the retained native session. Its small lookup cache can be evicted independently
    // while adjacent chapters are prepared; falling back to the owning session prevents a valid page boundary
    // from being rendered as a blank NodeContainer until the reader is reopened.
    const result = this.readerPaginationCache.get(key);
    return result?.v2Session?.pageSet || null;
  }

  readerV2Document(chapterIndex: number, source: string): ReaderV2Document | null {
    if (!source) return null;
    const key = this.buildReaderPaginationCacheKey(chapterIndex, source);
    const cached = this.readerV2DocumentCache.get(key);
    if (cached) return cached;
    return this.readerPaginationCache.get(key)?.v2Session?.document || null;
  }

  readerV2Page(chapterIndex: number, pageIndex: number, source: string): ReaderV2PageLayout | null {
    const pageSet = this.readerV2PageSet(chapterIndex, source);
    if (!pageSet || pageIndex < 0 || pageIndex >= pageSet.pages.length) return null;
    return pageSet.pages[pageIndex];
  }

  readerV2Controller(role: string, chapterIndex: number, pageIndex: number,
    source: string): ReaderV2PageNodeController {
    let controller = this.readerV2Controllers.get(role);
    if (!controller) {
      controller = new ReaderV2PageNodeController();
      this.readerV2Controllers.set(role, controller);
    }
    const page = this.readerV2Page(chapterIndex, pageIndex, source);
    controller.updatePage(page);
    // TTS focus is a declarative overlay below. Keeping it outside the retained FrameNode avoids
    // HarmonyOS builds that defer RenderNode.invalidate() until the next page transition.
    controller.updateHighlight(-1, -1);
    return controller;
  }

  readerTextEditMenuOptions(textProvider: () => string): EditMenuOptions {
    return {
      onCreateMenu: (items: TextMenuItem[]): TextMenuItem[] => {
        const replaceItem: TextMenuItem = {
          id: TextMenuItemId.of(READER_REPLACE_MENU_ITEM_ID),
          content: '替换'
        };
        const copyIndex = items.findIndex((menuItem: TextMenuItem) =>
          menuItem.id.equals(TextMenuItemId.COPY));
        if (copyIndex >= 0) {
          items.splice(copyIndex, 0, replaceItem);
        } else {
          items.unshift(replaceItem);
        }
        return items;
      },
      onMenuItemClick: (item: TextMenuItem, range: TextRange): boolean => {
        if (item.id.equals(TextMenuItemId.of(READER_REPLACE_MENU_ITEM_ID))) {
          // range 是选区在当前 Text 节点全文中的下标，textProvider 与各节点登记可选文本时用的是同一份内容。
          const selectedText = textProvider().substring(range.start ?? 0, range.end ?? 0);
          this.scheduleReaderTextSelectionClear();
          this.openReaderReplaceRuleWithSelection(selectedText);
          return true;
        }
        // Let Harmony execute Copy/Translate/Share/Search first, then clear the native selection owned by Text.
        // Merely closing the menu leaves the highlight and handles alive until the page is destroyed.
        this.scheduleReaderTextSelectionClear();
        return false;
      }
    };
  }

  scheduleReaderTextSelectionClear(): void {
    if (this.readerTextSelectionClearPending) return;
    this.readerTextSelectionClearPending = true;
    const serial = ++this.readerTextSelectionSerial;
    setTimeout(() => {
      // The flag must be released even when a newer selection superseded this clear, otherwise the
      // early return above would wedge and no later dismissal could ever run.
      this.readerTextSelectionClearPending = false;
      if (serial !== this.readerTextSelectionSerial) return;
      const controllers: Set<TextController> = new Set<TextController>();
      for (const controller of this.readerSelectableTextControllers.values()) controllers.add(controller);
      for (const controller of this.readerInlineActionTextControllers.values()) controllers.add(controller);
      for (const controller of controllers) {
        try {
          controller.closeSelectionMenu();
          controller.setTextSelection(-1, -1, { menuPolicy: MenuPolicy.HIDE });
        } catch (_) {
        }
      }
      this.clearReaderV2SelectionOverlay();
      this.setReaderTextSelectionActive(false);
      this.readerTextSelectionUntil = 0;
      this.suppressReaderTapClick = false;
      this.readerSelectionDismissArmed = false;
    }, 80);
  }

  refreshCurrentReaderV2RetainedPages(forceRebuild: boolean = false): void {
    if (!this.shouldUseReaderLayoutV2(this.pagedContentText)) return;
    const primaryRole = this.currentReaderSurfaceIndex() === 0 ? 'current_primary' : 'current_alternate';
    const roles: string[] = this.isLandscapeDoublePageActive() ?
      [`${primaryRole}_left`, `${primaryRole}_right`] : [`${primaryRole}_single`];
    const pageIndexes: number[] = this.isLandscapeDoublePageActive() ?
      [this.currentPageIndex, this.currentPageIndex + 1] : [this.currentPageIndex];
    for (let index = 0; index < roles.length; index++) {
      const role = roles[index];
      const pageIndex = pageIndexes[index];
      const page = this.readerV2Page(this.currentChapterIndex, pageIndex, this.pagedContentText);
      const controller = this.readerV2Controllers.get(role);
      if (controller) controller.updatePage(page, forceRebuild);
    }
  }

  republishCurrentReaderPageAfterBackground(): void {
    if (this.contentPages.length === 0 || this.pendingRestorePageIndex >= 0 ||
      this.readerTypographyRestoreOffset >= 0) return;
    const pageText = this.getCurrentPageText();
    // Footer progress is declarative state, while V2正文 is retained by a native FrameNode. After a Home/resume
    // transition the controller can still point at the right page object even though RenderService retained the
    // last animation/capture submission. Re-publish both layers from the same authoritative page index and force
    // the lightweight native node to rebuild even when the page object identity has not changed.
    this.currentPageText = pageText;
    this.displayPageText = pageText;
    this.displayPageChapterIndex = this.currentChapterIndex;
    this.displayPageIndex = this.currentPageIndex;
    this.displayPageRenderKey++;
    this.forceCurrentReaderPageRender();
    this.refreshCurrentReaderV2RetainedPages(true);
  }

  readerV2TtsHighlightRects(chapterIndex: number, pageIndex: number, source: string,
    _paintVersion: number = this.readerV2TtsPaintVersion): ReaderV2HighlightRect[] {
    if (chapterIndex !== this.currentChapterIndex || this.readerV2TtsSourceStart < 0 ||
      this.readerV2TtsSourceEnd <= this.readerV2TtsSourceStart) return [];
    const page = this.readerV2Page(chapterIndex, pageIndex, source);
    const document = this.readerV2Document(chapterIndex, source);
    if (!page || !document) return [];
    const absoluteStart = document.displayOffsetForSource(this.readerV2TtsSourceStart);
    const absoluteEnd = document.displayOffsetForSource(this.readerV2TtsSourceEnd);
    return this.readerV2DisplayHighlightRects(page, absoluteStart, absoluteEnd, 'tts');
  }

  readerV2SelectionHighlightRects(chapterIndex: number, pageIndex: number, source: string,
    _paintVersion: number = this.readerV2SelectionPaintVersion): ReaderV2HighlightRect[] {
    if (chapterIndex !== this.readerV2SelectionChapterIndex || pageIndex !== this.readerV2SelectionPageIndex ||
      this.readerV2SelectionDisplayStart < 0 ||
      this.readerV2SelectionDisplayEnd <= this.readerV2SelectionDisplayStart) return [];
    const page = this.readerV2Page(chapterIndex, pageIndex, source);
    if (!page) return [];
    return this.readerV2DisplayHighlightRects(page, this.readerV2SelectionDisplayStart,
      this.readerV2SelectionDisplayEnd, 'selection');
  }

  readerV2DisplayHighlightRects(page: ReaderV2PageLayout, absoluteStart: number,
    absoluteEnd: number, keyPrefix: string): ReaderV2HighlightRect[] {
    if (absoluteEnd <= absoluteStart) return [];
    const result: ReaderV2HighlightRect[] = [];
    for (let fragmentIndex = 0; fragmentIndex < page.fragments.length; fragmentIndex++) {
      const fragment = page.fragments[fragmentIndex];
      if (!fragment.paragraph || absoluteEnd <= fragment.displayStart ||
        absoluteStart >= fragment.displayEnd) continue;
      const localStart = Math.max(0, absoluteStart - fragment.displayStart);
      const localEnd = Math.min(fragment.localEnd - fragment.localStart,
        absoluteEnd - fragment.displayStart);
      if (localEnd <= localStart) continue;
      const boxes = fragment.paragraph.getRectsForRange({ start: localStart, end: localEnd },
        graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
      for (let boxIndex = 0; boxIndex < boxes.length; boxIndex++) {
        const rect = boxes[boxIndex].rect;
        const left = Math.max(fragment.clipRect.left, fragment.paragraphX + rect.left);
        const right = Math.min(fragment.clipRect.right, fragment.paragraphX + rect.right);
        const glyphTop = fragment.paragraphY + rect.top;
        const glyphBottom = fragment.paragraphY + rect.bottom;
        // TIGHT Paragraph boxes follow the actual painted glyphs. Give selection a small symmetric inset around
        // those boxes; the system Text background uses its lower line box and makes the same glyph look too high.
        const verticalPadding = keyPrefix === 'selection' ?
          Math.max(1, Math.min(3, (glyphBottom - glyphTop) * 0.08)) : 0;
        const top = Math.max(fragment.clipRect.top, glyphTop - verticalPadding);
        const bottom = Math.min(fragment.clipRect.bottom, glyphBottom + verticalPadding);
        if (right <= left || bottom <= top) continue;
        result.push({
          leftPx: left,
          topPx: top,
          widthPx: right - left,
          heightPx: bottom - top,
          key: `${keyPrefix}_${page.identity}_${fragmentIndex}_${boxIndex}_${absoluteStart}_${absoluteEnd}`
        });
      }
    }
    return result;
  }

  @Builder
  readerV2TtsHighlightRect(rect: ReaderV2HighlightRect) {
    Row() {
    }
    .width(px2vp(rect.widthPx))
    .height(px2vp(rect.heightPx))
    .backgroundColor(0x55FFE58A)
    .position({ x: px2vp(rect.leftPx), y: px2vp(rect.topPx) })
    .zIndex(1)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerV2SelectionHighlightRect(rect: ReaderV2HighlightRect) {
    Row() {
    }
    .width(px2vp(rect.widthPx))
    .height(px2vp(rect.heightPx))
    .backgroundColor(0x663B82F6)
    .position({ x: px2vp(rect.leftPx), y: px2vp(rect.topPx) })
    .zIndex(2)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerV2PageSurface(role: string, chapterIndex: number, pageIndex: number, source: string,
    halfWidth: boolean = false) {
    Stack({ alignContent: Alignment.TopStart }) {
      // TTS paint versions intentionally do not flow into the retained正文 node. Re-publishing that
      // NodeContainer for every spoken chunk can trigger a fresh safe-area measurement after a page
      // animation, moving all glyphs upward. Only the lightweight rectangle overlay below depends on
      // readerV2TtsPaintVersion.
      NodeContainer(this.readerV2Controller(role, chapterIndex, pageIndex, source))
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      // Image blocks are laid out by the V2 paginator but painted by ArkUI Image, which owns decoding,
      // caching and downsampling. Their rects use the same page-local pixel coordinates as the glyphs.
      ForEach(this.readerV2ImageFragments(chapterIndex, pageIndex, source), (fragment: ReaderV2PageFragment) => {
        this.readerV2ImageFragmentView(fragment)
      }, (fragment: ReaderV2PageFragment) => `reader_v2_image_${fragment.blockId}_` +
        `${Math.round(fragment.imageRect.left)}_${Math.round(fragment.imageRect.top)}_` +
        `${Math.round(fragment.imageRect.right)}_${Math.round(fragment.imageRect.bottom)}`)
      // The retained V2 node paints the bubble background and glyphs. Keep the theme cap artwork in a
      // lightweight ArkUI overlay so the actual reader uses the same ornaments as the font-settings preview.
      this.readerV2RegexBubbleCapsForPage(chapterIndex, pageIndex, source)
    }
    // Pagination subtracts the spread divider before measuring each column. Giving both native pages 50% plus
    // the divider makes their live width differ from the simulation capture width by the divider/fractional pixel,
    // which can reflow or shift glyphs when the capture hands off to the settled spread.
    .width(halfWidth ? this.getReaderPageColumnWidth() : '100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerV2RegexBubbleCapsForPage(chapterIndex: number, pageIndex: number, source: string) {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.readerV2PageFragments(chapterIndex, pageIndex, source),
        (fragment: ReaderV2PageFragment) => {
          ForEach(fragment.regexBubbleSegments, (segment: ReaderV2RegexBubbleSegment) => {
            this.readerV2RegexBubbleCaps(segment)
          }, (segment: ReaderV2RegexBubbleSegment) =>
            `reader_v2_bubble_caps_${segment.styleId}_${segment.rect.left}_${segment.rect.top}_` +
            `${segment.rect.right}_${segment.rect.bottom}_${segment.leading ? 'l' : ''}${segment.trailing ? 'r' : ''}`)
        }, (fragment: ReaderV2PageFragment) => `reader_v2_bubble_fragment_${fragment.blockId}_` +
          `${fragment.displayStart}_${fragment.displayEnd}`)
    }
    .width('100%')
    .height('100%')
    .zIndex(1)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerV2RegexBubbleCaps(segment: ReaderV2RegexBubbleSegment) {
    if (segment.leading && segment.leadingCapWidthPx > 0.5) {
      Image(ThemeAssetRegistry.regexBubbleCap(segment.styleId))
        .width(px2vp(segment.capSizePx))
        .height(px2vp(segment.capSizePx))
        .objectFit(ImageFit.Contain)
        .position({
          x: px2vp(segment.rect.left),
          y: px2vp(segment.rect.top + (segment.rect.height() - segment.capSizePx) / 2)
        })
        .hitTestBehavior(HitTestMode.None)
    }
    if (segment.trailing && segment.trailingCapWidthPx > 0.5) {
      Image(ThemeAssetRegistry.regexBubbleCap(segment.styleId))
        .width(px2vp(segment.capSizePx))
        .height(px2vp(segment.capSizePx))
        .objectFit(ImageFit.Contain)
        .rotate({ angle: 180 })
        .position({
          x: px2vp(segment.rect.right - segment.capSizePx),
          y: px2vp(segment.rect.top + (segment.rect.height() - segment.capSizePx) / 2)
        })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  currentReaderV2TtsOverlayKeys(paintVersion: number): string[] {
    if (!this.shouldUseReaderLayoutV2(this.pagedContentText) || !this.shouldRenderTtsFocus() ||
      this.readerV2TtsSourceStart < 0 || this.readerV2TtsSourceEnd <= this.readerV2TtsSourceStart) return [];
    return [`reader_v2_tts_${this.currentChapterIndex}_${this.currentPageIndex}_${paintVersion}`];
  }

  currentReaderV2SelectionSurfaceKeys(hostVersion: number): string[] {
    if (!this.shouldUseReaderLayoutV2(this.pagedContentText) ||
      this.readerV2NativeSelectionChapterIndex !== this.currentChapterIndex ||
      this.readerV2NativeSelectionPageIndex < this.currentPageIndex ||
      this.readerV2NativeSelectionPageIndex > this.currentPageIndex +
        (this.isLandscapeDoublePageActive() ? 1 : 0) ||
      this.readerV2NativeSelectionFragmentIndex < 0) return [];
    return [`reader_v2_selection_surface_${this.readerV2NativeSelectionChapterIndex}_` +
      `${this.readerV2NativeSelectionPageIndex}_${this.readerV2NativeSelectionFragmentIndex}_` +
      `${hostVersion}`];
  }

  currentReaderV2SelectionOverlayKeys(paintVersion: number): string[] {
    if (!this.shouldUseReaderLayoutV2(this.pagedContentText) ||
      this.readerV2SelectionChapterIndex !== this.currentChapterIndex ||
      this.readerV2SelectionPageIndex < this.currentPageIndex ||
      this.readerV2SelectionPageIndex > this.currentPageIndex +
        (this.isLandscapeDoublePageActive() ? 1 : 0) ||
      this.readerV2SelectionDisplayStart < 0 ||
      this.readerV2SelectionDisplayEnd <= this.readerV2SelectionDisplayStart) return [];
    return [`reader_v2_selection_paint_${this.readerV2SelectionChapterIndex}_` +
      `${this.readerV2SelectionPageIndex}_${paintVersion}`];
  }

  @Builder
  readerCurrentV2SelectionSurface(_hostVersion: number, offsetX: number, offsetY: number) {
    Column() {
      if (this.isLandscapeDoublePageActive()) {
        Row() {
          Stack({ alignContent: Alignment.TopStart }) {
            this.readerV2NativeSelectionPage(
              `${this.currentReaderSurfaceIndex() === 0 ? 'current_primary' : 'current_alternate'}_left`,
              this.currentChapterIndex, this.currentPageIndex, this.pagedContentText, offsetX, offsetY)
          }
          .width(this.getReaderPageColumnWidth())
          .height('100%')
          Blank()
            .width(READER_DOUBLE_PAGE_DIVIDER_WIDTH)
            .height('100%')
          Stack({ alignContent: Alignment.TopStart }) {
            this.readerV2NativeSelectionPage(
              `${this.currentReaderSurfaceIndex() === 0 ? 'current_primary' : 'current_alternate'}_right`,
              this.currentChapterIndex, this.currentPageIndex + 1, this.pagedContentText, offsetX, offsetY)
          }
          .width(this.getReaderPageColumnWidth())
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        this.readerV2NativeSelectionPage(
          `${this.currentReaderSurfaceIndex() === 0 ? 'current_primary' : 'current_alternate'}_single`,
          this.currentChapterIndex, this.currentPageIndex, this.pagedContentText, offsetX, offsetY)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.getReaderPageContentTopPadding() })
    .translate({ x: this.getCurrentPageTurnX(), y: this.getCurrentPageTurnY() + this.bookmarkPullOffsetY })
    .opacity(this.getCurrentPageTurnOpacity())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerCurrentV2SelectionOverlay(paintVersion: number) {
    Column() {
      if (this.isLandscapeDoublePageActive()) {
        Row() {
          this.readerCurrentV2SelectionOverlayPage(this.currentPageIndex, paintVersion, true)
          Blank()
            .width(READER_DOUBLE_PAGE_DIVIDER_WIDTH)
            .height('100%')
          this.readerCurrentV2SelectionOverlayPage(this.currentPageIndex + 1, paintVersion, true)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        this.readerCurrentV2SelectionOverlayPage(this.currentPageIndex, paintVersion)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.getReaderPageContentTopPadding() })
    .translate({ x: this.getCurrentPageTurnX(), y: this.getCurrentPageTurnY() + this.bookmarkPullOffsetY })
    .opacity(this.getCurrentPageTurnOpacity())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerCurrentV2SelectionOverlayPage(pageIndex: number, paintVersion: number,
    halfWidth: boolean = false) {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.readerV2SelectionHighlightRects(
        this.currentChapterIndex, pageIndex, this.pagedContentText, paintVersion),
      (rect: ReaderV2HighlightRect) => {
        this.readerV2SelectionHighlightRect(rect)
      }, (rect: ReaderV2HighlightRect) => rect.key)
    }
    .width(halfWidth ? this.getReaderPageColumnWidth() : '100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerCurrentV2TtsOverlay(paintVersion: number) {
    Column() {
      if (this.isLandscapeDoublePageActive()) {
        Row() {
          this.readerCurrentV2TtsOverlayPage(this.currentPageIndex, paintVersion, true)
          Blank()
            .width(READER_DOUBLE_PAGE_DIVIDER_WIDTH)
            .height('100%')
          this.readerCurrentV2TtsOverlayPage(this.currentPageIndex + 1, paintVersion, true)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        this.readerCurrentV2TtsOverlayPage(this.currentPageIndex, paintVersion)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.getReaderPageContentTopPadding() })
    .translate({ x: this.getCurrentPageTurnX(), y: this.getCurrentPageTurnY() + this.bookmarkPullOffsetY })
    .opacity(this.getCurrentPageTurnOpacity())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  readerCurrentV2TtsOverlayPage(pageIndex: number, paintVersion: number, halfWidth: boolean = false) {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.readerV2TtsHighlightRects(
        this.currentChapterIndex, pageIndex, this.pagedContentText, paintVersion),
      (rect: ReaderV2HighlightRect) => {
        this.readerV2TtsHighlightRect(rect)
      }, (rect: ReaderV2HighlightRect) => rect.key)
    }
    .width(halfWidth ? this.getReaderPageColumnWidth() : '100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  readerV2PageFragments(chapterIndex: number, pageIndex: number, source: string): ReaderV2PageFragment[] {
    const page = this.readerV2Page(chapterIndex, pageIndex, source);
    return page ? page.fragments : [];
  }

  @Builder
  readerV2ImageFragmentView(fragment: ReaderV2PageFragment) {
    // Only opacity is animated: the implicit animation covers attributes declared before it, so page relayouts
    // (size/position) still apply instantly.
    // 已解码的本地插图直接用 PixelMap 绘制：翻页和跨章会新建 Image 节点，用文件地址时新节点要重新异步解码，
    // 解码完成前插图位置是空的。
    Image(this.readerV2ImageContent(fragment, this.readerV2ImageBitmapVersion))
      .syncLoad(this.readerV2ImageBitmapReady(fragment, this.readerV2ImageBitmapVersion))
      .opacity(this.isReaderV2ImageShown(fragment, this.readerV2ImageBitmapVersion) ? 1 : 0)
      .animation({ duration: 220, curve: Curve.EaseOut })
      .width(px2vp(fragment.imageRect.width()))
      .height(px2vp(fragment.imageRect.height()))
      .position({ x: px2vp(fragment.imageRect.left), y: px2vp(fragment.imageRect.top) })
      .objectFit(ImageFit.Contain)
      .draggable(false)
      .hitTestBehavior(HitTestMode.None)
      .onComplete(() => {
        this.markReaderV2ImageLoaded(fragment.imageSource);
      })
      .onError((error: ImageError) => {
        console.error(`[Reader] 图片加载失败 path=${fragment.imageSource} message=${error?.message || ''}`);
        this.markReaderV2ImageBroken(fragment.imageSource);
      })
    if (this.readerV2BrokenImageSources.includes(fragment.imageSource)) {
      Text('图片加载失败')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.getSubTextColor())
        .textAlign(TextAlign.Center)
        .width(px2vp(fragment.imageRect.width()))
        .height(px2vp(fragment.imageRect.height()))
        .position({ x: px2vp(fragment.imageRect.left), y: px2vp(fragment.imageRect.top) })
        .hitTestBehavior(HitTestMode.None)
    } else if (!this.isReaderV2ImageShown(fragment, this.readerV2ImageBitmapVersion)) {
      LoadingProgress()
        .color(this.getSubTextColor())
        .width(READER_V2_IMAGE_LOADING_SIZE)
        .height(READER_V2_IMAGE_LOADING_SIZE)
        .position({
          x: px2vp(fragment.imageRect.left + fragment.imageRect.width() / 2) - READER_V2_IMAGE_LOADING_SIZE / 2,
          y: px2vp(fragment.imageRect.top + fragment.imageRect.height() / 2) - READER_V2_IMAGE_LOADING_SIZE / 2
        })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  readerV2ImageContent(fragment: ReaderV2PageFragment, _bitmapVersion: number): string | image.PixelMap {
    const bitmap = this.readerV2ImageBitmaps.get(fragment.imageSource, fragment.imageRect.width(),
      fragment.imageRect.height());
    if (bitmap) return bitmap;
    this.prepareReaderV2ImageBitmap(fragment);
    return this.readerImageUriForSource(fragment.imageSource);
  }

  readerV2ImageBitmapReady(fragment: ReaderV2PageFragment, _bitmapVersion: number): boolean {
    return !!this.readerV2ImageBitmaps.get(fragment.imageSource, fragment.imageRect.width(),
      fragment.imageRect.height());
  }

  isReaderV2ImageShown(fragment: ReaderV2PageFragment, bitmapVersion: number): boolean {
    return this.readerV2LoadedImageSources.includes(fragment.imageSource) ||
      this.readerV2ImageBitmapReady(fragment, bitmapVersion);
  }

  prepareReaderV2ImageBitmap(fragment: ReaderV2PageFragment): void {
    if (!fragment.imageSource) return;
    this.readerV2ImageBitmaps.prepare(fragment.imageSource, fragment.imageRect.width(),
      fragment.imageRect.height(), () => {
        this.readerV2ImageBitmapVersion++;
      });
  }

  /** 提前解码当前页前后几页的插图，翻到时新建的 Image 已能直接用缓存。 */
  prewarmReaderV2ImageBitmaps(chapterIndex: number, pageIndex: number, source: string): void {
    const pageSet = this.readerV2PageSet(chapterIndex, source);
    if (!pageSet) return;
    const first = Math.max(0, pageIndex - READER_V2_IMAGE_PREWARM_PAGES);
    const last = Math.min(pageSet.pages.length - 1, pageIndex + READER_V2_IMAGE_PREWARM_PAGES);
    for (let index = first; index <= last; index++) {
      for (const fragment of pageSet.pages[index].fragments) {
        if (fragment.imageSource) this.prepareReaderV2ImageBitmap(fragment);
      }
    }
  }

  markReaderV2ImageLoaded(imageSource: string): void {
    if (!imageSource || this.readerV2LoadedImageSources.includes(imageSource)) return;
    this.readerV2LoadedImageSources = [...this.readerV2LoadedImageSources.slice(-127), imageSource];
  }

  markReaderV2ImageBroken(imageSource: string): void {
    if (!imageSource || this.readerV2BrokenImageSources.includes(imageSource)) return;
    this.readerV2BrokenImageSources = [...this.readerV2BrokenImageSources.slice(-63), imageSource];
  }

  readerV2ImageFragments(chapterIndex: number, pageIndex: number, source: string): ReaderV2PageFragment[] {
    const page = this.readerV2Page(chapterIndex, pageIndex, source);
    if (!page) return READER_V2_NO_FRAGMENTS;
    this.prewarmReaderV2ImageBitmaps(chapterIndex, pageIndex, source);
    let result: ReaderV2PageFragment[] = READER_V2_NO_FRAGMENTS;
    for (const fragment of page.fragments) {
      if (!fragment.imageSource) continue;
      if (result === READER_V2_NO_FRAGMENTS) result = [];
      result.push(fragment);
    }
    return result;
  }

  readerV2NativeSelectionKey(role: string, chapterIndex: number, pageIndex: number,
    page: ReaderV2PageLayout): string {
    // Every lazy host owns a fresh controller. A controller retained from a destroyed host can expose the previous
    // page's LayoutManager briefly and put selection handles on stale glyph coordinates.
    return `reader_v2_native_page_${role}_${chapterIndex}_${pageIndex}_${page.identity}_` +
      `${this.readerV2NativeSelectionHostVersion}`;
  }

  // exactGaps: give every paragraph the gap the V2 layout actually left after it (plus extraGapPx) instead of
  // the nominal paragraph spacing. A native Text pads only its own first and last line, while every V2 block
  // is padded separately, so the nominal spacing lets the handles drift a little further with each paragraph.
  readerV2SelectionStyledText(page: ReaderV2PageLayout, exactGaps: boolean = false,
    extraGapPx: number = 0): MutableStyledString {
    const cacheKey = `${page.identity}_selection_page${exactGaps ? `_gaps_${Math.round(extraGapPx * 100)}` : ''}`;
    const cached = this.readerV2SelectionStyledTextCache.get(cacheKey);
    if (cached) return cached;
    const styles: StyleOptions[] = [];
    const snapshot = this.readerV2ActiveSnapshot || this.buildReaderV2Snapshot();
    for (let fragmentIndex = 0; fragmentIndex < page.fragments.length; fragmentIndex++) {
      const fragment = page.fragments[fragmentIndex];
      // Image fragments contribute nothing to the transparent selection text.
      if (!fragment.paragraph) continue;
      let runStart = fragment.selectionPageStart;
      for (const run of fragment.selectionRuns) {
        styles.push({
          start: runStart,
          length: run.text.length,
          styledKey: StyledStringKey.FONT,
          styledValue: new TextStyle({
            fontSize: LengthMetrics.px(run.fontSizePx),
            fontFamily: run.fontFamily || this.getBodyReaderFontFamily(),
            fontWeight: run.fontWeight,
            fontColor: Color.Transparent
          })
        });
        styles.push({
          start: runStart,
          length: run.text.length,
          styledKey: StyledStringKey.LETTER_SPACING,
          styledValue: new LetterSpacingStyle(LengthMetrics.px(run.letterSpacingPx))
        });
        runStart += run.text.length;
      }
      const paragraphLength = fragment.selectionPageEnd - fragment.selectionPageStart +
        (fragment.selectionBreakAfter ? 1 : 0);
      if (paragraphLength > 0) {
        styles.push({
          start: fragment.selectionPageStart,
          length: paragraphLength,
          styledKey: StyledStringKey.PARAGRAPH_STYLE,
          styledValue: new ParagraphStyle({
            textAlign: this.readerTextAlignValue(),
            wordBreak: WordBreak.BREAK_WORD,
            paragraphSpacing: LengthMetrics.px(exactGaps ?
              this.readerV2SelectionGapAfterPx(page, fragmentIndex, extraGapPx) : snapshot.paragraphSpacingPx)
          })
        });
      }
    }
    const styled = new MutableStyledString(page.selectionText, styles);
    this.readerV2SelectionStyledTextCache.set(cacheKey, styled);
    while (this.readerV2SelectionStyledTextCache.size > 64) {
      const oldest = this.readerV2SelectionStyledTextCache.keys().next().value as string | undefined;
      if (!oldest) break;
      this.readerV2SelectionStyledTextCache.delete(oldest);
    }
    return styled;
  }

  readerV2NativeSelectionController(key: string, page: ReaderV2PageLayout): TextController {
    const controller = this.readerSelectableTextController(key);
    try {
      controller.setStyledString(this.readerV2SelectionStyledText(page, true,
        this.readerV2SelectionExtraGaps.get(page.identity) || 0));
    } catch (_) {
    }
    return controller;
  }

  readerV2DisplayOffsetForPageSelection(page: ReaderV2PageLayout, selectionOffset: number): number {
    const target = Math.max(0, Math.min(page.selectionText.length, selectionOffset));
    let previousDisplayEnd = page.displayStart;
    for (const fragment of page.fragments) {
      if (!fragment.paragraph) continue;
      if (target < fragment.selectionPageStart) return previousDisplayEnd;
      if (target <= fragment.selectionPageEnd) {
        return fragment.displayStart + Math.max(0,
          Math.min(fragment.displayEnd - fragment.displayStart, target - fragment.selectionPageStart));
      }
      previousDisplayEnd = fragment.displayEnd;
    }
    return page.displayEnd;
  }

  showReaderV2NativeSelectionAfterLayout(page: ReaderV2PageLayout, fragmentIndex: number,
    controller: TextController, hostVersion: number, attempt: number = 0): void {
    setTimeout(() => {
      if (hostVersion !== this.readerV2NativeSelectionHostVersion ||
        this.readerV2NativeSelectionPendingSerial !== this.readerTextSelectionSerial ||
        !this.readerPageVisible || this.readerV2NativeSelectionPendingStart < 0 ||
        this.readerV2NativeSelectionPendingEnd <= this.readerV2NativeSelectionPendingStart) return;
      let calibrated = false;
      try {
        const manager = controller.getLayoutManager();
        const fragment = page.fragments[fragmentIndex];
        if (manager && fragment && fragment.paragraph) {
          const fragmentStart = Math.max(0,
            this.readerV2NativeSelectionPendingStart - fragment.selectionPageStart);
          const fragmentEnd = Math.min(fragment.selectionPageEnd - fragment.selectionPageStart,
            this.readerV2NativeSelectionPendingEnd - fragment.selectionPageStart);
          const nativeBoxes = manager.getRectsForRange({
            start: this.readerV2NativeSelectionPendingStart,
            end: this.readerV2NativeSelectionPendingEnd
          }, graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
          const paintedBoxes = fragment.paragraph.getRectsForRange({ start: fragmentStart, end: fragmentEnd },
            graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
          if (nativeBoxes.length > 0 && paintedBoxes.length > 0) {
            const nativeRect = nativeBoxes[0].rect;
            const paintedRect = paintedBoxes[0].rect;
            const offsetX = fragment.paragraphX + paintedRect.left - (page.selectionX + nativeRect.left);
            const offsetY = fragment.paragraphY + paintedRect.top - (page.selectionY + nativeRect.top);
            if (Number.isFinite(offsetX) && Number.isFinite(offsetY) &&
              Math.abs(offsetX) <= Math.max(1, page.selectionWidth * 0.5) &&
              Math.abs(offsetY) <= Math.max(1, page.selectionHeight * 0.5)) {
              this.readerV2NativeSelectionOffsetX = offsetX;
              this.readerV2NativeSelectionOffsetY = offsetY;
              calibrated = true;
            }
          }
        }
      } catch (_) {
      }
      if (!calibrated && attempt < 4) {
        this.showReaderV2NativeSelectionAfterLayout(page, fragmentIndex, controller, hostVersion, attempt + 1);
        return;
      }
      setTimeout(() => {
        if (hostVersion !== this.readerV2NativeSelectionHostVersion ||
          this.readerV2NativeSelectionPendingSerial !== this.readerTextSelectionSerial ||
          !this.readerPageVisible) return;
        try {
          controller.setTextSelection(this.readerV2NativeSelectionPendingStart,
            this.readerV2NativeSelectionPendingEnd, { menuPolicy: MenuPolicy.SHOW });
        } catch (_) {
        }
      }, calibrated ? 32 : 0);
    }, attempt === 0 ? 16 : 24);
  }

  @Builder
  readerV2NativeSelectionPage(role: string, chapterIndex: number, pageIndex: number, source: string,
    offsetX: number, offsetY: number) {
    if (chapterIndex === this.readerV2NativeSelectionChapterIndex &&
      pageIndex === this.readerV2NativeSelectionPageIndex && role === this.readerV2NativeSelectionRole &&
      this.readerV2Page(chapterIndex, pageIndex, source)) {
      if ((this.readerV2Page(chapterIndex, pageIndex, source) as ReaderV2PageLayout).selectionText &&
        this.readerV2NativeSelectionFragmentIndex >= 0 &&
        this.readerV2NativeSelectionFragmentIndex <
          (this.readerV2Page(chapterIndex, pageIndex, source) as ReaderV2PageLayout).fragments.length) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.readerV2NativeSelectionText(role, chapterIndex, pageIndex,
            this.readerV2Page(chapterIndex, pageIndex, source) as ReaderV2PageLayout,
            this.readerV2NativeSelectionFragmentIndex, offsetX, offsetY)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }
    }
  }

  onReaderV2NativeSelectionChanged(page: ReaderV2PageLayout, chapterIndex: number, pageIndex: number,
    selectionStart: number, selectionEnd: number): void {
    const textLength = page.selectionText.length;
    this.readerTextSelectionUntil = Date.now() + 900;
    this.suppressReaderTapClick = true;
    this.readerTouchActive = false;
    this.readerPanActive = false;
    const safeStart = Math.max(0, Math.min(selectionStart, textLength));
    const safeEnd = Math.max(safeStart, Math.min(selectionEnd, textLength));
    if (safeEnd > safeStart) {
      this.readerV2SelectionChapterIndex = chapterIndex;
      this.readerV2SelectionPageIndex = pageIndex;
      this.readerV2SelectionDisplayStart = this.readerV2DisplayOffsetForPageSelection(page, safeStart);
      this.readerV2SelectionDisplayEnd = this.readerV2DisplayOffsetForPageSelection(page, safeEnd);
      this.readerV2SelectionPaintVersion++;
    }
  }

  // The transparent system Text that owns the selection handles and menu. It wraps its content at the top of
  // its host, and its measured height calibrates the paragraph gaps (see calibrateReaderV2NativeSelection),
  // so handles stay on the painted glyphs however many paragraphs the selection is dragged across.
  @Builder
  readerV2NativeSelectionText(role: string, chapterIndex: number, pageIndex: number,
    page: ReaderV2PageLayout, fragmentIndex: number, offsetX: number, offsetY: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (deviceInfo.sdkApiVersion >= 23) {
        Text('', { controller: this.readerV2NativeSelectionController(
          this.readerV2NativeSelectionKey(role, chapterIndex, pageIndex, page), page) })
          .lineSpacing(LengthMetrics.vp(px2vp(this.toMeasureNonNegativePx(this.readerLineHeight))),
            { onlyBetweenLines: true })
          .halfLeading(false)
          .includeFontPadding(true)
          .textAlign(this.readerTextAlignValue())
          .wordBreak(WordBreak.BREAK_WORD)
          .lineBreakStrategy(LineBreakStrategy.GREEDY)
          .copyOption(CopyOptions.LocalDevice)
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .editMenuOptions(this.readerTextEditMenuOptions(() => page.selectionText))
          .onCopy(() => this.scheduleReaderTextSelectionClear())
          .selectedBackgroundColor(Color.Transparent)
          .width('100%')
          .hitTestBehavior(HitTestMode.None)
          .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
            this.onReaderV2NativeSelectionChanged(page, chapterIndex, pageIndex, selectionStart, selectionEnd);
          })
          .id(`reader_v2_selection_${role}_${chapterIndex}_${pageIndex}`)
          .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
            this.calibrateReaderV2NativeSelection(page, fragmentIndex,
              this.readerV2NativeSelectionKey(role, chapterIndex, pageIndex, page),
              vp2px(Number(newValue.height)), this.readerV2NativeSelectionHostVersion);
          })
      } else {
        // 选区文本层的 onlyBetweenLines 行距（API 20）、includeFontPadding（API 23）和透明选中底色（API 14）
        // 在旧系统上不存在，调用会抛错。这里退回基础属性：手柄位置靠高度自校准兜底，
        // 系统自带的选中底色会和绘制的高亮叠在一起。
        Text('', { controller: this.readerV2NativeSelectionController(
          this.readerV2NativeSelectionKey(role, chapterIndex, pageIndex, page), page) })
          .lineSpacing(LengthMetrics.vp(px2vp(this.toMeasureNonNegativePx(this.readerLineHeight))))
          .halfLeading(false)
          .textAlign(this.readerTextAlignValue())
          .wordBreak(WordBreak.BREAK_WORD)
          .lineBreakStrategy(LineBreakStrategy.GREEDY)
          .copyOption(CopyOptions.LocalDevice)
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .editMenuOptions(this.readerTextEditMenuOptions(() => page.selectionText))
          .onCopy(() => this.scheduleReaderTextSelectionClear())
          .width('100%')
          .hitTestBehavior(HitTestMode.None)
          .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
            this.onReaderV2NativeSelectionChanged(page, chapterIndex, pageIndex, selectionStart, selectionEnd);
          })
          .id(`reader_v2_selection_${role}_${chapterIndex}_${pageIndex}`)
          .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
            this.calibrateReaderV2NativeSelection(page, fragmentIndex,
              this.readerV2NativeSelectionKey(role, chapterIndex, pageIndex, page),
              vp2px(Number(newValue.height)), this.readerV2NativeSelectionHostVersion);
          })
      }
    }
    .width(px2vp(page.selectionWidth))
    .height(px2vp(Math.max(1, page.selectionHeight)))
    .position({ x: px2vp(page.selectionX + offsetX), y: px2vp(page.selectionY + offsetY) })
    .hitTestBehavior(HitTestMode.None)
  }

  readerV2SurfaceTopOffset(): number {
    // Simulation/stack pages are laid out in a full-screen sheet and inset the live正文 with explicit top
    // padding. onAreaChange still reports the unpadded sheet origin for both the page and tap layer, so their
    // global-position delta can be zero even though painted glyphs start below the status bar. Keep that
    // declarative padding in the hit-test origin; otherwise every long press resolves roughly one line lower.
    const contentTopPadding = this.getReaderPageContentTopPadding();
    const measuredOffset = this.readerCommentPageAreaTop - this.readerTapLayerGlobalY;
    if (this.readerCommentPageAreaTop >= 0 && Number.isFinite(measuredOffset)) {
      return Math.max(contentTopPadding, measuredOffset);
    }
    return contentTopPadding;
  }

  clearReaderV2SelectionOverlay(): void {
    const hasNativeHost = this.readerV2NativeSelectionFragmentIndex >= 0;
    if (this.readerV2SelectionDisplayStart < 0 && this.readerV2SelectionDisplayEnd < 0 && !hasNativeHost) return;
    this.readerV2SelectionChapterIndex = -1;
    this.readerV2SelectionPageIndex = -1;
    this.readerV2SelectionDisplayStart = -1;
    this.readerV2SelectionDisplayEnd = -1;
    this.readerV2NativeSelectionChapterIndex = -1;
    this.readerV2NativeSelectionPageIndex = -1;
    this.readerV2NativeSelectionFragmentIndex = -1;
    this.readerV2NativeSelectionRole = '';
    this.readerV2NativeSelectionPendingStart = -1;
    this.readerV2NativeSelectionPendingEnd = -1;
    this.readerV2NativeSelectionPendingSerial = -1;
    this.readerV2NativeSelectionOffsetX = 0;
    this.readerV2NativeSelectionOffsetY = 0;
    this.readerV2NativeSelectionHostVersion++;
    this.readerV2SelectionPaintVersion++;
  }

  readerV2ActionAtLocalPoint(xVp: number, yVp: number): string {
    const located = this.readerV2LocatedPagePoint(xVp, yVp);
    if (located.length < 4) return '';
    const pageIndex = located[0];
    const xPx = located[1];
    const yPx = located[2];
    const page = this.readerV2Page(this.currentChapterIndex, pageIndex, this.pagedContentText);
    const snapshot = this.readerV2ActiveSnapshot || this.buildReaderV2Snapshot();
    const hit: ReaderV2TapResult = ReaderV2GestureRouter.hitTest(page, snapshot, xPx, yPx);
    return hit.kind === 'action' ? hit.marker : '';
  }

  readerV2LocatedPagePoint(xVp: number, yVp: number): number[] {
    let pageIndex = this.currentPageIndex;
    let localX = xVp;
    if (this.isLandscapeDoublePageActive()) {
      const dividerLeft = Math.max(0, (this.pageViewWidth - READER_DOUBLE_PAGE_DIVIDER_WIDTH) / 2);
      if (xVp > dividerLeft + READER_DOUBLE_PAGE_DIVIDER_WIDTH) {
        pageIndex++;
        localX = xVp - dividerLeft - READER_DOUBLE_PAGE_DIVIDER_WIDTH;
      }
    }
    return [pageIndex, this.toMeasurePx(localX), this.toMeasurePx(yVp), 1];
  }

  selectReaderV2TextAtGlobalPoint(globalX: number, globalY: number, serial: number, attempt: number): void {
    if (serial !== this.readerTextSelectionSerial) return;
    const localX = globalX - this.readerTapLayerGlobalX;
    const localY = globalY - this.readerTapLayerGlobalY - this.readerV2SurfaceTopOffset();
    const located = this.readerV2LocatedPagePoint(localX, localY);
    if (located.length < 4) return;
    const pageIndex = located[0];
    // The retained page surface alternates between two keyed buffers. Selection must address
    // the controller attached to the currently visible buffer; using a generic current_left key
    // silently created a detached TextController whose selection menu could never appear.
    const surfaceRole = this.currentReaderSurfaceIndex() === 0 ? 'current_primary' : 'current_alternate';
    const role = this.isLandscapeDoublePageActive() ?
      `${surfaceRole}_${pageIndex === this.currentPageIndex ? 'left' : 'right'}` : `${surfaceRole}_single`;
    const page = this.readerV2Page(this.currentChapterIndex, pageIndex, this.pagedContentText);
    if (!page || !page.selectionText) {
      this.retryReaderTextSelection(serial, attempt,
        (nextAttempt: number): void => this.selectReaderV2TextAtGlobalPoint(
          globalX, globalY, serial, nextAttempt));
      return;
    }
    const selectionResult = this.beginReaderV2NativeSelection(page, pageIndex, role, located[1], located[2],
      serial);
    if (selectionResult === 1) return;
    if (selectionResult === 0 && attempt >= 3) return;
    this.retryReaderTextSelection(serial, attempt,
      (nextAttempt: number): void => this.selectReaderV2TextAtGlobalPoint(
        globalX, globalY, serial, nextAttempt));
  }

  // Starts a native selection on the fragment under (xPx, yPx) of a laid-out V2 page; the paged reader and
  // continuous scrolling share it. Returns 1 when the selection host was requested, 0 when no fragment is
  // under the point, and 2 when a fragment was hit but could not take a selection yet.
  beginReaderV2NativeSelection(page: ReaderV2PageLayout, pageIndex: number, role: string, xPx: number,
    yPx: number, serial: number): number {
    let matchedFragment = false;
    const selectionSlop = this.toMeasurePx(8);
    for (let fragmentIndex = 0; fragmentIndex < page.fragments.length; fragmentIndex++) {
      const fragment = page.fragments[fragmentIndex];
      if (!fragment.clipRect.contains(xPx, yPx, selectionSlop, selectionSlop)) continue;
      matchedFragment = true;
      try {
        if (!fragment.paragraph) break;
        // The transparent Text's LayoutManager can stay unavailable on some HarmonyOS builds
        // even though it is already on screen. The painted paragraph is the pagination source of
        // truth and always has the exact glyph coordinates, so derive the transparent selection
        // offset from it instead of depending on that optional manager.
        const fragmentPosition = fragment.paragraph.getGlyphPositionAtCoordinate(
          xPx - fragment.paragraphX, yPx - fragment.paragraphY).position;
        const text = page.selectionText;
        let position = fragment.selectionPageStart + Math.max(0,
          Math.min(fragment.selectionPageEnd - fragment.selectionPageStart - 1, fragmentPosition));
        position = Math.max(0, Math.min(text.length - 1, position));
        while (position < text.length - 1 && /\s/.test(text.charAt(position))) position++;
        while (position > 0 && /\s/.test(text.charAt(position))) position--;
        let start = position;
        let end = Math.min(text.length, position + 1);
        const wordPattern = /[A-Za-z0-9_]/;
        if (wordPattern.test(text.charAt(position))) {
          while (start > 0 && wordPattern.test(text.charAt(start - 1))) start--;
          while (end < text.length && wordPattern.test(text.charAt(end))) end++;
        } else {
          const code = text.charCodeAt(position);
          if (code >= 0xDC00 && code <= 0xDFFF && start > 0) start--;
          if (code >= 0xD800 && code <= 0xDBFF && end < text.length) end++;
        }
        this.readerTextSelectionUntil = Date.now() + 900;
        this.suppressReaderTapClick = true;
        this.readerTouchActive = false;
        this.readerPanActive = false;
        // Mount one whole-page Text only after long press. Its continuous selection range includes the separators
        // between fragments, allowing native handles to cross paragraph boundaries without adding page-turn cost.
        this.readerV2NativeSelectionChapterIndex = this.currentChapterIndex;
        this.readerV2NativeSelectionPageIndex = pageIndex;
        this.readerV2NativeSelectionFragmentIndex = fragmentIndex;
        this.readerV2NativeSelectionRole = role;
        this.readerV2NativeSelectionPendingStart = start;
        this.readerV2NativeSelectionPendingEnd = end;
        this.readerV2NativeSelectionPendingSerial = serial;
        this.readerV2NativeSelectionOffsetX = 0;
        this.readerV2NativeSelectionOffsetY = 0;
        this.readerV2SelectionChapterIndex = this.currentChapterIndex;
        this.readerV2SelectionPageIndex = pageIndex;
        this.readerV2SelectionDisplayStart = this.readerV2DisplayOffsetForPageSelection(page, start);
        this.readerV2SelectionDisplayEnd = this.readerV2DisplayOffsetForPageSelection(page, end);
        this.readerV2SelectionPaintVersion++;
        this.readerV2NativeSelectionHostVersion++;
        return 1;
      } catch (error) {
        console.info('V2 正文选区布局尚未就绪，准备重试:', error);
      }
      break;
    }
    return matchedFragment ? 2 : 0;
  }

  // Vertical gap the layout left between this text fragment and the next one, images in between included.
  readerV2SelectionGapAfterPx(page: ReaderV2PageLayout, fragmentIndex: number, extraGapPx: number): number {
    const fragment = page.fragments[fragmentIndex];
    for (let index = fragmentIndex + 1; index < page.fragments.length; index++) {
      const next = page.fragments[index];
      if (!next.paragraph) continue;
      return Math.max(0, next.paragraphY - (fragment.paragraphY + fragment.paragraphHeight) + extraGapPx);
    }
    return 0;
  }

  // The transparent selection Text wraps its content, so its measured height is the native layout's height.
  // The first measurement of a chunk spreads the difference to the V2 layout over the paragraph gaps; the
  // selection is shown once the corrected text has been laid out.
  calibrateReaderV2NativeSelection(page: ReaderV2PageLayout, fragmentIndex: number, key: string,
    nativeHeightPx: number, hostVersion: number): void {
    if (hostVersion !== this.readerV2NativeSelectionHostVersion ||
      this.readerV2SelectionShownHostVersion === hostVersion || nativeHeightPx <= 0) return;
    const controller = this.readerSelectableTextController(key);
    let paragraphCount = 0;
    for (const fragment of page.fragments) {
      if (fragment.paragraph) paragraphCount++;
    }
    if (!this.readerV2SelectionExtraGaps.has(page.identity)) {
      const extraGapPx = paragraphCount > 1 ? (page.selectionHeight - nativeHeightPx) / (paragraphCount - 1) : 0;
      const usable = Number.isFinite(extraGapPx) && Math.abs(extraGapPx) <= this.toMeasureFontPx(this.readerFontSize) * 2;
      this.readerV2SelectionExtraGaps.set(page.identity, usable ? extraGapPx : 0);
      while (this.readerV2SelectionExtraGaps.size > 48) {
        const oldest = this.readerV2SelectionExtraGaps.keys().next().value as string | undefined;
        if (oldest === undefined) break;
        this.readerV2SelectionExtraGaps.delete(oldest);
      }
      console.info(`[ReaderSelection] calibration v2=${Math.round(page.selectionHeight)} ` +
        `native=${Math.round(nativeHeightPx)} paragraphs=${paragraphCount} ` +
        `extraGap=${Math.round(extraGapPx * 100) / 100}`);
      if (usable && Math.abs(extraGapPx) > 0.5) {
        try {
          controller.setStyledString(this.readerV2SelectionStyledText(page, true, extraGapPx));
        } catch (_) {
        }
        // The corrected text reports a new size and re-enters above. The timer only covers a build that
        // swallows that callback.
        setTimeout(() => {
          this.showReaderV2NativeSelectionOnce(page, fragmentIndex, controller, hostVersion);
        }, 120);
        return;
      }
    }
    this.showReaderV2NativeSelectionOnce(page, fragmentIndex, controller, hostVersion);
  }

  showReaderV2NativeSelectionOnce(page: ReaderV2PageLayout, fragmentIndex: number, controller: TextController,
    hostVersion: number): void {
    if (hostVersion !== this.readerV2NativeSelectionHostVersion ||
      this.readerV2SelectionShownHostVersion === hostVersion) return;
    this.readerV2SelectionShownHostVersion = hostVersion;
    this.showReaderV2NativeSelectionAfterLayout(page, fragmentIndex, controller, hostVersion);
  }

  usesReaderContinuousV2(): boolean {
    return this.isReaderNovelContinuousScrollModeActive();
  }

  // Chunk boundaries are trimmed for progress bookkeeping, which also strips the indent of the paragraph a
  // chunk starts with. Take that indent back from the source so every paragraph is laid out alike.
  readerContinuousV2ChunkText(index: number, text: string, chapterIndex: number = -1): string {
    const start = this.readerContinuousV2ChunkStart(index, text, chapterIndex);
    return start < 0 ? text :
      this.readerContinuousSourceOf(chapterIndex).substring(start, this.readerContinuousEndsOf(chapterIndex)[index]);
  }

  /** 列表里某章的源文本与分块起止；-1 或当前章取当前分页，相邻章节取列表里保存的分页。 */
  readerContinuousSourceOf(chapterIndex: number): string {
    if (chapterIndex < 0 || chapterIndex === this.currentChapterIndex) return this.pagedContentText;
    return this.readerComicPageDataSource.segment(chapterIndex)?.source || '';
  }

  readerContinuousStartsOf(chapterIndex: number): number[] {
    if (chapterIndex < 0 || chapterIndex === this.currentChapterIndex) return this.contentPageStarts;
    return this.readerComicPageDataSource.segment(chapterIndex)?.starts || [];
  }

  readerContinuousEndsOf(chapterIndex: number): number[] {
    if (chapterIndex < 0 || chapterIndex === this.currentChapterIndex) return this.contentPageEnds;
    return this.readerComicPageDataSource.segment(chapterIndex)?.ends || [];
  }

  readerContinuousChapterOf(chapterIndex: number): number {
    return chapterIndex < 0 ? this.currentChapterIndex : chapterIndex;
  }

  // Start of the chunk text in the chapter source, indent included; -1 when the chunk is not a slice of it.
  readerContinuousV2ChunkStart(index: number, text: string, chapterIndex: number = -1): number {
    const source = this.readerContinuousSourceOf(chapterIndex);
    const starts = this.readerContinuousStartsOf(chapterIndex);
    const ends = this.readerContinuousEndsOf(chapterIndex);
    if (!source || index < 0 || index >= starts.length || index >= ends.length) {
      return -1;
    }
    const start = starts[index];
    if (source.substring(start, ends[index]) !== text) return -1;
    let indentStart = start;
    while (indentStart > 0 &&
      (source.charAt(indentStart - 1) === '\u3000' || source.charAt(indentStart - 1) === ' ')) {
      indentStart--;
    }
    return indentStart === start || (indentStart > 0 && source.charAt(indentStart - 1) !== '\n') ? start :
      indentStart;
  }

  // One scrolling chunk laid out by the V2 paragraph engine. Called from list item builders, so the result
  // is cached by content and layout identity; a typography or theme change simply misses the cache.
  readerContinuousV2Layout(index: number, text: string, chapterIndexHint: number = -1): ReaderV2PageLayout | null {
    if (!text || this.pageViewWidth <= 0) return null;
    const snapshot = this.buildReaderV2Snapshot(true);
    const chapterIndex = this.readerContinuousChapterOf(chapterIndexHint);
    const chunk = this.readerContinuousV2ChunkText(index, text, chapterIndex);
    const key = `${chapterIndex}_${index}_${chunk.length}_${this.hashText(chunk)}_${snapshot.identity}`;
    const cached = this.readerContinuousV2Layouts.get(key);
    if (cached) return cached;
    const startedAt = Date.now();
    let layout: ReaderV2PageLayout | null = null;
    try {
      const document = ReaderV2DocumentParser.parse(chunk, chapterIndex,
        index === 0 ? this.getChapterTitle(chapterIndex) : '', this.readerV2HeadingHints(chapterIndex));
      layout = ReaderV2Paginator.layoutContinuous(document, snapshot, this.buildReaderV2RegexStyles(document));
      if (layout) {
        this.readerContinuousV2Documents.set(layout.identity, document);
        this.readerContinuousV2Sources.set(layout.identity, this.readerContinuousV2ChunkStart(index, text, chapterIndex));
      }
    } catch (error) {
      console.error(`[ReaderContinuous] 正文块排版失败 chapter=${chapterIndex} chunk=${index}:`, error);
    }
    if (!layout) return null;
    this.readerContinuousV2Layouts.set(key, layout);
    while (this.readerContinuousV2Layouts.size > 24) {
      const oldest = this.readerContinuousV2Layouts.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      const evicted = this.readerContinuousV2Layouts.get(oldest);
      if (evicted) {
        this.readerContinuousV2Documents.delete(evicted.identity);
        this.readerContinuousV2Sources.delete(evicted.identity);
      }
      this.readerContinuousV2Layouts.delete(oldest);
    }
    CooperativeScheduler.reportSynchronousOperation('reader/v2-continuous-chunk', Date.now() - startedAt,
      `chapter=${chapterIndex},chunk=${index},chars=${chunk.length}`);
    return layout;
  }

  readerContinuousV2ItemHeight(index: number, text: string, chapterIndex: number = -1): number {
    const layout = this.readerContinuousV2Layout(index, text, chapterIndex);
    if (!layout) return 1;
    // Blocks inside a chunk are separated by the paragraph spacing; the same gap separates two chunks.
    const chunkCount = this.readerContinuousEndsOf(chapterIndex).length;
    const gapPx = index < chunkCount - 1 ? this.toMeasureNonNegativePx(this.readerParagraphSpacing) : 0;
    return Math.max(1, px2vp(Math.ceil(layout.contentBottomPx + gapPx)));
  }

  readerContinuousV2Controller(index: number, text: string, chapterIndex: number = -1): ReaderV2PageNodeController {
    const key = `${this.readerContinuousChapterOf(chapterIndex)}_${index}`;
    let controller = this.readerContinuousV2Controllers.get(key);
    if (!controller) {
      controller = new ReaderV2PageNodeController();
      this.readerContinuousV2Controllers.set(key, controller);
    }
    controller.updatePage(this.readerContinuousV2Layout(index, text, chapterIndex));
    return controller;
  }

  /** 只保留列表可见区附近（列表序号）各项的原生排版节点，不论属于哪一章。 */
  pruneReaderContinuousV2Controllers(listFirst: number, listLast: number): void {
    if (this.readerContinuousV2Controllers.size === 0) return;
    const keep: Set<string> = new Set();
    for (let index = Math.max(0, listFirst); index <= listLast; index++) {
      const item = this.readerComicPageDataSource.itemAt(index);
      if (item && item.isPage()) keep.add(`${item.chapterIndex}_${item.pageIndex}`);
    }
    for (const key of Array.from(this.readerContinuousV2Controllers.keys())) {
      if (!keep.has(key)) this.readerContinuousV2Controllers.delete(key);
    }
  }

  readerContinuousV2ItemId(index: number, chapterIndex: number = -1): string {
    return `reader_continuous_v2_${this.readerContinuousChapterOf(chapterIndex)}_${index}`;
  }

  readerContinuousV2Fragments(index: number, text: string, imagesOnly: boolean,
    _renderVersion: number, chapterIndex: number = -1): ReaderV2PageFragment[] {
    const layout = this.readerContinuousV2Layout(index, text, chapterIndex);
    if (!layout) return READER_V2_NO_FRAGMENTS;
    let result: ReaderV2PageFragment[] = READER_V2_NO_FRAGMENTS;
    for (const fragment of layout.fragments) {
      if (imagesOnly ? !fragment.imageSource : fragment.regexBubbleSegments.length === 0) continue;
      if (result === READER_V2_NO_FRAGMENTS) result = [];
      result.push(fragment);
    }
    return result;
  }

  readerContinuousV2SelectionRects(index: number, text: string,
    _paintVersion: number): ReaderV2HighlightRect[] {
    if (this.readerV2SelectionChapterIndex !== this.currentChapterIndex ||
      this.readerV2SelectionPageIndex !== index || this.readerV2SelectionDisplayStart < 0 ||
      this.readerV2SelectionDisplayEnd <= this.readerV2SelectionDisplayStart) return [];
    const layout = this.readerContinuousV2Layout(index, text);
    if (!layout) return [];
    return this.readerV2DisplayHighlightRects(layout, this.readerV2SelectionDisplayStart,
      this.readerV2SelectionDisplayEnd, 'selection');
  }

  // Rectangles of the spoken sentence inside this chunk, in chunk-local pixels.
  readerContinuousV2TtsRects(index: number, text: string, _paintVersion: number): ReaderV2HighlightRect[] {
    if (!this.shouldRenderTtsFocus() || this.readerV2TtsSourceStart < 0 ||
      this.readerV2TtsSourceEnd <= this.readerV2TtsSourceStart || index >= this.contentPageEnds.length ||
      this.readerV2TtsSourceStart >= this.contentPageEnds[index] ||
      this.readerV2TtsSourceEnd <= this.contentPageStarts[index]) return [];
    const layout = this.readerContinuousV2Layout(index, text);
    if (!layout) return [];
    const document = this.readerContinuousV2Documents.get(layout.identity);
    const chunkStart = this.readerContinuousV2Sources.get(layout.identity);
    if (!document || chunkStart === undefined || chunkStart < 0) return [];
    return this.readerV2DisplayHighlightRects(layout,
      document.displayOffsetForSource(Math.max(0, this.readerV2TtsSourceStart - chunkStart)),
      document.displayOffsetForSource(Math.max(0, this.readerV2TtsSourceEnd - chunkStart)), 'tts');
  }

  // Window rectangle [top, bottom] in pixels of the list's text area, or an empty array before it is laid out.
  readerContinuousV2ViewportPx(): number[] {
    try {
      const rect = this.getUIContext().getComponentUtils().getRectangleById(READER_CONTINUOUS_LIST_ID);
      if (rect.size.height <= 0) return [];
      return [rect.windowOffset.y + this.toMeasureNonNegativePx(this.getEffectiveReaderMarginTop()),
        rect.windowOffset.y + rect.size.height -
          this.toMeasureNonNegativePx(this.getReaderContinuousScrollBottomPadding())];
    } catch (_) {
      return [];
    }
  }

  // Chapter source offset of the first line that is fully on screen, or -1 when it cannot be resolved.
  readerContinuousV2FirstVisibleSourceOffset(): number {
    const viewport = this.readerContinuousV2ViewportPx();
    if (viewport.length < 2 || this.contentPages.length === 0) return -1;
    const first = Math.max(0, this.readerContinuousVisibleStart);
    const last = Math.min(this.contentPages.length - 1, this.readerContinuousVisibleEnd);
    for (let index = first; index <= last; index++) {
      try {
        const rect = this.getUIContext().getComponentUtils().getRectangleById(this.readerContinuousV2ItemId(index));
        if (rect.size.height <= 0 || rect.windowOffset.y + rect.size.height <= viewport[0]) continue;
        const layout = this.readerContinuousV2Layout(index, this.contentPages[index] || '');
        if (!layout) continue;
        const document = this.readerContinuousV2Documents.get(layout.identity);
        const chunkStart = this.readerContinuousV2Sources.get(layout.identity);
        if (!document || chunkStart === undefined || chunkStart < 0) continue;
        const localTop = viewport[0] - rect.windowOffset.y;
        for (const fragment of layout.fragments) {
          if (!fragment.paragraph) continue;
          for (const line of fragment.paragraph.getLineMetrics()) {
            if (fragment.paragraphY + line.topHeight < localTop - 1) continue;
            return chunkStart + document.sourceOffsetForDisplay(fragment.displayStart + line.startIndex);
          }
        }
      } catch (_) {
      }
    }
    return -1;
  }

  // Keeps the spoken sentence on screen in the scrolling list. A manual scroll is respected for a moment, so
  // the reader can look ahead without the list snapping back at the next sentence; force skips that grace.
  followReaderContinuousTtsFocus(force: boolean): void {
    if (!this.usesReaderContinuousV2() || this.readerV2TtsSourceStart < 0 || this.contentPages.length === 0 ||
      this.readerTextSelectionActive || this.readerComicScrollRestoring || this.pendingRestorePageIndex >= 0 ||
      this.readerComicChapterSwitching) return;
    if (!force && Date.now() - this.readerContinuousPointerAt < READER_CONTINUOUS_TTS_FOLLOW_GRACE_MS) return;
    const index = this.findPageIndexByOffset(this.readerV2TtsSourceStart);
    if (index < 0 || index >= this.contentPages.length) return;
    const rects = this.readerContinuousV2TtsRects(index, this.contentPages[index] || '', 0);
    const viewport = this.readerContinuousV2ViewportPx();
    if (viewport.length < 2) return;
    const viewportHeightPx = viewport[1] - viewport[0];
    let focusTopPx = 0;
    if (rects.length > 0) {
      focusTopPx = rects[0].topPx;
      const focusBottomPx = rects[rects.length - 1].topPx + rects[rects.length - 1].heightPx;
      try {
        const rect = this.getUIContext().getComponentUtils().getRectangleById(this.readerContinuousV2ItemId(index));
        if (rect.size.height > 0) {
          const top = rect.windowOffset.y + focusTopPx;
          const bottom = rect.windowOffset.y + focusBottomPx;
          // Leave the lowest part of the screen out: a sentence there is about to scroll off anyway.
          if (top >= viewport[0] && bottom <= viewport[1] - viewportHeightPx * 0.18) return;
        }
      } catch (_) {
      }
    }
    try {
      this.readerComicScroller.scrollToIndex(this.readerContinuousListIndex(index), true, ScrollAlign.START,
        { extraOffset: LengthMetrics.vp(px2vp(focusTopPx - viewportHeightPx * 0.22)) });
    } catch (error) {
      console.warn('[ReaderContinuous] 跟随朗读焦点滚动失败:', error);
    }
  }

  // Whether the native selection host belongs to this chunk. hostVersion is the reactive trigger: the
  // owning fields are plain members.
  readerContinuousV2OwnsSelection(index: number, text: string, _hostVersion: number): boolean {
    if (this.readerV2NativeSelectionRole !== READER_V2_CONTINUOUS_ROLE ||
      this.readerV2NativeSelectionChapterIndex !== this.currentChapterIndex ||
      this.readerV2NativeSelectionPageIndex !== index || this.readerV2NativeSelectionFragmentIndex < 0) return false;
    const layout = this.readerContinuousV2Layout(index, text);
    return !!layout && !!layout.selectionText &&
      this.readerV2NativeSelectionFragmentIndex < layout.fragments.length;
  }

  @Builder
  readerContinuousV2Item(chapterIndex: number, index: number, text: string, renderVersion: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      NodeContainer(this.readerContinuousV2Controller(index, text, chapterIndex))
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      ForEach(this.readerContinuousV2Fragments(index, text, true, renderVersion, chapterIndex),
        (fragment: ReaderV2PageFragment) => {
        this.readerV2ImageFragmentView(fragment)
      }, (fragment: ReaderV2PageFragment) => `reader_continuous_v2_image_${fragment.blockId}_` +
        `${Math.round(fragment.imageRect.top)}_${Math.round(fragment.imageRect.bottom)}`)
      ForEach(this.readerContinuousV2Fragments(index, text, false, renderVersion, chapterIndex),
        (fragment: ReaderV2PageFragment) => {
        ForEach(fragment.regexBubbleSegments, (segment: ReaderV2RegexBubbleSegment) => {
          this.readerV2RegexBubbleCaps(segment)
        }, (segment: ReaderV2RegexBubbleSegment) =>
          `reader_continuous_v2_caps_${segment.styleId}_${segment.rect.left}_${segment.rect.top}_` +
          `${segment.rect.right}_${segment.rect.bottom}_${segment.leading ? 'l' : ''}${segment.trailing ? 'r' : ''}`)
      }, (fragment: ReaderV2PageFragment) => `reader_continuous_v2_bubble_${fragment.blockId}_` +
        `${fragment.displayStart}_${fragment.displayEnd}`)
      // 朗读焦点、选区只属于当前章；相邻章节的块只读显示，滚进视口顶部成为当前章后再挂上。
      if (chapterIndex === this.currentChapterIndex) {
        ForEach(this.readerContinuousV2TtsRects(index, text, this.readerV2TtsPaintVersion),
          (rect: ReaderV2HighlightRect) => {
          this.readerV2TtsHighlightRect(rect)
        }, (rect: ReaderV2HighlightRect) => rect.key)
        ForEach(this.readerContinuousV2SelectionRects(index, text, this.readerV2SelectionPaintVersion),
          (rect: ReaderV2HighlightRect) => {
          this.readerV2SelectionHighlightRect(rect)
        }, (rect: ReaderV2HighlightRect) => rect.key)
        if (this.readerContinuousV2OwnsSelection(index, text, this.readerV2NativeSelectionHostVersion)) {
          this.readerV2NativeSelectionText(READER_V2_CONTINUOUS_ROLE, this.currentChapterIndex, index,
            this.readerContinuousV2Layout(index, text) as ReaderV2PageLayout,
            this.readerV2NativeSelectionFragmentIndex, this.readerV2NativeSelectionOffsetX,
            this.readerV2NativeSelectionOffsetY)
        }
      }
    }
    .id(this.readerContinuousV2ItemId(index, chapterIndex))
    .width('100%')
    .height(this.readerContinuousV2ItemHeight(index, text, chapterIndex))
  }

  // [chunk index, xPx, yPx] of a window point inside a mounted chunk, or an empty array. The item rectangle
  // is read on demand, so no per-frame area callback runs while the list scrolls.
  readerContinuousV2Locate(globalX: number, globalY: number): number[] {
    if (this.contentPages.length === 0) return [];
    const pointX = vp2px(globalX);
    const pointY = vp2px(globalY);
    const first = Math.max(0, this.readerContinuousVisibleStart - 1);
    const last = Math.min(this.contentPages.length - 1, this.readerContinuousVisibleEnd + 1);
    for (let index = first; index <= last; index++) {
      try {
        const rect = this.getUIContext().getComponentUtils().getRectangleById(this.readerContinuousV2ItemId(index));
        if (rect.size.width <= 0 || rect.size.height <= 0) continue;
        const x = pointX - rect.windowOffset.x;
        const y = pointY - rect.windowOffset.y;
        if (x >= 0 && x <= rect.size.width && y >= 0 && y <= rect.size.height) return [index, x, y];
      } catch (_) {
      }
    }
    return [];
  }

  readerContinuousV2ActionAtPoint(globalX: number, globalY: number): string {
    const located = this.readerContinuousV2Locate(globalX, globalY);
    if (located.length < 3) return '';
    const layout = this.readerContinuousV2Layout(located[0], this.contentPages[located[0]] || '');
    if (!layout) return '';
    const action = layout.actionAt(located[1], located[2], this.toMeasurePx(this.readerSourceActionHitSlopX),
      this.toMeasurePx(this.readerSourceActionHitSlopY));
    return action ? action.marker : '';
  }

  selectReaderContinuousV2TextAtPoint(globalX: number, globalY: number, serial: number, attempt: number): void {
    if (serial !== this.readerTextSelectionSerial) return;
    const located = this.readerContinuousV2Locate(globalX, globalY);
    const layout = located.length >= 3 ?
      this.readerContinuousV2Layout(located[0], this.contentPages[located[0]] || '') : null;
    if (layout && layout.selectionText) {
      const result = this.beginReaderV2NativeSelection(layout, located[0], READER_V2_CONTINUOUS_ROLE,
        located[1], located[2], serial);
      if (result === 1) return;
      if (result === 0 && attempt >= 3) {
        this.setReaderTextSelectionActive(false);
        return;
      }
    }
    this.retryReaderTextSelection(serial, attempt,
      (nextAttempt: number): void => this.selectReaderContinuousV2TextAtPoint(
        globalX, globalY, serial, nextAttempt));
  }

  readerV2TtsSourceOffset(speechOffset: number): number {
    return this.readerV2ActiveSpeechText ? this.readerV2ActiveSpeechText.sourceOffsetAt(speechOffset) :
      this.ttsTextStartOffset + speechOffset;
  }

  refreshReaderV2TtsOverlay(): void {
    // The declarative overlay is republished by readerV2TtsPaintVersion. Do not rely on a retained
    // RenderNode invalidation here: on affected devices it only becomes visible after turning a page.
  }

  async exitReaderPage(): Promise<void> {
    if (this.readerExitProgressSaved) {
      return;
    }
    // Freeze scroll-derived progress before awaiting the database write. During the route transition List can emit
    // a shorter visible range (notably 3..3 for a short final item that was pinned below 3..4), which otherwise
    // downgrades a saved 5/5 position to 4/5 immediately before the exit checkpoint is serialized.
    this.readerPageVisible = false;
    this.clearReaderPagedProgressSaveTimer();
    this.hideReaderPanels();
    if (this.openedFromShortcut) {
      this.readerExitProgressSaved = true;
      this.saveReadingProgress(true).then(() => {
        return CloudSyncCoordinator.syncAutomatically(
          getContext(this), CloudSyncCoordinator.TRIGGER_CHANGE);
      }).catch((error: Error) => {
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
      await this.saveReadingProgress(true);
      this.readerExitProgressSaved = true;
      CloudSyncCoordinator.syncAutomatically(
        getContext(this), CloudSyncCoordinator.TRIGGER_CHANGE).catch((error: Error) => {
        console.warn('离开阅读页同步进度失败:', error);
      });
    } catch (e) {
      console.error('返回阅读页时保存进度失败:', e);
    }
    if (this.openedWithShelfAnimation) {
      AppStorage.setOrCreate('shelfBookCloseAnimationUrl', this.bookUrl);
      AppStorage.setOrCreate('shelfBookCloseAnimationNonce', Date.now());
    }
    router.back();
  }

  getReaderMixedImageMinHeightPx(): number {
    return this.toMeasurePx(120);
  }

  buildReaderPaginationCacheKey(chapterIndex: number, source: string): string {
    // V2 uses a deterministic footer guard rather than the asynchronously measured line box, so the first footer
    // area callback cannot invalidate an otherwise identical native Paragraph session during book open.
    const footerHeight = this.shouldUseReaderLayoutV2(source) ?
      Math.round(this.getReaderV2BottomGuard() * 100) / 100 :
      Math.round(this.getReaderBottomInfoBarHeight() * 100) / 100;
    const layoutMode = this.isReaderComicModeActive() ? 'comic' :
      (this.isReaderNovelContinuousScrollModeActive() ? 'continuous' : 'paged');
    const headerReserve = Math.round(this.getReaderHeaderContentReserve() * 100) / 100;
    return `reader_page_v84_${layoutMode}_${chapterIndex}_${this.pageViewWidth}_` +
      `${this.getReaderPaginationViewportHeight()}_` +
      `${headerReserve}_${footerHeight}_` +
      `${this.readerFooterEnabled ? 0 : Math.round(this.getReaderNavigationBottomReserve() * 100) / 100}_` +
      `${this.readerHeaderEnabled}_${this.readerFooterEnabled}_` +
      `${this.readerExtendToStatusBar}_${this.isLandscapeDoublePageActive()}_${this.readerTypographyCacheIdentity()}_` +
      `${this.readerParagraphCommentPaginationIdentity()}_` +
      `${source.length}_${this.hashText(source)}`;
  }

  // 预排版去重键用的视口部分。完成的预排版会一直占着去重标记，键里不带视口的话，进出小窗/分屏后
  // 相邻章节永远不会按新视口重新预排，跨章时只能现排，页数从 1/1 开始一路跳。
  readerPaginationViewportIdentity(): string {
    return `${this.pageViewWidth}_${this.getReaderPaginationViewportHeight()}_${this.isLandscapeDoublePageActive()}`;
  }

  readerTypographyCacheIdentity(): string {
    const regexIdentity = `${this.readerRegexFontEnabled}_${this.readerRegexFontRulesRaw}_` +
      `${this.readerRegexFontPattern}_${this.readerRegexFontMode}_${this.readerRegexFontFamily}_` +
      `${this.readerRegexFontSize}_${this.readerRegexShadowColor}_${this.themeRevision}_` +
      `${this.themeRegexEmphasisMode()}_${this.themeRegexBubbleStyleId()}_reader_action_layout_v7`;
    return `${this.readerFontSize}_${this.readerFontWeight}_${this.readerLetterSpacing}_${this.readerTextAlign}_${this.readerLineHeight}_${this.readerParagraphSpacing}_` +
      `${this.readerParagraphIndent}_${this.readerCommentBubbleSize}_` +
      `${this.readerMarginLeft}_${this.readerMarginRight}_${this.readerMarginTop}_${this.readerMarginBottom}_` +
      `${this.readerBodyFontMode}_${this.readerBodyFontFamily}_${this.getBodyReaderFontFamily()}_` +
      `${this.readerTitleFontSize}_${this.readerTitleFontMode}_${this.readerTitleFontFamily}_` +
      `${this.getTitleReaderFontFamily()}_${this.getReaderFontFamily()}_${this.systemFontRevision}_` +
      `${this.hashText(regexIdentity)}`;
  }

  getCachedReaderPagination(chapterIndex: number, source: string): ReaderPaginationResult | null {
    const key = this.buildReaderPaginationCacheKey(chapterIndex, source);
    return this.readerPaginationCache.get(key) || null;
  }

  getOrCreateReaderPagination(chapterIndex: number, source: string,
    preferredInitialPageCount: number = 0): ReaderPaginationResult {
    const key = this.buildReaderPaginationCacheKey(chapterIndex, source);
    let result = this.readerPaginationCache.get(key);
    const defaultDesiredPageCount = chapterIndex === this.currentChapterIndex ?
      Math.max(READER_CURRENT_PAGINATION_AHEAD_PAGE_COUNT,
        (this.pendingRestorePageIndex >= 0 ? this.pendingRestorePageIndex : this.currentPageIndex) +
        READER_CURRENT_PAGINATION_AHEAD_PAGE_COUNT) : READER_ADJACENT_PAGINATION_PREVIEW_PAGE_COUNT;
    const desiredPageCount = preferredInitialPageCount > 0 ?
      Math.max(1, Math.round(preferredInitialPageCount)) : defaultDesiredPageCount;
    if (!result) {
      result = this.createIncrementalReaderPagination(source, chapterIndex, desiredPageCount);
      this.readerPaginationCache.set(key, result);
      while (this.readerPaginationCache.size > 3) {
        // Never evict the entry the active completion chain is still appending to: the chain's
        // liveness guard compares against this exact instance and would silently die mid-chapter,
        // leaving the reader stuck on the restore overlay.
        let evictableKey: string | undefined = undefined;
        for (const cacheKey of this.readerPaginationCache.keys()) {
          if (cacheKey !== key) {
            evictableKey = cacheKey;
            break;
          }
        }
        if (!evictableKey) break;
        this.readerPaginationCache.delete(evictableKey);
      }
    } else if (!result.complete && result.pages.length < desiredPageCount) {
      const missingPageCount = desiredPageCount - result.pages.length;
      // A cached deep restore must remain cooperative too. Otherwise reopening while a partial session is cached
      // reintroduces the same synchronous native-Paragraph burst avoided by the initial creation path.
      const synchronousPageCount = result.v2Session ? Math.min(1, missingPageCount) : missingPageCount;
      this.appendReaderPaginationBatch(result, chapterIndex, synchronousPageCount);
    }
    if (chapterIndex === this.currentChapterIndex) {
      this.updateReaderComicPaginationProgress(chapterIndex, result);
    }
    if (chapterIndex === this.currentChapterIndex && !result.complete) {
      this.scheduleReaderPaginationCompletion(chapterIndex, key, result);
    } else if (result.complete) {
      this.persistReaderPagination(chapterIndex, key, result);
    }
    return result;
  }

  createIncrementalReaderPagination(source: string, chapterIndex: number,
    initialPageCount: number): ReaderPaginationResult {
    const text = source || '';
    if (text && this.shouldUseReaderLayoutV2(text)) {
      return this.createIncrementalReaderV2Pagination(text, chapterIndex, initialPageCount);
    }
    return this.createChunkReaderPagination(text);
  }

  appendReaderPaginationBatch(result: ReaderPaginationResult, chapterIndex: number, maxPages: number,
    timeBudgetMs: number = 8): void {
    if (result.complete || maxPages <= 0) return;
    const batchStartedAt = Date.now();
    const text = result.source || '';
    if (!text || this.pageViewWidth <= 0 || this.pageViewHeight <= 0) {
      result.complete = true;
      result.cursor = text.length;
      return;
    }
    if (result.v2Session) {
      // One native Paragraph page can already consume most of a frame budget on a large tablet. In particular,
      // the previous-chapter preloader requests several pages at once; honouring that count in one callback was
      // enough to trigger THREAD_BLOCK_3S. Every V2 callback produces at most one page and yields before the next.
      this.appendReaderV2PaginationBatch(result, chapterIndex, Math.min(1, maxPages));
      return;
    }
    // Chunked list results (comics, continuous scrolling) are produced whole.
    result.cursor = text.length;
    result.complete = true;
  }

  scheduleReaderPaginationCompletion(chapterIndex: number, key: string,
    result: ReaderPaginationResult): void {
    const serial = ++this.readerPaginationWorkSerial;
    const imageOnlyPagination = this.isReaderImageOnlySource(result.source);
    const batchDelay = ReaderActionMarker.has(result.source) ?
      READER_INTERACTIVE_PAGINATION_BATCH_DELAY_MS : READER_PAGINATION_BATCH_DELAY_MS;
    let failureCount = 0;
    const runBatch = (): void => {
      if (!this.readerPageVisible || serial !== this.readerPaginationWorkSerial ||
        chapterIndex !== this.currentChapterIndex ||
        this.readerPaginationCache.get(key) !== result) {
        return;
      }
      // The loading overlay owns all input until the saved page/offset is restored. A stale shelf-touch idle
      // window must not throttle that mandatory pagination into one page every few seconds. Interaction-aware
      // yielding still applies after the first real reader page is visible.
      if (this.readerInitialPageReady && this.isReaderPaginationInteractionBusy()) {
        setTimeout(runBatch, READER_PAGINATION_BUSY_RETRY_DELAY_MS);
        return;
      }
      try {
        const batchStartedAt = Date.now();
        if (!this.readerInitialPageReady) {
          // A saved page/offset is still waiting: measure in bursts instead of the idle cadence, so deep
          // restores finish within a few frames instead of one page every 64 ms. The batch helper yields
          // through its time budget; stop as soon as the saved page exists (or the burst budget is spent).
          const burstBudgetMs = 160;
          while (!result.complete && Date.now() - batchStartedAt < burstBudgetMs &&
            (this.pendingRestorePageIndex < 0 || result.pages.length <= this.pendingRestorePageIndex)) {
            const beforePageCount = result.pages.length;
            this.appendReaderPaginationBatch(result, chapterIndex, imageOnlyPagination ? 8 : 4, 24);
            if (result.pages.length <= beforePageCount) break;
          }
          // Publish cooperative snapshots only while a saved page/offset is waiting to become available.
          // Normal background pagination remains private and is published once at completion.
          this.publishCurrentReaderPagination(result);
        } else {
          // Text measurement and paragraph layout both run on the UI thread. Keep each idle batch small and do not
          // publish every intermediate array: repeated @State replacements rebuild the reader while a page is moving.
          // A pure comic page is already delimited by an image marker and requires no text measurement. Parse a small
          // group per idle slice so large comics finish promptly without turning the whole chapter into one UI task.
          this.appendReaderPaginationBatch(result, chapterIndex, imageOnlyPagination ? 8 : 1);
          // 重新排版后不必等整章排完：阅读位置所在的页和它的下一页（双页时的右页）一排出来就发布，
          // 让正文尽快从纯文本兜底换回正式排版。其余页面照旧在后台排完后一次发布。
          if (!result.complete && this.readerRelayoutRepaintPending && this.readerTypographyRestoreOffset >= 0 &&
            result.ends.length >= 2 &&
            this.readerTypographyRestoreOffset < result.ends[result.ends.length - 2]) {
            this.publishCurrentReaderPagination(result);
          }
        }
        const batchElapsedMs = Math.max(0, Date.now() - batchStartedAt);
        failureCount = 0;
        if (result.complete) {
          this.publishCurrentReaderPagination(result);
          this.persistReaderPagination(chapterIndex, key, result);
          this.updateReaderComicPaginationProgress(chapterIndex, result);
          if (!this.isPageTurning && this.pageTurnQueue.hasPendingForward()) {
            // 章末等排版的那次向后翻页（见 runPageTurnAnimation）。
            setTimeout(() => this.runQueuedPageTurnLater(), 0);
          }
          return;
        }
        this.updateReaderComicPaginationProgress(chapterIndex, result);
        const stillRestoring = !this.readerInitialPageReady;
        const adaptiveDelay = stillRestoring ? 16 :
          (batchElapsedMs >= CooperativeScheduler.SLOW_OPERATION_MS ?
            Math.min(240, Math.max(batchDelay, batchElapsedMs * 2)) : batchDelay);
        setTimeout(runBatch, adaptiveDelay);
      } catch (error) {
        // A native measurement failure must not kill the self-scheduling chain: without a catch the
        // exception leaves the reader on the "restoring progress" overlay forever. Retry a few times,
        // then land on the deepest published page and release the restore flags.
        console.error(`[ReaderPagination] 分页批次异常 chapter=${chapterIndex} pages=${result.pages.length} ` +
          `cursor=${result.cursor}:`, error);
        failureCount++;
        if (failureCount <= 3) {
          setTimeout(runBatch, batchDelay * failureCount * 4);
          return;
        }
        this.recoverReaderPaginationStall(chapterIndex, key, result, serial);
      }
    };
    setTimeout(runBatch, batchDelay);
    this.armReaderRestoreWatchdog();
  }

  // Bounded watchdog for every path that leaves pendingRestorePageIndex / typography restore pending:
  // if no pagination chain manages to resolve them (hung DB await, dead timer chain, lost race), land
  // on the deepest page published so far instead of freezing input and progress saving forever.
  armReaderRestoreWatchdog(timeoutMs: number = 15000): void {
    if (this.readerRestoreWatchdogRunning) {
      return;
    }
    if (this.pendingRestorePageIndex < 0 && this.readerTypographyRestoreOffset < 0) {
      return;
    }
    this.readerRestoreWatchdogRunning = true;
    this.runReaderRestoreWatchdog(timeoutMs).finally(() => {
      this.readerRestoreWatchdogRunning = false;
    });
  }

  async runReaderRestoreWatchdog(timeoutMs: number): Promise<void> {
    const deadline = Date.now() + Math.max(1000, timeoutMs);
    // A restore paused while the page is hidden must not be clobbered; wait for visibility first.
    while (Date.now() < deadline && !this.readerPageVisible) {
      await sleepMs(200);
    }
    while (Date.now() < deadline && this.readerPageVisible &&
      (this.pendingRestorePageIndex >= 0 || this.readerTypographyRestoreOffset >= 0)) {
      await sleepMs(100);
    }
    if (this.pendingRestorePageIndex < 0 && this.readerTypographyRestoreOffset < 0) {
      return;
    }
    if (!this.readerPageVisible) {
      // Still hidden: the pagination chain resumes on its own once the page shows again.
      return;
    }
    console.warn(`[ReaderPagination] 恢复进度看门狗兜底落地 chapter=${this.currentChapterIndex} ` +
      `pages=${this.contentPages.length} pending=${this.pendingRestorePageIndex}`);
    if (this.contentPages.length === 0) {
      // Nothing has been published yet: show the raw chapter text as a single readable page
      // instead of settling on a permanently blank screen.
      const fallback = this.content || this.pagedContentText;
      if (fallback) {
        this.pagedContentText = fallback;
        this.contentPages = [fallback];
        this.contentPageStarts = [0];
        this.contentPageEnds = [fallback.length];
        this.setCurrentPageText(fallback);
      }
    }
    this.currentPageIndex = Math.max(0, this.contentPages.length - 1);
    this.pendingRestorePageIndex = -1;
    this.readerTypographyRestoreOffset = -1;
    this.readerInitialPageReady = true;
    this.finishReaderInitialOpening();
  }

  // Last-resort settlement for a pagination chain that kept throwing: publish whatever pages exist and
  // release every restore flag so the reader never stays on the loading overlay.
  recoverReaderPaginationStall(chapterIndex: number, key: string, result: ReaderPaginationResult,
    serial: number): void {
    if (serial !== this.readerPaginationWorkSerial || chapterIndex !== this.currentChapterIndex ||
      this.readerPaginationCache.get(key) !== result) {
      return;
    }
    if (result.pages.length > 0) {
      this.publishCurrentReaderPagination(result);
    }
    if (this.contentPages.length === 0) {
      // Pagination kept failing before a single page was produced: fall back to one readable page
      // with the raw chapter text instead of leaving the reader on a blank screen.
      this.applyReaderPaginationResult(result, this.content || result.source);
    }
    if (this.pendingRestorePageIndex >= 0 || this.readerTypographyRestoreOffset >= 0) {
      this.currentPageIndex = Math.max(0, this.contentPages.length - 1);
      this.pendingRestorePageIndex = -1;
      this.readerTypographyRestoreOffset = -1;
    }
    this.readerInitialPageReady = true;
    this.finishReaderInitialOpening();
  }

  isReaderPaginationInteractionBusy(): boolean {
    const deferredPreviousTurn = this.pageTurnQueue.hasPendingBackward() &&
      this.currentPageIndex <= 0 && !this.isPreviousChapterTurnReady();
    // 章末等本章排完的向后翻页同理：排队中的翻页正是在等这条补排链，不能反过来把它卡住。
    const deferredNextTurn = this.pageTurnQueue.hasPendingForward() && this.isForwardChapterTurnWaitingForPagination();
    const queuedTurnBusy = !deferredPreviousTurn && !deferredNextTurn && this.pendingRestorePageIndex < 0 &&
      this.pageTurnQueue.hasPending();
    return this.showReaderCommentPanel || this.isPageTurning || this.readerPanActive || this.readerTouchActive ||
      this.readerComicPanMoved || this.readerComicBoundaryDirection !== 0 || this.readerComicChapterSwitching ||
      this.pageSlideDirection !== 0 || this.pageTurnAnimating || queuedTurnBusy ||
      Date.now() < this.readerPaginationInteractionIdleUntil;
  }

  deferReaderPaginationForInteraction(idleDelayMs: number = 420): void {
    this.readerPaginationInteractionIdleUntil = Math.max(this.readerPaginationInteractionIdleUntil,
      Date.now() + Math.max(0, idleDelayMs));
  }

  publishCurrentReaderPagination(result: ReaderPaginationResult): void {
    if (this.currentChapterIndex < 0 || this.pagedContentText !== result.source) return;
    const keepVisibleReaderReady = this.readerInitialPageReady &&
      this.displayPageChapterIndex === this.currentChapterIndex && this.contentPages.length > 0;
    const pendingRestore = this.pendingRestorePageIndex;
    const secondaryPageIndex = this.currentPageIndex + 1;
    const shouldRefreshCompletedSpread = this.isLandscapeDoublePageActive() &&
      secondaryPageIndex >= this.contentPages.length && secondaryPageIndex < result.pages.length;
    this.contentPages = [...result.pages];
    this.contentPageStarts = [...result.starts];
    this.contentPageEnds = [...result.ends];
    this.restorePendingPageIndex(result.complete === true);
    if (pendingRestore >= 0 && this.pendingRestorePageIndex < 0) {
      this.setCurrentPageText(this.contentPages[this.currentPageIndex] || '');
    } else if (shouldRefreshCompletedSpread) {
      // The current page surface is keyed by its render version. Merely replacing contentPages updates
      // counters, but a retained ForEach surface can keep the formerly empty right page until a turn.
      this.refreshReaderTextRender();
    }
    const restoredTypographyPosition = this.restoreReaderTypographyOffsetIfAvailable(result.complete === true);
    this.readerInitialPageReady = keepVisibleReaderReady ||
      (this.pendingRestorePageIndex < 0 && this.readerTypographyRestoreOffset < 0);
    if (this.readerInitialPageReady) this.finishReaderInitialOpening();
    const restoredPendingPosition = pendingRestore >= 0 && this.pendingRestorePageIndex < 0;
    if (this.isReaderContinuousScrollSurfaceActive()) {
      if (restoredPendingPosition || restoredTypographyPosition) this.readerComicScrollRestoring = true;
      this.syncReaderComicPageDataSource();
      if (restoredPendingPosition || restoredTypographyPosition) this.scheduleReaderComicScrollRestore();
    }
    this.scheduleTtsFocusSyncAfterPagination();
    if (this.readerRelayoutRepaintPending && (result.complete || restoredTypographyPosition)) {
      this.readerRelayoutRepaintPending = false;
      // 页面宿主在重新排版的那一刻就按新版式重新挂载了，但新的分页会话当时往往还没排到当前页，
      // 挂上去的是纯文本兜底：只按旧分页的文字量铺开（字号变小时只占半屏），也没有强调气泡。
      // "有没有原生页面"这个判断读的是普通缓存，不会随缓存填充自动重算；宿主的 key 只含章节、页码
      // 和代数，页码没变就一直停在兜底上，直到下一次翻页。当前页排出来后换一个代数，重新挂载一次。
      // 翻页动画进行中不处理，动画落定时页码变化本来就会重新挂载。
      if (!this.isReaderContinuousScrollSurfaceActive() && !this.isPageTurning && !this.pageTurnAnimating &&
        this.pageSlideDirection === 0) {
        this.readerV2SurfaceGeneration++;
        this.forceCurrentReaderPageRender();
        this.refreshCurrentReaderV2RetainedPages(true);
      }
    }
    if (restoredPendingPosition && !this.isPageTurning && this.pageTurnQueue.pendingCount() > 0) {
      // A queued physical tap may have arrived while the previous chapter's authoritative tail was rebuilding.
      // Resume it only after the pending index has resolved, so one tap remains one page turn.
      setTimeout(() => this.runQueuedPageTurnLater(), 0);
    }
  }

  persistReaderPagination(chapterIndex: number, key: string, result: ReaderPaginationResult): void {
    if (!result.complete || !this.bookUrl || result.starts.length === 0 ||
      result.starts.length !== result.ends.length) {
      return;
    }
    AppDatabase.getInstance().saveReaderPaginationCache(this.bookUrl, chapterIndex, key,
      result.starts, result.ends).catch((error: Error) => {
      console.warn('保存阅读分页缓存失败:', error);
    });
  }

  applyPreparedReaderPagination(content: string, chapterIndex: number, createIfMissing: boolean): boolean {
    if (!content || !this.hasPagedReaderArea()) return false;
    const source = this.buildPagedSourceText(chapterIndex, content);
    const cached = this.getCachedReaderPagination(chapterIndex, source);
    if (!cached && !createIfMissing) return false;
    // Crossing a chapter only needs its first spread immediately. Measuring eight pages or waiting for the
    // persisted cache before publishing page one makes the completed swipe appear frozen on fast input.
    const result = this.getOrCreateReaderPagination(chapterIndex, source,
      createIfMissing ? READER_ADJACENT_PAGINATION_PREVIEW_PAGE_COUNT : 0);
    this.applyReaderPaginationResult(result, content);
    return true;
  }

  preloadNextChapterPaginationLater(delayMs: number = 520): void {
    if (!this.readerPageVisible || !this.readerPreloadEnabled || !this.hasPagedReaderArea() ||
      this.currentChapterIndex >= this.chapters.length - 1) {
      return;
    }
    const sourceChapterIndex = this.currentChapterIndex;
    const targetChapterIndex = sourceChapterIndex + 1;
    const sessionBookUrl = this.book?.bookUrl || this.bookUrl;
    const activeKey = `${sessionBookUrl}_${sourceChapterIndex}_${targetChapterIndex}_` +
      `${this.readerPaginationViewportIdentity()}_` +
      `${this.readerTypographyCacheIdentity()}_${this.readerParagraphCommentPaginationIdentity()}`;
    if (this.adjacentPaginationPreloadActiveSerial === this.adjacentPaginationPreloadSerial &&
      this.adjacentPaginationPreloadActiveKey === activeKey) return;
    const serial = ++this.adjacentPaginationPreloadSerial;
    this.adjacentPaginationPreloadActiveSerial = serial;
    this.adjacentPaginationPreloadActiveKey = activeKey;
    setTimeout(() => {
      if (!this.readerPageVisible || serial !== this.adjacentPaginationPreloadSerial ||
        !this.isCurrentReaderEngineBook(sessionBookUrl) ||
        (this.currentChapterIndex !== sourceChapterIndex && this.currentChapterIndex !== targetChapterIndex)) {
        return;
      }
      this.readerEngine().peekContent(targetChapterIndex)
        .then(async (body: string): Promise<void> => {
          if (!body || !this.readerPageVisible || serial !== this.adjacentPaginationPreloadSerial ||
            !this.isCurrentReaderEngineBook(sessionBookUrl) ||
            (this.currentChapterIndex !== sourceChapterIndex && this.currentChapterIndex !== targetChapterIndex)) {
            if (serial === this.adjacentPaginationPreloadSerial && !body) {
              this.adjacentPaginationPreloadActiveSerial = -1;
            }
            return;
          }
          const processed = await this.prepareReaderContentRules(body, targetChapterIndex);
          if (!this.readerPageVisible || serial !== this.adjacentPaginationPreloadSerial ||
            !this.isCurrentReaderEngineBook(sessionBookUrl) ||
            (this.currentChapterIndex !== sourceChapterIndex && this.currentChapterIndex !== targetChapterIndex)) {
            return;
          }
          const source = this.buildPagedSourceText(targetChapterIndex, processed);
          const key = this.buildReaderPaginationCacheKey(targetChapterIndex, source);
          const result = this.getCachedReaderPagination(targetChapterIndex, source) ||
            this.getOrCreateReaderPagination(targetChapterIndex, source);
          this.scheduleNextChapterPaginationCompletion(sourceChapterIndex, targetChapterIndex, key, result, serial);
        })
        .catch((err: Error) => {
          if (serial === this.adjacentPaginationPreloadSerial) {
            this.adjacentPaginationPreloadActiveSerial = -1;
          }
          console.error('预排版下一章失败:', err);
        });
    }, Math.max(0, delayMs));
  }

  scheduleNextChapterPaginationCompletion(sourceChapterIndex: number, targetChapterIndex: number, key: string,
    result: ReaderPaginationResult, serial: number): void {
    if (result.complete) {
      this.persistReaderPagination(targetChapterIndex, key, result);
      return;
    }
    // A cross-chapter turn must not expose the small provisional spread and then replace it with the
    // completed V2 page set after the animation. That changes the visible total from e.g. 2 to 6 and
    // rebuilds the reader immediately after landing, which looks like a vertical layout shake. Finish
    // the retained next-chapter session cooperatively while the current chapter is still visible.
    // Interaction-busy checks below keep native Paragraph work away from an active drag/turn chain.
    const batchDelay = ReaderActionMarker.has(result.source) ?
      READER_INTERACTIVE_PAGINATION_BATCH_DELAY_MS : READER_PAGINATION_BATCH_DELAY_MS;
    const runBatch = (): void => {
      if (!this.readerPageVisible || serial !== this.adjacentPaginationPreloadSerial ||
        this.currentChapterIndex !== sourceChapterIndex ||
        this.readerPaginationCache.get(key) !== result) {
        // Same hygiene as the previous-chapter session: a silently aborted run must not keep the
        // active-session dedupe claiming this preload is still running.
        if (serial === this.adjacentPaginationPreloadSerial &&
          this.adjacentPaginationPreloadActiveSerial === serial) {
          this.adjacentPaginationPreloadActiveSerial = -1;
        }
        return;
      }
      if (this.isReaderPaginationInteractionBusy()) {
        setTimeout(runBatch, READER_PAGINATION_BUSY_RETRY_DELAY_MS);
        return;
      }
      try {
        const startedAt = Date.now();
        this.appendReaderPaginationBatch(result, targetChapterIndex, 1);
        if (result.complete) {
          this.persistReaderPagination(targetChapterIndex, key, result);
          console.info(`[ReaderPreload] next chapter=${targetChapterIndex} pages=${result.pages.length} ` +
            `lastBatch=${Date.now() - startedAt}ms`);
          return;
        }
        const elapsedMs = Math.max(0, Date.now() - startedAt);
        const nextDelay = elapsedMs >= CooperativeScheduler.SLOW_OPERATION_MS ?
          Math.min(240, Math.max(batchDelay, elapsedMs * 2)) : batchDelay;
        setTimeout(runBatch, nextDelay);
      } catch (error) {
        // Same protection as the previous-chapter session: a throwing batch must release the active-session
        // marker, otherwise the dedupe treats the dead session as alive and the next chapter is never prepared.
        console.error(`[ReaderPreload] 下一章预排版批次异常 chapter=${targetChapterIndex} ` +
          `pages=${result.pages.length} cursor=${result.cursor}:`, error);
        if (serial === this.adjacentPaginationPreloadSerial &&
          this.adjacentPaginationPreloadActiveSerial === serial) {
          this.adjacentPaginationPreloadActiveSerial = -1;
        }
      }
    };
    setTimeout(runBatch, 0);
  }

  preloadPreviousChapterPaginationLater(delayMs: number = 760): void {
    if (!this.readerPageVisible || !this.hasPagedReaderArea() || this.currentChapterIndex <= 0) return;
    const sourceChapterIndex = this.currentChapterIndex;
    const targetChapterIndex = sourceChapterIndex - 1;
    // "Preload" off disables speculative network requests, but a chapter the user just left is already cached.
    // Its tail pagination is required for a correct instant backward turn and is safe to prepare locally.
    if (!this.readerPreloadEnabled && !this.readerEngine().hasCachedContent(targetChapterIndex)) return;
    const sessionBookUrl = this.book?.bookUrl || this.bookUrl;
    const activeKey = `${sessionBookUrl}_${sourceChapterIndex}_${targetChapterIndex}_` +
      `${this.readerPaginationViewportIdentity()}_` +
      `${this.readerTypographyCacheIdentity()}_${this.readerParagraphCommentPaginationIdentity()}`;
    // Page 2/3 hooks can request the same previous chapter repeatedly. Restarting the retained V2 session on
    // every local turn prevented it from ever reaching the real last page before the user swiped backwards.
    if (this.previousPaginationPreloadActiveSerial === this.previousPaginationPreloadSerial &&
      this.previousPaginationPreloadActiveKey === activeKey) return;
    const serial = ++this.previousPaginationPreloadSerial;
    this.previousPaginationPreloadActiveSerial = serial;
    this.previousPaginationPreloadActiveKey = activeKey;
    setTimeout(() => {
      if (!this.readerPageVisible || serial !== this.previousPaginationPreloadSerial ||
        !this.isCurrentReaderEngineBook(sessionBookUrl) ||
        this.currentChapterIndex !== sourceChapterIndex) return;
      this.readerEngine().peekContent(targetChapterIndex)
        .then(async (body: string): Promise<void> => {
          if (!body || !this.readerPageVisible || serial !== this.previousPaginationPreloadSerial ||
            !this.isCurrentReaderEngineBook(sessionBookUrl) ||
            this.currentChapterIndex !== sourceChapterIndex) {
            if (serial === this.previousPaginationPreloadSerial && !body) {
              this.previousPaginationPreloadActiveSerial = -1;
            }
            return;
          }
          const processed = await this.prepareReaderContentRules(body, targetChapterIndex);
          if (!this.readerPageVisible || serial !== this.previousPaginationPreloadSerial ||
            !this.isCurrentReaderEngineBook(sessionBookUrl) ||
            this.currentChapterIndex !== sourceChapterIndex) {
            return;
          }
          const source = this.buildPagedSourceText(targetChapterIndex, processed);
          const key = this.buildReaderPaginationCacheKey(targetChapterIndex, source);
          const result = this.getCachedReaderPagination(targetChapterIndex, source) ||
            this.getOrCreateReaderPagination(targetChapterIndex, source);
          this.schedulePreviousChapterPaginationCompletion(sourceChapterIndex, targetChapterIndex, key, result,
            serial);
        })
        .catch((error: Error) => {
          if (serial === this.previousPaginationPreloadSerial) {
            this.previousPaginationPreloadActiveSerial = -1;
          }
          console.error('预排版上一章失败:', error);
        });
    }, Math.max(0, delayMs));
  }

  schedulePreviousChapterPaginationCompletion(sourceChapterIndex: number, targetChapterIndex: number, key: string,
    result: ReaderPaginationResult, serial: number): void {
    if (result.complete) {
      this.persistReaderPagination(targetChapterIndex, key, result);
      this.resumeDeferredPreviousChapterTurn(sourceChapterIndex);
      return;
    }
    // Going backwards must land on the real last page. V2 used to stop here after producing only
    // the two-page turn preview, so the first backward chapter turn had to finish the whole chapter
    // after the gesture and exposed the "restore progress" overlay. Complete the retained native
    // pagination cooperatively while the current chapter is being read; a small two-page idle slice keeps
    // the UI responsive and makes the previous tail immediately available when the user turns back.
    const batchDelay = ReaderActionMarker.has(result.source) ?
      READER_INTERACTIVE_PAGINATION_BATCH_DELAY_MS : READER_PAGINATION_BATCH_DELAY_MS;
    const runBatch = (): void => {
      if (!this.readerPageVisible || serial !== this.previousPaginationPreloadSerial ||
        this.currentChapterIndex !== sourceChapterIndex ||
        this.readerPaginationCache.get(key) !== result) {
        // Losing the retained cache entry (LRU eviction, a global pagination-cache clear, a chapter jump)
        // kills this session. Clear the active-session marker too, otherwise the dedupe in
        // preloadPreviousChapterPaginationLater keeps treating the dead session as alive and every later
        // swipe becomes a silent no-op with the user's turn stuck in the queue forever.
        if (serial === this.previousPaginationPreloadSerial &&
          this.previousPaginationPreloadActiveSerial === serial) {
          this.previousPaginationPreloadActiveSerial = -1;
        }
        return;
      }
      if (this.isReaderPaginationInteractionBusy()) {
        setTimeout(runBatch, READER_PAGINATION_BUSY_RETRY_DELAY_MS);
        return;
      }
      try {
        const startedAt = Date.now();
        // appendReaderPaginationBatch limits Reader V2 to one native Paragraph page per callback. The larger count
        // remains useful for the legacy text measurer, whose explicit time budget yields inside the loop.
        this.appendReaderPaginationBatch(result, targetChapterIndex, 3, 10);
        if (result.complete) {
          this.persistReaderPagination(targetChapterIndex, key, result);
          console.info(`[ReaderPreload] previous chapter=${targetChapterIndex} pages=${result.pages.length} ` +
            `lastBatch=${Date.now() - startedAt}ms`);
          // A slow drag may already be exposing the temporary incoming leaf. Replace it with the
          // confirmed tail before the curl snapshot is captured/released; never leave the provisional
          // first spread on the back of a backward cross-chapter turn.
          if (this.pageSlideDirection < 0 && this.pageTurnCrossChapterHandoff &&
            this.pageTurnIncomingChapterIndex === targetChapterIndex) {
            const preview = this.buildAdjacentPageTurnPreview(-1, targetChapterIndex, result.source);
            if (preview.text) this.applyPageTurnPreview(preview);
          }
          this.resumeDeferredPreviousChapterTurn(sourceChapterIndex);
          return;
        }
        const elapsedMs = Math.max(0, Date.now() - startedAt);
        const nextDelay = elapsedMs >= CooperativeScheduler.SLOW_OPERATION_MS ?
          Math.min(160, Math.max(32, elapsedMs * 2)) : Math.min(batchDelay, 24);
        setTimeout(runBatch, nextDelay);
      } catch (error) {
        // Same protection as the main completion chain: an unhandled batch exception would kill the
        // retained session and strand the previous-chapter tail (and the deferred turn) forever.
        console.error(`[ReaderPreload] 上一章预排版批次异常 chapter=${targetChapterIndex} ` +
          `pages=${result.pages.length} cursor=${result.cursor}:`, error);
        if (serial === this.previousPaginationPreloadSerial &&
          this.previousPaginationPreloadActiveSerial === serial) {
          this.previousPaginationPreloadActiveSerial = -1;
        }
      }
    };
    setTimeout(runBatch, 0);
  }

  paginateContent(sourceContent?: string, chapterIndex: number = this.currentChapterIndex) {
    const content = sourceContent !== undefined ? sourceContent : this.content;
    if (!content || !content.trim()) {
      // Never leave the reader on zero pages: a blank screen with a footer. Show an explicit page
      // so pending restores can settle and the user gets an actionable state.
      this.clearReaderComicPaginationProgress();
      const emptyChapterIndex = this.clampChapterIndex(chapterIndex);
      const emptyTitle = this.getChapterTitle(emptyChapterIndex).trim();
      const emptyPage = emptyTitle ? `${emptyTitle}\n\n本章暂无正文内容。` : '本章暂无正文内容。';
      this.pagedContentText = emptyPage;
      this.contentPages = [emptyPage];
      this.contentPageStarts = [0];
      this.contentPageEnds = [emptyPage.length];
      this.setCurrentPageText(emptyPage);
      this.restorePendingPageIndex(true);
      this.readerInitialPageReady = this.pendingRestorePageIndex < 0 && this.readerTypographyRestoreOffset < 0;
      if (this.readerInitialPageReady) this.finishReaderInitialOpening();
      return;
    }

    if (!this.hasPagedReaderArea()) {
      this.clearReaderComicPaginationProgress();
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
    this.applyReaderPaginationResult(result, content);
    // 同步分页完成时会立即复位；只有恢复标志仍未落地（持久分页缓存 await、竞态）时才需要看门狗。
    this.armReaderRestoreWatchdog();
  }

  applyReaderPaginationResult(result: ReaderPaginationResult, fallbackContent: string): void {
    const initialPageWasReady = this.readerInitialPageReady;
    const keepVisibleReaderReady = initialPageWasReady &&
      this.displayPageChapterIndex === this.currentChapterIndex && this.contentPages.length > 0;
    if (keepVisibleReaderReady && !result.complete && this.pagedContentText === result.source) {
      // Do not replace a completed on-screen page set with the first one/two pages of a new incremental session.
      // That transient snapshot made a foreground resume visibly jump from e.g. 3-4/8 to 1-2/2 before returning.
      // scheduleReaderPaginationCompletion() still owns the private result and publishes it once complete.
      // 这期间新会话可能还没有当前页，可见页面挂载的是纯文本兜底，见 publishCurrentReaderPagination。
      this.readerRelayoutRepaintPending = true;
      return;
    }
    const pages: string[] = result.pages.length > 0 ? result.pages : [fallbackContent];
    const hasAuthoritativePageBoundary = result.pages.length > 0 && result.starts.length > 0 &&
      result.ends.length > 0;
    if (!result.complete && this.pendingRestorePageIndex < 0 && this.currentPageIndex >= pages.length) {
      // Incremental pagination (especially chapters containing paragraph-comment markers) may initially expose
      // only page one. Preserve the authoritative page until enough boundaries have been rebuilt instead of
      // clamping it to zero and later persisting that temporary fallback as the reading progress.
      this.pendingRestorePageIndex = this.currentPageIndex;
    }
    this.pagedContentText = result.source;
    // Render from a snapshot. Incremental pagination continues in its private cache and is published once complete,
    // so background layout cannot mutate or replace the visible page collection every few milliseconds.
    this.contentPages = [...pages];
    this.contentPageStarts = result.starts.length > 0 ? [...result.starts] : [0];
    this.contentPageEnds = result.ends.length > 0 ? [...result.ends] : [this.pagedContentText.length];
    // The synthetic fallback above is only a hidden render placeholder while V2 has not produced its first
    // measured boundary. Treating its full-source end as a real one-page pagination maps every persisted
    // character offset to page zero and permanently discards a saved deep/last-page position.
    if (hasAuthoritativePageBoundary) this.restorePendingPageIndex(result.complete === true);
    if (this.currentPageIndex >= pages.length) {
      this.currentPageIndex = Math.max(0, pages.length - 1);
    }
    const pageIndex = this.normalizeReaderSpreadPageIndex(
      Math.max(0, Math.min(this.currentPageIndex, Math.max(0, pages.length - 1)))
    );
    this.currentPageIndex = pageIndex;
    this.setCurrentPageText(pages[pageIndex] || '');
    if (hasAuthoritativePageBoundary) {
      this.restoreReaderTypographyOffsetIfAvailable(result.complete === true);
    }
    // Incremental pagination may initially contain only page one. Do not expose that temporary page while
    // the saved position is still waiting for enough page boundaries to be rebuilt.
    this.readerInitialPageReady = keepVisibleReaderReady ||
      (this.pendingRestorePageIndex < 0 && this.readerTypographyRestoreOffset < 0);
    if (this.readerInitialPageReady) this.finishReaderInitialOpening();
    if (!initialPageWasReady && this.readerInitialPageReady && this.bookUrl) {
      ReaderOpenTrace.finish(this.bookUrl);
    }
    this.syncReaderComicPageDataSource();
    this.scheduleReaderComicScrollRestore();
    this.scheduleTtsFocusSyncAfterPagination();
  }

  async turnNext() {
    if (this.isReaderContinuousScrollSurfaceActive()) {
      this.scrollReaderComicByPage(1);
      return;
    }
    await this.runPageTurnAnimation(1, this.readerEffectivePageTurnMode() === 1 ? 'slide' : 'tap');
  }

  async turnPrev() {
    if (this.isReaderContinuousScrollSurfaceActive()) {
      this.scrollReaderComicByPage(-1);
      return;
    }
    await this.runPageTurnAnimation(-1, this.readerEffectivePageTurnMode() === 1 ? 'slide' : 'tap');
  }

  scrollReaderComicByPage(direction: number): void {
    if (this.isReaderComicModeActive()) {
      this.scrollReaderComicByScreen(direction);
      return;
    }
    if (!this.isReaderContinuousScrollSurfaceActive() || this.contentPages.length === 0) return;
    let targetIndex = this.currentPageIndex + (direction > 0 ? 1 : -1);
    if (direction > 0 && targetIndex >= this.contentPages.length) {
      this.ensureCurrentReaderPaginationAhead(targetIndex + 1);
      targetIndex = this.currentPageIndex + 1;
    }
    if (targetIndex >= 0 && targetIndex < this.contentPages.length) {
      this.readerComicScroller.scrollToIndex(this.readerContinuousListIndex(targetIndex), true, ScrollAlign.START);
      return;
    }
    // 相邻章节已经接在列表里：直接滚过去，滚进视口顶部后自动成为当前章。
    const window = this.readerComicPageDataSource;
    const neighbour = this.currentChapterIndex + (direction > 0 ? 1 : -1);
    const neighbourSegment = window.segment(neighbour);
    if (neighbourSegment && neighbourSegment.pages.length > 0) {
      const neighbourIndex = window.offsetOf(neighbour) + (direction > 0 ? 0 : neighbourSegment.pages.length - 1);
      this.readerComicScroller.scrollToIndex(neighbourIndex, true, ScrollAlign.START);
      return;
    }
    if (direction > 0) {
      // contentPages is an incremental snapshot. Its temporary tail is not the chapter tail until the retained
      // pagination session reports complete; crossing here can skip pages which are appended a moment later.
      if (!this.isCurrentReaderPaginationComplete()) return;
      this.loadNextChapter(false, true);
    } else {
      if (!this.isPreviousChapterTurnReady()) {
        this.pendingScrollPreviousChapterTurn = true;
        this.preloadPreviousChapterPaginationLater(0);
        return;
      }
      this.loadPrevChapter(true, false, true);
    }
  }

  preloadReaderContent(): void {
    if (this.chapters.length === 0) return;
    if (!this.readerPageVisible) {
      this.preloadReaderContentForHiddenTts();
      return;
    }
    if (!this.readerPreloadEnabled) return;
    // Current-page recovery is user-visible work. Do not let speculative adjacent Paragraph sessions compete
    // with it; retry once the authoritative current page has been published.
    if (!this.readerInitialPageReady) {
      this.preloadReaderContentLater(240);
      return;
    }
    const engine = this.readerEngine();
    if (!this.isCurrentReaderEngineBook()) return;
    engine.preloadAround(this.currentChapterIndex, this.normalizePreloadChapterCount(this.readerPreloadChapterCount), 0);
    this.preloadNextChapterPaginationLater();
    this.preloadPreviousChapterPaginationLater();
  }

  // Lock-screen reading has no visible page, but the next chapter body must still be fetched while the current
  // chapter is audible. Fetching it only at the chapter boundary leaves a silent gap in which the system can
  // suspend the process mid-request, so reading stalls until the app returns to the foreground. Only the
  // network/database body is prefetched here; adjacent pagination stays a visible-page job. At least one
  // chapter is fetched even with preloading switched off, because the handoff needs it moments later anyway.
  preloadReaderContentForHiddenTts(): void {
    if (!this.isTtsSpeaking || !this.ttsAutoContinue || !this.isCurrentReaderEngineBook()) return;
    const forwardCount = this.readerPreloadEnabled ?
      this.normalizePreloadChapterCount(this.readerPreloadChapterCount) : 1;
    this.readerEngine().preloadAround(this.currentChapterIndex, forwardCount, 0);
  }

  normalizePreloadChapterCount(count: number): number {
    return Math.max(1, Math.min(Math.round(count), 10));
  }

  preloadReaderContentLater(delayMs: number = 240): void {
    setTimeout(() => {
      this.preloadReaderContent();
    }, Math.max(0, delayMs));
  }

  canTurnPage(direction: number): boolean {
    if (this.chapters.length === 0) {
      return false;
    }
    if (this.pendingRestorePageIndex >= 0) return false;
    if (direction > 0) {
      const targetPageIndex = this.currentPageIndex + this.getReaderPageTurnStep();
      if (targetPageIndex >= this.contentPages.length) {
        this.ensureCurrentReaderPaginationAhead(targetPageIndex + 2);
      }
      if (this.currentPageIndex + this.getReaderPageTurnStep() < this.contentPages.length) return true;
      // Only a completed pagination result owns an authoritative chapter tail. A fast queue can otherwise consume
      // the provisional last spread and enter the next chapter while V2 is still appending hidden pages.
      return this.isCurrentReaderPaginationComplete() && this.currentChapterIndex < this.chapters.length - 1;
    }
    if (this.currentPageIndex > 0) return true;
    if (this.currentChapterIndex <= 0) return false;
    // 跨章前翻与向前跨章、滚动模式同策略：立即提交章节切换。落在真实的最后一页由 loadPrevChapter 的
    // pendingRestorePageIndex(MAX_SAFE_INTEGER) 机制保证——增量排版补齐尾页后才复位，等待期间翻页提示页覆盖屏幕。
    return true;
  }

  // 已在本章已知的最后一页，下一章存在，但本章分页还没排完（进出小窗、分屏等视口变化后要整章重排）。
  // 只读状态，不像 canTurnPage 那样顺手补排。
  isForwardChapterTurnWaitingForPagination(): boolean {
    return this.currentPageIndex + this.getReaderPageTurnStep() >= this.contentPages.length &&
      this.currentChapterIndex < this.chapters.length - 1 && !this.isCurrentReaderPaginationComplete();
  }

  isPreviousChapterTurnReady(): boolean {
    if (!this.hasPagedReaderArea() || this.currentChapterIndex <= 0) return true;
    if (!this.isCurrentReaderEngineBook()) return false;
    const targetChapterIndex = this.currentChapterIndex - 1;
    const body = this.readerEngine().getCachedContent(targetChapterIndex);
    if (!body) return false;
    const prepared = this.getPreparedReaderContent(body, targetChapterIndex);
    if (!prepared && this.readerContentNeedsPreparation(body)) return false;
    const source = this.buildPagedSourceText(targetChapterIndex, prepared || body);
    return this.getCachedReaderPagination(targetChapterIndex, source)?.complete === true;
  }

  resumeDeferredPreviousChapterTurn(sourceChapterIndex: number): void {
    if (this.currentChapterIndex !== sourceChapterIndex || !this.isPreviousChapterTurnReady()) return;
    if (this.pendingScrollPreviousChapterTurn && this.isReaderContinuousScrollSurfaceActive()) {
      this.pendingScrollPreviousChapterTurn = false;
      this.loadPrevChapter(true, false, true);
      return;
    }
    if (!this.isPageTurning && this.pageTurnQueue.hasPendingBackward()) {
      this.runQueuedPageTurnLater();
    }
  }

  // 向前跨章提交后等待增量排版补齐真实的最后一页（pendingRestorePageIndex 复位）。有界等待 + 兜底落页，
  // 任何情况（网络 hang、排版中断、页面隐藏）下都不会把用户留在提示页上；后台排版完成时会原地补齐边界。
  async waitForReaderChapterTailSettled(timeoutMs: number = 12000): Promise<void> {
    if (this.pendingRestorePageIndex < 0 && this.readerTypographyRestoreOffset < 0) return;
    const startedAtChapterIndex = this.currentChapterIndex;
    const deadline = Date.now() + Math.max(0, timeoutMs);
    while (Date.now() < deadline && this.readerPageVisible &&
      (this.pendingRestorePageIndex >= 0 || this.readerTypographyRestoreOffset >= 0)) {
      if (this.currentChapterIndex !== startedAtChapterIndex) return;
      // 加载失败/需要网页验证的提示正文只有一页，不会再排版出尾页，立即落地展示。
      if (this.content.includes('章节正文加载失败') || this.content.includes('完成网页验证')) break;
      await sleepMs(16);
    }
    if (this.pendingRestorePageIndex < 0 && this.readerTypographyRestoreOffset < 0) return;
    console.warn(`[ReaderTurn] previous-chapter tail not ready (timedOut=${Date.now() >= deadline}), ` +
      `chapter=${this.currentChapterIndex}, pages=${this.contentPages.length}`);
    // 兜底：落到当前已知的最后一页。与本地翻页恢复锚点的清理方式保持一致。
    this.currentPageIndex = Math.max(0, this.contentPages.length - 1);
    this.pendingRestorePageIndex = -1;
    this.readerTypographyRestoreOffset = -1;
    this.readerInitialPageReady = true;
    this.finishReaderInitialOpening();
  }

  // 提交跨章前翻后，若提示页仍是通用“正在加载章节内容...”，按内容是否已在本地改为更明确的文案。
  showReaderTailWaitingLeafIfGeneric(): void {
    if (this.pageSlideDirection >= 0 || !this.pageTurnIncomingText) return;
    const targetChapterIndex = this.currentChapterIndex;
    if (this.pageTurnIncomingChapterIndex !== targetChapterIndex) return;
    if (this.pageTurnIncomingText !== this.getPageTurnLoadingText(targetChapterIndex)) return;
    const title = this.getChapterTitle(targetChapterIndex).trim();
    const waiting = this.readerEngine().getCachedContent(targetChapterIndex) ?
      '上一章排版中，请稍候...' : '正在加载上一章...';
    this.setPageTurnIncomingState(this.pageTurnIncomingPageIndex,
      title ? `${title}\n\n${waiting}` : waiting, true, targetChapterIndex);
  }

  ensureCurrentReaderPaginationAhead(requiredPageCount: number): void {
    if (!this.pagedContentText) return;
    let result = this.currentReaderPaginationResult();
    if (!result) {
      if (!this.hasPagedReaderArea()) return;
      // 当前键下没有本章的分页会话（被相邻章节挤出缓存，或分页键在页面不可见时变了却没重排）。
      // 不补建的话本章永远不算排完，章末向后翻页会被一直静默拒绝。新会话在后台排完后才替换可见页面。
      console.warn(`[ReaderPagination] 本章分页会话缺失，重建 chapter=${this.currentChapterIndex} ` +
        `page=${this.currentPageIndex}/${this.contentPages.length}`);
      result = this.getOrCreateReaderPagination(this.currentChapterIndex, this.pagedContentText);
    }
    if (!result.complete && result.pages.length < requiredPageCount) {
      // Normally the idle worker stays well ahead. This is only a boundary fallback for exceptionally fast input.
      this.appendReaderPaginationBatch(result, this.currentChapterIndex,
        Math.max(1, requiredPageCount - result.pages.length));
    }
    if (result.pages.length > this.contentPages.length) this.publishCurrentReaderPagination(result);
    if (result.complete) {
      const key = this.buildReaderPaginationCacheKey(this.currentChapterIndex, this.pagedContentText);
      this.persistReaderPagination(this.currentChapterIndex, key, result);
    }
  }

  currentReaderPaginationResult(): ReaderPaginationResult | null {
    if (!this.pagedContentText || !this.hasPagedReaderArea()) return null;
    const key = this.buildReaderPaginationCacheKey(this.currentChapterIndex, this.pagedContentText);
    const result = this.readerPaginationCache.get(key) || null;
    if (result) {
      // Keep the active chapter newer than speculative adjacent entries. Losing the owning session at a fast
      // chapter boundary makes the visible snapshot look complete even though more pages still exist.
      this.readerPaginationCache.delete(key);
      this.readerPaginationCache.set(key, result);
    }
    return result;
  }

  // Comics and continuous scrolling render a list of chunks, not screen-sized pages: no text is measured
  // and the result is complete at once. Anything else without a usable viewport is a single page.
  createChunkReaderPagination(source: string): ReaderPaginationResult {
    let pages: string[] = source ? [source] : [];
    let starts: number[] = source ? [0] : [];
    let ends: number[] = source ? [source.length] : [];
    if (source && this.isReaderContinuousScrollSurfaceActive()) {
      const chunks: ReaderChunkResult = this.isReaderComicModeActive() ?
        ReaderChunkPagination.splitComic(source) :
        ReaderChunkPagination.splitContinuous(source);
      pages = chunks.pages;
      starts = chunks.starts;
      ends = chunks.ends;
    }
    return {
      source: source,
      pages: pages,
      starts: starts,
      ends: ends,
      cursor: source.length,
      complete: true
    };
  }

  isCurrentReaderPaginationComplete(): boolean {
    if (!this.hasPagedReaderArea() || !this.pagedContentText) return true;
    const result = this.currentReaderPaginationResult();
    // paginateContent always registers the active result. If it is temporarily absent, fail closed at the
    // chapter boundary instead of treating an unverified visible snapshot as authoritative.
    return result?.complete === true;
  }

  async applyPageTurn(direction: number, targetPreview: PageTurnPreview | null = null,
    commitText: boolean = true): Promise<void> {
    const capturedLocalTarget = !!targetPreview && targetPreview.chapterIndex === this.currentChapterIndex &&
      (!targetPreview.documentSource || targetPreview.documentSource === this.pagedContentText);
    let localPageIndex = -1;
    if (capturedLocalTarget && targetPreview) {
      const capturedPageIndex = this.normalizeReaderSpreadPageIndex(Math.max(0, targetPreview.pageIndex));
      if (capturedPageIndex >= this.contentPages.length) {
        this.ensureCurrentReaderPaginationAhead(capturedPageIndex + this.getReaderPageTurnStep());
      }
      // The target was frozen before the animation. If its pagination window is still rebuilding, never reinterpret
      // the changed currentPageIndex as a chapter boundary; that turns one local page into a whole-chapter skip.
      if (capturedPageIndex >= this.contentPages.length) return;
      if (this.pendingRestorePageIndex >= 0 || this.readerTypographyRestoreOffset >= 0) {
        // A background snapshot may have preserved the page that was visible at animation start. The explicit user
        // turn now supersedes that anchor; leaving it alive restores the old page a moment after the animation.
        this.pendingRestorePageIndex = -1;
        this.readerTypographyRestoreOffset = -1;
        this.readerInitialPageReady = true;
        this.finishReaderInitialOpening();
      }
      localPageIndex = capturedPageIndex;
    } else {
      localPageIndex = this.getLocalPageTurnTargetPageIndex(direction);
    }
    if (localPageIndex >= 0) {
      // A valid explicit turn is authoritative even when the initial restore finished before this gesture began.
      // Without this assignment an offset-based restore could keep every later checkpoint pinned to the old page.
      this.readerProgressRestoreConfirmed = true;
    }
    if (direction > 0) {
      if (localPageIndex >= 0) {
        this.applyLocalPageTurnTarget(localPageIndex, targetPreview, commitText);
        if (this.contentPages.length - this.currentPageIndex <= 3) {
          this.preloadReaderContentLater();
          this.preloadNextChapterPaginationLater(0);
        }
        this.scheduleReaderPagedProgressSave();
      } else {
        if (!this.isCurrentReaderPaginationComplete()) return;
        await this.loadNextChapter();
      }
      return;
    }

    if (localPageIndex >= 0) {
      this.applyLocalPageTurnTarget(localPageIndex, targetPreview, commitText);
      if (this.currentPageIndex <= 2) {
        this.preloadReaderContentLater();
      }
      this.scheduleReaderPagedProgressSave();
    } else {
      // 与向前跨章、滚动模式同策略：立即提交章节切换。提示页（“上一章排版中/加载中”）在等待期间
      // 覆盖屏幕，尾页排版完成后 pendingRestorePageIndex 复位、自动落在真实的最后一页。
      await this.loadPrevChapter(true);
      this.showReaderTailWaitingLeafIfGeneric();
      await this.waitForReaderChapterTailSettled();
      this.scheduleReaderPagedProgressSave();
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
        chapterIndex: this.currentChapterIndex,
        pageStart: this.getPageStartOffset(localPageIndex),
        secondaryPageStart: this.isLandscapeDoublePageActive() ? this.getPageStartOffset(localPageIndex + 1) : -1,
        documentSource: this.pagedContentText
      };
    }
    if (this.pageTurnIncomingText) {
      return {
        text: this.pageTurnIncomingText,
        secondaryText: this.pageTurnIncomingSecondaryText,
        pageIndex: this.pageTurnIncomingPageIndex,
        chapterIndex: this.pageTurnIncomingChapterIndex,
        pageStart: this.pageTurnIncomingPageStart,
        secondaryPageStart: this.pageTurnIncomingSecondaryPageStart,
        documentSource: this.pageTurnIncomingDocumentSource
      };
    }
    return null;
  }
  async runPageTurnAnimation(direction: number, style: string, fromQueue: boolean = false,
    releaseVelocity: number = 0): Promise<void> {
    if (!fromQueue && Date.now() < this.readerGestureTurnGuardUntil) {
      if (style === 'gesture' && this.readerGestureTurnAllowance > 0) {
        this.readerGestureTurnAllowance = 0;
      } else {
        return;
      }
    }
    if (this.isPageTurning) {
      // Touch.Up and PanGesture.onActionEnd can both report the same physical swipe.
      // commitReaderMove already de-duplicates them, so one subsequent physical swipe can safely be queued.
      // Keep a tiny bounded queue so rapid input flows into the next animation instead of being swallowed.
      // Two slots cover animation/chapter handoff jitter without letting a long input backlog run away.
      this.enqueueReaderPageTurn(direction, style, releaseVelocity);
      return;
    }
    if (this.pendingRestorePageIndex >= 0) {
      // Loading the previous chapter can publish a small V2 window before its real tail is rebuilt. Keep input
      // queued until restorePendingPageIndex resolves; accepting a new turn here skips the still-hidden pages.
      this.enqueueReaderPageTurn(direction, style, releaseVelocity);
      return;
    }
    if (!this.canTurnPage(direction)) {
      if (direction > 0 && this.isForwardChapterTurnWaitingForPagination()) {
        // 章末向后翻页要等本章排完才知道是不是真的最后一页。先记下这次翻页，确保后台补排链在跑，
        // 排完时 scheduleReaderPaginationCompletion 会接着执行；以前这里直接丢弃，章末怎么点都没反应。
        this.resetSlidePageEffect();
        this.enqueueReaderPageTurn(direction, style, releaseVelocity);
        this.resumeCurrentReaderPaginationCompletion();
        return;
      }
      this.pageTurnQueue.reset();
      this.resetSlidePageEffect();
      if (direction > 0 && this.chapters.length > 0 &&
        this.currentChapterIndex >= this.chapters.length - 1 &&
        this.getLocalPageTurnTargetPageIndex(1) < 0) {
        HdsFeedback.showToast('本书已阅读完成');
      }
      return;
    }
    if (direction < 0 && this.pageTurnQueue.hasPendingForward()) {
      // 用户已经往回翻了，章末那次等排版的向后翻页作废，免得排完后突然自己翻一页。
      this.pageTurnQueue.reset();
    }
    const turnRequestStartedAt = Date.now();
    const resumeMirroredTtsAfterTurn = this.isMirroringActiveTtsForCurrentBook();
    const resumeTtsAfterTurn = this.ttsManualPageTurnResumePending ||
      this.isTtsSpeaking || this.ttsReader.isSpeaking();
    let ttsPrepareElapsed = 0;
    if (resumeMirroredTtsAfterTurn) {
      this.prepareMirroredTtsManualPageTurn();
    } else if (resumeTtsAfterTurn) {
      // Stop only synthesis/audio. Do not synchronously refresh AVSession metadata or clear the
      // highlighted subtree before the visual turn; both operations are much more expensive than
      // the animation itself. Rapid/queued turns share one deferred restart at the final page.
      this.prepareTtsForManualPageTurn();
      ttsPrepareElapsed = Math.max(0, Date.now() - turnRequestStartedAt);
    }
    const visualStartedAt = Date.now();
    // Text pagination runs on the UI thread. Reserve the whole visual turn plus a short handoff window so an
    // idle batch cannot slip between two queued curls and move the paragraph tree on their shared boundary.
    this.deferReaderPaginationForInteraction(700);
    this.isPageTurning = true;
    let turnCompleted = false;
    try {
      if (!this.isPageTurnAnimationEnabled()) {
        await this.runNoAnimationPageTurn(direction);
      } else if (style === 'slide' || style === 'gesture') {
        await this.runSlidePageTurn(direction, fromQueue && style === 'gesture', releaseVelocity);
      } else {
        await this.runTapPageTurn(direction);
      }
      turnCompleted = true;
    } finally {
      this.isPageTurning = false;
    }
    this.deferReaderPaginationForInteraction(220);
    if (resumeTtsAfterTurn) {
      console.info(`[TTS-Turn] visual ${turnCompleted ? 'completed' : 'cancelled'} in ` +
        `${Math.max(0, Date.now() - visualStartedAt)}ms,request=${Math.max(0, Date.now() - turnRequestStartedAt)}ms,` +
        `prepare=${ttsPrepareElapsed}ms,chapter=${this.currentChapterIndex},` +
        `page=${this.currentPageIndex},queued=${this.pageTurnQueue.pendingCount()}`);
    }
    this.runQueuedPageTurnLater();
    if (resumeMirroredTtsAfterTurn) {
      this.scheduleMirroredTtsResumeAfterManualPageTurn();
    } else if (resumeTtsAfterTurn) {
      this.scheduleTtsResumeAfterManualPageTurn();
    }
  }

  prepareMirroredTtsManualPageTurn(): void {
    if (this.mirroredTtsManualTurnTimerId >= 0) {
      clearTimeout(this.mirroredTtsManualTurnTimerId);
      this.mirroredTtsManualTurnTimerId = -1;
    }
    this.mirroredTtsManualTurnPending = true;
    this.mirroredTtsManualTurnSerial++;
    // Invalidate a focus sync that may currently be awaiting chapter content.
    this.mirroredTtsFocusSyncSerial++;
  }

  scheduleMirroredTtsResumeAfterManualPageTurn(): void {
    if (!this.mirroredTtsManualTurnPending) return;
    if (this.mirroredTtsManualTurnTimerId >= 0) clearTimeout(this.mirroredTtsManualTurnTimerId);
    const serial = ++this.mirroredTtsManualTurnSerial;
    this.mirroredTtsManualTurnTimerId = setTimeout(() => {
      this.mirroredTtsManualTurnTimerId = -1;
      if (serial !== this.mirroredTtsManualTurnSerial || !this.mirroredTtsManualTurnPending) return;
      if (this.isPageTurning || this.pageTurnQueue.hasPending() ||
        !this.isReaderPageTurnPositionReadyForTts()) {
        this.scheduleMirroredTtsResumeAfterManualPageTurn();
        return;
      }
      const chapterIndex = this.currentChapterIndex;
      const pageIndex = this.currentPageIndex;
      const pageStartOffset = this.getPageStartOffset(pageIndex);
      ReaderTtsFloatingSession.jumpToPosition(chapterIndex, pageIndex, pageStartOffset)
        .then(() => {
          if (serial !== this.mirroredTtsManualTurnSerial) return;
          this.mirroredTtsManualTurnPending = false;
          this.syncMirroredTtsFocus()
            .then(() => this.scheduleCurrentTtsFocusRepublishAfterPageTurn())
            .catch((error: Error) => {
              console.warn('手动翻页后同步后台朗读焦点失败:', error);
            });
        })
        .catch((error: Error) => {
          if (serial !== this.mirroredTtsManualTurnSerial) return;
          this.mirroredTtsManualTurnPending = false;
          console.warn('手动翻页提交后台朗读位置失败:', error);
          this.syncMirroredTtsFocus()
            .then(() => this.scheduleCurrentTtsFocusRepublishAfterPageTurn())
            .catch(() => {});
        });
    }, 48);
  }

  cancelMirroredTtsManualPageTurn(): void {
    this.mirroredTtsManualTurnSerial++;
    this.mirroredTtsManualTurnPending = false;
    if (this.mirroredTtsManualTurnTimerId >= 0) {
      clearTimeout(this.mirroredTtsManualTurnTimerId);
      this.mirroredTtsManualTurnTimerId = -1;
    }
  }

  enqueueReaderPageTurn(direction: number, style: string, releaseVelocity: number): void {
    this.pageTurnQueue.enqueue(direction, style, releaseVelocity);
  }

  runQueuedPageTurnLater(): void {
    if (this.pendingRestorePageIndex >= 0) return;
    const turn = this.pageTurnQueue.take();
    if (!turn) return;
    setTimeout(() => {
      if (!this.pageTurnQueue.isCurrent(turn)) return;
      this.runPageTurnAnimation(turn.direction, turn.style, true, turn.velocity);
    }, 0);
  }

  clearQueuedReaderPageTurns(): void {
    this.pageTurnQueue.cancel();
    this.pendingScrollPreviousChapterTurn = false;
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
      this.finishPageTurnAnimation(false);
      if (direction > 0 && this.contentPages.length - this.currentPageIndex <= 3) {
        this.preloadReaderContentLater();
        this.preloadNextChapterPaginationLater(0);
      } else if (direction < 0 && this.currentPageIndex <= 2) {
        this.preloadReaderContentLater();
      }
      this.scheduleReaderPagedProgressSave();
      this.commitCurrentPageTextLater(this.currentChapterIndex, this.currentPageIndex, targetText);
      return;
    }

    if (direction > 0) {
      if (this.isCurrentReaderPaginationComplete()) await this.loadNextChapter();
    } else {
      await this.loadPrevChapter(true);
      await this.waitForReaderChapterTailSettled();
    }
    const targetText = this.getCurrentPageText();
    this.finishPageTurnAnimation(false);
    this.commitVisibleCurrentPageText(targetText, true);
    this.commitCurrentPageTextLater(this.currentChapterIndex, this.currentPageIndex, targetText);
  }

  commitVisibleCurrentPageText(text: string = this.visibleCurrentPageText(), forceRender: boolean = false): void {
    const nextText = text || '';
    if (!forceRender && this.currentPageText === nextText && this.displayPageText === nextText &&
      this.displayPageChapterIndex === this.currentChapterIndex && this.displayPageIndex === this.currentPageIndex) {
      return;
    }
    this.readerTextSelectionSerial++;
    this.setReaderTextSelectionActive(false);
    this.clearReaderV2SelectionOverlay();
    this.readerSourceActionAreas.clear();
    this.readerSourceActionScrollOffsets.clear();
    this.clearPendingReaderSourceActionBounds();
    this.currentPageText = nextText;
    this.displayPageText = nextText;
    this.displayPageChapterIndex = this.currentChapterIndex;
    this.displayPageIndex = this.currentPageIndex;
    this.displayPageRenderKey++;
    this.forceCurrentReaderPageRender();
    // V2 keeps one native FrameNode across horizontal turns. Updating only the declarative page state can leave
    // that retained node painting the previous page until another frame happens to rebuild the surrounding tree,
    // which is especially visible at a cross-chapter handoff. Publish the exact settled page immediately.
    this.refreshCurrentReaderV2RetainedPages();
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

  async runTapPageTurn(direction: number): Promise<void> {
    const distance = this.getPageTurnDistance();
    this.prepareSlidePageTurn(direction, 0);
    const targetPreview = this.capturePageTurnCommitTarget(direction);
    if (this.usesReaderPageCurlCanvas()) {
      await this.completeSimulationPageTurnMotion(direction);
    } else {
      const duration = 220;
      await this.runReaderAnimation(duration, this.pageTurnAnimationCurve(), () => {
        this.setPageSlideAxisOffset(direction > 0 ? -distance : distance);
        this.pageTransitionOpacity = 1;
      });
    }
    await this.applyPageTurn(direction, targetPreview, false);
    await this.finishAnimatedPageTurn();
  }

  readerSlideCompletionDuration(remaining: number, distance: number, releaseVelocity: number,
    queuedGesture: boolean): number {
    const safeDistance = Math.max(1, distance);
    const remainingRatio = Math.max(0, Math.min(1, remaining / safeDistance));
    if (queuedGesture) {
      return Math.max(70, Math.min(100, Math.round(100 * remainingRatio)));
    }
    let durationCap = 160;
    if (releaseVelocity >= 2800) {
      durationCap = 90;
    } else if (releaseVelocity >= 1400) {
      durationCap = 115;
    } else if (releaseVelocity >= 700) {
      durationCap = 140;
    }
    return Math.max(90, Math.min(durationCap, Math.round(160 * remainingRatio)));
  }

  async runSlidePageTurn(direction: number, queuedGesture: boolean = false,
    releaseVelocity: number = 0): Promise<void> {
    const distance = this.getPageTurnDistance();
    this.prepareSlidePageTurn(direction, this.getPageSlideAxisOffset());
    const targetPreview = this.capturePageTurnCommitTarget(direction);
    const targetOffset = direction > 0 ? -distance : distance;
    const remaining = Math.abs(targetOffset - this.getPageSlideAxisOffset());
    if (this.usesReaderPageCurlCanvas()) {
      await this.completeSimulationPageTurnMotion(direction);
    } else {
      const duration = this.readerSlideCompletionDuration(remaining, distance, releaseVelocity, queuedGesture);
      await this.runReaderAnimation(duration, this.pageTurnAnimationCurve(), () => {
        this.setPageSlideAxisOffset(targetOffset);
        this.pageTransitionOpacity = 1;
      });
    }
    await this.applyPageTurn(direction, targetPreview, false);
    await this.finishAnimatedPageTurn();
  }

  async finishAnimatedPageTurn(): Promise<void> {
    const chapterIndex = this.currentChapterIndex;
    const pageIndex = this.currentPageIndex;
    const targetText = this.getCurrentPageText();
    // The incoming surface is already at the viewport origin. Commit and lay out the new current surface behind it,
    // then remove the incoming surface on the next frame. Removing it first caused an intermittent background flash.
    const keepIncomingVisible = this.pageSlideDirection !== 0 && !!this.pageTurnIncomingText;
    this.commitVisibleCurrentPageText(targetText);
    if (keepIncomingVisible) {
      // Cross-chapter pages may contain many bubble ImageSpans. Keep the already-complete preview on top
      // for a few frames while the new current render group is rasterized behind it.
      await sleepMs(this.pageTurnCrossChapterHandoff ? 48 : 16);
      if (chapterIndex !== this.currentChapterIndex || pageIndex !== this.currentPageIndex) return;
    }
    this.finishPageTurnAnimation(false);
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
    this.requestReaderPageCurlCapture();
  }

  finishPageTurnAnimation(releaseTurnLock: boolean = true): void {
    this.readerCurlStartRegion = READER_CURL_REGION_UNSET;
    this.resetReaderPageCurl();
    this.pageTransitionX = 0;
    this.pageTransitionOpacity = 1;
    this.pageSlideOffsetX = 0;
    this.pageSlideOffsetY = 0;
    this.pageSlideDirection = 0;
    this.pageTurnIncomingX = 0;
    this.pageTurnIncomingOpacity = 1;
    this.setPageTurnIncomingState(this.currentPageIndex, '', false);
    this.clearPageTurnPreviewState();
    if (releaseTurnLock) this.isPageTurning = false;
  }

  setPageTurnIncomingState(pageIndex: number, text: string, animating: boolean = true,
    chapterIndex: number = this.currentChapterIndex, secondaryText: string = '', pageStart: number = -1,
    secondaryPageStart: number = -1, documentSource: string = ''): void {
    const safeText = text || '';
    const safeSecondaryText = secondaryText || '';
    const safeDocumentSource = documentSource || '';
    const nextAnimating = animating && !!safeText;
    if (this.pageTurnIncomingPageIndex !== pageIndex || this.pageTurnIncomingChapterIndex !== chapterIndex ||
      this.pageTurnIncomingText !== safeText || this.pageTurnIncomingSecondaryText !== safeSecondaryText ||
      this.pageTurnIncomingPageStart !== pageStart ||
      this.pageTurnIncomingSecondaryPageStart !== secondaryPageStart ||
      this.pageTurnIncomingDocumentSource !== safeDocumentSource || this.pageTurnAnimating !== nextAnimating) {
      this.pageTurnIncomingRenderVersion++;
    }
    this.pageTurnIncomingPageIndex = pageIndex;
    this.pageTurnIncomingChapterIndex = chapterIndex;
    this.pageTurnIncomingText = safeText;
    this.pageTurnIncomingSecondaryText = safeSecondaryText;
    this.pageTurnIncomingPageStart = pageStart;
    this.pageTurnIncomingSecondaryPageStart = secondaryPageStart;
    this.pageTurnIncomingDocumentSource = safeDocumentSource;
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

  getLocalPageTurnTargetPageIndex(direction: number): number {
    const step = this.getReaderPageTurnStep();
    if (direction > 0 && this.currentPageIndex + step >= this.contentPages.length) {
      this.ensureCurrentReaderPaginationAhead(this.currentPageIndex + step + 2);
    }
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
      this.isCurrentReaderPaginationComplete() && this.currentChapterIndex < this.chapters.length - 1) {
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
      this.pageTurnCrossChapterHandoff = false;
      this.pageTurnPreviewKey = `local_${localPageIndex}`;
      this.setPageTurnIncomingState(localPageIndex, this.getPageText(localPageIndex), true,
        this.currentChapterIndex, this.getSecondaryPageText(localPageIndex),
        this.getPageStartOffset(localPageIndex),
        this.isLandscapeDoublePageActive() ? this.getPageStartOffset(localPageIndex + 1) : -1,
        this.pagedContentText);
      return;
    }

    const targetChapterIndex = this.getAdjacentPageTurnChapterIndex(direction);
    if (targetChapterIndex < 0) {
      this.pageTurnCrossChapterHandoff = false;
      this.setPageTurnIncomingState(this.currentPageIndex, '', false);
      return;
    }
    this.pageTurnCrossChapterHandoff = true;

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
      `${this.readerExtendToStatusBar}_${this.getReaderPageContentTopPadding()}_` +
      `${this.isLandscapeDoublePageActive()}_${this.readerTypographyCacheIdentity()}`;
  }

  buildCachedAdjacentPageTurnPreview(direction: number, chapterIndex: number): PageTurnPreview {
    if (!this.isCurrentReaderEngineBook()) {
      return { text: '', pageIndex: 0, chapterIndex: chapterIndex };
    }
    const body = this.readerEngine().getCachedContent(chapterIndex);
    if (!body) {
      return { text: '', pageIndex: 0, chapterIndex: chapterIndex };
    }
    const prepared = this.getPreparedReaderContent(body, chapterIndex);
    if (!prepared && this.readerContentNeedsPreparation(body)) {
      return { text: '', pageIndex: 0, chapterIndex: chapterIndex };
    }
    return this.buildAdjacentPageTurnPreview(direction, chapterIndex, prepared || body);
  }

  buildAdjacentPageTurnPreview(direction: number, chapterIndex: number, preparedBody: string): PageTurnPreview {
    const source = this.buildPagedSourceText(chapterIndex, preparedBody);
    const result = this.getOrCreateReaderPagination(chapterIndex, source);
    if (result.pages.length === 0) {
      return { text: '', pageIndex: 0, chapterIndex: chapterIndex };
    }
    // For a backward chapter turn, result.pages.length is authoritative only after pagination is
    // complete. A cooperative V2 session initially contains the first spread, so treating its last
    // currently-known page as the chapter tail makes simulation mode preview page one and then jump
    // to the real last page after commit.
    if (direction < 0 && !result.complete) {
      return { text: '', pageIndex: 0, chapterIndex: chapterIndex };
    }
    const pageIndex = direction > 0 ? 0 : this.normalizeReaderSpreadPageIndex(result.pages.length - 1);
    return {
      text: result.pages[pageIndex],
      secondaryText: this.isLandscapeDoublePageActive() ? (result.pages[pageIndex + 1] || '') : '',
      pageIndex: pageIndex,
      chapterIndex: chapterIndex,
      pageStart: result.starts[pageIndex] ?? 0,
      secondaryPageStart: this.isLandscapeDoublePageActive() ? (result.starts[pageIndex + 1] ?? -1) : -1,
      documentSource: result.source
    };
  }

  getPageTurnLoadingText(chapterIndex: number): string {
    const title = this.getChapterTitle(chapterIndex).trim();
    return title ? `${title}\n\n正在加载章节内容...` : '正在加载章节内容...';
  }

  applyPageTurnPreview(preview: PageTurnPreview): void {
    this.setPageTurnIncomingState(preview.pageIndex, preview.text, true, preview.chapterIndex,
      preview.secondaryText || '', preview.pageStart ?? -1, preview.secondaryPageStart ?? -1,
      preview.documentSource || '');
    this.pageTurnIncomingOpacity = 1;
    this.requestReaderPageCurlCapture();
  }

  loadAdjacentPageTurnPreview(direction: number, chapterIndex: number, key: string): void {
    if (this.pageTurnPreviewLoadingKey === key) {
      return;
    }
    const sessionBookUrl = this.book?.bookUrl || this.bookUrl;
    if (!this.isCurrentReaderEngineBook(sessionBookUrl)) return;
    this.pageTurnPreviewLoadingKey = key;
    this.readerEngine().peekContent(chapterIndex)
      .then(async (body: string): Promise<void> => {
        if (!this.isCurrentReaderEngineBook(sessionBookUrl) || this.pageTurnPreviewKey !== key ||
          this.pageSlideDirection !== direction) {
          return;
        }
        const prepared = await this.prepareReaderContentRules(body, chapterIndex);
        if (!this.isCurrentReaderEngineBook(sessionBookUrl) || this.pageTurnPreviewKey !== key ||
          this.pageSlideDirection !== direction) return;
        const preview = this.buildAdjacentPageTurnPreview(direction, chapterIndex, prepared);
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

  isCurrentReaderEngineBook(expectedBookUrl: string = this.book?.bookUrl || this.bookUrl): boolean {
    return !!expectedBookUrl && this.readerEngine().book?.bookUrl === expectedBookUrl;
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
    this.requestReaderPageCurlCapture();
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
    if (this.usesReaderPageCurlCanvas()) {
      this.rollbackReaderPageCurl(duration, serial).catch((error: Error) => {
        console.warn('回弹仿真翻页失败:', error);
        if (this.slideResetSerial === serial && !this.isPageTurning) this.resetSlidePageState();
      });
      return;
    }
    this.runReaderAnimation(duration, Curve.EaseOut, () => {
      this.setPageSlideAxisOffset(0);
      this.pageTransitionOpacity = 1;
      this.pageTurnIncomingOpacity = 1;
    }).then(() => {
      if (this.slideResetSerial === serial && !this.isPageTurning) {
        this.resetSlidePageState();
      }
    });
  }

  async rollbackReaderPageCurl(duration: number, serial: number): Promise<void> {
    const ready = await this.ensureReaderPageCurlReady();
    if (!ready) {
      if (this.slideResetSerial === serial && !this.isPageTurning) this.resetSlidePageState();
      return;
    }
    await this.animateReaderPageCurlOffset(0, duration);
    if (this.slideResetSerial === serial && !this.isPageTurning) this.resetSlidePageState();
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
    const type = this.effectivePageTurnAnimationType();
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
    // The declarative page-turn surface expands through the bottom system safe area. When pageViewHeight is
    // measured before that expansion, omitting the inset scales a full-height snapshot into a shorter canvas
    // and makes the entire page visibly squeeze upward while it is turning. The inset is the measured gap below
    // the paged area, which is zero when the area already reaches the window bottom.
    return Math.max(1, contentHeight + this.getReaderPageContentTopPadding() +
      this.getReaderBottomSystemExtension());
  }

  isVerticalPageTurnAnimation(): boolean {
    return this.readerEffectivePageTurnMode() === 0 && !this.usesReaderPageCurlCanvas();
  }

  // 3D 仿真在单页与左右双页下都走卷曲画布管线；双页时由 ReaderEmulationFlipPainter 处理半页纸的卷起与落地。
  effectivePageTurnAnimationType(): number {
    return this.normalizePageTurnAnimationType(this.readerPageTurnAnimationType);
  }

  isStackPageTurnAnimation(): boolean {
    return this.effectivePageTurnAnimationType() === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK;
  }

  isSimulationPageTurnAnimation(): boolean {
    return this.effectivePageTurnAnimationType() === ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION;
  }

  is3DPageTurnAnimation(): boolean {
    return this.effectivePageTurnAnimationType() === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D;
  }

  // 仿真与 3D 仿真都依赖同一个卷曲画布管线：截图当前页、底层铺目标页、由 Canvas 绘制翻页。
  usesReaderPageCurlCanvas(): boolean {
    return this.isSimulationPageTurnAnimation() || this.is3DPageTurnAnimation();
  }

  // 对应官方示例 initPanPositionX：按手指落点决定卷曲从上角/下角/中部开始。
  // 折页背面的纸张底色：取主题背景色；背景图主题的背景色常为全透明，此时退回白纸避免透出下层。
  readerFlapPaperColor(): string {
    const color = this.getBackgroundColor();
    if (!color) {
      return '#FFFFFF';
    }
    return color.length >= 9 && color.toUpperCase().endsWith('00') ? '#FFFFFF' : color;
  }

  // 3D 仿真单页拖动时把手指位置交给绘制器，纸张抓取点跟随手指。手势层与卷曲画布都铺满阅读页，
  // 手指的组件内坐标可以直接当作画布坐标。上一页还在自动翻完时不接管，免得半途的折页跳到新手指处。
  updateReaderCurlFinger(event: GestureEvent): void {
    if (!this.is3DPageTurnAnimation() || this.isLandscapeDoublePageActive() || this.isPageTurning || !event ||
      !event.fingerList || event.fingerList.length === 0) {
      return;
    }
    this.readerEmulationFlipPainter.dragCorner(event.fingerList[0].localX, event.fingerList[0].localY);
  }

  captureReaderCurlStartRegion(event: GestureEvent): void {
    if (this.isPageTurning) {
      return;
    }
    this.readerCurlStartRegion = ReaderEmulationFlipRegion.MIDDLE;
    if (!this.is3DPageTurnAnimation() || !event || !event.fingerList || event.fingerList.length === 0) {
      return;
    }
    const localY = event.fingerList[0].localY;
    const height = this.getPageTurnHeight();
    // 上/下部起手抓页角折过去；中部起手抓右边缘与手指同高处，折线随手指上下倾斜。
    if (localY < height / 3) {
      this.readerCurlStartRegion = ReaderEmulationFlipRegion.TOP;
    } else if (localY > height * 2 / 3) {
      this.readerCurlStartRegion = ReaderEmulationFlipRegion.BOTTOM;
    } else {
      this.readerCurlStartRegion = ReaderEmulationFlipRegion.MIDDLE;
    }
  }

  pageTurnAnimationCurve(): Curve {
    return this.isSimulationPageTurnAnimation() || this.is3DPageTurnAnimation() ?
      Curve.EaseInOut : Curve.EaseOut;
  }

  readerPageCurlSnapshotScale(): number {
    return this.is3DPageTurnAnimation() ? READER_PAGE_3D_SNAPSHOT_SCALE : READER_PAGE_CURL_SNAPSHOT_SCALE;
  }

  // 3D 仿真单页不绘制背页位图，省掉这次截图可以让卷曲更快起步。
  readerPageCurlNeedsBackSnapshot(): boolean {
    return !this.is3DPageTurnAnimation() || this.isLandscapeDoublePageActive();
  }

  getReaderPageCurlCanvasHeight(): number {
    // Prefer the actual captured component height. It stays correct for gesture-navigation variants, split-screen
    // windows and devices whose bottom avoid area differs from the globally cached navigation height.
    return this.readerPageCurlSnapshotHeight > 0 ? this.readerPageCurlSnapshotHeight : this.getPageTurnHeight();
  }

  readerPageCurlKey(): string {
    return `${this.pageSlideDirection}_${this.currentChapterIndex}_${this.currentPageIndex}_` +
      `${this.pageRenderVersion}_${this.ttsHighlightRenderVersion}_${this.pageTurnIncomingChapterIndex}_` +
      `${this.pageTurnIncomingPageIndex}_${this.pageTurnIncomingRenderVersion}_` +
      `${this.isLandscapeDoublePageActive() ? 1 : 0}_${this.getPageTurnWidth()}_${this.getPageTurnHeight()}_` +
      `${this.getReaderPageContentTopPadding()}_${this.navBarHeight}_${this.readerExtendToStatusBar ? 1 : 0}`;
  }

  drawReaderPageCurl(): void {
    if (!this.readerPageCurlCanvasReady || !this.readerPageCurlSnapshotReady ||
      !this.readerPageCurlFront || this.pageSlideDirection === 0) {
      return;
    }
    if (this.is3DPageTurnAnimation()) {
      // 3D 仿真单页时只卷曲当前页，目标页由底层声明式页面呈现；只有双页才需要背页位图。
      // 点击翻页没有手指落点，统一从下角卷起。
      const region = this.readerCurlStartRegion === READER_CURL_REGION_UNSET ?
        ReaderEmulationFlipRegion.BOTTOM : this.readerCurlStartRegion;
      this.readerEmulationFlipPainter.draw(this.readerPageCurlContext, this.readerPageCurlFront,
        this.readerPageCurlBack, this.getPageTurnWidth(), this.getReaderPageCurlCanvasHeight(),
        this.getPageTurnProgress(), this.pageSlideDirection, region,
        this.isLandscapeDoublePageActive(), this.getReaderPageColumnWidth(),
        this.getReaderDoublePageRightOrigin(), 1 / this.getUIContext().vp2px(1),
        this.readerFlapPaperColor(), this.isReaderThemeDark());
      return;
    }
    if (!this.readerPageCurlBack) {
      return;
    }
    this.readerPageCurlPainter.draw(this.readerPageCurlContext, this.readerPageCurlFront,
      this.readerPageCurlBack, this.getPageTurnWidth(), this.getReaderPageCurlCanvasHeight(),
      this.getPageTurnProgress(), this.pageSlideDirection, this.isLandscapeDoublePageActive(),
      this.isReaderThemeDark(), this.getReaderPageColumnWidth(), this.getReaderDoublePageRightOrigin());
  }

  requestReaderPageCurlCapture(): void {
    if (!this.usesReaderPageCurlCanvas() || this.pageSlideDirection === 0 ||
      !this.shouldRenderSlidingPageTurn()) {
      return;
    }
    const key = this.readerPageCurlKey();
    if (key === this.readerPageCurlCaptureKey &&
      (this.readerPageCurlSnapshotReady || this.readerPageCurlCapturePending)) {
      // The gesture/animator already paints after publishing the latest offset. Repainting here
      // made every double-page drag update submit the same expensive textured mesh twice.
      return;
    }
    this.readerPageCurlCaptureKey = key;
    this.readerPageCurlCapturePending = true;
    this.readerPageCurlSnapshotReady = false;
    const serial = ++this.readerPageCurlCaptureSerial;
    setTimeout(() => {
      this.captureReaderPageCurlSnapshots(serial, key).catch((error: Error) => {
        if (serial === this.readerPageCurlCaptureSerial) {
          this.readerPageCurlCapturePending = false;
        }
        console.warn('生成仿真翻页快照失败:', error);
      });
    }, 0);
  }

  async captureReaderPageCurlSnapshots(serial: number, key: string): Promise<void> {
    for (let attempt = 0; attempt < 30 && this.pageTurnPreviewLoadingKey; attempt++) {
      if (serial !== this.readerPageCurlCaptureSerial || key !== this.readerPageCurlCaptureKey) return;
      await sleepMs(20);
    }
    // Let the incoming cross-chapter preview and its ImageSpans finish one layout pass before rasterizing.
    await sleepMs(this.pageTurnCrossChapterHandoff ? 32 : 0);
    // The retained V2 current component keeps a stable id across pages. Unlike the old temporary capture node,
    // that id already exists in the same task that commits a queued turn, so snapshot.get() could succeed before
    // its controller has painted the newly-settled page. Wait one render frame and capture the page the user
    // actually sees, not the previous texture still owned by RenderService.
    await sleepMs(16);
    if (serial !== this.readerPageCurlCaptureSerial || key !== this.readerPageCurlCaptureKey ||
      this.pageSlideDirection === 0) return;
    const snapshot = this.getUIContext().getComponentSnapshot();
    const suffix = this.isLandscapeDoublePageActive() ? 'double' : 'single';
    const snapshotScale = this.readerPageCurlSnapshotScale();
    const needsBack = this.readerPageCurlNeedsBackSnapshot();
    let front: image.PixelMap | null = null;
    let back: image.PixelMap | null = null;
    // A tap can request the snapshot in the same task that publishes the simulation subtree.
    // The component IDs become available on a following render frame, so retry transient 100001
    // failures instead of letting tap turns miss the curl while drag turns happen to work.
    for (let attempt = 0; attempt < 24; attempt++) {
      try {
        // The paper front must be the exact settled component already visible to the user. Rebuilding a second
        // native Paragraph solely for capture can resolve to a neighbouring physical-pixel origin and produces
        // a small but repeatable vertical jump at the start of every rapid turn.
        front = await snapshot.get(this.currentReaderSnapshotComponentId(), {
          scale: snapshotScale,
          waitUntilRenderFinished: false
        });
        if (needsBack) {
          back = await snapshot.get(`reader_page_curl_back_${suffix}`, {
            scale: snapshotScale,
            waitUntilRenderFinished: false
          });
        }
        if (this.isLandscapeDoublePageActive()) {
          await this.cropReaderPageCurlFrontToTurningLeaf(front);
        }
        break;
      } catch (error) {
        if (front) front.release().catch(() => {});
        if (back) back.release().catch(() => {});
        front = null;
        back = null;
        if (serial !== this.readerPageCurlCaptureSerial || key !== this.readerPageCurlCaptureKey ||
          this.pageSlideDirection === 0) return;
        if (attempt >= 23) throw new Error(`获取仿真翻页快照失败: ${error}`);
        await sleepMs(16);
      }
    }
    if (!front || (needsBack && !back)) return;
    let snapshotHeight = this.getPageTurnHeight();
    try {
      const frontInfo = await front.getImageInfo();
      snapshotHeight = px2vp(Math.max(1,
        frontInfo.size.height / snapshotScale));
    } catch (error) {
      console.warn('读取仿真翻页快照尺寸失败，使用页面布局高度:', error);
    }
    if (serial !== this.readerPageCurlCaptureSerial || key !== this.readerPageCurlCaptureKey ||
      this.pageSlideDirection === 0) {
      front.release().catch(() => {});
      if (back) back.release().catch(() => {});
      return;
    }
    const oldFront = this.readerPageCurlFront;
    const oldBack = this.readerPageCurlBack;
    this.readerPageCurlFront = front;
    this.readerPageCurlBack = back;
    this.readerPageCurlSnapshotHeight = snapshotHeight;
    this.readerPageCurlCapturePending = false;
    this.readerPageCurlSnapshotReady = true;
    this.drawReaderPageCurl();
    // RenderService can still own the previous texture for the frame currently being submitted.
    // Releasing it in the same task intermittently invalidates that frame during rapid queued turns.
    setTimeout(() => {
      if (oldFront) oldFront.release().catch(() => {});
      if (oldBack) oldBack.release().catch(() => {});
    }, 48);
  }

  async cropReaderPageCurlFrontToTurningLeaf(front: image.PixelMap): Promise<void> {
    const info = await front.getImageInfo();
    const fullWidthPx = Math.max(1, info.size.width);
    const fullHeightPx = Math.max(1, info.size.height);
    const viewportWidth = Math.max(1, this.getPageTurnWidth());
    const leafWidth = Math.max(1, this.getReaderPageColumnWidth());
    const origin = this.pageSlideDirection > 0 ? this.getReaderDoublePageRightOrigin() : 0;
    const cropX = Math.max(0, Math.min(fullWidthPx - 1,
      Math.round(fullWidthPx * origin / viewportWidth)));
    const requestedWidth = Math.max(1, Math.round(fullWidthPx * leafWidth / viewportWidth));
    const cropWidth = Math.max(1, Math.min(requestedWidth, fullWidthPx - cropX));
    await front.crop({
      x: cropX,
      y: 0,
      size: {
        width: cropWidth,
        height: fullHeightPx
      }
    });
  }

  async ensureReaderPageCurlReady(): Promise<boolean> {
    if (!this.usesReaderPageCurlCanvas() || this.pageSlideDirection === 0) return false;
    this.requestReaderPageCurlCapture();
    let key = this.readerPageCurlCaptureKey;
    let keyChangeCount = 0;
    for (let attempt = 0; attempt < 120; attempt++) {
      if (this.pageSlideDirection === 0) return false;
      const latestKey = this.readerPageCurlCaptureKey;
      if (latestKey !== key) {
        // An uncached adjacent chapter first publishes a loading leaf and then replaces it with the prepared
        // destination page. That replacement deliberately starts a new capture with a new render-version key;
        // follow it instead of treating the valid cross-chapter handoff as a snapshot failure.
        key = latestKey;
        keyChangeCount++;
        if (keyChangeCount > 4) return false;
        attempt = 0;
      }
      const crossChapterPreviewLoading = this.pageTurnCrossChapterHandoff && !!this.pageTurnPreviewLoadingKey;
      const crossChapterPreviewReady = !this.pageTurnCrossChapterHandoff ||
        !!this.pageTurnIncomingDocumentSource;
      if (this.readerPageCurlSnapshotReady && key === this.readerPageCurlCaptureKey &&
        crossChapterPreviewReady) return true;
      // captureReaderPageCurlSnapshots clears the pending flag when the platform snapshot request fails.
      // Do not keep the turn locked for the remainder of the old 1.9s polling window after a terminal failure.
      // While an adjacent preview is still loading, a completed placeholder capture is not a terminal result:
      // applyPageTurnPreview will publish the real leaf and start the authoritative replacement capture.
      if (!this.readerPageCurlCapturePending && !crossChapterPreviewLoading) return false;
      await sleepMs(16);
    }
    return false;
  }

  async completeSimulationPageTurnMotion(direction: number): Promise<void> {
    const ready = await this.ensureReaderPageCurlReady();
    if (!ready) {
      // Snapshot services can be temporarily unavailable after foregrounding or during a rapid turn chain.
      // Preserve a visible, bounded transition instead of committing an apparently animation-less page.
      console.warn('仿真翻页快照未就绪，使用轻量过渡完成本次翻页');
      const fallbackOffset = direction > 0 ? -18 : 18;
      await this.runReaderAnimation(130, Curve.EaseOut, () => {
        this.pageTransitionX = fallbackOffset;
        this.pageTransitionOpacity = 0.18;
      });
      return;
    }
    const distance = this.getPageTurnDistance();
    const targetOffset = direction > 0 ? -distance : distance;
    const remaining = Math.abs(targetOffset - this.getPageSlideAxisOffset());
    if (this.is3DPageTurnAnimation() && !this.isLandscapeDoublePageActive()) {
      // 单页平折：时长按折页还要走的可见行程算，整页约 400ms；曲线接近匀速、收尾略缓，
      // 折线在后半程保持稳定的速度扫出左边缘，而不是先冲过大半程再停住。
      const releasedFraction = this.readerEmulationFlipPainter.flatRemainingFraction(this.getPageTurnWidth());
      const fraction = releasedFraction >= 0 ? releasedFraction : remaining / Math.max(1, distance);
      const flatDuration = Math.max(180, Math.round(400 * Math.pow(Math.max(0, fraction), 0.6)));
      await this.animateReaderPageCurlOffset(targetOffset, flatDuration, true, 'cubic-bezier(0.3, 0.4, 0.7, 1)');
      return;
    }
    // A long symmetric EaseInOut made the last part of the sheet appear to stop before the
    // incoming page was committed. Finish with a shorter, momentum-preserving edge motion.
    // 3D 仿真的纸角行程比位移长，同样的时长会显得一闪而过，给它更宽裕的补完时间。
    const fullDuration = this.is3DPageTurnAnimation() ? 460 : 340;
    const duration = Math.max(this.is3DPageTurnAnimation() ? 150 : 110,
      Math.min(fullDuration, Math.round(fullDuration * remaining / distance)));
    await this.animateReaderPageCurlOffset(targetOffset, duration, true);
  }

  resetReaderPageCurl(): void {
    this.readerEmulationFlipPainter.clearCorner();
    this.readerPageCurlCaptureSerial++;
    this.readerPageCurlCapturePending = false;
    this.readerPageCurlCaptureKey = '';
    this.readerPageCurlSnapshotReady = false;
    this.readerPageCurlAnimationSerial++;
    const activeAnimator = this.readerPageCurlAnimator;
    this.readerPageCurlAnimator = null;
    if (activeAnimator) activeAnimator.cancel();
    this.readerPageCurlOffset = 0;
    this.readerPageCurlSnapshotHeight = 0;
    const front = this.readerPageCurlFront;
    const back = this.readerPageCurlBack;
    this.readerPageCurlFront = null;
    this.readerPageCurlBack = null;
    // Keep the last raster alive for a few frames after hiding the curl Canvas. The RS submission is
    // asynchronous; a zero-delay release races its final draw and can expose a transient unformatted page.
    setTimeout(() => {
      if (front) front.release().catch(() => {});
      if (back) back.release().catch(() => {});
    }, 48);
  }

  animateReaderPageCurlOffset(targetOffset: number, duration: number,
    completingPageTurn: boolean = false, easing: string = ''): Promise<void> {
    const activeAnimator = this.readerPageCurlAnimator;
    this.readerPageCurlAnimator = null;
    if (activeAnimator) activeAnimator.cancel();
    const serial = ++this.readerPageCurlAnimationSerial;
    const startOffset = this.getPageSlideAxisOffset();
    return new Promise<void>((resolve) => {
      let settled = false;
      let watchdogId = -1;
      const settle = (): void => {
        if (settled) return;
        settled = true;
        if (watchdogId >= 0) clearTimeout(watchdogId);
        resolve();
      };
      let pageCurlAnimator: AnimatorResult;
      try {
        pageCurlAnimator = Animator.create({
          duration: Math.max(1, duration),
          easing: easing ? easing : (completingPageTurn ? 'cubic-bezier(0.18, 0.68, 0.32, 0.98)' :
            'cubic-bezier(0.65, 0, 0.35, 1)'),
          delay: 0,
          fill: 'forwards',
          direction: 'normal',
          iterations: 1,
          begin: startOffset,
          end: targetOffset
        });
      } catch (error) {
        console.warn('创建仿真翻页动画失败，提交目标帧:', error);
        this.setPageSlideAxisOffset(targetOffset);
        settle();
        return;
      }
      this.readerPageCurlAnimator = pageCurlAnimator;
      pageCurlAnimator.onFrame = (value: number): void => {
        if (serial !== this.readerPageCurlAnimationSerial) return;
        this.setPageSlideAxisOffset(value);
      };
      pageCurlAnimator.onFinish = (): void => {
        if (serial === this.readerPageCurlAnimationSerial) {
          this.setPageSlideAxisOffset(targetOffset);
          this.readerPageCurlAnimator = null;
        }
        settle();
      };
      pageCurlAnimator.onCancel = (): void => {
        if (this.readerPageCurlAnimator === pageCurlAnimator) this.readerPageCurlAnimator = null;
        settle();
      };
      // A few platform versions can lose Animator.onFinish after the window is resumed. Do not leave page-turn
      // input locked indefinitely; commit the exact target frame shortly after the declared duration.
      watchdogId = setTimeout(() => {
        if (serial === this.readerPageCurlAnimationSerial) {
          this.setPageSlideAxisOffset(targetOffset);
          if (this.readerPageCurlAnimator === pageCurlAnimator) this.readerPageCurlAnimator = null;
        }
        settle();
      }, Math.max(1, duration) + 96);
      try {
        pageCurlAnimator.play();
      } catch (error) {
        console.warn('启动仿真翻页动画失败，提交目标帧:', error);
        this.setPageSlideAxisOffset(targetOffset);
        settle();
      }
    });
  }

  getSimulationSpineColor(): string {
    return this.isReaderThemeDark() ? '#66000000' : '#36000000';
  }

  getPageTurnDistance(): number {
    return this.isVerticalPageTurnAnimation() ? this.getPageTurnHeight() : this.getPageTurnWidth();
  }

  getPageSlideAxisOffset(): number {
    if (this.usesReaderPageCurlCanvas()) return this.readerPageCurlOffset;
    return this.isVerticalPageTurnAnimation() ? this.pageSlideOffsetY : this.pageSlideOffsetX;
  }

  setPageSlideAxisOffset(offset: number): void {
    if (this.usesReaderPageCurlCanvas()) {
      this.readerPageCurlOffset = offset;
      this.drawReaderPageCurl();
      return;
    }
    if (this.isVerticalPageTurnAnimation()) {
      this.pageSlideOffsetX = 0;
      this.pageSlideOffsetY = offset;
      this.drawReaderPageCurl();
      return;
    }
    this.pageSlideOffsetX = offset;
    this.pageSlideOffsetY = 0;
    this.drawReaderPageCurl();
  }

  shouldRenderSlidingPageTurn(): boolean {
    return this.isPageTurnAnimationEnabled() && this.pageSlideDirection !== 0 &&
      (this.pageTurnAnimating || this.canTurnPage(this.pageSlideDirection));
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
    const type = this.effectivePageTurnAnimationType();
    // 淡入原地淡出、叠页与 3D 仿真都由各自的动画层接管视觉位移，当前页不再做水平平移。
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE ||
      type === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK ||
      type === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D) {
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
    const type = this.effectivePageTurnAnimationType();
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
    const type = this.effectivePageTurnAnimationType();
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE) {
      return Math.max(0.12, 1 - this.getPageTurnProgress());
    }
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return 1;
    }
    if (this.usesReaderPageCurlCanvas() && !this.isLandscapeDoublePageActive()) {
      // 卷曲类型由画布上的快照绘制纸张,实时页面必须让位,否则会与快照叠出重影(官方示例同样会隐藏当前页)。
      // 快照就绪前保持可见,避免空白帧;双页时左列仍需实时页面,故不在此隐藏。
      return this.readerPageCurlSnapshotReady ? 0 : this.pageTransitionOpacity;
    }
    return this.pageTransitionOpacity;
  }

  getSlideIncomingX(direction: number, offsetX: number, width: number = this.getPageTurnWidth()): number {
    const type = this.effectivePageTurnAnimationType();
    // 仿真与 3D 仿真都让目标页固定铺满窗口，由卷曲画布或 3D 翻转层负责过渡。
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION ||
      type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE ||
      type === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D) {
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
    const type = this.effectivePageTurnAnimationType();
    if (type === ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION ||
      type === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE ||
      type === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D) {
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
    this.resetReaderPageCurl();
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
    this.pageTurnCrossChapterHandoff = false;
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
        const stageError = AppStorage.get<string>('bookSourceStageLastError') || '';
        if (stageError) text += `\n诊断：${stageError}`;
      }
    }
    return text;
  }

  async jumpToAdjacentChapterFirstPage(direction: number): Promise<void> {
    // Reopening the currently narrated book creates a new reader page while the hidden
    // original page still owns TTS. Route the chapter bar command to that owner; changing
    // only this mirrored page is immediately overwritten by the owner's position update.
    if (this.isMirroringActiveTtsForCurrentBook()) {
      if (direction < 0 && !this.globalTtsCanPrevious) {
        HdsFeedback.showToast('已经是第一章');
        return;
      }
      if (direction > 0 && !this.globalTtsCanNext) {
        HdsFeedback.showToast('本书已阅读完成');
        return;
      }
      if (direction > 0) {
        ReaderTtsFloatingSession.next();
      } else {
        ReaderTtsFloatingSession.previous();
      }
      return;
    }
    const targetChapterIndex = this.currentChapterIndex + (direction > 0 ? 1 : -1);
    if (targetChapterIndex < 0) {
      HdsFeedback.showToast('已经是第一章');
      return;
    }
    if (targetChapterIndex >= this.chapters.length) {
      HdsFeedback.showToast('本书已阅读完成');
      return;
    }

    const shouldResumeTts = this.isTtsSpeaking || this.ttsReader.isSpeaking();
    if (shouldResumeTts) {
      this.stopTtsReaderForChapterSwitch();
      await this.ttsMediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING);
    }
    this.finishPageTurnAnimation();
    this.isLoading = true;
    this.loadStatus = '正在切换章节...';
    await sleepMs(0);
    try {
      this.currentPageIndex = 0;
      this.pendingRestorePageIndex = 0;
      await this.loadContent(true, targetChapterIndex, true);
      if (this.currentChapterIndex !== targetChapterIndex) {
        return;
      }

      this.currentPageIndex = 0;
      this.pendingRestorePageIndex = -1;
      const targetPageText = this.contentPages[0] || this.content || '';
      this.setCurrentPageText(targetPageText);
      this.finishPageTurnAnimation();
      this.refreshReaderTextRender();
      await sleepMs(16);
    } finally {
      this.isLoading = false;
      this.loadStatus = '';
    }
    this.saveReadingProgress();
    if (shouldResumeTts) {
      await this.startTtsReadingFromCurrentPosition(false);
    }
  }

  async loadNextChapter(showLoading: boolean = false, showBoundaryToast: boolean = false): Promise<void> {
    if (this.currentChapterIndex >= this.chapters.length - 1) {
      if (showBoundaryToast) {
        HdsFeedback.showToast('本书已阅读完成');
      }
      return;
    }
    const targetChapterIndex = this.currentChapterIndex + 1;
    const previousPageIndex = this.currentPageIndex;
    this.currentPageIndex = 0;
    this.pendingRestorePageIndex = 0;
    const loaded = await this.loadContent(!showLoading, targetChapterIndex, true);
    if (!loaded) {
      // 章节提交前加载失败（或序列竞争）：不能把用户留在永不落地的“恢复进度”遮罩上，
      // 回退到原章节原页并释放恢复标志。
      if (this.currentChapterIndex !== targetChapterIndex) {
        this.currentPageIndex = previousPageIndex;
      }
      this.pendingRestorePageIndex = -1;
      return;
    }
    this.saveReadingProgress();
  }

  async loadPrevChapter(toLastPage: boolean = false, showLoading: boolean = false,
    showBoundaryToast: boolean = false): Promise<void> {
    if (this.currentChapterIndex <= 0) {
      if (showBoundaryToast) {
        HdsFeedback.showToast('已经是第一章');
      }
      return;
    }
    const targetChapterIndex = this.currentChapterIndex - 1;
    const previousPageIndex = this.currentPageIndex;
    this.currentPageIndex = 0;
    this.pendingRestorePageIndex = toLastPage ? Number.MAX_SAFE_INTEGER : 0;
    const loaded = await this.loadContent(!showLoading, targetChapterIndex);
    if (!loaded) {
      if (this.currentChapterIndex !== targetChapterIndex) {
        this.currentPageIndex = previousPageIndex;
      }
      this.pendingRestorePageIndex = -1;
      return;
    }
    this.saveReadingProgress();
  }
}
