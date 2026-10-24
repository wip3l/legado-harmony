import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import http from '@ohos.net.http';
import { HttpClient, SourceCoverLoader, SourceCoverUrl } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { CoverUrlNormalizer } from './CoverUrlNormalizer';

export class BookCoverCache {
  private static resolvedCoverUris: Map<string, string> = new Map();
  private static inFlightResolutions: Map<string, Promise<string>> = new Map();
  private static activeNetworkTasks: number = 0;
  private static writeSerial: number = 0;
  private static readonly MAX_NETWORK_TASKS: number = 4;
  private static networkWaiters: Array<() => void> = [];
  // 书源声明了 coverDecode 的封面：地址带 SourceCoverUrl 标记，下载后要用该书源的参数解密才是图片。
  private static sourceCoverHttp: HttpClient | null = null;
  private static sourceCoverFailedAt: Map<string, number> = new Map();
  private static readonly SOURCE_COVER_RETRY_MS: number = 60000;
  private static sourceCoverRevisionTimer: number = -1;

  /**
   * Cover address an Image can load. An encrypted source cover is never handed to Image directly: until its
   * decrypted copy is cached this returns '' (callers show their placeholder) and starts decrypting in the
   * background; when that finishes, AppStorage `sourceCoverRevision` is bumped so views that read it re-render.
   * Other addresses are returned unchanged.
   */
  static displayCover(context: Context, raw: string): string {
    if (!raw || !SourceCoverUrl.isEncoded(raw)) return raw;
    const cached = BookCoverCache.resolveCachedCover(context, raw);
    if (cached) return cached;
    const failedAt = BookCoverCache.sourceCoverFailedAt.get(raw) || 0;
    if (!BookCoverCache.inFlightResolutions.has(raw) && Date.now() - failedAt > BookCoverCache.SOURCE_COVER_RETRY_MS) {
      BookCoverCache.resolveCover(context, raw).then((resolved: string) => {
        if (resolved) {
          BookCoverCache.sourceCoverFailedAt.delete(raw);
          BookCoverCache.bumpSourceCoverRevision();
        } else {
          BookCoverCache.sourceCoverFailedAt.set(raw, Date.now());
        }
      }).catch(() => {
        BookCoverCache.sourceCoverFailedAt.set(raw, Date.now());
      });
    }
    return '';
  }

  /** Decrypted bytes of an encrypted source cover, or null when the source is missing or decoding fails. */
  static async loadSourceCoverBytes(raw: string): Promise<Uint8Array | null> {
    try {
      const source = await AppDatabase.getInstance().getBookSource(SourceCoverUrl.source(raw));
      if (!source) return null;
      if (!BookCoverCache.sourceCoverHttp) BookCoverCache.sourceCoverHttp = new HttpClient(15000);
      const data = await SourceCoverLoader.load(BookCoverCache.sourceCoverHttp, source, raw);
      return data.byteLength > 0 ? data : null;
    } catch (e) {
      console.warn('解密书源封面失败:', e instanceof Error ? e.message : String(e));
      return null;
    }
  }

  private static bumpSourceCoverRevision(): void {
    // 一屏封面陆续解密完成时合并成一次刷新。
    if (BookCoverCache.sourceCoverRevisionTimer !== -1) return;
    BookCoverCache.sourceCoverRevisionTimer = setTimeout(() => {
      BookCoverCache.sourceCoverRevisionTimer = -1;
      AppStorage.setOrCreate<number>('sourceCoverRevision', (AppStorage.get<number>('sourceCoverRevision') || 0) + 1);
    }, 200);
  }

  static resolveCachedCover(context: Context, raw: string): string {
    if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) {
      return '';
    }
    const remembered = BookCoverCache.resolvedCoverUris.get(raw);
    if (remembered && BookCoverCache.exists(BookCoverCache.cachedCoverPath(context, raw))) return remembered;
    BookCoverCache.resolvedCoverUris.delete(raw);
    const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
    if (!BookCoverCache.exists(cachedPath)) return '';
    const resolved = fileUri.getUriFromPath(cachedPath);
    BookCoverCache.resolvedCoverUris.set(raw, resolved);
    return resolved;
  }

  static async resolveCachedCoverAsync(context: Context, raw: string): Promise<string> {
    if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) return '';
    const remembered = BookCoverCache.resolvedCoverUris.get(raw);
    if (remembered && await BookCoverCache.existsAsync(BookCoverCache.cachedCoverPath(context, raw))) return remembered;
    BookCoverCache.resolvedCoverUris.delete(raw);
    const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
    if (!(await BookCoverCache.existsAsync(cachedPath))) return '';
    const resolved = fileUri.getUriFromPath(cachedPath);
    BookCoverCache.resolvedCoverUris.set(raw, resolved);
    return resolved;
  }

  static async resolveCover(context: Context, raw: string): Promise<string> {
    const active = BookCoverCache.inFlightResolutions.get(raw);
    if (active) return await active;
    const task = BookCoverCache.resolveCoverInternal(context, raw);
    BookCoverCache.inFlightResolutions.set(raw, task);
    try {
      return await task;
    } finally {
      if (BookCoverCache.inFlightResolutions.get(raw) === task) {
        BookCoverCache.inFlightResolutions.delete(raw);
      }
    }
  }

  private static async resolveCoverInternal(context: Context, raw: string): Promise<string> {
    if (!raw) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
      if (await BookCoverCache.existsAsync(cachedPath)) {
        const resolved = fileUri.getUriFromPath(cachedPath);
        BookCoverCache.resolvedCoverUris.set(raw, resolved);
        return resolved;
      }
      const path = await BookCoverCache.downloadCover(context, raw);
      if (!path) return SourceCoverUrl.isEncoded(raw) ? '' : raw;
      const resolved = fileUri.getUriFromPath(path);
      BookCoverCache.resolvedCoverUris.set(raw, resolved);
      return resolved;
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (localPath && await BookCoverCache.existsAsync(localPath)) {
      return raw.startsWith('file://') ? raw : fileUri.getUriFromPath(localPath);
    }
    const copiedPath = await BookCoverCache.copyCoverUriToCache(context, raw);
    if (copiedPath) {
      return fileUri.getUriFromPath(copiedPath);
    }
    return raw;
  }

  static async prepareCoverFile(context: Context, raw: string): Promise<string> {
    if (!raw) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
      if (await BookCoverCache.existsAsync(cachedPath)) {
        return cachedPath;
      }
      return await BookCoverCache.downloadCover(context, raw);
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (localPath && await BookCoverCache.existsAsync(localPath)) {
      return localPath;
    }
    return await BookCoverCache.copyCoverUriToCache(context, raw);
  }

  static deleteCachedCover(context: Context, raw: string): void {
    if (!raw) {
      return;
    }
    BookCoverCache.resolvedCoverUris.delete(raw);
    BookCoverCache.sourceCoverFailedAt.delete(raw);
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      BookCoverCache.deletePath(BookCoverCache.cachedCoverPath(context, raw));
      return;
    }
    BookCoverCache.deletePath(BookCoverCache.cachedCoverPath(context, raw));
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (!localPath || !BookCoverCache.isAppOwnedPath(context, localPath)) {
      return;
    }
    BookCoverCache.deletePath(localPath);
  }

  // 调用方自行取回的封面（如需要登录凭据的书库）落到同一份缓存里。
  static async storeCover(context: Context, raw: string, data: Uint8Array): Promise<string> {
    if (!raw || data.byteLength === 0) return '';
    await BookCoverCache.ensureDirAsync(`${context.cacheDir}/book_covers`);
    const path = BookCoverCache.cachedCoverPath(context, raw);
    await BookCoverCache.writeFile(path, data);
    const resolved = fileUri.getUriFromPath(path);
    BookCoverCache.resolvedCoverUris.set(raw, resolved);
    return resolved;
  }

  private static async downloadCover(context: Context, url: string): Promise<string> {
    const dir = `${context.cacheDir}/book_covers`;
    await BookCoverCache.ensureDirAsync(dir);
    const path = BookCoverCache.cachedCoverPath(context, url);
    if (await BookCoverCache.existsAsync(path)) {
      return path;
    }
    await BookCoverCache.acquireNetworkSlot();
    try {
      // Another request may have completed while this one waited for a slot.
      if (await BookCoverCache.existsAsync(path)) return path;
      if (SourceCoverUrl.isEncoded(url)) {
        const data = await BookCoverCache.loadSourceCoverBytes(url);
        if (!data) return '';
        await BookCoverCache.writeFile(path, data);
        return path;
      }
      const candidates = CoverUrlNormalizer.downloadCandidates(url);
      for (const requestUrl of candidates) {
        const request = http.createHttp();
        try {
          const response = await request.request(requestUrl, {
            method: http.RequestMethod.GET,
            connectTimeout: 10000,
            readTimeout: 10000,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            header: {
              'User-Agent': 'Mozilla/5.0 (Linux; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
              'Referer': BookCoverCache.refererFromUrl(requestUrl),
              'Origin': BookCoverCache.originFromUrl(requestUrl)
            }
          });
          if (response.responseCode < 200 || response.responseCode >= 300 || !(response.result instanceof ArrayBuffer)) {
            continue;
          }
          if (response.result.byteLength === 0) continue;
          await BookCoverCache.writeFile(path, new Uint8Array(response.result));
          return path;
        } catch (e) {
          console.warn('下载书籍封面失败:', e);
        } finally {
          request.destroy();
        }
      }
      return '';
    } finally {
      BookCoverCache.releaseNetworkSlot();
    }
  }

  private static async writeFile(path: string, data: Uint8Array): Promise<void> {
    if (data.byteLength === 0) throw new Error('Empty cover image');
    // 最终路径只在完整写入并关闭后出现，其他封面刷新不能读到半张图片。
    const temporary = `${path}.part-${++BookCoverCache.writeSerial}`;
    try {
      const file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < data.byteLength) {
          const bytes = data.buffer.slice(data.byteOffset + offset, data.byteOffset + data.byteLength);
          const written = await fs.write(file.fd, bytes);
          if (written <= 0) throw new Error('Incomplete cover image write');
          offset += written;
        }
      } finally {
        await fs.close(file);
      }
      await fs.rename(temporary, path);
    } finally {
      // 失败只清理临时文件，不能损坏此前已完成的缓存。
      try { await fs.unlink(temporary); } catch (_) {}
    }
  }

  private static async acquireNetworkSlot(): Promise<void> {
    if (BookCoverCache.activeNetworkTasks < BookCoverCache.MAX_NETWORK_TASKS) {
      BookCoverCache.activeNetworkTasks++;
      return;
    }
    await new Promise<void>((resolve) => {
      BookCoverCache.networkWaiters.push(resolve);
    });
  }

  private static releaseNetworkSlot(): void {
    const next = BookCoverCache.networkWaiters.shift();
    if (next) {
      next();
      return;
    }
    BookCoverCache.activeNetworkTasks = Math.max(0, BookCoverCache.activeNetworkTasks - 1);
  }

  private static async copyCoverUriToCache(context: Context, raw: string): Promise<string> {
    if (!raw || raw.startsWith('http://') || raw.startsWith('https://')) {
      return '';
    }
    const dir = `${context.cacheDir}/book_covers`;
    await BookCoverCache.ensureDirAsync(dir);
    const path = BookCoverCache.cachedCoverPath(context, raw);
    if (await BookCoverCache.existsAsync(path)) {
      return path;
    }
    try {
      const source = raw.startsWith('/') ? fileUri.getUriFromPath(raw) : raw;
      await fs.copy(source, fileUri.getUriFromPath(path));
      return await BookCoverCache.existsAsync(path) ? path : '';
    } catch (e) {
      console.warn('复制书籍封面到缓存失败:', e);
      BookCoverCache.deletePath(path);
      return '';
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
      return fs.statSync(path).size > 0;
    } catch (e) {
      return false;
    }
  }

  private static async existsAsync(path: string): Promise<boolean> {
    try {
      return (await fs.stat(path)).size > 0;
    } catch (e) {
      return false;
    }
  }

  private static async ensureDirAsync(path: string): Promise<void> {
    try {
      await fs.mkdir(path, true);
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

  private static originFromUrl(url: string): string {
    const match = url.match(/^(https?:\/\/[^\/]+)/);
    return match ? match[1] : '';
  }

  private static refererFromUrl(url: string): string {
    const origin = BookCoverCache.originFromUrl(url);
    return origin ? `${origin}/` : '';
  }

  private static hashText(value: string): string {
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = value.charCodeAt(i) + ((hash << 5) - hash);
    }
    return Math.abs(hash).toString(16);
  }
}
