import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { ColorCodePicker } from '../components/ColorCodePicker';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeIds } from '../theme/ThemeModels';

@Component
struct ThemeColorOption {
  @Link color: string;
  @Prop title: string = '';
  @Prop appDarkMode: boolean = false;
  @Prop cardColor: string = '#FFFFFF';
  @Prop primaryTextColor: string = '#1F1F1F';
  @Prop accentColor: string = '#007DFF';
  onColorChange: (color: string) => void = (_color: string): void => {};

  build() {
    Stack() {
      Row() {
        Text(this.title)
          .fontSize(16)
          .fontColor(this.primaryTextColor)
          .layoutWeight(1)
        Row()
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(this.color)
          .border({ width: 2, color: this.appDarkMode ? '#55FFFFFF' : '#22000000' })
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.cardColor)
      .alignItems(VerticalAlign.Center)

      ColorCodePicker({
        value: this.color,
        placeholder: this.color,
        appDarkMode: this.appDarkMode,
        accentColor: this.accentColor,
        optionTitle: this.title,
        hideOptionTrigger: true,
        onColorChange: (color: string) => {
          this.color = color;
          this.onColorChange(color);
        }
      })
    }
    .width('100%')
    .margin({ top: 1 })
  }
}

@Entry
@Component
struct ThemeColorSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appCustomLightAccentColor') lightAccentColor: string = '#007DFF';
  @StorageLink('appCustomDarkAccentColor') darkAccentColor: string = '#4E9BFF';
  @StorageLink('appCustomLightButtonColor') lightButtonColor: string = '#007DFF';
  @StorageLink('appCustomDarkButtonColor') darkButtonColor: string = '#3F8CFF';
  @StorageLink('appCustomBaseThemeId') customBaseThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State selectedMode: string = 'light';

  aboutToAppear(): void {
    this.reloadSettings();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadSettings();
    this.syncBars();
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('修改任一颜色后会自动启用自定义主题')
          this.modeOptions()
          this.colorOptions()
          this.previewPanel()
        }
        .width('100%')
        .padding({ bottom: 32 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  async reloadSettings(): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      AppThemeSettingsStore.applyToStorage(settings);
      this.customBaseThemeId = settings.customBaseThemeId;
      this.lightAccentColor = settings.customLightAccentColor;
      this.darkAccentColor = settings.customDarkAccentColor;
      this.lightButtonColor = settings.customLightButtonColor;
      this.darkButtonColor = settings.customDarkButtonColor;
    } catch (e) {
      console.warn('读取主题色设置失败:', e);
    }
  }

  async onSettingChanged(): Promise<void> {
    try {
      const settings: AppThemeSettings = await AppThemeSettingsStore.load(getContext(this));
      settings.themeId = ThemeIds.CUSTOM;
      settings.customBaseThemeId = this.customBaseThemeId;
      settings.lightAccentColor = this.lightAccentColor;
      settings.darkAccentColor = this.darkAccentColor;
      settings.lightButtonColor = this.lightButtonColor;
      settings.darkButtonColor = this.darkButtonColor;
      settings.customLightAccentColor = this.lightAccentColor;
      settings.customDarkAccentColor = this.darkAccentColor;
      settings.customLightButtonColor = this.lightButtonColor;
      settings.customDarkButtonColor = this.darkButtonColor;
      AppThemeSettingsStore.applyToStorage(settings);
      await AppThemeSettingsStore.save(getContext(this), settings);
    } catch (e) {
      console.warn('保存主题色设置失败:', e);
    }
  }

  setCurrentAccentColor(color: string): void {
    const normalized = AppThemeSettingsStore.normalizeColor(color, this.currentAccentColor());
    if (this.selectedMode === 'dark') {
      this.darkAccentColor = normalized;
    } else {
      this.lightAccentColor = normalized;
    }
    this.onSettingChanged();
  }

  setCurrentButtonColor(color: string): void {
    const normalized = AppThemeSettingsStore.normalizeColor(color, this.currentButtonColor());
    if (this.selectedMode === 'dark') {
      this.darkButtonColor = normalized;
    } else {
      this.lightButtonColor = normalized;
    }
    this.onSettingChanged();
  }

  currentAccentColor(): string {
    return this.selectedMode === 'dark' ? this.darkAccentColor : this.lightAccentColor;
  }

  currentButtonColor(): string {
    return this.selectedMode === 'dark' ? this.darkButtonColor : this.lightButtonColor;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
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
          router.back();
        })
      Text('自定义主题')
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
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }

  @Builder
  modeOptions() {
    Row({ space: 8 }) {
      this.modeButton('浅色模式', 'light')
      this.modeButton('深色模式', 'dark')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  modeButton(title: string, mode: string) {
    Stack({ alignContent: Alignment.Center }) {
      Text(title)
        .fontSize(14)
        .fontColor(this.selectedMode === mode ? '#FFFFFF' : this.primaryTextColor())
    }
      .layoutWeight(1)
      .height(38)
      .borderRadius(19)
      .backgroundColor(this.selectedMode === mode ? this.currentAccentColor() : this.inputColor())
      .onClick(() => {
        this.selectedMode = mode;
      })
  }

  @Builder
  colorOptions() {
    if (this.selectedMode === 'dark') {
      ThemeColorOption({
        title: '按钮色',
        color: $darkButtonColor,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: this.darkAccentColor,
        onColorChange: (color: string) => {
          this.setCurrentButtonColor(color);
        }
      })
      ThemeColorOption({
        title: '强调色',
        color: $darkAccentColor,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: this.darkAccentColor,
        onColorChange: (color: string) => {
          this.setCurrentAccentColor(color);
        }
      })
    } else {
      ThemeColorOption({
        title: '按钮色',
        color: $lightButtonColor,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: this.lightAccentColor,
        onColorChange: (color: string) => {
          this.setCurrentButtonColor(color);
        }
      })
      ThemeColorOption({
        title: '强调色',
        color: $lightAccentColor,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: this.lightAccentColor,
        onColorChange: (color: string) => {
          this.setCurrentAccentColor(color);
        }
      })
    }
  }

  @Builder
  previewPanel() {
    Column() {
      Text(`${this.selectedMode === 'dark' ? '深色' : '浅色'}模式预览`)
        .fontSize(13)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ bottom: 12 })

      Row({ space: 12 }) {
        Button('主要按钮')
          .height(40)
          .layoutWeight(1)
          .fontColor('#FFFFFF')
          .backgroundColor(this.currentButtonColor())
        Text('强调文字')
          .fontSize(15)
          .fontColor(this.currentAccentColor())
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(this.cardColor())
    .margin({ top: 12 })
  }

}
