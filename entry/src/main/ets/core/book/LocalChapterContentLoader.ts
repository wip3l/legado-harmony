import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { Book, BookChapter } from '../../model/data/Book';
import { ReaderImageMarker } from './ReaderImageMarker';

export class LocalChapterContentLoader {
  static async load(book: Book, chapter: BookChapter): Promise<string> {
    if (book.origin !== 'local' || book.type !== 2) return '';
    const path = (chapter.resourceUrl || '').trim();
    const extractRoot = this.normalizePath(book.getVariable('localExtractRoot'));
    const normalizedPath = this.normalizePath(path);
    if (!normalizedPath || !extractRoot || !normalizedPath.startsWith(`${extractRoot}/`) || !this.exists(normalizedPath)) {
      return '';
    }
    if (/\.(?:avif|bmp|gif|jpe?g|png|svg|webp)$/i.test(this.withoutFragment(normalizedPath))) {
      return ReaderImageMarker.create(normalizedPath);
    }
    const html = await this.readUtf8File(normalizedPath);
    return this.htmlToReaderContent(html, this.parentPath(normalizedPath));
  }

  private static async readUtf8File(path: string): Promise<string> {
    const stat = await fs.stat(path);
    if (stat.size <= 0) return '';
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer), { stream: false });
    } finally {
      await fs.close(file);
    }
  }

  private static htmlToReaderContent(html: string, baseDir: string): string {
    const body = html.match(/<body\b[^>]*>([\s\S]*?)<\/body>/i);
    const source = (body ? body[1] : html)
      .replace(/<(?:img|image)\b[^>]*>/gi, (tag: string): string => {
        return this.imageTagToMarker(tag, baseDir, ['src', 'xlink:href', 'href']);
      })
      .replace(/<object\b[^>]*>/gi, (tag: string): string => {
        return this.imageTagToMarker(tag, baseDir, ['data']);
      });
    return this.decodeEntities(source
      .replace(/<script\b[\s\S]*?<\/script>/gi, '')
      .replace(/<style\b[\s\S]*?<\/style>/gi, '')
      .replace(/<(?:br|hr)\b[^>]*\/?>/gi, '\n')
      .replace(/<\/(?:p|div|section|article|h[1-6]|li|blockquote)>/gi, '\n')
      .replace(/<li\b[^>]*>/gi, '　• ')
      .replace(/<[^>]+>/g, ''))
      .replace(/\r\n?/g, '\n')
      .replace(/[ \t\u00A0]+\n/g, '\n')
      .replace(/\n[ \t\u00A0]+/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private static imageTagToMarker(tag: string, baseDir: string, attributes: string[]): string {
    const source = this.findHtmlAttribute(tag, attributes);
    if (!source || /^(?:data:|https?:)/i.test(source)) return ' ';
    if (/^<object\b/i.test(tag)) {
      const mediaType = this.findHtmlAttribute(tag, ['type']).toLowerCase();
      const cleanSource = this.withoutFragment(source).toLowerCase();
      if (!mediaType.startsWith('image/') && !/\.(?:avif|bmp|gif|jpe?g|png|svg|webp)$/.test(cleanSource)) {
        return ' ';
      }
    }
    const path = this.resolveBookPath(baseDir, this.decodeEntities(source));
    return path && this.exists(path) ? `\n\n${ReaderImageMarker.create(path)}\n\n` : ' ';
  }

  private static findHtmlAttribute(tag: string, names: string[]): string {
    for (const name of names) {
      const escaped = name.replace(':', '\\:');
      const quoted = new RegExp(`(?:^|\\s)${escaped}\\s*=\\s*["']([^"']+)["']`, 'i').exec(tag);
      if (quoted && quoted[1]) return quoted[1];
      const unquoted = new RegExp(`(?:^|\\s)${escaped}\\s*=\\s*([^\\s>]+)`, 'i').exec(tag);
      if (unquoted && unquoted[1]) return unquoted[1];
    }
    return '';
  }

  private static decodeEntities(value: string): string {
    const named: Record<string, string> = {};
    named['amp'] = '&';
    named['lt'] = '<';
    named['gt'] = '>';
    named['quot'] = '"';
    named['apos'] = "'";
    named['nbsp'] = ' ';
    return (value || '').replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi,
      (raw: string, entity: string): string => {
        const lower = entity.toLowerCase();
        if (lower.startsWith('#x')) return String.fromCharCode(parseInt(lower.substring(2), 16));
        if (lower.startsWith('#')) return String.fromCharCode(parseInt(lower.substring(1), 10));
        return named[lower] ?? raw;
      });
  }

  private static resolveBookPath(baseDir: string, value: string): string {
    const clean = this.withoutFragment((value || '').replace(/\\/g, '/'));
    if (!clean) return '';
    if (clean.startsWith('/')) return this.normalizePath(clean);
    return this.normalizePath(`${baseDir}/${clean}`);
  }

  private static normalizePath(value: string): string {
    const source = (value || '').replace(/\\/g, '/');
    const prefix = source.startsWith('/') ? '/' : '';
    const parts: string[] = [];
    for (const part of source.split('/')) {
      if (!part || part === '.') continue;
      if (part === '..') {
        if (parts.length > 0) parts.pop();
      } else {
        parts.push(part);
      }
    }
    return prefix + parts.join('/');
  }

  private static parentPath(path: string): string {
    const normalized = this.normalizePath(path);
    const index = normalized.lastIndexOf('/');
    return index > 0 ? normalized.substring(0, index) : normalized;
  }

  private static withoutFragment(value: string): string {
    const index = (value || '').indexOf('#');
    return index >= 0 ? value.substring(0, index) : value;
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }
}
