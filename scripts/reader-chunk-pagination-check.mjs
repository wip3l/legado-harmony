#!/usr/bin/env node
// 滚动阅读与漫画分块规则的回归检查。阅读进度按块索引保存，切块结果必须稳定，
// 且动作标记、图片标记不能被切开。
// Usage: node --experimental-strip-types scripts/reader-chunk-pagination-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { ReaderChunkPagination: C, ReaderTextNormalizer: N, ReaderChapterRange, ReaderPageTurnQueue, ReaderActionMarker, ReaderImageMarker,
  cleanup } = await loadReaderModules();

let failures = 0;
function check(condition, label, detail = '') {
  if (condition) return;
  failures++;
  console.error(`FAIL ${label}${detail ? `\n  ${detail}` : ''}`);
}
function consistent(source, result, label) {
  check(result.pages.length === result.starts.length && result.pages.length === result.ends.length,
    `${label}：三个数组等长`);
  let previousEnd = 0;
  for (let i = 0; i < result.pages.length; i++) {
    check(source.substring(result.starts[i], result.ends[i]) === result.pages[i], `${label}：块 ${i} 文本与偏移一致`);
    check(result.starts[i] >= previousEnd, `${label}：块 ${i} 不与前一块重叠`);
    check(result.pages[i].length > 0, `${label}：块 ${i} 非空`);
    check(!source.substring(previousEnd, result.starts[i]).trim(), `${label}：块 ${i} 之前没有丢正文`);
    previousEnd = result.ends[i];
  }
  check(!source.substring(previousEnd).trim(), `${label}：末尾没有丢正文`);
}
function markersIntact(result, prefix, suffix, label) {
  for (let i = 0; i < result.pages.length; i++) {
    const page = result.pages[i];
    let cursor = 0;
    while (true) {
      const start = page.indexOf(prefix, cursor);
      if (start < 0) break;
      const end = page.indexOf(suffix, start);
      check(end >= 0, `${label}：块 ${i} 里的标记是完整的`);
      if (end < 0) break;
      cursor = end + suffix.length;
    }
    // 没有只剩后半截的标记
    const firstSuffix = page.indexOf(suffix);
    const firstPrefix = page.indexOf(prefix);
    check(firstSuffix < 0 || (firstPrefix >= 0 && firstPrefix < firstSuffix), `${label}：块 ${i} 不以半截标记开头`);
  }
}

try {
  const paragraph = (n, size = 60) => `　　${String(n).padStart(3, '0')}${'字'.repeat(size)}。`;
  const paragraphs = [];
  for (let i = 0; i < 120; i++) paragraphs.push(paragraph(i));
  const plain = `第一章 测试\n\n${paragraphs.join('\n')}`;

  // ---- 滚动阅读 ----
  const continuous = C.splitContinuous(plain);
  consistent(plain, continuous, '滚动');
  check(continuous.pages.length > 3, '滚动：长章节被切成多块', `实际 ${continuous.pages.length}`);
  for (let i = 0; i < continuous.pages.length - 1; i++) {
    check(continuous.pages[i].length <= C.TARGET_LENGTH * 1.35 + 1, `滚动：块 ${i} 不超过上限`,
      `长度 ${continuous.pages[i].length}`);
    check(plain.charAt(continuous.ends[i]) === '\n', `滚动：块 ${i} 结束在段落边界`);
  }
  check(continuous.pages[1].startsWith('　　'), '滚动：块首保留段落缩进');
  for (let chars = 0; chars <= 4; chars++) {
    const source = N.indentChapterBody(paragraphs.join('\n'), chars);
    const result = C.splitContinuous(source);
    consistent(source, result, `滚动 ${chars} 字符缩进`);
    check(result.pages.every(page => page.startsWith('　'.repeat(chars)) && page.charAt(chars) !== '　'),
      `滚动：章节开头与每个段落块首均为 ${chars} 字符缩进`);
  }
  check(JSON.stringify(C.splitContinuous(plain)) === JSON.stringify(continuous), '滚动：结果确定');

  const short = C.splitContinuous('只有一句话。');
  check(short.pages.length === 1 && short.pages[0] === '只有一句话。', '滚动：短章节一块');
  check(C.splitContinuous('').pages.length === 0, '滚动：空章节无块');
  const blank = C.splitContinuous('\n　\n');
  check(blank.pages.length === 1 && blank.starts[0] === 0, '滚动：只有空白时回退为整章一块');

  // 没有换行的超长段落也必须前进并切完
  const wall = '墙'.repeat(C.TARGET_LENGTH * 3 + 17);
  const wallResult = C.splitContinuous(wall);
  consistent(wall, wallResult, '无换行长段');
  check(wallResult.pages.length === 4, '无换行长段：按上限硬切', `实际 ${wallResult.pages.length}`);
  const indentedWall = `　　${wall}`;
  const indentedWallResult = C.splitContinuous(indentedWall);
  consistent(indentedWall, indentedWallResult, '带缩进的超长段');
  check(indentedWallResult.pages[0].startsWith('　　'), '超长段：首行保留缩进');
  check(indentedWallResult.pages.slice(1).every(page => page.startsWith('墙')), '超长段：跨块续行不补缩进');

  // ---- 动作标记 ----
  const action = ReaderActionMarker.create('12', 'https://example.invalid/comment', '段评');
  const withActions = paragraphs.map((text) => `${text}${action}`).join('\n');
  const actionResult = C.splitContinuous(withActions);
  consistent(withActions, actionResult, '带段评');
  markersIntact(actionResult, ReaderActionMarker.PREFIX, ReaderActionMarker.SUFFIX, '带段评');

  const head = '头'.repeat(40);
  const inline = `${head}${action}尾`;
  check(C.adjustActionMarkerEnd(inline, 0, head.length + 5) === head.length + action.length,
    '行内标记被切到中间时整体并入本块');
  check(C.adjustActionMarkerEnd(inline, 0, head.length) === head.length + action.length,
    '终点紧贴行内标记之前时并入标记');
  const ownLine = `${head}\n${action}\n尾`;
  check(C.adjustActionMarkerEnd(ownLine, 0, head.length + 6) === head.length + 1,
    '独占一行的标记被切到中间时留给下一块');
  check(C.adjustActionMarkerEnd(ownLine, head.length + 1, head.length + 6) === head.length + 1 + action.length,
    '块首的独行标记整体并入');
  check(C.adjustActionMarkerEnd(head, 0, 10) === 10, '没有标记时终点不变');

  // ---- 漫画 ----
  const image = (n) => ReaderImageMarker.create(`/data/comic/${n}.jpg`);
  const sized = ReaderImageMarker.create('/data/comic/sized.jpg', 800, 1200);
  const comic = [image(1), image(2), sized, image(4)].join('\n\n');
  const comicResult = C.splitComic(comic);
  consistent(comic, comicResult, '漫画');
  check(comicResult.pages.length === 4, '漫画：每张图一块', `实际 ${comicResult.pages.length}`);
  check(comicResult.pages.every((page) => ReaderImageMarker.isMarker(page)), '漫画：每块正好是一个图片标记');
  check(comicResult.pages[2] === sized, '漫画：带尺寸的标记保持原样');

  const mixedComic = `作者的话：本话休刊。\n\n${image(1)}\n\n${paragraphs.slice(0, 60).join('\n')}\n\n${image(2)}`;
  const mixedResult = C.splitComic(mixedComic);
  consistent(mixedComic, mixedResult, '漫画夹文字');
  check(mixedResult.pages[0] === '作者的话：本话休刊。', '漫画：图片前的文字独立成块');
  check(ReaderImageMarker.isMarker(mixedResult.pages[1]), '漫画：文字后的图片独立成块');
  check(ReaderImageMarker.isMarker(mixedResult.pages[mixedResult.pages.length - 1]), '漫画：末尾图片独立成块');
  check(mixedResult.pages.filter((page) => ReaderImageMarker.isMarker(page)).length === 2, '漫画：图片数量不变');
  markersIntact(mixedResult, ReaderImageMarker.PREFIX, ReaderImageMarker.SUFFIX, '漫画夹文字');
  check(mixedResult.pages.length > 4, '漫画：图片之间的长文字继续切块');

  const errorText = C.splitComic('章节正文加载失败，请重试。');
  check(errorText.pages.length === 1, '漫画：纯文字提示一块');
  const broken = C.splitComic(`${ReaderImageMarker.PREFIX}没有结束`);
  check(broken.pages.length === 1, '漫画：残缺标记按文字处理而不是死循环');

  // ---- 章节范围输入 ----
  const range = (raw, total = 100) => JSON.stringify(ReaderChapterRange.parse(raw, total));
  check(range('1-3') === '[0,1,2]', '范围：1-3');
  check(range('3-1') === '[0,1,2]', '范围：倒写的区间');
  check(range('1,3,5-6') === '[0,2,4,5]', '范围：逗号与区间混写');
  check(range('5，3、3；1') === '[0,2,4]', '范围：中文分隔符、去重并排序');
  check(range('2 至 4') === '[]' && range('2至4') === '[1,2,3]', '范围：“至”紧贴数字才算区间');
  check(range('2～4') === '[1,2,3]', '范围：波浪号');
  check(range(' 7 ') === '[6]', '范围：单章');
  check(range('0-3') === '[]' && range('99-101') === '[]' && range('101') === '[]', '范围：越界整体无效');
  check(range('1-3,abc') === '[]' && range('一到三') === '[]', '范围：无法识别整体无效');
  check(range('') === '[]' && range('1-3', 0) === '[]', '范围：空输入或没有目录');

  // ---- 翻页排队 ----
  const queue = new ReaderPageTurnQueue();
  check(!queue.hasPending() && queue.take() === null, '排队：空队列取不到');
  queue.enqueue(1, 'tap', 0);
  queue.enqueue(1, 'tap', 3);
  queue.enqueue(1, 'tap', 1);
  check(queue.pendingCount() === 2, '排队：同方向最多保留两次');
  const first = queue.take();
  check(first.direction === 1 && first.style === 'tap' && first.velocity === 3, '排队：保留最大的松手速度');
  check(queue.hasPending() && queue.pendingCount() === 1, '排队：取走一次后还剩一次');
  queue.take();
  check(!queue.hasPending() && queue.take() === null, '排队：取完即空');
  queue.enqueue(1, 'tap', 0);
  queue.enqueue(-1, 'gesture', 2);
  check(queue.pendingCount() === 1 && queue.hasPendingBackward(), '排队：换方向时替换而不是累加');
  const taken = queue.take();
  check(queue.isCurrent(taken), '排队：未取消时已取出的翻页有效');
  queue.cancel();
  check(!queue.isCurrent(taken), '排队：取消后已取出但未开始的翻页作废');
  queue.enqueue(1, 'tap', 0);
  const survivor = queue.take();
  queue.enqueue(1, 'tap', 0);
  queue.reset();
  check(!queue.hasPending() && queue.isCurrent(survivor), '排队：清空等待项不影响已取出的翻页');
} finally {
  cleanup();
}

if (failures > 0) {
  console.error(`reader-chunk-pagination-check: ${failures} 项失败`);
  process.exit(1);
}
console.log('reader-chunk-pagination-check: ok');
