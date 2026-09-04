import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

@Component
export struct ReaderTtsPlayerPanel {
  @Prop darkMode: boolean = false;
  @Prop accentColor: ResourceColor = '#5B8F86';
  @Prop primaryTextColor: ResourceColor = '#18191C';
  @Prop subTextColor: ResourceColor = '#71747A';
  @Prop panelColor: ResourceColor = '#F7F7F7';
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop viewportHeight: number = 720;
  onClose: () => void = () => {};
  onOpenCatalog: () => void = () => {};
  onOpenVoice: () => void = () => ReaderTtsFloatingSession.openVoice();

  @StorageLink('globalTtsPaused') globalTtsPaused: boolean = false;
  @StorageLink('globalTtsBookName') globalTtsBookName: string = '';
  @StorageLink('globalTtsChapterTitle') globalTtsChapterTitle: string = '';
  @StorageLink('globalTtsMode') globalTtsMode: string = '';
  @StorageLink('globalTtsVoiceCode') globalTtsVoiceCode: string = '';
  @StorageLink('globalTtsCover') globalTtsCover: ResourceStr = '';
  @StorageLink('globalTtsCoverFrame') globalTtsCoverFrame: ResourceStr = '';
  @StorageLink('globalTtsContent') globalTtsContent: string = '';
  @StorageLink('globalTtsTextBefore') globalTtsTextBefore: string = '';
  @StorageLink('globalTtsCurrentText') @Watch('onCurrentTextChanged') globalTtsCurrentText: string = '';
  @StorageLink('globalTtsTextAfter') globalTtsTextAfter: string = '';
  @StorageLink('globalTtsChapterProgress') globalTtsChapterProgress: string = '';
  @StorageLink('globalTtsProgress') globalTtsProgress: number = 0;
  @StorageLink('globalTtsSpeed') globalTtsSpeed: number = 1;
  @StorageLink('globalTtsTimerMinutes') globalTtsTimerMinutes: number = 0;
  @StorageLink('globalTtsTimerRemainingSeconds') globalTtsTimerRemainingSeconds: number = 0;
  @StorageLink('globalTtsCanPrevious') globalTtsCanPrevious: boolean = false;
  @StorageLink('globalTtsCanNext') globalTtsCanNext: boolean = false;
  @StorageLink('globalTtsAudioPositionMs') globalTtsAudioPositionMs: number = 0;
  @StorageLink('globalTtsAudioDurationMs') globalTtsAudioDurationMs: number = 0;
  @StorageLink('globalTtsVoiceRevision') globalTtsVoiceRevision: number = 0;
  @State optionsPanel: number = 0;
  private textScroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    this.scrollToCurrentSentence(false);
  }

  onCurrentTextChanged(): void {
    this.scrollToCurrentSentence(true);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.darkMode ? '#52000000' : '#26000000')
        .backdropBlur(ThemeRuntime.glassBlur('popover', 10))
        .onClick(() => this.close())

      Column({ space: 14 }) {
        this.header()
        this.contentPanel()

        if (this.globalTtsMode === 'audio') {
          this.audioProgress()
        }

        this.playbackControls()

        if (this.optionsPanel === 1) {
          this.timerOptions()
        } else if (this.optionsPanel === 2) {
          this.speedOptions()
        }

        if (this.globalTtsMode === 'audio') {
          this.audioActions()
        } else if (ReaderTtsFloatingSession.ttsVoiceTitles().length > 0) {
          this.ttsVoiceSelect()
        }

        if (this.globalTtsMode !== 'audio') {
          this.catalogAction()
        }

        Button(this.globalTtsMode === 'audio' ? '停止听书' : '停止朗读')
          .width('100%')
          .height(42)
          .borderRadius(12)
          .fontColor('#FFFFFF')
          .backgroundColor('#D94841')
          .onClick(() => {
            this.close();
            ReaderTtsFloatingSession.stop();
          })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 18, right: 18, top: this.topInset + 16, bottom: this.bottomInset + 16 })
      .backgroundColor(this.panelColor)
      .backdropBlur(ThemeRuntime.glassBlur('panel', 24))
      .transition(TransitionEffect.translate({ y: 520 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 280, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  header() {
    Row({ space: 11 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(38).height(38).fill(ThemeRuntime.accentSurfaceColor(this.darkMode))
        SymbolGlyph($r('sys.symbol.speaker_wave_3'))
          .fontSize(19)
          .fontColor([this.accentColor])
      }
      Column({ space: 3 }) {
        Text(this.globalTtsBookName || '快速朗读')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.globalTtsChapterTitle || this.globalTtsChapterProgress)
          .fontSize(11)
          .fontColor(this.subTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(20)
        .fontColor([this.primaryTextColor])
        .width(38)
        .height(38)
        .accessibilityText('收起播放面板')
        .onClick(() => this.close())
    }
    .width('100%')
  }

  @Builder
  contentPanel() {
    Column({ space: 8 }) {
      this.bookCover()
      if (this.globalTtsMode === 'audio') {
        Scroll() {
          Text(this.globalTtsContent || '暂无书籍简介')
            .fontSize(15)
            .lineHeight(25)
            .fontColor(this.primaryTextColor)
            .copyOption(CopyOptions.LocalDevice)
            .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
            .width('100%')
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 4, right: 4 })
        .scrollBar(BarState.Auto)
      } else {
        List({ scroller: this.textScroller, space: 8 }) {
          ListItem() {
            Text(this.globalTtsTextBefore)
              .fontSize(15)
              .lineHeight(25)
              .fontColor(this.subTextColor)
              .width('100%')
          }
          ListItem() {
            Text(this.globalTtsCurrentText || '正在定位当前朗读内容…')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .lineHeight(26)
              .fontColor(this.primaryTextColor)
              .width('100%')
              .padding({ left: 8, right: 8, top: 6, bottom: 6 })
              .borderRadius(8)
              .backgroundColor(this.darkMode ? '#24FFFFFF' : '#12000000')
          }
          ListItem() {
            Text(this.globalTtsTextAfter || (this.globalTtsContent ? '' : '正在准备当前朗读内容…'))
              .fontSize(15)
              .lineHeight(25)
              .fontColor(this.subTextColor)
              .width('100%')
          }
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 4, right: 4 })
        .scrollBar(BarState.Auto)
      }
      Row() {
        Text(this.globalTtsChapterProgress || (this.globalTtsMode === 'audio' ? '后台听书' : '正在朗读'))
          .fontSize(10)
          .fontColor(this.subTextColor)
          .layoutWeight(1)
        if (this.globalTtsVoiceCode) {
          Text(this.globalTtsVoiceCode)
            .fontSize(10)
            .fontColor(this.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 150 })
        }
      }
      .width('100%')
      if (this.globalTtsMode !== 'audio' && this.globalTtsProgress > 0) {
        Progress({ value: this.globalTtsProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(3)
          .color(this.accentColor)
          .backgroundColor(this.darkMode ? '#34FFFFFF' : '#18000000')
      }
    }
    .layoutWeight(1)
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
  }

  @Builder
  bookCover() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.globalTtsCover) {
        Image(this.globalTtsCover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
        if (this.globalTtsCoverFrame) {
          Image(this.globalTtsCoverFrame)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        }
      } else {
        Column() {
          Text(this.globalTtsBookName ? this.globalTtsBookName.substring(0, 1) : '书')
            .fontSize(42)
            .fontColor('#FFFFFF')
        }
        .width('58%')
        .height('88%')
        .constraintSize({ maxWidth: 260, maxHeight: 360 })
        .borderRadius(10)
        .backgroundColor(this.accentColor)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height(this.coverHeight())
    .padding(10)
    .borderRadius(14)
    .clip(true)
  }

  @Builder
  playbackControls() {
    Row() {
      this.control($r('sys.symbol.timer'), this.globalTtsTimerMinutes > 0 ?
        `${Math.max(1, Math.ceil(this.globalTtsTimerRemainingSeconds / 60))}分` : '定时', true,
        () => this.optionsPanel = this.optionsPanel === 1 ? 0 : 1)
      this.control($r('sys.symbol.arrow_left'), '上一章', this.globalTtsCanPrevious,
        () => ReaderTtsFloatingSession.previous())
      this.playbackControl()
      this.control($r('sys.symbol.arrow_right'), '下一章', this.globalTtsCanNext,
        () => ReaderTtsFloatingSession.next())
      this.speedControl()
    }
    .width('100%')
  }

  @Builder
  playbackControl() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(46).height(46).fill(this.accentColor)
        SymbolGlyph(this.globalTtsPaused ? $r('sys.symbol.play') : $r('sys.symbol.pause'))
          .id(`shared_tts_panel_playback_${this.globalTtsPaused}`)
          .fontSize(23)
          .fontColor(['#FFFFFF'])
      }
      Text(this.globalTtsPaused ? '播放' : '暂停')
        .fontSize(10)
        .fontColor(this.subTextColor)
    }
    .layoutWeight(1)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .onClick(() => ReaderTtsFloatingSession.toggle())
  }

  @Builder
  control(icon: Resource, label: string, enabled: boolean, action: () => void) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(38).height(38).fill(this.darkMode ? '#24FFFFFF' : '#10000000')
        SymbolGlyph(icon)
          .fontSize(19)
          .fontColor([enabled ? this.primaryTextColor : this.subTextColor])
      }
      Text(label).fontSize(10).fontColor(this.subTextColor)
    }
    .layoutWeight(1)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .opacity(enabled ? 1 : 0.45)
    .onClick(() => { if (enabled) action(); })
  }

  @Builder
  speedControl() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(38).height(38).fill(this.darkMode ? '#24FFFFFF' : '#10000000')
        SymbolGlyph($r('sys.symbol.hourglass'))
          .fontSize(19)
          .fontColor([this.primaryTextColor])
      }
      Text(`${this.globalTtsSpeed.toFixed(1)}x`).fontSize(10).fontColor(this.subTextColor)
    }
    .layoutWeight(1)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.optionsPanel = this.optionsPanel === 2 ? 0 : 2)
  }

  @Builder
  timerOptions() {
    Row({ space: 6 }) {
      this.timerChip(0, '关闭')
      this.timerChip(15, '15分')
      this.timerChip(30, '30分')
      this.timerChip(60, '60分')
      this.timerChip(90, '90分')
      this.timerChip(120, '120分')
    }
    .width('100%')
  }

  @Builder
  speedOptions() {
    Row({ space: 8 }) {
      this.speedChip(0.8)
      this.speedChip(1.0)
      this.speedChip(1.2)
      this.speedChip(1.5)
      this.speedChip(2.0)
    }
    .width('100%')
  }

  @Builder
  speedChip(value: number) {
    Text(`${value.toFixed(1)}x`)
      .fontSize(11)
      .fontWeight(Math.abs(this.globalTtsSpeed - value) < 0.01 ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(Math.abs(this.globalTtsSpeed - value) < 0.01 ? '#FFFFFF' : this.primaryTextColor)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(15)
      .backgroundColor(Math.abs(this.globalTtsSpeed - value) < 0.01 ? this.accentColor :
        (this.darkMode ? '#20FFFFFF' : '#0D000000'))
      .onClick(() => ReaderTtsFloatingSession.setSpeed(value))
  }

  @Builder
  timerChip(minutes: number, label: string) {
    Text(label)
      .fontSize(11)
      .fontWeight(this.globalTtsTimerMinutes === minutes ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.globalTtsTimerMinutes === minutes ? '#FFFFFF' : this.primaryTextColor)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(15)
      .backgroundColor(this.globalTtsTimerMinutes === minutes ? this.accentColor :
        (this.darkMode ? '#20FFFFFF' : '#0D000000'))
      .onClick(() => ReaderTtsFloatingSession.setTimer(minutes))
  }

  @Builder
  ttsVoiceSelect() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.speaker_wave_3'))
        .fontSize(17)
        .fontColor([this.accentColor])
        .width(24)
      Select(this.ttsVoiceOptions())
        .id(`shared_tts_voice_${this.globalTtsVoiceRevision}_${ReaderTtsFloatingSession.ttsVoiceIndex()}`)
        .selected(ReaderTtsFloatingSession.ttsVoiceIndex())
        .value(this.globalTtsVoiceCode)
        .font({ size: 13 })
        .fontColor(this.primaryTextColor)
        .layoutWeight(1)
        .height(40)
        .padding({ left: 0, right: 0 })
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor)
        .selectedOptionFontColor(this.accentColor)
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.darkMode, ''))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .menuSystemMaterial(ImmersiveMaterialRuntime.selectMenuMaterial())
        .onSelect((index: number) => ReaderTtsFloatingSession.selectTtsVoice(index))
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 10 })
    .borderRadius(12)
    .backgroundColor(this.darkMode ? '#20FFFFFF' : '#0D000000')
  }

  ttsVoiceOptions(): SelectOption[] {
    return ReaderTtsFloatingSession.ttsVoiceTitles().map((title: string): SelectOption => ({ value: title }));
  }

  @Builder
  audioProgress() {
    Column({ space: 2 }) {
      Slider({ value: this.globalTtsAudioPositionMs, min: 0,
        max: Math.max(1, this.globalTtsAudioDurationMs), step: 1000 })
        .width('100%')
        .showTips(true)
        .selectedColor(this.accentColor)
        .trackColor(ThemeRuntime.inputColor(this.darkMode))
        .onChange((value: number, mode: SliderChangeMode) => {
          this.globalTtsAudioPositionMs = value;
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            ReaderTtsFloatingSession.seekAudio(value);
          }
        })
      Row() {
        Text(this.formatAudioDuration(this.globalTtsAudioPositionMs)).fontSize(11).fontColor(this.subTextColor)
        Blank()
        Text(this.formatAudioDuration(this.globalTtsAudioDurationMs)).fontSize(11).fontColor(this.subTextColor)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  audioActions() {
    Row({ space: 10 }) {
      Button(`音色 · ${this.globalTtsVoiceCode || '4'}`)
        .layoutWeight(1)
        .height(40)
        .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
        .fontColor(this.primaryTextColor)
        .onClick(() => this.onOpenVoice())
      Button('目录跳转')
        .layoutWeight(1)
        .height(40)
        .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
        .fontColor(this.primaryTextColor)
        .onClick(() => this.onOpenCatalog())
    }
    .width('100%')
  }

  @Builder
  catalogAction() {
    Button('目录跳转')
      .width('100%')
      .height(40)
      .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
      .fontColor(this.primaryTextColor)
      .onClick(() => this.onOpenCatalog())
  }

  close(): void {
    this.optionsPanel = 0;
    this.onClose();
  }

  coverHeight(): number {
    return Math.min(250, Math.max(130,
      (Math.max(1, this.viewportHeight) - this.topInset - this.bottomInset) * 0.32));
  }

  scrollToCurrentSentence(smooth: boolean): void {
    setTimeout(() => {
      if (this.globalTtsMode === 'audio') return;
      try {
        this.textScroller.scrollToIndex(1, smooth, ScrollAlign.CENTER);
      } catch (_) {}
    }, 0);
  }

  formatAudioDuration(valueMs: number): string {
    const totalSeconds = Math.max(0, Math.floor((valueMs || 0) / 1000));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    const mm = minutes.toString().padStart(2, '0');
    const ss = seconds.toString().padStart(2, '0');
    return hours > 0 ? `${hours}:${mm}:${ss}` : `${minutes}:${ss}`;
  }
}
