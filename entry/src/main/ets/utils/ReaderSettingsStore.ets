import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class ReaderSettings {
  pageTurnMode: number = 1;
}

export class ReaderSettingsStore {
  static readonly KEY_PAGE_TURN_MODE: string = 'readerPageTurnMode';
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
      1
    );
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    return settings;
  }

  static async savePageTurnMode(context: Context, mode: number): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || new ReaderSettings();
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(mode);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PAGE_TURN_MODE, settings.pageTurnMode);
    await store.flush();
  }

  static applyToStorage(settings: ReaderSettings): void {
    const normalized = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.cachedSettings = normalized;
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_MODE, normalized.pageTurnMode);
  }

  private static async getNumber(
    store: preferences.Preferences,
    key: string,
    fallback: number
  ): Promise<number> {
    const value = await store.get(key, fallback);
    if (typeof value === 'number') {
      return ReaderSettingsStore.normalizePageTurnMode(value);
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      if (!Number.isNaN(parsed)) {
        return ReaderSettingsStore.normalizePageTurnMode(parsed);
      }
    }
    return fallback;
  }

  private static normalizePageTurnMode(mode: number): number {
    const value = Math.round(mode);
    return value >= 0 && value <= 2 ? value : 1;
  }

  private static clone(source: ReaderSettings): ReaderSettings {
    const settings = new ReaderSettings();
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(source.pageTurnMode);
    return settings;
  }
}
