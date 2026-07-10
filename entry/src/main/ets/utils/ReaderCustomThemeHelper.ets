import { ReaderThemeHelper } from './ReaderThemeHelper';

export class ReaderCustomThemeScheme {
  id: string = '';
  name: string = '';
  darkMode: boolean = false;
  backgroundColor: string = '';
  textColor: string = '';
  backgroundType: string = 'color';
  backgroundImageUri: string = '';
  backgroundImageFit: string = 'cover';
}

export class ReaderCustomThemeData {
  schemes: ReaderCustomThemeScheme[] = [];
  lightSelectedId: string = '';
  darkSelectedId: string = '';
}

export class ReaderCustomThemeHelper {
  static parse(raw: string, lightBackgroundColor: string, lightTextColor: string,
    darkBackgroundColor: string, darkTextColor: string): ReaderCustomThemeData {
    let source = new ReaderCustomThemeData();
    if ((raw || '').trim()) {
      try {
        source = JSON.parse(raw) as ReaderCustomThemeData;
      } catch (e) {
        console.warn('读取自定义阅读背景失败:', e);
      }
    }
    const data = new ReaderCustomThemeData();
    const schemes = source && Array.isArray(source.schemes) ? source.schemes : [];
    for (let i = 0; i < schemes.length; i++) {
      const item = ReaderCustomThemeHelper.normalizeScheme(schemes[i], i);
      if (item) {
        data.schemes.push(item);
      }
    }
    ReaderCustomThemeHelper.ensureModeScheme(
      data,
      false,
      lightBackgroundColor || ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR,
      lightTextColor || ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    ReaderCustomThemeHelper.ensureModeScheme(
      data,
      true,
      darkBackgroundColor || ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR,
      darkTextColor || ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
    );
    data.lightSelectedId = ReaderCustomThemeHelper.validSelectedId(
      data,
      false,
      source ? source.lightSelectedId : ''
    );
    data.darkSelectedId = ReaderCustomThemeHelper.validSelectedId(
      data,
      true,
      source ? source.darkSelectedId : ''
    );
    return data;
  }

  static stringify(data: ReaderCustomThemeData): string {
    return JSON.stringify(data);
  }

  static schemesForMode(data: ReaderCustomThemeData, darkMode: boolean): ReaderCustomThemeScheme[] {
    return data.schemes.filter((item: ReaderCustomThemeScheme) => item.darkMode === darkMode);
  }

  static selected(data: ReaderCustomThemeData, darkMode: boolean): ReaderCustomThemeScheme {
    const selectedId = darkMode ? data.darkSelectedId : data.lightSelectedId;
    for (const item of data.schemes) {
      if (item.darkMode === darkMode && item.id === selectedId) {
        return item;
      }
    }
    return ReaderCustomThemeHelper.schemesForMode(data, darkMode)[0];
  }

  static select(data: ReaderCustomThemeData, darkMode: boolean, id: string): void {
    const exists = data.schemes.some((item: ReaderCustomThemeScheme) => item.darkMode === darkMode && item.id === id);
    if (!exists) {
      return;
    }
    if (darkMode) {
      data.darkSelectedId = id;
    } else {
      data.lightSelectedId = id;
    }
  }

  static add(data: ReaderCustomThemeData, darkMode: boolean): ReaderCustomThemeScheme {
    const current = ReaderCustomThemeHelper.selected(data, darkMode);
    const count = ReaderCustomThemeHelper.schemesForMode(data, darkMode).length;
    const item = new ReaderCustomThemeScheme();
    item.id = `${darkMode ? 'dark' : 'light'}_${Date.now()}_${count}`;
    item.name = `自定义 ${count + 1}`;
    item.darkMode = darkMode;
    item.backgroundColor = current.backgroundColor;
    item.textColor = current.textColor;
    item.backgroundType = 'color';
    item.backgroundImageFit = current.backgroundImageFit;
    data.schemes.push(item);
    ReaderCustomThemeHelper.select(data, darkMode, item.id);
    return item;
  }

  static removeSelected(data: ReaderCustomThemeData, darkMode: boolean): string {
    const items = ReaderCustomThemeHelper.schemesForMode(data, darkMode);
    if (items.length <= 1) {
      return '';
    }
    const current = ReaderCustomThemeHelper.selected(data, darkMode);
    data.schemes = data.schemes.filter((item: ReaderCustomThemeScheme) => item.id !== current.id);
    const next = ReaderCustomThemeHelper.schemesForMode(data, darkMode)[0];
    ReaderCustomThemeHelper.select(data, darkMode, next.id);
    return current.backgroundImageUri;
  }

  private static ensureModeScheme(data: ReaderCustomThemeData, darkMode: boolean,
    backgroundColor: string, textColor: string): void {
    if (data.schemes.some((item: ReaderCustomThemeScheme) => item.darkMode === darkMode)) {
      return;
    }
    const item = new ReaderCustomThemeScheme();
    item.id = darkMode ? 'legacy-dark' : 'legacy-light';
    item.name = '自定义 1';
    item.darkMode = darkMode;
    item.backgroundColor = ReaderCustomThemeHelper.normalizeColor(backgroundColor,
      darkMode ? ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR : ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR);
    item.textColor = ReaderCustomThemeHelper.normalizeColor(textColor,
      darkMode ? ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR : ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR);
    data.schemes.push(item);
  }

  private static validSelectedId(data: ReaderCustomThemeData, darkMode: boolean, selectedId: string): string {
    const items = ReaderCustomThemeHelper.schemesForMode(data, darkMode);
    return items.some((item: ReaderCustomThemeScheme) => item.id === selectedId) ? selectedId : items[0].id;
  }

  private static normalizeScheme(source: ReaderCustomThemeScheme, index: number): ReaderCustomThemeScheme | null {
    if (!source || typeof source !== 'object') {
      return null;
    }
    const item = new ReaderCustomThemeScheme();
    item.darkMode = source.darkMode === true;
    item.id = (source.id || '').trim() || `${item.darkMode ? 'dark' : 'light'}_restored_${index}`;
    item.name = (source.name || '').trim() || `自定义 ${index + 1}`;
    item.backgroundColor = ReaderCustomThemeHelper.normalizeColor(
      source.backgroundColor,
      item.darkMode ? ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR : ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
    );
    item.textColor = ReaderCustomThemeHelper.normalizeColor(
      source.textColor,
      item.darkMode ? ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR : ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    item.backgroundImageUri = (source.backgroundImageUri || '').trim();
    item.backgroundType = source.backgroundType === 'image' ||
      (!source.backgroundType && !!item.backgroundImageUri) ? 'image' : 'color';
    item.backgroundImageFit = ReaderCustomThemeHelper.normalizeFit(source.backgroundImageFit);
    return item;
  }

  private static normalizeFit(fit: string): string {
    return fit === 'contain' || fit === 'fill' ? fit : 'cover';
  }

  private static normalizeColor(color: string, fallback: string): string {
    const trimmed = (color || '').trim();
    const normalized = trimmed.startsWith('#') ? trimmed : `#${trimmed}`;
    return /^#[0-9a-fA-F]{6}$/.test(normalized) ? normalized.toUpperCase() : fallback;
  }
}
