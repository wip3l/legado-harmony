import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class ReaderSettings {
  pageTurnMode: number = 1;
  preloadEnabled: boolean = true;
  preloadChapterCount: number = 1;
}

export class ReaderSettingsStore {
  static readonly KEY_PAGE_TURN_MODE: string = 'readerPageTurnMode';
  static readonly KEY_PRELOAD_ENABLED: string = 'readerPreloadEnabled';
  static readonly KEY_PRELOAD_CHAPTER_COUNT: string = 'readerPreloadChapterCount';
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

  static async savePreloadEnabled(context: Context, enabled: boolean): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || new ReaderSettings();
    settings.preloadEnabled = enabled;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PRELOAD_ENABLED, settings.preloadEnabled);
    await store.flush();
  }

  static async savePreloadChapterCount(context: Context, count: number): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || new ReaderSettings();
    settings.preloadChapterCount = ReaderSettingsStore.normalizePreloadChapterCount(count);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT, settings.preloadChapterCount);
    await store.flush();
  }

  static applyToStorage(settings: ReaderSettings): void {
    const normalized = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.cachedSettings = normalized;
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_MODE, normalized.pageTurnMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PRELOAD_ENABLED, normalized.preloadEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT, normalized.preloadChapterCount);
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
    return settings;
  }
}
