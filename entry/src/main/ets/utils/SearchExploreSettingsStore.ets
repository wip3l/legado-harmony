import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class SearchExploreSettings {
  showResultCover: boolean = true;
  useBookshelfCoverGallery: boolean = false;
  showResultTags: boolean = true;
  promptAddToShelfOnBack: boolean = true;
  exactSearch: boolean = false;
  exactSearchMatchAuthor: boolean = true;
  showSearchProgress: boolean = true;
  searchConcurrency: number = 6;
  selectedSourceGroupsRaw: string = '';
  sourceSortRaw: string = '';
  exploreSourceUrl: string = '';
  explorePlatform: string = '番茄';
}

export class SearchExploreSettingsStore {
  static readonly KEY_SHOW_RESULT_COVER: string = 'searchExploreShowResultCover';
  static readonly KEY_USE_BOOKSHELF_COVER_GALLERY: string = 'searchExploreUseBookshelfCoverGallery';
  static readonly KEY_SHOW_RESULT_TAGS: string = 'searchExploreShowResultTags';
  static readonly KEY_PROMPT_ADD_TO_SHELF_ON_BACK: string = 'searchExplorePromptAddToShelfOnBack';
  static readonly KEY_EXACT_SEARCH: string = 'searchExploreExactSearch';
  static readonly KEY_EXACT_SEARCH_MATCH_AUTHOR: string = 'searchExploreExactSearchMatchAuthor';
  static readonly KEY_SHOW_SEARCH_PROGRESS: string = 'searchExploreShowSearchProgress';
  static readonly KEY_SEARCH_CONCURRENCY: string = 'searchExploreSearchConcurrency';
  static readonly KEY_SELECTED_SOURCE_GROUPS: string = 'searchExploreSelectedSourceGroups';
  static readonly KEY_SOURCE_SORT: string = 'searchExploreSourceSort';
  static readonly KEY_EXPLORE_SOURCE_URL: string = 'exploreSourceUrl';
  static readonly KEY_EXPLORE_PLATFORM: string = 'explorePlatform';
  private static readonly STORE_NAME: string = 'search_explore_settings';
  private static readonly DEFAULT_SEARCH_CONCURRENCY: number = 6;
  private static readonly MIN_SEARCH_CONCURRENCY: number = 1;
  private static readonly MAX_SEARCH_CONCURRENCY: number = 12;
  private static cachedSettings: SearchExploreSettings | null = null;

  static async load(context: Context): Promise<SearchExploreSettings> {
    if (SearchExploreSettingsStore.cachedSettings) {
      return SearchExploreSettingsStore.clone(SearchExploreSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    const settings = new SearchExploreSettings();
    settings.showResultCover = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER, true);
    settings.useBookshelfCoverGallery = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_USE_BOOKSHELF_COVER_GALLERY, false);
    settings.showResultTags = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_SHOW_RESULT_TAGS, true);
    settings.promptAddToShelfOnBack = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_PROMPT_ADD_TO_SHELF_ON_BACK, true);
    settings.exactSearch = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_EXACT_SEARCH, false);
    settings.exactSearchMatchAuthor = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_EXACT_SEARCH_MATCH_AUTHOR, true);
    settings.showSearchProgress = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_SHOW_SEARCH_PROGRESS, true);
    const storageConcurrency = AppStorage.get<number>(SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY);
    settings.searchConcurrency = await SearchExploreSettingsStore.getNumber(
      store,
      SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY,
      typeof storageConcurrency === 'number' ?
        SearchExploreSettingsStore.normalizeSearchConcurrency(storageConcurrency) :
        SearchExploreSettingsStore.DEFAULT_SEARCH_CONCURRENCY);
    settings.selectedSourceGroupsRaw = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_SELECTED_SOURCE_GROUPS, '');
    settings.sourceSortRaw = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_SOURCE_SORT, '');
    settings.exploreSourceUrl = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, '');
    settings.explorePlatform = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, '番茄');
    SearchExploreSettingsStore.cachedSettings = SearchExploreSettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: SearchExploreSettings): Promise<void> {
    SearchExploreSettingsStore.cachedSettings = SearchExploreSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER, settings.showResultCover);
    await store.put(SearchExploreSettingsStore.KEY_USE_BOOKSHELF_COVER_GALLERY, settings.useBookshelfCoverGallery);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_RESULT_TAGS, settings.showResultTags);
    await store.put(SearchExploreSettingsStore.KEY_PROMPT_ADD_TO_SHELF_ON_BACK, settings.promptAddToShelfOnBack);
    await store.put(SearchExploreSettingsStore.KEY_EXACT_SEARCH, settings.exactSearch);
    await store.put(SearchExploreSettingsStore.KEY_EXACT_SEARCH_MATCH_AUTHOR, settings.exactSearchMatchAuthor);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_SEARCH_PROGRESS, settings.showSearchProgress);
    await store.put(SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY,
      SearchExploreSettingsStore.normalizeSearchConcurrency(settings.searchConcurrency));
    await store.put(SearchExploreSettingsStore.KEY_SELECTED_SOURCE_GROUPS, settings.selectedSourceGroupsRaw);
    await store.put(SearchExploreSettingsStore.KEY_SOURCE_SORT, settings.sourceSortRaw);
    await store.put(SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, settings.exploreSourceUrl);
    await store.put(SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, settings.explorePlatform);
    await store.flush();
  }

  static async saveExploreSelection(
    context: Context,
    exploreSourceUrl: string,
    explorePlatform: string
  ): Promise<void> {
    if (SearchExploreSettingsStore.cachedSettings) {
      SearchExploreSettingsStore.cachedSettings.exploreSourceUrl = exploreSourceUrl;
      SearchExploreSettingsStore.cachedSettings.explorePlatform = explorePlatform;
    }
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, exploreSourceUrl);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, explorePlatform);
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    await store.put(SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, exploreSourceUrl);
    await store.put(SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, explorePlatform);
    await store.flush();
  }

  static applyToStorage(settings: SearchExploreSettings): void {
    SearchExploreSettingsStore.cachedSettings = SearchExploreSettingsStore.clone(settings);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER, settings.showResultCover);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_USE_BOOKSHELF_COVER_GALLERY,
      settings.useBookshelfCoverGallery);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SHOW_RESULT_TAGS, settings.showResultTags);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_PROMPT_ADD_TO_SHELF_ON_BACK,
      settings.promptAddToShelfOnBack);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXACT_SEARCH, settings.exactSearch);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_EXACT_SEARCH_MATCH_AUTHOR,
      settings.exactSearchMatchAuthor);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SHOW_SEARCH_PROGRESS, settings.showSearchProgress);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY,
      SearchExploreSettingsStore.normalizeSearchConcurrency(settings.searchConcurrency));
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SELECTED_SOURCE_GROUPS, settings.selectedSourceGroupsRaw);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SOURCE_SORT, settings.sourceSortRaw);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, settings.exploreSourceUrl);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, settings.explorePlatform);
  }

  static getSearchConcurrency(): number {
    const cached = SearchExploreSettingsStore.cachedSettings?.searchConcurrency;
    if (typeof cached === 'number' && cached > 0) {
      return cached;
    }
    const value = AppStorage.get<number>(SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY);
    return typeof value === 'number' && value > 0 ?
      SearchExploreSettingsStore.normalizeSearchConcurrency(value) :
      SearchExploreSettingsStore.DEFAULT_SEARCH_CONCURRENCY;
  }

  static normalizeSearchConcurrency(value: number): number {
    const parsed = Math.round(value);
    if (Number.isNaN(parsed)) {
      return SearchExploreSettingsStore.DEFAULT_SEARCH_CONCURRENCY;
    }
    return Math.max(
      SearchExploreSettingsStore.MIN_SEARCH_CONCURRENCY,
      Math.min(parsed, SearchExploreSettingsStore.MAX_SEARCH_CONCURRENCY)
    );
  }

  private static async getBoolean(
    store: preferences.Preferences,
    key: string,
    fallback: boolean
  ): Promise<boolean> {
    const value = await store.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  private static clone(source: SearchExploreSettings): SearchExploreSettings {
    const settings = new SearchExploreSettings();
    settings.showResultCover = source.showResultCover;
    settings.useBookshelfCoverGallery = source.useBookshelfCoverGallery;
    settings.showResultTags = source.showResultTags;
    settings.promptAddToShelfOnBack = source.promptAddToShelfOnBack;
    settings.exactSearch = source.exactSearch;
    settings.exactSearchMatchAuthor = source.exactSearchMatchAuthor;
    settings.showSearchProgress = source.showSearchProgress;
    settings.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(source.searchConcurrency);
    settings.selectedSourceGroupsRaw = source.selectedSourceGroupsRaw;
    settings.sourceSortRaw = source.sourceSortRaw;
    settings.exploreSourceUrl = source.exploreSourceUrl;
    settings.explorePlatform = source.explorePlatform || '番茄';
    return settings;
  }

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static async getNumber(
    store: preferences.Preferences,
    key: string,
    fallback: number
  ): Promise<number> {
    const value = await store.get(key, fallback);
    if (typeof value === 'number' && !isNaN(value) && value > 0) {
      return SearchExploreSettingsStore.normalizeSearchConcurrency(value);
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      if (!Number.isNaN(parsed) && parsed > 0) {
        return SearchExploreSettingsStore.normalizeSearchConcurrency(parsed);
      }
    }
    return fallback;
  }
}
