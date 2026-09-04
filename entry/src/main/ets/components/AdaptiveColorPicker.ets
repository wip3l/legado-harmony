import deviceInfo from '@ohos.deviceInfo';
import { HdsColorPicker, HdsColorPickerOptions, HdsColorPickerTabType } from '@kit.UIDesignKit';
import { ColorCodePicker } from './ColorCodePicker';

/**
 * Uses the API 26 HDS color picker when available and keeps the existing
 * picker as a compatibility fallback on older HarmonyOS versions.
 */
@Component
export struct AdaptiveColorPicker {
  @Prop value: string = '#007DFF';
  @Prop placeholder: string = '#007DFF';
  @Prop appDarkMode: boolean = false;
  @Prop accentColor: string = '#007DFF';
  @Prop allowEmpty: boolean = false;
  @Prop optionTitle: string = '';
  @Prop hideOptionTrigger: boolean = false;
  @Prop directSelection: boolean = false;
  @Prop colorMode: string = '';
  @State favoriteColors: string[] = [];
  onColorChange: (color: string) => void = (_color: string): void => {};
  onColorModeChange: (mode: string) => void = (_mode: string): void => {};

  private supportsHdsPicker(): boolean {
    // The legacy picker also provides the custom/accent/off mode selector.
    // Keep that richer mode UI intact when a caller uses colorMode.
    return deviceInfo.sdkApiVersion >= 26 && this.colorMode === '' && !this.directSelection;
  }

  private hdsOptions(): HdsColorPickerOptions {
    const options: HdsColorPickerOptions = {
      circleRadius: 14,
      tabs: [HdsColorPickerTabType.GRID, HdsColorPickerTabType.SPECTRUM, HdsColorPickerTabType.SLIDERS]
    };
    return options;
  }

  build() {
    if (this.supportsHdsPicker()) {
      Stack() {
        if (!this.hideOptionTrigger) {
          Row() {
            Text(this.optionTitle || '颜色')
              .fontSize(16)
              .layoutWeight(1)
            Row()
              .width(30)
              .height(30)
              .borderRadius(15)
              .backgroundColor(this.value)
              .border({ width: 2, color: this.appDarkMode ? '#55FFFFFF' : '#22000000' })
          }
          .width('100%')
          .height(60)
        }
        HdsColorPicker({
          initialColor: this.value,
          initialFavoriteColors: this.favoriteColors,
          options: this.hdsOptions(),
          onColorSelected: (color: string) => {
            this.onColorChange(color);
          },
          onFavoriteColorsUpdate: (colors: string[]) => {
            this.favoriteColors = colors;
          }
        })
          .width('100%')
          .height(60)
          .opacity(0.01)
      }
      .width('100%')
      .height(60)
    } else {
      ColorCodePicker({
        value: this.value,
        placeholder: this.placeholder,
        appDarkMode: this.appDarkMode,
        accentColor: this.accentColor,
        allowEmpty: this.allowEmpty,
        optionTitle: this.optionTitle,
        hideOptionTrigger: this.hideOptionTrigger,
        colorMode: this.colorMode,
        onColorChange: (color: string) => {
          this.onColorChange(color);
        },
        onColorModeChange: (mode: string) => {
          this.onColorModeChange(mode);
        }
      })
    }
  }

}
