import { EpubConvertResult, EpubHeading, EpubHtmlConverter } from './EpubHtmlConverter';

/** 目录中的一个条目：指向某个 spine 文件，可带锚点。 */
export class EpubTocEntry {
  path: string = '';
  fragment: string = '';
  title: string = '';
}

/** 章节正文的来源片段：某个文件中 [startId, endId) 之间的内容，空 id 表示文件开头/结尾。 */
export class EpubChapterSegment {
  path: string = '';
  startId: string = '';
  endId: string = '';
}

/** 同一个 spine 文件按目录锚点切出的一段；title 为空表示这段不对应任何目录条目。 */
export class EpubFileCut {
  startId: string = '';
  endId: string = '';
  title: string = '';
}

export class EpubPlannedChapter {
  title: string = '';
  segments: EpubChapterSegment[] = [];
  headings: EpubHeading[] = [];
  content: string = '';
  imageOnly: boolean = false;
  /** 未进入目录、因为过长而从上一章拆出的续篇序号（1 表示不是续篇）。 */
  part: number = 1;
  baseTitle: string = '';
}

/**
 * 以目录为准把 spine 切成章节：
 * - 一个文件里有多个目录锚点时按锚点拆成多章；
 * - 目录没有提到的文件（被拆分工具切开的长章节、插图页）并入前一章；
 * - 完全没有目录时退回"一个文件一章"。
 */
export class EpubChapterPlanner {
  /** 合并无目录条目的文件时，单章正文的长度上限；超过后另起续篇，避免目录残缺的书变成一个巨型章节。 */
  static readonly MAX_MERGED_CHAPTER_CHARS: number = 120000;
  private static readonly VARIABLE_KEY: string = 'epubSegments';
  private static readonly HEADINGS_KEY: string = 'epubHeadings';
  private static readonly MAX_CHAPTER_HEADINGS: number = 64;

  chapters: EpubPlannedChapter[] = [];
  spineFileCount: number = 0;
  imageOnlyFileCount: number = 0;
  private hasToc: boolean = false;
  private fileHasContent: boolean = false;
  private fileImageOnly: boolean = true;

  constructor(hasToc: boolean) {
    this.hasToc = hasToc;
  }

  static parseNavToc(html: string, baseDir: string, containerRoot: string = ''): EpubTocEntry[] {
    const source = html || '';
    const nav = /<nav\b[^>]*(?:epub:type\s*=\s*["'][^"']*\btoc\b[^"']*["']|role\s*=\s*["']doc-toc["'])[^>]*>([\s\S]*?)<\/nav>/i
      .exec(source);
    const scope = nav ? nav[1] : source;
    const entries: EpubTocEntry[] = [];
    const anchor = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
    let match = anchor.exec(scope);
    while (match) {
      const href = EpubHtmlConverter.decodeEntities(EpubHtmlConverter.findHtmlAttribute(`<a ${match[1]}>`, ['href']));
      EpubChapterPlanner.pushTocEntry(entries, href, EpubHtmlConverter.inlineText(match[2]), baseDir, containerRoot);
      match = anchor.exec(scope);
    }
    return entries;
  }

  static parseNcxToc(ncx: string, baseDir: string, containerRoot: string = ''): EpubTocEntry[] {
    const source = ncx || '';
    const mapStart = source.search(/<navMap\b/i);
    const scope = mapStart >= 0 ? source.substring(mapStart) : source;
    const entries: EpubTocEntry[] = [];
    // 逐个匹配 navLabel + content 对，而不是整个 navPoint：嵌套的 navPoint 无法用非贪婪正则配对。
    const point = /<navLabel\b[^>]*>\s*<text\b[^>]*>([\s\S]*?)<\/text>\s*<\/navLabel>\s*<content\b([^>]*)>/gi;
    let match = point.exec(scope);
    while (match) {
      const src = EpubHtmlConverter.decodeEntities(
        EpubHtmlConverter.findHtmlAttribute(`<content ${match[2]}>`, ['src']));
      EpubChapterPlanner.pushTocEntry(entries, src, EpubHtmlConverter.inlineText(match[1]), baseDir, containerRoot);
      match = point.exec(scope);
    }
    return entries;
  }

  private static pushTocEntry(entries: EpubTocEntry[], href: string, title: string, baseDir: string,
    containerRoot: string): void {
    if (!href || !title || /^[a-z][a-z0-9+.-]*:/i.test(href)) return;
    const path = EpubHtmlConverter.resolvePath(baseDir, href, containerRoot);
    if (!path) return;
    const entry = new EpubTocEntry();
    entry.path = path;
    entry.fragment = EpubHtmlConverter.fragmentOf(href);
    entry.title = title;
    entries.push(entry);
  }

  /** 把目录条目按文件分组，保持目录顺序。 */
  static groupTocByPath(entries: EpubTocEntry[]): Map<string, EpubTocEntry[]> {
    const grouped = new Map<string, EpubTocEntry[]>();
    // 按“文件 + 锚点”去重；单文件上千个目录条目时逐个比较会变成平方级。
    const seen = new Set<string>();
    for (const entry of entries) {
      const key = `${entry.path}#${entry.fragment}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const list = grouped.get(entry.path);
      if (list) {
        list.push(entry);
      } else {
        grouped.set(entry.path, [entry]);
      }
    }
    return grouped;
  }

  /** 按目录锚点把一个文件的 body 切成若干段。没有目录条目时整个文件是一段无标题内容。 */
  static planFileCuts(body: string, entries: EpubTocEntry[]): EpubFileCut[] {
    const ids: string[] = [];
    const titles: string[] = [];
    const offsets: number[] = [];
    for (const entry of entries) {
      let offset = entry.fragment ? EpubHtmlConverter.findAnchorOffset(body, entry.fragment) : 0;
      // 第一个条目的锚点找不到时仍然从文件开头起算，后续找不到的条目无法定位，只能忽略。
      if (offset < 0) {
        if (offsets.length > 0) continue;
        offset = 0;
      }
      if (offsets.length > 0 && offset <= offsets[offsets.length - 1]) {
        // 卷标题与卷内第一章常指向同一位置：合成一个标题，而不是丢掉其中一个。
        const last = titles.length - 1;
        if (offset === offsets[last] && entry.title !== titles[last] &&
          !titles[last].includes(entry.title) && titles[last].length + entry.title.length < 60) {
          titles[last] = `${titles[last]} ${entry.title}`;
        }
        continue;
      }
      offsets.push(offset);
      ids.push(offset > 0 ? entry.fragment : '');
      titles.push(entry.title);
    }
    const cuts: EpubFileCut[] = [];
    if (offsets.length === 0) {
      cuts.push(new EpubFileCut());
      return cuts;
    }
    if (offsets[0] > 0) {
      // 第一个锚点之前的内容属于上一章的结尾（或者是空的包装标签）。
      const leading = new EpubFileCut();
      leading.endId = ids[0];
      cuts.push(leading);
    }
    for (let index = 0; index < offsets.length; index++) {
      const cut = new EpubFileCut();
      cut.startId = ids[index];
      cut.endId = index + 1 < ids.length ? ids[index + 1] : '';
      cut.title = titles[index];
      cuts.push(cut);
    }
    return cuts;
  }

  beginFile(): void {
    this.fileHasContent = false;
    this.fileImageOnly = true;
  }

  endFile(): void {
    if (!this.fileHasContent) return;
    this.spineFileCount++;
    if (this.fileImageOnly) this.imageOnlyFileCount++;
  }

  /**
   * 追加一段已转换的内容。title 为空表示没有对应的目录条目；这种情况下需要独立成章时，
   * 依次使用正文的第一个标题和 fallbackTitle（文档 <title>）取名。
   */
  addPiece(path: string, startId: string, endId: string, title: string, converted: EpubConvertResult,
    fallbackTitle: string = ''): void {
    const content = converted.content;
    if (!content) return;
    const imageOnly = !converted.hasText;
    this.fileHasContent = true;
    if (!imageOnly) this.fileImageOnly = false;

    const segment = new EpubChapterSegment();
    segment.path = path;
    segment.startId = startId;
    segment.endId = endId;

    const previous = this.chapters.length > 0 ? this.chapters[this.chapters.length - 1] : null;
    if (!title && this.hasToc && previous) {
      if (previous.content.length + content.length <= EpubChapterPlanner.MAX_MERGED_CHAPTER_CHARS) {
        previous.segments.push(segment);
        EpubChapterPlanner.appendHeadings(previous, converted.headings);
        previous.content += `\n\n${content}`;
        previous.imageOnly = previous.imageOnly && imageOnly;
        return;
      }
      const continued = new EpubPlannedChapter();
      continued.baseTitle = previous.baseTitle;
      continued.part = previous.part + 1;
      continued.title = `${continued.baseTitle}（${continued.part}）`;
      continued.segments.push(segment);
      EpubChapterPlanner.appendHeadings(continued, converted.headings);
      continued.content = content;
      continued.imageOnly = imageOnly;
      this.chapters.push(continued);
      return;
    }

    const chapter = new EpubPlannedChapter();
    let name = title || converted.headingText || fallbackTitle;
    if (!name) {
      name = this.chapters.length === 0 && imageOnly ? '封面' : `第${this.chapters.length + 1}节`;
    }
    chapter.title = name;
    chapter.baseTitle = name;
    chapter.segments.push(segment);
    EpubChapterPlanner.appendHeadings(chapter, converted.headings);
    chapter.content = content;
    chapter.imageOnly = imageOnly;
    this.chapters.push(chapter);
  }

  /** 少量封面/插图页不应把整本书识别为漫画：长篇要求 ≥3 个纯图文件且占比 ≥80%，两个文件的短篇必须全部为纯图。 */
  isComicDominant(): boolean {
    return (this.spineFileCount === 2 && this.imageOnlyFileCount === 2) ||
      (this.imageOnlyFileCount >= 3 && this.imageOnlyFileCount * 100 >= this.spineFileCount * 80);
  }

  private static appendHeadings(chapter: EpubPlannedChapter, headings: EpubHeading[]): void {
    for (const heading of headings) {
      if (chapter.headings.length >= EpubChapterPlanner.MAX_CHAPTER_HEADINGS) return;
      chapter.headings.push(heading);
    }
  }

  /** 章节的 variable：正文来源片段，以及章内标题（阅读器据此排标题样式）。 */
  static encodeVariable(segments: EpubChapterSegment[], headings: EpubHeading[] = []): string {
    const holder: Record<string, string[][]> = {};
    holder[EpubChapterPlanner.VARIABLE_KEY] = segments.map((segment: EpubChapterSegment): string[] =>
      [segment.path, segment.startId, segment.endId]);
    if (headings.length > 0) {
      holder[EpubChapterPlanner.HEADINGS_KEY] = headings.map((heading: EpubHeading): string[] =>
        [`${heading.level}`, heading.text]);
    }
    return JSON.stringify(holder);
  }

  static decodeHeadings(variable: string): EpubHeading[] {
    const result: EpubHeading[] = [];
    if (!variable || variable.indexOf(EpubChapterPlanner.HEADINGS_KEY) < 0) return result;
    try {
      const holder = JSON.parse(variable) as Record<string, string[][]>;
      const list = holder[EpubChapterPlanner.HEADINGS_KEY];
      if (!Array.isArray(list)) return result;
      for (const item of list) {
        if (!Array.isArray(item) || typeof item[1] !== 'string' || !item[1]) continue;
        const level = parseInt(`${item[0]}`, 10);
        if (!(level >= 1 && level <= 6)) continue;
        const heading = new EpubHeading();
        heading.level = level;
        heading.text = item[1];
        result.push(heading);
      }
    } catch (_) {
    }
    return result;
  }

  static decodeSegments(variable: string): EpubChapterSegment[] {
    const result: EpubChapterSegment[] = [];
    if (!variable || variable.indexOf(EpubChapterPlanner.VARIABLE_KEY) < 0) return result;
    try {
      const holder = JSON.parse(variable) as Record<string, string[][]>;
      const list = holder[EpubChapterPlanner.VARIABLE_KEY];
      if (!Array.isArray(list)) return result;
      for (const item of list) {
        if (!Array.isArray(item) || typeof item[0] !== 'string' || !item[0]) continue;
        const segment = new EpubChapterSegment();
        segment.path = item[0];
        segment.startId = typeof item[1] === 'string' ? item[1] : '';
        segment.endId = typeof item[2] === 'string' ? item[2] : '';
        result.push(segment);
      }
    } catch (_) {
    }
    return result;
  }

  /**
   * 重新解析后旧的章节序号不再有效：按旧章节所在的文件找到新的章节序号，找不到返回 -1。
   */
  static chapterIndexForPath(chapters: EpubPlannedChapter[], path: string): number {
    const target = EpubHtmlConverter.withoutFragment(path || '');
    if (!target) return -1;
    for (let index = 0; index < chapters.length; index++) {
      if (chapters[index].segments.length > 0 && chapters[index].segments[0].path === target) return index;
    }
    for (let index = 0; index < chapters.length; index++) {
      if (chapters[index].segments.some((segment: EpubChapterSegment): boolean => segment.path === target)) {
        return index;
      }
    }
    return -1;
  }
}
