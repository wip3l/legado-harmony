import { Book } from '@legado/sourceengine';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';

/** 各页面共用主题封面的顺序和轮播间隔。 */
export class ThemeBookCoverSettings {
  static enabled(darkMode: boolean, enabled: boolean): boolean {
    return enabled && ThemeAssetRegistry.themeBookCovers(ThemeRuntime.bookTokens(darkMode).coverAssetId).length > 0;
  }

  static covers(book: Book, darkMode: boolean): ResourceStr[] {
    return ThemeBookCoverSettings.coversForAsset(book, ThemeRuntime.bookTokens(darkMode).coverAssetId);
  }

  static coversForAsset(book: Book, assetId: string): ResourceStr[] {
    const covers = ThemeAssetRegistry.themeBookCovers(assetId);
    if (covers.length <= 1) return covers;
    const result: ResourceStr[] = [];
    const seed = ThemeBookCoverSettings.seed(book);
    const start = seed % covers.length;
    const direction = seed % 2 === 0 ? 1 : covers.length - 1;
    for (let index = 0; index < covers.length; index++) {
      result.push(covers[(start + index * direction) % covers.length]);
    }
    return result;
  }

  static seed(book: Book): number {
    const key = `${book.bookUrl}|${book.name}|${book.author}`;
    let hash = 17;
    for (let index = 0; index < key.length; index++) hash = (hash * 31 + key.charCodeAt(index)) & 0x7FFFFFFF;
    return hash;
  }

  static interval(book: Book): number {
    return 3200 + ThemeBookCoverSettings.seed(book) % 5 * 420;
  }

  static frame(darkMode: boolean): ResourceStr {
    return ThemeAssetRegistry.themeShelfFrame(ThemeRuntime.bookTokens(darkMode).shelfFrameAssetId);
  }
}
