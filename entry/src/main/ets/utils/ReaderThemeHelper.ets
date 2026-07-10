import { ThemeRuntime } from '../theme/ThemeRuntime';

export class ReaderThemeItem {
  name: string = '';
  backgroundColor: string = '';
  textColor: string = '';
  subTextColor: string = '';
  backgroundAssetId: string = '';
  backgroundImageFit: string = 'cover';
  contentTone: string = 'light';
}

export class ReaderThemeHelper {
  static readonly CUSTOM_THEME_INDEX: number = 3;
  static readonly APP_THEME_INDEX: number = 4;
  static readonly LIGHT_CUSTOM_BACKGROUND_COLOR: string = '#F5F5F5';
  static readonly LIGHT_CUSTOM_TEXT_COLOR: string = '#333333';
  static readonly DARK_CUSTOM_BACKGROUND_COLOR: string = '#1F2329';
  static readonly DARK_CUSTOM_TEXT_COLOR: string = '#D8D8D8';

  static normalizeIndex(index: number): number {
    const value = Math.round(index);
    return value >= 0 && value <= ReaderThemeHelper.APP_THEME_INDEX ? value : 0;
  }

  static lightThemes(customBackgroundColor: string, customTextColor: string): ReaderThemeItem[] {
    return [
      ReaderThemeHelper.theme('米黄', '#F7F1E3', '#2F261D', '#7A6F63'),
      ReaderThemeHelper.theme('素白', '#FFFFFF', '#333333', '#777777'),
      ReaderThemeHelper.theme('青绿', '#E9F3E5', '#26352A', '#657769'),
      ReaderThemeHelper.theme('自定义', customBackgroundColor || ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR,
        customTextColor || ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR,
        ReaderThemeHelper.derivedSubTextColor(false, customTextColor)),
      ReaderThemeHelper.applicationTheme(false)
    ];
  }

  static darkThemes(customBackgroundColor: string, customTextColor: string): ReaderThemeItem[] {
    return [
      ReaderThemeHelper.theme('夜间', '#1F2329', '#D8D8D8', '#9AA0A6'),
      ReaderThemeHelper.theme('墨灰', '#14161A', '#C8CCD3', '#8A8F98'),
      ReaderThemeHelper.theme('深蓝', '#101826', '#D5DFEA', '#8FA2B8'),
      ReaderThemeHelper.theme('自定义', customBackgroundColor || ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR,
        customTextColor || ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR,
        ReaderThemeHelper.derivedSubTextColor(true, customTextColor)),
      ReaderThemeHelper.applicationTheme(true)
    ];
  }

  static themes(darkMode: boolean, customBackgroundColor: string, customTextColor: string): ReaderThemeItem[] {
    return darkMode ?
      ReaderThemeHelper.darkThemes(customBackgroundColor, customTextColor) :
      ReaderThemeHelper.lightThemes(customBackgroundColor, customTextColor);
  }

  static themeAt(darkMode: boolean, index: number, customBackgroundColor: string, customTextColor: string): ReaderThemeItem {
    const items = ReaderThemeHelper.themes(darkMode, customBackgroundColor, customTextColor);
    return items[ReaderThemeHelper.normalizeIndex(index)] || items[0];
  }

  private static applicationTheme(darkMode: boolean): ReaderThemeItem {
    return ReaderThemeHelper.theme(
      '应用主题',
      ThemeRuntime.readerBackgroundColor(darkMode),
      ThemeRuntime.readerTextColor(darkMode),
      ThemeRuntime.readerSubTextColor(darkMode),
      ThemeRuntime.readerBackgroundAssetId(darkMode),
      ThemeRuntime.readerContentTone(darkMode),
      ThemeRuntime.readerBackgroundImageFit(darkMode)
    );
  }

  private static theme(name: string, backgroundColor: string, textColor: string, subTextColor: string,
    backgroundAssetId: string = '', contentTone: string = '', backgroundImageFit: string = 'cover'): ReaderThemeItem {
    const item = new ReaderThemeItem();
    item.name = name;
    item.backgroundColor = backgroundColor;
    item.textColor = textColor;
    item.subTextColor = subTextColor;
    item.backgroundAssetId = backgroundAssetId;
    item.backgroundImageFit = backgroundImageFit;
    item.contentTone = contentTone || (ReaderThemeHelper.isDarkColor(backgroundColor) ? 'dark' : 'light');
    return item;
  }

  private static isDarkColor(color: string): boolean {
    const value = (color || '').trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(value)) {
      return false;
    }
    const red = parseInt(value.substring(1, 3), 16);
    const green = parseInt(value.substring(3, 5), 16);
    const blue = parseInt(value.substring(5, 7), 16);
    return red * 0.299 + green * 0.587 + blue * 0.114 < 128;
  }

  private static derivedSubTextColor(darkMode: boolean, textColor: string): string {
    const normalized = (textColor || '').trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(normalized)) {
      return darkMode ? '#9AA0A6' : '#777777';
    }
    return darkMode ? '#9AA0A6' : '#777777';
  }
}
