import { HttpTTS } from '@legado/sourceengine';
import { TtsVoiceInfo } from '../../account/AccountCommerceModels';
import { TtsVoiceOption } from '../../utils/SystemTtsReader';
import { TtsVoiceCatalog } from '../../utils/TtsVoiceCatalog';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';

/**
 * 阅读设置面板里的"朗读"页：倍速、音色入口、定时、开始/停止。
 * 只展示页面传入的朗读状态并把操作回报给页面；画在阅读页的设置面板里，配色用阅读主题。
 */
@Component
export struct ReaderTtsQuickSettingsPanel {
  @Prop speed: number = 1;
  @Prop voicesLoading: boolean = false;
  @Prop voiceTitle: string = '';
  @Prop sleepTimerMinutes: number = 0;
  @Prop sleepTimerRemainingSeconds: number = 0;
  @Prop speaking: boolean = false;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#80868B';
  @Prop accentColor: string = '#0A59F7';
  @Prop actionColor: string = '#0A59F7';
  onSpeedChange: (speed: number) => void = (_speed: number): void => {
  };
  onOpenVoicePicker: () => void = (): void => {
  };
  /** 0 表示取消定时。 */
  onSleepTimerChange: (minutes: number) => void = (_minutes: number): void => {
  };
  onToggleReading: () => void = (): void => {
  };

  private chipColor(): string {
    return this.dark ? '#24272D' : '#EEF0F3';
  }

  build() {
    Column({ space: AppSpacing.LG }) {
      Row() {
        Text('朗读倍速')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .layoutWeight(1)
        Text(`${this.speed.toFixed(1)}x`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor)
      }
      .width('100%')

      Row({ space: AppSpacing.MD }) {
        this.stepButton($r('sys.symbol.minus'), '降低朗读倍速', this.speed > 0.5, () => {
          this.onSpeedChange(this.speed - 0.1);
        })
        Slider({ value: this.speed, min: 0.5, max: 2, step: 0.1 })
          .layoutWeight(1)
          .showTips(true)
          .selectedColor(this.accentColor)
          .sliderInteractionMode(ImmersiveMaterialRuntime.supportsHds() ?
            SliderInteraction.SLIDE_AND_CLICK_UP : SliderInteraction.SLIDE_ONLY)
          .onChange((value: number) => this.onSpeedChange(value))
        this.stepButton($r('sys.symbol.plus'), '提高朗读倍速', this.speed !== 2, () => {
          this.onSpeedChange(this.speed + 0.1);
        })
      }
      .width('100%')

      Row({ space: AppSpacing.MD }) {
        this.speedChip(0.8)
        this.speedChip(1.0)
        this.speedChip(1.2)
        this.speedChip(1.5)
        this.speedChip(2.0)
      }
      .width('100%')

      Row() {
        Text('朗读音色')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .layoutWeight(1)
        if (this.voicesLoading) {
          Text('加载中')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
        }
      }
      .width('100%')

      Row() {
        Text(this.voiceTitle)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.textColor)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([this.subTextColor])
          .margin({ left: AppSpacing.MD })
      }
      .width('100%')
      .height(44)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .backgroundColor(this.chipColor())
      .borderRadius(ThemeRuntime.mediumRadius())
      .onClick(() => this.onOpenVoicePicker())

      Row() {
        Text('朗读定时')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .layoutWeight(1)
        Text(this.sleepTimerMinutes > 0 ?
          `剩余 ${Math.max(1, Math.ceil(this.sleepTimerRemainingSeconds / 60))} 分钟` : '未设置')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
      }
      .width('100%')

      Row({ space: AppSpacing.MD }) {
        this.sleepTimerChip(15)
        this.sleepTimerChip(30)
        this.sleepTimerChip(60)
        this.sleepTimerChip(90)
        this.sleepTimerChip(120)
      }
      .width('100%')

      Button(this.speaking ? '停止朗读' : '开始朗读')
        .width('100%')
        .height(40)
        .backgroundColor(this.speaking ? ThemeRuntime.dangerColor(this.dark) : this.actionColor)
        .fontColor(ThemeRuntime.onAccentColor())
        .onClick(() => this.onToggleReading())
    }
    .width('100%')
  }

  @Builder
  stepButton(icon: Resource, accessibilityText: string, enabled: boolean, action: () => void) {
    ImmersiveBackButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
      disabledIconColor: this.subTextColor,
      darkMode: this.dark,
      buttonEnabled: enabled,
      buttonSize: 34,
      containerWidth: 34,
      containerHeight: 34,
      startInset: 0,
      compactLayout: true,
      onBack: action
    })
  }

  @Builder
  speedChip(value: number) {
    Text(`${value.toFixed(1)}x`)
      .fontSize(AppFontSize.BODY)
      .fontColor(Math.abs(this.speed - value) < 0.01 ? '#FFFFFF' : this.textColor)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(32)
      .borderRadius(16)
      .backgroundColor(Math.abs(this.speed - value) < 0.01 ? this.accentColor : this.chipColor())
      .onClick(() => this.onSpeedChange(value))
  }

  @Builder
  sleepTimerChip(minutes: number) {
    Text(`${minutes}分`)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.sleepTimerMinutes === minutes ? '#FFFFFF' : this.textColor)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(32)
      .borderRadius(16)
      .backgroundColor(this.sleepTimerMinutes === minutes ? this.accentColor : this.chipColor())
      .accessibilityText(this.sleepTimerMinutes === minutes ?
        `关闭 ${minutes} 分钟朗读定时` : `设置 ${minutes} 分钟朗读定时`)
      .onClick(() => this.onSleepTimerChange(this.sleepTimerMinutes === minutes ? 0 : minutes))
  }
}

/**
 * 朗读音色选择面板：云端、自定义、系统三组音色。画在阅读页上的浮层，配色用阅读主题；
 * 在页面里的位置和进出场动画由页面加在组件上。
 */
@Component
export struct ReaderTtsVoicePickerPanel {
  @Prop cloudVoices: TtsVoiceInfo[] = [];
  @Prop customVoices: HttpTTS[] = [];
  @Prop systemVoices: TtsVoiceOption[] = [];
  /** 当前音色的键，取值见 TtsVoiceCatalog 的三个 *VoiceKey。 */
  @Prop selectedKey: string = '';
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#80868B';
  @Prop accentColor: string = '#0A59F7';
  @Prop panelColor: string = '#F2FFFFFF';
  @Prop panelBorderColor: string = '#1F000000';
  @Prop panelShadowColor: string = '#33000000';
  @Prop selectedColor: string = '#11007DFF';
  @Prop panelWidth: number = 360;
  @Prop panelHeight: number = 480;
  onClose: () => void = (): void => {
  };
  onSelectCloudVoice: (voice: TtsVoiceInfo) => void = (_voice: TtsVoiceInfo): void => {
  };
  onSelectCustomVoice: (voice: HttpTTS) => void = (_voice: HttpTTS): void => {
  };
  onSelectSystemVoice: (voice: TtsVoiceOption) => void = (_voice: TtsVoiceOption): void => {
  };

  build() {
    ReaderMaterialPanel({
      panelWidth: this.panelWidth,
      panelHeight: this.panelHeight,
      cornerRadius: 28,
      darkMode: this.dark,
      fallbackColor: this.panelColor
    }) {
      this.panelBody()
    }
  }

  @Builder
  panelBody() {
    Column() {
      Row() {
        Text('朗读音色')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor)

        Blank()
          .layoutWeight(1)

        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
          darkMode: this.dark,
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          materialScale: 0.83,
          compactLayout: true,
          accessibilityLabel: '关闭音色选择',
          onBack: () => this.onClose()
        })
      }
      .width('100%')
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.MD })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          if (this.cloudVoices.length > 0) {
            this.sectionTitle('云端音色')
            ForEach(this.cloudVoices, (voice: TtsVoiceInfo) => {
              this.option(TtsVoiceCatalog.cloudVoiceTitle(voice),
                TtsVoiceCatalog.cloudVoiceKey(voice) === this.selectedKey, () => this.onSelectCloudVoice(voice))
            }, (voice: TtsVoiceInfo) => TtsVoiceCatalog.cloudVoiceKey(voice))
          }

          if (this.customVoices.length > 0) {
            this.sectionTitle('自定义音色')
            ForEach(this.customVoices, (voice: HttpTTS) => {
              this.option(TtsVoiceCatalog.customVoiceTitle(voice),
                TtsVoiceCatalog.customVoiceKey(voice) === this.selectedKey, () => this.onSelectCustomVoice(voice))
            }, (voice: HttpTTS) => TtsVoiceCatalog.customVoiceKey(voice))
          }

          if (this.systemVoices.length > 0) {
            this.sectionTitle('系统音色')
            ForEach(this.systemVoices, (voice: TtsVoiceOption) => {
              this.option(TtsVoiceCatalog.voiceTitle(voice),
                TtsVoiceCatalog.voiceKey(voice) === this.selectedKey, () => this.onSelectSystemVoice(voice))
            }, (voice: TtsVoiceOption) => TtsVoiceCatalog.voiceKey(voice))
          }
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.XL })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .scrollBarColor(this.dark ? '#668A8F98' : '#667A6F63')
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.subTextColor)
      .width('100%')
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.LG, bottom: AppSpacing.SM })
  }

  @Builder
  option(title: string, selected: boolean, action: () => void) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.textColor)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([this.accentColor])
          .margin({ left: AppSpacing.MD })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(selected ? this.selectedColor : Color.Transparent)
    .onClick(action)
  }
}
