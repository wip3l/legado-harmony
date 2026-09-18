import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { router, promptAction } from '@kit.ArkUI';
import {
  AppDataBackupImportSession,
  AppDataBackupSelection,
  AppDataBackupService
} from '../utils/AppDataBackupService';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { WebDavBookService } from '../webdav/WebDavBookService';
import { WebDavClient } from '../webdav/WebDavClient';
import { WebDavError } from '../webdav/WebDavError';
import { WebDavConnection, WebDavEntry } from '../webdav/WebDavModels';
import { WebDavSecretStore } from '../webdav/WebDavSecretStore';
import { WebDavSettingsStore } from '../webdav/WebDavSettingsStore';
import { FormDraftStore } from '../utils/FormDraftStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';

class WebDavFormDraft {
  connectionJson: string = '';
  tab: string = 'settings';
  encryptBackup: boolean = false;
  includeLocalBooks: boolean = false;
  entryNameDraft: string = '';
}

@Entry
@Component
struct WebDavPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State tab: string = 'files';
  @State connection: WebDavConnection = new WebDavConnection();
  @State password: string = '';
  @State currentPath: string = '';
  @State entries: WebDavEntry[] = [];
  @State backups: WebDavEntry[] = [];
  @State configured: boolean = false;
  @State editing: boolean = false;
  @State busy: boolean = false;
  @State busyText: string = '';
  @State busyProgress: number = 0;
  @State encryptBackup: boolean = false;
  @State backupPassword: string = '';
  @State includeLocalBooks: boolean = false;
  private restorePasswordDialogSession: SystemDialogSession = new SystemDialogSession();
  private entryNameDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showRestorePasswordDialog: boolean = false;
  @State restorePassword: string = '';
  @State restorePasswordError: string = '';
  @State pendingRestoreSourcePath: string = '';
  @State showEntryActionMenu: boolean = false;
  @State actionEntryPath: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State @Watch('onSystemDialogFlagChanged') showEntryNameDialog: boolean = false;
  @State entryNameMode: string = '';
  @State entryNameDraft: string = '';
  private connectionInitialized: boolean = false;
  private draftSaveTimerId: number = -1;
  private draftSecretSaveTimerId: number = -1;
  private formDraftDirty: boolean = false;
  private readonly draftPasswordId: string = '__webdav_form_draft_password__';
  private readonly draftBackupPasswordId: string = '__webdav_form_draft_backup_password__';

  aboutToAppear(): void {
    this.syncBars();
    if (this.connectionInitialized) return;
    this.connectionInitialized = true;
    this.initializeWebDavForm();
  }

  onPageShow(): void {
    this.syncBars();
  }

  onPageHide(): void {
    this.persistFormDraftNow();
  }

  onBackPress(): boolean {    if (this.showEntryActionMenu) {
      this.closeEntryActions();
      return true;
    }
    if (this.tab === 'files' && this.currentPath) {
      if (!this.busy) this.goParent();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.tabs()
        if (this.tab === 'files') {
          this.filesPanel()
        } else if (this.tab === 'backups') {
          this.backupPanel()
        } else {
          this.settingsPanel()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 56 + this.statusBarHeight })

      this.titleBar()

      if (this.showEntryActionMenu) {
        this.entryActionMenu()
      }



      if (this.busy) {
        Column({ space: 12 }) {
          Progress({ value: this.busyProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.accentColor())
          Text(this.busyText || '处理中...')
            .fontSize(14)
            .fontColor(this.primaryTextColor())
        }
        .width('78%')
        .padding(20)
        .borderRadius(16)
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
  tabs() {
    Row() {
      this.tabButton('文件', 'files')
      this.tabButton('备份', 'backups')
      this.tabButton('设置', 'settings')
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
    .zIndex(2)
  }

  @Builder
  tabButton(title: string, value: string) {
    Button(title)
      .layoutWeight(1)
      .height(36)
      .fontSize(14)
      .fontColor(this.tab === value ? Color.White : this.primaryTextColor())
      .backgroundColor(this.tab === value ? this.accentColor() : Color.Transparent)
      .borderRadius(10)
      .onClick(() => {
        this.tab = value;
        if (value === 'files' && this.configured && this.entries.length === 0) this.refreshFiles();
        if (value === 'backups' && this.configured) this.refreshBackups();
      })
  }

  @Builder
  filesPanel() {
    Column() {
      if (!this.configured) {
        this.emptyConfiguration('先配置 WebDAV 连接，之后即可浏览其中的 TXT 和 EPUB。')
      } else {
        Row({ space: 8 }) {
          if (this.currentPath) {
            Button('上一级')
              .height(34)
              .fontSize(13)
              .fontColor(this.accentColor())
              .backgroundColor(this.softColor())
              .onClick(() => this.goParent())
          }
          Column() {
            Text(this.connection.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryTextColor())
            Text(this.currentPath ? `/${this.currentPath}` : '/')
              .fontSize(11)
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
        .padding({ left: 14, right: 14, top: 12, bottom: 8 })
        .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
        .backdropBlur(ThemeRuntime.topBarBlur())
        .zIndex(2)

        List({ space: 1 }) {
          ListItem() {
            Row()
              .height(this.fileListTopInset())
              .hitTestBehavior(HitTestMode.None)
          }

          ForEach(this.entries, (entry: WebDavEntry) => {
            ListItem() {
              Row({ space: 12 }) {
                SymbolGlyph($r(entry.directory ? 'sys.symbol.folder' : 'sys.symbol.doc'))
                  .fontSize(26)
                  .fontColor([entry.directory ? this.accentColor() : this.subTextColor()])
                Column({ space: 4 }) {
                  Text(entry.name)
                    .fontSize(15)
                    .fontColor(this.primaryTextColor())
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(entry.directory ? '文件夹' : this.fileDescription(entry))
                    .fontSize(11)
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
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
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
        .padding({ left: 12, right: 12 })
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
      .fontSize(12)
      .fontColor(this.accentColor())
      .backgroundColor(this.softColor())
      .padding({ left: 10, right: 10 })
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
        this.entryContextActionItem($r('sys.symbol.trash'), '删除', '#E53935',
          () => this.confirmDeleteEntry())
      }
      .width(148)
      .padding({ top: 6, bottom: 6 })
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
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([color])
        .width(24)
      Text(label)
        .fontSize(15)
        .fontColor(color)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }


  onSystemDialogFlagChanged(): void {
    if (!this.showEntryNameDialog) this.entryNameDialogSession.close(this.getUIContext());
    if (!this.showRestorePasswordDialog) this.restorePasswordDialogSession.close(this.getUIContext());
  }

  openEntryNameDialog(): void {
    this.showEntryNameDialog = true;
    this.entryNameDialogSession.open(this.getUIContext(), (): void => {
      this.entryNameDialogContent();
    }, {
      autoCancel: true,
      maskColor: this.appDarkMode ? '#99000000' : '#33000000',
      warnTag: '显示文件命名弹窗失败:'
    });
  }

  openRestorePasswordDialog(): void {
    this.showRestorePasswordDialog = true;
    this.restorePasswordDialogSession.open(this.getUIContext(), (): void => {
      this.restorePasswordDialogContent();
    }, {
      autoCancel: true,
      maskColor: this.appDarkMode ? '#99000000' : '#33000000',
      warnTag: '显示恢复密码弹窗失败:'
    });
  }

  @Builder
  entryNameDialogContent() {
    Column() {
      Text(this.entryNameMode === 'create' ? '创建文件夹' : '重命名')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 14 })
        TextInput({ text: this.entryNameDraft,
        placeholder: this.entryNameMode === 'create' ? '文件夹名称' : '新名称' })
        .width('100%')
        .height(44)
        .backgroundColor(this.softColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .onChange((value: string) => {
          this.entryNameDraft = value;
          this.scheduleFormDraftSave();
        })
      Row({ space: 10 }) {
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
          .fontColor('#FFFFFF')
          .onClick(() => this.submitEntryNameDialog())
      }
      .width('100%')
      .margin({ top: 14 })
    }    .padding(20)
  }


  @Builder
  restorePasswordDialogContent() {
    Column({ space: 12 }) {
      Text('输入备份密码')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text('检测到该远端备份已加密，请输入创建备份时设置的密码。')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .width('100%')
      TextInput({ text: this.restorePassword, placeholder: '输入备份密码' })
        .type(InputType.Password)
        .height(44)
        .backgroundColor(this.softColor())
        .onChange((value: string) => {
          this.restorePassword = value;
          this.restorePasswordError = '';
        })
      if (this.restorePasswordError) {
        Text(this.restorePasswordError)
          .fontSize(12)
          .fontColor('#D9485F')
          .width('100%')
      }
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontColor(this.primaryTextColor())
          .backgroundColor(this.softColor())
          .onClick(() => this.cancelRestorePassword())
        Button('继续恢复')
          .layoutWeight(1)
          .height(40)
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => this.confirmRestorePassword())
      }
      .width('100%')
    }    .padding(20)
  }


  @Builder
  backupPanel() {
    Scroll() {
      Column({ space: 12 }) {
        if (!this.configured) {
          this.emptyConfiguration('配置连接后，可以把应用备份保存到 WebDAV。')
        } else {
          Column({ space: 10 }) {
            Row() {
              Column({ space: 3 }) {
                Text('加密备份')
                  .fontSize(14)
                  .fontColor(this.primaryTextColor())
                Text(this.encryptBackup ? '使用密码加密，恢复时需要输入密码' : '默认关闭，备份文件不加密')
                  .fontSize(11)
                  .fontColor(this.subTextColor())
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.encryptBackup })
                .selectedColor(this.accentColor())
                .onChange((value: boolean) => {
                  this.encryptBackup = value;
                  this.scheduleFormDraftSave();
                })
            }
            .width('100%')
            if (this.encryptBackup) {
              Column({ space: 6 }) {
                Text('备份加密密码')
                  .fontSize(13)
                  .fontColor(this.subTextColor())
                  .width('100%')
                TextInput({ text: this.backupPassword, placeholder: '至少 8 个字符；请妥善保存' })
                  .type(InputType.Password)
                  .height(44)
                  .backgroundColor(this.softColor())
                  .onChange((value: string) => {
                    this.backupPassword = value;
                    this.scheduleFormDraftSave();
                    this.scheduleDraftSecretSave();
                  })
              }
              .width('100%')
            }
            Row() {
              Column() {
                Text('包含本地图书文件')
                  .fontSize(14)
                  .fontColor(this.primaryTextColor())
                Text('WebDAV 书籍缓存不会重复写入备份')
                  .fontSize(11)
                  .fontColor(this.subTextColor())
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.includeLocalBooks })
                .selectedColor(this.accentColor())
                .onChange((value: boolean) => {
                  this.includeLocalBooks = value;
                  this.scheduleFormDraftSave();
                })
            }
            .width('100%')
            Button(this.encryptBackup ? '立即上传加密备份' : '立即上传备份')
              .width('100%')
              .height(44)
              .fontColor(Color.White)
              .backgroundColor(this.accentColor())
              .onClick(() => this.uploadBackup())
          }
          .width('calc(100% - 24vp)')
          .padding(14)
          .borderRadius(16)
          .backgroundColor(this.cardColor())

          Row() {
            Text('远端备份')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Button('刷新')
              .height(32)
              .fontSize(12)
              .fontColor(this.accentColor())
              .backgroundColor(this.softColor())
              .onClick(() => this.refreshBackups())
          }
          .width('calc(100% - 24vp)')

          ForEach(this.backups, (entry: WebDavEntry) => {
            Column({ space: 8 }) {
              Text(entry.name)
                .fontSize(14)
                .fontColor(this.primaryTextColor())
                .maxLines(2)
                .width('100%')
              Text(`${this.formatSize(entry.size)} · ${this.formatDate(entry.lastModified)}`)
                .fontSize(11)
                .fontColor(this.subTextColor())
                .width('100%')
              Row({ space: 8 }) {
                Button('恢复')
                  .layoutWeight(1)
                  .height(34)
                  .fontColor(Color.White)
                  .backgroundColor(this.accentColor())
                  .onClick(() => this.restoreBackup(entry))
                Button('删除')
                  .layoutWeight(1)
                  .height(34)
                  .fontColor('#D9485F')
                  .backgroundColor(this.softColor())
                  .onClick(() => this.deleteBackup(entry))
              }
            }
            .width('calc(100% - 24vp)')
            .padding(14)
            .borderRadius(14)
            .backgroundColor(this.cardColor())
          }, (entry: WebDavEntry) => entry.name)

          if (this.backups.length === 0) {
            Text('暂无远端备份')
              .fontSize(13)
              .fontColor(this.subTextColor())
              .padding(24)
          }
        }
      }
      .width('100%')
      .padding({ top: this.scrollableTopInset() + 12, bottom: Math.max(24, this.navBarHeight) })
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
    .margin({ top: -this.scrollableTopInset() })
    .zIndex(0)
  }

  @Builder
  settingsPanel() {
    Scroll() {
      Column({ space: 12 }) {
        this.field('连接名称', this.connection.name, '例如：我的云盘', (value: string) => this.connection.name = value)
        this.field('WebDAV 地址', this.connection.baseUrl, 'https://example.com/dav/ 或 http://192.168.1.2/dav/',
          (value: string) => this.connection.baseUrl = value)
        if (/^http:\/\//i.test(this.connection.baseUrl.trim())) {
          Text('HTTP 会明文传输用户名、密码和文件内容，请仅在可信局域网或受保护的 VPN 中使用。')
            .fontSize(12)
            .fontColor('#D9485F')
            .width('calc(100% - 32vp)')
        }
        this.field('用户名', this.connection.username, 'WebDAV 用户名',
          (value: string) => this.connection.username = value)
        Column({ space: 6 }) {
          Text('密码 / 应用专用密码').fontSize(13).fontColor(this.subTextColor()).width('100%')
          TextInput({ text: this.password, placeholder: this.configured ? '留空则使用已保存密码' : '输入密码' })
            .type(InputType.Password)
            .height(44)
            .backgroundColor(this.softColor())
            .onChange((value: string) => {
              this.password = value;
              this.scheduleFormDraftSave();
              this.scheduleDraftSecretSave();
            })
        }.width('calc(100% - 24vp)')
        this.field('书库目录', this.connection.libraryRoot, '留空表示 WebDAV 根目录',
          (value: string) => this.connection.libraryRoot = value)
        this.field('备份目录', this.connection.backupRoot, 'LegadoHarmony/Backups',
          (value: string) => this.connection.backupRoot = value)
        Row() {
          Text('在系统密钥库中保存密码')
            .fontSize(14)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.connection.rememberPassword })
            .selectedColor(this.accentColor())
            .onChange((value: boolean) => {
              this.connection.rememberPassword = value;
              this.scheduleFormDraftSave();
            })
        }
        .width('calc(100% - 24vp)')
        .padding(14)
        .borderRadius(14)
        .backgroundColor(this.cardColor())
        Button('测试并保存')
          .width('calc(100% - 24vp)')
          .height(44)
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => this.testAndSave())
        if (this.configured) {
          Button('删除此连接')
            .width('calc(100% - 24vp)')
            .height(42)
            .fontColor('#D9485F')
            .backgroundColor(this.cardColor())
            .onClick(() => this.deleteConnection())
        }
        Text('支持 HTTP 和 HTTPS。推荐使用 HTTPS；当前可阅读 TXT 和 EPUB，远端原文件不会因移出书架而被删除。')
          .fontSize(12)
          .fontColor(this.subTextColor())
          .width('calc(100% - 32vp)')
      }
      .width('100%')
      .padding({ top: this.scrollableTopInset() + 14, bottom: Math.max(28, this.navBarHeight) })
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
    .margin({ top: -this.scrollableTopInset() })
    .zIndex(0)
  }

  @Builder
  field(title: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: 6 }) {
      Text(title).fontSize(13).fontColor(this.subTextColor()).width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .height(44)
        .backgroundColor(this.softColor())
        .onChange((nextValue: string) => {
          onChange(nextValue);
          this.scheduleFormDraftSave();
        })
    }
    .width('calc(100% - 24vp)')
  }

  @Builder
  emptyConfiguration(message: string) {
    Column({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.externaldrive'))
        .fontSize(42)
        .fontColor([this.accentColor()])
      Text(message)
        .fontSize(14)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
      Button('去配置')
        .fontColor(Color.White)
        .backgroundColor(this.accentColor())
        .onClick(() => this.tab = 'settings')
    }
    .width('100%')
    .padding({ top: 90, left: 36, right: 36 })
  }

  async loadConnection(): Promise<void> {
    const connections = await WebDavSettingsStore.loadConnections(getContext(this));
    const activeId = await WebDavSettingsStore.activeConnectionId(getContext(this));
    const active = connections.find((item: WebDavConnection): boolean => item.id === activeId) || connections[0];
    if (!active) {
      this.connection = new WebDavConnection();
      this.tab = 'settings';
      return;
    }
    this.connection = active;
    this.password = await WebDavSecretStore.password(getContext(this), active.id);
    this.configured = true;
    await this.refreshFiles();
  }

  async initializeWebDavForm(): Promise<void> {
    if (await this.restoreFormDraft()) return;
    await this.loadConnection();
  }

  async restoreFormDraft(): Promise<boolean> {
    const raw = await FormDraftStore.load(getContext(this), 'webdav:form');
    if (!raw) return false;
    try {
      const draft = JSON.parse(raw) as WebDavFormDraft;
      this.connection = JSON.parse(draft.connectionJson) as WebDavConnection;
      this.password = await WebDavSecretStore.password(getContext(this), this.draftPasswordId);
      this.tab = draft.tab || 'settings';
      this.backupPassword = await WebDavSecretStore.password(getContext(this), this.draftBackupPasswordId);
      this.encryptBackup = draft.encryptBackup === true;
      this.includeLocalBooks = draft.includeLocalBooks === true;
      this.entryNameDraft = draft.entryNameDraft || '';
      this.configured = !!this.connection.id;
      this.formDraftDirty = true;
      return true;
    } catch (_) {
      FormDraftStore.removePersistent(getContext(this), 'webdav:form');
      return false;
    }
  }

  scheduleFormDraftSave(): void {
    this.formDraftDirty = true;
    const current = this.connection;
    const next = new WebDavConnection();
    next.id = current.id;
    next.name = current.name;
    next.baseUrl = current.baseUrl;
    next.username = current.username;
    next.libraryRoot = current.libraryRoot;
    next.backupRoot = current.backupRoot;
    next.rememberPassword = current.rememberPassword;
    next.secretStorageVersion = current.secretStorageVersion;
    next.enabled = current.enabled;
    next.createdAt = current.createdAt;
    next.updatedAt = current.updatedAt;
    this.connection = next;
    if (this.draftSaveTimerId >= 0) clearTimeout(this.draftSaveTimerId);
    this.draftSaveTimerId = setTimeout(() => {
      this.draftSaveTimerId = -1;
      const draft = new WebDavFormDraft();
      draft.connectionJson = JSON.stringify(this.connection);
      draft.tab = this.tab;
      draft.encryptBackup = this.encryptBackup;
      draft.includeLocalBooks = this.includeLocalBooks;
      draft.entryNameDraft = this.entryNameDraft;
      FormDraftStore.persistSoon(getContext(this), 'webdav:form', JSON.stringify(draft));
    }, 60);
  }

  persistFormDraftNow(): void {
    if (!this.formDraftDirty) return;
    if (this.draftSaveTimerId >= 0) {
      clearTimeout(this.draftSaveTimerId);
      this.draftSaveTimerId = -1;
    }
    const draft = new WebDavFormDraft();
    draft.connectionJson = JSON.stringify(this.connection);
    draft.tab = this.tab;
    draft.encryptBackup = this.encryptBackup;
    draft.includeLocalBooks = this.includeLocalBooks;
    draft.entryNameDraft = this.entryNameDraft;
    FormDraftStore.persist(getContext(this), 'webdav:form', JSON.stringify(draft));
    WebDavSecretStore.savePassword(getContext(this), this.draftPasswordId, this.password, true);
    WebDavSecretStore.savePassword(getContext(this), this.draftBackupPasswordId, this.backupPassword, true);
  }

  scheduleDraftSecretSave(): void {
    if (this.draftSecretSaveTimerId >= 0) clearTimeout(this.draftSecretSaveTimerId);
    this.draftSecretSaveTimerId = setTimeout(() => {
      this.draftSecretSaveTimerId = -1;
      WebDavSecretStore.savePassword(getContext(this), this.draftPasswordId, this.password, true);
      WebDavSecretStore.savePassword(getContext(this), this.draftBackupPasswordId, this.backupPassword, true);
    }, 240);
  }

  clearFormDraft(): void {
    if (this.draftSaveTimerId >= 0) {
      clearTimeout(this.draftSaveTimerId);
      this.draftSaveTimerId = -1;
    }
    if (this.draftSecretSaveTimerId >= 0) {
      clearTimeout(this.draftSecretSaveTimerId);
      this.draftSecretSaveTimerId = -1;
    }
    this.formDraftDirty = false;
    FormDraftStore.removePersistent(getContext(this), 'webdav:form');
    WebDavSecretStore.deletePassword(getContext(this), this.draftPasswordId);
    WebDavSecretStore.deletePassword(getContext(this), this.draftBackupPasswordId);
  }

  async testAndSave(): Promise<void> {
    if (this.busy) return;
    const baseUrl = WebDavSettingsStore.normalizeBaseUrl(this.connection.baseUrl);
    if (!/^https?:\/\//i.test(baseUrl)) {
      HdsFeedback.showToast('WebDAV 地址必须以 http:// 或 https:// 开头');
      return;
    }
    if (!this.connection.username || !this.password) {
      HdsFeedback.showToast('请输入用户名和密码');
      return;
    }
    this.connection.baseUrl = baseUrl;
    this.busy = true;
    this.busyText = '正在测试 WebDAV 连接...';
    this.busyProgress = 30;
    try {
      const client = new WebDavClient(this.connection, this.password);
      const result = await client.testConnection();
      if (!result.ok) throw new Error(result.message);
      this.busyProgress = 65;
      let saved = await WebDavSettingsStore.saveConnection(getContext(this), this.connection);
      let credentialWarning = '';
      try {
        await WebDavSecretStore.savePassword(getContext(this), saved.id, this.password, saved.rememberPassword);
      } catch (credentialError) {
        await WebDavSecretStore.savePassword(getContext(this), saved.id, this.password, false);
        credentialWarning = '；系统密钥库不可用，本次会话仍可使用，重启后需重新输入密码';
        console.warn('[WebDAV] 凭据持久化已降级:', this.message(credentialError as Object));
      }
      this.connection = saved;
      this.clearFormDraft();
      this.configured = true;
      this.currentPath = '';
      this.busyText = '正在读取远端目录...';
      this.busyProgress = 78;
      this.entries = await new WebDavClient(saved, this.password).list('');
      this.tab = 'files';
      this.busyProgress = 100;
      HdsFeedback.showToast(`WebDAV 连接已保存${credentialWarning}`);
    } catch (error) {
      HdsFeedback.showToast(`连接失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async deleteConnection(): Promise<void> {
    const confirmation = await promptAction.showDialog({
      title: '删除 WebDAV 连接',
      message: '只会删除本机连接配置和保存的密码，不会删除远端文件。',
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: '#D9485F' }]
    });
    if (confirmation.index !== 1) return;
    await WebDavSecretStore.deletePassword(getContext(this), this.connection.id);
    await WebDavSettingsStore.deleteConnection(getContext(this), this.connection.id);
    this.connection = new WebDavConnection();
    this.password = '';
    this.configured = false;
    this.entries = [];
    this.backups = [];
  }

  async refreshFiles(): Promise<void> {
    if (!this.configured || !this.password || this.busy) return;
    this.busy = true;
    this.busyText = '正在读取远端目录...';
    this.busyProgress = 35;
    try {
      this.entries = await new WebDavClient(this.connection, this.password).list(this.currentPath);
      this.busyProgress = 100;
    } catch (error) {
      HdsFeedback.showToast(`读取失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async openEntry(entry: WebDavEntry): Promise<void> {
    if (entry.directory) {
      this.currentPath = entry.relativePath;
      await this.refreshFiles();
      return;
    }
    if (!entry.readableBook()) {
      HdsFeedback.showToast('当前仅支持 TXT 和 EPUB');
      return;
    }
    if (this.busy) return;
    this.busy = true;
    this.busyText = '正在准备远程书籍...';
    this.busyProgress = 1;
    try {
      const book = await WebDavBookService.openOrImport(getContext(this), this.connection, this.password, entry,
        (message: string, percent: number): void => {
          this.busyText = message;
          this.busyProgress = percent;
        });
      this.busy = false;
      await router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: book.bookUrl } });
    } catch (error) {
      HdsFeedback.showToast(`打开失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  goParent(): void {
    const index = this.currentPath.lastIndexOf('/');
    this.currentPath = index >= 0 ? this.currentPath.substring(0, index) : '';
    this.refreshFiles();
  }

  openCreateFolderDialog(): void {
    if (this.busy || !this.configured || !this.password) return;
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
    this.showEntryNameDialog = false;
    this.busy = true;
    this.busyText = mode === 'create' ? '正在创建文件夹...' : '正在重命名...';
    this.busyProgress = 45;
    try {
      const client = new WebDavClient(this.connection, this.password);
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
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: '#E53935' }]
    });
    if (confirmation.index !== 1) return;
    this.busy = true;
    this.busyText = entry.directory ? '正在删除文件夹...' : '正在删除文件...';
    this.busyProgress = 45;
    try {
      const client = new WebDavClient(this.connection, this.password);
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
    if (this.busy || !this.configured || !this.password) return;
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
    const client = new WebDavClient(this.connection, this.password);
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

  async refreshBackups(): Promise<void> {
    if (!this.configured || !this.password || this.busy) return;
    this.busy = true;
    this.busyText = '正在读取远端备份...';
    this.busyProgress = 35;
    try {
      this.backups = await new WebDavClient(this.connection, this.password).listBackups();
      this.busyProgress = 100;
    } catch (error) {
      HdsFeedback.showToast(`读取备份失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async uploadBackup(): Promise<void> {
    if (this.busy) return;
    if (this.encryptBackup && this.backupPassword.length < 8) {
      HdsFeedback.showToast('备份加密密码至少需要 8 个字符');
      return;
    }
    const encryptionPassword = this.encryptBackup ? this.backupPassword : '';
    this.busy = true;
    this.busyText = this.encryptBackup ? '正在生成加密备份...' : '正在生成备份...';
    this.busyProgress = 1;
    let archivePath = '';
    try {
      const selection = new AppDataBackupSelection();
      selection.localBooks = this.includeLocalBooks;
      const backup = await AppDataBackupService.createBackup(getContext(this), selection, encryptionPassword,
        (message: string, percent: number): void => {
          this.busyText = message;
          this.busyProgress = Math.floor(percent * 0.65);
        });
      archivePath = backup.archivePath;
      const remoteName = `legado_harmony_${this.timestamp()}.qingyebak`;
      this.busyText = '正在上传 WebDAV...';
      await new WebDavClient(this.connection, this.password).uploadBackup(
        getContext(this), backup.archivePath, remoteName,
        (sent: number, total: number): void => {
          const ratio = total > 0 ? sent / total : 0;
          this.busyProgress = 66 + Math.min(33, Math.floor(ratio * 33));
        });
      this.busyProgress = 100;
      HdsFeedback.showToast(this.encryptBackup ? 'WebDAV 加密备份上传完成' : 'WebDAV 备份上传完成');
      this.backups = await new WebDavClient(this.connection, this.password).listBackups();
    } catch (error) {
      HdsFeedback.showToast(`备份失败：${this.message(error)}`);
    } finally {
      await AppDataBackupService.discardExport(archivePath);
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async restoreBackup(entry: WebDavEntry): Promise<void> {
    if (this.busy) return;
    const confirmation = await promptAction.showDialog({
      title: '恢复 WebDAV 备份',
      message: '备份数据会合并到当前应用，相同书籍、书源和设置会更新。是否继续？',
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '继续恢复', color: this.accentColor() }]
    });
    if (confirmation.index !== 1) return;
    this.busy = true;
    this.busyText = '正在下载备份...';
    this.busyProgress = 1;
    const sourcePath = `${getContext(this).tempDir}/webdav_restore_${Date.now()}.qingyebak`;
    let keepSourceForPassword: boolean = false;
    try {
      await new WebDavClient(this.connection, this.password).downloadBackup(entry.relativePath, sourcePath,
        (received: number, total: number): void => {
          const ratio = total > 0 ? received / total : 0;
          this.busyProgress = 1 + Math.min(39, Math.floor(ratio * 39));
        });
      const summary = await this.importDownloadedBackup(sourcePath, '');
      this.busyProgress = 100;
      HdsFeedback.showToast(`恢复完成：${summary}`);
    } catch (error) {
      if (this.isBackupPasswordRequired(error)) {
        keepSourceForPassword = true;
        this.pendingRestoreSourcePath = sourcePath;
        this.restorePassword = '';
        this.restorePasswordError = '';
        this.openRestorePasswordDialog();
      } else {
        HdsFeedback.showToast(`恢复失败：${this.message(error)}`);
      }
    } finally {
      if (!keepSourceForPassword) this.deleteRestoreSource(sourcePath);
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async confirmRestorePassword(): Promise<void> {
    if (this.busy) return;
    if (!this.restorePassword) {
      this.restorePasswordError = '请输入备份密码';
      return;
    }
    const sourcePath = this.pendingRestoreSourcePath;
    if (!sourcePath || !fs.accessSync(sourcePath)) {
      this.cancelRestorePassword();
      HdsFeedback.showToast('待恢复的备份文件已失效，请重新选择');
      return;
    }
    this.showRestorePasswordDialog = false;
    this.restorePasswordError = '';
    this.busy = true;
    this.busyText = '正在解密备份...';
    this.busyProgress = 41;
    try {
      const summary = await this.importDownloadedBackup(sourcePath, this.restorePassword);
      this.busyProgress = 100;
      this.deleteRestoreSource(sourcePath);
      this.pendingRestoreSourcePath = '';
      this.restorePassword = '';
      HdsFeedback.showToast(`恢复完成：${summary}`);
    } catch (error) {
      this.restorePasswordError = this.message(error);
      this.showRestorePasswordDialog = true;
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  cancelRestorePassword(): void {
    this.showRestorePasswordDialog = false;
    this.restorePassword = '';
    this.restorePasswordError = '';
    this.deleteRestoreSource(this.pendingRestoreSourcePath);
    this.pendingRestoreSourcePath = '';
  }

  async importDownloadedBackup(sourcePath: string, password: string): Promise<string> {
    let session: AppDataBackupImportSession | null = null;
    try {
      const prepared = await AppDataBackupService.prepareImport(getContext(this), sourcePath, password,
        (message: string, percent: number): void => {
          this.busyText = message;
          this.busyProgress = 41 + Math.floor(percent * 0.39);
        });
      session = prepared;
      this.busyText = '正在合并备份数据...';
      const selection = new AppDataBackupSelection();
      selection.searchHistory = true;
      const result = await AppDataBackupService.importBackup(getContext(this), prepared, selection);
      return result.summary();
    } finally {
      await AppDataBackupService.discardImport(session);
    }
  }

  isBackupPasswordRequired(error: Object): boolean {
    return this.message(error).includes(AppDataBackupService.PASSWORD_REQUIRED_MESSAGE);
  }

  deleteRestoreSource(sourcePath: string): void {
    if (!sourcePath) return;
    try { if (fs.accessSync(sourcePath)) fs.unlinkSync(sourcePath); } catch (_) {}
  }

  async deleteBackup(entry: WebDavEntry): Promise<void> {
    const confirmation = await promptAction.showDialog({
      title: '删除远端备份',
      message: `确定删除“${entry.name}”吗？此操作无法撤销。`,
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: '#D9485F' }]
    });
    if (confirmation.index !== 1) return;
    this.busy = true;
    this.busyText = '正在删除远端备份...';
    this.busyProgress = 50;
    try {
      await new WebDavClient(this.connection, this.password).deleteBackup(entry.relativePath);
      this.backups = this.backups.filter((item: WebDavEntry): boolean => item.relativePath !== entry.relativePath);
      HdsFeedback.showToast('远端备份已删除');
    } catch (error) {
      HdsFeedback.showToast(`删除失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
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

  timestamp(): string {
    const date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_` +
      `${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
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

  scrollableTopInset(): number {
    return 56 + this.statusBarHeight + 48;
  }

  fileListTopInset(): number {
    return this.scrollableTopInset() + 54;
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('WebDAV')
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
    .position({ x: 0, y: 0 })
    .zIndex(3)
  }

  syncBars(): void { syncSystemBars(getContext(this), this.appDarkMode, this.pageColor()); }
  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }
  softColor(): string { return this.appDarkMode ? '#24272D' : '#EEF2F7'; }
}
