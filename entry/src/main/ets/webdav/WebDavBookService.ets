import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book } from '@legado/sourceengine';
import { LocalBookService } from '../core/book/LocalBookService';
import { WebDavClient } from './WebDavClient';
import { WebDavConnection, WebDavEntry } from './WebDavModels';
import { WebDavSecretStore } from './WebDavSecretStore';
import { WebDavSettingsStore } from './WebDavSettingsStore';

export class WebDavBookService {
  static async ensureCached(context: Context, book: Book,
    onProgress?: (message: string, percent: number) => void): Promise<Book> {
    if (!LocalBookService.isWebDavBook(book)) return book;
    const cacheReady = WebDavBookService.cacheReady(book);
    const checkedAt = Math.max(0, Number(book.getVariable('webdavCheckedAt')) || 0);
    if (cacheReady && Date.now() - checkedAt < 10 * 60 * 1000) return book;
    const connectionId = book.getVariable('webdavConnectionId');
    const remotePath = book.getVariable('webdavRemotePath');
    const connections = await WebDavSettingsStore.loadConnections(context);
    const connection = connections.find((item: WebDavConnection): boolean => item.id === connectionId);
    if (!connection) {
      if (cacheReady) return book;
      throw new Error('找不到此书对应的 WebDAV 连接，请先恢复或重新配置连接');
    }
    const password = await WebDavSecretStore.password(context, connection.id);
    if (!password) {
      if (cacheReady) return book;
      throw new Error('WebDAV 密码未保存，请先在 WebDAV 设置中重新输入');
    }
    try {
      if (onProgress) onProgress('正在检查远程书籍...', 5);
      const client = new WebDavClient(connection, password, 30000);
      const info = await client.headLibraryFile(remotePath);
      if (!info.exists) {
        if (cacheReady) return book;
        throw new Error('WebDAV 上的原始书籍已不存在');
      }
      const entry = new WebDavEntry();
      entry.name = WebDavBookService.fileName(remotePath);
      entry.relativePath = remotePath;
      entry.size = info.size;
      entry.lastModified = info.lastModified;
      entry.etag = info.etag;
      entry.contentType = info.contentType;
      const result = await WebDavBookService.openOrImport(context, connection, password, entry, onProgress);
      result.putVariable('webdavCheckedAt', `${Date.now()}`);
      await AppDatabase.getInstance().updateBook(result, false);
      return result;
    } catch (error) {
      if (cacheReady) return book;
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  static async openOrImport(context: Context, connection: WebDavConnection, password: string,
    entry: WebDavEntry, onProgress?: (message: string, percent: number) => void): Promise<Book> {
    if (!entry || entry.directory || !entry.readableBook()) throw new Error('仅支持 TXT、EPUB 和 MOBI 文件');
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const bookUrl = LocalBookService.webDavBookUrl(connection.id, entry.relativePath);
    const existing = await db.getBook(bookUrl);
    if (existing && WebDavBookService.cacheReady(existing) &&
      WebDavBookService.remoteVersionMatches(existing, entry)) {
      if (onProgress) onProgress('正在打开本地缓存...', 100);
      return existing;
    }

    const tempRoot = `${context.tempDir}/webdav_book_${Date.now()}`;
    const tempPath = `${tempRoot}/source.${entry.format()}`;
    if (!fs.accessSync(tempRoot)) fs.mkdirSync(tempRoot, true);
    try {
      if (onProgress) onProgress('正在下载远程书籍...', 2);
      const client = new WebDavClient(connection, password, 30000);
      const downloaded = await client.downloadLibraryFile(entry.relativePath, tempPath,
        (received: number, total: number): void => {
          const ratio = total > 0 ? received / total : 0;
          if (onProgress) onProgress('正在下载远程书籍...', 2 + Math.min(73, Math.floor(ratio * 73)));
        });
      if (entry.size > 0 && downloaded.size !== entry.size) throw new Error('远程书籍下载长度不完整');
      if (onProgress) onProgress('正在解析书籍...', 78);
      const book = await LocalBookService.importWebDavBook(context, tempPath, connection.id,
        entry.relativePath, entry.name, entry.format(), downloaded.etag || entry.etag,
        downloaded.lastModified || entry.lastModified, downloaded.size || entry.size);
      if (onProgress) onProgress('书籍已加入书架', 100);
      return book;
    } finally {
      WebDavBookService.removeTree(tempRoot);
    }
  }

  static cacheReady(book: Book): boolean {
    if (!LocalBookService.isWebDavBook(book)) return false;
    const path = book.getVariable('localFilePath');
    try {
      return !!path && fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  static remoteVersionMatches(book: Book, entry: WebDavEntry): boolean {
    const storedEtag = book.getVariable('webdavETag');
    if (storedEtag && entry.etag) return storedEtag === entry.etag;
    const size = Math.max(0, Number(book.getVariable('webdavRemoteSize')) || 0);
    const modified = Math.max(0, Number(book.getVariable('webdavLastModified')) || 0);
    return size === entry.size && modified === entry.lastModified;
  }

  private static removeTree(path: string): void {
    try {
      if (!path || !fs.accessSync(path)) return;
      const stat = fs.statSync(path);
      if (!stat.isDirectory()) {
        fs.unlinkSync(path);
        return;
      }
      for (const name of fs.listFileSync(path)) WebDavBookService.removeTree(`${path}/${name}`);
      fs.rmdirSync(path);
    } catch (_) {}
  }

  private static fileName(path: string): string {
    const value = (path || '').replace(/\\/g, '/');
    const index = value.lastIndexOf('/');
    return index >= 0 ? value.substring(index + 1) : value;
  }
}
