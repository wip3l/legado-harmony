// node scripts/category-swipe-pager-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = path => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${path}`, 'utf8');
const context = vm.createContext({
  console, getContext: () => ({}), ScrollAlign: { CENTER: 0 },
  ExploreCategoryHistoryStore: { record() {}, entryKey: (title, url) => `${title}:${url}` },
  SearchBook: class {}, SearchCategoryChip: class {}, SEARCH_CATEGORY_ALL: 'all',
  BookTypeSupport: {
    MEDIA_CATEGORIES: ['novel', 'comic', 'audio', 'video'],
    mediaCategoryOf: book => book.category || 'novel'
  },
  ListScroller: class { scrollToIndex() {} }
});
Object.assign(context, {
  SearchPage: { HEADER_CONTROL_SIZE: 40, TITLE_ROW_HEIGHT: 56, STATUS_ROW_HEIGHT: 32, CATEGORY_BAR_HEIGHT: 44 },
  ExplorePage: { CHANNEL_BAR_HEIGHT: 44 }, AppSpacing: { MD: 8 },
  ScrollState: { Idle: 0, Scroll: 1, Fling: 2 }, Curve: { FastOutSlowIn: 0 },
  animateTo: (_options, update) => update()
});
vm.runInContext(stripTypeScriptTypes(read('utils/CollapsingHeader.ets').replace('export class', 'class')), context);
function methods(file, names) {
  const source = read(`components/home/${file}.ets`);
  const bodies = names.map(name => {
    const start = source.indexOf(`  ${name}(`);
    assert.ok(start >= 0, name);
    return source.slice(start, source.indexOf('\n  }', start) + 4);
  });
  return vm.runInContext(stripTypeScriptTypes(`({${bodies.join(',')}})`), context);
}

const dataSourceCode = read('components/home/CategorySwipePager.ets').split('@Component')[0];
const pages = vm.runInContext(stripTypeScriptTypes(`${dataSourceCode}\nnew CategoryPageDataSource()`), context);
let reloads = 0;
pages.registerDataChangeListener({ onDataReloaded: () => reloads++ });
pages.replace(['all', 'novel', 'audio']);
pages.replace(['all', 'novel', 'audio']);
assert.equal(reloads, 1, 'new results with the same category order must not reload the pager during a drag');
pages.replace(['all', 'novel', 'comic', 'audio']);
assert.equal(reloads, 2);
assert.equal(pages.getData(3), 'audio');

const storeSource = read('utils/SearchResultAggregationStore.ets')
  .replace(/^import .*;\r?\n/gm, '').replace(/export class /g, 'class ');
vm.runInContext(stripTypeScriptTypes(storeSource), context);
const search = methods('SearchPage', [
  'applySearchResultsSnapshot', 'searchCategoryCount', 'effectiveSearchCategory',
  'searchCategoryChips', 'searchBooksForCategory', 'searchCategoryScroller'
]);
Object.assign(search, {
  searchCategoryScrollers: new Map(), searchResultCategory: 'audio', isSearching: true,
  searchExploreAggregateResults: true
});
const results = [
  { name: '同一本书', category: 'novel', origin: 'a', bookUrl: 'a/1' },
  { name: '同一本书', category: 'novel', origin: 'b', bookUrl: 'b/1' },
  { name: '同一本书', category: 'audio', origin: 'a', bookUrl: 'a/2' }
];
search.applySearchResultsSnapshot(results);
assert.equal(search.searchBooksForCategory('novel')[0].aggregationCount, 2);
assert.equal(search.searchBooksForCategory('audio')[0].aggregationCount, 1);
assert.equal(search.searchBooksForCategory('all').length, 2);
assert.notEqual(search.searchCategoryScroller('novel'), search.searchCategoryScroller('audio'));
assert.equal(search.searchCategoryScroller('novel'), search.searchCategoryScroller('novel'));
search.applySearchResultsSnapshot([...results, { name: '漫画', category: 'comic', origin: 'c', bookUrl: 'c/1' }]);
assert.equal(search.effectiveSearchCategory(), 'audio', 'new category insertion keeps the selected category identity');
assert.deepEqual(Array.from(search.searchCategoryChips(), chip => chip.key), ['all', 'novel', 'comic', 'audio']);
assert.equal(search.searchBooksForCategory('comic').length, 1, 'neighbor pages read newly arrived results');
assert.equal(search.searchBooksForCategory(''), search.displayedSearchResults, 'list mode reads the current filter dynamically');

const explore = methods('ExplorePage', [
  'explorePageKeys', 'isCurrentExplorePage', 'explorePageLoading', 'explorePageBooks', 'selectExploreEntry'
]);
Object.assign(explore, {
  selectedPlatform: '频道', selectedSourceUrl: 'source-a', selectedIndex: 0, isLoading: false,
  books: [{ name: '第一类的书' }], exploreSwipePreviews: new Map(),
  getActiveEntries() {
    return Array.from({ length: 6 }, (_, index) => ({ sourceUrl: this.selectedSourceUrl, title: `分类${index}`, url: `${index}` }));
  },
  loadBooks() { this.isLoading = true; this.books = []; },
  exploreChannelScroller: { scrollToIndex() {} }
});
const keys = Array.from(explore.explorePageKeys());
explore.exploreBooksPageKey = keys[0];
explore.selectExploreEntry(1);
assert.equal(explore.explorePageBooks(keys[0])[0].name, '第一类的书', 'outgoing page keeps its content during the animation');
assert.equal(explore.explorePageLoading(keys[1]), true);
explore.isLoading = false;
assert.equal(explore.explorePageBooks(keys[1]).length, 0, 'failed incoming request must not display outgoing books');
explore.selectExploreEntry(0);
assert.equal(explore.explorePageLoading(keys[0]), false, 'cached page stays visible while its result is loading');
assert.equal(explore.explorePageBooks(keys[0])[0].name, '第一类的书');
for (let index = 0; index < 5; index++) {
  explore.selectedIndex = index;
  explore.isLoading = false;
  explore.exploreBooksPageKey = keys[index];
  explore.books = [{ name: `书${index}` }];
  explore.selectExploreEntry(index + 1);
}
assert.equal(explore.exploreSwipePreviews.size, 3, 'preview cache stays bounded');
explore.isLoading = false;
explore.selectedPlatform = '另一个频道';
const newKey = explore.explorePageKeys()[explore.selectedIndex];
explore.selectExploreEntry(0);
assert.equal(explore.exploreSwipePreviews.has(newKey), false, 'changing platform must not relabel old books as new-category previews');
explore.selectedSourceUrl = 'source-b';
assert.notEqual(explore.explorePageKeys()[0], keys[0], 'source identity is part of each page key');

// 分类各自从纵向位置 0 开始，但共享的顶栏收起量不能因此归零。
for (const [file, prefix] of [['ExplorePage', 'explore'], ['SearchPage', 'search']]) {
  const isSearch = prefix === 'search';
  const page = methods(file, [
    `uses${isSearch ? 'Search' : 'Explore'}CategoryPager`, `${prefix}ResultTopPadding`,
    `${prefix}HeaderCollapseValue`, `${prefix}TopOverlayHeight`,
    `on${isSearch ? 'Search' : 'Explore'}ListScroll`, `on${isSearch ? 'Search' : 'Explore'}ListScrollStop`,
    ...(isSearch ? ['searchCollapsibleHeight', 'searchFieldRowHeight', 'searchStatusRowTop'] : [])
  ]);
  Object.assign(page, {
    statusBarHeight: 24, showResult: true, isLoading: true, statusMessage: '搜索中',
    books: [], displayedSearchResults: [], showSearchCategoryBar: () => true,
    getActiveEntries: () => [{}], showsExploreChannelBar: () => true, shouldShowExploreStatus: () => false,
    searchResultLayout: 'grid', exploreResultLayout: 'grid'
  });
  const distance = isSearch ? page.searchCollapsibleHeight() : 56;
  const collapseKey = `${prefix}HeaderCollapse`;
  const value = () => page[`${prefix}HeaderCollapseValue`]();
  page[collapseKey] = distance;
  assert.equal(value(), distance, `${file}: loading/empty incoming page preserves the collapsed header`);
  assert.equal(page[`${prefix}ResultTopPadding`](), 0, `${file}: no expanded-header spacer inside each page`);
  assert.equal(page[`${prefix}TopOverlayHeight`]() - value(), 24 + 44 + 8,
    `${file}: content begins directly after the remaining status/category bar and its normal margin`);

  const name = isSearch ? 'Search' : 'Explore';
  const list = { userScrollOnly: true, gridUserScrolled: false,
    scroller: { currentOffset: () => ({ yOffset: 0 }) },
    onListScroll: (delta, offset) => page[`on${name}ListScroll`](delta, offset),
    onListScrollStop: offset => page[`on${name}ListScrollStop`](offset)
  };
  const listSource = read('components/book/SearchBookResultList.ets');
  for (const event of ['onDidScroll', 'onScrollStop']) {
    const callback = listSource.match(new RegExp(`\\.${event}\\((\\([^\\n]*\\) => \\{[\\s\\S]*?\\n\\s*\\})\\)`))[1];
    context.list = list;
    vm.runInContext(stripTypeScriptTypes(`list.${event} = function () { return ${callback}; }.call(list);`), context);
  }
  list.onDidScroll(-200, 0);
  list.onScrollStop();
  assert.equal(value(), distance, `${file}: mounting/resetting the new list cannot expand the header`);
  list.onDidScroll(-12, 1);
  assert.equal(value(), distance - 12, `${file}: real downward dragging still reveals the header`);
  page[`on${name}ListScroll`](12, 0);
  assert.equal(value(), distance - 12, `${file}: top spring rebound does not hide it again`);
  page[`on${name}ListScroll`](-distance, -40);
  assert.equal(value(), 0, `${file}: downward dragging can fully expand it`);
  page[`on${name}ListScroll`](distance, distance);
  assert.equal(value(), distance, `${file}: upward scrolling still collapses it`);
  page.isLoading = false;
  page.books = [{}]; page.displayedSearchResults = [{}];
  page.searchResultLayout = 'list'; page.exploreResultLayout = 'list';
  page[`on${name}ListScroll`](0, 0);
  assert.equal(value(), 0, `${file}: ordinary list mode keeps its existing offset-based behavior`);
}

console.log('PASS category pager: page identity, aggregation, previews, bounded cache, shared header state, gap-free content inset and user-only vertical scroll');
