import { HdsTabs } from '@kit.UIDesignKit';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

export const IMMERSIVE_READ_BUTTON_WIDTH: number = 160;

/** 与返回按钮共用系统沉浸材质的阅读悬浮胶囊。 */
@Component
export struct ImmersiveReadButton {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop label: string = '开始阅读';
  @Prop icon: Resource = $r('sys.symbol.book');
  @Prop darkMode: boolean = false;
  @Prop accentColor: string = '#007DFF';
  @Prop busy: boolean = false;
  onRead: () => void = (): void => {};

  @Builder
  emptyMaterialContent() {
    Column()
      .width('100%')
      .height('100%')
  }

  build() {
    Stack() {
      if (ImmersiveMaterialRuntime.supportsHdsMaterial()) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() {
            Column()
          }
          .tabBar(this.emptyMaterialContent())
        }
        .barMode(BarMode.Fixed)
        .barHeight(56)
        .barOverlap(true)
        .barFloatingStyle({
          barWidth: {
            smallWidth: IMMERSIVE_READ_BUTTON_WIDTH,
            mediumWidth: IMMERSIVE_READ_BUTTON_WIDTH,
            largeWidth: IMMERSIVE_READ_BUTTON_WIDTH
          },
          systemMaterialEffect: {
            materialType: ImmersiveMaterialRuntime.materialType(),
            materialLevel: ImmersiveMaterialRuntime.materialLevel(this.immersiveLightLevel)
          },
          barSideMargin: 0,
          barBottomMargin: 0,
          gradientMask: { maskColor: Color.Transparent, maskHeight: 56 },
          // 握姿由宿主移动整个按钮，避免仅材质层移动造成点击区域错位。
          adaptToHandedness: false,
          thermoCtrl: true,
          barOpacity: 1
        })
        .scrollable(false)
        .onContentWillChange(() => false)
        .width(IMMERSIVE_READ_BUTTON_WIDTH)
        .height(56)
        .borderRadius(28, RenderStrategy.OFFSCREEN)
        .clip(true)
        .accessibilityLevel('no-hide-descendants')
        .hitTestBehavior(HitTestMode.None)
      } else {
        Column()
          .width(IMMERSIVE_READ_BUTTON_WIDTH)
          .height(56)
          .borderRadius(28)
          .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
          .border({ width: 1, color: ThemeRuntime.glassBorderColor(this.darkMode, 'panel') })
          .shadow(ThemeRuntime.floatingControlShadow(this.darkMode))
          .hitTestBehavior(HitTestMode.None)
      }

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Row({ space: AppSpacing.MD }) {
          if (this.busy) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(this.accentColor)
          } else {
            SymbolGlyph(this.icon)
              .fontSize(22)
              .fontColor([this.accentColor])
          }
          Text(this.label)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .maxLines(1)
        }
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
      .width(IMMERSIVE_READ_BUTTON_WIDTH)
      .height(56)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .backgroundColor(Color.Transparent)
      .enabled(!this.busy)
      .accessibilityText(this.label)
      .onClick(() => this.onRead())
    }
    .width(IMMERSIVE_READ_BUTTON_WIDTH)
    .height(56)
    .borderRadius(28)
    .border(ImmersiveMaterialRuntime.surfaceBorder(this.immersiveLightLevel, this.darkMode))
  }
}
