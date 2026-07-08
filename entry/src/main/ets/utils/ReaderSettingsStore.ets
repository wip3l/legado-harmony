import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ReaderThemeHelper } from './ReaderThemeHelper';

export class ReaderSettings {
  fontSize: number = 20;
  lineHeight: number = 12;
  paragraphSpacing: number = 10;
  themeIndex: number = 0;
  lightThemeIndex: number = 0;
  darkThemeIndex: number = 0;
  lightCustomThemeBackgroundColor: string = ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR;
  lightCustomThemeTextColor: string = ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR;
  darkCustomThemeBackgroundColor: string = ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR;
  darkCustomThemeTextColor: string = ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR;
  pageTurnMode: number = 1;
  pageTurnAnimationType: number = 1;
  volumeTurnPage: boolean = false;
  keepScreenOn: boolean = true;
  extendToStatusBar: boolean = false;
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
  static readonly PAGE_TURN_ANIMATION_NONE: number = 0;
  static readonly PAGE_TURN_ANIMATION_SLIDE: number = 1;
  static readonly PAGE_TURN_ANIMATION_FADE: number = 3;
  static readonly PAGE_TURN_ANIMATION_STACK: number = 4;
  static readonly PAGE_TURN_ANIMATION_VERTICAL: number = 5;
  static readonly KEY_FONT_SIZE: string = 'readerFontSize';
  static readonly KEY_LINE_HEIGHT: string = 'readerLineHeight';
  static readonly KEY_LINE_HEIGHT_MODE: string = 'readerLineHeightMode';
  static readonly KEY_PARAGRAPH_SPACING: string = 'readerParagraphSpacing';
  static readonly KEY_THEME_INDEX: string = 'readerThemeIndex';
  static readonly KEY_LIGHT_THEME_INDEX: string = 'readerLightThemeIndex';
  static readonly KEY_DARK_THEME_INDEX: string = 'readerDarkThemeIndex';
  static readonly KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR: string = 'readerLightCustomThemeBackgroundColor';
  static readonly KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR: string = 'readerLightCustomThemeTextColor';
  static readonly KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR: string = 'readerDarkCustomThemeBackgroundColor';
  static readonly KEY_DARK_CUSTOM_THEME_TEXT_COLOR: string = 'readerDarkCustomThemeTextColor';
  static readonly KEY_PAGE_TURN_MODE: string = 'readerPageTurnMode';
  static readonly KEY_PAGE_TURN_ANIMATION: string = 'readerPageTurnAnimation';
  static readonly KEY_PAGE_TURN_ANIMATION_TYPE: string = 'readerPageTurnAnimationType';
  static readonly KEY_VOLUME_TURN_PAGE: string = 'readerVolumeTurnPage';
  static readonly KEY_KEEP_SCREEN_ON: string = 'readerKeepScreenOn';
  static readonly KEY_EXTEND_TO_STATUS_BAR: string = 'readerExtendToStatusBar';
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
      'legacyLineHeight',
      settings.fontSize,
      await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_LINE_HEIGHT_MODE, '')
    );
    settings.paragraphSpacing = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PARAGRAPH_SPACING,
      10,
      'paragraphSpacing'
    );
    const legacyThemeIndex = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_THEME_INDEX,
      0,
      'themeIndex'
    );
    settings.themeIndex = legacyThemeIndex;
    settings.lightThemeIndex = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_LIGHT_THEME_INDEX,
      legacyThemeIndex,
      'themeIndex'
    );
    settings.darkThemeIndex = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_DARK_THEME_INDEX,
      legacyThemeIndex,
      'themeIndex'
    );
    settings.lightCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR,
        ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
      ),
      ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
    );
    settings.lightCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR,
        ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
      ),
      ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    settings.darkCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR,
        ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
      ),
      ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
    );
    settings.darkCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_TEXT_COLOR,
        ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
      ),
      ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
    );
    settings.pageTurnMode = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PAGE_TURN_MODE,
      1,
      'pageTurnMode'
    );
    const legacyPageTurnAnimation = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION) ?? true
    );
    const storedPageTurnAnimationType = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE,
      legacyPageTurnAnimation ?
        ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE :
        ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE,
      'pageTurnAnimationType'
    );
    settings.pageTurnAnimationType = legacyPageTurnAnimation ?
      storedPageTurnAnimationType :
      ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE;
    settings.volumeTurnPage = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_VOLUME_TURN_PAGE,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_VOLUME_TURN_PAGE) ?? false
    );
    settings.keepScreenOn = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_KEEP_SCREEN_ON,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_KEEP_SCREEN_ON) ?? true
    );
    settings.extendToStatusBar = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR) ?? false
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
    _themeIndex?: number
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.fontSize = ReaderSettingsStore.normalizeFontSize(fontSize);
    settings.lineHeight = ReaderSettingsStore.normalizeLineHeight(lineHeight);
    settings.paragraphSpacing = ReaderSettingsStore.normalizeParagraphSpacing(paragraphSpacing);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.applyLayoutToStorage(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_FONT_SIZE, settings.fontSize);
    await store.put(ReaderSettingsStore.KEY_LINE_HEIGHT, settings.lineHeight);
    await store.put(ReaderSettingsStore.KEY_LINE_HEIGHT_MODE, 'spacing');
    await store.put(ReaderSettingsStore.KEY_PARAGRAPH_SPACING, settings.paragraphSpacing);
    await store.flush();
  }

  static async saveThemeSettings(
    context: Context,
    lightThemeIndex: number,
    darkThemeIndex: number,
    lightCustomThemeBackgroundColor: string,
    lightCustomThemeTextColor: string,
    darkCustomThemeBackgroundColor: string,
    darkCustomThemeTextColor: string,
    currentDarkMode: boolean
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.lightThemeIndex = ReaderSettingsStore.normalizeThemeIndex(lightThemeIndex);
    settings.darkThemeIndex = ReaderSettingsStore.normalizeThemeIndex(darkThemeIndex);
    settings.lightCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      lightCustomThemeBackgroundColor,
      ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
    );
    settings.lightCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      lightCustomThemeTextColor,
      ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    settings.darkCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      darkCustomThemeBackgroundColor,
      ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
    );
    settings.darkCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      darkCustomThemeTextColor,
      ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
    );
    settings.themeIndex = currentDarkMode ? settings.darkThemeIndex : settings.lightThemeIndex;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.applyThemeToStorage(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_THEME_INDEX, settings.themeIndex);
    await store.put(ReaderSettingsStore.KEY_LIGHT_THEME_INDEX, settings.lightThemeIndex);
    await store.put(ReaderSettingsStore.KEY_DARK_THEME_INDEX, settings.darkThemeIndex);
    await store.put(
      ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR,
      settings.lightCustomThemeBackgroundColor
    );
    await store.put(ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR, settings.lightCustomThemeTextColor);
    await store.put(
      ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR,
      settings.darkCustomThemeBackgroundColor
    );
    await store.put(ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_TEXT_COLOR, settings.darkCustomThemeTextColor);
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

  static async saveReadingInteractionSettings(
    context: Context,
    volumeTurnPage: boolean,
    keepScreenOn: boolean,
    extendToStatusBar: boolean
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.volumeTurnPage = volumeTurnPage;
    settings.keepScreenOn = keepScreenOn;
    settings.extendToStatusBar = extendToStatusBar;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.applyInteractionToStorage(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_VOLUME_TURN_PAGE, settings.volumeTurnPage);
    await store.put(ReaderSettingsStore.KEY_KEEP_SCREEN_ON, settings.keepScreenOn);
    await store.put(ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR, settings.extendToStatusBar);
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

  static async savePageTurnAnimationType(context: Context, type: number): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.pageTurnAnimationType = ReaderSettingsStore.normalizePageTurnAnimationType(type);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE, settings.pageTurnAnimationType);
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION,
      settings.pageTurnAnimationType !== ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE
    );
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE, settings.pageTurnAnimationType);
    await store.put(
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION,
      settings.pageTurnAnimationType !== ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE
    );
    await store.flush();
  }

  static applyToStorage(settings: ReaderSettings): void {
    const normalized = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.cachedSettings = normalized;
    ReaderSettingsStore.applyLayoutToStorage(normalized);
    ReaderSettingsStore.applyThemeToStorage(normalized);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_MODE, normalized.pageTurnMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE, normalized.pageTurnAnimationType);
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION,
      normalized.pageTurnAnimationType !== ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE
    );
    ReaderSettingsStore.applyInteractionToStorage(normalized);
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

  private static applyInteractionToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_VOLUME_TURN_PAGE, settings.volumeTurnPage);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_KEEP_SCREEN_ON, settings.keepScreenOn);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR, settings.extendToStatusBar);
  }

  private static applyLayoutToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_SIZE, settings.fontSize);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LINE_HEIGHT, settings.lineHeight);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LINE_HEIGHT_MODE, 'spacing');
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PARAGRAPH_SPACING, settings.paragraphSpacing);
  }

  private static applyThemeToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_THEME_INDEX, settings.themeIndex);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LIGHT_THEME_INDEX, settings.lightThemeIndex);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_DARK_THEME_INDEX, settings.darkThemeIndex);
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR,
      settings.lightCustomThemeBackgroundColor
    );
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR,
      settings.lightCustomThemeTextColor
    );
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR,
      settings.darkCustomThemeBackgroundColor
    );
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_TEXT_COLOR,
      settings.darkCustomThemeTextColor
    );
  }

  private static async getNumber(
    store: preferences.Preferences,
    key: string,
    fallback: number,
    type: string,
    fontSize: number = 20,
    lineHeightMode: string = ''
  ): Promise<number> {
    const value = await store.get(key, fallback);
    if (typeof value === 'number') {
      return ReaderSettingsStore.normalizeNumber(value, type, fallback, fontSize, lineHeightMode);
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      if (!Number.isNaN(parsed)) {
        return ReaderSettingsStore.normalizeNumber(parsed, type, fallback, fontSize, lineHeightMode);
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

  private static normalizeNumber(
    value: number,
    type: string,
    fallback: number,
    fontSize: number = 20,
    lineHeightMode: string = ''
  ): number {
    if (type === 'fontSize') {
      return ReaderSettingsStore.normalizeFontSize(value);
    }
    if (type === 'lineHeight') {
      return ReaderSettingsStore.normalizeLineHeight(value);
    }
    if (type === 'legacyLineHeight') {
      return lineHeightMode === 'spacing' ?
        ReaderSettingsStore.normalizeLineHeight(value) :
        ReaderSettingsStore.normalizeLegacyLineHeight(value, fontSize);
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
    if (type === 'pageTurnAnimationType') {
      return ReaderSettingsStore.normalizePageTurnAnimationType(value);
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
    return Math.max(0, Math.min(value, 52));
  }

  private static normalizeLegacyLineHeight(lineHeight: number, fontSize: number): number {
    const value = Math.round(lineHeight);
    if (value >= 24) {
      return ReaderSettingsStore.normalizeLineHeight(value - ReaderSettingsStore.normalizeFontSize(fontSize));
    }
    return ReaderSettingsStore.normalizeLineHeight(value);
  }

  private static normalizeParagraphSpacing(paragraphSpacing: number): number {
    const value = Math.round(paragraphSpacing);
    return Math.max(0, Math.min(value, 32));
  }

  private static normalizeThemeIndex(themeIndex: number): number {
    return ReaderThemeHelper.normalizeIndex(themeIndex);
  }

  private static normalizeColor(color: string, fallback: string): string {
    const trimmed = (color || '').trim();
    const normalized = trimmed.startsWith('#') ? trimmed : `#${trimmed}`;
    if (/^#[0-9a-fA-F]{6}$/.test(normalized)) {
      return normalized.toUpperCase();
    }
    const fallbackTrimmed = (fallback || '').trim();
    const normalizedFallback = fallbackTrimmed.startsWith('#') ? fallbackTrimmed : `#${fallbackTrimmed}`;
    return /^#[0-9a-fA-F]{6}$/.test(normalizedFallback) ? normalizedFallback.toUpperCase() : '#333333';
  }

  private static normalizePageTurnMode(mode: number): number {
    const value = Math.round(mode);
    return value >= 0 && value <= 2 ? value : 1;
  }

  private static normalizePageTurnAnimationType(type: number): number {
    const value = Math.round(type);
    if (value === ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK) {
      return value;
    }
    return ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
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
    settings.lightThemeIndex = ReaderSettingsStore.normalizeThemeIndex(source.lightThemeIndex);
    settings.darkThemeIndex = ReaderSettingsStore.normalizeThemeIndex(source.darkThemeIndex);
    settings.lightCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      source.lightCustomThemeBackgroundColor,
      ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
    );
    settings.lightCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      source.lightCustomThemeTextColor,
      ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    settings.darkCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      source.darkCustomThemeBackgroundColor,
      ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
    );
    settings.darkCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      source.darkCustomThemeTextColor,
      ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
    );
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(source.pageTurnMode);
    settings.pageTurnAnimationType = ReaderSettingsStore.normalizePageTurnAnimationType(source.pageTurnAnimationType);
    settings.volumeTurnPage = source.volumeTurnPage;
    settings.keepScreenOn = source.keepScreenOn;
    settings.extendToStatusBar = source.extendToStatusBar;
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
    const storageLineHeight = AppStorage.get<number>(ReaderSettingsStore.KEY_LINE_HEIGHT) ?? 32;
    settings.lineHeight = AppStorage.get<string>(ReaderSettingsStore.KEY_LINE_HEIGHT_MODE) === 'spacing' ?
      ReaderSettingsStore.normalizeLineHeight(storageLineHeight) :
      ReaderSettingsStore.normalizeLegacyLineHeight(storageLineHeight, settings.fontSize);
    settings.paragraphSpacing = ReaderSettingsStore.normalizeParagraphSpacing(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PARAGRAPH_SPACING) ?? 10
    );
    const legacyThemeIndex = ReaderSettingsStore.normalizeThemeIndex(
      AppStorage.get<number>(ReaderSettingsStore.KEY_THEME_INDEX) ?? 0
    );
    settings.themeIndex = legacyThemeIndex;
    settings.lightThemeIndex = ReaderSettingsStore.normalizeThemeIndex(
      AppStorage.get<number>(ReaderSettingsStore.KEY_LIGHT_THEME_INDEX) ?? legacyThemeIndex
    );
    settings.darkThemeIndex = ReaderSettingsStore.normalizeThemeIndex(
      AppStorage.get<number>(ReaderSettingsStore.KEY_DARK_THEME_INDEX) ?? legacyThemeIndex
    );
    settings.lightCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      AppStorage.get<string>(ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR) || '',
      ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
    );
    settings.lightCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      AppStorage.get<string>(ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR) || '',
      ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    settings.darkCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      AppStorage.get<string>(ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR) || '',
      ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
    );
    settings.darkCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      AppStorage.get<string>(ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_TEXT_COLOR) || '',
      ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
    );
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PAGE_TURN_MODE) ?? 1
    );
    const legacyPageTurnAnimation = AppStorage.get<boolean>(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION) ?? true;
    const storagePageTurnAnimationType = ReaderSettingsStore.normalizePageTurnAnimationType(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE) ??
        (legacyPageTurnAnimation ?
          ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE :
          ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE)
    );
    settings.pageTurnAnimationType = legacyPageTurnAnimation ?
      storagePageTurnAnimationType :
      ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE;
    settings.volumeTurnPage = AppStorage.get<boolean>(ReaderSettingsStore.KEY_VOLUME_TURN_PAGE) ?? false;
    settings.keepScreenOn = AppStorage.get<boolean>(ReaderSettingsStore.KEY_KEEP_SCREEN_ON) ?? true;
    settings.extendToStatusBar = AppStorage.get<boolean>(ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR) ?? false;
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
