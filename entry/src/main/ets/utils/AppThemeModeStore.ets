import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class AppThemeModeStore {
  static readonly KEY_THEME_MODE: string = 'appThemeMode';
  private static readonly STORE_NAME: string = 'app_theme_mode';
  private static cachedMode: string = '';

  static async load(context: Context): Promise<string> {
    if (AppThemeModeStore.cachedMode) {
      return AppThemeModeStore.cachedMode;
    }
    const store = await preferences.getPreferences(context, AppThemeModeStore.STORE_NAME);
    const fallback = AppStorage.get<string>(AppThemeModeStore.KEY_THEME_MODE) || 'system';
    const value = await store.get(AppThemeModeStore.KEY_THEME_MODE, fallback);
    const mode = typeof value === 'string' ? AppThemeModeStore.normalizeMode(value) : 'system';
    AppThemeModeStore.cachedMode = mode;
    return mode;
  }

  static async save(context: Context, mode: string): Promise<void> {
    const normalizedMode = AppThemeModeStore.normalizeMode(mode);
    AppThemeModeStore.cachedMode = normalizedMode;
    AppThemeModeStore.applyToStorage(normalizedMode);
    const store = await preferences.getPreferences(context, AppThemeModeStore.STORE_NAME);
    await store.put(AppThemeModeStore.KEY_THEME_MODE, normalizedMode);
    await store.flush();
  }

  static applyToStorage(mode: string): void {
    const normalizedMode = AppThemeModeStore.normalizeMode(mode);
    AppThemeModeStore.cachedMode = normalizedMode;
    AppStorage.setOrCreate(AppThemeModeStore.KEY_THEME_MODE, normalizedMode);
  }

  static normalizeMode(mode: string): string {
    if (mode === 'light' || mode === 'dark' || mode === 'system') {
      return mode;
    }
    return 'system';
  }
}
