import { ReaderActionMarker } from '@legado/sourceengine';
import { ReaderImageMarker } from '../book/ReaderImageMarker';
import { ReaderTextNormalizer } from './ReaderTextNormalizer';

export class ReaderChunkResult {
  pages: string[] = [];
  starts: number[] = [];
  ends: number[] = [];
}

/**
 * 列表式阅读（滚动阅读、漫画）的分块（纯逻辑）。列表项不需要贴合屏幕高度，按字符数切块即可：
 * 不做任何文本测量，结果一次算完，块边界落在段落之间，书源动作标记和图片标记保持完整。
 * 阅读进度按块索引和章内字符偏移保存，切块规则变化会让已保存的块索引失效。
 */
export class ReaderChunkPagination {
  static readonly TARGET_LENGTH: number = 1800;
  private static readonly MINIMUM_BREAK_LENGTH: number = Math.round(ReaderChunkPagination.TARGET_LENGTH * 0.55);
  private static readonly MAXIMUM_FORWARD_BREAK: number = Math.round(ReaderChunkPagination.TARGET_LENGTH * 0.35);

  /**
   * 动作标记是原子的。rawEnd 落在标记内部或紧贴行内标记之前时，把终点挪到不切开标记的位置：
   * 行内标记整体并入本块，独占一行的标记留给下一块（它正好在块首时则整体并入）。
   */
  static adjustActionMarkerEnd(source: string, start: number, rawEnd: number): number {
    const end = Math.max(start + 1, Math.min(rawEnd, source.length));
    let searchStart = start;
    while (searchStart < end) {
      let markerStart = -1;
      for (const prefix of [ReaderActionMarker.PREFIX, ReaderActionMarker.LEGACY_PREFIX,
        ReaderActionMarker.ORIGINAL_PREFIX]) {
        const index = source.indexOf(prefix, searchStart);
        if (index >= 0 && (markerStart < 0 || index < markerStart)) markerStart = index;
      }
      if (markerStart < 0) return end;
      const suffix = source.indexOf(ReaderActionMarker.SUFFIX, markerStart);
      if (suffix < 0) return end;
      const markerEnd = suffix + ReaderActionMarker.SUFFIX.length;
      const previousChar = markerStart > 0 ? source.charAt(markerStart - 1) : '';
      const inlineMarker = markerStart > 0 && previousChar !== '\n' && previousChar !== '\r';
      if (markerStart === end) {
        return inlineMarker ? markerEnd : end;
      }
      if (markerStart > end) return end;
      if (end < markerEnd) {
        return inlineMarker ? markerEnd : (markerStart > start ? markerStart : markerEnd);
      }
      searchStart = markerEnd;
    }
    return end;
  }

  /** 滚动阅读：整章按约 TARGET_LENGTH 字切块。图片标记留在所在的块里，由排版引擎当作图片块处理。 */
  static splitContinuous(source: string): ReaderChunkResult {
    const text = source || '';
    const result = new ReaderChunkResult();
    ReaderChunkPagination.appendTextChunks(text, 0, text.length, result);
    ReaderChunkPagination.ensureNotEmpty(text, result);
    return result;
  }

  /** 漫画：每张图片独占一块，图片之间的文字（说明、报错提示）按滚动阅读的规则切块。 */
  static splitComic(source: string): ReaderChunkResult {
    const text = source || '';
    const result = new ReaderChunkResult();
    let cursor = 0;
    while (cursor < text.length) {
      const markerStart = text.indexOf(ReaderImageMarker.PREFIX, cursor);
      const suffix = markerStart < 0 ? -1 :
        text.indexOf(ReaderImageMarker.SUFFIX, markerStart + ReaderImageMarker.PREFIX.length);
      if (markerStart < 0 || suffix < 0) {
        ReaderChunkPagination.appendTextChunks(text, cursor, text.length, result);
        break;
      }
      ReaderChunkPagination.appendTextChunks(text, cursor, markerStart, result);
      const markerEnd = suffix + ReaderImageMarker.SUFFIX.length;
      result.pages.push(text.substring(markerStart, markerEnd));
      result.starts.push(markerStart);
      result.ends.push(markerEnd);
      cursor = markerEnd;
    }
    ReaderChunkPagination.ensureNotEmpty(text, result);
    return result;
  }

  private static ensureNotEmpty(text: string, result: ReaderChunkResult): void {
    if (result.pages.length > 0 || !text) return;
    result.pages.push(text);
    result.starts.push(0);
    result.ends.push(text.length);
  }

  private static appendTextChunks(source: string, from: number, to: number,
    result: ReaderChunkResult): void {
    let cursor = from;
    while (cursor < to) {
      while (cursor < to && ReaderTextNormalizer.isPageStartTrimChar(source.charAt(cursor))) {
        cursor++;
      }
      if (cursor >= to) break;
      let end = Math.min(to, cursor + ReaderChunkPagination.TARGET_LENGTH);
      if (end < to) {
        const backwardBreak = source.lastIndexOf('\n', end);
        if (backwardBreak >= cursor + ReaderChunkPagination.MINIMUM_BREAK_LENGTH) {
          end = backwardBreak;
        } else {
          const forwardBreak = source.indexOf('\n', end);
          if (forwardBreak > end && forwardBreak <= end + ReaderChunkPagination.MAXIMUM_FORWARD_BREAK &&
            forwardBreak <= to) {
            end = forwardBreak;
          }
        }
        end = Math.min(to, ReaderChunkPagination.adjustActionMarkerEnd(source, cursor, end));
      }
      if (end <= cursor) end = Math.min(to, cursor + ReaderChunkPagination.TARGET_LENGTH);
      ReaderTextNormalizer.pushPage(source, cursor, end, result.pages, result.starts, result.ends);
      cursor = Math.max(cursor + 1, end);
    }
  }
}
