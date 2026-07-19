import { router, promptAction } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { ThemeRuntime } from '../theme/ThemeRuntime';

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
struct CustomFontManagerPage {
  @StorageLink('readerFontFamily') readerFontFamily: string = '';
  @StorageLink('readerFontFilePath') readerFontFilePath: string = '';
  @StorageLink('readerFontSourceName') readerFontSourceName: string = '系统默认';
  @StorageLink('readerFontMode') readerFontMode: string = 'system';
  @StorageLink('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageLink('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @StorageLink('readerActiveFontFamily') readerActiveFontFamily: string = '';
  @StorageLink('readerFontRegistered') readerFontRegistered: boolean = false;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
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
          this.uploadPanel()

          this.sectionTitle('已上传字体')
          if (this.customFonts.length > 0) {
            Column({ space: 1 }) {
              ForEach(this.customFonts, (item: ReaderCustomFontItem) => {
                this.fontItem(item)
              })
            }
            .width('100%')
            .backgroundColor(this.cardColor())
          } else {
            this.emptyPanel()
          }
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
      this.saveCustomFonts(this.customFonts);
    } catch (e) {
      this.customFonts = [];
    }
  }

  saveCustomFonts(fonts: ReaderCustomFontItem[]): void {
    const data = new ReaderCustomFontData();
    data.fonts = this.cleanCustomFonts(fonts);
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

  async pickCustomFont(): Promise<void> {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['字体文件|.ttf', '字体文件|.otf', '字体文件|.ttc'];
      options.maxSelectNumber = 1;
      const result = await new picker.DocumentViewPicker(getContext(this)).select(options);
      if (!result || result.length === 0) {
        return;
      }
      const sourceUri = result[0];
      const context = getContext(this);
      const dir = `${context.filesDir}/reader_fonts`;
      await this.ensureDir(dir);
      const sourceName = this.fileNameFromUri(sourceUri);
      const destName = await this.uniqueFontFileName(dir, this.asciiStoredFontName(sourceName, Date.now()));
      const destPath = `${dir}/${destName}`;
      const copySource = sourceUri.startsWith('/') ? fileUri.getUriFromPath(sourceUri) : sourceUri;
      await fs.copy(copySource, fileUri.getUriFromPath(destPath));
      const familyName = this.familyNameForPath(destPath);

      const item = new ReaderCustomFontItem();
      item.familyName = familyName;
      item.filePath = destPath;
      item.sourceName = sourceName;
      const next = this.customFonts.slice();
      next.push(item);
      this.saveCustomFonts(next);
      if (this.registerCustomFont(item)) {
        promptAction.showToast({ message: '已上传字体，可返回阅读设置选择' });
      } else {
        promptAction.showToast({ message: '字体已保存，但注册失败' });
      }
    } catch (e) {
      console.error('上传字体失败:', e);
      promptAction.showToast({ message: '上传字体失败' });
    }
  }

  deleteCustomFont(item: ReaderCustomFontItem): void {
    const next = this.customFonts.filter((fontItem: ReaderCustomFontItem) =>
      fontItem.familyName !== item.familyName && fontItem.filePath !== item.filePath);
    this.saveCustomFonts(next);
    if (this.readerFontFilePath === item.filePath || this.readerFontFamily === item.familyName) {
      const systemFontFamily = this.refreshSystemFontFamily();
      this.readerFontMode = 'system';
      this.readerFontFamily = '';
      this.readerFontFilePath = '';
      this.readerFontSourceName = '系统默认';
      this.readerActiveFontFamily = '';
      this.readerFontRegistered = false;
      this.applyApplicationFont(systemFontFamily);
    }
    this.saveFontSettings();
    try {
      fs.unlinkSync(item.filePath);
    } catch (e) {
      console.warn('删除字体文件失败:', e);
    }
    promptAction.showToast({ message: '已删除字体' });
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
    const oldPath = item.filePath;
    const oldFamilyName = item.familyName;
    const result = ReaderFontHelper.registerFont(this.getUIContext(), fontItem);
    if (result.registered) {
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
    return this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext());
  }

  applyApplicationFont(familyName: string): void {
    try {
      getContext(this).getApplicationContext().setFont(familyName || '');
    } catch (e) {
      console.warn('应用阅读字体失败:', e);
    }
  }

  async ensureDir(path: string): Promise<void> {
    try {
      await fs.mkdir(path, true);
    } catch (e) {
    }
  }

  fontExt(uri: string): string {
    const lower = uri.toLowerCase();
    if (lower.includes('.otf')) return '.otf';
    if (lower.includes('.ttc')) return '.ttc';
    return '.ttf';
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

  familyNameForPath(filePath: string): string {
    return ReaderFontHelper.normalizeFontFamily(filePath);
  }

  normalizedFontFamily(filePath: string): string {
    return ReaderFontHelper.normalizeFontFamily(filePath);
  }

  previewFontFamily(item: ReaderCustomFontItem): string {
    if (item && item.filePath === this.readerFontFilePath && this.readerActiveFontFamily) {
      return this.readerActiveFontFamily;
    }
    return '';
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
    this.saveFontSettings();
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

  async uniqueFontFileName(dir: string, sourceName: string): Promise<string> {
    const safeName = this.sanitizeFontFileName(sourceName || `custom${this.fontExt(sourceName)}`);
    const dotIndex = safeName.lastIndexOf('.');
    const base = dotIndex > 0 ? safeName.substring(0, dotIndex) : safeName;
    const ext = dotIndex > 0 ? safeName.substring(dotIndex) : this.fontExt(safeName);
    let candidate = `${base}${ext}`;
    let index = 1;
    while (this.fontFileExists(`${dir}/${candidate}`)) {
      candidate = `${base}_${index}${ext}`;
      index++;
    }
    return candidate;
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

  sanitizeFontFileName(name: string): string {
    const source = this.fileNameFromUri(name || 'custom.ttf');
    const ext = this.fontExt(source);
    const rawBase = this.familyNameFromFontFileName(source).trim() || 'custom';
    const invalidChars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
    let base = '';
    for (let i = 0; i < rawBase.length; i++) {
      const ch = rawBase.charAt(i);
      base += invalidChars.includes(ch) ? '_' : ch;
    }
    base = base.trim() || 'custom';
    return `${base}${ext}`;
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

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
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

      Text('自定义字体')
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
  uploadPanel() {
    Row() {
      Column() {
        Text('上传字体')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text('支持 ttf / otf / ttc，上传后会出现在阅读设置的字体下拉框中')
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('+')
        .fontSize(24)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.buttonColor())
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.pickCustomFont();
    })
  }

  @Builder
  emptyPanel() {
    Column() {
      Text('还没有上传字体')
        .fontSize(16)
        .fontColor(this.subTextColor())
      Text('点击上方上传按钮添加字体文件')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 28, bottom: 28 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  fontItem(item: ReaderCustomFontItem) {
    Row() {
      Column() {
        Text(item.sourceName || item.familyName)
          .fontSize(16)
          .fontFamily(this.previewFontFamily(item))
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.filePath)
          .fontSize(11)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('删除')
        .fontSize(13)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width(54)
        .height(32)
        .borderRadius(16)
        .backgroundColor('#E53935')
        .onClick(() => {
          this.deleteCustomFont(item);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 68 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }
}
