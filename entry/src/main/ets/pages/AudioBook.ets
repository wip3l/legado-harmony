import { BookCoverResolver } from '../utils/BookCoverResolver';
import fileUri from '@ohos.file.fileuri';
import { ThemeBookCoverSettings } from '../utils/ThemeBookCoverSettings';
import { BookCover } from '../components/book/BookCover';
import { NativeSourceService, NativeVoiceOption, Book, BookChapter, BookSource, BookTypeSupport, BookUrlResolver, VerificationSupport } from '@legado/sourceengine';
import { router } from '@kit.ArkUI';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import { AppDatabase } from '../model/data/AppDatabase';
import { ReadBookEngine } from '../core/book/ReadBookEngine';
import { WebBookService } from '../core/book/WebBookService';
import { BookSourceDataUrlSupport } from '../core/book/BookSourceDataUrlSupport';
import { AudioRuleSupport } from '../core/book/AudioRuleSupport';
import { AudioStartTiming, RemoteAudioPlayback, RemoteAudioPlaybackListener } from '../utils/RemoteAudioPlayback';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { BookCoverCache } from '../utils/BookCoverCache';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ReaderTtsPlayerPanel } from '../components/ReaderTtsPlayerPanel';
import { TtsCatalogSheet, CatalogTitleDataSource } from '../components/TtsCatalogSheet';
import { BookSourceStageRuntimeHost } from '../components/BookSourceStageRuntimeHost';
import { BookSourceAudioWebRuntimeHost } from '../components/BookSourceAudioWebRuntimeHost';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

/** 书源解析出音频地址的总时限。WebView 嗅探本身最多 15 秒，失败后还会回退 HTTP 规则。 */
const AUDIO_URL_RESOLVE_TIMEOUT_MS = 30000;

class AudioBookPlaybackListener implements RemoteAudioPlaybackListener {
  private readonly stateCallback: (state: string) => void;
  private readonly positionCallback: (positionMs: number, durationMs: number) => void;
  private readonly completedCallback: () => void;
  private readonly errorCallback: (message: string) => void;

  constructor(stateCallback: (state: string) => void,
    positionCallback: (positionMs: number, durationMs: number) => void,
    completedCallback: () => void, errorCallback: (message: string) => void) {
    this.stateCallback = stateCallback;
    this.positionCallback = positionCallback;
    this.completedCallback = completedCallback;
    this.errorCallback = errorCallback;
  }

  onStateChanged(state: string): void { this.stateCallback(state); }
  onPositionChanged(positionMs: number, durationMs: number): void {
    this.positionCallback(positionMs, durationMs);
  }
  onPlaybackCompleted(): void { this.completedCallback(); }
  onPlaybackError(message: string): void { this.errorCallback(message); }
}

/**
 * RemoteAudioPlayback lives for the whole process, while AudioBookPage instances can be
 * replaced when the user reopens the floating player. Keep the AVSession at the same
 * lifetime as the player so a newly opened page can take over and, importantly, destroy
 * the session created by the previous page.
 */
class AudioBookAvSessionHolder {
  static session: avSession.AVSession | null = null;
}

@Entry
@Component
struct AudioBookPage {
  // 加密的书源封面解密完成后递增，读取它的封面会重新取到本地文件地址。
  @StorageProp('sourceCoverRevision') sourceCoverRevision: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appThemeBookCoverEnabled') @Watch('onThemeBookCoverChanged')
  themeBookCoverEnabled: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State book: Book | null = null;
  @State chapters: BookChapter[] = [];
  @State chapterIndex: number = 0;
  @State positionMs: number = 0;
  @State durationMs: number = 0;
  @State playbackState: string = 'idle';
  @State speed: number = 1;
  @State statusText: string = '正在加载听书信息…';
  // 打开页面后读书籍、目录这段时间也算加载中，播放面板据此显示加载状态。
  @State openingBook: boolean = true;
  @State showChapterList: boolean = false;
  @StorageLink('globalTtsAudioCatalogReverseOrder') @Watch('onChapterOrderChanged')
  chapterReverseOrder: boolean = false;
  private voiceDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showVoiceDialog: boolean = false;
  @State voiceCodeInput: string = '';
  @State audioVoiceCode: string = '';
  @State audioVoiceTitles: string[] = ['默认'];
  @State audioVoiceIndex: number = 0;
  @State sleepMinutes: number = 0;
  @State sleepRemainingSeconds: number = 0;
  @State audioOptionsPanel: number = 0;
  @State viewportHeight: number = 720;
  private bookUrl: string = '';
  @State source: BookSource | null = null;
  private openedWithShelfAnimation: boolean = false;
  private openedFromShortcut: boolean = false;
  private shortcutReplacedPreviousPage: boolean = false;
  private playback: RemoteAudioPlayback = RemoteAudioPlayback.get();
  private playbackListener: RemoteAudioPlaybackListener = new AudioBookPlaybackListener(
    (state: string): void => this.onPlaybackStateChanged(state),
    // 切章后新章节地址就绪前，上一章仍在播放；它的进度、播完和报错不能记到新章节头上。
    (positionMs: number, durationMs: number): void => {
      if (this.isPlaybackOnCurrentChapter()) this.onPlaybackPositionChanged(positionMs, durationMs);
    },
    (): void => {
      if (this.isPlaybackOnCurrentChapter()) this.onPlaybackCompleted();
    },
    (message: string): void => {
      if (this.isPlaybackOnCurrentChapter()) this.onPlaybackError(message);
    });
  private progressSaveTimerId: number = -1;
  private progressSaveQueue: Promise<void> = Promise.resolve();
  private sleepTimerId: number = -1;
  private playbackRetryCount: number = 0;
  private chapterDataSource: CatalogTitleDataSource = new CatalogTitleDataSource();
  private chapterScroller: ListScroller = new ListScroller();
  private loadingSerial: number = 0;
  private audioBackgroundRunning: boolean = false;
  private audioBackgroundStarting: boolean = false;
  private audioBackgroundDesired: boolean = false;
  private audioAvSession: avSession.AVSession | null = null;
  private audioAvSessionStarting: boolean = false;
  private lastAvSessionPositionUpdateAt: number = 0;
  private lastMediaChapterCommandAt: number = 0;
  private audioBackgroundHeartbeatId: number = -1;
  private floatingSessionOwnerId: string = '';
  private pendingPanelAction: string = '';
  private lastFloatingPositionUpdateAt: number = 0;
  private stopPlaybackPromise: Promise<void> | null = null;
  private pageVisible: boolean = true;
  private latestPositionMs: number = 0;
  private latestDurationMs: number = 0;

  aboutToAppear(): void {
    this.syncBars();
    const params = router.getParams() as Record<string, string>;
    this.bookUrl = params?.['bookUrl'] || '';
    this.floatingSessionOwnerId = `audio_${this.bookUrl}`;
    this.pendingPanelAction = params?.['audioPanelAction'] || '';
    this.openedWithShelfAnimation = params?.['shelfBookOpening'] === 'true';
    this.openedFromShortcut = params?.['shortcutEntry'] === 'true';
    this.shortcutReplacedPreviousPage = params?.['shortcutReplace'] === 'true';
    this.playback.attach(this.playbackListener);
    if (this.bookUrl && this.playback.bookUrl === this.bookUrl && this.playback.mediaUrl) {
      // 从书架胶囊回到正在播放的这本书：沿用播放器状态，不显示加载中。
      this.playbackState = this.playback.state;
      this.openingBook = false;
    }
    this.loadBook();
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.syncBars();
    this.playback.attach(this.playbackListener);
    this.restoreSleepTimerUi();
    this.refreshVoiceSource();
  }

  onPageHide(): void {
    this.pageVisible = false;
  }

  onBackPress(): boolean {
    this.closePage();
    return true;
  }

  aboutToDisappear(): void {
    this.saveProgressNow(true);
    if (!ReaderTtsFloatingSession.isOwner(this.floatingSessionOwnerId)) {
      this.playback.detach(this.playbackListener);
      this.clearProgressSaveTimer();
    }
    this.clearSleepTimer();
  }

  audioPanelTransition(): TransitionEffect {
    const appear = TransitionEffect.translate({ y: 52 })
      .combine(TransitionEffect.scale({ x: 0.985, y: 0.985, centerX: '50%', centerY: '100%' }))
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 300, curve: Curve.Friction });
    const disappear = TransitionEffect.translate({ y: 28 })
      .combine(TransitionEffect.scale({ x: 0.99, y: 0.99, centerX: '50%', centerY: '100%' }))
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 190, curve: Curve.EaseIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ReaderTtsPlayerPanel({
        darkMode: this.appDarkMode,
        accentColor: this.accentColor(),
        playButtonColor: ThemeRuntime.buttonColor(this.appDarkMode),
        primaryTextColor: this.primaryTextColor(),
        subTextColor: this.subTextColor(),
        panelColor: ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'),
        backgroundThemeId: ThemeRuntime.ttsPanelThemeId(this.appDarkMode),
        topInset: this.statusBarHeight,
        bottomInset: this.navBarHeight,
        viewportHeight: this.viewportHeight,
        hostAudioPage: true,
        hostBookName: this.book?.name || '',
        hostChapterTitle: this.currentChapter()?.title || '',
        hostIntro: this.book ? this.displayIntro() : '',
        hostBookUrl: this.bookUrl,
        hostCover: this.book ? this.panelCover() : '',
        hostPlaying: this.isPlaying(),
        hostStatusText: this.panelStatusText(),
        hostBusy: this.isPanelBusy(),
        hostVoiceTitles: this.audioVoiceTitles,
        hostVoiceIndex: this.audioVoiceIndex,
        onSelectHostVoice: (index: number) => this.selectVoice(index),
        onClose: () => this.closePage(),
        onOpenVoice: () => this.openVoiceDialog(),
        onOpenCatalog: () => this.openChapterList(),
        onTogglePlayback: () => {
          this.togglePlayback();
        }
      })

      if (this.showChapterList) {
        this.chapterListOverlay()
      }
      BookSourceStageRuntimeHost()
      BookSourceAudioWebRuntimeHost()
      WebBookFetchRuntimeHost()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const height = typeof newValue.height === 'number' ? newValue.height : Number.parseFloat(`${newValue.height}`);
      if (Number.isFinite(height) && height > 0) this.viewportHeight = height;
    })
  }

  @Builder
  audioPlayerHeader() {
    Row({ space: AppSpacing.LG }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(38).height(38).fill(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        SymbolGlyph($r('sys.symbol.speaker_wave_3'))
          .fontSize(19)
          .fontColor([this.accentColor()])
      }
      Column({ space: AppSpacing.XXS }) {
        Text(this.book?.name || '快速听书')
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.currentChapter()?.title || this.statusText)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(20)
        .fontColor([this.primaryTextColor()])
        .width(38)
        .height(38)
        .onClick(() => this.closePage())
    }
    .width('100%')
  }

  @Builder
  audioIntroCard() {
    Column({ space: AppSpacing.MD }) {
      Stack({ alignContent: Alignment.Center }) {
        BookCover({ bookUrl: this.bookUrl, origin: this.book?.origin || '',
          name: this.book?.name || '', author: this.book?.author || '',
          coverUrl: this.book?.coverUrl || '', customCoverUrl: this.book?.customCoverUrl || '',
          placeholderColor: this.accentColor(), cornerRadius: 12 })
          .width('58%')
          .height('88%')
          .constraintSize({ maxWidth: 260, maxHeight: 360 })
      }
      .width('100%')
      .height(Math.min(250, Math.max(130,
        (this.viewportHeight - this.statusBarHeight - this.navBarHeight) * 0.32)))
      .padding(AppSpacing.MD)
      .borderRadius(14)
      .clip(true)
      Scroll() {
        Text(this.displayIntro())
          .fontSize(AppFontSize.BODY_LARGE)
          .lineHeight(25)
          .fontColor(this.primaryTextColor())
          .copyOption(CopyOptions.LocalDevice)
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1)
      .width('100%')
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
      .scrollBar(BarState.Auto)
    }
    .layoutWeight(1)
    .width('100%')
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
  }

  @Builder
  audioPanelControls() {
    Row() {
      this.audioPanelControl($r('sys.symbol.timer'), this.sleepMinutes > 0 ?
        `${Math.max(1, Math.ceil(this.sleepRemainingSeconds / 60))}分` : '定时', true,
        () => this.audioOptionsPanel = this.audioOptionsPanel === 1 ? 0 : 1)
      this.audioChapterControl($r('sys.symbol.arrow_left'), '上一章', -1)
      this.audioPlaybackControl()
      this.audioChapterControl($r('sys.symbol.arrow_right'), '下一章', 1)
      this.audioPanelControl($r('sys.symbol.hourglass'), `${this.speed.toFixed(1)}x`, true,
        () => this.audioOptionsPanel = this.audioOptionsPanel === 2 ? 0 : 2)
    }
    .width('100%')
  }

  @Builder
  audioPanelControl(icon: Resource, label: string, enabled: boolean, action: () => void) {
    Column({ space: AppSpacing.SM }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(38).height(38).fill(ThemeRuntime.hairlineColor(this.appDarkMode))
        SymbolGlyph(icon).fontSize(19).fontColor([enabled ? this.primaryTextColor() : this.subTextColor()])
      }
      Text(label).fontSize(AppFontSize.MICRO).fontColor(this.subTextColor())
    }
    .layoutWeight(1)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .opacity(enabled ? 1 : 0.45)
    .onClick(() => { if (enabled) action(); })
  }

  @Builder
  audioChapterControl(icon: Resource, label: string, offset: number) {
    Column({ space: AppSpacing.SM }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(38).height(38).fill(ThemeRuntime.hairlineColor(this.appDarkMode))
        SymbolGlyph(icon)
          .fontSize(19)
          .fontColor([(offset < 0 ? this.chapterIndex > 0 : this.chapterIndex < this.chapters.length - 1) ?
            this.primaryTextColor() : this.subTextColor()])
      }
      Text(label).fontSize(AppFontSize.MICRO).fontColor(this.subTextColor())
    }
    .layoutWeight(1)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .opacity((offset < 0 ? this.chapterIndex > 0 : this.chapterIndex < this.chapters.length - 1) ? 1 : 0.45)
    .onClick(() => {
      const enabled = offset < 0 ? this.chapterIndex > 0 : this.chapterIndex < this.chapters.length - 1;
      if (enabled) this.changeChapter(offset);
    })
  }

  @Builder
  audioPlaybackControl() {
    Column({ space: AppSpacing.SM }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(46).height(46).fill(this.accentColor())
        SymbolGlyph(this.isPlaying() ? $r('sys.symbol.pause') : $r('sys.symbol.play'))
          .fontSize(23)
          .fontColor(['#FFFFFF'])
      }
      Text(this.playbackState === 'loading' ? '加载中' : (this.isPlaying() ? '暂停' : '播放'))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
    }
    .layoutWeight(1)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .opacity(this.playbackState === 'loading' ? 0.55 : 1)
    .onClick(() => { if (this.playbackState !== 'loading') this.togglePlayback(); })
  }


  onSystemDialogFlagChanged(): void {
    if (!this.showVoiceDialog) this.voiceDialogSession.close(this.getUIContext());
  }

  openVoiceCodeDialog(): void {
    this.showVoiceDialog = true;
    const content: CustomBuilder = (): void => {
      this.voiceCodeDialogContent();
    };
    this.voiceDialogSession.open(this.getUIContext(), content, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示音色代码弹窗失败:'
    });
  }

  @Builder
  audioPanelActions() {
    Row({ space: AppSpacing.MD }) {
      Button(`音色 · ${this.currentVoiceCode()}`)
        .layoutWeight(1)
        .height(40)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => this.openVoiceDialog())
      Button('目录跳转')
        .layoutWeight(1)
        .height(40)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => this.openChapterList())
    }
    .width('100%')
  }

  @Builder
  voiceCodeDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text('听书音色代码')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Text('填写书源详情中列出的数字音色代码；留空使用书源默认音色')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
      TextInput({ text: this.voiceCodeInput, placeholder: '留空使用书源默认音色' })
        .type(InputType.Number)
        .height(44)
        .width('100%')
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onChange((value: string) => {
          this.voiceCodeInput = value;
        })
      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.showVoiceDialog = false;
          })
        Button('保存并重新加载')
          .layoutWeight(1)
          .backgroundColor(this.accentColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => this.saveVoiceCode())
      }
      .width('100%')
    }    .padding(AppSpacing.XXL)
  }


  @Builder
  coverSection() {
    Column() {
      BookCover({ bookUrl: this.bookUrl, origin: this.book?.origin || '',
        name: this.book?.name || '', author: this.book?.author || '',
        coverUrl: this.book?.coverUrl || '', customCoverUrl: this.book?.customCoverUrl || '',
        placeholderColor: this.accentColor(), cornerRadius: 16 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  chapterSection() {
    Column() {
      Text(this.currentChapter()?.title || '正在获取目录...')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      Text(this.chapters.length > 0 ? `${this.chapterIndex + 1} / ${this.chapters.length}` : '- / -')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .margin({ top: AppSpacing.SM })
    }
    .width('100%')
    .margin({ top: AppSpacing.XXXL })
  }

  @Builder
  progressSection() {
    Column() {
      Slider({ value: this.positionMs, min: 0, max: Math.max(1, this.durationMs), step: 1000 })
        .width('100%')
        .showTips(true)
        .selectedColor(this.accentColor())
        .trackColor(this.inputColor())
        .onChange((value: number, mode: SliderChangeMode) => {
          this.positionMs = value;
          this.latestPositionMs = value;
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.playback.seek(value);
            this.scheduleProgressSave();
          }
        })
      Row() {
        Text(this.formatDuration(this.positionMs))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
        Blank()
        Text(this.formatDuration(this.durationMs))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  playbackControls() {
    Row() {
      Button('上一章')
        .height(44)
        .fontSize(AppFontSize.BODY)
        .enabled(this.chapterIndex > 0)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => this.changeChapter(-1))
      Button(this.isPlaying() ? '暂停' : (this.playbackState === 'loading' ? '加载中' : '播放'))
        .width(100)
        .height(52)
        .fontSize(AppFontSize.SUBTITLE)
        .enabled(this.chapters.length > 0 && this.playbackState !== 'loading')
        .backgroundColor(this.accentColor())
        .fontColor(ThemeRuntime.onAccentColor())
        .onClick(() => this.togglePlayback())
      Button('下一章')
        .height(44)
        .fontSize(AppFontSize.BODY)
        .enabled(this.chapterIndex < this.chapters.length - 1)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => this.changeChapter(1))
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
    .alignItems(VerticalAlign.Center)
    .margin({ top: AppSpacing.XXL })
  }

  @Builder
  speedSection() {
    Row({ space: AppSpacing.MD }) {
      this.audioSpeedChip(0.8)
      this.audioSpeedChip(1.0)
      this.audioSpeedChip(1.2)
      this.audioSpeedChip(1.5)
      this.audioSpeedChip(2.0)
    }
    .width('100%')
  }

  @Builder
  sleepSection() {
    Row({ space: AppSpacing.SM }) {
      this.audioTimerChip(0, '关闭')
      this.audioTimerChip(15, '15分')
      this.audioTimerChip(30, '30分')
      this.audioTimerChip(60, '60分')
      this.audioTimerChip(90, '90分')
      this.audioTimerChip(120, '120分')
    }
    .width('100%')
  }

  @Builder
  audioSpeedChip(value: number) {
    Text(`${value.toFixed(1)}x`)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(Math.abs(this.speed - value) < 0.01 ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(Math.abs(this.speed - value) < 0.01 ? '#FFFFFF' : this.primaryTextColor())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(15)
      .backgroundColor(Math.abs(this.speed - value) < 0.01 ? this.accentColor() :
        (ThemeRuntime.softFillColor(this.appDarkMode)))
      .onClick(() => this.changeSpeed(value))
  }

  @Builder
  audioTimerChip(minutes: number, label: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(this.sleepMinutes === minutes ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.sleepMinutes === minutes ? '#FFFFFF' : this.primaryTextColor())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(15)
      .backgroundColor(this.sleepMinutes === minutes ? this.accentColor() :
        (ThemeRuntime.softFillColor(this.appDarkMode)))
      .onClick(() => this.setSleepTimer(minutes))
  }

  @Builder
  chapterListOverlay() {
    TtsCatalogSheet({
      bookUrl: this.bookUrl,
      darkMode: this.appDarkMode,
      accentColor: this.accentColor(),
      primaryTextColor: this.primaryTextColor(),
      subTextColor: this.subTextColor(),
      controlIconColor: this.primaryTextColor(),
      panelColor: ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'),
      bookName: this.book?.name || '',
      bookInitial: this.bookInitial(),
      cover: this.displayCover(),
      bookSubtitle: this.book?.author || '',
      count: this.chapters.length,
      currentDisplayIndex: this.chapterDisplayIndex(this.chapterIndex),
      reverseOrder: this.chapterReverseOrder,
      progressText: `${this.chapterIndex + 1} / ${this.chapters.length}`,
      bottomInset: this.navBarHeight,
      viewportHeight: this.viewportHeight,
      zIndexValue: 20,
      scroller: this.chapterScroller,
      source: this.chapterDataSource,
      isCached: (displayIndex: number): boolean =>
        this.isChapterCached(this.chapterCanonicalIndex(displayIndex)),
      onToggleOrder: () => this.toggleChapterOrder(),
      onSelect: (displayIndex: number) => this.selectChapter(this.chapterCanonicalIndex(displayIndex)),
      onClose: () => this.closeChapterList()
    })
  }

  async loadBook(): Promise<void> {
    const serial = ++this.loadingSerial;
    if (!this.bookUrl) {
      this.openingBook = false;
      this.playbackState = 'error';
      this.statusText = '书籍地址为空';
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      let storedBook = await db.getBook(this.bookUrl);
      if (!storedBook || serial !== this.loadingSerial) {
        if (!storedBook) {
          this.playbackState = 'error';
          this.statusText = '书籍不存在，请重新从搜索结果打开';
        }
        return;
      }
      this.source = storedBook.origin ? await db.getBookSource(storedBook.origin) : null;
      if (this.source && BookSourceDataUrlSupport.sourceUsesGySearch(this.source) &&
        (!/(?:音色配置|真人音色|AI音色)/.test(storedBook.intro || '') ||
          !/(?:数据来源|当前模式)/.test(storedBook.intro || ''))) {
        storedBook = await new WebBookService().getBookInfo(this.source, storedBook);
        if (serial !== this.loadingSerial) return;
        await db.updateBook(storedBook, false);
      }
      BookTypeSupport.applyBookType(storedBook, this.source);
      storedBook.type = storedBook.type || BookTypeSupport.AUDIO;
      this.book = storedBook;
      this.audioVoiceCode = storedBook.getVariable('custom') || '';
      this.refreshVoiceOptions();
      this.speed = this.savedSpeed(storedBook);
      const engine = ReadBookEngine.get();
      const requestedBookUrl = storedBook.bookUrl;
      await engine.openBook(storedBook);
      if (serial !== this.loadingSerial || engine.book?.bookUrl !== requestedBookUrl) return;
      this.book = engine.book || storedBook;
      BookTypeSupport.applyBookType(this.book, this.source);
      if (BookTypeSupport.isAudio(this.book) && this.book.type !== BookTypeSupport.AUDIO) {
        this.book.type |= BookTypeSupport.AUDIO;
      }
      this.chapters = engine.chapters;
      this.refreshChapterDataSource();
      this.chapterIndex = this.clampChapterIndex(this.book.durChapterIndex);
      await db.updateBook(this.book, false);
      if (this.chapters.length === 0) {
        this.playbackState = 'error';
        this.statusText = '未获取到听书目录';
        return;
      }
      if (this.playback.matches(this.book.bookUrl, this.chapterIndex)) {
        this.positionMs = this.playback.positionMs;
        this.durationMs = this.playback.durationMs;
        this.latestPositionMs = this.playback.positionMs;
        this.latestDurationMs = this.playback.durationMs;
        this.playbackState = this.playback.state;
        this.speed = this.playback.speed;
        this.statusText = this.stateLabel(this.playback.state);
        this.publishFloatingSession();
      } else {
        await this.playCurrentChapter(this.book.durChapterPos);
      }
      this.applyPendingPanelAction();
    } catch (error) {
      this.playbackState = 'error';
      this.statusText = `打开听书失败：${this.errorMessage(error)}`;
      console.error('打开听书失败:', error);
    } finally {
      this.openingBook = false;
    }
  }

  async saveVoiceCode(): Promise<void> {
    const book = this.book;
    if (!book) return;
    const value = (this.voiceCodeInput || '').trim();
    book.putVariable('custom', value);
    this.audioVoiceCode = value;
    this.refreshVoiceOptions();
    if (book.intro && value) {
      book.intro = book.intro.replace(/(音色配置\s*[：:]\s*)[^\s\n]+/, `$1${value}`);
    }
    this.book = book;
    await this.queueBookStateSave(book);
    const engine = ReadBookEngine.get();
    if (engine.book && engine.book.bookUrl === book.bookUrl) {
      engine.book.putVariable('custom', value);
      engine.clearCurrentBookMemoryCache();
    }
    this.showVoiceDialog = false;
    this.statusText = value ? `正在切换音色 ${value}...` : '正在恢复书源默认音色...';
    this.publishFloatingSession();
    await this.playCurrentChapter(0, true);
  }

  async playCurrentChapter(startPositionMs: number = 0, forceRefresh: boolean = false): Promise<void> {
    const book = this.book;
    const chapter = this.currentChapter();
    if (!book || !chapter) return;
    const serial = ++this.loadingSerial;
    const chapterIndex = this.chapterIndex;
    const timing = new AudioStartTiming(chapterIndex);
    let timedOut = false;
    // 被新的选章取代或超时后，书源请求在取消检查点停下，不再占着书源的请求频率额度。
    const cancelled = (): boolean => timedOut || serial !== this.loadingSerial;
    this.latestPositionMs = Math.max(0, startPositionMs);
    this.latestDurationMs = 0;
    if (this.pageVisible) {
      this.positionMs = this.latestPositionMs;
      this.durationMs = 0;
    }
    this.playbackRetryCount = forceRefresh ? this.playbackRetryCount : 0;
    this.statusText = forceRefresh ? '正在刷新音频地址…' : '正在获取音频地址…';
    this.playbackState = 'loading';
    this.syncFloatingStatus();
    try {
      // 上一章若还在缓冲，立即作废，免得它在新章节地址就绪前先响起来。
      await this.playback.abortPendingLoad();
      await ReaderTtsFloatingSession.stopOther(this.floatingSessionOwnerId);
      if (serial !== this.loadingSerial) return;
      const engine = ReadBookEngine.get();
      const content = await this.withAudioResolveTimeout(
        forceRefresh ? engine.reloadContent(chapterIndex, cancelled) : engine.loadContent(chapterIndex, cancelled),
        (): void => {
          timedOut = true;
        });
      timing.mark('resolve-url');
      if (serial !== this.loadingSerial) return;
      const url = this.resolveAudioUrl(content, chapter.url || book.bookUrl || this.source?.bookSourceUrl || '');
      if (!url) throw new Error(this.invalidAudioAddressMessage(content));
      const headers = this.audioHeaders(url, this.source, content);
      await this.playback.play(book.bookUrl, chapterIndex, url, headers, startPositionMs, this.speed, timing);
      if (serial !== this.loadingSerial) return;
      this.statusText = '正在播放';
      this.publishFloatingSession();
      this.saveProgressNow();
    } catch (error) {
      if (serial !== this.loadingSerial) return;
      // 超时再自动刷新重试一遍通常还是超时，让用户看到原因后自己点播放重试。
      if (timedOut) this.playbackRetryCount = Math.max(this.playbackRetryCount, 1);
      this.onPlaybackError(this.errorMessage(error));
    }
  }

  private async withAudioResolveTimeout(task: Promise<string>, onTimeout: () => void): Promise<string> {
    let timerId: number = -1;
    const timeout = new Promise<string>((_resolve, reject): void => {
      timerId = setTimeout((): void => {
        timerId = -1;
        onTimeout();
        reject(new Error(`获取音频地址超时（超过 ${AUDIO_URL_RESOLVE_TIMEOUT_MS / 1000} 秒），可点播放重试`));
      }, AUDIO_URL_RESOLVE_TIMEOUT_MS);
    });
    try {
      return await Promise.race([task, timeout]);
    } finally {
      if (timerId >= 0) clearTimeout(timerId);
    }
  }

  /** 播放器里装的是否就是页面当前选中的章节。切章后新地址就绪前，播放器里还是上一章。 */
  private isPlaybackOnCurrentChapter(): boolean {
    return !!this.book && this.playback.bookUrl === this.book.bookUrl &&
      this.playback.chapterIndex === this.chapterIndex;
  }

  async togglePlayback(): Promise<void> {
    try {
      if (this.isPlaying()) await this.playback.pause();
      else if (this.playback.matches(this.book?.bookUrl || '', this.chapterIndex)) await this.playback.resume();
      else await this.playCurrentChapter(this.positionMs);
    } catch (error) {
      this.onPlaybackError(this.errorMessage(error));
    }
  }

  async changeChapter(offset: number): Promise<void> {
    await this.selectChapter(this.chapterIndex + offset);
  }

  openChapterList(): void {
    this.refreshChapterDataSource();
    // Re-snapshot at open time so the cache chip reflects chapters cached while this
    // session has been running, instead of the state at session publish time.
    ReaderTtsFloatingSession.updateCatalogCachedFlags(
      this.floatingSessionOwnerId, this.chapterCachedFlags());
    animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.showChapterList = true;
    });
    this.scrollChapterListToCurrent();
  }

  chapterCanonicalIndex(displayIndex: number): number {
    return this.chapterReverseOrder ? this.chapters.length - 1 - displayIndex : displayIndex;
  }

  refreshChapterDataSource(): void {
    const titles = this.chapters.map((chapter: BookChapter): string => chapter.title || '');
    this.chapterDataSource.replace(this.chapterReverseOrder ? titles.slice().reverse() : titles);
  }

  onChapterOrderChanged(): void {
    this.refreshChapterDataSource();
    this.scrollChapterListToCurrent();
  }

  toggleChapterOrder(): void {
    this.chapterReverseOrder = !this.chapterReverseOrder;
  }

  chapterDisplayIndex(canonicalIndex: number): number {
    return this.chapterReverseOrder ? this.chapters.length - 1 - canonicalIndex : canonicalIndex;
  }

  scrollChapterListToCurrent(): void {
    setTimeout(() => {
      if (!this.showChapterList || this.chapters.length === 0) return;
      try {
        this.chapterScroller.scrollToIndex(
          this.chapterDisplayIndex(this.chapterIndex), false, ScrollAlign.CENTER);
      } catch (_) {}
    }, 0);
  }

  closeChapterList(): void {
    animateTo({ duration: 210, curve: Curve.EaseIn }, () => {
      this.showChapterList = false;
    });
  }

  async selectChapter(index: number): Promise<void> {
    if (index < 0 || index >= this.chapters.length || index === this.chapterIndex) {
      this.closeChapterList();
      return;
    }
    // 上一章还在取地址或缓冲时也允许直接改选：playCurrentChapter 让旧加载失效并取消它的书源请求。
    // 以前这里会锁住切章，慢书源上点了没反应，只能等它加载完或超时。
    // saveProgressNow 在第一个 await 之前就记下了当前章节和进度，所以可以先发出再改 chapterIndex。
    const savePrevious = this.saveProgressNow(true);
    this.chapterIndex = index;
    this.positionMs = 0;
    this.durationMs = 0;
    this.latestPositionMs = 0;
    this.latestDurationMs = 0;
    this.closeChapterList();
    await Promise.all([savePrevious, this.playCurrentChapter(0)]);
  }

  handleMediaChapterCommand(offset: number): void {
    const now = Date.now();
    if (now - this.lastMediaChapterCommandAt < 1000) return;
    this.lastMediaChapterCommandAt = now;
    this.changeChapter(offset).catch((error: Error) => {
      console.warn('处理锁屏切章命令失败:', error);
    });
  }

  onPlaybackStateChanged(state: string): void {
    this.playbackState = state;
    this.statusText = this.stateLabel(state);
    this.syncFloatingStatus();
    if (state === 'playing') {
      this.publishFloatingSession();
      this.startAudioBackground().catch((error: Error) => {
        console.warn('启动听书后台播放失败:', error);
      });
    } else if (state === 'paused' || state === 'stopped') {
      this.updateFloatingSession();
      this.updateAudioAvSessionState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE).catch(() => {});
    } else if (state === 'loading' || state === 'initialized' || state === 'prepared') {
      this.updateAudioAvSessionState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING).catch(() => {});
    } else if (state === 'completed') {
      this.updateAudioAvSessionState(avSession.PlaybackState.PLAYBACK_STATE_STOP).catch(() => {});
    } else if (state === 'error' || state === 'idle') {
      ReaderTtsFloatingSession.clear(this.floatingSessionOwnerId);
      // STOP only changes the visible playback state; it does not remove the session from
      // system media controls. An idle/error player has no background work left, so release
      // the shared AVSession completely and prevent stale audiobook metadata from surviving.
      this.stopAudioBackground().catch((error: Error) => {
        console.warn('清理已停止的听书媒体会话失败:', error);
      });
    }
  }

  onPlaybackPositionChanged(positionMs: number, durationMs: number): void {
    this.latestPositionMs = positionMs;
    this.latestDurationMs = durationMs;
    if (this.pageVisible) {
      this.positionMs = positionMs;
      this.durationMs = durationMs;
    }
    this.scheduleProgressSave();
    const now = Date.now();
    if (now - this.lastFloatingPositionUpdateAt >= 1000) {
      this.lastFloatingPositionUpdateAt = now;
      this.updateFloatingSession();
    }
    if (now - this.lastAvSessionPositionUpdateAt >= 5000) {
      this.lastAvSessionPositionUpdateAt = now;
      this.updateAudioAvSessionState(this.isPlaying() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE).catch(() => {});
    }
  }

  onPlaybackCompleted(): void {
    this.saveProgressNow(true);
    if (this.chapterIndex < this.chapters.length - 1) {
      this.selectChapter(this.chapterIndex + 1);
    } else {
      this.statusText = '已播放完全部章节';
      ReaderTtsFloatingSession.clear(this.floatingSessionOwnerId);
      this.stopAudioBackground().catch(() => {});
    }
  }

  onPlaybackError(message: string): void {
    if (this.playbackRetryCount < 1 && this.book && this.currentChapter()) {
      this.playbackRetryCount++;
      this.playCurrentChapter(this.latestPositionMs, true);
      return;
    }
    this.playbackState = 'error';
    this.statusText = `播放失败：${message}`;
    this.syncFloatingStatus();
    HdsFeedback.showToast(this.statusText);
  }

  changeSpeed(value: number): void {
    this.speed = value;
    this.playback.setSpeed(value);
    if (this.book) {
      this.book.putVariable('audioSpeed', String(value));
      this.queueBookStateSave(this.book).catch((error: Error) => {
        console.warn('保存听书倍速失败:', error);
      });
    }
    this.updateFloatingSession();
  }

  setSleepTimer(minutes: number): void {
    this.clearSleepTimer();
    this.sleepMinutes = minutes;
    this.playback.setSleepTimer(minutes);
    this.sleepRemainingSeconds = this.playback.sleepRemainingSeconds();
    this.updateFloatingSession();
    if (minutes <= 0) return;
    this.startSleepTimerUi();
  }

  startSleepTimerUi(): void {
    this.sleepTimerId = setInterval(() => {
      this.sleepRemainingSeconds = this.playback.sleepRemainingSeconds();
      if (this.sleepRemainingSeconds <= 0) {
        this.clearSleepTimer();
        this.sleepMinutes = 0;
        HdsFeedback.showToast('定时停止已生效');
      }
    }, 1000);
  }

  restoreSleepTimerUi(): void {
    const remaining = this.playback.sleepRemainingSeconds();
    if (remaining <= 0) return;
    this.sleepRemainingSeconds = remaining;
    this.sleepMinutes = Math.max(1, Math.ceil(remaining / 60));
    this.clearSleepTimer();
    this.sleepRemainingSeconds = remaining;
    this.startSleepTimerUi();
  }

  async closePage(): Promise<void> {
    await this.saveProgressNow(true);
    const keepPlaying = this.playback.matches(this.bookUrl, this.chapterIndex) &&
      this.playback.state !== 'idle' && this.playback.state !== 'error' && this.playback.state !== 'completed';
    if (keepPlaying) {
      this.publishFloatingSession();
    } else {
      await this.stopAudioPlayback();
    }
    if (this.openedWithShelfAnimation) {
      AppStorage.setOrCreate('shelfBookCloseAnimationUrl', this.bookUrl);
      AppStorage.setOrCreate('shelfBookCloseAnimationNonce', Date.now());
    }
    try {
      if (this.openedFromShortcut && this.shortcutReplacedPreviousPage) {
        await router.replaceUrl({ url: 'pages/Index' });
      } else {
        router.back();
      }
    } catch (error) {
      console.error('退出听书页失败:', error);
    }
  }

  async stopAudioPlayback(): Promise<void> {
    if (this.stopPlaybackPromise) {
      await this.stopPlaybackPromise;
      return;
    }
    const task = this.performStopAudioPlayback();
    this.stopPlaybackPromise = task;
    try {
      await task;
    } finally {
      this.stopPlaybackPromise = null;
    }
  }

  private async performStopAudioPlayback(): Promise<void> {
    this.loadingSerial++;
    await this.playback.stop();
    await this.stopAudioBackground();
    ReaderTtsFloatingSession.clear(this.floatingSessionOwnerId);
    this.playbackState = 'idle';
    this.statusText = '已停止听书';
  }

  async openVoiceDialog(): Promise<void> {
    this.voiceCodeInput = this.book?.getVariable('custom') || '';
    await this.refreshVoiceSource();
    this.openVoiceCodeDialog();
  }

  async refreshVoiceSource(): Promise<void> {
    // 听书会话可能在书源更新之前就已经打开（后台一直在播），这里重新读一次书源，
    // 否则拿到的还是旧定义，看不到新声明的音色列表。
    try {
      const origin = this.book?.origin || '';
      const latest = origin ? await AppDatabase.getInstance().getBookSource(origin) : null;
      if (latest && this.book?.origin === origin) {
        this.source = latest;
        this.refreshVoiceOptions();
        this.publishVoiceChoices();
      }
    } catch (e) {
      console.warn('刷新书源失败:', e);
    }
  }

  sourceVoices(): NativeVoiceOption[] {
    return NativeSourceService.voices(this.source);
  }

  /** 音色列表，最前面加一项「默认」（不指定音色）。 */
  voiceChoices(): NativeVoiceOption[] {
    const choices: NativeVoiceOption[] = [{ id: '', name: '默认' }];
    const voices = choices.concat(this.sourceVoices());
    if (this.audioVoiceCode && !voices.some((voice: NativeVoiceOption): boolean => voice.id === this.audioVoiceCode)) {
      voices.push({ id: this.audioVoiceCode, name: this.audioVoiceCode });
    }
    return voices;
  }

  currentVoiceIndex(): number {
    return Math.max(0, this.voiceChoices().findIndex((voice: NativeVoiceOption): boolean =>
      voice.id === this.audioVoiceCode));
  }

  selectVoice(index: number): void {
    const voice = this.voiceChoices()[index];
    if (!voice || voice.id === this.audioVoiceCode) return;
    this.voiceCodeInput = voice.id;
    this.saveVoiceCode().catch((error: Error) => {
      console.warn('切换听书音色失败:', error);
      HdsFeedback.showToast('切换音色失败，请重试');
    });
  }

  publishVoiceChoices(): void {
    ReaderTtsFloatingSession.configureTtsVoices(
      this.floatingSessionOwnerId,
      this.voiceChoices().map((voice: NativeVoiceOption): string => voice.name),
      this.currentVoiceIndex(),
      (index: number) => this.selectVoice(index)
    );
  }

  refreshVoiceOptions(): void {
    const titles = this.voiceChoices().map((voice: NativeVoiceOption): string => voice.name);
    // 与 TTS 一样，仅在音色变化时更新选项，播放进度刷新不向 Select 反复传入新数组。
    if (titles.length !== this.audioVoiceTitles.length ||
      titles.some((title: string, index: number): boolean => title !== this.audioVoiceTitles[index])) {
      this.audioVoiceTitles = titles;
    }
    this.audioVoiceIndex = this.currentVoiceIndex();
  }

  currentVoiceCode(): string {
    const code = this.book?.getVariable('custom') || '';
    if (!code) return '默认';
    const voice = this.sourceVoices().find((item: NativeVoiceOption): boolean => item.id === code);
    return voice ? voice.name : code;
  }

  displayIntro(): string {
    const value = this.book?.customIntro || this.book?.intro || '暂无书籍简介';
    return value.replace(/&lrm;|&nbsp;/gi, '').replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').trim();
  }

  applyPendingPanelAction(): void {
    const action = this.pendingPanelAction;
    this.pendingPanelAction = '';
    if (action === 'voice') this.openVoiceDialog();
  }

  publishFloatingSession(): void {
    const book = this.book;
    if (!book || !this.floatingSessionOwnerId || !this.playback.mediaUrl) return;
    ReaderTtsFloatingSession.attach(
      this.floatingSessionOwnerId,
      book.bookUrl,
      book.name || '正在听书',
      this.currentChapter()?.title || '',
      !this.isPlaying(),
      () => this.togglePlayback(),
      () => !this.isPlaying(),
      () => this.stopAudioPlayback()
    );
    ReaderTtsFloatingSession.configureControls(
      this.floatingSessionOwnerId,
      () => { this.handleMediaChapterCommand(-1); },
      () => { this.handleMediaChapterCommand(1); },
      (value: number) => this.changeSpeed(value),
      (minutes: number) => this.setSleepTimer(minutes)
    );
    ReaderTtsFloatingSession.configureAudioControls(
      this.floatingSessionOwnerId,
      this.currentVoiceCode(),
      () => this.openFloatingPanel('voice'),
      (positionMs: number) => {
        const target = Math.max(0, Math.min(positionMs, this.latestDurationMs || positionMs));
        this.latestPositionMs = target;
        if (this.pageVisible) this.positionMs = target;
        this.playback.seek(target);
        this.scheduleProgressSave();
      }
    );
    this.publishVoiceChoices();
    ReaderTtsFloatingSession.configureCatalog(
      this.floatingSessionOwnerId,
      this.chapters.map((chapter: BookChapter) => chapter.title),
      this.chapterIndex,
      (index: number) => {
        this.selectChapter(index).catch((error: Error) => console.warn('听书目录跳转失败:', error));
      },
      this.chapterCachedFlags()
    );
    this.updateFloatingSession();
  }

  updateFloatingSession(): void {
    if (!ReaderTtsFloatingSession.isOwner(this.floatingSessionOwnerId) || !this.book) return;
    ReaderTtsFloatingSession.update(
      this.floatingSessionOwnerId,
      this.book.name || '正在听书',
      this.currentChapter()?.title || '',
      !this.isPlaying()
    );
    ReaderTtsFloatingSession.updateDetails(
      this.floatingSessionOwnerId,
      this.displayIntro(), '', '', '', this.panelCover(),
      this.shouldUseThemeBookCover() ? this.activeThemeShelfFrame() : '',
      `${this.chapterIndex + 1}/${Math.max(1, this.chapters.length)}章`,
      this.speed, this.sleepMinutes, this.sleepRemainingSeconds,
      this.chapterIndex > 0, this.chapterIndex < this.chapters.length - 1
    );
    ReaderTtsFloatingSession.updateAudioProgress(
      this.floatingSessionOwnerId, this.latestPositionMs, this.latestDurationMs);
    ReaderTtsFloatingSession.updateCatalogIndex(this.floatingSessionOwnerId, this.chapterIndex);
    this.syncFloatingStatus();
  }

  /** 读书籍目录、取音频地址、播放器缓冲都算加载中。 */
  isPanelBusy(): boolean {
    return this.openingBook || this.playbackState === 'loading' || this.playbackState === 'initialized' ||
      this.playbackState === 'prepared';
  }

  /** 播放面板上的提示：加载中显示进行到哪一步，失败时显示原因，正常播放或暂停时不显示。 */
  panelStatusText(): string {
    return this.isPanelBusy() || this.playbackState === 'error' ? this.statusText : '';
  }

  /** 共享会话已发布时（如切章缓冲），书架上的播放面板和胶囊也显示同样的加载状态。 */
  syncFloatingStatus(): void {
    ReaderTtsFloatingSession.updateStatus(this.floatingSessionOwnerId, this.panelStatusText(), this.isPanelBusy());
  }

  openFloatingPanel(action: string): void {
    router.pushUrl({
      url: 'pages/AudioBook',
      params: { bookUrl: this.bookUrl, audioPanelAction: action }
    }).catch((error: Error) => console.warn('打开听书设置面板失败:', error));
  }

  scheduleProgressSave(): void {
    if (this.progressSaveTimerId >= 0) return;
    this.progressSaveTimerId = setTimeout(() => {
      this.progressSaveTimerId = -1;
      this.saveProgressNow();
    }, 5000);
  }

  async saveProgressNow(notifyShelf: boolean = false): Promise<void> {
    const book = this.book;
    const chapter = this.currentChapter();
    if (!book || !chapter) return;
    const chapterIndex = this.chapterIndex;
    const chapterPosition = Math.max(0, Math.floor(this.latestPositionMs || this.positionMs));
    const chapterTitle = chapter.title;
    const chapterTime = Date.now();
    book.durChapterIndex = chapterIndex;
    book.durChapterPos = chapterPosition;
    book.durChapterTitle = chapterTitle;
    book.durChapterTime = chapterTime;
    book.putVariable('readStarted', '1');
    book.putVariable('lastReadTime', String(chapterTime));
    const bookUrl = book.bookUrl;
    const variable = book.variable;
    const syncRelevant = !!book.origin && book.origin !== 'local';
    const previous = this.progressSaveQueue.catch(() => {});
    const next = previous.then(async () => {
      await AppDatabase.getInstance().updateBookReadingProgress(
        bookUrl, chapterTitle, chapterIndex, chapterPosition, chapterTime, variable,
        syncRelevant && notifyShelf);
      if (notifyShelf) AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    });
    this.progressSaveQueue = next;
    try {
      await next;
    } catch (error) {
      console.warn('保存听书进度失败:', error);
    }
  }

  queueBookStateSave(book: Book): Promise<void> {
    const previous = this.progressSaveQueue.catch(() => {});
    const next = previous.then(async () => {
      await AppDatabase.getInstance().updateBook(book, false);
    });
    this.progressSaveQueue = next;
    return next;
  }

  resolveAudioUrl(raw: string, baseUrl: string = ''): string {
    let value = String(raw || '').trim();
    if (!value) return '';
    if (value.startsWith('"') && value.endsWith('"')) {
      try { value = String(JSON.parse(value)); } catch (_) {}
    }
    value = this.decodeAudioRuleValue(value);
    try {
      const parsed = JSON.parse(value) as Record<string, Object>;
      const candidate = this.audioUrlFromObject(parsed, baseUrl);
      if (candidate) return candidate;
    } catch (_) {}

    const tagMatch = value.match(/<(?:audio|source)\b[^>]*\b(?:src|data-src|data-url)\s*=\s*["']([^"']+)["'][^>]*>/i) ||
      value.match(/<(?:audio|source)\b[^>]*\b(?:src|data-src|data-url)\s*=\s*([^\s>]+)[^>]*>/i);
    if (tagMatch && tagMatch[1]) {
      const taggedUrl = this.normalizeAudioCandidate(tagMatch[1], baseUrl, true);
      if (taggedUrl) return taggedUrl;
    }

    const fieldMatch = value.match(/["']?(?:audio_url|audioUrl|play_url|playUrl|playurl|listenUrl|streamUrl|mediaUrl|src|file|path|url)["']?\s*[:=]\s*["']([^"']+)["']/i);
    if (fieldMatch && fieldMatch[1]) {
      const fieldUrl = this.normalizeAudioCandidate(fieldMatch[1], baseUrl, true);
      if (fieldUrl) return fieldUrl;
    }

    // HTML/JS chapter pages often contain covers, analytics and API links before the player.
    // Prefer a media-looking address so a generic first URL cannot mask the actual stream.
    const mediaMatch = value.match(/(?:https?:)?\/\/[^\s"'<>\\]+?\.(?:aac|flac|m3u8|m4a|mp3|mp4|ogg|opus|wav)(?:\?[^\s"'<>\\]*)?/i);
    if (mediaMatch) {
      const mediaUrl = this.normalizeAudioCandidate(mediaMatch[0], baseUrl, true);
      if (mediaUrl) return mediaUrl;
    }

    const absoluteMatch = value.match(/https?:\/\/[^\s"'<>]+/i);
    if (absoluteMatch) {
      const absoluteUrl = this.normalizeAudioCandidate(absoluteMatch[0], baseUrl, true);
      if (absoluteUrl) return absoluteUrl;
    }
    const protocolRelativeMatch = value.match(/\/\/[A-Za-z0-9.-]+(?::\d+)?\/[^\s"'<>]*/);
    if (protocolRelativeMatch) {
      const protocolRelativeUrl = this.normalizeAudioCandidate(protocolRelativeMatch[0], baseUrl, true);
      if (protocolRelativeUrl) return protocolRelativeUrl;
    }
    return this.normalizeAudioCandidate(value, baseUrl, false);
  }

  audioUrlFromObject(value: Record<string, Object>, baseUrl: string): string {
    const keys = ['audio_url', 'audioUrl', 'play_url', 'playUrl', 'playurl', 'main_url', 'mainUrl',
      'listenUrl', 'downloadUrl', 'streamUrl', 'mediaUrl', 'backup_url', 'backupUrl', 'src', 'file', 'path',
      'url', 'url_list', 'urlList', 'backup_urls', 'backupUrls', 'audio_list', 'audioList', 'play_info',
      'playInfo', 'decodedContent', 'content', 'data', 'result', 'payload', 'audio', 'media'];
    for (const key of keys) {
      const item = value[key];
      if (typeof item === 'string') {
        const candidate = this.resolveAudioUrl(item, baseUrl);
        if (candidate) return candidate;
      } else if (item && typeof item === 'object' && !Array.isArray(item)) {
        const nested = this.audioUrlFromObject(item as Record<string, Object>, baseUrl);
        if (nested) return nested;
      } else if (Array.isArray(item)) {
        for (const entry of item as Object[]) {
          if (typeof entry === 'string') {
            const candidate = this.resolveAudioUrl(entry, baseUrl);
            if (candidate) return candidate;
          }
          if (entry && typeof entry === 'object') {
            const nested = this.audioUrlFromObject(entry as Record<string, Object>, baseUrl);
            if (nested) return nested;
          }
        }
      }
    }
    return '';
  }

  invalidAudioAddressMessage(raw: string): string {
    // 取正文失败时内容为空，原因记在书源阶段错误里（例如接口返回的 code/message、书源给的说明）。
    if (!(raw || '').trim()) {
      const stageError = (AppStorage.get<string>('bookSourceStageLastError') || '').trim();
      if (stageError) return stageError;
    }
    try {
      const root = JSON.parse(raw || '{}') as Record<string, Object>;
      let data: Record<string, Object> = root;
      if (root['data'] && typeof root['data'] === 'object' && !Array.isArray(root['data'])) {
        data = root['data'] as Record<string, Object>;
      }
      const message = String(root['error'] || root['message'] || root['msg'] ||
        data['error'] || data['message'] || data['msg'] || '').trim();
      if (message) return `音频接口未返回可播放地址：${message}`;
    } catch (_) {}
    return '正文规则没有返回有效音频地址';
  }

  decodeAudioRuleValue(raw: string): string {
    return String(raw || '').trim()
      .replace(/&amp;/gi, '&')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;|&apos;/gi, "'")
      .replace(/\\u002[fF]|\\x2[fF]/g, '/')
      .replace(/\\u003[aA]|\\x3[aA]/g, ':')
      .replace(/\\u0026|\\x26/gi, '&')
      .replace(/\\u003[dD]|\\x3[dD]/g, '=')
      .replace(/\\\//g, '/');
  }

  normalizeAudioCandidate(raw: string, baseUrl: string, trustPlainValue: boolean): string {
    let value = this.decodeAudioRuleValue(raw)
      .replace(/^url\(\s*|\s*\)$/gi, '')
      .replace(/^["']|["']$/g, '')
      .trim();
    value = value.replace(/,\s*\{[\s\S]*$/, '').replace(/[),.;\]}]+$/, '');
    if (!value || /\s/.test(value) || /^(?:javascript:|data:|about:|#)/i.test(value)) return '';

    const isExplicitUrl = /^(?:https?:)?\/\//i.test(value) || /^\.?\.?\//.test(value);
    const isLikelyMediaPath = /\.(?:aac|flac|m3u8|m4a|mp3|mp4|ogg|opus|wav)(?:[?#].*)?$/i.test(value);
    const isLikelyRelativeEndpoint = /^[A-Za-z0-9._~-]+(?:\/|\?)[^\s<>{}\[\]"']+$/.test(value);
    if (!isExplicitUrl && !isLikelyMediaPath && !isLikelyRelativeEndpoint && !trustPlainValue) return '';
    const resolved = BookUrlResolver.resolve(value, baseUrl);
    return /^https?:\/\//i.test(resolved) ? resolved : '';
  }

  /**
   * Source headers follow the stream only within the source's own site; headers the rule attached
   * to the address itself (`url,{"headers":{...}}`) are the author's explicit choice and win.
   */
  audioHeaders(url: string, source: BookSource | null, ruleValue: string = ''): Record<string, string> {
    const explicit = AudioRuleSupport.splitRequestOptions(this.decodeAudioRuleValue(ruleValue)).headers;
    let headers = this.sourceAudioHeaders(source);
    if (source) {
      headers = AudioRuleSupport.scopeHeadersToMediaHost(headers, source.bookSourceUrl, url);
      // The cookie jar is already scoped to the media address, so it applies on any host.
      const cookie = VerificationSupport.sourceCookieHeader(source, url);
      if (cookie) headers = AudioRuleSupport.mergeHeaders(headers, { 'Cookie': cookie });
    }
    return AudioRuleSupport.mergeHeaders(headers, explicit);
  }

  private sourceAudioHeaders(source: BookSource | null): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36'
    };
    if (!source) return headers;
    const rawHeader = source.header || '';
    try {
      const parsed = JSON.parse(rawHeader.replace(/'/g, '"')) as Record<string, string>;
      for (const key of Object.keys(parsed)) {
        const value = String(parsed[key] || '');
        if (key && value && !value.includes('java.')) headers[key] = value;
      }
    } catch (_) {
      const regex = /["']([A-Za-z0-9_-]+)["']\s*:\s*["']([^"']+)["']/g;
      let match: RegExpExecArray | null;
      while ((match = regex.exec(rawHeader)) !== null) {
        const key = match[1] || '';
        const value = match[2] || '';
        if (key && value && !value.includes('java.')) headers[key] = value;
      }
    }
    return headers;
  }

  currentChapter(): BookChapter | null {
    return this.chapterIndex >= 0 && this.chapterIndex < this.chapters.length ? this.chapters[this.chapterIndex] : null;
  }

  clampChapterIndex(index: number): number {
    if (this.chapters.length === 0) return 0;
    return Math.max(0, Math.min(index || 0, this.chapters.length - 1));
  }

  isPlaying(): boolean {
    return this.playbackState === 'playing';
  }

  savedSpeed(book: Book): number {
    const value = Number(book.getVariable('audioSpeed') || 1);
    return Number.isFinite(value) ? Math.max(0.5, Math.min(2.5, value)) : 1;
  }

  displayCover(): ResourceStr {
    const raw = BookCoverResolver.first(this.book, this.appDarkMode);
    return typeof raw === 'string' && this.sourceCoverRevision >= 0 ? BookCoverCache.displayCover(getContext(this), raw) : raw;
  }

  onThemeBookCoverChanged(): void {
    this.updateFloatingSession();
  }

  shouldUseThemeBookCover(): boolean {
    return ThemeBookCoverSettings.enabled(this.appDarkMode, this.themeBookCoverEnabled);
  }

  panelCover(): ResourceStr {
    return this.displayCover();
  }

  activeThemeShelfFrame(): ResourceStr {
    return ThemeBookCoverSettings.frame(this.appDarkMode);
  }

  formatDuration(valueMs: number): string {
    const totalSeconds = Math.max(0, Math.floor((valueMs || 0) / 1000));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    const mm = minutes.toString().padStart(2, '0');
    const ss = seconds.toString().padStart(2, '0');
    return hours > 0 ? `${hours}:${mm}:${ss}` : `${minutes}:${ss}`;
  }

  stateLabel(state: string): string {
    if (state === 'playing') return '正在播放';
    if (state === 'paused' || state === 'stopped') return '已暂停';
    if (state === 'loading' || state === 'initialized' || state === 'prepared') return '正在缓冲音频…';
    if (state === 'completed') return '本章播放完成';
    if (state === 'error') return '播放失败，可点击播放重试';
    return '准备播放';
  }

  errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || String(error);
    return String(error || '未知错误');
  }

  async startAudioBackground(): Promise<void> {
    this.audioBackgroundDesired = true;
    if (this.audioBackgroundRunning) {
      await this.updateAudioAvSessionState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
      this.startAudioBackgroundHeartbeat();
      return;
    }
    if (this.audioBackgroundStarting) return;
    this.audioBackgroundStarting = true;
    try {
      const agent = await this.createAudioWantAgent();
      await this.startAudioAvSession(agent);
      await backgroundTaskManager.startBackgroundRunning(getContext(this), ['audioPlayback'], agent);
      if (this.audioBackgroundDesired) {
        this.audioBackgroundRunning = true;
        this.startAudioBackgroundHeartbeat();
      } else {
        await this.releaseAudioAvSession();
        await backgroundTaskManager.stopBackgroundRunning(getContext(this));
      }
    } catch (error) {
      console.warn('申请听书后台任务失败:', error);
    } finally {
      this.audioBackgroundStarting = false;
    }
  }

  async stopAudioBackground(): Promise<void> {
    this.audioBackgroundDesired = false;
    this.stopAudioBackgroundHeartbeat();
    await this.releaseAudioAvSession();
    if (!this.audioBackgroundRunning && !this.audioBackgroundStarting) return;
    this.audioBackgroundRunning = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(getContext(this));
    } catch (error) {
      console.warn('停止听书后台任务失败:', error);
    }
  }

  startAudioBackgroundHeartbeat(): void {
    if (this.audioBackgroundHeartbeatId >= 0) return;
    this.audioBackgroundHeartbeatId = setInterval((): void => {
      this.keepAudioBackgroundAlive().catch((error: Error) => {
        console.warn('听书后台播放保活失败:', error);
      });
    }, 30000);
  }

  stopAudioBackgroundHeartbeat(): void {
    if (this.audioBackgroundHeartbeatId < 0) return;
    clearInterval(this.audioBackgroundHeartbeatId);
    this.audioBackgroundHeartbeatId = -1;
  }

  async keepAudioBackgroundAlive(): Promise<void> {
    const state = this.playback.state;
    if (!this.audioBackgroundDesired || !this.playback.mediaUrl || state === 'idle' || state === 'error') {
      this.stopAudioBackgroundHeartbeat();
      return;
    }
    if (!this.audioBackgroundRunning && !this.audioBackgroundStarting) {
      await this.startAudioBackground();
      return;
    }
    if (!this.audioAvSession) {
      const agent = await this.createAudioWantAgent();
      await this.startAudioAvSession(agent);
    }
    await this.updateAudioAvSessionState(state === 'playing' ?
      avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
  }

  async releaseAudioAvSession(): Promise<void> {
    const session = this.audioAvSession || AudioBookAvSessionHolder.session;
    this.audioAvSession = null;
    if (AudioBookAvSessionHolder.session === session) {
      AudioBookAvSessionHolder.session = null;
    }
    if (session) {
      this.unregisterAudioAvSessionCommands(session);
      try {
        await session.setAVPlaybackState({ state: avSession.PlaybackState.PLAYBACK_STATE_STOP });
      } catch (error) {
        console.warn('标记听书媒体会话停止失败:', error);
      }
      try {
        await session.deactivate();
      } catch (error) {
        console.warn('停用听书媒体会话失败:', error);
      }
      try {
        await session.destroy();
      } catch (error) {
        console.warn('销毁听书媒体会话失败:', error);
      }
    }
  }

  async startAudioAvSession(agent: WantAgent): Promise<void> {
    if (this.audioAvSessionStarting) return;
    this.audioAvSessionStarting = true;
    try {
      if (!this.audioAvSession && AudioBookAvSessionHolder.session) {
        this.audioAvSession = AudioBookAvSessionHolder.session;
        // The shared session may still hold callbacks closed over an older page.
        // Remove them before registering the currently visible controller.
        this.unregisterAudioAvSessionCommands(this.audioAvSession);
        this.registerAudioAvSessionCommands(this.audioAvSession);
      }
      if (!this.audioAvSession) {
        this.audioAvSession = await avSession.createAVSession(getContext(this), 'LegadoAudioBook', 'audio');
        AudioBookAvSessionHolder.session = this.audioAvSession;
        this.registerAudioAvSessionCommands(this.audioAvSession);
      }
      await this.audioAvSession.setLaunchAbility(agent);
      await this.audioAvSession.setAVQueueTitle(this.book?.name || '听书');
      await this.audioAvSession.setAVMetadata(await this.audioAvMetadata());
      await this.audioAvSession.setExtras({
        bookUrl: this.bookUrl,
        chapterIndex: this.chapterIndex,
        chapterTitle: this.currentChapter()?.title || ''
      });
      await this.updateAudioAvSessionState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
      await this.audioAvSession.activate();
    } finally {
      this.audioAvSessionStarting = false;
    }
  }

  registerAudioAvSessionCommands(session: avSession.AVSession): void {
    session.on('play', (): void => {
      this.playback.resume().catch((error: Error) => {
        this.onPlaybackError(this.errorMessage(error));
      });
    });
    session.on('pause', (): void => {
      this.playback.pause().catch(() => {});
    });
    session.on('stop', (): void => {
      this.playback.stop().then(() => this.stopAudioBackground()).catch(() => {});
    });
    session.on('playNext', (): void => {
      this.handleMediaChapterCommand(1);
    });
    session.on('playPrevious', (): void => {
      this.handleMediaChapterCommand(-1);
    });
    session.on('seek', (time: number): void => {
      this.playback.seek(time);
    });
    session.on('setSpeed', (speed: number): void => {
      this.changeSpeed(speed);
    });
  }

  unregisterAudioAvSessionCommands(session: avSession.AVSession): void {
    try { session.off('play'); } catch (_) {}
    try { session.off('pause'); } catch (_) {}
    try { session.off('stop'); } catch (_) {}
    try { session.off('playNext'); } catch (_) {}
    try { session.off('playPrevious'); } catch (_) {}
    try { session.off('seek'); } catch (_) {}
    try { session.off('setSpeed'); } catch (_) {}
  }

  async updateAudioAvSessionState(state: avSession.PlaybackState): Promise<void> {
    const session = this.audioAvSession;
    if (!session) return;
    try {
      await session.setAVMetadata(await this.audioAvMetadata());
      await session.setAVPlaybackState({
        state: state,
        speed: this.speed,
        position: { elapsedTime: this.latestPositionMs, updateTime: Date.now() },
        bufferedTime: this.latestDurationMs,
        loopMode: avSession.LoopMode.LOOP_MODE_SEQUENCE,
        activeItemId: this.chapterIndex
      });
      if (state === avSession.PlaybackState.PLAYBACK_STATE_PLAY ||
        state === avSession.PlaybackState.PLAYBACK_STATE_BUFFERING) await session.activate();
    } catch (error) {
      console.warn('更新听书媒体控制状态失败:', error);
    }
  }

  async audioAvMetadata(): Promise<avSession.AVMetadata> {
    const chapter = this.currentChapter();
    const metadata: avSession.AVMetadata = {
      assetId: `${this.bookUrl}_${this.chapterIndex}`,
      title: chapter?.title || this.book?.name || '听书',
      subtitle: this.book?.name || '',
      artist: this.book?.author || this.book?.originName || '听书',
      author: this.book?.author || '',
      album: this.book?.name || '听书',
      duration: this.latestDurationMs,
      previousAssetId: this.chapterIndex > 0 ? `${this.bookUrl}_${this.chapterIndex - 1}` : '',
      nextAssetId: this.chapterIndex < this.chapters.length - 1 ? `${this.bookUrl}_${this.chapterIndex + 1}` : '',
      avQueueName: this.book?.name || '听书',
      avQueueId: this.bookUrl || 'audio_book'
    };
    const cover = BookCoverResolver.first(this.book, this.appDarkMode);
    try {
      // 网络封面沿用系统异步加载，不能让图片下载阻塞媒体会话激活。
      const image = typeof cover === 'string' ? BookCoverCache.displayCover(getContext(this), cover) :
        await BookCoverResolver.prepareFile(getContext(this), cover);
      if (image) {
        const uri = image.startsWith('/') ? fileUri.getUriFromPath(image) : image;
        metadata.mediaImage = uri;
        metadata.avQueueImage = uri;
      }
    } catch (error) {
      console.warn('读取听书媒体封面失败:', error);
    }
    return metadata;
  }

  async createAudioWantAgent(): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          audioBookAction: 'openPanel',
          bookUrl: this.bookUrl
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1101,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  clearProgressSaveTimer(): void {
    if (this.progressSaveTimerId >= 0) clearTimeout(this.progressSaveTimerId);
    this.progressSaveTimerId = -1;
  }

  clearSleepTimer(): void {
    if (this.sleepTimerId >= 0) clearInterval(this.sleepTimerId);
    this.sleepTimerId = -1;
    this.sleepRemainingSeconds = 0;
  }

  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  inputColor(): string { return ThemeRuntime.inputColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  secondaryTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }

  bookInitial(): string {
    const name = (this.book?.name || '书').trim();
    return name.length > 0 ? name.substring(0, 1) : '书';
  }

  /** Mirrors the reader catalog's "已缓存" chip; local books have no remote cache state. */
  isChapterCached(canonicalIndex: number): boolean {
    if (!this.book || this.book.origin === 'local') return false;
    if (canonicalIndex < 0 || canonicalIndex >= this.chapters.length) return false;
    return this.chapters[canonicalIndex].cacheDate > 0;
  }

  chapterCachedFlags(): boolean[] {
    const flags: boolean[] = [];
    for (let index = 0; index < this.chapters.length; index++) {
      flags.push(this.isChapterCached(index));
    }
    return flags;
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
