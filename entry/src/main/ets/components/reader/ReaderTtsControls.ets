import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';

/**
 * 朗读/听书悬浮胶囊：本页朗读与后台朗读共用同一外观。
 * 位置由使用方通过 translate 控制，这里只上报拖动的起止与偏移。
 */
@Component
export struct ReaderTtsCapsule {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop paused: boolean = false;
  @Prop playbackKey: string = '';
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#8A8A8A';
  @Prop accentColor: string = '#0A59F7';
  @Prop panelColor: string = '#FFFFFF';
  @Prop panelBorderColor: string = '#22000000';
  @Prop panelShadowColor: string = '#22000000';
  @Prop dark: boolean = false;
  onOpen: () => void = (): void => {
  };
  onToggle: () => void = (): void => {
  };
  onClose: () => void = (): void => {
  };
  onCapsuleDragStart: () => void = (): void => {
  };
  onCapsuleDragMove: (offsetX: number, offsetY: number) => void = (_offsetX: number, _offsetY: number): void => {
  };

  static readonly WIDTH: number = 184;
  static readonly HEIGHT: number = 46;

  build() {
    Column() {
      ReaderMaterialPanel({
        panelWidth: ReaderTtsCapsule.WIDTH,
        panelHeight: ReaderTtsCapsule.HEIGHT,
        cornerRadius: ReaderTtsCapsule.HEIGHT / 2,
        darkMode: this.dark,
        fallbackColor: this.panelColor
      }) {
        this.capsuleBody()
      }
    }
    .parallelGesture(
      PanGesture({ direction: PanDirection.All, distance: 4 })
        .onActionStart(() => this.onCapsuleDragStart())
        .onActionUpdate((event: GestureEvent) => this.onCapsuleDragMove(event.offsetX, event.offsetY))
    )
  }

  @Builder
  capsuleBody() {
    Row({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.SM }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle().width(30).height(30).fill(this.accentColor)
          SymbolGlyph($r('sys.symbol.speaker_wave_3'))
            .fontSize(15)
            .fontColor(['#FFFFFF'])
        }

        Column({ space: 1 }) {
          Text(this.title)
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textColor)
          Text(this.subtitle)
            .fontSize(9)
            .fontColor(this.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .onClick(() => this.onOpen())

      SymbolGlyph(this.paused ? $r('sys.symbol.play') : $r('sys.symbol.pause'))
        .id(this.playbackKey)
        .fontSize(17)
        .fontColor([this.textColor])
        .width(28)
        .height(34)
        .onClick(() => this.onToggle())
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(14)
        .fontColor([this.subTextColor])
        .width(24)
        .height(34)
        .onClick(() => this.onClose())
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.MD, right: AppSpacing.XS })
  }
}
