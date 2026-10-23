import { promptAction, router } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { lanReaderServer } from '../core/lan/LanReaderServer';
import { LanReaderPasswordStore } from '../core/lan/LanReaderPasswordStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ReaderCacheBudget, ReaderCacheCleanup } from '../core/book/ReaderCacheBudget';
import { ReaderCacheBudgetPolicy } from '../core/book/ReaderCacheBudgetPolicy';

@Entry
@Component
struct OtherSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('lanReaderEnabled') lanReaderEnabled: boolean = false;
  @StorageLink('lanReaderAddress') lanReaderAddress: string = '';
  @StorageLink('lanReaderStatus') lanReaderStatus: string = '已关闭';
  @StorageLink('lanReaderToken') lanReaderToken: string = '';
  @StorageLink('lanReaderPassword') lanReaderPassword: string = '';
  @StorageProp('lanReaderPasswordUnreadable') lanReaderPasswordUnreadable: boolean = false;
  @StorageLink('lanReaderBackgroundStatus') lanReaderBackgroundStatus: string = '未启动';
  @State lanReaderPasswordDraft: string = '';
  /** -1 表示还在统计。 */
  @State textCacheBytes: number = -1;
  @State comicCacheBytes: number = -1;
  @State cacheClearing: boolean = false;

  aboutToAppear(): void {
    this.lanReaderPasswordDraft = this.lanReaderPasswordUnreadable ? '' : this.lanReaderPassword;
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
    this.refreshCacheUsage();
  }

  build() {
    Stack() {
      PageScaffold({ title: '其他设置', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    this.sectionTitle('数据')
    Column() {
      SettingNavRow({
        title: '数据导入',
        description: '从备份文件导入书源、书架、进度、本地图书和设置',
        onTap: () => {
          router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'import' } });
        }
      })
      SettingNavRow({
        title: '数据导出',
        description: '将书源、书架、进度、本地图书和设置导出为备份',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'export' } });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('缓存')
    Column() {
      SettingRow({
        title: '小说正文缓存',
        description: this.cacheUsageText(this.textCacheBytes, ReaderCacheBudget.TEXT_LIMIT_BYTES,
          '超出后自动清理阅读时顺带缓存的章节，手动缓存的章节和本地书不清理'),
        onTap: () => this.confirmClearCache(true)
      }) {
        this.cacheClearLabel()
      }
      SettingRow({
        title: '漫画图片缓存',
        description: this.cacheUsageText(this.comicCacheBytes, ReaderCacheBudget.COMIC_LIMIT_BYTES,
          '超出后自动清理最久未看的图片'),
        showDivider: false,
        onTap: () => this.confirmClearCache(false)
      }) {
        this.cacheClearLabel()
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('浏览器看书')
    Column() {
      SettingSwitchRow({
        title: '浏览器看书',
        description: '同一局域网内的设备可用浏览器访问本机书架',
        isOn: this.lanReaderEnabled,
        onChange: (value: boolean) => {
          this.setLanReaderEnabled(value);
        }
      })
      if (this.lanReaderEnabled) {
        this.lanReaderAddressRow()
        this.lanReaderPasswordRow()
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('外观')
    Column() {
      SettingNavRow({
        title: '磨砂玻璃',
        description: '预设、模糊、透明度、边框、阴影',
        onTap: () => {
          router.pushUrl({ url: 'pages/GlassSettings' });
        }
      })
      SettingRow({ title: '沉浸光感', description: '沉浸材质的光感强度' }) {
        this.immersiveLightLevelSelect()
      }
      SettingNavRow({
        title: '字体设置',
        description: '全局字体、自定义字体',
        onTap: () => {
          router.pushUrl({ url: 'pages/FontSettings' });
        }
      })
      SettingNavRow({
        title: '图标设置',
        description: '更换桌面图标',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/AppIconSettings' });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('兼容与诊断')
    Column() {
      SettingNavRow({
        title: '脚本引擎迁移',
        description: 'QuickJS 影子校验、灰度路由、自动回退状态',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/QuickJsDiagnostics' });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  immersiveLightLevelOptions(): SelectOption[] {
    return [
      { value: '跟随系统' },
      { value: '高' },
      { value: '均衡' },
      { value: '弱' }
    ];
  }

  immersiveLightLevelValues(): string[] {
    return ['adaptive', 'high', 'balanced', 'weak'];
  }

  immersiveLightLevelSelectedIndex(): number {
    const index = this.immersiveLightLevelValues().indexOf(this.immersiveLightLevel);
    return index >= 0 ? index : 0;
  }

  setImmersiveLightLevel(index: number): void {
    const values = this.immersiveLightLevelValues();
    const next = index >= 0 && index < values.length ? values[index] : values[0];
    if (this.immersiveLightLevel === next) return;
    this.immersiveLightLevel = next;
    const revision = AppStorage.get<number>('themeRevision') ?? 0;
    AppStorage.setOrCreate('themeRevision', revision + 1);
  }

  @Builder
  cacheClearLabel() {
    Text('清理')
      .fontSize(AppFontSize.BODY)
      .fontColor(this.cacheClearing ? this.subTextColor() : this.accentColor())
      .margin({ left: AppSpacing.LG })
  }

  cacheUsageText(bytes: number, limit: number, note: string): string {
    const usage = bytes < 0 ? '正在统计…' :
      `${ReaderCacheBudgetPolicy.formatBytes(bytes)} / ${ReaderCacheBudgetPolicy.formatBytes(limit)}`;
    return `${usage}\n${note}`;
  }

  async refreshCacheUsage(): Promise<void> {
    try {
      this.textCacheBytes = await ReaderCacheBudget.textUsageBytes();
    } catch (e) {
      console.warn('统计正文缓存失败:', e);
      this.textCacheBytes = 0;
    }
    try {
      this.comicCacheBytes = await ReaderCacheBudget.comicUsageBytes();
    } catch (e) {
      console.warn('统计漫画缓存失败:', e);
      this.comicCacheBytes = 0;
    }
  }

  async confirmClearCache(text: boolean): Promise<void> {
    if (this.cacheClearing) return;
    const dark = this.appDarkMode;
    try {
      const result = await promptAction.showDialog({
        title: text ? '清理小说正文缓存？' : '清理漫画图片缓存？',
        message: text ? '会删除在线书籍已缓存的正文，包括手动缓存的离线章节，之后阅读需要重新联网获取。本地导入的书不受影响，正在阅读的书会保留。' :
          '会删除已下载的漫画图片，之后阅读需要重新下载。最近 10 分钟内看过的图片会保留。',
        buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(dark) },
          { text: '清理', color: ThemeRuntime.dangerColor(dark) }]
      });
      if (result.index !== 1) return;
    } catch (e) {
      console.warn('显示清理缓存确认失败:', e);
      return;
    }
    this.cacheClearing = true;
    try {
      const cleanup = text ? await ReaderCacheBudget.clearText() : await ReaderCacheBudget.clearComic();
      HdsFeedback.showToast(this.cleanupSummary(cleanup));
    } catch (e) {
      HdsFeedback.showToast(`清理失败：${(e as Error).message}`);
    } finally {
      this.cacheClearing = false;
    }
    await this.refreshCacheUsage();
  }

  cleanupSummary(cleanup: ReaderCacheCleanup): string {
    const parts: string[] = [`已释放 ${ReaderCacheBudgetPolicy.formatBytes(cleanup.releasedBytes)}`];
    if (cleanup.protectedCount > 0) parts.push(`使用中保留 ${cleanup.protectedCount} 项`);
    if (cleanup.failed > 0) parts.push(`${cleanup.failed} 项删除失败`);
    return parts.join('，');
  }

  lanReaderUrl(): string {

    return this.lanReaderAddress;
  }

  @Builder
  lanReaderPasswordRow() {
    Column() {
      Text('访问密码（可选）')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Row({ space: AppSpacing.MD }) {
        TextInput({ text: this.lanReaderPasswordDraft, placeholder: '留空则无需密码' })
          .type(InputType.Password)
          .layoutWeight(1)
          .onChange((value: string) => this.lanReaderPasswordDraft = value)
        Button(this.lanReaderPassword ? '修改' : '设置')
          .fontSize(AppFontSize.BODY)
          .onClick(() => this.saveLanReaderPassword())
        if (this.lanReaderPassword) {
          Button('清除')
            .fontSize(AppFontSize.BODY)
            .onClick(() => {
              this.lanReaderPasswordDraft = '';
              this.saveLanReaderPassword();
            })
        }
      }
      .width('100%')
      .margin({ top: AppSpacing.MD })
      Text(this.lanReaderPasswordUnreadable ? '已保存的密码无法读取，浏览器访问已锁定，请重新设置密码' :
        (this.lanReaderPassword ? '已设置密码，访问地址无需携带 token' : '未设置密码，局域网内打开地址即可进入'))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .margin({ top: AppSpacing.XS })
        .width('100%')
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
  }

  async saveLanReaderPassword(): Promise<void> {
    const password = this.lanReaderPasswordDraft.trim();
    if (password.length > 64) {
      HdsFeedback.showToast('密码最多 64 个字符');
      return;
    }
    try {
      await LanReaderPasswordStore.save(getContext(this), password);
    } catch (error) {
      HdsFeedback.showToast(`访问密码保存失败：${(error as Error).message}`);
      return;
    }
    lanReaderServer.setPassword(password);
    this.lanReaderPasswordDraft = password;
    HdsFeedback.showToast(password ? '访问密码已设置' : '已取消访问密码');
  }

  @Builder
  lanReaderAddressRow() {
    Row() {
      Text(this.lanReaderUrl() || this.lanReaderStatus)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(2)
        .onClick(() => this.copyLanReaderAddress())
      Button() {
        Text('⧉')
          .fontSize(AppFontSize.TITLE)
      }
      .width(40)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.copyLanReaderAddress())
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .alignItems(VerticalAlign.Center)
  }

  async copyLanReaderAddress(): Promise<void> {
    const address = this.lanReaderUrl();
    if (!address) return;
    try {
      const board = pasteboard.getSystemPasteboard();
      await board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, address));
      HdsFeedback.showToast('访问地址已复制');
    } catch (error) {
      console.error('复制浏览器看书地址失败', error);
      HdsFeedback.showToast('复制失败，请长按地址复制');
    }
  }

  async setLanReaderEnabled(enabled: boolean): Promise<void> {
    this.lanReaderEnabled = enabled;
    if (!enabled) {
      await lanReaderServer.stop();
      return;
    }
    try {
      await lanReaderServer.start(getContext(this));
    } catch (error) {
      this.lanReaderEnabled = false;
      this.lanReaderStatus = '启动失败';
      console.error('浏览器看书服务启动失败', error);
    }
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

  @Builder
  immersiveLightLevelSelect() {
    Select(this.immersiveLightLevelOptions())
      .selected(this.immersiveLightLevelSelectedIndex())
      .value(this.immersiveLightLevelOptions()[this.immersiveLightLevelSelectedIndex()].value)
      .font({ size: AppFontSize.BODY })
      .fontColor(this.subTextColor())
      .backgroundColor(Color.Transparent)
      .arrowPosition(ArrowPosition.END)
      .padding({ left: 0, right: 0 })
      .borderRadius(16)
      .border({ width: 0 })
      .divider(null)
      .optionBgColor(Color.Transparent)
      .optionFontColor(this.primaryTextColor())
      .selectedOptionFontColor(this.accentColor())
      .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
      .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
      .menuBackgroundBlurStyle(BlurStyle.NONE)
      .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
      .onSelect((index: number) => this.setImmersiveLightLevel(index))
  }
}
