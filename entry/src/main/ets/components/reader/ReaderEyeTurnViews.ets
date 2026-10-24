import { ReaderEyeTurnCoordinator, ReaderEyeTurnViewState } from '../../core/reader/ReaderEyeTurnCoordinator';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/** 阅读设置里的"眼动校准"一行：当前屏幕方向、识别状态和校准入口。 */
@Component
export struct ReaderEyeTurnCalibrationSettingItem {
  @ObjectLink state: ReaderEyeTurnViewState;
  coordinator?: ReaderEyeTurnCoordinator;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#8A8A8A';
  @Prop accentColor: string = '#0A59F7';

  private landscape(): boolean {
    return this.coordinator ? this.coordinator.isLandscape() : false;
  }

  build() {
    Row() {
      Column() {
        Text('眼动校准')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
        Text(this.state.arFaceActive ? 'AR 自动校准 · 无需手动校准' :
          `${this.landscape() ? '横屏' : '竖屏'} · ${this.state.status}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .margin({ top: AppSpacing.XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.state.arFaceActive) {
        // AR Engine gaze needs no per-device calibration; only the camera pipeline does.
        Button(this.coordinator && this.coordinator.hasStoredCalibration() ? '重新校准' : '开始校准')
          .height(36)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(this.accentColor)
          .onClick((): void => this.coordinator?.openCalibration())
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 眼动翻页的三步校准浮层。相机预览画面由阅读页里常驻的 Surface 提供，
 * 这里只画预览框、目标点和操作面板，并把浮层尺寸回写给预览定位使用。
 */
@Component
export struct ReaderEyeCalibrationPanel {
  @ObjectLink state: ReaderEyeTurnViewState;
  coordinator?: ReaderEyeTurnCoordinator;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#8A8A8A';
  @Prop accentColor: string = '#0A59F7';
  @Prop panelColor: string = '#FFFFFF';
  @Prop panelBorderColor: string = '#22000000';
  @Prop viewportWidth: number = 0;
  @Prop viewportHeight: number = 0;
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;

  private previewWidth(): number {
    return this.state.previewWidthVp(this.viewportWidth, this.viewportHeight);
  }

  private previewHeight(): number {
    return this.state.previewHeightVp(this.viewportWidth, this.viewportHeight);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: AppSpacing.XL }) {
        Row() {
          Text('眼动翻页校准')
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textColor)
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([this.textColor])
          }
          .width(38)
          .height(38)
          .backgroundColor(this.dark ? '#28FFFFFF' : '#12000000')
          .onClick((): void => this.coordinator?.cancelCalibration())
        }
        .width('100%')

        Text(this.state.instruction())
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
          .textAlign(TextAlign.Center)

        Text('头部和手机保持稳定，只用眼睛注视目标点。每一步先看准目标点，再点击「开始采样」并保持视线不动。')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor)
          .textAlign(TextAlign.Center)
          .lineHeight(20)

        Progress({ value: this.state.calibrationProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(6)
          .color(this.accentColor)
        Text(this.state.status)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .textAlign(TextAlign.Center)
        if (!this.state.calibrationSessionActive) {
          Button('开始三步校准')
            .width('100%')
            .height(46)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.onAccentColor())
            .backgroundColor(this.accentColor)
            .onClick((): void => this.coordinator?.beginCalibrationCapture())
        } else {
          Button(this.state.calibrationCapturing ? '采样中…' : `开始采样（${this.state.targetLabel()}）`)
            .width('100%')
            .height(46)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor('#FFFFFF')
            .backgroundColor(this.state.calibrationCapturing ? (this.dark ? '#33FFFFFF' : '#33000000') :
            this.accentColor)
            .enabled(!this.state.calibrationCapturing)
            .onClick((): void => this.coordinator?.startCalibrationPhaseSampling())
        }
      }
      .width('calc(100% - 48vp)')
      .constraintSize({ maxWidth: 480 })
      .padding(AppSpacing.XXXL)
      .borderRadius(28)
      .backgroundColor(this.panelColor)
      .border({ width: 1, color: this.panelBorderColor })
      .margin({ bottom: AppSpacing.XXXL })

      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(this.previewWidth() * 0.48)
          .height(this.previewHeight() * 0.76)
          .borderRadius(999)
          .border({ width: 2, color: this.accentColor, style: BorderStyle.Dashed })

        Column() {
          Blank()
          Text(this.state.previewHint())
            .fontSize(AppFontSize.CAPTION)
            .fontColor('#FFFFFF')
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
            .borderRadius(ThemeRuntime.mediumRadius())
            .backgroundColor('#88000000')
            .margin({ bottom: AppSpacing.MD })
        }
        .height('100%')
      }
      .width(this.previewWidth())
      .height(this.previewHeight())
      .position({
        x: this.state.previewLeftVp(this.viewportWidth, this.viewportHeight),
        y: ReaderEyeTurnViewState.PREVIEW_TOP_VP
      })
      .borderRadius(20)
      .border({ width: 1, color: '#70FFFFFF' })
      .hitTestBehavior(HitTestMode.None)

      if (this.state.calibrationSessionActive && this.state.calibrationStep >= 0 &&
        this.state.calibrationStep < ReaderEyeTurnViewState.PHASE_COUNT) {
        Row()
          .width(24)
          .height(24)
          .borderRadius(12)
          .backgroundColor(this.accentColor)
          .border({ width: 4, color: this.dark ? '#A0FFFFFF' : '#D0FFFFFF' })
          .shadow({ radius: 16, color: this.accentColor, offsetX: 0, offsetY: 0 })
          .position({
            x: Math.max(0, (this.state.overlayWidth - 24) / 2),
            y: this.state.targetTopVp(this.viewportHeight, this.statusBarHeight, this.navBarHeight)
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width = Number(newArea.width);
      const height = Number(newArea.height);
      if (width > 0 && Math.abs(width - this.state.overlayWidth) >= 0.5) this.state.overlayWidth = width;
      if (height > 0 && Math.abs(height - this.state.overlayHeight) >= 0.5) this.state.overlayHeight = height;
    })
    .onClick((): void => {
    })
  }
}
