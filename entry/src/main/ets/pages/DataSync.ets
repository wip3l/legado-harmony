import { promptAction, router } from '@kit.ArkUI';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { CloudSyncSettings, CloudSyncSettingsStore } from '../account/CloudSyncSettingsStore';
import { CloudSyncCoordinator } from '../account/CloudSyncCoordinator';
import { CloudSyncIssueStore } from '../account/CloudSyncIssueStore';
import { CloudSyncStateStore } from '../account/CloudSyncStateStore';
import { CloudAutoSync } from '../account/CloudAutoSync';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingSwitchRow, SettingRow } from '../components/common/SettingRow';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';

@Entry
@Component
struct DataSyncPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('accountLoggedIn') accountLoggedIn: boolean = false;
  @StorageLink('accountMembershipSku') membershipSku: string = '';
  @State cloudSyncEnabled: boolean = false;
  @State autoSyncEnabled: boolean = true;
  @State wifiOnly: boolean = false;
  @State foregroundSyncEnabled: boolean = false;
  @State localBooksEnabled: boolean = true;
  @State customFontsEnabled: boolean = true;
  @State readingDataEnabled: boolean = true;
  @State bookSourcesEnabled: boolean = true;
  @State readingPreferencesEnabled: boolean = true;
  @State applicationPreferencesEnabled: boolean = true;
  @StorageLink('cloudSyncLastSuccessAt') lastSuccessAt: number = 0;
  @StorageLink('cloudSyncPendingCount') pendingCount: number = 0;
  @StorageLink('cloudSyncStatus') syncStatus: string = CloudSyncSettingsStore.STATUS_DISABLED;
  @StorageLink('cloudSyncErrorMessage') syncErrorMessage: string = '';
  @StorageLink('cloudSyncIssueCount') issueCount: number = 0;
  @StorageLink('cloudSyncIssueLatest') latestIssue: string = '';
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
      await CloudSyncIssueStore.load(getContext(this), userId);
    } catch (e) {
      console.warn('读取云同步设置失败:', e);
      HdsFeedback.showToast('读取同步设置失败');
    } finally {
      this.loadingSettings = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '数据同步', bottomInset: 0, content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    this.statusCard()

    this.sectionTitle('同步设置')
    if (this.loadingSettings) {
      this.settingsLoadingCard()
    } else {
      Column() {
        SettingSwitchRow({
          title: '云同步',
          description: '登录后在多台设备间同步',
          isOn: this.cloudSyncEnabled,
          onChange: (value: boolean) => {
            this.setCloudSyncEnabled(value);
          }
        })
        SettingSwitchRow({
          title: '自动同步',
          description: '数据变更后自动同步，失败后稍后重试',
          isOn: this.autoSyncEnabled,
          onChange: (value: boolean) => {
            this.autoSyncEnabled = value;
            this.saveSettings();
          }
        })
        SettingSwitchRow({
          title: '仅 Wi-Fi 自动同步',
          description: '移动网络下仍可手动同步',
          isOn: this.wifiOnly,
          onChange: (value: boolean) => {
            this.wifiOnly = value;
            this.saveSettings();
          }
        })
        SettingSwitchRow({
          title: '回到前台时同步',
          description: '打开或切回应用时检查云端变更',
          isOn: this.foregroundSyncEnabled,
          showDivider: false,
          onChange: (value: boolean) => {
            this.foregroundSyncEnabled = value;
            this.saveSettings();
          }
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(this.cardColor())

      this.sectionTitle('同步内容')
      Column() {
        this.fileSyncRow('本地书籍', '同步加入书架的本地书籍文件', true)
        this.fileSyncRow('自定义字体', '同步导入的自定义字体文件', false)
        SettingSwitchRow({
          title: '阅读数据',
          description: '在线书架、分组、排序、进度、书签；本地书仅同步进度',
          isOn: this.readingDataEnabled,
          onChange: (value: boolean) => {
            this.setScopeEnabled(true, value);
          }
        })
        SettingSwitchRow({
          title: '书源',
          description: '配置、分组、排序、启用和锁定状态；不含登录凭证',
          isOn: this.bookSourcesEnabled,
          onChange: (value: boolean) => {
            this.setBookSourcesEnabled(value);
          }
        })
        SettingSwitchRow({
          title: '阅读偏好',
          description: '字体规则、替换规则、主题；排版仅保存在本机',
          isOn: this.readingPreferencesEnabled,
          onChange: (value: boolean) => {
            this.setScopeEnabled(false, value);
          }
        })
        SettingSwitchRow({
          title: '应用偏好',
          description: '显示模式、书架布局、搜索显示',
          isOn: this.applicationPreferencesEnabled,
          showDivider: false,
          onChange: (value: boolean) => {
            this.setApplicationScopeEnabled(value);
          }
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(this.cardColor())
    }

    this.sectionTitle('管理')
    Column() {
      this.actionItem('同步设备', '查看和管理当前账号下的设备', true, () => {
        if (!this.accountLoggedIn) {
          HdsFeedback.showToast('请先登录华为账号');
          return;
        }
        router.pushUrl({ url: 'pages/SyncDevices' });
      })
      this.actionItem('同步问题', this.issueSummary(), true, () => {
        if (!this.accountLoggedIn) {
          HdsFeedback.showToast('请先登录华为账号');
          return;
        }
        router.pushUrl({ url: 'pages/SyncIssues' });
      })
      this.actionItem('重新从云端同步', '保留本机待上传修改，重新获取云端数据', false, () => {
        this.confirmReloadFromCloud();
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    Text('数据导入和导出仍位于“其他设置”，用于手动备份，不会代替云同步。')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .lineHeight(18)
      .width('calc(100% - 32vp)')
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: 32 })
  }

  @Builder
  statusCard() {
    Column({ space: AppSpacing.LG }) {
      Row() {
        Column({ space: AppSpacing.XS }) {
          Text('云同步')
            .fontSize(AppFontSize.SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(this.statusSummary())
            .fontSize(AppFontSize.BODY)
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
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.cloudSyncEnabled && this.accountLoggedIn ? this.accentColor() : this.subTextColor())
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
            .borderRadius(ThemeRuntime.mediumRadius())
            .backgroundColor(this.softColor())
        }
      }
      .width('100%')

      if (!this.accountLoggedIn) {
        Text('登录华为账号后，可跨设备同步书架、阅读进度和阅读设置；终身超级会员还可同步本地书籍和自定义字体。')
          .fontSize(AppFontSize.BODY)
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
          .fontSize(AppFontSize.CAPTION)
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
    .padding(AppSpacing.XL)
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  settingsLoadingCard() {
    Row({ space: AppSpacing.MD }) {
      LoadingProgress()
        .width(22)
        .height(22)
        .color(this.accentColor())
      Text('正在读取本机同步设置')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
    }
    .width('calc(100% - 24vp)')
    .height(72)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  fileSyncRow(title: string, description: string, books: boolean) {
    SettingRow({ title: title, minimumMembership: 'SUPER_LIFETIME',
      description: description,
      onTap: () => {
        if (!this.isSuperMember()) this.promptSuperMembership();
      } }) {
      AdaptiveSwitch({
        isOn: this.isSuperMember() && (books ? this.localBooksEnabled : this.customFontsEnabled),
        switchEnabled: this.isSuperMember() && !this.saving,
        accessibilityLabel: title,
        onChange: (value: boolean) => { this.setFileScopeEnabled(books, value); }
      })
        .opacity(this.isSuperMember() ? 1 : 0.45)
    }
  }

  isSuperMember(): boolean {
    return this.accountLoggedIn && this.membershipSku === 'SUPER_LIFETIME';
  }

  async promptSuperMembership(): Promise<void> {
    const result = await promptAction.showDialog({
      title: '终身超级会员专享',
      message: '本地书籍和自定义字体同步仅限终身超级会员，请开通或升级为终身超级会员。',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '开通或升级', color: this.accentColor() }
      ]
    });
    if (result.index === 1) router.pushUrl({ url: 'pages/AccountCenter' });
  }

  async setFileScopeEnabled(books: boolean, value: boolean): Promise<void> {
    if (AccountSessionStore.activeMembershipSku() !== 'SUPER_LIFETIME') {
      await this.promptSuperMembership();
      return;
    }
    if (this.saving) return;
    const previous = books ? this.localBooksEnabled : this.customFontsEnabled;
    if (books) this.localBooksEnabled = value;
    else this.customFontsEnabled = value;
    if (!await this.saveSettings()) {
      if (books) this.localBooksEnabled = previous;
      else this.customFontsEnabled = previous;
      return;
    }
    CloudAutoSync.schedule(getContext(this), 0);
  }

  @Builder
  actionItem(title: string, desc: string, showDivider: boolean, onClick: () => void) {
    SettingNavRow({ title: title, description: desc, showDivider: showDivider, onTap: onClick })
  }

  async setCloudSyncEnabled(value: boolean): Promise<void> {
    if (value && !this.accountLoggedIn) {
      HdsFeedback.showToast('请先登录华为账号');
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
        HdsFeedback.showToast(e instanceof Error ? e.message : '暂时无法检查云端数据');
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
      HdsFeedback.showToast('请至少保留一项同步内容');
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
      HdsFeedback.showToast('请至少保留一项同步内容');
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
      HdsFeedback.showToast('请至少保留一项同步内容');
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

  async saveSettings(): Promise<boolean> {
    this.saving = true;
    try {
      const settings = this.currentSettings();
      const userId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      await CloudSyncSettingsStore.saveUserPreferences(getContext(this), userId, settings);
      this.loadedUserId = userId;
      return true;
    } catch (e) {
      console.warn('保存云同步设置失败:', e);
      HdsFeedback.showToast('保存同步设置失败');
      return false;
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
      HdsFeedback.showToast('请先开启云同步');
      return;
    }
    this.saving = true;
    try {
      const result = await CloudSyncCoordinator.syncNow(getContext(this), conflictPolicy);
      const details: string[] = [];
      if (result.uploaded > 0) details.push(`上传 ${result.uploaded} 项`);
      if (result.downloaded > 0) details.push(`下载 ${result.downloaded} 项`);
      if (result.conflicts > 0) details.push(`处理 ${result.conflicts} 个冲突`);
      HdsFeedback.showToast(details.length > 0 ? `同步完成：${details.join('，')}` : '所有数据已同步');
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      HdsFeedback.showToast(`同步失败：${message}`);
    } finally {
      this.saving = false;
    }
  }

  async confirmReloadFromCloud(): Promise<void> {
    if (!this.accountLoggedIn || !this.cloudSyncEnabled) {
      HdsFeedback.showToast(this.accountLoggedIn ? '请先开启云同步' : '请先登录华为账号');
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
    settings.localBooksEnabled = this.localBooksEnabled;
    settings.customFontsEnabled = this.customFontsEnabled;
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
    this.localBooksEnabled = settings.localBooksEnabled;
    this.customFontsEnabled = settings.customFontsEnabled;
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

  issueSummary(): string {
    if (this.issueCount > 0) {
      return `${this.issueCount} 条记录 · ${this.latestIssue}`;
    }
    return this.syncErrorMessage || '暂无同步问题';
  }

  lastSyncDescription(): string {
    if (this.lastSuccessAt <= 0) {
      return this.cloudSyncEnabled ? '开启后将在同步服务可用时进行首次同步' : '开启云同步后才会上传数据';
    }
    return `上次同步：${new Date(this.lastSuccessAt).toLocaleString()}`;
  }

  statusColor(): string {
    if (this.syncStatus === CloudSyncSettingsStore.STATUS_ERROR) {
      return ThemeRuntime.dangerColor(this.appDarkMode);
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
    return ThemeRuntime.hairlineColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

}
