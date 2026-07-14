import deviceInfo from '@ohos.deviceInfo';
import { LengthMetrics } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial } from '@kit.UIDesignKit';

@Component
export struct ImmersiveBackButton {
  @Prop icon: Resource = $r('sys.symbol.arrow_left');
  @Prop iconColor: ResourceColor = '#18191C';
  @Prop labelText: string = '';
  @Prop labelFontSize: number = 21;
  @Prop darkMode: boolean = false;
  @Prop buttonSize: number = 38;
  @Prop containerWidth: number = 52;
  @Prop containerHeight: number = 56;
  @Prop startInset: number = 16;
  @Prop materialScale: number = 1;
  @Prop accessibilityLabel: string = '返回';
  onBack: () => void = () => {};

  build() {
    Stack() {
      if (deviceInfo.sdkApiVersion >= 23) {
        HdsNavigation() {
          Column() {
          }
        }
        .titleBar({
          padding: {
            start: LengthMetrics.vp(this.startInset),
            end: LengthMetrics.vp(0)
          },
          content: {
            backIcon: {
              icon: this.icon,
              label: this.accessibilityLabel,
                action: () => this.onBack()
            }
          },
          style: {
            systemMaterialEffect: {
              materialType: hdsMaterial.MaterialType.ADAPTIVE,
              materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
            },
            originalStyle: {
              contentStyle: {
                backIconStyle: {
                  iconColor: this.labelText ? '#00000000' : this.iconColor
                }
              }
            }
          }
        })
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(false)
        .hideToolBar(true)
        .width(this.materialContainerWidth())
        .height(this.materialContainerHeight())
        .scale({ x: this.normalizedMaterialScale(), y: this.normalizedMaterialScale() })

        if (this.labelText) {
          Stack({ alignContent: Alignment.Center }) {
            Text(this.labelText)
              .fontSize(this.labelFontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.iconColor)
          }
          .width(this.effectiveContainerWidth())
          .height(this.containerHeight)
          .hitTestBehavior(HitTestMode.None)
        }
      } else {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          if (this.labelText) {
            Text(this.labelText)
              .fontSize(this.labelFontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.iconColor)
          } else {
            SymbolGlyph(this.icon)
              .fontSize(21)
              .fontWeight(FontWeight.Medium)
              .fontColor([this.iconColor])
          }
        }
        .width(this.buttonSize)
        .height(this.buttonSize)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.accessibilityLabel)
        .onClick(() => this.onBack())
      }
    }
    .width(this.effectiveContainerWidth())
    .height(this.containerHeight)
    .alignContent(Alignment.Center)
  }

  effectiveContainerWidth(): number {
    // HdsNavigation 的原生按钮包含系统点击热区与材质外沿，不能压缩到旧版 52vp 容器中。
    return Math.max(this.containerWidth, 64 * this.normalizedMaterialScale());
  }

  normalizedMaterialScale(): number {
    return Math.max(0.6, Math.min(this.materialScale, 1));
  }

  materialContainerWidth(): number {
    return this.effectiveContainerWidth() / this.normalizedMaterialScale();
  }

  materialContainerHeight(): number {
    // 原生 MINI 标题栏至少需要 56vp 高度；外层保持紧凑尺寸并将其居中，避免圆形材质底部被裁切。
    return Math.max(56, this.containerHeight / this.normalizedMaterialScale());
  }
}
