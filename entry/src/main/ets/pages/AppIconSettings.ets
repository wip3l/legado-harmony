import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { syncSystemBars } from '../utils/SystemBars';
import { AppIconManager, AppIconOption } from '../utils/AppIconManager';
import { AppIconSettings, AppIconSettingsStore } from '../utils/AppIconSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';

@Entry
@Component
struct AppIconSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appIconId') appIconId: string = AppIconSettingsStore.DEFAULT_ICON_ID;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State configuredIconIds: string[] = [];
  @State loadedDynamicIcons: boolean = false;
  @State applyingIconId: string = '';

  aboutToAppear(): void {
    this.syncBars();
    AppIconSettingsStore.load(getContext(this)).then((settings: AppIconSettings) => {
      AppIconSettingsStore.applyToStorage(settings);
    }).catch(() => {
      AppStorage.setOrCreate(AppIconSettingsStore.KEY_ICON_ID, AppIconSettingsStore.DEFAULT_ICON_ID);
    });
    this.refreshDynamicIcons();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          Text('选择桌面图标')
            .fontSize(13)
            .fontColor(this.subTextColor())
            .width('100%')
            .padding({ left: 16, right: 16, top: 20, bottom: 8 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(AppIconManager.OPTIONS, (option: AppIconOption) => {
              this.iconCard(option)
            }, (option: AppIconOption) => option.id)
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  optionBorderColor(selected: boolean): string {
    if (selected) {
      return ThemeRuntime.accentColor(this.appDarkMode);
    }
    return ThemeRuntime.dividerColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  refreshDynamicIcons(): void {
    AppIconManager.queryConfiguredIconIds().then((ids: string[]) => {
      this.configuredIconIds = ids;
      this.loadedDynamicIcons = true;
    }).catch(() => {
      this.configuredIconIds = [];
      this.loadedDynamicIcons = false;
    });
  }

  isConfigured(option: AppIconOption): boolean {
    if (!option.dynamicIconId) {
      return true;
    }
    return this.configuredIconIds.includes(option.dynamicIconId);
  }

  async selectIcon(option: AppIconOption): Promise<void> {
    if (this.applyingIconId) {
      return;
    }
    if (this.appIconId === option.id) {
      this.showToastSafely(`当前已是${option.title}`);
      return;
    }
    this.applyingIconId = option.id;
    try {
      await AppIconManager.applyIcon(option);
      const settings = new AppIconSettings();
      settings.iconId = option.id;
      AppIconSettingsStore.applyToStorage(settings);
      await AppIconSettingsStore.save(getContext(this), settings);
      this.showToastSafely(`已切换为${option.title}`);
    } catch (e) {
      hilog.warn(0x0000, 'appIcon', 'Switch app icon failed option=%{public}s err=%{public}s',
        option.id, JSON.stringify(e));
      this.showToastSafely(this.switchErrorMessage(e));
      this.refreshDynamicIcons();
    } finally {
      this.applyingIconId = '';
    }
  }

  showToastSafely(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (e) {
      hilog.warn(0x0000, 'appIcon', 'Show app icon toast failed err=%{public}s', JSON.stringify(e));
    }
  }

  backSafely(): void {
    try {
      router.back();
    } catch (e) {
      hilog.warn(0x0000, 'appIcon', 'Back from app icon settings failed err=%{public}s', JSON.stringify(e));
    }
  }

  @Builder
  titleBar() {
    Row() {
      Text('<')
        .fontSize(24)
        .fontColor(this.primaryTextColor())
        .width(40)
        .height(56)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.backSafely();
        })
      Text('图标设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  iconCard(option: AppIconOption) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(option.preview)
          .width(72)
          .height(72)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
        if (this.appIconId === option.id) {
          Text('✓')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
            .width(22)
            .height(22)
            .textAlign(TextAlign.Center)
            .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode))
            .borderRadius(11)
            .margin({ top: -4, right: -4 })
        }
      }
      .width(82)
      .height(82)
      .alignContent(Alignment.Center)

      Text(option.title)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })

      Text(option.desc)
        .fontSize(11)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 3 })

      if (this.loadedDynamicIcons && !this.isConfigured(option)) {
        Text('未生效')
          .fontSize(10)
          .fontColor('#B46A00')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor('#FFF2D6')
          .borderRadius(8)
          .margin({ top: 8 })
      } else if (this.applyingIconId === option.id) {
        Text('切换中')
          .fontSize(10)
          .fontColor(this.subTextColor())
          .margin({ top: 8 })
      }
    }
    .width('48%')
    .height(166)
    .padding({ top: 14, left: 10, right: 10, bottom: 12 })
    .margin({ bottom: 12 })
    .backgroundColor(this.cardColor())
    .borderRadius(8)
    .border({ width: 1, color: this.optionBorderColor(this.appIconId === option.id) })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.selectIcon(option);
    })
  }

  switchErrorMessage(error: Object): string {
    const code = this.errorCode(error);
    if (!code) {
      return '桌面图标切换失败，请检查图标管理服务、审核状态和图标 ID';
    }
    return `桌面图标切换失败(${code})，请检查图标管理服务、审核状态和图标 ID`;
  }

  errorCode(error: Object): string {
    if (!error) {
      return '';
    }
    const source = error as Record<string, Object>;
    const code = source['code'];
    if (code === undefined || code === null) {
      return '';
    }
    return `${code}`;
  }
}
