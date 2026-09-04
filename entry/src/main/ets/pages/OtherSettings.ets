import { router, promptAction } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { lanReaderServer } from '../core/lan/LanReaderServer';

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
  @StorageLink('lanReaderBackgroundStatus') lanReaderBackgroundStatus: string = '未启动';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State lanReaderPasswordDraft: string = '';

  aboutToAppear(): void {
    this.lanReaderPasswordDraft = this.lanReaderPassword;
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          this.sectionTitle('数据')
          Column() {
            this.menuItem('WebDAV', '浏览远程 TXT / EPUB，并管理加密备份', true, () => {
              router.pushUrl({ url: 'pages/WebDav' });
            })
            this.menuItem('数据导入', '从备份文件导入书源、书架、进度、本地图书和设置', true, () => {
              router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'import' } });
            })
            this.menuItem('数据导出', '将书源、书架、进度、本地图书和设置导出为备份', false, () => {
              router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'export' } });
            })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('浏览器看书')
          Column() {
            this.switchItem('浏览器看书', '开启后，同一局域网内的手机、平板或电脑可访问本机书架', this.lanReaderEnabled,
              (value: boolean) => {
                this.setLanReaderEnabled(value);
              })
            if (this.lanReaderEnabled) {
              this.lanReaderAddressRow()
              this.lanReaderPasswordRow()
            }
            if (false && this.lanReaderEnabled) {
              Column() {
                Text(this.lanReaderStatus === '运行中' ?
                  `访问地址：${this.lanReaderUrl()}` : `状态：${this.lanReaderStatus}`)
                  .fontSize(13)
                  .fontColor(this.subTextColor())
                  .width('100%')
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .maxLines(2)
                  .onClick(() => {
                    this.copyLanReaderAddress();
                  })
                Text('仅建议在可信局域网使用；关闭开关后令牌立即失效')
                  .fontSize(12)
                  .fontColor(this.subTextColor())
                  .margin({ top: 4 })
                  .width('100%')
                Text(this.lanReaderBackgroundStatus)
                  .fontSize(12)
                  .fontColor(this.subTextColor())
                  .margin({ top: 4 })
                  .width('100%')
              }
              .width('calc(100% - 32vp)')
              .margin({ left: 16, right: 16, bottom: 8 })
            }
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('外观')
          Column() {
            this.menuItem('磨砂玻璃', '预设 / 模糊 / 透明度 / 边框 / 阴影', true, () => {
              router.pushUrl({ url: 'pages/GlassSettings' });
            })
            this.immersiveLightLevelItem()
            this.menuItem('字体设置', '全局字体 / 自定义字体', true, () => {
              router.pushUrl({ url: 'pages/FontSettings' });
            })
            this.menuItem('图标设置', '桌面图标 / 候选图标', false, () => {
              router.pushUrl({ url: 'pages/AppIconSettings' });
            })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('兼容与诊断')
          Column() {
            this.menuItem('脚本引擎迁移', 'QuickJS 影子校验、灰度路由与自动回退状态', false, () => {
              router.pushUrl({ url: 'pages/QuickJsDiagnostics' });
            })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())
        }
        .width('100%')
        .padding({ top: 56 + this.statusBarHeight, bottom: 32 + this.navBarHeight })
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

  lanReaderUrl(): string {
    return this.lanReaderAddress;
  }

  @Builder
  lanReaderPasswordRow() {
    Column() {
      Text('访问密码（可选）')
        .fontSize(13)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.lanReaderPasswordDraft, placeholder: '留空则无需密码' })
          .type(InputType.Password)
          .layoutWeight(1)
          .onChange((value: string) => this.lanReaderPasswordDraft = value)
        Button(this.lanReaderPassword ? '修改' : '设置')
          .fontSize(13)
          .onClick(() => this.saveLanReaderPassword())
        if (this.lanReaderPassword) {
          Button('清除')
            .fontSize(13)
            .onClick(() => {
              this.lanReaderPasswordDraft = '';
              this.saveLanReaderPassword();
            })
        }
      }
      .width('100%')
      .margin({ top: 8 })
      Text(this.lanReaderPassword ? '已设置密码，访问地址无需携带 token' : '未设置密码，局域网内打开地址即可进入')
        .fontSize(12)
        .fontColor(this.subTextColor())
        .margin({ top: 5 })
        .width('100%')
    }
    .width('calc(100% - 32vp)')
    .margin({ left: 16, right: 16, bottom: 10 })
  }

  async saveLanReaderPassword(): Promise<void> {
    const password = this.lanReaderPasswordDraft.trim();
    if (password.length > 64) {
      promptAction.showToast({ message: '密码最多 64 个字符' });
      return;
    }
    lanReaderServer.setPassword(password);
    this.lanReaderPasswordDraft = password;
    promptAction.showToast({ message: password ? '访问密码已设置' : '已取消访问密码' });
  }

  @Builder
  lanReaderAddressRow() {
    Row() {
      Text(this.lanReaderUrl() || this.lanReaderStatus)
        .fontSize(13)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(2)
        .onClick(() => this.copyLanReaderAddress())
      Button() {
        Text('⧉')
          .fontSize(20)
      }
      .width(40)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.copyLanReaderAddress())
    }
    .width('calc(100% - 32vp)')
    .margin({ left: 16, right: 16, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  async copyLanReaderAddress(): Promise<void> {
    const address = this.lanReaderUrl();
    if (!address) return;
    try {
      const board = pasteboard.getSystemPasteboard();
      await board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, address));
      promptAction.showToast({ message: '访问地址已复制' });
    } catch (error) {
      console.error('复制浏览器看书地址失败', error);
      promptAction.showToast({ message: '复制失败，请长按地址复制' });
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
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('其他设置')
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
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }

  @Builder
  menuItem(title: string, desc: string, showDivider: boolean, onClick: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('calc(100% - 32vp)')
    .height(64)
    .padding({ left: 0, right: 0 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: showDivider ? 0.5 : 0 },
      color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
    .onClick(onClick)
  }

  @Builder
  immersiveLightLevelItem() {
    Row() {
      Column() {
        Text('沉浸光感')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text('设置鸿蒙沉浸材质的光感强度')
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Select(this.immersiveLightLevelOptions())
        .selected(this.immersiveLightLevelSelectedIndex())
        .value(this.immersiveLightLevelOptions()[this.immersiveLightLevelSelectedIndex()].value)
        .font({ size: 14 })
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
        .menuSystemMaterial(ImmersiveMaterialRuntime.selectMenuMaterial())
        .onSelect((index: number) => this.setImmersiveLightLevel(index))
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  switchItem(title: string, desc: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.buttonColor())
        .onChange((checked: boolean) => onChange(checked))
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
  }
}
