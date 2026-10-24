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
import { HttpTTS, HttpClient } from '@legado/sourceengine';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemTtsReader, TtsVoiceOption } from '../utils/SystemTtsReader';
import { TtsVoiceCatalog } from '../utils/TtsVoiceCatalog';
import { AdaptiveIconButton } from '../components/AdaptiveIconButton';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';

const TTS_CUSTOM_VOICE_IMPORT_LIMIT_BYTES: number = 2 * 1024 * 1024;

@Entry
@Component
struct TtsSettingsPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
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

  @State voices: TtsVoiceOption[] = [TtsVoiceCatalog.defaultVoice()];
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
  @State voiceSelectorWidth: number = 320;
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
      PageScaffold({ title: '朗读设置', content: () => {
        this.pageContent()
      } })

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
      this.sectionTitle('朗读音色')
      this.voiceDropdownSelector()

    this.sectionTitle('自定义音色')
    Row() {
      Column() {
        Text(this.customVoiceSummary())
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('导入、启用、禁用、删除自定义音色')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('管理')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .width(52)
        .textAlign(TextAlign.Center)
    }
    .width('calc(100% - 24vp)')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
    .border({ width: { bottom: 0.5 }, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
    .onClick(() => {
      router.pushUrl({ url: 'pages/CustomTtsVoiceManager' });
    })

    this.sectionTitle('朗读倍速')
    Column() {
      Row() {
        Text('倍速')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.ttsSpeed.toFixed(1)}x`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
      }
      .width('100%')

      Row({ space: AppSpacing.MD }) {
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
      .margin({ top: AppSpacing.MD })

      Row({ space: AppSpacing.MD }) {
        this.speedChip(0.8)
        this.speedChip(1.0)
        this.speedChip(1.2)
        this.speedChip(1.5)
        this.speedChip(2.0)
      }
      .width('100%')
      .margin({ top: AppSpacing.MD })
    }
    .width('calc(100% - 24vp)')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('预览')
    Column({ space: AppSpacing.LG }) {
      Text(this.previewText)
        .fontSize(AppFontSize.BODY)
        .lineHeight(22)
        .fontColor(this.subTextColor())
        .width('100%')

      Button(this.isPreviewing ? '停止试听' : '试听')
        .width('100%')
        .height(42)
        .backgroundColor(this.isPreviewing ? ThemeRuntime.dangerColor(this.appDarkMode) : this.buttonColor())
        .fontColor(ThemeRuntime.onAccentColor())
        .onClick(() => {
          this.togglePreview();
        })
    }
    .width('calc(100% - 24vp)')
    .padding(AppSpacing.XL)
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('在线朗读字数')
    this.ttsCommerceSection()
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
      return TtsVoiceCatalog.cloudVoiceTitle(cloudVoice);
    }
    const customVoice = this.findCurrentCustomVoice();
    if (customVoice && customVoice.enabled !== false) {
      return TtsVoiceCatalog.customVoiceTitle(customVoice);
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
        .fontSize(AppFontSize.BODY_LARGE)
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
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .onClick(() => {
      this.showVoiceDropdown = !this.showVoiceDropdown;
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      if (Number.isFinite(width) && width > 0) this.voiceSelectorWidth = width;
    })
    .bindPopup(this.showVoiceDropdown, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.voiceDropdownMenu()
    }, Placement.Bottom, this.appDarkMode, this.accentColor(), () => {
      this.showVoiceDropdown = false;
    }))
  }

  /** 音色下拉：系统弹出层，API 26+ 挂沉浸光感材质。 */
  @Builder
  voiceDropdownMenu() {
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
            }, (voice: HttpTTS) => `${TtsVoiceCatalog.customVoiceKey(voice)}_enabled`)
          }

          this.voiceDropdownSectionTitle('系统音色')
          ForEach(this.voices, (voice: TtsVoiceOption) => {
            this.systemVoiceDropdownOption(voice)
          }, (voice: TtsVoiceOption) => TtsVoiceCatalog.voiceKey(voice))

          if (this.disabledCustomVoices().length > 0) {
            this.voiceDropdownSectionTitle('已禁用')
            ForEach(this.disabledCustomVoices(), (voice: HttpTTS) => {
              this.customVoiceDropdownOption(voice, true)
            }, (voice: HttpTTS) => `${TtsVoiceCatalog.customVoiceKey(voice)}_disabled`)
          }
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .constraintSize({ maxHeight: 420 })
    }
    .width(this.voiceSelectorWidth)
    .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
  }

  @Builder
  voiceDropdownSectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.XS })
  }

  @Builder
  customVoiceDropdownOption(voice: HttpTTS, disabled: boolean) {
    Row() {
      Text(TtsVoiceCatalog.customVoiceTitle(voice))
        .fontSize(AppFontSize.BODY_LARGE)
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
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
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
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor((voice.available || voice.downloadable) ? this.primaryTextColor() : this.subTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.isVoiceDownloading(voice)) {
        Text(this.downloadProgressText || '下载中')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
      } else if (this.isVoiceSelected(voice)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([this.accentColor()])
      } else if (!voice.available && voice.downloadable) {
        Text('下载')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
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
      Text(TtsVoiceCatalog.cloudVoiceTitle(voice))
        .fontSize(AppFontSize.BODY_LARGE)
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
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .onClick(() => {
      this.showVoiceDropdown = false;
      this.applyCloudVoice(voice);
    })
  }

  normalizeDefaultOnlineVoice(): void {
    if (this.ttsOnline === 0 && this.ttsPerson === 0 && !this.ttsStyle &&
      TtsVoiceCatalog.sameLanguage(this.ttsLanguage || 'zh-CN', 'zh-CN')) {
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
      HdsFeedback.showToast('请先在“我的-账号与点数”登录');
      return;
    }
    if (this.paidPoints < item.points) {
      HdsFeedback.showToast('充值点不足，请先充值点数');
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
      HdsFeedback.showToast(`已到账 ${this.formatTtsChars(item.chars)}`);
    } catch (e) {
      HdsFeedback.showToast(this.commerceErrorMessage(e as Object, '兑换失败'));
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
      this.voices = this.applyInstalledOverrides(TtsVoiceCatalog.mergeWithDefault(voices));
      const currentCloudVoice = this.findCurrentCloudVoice();
      if (currentCloudVoice) {
        this.selectedVoiceKey = `cloud_${currentCloudVoice.id}`;
        return;
      }
      const currentCustomVoice = this.findCurrentCustomVoice();
      if (currentCustomVoice) {
        this.selectedVoiceKey = TtsVoiceCatalog.customVoiceKey(currentCustomVoice);
        return;
      }
      const currentVoice = this.findCurrentVoice();
      if (!currentVoice || !currentVoice.available) {
        const defaultVoice = this.firstAvailableVoice();
        this.applyVoice(defaultVoice, false);
      } else {
        this.selectedVoiceKey = TtsVoiceCatalog.voiceKey(currentVoice);
      }
    } catch (_) {
      this.voices = [TtsVoiceCatalog.defaultVoice()];
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

  firstAvailableVoice(): TtsVoiceOption {
    return this.voices.find((voice: TtsVoiceOption) => voice.available) || this.voices[0] ||
      TtsVoiceCatalog.defaultVoice();
  }

  async selectVoice(voice: TtsVoiceOption): Promise<void> {
    if (!voice.available) {
      if (voice.downloadable) {
        await this.downloadAndSelectVoice(voice);
      } else {
        HdsFeedback.showToast('该系统音色当前不可用');
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
    this.selectedVoiceKey = TtsVoiceCatalog.voiceKey(voice);
    this.saveSettings();
  }

  applyCustomVoice(voice: HttpTTS): void {
    if (voice.enabled === false) {
      HdsFeedback.showToast('该自定义音色已禁用');
      return;
    }
    if (this.isPreviewing) {
      this.previewReader.stop();
      this.isPreviewing = false;
    }
    this.ttsCustomVoiceId = String(voice.id);
    this.ttsCloudVoiceId = '';
    this.selectedVoiceKey = TtsVoiceCatalog.customVoiceKey(voice);
    this.saveSettings();
    HdsFeedback.showToast(`已启用 ${voice.name}`);
  }

  applyCloudVoice(voice: TtsVoiceInfo): void {
    if (!AccountSessionStore.isLoggedIn()) {
      HdsFeedback.showToast('请先登录华为账号后使用云端音色');
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
    HdsFeedback.showToast(`已启用 ${voice.name}`);
  }

  findCurrentCloudVoice(): TtsVoiceInfo | undefined {
    const id = (this.ttsCloudVoiceId || '').trim();
    if (!id) return undefined;
    return this.cloudVoices.find((voice: TtsVoiceInfo) => voice.id === id);
  }

  async downloadAndSelectVoice(voice: TtsVoiceOption): Promise<void> {
    if (this.downloadingVoiceKey) {
      HdsFeedback.showToast('正在下载音色，请稍候');
      return;
    }
    const key = TtsVoiceCatalog.voiceKey(voice);
    this.downloadingVoiceKey = key;
    this.downloadProgressText = '';
    try {
      HdsFeedback.showToast(`开始下载 ${voice.name}`);
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
        downloaded = TtsVoiceCatalog.markInstalled(voice);
        this.voices = this.applyInstalledOverrides(TtsVoiceCatalog.mergeWithDefault(this.voices.concat([downloaded])));
      }
      this.applyVoice(downloaded, true);
      HdsFeedback.showToast(`已启用 ${downloaded.name}`);
    } catch (error) {
      HdsFeedback.showToast(`音色下载失败：${this.shortErrorMessage(error as Object)}`);
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
      options.push(this.isLocallyInstalledVoice(voice) ? TtsVoiceCatalog.markInstalled(voice) : voice);
    }
    return options;
  }

  markVoiceInstalled(voice: TtsVoiceOption): void {
    const key = TtsVoiceCatalog.installedKey(voice);
    if (!key || this.installedVoiceKeyExists(key)) {
      return;
    }
    this.ttsInstalledVoiceKeys = this.ttsInstalledVoiceKeys ?
      `${this.ttsInstalledVoiceKeys}\n${key}` : key;
    this.saveSettings();
  }

  isLocallyInstalledVoice(voice: TtsVoiceOption): boolean {
    return this.installedVoiceKeyExists(TtsVoiceCatalog.installedKey(voice));
  }

  installedVoiceKeyExists(key: string): boolean {
    if (!key) {
      return false;
    }
    const keys = this.ttsInstalledVoiceKeys.split('\n');
    return keys.includes(key);
  }

  voiceTitle(voice: TtsVoiceOption): string {
    if (voice.status !== 'default' && this.isVoiceDownloading(voice)) {
      const progress = this.downloadProgressText ? ` · ${this.downloadProgressText}` : '';
      return `${voice.name} · 下载中${progress}`;
    }
    return TtsVoiceCatalog.voiceTitle(voice);
  }

  currentVoiceKey(): string {
    if (this.ttsCloudVoiceId) {
      return `cloud_${this.ttsCloudVoiceId}`;
    }
    const customVoice = this.findCurrentCustomVoice();
    if (customVoice) {
      return TtsVoiceCatalog.customVoiceKey(customVoice);
    }
    const matched = this.findCurrentVoice();
    return matched ? TtsVoiceCatalog.voiceKey(matched) :
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
      TtsVoiceCatalog.sameLanguage(voice.language || 'zh-CN', this.ttsLanguage || 'zh-CN');
  }

  findCurrentCustomVoice(): HttpTTS | undefined {
    const selectedId = (this.ttsCustomVoiceId || '').trim();
    if (!selectedId) {
      return undefined;
    }
    return this.customVoices.find((voice: HttpTTS) => String(voice.id) === selectedId);
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
      HdsFeedback.showToast('请输入音色 JSON URL');
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
      HdsFeedback.showToast(`导入失败：${this.shortErrorMessage(error as Object)}`);
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
      HdsFeedback.showToast(`导入失败：${this.shortErrorMessage(error as Object)}`);
    } finally {
      this.isImportingCustomVoices = false;
    }
  }

  importCustomVoicesFromJson(content: string): void {
    const incoming = SystemTtsReader.parseCustomVoices(content);
    if (incoming.length === 0) {
      HdsFeedback.showToast('未识别到有效自定义音色');
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
      this.selectedVoiceKey = TtsVoiceCatalog.customVoiceKey(incoming[0]);
    }
    this.saveSettings();
    HdsFeedback.showToast(`已导入 ${changed} 个自定义音色`);
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
      TtsVoiceCatalog.sameLanguage(voice.language || 'zh-CN', target.language || 'zh-CN') &&
      (!availableOnly || voice.available));
    if (exact) {
      return exact;
    }
    const sameModule = this.voices.find((voice: TtsVoiceOption) => voice.id === target.id &&
      voice.online === target.online && TtsVoiceCatalog.sameLanguage(voice.language || 'zh-CN', target.language || 'zh-CN') &&
      (!availableOnly || voice.available));
    if (sameModule) {
      return sameModule;
    }
    return this.voices.find((voice: TtsVoiceOption) => voice.id === target.id &&
      (!availableOnly || voice.available));
  }

  isVoiceDownloading(voice: TtsVoiceOption): boolean {
    return this.downloadingVoiceKey === TtsVoiceCatalog.voiceKey(voice);
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
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  ttsCommerceSection() {
    Column({ space: AppSpacing.LG }) {
      Row() {
        Text(this.accountLoggedIn ? '当前额度' : '登录后可查看额度并兑换')
          .fontSize(AppFontSize.BODY_LARGE)
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
            .fontSize(AppFontSize.BODY)
            .fontColor(this.accentColor())
            .padding({ left: AppSpacing.MD, right: AppSpacing.XXS, top: AppSpacing.SM, bottom: AppSpacing.SM })
            .onClick(() => {
              this.loadTtsCommerce();
            })
        }
      }
      .width('100%')

      if (this.accountLoggedIn) {
        Row({ space: AppSpacing.MD }) {
          this.ttsBalanceCard('标准音色', false)
          this.ttsBalanceCard('精品音色', true)
        }
        .width('100%')

        if (this.ttsWalletError) {
          Text(`${this.ttsWalletError}，请点击刷新`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
            .width('100%')
        }

        Text(`可用于兑换：${this.paidPoints} 充值点 · 赠送点 ${this.promoPoints} 仅可兑换主题`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
      } else {
        Text('请先在“我的-账号与点数”登录华为账号，再返回这里兑换在线朗读字数。')
          .fontSize(AppFontSize.CAPTION)
          .lineHeight(18)
          .fontColor(this.subTextColor())
          .width('100%')
      }

      ForEach(this.ttsCatalog.packages, (item: TtsPackageInfo) => {
        Row({ space: AppSpacing.MD }) {
          Column({ space: AppSpacing.XS }) {
            Text(`${item.tier === 'PREMIUM' ? '精品' : '标准'} · ${this.formatTtsChars(item.chars)}`)
              .fontSize(AppFontSize.BODY_LARGE)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryTextColor())
            Text(`${item.validDays} 天有效`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.redeemingTtsSku === item.sku ? '兑换中' : `${item.points} 点`)
            .height(34)
            .fontSize(AppFontSize.BODY)
            .enabled(!this.redeemingTtsSku && this.accountLoggedIn && this.paidPoints >= item.points)
            .fontColor(ThemeRuntime.onAccentColor())
            .backgroundColor(this.accentColor())
            .onClick(() => {
              this.redeemTtsPackage(item);
            })
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.MD, top: AppSpacing.MD, bottom: AppSpacing.MD })
        .borderRadius(ThemeRuntime.mediumRadius())
        .backgroundColor(this.inputColor())
      }, (item: TtsPackageInfo) => item.sku)

      Text('标准音色每次按 100 字向上取整，精品音色每次按 50 字向上取整；相同音色、文字和倍速会优先使用本地缓存。')
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(17)
        .fontColor(this.subTextColor())
        .width('100%')
    }
    .width('calc(100% - 24vp)')
    .padding(AppSpacing.XL)
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.XXXL })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  ttsBalanceCard(title: string, premium: boolean) {
    Column({ space: AppSpacing.XS }) {
      Text(title)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
      Text(this.ttsWalletLoaded
        ? this.formatTtsChars(premium ? this.ttsPremiumChars : this.ttsStandardChars)
        : '--')
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Text(this.ttsWalletLoaded
        ? ((premium ? this.ttsPremiumNextExpiry : this.ttsStandardNextExpiry)
          ? `${new Date((premium ? this.ttsPremiumNextExpiry : this.ttsStandardNextExpiry) as number)
            .toLocaleDateString()} 到期`
          : '暂无额度')
        : (this.ttsWalletError ? '同步失败' : '正在同步'))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.mediumRadius())
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
          HdsFeedback.showToast(message);
        }
      });
    } catch (e) {
      this.isPreviewing = false;
      HdsFeedback.showToast('试听失败');
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
        .fontSize(AppFontSize.BODY)
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
