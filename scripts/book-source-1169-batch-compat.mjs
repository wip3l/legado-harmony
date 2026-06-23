import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const root = path.resolve(import.meta.dirname, '..');
const typescriptPaths = [
  'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js',
  'C:/Program Files/Huawei/DevEco Studio/plugins/codelinter/node_modules/typescript/lib/typescript.js'
];

const sourceUrl = 'https://www.yckceo.com/yuedu/shuyuans/json/id/1169.json';
const sourceMirrorUrl =
  'https://gcore.jsdelivr.net/gh/mumuceo/file01/202606/11780_e23645a35b55ac384f4fe66187b6148c.json';
const keyword = process.env.BOOK_SOURCE_KEYWORD || '斗破苍穹';
const onlineTarget = Number(process.env.BOOK_SOURCE_ONLINE_TARGET || '10');
const onlineChainTarget = Number(process.env.BOOK_SOURCE_CHAIN_TARGET || '10');
const timeoutMs = Number(process.env.BOOK_SOURCE_TIMEOUT_MS || '5000');
const chainTimeoutMs = Number(process.env.BOOK_SOURCE_CHAIN_TIMEOUT_MS || '10000');
const onlineMaxAttempts = Number(process.env.BOOK_SOURCE_ONLINE_ATTEMPTS || '80');
const sourceFilter = String(process.env.BOOK_SOURCE_FILTER || '').trim().toLowerCase();

let ts;
for (const candidate of typescriptPaths) {
  try {
    ts = require(candidate);
    break;
  } catch (_) {}
}
if (!ts) throw new Error('DevEco Studio TypeScript runtime not found');

async function loadModules() {
  const files = [
    'entry/src/main/ets/core/rule/JsRuntime.ts',
    'entry/src/main/ets/core/rule/JsonPathEvaluator.ts',
    'entry/src/main/ets/core/rule/AjaxRuleCompat.ts',
    'entry/src/main/ets/core/rule/AnalyzeRule.ts',
    'entry/src/main/ets/core/rule/AnalyzeUrl.ts'
  ];
  const sources = await Promise.all(files.map(file => fs.readFile(path.join(root, file), 'utf8')));
  const stubs = [
    "class CompatTextEncoder {",
    "  constructor(label) { this.label = label || 'utf-8'; }",
    "  encodeInto(value) { return new Uint8Array(Buffer.from(String(value), 'utf8')); }",
    "  encode(value) { return new Uint8Array(Buffer.from(String(value), 'utf8')); }",
    "}",
    "const util = {",
    "  TextEncoder: CompatTextEncoder,",
    "  TextDecoder: { create: () => new globalThis.TextDecoder() },",
    "  Base64Helper: class {",
    "    encodeToStringSync(v) { return Buffer.from(v).toString('base64'); }",
    "    decodeSync(v) { return new Uint8Array(Buffer.from(v, 'base64')); }",
    "  }",
    "};",
    "const cryptoFramework = { createMd() { throw new Error('crypto not used by batch compatibility scan'); } };",
    "class CookieStore {",
    "  static getCookie() { return ''; }",
    "  static getCookieValue() { return ''; }",
    "  static setCookies() {}",
    "  static removeCookie() {}",
    "  static saveAsync() {}",
    "}",
    "class RuleContext {",
    "  constructor() { this.values = {}; }",
    "  get(key) { return this.values[key] || ''; }",
    "  put(key, value) { this.values[key] = value; return value; }",
    "  toJson() { return JSON.stringify(this.values); }",
    "}",
    "const VerificationSupport = {",
    "  sourceCookieHeader: () => '',",
    "  isChallengeResponse: () => false,",
    "  shouldRequestBrowserVerification: () => false,",
    "  pickStartBrowserUrl: () => '',",
    "  pickVerificationUrl: () => '',",
    "  requestVerification: () => {}",
    "};",
    "const EncodedSourceUrl = {",
    "  asMap: value => value || {},",
    "  encode: (value, type) => 'data:application/json;type=' + encodeURIComponent(type || '') + ';base64,' + Buffer.from(JSON.stringify(value || {})).toString('base64'),",
    "  encodeRaw: (value, type, host) => 'data:;type=' + encodeURIComponent(type || '') + ';host=' + encodeURIComponent(host || '') + ';base64,' + Buffer.from(String(value || '')).toString('base64')",
    "};"
  ].join('\n');
  const combined = [
    stubs,
    ...sources.map(stripImportsAndExports),
    'export { AjaxRuleCompat, AnalyzeRule, AnalyzeUrl, JsonPathEvaluator, JsRuntime, RuleContext };'
  ].join('\n');
  const output = ts.transpileModule(combined, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 }
  }).outputText;
  const tempPath = path.join(root, '.hvigor', 'book-source-1169-batch-compat.mjs');
  await fs.writeFile(tempPath, output, 'utf8');
  return import(pathToFileURL(tempPath).href + '?v=' + Date.now());
}

function stripImportsAndExports(source) {
  return source.replace(/^import .*$/gm, '').replace(/\bexport\s+(?=(?:class|interface|type|const|function)\b)/g, '');
}

async function fetchText(url, headers = {}, timeout = timeoutMs) {
  let lastError;
  for (let attempt = 0; attempt < 3; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      const response = await fetch(url, {
        redirect: 'follow',
        signal: controller.signal,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
            '(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
          ...headers
        }
      });
      if (!response.ok) throw new Error(String(response.status) + ' ' + response.statusText + ': ' + url);
      const buffer = await response.arrayBuffer();
      return decodeBody(buffer, charsetFromContentType(response.headers.get('content-type') || ''));
    } catch (error) {
      lastError = error;
      await sleep(350 * (attempt + 1));
    } finally {
      clearTimeout(timer);
    }
  }
  throw lastError;
}

function decodeBody(buffer, charset = '') {
  const normalized = normalizeCharset(charset);
  try {
    return new TextDecoder(normalized || 'utf-8').decode(buffer);
  } catch (_) {
    return new TextDecoder('utf-8').decode(buffer);
  }
}

function normalizeCharset(charset) {
  const value = String(charset || '').trim().toLowerCase();
  if (!value) return '';
  if (value === 'gbk' || value === 'gb2312') return 'gb18030';
  return value;
}

function charsetFromContentType(contentType) {
  const match = String(contentType || '').match(/charset\s*=\s*["']?([^;"'\s]+)/i);
  return match ? match[1] : '';
}

async function loadSourceList() {
  try {
    return JSON.parse(await fetchText(sourceUrl));
  } catch (_) {
    return JSON.parse(await fetchText(sourceMirrorUrl));
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function normalizeSource(source) {
  return {
    ...source,
    searchRule: source.searchRule || source.ruleSearch || {},
    ruleSearch: source.ruleSearch || source.searchRule || {},
    ruleBookInfo: source.ruleBookInfo || source.bookInfoRule || {},
    ruleToc: source.ruleToc || source.tocRule || {},
    ruleContent: source.ruleContent || source.contentRule || {}
  };
}

function collectRuleStrings(source) {
  return {
    searchUrl: [source.searchUrl || ''],
    exploreUrl: [source.exploreUrl || ''],
    loginUrl: [source.loginUrl || ''],
    header: [source.header || ''],
    jsLib: [source.jsLib || ''],
    ruleSearch: flattenStrings(source.ruleSearch || source.searchRule || {}),
    ruleBookInfo: flattenStrings(source.ruleBookInfo || source.bookInfoRule || {}),
    ruleToc: flattenStrings(source.ruleToc || source.tocRule || {}),
    ruleContent: flattenStrings(source.ruleContent || source.contentRule || {})
  };
}

function flattenStrings(value, out = []) {
  if (typeof value === 'string') {
    if (value.trim()) out.push(value);
  } else if (Array.isArray(value)) {
    for (const item of value) flattenStrings(item, out);
  } else if (value && typeof value === 'object') {
    for (const key of Object.keys(value)) flattenStrings(value[key], out);
  }
  return out;
}

function classify(text) {
  const v = String(text || '');
  return {
    jsonPath: /(^|[|&%>\n\r\s])(\$|@\.)[.\[]/.test(v) || /(^|[|&%>\n\r\s])\$\.\./.test(v),
    css: /@css:|(^|[|&%>\n\r\s])[.#][\w-]|&&/.test(v),
    xpath: /(^|[|&%>\n\r\s])\/{1,2}[A-Za-z*]/.test(v) || /@XPath:|@xpath:/.test(v),
    regex: /##|@replace:|@match:|:\{[\s\S]*?\}/.test(v),
    js: /<js>|@js:|\{\{[\s\S]*?\}\}/.test(v),
    java: /java\./.test(v),
    ajax: /java\.ajax|java\.ajaxAll/.test(v),
    cookie: /Cookie|cookie|java\.getCookie|java\.cookie/.test(v),
    encoding: /charset|gbk|gb2312|base64|decode|encodeURI|unescape|escape/.test(v),
    crypto: /md5|sha|HMac|AES|DES|crypto|requestKey|digest/i.test(v),
    post: /"method"\s*:\s*"POST"|'method'\s*:\s*'POST'|method=POST/i.test(v)
  };
}

function addStats(stats, text) {
  const c = classify(text);
  for (const key of Object.keys(c)) {
    if (c[key]) stats[key] = (stats[key] || 0) + 1;
  }
}

function seedRule(rule, keywordValue) {
  rule.setJsVar('key', encodeURIComponent(keywordValue));
  rule.setJsVar('searchKey', encodeURIComponent(keywordValue));
  rule.setJsVar('keyword', encodeURIComponent(keywordValue));
  rule.setJsVar('searchKeyRaw', keywordValue);
  rule.setJsVar('page', '1');
  rule.getContext().put('key', encodeURIComponent(keywordValue));
  rule.getContext().put('page', '1');
}

function offlineSmoke(source, AnalyzeRule) {
  const failures = [];
  const jsonSample = JSON.stringify({
    code: 200,
    data: {
      list: [
        { name: '斗破苍穹', title: '斗破苍穹', author: '天蚕土豆', bookUrl: '/book/1', url: '/book/1',
          id: 1, type: 'item', chapter_id: 1, chapter_name: '第1章', content: '正文' }
      ],
      book: { name: '斗破苍穹', author: '天蚕土豆', intro: '简介', tocUrl: '/toc/1' },
      content: '正文'
    },
    list: [
      { name: '斗破苍穹', title: '斗破苍穹', author: '天蚕土豆', url: '/book/1', type: 'item',
        chapter_id: 1, chapter_name: '第1章', content: '正文' }
    ]
  });
  const htmlSample =
    '<html><body><div class="book"><a class="name" href="/book/1">斗破苍穹</a>' +
    '<span class="author">天蚕土豆</span><p class="intro">简介</p></div>' +
    '<ul class="chapter"><li><a href="/c/1">第1章</a></li></ul><div id="content">正文</div></body></html>';
  const buckets = collectRuleStrings(source);
  for (const bucketName of ['ruleSearch', 'ruleBookInfo', 'ruleToc', 'ruleContent']) {
    for (const text of buckets[bucketName]) {
      if (!text || text.length > 4000) continue;
      for (const content of [jsonSample, htmlSample]) {
        try {
          const rule = new AnalyzeRule(content, source.bookSourceUrl || '');
          seedRule(rule, keyword);
          if (/bookList|chapterList|list|\[\*\]|\$\.data\.list/.test(text)) rule.getElements(text);
          else rule.analyzeFirst(text);
        } catch (error) {
          failures.push({
            source: source.bookSourceName,
            bucket: bucketName,
            rule: compact(text),
            error: compact(String(error && error.stack || error))
          });
        }
      }
    }
  }
  return failures;
}

function compact(value, max = 220) {
  const oneLine = String(value || '').replace(/\s+/g, ' ').trim();
  return oneLine.length > max ? oneLine.substring(0, max) + '...' : oneLine;
}

function buildSearchTemplate(source, JsRuntime) {
  const js = new JsRuntime();
  js.setVar('key', encodeURIComponent(keyword));
  js.setVar('searchKey', encodeURIComponent(keyword));
  js.setVar('keyword', encodeURIComponent(keyword));
  js.setVar('searchKeyRaw', keyword);
  js.setVar('page', '1');
  js.setVar('pageIndex', '1');
  return js.evalTemplate(source.searchUrl || '');
}

function isOnlineCandidate(source) {
  const searchRule = source.ruleSearch || source.searchRule || {};
  if (!source.searchUrl || !searchRule.bookList || !searchRule.name || !searchRule.bookUrl) return false;
  if (/kdocs|longToast|source\.loginUrl|getVariable\(\)\s*==|java\.ajaxAll|webView|验证码/.test(source.searchUrl || '')) return false;
  return /https?:\/\//.test(source.searchUrl) || String(source.searchUrl).trim().startsWith('/');
}

function matchesSourceFilter(source) {
  if (!sourceFilter) return true;
  return [source.bookSourceName, source.bookSourceUrl, source.searchUrl]
    .some(value => String(value || '').toLowerCase().includes(sourceFilter));
}

function sourceScore(source) {
  const all = Object.values(collectRuleStrings(source)).flat().join('\n');
  const c = classify(all);
  let score = 0;
  for (const key of Object.keys(c)) if (c[key]) score += 1;
  if ((source.searchUrl || '').includes('"method"') || (source.searchUrl || '').includes("'method'")) score += 2;
  if ((source.searchUrl || '').startsWith('/')) score += 1;
  return score;
}

async function fetchRequest(request) {
  const method = (request.method || 'GET').toUpperCase();
  const headers = { ...(request.headers || {}) };
  const init = { method, redirect: 'follow', headers };
  if (method !== 'GET' && method !== 'HEAD' && request.body) init.body = request.body;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(request.url, { ...init, signal: controller.signal });
    const buffer = await response.arrayBuffer();
    const body = decodeBody(buffer, request.charset || charsetFromContentType(response.headers.get('content-type') || ''));
    return { body, statusCode: response.status, url: response.url, ok: response.ok };
  } finally {
    clearTimeout(timer);
  }
}

async function runOnline(source, modules) {
  const { AnalyzeRule, AnalyzeUrl, JsRuntime } = modules;
  const searchRule = source.ruleSearch || source.searchRule || {};
  const au = new AnalyzeUrl(source, { execute: async request => {
    try {
      const response = await fetchRequest(request);
      return { url: response.url, statusCode: response.statusCode, headers: {}, body: response.body, success: response.ok };
    } catch (error) {
      return { url: request.url, statusCode: 0, headers: {}, body: '', success: false, error: String(error) };
    }
  }});
  const template = buildSearchTemplate(source, JsRuntime);
  const built = au.parse(template);
  const request = au.buildRequest();
  if (!/^https?:\/\//.test(request.url)) throw new Error('search URL is not absolute: ' + request.url);
  const response = built.method === 'GET' ? await fetchRequest(request) : await au.fetch(template);
  const body = response.body || '';
  if (!body) throw new Error('empty search response');
  return parseSearchResponse(source, searchRule, body, response.url || request.url, AnalyzeRule);
}

function parseSearchResponse(source, searchRule, body, baseUrl, AnalyzeRule) {
  const rootRule = new AnalyzeRule(body, baseUrl);
  seedRule(rootRule, keyword);
  const items = rootRule.getElements(searchRule.bookList || '');
  if (items.length <= 0) throw new Error('search parsed 0 items');
  const first = new AnalyzeRule(items[0], baseUrl);
  seedRule(first, keyword);
  const name = first.analyzeFirst(searchRule.name || '');
  const author = first.analyzeFirst(searchRule.author || '');
  const bookUrl = first.analyzeFirst(searchRule.bookUrl || '');
  if (!name || !bookUrl || hasUnresolvedRule(name) || hasUnresolvedRule(bookUrl) || !isRelevantSearchName(name)) {
    throw new Error('first item has unresolved or irrelevant name/bookUrl');
  }
  return {
    source: source.bookSourceName,
    count: items.length,
    name: compact(name, 80),
    author: compact(author, 80),
    bookUrl: compact(bookUrl, 120),
    bookUrlFull: bookUrl,
    searchBaseUrl: baseUrl
  };
}

function hasUnresolvedRule(value) {
  return /\{\{|\}\}|\{\$\.|\$\.\.?|@js:|<js>/i.test(String(value || ''));
}

function isRelevantSearchName(value) {
  const name = String(value || '').replace(/\s+/g, '');
  const expected = String(keyword || '').replace(/\s+/g, '');
  if (!name || !expected) return false;
  return name.includes(expected) || (expected.length >= 2 && name.includes(expected.substring(0, 2)));
}

function canAttemptChain(source, result) {
  const detailRule = source.ruleBookInfo || {};
  const tocRule = source.ruleToc || {};
  const contentRule = source.ruleContent || {};
  const url = String(result.bookUrlFull || '').trim();
  if (!detailRule || !tocRule || !contentRule) return false;
  if (!tocRule.chapterList || !tocRule.chapterUrl || !contentRule.content) return false;
  if (!url || /javascript:|history\.go|^\{|\}$/.test(url)) return false;
  return /^https?:\/\//.test(url) || url.startsWith('/') || /^[A-Za-z0-9_.~!$&'()*+,;=:@%-]+(?:\/|$)/.test(url);
}

function resolveUrl(value, baseUrl, sourceUrlValue = '') {
  const url = String(value || '').trim();
  if (!url) return '';
  if (/^https?:\/\//.test(url) || url.startsWith('data:')) return url;
  if (url.startsWith('//')) return 'https:' + url;
  const base = String(baseUrl || sourceUrlValue || '').split('##')[0];
  if (!base) return url;
  const origin = base.match(/^(https?:\/\/[^/]+)/);
  if (url.startsWith('/')) return origin ? origin[1] + url : url;
  const clean = base.split('?')[0];
  const dir = clean.endsWith('/') ? clean : clean.replace(/\/[^/]*$/, '/');
  return dir + url;
}

function sourceHeaders(source) {
  const value = String(source.header || '').trim();
  if (!value) return {};
  try {
    return JSON.parse(value.replace(/'/g, '"'));
  } catch (_) {
    const headers = {};
    for (const line of value.split(/[\r\n]+/)) {
      const index = line.indexOf(':');
      if (index > 0) headers[line.substring(0, index).trim()] = line.substring(index + 1).trim();
    }
    return headers;
  }
}

function fetchSourceText(source, url) {
  return fetchText(url, sourceHeaders(source), chainTimeoutMs);
}

async function runBookChain(source, searchResult, modules) {
  const { AnalyzeRule, RuleContext } = modules;
  const detailRule = source.ruleBookInfo || {};
  const tocRule = source.ruleToc || {};
  const contentRule = source.ruleContent || {};
  const chain = { detail: false, toc: false, content: false, error: '' };
  const ctx = new RuleContext();
  try {
    const detailUrl = resolveUrl(searchResult.bookUrlFull, searchResult.searchBaseUrl, source.bookSourceUrl);
    if (!detailUrl || !/^https?:\/\//.test(detailUrl)) throw new Error('invalid detail url');
    const detailBody = await fetchSourceText(source, detailUrl);
    let detailContent = detailBody;
    if (detailRule.init) {
      const initRule = new AnalyzeRule(detailBody, detailUrl, ctx);
      seedRule(initRule, keyword);
      detailContent = initRule.getString(detailRule.init) || detailBody;
    }
    const detailAnalyze = new AnalyzeRule(detailContent, detailUrl, ctx);
    seedRule(detailAnalyze, keyword);
    if (detailRule.name) detailAnalyze.analyzeFirst(detailRule.name);
    chain.detail = true;

    const tocUrlValue = detailRule.tocUrl ? detailAnalyze.analyzeFirst(detailRule.tocUrl) : '';
    const tocUrl = resolveUrl(tocUrlValue || detailUrl, detailUrl, source.bookSourceUrl);
    if (!tocRule.chapterList || !/^https?:\/\//.test(tocUrl)) return chain;
    const tocBody = await fetchSourceText(source, tocUrl);
    const tocAnalyze = new AnalyzeRule(tocBody, tocUrl, ctx);
    seedRule(tocAnalyze, keyword);
    const chapters = tocAnalyze.getElements(tocRule.chapterList);
    if (chapters.length <= 0) throw new Error('toc parsed 0 chapters');
    chain.toc = true;

    if (!tocRule.chapterUrl || !contentRule.content) return chain;
    let lastChapterUrl = '';
    let lastContentLength = 0;
    for (const item of chapters.slice(0, 5)) {
      const chapterAnalyze = new AnalyzeRule(item, tocUrl, ctx);
      seedRule(chapterAnalyze, keyword);
      const isVolume = tocRule.isVolume ? chapterAnalyze.analyzeFirst(tocRule.isVolume) : '';
      if (String(isVolume).toLowerCase() === 'true') continue;
      const chapterUrl = resolveUrl(chapterAnalyze.analyzeFirst(tocRule.chapterUrl), tocUrl, source.bookSourceUrl);
      if (!/^https?:\/\//.test(chapterUrl) || /javascript:|history\.go/i.test(chapterUrl)) continue;
      lastChapterUrl = chapterUrl;
      const contentBody = await fetchSourceText(source, chapterUrl);
      const contentAnalyze = new AnalyzeRule(contentBody, chapterUrl, ctx);
      seedRule(contentAnalyze, keyword);
      const content = contentAnalyze.analyzeFirst(contentRule.content || '');
      lastContentLength = content.length;
      if (content && content.length > 10) {
        chain.content = true;
        break;
      }
    }
    if (!chain.content) {
      chain.error = 'content parsed empty len=' + lastContentLength + ' url=' + compact(lastChapterUrl, 100);
    }
    return chain;
  } catch (error) {
    chain.error = compact(String(error && error.message || error), 160);
    return chain;
  }
}

function printStats(sourceList, syntaxStats, offlineFailures, onlineResults, onlineFailures, onlineAttempts, chainResults) {
  const keys = ['jsonPath', 'css', 'xpath', 'regex', 'js', 'java', 'ajax', 'cookie', 'encoding', 'crypto', 'post'];
  console.log('Sources: ' + sourceList.length);
  console.log('Syntax coverage:');
  for (const key of keys) console.log('  ' + key.padEnd(9) + String(syntaxStats[key] || 0).padStart(4));
  console.log('');
  console.log('Offline smoke: ' + (sourceList.length - offlineFailures.sourceCount) + '/' + sourceList.length +
    ' sources without parser exceptions, ' + offlineFailures.items.length + ' rule failures');
  for (const item of offlineFailures.items.slice(0, 12)) {
    console.log('  FAIL ' + item.source + ' [' + item.bucket + '] ' + item.error + ' :: ' + item.rule);
  }
  console.log('');
  console.log('Online search: ' + onlineResults.length + '/' + onlineTarget +
    ' representative sources passed, attempts=' + onlineAttempts + '/' + onlineMaxAttempts);
  for (const item of onlineResults) {
    console.log('  PASS ' + item.source + ' count=' + item.count + ' name=' + item.name);
  }
  for (const item of onlineFailures.slice(0, 12)) {
    console.log('  FAIL ' + item.source + ' ' + item.error);
  }
  console.log('');
  console.log('Online chain: ' + chainResults.filter(item => item.detail && item.toc && item.content).length + '/' +
    chainResults.length + ' reached content, target=' + onlineChainTarget);
  for (const item of chainResults) {
    const stages = ['detail=' + yesNo(item.detail), 'toc=' + yesNo(item.toc), 'content=' + yesNo(item.content)].join(' ');
    console.log('  ' + stages + ' ' + item.source + (item.error ? ' :: ' + item.error : ''));
  }
}

function yesNo(value) {
  return value ? 'Y' : 'N';
}

function runCapabilitySmoke(modules) {
  const { AjaxRuleCompat, AnalyzeRule, RuleContext } = modules;
  const checks = [];
  const ctx = new RuleContext();
  ctx.put('source.bookSourceUrl', 'https://example.com');
  ctx.put('source.variable', 'origin');

  const sourceRule = new AnalyzeRule('{}', 'https://example.com', ctx);
  checks.push({
    name: 'source.getKey',
    pass: sourceRule.analyzeFirst("@js:source.getKey() + '/search'") === 'https://example.com/search'
  });
  checks.push({
    name: 'source variable read',
    pass: sourceRule.analyzeFirst('@js:source.getVariable()') === 'origin'
  });
  checks.push({
    name: 'source variable write',
    pass: sourceRule.analyzeFirst("<js>source.setVariable('next');result=source.getVariable();</js>") === 'next' &&
      ctx.get('source.variable') === 'next'
  });

  const imageRule = new AnalyzeRule('{"data":{"page":[{"image":"a.jpg"},{"image":"b.jpg"}]}}', '');
  const images = imageRule.analyzeFirst(
    "@js:java.getStringList('$.data.page[*].image').toArray().map(a=>'<img src=\"'+a+'\">').join(' ')"
  );
  checks.push({
    name: 'java.getStringList map',
    pass: images === '<img src="a.jpg"> <img src="b.jpg">'
  });

  const templateRule = new AnalyzeRule('{"bookId":"10","chapterId":"20"}', '');
  checks.push({
    name: 'single brace template',
    pass: templateRule.analyzeFirst('/book/{$.bookId}/{$.chapterId}') === '/book/10/20'
  });
  const ajaxPlan = AjaxRuleCompat.directResultPlan(
    "#resource@value@js:result=String(java.ajax(result)).replace(/callback.+?:'/g,'').replace(/'\\}\\)/g,'')"
  );
  checks.push({
    name: 'direct java.ajax plan',
    pass: ajaxPlan?.urlRule === '#resource@value' &&
      AjaxRuleCompat.applyReplaceChain("callback_1:'正文'})", ajaxPlan?.jsCode || '') === '正文'
  });
  const htmlRule = new AnalyzeRule(
    '<ul id="chapterlist"><li><a href="/c1">第一章</a></li><li><a href="/c2">第二章</a></li></ul>' +
    '<div id="WuXian"><p>正文内容测试文本</p></div>',
    'http://example.com'
  );
  const chapterItems = htmlRule.getElements('#chapterlist@li@a');
  checks.push({
    name: 'legacy css selector chain',
    pass: chapterItems.length === 2 && chapterItems[0].includes('/c1'),
    actual: 'count=' + chapterItems.length + ' first=' + compact(chapterItems[0] || '', 100)
  });
  checks.push({
    name: 'legacy css html',
    pass: htmlRule.analyzeFirst('#WuXian@html').includes('正文内容测试文本')
  });
  return checks;
}

const modules = await loadModules();
const sourceList = (await loadSourceList()).map(normalizeSource);
const capabilityChecks = runCapabilitySmoke(modules);
const syntaxStats = {};
const offlineItems = [];
let offlineSourceCount = 0;
const originalWarn = console.warn;
console.warn = () => {};

for (const source of sourceList) {
  const buckets = collectRuleStrings(source);
  for (const text of Object.values(buckets).flat()) addStats(syntaxStats, text);
  const failures = offlineSmoke(source, modules.AnalyzeRule);
  if (failures.length > 0) {
    offlineSourceCount += 1;
    offlineItems.push(...failures);
  }
}

const onlineResults = [];
const onlineFailures = [];
const chainResults = [];
const candidates = sourceList.filter(source => isOnlineCandidate(source) && matchesSourceFilter(source))
  .sort((a, b) => sourceScore(b) - sourceScore(a));
let onlineAttempts = 0;
for (const source of candidates) {
  if (onlineResults.length >= onlineTarget) break;
  if (onlineAttempts >= onlineMaxAttempts) break;
  onlineAttempts += 1;
  try {
    const result = await runOnline(source, modules);
    onlineResults.push(result);
    if (chainResults.length < onlineChainTarget && canAttemptChain(source, result)) {
      chainResults.push({ source: result.source, ...(await runBookChain(source, result, modules)) });
    }
  } catch (error) {
    onlineFailures.push({ source: source.bookSourceName, error: compact(String(error && error.message || error), 180) });
  }
}

const offlineFailures = { sourceCount: offlineSourceCount, items: offlineItems };
console.warn = originalWarn;
console.log('Capability smoke: ' + capabilityChecks.filter(item => item.pass).length + '/' + capabilityChecks.length);
for (const item of capabilityChecks) {
  console.log('  ' + (item.pass ? 'PASS ' : 'FAIL ') + item.name + (!item.pass && item.actual ? ' :: ' + item.actual : ''));
}
console.log('');
printStats(sourceList, syntaxStats, offlineFailures, onlineResults, onlineFailures, onlineAttempts, chainResults);

if (capabilityChecks.some(item => !item.pass) || offlineItems.length > 0 ||
  onlineResults.length < Math.min(10, onlineTarget)) {
  process.exitCode = 1;
}
