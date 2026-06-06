import { router, promptAction, font } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';

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
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State customFonts: ReaderCustomFontItem[] = [];

  aboutToAppear(): void {
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
      const familyName = `ReaderCustomFont_${Date.now()}`;
      const destPath = `${dir}/${familyName}${this.fontExt(sourceUri)}`;
      const copySource = sourceUri.startsWith('/') ? fileUri.getUriFromPath(sourceUri) : sourceUri;
      await fs.copy(copySource, fileUri.getUriFromPath(destPath));

      const item = new ReaderCustomFontItem();
      item.familyName = familyName;
      item.filePath = destPath;
      item.sourceName = this.fileNameFromUri(sourceUri);
      const next = this.customFonts.slice();
      next.push(item);
      this.saveCustomFonts(next);
      this.registerCustomFont(item);
      promptAction.showToast({ message: '已上传字体，可返回阅读设置选择' });
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
      const systemFontFamily = this.readerSystemFontFamily || '';
      this.readerFontMode = 'system';
      this.readerSystemFontFamily = systemFontFamily;
      this.readerFontFamily = systemFontFamily;
      this.readerFontFilePath = '';
      this.readerFontSourceName = systemFontFamily || '系统默认';
    }
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

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F0F2F5';
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
        .backgroundColor('#007DFF')
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
          .fontFamily(item.familyName)
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
