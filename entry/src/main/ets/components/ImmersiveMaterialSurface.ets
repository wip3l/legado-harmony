import { HdsTabs } from '@kit.UIDesignKit';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

/** 圆角裁剪：带 HDS 材质时走离屏圆角，否则普通圆角。 */
class ImmersiveSurfaceClip implements AttributeModifier<CommonAttribute> {
  private radius: number;

  constructor(radius: number) {
    this.radius = radius;
  }

  applyNormalAttribute(node: CommonAttribute): void {
    if (ImmersiveMaterialRuntime.supportsHdsTabs()) {
      node.borderRadius(this.radius, RenderStrategy.OFFSCREEN);
    } else {
      node.borderRadius(this.radius);
    }
    node.clip(true);
  }
}

/**
 * 沉浸光感胶囊底板：借一个只有悬浮栏的 HdsTabs 承载系统 IMMERSIVE 材质（和首页底栏同一条渲染路径，
 * 与 ImmersiveBackButton 相同的做法），内容叠在上面，手指按下时再叠一层跟随触点的光晕。
 * API 23 以下没有 HDS 悬浮栏，退回实色底加浅投影。
 *
 * 悬浮栏只接受明确的宽度，surfaceWidth 必须是具体数值。内容用尾随闭包传入：
 *   ImmersiveMaterialSurface({ surfaceWidth: 40, surfaceHeight: 40, ... }) { SymbolGlyph(...) }
 */
@Component
export struct ImmersiveMaterialSurface {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop surfaceWidth: number = 40;
  @Prop surfaceHeight: number = 40;
  @Prop darkMode: boolean = false;
  /** 没有 HDS 材质时的底色。 */
  @Prop fallbackColor: ResourceColor = '#FFFFFF';
  /** 触摸光晕的颜色，一般传带透明度的强调色。 */
  @Prop glowColor: ResourceColor = '#33FFFFFF';
  @State touching: boolean = false;
  @State touchX: number = 0;
  @State touchY: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  @Builder
  materialTabContent() {
    Stack()
      .width('100%')
      .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (ImmersiveMaterialRuntime.supportsHdsTabs()) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() {
            Column()
          }
          .height(this.surfaceHeight)
          .tabBar(this.materialTabContent())
        }
        .barMode(BarMode.Fixed)
        .barHeight(this.surfaceHeight)
        .barOverlap(true)
        .barFloatingStyle({
          barWidth: {
            smallWidth: this.surfaceWidth,
            mediumWidth: this.surfaceWidth,
            largeWidth: this.surfaceWidth
          },
          systemMaterialEffect: {
            materialType: ImmersiveMaterialRuntime.materialType(),
            materialLevel: ImmersiveMaterialRuntime.materialLevel(this.immersiveLightLevel)
          },
          barSideMargin: 0,
          barBottomMargin: 0,
          gradientMask: {
            maskColor: Color.Transparent,
            maskHeight: this.surfaceHeight
          },
          adaptToHandedness: false,
          thermoCtrl: true,
          barOpacity: 1
        })
        .scrollable(false)
        .onContentWillChange(() => false)
        .width(this.surfaceWidth)
        .height(this.surfaceHeight)
        .hitTestBehavior(HitTestMode.None)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.fallbackColor)
          .hitTestBehavior(HitTestMode.None)
      }

      Stack({ alignContent: Alignment.Center }) {
        this.content()
      }
      .width(this.surfaceWidth - 2)
      .height(this.surfaceHeight - 2)
      .borderRadius(Math.max(0, this.surfaceHeight / 2 - 1))
      .backgroundColor(ImmersiveMaterialRuntime.surfaceColor(this.immersiveLightLevel,
        this.darkMode, this.fallbackColor, true))

      Row()
        .width(this.surfaceHeight * 2)
        .height(this.surfaceHeight * 2)
        .position({ x: this.touchX - this.surfaceHeight, y: this.touchY - this.surfaceHeight })
        .radialGradient({
          center: [this.surfaceHeight, this.surfaceHeight],
          radius: this.surfaceHeight,
          colors: [[this.glowColor, 0], [Color.Transparent, 1]]
        })
        .opacity(this.touching ? ImmersiveMaterialRuntime.touchGlowOpacity(this.immersiveLightLevel) : 0)
        .animation({ duration: 160, curve: Curve.Friction })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
    .attributeModifier(new ImmersiveSurfaceClip(this.surfaceHeight / 2))
    .border(ImmersiveMaterialRuntime.surfaceBorder(this.immersiveLightLevel, this.darkMode))
    .shadow(ImmersiveMaterialRuntime.supportsHdsTabs() ? { radius: 0, color: Color.Transparent } : {
      radius: this.darkMode ? 0 : 12,
      color: this.darkMode ? Color.Transparent : '#14000000',
      offsetX: 0,
      offsetY: this.darkMode ? 0 : 2
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.touching = false;
      } else if (event.touches.length > 0) {
        this.touchX = Math.max(0, Math.min(this.surfaceWidth, event.touches[0].x));
        this.touchY = Math.max(0, Math.min(this.surfaceHeight, event.touches[0].y));
        this.touching = true;
      }
    })
  }
}
