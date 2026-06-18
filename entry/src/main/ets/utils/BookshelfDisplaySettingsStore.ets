import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class BookshelfDisplaySettings {
  showTags: boolean = true;
  showIntro: boolean = true;
  showFullIntro: boolean = false;
  showProgressBar: boolean = false;
}

export class BookshelfDisplaySettingsStore {
  private static readonly STORE_NAME: string = 'bookshelf_display_settings';
  private static readonly KEY_SHOW_TAGS: string = 'bookshelfShowTags';
  private static readonly KEY_SHOW_INTRO: string = 'bookshelfShowIntro';
  private static readonly KEY_SHOW_FULL_INTRO: string = 'bookshelfShowFullIntro';
  private static readonly KEY_SHOW_PROGRESS_BAR: string = 'bookshelfShowProgressBar';
  private static cachedSettings: BookshelfDisplaySettings | null = null;

  static async load(context: Context): Promise<BookshelfDisplaySettings> {
    if (BookshelfDisplaySettingsStore.cachedSettings) {
      return BookshelfDisplaySettingsStore.clone(BookshelfDisplaySettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, BookshelfDisplaySettingsStore.STORE_NAME);
    const settings = new BookshelfDisplaySettings();
    settings.showTags = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_TAGS, true);
    settings.showIntro = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_INTRO, true);
    settings.showFullIntro = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO, false);
    settings.showProgressBar = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR, false);
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: BookshelfDisplaySettings): Promise<void> {
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, BookshelfDisplaySettingsStore.STORE_NAME);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_TAGS, settings.showTags);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_INTRO, settings.showIntro);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO, settings.showFullIntro);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR, settings.showProgressBar);
    await store.flush();
  }

  static applyToStorage(settings: BookshelfDisplaySettings): void {
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_TAGS, settings.showTags);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_INTRO, settings.showIntro);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO, settings.showFullIntro);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR, settings.showProgressBar);
  }

  static fromStorage(): BookshelfDisplaySettings {
    const settings = new BookshelfDisplaySettings();
    settings.showTags = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_TAGS) ?? true;
    settings.showIntro = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_INTRO) ?? true;
    settings.showFullIntro = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO) ?? false;
    settings.showProgressBar = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR) ?? false;
    return settings;
  }

  private static async getBoolean(
    store: preferences.Preferences,
    key: string,
    fallback: boolean
  ): Promise<boolean> {
    const value = await store.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  private static clone(source: BookshelfDisplaySettings): BookshelfDisplaySettings {
    const settings = new BookshelfDisplaySettings();
    settings.showTags = source.showTags;
    settings.showIntro = source.showIntro;
    settings.showFullIntro = source.showFullIntro;
    settings.showProgressBar = source.showProgressBar;
    return settings;
  }
}
