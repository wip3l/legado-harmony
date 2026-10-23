import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { appDb } from '../model/data/AppDatabase';
import { Book } from '@legado/sourceengine';
import { LocalBookService } from '../core/book/LocalBookService';
import { OpdsLink, OpdsServerConfig, opdsFormatOfType } from './OpdsModels';
import { OpdsClient, OpdsDownloadHandle } from './OpdsClient';
import { OpdsError } from './OpdsError';

export class OpdsBookService {
  static bookIdentityUrl(serverId: string, acquisitionUrl: string): string {
    return LocalBookService.opdsBookUrl(serverId, acquisitionUrl);
  }

  static formatOfLink(link: OpdsLink): string {
    const fromType = opdsFormatOfType(link.type);
    if (fromType) return fromType;
    const mediaType = (link.type || '').split(';')[0].trim().toLowerCase();
    if (mediaType && mediaType !== 'application/octet-stream') return '';
    const href = (link.href || '').split('?')[0].split('#')[0].toLowerCase();
    if (href.endsWith('.epub')) return 'epub';
    if (href.endsWith('.mobi')) return 'mobi';
    if (href.endsWith('.txt')) return 'txt';
    return '';
  }

  static isDownloadableFormat(format: string): boolean {
    return format === 'epub' || format === 'txt' || format === 'mobi';
  }

  static async isAlreadyImported(serverId: string, acquisitionUrl: string): Promise<boolean> {
    const identity = OpdsBookService.bookIdentityUrl(serverId, acquisitionUrl);
    const book = await appDb.getBook(identity);
    return !!book;
  }

  static async downloadAndImport(context: Context, server: OpdsServerConfig, password: string,
    link: OpdsLink, bookName: string,
    onProgress?: (received: number, total: number) => void,
    handleSink?: (handle: OpdsDownloadHandle) => void): Promise<Book> {
    const format = OpdsBookService.formatOfLink(link);
    if (!OpdsBookService.isDownloadableFormat(format)) {
      throw new OpdsError('unknown', '仅支持下载 EPUB、TXT 和 MOBI');
    }
    await appDb.initWithContext(context);
    const tempRoot = `${context.tempDir}/opds_book_${Date.now()}`;
    const tempPath = `${tempRoot}/source.${format}`;
    if (!fs.accessSync(tempRoot)) fs.mkdirSync(tempRoot, true);
    try {
      const client = new OpdsClient(server, password);
      const handle = client.downloadBook(link.href, tempPath, onProgress);
      if (handleSink) handleSink(handle);
      await handle.promise;
      const stat = await fs.stat(tempPath);
      const totalSize = Math.max(0, stat.size);
      return await LocalBookService.importOpdsBook(context, tempPath, server.id, bookName, format,
        link.href, totalSize);
    } finally {
      OpdsBookService.removeTree(tempRoot);
    }
  }

  private static removeTree(path: string): void {
    try {
      if (!path || !fs.accessSync(path)) return;
      const stat = fs.statSync(path);
      if (!stat.isDirectory()) {
        fs.unlinkSync(path);
        return;
      }
      for (const name of fs.listFileSync(path)) OpdsBookService.removeTree(`${path}/${name}`);
      fs.rmdirSync(path);
    } catch (_) {}
  }
}
