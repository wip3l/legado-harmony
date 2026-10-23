// Run with: node --experimental-strip-types scripts/reader-toc-search-check.mjs
// Keep keyed row callbacks alive across filtering, as ArkUI ForEach does.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const file = new URL('../entry/src/main/ets/components/reader/ReaderTocPanel.ets', import.meta.url);
const source = fs.readFileSync(file, 'utf8');
const rowSource = source.slice(source.indexOf('ForEach(this.visibleChapters'), source.indexOf('  @Builder\n  virtualScrollbar'));
function method(name) {
  const start = new RegExp(`^  private (?:async )?${name}\\(`, 'm').exec(source)?.index;
  assert.notEqual(start, undefined, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
}
const title = rowSource.match(/Text\((this\.chapterTitle\([^\n]+)\)/)[1];
const jump = rowSource.match(/\.onClick\(\(\) => (this\.onJumpToChapter\([^\n]+)\)/)[1];
const selected = rowSource.match(/\.backgroundColor\(([^\n]+) \?/)[1];
const key = rowSource.match(/\n\s*(`[^\n]+`)\)/)[1];

function harness(reverseOrder = false) {
  const timers = [];
  const context = vm.createContext({
    console: { info() {}, warn() {} },
    setTimeout: fn => { timers.push(fn); return timers.length; },
    ScrollAlign: { START: 0, CENTER: 1, END: 2 }, TOC_WINDOW_PAGE_SIZE: 72
  });
  const methods = ['isSearchActive', 'globalIndex', 'chapterAtDisplayIndex', 'setWindowAround',
    'submitSearch', 'clearSearchResult', 'toggleOrder', 'scrollToCurrentChapter', 'scrollToChapter',
    'loadNextPage', 'loadPreviousPage'];
  const panel = vm.runInContext(stripTypeScriptTypes(`({${methods.map(method).join(',')}})`), context);
  const chapters = Array.from({ length: 75 }, (_, index) => ({
    index, title: `第${index + 1}章`, url: `chapter-${index}`, cacheDate: 1
  }));
  Object.assign(panel, {
    chapters, reverseOrder, currentChapterIndex: 0, book: { bookUrl: 'test-book' },
    searchVisible: true, searchResultActive: false, searchChapterIndexes: [], searchQuery: '',
    searchRequestSerial: 0, positionRequestSerial: 0, orderRevision: 0,
    tocScroller: { scrollToIndex() {} },
    chapterTitle: index => chapters[index].title, onJumpToChapter: index => index
  });
  const cache = new Map();
  const makeRow = vm.runInContext(`(function(chapter, localIndex) {
    return { key: ${key}, title: () => ${title}, jump: () => ${jump}, selected: () => ${selected} };
  })`, context);
  return { panel, flush() {
    while (timers.length) timers.shift()();
  }, render() {
    return panel.visibleChapters.map((chapter, localIndex) => {
      const candidate = makeRow.call(panel, chapter, localIndex);
      if (!cache.has(candidate.key)) cache.set(candidate.key, candidate);
      return cache.get(candidate.key);
    });
  } };
}

for (const reversed of [false, true]) {
  const h = harness(reversed);
  const p = h.panel;
  p.setWindowAround(35, 1);
  h.render(); // Existing chapter rows capture their positions in the unfiltered list.
  p.searchQuery = '36';
  await p.submitSearch();
  h.flush();
  let rows = h.render();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].title(), '第36章', 'search 36 must display chapter 36, not chapter 1');
  assert.equal(rows[0].jump(), 35, 'search result opens the matching chapter');
  assert.equal(rows[0].selected(), false, 'chapter 36 is not highlighted while reading chapter 1');
  p.currentChapterIndex = 35;
  assert.equal(rows[0].selected(), true, 'selected state follows the actual chapter');

  p.searchQuery = '3';
  await p.submitSearch();
  h.flush();
  rows = h.render();
  const expected = p.chapters.filter(chapter => chapter.title.includes('3'));
  if (reversed) expected.reverse();
  assert.deepEqual(rows.map(row => row.jump()), expected.map(chapter => chapter.index));
  assert.deepEqual(rows.map(row => row.title()), expected.map(chapter => chapter.title));

  p.searchQuery = 'missing';
  await p.submitSearch();
  assert.equal(h.render().length, 0, 'no matches leaves an empty result');
  p.clearSearchResult();
  h.flush();
  rows = h.render();
  assert.deepEqual(rows.map(row => row.jump()), p.visibleChapters.map(chapter => chapter.index));
  assert.deepEqual(rows.map(row => row.title()), p.visibleChapters.map(chapter => chapter.title));

  p.toggleOrder();
  h.flush();
  rows = h.render();
  assert.deepEqual(rows.map(row => row.jump()), p.visibleChapters.map(chapter => chapter.index));
  p.setWindowAround(74, 0);
  h.render();
  p.loadPreviousPage();
  h.flush();
  p.loadNextPage();
  h.flush();
  rows = h.render();
  assert.deepEqual(rows.map(row => row.title()), p.visibleChapters.map(chapter => chapter.title),
    'extending a catalog window preserves retained row titles');
  assert.deepEqual(rows.map(row => row.jump()), p.visibleChapters.map(chapter => chapter.index));
}
console.log('Reader TOC checks passed: retained rows, search, selection, clearing, reverse order and paging.');
