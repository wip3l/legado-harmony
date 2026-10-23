import { EpubHtmlConverter } from './EpubHtmlConverter';

/** 内嵌图片记录；recIndex 从 1 起，对应正文里 <img recindex="00001">。 */
export class MobiImage {
  recIndex: number = 0;
  bytes: Uint8Array = new Uint8Array(0);
  ext: string = '';
}

/** 原书目录条目，指向 parts[part] 中 id 为 fragment 的锚点；fragment 为空表示该段开头。 */
export class MobiTocItem {
  part: number = 0;
  fragment: string = '';
  title: string = '';
}

export class MobiBook {
  title: string = '';
  author: string = '';
  /** 按分页标记（没有目录和分页时按标题）拆开的正文 body 片段，图片地址已改写为 imageDir 下的文件。 */
  parts: string[] = [];
  toc: MobiTocItem[] = [];
  images: MobiImage[] = [];
  /** 封面图片的 recIndex，0 表示没有。 */
  coverRecIndex: number = 0;
}

export type MobiTextDecoder = (bytes: Uint8Array, encoding: string) => string;

/**
 * 未加密的 MOBI6（未压缩或 PalmDOC 压缩）解析：
 * PalmDB 记录表 → 第 0 条记录里的 PalmDOC 头、MOBI 头和 EXTH 元数据 → 解压正文记录并去掉尾部附加数据 →
 * 在 filepos 指向的字节位置插入锚点，把 filepos 链接、recindex 图片改写成普通 HTML。
 * 目录取自 <guide> 里 type="toc" 指向的目录页；KF8（AZW3）、HUFF/CDIC 压缩和 DRM 加密的书给出明确提示。
 */
export class MobiBookParser {
  private static readonly MAX_TEXT_BYTES: number = 256 * 1024 * 1024;
  private static readonly TOC_SCAN_CHARS: number = 1024 * 1024;

  static parse(data: Uint8Array, decode: MobiTextDecoder, imageDir: string): MobiBook {
    if (data.length < 78 + 8 || MobiBookParser.ascii(data, 60, 8) !== 'BOOKMOBI') {
      throw new Error('不是有效的 MOBI 文件');
    }
    const recordCount = MobiBookParser.u16(data, 76);
    const offsets: number[] = [];
    for (let i = 0; i < recordCount; i++) {
      const at = 78 + i * 8;
      if (at + 4 > data.length) break;
      offsets.push(MobiBookParser.u32(data, at));
    }
    if (offsets.length === 0) throw new Error('MOBI 文件没有记录');
    const record = (index: number): Uint8Array => {
      if (index < 0 || index >= offsets.length) return new Uint8Array(0);
      const start = offsets[index];
      const end = index + 1 < offsets.length ? offsets[index + 1] : data.length;
      if (start >= end || end > data.length) return new Uint8Array(0);
      return data.subarray(start, end);
    };

    const header = record(0);
    if (header.length < 16) throw new Error('MOBI 文件头不完整');
    const compression = MobiBookParser.u16(header, 0);
    const textRecordCount = MobiBookParser.u16(header, 8);
    const encryption = MobiBookParser.u16(header, 12);
    if (encryption !== 0) throw new Error('这本 MOBI 有 DRM 加密，无法导入');
    if (compression === 17480) throw new Error('这本 MOBI 使用 HUFF/CDIC 压缩，暂不支持，请转换为 EPUB 后导入');
    if (compression !== 1 && compression !== 2) throw new Error(`不支持的 MOBI 压缩方式（${compression}）`);

    const book = new MobiBook();
    let encoding = 'windows-1252';
    let firstImageIndex = -1;
    let extraFlags = 0;
    if (header.length >= 24 && MobiBookParser.ascii(header, 16, 4) === 'MOBI') {
      const mobiLength = MobiBookParser.u32(header, 20);
      const textEncoding = MobiBookParser.u32(header, 28);
      if (textEncoding === 65001) encoding = 'utf-8';
      const version = header.length >= 40 ? MobiBookParser.u32(header, 36) : 0;
      if (version >= 8) throw new Error('这本书是 KF8（AZW3）格式，暂不支持，请转换为 EPUB 后导入');
      if (header.length >= 112) firstImageIndex = MobiBookParser.u32(header, 108);
      if (mobiLength >= 0xE4 && header.length >= 0xF4) extraFlags = MobiBookParser.u16(header, 0xF2);
      if (header.length >= 92) {
        const nameOffset = MobiBookParser.u32(header, 84);
        const nameLength = MobiBookParser.u32(header, 88);
        if (nameLength > 0 && nameOffset + nameLength <= header.length) {
          book.title = decode(header.subarray(nameOffset, nameOffset + nameLength), encoding).trim();
        }
      }
      const exthFlags = header.length >= 132 ? MobiBookParser.u32(header, 128) : 0;
      if ((exthFlags & 0x40) !== 0) MobiBookParser.readExth(header, 16 + mobiLength, encoding, decode, book);
    }
    if (!book.title) book.title = MobiBookParser.ascii(data, 0, 32).replace(/\u0000[\s\S]*$/, '').replace(/_/g, ' ').trim();

    // 正文记录：解压、去掉尾部附加数据后按顺序拼接。
    const chunks: Uint8Array[] = [];
    let total = 0;
    for (let i = 1; i <= textRecordCount && i < offsets.length; i++) {
      let raw = record(i);
      raw = raw.subarray(0, Math.max(0, raw.length - MobiBookParser.trailingSize(raw, extraFlags)));
      const text = compression === 2 ? MobiBookParser.palmDocDecompress(raw) : raw;
      total += text.length;
      if (total > MobiBookParser.MAX_TEXT_BYTES) throw new Error('MOBI 正文过大');
      chunks.push(text);
    }
    const textBytes = new Uint8Array(total);
    let cursor = 0;
    for (const chunk of chunks) {
      textBytes.set(chunk, cursor);
      cursor += chunk.length;
    }

    if (firstImageIndex > 0 && firstImageIndex < offsets.length) {
      for (let index = firstImageIndex; index < offsets.length; index++) {
        const bytes = record(index);
        const ext = MobiBookParser.imageExtension(bytes);
        if (!ext) continue;
        const image = new MobiImage();
        image.recIndex = index - firstImageIndex + 1;
        image.bytes = bytes;
        image.ext = ext;
        book.images.push(image);
      }
    }
    if (book.coverRecIndex > 0 && !book.images.some((image: MobiImage) => image.recIndex === book.coverRecIndex)) {
      book.coverRecIndex = 0;
    }

    MobiBookParser.buildParts(textBytes, encoding, decode, imageDir, book);
    return book;
  }

  /** PalmDOC LZ77 解压。 */
  static palmDocDecompress(input: Uint8Array): Uint8Array {
    let out = new Uint8Array(Math.max(4096, input.length * 2));
    let length = 0;
    const ensure = (extra: number): void => {
      if (length + extra <= out.length) return;
      const grown = new Uint8Array(Math.max(out.length * 2, length + extra));
      grown.set(out.subarray(0, length));
      out = grown;
    };
    let i = 0;
    while (i < input.length) {
      const c = input[i++];
      if (c >= 1 && c <= 8) {
        ensure(c);
        for (let k = 0; k < c && i < input.length; k++) out[length++] = input[i++];
      } else if (c < 0x80) {
        ensure(1);
        out[length++] = c;
      } else if (c >= 0xC0) {
        ensure(2);
        out[length++] = 0x20;
        out[length++] = c ^ 0x80;
      } else {
        if (i >= input.length) break;
        const pair = (c << 8) | input[i++];
        const distance = (pair >> 3) & 0x7FF;
        const count = (pair & 7) + 3;
        if (distance === 0 || distance > length) continue;
        ensure(count);
        // 源与目标可能重叠，逐字节复制。
        for (let k = 0; k < count; k++) {
          out[length] = out[length - distance];
          length++;
        }
      }
    }
    return out.subarray(0, length);
  }

  /** 正文记录末尾附加数据（多字节字符续接、索引信息）的总长度，由 MOBI 头的 extra flags 决定。 */
  static trailingSize(record: Uint8Array, flags: number): number {
    let size = 0;
    let rest = flags >> 1;
    while (rest !== 0) {
      if ((rest & 1) !== 0) size += MobiBookParser.backwardVarint(record, record.length - size);
      rest >>= 1;
    }
    if ((flags & 1) !== 0 && record.length - size - 1 >= 0) {
      size += (record[record.length - size - 1] & 0x3) + 1;
    }
    return Math.min(size, record.length);
  }

  private static backwardVarint(record: Uint8Array, end: number): number {
    let value = 0;
    let shift = 0;
    let position = end;
    while (position > 0) {
      const byte = record[position - 1];
      value |= (byte & 0x7F) << shift;
      shift += 7;
      position--;
      if ((byte & 0x80) !== 0 || shift >= 28) break;
    }
    return value;
  }

  private static readExth(header: Uint8Array, start: number, encoding: string, decode: MobiTextDecoder,
    book: MobiBook): void {
    if (start + 12 > header.length || MobiBookParser.ascii(header, start, 4) !== 'EXTH') return;
    const count = MobiBookParser.u32(header, start + 8);
    let at = start + 12;
    const authors: string[] = [];
    let updatedTitle = '';
    let coverOffset = -1;
    let thumbOffset = -1;
    for (let i = 0; i < count && at + 8 <= header.length; i++) {
      const type = MobiBookParser.u32(header, at);
      const length = MobiBookParser.u32(header, at + 4);
      if (length < 8 || at + length > header.length) break;
      const value = header.subarray(at + 8, at + length);
      if (type === 100) {
        const author = decode(value, encoding).trim();
        if (author && !authors.includes(author)) authors.push(author);
      } else if (type === 503) {
        updatedTitle = decode(value, encoding).trim();
      } else if (type === 201 && value.length >= 4) {
        coverOffset = MobiBookParser.u32(value, 0);
      } else if (type === 202 && value.length >= 4) {
        thumbOffset = MobiBookParser.u32(value, 0);
      }
      at += length;
    }
    if (updatedTitle) book.title = updatedTitle;
    book.author = authors.join('、');
    // 0xFFFFFFFF 表示没有；原封面优先，缩略图兜底。
    if (coverOffset >= 0 && coverOffset !== 0xFFFFFFFF) {
      book.coverRecIndex = coverOffset + 1;
    } else if (thumbOffset >= 0 && thumbOffset !== 0xFFFFFFFF) {
      book.coverRecIndex = thumbOffset + 1;
    }
  }

  private static buildParts(textBytes: Uint8Array, encoding: string, decode: MobiTextDecoder, imageDir: string,
    book: MobiBook): void {
    let raw = MobiBookParser.latin1(textBytes);
    // 目录页位置取自 <guide><reference type="toc" filepos=...>。
    let tocPos = -1;
    const guide = /<reference\b[^>]*>/gi;
    let reference = guide.exec(raw);
    while (reference) {
      if (/\btype\s*=\s*["']?toc\b/i.test(reference[0])) {
        const pos = /\bfilepos\s*=\s*["']?0*(\d+)/i.exec(reference[0]);
        if (pos) tocPos = Number(pos[1]);
        break;
      }
      reference = guide.exec(raw);
    }

    // filepos 是解压后正文的字节偏移：先在原始字节上插好锚点，再按实际编码解码。
    const targets = new Set<number>();
    const filepos = /\bfilepos\s*=\s*["']?0*(\d+)/gi;
    let match = filepos.exec(raw);
    while (match) {
      const value = Number(match[1]);
      if (value >= 0 && value <= raw.length) targets.add(value);
      match = filepos.exec(raw);
    }
    const sorted = Array.from(targets).sort((a: number, b: number) => b - a);
    const pieces: string[] = [];
    let end = raw.length;
    for (const target of sorted) {
      let position = Math.min(target, end);
      // 落在标签内部时挪到标签开头，避免把锚点插进属性里。
      const open = raw.lastIndexOf('<', position);
      const close = position > 0 ? raw.lastIndexOf('>', position - 1) : -1;
      if (open > close && open >= 0 && position > open) position = open;
      pieces.push(raw.substring(position, end));
      pieces.push(`<a id="filepos${target}"></a>`);
      end = position;
    }
    pieces.push(raw.substring(0, end));
    raw = pieces.reverse().join('');
    raw = raw.replace(/(<a\b[^>]*?)\bfilepos\s*=\s*["']?0*(\d+)["']?/gi, '$1href="#filepos$2"');
    const images = new Map<number, MobiImage>();
    for (const image of book.images) images.set(image.recIndex, image);
    raw = raw.replace(/<img\b[^>]*>/gi, (tag: string): string => {
      const index = /\b(?:hi|lo)?recindex\s*=\s*["']?0*(\d+)/i.exec(tag);
      const image = index ? images.get(Number(index[1])) : undefined;
      if (!image) return '';
      return `<img src="${imageDir}/${MobiBookParser.imageName(image)}"/>`;
    });

    const html = decode(MobiBookParser.fromLatin1(raw), encoding);
    const body = EpubHtmlConverter.bodyOf(html);
    let parts = body.split(/<mbp:pagebreak\b[^>]*\/?>(?:\s*<\/mbp:pagebreak>)?/i);
    const toc = tocPos >= 0 ? MobiBookParser.readToc(body, tocPos) : [];
    if (toc.length < 2 && parts.length <= 1) {
      // 没有目录也没有分页标记：按 h1–h3 标题拆开，避免整本书只有一章。
      const byHeading = body.split(/(?=<h[1-3]\b)/i);
      if (byHeading.length >= 3) parts = byHeading;
    }
    const kept: string[] = [];
    const keptIndexForPart: number[] = [];
    for (const part of parts) {
      const hasContent = /<img\b/i.test(part) || EpubHtmlConverter.inlineText(part).length > 0;
      if (hasContent) kept.push(part);
      // 空段里的锚点归到下一个有内容的段开头。
      keptIndexForPart.push(hasContent ? kept.length - 1 : -(kept.length + 1));
    }
    book.parts = kept;
    for (const entry of toc) {
      const marker = `id="${entry.fragment}"`;
      const partIndex = parts.findIndex((part: string) => part.includes(marker));
      if (partIndex < 0) continue;
      const mapped = keptIndexForPart[partIndex];
      const item = new MobiTocItem();
      if (mapped >= 0) {
        item.part = mapped;
        item.fragment = entry.fragment;
      } else {
        item.part = -mapped - 1;
        item.fragment = '';
        if (item.part >= kept.length) continue;
      }
      item.title = entry.title;
      book.toc.push(item);
    }
    if (book.toc.length < 2) book.toc = [];
  }

  /** 读目录页里的 filepos 链接；目录页从锚点开始，到下一个分页标记为止。 */
  private static readToc(body: string, tocPos: number): MobiTocItem[] {
    const items: MobiTocItem[] = [];
    const anchor = body.indexOf(`<a id="filepos${tocPos}"></a>`);
    if (anchor < 0) return items;
    const rest = body.substring(anchor, anchor + MobiBookParser.TOC_SCAN_CHARS);
    const pageEnd = rest.search(/<mbp:pagebreak\b/i);
    const region = pageEnd > 0 ? rest.substring(0, pageEnd) : rest;
    const link = /<a\b[^>]*\bhref="#filepos(\d+)"[^>]*>([\s\S]*?)<\/a>/gi;
    const seen = new Set<number>();
    let match = link.exec(region);
    while (match) {
      const target = Number(match[1]);
      const title = EpubHtmlConverter.inlineText(match[2]);
      if (title && target !== tocPos && !seen.has(target)) {
        seen.add(target);
        const item = new MobiTocItem();
        item.fragment = `filepos${target}`;
        item.title = title.length > 80 ? title.substring(0, 80) : title;
        items.push(item);
      }
      match = link.exec(region);
    }
    return items;
  }

  static imageName(image: MobiImage): string {
    return `${`${image.recIndex}`.padStart(5, '0')}.${image.ext}`;
  }

  private static imageExtension(bytes: Uint8Array): string {
    if (bytes.length < 8) return '';
    if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) return 'jpg';
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) return 'png';
    if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38) return 'gif';
    if (bytes[0] === 0x42 && bytes[1] === 0x4D) return 'bmp';
    return '';
  }

  private static latin1(bytes: Uint8Array): string {
    const parts: string[] = [];
    const step = 8192;
    for (let start = 0; start < bytes.length; start += step) {
      const end = Math.min(bytes.length, start + step);
      let piece = '';
      for (let i = start; i < end; i++) piece += String.fromCharCode(bytes[i]);
      parts.push(piece);
    }
    return parts.join('');
  }

  private static fromLatin1(text: string): Uint8Array {
    const bytes = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i) & 0xFF;
    return bytes;
  }

  private static ascii(bytes: Uint8Array, start: number, length: number): string {
    let text = '';
    for (let i = start; i < start + length && i < bytes.length; i++) text += String.fromCharCode(bytes[i]);
    return text;
  }

  private static u16(bytes: Uint8Array, at: number): number {
    return at + 2 <= bytes.length ? (bytes[at] << 8) | bytes[at + 1] : 0;
  }

  private static u32(bytes: Uint8Array, at: number): number {
    return at + 4 <= bytes.length ?
      ((bytes[at] * 0x1000000) + ((bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3])) : 0;
  }
}
