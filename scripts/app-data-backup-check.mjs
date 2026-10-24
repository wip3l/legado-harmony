// Runs the production backup service against temporary files and in-memory DB/preferences.
// HarmonyOS ZIP and crypto are substituted here; device integration is covered by the HAP build/manual QA.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const plain = value => JSON.parse(JSON.stringify(value));
const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

function harness(t, nestedTarget = false) {
  const prefix = path.join(os.tmpdir(), 'qingye-backup-check-');
  const root = fs.mkdtempSync(prefix);
  t.after(() => {
    assert.ok(path.resolve(root).startsWith(path.resolve(prefix)));
    fs.rmSync(root, { recursive: true, force: true });
  });
  const states = new Map();
  const makeDevice = name => {
    const filesDir = path.join(root, name, 'files').replaceAll('\\', '/');
    const tempDir = path.join(root, name, 'temp').replaceAll('\\', '/');
    fs.mkdirSync(filesDir, { recursive: true });
    fs.mkdirSync(tempDir, { recursive: true });
    const context = { filesDir, tempDir };
    states.set(filesDir, { prefs: new Map(), books: new Map(), sources: [], groups: [], bookmarks: [], keywords: [] });
    return context;
  };
  const source = makeDevice('source');
  const target = makeDevice(nestedTarget ? 'source/files/migrated' : 'target');
  let active;
  let failCopy = '';
  const db = {
    initWithContext: async context => { active = states.get(context.filesDir); },
    getAllBookSources: async () => active.sources,
    getAllBooks: async () => [...active.books.values()],
    getCustomBookGroups: async () => active.groups,
    getAllBookmarks: async () => active.bookmarks,
    getSearchKeywords: async () => active.keywords,
    getBook: async url => active.books.get(url),
    restoreBook: async book => active.books.set(book.bookUrl, book),
    updateBook: async book => active.books.set(book.bookUrl, book),
    restoreBookSource: async value => active.sources.push(plain(value)),
    restoreBookGroup: async value => active.groups.push(plain(value)),
    restoreBookmark: async value => active.bookmarks.push(plain(value)),
    restoreSearchKeyword: async value => active.keywords.push(plain(value))
  };
  const handles = new Map();
  const platformFs = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 2, CREATE: 64, TRUNC: 512 },
    accessSync: fs.existsSync,
    stat: async file => fs.statSync(file),
    listFile: async file => fs.readdirSync(file),
    mkdir: async file => fs.mkdirSync(file, { recursive: true }),
    rmdir: async file => fs.rmdirSync(file),
    unlink: async file => fs.unlinkSync(file),
    open: async (file, mode) => {
      const fd = fs.openSync(file, mode & 64 ? 'w+' : mode === 0 ? 'r' : 'r+');
      handles.set(fd, file);
      return { fd };
    },
    close: async file => { fs.closeSync(file.fd); handles.delete(file.fd); },
    copyFile: async (src, dest) => {
      if (handles.get(src) === failCopy) throw new Error('simulated copy failure');
      fs.copyFileSync(handles.get(src), handles.get(dest));
    },
    read: async (fd, buffer, options = {}) => fs.readSync(fd, Buffer.from(buffer), 0,
      options.length ?? buffer.byteLength, options.offset ?? null),
    write: async (fd, buffer, options = {}) => fs.writeSync(fd, Buffer.from(buffer), 0,
      options.length ?? buffer.byteLength, options.offset ?? null)
  };
  const snapshot = dir => {
    const result = {};
    const walk = (current, relative = '') => {
      for (const name of fs.readdirSync(current)) {
        const absolute = path.join(current, name);
        const key = relative + name;
        if (fs.statSync(absolute).isDirectory()) walk(absolute, key + '/');
        else result[key] = fs.readFileSync(absolute).toString('base64');
      }
    };
    walk(dir);
    return result;
  };
  const zlib = {
    CompressLevel: { COMPRESS_LEVEL_BEST_SPEED: 1, COMPRESS_LEVEL_NO_COMPRESSION: 0 },
    compressFile: async (dir, archive) => fs.writeFileSync(archive, JSON.stringify(snapshot(dir))),
    decompressFile: async (archive, dir) => {
      for (const [relative, bytes] of Object.entries(JSON.parse(fs.readFileSync(archive, 'utf8')))) {
        const file = path.join(dir, relative);
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, Buffer.from(bytes, 'base64'));
      }
    }
  };
  const sandbox = vm.createContext({
    console, fs: platformFs, zlib,
    util: {
      TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
      TextDecoder: { create: () => ({ decodeWithStream: bytes => new TextDecoder().decode(bytes) }) }
    },
    statfs: { getFreeSize: async () => 1024 ** 4 },
    fileUri: { getUriFromPath: file => `file://${file}` },
    AppStorage: { get: () => 'recentRead', setOrCreate() {} },
    AppDatabase: { getInstance: () => db },
    BookshelfStateStore: { normalizeSortMode: value => value, saveSortMode: async () => {} },
    LocalBookService: {
      TYPE_EPUB: 1,
      isLocalBook: book => book.bookUrl.startsWith('local://'),
      isPhysicalLocalBook: book => book.bookUrl.startsWith('local://'),
      ensureLocalParserCurrent: async () => {}
    },
    preferences: { getPreferences: async (context, name) => {
      const prefs = states.get(context.filesDir).prefs;
      if (!prefs.has(name)) prefs.set(name, {});
      return {
        getAll: async () => plain(prefs.get(name)),
        clear: async () => prefs.set(name, {}),
        put: async (key, value) => { prefs.get(name)[key] = value; },
        flush: async () => {}
      };
    } },
    BackupCrypto: {
      encryptFile: async (src, dest) => { fs.copyFileSync(src, dest); return { payloadFile: 'payload.bin' }; },
      parseMetadata: JSON.parse,
      decryptFile: async (src, dest) => fs.copyFileSync(src, dest)
    }
  });
  vm.runInContext(compile(readEtsModule('model/data/Book.ts')) + '\n' +
    compile(readEtsModule('utils/ReaderFontHelper.ets')) + '\n' +
    compile(readEtsModule('utils/AppDataBackupService.ets')) +
    '\nglobalThis.api = { AppDataBackupService, AppDataBackupSelection, Book, ReaderFontHelper };', sandbox);
  const { AppDataBackupService: service, AppDataBackupSelection: Selection, Book, ReaderFontHelper: fonts } = sandbox.api;
  const write = (context, relative, contents) => {
    const file = `${context.filesDir}/${relative}`;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, contents);
    return file;
  };
  const addBook = (url, name, file = '') => {
    const book = new Book();
    book.bookUrl = url;
    book.name = name;
    book.durChapterIndex = 3;
    book.durChapterPos = 120;
    book.putVariable('readStarted', 'true');
    if (file) { book.putVariable('localFilePath', file); book.putVariable('localFormat', 'txt'); }
    states.get(source.filesDir).books.set(url, book);
    return book;
  };
  const selection = (...keys) => Object.assign(new Selection(), {
    sources: false, bookshelf: false, progress: false, bookmarks: false, localBooks: false, settings: false,
    searchHistory: false
  }, Object.fromEntries(keys.map(key => [key, true])));
  return { service, Selection, source, target, fonts, write, addBook, selection, zlib,
    from: states.get(source.filesDir), to: states.get(target.filesDir),
    failCopy: file => { failCopy = file; } };
}

test('full export/import preserves themes, OPDS, fonts, books and reports missing local files', async t => {
  const h = harness(t);
  const fontPath = h.write(h.source, 'reader_fonts/reader_font_1.ttf', 'font bytes');
  const family = h.fonts.stableFontFamily(fontPath);
  const library = JSON.stringify({ fonts: [{ familyName: family, filePath: fontPath, sourceName: '我的字体' }] });
  const profile = { fontMode: 'custom', fontFamily: family, fontFilePath: fontPath, customFontsRaw: library,
    bodyFontFamily: family, titleFontFamily: family, regexFontRulesRaw: JSON.stringify([{ fontFamily: family }]) };
  h.from.prefs.set('reader_settings', {
    readerFontMode: 'custom', readerFontFamily: family, readerFontFilePath: fontPath,
    readerFontSourceName: '我的字体', readerCustomFontsRaw: library,
    readerBodyFontFamily: family, readerTitleFontFamily: family,
    readerRegexFontRulesRaw: profile.regexFontRulesRaw, readerThemeProfileV1_custom_2: JSON.stringify(profile)
  });
  h.from.prefs.set('custom_theme_schemes', { active_scheme_id: 'custom_2', active_scheme_revision: 4,
    schemes: JSON.stringify([{ id: 'custom_1', name: '白天' }, { id: 'custom_2', name: '夜间', revision: 4 }]) });
  h.from.prefs.set('opds_settings', { active_server_id: 'opds-1', servers_v1: JSON.stringify([
    { id: 'opds-1', name: '书库', baseUrl: 'https://books.example/opds/', authType: 'basic',
      username: 'reader', rememberPassword: false, password: 'do-not-export' }
  ]) });
  h.from.prefs.set('opds_secrets', { password: 'secret' });
  h.to.prefs.set('opds_secrets', { password: 'target-secret' });
  h.to.prefs.set('reader_settings', { readerFontMode: 'device', readerCustomFontsRaw: '' });
  h.from.sources = [{ bookSourceUrl: 'https://source.example', loginHeader: 'secret', loginInfo: 'secret' }];
  h.from.groups = [{ groupId: 1, groupName: '收藏' }];
  h.addBook('https://books.example/1', '网络书');
  const localPath = h.write(h.source, 'local_books/1.txt', '本地书正文');
  h.addBook('local://1', '本地书', localPath);
  h.addBook('local://2', '缺失的书', `${h.source.filesDir}/local_books/missing.txt`);
  h.addBook('local://3', '没有路径的书');
  h.from.bookmarks = [{ bookUrl: 'local://1', content: '书签正文' }];
  h.from.keywords = [{ word: '测试', usage: 2 }];
  const selected = new h.Selection();
  selected.searchHistory = true;
  const backup = await h.service.createBackup(h.source, selected, 'password123');
  assert.equal(backup.manifest.localBooks.length, 1);
  assert.deepEqual(plain(backup.manifest.skippedLocalBooks), ['缺失的书', '没有路径的书']);
  assert.deepEqual(Object.keys(backup.manifest.localFiles), ['local://1']);
  assert.match(backup.summary(), /本地图书 1/);
  assert.match(backup.summary(), /网络书籍 1/);
  assert.equal(backup.manifest.preferenceStores.opds_secrets, undefined);
  assert.equal(backup.manifest.sources[0].loginHeader, '');
  const session = await h.service.prepareImport(h.target, backup.archivePath, 'password123');
  assert.equal(session.encrypted, true);
  const result = await h.service.importBackup(h.target, session, selected);
  assert.equal(result.localBooks, 1);
  assert.equal(result.books, 1);
  assert.equal(result.bookmarks, 1);
  assert.equal(result.progress, 2);
  assert.equal(result.settings, 14);
  assert.equal(h.to.books.get('local://1').durChapterPos, 120);
  assert.equal(fs.readFileSync(`${h.target.filesDir}/local_books/1.txt`, 'utf8'), '本地书正文');
  assert.deepEqual(h.to.prefs.get('custom_theme_schemes'), h.from.prefs.get('custom_theme_schemes'));
  const opds = JSON.parse(h.to.prefs.get('opds_settings').servers_v1)[0];
  assert.equal(opds.baseUrl, 'https://books.example/opds/');
  assert.equal(opds.password, '');
  assert.equal(opds.rememberPassword, false);
  assert.equal(h.to.prefs.get('opds_secrets').password, 'target-secret');
  const restored = h.to.prefs.get('reader_settings');
  const newPath = `${h.target.filesDir}/reader_fonts/reader_font_1.ttf`;
  const newFamily = h.fonts.stableFontFamily(newPath);
  assert.notEqual(newFamily, family);
  assert.equal(restored.readerFontMode, 'custom');
  assert.equal(restored.readerFontFilePath, newPath);
  assert.equal(restored.readerFontFamily, newFamily);
  assert.equal(restored.readerTitleFontFamily, newFamily);
  assert.equal(restored.readerBodyFontFamily, newFamily);
  assert.equal(JSON.parse(restored.readerCustomFontsRaw).fonts[0].familyName, newFamily);
  const restoredProfile = JSON.parse(restored.readerThemeProfileV1_custom_2);
  assert.equal(restoredProfile.titleFontFamily, newFamily);
  assert.equal(JSON.parse(restoredProfile.regexFontRulesRaw)[0].fontFamily, newFamily);
  assert.equal(fs.readFileSync(newPath, 'utf8'), 'font bytes');
  await h.service.discardImport(session);
  await h.service.discardExport(backup.archivePath);
  assert.equal(fs.existsSync(backup.archivePath), false);
});

test('deselected settings are neither exported nor restored', async t => {
  const h = harness(t);
  h.from.prefs.set('custom_theme_schemes', { active_scheme_id: 'incoming' });
  h.to.prefs.set('custom_theme_schemes', { active_scheme_id: 'local' });
  const backup = await h.service.createBackup(h.source, h.selection('bookshelf'), '');
  assert.deepEqual(plain(backup.manifest.preferenceStores), {});
  const settingsBackup = await h.service.createBackup(h.source, h.selection('settings'), '');
  const session = await h.service.prepareImport(h.target, settingsBackup.archivePath);
  await h.service.importBackup(h.target, session, h.selection('bookshelf'));
  assert.equal(h.to.prefs.get('custom_theme_schemes').active_scheme_id, 'local');
});

for (const version of [1, 2]) {
  test(`legacy v${version} without new optional fields still imports, absent stores stay intact`, async t => {
    const h = harness(t);
    h.to.prefs.set('opds_settings', { active_server_id: 'local' });
    h.from.prefs.set('reader_settings', { readerFontMode: 'device' });
    const backup = await h.service.createBackup(h.source, h.selection('settings'), '');
    const manifest = plain(backup.manifest);
    manifest.version = version;
    delete manifest.skippedLocalBooks;
    delete manifest.preferenceStores.opds_settings;
    delete manifest.preferenceStores.custom_theme_schemes;
    manifest.preferenceStores.account_commerce_session = '{"token":"untrusted"}';
    const archive = JSON.parse(fs.readFileSync(backup.archivePath, 'utf8'));
    archive['manifest.json'] = Buffer.from(JSON.stringify(manifest)).toString('base64');
    fs.writeFileSync(backup.archivePath, JSON.stringify(archive));
    const session = await h.service.prepareImport(h.target, backup.archivePath);
    await h.service.importBackup(h.target, session, h.selection('settings'));
    assert.equal(h.to.prefs.get('reader_settings').readerFontMode, 'device');
    assert.equal(h.to.prefs.get('opds_settings').active_server_id, 'local');
    assert.equal(h.to.prefs.has('account_commerce_session'), false);
  });
}

test('local file copy errors fail export instead of reporting a complete backup', async t => {
  const h = harness(t);
  const file = h.write(h.source, 'local_books/1.txt', 'content');
  h.addBook('local://1', '读取失败的书', file);
  h.failCopy(file);
  await assert.rejects(h.service.createBackup(h.source, h.selection('localBooks'), ''), /simulated copy failure/);
});

test('legacy backups with missing local book payload report skipped imports', async t => {
  const h = harness(t);
  const file = h.write(h.source, 'local_books/1.txt', 'content');
  h.addBook('local://1', '缺失载荷', file);
  const backup = await h.service.createBackup(h.source, h.selection('localBooks'), '');
  const session = await h.service.prepareImport(h.target, backup.archivePath);
  fs.unlinkSync(`${session.rootPath}/local_books/0.txt`);
  const result = await h.service.importBackup(h.target, session, h.selection('localBooks'));
  assert.equal(result.localBooks, 0);
  assert.equal(result.skippedLocalBooks, 1);
  assert.match(result.summary(), /跳过本地书 1/);
});

test('font paths are rebased once even when the target root contains the original root', async t => {
  const h = harness(t, true);
  const file = h.write(h.source, 'reader_fonts/a.ttf', 'font bytes');
  h.from.prefs.set('reader_settings', {
    readerFontMode: 'custom', readerFontFamily: h.fonts.stableFontFamily(file), readerFontFilePath: file,
    readerCustomFontsRaw: JSON.stringify([{ filePath: file, familyName: h.fonts.stableFontFamily(file) }])
  });
  const backup = await h.service.createBackup(h.source, h.selection('settings'), '');
  const session = await h.service.prepareImport(h.target, backup.archivePath);
  await h.service.importBackup(h.target, session, h.selection('settings'));
  const restored = h.to.prefs.get('reader_settings');
  assert.equal(restored.readerFontFilePath, `${h.target.filesDir}/reader_fonts/a.ttf`);
  assert.equal(restored.readerFontFamily, h.fonts.stableFontFamily(restored.readerFontFilePath));
  assert.equal(JSON.parse(restored.readerCustomFontsRaw)[0].filePath, restored.readerFontFilePath);
});
