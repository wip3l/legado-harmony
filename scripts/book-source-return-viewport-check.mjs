// Exercise the real page lifecycle, reload and filter methods with a simulated List.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const source = fs.readFileSync(`${projectRoot}/entry/src/main/ets/pages/BookSource.ets`, 'utf8');
function method(name) {
  const match = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source);
  assert(match, name);
  const end = source.indexOf('\n  }', match.index);
  return source.slice(match.index, end + '\n  }'.length).replace('private ', '');
}
const rows = Array.from({ length: 100 }, (_, index) => ({
  bookSourceUrl: `source-${index}`, bookSourceName: `Source ${index}`,
  bookSourceGroup: '', customOrder: index, enabled: true, isPinned: false
}));

function harness({ initial = rows, updated = initial, lanes = 1, fail = false } = {}) {
  const timers = [], loading = [], scrolls = [], routes = [];
  let offset = 5432.5;
  const db = {
    async initWithContext() {},
    async getBookSourceSummaries() {
      if (fail) throw new Error('read failure');
      return updated.map(row => ({ ...row }));
    },
    async getBottomBookSourceUrls() { return []; }
  };
  const context = vm.createContext({
    console: { error() {} }, getContext() { return {}; },
    AppDatabase: { getInstance: () => db },
    BookSourceGroupStore: { async load() { return []; } },
    ScrollAlign: { START: 'start' },
    setTimeout: callback => timers.push(callback),
    router: { pushUrl: route => routes.push(route) }
  });
  vm.runInContext(stripTypeScriptTypes(`globalThis.page = {
    ${['onPageShow', 'onPageHide', 'refreshSources', 'loadSources', 'applySourceFilters',
      'sortFilteredSources', 'openActionSourceEdit'].map(method).join(',\n')}
  };`, { mode: 'strip' }), context);
  const p = context.page;
  Object.assign(p, {
    allSources: initial, sources: initial, visibleSources: initial,
    sourceFirstVisibleIndex: initial.length ? 60 : 0, sourceVisibleItemCount: 7,
    sourceHeaderCollapse: 56, pageVisible: true, hasShownOnce: true,
    searchText: '', activeSourceGroup: '__all__', sourceSortMode: 'custom',
    sourceFormatFilter: 'all', sourceEnabledFilter: 'all', sourceExplorePageFilter: 'all',
    sourceExploreEnabledFilter: 'all', sourceLoginFilter: 'all', sourceValidationFilter: 'all',
    sourceGroups: [], sourceGroupsFromSources: () => [], ensureActiveSourceGroup() {},
    pruneSelectedSources() {}, isSourceAtBottom: () => false,
    syncBars() {}, resumeLoginRuntimeBrowserAwait() {}, handlePendingBookSourceImport() {},
    stopSourceSelectionAutoScroll() {}, releaseBookSourceCheckCancelSubscriber() {},
    actionSource: () => p.sources[63], closeSourceActions() {},
    sourceListLaneCount: () => lanes,
    // Model a List reload losing its offset; restoration must happen after this reload.
    sourceListDataSource: { replace() { offset = 0; } },
    sourceListScroller: {
      currentOffset: () => ({ yOffset: offset }),
      scrollTo: options => { offset = options.yOffset; scrolls.push(['offset', offset]); },
      scrollToIndex: (index, animated, align) => scrolls.push(['index', index, animated, align])
    }
  });
  Object.defineProperty(p, 'isLoading', {
    get: () => loading.at(-1) ?? false,
    set: value => loading.push(value)
  });
  const refresh = p.refreshSources.bind(p);
  let pending;
  p.refreshSources = () => (pending = refresh());
  return {
    p, loading, scrolls, routes,
    flush: () => { while (timers.length) timers.shift()(); },
    async returnToPage() { p.onPageShow(); await pending; this.flush(); }
  };
}

// Both editors, with and without saving; retain partial-row pixel offset and header state.
for (const format of ['native', 'legado']) {
  for (const save of [false, true]) {
    const initial = rows.map(row => ({ ...row, sourceFormat: format }));
    const updated = initial.map((row, index) => ({
      ...row, bookSourceName: save && index === 63 ? 'Edited source' : row.bookSourceName
    }));
    const h = harness({ initial, updated });
    h.p.openActionSourceEdit();
    assert.equal(h.routes[0].url, format === 'native' ? 'pages/NativeSourceEdit' : 'pages/BookSourceEdit');
    h.p.onPageHide();
    await h.returnToPage();
    assert.equal(h.p.sources[63].bookSourceName, updated[63].bookSourceName);
    assert.equal(h.loading.includes(true), false, 'return refresh must not unmount the List');
    assert.deepEqual(h.scrolls, [['offset', 5432.5]]);
    assert.equal(h.p.sourceFirstVisibleIndex, 60);
    assert.equal(h.p.sourceVisibleItemCount, 7);
    assert.equal(h.p.sourceHeaderCollapse, 56);
  }
}

// Reordering preserves the old visible source, with the correct spacer count on wide screens.
for (const lanes of [1, 2, 3]) {
  const updated = rows.map((row, index) => ({ ...row, customOrder: index === 0 ? 999 : index }));
  const h = harness({ updated, lanes });
  await h.returnToPage();
  assert.equal(h.p.sources[h.p.sourceFirstVisibleIndex].bookSourceUrl, 'source-60');
  assert.deepEqual(h.scrolls, [['index', 59 + lanes, false, 'start']]);
}

// If filtering removes the anchor, use the nearest remaining index and clamp short lists.
for (const count of [80, 20, 0]) {
  // Supply disabled rows via the reload itself, not by bypassing filtering.
  const updated = rows.map((row, index) => ({ ...row, enabled: index < count && index !== 60 }));
  const filtered = harness({ updated });
  filtered.p.sourceEnabledFilter = 'yes';
  await filtered.returnToPage();
  if (count === 0) assert.deepEqual(filtered.scrolls, []);
  else assert.equal(filtered.scrolls[0][1], Math.min(60, count - 1) + 1);
}

const failed = harness({ fail: true });
await failed.returnToPage();
assert.equal(failed.p.sources.length, 100);
assert.deepEqual(failed.scrolls, [['offset', 5432.5]]);

const empty = harness({ initial: [], updated: rows });
await empty.returnToPage();
assert.deepEqual(empty.loading, [true, false]);
assert.deepEqual(empty.scrolls, []);

const hidden = harness();
await hidden.p.refreshSources();
hidden.p.onPageHide();
hidden.flush();
assert.deepEqual(hidden.scrolls, [], 'do not scroll a page hidden again before layout');

console.log('Book source return viewport checks passed: both editors, save/cancel, offsets, reorder, filters, empty, failure, hidden page.');
