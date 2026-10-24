import { AppAiHost } from '../utils/AppAiHost';
import { AiAccessPolicy } from '../account/AiAccessPolicy';
import { ComicColorizer } from '@legado/aiengine';
import { ImmersiveLightSettingsStore } from '../utils/ImmersiveLightSettingsStore';
import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext, window } from '@kit.ArkUI';
import { RecentReadShortcut, RECENT_READ_SHORTCUT_ACTION, OPEN_BOOK_SHORTCUT_ACTION } from '../utils/RecentReadShortcut';
import { CoverGalleryStore } from '../utils/CoverGalleryStore';
import { BookshelfDisplaySettingsStore } from '../utils/BookshelfDisplaySettingsStore';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { CustomThemeSchemeStore } from '../utils/CustomThemeSchemeStore';
import { AppThemeModeStore } from '../utils/AppThemeModeStore';
import { AppIconSettingsStore } from '../utils/AppIconSettingsStore';
import { AppIconManager } from '../utils/AppIconManager';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ReaderProgressCheckpoint } from '../utils/ReaderProgressCheckpoint';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeIds } from '../theme/ThemeModels';
import { ThemeTrialManager } from '../utils/ThemeTrialManager';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { MemberSettingsStore } from '../account/MemberSettingsStore';
import { MembershipThemeGuard } from '../account/MembershipThemeGuard';
import { HuaweiAccountService } from '../account/HuaweiAccountService';
import { CloudSyncSettingsStore } from '../account/CloudSyncSettingsStore';
import { CloudSyncCoordinator } from '../account/CloudSyncCoordinator';
import { CloudSyncChangeTracker } from '../account/CloudSyncChangeTracker';
import { StartupCoverTextStore } from '../utils/StartupCoverTextStore';
import { BookSourceRuntimeStore, NativeSourceInteraction, SourceScriptNotice, TlsTrustStore } from '@legado/sourceengine';
import { AppSourceInteraction } from '../utils/AppSourceInteraction';
import { HdsFeedback } from '../utils/HdsFeedback';
import { QuickJsDiagnostics } from '@legado/sourceengine/Diagnostics';
import { AppDatabase } from '../model/data/AppDatabase';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { FullTextCacheCancelCoordinator } from '../utils/FullTextCacheCancelCoordinator';
import { lanReaderServer } from '../core/lan/LanReaderServer';
import { LanReaderPasswordStore } from '../core/lan/LanReaderPasswordStore';
import { readStatsTracker } from '../core/stats/ReadStatsTracker';
import { CloudAutoSync } from '../account/CloudAutoSync';
import { ReaderCacheBudget } from '../core/book/ReaderCacheBudget';

export default class EntryAbility extends UIAbility {
  private appliedColorMode: number = -1;
  private modeDependentThemeKey: string = '';
  private immersiveLightBootstrapPromise: Promise<void> = Promise.resolve();
  private memberSettingsBootstrapPromise: Promise<void> = Promise.resolve();
  private themeBootstrapPromise: Promise<void> = Promise.resolve();
  private readerBootstrapPromise: Promise<void> = Promise.resolve();
  private accountBootstrapPromise: Promise<void> = Promise.resolve();
  private membershipThemeTimer: number = -1;
  private deferredStartupScheduled: boolean = false;
  private mainWindowStage: window.WindowStage | null = null;
  // 系统全局字体的 ID，后台换了手机字体后回到前台靠它发现变化。
  private systemFontId: string = '';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    AppStorage.setOrCreate('startupT0', Date.now());
    AppStorage.setOrCreate('appCacheDir', this.context.cacheDir);
    AppStorage.setOrCreate('appFilesDir', this.context.filesDir);
    AppStorage.setOrCreate('pendingBookSourceImportUri', '');
    AppStorage.setOrCreate('pendingBookSourceImportUrl', '');
    AppStorage.setOrCreate('pendingBookSourceImportNonce', 0);
    AppStorage.setOrCreate('bookSourceCheckOpenNonce', 0);
    AppStorage.setOrCreate('shelfUpdateTime', 0);
    AppStorage.setOrCreate('pendingLocalBookImportUri', '');
    AppStorage.setOrCreate('pendingLocalBookImportNonce', 0);
    AppStorage.setOrCreate('pendingLocalBookImportFormat', '');
    AppStorage.setOrCreate('pendingLocalBookImportName', '');
    AppStorage.setOrCreate('globalTtsCapsulePositionX', 16);
    AppStorage.setOrCreate('globalTtsCapsulePositionY', -1);
    AppStorage.setOrCreate('globalTtsTextBefore', '');
    AppStorage.setOrCreate('globalTtsCurrentText', '');
    AppStorage.setOrCreate('globalTtsTextAfter', '');
    AccountSessionStore.initializeStorage();
    AiAccessPolicy.initialize();
    AppAiHost.install();
    this.memberSettingsBootstrapPromise = MemberSettingsStore.load(this.context).catch((error: Error) => {
      console.warn('恢复会员设置失败:', error);
    });
    CloudSyncSettingsStore.initializeStorage();
    CloudSyncChangeTracker.initializeStorage();
    readStatsTracker.init(this.context);
    BookSourceRuntimeStore.install(AppDatabase.getInstance());
    SourceScriptNotice.setHandler((sourceName: string, message: string): void => {
      HdsFeedback.showToast(sourceName ? `${sourceName}：${message}` : message);
    });
    // 原生书源脚本的提示、刷新发现页、打开网页。
    NativeSourceInteraction.setHandler(new AppSourceInteraction(this.context));
    TlsTrustStore.load(this.context).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Load TLS trust settings failed: %{public}s', JSON.stringify(e));
    });
    hilog.info(0x0000, 'testTag', 'StartupTrace onCreate %{public}d', Date.now());
    PersistentStorage.persistProp('appThemeMode', 'system');
    AppThemeModeStore.load(this.context).then((mode: string) => {
      AppThemeModeStore.applyToStorage(mode);
      this.applyThemeColorMode(mode, this.context.config);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync app theme mode failed: %{public}s', JSON.stringify(e));
      this.syncSystemColorMode(this.context.config);
    });
    AppStorage.setOrCreate('readerSystemFontFamily', ReaderSystemFontHelper.FALLBACK_SYSTEM_FONT_FAMILY);
    AppStorage.setOrCreate('readerActiveFontFamily', '');
    AppStorage.setOrCreate('readerFontRegistered', false);
    AppStorage.setOrCreate('systemFontRevision', 0);
    this.systemFontId = this.context.config.fontId || '';
    PersistentStorage.persistProp('readerPageTurnMode', 1);
    PersistentStorage.persistProp('readerPreloadEnabled', true);
    PersistentStorage.persistProp('readerPreloadChapterCount', 1);
    PersistentStorage.persistProp('readerUseTtsQuickAction', true);
    PersistentStorage.persistProp('readerUseChapterQuickJump', true);
    PersistentStorage.persistProp('fullTextCacheCancelNonce', 0);
    PersistentStorage.persistProp('fullTextCacheCancelSignal', '');
    PersistentStorage.persistProp('readerBodyFontMode', 'global');
    PersistentStorage.persistProp('readerBodyFontFamily', '');
    PersistentStorage.persistProp('readerTitleFontMode', 'global');
    PersistentStorage.persistProp('readerTitleFontFamily', '');
    PersistentStorage.persistProp('readerTitleFontSize', 22);
    PersistentStorage.persistProp('readerRegexFontEnabled', false);
    PersistentStorage.persistProp('readerRegexFontPattern', '');
    PersistentStorage.persistProp('readerRegexFontMode', 'global');
    PersistentStorage.persistProp('readerRegexFontFamily', '');
    PersistentStorage.persistProp('readerRegexFontSize', 20);
    PersistentStorage.persistProp('readerRegexShadowColor', '');
    PersistentStorage.persistProp('readerRegexFontRulesRaw', '');
    PersistentStorage.persistProp('lanReaderEnabled', false);
    // Only read here to pick up a plain-text password left by older versions; LanReaderPasswordStore moves it
    // into encrypted storage and stops persisting this entry.
    PersistentStorage.persistProp('lanReaderPassword', '');
    AppStorage.setOrCreate('lanReaderAddress', '');
    AppStorage.setOrCreate('lanReaderStatus', '已关闭');
    AppStorage.setOrCreate('lanReaderToken', '');
    AppStorage.setOrCreate('lanReaderBackgroundStatus', '未启动');
    if (AppStorage.get<number>('statusBarHeight') === undefined) {
      AppStorage.setOrCreate('statusBarHeight', 32);
    }
    if (AppStorage.get<number>('navBarHeight') === undefined) {
      AppStorage.setOrCreate('navBarHeight', 0);
    }
    PersistentStorage.persistProp('bookshelfSortMode', 'recentRead');
    PersistentStorage.persistProp('ttsPerson', 0);
    PersistentStorage.persistProp('ttsOnline', 1);
    PersistentStorage.persistProp('ttsStyle', '');
    PersistentStorage.persistProp('ttsLanguage', 'zh-CN');
    PersistentStorage.persistProp('ttsSpeed', 1);
    PersistentStorage.persistProp('ttsInstalledVoiceKeys', '');
    PersistentStorage.persistProp('ttsCustomVoiceId', '');
    PersistentStorage.persistProp('ttsCustomVoices', '');
    PersistentStorage.persistProp('ttsCloudVoiceId', '');
    PersistentStorage.persistProp('ttsOfflineSdkModeMigrated', false);
    if (!AppStorage.get<boolean>('ttsOfflineSdkModeMigrated')) {
      if (AppStorage.get<number>('ttsOnline') === 0 &&
        (AppStorage.get<number>('ttsPerson') ?? 0) === 0 &&
        !(AppStorage.get<string>('ttsStyle') || '') &&
        ((AppStorage.get<string>('ttsLanguage') || 'zh-CN') === 'zh-CN')) {
        AppStorage.setOrCreate('ttsOnline', 1);
      }
      AppStorage.setOrCreate('ttsOfflineSdkModeMigrated', true);
    }
    PersistentStorage.persistProp('readerPageTurnAnimation', true);
    PersistentStorage.persistProp('readerPageTurnAnimationType', 1);
    PersistentStorage.persistProp('readerVolumeTurnPage', false);
    PersistentStorage.persistProp('readerKeepScreenOn', true);
    PersistentStorage.persistProp('readerExtendToStatusBar', false);
    PersistentStorage.persistProp('readerLastPageViewWidth', 0);
    PersistentStorage.persistProp('readerLastPageViewHeight', 0);
    PersistentStorage.persistProp('bookshelfShowTags', true);
    PersistentStorage.persistProp('bookshelfShowSource', true);
    PersistentStorage.persistProp('bookshelfShowIntro', true);
    PersistentStorage.persistProp('bookshelfShowFullIntro', false);
    PersistentStorage.persistProp('bookshelfShowProgressBar', false);
    PersistentStorage.persistProp('bookshelfShowLastReadTime', true);
    PersistentStorage.persistProp('bookshelfShowLastReadChapter', false);
    PersistentStorage.persistProp('bookshelfLayoutMode', 'compact');
    PersistentStorage.persistProp('bookshelfLastReadLeafMode', 'adaptive');
    PersistentStorage.persistProp('bookshelfLastReadPinMode', 'medium');
    PersistentStorage.persistProp('bookshelfBookOpenAnimation', true);
    PersistentStorage.persistProp('bookshelfCoverAlbums', '');
    PersistentStorage.persistProp('bookshelfLightCoverAlbumId', '');
    PersistentStorage.persistProp('bookshelfDarkCoverAlbumId', '');
    PersistentStorage.persistProp('bookshelfCoverApplyScope', 'all');
    PersistentStorage.persistProp('bookshelfCoverTargetBooks', '');
    PersistentStorage.persistProp('bookshelfIgnoreSourceCover', false);
    PersistentStorage.persistProp('bookshelfCoverMode', 'sequence');
    PersistentStorage.persistProp('searchExploreShowResultCover', true);
    PersistentStorage.persistProp('searchExploreShowResultCoverBackground', true);
    PersistentStorage.persistProp('searchExploreUseBookshelfCoverGallery', false);
    PersistentStorage.persistProp('searchExploreShowResultTags', true);
    PersistentStorage.persistProp('searchExploreAggregateResults', true);
    PersistentStorage.persistProp('searchResultCategory', 'all');
    PersistentStorage.persistProp('searchResultLayout', 'list');
    PersistentStorage.persistProp('exploreResultLayout', 'list');
    PersistentStorage.persistProp('searchExplorePromptAddToShelfOnBack', true);
    PersistentStorage.persistProp('searchExploreExactSearch', false);
    PersistentStorage.persistProp('searchExploreExactSearchMatchAuthor', true);
    PersistentStorage.persistProp('searchExploreShowSearchProgress', true);
    PersistentStorage.persistProp('searchExploreSearchConcurrency', 6);
    PersistentStorage.persistProp('searchExploreSelectedSourceGroups', '');
    PersistentStorage.persistProp('searchExploreSourceSort', '');
    PersistentStorage.persistProp('bookSourceOrderRevision', 0);
    PersistentStorage.persistProp('compatSourceNoticeDismissed', false);
    PersistentStorage.persistProp('appLightAccentColor', '#007DFF');
    PersistentStorage.persistProp('appDarkAccentColor', '#4E9BFF');
    PersistentStorage.persistProp('appLightButtonColor', '#007DFF');
    PersistentStorage.persistProp('appDarkButtonColor', '#3F8CFF');
    // Immersive light strength: adaptive follows the system by default.
    PersistentStorage.persistProp('immersiveLightLevel', 'adaptive');
    this.immersiveLightBootstrapPromise = ImmersiveLightSettingsStore.load(this.context).catch((error: Error) => {
      console.warn('恢复沉浸光感设置失败:', error);
    });
    PersistentStorage.persistProp('appIconId', AppIconSettingsStore.DEFAULT_ICON_ID);
    PersistentStorage.persistProp('explorePlatform', '');
    PersistentStorage.persistProp('exploreSourceUrl', '');
    CoverGalleryStore.load(this.context).then((snapshot) => {
      CoverGalleryStore.applyToStorage(snapshot);
      return CoverGalleryStore.save(this.context, snapshot);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync cover gallery settings failed: %{public}s', JSON.stringify(e));
    });
    BookshelfDisplaySettingsStore.load(this.context).then((settings) => {
      BookshelfDisplaySettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync bookshelf display settings failed: %{public}s', JSON.stringify(e));
    });
    SearchExploreSettingsStore.load(this.context).then((settings) => {
      SearchExploreSettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync search explore settings failed: %{public}s', JSON.stringify(e));
    });
    TtsSettingsStore.load(this.context).then((settings) => {
      TtsSettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync tts settings failed: %{public}s', JSON.stringify(e));
    });
    this.accountBootstrapPromise = AccountSessionStore.load(this.context).then(() => {
      AiAccessPolicy.start();
      const userId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      return CloudSyncSettingsStore.load(this.context, userId).then((): void => {});
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Load account session failed: %{public}s', JSON.stringify(e));
    });
    const appThemePromise = AppThemeSettingsStore.load(this.context).then((settings) => {
      AppThemeSettingsStore.applyToStorage(settings);
      return StartupCoverTextStore.load(this.context);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync app theme settings failed: %{public}s', JSON.stringify(e));
    });
    // The theme affects the first frame.
    this.themeBootstrapPromise = appThemePromise.then(() => {});
    Promise.all([this.themeBootstrapPromise, this.accountBootstrapPromise]).then(() => {
      this.membershipThemeTimer = setInterval(() => {
        MembershipThemeGuard.refresh(this.context).catch((error: Error) => console.warn('主题权益检查失败', error.message));
      }, 60000);
      return MembershipThemeGuard.refresh(this.context);
    }).then(() => {
      // Font and local-book cloud sync waits for the account and stays out of the first frames.
      CloudAutoSync.schedule(this.context, 8000);
    }).catch((error: Error) => console.warn('主题权益初始化检查失败', error.message));
    // Reader preferences and custom font registration are not needed to paint Index/Startup, so the first
    // content does not wait for them. They do wait for the theme: reader settings are kept per theme, and
    // loading before appThemeId is restored would read the default theme's copy (including its global font).
    // 自定义主题每套方案各有一份阅读设置，读取前先恢复正在使用的方案。
    this.readerBootstrapPromise = appThemePromise.then(() => {
      return CustomThemeSchemeStore.restoreActiveSchemeId(this.context).catch((e: Error) => {
        hilog.warn(0x0000, 'testTag', 'Restore custom theme scheme failed: %{public}s', JSON.stringify(e));
      });
    }).then(() => {
      return ReaderSettingsStore.load(this.context);
    }).then((settings) => {
      ReaderSettingsStore.applyToStorage(settings);
      if (AppStorage.get<boolean>('lanReaderEnabled')) {
        return lanReaderServer.start(this.context);
      }
      return LanReaderPasswordStore.restore(this.context);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync reader settings failed: %{public}s', JSON.stringify(e));
    });
    AppIconSettingsStore.load(this.context).then((settings) => {
      AppIconSettingsStore.applyToStorage(settings);
      return AppIconManager.syncCurrentIcon(this.context);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync app icon settings failed: %{public}s', JSON.stringify(e));
    });
    this.handleLaunchWant(want);
  }

  onDestroy(): void {
    AiAccessPolicy.stop();
    if (this.membershipThemeTimer >= 0) clearInterval(this.membershipThemeTimer);
    lanReaderServer.stop().catch(() => undefined);
    readStatsTracker.flush();
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindowStage = windowStage;
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    hilog.info(0x0000, 'testTag', 'StartupTrace onWindowStageCreate %{public}d', Date.now());

    Promise.all([this.themeBootstrapPromise, this.immersiveLightBootstrapPromise,
      this.memberSettingsBootstrapPromise]).finally(() => {
      this.loadStartupContent(windowStage);
    });
  }

  private loadStartupContent(windowStage: window.WindowStage): void {
    const darkMode = AppStorage.get<boolean>('appDarkMode') || false;
    const activeThemeId = AppStorage.get<string>(AppThemeSettingsStore.KEY_THEME_ID) ||
      AppThemeSettingsStore.DEFAULT_THEME_ID;
    const customStartupImage = activeThemeId === ThemeIds.CUSTOM ?
      (AppStorage.get<string>(darkMode ?
        AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_IMAGE_PATH :
        AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_IMAGE_PATH) || '') : '';
    const usesSystemStartup = ThemeRuntime.startupThemeId(darkMode) === ThemeIds.PLAIN_DEFAULT &&
      !customStartupImage;
    const hasPendingImport = !!AppStorage.get<string>('pendingBookSourceImportUri') ||
      !!AppStorage.get<string>('pendingLocalBookImportUri');
    const initialPage = usesSystemStartup && !hasPendingImport ? 'pages/Index' : 'pages/Startup';
    windowStage.loadContent(initialPage, (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'testTag', 'StartupTrace %{public}s content loaded %{public}d',
        initialPage, Date.now());
      this.syncStartupWindow(windowStage);
      this.scheduleDeferredStartupInitialization();
    });
  }

  private scheduleDeferredStartupInitialization(): void {
    if (this.deferredStartupScheduled) return;
    this.deferredStartupScheduled = true;
    // Let the first frame commit before registering a potentially large custom font file.
    setTimeout(() => {
      ReaderCacheBudget.scheduleStartupTrim();
      QuickJsDiagnostics.initialize(this.context).catch((error: Error) => {

        hilog.warn(0x0000, 'QuickJS', 'Migration initialization failed: %{public}s', error.message);
      });
      // ReaderFontHelper only counts a font as registered when the UIContext registration succeeds, so a null
      // context here always fell back to the theme font when Index (not Startup) was the first page.
      this.readerBootstrapPromise
        .then(() => ReaderFontBootstrap.registerFromSettings(
          this.context, this.mainUIContext(), 'ability-after-first-content'))
        .catch((e: Error) => {
          hilog.warn(0x0000, 'testTag', 'Deferred reader bootstrap failed: %{public}s', JSON.stringify(e));
        });
    }, 80);
  }

  private mainUIContext(): UIContext | null {
    if (!this.mainWindowStage) {
      return null;
    }
    try {
      return this.mainWindowStage.getMainWindowSync().getUIContext();
    } catch (e) {
      hilog.warn(0x0000, 'testTag', 'Get main UIContext failed: %{public}s', JSON.stringify(e));
      return null;
    }
  }

  onWindowStageDestroy(): void {
    this.mainWindowStage = null;
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    ComicColorizer.setAppForeground(true);
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
    readStatsTracker.setAppForeground(true);
    AppStorage.setOrCreate<number>('appLifecycleForegroundRevision', Date.now());
    if (AppStorage.get<boolean>('lanReaderEnabled') && !lanReaderServer.isRunning()) {
      lanReaderServer.start(this.context).catch((e: Error) => {
        hilog.warn(0x0000, 'testTag', 'Restart LAN reader failed: %{public}s', JSON.stringify(e));
      });
    }
    ThemeTrialManager.stopIfExpired();
    this.syncSystemColorMode(this.context.config);
    this.syncSystemFont(this.context.config, 'foreground');
    this.accountBootstrapPromise
      .then(() => {
        AiAccessPolicy.start();
        return HuaweiAccountService.renewSession(this.context);
      })
      .then(() => MembershipThemeGuard.refresh(this.context))
      .catch((e: Error) => {
        hilog.warn(0x0000, 'testTag', 'Renew account session failed: %{public}s', JSON.stringify(e));
      })
      .finally(() => {
        // A failed renewal must not skip the file sync; it checks login and membership itself.
        CloudAutoSync.schedule(this.context, 5000);
        setTimeout(() => {
          CloudSyncCoordinator.syncAutomatically(
            this.context, CloudSyncCoordinator.TRIGGER_FOREGROUND).catch((e: Error) => {
            hilog.warn(0x0000, 'testTag', 'Foreground cloud sync failed: %{public}s', JSON.stringify(e));
          });
        }, 1200);
      });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', 'Ability onNewWant %{public}s', JSON.stringify(launchParam));
    const launchTarget = this.handleLaunchWant(want);
    if (launchTarget && this.mainWindowStage) {
      const targetUrl = launchTarget === 'bookSource' ? 'pages/BookSource' :
        launchTarget === 'themeImport' ? 'pages/ThemeSettings' :
        (launchTarget === 'audioBook' ? 'pages/AudioBook' : 'pages/Startup');
      this.mainWindowStage.getMainWindow().then((mainWindow: window.Window) => {
        const appRouter = mainWindow.getUIContext().getRouter();
        const state = appRouter.getState();
        if (this.routeMatches(state.name, state.path, targetUrl)) {
          return Promise.resolve();
        }
        if (launchTarget === 'audioBook') {
          return appRouter.pushUrl({
            url: targetUrl,
            params: {
              bookUrl: AppStorage.get<string>('pendingAudioBookUrl') || '',
              audioPanelAction: ''
            }
          });
        }
        return appRouter.pushUrl({ url: targetUrl });
      }).catch((e: Error) => {
        hilog.warn(0x0000, 'testTag', 'Open external file failed: %{public}s', JSON.stringify(e));
      });
    }
  }

  onBackground(): void {
    AiAccessPolicy.stop();
    ComicColorizer.setAppForeground(false);
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
    readStatsTracker.setAppForeground(false);
    // Page.onPageShow is shared by real route returns and a simple Home/lock-screen resume. Publish a
    // background revision so retained pages do not treat the foreground transition as a settings change.
    AppStorage.setOrCreate<number>('appLifecycleBackgroundRevision', Date.now());
    ReaderProgressCheckpoint.request('ability-background').then(() => {
      // Keep the background upload behind the local checkpoint so it cannot publish a stale page number.
      return CloudSyncCoordinator.syncAutomatically(
        this.context, CloudSyncCoordinator.TRIGGER_BACKGROUND);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Background cloud sync failed: %{public}s', JSON.stringify(e));
    });
  }

  onMemoryLevel(_level: AbilityConstant.MemoryLevel): void {
    ComicColorizer.onMemoryPressure();
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.syncSystemColorMode(newConfig);
    this.syncSystemFont(newConfig, 'configuration-update');
  }

  private syncSystemFont(config: Configuration, source: string): void {
    const fontId = config.fontId || '';
    if (!fontId || fontId === this.systemFontId) {
      return;
    }
    const known = !!this.systemFontId;
    this.systemFontId = fontId;
    if (!known) {
      return;
    }
    // 等阅读设置载入后再处理，回写的系统字体名才不会被启动流程用旧值盖掉。
    // 回调先于 ArkUI 收到这次配置变化（日志里相差约 30ms），延后一点，等它装好新的主题字体再清缓存、重排。
    this.readerBootstrapPromise.then(() => {
      setTimeout(() => {
        ReaderFontBootstrap.onSystemFontChanged(this.context, this.mainUIContext(), source);
      }, 500);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync system font failed: %{public}s', JSON.stringify(e));
    });
  }

  private syncSystemColorMode(config: Configuration): void {
    const mode = AppStorage.get<string>('appThemeMode') || 'system';
    this.applyThemeColorMode(mode, config);
  }

  private applyThemeColorMode(mode: string, config: Configuration): void {
    const normalizedMode = AppThemeModeStore.normalizeMode(mode);
    AppStorage.setOrCreate('appThemeMode', normalizedMode);
    if (normalizedMode === 'dark') {
      AppStorage.setOrCreate('appDarkMode', true);
      this.setApplicationColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      this.refreshModeDependentTheme(true);
      return;
    }
    if (normalizedMode === 'light') {
      AppStorage.setOrCreate('appDarkMode', false);
      this.setApplicationColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      this.refreshModeDependentTheme(false);
      return;
    }
    this.setApplicationColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    const darkMode = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate('appDarkMode', darkMode);
    this.refreshModeDependentTheme(darkMode);
  }

  private refreshModeDependentTheme(darkMode: boolean): void {
    // Foregrounding the ability does not imply that the effective theme changed.
    // Re-publishing an unchanged custom theme increments themeRevision and forces
    // every visible ArkUI form to rebuild, which can reset native text editors.
    const themeKey = `${ThemeRuntime.currentThemeId()}:${darkMode ? 'dark' : 'light'}`;
    if (this.modeDependentThemeKey === themeKey) {
      return;
    }
    this.modeDependentThemeKey = themeKey;
    AppThemeSettingsStore.reapplyCustomForMode(darkMode);
    ReaderFontBootstrap.applyApplicationFont(this.context, 'mode-dependent-theme');
  }

  private setApplicationColorMode(colorMode: number): void {
    if (this.appliedColorMode === colorMode) {
      return;
    }
    this.appliedColorMode = colorMode;
    this.context.getApplicationContext().setColorMode(colorMode);
  }

  private handleLaunchWant(want: Want): string {
    hilog.info(0x0000, 'testTag',
      'Launch want action=%{public}s type=%{public}s uri=%{private}s params=%{public}s',
      want.action || '', want.type || '', want.uri || '', this.wantParameterKeys(want));
    const externalUri = this.externalFileUri(want);
    const externalName = this.externalFileNameHint(want, externalUri);
    const externalFormat = externalUri ? this.externalFileFormat(want, externalUri, externalName) : '';
    if (externalUri && externalFormat === 'qytheme') {
      AppStorage.setOrCreate('pendingThemeImportUri', externalUri);
      const nonce = AppStorage.get<number>('pendingThemeImportNonce') || 0;
      AppStorage.setOrCreate('pendingThemeImportNonce', nonce + 1);
      return 'themeImport';
    }
    if (externalUri && externalFormat === 'json') {
      AppStorage.setOrCreate('pendingBookSourceImportUri', externalUri);
      const nonce = AppStorage.get<number>('pendingBookSourceImportNonce') || 0;
      AppStorage.setOrCreate('pendingBookSourceImportNonce', nonce + 1);
      return 'bookSource';
    }
    if (externalUri && (externalFormat === 'txt' || externalFormat === 'epub' || externalFormat === 'mobi')) {
      AppStorage.setOrCreate('pendingLocalBookImportUri', externalUri);
      AppStorage.setOrCreate('pendingLocalBookImportFormat', externalFormat);
      AppStorage.setOrCreate('pendingLocalBookImportName', externalName);
      const nonce = AppStorage.get<number>('pendingLocalBookImportNonce') || 0;
      AppStorage.setOrCreate('pendingLocalBookImportNonce', nonce + 1);
      return 'localBook';
    }
    const params = this.getLaunchParams(want);
    if (params['bookSourceCheckAction'] === 'open') {
      AppStorage.setOrCreate('bookSourceCheckOpenNonce', Date.now());
      return 'bookSource';
    }
    if (params['audioBookAction'] === 'openPanel' && params['bookUrl']) {
      AppStorage.setOrCreate('pendingAudioBookUrl', params['bookUrl']);
      return 'audioBook';
    }
    if (params['cacheAction'] === 'cancelFullTextCache') {
      FullTextCacheCancelCoordinator.request(params['cacheTaskKey'] || '', params['bookUrl'] || '');
      return '';
    }
    const action = params['shortcutAction'];
    if (action === RECENT_READ_SHORTCUT_ACTION) {
      RecentReadShortcut.request();
      return '';
    }
    if (action === OPEN_BOOK_SHORTCUT_ACTION) {
      const bookUrl = params['bookUrl'];
      if (bookUrl) {
        RecentReadShortcut.requestBook(bookUrl);
      }
    }
    return '';
  }

  private externalFileFormat(want: Want, uri: string, fileNameHint: string): string {
    const uriExtension = this.externalFileExtension(uri);
    const nameExtension = this.externalFileExtension(fileNameHint);
    const extension = this.isSupportedExternalExtension(uriExtension) ? uriExtension : nameExtension;
    if (this.isSupportedExternalExtension(extension)) return extension;
    const type = (want.type || '').toLowerCase();
    if (type === 'io.legado.read.qytheme') return 'qytheme';
    if (type === 'application/json' || type === 'text/json' || type === 'application/x-json' ||
      type === 'general.json') return 'json';
    if (type === 'general.epub' || type === 'application/epub+zip' ||
      type === 'application/x-epub+zip') return 'epub';
    if (type === 'com.amazon.mobi' || type === 'application/x-mobipocket-ebook') return 'mobi';
    const sniffed = this.sniffExternalFileFormat(uri);
    if (sniffed) return sniffed;
    if (type === 'general.plain-text' || type === 'text/plain' || type === 'general.text') return 'txt';
    return '';
  }

  private externalFileUri(want: Want): string {
    const directUri = this.externalFileUriFromValue(want.uri);
    if (directUri) return directUri;
    const parameters = want.parameters;
    if (!parameters) return '';
    const preferredKeys = ['ability.params.stream', 'ohos.extra.param.key.stream', 'uri', 'fileUri', 'shareUri'];
    for (const key of preferredKeys) {
      const preferredUri = this.externalFileUriFromValue(parameters[key]);
      if (preferredUri) return preferredUri;
    }
    for (const key of Object.keys(parameters)) {
      const candidate = this.externalFileUriFromValue(parameters[key]);
      if (candidate) return candidate;
    }
    return '';
  }

  private externalFileUriFromValue(value: Object | undefined): string {
    if (typeof value === 'string') {
      const text = value.trim();
      if (this.isExternalFileUri(text)) return text;
      if ((text.startsWith('[') && text.endsWith(']')) || (text.startsWith('{') && text.endsWith('}'))) {
        try {
          return this.externalFileUriFromValue(JSON.parse(text) as Object);
        } catch (_) {
        }
      }
      return '';
    }
    if (Array.isArray(value)) {
      const items = value as Object[];
      for (let i = 0; i < items.length; i++) {
        const item: Object = items[i];
        const candidate = this.externalFileUriFromValue(item);
        if (candidate) return candidate;
      }
      return '';
    }
    if (value && typeof value === 'object') {
      const record = value as Record<string, Object>;
      for (const key of Object.keys(record)) {
        const candidate = this.externalFileUriFromValue(record[key]);
        if (candidate) return candidate;
      }
    }
    return '';
  }

  private isExternalFileUri(value: string): boolean {
    const lower = value.toLowerCase();
    return lower.startsWith('file://') || lower.startsWith('datashare://') ||
      lower.startsWith('content://') || value.startsWith('/');
  }

  private externalFileNameHint(want: Want, uri: string): string {
    const uriExtension = this.externalFileExtension(uri);
    if (this.isSupportedExternalExtension(uriExtension)) return this.externalFileName(uri);
    const parameters = want.parameters;
    if (!parameters) return '';
    const preferredKeys = ['fileName', 'filename', 'displayName', 'name', 'title',
      'ohos.extra.param.key.contentTitle'];
    for (const key of preferredKeys) {
      const hint = this.externalFileNameFromValue(parameters[key]);
      if (hint) return hint;
    }
    for (const key of Object.keys(parameters)) {
      const hint = this.externalFileNameFromValue(parameters[key]);
      if (hint) return hint;
    }
    return '';
  }

  private externalFileNameFromValue(value: Object | undefined): string {
    if (typeof value === 'string') {
      const text = value.trim();
      return this.isSupportedExternalExtension(this.externalFileExtension(text)) ?
        this.externalFileName(text) : '';
    }
    if (Array.isArray(value)) {
      const items = value as Object[];
      for (let i = 0; i < items.length; i++) {
        const item: Object = items[i];
        const hint = this.externalFileNameFromValue(item);
        if (hint) return hint;
      }
    }
    return '';
  }

  private sniffExternalFileFormat(uri: string): string {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(8192);
      const readLength = fs.readSync(file.fd, buffer, { offset: 0, length: buffer.byteLength });
      if (readLength >= 4) {
        const bytes = new Uint8Array(buffer, 0, readLength);
        if (bytes[0] === 0x50 && bytes[1] === 0x4B &&
          ((bytes[2] === 0x03 && bytes[3] === 0x04) || (bytes[2] === 0x05 && bytes[3] === 0x06))) {
          return 'epub';
        }
        // PalmDB 头第 60 字节起是类型与创建者标识。
        if (readLength >= 68 && util.TextDecoder.create('utf-8').decodeWithStream(bytes.subarray(60, 68),
          { stream: false }) === 'BOOKMOBI') {
          return 'mobi';
        }
        const text = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false })
          .replace(/^\uFEFF/, '').trim();
        if (text.startsWith('{') || text.startsWith('[')) return 'json';
        return 'txt';
      }
    } catch (e) {
      hilog.warn(0x0000, 'testTag', 'Sniff external file failed: %{public}s', JSON.stringify(e));
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
    return '';
  }

  private isSupportedExternalExtension(extension: string): boolean {
    return extension === 'json' || extension === 'txt' || extension === 'epub' || extension === 'mobi' ||
      extension === 'qytheme';
  }

  private externalFileName(uriOrName: string): string {
    const clean = uriOrName.split('?')[0].split('#')[0];
    let decoded = clean;
    try {
      decoded = decodeURIComponent(clean);
    } catch (_) {
    }
    return decoded.substring(Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\')) + 1);
  }

  private externalFileExtension(uri: string): string {
    const cleanUri = uri.split('?')[0].split('#')[0];
    let decoded = cleanUri;
    try {
      decoded = decodeURIComponent(cleanUri);
    } catch (_) {
    }
    const fileName = decoded.substring(decoded.lastIndexOf('/') + 1).toLowerCase();
    const dot = fileName.lastIndexOf('.');
    return dot >= 0 ? fileName.substring(dot + 1) : '';
  }

  private wantParameterKeys(want: Want): string {
    return want.parameters ? Object.keys(want.parameters).join(',') : '';
  }

  private routeMatches(name: string, path: string, targetUrl: string): boolean {
    const targetName = targetUrl.substring(targetUrl.lastIndexOf('/') + 1);
    return name === targetName || path === targetUrl || path.endsWith(`/${targetName}`);
  }

  private getLaunchParams(want: Want): Record<string, string> {
    const result: Record<string, string> = {};
    const parameters = want.parameters;
    if (!parameters) {
      return result;
    }

    const shortcutAction = parameters['shortcutAction'];
    if (typeof shortcutAction === 'string') {
      result['shortcutAction'] = shortcutAction;
    }
    const bookUrl = parameters['bookUrl'];
    if (typeof bookUrl === 'string') {
      result['bookUrl'] = bookUrl;
    }
    const cacheAction = parameters['cacheAction'];
    if (typeof cacheAction === 'string') {
      result['cacheAction'] = cacheAction;
    }
    const cacheTaskKey = parameters['cacheTaskKey'];
    if (typeof cacheTaskKey === 'string') {
      result['cacheTaskKey'] = cacheTaskKey;
    }
    const bookSourceCheckAction = parameters['bookSourceCheckAction'];
    if (typeof bookSourceCheckAction === 'string') {
      result['bookSourceCheckAction'] = bookSourceCheckAction;
    }
    const audioBookAction = parameters['audioBookAction'];
    if (typeof audioBookAction === 'string') {
      result['audioBookAction'] = audioBookAction;
    }

    const cardParams = parameters['params'];
    if (typeof cardParams === 'string') {
      try {
        const parsed = JSON.parse(cardParams) as Record<string, Object>;
        const parsedAction = parsed['shortcutAction'];
        if (typeof parsedAction === 'string') {
          result['shortcutAction'] = parsedAction;
        }
        const parsedBookUrl = parsed['bookUrl'];
        if (typeof parsedBookUrl === 'string') {
          result['bookUrl'] = parsedBookUrl;
        }
        const parsedCacheAction = parsed['cacheAction'];
        if (typeof parsedCacheAction === 'string') {
          result['cacheAction'] = parsedCacheAction;
        }
        const parsedCacheTaskKey = parsed['cacheTaskKey'];
        if (typeof parsedCacheTaskKey === 'string') {
          result['cacheTaskKey'] = parsedCacheTaskKey;
        }
        const parsedBookSourceCheckAction = parsed['bookSourceCheckAction'];
        if (typeof parsedBookSourceCheckAction === 'string') {
          result['bookSourceCheckAction'] = parsedBookSourceCheckAction;
        }
      } catch (e) {
        hilog.warn(0x0000, 'testTag', 'Parse card params failed: %{public}s', JSON.stringify(e));
      }
    }
    return result;
  }

  private syncStartupWindow(windowStage: window.WindowStage): void {
    setTimeout(() => {
      windowStage.getMainWindow().then((mainWindow) => {
        const darkMode = AppStorage.get<boolean>('appDarkMode') || false;
        const bg = ThemeRuntime.pageColor(darkMode);
        mainWindow.setWindowBackgroundColor(bg);
        mainWindow.setWindowLayoutFullScreen(true);
        mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          isStatusBarLightIcon: darkMode,
          statusBarContentColor: ThemeRuntime.primaryTextColor(darkMode),
          navigationBarColor: bg,
          isNavigationBarLightIcon: darkMode,
          navigationBarContentColor: ThemeRuntime.primaryTextColor(darkMode)
        });
      }).catch((err: Error) => {
        hilog.warn(0x0000, 'testTag', 'Startup window sync failed: %{public}s', JSON.stringify(err));
      });
    }, 0);
  }

}
