import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { RecentReadShortcut, RECENT_READ_SHORTCUT_ACTION, OPEN_BOOK_SHORTCUT_ACTION } from '../utils/RecentReadShortcut';
import { CoverGalleryStore } from '../utils/CoverGalleryStore';
import { BookshelfDisplaySettingsStore } from '../utils/BookshelfDisplaySettingsStore';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    AppStorage.setOrCreate('startupT0', Date.now());
    hilog.info(0x0000, 'testTag', 'StartupTrace onCreate %{public}d', Date.now());
    this.syncSystemColorMode(this.context.config);
    PersistentStorage.persistProp('readerPageTurnMode', 1);
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
    PersistentStorage.persistProp('ttsOfflineSdkModeMigrated', false);
    if (!AppStorage.get<boolean>('ttsOfflineSdkModeMigrated')) {
      if (AppStorage.get<number>('ttsOnline') === 0) {
        AppStorage.setOrCreate('ttsOnline', 1);
      }
      AppStorage.setOrCreate('ttsOfflineSdkModeMigrated', true);
    }
    PersistentStorage.persistProp('readerFontFamily', '');
    PersistentStorage.persistProp('readerFontFilePath', '');
    PersistentStorage.persistProp('readerFontSourceName', '系统默认');
    PersistentStorage.persistProp('readerFontMode', 'system');
    PersistentStorage.persistProp('readerSystemFontFamily', '');
    PersistentStorage.persistProp('readerCustomFontsRaw', '');
    PersistentStorage.persistProp('readerPageTurnAnimation', true);
    PersistentStorage.persistProp('bookshelfShowTags', true);
    PersistentStorage.persistProp('bookshelfShowIntro', true);
    PersistentStorage.persistProp('bookshelfShowFullIntro', false);
    PersistentStorage.persistProp('bookshelfCoverAlbums', '');
    PersistentStorage.persistProp('bookshelfLightCoverAlbumId', '');
    PersistentStorage.persistProp('bookshelfDarkCoverAlbumId', '');
    PersistentStorage.persistProp('bookshelfCoverApplyScope', 'all');
    PersistentStorage.persistProp('bookshelfCoverTargetBooks', '');
    PersistentStorage.persistProp('bookshelfIgnoreSourceCover', false);
    PersistentStorage.persistProp('bookshelfCoverMode', 'sequence');
    PersistentStorage.persistProp('searchExploreShowResultCover', true);
    PersistentStorage.persistProp('searchExploreShowResultTags', true);
    PersistentStorage.persistProp('searchExplorePromptAddToShelfOnBack', true);
    PersistentStorage.persistProp('searchExploreExactSearch', false);
    PersistentStorage.persistProp('searchExploreShowSearchProgress', true);
    PersistentStorage.persistProp('searchExploreSelectedSourceGroups', '');
    PersistentStorage.persistProp('appLightAccentColor', '#007DFF');
    PersistentStorage.persistProp('appDarkAccentColor', '#4E9BFF');
    PersistentStorage.persistProp('appLightButtonColor', '#007DFF');
    PersistentStorage.persistProp('appDarkButtonColor', '#3F8CFF');
    PersistentStorage.persistProp('explorePlatform', '番茄');
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
    ReaderSettingsStore.load(this.context).then((settings) => {
      ReaderSettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync reader settings failed: %{public}s', JSON.stringify(e));
    });
    AppThemeSettingsStore.load(this.context).then((settings) => {
      AppThemeSettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync app theme settings failed: %{public}s', JSON.stringify(e));
    });
    this.handleLaunchWant(want);
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    hilog.info(0x0000, 'testTag', 'StartupTrace onWindowStageCreate %{public}d', Date.now());

    windowStage.loadContent('pages/Startup', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'testTag', 'StartupTrace Startup content loaded %{public}d', Date.now());
      this.syncStartupWindow(windowStage);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
    this.syncSystemColorMode(this.context.config);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', 'Ability onNewWant %{public}s', JSON.stringify(launchParam));
    this.handleLaunchWant(want);
  }

  onBackground(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.syncSystemColorMode(newConfig);
  }

  private syncSystemColorMode(config: Configuration): void {
    const mode = AppStorage.get<string>('appThemeMode') || 'system';
    if (mode === 'system') {
      AppStorage.setOrCreate('appDarkMode', config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    }
  }

  private handleLaunchWant(want: Want): void {
    const params = this.getLaunchParams(want);
    const action = params['shortcutAction'];
    if (action === RECENT_READ_SHORTCUT_ACTION) {
      RecentReadShortcut.request();
      return;
    }
    if (action === OPEN_BOOK_SHORTCUT_ACTION) {
      const bookUrl = params['bookUrl'];
      if (bookUrl) {
        RecentReadShortcut.requestBook(bookUrl);
      }
    }
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
        const bg = darkMode ? '#101113' : '#F5F5F5';
        mainWindow.setWindowBackgroundColor(bg);
        mainWindow.setWindowLayoutFullScreen(true);
        mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          isStatusBarLightIcon: darkMode,
          statusBarContentColor: darkMode ? '#FFFFFF' : '#1F1F1F',
          navigationBarColor: bg,
          isNavigationBarLightIcon: darkMode,
          navigationBarContentColor: darkMode ? '#FFFFFF' : '#1F1F1F'
        });
      }).catch((err: Error) => {
        hilog.warn(0x0000, 'testTag', 'Startup window sync failed: %{public}s', JSON.stringify(err));
      });
    }, 0);
  }
}
