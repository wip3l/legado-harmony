import { router, promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { WebDavClient } from '../webdav/WebDavClient';
import { WebDavError } from '../webdav/WebDavError';
import { WebDavConnection } from '../webdav/WebDavModels';
import { WebDavSecretStore } from '../webdav/WebDavSecretStore';
import { WebDavSettingsStore } from '../webdav/WebDavSettingsStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { PopupMenuAction } from '../components/common/PopupMenuAction';

@Entry
@Component
struct WebDavPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State connections: WebDavConnection[] = [];
  @State busy: boolean = false;
  @State busyText: string = '';
  @State busyProgress: number = 0;
  @State showConnectionActionMenu: boolean = false;
  @State actionConnectionId: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State @Watch('onSystemDialogFlagChanged') showConnectionEditorDialog: boolean = false;
  @State editingConnectionId: string = '';
  @State draftName: string = '';
  @State draftBaseUrl: string = '';
  @State draftLibraryRoot: string = '';
  @State draftUsername: string = '';
  @State draftPassword: string = '';
  @State draftRememberPassword: boolean = true;
  private editorDialogSession: SystemDialogSession = new SystemDialogSession();

  aboutToAppear(): void {
    this.syncBars();
    this.loadConnections();
    this.cleanupLegacyBackupDraftSecret();
  }

  onPageShow(): void {
    this.syncBars();
  }

  onBackPress(): boolean {
    if (this.showConnectionActionMenu) {
      this.closeConnectionActions();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: 'WebDAV', scrollable: false, externalCollapse: this.headerCollapse, content: () => {
        this.pageContent()
      } })

      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showConnectionActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.connectionActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          this.showConnectionActionMenu = false;
        }))

      if (!this.showConnectionActionMenu && !this.showConnectionEditorDialog && !this.busy) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.addConnectionFloatingButton()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
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
    this.connectionList()
  }

  @Builder
  connectionList() {
    Column() {
      if (this.connections.length === 0) {
        this.emptyGuide()
      } else {
        List({ scroller: this.headerScroller, space: AppSpacing.MD }) {
          ListItem() {
            Row()
              .height(this.listTopInset())
              .hitTestBehavior(HitTestMode.None)
          }

          ForEach(this.connections, (connection: WebDavConnection) => {
            if (deviceInfo.sdkApiVersion >= 26) {
              HdsListItem({
                customItemBuilder: (): void => {
                  this.connectionRow(connection)
                },
                swipeActionOptions: this.connectionSwipeActions(connection)
              })
            }
            if (deviceInfo.sdkApiVersion < 26) {
              ListItem() {
                this.connectionRow(connection)
              }
              .borderRadius(ThemeRuntime.mediumRadius())
              .clip(true)
              .swipeAction(this.busy ? {} : {
                end: {
                  builder: (): void => {
                    this.connectionSwipeButtons(connection)
                  },
                  actionAreaDistance: 128,
                  onAction: (): void => {
                    if (!this.busy) this.confirmDeleteConnection(connection);
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
            }
          }, (connection: WebDavConnection) => connection.id)

          ListItem() {
            Text('仅支持下载 TXT / EPUB / MOBI 格式')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: AppSpacing.XL, bottom: AppSpacing.XL })
          }
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        // 顶栏收起时外层留白同步减少，列表顶边保持贴住页面顶部。
        .margin({ top: -(this.listTopInset() - this.headerCollapse) })
        .zIndex(0)
        .onDidScroll((yOffset: number) => {
          this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
            this.headerScroller.currentOffset().yOffset);
        })
        .onScrollStop(() => {
          const target = CollapsingHeader.settle(this.headerCollapse, this.headerScroller.currentOffset().yOffset);
          if (target !== this.headerCollapse) {
            animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
              this.headerCollapse = target;
            });
          }
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  connectionRow(connection: WebDavConnection) {
    Row({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.externaldrive'))
        .fontSize(26)
        .fontColor([this.accentColor()])
      Column({ space: AppSpacing.XS }) {
        Text(connection.name)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(connection.baseUrl)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: AppSpacing.MD }) {
          if (connection.username) {
            Text(`账号：${connection.username}`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(connection.enabled ? '已启用' : '已停用')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(connection.enabled ? this.subTextColor() : ThemeRuntime.dangerColor(this.appDarkMode))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(17)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (!this.busy) this.openConnectionActions(connection, event);
        })
    )
    .onClick(() => {
      if (!this.showConnectionActionMenu && !this.showConnectionEditorDialog) this.openConnection(connection);
    })
  }

  private connectionSwipeActions(connection: WebDavConnection): HdsSwipeActionOptions {
    if (this.busy) return { icons: [] };
    return { icons: [
      { icon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
        backgroundColor: ThemeRuntime.buttonColor(this.appDarkMode),
        iconOptions: { accessibilityText: '编辑连接' },
        onAction: () => this.openEditDialog(connection) },
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode),
        iconOptions: { accessibilityText: '删除连接' },
        onAction: () => this.confirmDeleteConnection(connection) }
    ] };
  }

  @Builder
  connectionSwipeButtons(connection: WebDavConnection) {
    Row() {
      this.connectionEditSwipeButton(connection)
      this.connectionDeleteSwipeButton(connection)
    }
    .height('100%')
  }

  @Builder
  connectionEditSwipeButton(connection: WebDavConnection) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph($r('sys.symbol.square_and_pencil'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('编辑')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
    .onClick(() => {
      if (!this.busy) this.openEditDialog(connection);
    })
  }

  @Builder
  connectionDeleteSwipeButton(connection: WebDavConnection) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
    .onClick(() => {
      if (!this.busy) this.confirmDeleteConnection(connection);
    })
  }

  @Builder
  emptyGuide() {
    Column({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.externaldrive'))
        .fontSize(42)
        .fontColor([this.accentColor()])
      Text('点击右下角添加 WebDAV 服务')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 90, left: 36, right: 36 })
  }

  @Builder
  connectionActionMenu() {
    Scroll() {
      Column() {
        this.connectionContextActionItem($r('sys.symbol.chevron_right'), '浏览', this.primaryTextColor(),
          () => this.browseActionConnection())
        this.connectionContextActionItem($r('sys.symbol.arrow_clockwise'), '测试连接', this.primaryTextColor(),
          () => this.testActionConnection())
        this.connectionContextActionItem($r('sys.symbol.square_and_pencil'), '编辑', this.primaryTextColor(),
          () => this.editActionConnection())
        this.connectionContextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode),
          () => this.confirmDeleteActionConnection())

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  connectionContextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    PopupMenuAction(icon, label, color, action)
  }

  @Builder
  addConnectionFloatingButton() {
    Stack() {
      ImmersiveMaterialSurface({
        surfaceWidth: 52,
        surfaceHeight: 52,
        darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(),
        glowColor: `#40${this.accentColor().substring(1)}`
      }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(25)
          .fontColor([this.accentColor()])
      }
    }
    .width(52)
    .height(52)
    .margin({ right: AppSpacing.XXL, bottom: this.navBarHeight + 22 })
    .accessibilityText('添加 WebDAV 服务')
    .onClick(() => {
      this.openAddDialog();
    })
    .accessibilityRole(AccessibilityRoleType.BUTTON)
  }

  @Builder
  connectionEditorDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text(this.editingConnectionId ? '编辑连接' : '添加连接')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      // 字段区包一层滚动：弹窗高度受限（如输入法弹出）时底部字段仍可达
      Scroll() {
        Column({ space: AppSpacing.LG }) {
          Column({ space: AppSpacing.SM }) {
            Text('名称').fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).width('100%')
            TextInput({ text: this.draftName, placeholder: '例如：我的云盘' })
              .width('100%')
              .height(44)
              .backgroundColor(this.softColor())
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.subTextColor())
              .onChange((value: string) => {
                this.draftName = value;
              })
          }
          .width('100%')
          Column({ space: AppSpacing.SM }) {
            Text('服务器地址').fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).width('100%')
            TextInput({ text: this.draftBaseUrl, placeholder: 'http://192.168.1.10:8080/webdav' })
              .width('100%')
              .height(44)
              .backgroundColor(this.softColor())
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.subTextColor())
              .onChange((value: string) => {
                this.draftBaseUrl = value;
              })
          }
          .width('100%')
          Column({ space: AppSpacing.SM }) {
            Text('书籍目录').fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).width('100%')
            TextInput({ text: this.draftLibraryRoot, placeholder: '留空表示 WebDAV 根目录' })
              .width('100%')
              .height(44)
              .backgroundColor(this.softColor())
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.subTextColor())
              .onChange((value: string) => {
                this.draftLibraryRoot = value;
              })
          }
          .width('100%')
          Column({ space: AppSpacing.SM }) {
            Text('用户名').fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).width('100%')
            TextInput({ text: this.draftUsername, placeholder: 'WebDAV 用户名' })
              .width('100%')
              .height(44)
              .backgroundColor(this.softColor())
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.subTextColor())
              .onChange((value: string) => {
                this.draftUsername = value;
              })
          }
          .width('100%')
          Column({ space: AppSpacing.SM }) {
            Text('密码').fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).width('100%')
            TextInput({ text: this.draftPassword, placeholder: '密码 / 应用专用密码' })
              .type(InputType.Password)
              .width('100%')
              .height(44)
              .backgroundColor(this.softColor())
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.subTextColor())
              .onChange((value: string) => {
                this.draftPassword = value;
              })
          }
          .width('100%')
          Row() {
            Text('记住密码')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            AdaptiveSwitch({
              isOn: this.draftRememberPassword,
              onChange: (value: boolean) => {
                this.draftRememberPassword = value;
              }
            })
          }
          .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.softColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeEditorDialog())
        Button(this.editingConnectionId ? '保存' : '添加')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.accentColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => this.submitEditorDialog())
      }
      .width('100%')
      .margin({ top: AppSpacing.SM })
    }
    .padding(AppSpacing.XXL)
  }

  onSystemDialogFlagChanged(): void {
    if (!this.showConnectionEditorDialog) this.editorDialogSession.close(this.getUIContext());
  }

  async loadConnections(): Promise<void> {
    this.connections = await WebDavSettingsStore.loadConnections(getContext(this));
  }

  openConnection(connection: WebDavConnection): void {
    if (this.busy) return;
    router.pushUrl({ url: 'pages/WebDavBrowse', params: { connectionId: connection.id, title: connection.name } })
      .catch((error: Error) => {
        HdsFeedback.showToast(`无法打开浏览页：${this.message(error)}`);
      });
  }

  openConnectionActions(connection: WebDavConnection, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionConnectionId = connection.id;
    this.showConnectionActionMenu = true;
  }

  closeConnectionActions(): void {
    this.showConnectionActionMenu = false;
    this.actionConnectionId = '';
  }

  actionConnection(): WebDavConnection | null {
    return this.connections.find((item: WebDavConnection): boolean => item.id === this.actionConnectionId) || null;
  }

  browseActionConnection(): void {
    const connection = this.actionConnection();
    this.closeConnectionActions();
    if (connection) this.openConnection(connection);
  }

  testActionConnection(): void {
    const connection = this.actionConnection();
    this.closeConnectionActions();
    if (connection) this.testConnection(connection);
  }

  editActionConnection(): void {
    const connection = this.actionConnection();
    this.closeConnectionActions();
    if (connection) this.openEditDialog(connection);
  }

  confirmDeleteActionConnection(): void {
    const connection = this.actionConnection();
    this.closeConnectionActions();
    if (connection) this.confirmDeleteConnection(connection);
  }

  async testConnection(connection: WebDavConnection): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.busyText = `正在连接“${connection.name}”...`;
    this.busyProgress = 40;
    try {
      const password = await WebDavSecretStore.password(getContext(this), connection.id);
      await new WebDavClient(connection, password).list('');
      this.busyProgress = 100;
      HdsFeedback.showToast('连接成功');
    } catch (error) {
      HdsFeedback.showToast(`连接失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async confirmDeleteConnection(connection: WebDavConnection): Promise<void> {
    const confirmation = await promptAction.showDialog({
      title: '删除连接',
      message: `确定删除“${connection.name}”吗？只会删除本机配置和保存的密码，不会删除远端文件。`,
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
    });
    if (confirmation.index !== 1) return;
    await WebDavSecretStore.deletePassword(getContext(this), connection.id);
    await WebDavSettingsStore.deleteConnection(getContext(this), connection.id);
    this.connections = this.connections.filter((item: WebDavConnection): boolean => item.id !== connection.id);
    HdsFeedback.showToast('连接已删除');
  }

  openAddDialog(): void {
    if (this.busy) return;
    this.editingConnectionId = '';
    this.draftName = '';
    this.draftBaseUrl = '';
    this.draftLibraryRoot = '';
    this.draftUsername = '';
    this.draftPassword = '';
    this.draftRememberPassword = true;
    this.openEditorDialog();
  }

  async openEditDialog(connection: WebDavConnection): Promise<void> {
    if (this.busy) return;
    this.editingConnectionId = connection.id;
    this.draftName = connection.name;
    this.draftBaseUrl = connection.baseUrl;
    this.draftLibraryRoot = connection.libraryRoot;
    this.draftUsername = connection.username;
    this.draftRememberPassword = connection.rememberPassword;
    this.draftPassword = await WebDavSecretStore.password(getContext(this), connection.id);
    this.openEditorDialog();
  }

  openEditorDialog(): void {
    this.showConnectionEditorDialog = true;
    this.editorDialogSession.open(this.getUIContext(), (): void => {
      this.connectionEditorDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示连接编辑弹窗失败:',
      onDismiss: (): void => {
        this.showConnectionEditorDialog = false;
      }
    });
  }

  closeEditorDialog(): void {
    this.showConnectionEditorDialog = false;
    this.editingConnectionId = '';
    this.draftName = '';
    this.draftBaseUrl = '';
    this.draftLibraryRoot = '';
    this.draftUsername = '';
    this.draftPassword = '';
    this.draftRememberPassword = true;
  }

  async submitEditorDialog(): Promise<void> {
    if (this.busy) return;
    const name = this.draftName.trim();
    if (!name) {
      HdsFeedback.showToast('请输入名称');
      return;
    }
    const baseUrl = WebDavSettingsStore.normalizeBaseUrl(this.draftBaseUrl);
    if (!/^https?:\/\//i.test(baseUrl)) {
      HdsFeedback.showToast('服务器地址必须以 http:// 或 https:// 开头');
      return;
    }
    const connection = new WebDavConnection();
    const existing = this.connections.find((item: WebDavConnection): boolean =>
      item.id === this.editingConnectionId);
    if (existing) {
      connection.id = existing.id;
      connection.createdAt = existing.createdAt;
      connection.enabled = existing.enabled;
    }
    connection.name = name;
    connection.baseUrl = baseUrl;
    connection.username = this.draftUsername.trim();
    connection.libraryRoot = WebDavSettingsStore.normalizeRelativePath(this.draftLibraryRoot);
    connection.rememberPassword = this.draftRememberPassword;
    const password = this.draftPassword;
    this.showConnectionEditorDialog = false;
    this.busy = true;
    this.busyText = '正在保存连接...';
    this.busyProgress = 40;
    try {
      const saved = await WebDavSettingsStore.saveConnection(getContext(this), connection);
      let credentialWarning = '';
      try {
        await WebDavSecretStore.savePassword(getContext(this), saved.id, password,
          connection.rememberPassword && !!password);
      } catch (credentialError) {
        await WebDavSecretStore.savePassword(getContext(this), saved.id, password, false);
        credentialWarning = '；系统密钥库不可用，密码仅本次会话有效';
        console.warn('[WebDAV] 凭据持久化已降级:', this.message(credentialError as Object));
      }
      await this.loadConnections();
      this.busyProgress = 100;
      HdsFeedback.showToast(`连接已保存${credentialWarning}`);
    } catch (error) {
      HdsFeedback.showToast(`保存失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
      this.closeEditorDialog();
    }
  }

  cleanupLegacyBackupDraftSecret(): void {
    const run = async (): Promise<void> => {
      try {
        await WebDavSecretStore.deletePassword(getContext(this), '__webdav_form_draft_backup_password__');
      } catch (error) {
        console.warn('[WebDAV] 清理旧备份密码草稿失败:', this.message(error as Object));
      }
    };
    run();
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

  listTopInset(): number {
    return 56 + this.statusBarHeight;
  }

  syncBars(): void { syncSystemBars(getContext(this), this.appDarkMode, this.pageColor()); }
  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }
  softColor(): string { return ThemeRuntime.inputColor(this.appDarkMode); }
}
