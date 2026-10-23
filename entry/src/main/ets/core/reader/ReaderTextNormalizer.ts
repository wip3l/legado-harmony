import { ReaderActionMarker } from '@legado/sourceengine';
import { ReaderImageMarker } from '../book/ReaderImageMarker';
import { ReaderParagraphIndent } from './ReaderParagraphIndent';

/**
 * 章节正文归一化（纯逻辑，不依赖 ArkUI）：换行与空白清理、软换行合并、段首缩进、重复标题剥离。
 * 分页偏移以这里的输出为基准，任何规则变化都会让已保存的字符偏移失效，改动前先跑
 * scripts/reader-text-normalizer-check.mjs。
 */
export class ReaderTextNormalizer {
  static isTrimChar(value: string): boolean {
    return value === ' ' || value === '\t' || value === '\n' || value === '\r' ||
      value === ' ' || value === '　' || value === '﻿' || value === '​' ||
      value === '‌' || value === '‍' || value === '⁠';
  }

  // 分页/分块起点只跳过换行与零宽字符，保留正文按字符数设置生成的段首缩进。
  static isPageStartTrimChar(value: string): boolean {
    return value === '\n' || value === '\r' || value === '﻿' ||
      value === '​' || value === '‌' || value === '‍' || value === '⁠';
  }

  static trim(text: string): string {
    const source = text || '';
    let start = 0;
    let end = source.length;
    while (start < end && ReaderTextNormalizer.isTrimChar(source.charAt(start))) {
      start++;
    }
    while (end > start && ReaderTextNormalizer.isTrimChar(source.charAt(end - 1))) {
      end--;
    }
    return source.substring(start, end);
  }

  static normalizeText(text: string): string {
    return ReaderTextNormalizer.trim((text || '')
      .replace(/\r\n/g, '\n')
      .replace(/ /g, ' ')
      .replace(/\n{3,}/g, '\n\n'));
  }

  static normalizeChapterBody(text: string): string {
    return ReaderTextNormalizer.mergeSoftWrappedLines(ReaderTextNormalizer.normalizeText(text));
  }

  static mergeSoftWrappedLines(text: string): string {
    if (!text || text.indexOf('\n') < 0) {
      return text;
    }
    const rawLines = text.split('\n');
    const result: string[] = [];
    let current = '';
    for (const rawLine of rawLines) {
      const line = rawLine.trim();
      if (!line) {
        if (current) {
          result.push(current);
          current = '';
        }
        if (result.length > 0 && result[result.length - 1] !== '') {
          result.push('');
        }
        continue;
      }
      if (!current) {
        current = line;
        continue;
      }
      if (ReaderTextNormalizer.shouldMergeSoftLine(current, rawLine)) {
        current += ReaderTextNormalizer.softLineJoiner(current, line) + line;
      } else {
        result.push(current);
        current = line;
      }
    }
    if (current) {
      result.push(current);
    }
    return result.join('\n').replace(/\n{3,}/g, '\n\n').trim();
  }

  static softLineJoiner(previous: string, next: string): string {
    const left = (previous || '').trim();
    const right = (next || '').trim();
    if (!left || !right || /[-‐‑‒–—]$/.test(left)) {
      return '';
    }
    return /[A-Za-z0-9,.:;\'"）)\]]$/.test(left) && /^[A-Za-z0-9]/.test(right) ? ' ' : '';
  }

  static shouldMergeSoftLine(previous: string, nextRaw: string): boolean {
    const prev = (previous || '').trim();
    const next = (nextRaw || '').trim();
    if (ReaderActionMarker.has(prev) || ReaderActionMarker.has(next)) {
      return false;
    }
    // 图片标记必须独占一行才会成为图片块；并进相邻段落后只能被当作行内标记隐藏掉。
    if (ReaderImageMarker.isMarker(prev) || ReaderImageMarker.isMarker(next)) {
      return false;
    }
    if (!prev || !next) {
      return false;
    }
    if (/^[　\s]/.test(nextRaw)) {
      return false;
    }
    if (/^[第卷章节回番外序楔引]\s*[\d一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾]/.test(next)) {
      return false;
    }
    if (/^[，,。！？!?；;：:、」』”）)]/.test(next)) {
      return true;
    }
    if (/[。！？!?；;」』”）)]$/.test(prev)) {
      return false;
    }
    return prev.length < 48 && next.length < 48;
  }

  static indentChapterBody(text: string, indentChars: number = ReaderParagraphIndent.DEFAULT): string {
    const normalized = ReaderTextNormalizer.normalizeChapterBody(text);
    if (!normalized) {
      return '';
    }
    return normalized
      .split('\n')
      .map((line: string) => ReaderTextNormalizer.indentLine(line, indentChars))
      .join('\n');
  }

  static indentLine(line: string, indentChars: number = ReaderParagraphIndent.DEFAULT): string {
    if (!line || line.trim().length === 0) {
      return line;
    }
    const trimmed = line.trim();
    // 图片标记是结构数据，不是正文段落；添加缩进会被分页器拆成一张不可见的文本页。
    if (ReaderImageMarker.isMarker(trimmed)) {
      return trimmed;
    }
    const indent = '　'.repeat(ReaderParagraphIndent.normalize(indentChars));
    return `${indent}${line.replace(/^[　\s]+/g, '')}`;
  }

  /**
   * 正文开头重复章节名时剥离那一行。比较时忽略空白、零宽字符和行内交互标记：有的书源用零宽空格代替
   * 章节名里的空格，或者在标题行上挂段评。标题行前面的图片行（如卷首插图）和空行会被跳过并保留。
   */
  static stripDuplicatedTitle(body: string, title: string): string {
    if (!body || !title) {
      return body;
    }
    const wanted = ReaderTextNormalizer.titleKey(title);
    if (!wanted) {
      return body;
    }
    const lines = body.split('\n');
    let index = 0;
    while (index < lines.length && (!lines[index].trim() || ReaderImageMarker.isMarker(lines[index].trim()))) {
      index++;
    }
    if (index >= lines.length || ReaderTextNormalizer.titleKey(lines[index]) !== wanted) {
      return body;
    }
    const rest = lines.slice(index + 1).join('\n').replace(/^\n+/, '');
    if (index === 0) {
      return ReaderTextNormalizer.trim(rest);
    }
    return ReaderTextNormalizer.trim(`${lines.slice(0, index).join('\n')}\n${rest}`);
  }

  /**
   * 把正文开头连续的图片行（中间可夹空行）拆出来：返回 [图片行, 其余正文]。开头不是图片时第一项为空串。
   */
  static splitLeadingImages(body: string): string[] {
    const lines = (body || '').split('\n');
    let index = 0;
    let lastImage = -1;
    while (index < lines.length && (!lines[index].trim() || ReaderImageMarker.isMarker(lines[index].trim()))) {
      if (lines[index].trim()) lastImage = index;
      index++;
    }
    if (lastImage < 0) {
      return ['', body || ''];
    }
    const images = lines.slice(0, lastImage + 1).map((line: string): string => line.trim())
      .filter((line: string): boolean => line.length > 0);
    // 只去掉开头的换行：正文已经缩进过，段首的全角空格要保留。
    return [images.join('\n\n'), lines.slice(lastImage + 1).join('\n').replace(/^\n+/, '')];
  }

  /** 两个标题去掉空白、零宽字符和交互标记后是否相同。 */
  static sameTitle(a: string, b: string): boolean {
    const key = ReaderTextNormalizer.titleKey(a);
    return key.length > 0 && key === ReaderTextNormalizer.titleKey(b);
  }

  /** 标题比较用的键：去掉交互标记和所有空白、零宽字符。 */
  private static titleKey(text: string): string {
    const plain = ReaderActionMarker.strip(text || '');
    let key = '';
    for (let index = 0; index < plain.length; index++) {
      const char = plain.charAt(index);
      if (!ReaderTextNormalizer.isTrimChar(char)) {
        key += char;
      }
    }
    return key;
  }

  /**
   * 把 [rawStart, rawEnd) 追加为一页；页首保留已有缩进，不给段落续行补缩进。
   * 裁掉首部换行与零宽字符、尾部空白；裁完为空则不追加。
   */
  static pushPage(source: string, rawStart: number, rawEnd: number, pages: string[], starts: number[],
    ends: number[]): void {
    let pageStart = Math.max(0, Math.min(rawStart, source.length));
    let pageEnd = Math.max(pageStart, Math.min(rawEnd, source.length));
    while (pageStart < pageEnd && ReaderTextNormalizer.isPageStartTrimChar(source.charAt(pageStart))) {
      pageStart++;
    }
    while (pageEnd > pageStart && ReaderTextNormalizer.isTrimChar(source.charAt(pageEnd - 1))) {
      pageEnd--;
    }
    const pageText = source.substring(pageStart, pageEnd);
    if (!pageText) {
      return;
    }
    pages.push(pageText);
    starts.push(pageStart);
    ends.push(pageEnd);
  }
}
