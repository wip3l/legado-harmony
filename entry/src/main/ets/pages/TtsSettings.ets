import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import {
  TtsCatalogResponse,
  TtsPackageInfo,
  TtsVoiceInfo,
  TtsWalletSnapshot
} from '../account/AccountCommerceModels';
import { HttpTTS } from '../model/data/Book';
import { HttpClient } from '../core/http/HttpClient';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemTtsReader, TtsVoiceOption } from '../utils/SystemTtsReader';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { AdaptiveIconButton } from '../components/AdaptiveIconButton';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
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
  @StorageLink('ttsCustomVoiceId') @Watch('onCustomVoiceSelectionChanged') ttsCustomVoiceId: string = '';
  @StorageLink('ttsCustomVoices') @Watch('onCustomVoicesStorageChanged') ttsCustomVoices: string = '';
  @StorageLink('ttsCloudVoiceId') ttsCloudVoiceId: string = '';
  @StorageLink('accountLoggedIn') accountLoggedIn: boolean = false;
  @StorageLink('accountPaidPoints') paidPoints: number = 0;
  @StorageLink('accountPromoPoints') promoPoints: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State voices: TtsVoiceOption[] = [TtsSettingsPage.defaultVoice()];
  @State cloudVoices: TtsVoiceInfo[] = [];
  @State ttsCatalog: TtsCatalogResponse = new TtsCatalogResponse();
  @State ttsStandardChars: number = 0;
  @State ttsPremiumChars: number = 0;
  @State ttsStandardNextExpiry: number | null = null;
  @State ttsPremiumNextExpiry: number | null = null;
  @State ttsWalletLoaded: boolean = false;
  @State ttsWalletError: string = '';
  @State ttsCommerceLoading: boolean = false;
  @State redeemingTtsSku: string = '';
  @State selectedVoiceKey: string = '';
  private previewText: string = '这是一段朗读试听文字。点击试听后，会按照当前音色和倍速播放。';
  private previewReader: SystemTtsReader = new SystemTtsReader();
  @State isPreviewing: boolean = false;
  @State isLoadingVoices: boolean = false;
  @State downloadingVoiceKey: string = '';
  @State downloadProgressText: string = '';
  @State customVoices: HttpTTS[] = [];
  @State showVoiceDropdown: boolean = false;
  @State customVoiceImportUrl: string = '';
  @State isImportingCustomVoices: boolean = false;
  private speedSaveTimerId: number = -1;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.syncBars();
    this.loadSettingsAndVoices();
    this.loadTtsCommerce();
  }

  onPageShow(): void {
    this.syncBars();
    this.loadSettingsAndVoices();
    this.loadTtsCommerce();
  }

  aboutToDisappear(): void {
    this.flushPendingSpeedSettings();
    this.previewReader.shutdown();
    this.isPreviewing = false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          Column() {
            this.sectionTitle('朗读音色')
            this.voiceDropdownSelector()

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

            Row({ space: 10 }) {
              this.speedStepButton($r('sys.symbol.minus'), '降低朗读倍速', this.ttsSpeed > 0.5, () => {
                this.applySpeed(this.ttsSpeed - 0.1);
              })
              Slider({ value: this.ttsSpeed, min: 0.5, max: 2, step: 0.1 })
                .layoutWeight(1)
                .showTips(true)
                .selectedColor(this.accentColor())
                .sliderInteractionMode(ImmersiveMaterialRuntime.supportsHds() ? SliderInteraction.SLIDE_AND_CLICK_UP : SliderInteraction.SLIDE_ONLY)
                .onChange((value: number) => {
                  this.applySpeed(value);
                })
              this.speedStepButton($r('sys.symbol.plus'), '提高朗读倍速', this.ttsSpeed !== 2, () => {
                this.applySpeed(this.ttsSpeed + 0.1);
              })
            }
            .width('100%')
            .margin({ top: 10 })

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

          this.sectionTitle('在线朗读字数')
          this.ttsCommerceSection()
          }
          .width('100%')
          .padding({ top: 56 + this.statusBarHeight, bottom: this.navBarHeight + 32 })
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)

      this.titleBar()

      if (this.showVoiceDropdown) {
        this.voiceDropdownMenu()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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

  onCustomVoicesStorageChanged(): void {
    this.customVoices = SystemTtsReader.parseCustomVoices(this.ttsCustomVoices);
    this.selectedVoiceKey = this.currentVoiceKey();
  }

  onCustomVoiceSelectionChanged(): void {
    this.selectedVoiceKey = this.currentVoiceKey();
  }

  enabledCustomVoices(): HttpTTS[] {
    return this.customVoices.filter((voice: HttpTTS) => voice.enabled !== false);
  }

  disabledCustomVoices(): HttpTTS[] {
    return this.customVoices.filter((voice: HttpTTS) => voice.enabled === false);
  }

  selectedVoiceTitle(): string {
    const cloudVoice = this.findCurrentCloudVoice();
    if (cloudVoice) {
      return this.cloudVoiceTitle(cloudVoice);
    }
    const customVoice = this.findCurrentCustomVoice();
    if (customVoice && customVoice.enabled !== false) {
      return this.customVoiceTitle(customVoice);
    }
    const systemVoice = this.findCurrentVoice();
    if (systemVoice) {
      return this.voiceTitle(systemVoice);
    }
    return this.isLoadingVoices ? '正在加载音色...' : '默认音色';
  }

  @Builder
  voiceDropdownSelector() {
    Row() {
      Text(this.selectedVoiceTitle())
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      SymbolGlyph(this.showVoiceDropdown ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
        .width(18)
    }
    .width('calc(100% - 24vp)')
    .height(54)
    .padding({ left: 16, right: 16 })
    .margin({ left: 12, right: 12 })
    .borderRadius(14)
    .backgroundColor(this.cardColor())
    .onClick(() => {
      this.showVoiceDropdown = !this.showVoiceDropdown;
    })
  }

  @Builder
  voiceDropdownMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.showVoiceDropdown = false;
        })

      Column() {
        Scroll() {
          Column() {
            if (this.cloudVoices.length > 0) {
              this.voiceDropdownSectionTitle('云端音色')
              ForEach(this.cloudVoices, (voice: TtsVoiceInfo) => {
                this.cloudVoiceDropdownOption(voice)
              }, (voice: TtsVoiceInfo) => `cloud_${voice.id}`)
            }
            if (this.enabledCustomVoices().length > 0) {
              this.voiceDropdownSectionTitle('自定义音色')
              ForEach(this.enabledCustomVoices(), (voice: HttpTTS) => {
                this.customVoiceDropdownOption(voice, false)
              }, (voice: HttpTTS) => `${this.customVoiceKey(voice)}_enabled`)
            }

            this.voiceDropdownSectionTitle('系统音色')
            ForEach(this.voices, (voice: TtsVoiceOption) => {
              this.systemVoiceDropdownOption(voice)
            }, (voice: TtsVoiceOption) => this.voiceKey(voice))

            if (this.disabledCustomVoices().length > 0) {
              this.voiceDropdownSectionTitle('已禁用')
              ForEach(this.disabledCustomVoices(), (voice: HttpTTS) => {
                this.customVoiceDropdownOption(voice, true)
              }, (voice: HttpTTS) => `${this.customVoiceKey(voice)}_disabled`)
            }
          }
          .width('100%')
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .constraintSize({ maxHeight: 420 })
      }
      .width('calc(100% - 24vp)')
      .constraintSize({ maxWidth: 560 })
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
      .position({ x: 12, y: this.statusBarHeight + 108 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  voiceDropdownSectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 5 })
  }

  @Builder
  customVoiceDropdownOption(voice: HttpTTS, disabled: boolean) {
    Row() {
      Text(this.customVoiceTitle(voice))
        .fontSize(15)
        .fontColor(disabled ? this.subTextColor() : this.primaryTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (!disabled && this.isCustomVoiceSelected(voice)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: 14, right: 14 })
    .opacity(disabled ? 0.5 : 1)
    .onClick(() => {
      if (disabled) {
        return;
      }
      this.showVoiceDropdown = false;
      this.applyCustomVoice(voice);
    })
  }

  @Builder
  systemVoiceDropdownOption(voice: TtsVoiceOption) {
    Row() {
      Text(this.voiceTitle(voice))
        .fontSize(15)
        .fontColor((voice.available || voice.downloadable) ? this.primaryTextColor() : this.subTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.isVoiceDownloading(voice)) {
        Text(this.downloadProgressText || '下载中')
          .fontSize(11)
          .fontColor(this.accentColor())
      } else if (this.isVoiceSelected(voice)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([this.accentColor()])
      } else if (!voice.available && voice.downloadable) {
        Text('下载')
          .fontSize(12)
          .fontColor(this.accentColor())
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: 14, right: 14 })
    .opacity((voice.available || voice.downloadable) ? 1 : 0.5)
    .onClick(() => {
      if (!voice.available && !voice.downloadable) {
        return;
      }
      this.showVoiceDropdown = false;
      this.selectVoice(voice);
    })
  }

  @Builder
  cloudVoiceDropdownOption(voice: TtsVoiceInfo) {
    Row() {
      Text(this.cloudVoiceTitle(voice))
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.ttsCloudVoiceId === voice.id) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      this.showVoiceDropdown = false;
      this.applyCloudVoice(voice);
    })
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

  async loadTtsCommerce(): Promise<void> {
    if (this.ttsCommerceLoading) {
      return;
    }
    this.ttsCommerceLoading = true;
    this.ttsWalletError = '';
    try {
      const catalog = await AccountCommerceApi.fetchTtsCatalog();
      this.ttsCatalog = catalog;
      if (!AccountSessionStore.isLoggedIn()) {
        this.ttsWalletLoaded = false;
        return;
      }
      this.applyTtsWallet(await AccountCommerceApi.fetchTtsWallet(AccountSessionStore.token()));
    } catch (e) {
      console.warn('加载在线朗读字数包失败:', e);
      this.ttsWalletError = this.commerceErrorMessage(e as Object, '额度同步失败');
    } finally {
      this.ttsCommerceLoading = false;
    }
  }

  async redeemTtsPackage(item: TtsPackageInfo): Promise<void> {
    if (this.redeemingTtsSku) {
      return;
    }
    if (!AccountSessionStore.isLoggedIn()) {
      promptAction.showToast({ message: '请先在“我的-账号与点数”登录' });
      return;
    }
    if (this.paidPoints < item.points) {
      promptAction.showToast({ message: '充值点不足，请先充值点数' });
      return;
    }
    const tierName = item.tier === 'PREMIUM' ? '精品音色' : '标准音色';
    const result = await promptAction.showDialog({
      title: '兑换在线朗读字数',
      message: `使用 ${item.points} 充值点兑换 ${tierName} ${this.formatTtsChars(item.chars)}，有效期 ${item.validDays} 天。赠送点不能兑换。`,
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '确认兑换', color: this.accentColor() }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    this.redeemingTtsSku = item.sku;
    try {
      const response = await AccountCommerceApi.redeemTtsPackage(
        item.sku,
        util.generateRandomUUID(),
        AccountSessionStore.token()
      );
      await AccountSessionStore.updateSnapshot(this.context, response.account);
      this.applyTtsWallet(response.ttsWallet);
      try {
        this.applyTtsWallet(await AccountCommerceApi.fetchTtsWallet(AccountSessionStore.token()));
      } catch (refreshError) {
        console.warn('兑换后刷新在线朗读字数失败:', refreshError);
      }
      promptAction.showToast({ message: `已到账 ${this.formatTtsChars(item.chars)}` });
    } catch (e) {
      promptAction.showToast({ message: this.commerceErrorMessage(e as Object, '兑换失败') });
    } finally {
      this.redeemingTtsSku = '';
    }
  }

  applyTtsWallet(wallet: TtsWalletSnapshot): void {
    this.ttsStandardChars = wallet.standardChars;
    this.ttsPremiumChars = wallet.premiumChars;
    this.ttsStandardNextExpiry = wallet.standardNextExpiry;
    this.ttsPremiumNextExpiry = wallet.premiumNextExpiry;
    this.ttsWalletLoaded = true;
    this.ttsWalletError = '';
  }

  formatTtsChars(chars: number): string {
    if (chars >= 10000) {
      const wan = chars / 10000;
      return `${Number.isInteger(wan) ? wan.toFixed(0) : wan.toFixed(1)} 万字`;
    }
    return `${chars} 字`;
  }

  commerceErrorMessage(error: Object, fallback: string): string {
    const message = this.shortErrorMessage(error);
    return message && message !== '未知错误' ? message : fallback;
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
    this.ttsCloudVoiceId = settings.cloudVoiceId;
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
    settings.cloudVoiceId = this.ttsCloudVoiceId;
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
      const results = await Promise.all([
        SystemTtsReader.listAvailableVoices(),
        AccountCommerceApi.fetchTtsCatalog().catch(() => null)
      ]);
      const voices = results[0] as TtsVoiceOption[];
      const catalog = results[1];
      this.cloudVoices = catalog ? catalog.voices : [];
      if (catalog && this.ttsCloudVoiceId && !this.findCurrentCloudVoice()) {
        const previousVoiceId = this.ttsCloudVoiceId;
        const fallbackVoice = this.cloudVoices.find((voice: TtsVoiceInfo) => voice.id === 'xiaoyan') ||
          this.cloudVoices[0];
        this.ttsCloudVoiceId = fallbackVoice ? fallbackVoice.id : '';
        console.warn(`[TTS] unsupported cloud voice migrated: ${previousVoiceId} -> ${this.ttsCloudVoiceId}`);
        this.saveSettings();
      }
      if (!catalog && this.ttsCloudVoiceId) {
        const fallbackCloudVoice = new TtsVoiceInfo();
        fallbackCloudVoice.id = this.ttsCloudVoiceId;
        fallbackCloudVoice.name = '云端音色';
        this.cloudVoices = [fallbackCloudVoice];
      }
      this.voices = this.applyInstalledOverrides(this.mergeWithDefaultVoice(voices));
      const currentCloudVoice = this.findCurrentCloudVoice();
      if (currentCloudVoice) {
        this.selectedVoiceKey = `cloud_${currentCloudVoice.id}`;
        return;
      }
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
    this.ttsCloudVoiceId = '';
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
    this.ttsCloudVoiceId = '';
    this.selectedVoiceKey = this.customVoiceKey(voice);
    this.saveSettings();
    promptAction.showToast({ message: `已启用 ${voice.name}` });
  }

  applyCloudVoice(voice: TtsVoiceInfo): void {
    if (!AccountSessionStore.isLoggedIn()) {
      promptAction.showToast({ message: '请先登录华为账号后使用云端音色' });
      return;
    }
    if (this.isPreviewing) {
      this.previewReader.stop();
      this.isPreviewing = false;
    }
    this.ttsCloudVoiceId = voice.id;
    this.ttsCustomVoiceId = '';
    this.selectedVoiceKey = `cloud_${voice.id}`;
    this.saveSettings();
    promptAction.showToast({ message: `已启用 ${voice.name}` });
  }

  findCurrentCloudVoice(): TtsVoiceInfo | undefined {
    const id = (this.ttsCloudVoiceId || '').trim();
    if (!id) return undefined;
    return this.cloudVoices.find((voice: TtsVoiceInfo) => voice.id === id);
  }

  cloudVoiceTitle(voice: TtsVoiceInfo): string {
    const tier = voice.tier === 'PREMIUM' ? '精品' : '标准';
    const description = (voice.description || '').trim();
    return description
      ? `${voice.name} · ${description} · 云端${tier}`
      : `${voice.name} · 云端${tier}`;
  }

  async downloadAndSelectVoice(voice: TtsVoiceOption): Promise<void> {
    if (!SystemTtsReader.supportsVoiceDownload()) {
      promptAction.showToast({ message: '当前系统版本不支持下载系统音色，请升级系统后重试' });
      return;
    }
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
    if (this.ttsCloudVoiceId) {
      return `cloud_${this.ttsCloudVoiceId}`;
    }
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
    if (this.ttsCustomVoiceId || this.ttsCloudVoiceId) {
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
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })

      Text('朗读设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ top: this.statusBarHeight })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
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

  @Builder
  ttsCommerceSection() {
    Column({ space: 12 }) {
      Row() {
        Text(this.accountLoggedIn ? '当前额度' : '登录后可查看额度并兑换')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        if (this.ttsCommerceLoading) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.accentColor())
        } else {
          Text('刷新')
            .fontSize(13)
            .fontColor(this.accentColor())
            .padding({ left: 10, right: 2, top: 6, bottom: 6 })
            .onClick(() => {
              this.loadTtsCommerce();
            })
        }
      }
      .width('100%')

      if (this.accountLoggedIn) {
        Row({ space: 10 }) {
          this.ttsBalanceCard('标准音色', false)
          this.ttsBalanceCard('精品音色', true)
        }
        .width('100%')

        if (this.ttsWalletError) {
          Text(`${this.ttsWalletError}，请点击刷新`)
            .fontSize(11)
            .fontColor('#E5484D')
            .width('100%')
        }

        Text(`可用于兑换：${this.paidPoints} 充值点 · 赠送点 ${this.promoPoints} 仅可兑换主题`)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .width('100%')
      } else {
        Text('请先在“我的-账号与点数”登录华为账号，再返回这里兑换在线朗读字数。')
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.subTextColor())
          .width('100%')
      }

      ForEach(this.ttsCatalog.packages, (item: TtsPackageInfo) => {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text(`${item.tier === 'PREMIUM' ? '精品' : '标准'} · ${this.formatTtsChars(item.chars)}`)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryTextColor())
            Text(`${item.validDays} 天有效`)
              .fontSize(11)
              .fontColor(this.subTextColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.redeemingTtsSku === item.sku ? '兑换中' : `${item.points} 点`)
            .height(34)
            .fontSize(13)
            .enabled(!this.redeemingTtsSku && this.accountLoggedIn && this.paidPoints >= item.points)
            .fontColor('#FFFFFF')
            .backgroundColor(this.accentColor())
            .onClick(() => {
              this.redeemTtsPackage(item);
            })
        }
        .width('100%')
        .padding({ left: 12, right: 10, top: 10, bottom: 10 })
        .borderRadius(12)
        .backgroundColor(this.inputColor())
      }, (item: TtsPackageInfo) => item.sku)

      Text('标准音色每次按 100 字向上取整，精品音色每次按 50 字向上取整；相同音色、文字和倍速会优先使用本地缓存。')
        .fontSize(11)
        .lineHeight(17)
        .fontColor(this.subTextColor())
        .width('100%')
    }
    .width('calc(100% - 24vp)')
    .padding(16)
    .margin({ left: 12, right: 12, bottom: 24 })
    .borderRadius(16)
    .backgroundColor(this.cardColor())
  }

  @Builder
  ttsBalanceCard(title: string, premium: boolean) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(12)
        .fontColor(this.subTextColor())
      Text(this.ttsWalletLoaded
        ? this.formatTtsChars(premium ? this.ttsPremiumChars : this.ttsStandardChars)
        : '--')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Text(this.ttsWalletLoaded
        ? ((premium ? this.ttsPremiumNextExpiry : this.ttsStandardNextExpiry)
          ? `${new Date((premium ? this.ttsPremiumNextExpiry : this.ttsStandardNextExpiry) as number)
            .toLocaleDateString()} 到期`
          : '暂无额度')
        : (this.ttsWalletError ? '同步失败' : '正在同步'))
        .fontSize(10)
        .fontColor(this.subTextColor())
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.inputColor())
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
        cloudVoiceId: this.findCurrentCloudVoice()?.id || '',
        cloudVoiceName: this.findCurrentCloudVoice()?.name || '',
        cloudVoiceTier: this.findCurrentCloudVoice()?.tier || 'STANDARD',
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
  speedStepButton(icon: Resource, accessibilityText: string, enabled: boolean, action: () => void) {
    AdaptiveIconButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      buttonEnabled: enabled,
      buttonSize: 34,
      iconSize: 16,
      fillColor: this.inputColor(),
      iconColor: this.primaryTextColor(),
      disabledIconColor: this.subTextColor(),
      action: action
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

}
