import { router, promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { OpdsServerConfig } from '../opds/OpdsModels';
import { OpdsSettingsStore } from '../opds/OpdsSettingsStore';
import { OpdsSecretStore } from '../opds/OpdsSecretStore';
import { OpdsClient } from '../opds/OpdsClient';
import { OpdsError } from '../opds/OpdsError';
import { OpdsKavita } from '../opds/OpdsKavita';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';

@Entry
@Component
struct OpdsServersPage {
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State servers: OpdsServerConfig[] = [];
  @State busy: boolean = false;
  @State busyText: string = '';
  @State busyProgress: number = 0;
  @State showServerActionMenu: boolean = false;
  @State actionServerId: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State @Watch('onSystemDialogFlagChanged') showServerEditorDialog: boolean = false;
  @State editingServerId: string = '';
  @State draftName: string = '';
  @State draftBaseUrl: string = '';
  @State draftNeedLogin: boolean = false;
  @State draftUsername: string = '';
  @State draftPassword: string = '';
  @State draftRememberPassword: boolean = true;
  private editorDialogSession: SystemDialogSession = new SystemDialogSession();

  aboutToAppear(): void {
    this.syncBars();
    this.loadServers();
  }

  onPageShow(): void {
    this.syncBars();
  }

  onBackPress(): boolean {
    if (this.showServerActionMenu) {
      this.closeServerActions();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: 'OPDS 书库', scrollable: false, externalCollapse: this.headerCollapse, content: () => {
        this.pageContent()
      } })

      if (this.showServerActionMenu) {
        this.serverActionMenu()
      }

      if (!this.showServerActionMenu && !this.showServerEditorDialog && !this.busy) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.addServerFloatingButton()
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
    this.serverList()
  }

  @Builder
  addServerFloatingButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(25)
        .fontColor([this.accentColor()])
    }
    .width(52)
    .height(52)
    .margin({ right: AppSpacing.XXL, bottom: this.navBarHeight + 22 })
    .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, this.cardColor(), 'button'))
    .backdropBlur(ThemeRuntime.glassBlur('button', 12))
    .border({ width: ThemeRuntime.glassBorderWidth('button'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'button') })
    .shadow({ radius: ThemeRuntime.glassShadowRadius('button'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'button'), offsetX: ThemeRuntime.glassShadowOffsetX('button'), offsetY: ThemeRuntime.glassShadowOffsetY('button') })
    .accessibilityText('添加 OPDS 书库')
    .onClick(() => {
      this.openAddDialog();
    })
  }

  @Builder
  serverList() {
    Column() {
      if (this.servers.length === 0) {
        this.emptyGuide()
      } else {
        List({ scroller: this.headerScroller, space: AppSpacing.MD }) {
          ListItem() {
            Row()
              .height(this.listTopInset())
              .hitTestBehavior(HitTestMode.None)
          }

          ForEach(this.servers, (server: OpdsServerConfig) => {
            if (deviceInfo.sdkApiVersion >= 26) {
              HdsListItem({
                customItemBuilder: (): void => {
                  this.serverRow(server)
                },
                swipeActionOptions: this.serverSwipeActions(server)
              })
            }
            if (deviceInfo.sdkApiVersion < 26) {
              ListItem() {
                this.serverRow(server)
              }
              .borderRadius(ThemeRuntime.mediumRadius())
              .clip(true)
              .swipeAction(this.busy ? {} : {
                end: {
                  builder: (): void => {
                    this.serverSwipeButtons(server)
                  },
                  actionAreaDistance: 128,
                  onAction: (): void => {
                    if (!this.busy) this.confirmDeleteServer(server);
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
            }
          }, (server: OpdsServerConfig) => server.id)

          ListItem() {
            Text('仅支持下载 EPUB / TXT / MOBI 格式')
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
  serverRow(server: OpdsServerConfig) {
    Row({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.bookshelf'))
        .fontSize(26)
        .fontColor([this.accentColor()])
      Column({ space: AppSpacing.XS }) {
        Text(server.name)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(OpdsKavita.maskedUrl(server.baseUrl))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: AppSpacing.MD }) {
          if (server.authType === 'basic' && server.username) {
            Text(`账号：${server.username}`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(server.enabled ? '已启用' : '已停用')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(server.enabled ? this.subTextColor() : ThemeRuntime.dangerColor(this.appDarkMode))
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
          if (!this.busy) this.openServerActions(server, event);
        })
    )
    .onClick(() => {
      if (!this.showServerActionMenu && !this.showServerEditorDialog) this.openServer(server);
    })
  }

  private serverSwipeActions(server: OpdsServerConfig): HdsSwipeActionOptions {
    if (this.busy) return { icons: [] };
    return { icons: [
      { icon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
        backgroundColor: ThemeRuntime.buttonColor(this.appDarkMode),
        iconOptions: { accessibilityText: '编辑书库' },
        onAction: () => this.openEditDialog(server) },
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode),
        iconOptions: { accessibilityText: '删除书库' },
        onAction: () => this.confirmDeleteServer(server) }
    ] };
  }

  @Builder
  serverSwipeButtons(server: OpdsServerConfig) {
    Row() {
      this.serverEditSwipeButton(server)
      this.serverDeleteSwipeButton(server)
    }
    .height('100%')
  }

  @Builder
  serverEditSwipeButton(server: OpdsServerConfig) {
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
      if (!this.busy) this.openEditDialog(server);
    })
  }

  @Builder
  serverDeleteSwipeButton(server: OpdsServerConfig) {
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
      if (!this.busy) this.confirmDeleteServer(server);
    })
  }

  @Builder
  emptyGuide() {
    Column({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.bookshelf'))
        .fontSize(42)
        .fontColor([this.accentColor()])
      Text('点击右下角添加 Calibre、Komga、Kavita 等 OPDS 书库')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 90, left: 36, right: 36 })
  }

  @Builder
  serverActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#38000000' : '#18FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('button', 12))
        .onClick(() => this.closeServerActions())
      Column() {
        this.serverContextActionItem($r('sys.symbol.arrow_clockwise'), '测试连接', this.primaryTextColor(),
          () => this.testActionServer())
        this.serverContextActionItem($r('sys.symbol.square_and_pencil'), '编辑', this.primaryTextColor(),
          () => this.editActionServer())
        this.serverContextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode),
          () => this.confirmDeleteActionServer())
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
      .position({ x: this.contextMenuLeft(148), y: this.contextMenuTop(144) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  serverContextActionItem(icon: Resource, label: string, color: string, action: () => void) {
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

  @Builder
  serverEditorDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text(this.editingServerId ? '编辑书库' : '添加书库')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      // 字段区包一层滚动：弹窗高度受限（如输入法弹出）时底部字段仍可达
      Scroll() {
        Column({ space: AppSpacing.LG }) {
          Column({ space: AppSpacing.SM }) {
            Text('名称').fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).width('100%')
            TextInput({ text: this.draftName, placeholder: '例如：我的 Calibre 书库' })
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
            TextInput({ text: this.draftBaseUrl, placeholder: 'http://192.168.1.10:8080/opds' })
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
          Row() {
            Column({ space: AppSpacing.XXS }) {
              Text('需要登录')
                .fontSize(AppFontSize.BODY)
                .fontColor(this.primaryTextColor())
              Text('Calibre、Komga 等的账号；Kavita 填账号可自动获取 OPDS 地址')
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            AdaptiveSwitch({
              isOn: this.draftNeedLogin,
              onChange: (value: boolean) => {
                this.draftNeedLogin = value;
              }
            })
          }
          .width('100%')
          if (this.draftNeedLogin) {
            Column({ space: AppSpacing.SM }) {
              Text('账号').fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).width('100%')
              TextInput({ text: this.draftUsername, placeholder: '登录用户名' })
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
              TextInput({ text: this.draftPassword, placeholder: '登录密码' })
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
        Button(this.editingServerId ? '保存' : '添加')
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
    if (!this.showServerEditorDialog) this.editorDialogSession.close(this.getUIContext());
  }

  async loadServers(): Promise<void> {
    this.servers = await OpdsSettingsStore.loadServers(getContext(this));
  }

  openServer(server: OpdsServerConfig): void {
    if (this.busy) return;
    router.pushUrl({ url: 'pages/OpdsBrowse', params: { serverId: server.id, title: server.name } })
      .catch((error: Error) => {
        HdsFeedback.showToast(`无法打开书库：${this.message(error)}`);
      });
  }

  openServerActions(server: OpdsServerConfig, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionServerId = server.id;
    this.showServerActionMenu = true;
  }

  closeServerActions(): void {
    this.showServerActionMenu = false;
    this.actionServerId = '';
  }

  actionServer(): OpdsServerConfig | null {
    return this.servers.find((item: OpdsServerConfig): boolean => item.id === this.actionServerId) || null;
  }

  testActionServer(): void {
    const server = this.actionServer();
    this.closeServerActions();
    if (server) this.testServer(server);
  }

  editActionServer(): void {
    const server = this.actionServer();
    this.closeServerActions();
    if (server) this.openEditDialog(server);
  }

  confirmDeleteActionServer(): void {
    const server = this.actionServer();
    this.closeServerActions();
    if (server) this.confirmDeleteServer(server);
  }

  async testServer(server: OpdsServerConfig): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.busyText = `正在连接“${server.name}”...`;
    this.busyProgress = 40;
    try {
      const password = await OpdsSecretStore.password(getContext(this), server.id);
      const catalog = await new OpdsClient(server, password).fetchCatalog(server.baseUrl);
      if (catalog.url !== server.baseUrl) {
        // 地址被自动纠正（尾斜杠、/opds、Kavita 登录换取的地址）：存回配置，下次直接用
        server.baseUrl = catalog.url;
        await OpdsSettingsStore.saveServer(getContext(this), server);
        await this.loadServers();
      }
      this.busyProgress = 100;
      HdsFeedback.showToast(`连接成功，共 ${catalog.feed.entries.length} 个条目`);
    } catch (error) {
      const failure = error instanceof OpdsError ? error : null;
      const detail = failure ? failure.userMessage : this.message(error);
      if (failure && failure.code === 'auth') {
        HdsFeedback.showToast(`连接失败：${detail}，请检查账号和密码`);
      } else {
        HdsFeedback.showToast(`连接失败：${detail}`);
      }
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async confirmDeleteServer(server: OpdsServerConfig): Promise<void> {
    const confirmation = await promptAction.showDialog({
      title: '删除书库',
      message: `确定删除“${server.name}”吗？只会删除本机配置和保存的密码，不会删除远端图书。`,
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
    });
    if (confirmation.index !== 1) return;
    await OpdsSecretStore.deletePassword(getContext(this), server.id);
    await OpdsSettingsStore.deleteServer(getContext(this), server.id);
    this.servers = this.servers.filter((item: OpdsServerConfig): boolean => item.id !== server.id);
    HdsFeedback.showToast('书库已删除');
  }

  openAddDialog(): void {
    if (this.busy) return;
    this.editingServerId = '';
    this.draftName = '';
    this.draftBaseUrl = '';
    this.draftNeedLogin = false;
    this.draftUsername = '';
    this.draftPassword = '';
    this.draftRememberPassword = true;
    this.openEditorDialog();
  }

  async openEditDialog(server: OpdsServerConfig): Promise<void> {
    if (this.busy) return;
    this.editingServerId = server.id;
    this.draftName = server.name;
    this.draftBaseUrl = server.baseUrl;
    this.draftNeedLogin = server.authType === 'basic';
    this.draftUsername = server.username;
    this.draftRememberPassword = server.rememberPassword;
    this.draftPassword = await OpdsSecretStore.password(getContext(this), server.id);
    this.openEditorDialog();
  }

  openEditorDialog(): void {
    this.showServerEditorDialog = true;
    this.editorDialogSession.open(this.getUIContext(), (): void => {
      this.serverEditorDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示书库编辑弹窗失败:',
      onDismiss: (): void => {
        this.showServerEditorDialog = false;
      }
    });
  }

  closeEditorDialog(): void {
    this.showServerEditorDialog = false;
    this.editingServerId = '';
    this.draftName = '';
    this.draftBaseUrl = '';
    this.draftNeedLogin = false;
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
    const baseUrl = OpdsSettingsStore.normalizeBaseUrl(this.draftBaseUrl);
    if (!/^https?:\/\//i.test(baseUrl)) {
      HdsFeedback.showToast('服务器地址必须以 http:// 或 https:// 开头');
      return;
    }
    if (this.draftNeedLogin && !this.draftUsername.trim()) {
      HdsFeedback.showToast('请输入账号');
      return;
    }
    const server = new OpdsServerConfig();
    const existing = this.servers.find((item: OpdsServerConfig): boolean =>
      item.id === this.editingServerId);
    if (existing) {
      server.id = existing.id;
      server.createdAt = existing.createdAt;
      server.enabled = existing.enabled;
    }
    server.name = name;
    server.baseUrl = baseUrl;
    server.authType = this.draftNeedLogin ? 'basic' : 'none';
    server.username = this.draftNeedLogin ? this.draftUsername.trim() : '';
    server.rememberPassword = this.draftRememberPassword;
    const password = this.draftNeedLogin ? this.draftPassword : '';
    this.showServerEditorDialog = false;
    this.busy = true;
    this.busyText = '正在保存书库...';
    this.busyProgress = 40;
    try {
      const saved = await OpdsSettingsStore.saveServer(getContext(this), server);
      let credentialWarning = '';
      try {
        await OpdsSecretStore.savePassword(getContext(this), saved.id, password,
          server.rememberPassword && !!password);
      } catch (credentialError) {
        await OpdsSecretStore.savePassword(getContext(this), saved.id, password, false);
        credentialWarning = '；系统密钥库不可用，密码仅本次会话有效';
        console.warn('[OPDS] 凭据持久化已降级:', this.message(credentialError as Object));
      }
      await this.loadServers();
      this.busyProgress = 100;
      HdsFeedback.showToast(`书库已保存${credentialWarning}`);
    } catch (error) {
      HdsFeedback.showToast(`保存失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
      this.closeEditorDialog();
    }
  }

  message(error: Object): string {
    return OpdsError.message(error);
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
