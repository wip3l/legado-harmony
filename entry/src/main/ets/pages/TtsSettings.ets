import { router, promptAction } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemTtsReader, TtsVoiceOption } from '../utils/SystemTtsReader';

@Entry
@Component
struct TtsSettingsPage {
  @StorageLink('ttsPerson') ttsPerson: number = 0;
  @StorageLink('ttsOnline') ttsOnline: number = 1;
  @StorageLink('ttsStyle') ttsStyle: string = '';
  @StorageLink('ttsLanguage') ttsLanguage: string = 'zh-CN';
  @StorageLink('ttsSpeed') ttsSpeed: number = 1;
  @StorageLink('ttsInstalledVoiceKeys') ttsInstalledVoiceKeys: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State voices: TtsVoiceOption[] = [TtsSettingsPage.defaultVoice()];
  @State selectedVoiceKey: string = '';
  private previewText: string = '这是一段朗读试听文字。点击试听后，会按照当前音色和倍速播放。';
  private previewReader: SystemTtsReader = new SystemTtsReader();
  @State isPreviewing: boolean = false;
  @State isLoadingVoices: boolean = false;
  @State downloadingVoiceKey: string = '';
  @State downloadProgressText: string = '';

  aboutToAppear(): void {
    this.syncBars();
    this.normalizeDefaultOnlineVoice();
    this.selectedVoiceKey = this.currentVoiceKey();
    this.loadVoices();
  }

  onPageShow(): void {
    this.syncBars();
  }

  aboutToDisappear(): void {
    this.previewReader.shutdown();
    this.isPreviewing = false;
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('朗读音色')
          Column({ space: 8 }) {
            ForEach(this.voices, (voice: TtsVoiceOption) => {
              this.voiceRow(voice)
            }, (voice: TtsVoiceOption) => this.voiceKey(voice))
            if (this.isLoadingVoices) {
              Text('正在加载系统音色...')
                .fontSize(12)
                .fontColor(this.subTextColor())
                .width('100%')
                .padding({ top: 4, bottom: 4 })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(this.cardColor())

          this.sectionTitle('朗读倍速')
          Column() {
            Row() {
              Text('倍速')
                .fontSize(16)
                .fontColor(this.primaryTextColor())
                .layoutWeight(1)
              Text(`${this.ttsSpeed.toFixed(1)}x`)
                .fontSize(14)
                .fontColor(this.subTextColor())
            }
            .width('100%')

            Slider({ value: this.ttsSpeed, min: 0.5, max: 2, step: 0.1 })
              .width('100%')
              .margin({ top: 10 })
              .onChange((value: number) => {
                this.ttsSpeed = Math.round(value * 10) / 10;
              })

            Row({ space: 8 }) {
              this.speedChip(0.8)
              this.speedChip(1.0)
              this.speedChip(1.2)
              this.speedChip(1.5)
              this.speedChip(2.0)
            }
            .width('100%')
            .margin({ top: 10 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor(this.cardColor())

          this.sectionTitle('预览')
          Column({ space: 12 }) {
            Text(this.previewText)
              .fontSize(14)
              .lineHeight(22)
              .fontColor(this.subTextColor())
              .width('100%')

            Button(this.isPreviewing ? '停止试听' : '试听')
              .width('100%')
              .height(42)
              .onClick(() => {
                this.togglePreview();
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.cardColor())
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#888';
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  normalizeDefaultOnlineVoice(): void {
    if (this.ttsOnline === 0) {
      this.ttsOnline = 1;
    }
  }

  static defaultVoice(): TtsVoiceOption {
    const option = new TtsVoiceOption();
    option.id = 0;
    option.name = '默认音色';
    option.online = 1;
    option.status = 'default';
    option.language = 'zh-CN';
    return option;
  }

  async loadVoices(): Promise<void> {
    if (this.isLoadingVoices) {
      return;
    }
    this.isLoadingVoices = true;
    try {
      const voices = await SystemTtsReader.listAvailableVoices();
      this.voices = this.applyInstalledOverrides(this.mergeWithDefaultVoice(voices));
      const currentVoice = this.findCurrentVoice();
      if (!currentVoice || !currentVoice.available) {
        const defaultVoice = this.firstAvailableVoice();
        this.applyVoice(defaultVoice, false);
      } else {
        this.selectedVoiceKey = this.voiceKey(currentVoice);
      }
    } catch (_) {
      this.voices = [TtsSettingsPage.defaultVoice()];
      this.ttsPerson = 0;
      this.ttsOnline = 1;
      this.ttsStyle = '';
      this.ttsLanguage = 'zh-CN';
      this.selectedVoiceKey = this.currentVoiceKey();
    } finally {
      this.isLoadingVoices = false;
    }
  }

  mergeWithDefaultVoice(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [TtsSettingsPage.defaultVoice()];
    for (const voice of voices) {
      const existingIndex = options.findIndex((item: TtsVoiceOption) =>
        this.isSameVoiceOption(item, voice) || this.isSameDisplayVoice(item, voice));
      if (existingIndex < 0) {
        options.push(voice);
      } else if (this.shouldPreferVoiceOption(voice, options[existingIndex])) {
        options[existingIndex] = voice;
      }
    }
    return options;
  }

  isSameVoiceOption(left: TtsVoiceOption, right: TtsVoiceOption): boolean {
    if (left.id !== right.id || left.online !== right.online ||
      !this.sameLanguage(left.language || 'zh-CN', right.language || 'zh-CN')) {
      return false;
    }
    if (this.isKnownVoiceId(left.id)) {
      return true;
    }
    return (left.style || '') === (right.style || '');
  }

  isSameDisplayVoice(left: TtsVoiceOption, right: TtsVoiceOption): boolean {
    if (this.voiceTitle(left) === this.voiceTitle(right)) {
      return true;
    }
    return (left.name || '') === (right.name || '') && left.online === right.online &&
      this.sameLanguage(left.language || 'zh-CN', right.language || 'zh-CN');
  }

  shouldPreferVoiceOption(candidate: TtsVoiceOption, current: TtsVoiceOption): boolean {
    if (candidate.available !== current.available) {
      return candidate.available;
    }
    if (this.isKnownVoiceId(candidate.id) !== this.isKnownVoiceId(current.id)) {
      return this.isKnownVoiceId(candidate.id);
    }
    if (candidate.downloadable !== current.downloadable) {
      return candidate.downloadable;
    }
    return !current.style && !!candidate.style;
  }

  isKnownVoiceId(id: number): boolean {
    return id === 0 || id === 8 || id === 13 || id === 21;
  }

  firstAvailableVoice(): TtsVoiceOption {
    return this.voices.find((voice: TtsVoiceOption) => voice.available) || this.voices[0] ||
      TtsSettingsPage.defaultVoice();
  }

  async selectVoice(voice: TtsVoiceOption): Promise<void> {
    if (!voice.available) {
      if (voice.downloadable) {
        await this.downloadAndSelectVoice(voice);
      } else {
        promptAction.showToast({ message: '该系统音色当前不可用' });
      }
      return;
    }
    this.applyVoice(voice, true);
  }

  applyVoice(voice: TtsVoiceOption, stopPreview: boolean): void {
    if (stopPreview && this.isPreviewing) {
      this.previewReader.stop();
      this.isPreviewing = false;
    }
    this.ttsPerson = voice.id;
    this.ttsOnline = voice.online;
    this.ttsStyle = voice.style;
    this.ttsLanguage = voice.language;
    this.selectedVoiceKey = this.voiceKey(voice);
  }

  async downloadAndSelectVoice(voice: TtsVoiceOption): Promise<void> {
    if (this.downloadingVoiceKey) {
      promptAction.showToast({ message: '正在下载音色，请稍候' });
      return;
    }
    const key = this.voiceKey(voice);
    this.downloadingVoiceKey = key;
    this.downloadProgressText = '';
    try {
      promptAction.showToast({ message: `开始下载 ${voice.name}` });
      await SystemTtsReader.downloadVoice(voice, {
        onStart: (_message: string) => {
          this.downloadProgressText = '准备中';
        },
        onProgress: (progress: string) => {
          this.downloadProgressText = this.formatDownloadProgress(progress);
        }
      });
      this.markVoiceInstalled(voice);
      await this.loadVoices();
      let downloaded = this.findMatchingVoice(voice, true);
      if (!downloaded) {
        downloaded = this.markVoiceOptionInstalled(voice);
        this.voices = this.applyInstalledOverrides(this.mergeWithDefaultVoice(this.voices.concat([downloaded])));
      }
      this.applyVoice(downloaded, true);
      promptAction.showToast({ message: `已启用 ${downloaded.name}` });
    } catch (error) {
      promptAction.showToast({ message: `音色下载失败：${this.shortErrorMessage(error as Object)}` });
    } finally {
      this.downloadingVoiceKey = '';
      this.downloadProgressText = '';
    }
  }

  isVoiceSelected(voice: TtsVoiceOption): boolean {
    return this.isCurrentVoice(voice);
  }

  applyInstalledOverrides(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [];
    for (const voice of voices) {
      options.push(this.isLocallyInstalledVoice(voice) ? this.markVoiceOptionInstalled(voice) : voice);
    }
    return options;
  }

  markVoiceInstalled(voice: TtsVoiceOption): void {
    const key = this.installedVoiceKey(voice);
    if (!key || this.installedVoiceKeyExists(key)) {
      return;
    }
    this.ttsInstalledVoiceKeys = this.ttsInstalledVoiceKeys ?
      `${this.ttsInstalledVoiceKeys}\n${key}` : key;
  }

  isLocallyInstalledVoice(voice: TtsVoiceOption): boolean {
    return this.installedVoiceKeyExists(this.installedVoiceKey(voice));
  }

  installedVoiceKeyExists(key: string): boolean {
    if (!key) {
      return false;
    }
    const keys = this.ttsInstalledVoiceKeys.split('\n');
    return keys.includes(key);
  }

  installedVoiceKey(voice: TtsVoiceOption): string {
    const style = this.isKnownVoiceId(voice.id) ? '' : (voice.style || '');
    return `${voice.id}_${voice.online}_${this.normalizeLanguage(voice.language || 'zh-CN')}_${style}`;
  }

  markVoiceOptionInstalled(voice: TtsVoiceOption): TtsVoiceOption {
    const option = this.copyVoiceOption(voice);
    option.available = true;
    option.downloadable = false;
    option.status = 'INSTALLED';
    option.systemStatus = 'INSTALLED';
    return option;
  }

  copyVoiceOption(voice: TtsVoiceOption): TtsVoiceOption {
    const option = new TtsVoiceOption();
    option.id = voice.id;
    option.name = voice.name;
    option.online = voice.online;
    option.status = voice.status;
    option.systemStatus = voice.systemStatus;
    option.style = voice.style;
    option.language = voice.language;
    option.downloadLanguage = voice.downloadLanguage;
    option.gender = voice.gender;
    option.available = voice.available;
    option.downloadable = voice.downloadable;
    return option;
  }

  voiceTitle(voice: TtsVoiceOption): string {
    if (voice.status === 'default') {
      return `${voice.name} · 系统默认`;
    }
    if (this.isVoiceDownloading(voice)) {
      const progress = this.downloadProgressText ? ` · ${this.downloadProgressText}` : '';
      return `${voice.name} · 下载中${progress}`;
    }
    const suffix = voice.online === 0 ? '在线' : '离线';
    const gender = this.voiceGenderText(voice);
    const state = voice.available ? '' : (voice.downloadable ? ' · 需下载' : ' · 不可用');
    return `${voice.name} · ${suffix}${gender}${state}`;
  }

  voiceGenderText(voice: TtsVoiceOption): string {
    const value = (voice.gender || '').toLowerCase();
    if (value === 'male' || value === '男' || value === '男声') {
      return ' · 男声';
    }
    if (value === 'female' || value === '女' || value === '女声') {
      return ' · 女声';
    }
    return '';
  }

  voiceKey(voice: TtsVoiceOption): string {
    return `${voice.id}_${voice.online}_${voice.language || 'zh-CN'}_${voice.style || ''}_${voice.name || ''}`;
  }

  currentVoiceKey(): string {
    const matched = this.findCurrentVoice();
    return matched ? this.voiceKey(matched) :
      `${this.ttsPerson}_${this.ttsOnline}_${this.ttsLanguage || 'zh-CN'}_${this.ttsStyle || ''}_`;
  }

  findCurrentVoice(): TtsVoiceOption | undefined {
    return this.voices.find((voice: TtsVoiceOption) => this.isCurrentVoice(voice));
  }

  isCurrentVoice(voice: TtsVoiceOption): boolean {
    return voice.id === this.ttsPerson && voice.online === this.ttsOnline &&
      (voice.style || '') === (this.ttsStyle || '') &&
      this.sameLanguage(voice.language || 'zh-CN', this.ttsLanguage || 'zh-CN');
  }

  findMatchingVoice(target: TtsVoiceOption, availableOnly: boolean): TtsVoiceOption | undefined {
    const exact = this.voices.find((voice: TtsVoiceOption) => voice.id === target.id && voice.online === target.online &&
      (voice.style || '') === (target.style || '') &&
      this.sameLanguage(voice.language || 'zh-CN', target.language || 'zh-CN') &&
      (!availableOnly || voice.available));
    if (exact) {
      return exact;
    }
    const sameModule = this.voices.find((voice: TtsVoiceOption) => voice.id === target.id &&
      voice.online === target.online && this.sameLanguage(voice.language || 'zh-CN', target.language || 'zh-CN') &&
      (!availableOnly || voice.available));
    if (sameModule) {
      return sameModule;
    }
    return this.voices.find((voice: TtsVoiceOption) => voice.id === target.id &&
      (!availableOnly || voice.available));
  }

  sameLanguage(left: string, right: string): boolean {
    return this.normalizeLanguage(left) === this.normalizeLanguage(right);
  }

  normalizeLanguage(language: string): string {
    const value = (language || 'zh-CN').trim().replace(/_/g, '-').toLowerCase();
    if (value === 'zh' || value === 'zh-cn' || value.startsWith('zh-hans')) {
      return 'zh-CN';
    }
    if (value === 'en' || value === 'en-us') {
      return 'en-US';
    }
    return value || 'zh-CN';
  }

  isVoiceDownloading(voice: TtsVoiceOption): boolean {
    return this.downloadingVoiceKey === this.voiceKey(voice);
  }

  formatDownloadProgress(progress: string): string {
    const value = (progress || '').trim();
    if (!value) {
      return '下载中';
    }
    return value;
  }

  shortErrorMessage(error: Object | undefined): string {
    if (!error) {
      return '未知错误';
    }
    const anyError = error as Record<string, Object>;
    const message = anyError['message'];
    if (message !== undefined) {
      return String(message);
    }
    return String(error);
  }

  @Builder
  titleBar() {
    Row() {
      Text('<')
        .fontSize(24)
        .fontColor(this.primaryTextColor())
        .width(40)
        .height(56)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })

      Text('朗读设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }

  async togglePreview(): Promise<void> {
    if (this.isPreviewing) {
      this.previewReader.stop();
      this.isPreviewing = false;
      return;
    }
    try {
      this.isPreviewing = true;
      await this.previewReader.start(this.getPreviewText(), {
        person: this.ttsPerson,
        online: this.ttsOnline,
        style: this.ttsStyle,
        language: this.ttsLanguage,
        speed: this.ttsSpeed,
        onFinished: () => {
          this.isPreviewing = false;
        },
        onError: (message: string) => {
          this.isPreviewing = false;
          promptAction.showToast({ message });
        }
      });
    } catch (e) {
      this.isPreviewing = false;
      promptAction.showToast({ message: '试听失败' });
    }
  }

  getPreviewText(): string {
    const language = (this.ttsLanguage || '').toLowerCase();
    if (language.startsWith('en')) {
      return 'This is a short text for voice preview. The current voice and speed will be used for playback.';
    }
    return this.previewText;
  }

  @Builder
  voiceRow(voice: TtsVoiceOption) {
    Row() {
      Text(this.voiceTitle(voice))
        .fontSize(16)
        .fontColor((voice.available || this.isVoiceDownloading(voice)) ? this.primaryTextColor() : this.subTextColor())
      .layoutWeight(1)

      Text(this.voiceTrailingText(voice))
        .fontSize(this.voiceTrailingFontSize(voice))
      .fontColor('#007DFF')
      .width(48)
      .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .borderRadius(8)
    .backgroundColor(this.voiceRowColor(voice))
    .onClick(() => {
      this.selectVoice(voice);
    })
  }

  voiceRowColor(voice: TtsVoiceOption): string {
    if (this.isVoiceDownloading(voice)) {
      return this.appDarkMode ? '#12304D' : '#E8F2FF';
    }
    if (!voice.available) {
      return this.appDarkMode ? '#1B1D22' : '#F1F2F4';
    }
    return this.isVoiceSelected(voice) ? (this.appDarkMode ? '#12304D' : '#E8F2FF') :
      (this.appDarkMode ? '#202329' : '#F6F7F9');
  }

  @Builder
  speedChip(value: number) {
    Text(`${value.toFixed(1)}x`)
      .fontSize(13)
      .fontColor(Math.abs(this.ttsSpeed - value) < 0.01 ? '#FFFFFF' : this.primaryTextColor())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(32)
      .borderRadius(16)
      .backgroundColor(Math.abs(this.ttsSpeed - value) < 0.01 ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
      .onClick(() => {
        this.ttsSpeed = value;
      })
  }

  voiceTrailingText(voice: TtsVoiceOption): string {
    if (this.isVoiceDownloading(voice)) {
      return '...';
    }
    if (!voice.available && voice.downloadable) {
      return '下载';
    }
    return this.isVoiceSelected(voice) ? '✓' : '';
  }

  voiceTrailingFontSize(voice: TtsVoiceOption): number {
    return (!voice.available && voice.downloadable) ? 14 : 18;
  }
}
