import {
  ThemeBubbleStyles,
  ThemeColorTokens,
  ThemeGlassTokens,
  ThemeIds,
  ThemePack,
  ThemeRadiusTokens,
  ThemeReaderTokens,
  ThemeRegexEmphasisModes,
  ThemeRegexEmphasisTokens,
  ThemeVariant
} from './ThemeModels';

export class BuiltinThemeRegistry {
  static readonly DEFAULT_THEME_ID: string = ThemeIds.CLASSIC_BLUE;
  static readonly THEMES: ThemePack[] = BuiltinThemeRegistry.createThemes();

  static all(): ThemePack[] {
    const result: ThemePack[] = [];
    for (const theme of BuiltinThemeRegistry.THEMES) {
      result.push(BuiltinThemeRegistry.cloneTheme(theme));
    }
    return result;
  }

  static findById(themeId: string): ThemePack {
    const normalized = (themeId || '').trim();
    if (normalized === ThemeIds.CUSTOM) {
      return BuiltinThemeRegistry.customTheme();
    }
    for (const theme of BuiltinThemeRegistry.THEMES) {
      if (theme.id === normalized) {
        return BuiltinThemeRegistry.cloneTheme(theme);
      }
    }
    return BuiltinThemeRegistry.cloneTheme(BuiltinThemeRegistry.THEMES[0]);
  }

  static normalizeId(themeId: string): string {
    const normalized = (themeId || '').trim();
    if (normalized === ThemeIds.CUSTOM) {
      return ThemeIds.CUSTOM;
    }
    for (const theme of BuiltinThemeRegistry.THEMES) {
      if (theme.id === normalized) {
        return normalized;
      }
    }
    return BuiltinThemeRegistry.DEFAULT_THEME_ID;
  }

  static has(themeId: string): boolean {
    const normalized = (themeId || '').trim();
    if (normalized === ThemeIds.CUSTOM) {
      return true;
    }
    for (const theme of BuiltinThemeRegistry.THEMES) {
      if (theme.id === normalized) {
        return true;
      }
    }
    return false;
  }

  static normalizeBuiltinId(themeId: string): string {
    const normalized = (themeId || '').trim();
    for (const theme of BuiltinThemeRegistry.THEMES) {
      if (theme.id === normalized) {
        return normalized;
      }
    }
    return BuiltinThemeRegistry.DEFAULT_THEME_ID;
  }

  static customTheme(baseThemeId: string = ''): ThemePack {
    const theme = BuiltinThemeRegistry.findById(BuiltinThemeRegistry.normalizeBuiltinId(baseThemeId));
    theme.id = ThemeIds.CUSTOM;
    theme.name = '自定义主题';
    theme.description = '保留你的配色与阅读背景';
    return theme;
  }

  /** Registers a compiled-in theme pack. Reusing an id replaces the previous pack. */
  static register(theme: ThemePack): boolean {
    const themeId = (theme.id || '').trim();
    if (!themeId || !theme.light || !theme.dark) {
      return false;
    }
    theme.id = themeId;
    for (let index = 0; index < BuiltinThemeRegistry.THEMES.length; index++) {
      if (BuiltinThemeRegistry.THEMES[index].id === themeId) {
        BuiltinThemeRegistry.THEMES[index] = BuiltinThemeRegistry.cloneTheme(theme);
        return true;
      }
    }
    BuiltinThemeRegistry.THEMES.push(BuiltinThemeRegistry.cloneTheme(theme));
    return true;
  }

  static registerAll(themes: ThemePack[]): number {
    let registered = 0;
    for (const theme of themes) {
      if (BuiltinThemeRegistry.register(theme)) {
        registered++;
      }
    }
    return registered;
  }

  private static createThemes(): ThemePack[] {
    const themes: ThemePack[] = [];
    themes.push(BuiltinThemeRegistry.classicBlue());
    themes.push(BuiltinThemeRegistry.warmPaper());
    themes.push(BuiltinThemeRegistry.forestMist());
    themes.push(BuiltinThemeRegistry.inkWash());
    themes.push(BuiltinThemeRegistry.neonNight());
    return themes;
  }

  private static classicBlue(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.CLASSIC_BLUE,
      '经典蓝',
      '清爽、克制并延续当前应用视觉的默认主题',
      'sans-serif',
      'classic'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#F5F7FA', '#FFFFFF', '#EEF2F7', '#1F2937', '#667085', '#E4E7EC',
        '#007DFF', '#007DFF', '#E5484D'),
      BuiltinThemeRegistry.reader('#F7F1E3', '', '#2F261D', '#7A6F63', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.QQ_SOFT, '#D9ECFF', '#1B4168')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#101318', '#191D24', '#242A33', '#F2F4F7', '#98A2B3', '#2D3440',
        '#4E9BFF', '#3F8CFF', '#FF6B6B'),
      BuiltinThemeRegistry.reader('#1F2329', '', '#D8D8D8', '#9AA0A6', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.QQ_SOFT, '#173A5E', '#DCEBFF')
    );
    theme.radius = BuiltinThemeRegistry.radius(6, 10, 16, 10, 20, 6);
    return theme;
  }

  private static warmPaper(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.WARM_PAPER,
      '暖纸',
      '温润纸页、棕陶强调色与适合长时间阅读的低对比配色',
      'serif',
      'rounded'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#F6F0E5', '#FFF9EF', '#EFE4D2', '#3A2E24', '#7A6958', '#DDCFBB',
        '#B66A3C', '#A95C32', '#C94A45'),
      BuiltinThemeRegistry.reader('#F8EFD9', 'paper-light', '#35291E', '#806D58', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.PAPER, '#E8D1AD', '#4A3423')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#211A16', '#2B221C', '#382C23', '#F0E2D1', '#B9A38E', '#49392D',
        '#E49A69', '#C77D50', '#F07870'),
      BuiltinThemeRegistry.reader('#241D18', 'paper-dark', '#E4D5C1', '#A9957F', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.PAPER, '#5A3F2C', '#FFE9CE')
    );
    theme.radius = BuiltinThemeRegistry.radius(8, 12, 18, 14, 20, 8);
    return theme;
  }

  private static forestMist(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.FOREST_MIST,
      '林雾',
      '柔和雾绿、自然层次与安静的沉浸阅读氛围',
      'sans-serif',
      'rounded'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#EFF5F0', '#FAFCFA', '#E2ECE4', '#20342A', '#617568', '#CDDDD0',
        '#3F7D5B', '#36704F', '#C74A4A'),
      BuiltinThemeRegistry.reader('#E8F2E7', 'forest-light', '#24362B', '#687D6D', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.CAPSULE, '#CFE6D5', '#234B35')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#101A16', '#17241E', '#203129', '#E5F0E9', '#9BB2A4', '#2E4438',
        '#70B58B', '#5A9D75', '#F06F6F'),
      BuiltinThemeRegistry.reader('#15221B', 'forest-dark', '#D6E4DA', '#8EA496', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.CAPSULE, '#294C38', '#DDF5E5')
    );
    theme.radius = BuiltinThemeRegistry.radius(10, 14, 22, 16, 22, 14);
    return theme;
  }

  private static inkWash(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.INK_WASH,
      '水墨',
      '宣纸灰、墨色层次与简洁利落的东方视觉',
      'serif',
      'ink'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#F2F1ED', '#FAF9F5', '#E7E5DE', '#292A2C', '#6E706F', '#D5D3CC',
        '#4E5D6C', '#394957', '#B74747'),
      BuiltinThemeRegistry.reader('#EEECE4', 'ink-light', '#25282B', '#6C706F', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.QQ_SOLID, '#D9DDE0', '#252B30')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#121416', '#1B1E21', '#25292D', '#ECEEEF', '#A4A9AD', '#34393E',
        '#9AA8B5', '#718493', '#ED7171'),
      BuiltinThemeRegistry.reader('#17191B', 'ink-dark', '#D7D9DA', '#92979B', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.QQ_SOLID, '#3B4248', '#F1F3F4')
    );
    theme.radius = BuiltinThemeRegistry.radius(4, 8, 12, 8, 18, 4);
    return theme;
  }

  private static neonNight(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.NEON_NIGHT,
      '霓虹',
      '蓝紫高饱和强调色与深夜赛博氛围',
      'sans-serif',
      'rounded'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#F3F4FF', '#FFFFFF', '#E8E9FA', '#181A2D', '#646783', '#D8DAEE',
        '#6750FF', '#5840F4', '#E5487D'),
      BuiltinThemeRegistry.reader('#F0F0FF', 'neon-light', '#24253E', '#747795', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.NEON, '#CFEAFF', '#163C67')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#080A14', '#101426', '#171D35', '#F4F5FF', '#9FA8C7', '#252D4C',
        '#00D5FF', '#8A5CFF', '#FF4D8D'),
      BuiltinThemeRegistry.reader('#070B16', 'neon-dark', '#E8F7FF', '#8DA8BD', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.NEON, '#123F55', '#7FF3FF')
    );
    theme.radius = BuiltinThemeRegistry.radius(6, 10, 14, 10, 18, 8);
    return theme;
  }

  private static theme(id: string, name: string, description: string, fontFamily: string,
    iconPackId: string): ThemePack {
    const theme = new ThemePack();
    theme.schemaVersion = 2;
    theme.id = id;
    theme.name = name;
    theme.description = description;
    theme.typography.appFontFamily = fontFamily;
    theme.navigation.iconPackId = iconPackId;
    return theme;
  }

  private static colors(pageColor: string, cardColor: string, inputColor: string, primaryTextColor: string,
    subTextColor: string, dividerColor: string, accentColor: string, buttonColor: string,
    dangerColor: string): ThemeColorTokens {
    const colors = new ThemeColorTokens();
    colors.pageColor = pageColor;
    colors.cardColor = cardColor;
    colors.inputColor = inputColor;
    colors.primaryTextColor = primaryTextColor;
    colors.subTextColor = subTextColor;
    colors.dividerColor = dividerColor;
    colors.accentColor = accentColor;
    colors.buttonColor = buttonColor;
    colors.dangerColor = dangerColor;
    return colors;
  }

  private static reader(backgroundColor: string, backgroundAssetId: string, textColor: string,
    subTextColor: string, contentTone: string): ThemeReaderTokens {
    const reader = new ThemeReaderTokens();
    reader.backgroundColor = backgroundColor;
    reader.backgroundAssetId = backgroundAssetId;
    reader.backgroundImageFit = 'cover';
    reader.textColor = textColor;
    reader.subTextColor = subTextColor;
    reader.contentTone = contentTone;
    return reader;
  }

  private static regex(bubbleStyle: string, emphasisColor: string,
    emphasisTextColor: string): ThemeRegexEmphasisTokens {
    const regex = new ThemeRegexEmphasisTokens();
    regex.emphasisMode = ThemeRegexEmphasisModes.BUBBLE;
    regex.bubbleStyle = bubbleStyle;
    regex.emphasisColor = emphasisColor;
    regex.emphasisTextColor = emphasisTextColor;
    return regex;
  }

  private static variant(colors: ThemeColorTokens, reader: ThemeReaderTokens,
    regexEmphasis: ThemeRegexEmphasisTokens): ThemeVariant {
    const variant = new ThemeVariant();
    variant.colors = colors;
    variant.reader = reader;
    variant.regexEmphasis = regexEmphasis;
    return variant;
  }

  private static radius(small: number, medium: number, large: number, card: number, button: number,
    bubble: number): ThemeRadiusTokens {
    const radius = new ThemeRadiusTokens();
    radius.small = small;
    radius.medium = medium;
    radius.large = large;
    radius.card = card;
    radius.button = button;
    radius.bubble = bubble;
    return radius;
  }

  private static cloneTheme(source: ThemePack): ThemePack {
    const theme = new ThemePack();
    theme.schemaVersion = source.schemaVersion;
    theme.id = source.id;
    theme.name = source.name;
    theme.description = source.description;
    theme.light = BuiltinThemeRegistry.cloneVariant(source.light);
    theme.dark = BuiltinThemeRegistry.cloneVariant(source.dark);
    theme.typography.appFontFamily = source.typography.appFontFamily;
    theme.navigation.iconPackId = source.navigation.iconPackId;
    theme.radius = BuiltinThemeRegistry.radius(source.radius.small, source.radius.medium, source.radius.large,
      source.radius.card, source.radius.button, source.radius.bubble);
    theme.glass = BuiltinThemeRegistry.cloneGlass(source.glass || new ThemeGlassTokens());
    return theme;
  }

  private static cloneGlass(source: ThemeGlassTokens): ThemeGlassTokens {
    const glass = new ThemeGlassTokens();
    glass.enabled = source.enabled;
    glass.panel.blurRadius = source.panel.blurRadius;
    glass.panel.cornerRadius = source.panel.cornerRadius;
    glass.popover.blurRadius = source.popover.blurRadius;
    glass.popover.cornerRadius = source.popover.cornerRadius;
    glass.button.blurRadius = source.button.blurRadius;
    glass.button.cornerRadius = source.button.cornerRadius;
    glass.overlay.blurRadius = source.overlay.blurRadius;
    glass.overlay.cornerRadius = source.overlay.cornerRadius;
    glass.menu.blurRadius = source.menu.blurRadius;
    glass.menu.cornerRadius = source.menu.cornerRadius;
    glass.lightTintOpacity = source.lightTintOpacity;
    glass.darkTintOpacity = source.darkTintOpacity;
    glass.lightBorderOpacity = source.lightBorderOpacity;
    glass.darkBorderOpacity = source.darkBorderOpacity;
    glass.borderWidth = source.borderWidth;
    glass.shadowEnabled = source.shadowEnabled;
    glass.lightShadowOpacity = source.lightShadowOpacity;
    glass.darkShadowOpacity = source.darkShadowOpacity;
    glass.shadowRadius = source.shadowRadius;
    glass.shadowOffsetX = source.shadowOffsetX;
    glass.shadowOffsetY = source.shadowOffsetY;
    glass.adaptiveColor = source.adaptiveColor;
    glass.materialScale = source.materialScale;
    return glass;
  }

  private static cloneVariant(source: ThemeVariant): ThemeVariant {
    return BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors(source.colors.pageColor, source.colors.cardColor, source.colors.inputColor,
        source.colors.primaryTextColor, source.colors.subTextColor, source.colors.dividerColor,
        source.colors.accentColor, source.colors.buttonColor, source.colors.dangerColor),
      BuiltinThemeRegistry.reader(source.reader.backgroundColor, source.reader.backgroundAssetId,
        source.reader.textColor, source.reader.subTextColor, source.reader.contentTone),
      BuiltinThemeRegistry.regex(source.regexEmphasis.bubbleStyle, source.regexEmphasis.emphasisColor,
        source.regexEmphasis.emphasisTextColor)
    );
  }
}
