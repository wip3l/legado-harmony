import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import preferences from '@ohos.data.preferences';
import { Book } from '@legado/sourceengine';
import { AccountSessionStore } from './AccountSessionStore';
import { CloudSyncSettingsStore } from './CloudSyncSettingsStore';
import { CloudSyncIssueStore } from './CloudSyncIssueStore';
import { CloudFileClient } from './CloudFileClient';
import { CloudFontImport } from './CloudFontImport';
import { CloudFileItem, CloudFileMeta, CloudTombstone } from './CloudFileModels';
import { AppDatabase } from '../model/data/AppDatabase';
import { LocalBookService } from '../core/book/LocalBookService';
import { ReaderFontHelper } from '../utils/ReaderFontHelper';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';

/** 云端有、本机还没下载的字体，供各字体下拉框置灰显示。 */
export class CloudRemoteFont {
  id: string = '';
  name: string = '';
  bytes: number = 0;
}

class PendingRemoval {
  id: string = '';
  kind: string = '';
  /** FONT：文件指纹；BOOK：内容指纹。上传尚未完成时用它在云端找到对应文件。 */
  hash: string = '';
  reason: string = 'REMOVED';
  createdAt: number = 0;
}

class FontHashEntry {
  size: number = 0;
  mtime: number = 0;
  hash: string = '';
}

class LocalFontRef {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class LocalFontData {
  fonts: LocalFontRef[] = [];
}

class UploadJob {
  path: string = '';
  name: string = '';
  kind: string = '';
  meta: CloudFileMeta | null = null;
  manifestHash: string = '';
  key: string = '';
}

/**
 * 终身超级会员的字体与本地书籍云同步，用户无感：
 * - 本机新增的自定义字体、加入书架的本地书籍自动上传；
 * - 删除字体、移出书架时删除云端文件，并留下删除标记，其他设备据此一并移除；
 * - 其他设备上，未下载的云端字体出现在字体下拉框（置灰），未下载的书籍以占位书出现在书架（置灰），
 *   选中或打开时自动下载导入。
 * 只在登录、有效终身超级会员且云文件服务可用时工作；任何失败都留到下次再试，不打扰用户。
 */
export class CloudAutoSync {
  static readonly STORAGE_REMOTE_FONTS: string = 'cloudRemoteFontsRaw';
  static readonly STORAGE_REVISION: string = 'cloudAutoSyncRevision';
  static readonly PLACEHOLDER_KEY: string = 'cloudPlaceholder';
  static readonly CLOUD_FILE_ID_KEY: string = 'cloudFileId';
  private static readonly STORE: string = 'cloud_auto_sync';
  private static readonly CLOUD_FONT_NAME: RegExp =
    /^cloud_([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\.(?:ttf|otf|ttc)$/i;
  private static running: Promise<void> | null = null;
  private static rerun: boolean = false;
  private static timer: number = -1;
  /** 本次运行期间上传失败（如空间不足）的内容，不在每次对账时反复重试。 */
  private static failedUploads: Set<string> = new Set<string>();

  static isPlaceholder(book: Book | null): boolean {
    return !!book && book.getVariable(CloudAutoSync.PLACEHOLDER_KEY) === '1';
  }

  static remoteFonts(): CloudRemoteFont[] {
    return CloudAutoSync.parseRemoteFonts(AppStorage.get<string>(CloudAutoSync.STORAGE_REMOTE_FONTS) || '');
  }

  /** 页面通过 @StorageLink 拿到原始字符串再解析，列表变化时下拉框随之刷新。 */
  static parseRemoteFonts(raw: string): CloudRemoteFont[] {
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw) as CloudRemoteFont[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  /** 合并短时间内的多次触发；正在运行时安排一次补跑。 */
  static schedule(context: Context, delayMs: number = 2000): void {
    if (CloudAutoSync.timer >= 0) clearTimeout(CloudAutoSync.timer);
    CloudAutoSync.timer = setTimeout(() => {
      CloudAutoSync.timer = -1;
      CloudAutoSync.reconcile(context).catch((error: Error) => {
        console.warn('[CloudAutoSync] reconcile failed:', error.message);
        const message = error.message || '文件同步失败';
        CloudAutoSync.recordIssue(context, AccountSessionStore.account().userId, `file-run:${message}`,
          '本地书籍与字体同步失败', message);
      });
    }, delayMs);
  }

  static async reconcile(context: Context): Promise<void> {
    if (CloudAutoSync.running) {
      CloudAutoSync.rerun = true;
      return CloudAutoSync.running;
    }
    const task = CloudAutoSync.run(context);
    CloudAutoSync.running = task;
    try {
      await task;
    } finally {
      CloudAutoSync.running = null;
      if (CloudAutoSync.rerun) {
        CloudAutoSync.rerun = false;
        CloudAutoSync.schedule(context, 500);
      }
    }
  }

  /** 字体管理页删除字体前调用：记下云端要删除的文件，文件指纹要在删除本地文件前算好。 */
  static async onFontDeleted(context: Context, filePath: string): Promise<void> {
    const userId = AccountSessionStore.account().userId;
    if (!userId || !filePath) return;
    await CloudAutoSync.loadSettings(context, userId);
    if (!CloudAutoSync.scopeEnabled(userId, 'FONT')) return;
    const removal = new PendingRemoval();
    removal.kind = 'FONT';
    removal.createdAt = Date.now();
    removal.id = CloudAutoSync.cloudIdFromPath(filePath);
    if (!removal.id) {
      try {
        removal.hash = await CloudAutoSync.fontHash(context, filePath);
      } catch (e) {
        return;
      }
    }
    await CloudAutoSync.addRemoval(context, userId, removal);
    CloudAutoSync.schedule(context, 1000);
  }

  /** 书架移出本地书籍时调用：云端文件随之删除，其他设备也会移除。 */
  static async onBookRemoved(context: Context, book: Book): Promise<void> {
    const userId = AccountSessionStore.account().userId;
    if (!userId || !LocalBookService.isLocalBook(book) || book.getVariable('storageKind')) return;
    await CloudAutoSync.loadSettings(context, userId);
    if (!CloudAutoSync.scopeEnabled(userId, 'BOOK')) return;
    const removal = new PendingRemoval();
    removal.kind = 'BOOK';
    removal.createdAt = Date.now();
    removal.id = book.getVariable(CloudAutoSync.CLOUD_FILE_ID_KEY);
    removal.hash = book.getVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY);
    if (!removal.id && !removal.hash) return;
    await CloudAutoSync.addRemoval(context, userId, removal);
    CloudAutoSync.schedule(context, 1000);
  }

  /** 下拉框选中未下载的云端字体：下载并登记为本机字体，返回字体文件路径。 */
  static async ensureFontDownloaded(context: Context, font: CloudRemoteFont): Promise<string> {
    const item = new CloudFileItem();
    item.id = font.id;
    item.name = font.name;
    item.kind = 'FONT';
    item.bytes = font.bytes;
    item.state = 'READY';
    const target = CloudFontImport.localPath(context.filesDir, item);
    if (!target) throw new Error('字体格式无效');
    if (!fs.accessSync(target)) {
      const downloaded = await CloudFileClient.download(context, item, () => {});
      const dir = `${context.filesDir}/reader_fonts`;
      if (!fs.accessSync(dir)) await fs.mkdir(dir);
      await fs.copy(fileUri.getUriFromPath(downloaded), fileUri.getUriFromPath(target));
      try { await fs.unlink(downloaded); } catch (e) { /* the transfer copy is only a cache */ }
    }
    await CloudFontImport.saveNames(context, context.filesDir, [item]);
    CloudAutoSync.publishRemoteFonts(CloudAutoSync.remoteFonts().filter((entry: CloudRemoteFont) => entry.id !== font.id));
    return target;
  }

  /** 上传后直接登记暂存字体；同一字体已在本机时复用路径，不改变当前字体选择。 */
  static async importFontFile(context: Context, file: CloudFileItem, path: string): Promise<string> {
    const target = CloudFontImport.localPath(context.filesDir, file);
    if (!target) throw new Error('字体格式无效');
    if (file.manifestHash && file.bytes > 0) {
      for (const font of CloudAutoSync.localFonts()) {
        if (!CloudAutoSync.exists(font.filePath)) continue;
        if ((await fs.stat(font.filePath)).size === file.bytes &&
          await CloudAutoSync.fontHash(context, font.filePath) === file.manifestHash) return font.filePath;
      }
    }
    const dir = `${context.filesDir}/reader_fonts`;
    if (!fs.accessSync(dir)) await fs.mkdir(dir);
    if (path !== target) await fs.copy(fileUri.getUriFromPath(path), fileUri.getUriFromPath(target));
    await CloudFontImport.saveNames(context, context.filesDir, [file]);
    CloudAutoSync.publishRemoteFonts(CloudAutoSync.remoteFonts().filter((entry: CloudRemoteFont) => entry.id !== file.id));
    return target;
  }

  /** 打开书架上的云端占位书：下载导入为真正的本地书，书架分组与阅读进度保留。 */
  static async ensureBookDownloaded(context: Context, book: Book): Promise<Book> {
    if (!CloudAutoSync.isPlaceholder(book)) return book;
    const item = new CloudFileItem();
    item.id = book.getVariable(CloudAutoSync.CLOUD_FILE_ID_KEY);
    item.kind = 'BOOK';
    item.state = 'READY';
    const format = (book.getVariable('localFormat') || 'txt').toLowerCase();
    item.name = `${LocalBookService.sanitizeFileName(book.name)}.${format}`;
    item.manifestHash = book.getVariable('cloudManifestHash');
    const downloaded = await CloudFileClient.download(context, item, () => {});
    try {
      return await CloudAutoSync.importBookFile(context, item, downloaded);
    } finally {
      try { await fs.unlink(downloaded); } catch (e) { /* the transfer copy is only a cache */ }
    }
  }

  /** 手动上传使用暂存原文件，下载使用传输文件；复用已有书架行，避免重新下载或重复导入。 */
  static async importBookFile(context: Context, file: CloudFileItem, path: string): Promise<Book> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const books = (await db.getAllBooks()).filter((book: Book) => LocalBookService.isLocalBook(book) &&
      !book.getVariable('storageKind') && !book.pendingAddToShelf);
    const existing = await CloudAutoSync.findLocalBook(context, books, file);
    const format = (file.meta?.format || LocalBookService.extensionOf(file.name)).toLowerCase();
    const ready = existing && !CloudAutoSync.isPlaceholder(existing) &&
      LocalBookService.exists(existing.getVariable('localFilePath'));
    const book = ready ? existing! : await LocalBookService.importCloudBook(context, path, format,
      file.name, existing?.bookUrl || `cloudbook://${file.id}`, [CloudAutoSync.PLACEHOLDER_KEY]);
    book.putVariable(CloudAutoSync.CLOUD_FILE_ID_KEY, file.id);
    book.putVariable('cloudManifestHash', file.manifestHash || '');
    await db.updateBook(book, false, 'cloud_book_linked');
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    return book;
  }

  private static async findLocalBook(context: Context, books: Book[], file: CloudFileItem): Promise<Book | null> {
    const linked = books.find((book: Book) => book.getVariable(CloudAutoSync.CLOUD_FILE_ID_KEY) === file.id ||
      (!!file.meta?.contentHash && book.getVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY) === file.meta.contentHash) ||
      (!!file.manifestHash && book.getVariable('cloudManifestHash') === file.manifestHash));
    if (linked) return linked;
    // Historical manual uploads lack contentHash. Match their chunk manifest without inventing a raw content hash.
    if (file.manifestHash && file.bytes > 0) {
      for (const book of books) {
        const path = book.getVariable('localFilePath');
        if (!path || !CloudAutoSync.exists(path) || CloudAutoSync.isPlaceholder(book)) continue;
        if ((await fs.stat(path)).size === file.bytes && await CloudAutoSync.fontHash(context, path) === file.manifestHash) {
          return book;
        }
      }
    }
    return null;
  }

  private static bookFileKey(file: CloudFileItem): string {
    return file.meta?.contentHash ? `content:${file.meta.contentHash}` :
      file.manifestHash ? `manifest:${file.manifestHash}` : `id:${file.id}`;
  }

  private static async run(context: Context): Promise<void> {
    const userId = AccountSessionStore.account().userId;
    if (!userId || !AccountSessionStore.isLoggedIn() || AccountSessionStore.activeMembershipSku() !== 'SUPER_LIFETIME') {
      CloudAutoSync.publishRemoteFonts([]);
      return;
    }
    await CloudAutoSync.loadSettings(context, userId);
    if (!CloudAutoSync.scopeEnabled(userId, 'FONT')) CloudAutoSync.publishRemoteFonts([]);
    if (!CloudAutoSync.scopeEnabled(userId, 'FONT') && !CloudAutoSync.scopeEnabled(userId, 'BOOK')) return;
    const summary = await CloudFileClient.summary();
    if (!summary.configured || !summary.eligible) {
      CloudAutoSync.publishRemoteFonts([]);
      return;
    }
    let files = (await CloudFileClient.listAll()).filter((file: CloudFileItem) => file.state === 'READY');
    const tombstones = (await CloudFileClient.tombstones()).tombstones || [];
    const removed = await CloudAutoSync.flushRemovals(context, userId, files);
    files = files.filter((file: CloudFileItem) => !removed.has(file.id));
    if (AccountSessionStore.account().userId !== userId) return;
    const uploads: UploadJob[] = [];
    if (CloudAutoSync.scopeEnabled(userId, 'FONT')) {
      await CloudAutoSync.syncFonts(context, files, tombstones, uploads);
    }
    if (CloudAutoSync.scopeEnabled(userId, 'BOOK')) {
      await CloudAutoSync.syncBooks(context, files, tombstones, uploads);
    }
    await CloudAutoSync.runUploads(context, userId, uploads);
  }

  private static async loadSettings(context: Context, userId: string): Promise<void> {
    if (CloudSyncSettingsStore.currentAccountId() !== userId) {
      await CloudSyncSettingsStore.load(context, userId);
    }
  }

  private static scopeEnabled(userId: string, kind: string): boolean {
    if (!AccountSessionStore.isLoggedIn() || AccountSessionStore.account().userId !== userId ||
      AccountSessionStore.activeMembershipSku() !== 'SUPER_LIFETIME' ||
      CloudSyncSettingsStore.currentAccountId() !== userId) return false;
    const settings = CloudSyncSettingsStore.current();
    return kind === 'BOOK' ? settings.localBooksEnabled : kind === 'FONT' && settings.customFontsEnabled;
  }

  private static async syncFonts(context: Context, files: CloudFileItem[], tombstones: CloudTombstone[],
    uploads: UploadJob[]): Promise<void> {
    const cloudFonts = files.filter((file: CloudFileItem) => file.kind === 'FONT');
    const fontTombs = tombstones.filter((tomb: CloudTombstone) => tomb.kind === 'FONT');
    const linked = new Set<string>();
    for (const font of CloudAutoSync.localFonts()) {
      const cloudId = CloudAutoSync.cloudIdFromPath(font.filePath);
      let file = cloudId ? cloudFonts.find((item: CloudFileItem) => item.id === cloudId) : undefined;
      let hash = '';
      if (!file) {
        try {
          hash = await CloudAutoSync.fontHash(context, font.filePath);
        } catch (e) {
          continue;
        }
        file = cloudFonts.find((item: CloudFileItem) => item.manifestHash === hash);
      }
      if (file) {
        linked.add(file.id);
        continue;
      }
      const tomb = fontTombs.find((item: CloudTombstone) => (!!cloudId && item.id === cloudId) ||
        (!!hash && item.manifestHash === hash));
      // Only a copy that existed before the removal follows it; a font imported again afterwards is new.
      if (tomb && CloudAutoSync.fileTime(font.filePath) < tomb.removedAt) {
        if (tomb.reason === 'REMOVED') CloudAutoSync.removeLocalFont(context, font);
        continue;
      }
      const job = new UploadJob();
      job.path = font.filePath;
      job.name = CloudFontImport.uploadName(font.sourceName, font.filePath);
      job.kind = 'FONT';
      const meta = new CloudFileMeta();
      meta.fontName = ReaderFontHelper.resolveDisplayName(font.sourceName, font.filePath).slice(0, 200);
      job.meta = meta;
      job.manifestHash = hash;
      job.key = `FONT:${hash}`;
      uploads.push(job);
    }
    const remote: CloudRemoteFont[] = [];
    for (const file of cloudFonts) {
      if (linked.has(file.id)) continue;
      const entry = new CloudRemoteFont();
      entry.id = file.id;
      entry.name = file.name;
      entry.bytes = file.bytes;
      remote.push(entry);
    }
    CloudAutoSync.publishRemoteFonts(remote);
  }

  private static async syncBooks(context: Context, files: CloudFileItem[], tombstones: CloudTombstone[],
    uploads: UploadJob[]): Promise<void> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const cloudBooks = files.filter((file: CloudFileItem) => file.kind === 'BOOK' &&
      (!!file.meta?.contentHash || LocalBookService.isSupportedFormat(file.meta?.format || LocalBookService.extensionOf(file.name))));
    const bookTombs = tombstones.filter((tomb: CloudTombstone) => tomb.kind === 'BOOK');
    const present = new Set<string>();
    let changed = false;
    const books = (await db.getAllBooks()).filter((book: Book) => LocalBookService.isLocalBook(book) &&
      !book.getVariable('storageKind') && !book.pendingAddToShelf);
    for (const book of books) {
      if (CloudAutoSync.isPlaceholder(book)) {
        const file = cloudBooks.find((item: CloudFileItem) => item.id === book.getVariable(CloudAutoSync.CLOUD_FILE_ID_KEY));
        if (!file) {
          await CloudAutoSync.removeShelfBook(context, book);
          changed = true;
          continue;
        }
        present.add(CloudAutoSync.bookFileKey(file));
        continue;
      }
      const hash = await LocalBookService.ensureContentHash(book);
      let linked: CloudFileItem | null = null;
      for (const file of cloudBooks) {
        if (await CloudAutoSync.findLocalBook(context, [book], file)) { linked = file; break; }
      }
      if (linked) {
        present.add(CloudAutoSync.bookFileKey(linked));
        if (book.getVariable(CloudAutoSync.CLOUD_FILE_ID_KEY) !== linked.id ||
          book.getVariable('cloudManifestHash') !== linked.manifestHash) {
          book.putVariable(CloudAutoSync.CLOUD_FILE_ID_KEY, linked.id);
          book.putVariable('cloudManifestHash', linked.manifestHash || '');
          await db.updateBook(book, false, 'cloud_book_linked');
        }
        continue;
      }
      const tomb = bookTombs.find((item: CloudTombstone) => item.id === book.getVariable(CloudAutoSync.CLOUD_FILE_ID_KEY) ||
        (!!hash && item.meta?.contentHash === hash) ||
        (!!item.manifestHash && item.manifestHash === book.getVariable('cloudManifestHash')));
      if (tomb && (Number(book.getVariable('bookAddTime')) || 0) < tomb.removedAt) {
        if (tomb.reason === 'REMOVED') {
          await CloudAutoSync.removeShelfBook(context, book);
          changed = true;
        }
        continue;
      }
      if (!hash) continue;
      const path = book.getVariable('localFilePath');
      // Private-shelf books stay on the device.
      if (book.isPrivate || !path || !LocalBookService.exists(path)) continue;
      const format = (book.getVariable('localFormat') ||
        (book.type === LocalBookService.TYPE_EPUB ? 'epub' : 'txt')).toLowerCase();
      const job = new UploadJob();
      job.path = path;
      job.name = `${LocalBookService.sanitizeFileName(book.name).slice(0, 180)}.${format}`;
      job.kind = 'BOOK';
      const meta = new CloudFileMeta();
      meta.title = (book.name || '').slice(0, 200);
      meta.author = (book.author || '').slice(0, 200);
      meta.format = format;
      meta.contentHash = hash;
      job.meta = meta;
      job.key = `BOOK:${hash}`;
      uploads.push(job);
    }
    for (const file of cloudBooks) {
      const key = CloudAutoSync.bookFileKey(file);
      if (present.has(key)) continue;
      present.add(key);
      await CloudAutoSync.insertPlaceholder(db, file);
      changed = true;
    }
    if (changed) AppStorage.setOrCreate('shelfUpdateTime', Date.now());
  }

  private static async insertPlaceholder(db: AppDatabase, file: CloudFileItem): Promise<void> {
    const meta = file.meta || new CloudFileMeta();
    const format = (meta.format || LocalBookService.extensionOf(file.name) || 'txt').toLowerCase();
    const book = new Book();
    book.bookUrl = `cloudbook://${file.id}`;
    book.tocUrl = book.bookUrl;
    book.origin = LocalBookService.ORIGIN;
    book.originName = format.toUpperCase();
    book.name = meta.title || LocalBookService.fileStem(file.name);
    book.author = meta.author || '';
    book.canUpdate = false;
    book.group = 0;
    book.type = LocalBookService.bookTypeForFormat(format);
    book.putVariable(CloudAutoSync.PLACEHOLDER_KEY, '1');
    book.putVariable(CloudAutoSync.CLOUD_FILE_ID_KEY, file.id);
    book.putVariable('cloudManifestHash', file.manifestHash || '');
    book.putVariable('localFormat', format);
    book.putVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY, meta.contentHash || '');
    book.putVariable('bookAddTime', `${Date.now()}`);
    await db.insertBook(book, 'cloud_book_placeholder');
  }

  private static async removeShelfBook(context: Context, book: Book): Promise<void> {
    const db = AppDatabase.getInstance();
    LocalBookService.deleteLocalBookFiles(context, book);
    await db.deleteBook(book.bookUrl, 'cloud_book_removed');
  }

  /** 与字体管理页删除字体相同：移出列表、删除文件，正在使用时恢复系统字体。 */
  private static removeLocalFont(context: Context, font: LocalFontRef): void {
    const data = new LocalFontData();
    data.fonts = CloudAutoSync.localFonts().filter((item: LocalFontRef) => item.filePath !== font.filePath);
    const raw = JSON.stringify(data);
    AppStorage.setOrCreate('readerCustomFontsRaw', raw);
    const selected = AppStorage.get<string>('readerFontFilePath') === font.filePath;
    if (selected) {
      AppStorage.setOrCreate('readerFontMode', ReaderSettingsStore.FONT_MODE_DEVICE);
      AppStorage.setOrCreate('readerFontFamily', '');
      AppStorage.setOrCreate('readerFontFilePath', '');
      AppStorage.setOrCreate('readerFontSourceName', '系统默认');
      AppStorage.setOrCreate('readerActiveFontFamily', '');
      AppStorage.setOrCreate('readerFontRegistered', false);
      ReaderFontBootstrap.applyApplicationFont(context, 'cloud-font-deleted');
    }
    ReaderSettingsStore.saveFontSettings(context,
      AppStorage.get<string>('readerFontFamily') || '',
      AppStorage.get<string>('readerFontFilePath') || '',
      AppStorage.get<string>('readerFontSourceName') || '系统默认',
      AppStorage.get<string>('readerFontMode') || ReaderSettingsStore.FONT_MODE_DEVICE,
      AppStorage.get<string>('readerSystemFontFamily') || '', raw).catch((error: Error) => {
      console.warn('[CloudAutoSync] save font settings failed:', error.message);
    });
    try {
      fs.unlinkSync(font.filePath);
    } catch (e) {
      console.warn('[CloudAutoSync] delete font file failed:', e);
    }
  }

  private static async runUploads(context: Context, userId: string, uploads: UploadJob[]): Promise<void> {
    if (uploads.length === 0 || CloudFileClient.isTransferring()) return;
    const pending = await CloudFileClient.pending(context);
    if (pending && !pending.auto) return; // A manual upload is waiting for the user; leave it alone.
    if (pending) {
      if (!CloudAutoSync.scopeEnabled(userId, pending.kind)) return;
      try {
        await CloudFileClient.upload(context, () => {});
      } catch (e) {
        console.warn('[CloudAutoSync] resume upload failed:', (e as Error).message);
        return;
      }
    }
    let uploaded = false;
    for (const job of uploads) {
      if (!CloudAutoSync.scopeEnabled(userId, job.kind)) continue;
      if (CloudAutoSync.failedUploads.has(job.key) || AccountSessionStore.account().userId !== userId) continue;
      try {
        await CloudFileClient.stage(context, job.path, job.name, job.kind, job.meta, true, job.manifestHash);
        await CloudFileClient.upload(context, () => {});
        uploaded = true;
      } catch (e) {
        const message = (e as Error).message || '';
        console.warn('[CloudAutoSync] upload failed:', job.name, message);
        CloudAutoSync.failedUploads.add(job.key);
        const label = job.kind === 'FONT' ? `字体“${job.meta?.fontName || job.name}”` :
          `本地书籍“${job.meta?.title || job.name}”`;
        CloudAutoSync.recordIssue(context, userId, `file:${job.key}`, `${label}未能上传`, message || '上传失败');
        // Keep the staged task for the next run only if it is resumable; a full space must be freed first.
        try { await CloudFileClient.cancelUpload(context); } catch (cancelError) { /* retried next run */ }
        if (message.includes('云空间不足')) break;
      }
    }
    if (uploaded) AppStorage.setOrCreate(CloudAutoSync.STORAGE_REVISION, Date.now());
  }

  private static recordIssue(context: Context, userId: string, key: string, title: string, message: string): void {
    if (!userId) return;
    CloudSyncIssueStore.record(context, userId,
      [CloudSyncIssueStore.create(CloudSyncIssueStore.KIND_FILE, key, title, message)]).catch((error: Error) => {
      console.warn('[CloudAutoSync] record issue failed:', error.message);
    });
  }

  private static async flushRemovals(context: Context, userId: string, files: CloudFileItem[]): Promise<Set<string>> {
    const removed = new Set<string>();
    const removals = await CloudAutoSync.loadRemovals(context, userId);
    if (removals.length === 0) return removed;
    const keep: PendingRemoval[] = [];
    for (const removal of removals) {
      if (!CloudAutoSync.scopeEnabled(userId, removal.kind)) {
        keep.push(removal);
        continue;
      }
      const file = removal.id ? files.find((item: CloudFileItem) => item.id === removal.id) :
        files.find((item: CloudFileItem) => item.kind === removal.kind &&
          (removal.kind === 'BOOK' ? item.meta?.contentHash === removal.hash : item.manifestHash === removal.hash));
      if (!file) {
        // Nothing in the cloud yet (or already gone). Keep a short while in case an upload is still finishing.
        if (Date.now() - removal.createdAt < 24 * 60 * 60 * 1000 && !removal.id) keep.push(removal);
        continue;
      }
      try {
        await CloudFileClient.remove(file.id, removal.reason);
        removed.add(file.id);
      } catch (e) {
        keep.push(removal);
      }
    }
    await CloudAutoSync.saveRemovals(context, userId, keep);
    return removed;
  }

  private static localFonts(): LocalFontRef[] {
    const raw = (AppStorage.get<string>('readerCustomFontsRaw') || '').trim();
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw) as LocalFontData | LocalFontRef[];
      const source = Array.isArray(parsed) ? parsed as LocalFontRef[] : ((parsed as LocalFontData).fonts || []);
      return source.filter((item: LocalFontRef) => !!item && !!item.filePath && CloudAutoSync.exists(item.filePath));
    } catch (e) {
      return [];
    }
  }

  private static cloudIdFromPath(path: string): string {
    const name = ReaderFontHelper.fileNameFromPath(path || '');
    const match = CloudAutoSync.CLOUD_FONT_NAME.exec(name);
    return match ? match[1].toLowerCase() : '';
  }

  /** 字体文件指纹按路径、大小和修改时间缓存，避免每次对账重读文件。 */
  private static async fontHash(context: Context, path: string): Promise<string> {
    const stat = await fs.stat(path);
    const store = await preferences.getPreferences(context, CloudAutoSync.STORE);
    const key = `font_hash:${path}`;
    const raw = await store.get(key, '') as string;
    if (raw) {
      const entry = JSON.parse(raw) as FontHashEntry;
      if (entry.size === stat.size && entry.mtime === stat.mtime && entry.hash) return entry.hash;
    }
    const entry = new FontHashEntry();
    entry.size = stat.size;
    entry.mtime = stat.mtime;
    entry.hash = await CloudFileClient.manifestHashOfFile(path);
    await store.put(key, JSON.stringify(entry));
    await store.flush();
    return entry.hash;
  }

  /** 文件修改时间（毫秒）；fs 给的是秒。 */
  private static fileTime(path: string): number {
    try {
      return fs.statSync(path).mtime * 1000;
    } catch (e) {
      return 0;
    }
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private static publishRemoteFonts(fonts: CloudRemoteFont[]): void {
    const raw = JSON.stringify(fonts);
    if ((AppStorage.get<string>(CloudAutoSync.STORAGE_REMOTE_FONTS) || '[]') === raw) return;
    AppStorage.setOrCreate(CloudAutoSync.STORAGE_REMOTE_FONTS, raw);
    AppStorage.setOrCreate(CloudAutoSync.STORAGE_REVISION, Date.now());
  }

  private static async loadRemovals(context: Context, userId: string): Promise<PendingRemoval[]> {
    const store = await preferences.getPreferences(context, CloudAutoSync.STORE);
    const raw = await store.get(`removals:${userId}`, '') as string;
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw) as PendingRemoval[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  private static async saveRemovals(context: Context, userId: string, removals: PendingRemoval[]): Promise<void> {
    const store = await preferences.getPreferences(context, CloudAutoSync.STORE);
    await store.put(`removals:${userId}`, JSON.stringify(removals));
    await store.flush();
  }

  private static async addRemoval(context: Context, userId: string, removal: PendingRemoval): Promise<void> {
    const removals = await CloudAutoSync.loadRemovals(context, userId);
    removals.push(removal);
    await CloudAutoSync.saveRemovals(context, userId, removals.slice(-500));
  }
}
