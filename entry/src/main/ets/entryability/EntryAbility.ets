import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { appDb } from '../model/data/AppDatabase';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    this.syncSystemColorMode(this.context.config);
    if (AppStorage.get<number>('readerPageTurnMode') === undefined) {
      AppStorage.setOrCreate('readerPageTurnMode', 1);
    }
    appDb.init(this.context).then(() => {
      hilog.info(0x0000, 'testTag', '数据库初始化成功');
    }).catch((err: Error) => {
      hilog.error(0x0000, 'testTag', '数据库初始化失败: %{public}s', err.message);
    });
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.getMainWindow().then((mainWindow) => {
      // 启用系统导航条以获得悬浮指示器效果
      mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'testTag', 'Content loaded successfully');
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
}
