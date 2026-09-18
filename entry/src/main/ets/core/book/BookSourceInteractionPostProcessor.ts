import { Book, BookChapter, BookSource } from '../../model/data/Book';
import { BookSourceRuntimeSnapshotStore } from './BookSourceRuntimeSnapshot';

const INTERACTION_SETTING_KEYS: string[] = ['段评开关', '章评开关', '章名段评', '本章讨论',
  '作者评论', '热门评论', '本章说开关', '神评论开关', '书旗评论 API Key'];

/**
 * Reader content is returned exactly as produced by the imported source rules. The application
 * does not identify a publisher, append a private comment service, or add platform credentials.
 * Generic HTML/content normalization remains in WebBookService.
 */
export class BookSourceInteractionPostProcessor {
  static shouldRequestParagraphComments(source: BookSource, chapter?: BookChapter): boolean {
    return false;
  }

  static shouldRequestGodComments(source: BookSource, chapter?: BookChapter): boolean {
    return false;
  }

  /**
   * Identity of the user-switchable interaction state that changes how a source renders chapter
   * content. It deliberately ignores the rest of `variable`/`loginInfo`: ordinary fetching rewrites
   * that blob with bookkeeping (device id, cached API domains, session timestamps), so treating the
   * whole snapshot as the identity marked every book as "source changed" and discarded durable
   * chapter caches on the next open — including after a restart.
   */
  static interactionCacheIdentity(source: BookSource): string {
    const script = `${source.contentRule?.content || ''}\n${source.jsLib || ''}`;
    // Sources without an interaction feature render the same content regardless of login state, so
    // they must never invalidate anything.
    if (!/段评|章评|评论|comment|review|showSqComments/i.test(script)) return '';
    const snapshot = BookSourceRuntimeSnapshotStore.get(source);
    const values: string[] = [];
    for (const key of INTERACTION_SETTING_KEYS) values.push(`${key}=${snapshot.getString(key)}`);
    if (/\bSQ_COMMENT_API_BASE\b/.test(script)) values.push('sqProvider=compact');
    return values.join('&');
  }

  static async process(source: BookSource, book: Book | null, chapter: BookChapter,
    content: string): Promise<string> {
    return content || '';
  }
}
