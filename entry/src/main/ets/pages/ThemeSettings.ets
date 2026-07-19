import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderThemeHelper } from '../utils/ReaderThemeHelper';
import { syncSystemBars } from '../utils/SystemBars';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemeIds, ThemePack, ThemeVariant } from '../theme/ThemeModels';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import fs from '@ohos.file.fs';

@Entry
@Component
struct ThemeSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appThemeId') appThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appCustomBaseThemeId') customBaseThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appCustomLightAccentColor') customLightAccentColor: string = '#007DFF';
  @StorageLink('appCustomDarkAccentColor') customDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appCustomLightButtonColor') customLightButtonColor: string = '#007DFF';
  @StorageLink('appCustomDarkButtonColor') customDarkButtonColor: string = '#3F8CFF';
  @StorageLink('appCustomLightReaderBackgroundColor') customLightReaderBackgroundColor: string = '#F7F1E3';
  @StorageLink('appCustomLightReaderTextColor') customLightReaderTextColor: string = '#2F261D';
  @StorageLink('appCustomLightReaderSubTextColor') customLightReaderSubTextColor: string = '#7A6F63';
  @StorageLink('appCustomLightReaderBackgroundAssetId') customLightReaderBackgroundAssetId: string = '';
  @StorageLink('appCustomLightReaderBackgroundImageFit') customLightReaderBackgroundImageFit: string = 'cover';
  @StorageLink('appCustomLightReaderContentTone') customLightReaderContentTone: string = 'light';
  @StorageLink('appCustomDarkReaderBackgroundColor') customDarkReaderBackgroundColor: string = '#1F2329';
  @StorageLink('appCustomDarkReaderTextColor') customDarkReaderTextColor: string = '#D8D8D8';
  @StorageLink('appCustomDarkReaderSubTextColor') customDarkReaderSubTextColor: string = '#9AA0A6';
  @StorageLink('appCustomDarkReaderBackgroundAssetId') customDarkReaderBackgroundAssetId: string = '';
  @StorageLink('appCustomDarkReaderBackgroundImageFit') customDarkReaderBackgroundImageFit: string = 'cover';
  @StorageLink('appCustomDarkReaderContentTone') customDarkReaderContentTone: string = 'dark';
  @StorageLink('readerLightThemeIndex') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') readerDarkThemeIndex: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State applyingThemeId: string = '';

  aboutToAppear(): void {
    this.loadThemeSettings();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column({ space: 12 }) {
          this.currentThemeSummary()
          this.sectionTitle('自定义主题')
          this.themeCard(this.customTheme())
          this.sectionTitle('内置主题')
          ForEach(BuiltinThemeRegistry.all(), (theme: ThemePack) => {
            this.themeCard(theme)
          }, (theme: ThemePack) => theme.id)
          this.followThemeHint()
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 32 })
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%').justifyContent(FlexAlign.Start)
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  async loadThemeSettings(): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      AppThemeSettingsStore.applyToStorage(settings);
      this.appThemeId = settings.themeId;
      const readerSettings = await ReaderSettingsStore.load(getContext(this));
      ReaderSettingsStore.applyToStorage(readerSettings);
    } catch (e) {
      console.warn('加载主题设置失败:', e);
    }
  }

  async selectTheme(themeId: string): Promise<void> {
    if (this.applyingThemeId || themeId === this.appThemeId) {
      return;
    }
    this.applyingThemeId = themeId;
    try {
      const previous: AppThemeSettings = await AppThemeSettingsStore.load(getContext(this));
      const settings: AppThemeSettings = AppThemeSettingsStore.activateTheme(themeId, previous);
      AppThemeSettingsStore.applyToStorage(settings);
      await AppThemeSettingsStore.save(getContext(this), settings);
      this.appThemeId = settings.themeId;
      const readerSettings = await ReaderSettingsStore.switchThemeProfile(
        getContext(this), previous.themeId, settings.themeId);
      this.readerLightThemeIndex = readerSettings.lightThemeIndex;
      this.readerDarkThemeIndex = readerSettings.darkThemeIndex;
      await this.applyThemeFontWhenAvailable();
      this.refreshRecentReadCard();
      this.syncBars();
      promptAction.showToast({ message: `已应用「${BuiltinThemeRegistry.findById(themeId).name}」主题` });
    } catch (e) {
      console.error('应用主题失败:', e);
      promptAction.showToast({ message: '应用主题失败，请稍后重试' });
    } finally {
      this.applyingThemeId = '';
    }
  }

  async useAppReaderTheme(): Promise<void> {
    const settings: ReaderSettings = await ReaderSettingsStore.load(getContext(this));
    this.readerLightThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
    this.readerDarkThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
    await ReaderSettingsStore.saveThemeSettings(
      getContext(this),
      this.readerLightThemeIndex,
      this.readerDarkThemeIndex,
      settings.lightCustomThemeBackgroundColor,
      settings.lightCustomThemeTextColor,
      settings.darkCustomThemeBackgroundColor,
      settings.darkCustomThemeTextColor,
      this.appDarkMode
    );
  }

  async enableAppReaderTheme(): Promise<void> {
    try {
      await this.useAppReaderTheme();
      promptAction.showToast({ message: '阅读背景已改为跟随应用主题' });
    } catch (e) {
      console.error('启用应用阅读主题失败:', e);
      promptAction.showToast({ message: '设置阅读主题失败' });
    }
  }

  readerFollowsAppTheme(): boolean {
    return this.readerLightThemeIndex === ReaderThemeHelper.APP_THEME_INDEX &&
      this.readerDarkThemeIndex === ReaderThemeHelper.APP_THEME_INDEX;
  }

  async applyThemeFontWhenAvailable(): Promise<void> {
    const settings: ReaderSettings = await ReaderSettingsStore.load(getContext(this));
    if (settings.fontFilePath && this.fontFileExists(settings.fontFilePath)) {
      return;
    }
    try {
      getContext(this).getApplicationContext().setFont(ThemeRuntime.fontFamily());
    } catch (e) {
      console.warn('应用主题默认字体失败:', e);
    }
  }

  fontFileExists(filePath: string): boolean {
    if (!filePath) {
      return false;
    }
    try {
      return fs.accessSync(filePath);
    } catch (e) {
      return false;
    }
  }

  refreshRecentReadCard(): void {
    const context = getContext(this) as common.UIAbilityContext;
    RecentReadCardUpdater.reload(context).catch((e: Error) => {
      console.warn('主题切换后刷新最近阅读卡片失败:', e);
    });
  }

  activeTheme(): ThemePack {
    if (this.appThemeId === ThemeIds.CUSTOM) {
      return this.customTheme();
    }
    return BuiltinThemeRegistry.findById(this.appThemeId);
  }

  customTheme(): ThemePack {
    const theme = BuiltinThemeRegistry.customTheme(this.customBaseThemeId);
    theme.light.colors.accentColor = this.customLightAccentColor;
    theme.dark.colors.accentColor = this.customDarkAccentColor;
    theme.light.colors.buttonColor = this.customLightButtonColor;
    theme.dark.colors.buttonColor = this.customDarkButtonColor;
    theme.light.reader.backgroundColor = this.customLightReaderBackgroundColor;
    theme.light.reader.textColor = this.customLightReaderTextColor;
    theme.light.reader.subTextColor = this.customLightReaderSubTextColor;
    theme.light.reader.backgroundAssetId = this.customLightReaderBackgroundAssetId;
    theme.light.reader.backgroundImageFit = this.customLightReaderBackgroundImageFit;
    theme.light.reader.contentTone = this.customLightReaderContentTone;
    theme.dark.reader.backgroundColor = this.customDarkReaderBackgroundColor;
    theme.dark.reader.textColor = this.customDarkReaderTextColor;
    theme.dark.reader.subTextColor = this.customDarkReaderSubTextColor;
    theme.dark.reader.backgroundAssetId = this.customDarkReaderBackgroundAssetId;
    theme.dark.reader.backgroundImageFit = this.customDarkReaderBackgroundImageFit;
    theme.dark.reader.contentTone = this.customDarkReaderContentTone;
    return theme;
  }

  activeVariant(theme: ThemePack): ThemeVariant {
    return this.appDarkMode ? theme.dark : theme.light;
  }

  isSelected(theme: ThemePack): boolean {
    return theme.id === this.appThemeId;
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

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('主题与外观')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ right: 12 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  currentThemeSummary() {
    Row({ space: 12 }) {
      Image(ThemeAssetRegistry.themeLogo(this.activeTheme().id))
        .width(52)
        .height(52)
        .borderRadius(16)
        .objectFit(ImageFit.Contain)

      Text(this.activeTheme().name)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .alignItems(VerticalAlign.Center)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 2, top: 6, bottom: 0 })
  }

  @Builder
  themeCard(theme: ThemePack) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(theme.name)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontFamily(theme.typography.appFontFamily)
            .fontColor(this.activeVariant(theme).colors.primaryTextColor)
          Text(theme.description)
            .fontSize(12)
            .fontColor(this.activeVariant(theme).colors.subTextColor)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.isSelected(theme)) {
          Text('已启用')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(this.activeVariant(theme).colors.accentColor)
        } else if (this.applyingThemeId === theme.id) {
          Text('应用中')
            .fontSize(12)
            .fontColor(this.activeVariant(theme).colors.accentColor)
        }
      }
      .width('100%')

      this.themeVisualPreview(theme)
      if (theme.id === ThemeIds.CUSTOM) {
        Row() {
          Text('已保存配色与阅读背景')
            .fontSize(11)
            .fontColor(this.activeVariant(theme).colors.subTextColor)
            .layoutWeight(1)
          Button('编辑主题')
            .height(32)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .backgroundColor(this.activeVariant(theme).colors.buttonColor)
            .onClick(() => {
              router.pushUrl({ url: 'pages/ThemeColorSettings' });
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(theme.radius.card)
    .backgroundColor(this.activeVariant(theme).colors.cardColor)
    .border({
      width: this.isSelected(theme) ? 2 : 1,
      color: this.isSelected(theme) ? this.activeVariant(theme).colors.accentColor :
        this.activeVariant(theme).colors.dividerColor
    })
    .onClick(() => {
      this.selectTheme(theme.id);
    })
  }

  @Builder
  themeVisualPreview(theme: ThemePack) {
    Row({ space: 10 }) {
      Stack() {
        if (this.activeVariant(theme).reader.backgroundAssetId) {
          Image(ThemeAssetRegistry.readerBackground(this.activeVariant(theme).reader.backgroundAssetId))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
        Text('阅读')
          .fontSize(13)
          .fontFamily(theme.typography.appFontFamily)
          .fontColor(this.activeVariant(theme).reader.textColor)
      }
      .width(76)
      .height(58)
      .borderRadius(theme.radius.medium)
      .backgroundColor(this.activeVariant(theme).reader.backgroundColor)

      Column({ space: 7 }) {
        Row({ space: 6 }) {
          Blank()
            .height(8)
            .layoutWeight(1)
            .borderRadius(4)
            .backgroundColor(this.activeVariant(theme).colors.primaryTextColor)
          Blank()
            .width(32)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.activeVariant(theme).colors.subTextColor)
        }
        Text('强调气泡')
          .fontSize(12)
          .fontColor(this.activeVariant(theme).regexEmphasis.emphasisTextColor)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(theme.radius.bubble)
          .backgroundColor(this.activeVariant(theme).regexEmphasis.emphasisColor)
        Row({ space: 5 }) {
          ForEach(['bookshelf', 'explore', 'search', 'mine'], (tabId: string) => {
            Image(ThemeAssetRegistry.navigationIcon(theme.navigation.iconPackId, tabId))
              .width(16)
              .height(16)
              .fillColor(this.activeVariant(theme).colors.accentColor)
          }, (tabId: string) => `${theme.id}_${tabId}`)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(10)
    .borderRadius(theme.radius.medium)
    .backgroundColor(this.activeVariant(theme).colors.inputColor)
  }

  @Builder
  followThemeHint() {
    Column({ space: 8 }) {
      Row() {
        Text(this.readerFollowsAppTheme() ? '阅读设置正在跟随应用主题' : '阅读设置正在使用独立配色')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        if (!this.readerFollowsAppTheme()) {
          Button('改为跟随')
            .height(32)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .backgroundColor(this.accentColor())
            .onClick(() => {
              this.enableAppReaderTheme();
            })
        }
      }
      .width('100%')
      Text('你仍可在阅读设置中单独选择米黄、素白、青绿或自定义配色。')
        .fontSize(12)
        .fontColor(this.subTextColor())
    }
    .width('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

}
