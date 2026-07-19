import { router } from '@kit.ArkUI';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { GlassPresetIds, GlassSettings, GlassSettingsStore } from '../utils/GlassSettingsStore';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct GlassSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State settings: GlassSettings = new GlassSettings();
  @State selectedPresetId: string = GlassPresetIds.STANDARD;
  @State previewIndex: number = 0;
  private previewSwiperController: SwiperController = new SwiperController();
  private saveTimer: number = -1;
  private interactionRevision: number = 0;

  aboutToAppear(): void {
    this.loadSettings();
    this.syncBars();
  }

  aboutToDisappear(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
      GlassSettingsStore.save(getContext(this), this.settings);
    }
  }

  build() {
    Column() {
      this.titleBar()
      this.floatingPreview()
      Scroll() {
        Column({ space: 12 }) {
          this.glassEnabledSwitch()
          Column({ space: 12 }) {
            this.sectionTitle('效果预设')
            this.presets()
            this.sectionTitle('模糊强度')
            this.sliderCard('全局模糊强度', 'blur', 0, 40, 1)
            this.sectionTitle('颜色与边框')
            this.sliderCard('透明度', 'tintOpacity', 0, 100, 1)
            this.sliderCard('边框透明度', 'borderOpacity', 0, 100, 1)
            this.sliderCard('边框宽度', 'borderWidth', 0, 2, 0.5)
            this.sliderCard('组件圆角', 'cornerRadius', 0, 32, 1)
            this.sectionTitle('阴影')
            this.shadowSwitch()
            if (this.settings.shadowEnabled) {
              this.sliderCard('阴影模糊', 'shadowRadius', 0, 30, 1)
              this.sliderCard(this.appDarkMode ? '深色阴影' : '浅色阴影',
                this.appDarkMode ? 'darkShadowOpacity' : 'lightShadowOpacity', 0, 100, 1)
              this.sliderCard('水平偏移', 'shadowOffsetX', -12, 12, 1)
              this.sliderCard('垂直偏移', 'shadowOffsetY', -12, 12, 1)
            }
            this.performanceCard()
          }
          .width('100%')
          .enabled(this.settings.enabled)
          .opacity(this.settings.enabled ? 1 : 0.42)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 6, bottom: 32 })
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%').justifyContent(FlexAlign.Start)
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  async loadSettings(): Promise<void> {
    const loadRevision = this.interactionRevision;
    try {
      const loaded = await GlassSettingsStore.load(getContext(this));
      if (loadRevision !== this.interactionRevision) {
        return;
      }
      this.selectedPresetId = loaded.preset;
      this.settings = loaded;
      GlassSettingsStore.applyToStorage(loaded);
    } catch (e) {
      console.warn('加载磨砂玻璃设置失败:', e);
    }
  }

  changed(): void {
    this.interactionRevision++;
    this.selectedPresetId = GlassPresetIds.CUSTOM;
    this.settings.preset = GlassPresetIds.CUSTOM;
    this.settings = GlassSettingsStore.cloneSettings(this.settings);
    this.scheduleSave();
  }

  selectPreset(id: string): void {
    if (!this.settings.enabled || this.selectedPresetId === id) return;
    this.interactionRevision++;
    if (id === GlassPresetIds.CUSTOM) {
      this.settings.preset = GlassPresetIds.CUSTOM;
      this.settings = GlassSettingsStore.cloneSettings(this.settings);
    } else {
      const next = GlassSettingsStore.preset(id);
      next.enabled = true;
      this.settings = GlassSettingsStore.cloneSettings(next);
    }
    this.selectedPresetId = id;
    this.scheduleSave();
  }

  sliderValue(key: string): number {
    switch (key) {
      case 'blur': return this.settings.blur;
      case 'tintOpacity': return this.settings.tintOpacity;
      case 'borderOpacity': return this.settings.borderOpacity;
      case 'borderWidth': return this.settings.borderWidth;
      case 'cornerRadius': return this.settings.cornerRadius;
      case 'shadowRadius': return this.settings.shadowRadius;
      case 'darkShadowOpacity': return this.settings.darkShadowOpacity;
      case 'lightShadowOpacity': return this.settings.lightShadowOpacity;
      case 'shadowOffsetX': return this.settings.shadowOffsetX;
      case 'shadowOffsetY': return this.settings.shadowOffsetY;
      default: return 0;
    }
  }

  updateSliderValue(key: string, value: number): void {
    switch (key) {
      case 'blur': this.settings.blur = value; break;
      case 'tintOpacity': this.settings.tintOpacity = value; break;
      case 'borderOpacity': this.settings.borderOpacity = value; break;
      case 'borderWidth': this.settings.borderWidth = value; break;
      case 'cornerRadius': this.settings.cornerRadius = value; break;
      case 'shadowRadius': this.settings.shadowRadius = value; break;
      case 'darkShadowOpacity': this.settings.darkShadowOpacity = value; break;
      case 'lightShadowOpacity': this.settings.lightShadowOpacity = value; break;
      case 'shadowOffsetX': this.settings.shadowOffsetX = value; break;
      case 'shadowOffsetY': this.settings.shadowOffsetY = value; break;
      default: return;
    }
    this.changed();
  }

  sliderDisplayValue(key: string): string {
    const value = Math.round(this.sliderValue(key) * 10) / 10;
    return `${value}`;
  }

  setGlassEnabled(enabled: boolean): void {
    this.interactionRevision++;
    this.settings.enabled = enabled;
    this.settings.preset = this.selectedPresetId;
    this.settings = GlassSettingsStore.cloneSettings(this.settings);
    this.scheduleSave();
  }

  selectPreview(index: number): void {
    const target = Math.max(0, Math.min(index, 4));
    if (target === this.previewIndex) return;
    this.previewIndex = target;
    this.previewSwiperController.changeIndex(target, true);
  }

  scheduleSave(): void {
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer);
    const snapshot = GlassSettingsStore.cloneSettings(this.settings);
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      GlassSettingsStore.save(getContext(this), snapshot);
    }, 300);
  }

  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }
  syncBars(): void { syncSystemBars(getContext(this), this.appDarkMode, this.pageColor()); }

  previewEffectEnabled(): boolean {
    return this.settings.enabled && !this.settings.lowPerformance;
  }

  previewBlur(): number {
    return this.previewEffectEnabled() ? this.settings.blur : 0;
  }

  previewGlassColor(dropdown: boolean = false): string {
    const color = this.cardColor();
    if (!this.previewEffectEnabled()) return color;
    const appliedOpacity = dropdown ? Math.round(this.settings.tintOpacity * 0.47) : this.settings.tintOpacity;
    return `#${this.previewOpacityHex(appliedOpacity)}${color.substring(1)}`;
  }

  previewBorderColor(): string {
    return `#${this.previewOpacityHex(this.settings.borderOpacity)}FFFFFF`;
  }

  previewShadowColor(): string {
    if (!this.previewEffectEnabled() || !this.settings.shadowEnabled) return '#00000000';
    const opacity = this.appDarkMode ? this.settings.darkShadowOpacity : this.settings.lightShadowOpacity;
    return `#${this.previewOpacityHex(opacity)}000000`;
  }

  previewShadowRadius(): number {
    return this.previewEffectEnabled() && this.settings.shadowEnabled ? this.settings.shadowRadius : 0;
  }

  previewOpacityHex(opacity: number): string {
    const value = Math.max(0, Math.min(255, Math.round(opacity * 2.55)));
    return value.toString(16).padStart(2, '0').toUpperCase();
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('磨砂玻璃')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ right: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  floatingPreview() {
    Column() {
      this.preview()
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 6 })
    .zIndex(2)
  }

  @Builder
  preview() {
    Stack() {
      Swiper(this.previewSwiperController) {
        this.panelPreview()
        this.popoverPreview()
        this.buttonPreview()
        this.overlayPreview()
        this.menuPreview()
      }
      .width('100%')
      .height('100%')
      .index(this.previewIndex)
      .indicator(false)
      .loop(false)
      .onChange((index: number) => {
        this.previewIndex = index;
      })

      Row() {
        Text(this.previewTitle())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(10)
          .backgroundColor(this.previewGlassColor())
        Blank().layoutWeight(1)
        Row({ space: 5 }) {
          ForEach([0, 1, 2, 3, 4], (index: number) => {
            Circle()
              .width(this.previewIndex === index ? 12 : 5)
              .height(5)
              .fill(this.previewIndex === index ? this.accentColor() : this.subTextColor())
              .onClick(() => this.selectPreview(index))
          }, (index: number) => `${index}`)
        }
      }
      .width('100%')
      .padding({ left: 10, right: 10, bottom: 7 })
      .alignItems(VerticalAlign.Center)
      .position({ x: 0, y: '100%' })
      .translate({ y: -27 })
    }
    .width('100%')
    .height(126)
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
  }

  previewTitle(): string {
    return ['面板', '弹出层', '磨砂按钮', '遮罩层', '菜单'][this.previewIndex];
  }

  @Builder
  previewBackdrop() {
    Row({ space: 18 }) {
      Circle().width(72).height(72).fill(this.accentColor())
      Circle().width(62).height(62).fill(ThemeRuntime.dangerColor(this.appDarkMode))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  panelPreview() {
    Stack({ alignContent: Alignment.Center }) {
      this.previewBackdrop()
      Column({ space: 4 }) {
        Text('内容面板').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
        Text('承载主要内容').fontSize(11).fontColor(this.subTextColor())
      }
      .width('78%')
      .padding(14)
      .borderRadius(this.settings.cornerRadius)
      .backgroundColor(this.previewGlassColor())
      .backdropBlur(this.previewBlur())
      .border({ width: this.settings.borderWidth, color: this.previewBorderColor() })
      .shadow({ color: this.previewShadowColor(), radius: this.previewShadowRadius(),
        offsetX: this.settings.shadowOffsetX, offsetY: this.settings.shadowOffsetY })
    }.width('100%').height('100%')
  }

  @Builder
  popoverPreview() {
    Stack({ alignContent: Alignment.Center }) {
      this.previewBackdrop()
      Column({ space: 5 }) {
        Text('弹出提示').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
        Text('这是浮在内容上方的弹出层').fontSize(10).fontColor(this.subTextColor())
      }
      .width('64%').padding(12).borderRadius(this.settings.cornerRadius)
      .backgroundColor(this.previewGlassColor(true))
      .backdropBlur(this.previewBlur())
      .border({ width: this.settings.borderWidth, color: this.previewBorderColor() })
      .shadow({ color: this.previewShadowColor(), radius: this.previewShadowRadius(),
        offsetX: this.settings.shadowOffsetX, offsetY: this.settings.shadowOffsetY })
    }.width('100%').height('100%')
  }

  @Builder
  buttonPreview() {
    Stack({ alignContent: Alignment.Center }) {
      this.previewBackdrop()
      Row({ space: 12 }) {
        Button('Aa').width(48).height(48).fontSize(16)
          .fontColor(this.primaryTextColor())
          .backgroundColor(this.previewGlassColor())
          .backdropBlur(this.previewBlur())
          .borderRadius(this.settings.cornerRadius)
          .border({ width: this.settings.borderWidth, color: this.previewBorderColor() })
          .shadow({ color: this.previewShadowColor(), radius: this.previewShadowRadius(),
            offsetX: this.settings.shadowOffsetX, offsetY: this.settings.shadowOffsetY })
        Button('操作').height(42).fontSize(13).fontColor(this.primaryTextColor())
          .backgroundColor(this.previewGlassColor())
          .backdropBlur(this.previewBlur())
          .borderRadius(this.settings.cornerRadius)
          .border({ width: this.settings.borderWidth, color: this.previewBorderColor() })
          .shadow({ color: this.previewShadowColor(), radius: this.previewShadowRadius(),
            offsetX: this.settings.shadowOffsetX, offsetY: this.settings.shadowOffsetY })
      }
    }.width('100%').height('100%')
  }

  @Builder
  overlayPreview() {
    Stack({ alignContent: Alignment.Center }) {
      this.previewBackdrop()
      Column() {
        Text('背景遮罩').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      }
      .width('88%').height('76%').justifyContent(FlexAlign.Center)
      .borderRadius(this.settings.cornerRadius)
      .backgroundColor(this.previewGlassColor())
      .backdropBlur(this.previewBlur())
      .border({ width: this.settings.borderWidth, color: this.previewBorderColor() })
      .shadow({ color: this.previewShadowColor(), radius: this.previewShadowRadius(),
        offsetX: this.settings.shadowOffsetX, offsetY: this.settings.shadowOffsetY })
    }.width('100%').height('100%')
  }

  @Builder
  menuPreview() {
    Stack({ alignContent: Alignment.Center }) {
      this.previewBackdrop()
      Column() {
        this.previewMenuItem('复制')
        this.previewMenuItem('分享')
        this.previewMenuItem('删除')
      }
      .width(126).padding({ top: 4, bottom: 4 })
      .borderRadius(this.settings.cornerRadius)
      .backgroundColor(this.previewGlassColor())
      .backdropBlur(this.previewBlur())
      .border({ width: this.settings.borderWidth, color: this.previewBorderColor() })
      .shadow({ color: this.previewShadowColor(), radius: this.previewShadowRadius(),
        offsetX: this.settings.shadowOffsetX, offsetY: this.settings.shadowOffsetY })
    }.width('100%').height('100%')
  }

  @Builder
  previewMenuItem(title: string) {
    Text(title).width('100%').height(28).fontSize(11).fontColor(this.primaryTextColor())
      .textAlign(TextAlign.Center)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title).fontSize(13).fontColor(this.subTextColor()).width('100%').padding({ left: 2, top: 6 })
  }

  @Builder
  presets() {
    Row({ space: 8 }) {
      this.presetButton('轻盈', GlassPresetIds.LIGHT)
      this.presetButton('标准', GlassPresetIds.STANDARD)
      this.presetButton('强烈', GlassPresetIds.STRONG)
      this.presetButton('自定义', GlassPresetIds.CUSTOM)
    }
    .width('100%')
  }

  @Builder
  presetButton(title: string, id: string) {
    Stack({ alignContent: Alignment.Center }) {
      Text(title)
        .fontSize(13)
        .fontColor(this.selectedPresetId === id ? '#FFFFFF' : this.primaryTextColor())
    }
      .layoutWeight(1)
      .height(38)
      .borderRadius(19)
      .backgroundColor(this.selectedPresetId === id ? this.accentColor() : this.cardColor())
      .onClick(() => this.selectPreset(id))
  }

  @Builder
  glassEnabledSwitch() {
    Row() {
      Column({ space: 3 }) {
        Text('启用磨砂玻璃').fontSize(16).fontColor(this.primaryTextColor())
        Text(this.settings.enabled ? '已启用，可选择预设或调整参数' : '已关闭，下方参数暂不可调整')
          .fontSize(12).fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.settings.enabled })
        .selectedColor(this.accentColor())
        .onChange((value: boolean) => this.setGlassEnabled(value))
    }
    .width('100%')
    .padding(14)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  shadowSwitch() {
    Row() {
      Text('显示悬浮阴影').fontSize(16).fontColor(this.primaryTextColor()).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.settings.shadowEnabled })
        .selectedColor(this.accentColor())
        .onChange((value: boolean) => { this.settings.shadowEnabled = value; this.changed(); })
    }
    .width('100%').padding(14).borderRadius(ThemeRuntime.cardRadius()).backgroundColor(this.cardColor())
  }

  @Builder
  performanceCard() {
    Row() {
      Column({ space: 3 }) {
        Text('低性能模式').fontSize(16).fontColor(this.primaryTextColor())
        Text('禁用实时模糊和阴影，列表较多时更流畅').fontSize(12).fontColor(this.subTextColor())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.settings.lowPerformance })
        .selectedColor(this.accentColor())
        .onChange((value: boolean) => { this.settings.lowPerformance = value; this.changed(); })
    }
    .width('100%').padding(14).borderRadius(ThemeRuntime.cardRadius()).backgroundColor(this.cardColor())
  }

  @Builder
  sliderCard(title: string, key: string, min: number, max: number, step: number) {
    Column({ space: 4 }) {
      Row() {
        Text(title).fontSize(15).fontColor(this.primaryTextColor()).layoutWeight(1)
        Text(this.sliderDisplayValue(key)).fontSize(13).fontColor(this.accentColor())
      }.width('100%')
      Slider({ value: this.sliderValue(key), min: min, max: max, step: step, style: SliderStyle.OutSet })
        .selectedColor(this.accentColor())
        .trackColor(ThemeRuntime.inputColor(this.appDarkMode))
        .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
        .onChange((next: number) => this.updateSliderValue(key, next))
    }
    .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 8 })
    .borderRadius(ThemeRuntime.cardRadius()).backgroundColor(this.cardColor())
  }
}
