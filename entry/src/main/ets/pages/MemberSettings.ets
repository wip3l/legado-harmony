import { MemberSettingsStore } from '../account/MemberSettingsStore';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingSwitchRow } from '../components/common/SettingRow';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppSpacing } from '../theme/AppSpacing';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct MemberSettingsPage {
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('memberIdentityVisible') identityVisible: boolean = true;
  @StorageProp('memberSettingsVisible') settingsVisible: boolean = true;
  @State saving: boolean = false;

  onPageShow(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }

  private async save(key: string, enabled: boolean): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      await MemberSettingsStore.save(getContext(this), key, enabled);
    } catch (_) {
      HdsFeedback.showToast('保存会员设置失败，请重试');
    } finally {
      this.saving = false;
    }
  }

  build() {
    Stack() {
      PageScaffold({ title: '会员设置', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Column() {
      SettingSwitchRow({
        title: '会员身份外显',
        description: '在“我的”页面昵称后显示当前会员等级图标',
        isOn: this.identityVisible,
        switchEnabled: !this.saving,
        onChange: (enabled: boolean) => { this.save(MemberSettingsStore.IDENTITY_VISIBLE, enabled); }
      })
      SettingSwitchRow({
        title: '会员设置外显',
        description: '始终在功能名称后显示所需最低会员等级图标；关闭后，仅在等级不足时显示',
        isOn: this.settingsVisible,
        switchEnabled: !this.saving,
        showDivider: false,
        onChange: (enabled: boolean) => { this.save(MemberSettingsStore.SETTINGS_VISIBLE, enabled); }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }
}
