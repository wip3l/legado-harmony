import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class AppIconSettings {
  iconId: string = AppIconSettingsStore.DEFAULT_ICON_ID;
}

export class AppIconSettingsStore {
  static readonly KEY_ICON_ID: string = 'appIconId';
  static readonly DEFAULT_ICON_ID: string = 'default';
  private static readonly STORE_NAME: string = 'app_icon_settings';
  private static cachedSettings: AppIconSettings | null = null;

  static async load(context: Context): Promise<AppIconSettings> {
    if (AppIconSettingsStore.cachedSettings) {
      return AppIconSettingsStore.clone(AppIconSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, AppIconSettingsStore.STORE_NAME);
    const settings = new AppIconSettings();
    settings.iconId = AppIconSettingsStore.normalizeIconId(await AppIconSettingsStore.getString(
      store, AppIconSettingsStore.KEY_ICON_ID, AppIconSettingsStore.DEFAULT_ICON_ID));
    AppIconSettingsStore.cachedSettings = AppIconSettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: AppIconSettings): Promise<void> {
    const normalized = AppIconSettingsStore.clone(settings);
    AppIconSettingsStore.cachedSettings = AppIconSettingsStore.clone(normalized);
    const store = await preferences.getPreferences(context, AppIconSettingsStore.STORE_NAME);
    await store.put(AppIconSettingsStore.KEY_ICON_ID, normalized.iconId);
    await store.flush();
  }

  static applyToStorage(settings: AppIconSettings): void {
    const normalized = AppIconSettingsStore.clone(settings);
    AppIconSettingsStore.cachedSettings = AppIconSettingsStore.clone(normalized);
    AppStorage.setOrCreate(AppIconSettingsStore.KEY_ICON_ID, normalized.iconId);
  }

  static normalizeIconId(value: string): string {
    const text = (value || '').trim();
    if (!text) {
      return AppIconSettingsStore.DEFAULT_ICON_ID;
    }
    return text;
  }

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static clone(source: AppIconSettings): AppIconSettings {
    const settings = new AppIconSettings();
    settings.iconId = AppIconSettingsStore.normalizeIconId(source.iconId);
    return settings;
  }
}
