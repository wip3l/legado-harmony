import { router, promptAction } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
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
struct FontSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('readerFontFamily') readerFontFamily: string = '';
  @StorageLink('readerFontFilePath') readerFontFilePath: string = '';
  @StorageLink('readerFontSourceName') readerFontSourceName: string = '系统默认';
  @StorageLink('readerFontMode') readerFontMode: string = 'system';
  @StorageLink('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageLink('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @StorageLink('readerActiveFontFamily') readerActiveFontFamily: string = '';
  @StorageLink('readerFontRegistered') readerFontRegistered: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State customFonts: ReaderCustomFontItem[] = [];

  aboutToAppear(): void {
    this.refreshSystemFontFamily();
    this.reloadCustomFonts();
    this.syncBars();
  }

  onPageShow(): void {
    this.refreshSystemFontFamily();
    this.reloadCustomFonts();
    this.syncBars();
  }

  refreshSystemFontFamily(): string {
    const family = ReaderSystemFontHelper.applyToStorage(this.getUIContext());
    this.readerSystemFontFamily = family;
    return family;
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('全局字体设置')
          this.fontSettingPanel()
          this.customFontEntryItem()
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

  async reloadCustomFonts(): Promise<void> {
    this.loadCustomFonts();
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
      const oldPath = item.filePath;
      const oldFamilyName = item.familyName;
      item.filePath = result.filePath;
      item.familyName = this.familyNameForPath(result.filePath);
      if (this.readerFontFilePath === item.filePath || this.readerFontFilePath === oldPath ||
        this.readerFontFamily === item.familyName || this.readerFontFamily === oldFamilyName) {
        this.readerFontFilePath = item.filePath;
        this.readerFontFamily = item.familyName;
        this.readerActiveFontFamily = result.familyName;
        this.readerFontRegistered = true;
      }
      return result.familyName;
    }
    return '';
  }

  selectSystemFont(): void {
    const systemFontFamily = this.refreshSystemFontFamily();
    this.readerFontMode = 'system';
    this.readerFontFamily = '';
    this.readerFontFilePath = '';
    this.readerFontSourceName = '系统默认';
    this.readerActiveFontFamily = '';
    this.readerFontRegistered = false;
    this.applyApplicationFont(systemFontFamily);
    this.saveFontSettings();
    promptAction.showToast({ message: '已恢复系统默认字体' });
  }

  selectCustomFont(item: ReaderCustomFontItem): void {
    if (!item || !item.familyName || !item.filePath) {
      return;
    }
    if (!this.fontFileExists(item.filePath)) {
      this.reloadCustomFonts();
      promptAction.showToast({ message: '字体文件不存在' });
      return;
    }
    this.readerFontMode = 'custom';
    const registeredFamily = this.registerCustomFont(item);
    if (!registeredFamily) {
      promptAction.showToast({ message: '字体注册失败，请更换字体文件' });
      return;
    }
    this.readerFontFamily = item.familyName;
    this.readerFontFilePath = item.filePath;
    this.readerFontSourceName = item.sourceName || this.fileNameFromUri(item.filePath);
    this.applyApplicationFont(registeredFamily);
    this.saveFontSettings();
    promptAction.showToast({ message: `已选择字体：${this.readerFontSourceName}` });
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

  applyApplicationFont(familyName: string): void {
    try {
      getContext(this).getApplicationContext().setFont(familyName || '');
    } catch (e) {
      console.warn('应用阅读字体失败:', e);
    }
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
      this.selectSystemFont();
      return;
    }
    const customIndex = index - 1;
    if (customIndex >= 0 && customIndex < this.customFonts.length) {
      this.selectCustomFont(this.customFonts[customIndex]);
    }
  }

  isFontFile(name: string): boolean {
    const lower = (name || '').toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf') || lower.endsWith('.ttc');
  }

  fontExt(value: string): string {
    const lower = (value || '').toLowerCase();
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

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F0F2F5';
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

      Text('全局字体设置')
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
      Text('全局字体设置')
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Select(this.readerFontOptions())
        .selected(this.readerFontSelectedIndex())
        .value(this.readerFontValue())
        .font({ size: 14 })
        .fontColor(this.primaryTextColor())
        .backgroundColor(this.inputColor())
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
}
