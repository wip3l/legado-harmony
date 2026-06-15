import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class SearchExploreSettings {
  showResultCover: boolean = true;
  showResultTags: boolean = true;
  promptAddToShelfOnBack: boolean = true;
  exactSearch: boolean = false;
  exactSearchMatchAuthor: boolean = true;
  showSearchProgress: boolean = true;
  selectedSourceGroupsRaw: string = '';
  sourceSortRaw: string = '';
}

export class SearchExploreSettingsStore {
  static readonly KEY_SHOW_RESULT_COVER: string = 'searchExploreShowResultCover';
  static readonly KEY_SHOW_RESULT_TAGS: string = 'searchExploreShowResultTags';
  static readonly KEY_PROMPT_ADD_TO_SHELF_ON_BACK: string = 'searchExplorePromptAddToShelfOnBack';
  static readonly KEY_EXACT_SEARCH: string = 'searchExploreExactSearch';
  static readonly KEY_EXACT_SEARCH_MATCH_AUTHOR: string = 'searchExploreExactSearchMatchAuthor';
  static readonly KEY_SHOW_SEARCH_PROGRESS: string = 'searchExploreShowSearchProgress';
  static readonly KEY_SELECTED_SOURCE_GROUPS: string = 'searchExploreSelectedSourceGroups';
  static readonly KEY_SOURCE_SORT: string = 'searchExploreSourceSort';
  private static readonly STORE_NAME: string = 'search_explore_settings';
  private static cachedSettings: SearchExploreSettings | null = null;

  static async load(context: Context): Promise<SearchExploreSettings> {
    if (SearchExploreSettingsStore.cachedSettings) {
      return SearchExploreSettingsStore.clone(SearchExploreSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    const settings = new SearchExploreSettings();
    settings.showResultCover = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER, true);
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
    settings.selectedSourceGroupsRaw = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_SELECTED_SOURCE_GROUPS, '');
    settings.sourceSortRaw = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_SOURCE_SORT, '');
    SearchExploreSettingsStore.cachedSettings = SearchExploreSettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: SearchExploreSettings): Promise<void> {
    SearchExploreSettingsStore.cachedSettings = SearchExploreSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER, settings.showResultCover);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_RESULT_TAGS, settings.showResultTags);
    await store.put(SearchExploreSettingsStore.KEY_PROMPT_ADD_TO_SHELF_ON_BACK, settings.promptAddToShelfOnBack);
    await store.put(SearchExploreSettingsStore.KEY_EXACT_SEARCH, settings.exactSearch);
    await store.put(SearchExploreSettingsStore.KEY_EXACT_SEARCH_MATCH_AUTHOR, settings.exactSearchMatchAuthor);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_SEARCH_PROGRESS, settings.showSearchProgress);
    await store.put(SearchExploreSettingsStore.KEY_SELECTED_SOURCE_GROUPS, settings.selectedSourceGroupsRaw);
    await store.put(SearchExploreSettingsStore.KEY_SOURCE_SORT, settings.sourceSortRaw);
    await store.flush();
  }

  static applyToStorage(settings: SearchExploreSettings): void {
    SearchExploreSettingsStore.cachedSettings = SearchExploreSettingsStore.clone(settings);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER, settings.showResultCover);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SHOW_RESULT_TAGS, settings.showResultTags);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_PROMPT_ADD_TO_SHELF_ON_BACK,
      settings.promptAddToShelfOnBack);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXACT_SEARCH, settings.exactSearch);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_EXACT_SEARCH_MATCH_AUTHOR,
      settings.exactSearchMatchAuthor);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SHOW_SEARCH_PROGRESS, settings.showSearchProgress);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SELECTED_SOURCE_GROUPS, settings.selectedSourceGroupsRaw);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SOURCE_SORT, settings.sourceSortRaw);
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
    settings.showResultTags = source.showResultTags;
    settings.promptAddToShelfOnBack = source.promptAddToShelfOnBack;
    settings.exactSearch = source.exactSearch;
    settings.exactSearchMatchAuthor = source.exactSearchMatchAuthor;
    settings.showSearchProgress = source.showSearchProgress;
    settings.selectedSourceGroupsRaw = source.selectedSourceGroupsRaw;
    settings.sourceSortRaw = source.sourceSortRaw;
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
}
