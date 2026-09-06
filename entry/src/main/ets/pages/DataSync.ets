import { promptAction, router } from '@kit.ArkUI';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { CloudSyncSettings, CloudSyncSettingsStore } from '../account/CloudSyncSettingsStore';
import { CloudSyncCoordinator } from '../account/CloudSyncCoordinator';
import { CloudSyncStateStore } from '../account/CloudSyncStateStore';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct DataSyncPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('accountLoggedIn') accountLoggedIn: boolean = false;
  @State cloudSyncEnabled: boolean = false;
  @State autoSyncEnabled: boolean = true;
  @State wifiOnly: boolean = false;
  @State foregroundSyncEnabled: boolean = false;
  @State readingDataEnabled: boolean = true;
  @State bookSourcesEnabled: boolean = true;
  @State readingPreferencesEnabled: boolean = true;
  @State applicationPreferencesEnabled: boolean = true;
  @StorageLink('cloudSyncLastSuccessAt') lastSuccessAt: number = 0;
  @StorageLink('cloudSyncPendingCount') pendingCount: number = 0;
  @StorageLink('cloudSyncStatus') syncStatus: string = CloudSyncSettingsStore.STATUS_DISABLED;
  @StorageLink('cloudSyncErrorMessage') syncErrorMessage: string = '';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State saving: boolean = false;
  @State loadingSettings: boolean = false;
  private loadedUserId: string = '__not_loaded__';

  aboutToAppear(): void {
    this.loadSettings();
    this.syncBars();
  }

  onPageShow(): void {
    const currentUserId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
    if (!this.loadingSettings && currentUserId !== this.loadedUserId) {
      this.loadSettings();
    }
    this.syncBars();
  }

  async loadSettings(): Promise<void> {
    if (this.loadingSettings) {
      return;
    }
    this.loadingSettings = true;
    try {
      await AccountSessionStore.load(getContext(this));
      const userId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      const settings = await CloudSyncSettingsStore.load(getContext(this), userId);
      this.applyLoadedSettings(settings);
      this.loadedUserId = userId;
    } catch (e) {
      console.warn('读取云同步设置失败:', e);
      promptAction.showToast({ message: '读取同步设置失败' });
    } finally {
      this.loadingSettings = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          Row()
            .height(56 + this.statusBarHeight)

          this.statusCard()

          this.sectionTitle('同步设置')
          if (this.loadingSettings) {
            this.settingsLoadingCard()
          } else {
            Column() {
              this.switchItem('云同步', '登录后在设备之间同步阅读数据和阅读偏好',
                this.cloudSyncEnabled, true, (value: boolean) => {
                  this.setCloudSyncEnabled(value);
                })
              this.switchItem('自动同步', '数据修改后自动同步，失败时保留待同步任务',
                this.autoSyncEnabled, true, (value: boolean) => {
                  this.autoSyncEnabled = value;
                  this.saveSettings();
                })
              this.switchItem('仅 Wi-Fi 自动同步', '开启后移动网络下仍可手动同步',
                this.wifiOnly, true, (value: boolean) => {
                  this.wifiOnly = value;
                  this.saveSettings();
                })
              this.switchItem('回到前台时同步', '打开应用或重新进入前台时检查云端变更',
                this.foregroundSyncEnabled, true, (value: boolean) => {
                  this.foregroundSyncEnabled = value;
                  this.saveSettings();
                }, false)
            }
            .width('calc(100% - 24vp)')
            .margin({ left: 12, right: 12 })
            .borderRadius(16)
            .clip(true)
            .backgroundColor(this.cardColor())

            this.sectionTitle('同步内容')
            Column() {
              this.switchItem('阅读数据', '在线书架、分组、排序、阅读进度、书签；本地书仅同步阅读进度',
                this.readingDataEnabled, true, (value: boolean) => {
                  this.setScopeEnabled(true, value);
                })
              this.switchItem('书源', '书源配置、分组、排序、启用和锁定状态，不同步登录凭证',
                this.bookSourcesEnabled, true, (value: boolean) => {
                  this.setBookSourcesEnabled(value);
                })
              this.switchItem('阅读偏好', '字体大小、边距、字体规则、替换规则、主题设置',
                this.readingPreferencesEnabled, true, (value: boolean) => {
                  this.setScopeEnabled(false, value);
                })
              this.switchItem('应用偏好', '显示模式、书架布局、搜索显示、自定义主题方案',
                this.applicationPreferencesEnabled, true, (value: boolean) => {
                  this.setApplicationScopeEnabled(value);
                }, false)
            }
            .width('calc(100% - 24vp)')
            .margin({ left: 12, right: 12 })
            .borderRadius(16)
            .clip(true)
            .backgroundColor(this.cardColor())
          }

          this.sectionTitle('管理')
          Column() {
            this.actionItem('同步设备', '查看和管理使用当前账号同步的设备', true, () => {
              if (!this.accountLoggedIn) {
                promptAction.showToast({ message: '请先登录华为账号' });
                return;
              }
              router.pushUrl({ url: 'pages/SyncDevices' });
            })
            this.actionItem('同步问题', this.syncErrorMessage || '当前没有需要处理的同步问题', true, () => {
              if (this.syncErrorMessage) {
                promptAction.showToast({ message: this.syncErrorMessage });
              } else {
                promptAction.showToast({ message: '当前没有同步问题' });
              }
            })
            this.actionItem('重新从云端同步', '保留本机待上传修改，重新获取云端数据', false, () => {
              this.confirmReloadFromCloud();
            })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          Text('数据导入和导出仍位于“其他设置”，用于手动备份，不会代替云同步。')
            .fontSize(12)
            .fontColor(this.subTextColor())
            .lineHeight(18)
            .width('calc(100% - 32vp)')
            .margin({ left: 16, right: 16, top: 14, bottom: 32 + this.navBarHeight })
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)

      this.titleBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  statusCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('云同步')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(this.statusSummary())
            .fontSize(13)
            .fontColor(this.statusColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.syncStatus === CloudSyncSettingsStore.STATUS_SYNCING) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(this.accentColor())
        } else {
          Text(this.cloudSyncEnabled && this.accountLoggedIn ? '已开启' : '未开启')
            .fontSize(12)
            .fontColor(this.cloudSyncEnabled && this.accountLoggedIn ? this.accentColor() : this.subTextColor())
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(12)
            .backgroundColor(this.softColor())
        }
      }
      .width('100%')

      if (!this.accountLoggedIn) {
        Text('登录华为账号后，可跨设备同步书架、阅读进度和阅读设置；本地书不会上传文件。')
          .fontSize(13)
          .fontColor(this.subTextColor())
          .lineHeight(20)
          .width('100%')
        Button('登录并开启同步')
          .width('100%')
          .height(42)
          .backgroundColor(this.accentColor())
          .onClick(() => {
            router.pushUrl({ url: 'pages/AccountCenter' });
          })
      } else {
        Text(this.lastSyncDescription())
          .fontSize(12)
          .fontColor(this.subTextColor())
          .width('100%')
        Button(this.syncStatus === CloudSyncSettingsStore.STATUS_SYNCING ? '正在同步' : '立即同步')
          .width('100%')
          .height(42)
          .enabled(!this.saving && this.syncStatus !== CloudSyncSettingsStore.STATUS_SYNCING)
          .fontColor(this.cloudSyncEnabled ? Color.White : this.primaryTextColor())
          .backgroundColor(this.cloudSyncEnabled ? this.accentColor() : this.softColor())
          .onClick(() => {
            this.syncNow();
          })
      }
    }
    .width('calc(100% - 24vp)')
    .padding(16)
    .margin({ left: 12, right: 12, top: 12 })
    .borderRadius(16)
    .backgroundColor(this.cardColor())
  }

  @Builder
  settingsLoadingCard() {
    Row({ space: 10 }) {
      LoadingProgress()
        .width(22)
        .height(22)
        .color(this.accentColor())
      Text('正在读取本机同步设置')
        .fontSize(14)
        .fontColor(this.subTextColor())
    }
    .width('calc(100% - 24vp)')
    .height(72)
    .padding({ left: 16, right: 16 })
    .margin({ left: 12, right: 12 })
    .borderRadius(16)
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  switchItem(title: string, desc: string, value: boolean, enabled: boolean,
    onChange: (value: boolean) => void, showDivider: boolean = true) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(enabled ? this.primaryTextColor() : this.subTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.buttonColor())
        .enabled(enabled)
        .opacity(enabled ? 1 : 0.45)
        .onChange((checked: boolean) => {
          onChange(checked);
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .border({ width: { bottom: showDivider ? 0.5 : 0 },
      color: this.dividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  actionItem(title: string, desc: string, showDivider: boolean, onClick: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .border({ width: { bottom: showDivider ? 0.5 : 0 },
      color: this.dividerColor() })
    .alignItems(VerticalAlign.Center)
    .onClick(onClick)
  }

  async setCloudSyncEnabled(value: boolean): Promise<void> {
    if (value && !this.accountLoggedIn) {
      promptAction.showToast({ message: '请先登录华为账号' });
      router.pushUrl({ url: 'pages/AccountCenter' });
      return;
    }
    this.cloudSyncEnabled = value;
    this.syncStatus = value ? CloudSyncSettingsStore.STATUS_NOT_STARTED :
      CloudSyncSettingsStore.STATUS_DISABLED;
    this.syncErrorMessage = '';
    await this.saveSettings();
    if (value) {
      try {
        const conflictPolicy = await this.initialConflictPolicy();
        await this.syncNow(conflictPolicy);
      } catch (e) {
        promptAction.showToast({
          message: e instanceof Error ? e.message : '暂时无法检查云端数据'
        });
      }
    }
  }

  async initialConflictPolicy(): Promise<string> {
    try {
      if (!(await CloudSyncCoordinator.needsInitialConflictChoice(getContext(this)))) {
        return 'cloud';
      }
      const result = await promptAction.showDialog({
        title: '选择首次同步方式',
        message: '检测到云端已有同步数据。如果本机与云端的同一项数据发生冲突，请选择以哪一端为准。未冲突的数据仍会正常合并。',
        buttons: [
          { text: '云端为主', color: this.subTextColor() },
          { text: '本地为主', color: this.accentColor() }
        ]
      });
      return result.index === 1 ? 'local' : 'cloud';
    } catch (e) {
      console.warn('检查首次同步状态失败:', e);
      throw new Error('暂时无法检查云端数据，请稍后重试');
    }
  }

  async setScopeEnabled(readingData: boolean, value: boolean): Promise<void> {
    const otherEnabled = readingData ?
      (this.bookSourcesEnabled || this.readingPreferencesEnabled || this.applicationPreferencesEnabled) :
      (this.readingDataEnabled || this.bookSourcesEnabled || this.applicationPreferencesEnabled);
    if (!value && !otherEnabled) {
      promptAction.showToast({ message: '请至少保留一项同步内容' });
      return;
    }
    if (readingData) {
      this.readingDataEnabled = value;
    } else {
      this.readingPreferencesEnabled = value;
    }
    await this.saveSettings();
    if (value && this.cloudSyncEnabled && this.accountLoggedIn) {
      const userId = AccountSessionStore.account().userId;
      await CloudSyncStateStore.resetCursor(getContext(this), userId);
      await this.syncNow();
    }
  }

  async setApplicationScopeEnabled(value: boolean): Promise<void> {
    if (!value && !this.readingDataEnabled && !this.bookSourcesEnabled &&
      !this.readingPreferencesEnabled) {
      promptAction.showToast({ message: '请至少保留一项同步内容' });
      return;
    }
    this.applicationPreferencesEnabled = value;
    await this.saveSettings();
    if (value && this.cloudSyncEnabled && this.accountLoggedIn) {
      const userId = AccountSessionStore.account().userId;
      await CloudSyncStateStore.resetCursor(getContext(this), userId);
      await this.syncNow();
    }
  }

  async setBookSourcesEnabled(value: boolean): Promise<void> {
    if (!value && !this.readingDataEnabled && !this.readingPreferencesEnabled &&
      !this.applicationPreferencesEnabled) {
      promptAction.showToast({ message: '请至少保留一项同步内容' });
      return;
    }
    this.bookSourcesEnabled = value;
    await this.saveSettings();
    if (value && this.cloudSyncEnabled && this.accountLoggedIn) {
      const userId = AccountSessionStore.account().userId;
      await CloudSyncStateStore.resetCursor(getContext(this), userId);
      await this.syncNow();
    }
  }

  async saveSettings(): Promise<void> {
    this.saving = true;
    try {
      const settings = this.currentSettings();
      const userId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      await CloudSyncSettingsStore.saveUserPreferences(getContext(this), userId, settings);
      this.loadedUserId = userId;
    } catch (e) {
      console.warn('保存云同步设置失败:', e);
      promptAction.showToast({ message: '保存同步设置失败' });
    } finally {
      this.saving = false;
    }
  }

  async syncNow(conflictPolicy: string = 'cloud'): Promise<void> {
    if (!this.accountLoggedIn) {
      router.pushUrl({ url: 'pages/AccountCenter' });
      return;
    }
    if (!this.cloudSyncEnabled) {
      promptAction.showToast({ message: '请先开启云同步' });
      return;
    }
    this.saving = true;
    try {
      const result = await CloudSyncCoordinator.syncNow(getContext(this), conflictPolicy);
      const details: string[] = [];
      if (result.uploaded > 0) details.push(`上传 ${result.uploaded} 项`);
      if (result.downloaded > 0) details.push(`下载 ${result.downloaded} 项`);
      if (result.conflicts > 0) details.push(`处理 ${result.conflicts} 个冲突`);
      promptAction.showToast({ message: details.length > 0 ? `同步完成：${details.join('，')}` : '所有数据已同步' });
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      promptAction.showToast({ message: `同步失败：${message}` });
    } finally {
      this.saving = false;
    }
  }

  async confirmReloadFromCloud(): Promise<void> {
    if (!this.accountLoggedIn || !this.cloudSyncEnabled) {
      promptAction.showToast({ message: this.accountLoggedIn ? '请先开启云同步' : '请先登录华为账号' });
      return;
    }
    const result = await promptAction.showDialog({
      title: '重新从云端同步',
      message: '将重新获取云端阅读数据，本机尚未上传的修改会继续保留。',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '继续', color: this.accentColor() }
      ]
    });
    if (result.index === 1) {
      const userId = AccountSessionStore.account().userId;
      await CloudSyncStateStore.resetCursor(getContext(this), userId);
      await this.syncNow();
    }
  }

  currentSettings(): CloudSyncSettings {
    const settings = new CloudSyncSettings();
    settings.enabled = this.cloudSyncEnabled;
    settings.autoSyncEnabled = this.autoSyncEnabled;
    settings.wifiOnly = this.wifiOnly;
    settings.foregroundSyncEnabled = this.foregroundSyncEnabled;
    settings.readingDataEnabled = this.readingDataEnabled;
    settings.bookSourcesEnabled = this.bookSourcesEnabled;
    settings.readingPreferencesEnabled = this.readingPreferencesEnabled;
    settings.applicationPreferencesEnabled = this.applicationPreferencesEnabled;
    settings.lastSuccessAt = this.lastSuccessAt;
    settings.pendingCount = this.pendingCount;
    settings.status = this.syncStatus;
    settings.errorMessage = this.syncErrorMessage;
    return settings;
  }

  applyLoadedSettings(settings: CloudSyncSettings): void {
    this.cloudSyncEnabled = settings.enabled;
    this.autoSyncEnabled = settings.autoSyncEnabled;
    this.wifiOnly = settings.wifiOnly;
    this.foregroundSyncEnabled = settings.foregroundSyncEnabled;
    this.readingDataEnabled = settings.readingDataEnabled;
    this.bookSourcesEnabled = settings.bookSourcesEnabled;
    this.readingPreferencesEnabled = settings.readingPreferencesEnabled;
    this.applicationPreferencesEnabled = settings.applicationPreferencesEnabled;
    this.lastSuccessAt = settings.lastSuccessAt;
    this.pendingCount = settings.pendingCount;
    this.syncStatus = settings.status;
    this.syncErrorMessage = settings.errorMessage;
  }

  statusSummary(): string {
    return CloudSyncSettingsStore.statusSummary(this.accountLoggedIn, this.cloudSyncEnabled,
      this.syncStatus, this.pendingCount, this.lastSuccessAt);
  }

  lastSyncDescription(): string {
    if (this.lastSuccessAt <= 0) {
      return this.cloudSyncEnabled ? '开启后将在同步服务可用时进行首次同步' : '开启云同步后才会上传数据';
    }
    return `上次同步：${new Date(this.lastSuccessAt).toLocaleString()}`;
  }

  statusColor(): string {
    if (this.syncStatus === CloudSyncSettingsStore.STATUS_ERROR) {
      return '#E5484D';
    }
    if (this.cloudSyncEnabled && this.accountLoggedIn) {
      return this.accentColor();
    }
    return this.subTextColor();
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

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  dividerColor(): string {
    return this.appDarkMode ? '#24FFFFFF' : '#14000000';
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
      Text('数据同步')
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
}
