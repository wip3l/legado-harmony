import { ReaderTypographyField } from '../components/reader/ReaderLayoutSettings';
import { ReaderFontWeight } from '../core/reader/ReaderFontWeight';
import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderThemeHelper, ReaderThemeItem } from '../utils/ReaderThemeHelper';
import { ReaderCustomThemeData, ReaderCustomThemeHelper, ReaderCustomThemeScheme } from '../utils/ReaderCustomThemeHelper';
import { ReaderBackgroundImageStore } from '../utils/ReaderBackgroundImageStore';
import { AppThemeModeStore } from '../utils/AppThemeModeStore';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ReaderHeaderFooterSettings } from '../components/reader/ReaderLayoutSettings';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { AdaptiveColorPicker } from '../components/AdaptiveColorPicker';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { EyeTurnController } from '../core/reader/EyeTurnController';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import fs from '@ohos.file.fs';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { TapZoneSettingsDialogContent } from '../components/TapZoneSettingsDialog';
import { HexColor } from '../utils/HexColor';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { CloudAutoSync, CloudRemoteFont } from '../account/CloudAutoSync';
import { CloudFontMenu } from '../account/CloudFontMenu';
class ReaderCustomFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class ReaderCustomFontData {
  fonts: ReaderCustomFontItem[] = [];
}

@Entry
@Component
struct SettingsPage {
  @StorageLink('appThemeMode') appThemeMode: string = 'system';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('readerFontWeight') readerFontWeight: number = 400;
  @StorageLink('readerFontSize') readerFontSize: number = 20;
  @StorageLink('readerLetterSpacing') readerLetterSpacing: number = 0;
  @StorageLink('readerTextAlign') readerTextAlign: string = 'justify';
  @StorageLink('readerLineHeight') readerLineHeight: number = 12;
  @StorageLink('readerParagraphSpacing') readerParagraphSpacing: number = 0;
  @StorageLink('readerMarginLeft') readerMarginLeft: number = 18;
  @StorageLink('readerMarginRight') readerMarginRight: number = 18;
  @StorageLink('readerMarginTop') readerMarginTop: number = 18;
  @StorageLink('readerMarginBottom') readerMarginBottom: number = 18;
  @State typographySettingIndex: number = 0;
  @State showTypographyValueInput: boolean = false;
  @State typographyValueDraft: string = '';
  @StorageLink('readerLightThemeIndex') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') readerDarkThemeIndex: number = 0;
  @StorageLink('readerLightCustomThemeBackgroundColor') readerLightCustomThemeBackgroundColor: string = ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerLightCustomThemeTextColor') readerLightCustomThemeTextColor: string = ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR;
  @StorageLink('readerDarkCustomThemeBackgroundColor') readerDarkCustomThemeBackgroundColor: string = ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerDarkCustomThemeTextColor') readerDarkCustomThemeTextColor: string = ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR;
  @StorageLink('readerCustomThemesRaw') readerCustomThemesRaw: string = '';
  @StorageLink('readerFontFamily') readerFontFamily: string = '';
  @StorageLink('readerFontFilePath') readerFontFilePath: string = '';
  @StorageLink('readerFontSourceName') readerFontSourceName: string = '系统默认';
  @StorageLink('readerFontMode') readerFontMode: string = 'device';
  @StorageLink('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageLink('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @StorageLink('cloudRemoteFontsRaw') cloudRemoteFontsRaw: string = '';
  private downloadingRemoteFont: boolean = false;
  @StorageLink('readerActiveFontFamily') readerActiveFontFamily: string = '';
  @StorageLink('readerFontRegistered') readerFontRegistered: boolean = false;
  @StorageLink('readerBodyFontMode') readerBodyFontMode: string = 'global';
  @StorageLink('readerBodyFontFamily') readerBodyFontFamily: string = '';
  @StorageLink('readerPageTurnMode') readerPageTurnMode: number = 1;
  @StorageLink('readerPageTurnAnimationType') readerPageTurnAnimationType: number = ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
  @StorageLink('readerLandscapeDoublePage') readerLandscapeDoublePage: boolean = false;
  @StorageLink('readerScreenOrientation') readerScreenOrientation: string =
    ReaderSettingsStore.SCREEN_ORIENTATION_SYSTEM;
  @StorageLink('readerTapZoneActions') readerTapZoneActions: string = '3,3,3,3,1,2,2,2,2';
  @StorageLink('readerVolumeTurnPage') readerVolumeTurnPage: boolean = false;
  @StorageLink('readerScreenTimeoutMinutes') readerScreenTimeoutMinutes: number =
    ReaderSettingsStore.SCREEN_TIMEOUT_ALWAYS_ON;
  @StorageLink('readerExtendToStatusBar') readerExtendToStatusBar: boolean = false;
  @StorageLink('readerKeepParagraphIndent') keepParagraphIndent: boolean = false;
  @StorageLink('readerHeaderEnabled') readerHeaderEnabled: boolean = false;
  @StorageLink('readerFooterEnabled') readerFooterEnabled: boolean = true;
  @StorageLink('readerInfoBarConfig') readerInfoBarConfig: string = '';
  @StorageLink('readerEyeTurnEnabled') readerEyeTurnEnabled: boolean = false;
  @StorageLink('readerEyeTurnPortraitCalibration') readerEyeTurnPortraitCalibration: string = '';
  @StorageLink('readerEyeTurnLandscapeCalibration') readerEyeTurnLandscapeCalibration: string = '';
  @StorageLink('readerEyeTurnPreviousEnabled') readerEyeTurnPreviousEnabled: boolean = false;
  @StorageLink('readerEyeTurnNextEnabled') readerEyeTurnNextEnabled: boolean = true;
  @StorageLink('readerEyeTurnPreviousDwellMs') readerEyeTurnPreviousDwellMs: number = 850;
  @StorageLink('readerEyeTurnNextDwellMs') readerEyeTurnNextDwellMs: number = 650;
  @StorageLink('readerPreloadEnabled') readerPreloadEnabled: boolean = true;
  @StorageLink('readerPreloadChapterCount') readerPreloadChapterCount: number = 1;
  @StorageLink('readerQuickBookmarkEnabled') readerQuickBookmarkEnabled: boolean = true;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @State customFonts: ReaderCustomFontItem[] = [];
  @State previewFontRenderVersion: number = 0;
  private tapZoneDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showTapZoneSettings: boolean = false;
  @State customThemeNameDraft: string = '';
  private readerEyePermissionRequestSerial: number = 0;
  /** 本页已注册过的字体：文件路径 -> 注册得到的 fontFamily。 */
  private registeredFontFamilies: Map<string, string> = new Map();
  /** 第一层（空串）放小说和漫画共用的设置；SECTION_NOVEL 为小说子页（同一页面按参数显示）。 */
  private section: string = '';
  private static readonly SECTION_NOVEL: string = 'novel';

  // 设置和字体只在 onPageShow 里读：首次进入时它紧跟 aboutToAppear 执行，两处都读会把同样的活做两遍。
  aboutToAppear() {
    const params = router.getParams() as Record<string, string> | undefined;
    this.section = params?.['section'] === SettingsPage.SECTION_NOVEL ? SettingsPage.SECTION_NOVEL : '';
    this.loadThemeMode();
  }

  isNovelSection(): boolean {
    return this.section === SettingsPage.SECTION_NOVEL;
  }

  onPageShow(): void {
    this.refreshSystemFontFamily();
    this.loadReaderSettings();
    this.reloadCustomFonts();
    this.syncBars();
  }

  refreshSystemFontFamily(): string {
    const family = ReaderSystemFontHelper.applyToStorage(this.getUIContext());
    this.readerSystemFontFamily = family;
    return family;
  }

  async loadReaderSettings(): Promise<void> {
    try {
      const settings = await ReaderSettingsStore.load(getContext(this));
      ReaderSettingsStore.applyToStorage(settings);
      this.applyLoadedReaderSettings(settings);
      this.registerSelectedReaderFont(settings);
    } catch (e) {
      console.warn('读取阅读设置失败:', e);
    }
  }

  async loadThemeMode(): Promise<void> {
    try {
      const mode = await AppThemeModeStore.load(getContext(this));
      // 启动时已按保存的模式设过颜色模式；没变就别再 setColorMode，那会触发整个应用的配置刷新。
      if (AppThemeModeStore.normalizeMode(mode) === this.appThemeMode) {
        return;
      }
      this.applyThemeMode(mode, false);
    } catch (e) {
      console.warn('读取主题模式失败:', e);
      this.applyThemeMode(this.appThemeMode, false);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: this.isNovelSection() ? '小说设置' : '阅读设置', bottomInset: 0, content: () => {
        if (this.isNovelSection()) {
          this.novelContent()
        } else {
          this.pageContent()
        }
      } })

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 第一层：小说和漫画共用的设置，以及两类书各自的入口。 */
  @Builder
  pageContent() {
    this.sectionTitle('外观')
    Column() {
      this.appThemeOptions()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('操作')
    Column() {
      this.tapZoneSettingItem()
      this.selectItem('屏幕方向', '阅读时的屏幕方向',
        this.screenOrientationOptions(), this.screenOrientationSelectedIndex(), (index: number) => {
          this.setReaderScreenOrientationByIndex(index);
        }, 'settings_screen_orientation_select')
      SettingSwitchRow({
        title: '音量键翻页',
        description: '音量上/下键翻到上一页/下一页，条漫为翻一屏',
        isOn: this.readerVolumeTurnPage,
        showDivider: false,
        onChange: (value: boolean) => {
          this.setReaderVolumeTurnPage(value);
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('其他')
    Column() {
      this.selectItem('亮屏时间设置', '无操作达到所选时长后恢复系统息屏',
        this.screenTimeoutOptions(), this.screenTimeoutSelectedIndex(), (index: number) => {
          this.setReaderScreenTimeoutByIndex(index);
        }, 'settings_screen_timeout_select')
      this.preloadSettingPanel()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('分类设置')
    Column() {
      SettingNavRow({
        title: '小说',
        description: '排版、背景、翻页',
        onTap: () => {
          router.pushUrl({ url: 'pages/Settings', params: { section: SettingsPage.SECTION_NOVEL } });
        }
      })
      SettingNavRow({
        title: '漫画',
        description: '阅读方式、画面、漫画超分',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/ComicSettings' });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.XXL })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  /** 小说子页：只对文字书生效的排版、背景、翻页与预览。 */
  @Builder
  novelContent() {
    this.sectionTitle('排版')
    Column() {
      this.typographyStepper()
      this.selectItem('正文对齐方式', '正文段落的水平对齐',
        this.readerTextAlignOptions(), this.readerTextAlignSelectedIndex(), (index: number) => {
          this.setReaderTextAlignByIndex(index);
        }, 'settings_reader_text_align_select')
      this.readerHeaderFooterSettingsPanel()
      this.readerFontEntryItem()
      this.readerReplaceRulesEntryItem()
      SettingSwitchRow({
        title: '正文扩展至状态栏',
        description: '隐藏状态栏，正文延伸到屏幕顶部',
        isOn: this.readerExtendToStatusBar,
        onChange: (value: boolean) => {
          this.setReaderExtendToStatusBar(value);
        }
      })
      SettingSwitchRow({
        title: '保留段首缩进',
        description: '章节开头与页首保留原文的全角空格缩进',
        isOn: this.keepParagraphIndent,
        showDivider: false,
        onChange: (value: boolean) => {
          this.setKeepParagraphIndent(value);
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('阅读背景')
    Column() {
      this.readerThemePanel()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('翻页')
    Column() {
      this.selectItem('翻页方式', '上下滑动、横向滑动或滚动阅读',
        this.pageTurnModeOptions(), this.pageTurnModeSelectedIndex(), (index: number) => {
          this.setReaderPageTurnMode(this.pageTurnModeByIndex(index));
        }, 'settings_page_turn_mode_select')
      if (this.readerPageTurnMode === 2) {
        this.selectItem('翻页动画', '翻页时的切换效果',
          this.pageTurnAnimationOptions(), this.pageTurnAnimationSelectedIndex(), (index: number) => {
            this.setReaderPageTurnAnimationType(index);
          }, 'settings_page_turn_animation_select_horizontal')
      } else if (this.readerPageTurnMode === 0) {
        this.selectItem('翻页动画', '翻页时的切换效果',
          this.pageTurnAnimationOptions(), this.pageTurnAnimationSelectedIndex(), (index: number) => {
            this.setReaderPageTurnAnimationType(index);
          }, 'settings_page_turn_animation_select_vertical')
      }
      SettingSwitchRow({
        title: '使用双翻页',
        description: '横屏、折叠屏展开等宽屏下并排显示两页',
        isOn: this.readerLandscapeDoublePage,
        onChange: (value: boolean) => {
          this.setReaderLandscapeDoublePage(value);
        }
      })
      SettingSwitchRow({
        title: '快速添加书签',
        description: '下拉正文添加或删除当前页书签',
        isOn: this.readerQuickBookmarkEnabled,
        onChange: (value: boolean) => {
          this.setReaderQuickBookmarkEnabled(value);
        }
      })
      SettingSwitchRow({
        title: '眼动翻页（beta）',
        description: '看到页底后向上看即翻页；摄像头图像仅在本机处理',
        isOn: this.readerEyeTurnEnabled,
        showDivider: this.readerEyeTurnEnabled,
        onChange: (value: boolean) => {
          this.setReaderEyeTurnEnabled(value);
        }
      })
      if (this.readerEyeTurnEnabled) {
        this.eyeTurnCalibrationStatusItem()
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('预览')
    Column() {
      Text('第一章 风起')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.previewTitleColor())
        .width('100%')
        .margin({ bottom: AppSpacing.LG })

      if (this.previewFontRenderVersion % 2 === 0) {
        this.previewReaderText()
      } else {
        this.previewReaderText()
      }

      Text(`当前字体：${this.previewBodyFontName()} · 当前翻页：${this.pageTurnModeText()}`)
        .fontSize(AppFontSize.CAPTION)
        .fontFamily(this.getPreviewBodyFontFamily())
        .fontColor(this.previewSubTextColor())
        .width('100%')
        .margin({ top: AppSpacing.MD })
    }
    .width('calc(100% - 24vp)')
    .padding({
      left: this.readerMarginLeft,
      right: this.readerMarginRight,
      top: this.readerMarginTop,
      bottom: this.readerMarginBottom
    })
    .backgroundColor(this.previewBackgroundColor())
    .backgroundImage(this.previewBackgroundImage(), ImageRepeat.NoRepeat)
    .backgroundImageSize(this.previewBackgroundImageSize())
    .borderRadius(ThemeRuntime.buttonRadius())
    .clip(true)
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: 32 })
  }

  applyThemeMode(mode: string, persist: boolean = true) {
    const normalizedMode = AppThemeModeStore.normalizeMode(mode);
    this.appThemeMode = normalizedMode;
    AppStorage.setOrCreate('appThemeMode', normalizedMode);
    if (persist) {
      AppThemeModeStore.save(getContext(this), normalizedMode).catch((e: Error) => {
        console.warn('保存主题模式失败:', e);
      });
    }
    if (normalizedMode === 'dark') {
      this.appDarkMode = true;
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (normalizedMode === 'light') {
      this.appDarkMode = false;
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
    this.syncBars();
  }

  async reloadCustomFonts(): Promise<void> {
    this.loadCustomFonts();
    this.migrateCurrentCustomFont();
    this.syncFontModeFromCurrent();
    try {
      await this.scanCustomFontDir();
    } catch (e) {
      console.warn('扫描自定义字体失败:', e);
    }
    this.syncSelectedCustomFont();
    this.registerCustomFonts();
  }

  loadCustomFonts(): void {
    const raw = (this.readerCustomFontsRaw || '').trim();
    if (!raw) {
      this.customFonts = [];
      return;
    }
    try {
      const parsed = JSON.parse(raw) as ReaderCustomFontData | ReaderCustomFontItem[];
      const source = Array.isArray(parsed) ? parsed as ReaderCustomFontItem[] : ((parsed as ReaderCustomFontData).fonts || []);
      this.customFonts = this.cleanCustomFonts(source);
    } catch (e) {
      this.customFonts = [];
    }
  }

  saveCustomFonts(fonts?: ReaderCustomFontItem[]): void {
    const data = new ReaderCustomFontData();
    data.fonts = this.cleanCustomFonts(fonts ?? this.customFonts);
    this.customFonts = data.fonts;
    this.readerCustomFontsRaw = JSON.stringify(data);
    this.saveFontSettings();
  }

  cleanCustomFonts(source: ReaderCustomFontItem[]): ReaderCustomFontItem[] {
    const result: ReaderCustomFontItem[] = [];
    for (const item of source) {
      if (!item || !item.filePath || !this.fontFileExists(item.filePath)) {
        continue;
      }
      const fontItem = new ReaderCustomFontItem();
      fontItem.filePath = (item.filePath || '').trim();
      fontItem.sourceName = (item.sourceName || '').trim() || this.fileNameFromUri(fontItem.filePath);
      fontItem.familyName = this.normalizedFontFamily(fontItem.filePath);
      if (fontItem.familyName && fontItem.filePath && !this.hasCustomFont(result, fontItem.familyName, fontItem.filePath)) {
        result.push(fontItem);
      }
    }
    return result;
  }

  migrateCurrentCustomFont(): void {
    if (!this.readerFontFamily || !this.readerFontFilePath || !this.fontFileExists(this.readerFontFilePath)) {
      return;
    }
    const item = new ReaderCustomFontItem();
    item.familyName = this.readerFontFamily;
    item.filePath = this.readerFontFilePath;
    item.sourceName = this.readerFontSourceName || this.fileNameFromUri(this.readerFontFilePath);
    if (!this.hasCustomFont(this.customFonts, item.familyName, item.filePath)) {
      const next = this.customFonts.slice();
      next.push(item);
      this.saveCustomFonts(next);
    }
  }

  syncFontModeFromCurrent(): void {
    if (this.readerFontFilePath) {
      if (this.fontFileExists(this.readerFontFilePath)) {
        this.readerFontMode = 'custom';
        return;
      }
      this.readerFontFamily = '';
      this.readerFontFilePath = '';
      this.readerFontSourceName = '系统默认';
    }
    // 没有自定义字体时，只有明确选过跟随主题的才保留，其余回到默认的跟随系统。
    if (this.readerFontMode !== ReaderFontBootstrap.FONT_MODE_THEME ||
      this.readerFontSourceName !== ReaderSettingsStore.FONT_SOURCE_NAME_THEME) {
      this.readerFontMode = ReaderFontBootstrap.FONT_MODE_DEVICE;
    }
    this.refreshSystemFontFamily();
    if (this.readerFontFamily) {
      this.readerFontFamily = '';
      this.readerFontSourceName = '系统默认';
    }
  }

  async scanCustomFontDir(): Promise<void> {
    const dir = `${getContext(this).filesDir}/reader_fonts`;
    let names: string[] = [];
    try {
      names = await fs.listFile(dir);
    } catch (e) {
      return;
    }
    names.sort();
    const next = this.customFonts.slice();
    let changed = false;
    for (const name of names) {
      if (!this.isFontFile(name)) {
        continue;
      }
      const migratedName = this.ensureAsciiStoredFontName(dir, name);
      const filePath = `${dir}/${migratedName}`;
      const familyName = this.familyNameForPath(filePath);
      const existingIndex = this.findCustomFontIndexByFilePath(next, filePath);
      if (familyName && existingIndex >= 0 && next[existingIndex].familyName !== familyName) {
        next[existingIndex].familyName = familyName;
        if (this.readerFontFilePath === filePath) {
          this.readerFontFamily = familyName;
        }
        changed = true;
      } else if (familyName && !this.hasCustomFont(next, familyName, filePath)) {
        const oldPath = `${dir}/${name}`;
        const oldIndex = this.findCustomFontIndexByFilePath(next, oldPath);
        if (oldIndex >= 0) {
          next[oldIndex].familyName = familyName;
          next[oldIndex].filePath = filePath;
          if (!next[oldIndex].sourceName || next[oldIndex].sourceName === name) {
            next[oldIndex].sourceName = name;
          }
          if (this.readerFontFilePath === oldPath) {
            this.readerFontFilePath = filePath;
            this.readerFontFamily = familyName;
          }
          changed = true;
          continue;
        }
        const item = new ReaderCustomFontItem();
        item.familyName = familyName;
        item.filePath = filePath;
        item.sourceName = name;
        next.push(item);
        changed = true;
      }
    }
    if (changed) {
      this.saveCustomFonts(next);
    }
  }

  // 只为预览和列表注册，不改应用字体：全局字体由 registerSelectedReaderFont / selectCustomFont 决定。
  registerCustomFonts(): void {
    for (const item of this.customFonts) {
      this.registerCustomFont(item, false);
    }
    if (this.readerFontFamily && this.readerFontFilePath &&
      !this.hasCustomFont(this.customFonts, this.readerFontFamily, this.readerFontFilePath)) {
      const item = new ReaderCustomFontItem();
      item.familyName = this.readerFontFamily;
      item.filePath = this.readerFontFilePath;
      item.sourceName = this.readerFontSourceName || this.fileNameFromUri(this.readerFontFilePath);
      this.registerCustomFont(item, false);
    }
  }

  /**
   * 注册字体并返回可用的 fontFamily。同一路径在本页只真正注册一次（预览在 build 里会反复调用）。
   * activate 为 true 时同时把它记为当前应用字体，只有用户选定的全局字体才应该这样做。
   */
  registerCustomFont(item: ReaderCustomFontItem, activate: boolean = true): string {
    if (!item.filePath) {
      return '';
    }
    let family = this.registeredFontFamilies.get(item.filePath) || '';
    if (!family) {
      const fontItem = new ReaderFontItem();
      fontItem.familyName = item.familyName;
      fontItem.filePath = item.filePath;
      fontItem.sourceName = item.sourceName;
      const result = ReaderFontHelper.registerFont(this.getUIContext(), fontItem);
      if (!result.registered) {
        return '';
      }
      this.registeredFontFamilies.set(item.filePath, result.familyName);
      this.registeredFontFamilies.set(result.filePath, result.familyName);
      item.filePath = result.filePath;
      item.familyName = this.familyNameForPath(result.filePath);
      family = result.familyName;
    }
    if (activate) {
      this.readerActiveFontFamily = family;
      this.readerFontRegistered = true;
    }
    return family;
  }

  getPreviewFontFamily(): string {
    if (this.readerActiveFontFamily) {
      return this.readerActiveFontFamily;
    }
    if (this.readerFontFilePath) {
      return this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext());
    }
    return this.readerFontFamily || ReaderFontBootstrap.defaultFontFamily(this.readerFontMode,
      this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext()));
  }

  getPreviewBodyFontFamily(): string {
    return this.resolvePreviewStyledFontFamily(this.readerBodyFontMode, this.readerBodyFontFamily);
  }

  resolvePreviewStyledFontFamily(mode: string, family: string): string {
    if (mode === 'system') {
      return this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext());
    }
    if (mode === 'custom' && family) {
      return this.resolvePreviewCustomFontFamily(family);
    }
    return this.getPreviewFontFamily();
  }

  resolvePreviewCustomFontFamily(family: string): string {
    if (!family) {
      return '';
    }
    for (const item of this.customFonts) {
      const stableFamily = item.filePath ? ReaderFontHelper.normalizeFontFamily(item.filePath) : item.familyName;
      if (item.familyName === family || stableFamily === family) {
        return this.registerCustomFont(item, false) || stableFamily || family;
      }
    }
    return family;
  }

  previewBodyFontName(): string {
    if (this.readerBodyFontMode === 'system') {
      return '系统默认';
    }
    if (this.readerBodyFontMode === 'custom' && this.readerBodyFontFamily) {
      for (const item of this.customFonts) {
        const stableFamily = item.filePath ? ReaderFontHelper.normalizeFontFamily(item.filePath) : item.familyName;
        if (item.familyName === this.readerBodyFontFamily || stableFamily === this.readerBodyFontFamily) {
          return item.sourceName || item.familyName || '自定义字体';
        }
      }
      return this.readerBodyFontFamily;
    }
    return this.readerFontSourceName || '系统默认';
  }

  applyLoadedReaderSettings(settings: ReaderSettings): void {
    this.readerFontSize = settings.fontSize;
    this.readerFontWeight = settings.fontWeight;
    this.readerLetterSpacing = settings.letterSpacing;
    this.readerTextAlign = settings.textAlign;
    this.readerLineHeight = settings.lineHeight;
    this.readerParagraphSpacing = settings.paragraphSpacing;
    this.readerMarginLeft = settings.marginLeft;
    this.readerMarginRight = settings.marginRight;
    this.readerMarginTop = settings.marginTop;
    this.readerMarginBottom = settings.marginBottom;
    this.readerLightThemeIndex = settings.lightThemeIndex;
    this.readerDarkThemeIndex = settings.darkThemeIndex;
    this.readerLightCustomThemeBackgroundColor = settings.lightCustomThemeBackgroundColor;
    this.readerLightCustomThemeTextColor = settings.lightCustomThemeTextColor;
    this.readerDarkCustomThemeBackgroundColor = settings.darkCustomThemeBackgroundColor;
    this.readerDarkCustomThemeTextColor = settings.darkCustomThemeTextColor;
    this.readerCustomThemesRaw = settings.customThemesRaw || '';
    this.customThemeNameDraft = this.currentCustomThemeScheme().name;
    this.readerPageTurnMode = settings.pageTurnMode;
    this.readerPageTurnAnimationType = settings.pageTurnAnimationType;
    this.readerLandscapeDoublePage = settings.landscapeDoublePage;
    this.readerScreenOrientation = settings.screenOrientation;
    this.readerTapZoneActions = settings.tapZoneActions;
    this.readerVolumeTurnPage = settings.volumeTurnPage;
    this.readerScreenTimeoutMinutes = settings.screenTimeoutMinutes;
    this.readerExtendToStatusBar = settings.extendToStatusBar;
    this.keepParagraphIndent = settings.keepParagraphIndent;
    this.readerHeaderEnabled = settings.readerHeaderEnabled;
    this.readerFooterEnabled = settings.readerFooterEnabled;
    this.readerInfoBarConfig = settings.readerInfoBarConfig;
    this.readerEyeTurnEnabled = settings.eyeTurnEnabled;
    this.readerEyeTurnPortraitCalibration = settings.eyeTurnPortraitCalibration;
    this.readerEyeTurnLandscapeCalibration = settings.eyeTurnLandscapeCalibration;
    this.readerEyeTurnPreviousEnabled = settings.eyeTurnPreviousEnabled;
    this.readerEyeTurnNextEnabled = settings.eyeTurnNextEnabled;
    this.readerEyeTurnPreviousDwellMs = settings.eyeTurnPreviousDwellMs;
    this.readerEyeTurnNextDwellMs = settings.eyeTurnNextDwellMs;
    this.readerPreloadEnabled = settings.preloadEnabled;
    this.readerPreloadChapterCount = settings.preloadChapterCount;
    this.readerQuickBookmarkEnabled = settings.quickBookmarkEnabled;
    this.readerFontFamily = settings.fontFamily || '';
    this.readerFontFilePath = settings.fontFilePath || '';
    this.readerFontSourceName = settings.fontSourceName || '系统默认';
    this.readerFontMode = settings.fontMode || (settings.fontFilePath ? 'custom' : 'device');
    this.readerSystemFontFamily = settings.systemFontFamily || '';
    this.readerCustomFontsRaw = settings.customFontsRaw || '';
    this.readerBodyFontMode = settings.bodyFontMode || 'global';
    this.readerBodyFontFamily = settings.bodyFontFamily || '';
  }

  registerSelectedReaderFont(settings?: ReaderSettings): boolean {
    const fontFilePath = settings ? settings.fontFilePath : this.readerFontFilePath;
    const fontFamily = settings ? settings.fontFamily : this.readerFontFamily;
    const fontSourceName = settings ? settings.fontSourceName : this.readerFontSourceName;
    if (!fontFilePath || !this.fontFileExists(fontFilePath)) {
      return false;
    }
    // 启动或选字体时已注册并设成应用字体的，打开页面不再重注册、setFont 和回写设置：
    // setFont 会让整个应用（含所有 Web 组件）刷新一遍配置，正赶上页面转场。
    if (this.readerFontRegistered && this.readerActiveFontFamily === ReaderFontHelper.runtimeFontFamily(fontFilePath)) {
      return true;
    }
    const item = new ReaderCustomFontItem();
    item.familyName = fontFamily || ReaderFontHelper.normalizeFontFamily(fontFilePath);
    item.filePath = fontFilePath;
    item.sourceName = fontSourceName || this.fileNameFromUri(fontFilePath);
    const registeredFamily = this.registerCustomFont(item);
    if (registeredFamily) {
      this.readerFontFamily = item.familyName;
      this.readerFontFilePath = item.filePath;
      this.applyApplicationFont();
      this.saveFontSettings();
    }
    return !!registeredFamily;
  }

  applyApplicationFont(): void {
    ReaderFontBootstrap.applyApplicationFont(getContext(this), 'settings');
  }

  selectSystemFont(name: string): void {
    this.refreshSystemFontFamily();
    this.readerFontMode = 'system';
    this.readerFontFamily = '';
    this.readerFontFilePath = '';
    this.readerFontSourceName = '跟随主题';
    this.readerActiveFontFamily = '';
    this.readerFontRegistered = false;
    this.previewFontRenderVersion++;
    this.applyApplicationFont();
    this.saveFontSettings();
    HdsFeedback.showToast('已恢复主题默认字体');
  }

  selectDeviceFont(): void {
    this.refreshSystemFontFamily();
    this.readerFontMode = ReaderFontBootstrap.FONT_MODE_DEVICE;
    this.readerFontFamily = '';
    this.readerFontFilePath = '';
    this.readerFontSourceName = '跟随系统';
    this.readerActiveFontFamily = '';
    this.readerFontRegistered = false;
    this.previewFontRenderVersion++;
    this.applyApplicationFont();
    this.saveFontSettings();
    HdsFeedback.showToast('已改为跟随系统字体');
  }

  rememberCurrentSystemFont(): void {
    if (!this.readerFontFilePath) {
      this.refreshSystemFontFamily();
    }
  }

  selectCustomFont(item: ReaderCustomFontItem, showToast: boolean = true): void {
    if (!item || !item.familyName || !item.filePath) {
      return;
    }
    if (!this.fontFileExists(item.filePath)) {
      this.reloadCustomFonts();
      HdsFeedback.showToast('字体文件不存在');
      return;
    }
    this.rememberCurrentSystemFont();
    const registeredFamily = this.registerCustomFont(item);
    if (!registeredFamily) {
      HdsFeedback.showToast('字体注册失败，请更换字体文件');
      return;
    }
    this.readerFontMode = 'custom';
    this.readerFontFamily = item.familyName;
    this.readerFontFilePath = item.filePath;
    this.readerFontSourceName = item.sourceName || this.fileNameFromUri(item.filePath);
    this.previewFontRenderVersion++;
    this.applyApplicationFont();
    this.saveFontSettings();
    if (showToast) {
      HdsFeedback.showToast(`已选择字体：${this.readerFontSourceName}`);
    }
  }

  @Builder
  previewReaderText() {
    Text('窗外的风掠过树梢，纸页在指尖轻轻翻动。夜色渐深，故事也在这一刻慢慢展开。')
      .fontSize(this.readerFontSize)
      .fontWeight(this.readerFontWeight)
      .fontFamily(this.getPreviewBodyFontFamily())
      .fontColor(this.previewTextColor())
      .lineHeight(this.getPreviewReaderLineHeight())
      .padding({ bottom: this.readerParagraphSpacing })

    Text('他停在灯下，听见远处传来的脚步声，像是某个被遗忘的约定终于抵达。')
      .fontSize(this.readerFontSize)
      .fontWeight(this.readerFontWeight)
      .fontFamily(this.getPreviewBodyFontFamily())
      .fontColor(this.previewTextColor())
      .lineHeight(this.getPreviewReaderLineHeight())
  }

  getPreviewReaderLineHeight(): number {
    return this.readerFontSize + Math.max(0, this.readerLineHeight);
  }

  saveFontSettings(): void {
    ReaderSettingsStore.saveFontSettings(
      getContext(this),
      this.readerFontFamily,
      this.readerFontFilePath,
      this.readerFontSourceName,
      this.readerFontMode,
      this.readerSystemFontFamily,
      this.readerCustomFontsRaw
    ).catch((e: Error) => {
      console.warn('保存阅读字体设置失败:', e);
    });
  }

  isFontFile(name: string): boolean {
    const lower = (name || '').toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf') || lower.endsWith('.ttc');
  }

  fontExt(uri: string): string {
    const lower = (uri || '').toLowerCase();
    if (lower.includes('.otf')) return '.otf';
    if (lower.includes('.ttc')) return '.ttc';
    return '.ttf';
  }

  fontFileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  familyNameFromFontFileName(name: string): string {
    const index = name.lastIndexOf('.');
    return index > 0 ? name.substring(0, index) : name;
  }

  familyNameForPath(filePath: string): string {
    return ReaderFontHelper.normalizeFontFamily(filePath);
  }

  normalizedFontFamily(filePath: string): string {
    return ReaderFontHelper.normalizeFontFamily(filePath);
  }

  ensureAsciiStoredFontName(dir: string, name: string): string {
    if (this.isAsciiSafeFileName(name)) {
      return name;
    }
    const targetName = this.uniqueAsciiStoredFontName(dir, name);
    try {
      fs.renameSync(`${dir}/${name}`, `${dir}/${targetName}`);
      return targetName;
    } catch (e) {
      console.warn('迁移字体文件名失败:', e);
      return name;
    }
  }

  uniqueAsciiStoredFontName(dir: string, sourceName: string): string {
    const ext = this.fontExt(sourceName);
    const base = this.asciiStoredFontName(sourceName, 0).replace(ext, '');
    let candidate = `${base}${ext}`;
    let index = 1;
    while (this.fontFileExists(`${dir}/${candidate}`)) {
      candidate = `${base}_${index}${ext}`;
      index++;
    }
    return candidate;
  }

  asciiStoredFontName(sourceName: string, salt: number): string {
    const ext = this.fontExt(sourceName);
    let hash = salt & 0x7fffffff;
    for (let i = 0; i < sourceName.length; i++) {
      hash = ((hash * 31) + sourceName.charCodeAt(i)) & 0x7fffffff;
    }
    return `reader_font_${hash}${ext}`;
  }

  isAsciiSafeFileName(name: string): boolean {
    if (!name || name.includes('/') || name.includes('\\')) {
      return false;
    }
    for (let i = 0; i < name.length; i++) {
      const code = name.charCodeAt(i);
      if (code < 33 || code > 126) {
        return false;
      }
    }
    return true;
  }

  syncSelectedCustomFont(): void {
    if (!this.readerFontFilePath) {
      return;
    }
    const index = this.findCustomFontIndexByFilePath(this.customFonts, this.readerFontFilePath);
    if (index < 0) {
      return;
    }
    const item = this.customFonts[index];
    this.readerFontFamily = item.familyName;
    this.readerFontSourceName = item.sourceName || this.fileNameFromUri(item.filePath);
    this.readerFontMode = 'custom';
  }

  fileNameFromUri(uri: string): string {
    const decoded = decodeURIComponent(uri || '');
    const index = Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\'));
    return index >= 0 ? decoded.substring(index + 1) : decoded || '自定义字体';
  }

  hasCustomFont(fonts: ReaderCustomFontItem[], familyName: string, filePath: string): boolean {
    for (const item of fonts) {
      if (item.familyName === familyName || item.filePath === filePath) {
        return true;
      }
    }
    return false;
  }

  findCustomFontIndexByFilePath(fonts: ReaderCustomFontItem[], filePath: string): number {
    for (let i = 0; i < fonts.length; i++) {
      if (fonts[i].filePath === filePath) {
        return i;
      }
    }
    return -1;
  }

  readerFontOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '跟随系统' }, { value: '跟随主题' }];
    for (const item of this.customFonts) {
      options.push({ value: item.sourceName || item.familyName });
    }
    for (const font of this.remoteFonts()) {
      options.push({ value: CloudFontMenu.label(font) });
    }
    return options;
  }

  /** 云端有、本机未下载的字体（终身超级会员字体云同步），排在本机字体之后。 */
  remoteFonts(): CloudRemoteFont[] {
    return CloudAutoSync.parseRemoteFonts(this.cloudRemoteFontsRaw);
  }

  remoteFontStart(): number {
    return this.customFontOptionStart() + this.customFonts.length;
  }

  /** 下拉框前两项是“跟随系统”“跟随主题”，本机字体从第 3 项开始。 */
  customFontOptionStart(): number {
    return 2;
  }

  /** 选中云端字体：静默下载导入，完成后按本机字体应用。 */
  async selectRemoteFont(remoteIndex: number, apply: (customIndex: number) => void): Promise<void> {
    const font = this.remoteFonts()[remoteIndex];
    if (!font || this.downloadingRemoteFont) return;
    this.downloadingRemoteFont = true;
    try {
      const filePath = await CloudAutoSync.ensureFontDownloaded(getContext(this), font);
      this.loadCustomFonts();
      const index = this.customFonts.findIndex((item: ReaderCustomFontItem) => item.filePath === filePath);
      if (index >= 0) apply(index);
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error && e.message ? e.message : '云端字体下载失败，请稍后重试');
    } finally {
      this.downloadingRemoteFont = false;
    }
  }


  readerFontSelectedIndex(): number {
    if (this.readerFontFilePath) {
      for (let i = 0; i < this.customFonts.length; i++) {
        const item = this.customFonts[i];
        if (item.filePath === this.readerFontFilePath || item.familyName === this.readerFontFamily) {
          return i + this.customFontOptionStart();
        }
      }
    }
    return this.readerFontMode === ReaderFontBootstrap.FONT_MODE_DEVICE ? 0 : 1;
  }

  readerFontValue(): string {
    const index = this.readerFontSelectedIndex();
    if (index === 0) {
      return '跟随系统';
    }
    if (index === 1) {
      return '跟随主题';
    }
    const customIndex = index - this.customFontOptionStart();
    if (customIndex >= 0 && customIndex < this.customFonts.length) {
      const item = this.customFonts[customIndex];
      return item.sourceName || item.familyName || '自定义字体';
    }
    return '跟随主题';
  }

  selectReaderFontByIndex(index: number): void {
    if (index <= 0) {
      this.selectDeviceFont();
      return;
    }
    if (index === 1) {
      this.selectSystemFont('');
      return;
    }
    const customIndex = index - this.customFontOptionStart();
    if (customIndex >= 0 && customIndex < this.customFonts.length) {
      this.selectCustomFont(this.customFonts[customIndex]);
    }
  }

  pageTurnModeText(): string {
    if (this.readerPageTurnMode === 2) return '横向滑动';
    if (this.readerPageTurnMode === 3) return '滚动阅读';
    return '上下滑动';
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
    return actions[Math.max(0, Math.min(8, Math.round(index)))];
  }

  cycleTapZoneAction(index: number): void {
    const actions = this.readerTapZoneActionsList();
    const safeIndex = Math.max(0, Math.min(8, Math.round(index)));
    actions[safeIndex] = (actions[safeIndex] + 1) % 4;
    this.setTapZoneActions(actions.join(','));
  }

  setTapZoneActions(actions: string): void {
    const normalized = this.normalizeTapZoneActions(actions);
    this.readerTapZoneActions = normalized;
    ReaderSettingsStore.saveTapZoneActions(getContext(this), normalized).catch((e: Error) => {
      console.error('保存点击区域动作失败:', e);
    });
  }

  normalizeTapZoneActions(actions: string): string {
    const fallback = [3, 3, 3, 3, 1, 2, 2, 2, 2];
    const parts = (actions || '').split(',');
    const result: number[] = [];
    for (let i = 0; i < 9; i++) {
      const parsed = Number(parts[i]);
      result.push(Number.isFinite(parsed) && parsed >= 0 && parsed <= 3 ? Math.round(parsed) : fallback[i]);
    }
    return result.join(',');
  }

  tapActionLabel(action: number): string {
    if (action === 1) return '菜单';
    if (action === 2) return '下一页';
    if (action === 3) return '上一页';
    return '无动作';
  }

  tapZoneCellColor(action: number): string {
    if (action === 1) return '#332A6FCC';
    if (action === 2) return '#2239A86B';
    if (action === 3) return '#22A85C39';
    return '#14000000';
  }

  tapZoneSummaryText(): string {
    const counts = [0, 0, 0, 0];
    for (const action of this.readerTapZoneActionsList()) {
      counts[action]++;
    }
    return `菜单${counts[1]} · 下一页${counts[2]} · 上一页${counts[3]} · 无动作${counts[0]}`;
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

  saveReaderChromeSettings(headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string): void {
    ReaderSettingsStore.saveReaderChromeSettings(
      getContext(this),
      headerEnabled,
      footerEnabled,
      infoBarConfig
    ).catch((e: Error) => {
      console.warn('保存页眉页脚设置失败:', e);
    });
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
      this.readerFontWeight
    ).catch((e: Error) => {
      console.warn('保存阅读排版设置失败:', e);
    });
  }

  setReaderFontSize(fontSize: number): void {
    this.readerFontSize = Math.max(14, Math.min(Math.round(fontSize), 50));
    this.saveReaderLayoutSettings();
  }

  setReaderFontWeight(weight: number): void {
    this.readerFontWeight = ReaderFontWeight.normalize(weight);
    this.saveReaderLayoutSettings();
  }

  setReaderLetterSpacing(letterSpacing: number): void {
    this.readerLetterSpacing = Math.max(0, Math.min(Math.round(letterSpacing), 8));
    this.saveReaderLayoutSettings();
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

  setReaderLineHeight(lineHeight: number): void {
    this.readerLineHeight = Math.max(0, Math.min(Math.round(lineHeight), 52));
    this.saveReaderLayoutSettings();
  }

  setReaderParagraphSpacing(paragraphSpacing: number): void {
    this.readerParagraphSpacing = Math.max(0, Math.min(Math.round(paragraphSpacing), 32));
    this.saveReaderLayoutSettings();
  }

  setReaderThemeIndex(index: number): void {
    const nextIndex = ReaderThemeHelper.normalizeIndex(index);
    if (this.appDarkMode) {
      this.readerDarkThemeIndex = nextIndex;
    } else {
      this.readerLightThemeIndex = nextIndex;
    }
    this.saveReaderThemeSettings();
  }

  setReaderMarginLeft(value: number): void {
    this.readerMarginLeft = this.normalizeReaderHorizontalMargin(value);
    this.saveReaderLayoutSettings();
  }

  setReaderMarginRight(value: number): void {
    this.readerMarginRight = this.normalizeReaderHorizontalMargin(value);
    this.saveReaderLayoutSettings();
  }

  setReaderMarginTop(value: number): void {
    this.readerMarginTop = this.normalizeReaderVerticalMargin(value);
    this.saveReaderLayoutSettings();
  }

  setReaderMarginBottom(value: number): void {
    this.readerMarginBottom = this.normalizeReaderVerticalMargin(value);
    this.saveReaderLayoutSettings();
  }

  normalizeReaderHorizontalMargin(value: number): number {
    return Math.max(0, Math.min(Math.round(value), 80));
  }

  normalizeReaderVerticalMargin(value: number): number {
    return Math.max(0, Math.min(Math.round(value), 120));
  }

  typographySettingOptions(): SelectOption[] {
    return ReaderTypographyField.LABELS.map((label: string): SelectOption => ({ value: label }));
  }

  typographySettingTitle(): string {
    return ReaderTypographyField.LABELS[this.typographySettingIndex];
  }

  typographySettingMin(): number {
    return ReaderTypographyField.min(this.typographySettingIndex);
  }

  typographySettingMax(): number {
    return ReaderTypographyField.max(this.typographySettingIndex);
  }

  currentTypographySettingValue(): number {
    switch (this.typographySettingIndex) {
      case ReaderTypographyField.FONT_WEIGHT:
        return this.readerFontWeight;
      case 2:
        return this.readerLetterSpacing;
      case 3:
        return this.readerLineHeight;
      case 4:
        return this.readerParagraphSpacing;
      case 5:
        return this.readerMarginLeft;
      case 6:
        return this.readerMarginRight;
      case 7:
        return this.readerMarginTop;
      case 8:
        return this.readerMarginBottom;
      default:
        return this.readerFontSize;
    }
  }

  adjustCurrentTypographySetting(delta: number): void {
    const next = this.currentTypographySettingValue() + delta * ReaderTypographyField.step(this.typographySettingIndex);
    switch (this.typographySettingIndex) {
      case ReaderTypographyField.FONT_WEIGHT:
        this.setReaderFontWeight(next);
        return;
      case 2:
        this.setReaderLetterSpacing(next);
        return;
      case 3:
        this.setReaderLineHeight(next);
        return;
      case 4:
        this.setReaderParagraphSpacing(next);
        return;
      case 5:
        this.setReaderMarginLeft(next);
        return;
      case 6:
        this.setReaderMarginRight(next);
        return;
      case 7:
        this.setReaderMarginTop(next);
        return;
      case 8:
        this.setReaderMarginBottom(next);
        return;
      default:
        this.setReaderFontSize(next);
    }
  }

  openTypographyValueInput(): void {
    this.typographyValueDraft = '';
    this.showTypographyValueInput = true;
  }

  applyTypographyValueInput(): void {
    if (!this.showTypographyValueInput) {
      return;
    }
    const value = Number(this.typographyValueDraft);
    if (!this.typographyValueDraft.trim() || !Number.isFinite(value)) {
      this.showTypographyValueInput = false;
      return;
    }
    switch (this.typographySettingIndex) {
      case ReaderTypographyField.FONT_WEIGHT:
        this.setReaderFontWeight(value);
        break;
      case 2:
        this.setReaderLetterSpacing(value);
        break;
      case 3:
        this.setReaderLineHeight(value);
        break;
      case 4:
        this.setReaderParagraphSpacing(value);
        break;
      case 5:
        this.setReaderMarginLeft(value);
        break;
      case 6:
        this.setReaderMarginRight(value);
        break;
      case 7:
        this.setReaderMarginTop(value);
        break;
      case 8:
        this.setReaderMarginBottom(value);
        break;
      default:
        this.setReaderFontSize(value);
    }
    this.showTypographyValueInput = false;
  }

  setCurrentThemeBackgroundColor(color: string): void {
    const value = this.normalizeColor(color, this.currentCustomThemeBackgroundColor());
    const data = this.customThemeData();
    ReaderCustomThemeHelper.selected(data, this.appDarkMode).backgroundColor = value;
    this.persistCustomThemeData(data);
  }

  setCurrentThemeTextColor(color: string): void {
    const value = this.normalizeColor(color, this.currentCustomThemeTextColor());
    const data = this.customThemeData();
    ReaderCustomThemeHelper.selected(data, this.appDarkMode).textColor = value;
    this.persistCustomThemeData(data);
  }

  addCustomTheme(): void {
    const data = this.customThemeData();
    const item = ReaderCustomThemeHelper.add(data, this.appDarkMode);
    this.customThemeNameDraft = item.name;
    this.persistCustomThemeData(data);
  }

  deleteCurrentCustomTheme(): void {
    const data = this.customThemeData();
    if (ReaderCustomThemeHelper.schemesForMode(data, this.appDarkMode).length <= 1) {
      HdsFeedback.showToast('至少保留一套自定义背景');
      return;
    }
    ReaderCustomThemeHelper.removeSelected(data, this.appDarkMode);
    this.customThemeNameDraft = ReaderCustomThemeHelper.selected(data, this.appDarkMode).name;
    this.persistCustomThemeData(data);
  }

  selectCustomTheme(index: number): void {
    const data = this.customThemeData();
    const schemes = ReaderCustomThemeHelper.schemesForMode(data, this.appDarkMode);
    if (index < 0 || index >= schemes.length) {
      return;
    }
    ReaderCustomThemeHelper.select(data, this.appDarkMode, schemes[index].id);
    this.customThemeNameDraft = schemes[index].name;
    this.persistCustomThemeData(data);
  }

  renameCurrentCustomTheme(name: string): void {
    const data = this.customThemeData();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    const value = (name || '').trim().substring(0, 20);
    if (!value) {
      this.customThemeNameDraft = current.name;
      return;
    }
    current.name = value;
    this.customThemeNameDraft = value;
    this.persistCustomThemeData(data);
  }

  async chooseCurrentCustomThemeImage(): Promise<void> {
    const data = this.customThemeData();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    try {
      const imageUri = await ReaderBackgroundImageStore.pickAndSave(getContext(this), current.id);
      if (!imageUri) {
        return;
      }
      current.backgroundImageUri = imageUri;
      current.backgroundType = 'image';
      this.persistCustomThemeData(data);
    } catch (e) {
      console.error('选择阅读背景图片失败:', e);
      HdsFeedback.showToast('选择背景图片失败');
    }
  }

  clearCurrentCustomThemeImage(): void {
    const data = this.customThemeData();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    current.backgroundImageUri = '';
    current.backgroundType = 'color';
    this.persistCustomThemeData(data);
  }

  setCurrentCustomThemeBackgroundType(index: number): void {
    const data = this.customThemeData();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    current.backgroundType = index === 1 ? 'image' : 'color';
    this.persistCustomThemeData(data);
  }

  currentCustomThemeBackgroundTypeIndex(): number {
    return this.currentCustomThemeScheme().backgroundType === 'image' ? 1 : 0;
  }

  currentCustomThemeBackgroundImageUri(): string {
    const current = this.currentCustomThemeScheme();
    return current.backgroundType === 'image' ? current.backgroundImageUri : '';
  }

  setCurrentCustomThemeImageFit(index: number): void {
    const fits = ['cover', 'contain', 'fill'];
    const data = this.customThemeData();
    ReaderCustomThemeHelper.selected(data, this.appDarkMode).backgroundImageFit = fits[index] || 'cover';
    this.persistCustomThemeData(data);
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

  setReaderPageTurnMode(mode: number): void {
    this.readerPageTurnMode = mode;
    if (mode === 0 && (Math.round(this.readerPageTurnAnimationType) ===
      ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION ||
      Math.round(this.readerPageTurnAnimationType) === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D)) {
      this.readerPageTurnAnimationType = ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK;
      ReaderSettingsStore.savePageTurnAnimationType(getContext(this), this.readerPageTurnAnimationType)
        .catch((e: Error) => {
          console.error('降级上下滑动翻页动画失败:', e);
        });
    }
    ReaderSettingsStore.savePageTurnMode(getContext(this), mode).catch((e: Error) => {
      console.error('保存翻页方式失败:', e);
    });
  }

  setReaderPageTurnAnimationType(index: number): void {
    const types = this.pageTurnAnimationTypes();
    const type = index >= 0 && index < types.length ? types[index] : ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
    this.readerPageTurnAnimationType = this.normalizePageTurnAnimationType(type);
    ReaderSettingsStore.savePageTurnAnimationType(getContext(this), this.readerPageTurnAnimationType).catch((e: Error) => {
      console.error('保存翻页动画失败:', e);
    });
  }

  setReaderLandscapeDoublePage(enabled: boolean): void {
    this.readerLandscapeDoublePage = enabled;
    ReaderSettingsStore.saveLandscapeDoublePage(getContext(this), enabled).catch((e: Error) => {
      console.error('保存双翻页设置失败:', e);
    });
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
    const index = this.screenOrientationValues().indexOf(value);
    return index >= 0 ? index : 0;
  }

  setReaderScreenOrientationByIndex(index: number): void {
    const values = this.screenOrientationValues();
    this.readerScreenOrientation = index >= 0 && index < values.length ? values[index] :
      ReaderSettingsStore.SCREEN_ORIENTATION_SYSTEM;
    ReaderSettingsStore.saveScreenOrientation(getContext(this), this.readerScreenOrientation).catch((e: Error) => {
      console.error('保存阅读屏幕方向失败:', e);
    });
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
    this.saveReaderInteractionSettings();
  }

  setReaderEyeTurnEnabled(enabled: boolean): void {
    const serial = ++this.readerEyePermissionRequestSerial;
    if (!enabled) {
      this.readerEyeTurnEnabled = false;
      this.saveReaderEyeTurnSettings();
      return;
    }
    EyeTurnController.requestPermission(getContext(this) as common.UIAbilityContext)
      .then((granted: boolean): void => {
        if (serial !== this.readerEyePermissionRequestSerial) return;
        this.readerEyeTurnEnabled = granted;
        this.saveReaderEyeTurnSettings();
        if (!granted) {
          HdsFeedback.showToast('需要相机权限才能使用眼动翻页');
          return;
        }
        if (!this.readerEyeTurnPortraitCalibration && !this.readerEyeTurnLandscapeCalibration) {
          HdsFeedback.showToast('已开启，请进入正文阅读设置完成眼动校准');
        }
      })
      .catch((error: Error): void => {
        if (serial !== this.readerEyePermissionRequestSerial) return;
        this.readerEyeTurnEnabled = false;
        this.saveReaderEyeTurnSettings();
        HdsFeedback.showToast(`眼动翻页启用失败：${error.message}`);
      });
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
      console.warn('保存眼动翻页设置失败:', error.message);
    });
  }

  setReaderEyeTurnDirectionEnabled(previous: boolean, enabled: boolean): void {
    if (previous) this.readerEyeTurnPreviousEnabled = enabled;
    else this.readerEyeTurnNextEnabled = enabled;
    this.saveReaderEyeTurnSettings();
  }

  readerEyeDwellOptions(): SelectOption[] {
    return [
      { value: '0.5秒' },
      { value: '0.65秒' },
      { value: '0.85秒' },
      { value: '1.1秒' },
      { value: '1.4秒' }
    ];
  }

  readerEyeDwellValues(): number[] {
    return [500, 650, 850, 1100, 1400];
  }

  readerEyeDwellSelectedIndex(value: number): number {
    const values = this.readerEyeDwellValues();
    let selected = 0;
    let distance = Number.MAX_SAFE_INTEGER;
    for (let index = 0; index < values.length; index++) {
      const nextDistance = Math.abs(values[index] - value);
      if (nextDistance < distance) {
        selected = index;
        distance = nextDistance;
      }
    }
    return selected;
  }

  setReaderEyeDwell(previous: boolean, index: number): void {
    const values = this.readerEyeDwellValues();
    const value = index >= 0 && index < values.length ? values[index] : 850;
    if (previous) {
      this.readerEyeTurnPreviousDwellMs = value;
    } else {
      this.readerEyeTurnNextDwellMs = value;
    }
    this.saveReaderEyeTurnSettings();
  }

  readerEyeCalibrationSummary(): string {
    const portrait = this.readerEyeTurnPortraitCalibration ? '已校准' : '未校准';
    const landscape = this.readerEyeTurnLandscapeCalibration ? '已校准' : '未校准';
    return `竖屏 ${portrait} · 横屏 ${landscape}`;
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
    const index = this.screenTimeoutValues().indexOf(
      ReaderSettingsStore.normalizeScreenTimeoutMinutes(this.readerScreenTimeoutMinutes)
    );
    return index >= 0 ? index : 0;
  }

  setReaderScreenTimeoutByIndex(index: number): void {
    const values = this.screenTimeoutValues();
    this.readerScreenTimeoutMinutes = index >= 0 && index < values.length ?
      values[index] :
      ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM;
    this.saveReaderInteractionSettings();
  }

  setReaderExtendToStatusBar(enabled: boolean): void {
    this.readerExtendToStatusBar = enabled;
    this.saveReaderInteractionSettings();
  }

  setKeepParagraphIndent(enabled: boolean): void {
    this.keepParagraphIndent = enabled;
    ReaderSettingsStore.saveKeepParagraphIndent(getContext(this), enabled).catch((e: Error) => {
      console.error('保存保留段首缩进设置失败:', e);
    });
  }

  setReaderPreloadEnabled(enabled: boolean): void {
    this.readerPreloadEnabled = enabled;
    ReaderSettingsStore.savePreloadEnabled(getContext(this), enabled).catch((e: Error) => {
      console.error('保存预缓存开关失败:', e);
    });
  }

  setReaderPreloadChapterCount(count: number): void {
    const value = Math.max(1, Math.min(Math.round(count), 10));
    this.readerPreloadChapterCount = value;
    ReaderSettingsStore.savePreloadChapterCount(getContext(this), value).catch((e: Error) => {
      console.error('保存预缓存章节数失败:', e);
    });
  }

  setReaderQuickBookmarkEnabled(enabled: boolean): void {
    this.readerQuickBookmarkEnabled = enabled;
    ReaderSettingsStore.saveQuickBookmarkEnabled(getContext(this), enabled).catch((e: Error) => {
      console.error('保存快速添加书签设置失败:', e);
    });
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

  settingsDividerColor(): string {
    return ThemeRuntime.hairlineColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  /** Use one deterministic menu material for settings Select controls on API 26+. */
  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  previewBackgroundColor(): string {
    return this.currentReaderTheme().backgroundColor;
  }

  previewBackgroundImage(): ResourceStr {
    return this.currentReaderTheme().backgroundImageUri || '';
  }

  previewBackgroundImageSize(): ImageSize {
    const fit = this.currentReaderTheme().backgroundImageFit;
    return fit === 'contain' ? ImageSize.Contain : (fit === 'fill' ? ImageSize.FILL : ImageSize.Cover);
  }

  previewTitleColor(): string {
    return this.currentReaderTheme().textColor;
  }

  previewTextColor(): string {
    return this.currentReaderTheme().textColor;
  }

  previewSubTextColor(): string {
    return this.currentReaderTheme().subTextColor;
  }

  effectivePreviewThemeIndex(): number {
    return this.currentReaderThemeIndex();
  }

  currentReaderThemeIndex(): number {
    return this.appDarkMode ? this.readerDarkThemeIndex : this.readerLightThemeIndex;
  }

  currentCustomThemeBackgroundColor(): string {
    return this.currentCustomThemeScheme().backgroundColor;
  }

  currentCustomThemeTextColor(): string {
    return this.currentCustomThemeScheme().textColor;
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

  currentCustomThemeSchemes(): ReaderCustomThemeScheme[] {
    return ReaderCustomThemeHelper.schemesForMode(this.customThemeData(), this.appDarkMode);
  }

  currentCustomThemeSelectedIndex(): number {
    const schemes = this.currentCustomThemeSchemes();
    const selectedId = this.currentCustomThemeScheme().id;
    const index = schemes.findIndex((item: ReaderCustomThemeScheme) => item.id === selectedId);
    return Math.max(0, index);
  }

  customThemeOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const item of this.currentCustomThemeSchemes()) {
      const option: SelectOption = { value: item.name };
      options.push(option);
    }
    return options;
  }

  customThemeFitSelectedIndex(): number {
    const fit = this.currentCustomThemeScheme().backgroundImageFit;
    return fit === 'contain' ? 1 : (fit === 'fill' ? 2 : 0);
  }

  persistCustomThemeData(data: ReaderCustomThemeData): void {
    const selected = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    if (this.appDarkMode) {
      this.readerDarkCustomThemeBackgroundColor = selected.backgroundColor;
      this.readerDarkCustomThemeTextColor = selected.textColor;
    } else {
      this.readerLightCustomThemeBackgroundColor = selected.backgroundColor;
      this.readerLightCustomThemeTextColor = selected.textColor;
    }
    this.readerCustomThemesRaw = ReaderCustomThemeHelper.stringify(data);
    this.saveReaderThemeSettings();
  }

  currentReaderThemes(): ReaderThemeItem[] {
    const custom = this.currentCustomThemeScheme();
    return ReaderThemeHelper.themes(this.appDarkMode, custom.backgroundColor, custom.textColor,
      this.currentCustomThemeBackgroundImageUri(), custom.backgroundImageFit);
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

  normalizeColor(color: string, fallback: string): string {
    return HexColor.normalize(color, fallback, '#333333');
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }


  onSystemDialogFlagChanged(): void {
    if (!this.showTapZoneSettings) this.tapZoneDialogSession.close(this.getUIContext());
  }

  presentTapZoneSettings(): void {
    this.showTapZoneSettings = true;
    this.tapZoneDialogSession.open(this.getUIContext(), (): void => {
      this.tapZoneSettingsContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
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

  @Builder
  fontSettingPanel() {
    Row() {
      Text('字体设置')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Select(this.readerFontOptions())
        .selected(this.readerFontSelectedIndex())
        .value(this.readerFontValue())
        .font({ size: AppFontSize.BODY })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
        .onSelect((index: number) => {
          if (index >= this.remoteFontStart()) {
            this.selectRemoteFont(index - this.remoteFontStart(), (customIndex: number) => {
              this.selectReaderFontByIndex(customIndex + this.customFontOptionStart());
            });
            return;
          }
          this.selectReaderFontByIndex(index);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  customFontEntryItem() {
    Row() {
      Text('自定义字体')
        .fontColor(this.primaryTextColor())
        .fontSize(AppFontSize.BODY_LARGE)
        .layoutWeight(1)
      Text('上传 / 删除')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .margin({ right: AppSpacing.MD })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(56)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/CustomFontManager' });
    })
  }

  @Builder
  readerFontEntryItem() {
    SettingNavRow({
      title: '阅读字体',
      description: '正文、标题、正则样式',
      onTap: () => {
        router.pushUrl({ url: 'pages/ReaderFontSettings' });
      }
    })
  }

  @Builder
  readerReplaceRulesEntryItem() {
    SettingNavRow({
      title: '替换净化',
      description: '正文与章节标题的替换规则',
      onTap: () => {
        router.pushUrl({ url: 'pages/ReaderReplaceRules' });
      }
    })
  }

  @Builder
  appThemeOptions() {
    Row({ space: AppSpacing.MD }) {
      Stack({ alignContent: Alignment.Center }) {
        Text('跟随系统')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.appThemeMode === 'system' ? '#FFFFFF' : this.primaryTextColor())
      }
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'system' ? this.accentColor() : this.inputColor())
        .onClick(() => {
          this.applyThemeMode('system');
        })
      Stack({ alignContent: Alignment.Center }) {
        Text('浅色')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.appThemeMode === 'light' ? '#FFFFFF' : this.primaryTextColor())
      }
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'light' ? this.accentColor() : this.inputColor())
        .onClick(() => {
          this.applyThemeMode('light');
        })
      Stack({ alignContent: Alignment.Center }) {
        Text('深色')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.appThemeMode === 'dark' ? '#FFFFFF' : this.primaryTextColor())
      }
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'dark' ? this.accentColor() : this.inputColor())
        .onClick(() => {
          this.applyThemeMode('dark');
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
  }

  @Builder
  tapZoneSettingItem() {
    SettingRow({ title: '点击区域动作', description: this.tapZoneSummaryText() }) {
      Button('配置')
        .height(36)
        .fontSize(AppFontSize.BODY)
        .backgroundColor(this.buttonColor())
        .fontColor(ThemeRuntime.onAccentColor())
        .margin({ left: AppSpacing.LG })
        .onClick(() => {
          this.presentTapZoneSettings();
        })
    }
  }



  @Builder
  readerThemePanel() {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.XS }) {
        ForEach(this.currentReaderThemes(), (theme: ReaderThemeItem, index: number) => {
          Column({ space: AppSpacing.SM }) {
            Text(index === ReaderThemeHelper.CUSTOM_THEME_INDEX ? '自' :
              (index === ReaderThemeHelper.APP_THEME_INDEX ? '主' : ''))
              .fontSize(AppFontSize.BODY)
              .fontColor(theme.textColor)
              .textAlign(TextAlign.Center)
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor(theme.backgroundColor)
              .backgroundImage(theme.backgroundImageUri || '', ImageRepeat.NoRepeat)
              .backgroundImageSize(ImageSize.Cover)
              .border({
                width: this.currentReaderThemeIndex() === index ? 3 : 1,
                color: this.currentReaderThemeIndex() === index ? this.accentColor() : '#22000000'
              })
            Text(theme.name)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
          }
          .layoutWeight(1)
          .onClick(() => {
            this.setReaderThemeIndex(index);
          })
        }, (theme: ReaderThemeItem) =>
          `${theme.name}_${theme.backgroundColor}_${theme.textColor}_${theme.backgroundAssetId}_${theme.backgroundImageUri}_${theme.backgroundImageFit}`)
      }
      .width('100%')

      if (this.currentReaderThemeIndex() === ReaderThemeHelper.CUSTOM_THEME_INDEX) {
        Column({ space: AppSpacing.MD }) {
          Row({ space: AppSpacing.MD }) {
            Select(this.customThemeOptions())
              .selected(this.currentCustomThemeSelectedIndex())
              .value(this.currentCustomThemeScheme().name)
              .font({ size: AppFontSize.BODY })
              .fontColor(this.subTextColor())
              .backgroundColor(Color.Transparent)
              .arrowPosition(ArrowPosition.START)
              .padding({ left: 0, right: 0 })
              .borderRadius(16)
              .border({ width: 0 })
              .layoutWeight(1)
              .divider(null)
              .optionBgColor(Color.Transparent)
              .optionFontColor(this.primaryTextColor())
              .selectedOptionFontColor(this.accentColor())
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
              .menuBackgroundBlurStyle(BlurStyle.NONE)
              .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
              .onSelect((index: number) => {
                this.selectCustomTheme(index);
              })
            Button('新增')
              .height(36)
              .fontSize(AppFontSize.BODY)
              .backgroundColor(this.buttonColor())
              .fontColor(ThemeRuntime.onAccentColor())
              .onClick(() => {
                this.addCustomTheme();
              })
            Button('删除')
              .height(36)
              .fontSize(AppFontSize.BODY)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.deleteCurrentCustomTheme();
              })
          }
          .width('100%')
          TextInput({ text: this.customThemeNameDraft, placeholder: '输入方案名称' })
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .height(36)
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
            .backgroundColor(this.inputColor())
            .borderRadius(ThemeRuntime.mediumRadius())
            .onChange((value: string) => {
              this.customThemeNameDraft = value.substring(0, 20);
            })
            .onSubmit(() => {
              this.renameCurrentCustomTheme(this.customThemeNameDraft);
            })
            .onBlur(() => {
              this.renameCurrentCustomTheme(this.customThemeNameDraft);
            })
          Row() {
            Text('背景设置')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
            Blank()
            Select([{ value: '背景色' }, { value: '背景图片' }])
              .selected(this.currentCustomThemeBackgroundTypeIndex())
              .value(this.currentCustomThemeBackgroundTypeIndex() === 1 ? '背景图片' : '背景色')
              .font({ size: AppFontSize.BODY })
              .fontColor(this.subTextColor())
              .backgroundColor(Color.Transparent)
              .arrowPosition(ArrowPosition.END)
              .padding({ left: 0, right: 0 })
              .borderRadius(16)
              .border({ width: 0 })
              .optionBgColor(Color.Transparent)
              .divider(null)
              .optionFontColor(this.primaryTextColor())
              .selectedOptionFontColor(this.accentColor())
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
              .menuBackgroundBlurStyle(BlurStyle.NONE)
              .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
              .onSelect((index: number) => {
                this.setCurrentCustomThemeBackgroundType(index);
              })
          }
          .width('100%')
          if (this.currentCustomThemeBackgroundTypeIndex() === 0) {
            AdaptiveColorPicker({
              value: this.currentCustomThemeBackgroundColor(),
              placeholder: this.currentCustomThemeBackgroundColor(),
              appDarkMode: this.appDarkMode,
              accentColor: this.accentColor(),
              optionTitle: '背景颜色',
              onColorChange: (value: string) => {
                this.setCurrentThemeBackgroundColor(value);
              }
            })
          } else {
            Row({ space: AppSpacing.MD }) {
              Button(this.currentCustomThemeScheme().backgroundImageUri ? '更换背景图片' : '选择背景图片')
                .height(36)
                .fontSize(AppFontSize.BODY)
                .backgroundColor(this.buttonColor())
                .fontColor(ThemeRuntime.onAccentColor())
                .onClick(() => {
                  this.chooseCurrentCustomThemeImage();
                })
              if (this.currentCustomThemeScheme().backgroundImageUri) {
                Button('移除图片')
                  .height(36)
                  .fontSize(AppFontSize.BODY)
                  .backgroundColor(this.inputColor())
                  .fontColor(this.primaryTextColor())
                  .onClick(() => {
                    this.clearCurrentCustomThemeImage();
                  })
                Select([{ value: '裁剪填充' }, { value: '完整显示' }, { value: '拉伸铺满' }])
                  .selected(this.customThemeFitSelectedIndex())
                  .value(['裁剪填充', '完整显示', '拉伸铺满'][this.customThemeFitSelectedIndex()])
                  .font({ size: AppFontSize.BODY })
                  .fontColor(this.subTextColor())
                  .backgroundColor(Color.Transparent)
                  .arrowPosition(ArrowPosition.END)
                  .padding({ left: 0, right: 0 })
                  .borderRadius(16)
                  .border({ width: 0 })
                  .layoutWeight(1)
                  .divider(null)
                  .optionBgColor(Color.Transparent)
                  .optionFontColor(this.primaryTextColor())
                  .selectedOptionFontColor(this.accentColor())
                  .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
                  .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
                  .menuBackgroundBlurStyle(BlurStyle.NONE)
                  .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
                  .onSelect((index: number) => {
                    this.setCurrentCustomThemeImageFit(index);
                  })
              }
            }
            .width('100%')
          }
          AdaptiveColorPicker({
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
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.XL })
    .backgroundColor(this.cardColor())
  }

  @Builder
  typographyStepper() {
    Row({ space: AppSpacing.MD }) {
      Select(this.typographySettingOptions())
        .selected(this.typographySettingIndex)
        .value(this.typographySettingTitle())
        .font({ size: AppFontSize.BODY_LARGE })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.START)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
        .onSelect((index: number) => {
          this.showTypographyValueInput = false;
          this.typographySettingIndex = Math.max(0, Math.min(index, this.typographySettingOptions().length - 1));
        })
      Blank()
        .layoutWeight(1)
      this.settingsSliderStepButton($r('sys.symbol.minus'), `减小${this.typographySettingTitle()}`,
        this.currentTypographySettingValue() > this.typographySettingMin(), () => {
          this.adjustCurrentTypographySetting(-1);
        })
      if (this.showTypographyValueInput) {
        TextInput({ text: this.typographyValueDraft, placeholder: `${this.currentTypographySettingValue()}` })
          .type(InputType.Number)
          .enterKeyType(EnterKeyType.Done)
          .defaultFocus(true)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .width(52)
          .height(36)
          .padding(0)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.inputColor())
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.typographyValueDraft = value.replace(/[^0-9]/g, '').substring(0, 3);
          })
          .onSubmit(() => {
            this.applyTypographyValueInput();
          })
          .onBlur(() => {
            this.applyTypographyValueInput();
          })
      } else {
        Text(`${this.currentTypographySettingValue()}`)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .width(52)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openTypographyValueInput();
          })
      }
      this.settingsSliderStepButton($r('sys.symbol.plus'), `增加${this.typographySettingTitle()}`,
        this.currentTypographySettingValue() < this.typographySettingMax(), () => {
          this.adjustCurrentTypographySetting(1);
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  readerHeaderFooterSettingsPanel() {
    ReaderHeaderFooterSettings({
      dark: this.appDarkMode,
      textColor: this.primaryTextColor(),
      subTextColor: this.subTextColor(),
      accentColor: this.accentColor(),
      switchColor: this.buttonColor(),
      menuColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode),
      cardStyle: true,
      dividerColor: this.settingsDividerColor(),
      onChanged: (headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string): void => {
        this.saveReaderChromeSettings(headerEnabled, footerEnabled, infoBarConfig);
      }
    })
  }

  @Builder
  preloadSettingPanel() {
    SettingSwitchRow({
      title: '预缓存设置',
      description: '阅读时提前缓存后续章节',
      isOn: this.readerPreloadEnabled,
      showDivider: this.readerPreloadEnabled,
      onChange: (checked: boolean) => {
        this.setReaderPreloadEnabled(checked);
      }
    })
    if (this.readerPreloadEnabled) {
      this.selectItem('下一章节数', '预缓存的后续章节数',
        this.readerPreloadChapterOptions(), this.readerPreloadChapterCount - 1,
        (index: number) => this.setReaderPreloadChapterCount(index + 1),
        'settings_reader_preload_chapter_count_select', false)
    }
  }

  @Builder
  settingsSliderStepButton(icon: Resource, accessibilityText: string, enabled: boolean, action: () => void) {
    ImmersiveBackButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      iconColor: this.primaryTextColor(),
      disabledIconColor: this.subTextColor(),
      darkMode: this.appDarkMode,
      buttonEnabled: enabled,
      buttonSize: 34,
      containerWidth: 34,
      containerHeight: 34,
      startInset: 0,
      compactLayout: true,
      onBack: action
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
  eyeTurnCalibrationStatusItem() {
    SettingRow({
      title: '眼动校准',
      description: this.readerEyeCalibrationSummary(),
      showDivider: false,
      onTap: (): void => {
        HdsFeedback.showToast('请打开任意书籍，在正文阅读设置中点击“眼动校准”');
      }
    }) {
      Text('在正文内校准')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .margin({ left: AppSpacing.LG })
    }
  }

  @Builder
  selectItem(title: string, desc: string, options: SelectOption[], selected: number,
    onSelect: (index: number) => void, controlId: string, showDivider: boolean = true) {
    SettingRow({ title: title, description: desc, showDivider: showDivider }) {
      Select(options)
        .id(controlId)
        .selected(selected)
        .value(this.optionValue(options, selected))
        .font({ size: AppFontSize.BODY })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
        .onSelect((index: number) => {
          onSelect(index);
        })
    }
  }

  optionValue(options: SelectOption[], index: number): ResourceStr {
    if (index >= 0 && index < options.length) {
      return options[index].value;
    }
    return options.length > 0 ? options[0].value : '';
  }

}
