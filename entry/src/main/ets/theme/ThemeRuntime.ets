import { BuiltinThemeRegistry } from './BuiltinThemeRegistry';
import {
  ThemeBubbleStyles,
  ThemeBookTokens,
  ThemeComponentSourceIds,
  ThemeGlassSurfaceTokens,
  ThemeGlassTokens,
  ThemeIds,
  ThemePack,
  ThemeReaderLayoutTokens,
  ThemeRegexEmphasisModes,
  ThemeVariant
} from './ThemeModels';
import { HexColor } from '../utils/HexColor';

export class ThemeRuntime {
  static readonly KEY_THEME_ID: string = 'appThemeId';
  static readonly KEY_THEME_REVISION: string = 'themeRevision';
  static readonly KEY_FONT_FAMILY: string = 'themeFontFamily';
  static readonly KEY_ICON_PACK_ID: string = 'themeIconPackId';
  static readonly KEY_CUSTOM_BASE_THEME_ID: string = 'appCustomBaseThemeId';
  static readonly KEY_CUSTOM_LIGHT_SOURCES: string = 'appCustomLightThemeSources';
  static readonly KEY_CUSTOM_DARK_SOURCES: string = 'appCustomDarkThemeSources';

  static readonly KEY_LIGHT_PAGE_COLOR: string = 'themeLightPageColor';
  static readonly KEY_DARK_PAGE_COLOR: string = 'themeDarkPageColor';
  static readonly KEY_LIGHT_CARD_COLOR: string = 'themeLightCardColor';
  static readonly KEY_DARK_CARD_COLOR: string = 'themeDarkCardColor';
  static readonly KEY_LIGHT_INPUT_COLOR: string = 'themeLightInputColor';
  static readonly KEY_DARK_INPUT_COLOR: string = 'themeDarkInputColor';
  static readonly KEY_LIGHT_PRIMARY_TEXT_COLOR: string = 'themeLightPrimaryTextColor';
  static readonly KEY_DARK_PRIMARY_TEXT_COLOR: string = 'themeDarkPrimaryTextColor';
  static readonly KEY_LIGHT_SUB_TEXT_COLOR: string = 'themeLightSubTextColor';
  static readonly KEY_DARK_SUB_TEXT_COLOR: string = 'themeDarkSubTextColor';
  static readonly KEY_LIGHT_DIVIDER_COLOR: string = 'themeLightDividerColor';
  static readonly KEY_DARK_DIVIDER_COLOR: string = 'themeDarkDividerColor';
  static readonly KEY_LIGHT_ACCENT_COLOR: string = 'themeLightAccentColor';
  static readonly KEY_DARK_ACCENT_COLOR: string = 'themeDarkAccentColor';
  static readonly KEY_LIGHT_BUTTON_COLOR: string = 'themeLightButtonColor';
  static readonly KEY_DARK_BUTTON_COLOR: string = 'themeDarkButtonColor';
  static readonly KEY_LIGHT_DANGER_COLOR: string = 'themeLightDangerColor';
  static readonly KEY_DARK_DANGER_COLOR: string = 'themeDarkDangerColor';

  static readonly KEY_LIGHT_READER_BACKGROUND_COLOR: string = 'themeLightReaderBackgroundColor';
  static readonly KEY_DARK_READER_BACKGROUND_COLOR: string = 'themeDarkReaderBackgroundColor';
  static readonly KEY_LIGHT_READER_BACKGROUND_ASSET_ID: string = 'themeLightReaderBackgroundAssetId';
  static readonly KEY_DARK_READER_BACKGROUND_ASSET_ID: string = 'themeDarkReaderBackgroundAssetId';
  static readonly KEY_LIGHT_READER_BACKGROUND_IMAGE_FIT: string = 'themeLightReaderBackgroundImageFit';
  static readonly KEY_DARK_READER_BACKGROUND_IMAGE_FIT: string = 'themeDarkReaderBackgroundImageFit';
  static readonly KEY_LIGHT_READER_TEXT_COLOR: string = 'themeLightReaderTextColor';
  static readonly KEY_DARK_READER_TEXT_COLOR: string = 'themeDarkReaderTextColor';
  static readonly KEY_LIGHT_READER_SUB_TEXT_COLOR: string = 'themeLightReaderSubTextColor';
  static readonly KEY_DARK_READER_SUB_TEXT_COLOR: string = 'themeDarkReaderSubTextColor';
  static readonly KEY_LIGHT_READER_CONTENT_TONE: string = 'themeLightReaderContentTone';
  static readonly KEY_DARK_READER_CONTENT_TONE: string = 'themeDarkReaderContentTone';

  static readonly KEY_LIGHT_REGEX_EMPHASIS_MODE: string = 'themeLightRegexEmphasisMode';
  static readonly KEY_DARK_REGEX_EMPHASIS_MODE: string = 'themeDarkRegexEmphasisMode';
  static readonly KEY_LIGHT_REGEX_BUBBLE_STYLE: string = 'themeLightRegexBubbleStyle';
  static readonly KEY_DARK_REGEX_BUBBLE_STYLE: string = 'themeDarkRegexBubbleStyle';
  static readonly KEY_LIGHT_REGEX_EMPHASIS_COLOR: string = 'themeLightRegexEmphasisColor';
  static readonly KEY_DARK_REGEX_EMPHASIS_COLOR: string = 'themeDarkRegexEmphasisColor';
  static readonly KEY_LIGHT_REGEX_EMPHASIS_TEXT_COLOR: string = 'themeLightRegexEmphasisTextColor';
  static readonly KEY_DARK_REGEX_EMPHASIS_TEXT_COLOR: string = 'themeDarkRegexEmphasisTextColor';

  static readonly KEY_RADIUS_SMALL: string = 'themeRadiusSmall';
  static readonly KEY_RADIUS_MEDIUM: string = 'themeRadiusMedium';
  static readonly KEY_RADIUS_LARGE: string = 'themeRadiusLarge';
  static readonly KEY_RADIUS_CARD: string = 'themeRadiusCard';
  static readonly KEY_RADIUS_BUTTON: string = 'themeRadiusButton';
  static readonly KEY_RADIUS_BUBBLE: string = 'themeRadiusBubble';

  static applyTheme(themeId: string, lightAccentOverride: string = '', darkAccentOverride: string = '',
    lightButtonOverride: string = '', darkButtonOverride: string = '', customBaseThemeId: string = ''): ThemePack {
    const normalizedThemeId = BuiltinThemeRegistry.normalizeId(themeId);
    const baseThemeId = BuiltinThemeRegistry.normalizeBuiltinId(customBaseThemeId);
    const theme = normalizedThemeId === ThemeIds.CUSTOM ?
      BuiltinThemeRegistry.customTheme(baseThemeId) : BuiltinThemeRegistry.findById(normalizedThemeId);
    ThemeRuntime.setString(ThemeRuntime.KEY_CUSTOM_BASE_THEME_ID, baseThemeId);
    ThemeRuntime.applyPack(theme, lightAccentOverride, darkAccentOverride, lightButtonOverride, darkButtonOverride);
    return theme;
  }

  static applyPack(theme: ThemePack, lightAccentOverride: string = '', darkAccentOverride: string = '',
    lightButtonOverride: string = '', darkButtonOverride: string = ''): void {
    const fallback = BuiltinThemeRegistry.findById(BuiltinThemeRegistry.DEFAULT_THEME_ID);
    const themeId = (theme.id || '').trim() || BuiltinThemeRegistry.DEFAULT_THEME_ID;
    ThemeRuntime.setString(ThemeRuntime.KEY_THEME_ID, themeId);
    ThemeRuntime.setString(ThemeRuntime.KEY_FONT_FAMILY,
      (theme.typography.appFontFamily || '').trim() || fallback.typography.appFontFamily);
    ThemeRuntime.setString(ThemeRuntime.KEY_ICON_PACK_ID,
      (theme.navigation.iconPackId || '').trim() || fallback.navigation.iconPackId);

    ThemeRuntime.publishVariant(false, theme.light, fallback.light, lightAccentOverride, lightButtonOverride);
    ThemeRuntime.publishVariant(true, theme.dark, fallback.dark, darkAccentOverride, darkButtonOverride);

    ThemeRuntime.setNumber(ThemeRuntime.KEY_RADIUS_SMALL,
      ThemeRuntime.normalizeRadius(theme.radius.small, fallback.radius.small));
    ThemeRuntime.setNumber(ThemeRuntime.KEY_RADIUS_MEDIUM,
      ThemeRuntime.normalizeRadius(theme.radius.medium, fallback.radius.medium));
    ThemeRuntime.setNumber(ThemeRuntime.KEY_RADIUS_LARGE,
      ThemeRuntime.normalizeRadius(theme.radius.large, fallback.radius.large));
    ThemeRuntime.setNumber(ThemeRuntime.KEY_RADIUS_CARD,
      ThemeRuntime.normalizeRadius(theme.radius.card, fallback.radius.card));
    ThemeRuntime.setNumber(ThemeRuntime.KEY_RADIUS_BUTTON,
      ThemeRuntime.normalizeRadius(theme.radius.button, fallback.radius.button));
    ThemeRuntime.setNumber(ThemeRuntime.KEY_RADIUS_BUBBLE,
      ThemeRuntime.normalizeRadius(theme.radius.bubble, fallback.radius.bubble));

    const revision = AppStorage.get<number>(ThemeRuntime.KEY_THEME_REVISION) ?? 0;
    AppStorage.setOrCreate(ThemeRuntime.KEY_THEME_REVISION, revision + 1);
  }

  static currentThemeId(): string {
    const stored = ThemeRuntime.storageString(ThemeRuntime.KEY_THEME_ID, BuiltinThemeRegistry.DEFAULT_THEME_ID);
    return BuiltinThemeRegistry.normalizeId(stored);
  }

  static startupThemeId(darkMode: boolean = AppStorage.get<boolean>('appDarkMode') || false): string {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('startup', darkMode).startup.styleId;
    }
    return ThemeRuntime.currentPack().startup.styleId;
  }

  /** Theme whose TTS / audiobook panel background applies; a custom theme names its own source. */
  static ttsPanelThemeId(darkMode: boolean = AppStorage.get<boolean>('appDarkMode') || false): string {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('ttsPanel', darkMode).id;
    }
    return ThemeRuntime.currentThemeId();
  }

  static themeRevision(): number {
    return AppStorage.get<number>(ThemeRuntime.KEY_THEME_REVISION) ?? 0;
  }

  static pageColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.pageColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_PAGE_COLOR :
      ThemeRuntime.KEY_LIGHT_PAGE_COLOR, fallback);
  }

  static cardColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.cardColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_CARD_COLOR :
      ThemeRuntime.KEY_LIGHT_CARD_COLOR, fallback);
  }

  /** 顶栏与页面同色且不透明，不再用模糊和半透明，也不做成一条单独的白条。 */
  static topBarColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.pageColor;
    return ThemeRuntime.normalizeColor(ThemeRuntime.pageColor(darkMode), fallback);
  }

  static inputColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.inputColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_INPUT_COLOR :
      ThemeRuntime.KEY_LIGHT_INPUT_COLOR, fallback);
  }

  static primaryTextColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.primaryTextColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_PRIMARY_TEXT_COLOR :
      ThemeRuntime.KEY_LIGHT_PRIMARY_TEXT_COLOR, fallback);
  }

  static subTextColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.subTextColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_SUB_TEXT_COLOR :
      ThemeRuntime.KEY_LIGHT_SUB_TEXT_COLOR, fallback);
  }

  static dividerColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.dividerColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_DIVIDER_COLOR :
      ThemeRuntime.KEY_LIGHT_DIVIDER_COLOR, fallback);
  }

  static accentColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.accentColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_ACCENT_COLOR :
      ThemeRuntime.KEY_LIGHT_ACCENT_COLOR, fallback);
  }

  static accentSurfaceColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.accentColor;
    const accent = ThemeRuntime.normalizeColor(ThemeRuntime.accentColor(darkMode), fallback);
    return `#${darkMode ? '33' : '1F'}${accent.substring(1)}`;
  }

  /**
   * 列表卡片等常驻表面的玻璃色调，取当前主题包的玻璃参数（磨砂玻璃设置已移除，浮层面板改用系统沉浸光感材质）。
   */
  static glassPanelColor(darkMode: boolean, baseColor: string = '', surface: string = 'panel'): string {
    const fallback = ThemeRuntime.cardColor(darkMode);
    const color = ThemeRuntime.normalizeColor(baseColor || fallback, fallback);
    if (!ThemeRuntime.glassEnabled()) {
      return color;
    }
    const glass = ThemeRuntime.currentGlass();
    const opacity = darkMode ? glass.darkTintOpacity : glass.lightTintOpacity;
    return `#${ThemeRuntime.opacityHex(opacity)}${color.substring(1)}`;
  }

  static dropdownPanelColor(darkMode: boolean, baseColor: string = '', surface: string = 'popover'): string {
    const fallback = ThemeRuntime.cardColor(darkMode);
    const color = ThemeRuntime.normalizeColor(baseColor || fallback, fallback);
    if (!ThemeRuntime.glassEnabled()) {
      return color;
    }
    // 菜单与沉浸面板统一为 50% 底色。
    return `#80${color.substring(1)}`;
  }

  static glassBorderColor(darkMode: boolean, surface: string = 'panel'): string {
    const glass = ThemeRuntime.currentGlass();
    const opacity = darkMode ? glass.darkBorderOpacity : glass.lightBorderOpacity;
    return `#${ThemeRuntime.opacityHex(opacity)}FFFFFF`;
  }

  static glassShadowColor(darkMode: boolean, surface: string = 'panel'): string {
    if (!ThemeRuntime.glassShadowEnabled()) {
      return '#00000000';
    }
    const glass = ThemeRuntime.currentGlass();
    const opacity = darkMode ? glass.darkShadowOpacity : glass.lightShadowOpacity;
    return `#${ThemeRuntime.opacityHex(opacity)}000000`;
  }

  static glassEnabled(): boolean {
    return ThemeRuntime.currentGlass().enabled;
  }

  static glassShadowEnabled(surface: string = 'panel'): boolean {
    return ThemeRuntime.glassEnabled() && ThemeRuntime.currentGlass().shadowEnabled;
  }

  static glassBorderWidth(surface: string = 'panel'): number {
    return ThemeRuntime.clampNumber(ThemeRuntime.currentGlass().borderWidth, 0, 2);
  }

  static glassCornerRadius(fallback: number = 16, surface: string = 'panel'): number {
    return ThemeRuntime.clampNumber(ThemeRuntime.glassSurface(ThemeRuntime.currentGlass(), surface).cornerRadius,
      0, 32);
  }

  static glassShadowRadius(surface: string = 'panel'): number {
    if (!ThemeRuntime.glassShadowEnabled()) {
      return 0;
    }
    return ThemeRuntime.clampNumber(ThemeRuntime.currentGlass().shadowRadius, 0, 30);
  }

  static glassShadowOffsetX(surface: string = 'panel'): number {
    return ThemeRuntime.clampNumber(ThemeRuntime.currentGlass().shadowOffsetX, -12, 12);
  }

  static glassShadowOffsetY(surface: string = 'panel'): number {
    return ThemeRuntime.clampNumber(ThemeRuntime.currentGlass().shadowOffsetY, -12, 12);
  }

  private static clampNumber(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private static currentGlass(): ThemeGlassTokens {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('glass').glass || new ThemeGlassTokens();
    }
    return ThemeRuntime.currentPack().glass || new ThemeGlassTokens();
  }

  private static glassSurface(glass: ThemeGlassTokens, surface: string): ThemeGlassSurfaceTokens {
    const normalized = (surface || '').trim().toLowerCase();
    if (normalized === 'popover') return glass.popover;
    if (normalized === 'button') return glass.button;
    if (normalized === 'overlay') return glass.overlay;
    if (normalized === 'menu') return glass.menu;
    return glass.panel;
  }

  private static opacityHex(opacity: number): string {
    const value = Math.max(0, Math.min(255, Math.round(opacity * 2.55)));
    return value.toString(16).padStart(2, '0').toUpperCase();
  }

  static buttonColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.buttonColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_BUTTON_COLOR :
      ThemeRuntime.KEY_LIGHT_BUTTON_COLOR, fallback);
  }

  static dangerColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).colors.dangerColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_DANGER_COLOR :
      ThemeRuntime.KEY_LIGHT_DANGER_COLOR, fallback);
  }

  // 以下语义色不属于主题包，各主题共用，只随深浅色变化。

  /** 成功、通过、已启用等状态的文字和图标。 */
  static successColor(darkMode: boolean): string {
    return darkMode ? '#7CC7A0' : '#1F8F55';
  }

  /** 成功状态标签的浅底色。 */
  static successSurfaceColor(darkMode: boolean): string {
    return darkMode ? '#24382F' : '#E6F4EC';
  }

  /** 警告、待处理等状态。 */
  static warningColor(_darkMode: boolean): string {
    return '#E89725';
  }

  /** 强调色、按钮色、危险色等实色背景上的文字。 */
  static onAccentColor(backgroundColor: string = ''): string {
    // Detail previews may use another theme's champagne accent before that theme is applied.
    // Preserve the legacy default; callers painting a light fill can supply its actual color.
    if (/^#[0-9a-fA-F]{6}$/.test(backgroundColor)) {
      const channels: number[] = [1, 3, 5].map((start: number): number => {
        const value = Number.parseInt(backgroundColor.slice(start, start + 2), 16) / 255;
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
      });
      const luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
      return luminance > 0.179 ? '#000000' : '#FFFFFF';
    }
    return '#FFFFFF';
  }

  /** 弹窗与浮层背后的遮罩。 */
  static scrimColor(darkMode: boolean): string {
    return darkMode ? '#99000000' : '#33000000';
  }

  /** 列表行、卡片的细分隔线和描边。 */
  static hairlineColor(darkMode: boolean): string {
    return darkMode ? '#24FFFFFF' : '#14000000';
  }

  /** 首页顶部白色胶囊、圆形按钮等悬浮控件的浅投影；深色模式靠底色区分，不加投影。 */
  static floatingControlShadow(darkMode: boolean): ShadowOptions {
    return {
      radius: darkMode ? 0 : 12,
      color: darkMode ? Color.Transparent : '#14000000',
      offsetX: 0,
      offsetY: darkMode ? 0 : 2
    };
  }

  /** 叠在任意底色上的浅色填充，用于次要按钮、选中行、占位块。 */
  static softFillColor(darkMode: boolean): string {
    return darkMode ? '#1FFFFFFF' : '#0D000000';
  }

  static fontFamily(): string {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('typography').typography.appFontFamily || 'sans-serif';
    }
    const fallback = ThemeRuntime.currentPack().typography.appFontFamily || 'sans-serif';
    return ThemeRuntime.storageString(ThemeRuntime.KEY_FONT_FAMILY, fallback);
  }

  static iconPackId(): string {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('navigation').navigation.iconPackId || 'classic';
    }
    const fallback = ThemeRuntime.currentPack().navigation.iconPackId || 'classic';
    return ThemeRuntime.storageString(ThemeRuntime.KEY_ICON_PACK_ID, fallback);
  }

  static bookTokens(darkMode: boolean = AppStorage.get<boolean>('appDarkMode') || false): ThemeBookTokens {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('book', darkMode).book;
    }
    return ThemeRuntime.currentPack().book;
  }

  static readerLayout(darkMode: boolean = AppStorage.get<boolean>('appDarkMode') || false): ThemeReaderLayoutTokens {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      // Layout is a theme-level preference. Color mode may change the reader
      // surface, but must not switch font size, spacing or page margins.
      return ThemeRuntime.customSourceTheme('layout', false).readerLayout;
    }
    return ThemeRuntime.currentPack().readerLayout;
  }

  static readerBackgroundColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).reader.backgroundColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_READER_BACKGROUND_COLOR :
      ThemeRuntime.KEY_LIGHT_READER_BACKGROUND_COLOR, fallback);
  }

  static readerBackgroundAssetId(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).reader.backgroundAssetId;
    return ThemeRuntime.storageStringAllowEmpty(darkMode ? ThemeRuntime.KEY_DARK_READER_BACKGROUND_ASSET_ID :
      ThemeRuntime.KEY_LIGHT_READER_BACKGROUND_ASSET_ID, fallback);
  }

  static readerBackgroundImageAssetId(darkMode: boolean): string {
    return ThemeRuntime.readerBackgroundAssetId(darkMode);
  }

  static readerBackgroundImageFit(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).reader.backgroundImageFit || 'cover';
    const stored = ThemeRuntime.storageString(darkMode ? ThemeRuntime.KEY_DARK_READER_BACKGROUND_IMAGE_FIT :
      ThemeRuntime.KEY_LIGHT_READER_BACKGROUND_IMAGE_FIT, fallback);
    return ThemeRuntime.normalizeImageFit(stored, fallback);
  }

  static readerTextColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).reader.textColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_READER_TEXT_COLOR :
      ThemeRuntime.KEY_LIGHT_READER_TEXT_COLOR, fallback);
  }

  static readerSubTextColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).reader.subTextColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_READER_SUB_TEXT_COLOR :
      ThemeRuntime.KEY_LIGHT_READER_SUB_TEXT_COLOR, fallback);
  }

  static readerContentTone(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).reader.contentTone;
    const stored = ThemeRuntime.storageString(darkMode ? ThemeRuntime.KEY_DARK_READER_CONTENT_TONE :
      ThemeRuntime.KEY_LIGHT_READER_CONTENT_TONE, fallback);
    return ThemeRuntime.normalizeContentTone(stored, fallback);
  }

  static regexEmphasisMode(): string {
    return ThemeRuntime.regexEmphasisModeFor(AppStorage.get<boolean>('appDarkMode') ?? false);
  }

  static regexEmphasisModeFor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).regexEmphasis.emphasisMode;
    const stored = ThemeRuntime.storageString(darkMode ? ThemeRuntime.KEY_DARK_REGEX_EMPHASIS_MODE :
      ThemeRuntime.KEY_LIGHT_REGEX_EMPHASIS_MODE, fallback);
    return ThemeRuntime.normalizeEmphasisMode(stored, fallback);
  }

  static regexBubbleStyle(): string {
    return ThemeRuntime.regexBubbleStyleFor(AppStorage.get<boolean>('appDarkMode') ?? false);
  }

  static regexBubbleStyleFor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).regexEmphasis.bubbleStyle;
    const stored = ThemeRuntime.storageString(darkMode ? ThemeRuntime.KEY_DARK_REGEX_BUBBLE_STYLE :
      ThemeRuntime.KEY_LIGHT_REGEX_BUBBLE_STYLE, fallback);
    return ThemeRuntime.normalizeBubbleStyle(stored, fallback);
  }

  static regexEmphasisColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).regexEmphasis.emphasisColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_REGEX_EMPHASIS_COLOR :
      ThemeRuntime.KEY_LIGHT_REGEX_EMPHASIS_COLOR, fallback);
  }

  static regexEmphasisTextColor(darkMode: boolean): string {
    const fallback = ThemeRuntime.fallbackVariant(darkMode).regexEmphasis.emphasisTextColor;
    return ThemeRuntime.colorFromStorage(darkMode ? ThemeRuntime.KEY_DARK_REGEX_EMPHASIS_TEXT_COLOR :
      ThemeRuntime.KEY_LIGHT_REGEX_EMPHASIS_TEXT_COLOR, fallback);
  }

  static smallRadius(): number {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('radius').radius.small;
    }
    return ThemeRuntime.radiusFromStorage(ThemeRuntime.KEY_RADIUS_SMALL, ThemeRuntime.currentPack().radius.small);
  }

  static mediumRadius(): number {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('radius').radius.medium;
    }
    return ThemeRuntime.radiusFromStorage(ThemeRuntime.KEY_RADIUS_MEDIUM, ThemeRuntime.currentPack().radius.medium);
  }

  static largeRadius(): number {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('radius').radius.large;
    }
    return ThemeRuntime.radiusFromStorage(ThemeRuntime.KEY_RADIUS_LARGE, ThemeRuntime.currentPack().radius.large);
  }

  static cardRadius(): number {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('radius').radius.card;
    }
    return ThemeRuntime.radiusFromStorage(ThemeRuntime.KEY_RADIUS_CARD, ThemeRuntime.currentPack().radius.card);
  }

  static buttonRadius(): number {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('radius').radius.button;
    }
    return ThemeRuntime.radiusFromStorage(ThemeRuntime.KEY_RADIUS_BUTTON, ThemeRuntime.currentPack().radius.button);
  }

  static bubbleRadius(): number {
    if (ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM) {
      return ThemeRuntime.customSourceTheme('radius').radius.bubble;
    }
    return ThemeRuntime.radiusFromStorage(ThemeRuntime.KEY_RADIUS_BUBBLE, ThemeRuntime.currentPack().radius.bubble);
  }

  private static publishVariant(darkMode: boolean, variant: ThemeVariant, fallback: ThemeVariant,
    accentOverride: string, buttonOverride: string): void {
    const pageColor = ThemeRuntime.normalizeColor(variant.colors.pageColor, fallback.colors.pageColor);
    const cardColor = ThemeRuntime.normalizeColor(variant.colors.cardColor, fallback.colors.cardColor);
    const inputColor = ThemeRuntime.normalizeColor(variant.colors.inputColor, fallback.colors.inputColor);
    const primaryTextColor = ThemeRuntime.normalizeColor(variant.colors.primaryTextColor,
      fallback.colors.primaryTextColor);
    const subTextColor = ThemeRuntime.normalizeColor(variant.colors.subTextColor, fallback.colors.subTextColor);
    const dividerColor = ThemeRuntime.normalizeColor(variant.colors.dividerColor, fallback.colors.dividerColor);
    const accentColor = ThemeRuntime.normalizeColor(accentOverride || variant.colors.accentColor,
      fallback.colors.accentColor);
    const buttonColor = ThemeRuntime.normalizeColor(buttonOverride || variant.colors.buttonColor,
      fallback.colors.buttonColor);
    const dangerColor = ThemeRuntime.normalizeColor(variant.colors.dangerColor, fallback.colors.dangerColor);
    const readerBackgroundColor = ThemeRuntime.normalizeColor(variant.reader.backgroundColor,
      fallback.reader.backgroundColor);
    const readerTextColor = ThemeRuntime.normalizeColor(variant.reader.textColor, fallback.reader.textColor);
    const readerSubTextColor = ThemeRuntime.normalizeColor(variant.reader.subTextColor,
      fallback.reader.subTextColor);
    const regexColor = ThemeRuntime.normalizeColor(variant.regexEmphasis.emphasisColor,
      fallback.regexEmphasis.emphasisColor);
    const regexTextColor = ThemeRuntime.normalizeColor(variant.regexEmphasis.emphasisTextColor,
      fallback.regexEmphasis.emphasisTextColor);
    const regexMode = ThemeRuntime.normalizeEmphasisMode(variant.regexEmphasis.emphasisMode,
      fallback.regexEmphasis.emphasisMode);
    const bubbleStyle = ThemeRuntime.normalizeBubbleStyle(variant.regexEmphasis.bubbleStyle,
      fallback.regexEmphasis.bubbleStyle);

    if (darkMode) {
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_PAGE_COLOR, pageColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_CARD_COLOR, cardColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_INPUT_COLOR, inputColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_PRIMARY_TEXT_COLOR, primaryTextColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_SUB_TEXT_COLOR, subTextColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_DIVIDER_COLOR, dividerColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_ACCENT_COLOR, accentColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_BUTTON_COLOR, buttonColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_DANGER_COLOR, dangerColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_READER_BACKGROUND_COLOR, readerBackgroundColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_READER_BACKGROUND_ASSET_ID,
        (variant.reader.backgroundAssetId || '').trim());
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_READER_BACKGROUND_IMAGE_FIT,
        ThemeRuntime.normalizeImageFit(variant.reader.backgroundImageFit, fallback.reader.backgroundImageFit));
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_READER_TEXT_COLOR, readerTextColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_READER_SUB_TEXT_COLOR, readerSubTextColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_READER_CONTENT_TONE,
        ThemeRuntime.normalizeContentTone(variant.reader.contentTone, fallback.reader.contentTone));
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_REGEX_EMPHASIS_MODE, regexMode);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_REGEX_BUBBLE_STYLE, bubbleStyle);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_REGEX_EMPHASIS_COLOR, regexColor);
      ThemeRuntime.setString(ThemeRuntime.KEY_DARK_REGEX_EMPHASIS_TEXT_COLOR, regexTextColor);
      AppStorage.setOrCreate('appDarkAccentColor', accentColor);
      AppStorage.setOrCreate('appDarkButtonColor', buttonColor);
      return;
    }

    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_PAGE_COLOR, pageColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_CARD_COLOR, cardColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_INPUT_COLOR, inputColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_PRIMARY_TEXT_COLOR, primaryTextColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_SUB_TEXT_COLOR, subTextColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_DIVIDER_COLOR, dividerColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_ACCENT_COLOR, accentColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_BUTTON_COLOR, buttonColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_DANGER_COLOR, dangerColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_READER_BACKGROUND_COLOR, readerBackgroundColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_READER_BACKGROUND_ASSET_ID,
      (variant.reader.backgroundAssetId || '').trim());
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_READER_BACKGROUND_IMAGE_FIT,
      ThemeRuntime.normalizeImageFit(variant.reader.backgroundImageFit, fallback.reader.backgroundImageFit));
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_READER_TEXT_COLOR, readerTextColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_READER_SUB_TEXT_COLOR, readerSubTextColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_READER_CONTENT_TONE,
      ThemeRuntime.normalizeContentTone(variant.reader.contentTone, fallback.reader.contentTone));
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_REGEX_EMPHASIS_MODE, regexMode);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_REGEX_BUBBLE_STYLE, bubbleStyle);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_REGEX_EMPHASIS_COLOR, regexColor);
    ThemeRuntime.setString(ThemeRuntime.KEY_LIGHT_REGEX_EMPHASIS_TEXT_COLOR, regexTextColor);
    AppStorage.setOrCreate('appLightAccentColor', accentColor);
    AppStorage.setOrCreate('appLightButtonColor', buttonColor);
  }

  private static currentPack(): ThemePack {
    const themeId = AppStorage.get<string>(ThemeRuntime.KEY_THEME_ID) || BuiltinThemeRegistry.DEFAULT_THEME_ID;
    if (themeId === ThemeIds.CUSTOM) {
      const baseThemeId = AppStorage.get<string>(ThemeRuntime.KEY_CUSTOM_BASE_THEME_ID) ||
        BuiltinThemeRegistry.DEFAULT_THEME_ID;
      return BuiltinThemeRegistry.customTheme(baseThemeId);
    }
    return BuiltinThemeRegistry.findById(themeId);
  }

  private static customSourceTheme(
    category: string,
    darkMode: boolean = AppStorage.get<boolean>('appDarkMode') || false
  ): ThemePack {
    const fallback = AppStorage.get<string>(ThemeRuntime.KEY_CUSTOM_BASE_THEME_ID) ||
      BuiltinThemeRegistry.DEFAULT_THEME_ID;
    const sources = ThemeRuntime.customSources(darkMode, fallback);
    let themeId = fallback;
    if (category === 'startup') themeId = sources.startupThemeId;
    else if (category === 'palette') themeId = sources.paletteThemeId;
    else if (category === 'reader') themeId = sources.readerThemeId;
    else if (category === 'ttsPanel') themeId = sources.ttsPanelThemeId;
    else if (category === 'bubble') themeId = sources.bubbleThemeId;
    else if (category === 'navigation') themeId = sources.navigationThemeId;
    else if (category === 'book') themeId = sources.bookThemeId;
    else if (category === 'typography') themeId = sources.typographyThemeId;
    else if (category === 'layout') themeId = sources.layoutThemeId;
    else if (category === 'radius') themeId = sources.radiusThemeId;
    else if (category === 'glass') themeId = sources.glassThemeId;
    return BuiltinThemeRegistry.findById(themeId);
  }

  private static customSources(darkMode: boolean, fallbackThemeId: string): ThemeComponentSourceIds {
    const fallback = BuiltinThemeRegistry.normalizeBuiltinId(fallbackThemeId);
    const raw = AppStorage.get<string>(darkMode ? ThemeRuntime.KEY_CUSTOM_DARK_SOURCES :
      ThemeRuntime.KEY_CUSTOM_LIGHT_SOURCES) || '';
    let source = new ThemeComponentSourceIds();
    if (raw) {
      try {
        source = JSON.parse(raw) as ThemeComponentSourceIds;
      } catch (_) {
        source = new ThemeComponentSourceIds();
      }
    }
    const normalized = new ThemeComponentSourceIds();
    normalized.startupThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.startupThemeId || fallback);
    normalized.paletteThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.paletteThemeId || fallback);
    normalized.readerThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.readerThemeId || fallback);
    normalized.ttsPanelThemeId = BuiltinThemeRegistry.normalizeBuiltinId(
      source.ttsPanelThemeId || source.readerThemeId || fallback);
    normalized.bubbleThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.bubbleThemeId || fallback);
    normalized.navigationThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.navigationThemeId || fallback);
    normalized.bookThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.bookThemeId || fallback);
    normalized.typographyThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.typographyThemeId || fallback);
    normalized.layoutThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.layoutThemeId || fallback);
    normalized.radiusThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.radiusThemeId || fallback);
    normalized.glassThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.glassThemeId || fallback);
    return normalized;
  }

  private static fallbackVariant(darkMode: boolean): ThemeVariant {
    const theme = ThemeRuntime.currentPack();
    return darkMode ? theme.dark : theme.light;
  }

  private static normalizeColor(value: string, fallback: string): string {
    return HexColor.normalize(value, fallback, '#000000');
  }

  private static normalizeEmphasisMode(value: string, fallback: string): string {
    const mode = (value || '').trim();
    if (mode === ThemeRegexEmphasisModes.NONE || mode === ThemeRegexEmphasisModes.TEXT ||
      mode === ThemeRegexEmphasisModes.HIGHLIGHT || mode === ThemeRegexEmphasisModes.BUBBLE) {
      return mode;
    }
    const fallbackMode = (fallback || '').trim();
    if (fallbackMode === ThemeRegexEmphasisModes.NONE || fallbackMode === ThemeRegexEmphasisModes.TEXT ||
      fallbackMode === ThemeRegexEmphasisModes.HIGHLIGHT || fallbackMode === ThemeRegexEmphasisModes.BUBBLE) {
      return fallbackMode;
    }
    return ThemeRegexEmphasisModes.HIGHLIGHT;
  }

  private static normalizeBubbleStyle(value: string, fallback: string): string {
    const style = (value || '').trim();
    if (style === ThemeBubbleStyles.QQ_SOFT || style === ThemeBubbleStyles.QQ_SOLID ||
      style === ThemeBubbleStyles.CAPSULE || style === ThemeBubbleStyles.PAPER ||
      style === ThemeBubbleStyles.NEON || style === ThemeBubbleStyles.CLASSIC_GLASS ||
      style === ThemeBubbleStyles.WARM_SCROLL || style === ThemeBubbleStyles.FOREST_DEW ||
      style === ThemeBubbleStyles.INK_BRUSH || style === ThemeBubbleStyles.NEON_PULSE ||
      style === ThemeBubbleStyles.STRAWBERRY_RIBBON ||
      style === ThemeBubbleStyles.CRIMSON_STAMP || style === ThemeBubbleStyles.CELADON_SLIP ||
      style === ThemeBubbleStyles.ROSE_FRAME || style === ThemeBubbleStyles.MOON_HALO ||
      style === ThemeBubbleStyles.SWORD_TALISMAN || style === ThemeBubbleStyles.QINGLUAN_JADE ||
      style === ThemeBubbleStyles.PIPI_SOFT_PAW || style === ThemeBubbleStyles.MECHA_COMM ||
      style === ThemeBubbleStyles.STARWISH_RIBBON || style === ThemeBubbleStyles.PENCIL_MARK ||
      style === ThemeBubbleStyles.GILDED_ORBIT || style === ThemeBubbleStyles.HARBOR_POSTCARD) {
      return style;
    }
    const fallbackStyle = (fallback || '').trim();
    if (fallbackStyle === ThemeBubbleStyles.QQ_SOFT || fallbackStyle === ThemeBubbleStyles.QQ_SOLID ||
      fallbackStyle === ThemeBubbleStyles.CAPSULE || fallbackStyle === ThemeBubbleStyles.PAPER ||
      fallbackStyle === ThemeBubbleStyles.NEON || fallbackStyle === ThemeBubbleStyles.CLASSIC_GLASS ||
      fallbackStyle === ThemeBubbleStyles.WARM_SCROLL || fallbackStyle === ThemeBubbleStyles.FOREST_DEW ||
      fallbackStyle === ThemeBubbleStyles.INK_BRUSH || fallbackStyle === ThemeBubbleStyles.NEON_PULSE ||
      fallbackStyle === ThemeBubbleStyles.STRAWBERRY_RIBBON ||
      fallbackStyle === ThemeBubbleStyles.CRIMSON_STAMP || fallbackStyle === ThemeBubbleStyles.CELADON_SLIP ||
      fallbackStyle === ThemeBubbleStyles.ROSE_FRAME || fallbackStyle === ThemeBubbleStyles.MOON_HALO ||
      fallbackStyle === ThemeBubbleStyles.SWORD_TALISMAN ||
      fallbackStyle === ThemeBubbleStyles.QINGLUAN_JADE ||
      fallbackStyle === ThemeBubbleStyles.PIPI_SOFT_PAW ||
      fallbackStyle === ThemeBubbleStyles.MECHA_COMM ||
      fallbackStyle === ThemeBubbleStyles.STARWISH_RIBBON ||
      fallbackStyle === ThemeBubbleStyles.PENCIL_MARK ||
      fallbackStyle === ThemeBubbleStyles.GILDED_ORBIT || fallbackStyle === ThemeBubbleStyles.HARBOR_POSTCARD) {
      return fallbackStyle;
    }
    return ThemeBubbleStyles.QQ_SOFT;
  }

  private static normalizeContentTone(value: string, fallback: string): string {
    const tone = (value || '').trim();
    if (tone === 'light' || tone === 'dark') {
      return tone;
    }
    return fallback === 'dark' ? 'dark' : 'light';
  }

  private static normalizeImageFit(value: string, fallback: string): string {
    const fit = (value || '').trim();
    if (fit === 'cover' || fit === 'contain' || fit === 'fill') {
      return fit;
    }
    const fallbackFit = (fallback || '').trim();
    if (fallbackFit === 'cover' || fallbackFit === 'contain' || fallbackFit === 'fill') {
      return fallbackFit;
    }
    return 'cover';
  }

  private static normalizeRadius(value: number, fallback: number): number {
    if (!Number.isFinite(value)) {
      return Math.max(0, Math.min(Math.round(fallback), 48));
    }
    return Math.max(0, Math.min(Math.round(value), 48));
  }

  private static colorFromStorage(key: string, fallback: string): string {
    return ThemeRuntime.normalizeColor(ThemeRuntime.storageString(key, fallback), fallback);
  }

  private static radiusFromStorage(key: string, fallback: number): number {
    return ThemeRuntime.normalizeRadius(AppStorage.get<number>(key) ?? fallback, fallback);
  }

  private static storageString(key: string, fallback: string): string {
    const value = AppStorage.get<string>(key);
    return value === undefined || !value ? fallback : value;
  }

  private static storageStringAllowEmpty(key: string, fallback: string): string {
    const value = AppStorage.get<string>(key);
    return value === undefined ? fallback : value;
  }

  private static setString(key: string, value: string): void {
    AppStorage.setOrCreate(key, value);
  }

  private static setNumber(key: string, value: number): void {
    AppStorage.setOrCreate(key, value);
  }
}
