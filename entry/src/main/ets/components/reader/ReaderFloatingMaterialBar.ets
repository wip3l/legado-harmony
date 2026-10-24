import { uiMaterial } from '@kit.ArkUI';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';

/**
 * API 26 materials on layout containers only render inside supported system UI regions.
 * Keep the complete capsule inside one bottom TabBar, sized and clipped to the capsule itself.
 */
@Component
export struct ReaderFloatingMaterialBar {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop darkMode: boolean = false;
  @Prop fallbackColor: ResourceColor = '';
  @Prop barWidth: number = 320;
  @Prop barHeight: number = 48;
  /** 圆角；不传（负数）时按胶囊处理，取高度的一半。 */
  @Prop cornerRadius: number = -1;
  @Prop denseContent: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  @Builder
  materialContent() {
    Stack({ alignContent: Alignment.Center }) {
      // 内容侧的底色不会被系统材质覆盖；留出细边显示原生折射与高光。
      Stack({ alignContent: Alignment.Center }) {
        this.content()
      }
      .width('calc(100% - 2vp)')
      .height(this.barHeight - 2)
      .borderRadius(Math.max(0, this.radius() - 1))
      .backgroundColor(ImmersiveMaterialRuntime.surfaceColor(this.immersiveLightLevel,
        this.darkMode, this.fallbackColor, !this.denseContent))
      .clip(true)
    }
    .width('100%')
    .height(this.barHeight)
    .borderRadius(this.radius())
    .systemMaterial(this.material())
    .backgroundBlurStyle(ImmersiveMaterialRuntime.surfaceBlur(this.immersiveLightLevel))
    .border(ImmersiveMaterialRuntime.surfaceBorder(this.immersiveLightLevel, this.darkMode))
  }

  private radius(): number {
    return this.cornerRadius >= 0 ? this.cornerRadius : this.barHeight / 2;
  }

  private material(): uiMaterial.Material {
    return ImmersiveMaterialRuntime.componentMaterial({
      style: ImmersiveMaterialRuntime.materialStyle(this.immersiveLightLevel),
      // 材质保留边缘光感，可读性由内容底板保障。
      materialColor: Color.Transparent,
      applyShadow: false,
      // Sliders must not deform the whole capsule while the user drags them.
      interactive: false,
      lightEffect: ImmersiveMaterialRuntime.lightEffect(true, this.immersiveLightLevel)
    }, this.immersiveLightLevel);
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: 0 }) {
      TabContent() {
        Column()
      }
      .tabBar(this.materialContent())
    }
    .barMode(BarMode.Fixed)
    .barHeight(this.barHeight)
    .barOverlap(true)
    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.NONE)
    .scrollable(false)
    .onContentWillChange(() => false)
    .width(this.barWidth)
    .height(this.barHeight)
    .borderRadius(this.radius(), RenderStrategy.OFFSCREEN)
    .clip(true)
  }
}

/**
 * 阅读页浮层面板（目录、设置、朗读音色等）的底板：API 26+ 把整块面板放进 ReaderFloatingMaterialBar，
 * 由系统画沉浸光感材质；旧系统退回实色底加浅投影。面板需要明确的宽高。
 * 内容用尾随闭包传入；位置、进出场动画加在外面包的一层容器上。
 */
@Component
export struct ReaderMaterialPanel {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop panelWidth: number = 320;
  @Prop panelHeight: number = 400;
  @Prop cornerRadius: number = 28;
  @Prop darkMode: boolean = false;
  /** 没有系统材质时的实色底。 */
  @Prop fallbackColor: ResourceColor = '#FFFFFF';
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    if (ImmersiveMaterialRuntime.supportsHds()) {
      ReaderFloatingMaterialBar({
        barWidth: this.panelWidth,
        barHeight: this.panelHeight,
        cornerRadius: this.cornerRadius,
        fallbackColor: this.fallbackColor,
        darkMode: this.darkMode,
        denseContent: true
      }) {
        this.content()
      }
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        this.content()
      }
      .width(this.panelWidth)
      .height(this.panelHeight)
      .borderRadius(this.cornerRadius)
      .border(ImmersiveMaterialRuntime.surfaceBorder(this.immersiveLightLevel, this.darkMode))
      .clip(true)
      .backgroundColor(this.fallbackColor)
      .shadow({
        radius: 18,
        color: this.darkMode ? '#66000000' : '#1F000000',
        offsetX: 0,
        offsetY: 6
      })
    }
  }
}
