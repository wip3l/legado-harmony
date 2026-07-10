import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import util from '@ohos.util';
import zlib from '@ohos.zlib';
import xml from '@ohos.xml';
import { appDb } from '../../model/data/AppDatabase';
import { Book, BookChapter } from '../../model/data/Book';

export class LocalBookFile {
  uri: string = '';
  name: string = '';
  addedAt: number = 0;
}

export class LocalBookScanResult {
  discovered: number = 0;
  imported: number = 0;
  failed: number = 0;
}

class LocalChapterData {
  title: string = '';
  content: string = '';
  sourcePath: string = '';
}

class XmlNodeData {
  name: string = '';
  text: string = '';
  attributes: Record<string, string> = {};
  children: XmlNodeData[] = [];
}

class EpubManifestItem {
  id: string = '';
  href: string = '';
  mediaType: string = '';
  properties: string = '';
}

class EpubPackageData {
  title: string = '';
  author: string = '';
  coverPath: string = '';
  extractRoot: string = '';
  chapters: LocalChapterData[] = [];
}

class DecodedLocalText {
  text: string = '';
  charset: string = 'utf-8';
}

class LocalTxtImportResult {
  chapterCount: number = 0;
  latestTitle: string = '';
}

export class LocalBookService {
  static readonly ORIGIN: string = 'local';
  static readonly TYPE_TXT: number = 1;
  static readonly TYPE_EPUB: number = 2;

  private static readonly TXT_PARSER_VERSION: string = '4';
  private static readonly TXT_READ_CHUNK_BYTES: number = 256 * 1024;
  private static readonly TXT_MAX_CHAPTER_CHARS: number = 32 * 1024;
  private static readonly TXT_DB_BATCH_SIZE: number = 16;
  private static readonly TXT_RULE_TOP_LEVEL: string =
    '^(?:扉页|[序引前楔][言子]?|(内容|文章|书籍)?简介|作品相关|卷[首尾末](语|总结|感言)|([^-·.–—_*＊~～=\\s\\n\\r](?!(者[：:]))|[-·.–—_*＊~～=](?!(\\s*[-·.–—_*＊~～=]))).*(?!.)|最?[上中下序引终末][章卷篇幕回节册季话集]|[\\dO零一两二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬]+?\\s{0,4}[｜、_|：:；;–.·\\s—-]|[第章卷篇节幕回册]\\s{0,4}[\\dO零一两二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬]+?\\s{0,4}[章卷页回幕册话段季篇节集部]?|[\\dO零一两二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬]+?\\s{0,4}[章卷页季回幕册话段篇节集部]).{0,35}$';

  static isLocalBook(book: Book): boolean {
    return book.origin === LocalBookService.ORIGIN;
  }

  static async chooseBookFiles(context: Context): Promise<LocalBookFile[]> {
    const options = new picker.DocumentSelectOptions();
    options.selectMode = picker.DocumentSelectMode.FILE;
    options.maxSelectNumber = 500;
    options.fileSuffixFilters = ['电子书|.txt,.epub'];
    const result = await new picker.DocumentViewPicker(context).select(options);
    const paths: LocalBookFile[] = [];
    for (const uri of result) {
      if (!uri || paths.some((item: LocalBookFile) => item.uri === uri)) continue;
      const path = new LocalBookFile();
      path.uri = uri;
      path.name = LocalBookService.displayName(path.uri);
      path.addedAt = Date.now();
      paths.push(path);
    }
    return paths;
  }

  static async importSelectedFiles(context: Context, selected: LocalBookFile[]): Promise<LocalBookScanResult> {
    const result = new LocalBookScanResult();
    await appDb.initWithContext(context);
    result.discovered = selected.length;
    for (const path of selected) {
      try {
        await LocalBookService.importBook(context, path.uri);
        result.imported++;
      } catch (e) {
        result.failed++;
        console.error('[LocalBook] import failed:', path.uri, e);
      }
    }
    return result;
  }

  private static async importBook(context: Context, sourceUri: string): Promise<void> {
    const extension = LocalBookService.extensionOf(sourceUri);
    const id = LocalBookService.hashText(sourceUri);
    const bookUrl = `local://${id}`;
    const sourceStat = await fs.stat(sourceUri);
    const oldBook = await appDb.getBook(bookUrl);
    const oldChapterCount = oldBook ? await appDb.getBookChapterCount(bookUrl) : 0;
    const root = `${context.filesDir}/local_books`;
    LocalBookService.ensureDir(root);
    const localPath = `${root}/${id}.${extension}`;
    const oldParserVersion = oldBook?.getVariable('localParserVersion') || '';
    const parserIsCurrent = oldParserVersion === LocalBookService.TXT_PARSER_VERSION ||
      (extension === 'epub' && oldParserVersion === '3');
    if (oldBook && parserIsCurrent &&
      oldBook.getVariable('localSourceMtime') === `${sourceStat.mtime}` &&
      oldBook.getVariable('localSourceSize') === `${sourceStat.size}` &&
      LocalBookService.exists(localPath) && oldChapterCount > 0) {
      return;
    }
    if (LocalBookService.exists(localPath)) {
      fs.unlinkSync(localPath);
    }
    const copySource = sourceUri.startsWith('/') ? fileUri.getUriFromPath(sourceUri) : sourceUri;
    await fs.copy(copySource, fileUri.getUriFromPath(localPath));

    const book = oldBook || new Book();
    book.bookUrl = bookUrl;
    book.tocUrl = bookUrl;
    book.origin = LocalBookService.ORIGIN;
    book.originName = extension.toUpperCase();
    book.canUpdate = false;
    book.group = 0;
    book.type = extension === 'epub' ? LocalBookService.TYPE_EPUB : LocalBookService.TYPE_TXT;
    book.putVariable('localSourceUri', sourceUri);
    book.putVariable('localFilePath', localPath);
    book.putVariable('localFormat', extension);
    book.putVariable('localParserVersion', 'importing');
    book.putVariable('localSourceMtime', `${sourceStat.mtime}`);
    book.putVariable('localSourceSize', `${sourceStat.size}`);
    book.putVariable('bookAddTime', oldBook?.getVariable('bookAddTime') || `${Date.now()}`);

    if (extension === 'txt') {
      book.name = LocalBookService.fileStem(sourceUri);
      book.author = '';
      book.coverUrl = '';
      book.putVariable('localExtractRoot', '');
      book.putVariable('localParserVersion', 'importing');
      if (oldBook) {
        await appDb.updateBook(book);
      } else {
        await appDb.insertBook(book);
      }
      await LocalBookService.rebuildTxtBook(book, localPath);
      return;
    }

    let chapters: LocalChapterData[] = [];
    const epub = await LocalBookService.parseEpub(context, localPath, id);
    book.name = epub.title || LocalBookService.fileStem(sourceUri);
    book.author = epub.author;
    book.coverUrl = epub.coverPath ? fileUri.getUriFromPath(epub.coverPath) : '';
    const oldExtractRoot = book.getVariable('localExtractRoot');
    if (oldExtractRoot && oldExtractRoot !== epub.extractRoot) {
      LocalBookService.deleteLocalPath(context, oldExtractRoot);
    }
    book.putVariable('localExtractRoot', epub.extractRoot);
    book.putVariable('localParserVersion', LocalBookService.TXT_PARSER_VERSION);
    chapters = epub.chapters;

    if (chapters.length === 0) {
      const chapter = new LocalChapterData();
      chapter.title = book.name || '正文';
      chapter.content = '暂无可阅读内容';
      chapters.push(chapter);
    }
    book.totalChapterNum = chapters.length;
    book.latestChapterTitle = chapters[chapters.length - 1].title;
    book.latestChapterTime = Date.now();
    if (book.durChapterIndex >= chapters.length) {
      book.durChapterIndex = 0;
      book.durChapterPos = 0;
      book.durChapterTitle = '';
    }

    if (oldBook) {
      await appDb.updateBook(book);
    } else {
      await appDb.insertBook(book);
    }
    await appDb.deleteBookChapters(bookUrl);
    await appDb.deleteBookCachedContent(bookUrl);
    const dbChapters: BookChapter[] = [];
    for (let i = 0; i < chapters.length; i++) {
      const data = chapters[i];
      const chapter = new BookChapter();
      chapter.bookUrl = bookUrl;
      chapter.index = i;
      chapter.title = data.title || `第${i + 1}章`;
      chapter.url = `${bookUrl}#chapter=${i}`;
      chapter.resourceUrl = data.sourcePath;
      dbChapters.push(chapter);
    }
    await appDb.insertBookChaptersWithContents(bookUrl, dbChapters,
      chapters.map((chapter: LocalChapterData) => chapter.content || ' '));
  }

  static async ensureTxtParserCurrent(context: Context, book: Book): Promise<boolean> {
    if (!LocalBookService.isLocalBook(book) || book.type !== LocalBookService.TYPE_TXT ||
      book.getVariable('localParserVersion') === LocalBookService.TXT_PARSER_VERSION) {
      return false;
    }
    const localPath = book.getVariable('localFilePath');
    if (!localPath || !LocalBookService.exists(localPath)) {
      return false;
    }
    await appDb.initWithContext(context);
    book.putVariable('localParserVersion', 'importing');
    await appDb.updateBook(book);
    await LocalBookService.rebuildTxtBook(book, localPath);
    return true;
  }

  private static async rebuildTxtBook(book: Book, localPath: string): Promise<void> {
    book.charset = await LocalBookService.detectTextFileCharset(localPath);
    await appDb.deleteBookChapters(book.bookUrl);
    await appDb.deleteBookCachedContent(book.bookUrl);
    const imported = await LocalBookService.importTxtChapters(book.bookUrl, localPath, book.charset);
    book.totalChapterNum = imported.chapterCount;
    book.latestChapterTitle = imported.latestTitle;
    book.latestChapterTime = Date.now();
    if (book.durChapterIndex >= imported.chapterCount) {
      book.durChapterIndex = 0;
      book.durChapterPos = 0;
      book.durChapterTitle = '';
    }
    book.putVariable('localParserVersion', LocalBookService.TXT_PARSER_VERSION);
    await appDb.updateBook(book);
  }

  private static async importTxtChapters(bookUrl: string, path: string,
    charset: string): Promise<LocalTxtImportResult> {
    const result = new LocalTxtImportResult();
    const titleRegex = new RegExp(LocalBookService.TXT_RULE_TOP_LEVEL);
    let currentTitle = '';
    let currentPart = 1;
    let currentHasPersisted = false;
    let bodyParts: string[] = [];
    let bodyLength = 0;
    let chapterBatch: BookChapter[] = [];
    let contentBatch: string[] = [];

    const flushBatch = async (): Promise<void> => {
      if (chapterBatch.length === 0) return;
      const pendingChapters = chapterBatch;
      const pendingContents = contentBatch;
      chapterBatch = [];
      contentBatch = [];
      await appDb.insertBookChaptersWithContents(bookUrl, pendingChapters, pendingContents);
    };

    const persistCurrent = async (allowEmptyTitle: boolean): Promise<boolean> => {
      const content = bodyParts.join('').trim();
      bodyParts = [];
      bodyLength = 0;
      if (!content && (!allowEmptyTitle || !currentTitle || currentHasPersisted)) {
        return false;
      }
      const chapter = new LocalChapterData();
      const baseTitle = currentTitle || '正文';
      chapter.title = currentPart > 1 ? `${baseTitle}（${currentPart}）` : baseTitle;
      chapter.content = content || chapter.title;
      const dbChapter = new BookChapter();
      dbChapter.bookUrl = bookUrl;
      dbChapter.index = result.chapterCount;
      dbChapter.title = chapter.title;
      dbChapter.url = `${bookUrl}#chapter=${dbChapter.index}`;
      dbChapter.resourceUrl = path;
      chapterBatch.push(dbChapter);
      contentBatch.push(chapter.content);
      result.chapterCount++;
      result.latestTitle = chapter.title;
      currentHasPersisted = true;
      if (chapterBatch.length >= LocalBookService.TXT_DB_BATCH_SIZE) {
        await flushBatch();
      }
      return true;
    };

    const appendBodyText = async (text: string): Promise<void> => {
      let remaining = text;
      while (remaining.length > 0) {
        const capacity = Math.max(1, LocalBookService.TXT_MAX_CHAPTER_CHARS - bodyLength);
        const take = Math.min(capacity, remaining.length);
        bodyParts.push(remaining.substring(0, take));
        bodyLength += take;
        remaining = remaining.substring(take);
        if (bodyLength >= LocalBookService.TXT_MAX_CHAPTER_CHARS) {
          const persisted = await persistCurrent(false);
          if (persisted) currentPart++;
        }
      }
    };

    const consumeLine = async (rawLine: string, forceBody: boolean = false): Promise<void> => {
      const line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;
      const candidate = line.trim();
      if (!forceBody && candidate && candidate.length <= 50 && titleRegex.test(line)) {
        await persistCurrent(true);
        currentTitle = candidate;
        currentPart = 1;
        currentHasPersisted = false;
      } else {
        await appendBodyText(`${line}\n`);
      }
    };

    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    const decoder = util.TextDecoder.create(charset || 'utf-8');
    let carry = '';
    let carryIsBody = false;
    let isFirstChunk = true;
    try {
      while (true) {
        const buffer = new ArrayBuffer(LocalBookService.TXT_READ_CHUNK_BYTES);
        const readSize = await fs.read(file.fd, buffer);
        if (readSize <= 0) break;
        const bytes = new Uint8Array(buffer, 0, readSize);
        let decoded = decoder.decodeWithStream(bytes, { stream: true });
        if (isFirstChunk) {
          decoded = decoded.replace(/^\uFEFF/, '');
          isFirstChunk = false;
        }
        const decodedText = carry + decoded;
        let lineStart = 0;
        let lineEnd = decodedText.indexOf('\n', lineStart);
        while (lineEnd >= 0) {
          const line = decodedText.substring(lineStart, lineEnd);
          await consumeLine(line, carryIsBody && lineStart === 0);
          carryIsBody = false;
          lineStart = lineEnd + 1;
          lineEnd = decodedText.indexOf('\n', lineStart);
        }
        carry = decodedText.substring(lineStart);
        while (carry.length > LocalBookService.TXT_MAX_CHAPTER_CHARS) {
          await appendBodyText(carry.substring(0, LocalBookService.TXT_MAX_CHAPTER_CHARS));
          carry = carry.substring(LocalBookService.TXT_MAX_CHAPTER_CHARS);
          carryIsBody = true;
        }
      }
      const tail = decoder.decodeWithStream(new Uint8Array(0), { stream: false });
      carry += tail;
      if (carry || carryIsBody) {
        await consumeLine(carry, carryIsBody);
      }
      await persistCurrent(true);
      if (result.chapterCount === 0) {
        currentTitle = '正文';
        currentPart = 1;
        currentHasPersisted = false;
        bodyParts = ['暂无可阅读内容'];
        bodyLength = bodyParts[0].length;
        await persistCurrent(true);
      }
      await flushBatch();
    } finally {
      await fs.close(file);
    }
    return result;
  }

  private static async detectTextFileCharset(path: string): Promise<string> {
    const stat = await fs.stat(path);
    const sampleSize = Math.min(stat.size, 64 * 1024);
    if (sampleSize <= 0) return 'utf-8';
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(sampleSize);
      const readSize = await fs.read(file.fd, buffer);
      return LocalBookService.detectCharset(new Uint8Array(buffer, 0, Math.max(0, readSize)));
    } finally {
      await fs.close(file);
    }
  }

  private static async parseEpub(context: Context, epubPath: string, id: string): Promise<EpubPackageData> {
    const stat = await fs.stat(epubPath);
    const extractRoot = `${context.filesDir}/local_books/${id}_${stat.mtime}`;
    if (!LocalBookService.exists(extractRoot)) {
      LocalBookService.ensureDir(extractRoot);
      await zlib.decompressFile(epubPath, extractRoot);
    }
    const containerPath = `${extractRoot}/META-INF/container.xml`;
    const containerText = (await LocalBookService.readTextFile(containerPath, 'utf-8')).text;
    const container = LocalBookService.parseXml(containerText);
    const rootfile = LocalBookService.findFirstNode(container, 'rootfile');
    const opfRelative = rootfile?.attributes['full-path'] || '';
    if (!opfRelative) {
      throw new Error('EPUB container.xml 缺少 OPF 路径');
    }
    const opfPath = LocalBookService.normalizePath(`${extractRoot}/${opfRelative}`);
    const opfDir = LocalBookService.parentPath(opfPath);
    const opfText = (await LocalBookService.readTextFile(opfPath, 'utf-8')).text;
    const opf = LocalBookService.parseXml(opfText);
    const result = new EpubPackageData();
    result.extractRoot = extractRoot;
    result.title = LocalBookService.nodeText(LocalBookService.findFirstNode(opf, 'title'));
    result.author = LocalBookService.nodeText(LocalBookService.findFirstNode(opf, 'creator'));

    const manifestNodes = LocalBookService.findNodes(opf, 'item');
    const manifest: Record<string, EpubManifestItem> = {};
    const manifestItems: EpubManifestItem[] = [];
    let navItem: EpubManifestItem | null = null;
    let ncxItem: EpubManifestItem | null = null;
    for (const node of manifestNodes) {
      const item = new EpubManifestItem();
      item.id = node.attributes['id'] || '';
      item.href = node.attributes['href'] || '';
      item.mediaType = node.attributes['media-type'] || '';
      item.properties = node.attributes['properties'] || '';
      if (item.id) {
        manifest[item.id] = item;
        manifestItems.push(item);
      }
      if (item.properties.split(/\s+/).includes('nav')) navItem = item;
      if (item.mediaType === 'application/x-dtbncx+xml') ncxItem = item;
    }

    const metadataNodes = LocalBookService.findNodes(opf, 'meta');
    let coverId = '';
    for (const node of metadataNodes) {
      if ((node.attributes['name'] || '').toLowerCase() === 'cover') {
        coverId = node.attributes['content'] || '';
      }
    }
    let coverItem = coverId ? manifest[coverId] : null;
    if (!coverItem) {
      for (const item of manifestItems) {
        if (item.properties.split(/\s+/).includes('cover-image')) {
          coverItem = item;
          break;
        }
      }
    }
    if (coverItem?.href) {
      result.coverPath = LocalBookService.resolveBookPath(opfDir, coverItem.href);
    }

    const tocTitles: Record<string, string> = {};
    if (navItem?.href) {
      const navPath = LocalBookService.resolveBookPath(opfDir, navItem.href);
      const navText = (await LocalBookService.readTextFile(navPath, 'utf-8')).text;
      LocalBookService.extractNavTitles(navText, LocalBookService.parentPath(navPath), tocTitles);
    } else if (ncxItem?.href) {
      const ncxPath = LocalBookService.resolveBookPath(opfDir, ncxItem.href);
      const ncxText = (await LocalBookService.readTextFile(ncxPath, 'utf-8')).text;
      LocalBookService.extractNcxTitles(ncxText, LocalBookService.parentPath(ncxPath), tocTitles);
    }

    const spineNodes = LocalBookService.findNodes(opf, 'itemref');
    for (const spine of spineNodes) {
      const idref = spine.attributes['idref'] || '';
      const item = manifest[idref];
      if (!item || !item.href) continue;
      const chapterPath = LocalBookService.resolveBookPath(opfDir, item.href);
      if (!LocalBookService.exists(chapterPath)) continue;
      const html = (await LocalBookService.readTextFile(chapterPath, 'utf-8')).text;
      const content = LocalBookService.htmlToText(html);
      if (!content) continue;
      const chapter = new LocalChapterData();
      chapter.sourcePath = chapterPath;
      const key = LocalBookService.withoutFragment(LocalBookService.normalizePath(chapterPath));
      chapter.title = tocTitles[key] || LocalBookService.extractHtmlTitle(html) || `第${result.chapters.length + 1}章`;
      chapter.content = content;
      result.chapters.push(chapter);
    }
    return result;
  }

  private static parseXml(text: string): XmlNodeData {
    const root = new XmlNodeData();
    root.name = '#document';
    const stack: XmlNodeData[] = [root];
    const encoded = new util.TextEncoder().encodeInto(text);
    const bytes = new ArrayBuffer(encoded.length);
    new Uint8Array(bytes).set(encoded);
    const parser = new xml.XmlPullParser(bytes, 'utf-8');
    parser.parse({
      supportDoctype: false,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (eventType: xml.EventType, info: xml.ParseInfo): boolean => {
        if (eventType === xml.EventType.START_TAG) {
          const node = new XmlNodeData();
          node.name = LocalBookService.localName(info.getName());
          stack[stack.length - 1].children.push(node);
          stack.push(node);
        } else if (eventType === xml.EventType.TEXT || eventType === xml.EventType.CDSECT) {
          stack[stack.length - 1].text += info.getText();
        } else if (eventType === xml.EventType.END_TAG && stack.length > 1) {
          stack.pop();
        }
        return true;
      },
      attributeValueCallbackFunction: (name: string, value: string): boolean => {
        if (stack.length > 1) {
          stack[stack.length - 1].attributes[LocalBookService.localName(name)] = value;
        }
        return true;
      }
    });
    return root;
  }

  private static findFirstNode(root: XmlNodeData, name: string): XmlNodeData | null {
    if (root.name === name) return root;
    for (const child of root.children) {
      const found = LocalBookService.findFirstNode(child, name);
      if (found) return found;
    }
    return null;
  }

  private static findNodes(root: XmlNodeData, name: string): XmlNodeData[] {
    const result: XmlNodeData[] = [];
    LocalBookService.appendNodes(root, name, result);
    return result;
  }

  private static appendNodes(root: XmlNodeData, name: string, target: XmlNodeData[]): void {
    if (root.name === name) target.push(root);
    for (const child of root.children) {
      LocalBookService.appendNodes(child, name, target);
    }
  }

  private static nodeText(node: XmlNodeData | null): string {
    if (!node) return '';
    let text = node.text;
    for (const child of node.children) text += ` ${LocalBookService.nodeText(child)}`;
    return LocalBookService.decodeEntities(text).replace(/\s+/g, ' ').trim();
  }

  private static extractNavTitles(html: string, baseDir: string, target: Record<string, string>): void {
    const navMatch = html.match(/<nav\b[^>]*(?:epub:type\s*=\s*["']toc["']|role\s*=\s*["']doc-toc["'])[^>]*>([\s\S]*?)<\/nav>/i);
    const source = navMatch ? navMatch[1] : html;
    const anchor = /<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
    let match: RegExpExecArray | null;
    while ((match = anchor.exec(source)) !== null) {
      const path = LocalBookService.withoutFragment(LocalBookService.resolveBookPath(baseDir, match[1]));
      const title = LocalBookService.htmlToInlineText(match[2]);
      if (path && title && !target[path]) target[path] = title;
    }
  }

  private static extractNcxTitles(ncx: string, baseDir: string, target: Record<string, string>): void {
    const point = /<navPoint\b[^>]*>([\s\S]*?)<\/navPoint>/gi;
    let match: RegExpExecArray | null;
    while ((match = point.exec(ncx)) !== null) {
      const src = match[1].match(/<content\b[^>]*src\s*=\s*["']([^"']+)["']/i);
      const label = match[1].match(/<navLabel\b[^>]*>[\s\S]*?<text\b[^>]*>([\s\S]*?)<\/text>/i);
      if (!src || !label) continue;
      const path = LocalBookService.withoutFragment(LocalBookService.resolveBookPath(baseDir, src[1]));
      const title = LocalBookService.htmlToInlineText(label[1]);
      if (path && title && !target[path]) target[path] = title;
    }
  }

  private static htmlToText(html: string): string {
    const body = html.match(/<body\b[^>]*>([\s\S]*?)<\/body>/i);
    return LocalBookService.decodeEntities((body ? body[1] : html)
      .replace(/<script\b[\s\S]*?<\/script>/gi, '')
      .replace(/<style\b[\s\S]*?<\/style>/gi, '')
      .replace(/<(?:br|hr)\b[^>]*\/?>/gi, '\n')
      .replace(/<\/(?:p|div|section|article|h[1-6]|li|blockquote)>/gi, '\n')
      .replace(/<[^>]+>/g, ' '))
      .replace(/\u00A0/g, ' ')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n[ \t]+/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .replace(/[ \t]{2,}/g, ' ')
      .trim();
  }

  private static htmlToInlineText(html: string): string {
    return LocalBookService.decodeEntities(html.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
  }

  private static extractHtmlTitle(html: string): string {
    const heading = html.match(/<h[1-3]\b[^>]*>([\s\S]*?)<\/h[1-3]>/i);
    if (heading) return LocalBookService.htmlToInlineText(heading[1]);
    const title = html.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i);
    return title ? LocalBookService.htmlToInlineText(title[1]) : '';
  }

  private static decodeEntities(value: string): string {
    const named: Record<string, string> = {};
    named['amp'] = '&';
    named['lt'] = '<';
    named['gt'] = '>';
    named['quot'] = '"';
    named['apos'] = "'";
    named['nbsp'] = ' ';
    return value.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (raw: string, entity: string): string => {
      const lower = entity.toLowerCase();
      if (lower.startsWith('#x')) return String.fromCharCode(parseInt(lower.substring(2), 16));
      if (lower.startsWith('#')) return String.fromCharCode(parseInt(lower.substring(1), 10));
      return named[lower] ?? raw;
    });
  }

  private static async readTextFile(path: string, preferredCharset: string): Promise<DecodedLocalText> {
    const stat = await fs.stat(path);
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      const bytes = new Uint8Array(buffer);
      const charset = preferredCharset || LocalBookService.detectCharset(bytes);
      let text = '';
      try {
        text = util.TextDecoder.create(charset).decodeWithStream(bytes, { stream: false });
      } catch (e) {
        text = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
      }
      const result = new DecodedLocalText();
      result.text = text;
      result.charset = charset;
      return result;
    } finally {
      await fs.close(file);
    }
  }

  private static detectCharset(bytes: Uint8Array): string {
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) return 'utf-8';
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) return 'utf-16le';
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) return 'utf-16be';
    try {
      const utf8 = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
      const replacements = (utf8.match(/\uFFFD/g) || []).length;
      if (replacements <= Math.max(1, Math.floor(utf8.length / 1000))) return 'utf-8';
    } catch (e) {
    }
    return 'gb18030';
  }

  private static isSupportedBookFile(path: string): boolean {
    const ext = LocalBookService.extensionOf(path);
    return ext === 'txt' || ext === 'epub';
  }

  private static extensionOf(path: string): string {
    const clean = decodeURIComponent(LocalBookService.withoutFragment(path)).toLowerCase();
    const index = clean.lastIndexOf('.');
    return index >= 0 ? clean.substring(index + 1) : '';
  }

  private static fileStem(path: string): string {
    const name = LocalBookService.displayName(path);
    const index = name.lastIndexOf('.');
    return index > 0 ? name.substring(0, index) : name;
  }

  private static displayName(path: string): string {
    const clean = decodeURIComponent(LocalBookService.withoutFragment(path).replace(/\/+$/, ''));
    const index = clean.lastIndexOf('/');
    return index >= 0 ? clean.substring(index + 1) : clean;
  }

  private static childPath(parent: string, child: string): string {
    if (child.startsWith('file://') || child.startsWith('datashare://') || child.startsWith('/')) return child;
    return `${parent.replace(/\/+$/, '')}/${child}`;
  }

  private static resolveBookPath(baseDir: string, relative: string): string {
    const decoded = decodeURIComponent(LocalBookService.withoutFragment(relative));
    return LocalBookService.normalizePath(`${baseDir}/${decoded}`);
  }

  private static normalizePath(path: string): string {
    const prefix = path.startsWith('/') ? '/' : '';
    const parts = path.replace(/\\/g, '/').split('/');
    const normalized: string[] = [];
    for (const part of parts) {
      if (!part || part === '.') continue;
      if (part === '..') {
        normalized.pop();
      } else {
        normalized.push(part);
      }
    }
    return `${prefix}${normalized.join('/')}`;
  }

  private static parentPath(path: string): string {
    const normalized = LocalBookService.normalizePath(path);
    const index = normalized.lastIndexOf('/');
    return index > 0 ? normalized.substring(0, index) : normalized;
  }

  private static withoutFragment(value: string): string {
    const index = value.indexOf('#');
    return index >= 0 ? value.substring(0, index) : value;
  }

  private static localName(value: string): string {
    const index = value.indexOf(':');
    return (index >= 0 ? value.substring(index + 1) : value).toLowerCase();
  }

  private static ensureDir(path: string): void {
    if (!LocalBookService.exists(path)) fs.mkdirSync(path, true);
  }

  static deleteLocalBookFiles(context: Context, book: Book): void {
    if (!LocalBookService.isLocalBook(book)) return;
    LocalBookService.deleteLocalPath(context, book.getVariable('localFilePath'));
    LocalBookService.deleteLocalPath(context, book.getVariable('localExtractRoot'));
  }

  private static deleteLocalPath(context: Context, path: string): void {
    const root = `${context.filesDir}/local_books`;
    if (!path || !path.startsWith(root) || !LocalBookService.exists(path)) return;
    try {
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        const names = fs.listFileSync(path);
        for (const name of names) {
          LocalBookService.deleteLocalPath(context, `${path}/${name}`);
        }
        fs.rmdirSync(path);
      } else {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.warn('[LocalBook] cleanup failed:', path, e);
    }
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private static hashText(value: string): string {
    let hash = 2166136261;
    for (let i = 0; i < value.length; i++) {
      hash ^= value.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }
}
