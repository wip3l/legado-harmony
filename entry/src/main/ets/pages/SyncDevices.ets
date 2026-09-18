import { promptAction, router } from '@kit.ArkUI';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { CloudSyncDevice } from '../account/CloudSyncModels';
import { CloudSyncStateStore } from '../account/CloudSyncStateStore';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';

@Entry
@Component
struct SyncDevicesPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State devices: CloudSyncDevice[] = [];
  @State currentDeviceId: string = '';
  @State loading: boolean = true;
  @State errorMessage: string = '';
  private renameDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showRenameDialog: boolean = false;
  @State renameDeviceId: string = '';
  @State renameDeviceName: string = '';
  @State renaming: boolean = false;

  aboutToAppear(): void {
    this.loadDevices();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  async loadDevices(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      await AccountSessionStore.load(getContext(this));
      if (!AccountSessionStore.isLoggedIn()) {
        this.errorMessage = '请先登录华为账号';
        return;
      }
      this.currentDeviceId = await CloudSyncStateStore.deviceId(getContext(this));
      const response = await AccountCommerceApi.fetchSyncDevices(AccountSessionStore.token());
      this.devices = (response.devices || []).slice();
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : String(e);
    } finally {
      this.loading = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          Row()
            .height(56 + this.statusBarHeight)

          if (this.loading) {
            Column({ space: 12 }) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(this.accentColor())
              Text('正在读取同步设备…')
                .fontSize(13)
                .fontColor(this.subTextColor())
            }
            .width('100%')
            .padding({ top: 48 })
          } else if (this.errorMessage) {
            Column({ space: 12 }) {
              Text(this.errorMessage)
                .fontSize(14)
                .fontColor(this.subTextColor())
                .textAlign(TextAlign.Center)
              Button('重试')
                .height(40)
                .backgroundColor(this.accentColor())
                .onClick(() => this.loadDevices())
            }
            .width('calc(100% - 24vp)')
            .padding(20)
            .margin({ left: 12, right: 12, top: 20 })
            .borderRadius(16)
            .backgroundColor(this.cardColor())
          } else {
            this.sectionTitle('已登录设备')
            Column() {
              if (this.devices.length === 0) {
                Text('完成首次同步后，当前设备会显示在这里。')
                  .fontSize(13)
                  .fontColor(this.subTextColor())
                  .width('100%')
                  .padding(16)
              } else {
                ForEach(this.devices, (device: CloudSyncDevice, index: number) => {
                  this.deviceItem(device, index < this.devices.length - 1)
                }, (device: CloudSyncDevice) => device.deviceId)
              }
            }
            .width('calc(100% - 24vp)')
            .margin({ left: 12, right: 12 })
            .borderRadius(16)
            .clip(true)
            .backgroundColor(this.cardColor())

            Text('可以移除不再使用的其他设备。本机同步权限需要通过关闭云同步或退出账号进行管理。')
              .fontSize(12)
              .fontColor(this.subTextColor())
              .lineHeight(18)
              .width('calc(100% - 32vp)')
              .margin({ left: 16, right: 16, top: 14 })
          }

          Row()
            .height(32 + this.navBarHeight)
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')

      this.titleBar()

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  deviceItem(device: CloudSyncDevice, showDivider: boolean) {
    Row({ space: 12 }) {
      this.deviceIcon(device)

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(device.deviceName || 'HarmonyOS 设备')
            .fontSize(16)
            .fontColor(this.primaryTextColor())
          if (device.deviceId === this.currentDeviceId) {
            Text('本机')
              .fontSize(11)
              .fontColor(this.accentColor())
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .borderRadius(9)
              .backgroundColor(this.softColor())
          } else if (device.revokedAt) {
            Text('已移除')
              .fontSize(11)
              .fontColor(this.subTextColor())
          }
        }
        Text(`${device.platform || 'HarmonyOS'}${device.appVersion ? ` · ${device.appVersion}` : ''}`)
          .fontSize(12)
          .fontColor(this.subTextColor())
        Text(`最近同步：${this.timeText(device.lastSeenAt)}`)
          .fontSize(12)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!device.revokedAt) {
        Column({ space: 6 }) {
          Button('改名')
            .height(30)
            .fontSize(11)
            .fontColor(this.accentColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.openRename(device))
          if (device.deviceId !== this.currentDeviceId) {
            Button('移除')
              .height(30)
              .fontSize(11)
              .fontColor('#E5484D')
              .backgroundColor(this.softColor())
              .onClick(() => this.confirmRevoke(device))
          }
        }
      }
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 86 })
    .padding({ top: 12, bottom: 12 })
    .margin({ left: 16, right: 16 })
    .border({ width: { bottom: showDivider ? 0.5 : 0 },
      color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  deviceIcon(device: CloudSyncDevice) {
    if (device.deviceKind === 'foldable') {
      Image($r('app.media.ic_device_foldable'))
        .width(32)
        .height(32)
        .fillColor(this.accentColor())
        .opacity(device.revokedAt ? 0.45 : 1)
    } else if (device.deviceKind === '2in1') {
      Image($r('app.media.ic_device_2in1'))
        .width(32)
        .height(32)
        .fillColor(this.accentColor())
        .opacity(device.revokedAt ? 0.45 : 1)
    } else if (device.deviceKind === 'tablet') {
      Image($r('app.media.ic_device_tablet'))
        .width(32)
        .height(32)
        .fillColor(this.accentColor())
        .opacity(device.revokedAt ? 0.45 : 1)
    } else {
      Image($r('app.media.ic_device_phone'))
        .width(32)
        .height(32)
        .fillColor(this.accentColor())
        .opacity(device.revokedAt ? 0.45 : 1)
    }
  }

  openRename(device: CloudSyncDevice): void {
    this.renameDeviceId = device.deviceId;
    this.renameDeviceName = device.deviceName || 'HarmonyOS 设备';
    this.openRenameDialog();
  }

  async saveRename(): Promise<void> {
    const name = this.renameDeviceName.trim();
    if (!name || this.renaming) {
      return;
    }
    this.renaming = true;
    try {
      await AccountCommerceApi.renameSyncDevice(
        this.renameDeviceId, name, AccountSessionStore.token());
      this.showRenameDialog = false;
      HdsFeedback.showToast('设备名称已更新');
      await this.loadDevices();
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? `改名失败：${e.message}` : '设备改名失败');
    } finally {
      this.renaming = false;
    }
  }


  onSystemDialogFlagChanged(): void {
    if (!this.showRenameDialog) this.renameDialogSession.close(this.getUIContext());
  }

  openRenameDialog(): void {
    this.showRenameDialog = true;
    this.renameDialogSession.open(this.getUIContext(), (): void => {
      this.renameDialogContent();
    }, {
      autoCancel: true,
      maskColor: this.appDarkMode ? '#99000000' : '#33000000',
      warnTag: '显示设备重命名弹窗失败:'
    });
  }

  @Builder
  renameDialogContent() {
    Column({ space: 16 }) {
      Text('修改设备名称')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      TextInput({ placeholder: '输入设备名称', text: this.renameDeviceName })
        .width('100%')
        .height(42)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.softColor())
        .borderRadius(10)
        .maxLength(80)
        .onChange((value: string) => {
          this.renameDeviceName = value;
        })
      Row({ space: 12 }) {
        Button('取消', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(10)
          .backgroundColor(this.cardColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.showRenameDialog = false;
          })
        Button(this.renaming ? '保存中' : '保存', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(10)
          .backgroundColor(this.accentColor())
          .fontColor('#FFFFFF')
          .enabled(!!this.renameDeviceName.trim() && !this.renaming)
          .onClick(() => this.saveRename())
      }
      .width('100%')
    }    .constraintSize({ maxWidth: 360 })
    .padding(20)
  }


  async confirmRevoke(device: CloudSyncDevice): Promise<void> {
    const result = await promptAction.showDialog({
      title: '移除同步设备',
      message: `确定移除“${device.deviceName || 'HarmonyOS 设备'}”吗？`,
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '移除', color: '#E5484D' }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    try {
      await AccountCommerceApi.revokeSyncDevice(device.deviceId, AccountSessionStore.token());
      HdsFeedback.showToast('设备已移除');
      await this.loadDevices();
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? `移除失败：${e.message}` : '移除设备失败');
    }
  }

  timeText(timestamp: number): string {
    return timestamp > 0 ? new Date(timestamp).toLocaleString() : '尚未同步';
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  softColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
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
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('同步设备')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(20)
        .fontColor([this.accentColor()])
        .width(48)
        .height(48)
        .onClick(() => this.loadDevices())
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ top: this.statusBarHeight })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
    .alignItems(VerticalAlign.Center)
  }
}
