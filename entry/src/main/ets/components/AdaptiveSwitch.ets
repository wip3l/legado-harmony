import { uiMaterial } from '@kit.ArkUI';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

/**
 * Theme-aware switch. API 26+ lets the system Toggle render its immersive
 * light-sense surface; older versions keep the standard Toggle appearance.
 */
@Component
export struct AdaptiveSwitch {
  @Prop isOn: boolean = false;
  @Prop selectedColor: ResourceColor = '#4F8F86';
  @Prop switchEnabled: boolean = true;
  accessibilityLabel: string = '';
  onChange: (isOn: boolean) => void = (_isOn: boolean) => {};

  build() {
    if (ImmersiveMaterialRuntime.supportsHds()) {
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.selectedColor)
        .enabled(this.switchEnabled)
        .systemMaterial(this.material())
        .accessibilityText(this.accessibilityLabel)
        .onChange((isOn: boolean) => this.onChange(isOn));
    } else {
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.selectedColor)
        .enabled(this.switchEnabled)
        .accessibilityText(this.accessibilityLabel)
        .onChange((isOn: boolean) => this.onChange(isOn));
    }
  }

  private material(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: '#22FFFFFF',
      applyShadow: true,
      interactive: true,
      lightEffect: { color: '#55FFFFFF' }
    });
  }
}
