#!/usr/bin/env node
// MOBI6 解析的回归检查：在脚本里拼出合成的 MOBI 文件（PalmDB 记录表、PalmDOC 头、MOBI 头、EXTH、
// 正文记录尾部附加数据、内嵌图片），校验解压、filepos 目录、图片改写、封面与不支持格式的提示。
// 直接加载 entry 下的 MobiBookParser.ts；文件写入与分章走 EPUB 同一流程，在真机上验证。
// Usage: node --experimental-strip-types scripts/mobi-parser-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { MobiBookParser, cleanup } = await loadReaderModules();

let failures = 0;
const check = (condition, message, detail = '') => {
  if (condition) {
    console.log(`  ok - ${message}`);
  } else {
    failures++;
    console.error(`  FAIL - ${message}${detail ? `\n         ${detail}` : ''}`);
  }
};
const equal = (actual, expected, message) =>
  check(JSON.stringify(actual) === JSON.stringify(expected), message,
    `expected ${JSON.stringify(expected)}\n         actual   ${JSON.stringify(actual)}`);
const throwsWith = (fn, pattern, message) => {
  try {
    fn();
    check(false, message, 'no error thrown');
  } catch (error) {
    check(pattern.test(error.message), message, error.message);
  }
};

const decode = (bytes, encoding) => new TextDecoder(encoding === 'utf-8' ? 'utf-8' : 'windows-1252').decode(bytes);
const utf8 = (text) => new TextEncoder().encode(text);
const concat = (...arrays) => {
  const out = new Uint8Array(arrays.reduce((sum, item) => sum + item.length, 0));
  let at = 0;
  for (const item of arrays) {
    out.set(item, at);
    at += item.length;
  }
  return out;
};
const u16 = (value) => new Uint8Array([(value >> 8) & 0xFF, value & 0xFF]);
const u32 = (value) => new Uint8Array([(value >>> 24) & 0xFF, (value >>> 16) & 0xFF, (value >>> 8) & 0xFF, value & 0xFF]);
const png = Uint8Array.from(Buffer.from(
  '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000b49444154789c636000020000050001a5f645400000000049454e44ae426082',
  'hex'));

/** 只输出字面量的 PalmDOC "压缩"：0x80 以上的字节用 1–8 字节的字面量串。 */
const palmDocLiterals = (bytes) => {
  const out = [];
  for (let i = 0; i < bytes.length;) {
    if (bytes[i] >= 0x80 || (bytes[i] >= 1 && bytes[i] <= 8)) {
      const run = Math.min(8, bytes.length - i);
      out.push(run, ...bytes.subarray(i, i + run));
      i += run;
    } else {
      out.push(bytes[i++]);
    }
  }
  return Uint8Array.from(out);
};

/**
 * html 里的 {{pos:NAME}} 会替换成 {{at:NAME}} 所在字节位置（10 位补零，长度固定所以偏移不变）。
 * options: compression(1|2) encryption version extraFlags exth(bool) images
 */
const buildMobi = (template, options = {}) => {
  const compression = options.compression ?? 2;
  const extraFlags = options.extraFlags ?? 3;
  let html = template.replace(/\{\{pos:(\w+)\}\}/g, (_, name) => `{{pos:${name.padEnd(10, '_').slice(0, 10)}}}`);
  const resolveOffsets = (text) => {
    const marks = {};
    let clean = text;
    for (;;) {
      const match = /\{\{at:(\w+)\}\}/.exec(clean);
      if (!match) break;
      marks[match[1]] = utf8(clean.substring(0, match.index)).length;
      clean = clean.substring(0, match.index) + clean.substring(match.index + match[0].length);
    }
    return { marks, clean };
  };
  // 先把 pos 换成等长占位再算位置，最后填数字。
  html = html.replace(/\{\{pos:(\w{10})\}\}/g, (_, name) => `{{pos:${name}}}`);
  let { marks, clean } = resolveOffsets(html.replace(/\{\{pos:(\w{10})\}\}/g, '0000000000'));
  clean = (() => {
    let output = html;
    // 重新去掉 at 标记，再填 pos。
    output = output.replace(/\{\{at:\w+\}\}/g, '');
    return output.replace(/\{\{pos:(\w{10})\}\}/g, (_, name) => {
      const key = name.replace(/_+$/, '');
      return `${marks[key] ?? 0}`.padStart(10, '0');
    });
  })();
  const text = utf8(clean);

  const records = [];
  const textRecords = [];
  for (let start = 0; start < text.length; start += 4096) {
    const chunk = text.subarray(start, Math.min(text.length, start + 4096));
    let body = compression === 2 ? palmDocLiterals(chunk) : chunk;
    if (extraFlags & 1) body = concat(body, new Uint8Array([0x00]));
    if (extraFlags & 2) body = concat(body, new Uint8Array([0xAA, 0x82]));
    textRecords.push(body);
  }
  const images = options.images ?? [png];
  const exth = [];
  if (options.exth !== false) {
    const entry = (type, value) => concat(u32(type), u32(value.length + 8), value);
    exth.push(entry(100, utf8('作者甲')), entry(100, utf8('作者乙')), entry(503, utf8('测试书')), entry(201, u32(0)));
  }
  const exthBody = concat(...exth);
  const exthBlock = exth.length ? concat(utf8('EXTH'), u32(12 + exthBody.length), u32(exth.length), exthBody) : new Uint8Array();
  const fullName = utf8('Full Name');
  const mobiLength = 232;
  const record0 = new Uint8Array(16 + mobiLength + exthBlock.length + fullName.length + 4);
  record0.set(u16(compression), 0);
  record0.set(u32(text.length), 4);
  record0.set(u16(textRecords.length), 8);
  record0.set(u16(4096), 10);
  record0.set(u16(options.encryption ?? 0), 12);
  record0.set(utf8('MOBI'), 16);
  record0.set(u32(mobiLength), 20);
  record0.set(u32(2), 24);
  record0.set(u32(65001), 28);
  record0.set(u32(options.version ?? 6), 36);
  const nameOffset = 16 + mobiLength + exthBlock.length;
  record0.set(u32(nameOffset), 84);
  record0.set(u32(fullName.length), 88);
  record0.set(u32(1 + textRecords.length), 108);
  record0.set(u32(exth.length ? 0x40 : 0), 128);
  record0.set(u16(extraFlags), 0xF2);
  record0.set(exthBlock, 16 + mobiLength);
  record0.set(fullName, nameOffset);
  records.push(record0, ...textRecords, ...images, utf8('FLIS\0\0\0\0'), utf8('EOF\0'));

  const headerLength = 78 + records.length * 8 + 2;
  const palm = new Uint8Array(headerLength);
  palm.set(utf8('Palm_Name'), 0);
  palm.set(utf8('BOOKMOBI'), 60);
  palm.set(u16(records.length), 76);
  let offset = headerLength;
  records.forEach((record, index) => {
    palm.set(u32(offset), 78 + index * 8);
    offset += record.length;
  });
  return { bytes: concat(palm, ...records), marks };
};

const template = (filler = '') =>
  '<html><head><guide><reference type="toc" title="目录" filepos={{pos:toc}} /></guide></head><body>' +
  '<p>封面页</p><img recindex="00001" />' +
  '<mbp:pagebreak/>{{at:toc}}<div>目录</div>' +
  '<p><a filepos={{pos:c1}}>第一章 开端</a></p><p><a filepos={{pos:c2}}>第二章 继续</a></p>' +
  '<mbp:pagebreak/>{{at:c1}}<h2>第一章 开端</h2><p>正文一。' + filler + '</p>' +
  '<mbp:pagebreak/>{{at:c2}}<h2>第二章 继续</h2><p>正文二，中文。</p><p>结尾</p>' +
  '</body></html>';

try {
  console.log('palmDocDecompress');
  {
    // 'abc' 字面量 + 回溯 3 字节复制 6 字节 + 空格合成字节 0xE1 → ' a' + 字面量串 0x02 'x' 'y'
    const input = Uint8Array.from([0x61, 0x62, 0x63, 0x80, 0x1B, 0xE1, 0x02, 0x78, 0x79]);
    equal(new TextDecoder().decode(MobiBookParser.palmDocDecompress(input)), 'abcabcabc axy', 'LZ77 回溯、空格合成与字面量串');
  }

  console.log('trailingSize');
  {
    equal(MobiBookParser.trailingSize(Uint8Array.from([1, 2, 3, 0x00, 0xAA, 0x82]), 3), 3, '多字节标记 + 一个索引附加项');
    equal(MobiBookParser.trailingSize(Uint8Array.from([1, 2, 3, 0x01, 0x81]), 3), 3, '多字节标记带一个续接字节');
    equal(MobiBookParser.trailingSize(Uint8Array.from([1, 2, 3]), 0), 0, '没有附加数据');
  }

  console.log('parse');
  for (const compression of [1, 2]) {
    const { bytes } = buildMobi(template('长段落'.repeat(1200)), { compression });
    const book = MobiBookParser.parse(bytes, decode, '../images');
    const label = compression === 2 ? 'PalmDOC' : '未压缩';
    equal(book.title, '测试书', `${label}：EXTH 503 书名优先`);
    equal(book.author, '作者甲、作者乙', `${label}：多个作者合并`);
    equal(book.coverRecIndex, 1, `${label}：EXTH 201 封面`);
    equal(book.images.map((image) => [image.recIndex, image.ext]), [[1, 'png']], `${label}：只收图片记录，FLIS/EOF 跳过`);
    equal(book.parts.length, 4, `${label}：按分页标记拆成 4 段`);
    check(book.parts[0].includes('<img src="../images/00001.png"/>'), `${label}：recindex 改写为图片文件`);
    equal(book.toc.map((item) => [item.part, item.title]), [[2, '第一章 开端'], [3, '第二章 继续']],
      `${label}：目录取自 guide 指向的目录页`);
    check(book.toc.every((item) => book.parts[item.part].includes(`id="${item.fragment}"`)), `${label}：目录锚点落在对应段里`);
    check(book.parts[1].includes('href="#filepos'), `${label}：filepos 链接改写为 href`);
    check(book.parts[2].includes('长段落长段落') && book.parts[3].includes('正文二，中文。'),
      `${label}：跨记录的多字节字符完整`);
  }

  {
    const { bytes } = buildMobi(template(), { exth: false, extraFlags: 0 });
    const book = MobiBookParser.parse(bytes, decode, '../images');
    equal(book.title, 'Full Name', '没有 EXTH 时用 MOBI 头里的完整书名');
    equal(book.coverRecIndex, 0, '没有封面记录');
  }

  {
    const html = '<html><body><h1>序</h1><p>甲</p><h2>第一回</h2><p>乙</p><h2>第二回</h2><p>丙</p></body></html>';
    const book = MobiBookParser.parse(buildMobi(html).bytes, decode, '../images');
    equal(book.parts.length, 3, '没有目录和分页标记时按标题拆段');
    equal(book.toc, [], '没有目录时 toc 为空');
  }

  {
    // filepos 指向标签内部时，锚点挪到标签开头。
    const html = '<html><body><p>a</p><mbp:pagebreak/><p><a filepos={{pos:x}}>跳</a></p><mbp:pagebreak/>' +
      '<h3 class="t{{at:x}}">标题</h3><p>b</p></body></html>';
    const book = MobiBookParser.parse(buildMobi(html).bytes, decode, '../images');
    check(/<a id="filepos\d+"><\/a><h3 class="t">/.test(book.parts[2]), '落在标签内部的锚点挪到标签前', book.parts[2]);
  }

  console.log('errors');
  throwsWith(() => MobiBookParser.parse(utf8('plain text file '.repeat(10)), decode, ''), /不是有效的 MOBI/, '非 MOBI 文件');
  throwsWith(() => MobiBookParser.parse(buildMobi(template(), { encryption: 2 }).bytes, decode, ''), /DRM/, 'DRM 加密');
  throwsWith(() => MobiBookParser.parse(buildMobi(template(), { version: 8 }).bytes, decode, ''), /KF8/, 'KF8 格式');
  throwsWith(() => MobiBookParser.parse(buildMobi(template(), { compression: 17480 }).bytes, decode, ''), /HUFF/, 'HUFF/CDIC 压缩');
} finally {
  cleanup();
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall mobi parser checks passed');
