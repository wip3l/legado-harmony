import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';

const require = createRequire(import.meta.url);
const root = path.resolve(import.meta.dirname, '..');
const typescriptPaths = [
  'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js',
  'C:/Program Files/Huawei/DevEco Studio/plugins/codelinter/node_modules/typescript/lib/typescript.js'
];

let ts;
for (const candidate of typescriptPaths) {
  try {
    ts = require(candidate);
    break;
  } catch (_) {}
}
if (!ts) throw new Error('DevEco Studio TypeScript runtime not found');

const sourceUrl = 'https://www.yckceo.com/yuedu/shuyuans/json/id/1169.json';
const sourceMirrorUrl =
  'https://gcore.jsdelivr.net/gh/mumuceo/file01/202606/11780_e23645a35b55ac384f4fe66187b6148c.json';
const keyword = '他好可怕';
const expectedBookId = '1404068';

async function loadRuleModule() {
  const rulePath = path.join(root, 'entry/src/main/ets/core/rule/AnalyzeRule.ts');
  const jsonPath = path.join(root, 'entry/src/main/ets/core/rule/JsonPathEvaluator.ts');
  const jsRuntimePath = path.join(root, 'entry/src/main/ets/core/rule/JsRuntime.ts');
  const scriptEnginePath = path.join(root, 'entry/src/main/ets/core/rule/ScriptEngine.ts');
  const [ruleSource, jsonSource, jsSource, scriptEngineSource] = await Promise.all([
    fs.readFile(rulePath, 'utf8'), fs.readFile(jsonPath, 'utf8'), fs.readFile(jsRuntimePath, 'utf8'),
    fs.readFile(scriptEnginePath, 'utf8')
  ]);
  const stubs = `
const util = {
  TextEncoder: globalThis.TextEncoder,
  TextDecoder: { create: () => new globalThis.TextDecoder() },
  Base64Helper: class {
    encodeToStringSync(v) { return Buffer.from(v).toString('base64'); }
    decodeSync(v) { return new Uint8Array(Buffer.from(v, 'base64')); }
  }
};
const cryptoFramework = { createMd() { throw new Error('crypto not used by parser compatibility test'); } };
class CookieStore {
  static getCookie() { return ''; }
  static getCookieValue() { return ''; }
  static setCookies() {}
  static removeCookie() {}
  static saveAsync() {}
}
class RuleContext {
  constructor() { this.values = {}; }
  get(key) { return this.values[key] || ''; }
  put(key, value) { this.values[key] = value; return value; }
  toJson() { return JSON.stringify(this.values); }
}
const VerificationSupport = {
  isChallengeResponse: () => false,
  pickStartBrowserUrl: () => '',
  requestVerification: () => {}
};
const EncodedSourceUrl = {
  asMap: value => value || {},
  str: value => value === undefined || value === null ? '' : String(value).trim()
};
`;
  const combined = [
    stubs,
    stripImportsAndExports(jsSource),
    stripImportsAndExports(scriptEngineSource),
    stripImportsAndExports(jsonSource),
    stripImportsAndExports(ruleSource),
    'export { AnalyzeRule, JsonPathEvaluator, JsRuntime, RuleContext };'
  ].join('\n');
  const output = ts.transpileModule(combined, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 }
  }).outputText;
  const tempPath = path.join(root, '.hvigor', 'book-source-1169-compat.mjs');
  await fs.writeFile(tempPath, output, 'utf8');
  return import(`${pathToFileURL(tempPath).href}?v=${Date.now()}`);
}

function stripImportsAndExports(source) {
  return source.replace(/^import .*$/gm, '').replace(/\bexport\s+(?=(?:class|interface|type|const|function)\b)/g, '');
}

async function fetchText(url, headers = {}) {
  let lastError;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const response = await fetch(url, {
        redirect: 'follow',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
            '(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
          ...headers
        }
      });
      if (!response.ok) throw new Error(`${response.status} ${response.statusText}: ${url}`);
      return response.text();
    } catch (error) {
      lastError = error;
      await new Promise(resolve => setTimeout(resolve, 500 * (attempt + 1)));
    }
  }
  throw lastError;
}

async function fetchJsonApi(url) {
  let lastText = '';
  for (let attempt = 0; attempt < 4; attempt++) {
    lastText = await fetchText(url);
    try {
      const value = JSON.parse(lastText);
      if (value.code === 200) return lastText;
    } catch (_) {}
    await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1)));
  }
  throw new Error(`API business response is not successful: ${lastText.substring(0, 300)}`);
}

function expectEqual(name, actual, expected, checks) {
  const pass = JSON.stringify(actual) === JSON.stringify(expected);
  checks.push({ name, pass, actual, expected });
}

const { AnalyzeRule, JsRuntime } = await loadRuleModule();
let sourceText;
try {
  sourceText = await fetchText(sourceUrl);
} catch (_) {
  sourceText = await fetchText(sourceMirrorUrl);
}
const sourceList = JSON.parse(sourceText);
const source = sourceList[0];
const checks = [];

expectEqual('source name', source.bookSourceName, '🔰长佩文学', checks);

const js = new JsRuntime();
js.setVar('key', encodeURIComponent(keyword));
js.setVar('page', '1');
const searchUrl = js.evalTemplate(source.searchUrl);
expectEqual('search url', searchUrl,
  `https://webapi.gongzicp.com/search/novels?k=${encodeURIComponent(keyword)}&page=1`, checks);

const searchBody = await fetchJsonApi(searchUrl);
const searchRule = new AnalyzeRule(searchBody, searchUrl);
const searchItems = searchRule.getElements(source.ruleSearch.bookList);
const targetSearchItem = searchItems.find(item => {
  try { return String(JSON.parse(item).novel_id) === expectedBookId; } catch (_) { return false; }
});
expectEqual('search has parsed items', searchItems.length > 0, true, checks);
const firstSearch = new AnalyzeRule(targetSearchItem || searchItems[0] || '{}', searchUrl);
expectEqual('search name parsed', firstSearch.analyzeFirst(source.ruleSearch.name).length > 0, true, checks);
expectEqual('search author parsed', firstSearch.analyzeFirst(source.ruleSearch.author).length > 0, true, checks);
expectEqual('search kind parsed', firstSearch.analyzeFirst(source.ruleSearch.kind).length > 0, true, checks);
const parsedBookUrl = firstSearch.analyzeFirst(source.ruleSearch.bookUrl);
expectEqual('book url parsed', /novelInfo\?id=\d+/.test(parsedBookUrl), true, checks);
const bookUrl = `https://www.gongzicp.com/webapi/novel/novelInfo?id=${expectedBookId}`;

const detailBody = await fetchJsonApi(bookUrl);
const detailRoot = new AnalyzeRule(detailBody, bookUrl);
const detailItem = detailRoot.getString(source.ruleBookInfo.init);
const detailRule = new AnalyzeRule(detailItem, bookUrl);
expectEqual('detail name', detailRule.analyzeFirst(source.ruleBookInfo.name), keyword, checks);
expectEqual('detail author', detailRule.analyzeFirst(source.ruleBookInfo.author), '十八鹿', checks);
expectEqual('detail kind', detailRule.analyzeFirst(source.ruleBookInfo.kind), '纯爱', checks);
const tocUrl = detailRule.analyzeFirst(source.ruleBookInfo.tocUrl);
expectEqual('toc url', tocUrl,
  `https://www.gongzicp.com/webapi/novel/chapterGetList?nid=${expectedBookId}`, checks);

const tocBody = await fetchJsonApi(tocUrl);
const tocRoot = new AnalyzeRule(tocBody, tocUrl);
const chapters = tocRoot.getElements(source.ruleToc.chapterList);
expectEqual('chapter count', chapters.length >= 150, true, checks);
const volumeRule = new AnalyzeRule(chapters[0], tocUrl);
expectEqual('volume flag', volumeRule.analyzeFirst(source.ruleToc.isVolume), 'true', checks);
const firstChapterItem = chapters.find(item => JSON.parse(item).type === 'item');
const chapterRule = new AnalyzeRule(firstChapterItem, tocUrl);
expectEqual('chapter name', chapterRule.analyzeFirst(source.ruleToc.chapterName), '第1章', checks);
expectEqual('chapter vip', chapterRule.analyzeFirst(source.ruleToc.isVip), 'false', checks);
expectEqual('chapter update', chapterRule.analyzeFirst(source.ruleToc.updateTime),
  '2023-08-08 14:37:44  4303字', checks);
const chapterJs = source.ruleToc.chapterUrl.match(/<js>([\s\S]*?)<\/js>/)?.[1] || '';
expectEqual('chapter url js block', chapterRule.evalJsBlockSideEffects(chapterJs),
  `https://api1.gongzicp.com/apiv2/novel/getNovelChapterContents?nid=${expectedBookId}&chapter_ids=5336981`, checks);
expectEqual('chapter url after js block', chapterRule.applyJsBlocks(source.ruleToc.chapterUrl),
  `https://api1.gongzicp.com/apiv2/novel/getNovelChapterContents?nid=${expectedBookId}&chapter_ids=5336981\n@js:\n"{{$.type}}"=="volume"?"":result`, checks);
expectEqual('chapter url', chapterRule.analyzeFirst(source.ruleToc.chapterUrl),
  `https://api1.gongzicp.com/apiv2/novel/getNovelChapterContents?nid=${expectedBookId}&chapter_ids=5336981`, checks);

const chapterUrl = `https://api1.gongzicp.com/apiv2/novel/getNovelChapterContents?nid=${expectedBookId}&chapter_ids=5336981`;
const timestamp = String(Math.floor(Date.now() / 1000));
const version = source.jsLib.match(/\bver\s*=\s*["']([^"']+)["']/)?.[1] || 'android_02050803';
const salt = source.jsLib.match(/\bf\s*=\s*["']([^"']+)["']/)?.[1] || '';
const digest = createHash('sha256')
  .update(`chapter_ids=5336981&nid=${expectedBookId}${timestamp}${version}${salt}`, 'utf8').digest('hex');
const contentBody = await fetchText(chapterUrl, {
  'User-Agent': 'chang pei yue du/2.5.8.3 (Android 13; HarmonyOS; Mobile)',
  randStr: timestamp,
  version,
  requestKey: digest.substring(10, 42),
  client: 'android',
  imei: '455321005bc9cd38',
  referer: 'https://www.gongzicp.com',
  token: ''
});
const contentRoot = JSON.parse(contentBody);
const content = contentRoot?.data?.['5336981']?.content || '';
expectEqual('chapter content response', contentRoot.code, 1, checks);
expectEqual('chapter content text', content.startsWith('第一场秋雨'), true, checks);

for (const check of checks) {
  console.log(`${check.pass ? 'PASS' : 'FAIL'} ${check.name}`);
  if (!check.pass) console.log(`  expected=${JSON.stringify(check.expected)} actual=${JSON.stringify(check.actual)}`);
}
const failed = checks.filter(check => !check.pass);
console.log(`\n${checks.length - failed.length}/${checks.length} checks passed`);
if (failed.length > 0) process.exitCode = 1;
