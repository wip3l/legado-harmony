import { router, promptAction } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { HttpTTS } from '../model/data/Book';
import { HttpClient } from '../core/http/HttpClient';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemTtsReader, TtsVoiceOption } from '../utils/SystemTtsReader';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';

const TTS_CUSTOM_VOICE_IMPORT_LIMIT_BYTES: number = 2 * 1024 * 1024;

@Entry
@Component
struct TtsSettingsPage {
  @StorageLink('ttsPerson') ttsPerson: number = 0;
  @StorageLink('ttsOnline') ttsOnline: number = 1;
  @StorageLink('ttsStyle') ttsStyle: string = '';
  @StorageLink('ttsLanguage') ttsLanguage: string = 'zh-CN';
  @StorageLink('ttsSpeed') ttsSpeed: number = 1;
  @StorageLink('ttsInstalledVoiceKeys') ttsInstalledVoiceKeys: string = '';
  @StorageLink('ttsCustomVoiceId') ttsCustomVoiceId: string = '';
  @StorageLink('ttsCustomVoices') ttsCustomVoices: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
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
  @State customVoices: HttpTTS[] = [];
  @State customVoiceImportUrl: string = '';
  @State isImportingCustomVoices: boolean = false;
  private speedSaveTimerId: number = -1;

  aboutToAppear(): void {
    this.syncBars();
    this.loadSettingsAndVoices();
  }

  onPageShow(): void {
    this.syncBars();
    this.loadSettingsAndVoices();
  }

  aboutToDisappear(): void {
    this.flushPendingSpeedSettings();
    this.previewReader.shutdown();
    this.isPreviewing = false;
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('朗读音色')
          Column() {
            ForEach(this.customVoices, (voice: HttpTTS) => {
              this.customVoiceSelectRow(voice)
            }, (voice: HttpTTS) => this.customVoiceKey(voice))
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
          .width('calc(100% - 24vp)')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('自定义音色')
          Row() {
            Column() {
              Text(this.customVoiceSummary())
                .fontSize(16)
                .fontColor(this.primaryTextColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('导入、启用、禁用、删除自定义音色')
                .fontSize(12)
                .fontColor(this.subTextColor())
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('管理')
              .fontSize(14)
              .fontColor(this.accentColor())
              .width(52)
              .textAlign(TextAlign.Center)
          }
          .width('calc(100% - 24vp)')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())
          .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
          .onClick(() => {
            router.pushUrl({ url: 'pages/CustomTtsVoiceManager' });
          })

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
              .selectedColor(this.accentColor())
              .onChange((value: number) => {
                this.applySpeed(value);
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
          .width('calc(100% - 24vp)')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
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
              .backgroundColor(this.isPreviewing ? '#E53935' : this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.togglePreview();
              })
          }
          .width('calc(100% - 24vp)')
          .padding(16)
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
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
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  normalizeDefaultOnlineVoice(): void {
    if (this.ttsOnline === 0 && this.ttsPerson === 0 && !this.ttsStyle &&
      this.sameLanguage(this.ttsLanguage || 'zh-CN', 'zh-CN')) {
      this.ttsOnline = 1;
      this.saveSettings();
    }
  }

  async loadSettingsAndVoices(): Promise<void> {
    try {
      const settings = await TtsSettingsStore.load(getContext(this));
      this.applySettings(settings);
    } catch (e) {
      console.warn('加载朗读设置失败:', e);
    }
    this.normalizeDefaultOnlineVoice();
    this.selectedVoiceKey = this.currentVoiceKey();
    this.loadVoices();
  }

  applySettings(settings: TtsSettings): void {
    this.ttsPerson = settings.person;
    this.ttsOnline = settings.online;
    this.ttsStyle = settings.style;
    this.ttsLanguage = settings.language;
    this.ttsSpeed = settings.speed;
    this.ttsInstalledVoiceKeys = settings.installedVoiceKeys;
    this.ttsCustomVoiceId = settings.customVoiceId;
    this.ttsCustomVoices = settings.customVoices;
    this.customVoices = SystemTtsReader.parseCustomVoices(settings.customVoices);
  }

  currentSettings(): TtsSettings {
    const settings = new TtsSettings();
    settings.person = this.ttsPerson;
    settings.online = this.ttsOnline;
    settings.style = this.ttsStyle;
    settings.language = this.ttsLanguage;
    settings.speed = this.ttsSpeed;
    settings.installedVoiceKeys = this.ttsInstalledVoiceKeys;
    settings.customVoiceId = this.ttsCustomVoiceId;
    settings.customVoices = this.ttsCustomVoices;
    return settings;
  }

  saveSettings(): void {
    const settings = this.currentSettings();
    TtsSettingsStore.applyToStorage(settings);
    TtsSettingsStore.save(getContext(this), settings).catch((e: Error) => {
      console.warn('保存朗读设置失败:', e);
    });
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
      const currentCustomVoice = this.findCurrentCustomVoice();
      if (currentCustomVoice) {
        this.selectedVoiceKey = this.customVoiceKey(currentCustomVoice);
        return;
      }
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
      this.ttsCustomVoiceId = '';
      this.saveSettings();
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
    this.ttsCustomVoiceId = '';
    this.selectedVoiceKey = this.voiceKey(voice);
    this.saveSettings();
  }

  applyCustomVoice(voice: HttpTTS): void {
    if (voice.enabled === false) {
      promptAction.showToast({ message: '该自定义音色已禁用' });
      return;
    }
    if (this.isPreviewing) {
      this.previewReader.stop();
      this.isPreviewing = false;
    }
    this.ttsCustomVoiceId = String(voice.id);
    this.selectedVoiceKey = this.customVoiceKey(voice);
    this.saveSettings();
    promptAction.showToast({ message: `已启用 ${voice.name}` });
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
    this.saveSettings();
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
    const customVoice = this.findCurrentCustomVoice();
    if (customVoice) {
      return this.customVoiceKey(customVoice);
    }
    const matched = this.findCurrentVoice();
    return matched ? this.voiceKey(matched) :
      `${this.ttsPerson}_${this.ttsOnline}_${this.ttsLanguage || 'zh-CN'}_${this.ttsStyle || ''}_`;
  }

  findCurrentVoice(): TtsVoiceOption | undefined {
    return this.voices.find((voice: TtsVoiceOption) => this.isCurrentVoice(voice));
  }

  isCurrentVoice(voice: TtsVoiceOption): boolean {
    if (this.ttsCustomVoiceId) {
      return false;
    }
    return voice.id === this.ttsPerson && voice.online === this.ttsOnline &&
      (voice.style || '') === (this.ttsStyle || '') &&
      this.sameLanguage(voice.language || 'zh-CN', this.ttsLanguage || 'zh-CN');
  }

  findCurrentCustomVoice(): HttpTTS | undefined {
    const selectedId = (this.ttsCustomVoiceId || '').trim();
    if (!selectedId) {
      return undefined;
    }
    return this.customVoices.find((voice: HttpTTS) => String(voice.id) === selectedId);
  }

  customVoiceKey(voice: HttpTTS): string {
    return `custom_${voice.id}_${voice.name || ''}`;
  }

  customVoiceTitle(voice: HttpTTS): string {
    const state = voice.enabled === false ? ' · 已禁用' : '';
    return `${voice.name || '未命名音色'} · 自定义${state}`;
  }

  isCustomVoiceSelected(voice: HttpTTS): boolean {
    return (this.ttsCustomVoiceId || '') === String(voice.id);
  }

  customVoiceSummary(): string {
    return this.customVoices.length > 0 ? `已导入 ${this.customVoices.length} 个自定义音色` : '暂无自定义音色';
  }

  deleteCustomVoice(voice: HttpTTS): void {
    const selected = this.isCustomVoiceSelected(voice);
    this.customVoices = this.customVoices.filter((item: HttpTTS) => String(item.id) !== String(voice.id));
    this.ttsCustomVoices = SystemTtsReader.serializeCustomVoices(this.customVoices);
    if (selected) {
      if (this.isPreviewing) {
        this.previewReader.stop();
        this.isPreviewing = false;
      }
      this.ttsCustomVoiceId = '';
      this.ttsPerson = 0;
      this.ttsOnline = 1;
      this.ttsStyle = '';
      this.ttsLanguage = 'zh-CN';
      this.selectedVoiceKey = this.currentVoiceKey();
    }
    this.saveSettings();
    promptAction.showToast({ message: `已删除 ${voice.name || '自定义音色'}` });
  }

  async importCustomVoicesFromUrl(): Promise<void> {
    const url = this.customVoiceImportUrl.trim();
    if (!url) {
      promptAction.showToast({ message: '请输入音色 JSON URL' });
      return;
    }
    if (this.isImportingCustomVoices) {
      return;
    }
    this.isImportingCustomVoices = true;
    try {
      const response = await new HttpClient(15000).execute({
        url,
        method: 'GET',
        headers: {},
        maxResponseBytes: TTS_CUSTOM_VOICE_IMPORT_LIMIT_BYTES
      });
      if (!response.success) {
        throw new Error(response.error || `HTTP ${response.statusCode}`);
      }
      this.importCustomVoicesFromJson(response.body);
    } catch (error) {
      promptAction.showToast({ message: `导入失败：${this.shortErrorMessage(error as Object)}` });
    } finally {
      this.isImportingCustomVoices = false;
    }
  }

  async importCustomVoicesFromFile(): Promise<void> {
    if (this.isImportingCustomVoices) {
      return;
    }
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['JSON|.json', '文本|.txt'];
      const result: Array<string> = await new picker.DocumentViewPicker().select(options);
      if (!result || result.length === 0) {
        return;
      }
      this.isImportingCustomVoices = true;
      const content = await this.readTextFile(result[0]);
      this.importCustomVoicesFromJson(content);
    } catch (error) {
      promptAction.showToast({ message: `导入失败：${this.shortErrorMessage(error as Object)}` });
    } finally {
      this.isImportingCustomVoices = false;
    }
  }

  importCustomVoicesFromJson(content: string): void {
    const incoming = SystemTtsReader.parseCustomVoices(content);
    if (incoming.length === 0) {
      promptAction.showToast({ message: '未识别到有效自定义音色' });
      return;
    }
    const merged: HttpTTS[] = this.customVoices.slice();
    let changed = 0;
    for (const voice of incoming) {
      this.ensureUniqueCustomVoiceId(voice, merged);
      const index = merged.findIndex((item: HttpTTS) => String(item.id) === String(voice.id) ||
        ((item.name || '') === (voice.name || '') && (item.url || '') === (voice.url || '')));
      if (index >= 0) {
        merged[index] = voice;
      } else {
        merged.push(voice);
      }
      changed++;
    }
    this.customVoices = merged;
    this.ttsCustomVoices = SystemTtsReader.serializeCustomVoices(merged);
    if (!this.ttsCustomVoiceId && incoming.length > 0) {
      this.ttsCustomVoiceId = String(incoming[0].id);
      this.selectedVoiceKey = this.customVoiceKey(incoming[0]);
    }
    this.saveSettings();
    promptAction.showToast({ message: `已导入 ${changed} 个自定义音色` });
  }

  ensureUniqueCustomVoiceId(voice: HttpTTS, existing: HttpTTS[]): void {
    if (!existing.some((item: HttpTTS) => item.id === voice.id && (item.url || '') !== (voice.url || ''))) {
      return;
    }
    let id = Date.now();
    while (existing.some((item: HttpTTS) => item.id === id)) {
      id++;
    }
    voice.id = id;
  }

  async readTextFile(filePath: string): Promise<string> {
    let file: fs.File | null = null;
    try {
      const stat = await fs.stat(filePath);
      if (stat.size <= 0) {
        return '';
      }
      if (stat.size > TTS_CUSTOM_VOICE_IMPORT_LIMIT_BYTES) {
        throw new Error('文件过大，请选择 2MB 以内的音色文件');
      }
      file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer), { stream: false })
        .replace(/^\uFEFF/, '');
    } finally {
      if (file) {
        await fs.close(file);
      }
    }
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
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        onBack: () => router.back() })

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
      .fontColor(this.accentColor())
      .width(48)
      .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.voiceRowColor(voice))
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .onClick(() => {
      this.selectVoice(voice);
    })
  }

  voiceRowColor(voice: TtsVoiceOption): string {
    if (this.isVoiceDownloading(voice)) {
      return ThemeRuntime.accentSurfaceColor(this.appDarkMode);
    }
    if (!voice.available) {
      return this.inputColor();
    }
    return this.isVoiceSelected(voice) ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : this.inputColor();
  }

  @Builder
  speedChip(value: number) {
    Stack({ alignContent: Alignment.Center }) {
      Text(`${value.toFixed(1)}x`)
        .fontSize(13)
        .fontColor(Math.abs(this.ttsSpeed - value) < 0.01 ? '#FFFFFF' : this.primaryTextColor())
    }
        .layoutWeight(1)
      .height(32)
      .borderRadius(16)
      .backgroundColor(Math.abs(this.ttsSpeed - value) < 0.01 ? this.accentColor() : this.inputColor())
      .onClick(() => {
        this.applySpeed(value);
      })
  }

  @Builder
  customVoiceRow(voice: HttpTTS) {
    Row() {
      Text(this.customVoiceTitle(voice))
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .onClick(() => {
          this.applyCustomVoice(voice);
        })

      Text(this.isCustomVoiceSelected(voice) ? '✓' : '')
        .fontSize(18)
        .fontColor(this.accentColor())
        .width(36)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.applyCustomVoice(voice);
        })

      Text('删除')
        .fontSize(14)
        .fontColor('#E53935')
        .width(46)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.deleteCustomVoice(voice);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.isCustomVoiceSelected(voice) ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) :
      this.inputColor())
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
  }

  @Builder
  customVoiceSelectRow(voice: HttpTTS) {
    Row() {
      Text(this.customVoiceTitle(voice))
        .fontSize(16)
        .fontColor(voice.enabled === false ? this.subTextColor() : this.primaryTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.isCustomVoiceSelected(voice) ? '✓' : '')
        .fontSize(18)
        .fontColor(this.accentColor())
        .width(48)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .borderRadius(8)
    .backgroundColor(this.isCustomVoiceSelected(voice) ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) :
      this.inputColor())
    .onClick(() => {
      this.applyCustomVoice(voice);
    })
  }

  applySpeed(value: number): void {
    const nextSpeed = Math.max(0.5, Math.min(2, Math.round(value * 10) / 10));
    if (Math.abs(this.ttsSpeed - nextSpeed) < 0.01) {
      return;
    }
    this.ttsSpeed = nextSpeed;
    this.scheduleSpeedSettingsSave();
  }

  scheduleSpeedSettingsSave(): void {
    if (this.speedSaveTimerId >= 0) {
      clearTimeout(this.speedSaveTimerId);
    }
    this.speedSaveTimerId = setTimeout(() => {
      this.speedSaveTimerId = -1;
      this.saveSettings();
    }, 300);
  }

  flushPendingSpeedSettings(): void {
    if (this.speedSaveTimerId >= 0) {
      clearTimeout(this.speedSaveTimerId);
      this.speedSaveTimerId = -1;
      this.saveSettings();
    }
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
