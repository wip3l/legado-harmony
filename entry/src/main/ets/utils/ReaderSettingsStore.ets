import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class ReaderSettings {
  pageTurnMode: number = 1;
  preloadEnabled: boolean = true;
  preloadChapterCount: number = 1;
  fontFamily: string = '';
  fontFilePath: string = '';
  fontSourceName: string = '系统默认';
  fontMode: string = 'system';
  systemFontFamily: string = '';
  customFontsRaw: string = '';
}

export class ReaderSettingsStore {
  static readonly KEY_PAGE_TURN_MODE: string = 'readerPageTurnMode';
  static readonly KEY_PRELOAD_ENABLED: string = 'readerPreloadEnabled';
  static readonly KEY_PRELOAD_CHAPTER_COUNT: string = 'readerPreloadChapterCount';
  static readonly KEY_FONT_FAMILY: string = 'readerFontFamily';
  static readonly KEY_FONT_FILE_PATH: string = 'readerFontFilePath';
  static readonly KEY_FONT_SOURCE_NAME: string = 'readerFontSourceName';
  static readonly KEY_FONT_MODE: string = 'readerFontMode';
  static readonly KEY_SYSTEM_FONT_FAMILY: string = 'readerSystemFontFamily';
  static readonly KEY_CUSTOM_FONTS_RAW: string = 'readerCustomFontsRaw';
  private static readonly STORE_NAME: string = 'reader_settings';
  private static cachedSettings: ReaderSettings | null = null;

  static async load(context: Context): Promise<ReaderSettings> {
    if (ReaderSettingsStore.cachedSettings) {
      return ReaderSettingsStore.clone(ReaderSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    const settings = new ReaderSettings();
    settings.pageTurnMode = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PAGE_TURN_MODE,
      1,
      'pageTurnMode'
    );
    settings.preloadEnabled = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_PRELOAD_ENABLED,
      true
    );
    settings.preloadChapterCount = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT,
      1,
      'preloadChapterCount'
    );
    settings.fontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FONT_FAMILY, '');
    settings.fontFilePath = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FONT_FILE_PATH, '');
    settings.fontSourceName = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FONT_SOURCE_NAME, '系统默认');
    settings.fontMode = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FONT_MODE, 'system');
    settings.systemFontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY, '');
    settings.customFontsRaw = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW, '');
    ReaderSettingsStore.mergeStorageFontSettings(settings);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    return settings;
  }

  static async savePageTurnMode(context: Context, mode: number): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(mode);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PAGE_TURN_MODE, settings.pageTurnMode);
    await store.flush();
  }

  static async savePreloadEnabled(context: Context, enabled: boolean): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.preloadEnabled = enabled;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PRELOAD_ENABLED, settings.preloadEnabled);
    await store.flush();
  }

  static async savePreloadChapterCount(context: Context, count: number): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.preloadChapterCount = ReaderSettingsStore.normalizePreloadChapterCount(count);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT, settings.preloadChapterCount);
    await store.flush();
  }

  static async saveFontSettings(
    context: Context,
    fontFamily: string,
    fontFilePath: string,
    fontSourceName: string,
    fontMode: string,
    systemFontFamily: string,
    customFontsRaw: string
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.fontFamily = fontFamily || '';
    settings.fontFilePath = fontFilePath || '';
    settings.fontSourceName = fontSourceName || '系统默认';
    settings.fontMode = fontMode || 'system';
    settings.systemFontFamily = systemFontFamily || '';
    settings.customFontsRaw = customFontsRaw || '';
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_FONT_FAMILY, settings.fontFamily);
    await store.put(ReaderSettingsStore.KEY_FONT_FILE_PATH, settings.fontFilePath);
    await store.put(ReaderSettingsStore.KEY_FONT_SOURCE_NAME, settings.fontSourceName);
    await store.put(ReaderSettingsStore.KEY_FONT_MODE, settings.fontMode);
    await store.put(ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY, settings.systemFontFamily);
    await store.put(ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW, settings.customFontsRaw);
    await store.flush();
  }

  static applyToStorage(settings: ReaderSettings): void {
    const normalized = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.cachedSettings = normalized;
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_MODE, normalized.pageTurnMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PRELOAD_ENABLED, normalized.preloadEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT, normalized.preloadChapterCount);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_FAMILY, normalized.fontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_FILE_PATH, normalized.fontFilePath);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_SOURCE_NAME, normalized.fontSourceName);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_MODE, normalized.fontMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY, normalized.systemFontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW, normalized.customFontsRaw);
  }

  private static async getNumber(
    store: preferences.Preferences,
    key: string,
    fallback: number,
    type: string
  ): Promise<number> {
    const value = await store.get(key, fallback);
    if (typeof value === 'number') {
      return ReaderSettingsStore.normalizeNumber(value, type, fallback);
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      if (!Number.isNaN(parsed)) {
        return ReaderSettingsStore.normalizeNumber(parsed, type, fallback);
      }
    }
    return fallback;
  }

  private static async getBoolean(
    store: preferences.Preferences,
    key: string,
    fallback: boolean
  ): Promise<boolean> {
    const value = await store.get(key, fallback);
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    if (typeof value === 'string') {
      return value === 'true' || value === '1';
    }
    return fallback;
  }

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    if (typeof value === 'string') {
      return value;
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value);
    }
    return fallback;
  }

  private static normalizeNumber(value: number, type: string, fallback: number): number {
    if (type === 'pageTurnMode') {
      return ReaderSettingsStore.normalizePageTurnMode(value);
    }
    if (type === 'preloadChapterCount') {
      return ReaderSettingsStore.normalizePreloadChapterCount(value);
    }
    return fallback;
  }

  private static normalizePageTurnMode(mode: number): number {
    const value = Math.round(mode);
    return value >= 0 && value <= 2 ? value : 1;
  }

  private static normalizePreloadChapterCount(count: number): number {
    const value = Math.round(count);
    return Math.max(1, Math.min(value, 10));
  }

  private static clone(source: ReaderSettings): ReaderSettings {
    const settings = new ReaderSettings();
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(source.pageTurnMode);
    settings.preloadEnabled = source.preloadEnabled;
    settings.preloadChapterCount = ReaderSettingsStore.normalizePreloadChapterCount(source.preloadChapterCount);
    settings.fontFamily = source.fontFamily || '';
    settings.fontFilePath = source.fontFilePath || '';
    settings.fontSourceName = source.fontSourceName || '系统默认';
    settings.fontMode = source.fontMode || 'system';
    settings.systemFontFamily = source.systemFontFamily || '';
    settings.customFontsRaw = source.customFontsRaw || '';
    return settings;
  }

  private static fromStorage(): ReaderSettings {
    const settings = new ReaderSettings();
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PAGE_TURN_MODE) ?? 1
    );
    settings.preloadEnabled = AppStorage.get<boolean>(ReaderSettingsStore.KEY_PRELOAD_ENABLED) ?? true;
    settings.preloadChapterCount = ReaderSettingsStore.normalizePreloadChapterCount(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT) ?? 1
    );
    settings.fontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_FAMILY) || '';
    settings.fontFilePath = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_FILE_PATH) || '';
    settings.fontSourceName = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_SOURCE_NAME) || '系统默认';
    settings.fontMode = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_MODE) || 'system';
    settings.systemFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY) || '';
    settings.customFontsRaw = AppStorage.get<string>(ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW) || '';
    return settings;
  }

  private static mergeStorageFontSettings(settings: ReaderSettings): void {
    const storageFontFilePath = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_FILE_PATH) || '';
    const storageCustomFontsRaw = AppStorage.get<string>(ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW) || '';
    if (!settings.fontFilePath && storageFontFilePath) {
      settings.fontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_FAMILY) || '';
      settings.fontFilePath = storageFontFilePath;
      settings.fontSourceName = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_SOURCE_NAME) || '系统默认';
      settings.fontMode = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_MODE) || 'custom';
      settings.systemFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY) || '';
    }
    if (!settings.customFontsRaw && storageCustomFontsRaw) {
      settings.customFontsRaw = storageCustomFontsRaw;
    }
  }
}
