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
  action: () => void = () => {};

  build() {
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
      .onClick(() => this.action())
    } else {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        this.iconContent()
      }
      .width(this.buttonSize)
      .height(this.buttonSize)
      .padding(0)
      .enabled(this.buttonEnabled)
      .backgroundColor(this.fillColor)
      .focusable(false)
      .accessibilityText(this.accessibilityLabel)
      .onClick(() => this.action())
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
      lightEffect: ImmersiveMaterialRuntime.lightEffect()
    });
  }
}
