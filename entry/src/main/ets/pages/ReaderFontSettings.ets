import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ColorCodePicker } from '../components/ColorCodePicker';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderRegexFontCodec,
  ReaderRegexFontRule,
  ReaderRegexLegacySettings,
  ReaderResolvedRegexEmphasis
} from '../model/reader/ReaderRegexFontRule';
import { ThemeRuntime } from '../theme/ThemeRuntime';

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

@Entry
@Component
struct ReaderFontSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('themeRevision') themeRevision: number = 0;
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

  aboutToAppear(): void {
    this.loadSettings();
    this.syncBars();
  }

  onPageShow(): void {
    this.loadSettings();
    this.syncBars();
  }

  async loadSettings(): Promise<void> {
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
    } catch (e) {
      console.warn('加载阅读字体设置失败:', e);
    }
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('正文字体设置')
          this.fontModeItem('字体类型', this.readerBodyFontMode, this.readerBodyFontFamily, (mode: string, family: string) => {
            this.readerBodyFontMode = mode;
            this.readerBodyFontFamily = family;
            this.saveSettings();
          })
          this.bodyFontSizeSlider()
          this.bodyPreviewItem()

          this.sectionTitle('标题字体设置')
          this.fontModeItem('字体类型', this.readerTitleFontMode, this.readerTitleFontFamily, (mode: string, family: string) => {
            this.readerTitleFontMode = mode;
            this.readerTitleFontFamily = family;
            this.saveSettings();
          })
          this.titleFontSizeSlider()
          this.titlePreviewItem()

          this.sectionTitle('正则字体设置')
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
        .width('100%')
        .padding({ bottom: 32 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  saveSettings(): void {
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
    settings.regexFontRulesRaw = this.encodeRegexRules(this.regexRules);
    ReaderSettingsStore.saveReaderFontStyleSettings(getContext(this), settings).catch((e: Error) => {
      console.warn('保存阅读字体设置失败:', e);
    });
  }

  setBodyFontSize(value: number): void {
    this.readerFontSize = Math.max(14, Math.min(Math.round(value), 30));
    this.saveSettings();
  }

  setTitleFontSize(value: number): void {
    this.readerTitleFontSize = Math.max(14, Math.min(Math.round(value), 30));
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

  cleanRegexRules(source: ReaderRegexFontRule[]): ReaderRegexFontRule[] {
    return ReaderRegexFontCodec.cleanRules(source);
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
    this.saveSettings();
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
        if (fonts[i].familyName === family) {
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
        font.sourceName = item.sourceName || item.familyName;
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
    item.sourceName = font.sourceName || ReaderFontHelper.fileNameFromPath(font.filePath);
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
      Text('<')
        .fontSize(24)
        .fontColor(this.primaryTextColor())
        .width(40)
        .height(56)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Text('阅读字体')
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
        .fontColor(this.primaryTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(8)
        .constraintSize({ minWidth: 140, maxWidth: 180 })
        .onSelect((index: number) => {
          const result = this.modeAndFamilyByIndex(index);
          onChange(result[0], result[1]);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  fontSizeSlider(title: string, value: number, min: number, max: number, onChange: (value: number) => void) {
    Column() {
      Row() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${Math.round(value)}sp`)
          .fontSize(14)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: 1 })
        .width('100%')
        .margin({ top: 8 })
        .selectedColor(this.accentColor())
        .onChange((sliderValue: number) => {
          onChange(sliderValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  bodyFontSizeSlider() {
    Column() {
      Row() {
        Text('字体大小')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.readerFontSize}sp`)
          .fontSize(14)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Slider({ value: this.readerFontSize, min: 14, max: 30, step: 1 })
        .width('100%')
        .margin({ top: 8 })
        .selectedColor(this.accentColor())
        .onChange((sliderValue: number) => {
          this.setBodyFontSize(sliderValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  titleFontSizeSlider() {
    Column() {
      Row() {
        Text('字体大小')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.readerTitleFontSize}sp`)
          .fontSize(14)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Slider({ value: this.readerTitleFontSize, min: 14, max: 30, step: 1 })
        .width('100%')
        .margin({ top: 8 })
        .selectedColor(this.accentColor())
        .onChange((sliderValue: number) => {
          this.setTitleFontSize(sliderValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
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
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  emptyRegexRule() {
    Text('暂无正则规则')
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .backgroundColor(this.cardColor())
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
        this.regexFontSizeSlider(index, refreshKey)

        this.regexEmphasisSettings(index, refreshKey)

        this.regexRulePreviewItem(index, refreshKey)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.cardColor())
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
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
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
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
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

  regexPreviewTextShadow(highlighted: boolean, index: number): ShadowOptions {
    const style = this.resolvedRegexEmphasis(index);
    if (!highlighted) {
      return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
    }
    return {
      radius: style.textShadowRadius,
      color: style.textShadowColor,
      offsetX: style.textShadowOffsetX,
      offsetY: style.textShadowOffsetY
    };
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
          Span(slice.text)
            .fontSize(slice.highlighted ? this.regexRuleAt(index).fontSize : this.readerFontSize)
            .fontFamily(slice.highlighted ? this.previewFontFamily(this.regexRuleAt(index).fontMode, this.regexRuleAt(index).fontFamily) :
              this.previewFontFamily(this.readerBodyFontMode, this.readerBodyFontFamily))
            .fontColor(this.regexPreviewTextColor(slice.highlighted, index))
            .textBackgroundStyle(this.regexPreviewBackgroundStyle(slice.highlighted, index))
            .textShadow(this.regexPreviewTextShadow(slice.highlighted, index))
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
      { value: '仅文字色' },
      { value: '高亮色块' },
      { value: '强调气泡' }
    ];
  }

  emphasisModeIndex(mode: string): number {
    if (mode === 'none') {
      return 1;
    }
    if (mode === 'text') {
      return 2;
    }
    if (mode === 'highlight') {
      return 3;
    }
    if (mode === 'bubble') {
      return 4;
    }
    return 0;
  }

  emphasisModeByIndex(index: number): string {
    if (index === 1) {
      return 'none';
    }
    if (index === 2) {
      return 'text';
    }
    if (index === 3) {
      return 'highlight';
    }
    if (index === 4) {
      return 'bubble';
    }
    return 'inherit';
  }

  emphasisModeLabel(mode: string): string {
    const options = this.emphasisModeOptions();
    return String(options[this.emphasisModeIndex(mode)].value);
  }

  bubbleStyleOptions(): SelectOption[] {
    return [
      { value: '跟随主题' },
      { value: '柔和' },
      { value: '实色' },
      { value: '圆角胶囊' },
      { value: '纸笺' },
      { value: '霓虹' }
    ];
  }

  bubbleStyleIndex(styleId: string): number {
    if (styleId === 'qq-soft') {
      return 1;
    }
    if (styleId === 'qq-solid') {
      return 2;
    }
    if (styleId === 'capsule') {
      return 3;
    }
    if (styleId === 'paper') {
      return 4;
    }
    if (styleId === 'neon') {
      return 5;
    }
    return 0;
  }

  bubbleStyleByIndex(index: number): string {
    if (index === 1) {
      return 'qq-soft';
    }
    if (index === 2) {
      return 'qq-solid';
    }
    if (index === 3) {
      return 'capsule';
    }
    if (index === 4) {
      return 'paper';
    }
    if (index === 5) {
      return 'neon';
    }
    return 'inherit';
  }

  bubbleStyleLabel(styleId: string): string {
    const options = this.bubbleStyleOptions();
    return String(options[this.bubbleStyleIndex(styleId)].value);
  }

  shouldShowBubbleStyle(index: number): boolean {
    const mode = this.regexRuleAt(index).emphasisMode;
    return mode === 'inherit' || mode === 'bubble';
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
          .fontColor(this.primaryTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(8)
          .constraintSize({ minWidth: 126, maxWidth: 160 })
          .opacity(refreshKey >= 0 ? 1 : 1)
          .onSelect((selectedIndex: number) => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
              target.emphasisMode = this.emphasisModeByIndex(selectedIndex);
            });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.shouldShowBubbleStyle(index)) {
        Row() {
          Text('气泡风格')
            .fontSize(15)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Select(this.bubbleStyleOptions())
            .selected(this.bubbleStyleIndex(this.regexRuleAt(index).bubbleStyleId))
            .value(this.bubbleStyleLabel(this.regexRuleAt(index).bubbleStyleId))
            .font({ size: 13 })
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.inputColor())
            .borderRadius(8)
            .constraintSize({ minWidth: 126, maxWidth: 160 })
            .onSelect((selectedIndex: number) => {
              this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                target.bubbleStyleId = this.bubbleStyleByIndex(selectedIndex);
              });
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      if (this.regexRuleAt(index).emphasisMode !== 'none') {
        Row() {
          Text('强调颜色')
            .fontSize(15)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Select([{ value: '跟随主题' }, { value: '自定义' }])
            .selected(this.regexRuleAt(index).emphasisColor.trim() ? 1 : 0)
            .value(this.regexRuleAt(index).emphasisColor.trim() ? '自定义' : '跟随主题')
            .font({ size: 13 })
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.inputColor())
            .borderRadius(8)
            .constraintSize({ minWidth: 126, maxWidth: 160 })
            .onSelect((selectedIndex: number) => {
              this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                target.emphasisColor = selectedIndex === 0 ? '' :
                  (target.emphasisColor.trim() || this.accentColor());
                target.shadowColor = target.emphasisColor;
              });
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.regexRuleAt(index).emphasisColor.trim()) {
          ColorCodePicker({
            value: this.regexRuleAt(index).emphasisColor,
            placeholder: this.accentColor(),
            appDarkMode: this.appDarkMode,
            accentColor: this.accentColor(),
            optionTitle: '自定义强调色',
            onColorChange: (value: string) => {
              this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                target.emphasisColor = this.normalizeColorInput(value, target.emphasisColor);
                target.shadowColor = target.emphasisColor;
              });
            }
          })
        }
      }
    }
    .width('100%')
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
        .fontColor(this.primaryTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(8)
        .constraintSize({ minWidth: 140, maxWidth: 180 })
        .onSelect((index: number) => {
          const result = this.modeAndFamilyByIndex(index);
          onChange(result[0], result[1]);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  compactFontSizeSlider(title: string, value: number, onChange: (value: number) => void) {
    Column() {
      Row() {
        Text(title)
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${Math.round(value)}sp`)
          .fontSize(13)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Slider({ value: value, min: 14, max: 30, step: 1 })
        .width('100%')
        .margin({ top: 6 })
        .selectedColor(this.accentColor())
        .onChange((sliderValue: number) => {
          onChange(sliderValue);
        })
    }
    .width('100%')
  }

  @Builder
  regexFontSizeSlider(index: number, refreshKey: number) {
    Column() {
      Row() {
        Text('字体大小')
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${Math.round(this.regexRuleAt(index).fontSize)}sp`)
          .fontSize(13)
          .fontColor(this.subTextColor())
          .opacity(refreshKey >= 0 ? 1 : 1)
      }
      .width('100%')
      Slider({ value: this.regexRuleAt(index).fontSize, min: 14, max: 30, step: 1 })
        .width('100%')
        .margin({ top: 6 })
        .selectedColor(this.accentColor())
        .onChange((sliderValue: number) => {
          this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
            target.fontSize = Math.max(14, Math.min(Math.round(sliderValue), 30));
          });
        })
    }
    .width('100%')
  }

  @Builder
  regexEnableSwitchItem() {
    Row() {
      Text('启用正则字体')
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      if (this.readerRegexFontEnabled) {
        Row() {
          Row() {}
            .width(24)
            .height(24)
            .borderRadius(12)
            .backgroundColor('#FFFFFF')
        }
        .width(48)
        .height(28)
        .padding(2)
        .borderRadius(14)
        .backgroundColor(this.accentColor())
        .justifyContent(FlexAlign.End)
        .onClick(() => {
          this.readerRegexFontEnabled = false;
          this.saveSettings();
        })
      } else {
        Row() {
          Row() {}
            .width(24)
            .height(24)
            .borderRadius(12)
            .backgroundColor('#FFFFFF')
        }
        .width(48)
        .height(28)
        .padding(2)
        .borderRadius(14)
        .backgroundColor(this.inputColor())
        .justifyContent(FlexAlign.Start)
        .onClick(() => {
          this.readerRegexFontEnabled = true;
          this.saveSettings();
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  inputItem(title: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .fontSize(14)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(8)
        .margin({ top: 8 })
        .onChange((inputValue: string) => {
          onChange(inputValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }
}
