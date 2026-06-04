import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import http from '@ohos.net.http';

export class BookCoverCache {
  static async resolveCover(context: Context, raw: string): Promise<string> {
    if (!raw) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      const path = await BookCoverCache.downloadCover(context, raw);
      return path ? fileUri.getUriFromPath(path) : raw;
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (localPath && BookCoverCache.exists(localPath)) {
      return raw.startsWith('file://') ? raw : fileUri.getUriFromPath(localPath);
    }
    return raw;
  }

  static async prepareCoverFile(context: Context, raw: string): Promise<string> {
    if (!raw) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return await BookCoverCache.downloadCover(context, raw);
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    return localPath && BookCoverCache.exists(localPath) ? localPath : '';
  }

  static deleteCachedCover(context: Context, raw: string): void {
    if (!raw) {
      return;
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      BookCoverCache.deletePath(BookCoverCache.cachedCoverPath(context, raw));
      return;
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (!localPath || !BookCoverCache.isAppOwnedPath(context, localPath)) {
      return;
    }
    BookCoverCache.deletePath(localPath);
  }

  private static async downloadCover(context: Context, url: string): Promise<string> {
    const dir = `${context.cacheDir}/book_covers`;
    BookCoverCache.ensureDir(dir);
    const path = BookCoverCache.cachedCoverPath(context, url);
    if (BookCoverCache.exists(path)) {
      return path;
    }
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8'
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || !(response.result instanceof ArrayBuffer)) {
        return '';
      }
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, response.result);
      } finally {
        fs.closeSync(file);
      }
      return path;
    } catch (e) {
      console.warn('下载书籍封面失败:', e);
      return '';
    } finally {
      request.destroy();
    }
  }

  private static localPathFromUri(raw: string): string {
    if (raw.startsWith('file://')) {
      return decodeURIComponent(raw.substring('file://'.length));
    }
    return raw.startsWith('/') ? raw : '';
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private static ensureDir(path: string): void {
    try {
      fs.mkdirSync(path, true);
    } catch (e) {
    }
  }

  private static cachedCoverPath(context: Context, url: string): string {
    return `${context.cacheDir}/book_covers/${BookCoverCache.hashText(url)}${BookCoverCache.coverExt(url)}`;
  }

  private static isAppOwnedPath(context: Context, path: string): boolean {
    return path.startsWith(`${context.filesDir}/covers/`) || path.startsWith(`${context.cacheDir}/book_covers/`);
  }

  private static deletePath(path: string): void {
    try {
      if (path && BookCoverCache.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.warn('删除书籍封面缓存失败:', e);
    }
  }

  private static coverExt(value: string): string {
    const lower = value.toLowerCase();
    if (lower.includes('.png')) return '.png';
    if (lower.includes('.webp')) return '.webp';
    if (lower.includes('.bmp')) return '.bmp';
    if (lower.includes('.gif')) return '.gif';
    return '.jpg';
  }

  private static hashText(value: string): string {
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = value.charCodeAt(i) + ((hash << 5) - hash);
    }
    return Math.abs(hash).toString(16);
  }
}
