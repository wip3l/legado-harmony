import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class AppThemeSettings {
  lightAccentColor: string = AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR;
  darkAccentColor: string = AppThemeSettingsStore.DEFAULT_DARK_ACCENT_COLOR;
  lightButtonColor: string = AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR;
  darkButtonColor: string = AppThemeSettingsStore.DEFAULT_DARK_BUTTON_COLOR;
}

export class AppThemeSettingsStore {
  static readonly KEY_LIGHT_ACCENT_COLOR: string = 'appLightAccentColor';
  static readonly KEY_DARK_ACCENT_COLOR: string = 'appDarkAccentColor';
  static readonly KEY_LIGHT_BUTTON_COLOR: string = 'appLightButtonColor';
  static readonly KEY_DARK_BUTTON_COLOR: string = 'appDarkButtonColor';
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
    settings.lightAccentColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_LIGHT_ACCENT_COLOR, AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR),
      AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR);
    settings.darkAccentColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_DARK_ACCENT_COLOR, AppThemeSettingsStore.DEFAULT_DARK_ACCENT_COLOR),
      AppThemeSettingsStore.DEFAULT_DARK_ACCENT_COLOR);
    settings.lightButtonColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_LIGHT_BUTTON_COLOR, AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR),
      AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR);
    settings.darkButtonColor = AppThemeSettingsStore.normalizeColor(await AppThemeSettingsStore.getString(
      store, AppThemeSettingsStore.KEY_DARK_BUTTON_COLOR, AppThemeSettingsStore.DEFAULT_DARK_BUTTON_COLOR),
      AppThemeSettingsStore.DEFAULT_DARK_BUTTON_COLOR);
    AppThemeSettingsStore.cachedSettings = AppThemeSettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: AppThemeSettings): Promise<void> {
    const normalized = AppThemeSettingsStore.clone(settings);
    AppThemeSettingsStore.cachedSettings = AppThemeSettingsStore.clone(normalized);
    const store = await preferences.getPreferences(context, AppThemeSettingsStore.STORE_NAME);
    await store.put(AppThemeSettingsStore.KEY_LIGHT_ACCENT_COLOR, normalized.lightAccentColor);
    await store.put(AppThemeSettingsStore.KEY_DARK_ACCENT_COLOR, normalized.darkAccentColor);
    await store.put(AppThemeSettingsStore.KEY_LIGHT_BUTTON_COLOR, normalized.lightButtonColor);
    await store.put(AppThemeSettingsStore.KEY_DARK_BUTTON_COLOR, normalized.darkButtonColor);
    await store.flush();
  }

  static applyToStorage(settings: AppThemeSettings): void {
    const normalized = AppThemeSettingsStore.clone(settings);
    AppThemeSettingsStore.cachedSettings = AppThemeSettingsStore.clone(normalized);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_LIGHT_ACCENT_COLOR, normalized.lightAccentColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_DARK_ACCENT_COLOR, normalized.darkAccentColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_LIGHT_BUTTON_COLOR, normalized.lightButtonColor);
    AppStorage.setOrCreate(AppThemeSettingsStore.KEY_DARK_BUTTON_COLOR, normalized.darkButtonColor);
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

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static clone(source: AppThemeSettings): AppThemeSettings {
    const settings = new AppThemeSettings();
    settings.lightAccentColor = AppThemeSettingsStore.normalizeColor(
      source.lightAccentColor, AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR);
    settings.darkAccentColor = AppThemeSettingsStore.normalizeColor(
      source.darkAccentColor, AppThemeSettingsStore.DEFAULT_DARK_ACCENT_COLOR);
    settings.lightButtonColor = AppThemeSettingsStore.normalizeColor(
      source.lightButtonColor, AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR);
    settings.darkButtonColor = AppThemeSettingsStore.normalizeColor(
      source.darkButtonColor, AppThemeSettingsStore.DEFAULT_DARK_BUTTON_COLOR);
    return settings;
  }
}
