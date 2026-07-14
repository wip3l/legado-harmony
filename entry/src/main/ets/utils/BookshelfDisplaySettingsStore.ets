import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class BookshelfDisplaySettings {
  showTags: boolean = true;
  showSource: boolean = true;
  showIntro: boolean = true;
  showFullIntro: boolean = false;
  showProgressBar: boolean = false;
  showLastReadTime: boolean = true;
  showLastReadChapter: boolean = false;
  layoutMode: string = 'compact';
}

export class BookshelfDisplaySettingsStore {
  private static readonly STORE_NAME: string = 'bookshelf_display_settings';
  private static readonly KEY_SHOW_TAGS: string = 'bookshelfShowTags';
  private static readonly KEY_SHOW_SOURCE: string = 'bookshelfShowSource';
  private static readonly KEY_SHOW_INTRO: string = 'bookshelfShowIntro';
  private static readonly KEY_SHOW_FULL_INTRO: string = 'bookshelfShowFullIntro';
  private static readonly KEY_SHOW_PROGRESS_BAR: string = 'bookshelfShowProgressBar';
  private static readonly KEY_SHOW_LAST_READ_TIME: string = 'bookshelfShowLastReadTime';
  private static readonly KEY_SHOW_LAST_READ_CHAPTER: string = 'bookshelfShowLastReadChapter';
  private static readonly KEY_LAYOUT_MODE: string = 'bookshelfLayoutMode';
  private static cachedSettings: BookshelfDisplaySettings | null = null;

  static async load(context: Context): Promise<BookshelfDisplaySettings> {
    if (BookshelfDisplaySettingsStore.cachedSettings) {
      return BookshelfDisplaySettingsStore.clone(BookshelfDisplaySettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, BookshelfDisplaySettingsStore.STORE_NAME);
    const settings = new BookshelfDisplaySettings();
    settings.showTags = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_TAGS, true);
    settings.showSource = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_SOURCE, true);
    settings.showIntro = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_INTRO, true);
    settings.showFullIntro = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO, false);
    settings.showProgressBar = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR, false);
    settings.showLastReadTime = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_TIME, true);
    settings.showLastReadChapter = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_CHAPTER, false);
    settings.layoutMode = BookshelfDisplaySettingsStore.normalizeLayoutMode(await BookshelfDisplaySettingsStore.getString(
      store, BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE, 'compact'));
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: BookshelfDisplaySettings): Promise<void> {
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, BookshelfDisplaySettingsStore.STORE_NAME);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_TAGS, settings.showTags);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_SOURCE, settings.showSource);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_INTRO, settings.showIntro);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO, settings.showFullIntro);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR, settings.showProgressBar);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_TIME, settings.showLastReadTime);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_CHAPTER, settings.showLastReadChapter);
    await store.put(BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE,
      BookshelfDisplaySettingsStore.normalizeLayoutMode(settings.layoutMode));
    await store.flush();
  }

  static applyToStorage(settings: BookshelfDisplaySettings): void {
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_TAGS, settings.showTags);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_SOURCE, settings.showSource);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_INTRO, settings.showIntro);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO, settings.showFullIntro);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR, settings.showProgressBar);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_TIME, settings.showLastReadTime);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_CHAPTER, settings.showLastReadChapter);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE,
      BookshelfDisplaySettingsStore.normalizeLayoutMode(settings.layoutMode));
  }

  static fromStorage(): BookshelfDisplaySettings {
    const settings = new BookshelfDisplaySettings();
    settings.showTags = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_TAGS) ?? true;
    settings.showSource = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_SOURCE) ?? true;
    settings.showIntro = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_INTRO) ?? true;
    settings.showFullIntro = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO) ?? false;
    settings.showProgressBar = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR) ?? false;
    settings.showLastReadTime = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_TIME) ?? true;
    settings.showLastReadChapter = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_CHAPTER) ?? false;
    settings.layoutMode = BookshelfDisplaySettingsStore.normalizeLayoutMode(
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE) ?? 'compact');
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

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static normalizeLayoutMode(value: string): string {
    if (value === 'loose' || value === 'tile') {
      return value;
    }
    return 'compact';
  }

  private static clone(source: BookshelfDisplaySettings): BookshelfDisplaySettings {
    const settings = new BookshelfDisplaySettings();
    settings.showTags = source.showTags;
    settings.showSource = source.showSource;
    settings.showIntro = source.showIntro;
    settings.showFullIntro = source.showFullIntro;
    settings.showProgressBar = source.showProgressBar;
    settings.showLastReadTime = source.showLastReadTime;
    settings.showLastReadChapter = source.showLastReadChapter;
    settings.layoutMode = BookshelfDisplaySettingsStore.normalizeLayoutMode(source.layoutMode);
    return settings;
  }
}
