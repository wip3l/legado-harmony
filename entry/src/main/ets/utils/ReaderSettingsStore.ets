import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class ReaderSettings {
  fontSize: number = 20;
  lineHeight: number = 32;
  paragraphSpacing: number = 10;
  themeIndex: number = 0;
  pageTurnMode: number = 1;
  preloadEnabled: boolean = true;
  preloadChapterCount: number = 1;
  fontFamily: string = '';
  fontFilePath: string = '';
  fontSourceName: string = '系统默认';
  fontMode: string = 'system';
  systemFontFamily: string = '';
  customFontsRaw: string = '';
  bodyFontMode: string = 'global';
  bodyFontFamily: string = '';
  titleFontMode: string = 'global';
  titleFontFamily: string = '';
  titleFontSize: number = 22;
  regexFontEnabled: boolean = false;
  regexFontPattern: string = '';
  regexFontMode: string = 'global';
  regexFontFamily: string = '';
  regexFontSize: number = 20;
  regexShadowColor: string = '';
  regexFontRulesRaw: string = '';
}

export class ReaderSettingsStore {
  static readonly KEY_FONT_SIZE: string = 'readerFontSize';
  static readonly KEY_LINE_HEIGHT: string = 'readerLineHeight';
  static readonly KEY_PARAGRAPH_SPACING: string = 'readerParagraphSpacing';
  static readonly KEY_THEME_INDEX: string = 'readerThemeIndex';
  static readonly KEY_PAGE_TURN_MODE: string = 'readerPageTurnMode';
  static readonly KEY_PRELOAD_ENABLED: string = 'readerPreloadEnabled';
  static readonly KEY_PRELOAD_CHAPTER_COUNT: string = 'readerPreloadChapterCount';
  static readonly KEY_FONT_FAMILY: string = 'readerFontFamily';
  static readonly KEY_FONT_FILE_PATH: string = 'readerFontFilePath';
  static readonly KEY_FONT_SOURCE_NAME: string = 'readerFontSourceName';
  static readonly KEY_FONT_MODE: string = 'readerFontMode';
  static readonly KEY_SYSTEM_FONT_FAMILY: string = 'readerSystemFontFamily';
  static readonly KEY_CUSTOM_FONTS_RAW: string = 'readerCustomFontsRaw';
  static readonly KEY_BODY_FONT_MODE: string = 'readerBodyFontMode';
  static readonly KEY_BODY_FONT_FAMILY: string = 'readerBodyFontFamily';
  static readonly KEY_TITLE_FONT_MODE: string = 'readerTitleFontMode';
  static readonly KEY_TITLE_FONT_FAMILY: string = 'readerTitleFontFamily';
  static readonly KEY_TITLE_FONT_SIZE: string = 'readerTitleFontSize';
  static readonly KEY_REGEX_FONT_ENABLED: string = 'readerRegexFontEnabled';
  static readonly KEY_REGEX_FONT_PATTERN: string = 'readerRegexFontPattern';
  static readonly KEY_REGEX_FONT_MODE: string = 'readerRegexFontMode';
  static readonly KEY_REGEX_FONT_FAMILY: string = 'readerRegexFontFamily';
  static readonly KEY_REGEX_FONT_SIZE: string = 'readerRegexFontSize';
  static readonly KEY_REGEX_SHADOW_COLOR: string = 'readerRegexShadowColor';
  static readonly KEY_REGEX_FONT_RULES_RAW: string = 'readerRegexFontRulesRaw';
  private static readonly STORE_NAME: string = 'reader_settings';
  private static cachedSettings: ReaderSettings | null = null;

  static async load(context: Context): Promise<ReaderSettings> {
    if (ReaderSettingsStore.cachedSettings) {
      return ReaderSettingsStore.clone(ReaderSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    const settings = new ReaderSettings();
    settings.fontSize = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_FONT_SIZE,
      20,
      'fontSize'
    );
    settings.lineHeight = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_LINE_HEIGHT,
      32,
      'lineHeight'
    );
    settings.paragraphSpacing = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PARAGRAPH_SPACING,
      10,
      'paragraphSpacing'
    );
    settings.themeIndex = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_THEME_INDEX,
      0,
      'themeIndex'
    );
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
    settings.bodyFontMode = ReaderSettingsStore.normalizeFontMode(await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_BODY_FONT_MODE, 'global'));
    settings.bodyFontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_BODY_FONT_FAMILY, '');
    settings.titleFontMode = ReaderSettingsStore.normalizeFontMode(await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_TITLE_FONT_MODE, 'global'));
    settings.titleFontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_TITLE_FONT_FAMILY, '');
    settings.titleFontSize = await ReaderSettingsStore.getNumber(store, ReaderSettingsStore.KEY_TITLE_FONT_SIZE, 22, 'fontSize');
    settings.regexFontEnabled = await ReaderSettingsStore.getBoolean(store, ReaderSettingsStore.KEY_REGEX_FONT_ENABLED, false);
    settings.regexFontPattern = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_FONT_PATTERN, '');
    settings.regexFontMode = ReaderSettingsStore.normalizeFontMode(await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_FONT_MODE, 'global'));
    settings.regexFontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_FONT_FAMILY, '');
    settings.regexFontSize = await ReaderSettingsStore.getNumber(store, ReaderSettingsStore.KEY_REGEX_FONT_SIZE, 20, 'fontSize');
    settings.regexShadowColor = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_SHADOW_COLOR, '');
    settings.regexFontRulesRaw = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_FONT_RULES_RAW, '');
    ReaderSettingsStore.mergeStorageFontSettings(settings);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    return settings;
  }

  static async saveLayoutSettings(
    context: Context,
    fontSize: number,
    lineHeight: number,
    paragraphSpacing: number,
    themeIndex: number
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.fontSize = ReaderSettingsStore.normalizeFontSize(fontSize);
    settings.lineHeight = ReaderSettingsStore.normalizeLineHeight(lineHeight);
    settings.paragraphSpacing = ReaderSettingsStore.normalizeParagraphSpacing(paragraphSpacing);
    settings.themeIndex = ReaderSettingsStore.normalizeThemeIndex(themeIndex);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.applyLayoutToStorage(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_FONT_SIZE, settings.fontSize);
    await store.put(ReaderSettingsStore.KEY_LINE_HEIGHT, settings.lineHeight);
    await store.put(ReaderSettingsStore.KEY_PARAGRAPH_SPACING, settings.paragraphSpacing);
    await store.put(ReaderSettingsStore.KEY_THEME_INDEX, settings.themeIndex);
    await store.flush();
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

  static async saveReaderFontStyleSettings(context: Context, settings: ReaderSettings): Promise<void> {
    const current = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    current.fontSize = ReaderSettingsStore.normalizeFontSize(settings.fontSize || current.fontSize);
    current.bodyFontMode = ReaderSettingsStore.normalizeFontMode(settings.bodyFontMode);
    current.bodyFontFamily = settings.bodyFontFamily || '';
    current.titleFontMode = ReaderSettingsStore.normalizeFontMode(settings.titleFontMode);
    current.titleFontFamily = settings.titleFontFamily || '';
    current.titleFontSize = ReaderSettingsStore.normalizeFontSize(settings.titleFontSize);
    current.regexFontEnabled = settings.regexFontEnabled;
    current.regexFontPattern = settings.regexFontPattern || '';
    current.regexFontMode = ReaderSettingsStore.normalizeFontMode(settings.regexFontMode);
    current.regexFontFamily = settings.regexFontFamily || '';
    current.regexFontSize = ReaderSettingsStore.normalizeFontSize(settings.regexFontSize);
    current.regexShadowColor = settings.regexShadowColor || '';
    current.regexFontRulesRaw = settings.regexFontRulesRaw || '';
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(current);
    ReaderSettingsStore.applyLayoutToStorage(current);
    ReaderSettingsStore.applyReaderFontStyleToStorage(current);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_FONT_SIZE, current.fontSize);
    await store.put(ReaderSettingsStore.KEY_BODY_FONT_MODE, current.bodyFontMode);
    await store.put(ReaderSettingsStore.KEY_BODY_FONT_FAMILY, current.bodyFontFamily);
    await store.put(ReaderSettingsStore.KEY_TITLE_FONT_MODE, current.titleFontMode);
    await store.put(ReaderSettingsStore.KEY_TITLE_FONT_FAMILY, current.titleFontFamily);
    await store.put(ReaderSettingsStore.KEY_TITLE_FONT_SIZE, current.titleFontSize);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_ENABLED, current.regexFontEnabled);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_PATTERN, current.regexFontPattern);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_MODE, current.regexFontMode);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_FAMILY, current.regexFontFamily);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_SIZE, current.regexFontSize);
    await store.put(ReaderSettingsStore.KEY_REGEX_SHADOW_COLOR, current.regexShadowColor);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_RULES_RAW, current.regexFontRulesRaw);
    await store.flush();
  }

  static applyToStorage(settings: ReaderSettings): void {
    const normalized = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.cachedSettings = normalized;
    ReaderSettingsStore.applyLayoutToStorage(normalized);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_MODE, normalized.pageTurnMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PRELOAD_ENABLED, normalized.preloadEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT, normalized.preloadChapterCount);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_FAMILY, normalized.fontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_FILE_PATH, normalized.fontFilePath);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_SOURCE_NAME, normalized.fontSourceName);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_MODE, normalized.fontMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY, normalized.systemFontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW, normalized.customFontsRaw);
    ReaderSettingsStore.applyReaderFontStyleToStorage(normalized);
  }

  private static applyReaderFontStyleToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_BODY_FONT_MODE, settings.bodyFontMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_BODY_FONT_FAMILY, settings.bodyFontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_TITLE_FONT_MODE, settings.titleFontMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_TITLE_FONT_FAMILY, settings.titleFontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_TITLE_FONT_SIZE, settings.titleFontSize);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_ENABLED, settings.regexFontEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_PATTERN, settings.regexFontPattern);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_MODE, settings.regexFontMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_FAMILY, settings.regexFontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_SIZE, settings.regexFontSize);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_SHADOW_COLOR, settings.regexShadowColor);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_RULES_RAW, settings.regexFontRulesRaw);
  }

  private static applyLayoutToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_SIZE, settings.fontSize);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LINE_HEIGHT, settings.lineHeight);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PARAGRAPH_SPACING, settings.paragraphSpacing);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_THEME_INDEX, settings.themeIndex);
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
    if (type === 'fontSize') {
      return ReaderSettingsStore.normalizeFontSize(value);
    }
    if (type === 'lineHeight') {
      return ReaderSettingsStore.normalizeLineHeight(value);
    }
    if (type === 'paragraphSpacing') {
      return ReaderSettingsStore.normalizeParagraphSpacing(value);
    }
    if (type === 'themeIndex') {
      return ReaderSettingsStore.normalizeThemeIndex(value);
    }
    if (type === 'pageTurnMode') {
      return ReaderSettingsStore.normalizePageTurnMode(value);
    }
    if (type === 'preloadChapterCount') {
      return ReaderSettingsStore.normalizePreloadChapterCount(value);
    }
    return fallback;
  }

  private static normalizeFontSize(fontSize: number): number {
    const value = Math.round(fontSize);
    return Math.max(14, Math.min(value, 30));
  }

  private static normalizeLineHeight(lineHeight: number): number {
    const value = Math.round(lineHeight);
    return Math.max(24, Math.min(value, 52));
  }

  private static normalizeParagraphSpacing(paragraphSpacing: number): number {
    const value = Math.round(paragraphSpacing);
    return Math.max(0, Math.min(value, 32));
  }

  private static normalizeThemeIndex(themeIndex: number): number {
    const value = Math.round(themeIndex);
    return value >= 0 && value <= 3 ? value : 0;
  }

  private static normalizePageTurnMode(mode: number): number {
    const value = Math.round(mode);
    return value >= 0 && value <= 2 ? value : 1;
  }

  private static normalizePreloadChapterCount(count: number): number {
    const value = Math.round(count);
    return Math.max(1, Math.min(value, 10));
  }

  private static normalizeFontMode(mode: string): string {
    if (mode === 'system' || mode === 'custom') {
      return mode;
    }
    return 'global';
  }

  private static clone(source: ReaderSettings): ReaderSettings {
    const settings = new ReaderSettings();
    settings.fontSize = ReaderSettingsStore.normalizeFontSize(source.fontSize);
    settings.lineHeight = ReaderSettingsStore.normalizeLineHeight(source.lineHeight);
    settings.paragraphSpacing = ReaderSettingsStore.normalizeParagraphSpacing(source.paragraphSpacing);
    settings.themeIndex = ReaderSettingsStore.normalizeThemeIndex(source.themeIndex);
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(source.pageTurnMode);
    settings.preloadEnabled = source.preloadEnabled;
    settings.preloadChapterCount = ReaderSettingsStore.normalizePreloadChapterCount(source.preloadChapterCount);
    settings.fontFamily = source.fontFamily || '';
    settings.fontFilePath = source.fontFilePath || '';
    settings.fontSourceName = source.fontSourceName || '系统默认';
    settings.fontMode = source.fontMode || 'system';
    settings.systemFontFamily = source.systemFontFamily || '';
    settings.customFontsRaw = source.customFontsRaw || '';
    settings.bodyFontMode = ReaderSettingsStore.normalizeFontMode(source.bodyFontMode);
    settings.bodyFontFamily = source.bodyFontFamily || '';
    settings.titleFontMode = ReaderSettingsStore.normalizeFontMode(source.titleFontMode);
    settings.titleFontFamily = source.titleFontFamily || '';
    settings.titleFontSize = ReaderSettingsStore.normalizeFontSize(source.titleFontSize || 22);
    settings.regexFontEnabled = source.regexFontEnabled;
    settings.regexFontPattern = source.regexFontPattern || '';
    settings.regexFontMode = ReaderSettingsStore.normalizeFontMode(source.regexFontMode);
    settings.regexFontFamily = source.regexFontFamily || '';
    settings.regexFontSize = ReaderSettingsStore.normalizeFontSize(source.regexFontSize || 20);
    settings.regexShadowColor = source.regexShadowColor || '';
    settings.regexFontRulesRaw = source.regexFontRulesRaw || '';
    return settings;
  }

  private static fromStorage(): ReaderSettings {
    const settings = new ReaderSettings();
    settings.fontSize = ReaderSettingsStore.normalizeFontSize(
      AppStorage.get<number>(ReaderSettingsStore.KEY_FONT_SIZE) ?? 20
    );
    settings.lineHeight = ReaderSettingsStore.normalizeLineHeight(
      AppStorage.get<number>(ReaderSettingsStore.KEY_LINE_HEIGHT) ?? 32
    );
    settings.paragraphSpacing = ReaderSettingsStore.normalizeParagraphSpacing(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PARAGRAPH_SPACING) ?? 10
    );
    settings.themeIndex = ReaderSettingsStore.normalizeThemeIndex(
      AppStorage.get<number>(ReaderSettingsStore.KEY_THEME_INDEX) ?? 0
    );
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
    settings.bodyFontMode = ReaderSettingsStore.normalizeFontMode(AppStorage.get<string>(ReaderSettingsStore.KEY_BODY_FONT_MODE) || 'global');
    settings.bodyFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_BODY_FONT_FAMILY) || '';
    settings.titleFontMode = ReaderSettingsStore.normalizeFontMode(AppStorage.get<string>(ReaderSettingsStore.KEY_TITLE_FONT_MODE) || 'global');
    settings.titleFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_TITLE_FONT_FAMILY) || '';
    settings.titleFontSize = ReaderSettingsStore.normalizeFontSize(AppStorage.get<number>(ReaderSettingsStore.KEY_TITLE_FONT_SIZE) ?? 22);
    settings.regexFontEnabled = AppStorage.get<boolean>(ReaderSettingsStore.KEY_REGEX_FONT_ENABLED) ?? false;
    settings.regexFontPattern = AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_FONT_PATTERN) || '';
    settings.regexFontMode = ReaderSettingsStore.normalizeFontMode(AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_FONT_MODE) || 'global');
    settings.regexFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_FONT_FAMILY) || '';
    settings.regexFontSize = ReaderSettingsStore.normalizeFontSize(AppStorage.get<number>(ReaderSettingsStore.KEY_REGEX_FONT_SIZE) ?? 20);
    settings.regexShadowColor = AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_SHADOW_COLOR) || '';
    settings.regexFontRulesRaw = AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_FONT_RULES_RAW) || '';
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
