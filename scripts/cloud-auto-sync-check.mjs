// Runs the real CloudAutoSync decision logic against in-memory stand-ins for files, the database,
// preferences and the cloud API. Device font rendering and real transfers are not covered here.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/account/CloudAutoSync.ets', import.meta.url), 'utf8');
const compiled = stripTypeScriptTypes(source.replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, ''),
  { mode: 'strip' });
const settingsSource = fs.readFileSync(new URL('../entry/src/main/ets/account/CloudSyncSettingsStore.ets', import.meta.url), 'utf8');
const settingsCompiled = stripTypeScriptTypes(settingsSource.replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, ''),
  { mode: 'strip' });

const NOW = Date.parse('2026-11-10T12:00:00+08:00');
const HASH = { a: 'a'.repeat(64), b: 'b'.repeat(64), c: 'c'.repeat(64), d: 'd'.repeat(64) };

function fixture(settings = {}) {
  const storage = new Map();
  const prefs = new Map();
  prefs.set('settings_u1', JSON.stringify(settings));
  const files = new Map(); // path -> { mtime (seconds), size, hash }
  const books = [];
  const cloud = { files: [], tombstones: [] };
  const log = { staged: [], removed: [], inserted: [], deleted: [], imports: [], downloads: [], copies: [], fontNames: [], fontSaves: 0 };
  let sku = 'SUPER_LIFETIME';

  class Book {
    constructor() { this.variables = {}; this.name = ''; this.author = ''; this.bookUrl = ''; this.origin = '';
      this.type = 1; this.group = 0; this.isPrivate = false; this.pendingAddToShelf = false; }
    getVariable(key) { return this.variables[key] || ''; }
    putVariable(key, value) { this.variables[key] = value; }
  }
  const context = { filesDir: '/data/files', getApplicationContext: () => ({ setFont() {} }) };
  const sandbox = vm.createContext({
    console, setTimeout, clearTimeout, Date, JSON, Math, Number, String, Array, Set, Map, Promise, Error, RegExp,
    Book,
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    preferences: { getPreferences: async () => ({ get: async (key, fallback) => prefs.has(key) ? prefs.get(key) : fallback,
      put: async (key, value) => { prefs.set(key, value); }, flush: async () => {} }) },
    fs: {
      accessSync: path => files.has(path),
      statSync: path => { const f = files.get(path); if (!f) throw new Error('missing'); return f; },
      stat: async path => { const f = files.get(path); if (!f) throw new Error('missing'); return f; },
      unlinkSync: path => { files.delete(path); },
      unlink: async path => { files.delete(path); },
      mkdir: async () => {}, copy: async (source, target) => { log.copies.push({ source, target }); files.set(target, files.get(source)); }
    },
    fileUri: { getUriFromPath: path => path },
    AccountSessionStore: { account: () => ({ userId: 'u1' }), isLoggedIn: () => true, activeMembershipSku: () => sku },
    CloudFileClient: {
      summary: async () => ({ configured: true, eligible: true }),
      listAll: async () => cloud.files.map(file => ({ ...file })),
      tombstones: async () => ({ tombstones: cloud.tombstones.map(t => ({ ...t })) }),
      remove: async (id, reason) => { log.removed.push({ id, reason }); cloud.files = cloud.files.filter(f => f.id !== id); },
      isTransferring: () => false,
      pending: async () => null,
      stage: async (_ctx, path, name, kind, meta, auto, manifestHash) => {
        log.staged.push({ path, name, kind, meta, auto, manifestHash });
      },
      upload: async () => 'uploaded-id',
      cancelUpload: async () => {},
      manifestHashOfFile: async path => files.get(path).hash,
      download: async (_ctx, file) => { log.downloads.push(file.id); return '/data/files/cloud_transfers/tmp'; }
    },
    CloudFontImport: {
      uploadName: (name, path) => `${name}.${path.split('.').pop()}`,
      localPath: (dir, file) => `${dir}/reader_fonts/cloud_${file.id}.ttf`,
      saveNames: async (_ctx, dir, items) => {
        log.fontNames.push(...items);
        const data = JSON.parse(storage.get('readerCustomFontsRaw') || '{"fonts":[]}');
        for (const item of items) {
          const path = `${dir}/reader_fonts/cloud_${item.id}.ttf`;
          if (!data.fonts.some(font => font.filePath === path)) {
            data.fonts.push({ filePath: path, familyName: item.id, sourceName: item.name });
          }
        }
        storage.set('readerCustomFontsRaw', JSON.stringify(data));
      }
    },
    CloudFileItem: class { constructor() { this.meta = null; } },
    CloudFileMeta: class {},
    AppDatabase: { getInstance: () => ({
      initWithContext: async () => {},
      getAllBooks: async () => books.slice(),
      insertBook: async book => { log.inserted.push(book); books.push(book); },
      updateBook: async book => { const i = books.findIndex(b => b.bookUrl === book.bookUrl); if (i >= 0) books[i] = book; },
      deleteBook: async url => { log.deleted.push(url); const i = books.findIndex(b => b.bookUrl === url); if (i >= 0) books.splice(i, 1); }
    }) },
    LocalBookService: {
      ORIGIN: 'local', TYPE_EPUB: 2, TYPE_TXT: 1, LOCAL_CONTENT_HASH_KEY: 'localContentHash',
      isLocalBook: book => book.origin === 'local',
      isSupportedFormat: format => ['txt', 'epub', 'mobi'].includes((format || '').toLowerCase()),
      bookTypeForFormat: format => ['epub', 'mobi'].includes((format || '').toLowerCase()) ? 2 : 1,
      ensureContentHash: async book => book.getVariable('localContentHash'),
      exists: path => files.has(path),
      sanitizeFileName: value => value,
      extensionOf: path => path.split('.').pop(),
      fileStem: path => path.replace(/\.[^.]+$/, ''),
      importCloudBook: async (_ctx, path, format, name, url, clearVariables) => {
        log.imports.push({ path, format, name, url });
        let book = books.find(b => b.bookUrl === url);
        if (!book) { book = new Book(); book.bookUrl = url; books.push(book); }
        book.name = name.replace(/\.[^.]+$/, ''); book.origin = 'local'; book.type = format === 'epub' ? 2 : 1;
        book.putVariable('localFilePath', `/data/files/local_books/${name}`);
        book.putVariable('localFormat', format); book.putVariable('localContentHash', HASH.a);
        files.set(book.getVariable('localFilePath'), { mtime: 0, size: 100, hash: HASH.b });
        for (const key of clearVariables) book.putVariable(key, '');
        return book;
      },
      deleteLocalBookFiles: () => {}
    },
    ReaderFontHelper: { fileNameFromPath: path => path.split('/').pop(), resolveDisplayName: name => name },
    ReaderSettingsStore: { saveFontSettings: async () => { log.fontSaves++; } }
  });
  vm.runInContext(settingsCompiled, sandbox);
  vm.runInContext(compiled, sandbox);
  const sync = vm.runInContext('CloudAutoSync', sandbox);
  const settingsStore = vm.runInContext('CloudSyncSettingsStore', sandbox);

  const addFont = (path, name, hash, importedAt) => {
    files.set(path, { mtime: Math.floor(importedAt / 1000), size: 100, hash });
    const raw = JSON.parse(storage.get('readerCustomFontsRaw') || '{"fonts":[]}');
    raw.fonts.push({ familyName: name, filePath: path, sourceName: name });
    storage.set('readerCustomFontsRaw', JSON.stringify(raw));
  };
  const fontPaths = () => JSON.parse(storage.get('readerCustomFontsRaw') || '{"fonts":[]}').fonts.map(f => f.filePath);
  const addBook = (url, name, hash, addedAt, extra = {}) => {
    const book = new Book();
    Object.assign(book, { bookUrl: url, name, origin: 'local' }, extra);
    book.putVariable('localContentHash', hash);
    book.putVariable('bookAddTime', `${addedAt}`);
    book.putVariable('localFilePath', `/data/files/local_books/${url.slice(-4)}.txt`);
    book.putVariable('localFormat', 'txt');
    files.set(book.getVariable('localFilePath'), { mtime: 0, size: 10, hash: 'x' });
    books.push(book);
    return book;
  };
  const cloudFile = (id, kind, manifestHash, meta = null, name = 'f.ttf') =>
    cloud.files.push({ id, kind, name, bytes: 100, state: 'READY', manifestHash, meta });
  return { sync, settingsStore, context, storage, prefs, files, books, cloud, log, addFont, fontPaths, addBook, cloudFile,
    setSku: value => { sku = value; } };
}

test('fonts: new ones upload, cloud copies link, others show as downloadable', async () => {
  const f = fixture();
  f.addFont('/data/files/reader_fonts/reader_font_1.ttf', '霞鹜文楷', HASH.a, NOW);
  f.addFont('/data/files/reader_fonts/reader_font_2.ttf', '思源宋体', HASH.b, NOW);
  f.cloudFile('11111111-1111-1111-1111-111111111111', 'FONT', HASH.b, { fontName: '思源宋体' }, '思源宋体.ttf');
  f.cloudFile('22222222-2222-2222-2222-222222222222', 'FONT', HASH.c, { fontName: '方正楷体' }, '方正楷体.otf');
  await f.sync.reconcile(f.context);
  assert.deepEqual(f.log.staged.map(s => s.name), ['霞鹜文楷.ttf']);
  assert.equal(f.log.staged[0].auto, true);
  assert.equal(f.log.staged[0].manifestHash, HASH.a); // Fingerprint reused, not recomputed during upload.
  assert.equal(f.log.staged[0].meta.fontName, '霞鹜文楷');
  assert.deepEqual(f.sync.remoteFonts().map(r => r.name), ['方正楷体.otf']);
});

test('file scope preferences: old accounts default on; explicit off survives saves, runtime updates and account switches', async () => {
  const f = fixture();
  const settings = await f.settingsStore.load(f.context, 'u1');
  assert.equal(settings.localBooksEnabled, true);
  assert.equal(settings.customFontsEnabled, true);
  settings.localBooksEnabled = false;
  settings.customFontsEnabled = false;
  await f.settingsStore.saveUserPreferences(f.context, 'u1', settings);
  await f.settingsStore.saveRuntimeState(f.context, 'u1', 'synced', NOW, 0, '');
  const other = await f.settingsStore.load(f.context, 'u2');
  assert.equal(other.localBooksEnabled, true);
  assert.equal(other.customFontsEnabled, true);
  const restored = await f.settingsStore.load(f.context, 'u1');
  assert.equal(restored.localBooksEnabled, false);
  assert.equal(restored.customFontsEnabled, false);
});

for (const kind of ['BOOK', 'FONT']) {
  test(`${kind}: disabled scope skips upload, cloud imports and deletions while the other scope works`, async () => {
    const f = fixture({ localBooksEnabled: kind !== 'BOOK', customFontsEnabled: kind !== 'FONT' });
    const book = f.addBook('local://aaaa', '本地书', HASH.a, NOW);
    f.addFont('/data/files/reader_fonts/a.ttf', '本地字体', HASH.b, NOW);
    f.cloudFile('remote-book', 'BOOK', 'm', { title: '云端书', contentHash: HASH.c, format: 'txt' });
    f.cloudFile('remote-font', 'FONT', HASH.d);
    await f.sync.reconcile(f.context);
    assert.deepEqual(f.log.staged.map(s => s.kind), [kind === 'BOOK' ? 'FONT' : 'BOOK']);
    assert.equal(f.log.inserted.length, kind === 'BOOK' ? 0 : 1);
    assert.equal(f.sync.remoteFonts().length, kind === 'FONT' ? 0 : 1);
    if (kind === 'BOOK') await f.sync.onBookRemoved(f.context, book);
    else await f.sync.onFontDeleted(f.context, '/data/files/reader_fonts/a.ttf');
    assert.equal(f.log.removed.length, 0);
    assert.ok(![...f.prefs.values()].some(value => typeof value === 'string' && value.includes('REMOVED')));
  });
}

test('both file scopes off leaves local and cloud contents untouched', async () => {
  const f = fixture({ localBooksEnabled: false, customFontsEnabled: false });
  f.addBook('local://aaaa', '本地书', HASH.a, NOW);
  f.addFont('/data/files/reader_fonts/a.ttf', '本地字体', HASH.b, NOW);
  f.cloudFile('remote-book', 'BOOK', 'm', { title: '云端书', contentHash: HASH.c, format: 'txt' });
  f.cloudFile('remote-font', 'FONT', HASH.d);
  await f.sync.reconcile(f.context);
  assert.equal(f.log.staged.length, 0);
  assert.equal(f.log.inserted.length, 0);
  assert.equal(f.log.deleted.length, 0);
  assert.equal(f.sync.remoteFonts().length, 0);
});

test('sync page gates both switches by membership and restores the previous value on save failure', async () => {
  const pageSource = fs.readFileSync(new URL('../entry/src/main/ets/pages/DataSync.ets', import.meta.url), 'utf8');
  const match = /^  async setFileScopeEnabled\([\s\S]*?\n  }/m.exec(pageSource);
  assert.ok(match);
  let sku = '';
  let prompts = 0;
  let saves = 0;
  let scheduled = 0;
  let saveSucceeds = true;
  const sandbox = vm.createContext({
    AccountSessionStore: { activeMembershipSku: () => sku },
    CloudAutoSync: { schedule: () => { scheduled++; } }, getContext: () => ({})
  });
  vm.runInContext(stripTypeScriptTypes(`globalThis.page = { ${match[0]} }`, { mode: 'strip' }), sandbox);
  const page = sandbox.page;
  Object.assign(page, { saving: false, localBooksEnabled: false, customFontsEnabled: false,
    promptSuperMembership: async () => { prompts++; },
    saveSettings: async () => { saves++; return saveSucceeds; } });
  for (const tier of ['', 'MONTHLY', 'ANNUAL', 'LIFETIME']) {
    sku = tier;
    await page.setFileScopeEnabled(true, true);
    await page.setFileScopeEnabled(false, true);
    assert.equal(page.localBooksEnabled, false);
    assert.equal(page.customFontsEnabled, false);
  }
  assert.equal(prompts, 8);
  assert.equal(saves, 0);
  assert.equal(scheduled, 0);
  sku = 'SUPER_LIFETIME';
  await page.setFileScopeEnabled(true, true);
  await page.setFileScopeEnabled(false, true);
  assert.equal(page.localBooksEnabled, true);
  assert.equal(page.customFontsEnabled, true);
  assert.equal(scheduled, 2);
  saveSucceeds = false;
  await page.setFileScopeEnabled(true, false);
  await page.setFileScopeEnabled(false, false);
  assert.equal(page.localBooksEnabled, true);
  assert.equal(page.customFontsEnabled, true);
  assert.equal(scheduled, 2);
});

test('fonts: removal elsewhere follows; DETACHED keeps; re-import after removal uploads again', async () => {
  const f = fixture();
  const removedAt = NOW;
  f.addFont('/data/files/reader_fonts/old.ttf', '旧字体', HASH.a, NOW - 3600000);
  f.addFont('/data/files/reader_fonts/kept.ttf', '留存', HASH.b, NOW - 3600000);
  f.addFont('/data/files/reader_fonts/again.ttf', '重新导入', HASH.c, NOW + 3600000);
  f.cloud.tombstones.push({ id: 't1', kind: 'FONT', manifestHash: HASH.a, reason: 'REMOVED', removedAt });
  f.cloud.tombstones.push({ id: 't2', kind: 'FONT', manifestHash: HASH.b, reason: 'DETACHED', removedAt });
  f.cloud.tombstones.push({ id: 't3', kind: 'FONT', manifestHash: HASH.c, reason: 'REMOVED', removedAt });
  f.storage.set('readerFontFilePath', '/data/files/reader_fonts/old.ttf');
  await f.sync.reconcile(f.context);
  assert.equal(f.files.has('/data/files/reader_fonts/old.ttf'), false);
  assert.deepEqual(f.fontPaths(), ['/data/files/reader_fonts/kept.ttf', '/data/files/reader_fonts/again.ttf']);
  assert.equal(f.storage.get('readerFontMode'), 'system'); // The removed font was in use: back to system font.
  assert.deepEqual(f.log.staged.map(s => s.name), ['重新导入.ttf']);
});

test('fonts: deleting locally removes the cloud copy everywhere, even before its id is known', async () => {
  const f = fixture();
  f.addFont('/data/files/reader_fonts/a.ttf', 'A', HASH.a, NOW);
  f.addFont('/data/files/reader_fonts/cloud_33333333-3333-3333-3333-333333333333.ttf', 'B', HASH.b, NOW);
  f.cloudFile('44444444-4444-4444-4444-444444444444', 'FONT', HASH.a);
  f.cloudFile('33333333-3333-3333-3333-333333333333', 'FONT', HASH.b);
  await f.sync.onFontDeleted(f.context, '/data/files/reader_fonts/a.ttf');
  await f.sync.onFontDeleted(f.context, '/data/files/reader_fonts/cloud_33333333-3333-3333-3333-333333333333.ttf');
  f.storage.set('readerCustomFontsRaw', '{"fonts":[]}');
  await f.sync.reconcile(f.context);
  assert.deepEqual(f.log.removed.map(r => `${r.id}:${r.reason}`).sort(), [
    '33333333-3333-3333-3333-333333333333:REMOVED', '44444444-4444-4444-4444-444444444444:REMOVED']);
  assert.equal(f.log.staged.length, 0);
});

test('books: upload new, placeholder for cloud-only, private stays local', async () => {
  const f = fixture();
  f.addBook('local://aaaa', '三体', HASH.a, NOW);
  f.addBook('local://bbbb', '私密', HASH.b, NOW, { isPrivate: true });
  f.addBook('local://cccc', '已在云端', HASH.c, NOW);
  f.cloudFile('55555555-5555-5555-5555-555555555555', 'BOOK', 'm1', { title: '已在云端', contentHash: HASH.c, format: 'txt' });
  f.cloudFile('66666666-6666-6666-6666-666666666666', 'BOOK', 'm2',
    { title: '球状闪电', author: '刘慈欣', contentHash: HASH.d, format: 'epub' }, '球状闪电.epub');
  await f.sync.reconcile(f.context);
  assert.deepEqual(f.log.staged.map(s => s.name), ['三体.txt']);
  assert.deepEqual({ ...f.log.staged[0].meta }, { title: '三体', author: '', format: 'txt', contentHash: HASH.a });
  assert.equal(f.log.inserted.length, 1);
  const placeholder = f.log.inserted[0];
  assert.equal(placeholder.bookUrl, 'cloudbook://66666666-6666-6666-6666-666666666666');
  assert.equal(placeholder.name, '球状闪电');
  assert.equal(placeholder.author, '刘慈欣');
  assert.equal(placeholder.origin, 'local'); // Shelf filters treat it as a local book.
  assert.equal(placeholder.type, 2);
  assert.equal(f.sync.isPlaceholder(placeholder), true);
  assert.equal(placeholder.getVariable('localContentHash'), HASH.d); // Reading progress keys on this.
  await f.sync.reconcile(f.context);
  assert.equal(f.log.inserted.length, 1); // Not duplicated on the next run.
});

test('books: removal elsewhere removes copies and placeholders; re-added later uploads', async () => {
  const f = fixture();
  f.addBook('local://aaaa', '移走的', HASH.a, NOW - 3600000);
  f.addBook('local://bbbb', '再加回来', HASH.b, NOW + 3600000);
  f.addBook('local://cccc', '只删云端', HASH.c, NOW - 3600000);
  const placeholder = f.addBook('cloudbook://77777777-7777-7777-7777-777777777777', '占位', HASH.d, NOW);
  placeholder.putVariable('cloudPlaceholder', '1');
  placeholder.putVariable('cloudFileId', '77777777-7777-7777-7777-777777777777');
  f.cloud.tombstones.push({ id: 't1', kind: 'BOOK', manifestHash: 'm', meta: { contentHash: HASH.a }, reason: 'REMOVED', removedAt: NOW });
  f.cloud.tombstones.push({ id: 't2', kind: 'BOOK', manifestHash: 'm', meta: { contentHash: HASH.b }, reason: 'REMOVED', removedAt: NOW });
  f.cloud.tombstones.push({ id: 't3', kind: 'BOOK', manifestHash: 'm', meta: { contentHash: HASH.c }, reason: 'DETACHED', removedAt: NOW });
  await f.sync.reconcile(f.context);
  assert.deepEqual(f.log.deleted.sort(), ['cloudbook://77777777-7777-7777-7777-777777777777', 'local://aaaa']);
  assert.deepEqual(f.log.staged.map(s => s.name), ['再加回来.txt']);
  assert.ok(f.books.some(b => b.bookUrl === 'local://cccc')); // Cloud copy dropped only: the book stays.
});

test('books: shelf removal deletes the cloud file with REMOVED; not eligible means no work', async () => {
  const f = fixture();
  const book = f.addBook('local://aaaa', '三体', HASH.a, NOW);
  f.cloudFile('88888888-8888-8888-8888-888888888888', 'BOOK', 'm', { contentHash: HASH.a });
  await f.sync.onBookRemoved(f.context, book);
  f.books.splice(0, 1);
  await f.sync.reconcile(f.context);
  assert.deepEqual(f.log.removed, [{ id: '88888888-8888-8888-8888-888888888888', reason: 'REMOVED' }]);

  const g = fixture();
  g.setSku('ANNUAL');
  g.addBook('local://aaaa', '三体', HASH.a, NOW);
  g.cloudFile('99999999-9999-9999-9999-999999999999', 'FONT', HASH.b);
  await g.sync.reconcile(g.context);
  assert.equal(g.log.staged.length, 0);
  assert.equal(g.log.inserted.length, 0);
  assert.equal(g.sync.remoteFonts().length, 0);
});

test('manual EPUB without metadata appears under local books, then downloads into the same shelf row', async () => {
  const f = fixture();
  f.cloudFile('manual-epub', 'BOOK', HASH.b, null, '手动上传.epub');
  await f.sync.reconcile(f.context);
  assert.equal(f.books.length, 1);
  const book = f.books[0];
  assert.equal(book.origin, 'local');
  assert.equal(book.type, 2);
  assert.equal(book.name, '手动上传');
  assert.equal(book.getVariable('localContentHash'), ''); // Chunk manifest is NOT the content hash.
  assert.equal(f.sync.isPlaceholder(book), true);
  book.group = 8; book.durChapterIndex = 12;
  await f.sync.reconcile(f.context);
  assert.equal(f.books.length, 1);
  const ready = await f.sync.ensureBookDownloaded(f.context, book);
  assert.equal(ready.bookUrl, book.bookUrl);
  assert.equal(ready.group, 8);
  assert.equal(ready.durChapterIndex, 12);
  assert.equal(f.sync.isPlaceholder(ready), false);
  assert.equal(ready.getVariable('cloudFileId'), 'manual-epub');
  assert.deepEqual(f.log.downloads, ['manual-epub']);
  await f.sync.reconcile(f.context);
  assert.equal(f.books.length, 1);
  assert.equal(f.log.staged.length, 0);
  await f.sync.onBookRemoved(f.context, ready);
  f.books.length = 0;
  await f.sync.reconcile(f.context);
  assert.deepEqual(f.log.removed, [{ id: 'manual-epub', reason: 'REMOVED' }]);
});

test('historical manual upload links matching local bytes instead of adding or uploading another copy', async () => {
  const f = fixture();
  const book = f.addBook('local://same', '已有的书', HASH.a, NOW);
  f.files.set(book.getVariable('localFilePath'), { mtime: 0, size: 100, hash: HASH.b });
  f.cloudFile('manual-txt', 'BOOK', HASH.b, null, '已有的书.txt');
  await f.sync.reconcile(f.context);
  assert.equal(f.books.length, 1);
  assert.equal(book.getVariable('cloudFileId'), 'manual-txt');
  assert.equal(book.getVariable('localContentHash'), HASH.a);
  assert.equal(f.log.staged.length, 0);
  assert.equal(f.log.inserted.length, 0);
});

test('new manual upload imports staged bytes without downloading, repeated import reuses the shelf row', async () => {
  const f = fixture();
  f.cloudFile('new-upload', 'BOOK', HASH.b, null, '新书.epub');
  const ready = await f.sync.importBookFile(f.context, f.cloud.files[0], '/data/staged.epub');
  assert.equal(f.books.length, 1);
  assert.equal(ready.origin, 'local');
  assert.equal(ready.type, 2);
  assert.equal(f.sync.isPlaceholder(ready), false);
  assert.equal(f.log.imports[0].path, '/data/staged.epub');
  assert.equal(f.log.downloads.length, 0);
  assert.ok(f.storage.get('shelfUpdateTime'));
  ready.group = 4; ready.durChapterIndex = 7;
  await f.sync.importBookFile(f.context, f.cloud.files[0], '/data/staged-again.epub');
  await f.sync.reconcile(f.context);
  assert.equal(f.books.length, 1);
  assert.equal(f.log.imports.length, 1);
  assert.equal(f.log.staged.length, 0);
  assert.equal(ready.group, 4);
  assert.equal(ready.durChapterIndex, 7);
});

test('metadata-free remote deletion follows the linked id; detached files stay local', async () => {
  const f = fixture();
  const removed = f.addBook('local://gone', '移除', HASH.a, NOW - 1000);
  const kept = f.addBook('local://keep', '保留', HASH.b, NOW - 1000);
  removed.putVariable('cloudFileId', 'removed');
  kept.putVariable('cloudFileId', 'detached');
  f.cloud.tombstones.push({ id: 'removed', kind: 'BOOK', meta: null, reason: 'REMOVED', removedAt: NOW });
  f.cloud.tombstones.push({ id: 'detached', kind: 'BOOK', meta: null, reason: 'DETACHED', removedAt: NOW });
  await f.sync.reconcile(f.context);
  assert.deepEqual(f.log.deleted, ['local://gone']);
  assert.equal(f.books[0].bookUrl, 'local://keep');
  assert.equal(f.log.staged.length, 0);
});

test('manual font upload registers staged bytes without downloading or changing the selected font', async () => {
  const f = fixture();
  f.storage.set('readerFontFilePath', '/existing.ttf');
  f.files.set('/staged.upload', { mtime: 0, size: 100, hash: HASH.b });
  f.cloudFile('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'FONT', HASH.b, null, '中文字体.ttf');
  const path = await f.sync.importFontFile(f.context, f.cloud.files[0], '/staged.upload');
  assert.equal(f.log.downloads.length, 0);
  assert.equal(f.log.fontNames[0].name, '中文字体.ttf');
  assert.deepEqual(f.log.copies, [{ source: '/staged.upload', target: path }]);
  assert.equal(f.storage.get('readerFontFilePath'), '/existing.ttf');
  await f.sync.importFontFile(f.context, f.cloud.files[0], '/staged.upload');
  await f.sync.reconcile(f.context);
  assert.equal(f.fontPaths().length, 1);
  assert.equal(f.log.copies.length, 1);
  assert.equal(f.log.staged.length, 0);
  assert.equal(f.sync.remoteFonts().length, 0);
});

test('uploading an existing local font reuses its path without a duplicate cloud-named copy', async () => {
  const f = fixture();
  f.addFont('/data/files/reader_fonts/local.ttf', '已有字体', HASH.b, NOW);
  f.cloudFile('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'FONT', HASH.b, null, '已有字体.ttf');
  assert.equal(await f.sync.importFontFile(f.context, f.cloud.files[0], '/staged.upload'), '/data/files/reader_fonts/local.ttf');
  assert.equal(f.log.copies.length, 0);
  assert.equal(f.fontPaths().length, 1);
});
