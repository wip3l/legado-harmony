import { router, promptAction } from '@kit.ArkUI';
import { BookSource, SearchBook, BookListRule, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { HttpClient, HttpResponse } from '../core/http/HttpClient';
import { RawHttpTextClient } from '../core/http/RawHttpTextClient';
import { SearchCoordinator, SearchProgress, SearchSourceResult } from '../core/book/SearchCoordinator';
import { syncSystemBars } from '../utils/SystemBars';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { BookSourceStageRuntimeHost } from '../components/BookSourceStageRuntimeHost';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { VerificationSupport } from '../core/http/VerificationSupport';
import { CookieStore } from '../core/http/CookieStore';
import { TlsTrustStore } from '../core/http/TlsTrustStore';
import { BookSourceGroupStore } from '../utils/BookSourceGroupStore';
import { ResponsiveManagerListLayout } from '../utils/ResponsiveManagerListLayout';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { VirtualListScrollbar } from '../utils/VirtualListScrollbar';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import commonEventManager from '@ohos.commonEventManager';
import { BookSourceLoginItem, BookSourceScriptRunner } from '../core/book/BookSourceScriptRunner';
import { BookSourceLoginWebRuntime, LoginCookieOperation, LoginRuntimeStep } from '../core/book/BookSourceLoginWebRuntime';
import { BookSourceLoginCrypto } from '../core/book/BookSourceLoginCrypto';
import { BookSourceExecutionJournal } from '../core/book/BookSourceExecutionJournal';
import {
  BookSourceRuntimeRouter,
  SourceRuntimeDecision,
  SourceRuntimeStage
} from '../core/book/BookSourceRuntimeRouter';
import { AnalyzeUrl } from '../core/rule/AnalyzeUrl';
import { ExploreResultCache } from '../utils/ExploreResultCache';
import {
  ExploreReadingValidationProgress,
  ExploreReadingValidationResult,
  ExploreReadingValidator
} from '../core/book/ExploreReadingValidator';

const BOOK_SOURCE_IMPORT_FILE_LIMIT_BYTES = 25 * 1024 * 1024;
const BOOK_SOURCE_IMPORT_TIMEOUT_MS = 20000;
const BOOK_SOURCE_IMPORT_URL_RETRY_COUNT = 3;
const BOOK_SOURCE_WEB_IMPORT_RETRY_COUNT = 3;
const BOOK_SOURCE_CHECK_KEYWORD = '斗破苍穹';
const BOOK_SOURCE_CHECK_CANCEL_EVENT: string = 'com.legado.harmony.action.BOOK_SOURCE_CHECK_CANCEL';
const BOOK_SOURCE_CHECK_NOTIFICATION_INTERVAL_MS: number = 1000;
const BOOK_SOURCE_CHECK_NOTIFICATION_ID: number = 2701;

class BookSourceListDataSource implements IDataSource {
  private sources: BookSource[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.sources.length; }
  getData(index: number): BookSource { return this.sources[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(sources: BookSource[], force: boolean = false): void {
    if (!force && this.sources.length === sources.length &&
      this.sources.every((source: BookSource, index: number) => source === sources[index])) return;
    this.sources = [...sources];
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

class BookSourceCheckUiUpdate {
  bookSourceUrl: string = '';
  validationStatus: number = BookSource.VALIDATION_UNCHECKED;
  detail: string = '';
}

@Entry
@Component
struct BookSourcePage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('pendingBookSourceImportNonce') @Watch('onPendingBookSourceImportChanged')
  pendingBookSourceImportNonce: number = 0;
  @StorageLink('bookSourceCheckOpenNonce') @Watch('onBookSourceCheckOpenRequested')
  bookSourceCheckOpenNonce: number = 0;
  @State allSources: BookSource[] = [];
  @State sources: BookSource[] = [];
  @State visibleSources: BookSource[] = [];
  private sourceListDataSource: BookSourceListDataSource = new BookSourceListDataSource();
  @State sourceListViewportHeight: number = 0;
  @State sourceFirstVisibleIndex: number = 0;
  @State sourceVisibleItemCount: number = 1;
  @State sourceScrollbarDragging: boolean = false;
  @State sourceScrollbarDragOffset: number = 0;
  @State sourceGroups: string[] = [];
  @State isLoading: boolean = false;
  @State searchText: string = '';
  @State activeSourceGroup: string = '__all__';
  @State showSourceFilterDialog: boolean = false;
  @State sourceEnabledFilter: string = 'all';
  @State sourceExplorePageFilter: string = 'all';
  @State sourceExploreEnabledFilter: string = 'all';
  @State sourceLoginFilter: string = 'all';
  @State sourceValidationFilter: string = 'all';
  @State sourceSortMode: string = 'custom';
  @State showAddDialog: boolean = false;
  @State showImportUrlDialog: boolean = false;
  @State showImportSourceSelectionDialog: boolean = false;
  @State pendingImportSources: BookSource[] = [];
  @State selectedImportSourceUrls: string[] = [];
  @State selectionMode: boolean = false;
  @State selectedSourceUrls: string[] = [];
  @State showBatchDeleteDialog: boolean = false;
  @State showGroupDialog: boolean = false;
  @State showMoreActionDialog: boolean = false;
  @State showSourceActionDialog: boolean = false;
  @State showSourceLoginUiDialog: boolean = false;
  @State sourceLoginItems: BookSourceLoginItem[] = [];
  @State isExecutingLoginAction: boolean = false;
  @State loginRuntimeActive: boolean = false;
  @State showSourceDeleteDialog: boolean = false;
  @State showSourceGroupToolsMenu: boolean = false;
  @State showSourceGroupActionMenu: boolean = false;
  @State showRenameSourceGroupDialog: boolean = false;
  @State showDeleteSourceGroupDialog: boolean = false;
  @State showAddSourceGroupDialog: boolean = false;
  @State showSourceGroupManagerDialog: boolean = false;
  @State showDeleteSelectedSourceGroupsDialog: boolean = false;
  @State selectedManagedSourceGroups: string[] = [];
  @State pendingSourceGroup: string = '';
  @State renameSourceGroupInput: string = '';
  @State newSourceGroupInput: string = '';
  @State actionSourceUrl: string = '';
  @State actionSourceDetail: BookSource | null = null;
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State groupNameInput: string = '';
  @State groupActionSourceUrl: string = '';
  @State draggingSourceUrl: string = '';
  @State importUrl: string = '';
  @State isImporting: boolean = false;
  @State isBatchOperating: boolean = false;
  @State batchOperationText: string = '正在操作书源...';
  @State showCheckDialog: boolean = false;
  @State showCheckOptionsDialog: boolean = false;
  @State isCheckingSources: boolean = false;
  @State checkDone: number = 0;
  @State checkTotal: number = 0;
  @State checkOkCount: number = 0;
  @State checkFailedCount: number = 0;
  @State checkNoResultCount: number = 0;
  @State checkNeedVerificationCount: number = 0;
  @State checkTemporaryErrorCount: number = 0;
  @State checkBadUrls: string[] = [];
  @State checkResultDetails: string[] = [];
  @State checkTlsTrustHosts: string[] = [];
  @State checkTlsRetrySourceUrls: string[] = [];
  @State checkStatus: string = '';
  @State checkInvalidAction: string = 'none';
  @State checkValidationMode: string = 'search';
  @State checkAutoHandledCount: number = 0;
  @State checkBackgroundMode: boolean = false;
  @State webImportActive: boolean = false;
  private sourceListScroller: Scroller = new Scroller();
  private sourceScrollbarPointerAnchor: number = 0;
  private sourceScrollbarPendingIndex: number = -1;
  private sourceScrollbarUpdateTimer: number = -1;
  private hasShownOnce: boolean = false;
  private sourceOrderSaving: boolean = false;
  private checkCoordinator: SearchCoordinator | null = null;
  private checkExploreValidator: ExploreReadingValidator | null = null;
  private checkTaskSerial: number = 0;
  private checkNotificationLastAt: number = 0;
  private checkBackgroundRunning: boolean = false;
  private checkCancelAgent: WantAgent | null = null;
  private checkCancelSubscriber: commonEventManager.CommonEventSubscriber | null = null;
  private checkUiUpdates: BookSourceCheckUiUpdate[] = [];
  private checkUiFlushTimer: number = -1;
  private pageVisible: boolean = true;
  private selectedSourceUrlsSnapshot: string[] = [];
  private selectedSourceUrlLookup: Set<string> = new Set<string>();
  private sourceSelectionAreas: Map<string, number[]> = new Map<string, number[]>();
  private sourceDragVisited: Set<string> = new Set<string>();
  private sourceDragSelectValue: boolean = true;
  private sourceSelectionDragging: boolean = false;
  private sourceSelectionLastX: number = 0;
  private sourceSelectionLastY: number = 0;
  private sourceSelectionAutoScrollId: number = -1;
  private sourceSelectionAutoDirection: number = 0;
  private sourceSelectionViewportTop: number = 0;
  private sourceSelectionViewportBottom: number = 0;
  private sourceSelectionSuppressClickUntil: number = 0;
  private webImportController: webview.WebviewController = new webview.WebviewController();
  private webImportTargetUrl: string = '';
  private webImportStarted: boolean = false;
  private webImportResolve: ((value: string) => void) | null = null;
  private webImportReject: ((reason: Error) => void) | null = null;
  private webImportTimeoutId: number = -1;
  private webImportDownloadDelegate: webview.WebDownloadDelegate | null = null;
  private webImportDownloadItem: webview.WebDownloadItem | null = null;
  private webImportDownloadPath: string = '';
  private loginRuntimeController: webview.WebviewController = new webview.WebviewController();
  private loginRuntimeSource: BookSource | null = null;
  private loginRuntimeBaseSource: BookSource | null = null;
  private loginRuntimeAction: string = '';
  private loginRuntimeJournal: BookSourceExecutionJournal = new BookSourceExecutionJournal();
  private loginRuntimeDecision: SourceRuntimeDecision | null = null;
  private loginRuntimeCookies: Record<string, string> = {};
  private loginRuntimeCookieUrls: string[] = [];
  private loginRuntimeRequestCount: number = 0;
  private loginRuntimeFixedNow: number = 0;
  private loginRuntimeRandomSeed: number = 1;
  private loginRuntimeCookieSnapshots: Record<string, string> = {};
  private loginRuntimeAwaitingBrowser: boolean = false;
  private loginRuntimeBrowserToken: string = '';
  private loginRuntimeBrowserUrl: string = '';
  private loginRuntimeStepRunning: boolean = false;
  private loginRuntimeReady: boolean = false;
  private loginRuntimeResolve: ((value: LoginRuntimeStep) => void) | null = null;
  private loginRuntimeReject: ((reason: Error) => void) | null = null;
  private loginRuntimeTimeoutId: number = -1;
  private loginRuntimeWebViewPageResolve: (() => void) | null = null;
  private pendingOpenLoginSourceUrl: string = '';
  private pendingOpenLoginHandled: boolean = false;

  aboutToAppear() {
    this.syncBars();
    const params = router.getParams() as Record<string, string>;
    this.pendingOpenLoginSourceUrl = params ? String(params['openLoginSourceUrl'] || '').trim() : '';
    this.pendingOpenLoginHandled = false;
    this.loadSources().then(() => {
      return this.openPendingReaderSourceLogin();
    }).catch((error: Error) => {
      console.warn('从阅读页打开书源登录失败:', error);
    });
    this.handlePendingBookSourceImport();
    this.ensureBookSourceCheckCancelSubscriber();
    this.resumeLoginRuntimeBrowserAwait();
  }

  aboutToDisappear(): void {
    this.stopSourceSelectionAutoScroll();
    this.finishWebImport('', '网页取数已取消');
    if (!this.loginRuntimeAwaitingBrowser) {
      this.finishLoginRuntime(null, '登录动作已取消');
    }
    if (!this.isCheckingSources) {
      this.releaseBookSourceCheckCancelSubscriber();
    }
  }

  onPendingBookSourceImportChanged(): void {
    this.handlePendingBookSourceImport();
  }

  onBookSourceCheckOpenRequested(): void {
    if (this.isCheckingSources || this.checkBackgroundMode) {
      this.showCheckDialog = true;
    }
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.syncBars();
    this.resumeLoginRuntimeBrowserAwait();
    this.handlePendingBookSourceImport();
    if (!this.hasShownOnce) {
      this.hasShownOnce = true;
      return;
    }
    this.refreshSources();
  }

  onPageHide(): void {
    this.stopSourceSelectionAutoScroll();
    this.pageVisible = false;
    if (!this.isCheckingSources) {
      this.releaseBookSourceCheckCancelSubscriber();
    }
  }

  async refreshSources(): Promise<void> {
    await this.loadSources();
  }

  async loadSources() {
    this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.allSources = await db.getBookSourceSummaries();
      this.sourceGroups = await BookSourceGroupStore.load(getContext(this), this.sourceGroupsFromSources());
      this.ensureActiveSourceGroup();
      this.applySourceFilters();
    } catch (e) {
      console.error('加载书源失败:', e);
    } finally {
      this.isLoading = false;
    }
  }

  async openPendingReaderSourceLogin(): Promise<void> {
    if (this.pendingOpenLoginHandled || !this.pendingOpenLoginSourceUrl) return;
    this.pendingOpenLoginHandled = true;
    const sourceUrl = this.pendingOpenLoginSourceUrl;
    this.pendingOpenLoginSourceUrl = '';
    const source = await AppDatabase.getInstance().getBookSource(sourceUrl);
    if (!source || !this.sourceNeedsLogin(source)) {
      promptAction.showToast({ message: '未找到可用的书源登录配置' });
      return;
    }
    this.actionSourceUrl = source.bookSourceUrl;
    this.actionSourceDetail = source;
    await this.openActionSourceLogin();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      WebBookFetchRuntimeHost()
      Column() {
        Column() {
          Row() {
            TextInput({ placeholder: '搜索书源', text: this.searchText })
              .layoutWeight(1)
              .height(40)
              .borderRadius(20)
              .backgroundColor(this.glassInputColor())
              .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
              .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.placeholderTextColor())
              .padding({ left: 16, right: 16 })
              .onChange((value: string) => {
                this.searchText = value;
                this.searchSources();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })

          if (!this.selectionMode) {
            this.sourceGroupBar()
          }

          if (this.selectionMode) {
            Row() {
              Text(this.isAllSelected() ? '☑' : '☐')
                .fontSize(20)
                .fontColor(this.accentColor())
                .width(28)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  if (this.isBatchOperating) {
                    return;
                  }
                  this.toggleAllSources();
                })

              Text(`已选择 ${this.selectedSourceUrls.length}/${this.allSources.length}`)
                .fontSize(14)
                .fontColor(this.secondaryTextColor())
                .margin({ left: 8 })
                .layoutWeight(1)

              Text(this.isAllSelected() ? '取消全选' : '全选')
                .fontSize(14)
                .fontColor(this.isBatchOperating ? this.subTextColor() : this.accentColor())
                .onClick(() => {
                  if (this.isBatchOperating) {
                    return;
                  }
                  this.toggleAllSources();
                })
            }
            .width('100%')
            .height(42)
            .padding({ left: 16, right: 16 })
          }
        }
        .width('100%')
        .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
        .backdropBlur(ThemeRuntime.topBarBlur())
        .zIndex(2)

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
            Text('加载中...')
              .fontSize(14)
              .fontColor(this.subTextColor())
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.sources.length === 0) {
          Column() {
            Text(this.emptySourceTitle())
              .fontSize(16)
              .fontColor(this.subTextColor())
            Text(this.emptySourceDescription())
              .fontSize(14)
              .fontColor(this.subTextColor())
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Stack({ alignContent: Alignment.TopEnd }) {
            List({ space: 8, scroller: this.sourceListScroller }) {
            ListItem() {
              Row()
                .height(this.sourceListTopInset())
                .hitTestBehavior(HitTestMode.None)
            }

            LazyForEach(this.currentSourceListDataSource(), (source: BookSource) => {
              if (deviceInfo.sdkApiVersion >= 26) {
                HdsListItem({
                  customItemBuilder: () => {
                    this.sourceSwipeCard(source)
                  },
                  swipeActionOptions: this.sourceSwipeActions(source)
                })
              }
              if (deviceInfo.sdkApiVersion < 26) {
              ListItem() {
                Row() {
                  if (this.selectionMode) {
                    this.sourceSelectionSafeArea(source)
                  }

                  if (!this.selectionMode) {
                    Stack({ alignContent: Alignment.Center }) {
                      Text('☰')
                        .fontSize(18)
                        .fontColor(this.subTextColor())
                    }
                    .width(52)
                    .height(56)
                    .margin({ left: -8, right: 4 })
                    .hitTestBehavior(HitTestMode.Transparent)
                    .accessibilityText(`长按拖动排序：${source.bookSourceName}`)
                  }

                  Column() {
                    Row() {
                      Text(source.bookSourceName)
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.primaryTextColor())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)

                      if (source.isPinned) {
                        this.sourceStatusIcon($r('sys.symbol.pin'), this.accentColor(), '已置顶')
                      }
                      if (this.isSourceAtBottom(source)) {
                        this.sourceOrderStatusBadge('尾', '已置尾')
                      }

                      if (source.bookSourceGroup) {
                        Text(source.bookSourceGroup)
                          .fontSize(11)
                          .fontColor(this.accentColor())
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .constraintSize({ maxWidth: 72 })
                          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                          .backgroundColor(this.inputColor())
                          .borderRadius(4)
                          .margin({ left: 6 })
                      }

                      if (this.sourceNeedsLogin(source)) {
                        this.sourceLoginStatusBadge(
                          this.sourceLoggedIn(source) ? '#1E8E3E' : '#C62828',
                          this.sourceLoggedIn(source) ? '已登录' : '未登录')
                      }
                      if (source.isLocked) {
                        this.sourceStatusIcon($r('sys.symbol.lock'), this.accentColor(), '已锁定')
                      }
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)

                    Row({ space: 7 }) {
                      this.sourceValidationStatusBadge(source.validationStatus)
                      Text(source.bookSourceUrl)
                        .fontSize(12)
                        .fontColor(this.subTextColor())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .margin({ top: 4 })
                    .alignItems(VerticalAlign.Center)

                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .gesture(
                    LongPressGesture({ repeat: false })
                      .onAction((event: GestureEvent) => {
                        if (!this.selectionMode && !this.isBatchOperating) {
                          this.openSourceActions(source, event);
                        }
                      })
                  )

                  if (this.selectionMode) {
                    Column() {
                      Text(source.enabled ? '已启用' : '已禁用')
                        .fontSize(12)
                        .fontColor(source.enabled ? '#1E8E3E' : this.subTextColor())
                      Text(source.enabledExplore ? '发现已启用' : '发现已禁用')
                        .fontSize(12)
                        .fontColor(source.enabledExplore ? '#1E8E3E' : this.subTextColor())
                        .margin({ top: 4 })
                    }
                    .alignItems(HorizontalAlign.End)
                  }
                  if (!this.selectionMode && !source.isLocked && deviceInfo.sdkApiVersion < 26) {
                    Row({ space: 4 }) {
                      Button(source.enabled ? '禁用' : '启用').fontSize(11).width(60).height(30)
                        .fontColor('#FFFFFF').backgroundColor(this.buttonColor())
                        .onClick(() => this.toggleSourceEnabled(source))
                      Button('删除').fontSize(11).width(60).height(30)
                        .fontColor('#FFFFFF').backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
                        .onClick(() => this.deleteSourceFromSwipe(source))
                    }
                    .margin({ left: 8 })
                  }
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.glassCardColor())
                .borderRadius(8)
                .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
                .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
                .opacity(source.enabled ? 1 : 0.45)
                .onClick(() => {
                  if (this.isBatchOperating) {
                    return;
                  }
                  if (this.selectionMode) {
                    if (Date.now() < this.sourceSelectionSuppressClickUntil) return;
                    this.toggleSourceSelected(source.bookSourceUrl);
                  }
                })
              }
              .width('100%')
              .borderRadius(8)
              .clip(true)
              .onAreaChange((_oldValue: Area, area: Area) => {
                if (this.selectionMode) this.rememberSourceSelectionArea(source.bookSourceUrl, area);
              })
              .swipeAction(this.selectionMode || source.isLocked ? {} : {
                end: {
                  builder: this.sourceDeleteSwipeAction.bind(this, source),
                  actionAreaDistance: 64,
                  onAction: () => {
                    if (!this.selectionMode && !this.isBatchOperating) this.deleteSourceFromSwipe(source);
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
              }
            }, (source: BookSource) => this.sourceListItemKey(source))

            ListItem() {
              Row()
                .height(Math.max(20, this.navBarHeight + 12))
            }
            }
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .width('100%')
            .height('100%')
            .padding({ left: 16, right: 16 })
            .lanes(ResponsiveManagerListLayout.laneCount(this.contextViewportWidth),
              ResponsiveManagerListLayout.gutter(this.contextViewportWidth))
            .scrollBar(BarState.Off)
            .cachedCount(8)
            .clip(true)
            .onScrollIndex((start: number, end: number) => {
              this.sourceFirstVisibleIndex = Math.max(0, start - 1);
              this.sourceVisibleItemCount = Math.max(1, end - start + 1);
            })
            .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => {
              const sourceIndex = itemIndex - 1;
              this.draggingSourceUrl = !this.selectionMode && sourceIndex >= 0 &&
                sourceIndex < this.visibleSources.length ? this.visibleSources[sourceIndex].bookSourceUrl : '';
              return this.sourceDragPreview;
            })
            .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
              if (isSuccess && this.draggingSourceUrl) {
                this.moveVisibleSourceTo(itemIndex - 1, Math.max(0, insertIndex - 1));
              }
              this.draggingSourceUrl = '';
            })

            this.sourceVirtualScrollbar()
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ top: -this.sourceListTopInset() })
          .zIndex(0)
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.sourceListViewportHeight = Number(newValue.height);
            this.sourceSelectionViewportTop = Number(newValue.globalPosition.y);
            this.sourceSelectionViewportBottom = this.sourceSelectionViewportTop + Number(newValue.height);
          })
        }

        if (this.selectionMode) {
          Row() {
            Button('启用')
              .layoutWeight(1)
              .height(42)
              .enabled(this.selectedSourceUrls.length > 0 && !this.isBatchOperating)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.batchSetEnabled(true);
              })

            Button('禁用')
              .layoutWeight(1)
              .height(42)
              .margin({ left: 8 })
              .enabled(this.selectedSourceUrls.length > 0 && !this.isBatchOperating)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.batchSetEnabled(false);
              })

            Button('分组')
              .layoutWeight(1)
              .height(42)
              .margin({ left: 8 })
              .enabled(this.selectedSourceUrls.length > 0 && !this.isBatchOperating)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.groupNameInput = this.commonSelectedGroupName();
                this.showGroupDialog = true;
              })

            Button('更多')
              .layoutWeight(1)
              .height(42)
              .margin({ left: 8 })
              .enabled(this.selectedSourceUrls.length > 0 && !this.isBatchOperating)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.showMoreActionDialog = true;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 12 })
          .backgroundColor(this.glassCardColor())
          .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 56 + this.statusBarHeight })
      .backgroundColor(this.pageColor())

      this.bookSourceTitleBar()

      if (!this.selectionMode && !this.showAddDialog && !this.isImporting && !this.isBatchOperating) {
        this.addSourceFloatingButton()
      }

      if (this.showAddDialog) {
        this.addSourceDropdown()
      }

      if (this.showImportUrlDialog) {
        Column() {
          Column() {
            Text('从URL导入')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 16 })

            TextInput({ placeholder: '请输入书源URL', text: this.importUrl })
              .width('100%')
              .height(48)
              .borderRadius(8)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.placeholderTextColor())
              .padding({ left: 12, right: 12 })
              .margin({ bottom: 16 })
              .onChange((value: string) => {
                this.importUrl = value;
              })

            Row() {
              Button('取消')
                .width('45%')
                .height(44)
                .backgroundColor(this.inputColor())
                .fontColor(this.primaryTextColor())
                .onClick(() => {
                  this.showImportUrlDialog = false;
                  this.importUrl = '';
                })

              Button('导入')
                .width('45%')
                .height(44)
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.importFromUrl();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('90%')
          .padding(24)
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showImportUrlDialog = false;
        })
      }

      if (this.showImportSourceSelectionDialog) {
        this.importSourceSelectionDialog()
      }

      if (this.showBatchDeleteDialog) {
        Column() {
          Column() {
            Text('确认删除')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            Text(`确定删除已选择的 ${this.selectedSourceUrls.length} 个书源吗？删除后不可恢复。`)
              .fontSize(15)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 20 })

            Row() {
              Button('取消')
                .width('45%')
                .height(44)
                .backgroundColor(this.inputColor())
                .fontColor(this.primaryTextColor())
                .onClick(() => {
                  this.showBatchDeleteDialog = false;
                })

              Button('删除')
                .width('45%')
                .height(44)
                .backgroundColor('#E53935')
                .onClick(() => {
                  this.showBatchDeleteDialog = false;
                  this.batchDeleteSelectedSources();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('85%')
          .padding(24)
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showBatchDeleteDialog = false;
        })
      }

      if (this.showGroupDialog) {
        Column() {
          Column() {
            Text('设置书源分组')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            Text(this.groupActionSourceUrl ? `书源：${this.actionGroupingSourceName()}` :
              `已选择 ${this.selectedSourceUrls.length} 个书源`)
              .fontSize(13)
              .fontColor(this.subTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 14 })

            TextInput({ placeholder: '输入新分组名称，留空为未分组', text: this.groupNameInput })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.placeholderTextColor())
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.groupNameInput = value;
              })

            if (this.getSourceGroups().length > 0) {
              Scroll() {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.getSourceGroups(), (group: string) => {
                    Text(group)
                      .fontSize(13)
                      .fontColor(this.secondaryTextColor())
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .backgroundColor(this.inputColor())
                      .borderRadius(14)
                      .margin({ right: 8, top: 10 })
                      .onClick(() => {
                        this.groupNameInput = group;
                      })
                  })
                }
                .width('100%')
              }
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
              .width('100%')
              .constraintSize({ maxHeight: 240 })
              .scrollBar(BarState.Auto)
            }

            Row() {
              Button('取消')
                .width('45%')
                .height(44)
                .backgroundColor(this.inputColor())
                .fontColor(this.primaryTextColor())
                .onClick(() => {
                  this.closeSourceGroupDialog();
                })

              Button('保存')
                .width('45%')
                .height(44)
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.applySelectedSourceGroup();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 18 })
          }
          .width('88%')
          .constraintSize({ maxHeight: '78%' })
          .padding(24)
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.closeSourceGroupDialog();
        })
      }

      if (this.showMoreActionDialog) {
        this.batchMorePopupMenu()
      }

      if (this.showSourceGroupActionMenu) {
        this.sourceGroupActionMenu()
      }

      if (this.showSourceGroupToolsMenu) {
        this.sourceGroupToolsMenu()
      }

      if (this.showSourceGroupManagerDialog) {
        this.sourceGroupManagerDialog()
      }

      if (this.showRenameSourceGroupDialog) {
        this.renameSourceGroupDialog()
      }

      if (this.showDeleteSourceGroupDialog) {
        this.deleteSourceGroupDialog()
      }

      if (this.showDeleteSelectedSourceGroupsDialog) {
        this.deleteSelectedSourceGroupsDialog()
      }

      if (this.showAddSourceGroupDialog) {
        this.addSourceGroupDialog()
      }

      if (this.showSourceFilterDialog) {
        this.sourceFilterDialog()
      }

      if (this.showCheckOptionsDialog) {
        this.checkOptionsDialog()
      }

      if (this.showSourceActionDialog) {
        this.sourceActionDialog()
      }

      if (this.showSourceLoginUiDialog) {
        this.sourceLoginUiDialog()
      }

      if (this.showSourceDeleteDialog) {
        this.sourceDeleteDialog()
      }

      if (this.showCheckDialog) {
        Column() {
          Column() {
            Text(this.isCheckingSources ? '正在校验书源' : '校验完成')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            if (this.isCheckingSources) {
              LoadingProgress()
                .width(42)
                .height(42)
                .color(this.accentColor())
                .margin({ bottom: 12 })
            }

            Text(this.checkDialogStatusText())
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            Progress({ value: this.checkDone, total: Math.max(this.checkTotal, 1), type: ProgressType.Linear })
              .width('100%')
              .height(8)
              .color(this.buttonColor())
              .backgroundColor(this.inputColor())
              .margin({ bottom: 12 })

            Text(`${this.checkDone}/${this.checkTotal}`)
              .fontSize(13)
              .fontColor(this.subTextColor())
              .margin({ bottom: this.isCheckingSources ? 0 : 12 })

            if (this.isCheckingSources) {
              Row({ space: 10 }) {
                Button('取消', { type: ButtonType.Normal })
                  .layoutWeight(1)
                  .height(42)
                  .borderRadius(10)
                  .fontSize(13)
                  .backgroundColor(this.inputColor())
                  .fontColor(this.primaryTextColor())
                  .onClick(() => {
                    this.cancelBookSourceCheck(true);
                  })

                Button('后台', { type: ButtonType.Normal })
                  .layoutWeight(1)
                  .height(42)
                  .borderRadius(10)
                  .fontSize(13)
                  .backgroundColor(this.buttonColor())
                  .fontColor('#FFFFFF')
                  .onClick(() => {
                    this.continueBookSourceCheckInBackground();
                  })
              }
              .width('100%')
              .margin({ top: 16 })
            }

            if (!this.isCheckingSources) {
              if (this.checkResultDetails.length > 0) {
                Scroll() {
                  Column() {
                    ForEach(this.checkResultDetails, (name: string, index: number) => {
                      Text(name)
                        .fontSize(13)
                        .fontColor(this.subTextColor())
                        .width('100%')
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ bottom: index === this.checkResultDetails.length - 1 ? 0 : 6 })
                    }, (name: string, index: number) => `${index}-${name}`)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }
                .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
                .width('100%')
                .height(Math.min(this.checkResultDetails.length * 40 + 20, 160))
                .padding(10)
                .backgroundColor(this.inputColor())
                .borderRadius(8)
                .margin({ bottom: 16 })
                .scrollBar(BarState.Auto)
              }

              if (this.checkTlsTrustHosts.length > 0) {
                Button(`信任证书并重试（${this.checkTlsTrustHosts.length} 个主机）`, { type: ButtonType.Normal })
                  .width('100%')
                  .height(42)
                  .borderRadius(10)
                  .fontSize(13)
                  .backgroundColor('#B26A00')
                  .fontColor('#FFFFFF')
                  .margin({ bottom: 10 })
                  .onClick(() => {
                    this.trustCheckCertificateHostsAndRetry();
                  })
              }

              Row({ space: 8 }) {
                if (this.checkInvalidAction === 'none') {
                  Button('禁用失败项', { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(42)
                    .borderRadius(10)
                    .fontSize(11)
                    .enabled(this.checkBadUrls.length > 0 && !this.isBatchOperating)
                    .backgroundColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#F57C00' : this.inputColor())
                    .fontColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#FFFFFF' : this.subTextColor())
                    .onClick(() => {
                      this.disableFailedCheckedSources();
                    })

                  Button('删除失败项', { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(42)
                    .borderRadius(10)
                    .fontSize(11)
                    .enabled(this.checkBadUrls.length > 0 && !this.isBatchOperating)
                    .backgroundColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#E53935' : this.inputColor())
                    .fontColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#FFFFFF' : this.subTextColor())
                    .onClick(() => {
                      this.deleteFailedCheckedSources();
                    })
                }

                Button('关闭', { type: ButtonType.Normal })
                  .layoutWeight(1)
                  .height(42)
                  .borderRadius(10)
                  .fontSize(11)
                  .backgroundColor(this.inputColor())
                  .fontColor(this.primaryTextColor())
                  .onClick(() => {
                    this.showCheckDialog = false;
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
            }
          }
          .width('88%')
          .constraintSize({ maxHeight: '78%' })
          .padding(24)
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (!this.isCheckingSources) {
            this.showCheckDialog = false;
          }
        })
      }

      if (this.webImportActive) {
        Web({ src: 'about:blank', controller: this.webImportController })
          .width(1)
          .height(1)
          .opacity(0.01)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .mixedMode(MixedMode.All)
          .onControllerAttached(() => {
            this.startWebImportDownload();
          })
      }

      // Full source-rule scripts need a host owned by this visible route. The host can rebuild
      // itself between large user libraries without depending on the hidden home page lifecycle.
      BookSourceStageRuntimeHost()

      // Keep one JS runtime mounted for the lifetime of this page. Creating a new
      // controller for every click can fire onControllerAttached before about:blank
      // is ready, leaving runJavaScript pending forever on some Harmony devices.
      Web({ src: 'about:blank', controller: this.loginRuntimeController })
        .width(1)
        .height(1)
        .opacity(0.01)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onPageBegin(() => {
          this.loginRuntimeReady = false;
        })
        .onPageEnd(() => {
          this.loginRuntimeReady = true;
          const pageResolve = this.loginRuntimeWebViewPageResolve;
          this.loginRuntimeWebViewPageResolve = null;
          if (pageResolve) pageResolve();
          this.continueLoginRuntime();
        })

      if (this.isImporting) {
        Column() {
          Column() {
            LoadingProgress()
              .width(46)
              .height(46)
              .color(this.accentColor())

            Text('正在导入书源...')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .margin({ top: 14 })

            Text('请稍候')
              .fontSize(13)
              .fontColor(this.subTextColor())
              .margin({ top: 6 })
          }
          .width(180)
          .padding({ left: 24, right: 24, top: 26, bottom: 24 })
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
        })
      }

      if (this.isBatchOperating) {
        Column() {
          Column() {
            LoadingProgress()
              .width(46)
              .height(46)
              .color(this.accentColor())

            Text(this.batchOperationText)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .margin({ top: 14 })

            Text('请稍候')
              .fontSize(13)
              .fontColor(this.subTextColor())
              .margin({ top: 6 })
          }
          .width(190)
          .padding({ left: 24, right: 24, top: 26, bottom: 24 })
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .onAreaChange((_oldValue: Area, newValue: Area) => this.updateContextViewport(newValue))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  bookSourceTitleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })

      Text('书源管理')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      if (!this.selectionMode) {
        Stack({ alignContent: Alignment.Center }) {
          Column({ space: 3 }) {
            Row()
              .width(20)
              .height(2)
              .borderRadius(1)
              .backgroundColor(this.hasActiveSourceFilters() ? this.accentColor() : this.primaryTextColor())
            Row()
              .width(14)
              .height(2)
              .borderRadius(1)
              .backgroundColor(this.hasActiveSourceFilters() ? this.accentColor() : this.primaryTextColor())
            Row()
              .width(8)
              .height(2)
              .borderRadius(1)
              .backgroundColor(this.hasActiveSourceFilters() ? this.accentColor() : this.primaryTextColor())
          }
          .alignItems(HorizontalAlign.Center)
          if (this.hasActiveSourceFilters()) {
            Circle()
              .width(7)
              .height(7)
              .fill(this.accentColor())
              .position({ x: 27, y: 7 })
          }
        }
        .width(40)
        .height(40)
        .accessibilityText(this.hasActiveSourceFilters() ?
          `筛选，已启用 ${this.activeSourceFilterCount()} 项` : '筛选书源')
        .onClick(() => {
          this.showSourceFilterDialog = true;
        })

        Text('校验')
          .fontSize(15)
          .fontColor(this.isCheckingSources ? this.subTextColor() : this.primaryTextColor())
          .width(44)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openCheckOptions();
          })
      }

      Text(this.selectionMode ? '取消' : '选择')
        .fontSize(15)
        .fontColor(this.isBatchOperating ? this.subTextColor() : this.primaryTextColor())
        .width(44)
        .height(40)
        .textAlign(TextAlign.Center)
        .margin({ left: this.selectionMode ? 0 : 4 })
        .onClick(() => {
          if (this.isBatchOperating) return;
          if (this.selectionMode) {
            this.exitSelectionMode();
          } else {
            this.enterSelectionMode();
          }
        })
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ right: 16, top: this.statusBarHeight })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
    .alignItems(VerticalAlign.Center)
    .position({ x: 0, y: 0 })
  }

  @Builder
  addSourceFloatingButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(25)
        .fontColor([this.accentColor()])
    }
    .width(52)
    .height(52)
    .margin({ right: 22, bottom: this.navBarHeight + 22 })
    .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, this.cardColor(), 'button'))
    .backdropBlur(ThemeRuntime.glassBlur('button', 12))
    .border({ width: ThemeRuntime.glassBorderWidth('button'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'button') })
    .shadow({ radius: ThemeRuntime.glassShadowRadius('button'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'button'), offsetX: ThemeRuntime.glassShadowOffsetX('button'), offsetY: ThemeRuntime.glassShadowOffsetY('button') })
    .accessibilityText('新增书源')
    .onClick(() => {
      this.showAddDialog = true;
    })
  }

  @Builder
  addSourceDropdown() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.showAddDialog = false;
        })

      Column() {
        this.popupActionItem($r('sys.symbol.plus'), '新建书源', this.primaryTextColor(), () => {
          this.showAddDialog = false;
          router.pushUrl({
            url: 'pages/BookSourceEdit',
            params: { bookSourceUrl: '' }
          });
        })
        this.popupActionItem($r('sys.symbol.arrow_right_up_and_square'), '从 URL 导入', this.primaryTextColor(), () => {
          this.showAddDialog = false;
          this.showImportUrlDialog = true;
        })
        this.popupActionItem($r('sys.symbol.download'), '从文件导入', this.primaryTextColor(), () => {
          this.showAddDialog = false;
          this.importFromFile();
        }, false)
      }
      .width(188)
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .margin({ right: 22, bottom: this.navBarHeight + 82 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  batchMorePopupMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.showMoreActionDialog = false;
        })

      Column() {
        Text(`已选择 ${this.selectedSourceUrls.length} 个书源`)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .width('100%')
          .height(34)
          .padding({ left: 12, right: 12 })
          .textAlign(TextAlign.Start)

        this.popupActionItem($r('sys.symbol.checkmark_shield'), '校验所选', this.primaryTextColor(), () => {
          this.showMoreActionDialog = false;
          this.checkSelectedSources();
        })
        this.popupActionItem($r('sys.symbol.checkmark_circle'), '启用发现', this.primaryTextColor(), () => {
          this.showMoreActionDialog = false;
          this.batchSetExploreEnabled(true);
        })
        this.popupActionItem($r('sys.symbol.minus_circle'), '禁用发现', this.primaryTextColor(), () => {
          this.showMoreActionDialog = false;
          this.batchSetExploreEnabled(false);
        })
        this.popupActionItem($r('sys.symbol.lock'), '锁定', this.primaryTextColor(), () => {
          this.showMoreActionDialog = false;
          this.batchSetLocked(true);
        })
        this.popupActionItem($r('sys.symbol.lock_open'), '解锁', this.primaryTextColor(), () => {
          this.showMoreActionDialog = false;
          this.batchSetLocked(false);
        })
        this.popupActionItem($r('sys.symbol.download'), '导出 JSON', this.primaryTextColor(), () => {
          this.showMoreActionDialog = false;
          this.exportSelectedSources();
        })
        this.popupActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => {
          this.showMoreActionDialog = false;
          this.showBatchDeleteDialog = true;
        }, false)
      }
      .width(188)
      .padding({ left: 6, right: 6, top: 4, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: '100%', y: '100%' })
      .translate({ x: -200, y: -(378 + Math.max(this.navBarHeight, 8)) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  popupActionItem(icon: Resource, label: string, color: string, action: () => void,
    showDivider: boolean = true) {
    Column() {
      Row({ space: 10 }) {
        SymbolGlyph(icon)
          .fontSize(19)
          .fontColor([color])
          .width(24)
        Text(label)
          .fontSize(15)
          .fontColor(color)
          .layoutWeight(1)
      }
      .width('100%')
      .height(44)
      .padding({ left: 10, right: 10 })

      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.glassBorderColor(this.appDarkMode))
          .margin({ left: 44, right: 8 })
      }
    }
    .width('100%')
    .onClick(action)
  }

  @Builder
  sourceFilterDialog() {
    Column() {
      Column({ space: 14 }) {
        Row() {
          Text('筛选书源')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Text(`当前 ${this.sources.length}/${this.allSources.length}`)
            .fontSize(12)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        this.sourceSortFilterRow()
        this.sourceFilterRow('书源状态', 'enabled', '已启用', '未启用')
        this.sourceValidationFilterRow()
        this.sourceFilterRow('发现页面', 'explorePage', '有发现页', '无发现页')
        this.sourceFilterRow('发现状态', 'exploreEnabled', '已启用', '未启用')
        this.sourceFilterRow('登录要求', 'login', '需要登录', '无需登录')

        Row({ space: 10 }) {
          Button('重置', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .enabled(this.hasActiveSourceFilters())
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.resetSourceFilters())
          Button('完成', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => this.showSourceFilterDialog = false)
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('92%')
      .constraintSize({ maxWidth: 540 })
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  sourceSortFilterRow() {
    Row({ space: 10 }) {
      Text('排序')
        .fontSize(14)
        .fontColor(this.primaryTextColor())
        .width(66)
      Row({ space: 6 }) {
        this.sourceSortChoice('custom', '默认')
        this.sourceSortChoice('latest', '最新在前')
        this.sourceSortChoice('oldest', '最旧在前')
        this.sourceSortChoice('name', '名称排序')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sourceSortChoice(value: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.sourceSortMode === value ? '#FFFFFF' : this.secondaryTextColor())
      .layoutWeight(1)
      .height(34)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .backgroundColor(this.sourceSortMode === value ? this.accentColor() : this.inputColor())
      .borderRadius(9)
      .onClick(() => {
        this.sourceSortMode = value;
        this.applySourceFilters();
      })
  }

  @Builder
  sourceFilterRow(label: string, filterKey: string, yesLabel: string, noLabel: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(14)
        .fontColor(this.primaryTextColor())
        .width(66)
      Row({ space: 6 }) {
        this.sourceFilterChoice(filterKey, 'all', '不限')
        this.sourceFilterChoice(filterKey, 'yes', yesLabel)
        this.sourceFilterChoice(filterKey, 'no', noLabel)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sourceValidationFilterRow() {
    Row({ space: 10 }) {
      Text('校验状态')
        .fontSize(14)
        .fontColor(this.primaryTextColor())
        .width(66)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        this.sourceValidationFilterChoice('all', '不限')
        this.sourceValidationFilterChoice('unchecked', '未校验')
        this.sourceValidationFilterChoice('passed', '通过')
        this.sourceValidationFilterChoice('failed', '失败')
        this.sourceValidationFilterChoice('noResults', '无结果')
        this.sourceValidationFilterChoice('needsVerification', '需要验证')
        this.sourceValidationFilterChoice('temporaryError', '暂时异常')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sourceValidationFilterChoice(value: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.sourceValidationFilter === value ? '#FFFFFF' : this.secondaryTextColor())
      .width('32%')
      .height(34)
      .margin({ bottom: 6 })
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .backgroundColor(this.sourceValidationFilter === value ? this.accentColor() : this.inputColor())
      .borderRadius(9)
      .onClick(() => this.setSourceFilterValue('validation', value))
  }

  @Builder
  sourceFilterChoice(filterKey: string, value: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.sourceFilterValue(filterKey) === value ? '#FFFFFF' : this.secondaryTextColor())
      .layoutWeight(1)
      .height(34)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .backgroundColor(this.sourceFilterValue(filterKey) === value ? this.accentColor() : this.inputColor())
      .borderRadius(9)
      .onClick(() => this.setSourceFilterValue(filterKey, value))
  }

  @Builder
  checkOptionsDialog() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#38000000' : '#14FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('menu', 10))
        .onClick(() => {
          this.showCheckOptionsDialog = false;
        })

      Column({ space: 12 }) {
        Text('校验设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')

        Text(this.checkValidationMode === 'exploreReading' ?
          '逐源运行发现、详情、目录与首个非付费章节。登录、验证、VIP 或付费内容只会提示用户处理。' :
          '只有明确的请求或规则错误会标记为失败并参与自动处理；无结果、需要验证和暂时异常不会被禁用或删除。')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')

        Row({ space: 8 }) {
          this.checkModeOption('search', '搜索能力')
          this.checkModeOption('exploreReading', '发现/阅读链路')
        }
        .width('100%')

        if (this.checkValidationMode === 'search') {
          this.checkActionOption('仅校验', '记录各类校验状态，校验完成后再手动处理', 'none')
          this.checkActionOption('自动禁用', '仅禁用明确失败的书源，可稍后重新启用', 'disable')
          this.checkActionOption('自动删除', '仅删除明确失败的书源，此操作不可恢复', 'delete', true)
        }

        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.showCheckOptionsDialog = false;
            })

          Button('开始校验')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.checkValidationMode === 'search' && this.checkInvalidAction === 'delete' ?
              '#B71C1C' : this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.startCheckEnabledSources(this.checkValidationMode === 'exploreReading' ?
                'none' : this.checkInvalidAction);
            })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('calc(100% - 24vp)')
      .constraintSize({ maxWidth: 360 })
      .padding(18)
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .margin({ top: this.statusBarHeight + 62, right: 12 })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  checkModeOption(value: string, label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.checkValidationMode === value ? '#FFFFFF' : this.primaryTextColor())
      .layoutWeight(1)
      .height(38)
      .textAlign(TextAlign.Center)
      .borderRadius(10)
      .backgroundColor(this.checkValidationMode === value ? this.buttonColor() : this.inputColor())
      .onClick(() => {
        this.checkValidationMode = value;
        if (value === 'exploreReading') this.checkInvalidAction = 'none';
      })
  }

  @Builder
  checkActionOption(title: string, description: string, action: string, danger: boolean = false) {
    Row() {
      Text(this.checkInvalidAction === action ? '●' : '○')
        .fontSize(20)
        .fontColor(this.checkInvalidAction === action ?
          (danger ? '#B71C1C' : this.accentColor()) : this.subTextColor())
        .width(28)

      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(danger ? '#B71C1C' : this.primaryTextColor())
        Text(description)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(9)
    .backgroundColor(this.checkInvalidAction === action ? this.inputColor() : this.cardColor())
    .border({
      width: this.checkInvalidAction === action ? 1 : 0.5,
      color: this.checkInvalidAction === action ? (danger ? '#B71C1C' : this.accentColor()) : this.glassBorderColor()
    })
    .onClick(() => {
      this.checkInvalidAction = action;
    })
  }

  @Builder
  sourceActionDialog() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#52000000' : '#26FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
        .onClick(() => this.closeSourceActions())
      Column() {
        this.contextActionItem($r('sys.symbol.magnifyingglass'), '搜索', this.primaryTextColor(),
          () => this.openActionSourceSearch())
        if (this.actionSourceNeedsLogin()) {
          this.contextActionItem($r('sys.symbol.arrow_right_up_and_square'),
            this.actionSourceLoggedIn() ? '重新登录' : '登录',
            this.primaryTextColor(), () => this.openActionSourceLogin())
        }
        this.contextActionItem($r('sys.symbol.checkmark_shield'), '校验', this.primaryTextColor(),
          () => this.checkActionSource())
        this.contextActionItem($r('sys.symbol.gearshape'), '调试', this.primaryTextColor(),
          () => this.openActionSourceDebug())
        if (this.actionSourceTlsTrusted()) {
          this.contextActionItem($r('sys.symbol.checkmark_shield'), '取消证书信任', '#B26A00',
            () => this.revokeActionSourceTlsTrust())
        }
        this.contextActionItem($r('sys.symbol.pin'), this.actionSourcePinned() ? '取消置顶' : '置顶',
          this.primaryTextColor(), () => this.toggleActionSourcePinned())
        this.contextActionItem($r('sys.symbol.chevron_down'), '置底', this.primaryTextColor(),
          () => this.moveActionSourceToBottom())
        this.contextActionItem($r('sys.symbol.lock'), this.actionSourceLocked() ? '解锁' : '锁定',
          this.primaryTextColor(), () => this.toggleActionSourceLocked())
        if (!this.actionSourceLocked()) {
          this.contextActionItem($r('sys.symbol.folder'), '分组', this.primaryTextColor(),
            () => this.openActionSourceGroup())
          this.contextActionItem($r('sys.symbol.square_and_pencil'), '修改', this.primaryTextColor(),
            () => this.openActionSourceEdit())
          this.contextActionItem(this.actionSourceEnabled() ? $r('sys.symbol.minus_circle') :
            $r('sys.symbol.checkmark_circle'), this.actionSourceEnabled() ? '禁用' : '启用', this.primaryTextColor(),
            () => this.toggleActionSourceEnabled())
        }
        this.contextActionItem($r('sys.symbol.list_bullet'), '多选', this.primaryTextColor(),
          () => this.enterActionSourceSelection())
        if (!this.actionSourceLocked()) {
          this.contextActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => {
              this.showSourceActionDialog = false;
              this.showSourceDeleteDialog = true;
            })
        }
      }
      .width(158)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({
        x: this.contextMenuLeft(158),
        y: this.contextMenuTop(this.sourceActionMenuHeight())
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sourceLoginUiDialog() {
    Column() {
      Column() {
        Text(`${this.actionSourceName()} · 登录与接口`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 12 })

        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.sourceLoginItems, (item: BookSourceLoginItem, index: number) => {
              if (this.isSourceLoginInput(item)) {
                Column({ space: 4 }) {
                  Text(item.name)
                    .fontSize(12)
                    .fontColor(this.subTextColor())
                    .width('100%')
                  Row({ space: 8 }) {
                    TextInput({ text: item.value, placeholder: item.placeholder || item.name })
                      .type(item.type.toLowerCase() === 'password' ? InputType.Password : InputType.Normal)
                      .layoutWeight(1)
                      .height(42)
                      .borderRadius(8)
                      .backgroundColor(this.inputColor())
                      .fontColor(this.primaryTextColor())
                      .placeholderColor(this.placeholderTextColor())
                      .padding({ left: 12, right: 12 })
                      .enabled(!this.isExecutingLoginAction)
                      .onChange((value: string) => {
                        this.updateSourceLoginInput(index, value);
                      })
                    if (item.action) {
                      Button(this.isExecutingLoginAction ? '执行中' : '执行', { type: ButtonType.Normal })
                        .width(68)
                        .height(42)
                        .fontSize(13)
                        .fontColor(this.primaryTextColor())
                        .backgroundColor(this.inputColor())
                        .enabled(!this.isExecutingLoginAction)
                        .onClick(() => {
                          this.executeSourceLoginAction(item);
                        })
                    }
                  }
                  .width('100%')
                }
                .width('100%')
              } else if (this.isSourceLoginToggle(item)) {
                Row({ space: 12 }) {
                  Column({ space: 3 }) {
                    Text(this.sourceLoginItemDisplayName(item))
                      .fontSize(14)
                      .fontColor(this.primaryTextColor())
                      .width('100%')
                    Text(this.sourceLoginToggleOn(item) ? '已开启' : '已关闭')
                      .fontSize(11)
                      .fontColor(this.sourceLoginToggleOn(item) ? this.accentColor() : this.subTextColor())
                      .width('100%')
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Toggle({ type: ToggleType.Switch, isOn: this.sourceLoginToggleOn(item) })
                    .enabled(!this.isExecutingLoginAction)
                    .selectedColor(this.accentColor())
                    .onChange((isOn: boolean) => {
                      this.updateSourceLoginToggle(index, isOn);
                    })
                }
                .width('100%')
                .height(48)
                .padding({ left: 12, right: 12 })
                .borderRadius(8)
                .backgroundColor(this.inputColor())
              } else if (this.isSourceLoginSelect(item)) {
                Row({ space: 12 }) {
                  Text(this.sourceLoginItemDisplayName(item))
                    .fontSize(14)
                    .fontColor(this.primaryTextColor())
                    .layoutWeight(1)
                    .maxLines(2)
                  Select(this.sourceLoginSelectOptions(item))
                    .selected(this.sourceLoginSelectIndex(item))
                    .value(this.sourceLoginChoiceValue(item))
                    .fontColor(this.primaryTextColor())
                    .selectedOptionFontColor(this.accentColor())
                    .backgroundColor(this.cardColor())
                    .divider(null)
                    .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
                    .menuBackgroundBlurStyle(BlurStyle.NONE)
                    .menuSystemMaterial(ImmersiveMaterialRuntime.selectMenuMaterial())
                    .enabled(!this.isExecutingLoginAction)
                    .onSelect((selectedIndex: number) => {
                      this.updateSourceLoginSelect(index, selectedIndex);
                    })
                }
                .width('100%')
                .height(48)
                .padding({ left: 12, right: 8 })
                .borderRadius(8)
                .backgroundColor(this.inputColor())
              } else {
                Button(this.isExecutingLoginAction && item.action ? `执行中 · ${item.name}` :
                  this.sourceLoginButtonLabel(item),
                  { type: ButtonType.Normal })
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .fontColor(item.action ? this.primaryTextColor() : this.subTextColor())
                  .backgroundColor(item.action ? this.inputColor() : this.cardColor())
                  .enabled(!!item.action && !this.isExecutingLoginAction)
                  .onClick(() => {
                    this.executeSourceLoginAction(item);
                  })
              }
            }, (item: BookSourceLoginItem, index: number) => this.sourceLoginItemRenderKey(item, index))
          }
          .width('100%')
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .constraintSize({ maxHeight: 430 })
        .scrollBar(BarState.Auto)

        Button('关闭')
          .width('100%')
          .height(42)
          .margin({ top: 8 })
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.saveSourceLoginInputs();
            this.showSourceLoginUiDialog = false;
            this.sourceLoginItems = [];
            this.actionSourceUrl = '';
            this.actionSourceDetail = null;
          })
      }
      .width('90%')
      .padding(22)
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  contextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([color])
        .width(24)
      Text(label)
        .fontSize(15)
        .fontColor(color)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  @Builder
  sourceOrderStatusBadge(label: string, accessibilityLabel: string) {
    Text(label)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.accentColor())
      .width(24)
      .height(24)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.inputColor())
      .borderRadius(12)
      .margin({ left: 6 })
      .accessibilityText(accessibilityLabel)
  }

  @Builder
  sourceStatusIcon(icon: Resource, color: string, accessibilityLabel: string) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([color])
    }
    .width(24)
    .height(24)
    .borderRadius(12)
    .backgroundColor(this.inputColor())
    .margin({ left: 6 })
    .accessibilityText(accessibilityLabel)
  }

  @Builder
  sourceLoginStatusBadge(color: string, accessibilityLabel: string) {
    Text('登')
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(color)
      .width(24)
      .height(24)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.inputColor())
      .borderRadius(12)
      .margin({ left: 6 })
      .accessibilityText(accessibilityLabel)
  }

  @Builder
  sourceValidationStatusBadge(validationStatus: number) {
    Text(this.sourceValidationStatusLabel(validationStatus))
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.sourceValidationStatusColor(validationStatus))
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(this.inputColor())
      .borderRadius(4)
      .maxLines(1)
      .accessibilityText(this.sourceValidationStatusLabel(validationStatus))
  }

  sourceValidationStatusLabel(validationStatus: number): string {
    if (validationStatus === BookSource.VALIDATION_PASSED) return '通过';
    if (validationStatus === BookSource.VALIDATION_FAILED) return '失败';
    if (validationStatus === BookSource.VALIDATION_NO_RESULTS) return '无结果';
    if (validationStatus === BookSource.VALIDATION_NEEDS_VERIFICATION) return '需要验证';
    if (validationStatus === BookSource.VALIDATION_TEMPORARY_ERROR) return '暂时异常';
    return '未校验';
  }

  sourceValidationStatusColor(validationStatus: number): string {
    if (validationStatus === BookSource.VALIDATION_PASSED) return '#1E8E3E';
    if (validationStatus === BookSource.VALIDATION_FAILED) return '#C62828';
    if (validationStatus === BookSource.VALIDATION_NO_RESULTS) return '#8A6D3B';
    if (validationStatus === BookSource.VALIDATION_NEEDS_VERIFICATION) return '#1565C0';
    if (validationStatus === BookSource.VALIDATION_TEMPORARY_ERROR) return '#F57C00';
    return this.subTextColor();
  }

  @Builder
  sourceDisableSwipeAction(source: BookSource) {
    Column({ space: 4 }) {
      SymbolGlyph(source.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text(source.enabled ? '禁用' : '启用')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.buttonColor())
    .onClick(() => {
      if (!this.selectionMode && !this.isBatchOperating) this.toggleSourceEnabled(source);
    })
  }

  @Builder
  sourceSwipeCard(source: BookSource) {
    Row() {
      if (this.selectionMode) {
        this.sourceSelectionSafeArea(source)
      }
      if (!this.selectionMode) {
        Stack({ alignContent: Alignment.Center }) {
          Text('☰')
            .fontSize(18)
            .fontColor(this.subTextColor())
        }
        .width(52)
        .height(56)
        .margin({ left: -8, right: 4 })
        .hitTestBehavior(HitTestMode.Transparent)
        .accessibilityText(`长按拖动排序：${source.bookSourceName}`)
      }
      Column() {
        Row() {
          Text(source.bookSourceName)
            .fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (source.isPinned) this.sourceStatusIcon($r('sys.symbol.pin'), this.accentColor(), '已置顶')
          if (source.isLocked) this.sourceStatusIcon($r('sys.symbol.lock'), this.accentColor(), '已锁定')
          if (source.bookSourceGroup) {
            Text(source.bookSourceGroup).fontSize(11).fontColor(this.accentColor())
              .constraintSize({ maxWidth: 72 }).padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor(this.inputColor()).borderRadius(4).margin({ left: 6 })
          }
          if (this.sourceNeedsLogin(source)) {
            this.sourceLoginStatusBadge(this.sourceLoggedIn(source) ? '#1E8E3E' : '#C62828', this.sourceLoggedIn(source) ? '已登录' : '未登录')
          }
        }.width('100%')
        Row({ space: 7 }) {
          this.sourceValidationStatusBadge(source.validationStatus)
          Text(source.bookSourceUrl)
            .fontSize(12).fontColor(this.subTextColor())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }.width('100%').margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .gesture(LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => {
        if (!this.selectionMode && !this.isBatchOperating) this.openSourceActions(source, event)
      }))
      Column() {
        Text(source.enabled ? '已启用' : '已禁用').fontSize(12)
          .fontColor(source.enabled ? '#1E8E3E' : this.subTextColor())
        Text(source.enabledExplore ? '发现已启用' : '发现已禁用').fontSize(12)
          .fontColor(source.enabledExplore ? '#1E8E3E' : this.subTextColor()).margin({ top: 4 })
      }.alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.glassCardColor())
    .borderRadius(8)
    .opacity(source.enabled ? 1 : 0.45)
    .onClick(() => {
      if (this.isBatchOperating) return;
      if (this.selectionMode) {
        this.toggleSourceSelected(source.bookSourceUrl)
      } else {
        this.openSourceActions(source)
      }
    })
  }

  private sourceSwipeActions(source: BookSource): HdsSwipeActionOptions {
    if (this.selectionMode || source.isLocked) return { icons: [] };
    return { icons: [
      { icon: new SymbolGlyphModifier(source.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle')), backgroundColor: this.buttonColor(), iconOptions: { accessibilityText: source.enabled ? '禁用书源' : '启用书源' }, onAction: () => this.toggleSourceEnabled(source) },
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')), backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode), iconOptions: { accessibilityText: '删除书源' }, onAction: () => this.deleteSourceFromSwipe(source) }
    ] };
  }

  @Builder
  sourceDeleteSwipeAction(source: BookSource) {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
    .onClick(() => {
      if (!this.selectionMode && !this.isBatchOperating) this.deleteSourceFromSwipe(source);
    })
  }

  @Builder
  sourceDeleteDialog() {
    Column() {
      Column() {
        Text('删除书源')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)

        Text(`确定删除“${this.actionSourceName()}”吗？删除后不可恢复。`)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 12, bottom: 20 })

        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.showSourceDeleteDialog = false;
              this.actionSourceUrl = '';
            })

          Button('删除')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#B71C1C')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.deleteActionSource();
            })
        }
        .width('100%')
      }
      .width('86%')
      .padding(22)
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showSourceDeleteDialog = false;
      this.actionSourceUrl = '';
    })
  }

  @Builder
  sourceDragPreview() {
    Row() {
      Text('☰')
        .fontSize(18)
        .fontColor(this.subTextColor())
        .width(28)
        .textAlign(TextAlign.Center)
        .margin({ right: 8 })
      Column() {
        Text(this.draggingSourceName())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.draggingSourceUrl)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(280)
    .padding(12)
    .borderRadius(8)
    .backgroundColor(this.cardColor())
    .shadow({ radius: 12, color: this.appDarkMode ? '#66000000' : '#22000000', offsetX: 0, offsetY: 4 })
  }

  @Builder
  sourceVirtualScrollbar() {
    if (this.sourceShouldShowVirtualScrollbar()) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column()
          .width(3)
          .height(this.sourceScrollbarViewportHeight())
          .borderRadius(2)
          .backgroundColor(this.appDarkMode ? '#18FFFFFF' : '#14000000')
          .margin({ right: 3 })
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(this.sourceScrollbarDragging ? 6 : 4)
          .height(this.sourceScrollbarThumbLength())
          .borderRadius(3)
          .backgroundColor(this.appDarkMode ? '#BFD5D8DE' : '#A87A6F63')
          .margin({ right: 2 })
          .translate({ y: this.sourceDisplayedScrollbarThumbOffset() })
          .hitTestBehavior(HitTestMode.None)
      }
      .width(24)
      .height(this.sourceScrollbarViewportHeight())
      .translate({ y: this.sourceListTopInset() })
      .zIndex(10)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.Vertical, distance: 1 })
            .onActionStart((event: GestureEvent) => this.beginSourceScrollbarDrag(event))
            .onActionUpdate((event: GestureEvent) => this.updateSourceScrollbarDrag(event))
            .onActionEnd((event: GestureEvent) => this.endSourceScrollbarDrag(event))
            .onActionCancel(() => this.cancelSourceScrollbarDrag()),
          TapGesture().onAction((event: GestureEvent) => this.jumpSourceScrollbarToPointer(event))
        )
      )
    }
  }

  sourceShouldShowVirtualScrollbar(): boolean {
    return this.sourceScrollbarViewportHeight() > 0 && this.sources.length > this.sourceVisibleItemCount;
  }

  sourceScrollbarViewportHeight(): number {
    return Math.max(0, this.sourceListViewportHeight - this.sourceListTopInset());
  }

  sourceScrollbarThumbLength(): number {
    return VirtualListScrollbar.thumbLength(this.sourceScrollbarViewportHeight(),
      this.sources.length, this.sourceVisibleItemCount);
  }

  sourceScrollbarThumbOffset(): number {
    return VirtualListScrollbar.thumbOffset(this.sourceScrollbarViewportHeight(),
      this.sourceScrollbarThumbLength(), this.sources.length,
      this.sourceFirstVisibleIndex, this.sourceVisibleItemCount);
  }

  sourceDisplayedScrollbarThumbOffset(): number {
    return this.sourceScrollbarDragging ? this.sourceScrollbarDragOffset : this.sourceScrollbarThumbOffset();
  }

  sourceScrollbarPointerY(event: GestureEvent): number {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    return finger ? finger.localY : 0;
  }

  beginSourceScrollbarDrag(event: GestureEvent): void {
    const thumbLength = this.sourceScrollbarThumbLength();
    const currentOffset = this.sourceScrollbarThumbOffset();
    const pointerY = this.sourceScrollbarPointerY(event);
    this.sourceScrollbarDragging = true;
    this.sourceScrollbarDragOffset = currentOffset;
    if (pointerY >= currentOffset && pointerY <= currentOffset + thumbLength) {
      this.sourceScrollbarPointerAnchor = pointerY - currentOffset;
    } else {
      this.sourceScrollbarPointerAnchor = thumbLength / 2;
      this.updateSourceScrollbarFromPointer(pointerY);
    }
  }

  updateSourceScrollbarDrag(event: GestureEvent): void {
    if (!this.sourceScrollbarDragging) return;
    this.updateSourceScrollbarFromPointer(this.sourceScrollbarPointerY(event));
  }

  endSourceScrollbarDrag(event: GestureEvent): void {
    if (!this.sourceScrollbarDragging) return;
    this.updateSourceScrollbarFromPointer(this.sourceScrollbarPointerY(event));
    this.sourceScrollbarDragging = false;
  }

  cancelSourceScrollbarDrag(): void {
    this.sourceScrollbarDragging = false;
  }

  jumpSourceScrollbarToPointer(event: GestureEvent): void {
    this.sourceScrollbarPointerAnchor = this.sourceScrollbarThumbLength() / 2;
    this.updateSourceScrollbarFromPointer(this.sourceScrollbarPointerY(event));
  }

  updateSourceScrollbarFromPointer(pointerY: number): void {
    const thumbLength = this.sourceScrollbarThumbLength();
    const viewportHeight = this.sourceScrollbarViewportHeight();
    const offset = VirtualListScrollbar.clampThumbOffset(viewportHeight, thumbLength,
      pointerY - this.sourceScrollbarPointerAnchor);
    this.sourceScrollbarDragOffset = offset;
    const targetIndex = VirtualListScrollbar.firstVisibleIndex(viewportHeight, thumbLength,
      this.sources.length, this.sourceVisibleItemCount, offset);
    this.sourceFirstVisibleIndex = targetIndex;
    this.queueSourceScrollbarTarget(targetIndex);
  }

  queueSourceScrollbarTarget(targetIndex: number): void {
    this.sourceScrollbarPendingIndex = targetIndex;
    if (this.sourceScrollbarUpdateTimer >= 0) return;
    this.sourceScrollbarUpdateTimer = setTimeout(() => {
      this.sourceScrollbarUpdateTimer = -1;
      const pending = this.sourceScrollbarPendingIndex;
      this.sourceScrollbarPendingIndex = -1;
      if (pending < 0 || this.sources.length === 0) return;
      const target = Math.max(0, Math.min(pending, this.sources.length - 1));
      try {
        // The first ListItem is the top inset spacer, so source indexes start at one.
        this.sourceListScroller.scrollToIndex(target + 1, false, ScrollAlign.START);
      } catch (e) {
        console.warn('拖动书源滚动条定位失败:', e);
      }
    }, 16);
  }

  sourceListTopInset(): number {
    return 56 + this.statusBarHeight + 98;
  }

  @Builder
  importSourceSelectionDialog() {
    Column() {
      Column({ space: 12 }) {
        Text('选择要导入的书源')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)

        Text(`共 ${this.pendingImportSources.length} 个书源，已选择 ${this.selectedImportSourceUrls.length} 个`)
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)

        Row() {
          Toggle({ type: ToggleType.Checkbox, isOn: this.areAllImportSourcesSelected() })
            .selectedColor(this.buttonColor())
            .onChange((isOn: boolean) => {
              // ArkUI may invoke onChange again while the controlled `isOn`
              // value is being refreshed. Only handle a genuine user change;
              // otherwise a single-item toggle could clear every selection.
              if (isOn !== this.areAllImportSourcesSelected()) {
                this.selectAllImportSources(isOn);
              }
            })
          Text(this.areAllImportSourcesSelected() ? '取消全选' : '全选')
            .fontSize(14)
            .fontColor(this.accentColor())
            .margin({ left: 8 })
          Blank().layoutWeight(1)
        }
        .width('100%')

        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.pendingImportSources, (source: BookSource) => {
              Row() {
                Toggle({ type: ToggleType.Checkbox, isOn: this.isImportSourceSelected(source) })
                  .selectedColor(this.buttonColor())
                  .onChange((isOn: boolean) => {
                    // Ignore callbacks caused by the controlled value being
                    // re-rendered after another checkbox changes.
                    if (isOn !== this.isImportSourceSelected(source)) {
                      this.setImportSourceSelected(source, isOn);
                    }
                  })
                Column() {
                  Text(source.bookSourceName || '未命名书源')
                    .fontSize(15)
                    .fontColor(this.primaryTextColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(source.bookSourceUrl || '')
                    .fontSize(11)
                    .fontColor(this.subTextColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .margin({ left: 8 })
              }
              .width('100%')
              .padding({ left: 6, right: 6, top: 8, bottom: 8 })
              .borderRadius(10)
              .backgroundColor(this.inputColor())
            }, (source: BookSource) => source.bookSourceUrl)
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 360 })
        .scrollBar(BarState.Auto)

        Row({ space: 10 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.glassCardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.cancelImportSourceSelection())
          Button('导入所选', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .enabled(this.selectedImportSourceUrls.length > 0 && !this.isImporting)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => this.confirmImportSourceSelection())
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxWidth: 520 })
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  sourceGroupBar() {
    Scroll() {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.more'))
            .fontSize(18)
            .fontColor([this.primaryTextColor()])
        }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.glassCardColor())
          .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
          .onClick((event: ClickEvent) => {
            this.contextMenuX = event.windowX;
            this.contextMenuY = event.windowY;
            this.showSourceGroupToolsMenu = true;
          })
        this.sourceGroupChip('全部', '__all__')
        ForEach(this.getSourceGroups(), (group: string) => {
          this.sourceGroupChip(group, group, true)
        }, (group: string) => group)
        this.sourceGroupChip('未分组', '__ungrouped__')
        Text('＋')
          .fontSize(20)
          .fontColor(this.accentColor())
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .borderRadius(17)
          .backgroundColor(this.glassCardColor())
          .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
          .onClick(() => {
            this.newSourceGroupInput = '';
            this.showAddSourceGroupDialog = true;
          })
      }
      .padding({ left: 16, right: 16, bottom: 8 })
      .constraintSize({ minWidth: '100%' })
      .justifyContent(FlexAlign.Start)
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .zIndex(2)
  }

  @Builder
  sourceGroupToolsMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showSourceGroupToolsMenu = false;
        })

      Column() {
        this.contextActionItem($r('sys.symbol.list_bullet'), '分组管理', this.primaryTextColor(), () => {
          this.showSourceGroupToolsMenu = false;
          this.selectedManagedSourceGroups = [];
          this.showSourceGroupManagerDialog = true;
        })
        this.contextActionItem($r('sys.symbol.trash'), '清除空分组', this.primaryTextColor(), () => {
          this.showSourceGroupToolsMenu = false;
          this.clearEmptySourceGroups();
        })
        this.contextActionItem($r('sys.symbol.plus'), '新建分组', this.primaryTextColor(), () => {
          this.showSourceGroupToolsMenu = false;
          this.newSourceGroupInput = '';
          this.showAddSourceGroupDialog = true;
        })
      }
      .width(166)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.contextMenuLeft(166), y: this.contextMenuTop(144) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sourceGroupManagerDialog() {
    Column() {
      Column() {
        Row() {
          Text('分组管理')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Text('新建')
            .fontSize(14)
            .fontColor(this.accentColor())
            .padding({ left: 10, right: 2, top: 8, bottom: 8 })
            .onClick(() => {
              this.newSourceGroupInput = '';
              this.showAddSourceGroupDialog = true;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.getSourceGroups().length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(30)
              .fontColor([this.subTextColor()])
            Text('暂无书源分组')
              .fontSize(14)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .height(150)
          .justifyContent(FlexAlign.Center)
        } else {
          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.areAllManagedSourceGroupsSelected() })
              .selectedColor(this.buttonColor())
              .onChange((isOn: boolean) => this.selectAllManagedSourceGroups(isOn))
            Text(this.areAllManagedSourceGroupsSelected() ? '取消全选' : '全选')
              .fontSize(13)
              .fontColor(this.secondaryTextColor())
              .margin({ left: 8 })
              .layoutWeight(1)
            Text(`已选 ${this.selectedManagedSourceGroups.length} 项`)
              .fontSize(12)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .height(40)
          .padding({ left: 4, right: 4 })

          Scroll() {
            Column({ space: 6 }) {
              ForEach(this.getSourceGroups(), (group: string) => {
                Row() {
                  Toggle({ type: ToggleType.Checkbox, isOn: this.isManagedSourceGroupSelected(group) })
                    .selectedColor(this.buttonColor())
                    .onChange((isOn: boolean) => this.setManagedSourceGroupSelected(group, isOn))
                  Column() {
                    Text(group)
                      .fontSize(15)
                      .fontColor(this.primaryTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${this.sourceGroupCount(group)} 个书源`)
                      .fontSize(11)
                      .fontColor(this.subTextColor())
                      .margin({ top: 2 })
                  }
                  .layoutWeight(1)
                  .margin({ left: 8 })
                  .alignItems(HorizontalAlign.Start)
                  Text('编辑')
                    .fontSize(13)
                    .fontColor(this.accentColor())
                    .height(36)
                    .padding({ left: 9, right: 9 })
                    .textAlign(TextAlign.Center)
                    .onClick(() => this.openManagedSourceGroupRename(group))
                  Text('删除')
                    .fontSize(13)
                    .fontColor('#E53935')
                    .height(36)
                    .padding({ left: 9, right: 4 })
                    .textAlign(TextAlign.Center)
                    .onClick(() => this.openManagedSourceGroupDelete(group))
                }
                .width('100%')
                .height(56)
                .padding({ left: 8, right: 8 })
                .borderRadius(9)
                .backgroundColor(this.inputColor())
              }, (group: string) => group)
            }
            .width('100%')
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%')
          .constraintSize({ maxHeight: 360 })
          .scrollBar(BarState.Auto)
        }

        Row({ space: 10 }) {
          Button('关闭', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.glassCardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.showSourceGroupManagerDialog = false;
              this.selectedManagedSourceGroups = [];
            })
          Button('删除所选', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .enabled(this.selectedManagedSourceGroups.length > 0 && !this.isBatchOperating)
            .backgroundColor('#E53935')
            .fontColor('#FFFFFF')
            .onClick(() => this.showDeleteSelectedSourceGroupsDialog = true)
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('90%')
      .constraintSize({ maxWidth: 520 })
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  sourceGroupChip(label: string, groupKey: string, editable: boolean = false) {
    Text(label)
      .fontSize(13)
      .fontColor(this.activeSourceGroup === groupKey ? '#FFFFFF' : this.primaryTextColor())
      .maxLines(1)
      .padding({ left: 13, right: 13, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.activeSourceGroup === groupKey ? this.accentColor() : this.glassCardColor())
      .border({ width: this.activeSourceGroup === groupKey ? 0 : 1, color: this.glassBorderColor() })
      .onClick(() => {
        this.selectSourceGroup(groupKey);
      })
      .gesture(
        LongPressGesture({ repeat: false })
          .onAction((event: GestureEvent) => {
            if (editable) {
              this.openSourceGroupActions(groupKey, event);
            }
          })
      )
  }

  @Builder
  sourceGroupActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#52000000' : '#26FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
        .onClick(() => this.closeSourceGroupActions())

      Column() {
        this.contextActionItem($r('sys.symbol.square_and_pencil'), '重命名', this.primaryTextColor(), () => {
            this.renameSourceGroupInput = this.pendingSourceGroup;
            this.showSourceGroupActionMenu = false;
            this.showRenameSourceGroupDialog = true;
          })
        this.contextActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => {
            this.showSourceGroupActionMenu = false;
            this.showDeleteSourceGroupDialog = true;
          })
      }
      .width(148)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.contextMenuLeft(148), y: this.contextMenuTop(100) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  addSourceGroupDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('新增书源分组')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())

        TextInput({ placeholder: '输入分组名称', text: this.newSourceGroupInput })
          .width('100%')
          .height(42)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .borderRadius(10)
          .onChange((value: string) => this.newSourceGroupInput = value)

        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.glassCardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeAddSourceGroupDialog())
          Button('新增', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .enabled(!!this.newSourceGroupInput.trim() && !this.isBatchOperating)
            .onClick(() => this.addSourceGroup())
        }
        .width('100%')
      }
      .width('85%')
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  renameSourceGroupDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('重命名书源分组')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())

        TextInput({ placeholder: '输入分组名称', text: this.renameSourceGroupInput })
          .width('100%')
          .height(42)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .borderRadius(10)
          .onChange((value: string) => this.renameSourceGroupInput = value)

        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.glassCardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeRenameSourceGroupDialog())
          Button('保存', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .enabled(!!this.renameSourceGroupInput.trim() && !this.isBatchOperating)
            .onClick(() => this.renameSourceGroup())
        }
        .width('100%')
      }
      .width('85%')
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  deleteSourceGroupDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('删除书源分组')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Text(`删除“${this.pendingSourceGroup}”后，分组内书源将移到未分组，书源本身不会删除。`)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .textAlign(TextAlign.Center)
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.glassCardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeDeleteSourceGroupDialog())
          Button('删除', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor('#E53935')
            .fontColor('#FFFFFF')
            .enabled(!this.isBatchOperating)
            .onClick(() => this.deleteSourceGroup())
        }
        .width('100%')
      }
      .width('85%')
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  deleteSelectedSourceGroupsDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('删除所选分组')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Text(`确定删除所选 ${this.selectedManagedSourceGroups.length} 个分组吗？分组内书源将移到未分组。`)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .textAlign(TextAlign.Center)
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.glassCardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.showDeleteSelectedSourceGroupsDialog = false)
          Button('删除', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor('#E53935')
            .fontColor('#FFFFFF')
            .enabled(this.selectedManagedSourceGroups.length > 0 && !this.isBatchOperating)
            .onClick(() => this.deleteSelectedSourceGroups())
        }
        .width('100%')
      }
      .width('85%')
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  glassCardColor(): string {
    return this.cardColor();
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  glassInputColor(): string {
    return this.cardColor();
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

  placeholderTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  searchSources(): void {
    this.applySourceFilters();
  }

  rememberSourceSelectionArea(sourceUrl: string, area: Area): void {
    const position = area.globalPosition;
    this.sourceSelectionAreas.set(sourceUrl, [Number(position.x), Number(position.y),
      Number(position.x) + Number(area.width), Number(position.y) + Number(area.height)]);
  }

  @Builder
  sourceSelectionSafeArea(source: BookSource) {
    Stack({ alignContent: Alignment.Center }) {
      Toggle({ type: ToggleType.Checkbox, isOn: this.isSourceSelected(source.bookSourceUrl) })
        .selectedColor(this.buttonColor())
        .hitTestBehavior(HitTestMode.None)
    }
    .width(56)
    .height(64)
    .margin({ left: -10, right: 2 })
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.Vertical, distance: 2 })
          .onActionStart((event: GestureEvent) => this.beginSourceSlideSelection(event))
          .onActionUpdate((event: GestureEvent) => this.updateSourceSlideSelection(event))
          .onActionEnd(() => this.endSourceSlideSelection())
          .onActionCancel(() => this.endSourceSlideSelection()),
        TapGesture().onAction(() => {
          if (!this.isBatchOperating) {
            this.sourceSelectionSuppressClickUntil = Date.now() + 240;
            this.toggleSourceSelected(source.bookSourceUrl);
          }
        })
      ),
      GestureMask.IgnoreInternal
    )
  }

  beginSourceSlideSelection(event: GestureEvent): void {
    if (!this.selectionMode || this.isBatchOperating) return;
    this.sourceDragVisited.clear();
    const sourceUrl = this.sourceAtGesture(event);
    if (!sourceUrl) return;
    this.sourceSelectionDragging = true;
    this.captureSourceSelectionPoint(event);
    this.sourceDragSelectValue = !this.isSourceSelected(sourceUrl);
    this.applySourceSlideSelection(sourceUrl);
    this.updateSourceSelectionAutoScroll();
  }

  updateSourceSlideSelection(event: GestureEvent): void {
    if (!this.selectionMode || this.isBatchOperating) return;
    this.captureSourceSelectionPoint(event);
    this.applySourceSlideSelection(this.sourceAtGesture(event));
    this.updateSourceSelectionAutoScroll();
  }

  endSourceSlideSelection(): void {
    this.sourceSelectionSuppressClickUntil = Date.now() + 240;
    this.sourceSelectionDragging = false;
    this.sourceDragVisited.clear();
    this.stopSourceSelectionAutoScroll();
  }

  sourceAtGesture(event: GestureEvent): string {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (!finger) return '';
    return this.sourceAtPoint(finger.globalX, finger.globalY);
  }

  sourceAtPoint(globalX: number, globalY: number): string {
    for (const source of this.visibleSources) {
      const area = this.sourceSelectionAreas.get(source.bookSourceUrl);
      if (area && globalX >= area[0] && globalX <= area[2] &&
        globalY >= area[1] && globalY <= area[3]) return source.bookSourceUrl;
    }
    return '';
  }

  applySourceSlideSelection(sourceUrl: string): void {
    if (!sourceUrl || this.sourceDragVisited.has(sourceUrl)) return;
    this.sourceDragVisited.add(sourceUrl);
    this.setSourceSelected(sourceUrl, this.sourceDragSelectValue);
  }

  captureSourceSelectionPoint(event: GestureEvent): void {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (!finger) return;
    this.sourceSelectionLastX = finger.globalX;
    this.sourceSelectionLastY = finger.globalY;
  }

  updateSourceSelectionAutoScroll(): void {
    if (!this.sourceSelectionDragging || this.sourceSelectionViewportBottom <= this.sourceSelectionViewportTop) {
      this.stopSourceSelectionAutoScroll();
      return;
    }
    const edgeSize = 72;
    let direction = 0;
    if (this.sourceSelectionLastY <= this.sourceSelectionViewportTop + edgeSize) direction = -1;
    if (this.sourceSelectionLastY >= this.sourceSelectionViewportBottom - edgeSize) direction = 1;
    if (direction === this.sourceSelectionAutoDirection && this.sourceSelectionAutoScrollId >= 0) return;
    this.stopSourceSelectionAutoScroll();
    if (direction === 0 || this.sourceSelectionReachedBoundary(direction)) return;
    this.sourceSelectionAutoDirection = direction;
    this.sourceSelectionAutoScrollId = setInterval(() => {
      if (!this.sourceSelectionDragging || this.sourceSelectionReachedBoundary(direction)) {
        this.stopSourceSelectionAutoScroll();
        return;
      }
      this.sourceListScroller.scrollBy(0, direction * 12);
      setTimeout(() => {
        if (!this.sourceSelectionDragging) return;
        this.applySourceSlideSelection(this.sourceAtPoint(
          this.sourceSelectionLastX, this.sourceSelectionLastY));
      }, 0);
    }, 24);
  }

  sourceSelectionReachedBoundary(direction: number): boolean {
    if (direction < 0) return this.sourceFirstVisibleIndex <= 0;
    return this.visibleSources.length >= this.sources.length &&
      this.sourceFirstVisibleIndex + this.sourceVisibleItemCount >= this.visibleSources.length;
  }

  stopSourceSelectionAutoScroll(): void {
    if (this.sourceSelectionAutoScrollId >= 0) {
      clearInterval(this.sourceSelectionAutoScrollId);
      this.sourceSelectionAutoScrollId = -1;
    }
    this.sourceSelectionAutoDirection = 0;
  }

  selectSourceGroup(groupKey: string): void {
    if (this.activeSourceGroup === groupKey) {
      return;
    }
    this.activeSourceGroup = groupKey;
    this.applySourceFilters();
  }

  openSourceGroupActions(group: string, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.pendingSourceGroup = group;
    this.showSourceGroupActionMenu = true;
  }

  closeSourceGroupActions(): void {
    this.showSourceGroupActionMenu = false;
    this.pendingSourceGroup = '';
  }

  closeRenameSourceGroupDialog(): void {
    this.showRenameSourceGroupDialog = false;
    this.renameSourceGroupInput = '';
    this.pendingSourceGroup = '';
  }

  closeDeleteSourceGroupDialog(): void {
    this.showDeleteSourceGroupDialog = false;
    this.pendingSourceGroup = '';
  }

  closeAddSourceGroupDialog(): void {
    this.showAddSourceGroupDialog = false;
    this.newSourceGroupInput = '';
  }

  sourceGroupCount(group: string): number {
    return this.allSources.filter((source: BookSource) =>
      (source.bookSourceGroup || '').trim() === group).length;
  }

  isManagedSourceGroupSelected(group: string): boolean {
    return this.selectedManagedSourceGroups.includes(group);
  }

  setManagedSourceGroupSelected(group: string, selected: boolean): void {
    if (selected) {
      if (!this.isManagedSourceGroupSelected(group)) {
        this.selectedManagedSourceGroups = this.selectedManagedSourceGroups.concat([group]);
      }
      return;
    }
    this.selectedManagedSourceGroups = this.selectedManagedSourceGroups.filter((item: string) => item !== group);
  }

  areAllManagedSourceGroupsSelected(): boolean {
    const groups = this.getSourceGroups();
    return groups.length > 0 && this.selectedManagedSourceGroups.length === groups.length;
  }

  selectAllManagedSourceGroups(selected: boolean): void {
    this.selectedManagedSourceGroups = selected ? this.getSourceGroups() : [];
  }

  openManagedSourceGroupRename(group: string): void {
    this.pendingSourceGroup = group;
    this.renameSourceGroupInput = group;
    this.showRenameSourceGroupDialog = true;
  }

  openManagedSourceGroupDelete(group: string): void {
    this.pendingSourceGroup = group;
    this.showDeleteSourceGroupDialog = true;
  }

  async addSourceGroup(): Promise<void> {
    const groupName = this.newSourceGroupInput.trim();
    if (!groupName || this.isBatchOperating) {
      return;
    }
    if (this.getSourceGroups().includes(groupName)) {
      promptAction.showToast({ message: '分组名称已存在' });
      return;
    }
    this.isBatchOperating = true;
    try {
      this.sourceGroups = await BookSourceGroupStore.add(getContext(this), groupName, this.sourceGroups);
      this.activeSourceGroup = groupName;
      this.applySourceFilters();
      this.closeAddSourceGroupDialog();
      promptAction.showToast({ message: '书源分组已新增' });
    } catch (e) {
      console.error('新增书源分组失败:', e);
      promptAction.showToast({ message: '新增分组失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async deleteSelectedSourceGroups(): Promise<void> {
    const groupsToDelete = this.selectedManagedSourceGroups.filter((group: string) =>
      this.getSourceGroups().includes(group));
    if (groupsToDelete.length === 0 || this.isBatchOperating) return;
    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源分组...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of this.allSources) {
        if (groupsToDelete.includes((source.bookSourceGroup || '').trim())) {
          source.bookSourceGroup = '';
          await db.updateBookSourceGroupMembership(source.bookSourceUrl, '');
        }
      }
      let groups = this.sourceGroups;
      for (const group of groupsToDelete) {
        groups = await BookSourceGroupStore.remove(getContext(this), group, groups);
      }
      this.sourceGroups = groups;
      if (groupsToDelete.includes(this.activeSourceGroup)) {
        this.activeSourceGroup = '__ungrouped__';
      }
      this.selectedManagedSourceGroups = [];
      this.showDeleteSelectedSourceGroupsDialog = false;
      await this.loadSources();
      promptAction.showToast({ message: `已删除 ${groupsToDelete.length} 个分组` });
    } catch (e) {
      console.error('批量删除书源分组失败:', e);
      promptAction.showToast({ message: '删除分组失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async reconcileSourceGroups(): Promise<void> {
    try {
      this.sourceGroups = await BookSourceGroupStore.load(getContext(this), this.sourceGroupsFromSources());
      this.ensureActiveSourceGroup();
      this.applySourceFilters();
    } catch (e) {
      console.warn('清理空书源分组失败:', e);
    }
  }

  async clearEmptySourceGroups(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    this.isBatchOperating = true;
    this.batchOperationText = '正在清除空分组...';
    try {
      // 书源导入、分组修改或删除后，内存中的 allSources 可能尚未完成同步。
      // 清理前重新读取数据库，避免把仍在使用的分组误判为空，或漏掉刚产生的空分组。
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.allSources = await db.getBookSourceSummaries();
      this.sourceGroups = await BookSourceGroupStore.load(
        getContext(this), this.sourceGroupsFromSources());
      this.ensureActiveSourceGroup();
      this.applySourceFilters();

      const occupiedGroups = this.sourceGroupsFromSources();
      const emptyGroups = this.getSourceGroups().filter((group: string) => !occupiedGroups.includes(group));
      if (emptyGroups.length === 0) {
        promptAction.showToast({ message: '没有空分组' });
        return;
      }

      let groups = this.sourceGroups;
      for (const group of emptyGroups) {
        groups = await BookSourceGroupStore.remove(getContext(this), group, groups);
      }
      this.sourceGroups = groups;
      this.ensureActiveSourceGroup();
      this.applySourceFilters();
      promptAction.showToast({ message: `已清除 ${emptyGroups.length} 个空分组` });
    } catch (e) {
      console.error('清除空书源分组失败:', e);
      promptAction.showToast({ message: '清除空分组失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async renameSourceGroup(): Promise<void> {
    const oldName = this.pendingSourceGroup;
    const newName = this.renameSourceGroupInput.trim();
    if (!oldName || !newName || this.isBatchOperating) {
      return;
    }
    if (oldName === newName) {
      this.closeRenameSourceGroupDialog();
      return;
    }
    if (this.getSourceGroups().includes(newName)) {
      promptAction.showToast({ message: '分组名称已存在' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = '正在重命名书源分组...';
    try {
      const db = AppDatabase.getInstance();
      const groupedSources = this.allSources.filter((source: BookSource) =>
        (source.bookSourceGroup || '').trim() === oldName);
      for (const source of groupedSources) {
        source.bookSourceGroup = newName;
        await db.updateBookSourceGroupMembership(source.bookSourceUrl, newName);
      }
      this.sourceGroups = await BookSourceGroupStore.rename(
        getContext(this), oldName, newName, this.sourceGroups);
      this.selectedManagedSourceGroups = this.selectedManagedSourceGroups.map((group: string) =>
        group === oldName ? newName : group);
      if (this.activeSourceGroup === oldName) {
        this.activeSourceGroup = newName;
      }
      this.showRenameSourceGroupDialog = false;
      this.renameSourceGroupInput = '';
      this.pendingSourceGroup = '';
      await this.loadSources();
      promptAction.showToast({ message: '书源分组已重命名' });
    } catch (e) {
      console.error('重命名书源分组失败:', e);
      promptAction.showToast({ message: '重命名失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async deleteSourceGroup(): Promise<void> {
    const groupName = this.pendingSourceGroup;
    if (!groupName || this.isBatchOperating) {
      return;
    }
    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源分组...';
    try {
      const db = AppDatabase.getInstance();
      const groupedSources = this.allSources.filter((source: BookSource) =>
        (source.bookSourceGroup || '').trim() === groupName);
      for (const source of groupedSources) {
        source.bookSourceGroup = '';
        await db.updateBookSourceGroupMembership(source.bookSourceUrl, '');
      }
      this.sourceGroups = await BookSourceGroupStore.remove(getContext(this), groupName, this.sourceGroups);
      this.selectedManagedSourceGroups = this.selectedManagedSourceGroups.filter((group: string) =>
        group !== groupName);
      if (this.activeSourceGroup === groupName) {
        this.activeSourceGroup = '__ungrouped__';
      }
      this.showDeleteSourceGroupDialog = false;
      this.pendingSourceGroup = '';
      await this.loadSources();
      promptAction.showToast({ message: '分组已删除，书源已移到未分组' });
    } catch (e) {
      console.error('删除书源分组失败:', e);
      promptAction.showToast({ message: '删除分组失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  draggingSourceName(): string {
    const source = this.allSources.find((item: BookSource) => item.bookSourceUrl === this.draggingSourceUrl);
    return source ? (source.bookSourceName || '未命名书源') : '';
  }

  async moveVisibleSourceTo(from: number, to: number): Promise<void> {
    if (this.isBatchOperating || this.sourceOrderSaving || from < 0 ||
      from >= this.visibleSources.length || this.sources.length < 2) {
      return;
    }
    const draggedUrl = this.draggingSourceUrl || this.visibleSources[from].bookSourceUrl;
    const sourceIndex = this.sources.findIndex((source: BookSource) => source.bookSourceUrl === draggedUrl);
    if (sourceIndex < 0) return;
    const targetIndex = Math.max(0, Math.min(to, this.sources.length - 1));
    if (sourceIndex === targetIndex) return;

    const reordered = this.sources.slice();
    const moved = reordered.splice(sourceIndex, 1)[0];
    reordered.splice(targetIndex, 0, moved);

    const filteredUrls = new Set<string>(this.sources.map((source: BookSource) => source.bookSourceUrl));
    const nextAllSources = this.allSources.slice();
    let orderedIndex = 0;
    for (let index = 0; index < nextAllSources.length; index++) {
      if (filteredUrls.has(nextAllSources[index].bookSourceUrl)) {
        nextAllSources[index] = reordered[orderedIndex++];
      }
    }
    await this.applyAndPersistSourceOrder(nextAllSources, '排序已保存');
  }

  async applyAndPersistSourceOrder(nextSources: BookSource[], successMessage: string = ''): Promise<void> {
    if (this.isBatchOperating || this.sourceOrderSaving || nextSources.length === 0) return;
    const orderedSources = nextSources.filter((source: BookSource) => source.isPinned)
      .concat(nextSources.filter((source: BookSource) => !source.isPinned));
    const previousSources = this.allSources.slice();
    const restoreFirstIndex = this.sourceFirstVisibleIndex;
    const restoreVisibleCount = this.sourceVisibleItemCount;
    for (let index = 0; index < orderedSources.length; index++) {
      orderedSources[index].customOrder = index;
    }
    // Publish the drop result before touching the database. Waiting for the write first leaves LazyForEach on
    // its old order and makes a successful drag look as if it was ignored.
    this.allSources = [...orderedSources];
    this.applySourceFilters();
    this.restoreSourceListViewport(restoreFirstIndex, restoreVisibleCount);
    this.sourceOrderSaving = true;
    try {
      await AppDatabase.getInstance().updateBookSourceOrders(
        orderedSources.map((source: BookSource) => source.bookSourceUrl));
      const revision = AppStorage.get<number>('bookSourceOrderRevision') || 0;
      AppStorage.setOrCreate('bookSourceOrderRevision', revision + 1);
      if (successMessage) promptAction.showToast({ message: successMessage });
    } catch (e) {
      console.error('保存书源排序失败:', e);
      promptAction.showToast({ message: '保存排序失败' });
      for (let index = 0; index < previousSources.length; index++) {
        previousSources[index].customOrder = index;
      }
      this.allSources = [...previousSources];
      this.applySourceFilters();
      this.restoreSourceListViewport(restoreFirstIndex, restoreVisibleCount);
    } finally {
      this.sourceOrderSaving = false;
    }
  }

  restoreSourceListViewport(firstIndex: number, visibleCount: number): void {
    if (this.sources.length === 0) return;
    const targetIndex = Math.max(0, Math.min(firstIndex, this.sources.length - 1));
    this.visibleSources = this.sources;
    this.sourceFirstVisibleIndex = targetIndex;
    this.sourceVisibleItemCount = Math.max(1, visibleCount);
    setTimeout(() => {
      if (targetIndex < this.visibleSources.length) {
        this.sourceListScroller.scrollToIndex(targetIndex, false, ScrollAlign.START);
      }
    }, 0);
  }

  reapplySourceFiltersPreservingViewport(): void {
    const restoreFirstIndex = this.sourceFirstVisibleIndex;
    const restoreVisibleCount = this.sourceVisibleItemCount;
    this.applySourceFilters();
    this.restoreSourceListViewport(restoreFirstIndex, restoreVisibleCount);
  }

  sourceFilterValue(filterKey: string): string {
    switch (filterKey) {
      case 'enabled': return this.sourceEnabledFilter;
      case 'explorePage': return this.sourceExplorePageFilter;
      case 'exploreEnabled': return this.sourceExploreEnabledFilter;
      case 'login': return this.sourceLoginFilter;
      case 'validation': return this.sourceValidationFilter;
      default: return 'all';
    }
  }

  setSourceFilterValue(filterKey: string, value: string): void {
    if (filterKey === 'validation') {
      const allowed = ['unchecked', 'passed', 'failed', 'noResults', 'needsVerification', 'temporaryError'];
      this.sourceValidationFilter = allowed.includes(value) ? value : 'all';
      this.applySourceFilters();
      return;
    }
    const normalized = value === 'yes' || value === 'no' ? value : 'all';
    switch (filterKey) {
      case 'enabled': this.sourceEnabledFilter = normalized; break;
      case 'explorePage': this.sourceExplorePageFilter = normalized; break;
      case 'exploreEnabled': this.sourceExploreEnabledFilter = normalized; break;
      case 'login': this.sourceLoginFilter = normalized; break;
      default: return;
    }
    this.applySourceFilters();
  }

  resetSourceFilters(): void {
    this.sourceSortMode = 'custom';
    this.sourceEnabledFilter = 'all';
    this.sourceExplorePageFilter = 'all';
    this.sourceExploreEnabledFilter = 'all';
    this.sourceLoginFilter = 'all';
    this.sourceValidationFilter = 'all';
    this.applySourceFilters();
  }

  activeSourceFilterCount(): number {
    let count = 0;
    if (this.sourceSortMode !== 'custom') count++;
    if (this.sourceEnabledFilter !== 'all') count++;
    if (this.sourceExplorePageFilter !== 'all') count++;
    if (this.sourceExploreEnabledFilter !== 'all') count++;
    if (this.sourceLoginFilter !== 'all') count++;
    if (this.sourceValidationFilter !== 'all') count++;
    return count;
  }

  hasActiveSourceFilters(): boolean {
    return this.activeSourceFilterCount() > 0;
  }

  sourceHasExplorePage(source: BookSource): boolean {
    return !!String(source.exploreUrl || '').trim();
  }

  isSourceAtBottom(source: BookSource): boolean {
    return this.allSources.length > 1 &&
      this.allSources[this.allSources.length - 1].bookSourceUrl === source.bookSourceUrl;
  }

  applySourceFilters(): void {
    const keyword = this.searchText.trim().toLowerCase();
    let filtered: BookSource[] = this.allSources;
    if (this.activeSourceGroup === '__ungrouped__') {
      filtered = filtered.filter((source: BookSource) => !(source.bookSourceGroup || '').trim());
    } else if (this.activeSourceGroup !== '__all__') {
      filtered = filtered.filter((source: BookSource) =>
        (source.bookSourceGroup || '').trim() === this.activeSourceGroup);
    }
    if (this.sourceEnabledFilter !== 'all') {
      const expected = this.sourceEnabledFilter === 'yes';
      filtered = filtered.filter((source: BookSource) => source.enabled === expected);
    }
    if (this.sourceExplorePageFilter !== 'all') {
      const expected = this.sourceExplorePageFilter === 'yes';
      filtered = filtered.filter((source: BookSource) => this.sourceHasExplorePage(source) === expected);
    }
    if (this.sourceExploreEnabledFilter !== 'all') {
      const expected = this.sourceExploreEnabledFilter === 'yes';
      filtered = filtered.filter((source: BookSource) => source.enabledExplore === expected);
    }
    if (this.sourceLoginFilter !== 'all') {
      const expected = this.sourceLoginFilter === 'yes';
      filtered = filtered.filter((source: BookSource) => this.sourceNeedsLogin(source) === expected);
    }
    if (this.sourceValidationFilter !== 'all') {
      const expected = this.sourceValidationStatusForFilter(this.sourceValidationFilter);
      filtered = filtered.filter((source: BookSource) => source.validationStatus === expected);
    }
    if (keyword) {
      filtered = filtered.filter((source: BookSource) => {
        const searchable = `${source.bookSourceName || ''}\n${source.bookSourceUrl || ''}\n${source.bookSourceGroup || ''}`;
        return searchable.toLowerCase().includes(keyword);
      });
    }
    this.sources = this.sortFilteredSources(filtered);
    this.visibleSources = this.sources;
    this.sourceListDataSource.replace(this.visibleSources, true);
    this.sourceFirstVisibleIndex = 0;
    this.sourceVisibleItemCount = 1;
    this.pruneSelectedSources();
  }

  sortFilteredSources(filtered: BookSource[]): BookSource[] {
    if (this.sourceSortMode === 'custom') return filtered.slice();
    const bottomUrl = this.allSources.length > 0 ?
      this.allSources[this.allSources.length - 1].bookSourceUrl : '';
    return filtered.slice().sort((left: BookSource, right: BookSource): number => {
      if (left.isPinned !== right.isPinned) return left.isPinned ? -1 : 1;
      if (!left.isPinned && left.bookSourceUrl === bottomUrl) return 1;
      if (!right.isPinned && right.bookSourceUrl === bottomUrl) return -1;
      if (this.sourceSortMode === 'name') {
        return (left.bookSourceName || '').localeCompare(right.bookSourceName || '');
      }
      const timeDiff = (left.lastUpdateTime || 0) - (right.lastUpdateTime || 0);
      if (timeDiff !== 0) return this.sourceSortMode === 'oldest' ? timeDiff : -timeDiff;
      return left.customOrder - right.customOrder;
    });
  }

  sourceValidationStatusForFilter(value: string): number {
    if (value === 'passed') return BookSource.VALIDATION_PASSED;
    if (value === 'failed') return BookSource.VALIDATION_FAILED;
    if (value === 'noResults') return BookSource.VALIDATION_NO_RESULTS;
    if (value === 'needsVerification') return BookSource.VALIDATION_NEEDS_VERIFICATION;
    if (value === 'temporaryError') return BookSource.VALIDATION_TEMPORARY_ERROR;
    return BookSource.VALIDATION_UNCHECKED;
  }

  currentSourceListDataSource(): BookSourceListDataSource {
    return this.sourceListDataSource;
  }

  ensureActiveSourceGroup(): void {
    if (this.activeSourceGroup === '__all__') {
      return;
    }
    if (this.activeSourceGroup === '__ungrouped__') {
      return;
    }
    if (!this.getSourceGroups().includes(this.activeSourceGroup)) {
      this.activeSourceGroup = '__all__';
    }
  }

  emptySourceTitle(): string {
    if (this.searchText.trim()) {
      return '未找到匹配书源';
    }
    if (this.hasActiveSourceFilters()) {
      return '筛选条件下暂无书源';
    }
    if (this.activeSourceGroup !== '__all__') {
      return '当前分组暂无书源';
    }
    return '暂无书源';
  }

  emptySourceDescription(): string {
    if (this.searchText.trim()) {
      return '请尝试其他关键词';
    }
    if (this.hasActiveSourceFilters()) {
      return '请调整或重置筛选条件';
    }
    if (this.activeSourceGroup !== '__all__') {
      return '可切换其他分组查看';
    }
    return '点击右下角"+"添加书源';
  }

  sourceNeedsLogin(source: BookSource): boolean {
    const loginUrl = String(source.loginUrl || '').trim();
    const loginUi = String(source.loginUi || '').trim();
    const loginCheckJs = String(source.loginCheckJs || '').trim();
    const loginHeader = String(source.loginHeader || '').trim();
    if (loginUrl || loginUi || loginCheckJs || loginHeader) {
      return true;
    }
    const rules = `${source.jsLib || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}\n` +
      `${source.bookInfoRule?.init || ''}\n${source.tocRule?.chapterList || ''}\n${source.contentRule?.content || ''}`;
    return /loginCheck|loginUrl|loginUi|book-source-login|请先登[录陆]|需要登[录陆]|账号登[录陆]|网页登录|登[录陆]后/i.test(rules);
  }

  sourceLoggedIn(source: BookSource): boolean {
    if (!this.sourceNeedsLogin(source)) {
      return false;
    }
    if (String(source.loginHeader || '').trim()) {
      return true;
    }
    const loginUrl = VerificationSupport.resolveBookSourceLoginUrl(source);
    const urls = [
      String(source.loginUrl || '').trim(),
      loginUrl,
      this.sourceUrlOrigin(loginUrl),
      String(source.bookSourceUrl || '').trim(),
      this.sourceUrlOrigin(String(source.bookSourceUrl || '').trim())
    ];
    for (const url of urls) {
      if (url && this.hasLoginCookie(CookieStore.getCookie(url))) {
        return true;
      }
    }
    return false;
  }

  hasLoginCookie(cookie: string): boolean {
    return VerificationSupport.hasEffectiveLoginCookie(cookie);
  }

  sourceUrlOrigin(url: string): string {
    const match = (url || '').match(/^(https?:\/\/[^/]+)/i);
    return match && match[1] ? match[1] : '';
  }

  async openSourceActions(source: BookSource, event?: GestureEvent): Promise<void> {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionSourceUrl = source.bookSourceUrl;
    this.actionSourceDetail = null;
    this.showSourceDeleteDialog = false;
    this.showSourceActionDialog = true;
    const detail = await AppDatabase.getInstance().getBookSource(source.bookSourceUrl);
    if (this.actionSourceUrl === source.bookSourceUrl) {
      this.actionSourceDetail = detail;
    }
  }

  updateContextViewport(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
    if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
  }

  contextMenuLeft(menuWidth: number): number {
    return Math.max(12, Math.min(this.contextMenuX - 18, this.contextViewportWidth - menuWidth - 12));
  }

  contextMenuTop(menuHeight: number): number {
    const below = this.contextMenuY + 12;
    if (below + menuHeight <= this.contextViewportHeight - 12) return below;
    return Math.max(this.statusBarHeight + 8, this.contextMenuY - menuHeight - 12);
  }

  closeSourceActions(): void {
    this.showSourceActionDialog = false;
    this.actionSourceUrl = '';
    this.actionSourceDetail = null;
  }

  enterActionSourceSelection(): void {
    const sourceUrl = this.actionSourceUrl;
    if (!sourceUrl) {
      return;
    }
    this.showSourceActionDialog = false;
    this.actionSourceUrl = '';
    this.actionSourceDetail = null;
    this.showAddDialog = false;
    this.showMoreActionDialog = false;
    this.selectionMode = true;
    this.selectedSourceUrls = [sourceUrl];
  }

  actionSource(): BookSource | null {
    if (this.actionSourceDetail && this.actionSourceDetail.bookSourceUrl === this.actionSourceUrl) {
      return this.actionSourceDetail;
    }
    return this.sources.find((source: BookSource) => source.bookSourceUrl === this.actionSourceUrl) || null;
  }

  actionSourceName(): string {
    const source = this.actionSource();
    return source ? (source.bookSourceName || source.bookSourceUrl) : '当前书源';
  }

  actionSourceNeedsLogin(): boolean {
    const source = this.actionSource();
    return source ? this.sourceNeedsLogin(source) : false;
  }

  actionSourceLoggedIn(): boolean {
    const source = this.actionSource();
    return source ? this.sourceLoggedIn(source) : false;
  }

  actionSourceEnabled(): boolean {
    const source = this.actionSource();
    return source ? source.enabled : false;
  }

  actionSourceLocked(): boolean {
    const source = this.actionSource();
    return source ? source.isLocked : false;
  }

  actionSourcePinned(): boolean {
    const source = this.actionSource();
    return source ? source.isPinned : false;
  }

  actionSourceTlsTrusted(): boolean {
    const source = this.actionSource();
    return source ? TlsTrustStore.isTrustedUrl(source.bookSourceUrl) : false;
  }

  sourceActionMenuHeight(): number {
    const trustHeight = this.actionSourceTlsTrusted() ? 44 : 0;
    const debugHeight = 44;
    if (this.actionSourceLocked()) {
      return (this.actionSourceNeedsLogin() ? 320 : 276) + trustHeight + debugHeight;
    }
    return (this.actionSourceNeedsLogin() ? 496 : 452) + trustHeight + debugHeight;
  }

  async revokeActionSourceTlsTrust(): Promise<void> {
    const source = this.actionSource();
    if (!source) return;
    const host = TlsTrustStore.hostFromUrl(source.bookSourceUrl);
    this.closeSourceActions();
    if (!host) return;
    try {
      await TlsTrustStore.revokeHost(getContext(this) as common.UIAbilityContext, host);
      promptAction.showToast({ message: `已恢复 ${host} 的严格证书校验` });
    } catch (e) {
      console.error('取消证书信任失败:', e);
      promptAction.showToast({ message: '取消证书信任失败' });
    }
  }

  async toggleActionSourcePinned(): Promise<void> {
    const source = this.actionSource();
    if (!source || this.isBatchOperating) return;
    const sourceUrl = source.bookSourceUrl;
    const pinned = !source.isPinned;
    this.closeSourceActions();
    const currentIndex = this.allSources.findIndex((item: BookSource) => item.bookSourceUrl === sourceUrl);
    if (currentIndex < 0) return;
    const next = this.allSources.slice();
    const moved = next.splice(currentIndex, 1)[0];
    moved.isPinned = pinned;
    await AppDatabase.getInstance().setBookSourcePinned(sourceUrl, pinned);
    if (pinned) {
      next.unshift(moved);
    } else {
      const pinnedCount = next.filter((item: BookSource) => item.isPinned).length;
      next.splice(pinnedCount, 0, moved);
    }
    await this.applyAndPersistSourceOrder(next, pinned ? '书源已置顶' : '已取消置顶');
  }

  async moveActionSourceToBottom(): Promise<void> {
    const source = this.actionSource();
    if (!source || this.isBatchOperating) return;
    const sourceUrl = source.bookSourceUrl;
    this.closeSourceActions();
    const currentIndex = this.allSources.findIndex((item: BookSource) => item.bookSourceUrl === sourceUrl);
    if (currentIndex < 0) return;
    const next = this.allSources.slice();
    const moved = next.splice(currentIndex, 1)[0];
    moved.isPinned = false;
    await AppDatabase.getInstance().setBookSourcePinned(sourceUrl, false);
    next.push(moved);
    await this.applyAndPersistSourceOrder(next, '书源已置底');
  }

  openActionSourceGroup(): void {
    const source = this.actionSource();
    if (!source) return;
    if (source.isLocked) {
      this.closeSourceActions();
      promptAction.showToast({ message: '请先解锁书源' });
      return;
    }
    const sourceUrl = source.bookSourceUrl;
    const groupName = source.bookSourceGroup || '';
    this.closeSourceActions();
    this.groupActionSourceUrl = sourceUrl;
    this.groupNameInput = groupName;
    this.showGroupDialog = true;
  }

  async toggleActionSourceLocked(): Promise<void> {
    const source = this.actionSource();
    if (!source || this.isBatchOperating) return;
    const locked = !source.isLocked;
    await AppDatabase.getInstance().setBookSourceLocked(source.bookSourceUrl, locked);
    source.isLocked = locked;
    this.closeSourceActions();
    await this.loadSources();
    promptAction.showToast({ message: locked ? '书源已锁定' : '书源已解锁' });
  }

  openActionSourceSearch(): void {
    const source = this.actionSource();
    if (!source) {
      this.closeSourceActions();
      promptAction.showToast({ message: '书源不存在' });
      return;
    }
    const nonce = AppStorage.get<number>('singleSourceSearchNonce') || 0;
    AppStorage.setOrCreate('singleSourceSearchUrl', source.bookSourceUrl);
    AppStorage.setOrCreate('singleSourceSearchName', source.bookSourceName || source.bookSourceUrl);
    AppStorage.setOrCreate('singleSourceSearchNonce', nonce + 1);
    this.closeSourceActions();
    router.back();
  }

  async openActionSourceLogin(): Promise<void> {
    const summary = this.actionSource();
    if (!summary) {
      return;
    }
    const source = await AppDatabase.getInstance().getBookSource(summary.bookSourceUrl);
    if (!source || !this.sourceNeedsLogin(source)) {
      promptAction.showToast({ message: '书源不存在' });
      return;
    }
    this.showSourceActionDialog = false;
    const dynamicLoginUi = BookSourceScriptRunner.dynamicLoginUiScript(source);
    let loginItems: BookSourceLoginItem[] = [];
    try {
      loginItems = await this.resolveSourceLoginItems(source);
    } catch (error) {
      this.actionSourceUrl = '';
      promptAction.showToast({
        message: `登录界面脚本执行失败：${this.importErrorMessage(error as Object)}`
      });
      return;
    }
    if (loginItems.length > 0) {
      const loginInfo = BookSourceLoginWebRuntime.parseRecord(source.loginInfo);
      let compatibilityValueSeeded = false;
      for (const item of loginItems) {
        const compatibilityDefault = this.sourceLoginCompatibilityDefault(source, item);
        if (compatibilityDefault && loginInfo[item.name] === undefined) {
          loginInfo[item.name] = compatibilityDefault;
          compatibilityValueSeeded = true;
        }
        if ((this.isSourceLoginInput(item) || this.isSourceLoginChoice(item)) &&
          loginInfo[item.name] !== undefined) {
          item.value = loginInfo[item.name];
        } else if (this.isSourceLoginChoice(item) && !item.value) {
          item.value = item.defaultValue || (item.chars.length > 0 ? item.chars[0] : '');
        }
      }
      this.hydrateSourceLoginItemStates(source, loginItems);
      this.actionSourceDetail = source;
      this.sourceLoginItems = loginItems;
      if (compatibilityValueSeeded) {
        source.loginInfo = BookSourceLoginWebRuntime.mergeRecord(source.loginInfo, loginInfo);
        await AppDatabase.getInstance().updateBookSourceLoginRuntime(source.bookSourceUrl,
          source.variable, source.loginHeader, source.loginInfo);
      }
      this.showSourceLoginUiDialog = true;
      return;
    }
    if (dynamicLoginUi) {
      this.actionSourceUrl = '';
      promptAction.showToast({ message: '登录界面脚本未返回有效控件，请检查书源 loginUi 配置' });
      return;
    }
    const loginEntryUrl = VerificationSupport.resolveBookSourceLoginUrl(source) ||
      VerificationSupport.pickVerificationUrl(source, source.bookSourceUrl);
    if (!loginEntryUrl || !/^https?:\/\//i.test(loginEntryUrl)) {
      this.actionSourceUrl = '';
      promptAction.showToast({ message: '未找到可用的网页登录地址，请检查书源登录配置' });
      return;
    }
    this.openSourceLoginBrowser(source, loginEntryUrl, `${source.bookSourceName || '书源'} 登录`, true);
  }

  async resolveSourceLoginItems(source: BookSource): Promise<BookSourceLoginItem[]> {
    const dynamicScript = BookSourceScriptRunner.dynamicLoginUiScript(source);
    if (!dynamicScript) return BookSourceScriptRunner.loginItems(source);
    const staticItems = BookSourceScriptRunner.loginItems(source);
    if (staticItems.length > 0) return staticItems;
    const result = await this.runSourceLoginAction(source, dynamicScript);
    if (result.errorMessage) throw new Error(result.errorMessage);
    return BookSourceScriptRunner.parseLoginItems(result.resultValue);
  }

  sourceLoginCompatibilityDefault(source: BookSource, item: BookSourceLoginItem): string {
    // Login values and API credentials must come from the user/imported source. The application
    // never supplies a service-specific default credential.
    return '';
  }

  async executeSourceLoginAction(item: BookSourceLoginItem): Promise<void> {
    const currentSource = this.actionSourceDetail;
    if (!currentSource || !item.action || this.isExecutingLoginAction) return;
    if (BookSourceRuntimeRouter.isDirectUrlAction(item.action)) {
      this.showSourceLoginUiDialog = false;
      this.sourceLoginItems = [];
      this.openSourceLoginBrowser(currentSource, item.action.trim(),
        `${currentSource.bookSourceName || '书源'} · ${item.name}`, /(?:登录|login)/i.test(item.name));
      return;
    }
    this.isExecutingLoginAction = true;
    this.syncSourceLoginInfo(currentSource);
    try {
      let source = currentSource;
      const persistedSource = await AppDatabase.getInstance().getBookSource(currentSource.bookSourceUrl);
      if (persistedSource) {
        const inputValues = BookSourceLoginWebRuntime.parseRecord(currentSource.loginInfo);
        persistedSource.loginInfo = BookSourceLoginWebRuntime.mergeRecord(persistedSource.loginInfo, inputValues);
        source = persistedSource;
        this.actionSourceDetail = source;
      }
      const previousVariable = source.variable || '';
      const result = await this.runSourceLoginAction(source, item.action);
      if (result.errorMessage) throw new Error(result.errorMessage);
      source.variable = result.variable;
      source.loginHeader = result.loginHeader;
      source.loginInfo = result.loginInfo;
      await AppDatabase.getInstance().updateBookSourceLoginRuntime(source.bookSourceUrl,
        source.variable, source.loginHeader, source.loginInfo);
      if (this.shouldInvalidateExploreAfterLoginAction(item, result)) {
        await this.invalidateRuntimeExplore(source);
      }
      if (result.refreshLoginRequested) {
        const refreshedItems = await this.resolveSourceLoginItems(source);
        this.sourceLoginItems = refreshedItems;
        this.refreshSourceLoginItemsFromRuntime(source);
      }
      this.hydrateSourceLoginItemStates(source, this.sourceLoginItems, result.toastMessage, item.name);
      this.sourceLoginItems = this.sourceLoginItems.slice();
      this.markSourceLoginCompleted(item, result);
      if (result.toastMessage) {
        promptAction.showToast({ message: result.toastMessage.trim() || '操作成功' });
      } else if (result.variable !== previousVariable && result.variable.trim()) {
        promptAction.showToast({ message: /token/i.test(`${item.name}\n${item.action}`) ?
          'Token 已获取并保存到书源变量' : '书源变量已更新' });
      } else if (result.logMessage) {
        promptAction.showToast({ message: result.logMessage.trim() });
      } else if (!result.requestedSearchKeyword && !result.refreshExploreRequested &&
        !result.requestedUrl && !result.requestedHtml) {
        promptAction.showToast({ message: '操作已执行，书源没有返回提示信息' });
      }
      if (result.requestedSearchKeyword) {
        this.openRuntimeSourceSearch(source, result.requestedSearchKeyword);
        return;
      }
      if (result.refreshExploreRequested) {
        await this.refreshRuntimeExplore(source);
        return;
      }
      if (result.requestedUrl || result.requestedHtml) {
        this.showSourceLoginUiDialog = false;
        this.sourceLoginItems = [];
        const isLogin = /(?:登录|login)/i.test(item.name) ||
          /\/login(?:\.html)?(?:[?#]|$)/i.test(result.requestedUrl);
        this.openSourceLoginBrowser(source, result.requestedUrl || 'about:blank',
          result.requestedTitle || `${source.bookSourceName || '书源'} · ${item.name}`, isLogin,
          '', result.requestedHtml, result.requestedInjectJs);
        return;
      }
      this.actionSourceDetail = source;
      if (this.sourceLoginItems.length > 0) {
        this.refreshSourceLoginItemsFromRuntime(source);
        this.showSourceLoginUiDialog = true;
      }
    } catch (error) {
      console.error('[SourceLoginRuntime] action failed:', currentSource.bookSourceName, item.name,
        this.importErrorMessage(error as Object));
      const missing = BookSourceRuntimeRouter.missingCapabilityMessage(this.loginRuntimeDecision);
      promptAction.showToast({
        message: `登录动作失败：${this.importErrorMessage(error as Object)}${missing ? `\n${missing}` : ''}`
      });
    } finally {
      this.isExecutingLoginAction = false;
    }
  }

  isSourceLoginInput(item: BookSourceLoginItem): boolean {
    const type = (item.type || '').toLowerCase();
    return type === 'text' || type === 'password' || type === 'email' || type === 'number' || type === 'input';
  }

  isSourceLoginToggle(item: BookSourceLoginItem): boolean {
    return (item.type || '').toLowerCase() === 'toggle';
  }

  isSourceLoginSelect(item: BookSourceLoginItem): boolean {
    return (item.type || '').toLowerCase() === 'select';
  }

  isSourceLoginChoice(item: BookSourceLoginItem): boolean {
    return this.isSourceLoginToggle(item) || this.isSourceLoginSelect(item);
  }

  sourceLoginItemDisplayName(item: BookSourceLoginItem): string {
    const viewName = (item.viewName || '').trim().replace(/^(['"])(.*)\1$/, '$2').trim();
    return viewName || item.name;
  }

  sourceLoginChoiceValue(item: BookSourceLoginItem): string {
    return (item.value || item.defaultValue || (item.chars.length > 0 ? item.chars[0] : '')).trim();
  }

  sourceLoginToggleOn(item: BookSourceLoginItem): boolean {
    const value = this.sourceLoginChoiceValue(item);
    if (item.chars.length > 1) return value === item.chars[1];
    return /^(?:true|1|on|yes|enabled|enable|开启|已开启|✅)$/i.test(value);
  }

  sourceLoginSelectOptions(item: BookSourceLoginItem): SelectOption[] {
    const options: SelectOption[] = [];
    for (const value of item.chars) options.push({ value: value });
    if (options.length === 0) options.push({ value: this.sourceLoginChoiceValue(item) || '未设置' });
    return options;
  }

  sourceLoginSelectIndex(item: BookSourceLoginItem): number {
    const index = item.chars.indexOf(this.sourceLoginChoiceValue(item));
    return index >= 0 ? index : 0;
  }

  sourceLoginButtonLabel(item: BookSourceLoginItem): string {
    return item.status ? `${item.name} · ${item.status}` : item.name;
  }

  sourceLoginItemRenderKey(item: BookSourceLoginItem, index: number): string {
    let renderState = '';
    if (this.isSourceLoginChoice(item)) {
      renderState = this.sourceLoginChoiceValue(item);
    } else if (!this.isSourceLoginInput(item)) {
      renderState = item.status || '';
    }
    return `${index}_${item.name}_${item.type}_${item.action}_${renderState}`;
  }

  updateSourceLoginToggle(index: number, isOn: boolean): void {
    if (index < 0 || index >= this.sourceLoginItems.length) return;
    const item = this.sourceLoginItems[index];
    const offValue = item.chars.length > 0 ? item.chars[0] : 'false';
    const onValue = item.chars.length > 1 ? item.chars[1] : 'true';
    this.updateSourceLoginChoice(index, isOn ? onValue : offValue);
  }

  updateSourceLoginSelect(index: number, selectedIndex: number): void {
    if (index < 0 || index >= this.sourceLoginItems.length) return;
    const item = this.sourceLoginItems[index];
    if (selectedIndex < 0 || selectedIndex >= item.chars.length) return;
    this.updateSourceLoginChoice(index, item.chars[selectedIndex]);
  }

  updateSourceLoginChoice(index: number, value: string): void {
    if (index < 0 || index >= this.sourceLoginItems.length) return;
    const items = this.sourceLoginItems.slice();
    const copy = this.copySourceLoginItem(items[index]);
    copy.value = value;
    items[index] = copy;
    this.sourceLoginItems = items;
    const source = this.actionSourceDetail;
    if (!source) return;
    this.syncSourceLoginInfo(source);
    AppDatabase.getInstance().updateBookSourceLoginRuntime(source.bookSourceUrl,
      source.variable, source.loginHeader, source.loginInfo).catch((error: Object): void => {
      console.warn('保存书源登录选项失败:', error);
    });
    if (copy.action) this.executeSourceLoginAction(copy);
  }

  copySourceLoginItem(item: BookSourceLoginItem): BookSourceLoginItem {
    const copy = new BookSourceLoginItem();
    copy.name = item.name;
    copy.type = item.type;
    copy.action = item.action;
    copy.value = item.value;
    copy.placeholder = item.placeholder;
    copy.viewName = item.viewName;
    copy.chars = item.chars.slice();
    copy.defaultValue = item.defaultValue;
    copy.status = item.status;
    return copy;
  }

  markSourceLoginCompleted(item: BookSourceLoginItem, result: LoginRuntimeStep): void {
    if (!/(?:登录|login)/i.test(`${item.name}\n${item.action}`)) return;
    const message = result.toastMessage || '';
    if (result.errorMessage || /(?:失败|错误|未登录|请先|请输入)/.test(message)) return;
    const operations = BookSourceLoginWebRuntime.parseCookieOperations(result.cookieOperations);
    const hasLoginCookie = operations.some((operation: LoginCookieOperation): boolean =>
      operation.operation === 'set' && operation.value.includes('='));
    if (!(result.loginHeader || '').trim() && !hasLoginCookie && !/(?:成功|欢迎回来|已登录)/.test(message)) return;
    AppStorage.setOrCreate('pendingVerificationUrl', '');
    AppStorage.setOrCreate('pendingVerificationTitle', '');
    AppStorage.setOrCreate('verificationCompletedAt', Date.now());
  }

  updateSourceLoginInput(index: number, value: string): void {
    if (index < 0 || index >= this.sourceLoginItems.length) return;
    const items = this.sourceLoginItems.slice();
    const copy = this.copySourceLoginItem(items[index]);
    copy.value = value;
    items[index] = copy;
    this.sourceLoginItems = items;
  }

  syncSourceLoginInfo(source: BookSource): void {
    const values = BookSourceLoginWebRuntime.parseRecord(source.loginInfo);
    for (const item of this.sourceLoginItems) {
      if ((this.isSourceLoginInput(item) || this.isSourceLoginChoice(item)) && item.name) {
        values[item.name] = item.value || item.defaultValue || '';
      }
    }
    source.loginInfo = BookSourceLoginWebRuntime.mergeRecord(source.loginInfo, values);
  }

  refreshSourceLoginItemsFromRuntime(source: BookSource): void {
    const values = BookSourceLoginWebRuntime.parseRecord(source.loginInfo);
    const items = this.sourceLoginItems.slice();
    for (let index = 0; index < items.length; index++) {
      const item = items[index];
      if ((!this.isSourceLoginInput(item) && !this.isSourceLoginChoice(item)) ||
        values[item.name] === undefined) continue;
      const copy = this.copySourceLoginItem(item);
      copy.value = values[item.name];
      items[index] = copy;
    }
    this.sourceLoginItems = items;
  }

  hydrateSourceLoginItemStates(source: BookSource, items: BookSourceLoginItem[],
    toastMessage: string = '', targetName: string = ''): void {
    const states: Record<string, string> = {};
    this.appendSourceLoginStateValues(states, BookSourceLoginWebRuntime.parseRecord(source.loginInfo), '', 0);
    this.appendSourceLoginStateValues(states, BookSourceLoginWebRuntime.runtimeState(source.loginInfo), '', 0);
    this.appendSourceLoginVariableValues(states, source.variable || '');
    const toastStatus = this.sourceLoginStatusFromToast(toastMessage);
    for (const item of items) {
      if (this.isSourceLoginChoice(item) || this.isSourceLoginInput(item)) continue;
      item.status = this.sourceLoginStoredButtonStatus(item, states);
      if (!item.status && source.variable.trim().length > 60 &&
        /(?:邀请码.*注册|注册.*token)/i.test(item.name)) item.status = '已获取';
      if (toastStatus && targetName && item.name === targetName && !item.status) item.status = toastStatus;
    }
  }

  appendSourceLoginVariableValues(states: Record<string, string>, raw: string): void {
    const value = (raw || '').trim();
    if (!value) return;
    try {
      const parsed = JSON.parse(value) as Object;
      this.appendSourceLoginStateValues(states, parsed, 'variable', 0);
    } catch (_) {
      const parts = value.split(/&&|[&;,\n]/);
      for (const part of parts) {
        const match = part.match(/^\s*([^=:]+)\s*[=:]\s*(.*?)\s*$/);
        if (!match) continue;
        const key = this.normalizeSourceLoginStateKey(match[1]);
        if (key) states[key] = match[2] || '';
      }
    }
  }

  appendSourceLoginStateValues(states: Record<string, string>, value: Object,
    parentKey: string, depth: number): void {
    if (depth > 6 || value === null || value === undefined) return;
    if (Array.isArray(value)) {
      const values = value as Object[];
      for (const item of values) this.appendSourceLoginStateValues(states, item, parentKey, depth + 1);
      return;
    }
    if (typeof value !== 'object') {
      const normalized = this.normalizeSourceLoginStateKey(parentKey);
      if (normalized) states[normalized] = String(value);
      return;
    }
    const record = value as Record<string, Object>;
    const recordKeys = Object.keys(record);
    for (const key of recordKeys) {
      const childKey = parentKey ? `${parentKey}.${key}` : key;
      const child = record[key];
      if (child !== null && child !== undefined && typeof child === 'object') {
        this.appendSourceLoginStateValues(states, child, childKey, depth + 1);
      } else {
        const normalized = this.normalizeSourceLoginStateKey(childKey);
        if (normalized) states[normalized] = String(child === null || child === undefined ? '' : child);
        const shortKey = this.normalizeSourceLoginStateKey(key);
        if (shortKey) states[shortKey] = String(child === null || child === undefined ? '' : child);
      }
    }
  }

  normalizeSourceLoginStateKey(value: string): string {
    return (value || '').toLowerCase().replace(/[\s\p{P}\p{S}]/gu, '');
  }

  sourceLoginStoredButtonStatus(item: BookSourceLoginItem, states: Record<string, string>): string {
    const name = this.normalizeSourceLoginStateKey(item.name);
    const action = (item.action || '').toLowerCase();
    const choiceStatus = this.sourceLoginStoredChoiceStatus(action, states);
    if (choiceStatus) return choiceStatus;
    const switchLike = name.includes('开关') || name.includes('同步') || name.includes('显示') ||
      name.includes('简介') || name.includes('网络模式') ||
      /toggle|switch|paracomment|closeimg|set_info|ste\s*\(/i.test(action);
    if (!switchLike) return '';
    const aliases: string[] = [];
    if (name.includes('段评')) aliases.push('段评开关', 'yunpara', 'fqpara', 'paras');
    if (name.includes('图片')) aliases.push('显示图片', '图片开关', 'closeimg', 'close_img');
    if (name.includes('简介')) aliases.push('完整简介', '简介开关', 'info');
    if (name.includes('同步')) aliases.push('同步书架', 'booksync', 'book_sync');
    if (name.includes('目录')) aliases.push('目录显示来源', '目录显示来源开关');
    if (name.includes('网络')) aliases.push('网络模式');
    if (name.includes('下载')) aliases.push('fqdown', 'txt下载开关');
    const switchArgument = action.match(/\b(?:switchsetting|toggle|switch)\s*\(\s*(['"])(.*?)\1/i);
    if (switchArgument && switchArgument[2]) aliases.push(switchArgument[2]);
    aliases.push(item.name.replace(/开关/g, ''), item.name);
    for (const alias of aliases) {
      const normalizedAlias = this.normalizeSourceLoginStateKey(alias);
      if (!normalizedAlias) continue;
      const stateKeys = Object.keys(states);
      for (const key of stateKeys) {
        if (key !== normalizedAlias && !key.endsWith(normalizedAlias) && !normalizedAlias.endsWith(key)) continue;
        return this.sourceLoginStatusLabel(states[key], key.includes('closeimg'));
      }
    }
    return '';
  }

  sourceLoginStoredChoiceStatus(action: string, states: Record<string, string>): string {
    let stateKey = '';
    let expectedValue = '';
    let match = action.match(/\bsettype\s*\(\s*(['"])(.*?)\1/i);
    if (match && match[2] !== undefined) {
      stateKey = 'type';
      expectedValue = match[2];
    } else {
      match = action.match(/\bsetorder\s*\(\s*(['"]?)([^,'"\s)]+)\1/i);
      if (match && match[2] !== undefined) {
        stateKey = 'order';
        expectedValue = match[2];
      } else {
        match = action.match(/\bsetgender\s*\(\s*(['"]?)([^,'"\s)]+)\1/i);
        if (match && match[2] !== undefined) {
          stateKey = 'gender';
          expectedValue = match[2];
        } else {
          match = action.match(/\bsource\.put\s*\(\s*(['"])(.*?)\1\s*,\s*(['"]?)([^,'"\s)]+)\3/i);
          if (match && match[2] !== undefined && match[4] !== undefined) {
            stateKey = match[2];
            expectedValue = match[4];
          }
        }
      }
    }
    const normalizedKey = this.normalizeSourceLoginStateKey(stateKey);
    if (!normalizedKey || states[normalizedKey] === undefined) return '';
    const stored = String(states[normalizedKey] || '').trim().toLowerCase();
    const expected = String(expectedValue || '').trim().toLowerCase();
    return stored === expected ? '已选' : '';
  }

  sourceLoginStatusLabel(value: string, inverted: boolean = false): string {
    const normalized = (value || '').trim().toLowerCase();
    let enabled = false;
    let recognized = true;
    if (/^(?:true|1|on|yes|enabled|enable|开启|已开启|✅)$/.test(normalized)) enabled = true;
    else if (/^(?:false|0|off|no|disabled|disable|关闭|已关闭|❌)$/.test(normalized)) enabled = false;
    else recognized = false;
    if (recognized) {
      if (inverted) enabled = !enabled;
      return enabled ? '已开启' : '已关闭';
    }
    if (!normalized || normalized === 'undefined' || normalized === 'null') return '';
    return value.length > 16 ? '' : value;
  }

  sourceLoginStatusFromToast(message: string): string {
    const text = (message || '').replace(/\s+/g, '');
    if (!text) return '';
    if (/已关闭|❌.*关闭|不显示|已精简|停止同步/.test(text)) return '已关闭';
    if (/已开启|✅.*开启|显示文中图片|已恢复.*简介|自动同步/.test(text)) return '已开启';
    const mode = text.match(/(?:切换为|设置[^为]*为)[：:\s]*([^，。\n]{1,12})(?:模式)?/);
    return mode ? mode[1].replace(/模式$/, '').trim() : '';
  }

  openRuntimeSourceSearch(source: BookSource, keyword: string): void {
    const value = (keyword || '').trim();
    if (!value) return;
    const nonce = AppStorage.get<number>('singleSourceSearchNonce') || 0;
    AppStorage.setOrCreate('singleSourceSearchUrl', source.bookSourceUrl);
    AppStorage.setOrCreate('singleSourceSearchName', source.bookSourceName || source.bookSourceUrl);
    AppStorage.setOrCreate('singleSourceSearchKeyword', value);
    AppStorage.setOrCreate('singleSourceSearchNonce', nonce + 1);
    this.showSourceLoginUiDialog = false;
    this.sourceLoginItems = [];
    router.back();
  }

  async refreshRuntimeExplore(source: BookSource): Promise<void> {
    await this.invalidateRuntimeExplore(source);
    this.showSourceLoginUiDialog = false;
    this.sourceLoginItems = [];
    router.back();
  }

  shouldInvalidateExploreAfterLoginAction(item: BookSourceLoginItem, result: LoginRuntimeStep): boolean {
    const action = `${item.name}\n${item.action}`;
    if (!/(?:登[录陆]|退出|注销|令牌|token)/i.test(action)) return false;
    const outcome = `${result.resultValue || ''}\n${result.toastMessage || ''}`.trim();
    if (/失败|无效|未登[录陆]|请先|错误|异常/i.test(outcome)) return false;
    return /^(?:true|1)(?:\s|$)/i.test(outcome) ||
      /登[录陆]成功|令牌已生效|已退出|已注销|已清除.*(?:登录|令牌|凭证|状态)/i.test(outcome);
  }

  async invalidateRuntimeExplore(source: BookSource): Promise<void> {
    try {
      await ExploreResultCache.clearSource(getContext(this), source.bookSourceUrl);
    } catch (error) {
      console.warn('清理发现缓存失败，将继续请求刷新:', error);
    }
    const nonce = AppStorage.get<number>('bookSourceExploreRefreshNonce') || 0;
    AppStorage.setOrCreate('bookSourceExploreRefreshSourceUrl', source.bookSourceUrl);
    AppStorage.setOrCreate('exploreSourceUrl', source.bookSourceUrl);
    AppStorage.setOrCreate('bookSourceExploreRefreshNonce', nonce + 1);
  }

  saveSourceLoginInputs(): void {
    const source = this.actionSourceDetail;
    if (!source) return;
    this.syncSourceLoginInfo(source);
    AppDatabase.getInstance().updateBookSourceLoginRuntime(source.bookSourceUrl,
      source.variable, source.loginHeader, source.loginInfo).catch((error: Object): void => {
      console.warn('保存书源登录输入失败:', error);
    });
  }

  runSourceLoginAction(source: BookSource, action: string): Promise<LoginRuntimeStep> {
    if (this.loginRuntimeResolve || this.loginRuntimeReject) {
      return Promise.reject(new Error('已有登录动作正在执行'));
    }
    const decision = BookSourceRuntimeRouter.decide(SourceRuntimeStage.LOGIN,
      `${source.jsLib || ''}\n${source.loginUrl || ''}\n${action || ''}`);
    this.loginRuntimeDecision = decision;
    if (decision.capabilities.usesUnmanagedNetwork) {
      return Promise.reject(new Error('登录脚本包含未受执行日志保护的浏览器网络请求，请改用 java.ajax'));
    }
    this.loginRuntimeSource = source;
    this.loginRuntimeBaseSource = this.copyBookSourceRuntime(source);
    this.loginRuntimeAction = action;
    this.loginRuntimeJournal.reset();
    this.loginRuntimeCookies = {};
    this.loginRuntimeCookieUrls = [];
    this.loginRuntimeRequestCount = 0;
    this.loginRuntimeFixedNow = Date.now();
    this.loginRuntimeRandomSeed = Math.max(1, Math.floor(Math.random() * 0x7fffffff));
    this.loginRuntimeCookieSnapshots = {};
    this.loginRuntimeAwaitingBrowser = false;
    this.loginRuntimeBrowserToken = '';
    this.loginRuntimeBrowserUrl = '';
    this.loginRuntimeStepRunning = false;
    return new Promise<LoginRuntimeStep>((resolve, reject) => {
      this.loginRuntimeResolve = resolve;
      this.loginRuntimeReject = reject;
      this.loginRuntimeActive = true;
      this.armLoginRuntimeTimeout();
      if (this.loginRuntimeReady) this.continueLoginRuntime();
    });
  }

  armLoginRuntimeTimeout(): void {
    if (this.loginRuntimeTimeoutId >= 0) clearTimeout(this.loginRuntimeTimeoutId);
    this.loginRuntimeTimeoutId = setTimeout(() => {
      const message = this.loginRuntimeReady ? '登录脚本执行超时' : '登录脚本运行环境未就绪';
      this.finishLoginRuntime(null, message);
    }, 60000);
  }

  continueLoginRuntime(): void {
    if (!this.loginRuntimeActive || this.loginRuntimeStepRunning || !this.loginRuntimeSource) return;
    this.loginRuntimeStepRunning = true;
    this.executeLoginRuntimeStep().catch((error: Object): void => {
      this.finishLoginRuntime(null, this.importErrorMessage(error));
    });
  }

  async executeLoginRuntimeStep(): Promise<void> {
    const source = this.loginRuntimeSource;
    const baseSource = this.loginRuntimeBaseSource;
    if (!source || !baseSource || !this.loginRuntimeActive) return;
    const script = BookSourceLoginWebRuntime.buildScript(baseSource, this.loginRuntimeAction,
      this.loginRuntimeJournal.responses, this.loginRuntimeCookies,
      this.loginRuntimeFixedNow, this.loginRuntimeRandomSeed,
      this.loginRuntimeJournal.appliedOperations('cookie'));
    const raw = await this.runLoginRuntimeScript(script);
    const step = BookSourceLoginWebRuntime.parseResult(raw);
    this.applyLoginCookieOperations(step.cookieOperations);
    if (step.pendingCrypto) {
      const responseKey = `crypto:${step.pendingCrypto}`;
      if (!this.loginRuntimeJournal.hasResponse(responseKey)) {
        const response = await BookSourceLoginCrypto.execute(step.pendingCrypto);
        if (!this.loginRuntimeActive) return;
        this.loginRuntimeJournal.recordResponse(responseKey, response);
      }
      this.loginRuntimeStepRunning = false;
      this.continueLoginRuntime();
      return;
    }
    if (step.pendingCookie) {
      this.snapshotLoginRuntimeCookie(step.pendingCookie);
      this.loginRuntimeCookies[step.pendingCookie] = CookieStore.getCookie(step.pendingCookie);
      if (!this.loginRuntimeCookieUrls.includes(step.pendingCookie)) {
        this.loginRuntimeCookieUrls.push(step.pendingCookie);
      }
      this.loginRuntimeStepRunning = false;
      this.continueLoginRuntime();
      return;
    }
    if (step.pendingWebView) {
      const responseKey = `webview:${step.pendingWebView}`;
      if (!this.loginRuntimeJournal.hasResponse(responseKey)) {
        const response = await this.evaluateLoginRuntimeWebView(step.pendingWebView);
        if (!this.loginRuntimeActive) return;
        this.loginRuntimeJournal.recordResponse(responseKey, response);
      }
      this.loginRuntimeReady = false;
      try {
        this.loginRuntimeController.loadUrl('about:blank');
      } catch (_) {}
      this.loginRuntimeStepRunning = false;
      return;
    }
    if (step.pendingAjax) {
      if (this.loginRuntimeJournal.hasResponse(step.pendingAjax)) {
        this.loginRuntimeStepRunning = false;
        this.continueLoginRuntime();
        return;
      }
      this.loginRuntimeRequestCount++;
      if (this.loginRuntimeRequestCount > 12) {
        this.finishLoginRuntime(null, '登录脚本网络请求次数过多');
        return;
      }
      if (!this.loginRuntimeJournal.markRequestStarted(step.pendingAjax)) {
        this.finishLoginRuntime(null, '登录脚本重复请求未完成，已停止以避免重复提交');
        return;
      }
      const requestSource = this.copyBookSourceRuntime(baseSource);
      requestSource.variable = step.variable;
      requestSource.loginHeader = step.loginHeader;
      requestSource.loginInfo = step.loginInfo;
      this.snapshotLoginRuntimeRequestCookie(step.pendingAjax);
      const response = await this.fetchLoginRuntimeRequest(requestSource, step.pendingAjax);
      if (!this.loginRuntimeActive) return;
      if (!response.success && response.statusCode === 521) {
        this.finishLoginRuntime(null, '接口请求失败（HTTP 521）：服务端源站当前离线，请稍后重试');
        return;
      }
      if (!response.success && !response.body) {
        this.finishLoginRuntime(null, response.error || `HTTP ${response.statusCode}`);
        return;
      }
      this.loginRuntimeJournal.recordResponse(step.pendingAjax, response.body || '');
      for (const key of this.loginRuntimeCookieUrls) {
        this.loginRuntimeCookies[key] = CookieStore.getCookie(key);
      }
      this.loginRuntimeStepRunning = false;
      this.continueLoginRuntime();
      return;
    }
    if (step.pendingBrowserAwait) {
      this.suspendLoginRuntimeForBrowser(step);
      return;
    }
    if (step.errorMessage) {
      this.finishLoginRuntime(step, step.errorMessage);
      return;
    }
    this.finishLoginRuntime(step);
  }

  copyBookSourceRuntime(source: BookSource): BookSource {
    const copy = new BookSource();
    copy.bookSourceUrl = source.bookSourceUrl;
    copy.bookSourceName = source.bookSourceName;
    copy.bookSourceType = source.bookSourceType;
    copy.bookSourceGroup = source.bookSourceGroup;
    copy.bookSourceComment = source.bookSourceComment;
    copy.loginUrl = source.loginUrl;
    copy.loginUi = source.loginUi;
    copy.loginCheckJs = source.loginCheckJs;
    copy.loginHeader = source.loginHeader;
    copy.loginInfo = source.loginInfo;
    copy.rawSourceJson = source.rawSourceJson;
    copy.bookUrlPattern = source.bookUrlPattern;
    copy.searchUrl = source.searchUrl;
    copy.exploreUrl = source.exploreUrl;
    copy.jsLib = source.jsLib;
    copy.header = source.header;
    copy.bookListRule = source.bookListRule;
    copy.searchRule = source.searchRule;
    copy.exploreRule = source.exploreRule;
    copy.bookInfoRule = source.bookInfoRule;
    copy.tocRule = source.tocRule;
    copy.contentRule = source.contentRule;
    copy.variableComment = source.variableComment;
    copy.variable = source.variable;
    copy.lastUpdateTime = source.lastUpdateTime;
    copy.respondTime = source.respondTime;
    copy.customOrder = source.customOrder;
    copy.customButton = source.customButton;
    copy.eventListener = source.eventListener;
    copy.isPinned = source.isPinned;
    copy.enabled = source.enabled;
    copy.enabledExplore = source.enabledExplore;
    copy.isLocked = source.isLocked;
    copy.validationStatus = source.validationStatus;
    copy.weight = source.weight;
    copy.concurrentRate = source.concurrentRate;
    copy.enabledCookieJar = source.enabledCookieJar;
    return copy;
  }

  runLoginRuntimeScript(script: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      let completed = false;
      const timeoutId = setTimeout(() => {
        if (completed) return;
        completed = true;
        this.loginRuntimeReady = false;
        try {
          this.loginRuntimeController.loadUrl('about:blank');
        } catch (_) {}
        reject(new Error('登录脚本引擎响应超时'));
      }, 15000);
      this.loginRuntimeController.runJavaScript(script)
        .then((result: string): void => {
          if (completed) return;
          completed = true;
          clearTimeout(timeoutId);
          resolve(result);
        })
        .catch((error: Object): void => {
          if (completed) return;
          completed = true;
          clearTimeout(timeoutId);
          reject(error);
        });
    });
  }

  async evaluateLoginRuntimeWebView(rawRequest: string): Promise<string> {
    let url = '';
    let script = '';
    try {
      const request = JSON.parse(rawRequest || '{}') as Record<string, Object>;
      url = String(request['url'] || '');
      script = String(request['script'] || '');
    } catch (_) {}
    if (!/^https?:\/\//i.test(url)) throw new Error('java.webView 地址无效');
    await new Promise<void>((resolve, reject) => {
      let completed = false;
      const timer = setTimeout(() => {
        if (completed) return;
        completed = true;
        this.loginRuntimeWebViewPageResolve = null;
        reject(new Error('java.webView 页面加载超时'));
      }, 20000);
      this.loginRuntimeWebViewPageResolve = (): void => {
        if (completed) return;
        completed = true;
        clearTimeout(timer);
        resolve();
      };
      this.loginRuntimeReady = false;
      try {
        this.loginRuntimeController.loadUrl(url);
      } catch (error) {
        completed = true;
        clearTimeout(timer);
        this.loginRuntimeWebViewPageResolve = null;
        reject(error as Error);
      }
    });
    const raw = await this.loginRuntimeController.runJavaScript(script || 'document.documentElement.outerHTML');
    const value = String(raw || '');
    if (value.startsWith('"') && value.endsWith('"')) {
      try {
        return String(JSON.parse(value) || '');
      } catch (_) {}
    }
    return value;
  }

  fetchLoginRuntimeRequest(source: BookSource, requestUrl: string): Promise<HttpResponse> {
    const client = new HttpClient(15000);
    return new Promise<HttpResponse>((resolve) => {
      let completed = false;
      const timeoutId = setTimeout(() => {
        if (completed) return;
        completed = true;
        client.cancelAll();
        resolve({
          url: requestUrl,
          statusCode: 0,
          headers: {},
          body: '',
          success: false,
          error: '登录请求超时，请检查网络或切换书源线路'
        });
      }, 20000);
      new AnalyzeUrl(source, client).fetch(requestUrl)
        .then((response: HttpResponse): void => {
          if (completed) return;
          completed = true;
          clearTimeout(timeoutId);
          if ((response.body || '').length > 8 * 1024 * 1024) {
            resolve({
              url: response.url,
              statusCode: response.statusCode,
              headers: response.headers,
              body: '',
              success: false,
              error: '登录响应过大'
            });
            return;
          }
          resolve(response);
        })
        .catch((error: Object): void => {
          if (completed) return;
          completed = true;
          clearTimeout(timeoutId);
          resolve({
            url: requestUrl,
            statusCode: 0,
            headers: {},
            body: '',
            success: false,
            error: this.importErrorMessage(error)
          });
        });
    });
  }

  applyLoginCookieOperations(raw: string): void {
    const operations: LoginCookieOperation[] = BookSourceLoginWebRuntime.parseCookieOperations(raw);
    for (const operation of operations) {
      const payload = `${operation.operation}\n${operation.url}\n${operation.name}\n${operation.value}`;
      if (!this.loginRuntimeJournal.markOperationApplied('cookie', payload)) continue;
      this.snapshotLoginRuntimeCookie(operation.url);
      if (operation.operation === 'set') {
        CookieStore.setCookies(operation.url, operation.value);
      } else if (operation.operation === 'replace') {
        CookieStore.replaceCookies(operation.url, operation.value);
      } else if (operation.operation === 'remove') {
        CookieStore.removeCookie(operation.url, operation.name || undefined);
      }
      this.loginRuntimeCookies[operation.url] = CookieStore.getCookie(operation.url);
      if (!this.loginRuntimeCookieUrls.includes(operation.url)) {
        this.loginRuntimeCookieUrls.push(operation.url);
      }
    }
    if (operations.length > 0) CookieStore.saveAsync();
  }

  snapshotLoginRuntimeCookie(url: string): void {
    const key = (url || '').trim();
    if (!key || this.loginRuntimeCookieSnapshots[key] !== undefined) return;
    this.loginRuntimeCookieSnapshots[key] = CookieStore.getCookie(key);
  }

  snapshotLoginRuntimeRequestCookie(requestUrl: string): void {
    const match = (requestUrl || '').match(/^https?:\/\/[^\s,]+/i);
    if (!match || !match[0]) return;
    const url = match[0];
    this.snapshotLoginRuntimeCookie(url);
    if (!this.loginRuntimeCookieUrls.includes(url)) this.loginRuntimeCookieUrls.push(url);
    const origin = url.match(/^(https?:\/\/[^/?#]+)/i);
    if (origin && origin[1] && !this.loginRuntimeCookieUrls.includes(origin[1])) {
      this.snapshotLoginRuntimeCookie(origin[1]);
      this.loginRuntimeCookieUrls.push(origin[1]);
    }
  }

  rollbackLoginRuntimeCookies(): void {
    const urls = Object.keys(this.loginRuntimeCookieSnapshots);
    for (const url of urls) {
      CookieStore.removeCookie(url);
      const snapshot = this.loginRuntimeCookieSnapshots[url] || '';
      if (snapshot) CookieStore.setCookies(url, snapshot);
    }
    CookieStore.saveSync();
  }

  suspendLoginRuntimeForBrowser(step: LoginRuntimeStep): void {
    const source = this.loginRuntimeSource;
    if (!source || !step.pendingBrowserAwait) {
      this.finishLoginRuntime(null, '浏览器等待参数无效');
      return;
    }
    if (this.loginRuntimeTimeoutId >= 0) clearTimeout(this.loginRuntimeTimeoutId);
    this.loginRuntimeTimeoutId = -1;
    const token = `${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
    this.loginRuntimeAwaitingBrowser = true;
    this.loginRuntimeBrowserToken = token;
    this.loginRuntimeBrowserUrl = step.pendingBrowserAwait;
    this.loginRuntimeStepRunning = false;
    AppStorage.setOrCreate('bookSourceBrowserAwaitResultToken', '');
    AppStorage.setOrCreate('bookSourceBrowserAwaitResultBody', '');
    AppStorage.setOrCreate('bookSourceBrowserAwaitResultError', '');
    this.showSourceLoginUiDialog = false;
    this.openSourceLoginBrowser(source, step.pendingBrowserAwait,
      step.pendingBrowserTitle || `${source.bookSourceName || '书源'} 网页操作`, false, token);
  }

  resumeLoginRuntimeBrowserAwait(): void {
    if (!this.loginRuntimeAwaitingBrowser || !this.loginRuntimeBrowserToken || !this.loginRuntimeActive) return;
    const resultToken = AppStorage.get<string>('bookSourceBrowserAwaitResultToken') || '';
    if (resultToken !== this.loginRuntimeBrowserToken) return;
    const body = AppStorage.get<string>('bookSourceBrowserAwaitResultBody') || '';
    const error = AppStorage.get<string>('bookSourceBrowserAwaitResultError') || '';
    AppStorage.setOrCreate('bookSourceBrowserAwaitResultToken', '');
    AppStorage.setOrCreate('bookSourceBrowserAwaitResultBody', '');
    AppStorage.setOrCreate('bookSourceBrowserAwaitResultError', '');
    const browserUrl = this.loginRuntimeBrowserUrl;
    this.loginRuntimeAwaitingBrowser = false;
    this.loginRuntimeBrowserToken = '';
    this.loginRuntimeBrowserUrl = '';
    if (error) {
      this.finishLoginRuntime(null, error);
      return;
    }
    // startBrowserAwait() resumes through deterministic script replay. Refresh every Cookie URL
    // observed before suspension so the resumed pass sees credentials created by the browser,
    // instead of the deliberately cleared pre-login snapshot.
    for (const url of this.loginRuntimeCookieUrls) {
      this.loginRuntimeCookies[url] = CookieStore.getCookie(url);
    }
    if (browserUrl) {
      this.loginRuntimeCookies[browserUrl] = CookieStore.getCookie(browserUrl);
      if (!this.loginRuntimeCookieUrls.includes(browserUrl)) this.loginRuntimeCookieUrls.push(browserUrl);
    }
    this.loginRuntimeJournal.recordResponse(`browser:${browserUrl}`, body);
    this.loginRuntimeStepRunning = false;
    this.armLoginRuntimeTimeout();
    this.continueLoginRuntime();
  }

  finishLoginRuntime(result: LoginRuntimeStep | null, errorMessage: string = ''): void {
    if (!this.loginRuntimeResolve && !this.loginRuntimeReject) return;
    const failed = !!errorMessage || !!result?.errorMessage;
    if (failed) this.rollbackLoginRuntimeCookies();
    if (this.loginRuntimeTimeoutId >= 0) clearTimeout(this.loginRuntimeTimeoutId);
    const resolve = this.loginRuntimeResolve;
    const reject = this.loginRuntimeReject;
    this.loginRuntimeResolve = null;
    this.loginRuntimeReject = null;
    this.loginRuntimeTimeoutId = -1;
    this.loginRuntimeSource = null;
    this.loginRuntimeBaseSource = null;
    this.loginRuntimeAction = '';
    this.loginRuntimeCookies = {};
    this.loginRuntimeCookieUrls = [];
    this.loginRuntimeRequestCount = 0;
    this.loginRuntimeFixedNow = 0;
    this.loginRuntimeRandomSeed = 1;
    this.loginRuntimeCookieSnapshots = {};
    this.loginRuntimeAwaitingBrowser = false;
    this.loginRuntimeBrowserToken = '';
    this.loginRuntimeBrowserUrl = '';
    this.loginRuntimeStepRunning = false;
    this.loginRuntimeActive = false;
    this.loginRuntimeJournal.reset();
    if (errorMessage || result?.errorMessage) {
      if (reject) reject(new Error(errorMessage || result?.errorMessage || '登录动作失败'));
    } else if (result && resolve) {
      resolve(result);
    }
  }

  openSourceLoginBrowser(source: BookSource, url: string, title: string, requireLoginCookie: boolean,
    awaitToken: string = '', html: string = '', injectJs: string = ''): void {
    if (/^https?:\/\//i.test(url || '')) VerificationSupport.requestVerification(url, title, source);
    let payloadToken = '';
    if (html) {
      payloadToken = `${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
      AppStorage.setOrCreate('bookSourceBrowserPayloadToken', payloadToken);
      AppStorage.setOrCreate('bookSourceBrowserPayloadHtml', html);
      AppStorage.setOrCreate('bookSourceBrowserPayloadBaseUrl', url || 'about:blank');
      AppStorage.setOrCreate('bookSourceBrowserPayloadInjectJs', injectJs || '');
    }
    this.actionSourceUrl = '';
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: title,
        requireLoginCookie: requireLoginCookie ? 'true' : 'false',
        bookSourceBrowserAwaitToken: awaitToken,
        bookSourceBrowserPayloadToken: payloadToken
      }
    });
  }

  openActionSourceEdit(): void {
    const source = this.actionSource();
    if (!source) {
      return;
    }
    if (source.isLocked) {
      this.closeSourceActions();
      promptAction.showToast({ message: '请先解锁书源' });
      return;
    }
    this.closeSourceActions();
    router.pushUrl({
      url: 'pages/BookSourceEdit',
      params: { bookSourceUrl: source.bookSourceUrl }
    });
  }

  openActionSourceDebug(): void {
    const source = this.actionSource();
    if (!source) {
      this.closeSourceActions();
      promptAction.showToast({ message: '书源不存在' });
      return;
    }
    this.closeSourceActions();
    router.pushUrl({
      url: 'pages/BookSourceDebug',
      params: { bookSourceUrl: source.bookSourceUrl }
    });
  }

  async toggleActionSourceEnabled(): Promise<void> {
    const source = this.actionSource();
    if (!source) {
      return;
    }
    this.closeSourceActions();
    await this.toggleSourceEnabled(source);
  }

  async toggleSourceEnabled(source: BookSource): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    if (source.isLocked) {
      promptAction.showToast({ message: '锁定的书源不能修改' });
      return;
    }
    const enabled = !source.enabled;
    source.enabled = enabled;
    await this.updateSource(source);
    this.allSources = this.allSources.map((item: BookSource) =>
      item.bookSourceUrl === source.bookSourceUrl ? source : item);
    this.reapplySourceFiltersPreservingViewport();
    promptAction.showToast({ message: enabled ? '书源已启用' : '书源已禁用' });
  }

  async deleteSourceFromSwipe(source: BookSource): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    if (source.isLocked) {
      promptAction.showToast({ message: '锁定的书源不能删除' });
      return;
    }
    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源...';
    try {
      await AppDatabase.getInstance().deleteBookSource(source.bookSourceUrl);
      this.sources = this.sources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.allSources = this.allSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.visibleSources = this.visibleSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.selectedSourceUrls = this.selectedSourceUrls.filter((url: string) => url !== source.bookSourceUrl);
      await this.reconcileSourceGroups();
      promptAction.showToast({ message: '书源已删除' });
    } catch (e) {
      console.error('滑动删除书源失败:', e);
      promptAction.showToast({ message: '删除书源失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async deleteActionSource(): Promise<void> {
    const source = this.actionSource();
    if (!source || this.isBatchOperating) {
      return;
    }
    if (source.isLocked) {
      this.showSourceDeleteDialog = false;
      promptAction.showToast({ message: '锁定的书源不能删除' });
      return;
    }
    this.showSourceDeleteDialog = false;
    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源...';
    try {
      const db = AppDatabase.getInstance();
      await db.deleteBookSource(source.bookSourceUrl);
      this.sources = this.sources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.allSources = this.allSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.visibleSources = this.visibleSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.actionSourceUrl = '';
      await this.reconcileSourceGroups();
      promptAction.showToast({ message: '书源已删除' });
    } catch (e) {
      console.error('删除书源失败:', e);
      promptAction.showToast({ message: '删除书源失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  enterSelectionMode(): void {
    this.showAddDialog = false;
    this.selectionMode = true;
    this.selectedSourceUrls = [];
  }

  exitSelectionMode(): void {
    this.stopSourceSelectionAutoScroll();
    this.selectionMode = false;
    this.selectedSourceUrls = [];
    this.showBatchDeleteDialog = false;
    this.showMoreActionDialog = false;
  }

  sourceListItemKey(source: BookSource): string {
    const loginStatus = this.sourceNeedsLogin(source) ? (this.sourceLoggedIn(source) ? 'logged' : 'unlogged') : 'none';
    const positionStatus = `${source.isPinned ? 'pinned' : 'normal'}_${this.isSourceAtBottom(source) ? 'bottom' : 'middle'}`;
    return `${source.bookSourceUrl}_${source.bookSourceGroup || ''}_${source.enabled ? '1' : '0'}_${source.enabledExplore ? '1' : '0'}_${source.isLocked ? 'locked' : 'unlocked'}_${source.validationStatus}_${source.bookSourceName || ''}_${loginStatus}_${positionStatus}_${this.selectionMode ? 'select' : 'normal'}`;
  }

  isSourceSelected(bookSourceUrl: string): boolean {
    return this.getSelectedSourceUrlLookup().has(bookSourceUrl);
  }

  getSelectedSourceUrlLookup(): Set<string> {
    if (this.selectedSourceUrlsSnapshot !== this.selectedSourceUrls) {
      this.selectedSourceUrlsSnapshot = this.selectedSourceUrls;
      this.selectedSourceUrlLookup = new Set<string>(this.selectedSourceUrls);
    }
    return this.selectedSourceUrlLookup;
  }

  setSourceSelected(bookSourceUrl: string, selected: boolean): void {
    if (selected) {
      if (!this.isSourceSelected(bookSourceUrl)) {
        this.selectedSourceUrls = this.selectedSourceUrls.concat([bookSourceUrl]);
      }
      return;
    }
    this.selectedSourceUrls = this.selectedSourceUrls.filter((url: string) => url !== bookSourceUrl);
  }

  toggleSourceSelected(bookSourceUrl: string): void {
    this.setSourceSelected(bookSourceUrl, !this.isSourceSelected(bookSourceUrl));
  }

  isAllSelected(): boolean {
    if (this.sources.length === 0) return false;
    const selected = this.getSelectedSourceUrlLookup();
    return this.sources.every((source: BookSource) => selected.has(source.bookSourceUrl));
  }

  selectAllSources(): void {
    const selected = new Set<string>(this.selectedSourceUrls);
    for (const source of this.sources) {
      selected.add(source.bookSourceUrl);
    }
    this.selectedSourceUrls = Array.from(selected.values());
  }

  toggleAllSources(): void {
    if (this.isAllSelected()) {
      const filteredUrls = new Set<string>(this.sources.map((source: BookSource) => source.bookSourceUrl));
      this.selectedSourceUrls = this.selectedSourceUrls.filter((url: string) => !filteredUrls.has(url));
      return;
    }
    this.selectAllSources();
  }

  pruneSelectedSources(): void {
    if (this.selectedSourceUrls.length === 0) {
      return;
    }
    const existingUrls = new Set<string>(this.allSources.map((source: BookSource) => source.bookSourceUrl));
    this.selectedSourceUrls = this.selectedSourceUrls.filter((url: string) => existingUrls.has(url));
  }

  getSelectedSources(): BookSource[] {
    const selected = this.getSelectedSourceUrlLookup();
    return this.allSources.filter((source: BookSource) => selected.has(source.bookSourceUrl));
  }

  getSelectedMutableSources(): BookSource[] {
    return this.getSelectedSources().filter((source: BookSource) => !source.isLocked);
  }

  getSourceGroups(): string[] {
    return [...this.sourceGroups].sort((a: string, b: string) => a.localeCompare(b));
  }

  sourceGroupsFromSources(): string[] {
    const groups: string[] = [];
    for (const source of this.allSources) {
      const group = (source.bookSourceGroup || '').trim();
      if (group && !groups.includes(group)) {
        groups.push(group);
      }
    }
    return groups.sort((a: string, b: string) => a.localeCompare(b));
  }

  commonSelectedGroupName(): string {
    const selected = this.getSelectedSources();
    if (selected.length === 0) {
      return '';
    }
    const first = selected[0].bookSourceGroup || '';
    for (const source of selected) {
      if ((source.bookSourceGroup || '') !== first) {
        return '';
      }
    }
    return first;
  }

  groupingSources(): BookSource[] {
    if (this.groupActionSourceUrl) {
      const source = this.allSources.find((item: BookSource) =>
        item.bookSourceUrl === this.groupActionSourceUrl);
      return source ? [source] : [];
    }
    return this.getSelectedSources();
  }

  mutableGroupingSources(): BookSource[] {
    return this.groupingSources().filter((source: BookSource) => !source.isLocked);
  }

  actionGroupingSourceName(): string {
    const source = this.groupingSources()[0];
    return source ? (source.bookSourceName || source.bookSourceUrl) : '当前书源';
  }

  closeSourceGroupDialog(): void {
    this.showGroupDialog = false;
    this.groupActionSourceUrl = '';
  }

  async applySelectedSourceGroup(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const selectedSources = this.mutableGroupingSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '所选书源均已锁定' });
      return;
    }

    const groupName = this.groupNameInput.trim();
    const isNewUserGroup = !!groupName && !this.getSourceGroups().includes(groupName);
    this.isBatchOperating = true;
    this.batchOperationText = '正在设置分组...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        source.bookSourceGroup = groupName;
        await db.updateBookSourceListFields(source.bookSourceUrl, { bookSourceGroup: groupName });
      }
      if (groupName) {
        this.sourceGroups = await BookSourceGroupStore.add(
          getContext(this), groupName, this.sourceGroups, isNewUserGroup);
      }
      this.sources = this.sources.map((source: BookSource) => {
        if (this.isSourceSelected(source.bookSourceUrl) && !source.isLocked) {
          source.bookSourceGroup = groupName;
        }
        return source;
      });
      this.ensureActiveSourceGroup();
      this.applySourceFilters();
      this.closeSourceGroupDialog();
      promptAction.showToast({ message: groupName ? `已加入分组：${groupName}` : '已移出分组' });
    } catch (e) {
      console.error('设置书源分组失败:', e);
      promptAction.showToast({ message: '设置分组失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async batchSetEnabled(enabled: boolean): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const selectedSources = this.getSelectedMutableSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '所选书源均已锁定' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = enabled ? '正在启用书源...' : '正在禁用书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        source.enabled = enabled;
        await db.updateBookSourceListFields(source.bookSourceUrl, { enabled: enabled ? 1 : 0 });
      }
      this.reapplySourceFiltersPreservingViewport();
      promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${selectedSources.length} 个书源` });
    } catch (e) {
      console.error('批量更新书源失败:', e);
      promptAction.showToast({ message: '批量操作失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async batchSetExploreEnabled(enabled: boolean): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const selectedSources = this.getSelectedMutableSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '所选书源均已锁定' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = enabled ? '正在启用发现...' : '正在禁用发现...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        source.enabledExplore = enabled;
        await db.updateBookSourceListFields(source.bookSourceUrl, { enabledExplore: enabled ? 1 : 0 });
      }
      this.reapplySourceFiltersPreservingViewport();
      promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${selectedSources.length} 个书源的发现` });
    } catch (e) {
      console.error('批量更新发现状态失败:', e);
      promptAction.showToast({ message: '批量操作失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async batchSetLocked(locked: boolean): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const selectedSources = this.getSelectedSources()
      .filter((source: BookSource) => source.isLocked !== locked);
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: locked ? '所选书源均已锁定' : '所选书源均已解锁' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = locked ? '正在锁定书源...' : '正在解锁书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        await db.setBookSourceLocked(source.bookSourceUrl, locked);
        source.isLocked = locked;
      }
      this.reapplySourceFiltersPreservingViewport();
      promptAction.showToast({ message: `已${locked ? '锁定' : '解锁'} ${selectedSources.length} 个书源` });
    } catch (e) {
      console.error(`批量${locked ? '锁定' : '解锁'}书源失败:`, e);
      await this.loadSources();
      promptAction.showToast({ message: `批量${locked ? '锁定' : '解锁'}失败` });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async batchDeleteSelectedSources(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const selectedUrls = this.getSelectedMutableSources().map((source: BookSource) => source.bookSourceUrl);
    if (selectedUrls.length === 0) {
      promptAction.showToast({ message: '所选书源均已锁定' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const url of selectedUrls) {
        await db.deleteBookSource(url);
      }
      this.selectedSourceUrls = [];
      await this.loadSources();
      this.selectionMode = false;
      promptAction.showToast({ message: `已删除 ${selectedUrls.length} 个书源` });
    } catch (e) {
      console.error('批量删除书源失败:', e);
      promptAction.showToast({ message: '批量删除失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async updateSource(source: BookSource) {
    try {
      const db = AppDatabase.getInstance();
      await db.updateBookSourceListFields(source.bookSourceUrl, {
        bookSourceGroup: source.bookSourceGroup || '',
        enabled: source.enabled ? 1 : 0,
        enabledExplore: source.enabledExplore ? 1 : 0
      });
    } catch (e) {
      console.error('更新书源失败:', e);
    }
  }

  openCheckOptions(): void {
    if (this.selectionMode) {
      return;
    }
    if (this.isCheckingSources) {
      promptAction.showToast({ message: '正在校验中' });
      return;
    }
    this.showCheckOptionsDialog = true;
  }

  async startCheckEnabledSources(action: string = 'none'): Promise<void> {
    if (this.selectionMode) {
      return;
    }
    if (this.isCheckingSources) {
      promptAction.showToast({ message: '正在校验中' });
      return;
    }

    this.checkInvalidAction = action === 'disable' || action === 'delete' ? action : 'none';
    this.showCheckOptionsDialog = false;

    const db = AppDatabase.getInstance();
    const enabledSources = await db.getEnabledBookSources();
    if (enabledSources.length === 0) {
      promptAction.showToast({ message: '暂无启用书源' });
      return;
    }

    await this.startCheckSources(enabledSources, action);
  }

  async checkActionSource(): Promise<void> {
    const summary = this.actionSource();
    this.closeSourceActions();
    if (!summary) {
      promptAction.showToast({ message: '书源不存在' });
      return;
    }
    if (this.isCheckingSources) {
      promptAction.showToast({ message: '正在校验中' });
      return;
    }
    const source = await AppDatabase.getInstance().getBookSource(summary.bookSourceUrl);
    if (!source) {
      promptAction.showToast({ message: '书源不存在' });
      return;
    }
    await this.startCheckSources([source], 'none');
  }

  async checkSelectedSources(): Promise<void> {
    if (this.isCheckingSources) {
      promptAction.showToast({ message: '正在校验中' });
      return;
    }
    const selectedUrls = new Set<string>(this.selectedSourceUrls);
    if (selectedUrls.size === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    try {
      const allSources = await AppDatabase.getInstance().getAllBookSources();
      const targetSources = allSources.filter((source: BookSource) => selectedUrls.has(source.bookSourceUrl));
      if (targetSources.length === 0) {
        promptAction.showToast({ message: '所选书源不存在' });
        return;
      }
      await this.startCheckSources(targetSources, 'none');
    } catch (e) {
      console.error('加载所选书源失败:', e);
      promptAction.showToast({ message: '加载所选书源失败' });
    }
  }

  async startCheckSources(targetSources: BookSource[], action: string = 'none'): Promise<void> {
    if (targetSources.length === 0) {
      return;
    }

    const taskSerial = ++this.checkTaskSerial;
    const validationMode = this.checkValidationMode;
    this.checkInvalidAction = validationMode === 'search' && (action === 'disable' || action === 'delete') ?
      action : 'none';
    this.showCheckOptionsDialog = false;
    this.showCheckDialog = true;
    this.isCheckingSources = true;
    this.checkBackgroundMode = false;
    this.checkDone = 0;
    this.checkTotal = targetSources.length;
    this.checkOkCount = 0;
    this.checkFailedCount = 0;
    this.checkNoResultCount = 0;
    this.checkNeedVerificationCount = 0;
    this.checkTemporaryErrorCount = 0;
    this.checkBadUrls = [];
    this.checkResultDetails = [];
    this.checkTlsTrustHosts = [];
    this.checkTlsRetrySourceUrls = [];
    this.resetCheckedSourceUiUpdates();
    this.checkAutoHandledCount = 0;
    this.checkStatus = validationMode === 'exploreReading' ?
      `准备检查 ${targetSources.length} 个书源的发现/阅读链路` : `准备校验 ${targetSources.length} 个书源`;
    this.checkNotificationLastAt = 0;
    this.checkCancelAgent = null;
    await this.ensureBookSourceCheckCancelSubscriber();
    if (taskSerial !== this.checkTaskSerial || !this.isCheckingSources) {
      return;
    }

    try {
      if (validationMode === 'exploreReading') {
        const validator = new ExploreReadingValidator();
        this.checkExploreValidator = validator;
        await validator.validateSources(targetSources, (progress: ExploreReadingValidationProgress): void => {
          if (taskSerial !== this.checkTaskSerial || !this.isCheckingSources) {
            return;
          }
          this.checkDone = progress.done;
          this.checkTotal = progress.total;
          this.checkStatus = `${progress.sourceName} · ${progress.stage}（${progress.done}/${progress.total}）`;
          if (this.checkBackgroundMode) {
            this.publishBookSourceCheckProgress(false).catch((e: Error) => {
              console.warn('更新书源发现/阅读校验通知失败:', e);
            });
          }
        }, async (source: BookSource, result: ExploreReadingValidationResult): Promise<void> => {
          if (taskSerial !== this.checkTaskSerial || !this.isCheckingSources) return;
          await this.handleExploreReadingCompletion(source, result);
        });
      } else {
        const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
        this.checkCoordinator = coordinator;
        await coordinator.search(BOOK_SOURCE_CHECK_KEYWORD, (progress: SearchProgress) => {
          if (taskSerial !== this.checkTaskSerial || !this.isCheckingSources) {
            return;
          }
          this.checkDone = progress.done;
          this.checkTotal = progress.total;
          this.checkStatus = this.formatCheckProgressStatus(progress);
          if (this.checkBackgroundMode) {
            this.publishBookSourceCheckProgress(false).catch((e: Error) => {
              console.warn('更新书源校验通知失败:', e);
            });
          }
        }, {
          onSourceComplete: async (source: BookSource, result: SearchSourceResult) => {
            if (taskSerial !== this.checkTaskSerial || !this.isCheckingSources) {
              return;
            }
            await this.handleCheckedSourceCompletion(source, result);
          },
          targetSources: targetSources,
          validationOnly: true
        });
      }

      if (taskSerial !== this.checkTaskSerial) {
        return;
      }
      this.flushCheckedSourceUiUpdates();
      this.checkDone = targetSources.length;
      this.checkTotal = targetSources.length;
      this.checkStatus = this.checkResultText();
    } catch (e) {
      if (taskSerial !== this.checkTaskSerial) {
        return;
      }
      console.error('校验书源失败:', e);
      this.checkStatus = '校验失败，请稍后重试';
      promptAction.showToast({ message: '校验失败' });
    } finally {
      if (taskSerial !== this.checkTaskSerial) {
        return;
      }
      this.flushCheckedSourceUiUpdates();
      const finishedInBackground = this.checkBackgroundMode;
      this.checkCoordinator = null;
      this.checkExploreValidator = null;
      this.isCheckingSources = false;
      if (this.checkInvalidAction !== 'none') {
        await this.loadSources();
      }
      if (finishedInBackground) {
        await this.publishBookSourceCheckNotification('书源校验完成', this.checkResultText(), false);
      }
      this.checkBackgroundMode = false;
      await this.stopBookSourceCheckBackgroundRunning();
      if (!this.pageVisible) {
        this.releaseBookSourceCheckCancelSubscriber();
      }
    }
  }

  cancelBookSourceCheck(showToast: boolean): void {
    if (!this.isCheckingSources) {
      return;
    }
    const wasBackground = this.checkBackgroundMode;
    this.checkTaskSerial++;
    if (this.checkCoordinator) {
      this.checkCoordinator.cancel();
      this.checkCoordinator = null;
    }
    if (this.checkExploreValidator) {
      this.checkExploreValidator.cancel();
      this.checkExploreValidator = null;
    }
    this.flushCheckedSourceUiUpdates();
    this.isCheckingSources = false;
    this.checkBackgroundMode = false;
    this.checkStatus = `校验已取消（${this.checkDone}/${this.checkTotal}）`;
    if (showToast) {
      promptAction.showToast({ message: '已停止书源校验' });
    }
    if (this.checkInvalidAction !== 'none') {
      this.loadSources().catch((e: Error) => {
        console.warn('取消校验后刷新书源失败:', e);
      });
    }
    if (wasBackground) {
      this.publishBookSourceCheckNotification('书源校验已取消', this.bookSourceCheckProgressText(), false)
        .catch((e: Error) => {
          console.warn('更新书源校验取消通知失败:', e);
        });
    }
    this.stopBookSourceCheckBackgroundRunning().catch((e: Error) => {
      console.warn('停止书源校验后台任务失败:', e);
    });
    if (!this.pageVisible) {
      this.releaseBookSourceCheckCancelSubscriber();
    }
  }

  async continueBookSourceCheckInBackground(): Promise<void> {
    if (!this.isCheckingSources) {
      return;
    }
    this.checkBackgroundMode = true;
    this.showCheckDialog = false;
    promptAction.showToast({ message: '书源校验将在后台继续，可在通知栏取消' });
    await this.startBookSourceCheckBackgroundRunning();
    await this.requestBookSourceCheckNotificationEnabled();
    if (this.isCheckingSources && this.checkBackgroundMode) {
      await this.publishBookSourceCheckProgress(true);
    }
  }

  bookSourceCheckProgressText(): string {
    const total = Math.max(0, this.checkTotal);
    if (total === 0) {
      return '正在准备校验书源（0%）';
    }
    const done = Math.max(0, Math.min(this.checkDone, total));
    const percent = Math.floor((done / total) * 100);
    return `已校验 ${done}/${total}（${percent}%）`;
  }

  async publishBookSourceCheckProgress(force: boolean): Promise<void> {
    const now = Date.now();
    if (!force && now - this.checkNotificationLastAt < BOOK_SOURCE_CHECK_NOTIFICATION_INTERVAL_MS) {
      return;
    }
    this.checkNotificationLastAt = now;
    await this.publishBookSourceCheckNotification(
      this.checkStatus || '书源校验后台进行中',
      this.bookSourceCheckProgressText(),
      true
    );
  }

  async publishBookSourceCheckNotification(text: string, additionalText: string, ongoing: boolean): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: BOOK_SOURCE_CHECK_NOTIFICATION_ID,
        label: 'book_source_check',
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: ongoing,
        tapDismissed: false,
        isAlertOnce: true,
        wantAgent: await this.getBookSourceCheckOpenWantAgent(),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '书源校验',
            text: text,
            additionalText: additionalText
          }
        }
      };
      if (ongoing) {
        request.actionButtons = [{
          title: '取消',
          wantAgent: await this.getBookSourceCheckCancelWantAgent()
        }];
      } else {
        request.autoDeletedTime = Date.now() + 5000;
      }
      await notificationManager.publish(request);
    } catch (e) {
      console.warn('发布书源校验通知失败:', e);
    }
  }

  async requestBookSourceCheckNotificationEnabled(): Promise<void> {
    try {
      if (await notificationManager.isNotificationEnabled()) {
        return;
      }
      await notificationManager.requestEnableNotification(getContext(this) as common.UIAbilityContext);
    } catch (e) {
      console.warn('请求书源校验通知权限失败:', e);
    }
  }

  async getBookSourceCheckOpenWantAgent(): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          bookSourceCheckAction: 'open'
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 2702,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  async getBookSourceCheckCancelWantAgent(): Promise<WantAgent> {
    if (this.checkCancelAgent) {
      return this.checkCancelAgent;
    }
    this.checkCancelAgent = await wantAgent.getWantAgent({
      wants: [{
        action: BOOK_SOURCE_CHECK_CANCEL_EVENT
      }],
      actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
      requestCode: 2703,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    return this.checkCancelAgent;
  }

  async ensureBookSourceCheckCancelSubscriber(): Promise<void> {
    if (this.checkCancelSubscriber) {
      return;
    }
    try {
      const subscriber = await commonEventManager.createSubscriber({
        events: [BOOK_SOURCE_CHECK_CANCEL_EVENT]
      });
      this.checkCancelSubscriber = subscriber;
      commonEventManager.subscribe(subscriber,
        (error: Error | null, _data: commonEventManager.CommonEventData) => {
          if (error) {
            console.warn('接收书源校验取消事件失败:', error);
            return;
          }
          this.cancelBookSourceCheck(false);
        });
    } catch (e) {
      console.warn('注册书源校验取消事件失败:', e);
    }
  }

  releaseBookSourceCheckCancelSubscriber(): void {
    if (!this.checkCancelSubscriber) {
      return;
    }
    const subscriber = this.checkCancelSubscriber;
    this.checkCancelSubscriber = null;
    commonEventManager.unsubscribe(subscriber, (error: Error | null) => {
      if (error) {
        console.warn('注销书源校验取消事件失败:', error);
      }
    });
  }

  async startBookSourceCheckBackgroundRunning(): Promise<void> {
    if (this.checkBackgroundRunning) {
      return;
    }
    try {
      const agent = await this.getBookSourceCheckOpenWantAgent();
      await backgroundTaskManager.startBackgroundRunning(getContext(this), ['dataTransfer'], agent);
      this.checkBackgroundRunning = true;
    } catch (e) {
      console.warn('启动书源校验后台任务失败:', e);
    }
  }

  async stopBookSourceCheckBackgroundRunning(): Promise<void> {
    if (!this.checkBackgroundRunning) {
      return;
    }
    this.checkBackgroundRunning = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(getContext(this));
    } catch (e) {
      console.warn('停止书源校验后台任务失败:', e);
    }
  }

  async handleExploreReadingCompletion(source: BookSource, result: ExploreReadingValidationResult): Promise<void> {
    const compatibleResult: SearchSourceResult = {
      books: [],
      validationStatus: result.validationStatus,
      reason: result.reason
    };
    await this.handleCheckedSourceCompletion(source, compatibleResult, true);
  }

  async handleCheckedSourceCompletion(source: BookSource, result: SearchSourceResult,
    includePassedDetail: boolean = false): Promise<void> {
    source.validationStatus = result.validationStatus;
    this.recordCertificateTrustCandidate(source, result.reason || '');
    try {
      await AppDatabase.getInstance().updateBookSourceValidationStatus(
        source.bookSourceUrl, source.validationStatus);
    } catch (e) {
      console.error('保存书源校验状态失败:', source.bookSourceName, e);
    }
    let detail = '';
    if (source.validationStatus !== BookSource.VALIDATION_PASSED || includePassedDetail) {
      const sourceName = source.bookSourceName || source.bookSourceUrl;
      detail = result.reason ?
        `${sourceName}：${this.sourceValidationStatusLabel(source.validationStatus)}（${result.reason}）` :
        `${sourceName}：${this.sourceValidationStatusLabel(source.validationStatus)}`;
    }
    this.queueCheckedSourceUiUpdate(source.bookSourceUrl, source.validationStatus, detail);
    if (source.validationStatus === BookSource.VALIDATION_PASSED) {
      this.checkOkCount++;
      return;
    }
    if (source.validationStatus === BookSource.VALIDATION_FAILED) {
      this.checkFailedCount++;
    } else if (source.validationStatus === BookSource.VALIDATION_NO_RESULTS) {
      this.checkNoResultCount++;
    } else if (source.validationStatus === BookSource.VALIDATION_NEEDS_VERIFICATION) {
      this.checkNeedVerificationCount++;
    } else if (source.validationStatus === BookSource.VALIDATION_TEMPORARY_ERROR) {
      this.checkTemporaryErrorCount++;
    }
    if (source.validationStatus !== BookSource.VALIDATION_FAILED) {
      return;
    }
    if (!this.checkBadUrls.includes(source.bookSourceUrl)) {
      this.checkBadUrls = [...this.checkBadUrls, source.bookSourceUrl];
    }
    if (this.checkInvalidAction === 'none') {
      return;
    }
    if (source.isLocked) {
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      if (this.checkInvalidAction === 'disable') {
        source.enabled = false;
        source.lastUpdateTime = Date.now();
        await db.updateBookSource(source);
        this.sources = this.sources.map((item: BookSource) =>
          item.bookSourceUrl === source.bookSourceUrl ? source : item);
      } else if (this.checkInvalidAction === 'delete') {
        await db.deleteBookSource(source.bookSourceUrl);
        this.sources = this.sources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
        this.allSources = this.allSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
        this.visibleSources = this.visibleSources.filter(
          (item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      }
      this.checkAutoHandledCount++;
    } catch (e) {
      console.error(`自动${this.checkInvalidAction === 'delete' ? '删除' : '禁用'}无效书源失败:`, e);
    }
  }

  queueCheckedSourceUiUpdate(bookSourceUrl: string, validationStatus: number, detail: string): void {
    const update = new BookSourceCheckUiUpdate();
    update.bookSourceUrl = bookSourceUrl;
    update.validationStatus = validationStatus;
    update.detail = detail;
    this.checkUiUpdates.push(update);
    if (this.checkUiFlushTimer >= 0) return;
    this.checkUiFlushTimer = setTimeout(() => this.flushCheckedSourceUiUpdates(), 300);
  }

  resetCheckedSourceUiUpdates(): void {
    if (this.checkUiFlushTimer >= 0) clearTimeout(this.checkUiFlushTimer);
    this.checkUiFlushTimer = -1;
    this.checkUiUpdates = [];
  }

  flushCheckedSourceUiUpdates(): void {
    if (this.checkUiFlushTimer >= 0) clearTimeout(this.checkUiFlushTimer);
    this.checkUiFlushTimer = -1;
    if (this.checkUiUpdates.length === 0) return;
    const updates = this.checkUiUpdates;
    this.checkUiUpdates = [];
    const statusByUrl = new Map<string, number>();
    const details: string[] = [];
    for (const update of updates) {
      statusByUrl.set(update.bookSourceUrl, update.validationStatus);
      if (update.detail) details.push(update.detail);
    }
    this.allSources = this.allSources.map((item: BookSource) => {
      const status = statusByUrl.get(item.bookSourceUrl);
      if (status === undefined) return item;
      item.validationStatus = status;
      return item;
    });
    if (details.length > 0) {
      this.checkResultDetails = this.checkResultDetails.concat(details);
    }
    if (this.sourceValidationFilter !== 'all') {
      this.applySourceFilters();
      this.sourceListDataSource.replace(this.visibleSources, true);
      return;
    }
    this.sources = this.sources.map((item: BookSource) => {
      const status = statusByUrl.get(item.bookSourceUrl);
      if (status !== undefined) item.validationStatus = status;
      return item;
    });
    this.visibleSources = this.visibleSources.map((item: BookSource) => {
      const status = statusByUrl.get(item.bookSourceUrl);
      if (status !== undefined) item.validationStatus = status;
      return item;
    });
    this.sourceListDataSource.replace(this.visibleSources, true);
  }

  checkSummaryText(): string {
    return `已校验 ${this.checkTotal} 个书源${this.checkAutoActionSummary()}`;
  }

  checkDialogStatusText(): string {
    if (this.isCheckingSources) return this.checkStatus || '准备中...';
    if (/^校验(?:失败|已取消)/.test(this.checkStatus || '')) return this.checkStatus;
    return this.checkResultText();
  }

  recordCertificateTrustCandidate(source: BookSource, reason: string): void {
    if (!TlsTrustStore.isRemoteValidationSupported()) return;
    const host = TlsTrustStore.certificateErrorHost(reason, source.bookSourceUrl);
    if (!host || TlsTrustStore.isTrustedHost(host)) return;
    if (!this.checkTlsTrustHosts.includes(host)) {
      this.checkTlsTrustHosts = [...this.checkTlsTrustHosts, host];
    }
    if (!this.checkTlsRetrySourceUrls.includes(source.bookSourceUrl)) {
      this.checkTlsRetrySourceUrls = [...this.checkTlsRetrySourceUrls, source.bookSourceUrl];
    }
  }

  async trustCheckCertificateHostsAndRetry(): Promise<void> {
    if (this.isCheckingSources || this.checkTlsTrustHosts.length === 0) return;
    const hosts = [...this.checkTlsTrustHosts];
    const retryUrls = new Set<string>(this.checkTlsRetrySourceUrls);
    const confirmation = await promptAction.showDialog({
      title: '信任证书风险提示',
      message: `系统无法验证以下主机的身份：\n${hosts.join('\n')}\n\n` +
        '继续后，仅在本设备上对这些精确主机跳过证书校验。连接可能被冒充或监听；只有在你确认书源和网络可信时才继续。',
      buttons: [
        { text: '保持安全', color: this.subTextColor() },
        { text: '信任并重试', color: '#B26A00' }
      ]
    });
    if (confirmation.index !== 1) return;
    try {
      await TlsTrustStore.trustHosts(getContext(this) as common.UIAbilityContext, hosts);
      const allSources = await AppDatabase.getInstance().getAllBookSources();
      const retrySources = allSources.filter((source: BookSource) => retryUrls.has(source.bookSourceUrl));
      if (retrySources.length === 0) {
        promptAction.showToast({ message: '已保存证书信任，但原书源已不存在' });
        this.checkTlsTrustHosts = [];
        this.checkTlsRetrySourceUrls = [];
        return;
      }
      promptAction.showToast({ message: `已仅信任 ${hosts.length} 个主机，正在重新校验` });
      await this.startCheckSources(retrySources, 'none');
    } catch (e) {
      console.error('保存证书信任失败:', e);
      promptAction.showToast({ message: '保存证书信任失败' });
    }
  }

  formatCheckProgressStatus(progress: SearchProgress): string {
    const verifyText = progress.needVerification ? '；有书源需要网页验证' : '';
    return `已校验 ${progress.done}/${progress.total}${this.checkAutoActionSummary()}${verifyText}`;
  }

  checkAutoActionSummary(): string {
    if (this.checkInvalidAction === 'disable') {
      return `，已自动禁用 ${this.checkAutoHandledCount} 个`;
    }
    if (this.checkInvalidAction === 'delete') {
      return `，已自动删除 ${this.checkAutoHandledCount} 个`;
    }
    return '';
  }

  checkResultText(): string {
    if (this.checkTotal === 0) {
      return '没有需要校验的书源';
    }
    return `通过 ${this.checkOkCount}，失败 ${this.checkFailedCount}，无结果 ${this.checkNoResultCount}，` +
      `需要验证 ${this.checkNeedVerificationCount}，暂时异常 ${this.checkTemporaryErrorCount}` +
      this.checkAutoActionSummary();
  }

  async disableFailedCheckedSources(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const lockedUrls = new Set(this.allSources.filter((source: BookSource) => source.isLocked)
      .map((source: BookSource) => source.bookSourceUrl));
    const failedUrls = this.checkBadUrls.filter((url: string) => !lockedUrls.has(url));
    if (failedUrls.length === 0) {
      promptAction.showToast({ message: '明确失败的书源均已锁定，未执行禁用' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = '正在禁用书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const url of failedUrls) {
        const source = await db.getBookSource(url);
        if (source) {
          source.enabled = false;
          source.lastUpdateTime = Date.now();
          await db.updateBookSource(source);
        }
      }
      const disabledCount = failedUrls.length;
      this.showCheckDialog = false;
      await this.loadSources();
      promptAction.showToast({ message: `已禁用 ${disabledCount} 个明确失败的书源` });
    } catch (e) {
      console.error('禁用异常书源失败:', e);
      promptAction.showToast({ message: '禁用失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async deleteFailedCheckedSources(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const lockedUrls = new Set(this.allSources.filter((source: BookSource) => source.isLocked)
      .map((source: BookSource) => source.bookSourceUrl));
    const failedUrls = this.checkBadUrls.filter((url: string) => !lockedUrls.has(url));
    if (failedUrls.length === 0) {
      promptAction.showToast({ message: '明确失败的书源均已锁定，未执行删除' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const url of failedUrls) {
        await db.deleteBookSource(url);
      }
      this.checkBadUrls = [];
      this.showCheckDialog = false;
      await this.loadSources();
      promptAction.showToast({ message: `已删除 ${failedUrls.length} 个明确失败的书源` });
    } catch (e) {
      console.error('删除异常书源失败:', e);
      promptAction.showToast({ message: '删除失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async importFromFile() {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['JSON|.json', '文本|.txt'];
      const pickerResult: Array<string> = await new picker.DocumentViewPicker().select(options);

      if (!pickerResult || pickerResult.length === 0) {
        return;
      }

      this.isImporting = true;
      const content = await this.readTextFile(pickerResult[0]);
      if (!content.trim()) {
        promptAction.showToast({ message: '文件内容为空' });
        return;
      }
      await this.importSourcesFromJson(content);
    } catch (e) {
      console.error('从文件导入失败:', e);
      const errMsg = this.importErrorMessage(e as Object);
      promptAction.showToast({ message: `导入失败: ${errMsg}` });
    } finally {
      this.isImporting = false;
    }
  }

  async handlePendingBookSourceImport(): Promise<void> {
    if (this.isImporting) return;
    const uri = AppStorage.get<string>('pendingBookSourceImportUri') || '';
    const onlineUrl = AppStorage.get<string>('pendingBookSourceImportUrl') || '';
    if (!uri && !onlineUrl) return;
    AppStorage.setOrCreate('pendingBookSourceImportUri', '');
    AppStorage.setOrCreate('pendingBookSourceImportUrl', '');
    this.isImporting = true;
    try {
      const content = onlineUrl ? await this.fetchImportUrlBody(onlineUrl) : await this.readTextFile(uri);
      if (!content.trim()) {
        promptAction.showToast({ message: '文件内容为空' });
        return;
      }
      await this.importSourcesFromJson(content);
    } catch (e) {
      console.error('打开 JSON 书源文件失败:', e);
      const message = this.importErrorMessage(e as Object);
      promptAction.showToast({ message: `导入失败: ${message}` });
    } finally {
      this.isImporting = false;
      if (AppStorage.get<string>('pendingBookSourceImportUri') ||
        AppStorage.get<string>('pendingBookSourceImportUrl')) {
        this.handlePendingBookSourceImport();
      }
    }
  }

  async exportSelectedSources(): Promise<void> {
    if (this.selectedSourceUrls.length === 0 || this.isBatchOperating) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }
    const selectedLookup = this.getSelectedSourceUrlLookup();
    const selectedSummaries = this.sources.filter((source: BookSource) =>
      selectedLookup.has(source.bookSourceUrl));
    if (selectedSummaries.length === 0) {
      promptAction.showToast({ message: '未找到可导出的书源' });
      return;
    }

    let file: fs.File | null = null;
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`legado_book_sources_${this.exportTimestamp()}.json`];
      options.fileSuffixChoices = ['JSON 文件|.json'];
      const result = await new picker.DocumentViewPicker(getContext(this)).save(options);
      if (!result || result.length === 0) {
        return;
      }

      this.isBatchOperating = true;
      this.batchOperationText = '正在导出书源...';
      const selected: BookSource[] = [];
      const db = AppDatabase.getInstance();
      for (const summary of selectedSummaries) {
        const source = await db.getBookSource(summary.bookSourceUrl);
        if (source) selected.push(source);
      }
      const exported = selected.map((source: BookSource): Object => this.bookSourceExportObject(source));
      const json = JSON.stringify(exported, null, 2);
      const bytes = new util.TextEncoder().encodeInto(json);
      file = await fs.open(result[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
      await fs.close(file);
      file = null;
      promptAction.showToast({ message: `已导出 ${selected.length} 个书源` });
    } catch (e) {
      console.error('导出书源失败:', e);
      const message = e instanceof Error ? e.message : String(e);
      promptAction.showToast({ message: `导出失败: ${message}` });
    } finally {
      if (file) {
        try {
          await fs.close(file);
        } catch (_) {
        }
      }
      this.isBatchOperating = false;
      this.batchOperationText = '正在操作书源...';
    }
  }

  exportTimestamp(): string {
    const date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_` +
      `${pad(date.getHours())}${pad(date.getMinutes())}`;
  }

  bookSourceExportObject(source: BookSource): Object {
    let result: Record<string, Object> = {};
    try {
      const parsed = JSON.parse(source.rawSourceJson || '{}') as Object;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        result = parsed as Record<string, Object>;
      }
    } catch (_) {}
    result['bookSourceUrl'] = source.bookSourceUrl;
    result['bookSourceName'] = source.bookSourceName;
    result['bookSourceType'] = source.bookSourceType;
    result['bookSourceGroup'] = source.bookSourceGroup;
    result['bookSourceComment'] = source.bookSourceComment;
    result['bookUrlPattern'] = source.bookUrlPattern;
    result['customOrder'] = source.customOrder;
    result['enabled'] = source.enabled;
    result['enabledExplore'] = source.enabledExplore;
    result['enabledCookieJar'] = source.enabledCookieJar;
    result['jsLib'] = source.jsLib;
    result['header'] = source.header;
    result['loginUrl'] = source.loginUrl;
    result['loginUi'] = source.loginUi;
    result['loginCheckJs'] = source.loginCheckJs;
    result['searchUrl'] = source.searchUrl;
    result['exploreUrl'] = source.exploreUrl;
    result['ruleSearch'] = this.mergeRuleForExport(result['ruleSearch'], source.searchRule);
    result['ruleExplore'] = this.mergeRuleForExport(result['ruleExplore'], source.exploreRule);
    result['ruleBookInfo'] = this.mergeRuleForExport(result['ruleBookInfo'], source.bookInfoRule);
    result['ruleToc'] = this.mergeRuleForExport(result['ruleToc'], source.tocRule);
    result['ruleContent'] = this.mergeRuleForExport(result['ruleContent'], source.contentRule);
    result['variableComment'] = source.variableComment;
    result['lastUpdateTime'] = source.lastUpdateTime;
    result['respondTime'] = source.respondTime;
    result['weight'] = source.weight;
    result['concurrentRate'] = source.concurrentRate;
    result['customButton'] = source.customButton;
    result['eventListener'] = source.eventListener;
    if (source.isPinned || result['isPinned'] !== undefined) result['isPinned'] = source.isPinned;
    if (source.isLocked || result['isLocked'] !== undefined) result['isLocked'] = source.isLocked;
    return result;
  }

  mergeRuleForExport(rawRule: Object | undefined, storedRule: Object): Object {
    const merged: Record<string, Object> = {};
    if (rawRule && typeof rawRule === 'object' && !Array.isArray(rawRule)) {
      const rawRecord = rawRule as Record<string, Object>;
      for (const key of Object.keys(rawRecord)) merged[key] = rawRecord[key];
    }
    const stored = JSON.parse(JSON.stringify(storedRule || {})) as Record<string, Object>;
    for (const key of Object.keys(stored)) merged[key] = stored[key];
    return merged;
  }

  async readTextFile(filePath: string): Promise<string> {
    let file: fs.File | null = null;
    try {
      const stat = await fs.stat(filePath);
      if (stat.size <= 0) {
        return '';
      }
      if (stat.size > BOOK_SOURCE_IMPORT_FILE_LIMIT_BYTES) {
        throw new Error('文件过大，请选择 25MB 以内的书源文件');
      }

      file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      const text = util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer), { stream: false });
      return text.replace(/^\uFEFF/, '');
    } finally {
      if (file) {
        await fs.close(file);
      }
    }
  }

  async importFromUrl() {
    this.hideKeyboard();
    const url = this.importUrl.trim();
    if (!url) {
      promptAction.showToast({ message: '请输入URL' });
      return;
    }

    try {
      this.isImporting = true;
      const content = await this.fetchImportUrlBody(url);
      await this.importSourcesFromJson(content);
      this.showImportUrlDialog = false;
      this.importUrl = '';
    } catch (e) {
      console.error('从URL导入失败:', e);
      const errMsg = this.importErrorMessage(e as Object);
      promptAction.showToast({ message: `导入失败: ${errMsg}` });
    } finally {
      this.isImporting = false;
    }
  }

  async fetchImportUrlBody(url: string): Promise<string> {
    let lastError = '';
    let webFallbackError = '';
    const candidates = this.importUrlCandidates(url);
    const directAttempts = Math.min(BOOK_SOURCE_IMPORT_URL_RETRY_COUNT, candidates.length);
    for (let attempt = 0; attempt < directAttempts; attempt++) {
      const requestUrl = candidates[attempt];
      const response = await new HttpClient(BOOK_SOURCE_IMPORT_TIMEOUT_MS).execute({
        url: requestUrl,
        method: 'GET',
        headers: {
          'Accept': 'application/json,text/plain,*/*'
        },
        connectTimeout: BOOK_SOURCE_IMPORT_TIMEOUT_MS,
        readTimeout: BOOK_SOURCE_IMPORT_TIMEOUT_MS,
        maxResponseBytes: BOOK_SOURCE_IMPORT_FILE_LIMIT_BYTES
      });
      if (this.isValidBookSourceJson(response.body)) {
        return response.body.replace(/^\uFEFF/, '');
      }
      const reason = response.success ? '响应内容不是有效书源JSON' :
        (response.error || `HTTP ${response.statusCode}`);
      lastError = `${this.importUrlHost(requestUrl)}: ${reason}`;
      if (reason.includes('2300056') || reason.toLowerCase().includes('failed to receive data from the peer')) {
        break;
      }
      if (attempt + 1 < directAttempts) {
        await new Promise<void>((resolve) => setTimeout(resolve, (attempt + 1) * 300));
      }
    }

    const plainHttpUrl = candidates.find((candidate: string) => /^http:\/\//i.test(candidate));
    if (plainHttpUrl) {
      try {
        const body = await RawHttpTextClient.get(plainHttpUrl, BOOK_SOURCE_IMPORT_FILE_LIMIT_BYTES,
          BOOK_SOURCE_IMPORT_TIMEOUT_MS);
        if (this.isValidBookSourceJson(body)) return body.replace(/^\uFEFF/, '');
        lastError = `${this.importUrlHost(plainHttpUrl)}: TCP兜底响应不是有效书源JSON`;
      } catch (tcpError) {
        lastError = `${this.importUrlHost(plainHttpUrl)}: ${this.importErrorMessage(tcpError as Object)}`;
      }
    }

    const webCandidates = candidates.length > 0 ? candidates : [url];
    for (let attempt = 0; attempt < BOOK_SOURCE_WEB_IMPORT_RETRY_COUNT; attempt++) {
      const webRequestUrl = webCandidates[attempt % webCandidates.length];
      try {
        const body = await this.fetchImportUrlViaWeb(webRequestUrl);
        if (this.isValidBookSourceJson(body)) return body.replace(/^\uFEFF/, '');
        webFallbackError = '网页取数失败: 浏览器下载内容不是有效书源JSON';
        lastError = `${this.importUrlHost(webRequestUrl)}: ${webFallbackError}`;
      } catch (webError) {
        webFallbackError = `网页取数失败: ${this.importErrorMessage(webError as Object)}`;
        lastError = `${this.importUrlHost(webRequestUrl)}: ${webFallbackError}`;
      }
      if (attempt + 1 < BOOK_SOURCE_WEB_IMPORT_RETRY_COUNT) {
        await new Promise<void>((resolve) => setTimeout(resolve, (attempt + 1) * 350));
      }
    }

    for (const requestUrl of candidates) {
      try {
        const body = await this.fetchImportUrlViaDownload(requestUrl);
        if (this.isValidBookSourceJson(body)) return body.replace(/^\uFEFF/, '');
        lastError = `${this.importUrlHost(requestUrl)}: 下载内容不是有效书源JSON`;
      } catch (downloadError) {
        const downloadMessage = this.importErrorMessage(downloadError as Object);
        const combinedMessage = webFallbackError ? `${webFallbackError}；${downloadMessage}` : downloadMessage;
        lastError = `${this.importUrlHost(requestUrl)}: ${combinedMessage}`;
      }
    }
    throw new Error(lastError || '获取书源失败');
  }

  fetchImportUrlViaWeb(url: string): Promise<string> {
    const origin = this.importUrlOrigin(url);
    if (!origin) return Promise.reject(new Error('网页取数仅支持 HTTP/HTTPS 地址'));
    if (this.webImportResolve || this.webImportReject) {
      return Promise.reject(new Error('已有网页取数任务正在运行'));
    }
    this.webImportController = new webview.WebviewController();
    this.webImportTargetUrl = url;
    this.webImportStarted = false;
    return new Promise<string>((resolve, reject) => {
      this.webImportResolve = resolve;
      this.webImportReject = reject;
      this.webImportTimeoutId = setTimeout(() => {
        this.finishWebImport('', '浏览器内核下载超时');
      }, BOOK_SOURCE_IMPORT_TIMEOUT_MS);
      this.webImportActive = true;
    });
  }

  startWebImportDownload(): void {
    if (!this.webImportActive || this.webImportStarted || !this.webImportTargetUrl) return;
    this.webImportStarted = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const suffix = `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
      this.webImportDownloadPath = `${context.cacheDir}/book_source_web_import_${suffix}.json`;
      const delegate = new webview.WebDownloadDelegate();
      delegate.onBeforeDownload((item: webview.WebDownloadItem): void => {
        if (!this.webImportActive) {
          try {
            item.cancel();
          } catch (_) {
          }
          return;
        }
        this.webImportDownloadItem = item;
        const totalBytes = item.getTotalBytes();
        if (totalBytes > BOOK_SOURCE_IMPORT_FILE_LIMIT_BYTES) {
          this.finishWebImport('', '浏览器下载文件过大，请使用 25MB 以内的书源文件');
          return;
        }
        try {
          item.start(this.webImportDownloadPath);
        } catch (startError) {
          this.finishWebImport('', `浏览器下载启动失败: ${this.importErrorMessage(startError as Object)}`);
        }
      });
      delegate.onDownloadFinish((item: webview.WebDownloadItem): void => {
        if (!this.webImportActive) return;
        const filePath = item.getFullPath() || this.webImportDownloadPath;
        this.readTextFile(filePath)
          .then((body: string): void => {
            this.finishWebImport(body);
          })
          .catch((readError: Object): void => {
            this.finishWebImport('', `读取浏览器下载文件失败: ${this.importErrorMessage(readError)}`);
          });
      });
      delegate.onDownloadFailed((item: webview.WebDownloadItem): void => {
        if (!this.webImportActive) return;
        this.finishWebImport('', `浏览器内核下载失败 (${item.getLastErrorCode()})`);
      });
      this.webImportDownloadDelegate = delegate;
      this.webImportController.setDownloadDelegate(delegate);
      // Navigate like a normal browser address-bar request. The server's attachment
      // response then naturally enters WebDownloadDelegate.
      this.webImportController.loadUrl(this.webImportTargetUrl);
    } catch (error) {
      this.finishWebImport('', `浏览器内核下载启动失败: ${this.importErrorMessage(error as Object)}`);
    }
  }

  finishWebImport(body: string = '', errorMessage: string = ''): void {
    if (!this.webImportResolve && !this.webImportReject) return;
    if (this.webImportTimeoutId >= 0) clearTimeout(this.webImportTimeoutId);
    if (errorMessage && this.webImportDownloadItem) {
      try {
        this.webImportDownloadItem.cancel();
      } catch (_) {
      }
    }
    const resolve = this.webImportResolve;
    const reject = this.webImportReject;
    const downloadPath = this.webImportDownloadPath;
    this.webImportResolve = null;
    this.webImportReject = null;
    this.webImportTimeoutId = -1;
    this.webImportStarted = false;
    this.webImportTargetUrl = '';
    this.webImportDownloadDelegate = null;
    this.webImportDownloadItem = null;
    this.webImportDownloadPath = '';
    this.webImportActive = false;
    if (downloadPath) {
      try {
        fs.unlinkSync(downloadPath);
      } catch (_) {
      }
    }
    if (errorMessage) {
      if (reject) reject(new Error(errorMessage));
    } else if (resolve) {
      resolve(body);
    }
  }

  async fetchImportUrlViaDownload(url: string): Promise<string> {
    const context = getContext(this) as common.UIAbilityContext;
    const suffix = `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    const filePath = `${context.cacheDir}/book_source_import_${suffix}.json`;
    let task: request.DownloadTask | null = null;
    try {
      task = await request.downloadFile(context, {
        url: url,
        header: {
          'Accept': 'application/json,text/plain,*/*',
          'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS; Mobile) AppleWebKit/537.36 Safari/537.36'
        },
        enableMetered: true,
        enableRoaming: true,
        filePath: filePath,
        background: false,
        title: '导入书源'
      });
      await this.waitForImportDownload(task);
      return await this.readTextFile(filePath);
    } finally {
      if (task) {
        try {
          await task.delete();
        } catch (_) {
        }
      }
      try {
        fs.unlinkSync(filePath);
      } catch (_) {
      }
    }
  }

  waitForImportDownload(task: request.DownloadTask): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      let settled = false;
      const finish = (errorMessage: string = ''): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timeoutId);
        try {
          task.off('complete', onComplete);
          task.off('fail', onFail);
        } catch (_) {
        }
        if (errorMessage) reject(new Error(errorMessage));
        else resolve();
      };
      const onComplete = (): void => finish();
      const onFail = (errorCode: number): void => finish(this.downloadServiceErrorMessage(errorCode));
      const timeoutId = setTimeout(() => finish('下载服务超时'), BOOK_SOURCE_IMPORT_TIMEOUT_MS);
      try {
        task.on('complete', onComplete);
        task.on('fail', onFail);
      } catch (subscribeError) {
        finish(this.importErrorMessage(subscribeError as Object));
        return;
      }
      task.query().then((info: request.DownloadInfo): void => {
        if (info.status === request.SESSION_SUCCESSFUL) finish();
        else if (info.status === request.SESSION_FAILED) finish(this.downloadServiceErrorMessage(info.failedReason));
      }).catch((queryError: Object): void => {
        if (!settled) console.warn('查询书源下载状态失败:', queryError);
      });
    });
  }

  downloadServiceErrorMessage(errorCode: number): string {
    if (errorCode === 8) return '下载服务未知错误 (8)';
    return `下载服务失败 (${errorCode})`;
  }

  importUrlCandidates(url: string): string[] {
    const raw = (url || '').trim();
    if (!raw) return [];
    const candidates: string[] = [raw];
    if (/^http:\/\//i.test(raw)) {
      const secure = `https://${raw.substring('http://'.length)}`;
      if (!candidates.includes(secure)) candidates.push(secure);
    }
    return candidates;
  }

  importUrlHost(url: string): string {
    const match = (url || '').match(/^https?:\/\/([^/?#]+)/i);
    return match ? match[1] : '书源地址';
  }

  importUrlOrigin(url: string): string {
    const match = (url || '').match(/^(https?:\/\/[^/?#]+)/i);
    return match ? match[1] : '';
  }

  looksLikeBookSourceJson(body: string): boolean {
    const text = (body || '').replace(/^\uFEFF/, '').replace(/^\s+/, '');
    return text.startsWith('[') || text.startsWith('{');
  }

  isValidBookSourceJson(body: string): boolean {
    if (!this.looksLikeBookSourceJson(body)) return false;
    try {
      const parsed = JSON.parse((body || '').replace(/^\uFEFF/, '')) as Object;
      return Array.isArray(parsed) || (!!parsed && typeof parsed === 'object');
    } catch (_) {
      return false;
    }
  }

  hideKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (_) {
    }
  }

  importErrorMessage(error: Object): string {
    if (error instanceof Error && this.isReadableErrorText(error.message)) return error.message;
    if (typeof error === 'string' && this.isReadableErrorText(error as string)) return error as string;
    if (error && typeof error === 'object') {
      const record = error as Record<string, Object>;
      const rawMessage = record['message'] || record['msg'] || record['reason'];
      let message = typeof rawMessage === 'string' ? (rawMessage as string).trim() : '';
      if (!this.isReadableErrorText(message) && rawMessage && typeof rawMessage === 'object') {
        const nested = rawMessage as Record<string, Object>;
        message = String(nested['message'] || nested['msg'] || nested['reason'] || '').trim();
      }
      const code = String(record['code'] || record['errorCode'] || '').trim();
      if (this.isReadableErrorText(message)) return code ? `${message} (${code})` : message;
      try {
        const json = JSON.stringify(error);
        if (json && json !== '{}') return json;
      } catch (_) {
      }
    }
    const fallback = String(error || '').trim();
    return this.isReadableErrorText(fallback) ? fallback : '未知错误';
  }

  isReadableErrorText(value: string): boolean {
    const text = (value || '').trim().toLowerCase();
    return !!text && !text.includes('[object object]') && text !== 'object object' && text !== '{}';
  }

  async importSourcesFromJson(json: string) {
    try {
      console.log('开始解析JSON，长度:', json.length);
      let sources: BookSource[] = [];

      const parsed: Object = JSON.parse(json);
      console.log('JSON解析成功，类型:', typeof parsed);

      // 处理 {"value": [...]} 结构
      let items: Record<string, Object>[] = [];
      if (Array.isArray(parsed)) {
        items = parsed as Record<string, Object>[];
      } else if (typeof parsed === 'object') {
        const obj = parsed as Record<string, Object>;
        if (Array.isArray(obj['value'])) {
          items = obj['value'] as Record<string, Object>[];
        } else if (obj['bookSourceUrl']) {
          items = [obj];
        }
      }

      console.log('待解析书源数量:', items.length);

      for (const item of items) {
        const source = this.parseBookSource(item);
        if (source.bookSourceUrl) {
          sources.push(source);
        }
      }

      console.log('解析到书源数量:', sources.length);

      if (sources.length === 0) {
        promptAction.showToast({ message: '未找到有效的书源' });
        return;
      }

      // Multiple sources require an explicit choice so a large import does not
      // unexpectedly add every source to the local database.
      if (sources.length > 1) {
        this.pendingImportSources = sources;
        this.selectedImportSourceUrls = sources.map((source: BookSource) => source.bookSourceUrl);
        this.showImportSourceSelectionDialog = true;
        return;
      }

      await this.persistImportedSources(sources);
    } catch (e) {
      console.error('解析书源失败:', e);
      const errMsg = this.importErrorMessage(e as Object);
      promptAction.showToast({ message: `书源格式错误: ${errMsg}` });
    }
  }

  async persistImportedSources(sources: BookSource[]): Promise<void> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    let importCount = 0;
    let failedCount = 0;
    let lockedCount = 0;
    let lastInsertError = '';
    for (const source of sources) {
      if (source.bookSourceUrl && source.bookSourceName) {
        try {
          const stored = await db.insertBookSource(source);
          if (stored) {
            if (!await this.verifyImportedBookSource(db, source)) {
              throw new Error('写入后校验失败，书源内容未完整保存');
            }
            importCount++;
          } else {
            lockedCount++;
          }
        } catch (insertErr) {
          failedCount++;
          lastInsertError = this.importErrorMessage(insertErr as Object);
          console.error('插入书源失败:', source.bookSourceName, insertErr);
        }
      }
    }

    if (importCount === 0) {
      if (lockedCount > 0 && failedCount === 0) {
        promptAction.showToast({ message: `未导入：${lockedCount} 个同地址书源已锁定，请先解锁后重试` });
        return;
      }
      throw new Error(lastInsertError || '书源未能写入本地数据库');
    }

    const loginCount = sources.filter((source: BookSource) => this.sourceNeedsLogin(source)).length;
    const loginMessage = loginCount > 0 ? `，其中 ${loginCount} 个需要登录` : '';
    const failedMessage = failedCount > 0 ? `，${failedCount} 个失败` : '';
    const lockedMessage = lockedCount > 0 ? `，${lockedCount} 个已锁定未覆盖` : '';
    promptAction.showToast({
      message: `成功导入 ${importCount} 个书源${failedMessage}${lockedMessage}${loginMessage}`
    });
    await this.loadSources();
  }

  isImportSourceSelected(source: BookSource): boolean {
    return this.selectedImportSourceUrls.includes(source.bookSourceUrl);
  }

  setImportSourceSelected(source: BookSource, selected: boolean): void {
    if (selected) {
      if (!this.isImportSourceSelected(source)) {
        this.selectedImportSourceUrls = this.selectedImportSourceUrls.concat([source.bookSourceUrl]);
      }
      return;
    }
    this.selectedImportSourceUrls = this.selectedImportSourceUrls.filter((url: string) => url !== source.bookSourceUrl);
  }

  areAllImportSourcesSelected(): boolean {
    return this.pendingImportSources.length > 0 &&
      this.selectedImportSourceUrls.length === this.pendingImportSources.length;
  }

  selectAllImportSources(selected: boolean): void {
    this.selectedImportSourceUrls = selected ?
      this.pendingImportSources.map((source: BookSource) => source.bookSourceUrl) : [];
  }

  cancelImportSourceSelection(): void {
    this.showImportSourceSelectionDialog = false;
    this.pendingImportSources = [];
    this.selectedImportSourceUrls = [];
  }

  async confirmImportSourceSelection(): Promise<void> {
    if (this.selectedImportSourceUrls.length === 0 || this.isImporting) return;
    const selected = this.pendingImportSources.filter((source: BookSource) =>
      this.selectedImportSourceUrls.includes(source.bookSourceUrl));
    if (selected.length === 0) return;
    this.isImporting = true;
    try {
      await this.persistImportedSources(selected);
      this.cancelImportSourceSelection();
    } catch (e) {
      console.error('导入所选书源失败:', e);
      promptAction.showToast({ message: `导入失败: ${this.importErrorMessage(e as Object)}` });
    } finally {
      this.isImporting = false;
    }
  }

  parseBookSource(obj: Record<string, Object>): BookSource {
    const source = new BookSource();
    source.bookSourceUrl = obj['bookSourceUrl'] as string || '';
    source.bookSourceName = obj['bookSourceName'] as string || '';
    source.bookSourceType = Number(obj['bookSourceType'] || 0);
    source.bookSourceGroup = obj['bookSourceGroup'] as string || '';
    source.bookSourceComment = obj['bookSourceComment'] as string || '';
    source.loginUrl = obj['loginUrl'] as string || '';
    source.loginUi = obj['loginUi'] as string || '';
    source.loginCheckJs = obj['loginCheckJs'] as string || '';
    source.loginHeader = obj['loginHeader'] as string || '';
    source.loginInfo = String(obj['loginInfo'] || '');
    source.rawSourceJson = JSON.stringify(obj);
    source.bookUrlPattern = obj['bookUrlPattern'] as string || '';
    source.searchUrl = obj['searchUrl'] as string || '';
    source.exploreUrl = obj['exploreUrl'] as string || '';
    source.jsLib = obj['jsLib'] as string || '';
    source.header = obj['header'] as string || '';
    source.variableComment = obj['variableComment'] as string || '';
    source.variable = obj['variable'] as string || '';
    source.enabledCookieJar = obj['enabledCookieJar'] !== false;
    source.enabled = obj['enabled'] !== false;
    source.enabledExplore = obj['enabledExplore'] !== false;
    source.isPinned = obj['isPinned'] === true;
    source.isLocked = obj['isLocked'] === true || obj['locked'] === true;
    source.weight = (obj['weight'] as number) || 0;
    source.concurrentRate = obj['concurrentRate'] as string || '';
    source.lastUpdateTime = Number(obj['lastUpdateTime'] || Date.now());
    if (!Number.isFinite(source.lastUpdateTime)) source.lastUpdateTime = Date.now();
    source.respondTime = Number(obj['respondTime'] || 180000);
    if (!Number.isFinite(source.respondTime)) source.respondTime = 180000;
    source.customOrder = Math.floor(Number(obj['customOrder'] || 0));
    source.customButton = obj['customButton'] === true;
    source.eventListener = obj['eventListener'] === true;

    // 解析 searchRule (ruleSearch)
    const ruleSearch = obj['ruleSearch'];
    if (ruleSearch && typeof ruleSearch === 'string') {
      const fields = this.parseCompactRule(ruleSearch as string);
      const rule = new SearchRule();
      this.applyRuleToSearchRule(fields, rule);
      source.searchRule = rule;
    } else if (ruleSearch && typeof ruleSearch === 'object') {
      source.searchRule = ruleSearch as SearchRule;
    } else if (obj['searchRule'] && typeof obj['searchRule'] === 'object') {
      source.searchRule = obj['searchRule'] as SearchRule;
    }

    // 解析 exploreRule (ruleExplore)
    const ruleExplore = obj['ruleExplore'];
    if (ruleExplore && typeof ruleExplore === 'string') {
      const fields = this.parseCompactRule(ruleExplore as string);
      const rule = new ExploreRule();
      this.applyRuleToSearchRule(fields, rule);
      source.exploreRule = rule;
    } else if (ruleExplore && typeof ruleExplore === 'object' && !Array.isArray(ruleExplore)) {
      source.exploreRule = ruleExplore as ExploreRule;
    } else if (obj['exploreRule'] && typeof obj['exploreRule'] === 'object') {
      source.exploreRule = obj['exploreRule'] as ExploreRule;
    }

    // 解析 bookInfoRule (ruleBookInfo)
    const ruleBookInfo = obj['ruleBookInfo'];
    if (ruleBookInfo && typeof ruleBookInfo === 'string') {
      const fields = this.parseCompactRule(ruleBookInfo as string);
      const rule = new BookInfoRule();
      this.applyRuleToBookInfoRule(fields, rule);
      source.bookInfoRule = rule;
    } else if (ruleBookInfo && typeof ruleBookInfo === 'object') {
      source.bookInfoRule = ruleBookInfo as BookInfoRule;
    } else if (obj['bookInfoRule'] && typeof obj['bookInfoRule'] === 'object') {
      source.bookInfoRule = obj['bookInfoRule'] as BookInfoRule;
    }

    // 解析 tocRule (ruleToc)
    const ruleToc = obj['ruleToc'];
    if (ruleToc && typeof ruleToc === 'string') {
      const fields = this.parseCompactRule(ruleToc as string);
      const rule = new TocRule();
      this.applyRuleToTocRule(fields, rule);
      source.tocRule = rule;
    } else if (ruleToc && typeof ruleToc === 'object') {
      source.tocRule = ruleToc as TocRule;
    } else if (obj['tocRule'] && typeof obj['tocRule'] === 'object') {
      source.tocRule = obj['tocRule'] as TocRule;
    }

    // 解析 contentRule (ruleContent)
    const ruleContent = obj['ruleContent'];
    if (ruleContent && typeof ruleContent === 'string') {
      const fields = this.parseCompactRule(ruleContent as string);
      const rule = new ContentRule();
      this.applyRuleToContentRule(fields, rule);
      source.contentRule = rule;
    } else if (ruleContent && typeof ruleContent === 'object') {
      source.contentRule = ruleContent as ContentRule;
    } else if (obj['contentRule'] && typeof obj['contentRule'] === 'object') {
      source.contentRule = obj['contentRule'] as ContentRule;
    }

    return source;
  }

  async verifyImportedBookSource(db: AppDatabase, expected: BookSource): Promise<boolean> {
    const actual = await db.getBookSource(expected.bookSourceUrl);
    if (!actual) return false;
    return actual.rawSourceJson === expected.rawSourceJson &&
      actual.jsLib === expected.jsLib &&
      actual.loginUrl === expected.loginUrl &&
      actual.loginUi === expected.loginUi &&
      actual.header === expected.header &&
      actual.searchUrl === expected.searchUrl &&
      actual.exploreUrl === expected.exploreUrl &&
      this.ruleContainsImportedFields(actual.searchRule, expected.searchRule) &&
      this.ruleContainsImportedFields(actual.exploreRule, expected.exploreRule) &&
      this.ruleContainsImportedFields(actual.bookInfoRule, expected.bookInfoRule) &&
      this.ruleContainsImportedFields(actual.tocRule, expected.tocRule) &&
      this.ruleContainsImportedFields(actual.contentRule, expected.contentRule) &&
      actual.respondTime === expected.respondTime &&
      actual.customButton === expected.customButton &&
      actual.eventListener === expected.eventListener;
  }

  ruleContainsImportedFields(actual: Object, expected: Object): boolean {
    const actualRecord = actual as Record<string, Object>;
    const expectedRecord = expected as Record<string, Object>;
    for (const key of Object.keys(expectedRecord)) {
      if (JSON.stringify(actualRecord[key]) !== JSON.stringify(expectedRecord[key])) return false;
    }
    return true;
  }

  parseCompactRule(ruleStr: string): Record<string, string> {
    const result: Record<string, string> = {};

    let content = ruleStr.trim();
    if (content.startsWith('@{')) {
      content = content.substring(2);
    }
    if (content.endsWith('}')) {
      content = content.substring(0, content.length - 1);
    }

    let depth = 0;
    let inString = false;
    let stringChar = '';
    let inJsValue = false; // 是否在 @js: 值内部

    const pairs: string[] = [];
    let current = '';

    for (let i = 0; i < content.length; i++) {
      const ch = content[i];

      if (inString) {
        current += ch;
        if (ch === '\\') {
          i++;
          if (i < content.length) current += content[i];
        } else if (ch === stringChar) {
          inString = false;
        }
        continue;
      }

      if (ch === '"' || ch === "'") {
        inString = true;
        stringChar = ch;
        current += ch;
        continue;
      }

      if (ch === '(' || ch === '[' || ch === '{') {
        depth++;
        current += ch;
        continue;
      }

      if (ch === ')' || ch === ']' || ch === '}') {
        if (depth > 0) depth--;
        current += ch;
        continue;
      }

      // 检测当前是否在 @js: 值中（值以 @js: 开头时禁用分号拆分）
      if (!inJsValue && current.trim().includes('=@js:')) {
        inJsValue = true;
      }

      // 在非 @js: 值中，分号且深度为0时作为分隔符
      if (ch === ';' && depth === 0 && !inJsValue) {
        pairs.push(current.trim());
        current = '';
        continue;
      }

      // 在 @js: 值中，分号+换行可能表示新字段开始
      if (ch === ';' && depth === 0 && inJsValue) {
        // 检查后续是否是新字段: ;\s*keyword=
        const rest = content.substring(i + 1);
        const nextFieldMatch = rest.match(/^\s*(\w+)=/);
        if (nextFieldMatch) {
          // 是新字段开始，结束当前 @js: 值
          pairs.push(current.trim());
          current = '';
          inJsValue = false;
          // 跳过空白
          while (i + 1 < content.length && (content[i + 1] === ' ' || content[i + 1] === '\n' || content[i + 1] === '\r')) {
            i++;
          }
          continue;
        }
      }

      current += ch;
    }

    if (current.trim()) {
      pairs.push(current.trim());
    }

    for (const pair of pairs) {
      const eqIdx = pair.indexOf('=');
      if (eqIdx > 0) {
        const field = pair.substring(0, eqIdx).trim();
        let value = pair.substring(eqIdx + 1).trim();

        if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }

        result[field] = value;
      }
    }

    return result;
  }

  applyRuleToSearchRule(fields: Record<string, string>, rule: SearchRule): void {
    rule.bookList = fields['bookList'] || fields['booklist'] || '';
    rule.name = fields['name'] || '';
    rule.author = fields['author'] || '';
    rule.coverUrl = fields['coverUrl'] || '';
    rule.intro = fields['intro'] || fields['desc'] || '';
    rule.kind = fields['kind'] || '';
    rule.status = fields['status'] || '';
    rule.lastChapter = fields['lastChapter'] || fields['lastchapter'] || '';
    rule.bookUrl = fields['bookUrl'] || fields['bookurl'] || '';
    rule.wordCount = fields['wordCount'] || fields['wordcount'] || '';
  }

  applyRuleToTocRule(fields: Record<string, string>, rule: TocRule): void {
    rule.chapterList = fields['chapterList'] || fields['chapterlist'] || '';
    rule.chapterName = fields['chapterName'] || fields['chaptername'] || '';
    rule.chapterUrl = fields['chapterUrl'] || fields['chapterurl'] || '';
    rule.nextTocUrl = fields['nextTocUrl'] || fields['nexttocurl'] || '';
    rule.isVip = fields['isVip'] || fields['isvip'] || '';
    rule.isPay = fields['isPay'] || fields['ispay'] || '';
    rule.updateTime = fields['updateTime'] || fields['updatetime'] || '';
  }

  applyRuleToContentRule(fields: Record<string, string>, rule: ContentRule): void {
    rule.content = fields['content'] || '';
    rule.title = fields['title'] || '';
    rule.images = fields['images'] || '';
    rule.sourceRegex = fields['sourceRegex'] || fields['sourceregex'] || '';
    rule.nextContentUrl = fields['nextContentUrl'] || fields['nextcontenturl'] || '';
    rule.replaceRegex = fields['replaceRegex'] || fields['replaceregex'] || '';
    rule.imageDecode = fields['imageDecode'] || fields['imagedecode'] || '';
    rule.imageStyle = fields['imageStyle'] || fields['imagestyle'] || '';
    rule.payAction = fields['payAction'] || fields['payaction'] || '';
  }

  applyRuleToBookInfoRule(fields: Record<string, string>, rule: BookInfoRule): void {
    rule.init = fields['init'] || '';
    rule.name = fields['name'] || '';
    rule.author = fields['author'] || '';
    rule.coverUrl = fields['coverUrl'] || '';
    rule.intro = fields['intro'] || fields['desc'] || '';
    rule.kind = fields['kind'] || '';
    rule.lastChapter = fields['lastChapter'] || fields['lastchapter'] || '';
    rule.wordCount = fields['wordCount'] || fields['wordcount'] || '';
    rule.updateTime = fields['updateTime'] || fields['updatetime'] || '';
    rule.tocUrl = fields['tocUrl'] || fields['tocurl'] || '';
  }
}
