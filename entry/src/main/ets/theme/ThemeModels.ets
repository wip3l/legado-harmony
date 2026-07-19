export class ThemeIds {
  static readonly CUSTOM: string = 'custom';
  static readonly CLASSIC_BLUE: string = 'classic-blue';
  static readonly WARM_PAPER: string = 'warm-paper';
  static readonly FOREST_MIST: string = 'forest-mist';
  static readonly INK_WASH: string = 'ink-wash';
  static readonly NEON_NIGHT: string = 'neon-night';
  static readonly STRAWBERRY_CREAM: string = 'strawberry-cream';
  static readonly CRIMSON_ARCHIVE: string = 'crimson-archive';
  static readonly PLUM_TEA: string = 'plum-tea';
  static readonly ROSE_LETTER: string = 'rose-letter';
  static readonly MOON_CRANE: string = 'moon-crane';
}

export class ThemeRegexEmphasisModes {
  static readonly INHERIT: string = 'inherit';
  static readonly NONE: string = 'none';
  static readonly TEXT: string = 'text';
  static readonly HIGHLIGHT: string = 'highlight';
  static readonly BUBBLE: string = 'bubble';
}

export class ThemeBubbleStyles {
  static readonly INHERIT: string = 'inherit';
  static readonly QQ_SOFT: string = 'qq-soft';
  static readonly QQ_SOLID: string = 'qq-solid';
  static readonly CAPSULE: string = 'capsule';
  static readonly PAPER: string = 'paper';
  static readonly NEON: string = 'neon';
  static readonly CLASSIC_GLASS: string = 'classic-glass';
  static readonly WARM_SCROLL: string = 'warm-scroll';
  static readonly FOREST_DEW: string = 'forest-dew';
  static readonly INK_BRUSH: string = 'ink-brush';
  static readonly NEON_PULSE: string = 'neon-pulse';
  static readonly STRAWBERRY_RIBBON: string = 'strawberry-ribbon';
  static readonly CRIMSON_STAMP: string = 'crimson-stamp';
  static readonly CELADON_SLIP: string = 'celadon-slip';
  static readonly ROSE_FRAME: string = 'rose-frame';
  static readonly MOON_HALO: string = 'moon-halo';
}

export class ThemeColorTokens {
  pageColor: string = '#F5F5F5';
  cardColor: string = '#FFFFFF';
  inputColor: string = '#F0F2F5';
  primaryTextColor: string = '#1F1F1F';
  subTextColor: string = '#888888';
  dividerColor: string = '#E0E0E0';
  accentColor: string = '#007DFF';
  buttonColor: string = '#007DFF';
  dangerColor: string = '#E53935';
}

export class ThemeReaderTokens {
  backgroundColor: string = '#F7F1E3';
  backgroundAssetId: string = '';
  backgroundImageFit: string = 'cover';
  textColor: string = '#2F261D';
  subTextColor: string = '#7A6F63';
  contentTone: string = 'light';
}

export class ThemeRegexEmphasisTokens {
  emphasisMode: string = ThemeRegexEmphasisModes.BUBBLE;
  bubbleStyle: string = ThemeBubbleStyles.QQ_SOFT;
  emphasisColor: string = '#D9ECFF';
  emphasisTextColor: string = '#1B4168';
}

export class ThemeVariant {
  colors: ThemeColorTokens = new ThemeColorTokens();
  reader: ThemeReaderTokens = new ThemeReaderTokens();
  regexEmphasis: ThemeRegexEmphasisTokens = new ThemeRegexEmphasisTokens();
}

export class ThemeTypographyTokens {
  appFontFamily: string = 'sans-serif';
}

export class ThemeReaderLayoutTokens {
  fontSize: number = 20;
  lineHeight: number = 12;
  paragraphSpacing: number = 10;
  marginLeft: number = 18;
  marginRight: number = 18;
  marginTop: number = 18;
  marginBottom: number = 18;
}

export class ThemeBookTokens {
  coverAssetId: string = ThemeIds.CLASSIC_BLUE;
  shelfFrameAssetId: string = ThemeIds.CLASSIC_BLUE;
  shelfFolderAssetId: string = ThemeIds.CLASSIC_BLUE;
}

export class ThemeNavigationTokens {
  iconPackId: string = 'classic';
}

export class ThemeRadiusTokens {
  small: number = 6;
  medium: number = 10;
  large: number = 16;
  card: number = 10;
  button: number = 20;
  bubble: number = 6;
}

export class ThemeGlassSurfaceTokens {
  blurRadius: number = 22;
  cornerRadius: number = 16;
}

export class ThemeGlassTokens {
  enabled: boolean = true;
  panel: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  popover: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  button: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  overlay: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  menu: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  lightTintOpacity: number = 85;
  darkTintOpacity: number = 78;
  lightBorderOpacity: number = 65;
  darkBorderOpacity: number = 22;
  borderWidth: number = 1;
  shadowEnabled: boolean = true;
  lightShadowOpacity: number = 17;
  darkShadowOpacity: number = 44;
  shadowRadius: number = 18;
  shadowOffsetX: number = 0;
  shadowOffsetY: number = 6;
  adaptiveColor: boolean = true;
  materialScale: number = 1;

  constructor() {
    this.panel.blurRadius = 22;
    this.panel.cornerRadius = 16;
    this.popover.blurRadius = 18;
    this.popover.cornerRadius = 14;
    this.button.blurRadius = 12;
    this.button.cornerRadius = 24;
    this.overlay.blurRadius = 28;
    this.overlay.cornerRadius = 20;
    this.menu.blurRadius = 10;
    this.menu.cornerRadius = 12;
  }
}

export class ThemePack {
  schemaVersion: number = 3;
  id: string = ThemeIds.CLASSIC_BLUE;
  name: string = '经典蓝';
  description: string = '';
  light: ThemeVariant = new ThemeVariant();
  dark: ThemeVariant = new ThemeVariant();
  typography: ThemeTypographyTokens = new ThemeTypographyTokens();
  readerLayout: ThemeReaderLayoutTokens = new ThemeReaderLayoutTokens();
  book: ThemeBookTokens = new ThemeBookTokens();
  navigation: ThemeNavigationTokens = new ThemeNavigationTokens();
  radius: ThemeRadiusTokens = new ThemeRadiusTokens();
  glass: ThemeGlassTokens = new ThemeGlassTokens();
}
