export class ReaderThemeItem {
  name: string = '';
  backgroundColor: string = '';
  textColor: string = '';
  subTextColor: string = '';
}

export class ReaderThemeHelper {
  static readonly CUSTOM_THEME_INDEX: number = 3;
  static readonly LIGHT_CUSTOM_BACKGROUND_COLOR: string = '#F5F5F5';
  static readonly LIGHT_CUSTOM_TEXT_COLOR: string = '#333333';
  static readonly DARK_CUSTOM_BACKGROUND_COLOR: string = '#1F2329';
  static readonly DARK_CUSTOM_TEXT_COLOR: string = '#D8D8D8';

  static normalizeIndex(index: number): number {
    const value = Math.round(index);
    return value >= 0 && value <= ReaderThemeHelper.CUSTOM_THEME_INDEX ? value : 0;
  }

  static lightThemes(customBackgroundColor: string, customTextColor: string): ReaderThemeItem[] {
    return [
      ReaderThemeHelper.theme('米黄', '#F7F1E3', '#2F261D', '#7A6F63'),
      ReaderThemeHelper.theme('素白', '#FFFFFF', '#333333', '#777777'),
      ReaderThemeHelper.theme('青绿', '#E9F3E5', '#26352A', '#657769'),
      ReaderThemeHelper.theme('自定义', customBackgroundColor || ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR,
        customTextColor || ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR,
        ReaderThemeHelper.derivedSubTextColor(false, customTextColor))
    ];
  }

  static darkThemes(customBackgroundColor: string, customTextColor: string): ReaderThemeItem[] {
    return [
      ReaderThemeHelper.theme('夜间', '#1F2329', '#D8D8D8', '#9AA0A6'),
      ReaderThemeHelper.theme('墨灰', '#14161A', '#C8CCD3', '#8A8F98'),
      ReaderThemeHelper.theme('深蓝', '#101826', '#D5DFEA', '#8FA2B8'),
      ReaderThemeHelper.theme('自定义', customBackgroundColor || ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR,
        customTextColor || ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR,
        ReaderThemeHelper.derivedSubTextColor(true, customTextColor))
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

  private static theme(name: string, backgroundColor: string, textColor: string, subTextColor: string): ReaderThemeItem {
    const item = new ReaderThemeItem();
    item.name = name;
    item.backgroundColor = backgroundColor;
    item.textColor = textColor;
    item.subTextColor = subTextColor;
    return item;
  }

  private static derivedSubTextColor(darkMode: boolean, textColor: string): string {
    const normalized = (textColor || '').trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(normalized)) {
      return darkMode ? '#9AA0A6' : '#777777';
    }
    return darkMode ? '#9AA0A6' : '#777777';
  }
}
