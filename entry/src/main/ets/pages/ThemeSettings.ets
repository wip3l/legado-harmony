import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderThemeHelper } from '../utils/ReaderThemeHelper';
import { syncSystemBars } from '../utils/SystemBars';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { ThemeTrialManager } from '../utils/ThemeTrialManager';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../utils/CustomThemeSchemeStore';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeStartupCover } from '../components/ThemeStartupCover';
import { ReaderThemeBackground } from '../components/ReaderThemeBackground';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemeIds, ThemePack, ThemeVariant } from '../theme/ThemeModels';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AccountCommerceConfig } from '../account/AccountCommerceConfig';
import { AccountApiError, ThemeCatalogItem, ThemeCatalogResponse,
  ThemeEntitlement } from '../account/AccountCommerceModels';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { HuaweiAccountService } from '../account/HuaweiAccountService';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderResolvedRegexEmphasis
} from '../model/reader/ReaderRegexFontRule';
import fs from '@ohos.file.fs';
import { StartupCoverTextStore } from '../utils/StartupCoverTextStore';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';

@Entry
@Component
struct ThemeSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appThemeId') appThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appThemeBookCoverEnabled') themeBookCoverEnabled: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appCustomBaseThemeId') customBaseThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appCustomLightAccentColor') customLightAccentColor: string = '#007DFF';
  @StorageLink('appCustomDarkAccentColor') customDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appCustomLightButtonColor') customLightButtonColor: string = '#007DFF';
  @StorageLink('appCustomDarkButtonColor') customDarkButtonColor: string = '#3F8CFF';
  @StorageLink('appCustomLightReaderBackgroundColor') customLightReaderBackgroundColor: string = '#F7F1E3';
  @StorageLink('appCustomLightReaderTextColor') customLightReaderTextColor: string = '#2F261D';
  @StorageLink('appCustomLightReaderSubTextColor') customLightReaderSubTextColor: string = '#7A6F63';
  @StorageLink('appCustomLightReaderBackgroundAssetId') customLightReaderBackgroundAssetId: string = '';
  @StorageLink('appCustomLightReaderBackgroundImageFit') customLightReaderBackgroundImageFit: string = 'cover';
  @StorageLink('appCustomLightReaderContentTone') customLightReaderContentTone: string = 'light';
  @StorageLink('appCustomDarkReaderBackgroundColor') customDarkReaderBackgroundColor: string = '#1F2329';
  @StorageLink('appCustomDarkReaderTextColor') customDarkReaderTextColor: string = '#D8D8D8';
  @StorageLink('appCustomDarkReaderSubTextColor') customDarkReaderSubTextColor: string = '#9AA0A6';
  @StorageLink('appCustomDarkReaderBackgroundAssetId') customDarkReaderBackgroundAssetId: string = '';
  @StorageLink('appCustomDarkReaderBackgroundImageFit') customDarkReaderBackgroundImageFit: string = 'cover';
  @StorageLink('appCustomDarkReaderContentTone') customDarkReaderContentTone: string = 'dark';
  @StorageLink('readerLightThemeIndex') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') readerDarkThemeIndex: number = 0;
  @StorageLink('accountLoggedIn') accountLoggedIn: boolean = false;
  @StorageLink('accountPoints') accountPoints: number = 0;
  @StorageLink('accountEntitlementsRevision') accountEntitlementsRevision: number = 0;
  @StorageLink('themeTrialThemeId') trialThemeId: string = '';
  @StorageLink('themeTrialEndsAt') trialEndsAt: number = 0;
  @StorageLink('activeCustomThemeSchemeId') activeCustomSchemeId: string = '';
  @StorageLink('activeCustomThemeSchemeRevision') activeCustomSchemeRevision: number = 0;
  @StorageLink('customThemeSchemesRevision') @Watch('onCustomThemeSchemesRevisionChanged')
  customThemeSchemesRevision: number = 0;
  @StorageLink('startupCoverTextsRevision') startupCoverTextsRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State applyingThemeId: string = '';
  @State focusedThemeId: string = '';
  @State customSchemes: CustomThemeScheme[] = [];
  @State showCustomThemeActionMenu: boolean = false;
  @State showRenameCustomThemeDialog: boolean = false;
  @State showDeleteCustomThemeDialog: boolean = false;
  @State actionCustomSchemeId: string = '';
  @State renameCustomThemeName: string = '';
  @State contextMenuX: number = 24;
  @State contextMenuY: number = 120;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State showStartupTextDialog: boolean = false;
  @State startupTextThemeId: string = '';
  @State startupTextTitle: string = '';
  @State startupTextSubtitle: string = '';
  @State themeCatalog: ThemeCatalogItem[] = [];
  @State themeCatalogLoaded: boolean = false;
  private customSchemeRefreshSerial: number = 0;
  private themeListScroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    this.loadThemeSettings();
    this.refreshCustomSchemes();
    this.initializeAccount();
    this.refreshThemeCatalog();
    this.syncBars();
  }

  onPageShow(): void {
    ThemeTrialManager.stopIfExpired();
    this.refreshCustomSchemes();
    this.syncBars();
  }

  onCustomThemeSchemesRevisionChanged(): void {
    this.refreshCustomSchemes();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ space: 12, scroller: this.themeListScroller }) {
        // List padding is fixed to the viewport in ArkUI. Use real list items
        // for the safe-area gaps so they scroll away with the content.
        ListItem() {
          Row() {
          }
            .width('100%')
            .height(this.statusBarHeight + 58)
        }
        ListItem() {
          this.sectionTitle('默认主题')
        }
        ListItem() {
          this.themeCard(BuiltinThemeRegistry.findById(ThemeIds.PLAIN_DEFAULT))
        }
        ListItem() {
          this.customThemeSectionTitle()
        }
        ForEach(this.customSchemes, (scheme: CustomThemeScheme) => {
          if (deviceInfo.sdkApiVersion >= 26) {
            HdsListItem({
              customItemBuilder: () => {
                this.themeCard(this.customTheme(scheme), scheme.id)
              },
              swipeActionOptions: this.themeSwipeActions(scheme)
            })
          } else {
            ListItem() {
              Row() {
                this.themeCard(this.customTheme(scheme), scheme.id)
                Button('删除').fontSize(11).width(64).height(32).fontColor('#FFFFFF').backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode)).onClick(() => this.deleteCustomThemeFromSwipe(scheme))
              }
            }
          }
        }, (scheme: CustomThemeScheme) => `${scheme.id}_${scheme.revision}`)
        ListItem() {
          this.sectionTitle('更多主题')
        }
        ForEach(this.additionalBuiltinThemes(), (theme: ThemePack) => {
          ListItem() {
            this.themeCard(theme)
          }
        }, (theme: ThemePack) => theme.id)
        ListItem() {
          Row() {
          }
            .width('100%')
            .height(Math.max(20, this.navBarHeight + 8))
        }
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      // The list itself must own the system-safe-area expansion. Expanding
      // only its parent leaves the List viewport clipped to the safe area.
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({
        left: 14,
        right: 14
      })
      .scrollBar(BarState.Off)
      .backgroundColor(this.pageColor())

      // Pinned over the edge-to-edge list so scrolled content remains visible
      // beneath the status/title area instead of being clipped by it.
      this.titleBar()

      if (this.showCustomThemeActionMenu) {
        this.customThemeActionMenu()
      }
      if (this.showRenameCustomThemeDialog) {
        this.renameCustomThemeDialog()
      }
      if (this.showDeleteCustomThemeDialog) {
        this.deleteCustomThemeDialog()
      }
      if (this.showStartupTextDialog) {
        this.startupTextDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updateContextViewport(newValue);
    })
  }

  private themeSwipeActions(scheme: CustomThemeScheme): HdsSwipeActionOptions {
    return { icons: [{
      icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
      backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode),
      iconOptions: { accessibilityText: '删除主题' },
      onAction: () => this.deleteCustomThemeFromSwipe(scheme)
    }] };
  }

  async initializeAccount(): Promise<void> {
    try {
      await HuaweiAccountService.initialize(getContext(this));
      if (AccountSessionStore.isLoggedIn() && AccountCommerceConfig.isServerConfigured()) {
        await HuaweiAccountService.refresh(getContext(this));
      }
    } catch (e) {
      console.warn('同步主题权益失败:', e);
    }
  }

  async refreshThemeCatalog(): Promise<void> {
    if (!AccountCommerceConfig.isServerConfigured()) return;
    try {
      const response: ThemeCatalogResponse = await AccountCommerceApi.fetchThemeCatalog();
      this.themeCatalog = response.themes || [];
      this.themeCatalogLoaded = true;
    } catch (e) {
      // Keep the bundled 60-point/365-day offer when the device is offline or
      // is temporarily talking to an older server during a rolling upgrade.
      console.warn('同步主题目录失败，使用内置价格:', e);
    }
  }

  async loadThemeSettings(): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const theme = settings.themeId === ThemeIds.CUSTOM ?
        AppThemeSettingsStore.customTheme(settings, this.appDarkMode) :
        BuiltinThemeRegistry.findById(settings.themeId);
      if (settings.themeBookCoverEnabled && !this.themeHasBookCover(theme)) {
        settings.themeBookCoverEnabled = false;
        await AppThemeSettingsStore.save(getContext(this), settings);
      }
      AppThemeSettingsStore.applyToStorage(settings);
      this.appThemeId = settings.themeId;
      this.themeBookCoverEnabled = settings.themeBookCoverEnabled;
      const readerSettings = await ReaderSettingsStore.load(getContext(this));
      ReaderSettingsStore.applyToStorage(readerSettings);
    } catch (e) {
      console.warn('加载主题设置失败:', e);
    }
  }

  async refreshCustomSchemes(): Promise<void> {
    const serial = ++this.customSchemeRefreshSerial;
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const schemes = await CustomThemeSchemeStore.load(getContext(this), settings);
      if (serial === this.customSchemeRefreshSerial) {
        this.customSchemes = schemes;
      }
    } catch (e) {
      console.warn('加载自定义主题方案失败:', e);
    }
  }

  async selectTheme(themeId: string, customSchemeId: string = ''): Promise<void> {
    if (this.applyingThemeId) {
      return;
    }
    const customScheme = themeId === ThemeIds.CUSTOM ?
      CustomThemeSchemeStore.find(this.customSchemes, customSchemeId) : null;
    if (themeId === ThemeIds.CUSTOM && !customScheme) {
      return;
    }
    if (customScheme) {
      const unavailableStartupTheme = this.unavailableCustomStartupTheme(customScheme.settings);
      if (unavailableStartupTheme) {
        promptAction.showToast({ message: `启动封面主题「${unavailableStartupTheme}」尚未获取或已过期` });
        return;
      }
    }
    if (ThemeTrialManager.isActive()) {
      ThemeTrialManager.stop(getContext(this) as common.UIAbilityContext);
      this.appThemeId = AppStorage.get<string>('appThemeId') || AppThemeSettingsStore.DEFAULT_THEME_ID;
      this.themeBookCoverEnabled = AppStorage.get<boolean>('appThemeBookCoverEnabled') || false;
    }
    if (themeId === this.appThemeId && themeId !== ThemeIds.CUSTOM) {
      return;
    }
    const accessible = await this.ensureThemeAccess(themeId);
    if (!accessible) {
      return;
    }
    this.applyingThemeId = customSchemeId || themeId;
    try {
      const theme = customScheme ? this.customTheme(customScheme) : BuiltinThemeRegistry.findById(themeId);
      let enableThemeBookCover = false;
      if (this.themeHasBookCover(theme)) {
        const coverDialog = await promptAction.showDialog({
          title: `启用「${theme.name}」主题封面？`,
          message: '启用后，书架会忽略图书原封面，改用这套主题封面与配套书籍边框。之后可在本页随时关闭。',
          buttons: [
            { text: '保留原封面', color: this.subTextColor() },
            { text: '启用主题封面', color: this.accentColor() }
          ]
        });
        enableThemeBookCover = coverDialog.index === 1;
      }
      const previous: AppThemeSettings = await AppThemeSettingsStore.load(getContext(this));
      let settings: AppThemeSettings = AppThemeSettingsStore.activateTheme(themeId, previous);
      if (customScheme) {
        settings = AppThemeSettingsStore.applyCustomSnapshot(settings, customScheme.settings);
      }
      settings.themeBookCoverEnabled = enableThemeBookCover;
      AppThemeSettingsStore.applyToStorage(settings);
      await AppThemeSettingsStore.save(getContext(this), settings);
      if (customScheme) {
        await CustomThemeSchemeStore.setActiveScheme(getContext(this), customScheme);
        this.activeCustomSchemeId = customScheme.id;
        this.activeCustomSchemeRevision = customScheme.revision;
      }
      this.appThemeId = settings.themeId;
      this.themeBookCoverEnabled = settings.themeBookCoverEnabled;
      const readerSettings = await ReaderSettingsStore.switchThemeProfile(
        getContext(this), previous.themeId, settings.themeId);
      const layout = theme.readerLayout;
      await ReaderSettingsStore.saveLayoutSettings(getContext(this), layout.fontSize, layout.lineHeight,
        layout.paragraphSpacing, layout.marginLeft, layout.marginRight, layout.marginTop, layout.marginBottom,
        layout.letterSpacing);
      await ReaderSettingsStore.saveThemeSettings(getContext(this), ReaderThemeHelper.APP_THEME_INDEX,
        ReaderThemeHelper.APP_THEME_INDEX, readerSettings.lightCustomThemeBackgroundColor,
        readerSettings.lightCustomThemeTextColor, readerSettings.darkCustomThemeBackgroundColor,
        readerSettings.darkCustomThemeTextColor, this.appDarkMode, readerSettings.customThemesRaw);
      this.readerLightThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
      this.readerDarkThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
      this.focusedThemeId = '';
      await this.applyThemeFontWhenAvailable();
      this.refreshRecentReadCard();
      this.syncBars();
      promptAction.showToast({ message: `已应用「${theme.name}」主题` });
    } catch (e) {
      console.error('应用主题失败:', e);
      promptAction.showToast({ message: '应用主题失败，请稍后重试' });
    } finally {
      this.applyingThemeId = '';
    }
  }

  async ensureThemeAccess(themeId: string): Promise<boolean> {
    if (themeId === ThemeIds.CUSTOM || this.hasThemeAccess(themeId)) {
      return true;
    }
    const offer = this.themeOffer(themeId);
    if (this.themeCatalogLoaded && !offer) {
      promptAction.showToast({ message: '该主题暂未上架' });
      return false;
    }
    const pricePoints = offer?.pricePoints || AccountCommerceConfig.THEME_PRICE_POINTS;
    const validDays = offer?.validDays || AccountCommerceConfig.THEME_VALID_DAYS;
    if (!this.accountLoggedIn) {
      const loginDialog = await promptAction.showDialog({
        title: '登录后获取主题',
        message: `该主题需要 ${pricePoints} 点，获取后有效 ${validDays} 天。首次登录免费送 300 点。`,
        buttons: [
          { text: '取消', color: this.subTextColor() },
          { text: '去登录', color: this.accentColor() }
        ]
      });
      if (loginDialog.index === 1) {
        router.pushUrl({ url: 'pages/AccountCenter' });
      }
      return false;
    }
    const theme = BuiltinThemeRegistry.findById(themeId);
    const confirm = await promptAction.showDialog({
      title: `获取「${theme.name}」`,
      message: `将扣除 ${pricePoints} 点，主题有效期为 ${validDays} 天。有效期内可在所有已登录终端使用。`,
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: `确认 · ${pricePoints} 点`, color: this.accentColor() }
      ]
    });
    if (confirm.index !== 1) {
      return false;
    }
    try {
      await HuaweiAccountService.redeemTheme(getContext(this), themeId, pricePoints, validDays);
      promptAction.showToast({ message: `已获取「${theme.name}」，有效期 ${validDays} 天` });
      return true;
    } catch (e) {
      const error = e as AccountApiError;
      if (error.errorCode === 'THEME_OFFER_CHANGED') {
        await this.refreshThemeCatalog();
        promptAction.showToast({ message: '主题价格或有效期已更新，请重新确认' });
      } else if (error.errorCode === 'INSUFFICIENT_POINTS') {
        const recharge = await promptAction.showDialog({
          title: '点数不足',
          message: `当前有 ${this.accountPoints} 点，获取该主题需要 ${pricePoints} 点。`,
          buttons: [
            { text: '取消', color: this.subTextColor() },
            { text: '去充值', color: this.accentColor() }
          ]
        });
        if (recharge.index === 1) {
          router.pushUrl({ url: 'pages/AccountCenter' });
        }
      } else {
        promptAction.showToast({ message: error.message || '获取主题失败，请稍后重试' });
      }
      return false;
    }
  }

  themeOffer(themeId: string): ThemeCatalogItem | null {
    for (let index = 0; index < this.themeCatalog.length; index++) {
      const offer = this.themeCatalog[index];
      if (offer && offer.themeId === themeId && offer.pricePoints > 0 && offer.validDays > 0) {
        return offer;
      }
    }
    return null;
  }

  async setThemeBookCoverEnabled(enabled: boolean): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      settings.themeBookCoverEnabled = enabled;
      AppThemeSettingsStore.applyToStorage(settings);
      await AppThemeSettingsStore.save(getContext(this), settings);
      this.themeBookCoverEnabled = enabled;
      promptAction.showToast({ message: enabled ? '已启用主题封面与书籍边框' : '已恢复图书原封面' });
    } catch (e) {
      console.error('保存主题封面设置失败:', e);
      promptAction.showToast({ message: '保存主题封面设置失败' });
    }
  }

  async applyThemeFontWhenAvailable(): Promise<void> {
    const settings: ReaderSettings = await ReaderSettingsStore.load(getContext(this));
    if (settings.fontFilePath && this.fontFileExists(settings.fontFilePath)) {
      return;
    }
    try {
      getContext(this).getApplicationContext().setFont(ThemeRuntime.fontFamily());
    } catch (e) {
      console.warn('应用主题默认字体失败:', e);
    }
  }

  fontFileExists(filePath: string): boolean {
    if (!filePath) {
      return false;
    }
    try {
      return fs.accessSync(filePath);
    } catch (e) {
      return false;
    }
  }

  refreshRecentReadCard(): void {
    const context = getContext(this) as common.UIAbilityContext;
    RecentReadCardUpdater.reload(context).catch((e: Error) => {
      console.warn('主题切换后刷新最近阅读卡片失败:', e);
    });
  }

  customTheme(scheme: CustomThemeScheme): ThemePack {
    const theme = AppThemeSettingsStore.customTheme(scheme.settings, this.appDarkMode);
    theme.name = scheme.name;
    theme.description = '自由组合浅色与深色模式下的主题部件';
    return theme;
  }

  activeVariant(theme: ThemePack): ThemeVariant {
    return this.appDarkMode ? theme.dark : theme.light;
  }

  isSelected(theme: ThemePack, customSchemeId: string = ''): boolean {
    if (theme.id === ThemeIds.CUSTOM) {
      const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
      return this.appThemeId === ThemeIds.CUSTOM && this.activeCustomSchemeId === customSchemeId &&
        !!scheme && scheme.revision === this.activeCustomSchemeRevision;
    }
    return theme.id === this.appThemeId;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  titleBarSurfaceColor(): string {
    return ThemeRuntime.topBarColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('主题')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    // The status-bar inset belongs to the pinned title itself, avoiding an
    // additional opaque strip above it while keeping controls out of the
    // system status area.
    .height(56 + this.statusBarHeight)
    .padding({ top: this.statusBarHeight, right: 12 })
    .backgroundColor(this.titleBarSurfaceColor())
    .backdropBlur(ThemeRuntime.topBarBlur())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 2, top: 6, bottom: 0 })
  }

  @Builder
  customThemeSectionTitle() {
    Row({ space: 10 }) {
      Text(`自定义主题 · ${this.customSchemes.length}/${CustomThemeSchemeStore.MAX_SCHEMES}`)
        .fontSize(13)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
      Button('添加方案')
        .height(30)
        .fontSize(12)
        .fontColor(this.customSchemes.length < CustomThemeSchemeStore.MAX_SCHEMES ?
          '#FFFFFF' : this.subTextColor())
        .backgroundColor(this.customSchemes.length < CustomThemeSchemeStore.MAX_SCHEMES ?
          this.accentColor() : this.cardColor())
        .enabled(this.customSchemes.length < CustomThemeSchemeStore.MAX_SCHEMES)
        .onClick(() => {
          this.addCustomScheme();
        })
    }
    .width('100%')
    .padding({ left: 2, top: 6, bottom: 0 })
    .alignItems(VerticalAlign.Center)
  }

  async addCustomScheme(): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const added = await CustomThemeSchemeStore.add(getContext(this), settings);
      if (!added) {
        promptAction.showToast({ message: '最多只能创建 5 套自定义主题' });
        return;
      }
      await this.refreshCustomSchemes();
      promptAction.showToast({ message: `已添加「${added.name}」` });
    } catch (e) {
      console.error('添加自定义主题方案失败:', e);
      promptAction.showToast({ message: '添加方案失败，请稍后重试' });
    }
  }

  @Builder
  customThemeDeleteSwipeAction(scheme: CustomThemeScheme) {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
    .onClick(() => {
      this.deleteCustomThemeFromSwipe(scheme);
    })
  }

  @Builder
  customThemeActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#52000000' : '#26FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
        .onClick(() => this.closeCustomThemeActions())
      Column() {
        this.contextActionItem($r('sys.symbol.square_and_pencil'), '重命名', this.primaryTextColor(), () => {
          const scheme = this.actionCustomScheme();
          if (!scheme) return;
          this.renameCustomThemeName = scheme.name;
          this.showCustomThemeActionMenu = false;
          this.showRenameCustomThemeDialog = true;
        })
        this.contextActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => {
          this.showCustomThemeActionMenu = false;
          this.requestDeleteCustomTheme(this.actionCustomSchemeId);
        })
      }
      .width(148)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel')
      })
      .shadow({
        radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'),
        offsetY: ThemeRuntime.glassShadowOffsetY('panel')
      })
      .position({
        x: this.contextMenuLeft(148),
        y: this.contextMenuTop(104)
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  contextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([color])
        .width(24)
      Text(label)
        .fontSize(15)
        .fontColor(color)
        .layoutWeight(1)
    }
    .width('100%')
    .height(46)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  @Builder
  renameCustomThemeDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('重命名自定义主题')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        TextInput({ placeholder: '输入方案名称', text: this.renameCustomThemeName })
          .width('100%')
          .height(42)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .borderRadius(10)
          .onChange((value: string) => {
            this.renameCustomThemeName = value;
          })
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeRenameCustomThemeDialog())
          Button('保存', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.accentColor())
            .fontColor('#FFFFFF')
            .enabled(!!this.renameCustomThemeName.trim())
            .onClick(() => this.renameCustomTheme())
        }
        .width('100%')
      }
      .width('calc(100% - 48vp)')
      .constraintSize({ maxWidth: 360 })
      .padding(20)
      .borderRadius(ThemeRuntime.glassCornerRadius(18, 'panel'))
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel')
      })
      .shadow({
        radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'),
        offsetY: ThemeRuntime.glassShadowOffsetY('panel')
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.appDarkMode ? '#76000000' : '#52000000')
    .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
  }

  @Builder
  deleteCustomThemeDialog() {
    Column() {
      Column({ space: 14 }) {
        Text('删除自定义主题')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Text(`确定删除「${this.actionCustomScheme()?.name || '该方案'}」吗？此操作无法撤销。`)
          .fontSize(14)
          .fontColor(this.subTextColor())
          .width('100%')
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeDeleteCustomThemeDialog())
          Button('删除', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor('#E53935')
            .fontColor('#FFFFFF')
            .onClick(() => this.confirmDeleteCustomTheme())
        }
        .width('100%')
      }
      .width('calc(100% - 48vp)')
      .constraintSize({ maxWidth: 360 })
      .padding(20)
      .borderRadius(ThemeRuntime.glassCornerRadius(18, 'panel'))
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel')
      })
      .shadow({
        radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'),
        offsetY: ThemeRuntime.glassShadowOffsetY('panel')
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.appDarkMode ? '#76000000' : '#52000000')
    .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
  }

  @Builder
  startupTextDialog() {
    Column() {
      Column({ space: 14 }) {
        Text(`编辑「${BuiltinThemeRegistry.findById(this.startupTextThemeId).name}」启动文案`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Column({ space: 6 }) {
          Text('主标题')
            .fontSize(12)
            .fontColor(this.subTextColor())
            .width('100%')
          TextInput({ placeholder: '可留空', text: this.startupTextTitle })
            .width('100%')
            .height(42)
            .maxLength(24)
            .fontColor(this.primaryTextColor())
            .placeholderColor(this.subTextColor())
            .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
            .borderRadius(10)
            .onChange((value: string) => {
              this.startupTextTitle = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text('副标题')
            .fontSize(12)
            .fontColor(this.subTextColor())
            .width('100%')
          TextInput({ placeholder: '可留空', text: this.startupTextSubtitle })
            .width('100%')
            .height(42)
            .maxLength(48)
            .fontColor(this.primaryTextColor())
            .placeholderColor(this.subTextColor())
            .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
            .borderRadius(10)
            .onChange((value: string) => {
              this.startupTextSubtitle = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        Button('恢复默认文案', { type: ButtonType.Normal })
          .height(34)
          .fontSize(12)
          .fontColor(this.accentColor())
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .onClick(() => {
            this.startupTextTitle = '开源轻页';
            this.startupTextSubtitle = StartupCoverTextStore.defaultSubtitle(this.startupTextThemeId);
          })
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeStartupTextDialog())
          Button('保存', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.accentColor())
            .fontColor('#FFFFFF')
            .onClick(() => this.saveStartupText())
        }
        .width('100%')
      }
      .width('calc(100% - 48vp)')
      .constraintSize({ maxWidth: 360 })
      .padding(20)
      .borderRadius(ThemeRuntime.glassCornerRadius(18, 'panel'))
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel')
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.appDarkMode ? '#76000000' : '#52000000')
    .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
  }

  openStartupTextDialog(themeId: string): void {
    if (themeId === ThemeIds.PLAIN_DEFAULT || themeId === ThemeIds.CUSTOM) return;
    this.startupTextThemeId = themeId;
    this.startupTextTitle = StartupCoverTextStore.title(themeId, '开源轻页');
    this.startupTextSubtitle = StartupCoverTextStore.subtitle(
      themeId, StartupCoverTextStore.defaultSubtitle(themeId));
    this.showStartupTextDialog = true;
  }

  closeStartupTextDialog(): void {
    this.showStartupTextDialog = false;
    this.startupTextThemeId = '';
    this.startupTextTitle = '';
    this.startupTextSubtitle = '';
  }

  async saveStartupText(): Promise<void> {
    if (!this.startupTextThemeId) return;
    try {
      await StartupCoverTextStore.update(getContext(this), this.startupTextThemeId,
        this.startupTextTitle, this.startupTextSubtitle);
      this.closeStartupTextDialog();
      promptAction.showToast({ message: '启动文案已更新' });
    } catch (e) {
      console.error('保存启动文案失败:', e);
      promptAction.showToast({ message: '保存启动文案失败，请重试' });
    }
  }

  openCustomThemeActions(schemeId: string, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionCustomSchemeId = schemeId;
    this.showCustomThemeActionMenu = true;
  }

  closeCustomThemeActions(): void {
    this.showCustomThemeActionMenu = false;
    this.actionCustomSchemeId = '';
  }

  actionCustomScheme(): CustomThemeScheme | null {
    return CustomThemeSchemeStore.find(this.customSchemes, this.actionCustomSchemeId);
  }

  updateContextViewport(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
    if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
  }

  contextMenuLeft(menuWidth: number): number {
    return Math.max(12, Math.min(this.contextMenuX - 18, this.contextViewportWidth - menuWidth - 12));
  }

  contextMenuTop(menuHeight: number): number {
    const below = this.contextMenuY + 12;
    if (below + menuHeight <= this.contextViewportHeight - 12) return below;
    return Math.max(this.statusBarHeight + 8, this.contextMenuY - menuHeight - 12);
  }

  closeRenameCustomThemeDialog(): void {
    this.showRenameCustomThemeDialog = false;
    this.renameCustomThemeName = '';
    this.actionCustomSchemeId = '';
  }

  async renameCustomTheme(): Promise<void> {
    const scheme = this.actionCustomScheme();
    const name = this.renameCustomThemeName.trim();
    if (!scheme || !name) return;
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const renamed = await CustomThemeSchemeStore.rename(getContext(this), settings, scheme.id, name);
      if (!renamed) {
        promptAction.showToast({ message: '名称为空、重复或方案不存在' });
        return;
      }
      this.closeRenameCustomThemeDialog();
      await this.refreshCustomSchemes();
      promptAction.showToast({ message: '自定义主题已重命名' });
    } catch (e) {
      console.error('重命名自定义主题失败:', e);
      promptAction.showToast({ message: '重命名失败，请稍后重试' });
    }
  }

  requestDeleteCustomTheme(schemeId: string): void {
    if (this.customSchemes.length <= 1) {
      this.closeCustomThemeActions();
      promptAction.showToast({ message: '至少需要保留一套自定义主题' });
      return;
    }
    this.actionCustomSchemeId = schemeId;
    this.showDeleteCustomThemeDialog = true;
  }

  closeDeleteCustomThemeDialog(): void {
    this.showDeleteCustomThemeDialog = false;
    this.actionCustomSchemeId = '';
  }

  async confirmDeleteCustomTheme(): Promise<void> {
    const schemeId = this.actionCustomSchemeId;
    this.showDeleteCustomThemeDialog = false;
    await this.deleteCustomThemeScheme(schemeId);
  }

  async deleteCustomThemeFromSwipe(scheme: CustomThemeScheme): Promise<void> {
    await this.deleteCustomThemeScheme(scheme.id);
  }

  async deleteCustomThemeScheme(schemeId: string): Promise<void> {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    if (!scheme) return;
    if (this.customSchemes.length <= 1) {
      this.closeCustomThemeSwipeActions();
      promptAction.showToast({ message: '至少需要保留一套自定义主题' });
      return;
    }
    try {
      if (this.appThemeId === ThemeIds.CUSTOM && this.activeCustomSchemeId === schemeId) {
        await this.selectTheme(ThemeIds.PLAIN_DEFAULT);
        if (this.appThemeId === ThemeIds.CUSTOM) {
          return;
        }
      }
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const deleted = await CustomThemeSchemeStore.delete(getContext(this), settings, schemeId);
      if (!deleted) {
        promptAction.showToast({ message: '删除失败，至少需要保留一套方案' });
        return;
      }
      this.actionCustomSchemeId = '';
      await this.refreshCustomSchemes();
      promptAction.showToast({ message: `已删除「${scheme.name}」` });
    } catch (e) {
      console.error('删除自定义主题失败:', e);
      promptAction.showToast({ message: '删除失败，请稍后重试' });
    }
  }

  closeCustomThemeSwipeActions(): void {
    setTimeout(() => {
      try {
        this.themeListScroller.closeAllSwipeActions();
      } catch (e) {
        console.warn('关闭自定义主题滑动操作失败:', e);
      }
    }, 0);
  }

  @Builder
  themeBookCoverSetting(theme: ThemePack) {
    Row({ space: 12 }) {
      Stack() {
        Swiper() {
          ForEach(this.themeCoverSet(theme), (cover: ResourceStr, index: number) => {
            Image(cover)
              .width(42)
              .height(58)
              .objectFit(ImageFit.Fill)
              .draggable(false)
          }, (_cover: ResourceStr, index: number) => `active_cover_${index}`)
        }
        .width(42)
        .height(58)
        .autoPlay(this.themeCoverSet(theme).length > 1)
        .interval(2800)
        .indicator(false)
        .loop(true)
        Image(ThemeAssetRegistry.themeShelfFrame(theme.book.shelfFrameAssetId))
          .width(42)
          .height(58)
          .objectFit(ImageFit.Fill)
          .draggable(false)
      }
      .width(42)
      .height(58)

      Column({ space: 4 }) {
        Text('主题书籍封面')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeVariant(theme).colors.primaryTextColor)
        Text(this.themeBookCoverEnabled ? '书架已使用主题封面和配套边框' : '保留每本书原有封面')
          .fontSize(12)
          .fontColor(this.activeVariant(theme).colors.subTextColor)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.themeBookCoverEnabled })
        .selectedColor(this.accentColor())
        .enabled(!this.isTrialTheme(theme.id))
        .onChange((enabled: boolean) => {
          this.setThemeBookCoverEnabled(enabled);
        })
    }
    .width('100%')
    .padding(12)
    .alignItems(VerticalAlign.Center)
    .borderRadius(theme.radius.medium)
    .backgroundColor(this.activeVariant(theme).colors.inputColor)
  }

  @Builder
  themeCard(theme: ThemePack, customSchemeId: string = '') {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Image(ThemeAssetRegistry.themeLogo(theme.id))
          .width(42)
          .height(42)
          .borderRadius(theme.radius.medium)
          .objectFit(ImageFit.Contain)
          .draggable(false)

        Column({ space: 3 }) {
          Text(theme.name)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontFamily(theme.typography.appFontFamily)
            .fontColor(this.activeVariant(theme).colors.primaryTextColor)
          Text(theme.description)
            .fontSize(12)
            .fontColor(this.activeVariant(theme).colors.subTextColor)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.isTrialTheme(theme.id)) {
          Text('试用中')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(this.activeVariant(theme).colors.accentColor)
        } else if (this.isSelected(theme, customSchemeId)) {
          Text('已启用')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(this.activeVariant(theme).colors.accentColor)
        } else if (this.applyingThemeId === (customSchemeId || theme.id)) {
          Text('应用中')
            .fontSize(12)
            .fontColor(this.activeVariant(theme).colors.accentColor)
        } else if (this.isCustomSchemePending(theme, customSchemeId)) {
          Text('待应用')
            .fontSize(12)
            .fontColor(this.activeVariant(theme).colors.accentColor)
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(this.activeVariant(theme).colors.inputColor)
        } else if (theme.id !== ThemeIds.CUSTOM) {
          Text(this.themeAccessLabel(theme.id))
            .fontSize(11)
            .fontColor(this.hasThemeAccess(theme.id) ?
              this.activeVariant(theme).colors.accentColor : this.activeVariant(theme).colors.subTextColor)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(11)
            .backgroundColor(this.activeVariant(theme).colors.inputColor)
        }
      }
      .width('100%')

      this.themeVisualPreview(theme, customSchemeId)
      if (this.isSelected(theme, customSchemeId) && this.themeHasBookCover(theme)) {
        this.themeBookCoverSetting(theme)
      }
      Row({ space: 8 }) {
        if (!this.isSelected(theme, customSchemeId) && this.themeHasBookCover(theme)) {
          Stack() {
            Swiper() {
              ForEach(this.themeCoverSet(theme), (cover: ResourceStr, index: number) => {
                Image(cover)
                  .width(28)
                  .height(40)
                  .objectFit(ImageFit.Fill)
                  .draggable(false)
              }, (_cover: ResourceStr, index: number) => `${theme.id}_cover_${index}`)
            }
            .width(28)
            .height(40)
            .autoPlay(this.themeCoverSet(theme).length > 1)
            .interval(3000)
            .indicator(false)
            .loop(true)
            Image(ThemeAssetRegistry.themeShelfFrame(theme.book.shelfFrameAssetId))
              .width(28)
              .height(40)
              .objectFit(ImageFit.Fill)
              .draggable(false)
          }
          .width(28)
          .height(40)
        }
        Text(`${theme.readerLayout.fontSize} 字号 · ${theme.readerLayout.lineHeight} 行距 · ` +
          `${theme.readerLayout.marginLeft}/${theme.readerLayout.marginRight} 左右边距`)
          .fontSize(11)
          .fontColor(this.activeVariant(theme).colors.subTextColor)
          .layoutWeight(1)
      }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      if (theme.id === ThemeIds.CUSTOM) {
        Row() {
          Text('浅色 / 深色可分别组合全部主题部件')
            .fontSize(11)
            .fontColor(this.activeVariant(theme).colors.subTextColor)
            .layoutWeight(1)
          Button('编辑主题')
            .height(32)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .backgroundColor(this.activeVariant(theme).colors.buttonColor)
            .onClick(() => {
              router.pushUrl({
                url: 'pages/ThemeColorSettings',
                params: { schemeId: customSchemeId }
              });
            })
        }
        .width('100%')
      }
      if (this.focusedThemeId === theme.id && this.isThemeTrialCandidate(theme.id)) {
        Row({ space: 10 }) {
          Button(this.isTrialTheme(theme.id) ? '结束试用' : '试用5分钟')
            .height(34)
            .fontSize(12)
            .fontColor(this.activeVariant(theme).colors.accentColor)
            .backgroundColor(this.activeVariant(theme).colors.inputColor)
            .layoutWeight(1)
            .onClick(() => {
              if (this.isTrialTheme(theme.id)) {
                this.stopThemeTrial();
              } else {
                this.startThemeTrial(theme);
              }
            })
          Button(this.themeCatalogLoaded && !this.themeOffer(theme.id) ? '暂未上架' :
            `获取主题 · ${this.themeOffer(theme.id)?.pricePoints || AccountCommerceConfig.THEME_PRICE_POINTS}点`)
            .height(34)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .backgroundColor(this.activeVariant(theme).colors.buttonColor)
            .layoutWeight(1)
            .enabled(!this.themeCatalogLoaded || !!this.themeOffer(theme.id))
            .onClick(() => {
              this.acquireTheme(theme.id);
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(theme.radius.card)
    .backgroundColor(this.activeVariant(theme).colors.cardColor)
    .border({
      width: this.isThemeCardHighlighted(theme, customSchemeId) ? 2 : 1,
      color: this.isThemeCardHighlighted(theme, customSchemeId) ? this.activeVariant(theme).colors.accentColor :
        this.activeVariant(theme).colors.dividerColor
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (customSchemeId) {
            this.openCustomThemeActions(customSchemeId, event);
          }
        })
    )
    .onClick(() => {
      this.handleThemeCardClick(theme, customSchemeId);
    })
  }

  hasThemeAccess(themeId: string): boolean {
    return BuiltinThemeRegistry.isFree(themeId) ||
      (themeId === this.appThemeId && !this.isTrialTheme(themeId)) ||
      AccountSessionStore.hasValidEntitlement(themeId);
  }

  unavailableCustomStartupTheme(settings: AppThemeSettings): string {
    const lightThemeId = settings.customLightSources.startupThemeId;
    if (!BuiltinThemeRegistry.isFree(lightThemeId) &&
      !AccountSessionStore.hasValidEntitlement(lightThemeId)) {
      return BuiltinThemeRegistry.findById(lightThemeId).name;
    }
    const darkThemeId = settings.customDarkSources.startupThemeId;
    if (!BuiltinThemeRegistry.isFree(darkThemeId) &&
      !AccountSessionStore.hasValidEntitlement(darkThemeId)) {
      return BuiltinThemeRegistry.findById(darkThemeId).name;
    }
    return '';
  }

  isTrialTheme(themeId: string): boolean {
    return this.trialThemeId === themeId && this.trialEndsAt > Date.now() &&
      ThemeTrialManager.isActive(themeId);
  }

  isThemeTrialCandidate(themeId: string): boolean {
    return themeId !== ThemeIds.CUSTOM && !BuiltinThemeRegistry.isFree(themeId) &&
      !AccountSessionStore.hasValidEntitlement(themeId);
  }

  isThemeCardHighlighted(theme: ThemePack, customSchemeId: string = ''): boolean {
    return this.isSelected(theme, customSchemeId) || this.focusedThemeId === (customSchemeId || theme.id);
  }

  isCustomSchemePending(theme: ThemePack, customSchemeId: string): boolean {
    return theme.id === ThemeIds.CUSTOM && this.appThemeId === ThemeIds.CUSTOM &&
      this.activeCustomSchemeId === customSchemeId && !this.isSelected(theme, customSchemeId);
  }

  handleThemeCardClick(theme: ThemePack, customSchemeId: string = ''): void {
    if (this.isThemeTrialCandidate(theme.id)) {
      this.focusedThemeId = theme.id;
      return;
    }
    this.focusedThemeId = '';
    this.selectTheme(theme.id, customSchemeId);
  }

  async startThemeTrial(theme: ThemePack): Promise<void> {
    if (this.applyingThemeId) {
      return;
    }
    this.applyingThemeId = theme.id;
    try {
      await ThemeTrialManager.start(getContext(this) as common.UIAbilityContext, theme.id);
      this.appThemeId = theme.id;
      this.themeBookCoverEnabled = !!theme.book.coverAssetId;
      this.focusedThemeId = theme.id;
      this.syncBars();
      promptAction.showToast({ message: `「${theme.name}」已开始试用，5分钟后自动恢复` });
    } catch (e) {
      console.error('启动主题试用失败:', e);
      promptAction.showToast({ message: '主题试用启动失败，请稍后重试' });
    } finally {
      this.applyingThemeId = '';
    }
  }

  stopThemeTrial(): void {
    ThemeTrialManager.stop(getContext(this) as common.UIAbilityContext);
    this.appThemeId = AppStorage.get<string>('appThemeId') || AppThemeSettingsStore.DEFAULT_THEME_ID;
    this.themeBookCoverEnabled = AppStorage.get<boolean>('appThemeBookCoverEnabled') || false;
    this.syncBars();
  }

  async acquireTheme(themeId: string): Promise<void> {
    if (ThemeTrialManager.isActive()) {
      this.stopThemeTrial();
    }
    await this.selectTheme(themeId);
  }

  additionalBuiltinThemes(): ThemePack[] {
    const themes: ThemePack[] = [];
    for (const theme of BuiltinThemeRegistry.all()) {
      if (theme.id !== ThemeIds.PLAIN_DEFAULT) {
        themes.push(theme);
      }
    }
    return themes;
  }

  themeHasBookCover(theme: ThemePack): boolean {
    return !!theme.book.coverAssetId && this.themeCoverSet(theme).length > 0;
  }

  themeAccessLabel(themeId: string): string {
    if (BuiltinThemeRegistry.isFree(themeId)) {
      return '免费';
    }
    const entitlement: ThemeEntitlement | null = AccountSessionStore.entitlement(themeId);
    if (entitlement && entitlement.expiresAt > Date.now()) {
      return `有效至 ${this.formatDate(entitlement.expiresAt)}`;
    }
    return `${AccountCommerceConfig.THEME_PRICE_POINTS}点 / 1年`;
  }

  formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  @Builder
  themeVisualPreview(theme: ThemePack, customSchemeId: string = '') {
    Column({ space: 9 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        ThemeStartupCover({
          themeId: theme.startup.styleId,
          darkMode: this.appDarkMode,
          compact: true,
          animated: false,
          customImagePath: this.customPreviewStartupImage(customSchemeId),
          titleOverride: this.customPreviewStartupTitle(customSchemeId),
          subtitleOverride: this.customPreviewStartupSubtitle(customSchemeId),
          explicitText: !!customSchemeId,
          showTextEditButton: theme.id !== ThemeIds.PLAIN_DEFAULT && theme.id !== ThemeIds.CUSTOM,
          onEditText: () => this.openStartupTextDialog(theme.id)
        })
      }
      .width('100%')
      .height(126)
      .borderRadius(theme.radius.medium)
      .clip(true)

      Row({ space: 10 }) {
      Stack() {
        ReaderThemeBackground({
          surfaceColor: this.activeVariant(theme).reader.backgroundColor,
          backgroundAssetId: this.activeVariant(theme).reader.backgroundAssetId,
          compact: true
        })
        Text('阅读')
          .fontSize(13)
          .fontFamily(theme.typography.appFontFamily)
          .fontColor(this.activeVariant(theme).reader.textColor)
      }
      .width(76)
      .height(58)
      .borderRadius(theme.radius.medium)
      .clip(true)

      Column({ space: 7 }) {
        Row({ space: 6 }) {
          Blank()
            .height(8)
            .layoutWeight(1)
            .borderRadius(4)
            .backgroundColor(this.activeVariant(theme).colors.primaryTextColor)
          Blank()
            .width(32)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.activeVariant(theme).colors.subTextColor)
        }
        Text() {
          ContainerSpan() {
            ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle))
              .width(16)
              .height(16)
              .objectFit(ImageFit.Contain)
              .verticalAlign(ImageSpanAlignment.CENTER)
            Span(this.themeRegexPreviewLabel(theme))
              .fontSize(12)
              .fontColor(this.themeRegexPreview(theme).textColor)
              .textShadow(this.themeRegexPreviewShadow(theme))
              .decoration({ type: TextDecorationType.None })
            ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle))
              .width(16)
              .height(16)
              .objectFit(ImageFit.Contain)
              .verticalAlign(ImageSpanAlignment.CENTER)
              .rotate({ angle: 180 })
          }
          .textBackgroundStyle(this.themeRegexPreviewBackground(theme))
        }
        Row({ space: 5 }) {
          ForEach(['bookshelf', 'explore', 'search', 'mine'], (tabId: string) => {
            Image(ThemeAssetRegistry.navigationIcon(theme.navigation.iconPackId, tabId))
              .width(16)
              .height(16)
              .fillColor(this.activeVariant(theme).colors.accentColor)
              .draggable(false)
          }, (tabId: string) => `${theme.id}_${tabId}`)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .borderRadius(theme.radius.medium)
    .backgroundColor(this.activeVariant(theme).colors.inputColor)
  }

  customPreviewStartupImage(customSchemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme) return '';
    return this.appDarkMode ? scheme.settings.customDarkStartupImagePath :
      scheme.settings.customLightStartupImagePath;
  }

  customPreviewStartupTitle(customSchemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme) return '';
    return this.appDarkMode ? scheme.settings.customDarkStartupTitle :
      scheme.settings.customLightStartupTitle;
  }

  customPreviewStartupSubtitle(customSchemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme) return '';
    return this.appDarkMode ? scheme.settings.customDarkStartupSubtitle :
      scheme.settings.customLightStartupSubtitle;
  }

  themeRegexPreview(theme: ThemePack): ReaderResolvedRegexEmphasis {
    const variant = this.activeVariant(theme);
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = variant.regexEmphasis.emphasisMode;
    context.inheritedBubbleStyleId = variant.regexEmphasis.bubbleStyle;
    context.inheritedColor = variant.regexEmphasis.emphasisColor;
    context.inheritedTextColor = variant.regexEmphasis.emphasisTextColor;
    context.accentColor = variant.colors.accentColor;
    context.surfaceColor = variant.reader.backgroundColor;
    context.normalTextColor = variant.reader.textColor;
    context.darkMode = variant.reader.contentTone === 'dark';
    // Theme cards must preview the theme itself even before it is purchased.
    // Runtime entitlement checks are still enforced in the reader and the
    // regex-font settings page.
    return ReaderRegexBubbleStyleResolver.resolve(null, context, false);
  }

  themeCoverSet(theme: ThemePack): ResourceStr[] {
    return ThemeAssetRegistry.themeBookCovers(theme.book.coverAssetId);
  }

  themeRegexPreviewLabel(theme: ThemePack): string {
    const styleId = this.activeVariant(theme).regexEmphasis.bubbleStyle;
    if (styleId === 'classic-glass') return '经典玻璃';
    if (styleId === 'warm-scroll') return '暖纸卷轴';
    if (styleId === 'forest-dew') return '林间露珠';
    if (styleId === 'ink-brush') return '水墨笔触';
    if (styleId === 'neon-pulse') return '霓虹脉冲';
    if (styleId === 'strawberry-ribbon') return '草莓软框';
    if (styleId === 'crimson-stamp') return '赤墨印章';
    if (styleId === 'celadon-slip') return '青瓷纸笺';
    if (styleId === 'rose-frame') return '玫瑰信框';
    if (styleId === 'moon-halo') return '月光描边';
    if (styleId === 'sword-talisman') return '剑符';
    if (styleId === 'qingluan-jade') return '青鸾玉令';
    if (styleId === 'pipi-soft-paw') return '皮皮软爪';
    return '强调气泡';
  }

  themeRegexPreviewBackground(theme: ThemePack): TextBackgroundStyle {
    const style = this.themeRegexPreview(theme);
    if (!style.backgroundEnabled) return {};
    return {
      color: style.backgroundColor,
      radius: {
        topLeft: style.radiusTopLeft,
        topRight: style.radiusTopRight,
        bottomLeft: style.radiusBottomLeft,
        bottomRight: style.radiusBottomRight
      }
    };
  }

  themeRegexPreviewShadow(theme: ThemePack): ShadowOptions | ShadowOptions[] {
    const style = this.themeRegexPreview(theme);
    if (style.textShadows.length > 0) return style.textShadows;
    return {
      radius: style.textShadowRadius,
      color: style.textShadowColor,
      offsetX: style.textShadowOffsetX,
      offsetY: style.textShadowOffsetY
    };
  }

  themeRegexPreviewDecoration(theme: ThemePack): DecorationStyleInterface {
    const style = this.themeRegexPreview(theme);
    if (!style.decorationEnabled) return { type: TextDecorationType.None };
    return {
      type: TextDecorationType.Underline,
      color: style.decorationColor,
      style: this.themeRegexDecorationStyle(style.decorationStyleId)
    };
  }

  themeRegexDecorationStyle(styleId: string): TextDecorationStyle {
    if (styleId === 'double') return TextDecorationStyle.DOUBLE;
    if (styleId === 'dotted') return TextDecorationStyle.DOTTED;
    if (styleId === 'dashed') return TextDecorationStyle.DASHED;
    if (styleId === 'wavy') return TextDecorationStyle.WAVY;
    return TextDecorationStyle.SOLID;
  }

}
