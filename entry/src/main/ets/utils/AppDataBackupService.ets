import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import zlib from '@ohos.zlib';
import util from '@ohos.util';
import preferences from '@ohos.data.preferences';
import { Context } from '@kit.AbilityKit';
import { statfs } from '@kit.CoreFileKit';
import { AppDatabase } from '../model/data/AppDatabase';
import {
  Book,
  BookGroup,
  Bookmark,
  BookSource,
  BookListRule,
  SearchRule,
  ExploreRule,
  BookInfoRule,
  TocRule,
  ContentRule,
  HttpTTS,
  ReadConfig,
  SearchKeyword
} from '../model/data/Book';
import { LocalBookService } from '../core/book/LocalBookService';
import { BackupCrypto } from './BackupCrypto';
import { BookSourceGroupStore } from './BookSourceGroupStore';
import { ReaderReplaceRule, ReaderReplaceRuleStore } from './ReaderReplaceRuleStore';
import { TtsSettingsStore } from './TtsSettingsStore';
import { BookshelfStateStore } from './BookshelfStateStore';

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
  version: number = 2;
  createdAt: number = 0;
  sensitiveDataExcluded: boolean = true;
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
  tempRootPath: string = '';
  rootPath: string = '';
  encrypted: boolean = false;
  sourceFormat: string = 'legado-harmony';
  manifest: AppDataBackupManifest = new AppDataBackupManifest();
}

export class AppDataBackupImportResult {
  sources: number = 0;
  books: number = 0;
  bookGroups: number = 0;
  localBooks: number = 0;
  progress: number = 0;
  bookmarks: number = 0;
  settings: number = 0;
  httpTts: number = 0;
  replaceRules: number = 0;
  searchKeywords: number = 0;
  skippedLocalBooks: number = 0;

  summary(): string {
    const parts: string[] = [];
    if (this.sources > 0) parts.push(`书源 ${this.sources}`);
    if (this.books > 0) parts.push(`书架 ${this.books}`);
    if (this.bookGroups > 0) parts.push(`分组 ${this.bookGroups}`);
    if (this.localBooks > 0) parts.push(`本地图书 ${this.localBooks}`);
    if (this.progress > 0) parts.push(`进度 ${this.progress}`);
    if (this.bookmarks > 0) parts.push(`书签 ${this.bookmarks}`);
    if (this.settings > 0) parts.push(`设置 ${this.settings}`);
    if (this.httpTts > 0) parts.push(`HTTP TTS ${this.httpTts}`);
    if (this.replaceRules > 0) parts.push(`替换规则 ${this.replaceRules}`);
    if (this.searchKeywords > 0) parts.push(`搜索记录 ${this.searchKeywords}`);
    if (this.skippedLocalBooks > 0) parts.push(`跳过本地书 ${this.skippedLocalBooks}`);
    return parts.length > 0 ? parts.join('、') : '没有可导入的数据';
  }
}

class AndroidBookGroupMapping {
  legacyIds: number[] = [];
  localIds: Map<number, number> = new Map<number, number>();
}

export class AppDataBackupService {
  static readonly PASSWORD_REQUIRED_MESSAGE: string = '备份已加密，请输入密码';
  static readonly SOURCE_FORMAT_HARMONY: string = 'legado-harmony';
  static readonly SOURCE_FORMAT_ANDROID: string = 'legado-android';
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
    'startup_cover_texts',
    'tts_settings',
    'webdav_settings'
  ];
  private static readonly READER_SETTINGS_STORE: string = 'reader_settings';
  private static readonly READER_THEME_PROFILE_PREFIX: string = 'readerThemeProfileV1_';

  private static readonly ASSET_DIRS: string[] = [
    'reader_fonts',
    'reader_backgrounds',
    'theme_startups',
    'cover_albums',
    'covers'
  ];

  private static readonly PROGRESS_VARIABLE_KEYS: string[] = [
    'readStarted',
    'lastReadTime',
    'readProgressChapterIndex',
    'readProgressPageCount'
  ];

  private static readonly ANDROID_SOURCE_FILE: string = 'bookSource.json';
  private static readonly ANDROID_BOOKSHELF_FILE: string = 'bookshelf.json';
  private static readonly ANDROID_BOOK_GROUP_FILE: string = 'bookGroup.json';
  private static readonly ANDROID_HTTP_TTS_FILE: string = 'httpTTS.json';
  private static readonly ANDROID_REPLACE_RULE_FILE: string = 'replaceRule.json';
  private static readonly ANDROID_SEARCH_HISTORY_FILE: string = 'searchHistory.json';
  private static readonly ANDROID_MAX_SOURCE_BYTES: number = 128 * 1024 * 1024;
  private static readonly ANDROID_MAX_DATA_BYTES: number = 32 * 1024 * 1024;

  static async createBackup(context: Context, selection: AppDataBackupSelection,
    password: string, onProgress?: (message: string, percent: number) => void):
    Promise<AppDataBackupExportResult> {
    const encryptionPassword = password || '';
    if (encryptionPassword && encryptionPassword.length < 8) {
      throw new Error('备份密码至少需要 8 个字符');
    }
    AppDataBackupService.reportProgress(onProgress, '正在读取应用数据...', 3);
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const root = `${context.tempDir}/app_backup_${Date.now()}`;
    const payloadRoot = `${root}/payload`;
    const innerArchivePath = `${root}/payload.zip`;
    const envelopeRoot = `${root}/encrypted`;
    const encryptedPayloadPath = `${envelopeRoot}/payload.bin`;
    // zlib.compressFile() produces a ZIP archive and requires a ZIP output
    // path on some HarmonyOS versions. The user-facing picker can still save
    // these bytes with the custom .qingyebak extension.
    const archivePath = `${root}/legado_backup.zip`;
    const manifest = new AppDataBackupManifest();
    manifest.createdAt = Date.now();
    manifest.sourceFilesDir = context.filesDir;
    let archiveReady = false;
    try {

    if (selection.sources) {
      manifest.categories.push(AppDataBackupService.CATEGORY_SOURCES);
      manifest.sources = (await db.getAllBookSources()).map((source: BookSource): BookSource =>
        AppDataBackupService.sanitizeBookSource(source));
      manifest.sourceGroupPreferences = await AppDataBackupService.readPreferenceStore(context, 'book_source_groups');
    }

    const allBooks = await db.getAllBooks();
    AppDataBackupService.reportProgress(onProgress, '正在检查可用空间...', 8);
    await AppDataBackupService.ensureEnoughTempSpace(context, selection, allBooks);
    await AppDataBackupService.ensureDir(payloadRoot);
    if (encryptionPassword) await AppDataBackupService.ensureDir(envelopeRoot);
    if (selection.bookshelf || selection.localBooks) {
      manifest.bookGroups = await db.getCustomBookGroups();
    }
    if (selection.bookshelf) {
      manifest.categories.push(AppDataBackupService.CATEGORY_BOOKSHELF);
      manifest.books = allBooks.filter((book: Book): boolean => !LocalBookService.isPhysicalLocalBook(book))
        .map((book: Book): Book => AppDataBackupService.sanitizeBook(book));
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
      AppDataBackupService.reportProgress(onProgress, '正在整理本地图书...', 22);
      manifest.categories.push(AppDataBackupService.CATEGORY_LOCAL_BOOKS);
      const localSourceBooks = allBooks.filter((book: Book): boolean => LocalBookService.isPhysicalLocalBook(book));
      manifest.localBooks = localSourceBooks
        .map((book: Book): Book => AppDataBackupService.sanitizeBook(book));
      const localRoot = `${payloadRoot}/local_books`;
      await AppDataBackupService.ensureDir(localRoot);
      for (let index = 0; index < manifest.localBooks.length; index++) {
        const book = localSourceBooks[index];
        const sourcePath = book.getVariable('localFilePath');
        if (!sourcePath || !AppDataBackupService.exists(sourcePath)) continue;
        const format = book.getVariable('localFormat') || (book.type === LocalBookService.TYPE_EPUB ? 'epub' : 'txt');
        const archiveName = `${index}.${format}`;
        await AppDataBackupService.copyFile(sourcePath, `${localRoot}/${archiveName}`);
        manifest.localFiles[book.bookUrl] = archiveName;
        const progress = manifest.localBooks.length > 0 ?
          22 + Math.floor((index + 1) * 13 / manifest.localBooks.length) : 35;
        AppDataBackupService.reportProgress(onProgress, '正在整理本地图书...', progress);
      }
    }

    if (selection.settings) {
      AppDataBackupService.reportProgress(onProgress, '正在整理设置和自定义资源...', 36);
      manifest.categories.push(AppDataBackupService.CATEGORY_SETTINGS);
      for (const storeName of AppDataBackupService.SETTINGS_STORES) {
        manifest.preferenceStores[storeName] = AppDataBackupService.sanitizeStructuredText(
          await AppDataBackupService.readPreferenceStore(context, storeName));
      }
      const assetsRoot = `${payloadRoot}/assets`;
      for (let index = 0; index < AppDataBackupService.ASSET_DIRS.length; index++) {
        const dirName = AppDataBackupService.ASSET_DIRS[index];
        const source = `${context.filesDir}/${dirName}`;
        if (AppDataBackupService.exists(source)) {
          await AppDataBackupService.copyDirectory(source, `${assetsRoot}/${dirName}`);
        }
        AppDataBackupService.reportProgress(onProgress, '正在整理设置和自定义资源...',
          36 + Math.floor((index + 1) * 9 / AppDataBackupService.ASSET_DIRS.length));
      }
    }

    if (selection.searchHistory) {
      manifest.categories.push(AppDataBackupService.CATEGORY_SEARCH_HISTORY);
      manifest.searchKeywords = await db.getSearchKeywords();
    }

      AppDataBackupService.reportProgress(onProgress, '正在生成备份清单...', 48);
      await AppDataBackupService.writeText(`${payloadRoot}/manifest.json`, JSON.stringify(manifest));
      AppDataBackupService.reportProgress(onProgress, '正在压缩备份数据...', 52);
      try {
        await zlib.compressFile(payloadRoot, innerArchivePath,
          { level: zlib.CompressLevel.COMPRESS_LEVEL_BEST_SPEED });
      } catch (error) {
        throw new Error(`压缩备份数据失败：${error instanceof Error ? error.message : String(error)}`);
      }
      await AppDataBackupService.removeDirectory(payloadRoot);
      if (encryptionPassword) {
        AppDataBackupService.reportProgress(onProgress, '正在加密备份...', 68);
        const encryption = await BackupCrypto.encryptFile(innerArchivePath, encryptedPayloadPath,
          encryptionPassword, (processed: number, total: number): void => {
            const ratio = total > 0 ? processed / total : 1;
            AppDataBackupService.reportProgress(onProgress, '正在加密备份...',
              68 + Math.min(17, Math.floor(ratio * 17)));
          });
        AppDataBackupService.reportProgress(onProgress, '加密完成，正在清理中间文件...', 86);
        await AppDataBackupService.removeFile(innerArchivePath);
        await AppDataBackupService.writeText(`${envelopeRoot}/encryption.json`, JSON.stringify(encryption));
        AppDataBackupService.reportProgress(onProgress, '正在封装备份文件...', 88);
        try {
          await zlib.compressFile(envelopeRoot, archivePath,
            { level: zlib.CompressLevel.COMPRESS_LEVEL_NO_COMPRESSION });
          const archiveStat = await fs.stat(archivePath);
          if (archiveStat.size <= 0) throw new Error('生成的归档文件为空');
        } catch (error) {
          throw new Error(`封装备份文件失败：${error instanceof Error ? error.message : String(error)}`);
        }
        await AppDataBackupService.removeDirectory(envelopeRoot);
      } else {
        AppDataBackupService.reportProgress(onProgress, '正在生成未加密备份...', 82);
        await AppDataBackupService.copyFile(innerArchivePath, archivePath);
        await AppDataBackupService.removeFile(innerArchivePath);
        const archiveStat = await fs.stat(archivePath);
        if (archiveStat.size <= 0) throw new Error('生成的归档文件为空');
      }
      archiveReady = true;
      AppDataBackupService.reportProgress(onProgress, '备份文件已生成', 96);
    } finally {
      await AppDataBackupService.removeDirectory(payloadRoot);
      await AppDataBackupService.removeFile(innerArchivePath);
      await AppDataBackupService.removeDirectory(envelopeRoot);
      if (!archiveReady) await AppDataBackupService.removeFile(archivePath);
    }
    const result = new AppDataBackupExportResult();
    result.archivePath = archivePath;
    result.manifest = manifest;
    return result;
  }

  static async cleanupStaleTempFiles(context: Context): Promise<void> {
    const staleBeforeSeconds = Math.floor(Date.now() / 1000) - 24 * 60 * 60;
    let names: string[] = [];
    try {
      names = await fs.listFile(context.tempDir);
    } catch (_) {
      return;
    }
    for (const name of names) {
      if (!name.startsWith('app_backup_')) continue;
      const path = `${context.tempDir}/${name}`;
      try {
        const stat = await fs.stat(path);
        // A system picker can temporarily background and recreate the page.
        // Keep active/recent exports; only remove leftovers older than one day.
        if (stat.mtime >= staleBeforeSeconds) continue;
        if (stat.isDirectory()) await AppDataBackupService.removeDirectory(path);
        else await AppDataBackupService.removeFile(path);
      } catch (_) {}
    }
  }

  static async prepareImport(context: Context, sourceUri: string, password: string = '',
    onProgress?: (message: string, percent: number) => void): Promise<AppDataBackupImportSession> {
    const root = `${context.tempDir}/app_backup_import_${Date.now()}`;
    const archivePath = `${root}/source.zip`;
    const outRoot = `${root}/out`;
    AppDataBackupService.reportProgress(onProgress, '正在准备导入空间...', 3);
    await AppDataBackupService.ensureDir(root);
    await AppDataBackupService.ensureDir(outRoot);
    try {
      AppDataBackupService.reportProgress(onProgress, '正在复制备份文件...', 8);
      await AppDataBackupService.copyFile(sourceUri, archivePath);
      AppDataBackupService.reportProgress(onProgress, '正在解包备份文件...', 20);
      await zlib.decompressFile(archivePath, outRoot);
      AppDataBackupService.reportProgress(onProgress, '正在检查备份结构...', 42);
      const encryptionPath = await AppDataBackupService.findFile(outRoot, 'encryption.json');
      let manifestSearchRoot = outRoot;
      if (encryptionPath) {
        if (!password) throw new Error(AppDataBackupService.PASSWORD_REQUIRED_MESSAGE);
        AppDataBackupService.reportProgress(onProgress, '正在校验备份密码...', 46);
        const metadata = BackupCrypto.parseMetadata(await AppDataBackupService.readText(encryptionPath));
        const envelopeRoot = AppDataBackupService.parentPath(encryptionPath);
        const encryptedPayload = `${envelopeRoot}/${metadata.payloadFile}`;
        if (!AppDataBackupService.exists(encryptedPayload)) throw new Error('加密备份载荷不存在');
        const decryptedArchive = `${root}/decrypted.zip`;
        const decryptedRoot = `${root}/decrypted`;
        await AppDataBackupService.ensureDir(decryptedRoot);
        await BackupCrypto.decryptFile(encryptedPayload, decryptedArchive, password, metadata,
          (processed: number, total: number): void => {
            const ratio = total > 0 ? processed / total : 1;
            AppDataBackupService.reportProgress(onProgress, '正在解密备份数据...',
              48 + Math.min(30, Math.floor(ratio * 30)));
          });
        try {
          AppDataBackupService.reportProgress(onProgress, '正在解包应用数据...', 80);
          await zlib.decompressFile(decryptedArchive, decryptedRoot);
          AppDataBackupService.reportProgress(onProgress, '应用数据解包完成', 94);
        } finally {
          await AppDataBackupService.removeFile(decryptedArchive);
        }
        manifestSearchRoot = decryptedRoot;
      } else {
        AppDataBackupService.reportProgress(onProgress, '备份数据解包完成', 90);
      }
      AppDataBackupService.reportProgress(onProgress, '正在读取备份清单...', 96);
      const manifestPath = await AppDataBackupService.findFile(manifestSearchRoot, 'manifest.json');
      if (!manifestPath) {
        const androidManifest = await AppDataBackupService.prepareAndroidManifest(manifestSearchRoot);
        if (!androidManifest) {
          throw new Error('不是有效的 Legado Harmony 或 Android 阅读备份文件');
        }
        const androidSession = new AppDataBackupImportSession();
        androidSession.tempRootPath = root;
        androidSession.rootPath = manifestSearchRoot;
        androidSession.encrypted = false;
        androidSession.sourceFormat = AppDataBackupService.SOURCE_FORMAT_ANDROID;
        androidSession.manifest = androidManifest;
        AppDataBackupService.reportProgress(onProgress, 'Android 阅读备份识别完成', 100);
        return androidSession;
      }
      const raw = await AppDataBackupService.readText(manifestPath);
      const manifest = JSON.parse(raw) as AppDataBackupManifest;
      if (manifest.format !== 'legado-harmony-backup' ||
        (manifest.version !== 1 && manifest.version !== 2)) {
        throw new Error('备份格式不支持或版本过新');
      }
      const session = new AppDataBackupImportSession();
      session.tempRootPath = root;
      session.rootPath = AppDataBackupService.parentPath(manifestPath);
      session.encrypted = !!encryptionPath;
      session.sourceFormat = AppDataBackupService.SOURCE_FORMAT_HARMONY;
      session.manifest = manifest;
      AppDataBackupService.reportProgress(onProgress, '备份文件读取完成', 100);
      return session;
    } catch (error) {
      await AppDataBackupService.removeDirectory(root);
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  static async discardExport(archivePath: string): Promise<void> {
    if (!archivePath) return;
    await AppDataBackupService.removeDirectory(AppDataBackupService.parentPath(archivePath));
  }

  static async discardImport(session: AppDataBackupImportSession | null): Promise<void> {
    if (!session || !session.tempRootPath) return;
    await AppDataBackupService.removeDirectory(session.tempRootPath);
    session.tempRootPath = '';
  }

  static async importBackup(context: Context, session: AppDataBackupImportSession,
    selection: AppDataBackupSelection, onProgress?: (message: string, percent: number) => void):
    Promise<AppDataBackupImportResult> {
    if (session.sourceFormat === AppDataBackupService.SOURCE_FORMAT_ANDROID) {
      return AppDataBackupService.importAndroidBackup(context, session, selection, onProgress);
    }
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const manifest = session.manifest;
    const result = new AppDataBackupImportResult();

    if ((selection.bookshelf || selection.localBooks) && (manifest.bookGroups || []).length > 0) {
      for (const group of manifest.bookGroups) {
        await db.restoreBookGroup(group);
        result.bookGroups++;
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
      const restoredSortMode = BookshelfStateStore.normalizeSortMode(manifest.bookshelfSortMode);
      AppStorage.setOrCreate('bookshelfSortMode', restoredSortMode);
      await BookshelfStateStore.saveSortMode(context, restoredSortMode);
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

  private static async prepareAndroidManifest(root: string): Promise<AppDataBackupManifest | null> {
    const sourcePath = await AppDataBackupService.findFile(root, AppDataBackupService.ANDROID_SOURCE_FILE);
    const bookshelfPath = await AppDataBackupService.findFile(root, AppDataBackupService.ANDROID_BOOKSHELF_FILE);
    const groupPath = await AppDataBackupService.findFile(root, AppDataBackupService.ANDROID_BOOK_GROUP_FILE);
    const httpTtsPath = await AppDataBackupService.findFile(root, AppDataBackupService.ANDROID_HTTP_TTS_FILE);
    const replaceRulePath = await AppDataBackupService.findFile(root, AppDataBackupService.ANDROID_REPLACE_RULE_FILE);
    const searchHistoryPath = await AppDataBackupService.findFile(
      root, AppDataBackupService.ANDROID_SEARCH_HISTORY_FILE);
    if (!sourcePath && !bookshelfPath && !groupPath && !httpTtsPath && !replaceRulePath && !searchHistoryPath) {
      return null;
    }
    const manifest = new AppDataBackupManifest();
    manifest.format = 'legado-android-backup';
    manifest.version = 1;
    manifest.createdAt = Date.now();
    manifest.sensitiveDataExcluded = false;
    if (sourcePath) manifest.categories.push(AppDataBackupService.CATEGORY_SOURCES);
    if (bookshelfPath || groupPath) manifest.categories.push(AppDataBackupService.CATEGORY_BOOKSHELF);
    if (bookshelfPath) manifest.categories.push(AppDataBackupService.CATEGORY_PROGRESS);
    if (httpTtsPath || replaceRulePath) manifest.categories.push(AppDataBackupService.CATEGORY_SETTINGS);
    if (searchHistoryPath) manifest.categories.push(AppDataBackupService.CATEGORY_SEARCH_HISTORY);
    return manifest;
  }

  private static async importAndroidBackup(context: Context, session: AppDataBackupImportSession,
    selection: AppDataBackupSelection, onProgress?: (message: string, percent: number) => void):
    Promise<AppDataBackupImportResult> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const result = new AppDataBackupImportResult();
    let groupMapping = new AndroidBookGroupMapping();
    AppDataBackupService.reportProgress(onProgress, '正在准备 Android 阅读备份...', 2);

    if (selection.bookshelf &&
      AppDataBackupService.hasCategory(session.manifest, AppDataBackupService.CATEGORY_BOOKSHELF)) {
      groupMapping = await AppDataBackupService.importAndroidBookGroups(db, session.rootPath, result);
    }

    if (selection.sources &&
      AppDataBackupService.hasCategory(session.manifest, AppDataBackupService.CATEGORY_SOURCES)) {
      AppDataBackupService.reportProgress(onProgress, '正在导入 Android 书源...', 10);
      await AppDataBackupService.forEachAndroidJsonArray(session.rootPath,
        AppDataBackupService.ANDROID_SOURCE_FILE, AppDataBackupService.ANDROID_MAX_SOURCE_BYTES,
        async (raw: Record<string, Object>, index: number, offset: number, total: number): Promise<void> => {
          const source = AppDataBackupService.convertAndroidBookSource(raw);
          if (!source.bookSourceUrl || !source.bookSourceName) return;
          await db.restoreBookSource(source);
          result.sources++;
          if (index % 100 === 0) {
            AppDataBackupService.reportProgress(onProgress, '正在导入 Android 书源...',
              10 + Math.floor(offset * 42 / Math.max(1, total)));
          }
        });
      const summaries = await db.getBookSourceSummaries();
      const sourceGroups: string[] = [];
      for (const source of summaries) {
        const group = (source.bookSourceGroup || '').trim();
        if (group && !sourceGroups.includes(group)) sourceGroups.push(group);
      }
      await BookSourceGroupStore.load(context, sourceGroups);
    }

    if ((selection.bookshelf || selection.progress) &&
      await AppDataBackupService.findFile(session.rootPath, AppDataBackupService.ANDROID_BOOKSHELF_FILE)) {
      AppDataBackupService.reportProgress(onProgress, '正在导入网络书架和阅读进度...', 55);
      await AppDataBackupService.forEachAndroidJsonArray(session.rootPath,
        AppDataBackupService.ANDROID_BOOKSHELF_FILE, AppDataBackupService.ANDROID_MAX_DATA_BYTES,
        async (raw: Record<string, Object>, index: number, offset: number, total: number): Promise<void> => {
          if (AppDataBackupService.isAndroidLocalBook(raw)) {
            result.skippedLocalBooks++;
            return;
          }
          const book = AppDataBackupService.convertAndroidBook(raw, groupMapping);
          if (!book.bookUrl) return;
          if (selection.bookshelf) {
            await AppDataBackupService.restoreBookWithoutUnexpectedProgress(db, book, selection.progress);
            result.books++;
            if (selection.progress) result.progress++;
          } else if (selection.progress) {
            const existing = await db.getBook(book.bookUrl);
            if (existing) {
              existing.durChapterTitle = book.durChapterTitle;
              existing.durChapterIndex = book.durChapterIndex;
              existing.durChapterPos = book.durChapterPos;
              existing.durChapterTime = book.durChapterTime;
              AppDataBackupService.applyProgressVariables(existing,
                AppDataBackupService.progressVariables(book));
              await db.updateBook(existing);
              result.progress++;
            }
          }
          if (index % 25 === 0) {
            AppDataBackupService.reportProgress(onProgress, '正在导入网络书架和阅读进度...',
              55 + Math.floor(offset * 20 / Math.max(1, total)));
          }
        });
    }

    if (selection.settings &&
      AppDataBackupService.hasCategory(session.manifest, AppDataBackupService.CATEGORY_SETTINGS)) {
      AppDataBackupService.reportProgress(onProgress, '正在导入 HTTP TTS 和替换规则...', 78);
      result.httpTts = await AppDataBackupService.importAndroidHttpTts(context, session.rootPath);
      result.replaceRules = await AppDataBackupService.importAndroidReplaceRules(context, session.rootPath);
    }

    if (selection.searchHistory &&
      AppDataBackupService.hasCategory(session.manifest, AppDataBackupService.CATEGORY_SEARCH_HISTORY)) {
      AppDataBackupService.reportProgress(onProgress, '正在导入搜索历史...', 92);
      await AppDataBackupService.forEachAndroidJsonArray(session.rootPath,
        AppDataBackupService.ANDROID_SEARCH_HISTORY_FILE, AppDataBackupService.ANDROID_MAX_DATA_BYTES,
        async (raw: Record<string, Object>, _index: number, _offset: number, _total: number): Promise<void> => {
          const keyword = new SearchKeyword();
          keyword.keyword = AppDataBackupService.stringValue(raw['word'] || raw['keyword']);
          keyword.usage = AppDataBackupService.numberValue(raw['usage'], 0);
          keyword.lastUseTime = AppDataBackupService.numberValue(raw['lastUseTime'], 0);
          if (!keyword.keyword) return;
          await db.restoreSearchKeyword(keyword);
          result.searchKeywords++;
        });
    }

    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    AppDataBackupService.reportProgress(onProgress, 'Android 阅读备份导入完成', 100);
    return result;
  }

  private static async importAndroidBookGroups(db: AppDatabase, root: string,
    result: AppDataBackupImportResult): Promise<AndroidBookGroupMapping> {
    const mapping = new AndroidBookGroupMapping();
    const existing = await db.getCustomBookGroups();
    await AppDataBackupService.forEachAndroidJsonArray(root,
      AppDataBackupService.ANDROID_BOOK_GROUP_FILE, AppDataBackupService.ANDROID_MAX_DATA_BYTES,
      async (raw: Record<string, Object>, _index: number, _offset: number, _total: number): Promise<void> => {
        const legacyId = AppDataBackupService.numberValue(raw['groupId'], 0);
        const name = AppDataBackupService.stringValue(raw['groupName']).trim();
        if (legacyId <= 0 || !name) return;
        if (!mapping.legacyIds.includes(legacyId)) mapping.legacyIds.push(legacyId);
        let created = false;
        let target = existing.find((item: BookGroup): boolean => item.groupName === name) || null;
        if (!target) {
          target = await db.addBookGroup(name);
          if (target) {
            existing.push(target);
            created = true;
          }
        }
        if (!target) return;
        const resolved = target as BookGroup;
        if (created) {
          resolved.order = AppDataBackupService.numberValue(raw['order'], resolved.order);
          resolved.show = raw['show'] !== false;
          resolved.enableRefresh = raw['enableRefresh'] !== false;
          await db.restoreBookGroup(resolved);
        }
        mapping.localIds.set(legacyId, resolved.groupId);
        result.bookGroups++;
      });
    mapping.legacyIds.sort((left: number, right: number): number => left - right);
    return mapping;
  }

  private static async importAndroidHttpTts(context: Context, root: string): Promise<number> {
    const path = await AppDataBackupService.findFile(root, AppDataBackupService.ANDROID_HTTP_TTS_FILE);
    if (!path) return 0;
    const incoming: HttpTTS[] = [];
    await AppDataBackupService.forEachAndroidJsonArray(root, AppDataBackupService.ANDROID_HTTP_TTS_FILE,
      AppDataBackupService.ANDROID_MAX_DATA_BYTES,
      async (raw: Record<string, Object>, _index: number, _offset: number, _total: number): Promise<void> => {
        const voice = AppDataBackupService.convertAndroidHttpTts(raw);
        if (voice.name && voice.url) incoming.push(voice);
      });
    if (incoming.length === 0) return 0;
    const settings = await TtsSettingsStore.load(context);
    const merged = AppDataBackupService.parseHttpTtsArray(settings.customVoices);
    for (const voice of incoming) {
      let targetIndex = merged.findIndex((item: HttpTTS): boolean =>
        (item.id === voice.id && (item.url || '') === (voice.url || '')) ||
        ((item.name || '') === (voice.name || '') && (item.url || '') === (voice.url || '')));
      if (targetIndex < 0 && merged.some((item: HttpTTS): boolean => item.id === voice.id)) {
        let nextId = Math.max(Date.now(), voice.id + 1);
        while (merged.some((item: HttpTTS): boolean => item.id === nextId)) nextId++;
        voice.id = nextId;
      }
      targetIndex = merged.findIndex((item: HttpTTS): boolean => item.id === voice.id ||
        ((item.name || '') === (voice.name || '') && (item.url || '') === (voice.url || '')));
      if (targetIndex >= 0) merged[targetIndex] = voice;
      else merged.push(voice);
    }
    settings.customVoices = JSON.stringify(merged);
    await TtsSettingsStore.save(context, settings);
    return incoming.length;
  }

  private static async importAndroidReplaceRules(context: Context, root: string): Promise<number> {
    const path = await AppDataBackupService.findFile(root, AppDataBackupService.ANDROID_REPLACE_RULE_FILE);
    if (!path) return 0;
    const incoming: ReaderReplaceRule[] = [];
    await AppDataBackupService.forEachAndroidJsonArray(root, AppDataBackupService.ANDROID_REPLACE_RULE_FILE,
      AppDataBackupService.ANDROID_MAX_DATA_BYTES,
      async (raw: Record<string, Object>, index: number, _offset: number, _total: number): Promise<void> => {
        const rule = AppDataBackupService.convertAndroidReplaceRule(raw, index);
        if (rule.pattern) incoming.push(rule);
      });
    if (incoming.length === 0) return 0;
    const merged = await ReaderReplaceRuleStore.load(context, true);
    for (const rule of incoming) {
      let targetIndex = merged.findIndex((item: ReaderReplaceRule): boolean => item.id === rule.id ||
        (item.name === rule.name && item.pattern === rule.pattern && item.scope === rule.scope));
      if (targetIndex >= 0) merged[targetIndex] = rule;
      else merged.push(rule);
    }
    await ReaderReplaceRuleStore.save(context, merged);
    return incoming.length;
  }

  static hasCategory(manifest: AppDataBackupManifest, category: string): boolean {
    return (manifest.categories || []).includes(category);
  }

  private static convertAndroidBookSource(raw: Record<string, Object>): BookSource {
    const source = new BookSource();
    source.bookSourceUrl = AppDataBackupService.stringValue(raw['bookSourceUrl']);
    source.bookSourceName = AppDataBackupService.stringValue(raw['bookSourceName']);
    source.bookSourceType = AppDataBackupService.numberValue(raw['bookSourceType'], 0);
    source.bookSourceGroup = AppDataBackupService.stringValue(raw['bookSourceGroup']);
    source.bookSourceComment = AppDataBackupService.stringValue(raw['bookSourceComment']);
    source.loginUrl = AppDataBackupService.stringValue(raw['loginUrl']);
    source.loginUi = AppDataBackupService.stringValue(raw['loginUi']);
    source.loginCheckJs = AppDataBackupService.stringValue(raw['loginCheckJs']);
    source.loginHeader = AppDataBackupService.stringValue(raw['loginHeader']);
    source.loginInfo = AppDataBackupService.stringValue(raw['loginInfo']);
    // Android 书源的可运行字段已经逐项转换并存入专用列。保留完整原始对象会让同一份
    // 规则在数据库中至少保存两次；面对上万书源时，后续列表/同步会产生很高的内存峰值。
    // rawSourceJson 只用于书源管理页的回导出，那里会从专用列重建已支持的字段，因此不在
    // 跨端导入时重复保存未知字段。
    source.rawSourceJson = '';
    source.bookUrlPattern = AppDataBackupService.stringValue(raw['bookUrlPattern']);
    source.searchUrl = AppDataBackupService.stringValue(raw['searchUrl']);
    source.exploreUrl = AppDataBackupService.stringValue(raw['exploreUrl']);
    source.jsLib = AppDataBackupService.stringValue(raw['jsLib']);
    source.header = AppDataBackupService.stringValue(raw['header']);
    source.variableComment = AppDataBackupService.stringValue(raw['variableComment']);
    source.variable = AppDataBackupService.stringValue(raw['variable']);
    source.lastUpdateTime = AppDataBackupService.numberValue(raw['lastUpdateTime'], Date.now());
    source.respondTime = AppDataBackupService.numberValue(raw['respondTime'], 180000);
    source.customOrder = AppDataBackupService.numberValue(raw['customOrder'], 0);
    source.customButton = raw['customButton'] === true;
    source.eventListener = raw['eventListener'] === true;
    source.isPinned = raw['isPinned'] === true;
    source.enabled = raw['enabled'] !== false;
    source.enabledExplore = raw['enabledExplore'] !== false;
    source.isLocked = raw['isLocked'] === true || raw['locked'] === true;
    source.weight = AppDataBackupService.numberValue(raw['weight'], 0);
    source.concurrentRate = AppDataBackupService.stringValue(raw['concurrentRate']);
    source.enabledCookieJar = raw['enabledCookieJar'] !== false;
    source.bookListRule = AppDataBackupService.convertAndroidBookListRule(
      raw['ruleBookList'] || raw['bookListRule']);
    source.searchRule = AppDataBackupService.convertAndroidSearchRule(
      raw['ruleSearch'] || raw['searchRule']);
    source.exploreRule = AppDataBackupService.convertAndroidExploreRule(
      raw['ruleExplore'] || raw['exploreRule']);
    source.bookInfoRule = AppDataBackupService.convertAndroidBookInfoRule(
      raw['ruleBookInfo'] || raw['bookInfoRule']);
    source.tocRule = AppDataBackupService.convertAndroidTocRule(raw['ruleToc'] || raw['tocRule']);
    source.contentRule = AppDataBackupService.convertAndroidContentRule(
      raw['ruleContent'] || raw['contentRule']);
    return source;
  }

  private static convertAndroidBookListRule(value: Object | undefined): BookListRule {
    const raw = AppDataBackupService.ruleRecord(value);
    const rule = new BookListRule();
    if (!raw) return rule;
    rule.bookList = AppDataBackupService.ruleString(raw, 'bookList');
    rule.name = AppDataBackupService.ruleString(raw, 'name');
    rule.author = AppDataBackupService.ruleString(raw, 'author');
    rule.coverUrl = AppDataBackupService.ruleString(raw, 'coverUrl');
    rule.intro = AppDataBackupService.ruleString(raw, 'intro', 'desc');
    rule.kind = AppDataBackupService.ruleString(raw, 'kind');
    rule.status = AppDataBackupService.ruleString(raw, 'status');
    rule.lastChapter = AppDataBackupService.ruleString(raw, 'lastChapter', 'lastchapter');
    rule.bookUrl = AppDataBackupService.ruleString(raw, 'bookUrl', 'bookurl');
    rule.wordCount = AppDataBackupService.ruleString(raw, 'wordCount', 'wordcount');
    rule.updateTime = AppDataBackupService.ruleString(raw, 'updateTime', 'updatetime');
    return rule;
  }

  private static convertAndroidSearchRule(value: Object | undefined): SearchRule {
    const raw = AppDataBackupService.ruleRecord(value);
    const rule = new SearchRule();
    if (!raw) return rule;
    rule.bookList = AppDataBackupService.ruleString(raw, 'bookList');
    rule.name = AppDataBackupService.ruleString(raw, 'name');
    rule.author = AppDataBackupService.ruleString(raw, 'author');
    rule.coverUrl = AppDataBackupService.ruleString(raw, 'coverUrl');
    rule.intro = AppDataBackupService.ruleString(raw, 'intro', 'desc');
    rule.kind = AppDataBackupService.ruleString(raw, 'kind');
    rule.status = AppDataBackupService.ruleString(raw, 'status');
    rule.lastChapter = AppDataBackupService.ruleString(raw, 'lastChapter', 'lastchapter');
    rule.bookUrl = AppDataBackupService.ruleString(raw, 'bookUrl', 'bookurl');
    rule.wordCount = AppDataBackupService.ruleString(raw, 'wordCount', 'wordcount');
    rule.updateTime = AppDataBackupService.ruleString(raw, 'updateTime', 'updatetime');
    return rule;
  }

  private static convertAndroidExploreRule(value: Object | undefined): ExploreRule {
    const raw = AppDataBackupService.ruleRecord(value);
    const rule = new ExploreRule();
    if (!raw) return rule;
    rule.bookList = AppDataBackupService.ruleString(raw, 'bookList');
    rule.name = AppDataBackupService.ruleString(raw, 'name');
    rule.author = AppDataBackupService.ruleString(raw, 'author');
    rule.coverUrl = AppDataBackupService.ruleString(raw, 'coverUrl');
    rule.intro = AppDataBackupService.ruleString(raw, 'intro', 'desc');
    rule.kind = AppDataBackupService.ruleString(raw, 'kind');
    rule.status = AppDataBackupService.ruleString(raw, 'status');
    rule.lastChapter = AppDataBackupService.ruleString(raw, 'lastChapter', 'lastchapter');
    rule.bookUrl = AppDataBackupService.ruleString(raw, 'bookUrl', 'bookurl');
    rule.wordCount = AppDataBackupService.ruleString(raw, 'wordCount', 'wordcount');
    rule.updateTime = AppDataBackupService.ruleString(raw, 'updateTime', 'updatetime');
    return rule;
  }

  private static convertAndroidBookInfoRule(value: Object | undefined): BookInfoRule {
    const raw = AppDataBackupService.ruleRecord(value);
    const rule = new BookInfoRule();
    if (!raw) return rule;
    rule.init = AppDataBackupService.ruleString(raw, 'init');
    rule.name = AppDataBackupService.ruleString(raw, 'name');
    rule.author = AppDataBackupService.ruleString(raw, 'author');
    rule.coverUrl = AppDataBackupService.ruleString(raw, 'coverUrl');
    rule.intro = AppDataBackupService.ruleString(raw, 'intro', 'desc');
    rule.kind = AppDataBackupService.ruleString(raw, 'kind');
    rule.status = AppDataBackupService.ruleString(raw, 'status');
    rule.lastChapter = AppDataBackupService.ruleString(raw, 'lastChapter', 'lastchapter');
    rule.wordCount = AppDataBackupService.ruleString(raw, 'wordCount', 'wordcount');
    rule.updateTime = AppDataBackupService.ruleString(raw, 'updateTime', 'updatetime');
    rule.tocUrl = AppDataBackupService.ruleString(raw, 'tocUrl', 'tocurl');
    return rule;
  }

  private static convertAndroidTocRule(value: Object | undefined): TocRule {
    const raw = AppDataBackupService.ruleRecord(value);
    const rule = new TocRule();
    if (!raw) return rule;
    rule.chapterList = AppDataBackupService.ruleString(raw, 'chapterList', 'chapterlist');
    rule.chapterName = AppDataBackupService.ruleString(raw, 'chapterName', 'chaptername');
    rule.chapterUrl = AppDataBackupService.ruleString(raw, 'chapterUrl', 'chapterurl');
    rule.nextTocUrl = AppDataBackupService.ruleString(raw, 'nextTocUrl', 'nexttocurl');
    rule.isVip = AppDataBackupService.ruleString(raw, 'isVip', 'isvip');
    rule.isPay = AppDataBackupService.ruleString(raw, 'isPay', 'ispay');
    rule.updateTime = AppDataBackupService.ruleString(raw, 'updateTime', 'updatetime');
    rule.chapterListAddition = AppDataBackupService.ruleString(raw, 'chapterListAddition');
    return rule;
  }

  private static convertAndroidContentRule(value: Object | undefined): ContentRule {
    const raw = AppDataBackupService.ruleRecord(value);
    const rule = new ContentRule();
    if (!raw) return rule;
    rule.content = AppDataBackupService.ruleString(raw, 'content');
    rule.title = AppDataBackupService.ruleString(raw, 'title');
    rule.images = AppDataBackupService.ruleString(raw, 'images');
    rule.nextContentUrl = AppDataBackupService.ruleString(raw, 'nextContentUrl', 'nextcontenturl');
    rule.replaceRegex = AppDataBackupService.ruleString(raw, 'replaceRegex', 'replaceregex');
    rule.imageDecode = AppDataBackupService.ruleString(raw, 'imageDecode', 'imagedecode');
    rule.imageStyle = AppDataBackupService.ruleString(raw, 'imageStyle', 'imagestyle');
    rule.payAction = AppDataBackupService.ruleString(raw, 'payAction', 'payaction');
    return rule;
  }

  private static convertAndroidBook(raw: Record<string, Object>, mapping: AndroidBookGroupMapping): Book {
    const book = new Book();
    book.bookUrl = AppDataBackupService.limitedStringValue(raw['bookUrl'], 16384);
    book.tocUrl = AppDataBackupService.limitedStringValue(raw['tocUrl'], 16384);
    book.origin = AppDataBackupService.limitedStringValue(raw['origin'], 4096);
    book.originName = AppDataBackupService.limitedStringValue(raw['originName'], 512);
    book.name = AppDataBackupService.limitedStringValue(raw['name'], 1024);
    book.author = AppDataBackupService.limitedStringValue(raw['author'], 1024);
    book.kind = AppDataBackupService.limitedStringValue(raw['kind'], 4096);
    book.status = AppDataBackupService.limitedStringValue(raw['status'], 4096);
    book.customTag = AppDataBackupService.limitedStringValue(raw['customTag'], 4096);
    book.coverUrl = AppDataBackupService.limitedStringValue(raw['coverUrl'], 16384);
    book.customCoverUrl = AppDataBackupService.limitedStringValue(raw['customCoverUrl'], 16384);
    book.intro = AppDataBackupService.limitedStringValue(raw['intro'], 65536);
    book.customIntro = AppDataBackupService.limitedStringValue(raw['customIntro'], 65536);
    book.charset = AppDataBackupService.limitedStringValue(raw['charset'], 128);
    book.type = AppDataBackupService.numberValue(raw['type'], 0);
    book.group = AppDataBackupService.mapAndroidBookGroup(
      AppDataBackupService.numberValue(raw['group'], 0), mapping);
    book.isPinned = raw['isPinned'] === true;
    book.latestChapterTitle = AppDataBackupService.stringValue(raw['latestChapterTitle']);
    book.updateTime = AppDataBackupService.stringValue(raw['updateTime']);
    book.latestChapterTime = AppDataBackupService.numberValue(raw['latestChapterTime'], 0);
    book.lastCheckTime = AppDataBackupService.numberValue(raw['lastCheckTime'], 0);
    book.lastCheckCount = AppDataBackupService.numberValue(raw['lastCheckCount'], 0);
    book.totalChapterNum = AppDataBackupService.numberValue(raw['totalChapterNum'], 0);
    book.durChapterTitle = AppDataBackupService.stringValue(raw['durChapterTitle']);
    book.durChapterIndex = AppDataBackupService.numberValue(raw['durChapterIndex'], 0);
    book.durChapterPos = AppDataBackupService.numberValue(raw['durChapterPos'], 0);
    book.durChapterTime = AppDataBackupService.numberValue(raw['durChapterTime'], 0);
    book.wordCount = AppDataBackupService.stringValue(raw['wordCount']);
    book.canUpdate = raw['canUpdate'] !== false;
    book.order = AppDataBackupService.numberValue(raw['order'], 0);
    book.originOrder = AppDataBackupService.numberValue(raw['originOrder'], 0);
    const androidVariable = AppDataBackupService.stringValue(raw['variable']);
    book.replaceVariable(androidVariable.length <= 65536 ? (androidVariable || '{}') : '{}');
    // Android 备份中的 variable 是开放式运行时容器，可能夹带目录或正文缓存；Harmony
    // 只需要其中少量跨端阅读状态，避免把不兼容的大块缓存带进启动必读的 books 表。
    book.replaceVariable(AppDataBackupService.progressVariables(book));
    const readConfig = raw['readConfig'];
    if (readConfig && typeof readConfig === 'object' && !Array.isArray(readConfig)) {
      book.readConfig = AppDataBackupService.convertAndroidReadConfig(readConfig as Record<string, Object>);
    }
    book.syncTime = AppDataBackupService.numberValue(raw['syncTime'], 0);
    return book;
  }

  private static isAndroidLocalBook(raw: Record<string, Object>): boolean {
    const origin = AppDataBackupService.stringValue(raw['origin']).trim().toLowerCase();
    return origin === 'loc_book' || origin === 'local';
  }

  private static convertAndroidReadConfig(raw: Record<string, Object>): ReadConfig {
    const config = new ReadConfig();
    config.reverseToc = raw['reverseToc'] === true;
    config.pageAnim = AppDataBackupService.numberValue(raw['pageAnim'], 0);
    config.reSegment = raw['reSegment'] === true;
    config.imageStyle = AppDataBackupService.limitedStringValue(raw['imageStyle'], 64) || 'DEFAULT';
    config.useReplaceRule = raw['useReplaceRule'] !== false;
    config.delTag = AppDataBackupService.numberValue(raw['delTag'], 0);
    config.ttsEngine = AppDataBackupService.limitedStringValue(raw['ttsEngine'], 256);
    config.splitLongChapter = raw['splitLongChapter'] !== false;
    config.readSimulating = raw['readSimulating'] === true;
    config.startDate = AppDataBackupService.limitedStringValue(raw['startDate'], 64);
    config.startChapter = AppDataBackupService.numberValue(raw['startChapter'], 0);
    config.dailyChapters = AppDataBackupService.numberValue(raw['dailyChapters'], 3);
    return config;
  }

  private static mapAndroidBookGroup(legacyGroup: number, mapping: AndroidBookGroupMapping): number {
    if (legacyGroup <= 0) return 0;
    const exact = mapping.localIds.get(legacyGroup);
    if (exact !== undefined) return exact;
    for (const legacyId of mapping.legacyIds) {
      if ((legacyGroup & legacyId) === legacyId) {
        const localId = mapping.localIds.get(legacyId);
        if (localId !== undefined) return localId;
      }
    }
    return 0;
  }

  private static convertAndroidHttpTts(raw: Record<string, Object>): HttpTTS {
    const voice = new HttpTTS();
    const rawId = AppDataBackupService.numberValue(raw['id'], 0);
    voice.id = rawId > 0 ? rawId : Date.now();
    voice.name = AppDataBackupService.stringValue(raw['name']);
    voice.url = AppDataBackupService.stringValue(raw['url']);
    voice.contentType = AppDataBackupService.stringValue(raw['contentType']);
    voice.concurrentRate = AppDataBackupService.stringValue(raw['concurrentRate']);
    voice.loginUrl = AppDataBackupService.stringValue(raw['loginUrl']);
    voice.loginUi = AppDataBackupService.stringValue(raw['loginUi']);
    voice.loginCheckJs = AppDataBackupService.stringValue(raw['loginCheckJs']);
    voice.header = AppDataBackupService.stringValue(raw['header']);
    voice.jsLib = AppDataBackupService.stringValue(raw['jsLib']);
    voice.jsEngine = AppDataBackupService.stringValue(raw['jsEngine']) || voice.jsLib;
    voice.enabledCookieJar = raw['enabledCookieJar'] === true ||
      AppDataBackupService.stringValue(raw['enabledCookieJar']) === 'true';
    voice.customOrder = AppDataBackupService.numberValue(raw['customOrder'], 0);
    voice.lastUpdateTime = AppDataBackupService.numberValue(raw['lastUpdateTime'], 0);
    voice.enabled = raw['enabled'] !== false && AppDataBackupService.stringValue(raw['enabled']) !== 'false';
    return voice;
  }

  private static parseHttpTtsArray(raw: string): HttpTTS[] {
    const result: HttpTTS[] = [];
    if (!(raw || '').trim()) return result;
    try {
      const parsed = JSON.parse(raw) as Object;
      const values = Array.isArray(parsed) ? parsed as Object[] : [parsed];
      for (const value of values) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) continue;
        const voice = AppDataBackupService.convertAndroidHttpTts(value as Record<string, Object>);
        if (voice.name && voice.url) result.push(voice);
      }
    } catch (_) {}
    return result;
  }

  private static convertAndroidReplaceRule(raw: Record<string, Object>, index: number): ReaderReplaceRule {
    const rule = new ReaderReplaceRule();
    const rawId = AppDataBackupService.numberValue(raw['id'], 0);
    rule.id = rawId > 0 ? rawId : Date.now() + index;
    rule.name = AppDataBackupService.stringValue(raw['name']);
    rule.group = AppDataBackupService.stringValue(raw['group']) || '默认';
    rule.pattern = AppDataBackupService.stringValue(raw['pattern']);
    rule.replacement = AppDataBackupService.stringValue(raw['replacement']);
    rule.applyToTitle = raw['scopeTitle'] === undefined ? true : raw['scopeTitle'] === true;
    rule.applyToContent = raw['scopeContent'] === undefined ? true : raw['scopeContent'] === true;
    rule.isRegex = raw['isRegex'] !== false;
    rule.scope = AppDataBackupService.stringValue(raw['scope']);
    rule.excludeScope = AppDataBackupService.stringValue(raw['excludeScope']);
    rule.timeoutMs = AppDataBackupService.numberValue(
      raw['timeoutMillisecond'] || raw['timeoutMs'], 3000);
    rule.enabled = raw['isEnabled'] !== false && raw['enabled'] !== false;
    return rule;
  }

  private static ruleRecord(value: Object | undefined): Record<string, Object> | null {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    return value as Record<string, Object>;
  }

  private static ruleString(raw: Record<string, Object>, key: string, fallbackKey: string = ''): string {
    const value = raw[key] === undefined && fallbackKey ? raw[fallbackKey] : raw[key];
    return AppDataBackupService.stringValue(value);
  }

  private static stringValue(value: Object | undefined): string {
    if (value === undefined || value === null) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    try { return JSON.stringify(value); } catch (_) { return ''; }
  }

  private static limitedStringValue(value: Object | undefined, maxLength: number): string {
    const text = AppDataBackupService.stringValue(value);
    return text.length <= maxLength ? text : text.substring(0, maxLength);
  }

  private static numberValue(value: Object | undefined, fallback: number): number {
    if (typeof value === 'number') return Number.isFinite(value) ? Math.round(value) : fallback;
    const parsed = Number(AppDataBackupService.stringValue(value));
    return Number.isNaN(parsed) ? fallback : Math.round(parsed);
  }

  private static async forEachAndroidJsonArray(root: string, fileName: string, maxBytes: number,
    handler: (item: Record<string, Object>, index: number, offset: number, total: number) => Promise<void>):
    Promise<number> {
    const path = await AppDataBackupService.findFile(root, fileName);
    if (!path) return 0;
    const stat = await fs.stat(path);
    if (stat.size <= 0) return 0;
    if (stat.size > maxBytes) throw new Error(`${fileName} 过大，无法安全导入`);
    const raw = await AppDataBackupService.readText(path);
    let first = 0;
    while (first < raw.length && (raw[first].trim() === '' || raw.charCodeAt(first) === 0xFEFF)) first++;
    if (first >= raw.length) return 0;
    if (raw[first] === '{') {
      const parsed = JSON.parse(raw.substring(first)) as Object;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        await handler(parsed as Record<string, Object>, 0, raw.length, raw.length);
        return 1;
      }
      return 0;
    }
    if (raw[first] !== '[') throw new Error(`${fileName} 不是有效的 JSON 数组`);
    let itemStart = -1;
    let depth = 0;
    let inString = false;
    let escaped = false;
    let count = 0;
    for (let i = first + 1; i < raw.length; i++) {
      const ch = raw[i];
      if (itemStart < 0) {
        if (ch === ']') return count;
        if (ch === ',' || ch.trim() === '') continue;
        itemStart = i;
      }
      if (inString) {
        if (escaped) escaped = false;
        else if (ch === '\\') escaped = true;
        else if (ch === '"') inString = false;
        continue;
      }
      if (ch === '"') {
        inString = true;
        continue;
      }
      if (ch === '{' || ch === '[') {
        depth++;
        continue;
      }
      if (ch === '}' && depth > 0) {
        depth--;
        continue;
      }
      if (ch === ']' && depth > 0) {
        depth--;
        continue;
      }
      if ((ch === ',' || ch === ']') && depth === 0) {
        const itemRaw = raw.substring(itemStart, i).trim();
        if (itemRaw) {
          const parsed = JSON.parse(itemRaw) as Object;
          if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
            await handler(parsed as Record<string, Object>, count, i, raw.length);
            count++;
          }
        }
        itemStart = -1;
        if (ch === ']') return count;
      }
    }
    throw new Error(`${fileName} JSON 数组未完整结束`);
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
    book.status = raw.status || '';
    book.customTag = raw.customTag || '';
    book.coverUrl = AppDataBackupService.replaceRoot(raw.coverUrl || '', oldRoot, newRoot);
    book.customCoverUrl = AppDataBackupService.replaceRoot(raw.customCoverUrl || '', oldRoot, newRoot);
    book.intro = raw.intro || '';
    book.customIntro = raw.customIntro || '';
    book.charset = raw.charset || '';
    book.type = raw.type || 0;
    book.group = raw.group || 0;
    book.isPinned = raw.isPinned === true;
    book.latestChapterTitle = raw.latestChapterTitle || '';
    book.updateTime = raw.updateTime || '';
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

  private static sanitizeBookSource(source: BookSource): BookSource {
    const value = JSON.parse(JSON.stringify(source)) as BookSource;
    // Source definitions contain legitimate script identifiers such as `${token}` and URL
    // parameters named token/password. Generic text redaction corrupts those programs. Only
    // remove user-specific runtime credentials; keep imported definitions and unknown fields.
    value.loginHeader = '';
    value.loginInfo = '';
    value.rawSourceJson = AppDataBackupService.sanitizeRawBookSourceJson(value.rawSourceJson || '');
    return value;
  }

  private static sanitizeRawBookSourceJson(raw: string): string {
    if (!(raw || '').trim()) return '';
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return raw;
      const clean: Record<string, Object> = {};
      for (const key of Object.keys(parsed)) {
        if (key !== 'loginHeader' && key !== 'loginInfo') clean[key] = parsed[key];
      }
      return JSON.stringify(clean);
    } catch (_) {
      return raw;
    }
  }

  private static sanitizeBook(source: Book): Book {
    const book = JSON.parse(JSON.stringify(source)) as Book;
    book.variable = AppDataBackupService.sanitizeStructuredText(book.variable || '{}');
    return book;
  }

  private static sanitizeStructuredText(raw: string): string {
    const value = (raw || '').trim();
    if (!value) return raw || '';
    try {
      const parsed = JSON.parse(value) as Object;
      return JSON.stringify(AppDataBackupService.sanitizeValue(parsed));
    } catch (_) {
      return AppDataBackupService.redactSensitiveText(raw);
    }
  }

  private static sanitizeValue(value: Object): Object {
    if (typeof value === 'string') {
      const text = value.trim();
      if ((text.startsWith('{') && text.endsWith('}')) ||
        (text.startsWith('[') && text.endsWith(']'))) {
        try {
          return JSON.stringify(AppDataBackupService.sanitizeValue(JSON.parse(text) as Object));
        } catch (_) {}
      }
      return AppDataBackupService.redactSensitiveText(value);
    }
    if (Array.isArray(value)) {
      const result: Object[] = [];
      for (const item of value as Object[]) result.push(AppDataBackupService.sanitizeValue(item));
      return result;
    }
    if (value !== null && typeof value === 'object') {
      const source = value as Record<string, Object>;
      const result: Record<string, Object> = {};
      for (const key of Object.keys(source)) {
        result[key] = AppDataBackupService.isSensitiveKey(key) ? '' :
          AppDataBackupService.sanitizeValue(source[key]);
      }
      return result;
    }
    return value;
  }

  private static isSensitiveKey(key: string): boolean {
    const normalized = (key || '').toLowerCase().replace(/[_\-\s]/g, '');
    return normalized.includes('cookie') ||
      normalized.includes('密码') ||
      normalized.includes('password') ||
      normalized.includes('passwd') ||
      normalized.includes('credential') ||
      normalized === 'pwd' ||
      normalized.includes('token') ||
      normalized.includes('authorization') ||
      normalized.includes('loginheader') ||
      normalized.includes('secret') ||
      normalized.includes('apikey') ||
      normalized.includes('accesskey') ||
      normalized.includes('sessionid');
  }

  private static redactSensitiveText(raw: string): string {
    return (raw || '')
      .replace(/(^|\r?\n)\s*(cookie|authorization|proxy-authorization|x-api-key|x-access-token)\s*:[^\r\n]*/gi,
        '$1')
      .replace(/([?&](?:access_?token|refresh_?token|token|password|passwd|pwd|api_?key|secret|session_?id)=)[^&#\s"'\\]+/gi,
        '$1[removed]')
      .replace(/((?:cookie|authorization|access_?token|refresh_?token|token|password|passwd|pwd|api_?key|secret)\s*[:=]\s*["'])[^"'\r\n]*(["'])/gi,
        '$1[removed]$2');
  }

  private static async restorePreferenceStore(context: Context, storeName: string, raw: string,
    oldRoot: string): Promise<void> {
    const store = await preferences.getPreferences(context, storeName);
    let localValues: Record<string, preferences.ValueType> = {};
    if (storeName === AppDataBackupService.READER_SETTINGS_STORE) {
      localValues = await store.getAll() as Record<string, preferences.ValueType>;
    }
    const values = JSON.parse(AppDataBackupService.replaceRoot(raw || '{}', oldRoot, context.filesDir)) as
      Record<string, preferences.ValueType>;
    if (storeName === AppDataBackupService.READER_SETTINGS_STORE) {
      AppDataBackupService.preserveLocalGlobalFontSettings(values, localValues);
    }
    await store.clear();
    for (const key of Object.keys(values)) {
      await store.put(key, values[key]);
    }
    await store.flush();
  }

  private static preserveLocalGlobalFontSettings(
    incoming: Record<string, preferences.ValueType>,
    local: Record<string, preferences.ValueType>
  ): void {
    const fontFamily = AppDataBackupService.preferenceString(local, 'readerFontFamily', '');
    const fontFilePath = AppDataBackupService.preferenceString(local, 'readerFontFilePath', '');
    const fontSourceName = AppDataBackupService.preferenceString(local, 'readerFontSourceName', '系统默认');
    const fontMode = AppDataBackupService.preferenceString(local, 'readerFontMode', 'system');
    const systemFontFamily = AppDataBackupService.preferenceString(local, 'readerSystemFontFamily', '');
    const customFontsRaw = AppDataBackupService.preferenceString(local, 'readerCustomFontsRaw', '');

    incoming['readerFontFamily'] = fontFamily;
    incoming['readerFontFilePath'] = fontFilePath;
    incoming['readerFontSourceName'] = fontSourceName;
    incoming['readerFontMode'] = fontMode;
    incoming['readerSystemFontFamily'] = systemFontFamily;
    incoming['readerCustomFontsRaw'] = customFontsRaw;

    for (const key of Object.keys(incoming)) {
      if (!key.startsWith(AppDataBackupService.READER_THEME_PROFILE_PREFIX) ||
        typeof incoming[key] !== 'string') {
        continue;
      }
      try {
        const profile = JSON.parse(incoming[key] as string) as Record<string, Object>;
        profile['fontFamily'] = fontFamily;
        profile['fontFilePath'] = fontFilePath;
        profile['fontSourceName'] = fontSourceName;
        profile['fontMode'] = fontMode;
        profile['systemFontFamily'] = systemFontFamily;
        profile['customFontsRaw'] = customFontsRaw;
        incoming[key] = JSON.stringify(profile);
      } catch (_) {
        // Invalid profiles are ignored by ReaderSettingsStore as well.
      }
    }
  }

  private static preferenceString(
    values: Record<string, preferences.ValueType>,
    key: string,
    fallback: string
  ): string {
    const value = values[key];
    return typeof value === 'string' ? value : fallback;
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

  private static reportProgress(onProgress: ((message: string, percent: number) => void) | undefined,
    message: string, percent: number): void {
    if (onProgress) onProgress(message, Math.max(0, Math.min(100, percent)));
  }

  private static async ensureEnoughTempSpace(context: Context, selection: AppDataBackupSelection,
    allBooks: Book[]): Promise<void> {
    let sourceBytes = 0;
    const countedPaths: string[] = [];
    if (selection.localBooks) {
      for (const book of allBooks) {
        if (!LocalBookService.isLocalBook(book)) continue;
        const path = book.getVariable('localFilePath');
        if (!path || countedPaths.includes(path) || !AppDataBackupService.exists(path)) continue;
        countedPaths.push(path);
        sourceBytes += await AppDataBackupService.pathSize(path);
      }
    }
    if (selection.settings) {
      for (const dirName of AppDataBackupService.ASSET_DIRS) {
        const path = `${context.filesDir}/${dirName}`;
        if (AppDataBackupService.exists(path)) sourceBytes += await AppDataBackupService.pathSize(path);
      }
    }

    const reserve = 32 * 1024 * 1024;
    const minimum = 64 * 1024 * 1024;
    const required = Math.max(minimum, Math.ceil(sourceBytes * 2.25) + reserve);
    let free = 0;
    try {
      free = await statfs.getFreeSize(context.tempDir);
    } catch (error) {
      console.warn('读取备份临时空间失败，将继续备份:', error);
      return;
    }
    if (free < required) {
      throw new Error(`存储空间不足：预计需要 ${AppDataBackupService.formatBytes(required)} 临时空间，` +
        `当前可用 ${AppDataBackupService.formatBytes(free)}`);
    }
  }

  private static async pathSize(path: string): Promise<number> {
    const stat = await fs.stat(path);
    if (!stat.isDirectory()) return stat.size;
    let size = 0;
    const names = await fs.listFile(path);
    for (const name of names) size += await AppDataBackupService.pathSize(`${path}/${name}`);
    return size;
  }

  private static formatBytes(bytes: number): string {
    if (bytes >= 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
    return `${Math.max(1, Math.ceil(bytes / (1024 * 1024)))} MB`;
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
    let sourceFile: fs.File | null = null;
    let targetFile: fs.File | null = null;
    try {
      sourceFile = await fs.open(source, fs.OpenMode.READ_ONLY);
      targetFile = await fs.open(target,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.copyFile(sourceFile.fd, targetFile.fd);
    } finally {
      if (sourceFile) {
        try { await fs.close(sourceFile); } catch (_) {}
      }
      if (targetFile) {
        try { await fs.close(targetFile); } catch (_) {}
      }
    }
  }

  private static async removeDirectory(path: string): Promise<void> {
    if (!AppDataBackupService.exists(path)) return;
    const names = await fs.listFile(path);
    for (const name of names) {
      const child = `${path}/${name}`;
      const stat = await fs.stat(child);
      if (stat.isDirectory()) {
        await AppDataBackupService.removeDirectory(child);
      } else {
        await AppDataBackupService.removeFile(child);
      }
    }
    try { await fs.rmdir(path); } catch (_) {}
  }

  private static async removeFile(path: string): Promise<void> {
    try {
      if (AppDataBackupService.exists(path)) await fs.unlink(path);
    } catch (_) {}
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
