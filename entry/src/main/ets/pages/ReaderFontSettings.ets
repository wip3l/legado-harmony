import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { AdaptiveColorPicker } from '../components/AdaptiveColorPicker';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { AdaptiveIconButton } from '../components/AdaptiveIconButton';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderRegexFontCodec,
  ReaderRegexFontRule,
  ReaderRegexLegacySettings,
  ReaderResolvedRegexEmphasis
} from '../model/reader/ReaderRegexFontRule';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemeAccessPolicy } from '../account/ThemeAccessPolicy';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

class ReaderCustomFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class ReaderCustomFontData {
  fonts: ReaderCustomFontItem[] = [];
}

class ReaderRegexPreviewSlice {
  text: string = '';
  highlighted: boolean = false;
  key: string = '';
}

class ReaderBubbleStyleOption {
  styleId: string = '';
  label: string = '';

  constructor(styleId: string, label: string) {
    this.styleId = styleId;
    this.label = label;
  }
}

@Entry
@Component
struct ReaderFontSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('accountEntitlementsRevision') accountEntitlementsRevision: number = 0;
  @State readerFontSize: number = 20;
  @State readerBodyFontMode: string = 'global';
  @State readerBodyFontFamily: string = '';
  @State readerTitleFontMode: string = 'global';
  @State readerTitleFontFamily: string = '';
  @State readerTitleFontSize: number = 22;
  @State readerRegexFontEnabled: boolean = false;
  @State readerRegexFontPattern: string = '';
  @State readerRegexFontMode: string = 'global';
  @State readerRegexFontFamily: string = '';
  @State readerRegexFontSize: number = 20;
  @State readerRegexShadowColor: string = '';
  @State readerRegexFontRulesRaw: string = '';
  @StorageLink('readerFontFamily') readerFontFamily: string = '';
  @StorageLink('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageLink('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State regexRules: ReaderRegexFontRule[] = [];
  @State regexHighlightRefreshKey: number = 0;
  @State activeRegexInputKey: string = '';
  private readerSettingsLoaded: boolean = false;
  private readerSettingsLoading: boolean = false;
  private closingReaderFontSettings: boolean = false;
  private latestReaderFontStyleSave: Promise<void> = Promise.resolve();
  private latestReaderFontStyleSettings: ReaderSettings | null = null;
  private readerFontStyleSaveTimerId: number = -1;

  aboutToAppear(): void {
    this.loadSettings();
    this.syncBars();
  }

  onPageShow(): void {
    if (!this.readerSettingsLoaded && !this.readerSettingsLoading) {
      this.loadSettings();
    }
    this.syncBars();
  }

  onBackPress(): boolean {
    this.closeReaderFontSettings();
    return true;
  }

  async closeReaderFontSettings(): Promise<void> {
    if (this.closingReaderFontSettings) {
      return;
    }
    this.closingReaderFontSettings = true;
    this.flushScheduledSettingsSave();
    // Every editing control saves its own updated snapshot. Re-encoding the component
    // state while the route is being removed can read a stale ForEach item and overwrite
    // the just-persisted regex switches, which is especially visible when this page was
    // opened above the still-mounted reader page.
    try {
      await this.latestReaderFontStyleSave;
    } catch (e) {
      console.warn('等待当前阅读字体设置保存失败:', e);
    }
    await ReaderSettingsStore.waitForReaderFontStyleSaves();
    if (this.latestReaderFontStyleSettings) {
      await ReaderSettingsStore.saveReaderFontStyleSettings(
        getContext(this),
        this.latestReaderFontStyleSettings
      );
      await ReaderSettingsStore.waitForReaderFontStyleSaves();
    }
    router.back();
  }

  async loadSettings(): Promise<void> {
    if (this.readerSettingsLoading) {
      return;
    }
    this.readerSettingsLoading = true;
    try {
      const settings = await ReaderSettingsStore.load(getContext(this));
      this.readerFontSize = settings.fontSize;
      this.readerBodyFontMode = settings.bodyFontMode;
      this.readerBodyFontFamily = settings.bodyFontFamily;
      this.readerTitleFontMode = settings.titleFontMode;
      this.readerTitleFontFamily = settings.titleFontFamily;
      this.readerTitleFontSize = settings.titleFontSize;
      this.readerRegexFontEnabled = settings.regexFontEnabled;
      this.readerRegexFontPattern = settings.regexFontPattern;
      this.readerRegexFontMode = settings.regexFontMode;
      this.readerRegexFontFamily = settings.regexFontFamily;
      this.readerRegexFontSize = settings.regexFontSize;
      this.readerRegexShadowColor = settings.regexShadowColor;
      this.readerRegexFontRulesRaw = settings.regexFontRulesRaw;
      this.regexRules = this.parseRegexRules(settings);
      this.bumpRegexHighlightRefresh();
      this.readerSettingsLoaded = true;
    } catch (e) {
      console.warn('加载阅读字体设置失败:', e);
    } finally {
      this.readerSettingsLoading = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          this.sectionTitle('正文字体设置')
          Column() {
            this.fontModeItem('字体类型', this.readerBodyFontMode, this.readerBodyFontFamily, (mode: string, family: string) => {
              this.readerBodyFontMode = mode;
              this.readerBodyFontFamily = family;
              this.saveSettings();
            })
            this.bodyFontSizeStepper()
            this.bodyPreviewItem()
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('标题字体设置')
          Column() {
            this.fontModeItem('字体类型', this.readerTitleFontMode, this.readerTitleFontFamily, (mode: string, family: string) => {
              this.readerTitleFontMode = mode;
              this.readerTitleFontFamily = family;
              this.saveSettings();
            })
            this.titleFontSizeStepper()
            this.titlePreviewItem()
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('正则字体设置')
          Column() {
            this.regexEnableSwitchItem()
            if (this.readerRegexFontEnabled) {
              this.regexTemplateActions()
              if (this.regexRules.length === 0) {
                this.emptyRegexRule()
              }
              ForEach(this.regexRules, (rule: ReaderRegexFontRule, index: number) => {
                this.regexRulePanel(rule, index, this.regexHighlightRefreshKey)
              }, (rule: ReaderRegexFontRule) => rule.id)
            }
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())
        }
        .width('100%')
        .padding({ top: 56 + this.statusBarHeight, bottom: 32 + this.navBarHeight })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)

      this.titleBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  saveSettings(regexRules: ReaderRegexFontRule[] = this.regexRules): void {
    if (!this.readerSettingsLoaded || this.closingReaderFontSettings) {
      return;
    }
    const settings = new ReaderSettings();
    settings.fontSize = this.readerFontSize;
    settings.bodyFontMode = this.normalizeFontMode(this.readerBodyFontMode);
    settings.bodyFontFamily = this.readerBodyFontFamily;
    settings.titleFontMode = this.normalizeFontMode(this.readerTitleFontMode);
    settings.titleFontFamily = this.readerTitleFontFamily;
    settings.titleFontSize = this.readerTitleFontSize;
    settings.regexFontEnabled = this.readerRegexFontEnabled;
    settings.regexFontPattern = this.readerRegexFontPattern;
    settings.regexFontMode = this.normalizeFontMode(this.readerRegexFontMode);
    settings.regexFontFamily = this.readerRegexFontFamily;
    settings.regexFontSize = this.readerRegexFontSize;
    settings.regexShadowColor = this.readerRegexShadowColor;
    const rulesRaw = this.encodeRegexRules(regexRules);
    this.readerRegexFontRulesRaw = rulesRaw;
    settings.regexFontRulesRaw = rulesRaw;
    this.latestReaderFontStyleSettings = settings;
    this.scheduleSettingsSave();
  }

  scheduleSettingsSave(): void {
    if (this.readerFontStyleSaveTimerId >= 0) {
      clearTimeout(this.readerFontStyleSaveTimerId);
    }
    this.readerFontStyleSaveTimerId = setTimeout(() => {
      this.readerFontStyleSaveTimerId = -1;
      this.persistLatestSettings();
    }, 120);
  }

  flushScheduledSettingsSave(): void {
    if (this.readerFontStyleSaveTimerId >= 0) {
      clearTimeout(this.readerFontStyleSaveTimerId);
      this.readerFontStyleSaveTimerId = -1;
      this.persistLatestSettings();
    }
  }

  persistLatestSettings(): void {
    if (!this.latestReaderFontStyleSettings) return;
    this.latestReaderFontStyleSave = ReaderSettingsStore.saveReaderFontStyleSettings(
      getContext(this), this.latestReaderFontStyleSettings);
    this.latestReaderFontStyleSave.catch((e: Error) => {
      console.warn('保存阅读字体设置失败:', e);
    });
  }

  setBodyFontSize(value: number): void {
    this.readerFontSize = Math.max(14, Math.min(Math.round(value), 50));
    this.saveSettings();
  }

  setTitleFontSize(value: number): void {
    this.readerTitleFontSize = Math.max(14, Math.min(Math.round(value), 50));
    this.saveSettings();
  }

  parseRegexRules(settings: ReaderSettings): ReaderRegexFontRule[] {
    const legacy = new ReaderRegexLegacySettings();
    legacy.pattern = settings.regexFontPattern;
    legacy.fontMode = settings.regexFontMode;
    legacy.fontFamily = settings.regexFontFamily;
    legacy.fontSize = settings.regexFontSize;
    legacy.shadowColor = settings.regexShadowColor;
    return ReaderRegexFontCodec.decode(settings.regexFontRulesRaw || this.readerRegexFontRulesRaw, legacy);
  }

  encodeRegexRules(rules: ReaderRegexFontRule[]): string {
    return ReaderRegexFontCodec.encode(rules);
  }

  newRuleId(): string {
    return ReaderRegexFontCodec.newRuleId();
  }

  addRegexRule(name: string, pattern: string): void {
    const rule = new ReaderRegexFontRule();
    rule.id = this.newRuleId();
    rule.name = name;
    rule.pattern = pattern;
    rule.fontMode = 'global';
    rule.fontSize = this.readerRegexFontSize || this.readerFontSize;
    rule.emphasisMode = 'inherit';
    rule.bubbleStyleId = 'inherit';
    rule.emphasisColor = '';
    rule.highlightColorEnabled = false;
    rule.shadowColor = '';
    rule.expanded = true;
    this.regexRules = [...this.regexRules, rule];
    this.bumpRegexHighlightRefresh();
    this.saveSettings();
  }

  updateRegexRule(index: number, updater: (rule: ReaderRegexFontRule) => void): void {
    const next = this.regexRules.slice();
    if (index < 0 || index >= next.length) {
      return;
    }
    const source = next[index];
    const rule = ReaderRegexFontCodec.cloneRule(source);
    updater(rule);
    next[index] = rule;
    this.regexRules = next;
    this.bumpRegexHighlightRefresh();
    this.saveSettings(next);
  }

  updateRegexRuleById(ruleId: string, updater: (rule: ReaderRegexFontRule) => void): void {
    for (let i = 0; i < this.regexRules.length; i++) {
      if (this.regexRules[i].id === ruleId) {
        this.updateRegexRule(i, updater);
        return;
      }
    }
  }

  removeRegexRule(index: number): void {
    const next = this.regexRules.slice();
    if (index < 0 || index >= next.length) {
      return;
    }
    next.splice(index, 1);
    this.regexRules = next;
    this.bumpRegexHighlightRefresh();
    this.saveSettings();
  }

  bumpRegexHighlightRefresh(): void {
    this.regexHighlightRefreshKey = this.regexHighlightRefreshKey + 1;
  }

  regexInputKey(ruleId: string, field: string): string {
    return `${ruleId}:${field}`;
  }

  setRegexInputEditing(ruleId: string, field: string, editing: boolean): void {
    const key = this.regexInputKey(ruleId, field);
    if (editing) {
      this.activeRegexInputKey = key;
      return;
    }
    if (this.activeRegexInputKey === key) {
      this.activeRegexInputKey = '';
    }
  }

  isRegexInputEditing(ruleId: string, field: string): boolean {
    return this.activeRegexInputKey === this.regexInputKey(ruleId, field);
  }

  normalizeFontMode(mode: string): string {
    if (mode === 'system' || mode === 'custom') {
      return mode;
    }
    return 'global';
  }

  fontOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '跟随全局字体' }, { value: '系统字体' }];
    for (const item of this.customFonts()) {
      options.push({ value: item.sourceName || item.familyName || '自定义字体' });
    }
    return options;
  }

  selectedFontIndex(mode: string, family: string): number {
    if (mode === 'system') {
      return 1;
    }
    if (mode === 'custom') {
      const fonts = this.customFonts();
      for (let i = 0; i < fonts.length; i++) {
        const normalizedFamily = fonts[i].filePath ?
          ReaderFontHelper.normalizeFontFamily(fonts[i].filePath) : fonts[i].familyName;
        if (fonts[i].familyName === family || normalizedFamily === family) {
          return i + 2;
        }
      }
    }
    return 0;
  }

  selectedFontValue(mode: string, family: string): string {
    const options = this.fontOptions();
    const index = this.selectedFontIndex(mode, family);
    if (index >= 0 && index < options.length) {
      return String(options[index].value);
    }
    return '跟随全局字体';
  }

  customFonts(): ReaderCustomFontItem[] {
    const raw = (this.readerCustomFontsRaw || '').trim();
    if (!raw) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as ReaderCustomFontData | ReaderCustomFontItem[];
      const source = Array.isArray(parsed) ? parsed as ReaderCustomFontItem[] : ((parsed as ReaderCustomFontData).fonts || []);
      const result: ReaderCustomFontItem[] = [];
      for (const item of source) {
        if (!item || !item.familyName) {
          continue;
        }
        const font = new ReaderCustomFontItem();
        font.familyName = item.familyName;
        font.filePath = item.filePath || '';
        font.sourceName = ReaderFontHelper.resolveDisplayName(
          item.sourceName || item.familyName, font.filePath);
        result.push(font);
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  modeAndFamilyByIndex(index: number): string[] {
    if (index === 1) {
      return ['system', ''];
    }
    if (index >= 2) {
      const fonts = this.customFonts();
      const fontIndex = index - 2;
      if (fontIndex >= 0 && fontIndex < fonts.length) {
        return ['custom', this.registerCustomFont(fonts[fontIndex]) || fonts[fontIndex].familyName];
      }
    }
    return ['global', ''];
  }

  registerCustomFont(font: ReaderCustomFontItem): string {
    if (!font || !font.filePath) {
      return font ? font.familyName : '';
    }
    const item = new ReaderFontItem();
    item.familyName = font.familyName || ReaderFontHelper.normalizeFontFamily(font.filePath);
    item.filePath = font.filePath;
    item.sourceName = ReaderFontHelper.resolveDisplayName(font.sourceName, font.filePath);
    const result = ReaderFontHelper.registerFont(this.getUIContext(), item);
    return result.registered ? result.familyName : item.familyName;
  }

  resolveCustomFontFamily(family: string): string {
    if (!family) {
      return '';
    }
    const fonts = this.customFonts();
    for (const item of fonts) {
      const stableFamily = item.filePath ? ReaderFontHelper.normalizeFontFamily(item.filePath) : item.familyName;
      if (item.familyName === family || stableFamily === family) {
        return this.registerCustomFont(item) || stableFamily || family;
      }
    }
    return family;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  settingsDividerColor(): string {
    return this.appDarkMode ? '#24FFFFFF' : '#14000000';
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

  /**
   * Keep the font selectors on this page on the same menu material.  HDS
   * Select menus otherwise inherit a system shadow that can differ between
   * the top-level font rows and the nested regex rule rows.
   */
  selectMenuMaterial() {
    return ImmersiveMaterialRuntime.selectMenuMaterial();
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => this.closeReaderFontSettings() })
      Text('阅读字体')
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
  fontModeItem(title: string, mode: string, family: string, onChange: (mode: string, family: string) => void) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Select(this.fontOptions())
        .selected(this.selectedFontIndex(mode, family))
        .value(this.selectedFontValue(mode, family))
        .font({ size: 14 })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .divider(null)
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .menuSystemMaterial(this.selectMenuMaterial())
        .onSelect((index: number) => {
          const result = this.modeAndFamilyByIndex(index);
          onChange(result[0], result[1]);
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  bodyFontSizeStepper() {
    Row({ space: 8 }) {
      Text('字体大小')
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      this.fontSizeStepButton($r('sys.symbol.minus'), '减小正文字体', this.readerFontSize > 14, () => {
        this.setBodyFontSize(this.readerFontSize - 1);
      })
      Text(`${this.readerFontSize}sp`)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .width(52)
        .height(36)
        .textAlign(TextAlign.Center)
      this.fontSizeStepButton($r('sys.symbol.plus'), '增大正文字体', this.readerFontSize !== 50, () => {
        this.setBodyFontSize(this.readerFontSize + 1);
      })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  titleFontSizeStepper() {
    Row({ space: 8 }) {
      Text('字体大小')
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      this.fontSizeStepButton($r('sys.symbol.minus'), '减小标题字体', this.readerTitleFontSize > 14, () => {
        this.setTitleFontSize(this.readerTitleFontSize - 1);
      })
      Text(`${this.readerTitleFontSize}sp`)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .width(52)
        .height(36)
        .textAlign(TextAlign.Center)
      this.fontSizeStepButton($r('sys.symbol.plus'), '增大标题字体', this.readerTitleFontSize !== 50, () => {
        this.setTitleFontSize(this.readerTitleFontSize + 1);
      })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  fontSizeStepButton(icon: Resource, accessibilityText: string, enabled: boolean, action: () => void) {
    AdaptiveIconButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      buttonEnabled: enabled,
      buttonSize: 34,
      iconSize: 17,
      fillColor: this.inputColor(),
      iconColor: this.primaryTextColor(),
      disabledIconColor: this.subTextColor(),
      action: action
    })
  }

  @Builder
  regexTemplateActions() {
    Column({ space: 8 }) {
      Text('添加规则')
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Row({ space: 8 }) {
        Button('对话')
          .fontSize(13)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.addRegexRule('对话', '“[^”\\n]*”|「[^」\\n]*」|『[^』\\n]*』|"[^"\\n]*"');
          })
        Button('关键字匹配')
          .fontSize(13)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.addRegexRule('关键字匹配', '关键词');
          })
        Button('空白规则')
          .fontSize(13)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.addRegexRule('正则规则', '');
          })
      }
      .width('100%')
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  @Builder
  emptyRegexRule() {
    Text('暂无正则规则')
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('calc(100% - 32vp)')
      .padding({ left: 0, right: 0, top: 10, bottom: 10 })
      .margin({ left: 16, right: 16 })
      .backgroundColor(Color.Transparent)
      .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  @Builder
  regexRulePanel(rule: ReaderRegexFontRule, index: number, refreshKey: number) {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text(rule.name || `规则${index + 1}`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(rule.pattern || '未设置正则表达式')
            .fontSize(12)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button(this.isRegexRuleExpanded(index, refreshKey) ? '收起' : '展开')
          .fontSize(13)
          .fontColor(this.primaryTextColor())
          .backgroundColor(this.inputColor())
          .height(32)
          .onClick(() => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
              target.expanded = !target.expanded;
            });
          })
        Button('删除')
          .fontSize(13)
          .fontColor('#E53935')
          .backgroundColor(this.inputColor())
          .height(32)
          .onClick(() => {
            this.removeRegexRule(index);
          })
      }
      .width('100%')

      if (this.isRegexRuleExpanded(index, refreshKey)) {
        TextInput({ text: rule.name, placeholder: '规则名称' })
          .fontSize(14)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(8)
          .onEditChange((isEditing: boolean) => {
            this.setRegexInputEditing(rule.id, 'name', isEditing);
          })
          .onChange((value: string) => {
            if (!this.isRegexInputEditing(rule.id, 'name')) {
              return;
            }
            this.updateRegexRuleById(rule.id, (target: ReaderRegexFontRule) => {
              target.name = value;
            });
          })

        TextInput({ text: rule.pattern, placeholder: '正则表达式' })
          .fontSize(14)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(8)
          .onEditChange((isEditing: boolean) => {
            this.setRegexInputEditing(rule.id, 'pattern', isEditing);
          })
          .onChange((value: string) => {
            if (!this.isRegexInputEditing(rule.id, 'pattern')) {
              return;
            }
            this.updateRegexRuleById(rule.id, (target: ReaderRegexFontRule) => {
              target.pattern = value;
            });
          })

        this.compactFontModeItem('字体类型', rule.fontMode, rule.fontFamily, (mode: string, family: string) => {
          this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
            target.fontMode = mode;
            target.fontFamily = family;
          });
        })
        this.regexFontSizeStepper(index)

        this.regexEmphasisSettings(index, refreshKey)

        this.regexRulePreviewItem(index, refreshKey)
      }
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  @Builder
  bodyPreviewItem() {
    Column({ space: 8 }) {
      Text('正文预览')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .width('100%')
      Text('这是一段阅读正文预览，文字会跟随当前正文字体设置显示。')
        .fontSize(this.readerFontSize)
        .fontFamily(this.bodyPreviewFontFamily())
        .fontColor(this.primaryTextColor())
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  @Builder
  titlePreviewItem() {
    Column({ space: 8 }) {
      Text('标题预览')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .width('100%')
      Text('第一章 风起时')
        .fontSize(this.readerTitleFontSize)
        .fontFamily(this.titlePreviewFontFamily())
        .fontColor(this.primaryTextColor())
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  previewFontFamily(mode: string, family: string): string {
    if (mode === 'system') {
      return this.systemPreviewFontFamily();
    }
    if (mode === 'custom' && family) {
      return this.resolveCustomFontFamily(family);
    }
    return this.readerFontFamily || ThemeRuntime.fontFamily() || this.systemPreviewFontFamily();
  }

  bodyPreviewFontFamily(): string {
    return this.previewFontFamily(this.readerBodyFontMode, this.readerBodyFontFamily);
  }

  systemPreviewFontFamily(): string {
    return this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext()) || '';
  }

  titlePreviewFontFamily(): string {
    if (this.readerTitleFontMode === 'global' && !this.readerTitleFontFamily) {
      return this.previewFontFamily('global', '');
    }
    return this.previewFontFamily(this.readerTitleFontMode, this.readerTitleFontFamily);
  }

  normalizeColorInput(color: string, fallback: string): string {
    const value = (color || '').trim();
    if (/^#[0-9a-fA-F]{6}$/.test(value)) {
      return value.toUpperCase();
    }
    if (/^[0-9a-fA-F]{6}$/.test(value)) {
      return `#${value}`.toUpperCase();
    }
    return fallback;
  }

  regexRuleAt(index: number): ReaderRegexFontRule {
    if (index >= 0 && index < this.regexRules.length) {
      return this.regexRules[index];
    }
    return new ReaderRegexFontRule();
  }

  isRegexRuleExpanded(index: number, refreshKey: number): boolean {
    const key = refreshKey >= 0 ? true : true;
    return this.regexRuleAt(index).expanded && key;
  }

  regexPreviewText(rule: ReaderRegexFontRule): string {
    if (rule.name === '对话') {
      return '他说：“你好。”她点头说：「走吧。」';
    }
    if (rule.name === '关键字匹配') {
      return `这里包含${this.regexPreviewKeyword(rule.pattern)}，命中后会使用当前正则字体。`;
    }
    if (rule.pattern.trim()) {
      return `命中示例：${rule.pattern}`;
    }
    return '正则规则预览文本';
  }

  regexPreviewKeyword(pattern: string): string {
    let value = (pattern || '').trim();
    if (!value) {
      return '关键词';
    }
    const firstKeyword = value.split('|')[0].trim();
    if (firstKeyword) {
      value = firstKeyword;
    }
    value = value.replace(/\\b/g, '').replace(/^\^/, '').replace(/\$$/, '');
    return value || '关键词';
  }

  regexPreviewSlices(index: number, refreshKey: number): ReaderRegexPreviewSlice[] {
    const rule = this.regexRuleAt(index);
    const text = this.regexPreviewText(rule);
    const keySeed = refreshKey >= 0 ? refreshKey : 0;
    if (!rule.pattern.trim()) {
      return [this.previewSlice(text, false, `preview_plain_${keySeed}`)];
    }
    try {
      const regex = new RegExp(rule.pattern, 'g');
      const result: ReaderRegexPreviewSlice[] = [];
      let cursor = 0;
      let count = 0;
      let match = regex.exec(text);
      while (match && match.index >= 0) {
        const start = Math.max(cursor, match.index);
        const end = Math.max(start, Math.min(text.length, match.index + (match[0] || '').length));
        if (end <= start) {
          if (start >= text.length || regex.lastIndex >= text.length) {
            break;
          }
          regex.lastIndex = Math.max(regex.lastIndex + 1, start + 1);
          match = regex.exec(text);
          continue;
        }
        if (start > cursor) {
          result.push(this.previewSlice(text.substring(cursor, start), false, `preview_plain_${keySeed}_${cursor}_${start}`));
        }
        result.push(this.previewSlice(text.substring(start, end), true, `preview_hit_${keySeed}_${start}_${end}_${count}`));
        cursor = end;
        count++;
        regex.lastIndex = Math.max(regex.lastIndex, end);
        match = regex.exec(text);
      }
      if (result.length === 0) {
        return [this.previewSlice(text, false, `preview_miss_${keySeed}`)];
      }
      if (cursor < text.length) {
        result.push(this.previewSlice(text.substring(cursor), false, `preview_plain_${keySeed}_${cursor}_${text.length}`));
      }
      return result;
    } catch (e) {
      return [this.previewSlice('正则表达式无效', false, `preview_error_${keySeed}`)];
    }
  }

  previewSlice(text: string, highlighted: boolean, key: string): ReaderRegexPreviewSlice {
    const slice = new ReaderRegexPreviewSlice();
    slice.text = text;
    slice.highlighted = highlighted;
    slice.key = key;
    return slice;
  }

  themeRegexEmphasisMode(): string {
    return ThemeRuntime.regexEmphasisMode();
  }

  themeRegexBubbleStyleId(): string {
    return ThemeRuntime.regexBubbleStyle();
  }

  themeRegexEmphasisColor(): string {
    return ThemeRuntime.regexEmphasisColor(this.appDarkMode);
  }

  regexEmphasisContext(): ReaderRegexEmphasisContext {
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = this.themeRegexEmphasisMode();
    context.inheritedBubbleStyleId = this.themeRegexBubbleStyleId();
    context.inheritedColor = this.themeRegexEmphasisColor();
    context.inheritedTextColor = ThemeRuntime.regexEmphasisTextColor(this.appDarkMode);
    context.accentColor = this.accentColor();
    context.surfaceColor = this.cardColor();
    context.normalTextColor = this.primaryTextColor();
    context.darkMode = this.appDarkMode;
    return context;
  }

  resolvedRegexEmphasis(index: number): ReaderResolvedRegexEmphasis {
    return ReaderRegexBubbleStyleResolver.resolve(this.regexRuleAt(index), this.regexEmphasisContext());
  }

  regexPreviewTextColor(highlighted: boolean, index: number): string {
    return highlighted ? this.resolvedRegexEmphasis(index).textColor : this.primaryTextColor();
  }

  regexPreviewBackgroundStyle(highlighted: boolean, index: number): TextBackgroundStyle {
    const style = this.resolvedRegexEmphasis(index);
    if (!highlighted || !style.backgroundEnabled) {
      return {};
    }
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

  regexPreviewTextShadow(highlighted: boolean, index: number): ShadowOptions | ShadowOptions[] {
    const style = this.resolvedRegexEmphasis(index);
    if (!highlighted) {
      return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
    }
    if (style.textShadows.length > 0) {
      return style.textShadows;
    }
    return {
      radius: style.textShadowRadius,
      color: style.textShadowColor,
      offsetX: style.textShadowOffsetX,
      offsetY: style.textShadowOffsetY
    };
  }

  regexPreviewDecoration(highlighted: boolean, index: number): DecorationStyleInterface {
    if (!highlighted) {
      return { type: TextDecorationType.None };
    }
    const style = this.resolvedRegexEmphasis(index);
    if (!style.decorationEnabled) {
      return { type: TextDecorationType.None };
    }
    return {
      type: TextDecorationType.Underline,
      color: style.decorationColor,
      style: this.regexDecorationStyle(style.decorationStyleId)
    };
  }

  regexDecorationStyle(styleId: string): TextDecorationStyle {
    if (styleId === 'double') return TextDecorationStyle.DOUBLE;
    if (styleId === 'dotted') return TextDecorationStyle.DOTTED;
    if (styleId === 'dashed') return TextDecorationStyle.DASHED;
    if (styleId === 'wavy') return TextDecorationStyle.WAVY;
    return TextDecorationStyle.SOLID;
  }

  shouldUseRegexPreviewDecoration(slice: ReaderRegexPreviewSlice, index: number): boolean {
    if (!slice.highlighted) {
      return false;
    }
    const style = this.resolvedRegexEmphasis(index);
    return style.bubbleDecorationEnabled && ThemeAssetRegistry.hasRegexBubbleCap(style.bubbleStyleId);
  }

  regexPreviewBubbleStyleId(index: number): string {
    return this.resolvedRegexEmphasis(index).bubbleStyleId;
  }

  regexPreviewBubbleCapSize(index: number): number {
    return Math.max(15, Math.min(22, this.regexRuleAt(index).fontSize * 0.72));
  }

  @Builder
  regexPreviewSliceItem(slice: ReaderRegexPreviewSlice, index: number) {
    if (this.shouldUseRegexPreviewDecoration(slice, index)) {
      ContainerSpan() {
        ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.regexPreviewBubbleStyleId(index)))
          .width(this.regexPreviewBubbleCapSize(index))
          .height(this.regexPreviewBubbleCapSize(index))
          .objectFit(ImageFit.Contain)
          .verticalAlign(ImageSpanAlignment.CENTER)
        Span(slice.text)
          .fontSize(this.regexRuleAt(index).fontSize)
          .fontFamily(this.previewFontFamily(this.regexRuleAt(index).fontMode, this.regexRuleAt(index).fontFamily))
          .fontColor(this.regexPreviewTextColor(true, index))
          .textShadow(this.regexPreviewTextShadow(true, index))
          .decoration(this.regexPreviewDecoration(true, index))
        ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.regexPreviewBubbleStyleId(index)))
          .width(this.regexPreviewBubbleCapSize(index))
          .height(this.regexPreviewBubbleCapSize(index))
          .objectFit(ImageFit.Contain)
          .verticalAlign(ImageSpanAlignment.CENTER)
          .rotate({ angle: 180 })
      }
      .textBackgroundStyle(this.regexPreviewBackgroundStyle(true, index))
    } else {
      Span(slice.text)
        .fontSize(slice.highlighted ? this.regexRuleAt(index).fontSize : this.readerFontSize)
        .fontFamily(slice.highlighted ?
          this.previewFontFamily(this.regexRuleAt(index).fontMode, this.regexRuleAt(index).fontFamily) :
          this.previewFontFamily(this.readerBodyFontMode, this.readerBodyFontFamily))
        .fontColor(this.regexPreviewTextColor(slice.highlighted, index))
        .textBackgroundStyle(this.regexPreviewBackgroundStyle(slice.highlighted, index))
        .textShadow(this.regexPreviewTextShadow(slice.highlighted, index))
        .decoration(this.regexPreviewDecoration(slice.highlighted, index))
    }
  }

  @Builder
  regexRulePreviewItem(index: number, refreshKey: number) {
    Column({ space: 6 }) {
      Text('规则预览')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .width('100%')
      Text() {
        ForEach(this.regexPreviewSlices(index, refreshKey), (slice: ReaderRegexPreviewSlice) => {
          this.regexPreviewSliceItem(slice, index)
        }, (slice: ReaderRegexPreviewSlice) => slice.key)
      }
      .width('100%')
      .maxLines(3)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 4, bottom: 2 })
  }

  emphasisModeOptions(): SelectOption[] {
    return [
      { value: '跟随主题' },
      { value: '无强调' },
      { value: '自定义' }
    ];
  }

  emphasisModeIndex(mode: string): number {
    if (mode === 'none') {
      return 1;
    }
    if (mode === 'custom' || mode === 'text' || mode === 'highlight' || mode === 'bubble') {
      return 2;
    }
    return 0;
  }

  emphasisModeByIndex(index: number): string {
    if (index === 1) {
      return 'none';
    }
    if (index === 2) {
      return 'custom';
    }
    return 'inherit';
  }

  emphasisModeLabel(mode: string): string {
    const options = this.emphasisModeOptions();
    return String(options[this.emphasisModeIndex(mode)].value);
  }

  bubbleStyleOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const item of this.accessibleBubbleStyleOptions()) {
      options.push({ value: item.label });
    }
    return options;
  }

  accessibleBubbleStyleOptions(): ReaderBubbleStyleOption[] {
    const options: ReaderBubbleStyleOption[] = [
      new ReaderBubbleStyleOption('inherit', '跟随主题'),
      new ReaderBubbleStyleOption('qq-soft', '柔和'),
      new ReaderBubbleStyleOption('qq-solid', '实色'),
      new ReaderBubbleStyleOption('capsule', '圆角胶囊'),
      new ReaderBubbleStyleOption('paper', '纸笺'),
      new ReaderBubbleStyleOption('neon', '霓虹')
    ];
    const revision = this.accountEntitlementsRevision;
    this.appendAccessibleBubbleStyle(options, 'classic-glass', '经典玻璃', revision);
    this.appendAccessibleBubbleStyle(options, 'warm-scroll', '暖纸卷轴', revision);
    this.appendAccessibleBubbleStyle(options, 'forest-dew', '林间露珠', revision);
    this.appendAccessibleBubbleStyle(options, 'ink-brush', '水墨笔触', revision);
    this.appendAccessibleBubbleStyle(options, 'neon-pulse', '霓虹脉冲', revision);
    this.appendAccessibleBubbleStyle(options, 'strawberry-ribbon', '草莓软框', revision);
    this.appendAccessibleBubbleStyle(options, 'crimson-stamp', '赤墨印章', revision);
    this.appendAccessibleBubbleStyle(options, 'celadon-slip', '青瓷纸笺', revision);
    this.appendAccessibleBubbleStyle(options, 'rose-frame', '玫瑰信框', revision);
    this.appendAccessibleBubbleStyle(options, 'moon-halo', '月光描边', revision);
    this.appendAccessibleBubbleStyle(options, 'sword-talisman', '剑符', revision);
    this.appendAccessibleBubbleStyle(options, 'qingluan-jade', '青鸾玉令', revision);
    this.appendAccessibleBubbleStyle(options, 'pipi-soft-paw', '皮皮软爪', revision);
    return options;
  }

  appendAccessibleBubbleStyle(options: ReaderBubbleStyleOption[], styleId: string, label: string,
    revision: number): void {
    if (ThemeAccessPolicy.canUseBubbleStyle(styleId) || revision < 0) {
      options.push(new ReaderBubbleStyleOption(styleId, label));
    }
  }

  bubbleStyleIndex(styleId: string): number {
    const options = this.accessibleBubbleStyleOptions();
    for (let index = 0; index < options.length; index++) {
      if (options[index].styleId === styleId) {
        return index;
      }
    }
    return 0;
  }

  bubbleStyleByIndex(index: number): string {
    const options = this.accessibleBubbleStyleOptions();
    return index >= 0 && index < options.length ? options[index].styleId : 'inherit';
  }

  bubbleStyleLabel(styleId: string): string {
    const options = this.bubbleStyleOptions();
    return String(options[this.bubbleStyleIndex(styleId)].value);
  }

  @Builder
  regexEmphasisSettings(index: number, refreshKey: number) {
    Column({ space: 8 }) {
      Row() {
        Text('强调效果')
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Select(this.emphasisModeOptions())
          .selected(this.emphasisModeIndex(this.regexRuleAt(index).emphasisMode))
          .value(this.emphasisModeLabel(this.regexRuleAt(index).emphasisMode))
          .font({ size: 13 })
          .fontColor(this.subTextColor())
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.END)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .divider(null)
          .opacity(refreshKey >= 0 ? 1 : 1)
          .optionBgColor(Color.Transparent)
          .optionFontColor(this.primaryTextColor())
          .selectedOptionFontColor(this.accentColor())
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .menuSystemMaterial(this.selectMenuMaterial())
          .onSelect((selectedIndex: number) => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
              target.emphasisMode = this.emphasisModeByIndex(selectedIndex);
            });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.emphasisModeIndex(this.regexRuleAt(index).emphasisMode) === 2) {
        this.regexEmphasisToggle('设置文字色', this.regexRuleAt(index).customTextColorEnabled, (enabled: boolean) => {
          this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
            target.customTextColorEnabled = enabled;
            if (enabled && !target.customTextColor.trim()) {
              target.customTextColor = this.accentColor();
            }
          });
        })
        if (this.regexRuleAt(index).customTextColorEnabled) {
          AdaptiveColorPicker({
            value: this.regexRuleAt(index).customTextColor,
            placeholder: this.accentColor(),
            appDarkMode: this.appDarkMode,
            accentColor: this.accentColor(),
            optionTitle: '文字颜色',
            directSelection: true,
            onColorChange: (value: string) => {
              this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                target.customTextColor = this.normalizeColorInput(value, target.customTextColor || this.accentColor());
              });
            }
          })
        }

        this.regexEmphasisToggle('设置高亮色块', this.regexRuleAt(index).customHighlightEnabled,
          (enabled: boolean) => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
              target.customHighlightEnabled = enabled;
              if (enabled && !target.customHighlightColor.trim()) {
                target.customHighlightColor = this.accentColor();
              }
            });
          })
        if (this.regexRuleAt(index).customHighlightEnabled) {
          AdaptiveColorPicker({
            value: this.regexRuleAt(index).customHighlightColor,
            placeholder: this.accentColor(),
            appDarkMode: this.appDarkMode,
            accentColor: this.accentColor(),
            optionTitle: '高亮色块颜色',
            directSelection: true,
            onColorChange: (value: string) => {
              this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                target.customHighlightColor = this.normalizeColorInput(value,
                  target.customHighlightColor || this.accentColor());
              });
            }
          })
        }

        this.regexEmphasisToggle('设置强调气泡', this.regexRuleAt(index).customBubbleEnabled,
          (enabled: boolean) => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
              target.customBubbleEnabled = enabled;
              if (enabled && !target.customBubbleColor.trim()) {
                target.customBubbleColor = this.accentColor();
              }
            });
          })
        if (this.regexRuleAt(index).customBubbleEnabled) {
          Row() {
            Text('气泡风格')
              .fontSize(15)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Select(this.bubbleStyleOptions())
              .selected(this.bubbleStyleIndex(this.regexRuleAt(index).bubbleStyleId))
              .value(this.bubbleStyleLabel(this.regexRuleAt(index).bubbleStyleId))
              .font({ size: 13 })
              .fontColor(this.subTextColor())
              .backgroundColor(Color.Transparent)
              .arrowPosition(ArrowPosition.END)
              .padding({ left: 0, right: 0 })
              .borderRadius(16)
              .border({ width: 0 })
              .divider(null)
              .optionBgColor(Color.Transparent)
              .optionFontColor(this.primaryTextColor())
              .selectedOptionFontColor(this.accentColor())
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
              .menuBackgroundBlurStyle(BlurStyle.NONE)
              .menuSystemMaterial(this.selectMenuMaterial())
              .onSelect((selectedIndex: number) => {
                const selectedStyleId = this.bubbleStyleByIndex(selectedIndex);
                this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                  target.bubbleStyleId = selectedStyleId;
                });
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          AdaptiveColorPicker({
            value: this.regexRuleAt(index).customBubbleColor,
            placeholder: this.accentColor(),
            appDarkMode: this.appDarkMode,
            accentColor: this.accentColor(),
            optionTitle: '强调气泡颜色',
            directSelection: true,
            onColorChange: (value: string) => {
              this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                target.customBubbleColor = this.normalizeColorInput(value,
                  target.customBubbleColor || this.accentColor());
              });
            }
          })
        }
      }
    }
    .width('100%')
  }

  @Builder
  regexEmphasisToggle(title: string, enabled: boolean, onChange: (enabled: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      AdaptiveSwitch({ isOn: enabled, selectedColor: this.accentColor(),
        onChange: (checked: boolean) => {
          onChange(checked);
        },
      })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }
  @Builder
  compactFontModeItem(title: string, mode: string, family: string, onChange: (mode: string, family: string) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Select(this.fontOptions())
        .selected(this.selectedFontIndex(mode, family))
        .value(this.selectedFontValue(mode, family))
        .font({ size: 13 })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .divider(null)
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .menuSystemMaterial(this.selectMenuMaterial())
        .onSelect((index: number) => {
          const result = this.modeAndFamilyByIndex(index);
          onChange(result[0], result[1]);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  regexFontSizeStepper(index: number) {
    Row({ space: 8 }) {
      Text('字体大小')
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      this.fontSizeStepButton($r('sys.symbol.minus'), '减小规则字体',
        this.regexRuleAt(index).fontSize > 14, () => {
        this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
          target.fontSize = Math.max(14, Math.round(target.fontSize) - 1);
        });
      })
      Text(`${Math.round(this.regexRuleAt(index).fontSize)}sp`)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .width(52)
        .height(36)
        .textAlign(TextAlign.Center)
      this.fontSizeStepButton($r('sys.symbol.plus'), '增大规则字体',
        this.regexRuleAt(index).fontSize !== 50, () => {
        this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
          target.fontSize = Math.min(50, Math.round(target.fontSize) + 1);
        });
      })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  regexEnableSwitchItem() {
    Row() {
      Text('启用正则字体')
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      AdaptiveSwitch({ isOn: this.readerRegexFontEnabled, selectedColor: this.accentColor(),
        onChange: (checked: boolean) => {
          this.readerRegexFontEnabled = checked;
          this.saveSettings();
        },
      })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

}
