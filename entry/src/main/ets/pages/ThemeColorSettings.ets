import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';

@Entry
@Component
struct ThemeColorSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') lightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') darkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') lightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') darkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State selectedMode: string = 'light';

  private palette: string[] = [
    '#007DFF', '#3F8CFF', '#4E9BFF', '#00A870',
    '#2E7D68', '#FF7A1A', '#E53935', '#D81B60',
    '#7A5AF8', '#8E24AA', '#00ACC1', '#607D8B'
  ];

  aboutToAppear(): void {
    this.reloadSettings();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadSettings();
    this.syncBars();
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('主题色设置')
          this.modeOptions()
          this.colorPanel('按钮色', this.currentButtonColor(), (color: string) => {
            this.setCurrentButtonColor(color);
          })
          this.colorPanel('强调色', this.currentAccentColor(), (color: string) => {
            this.setCurrentAccentColor(color);
          })
          this.previewPanel()
        }
        .width('100%')
        .padding({ bottom: 32 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  async reloadSettings(): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      AppThemeSettingsStore.applyToStorage(settings);
      this.lightAccentColor = settings.lightAccentColor;
      this.darkAccentColor = settings.darkAccentColor;
      this.lightButtonColor = settings.lightButtonColor;
      this.darkButtonColor = settings.darkButtonColor;
    } catch (e) {
      console.warn('读取主题色设置失败:', e);
    }
  }

  onSettingChanged(): void {
    const settings = new AppThemeSettings();
    settings.lightAccentColor = this.lightAccentColor;
    settings.darkAccentColor = this.darkAccentColor;
    settings.lightButtonColor = this.lightButtonColor;
    settings.darkButtonColor = this.darkButtonColor;
    AppThemeSettingsStore.applyToStorage(settings);
    AppThemeSettingsStore.save(getContext(this), settings).catch((e: Error) => {
      console.warn('保存主题色设置失败:', e);
    });
  }

  setCurrentAccentColor(color: string): void {
    const normalized = AppThemeSettingsStore.normalizeColor(color, this.currentAccentColor());
    if (this.selectedMode === 'dark') {
      this.darkAccentColor = normalized;
    } else {
      this.lightAccentColor = normalized;
    }
    this.onSettingChanged();
  }

  setCurrentButtonColor(color: string): void {
    const normalized = AppThemeSettingsStore.normalizeColor(color, this.currentButtonColor());
    if (this.selectedMode === 'dark') {
      this.darkButtonColor = normalized;
    } else {
      this.lightButtonColor = normalized;
    }
    this.onSettingChanged();
  }

  currentAccentColor(): string {
    return this.selectedMode === 'dark' ? this.darkAccentColor : this.lightAccentColor;
  }

  currentButtonColor(): string {
    return this.selectedMode === 'dark' ? this.darkButtonColor : this.lightButtonColor;
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F0F2F5';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#888';
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleBar() {
    Row() {
      Text('<')
        .fontSize(24)
        .fontColor(this.primaryTextColor())
        .width(40)
        .height(56)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Text('主题色设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .backgroundColor(this.cardColor())
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
  modeOptions() {
    Row({ space: 8 }) {
      this.modeButton('浅色模式', 'light')
      this.modeButton('深色模式', 'dark')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  modeButton(title: string, mode: string) {
    Text(title)
      .fontSize(14)
      .fontColor(this.selectedMode === mode ? '#FFFFFF' : this.primaryTextColor())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(38)
      .borderRadius(19)
      .backgroundColor(this.selectedMode === mode ? this.currentAccentColor() : this.inputColor())
      .onClick(() => {
        this.selectedMode = mode;
      })
  }

  @Builder
  colorPanel(title: string, value: string, onChange: (color: string) => void) {
    Column() {
      Row() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(value)
          .fontSize(13)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.palette, (color: string) => {
          Text('')
            .width(34)
            .height(34)
            .borderRadius(17)
            .backgroundColor(color)
            .border({ width: value === color ? 3 : 1, color: value === color ? this.primaryTextColor() : '#22000000' })
            .margin({ right: 10, bottom: 10 })
            .onClick(() => {
              onChange(color);
            })
        })
      }
      .width('100%')

      TextInput({ text: value, placeholder: '#007DFF' })
        .height(42)
        .fontSize(14)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(8)
        .margin({ top: 12 })
        .onChange((text: string) => {
          if (/^#?[0-9a-fA-F]{6}$/.test(text.trim())) {
            onChange(text);
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 16 })
    .backgroundColor(this.cardColor())
    .margin({ top: 1 })
  }

  @Builder
  previewPanel() {
    Column() {
      Text(`${this.selectedMode === 'dark' ? '深色' : '浅色'}模式预览`)
        .fontSize(13)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ bottom: 12 })

      Row({ space: 12 }) {
        Button('主要按钮')
          .height(40)
          .layoutWeight(1)
          .fontColor('#FFFFFF')
          .backgroundColor(this.currentButtonColor())
        Text('强调文字')
          .fontSize(15)
          .fontColor(this.currentAccentColor())
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(this.cardColor())
    .margin({ top: 12 })
  }
}
