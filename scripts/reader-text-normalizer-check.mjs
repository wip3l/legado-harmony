#!/usr/bin/env node
// 正文归一化与页偏移映射的回归检查。阅读进度按章节字符偏移持久化，
// 这两块规则一旦漂移，已保存的进度会落到错误的页上。
// Usage: node --experimental-strip-types scripts/reader-text-normalizer-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { ReaderTextNormalizer: N, ReaderParagraphIndent: Indent, ReaderPageOffsets: O, ReaderActionMarker, ReaderImageMarker, cleanup } =
  await loadReaderModules();

let failures = 0;
function equal(actual, expected, label) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) return;
  failures++;
  console.error(`FAIL ${label}\n  expected ${e}\n  actual   ${a}`);
}

try {
  // ---- 空白与换行 ----
  equal(N.normalizeText('﻿  a\r\nb c\n\n\n\nd　\n'), 'a\nb c\n\nd', '归一化：BOM、CRLF、NBSP、连续空行、首尾全角空格');
  equal(N.trim('​　正文⁠\n'), '正文', '裁剪零宽与全角空格');
  equal(N.normalizeText(''), '', '空文本');

  // ---- 软换行合并 ----
  equal(N.mergeSoftWrappedLines('他走了过来\n，然后停下。'), '他走了过来，然后停下。', '下一行以标点开头时合并');
  equal(N.mergeSoftWrappedLines('他走了过来。\n然后停下。'), '他走了过来。\n然后停下。', '上一行以句末标点结束时不合并');
  equal(N.mergeSoftWrappedLines('短行没有标点\n另一短行'), '短行没有标点另一短行', '两行都短且无句末标点时合并');
  equal(N.mergeSoftWrappedLines('短行没有标点\n　　另一段'), '短行没有标点\n另一段', '下一行带缩进视为新段');
  equal(N.mergeSoftWrappedLines('短行没有标点\n第十二章 归来'), '短行没有标点\n第十二章 归来', '章节标题行不合并');
  equal(N.mergeSoftWrappedLines('The quick\nbrown fox'), 'The quick brown fox', '英文软换行补空格');
  equal(N.mergeSoftWrappedLines('inter-\nnational'), 'inter-national', '连字符断行不补空格');
  equal(N.mergeSoftWrappedLines('一段\n\n\n\n二段'), '一段\n\n二段', '段间空行压成一个');
  const long = '字'.repeat(48);
  equal(N.mergeSoftWrappedLines(`${long}\n短行`), `${long}\n短行`, '任一行达到 48 字不合并');

  const action = ReaderActionMarker.create('12', 'https://example.invalid/c', '段评');
  equal(N.mergeSoftWrappedLines(`短行${action}\n另一短行`), `短行${action}\n另一短行`, '带动作标记的行不合并');

  const inlineImage = ReaderImageMarker.create('images/b.png');
  equal(N.mergeSoftWrappedLines(`短行\n${inlineImage}\n，后续`), `短行\n${inlineImage}\n，后续`, '图片标记行不与相邻行合并');

  // ---- 段首缩进 ----
  equal(N.indentChapterBody('第一段。\n  第二段。\n　　第三段。'), '　　第一段。\n　　第二段。\n　　第三段。', '统一为两个全角空格缩进');
  equal(N.indentLine(''), '', '空行不缩进');
  const image = ReaderImageMarker.create('images/a.png', 100, 50);
  equal(N.indentLine(`  ${image}  `), image, '图片标记不缩进');
  equal(N.indentChapterBody(''), '', '空正文');
  for (let chars = 0; chars <= 4; chars++) {
    const prefix = '　'.repeat(chars);
    equal(N.indentChapterBody(`第一段。\n  第二段。\n　　　　第三段。\n\n${image}`, chars),
      `${prefix}第一段。\n${prefix}第二段。\n${prefix}第三段。\n\n${image}`, `${chars} 字符缩进应用于各段，保留空行与插图`);
    equal(N.indentLine('　　　　正文', chars), `${prefix}正文`, '已有缩进被替换而非叠加');
    for (let nextChars = 0; nextChars <= 4; nextChars++) {
      const before = `章节名\n\n${N.indentChapterBody('第一段。\n第二段。', chars)}`;
      const after = `章节名\n\n${N.indentChapterBody('第一段。\n第二段。', nextChars)}`;
      for (const token of ['章节名', '第一', '二段']) {
        equal(Indent.remapOffset(before, after, before.indexOf(token)), after.indexOf(token),
          `${chars} → ${nextChars} 字符后恢复 ${token} 的阅读位置`);
      }
      equal(Indent.remapOffset(before, after, before.length), after.length, '章末偏移恢复');
    }
  }
  for (const [value, expected] of [[undefined, 2], [NaN, 2], [Infinity, 2], [-1, 0], [9, 4], [1.6, 2]]) {
    equal(Indent.normalize(value), expected, '缺省或异常缩进值归一化');
  }
  equal(Indent.remapOffset('旧正文', '新正文', 2), 2, '正文改变时不做缩进偏移映射');

  // ---- 重复标题 ----
  equal(N.stripDuplicatedTitle('　　第一章 开端\n\n　　正文。', '第一章 开端'), '正文。', '首行与标题相同则剥离');
  equal(N.stripDuplicatedTitle('第一章 开端了\n正文。', '第一章 开端'), '第一章 开端了\n正文。', '首行只是以标题开头则保留');
  equal(N.stripDuplicatedTitle('正文。', ''), '正文。', '无标题时原样返回');
  const zwsp = String.fromCharCode(0x200b);
  const comment = ReaderActionMarker.create('段评 99+', 'https://example.invalid/p0', '段评');
  equal(N.stripDuplicatedTitle(`第1章${zwsp}戏鬼回家${comment}\n“我……是谁？”`, '第1章 戏鬼回家'), '“我……是谁？”',
    '零宽空格代替空格、标题行挂段评时仍剥离');
  const cover = ReaderImageMarker.create('https://example.invalid/cover.png');
  equal(N.stripDuplicatedTitle(`${cover}\n\n第1章${zwsp}戏鬼回家${comment}\n“我……是谁？”`, '第1章 戏鬼回家'),
    `${cover}\n\n“我……是谁？”`, '标题行前的卷首插图保留，只剥离标题行');
  equal(N.stripDuplicatedTitle(`${cover}\n正文第一段。`, '第1章 戏鬼回家'), `${cover}\n正文第一段。`,
    '插图后不是标题时原样返回');
  equal(N.stripDuplicatedTitle('第一章开端了\n正文。', '第一章 开端'), '第一章开端了\n正文。', '忽略空白后仍不同则保留');
  equal(N.splitLeadingImages(`${cover}\n\n　　正文。`), [cover, '　　正文。'], '拆出开头的卷首插图');
  equal(N.splitLeadingImages(`\n${cover}\n\n${inlineImage}\n　　正文。`), [`${cover}\n\n${inlineImage}`, '　　正文。'],
    '连续多张插图一起拆出');
  equal(N.splitLeadingImages('　　正文。'), ['', '　　正文。'], '开头不是图片时不拆');
  equal(N.sameTitle('第一卷：戏中人', `第一卷：${zwsp}戏中人 `), true, '标题比较忽略空白与零宽字符');
  equal(N.sameTitle('第一卷：戏中人', '第1章 戏鬼回家'), false, '不同标题');

  // ---- 分页起止裁剪 ----
  const source = '\n　　甲乙丙\n\n　　丁戊';
  let pages = [], starts = [], ends = [];
  N.pushPage(source, 0, 7, pages, starts, ends);
  N.pushPage(source, 7, source.length, pages, starts, ends);
  equal([pages, starts, ends], [['　　甲乙丙', '　　丁戊'], [1, 8], [6, 12]], '页首只跳过换行，始终保留段落缩进');
  pages = []; starts = []; ends = [];
  N.pushPage(source, 4, 6, pages, starts, ends);
  equal([pages, starts, ends], [['乙丙'], [4], [6]], '跨页续行不添加缩进');
  pages = []; starts = []; ends = [];
  N.pushPage(source, 6, 8, pages, starts, ends);
  equal(pages.length, 0, '裁完为空不产生空页');
  N.pushPage(source, -5, 999, pages, starts, ends);
  equal([starts[0], ends[0]], [1, 12], '越界区间被钳制');
  for (let i = 0; i < pages.length; i++) {
    equal(source.substring(starts[i], ends[i]), pages[i], `页文本与偏移一致 #${i}`);
  }

  // ---- 偏移 → 页 ----
  const pageStarts = [0, 12, 30];
  const pageEnds = [10, 28, 40];
  equal(O.pageIndexOf(pageStarts, pageEnds, 0, 40), 0, '偏移 0');
  equal(O.pageIndexOf(pageStarts, pageEnds, 9, 40), 0, '页内末字符');
  equal(O.pageIndexOf(pageStarts, pageEnds, 10, 40), 1, '页间被裁空白归后一页');
  equal(O.pageIndexOf(pageStarts, pageEnds, 12, 40), 1, '页首');
  equal(O.pageIndexOf(pageStarts, pageEnds, 29, 40), 2, '第二个页间空白');
  equal(O.pageIndexOf(pageStarts, pageEnds, 999, 40), 2, '越界偏移落在末页');
  equal(O.pageIndexOf(pageStarts, pageEnds, -3, 40), 0, '负偏移落在首页');
  equal(O.pageIndexOf([], [], 5, 40), -1, '尚未分页');
  // 增量分页只产出了前两页：目标偏移还没被覆盖时落在已有的最后一页，调用方据此判断继续等待。
  equal(O.pageIndexOf([0, 12], [10, 28], 35, 40), 1, '增量分页未覆盖目标偏移');

  equal(O.startOf(pageStarts, 1), 12, '页起点');
  equal(O.startOf(pageStarts, 99), 30, '页码越界取末页起点');
  equal(O.startOf([], 3), 0, '未分页起点为 0');
  equal(O.endOf(pageStarts, pageEnds, 1, 77), 28, '页终点');
  equal(O.endOf([], [], 0, 77), 77, '未分页终点用回退值');

  // 往返：每一页的起点都映射回它自己
  for (let i = 0; i < pageStarts.length; i++) {
    equal(O.pageIndexOf(pageStarts, pageEnds, O.startOf(pageStarts, i), 40), i, `页起点往返 #${i}`);
  }
} finally {
  cleanup();
}

if (failures > 0) {
  console.error(`reader-text-normalizer-check: ${failures} 项失败`);
  process.exit(1);
}
console.log('reader-text-normalizer-check: ok');
