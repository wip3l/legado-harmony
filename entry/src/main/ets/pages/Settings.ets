import { router, promptAction } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderThemeHelper, ReaderThemeItem } from '../utils/ReaderThemeHelper';
import { ReaderCustomThemeData, ReaderCustomThemeHelper, ReaderCustomThemeScheme } from '../utils/ReaderCustomThemeHelper';
import { ReaderBackgroundImageStore } from '../utils/ReaderBackgroundImageStore';
import { AppThemeModeStore } from '../utils/AppThemeModeStore';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ColorCodePicker } from '../components/ColorCodePicker';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import fs from '@ohos.file.fs';
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
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('readerFontSize') readerFontSize: number = 20;
  @StorageLink('readerLineHeight') readerLineHeight: number = 12;
  @StorageLink('readerParagraphSpacing') readerParagraphSpacing: number = 10;
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
  @StorageLink('readerFontMode') readerFontMode: string = 'system';
  @StorageLink('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageLink('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @StorageLink('readerActiveFontFamily') readerActiveFontFamily: string = '';
  @StorageLink('readerFontRegistered') readerFontRegistered: boolean = false;
  @StorageLink('readerBodyFontMode') readerBodyFontMode: string = 'global';
  @StorageLink('readerBodyFontFamily') readerBodyFontFamily: string = '';
  @StorageLink('readerPageTurnMode') readerPageTurnMode: number = 1;
  @StorageLink('readerPageTurnAnimationType') readerPageTurnAnimationType: number = ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
  @StorageLink('readerLandscapeDoublePage') readerLandscapeDoublePage: boolean = false;
  @StorageLink('readerTapZoneActions') readerTapZoneActions: string = '3,3,3,3,1,2,2,2,2';
  @StorageLink('readerVolumeTurnPage') readerVolumeTurnPage: boolean = false;
  @StorageLink('readerKeepScreenOn') readerKeepScreenOn: boolean = true;
  @StorageLink('readerExtendToStatusBar') readerExtendToStatusBar: boolean = false;
  @StorageLink('readerPreloadEnabled') readerPreloadEnabled: boolean = true;
  @StorageLink('readerPreloadChapterCount') readerPreloadChapterCount: number = 1;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';

  @State customFonts: ReaderCustomFontItem[] = [];
  @State previewFontRenderVersion: number = 0;
  @State showTapZoneSettings: boolean = false;
  @State customThemeNameDraft: string = '';

  aboutToAppear() {
    this.loadThemeMode();
    this.loadReaderSettings();
    this.reloadCustomFonts();
    this.syncBars();
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
      this.applyThemeMode(mode, false);
    } catch (e) {
      console.warn('读取主题模式失败:', e);
      this.applyThemeMode(this.appThemeMode, false);
    }
  }

  build() {
    Stack() {
      Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('App 配色')
          Column() {
            this.appThemeOptions()
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('排版')
          Column() {
            this.typographyStepper()
            this.readerFontEntryItem()
            this.readerReplaceRulesEntryItem()
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('阅读背景')
          Column() {
          this.readerThemePanel()

          this.selectItem('翻页方式', '选择滚动、滑动、点击或上下连续滑动',
            this.pageTurnModeOptions(), this.pageTurnModeSelectedIndex(), (index: number) => {
              this.setReaderPageTurnMode(index);
            })
          if (this.readerPageTurnMode === 2) {
            this.tapZoneSettingItem()
          }
          this.selectItem('翻页动画', '选择滑动或点击翻页时使用的页面切换效果',
            this.pageTurnAnimationOptions(), this.pageTurnAnimationSelectedIndex(), (index: number) => {
              this.setReaderPageTurnAnimationType(index);
            })
          this.switchItem('使用双翻页', '横屏或折叠屏展开等宽屏状态下同时显示左右两页',
            this.readerLandscapeDoublePage, (value: boolean) => {
              this.setReaderLandscapeDoublePage(value);
            })
          this.switchItem('音量键翻页', '阅读页获得焦点时使用音量上/下键切换上一页/下一页', this.readerVolumeTurnPage, (value: boolean) => {
            this.setReaderVolumeTurnPage(value);
          })
          this.switchItem('阅读时保持屏幕常亮', '进入阅读页后尽量避免自动息屏', this.readerKeepScreenOn, (value: boolean) => {
            this.setReaderKeepScreenOn(value);
          })
          this.switchItem('正文扩展至状态栏', '开启后正文阅读区域会延伸到顶部状态栏安全区', this.readerExtendToStatusBar, (value: boolean) => {
            this.setReaderExtendToStatusBar(value);
          })
          this.preloadSettingPanel()
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('预览')
          Column() {
            Text('第一章 风起')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.previewTitleColor())
              .width('100%')
              .margin({ bottom: 12 })

            if (this.previewFontRenderVersion % 2 === 0) {
              this.previewReaderText()
            } else {
              this.previewReaderText()
            }

            Text(`当前字体：${this.previewBodyFontName()} · 当前翻页：${this.pageTurnModeText()}`)
              .fontSize(12)
              .fontFamily(this.getPreviewBodyFontFamily())
              .fontColor(this.previewSubTextColor())
              .width('100%')
              .margin({ top: 10 })
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
          .borderRadius(16)
          .clip(true)
          .margin({ left: 12, right: 12, bottom: 32 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      if (this.showTapZoneSettings) {
        this.tapZoneSettingsDialog()
      }
    }
    .width('100%')
    .height('100%')
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
    this.readerFontMode = 'system';
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

  registerCustomFonts(): void {
    for (const item of this.customFonts) {
      this.registerCustomFont(item);
    }
    if (this.readerFontFamily && this.readerFontFilePath &&
      !this.hasCustomFont(this.customFonts, this.readerFontFamily, this.readerFontFilePath)) {
      const item = new ReaderCustomFontItem();
      item.familyName = this.readerFontFamily;
      item.filePath = this.readerFontFilePath;
      item.sourceName = this.readerFontSourceName || this.fileNameFromUri(this.readerFontFilePath);
      this.registerCustomFont(item);
    }
  }

  registerCustomFont(item: ReaderCustomFontItem): string {
    if (!item.filePath) {
      return '';
    }
    const fontItem = new ReaderFontItem();
    fontItem.familyName = item.familyName;
    fontItem.filePath = item.filePath;
    fontItem.sourceName = item.sourceName;
    const result = ReaderFontHelper.registerFont(this.getUIContext(), fontItem);
    if (result.registered) {
      item.filePath = result.filePath;
      item.familyName = this.familyNameForPath(result.filePath);
      this.readerActiveFontFamily = result.familyName;
      this.readerFontRegistered = true;
      return result.familyName;
    }
    return '';
  }

  getPreviewFontFamily(): string {
    if (this.readerActiveFontFamily) {
      return this.readerActiveFontFamily;
    }
    if (this.readerFontFilePath) {
      return this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext());
    }
    return this.readerFontFamily || ThemeRuntime.fontFamily() || this.readerSystemFontFamily ||
      ReaderSystemFontHelper.currentFromStorage(this.getUIContext());
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
        return this.registerCustomFont(item) || stableFamily || family;
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
    this.readerTapZoneActions = settings.tapZoneActions;
    this.readerVolumeTurnPage = settings.volumeTurnPage;
    this.readerKeepScreenOn = settings.keepScreenOn;
    this.readerExtendToStatusBar = settings.extendToStatusBar;
    this.readerPreloadEnabled = settings.preloadEnabled;
    this.readerPreloadChapterCount = settings.preloadChapterCount;
    this.readerFontFamily = settings.fontFamily || '';
    this.readerFontFilePath = settings.fontFilePath || '';
    this.readerFontSourceName = settings.fontSourceName || '系统默认';
    this.readerFontMode = settings.fontMode || (settings.fontFilePath ? 'custom' : 'system');
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
    const item = new ReaderCustomFontItem();
    item.familyName = fontFamily || ReaderFontHelper.normalizeFontFamily(fontFilePath);
    item.filePath = fontFilePath;
    item.sourceName = fontSourceName || this.fileNameFromUri(fontFilePath);
    const registeredFamily = this.registerCustomFont(item);
    if (registeredFamily) {
      this.readerFontFamily = item.familyName;
      this.readerFontFilePath = item.filePath;
      this.applyApplicationFont(registeredFamily);
      this.saveFontSettings();
    }
    return !!registeredFamily;
  }

  applyApplicationFont(familyName: string): void {
    try {
      getContext(this).getApplicationContext().setFont(familyName || '');
    } catch (e) {
      console.warn('应用阅读字体失败:', e);
    }
  }

  selectSystemFont(name: string): void {
    const systemFontFamily = this.refreshSystemFontFamily();
    this.readerFontMode = 'system';
    this.readerFontFamily = '';
    this.readerFontFilePath = '';
    this.readerFontSourceName = '跟随主题';
    this.readerActiveFontFamily = '';
    this.readerFontRegistered = false;
    this.previewFontRenderVersion++;
    this.applyApplicationFont(ThemeRuntime.fontFamily() || systemFontFamily);
    this.saveFontSettings();
    promptAction.showToast({ message: '已恢复主题默认字体' });
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
      promptAction.showToast({ message: '字体文件不存在' });
      return;
    }
    this.rememberCurrentSystemFont();
    this.readerFontMode = 'custom';
    const registeredFamily = this.registerCustomFont(item);
    if (!registeredFamily) {
      promptAction.showToast({ message: '字体注册失败，请更换字体文件' });
      return;
    }
    this.readerFontFamily = item.familyName;
    this.readerFontFilePath = item.filePath;
    this.readerFontSourceName = item.sourceName || this.fileNameFromUri(item.filePath);
    this.previewFontRenderVersion++;
    this.applyApplicationFont(registeredFamily);
    this.saveFontSettings();
    if (showToast) {
      promptAction.showToast({ message: `已选择字体：${this.readerFontSourceName}` });
    }
  }

  @Builder
  previewReaderText() {
    Text('窗外的风掠过树梢，纸页在指尖轻轻翻动。夜色渐深，故事也在这一刻慢慢展开。')
      .fontSize(this.readerFontSize)
      .fontFamily(this.getPreviewBodyFontFamily())
      .fontColor(this.previewTextColor())
      .lineHeight(this.getPreviewReaderLineHeight())
      .padding({ bottom: this.readerParagraphSpacing })

    Text('他停在灯下，听见远处传来的脚步声，像是某个被遗忘的约定终于抵达。')
      .fontSize(this.readerFontSize)
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
    const options: SelectOption[] = [{ value: '跟随主题' }];
    for (const item of this.customFonts) {
      options.push({ value: item.sourceName || item.familyName });
    }
    return options;
  }

  readerFontSelectedIndex(): number {
    if (this.readerFontFilePath) {
      for (let i = 0; i < this.customFonts.length; i++) {
        const item = this.customFonts[i];
        if (item.filePath === this.readerFontFilePath || item.familyName === this.readerFontFamily) {
          return i + 1;
        }
      }
      return 0;
    }
    return 0;
  }

  readerFontValue(): string {
    const index = this.readerFontSelectedIndex();
    if (index <= 0) {
      return '跟随主题';
    }
    const customIndex = index - 1;
    if (customIndex >= 0 && customIndex < this.customFonts.length) {
      const item = this.customFonts[customIndex];
      return item.sourceName || item.familyName || '自定义字体';
    }
    return '跟随主题';
  }

  selectReaderFontByIndex(index: number): void {
    if (index <= 0) {
      this.selectSystemFont('');
      return;
    }
    const customIndex = index - 1;
    if (customIndex >= 0 && customIndex < this.customFonts.length) {
      this.selectCustomFont(this.customFonts[customIndex]);
    }
  }

  pageTurnModeText(): string {
    if (this.readerPageTurnMode === 1) return '滑动翻页';
    if (this.readerPageTurnMode === 2) return '点击翻页';
    if (this.readerPageTurnMode === 3) return '上下滑动';
    return '滚动阅读';
  }

  pageTurnModeOptions(): SelectOption[] {
    return [
      { value: '滚动阅读' },
      { value: '滑动翻页' },
      { value: '点击翻页' },
      { value: '上下滑动' }
    ];
  }

  pageTurnModeSelectedIndex(): number {
    return this.readerPageTurnMode >= 0 && this.readerPageTurnMode <= 3 ? this.readerPageTurnMode : 0;
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
    return [
      { value: '无动画' },
      { value: '平移' },
      { value: '淡入' },
      { value: '叠页' }
    ];
  }

  pageTurnAnimationTypes(): number[] {
    return [
      ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE,
      ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE,
      ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE,
      ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK
    ];
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

  saveReaderLayoutSettings(): void {
    ReaderSettingsStore.saveLayoutSettings(
      getContext(this),
      this.readerFontSize,
      this.readerLineHeight,
      this.readerParagraphSpacing,
      this.readerMarginLeft,
      this.readerMarginRight,
      this.readerMarginTop,
      this.readerMarginBottom
    ).catch((e: Error) => {
      console.warn('保存阅读排版设置失败:', e);
    });
  }

  setReaderFontSize(fontSize: number): void {
    this.readerFontSize = Math.max(14, Math.min(Math.round(fontSize), 50));
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
    this.readerMarginLeft = this.normalizeReaderMargin(value);
    this.saveReaderLayoutSettings();
  }

  setReaderMarginRight(value: number): void {
    this.readerMarginRight = this.normalizeReaderMargin(value);
    this.saveReaderLayoutSettings();
  }

  setReaderMarginTop(value: number): void {
    this.readerMarginTop = this.normalizeReaderMargin(value);
    this.saveReaderLayoutSettings();
  }

  setReaderMarginBottom(value: number): void {
    this.readerMarginBottom = this.normalizeReaderMargin(value);
    this.saveReaderLayoutSettings();
  }

  normalizeReaderMargin(value: number): number {
    return Math.max(0, Math.min(Math.round(value), 300));
  }

  typographySettingOptions(): SelectOption[] {
    return [
      { value: '字号' },
      { value: '行距' },
      { value: '段落间距' },
      { value: '左边距' },
      { value: '右边距' },
      { value: '上边距' },
      { value: '下边距' }
    ];
  }

  typographySettingTitle(): string {
    const titles: string[] = ['字号', '行距', '段落间距', '左边距', '右边距', '上边距', '下边距'];
    const index = Math.max(0, Math.min(this.typographySettingIndex, titles.length - 1));
    return titles[index];
  }

  currentTypographySettingValue(): number {
    switch (this.typographySettingIndex) {
      case 1:
        return this.readerLineHeight;
      case 2:
        return this.readerParagraphSpacing;
      case 3:
        return this.readerMarginLeft;
      case 4:
        return this.readerMarginRight;
      case 5:
        return this.readerMarginTop;
      case 6:
        return this.readerMarginBottom;
      default:
        return this.readerFontSize;
    }
  }

  adjustCurrentTypographySetting(delta: number): void {
    const next = this.currentTypographySettingValue() + delta;
    switch (this.typographySettingIndex) {
      case 1:
        this.setReaderLineHeight(next);
        return;
      case 2:
        this.setReaderParagraphSpacing(next);
        return;
      case 3:
        this.setReaderMarginLeft(next);
        return;
      case 4:
        this.setReaderMarginRight(next);
        return;
      case 5:
        this.setReaderMarginTop(next);
        return;
      case 6:
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
      case 1:
        this.setReaderLineHeight(value);
        break;
      case 2:
        this.setReaderParagraphSpacing(value);
        break;
      case 3:
        this.setReaderMarginLeft(value);
        break;
      case 4:
        this.setReaderMarginRight(value);
        break;
      case 5:
        this.setReaderMarginTop(value);
        break;
      case 6:
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
      promptAction.showToast({ message: '至少保留一套自定义背景' });
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
      promptAction.showToast({ message: '选择背景图片失败' });
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

  normalizePageTurnAnimationType(type: number): number {
    const value = Math.round(type);
    if (value === ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return value;
    }
    return ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
  }

  saveReaderInteractionSettings(): void {
    ReaderSettingsStore.saveReadingInteractionSettings(
      getContext(this),
      this.readerVolumeTurnPage,
      this.readerKeepScreenOn,
      this.readerExtendToStatusBar
    ).catch((e: Error) => {
      console.error('保存阅读交互设置失败:', e);
    });
  }

  setReaderVolumeTurnPage(enabled: boolean): void {
    this.readerVolumeTurnPage = enabled;
    this.saveReaderInteractionSettings();
  }

  setReaderKeepScreenOn(enabled: boolean): void {
    this.readerKeepScreenOn = enabled;
    this.saveReaderInteractionSettings();
  }

  setReaderExtendToStatusBar(enabled: boolean): void {
    this.readerExtendToStatusBar = enabled;
    this.saveReaderInteractionSettings();
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
    const trimmed = (color || '').trim();
    const normalized = trimmed.startsWith('#') ? trimmed : `#${trimmed}`;
    if (/^#[0-9a-fA-F]{6}$/.test(normalized)) {
      return normalized.toUpperCase();
    }
    const fallbackTrimmed = (fallback || '').trim();
    const normalizedFallback = fallbackTrimmed.startsWith('#') ? fallbackTrimmed : `#${fallbackTrimmed}`;
    return /^#[0-9a-fA-F]{6}$/.test(normalizedFallback) ? normalizedFallback.toUpperCase() : '#333333';
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

      Text('阅读设置')
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
  fontSettingPanel() {
    Row() {
      Text('字体设置')
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Select(this.readerFontOptions())
        .selected(this.readerFontSelectedIndex())
        .value(this.readerFontValue())
        .font({ size: 14 })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(0)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onSelect((index: number) => {
          this.selectReaderFontByIndex(index);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  customFontEntryItem() {
    Row() {
      Text('自定义字体')
        .fontColor(this.primaryTextColor())
        .fontSize(16)
        .layoutWeight(1)
      Text('上传 / 删除')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .margin({ right: 8 })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/CustomFontManager' });
    })
  }

  @Builder
  readerFontEntryItem() {
    Row() {
      Column({ space: 4 }) {
        Text('阅读字体')
          .fontColor(this.primaryTextColor())
          .fontSize(16)
        Text('正文 / 标题 / 正则样式设置')
          .fontSize(12)
          .fontColor(this.subTextColor())
      }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 62 })
    .padding({ left: 0, right: 0, top: 8, bottom: 8 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ReaderFontSettings' });
    })
  }

  @Builder
  readerReplaceRulesEntryItem() {
    Row() {
      Column({ space: 4 }) {
        Text('替换净化')
          .fontColor(this.primaryTextColor())
          .fontSize(16)
        Text('管理正文与章节标题的替换规则')
          .fontSize(12)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 62 })
    .padding({ left: 0, right: 0, top: 8, bottom: 8 })
    .margin({ left: 16, right: 16 })
    .border({ width: { top: 0.5 }, color: ThemeRuntime.glassBorderColor(this.appDarkMode) })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ReaderReplaceRules' });
    })
  }

  @Builder
  appThemeOptions() {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Text('跟随系统')
          .fontSize(14)
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
          .fontSize(14)
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
          .fontSize(14)
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
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  tapZoneSettingItem() {
    Row() {
      Column() {
        Text('点击区域动作')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(this.tapZoneSummaryText())
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('配置')
        .height(36)
        .fontSize(14)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .margin({ left: 12 })
        .onClick(() => {
          this.showTapZoneSettings = true;
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  tapZoneSettingsDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 14 }) {
        Row() {
          Text('点击区域动作')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)

          Button('×')
            .fontSize(24)
            .fontColor(this.primaryTextColor())
            .width(44)
            .height(44)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .onClick(() => {
              this.showTapZoneSettings = false;
            })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        Text('点击九宫格可循环设置：无动作、菜单、下一页、上一页')
          .fontSize(12)
          .fontColor(this.subTextColor())
          .width('100%')

        Column() {
          ForEach([0, 1, 2], (row: number) => {
            Row() {
              ForEach([0, 1, 2], (column: number) => {
                this.tapZoneCell(row * 3 + column)
              }, (column: number) => `${row}_${column}`)
            }
            .width('100%')
            .layoutWeight(1)
          }, (row: number) => `${row}`)
        }
        .width('100%')
        .height(280)
        .border({ width: 1, color: this.appDarkMode ? '#44FFFFFF' : '#22000000' })
        .clip(true)

        Row({ space: 12 }) {
          Button('重置默认')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.setTapZoneActions('3,3,3,3,1,2,2,2,2');
            })

          Button('完成')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.showTapZoneSettings = false;
            })
        }
        .width('100%')
      }
      .width('calc(100% - 40vp)')
      .padding(18)
      .borderRadius(16)
      .backgroundColor(this.cardColor())
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor('#66000000')
  }

  @Builder
  tapZoneCell(index: number) {
    Text(this.tapActionLabel(this.readerTapZoneActionAt(index)))
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.primaryTextColor())
      .textAlign(TextAlign.Center)
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .backgroundColor(this.tapZoneCellColor(this.readerTapZoneActionAt(index)))
      .border({ width: 0.5, color: this.appDarkMode ? '#33FFFFFF' : '#22000000' })
      .onClick(() => {
        this.cycleTapZoneAction(index);
      })
  }

  @Builder
  readerThemePanel() {
    Column({ space: 14 }) {
      Row({ space: 4 }) {
        ForEach(this.currentReaderThemes(), (theme: ReaderThemeItem, index: number) => {
          Column({ space: 6 }) {
            Text(index === ReaderThemeHelper.CUSTOM_THEME_INDEX ? '自' :
              (index === ReaderThemeHelper.APP_THEME_INDEX ? '主' : ''))
              .fontSize(14)
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
              .fontSize(12)
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
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Select(this.customThemeOptions())
              .selected(this.currentCustomThemeSelectedIndex())
              .value(this.currentCustomThemeScheme().name)
              .font({ size: 14 })
              .fontColor(this.subTextColor())
              .backgroundColor(Color.Transparent)
              .arrowPosition(ArrowPosition.START)
              .padding({ left: 0, right: 0 })
              .layoutWeight(1)
              .optionBgColor(Color.Transparent)
              .optionFontColor(this.primaryTextColor())
              .selectedOptionFontColor(this.accentColor())
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
              .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
              .onSelect((index: number) => {
                this.selectCustomTheme(index);
              })
            Button('新增')
              .height(36)
              .fontSize(13)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.addCustomTheme();
              })
            Button('删除')
              .height(36)
              .fontSize(13)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.deleteCurrentCustomTheme();
              })
          }
          .width('100%')
          TextInput({ text: this.customThemeNameDraft, placeholder: '输入方案名称' })
            .fontSize(14)
            .fontColor(this.primaryTextColor())
            .height(36)
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.inputColor())
            .borderRadius(8)
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
              .fontSize(14)
              .fontColor(this.primaryTextColor())
            Blank()
            Select([{ value: '背景色' }, { value: '背景图片' }])
              .selected(this.currentCustomThemeBackgroundTypeIndex())
              .value(this.currentCustomThemeBackgroundTypeIndex() === 1 ? '背景图片' : '背景色')
              .font({ size: 14 })
              .fontColor(this.subTextColor())
              .backgroundColor(Color.Transparent)
              .arrowPosition(ArrowPosition.END)
              .padding({ left: 0, right: 0 })
              .optionBgColor(Color.Transparent)
              .optionFontColor(this.primaryTextColor())
              .selectedOptionFontColor(this.accentColor())
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
              .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
              .onSelect((index: number) => {
                this.setCurrentCustomThemeBackgroundType(index);
              })
          }
          .width('100%')
          if (this.currentCustomThemeBackgroundTypeIndex() === 0) {
            ColorCodePicker({
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
            Row({ space: 8 }) {
              Button(this.currentCustomThemeScheme().backgroundImageUri ? '更换背景图片' : '选择背景图片')
                .height(36)
                .fontSize(13)
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.chooseCurrentCustomThemeImage();
                })
              if (this.currentCustomThemeScheme().backgroundImageUri) {
                Button('移除图片')
                  .height(36)
                  .fontSize(13)
                  .backgroundColor(this.inputColor())
                  .fontColor(this.primaryTextColor())
                  .onClick(() => {
                    this.clearCurrentCustomThemeImage();
                  })
                Select([{ value: '裁剪填充' }, { value: '完整显示' }, { value: '拉伸铺满' }])
                  .selected(this.customThemeFitSelectedIndex())
                  .value(['裁剪填充', '完整显示', '拉伸铺满'][this.customThemeFitSelectedIndex()])
                  .font({ size: 13 })
                  .fontColor(this.subTextColor())
                  .backgroundColor(Color.Transparent)
                  .arrowPosition(ArrowPosition.END)
                  .padding({ left: 0, right: 0 })
                  .layoutWeight(1)
                  .optionBgColor(Color.Transparent)
                  .optionFontColor(this.primaryTextColor())
                  .selectedOptionFontColor(this.accentColor())
                  .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
                  .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
                  .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
                  .onSelect((index: number) => {
                    this.setCurrentCustomThemeImageFit(index);
                  })
              }
            }
            .width('100%')
          }
          ColorCodePicker({
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
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  typographyStepper() {
    Row({ space: 8 }) {
      Select(this.typographySettingOptions())
        .selected(this.typographySettingIndex)
        .value(this.typographySettingTitle())
        .font({ size: 15 })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.START)
        .padding({ left: 0, right: 0 })
        .borderRadius(0)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onSelect((index: number) => {
          this.showTypographyValueInput = false;
          this.typographySettingIndex = Math.max(0, Math.min(index, this.typographySettingOptions().length - 1));
        })
      Blank()
        .layoutWeight(1)
      Button('-')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.adjustCurrentTypographySetting(-1);
        })
      if (this.showTypographyValueInput) {
        TextInput({ text: this.typographyValueDraft, placeholder: `${this.currentTypographySettingValue()}` })
          .type(InputType.Number)
          .defaultFocus(true)
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .width(52)
          .height(36)
          .padding(0)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.inputColor())
          .borderRadius(6)
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
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .width(52)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openTypographyValueInput();
          })
      }
      Button('+')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.adjustCurrentTypographySetting(1);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  preloadSettingPanel() {
    Column() {
      Row() {
        Column() {
          Text('预缓存设置')
            .fontSize(16)
            .fontColor(this.primaryTextColor())
          Text(this.readerPreloadEnabled ? '阅读过程中提前缓存后续章节' : '已关闭阅读过程中的自动预缓存')
            .fontSize(12)
            .fontColor(this.subTextColor())
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.readerPreloadEnabled })
          .selectedColor(this.buttonColor())
          .onChange((checked: boolean) => {
            this.setReaderPreloadEnabled(checked);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.readerPreloadEnabled) {
        Row() {
          Text('下一章节数')
            .fontSize(14)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Text(`${this.readerPreloadChapterCount}章`)
            .fontSize(14)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .margin({ top: 12 })

        Row({ space: 10 }) {
          this.settingsSliderStepButton($r('sys.symbol.minus'), '减少预缓存章节数',
            this.readerPreloadChapterCount > 1, () => {
            this.setReaderPreloadChapterCount(this.readerPreloadChapterCount - 1);
          })
          Slider({ value: this.readerPreloadChapterCount, min: 1, max: 10, step: 1 })
            .layoutWeight(1)
            .selectedColor(this.accentColor())
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
            .onChange((sliderValue: number) => {
              this.setReaderPreloadChapterCount(sliderValue);
            })
          this.settingsSliderStepButton($r('sys.symbol.plus'), '增加预缓存章节数',
            this.readerPreloadChapterCount !== 10, () => {
            this.setReaderPreloadChapterCount(this.readerPreloadChapterCount + 1);
          })
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  settingsSliderStepButton(icon: Resource, accessibilityText: string, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([enabled ? this.primaryTextColor() : this.subTextColor()])
    }
    .width(34)
    .height(34)
    .padding(0)
    .enabled(enabled)
    .backgroundColor(this.inputColor())
    .accessibilityText(accessibilityText)
    .onClick(action)
  }

  @Builder
  selectItem(title: string, desc: string, options: SelectOption[], selected: number, onSelect: (index: number) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Select(options)
        .selected(selected)
        .value(this.optionValue(options, selected))
        .font({ size: 14 })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(0)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .onSelect((index: number) => {
          onSelect(index);
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
  }

  optionValue(options: SelectOption[], index: number): ResourceStr {
    if (index >= 0 && index < options.length) {
      return options[index].value;
    }
    return options.length > 0 ? options[0].value : '';
  }

  @Builder
  switchItem(title: string, desc: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.buttonColor())
        .onChange((checked: boolean) => {
          onChange(checked);
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
  }
}
