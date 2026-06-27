class HsvColor {
  hue: number = 0;
  saturation: number = 0;
  value: number = 0;
}

@Component
export struct ColorCodePicker {
  @Prop value: string = '#007DFF';
  @Prop placeholder: string = '#007DFF';
  @Prop appDarkMode: boolean = false;
  @Prop accentColor: string = '#007DFF';
  @Prop allowEmpty: boolean = false;
  @Prop optionTitle: string = '';
  @Prop hideOptionTrigger: boolean = false;
  @Prop colorMode: string = '';
  @State pickerVisible: boolean = false;
  @State draftColor: string = '#007DFF';
  @State hue: number = 210;
  @State saturation: number = 100;
  @State colorBrightness: number = 100;
  @State originalColor: string = '#007DFF';
  @State pickerAreaWidth: number = 260;
  @State pickerAreaHeight: number = 290;
  @State hueAreaHeight: number = 290;
  @State showPresetColors: boolean = false;
  onColorChange: (color: string) => void = (_color: string): void => {};
  onColorModeChange: (mode: string) => void = (_mode: string): void => {};

  private presetColors: string[] = [
    '#007DFF', '#4E9BFF', '#00A870', '#2E7D68', '#FF7A1A', '#E53935',
    '#D81B60', '#7A5AF8', '#8E24AA', '#00ACC1', '#607D8B', '#FFE58A'
  ];

  private normalizeColor(color: string, fallback: string): string {
    const trimmed = color.trim();
    const normalized = trimmed.startsWith('#') ? trimmed : `#${trimmed}`;
    if (/^#[0-9a-fA-F]{6}$/.test(normalized)) {
      return normalized.toUpperCase();
    }
    const fallbackTrimmed = fallback.trim();
    const normalizedFallback = fallbackTrimmed.startsWith('#') ? fallbackTrimmed : `#${fallbackTrimmed}`;
    return /^#[0-9a-fA-F]{6}$/.test(normalizedFallback) ? normalizedFallback.toUpperCase() : '#007DFF';
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(value, max));
  }

  private hexToHsv(color: string): HsvColor {
    const normalized = this.normalizeColor(color, '#007DFF');
    const red = parseInt(normalized.substring(1, 3), 16) / 255;
    const green = parseInt(normalized.substring(3, 5), 16) / 255;
    const blue = parseInt(normalized.substring(5, 7), 16) / 255;
    const max = Math.max(red, green, blue);
    const min = Math.min(red, green, blue);
    const delta = max - min;
    let hue = 0;
    if (delta !== 0) {
      if (max === red) {
        hue = 60 * (((green - blue) / delta) % 6);
      } else if (max === green) {
        hue = 60 * (((blue - red) / delta) + 2);
      } else {
        hue = 60 * (((red - green) / delta) + 4);
      }
    }
    if (hue < 0) {
      hue += 360;
    }
    const result = new HsvColor();
    result.hue = hue;
    result.saturation = max === 0 ? 0 : delta / max;
    result.value = max;
    return result;
  }

  private componentToHex(value: number): string {
    return Math.round(this.clamp(value, 0, 255)).toString(16).padStart(2, '0').toUpperCase();
  }

  private hsvToHex(hue: number, saturation: number, value: number): string {
    const normalizedHue = ((hue % 360) + 360) % 360;
    const normalizedSaturation = this.clamp(saturation, 0, 100) / 100;
    const normalizedValue = this.clamp(value, 0, 100) / 100;
    const chroma = normalizedValue * normalizedSaturation;
    const hueSection = normalizedHue / 60;
    const secondary = chroma * (1 - Math.abs((hueSection % 2) - 1));
    const match = normalizedValue - chroma;
    let red = 0;
    let green = 0;
    let blue = 0;
    if (hueSection < 1) {
      red = chroma;
      green = secondary;
    } else if (hueSection < 2) {
      red = secondary;
      green = chroma;
    } else if (hueSection < 3) {
      green = chroma;
      blue = secondary;
    } else if (hueSection < 4) {
      green = secondary;
      blue = chroma;
    } else if (hueSection < 5) {
      red = secondary;
      blue = chroma;
    } else {
      red = chroma;
      blue = secondary;
    }
    return `#${this.componentToHex((red + match) * 255)}${this.componentToHex((green + match) * 255)}${this.componentToHex((blue + match) * 255)}`;
  }

  private hueColor(): string {
    return this.hsvToHex(this.hue, 100, 100);
  }

  private updateDraftFromHsv(): void {
    this.draftColor = this.hsvToHex(this.hue, this.saturation, this.colorBrightness);
  }

  private updateHsvFromColor(color: string): void {
    const hsv = this.hexToHsv(color);
    this.hue = Math.round(hsv.hue);
    this.saturation = Math.round(hsv.saturation * 100);
    this.colorBrightness = Math.round(hsv.value * 100);
  }

  private openPicker(): void {
    this.draftColor = this.normalizeColor(this.value, this.placeholder);
    this.originalColor = this.draftColor;
    this.updateHsvFromColor(this.draftColor);
    this.showPresetColors = false;
    this.pickerVisible = true;
  }

  private parseAreaDimension(value: Length): number {
    const text = String(value).trim();
    const match = text.match(/\d+(\.\d+)?/);
    if (!match) {
      return 0;
    }
    const parsed = Number(match[0]);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private updatePickerAreaSize(area: Area): void {
    const width = this.parseAreaDimension(area.width);
    const height = this.parseAreaDimension(area.height);
    if (width > 0) {
      this.pickerAreaWidth = width;
    }
    if (height > 0) {
      this.pickerAreaHeight = height;
    }
  }

  private updateHueAreaSize(area: Area): void {
    const height = this.parseAreaDimension(area.height);
    if (height > 0) {
      this.hueAreaHeight = height;
    }
  }

  private updateSaturationAndBrightness(x: number, y: number): void {
    this.saturation = this.clamp(x / Math.max(this.pickerAreaWidth, 1) * 100, 0, 100);
    this.colorBrightness = this.clamp((1 - y / Math.max(this.pickerAreaHeight, 1)) * 100, 0, 100);
    this.updateDraftFromHsv();
  }

  private handlePickerAreaTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down && event.type !== TouchType.Move) {
      return;
    }
    const point = event.changedTouches.length > 0 ? event.changedTouches[0] :
      (event.touches.length > 0 ? event.touches[0] : null);
    if (point) {
      this.updateSaturationAndBrightness(point.x, point.y);
    }
  }

  private updateHue(y: number): void {
    const ratio = this.clamp(y / Math.max(this.hueAreaHeight, 1), 0, 1);
    this.hue = (360 - ratio * 360) % 360;
    this.updateDraftFromHsv();
  }

  private handleHueTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down && event.type !== TouchType.Move) {
      return;
    }
    const point = event.changedTouches.length > 0 ? event.changedTouches[0] :
      (event.touches.length > 0 ? event.touches[0] : null);
    if (point) {
      this.updateHue(point.y);
    }
  }

  private pickerIndicatorX(): number {
    return this.clamp(this.saturation / 100 * this.pickerAreaWidth - 10, -2, this.pickerAreaWidth - 18);
  }

  private pickerIndicatorY(): number {
    return this.clamp((1 - this.colorBrightness / 100) * this.pickerAreaHeight - 10, -2,
      this.pickerAreaHeight - 18);
  }

  private hueIndicatorY(): number {
    const ratio = this.hue === 0 ? 0 : (360 - this.hue) / 360;
    return this.clamp(ratio * this.hueAreaHeight - 3, -1, this.hueAreaHeight - 5);
  }

  private pageColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  private inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F0F2F5';
  }

  private primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  private subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#888888';
  }

  private colorModeIndex(): number {
    if (this.colorMode === 'accent') {
      return 1;
    }
    if (this.colorMode === 'custom') {
      return 2;
    }
    return 0;
  }

  private colorModeLabel(): string {
    if (this.colorMode === 'accent') {
      return '跟随强调色';
    }
    if (this.colorMode === 'custom') {
      return '自定义';
    }
    return '关闭';
  }

  build() {
    Column() {
      if (this.colorMode !== '') {
        Row({ space: 10 }) {
          Text('自定义高亮色')
            .fontSize(15)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Select([
            { value: '关闭' },
            { value: '跟随强调色' },
            { value: '自定义' }
          ])
            .selected(this.colorModeIndex())
            .value(this.colorModeLabel())
            .font({ size: 13 })
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.inputColor())
            .borderRadius(8)
            .constraintSize({ minWidth: 112, maxWidth: 140 })
            .onSelect((index: number) => {
              if (index === 2) {
                this.openPicker();
              } else {
                this.onColorModeChange(index === 1 ? 'accent' : 'off');
              }
            })
          if (this.colorMode === 'custom') {
            Row()
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(this.normalizeColor(this.value, this.placeholder))
              .border({ width: 2, color: this.appDarkMode ? '#55FFFFFF' : '#22000000' })
              .onClick(() => {
                this.openPicker();
              })
          }
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
      } else if (this.optionTitle !== '') {
        if (this.hideOptionTrigger) {
          Button('')
            .width('100%')
            .height(60)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .opacity(0.01)
            .onClick(() => {
              this.openPicker();
            })
        } else {
          Row() {
            Text(this.optionTitle)
              .fontSize(16)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Row()
              .width(30)
              .height(30)
              .borderRadius(15)
              .backgroundColor(this.normalizeColor(this.value, this.placeholder))
              .border({ width: 2, color: this.appDarkMode ? '#55FFFFFF' : '#22000000' })
          }
          .width('100%')
          .height(60)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.pageColor())
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openPicker();
          })
        }
      } else {
        TextInput({ text: this.value, placeholder: this.placeholder })
          .height(42)
          .fontSize(14)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(8)
          .onClick(() => {
            this.openPicker();
          })
          .onChange((text: string) => {
            if (this.allowEmpty && text.trim() === '') {
              this.onColorChange('');
              return;
            }
            if (/^#?[0-9a-fA-F]{6}$/.test(text.trim())) {
              this.onColorChange(this.normalizeColor(text, this.value));
            }
          })
      }
    }
      .width('100%')
      .bindSheet($$this.pickerVisible, this.colorPickerSheet(), {
        height: 650,
        dragBar: true,
        backgroundColor: this.pageColor(),
        onDisappear: () => {
          this.pickerVisible = false;
        }
      })
  }

  @Builder
  colorPickerSheet() {
    Column({ space: 18 }) {
      Row() {
        Text('选择颜色')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        if (this.allowEmpty) {
          Text('跟随强调色')
            .fontSize(14)
            .fontColor(this.accentColor)
            .margin({ left: 12 })
            .onClick(() => {
              this.onColorChange('');
              this.pickerVisible = false;
            })
        }
      }
      .width('100%')

      Row({ space: 14 }) {
        Stack({ alignContent: Alignment.TopStart }) {
          Row()
            .width('100%')
            .height('100%')
            .backgroundColor(this.hueColor())
          Row()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 90,
              colors: [['#FFFFFFFF', 0.0], ['#00FFFFFF', 1.0]]
            })
          Row()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 180,
              colors: [['#00000000', 0.0], ['#FF000000', 1.0]]
            })
          Row()
            .width(20)
            .height(20)
            .borderRadius(10)
            .border({ width: 3, color: '#FFFFFF' })
            .shadow({ radius: 3, color: '#99000000', offsetX: 0, offsetY: 1 })
            .position({ x: this.pickerIndicatorX(), y: this.pickerIndicatorY() })
            .hitTestBehavior(HitTestMode.None)
        }
        .height(290)
        .layoutWeight(1)
        .borderRadius(6)
        .clip(true)
        .border({ width: 1, color: this.appDarkMode ? '#44FFFFFF' : '#22000000' })
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.updatePickerAreaSize(newValue);
        })
        .onTouch((event: TouchEvent) => {
          this.handlePickerAreaTouch(event);
        })

        Stack({ alignContent: Alignment.TopStart }) {
          Row()
            .width(38)
            .height('100%')
            .linearGradient({
              angle: 180,
              colors: [
                ['#FF0000', 0.0], ['#FF00FF', 0.17], ['#0000FF', 0.33], ['#00FFFF', 0.5],
                ['#00FF00', 0.67], ['#FFFF00', 0.83], ['#FF0000', 1.0]
              ]
            })
          Row()
            .width(44)
            .height(6)
            .borderRadius(3)
            .border({ width: 2, color: this.appDarkMode ? '#F2F3F5' : '#555555' })
            .backgroundColor(Color.Transparent)
            .position({ x: -3, y: this.hueIndicatorY() })
            .hitTestBehavior(HitTestMode.None)
        }
        .width(38)
        .height(290)
        .borderRadius(4)
        .clip(false)
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.updateHueAreaSize(newValue);
        })
        .onTouch((event: TouchEvent) => {
          this.handleHueTouch(event);
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        Row()
          .width(48)
          .height(36)
          .borderRadius(4)
          .backgroundColor(this.originalColor)
          .border({ width: 1, color: this.appDarkMode ? '#44FFFFFF' : '#22000000' })
        Text('→')
          .fontSize(20)
          .fontColor(this.subTextColor())
        Row()
          .width(48)
          .height(36)
          .borderRadius(4)
          .backgroundColor(this.draftColor)
          .border({ width: 1, color: this.appDarkMode ? '#44FFFFFF' : '#22000000' })
        TextInput({ text: this.draftColor, placeholder: '#007DFF' })
          .height(40)
          .fontSize(17)
          .fontColor(this.primaryTextColor())
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .layoutWeight(1)
          .onChange((text: string) => {
            if (/^#?[0-9a-fA-F]{6}$/.test(text.trim())) {
              this.draftColor = this.normalizeColor(text, this.draftColor);
              this.updateHsvFromColor(this.draftColor);
            }
          })
      }
      .width('100%')

      if (this.showPresetColors) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.presetColors, (color: string) => {
            Button('')
              .width(30)
              .height(30)
              .borderRadius(15)
              .padding(0)
              .backgroundColor(color)
              .border({ width: this.draftColor === color ? 3 : 1,
                color: this.draftColor === color ? this.primaryTextColor() : '#22000000' })
              .margin({ right: 8, bottom: 6 })
              .onClick(() => {
                this.draftColor = color;
                this.updateHsvFromColor(color);
              })
          })
        }
        .width('100%')
      }

      Row({ space: 12 }) {
        Button('预置颜色')
          .height(42)
          .fontColor(this.accentColor)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onClick(() => {
            this.showPresetColors = !this.showPresetColors;
          })
        Button('确认')
          .height(42)
          .fontColor(this.accentColor)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onClick(() => {
            if (this.colorMode !== '') {
              this.onColorModeChange('custom');
            }
            this.onColorChange(this.draftColor);
            this.pickerVisible = false;
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 20 })
    .backgroundColor(this.pageColor())
  }
}
