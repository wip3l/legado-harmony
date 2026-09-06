import { uiMaterial } from '@kit.ArkUI';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

/** Circular action button with an API 26+ system material surface. */
@Component
export struct AdaptiveIconButton {
  @Prop icon: Resource = $r('sys.symbol.circle');
  @Prop accessibilityLabel: string = '';
  @Prop buttonEnabled: boolean = true;
  @Prop buttonSize: number = 34;
  @Prop iconSize: number = 16;
  @Prop fillColor: ResourceColor = Color.Transparent;
  @Prop iconColor: ResourceColor = '#1F1F1F';
  @Prop disabledIconColor: ResourceColor = '#999999';
  @Prop immersiveLightEffect: boolean = false;
  @Prop showSurface: boolean = false;
  @Prop surfaceBorderColor: ResourceColor = '#4DFFFFFF';
  @State private pressed: boolean = false;
  action: () => void = () => {};

  build() {
    // Keep a visible circular surface even when the device does not expose
    // API 26 component-level immersive materials. On supported devices the
    // child button adds Huawei's material/light-sense interaction on top.
    Stack({ alignContent: Alignment.Center }) {
      if (ImmersiveMaterialRuntime.supportsHds()) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          this.iconContent()
        }
        .width(this.buttonSize)
        .height(this.buttonSize)
        .padding(0)
        .enabled(this.buttonEnabled)
        .systemMaterial(this.material())
        .backgroundColor(Color.Transparent)
        .focusable(false)
        .accessibilityText(this.accessibilityLabel)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
        .onClick(() => this.action())
      } else {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          this.iconContent()
        }
        .width(this.buttonSize)
        .height(this.buttonSize)
        .padding(0)
        .enabled(this.buttonEnabled)
        .backgroundColor(Color.Transparent)
        .focusable(false)
        .accessibilityText(this.accessibilityLabel)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
        .onClick(() => this.action())
      }
      if (this.showSurface && this.pressed) {
        // Compatibility light-sense fallback for devices where the system
        // ImmersiveMaterial API is unavailable or visually suppressed.
        Row()
          .width(this.buttonSize * 0.72)
          .height(this.buttonSize * 0.72)
          .backgroundColor('#38FFFFFF')
          .borderRadius(this.buttonSize * 0.36)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .backgroundColor(this.showSurface ? this.fillColor : Color.Transparent)
    .border({ width: this.showSurface ? 1 : 0, color: this.surfaceBorderColor })
    .borderRadius(this.buttonSize / 2)
    .shadow({
      radius: this.showSurface ? 8 : 0,
      color: this.showSurface ? '#40000000' : Color.Transparent,
      offsetX: 0,
      offsetY: 2
    })
  }

  private handleTouch(event: TouchEvent): void {
    if (!this.showSurface) return;
    if (event.type === TouchType.Down) {
      this.pressed = true;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  @Builder
  iconContent() {
    SymbolGlyph(this.icon)
      .fontSize(this.iconSize)
      .fontColor([this.buttonEnabled ? this.iconColor : this.disabledIconColor])
  }

  private material(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: ImmersiveMaterialRuntime.materialStyle(),
      materialColor: '#2EFFFFFF',
      applyShadow: true,
      interactive: ImmersiveMaterialRuntime.configuredLightLevel() !== 'weak',
      lightEffect: ImmersiveMaterialRuntime.lightEffect(this.immersiveLightEffect)
    });
  }
}
