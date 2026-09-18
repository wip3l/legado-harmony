import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { promptAction, router } from '@kit.ArkUI';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import {
  AppDataBackupImportSession,
  AppDataBackupSelection,
  AppDataBackupService
} from '../utils/AppDataBackupService';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';

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
  @State mode: string = 'export';
  @State busy: boolean = false;
  @State busyText: string = '';
  @State busyProgress: number = 0;
  private exportPasswordDialogSession: SystemDialogSession = new SystemDialogSession();
  private importPasswordDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showExportPasswordDialog: boolean = false;
  @State @Watch('onSystemDialogFlagChanged') showImportPasswordDialog: boolean = false;
  @State exportPassword: string = '';
  @State exportPasswordConfirm: string = '';
  @State importPassword: string = '';
  @State passwordError: string = '';
  private importSession: AppDataBackupImportSession | null = null;
  private pendingImportUri: string = '';
  private tempCleanupTask: Promise<void> | null = null;

  aboutToAppear(): void {
    this.syncBars();
    const params = router.getParams() as Record<string, string>;
    this.mode = params?.['mode'] === 'import' ? 'import' : 'export';
    this.tempCleanupTask = AppDataBackupService.cleanupStaleTempFiles(getContext(this)).catch((error: Error) => {
      console.warn('清理遗留备份临时文件失败:', error);
    });
  }

  onPageShow(): void {
    this.syncBars();
  }

  onBackPress(): boolean {
    return this.busy;
  }

  aboutToDisappear(): void {
    const session = this.importSession;
    this.importSession = null;
    AppDataBackupService.discardImport(session);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          Row()
            .height(56 + this.statusBarHeight)

          if (this.mode === 'export') {
            this.sectionTitle('选择导出内容')
            this.selectionCard(true)
            Text('备份将使用密码和 AES-256-GCM 加密；Cookie、密码、Token、授权信息及登录 Header 不会写入备份。')
              .fontSize(12)
              .fontColor(this.subTextColor())
              .width('calc(100% - 32vp)')
              .margin({ left: 16, right: 16, top: 10 })
            Button('选择保存位置并导出')
              .width('calc(100% - 24vp)')
              .height(46)
              .margin({ left: 12, right: 12, top: 12 })
              .enabled(!this.busy && this.hasExportSelection())
              .opacity(this.hasExportSelection() ? 1 : 0.45)
              .backgroundColor(this.accentColor())
              .onClick(() => this.requestExport())
          } else {
            this.sectionTitle('选择备份文件')
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
              this.sectionTitle('选择导入内容')
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
              .margin({ left: 16, right: 16, top: 16 })
          }

          Row()
            .height(32 + this.navBarHeight)
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor(this.pageColor())

      this.titleBar()



      if (this.busy) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#66000000')

          Column({ space: 12 }) {
            LoadingProgress()
              .width(42)
              .height(42)
              .color(this.accentColor())
            Text(this.busyText || '正在处理...')
              .fontSize(14)
              .fontColor(this.primaryTextColor())
              .textAlign(TextAlign.Center)
              .width('100%')
            if (this.busyProgress > 0) {
              Text(`${this.busyProgress}%`)
                .fontSize(12)
                .fontColor(this.subTextColor())
            }
          }
          .width(240)
          .padding(22)
          .borderRadius(16)
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
        }
        .width('100%')
        .height('100%')
        .zIndex(30)
        .hitTestBehavior(HitTestMode.Block)
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text(this.mode === 'import' ? '数据导入' : '数据导出')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ top: this.statusBarHeight })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  selectionCard(exporting: boolean) {
    Column() {
      this.selectionRow('书源', '规则、分组、排序和启用状态；不含登录凭据', exporting,
        AppDataBackupService.CATEGORY_SOURCES)
      this.selectionRow('书架', '网络书籍、书架分组、标签和单书配置', exporting,
        AppDataBackupService.CATEGORY_BOOKSHELF)
      this.selectionRow('阅读进度', '当前章节、页码、阅读时间及单书状态', exporting,
        AppDataBackupService.CATEGORY_PROGRESS)
      this.selectionRow('书签', '章节位置和书签正文', exporting,
        AppDataBackupService.CATEGORY_BOOKMARKS)
      this.selectionRow('本地图书', 'TXT/EPUB 原文件及本地书籍信息', exporting,
        AppDataBackupService.CATEGORY_LOCAL_BOOKS)
      this.selectionRow('自定义设置与资源', '阅读、主题、字体、封面、TTS、替换规则等；敏感字段会清除', exporting,
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


  onSystemDialogFlagChanged(): void {
    if (!this.showExportPasswordDialog) this.exportPasswordDialogSession.close(this.getUIContext());
    if (!this.showImportPasswordDialog) this.importPasswordDialogSession.close(this.getUIContext());
  }

  openExportPasswordDialog(): void {
    this.showExportPasswordDialog = true;
    this.exportPasswordDialogSession.open(this.getUIContext(), (): void => {
      this.exportPasswordDialogContent();
    }, {
      autoCancel: true,
      maskColor: this.appDarkMode ? '#99000000' : '#33000000',
      warnTag: '显示导出密码弹窗失败:'
    });
  }

  openImportPasswordDialog(): void {
    this.showImportPasswordDialog = true;
    this.importPasswordDialogSession.open(this.getUIContext(), (): void => {
      this.importPasswordDialogContent();
    }, {
      autoCancel: true,
      maskColor: this.appDarkMode ? '#99000000' : '#33000000',
      warnTag: '显示导入密码弹窗失败:'
    });
  }

  @Builder
  exportPasswordDialogContent() {
    this.passwordDialogContent(true)
  }

  @Builder
  importPasswordDialogContent() {
    this.passwordDialogContent(false)
  }

  @Builder
  passwordDialogContent(exporting: boolean) {
    Column() {
      Text(exporting ? '设置备份密码' : '输入备份密码')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      Text(exporting ? '密码至少 8 个字符。密码不会被保存，遗忘后无法恢复此备份。' :
        '该备份已加密，请输入创建备份时设置的密码。')
        .fontSize(12)
        .fontColor(this.subTextColor())
        .lineHeight(18)
        .width('100%')
        .margin({ top: 8, bottom: 14 })

      TextInput({
        text: exporting ? this.exportPassword : this.importPassword,
        placeholder: exporting ? '输入备份密码' : '输入密码'
      })
        .type(InputType.Password)
        .height(44)
        .fontColor(this.primaryTextColor())
        .backgroundColor(this.softColor())
        .onChange((value: string) => {
          if (exporting) this.exportPassword = value;
          else this.importPassword = value;
          this.passwordError = '';
        })

      if (exporting) {
        TextInput({ text: this.exportPasswordConfirm, placeholder: '再次输入密码' })
          .type(InputType.Password)
          .height(44)
          .fontColor(this.primaryTextColor())
          .backgroundColor(this.softColor())
          .margin({ top: 10 })
          .onChange((value: string) => {
            this.exportPasswordConfirm = value;
            this.passwordError = '';
          })
      }

      if (this.passwordError) {
        Text(this.passwordError)
          .fontSize(12)
          .fontColor('#E84026')
          .width('100%')
          .margin({ top: 9 })
      }

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.softColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closePasswordDialog(exporting))
        Button(exporting ? '继续导出' : '解密备份')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.accentColor())
          .onClick(() => {
            if (exporting) this.confirmExportPassword();
            else this.confirmImportPassword();
          })
      }
      .width('100%')
      .margin({ top: 18 })
    }    .padding(20)
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

  requestExport(): void {
    if (this.busy || !this.hasExportSelection()) return;
    this.exportPassword = '';
    this.exportPasswordConfirm = '';
    this.passwordError = '';
    this.openExportPasswordDialog();
  }

  closePasswordDialog(exporting: boolean): void {
    this.passwordError = '';
    if (exporting) {
      this.exportPassword = '';
      this.exportPasswordConfirm = '';
      this.showExportPasswordDialog = false;
    } else {
      this.importPassword = '';
      this.showImportPasswordDialog = false;
    }
  }

  confirmExportPassword(): void {
    if (this.exportPassword.length < 8) {
      this.passwordError = '密码至少需要 8 个字符';
      return;
    }
    if (this.exportPassword !== this.exportPasswordConfirm) {
      this.passwordError = '两次输入的密码不一致';
      return;
    }
    const password = this.exportPassword;
    this.exportPassword = '';
    this.exportPasswordConfirm = '';
    this.passwordError = '';
    this.showExportPasswordDialog = false;
    this.exportData(password);
  }

  confirmImportPassword(): void {
    if (!this.importPassword) {
      this.passwordError = '请输入备份密码';
      return;
    }
    this.loadImportFile(this.importPassword, false);
  }

  async exportData(password: string): Promise<void> {
    if (this.busy || !this.hasExportSelection()) return;
    this.busy = true;
    this.busyText = '请选择备份保存位置...';
    this.busyProgress = 1;
    let archivePath = '';
    try {
      await this.awaitTempCleanup();
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`legado_harmony_${this.timestamp()}.qingyebak`];
      options.fileSuffixChoices = ['应用数据备份|.qingyebak'];
      const result = await new picker.DocumentViewPicker(getContext(this)).save(options);
      if (!result || result.length === 0) return;
      this.busyText = '正在整理备份数据...';
      const backup = await AppDataBackupService.createBackup(getContext(this), this.selection(true), password,
        (message: string, percent: number): void => {
          this.busyText = message;
          this.busyProgress = percent;
        });
      archivePath = backup.archivePath;
      this.busyText = '正在写入备份文件...';
      this.busyProgress = 97;
      await this.writeBackupToUri(backup.archivePath, result[0]);
      this.busyProgress = 100;
      HdsFeedback.showToast('加密备份已导出');
    } catch (e) {
      console.error('导出应用数据失败:', e);
      HdsFeedback.showToast(`导出失败：${e instanceof Error ? e.message : String(e)}`);
    } finally {
      await AppDataBackupService.discardExport(archivePath);
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async chooseImportFile(): Promise<void> {
    if (this.busy) return;
    try {
      await this.awaitTempCleanup();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['应用数据备份|.qingyebak', 'Android 阅读备份|.zip'];
      const result = await new picker.DocumentViewPicker(getContext(this)).select(options);
      if (!result || result.length === 0) return;
      await AppDataBackupService.discardImport(this.importSession);
      this.pendingImportUri = result[0];
      this.importSession = null;
      this.importReady = false;
      this.importPassword = '';
      this.passwordError = '';
      await this.loadImportFile('', true);
    } catch (e) {
      console.error('选择应用备份失败:', e);
      HdsFeedback.showToast(`选择失败：${e instanceof Error ? e.message : String(e)}`);
    }
  }

  async loadImportFile(password: string, allowPasswordPrompt: boolean): Promise<void> {
    if (!this.pendingImportUri || this.busy) return;
    this.busy = true;
    this.busyText = password ? '正在解密备份文件...' : '正在读取备份文件...';
    this.busyProgress = 1;
    try {
      this.importSession = await AppDataBackupService.prepareImport(
        getContext(this), this.pendingImportUri, password,
        (message: string, percent: number): void => {
          this.busyText = message;
          this.busyProgress = percent;
        });
      this.importReady = true;
      this.showImportPasswordDialog = false;
      this.importPassword = '';
      this.passwordError = '';
      const manifest = this.importSession.manifest;
      this.importSources = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_SOURCES);
      this.importBookshelf = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_BOOKSHELF);
      this.importProgress = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_PROGRESS);
      this.importBookmarks = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_BOOKMARKS);
      this.importLocalBooks = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_LOCAL_BOOKS);
      this.importSettings = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_SETTINGS);
      this.importSearchHistory = AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_SEARCH_HISTORY);
      if (this.importSession.sourceFormat === AppDataBackupService.SOURCE_FORMAT_ANDROID) {
        this.importDescription = '已识别 Android 阅读 ZIP 备份；可转换导入书源、HTTP TTS、网络书架、' +
          '阅读进度、自定义分组、替换规则和搜索历史。本地书及其他不兼容数据会跳过；' +
          '原备份未加密，可能包含敏感配置。';
      } else {
        const security = this.importSession.encrypted && manifest.version >= 2 && manifest.sensitiveDataExcluded ?
          '已加密，且不含登录凭据等敏感字段' :
          (this.importSession.encrypted ? '已加密，但旧版数据可能包含敏感字段' :
            '旧版未加密备份，可能包含敏感字段');
        this.importDescription = `备份时间：${new Date(manifest.createdAt).toLocaleString()}；${security}；` +
          '可按需取消不想导入的项目。';
      }
    } catch (e) {
      console.error('读取应用备份失败:', e);
      const message = e instanceof Error ? e.message : String(e);
      this.importSession = null;
      this.importReady = false;
      if (allowPasswordPrompt && message === AppDataBackupService.PASSWORD_REQUIRED_MESSAGE) {
        this.importDescription = '该备份已加密，请输入密码';
        this.importPassword = '';
        this.passwordError = '';
        this.openImportPasswordDialog();
      } else {
        this.importDescription = '备份文件读取失败';
        this.passwordError = message;
        if (this.showImportPasswordDialog) {
          this.passwordError = message;
        } else {
          HdsFeedback.showToast(`读取失败：${message}`);
        }
      }
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
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
    this.busyProgress = 0;
    try {
      const result = await AppDataBackupService.importBackup(getContext(this), this.importSession,
        this.selection(false), (message: string, percent: number): void => {
          this.busyText = message;
          this.busyProgress = percent;
        });
      HdsFeedback.showToast(`导入完成：${result.summary()}`);
      this.importDescription = `导入完成：${result.summary()}。设置项重启应用后完全生效。`;
      await AppDataBackupService.discardImport(this.importSession);
      this.importSession = null;
      this.importReady = false;
    } catch (e) {
      console.error('导入应用数据失败:', e);
      HdsFeedback.showToast(`导入失败：${e instanceof Error ? e.message : String(e)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  timestamp(): string {
    const date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_` +
      `${pad(date.getHours())}${pad(date.getMinutes())}`;
  }

  async awaitTempCleanup(): Promise<void> {
    const task = this.tempCleanupTask;
    this.tempCleanupTask = null;
    if (task) await task;
  }

  async writeBackupToUri(sourcePath: string, targetUri: string): Promise<void> {
    let source: fs.File | null = null;
    let target: fs.File | null = null;
    let stage = '检查临时备份文件';
    try {
      const stat = await fs.stat(sourcePath);
      stage = '打开临时备份文件';
      source = await fs.open(sourcePath, fs.OpenMode.READ_ONLY);
      // DocumentViewPicker.save() has already created the target file and grants
      // temporary read/write access to its URI. CREATE/TRUNC are path operations
      // and can make the user-file service reject the URI with ENOENT/EINVAL.
      stage = '打开所选目标文件';
      target = await fs.open(targetUri, fs.OpenMode.READ_WRITE);
      stage = '写入所选目标文件';
      let processed = 0;
      const chunkSize = 256 * 1024;
      while (true) {
        const buffer = new ArrayBuffer(chunkSize);
        // Omitting offset makes fs.read advance the file pointer. Supplying
        // offset: 0 can repeatedly read the same chunk on some OS versions.
        const length = await fs.read(source.fd, buffer);
        if (length <= 0) break;
        let written = 0;
        while (written < length) {
          const remaining = new Uint8Array(buffer, written, length - written);
          const owned = new Uint8Array(remaining.length);
          owned.set(remaining);
          // The target file pointer must advance as partial writes complete.
          const count = await fs.write(target.fd, owned.buffer);
          if (count <= 0) throw new Error('目标文件写入失败');
          written += count;
        }
        processed += length;
        const ratio = stat.size > 0 ? processed / stat.size : 1;
        this.busyProgress = 97 + Math.min(2, Math.floor(ratio * 2));
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`${stage}失败：${message}`);
    } finally {
      if (source) {
        try { await fs.close(source); } catch (_) {}
      }
      if (target) {
        try { await fs.close(target); } catch (_) {}
      }
    }
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
