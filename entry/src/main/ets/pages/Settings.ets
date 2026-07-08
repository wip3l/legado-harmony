import { router, promptAction } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderThemeHelper, ReaderThemeItem } from '../utils/ReaderThemeHelper';
import { AppThemeModeStore } from '../utils/AppThemeModeStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ColorCodePicker } from '../components/ColorCodePicker';
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
  @StorageLink('readerLightThemeIndex') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') readerDarkThemeIndex: number = 0;
  @StorageLink('readerLightCustomThemeBackgroundColor') readerLightCustomThemeBackgroundColor: string = ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerLightCustomThemeTextColor') readerLightCustomThemeTextColor: string = ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR;
  @StorageLink('readerDarkCustomThemeBackgroundColor') readerDarkCustomThemeBackgroundColor: string = ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerDarkCustomThemeTextColor') readerDarkCustomThemeTextColor: string = ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR;
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
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('App 配色')
          this.appThemeOptions()

          this.sectionTitle('排版')
          this.fontSizeSlider()
          this.lineHeightSlider()
          this.paragraphSpacingSlider()
          this.readerFontEntryItem()

          this.sectionTitle('阅读背景')
          this.readerThemePanel()

          this.sectionTitle('翻页方式')
          this.pageTurnOptions()
          this.selectItem('翻页动画', '选择滑动或点击翻页时使用的页面切换效果',
            this.pageTurnAnimationOptions(), this.pageTurnAnimationSelectedIndex(), (index: number) => {
              this.setReaderPageTurnAnimationType(index);
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
          .width('100%')
          .padding(18)
          .backgroundColor(this.previewBackgroundColor())
          .borderRadius(10)
          .margin({ left: 16, right: 16, top: 12, bottom: 32 })
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
    return this.readerFontFamily || this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext());
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
    this.readerLightThemeIndex = settings.lightThemeIndex;
    this.readerDarkThemeIndex = settings.darkThemeIndex;
    this.readerLightCustomThemeBackgroundColor = settings.lightCustomThemeBackgroundColor;
    this.readerLightCustomThemeTextColor = settings.lightCustomThemeTextColor;
    this.readerDarkCustomThemeBackgroundColor = settings.darkCustomThemeBackgroundColor;
    this.readerDarkCustomThemeTextColor = settings.darkCustomThemeTextColor;
    this.readerPageTurnMode = settings.pageTurnMode;
    this.readerPageTurnAnimationType = settings.pageTurnAnimationType;
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
    this.readerFontSourceName = '系统默认';
    this.readerActiveFontFamily = '';
    this.readerFontRegistered = false;
    this.previewFontRenderVersion++;
    this.applyApplicationFont(systemFontFamily);
    this.saveFontSettings();
    promptAction.showToast({ message: '已恢复系统默认字体' });
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
    const options: SelectOption[] = [{ value: '系统默认' }];
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
      return '系统默认';
    }
    const customIndex = index - 1;
    if (customIndex >= 0 && customIndex < this.customFonts.length) {
      const item = this.customFonts[customIndex];
      return item.sourceName || item.familyName || '自定义字体';
    }
    return '系统默认';
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
    return '滚动阅读';
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
      this.readerParagraphSpacing
    ).catch((e: Error) => {
      console.warn('保存阅读排版设置失败:', e);
    });
  }

  setReaderFontSize(fontSize: number): void {
    this.readerFontSize = Math.max(14, Math.min(Math.round(fontSize), 30));
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

  setCurrentThemeBackgroundColor(color: string): void {
    const value = this.normalizeColor(color, this.currentCustomThemeBackgroundColor());
    if (this.appDarkMode) {
      this.readerDarkCustomThemeBackgroundColor = value;
    } else {
      this.readerLightCustomThemeBackgroundColor = value;
    }
    this.saveReaderThemeSettings();
  }

  setCurrentThemeTextColor(color: string): void {
    const value = this.normalizeColor(color, this.currentCustomThemeTextColor());
    if (this.appDarkMode) {
      this.readerDarkCustomThemeTextColor = value;
    } else {
      this.readerLightCustomThemeTextColor = value;
    }
    this.saveReaderThemeSettings();
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
      this.appDarkMode
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
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#888';
  }

  accentColor(): string {
    return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  buttonColor(): string {
    return this.appDarkMode ? this.appDarkButtonColor : this.appLightButtonColor;
  }

  previewBackgroundColor(): string {
    return this.currentReaderTheme().backgroundColor;
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
    return this.appDarkMode ? this.readerDarkCustomThemeBackgroundColor : this.readerLightCustomThemeBackgroundColor;
  }

  currentCustomThemeTextColor(): string {
    return this.appDarkMode ? this.readerDarkCustomThemeTextColor : this.readerLightCustomThemeTextColor;
  }

  currentReaderThemes(): ReaderThemeItem[] {
    return ReaderThemeHelper.themes(this.appDarkMode, this.currentCustomThemeBackgroundColor(), this.currentCustomThemeTextColor());
  }

  currentReaderTheme(): ReaderThemeItem {
    return ReaderThemeHelper.themeAt(
      this.appDarkMode,
      this.currentReaderThemeIndex(),
      this.currentCustomThemeBackgroundColor(),
      this.currentCustomThemeTextColor()
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
      Text('<')
        .fontSize(24)
        .fontColor(this.primaryTextColor())
        .width(40)
        .height(56)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })

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
        .fontColor(this.primaryTextColor())
        .backgroundColor(this.appDarkMode ? '#24272D' : '#F0F2F5')
        .borderRadius(8)
        .constraintSize({ minWidth: 156, maxWidth: 220 })
        .margin({ left: 12 })
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
      Text('>')
        .fontSize(18)
        .fontColor(this.subTextColor())
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
      Text('阅读字体')
        .fontColor(this.primaryTextColor())
        .fontSize(16)
        .layoutWeight(1)
      Text('正文 / 标题 / 正则')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .margin({ right: 8 })
      Text('>')
        .fontSize(18)
        .fontColor(this.subTextColor())
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ReaderFontSettings' });
    })
  }

  @Builder
  appThemeOptions() {
    Row({ space: 8 }) {
      Text('跟随系统')
        .fontSize(14)
        .fontColor(this.appThemeMode === 'system' ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'system' ? this.accentColor() : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.applyThemeMode('system');
        })
      Text('浅色')
        .fontSize(14)
        .fontColor(this.appThemeMode === 'light' ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'light' ? this.accentColor() : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.applyThemeMode('light');
        })
      Text('深色')
        .fontSize(14)
        .fontColor(this.appThemeMode === 'dark' ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'dark' ? this.accentColor() : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.applyThemeMode('dark');
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  pageTurnOptions() {
    Row({ space: 8 }) {
      Text('滚动阅读')
        .fontSize(14)
        .fontColor(this.readerPageTurnMode === 0 ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.readerPageTurnMode === 0 ? this.accentColor() : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.setReaderPageTurnMode(0);
        })
      Text('滑动翻页')
        .fontSize(14)
        .fontColor(this.readerPageTurnMode === 1 ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.readerPageTurnMode === 1 ? this.accentColor() : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.setReaderPageTurnMode(1);
        })
      Text('点击翻页 ')
        .fontSize(14)
        .fontColor(this.readerPageTurnMode === 2 ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.readerPageTurnMode === 2 ? this.accentColor() : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.setReaderPageTurnMode(2);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  readerThemePanel() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        ForEach(this.currentReaderThemes(), (theme: ReaderThemeItem, index: number) => {
          Column({ space: 6 }) {
            Text(index === ReaderThemeHelper.CUSTOM_THEME_INDEX ? '自' : '')
              .fontSize(14)
              .fontColor(theme.textColor)
              .textAlign(TextAlign.Center)
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor(theme.backgroundColor)
              .border({
                width: this.currentReaderThemeIndex() === index ? 3 : 1,
                color: this.currentReaderThemeIndex() === index ? this.accentColor() : '#22000000'
              })
            Text(theme.name)
              .fontSize(12)
              .fontColor(this.subTextColor())
          }
          .margin({ right: 18 })
          .onClick(() => {
            this.setReaderThemeIndex(index);
          })
        }, (theme: ReaderThemeItem) => `${theme.name}_${theme.backgroundColor}_${theme.textColor}`)
      }
      .width('100%')

      if (this.currentReaderThemeIndex() === ReaderThemeHelper.CUSTOM_THEME_INDEX) {
        Column({ space: 10 }) {
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
  fontSizeSlider() {
    Row() {
      Text('字号')
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Button('-')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.setReaderFontSize(this.readerFontSize - 1);
        })
      Text(`${this.readerFontSize}`)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .width(48)
        .textAlign(TextAlign.Center)
      Button('+')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.setReaderFontSize(this.readerFontSize + 1);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  lineHeightSlider() {
    Row() {
      Text('行距')
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Button('-')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.setReaderLineHeight(this.readerLineHeight - 1);
        })
      Text(`${this.readerLineHeight}`)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .width(48)
        .textAlign(TextAlign.Center)
      Button('+')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.setReaderLineHeight(this.readerLineHeight + 1);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  paragraphSpacingSlider() {
    Row() {
      Text('段落间距')
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Button('-')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.setReaderParagraphSpacing(this.readerParagraphSpacing - 1);
        })
      Text(`${this.readerParagraphSpacing}`)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .width(48)
        .textAlign(TextAlign.Center)
      Button('+')
        .width(44)
        .height(36)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.setReaderParagraphSpacing(this.readerParagraphSpacing + 1);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
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

        Slider({ value: this.readerPreloadChapterCount, min: 1, max: 10, step: 1 })
          .width('100%')
          .margin({ top: 8 })
          .selectedColor(this.accentColor())
          .onChange((sliderValue: number) => {
            this.setReaderPreloadChapterCount(sliderValue);
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
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
        .fontColor(this.primaryTextColor())
        .backgroundColor(this.appDarkMode ? '#24272D' : '#F0F2F5')
        .borderRadius(8)
        .constraintSize({ minWidth: 136, maxWidth: 180 })
        .margin({ left: 12 })
        .onSelect((index: number) => {
          onSelect(index);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardColor())
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
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardColor())
  }
}
