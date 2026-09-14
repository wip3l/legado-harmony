import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ReplaceRuleImport } from '../entry/src/main/ets/core/rule/ReplaceRuleImport.ts';
import { JavaRegexCompat } from '../entry/src/main/ets/core/rule/JavaRegexCompat.ts';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

let assertions = 0;

function assert(condition, message) {
  assertions++;
  if (!condition) {
    throw new Error(message);
  }
}

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

// 摘自 https://gitlab.com/GJTQQ/YueDu/raw/master/Share/Rule.txt 的前 6 条（原文 45 条）。
const yueduRules = [
  { enable: true, id: 1, regex: '(?<!\\d)6(?=[地离续])|(?<=[大着内])6', replaceSummary: '6/陆', replacement: '陆', serialNumber: 2 },
  { enable: true, id: 2, regex: 'cha(?=[槽头座队])', replaceSummary: 'cha/插', replacement: '插', serialNumber: 3 },
  { enable: true, id: 3, regex: 'chou(?=[天风雨季雷])|chou(?=[如])', replaceSummary: 'chou/春', replacement: '春', serialNumber: 4 },
  { enable: true, id: 4, regex: '(?<=[空晃]|dang)dang', replaceSummary: 'dang/荡', replacement: '荡', serialNumber: 5 },
  { enable: true, id: 5, regex: '(?<=[震振])dang', replaceSummary: 'dang/动', replacement: '动', serialNumber: 6 },
  { enable: true, id: 6, regex: '(?<=[空漏])dong', replaceSummary: 'dong/洞', replacement: '洞', serialNumber: 7 }
];

const yueduResult = ReplaceRuleImport.parse(JSON.stringify(yueduRules));
assert(yueduResult.formatLabel === '阅读(YueDu)', `YueDu 格式识别失败: ${yueduResult.formatLabel}`);
assert(yueduResult.rules.length === 6 && yueduResult.skipped === 0,
  `YueDu 条目数不符: ${yueduResult.rules.length}/${yueduResult.skipped}`);
assert(yueduResult.rules[0].pattern === '(?<!\\d)6(?=[地离续])|(?<=[大着内])6', 'regex 未映射到 pattern');
assert(yueduResult.rules[0].replacement === '陆', 'replacement 未映射');
assert(yueduResult.rules[0].name === '6/陆', 'replaceSummary 未作为名称回退');
assert(yueduResult.rules[0].isRegex === true, '无 isRegex 字段时应按正则处理');
assert(yueduResult.rules[0].enabled === true, 'enable 未映射到 enabled');
assert(yueduResult.rules[0].applyToTitle === true && yueduResult.rules[0].applyToContent === true,
  '缺省时应同时作用于标题与正文');
assert(yueduResult.rules[0].id === 1, 'id 未保留');
assert(yueduResult.rules[0].order === 2 && yueduResult.rules[5].order === 7,
  'serialNumber 未映射到顺序');
assert(yueduResult.rules.every((rule, index) =>
  index === 0 || rule.order > yueduResult.rules[index - 1].order), '导入顺序未按 serialNumber 排序');

// 乱序文件必须按 serialNumber 重排后再应用。
const shuffled = ReplaceRuleImport.parse(JSON.stringify(yueduRules.slice().reverse()));
assert(shuffled.rules[0].name === '6/陆' && shuffled.rules[0].order === 2, '倒序文件未按 serialNumber 重排');
assert(shuffled.rules.map(rule => rule.order).join(',') === '2,3,4,5,6,7', '重排后的顺序不符');

// 阅读(Legado) 导出的字段命名。
const legado = ReplaceRuleImport.parse(JSON.stringify([
  {
    name: '去掉广告行', group: '自定义', pattern: '^本章未完.*$', replacement: '',
    isRegex: true, isEnabled: true, isEnabledForTitle: false, isEnabledForContent: true,
    timeoutMillisecond: 5000, scope: '(小说|文学)', excludeScope: '起点', order: 1
  },
  { name: '纯文本替换', pattern: 'abc', replacement: 'xyz', isRegex: false, isEnabled: false }
]));
assert(legado.formatLabel === '阅读(Legado)', `Legado 格式识别失败: ${legado.formatLabel}`);
assert(legado.rules[0].applyToTitle === false && legado.rules[0].applyToContent === true,
  'isEnabledForTitle/Content 未映射');
assert(legado.rules[0].timeoutMs === 5000, 'timeoutMillisecond 未映射');
assert(legado.rules[0].scope === '/(小说|文学)/', `正则型 scope 未包成 /…/: ${legado.rules[0].scope}`);
assert(legado.rules[0].excludeScope === '起点', '纯子串 scope 不应被改造');
assert(legado.rules[1].isRegex === false, 'isRegex=false 未生效');
assert(legado.rules[1].enabled === false, 'isEnabled=false 未生效');
assert(legado.ignoredContentScope === 0, '无 scopeContent 时不应计数');

// 阅读的正文范围条件（scopeContent）本应用没有对应字段，必须计数提示而不是静默忽略。
const withContentScope = ReplaceRuleImport.parse(JSON.stringify([
  { name: '仅正文含广告时', pattern: 'x', replacement: 'y', scopeContent: '广告' },
  { name: '普通规则', pattern: 'a', replacement: 'b' }
]));
assert(withContentScope.ignoredContentScope === 1,
  `scopeContent 计数不符: ${withContentScope.ignoredContentScope}`);
assert(withContentScope.rules.length === 2, '带 scopeContent 的规则仍应导入');

// 本应用自己的导出格式继续可用，且不会因 group 缺省被改写成导入分组。
const own = ReplaceRuleImport.parse(JSON.stringify([
  { id: 1700000000000, name: '自建规则', group: '默认', pattern: 'x', replacement: 'y', isRegex: true, enabled: true }
]));
assert(own.formatLabel === '本应用', `本应用格式识别失败: ${own.formatLabel}`);
assert(own.rules[0].group === '默认' && own.rules[0].id === 1700000000000, '本应用字段未原样保留');

// 包装成一个对象的导出、BOM 头、以及缺字段的条目。
const wrapped = ReplaceRuleImport.parse('\uFEFF' + JSON.stringify({ version: 1, rules: yueduRules }));
assert(wrapped.rules.length === 6, '包装在 rules 字段里的数组未识别');
const mixed = ReplaceRuleImport.parse(JSON.stringify([...yueduRules, { id: 99, name: '坏条目' }, { id: 100, pattern: '' }]));
assert(mixed.rules.length === 6 && mixed.skipped === 2, `缺 pattern 的条目未计入跳过: ${mixed.rules.length}/${mixed.skipped}`);
assert(mixed.rules[0].group === '导入规则', '导入规则的分组缺省值不符');

// 结构性错误要抛出可读信息，而不是静默导入 0 条。
for (const [raw, fragment] of [
  ['', '为空'],
  ['不是 JSON', '不是有效的 JSON'],
  ['{"version":1}', '未找到规则数组'],
  ['[]', '未找到规则数组'],
  ['[{"id":1}]', '未识别到']
]) {
  let message = '';
  try {
    ReplaceRuleImport.parse(raw);
  } catch (error) {
    message = error.message;
  }
  assert(message.includes(fragment), `错误提示不符: ${raw} -> ${message}`);
}

// 导入的正则必须能过兼容层：YueDu 这份文件里有 26 条依赖后行断言。
for (const rule of yueduResult.rules) {
  assert(JavaRegexCompat.isSupported(rule.pattern, 'g'), `导入规则无法编译: ${rule.pattern}`);
}
assert(yueduResult.rules.filter(rule => /\(\?<[=!]/.test(rule.pattern)).length === 4,
  '样例里的后行断言条目数不符');

// 来源不是本应用时必须先弹转换确认；本应用自己的导出直接导入，不打扰用户。
assert(ReplaceRuleImport.needsConfirm(yueduResult) === true, 'YueDu 规则应先询问是否转换');
assert(ReplaceRuleImport.needsConfirm(legado) === true, 'Legado 规则应先询问是否转换');
assert(ReplaceRuleImport.needsConfirm(own) === false, '本应用导出的规则不应弹出转换确认');
assert(ReplaceRuleImport.confirmTitle(yueduResult).includes('阅读(YueDu)'), '确认标题未标明来源');
const yueduMessage = ReplaceRuleImport.confirmMessage(yueduResult);
assert(yueduMessage.includes('6 条规则') && yueduMessage.includes('Android/Java 方言'),
  `确认文案不符: ${yueduMessage}`);
assert(yueduMessage.includes('是否继续导入'), '确认文案缺少询问语句');
assert(!yueduMessage.includes('缺少匹配规则'), '无跳过条目时不应提示跳过');
assert(ReplaceRuleImport.confirmMessage(mixed).includes('2 条缺少匹配规则'), '确认文案未提示跳过条目');
assert(ReplaceRuleImport.confirmMessage(withContentScope).includes('正文范围条件'),
  '确认文案未提示被忽略的正文范围条件');

// 静态守卫：导入入口必须走适配器，不能再按本应用字段硬读，并且要按来源决定是否询问。
const page = read('entry/src/main/ets/pages/ReaderReplaceRules.ets');
assert(page.includes('ReplaceRuleImport.parse'), '导入页未使用适配器');
assert(page.includes('ReplaceRuleImport.needsConfirm(result)'), '导入页未按来源判断是否提示转换');
assert(page.includes('转换导入'), '导入页缺少转换确认按钮');
assert(!page.includes('decodeImportedRules'), '导入页仍保留旧的按字段硬读逻辑');
assert(read('entry/src/main/ets/utils/ReaderReplaceRuleStore.ets').includes('fromImportEntry'),
  '规则仓库缺少导入条目转换方法');

console.log(`Replace rule import check passed: ${assertions} assertions.`);
