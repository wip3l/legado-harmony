import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { ReaderComicSuperResolutionAccess } from './ReaderComicSuperResolution';
import { ComicChineseDictionary } from './ComicChineseDictionary';
import { ComicTextRecognizer } from './ComicTextRecognizer';
import { ComicTextLayer, ComicTextResult } from './ComicTextTypes';

export class ComicChineseConverter {
  private static loading: Promise<ComicChineseDictionary> | null = null;

  /**
   * 漫画繁→简（会员专享，与超分同样的口径：任一有效档位）。取值同 ReaderComicSuperResolutionAccess；
   * 会员到期后保留本书开关，续费后自动恢复。
   */
  static access(): string {
    if (!ComicTextRecognizer.supported()) return ReaderComicSuperResolutionAccess.UNSUPPORTED;
    if (AccountSessionStore.activeMembershipSku() === '') return ReaderComicSuperResolutionAccess.MEMBER_REQUIRED;
    return ReaderComicSuperResolutionAccess.READY;
  }

  static async load(context: common.Context): Promise<ComicChineseDictionary> {
    if (!ComicChineseConverter.loading) {
      ComicChineseConverter.loading = ComicChineseConverter.read(context).catch((error: Error) => {
        ComicChineseConverter.loading = null;
        throw error;
      });
    }
    return await ComicChineseConverter.loading;
  }

  /** 阅读页的繁→简文字层：识别（有缓存）后只重写转换后有变化、且底色可安全覆盖的行。 */
  static async layer(context: common.Context, source: string, active: () => boolean): Promise<ComicTextLayer> {
    const result: ComicTextResult = await ComicTextRecognizer.recognize(context, source, active,
      (_done: number, _total: number): void => {});
    const dictionary = await ComicChineseConverter.load(context);
    const layer = ComicTextLayer.build(result, (text: string): string => dictionary.convert(text));
    // 只记数量，不写漫画原文和图片地址。
    console.info(`[ComicText] ${result.width}x${result.height} 识别 ${result.regions.length} 行，` +
      `改写 ${layer.patches.length} 行，底色不纯跳过 ${layer.skipped} 行，用时 ${result.elapsedMs}ms`);
    return layer;
  }

  private static async read(context: common.Context): Promise<ComicChineseDictionary> {
    const chars = await context.resourceManager.getRawFileContent('opencc/TSCharacters.txt');
    const phrases = await context.resourceManager.getRawFileContent('opencc/TSPhrases.txt');
    return new ComicChineseDictionary(
      util.TextDecoder.create('utf-8').decodeWithStream(chars, { stream: false }),
      util.TextDecoder.create('utf-8').decodeWithStream(phrases, { stream: false }));
  }
}
