// Run with: node scripts/trial-read-shelf-check.mjs
// Execute the real shelf/engine/database lifecycle and page save callbacks with an in-memory RDB adapter.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot, readEtsModule } from './lib/ets-module-staging.mjs';

const readPage = name => fs.readFileSync(`${projectRoot}/entry/src/main/ets/pages/${name}.ets`, 'utf8');
const compile = source => stripTypeScriptTypes(source
  .replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
function method(page, name) {
  const source = readPage(page);
  const match = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source);
  assert(match, `${page}.${name}`);
  const end = source.indexOf('\n  }', match.index);
  assert(end > match.index);
  return source.slice(match.index, end + '\n  }'.length).replace('private ', '');
}

function harness() {
  const rows = new Map();
  const writes = [];
  const storage = new Map();
  const context = vm.createContext({
    console: { log() {}, info() {}, warn: console.warn, error: console.error },
    relationalStore: { RdbPredicates: class {
      equalTo(key, value) { this[key] = value; return this; }
    } },
    BookIdentity: { keyOfBook: book => `${book.origin}|${book.bookUrl}` },
    CloudSyncChangeTracker: { markDataChanged() {}, markReadingProgressChanged() {} },
    WebBookService: class {},
    BookSourceInteractionPostProcessor: { interactionCacheIdentity: () => 'source-settings' },
    ReaderOpenTrace: { mark() {} },
    ReaderCacheBudget: { setProtectedBooksProvider() {}, noteTextWrite() {} },
    AppStorage: { setOrCreate: (key, value) => storage.set(key, value) },
    getContext: () => ({}), HdsFeedback: { showToast() {} }
  });
  vm.runInContext([
    'model/data/Book.ts', 'core/book/BookTypeSupport.ts', 'utils/SearchExplorePendingBook.ets',
    'model/data/AppDatabase.ts', 'core/book/ReadBookEngine.ts'
  ].map(file => compile(readEtsModule(file))).join('\n') + compile(`
    globalThis.api = { Book, BookTypeSupport, SearchExplorePendingBook, appDb, ReadBookEngine };
    globalThis.keepTrial = ({ ${method('SearchBookDetail', 'keepPendingReadBookInShelf')} });
    globalThis.reader = ({ ${method('ReadBook', 'saveReadConfig')} });
    globalThis.audio = ({ ${method('AudioBook', 'queueBookStateSave')} });
    globalThis.video = ({ ${method('VideoPlayer', 'saveProgress')} });
  `), context);
  const { Book, appDb: db, ReadBookEngine: Engine, SearchExplorePendingBook: pending } = context.api;
  const clone = book => Object.assign(new Book(), JSON.parse(JSON.stringify(book)));
  db.store = {
    async insert(table, bucket) { assert.equal(table, 'books'); rows.set(bucket.bookUrl, { ...bucket }); },
    async update(bucket, predicates) {
      writes.push({ ...bucket });
      const row = rows.get(predicates.bookUrl);
      if (!row) return 0;
      Object.assign(row, bucket);
      return 1;
    }
  };
  db.recordBookMutation = async () => {};
  db.initWithContext = async () => {};
  db.getBook = async url => {
    const row = rows.get(url);
    return row ? Object.assign(new Book(), row, {
      pendingAddToShelf: row.pendingAddToShelf === 1, isPrivate: row.isPrivate === 1
    }) : null;
  };
  db.getBookSource = async () => ({ bookSourceUrl: 'https://source.test', bookSourceName: 'fixture' });
  db.getBookChapters = async () => [{ index: 0, title: 'one', url: 'https://source.test/chapter/1' }];
  db.getBookChapterCacheDateMap = async () => new Map();
  const engine = Engine.get();
  // Content/network rendering is outside this lifecycle regression; opening/reusing the engine stays real.
  engine.peekContent = async () => 'content';
  return { ...context.api, db, engine, context, rows, writes, clone, pending };
}

async function trial(h, type = 0, media = 'novel') {
  const book = new h.Book();
  book.bookUrl = 'https://source.test/book/1';
  book.origin = 'https://source.test';
  book.type = type;
  if (media === 'video') book.putVariable('tab', 'video');
  h.pending.markPendingAddToShelf(book);
  await h.db.insertBook(book, 'temporary_read_insert');
  await h.engine.openBook(book);
  return book;
}

async function keep(h, book) {
  const page = Object.assign(h.context.keepTrial, {
    pendingAddToShelfBookUrl: book.bookUrl,
    syncStateFromBook() {}, addToShelf() { throw new Error('unexpected fallback'); }
  });
  assert.equal(await page.keepPendingReadBookInShelf(), true);
  const stored = await h.db.getBook(book.bookUrl);
  assert.equal(h.pending.filterShelfBooks([stored]).length, 1);
  assert(stored.shelfModifiedTime > 0);
  return stored;
}

const tests = {};
for (const media of ['novel', 'audio', 'comic', 'video']) {
  tests[`${media}: remains on shelf after trial → keep → reopen → save`] = async () => {
    const h = harness();
    const types = h.BookTypeSupport;
    const type = media === 'audio' ? types.AUDIO : media === 'comic' ? types.IMAGE : types.TEXT;
    const book = await trial(h, type, media);
    assert.equal(types.mediaCategoryOf(book), media);
    const kept = await keep(h, book);
    assert.equal(book.pendingAddToShelf, true, 'detail and engine hold separate snapshots');
    const chapters = h.engine.chapters;
    await h.engine.openBook(await h.db.getBook(book.bookUrl));
    assert.equal(h.engine.chapters, chapters, 'reuse cached catalog');
    assert.equal(types.mediaCategoryOf(h.engine.book), media);
    if (media === 'audio') {
      const page = Object.assign(h.context.audio, { progressSaveQueue: Promise.resolve() });
      await page.queueBookStateSave(h.engine.book);
    } else if (media === 'video') {
      const page = Object.assign(h.context.video, {
        book: h.engine.book, positionSec: 27, videoUrl: 'https://source.test/1.mp4'
      });
      page.saveProgress(true);
    } else {
      const page = Object.assign(h.context.reader, {
        book: h.engine.book, currentReaderThemeIndex: () => 0
      });
      await page.saveReadConfig();
    }
    const saved = await h.db.getBook(book.bookUrl);
    assert.equal(h.pending.filterShelfBooks([saved]).length, 1, media);
    assert.equal(saved.shelfModifiedTime, kept.shelfModifiedTime, media);
    assert.equal(h.engine.book.pendingAddToShelf, false, media);
    assert.equal(h.engine.book.shelfModifiedTime, kept.shelfModifiedTime, media);
  };
}
Object.assign(tests, {
  async 'prewarm reads durable shelf state instead of the retained trial snapshot'() {
    const h = harness();
    const book = await trial(h);
    await keep(h, book);
    await h.engine.prewarmOpen(book.bookUrl);
    assert.equal(h.engine.book.pendingAddToShelf, false);
  },
  async 'source initialization cannot write the old shelf state during session reuse'() {
    const h = harness();
    const book = await trial(h);
    await keep(h, book);
    const stored = await h.db.getBook(book.bookUrl);
    stored.replaceVariable('{}'); // Force source identity backfill, which writes a full Book.
    book.replaceVariable('{}');
    h.writes.length = 0;
    await h.engine.openBook(stored);
    assert(h.writes.length > 0);
    assert.equal(h.writes[0].pendingAddToShelf, 0);
    assert.equal(h.writes[0].shelfModifiedTime, stored.shelfModifiedTime);
  },
  async 'late trial saves cannot hide a kept book or erase its shelf timestamp'() {
    const h = harness();
    const book = await trial(h);
    const stale = h.clone(book);
    const kept = await keep(h, book);
    stale.durChapterPos = 42;
    await h.db.updateBook(stale, false, 'late_background_save');
    const stored = await h.db.getBook(book.bookUrl);
    assert.equal(stored.pendingAddToShelf, false);
    assert.equal(stored.shelfModifiedTime, kept.shelfModifiedTime);
    assert.equal(stored.durChapterPos, 42, 'progress is still persisted');
  },
  async 'saving an unkept trial does not add it to the shelf'() {
    const h = harness();
    const book = await trial(h);
    await h.db.updateBook(book, false);
    const stored = await h.db.getBook(book.bookUrl);
    assert.equal(stored.pendingAddToShelf, true);
    assert.equal(stored.shelfModifiedTime, 0);
    assert.equal(h.pending.filterShelfBooks([stored]).length, 0);
  },
  async 'prewarming a removed book does not reuse a stale trial session'() {
    const h = harness();
    const book = await trial(h);
    h.rows.delete(book.bookUrl);
    h.writes.length = 0;
    await h.engine.prewarmOpen(book.bookUrl);
    assert.equal(h.writes.length, 0);
    assert.equal(await h.db.getBook(book.bookUrl), null);
  },
  async 'reopening an in-flight engine task merges the kept shelf state'() {
    const h = harness();
    const book = await trial(h);
    const kept = await keep(h, book);
    let release;
    h.engine.openBookTask = new Promise(resolve => { release = resolve; });
    h.engine.openBookTaskUrl = book.bookUrl;
    const reopening = h.engine.openBook(kept);
    release();
    await reopening;
    assert.equal(h.engine.book.pendingAddToShelf, false);
    assert.equal(h.engine.book.shelfModifiedTime, kept.shelfModifiedTime);
  }
});

let failed = 0;
for (const [name, test] of Object.entries(tests)) {
  try { await test(); console.log(`PASS ${name}`); }
  catch (error) { failed++; console.error(`FAIL ${name}`, error); }
}
if (failed) process.exitCode = 1;
