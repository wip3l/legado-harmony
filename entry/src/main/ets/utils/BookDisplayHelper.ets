import { Book } from '../model/data/Book';
import { CoverUrlNormalizer } from './CoverUrlNormalizer';

class CoverData {
  covers: string[] = [];
}

export class BookDisplayHelper {
  static splitTags(kind?: string, customTag?: string): string[] {
    const tags: string[] = [];
    BookDisplayHelper.appendTags(tags, kind || '');
    BookDisplayHelper.appendTags(tags, customTag || '');
    return tags;
  }

  static joinTags(tags: string[]): string {
    const cleaned: string[] = [];
    for (const tag of tags) {
      const value = tag.trim();
      if (value && !cleaned.includes(value)) {
        cleaned.push(value);
      }
    }
    return cleaned.join(',');
  }

  static getBookTags(book: Book): string[] {
    const sourceTags = BookDisplayHelper.splitTags(book.kind, '');
    const customTokens = BookDisplayHelper.splitTags('', book.customTag);
    const hiddenTags: string[] = [];
    const customTags: string[] = [];
    for (const token of customTokens) {
      if (token.startsWith('!')) {
        const hidden = token.substring(1).trim();
        if (hidden && !hiddenTags.includes(hidden)) {
          hiddenTags.push(hidden);
        }
      } else if (token && !customTags.includes(token)) {
        customTags.push(token);
      }
    }
    const visible: string[] = [];
    for (const tag of sourceTags) {
      if (!hiddenTags.includes(tag) && !visible.includes(tag)) {
        visible.push(tag);
      }
    }
    for (const tag of customTags) {
      if (!visible.includes(tag)) {
        visible.push(tag);
      }
    }
    return visible;
  }

  static getLastUpdateText(book: Book): string {
    return BookDisplayHelper.extractLastUpdateText(book.kind);
  }

  static getCover(book: Book): string {
    const covers = BookDisplayHelper.getCoverList(book);
    if (covers.length > 0) {
      return BookDisplayHelper.pickCover(covers);
    }
    return CoverUrlNormalizer.normalize(book.coverUrl);
  }

  static getCoverList(book: Book): string[] {
    const customCovers = BookDisplayHelper.decodeCoverList(book.customCoverUrl);
    if (customCovers.length > 0) {
      return customCovers;
    }
    return BookDisplayHelper.cleanCoverList(book.coverUrl ? [book.coverUrl] : []);
  }

  static encodeCustomCovers(covers: string[]): string {
    const cleaned = BookDisplayHelper.cleanCoverList(covers);
    if (cleaned.length === 0) {
      return '';
    }
    if (cleaned.length === 1) {
      return cleaned[0];
    }
    const data = new CoverData();
    data.covers = cleaned;
    return JSON.stringify(data);
  }

  static decodeCoverList(raw?: string): string[] {
    const value = (raw || '').trim();
    if (!value) {
      return [];
    }
    if (!value.startsWith('{') && !value.startsWith('[')) {
      return BookDisplayHelper.cleanCoverList([value]);
    }
    try {
      const parsed = JSON.parse(value) as CoverData | string[];
      if (Array.isArray(parsed)) {
        return BookDisplayHelper.cleanCoverList(parsed as string[]);
      }
      return BookDisplayHelper.cleanCoverList((parsed as CoverData).covers || []);
    } catch (e) {
      return BookDisplayHelper.cleanCoverList([value]);
    }
  }

  static pickCover(covers: string[]): string {
    const cleaned = BookDisplayHelper.cleanCoverList(covers);
    if (cleaned.length === 0) {
      return '';
    }
    if (cleaned.length === 1) {
      return cleaned[0];
    }
    const index = Math.floor(Date.now() / 4000) % cleaned.length;
    return cleaned[index];
  }

  static getTagTextColor(index: number, darkMode: boolean): string {
    const dark = ['#8FB4FF', '#7DD89B', '#FFCA80', '#D6A4FF', '#80D8E8', '#FF9EA8'];
    const light = ['#3568D4', '#0A7D36', '#A15C00', '#7434A4', '#006C7A', '#B32636'];
    const palette = darkMode ? dark : light;
    return palette[index % palette.length];
  }

  static getTagBackgroundColor(index: number, darkMode: boolean): string {
    const dark = ['#1C3558', '#173B24', '#493114', '#351F49', '#173A40', '#4A2027'];
    const light = ['#EAF1FF', '#E8F5E9', '#FFF3E0', '#F3E8FF', '#E0F7FA', '#FCE8EA'];
    const palette = darkMode ? dark : light;
    return palette[index % palette.length];
  }

  private static appendTags(target: string[], raw: string): void {
    const normalized = BookDisplayHelper.removeUpdateText(raw)
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/gi, ' ')
      .replace(/[|/;；、，,·•●▪]+/g, ',')
      .replace(/\s*[:：]\s*/g, ',')
      .replace(/\s+/g, ',');
    const pieces = normalized.split(',');
    for (const piece of pieces) {
      const tag = piece.trim();
      if (tag && !target.includes(tag)) {
        target.push(tag);
      }
    }
  }

  private static extractLastUpdateText(raw: string): string {
    const value = raw || '';
    const labelledMatch = value.match(/(?:最后更新|更新时间|更新于|更新)\s*[:：]?\s*(\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}(?:日)?(?:\s+\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?)?)/);
    const dateTimeMatch = labelledMatch ? labelledMatch : value.match(/\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}(?:日)?(?:\s+\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?)?/);
    if (dateTimeMatch) {
      const matchText = labelledMatch ? dateTimeMatch[1] : dateTimeMatch[0];
      return matchText.replace(/[年月]/g, '-').replace(/日/g, '').replace(/：/g, ':').trim();
    }
    const relativeMatch = value.match(/(?:刚刚|\d+\s*(?:秒|分钟|小时|天|周|月|年)前|昨日|昨天|今天|前天)/);
    return relativeMatch ? relativeMatch[0].replace(/\s+/g, '') : '';
  }

  private static removeUpdateText(raw: string): string {
    return (raw || '')
      .replace(/(?:最后更新|更新时间|更新于|更新)\s*[:：]?\s*\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}(?:日)?(?:\s+\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?)?/g, ' ')
      .replace(/(?:最后更新|更新时间|更新于|更新)\s*[:：]?\s*(?:刚刚|\d+\s*(?:秒|分钟|小时|天|周|月|年)前|昨日|昨天|今天|前天)/g, ' ')
      .replace(/\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}(?:日)?(?:\s+\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?)?/g, ' ')
      .replace(/\b\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?\b/g, ' ')
      .replace(/(?:刚刚|\d+\s*(?:秒|分钟|小时|天|周|月|年)前|昨日|昨天|今天|前天)/g, ' ');
  }

  private static cleanCoverList(covers: string[]): string[] {
    const cleaned: string[] = [];
    for (const cover of covers) {
      const value = CoverUrlNormalizer.normalize(cover);
      if (value && !cleaned.includes(value)) {
        cleaned.push(value);
      }
    }
    return cleaned;
  }
}
