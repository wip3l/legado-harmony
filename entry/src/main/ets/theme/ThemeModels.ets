export class ThemeIds {
  static readonly CUSTOM: string = 'custom';
  static readonly CLASSIC_BLUE: string = 'classic-blue';
  static readonly WARM_PAPER: string = 'warm-paper';
  static readonly FOREST_MIST: string = 'forest-mist';
  static readonly INK_WASH: string = 'ink-wash';
  static readonly NEON_NIGHT: string = 'neon-night';
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

export class ThemePack {
  schemaVersion: number = 1;
  id: string = ThemeIds.CLASSIC_BLUE;
  name: string = '经典蓝';
  description: string = '';
  light: ThemeVariant = new ThemeVariant();
  dark: ThemeVariant = new ThemeVariant();
  typography: ThemeTypographyTokens = new ThemeTypographyTokens();
  navigation: ThemeNavigationTokens = new ThemeNavigationTokens();
  radius: ThemeRadiusTokens = new ThemeRadiusTokens();
}
