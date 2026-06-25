import { JsRuntime } from './JsRuntime';
import { RuleContext } from './RuleContext';
import { VerificationSupport } from '../http/VerificationSupport';
import { EncodedJsonMap, EncodedSourceUrl } from '../book/EncodedSourceUrl';
import { JsonPathEvaluator } from './JsonPathEvaluator';

export class AnalyzeRule {
  private content: string = '';
  private baseUrl: string = '';
  private ctx: RuleContext;
  private js: JsRuntime;

  constructor(content: string = '', baseUrl: string = '', ctx?: RuleContext) {
    this.content = content;
    this.baseUrl = baseUrl;
    this.ctx = ctx || new RuleContext();
    this.js = new JsRuntime();
  }

  setContent(c: string): AnalyzeRule { this.content = c; return this; }
  setBaseUrl(u: string): AnalyzeRule { this.baseUrl = u; return this; }
  setContext(ctx: RuleContext): AnalyzeRule { this.ctx = ctx; return this; }
  getContext(): RuleContext { return this.ctx; }
  setJsVar(k: string, v: string): AnalyzeRule { this.js.setVar(k, v); return this; }

  // === 主入口 ===

  getString(rule: string, isUrl: boolean = false): string {
    const r = this.analyzeFirst(rule);
    return isUrl ? this.resolveUrl(r) : r;
  }

  getStringList(rule: string): string[] {
    return this.analyze(rule);
  }

  getElements(rule: string): string[] {
    if (!rule) return [this.content];
    // 防止超大 HTML 进入正则/CSS 解析，但 JSON 接口列表仍需要正常走 JSONPath。
    if (this.content.length > 500000 && !this.isJsonPathLikeRule(rule)) return [];
    const items = this.analyze(rule);
    return items.length > 0 ? items : [this.content];
  }

  private isJsonPathLikeRule(rule: string): boolean {
    const effective = this.stripProcessor((rule || '').trim());
    return effective.startsWith('$') || effective.startsWith('@.') || effective.startsWith('@json:');
  }

  // === 核心解析 ===

  analyze(rule: string): string[] {
    if (!rule) return [];
    rule = this.applyJsBlocks(rule);
    const effective = this.stripProcessor(rule);
    if (!effective) return [];

    if (effective.startsWith('@json:')) {
      return this.jsonPathToStrings(effective.substring(6).trim());
    }

    const orParts = this.splitCombinedRule(effective, '||');
    if (orParts.length > 1) {
      const parts = orParts;
      for (const part of parts) {
        const values = this.analyze(part);
        if (values.length > 0) return values;
      }
      return [];
    }

    const andParts = this.splitCombinedRule(effective, '&&');
    if (andParts.length > 1) {
      const values: string[] = [];
      for (const part of andParts) {
        values.push(...this.analyze(part));
      }
      return values;
    }

    const interleaveParts = this.splitCombinedRule(effective, '%%');
    if (interleaveParts.length > 1) {
      const groups = interleaveParts.map(part => this.analyze(part));
      const values: string[] = [];
      const length = groups.length > 0 ? groups[0].length : 0;
      for (let i = 0; i < length; i++) {
        for (const group of groups) if (i < group.length) values.push(group[i]);
      }
      return values;
    }

    // 模板规则优先处理，避免 /book/{{$.id}} 或 /book/{$.id} 被误当 CSS
    if (effective.includes('{{') || /(^|[^{])\{(\$[.\[]|@\.)/.test(effective)) {
      return [this.evalTemplateRule(effective)];
    }

    if (/^\$\d+$/.test(effective)) {
      const jsonV = this.evalJsonPath(effective);
      if (jsonV !== undefined && jsonV !== null) return [this.jsonValueToString(jsonV)];
    }

    if (this.isJsonContent() && effective.startsWith('.') && !effective.startsWith('..')) {
      const jsonV = this.evalJsonPath('$' + effective);
      if (Array.isArray(jsonV)) return this.jsonPathArrayToStrings(jsonV as Object[]);
      if (jsonV !== undefined && jsonV !== null) return [this.jsonValueToString(jsonV)];
    }

    const xpathV = this.evalXPathBasic(effective);
    if (xpathV.length > 0) return xpathV;

    const legacyV = this.evalLegacyRule(effective);
    if (legacyV.length > 0) return legacyV;

    // JSONPath
    const jsonV = this.evalJsonPath(effective);
    if (Array.isArray(jsonV)) return this.jsonPathArrayToStrings(jsonV as Object[]);
    if (jsonV !== undefined && jsonV !== null) return [this.jsonValueToString(jsonV)];

    // CSS 选择器
    const cssV = this.evalCss(effective);
    if (cssV.length > 0) return cssV;

    // Regex
    if (effective.startsWith('%')) {
      try {
        const m = this.content.match(new RegExp(effective.substring(1)));
        return m ? Array.from(m).map(value => value || '') : [];
      } catch (_) {
        return [];
      }
    }

    const regexV = this.evalRegexRule(effective);
    if (regexV.length > 0) return regexV;

    // 纯文本/html
    if (effective === 'text') return [this.stripHtml(this.content)];
    if (effective === 'html') return [this.content];

    // 默认 CSS
    return this.evalCss(effective);
  }

  analyzeFirst(rule: string): string {
    if (!rule) return '';
    const originalRule = rule;
    const pureJs = rule.match(/^\s*<js>([\s\S]*?)<\/js>\s*$/i);
    if (pureJs) {
      return this.evalJsBlockSideEffects(pureJs[1]) || this.evalResultJs(pureJs[1], this.content);
    }
    const embeddedJs = rule.match(/^([\s\S]+?)<js>([\s\S]*?)<\/js>([\s\S]*)$/i);
    if (embeddedJs && embeddedJs[1].trim()) {
      const baseValue = this.analyzeFirst(embeddedJs[1].trim());
      const jsValue = this.evalResultJs(embeddedJs[2], baseValue);
      return this.applyProcessor(jsValue, embeddedJs[3] || '');
    }
    rule = this.applyJsBlocks(rule);

    // 处理 @put:{key:value} - 存储变量，value 按普通规则执行后写入上下文
    const putBlock = this.extractPutBlock(rule);
    if (putBlock) {
      this.applyPutBlock(putBlock.body);
      rule = (rule.substring(0, putBlock.start) + rule.substring(putBlock.end)).trim();
      if (!rule) return '';
    }

    const directGet = this.evalDirectGetRule(rule);
    if (directGet !== null) return directGet;

    // 处理 @get:{key} 替换
    rule = rule.replace(/@get:\{([^}]+)\}/g, (_: string, key: string) => {
      return this.ctx.get(key.trim());
    });

    // 处理 @js: 前缀规则（JS 模板拼接，如 @js:'url'+$.nid+'/'+$.cid）
    if (rule.startsWith('@js:')) {
      return this.evalJsTemplate(rule.substring(4), this.content);
    }

    if (rule.startsWith('@json:')) {
      const values = this.jsonPathToStrings(rule.substring(6).trim());
      return values.length > 0 ? values[0] : '';
    }

    const literalEffective = this.stripProcessor(rule).trim();
    if (!literalEffective.includes('{{') && !/(^|[^{])\{(\$[.\[]|@\.)/.test(literalEffective) &&
      (/^(?:https?:|\/|data:)/.test(literalEffective) ||
      literalEffective === 'true' || literalEffective === 'false')) {
      return this.applyProcessor(literalEffective, rule);
    }

    const a = this.analyze(rule);
    return a.length > 0 ? this.applyProcessor(a[0], originalRule) : '';
  }

  private extractPutBlock(rule: string): { start: number, end: number, body: string } | null {
    const marker = '@put:{';
    const start = rule.indexOf(marker);
    if (start < 0) return null;
    const bodyStart = start + marker.length;
    let depth = 1;
    let quote = '';
    for (let i = bodyStart; i < rule.length; i++) {
      const ch = rule.charAt(i);
      if (quote) {
        if (ch === quote && rule.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === '{') depth++;
      if (ch === '}') {
        depth--;
        if (depth === 0) {
          return { start: start, end: i + 1, body: rule.substring(bodyStart, i) };
        }
      }
    }
    return null;
  }

  private applyPutBlock(body: string): void {
    const parts = this.splitTopLevel(body, [',', ';']);
    for (const part of parts) {
      const idx = this.indexOfTopLevel(part, ':');
      if (idx <= 0) continue;
      const key = this.stripQuotes(part.substring(0, idx).trim());
      let valueRule = part.substring(idx + 1).trim();
      valueRule = this.stripQuotes(valueRule);
      if (!key) continue;
      const value = this.evaluatePutValue(valueRule);
      this.ctx.put(key, value);
    }
  }

  private evaluatePutValue(valueRule: string): string {
    if (!valueRule) return '';
    if (valueRule.startsWith('@get:{')) {
      const value = this.evalDirectGetRule(valueRule);
      if (value !== null) return value;
    }
    const values = this.analyze(valueRule);
    if (values.length > 0) {
      const processed = values
        .map(value => this.applyProcessor(value, valueRule))
        .filter(value => value.length > 0);
      return processed.join('\n');
    }
    return valueRule;
  }

  private evalDirectGetRule(rule: string): string | null {
    const match = rule.match(/^@get:\{([^}]+)\}([\s\S]*)$/);
    if (!match) return null;
    let value = this.ctx.get(match[1].trim());
    const suffix = match[2] || '';
    if (!suffix) return value;
    const processors = suffix.split('@').map(part => part.trim()).filter(part => part.length > 0);
    for (const processor of processors) {
      if (processor === 'text' || processor === 'ownText' || processor === 'textNodes') {
        value = this.stripHtml(value);
      } else if (processor === 'html') {
        value = value;
      } else if (processor.startsWith('js:')) {
        value = this.evalResultJs(processor.substring(3), value);
      } else if (this.isAttrName(processor)) {
        value = this.extractAttr(value, processor);
      }
      if (!value) break;
    }
    return value;
  }

  private splitTopLevel(text: string, separators: string[]): string[] {
    const result: string[] = [];
    let depth = 0;
    let quote = '';
    let start = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && separators.includes(ch)) {
        const part = text.substring(start, i).trim();
        if (part) result.push(part);
        start = i + 1;
      }
    }
    const last = text.substring(start).trim();
    if (last) result.push(last);
    return result;
  }

  private indexOfTopLevel(text: string, target: string): number {
    return this.indexOfTopLevelFrom(text, target, 0);
  }

  private indexOfTopLevelFrom(text: string, target: string, from: number): number {
    let depth = 0;
    let quote = '';
    for (let i = from; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && ch === target) return i;
    }
    return -1;
  }

  private handlePrefixAes(aesArgs: string, sourceJson: string): string {
    // aesArgs 格式: String(result).substring(28), "key", "iv"
    // 或: result, "key", "iv"
    const args = this.splitArgs(aesArgs);
    if (args.length < 2) return '';
    // 数据：如果 arg0 包含 substring(N)，截取 sourceJson
    let data = sourceJson;
    const subMatch = args[0].match(/\.substring\s*\(\s*(\d+)\s*\)/);
    if (subMatch) {
      const offset = parseInt(subMatch[1]);
      data = sourceJson.substring(offset);
    }
    const key = this.stripQuotes(args[1]);
    const iv = args.length >= 4 ? this.stripQuotes(args[3]) : (args.length >= 3 ? this.stripQuotes(args[2]) : '');
    return this.js.aesBase64DecodeToString(data, key, iv);
  }

  private evalJsTemplate(expr: string, sourceJson: string): string {
    if (!expr) return '';
    expr = expr.trim();
    const javaStringValue = this.evalJavaGetStringExpression(expr, sourceJson);
    if (javaStringValue !== null) return javaStringValue;
    const javaStringListValue = this.evalJavaGetStringListExpression(expr);
    if (javaStringListValue !== null) return javaStringListValue;
    const encodedDataUrl = this.evalEncodedDataUrlJs(expr, sourceJson);
    if (encodedDataUrl) return encodedDataUrl;
    if (expr.includes('startBrowserAwait') || expr.includes('getVerificationCode')) {
      const verifyUrl = VerificationSupport.pickStartBrowserUrl(expr) || this.baseUrl;
      VerificationSupport.requestVerification(verifyUrl, '网页验证');
      if (VerificationSupport.isChallengeResponse(sourceJson)) return '';
    }
    const baseReplace = this.evalBaseUrlReplace(expr);
    if (baseReplace) return baseReplace;
    if (expr.includes('vipreader.qidian.com/chapter')) {
      let bid = '';
      const bidMatch = this.baseUrl.match(/\d+/);
      if (bidMatch) bid = bidMatch[0];
      let data: Record<string, Object> | null = null;
      try { data = JSON.parse(sourceJson) as Record<string, Object>; } catch (_) {}
      const cid = data ? String((data as Record<string, Object>)['$3'] || (data as Record<string, Object>)['id'] || '') : '';
      if (bid && cid) return `https://vipreader.qidian.com/chapter/${bid}/${cid}/`;
    }
    // 处理 java.aesBase64DecodeToString 调用（前缀形式，常用于内容解密）
    const aesIdx = expr.indexOf('java.aesBase64DecodeToString');
    if (aesIdx >= 0) {
      const parenStart = expr.indexOf('(', aesIdx);
      if (parenStart > 0) {
        const parenEnd = this.findMatchingParen(expr, parenStart);
        if (parenEnd > 0) {
          return this.handlePrefixAes(expr.substring(parenStart + 1, parenEnd), sourceJson);
        }
      }
    }
    const simpleValue = this.evalSimpleJsExpression(expr, { result: sourceJson });
    if (simpleValue !== null) return simpleValue;
    // 包含复杂JS语句（非简单拼接），直接返回空，避免产生垃圾输出
    if (/\b(if|var|let|const|return|function|eval|parseInt|match|String|JSON)\b/.test(expr)) {
      console.warn('[AnalyzeRule] 复杂 @js: 规则暂不支持:', expr.substring(0, 80));
      return '';
    }
    // 去除尾部配置对象 ,{webView:true}
    expr = expr.replace(/\s*,\s*\{[^}]*\}\s*$/, '');
    // 解析 sourceJson 用于 $.xxx 查找
    let data: Record<string, Object> | null = null;
    try { data = JSON.parse(sourceJson) as Record<string, Object>; } catch (_) {}

    // 第一步：替换 $..key（深层搜索）和 $.key（根层搜索）
    expr = expr.replace(/\$\.\.(\w+)/g, (_m: string, key: string) => {
      if (data) {
        const v = this.deepFind(data as Object, key);
        if (v !== undefined) return String(v);
      }
      return '';
    });
    expr = expr.replace(/\$\.(\w+)/g, (_m: string, key: string) => {
      if (data && (data as Record<string, Object>)[key] !== undefined) {
        return String((data as Record<string, Object>)[key]);
      }
      return '';
    });

    // 第二步：清理 + 号和引号及 {{}} 模板括号，保留有效字符
    return expr.replace(/\s*\+\s*/g, '').replace(/['"]/g, '').replace(/\{\{|\}\}/g, '').trim();
  }

  private evalJavaGetStringExpression(expr: string, sourceJson: string): string | null {
    const getStringMatch = expr.match(/(?:replaceCover\s*\(\s*)?java\.getString\(\s*["']([^"']+)["']\s*\)\s*\)?/);
    if (!getStringMatch) return null;
    const keyOrPath = getStringMatch[1];
    let data: Object | null = null;
    try { data = JSON.parse(sourceJson) as Object; } catch (_) {}
    if (!data) return '';
    let value: Object | string | undefined = undefined;
    if (keyOrPath.startsWith('$')) {
      value = this.getByPath(data, keyOrPath);
    } else {
      value = (data as Record<string, Object>)[keyOrPath] as Object | string;
      if (value === undefined) value = this.deepFind(data, keyOrPath);
    }
    if (Array.isArray(value)) return value.map(item => String(item)).join(',');
    return value === undefined || value === null ? '' : String(value);
  }

  private evalJavaGetStringListExpression(expr: string): string | null {
    const listMatch = expr.match(/java\.getStringList\(\s*(['"])([\s\S]*?)\1\s*\)/);
    if (!listMatch) return null;
    const values = this.analyze(listMatch[2]);
    const mapMatch = expr.match(/\.map\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*=>\s*([\s\S]+?)\)\s*\.join\s*\(\s*([\s\S]*?)\s*\)/);
    if (!mapMatch) {
      const joinMatch = expr.match(/\.join\s*\(\s*(['"])([\s\S]*?)\1\s*\)/);
      return values.join(joinMatch ? joinMatch[2] : ',');
    }
    const mapped: string[] = [];
    for (const value of values) {
      const item = this.evalSimpleJsExpression(mapMatch[2], { [mapMatch[1]]: value });
      mapped.push(item === null ? value : item);
    }
    return mapped.join(this.stripQuotes(mapMatch[3]));
  }

  private evalEncodedDataUrlJs(expr: string, sourceJson: string): string {
    const typeMatch = expr.match(/type\s*:\s*["']([^"']+)["']|["']type["']\s*:\s*["']([^"']+)["']/);
    if (!typeMatch || !expr.includes('data:;base64')) return '';
    const type = typeMatch[1] || typeMatch[2] || '';
    if (type === 'mybxs' || type === 'mybxc') {
      const raw = this.evalRawEncodedValue(expr, sourceJson);
      const host = this.ctx.get('host') || this.ctx.get('backend') || this.js.getVar('host') || this.js.getVar('backend');
      return raw ? EncodedSourceUrl.encodeRaw(raw, type, host) : '';
    }
    const data = EncodedSourceUrl.asMap(this.parseContentObject());
    const resultData = this.parseJsonSafe(sourceJson);
    const output: EncodedJsonMap = {};

    if (type === 'gysearch') {
      output['key'] = this.ctx.get('key') || this.js.getVar('key');
      output['tab'] = this.extractLiteralAssignment(expr, 'tab') || '小说';
      output['sourcesKey'] = this.extractLiteralAssignment(expr, 'sourcesKey') || '全部';
      output['page'] = this.ctx.get('page') || this.js.getVar('page') || '1';
      output['disabled_sources'] = this.extractLiteralAssignment(expr, 'disabled_sources') || '0';
      return EncodedSourceUrl.encode(output, type);
    }

    const record = Object.keys(data).length > 0 ? data : resultData;
    const bookId = this.pickValue(record, ['book_id', 'bookId']);
    const source = this.pickValue(record, ['source', 'sources']);
    const tab = this.pickValue(record, ['tab']) || '小说';
    const tocUrl = this.pickValue(record, ['toc_url', 'tocUrl', 'url']);
    if (bookId) output['book_id'] = bookId;
    if (!output['book_id'] && this.ctx.get('book_id')) output['book_id'] = this.ctx.get('book_id');
    if (source) {
      output['source'] = source;
      output['sources'] = source;
    }
    output['tab'] = tab;
    if (tocUrl) {
      output['url'] = tocUrl;
      output['toc_url'] = tocUrl;
    }

    if (type === 'gycontent' || type === 'qingtian3') {
      const itemId = this.pickValue(record, ['item_id', 'itemId']);
      const title = this.pickValue(record, ['title']);
      if (itemId) output['item_id'] = itemId;
      if (title) output['title'] = title;
      const ctxBookId = this.ctx.get('book_id');
      if (!output['book_id'] && ctxBookId) output['book_id'] = ctxBookId;
    } else if (type === 'gycatalog' || type === 'qingtian2') {
      output['book_name'] = this.pickValue(record, ['book_name']);
      output['author'] = this.pickValue(record, ['author']);
      output['abstract'] = this.pickValue(record, ['abstract']);
      output['thumb_url'] = this.pickValue(record, ['thumb_url']);
    }
    return EncodedSourceUrl.encode(output, type);
  }

  private evalRawEncodedValue(expr: string, sourceJson: string): string {
    const vars: Record<string, string> = { result: sourceJson };
    const matchAssignRe = /\b(?:var|let|const)?\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*result\.match\((\/[\s\S]*?\/[gimsuy]*)\)\s*\[\s*(\d+)\s*\]\s*;?/g;
    let matchAssign: RegExpExecArray | null;
    while ((matchAssign = matchAssignRe.exec(expr)) !== null) {
      const re = this.parseJsRegex(matchAssign[2]);
      const idx = parseInt(matchAssign[3]);
      if (re) {
        const matched = sourceJson.match(re);
        vars[matchAssign[1]] = matched && matched[idx] !== undefined ? matched[idx] : '';
      }
    }
    const directMatch = expr.match(/java\.base64Encode\(\s*([A-Za-z_][A-Za-z0-9_]*|result)\s*\)/);
    if (directMatch) return vars[directMatch[1]] || '';
    return sourceJson;
  }

  private jsonPathToStrings(rule: string): string[] {
    if (!rule) return [];
    const jsonV = this.evalJsonPath(rule);
    if (Array.isArray(jsonV)) {
      return this.jsonPathArrayToStrings(jsonV as Object[]);
    }
    if (jsonV !== undefined && jsonV !== null) {
      return [typeof jsonV === 'string' ? jsonV as string : JSON.stringify(jsonV)];
    }
    return [];
  }

  private jsonPathArrayToStrings(values: Object[]): string[] {
    const result: string[] = [];
    for (const value of values) {
      if (Array.isArray(value)) {
        result.push(...this.jsonPathArrayToStrings(value as Object[]));
      } else {
        result.push(typeof value === 'string' ? value as string : JSON.stringify(value));
      }
    }
    return result;
  }

  private jsonValueToString(value: Object | string | undefined): string {
    if (value === undefined || value === null) return '';
    return typeof value === 'string' ? value as string : JSON.stringify(value);
  }

  private parseJsonSafe(text: string): EncodedJsonMap {
    try {
      return EncodedSourceUrl.asMap(JSON.parse(text || '{}') as Object);
    } catch (_) {
      return {};
    }
  }

  private pickValue(data: EncodedJsonMap, keys: string[]): string {
    for (const key of keys) {
      const value = data[key];
      if (value !== undefined && value !== null) return String(value);
    }
    return '';
  }

  private extractLiteralAssignment(expr: string, name: string): string {
    const re = new RegExp(`\\b${name}\\s*=\\s*["']([^"']+)["']`);
    const m = expr.match(re);
    return m ? m[1] : '';
  }

  private evalBaseUrlReplace(expr: string): string {
    if (!expr.includes('baseUrl')) return '';
    let value = this.baseUrl;
    const replaceRe = /\.replace\s*\(\s*(['"])(.*?)\1\s*,\s*(['"])(.*?)\3\s*\)/g;
    let matched = false;
    let m: RegExpExecArray | null;
    while ((m = replaceRe.exec(expr)) !== null) {
      matched = true;
      value = value.split(m[2]).join(m[4]);
    }
    if (matched) return value;

    const concatMatch = expr.match(/baseUrl\s*\+\s*(['"])(.*?)\1/);
    if (concatMatch) return value + concatMatch[2];
    return '';
  }

  // === JSONPath ===

  private evalJsonPath(rule: string): Object | string | undefined {
    const isBareKey = /^[A-Za-z_][A-Za-z0-9_]*$/.test(rule);
    if (!rule.startsWith('$') && !rule.startsWith('@.') && !isBareKey) return undefined;
    try {
      const data = JSON.parse(this.content) as Object;
      if (/^\$\d+$/.test(rule)) return (data as Record<string, Object>)[rule] as Object | string;
      if (isBareKey) return (data as Record<string, Object>)[rule] as Object | string;
      const values = JsonPathEvaluator.evaluate(data, rule.startsWith('@.') ? '$.' + rule.substring(2) : rule);
      if (values.length === 0) return undefined;
      return values.length === 1 ? values[0] as Object | string : values as Object[];
    } catch (_) {
      return undefined;
    }
  }

  private getByPath(obj: Object, path: string): Object | string | undefined {
    if (!obj || !path) return undefined;
    path = path.trim();
    const normalized = path.startsWith('$') || path.startsWith('@') ? path : '$.' + path;
    const evaluated = JsonPathEvaluator.evaluate(obj, normalized);
    if (evaluated.length > 0) return evaluated.length === 1 ? evaluated[0] as Object | string : evaluated as Object[];

    // $..list[*] → 递归搜索
    if (path.startsWith('$..')) {
      const selector = path.substring(3);
      const values = this.evalDeepSelector(obj, selector);
      if (values.length === 0) return undefined;
      return values.length === 1 ? values[0] as Object | string : values as Object[];
    }

    // $.data[*] → 按层级
    const parts = path.replace(/^\$\./, '').replace(/\$/, '').split('.');
    let cur: Object = obj;
    for (const p of parts) {
      if (p === '[*]' || p === '*') {
        if (Array.isArray(cur)) return cur as Object[];
        return undefined;
      }
      if (p.includes('..')) {
        const segs = p.split('..');
        const first = segs[0];
        if (first) {
          cur = (cur as Record<string, Object>)[first] as Record<string, Object>;
        }
        return this.deepFindBySelector(cur, segs.slice(1).join('..'));
      }
      const bIdx = p.indexOf('[');
      if (bIdx > 0) {
        const key = p.substring(0, bIdx);
        cur = (cur as Record<string, Object>)[key] as Record<string, Object>;
        const idxText = p.substring(bIdx + 1, p.indexOf(']'));
        if (idxText === '*') return cur;
        const idx = parseInt(idxText);
        if (Array.isArray(cur)) cur = cur[idx] as Record<string, Object>;
      } else {
        cur = (cur as Record<string, Object>)[p] as Record<string, Object>;
      }
      if (cur === undefined || cur === null) return undefined;
    }
    return cur;
  }

  private isJsonContent(): boolean {
    const value = (this.content || '').trim();
    return (value.startsWith('{') && value.endsWith('}')) || (value.startsWith('[') && value.endsWith(']'));
  }

  private splitCombinedRule(rule: string, delimiter: string): string[] {
    const parts: string[] = [];
    let start = 0;
    let quote = '';
    let square = 0;
    let round = 0;
    let brace = 0;
    for (let i = 0; i <= rule.length - delimiter.length; i++) {
      const ch = rule.charAt(i);
      if (quote) {
        if (ch === quote && rule.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '[') square++;
      if (ch === ']') square--;
      if (ch === '(') round++;
      if (ch === ')') round--;
      if (ch === '{') brace++;
      if (ch === '}') brace--;
      if (square === 0 && round === 0 && brace === 0 && rule.substring(i, i + delimiter.length) === delimiter) {
        parts.push(rule.substring(start, i).trim());
        start = i + delimiter.length;
        i += delimiter.length - 1;
      }
    }
    parts.push(rule.substring(start).trim());
    return parts.filter(part => part.length > 0);
  }

  private deepFindBySelector(obj: Object, selector: string): Object | string | undefined {
    const clean = selector.replace(/\[\*\]$/, '');
    const idxMatch = clean.match(/^([A-Za-z_][A-Za-z0-9_-]*)\[(\d+)\]$/);
    const key = idxMatch ? idxMatch[1] : clean;
    const found = this.deepFind(obj, key);
    if (idxMatch && Array.isArray(found)) {
      const idx = parseInt(idxMatch[2]);
      return found[idx] as Object | string;
    }
    return found;
  }

  private evalDeepSelector(obj: Object, selector: string): Object[] {
    const parts = selector.split('.').map(part => part.trim()).filter(part => part.length > 0);
    if (parts.length === 0) return [];

    let current = this.findAllByToken(obj, parts[0], true);
    for (let i = 1; i < parts.length; i++) {
      const next: Object[] = [];
      for (const item of current) {
        next.push(...this.findAllByToken(item as Object, parts[i], false));
      }
      current = next;
      if (current.length === 0) break;
    }
    return current;
  }

  private findAllByToken(obj: Object, token: string, deep: boolean): Object[] {
    const parsed = this.parsePathToken(token);
    const values = deep ? this.deepFindAll(obj, parsed.key) : this.directFindAll(obj, parsed.key);
    return this.applyTokenIndex(values, parsed.index);
  }

  private parsePathToken(token: string): { key: string, index: string } {
    const match = token.match(/^([A-Za-z_][A-Za-z0-9_-]*)(?:\[(\*|\d+)\])?$/);
    if (!match) return { key: token.replace(/\[\*\]$/, ''), index: '' };
    return { key: match[1], index: match[2] || '' };
  }

  private directFindAll(obj: Object, key: string): Object[] {
    if (!obj || typeof obj !== 'object') return [];
    if (Array.isArray(obj)) {
      const values: Object[] = [];
      for (const item of obj) {
        if (item && typeof item === 'object' && (item as Record<string, Object>)[key] !== undefined) {
          values.push((item as Record<string, Object>)[key]);
        }
      }
      return values;
    }
    const value = (obj as Record<string, Object>)[key];
    return value === undefined || value === null ? [] : [value];
  }

  private deepFindAll(obj: Object, key: string): Object[] {
    const values: Object[] = [];
    if (Array.isArray(obj)) {
      for (const item of obj) {
        values.push(...this.deepFindAll(item as Object, key));
      }
    } else if (typeof obj === 'object' && obj !== null) {
      const rec = obj as Record<string, Object>;
      if (rec[key] !== undefined && rec[key] !== null) values.push(rec[key]);
      for (const k in rec) {
        values.push(...this.deepFindAll(rec[k] as Object, key));
      }
    }
    return values;
  }

  private applyTokenIndex(values: Object[], index: string): Object[] {
    const flattened: Object[] = [];
    for (const value of values) {
      if (Array.isArray(value)) flattened.push(...value as Object[]);
      else flattened.push(value);
    }
    if (!index || index === '*') return flattened;
    const idx = parseInt(index);
    return idx >= 0 && idx < flattened.length ? [flattened[idx]] : [];
  }

  private deepFind(obj: Object, key: string): Object | string | undefined {
    if (Array.isArray(obj)) {
      for (const item of obj) {
        const r = this.deepFind(item as Object, key);
        if (r !== undefined) return r;
      }
    } else if (typeof obj === 'object' && obj !== null) {
      if ((obj as Record<string, Object>)[key] !== undefined) return (obj as Record<string, Object>)[key];
      for (const k in obj as Record<string, Object>) {
        const r = this.deepFind((obj as Record<string, Object>)[k] as Object, key);
        if (r !== undefined) return r;
      }
    }
    return undefined;
  }

  private applyJsBlocks(rule: string): string {
    if (!rule || !rule.includes('<js>')) return rule;
    return rule.replace(/<js>([\s\S]*?)<\/js>/gi, (_: string, code: string) => {
      const encodedUrl = this.evalEncodedDataUrlJs(code, this.content);
      if (encodedUrl) return encodedUrl;
      const result = this.evalJsBlockSideEffects(code);
      if (result) this.ctx.put('result', result);
      if (result && /\bresult\s*=/.test(code) && /^(?:https?:|\/|data:)/.test(result)) return result;
      return '';
    }).trim();
  }

  private evalJsBlockSideEffects(code: string): string {
    if (!code) return '';
    const knownValue = this.evalKnownJsLibBlock(code);
    if (knownValue) return knownValue;
    let lastValue = '';
    this.applySimpleAssignmentsToContext(code);
    const putRe = /java\.put\(\s*([^,]+)\s*,\s*([^)]+(?:\)[^,;]*)?)\s*\)/g;
    let putMatch: RegExpExecArray | null;
    while ((putMatch = putRe.exec(code)) !== null) {
      const key = this.stripQuotes(putMatch[1]);
      const value = this.evalJsValue(putMatch[2]);
      if (key) {
        this.ctx.put(key, value);
        lastValue = value;
      }
    }
    const sourceSetRe = /source\.setVariable\(\s*([\s\S]*?)\s*\)\s*;?/g;
    let sourceSetMatch: RegExpExecArray | null;
    while ((sourceSetMatch = sourceSetRe.exec(code)) !== null) {
      const value = this.evalJsValue(sourceSetMatch[1]);
      this.ctx.put('source.variable', value);
      lastValue = value;
    }

    const resultAssign = code.match(/\bresult\s*=\s*([^;]+);?/);
    if (resultAssign) {
      const resultExpr = resultAssign[1].trim();
      lastValue = this.evalJsValue(resultExpr);
      if (lastValue === resultExpr && /^[A-Za-z_][A-Za-z0-9_]*$/.test(resultExpr)) lastValue = '';
      if (lastValue) this.ctx.put('result', lastValue);
    }
    if (!lastValue) {
      const vars: Record<string, string> = { result: this.ctx.get('result') };
      const statements = this.splitJsStatements(code);
      for (const statement of statements) {
        const assign = statement.match(/^(?:var|let|const)?\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([\s\S]+)$/);
        if (assign) {
          const value = this.evalSimpleJsExpression(assign[2], vars);
          vars[assign[1]] = value === null ? '' : value;
          if (assign[1] === 'result') {
            this.ctx.put('result', vars[assign[1]]);
            lastValue = vars[assign[1]];
          }
        } else {
          const value = this.evalSimpleJsExpression(statement, vars);
          if (value !== null) lastValue = value;
        }
      }
    }
    return lastValue;
  }

  private splitJsStatements(code: string): string[] {
    const normalized = (code || '').replace(/\r/g, '\n').replace(/\n\s*\./g, '.');
    const parts: string[] = [];
    let start = 0;
    let quote = '';
    let depth = 0;
    for (let i = 0; i < normalized.length; i++) {
      const ch = normalized.charAt(i);
      if (quote) {
        if (ch === quote && normalized.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if ((ch === ';' || ch === '\n') && depth === 0) {
        const part = normalized.substring(start, i).trim();
        if (part && !part.startsWith('//')) parts.push(part);
        start = i + 1;
      }
    }
    const last = normalized.substring(start).trim();
    if (last && !last.startsWith('//')) parts.push(last);
    return parts;
  }

  private applySimpleAssignmentsToContext(code: string): void {
    const data = EncodedSourceUrl.asMap(this.parseContentObject());
    const assignRe = /\b(?:let|var|const)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*result\.([A-Za-z_][A-Za-z0-9_]*)\s*;/g;
    let assignMatch: RegExpExecArray | null;
    while ((assignMatch = assignRe.exec(code)) !== null) {
      const value = data[assignMatch[2]];
      if (value !== undefined && value !== null) this.ctx.put(assignMatch[1], String(value));
    }
    const destructMatch = code.match(/\{([^}]+)\}\s*=\s*result/);
    if (destructMatch) {
      const names = destructMatch[1].split(',').map(item => item.trim()).filter(item => item.length > 0);
      for (const name of names) {
        const key = name.includes(':') ? name.split(':')[0].trim() : name;
        const alias = name.includes(':') ? name.split(':')[1].trim() : name;
        const value = data[key];
        if (value !== undefined && value !== null) this.ctx.put(alias, String(value));
      }
    }
  }

  private evalJsValue(expr: string): string {
    if (!expr) return '';
    let text = expr.trim();
    text = text.replace(/\{\{([^}]+)\}\}/g, (_: string, rule: string) => {
      return this.resolveRuleValue(rule.trim());
    });
    text = text.replace(/\$\.\.(\w+)/g, (_: string, key: string) => {
      const v = this.deepFind(this.parseContentObject(), key);
      return this.jsonValueToString(v);
    });
    text = text.replace(/\$\.(\w+)/g, (_: string, key: string) => {
      const data = EncodedSourceUrl.asMap(this.parseContentObject());
      const v = data ? data[key] : undefined;
      return this.jsonValueToString(v);
    });
    text = text.replace(/\bresult\b/g, this.ctx.get('result'));
    text = this.replaceSourceCalls(text);
    text = this.js.evalTemplate(`{{${text}}}`);
    return this.stripQuotes(text);
  }

  private evalSimpleJsExpression(expr: string, vars: Record<string, string>): string | null {
    if (!expr) return '';
    let text = expr.trim();
    if (!text || /\b(function|if|while|for|JSON|java\.ajax|java\.get\(|java\.post\()/i.test(text)) return null;
    text = text.replace(/\{\{([^}]+)\}\}/g, (_: string, rule: string) => this.resolveRuleValue(rule.trim()));
    text = text.replace(/\$\.\.(\w+)/g, (_: string, key: string) => this.jsonValueToString(this.deepFind(this.parseContentObject(), key)));
    text = text.replace(/\$\.(\w+)/g, (_: string, key: string) => {
      const data = EncodedSourceUrl.asMap(this.parseContentObject());
      return this.jsonValueToString(data[key]);
    });
    const baseUrlMatch = this.evalBaseUrlMatchReplace(text);
    if (baseUrlMatch !== null) return baseUrlMatch;

    const question = this.indexOfTopLevel(text, '?');
    if (question >= 0) {
      const colon = this.indexOfTopLevelFrom(text, ':', question + 1);
      if (colon < 0) return null;
      const condition = this.evalJsCondition(text.substring(0, question), vars);
      return this.evalSimpleJsExpression(condition ? text.substring(question + 1, colon) : text.substring(colon + 1), vars);
    }

    const parts = this.splitJsConcat(text);
    if (parts.length > 1) {
      let value = '';
      for (const part of parts) {
        const item = this.evalSimpleJsExpression(part, vars);
        value += item === null ? '' : item;
      }
      return value;
    }

    text = text.trim();
    const sourceValue = this.evalSourceVariable(text);
    if (sourceValue !== null) return sourceValue;
    if (vars[text] !== undefined) return vars[text];
    if (text === 'baseUrl') return this.baseUrl;
    if (text === 'true' || text === 'false') return text;
    if ((text.startsWith('"') && text.endsWith('"')) || (text.startsWith("'") && text.endsWith("'"))) {
      return text.substring(1, text.length - 1);
    }
    if (/^-?\d+(?:\.\d+)?$/.test(text)) return text;
    if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(text)) return this.ctx.get(text) || vars[text] || '';
    return null;
  }

  private evalBaseUrlMatchReplace(expr: string): string | null {
    if (!expr.includes('baseUrl.match')) return null;
    const match = expr.match(/baseUrl\.match\((\/([\s\S]*?)\/[gimsuy]*)\)\s*\[\s*0\s*\]([\s\S]*)$/);
    if (!match) return null;
    const re = this.parseJsRegex(match[1]);
    const found = re ? this.baseUrl.match(re) : null;
    let value = found && found[0] !== undefined ? found[0] : '';
    const replaceRe = /\.replace\(\s*(['"])(.*?)\1\s*,\s*(['"])(.*?)\3\s*\)/g;
    let replaceMatch: RegExpExecArray | null;
    while ((replaceMatch = replaceRe.exec(match[3])) !== null) {
      value = value.split(replaceMatch[2]).join(replaceMatch[4]);
    }
    return value;
  }

  private evalJsCondition(expr: string, vars: Record<string, string>): boolean {
    const match = expr.match(/^([\s\S]+?)\s*(===|!==|==|!=|>=|<=|>|<)\s*([\s\S]+)$/);
    if (!match) {
      const value = this.evalSimpleJsExpression(expr, vars);
      return value !== null && value !== '' && value !== 'false' && value !== '0';
    }
    const left = this.evalSimpleJsExpression(match[1], vars) || '';
    const right = this.evalSimpleJsExpression(match[3], vars) || '';
    const ln = Number(left);
    const rn = Number(right);
    const numeric = !Number.isNaN(ln) && !Number.isNaN(rn) && left !== '' && right !== '';
    const a = numeric ? ln : left;
    const b = numeric ? rn : right;
    switch (match[2]) {
      case '===':
      case '==': return a === b;
      case '!==':
      case '!=': return a !== b;
      case '>=': return a >= b;
      case '<=': return a <= b;
      case '>': return a > b;
      case '<': return a < b;
    }
    return false;
  }

  private resolveRuleValue(rule: string): string {
    if (!rule) return '';
    if (rule.startsWith('@get:{')) {
      const m = rule.match(/@get:\{([^}]+)\}/);
      return m ? this.ctx.get(m[1].trim()) : '';
    }
    if (rule.startsWith('$') || rule.startsWith('@.')) {
      const v = this.evalJsonPath(rule);
      if (Array.isArray(v)) return this.jsonPathArrayToStrings(v as Object[]).join(',');
      return this.jsonValueToString(v);
    }
    const ctxVal = this.ctx.get(rule);
    if (ctxVal) return ctxVal;
    return this.js.evalTemplate(`{{${rule}}}`);
  }

  private parseContentObject(): Object {
    try {
      return JSON.parse(this.content) as Object;
    } catch (_) {
      return {};
    }
  }

  // === CSS 选择器 ===

  private evalLegacyRule(rule: string): string[] {
    if (!rule || !this.content) return [];
    rule = this.stripJsWrapper(rule).trim();
    if (rule.startsWith('@css:')) rule = rule.substring(5).trim();
    if (!rule.includes('@') && !this.isLegacySelector(rule) && !this.isAttrName(rule)) return [];

    const parts = rule.split('@').map(part => part.trim()).filter(part => part.length > 0);
    if (parts.length === 0) return [];

    let current: string[] = [this.content];
    for (const part of parts) {
      if (part.startsWith('js:')) {
        current = current.map(item => this.evalResultJs(part.substring(3), item)).filter(v => v.length > 0);
      } else if (part.startsWith('children[')) {
        const idx = parseInt(part.substring(9, part.indexOf(']')));
        const next: string[] = [];
        for (const item of current) next.push(...this.pickIndex(this.getDirectChildren(item), idx));
        current = next;
      } else
      if (this.isAttrName(part)) {
        current = current.map(item => this.extractAttr(item, this.normalizeAttrName(part))).filter(v => v.length > 0);
      } else if (part === 'text') {
        current = current.map(item => this.stripHtml(item)).filter(v => v.length > 0);
      } else if (part === 'ownText') {
        current = current.map(item => this.extractOwnText(item)).filter(v => v.length > 0);
      } else if (part === 'textNodes') {
        current = current.map(item => this.extractTextNodes(item)).filter(v => v.length > 0);
      } else if (part === 'html') {
        current = current.filter(v => v.length > 0);
      } else {
        const next: string[] = [];
        for (const item of current) {
          next.push(...this.matchLegacySelector(item, part));
        }
        current = next;
      }
      if (current.length === 0) break;
    }
    return current;
  }

  private isLegacySelector(part: string): boolean {
    return /^(class|id|tag)\.[^@]+/.test(part) || /^[-]?\d+$/.test(part) ||
      part.startsWith('.') || part.startsWith('#') || part.startsWith('@css:') || part.includes('[') || part.includes('!') ||
      /^[a-zA-Z][a-zA-Z0-9_-]*(\.-?\d+(:-?\d+)?)?$/.test(part);
  }

  private isAttrName(part: string): boolean {
    return part === 'href' || part === 'src' || part === 'content' || part === 'data-src' ||
      part === 'data-lazy' || part === 'data-bid' || part === 'onclick' || part === 'title' ||
      part === 'alt' || part === 'class' || part === 'id';
  }

  private normalizeAttrName(part: string): string {
    return part.startsWith('data-') ? part : part;
  }

  private matchLegacySelector(html: string, selector: string): string[] {
    if (!selector || !html) return [];

    const pieces = selector.split('.').filter(part => part.length > 0);
    if (pieces.length === 0) return [];

    let mode = '';
    let name = '';
    let index: number | null = null;

    if (pieces[0] === 'class' || pieces[0] === 'id' || pieces[0] === 'tag') {
      mode = pieces[0];
      name = pieces.length > 1 ? pieces[1] : '';
      const rangeMatch = name.match(/^([A-Za-z0-9_-]+)\[(-?\d+)(?::(-?\d+))?\]$/);
      if (rangeMatch) {
        name = rangeMatch[1];
        const matches = mode === 'class' ? this.matchByClass(html, name) :
          mode === 'id' ? this.matchById(html, name) : this.matchByTag(html, name);
        return this.pickRange(matches, parseInt(rangeMatch[2]), rangeMatch[3] !== undefined ? parseInt(rangeMatch[3]) : null);
      }
      if (pieces.length > 2 && /^-?\d+$/.test(pieces[2])) index = parseInt(pieces[2]);
    } else if (selector.startsWith('.') || selector.startsWith('#') || /^[a-zA-Z][a-zA-Z0-9_-]*/.test(selector)) {
      return this.matchSimpleElements(html, this.normalizeCssSelector(selector));
    }

    let matches: string[] = [];
    if (mode === 'class') matches = this.matchByClass(html, name);
    if (mode === 'id') matches = this.matchById(html, name);
    if (mode === 'tag') matches = this.matchByTag(html, name);

    return index === null ? matches : this.pickIndex(matches, index);
  }

  private pickIndex(values: string[], index: number): string[] {
    if (values.length === 0) return [];
    const real = index < 0 ? values.length + index : index;
    if (real < 0 || real >= values.length) return [];
    return [values[real]];
  }

  private matchByClass(html: string, className: string): string[] {
    if (!className) return [];
    return this.matchSimpleElements(html, '.' + className);
  }

  private matchById(html: string, id: string): string[] {
    if (!id) return [];
    return this.matchSimpleElements(html, '#' + id);
  }

  private matchByTag(html: string, tag: string): string[] {
    if (!tag) return [];
    return this.matchSimpleElements(html, tag);
  }

  private escapeRegex(text: string): string {
    return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  private evalCss(selector: string): string[] {
    if (!selector || !this.content) return [];
    const s = this.stripJsWrapper(selector).trim();
    const clean = s.startsWith('@css:') ? s.substring(5).trim() : s;

    // 属性提取:  selector@attr
    const atIdx = clean.lastIndexOf('@');
    let attr = '';
    let sel = clean;
    if (atIdx > 0) {
      const suf = clean.substring(atIdx + 1);
      if (suf === 'text' || suf === 'html' || this.isAttrName(suf)) {
        attr = suf;
        sel = clean.substring(0, atIdx);
      }
    }

    const matches = this.matchElements(sel);
    if (matches.length === 0) return [];

    if (attr === 'text') return matches.map(m => this.stripHtml(m));
    if (attr === 'html') return matches;
    if (attr) return matches.map(m => this.extractAttr(m, attr)).filter((v: string) => v.length > 0);

    return matches.map(m => this.stripHtml(m));
  }

  private matchElements(sel: string): string[] {
    // 防止大内容导致 OOM
    const MAX_LEN = 500000;
    if (this.content.length > MAX_LEN) return [];

    sel = this.normalizeCssSelector(this.stripJsWrapper(sel).trim());
    const groups = this.splitSelectorGroups(sel);
    if (groups.length > 1) {
      const values: string[] = [];
      for (const group of groups) {
        for (const value of this.matchElements(group)) if (!values.includes(value)) values.push(value);
      }
      return values;
    }
    const selectors = this.splitCssSelector(sel);
    if (selectors.length > 1) {
      let contexts: string[] = [this.content];
      let directChild = false;
      for (const part of selectors) {
        if (part === '>') {
          directChild = true;
          continue;
        }
        const next: string[] = [];
        for (const ctx of contexts) {
          if (directChild) {
            for (const child of this.getDirectChildren(ctx)) {
              if (this.matchSimpleElements(child, part).includes(child)) next.push(child);
            }
          } else {
            next.push(...this.matchSimpleElements(ctx, part));
          }
        }
        contexts = next;
        directChild = false;
        if (contexts.length === 0) break;
      }
      return contexts;
    }

    return this.matchSimpleElements(this.content, sel);
  }

  private matchSimpleElements(html: string, sel: string): string[] {
    if (!html || !sel) return [];
    let query = sel.trim();
    let containsText = '';
    let hasSelector = '';
    let notSelector = '';
    let positionMode = '';
    let positionValue = 0;
    query = query.replace(/:contains\(\s*(['"]?)(.*?)\1\s*\)/i, (_: string, _quote: string, text: string) => {
      containsText = text;
      return '';
    });
    query = query.replace(/:has\(\s*([^()]*)\s*\)/i, (_: string, nested: string) => {
      hasSelector = nested.trim();
      return '';
    });
    query = query.replace(/:not\(\s*([^()\[\]]+)\s*\)/i, (_: string, nested: string) => {
      notSelector = nested.trim();
      return '';
    });
    query = query.replace(/:(first|last)(?![-\w(])/i, (_: string, mode: string) => {
      positionMode = mode.toLowerCase();
      return '';
    });
    query = query.replace(/:(eq|lt|gt)\(\s*(-?\d+)\s*\)/i, (_: string, mode: string, index: string) => {
      positionMode = mode.toLowerCase();
      positionValue = parseInt(index);
      return '';
    });
    const parsed = this.parseSimpleSelector(query);
    if (!parsed) return [];
    const tagPattern = parsed.tag ? this.escapeRegex(parsed.tag) : '[a-zA-Z][a-zA-Z0-9_-]*';
    try {
      const re = new RegExp(`<(${tagPattern})(\\s[^>]*)?>`, 'gi');
      const res: string[] = [];
      let m: RegExpExecArray | null;
      while ((m = re.exec(html)) !== null) {
        const fullStartTag = m[0];
        const attrText = m[2] || '';
        if (!this.matchSelectorAttrs(attrText, parsed.id, parsed.classes, parsed.attrs)) continue;
        if (this.matchExcludedAttrs(attrText, parsed.notAttrs)) continue;
        if (!this.matchNthPseudo(html, m.index, m[1], parsed.nthChild, parsed.nthOfType)) continue;
        res.push(this.sliceWholeElement(html, m.index, fullStartTag, m[1]));
        if (res.length > 5000) break;
      }
      let filtered = parsed.excludeIndex === null ? res : this.excludeIndex(res, parsed.excludeIndex);
      if (containsText) filtered = filtered.filter(item => this.stripHtml(item).includes(containsText));
      if (hasSelector) filtered = filtered.filter(item => new AnalyzeRule(item, this.baseUrl, this.ctx).matchElements(hasSelector).length > 0);
      if (notSelector) filtered = filtered.filter(item => !this.elementMatchesSelector(item, notSelector));
      if (parsed.indexStart !== null) return this.pickRange(filtered, parsed.indexStart, parsed.indexEnd);
      if (positionMode === 'first') return this.pickIndex(filtered, 0);
      if (positionMode === 'last') return this.pickIndex(filtered, -1);
      if (positionMode === 'eq') return this.pickIndex(filtered, positionValue);
      if (positionMode === 'lt') return filtered.slice(0, Math.max(0, positionValue < 0 ? filtered.length + positionValue : positionValue));
      if (positionMode === 'gt') {
        const index = positionValue < 0 ? filtered.length + positionValue : positionValue;
        return filtered.slice(Math.min(filtered.length, index + 1));
      }
      return filtered;
    } catch (_) {
      return [];
    }
  }

  private extractAttr(html: string, attr: string): string {
    const startTag = html.match(/^<[^>]+>/);
    return startTag ? this.getHtmlAttr(startTag[0], attr) : '';
  }

  private stripJsWrapper(rule: string): string {
    let r = rule || '';
    if (r.includes('<js>') && (r.includes('startBrowserAwait') || r.includes('getVerificationCode')) &&
      VerificationSupport.isChallengeResponse(this.content)) {
      const code = this.extractJsBlock(r);
      const verifyUrl = VerificationSupport.pickStartBrowserUrl(code) || this.baseUrl;
      VerificationSupport.requestVerification(verifyUrl, '网页验证');
    }
    const end = r.lastIndexOf('</js>');
    if (end >= 0) r = r.substring(end + 5);
    r = r.replace(/<js>[\s\S]*?<\/js>/gi, '');
    return r;
  }

  private extractJsBlock(rule: string): string {
    const match = rule.match(/<js>([\s\S]*?)<\/js>/i);
    return match ? match[1] : rule;
  }

  private splitCssSelector(sel: string): string[] {
    const parts: string[] = [];
    let start = 0;
    let bracket = 0;
    let quote = '';
    for (let i = 0; i < sel.length; i++) {
      const ch = sel.charAt(i);
      if (quote) {
        if (ch === quote && sel.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '[') bracket++;
      if (ch === ']') bracket--;
      if (ch === '>' && bracket === 0) {
        const part = sel.substring(start, i).trim();
        if (part) parts.push(part);
        parts.push('>');
        start = i + 1;
      } else if (/\s/.test(ch) && bracket === 0) {
        const part = sel.substring(start, i).trim();
        if (part) parts.push(part);
        start = i + 1;
      }
    }
    const last = sel.substring(start).trim();
    if (last) parts.push(last);
    return parts;
  }

  private normalizeCssSelector(sel: string): string {
    let s = sel;
    if (s.startsWith('@css:')) s = s.substring(5).trim();
    s = s.replace(/\s*>\s*/g, ' > ');
    return s;
  }

  private splitSelectorGroups(selector: string): string[] {
    const groups: string[] = [];
    let start = 0;
    let square = 0;
    let round = 0;
    let quote = '';
    for (let i = 0; i < selector.length; i++) {
      const ch = selector.charAt(i);
      if (quote) {
        if (ch === quote && selector.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '[') square++;
      if (ch === ']') square--;
      if (ch === '(') round++;
      if (ch === ')') round--;
      if (ch === ',' && square === 0 && round === 0) {
        groups.push(selector.substring(start, i).trim());
        start = i + 1;
      }
    }
    groups.push(selector.substring(start).trim());
    return groups.filter(group => group.length > 0);
  }

  private elementMatchesSelector(element: string, selector: string): boolean {
    const start = element.match(/^<([a-zA-Z][a-zA-Z0-9_-]*)(\s[^>]*)?>/);
    if (!start) return false;
    const parsed = this.parseSimpleSelector(selector);
    if (!parsed) return false;
    if (parsed.tag && parsed.tag !== '*' && parsed.tag.toLowerCase() !== start[1].toLowerCase()) return false;
    const attrText = start[2] || '';
    return this.matchSelectorAttrs(attrText, parsed.id, parsed.classes, parsed.attrs) &&
      !this.matchExcludedAttrs(attrText, parsed.notAttrs);
  }

  private parseSimpleSelector(sel: string): {
    tag: string,
    id: string,
    classes: string[],
    attrs: Array<Record<string, string>>,
    notAttrs: Array<Record<string, string>>,
    nthChild: number | null,
    nthOfType: number | null,
    indexStart: number | null,
    indexEnd: number | null,
    excludeIndex: number | null
  } | null {
    let s = sel.trim();
    const notAttrs: Array<Record<string, string>> = [];
    s = s.replace(/:not\(\[([^\]]+)\]\)/g, (_: string, body: string) => {
      const m = body.match(/^([A-Za-z_:][\w:.-]*)([$~^*|]?=)?["']?([^"']*)["']?$/);
      if (m) notAttrs.push({ name: m[1], op: m[2] || '', value: m[3] || '' });
      return '';
    });
    let nthChild: number | null = null;
    let nthOfType: number | null = null;
    s = s.replace(/:nth-child\(\s*(\d+)\s*\)/gi, (_: string, index: string) => {
      nthChild = parseInt(index);
      return '';
    });
    s = s.replace(/:nth-of-type\(\s*(\d+)\s*\)/gi, (_: string, index: string) => {
      nthOfType = parseInt(index);
      return '';
    });
    let excludeIndex: number | null = null;
    const excludeMatch = s.match(/!(\-?\d+)$/);
    if (excludeMatch) {
      excludeIndex = parseInt(excludeMatch[1]);
      s = s.substring(0, excludeMatch.index).trim();
    }

    let indexStart: number | null = null;
    let indexEnd: number | null = null;
    const indexMatch = s.match(/\.(-?\d+)(?::(-?\d+))?$/);
    if (indexMatch) {
      indexStart = parseInt(indexMatch[1]);
      if (indexMatch[2] !== undefined) indexEnd = parseInt(indexMatch[2]);
      s = s.substring(0, indexMatch.index).trim();
    }

    const attrs: Array<Record<string, string>> = [];
    s = s.replace(/\[([^\]]+)\]/g, (_: string, body: string) => {
      const m = body.match(/^([A-Za-z_:][\w:.-]*)([$~^*|]?=)?["']?([^"']*)["']?$/);
      if (m) attrs.push({ name: m[1], op: m[2] || '', value: m[3] || '' });
      return '';
    });

    let tag = '';
    let id = '';
    const classes: string[] = [];
    let i = 0;
    const tagMatch = s.match(/^(?:\*|[A-Za-z][A-Za-z0-9_-]*)/);
    if (tagMatch) {
      tag = tagMatch[0];
      i = tag.length;
    }
    while (i < s.length) {
      const ch = s.charAt(i);
      if (ch !== '.' && ch !== '#') return null;
      let j = i + 1;
      while (j < s.length && /[A-Za-z0-9_-]/.test(s.charAt(j))) j++;
      const value = s.substring(i + 1, j);
      if (!value) return null;
      if (ch === '.') classes.push(value);
      if (ch === '#') id = value;
      i = j;
    }
    return { tag, id, classes, attrs, notAttrs, nthChild, nthOfType, indexStart, indexEnd, excludeIndex };
  }

  private matchSelectorAttrs(attrText: string, id: string, classes: string[], attrs: Array<Record<string, string>>): boolean {
    if (id && this.getHtmlAttr(attrText, 'id') !== id) return false;
    const classValue = this.getHtmlAttr(attrText, 'class');
    for (const cls of classes) {
      if (!new RegExp(`(^|\\s)${this.escapeRegex(cls)}(\\s|$)`).test(classValue)) return false;
    }
    for (const attr of attrs) {
      const value = this.getHtmlAttr(attrText, attr['name']);
      if (!value && attr['op']) return false;
      if (!attr['op'] && value === '') return false;
      const expect = attr['value'];
      switch (attr['op']) {
        case '=': if (value !== expect) return false; break;
        case '$=': if (!value.endsWith(expect)) return false; break;
        case '^=': if (!value.startsWith(expect)) return false; break;
        case '*=': if (!value.includes(expect)) return false; break;
        case '~=': if (!this.matchRegexLikeAttribute(value, expect)) return false; break;
        case '|=': if (value !== expect && !value.startsWith(expect + '-')) return false; break;
      }
    }
    return true;
  }

  private matchExcludedAttrs(attrText: string, attrs: Array<Record<string, string>>): boolean {
    for (const attr of attrs) {
      const value = this.getHtmlAttr(attrText, attr['name']);
      if (!value) continue;
      if (!attr['op']) return true;
      const expect = attr['value'];
      switch (attr['op']) {
        case '=': if (value === expect) return true; break;
        case '$=': if (value.endsWith(expect)) return true; break;
        case '^=': if (value.startsWith(expect)) return true; break;
        case '*=': if (value.includes(expect)) return true; break;
        case '~=': if (this.matchRegexLikeAttribute(value, expect)) return true; break;
        case '|=': if (value === expect || value.startsWith(expect + '-')) return true; break;
      }
    }
    return false;
  }

  private matchNthPseudo(html: string, startIndex: number, tag: string, nthChild: number | null, nthOfType: number | null): boolean {
    if (nthChild === null && nthOfType === null) return true;
    const pos = this.directChildPosition(html, startIndex, tag);
    if (nthChild !== null && pos.child !== nthChild) return false;
    if (nthOfType !== null && pos.type !== nthOfType) return false;
    return true;
  }

  private matchRegexLikeAttribute(value: string, expect: string): boolean {
    if (!value) return false;
    try {
      return new RegExp(expect, 'i').test(value);
    } catch (_) {
      return new RegExp(`(^|\\s)${this.escapeRegex(expect)}(\\s|$)`).test(value);
    }
  }

  private directChildPosition(html: string, targetIndex: number, targetTag: string): { child: number, type: number } {
    const stack: Array<{ tag: string, childCount: number, typeCounts: Record<string, number> }> = [];
    const re = /<\/?([a-zA-Z][a-zA-Z0-9_-]*)(?:\s[^>]*)?>/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(html)) !== null) {
      if (m.index > targetIndex) break;
      const raw = m[0];
      const tag = m[1].toLowerCase();
      if (raw.startsWith('</')) {
        for (let i = stack.length - 1; i >= 0; i--) {
          if (String(stack[i]['tag']) === tag) {
            stack.splice(i);
            break;
          }
        }
        continue;
      }

      let childIndex = 1;
      let typeIndex = 1;
      if (stack.length > 0) {
        const parent = stack[stack.length - 1];
        childIndex = parent.childCount + 1;
        parent.childCount = childIndex;
        typeIndex = (parent.typeCounts[tag] || 0) + 1;
        parent.typeCounts[tag] = typeIndex;
      }
      if (m.index === targetIndex) {
        return { child: childIndex, type: targetTag.toLowerCase() === tag ? typeIndex : 0 };
      }
      if (!raw.endsWith('/>') && !this.isVoidTag(tag)) {
        stack.push({ tag: tag, childCount: 0, typeCounts: {} as Record<string, number> });
      }
    }
    return { child: 0, type: 0 };
  }

  private getHtmlAttr(attrText: string, attr: string): string {
    const re = new RegExp(`\\s${this.escapeRegex(attr)}\\s*=\\s*(["'])(.*?)\\1`, 'i');
    const m = attrText.match(re);
    if (m) return m[2];
    const bare = new RegExp(`\\s${this.escapeRegex(attr)}\\s*=\\s*([^\\s>]+)`, 'i').exec(attrText);
    return bare ? bare[1] : '';
  }

  private sliceWholeElement(html: string, startIndex: number, startTag: string, tag: string): string {
    const lower = tag.toLowerCase();
    if (this.isVoidTag(lower)) return startTag;
    const re = new RegExp(`<\\/?${this.escapeRegex(tag)}(?:\\s[^>]*)?>`, 'gi');
    re.lastIndex = startIndex + startTag.length;
    let depth = 1;
    let m: RegExpExecArray | null;
    while ((m = re.exec(html)) !== null) {
      if (m[0].startsWith('</')) depth--;
      else if (!m[0].endsWith('/>')) depth++;
      if (depth === 0) return html.substring(startIndex, re.lastIndex);
    }
    return startTag;
  }

  private isVoidTag(tag: string): boolean {
    return tag === 'area' || tag === 'base' || tag === 'br' || tag === 'col' || tag === 'embed' ||
      tag === 'hr' || tag === 'img' || tag === 'input' || tag === 'link' || tag === 'meta' ||
      tag === 'param' || tag === 'source' || tag === 'track' || tag === 'wbr';
  }

  private getDirectChildren(html: string): string[] {
    const innerMatch = html.match(/^<([a-zA-Z][a-zA-Z0-9_-]*)[^>]*>([\s\S]*)<\/\1>\s*$/);
    const inner = innerMatch ? innerMatch[2] : html;
    const children: string[] = [];
    const re = /<([a-zA-Z][a-zA-Z0-9_-]*)(\s[^>]*)?>/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(inner)) !== null) {
      children.push(this.sliceWholeElement(inner, m.index, m[0], m[1]));
      if (children.length > 5000) break;
      re.lastIndex = m.index + children[children.length - 1].length;
    }
    return children;
  }

  private evalRegexRule(rule: string): string[] {
    if (!rule || rule.length > 300 || !/[()\\[\].*+?]/.test(rule)) return [];
    try {
      const re = new RegExp(rule, 'g');
      const values: string[] = [];
      let m: RegExpExecArray | null;
      while ((m = re.exec(this.content)) !== null) {
        if (m.length > 1) {
          const rec: Record<string, string> = { '$0': m[0] };
          for (let i = 1; i < m.length; i++) rec[`$${i}`] = m[i] || '';
          values.push(JSON.stringify(rec));
        } else {
          values.push(m[0]);
        }
        if (values.length > 5000) break;
        if (m[0].length === 0) re.lastIndex++;
      }
      return values;
    } catch (_) {
      return [];
    }
  }

  private evalXPathBasic(rule: string): string[] {
    if (!rule.startsWith('//')) return [];
    const translated = this.translateXPath(rule);
    if (!translated.selector) return [];
    const matches = this.matchElements(translated.selector);
    if (translated.attr) return matches.map(item => this.extractAttr(item, translated.attr)).filter(value => value.length > 0);
    if (translated.mode === 'text') return matches.map(item => this.stripHtml(item)).filter(value => value.length > 0);
    if (translated.mode === 'html') return matches;
    return matches;
  }

  private translateXPath(xpath: string): { selector: string, attr: string, mode: string } {
    let value = xpath.trim();
    let attr = '';
    let mode = 'html';
    const attrMatch = value.match(/\/@([A-Za-z_:][\w:.-]*)$/);
    if (attrMatch) {
      attr = attrMatch[1];
      value = value.substring(0, value.length - attrMatch[0].length);
    } else if (/\/text\(\)$/.test(value) || /\/string\(\)$/.test(value)) {
      mode = 'text';
      value = value.replace(/\/(?:text|string)\(\)$/, '');
    }

    const rawParts = value.replace(/^\/\//, '').split(/\/\/?/).filter(part => part.length > 0);
    const parts: string[] = [];
    for (let part of rawParts) {
      let tag = (part.match(/^[A-Za-z*][\w-]*/) || ['*'])[0];
      const predicates = part.match(/\[[^\]]+\]/g) || [];
      for (const predicateRaw of predicates) {
        const predicate = predicateRaw.substring(1, predicateRaw.length - 1).trim();
        const attrEq = predicate.match(/^@([A-Za-z_:][\w:.-]*)\s*=\s*['"]([^'"]*)['"]$/);
        const containsAttr = predicate.match(/^contains\(\s*@([A-Za-z_:][\w:.-]*)\s*,\s*['"]([^'"]*)['"]\s*\)$/);
        const startsAttr = predicate.match(/^starts-with\(\s*@([A-Za-z_:][\w:.-]*)\s*,\s*['"]([^'"]*)['"]\s*\)$/);
        const containsText = predicate.match(/^contains\(\s*(?:\.|text\(\))\s*,\s*['"]([^'"]*)['"]\s*\)$/);
        if (attrEq) {
          if (attrEq[1] === 'id') tag += `#${attrEq[2]}`;
          else if (attrEq[1] === 'class' && !attrEq[2].includes(' ')) tag += `.${attrEq[2]}`;
          else tag += `[${attrEq[1]}="${attrEq[2]}"]`;
        } else if (containsAttr) {
          tag += `[${containsAttr[1]}*="${containsAttr[2]}"]`;
        } else if (startsAttr) {
          tag += `[${startsAttr[1]}^="${startsAttr[2]}"]`;
        } else if (containsText) {
          tag += `:contains("${containsText[1]}")`;
        } else if (/^\d+$/.test(predicate)) {
          tag += `:nth-of-type(${predicate})`;
        } else if (predicate === 'last()') {
          tag += ':last';
        } else if (/^@([A-Za-z_:][\w:.-]*)$/.test(predicate)) {
          tag += `[${predicate.substring(1)}]`;
        }
      }
      parts.push(tag);
    }
    return { selector: parts.join(' '), attr: attr, mode: mode };
  }

  private excludeIndex(values: string[], index: number): string[] {
    const real = index < 0 ? values.length + index : index;
    return values.filter((_, i) => i !== real);
  }

  private pickRange(values: string[], start: number, end: number | null): string[] {
    if (values.length === 0) return [];
    if (end === null) return this.pickIndex(values, start);
    const realStart = start < 0 ? values.length + start : start;
    const realEnd = end < 0 ? values.length + end : end;
    return values.slice(Math.max(0, realStart), Math.min(values.length, realEnd));
  }

  private evalResultJs(jsCode: string, value: string): string {
    if (!jsCode) return value;
    const knownValue = this.evalKnownResultJs(jsCode, value);
    if (knownValue !== null) return knownValue;
    const simpleValue = this.evalSimpleJsExpression(jsCode, { result: value, baseUrl: this.baseUrl });
    if (simpleValue !== null) return simpleValue;
    const encodedDataUrl = this.evalEncodedDataUrlJs(jsCode, value);
    if (encodedDataUrl) return encodedDataUrl;
    const replaceChainValue = this.evalResultReplaceChain(jsCode, value);
    if (replaceChainValue !== null) return replaceChainValue;
    const legacyValue = this.evalCommonLegacyJs(jsCode, value);
    if (legacyValue) return legacyValue;
    const putMatch = jsCode.match(/java\.put\(\s*['"]([^'"]+)['"]\s*,\s*result\s*\)/);
    if (putMatch) {
      this.ctx.put(putMatch[1], value);
    }
    const prefixConcat = jsCode.match(/['"](https?:\/\/[^'"]*)['"]\s*\+\s*result/);
    if (prefixConcat) return prefixConcat[1] + value;
    const suffixConcat = jsCode.match(/result\s*\+\s*['"]([^'"]*)['"]/);
    if (suffixConcat) return value + suffixConcat[1];
    const baseReplace = this.evalBaseUrlReplace(jsCode);
    if (baseReplace) return baseReplace;
    if (jsCode.includes('result')) {
      const literal = jsCode
        .replace(/^\s*result\s*=\s*/, '')
        .replace(/;\s*result\s*;?\s*$/, '')
        .trim();
      if (/^['"][\s\S]*result[\s\S]*['"]$/.test(literal) || literal.includes('+result')) {
        return literal
          .replace(/\s*\+\s*/g, '')
          .replace(/['"]/g, '')
          .replace(/result/g, value)
          .trim();
      }
    }
    const matchRule = jsCode.match(/result\.match\((\/.*?\/[gimsuy]*)\)\s*\[\s*(\d+)\s*\]/);
    if (matchRule) {
      const re = this.parseJsRegex(matchRule[1]);
      const idx = parseInt(matchRule[2]);
      if (re) {
        const m = value.match(re);
        return m && m[idx] !== undefined ? m[idx] : '';
      }
    }
    if (jsCode.includes('java.t2s')) return value;
    if (/book\.origin\s*\+\s*result/.test(jsCode)) return this.resolveUrl(value);
    if (/\bjava\.(?:base64|hex|md5|sha|url|encodeURI|aes|des|getCookie)/.test(jsCode)) {
      this.js.setVar('baseUrl', this.baseUrl);
      return this.js.evaluate(jsCode, value);
    }
    return value;
  }

  private evalKnownJsLibBlock(code: string): string {
    const normalized = code || '';
    const vars: Record<string, string> = { result: this.content, baseUrl: this.baseUrl };

    if (normalized.includes('J(result)') || normalized.includes('JSON.parse')) {
      const articleId = this.extractArticleIdFromContent() || this.extractArticleIdFromUrl(this.baseUrl);
      if (articleId) {
        vars['id'] = articleId;
        vars['aid'] = articleId;
      }
    }

    const cacheGet = normalized.match(/cache\.getFromMemory\(\s*['"]([^'"]+)['"]\s*\)/);
    if (cacheGet) {
      const value = this.ctx.get(`cache.${cacheGet[1]}`) || this.ctx.get(cacheGet[1]);
      if (value) {
        vars['aid'] = value;
        vars[cacheGet[1]] = value;
      }
    }

    if (!vars['aid']) {
      const fromUrl = this.extractArticleIdFromUrl(this.baseUrl);
      if (fromUrl) vars['aid'] = fromUrl;
    }

    const cachePut = normalized.match(/cache\.putMemory\(\s*['"]([^'"]+)['"]\s*,\s*String\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\)/);
    if (cachePut) {
      const value = vars[cachePut[2]] || this.ctx.get(cachePut[2]) || '';
      if (value) {
        this.ctx.put(`cache.${cachePut[1]}`, value);
        this.ctx.put(cachePut[1], value);
      }
    }

    const baseExprIndex = normalized.lastIndexOf('Base()');
    const lastExpr = baseExprIndex >= 0 ? normalized.substring(baseExprIndex) : this.extractLastJsExpression(normalized);
    if (!lastExpr) return '';
    return this.evalKnownJsExpression(lastExpr, vars);
  }

  private evalKnownResultJs(jsCode: string, value: string): string | null {
    const trimmed = jsCode.trim();
    if (/^Clean\(\s*result\s*\)\s*;?$/.test(trimmed)) return this.cleanJsLibText(value);
    if (/^T\(\s*result\s*\)\s*;?$/.test(trimmed)) return this.cleanJsLibText(value);
    if (/^Cover\(\s*result\s*\)\s*;?$/.test(trimmed)) return this.coverFromArticleId(value);
    if (trimmed.includes('Base()')) {
      const vars: Record<string, string> = { result: value, baseUrl: this.baseUrl };
      const cacheGet = trimmed.match(/cache\.getFromMemory\(\s*['"]([^'"]+)['"]\s*\)/);
      if (cacheGet) {
        const cached = this.ctx.get(`cache.${cacheGet[1]}`) || this.ctx.get(cacheGet[1]);
        if (cached) {
          vars['aid'] = cached;
          vars[cacheGet[1]] = cached;
        }
      }
      if (!vars['aid']) {
        const fromUrl = this.extractArticleIdFromUrl(this.baseUrl);
        if (fromUrl) vars['aid'] = fromUrl;
      }
      const baseExprIndex = trimmed.lastIndexOf('Base()');
      if (baseExprIndex >= 0) {
        const resolved = this.evalKnownJsExpression(trimmed.substring(baseExprIndex), vars);
        if (resolved) return resolved;
      }
    }
    return null;
  }

  private evalKnownJsExpression(expr: string, vars: Record<string, string>): string {
    let value = (expr || '').trim().replace(/;$/, '');
    if (!value) return '';
    const cleanCall = value.match(/^(?:Clean|T)\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$/);
    if (cleanCall) return this.cleanJsLibText(vars[cleanCall[1]] || '');
    const coverCall = value.match(/^Cover\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$/);
    if (coverCall) return this.coverFromArticleId(vars[coverCall[1]] || '');
    value = value.replace(/\bBase\(\)/g, `'${this.extractBaseFunctionHost()}'`);
    value = value.replace(/\bString\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/g, (_: string, key: string) => {
      return `'${(vars[key] || '').replace(/'/g, "\\'")}'`;
    });
    const parts = this.splitJsConcat(value);
    if (parts.length <= 1 && !/^['"]/.test(value)) return vars[value] || '';
    let out = '';
    for (const part of parts) {
      const token = part.trim();
      if (!token) continue;
      if ((token.startsWith("'") && token.endsWith("'")) || (token.startsWith('"') && token.endsWith('"'))) {
        out += token.substring(1, token.length - 1);
      } else if (vars[token] !== undefined) {
        out += vars[token];
      } else if (/^\d+$/.test(token)) {
        out += token;
      } else {
        return '';
      }
    }
    return out;
  }

  private extractArticleIdFromContent(): string {
    try {
      const data = EncodedSourceUrl.asMap(JSON.parse(this.content || '{}') as Object);
      const direct = EncodedSourceUrl.str(data['articleid']);
      if (direct) return direct;
      const nested = EncodedSourceUrl.asMap(data['data'] as Object);
      return EncodedSourceUrl.str(nested['articleid']);
    } catch (_) {
      return '';
    }
  }

  private extractArticleIdFromUrl(url: string): string {
    const value = url || '';
    const match = value.match(/\/(?:detail|list)\/(\d+)(?:\D|$)/) || value.match(/[?&]articleid=(\d+)/i);
    return match ? match[1] : '';
  }

  private extractBaseFunctionHost(): string {
    const raw = this.ctx.get('source.jsLib') || this.ctx.get('jsLib') || '';
    const baseMatch = raw.match(/function\s+Base\s*\(\s*\)\s*\{\s*return\s*['"]([^'"]+)['"]/);
    if (baseMatch) return baseMatch[1];
    const hostMatch = raw.match(/https?:\/\/[^'"`\s,)]+/);
    if (hostMatch) return hostMatch[0];
    const base = (this.ctx.get('source.bookSourceUrl') || this.ctx.get('bookSourceUrl') || this.baseUrl || '')
      .match(/^(https?:\/\/[^/]+)/);
    return base ? base[1] : '';
  }

  private coverFromArticleId(value: string): string {
    const id = (value || '').replace(/\D/g, '');
    if (!id) return '';
    return `https://pic.cooks.tw/${Math.floor(Number(id) / 1000)}/${id}/${id}s.jpg`;
  }

  private cleanJsLibText(value: string): string {
    return (value || '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<p[^>]*>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&#39;/g, "'")
      .replace(/&quot;/g, '"')
      .replace(/\r/g, '')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private evalResultReplaceChain(jsCode: string, value: string): string | null {
    if (!jsCode || !jsCode.includes('result.replace')) return null;
    const vars = this.evalSimpleJsVariables(jsCode, value);
    let current = value;
    const replaceRe = /(?:result|String\s*\(\s*result\s*\)|\))\.replace\s*\(\s*([^,]+)\s*,\s*([^)]+)\s*\)/g;
    let matched = false;
    let match: RegExpExecArray | null;
    while ((match = replaceRe.exec(jsCode)) !== null) {
      const pattern = this.parseReplacePattern(match[1]);
      if (!pattern) continue;
      matched = true;
      current = current.replace(pattern, this.evalReplaceArgument(match[2], vars));
    }
    return matched ? current : null;
  }

  private evalSimpleJsVariables(jsCode: string, resultValue: string): Record<string, string> {
    const vars: Record<string, string> = { result: resultValue };
    const getStringAssignRe = /\b(?:let|var|const)?\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*java\.getString\(\s*["']([^"']+)["']\s*\)\s*;?/g;
    let getMatch: RegExpExecArray | null;
    while ((getMatch = getStringAssignRe.exec(jsCode)) !== null) {
      vars[getMatch[1]] = this.getJavaString(getMatch[2]);
    }

    const wanMatch = jsCode.match(/if\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*>\s*10000\s*\)\s*\1\s*=\s*\(Number\(\s*\1\s*\)\s*\/\s*10000\s*\)\.toFixed\(\s*(\d+)\s*\)\s*\+\s*['"]万['"]/);
    if (wanMatch) {
      const key = wanMatch[1];
      const digits = parseInt(wanMatch[2]);
      const num = Number(vars[key] || '0');
      if (num > 10000) vars[key] = `${(num / 10000).toFixed(Number.isNaN(digits) ? 2 : digits)}万`;
    }

    const timeMatch = jsCode.match(/java\.timeFormat\(\s*result\.match\((\/[\s\S]*?\/[gimsuy]*)\)\s*\[\s*(\d+)\s*\]\s*\*\s*1000\s*\)/);
    if (timeMatch) {
      const re = this.parseJsRegex(timeMatch[1]);
      const idx = parseInt(timeMatch[2]);
      const found = re ? resultValue.match(re) : null;
      const raw = found && found[idx] !== undefined ? found[idx] : '';
      vars['__timeFormatMatch'] = this.formatTimestamp(Number(raw) * 1000);
    }
    return vars;
  }

  private parseReplacePattern(raw: string): RegExp | null {
    const text = raw.trim();
    const re = this.parseJsRegex(text);
    if (re) return new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g');
    const literal = this.stripQuotes(text);
    if (!literal) return null;
    return new RegExp(this.escapeRegex(literal), 'g');
  }

  private evalReplaceArgument(raw: string, vars: Record<string, string>): string {
    let text = raw.trim();
    if (text.includes('java.timeFormat') && vars['__timeFormatMatch'] !== undefined) {
      text = text.replace(/java\.timeFormat\([\s\S]*?\)/, vars['__timeFormatMatch']);
    }
    const parts = this.splitJsConcat(text);
    if (parts.length > 1) {
      return parts.map((part: string) => this.evalReplaceArgument(part, vars)).join('');
    }
    text = this.stripQuotes(text);
    if (vars[text] !== undefined) return vars[text];
    return text;
  }

  private evalCommonLegacyJs(jsCode: string, value: string): string {
    const vars: Record<string, string> = { result: value };
    const matchAssignRe = /\b(?:var|let|const)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*result\.match\((\/[\s\S]*?\/[gimsuy]*)\)\s*\[\s*(\d+)\s*\]\s*;?/g;
    let matchAssign: RegExpExecArray | null;
    while ((matchAssign = matchAssignRe.exec(jsCode)) !== null) {
      const re = this.parseJsRegex(matchAssign[2]);
      const idx = parseInt(matchAssign[3]);
      if (re) {
        const m = value.match(re);
        vars[matchAssign[1]] = m && m[idx] !== undefined ? m[idx] : '';
      }
    }

    const parseIntRe = /\b(?:var|let|const)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*parseInt\(\s*([A-Za-z_][A-Za-z0-9_]*|\d+)\s*\/\s*(\d+)\s*\)\s*;?/g;
    let parseIntAssign: RegExpExecArray | null;
    while ((parseIntAssign = parseIntRe.exec(jsCode)) !== null) {
      const left = parseIntAssign[2];
      const raw = /^[0-9]+$/.test(left) ? left : (vars[left] || '');
      const divisor = parseInt(parseIntAssign[3]);
      const num = parseInt(raw);
      vars[parseIntAssign[1]] = divisor > 0 && !isNaN(num) ? String(Math.floor(num / divisor)) : '';
    }

    const expr = this.extractLastJsExpression(jsCode);
    if (!expr) return '';
    return this.evalSimpleConcatExpression(expr, vars);
  }

  private extractLastJsExpression(jsCode: string): string {
    const trimmed = jsCode.trim();
    const returnMatch = trimmed.match(/return\s+([\s\S]*?);?\s*$/);
    if (returnMatch) return returnMatch[1].trim();

    const parts = trimmed
      .split(';')
      .map(part => part.trim())
      .filter(part => part.length > 0);
    for (let i = parts.length - 1; i >= 0; i--) {
      const part = parts[i];
      if (!part.startsWith('var ') && !part.startsWith('let ') && !part.startsWith('const ')) {
        return part;
      }
    }
    return '';
  }

  private evalSimpleConcatExpression(expr: string, vars: Record<string, string>): string {
    const parts = this.splitJsConcat(expr);
    if (parts.length === 0) return '';
    let out = '';
    for (const part of parts) {
      const token = part.trim();
      if (!token) continue;
      if ((token.startsWith("'") && token.endsWith("'")) || (token.startsWith('"') && token.endsWith('"'))) {
        out += token.substring(1, token.length - 1);
      } else if (vars[token] !== undefined) {
        out += vars[token];
      } else if (/^\d+$/.test(token)) {
        out += token;
      } else {
        return '';
      }
    }
    return out;
  }

  private splitJsConcat(expr: string): string[] {
    const parts: string[] = [];
    let quote = '';
    let start = 0;
    for (let i = 0; i < expr.length; i++) {
      const ch = expr.charAt(i);
      if (quote) {
        if (ch === quote && expr.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === '+') {
        parts.push(expr.substring(start, i));
        start = i + 1;
      }
    }
    parts.push(expr.substring(start));
    return parts;
  }

  private parseJsRegex(literal: string): RegExp | null {
    const m = literal.match(/^\/([\s\S]*)\/([gimsuy]*)$/);
    if (!m) return null;
    try {
      return new RegExp(m[1].replace(/\\\//g, '/'), m[2].replace('g', ''));
    } catch (_) {
      return null;
    }
  }

  private evalTemplateRule(template: string): string {
    let result = template.replace(/\{\{([\s\S]*?)\}\}/g, (_: string, expr: string) => {
      const rule = expr.trim();
      const javaTime = this.evalJavaTimeFormatTemplate(rule);
      if (javaTime !== null) return javaTime;
      const sourceValue = this.evalSourceVariable(rule);
      if (sourceValue !== null) return sourceValue;
      if (rule.startsWith('@get:{')) {
        const m = rule.match(/@get:\{([^}]+)\}/);
        return m ? this.ctx.get(m[1].trim()) : '';
      }
      if ((rule.startsWith('$') || rule.startsWith('@.')) && (rule.includes('##') || rule.includes('@js:'))) {
        return this.analyzeFirst(rule);
      }
      if (rule.startsWith('$') || rule.startsWith('@.') || (this.isJsonContent() && rule.startsWith('.'))) {
        if (rule.includes('||') || rule.includes('&&') || rule.includes('%%')) return this.analyzeFirst(rule);
        const v = this.evalJsonPath(rule.startsWith('.') ? '$' + rule : rule);
        if (Array.isArray(v)) return this.jsonPathArrayToStrings(v as Object[]).join(',');
        return this.jsonValueToString(v);
      }
      if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(rule)) {
        const ctxVal = this.ctx.get(rule);
        if (ctxVal) return ctxVal;
      }
      const ctxVal = this.ctx.get(rule);
      if (ctxVal) return ctxVal;
      return this.js.evalTemplate(`{{${rule}}}`);
    });
    result = result.replace(/(^|[^{])\{(\$[.\[][^\r\n{}]+|@\.[^\r\n{}]+)\}/g, (_: string, prefix: string, expr: string) => {
      const rule = expr.trim();
      const v = this.evalJsonPath(rule.startsWith('@.') ? '$.' + rule.substring(2) : rule);
      if (Array.isArray(v)) return prefix + this.jsonPathArrayToStrings(v as Object[]).join(',');
      return prefix + this.jsonValueToString(v);
    });

    const jsIndex = result.indexOf('@js:');
    if (jsIndex > 0) {
      result = result.substring(0, jsIndex);
    }
    return result;
  }

  private evalJavaTimeFormatTemplate(rule: string): string | null {
    if (!rule.startsWith('java.timeFormat')) return null;
    const match = rule.match(/^java\.timeFormat\(\s*java\.getString\(\s*["']([^"']+)["']\s*\)\s*(?:\*\s*(\d+))?\s*\)$/);
    if (!match) return '';
    const raw = this.getJavaString(match[1]);
    const multiplier = match[2] ? Number(match[2]) : 1;
    const timestamp = Number(raw) * multiplier;
    return this.formatTimestamp(timestamp);
  }

  private getJavaString(pathOrKey: string): string {
    const data = this.parseContentObject();
    let value: Object | string | undefined = undefined;
    if (pathOrKey.startsWith('$')) {
      value = this.getByPath(data, pathOrKey);
    } else {
      value = (data as Record<string, Object>)[pathOrKey] as Object | string;
      if (value === undefined) value = this.deepFind(data, pathOrKey);
    }
    if (Array.isArray(value)) return this.jsonPathArrayToStrings(value as Object[]).join(',');
    return this.jsonValueToString(value);
  }

  private formatTimestamp(timestamp: number): string {
    if (!timestamp || Number.isNaN(timestamp)) return '';
    const millis = timestamp < 100000000000 ? timestamp * 1000 : timestamp;
    const date = new Date(millis);
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value);
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  }

  private evalSourceVariable(rule: string): string | null {
    if (rule === 'source.bookSourceUrl') return this.ctx.get('source.bookSourceUrl') || this.ctx.get('bookSourceUrl');
    if (rule === 'source.bookSourceName') return this.ctx.get('source.bookSourceName') || this.ctx.get('bookSourceName');
    if (rule === 'source.bookSourceGroup') return this.ctx.get('source.bookSourceGroup') || this.ctx.get('bookSourceGroup');
    if (rule === 'source.bookSourceComment') return this.ctx.get('source.bookSourceComment') || this.ctx.get('bookSourceComment');
    if (rule === 'source.getKey()' || rule === 'source.key') {
      return this.ctx.get('source.bookSourceUrl') || this.ctx.get('bookSourceUrl');
    }
    if (/^source\.getVariable\(\s*\)$/.test(rule)) return this.ctx.get('source.variable') || '';
    const getVariable = rule.match(/^source\.getVariable\(\s*["']([^"']+)["']\s*\)$/);
    if (getVariable) return this.ctx.get(`source.variable.${getVariable[1]}`) || this.ctx.get('source.variable') || '';
    return null;
  }

  private replaceSourceCalls(expr: string): string {
    const sourceUrl = this.ctx.get('source.bookSourceUrl') || this.ctx.get('bookSourceUrl');
    const variable = this.ctx.get('source.variable') || '';
    return expr
      .replace(/source\.getKey\(\)|source\.key/g, this.quoteJsValue(sourceUrl))
      .replace(/source\.getVariable\(\s*\)/g, this.quoteJsValue(variable));
  }

  private quoteJsValue(value: string): string {
    return `"${(value || '').replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  }

  // === 后处理 ===

  private stripProcessor(rule: string): string {
    // 先去除 @js: 后缀（如 $.path@js:java.aesBase64DecodeToString(...)）
    const jsSuf = rule.indexOf('@js:');
    let effective = rule;
    if (jsSuf > 0) {
      effective = rule.substring(0, jsSuf);
    }

    const i = effective.indexOf('##');
    if (i < 0) return effective;

    // @put: 和 @get: 标记
    if (rule.includes('@put:{') || rule.includes('@get:{')) {
      return rule; // 保留完整规则，由上层处理
    }
    return effective.substring(0, i);
  }

  private applyProcessor(value: string, rule: string): string {
    if (!value || !rule) return value;

    const jsBlock = rule.match(/<js>([\s\S]*?)<\/js>/i);
    if (jsBlock) {
      const jsValue = this.evalResultJs(jsBlock[1], value);
      if (jsValue) value = jsValue;
    }

    // 处理 @js: 后缀（AES解密等）
    const jsSuffix = rule.match(/@js:([\s\S]+)$/);
    if (jsSuffix) {
      const jsCode = jsSuffix[1].trim();
      if (jsCode.startsWith('java.aesBase64DecodeToString')) {
        value = this.applyAesDecrypt(value, jsCode);
        if (!value) return '';
      } else {
        value = this.evalResultJs(jsCode, value);
      }
    }

    const parts = this.splitReplacementRule(rule);
    if (parts.length < 2) return value;

    try {
      if (parts.length >= 3) {
        return value.replace(new RegExp(parts[1], 'g'), parts[2]);
      }
      return value.replace(new RegExp(parts[1], 'g'), '');
    } catch (_) {
      return value;
    }
  }

  private splitReplacementRule(rule: string): string[] {
    const parts: string[] = [];
    let start = 0;
    for (let i = 0; i < rule.length - 1; i++) {
      if (rule.charAt(i) === '#' && rule.charAt(i + 1) === '#' && rule.charAt(i - 1) !== '\\') {
        parts.push(rule.substring(start, i).replace(/\\##/g, '##'));
        start = i + 2;
        i++;
      }
    }
    parts.push(rule.substring(start).replace(/\\##/g, '##'));
    return parts;
  }

  private applyAesDecrypt(value: string, jsCode: string): string {
    // 解析 java.aesBase64DecodeToString(result, "key", "iv")
    const m = jsCode.match(/java\.aesBase64DecodeToString\(([^)]+)\)/);
    if (!m) return value;
    const args = this.splitArgs(m[1]);
    // args[0] 通常是 result（已由 value 提供），args[1] 是 key，args[2] 是 iv
    if (args.length >= 2) {
      const key = this.stripQuotes(args[1]);
      const transformation = args.length >= 4 ? this.stripQuotes(args[2]) : 'AES/CBC/PKCS5Padding';
      const iv = args.length >= 4 ? this.stripQuotes(args[3]) : (args.length >= 3 ? this.stripQuotes(args[2]) : '');
      return this.js.aesBase64DecodeToString(value, key, iv, transformation);
    }
    return value;
  }

  private splitArgs(args: string): string[] {
    const result: string[] = [];
    let depth = 0;
    let quote = '';
    let start = 0;
    for (let i = 0; i < args.length; i++) {
      const ch = args.charAt(i);
      if (quote) {
        if (ch === quote && args.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '(') depth++;
      if (ch === ')') depth--;
      if (ch === ',' && depth === 0) {
        result.push(args.substring(start, i).trim());
        start = i + 1;
      }
    }
    result.push(args.substring(start).trim());
    return result;
  }

  private stripQuotes(s: string): string {
    const t = s.trim();
    if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  private findMatchingParen(text: string, openIndex: number): number {
    let depth = 0;
    let quote = '';
    for (let i = openIndex; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '(') depth++;
      if (ch === ')') { depth--; if (depth === 0) return i; }
    }
    return -1;
  }

  private stripHtml(html: string): string {
    return html
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n\n')
      .replace(/<\/div>/gi, '\n')
      .replace(/<\/li>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private extractOwnText(html: string): string {
    const inner = html.replace(/^<[^>]+>/, '').replace(/<\/[^>]+>\s*$/, '');
    return this.decodeHtmlEntities(inner.replace(/<[^>]+>[\s\S]*?<\/[^>]+>/g, ' ').replace(/<[^>]+>/g, ' '))
      .replace(/\s+/g, ' ').trim();
  }

  private extractTextNodes(html: string): string {
    const inner = html.replace(/^<[^>]+>/, '').replace(/<\/[^>]+>\s*$/, '');
    return inner.split(/<[^>]+>/).map(item => this.decodeHtmlEntities(item).trim())
      .filter(item => item.length > 0).join('\n');
  }

  private decodeHtmlEntities(text: string): string {
    return text
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;|&apos;/gi, "'")
      .replace(/&#(\d+);/g, (_: string, value: string) => String.fromCharCode(parseInt(value)))
      .replace(/&#x([0-9a-f]+);/gi, (_: string, value: string) => String.fromCharCode(parseInt(value, 16)));
  }

  private resolveUrl(url: string): string {
    if (!url || url.startsWith('http')) return url;
    if (/^\/\/[A-Za-z0-9.-]+(?::\d+)?(?:[/?#]|$)/.test(url)) return 'https:' + url;
    if (url.startsWith('/')) {
      const m = this.baseUrl.match(/^(https?:\/\/[^/]+)/);
      return m ? m[0] + url : this.baseUrl + url;
    }
    const b = this.baseUrl.endsWith('/') ? this.baseUrl.substring(0, this.baseUrl.length - 1) : this.baseUrl;
    return b + '/' + url;
  }
}
