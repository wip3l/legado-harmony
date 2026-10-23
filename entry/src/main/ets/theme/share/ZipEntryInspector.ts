/**
 * 解压前读 ZIP 中央目录，检查条目名和解压后大小。系统解压接口不限制路径和总量，
 * 外来的主题包必须先在这里确认没有越界路径、条目数量和解压体积都在上限内。
 */

export class ZipEntryInfo {
  name: string = '';
  compressedSize: number = 0;
  uncompressedSize: number = 0;
  directory: boolean = false;
}

export class ZipInspectLimits {
  maxEntries: number = 64;
  maxTotalUncompressed: number = 0;
  maxEntryUncompressed: number = 0;
}

/** 按偏移读取原始字节；越界时返回实际能读到的部分。 */
export type ZipByteReader = (offset: number, length: number) => Uint8Array;

const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_SIGNATURE = 0x02014b50;
const EOCD_MIN_SIZE = 22;
const MAX_COMMENT_SIZE = 0xFFFF;
const ZIP64_MARKER = 0xFFFFFFFF;

function u16(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function u32(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16)) + bytes[offset + 3] * 0x1000000;
}

function decodeName(bytes: Uint8Array, utf8: boolean): string {
  if (!utf8) {
    let ascii = '';
    for (let i = 0; i < bytes.length; i++) {
      if (bytes[i] > 0x7E || bytes[i] < 0x20) {
        throw new Error('主题包内文件名包含不支持的字符');
      }
      ascii += String.fromCharCode(bytes[i]);
    }
    return ascii;
  }
  let result = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i];
    let code = 0;
    let extra = 0;
    if (b0 < 0x80) {
      code = b0;
    } else if ((b0 & 0xE0) === 0xC0) {
      code = b0 & 0x1F;
      extra = 1;
    } else if ((b0 & 0xF0) === 0xE0) {
      code = b0 & 0x0F;
      extra = 2;
    } else if ((b0 & 0xF8) === 0xF0) {
      code = b0 & 0x07;
      extra = 3;
    } else {
      throw new Error('主题包内文件名编码无效');
    }
    for (let k = 1; k <= extra; k++) {
      const next = bytes[i + k];
      if (next === undefined || (next & 0xC0) !== 0x80) {
        throw new Error('主题包内文件名编码无效');
      }
      code = (code << 6) | (next & 0x3F);
    }
    result += String.fromCodePoint(code);
    i += extra + 1;
  }
  return result;
}

/** 只接受相对路径：不能以 / 开头，不能含反斜杠、盘符、控制字符或 . / .. 段。 */
export function isSafeZipEntryName(name: string): boolean {
  if (!name || name.length > 240 || name.startsWith('/') || name.includes('\\') || name.includes(':')) {
    return false;
  }
  for (let i = 0; i < name.length; i++) {
    if (name.charCodeAt(i) < 0x20) return false;
  }
  const trimmed = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
  for (const segment of trimmed.split('/')) {
    if (!segment || segment === '.' || segment === '..') return false;
  }
  return true;
}

export class ZipEntryInspector {
  static inspect(fileSize: number, read: ZipByteReader, limits: ZipInspectLimits): ZipEntryInfo[] {
    if (fileSize < EOCD_MIN_SIZE) {
      throw new Error('文件不是有效的主题包');
    }
    const tailLength = Math.min(fileSize, EOCD_MIN_SIZE + MAX_COMMENT_SIZE);
    const tailStart = fileSize - tailLength;
    const tail = read(tailStart, tailLength);
    let eocd = -1;
    for (let pos = tail.length - EOCD_MIN_SIZE; pos >= 0; pos--) {
      if (u32(tail, pos) === EOCD_SIGNATURE) {
        eocd = pos;
        break;
      }
    }
    if (eocd < 0) {
      throw new Error('文件不是有效的主题包');
    }
    const diskNumber = u16(tail, eocd + 4);
    const entryCount = u16(tail, eocd + 10);
    const directorySize = u32(tail, eocd + 12);
    const directoryOffset = u32(tail, eocd + 16);
    if (diskNumber !== 0 || entryCount === 0xFFFF || directorySize === ZIP64_MARKER ||
      directoryOffset === ZIP64_MARKER) {
      throw new Error('不支持分卷或超大压缩包');
    }
    if (entryCount === 0) {
      throw new Error('主题包是空的');
    }
    if (entryCount > limits.maxEntries) {
      throw new Error(`主题包内文件过多（${entryCount} 个）`);
    }
    if (directoryOffset + directorySize > tailStart + eocd) {
      throw new Error('主题包已损坏');
    }
    const directory = read(directoryOffset, directorySize);
    if (directory.length < directorySize) {
      throw new Error('主题包已损坏');
    }
    const entries: ZipEntryInfo[] = [];
    const seen = new Set<string>();
    let total = 0;
    let pos = 0;
    for (let index = 0; index < entryCount; index++) {
      if (pos + 46 > directory.length || u32(directory, pos) !== CENTRAL_SIGNATURE) {
        throw new Error('主题包已损坏');
      }
      const flags = u16(directory, pos + 8);
      const compressedSize = u32(directory, pos + 20);
      const uncompressedSize = u32(directory, pos + 24);
      const nameLength = u16(directory, pos + 28);
      const extraLength = u16(directory, pos + 30);
      const commentLength = u16(directory, pos + 32);
      if ((flags & 0x1) !== 0) {
        throw new Error('不支持加密的主题包');
      }
      if (compressedSize === ZIP64_MARKER || uncompressedSize === ZIP64_MARKER) {
        throw new Error('不支持超大压缩包');
      }
      if (pos + 46 + nameLength > directory.length) {
        throw new Error('主题包已损坏');
      }
      const name = decodeName(directory.subarray(pos + 46, pos + 46 + nameLength), (flags & 0x800) !== 0);
      if (!isSafeZipEntryName(name)) {
        throw new Error('主题包内含有不安全的文件路径');
      }
      if (seen.has(name)) {
        throw new Error('主题包内有重复文件');
      }
      seen.add(name);
      const entry = new ZipEntryInfo();
      entry.name = name;
      entry.compressedSize = compressedSize;
      entry.uncompressedSize = uncompressedSize;
      entry.directory = name.endsWith('/');
      if (limits.maxEntryUncompressed > 0 && uncompressedSize > limits.maxEntryUncompressed) {
        throw new Error('主题包内有文件超出大小上限');
      }
      total += uncompressedSize;
      if (limits.maxTotalUncompressed > 0 && total > limits.maxTotalUncompressed) {
        throw new Error('主题包解压后超出大小上限');
      }
      entries.push(entry);
      pos += 46 + nameLength + extraLength + commentLength;
    }
    return entries;
  }

  /**
   * 压缩目录时系统会把目录名作为条目前缀。所有条目共享同一个顶层目录时返回它（带结尾 /），否则返回空串。
   */
  static commonRoot(entries: ZipEntryInfo[]): string {
    let root = '';
    for (const entry of entries) {
      const slash = entry.name.indexOf('/');
      if (slash < 0) return '';
      const head = entry.name.substring(0, slash + 1);
      if (!root) {
        root = head;
      } else if (root !== head) {
        return '';
      }
    }
    return root;
  }
}
