import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import crypto from 'node:crypto';

const require = createRequire(import.meta.url);
const root = path.resolve(import.meta.dirname, '..');
const typescriptPaths = [
  'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js',
  'C:/Program Files/Huawei/DevEco Studio/plugins/codelinter/node_modules/typescript/lib/typescript.js'
];

const sourceUrl = process.env.BOOK_SOURCE_URL || 'https://www.yckceo.com/yuedu/shuyuans/json/id/1169.json';
const sourceFile = process.env.BOOK_SOURCE_FILE || '';
const sourceMirrorUrl =
  process.env.BOOK_SOURCE_MIRROR_URL ||
  'https://gcore.jsdelivr.net/gh/mumuceo/file01/202606/11780_e23645a35b55ac384f4fe66187b6148c.json';
const keyword = process.env.BOOK_SOURCE_KEYWORD || '斗破苍穹';
const onlineTarget = Number(process.env.BOOK_SOURCE_ONLINE_TARGET || '10');
const onlineChainTarget = Number(process.env.BOOK_SOURCE_CHAIN_TARGET || '10');
const timeoutMs = Number(process.env.BOOK_SOURCE_TIMEOUT_MS || '5000');
const chainTimeoutMs = Number(process.env.BOOK_SOURCE_CHAIN_TIMEOUT_MS || '10000');
const onlineMaxAttempts = Number(process.env.BOOK_SOURCE_ONLINE_ATTEMPTS || '80');
const sourceFilter = String(process.env.BOOK_SOURCE_FILTER || '').trim().toLowerCase();
const offlineSourceLimit = Number(process.env.BOOK_SOURCE_OFFLINE_LIMIT || '0');
const offlineSourceSkip = Number(process.env.BOOK_SOURCE_OFFLINE_SKIP || '0');
const offlineRuleLimit = Number(process.env.BOOK_SOURCE_OFFLINE_RULE_LIMIT || '0');

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
    'entry/src/main/ets/core/book/EncodedSourceUrl.ts',
    'entry/src/main/ets/core/rule/JsRuntime.ts',
    'entry/src/main/ets/core/rule/ScriptEngine.ts',
    'entry/src/main/ets/core/rule/JsonPathEvaluator.ts',
    'entry/src/main/ets/core/rule/AjaxRuleCompat.ts',
    'entry/src/main/ets/core/rule/AnalyzeRule.ts',
    'entry/src/main/ets/core/rule/AnalyzeUrl.ts'
  ];
  const sources = await Promise.all(files.map(file => fs.readFile(path.join(root, file), 'utf8')));
  const stubs = [
    "import crypto from 'node:crypto';",
    "class CompatTextEncoder {",
    "  constructor(label) { this.label = label || 'utf-8'; }",
    "  encodeInto(value) { return new Uint8Array(Buffer.from(String(value), 'utf8')); }",
    "  encode(value) { return new Uint8Array(Buffer.from(String(value), 'utf8')); }",
    "}",
    "const util = {",
    "  TextEncoder: CompatTextEncoder,",
    "  TextDecoder: { create: label => ({ decodeWithStream: data => new globalThis.TextDecoder(label || 'utf-8').decode(data) }) },",
    "  Base64Helper: class {",
    "    encodeToStringSync(v) { return Buffer.from(v).toString('base64'); }",
    "    decodeSync(v) { return new Uint8Array(Buffer.from(v, 'base64')); }",
    "  }",
    "};",
    "const cryptoFramework = {",
    "  CryptoMode: { ENCRYPT_MODE: 1, DECRYPT_MODE: 2 },",
    "  createMd(algorithm) {",
    "    const normalized = String(algorithm).replace('-', '').toLowerCase();",
    "    const hash = crypto.createHash(normalized);",
    "    return { updateSync(blob) { hash.update(Buffer.from(blob.data)); }, digestSync() { return { data: new Uint8Array(hash.digest()) }; } };",
    "  },",
    "  createSymKeyGenerator(_algorithm) {",
    "    return { convertKeySync(blob) { return { data: Buffer.from(blob.data) }; } };",
    "  },",
    "  createCipher(algorithm) {",
    "    function normalizeAlg(name, key) {",
    "      const upper = String(name).toUpperCase();",
    "      const mode = upper.includes('ECB') ? 'ecb' : 'cbc';",
    "      if (upper.startsWith('3DES')) return 'des-ede3-' + mode;",
    "      if (upper.startsWith('DES')) return 'des-' + mode;",
    "      if (upper.startsWith('AES256')) return 'aes-256-' + mode;",
    "      if (upper.startsWith('AES192')) return 'aes-192-' + mode;",
    "      return (key.length >= 32 ? 'aes-256-' : key.length >= 24 ? 'aes-192-' : 'aes-128-') + mode;",
    "    }",
    "    function usesPadding(name) { return !String(name).toUpperCase().includes('NOPADDING'); }",
    "    let encrypt = true;",
    "    let key = Buffer.alloc(0);",
    "    let iv = null;",
    "    return {",
    "      initSync(mode, symKey, params) {",
    "        encrypt = mode === cryptoFramework.CryptoMode.ENCRYPT_MODE;",
    "        key = Buffer.from(symKey.data);",
    "        iv = params && params.iv ? Buffer.from(params.iv.data) : null;",
    "      },",
    "      doFinalSync(blob) {",
    "        const alg = normalizeAlg(algorithm, key);",
    "        const cipher = encrypt ? crypto.createCipheriv(alg, key, alg.includes('ecb') ? null : iv) : crypto.createDecipheriv(alg, key, alg.includes('ecb') ? null : iv);",
    "        cipher.setAutoPadding(usesPadding(algorithm));",
    "        return { data: new Uint8Array(Buffer.concat([cipher.update(Buffer.from(blob.data)), cipher.final()])) };",
    "      }",
    "    };",
    "  }",
    "};",
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
  ].join('\n');
  const combined = [
    stubs,
    ...sources.map(stripImportsAndExports),
    'export { AjaxRuleCompat, AnalyzeRule, AnalyzeUrl, EncodedSourceUrl, JsonPathEvaluator, JsRuntime, RuleContext };'
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
  const normalize = value => Array.isArray(value) ? value : [value];
  if (sourceFile) {
    return normalize(JSON.parse(await fs.readFile(sourceFile, 'utf8')));
  }
  try {
    return normalize(JSON.parse(await fetchText(sourceUrl)));
  } catch (_) {
    return normalize(JSON.parse(await fetchText(sourceMirrorUrl)));
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
  let candidates = [];
  for (const bucketName of ['ruleSearch', 'ruleBookInfo', 'ruleToc', 'ruleContent']) {
    for (const text of buckets[bucketName]) {
      candidates.push({ bucketName, text });
    }
  }
  if (offlineRuleLimit > 0) {
    candidates = candidates
      .sort((a, b) => offlineRuleScore(b.text) - offlineRuleScore(a.text))
      .slice(0, offlineRuleLimit);
  }
  for (const candidate of candidates) {
    const bucketName = candidate.bucketName;
    const text = candidate.text;
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
  return failures;
}

function offlineRuleScore(value) {
  const text = String(value || '');
  let score = 0;
  if (/<js>|@js:|\{\{/.test(text)) score += 10;
  if (/java\./.test(text)) score += 8;
  if (/java\.ajax|java\.ajaxAll/.test(text)) score += 8;
  if (/md5|sha|HMac|AES|DES|crypto|requestKey|digest/i.test(text)) score += 6;
  if (/Cookie|cookie|java\.getCookie/.test(text)) score += 5;
  if (/data:|base64|decode|encodeURI|escape/i.test(text)) score += 4;
  if (/(^|[|&%>\n\r\s])(\$|@\.)[.\[]/.test(text)) score += 3;
  if (/##|@replace:|@match:/.test(text)) score += 2;
  if (/@XPath:|@xpath:|(^|[|&%>\n\r\s])\/{1,2}[A-Za-z*]/.test(text)) score += 2;
  return score;
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
  for (const item of items) {
    const parsed = parseSearchItem(source, item, items.length, searchRule, baseUrl, AnalyzeRule);
    if (parsed) return parsed;
  }
  throw new Error('no valid search item found');
}

function parseSearchItem(source, item, count, searchRule, baseUrl, AnalyzeRule) {
  const first = new AnalyzeRule(item, baseUrl);
  seedRule(first, keyword);
  const name = first.analyzeFirst(searchRule.name || '');
  const author = first.analyzeFirst(searchRule.author || '');
  let bookUrl = first.analyzeFirst(searchRule.bookUrl || '');
  if (!bookUrl || hasUnresolvedRule(bookUrl) || (/result/.test(searchRule.bookUrl || '') && /\+/.test(searchRule.bookUrl || ''))) {
    const repaired = repairResultConcatUrl(searchRule.bookUrl || '', item, baseUrl, AnalyzeRule);
    if (repaired) bookUrl = repaired;
  }
  if (!name || !bookUrl || hasUnresolvedRule(name) || hasUnresolvedRule(bookUrl) || !isRelevantSearchName(name)) {
    return null;
  }
  return {
    source: source.bookSourceName,
    count,
    name: compact(name, 80),
    author: compact(author, 80),
    bookUrl: compact(bookUrl, 120),
    bookUrlFull: bookUrl,
    searchBaseUrl: baseUrl
  };
}

function repairResultConcatUrl(rule, item, baseUrl, AnalyzeRule) {
  const jsIndex = String(rule || '').indexOf('@js:');
  if (jsIndex < 0) return '';
  const baseExpr = String(rule || '').substring(0, jsIndex).trim();
  const jsExpr = String(rule || '').substring(jsIndex + 4).trim();
  const baseRule = new AnalyzeRule(item, baseUrl);
  seedRule(baseRule, keyword);
  const baseValue = baseRule.analyzeFirst(baseExpr);
  if (!baseValue) return '';
  const prefixMatch = jsExpr.match(/^["']([\s\S]*?)["']\s*\+\s*result(?:\s*\+\s*["']([\s\S]*?)["'])?$/);
  const suffixMatch = jsExpr.match(/^result\s*\+\s*["']([\s\S]*?)["']$/);
  const headMatch = jsExpr.match(/^["']([\s\S]*?)["']\s*\+\s*result$/);
  if (prefixMatch) return prefixMatch[1] + baseValue + (prefixMatch[2] || '');
  if (suffixMatch) return baseValue + suffixMatch[1];
  if (headMatch) return headMatch[1] + baseValue;
  return '';
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
  const offlineTested = offlineFailures.testedCount || sourceList.length;
  console.log('Offline smoke: ' + (offlineTested - offlineFailures.sourceCount) + '/' + offlineTested +
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
  const { AjaxRuleCompat, AnalyzeRule, AnalyzeUrl, EncodedSourceUrl, RuleContext } = modules;
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
  checks.push({
    name: 'source named variable bridge',
    pass: sourceRule.analyzeFirst("<js>source.setVariable('token','abc');source.getVariable('token');</js>") === 'abc' &&
      ctx.get('source.variable.token') === 'abc'
  });
  checks.push({
    name: 'cache memory bridge',
    pass: sourceRule.analyzeFirst("<js>cache.putMemory('aid','42');cache.getFromMemory('aid');</js>") === '42' &&
      ctx.get('cache.aid') === '42'
  });
  const scriptEngineRule = new AnalyzeRule('{"name":"斗破苍穹","id":7}', 'https://example.com', ctx);
  checks.push({
    name: 'ScriptEngine JSON.parse chain',
    pass: scriptEngineRule.analyzeFirst("<js>var data=JSON.parse(result); data.name + '-' + data.id;</js>") === '斗破苍穹-7'
  });
  checks.push({
    name: 'ScriptEngine function and branch',
    pass: scriptEngineRule.analyzeFirst("<js>function pick(v){ if(v.length>2){ return v.substring(0,2); } return v; } pick('斗破苍穹');</js>") === '斗破'
  });
  checks.push({
    name: 'ScriptEngine replace match chain',
    pass: new AnalyzeRule('abc123', 'https://example.com', ctx)
      .analyzeFirst("text@js:result.replace(/\\d+/g,'').toUpperCase()") === 'ABC'
  });
  const tripleDesRule = new AnalyzeRule('', '');
  const tripleDesPlain = '兼容3DES';
  const tripleDesExpr = `java.desEncodeToBase64String('${tripleDesPlain}','OW84U8Eerdb99rtsTXWSILDO','DESede/CBC/PKCS5Padding','SK8bncVu')`;
  const tripleDesCipher = tripleDesRule.analyzeFirst('@js:' + tripleDesExpr);
  checks.push({
    name: 'DESede compat crypto',
    pass: tripleDesCipher.length > 0 &&
      tripleDesRule.analyzeFirst(`@js:java.desBase64DecodeToString('${tripleDesCipher}','OW84U8Eerdb99rtsTXWSILDO','DESede/CBC/PKCS5Padding','SK8bncVu')`) === tripleDesPlain
  });
  const javaImporterCtx = new RuleContext();
  javaImporterCtx.put('source.bookSourceComment', `
var javaImport = new JavaImporter();
javaImport.importPackage(Packages.java.lang, Packages.javax.crypto.spec, Packages.javax.crypto, Packages.android.util);
with(javaImport){
  function decode(str){
    var key = SecretKeySpec(String("OW84U8Eerdb99rtsTXWSILDO").getBytes(),"DESede");
    var iv = IvParameterSpec(String("SK8bncVu").getBytes());
    var bytes = Base64.decode(String(str).getBytes(),2);
    var chipher = Cipher.getInstance("DESede/CBC/PKCS5Padding");
    chipher.init(2,key,iv);
    return String(chipher.doFinal(bytes));
  }
}`);
  const javaImporterRule = new AnalyzeRule(tripleDesCipher, '', javaImporterCtx);
  checks.push({
    name: 'JavaImporter Cipher decode bridge',
    pass: javaImporterRule.analyzeFirst('text@js:decode(result)') === tripleDesPlain
  });

  const imageRule = new AnalyzeRule('{"data":{"page":[{"image":"a.jpg"},{"image":"b.jpg"}]}}', '');
  const jsonBridgeRule = new AnalyzeRule(
    '{"data":{"book":{"name":"斗破苍穹"},"page":[{"image":"a.jpg"},{"image":"b.jpg"}]}}',
    ''
  );
  checks.push({
    name: 'JsRuntime java.getString bridge',
    pass: jsonBridgeRule.analyzeFirst("@js:java.getString('$.data.book.name') + '-ok'") === '斗破苍穹-ok'
  });
  checks.push({
    name: 'JsRuntime java.getStringList join',
    pass: jsonBridgeRule.analyzeFirst("@js:java.getStringList('$.data.page[*].image').join('|')") === 'a.jpg|b.jpg'
  });
  checks.push({
    name: 'JsRuntime loose jsonPath',
    pass: jsonBridgeRule.analyzeFirst("@js:java.getStringList('$.data.page[*]image').join('|')") === 'a.jpg|b.jpg'
  });
  const images = imageRule.analyzeFirst(
    "@js:java.getStringList('$.data.page[*].image').toArray().map(a=>'<img src=\"'+a+'\">').join(' ')"
  );
  checks.push({
    name: 'java.getStringList map',
    pass: images === '<img src="a.jpg"> <img src="b.jpg">'
  });
  const htmlGetStringRule = new AnalyzeRule(
    '<div><img data-original="a.jpg"><img data-original="b.jpg"></div>',
    ''
  );
  checks.push({
    name: 'java.getString html selector',
    pass: htmlGetStringRule.analyzeFirst("@js:java.getString('img@data-original')") === 'a.jpg\nb.jpg'
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
    pass: ajaxPlan?.urlRule === '#resource@value' && ajaxPlan?.ajaxAll === false &&
      AjaxRuleCompat.applyReplaceChain("callback_1:'正文'})", ajaxPlan?.jsCode || '') === '正文'
  });
  const ajaxAllPlan = AjaxRuleCompat.directResultPlan("#next@href@js:String(java.ajaxAll(result)).match(/content:'([^']+)'/)[1]");
  checks.push({
    name: 'direct java.ajaxAll match plan',
    pass: ajaxAllPlan?.urlRule === '#next@href' && ajaxAllPlan?.ajaxAll === true &&
      AjaxRuleCompat.applyReplaceChain("content:'下一页正文'", ajaxAllPlan?.jsCode || '') === '下一页正文'
  });
  const ajaxJsonPlan = AjaxRuleCompat.directResultPlan("$.api@js:JSON.parse(java.ajax(result)).data.content");
  checks.push({
    name: 'direct java.ajax JSON.parse plan',
    pass: ajaxJsonPlan?.urlRule === '$.api' &&
      AjaxRuleCompat.applyReplaceChain('{"data":{"content":"接口正文"}}', ajaxJsonPlan?.jsCode || '') === '接口正文'
  });
  const analyzeUrlSource = {
    bookSourceUrl: 'https://example.com/base/path.html',
    header: "{User-Agent:'UA',Cookie:'sid=1'}"
  };
  const analyzeUrl = new AnalyzeUrl(analyzeUrlSource, { execute: async request => ({ url: request.url, statusCode: 200, headers: {}, body: '', success: true }) });
  const analyzeConfig = analyzeUrl.parse("/api/search,{method:'POST',body:'a=1&b=2',headers:{X-Test:'1','X-Flag':'2'},charset:'gbk'}");
  const analyzeRequest = analyzeUrl.buildRequest();
  checks.push({
    name: 'AnalyzeUrl loose object parse',
    pass: analyzeConfig.url === 'https://example.com/api/search' &&
      analyzeConfig.method === 'POST' &&
      analyzeConfig.charset === 'gbk' &&
      analyzeConfig.headers['X-Test'] === '1' &&
      analyzeConfig.headers['X-Flag'] === '2' &&
      analyzeRequest.headers['User-Agent'] === 'UA' &&
      analyzeRequest.headers['Cookie'] === 'sid=1' &&
      analyzeRequest.headers['Content-Type'] === 'application/x-www-form-urlencoded'
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
  const shushanDetail = Buffer.from(JSON.stringify({
    source: '番茄小说',
    url: Buffer.from('https://example.com/detail?book_id=1234567890123456789').toString('base64'),
    name: '书山样例'
  })).toString('base64');
  const shushanCatalog = Buffer.from(JSON.stringify({
    source: '番茄小说',
    url: 'https://example.com/detail?book_id=1234567890123456789',
    name: '书山样例',
    tab: 'novel'
  })).toString('base64');
  const shushanContent = Buffer.from(
    'chapter?cid=100&source=番茄小说&device=android&book_id=1234567890123456789&item_id=100'
  ).toString('base64');
  const detailUrl = `data:detailsUrl;base64,${shushanDetail},{"type":"shushan"}`;
  const catalogUrl = `data:catalogUrl;base64,${shushanCatalog},{"type":"shushan"}`;
  const contentUrl = `data:contentUrl;base64,${shushanContent},{"type":"qingci"}`;
  const detailPayload = EncodedSourceUrl.decode(detailUrl);
  const catalogPayload = EncodedSourceUrl.decode(catalogUrl);
  const contentPayload = EncodedSourceUrl.decode(contentUrl);
  checks.push({
    name: 'shushan detailsUrl decode',
    pass: detailPayload?.type === 'shushanDetail' &&
      detailPayload.data?.source === '番茄小说' &&
      detailPayload.data?.name === '书山样例' &&
      EncodedSourceUrl.canHandle(detailUrl)
  });
  checks.push({
    name: 'shushan catalogUrl decode',
    pass: catalogPayload?.type === 'shushanCatalog' &&
      catalogPayload.data?.tab === 'novel' &&
      EncodedSourceUrl.canHandle(catalogUrl)
  });
  checks.push({
    name: 'shushan contentUrl decode',
    pass: contentPayload?.type === 'shushanContent' &&
      contentPayload.data?.cid === '100' &&
      contentPayload.data?.item_id === '100' &&
      EncodedSourceUrl.canHandle(contentUrl)
  });
  return checks;
}

const modules = await loadModules();
const sourceList = (await loadSourceList()).map(normalizeSource);
const capabilityChecks = runCapabilitySmoke(modules);
const syntaxStats = {};
const offlineItems = [];
let offlineSourceCount = 0;
let offlineTestedCount = 0;
const originalWarn = console.warn;
console.warn = () => {};

for (let sourceIndex = 0; sourceIndex < sourceList.length; sourceIndex++) {
  const source = sourceList[sourceIndex];
  const buckets = collectRuleStrings(source);
  for (const text of Object.values(buckets).flat()) addStats(syntaxStats, text);
  if (sourceIndex < offlineSourceSkip) {
    continue;
  }
  if (offlineSourceLimit > 0 && sourceIndex >= offlineSourceSkip + offlineSourceLimit) {
    continue;
  }
  offlineTestedCount += 1;
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

const offlineFailures = { sourceCount: offlineSourceCount, items: offlineItems, testedCount: offlineTestedCount };
console.warn = originalWarn;
console.log('Capability smoke: ' + capabilityChecks.filter(item => item.pass).length + '/' + capabilityChecks.length);
for (const item of capabilityChecks) {
  console.log('  ' + (item.pass ? 'PASS ' : 'FAIL ') + item.name + (!item.pass && item.actual ? ' :: ' + item.actual : ''));
}
console.log('');
printStats(sourceList, syntaxStats, offlineFailures, onlineResults, onlineFailures, onlineAttempts, chainResults);

const requireOnlineResults = onlineTarget > 0 && onlineMaxAttempts > 0;
if (capabilityChecks.some(item => !item.pass) || offlineItems.length > 0 ||
  (requireOnlineResults && onlineResults.length < Math.min(10, onlineTarget))) {
  process.exitCode = 1;
}
