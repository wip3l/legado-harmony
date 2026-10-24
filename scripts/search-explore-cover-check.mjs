// node scripts/search-explore-cover-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const context = vm.createContext({ console, Book: class { customCoverUrl = ''; },
  ThemeRuntime: { bookTokens: dark => ({ coverAssetId: dark ? 'dark' : 'light', shelfFrameAssetId: 'frame' }) },
  ThemeAssetRegistry: { themeBookCovers: id => [{ id: `${id}-1` }, { id: `${id}-2` }], themeShelfFrame: () => ({ id: 'frame' }) }
});
for (const file of ['utils/CoverUrlNormalizer.ts', 'utils/BookDisplayHelper.ets', 'utils/CoverGallerySettings.ets', 'utils/ThemeBookCoverSettings.ets']) {
  const source = read(file).replace(/^import .*;\r?\n/gm, '').replace(/export class /g, 'class ');
  vm.runInContext(stripTypeScriptTypes(source), context);
}
const source = read('components/book/BookCover.ets');
function method(name) {
  const start = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source)?.index;
  assert.notEqual(start, undefined, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
}
const cover = vm.runInContext(stripTypeScriptTypes(`({${[
  'coverBook', 'rawCoverList', 'refreshCovers', 'resolveDisplayCovers', 'clearCoverRetries', 'activeCover', 'isActiveCoverReady', 'notifyReadyCover', 'markLoaded', 'loadShelfBook'
].map(method).join(',')}})`), context);
Object.assign(cover, {
  bookUrl: 'book-1', origin: 'source', coverUrl: 'source.jpg', shelfBook: null,
  useBookshelfCover: true, appDarkMode: false, applyScope: 'all', targetBooks: '', themeCoverEnabled: false,
  ignoreSource: false, coverMode: 'sequence', lightAlbum: 'light', darkAlbum: 'dark',
  albums: JSON.stringify([{ id: 'light', covers: ['light-1.jpg', 'light-2.jpg'] }, { id: 'dark', covers: ['dark.jpg'] }]),
  covers: [], displayCovers: [], coverLoadSerial: 0, retryTimers: new Map(), retryCounts: new Map(), activeIndex: 0, loadedRevision: 0, loadedUrls: new Set(), mounted: true,
  imageCover: raw => raw, onReadyCover() {}
});
const list = () => Array.from(cover.rawCoverList());
assert.deepEqual(list(), ['source.jpg', 'light-1.jpg', 'light-2.jpg'], 'source and album follow shelf ordering');
cover.shelfBook = { bookUrl: 'book-1', coverUrl: 'shelf-source.jpg', customCoverUrl: '["custom-1.jpg","custom-2.jpg"]' };
assert.deepEqual(list(), ['custom-1.jpg', 'custom-2.jpg', 'light-1.jpg', 'light-2.jpg'], 'use saved shelf custom covers');
cover.ignoreSource = true;
assert.deepEqual(list(), ['light-1.jpg', 'light-2.jpg']);
cover.appDarkMode = true;
assert.deepEqual(list(), ['dark.jpg']);
cover.applyScope = 'books'; cover.targetBooks = '["other-book"]';
assert.deepEqual(list(), [], 'respect scope and ignore-source together, no silent source fallback');
cover.ignoreSource = false;
assert.deepEqual(list(), ['custom-1.jpg', 'custom-2.jpg']);
cover.targetBooks = '["book-1"]';
assert.deepEqual(list(), ['custom-1.jpg', 'custom-2.jpg', 'dark.jpg']);
cover.coverMode = 'random';
const random = list();
assert.equal(random.length, 1);
assert.deepEqual(random, list(), 'random selection stable for same book/time');
cover.useBookshelfCover = false;
assert.deepEqual(list(), ['source.jpg'], 'switch off restores result source cover');
cover.useBookshelfCover = true; cover.coverMode = 'sequence'; cover.darkAlbum = '';
assert.deepEqual(list(), ['custom-1.jpg', 'custom-2.jpg'], 'missing album uses shelf source/custom rule');
cover.ignoreSource = true;
assert.deepEqual(list(), [], 'empty cover selection stays empty like shelf');
cover.ignoreSource = false; cover.darkAlbum = 'dark';
const ready = [];
cover.onReadyCover = url => ready.push(url);
cover.refreshCovers();
assert.equal(ready.at(-1), '');
cover.markLoaded('custom-1.jpg');
assert.equal(ready.at(-1), 'custom-1.jpg');
cover.activeIndex = 1; cover.notifyReadyCover();
assert.equal(ready.at(-1), '', 'unloaded next slide does not reuse previous backdrop');
cover.markLoaded('custom-2.jpg');
assert.equal(ready.at(-1), 'custom-2.jpg');
cover.useBookshelfCover = false; cover.refreshCovers();
assert.equal(cover.activeIndex, 0, 'switch resets carousel selection');
cover.themeCoverEnabled = true;
cover.refreshCovers();
assert.deepEqual(Array.from(cover.covers), ['source.jpg'], 'disabled setting does not apply theme covers');
cover.useBookshelfCover = true;
cover.refreshCovers();
assert.equal(cover.covers.length, 2);
assert(cover.covers.every(item => item.id.startsWith('dark-')), 'theme covers override source and gallery like shelf');
assert.equal(cover.themeFrame.id, 'frame');
assert(cover.interval >= 3200 && cover.interval <= 4880);
cover.markLoaded(cover.covers[0]);
assert.equal(ready.at(-1).id, cover.covers[0].id, 'theme Resource covers drive backdrop too');
cover.themeCoverEnabled = false;
cover.refreshCovers();
assert.equal(cover.themeFrame, '');
assert.equal(cover.interval, 3500);

// Late shelf lookups must not apply another book's custom cover to a reused result cell.
let resolveShelf;
Object.assign(context, {
  getContext: () => ({}),
  AppDatabase: { getInstance: () => ({ initWithContext: async () => {} }) },
  BookIdentity: { keyOfUrl: url => url, keyOfBook: book => book.bookUrl },
  SearchBookShelfHelper: { findShelfBookByKey: () => new Promise(resolve => { resolveShelf = resolve; }) }
});
cover.requestSerial = 1;
const lateLoad = cover.loadShelfBook(1);
for (let i = 0; i < 5; i++) await Promise.resolve();
cover.requestSerial = 2;
const currentShelfBook = cover.shelfBook;
resolveShelf({ bookUrl: 'old-book', customCoverUrl: 'old-cover.jpg' });
await lateLoad;
assert.equal(cover.shelfBook, currentShelfBook);

// Visible result covers share one database fetch; a late old snapshot cannot overwrite new shelf settings.
let version = 1;
const pendingReads = [];
context.AppStorage = { get: () => version };
context.AppDatabase = { getInstance: () => ({ getAllBooks: () => new Promise(resolve => pendingReads.push(resolve)) }) };
const helperSource = read('utils/SearchBookShelfHelper.ets').replace(/^import .*;\r?\n/gm, '').replace(/export class /g, 'class ');
vm.runInContext(stripTypeScriptTypes(helperSource), context);
const helper = vm.runInContext('SearchBookShelfHelper', context);
const first = helper.getShelfLookup();
const shared = helper.getShelfLookup();
assert.equal(pendingReads.length, 1, 'one query for concurrent cover loads');
version = 2;
const latest = helper.getShelfLookup();
assert.equal(pendingReads.length, 2);
pendingReads[1]([{ bookUrl: 'new-book' }]);
await latest;
pendingReads[0]([{ bookUrl: 'old-book' }]);
assert((await first).has('new-book'));
assert((await shared).has('new-book'));
assert(!(await helper.getShelfLookup()).has('old-book'));

// Static surfaces (media/cards/LAN) select from exactly the same gallery/theme rules.
let themeEnabled = false;
const settings = { albumsRaw: cover.albums, lightAlbumId: 'light', darkAlbumId: 'dark',
  applyScope: 'all', targetBooksRaw: '', ignoreSourceCover: false, coverMode: 'sequence' };
context.AppStorage = { get: key => key === 'appThemeBookCoverEnabled' ? themeEnabled : false };
context.CoverGalleryStore = { snapshotFromStorage: () => settings };
let writes = 0, closed = 0, exists = false, failWrite = false, storedBytes;
context.fs = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  open: async () => ({ fd: 5 }), access: async () => exists,
  write: async (_fd, buffer) => { writes++; if (failWrite) throw Error('disk'); storedBytes = new Uint8Array(buffer); exists = true; },
  close: async () => { closed++; }
};
context.BookCoverCache = { prepareCoverFile: async (_ctx, url) => 'cached:' + url };
vm.runInContext(stripTypeScriptTypes(read('utils/BookCoverResolver.ets')
  .replace(/^import .*;\r?\n/gm, '').replace(/export class /g, 'class ')), context);
const resolver = vm.runInContext('BookCoverResolver', context);
const nativeBook = { bookUrl: 'book-1', name: 'Book', author: 'Author', coverUrl: 'source.jpg', customCoverUrl: 'custom.jpg' };
assert.equal(resolver.first(nativeBook, false), 'custom.jpg');
settings.ignoreSourceCover = true;
assert.equal(resolver.first(nativeBook, true), 'dark.jpg');
settings.applyScope = 'books'; settings.targetBooksRaw = '["other"]';
assert.equal(resolver.first(nativeBook, false), '', 'static surfaces do not restore suppressed source covers');
themeEnabled = true;
assert(resolver.first(nativeBook, true).id.startsWith('dark-'));
assert.equal(resolver.first(null, true), '');
const fileContext = { cacheDir: '/cache', resourceManager: { getMediaContent: async () => new Uint8Array([9, 1, 2, 3, 9]).subarray(1, 4) } };
assert.equal(await resolver.prepareFile(fileContext, ''), '');
assert.equal(await resolver.prepareFile(fileContext, 'source.jpg'), 'cached:source.jpg');
const files = await Promise.all([resolver.prepareFile(fileContext, { id: 7 }), resolver.prepareFile(fileContext, { id: 7 })]);
assert.equal(files[0], files[1]);
assert.equal(writes, 1, 'concurrent media/card requests write the theme resource once');
assert.deepEqual(Array.from(storedBytes), [1, 2, 3], 'respect byte offset and length');
exists = false;
await resolver.prepareFile(fileContext, { id: 7 });
assert.equal(writes, 2, 'recreate file after cache clearing');
failWrite = true;
await assert.rejects(resolver.prepareFile(fileContext, { id: 8 }));
failWrite = false;
await resolver.prepareFile(fileContext, { id: 8 });
assert.equal(closed, 4, 'close files even on failure; failed writes can retry');

// The same resolver powers both result layouts and the detail page; saved preference key is preserved.
const results = read('components/book/SearchBookResultList.ets');
assert(results.includes('BookCover({'));
assert(results.includes('this.resultCover(book, 8, 360, 480)'));
assert(results.includes('this.resultCover(book, 6, 180, 240)'));
assert(read('pages/SearchBookDetail.ets').includes('BookCover({'));
assert(read('pages/SearchExploreSettings.ets').includes("title: '使用书架封面'"));
assert(read('pages/SearchExploreSettings.ets').includes("@StorageLink('searchExploreUseBookshelfCoverGallery')"));
for (const path of ['components/reader/ReaderTocPanel.ets', 'components/TtsCatalogSheet.ets',
  'components/ReaderTtsPlayerPanel.ets', 'pages/ReadingStats.ets', 'pages/AudioBook.ets', 'pages/OpdsBrowse.ets']) {
  assert(read(path).includes('BookCover({'), `${path} uses the shared cover component`);
}
console.log('PASS shared covers: source/custom/theme/albums, scope, modes, backdrop, stale loads, shared lookup, static surfaces, resource file caching/retry');
