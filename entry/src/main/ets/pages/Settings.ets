import { router, promptAction, font } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import fs from '@ohos.file.fs';
import graphicsText from '@ohos.graphics.text';

class ReaderSystemFontItem {
  familyName: string = '';
  displayName: string = '';
}

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
  @StorageLink('readerLineHeight') readerLineHeight: number = 32;
  @StorageLink('readerParagraphSpacing') readerParagraphSpacing: number = 10;
  @StorageLink('readerThemeIndex') readerThemeIndex: number = 0;
  @StorageLink('readerFontFamily') readerFontFamily: string = '';
  @StorageLink('readerFontFilePath') readerFontFilePath: string = '';
  @StorageLink('readerFontSourceName') readerFontSourceName: string = '系统默认';
  @StorageLink('readerFontMode') readerFontMode: string = 'system';
  @StorageLink('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageLink('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @StorageLink('readerPageTurnMode') readerPageTurnMode: number = 1;
  @StorageLink('readerVolumeTurnPage') readerVolumeTurnPage: boolean = false;
  @StorageLink('readerKeepScreenOn') readerKeepScreenOn: boolean = true;
  @StorageLink('readerExtendToStatusBar') readerExtendToStatusBar: boolean = false;

  private themes: string[] = ['#F7F1E3', '#FFFFFF', '#E9F3E5', '#1F2329'];
  private themeNames: string[] = ['米黄', '素白', '青绿', '夜间'];
  @State systemFonts: ReaderSystemFontItem[] = [];
  @State customFonts: ReaderCustomFontItem[] = [];

  aboutToAppear() {
    this.applyThemeMode(this.appThemeMode);
    this.loadSystemFonts();
    this.reloadCustomFonts();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadCustomFonts();
    this.syncBars();
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
          this.fontSettingPanel()
          this.customFontEntryItem()

          this.sectionTitle('阅读背景')
          Row() {
            ForEach(this.themes, (color: string, index: number) => {
              Column() {
                Text('')
                  .width(44)
                  .height(44)
                  .borderRadius(22)
                  .backgroundColor(color)
                  .border({
                    width: this.readerThemeIndex === index ? 3 : 1,
                    color: this.readerThemeIndex === index ? '#007DFF' : '#22000000'
                  })
                Text(this.themeNames[index])
                  .fontSize(12)
                  .fontColor(this.subTextColor())
                  .margin({ top: 6 })
              }
              .margin({ right: 18 })
              .onClick(() => {
                this.readerThemeIndex = index;
              })
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 16 })
          .backgroundColor(this.cardColor())

          this.sectionTitle('翻页方式')
          this.pageTurnOptions()
          this.switchItem('音量键翻页', '阅读页获得焦点时使用音量上/下键切换上一页/下一页', this.readerVolumeTurnPage, (value: boolean) => {
            this.readerVolumeTurnPage = value;
          })
          this.switchItem('阅读时保持屏幕常亮', '进入阅读页后尽量避免自动息屏', this.readerKeepScreenOn, (value: boolean) => {
            this.readerKeepScreenOn = value;
          })
          this.switchItem('正文扩展至状态栏', '开启后正文阅读区域会延伸到顶部状态栏安全区', this.readerExtendToStatusBar, (value: boolean) => {
            this.readerExtendToStatusBar = value;
          })

          this.sectionTitle('预览')
          Column() {
            Text('第一章 风起')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.previewTitleColor())
              .width('100%')
              .margin({ bottom: 12 })

            Text('窗外的风掠过树梢，纸页在指尖轻轻翻动。夜色渐深，故事也在这一刻慢慢展开。')
              .fontSize(this.readerFontSize)
              .fontFamily(this.readerFontFamily || 'HarmonyOS Sans')
              .fontColor(this.previewTextColor())
              .lineHeight(this.readerLineHeight)
              .padding({ bottom: this.readerParagraphSpacing })

            Text('他停在灯下，听见远处传来的脚步声，像是某个被遗忘的约定终于抵达。')
              .fontSize(this.readerFontSize)
              .fontFamily(this.readerFontFamily || 'HarmonyOS Sans')
              .fontColor(this.previewTextColor())
              .lineHeight(this.readerLineHeight)

            Text(`当前字体：${this.readerFontSourceName || '系统默认'} · 当前翻页：${this.pageTurnModeText()}`)
              .fontSize(12)
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

  applyThemeMode(mode: string) {
    this.appThemeMode = mode;
    if (mode === 'dark') {
      this.appDarkMode = true;
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (mode === 'light') {
      this.appDarkMode = false;
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
    this.syncBars();
  }

  async loadSystemFonts(): Promise<void> {
    let result: ReaderSystemFontItem[] = [];
    result = await this.loadGraphicsSystemFonts(result);
    result = this.loadArkUISystemFonts(result);
    result = this.loadUIFontConfigFonts(result);
    this.systemFonts = result;
  }

  async loadGraphicsSystemFonts(result: ReaderSystemFontItem[]): Promise<ReaderSystemFontItem[]> {
    let fonts = result;
    try {
      const descriptors = await graphicsText.matchFontDescriptors({});
      fonts = this.addSystemFontDescriptors(fonts, descriptors);
    } catch (e) {
      console.warn('读取系统字体描述失败:', e);
    }

    if (fonts.length > 0) {
      return fonts;
    }

    try {
      const names = await graphicsText.getSystemFontFullNamesByType(graphicsText.SystemFontType.ALL);
      for (const name of names) {
        const value = (name || '').trim();
        if (!value) {
          continue;
        }
        try {
          const desc = await graphicsText.getFontDescriptorByFullName(value, graphicsText.SystemFontType.ALL);
          fonts = this.addSystemFontDescriptors(fonts, [desc]);
        } catch (e) {
          fonts = this.addSystemFont(fonts, value, value);
        }
      }
    } catch (e) {
      console.warn('读取系统字体全名失败:', e);
    }
    return fonts;
  }

  loadArkUISystemFonts(result: ReaderSystemFontItem[]): ReaderSystemFontItem[] {
    let fonts = result;
    try {
      const list = this.getUIContext().getFont().getSystemFontList();
      for (const name of list) {
        const value = (name || '').trim();
        if (value) {
          fonts = this.addSystemFont(fonts, value, value);
        }
      }
    } catch (e) {
      console.warn('读取 ArkUI 系统字体列表失败:', e);
    }
    return fonts;
  }

  loadUIFontConfigFonts(result: ReaderSystemFontItem[]): ReaderSystemFontItem[] {
    let fonts = result;
    try {
      const config = font.getUIFontConfig();
      for (const item of config.generic || []) {
        fonts = this.addSystemFont(fonts, item.family, item.family);
        for (const alias of item.alias || []) {
          fonts = this.addSystemFont(fonts, alias.name, alias.name);
        }
      }
      for (const group of config.fallbackGroups || []) {
        for (const fallback of group.fallback || []) {
          fonts = this.addSystemFont(fonts, fallback.family, fallback.family);
        }
      }
    } catch (e) {
      console.warn('读取 UI 字体配置失败:', e);
    }
    return fonts;
  }

  addSystemFontDescriptors(
    result: ReaderSystemFontItem[],
    descriptors: graphicsText.FontDescriptor[]
  ): ReaderSystemFontItem[] {
    let fonts = result;
    for (const desc of descriptors) {
      if (!desc) {
        continue;
      }
      const familyName = (desc.fontFamily || desc.fullName || '').trim();
      const displayName = (desc.fontFamily || desc.fullName || '').trim();
      fonts = this.addSystemFont(fonts, familyName, displayName);
    }
    return fonts;
  }

  addSystemFont(result: ReaderSystemFontItem[], familyName: string, displayName: string): ReaderSystemFontItem[] {
    const family = (familyName || '').trim();
    if (!family || family === 'System' || family === 'Default') {
      return result;
    }
    for (const item of result) {
      if (item.familyName === family) {
        return result;
      }
    }
    const next = result.slice();
    const item = new ReaderSystemFontItem();
    item.familyName = family;
    item.displayName = (displayName || '').trim() || family;
    next.push(item);
    return next;
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
  }

  cleanCustomFonts(source: ReaderCustomFontItem[]): ReaderCustomFontItem[] {
    const result: ReaderCustomFontItem[] = [];
    for (const item of source) {
      if (!item || !item.familyName || !item.filePath || !this.fontFileExists(item.filePath)) {
        continue;
      }
      const fontItem = new ReaderCustomFontItem();
      fontItem.familyName = (item.familyName || '').trim();
      fontItem.filePath = (item.filePath || '').trim();
      fontItem.sourceName = (item.sourceName || '').trim() || this.fileNameFromUri(fontItem.filePath);
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
      this.readerFontFamily = this.readerSystemFontFamily || '';
      this.readerFontFilePath = '';
      this.readerFontSourceName = this.readerFontFamily || '系统默认';
    }
    this.readerFontMode = 'system';
    this.readerSystemFontFamily = this.readerFontFamily;
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
      const filePath = `${dir}/${name}`;
      const familyName = this.familyNameFromFontFileName(name);
      if (familyName && !this.hasCustomFont(next, familyName, filePath)) {
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

  registerCustomFont(item: ReaderCustomFontItem): void {
    if (!item.familyName || !item.filePath) {
      return;
    }
    try {
      font.registerFont({
        familyName: item.familyName,
        familySrc: item.filePath
      });
    } catch (e) {
      console.warn('注册阅读字体失败:', e);
    }
  }

  selectSystemFont(name: string): void {
    this.readerFontMode = 'system';
    this.readerSystemFontFamily = name;
    this.readerFontFamily = name;
    this.readerFontFilePath = '';
    this.readerFontSourceName = name || '系统默认';
    promptAction.showToast({ message: name ? `已选择字体：${name}` : '已恢复系统默认字体' });
  }

  rememberCurrentSystemFont(): void {
    if (!this.readerFontFilePath) {
      this.readerSystemFontFamily = this.readerFontFamily;
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
    this.registerCustomFont(item);
    this.readerFontFamily = item.familyName;
    this.readerFontFilePath = item.filePath;
    this.readerFontSourceName = item.sourceName || this.fileNameFromUri(item.filePath);
    if (showToast) {
      promptAction.showToast({ message: `已选择字体：${this.readerFontSourceName}` });
    }
  }

  isFontFile(name: string): boolean {
    const lower = (name || '').toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf') || lower.endsWith('.ttc');
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

  readerFontOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '系统默认' }];
    for (const item of this.systemFonts) {
      options.push({ value: item.displayName || item.familyName });
    }
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
          return 1 + this.systemFonts.length + i;
        }
      }
      return 0;
    }
    if (!this.readerFontFamily) {
      return 0;
    }
    for (let i = 0; i < this.systemFonts.length; i++) {
      const item = this.systemFonts[i];
      if (item.familyName === this.readerFontFamily || item.displayName === this.readerFontFamily) {
        return i + 1;
      }
    }
    return 0;
  }

  readerFontValue(): string {
    const index = this.readerFontSelectedIndex();
    if (index <= 0) {
      return '系统默认';
    }
    const systemIndex = index - 1;
    if (systemIndex < this.systemFonts.length) {
      const item = this.systemFonts[systemIndex];
      return item.displayName || item.familyName || '系统默认';
    }
    const customIndex = systemIndex - this.systemFonts.length;
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
    const systemIndex = index - 1;
    if (systemIndex < this.systemFonts.length) {
      const item = this.systemFonts[systemIndex];
      this.selectSystemFont(item.familyName);
      this.readerFontSourceName = item.displayName || item.familyName || '系统默认';
      return;
    }
    const customIndex = systemIndex - this.systemFonts.length;
    if (customIndex >= 0 && customIndex < this.customFonts.length) {
      this.selectCustomFont(this.customFonts[customIndex]);
    }
  }

  pageTurnModeText(): string {
    if (this.readerPageTurnMode === 1) return '滑动翻页';
    if (this.readerPageTurnMode === 2) return '点击翻页';
    return '滚动阅读';
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

  previewBackgroundColor(): string {
    return this.themes[this.effectivePreviewThemeIndex()] || this.themes[0];
  }

  previewTitleColor(): string {
    return this.effectivePreviewThemeIndex() === 3 ? '#E8EAED' : '#1F1F1F';
  }

  previewTextColor(): string {
    return this.effectivePreviewThemeIndex() === 3 ? '#DADCE0' : '#333333';
  }

  previewSubTextColor(): string {
    return this.effectivePreviewThemeIndex() === 3 ? '#9AA0A6' : '#776B5F';
  }

  effectivePreviewThemeIndex(): number {
    return this.appDarkMode ? 3 : this.readerThemeIndex;
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
  appThemeOptions() {
    Row({ space: 8 }) {
      Text('跟随系统')
        .fontSize(14)
        .fontColor(this.appThemeMode === 'system' ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'system' ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
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
        .backgroundColor(this.appThemeMode === 'light' ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
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
        .backgroundColor(this.appThemeMode === 'dark' ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
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
        .backgroundColor(this.readerPageTurnMode === 0 ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.readerPageTurnMode = 0;
        })
      Text('滑动翻页')
        .fontSize(14)
        .fontColor(this.readerPageTurnMode === 1 ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.readerPageTurnMode === 1 ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.readerPageTurnMode = 1;
        })
      Text('点击翻页 ')
        .fontSize(14)
        .fontColor(this.readerPageTurnMode === 2 ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.readerPageTurnMode === 2 ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.readerPageTurnMode = 2;
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  fontSizeSlider() {
    Column() {
      Row() {
        Text('字号')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.readerFontSize}sp`)
          .fontSize(14)
          .fontColor(this.subTextColor())
      }
      .width('100%')

      Slider({ value: this.readerFontSize, min: 14, max: 30, step: 1 })
        .width('100%')
        .margin({ top: 8 })
        .onChange((sliderValue: number) => {
          this.readerFontSize = Math.round(sliderValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  lineHeightSlider() {
    Column() {
      Row() {
        Text('行距')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.readerLineHeight}px`)
          .fontSize(14)
          .fontColor(this.subTextColor())
      }
      .width('100%')

      Slider({ value: this.readerLineHeight, min: 24, max: 52, step: 1 })
        .width('100%')
        .margin({ top: 8 })
        .onChange((sliderValue: number) => {
          this.readerLineHeight = Math.round(sliderValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  paragraphSpacingSlider() {
    Column() {
      Row() {
        Text('段落间距')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.readerParagraphSpacing}px`)
          .fontSize(14)
          .fontColor(this.subTextColor())
      }
      .width('100%')

      Slider({ value: this.readerParagraphSpacing, min: 0, max: 32, step: 1 })
        .width('100%')
        .margin({ top: 8 })
        .onChange((sliderValue: number) => {
          this.readerParagraphSpacing = Math.round(sliderValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
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
