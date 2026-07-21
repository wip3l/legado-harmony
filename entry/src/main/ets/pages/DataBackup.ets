import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { promptAction, router } from '@kit.ArkUI';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import {
  AppDataBackupImportSession,
  AppDataBackupSelection,
  AppDataBackupService
} from '../utils/AppDataBackupService';

@Entry
@Component
struct DataBackupPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State exportSources: boolean = true;
  @State exportBookshelf: boolean = true;
  @State exportProgress: boolean = true;
  @State exportBookmarks: boolean = true;
  @State exportLocalBooks: boolean = true;
  @State exportSettings: boolean = true;
  @State exportSearchHistory: boolean = false;
  @State importSources: boolean = false;
  @State importBookshelf: boolean = false;
  @State importProgress: boolean = false;
  @State importBookmarks: boolean = false;
  @State importLocalBooks: boolean = false;
  @State importSettings: boolean = false;
  @State importSearchHistory: boolean = false;
  @State importReady: boolean = false;
  @State importDescription: string = '请先选择备份文件';
  @State busy: boolean = false;
  @State busyText: string = '';
  private importSession: AppDataBackupImportSession | null = null;

  aboutToAppear(): void {
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack() {
      Column() {
        this.titleBar()
        Scroll() {
          Column() {
            this.sectionTitle('导出数据')
            this.selectionCard(true)
            Button('选择保存位置并导出')
              .width('calc(100% - 24vp)')
              .height(46)
              .margin({ left: 12, right: 12, top: 12 })
              .enabled(!this.busy && this.hasExportSelection())
              .opacity(this.hasExportSelection() ? 1 : 0.45)
              .backgroundColor(this.accentColor())
              .onClick(() => this.exportData())

            this.sectionTitle('导入数据')
            Column() {
              Button(this.importReady ? '重新选择备份文件' : '选择备份文件')
                .width('100%')
                .height(44)
                .backgroundColor(this.softColor())
                .fontColor(this.primaryTextColor())
                .enabled(!this.busy)
                .onClick(() => this.chooseImportFile())

              Text(this.importDescription)
                .fontSize(12)
                .fontColor(this.subTextColor())
                .width('100%')
                .margin({ top: 10 })
            }
            .width('calc(100% - 24vp)')
            .padding(14)
            .margin({ left: 12, right: 12 })
            .borderRadius(16)
            .backgroundColor(this.cardColor())

            if (this.importReady) {
              this.selectionCard(false)
              Button('导入所选数据')
                .width('calc(100% - 24vp)')
                .height(46)
                .margin({ left: 12, right: 12, top: 12 })
                .enabled(!this.busy && this.hasImportSelection())
                .opacity(this.hasImportSelection() ? 1 : 0.45)
                .backgroundColor(this.accentColor())
                .onClick(() => this.importData())
            }

            Text('导入采用同类数据合并与覆盖方式，不会先清空整套应用数据。设置和自定义资源导入后建议重新启动应用。')
              .fontSize(12)
              .fontColor(this.subTextColor())
              .width('calc(100% - 32vp)')
              .margin({ left: 16, right: 16, top: 16, bottom: 32 })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
      .backgroundColor(this.pageColor())

      if (this.busy) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(42)
            .height(42)
            .color(this.accentColor())
          Text(this.busyText || '正在处理...')
            .fontSize(14)
            .fontColor(this.primaryTextColor())
        }
        .width(180)
        .padding(22)
        .borderRadius(16)
        .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
        .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('数据导入与导出')
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
  selectionCard(exporting: boolean) {
    Column() {
      this.selectionRow('书源', '规则、分组、排序、启用和登录配置', exporting,
        AppDataBackupService.CATEGORY_SOURCES)
      this.selectionRow('书架', '网络书籍、书架分组、标签和单书配置', exporting,
        AppDataBackupService.CATEGORY_BOOKSHELF)
      this.selectionRow('阅读进度', '当前章节、页码、阅读时间及单书状态', exporting,
        AppDataBackupService.CATEGORY_PROGRESS)
      this.selectionRow('书签', '章节位置和书签正文', exporting,
        AppDataBackupService.CATEGORY_BOOKMARKS)
      this.selectionRow('本地图书', 'TXT/EPUB 原文件及本地书籍信息', exporting,
        AppDataBackupService.CATEGORY_LOCAL_BOOKS)
      this.selectionRow('自定义设置与资源', '阅读、主题、字体、封面、TTS、替换规则等', exporting,
        AppDataBackupService.CATEGORY_SETTINGS)
      this.selectionRow('搜索历史', '搜索关键词和使用次数', exporting,
        AppDataBackupService.CATEGORY_SEARCH_HISTORY, false)
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12 })
    .borderRadius(16)
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  @Builder
  selectionRow(title: string, desc: string, exporting: boolean, category: string, divider: boolean = true) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(11)
          .fontColor(this.subTextColor())
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Checkbox, isOn: this.selectionValue(exporting, category) })
        .selectedColor(this.accentColor())
        .enabled(exporting || this.importCategoryAvailable(category))
        .opacity(exporting || this.importCategoryAvailable(category) ? 1 : 0.35)
        .onChange((value: boolean) => this.setSelectionValue(exporting, category, value))
    }
    .width('calc(100% - 28vp)')
    .height(68)
    .padding({ top: 9, bottom: 9 })
    .margin({ left: 14, right: 14 })
    .border({ width: { bottom: divider ? 0.5 : 0 }, color: this.dividerColor() })
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

  selectionValue(exporting: boolean, category: string): boolean {
    if (category === AppDataBackupService.CATEGORY_SOURCES) return exporting ? this.exportSources : this.importSources;
    if (category === AppDataBackupService.CATEGORY_BOOKSHELF) return exporting ? this.exportBookshelf : this.importBookshelf;
    if (category === AppDataBackupService.CATEGORY_PROGRESS) return exporting ? this.exportProgress : this.importProgress;
    if (category === AppDataBackupService.CATEGORY_BOOKMARKS) return exporting ? this.exportBookmarks : this.importBookmarks;
    if (category === AppDataBackupService.CATEGORY_LOCAL_BOOKS) return exporting ? this.exportLocalBooks : this.importLocalBooks;
    if (category === AppDataBackupService.CATEGORY_SETTINGS) return exporting ? this.exportSettings : this.importSettings;
    return exporting ? this.exportSearchHistory : this.importSearchHistory;
  }

  setSelectionValue(exporting: boolean, category: string, value: boolean): void {
    if (!exporting && !this.importCategoryAvailable(category)) return;
    if (category === AppDataBackupService.CATEGORY_SOURCES) exporting ? this.exportSources = value : this.importSources = value;
    else if (category === AppDataBackupService.CATEGORY_BOOKSHELF) exporting ? this.exportBookshelf = value : this.importBookshelf = value;
    else if (category === AppDataBackupService.CATEGORY_PROGRESS) exporting ? this.exportProgress = value : this.importProgress = value;
    else if (category === AppDataBackupService.CATEGORY_BOOKMARKS) exporting ? this.exportBookmarks = value : this.importBookmarks = value;
    else if (category === AppDataBackupService.CATEGORY_LOCAL_BOOKS) exporting ? this.exportLocalBooks = value : this.importLocalBooks = value;
    else if (category === AppDataBackupService.CATEGORY_SETTINGS) exporting ? this.exportSettings = value : this.importSettings = value;
    else exporting ? this.exportSearchHistory = value : this.importSearchHistory = value;
  }

  selection(exporting: boolean): AppDataBackupSelection {
    const value = new AppDataBackupSelection();
    value.sources = exporting ? this.exportSources : this.importSources;
    value.bookshelf = exporting ? this.exportBookshelf : this.importBookshelf;
    value.progress = exporting ? this.exportProgress : this.importProgress;
    value.bookmarks = exporting ? this.exportBookmarks : this.importBookmarks;
    value.localBooks = exporting ? this.exportLocalBooks : this.importLocalBooks;
    value.settings = exporting ? this.exportSettings : this.importSettings;
    value.searchHistory = exporting ? this.exportSearchHistory : this.importSearchHistory;
    return value;
  }

  hasExportSelection(): boolean {
    const value = this.selection(true);
    return value.sources || value.bookshelf || value.progress || value.bookmarks || value.localBooks ||
      value.settings || value.searchHistory;
  }

  hasImportSelection(): boolean {
    const value = this.selection(false);
    return value.sources || value.bookshelf || value.progress || value.bookmarks || value.localBooks ||
      value.settings || value.searchHistory;
  }

  importCategoryAvailable(category: string): boolean {
    return !!this.importSession && AppDataBackupService.hasCategory(this.importSession.manifest, category);
  }

  async exportData(): Promise<void> {
    if (this.busy || !this.hasExportSelection()) return;
    this.busy = true;
    this.busyText = '正在整理备份数据...';
    try {
      const backup = await AppDataBackupService.createBackup(getContext(this), this.selection(true));
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`legado_harmony_${this.timestamp()}.qingyebak`];
      options.fileSuffixChoices = ['应用数据备份|.qingyebak'];
      const result = await new picker.DocumentViewPicker(getContext(this)).save(options);
      if (!result || result.length === 0) return;
      this.busyText = '正在写入备份文件...';
      await fs.copy(fileUri.getUriFromPath(backup.archivePath), result[0]);
      promptAction.showToast({ message: '应用数据已导出' });
    } catch (e) {
      console.error('导出应用数据失败:', e);
      promptAction.showToast({ message: `导出失败：${e instanceof Error ? e.message : String(e)}` });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  async chooseImportFile(): Promise<void> {
    if (this.busy) return;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['应用数据备份|.qingyebak'];
      const result = await new picker.DocumentViewPicker(getContext(this)).select(options);
      if (!result || result.length === 0) return;
      this.busy = true;
      this.busyText = '正在读取备份文件...';
      this.importSession = await AppDataBackupService.prepareImport(getContext(this), result[0]);
      this.importReady = true;
      const manifest = this.importSession.manifest;
      this.importSources = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_SOURCES);
      this.importBookshelf = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_BOOKSHELF);
      this.importProgress = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_PROGRESS);
      this.importBookmarks = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_BOOKMARKS);
      this.importLocalBooks = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_LOCAL_BOOKS);
      this.importSettings = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_SETTINGS);
      this.importSearchHistory = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_SEARCH_HISTORY);
      this.importDescription = `备份时间：${new Date(manifest.createdAt).toLocaleString()}；可按需取消不想导入的项目。`;
    } catch (e) {
      console.error('读取应用备份失败:', e);
      this.importSession = null;
      this.importReady = false;
      this.importDescription = '备份文件读取失败';
      promptAction.showToast({ message: `读取失败：${e instanceof Error ? e.message : String(e)}` });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  async importData(): Promise<void> {
    if (this.busy || !this.importSession || !this.hasImportSelection()) return;
    const confirmation = await promptAction.showDialog({
      title: '确认导入数据',
      message: '所选数据会合并到当前应用；相同书籍、书源和设置将以备份内容更新。是否继续？',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '继续导入', color: this.accentColor() }
      ]
    });
    if (confirmation.index !== 1) return;
    this.busy = true;
    this.busyText = '正在导入所选数据...';
    try {
      const result = await AppDataBackupService.importBackup(getContext(this), this.importSession,
        this.selection(false));
      promptAction.showToast({ message: `导入完成：${result.summary()}` });
      this.importDescription = `导入完成：${result.summary()}。设置项重启应用后完全生效。`;
    } catch (e) {
      console.error('导入应用数据失败:', e);
      promptAction.showToast({ message: `导入失败：${e instanceof Error ? e.message : String(e)}` });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  timestamp(): string {
    const date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_` +
      `${pad(date.getHours())}${pad(date.getMinutes())}`;
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  softColor(): string { return this.appDarkMode ? '#24272D' : '#EEF2F7'; }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  dividerColor(): string { return this.appDarkMode ? '#24FFFFFF' : '#14000000'; }
  accentColor(): string { return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor; }
}
