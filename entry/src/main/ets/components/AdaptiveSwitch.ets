import { uiMaterial } from '@kit.ArkUI';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ThemeRuntime } from '../theme/ThemeRuntime';

/**
 * Theme-aware switch. API 26+ lets the system Toggle render its immersive
 * light-sense surface; older versions keep the standard Toggle appearance.
 * The checked color follows the app theme's button color unless selectedColor
 * is passed (reader overlays pass the reading theme's color).
 */
@Component
export struct AdaptiveSwitch {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop isOn: boolean = false;
  @Prop selectedColor?: ResourceColor;
  @Prop switchEnabled: boolean = true;
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  accessibilityLabel: string = '';
  onChange: (isOn: boolean) => void = (_isOn: boolean) => {};

  build() {
    if (ImmersiveMaterialRuntime.supportsHds()) {
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.checkedColor())
        .enabled(this.switchEnabled)
        .systemMaterial(this.material())
        .borderRadius(999)
        .border(ImmersiveMaterialRuntime.surfaceBorder(this.immersiveLightLevel, this.appDarkMode))
        .accessibilityText(this.accessibilityLabel)
        .onChange((isOn: boolean) => this.onChange(isOn));
    } else {
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.checkedColor())
        .enabled(this.switchEnabled)
        .accessibilityText(this.accessibilityLabel)
        .onChange((isOn: boolean) => this.onChange(isOn));
    }
  }

  private checkedColor(): ResourceColor {
    if (this.selectedColor !== undefined) return this.selectedColor;
    // Reading themeRevision re-resolves the color when the theme pack changes without a dark-mode flip.
    return this.themeRevision >= 0 ? ThemeRuntime.buttonColor(this.appDarkMode) : '';
  }

  private material(): uiMaterial.Material {
    return ImmersiveMaterialRuntime.componentMaterial({
      style: ImmersiveMaterialRuntime.materialStyle(this.immersiveLightLevel),
      materialColor: '#22FFFFFF',
      applyShadow: true,
      interactive: this.immersiveLightLevel !== 'weak',
      lightEffect: ImmersiveMaterialRuntime.lightEffect(false, this.immersiveLightLevel)
    }, this.immersiveLightLevel);
  }
}
