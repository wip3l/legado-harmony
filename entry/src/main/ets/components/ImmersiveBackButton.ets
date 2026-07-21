import deviceInfo from '@ohos.deviceInfo';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';

@Component
export struct ImmersiveBackButton {
  @Prop icon: Resource = $r('sys.symbol.chevron_left');
  @Prop iconColor: ResourceColor = '#18191C';
  @Prop labelText: string = '';
  @Prop labelFontSize: number = 21;
  @Prop iconSize: number = 22;
  @Prop iconOffsetX: number = -1;
  @Prop darkMode: boolean = false;
  @Prop buttonSize: number = 38;
  @Prop containerWidth: number = 52;
  @Prop containerHeight: number = 56;
  @Prop startInset: number = 16;
  @Prop materialScale: number = 1;
  @Prop compactLayout: boolean = false;
  @Prop accessibilityLabel: string = '返回';
  onBack: () => void = () => {};

  build() {
    Stack() {
      if (deviceInfo.sdkApiVersion >= 23) {
        this.linkedSystemMaterialButton()
      } else {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          this.buttonContent(false)
        }
        .width(this.materialButtonSize())
        .height(this.materialButtonSize())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.accessibilityLabel)
        .onClick(() => this.onBack())
      }
    }
    .width(this.effectiveContainerWidth())
    .height(this.containerHeight)
    .alignContent(deviceInfo.sdkApiVersion >= 23 ? Alignment.Start : Alignment.Center)
  }

  @Builder
  linkedSystemMaterialButton() {
    Stack({ alignContent: Alignment.Center }) {
      // API 23~25 只将 HdsTabs 作为系统材质和按压光影提供层；业务点击由上层标准按钮承载。
      // ADAPTIVE 会跟随系统沉浸光感设置、设备能力和热控策略。
      // API 26 升级点：compileSdk 升至 26 后，仅替换这个材质提供层为
      // systemMaterial(new uiMaterial.ImmersiveMaterial(...))，圆形裁剪、图标和交互层无需改动。
      HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
        TabContent() {
          Column()
        }
        .height(this.materialButtonSize())
        .tabBar(this.nativeMaterialTabContent())
      }
      .barMode(BarMode.Fixed)
      .barHeight(this.materialButtonSize())
      .barOverlap(true)
      .barFloatingStyle({
        barWidth: {
          smallWidth: this.materialButtonSize(),
          mediumWidth: this.materialButtonSize(),
          largeWidth: this.materialButtonSize()
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        barSideMargin: 0,
        barBottomMargin: 0,
        gradientMask: {
          maskColor: '#00000000',
          maskHeight: this.materialButtonSize()
        },
        adaptToHandedness: false,
        thermoCtrl: true,
        barOpacity: 1
      })
      .scrollable(false)
      .onContentWillChange(() => false)
      .width(this.materialButtonSize())
      .height(this.materialButtonSize())

      // 透明标准按钮专门承载业务点击，不依赖单项 Tabs 的选中回调。
      // Transparent 命中模式让按压同时透传给 HDS，保留系统材质光影响应。
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        this.buttonContent(true)
      }
      .width(this.materialButtonSize())
      .height(this.materialButtonSize())
      .padding(0)
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Transparent)
      .accessibilityText(this.accessibilityLabel)
      .onClick(() => this.onBack())
    }
    .width(this.materialButtonSize())
    .height(this.materialButtonSize())
    // 在 HDS 完成材质合成后裁剪整个承载层，消除 Tabs 的矩形合成边界。
    .borderRadius(this.materialButtonSize() / 2, RenderStrategy.OFFSCREEN)
    .clip(true)
    .translate({ x: this.startInset * this.normalizedMaterialScale() })
  }

  @Builder
  nativeMaterialTabContent() {
    Stack()
      .width('100%')
      .height('100%')
  }

  @Builder
  buttonContent(useMaterialScale: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.labelText) {
        Text(this.labelText)
          .fontSize(this.labelFontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.iconColor)
      } else {
        SymbolGlyph(this.icon)
          .fontSize(this.iconSize)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.iconColor])
          .translate({ x: this.iconOffsetX })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  effectiveContainerWidth(): number {
    if (this.compactLayout) {
      return Math.max(this.containerWidth,
        deviceInfo.sdkApiVersion >= 23 ? this.materialButtonSize() : this.buttonSize);
    }
    return Math.max(this.containerWidth, 64 * this.normalizedMaterialScale());
  }

  normalizedMaterialScale(): number {
    return Math.max(0.6, Math.min(this.materialScale, 1));
  }

  materialButtonSize(): number {
    // materialScale 应同时收紧材质底座；图标保持清晰尺寸，避免“小图标套大圆盘”的失衡观感。
    return Math.max(36, this.buttonSize * this.normalizedMaterialScale());
  }
}
