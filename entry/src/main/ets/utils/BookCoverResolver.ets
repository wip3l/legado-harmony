import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { Book } from '@legado/sourceengine';
import { CoverGallerySettings } from './CoverGallerySettings';
import { CoverGallerySnapshot, CoverGalleryStore } from './CoverGalleryStore';
import { ThemeBookCoverSettings } from './ThemeBookCoverSettings';
import { BookCoverCache } from './BookCoverCache';

/** 非 UI 场景（媒体信息、桌面卡片、局域网）也从书架规则取图。静态载体取轮播首张。 */
export class BookCoverResolver {
  private static themeFiles: Map<number, Promise<string>> = new Map();

  static sourceCovers(book: Book, darkMode: boolean,
    settings: CoverGallerySnapshot = CoverGalleryStore.snapshotFromStorage()): string[] {
    return CoverGallerySettings.getDisplayCoverList(book, darkMode, settings.albumsRaw,
      settings.lightAlbumId, settings.darkAlbumId, settings.applyScope, settings.targetBooksRaw,
      settings.ignoreSourceCover, settings.coverMode);
  }

  static first(book: Book | null, darkMode: boolean = AppStorage.get<boolean>('appDarkMode') || false,
    settings: CoverGallerySnapshot = CoverGalleryStore.snapshotFromStorage()): ResourceStr {
    if (!book) return '';
    if (ThemeBookCoverSettings.enabled(darkMode, AppStorage.get<boolean>('appThemeBookCoverEnabled') || false)) {
      return ThemeBookCoverSettings.covers(book, darkMode)[0] || '';
    }
    return BookCoverResolver.sourceCovers(book, darkMode, settings)[0] || '';
  }

  /** 把主题资源和普通封面统一转换为本地文件，供系统媒体和桌面卡片使用。 */
  static async prepareFile(context: Context, cover: ResourceStr): Promise<string> {
    if (typeof cover === 'string') return cover ? BookCoverCache.prepareCoverFile(context, cover) : '';
    const existing = BookCoverResolver.themeFiles.get(cover.id);
    if (existing) {
      const path = await existing;
      if (await fs.access(path)) return path;
      BookCoverResolver.themeFiles.delete(cover.id);
    }
    const task = BookCoverResolver.writeThemeFile(context, cover);
    BookCoverResolver.themeFiles.set(cover.id, task);
    try {
      return await task;
    } catch (error) {
      BookCoverResolver.themeFiles.delete(cover.id);
      throw new Error(String(error));
    }
  }

  private static async writeThemeFile(context: Context, cover: Resource): Promise<string> {
    const bytes = await context.resourceManager.getMediaContent(cover.id);
    const path = `${context.cacheDir}/book_theme_cover_${cover.id}.img`;
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
    } finally {
      await fs.close(file);
    }
    return path;
  }
}
