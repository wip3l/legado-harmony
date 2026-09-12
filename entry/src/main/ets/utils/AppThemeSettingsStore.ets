import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ThemeComponentSourceIds, ThemeIds, ThemePack } from '../theme/ThemeModels';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ReaderSettings, ReaderSettingsStore } from './ReaderSettingsStore';
import { ReaderThemeHelper, ReaderThemeItem } from './ReaderThemeHelper';
import { CloudSyncChangeTracker } from '../account/CloudSyncChangeTracker';

export class AppThemeSettings {
  themeId: string = '';
  themeBookCoverEnabled: boolean = false;
  // Remembers the last choice made in the "apply theme" prompt. Defaults to off so
  // switching themes preserves the reader's current layout unless the user opts in.
  themeApplyLayoutEnabled: boolean = false;
  lightAccentColor: string = AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR;
  darkAccentColor: string = AppThemeSettingsStore.DEFAULT_DARK_ACCENT_COLOR;
  lightButtonColor: string = AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR;
  darkButtonColor: string = AppThemeSettingsStore.DEFAULT_DARK_BUTTON_COLOR;
  customBaseThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  customLightSources: ThemeComponentSourceIds = new ThemeComponentSourceIds();
  customDarkSources: ThemeComponentSourceIds = new ThemeComponentSourceIds();
  customLightAccentColor: string = AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR;
  customDarkAccentColor: string = AppThemeSettingsStore.DEFAULT_DARK_ACCENT_COLOR;
  customLightButtonColor: string = AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR;
  customDarkButtonColor: string = AppThemeSettingsStore.DEFAULT_DARK_BUTTON_COLOR;
  customLightReaderBackgroundColor: string = '#F7F1E3';
  customLightReaderTextColor: string = '#2F261D';
  customLightReaderSubTextColor: string = '#7A6F63';
  customLightReaderBackgroundAssetId: string = '';
  customLightReaderBackgroundImageFit: string = 'cover';
  customLightReaderContentTone: string = 'light';
  customDarkReaderBackgroundColor: string = '#1F2329';
  customDarkReaderTextColor: string = '#D8D8D8';
  customDarkReaderSubTextColor: string = '#9AA0A6';
  customDarkReaderBackgroundAssetId: string = '';
  customDarkReaderBackgroundImageFit: string = 'cover';
  customDarkReaderContentTone: string = 'dark';
  customLightStartupImagePath: string = '';
  customDarkStartupImagePath: string = '';
  customLightStartupTitle: string = '开源轻页';
  customDarkStartupTitle: string = '开源轻页';
  customLightStartupSubtitle: string = '';
  customDarkStartupSubtitle: string = '';
}

export class AppThemeSettingsStore {
  static readonly KEY_THEME_ID: string = ThemeRuntime.KEY_THEME_ID;
  static readonly KEY_THEME_BOOK_COVER_ENABLED: string = 'appThemeBookCoverEnabled';
  static readonly KEY_THEME_APPLY_LAYOUT_ENABLED: string = 'appThemeApplyLayoutEnabled';
  static readonly KEY_LIGHT_ACCENT_COLOR: string = 'appLightAccentColor';
  static readonly KEY_DARK_ACCENT_COLOR: string = 'appDarkAccentColor';
  static readonly KEY_LIGHT_BUTTON_COLOR: string = 'appLightButtonColor';
  static readonly KEY_DARK_BUTTON_COLOR: string = 'appDarkButtonColor';
  static readonly KEY_CUSTOM_BASE_THEME_ID: string = ThemeRuntime.KEY_CUSTOM_BASE_THEME_ID;
  static readonly KEY_CUSTOM_LIGHT_SOURCES: string = ThemeRuntime.KEY_CUSTOM_LIGHT_SOURCES;
  static readonly KEY_CUSTOM_DARK_SOURCES: string = ThemeRuntime.KEY_CUSTOM_DARK_SOURCES;
  static readonly KEY_CUSTOM_LIGHT_ACCENT_COLOR: string = 'appCustomLightAccentColor';
  static readonly KEY_CUSTOM_DARK_ACCENT_COLOR: string = 'appCustomDarkAccentColor';
  static readonly KEY_CUSTOM_LIGHT_BUTTON_COLOR: string = 'appCustomLightButtonColor';
  static readonly KEY_CUSTOM_DARK_BUTTON_COLOR: string = 'appCustomDarkButtonColor';
  static readonly KEY_CUSTOM_LIGHT_READER_BACKGROUND_COLOR: string = 'appCustomLightReaderBackgroundColor';
  static readonly KEY_CUSTOM_LIGHT_READER_TEXT_COLOR: string = 'appCustomLightReaderTextColor';
  static readonly KEY_CUSTOM_LIGHT_READER_SUB_TEXT_COLOR: string = 'appCustomLightReaderSubTextColor';
  static readonly KEY_CUSTOM_LIGHT_READER_BACKGROUND_ASSET_ID: string = 'appCustomLightReaderBackgroundAssetId';
  static readonly KEY_CUSTOM_LIGHT_READER_BACKGROUND_IMAGE_FIT: string = 'appCustomLightReaderBackgroundImageFit';
  static readonly KEY_CUSTOM_LIGHT_READER_CONTENT_TONE: string = 'appCustomLightReaderContentTone';
  static readonly KEY_CUSTOM_DARK_READER_BACKGROUND_COLOR: string = 'appCustomDarkReaderBackgroundColor';
  static readonly KEY_CUSTOM_DARK_READER_TEXT_COLOR: string = 'appCustomDarkReaderTextColor';
  static readonly KEY_CUSTOM_DARK_READER_SUB_TEXT_COLOR: string = 'appCustomDarkReaderSubTextColor';
  static readonly KEY_CUSTOM_DARK_READER_BACKGROUND_ASSET_ID: string = 'appCustomDarkReaderBackgroundAssetId';
  static readonly KEY_CUSTOM_DARK_READER_BACKGROUND_IMAGE_FIT: string = 'appCustomDarkReaderBackgroundImageFit';
  static readonly KEY_CUSTOM_DARK_READER_CONTENT_TONE: string = 'appCustomDarkReaderContentTone';
  static readonly KEY_CUSTOM_LIGHT_STARTUP_IMAGE_PATH: string = 'appCustomLightStartupImagePath';
  static readonly KEY_CUSTOM_DARK_STARTUP_IMAGE_PATH: string = 'appCustomDarkStartupImagePath';
  static readonly KEY_CUSTOM_LIGHT_STARTUP_TITLE: string = 'appCustomLightStartupTitle';
  static readonly KEY_CUSTOM_DARK_STARTUP_TITLE: string = 'appCustomDarkStartupTitle';
  static readonly KEY_CUSTOM_LIGHT_STARTUP_SUBTITLE: string = 'appCustomLightStartupSubtitle';
  static readonly KEY_CUSTOM_DARK_STARTUP_SUBTITLE: string = 'appCustomDarkStartupSubtitle';
  static readonly DEFAULT_THEME_ID: string = BuiltinThemeRegistry.DEFAULT_THEME_ID;
  static readonly DEFAULT_LIGHT_ACCENT_COLOR: string = '#007DFF';
  static readonly DEFAULT_DARK_ACCENT_COLOR: string = '#4E9BFF';
  static readonly DEFAULT_LIGHT_BUTTON_COLOR: string = '#007DFF';
  static readonly DEFAULT_DARK_BUTTON_COLOR: string = '#3F8CFF';
  private static readonly STORE_NAME: string = 'app_theme_settings';
  private static cachedSettings: AppThemeSettings | null = null;

  static async load(context: Context): Promise<AppThemeSettings> {
    if (AppThemeSettingsStore.cachedSettings) {
      return AppThemeSettingsStore.clone(AppThemeSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, AppThemeSettingsStore.STORE_NAME);
    const settings = new AppThemeSettings();
    const storageThemeId = AppStorage.get<string>(AppThemeSettingsStore.KEY_THEME_ID) ||
      AppThemeSettingsStore.DEFAULT_THEME_ID;
    settings.themeId = AppThemeSettingsStore.normalizeThemeId(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_THEME_ID, storageThemeId));
    settings.themeBookCoverEnabled = await AppThemeSettingsStore.getBoolean(
      store, AppThemeSettingsStore.KEY_THEME_BOOK_COVER_ENABLED,
      AppStorage.get<boolean>(AppThemeSettingsStore.KEY_THEME_BOOK_COVER_ENABLED) || false);
    settings.themeApplyLayoutEnabled = await AppThemeSettingsStore.getBoolean(
      store, AppThemeSettingsStore.KEY_THEME_APPLY_LAYOUT_ENABLED, false);
    const customBaseFallback = BuiltinThemeRegistry.normalizeBuiltinId(settings.themeId);
    settings.customBaseThemeId = BuiltinThemeRegistry.normalizeBuiltinId(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_BASE_THEME_ID,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_BASE_THEME_ID) || customBaseFallback));
    settings.customLightSources = AppThemeSettingsStore.parseSources(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_SOURCES,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_SOURCES) || ''),
    settings.customBaseThemeId);
    settings.customDarkSources = AppThemeSettingsStore.parseSources(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_DARK_SOURCES,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_SOURCES) || ''),
    settings.customBaseThemeId);
    const defaults = AppThemeSettingsStore.defaultsForTheme(
      settings.themeId === ThemeIds.CUSTOM ? settings.customBaseThemeId : settings.themeId);
    settings.lightAccentColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_LIGHT_ACCENT_COLOR,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_LIGHT_ACCENT_COLOR) || defaults.lightAccentColor),
      defaults.lightAccentColor);
    settings.darkAccentColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_DARK_ACCENT_COLOR,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_DARK_ACCENT_COLOR) || defaults.darkAccentColor),
      defaults.darkAccentColor);
    settings.lightButtonColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_LIGHT_BUTTON_COLOR,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_LIGHT_BUTTON_COLOR) || defaults.lightButtonColor),
      defaults.lightButtonColor);
    settings.darkButtonColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_DARK_BUTTON_COLOR,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_DARK_BUTTON_COLOR) || defaults.darkButtonColor),
      defaults.darkButtonColor);
    // The active color keys existed before custom themes. They are the migration fallback so an
    // existing user's four color choices become their initial custom theme without data loss.
    settings.customLightAccentColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_ACCENT_COLOR,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_ACCENT_COLOR) || settings.lightAccentColor),
      settings.lightAccentColor);
    settings.customDarkAccentColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_DARK_ACCENT_COLOR,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_ACCENT_COLOR) || settings.darkAccentColor),
      settings.darkAccentColor);
    settings.customLightButtonColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_BUTTON_COLOR,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_BUTTON_COLOR) || settings.lightButtonColor),
      settings.lightButtonColor);
    settings.customDarkButtonColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_DARK_BUTTON_COLOR,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_BUTTON_COLOR) || settings.darkButtonColor),
      settings.darkButtonColor);
    settings.customLightStartupImagePath = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_IMAGE_PATH,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_IMAGE_PATH) || '');
    settings.customDarkStartupImagePath = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_IMAGE_PATH,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_IMAGE_PATH) || '');
    settings.customLightStartupTitle = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_TITLE,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_TITLE) || '开源轻页');
    settings.customDarkStartupTitle = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_TITLE,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_TITLE) || '开源轻页');
    settings.customLightStartupSubtitle = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_SUBTITLE,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_SUBTITLE) || '');
    settings.customDarkStartupSubtitle = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_SUBTITLE,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_SUBTITLE) || '');
    const needsAppearanceMigration = !(await store.has(
      AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_COLOR));
    await AppThemeSettingsStore.loadMigratedReaderAppearance(context, store, settings, defaults);
    if (settings.themeId === ThemeIds.CUSTOM) {
      AppThemeSettingsStore.useCustomColors(settings);
    }
    if (needsAppearanceMigration) {
      await AppThemeSettingsStore.persistCustomSnapshot(store, settings);
    }
    AppThemeSettingsStore.cachedSettings = AppThemeSettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: AppThemeSettings): Promise<void> {
    const normalized = AppThemeSettingsStore.clone(settings);
    AppThemeSettingsStore.cachedSettings = AppThemeSettingsStore.clone(normalized);
    const store = await preferences.getPreferences(context, AppThemeSettingsStore.STORE_NAME);
    await store.put(AppThemeSettingsStore.KEY_THEME_ID, normalized.themeId);
    await store.put(AppThemeSettingsStore.KEY_THEME_BOOK_COVER_ENABLED, normalized.themeBookCoverEnabled);
    await store.put(AppThemeSettingsStore.KEY_THEME_APPLY_LAYOUT_ENABLED, normalized.themeApplyLayoutEnabled);
    await store.put(AppThemeSettingsStore.KEY_LIGHT_ACCENT_COLOR, normalized.lightAccentColor);
    await store.put(AppThemeSettingsStore.KEY_DARK_ACCENT_COLOR, normalized.darkAccentColor);
    await store.put(AppThemeSettingsStore.KEY_LIGHT_BUTTON_COLOR, normalized.lightButtonColor);
    await store.put(AppThemeSettingsStore.KEY_DARK_BUTTON_COLOR, normalized.darkButtonColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_BASE_THEME_ID, normalized.customBaseThemeId);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_SOURCES,
      JSON.stringify(normalized.customLightSources));
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_SOURCES,
      JSON.stringify(normalized.customDarkSources));
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_ACCENT_COLOR, normalized.customLightAccentColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_ACCENT_COLOR, normalized.customDarkAccentColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_BUTTON_COLOR, normalized.customLightButtonColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_BUTTON_COLOR, normalized.customDarkButtonColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_COLOR,
      normalized.customLightReaderBackgroundColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_TEXT_COLOR, normalized.customLightReaderTextColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_SUB_TEXT_COLOR,
      normalized.customLightReaderSubTextColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_ASSET_ID,
      normalized.customLightReaderBackgroundAssetId);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_IMAGE_FIT,
      normalized.customLightReaderBackgroundImageFit);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_CONTENT_TONE,
      normalized.customLightReaderContentTone);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_COLOR,
      normalized.customDarkReaderBackgroundColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_TEXT_COLOR, normalized.customDarkReaderTextColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_SUB_TEXT_COLOR,
      normalized.customDarkReaderSubTextColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_ASSET_ID,
      normalized.customDarkReaderBackgroundAssetId);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_IMAGE_FIT,
      normalized.customDarkReaderBackgroundImageFit);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_CONTENT_TONE,
      normalized.customDarkReaderContentTone);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_IMAGE_PATH,
      normalized.customLightStartupImagePath);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_IMAGE_PATH,
      normalized.customDarkStartupImagePath);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_TITLE,
      normalized.customLightStartupTitle);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_TITLE,
      normalized.customDarkStartupTitle);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_SUBTITLE,
      normalized.customLightStartupSubtitle);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_SUBTITLE,
      normalized.customDarkStartupSubtitle);
    await store.flush();
    CloudSyncChangeTracker.markPreferenceChanged();
  }

  static applyToStorage(settings: AppThemeSettings): void {
    const normalized = AppThemeSettingsStore.clone(settings);
    AppThemeSettingsStore.cachedSettings = AppThemeSettingsStore.clone(normalized);
    const theme = normalized.themeId === ThemeIds.CUSTOM ?
      AppThemeSettingsStore.customTheme(normalized, AppStorage.get<boolean>('appDarkMode') || false) :
      BuiltinThemeRegistry.findById(normalized.themeId);
    if (normalized.themeId === ThemeIds.CUSTOM) {
      AppThemeSettingsStore.applyCustomAppearance(theme, normalized);
    }
    AppStorage.setOrCreate(ThemeRuntime.KEY_CUSTOM_BASE_THEME_ID, normalized.customBaseThemeId);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_SOURCES,
      JSON.stringify(normalized.customLightSources));
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_SOURCES,
      JSON.stringify(normalized.customDarkSources));
    ThemeRuntime.applyPack(
      theme,
      normalized.lightAccentColor,
      normalized.darkAccentColor,
      normalized.lightButtonColor,
      normalized.darkButtonColor
    );
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_THEME_ID, normalized.themeId);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_THEME_BOOK_COVER_ENABLED,
      normalized.themeBookCoverEnabled);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_LIGHT_ACCENT_COLOR, normalized.lightAccentColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_DARK_ACCENT_COLOR, normalized.darkAccentColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_LIGHT_BUTTON_COLOR, normalized.lightButtonColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_DARK_BUTTON_COLOR, normalized.darkButtonColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_BASE_THEME_ID, normalized.customBaseThemeId);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_SOURCES,
      JSON.stringify(normalized.customLightSources));
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_SOURCES,
      JSON.stringify(normalized.customDarkSources));
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_ACCENT_COLOR, normalized.customLightAccentColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_ACCENT_COLOR, normalized.customDarkAccentColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_BUTTON_COLOR, normalized.customLightButtonColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_BUTTON_COLOR, normalized.customDarkButtonColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_COLOR,
      normalized.customLightReaderBackgroundColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_TEXT_COLOR,
      normalized.customLightReaderTextColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_SUB_TEXT_COLOR,
      normalized.customLightReaderSubTextColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_ASSET_ID,
      normalized.customLightReaderBackgroundAssetId);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_IMAGE_FIT,
      normalized.customLightReaderBackgroundImageFit);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_CONTENT_TONE,
      normalized.customLightReaderContentTone);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_COLOR,
      normalized.customDarkReaderBackgroundColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_TEXT_COLOR,
      normalized.customDarkReaderTextColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_SUB_TEXT_COLOR,
      normalized.customDarkReaderSubTextColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_ASSET_ID,
      normalized.customDarkReaderBackgroundAssetId);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_IMAGE_FIT,
      normalized.customDarkReaderBackgroundImageFit);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_CONTENT_TONE,
      normalized.customDarkReaderContentTone);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_IMAGE_PATH,
      normalized.customLightStartupImagePath);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_IMAGE_PATH,
      normalized.customDarkStartupImagePath);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_TITLE,
      normalized.customLightStartupTitle);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_TITLE,
      normalized.customDarkStartupTitle);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_SUBTITLE,
      normalized.customLightStartupSubtitle);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_SUBTITLE,
      normalized.customDarkStartupSubtitle);
  }

  static accentColor(darkMode: boolean): string {
    return AppStorage.get<string>(darkMode ?
      AppThemeSettingsStore.KEY_DARK_ACCENT_COLOR :
      AppThemeSettingsStore.KEY_LIGHT_ACCENT_COLOR) || (darkMode ?
      AppThemeSettingsStore.DEFAULT_DARK_ACCENT_COLOR :
      AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR);
  }

  static buttonColor(darkMode: boolean): string {
    return AppStorage.get<string>(darkMode ?
      AppThemeSettingsStore.KEY_DARK_BUTTON_COLOR :
      AppThemeSettingsStore.KEY_LIGHT_BUTTON_COLOR) || (darkMode ?
      AppThemeSettingsStore.DEFAULT_DARK_BUTTON_COLOR :
      AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR);
  }

  static createForTheme(themeId: string): AppThemeSettings {
    const normalizedThemeId = AppThemeSettingsStore.normalizeThemeId(themeId);
    const settings = AppThemeSettingsStore.defaultsForTheme(
      normalizedThemeId === ThemeIds.CUSTOM ? BuiltinThemeRegistry.DEFAULT_THEME_ID : normalizedThemeId);
    settings.themeId = normalizedThemeId;
    settings.customBaseThemeId = BuiltinThemeRegistry.normalizeBuiltinId(normalizedThemeId);
    settings.customLightSources = AppThemeSettingsStore.sourcesForTheme(settings.customBaseThemeId);
    settings.customDarkSources = AppThemeSettingsStore.sourcesForTheme(settings.customBaseThemeId);
    settings.customLightAccentColor = settings.lightAccentColor;
    settings.customDarkAccentColor = settings.darkAccentColor;
    settings.customLightButtonColor = settings.lightButtonColor;
    settings.customDarkButtonColor = settings.darkButtonColor;
    if (normalizedThemeId === ThemeIds.CUSTOM) {
      AppThemeSettingsStore.useCustomColors(settings);
    }
    return settings;
  }

  static cloneSettings(settings: AppThemeSettings): AppThemeSettings {
    return AppThemeSettingsStore.clone(settings);
  }

  static applyCustomSnapshot(target: AppThemeSettings, snapshot: AppThemeSettings): AppThemeSettings {
    const settings = AppThemeSettingsStore.clone(target);
    AppThemeSettingsStore.copyCustom(snapshot, settings);
    if (settings.themeId === ThemeIds.CUSTOM) {
      AppThemeSettingsStore.useCustomColors(settings);
    }
    return AppThemeSettingsStore.clone(settings);
  }

  static activateTheme(themeId: string, previous: AppThemeSettings): AppThemeSettings {
    const normalizedThemeId = AppThemeSettingsStore.normalizeThemeId(themeId);
    const settings = AppThemeSettingsStore.defaultsForTheme(normalizedThemeId === ThemeIds.CUSTOM ?
      previous.customBaseThemeId : normalizedThemeId);
    settings.themeId = normalizedThemeId;
    settings.themeBookCoverEnabled = previous.themeBookCoverEnabled;
    AppThemeSettingsStore.copyCustom(previous, settings);
    if (normalizedThemeId === ThemeIds.CUSTOM) {
      AppThemeSettingsStore.useCustomColors(settings);
    }
    return AppThemeSettingsStore.clone(settings);
  }

  static customTheme(settings: AppThemeSettings, darkMode: boolean): ThemePack {
    const normalized = AppThemeSettingsStore.clone(settings);
    const light = normalized.customLightSources;
    const dark = normalized.customDarkSources;
    const theme = BuiltinThemeRegistry.customTheme(normalized.customBaseThemeId);
    theme.light.colors = BuiltinThemeRegistry.findById(light.paletteThemeId).light.colors;
    theme.light.reader = BuiltinThemeRegistry.findById(light.readerThemeId).light.reader;
    theme.light.regexEmphasis = BuiltinThemeRegistry.findById(light.bubbleThemeId).light.regexEmphasis;
    theme.dark.colors = BuiltinThemeRegistry.findById(dark.paletteThemeId).dark.colors;
    theme.dark.reader = BuiltinThemeRegistry.findById(dark.readerThemeId).dark.reader;
    theme.dark.regexEmphasis = BuiltinThemeRegistry.findById(dark.bubbleThemeId).dark.regexEmphasis;
    const active = darkMode ? dark : light;
    const startupTheme = BuiltinThemeRegistry.findById(active.startupThemeId);
    const typographyTheme = BuiltinThemeRegistry.findById(active.typographyThemeId);
    const navigationTheme = BuiltinThemeRegistry.findById(active.navigationThemeId);
    const bookTheme = BuiltinThemeRegistry.findById(active.bookThemeId);
    // Reader typography/layout is shared by both color modes. Keep light as the
    // canonical persisted source for backward-compatible custom-theme data.
    const layoutTheme = BuiltinThemeRegistry.findById(light.layoutThemeId);
    const radiusTheme = BuiltinThemeRegistry.findById(active.radiusThemeId);
    const glassTheme = BuiltinThemeRegistry.findById(active.glassThemeId);
    theme.typography = typographyTheme.typography;
    theme.startup = startupTheme.startup;
    theme.navigation = navigationTheme.navigation;
    theme.book = bookTheme.book;
    theme.readerLayout = layoutTheme.readerLayout;
    theme.radius = radiusTheme.radius;
    theme.glass = glassTheme.glass;
    AppThemeSettingsStore.applyCustomAppearance(theme, normalized);
    theme.light.colors.accentColor = normalized.customLightAccentColor;
    theme.light.colors.buttonColor = normalized.customLightButtonColor;
    theme.dark.colors.accentColor = normalized.customDarkAccentColor;
    theme.dark.colors.buttonColor = normalized.customDarkButtonColor;
    return theme;
  }

  static currentCustomTheme(darkMode: boolean): ThemePack {
    if (AppThemeSettingsStore.cachedSettings) {
      return AppThemeSettingsStore.customTheme(AppThemeSettingsStore.cachedSettings, darkMode);
    }
    const settings = AppThemeSettingsStore.createForTheme(ThemeIds.CUSTOM);
    settings.customBaseThemeId = BuiltinThemeRegistry.normalizeBuiltinId(
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_BASE_THEME_ID) || settings.customBaseThemeId);
    settings.customLightSources = AppThemeSettingsStore.parseSources(
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_SOURCES) || '', settings.customBaseThemeId);
    settings.customDarkSources = AppThemeSettingsStore.parseSources(
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_SOURCES) || '', settings.customBaseThemeId);
    return AppThemeSettingsStore.customTheme(settings, darkMode);
  }

  static reapplyCustomForMode(darkMode: boolean): void {
    if (!AppThemeSettingsStore.cachedSettings ||
      AppThemeSettingsStore.cachedSettings.themeId !== ThemeIds.CUSTOM) {
      return;
    }
    AppThemeSettingsStore.applyToStorage(AppThemeSettingsStore.cachedSettings);
  }

  private static defaultsForTheme(themeId: string): AppThemeSettings {
    const normalizedThemeId = BuiltinThemeRegistry.normalizeBuiltinId(themeId);
    const theme: ThemePack = BuiltinThemeRegistry.findById(normalizedThemeId);
    const settings = new AppThemeSettings();
    settings.themeId = normalizedThemeId;
    settings.customBaseThemeId = normalizedThemeId;
    settings.customLightSources = AppThemeSettingsStore.sourcesForTheme(normalizedThemeId);
    settings.customDarkSources = AppThemeSettingsStore.sourcesForTheme(normalizedThemeId);
    settings.lightAccentColor = AppThemeSettingsStore.normalizeColor(
      theme.light.colors.accentColor, AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR);
    settings.darkAccentColor = AppThemeSettingsStore.normalizeColor(
      theme.dark.colors.accentColor, AppThemeSettingsStore.DEFAULT_DARK_ACCENT_COLOR);
    settings.lightButtonColor = AppThemeSettingsStore.normalizeColor(
      theme.light.colors.buttonColor, AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR);
    settings.darkButtonColor = AppThemeSettingsStore.normalizeColor(
      theme.dark.colors.buttonColor, AppThemeSettingsStore.DEFAULT_DARK_BUTTON_COLOR);
    settings.customLightReaderBackgroundColor = theme.light.reader.backgroundColor;
    settings.customLightReaderTextColor = theme.light.reader.textColor;
    settings.customLightReaderSubTextColor = theme.light.reader.subTextColor;
    settings.customLightReaderBackgroundAssetId = theme.light.reader.backgroundAssetId;
    settings.customLightReaderBackgroundImageFit = theme.light.reader.backgroundImageFit;
    settings.customLightReaderContentTone = theme.light.reader.contentTone;
    settings.customDarkReaderBackgroundColor = theme.dark.reader.backgroundColor;
    settings.customDarkReaderTextColor = theme.dark.reader.textColor;
    settings.customDarkReaderSubTextColor = theme.dark.reader.subTextColor;
    settings.customDarkReaderBackgroundAssetId = theme.dark.reader.backgroundAssetId;
    settings.customDarkReaderBackgroundImageFit = theme.dark.reader.backgroundImageFit;
    settings.customDarkReaderContentTone = theme.dark.reader.contentTone;
    return settings;
  }

  static normalizeThemeId(themeId: string): string {
    return BuiltinThemeRegistry.normalizeId(themeId);
  }

  static normalizeColor(value: string, fallback: string): string {
    const text = (value || '').trim();
    if (/^#[0-9a-fA-F]{6}$/.test(text)) {
      return text.toUpperCase();
    }
    if (/^[0-9a-fA-F]{6}$/.test(text)) {
      return `#${text.toUpperCase()}`;
    }
    return fallback;
  }

  static sourcesForTheme(themeId: string): ThemeComponentSourceIds {
    const normalized = BuiltinThemeRegistry.normalizeBuiltinId(themeId);
    const sources = new ThemeComponentSourceIds();
    sources.startupThemeId = normalized;
    sources.paletteThemeId = normalized;
    sources.readerThemeId = normalized;
    sources.bubbleThemeId = normalized;
    sources.navigationThemeId = normalized;
    sources.bookThemeId = normalized;
    sources.typographyThemeId = normalized;
    sources.layoutThemeId = normalized;
    sources.radiusThemeId = normalized;
    sources.glassThemeId = normalized;
    return sources;
  }

  static cloneSources(source: ThemeComponentSourceIds, fallbackThemeId: string): ThemeComponentSourceIds {
    return AppThemeSettingsStore.normalizeSources(source, fallbackThemeId);
  }

  private static parseSources(raw: string, fallbackThemeId: string): ThemeComponentSourceIds {
    if (!raw) {
      return AppThemeSettingsStore.sourcesForTheme(fallbackThemeId);
    }
    try {
      return AppThemeSettingsStore.normalizeSources(JSON.parse(raw) as ThemeComponentSourceIds, fallbackThemeId);
    } catch (_) {
      return AppThemeSettingsStore.sourcesForTheme(fallbackThemeId);
    }
  }

  private static normalizeSources(
    source: ThemeComponentSourceIds | null | undefined,
    fallbackThemeId: string
  ): ThemeComponentSourceIds {
    const fallback = BuiltinThemeRegistry.normalizeBuiltinId(fallbackThemeId);
    const normalized = new ThemeComponentSourceIds();
    normalized.startupThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.startupThemeId || fallback);
    normalized.paletteThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.paletteThemeId || fallback);
    normalized.readerThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.readerThemeId || fallback);
    normalized.bubbleThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.bubbleThemeId || fallback);
    normalized.navigationThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.navigationThemeId || fallback);
    normalized.bookThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.bookThemeId || fallback);
    normalized.typographyThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.typographyThemeId || fallback);
    normalized.layoutThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.layoutThemeId || fallback);
    normalized.radiusThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.radiusThemeId || fallback);
    normalized.glassThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source?.glassThemeId || fallback);
    return normalized;
  }

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static async getBoolean(
    store: preferences.Preferences,
    key: string,
    fallback: boolean
  ): Promise<boolean> {
    const value = await store.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  private static clone(source: AppThemeSettings): AppThemeSettings {
    const settings = new AppThemeSettings();
    const currentThemeId = AppStorage.get<string>(AppThemeSettingsStore.KEY_THEME_ID) ||
      AppThemeSettingsStore.DEFAULT_THEME_ID;
    settings.themeId = AppThemeSettingsStore.normalizeThemeId(source.themeId || currentThemeId);
    settings.themeBookCoverEnabled = source.themeBookCoverEnabled === true;
    settings.themeApplyLayoutEnabled = source.themeApplyLayoutEnabled === true;
    settings.customBaseThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.customBaseThemeId);
    settings.customLightSources = AppThemeSettingsStore.normalizeSources(
      source.customLightSources, settings.customBaseThemeId);
    settings.customDarkSources = AppThemeSettingsStore.normalizeSources(
      source.customDarkSources, settings.customBaseThemeId);
    settings.customDarkSources.layoutThemeId = settings.customLightSources.layoutThemeId;
    const defaults = AppThemeSettingsStore.defaultsForTheme(settings.themeId === ThemeIds.CUSTOM ?
      settings.customBaseThemeId : settings.themeId);
    settings.lightAccentColor = AppThemeSettingsStore.normalizeColor(
      source.lightAccentColor, defaults.lightAccentColor);
    settings.darkAccentColor = AppThemeSettingsStore.normalizeColor(
      source.darkAccentColor, defaults.darkAccentColor);
    settings.lightButtonColor = AppThemeSettingsStore.normalizeColor(
      source.lightButtonColor, defaults.lightButtonColor);
    settings.darkButtonColor = AppThemeSettingsStore.normalizeColor(
      source.darkButtonColor, defaults.darkButtonColor);
    settings.customLightAccentColor = AppThemeSettingsStore.normalizeColor(
      source.customLightAccentColor, settings.lightAccentColor);
    settings.customDarkAccentColor = AppThemeSettingsStore.normalizeColor(
      source.customDarkAccentColor, settings.darkAccentColor);
    settings.customLightButtonColor = AppThemeSettingsStore.normalizeColor(
      source.customLightButtonColor, settings.lightButtonColor);
    settings.customDarkButtonColor = AppThemeSettingsStore.normalizeColor(
      source.customDarkButtonColor, settings.darkButtonColor);
    settings.customLightReaderBackgroundColor = AppThemeSettingsStore.normalizeColor(
      source.customLightReaderBackgroundColor, defaults.customLightReaderBackgroundColor);
    settings.customLightReaderTextColor = AppThemeSettingsStore.normalizeColor(
      source.customLightReaderTextColor, defaults.customLightReaderTextColor);
    settings.customLightReaderSubTextColor = AppThemeSettingsStore.normalizeColor(
      source.customLightReaderSubTextColor, defaults.customLightReaderSubTextColor);
    settings.customLightReaderBackgroundAssetId = source.customLightReaderBackgroundAssetId || '';
    settings.customLightReaderBackgroundImageFit = source.customLightReaderBackgroundImageFit || 'cover';
    settings.customLightReaderContentTone = source.customLightReaderContentTone === 'dark' ? 'dark' : 'light';
    settings.customDarkReaderBackgroundColor = AppThemeSettingsStore.normalizeColor(
      source.customDarkReaderBackgroundColor, defaults.customDarkReaderBackgroundColor);
    settings.customDarkReaderTextColor = AppThemeSettingsStore.normalizeColor(
      source.customDarkReaderTextColor, defaults.customDarkReaderTextColor);
    settings.customDarkReaderSubTextColor = AppThemeSettingsStore.normalizeColor(
      source.customDarkReaderSubTextColor, defaults.customDarkReaderSubTextColor);
    settings.customDarkReaderBackgroundAssetId = source.customDarkReaderBackgroundAssetId || '';
    settings.customDarkReaderBackgroundImageFit = source.customDarkReaderBackgroundImageFit || 'cover';
    settings.customDarkReaderContentTone = source.customDarkReaderContentTone === 'light' ? 'light' : 'dark';
    settings.customLightStartupImagePath = source.customLightStartupImagePath || '';
    settings.customDarkStartupImagePath = source.customDarkStartupImagePath || '';
    settings.customLightStartupTitle = source.customLightStartupTitle === undefined ?
      '开源轻页' : source.customLightStartupTitle;
    settings.customDarkStartupTitle = source.customDarkStartupTitle === undefined ?
      '开源轻页' : source.customDarkStartupTitle;
    settings.customLightStartupSubtitle = source.customLightStartupSubtitle || '';
    settings.customDarkStartupSubtitle = source.customDarkStartupSubtitle || '';
    if (settings.themeId === ThemeIds.CUSTOM) {
      AppThemeSettingsStore.useCustomColors(settings);
    }
    return settings;
  }

  private static copyCustom(source: AppThemeSettings, target: AppThemeSettings): void {
    target.customBaseThemeId = BuiltinThemeRegistry.normalizeBuiltinId(source.customBaseThemeId);
    target.customLightSources = AppThemeSettingsStore.normalizeSources(
      source.customLightSources, target.customBaseThemeId);
    target.customDarkSources = AppThemeSettingsStore.normalizeSources(
      source.customDarkSources, target.customBaseThemeId);
    target.customDarkSources.layoutThemeId = target.customLightSources.layoutThemeId;
    target.customLightAccentColor = source.customLightAccentColor;
    target.customDarkAccentColor = source.customDarkAccentColor;
    target.customLightButtonColor = source.customLightButtonColor;
    target.customDarkButtonColor = source.customDarkButtonColor;
    target.customLightReaderBackgroundColor = source.customLightReaderBackgroundColor;
    target.customLightReaderTextColor = source.customLightReaderTextColor;
    target.customLightReaderSubTextColor = source.customLightReaderSubTextColor;
    target.customLightReaderBackgroundAssetId = source.customLightReaderBackgroundAssetId;
    target.customLightReaderBackgroundImageFit = source.customLightReaderBackgroundImageFit;
    target.customLightReaderContentTone = source.customLightReaderContentTone;
    target.customDarkReaderBackgroundColor = source.customDarkReaderBackgroundColor;
    target.customDarkReaderTextColor = source.customDarkReaderTextColor;
    target.customDarkReaderSubTextColor = source.customDarkReaderSubTextColor;
    target.customDarkReaderBackgroundAssetId = source.customDarkReaderBackgroundAssetId;
    target.customDarkReaderBackgroundImageFit = source.customDarkReaderBackgroundImageFit;
    target.customDarkReaderContentTone = source.customDarkReaderContentTone;
    target.customLightStartupImagePath = source.customLightStartupImagePath;
    target.customDarkStartupImagePath = source.customDarkStartupImagePath;
    target.customLightStartupTitle = source.customLightStartupTitle;
    target.customDarkStartupTitle = source.customDarkStartupTitle;
    target.customLightStartupSubtitle = source.customLightStartupSubtitle;
    target.customDarkStartupSubtitle = source.customDarkStartupSubtitle;
  }

  private static async loadMigratedReaderAppearance(
    context: Context,
    store: preferences.Preferences,
    settings: AppThemeSettings,
    defaults: AppThemeSettings
  ): Promise<void> {
    const readerSettings: ReaderSettings = await ReaderSettingsStore.load(context);
    const lightReader: ReaderThemeItem = ReaderThemeHelper.themeAt(
      false,
      readerSettings.lightThemeIndex,
      readerSettings.lightCustomThemeBackgroundColor,
      readerSettings.lightCustomThemeTextColor
    );
    const darkReader: ReaderThemeItem = ReaderThemeHelper.themeAt(
      true,
      readerSettings.darkThemeIndex,
      readerSettings.darkCustomThemeBackgroundColor,
      readerSettings.darkCustomThemeTextColor
    );
    settings.customLightReaderBackgroundColor = AppThemeSettingsStore.normalizeColor(
      await AppThemeSettingsStore.getString(store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_COLOR,
        AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_COLOR) ||
          lightReader.backgroundColor),
      defaults.customLightReaderBackgroundColor);
    settings.customLightReaderTextColor = AppThemeSettingsStore.normalizeColor(
      await AppThemeSettingsStore.getString(store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_TEXT_COLOR,
        AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_TEXT_COLOR) || lightReader.textColor),
      defaults.customLightReaderTextColor);
    settings.customLightReaderSubTextColor = AppThemeSettingsStore.normalizeColor(
      await AppThemeSettingsStore.getString(store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_SUB_TEXT_COLOR,
        AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_SUB_TEXT_COLOR) ||
          lightReader.subTextColor),
      defaults.customLightReaderSubTextColor);
    settings.customLightReaderBackgroundAssetId = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_ASSET_ID,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_ASSET_ID) ||
        lightReader.backgroundAssetId);
    settings.customLightReaderBackgroundImageFit = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_IMAGE_FIT,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_IMAGE_FIT) ||
        lightReader.backgroundImageFit || 'cover');
    settings.customLightReaderContentTone = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_CONTENT_TONE,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_CONTENT_TONE) ||
        lightReader.contentTone || 'light');
    settings.customDarkReaderBackgroundColor = AppThemeSettingsStore.normalizeColor(
      await AppThemeSettingsStore.getString(store, AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_COLOR,
        AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_COLOR) ||
          darkReader.backgroundColor),
      defaults.customDarkReaderBackgroundColor);
    settings.customDarkReaderTextColor = AppThemeSettingsStore.normalizeColor(
      await AppThemeSettingsStore.getString(store, AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_TEXT_COLOR,
        AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_TEXT_COLOR) || darkReader.textColor),
      defaults.customDarkReaderTextColor);
    settings.customDarkReaderSubTextColor = AppThemeSettingsStore.normalizeColor(
      await AppThemeSettingsStore.getString(store, AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_SUB_TEXT_COLOR,
        AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_SUB_TEXT_COLOR) || darkReader.subTextColor),
      defaults.customDarkReaderSubTextColor);
    settings.customDarkReaderBackgroundAssetId = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_ASSET_ID,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_ASSET_ID) ||
        darkReader.backgroundAssetId);
    settings.customDarkReaderBackgroundImageFit = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_IMAGE_FIT,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_IMAGE_FIT) ||
        darkReader.backgroundImageFit || 'cover');
    settings.customDarkReaderContentTone = await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_CONTENT_TONE,
      AppStorage.get<string>(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_CONTENT_TONE) ||
        darkReader.contentTone || 'dark');
  }

  private static async persistCustomSnapshot(
    store: preferences.Preferences,
    settings: AppThemeSettings
  ): Promise<void> {
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_BASE_THEME_ID, settings.customBaseThemeId);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_SOURCES,
      JSON.stringify(settings.customLightSources));
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_SOURCES,
      JSON.stringify(settings.customDarkSources));
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_ACCENT_COLOR, settings.customLightAccentColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_ACCENT_COLOR, settings.customDarkAccentColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_BUTTON_COLOR, settings.customLightButtonColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_BUTTON_COLOR, settings.customDarkButtonColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_COLOR,
      settings.customLightReaderBackgroundColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_TEXT_COLOR, settings.customLightReaderTextColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_SUB_TEXT_COLOR,
      settings.customLightReaderSubTextColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_ASSET_ID,
      settings.customLightReaderBackgroundAssetId);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_BACKGROUND_IMAGE_FIT,
      settings.customLightReaderBackgroundImageFit);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_READER_CONTENT_TONE,
      settings.customLightReaderContentTone);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_COLOR,
      settings.customDarkReaderBackgroundColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_TEXT_COLOR, settings.customDarkReaderTextColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_SUB_TEXT_COLOR,
      settings.customDarkReaderSubTextColor);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_ASSET_ID,
      settings.customDarkReaderBackgroundAssetId);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_BACKGROUND_IMAGE_FIT,
      settings.customDarkReaderBackgroundImageFit);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_READER_CONTENT_TONE,
      settings.customDarkReaderContentTone);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_IMAGE_PATH,
      settings.customLightStartupImagePath);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_IMAGE_PATH,
      settings.customDarkStartupImagePath);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_TITLE,
      settings.customLightStartupTitle);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_TITLE,
      settings.customDarkStartupTitle);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_LIGHT_STARTUP_SUBTITLE,
      settings.customLightStartupSubtitle);
    await store.put(AppThemeSettingsStore.KEY_CUSTOM_DARK_STARTUP_SUBTITLE,
      settings.customDarkStartupSubtitle);
    await store.flush();
  }

  private static applyCustomAppearance(theme: ThemePack, settings: AppThemeSettings): void {
    theme.light.reader.backgroundColor = settings.customLightReaderBackgroundColor;
    theme.light.reader.textColor = settings.customLightReaderTextColor;
    theme.light.reader.subTextColor = settings.customLightReaderSubTextColor;
    theme.light.reader.backgroundAssetId = settings.customLightReaderBackgroundAssetId;
    theme.light.reader.backgroundImageFit = settings.customLightReaderBackgroundImageFit;
    theme.light.reader.contentTone = settings.customLightReaderContentTone;
    theme.dark.reader.backgroundColor = settings.customDarkReaderBackgroundColor;
    theme.dark.reader.textColor = settings.customDarkReaderTextColor;
    theme.dark.reader.subTextColor = settings.customDarkReaderSubTextColor;
    theme.dark.reader.backgroundAssetId = settings.customDarkReaderBackgroundAssetId;
    theme.dark.reader.backgroundImageFit = settings.customDarkReaderBackgroundImageFit;
    theme.dark.reader.contentTone = settings.customDarkReaderContentTone;
  }

  private static useCustomColors(settings: AppThemeSettings): void {
    settings.lightAccentColor = settings.customLightAccentColor;
    settings.darkAccentColor = settings.customDarkAccentColor;
    settings.lightButtonColor = settings.customLightButtonColor;
    settings.darkButtonColor = settings.customDarkButtonColor;
  }
}
