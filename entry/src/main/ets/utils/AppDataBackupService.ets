import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import zlib from '@ohos.zlib';
import util from '@ohos.util';
import preferences from '@ohos.data.preferences';
import { Context } from '@kit.AbilityKit';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book, BookGroup, Bookmark, BookSource, ReadConfig, SearchKeyword } from '../model/data/Book';
import { LocalBookService } from '../core/book/LocalBookService';

export class AppDataBackupSelection {
  sources: boolean = true;
  bookshelf: boolean = true;
  progress: boolean = true;
  bookmarks: boolean = true;
  localBooks: boolean = true;
  settings: boolean = true;
  searchHistory: boolean = false;
}

export class BookProgressBackup {
  bookUrl: string = '';
  durChapterTitle: string = '';
  durChapterIndex: number = 0;
  durChapterPos: number = 0;
  durChapterTime: number = 0;
  variable: string = '';
}

export class AppDataBackupManifest {
  format: string = 'legado-harmony-backup';
  version: number = 1;
  createdAt: number = 0;
  sourceFilesDir: string = '';
  categories: string[] = [];
  sources: BookSource[] = [];
  books: Book[] = [];
  bookGroups: BookGroup[] = [];
  progress: BookProgressBackup[] = [];
  bookmarks: Bookmark[] = [];
  localBooks: Book[] = [];
  localFiles: Record<string, string> = {};
  preferenceStores: Record<string, string> = {};
  sourceGroupPreferences: string = '';
  searchKeywords: SearchKeyword[] = [];
  bookshelfSortMode: string = 'recentRead';
}

export class AppDataBackupExportResult {
  archivePath: string = '';
  manifest: AppDataBackupManifest = new AppDataBackupManifest();
}

export class AppDataBackupImportSession {
  rootPath: string = '';
  manifest: AppDataBackupManifest = new AppDataBackupManifest();
}

export class AppDataBackupImportResult {
  sources: number = 0;
  books: number = 0;
  localBooks: number = 0;
  progress: number = 0;
  bookmarks: number = 0;
  settings: number = 0;
  searchKeywords: number = 0;

  summary(): string {
    const parts: string[] = [];
    if (this.sources > 0) parts.push(`书源 ${this.sources}`);
    if (this.books > 0) parts.push(`书架 ${this.books}`);
    if (this.localBooks > 0) parts.push(`本地图书 ${this.localBooks}`);
    if (this.progress > 0) parts.push(`进度 ${this.progress}`);
    if (this.bookmarks > 0) parts.push(`书签 ${this.bookmarks}`);
    if (this.settings > 0) parts.push(`设置 ${this.settings}`);
    if (this.searchKeywords > 0) parts.push(`搜索记录 ${this.searchKeywords}`);
    return parts.length > 0 ? parts.join('、') : '没有可导入的数据';
  }
}

export class AppDataBackupService {
  static readonly CATEGORY_SOURCES: string = 'sources';
  static readonly CATEGORY_BOOKSHELF: string = 'bookshelf';
  static readonly CATEGORY_PROGRESS: string = 'progress';
  static readonly CATEGORY_BOOKMARKS: string = 'bookmarks';
  static readonly CATEGORY_LOCAL_BOOKS: string = 'localBooks';
  static readonly CATEGORY_SETTINGS: string = 'settings';
  static readonly CATEGORY_SEARCH_HISTORY: string = 'searchHistory';

  private static readonly SETTINGS_STORES: string[] = [
    'app_icon_settings',
    'app_theme_mode',
    'app_theme_settings',
    'bookshelf_display_settings',
    'cover_gallery_settings',
    'glass_settings',
    'reader_replace_rules',
    'reader_settings',
    'search_explore_settings',
    'tts_settings'
  ];

  private static readonly ASSET_DIRS: string[] = [
    'reader_fonts',
    'reader_backgrounds',
    'cover_albums',
    'covers'
  ];

  private static readonly PROGRESS_VARIABLE_KEYS: string[] = [
    'readStarted',
    'lastReadTime',
    'readProgressChapterIndex',
    'readProgressPageCount'
  ];

  static async createBackup(context: Context, selection: AppDataBackupSelection): Promise<AppDataBackupExportResult> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const root = `${context.tempDir}/app_backup_${Date.now()}`;
    const payloadRoot = `${root}/payload`;
    const archivePath = `${root}/legado_backup.zip`;
    await AppDataBackupService.ensureDir(payloadRoot);

    const manifest = new AppDataBackupManifest();
    manifest.createdAt = Date.now();
    manifest.sourceFilesDir = context.filesDir;

    if (selection.sources) {
      manifest.categories.push(AppDataBackupService.CATEGORY_SOURCES);
      manifest.sources = await db.getAllBookSources();
      manifest.sourceGroupPreferences = await AppDataBackupService.readPreferenceStore(context, 'book_source_groups');
    }

    const allBooks = await db.getAllBooks();
    if (selection.bookshelf || selection.localBooks) {
      manifest.bookGroups = await db.getCustomBookGroups();
    }
    if (selection.bookshelf) {
      manifest.categories.push(AppDataBackupService.CATEGORY_BOOKSHELF);
      manifest.books = allBooks.filter((book: Book): boolean => !LocalBookService.isLocalBook(book));
      manifest.bookshelfSortMode = AppStorage.get<string>('bookshelfSortMode') || 'recentRead';
    }

    if (selection.progress) {
      manifest.categories.push(AppDataBackupService.CATEGORY_PROGRESS);
      manifest.progress = allBooks.map((book: Book): BookProgressBackup => {
        const progress = new BookProgressBackup();
        progress.bookUrl = book.bookUrl;
        progress.durChapterTitle = book.durChapterTitle;
        progress.durChapterIndex = book.durChapterIndex;
        progress.durChapterPos = book.durChapterPos;
        progress.durChapterTime = book.durChapterTime;
        progress.variable = AppDataBackupService.progressVariables(book);
        return progress;
      });
    }

    if (selection.bookmarks) {
      manifest.categories.push(AppDataBackupService.CATEGORY_BOOKMARKS);
      manifest.bookmarks = await db.getAllBookmarks();
    }

    if (selection.localBooks) {
      manifest.categories.push(AppDataBackupService.CATEGORY_LOCAL_BOOKS);
      manifest.localBooks = allBooks.filter((book: Book): boolean => LocalBookService.isLocalBook(book));
      const localRoot = `${payloadRoot}/local_books`;
      await AppDataBackupService.ensureDir(localRoot);
      for (let index = 0; index < manifest.localBooks.length; index++) {
        const book = manifest.localBooks[index];
        const sourcePath = book.getVariable('localFilePath');
        if (!sourcePath || !AppDataBackupService.exists(sourcePath)) continue;
        const format = book.getVariable('localFormat') || (book.type === LocalBookService.TYPE_EPUB ? 'epub' : 'txt');
        const archiveName = `${index}.${format}`;
        await AppDataBackupService.copyFile(sourcePath, `${localRoot}/${archiveName}`);
        manifest.localFiles[book.bookUrl] = archiveName;
      }
    }

    if (selection.settings) {
      manifest.categories.push(AppDataBackupService.CATEGORY_SETTINGS);
      for (const storeName of AppDataBackupService.SETTINGS_STORES) {
        manifest.preferenceStores[storeName] = await AppDataBackupService.readPreferenceStore(context, storeName);
      }
      const assetsRoot = `${payloadRoot}/assets`;
      for (const dirName of AppDataBackupService.ASSET_DIRS) {
        const source = `${context.filesDir}/${dirName}`;
        if (AppDataBackupService.exists(source)) {
          await AppDataBackupService.copyDirectory(source, `${assetsRoot}/${dirName}`);
        }
      }
    }

    if (selection.searchHistory) {
      manifest.categories.push(AppDataBackupService.CATEGORY_SEARCH_HISTORY);
      manifest.searchKeywords = await db.getSearchKeywords();
    }

    await AppDataBackupService.writeText(`${payloadRoot}/manifest.json`, JSON.stringify(manifest));
    await zlib.compressFile(payloadRoot, archivePath, {});
    const result = new AppDataBackupExportResult();
    result.archivePath = archivePath;
    result.manifest = manifest;
    return result;
  }

  static async prepareImport(context: Context, sourceUri: string): Promise<AppDataBackupImportSession> {
    const root = `${context.tempDir}/app_backup_import_${Date.now()}`;
    const archivePath = `${root}/source.zip`;
    const outRoot = `${root}/out`;
    await AppDataBackupService.ensureDir(root);
    await AppDataBackupService.ensureDir(outRoot);
    await fs.copy(sourceUri, fileUri.getUriFromPath(archivePath));
    await zlib.decompressFile(archivePath, outRoot);
    const manifestPath = await AppDataBackupService.findFile(outRoot, 'manifest.json');
    if (!manifestPath) throw new Error('不是有效的 Legado Harmony 备份文件');
    const raw = await AppDataBackupService.readText(manifestPath);
    const manifest = JSON.parse(raw) as AppDataBackupManifest;
    if (manifest.format !== 'legado-harmony-backup' || manifest.version !== 1) {
      throw new Error('备份格式不支持或版本过新');
    }
    const session = new AppDataBackupImportSession();
    session.rootPath = AppDataBackupService.parentPath(manifestPath);
    session.manifest = manifest;
    return session;
  }

  static async importBackup(context: Context, session: AppDataBackupImportSession,
    selection: AppDataBackupSelection): Promise<AppDataBackupImportResult> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const manifest = session.manifest;
    const result = new AppDataBackupImportResult();

    if ((selection.bookshelf || selection.localBooks) && (manifest.bookGroups || []).length > 0) {
      for (const group of manifest.bookGroups) {
        await db.restoreBookGroup(group);
      }
    }

    if (selection.sources && AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_SOURCES)) {
      for (const raw of manifest.sources || []) {
        await db.restoreBookSource(raw);
        result.sources++;
      }
      if (manifest.sourceGroupPreferences) {
        await AppDataBackupService.restorePreferenceStore(context, 'book_source_groups',
          manifest.sourceGroupPreferences, manifest.sourceFilesDir);
      }
    }

    if (selection.bookshelf && AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_BOOKSHELF)) {
      for (const raw of manifest.books || []) {
        const book = AppDataBackupService.hydrateBook(raw, manifest.sourceFilesDir, context.filesDir);
        await AppDataBackupService.restoreBookWithoutUnexpectedProgress(db, book, selection.progress);
        result.books++;
      }
      AppStorage.setOrCreate('bookshelfSortMode', manifest.bookshelfSortMode || 'recentRead');
    }

    if (selection.localBooks && AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_LOCAL_BOOKS)) {
      const targetRoot = `${context.filesDir}/local_books`;
      await AppDataBackupService.ensureDir(targetRoot);
      for (const raw of manifest.localBooks || []) {
        const archiveName = (manifest.localFiles || {})[raw.bookUrl] || '';
        const archivePath = archiveName ? `${session.rootPath}/local_books/${archiveName}` : '';
        if (!archivePath || !AppDataBackupService.exists(archivePath)) continue;
        const book = AppDataBackupService.hydrateBook(raw, manifest.sourceFilesDir, context.filesDir);
        const id = book.bookUrl.startsWith('local://') ? book.bookUrl.substring('local://'.length) :
          `${Math.abs(AppDataBackupService.hashText(book.bookUrl))}`;
        const format = book.getVariable('localFormat') || (book.type === LocalBookService.TYPE_EPUB ? 'epub' : 'txt');
        const targetPath = `${targetRoot}/${id}.${format}`;
        await AppDataBackupService.copyFile(archivePath, targetPath);
        book.putVariable('localFilePath', targetPath);
        book.putVariable('localSourceUri', fileUri.getUriFromPath(targetPath));
        book.putVariable('localExtractRoot', '');
        book.putVariable('localParserVersion', '');
        await AppDataBackupService.restoreBookWithoutUnexpectedProgress(db, book, selection.progress);
        await LocalBookService.ensureLocalParserCurrent(context, book);
        result.localBooks++;
      }
    }

    if (selection.progress && AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_PROGRESS)) {
      for (const progress of manifest.progress || []) {
        const book = await db.getBook(progress.bookUrl);
        if (!book) continue;
        book.durChapterTitle = progress.durChapterTitle;
        book.durChapterIndex = progress.durChapterIndex;
        book.durChapterPos = progress.durChapterPos;
        book.durChapterTime = progress.durChapterTime;
        AppDataBackupService.applyProgressVariables(book, progress.variable);
        await db.updateBook(book);
        result.progress++;
      }
    }

    if (selection.bookmarks && AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_BOOKMARKS)) {
      for (const bookmark of manifest.bookmarks || []) {
        if (!await db.getBook(bookmark.bookUrl)) continue;
        await db.restoreBookmark(bookmark);
        result.bookmarks++;
      }
    }

    if (selection.settings && AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_SETTINGS)) {
      const assetsRoot = `${session.rootPath}/assets`;
      for (const dirName of AppDataBackupService.ASSET_DIRS) {
        const source = `${assetsRoot}/${dirName}`;
        if (AppDataBackupService.exists(source)) {
          await AppDataBackupService.copyDirectory(source, `${context.filesDir}/${dirName}`);
        }
      }
      const stores = manifest.preferenceStores || {};
      for (const storeName of Object.keys(stores)) {
        await AppDataBackupService.restorePreferenceStore(context, storeName, stores[storeName],
          manifest.sourceFilesDir);
        result.settings++;
      }
    }

    if (selection.searchHistory &&
      AppDataBackupService.hasCategory(manifest, AppDataBackupService.CATEGORY_SEARCH_HISTORY)) {
      for (const keyword of manifest.searchKeywords || []) {
        await db.restoreSearchKeyword(keyword);
        result.searchKeywords++;
      }
    }

    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    return result;
  }

  static hasCategory(manifest: AppDataBackupManifest, category: string): boolean {
    return (manifest.categories || []).includes(category);
  }

  private static async restoreBookWithoutUnexpectedProgress(db: AppDatabase, book: Book,
    importProgress: boolean): Promise<void> {
    if (!importProgress) {
      const existing = await db.getBook(book.bookUrl);
      AppDataBackupService.stripProgressVariables(book);
      if (existing) {
        book.durChapterTitle = existing.durChapterTitle;
        book.durChapterIndex = existing.durChapterIndex;
        book.durChapterPos = existing.durChapterPos;
        book.durChapterTime = existing.durChapterTime;
        AppDataBackupService.applyProgressVariables(book, AppDataBackupService.progressVariables(existing));
      } else {
        book.durChapterTitle = '';
        book.durChapterIndex = 0;
        book.durChapterPos = 0;
        book.durChapterTime = 0;
      }
    }
    await db.restoreBook(book);
  }

  private static hydrateBook(raw: Book, oldRoot: string, newRoot: string): Book {
    const book = new Book();
    book.bookUrl = raw.bookUrl || '';
    book.tocUrl = raw.tocUrl || '';
    book.origin = raw.origin || 'local';
    book.originName = raw.originName || '';
    book.name = raw.name || '';
    book.author = raw.author || '';
    book.kind = raw.kind || '';
    book.customTag = raw.customTag || '';
    book.coverUrl = AppDataBackupService.replaceRoot(raw.coverUrl || '', oldRoot, newRoot);
    book.customCoverUrl = AppDataBackupService.replaceRoot(raw.customCoverUrl || '', oldRoot, newRoot);
    book.intro = raw.intro || '';
    book.customIntro = raw.customIntro || '';
    book.charset = raw.charset || '';
    book.type = raw.type || 0;
    book.group = raw.group || 0;
    book.latestChapterTitle = raw.latestChapterTitle || '';
    book.latestChapterTime = raw.latestChapterTime || 0;
    book.lastCheckTime = raw.lastCheckTime || 0;
    book.lastCheckCount = raw.lastCheckCount || 0;
    book.totalChapterNum = raw.totalChapterNum || 0;
    book.durChapterTitle = raw.durChapterTitle || '';
    book.durChapterIndex = raw.durChapterIndex || 0;
    book.durChapterPos = raw.durChapterPos || 0;
    book.durChapterTime = raw.durChapterTime || 0;
    book.wordCount = raw.wordCount || '';
    book.canUpdate = raw.canUpdate !== false;
    book.order = raw.order || 0;
    book.originOrder = raw.originOrder || 0;
    book.replaceVariable(AppDataBackupService.replaceRoot(raw.variable || '{}', oldRoot, newRoot));
    if (raw.readConfig) {
      book.readConfig = JSON.parse(JSON.stringify(raw.readConfig)) as ReadConfig;
    }
    book.syncTime = raw.syncTime || 0;
    return book;
  }

  private static async readPreferenceStore(context: Context, storeName: string): Promise<string> {
    const store = await preferences.getPreferences(context, storeName);
    return JSON.stringify(await store.getAll());
  }

  private static async restorePreferenceStore(context: Context, storeName: string, raw: string,
    oldRoot: string): Promise<void> {
    const store = await preferences.getPreferences(context, storeName);
    const values = JSON.parse(AppDataBackupService.replaceRoot(raw || '{}', oldRoot, context.filesDir)) as
      Record<string, preferences.ValueType>;
    await store.clear();
    for (const key of Object.keys(values)) {
      await store.put(key, values[key]);
    }
    await store.flush();
  }

  private static replaceRoot(value: string, oldRoot: string, newRoot: string): string {
    if (!value || !oldRoot || oldRoot === newRoot) return value;
    return value.split(oldRoot).join(newRoot);
  }

  private static progressVariables(book: Book): string {
    const values: Record<string, string> = {};
    for (const key of AppDataBackupService.PROGRESS_VARIABLE_KEYS) {
      const value = book.getVariable(key);
      if (value) values[key] = value;
    }
    return JSON.stringify(values);
  }

  private static applyProgressVariables(book: Book, raw: string): void {
    let values: Record<string, string> = {};
    try {
      values = JSON.parse(raw || '{}') as Record<string, string>;
    } catch (_) {
      return;
    }
    for (const key of AppDataBackupService.PROGRESS_VARIABLE_KEYS) {
      const value = values[key];
      if (value !== undefined) book.putVariable(key, `${value}`);
    }
  }

  private static stripProgressVariables(book: Book): void {
    let source: Record<string, string> = {};
    try {
      source = JSON.parse(book.variable || '{}') as Record<string, string>;
    } catch (_) {
      source = {};
    }
    const clean: Record<string, string> = {};
    for (const key of Object.keys(source)) {
      if (!AppDataBackupService.PROGRESS_VARIABLE_KEYS.includes(key)) clean[key] = source[key];
    }
    book.replaceVariable(JSON.stringify(clean));
  }

  private static async copyDirectory(source: string, target: string): Promise<void> {
    await AppDataBackupService.ensureDir(target);
    const names = await fs.listFile(source);
    for (const name of names) {
      const sourcePath = `${source}/${name}`;
      const targetPath = `${target}/${name}`;
      const stat = await fs.stat(sourcePath);
      if (stat.isDirectory()) {
        await AppDataBackupService.copyDirectory(sourcePath, targetPath);
      } else {
        await AppDataBackupService.copyFile(sourcePath, targetPath);
      }
    }
  }

  private static async copyFile(source: string, target: string): Promise<void> {
    await AppDataBackupService.ensureDir(AppDataBackupService.parentPath(target));
    if (AppDataBackupService.exists(target)) {
      try { await fs.unlink(target); } catch (_) {}
    }
    const sourceUri = source.startsWith('/') ? fileUri.getUriFromPath(source) : source;
    await fs.copy(sourceUri, fileUri.getUriFromPath(target));
  }

  private static async writeText(path: string, value: string): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(value);
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
    } finally {
      await fs.close(file);
    }
  }

  private static async readText(path: string): Promise<string> {
    const stat = await fs.stat(path);
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer), { stream: false });
    } finally {
      await fs.close(file);
    }
  }

  private static async findFile(root: string, fileName: string): Promise<string> {
    const names = await fs.listFile(root);
    for (const name of names) {
      const path = `${root}/${name}`;
      const stat = await fs.stat(path);
      if (stat.isDirectory()) {
        const nested = await AppDataBackupService.findFile(path, fileName);
        if (nested) return nested;
      } else if (name === fileName) {
        return path;
      }
    }
    return '';
  }

  private static async ensureDir(path: string): Promise<void> {
    try { await fs.mkdir(path, true); } catch (_) {}
  }

  private static parentPath(path: string): string {
    const normalized = path.replace(/\\/g, '/');
    const index = normalized.lastIndexOf('/');
    return index > 0 ? normalized.substring(0, index) : normalized;
  }

  private static exists(path: string): boolean {
    try { return fs.accessSync(path); } catch (_) { return false; }
  }

  private static hashText(value: string): number {
    let hash = 0;
    for (let i = 0; i < value.length; i++) hash = (hash * 31 + value.charCodeAt(i)) | 0;
    return hash;
  }
}
