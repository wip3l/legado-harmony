import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    AppStorage.setOrCreate('startupT0', Date.now());
    hilog.info(0x0000, 'testTag', 'StartupTrace onCreate %{public}d', Date.now());
    this.syncSystemColorMode(this.context.config);
    if (AppStorage.get<number>('readerPageTurnMode') === undefined) {
      AppStorage.setOrCreate('readerPageTurnMode', 1);
    }
    if (AppStorage.get<number>('statusBarHeight') === undefined) {
      AppStorage.setOrCreate('statusBarHeight', 32);
    }
    if (AppStorage.get<number>('navBarHeight') === undefined) {
      AppStorage.setOrCreate('navBarHeight', 0);
    }
    PersistentStorage.persistProp('bookshelfSortMode', 'recentRead');
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
