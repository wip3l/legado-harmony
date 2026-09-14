import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
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

function applyRegexRule(text, pattern, replacement) {
  return text.replace(JavaRegexCompat.compile(pattern, 'g'),
    JavaRegexCompat.convertReplacement(replacement));
}

// 这份语料来自 Android 阅读书源与净化规则的常见写法：全部按 Java 正则方言书写，
// 直接交给 new RegExp 会抛 Invalid group / Nothing to repeat。
const androidDialectPatterns = [
  '(?m)(?<=(!|？))\\1+|(^\\w+: )?"([^\\w\\r\\n“”]*)”',
  '^.*正文卷|网\\W文\\W小\\W说|(?mi)^插图[^\\r\\n]*$',
  '<(center|font).+?</\\1>|<img\\b[^>]+>|</br>|&\\b(nbsp|quot|ampl|lt|gt);|#[a-zA-Z]+;',
  '(?is)<div[^>]*>.*?</div>',
  '(?i)(?:正文|作品相关)卷',
  '^(?i)<br\\s*/?>$',
  '\\s*+\\z',
  '(?>第[0-9]+章)[^\\r\\n]*',
  '\\Q【】\\E\\d+',
  '\\p{Lu}{2,}',
  '(?m)^\\h*$',
  '[\\h&&[^ ]]',
  '(?x) \\d+  # 章节序号',
  '(?i)(?s).+?\\z'
];

for (const pattern of androidDialectPatterns) {
  let compiled = null;
  let failure = '';
  try {
    compiled = JavaRegexCompat.compile(pattern, 'g');
  } catch (error) {
    failure = error.message;
  }
  assert(compiled !== null, `Android 方言正则无法编译: ${pattern} -> ${failure}`);
}

// 这些写法在 JavaScript 里直接抛错，正是本次修复针对的形态：
// 若哪天样例被改写成 JS 也能编译的形式，这条断言会提醒检查失去意义。
const rawFailurePatterns = [
  '(?m)(?<=(!|？))\\1+|(^\\w+: )?"([^\\w\\r\\n“”]*)”',
  '^.*正文卷|网\\W文\\W小\\W说|(?mi)^插图[^\\r\\n]*$',
  '(?is)<div[^>]*>.*?</div>',
  '(?i)(?:正文|作品相关)卷',
  '^(?i)<br\\s*/?>$',
  '\\s*+\\z',
  '(?>第[0-9]+章)[^\\r\\n]*',
  '(?x) \\d+  # 章节序号'
];
for (const pattern of rawFailurePatterns) {
  let threw = false;
  try {
    new RegExp(pattern, 'g');
  } catch (_) {
    threw = true;
  }
  assert(threw, `该 java 方言写法本应在 JavaScript 下失败: ${pattern}`);
}

// 未做改写时不应产生噪音提示，并且编译结果必须与原始 pattern 完全一致。
const exactPatterns = ['第\\d+章.*', 'a{2,3}', '(?:x|y)', '[^a-z]'];
for (const pattern of exactPatterns) {
  const conversion = JavaRegexCompat.convert(pattern, 'g');
  assert(conversion.notes.length === 0, `无改写却出现提示: ${pattern} -> ${conversion.notes}`);
  assert(conversion.source === pattern, `原文被意外改写: ${pattern} -> ${conversion.source}`);
}

// 行首内联标志只是搬到 flags 上，语义完全等价，因此不应产生提示。
for (const [pattern, expectedFlags] of [['(?i)abc', 'gi'], ['(?m)^a$', 'gm'], ['(?s).+', 'gs']]) {
  const conversion = JavaRegexCompat.convert(pattern, 'g');
  assert(conversion.flags === expectedFlags,
    `行首标志提升错误: ${pattern} -> ${conversion.flags}`);
  assert(conversion.notes.length === 0, `行首标志不应提示: ${pattern} -> ${conversion.notes}`);
}
assert(JavaRegexCompat.convert('(?i)(?s).+', 'g').flags === 'gis', '连续标志组未合并');
assert(JavaRegexCompat.convert('(?i)a(?-i)b', 'g').flags === 'g', '关闭标志未生效');
assert(JavaRegexCompat.convert('(?i)a(?-i)b', 'g').notes.length === 1 &&
  JavaRegexCompat.convert('(?i)a(?-i)b', 'g').notes[0].includes('(?-i)'),
  '关闭标志应提示位置差异');

// 行首内联标志提升后行为不变。
assert(applyRegexRule('a<br>b', '(?i)<BR>', '') === 'ab', '(?i) 未生效');
assert(applyRegexRule('第一行\n第二行', '(?m)^第二行$', '') === '第一行\n', '(?m) 未生效');
assert(applyRegexRule('a\nb', '(?s)a.b', 'X') === 'X', '(?s) 未生效');
assert(applyRegexRule('A\nB', '(?s)(?i)a.b', 'X') === 'X', '(?s)(?i) 组合未生效');

// 出现位置在中间的内联标志（乌云净化 #E3 的写法）必须同样生效，并给出提示。
const middleFlags = JavaRegexCompat.convert('^.*正文卷|(?mi)^插图[^\\r\\n]*$', 'g');
assert(middleFlags.flags.includes('m') && middleFlags.flags.includes('i'),
  `中置 (?mi) 未提升为标志: ${middleFlags.flags}`);
assert(middleFlags.notes.length === 1, `中置标志应给出一条提示: ${middleFlags.notes}`);
assert(applyRegexRule('插图：http://x/a.jpg\n正文开始', '^(?m)插图.*$|(?m)^.*正文卷',
  '') === '插图：http://x/a.jpg\n正文开始'.replace(/插图：http:\/\/x\/a\.jpg/, ''),
  '中置标志提升后行为不符');

// 乌云净化 #E2 标点规则：只保留第一个标点，删掉后面重复的叹号/问号。
const punctuationPattern = '(?m)(?<=(!|？))\\1+';
assert(applyRegexRule('真的？？？', punctuationPattern, '') === '真的？', '标点规则净化结果不符');
assert(applyRegexRule('走!!', punctuationPattern, '') === '走!', '感叹号规则未生效');

// 乌云净化 #E1 HTML 规则：清理标签与实体。
const htmlPattern = '<(center|font).+?</\\1>|<img\\b[^>]+>|</br>|&\\b(nbsp|quot|ampl|lt|gt);|#[a-zA-Z]+;';
assert(applyRegexRule('正文<img src="a.png">第一段&nbsp;结束', htmlPattern, '') === '正文第一段结束',
  'HTML 规则净化结果不符');

// 占有量词降级为贪婪量词后仍应匹配。
assert(applyRegexRule('  <br/>  ', '\\s*+<br\\s*/>\\s*+', '') === '', '占有量词未生效');
const possessive = JavaRegexCompat.convert('\\s*+', 'g');
assert(possessive.source === '\\s*' && possessive.notes.length === 1,
  `占有量词未被降级: ${possessive.source} / ${possessive.notes}`);

// 原子组降级为普通分组，不改变分组编号。
const atomic = JavaRegexCompat.convert('(?>a+)b', 'g');
assert(atomic.source === '(?:a+)b', `原子组未降级: ${atomic.source}`);
assert(applyRegexRule('aaab', '(?>a+)b', 'X') === 'X', '原子组降级后未匹配');

// \Q…\E 字面量引用、\h/\z/\R、字符类内的 \h。
assert(JavaRegexCompat.convert('\\Q第1章.\\E\\d+', 'g').source === '第1章\\.\\d+', '\\Q…\\E 未转义');
assert(applyRegexRule('第1章.7', '\\Q第1章.\\E\\d+', 'X') === 'X', '\\Q…\\E 匹配不符');
assert(applyRegexRule('换行\r\n结束', 'x\\R', 'x\t') === '换行\r\n结束', '\\R 不应误伤');
assert(applyRegexRule('第一行\r\n第二行', '行\\R', '行\n') === '第一行\n第二行', '\\R 未替换行分隔');
assert(JavaRegexCompat.convert('[\\h]', 'g').source === '[ \\t\\u00A0\\u1680\\u2000-\\u200A\\u202F\\u205F\\u3000]',
  '字符类内的 \\h 展开成了一个嵌套字符类');
assert(applyRegexRule('abc', 'abc\\z', 'X') === 'X', '\\z 未匹配结尾');

// \p{…} 需要 u 标志；Java 专有属性名要给出提示。
const unicodeProperty = JavaRegexCompat.convert('\\p{Lu}+', 'g');
assert(unicodeProperty.flags.includes('u'), '\\p{…} 未附带 u 标志');
assert(applyRegexRule('AB cd', '\\p{Lu}+', '') === ' cd', '\\p{…} 未生效');
assert(JavaRegexCompat.convert('\\p{InCJKUnifiedIdeographs}+', 'g').notes.length === 1,
  'Java 专有属性名应给出提示');
// u 模式下必须保留 JS 自己的 \u{…} 转义，不能把它拆成 \u 加字面量花括号。
const codePoint = JavaRegexCompat.convert('\\p{L}|\\u{1F600}', 'g');
assert(codePoint.source === '\\p{L}|\\u{1F600}', `\\u{…} 被破坏: ${codePoint.source}`);
assert(JavaRegexCompat.isSupported('\\p{L}|\\u{1F600}'), '\\u{…} 转换后无法编译');
// 字符类交集是 Java 专有语法，只能按字面量处理并提示。
assert(JavaRegexCompat.convert('[a-z&&[^bc]]', 'g').notes.length === 1,
  '字符类交集应给出提示');
// Java 专有锚点/转义在 JS 里会退化成字面量，必须提示而不是静默错配。
assert(JavaRegexCompat.convert('\\G\\d+', 'g').notes.length === 1, '\\G 应给出提示');
assert(JavaRegexCompat.convert('\\A第', 'g').notes.length === 1, '\\A 应给出提示');

// (?x) 自由空白模式按 Java 语义忽略空白与注释。
const commentsMode = JavaRegexCompat.convert('(?x) \\d+  # 序号', 'g');
assert(commentsMode.source === '\\d+', `(?x) 未忽略空白与注释: ${commentsMode.source}`);

// 替换串：Java 的 $0 是整个匹配，反斜杠是转义符。
assert(applyRegexRule('abc', '(b)', '[$0|$1]') === 'a[b|b]c', '$0 未映射到整个匹配');
assert(applyRegexRule('abc', 'b', '\\d') === 'adc', '替换串里的反斜杠应按 Java 语义转义');
assert(JavaRegexCompat.convertReplacement('$0$1$$') === '$&$1$$', '替换串转换结果不符');

// 无法转换的构造必须仍然可用 isSupported 识别出来，避免界面误报“有效”。
assert(!JavaRegexCompat.isSupported('a(') , '括号不配对应被判为不支持');
assert(JavaRegexCompat.isSupported('(?m)^a$'), '合法方言被误判为不支持');

// 仍然无法等价的写法要能被指名，便于用户在规则列表里看懂失败原因。
assert(JavaRegexCompat.unsupportedHint('\\p{InCJKUnifiedIdeographs}+').includes('Unicode 属性名'),
  '未识别 Java 专有属性名');
assert(JavaRegexCompat.unsupportedHint('[a-z&&[^bc]]').includes('字符类交集'), '未识别字符类交集');
assert(JavaRegexCompat.unsupportedHint('第\\d+章.{0,4}') === '', '普通规则不应报无法等价');

// 静态守卫：净化规则与书源正则的入口都必须走兼容层。
const replaceStore = read('entry/src/main/ets/utils/ReaderReplaceRuleStore.ets');
assert(replaceStore.includes('JavaRegexCompat.compile'), 'ReaderReplaceRuleStore 未使用兼容层');
// 书源作用域里的 /正则/标志 是本应用自己的语法（不是 Android 方言），因此允许直接编译。
assert(!/new RegExp\(\s*(?:rule\.pattern|pattern)/.test(replaceStore),
  'ReaderReplaceRuleStore 的匹配规则仍直接使用 new RegExp，Android 方言规则会再次失效');
assert(replaceStore.includes('JavaRegexCompat.unsupportedHint'),
  'ReaderReplaceRuleStore 未在编译失败时给出可读原因');
assert(read('entry/src/main/ets/pages/ReaderReplaceRules.ets').includes('JavaRegexCompat.compile'),
  'ReaderReplaceRules 保存校验未使用兼容层');
assert(read('entry/src/main/ets/core/rule/AnalyzeRule.ts').includes('JavaRegexCompat.compile'),
  'AnalyzeRule 未使用兼容层');
assert(read('entry/src/main/ets/core/book/WebBookService.ts').includes('JavaRegexCompat.compile'),
  'WebBookService 正文净化未使用兼容层');

console.log(`Java regex compat check passed: ${androidDialectPatterns.length} dialect patterns, ` +
  `${assertions} assertions.`);
