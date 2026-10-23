#!/usr/bin/env node
// 页眉页脚槽位配置的回归检查：旧设置迁移后显示不变、损坏配置能回退、
// 槽位文字与进度计算正确，以及只有影响高度的项才会改变分页标识。
// Usage: node --experimental-strip-types scripts/reader-info-bar-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { ReaderInfoBarConfig: Config, ReaderInfoBarContext, ReaderInfoBarText: T, ReaderInfoItem: Item,
  ReaderInfoProgressBar: Bar, cleanup } = await loadReaderModules();

let failures = 0;
function check(condition, label, detail = '') {
  if (condition) return;
  failures++;
  console.error(`FAIL ${label}${detail ? `\n  ${detail}` : ''}`);
}
function equal(actual, expected, label) {
  check(actual === expected, label, `期望 ${JSON.stringify(expected)}，实际 ${JSON.stringify(actual)}`);
}

check(Item.VALUES.length === Item.LABELS.length, '信息项的值与名称一一对应');
check(new Set(Item.VALUES).size === Item.VALUES.length, '信息项的值不重复');

// 旧设置迁移：默认值。
const defaults = Config.fromLegacy('chapter', 'chapter', 'page', false);
equal(defaults.headerLeft, Item.CHAPTER_TITLE, '旧默认页眉 → 章节标题');
equal(defaults.footerLeft, Item.CHAPTER_INDEX_TITLE, '旧默认页脚左侧 → 章节序号 + 标题');
equal(defaults.footerRight, Item.PAGE, '旧默认阅读进度 → 页码');
equal(defaults.progressBar, Bar.NONE, '旧默认不显示进度条');
equal(defaults.serialize(), new Config().serialize(), '旧默认值迁移结果等于新默认配置');

// 旧设置迁移：非默认值。
const migrated = Config.fromLegacy('book_chapter', 'title', 'book', true);
equal(migrated.headerLeft, Item.BOOK_CHAPTER, '旧页眉"书名 + 章节标题"');
equal(migrated.footerLeft, Item.CHAPTER_TITLE, '旧页脚左侧"章节标题"');
equal(migrated.footerRight, Item.BOOK_PERCENT, '旧阅读进度"全书进度"');
equal(migrated.progressBar, Bar.FOOTER, '旧进度条开关 → 页脚上方');
equal(migrated.progressScope, Bar.SCOPE_BOOK, '旧全书进度模式下进度条表示全书');
equal(Config.fromLegacy('none', 'none', 'none', false).headerVisible(), false, '旧页眉"不显示"时页眉不占位');
equal(Config.fromLegacy('chapter', 'chapter', 'percentage', false).footerRight, Item.CHAPTER_PERCENT,
  '旧阅读进度"阅读百分比"');
equal(Config.fromLegacy('chapter', 'chapter', 'chapter', false).footerRight, Item.CHAPTER_PROGRESS,
  '旧阅读进度"章节进度"');

// 解析与回退。
equal(Config.parse(''), null, '空字符串解析为 null');
equal(Config.parse('{oops'), null, '损坏的 JSON 解析为 null');
const roundTrip = Config.parse(migrated.serialize());
equal(roundTrip.serialize(), migrated.serialize(), '序列化后再解析结果不变');
const dirty = Config.parse(JSON.stringify({ headerLeft: 'bogus', fontSize: 99, opacity: 1, progressBar: 'x' }));
equal(dirty.headerLeft, Item.CHAPTER_TITLE, '未知信息项回退到默认');
equal(dirty.headerFontSize, 40, '旧版过大字号迁移后页眉被限制为 40');
equal(dirty.footerFontSize, 40, '旧版过大字号迁移后页脚被限制为 40');
equal(dirty.headerOpacity, Config.OPACITY_MIN, '旧不透明度迁移到页眉时限制在下限');
equal(dirty.footerOpacity, Config.OPACITY_MIN, '旧不透明度迁移到页脚时限制在下限');
equal(dirty.progressBar, Bar.NONE, '未知进度条位置回退到不显示');

const legacySize = Config.parse(JSON.stringify({ fontSize: 15 }));
equal(legacySize.headerFontSize, 15, '旧共用字号沿用到页眉');
equal(legacySize.footerFontSize, 15, '旧共用字号沿用到页脚');
const separateSizes = Config.parse(JSON.stringify({ fontSize: 15, headerFontSize: 32, footerFontSize: 18 }));
equal(separateSizes.headerFontSize, 32, '独立页眉字号优先于旧字号');
equal(separateSizes.footerFontSize, 18, '独立页脚字号优先于旧字号');
equal(separateSizes.copy().serialize(), separateSizes.serialize(), '不同字号复制与序列化后保持不变');
equal(JSON.parse(separateSizes.serialize()).fontSize, undefined, '新配置不再保存旧共用字号');
const partialSize = Config.parse(JSON.stringify({ fontSize: 14, headerFontSize: 24 }));
equal(partialSize.headerFontSize, 24, '部分迁移的页眉使用新字号');
equal(partialSize.footerFontSize, 14, '部分迁移的页脚沿用旧字号');
const boundedSizes = Config.parse(JSON.stringify({ headerFontSize: 99, footerFontSize: 1 }));
equal(boundedSizes.headerFontSize, 40, '页眉字号上限为 40');
equal(boundedSizes.footerFontSize, 10, '页脚字号下限为 10');
const invalidSizes = Config.parse(JSON.stringify({ headerFontSize: 'bad', footerFontSize: {} }));
equal(invalidSizes.headerFontSize, 12, '无效页眉字号回退默认值');
equal(invalidSizes.footerFontSize, 12, '无效页脚字号回退默认值');

const legacyOpacity = Config.parse(JSON.stringify({ opacity: 60 }));
equal(legacyOpacity.headerOpacity, 60, '旧共用不透明度沿用到页眉');
equal(legacyOpacity.footerOpacity, 60, '旧共用不透明度沿用到页脚');
const separateOpacity = Config.parse(JSON.stringify({ opacity: 60, headerOpacity: 30, footerOpacity: 90 }));
equal(separateOpacity.headerOpacity, 30, '独立页眉不透明度优先于旧值');
equal(separateOpacity.footerOpacity, 90, '独立页脚不透明度优先于旧值');
equal(separateOpacity.copy().serialize(), separateOpacity.serialize(), '独立不透明度序列化与复制后保持不变');
equal(JSON.parse(separateOpacity.serialize()).opacity, undefined, '新配置不再保存旧共用不透明度');
for (const field of ['headerOpacity', 'footerOpacity']) {
  const other = field === 'headerOpacity' ? 'footerOpacity' : 'headerOpacity';
  const partial = Config.parse(JSON.stringify({ opacity: 60, [field]: 80 }));
  equal(partial[field], 80, `${field} 使用新值`);
  equal(partial[other], 60, `${other} 缺失时沿用旧值`);
  for (const [value, expected] of [[0, 30], [101, 100], ['bad', 100]]) {
    equal(Config.parse(JSON.stringify({ [field]: value }))[field], expected, `${field} 校验 ${value}`);
  }
  equal(new Config()[field], 100, `${field} 默认完全不透明`);
  const independent = new Config();
  independent[field] = 40;
  equal(independent.copy()[other], 100, `${field} 调整不影响另一项`);
  equal(independent.layoutIdentity(), new Config().layoutIdentity(), `${field} 调整不影响分页`);
}

// 分页标识：换内容不变，换高度相关项才变。
const base = new Config();
const contentOnly = base.copy();
contentOnly.headerRight = Item.TIME;
contentOnly.footerCenter = Item.BATTERY;
contentOnly.headerOpacity = 60;
contentOnly.footerOpacity = 80;
contentOnly.followMargin = true;
equal(contentOnly.layoutIdentity(), base.layoutIdentity(), '只换内容与外观不改变分页标识');
const bigger = base.copy();
bigger.headerFontSize = 40;
check(bigger.layoutIdentity() !== base.layoutIdentity(), '页眉字号变化改变分页标识');
equal(bigger.headerLineHeight(), 60, '大页眉字号同步增加行高');
equal(bigger.footerFontSize, 12, '调整页眉字号不影响页脚字号');
const biggerFooter = base.copy();
biggerFooter.footerFontSize = 40;
check(biggerFooter.layoutIdentity() !== base.layoutIdentity(), '页脚字号变化改变分页标识');
equal(biggerFooter.headerLineHeight(), base.headerLineHeight(), '调整页脚字号不影响页眉行高');
const withBar = base.copy();
withBar.progressBar = Bar.FOOTER;
check(withBar.layoutIdentity() !== base.layoutIdentity(), '进度条变化改变分页标识');
const shifted = base.copy();
shifted.footerOffset = 12;
check(shifted.layoutIdentity() !== base.layoutIdentity(), '页脚上移改变分页标识');
equal(Config.parse(JSON.stringify({ headerOffset: 999, footerOffset: -5 })).headerOffset, Config.OFFSET_MAX,
  '页眉下移被限制在上限');
equal(Config.parse(JSON.stringify({ footerOffset: -5 })).footerOffset, 0, '页脚上移不能为负');
equal(Config.parse(migrated.serialize()).footerOffset, 0, '旧配置没有位置偏移时默认为 0');
equal(base.headerLineHeight(), 18, '默认字号下页眉行高保持 18');
equal(base.footerExtraHeight(), 0, '默认配置页脚没有附加高度');
equal(withBar.footerExtraHeight(), 5, '页脚进度条附加高度保持 5');

// 时钟需求。
equal(base.usesClock(true, true), false, '默认配置不需要时钟');
equal(contentOnly.usesClock(true, false), true, '页眉用到时间时需要时钟');
equal(contentOnly.usesClock(false, false), false, '页眉页脚都关闭时不需要时钟');

// 槽位文字。
const context = new ReaderInfoBarContext();
context.bookName = '三体';
context.author = '刘慈欣';
context.chapterTitle = '第三章 红岸';
context.chapterIndex = 2;
context.chapterCount = 10;
context.pageIndex = 4;
context.pageCount = 20;
context.timeText = '21:05';
context.batteryPercent = 76;
equal(T.of(Item.NONE, context), '', '不显示');
equal(T.of(Item.BOOK, context), '三体', '书名');
equal(T.of(Item.AUTHOR, context), '刘慈欣', '作者');
equal(T.of(Item.CHAPTER_TITLE, context), '第三章 红岸', '章节标题');
equal(T.of(Item.CHAPTER_INDEX_TITLE, context), '3/10 第三章 红岸', '章节序号 + 标题');
equal(T.of(Item.BOOK_CHAPTER, context), '三体 · 第三章 红岸', '书名 + 章节标题');
equal(T.of(Item.PAGE, context), '5/20', '页码');
equal(T.of(Item.PAGES_LEFT, context), '剩余 15 页', '本章剩余页数');
equal(T.of(Item.CHAPTER_PERCENT, context), '25%', '本章百分比');
equal(T.of(Item.CHAPTER_PROGRESS, context), '3/10 章', '章节进度');
equal(T.of(Item.BOOK_PERCENT, context), '22.5%', '全书百分比包含章内进度');
equal(T.of(Item.TIME, context), '21:05', '时间');
equal(T.of(Item.BATTERY, context), '76%', '电量');
equal(T.leading(Item.BATTERY, context), '', '电量项没有前置文字');
equal(T.leading(Item.TIME_BATTERY, context), '21:05', '时间 + 电量的前置文字是时间');
equal(T.battery(Item.TIME_BATTERY, context), 76, '时间 + 电量需要画电池');
equal(T.battery(Item.PAGE, context), -1, '非电量项不画电池');

context.doublePage = true;
equal(T.of(Item.PAGE, context), '5-6/20', '双页页码');
equal(T.of(Item.PAGES_LEFT, context), '剩余 14 页', '双页剩余页数');
context.doublePage = false;

context.chapterIndex = 9;
context.pageIndex = 19;
equal(T.bookPercent(context), 100, '最后一章最后一页为 100%');
context.pageCount = 0;
context.pageIndex = 0;
equal(T.of(Item.PAGE, context), '1/1', '尚未分页时页码为 1/1');
context.batteryPercent = -1;
equal(T.battery(Item.BATTERY, context), -1, '读不到电量时不画电池');
context.chapterCount = 0;
equal(T.of(Item.CHAPTER_INDEX_TITLE, context), '三体', '没有目录时显示书名');

cleanup();

if (failures > 0) {
  console.error(`reader-info-bar-check: ${failures} 项失败`);
  process.exit(1);
}
console.log('reader-info-bar-check: ok');
