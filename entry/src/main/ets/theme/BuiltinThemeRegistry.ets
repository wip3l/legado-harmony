import {
  ThemeBubbleStyles,
  ThemeColorTokens,
  ThemeGlassTokens,
  ThemeIds,
  ThemePack,
  ThemeRadiusTokens,
  ThemeReaderLayoutTokens,
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
    for (const theme of BuiltinThemeRegistry.THEMES) {
      if (theme.id === BuiltinThemeRegistry.DEFAULT_THEME_ID) {
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
    themes.push(BuiltinThemeRegistry.strawberryCream());
    themes.push(BuiltinThemeRegistry.crimsonArchive());
    themes.push(BuiltinThemeRegistry.plumTea());
    themes.push(BuiltinThemeRegistry.roseLetter());
    themes.push(BuiltinThemeRegistry.moonCrane());
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
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.CLASSIC_GLASS, '#70B6F2', '#1B4168')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#101318', '#191D24', '#242A33', '#F2F4F7', '#98A2B3', '#2D3440',
        '#4E9BFF', '#3F8CFF', '#FF6B6B'),
      BuiltinThemeRegistry.reader('#1F2329', '', '#D8D8D8', '#9AA0A6', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.CLASSIC_GLASS, '#4E9BFF', '#DCEBFF')
    );
    theme.radius = BuiltinThemeRegistry.radius(6, 10, 16, 10, 20, 6);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(20, 12, 10, 18, 18, 18, 18);
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
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.WARM_SCROLL, '#C99355', '#4A3423')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#211A16', '#2B221C', '#382C23', '#F0E2D1', '#B9A38E', '#49392D',
        '#E49A69', '#C77D50', '#F07870'),
      BuiltinThemeRegistry.reader('#241D18', 'paper-dark', '#E4D5C1', '#A9957F', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.WARM_SCROLL, '#D8955B', '#FFE9CE')
    );
    theme.radius = BuiltinThemeRegistry.radius(8, 12, 18, 14, 20, 8);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(21, 14, 12, 22, 22, 22, 22);
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
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.FOREST_DEW, '#75A887', '#234B35')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#101A16', '#17241E', '#203129', '#E5F0E9', '#9BB2A4', '#2E4438',
        '#70B58B', '#5A9D75', '#F06F6F'),
      BuiltinThemeRegistry.reader('#15221B', 'forest-dark', '#D6E4DA', '#8EA496', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.FOREST_DEW, '#69AD84', '#DDF5E5')
    );
    theme.radius = BuiltinThemeRegistry.radius(10, 14, 22, 16, 22, 14);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(20, 14, 11, 22, 22, 22, 22);
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
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.INK_BRUSH, '#687580', '#252B30')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#121416', '#1B1E21', '#25292D', '#ECEEEF', '#A4A9AD', '#34393E',
        '#9AA8B5', '#718493', '#ED7171'),
      BuiltinThemeRegistry.reader('#17191B', 'ink-dark', '#D7D9DA', '#92979B', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.INK_BRUSH, '#9AA8B5', '#F1F3F4')
    );
    theme.radius = BuiltinThemeRegistry.radius(4, 8, 12, 8, 18, 4);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(21, 15, 13, 24, 24, 22, 24);
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
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.NEON_PULSE, '#5E7BFF', '#163C67')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#080A14', '#101426', '#171D35', '#F4F5FF', '#9FA8C7', '#252D4C',
        '#00D5FF', '#8A5CFF', '#FF4D8D'),
      BuiltinThemeRegistry.reader('#070B16', 'neon-dark', '#E8F7FF', '#8DA8BD', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.NEON_PULSE, '#00D5FF', '#A9F7FF')
    );
    theme.radius = BuiltinThemeRegistry.radius(6, 10, 14, 10, 18, 8);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(19, 13, 10, 20, 20, 20, 20);
    return theme;
  }

  private static strawberryCream(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.STRAWBERRY_CREAM,
      '草莓奶霜',
      '奶白纸笺、草莓粉与雾蓝气泡组成的轻甜手帐主题',
      'serif',
      'strawberry'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#FFF7F4', '#FFFCF9', '#F8E9E7', '#593B38', '#9A706C', '#F0D5D2',
        '#E76E77', '#DD5C67', '#D84F5A'),
      BuiltinThemeRegistry.reader('#FFF9F2', 'strawberry-light', '#533B38', '#9B716D', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.STRAWBERRY_RIBBON, '#B8D8EC', '#41657E')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#241B20', '#30242A', '#403139', '#F8E9E5', '#C49A98', '#533B45',
        '#FF929B', '#F27D88', '#FF777F'),
      BuiltinThemeRegistry.reader('#261D22', 'strawberry-dark', '#F2DEDA', '#BE9492', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.STRAWBERRY_RIBBON, '#6D9BB8', '#D8EEFC')
    );
    theme.radius = BuiltinThemeRegistry.radius(10, 16, 24, 18, 24, 16);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(20, 13, 11, 20, 20, 22, 22);
    theme.glass = BuiltinThemeRegistry.glass(20, 18, 88, 74, 58, 24, 16, 4);
    return theme;
  }

  private static crimsonArchive(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.CRIMSON_ARCHIVE,
      '赤墨档案',
      '黑白拼贴、赤色线迹与档案纸张构成的冷峻编辑风',
      'serif',
      'crimson'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#EFEEEA', '#F8F7F3', '#E4E2DD', '#211F1D', '#6D6863', '#CFCBC4',
        '#8D211C', '#791A17', '#B43A34'),
      BuiltinThemeRegistry.reader('#F1F0EC', 'crimson-light', '#252220', '#6F6862', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.CRIMSON_STAMP, '#8D211C', '#74201C')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#11100F', '#1B1918', '#272422', '#EEEAE4', '#A9A19A', '#393532',
        '#D55A50', '#B8453E', '#F07569'),
      BuiltinThemeRegistry.reader('#141311', 'crimson-dark', '#E9E5DE', '#AAA29A', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.CRIMSON_STAMP, '#C74F47', '#FFEAE4')
    );
    theme.radius = BuiltinThemeRegistry.radius(2, 5, 9, 5, 8, 3);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(19, 14, 12, 22, 22, 20, 22);
    theme.glass = BuiltinThemeRegistry.glass(10, 7, 94, 86, 42, 18, 10, 2);
    return theme;
  }

  private static plumTea(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.PLUM_TEA,
      '梅影茶烟',
      '梅枝、青瓷与窗棂边框点染的宋韵雅读主题',
      'serif',
      'plum'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#F4F0E8', '#FBF8F1', '#E8E9DF', '#3C3028', '#7B7066', '#D8D1C4',
        '#557A68', '#486B5B', '#A34D48'),
      BuiltinThemeRegistry.reader('#F8F4EA', 'plum-tea-light', '#49372E', '#817268', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.CELADON_SLIP, '#9FBBAA', '#405A4D')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#181A17', '#22241F', '#2D3029', '#EAE5D9', '#ACA697', '#3C4037',
        '#84A795', '#6F927F', '#D4746B'),
      BuiltinThemeRegistry.reader('#1B1D19', 'plum-tea-dark', '#E3DDD0', '#A69F91', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.CELADON_SLIP, '#73927F', '#E6F0E8')
    );
    theme.radius = BuiltinThemeRegistry.radius(5, 9, 15, 9, 16, 4);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(21, 14, 12, 26, 26, 24, 24);
    theme.glass = BuiltinThemeRegistry.glass(18, 14, 90, 78, 52, 22, 14, 4);
    return theme;
  }

  private static roseLetter(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.ROSE_LETTER,
      '玫瑰来信',
      '复古信纸、酒红玫瑰与柔金细节交织的浪漫主题',
      'serif',
      'rose'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#FAF3ED', '#FFF9F4', '#F3E3DE', '#583B3D', '#987071', '#E6CDC7',
        '#A84550', '#963B46', '#C34E58'),
      BuiltinThemeRegistry.reader('#FCF6EE', 'rose-letter-light', '#5B3A3C', '#936B6D', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.ROSE_FRAME, '#C77A83', '#7E3540')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#211719', '#2C1F22', '#3A2A2E', '#F4E4E1', '#C49B9C', '#4B353A',
        '#D87983', '#C8626D', '#F07B82'),
      BuiltinThemeRegistry.reader('#241A1C', 'rose-letter-dark', '#EEDCDA', '#BB9294', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.ROSE_FRAME, '#B9606A', '#FFE8E6')
    );
    theme.radius = BuiltinThemeRegistry.radius(8, 14, 22, 16, 22, 14);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(20, 13, 12, 24, 24, 22, 22);
    theme.glass = BuiltinThemeRegistry.glass(24, 20, 84, 72, 62, 28, 20, 5);
    return theme;
  }

  private static moonCrane(): ThemePack {
    const theme = BuiltinThemeRegistry.theme(
      ThemeIds.MOON_CRANE,
      '月鹤星河',
      '月银、鹤影与深海蓝黑构成的静谧夜读主题',
      'serif',
      'crane'
    );
    theme.light = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#EEF3F8', '#F8FBFE', '#E3EAF2', '#25344A', '#6E7E94', '#CCD7E4',
        '#5879A7', '#496A97', '#B74F62'),
      BuiltinThemeRegistry.reader('#EEF3F8', 'moon-crane-light', '#30425E', '#72829A', 'light'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.MOON_HALO, '#8BBEFF', '#315777')
    );
    theme.dark = BuiltinThemeRegistry.variant(
      BuiltinThemeRegistry.colors('#070D17', '#0D1624', '#142033', '#DCE9FC', '#8298B6', '#22324A',
        '#8BBEFF', '#72A7ED', '#FF748B'),
      BuiltinThemeRegistry.reader('#07101C', 'moon-crane-dark', '#C8DCFA', '#7F98BA', 'dark'),
      BuiltinThemeRegistry.regex(ThemeBubbleStyles.MOON_HALO, '#78B9F3', '#D5EEFF')
    );
    theme.radius = BuiltinThemeRegistry.radius(8, 13, 20, 14, 22, 11);
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(20, 15, 12, 24, 24, 22, 24);
    theme.glass = BuiltinThemeRegistry.glass(30, 22, 70, 58, 58, 28, 24, 3);
    return theme;
  }

  private static theme(id: string, name: string, description: string, fontFamily: string,
    iconPackId: string): ThemePack {
    const theme = new ThemePack();
    theme.schemaVersion = 3;
    theme.id = id;
    theme.name = name;
    theme.description = description;
    theme.typography.appFontFamily = fontFamily;
    theme.navigation.iconPackId = iconPackId;
    theme.book.coverAssetId = id;
    theme.book.shelfFrameAssetId = id;
    theme.book.shelfFolderAssetId = id;
    return theme;
  }

  private static readerLayout(fontSize: number, lineHeight: number, paragraphSpacing: number,
    marginLeft: number, marginRight: number, marginTop: number, marginBottom: number): ThemeReaderLayoutTokens {
    const layout = new ThemeReaderLayoutTokens();
    layout.fontSize = fontSize;
    layout.lineHeight = lineHeight;
    layout.paragraphSpacing = paragraphSpacing;
    layout.marginLeft = marginLeft;
    layout.marginRight = marginRight;
    layout.marginTop = marginTop;
    layout.marginBottom = marginBottom;
    return layout;
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

  private static glass(blur: number, cornerRadius: number, lightTintOpacity: number,
    darkTintOpacity: number, lightBorderOpacity: number, darkBorderOpacity: number,
    shadowRadius: number, shadowOffsetY: number): ThemeGlassTokens {
    const glass = new ThemeGlassTokens();
    glass.panel.blurRadius = blur;
    glass.popover.blurRadius = Math.max(0, blur - 4);
    glass.button.blurRadius = Math.max(0, blur - 8);
    glass.overlay.blurRadius = Math.min(40, blur + 4);
    glass.menu.blurRadius = Math.max(0, blur - 10);
    glass.panel.cornerRadius = cornerRadius;
    glass.popover.cornerRadius = Math.max(0, cornerRadius - 2);
    glass.button.cornerRadius = Math.min(32, cornerRadius + 6);
    glass.overlay.cornerRadius = Math.min(32, cornerRadius + 4);
    glass.menu.cornerRadius = Math.max(0, cornerRadius - 4);
    glass.lightTintOpacity = lightTintOpacity;
    glass.darkTintOpacity = darkTintOpacity;
    glass.lightBorderOpacity = lightBorderOpacity;
    glass.darkBorderOpacity = darkBorderOpacity;
    glass.shadowRadius = shadowRadius;
    glass.shadowOffsetY = shadowOffsetY;
    return glass;
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
    theme.readerLayout = BuiltinThemeRegistry.readerLayout(source.readerLayout.fontSize,
      source.readerLayout.lineHeight, source.readerLayout.paragraphSpacing, source.readerLayout.marginLeft,
      source.readerLayout.marginRight, source.readerLayout.marginTop, source.readerLayout.marginBottom);
    theme.book.coverAssetId = source.book.coverAssetId;
    theme.book.shelfFrameAssetId = source.book.shelfFrameAssetId;
    theme.book.shelfFolderAssetId = source.book.shelfFolderAssetId;
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
