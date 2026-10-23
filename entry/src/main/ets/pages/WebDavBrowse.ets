import { router, promptAction } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { Book } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { LocalBookService } from '../core/book/LocalBookService';
import { WebDavBookService } from '../webdav/WebDavBookService';
import { WebDavClient } from '../webdav/WebDavClient';
import { WebDavError } from '../webdav/WebDavError';
import { WebDavConnection, WebDavEntry } from '../webdav/WebDavModels';
import { WebDavSecretStore } from '../webdav/WebDavSecretStore';
import { WebDavSettingsStore } from '../webdav/WebDavSettingsStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';

@Entry
@Component
struct WebDavBrowsePage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State connection: WebDavConnection = new WebDavConnection();
  @State pageTitle: string = '';
  @State connectionMissing: boolean = false;
  @State currentPath: string = '';
  @State entries: WebDavEntry[] = [];
  @State busy: boolean = false;
  @State busyText: string = '';
  @State busyProgress: number = 0;
  @State errorMessage: string = '';
  @State showEntryActionMenu: boolean = false;
  @State actionEntryPath: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State @Watch('onSystemDialogFlagChanged') showEntryNameDialog: boolean = false;
  @State entryNameMode: string = '';
  @State entryNameDraft: string = '';
  @State @Watch('onFileDetailFlagChanged') showFileDetail: boolean = false;
  @State fileDetailEntry: WebDavEntry = new WebDavEntry();
  @State fileDetailBook: Book | null = null;
  private pendingPreviewBook: Book | null = null;
  private readonly fileDetailDialogSession: SystemDialogSession = new SystemDialogSession();
  private entryNameDialogSession: SystemDialogSession = new SystemDialogSession();
  private password: string = '';
  private client: WebDavClient | null = null;
  private initialized: boolean = false;

  aboutToAppear(): void {
    this.syncBars();
    if (this.initialized) return;
    this.initialized = true;
    this.bootstrap();
  }

  onPageShow(): void {
    this.syncBars();
    if (this.pendingPreviewBook) {
      const book = this.pendingPreviewBook;
      this.pendingPreviewBook = null;
      this.confirmPreviewShelf(book);
    }
  }

  onBackPress(): boolean {
    if (this.showEntryActionMenu) {
      this.closeEntryActions();
      return true;
    }
    if (this.currentPath) {
      if (!this.busy) this.goParent();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: this.currentTitle(), scrollable: false, content: () => {
        this.pageContent()
      } })

      if (this.showEntryActionMenu) {
        this.entryActionMenu()
      }

      if (this.busy) {
        Column({ space: AppSpacing.LG }) {
          Progress({ value: this.busyProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.accentColor())
          Text(this.busyText || '处理中...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
        }
        .width('78%')
        .padding(AppSpacing.XXL)
        .borderRadius(ThemeRuntime.cardRadius())
        .backgroundColor(this.cardColor())
        .shadow({ radius: 18, color: this.appDarkMode ? '#66000000' : '#28000000' })
        .position({ x: '11%', y: '42%' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .onAreaChange((_oldValue: Area, newValue: Area) => this.updateContextViewport(newValue))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    if (this.connectionMissing || this.errorMessage) {
      this.errorView();
    } else {
      this.filesPanel();
    }
  }

  @Builder
  errorView() {
    Column({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(42)
        .fontColor([this.subTextColor()])
      Text(this.errorMessage || '连接配置不存在')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
      if (this.connectionMissing) {
        Button('返回')
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => router.back())
      } else {
        Button('重试')
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => this.retry())
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(36)
  }

  @Builder
  filesPanel() {
    Column() {
      Row({ space: AppSpacing.MD }) {
        if (this.currentPath) {
          Button('上一级')
            .height(34)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.accentColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.goParent())
        }
        Column() {
          Text(this.connection.name)
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
          Text(this.currentPath ? `/${this.currentPath}` : '/')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        this.fileToolbarButton('新建', () => this.openCreateFolderDialog())
        this.fileToolbarButton('上传', () => this.chooseAndUploadFiles())
        this.fileToolbarButton('刷新', () => this.refreshFiles())
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG, bottom: AppSpacing.MD })
      .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
      .zIndex(2)

      if (this.entries.length === 0) {
        Column({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(40)
            .fontColor([this.subTextColor()])
          Text('这个目录还是空的')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 1 }) {
          ListItem() {
            Row()
              .height(this.fileListTopInset())
              .hitTestBehavior(HitTestMode.None)
          }

          ForEach(this.entries, (entry: WebDavEntry) => {
            ListItem() {
              Row({ space: AppSpacing.LG }) {
                SymbolGlyph($r(entry.directory ? 'sys.symbol.folder' : 'sys.symbol.doc'))
                  .fontSize(26)
                  .fontColor([entry.directory ? this.accentColor() : this.subTextColor()])
                Column({ space: AppSpacing.XS }) {
                  Text(entry.name)
                    .fontSize(AppFontSize.BODY_LARGE)
                    .fontColor(this.primaryTextColor())
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(entry.directory ? '文件夹' : this.fileDescription(entry))
                    .fontSize(AppFontSize.CAPTION)
                    .fontColor(this.subTextColor())
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                if (entry.directory || entry.readableBook()) {
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(17)
                    .fontColor([this.subTextColor()])
                }
              }
              .width('100%')
              .height(64)
              .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
              .backgroundColor(this.cardColor())
              .gesture(
                LongPressGesture({ repeat: false })
                  .onAction((event: GestureEvent) => {
                    if (!this.busy) this.openEntryActions(entry, event);
                  })
              )
              .onClick(() => {
                if (!this.showEntryActionMenu && !this.showEntryNameDialog) this.openEntry(entry);
              })
            }
          }, (entry: WebDavEntry) => `${entry.relativePath}_${entry.etag}_${entry.lastModified}`)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .margin({ top: -this.fileListTopInset() })
        .zIndex(0)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  fileToolbarButton(label: string, action: () => void) {
    Button(label)
      .height(34)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.accentColor())
      .backgroundColor(this.softColor())
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
      .onClick(action)
  }

  @Builder
  entryActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#38000000' : '#18FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('button', 12))
        .onClick(() => this.closeEntryActions())
      Column() {
        this.entryContextActionItem($r('sys.symbol.square_and_pencil'), '重命名', this.primaryTextColor(),
          () => this.openRenameEntryDialog())
        this.entryContextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode),
          () => this.confirmDeleteEntry())
      }
      .width(148)
      .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.contextMenuLeft(148), y: this.contextMenuTop(100) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  entryContextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    Row({ space: AppSpacing.MD }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([color])
        .width(24)
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(color)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  onSystemDialogFlagChanged(): void {
    if (!this.showEntryNameDialog) this.entryNameDialogSession.close(this.getUIContext());
  }

  openEntryNameDialog(): void {
    this.showEntryNameDialog = true;
    this.entryNameDialogSession.open(this.getUIContext(), (): void => {
      this.entryNameDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示文件命名弹窗失败:',
      onDismiss: (): void => {
        this.showEntryNameDialog = false;
      }
    });
  }

  @Builder
  entryNameDialogContent() {
    Column() {
      Text(this.entryNameMode === 'create' ? '创建文件夹' : '重命名')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.LG })
      TextInput({ text: this.entryNameDraft,
        placeholder: this.entryNameMode === 'create' ? '文件夹名称' : '新名称' })
        .width('100%')
        .height(44)
        .backgroundColor(this.softColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .onChange((value: string) => {
          this.entryNameDraft = value;
        })
      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.softColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeEntryNameDialog())
        Button(this.entryNameMode === 'create' ? '创建' : '保存')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.accentColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => this.submitEntryNameDialog())
      }
      .width('100%')
      .margin({ top: AppSpacing.LG })
    }
    .padding(AppSpacing.XXL)
  }

  async bootstrap(): Promise<void> {
    const params = router.getParams() as Record<string, string>;
    const connectionId = params?.['connectionId'] || '';
    const pageTitle = (params?.['title'] || '').trim();
    const context = getContext(this);
    let connections: WebDavConnection[] = [];
    try {
      connections = await WebDavSettingsStore.loadConnections(context);
    } catch (error) {
      this.errorMessage = this.message(error);
      return;
    }
    const found = connections.find((item: WebDavConnection): boolean => item.id === connectionId);
    if (!found) {
      this.connectionMissing = true;
      this.errorMessage = '连接配置不存在';
      return;
    }
    this.connection = found;
    this.pageTitle = pageTitle || found.name;
    try {
      this.password = await WebDavSecretStore.password(context, found.id);
    } catch (_) {
      this.password = '';
    }
    this.client = new WebDavClient(found, this.password);
    await this.refreshFiles();
  }

  async refreshFiles(): Promise<void> {
    const client = this.client;
    if (!client || this.busy) return;
    this.busy = true;
    this.busyText = '正在读取远端目录...';
    this.busyProgress = 35;
    try {
      this.entries = await client.list(this.currentPath);
      this.errorMessage = '';
      this.busyProgress = 100;
    } catch (error) {
      this.entries = [];
      this.errorMessage = `读取失败：${this.message(error)}`;
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  retry(): void {
    if (this.connectionMissing) return;
    if (!this.client) {
      this.bootstrap();
      return;
    }
    this.refreshFiles();
  }

  async openEntry(entry: WebDavEntry): Promise<void> {
    if (entry.directory) {
      this.currentPath = entry.relativePath;
      await this.refreshFiles();
      return;
    }
    if (!entry.readableBook()) {
      HdsFeedback.showToast('当前仅支持 TXT、EPUB 和 MOBI');
      return;
    }
    this.openFileDetail(entry);
  }

  onFileDetailFlagChanged(): void {
    if (!this.showFileDetail) this.fileDetailDialogSession.close(this.getUIContext());
  }

  openFileDetail(entry: WebDavEntry): void {
    if (this.busy) return;
    const run = async (): Promise<void> => {
      let book: Book | null = null;
      try {
        const db = AppDatabase.getInstance();
        await db.initWithContext(getContext(this));
        const identity = LocalBookService.webDavBookUrl(this.connection.id, entry.relativePath);
        book = await db.getBook(identity);
      } catch (_) {
        book = null;
      }
      this.fileDetailEntry = entry;
      this.fileDetailBook = book;
      this.showFileDetail = true;
      this.fileDetailDialogSession.open(this.getUIContext(), (): void => {
        this.fileDetailDialogContent();
      }, {
        autoCancel: true,
        maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
        warnTag: '显示书籍详情弹窗失败:',
        onDismiss: (): void => {
          this.showFileDetail = false;
        }
      });
    };
    run();
  }

  @Builder
  fileDetailDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.LG }) {
        SymbolGlyph($r('sys.symbol.doc'))
          .fontSize(30)
          .fontColor([this.accentColor()])
        Column({ space: AppSpacing.XS }) {
          Text(this.fileDetailEntry.name || '未命名')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`/${this.fileDetailEntry.relativePath}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Column({ space: AppSpacing.XS }) {
        Text(`格式：${this.fileDetailEntry.format().toUpperCase()}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
        Text(`大小：${this.formatSize(this.fileDetailEntry.size)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
        Text(`修改时间：${this.formatDate(this.fileDetailEntry.lastModified)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
      }
      .width('100%')
      .padding(AppSpacing.LG)
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(this.softColor())

      Row({ space: AppSpacing.MD }) {
        if (this.fileDetailBook) {
          Button('立即阅读')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.onAccentColor())
            .backgroundColor(this.accentColor())
            .onClick(() => this.readFileBookNow())
          Button('移出书架')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.removeFileBook())
        } else {
          Button('在线预览')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.previewFileBook())
          Button('加入书架')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.onAccentColor())
            .backgroundColor(this.accentColor())
            .onClick(() => this.addFileBookToShelf())
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XXL)
  }

  private prepareFileBook(onReady: (book: Book) => void): void {
    if (this.busy) return;
    const entry = this.fileDetailEntry;
    this.showFileDetail = false;
    this.busy = true;
    this.busyText = '正在准备远程书籍...';
    this.busyProgress = 1;
    WebDavBookService.openOrImport(getContext(this), this.connection, this.password, entry,
      (message: string, percent: number): void => {
        this.busyText = message;
        this.busyProgress = percent;
      }).then((book: Book): void => {
        this.busy = false;
        this.busyText = '';
        this.busyProgress = 0;
        onReady(book);
      }).catch((error: Object): void => {
        this.busy = false;
        this.busyText = '';
        this.busyProgress = 0;
        HdsFeedback.showToast(`下载失败：${this.message(error)}`);
      });
  }

  previewFileBook(): void {
    this.prepareFileBook((book: Book): void => {
      this.pendingPreviewBook = book;
      router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: book.bookUrl } })
        .catch((error: Error) => {
          HdsFeedback.showToast(`打开阅读失败：${this.message(error)}`);
        });
    });
  }

  addFileBookToShelf(): void {
    this.prepareFileBook((_book: Book): void => {
      HdsFeedback.showToast('已加入书架');
    });
  }

  readFileBookNow(): void {
    const book = this.fileDetailBook;
    if (!book) return;
    this.showFileDetail = false;
    router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: book.bookUrl } })
      .catch((error: Error) => {
        HdsFeedback.showToast(`打开阅读失败：${this.message(error)}`);
      });
  }

  removeFileBook(): void {
    const book = this.fileDetailBook;
    if (!book) return;
    promptAction.showDialog({
      title: '移出书架',
      message: `《${book.name}》`,
      buttons: [
        { text: '取消', color: this.primaryTextColor() },
        { text: '移出', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse): void => {
      if (data.index !== 1) return;
      const run = async (): Promise<void> => {
        try {
          await LocalBookService.deleteBookWithFiles(getContext(this), book.bookUrl);
          this.showFileDetail = false;
          HdsFeedback.showToast('已移出书架');
        } catch (error) {
          HdsFeedback.showToast(`移出失败：${this.message(error as Object)}`);
        }
      };
      run();
    }).catch(() => {});
  }

  private confirmPreviewShelf(book: Book): void {
    promptAction.showDialog({
      title: '是否加入书架',
      message: `《${book.name}》已下载到本地缓存`,
      buttons: [
        { text: '移出', color: this.primaryTextColor() },
        { text: '加入书架', color: this.accentColor() }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse): void => {
      if (data.index === 1) {
        HdsFeedback.showToast('已加入书架');
        return;
      }
      const run = async (): Promise<void> => {
        try {
          await LocalBookService.deleteBookWithFiles(getContext(this), book.bookUrl);
          HdsFeedback.showToast('已移出书架');
        } catch (error) {
          HdsFeedback.showToast(`移出失败：${this.message(error as Object)}`);
        }
      };
      run();
    }).catch(() => {});
  }

  goParent(): void {
    const index = this.currentPath.lastIndexOf('/');
    this.currentPath = index >= 0 ? this.currentPath.substring(0, index) : '';
    this.refreshFiles();
  }

  openCreateFolderDialog(): void {
    if (this.busy) return;
    this.actionEntryPath = '';
    this.entryNameMode = 'create';
    this.entryNameDraft = '';
    this.openEntryNameDialog();
  }

  openEntryActions(entry: WebDavEntry, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionEntryPath = entry.relativePath;
    this.showEntryActionMenu = true;
  }

  closeEntryActions(): void {
    this.showEntryActionMenu = false;
    this.actionEntryPath = '';
  }

  actionEntry(): WebDavEntry | null {
    return this.entries.find((entry: WebDavEntry): boolean => entry.relativePath === this.actionEntryPath) || null;
  }

  openRenameEntryDialog(): void {
    const entry = this.actionEntry();
    if (!entry) return;
    this.showEntryActionMenu = false;
    this.entryNameMode = 'rename';
    this.entryNameDraft = entry.name;
    this.openEntryNameDialog();
  }

  closeEntryNameDialog(): void {
    this.showEntryNameDialog = false;
    this.entryNameMode = '';
    this.entryNameDraft = '';
    this.actionEntryPath = '';
  }

  async submitEntryNameDialog(): Promise<void> {
    if (this.busy) return;
    const name = this.entryNameDraft.trim();
    const validation = this.validateEntryName(name);
    if (validation) {
      HdsFeedback.showToast(validation);
      return;
    }
    const entry = this.entryNameMode === 'rename' ? this.actionEntry() : null;
    if (this.entryNameMode === 'rename' && !entry) {
      this.closeEntryNameDialog();
      return;
    }
    const duplicate = this.entries.some((item: WebDavEntry): boolean =>
      item.name === name && (!entry || item.relativePath !== entry.relativePath));
    if (duplicate) {
      HdsFeedback.showToast('同名文件或文件夹已存在');
      return;
    }
    const mode = this.entryNameMode;
    const client = this.client;
    if (!client) return;
    this.showEntryNameDialog = false;
    this.busy = true;
    this.busyText = mode === 'create' ? '正在创建文件夹...' : '正在重命名...';
    this.busyProgress = 45;
    try {
      if (mode === 'create') {
        await client.createLibraryFolder(this.currentPath, name);
      } else if (entry) {
        await client.renameLibraryEntry(entry.relativePath, name, entry.directory);
      }
      this.busyProgress = 80;
      this.entries = await client.list(this.currentPath);
      this.busyProgress = 100;
      HdsFeedback.showToast(mode === 'create' ? '文件夹已创建' : '重命名完成');
    } catch (error) {
      HdsFeedback.showToast(`${mode === 'create' ? '创建' : '重命名'}失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
      this.entryNameMode = '';
      this.entryNameDraft = '';
      this.actionEntryPath = '';
    }
  }

  async confirmDeleteEntry(): Promise<void> {
    const entry = this.actionEntry();
    if (!entry || this.busy) return;
    this.closeEntryActions();
    const confirmation = await promptAction.showDialog({
      title: entry.directory ? '删除文件夹' : '删除文件',
      message: entry.directory ? `确定删除“${entry.name}”及其中的全部内容吗？此操作无法撤销。` :
        `确定删除“${entry.name}”吗？此操作无法撤销。`,
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
    });
    if (confirmation.index !== 1) return;
    const client = this.client;
    if (!client) return;
    this.busy = true;
    this.busyText = entry.directory ? '正在删除文件夹...' : '正在删除文件...';
    this.busyProgress = 45;
    try {
      await client.deleteLibraryEntry(entry.relativePath, entry.directory);
      this.busyProgress = 80;
      this.entries = await client.list(this.currentPath);
      this.busyProgress = 100;
      HdsFeedback.showToast('删除完成');
    } catch (error) {
      HdsFeedback.showToast(`删除失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async chooseAndUploadFiles(): Promise<void> {
    if (this.busy) return;
    const client = this.client;
    if (!client) return;
    let selected: string[] = [];
    try {
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FILE;
      options.maxSelectNumber = 20;
      selected = await new picker.DocumentViewPicker(getContext(this)).select(options);
    } catch (error) {
      const message = this.message(error);
      if (!message.toLowerCase().includes('cancel')) {
        HdsFeedback.showToast(`选择文件失败：${message}`);
      }
      return;
    }
    if (!selected || selected.length === 0) return;
    this.busy = true;
    this.busyProgress = 1;
    let uploaded = 0;
    let failed = 0;
    let firstFailure = '';
    try {
      for (let index = 0; index < selected.length; index++) {
        const uri = selected[index];
        const name = this.fileNameFromUri(uri, index);
        this.busyText = selected.length > 1 ? `正在上传 ${index + 1}/${selected.length}：${name}` : `正在上传：${name}`;
        try {
          await client.uploadLibraryFile(getContext(this), uri, this.currentPath, name,
            (sent: number, total: number): void => {
              const ratio = total > 0 ? Math.min(1, sent / total) : 0;
              this.busyProgress = Math.max(1, Math.min(94,
                Math.floor(((index + ratio) / selected.length) * 94)));
            });
          uploaded++;
        } catch (error) {
          failed++;
          if (!firstFailure) firstFailure = `${name}：${this.message(error)}`;
        }
      }
      this.busyText = '正在刷新远端目录...';
      this.busyProgress = 96;
      this.entries = await client.list(this.currentPath);
      this.busyProgress = 100;
      if (failed === 0) {
        HdsFeedback.showToast(`已上传 ${uploaded} 个文件`);
      } else {
        HdsFeedback.showToast(`上传完成：成功 ${uploaded}，失败 ${failed}；${firstFailure}`);
      }
    } catch (error) {
      HdsFeedback.showToast(`上传失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  validateEntryName(name: string): string {
    if (!name) return '请输入名称';
    if (name === '.' || name === '..') return '名称不能是“.”或“..”';
    if (name.includes('/') || name.includes('\\')) return '名称不能包含路径分隔符';
    if (name.length > 255) return '名称不能超过 255 个字符';
    return '';
  }

  fileNameFromUri(uri: string, index: number): string {
    const clean = (uri || '').split('?')[0].split('#')[0].replace(/\/+$/, '');
    let decoded = clean;
    try { decoded = decodeURIComponent(clean); } catch (_) {}
    const separator = Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\'));
    const name = (separator >= 0 ? decoded.substring(separator + 1) : decoded).trim();
    return name || `upload_${Date.now()}_${index + 1}`;
  }

  currentTitle(): string {
    return this.pageTitle || this.connection.name || 'WebDAV';
  }

  fileDescription(entry: WebDavEntry): string {
    const format = entry.format().toUpperCase() || '文件';
    return `${format} · ${this.formatSize(entry.size)} · ${this.formatDate(entry.lastModified)}`;
  }

  formatSize(size: number): string {
    if (size < 1024) return `${size} B`;
    if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
    if (size < 1024 * 1024 * 1024) return `${(size / 1024 / 1024).toFixed(1)} MB`;
    return `${(size / 1024 / 1024 / 1024).toFixed(2)} GB`;
  }

  formatDate(timestamp: number): string {
    return timestamp > 0 ? new Date(timestamp).toLocaleString() : '时间未知';
  }

  message(error: Object): string {
    return WebDavError.message(error);
  }

  updateContextViewport(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
    if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
  }

  contextMenuLeft(menuWidth: number): number {
    return Math.max(12, Math.min(this.contextMenuX - 18, this.contextViewportWidth - menuWidth - 12));
  }

  contextMenuTop(menuHeight: number): number {
    const below = this.contextMenuY + 12;
    if (below + menuHeight <= this.contextViewportHeight - this.navBarHeight - 12) return below;
    return Math.max(this.statusBarHeight + 8, this.contextMenuY - menuHeight - 12);
  }

  fileListTopInset(): number {
    return 56 + this.statusBarHeight + 54;
  }

  syncBars(): void { syncSystemBars(getContext(this), this.appDarkMode, this.pageColor()); }
  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }
  softColor(): string { return ThemeRuntime.inputColor(this.appDarkMode); }
}
