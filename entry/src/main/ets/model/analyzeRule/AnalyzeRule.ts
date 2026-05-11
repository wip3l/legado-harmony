import { Book, BookSource } from '../data/Book';
import { httpHelper } from '../http/HttpHelper';
import { LegadoCrypto } from '../js/JsEngine';

export class AnalyzeRule {
  private source: string = '';
  private content: string = '';
  private baseUrl: string = '';
  private bookSource: BookSource | null = null;
  private book: Book | null = null;
  private variableMap: Record<string, string> = {};

  constructor(source: string = '', content: string = '', baseUrl: string = '',
    bookSource?: BookSource | null, book?: Book | null) {
    this.source = source;
    this.content = content;
    this.baseUrl = baseUrl;
    this.bookSource = bookSource || null;
    this.book = book || null;
    // 从 Book 加载已有变量
    if (book) {
      this.variableMap = { ...book.variableMap };
    }
  }

  getVariable(key: string): string {
    return this.variableMap[key] || this.book?.getVariable(key) || '';
  }

  putVariable(key: string, value: string): void {
    this.variableMap[key] = value;
    if (this.book) {
      this.book.putVariable(key, value);
    }
  }

  analyze(rule: string): string[] {
    if (!rule || rule.length === 0) return [];

    // 先提取 @put:{...} 
    rule = this.extractPutRule(rule);

    const rules = this.splitRules(rule);

    for (const r of rules) {
      // 替换 @get:{key} 
      const resolvedRule = this.resolveGetRule(r);
      const results = this.analyzeSingleList(resolvedRule);
      if (results.length > 0) {
        return results;
      }
    }

    return [];
  }

  private extractPutRule(rule: string): string {
    const putRegex = /@put:\{([^}]+)\}/gi;
    let match: RegExpExecArray | null;
    while ((match = putRegex.exec(rule)) !== null) {
      const putContent = match[1];
      rule = rule.replace(match[0], '');
      try {
        const putObj = JSON.parse(`{${putContent}}`) as Record<string, string>;
        for (const key in putObj) {
          const value = putObj[key];
          const resolvedValue = this.resolveGetRule(value);
          const actualValue = this.analyzeFirst(resolvedValue) || resolvedValue;
          this.putVariable(key, actualValue);
        }
      } catch (e) {
        // 尝试非JSON格式: key:value
        const parts = putContent.split(/\s*,\s*/);
        for (const part of parts) {
          const [key, ...valParts] = part.split(':');
          if (key && valParts.length > 0) {
            const value = valParts.join(':').trim();
            const resolvedValue = this.resolveGetRule(value);
            const actualValue = this.analyzeFirst(resolvedValue) || resolvedValue;
            this.putVariable(key.trim(), actualValue);
          }
        }
      }
    }
    return rule;
  }

  private resolveGetRule(rule: string): string {
    const getRegex = /@get:\{([^}]+)\}/gi;
    return rule.replace(getRegex, (_: string, key: string) => {
      return this.getVariable(key);
    });
  }

  analyzeFirst(rule: string): string {
    const results = this.analyze(rule);
    return results.length > 0 ? results[0] : '';
  }

  private analyzeSingleList(rule: string): string[] {
    const cleanRule = this.extractEffectiveRule(rule);
    if (!cleanRule) return [];

    if (cleanRule.includes('{{') && cleanRule.includes('}}')) {
      const value = this.applyTemplate(cleanRule);
      return value ? [value] : [];
    }

    if (this.isJsonRule(cleanRule)) {
      const value = this.analyzeJsonValue(cleanRule);
      if (Array.isArray(value)) {
        return (value as Object[]).map((item: Object) => {
          if (item !== null && typeof item === 'object') {
            return JSON.stringify(item);
          }
          return this.applyProcessor(String(item), cleanRule);
        });
      }
      if (value !== undefined && value !== null) {
        const text = typeof value === 'object' ? JSON.stringify(value) : String(value);
        return [this.applyProcessor(text, cleanRule)];
      }
      return [];
    }

    const result = this.analyzeSingle(cleanRule);
    return result ? [result] : [];
  }

  private analyzeSingle(rule: string): string {
    if (!rule || rule.length === 0) return '';

    // 检查 @js: 后缀: 先执行基础规则，再执行JS
    const jsSuffixIdx = rule.indexOf('@js:');
    if (jsSuffixIdx >= 0) {
      const baseRule = rule.substring(0, jsSuffixIdx).trim();
      const jsCode = rule.substring(jsSuffixIdx + 4);
      let baseResult = this.content;
      if (baseRule && baseRule !== '') {
        baseResult = this.analyzeSingleInner(baseRule);
      }
      return this.executeJsSync(baseResult, jsCode);
    }

    // 检查 <js> 前缀
    if (rule.startsWith('<js>') && rule.endsWith('</js>')) {
      return this.executeJsSync(this.content, rule.substring(4, rule.length - 5));
    }

    return this.analyzeSingleInner(rule);
  }

  private analyzeSingleInner(rule: string): string {
    rule = this.extractEffectiveRule(rule);
    if (!rule) return '';

    if (rule.includes('{{') && rule.includes('}}')) {
      return this.applyTemplate(rule);
    }

    if (rule.startsWith('@CSS:') || rule.startsWith('@css:')) {
      return this.analyzeByJSoup(rule.substring(5));
    }

    if (rule.startsWith('@XPath:') || rule.startsWith('@xpath:')) {
      return this.analyzeByXPath(rule.substring(7));
    }

    if (this.isJsonRule(rule)) {
      const value = this.analyzeJsonValue(rule);
      if (value === undefined || value === null) return '';
      return typeof value === 'object' ? JSON.stringify(value) : String(value);
    }

    if (rule.startsWith('%')) {
      return this.analyzeByRegex(rule.substring(1));
    }

    if (rule === 'text' || rule === 'html') {
      return this.content;
    }

    return this.analyzeByJSoup(rule);
  }

  private executeJsSync(result: string, jsCode: string): string {
    try {
      let code = jsCode.trim();

      // 处理 eval(String(source.bookSourceComment)) 模式
      if (code.includes('eval(String(source.bookSourceComment))') && this.bookSource?.bookSourceComment) {
        code = this.bookSource.bookSourceComment;
      }

      // 处理 result = decode(result)
      if (code.includes('result = decode(result)')) {
        return result; // 实际解密需要 crypto 模块
      }

      // 处理 decode(result) 简单替换
      const decodeMatch = code.match(/decode\(([^)]+)\)/);
      if (decodeMatch) {
        return result;
      }

      // 处理 result.match(...)
      const matchMatch = code.match(/result\.match\(([^)]+)\)/);
      if (matchMatch) {
        let pattern = matchMatch[1].trim();
        if (pattern.startsWith('/') && pattern.endsWith('/')) {
          pattern = pattern.substring(1, pattern.length - 1);
        } else {
          pattern = pattern.replace(/^['"]|['"]$/g, '');
        }
        try {
          const m = result.match(new RegExp(pattern));
          return m ? m[0] : '';
        } catch (e) {
          return result;
        }
      }

      // 处理 result.replace(...)
      const replaceMatch = code.match(/result\.replace\(([^,]+),\s*([^)]+)\)/);
      if (replaceMatch) {
        let pattern = replaceMatch[1].trim();
        let replacement = replaceMatch[2].trim();
        if (pattern.startsWith('/') && pattern.endsWith('/')) {
          pattern = pattern.substring(1, pattern.length - 1);
        } else {
          pattern = pattern.replace(/^['"]|['"]$/g, '');
        }
        replacement = replacement.replace(/^['"]|['"]$/g, '');
        try {
          return result.replace(new RegExp(pattern, 'g'), replacement);
        } catch (e) {
          return result;
        }
      }

      return result;
    } catch (e) {
      console.error('同步JS执行失败:', e);
      return result;
    }
  }

  private analyzeByJSoup(selector: string): string {
    try {
      return this.parseHtmlBySelector(this.content, selector);
    } catch (e) {
      return '';
    }
  }

  private parseHtmlBySelector(html: string, selector: string): string {
    if (!html || !selector) return '';

    selector = selector.trim();

    // 处理 @text / @html 后缀
    let extractAttr = '';
    if (selector.endsWith('@text')) {
      selector = selector.substring(0, selector.length - 5).trim();
      extractAttr = 'text';
    } else if (selector.endsWith('@html') || selector.endsWith('@raw')) {
      selector = selector.substring(0, selector.length - 5).trim();
      extractAttr = 'html';
    } else if (selector.includes('@')) {
      const atIdx = selector.lastIndexOf('@');
      const suffix = selector.substring(atIdx + 1);
      if (suffix !== 'css' && suffix !== 'xpath' && suffix !== 'js') {
        extractAttr = suffix;
        selector = selector.substring(0, atIdx).trim();
      }
    }

    let matchedHtml = html;
    const rules = selector.split(/\s*>\s*/);

    for (const rule of rules) {
      const subMatches = this.matchHtmlElements(matchedHtml, rule.trim());
      if (subMatches.length === 0) return '';
      // 合并所有匹配结果
      matchedHtml = subMatches.join('');
    }

    if (extractAttr === 'text') {
      return this.stripHtmlTags(matchedHtml);
    } else if (extractAttr === 'html') {
      return matchedHtml;
    } else if (extractAttr) {
      return this.extractAttribute(matchedHtml, extractAttr);
    }

    return this.stripHtmlTags(matchedHtml);
  }

  private matchHtmlElements(html: string, simpleSelector: string): string[] {
    const results: string[] = [];

    if (simpleSelector === 'html' || simpleSelector === '*') {
      results.push(html);
      return results;
    }

    // 解析选择器: tag.class1.class2#id
    let tagName = '';
    let className = '';
    let idName = '';

    const idIndex = simpleSelector.indexOf('#');
    if (idIndex >= 0) {
      const afterId = simpleSelector.substring(idIndex + 1);
      const dotAfterId = afterId.indexOf('.');
      if (dotAfterId >= 0) {
        idName = afterId.substring(0, dotAfterId);
        simpleSelector = simpleSelector.substring(0, idIndex) + afterId.substring(dotAfterId);
      } else {
        idName = afterId;
        simpleSelector = simpleSelector.substring(0, idIndex);
      }
    }

    const parts = simpleSelector.split('.');
    if (parts.length > 0) {
      tagName = parts[0];
      for (let i = 1; i < parts.length; i++) {
        if (parts[i].startsWith('#')) {
          idName = parts[i].substring(1);
        } else {
          className = parts[i];
        }
      }
    }

    if (!tagName && className) {
      tagName = '[a-zA-Z][a-zA-Z0-9]*';
    }

    const tagPattern = tagName ? `<${tagName}\\b` : '<\\w+\\b';
    const classPattern = className ? `class=["'][^"']*\\b${className}\\b[^"']*["']` : '';
    const idPattern = idName ? `id=["']${idName}["']` : '';

    let regexStr = `${tagPattern}[^>]*`;
    if (classPattern) regexStr += `(?:${classPattern})?[^>]*`;
    if (idPattern) regexStr += `(?:${idPattern})?`;
    regexStr += `>([\\s\\S]*?)<\\/${tagName || '\\w+'}>`;

    try {
      const regex = new RegExp(regexStr, 'gi');
      let match: RegExpExecArray | null;
      while ((match = regex.exec(html)) !== null) {
        results.push(match[1] || match[0]);
      }
    } catch (e) {
      // 回退：匹配单个标签内容
      const fallbackRegex = new RegExp(`<${tagName || '\\w+'}[^>]*>([\\s\\S]*?)<\\/${tagName || '\\w+'}>`, 'gi');
      let match: RegExpExecArray | null;
      while ((match = fallbackRegex.exec(html)) !== null) {
        results.push(match[1] || match[0]);
      }
    }

    return results;
  }

  private stripHtmlTags(html: string): string {
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
      .replace(/&#39;/g, "'")
      .replace(/\n\s*\n\s*\n/g, '\n\n')
      .trim();
  }

  private extractAttribute(html: string, attr: string): string {
    const regex = new RegExp(`${attr}=["']([^"']*)["']`, 'i');
    const match = html.match(regex);
    return match ? match[1] : '';
  }

  private analyzeByXPath(xpath: string): string {
    try {
      return '';
    } catch (e) {
      return '';
    }
  }

  private analyzeJsonValue(jsonPath: string): Object | string | number | boolean | null | undefined {
    try {
      const data = JSON.parse(this.content) as Object;
      return this.evaluateJsonPath(data, this.stripProcessor(jsonPath));
    } catch (e) {
      return undefined;
    }
  }

  private analyzeByJsonPath(jsonPath: string): string {
    const value = this.analyzeJsonValue(jsonPath);
    return value === undefined || value === null ? '' : String(value);
  }

  private evaluateJsonPath(data: Object, path: string): Object | string | number | boolean | null | undefined {
    if (!data || !path) return undefined;

    path = path.trim();
    if (path.startsWith('$..')) {
      return this.findDeepValue(data, path.substring(3));
    }
    if (path.startsWith('@.')) {
      path = path.substring(2);
    } else if (path.startsWith('$.')) {
      path = path.substring(2);
    } else if (path.startsWith('$')) {
      path = path.substring(1);
    }
    if (path.startsWith('.')) {
      path = path.substring(1);
    }
    if (!path) return data;

    const parts = path.split('.');
    let current: Object | string | number | boolean | null | undefined = data;

    for (const rawPart of parts) {
      if (current === undefined || current === null) {
        return undefined;
      }

      let part = rawPart;
      let arrayAll = false;
      let arrayIndex = -1;

      if (part.endsWith('[*]')) {
        arrayAll = true;
        part = part.substring(0, part.length - 3);
      } else if (part.includes('[') && part.endsWith(']')) {
        const bracketIndex = part.indexOf('[');
        const indexText = part.substring(bracketIndex + 1, part.length - 1);
        arrayIndex = parseInt(indexText);
        part = part.substring(0, bracketIndex);
      }

      if (part) {
        current = (current as Record<string, Object>)[part];
      }

      if (arrayAll) {
        return current;
      }

      if (arrayIndex >= 0) {
        current = Array.isArray(current) ? (current as Object[])[arrayIndex] : undefined;
      }
    }

    return current;
  }

  private findDeepValue(root: Object | string | number | boolean | null | undefined, path: string): Object | string | number | boolean | null | undefined {
    if (root === undefined || root === null || !path) return undefined;

    if (typeof root === 'object') {
      const direct = this.evaluateJsonPath(root as Object, path);
      if (direct !== undefined) {
        return direct;
      }
    }

    if (Array.isArray(root)) {
      for (const item of root as Object[]) {
        const value = this.findDeepValue(item, path);
        if (value !== undefined) {
          return value;
        }
      }
      return undefined;
    }

    if (typeof root === 'object') {
      const obj = root as Record<string, Object>;
      for (const key in obj) {
        const value = this.findDeepValue(obj[key], path);
        if (value !== undefined) {
          return value;
        }
      }
    }

    return undefined;
  }

  private analyzeByRegex(regex: string): string {
    try {
      const match = this.content.match(regex);
      return match ? match[0] : '';
    } catch (e) {
      return '';
    }
  }

  private analyzeByJS(js: string): string {
    try {
      const resultMatch = js.match(/result\s*=\s*([^;]+)/);
      if (resultMatch) {
        return resultMatch[1].replace(/^['"]|['"]$/g, '');
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  private isJsonRule(rule: string): boolean {
    if (rule.startsWith('$.') || rule.startsWith('$[') || rule.startsWith('@.')) return true;

    try {
      const data = JSON.parse(this.content) as Object;
      if (!data || typeof data !== 'object') return false;
      const cleanRule = this.stripProcessor(rule).trim();
      if (cleanRule.includes(' ') || cleanRule.includes('@') || cleanRule.startsWith('.') || cleanRule.startsWith('#')) {
        return false;
      }
      const rootKey = cleanRule.split('.')[0].split('[')[0];
      return !!rootKey && (data as Record<string, Object>)[rootKey] !== undefined;
    } catch (e) {
      return false;
    }
  }

  private extractEffectiveRule(rule: string): string {
    if (!rule) return '';

    let result = rule.trim();
    if (result.includes('\n')) {
      const lines = result.split('\n')
        .map((line: string) => line.trim())
        .filter((line: string) => line && !line.startsWith('<js>') && !line.startsWith('</js>') && !line.startsWith('@js:'));
      if (lines.length > 0) {
        result = lines[lines.length - 1];
      }
    }

    if (result.startsWith('<js>') && result.endsWith('</js>')) {
      return '';
    }

    const jsIndex = result.indexOf('@js:');
    if (jsIndex >= 0) {
      result = result.substring(0, jsIndex);
    }

    return result.trim();
  }

  private applyTemplate(template: string): string {
    let result = template;
    const matches = template.match(/\{\{[^}]+\}\}/g) || [];
    for (const match of matches) {
      const rule = match.substring(2, match.length - 2);
      const value = this.analyzeJsonValue(rule);
      result = result.replace(match, value === undefined || value === null ? '' : String(value));
    }
    return this.applyProcessor(result, template);
  }

  private stripProcessor(rule: string): string {
    const processorIndex = rule.indexOf('##');
    return processorIndex >= 0 ? rule.substring(0, processorIndex) : rule;
  }

  private applyProcessor(value: string, rule: string): string {
    const parts = rule.split('##');
    if (parts.length < 2) return value;

    try {
      if (parts.length >= 3) {
        return value.replace(new RegExp(parts[1], 'g'), parts[2]);
      }
      return value.replace(new RegExp(parts[1], 'g'), '');
    } catch (e) {
      return value;
    }
  }

  private splitRules(rule: string): string[] {
    const rules: string[] = [];
    let current = '';
    let depth = 0;
    let inString = false;
    let stringChar = '';

    for (let i = 0; i < rule.length; i++) {
      const char = rule[i];

      if (inString) {
        current += char;
        if (char === stringChar) {
          inString = false;
        }
        continue;
      }

      if (char === '"' || char === "'") {
        inString = true;
        stringChar = char;
        current += char;
        continue;
      }

      if (char === '(' || char === '[' || char === '{') {
        depth++;
        current += char;
        continue;
      }

      if (char === ')' || char === ']' || char === '}') {
        depth--;
        current += char;
        continue;
      }

      if ((char === '|' || char === '\n') && depth === 0) {
        if (current.length > 0) {
          rules.push(current.trim());
        }
        current = '';
        continue;
      }

      current += char;
    }

    if (current.length > 0) {
      rules.push(current.trim());
    }

    return rules;
  }

  analyzeList(ruleList: string[]): string[] {
    if (!ruleList || ruleList.length === 0) return [];

    const results: string[] = [];
    for (const rule of ruleList) {
      const result = this.analyze(rule);
      results.push(...result);
    }

    return results;
  }

  analyzeFirstList(ruleList: string[]): string {
    if (!ruleList || ruleList.length === 0) return '';

    for (const rule of ruleList) {
      const result = this.analyzeFirst(rule);
      if (result && result.length > 0) {
        return result;
      }
    }

    return '';
  }

  analyzeMap(ruleMap: Record<string, string>): Record<string, string> {
    if (!ruleMap) return {};

    const result: Record<string, string> = {};
    for (const key in ruleMap) {
      result[key] = this.analyzeFirst(ruleMap[key]);
    }

    return result;
  }

  analyzeMapList(ruleMap: Record<string, string>): Record<string, string[]> {
    if (!ruleMap) return {};

    const result: Record<string, string[]> = {};
    for (const key in ruleMap) {
      result[key] = this.analyze(ruleMap[key]);
    }

    return result;
  }
}

export class AnalyzeUrl {
  private url: string = '';
  private headers: Record<string, string> = {};
  private body: string = '';
  private method: string = 'GET';
  private book: Book | null = null;
  private source: BookSource | null = null;

  constructor(url: string, book?: Book, source?: BookSource) {
    this.url = url;
    this.book = book || null;
    this.source = source || null;
    this.parseUrl();
  }

  private parseUrl(): void {
    if (!this.url) return;

    const option = this.extractUrlOption(this.url);
    this.url = option.url;
    this.method = option.method;
    this.body = option.body;
    this.headers = option.headers;

    if (this.url.includes('@Header:')) {
      const headerStart = this.url.indexOf('@Header:');
      const headerEnd = this.url.indexOf('@End', headerStart);
      if (headerEnd > headerStart) {
        const headerStr = this.url.substring(headerStart + 8, headerEnd);
        this.parseHeaders(headerStr);
        this.url = this.url.substring(0, headerStart) + this.url.substring(headerEnd + 4);
      }
    }

    if (this.url.startsWith('@')) {
      this.method = 'POST';
      this.url = this.url.substring(1);
      const questionIndex = this.url.indexOf('?');
      if (questionIndex >= 0) {
        this.body = this.url.substring(questionIndex + 1);
        this.url = this.url.substring(0, questionIndex);
      }
    }

    if (this.source) {
      this.url = this.resolveUrl(this.url, this.source.bookSourceUrl);
    } else if (this.book) {
      this.url = this.resolveUrl(this.url, this.book.origin);
    }
  }

  private parseHeaders(headerStr: string): void {
    const lines = headerStr.split('\n');
    for (const line of lines) {
      const colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        const key = line.substring(0, colonIndex).trim();
        const value = line.substring(colonIndex + 1).trim();
        this.headers[key] = value;
      }
    }
  }

  getUrl(): string {
    return this.url;
  }

  getHeaders(): Record<string, string> {
    return this.headers;
  }

  getBody(): string {
    return this.body;
  }

  getMethod(): string {
    return this.method;
  }

  async fetch(): Promise<string> {
    if (!this.url) {
      console.warn('[AnalyzeUrl] URL为空');
      return '';
    }

    console.log('[AnalyzeUrl] 请求:', this.method, this.url);

    const sourceHeaders = this.source ? this.parseSourceHeaders(this.source.header) : {};
    if (this.source?.header) {
      console.log('[AnalyzeUrl] 原始书源头:', this.source.header);
    }
    console.log('[AnalyzeUrl] 解析后头:', JSON.stringify(sourceHeaders));
    const headers: Record<string, string> = { ...sourceHeaders, ...this.headers };
    console.log('[AnalyzeUrl] 最终头:', JSON.stringify(headers));
    if (this.method === 'POST' && this.body && !headers['Content-Type']) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }

    const response = this.method === 'POST'
      ? await httpHelper.post(this.url, this.body, headers)
      : await httpHelper.get(this.url, headers);

    console.log('[AnalyzeUrl] 响应:', response.statusCode, '长度:', response.body.length);
    if (response.body.length < 500) {
      console.log('[AnalyzeUrl] 响应内容:', response.body);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    return '';
  }

  private async executeInitJs(initRule: string, body: string): Promise<string> {
    try {
      // 提取 @js: 后的代码
      let jsCode = initRule;
      if (jsCode.startsWith('@js:')) {
        jsCode = jsCode.substring(4);
      }

      // 处理 eval(String(source.bookSourceComment)) 模式
      if (jsCode.includes('eval(String(source.bookSourceComment))') && this.source?.bookSourceComment) {
        jsCode = this.source.bookSourceComment;
      }

      // 提取 function 定义
      const funcRegex = /function\s+(\w+)\s*\(([^)]*)\)\s*\{([\s\S]*?)\n\s*\}/g;
      const functions: Record<string, { args: string, body: string }> = {};
      let match: RegExpExecArray | null;
      while ((match = funcRegex.exec(jsCode)) !== null) {
        functions[match[1]] = { args: match[2] || '', body: match[3] || '' };
      }

      // 查找 JSON.parse 和 decode 调用
      if (jsCode.includes('JSON.parse(result)')) {
        // 查找 decode 函数
        const decodeFunc = functions['decode'];
        if (decodeFunc) {
          return await this.runDecodeJs(body, decodeFunc.body, decodeFunc.args);
        }
      }

      return body;
    } catch (e) {
      console.error('执行init JS失败:', e);
      return body;
    }
  }

  private async runDecodeJs(body: string, decodeBody: string, decodeArgs: string): Promise<string> {
    try {
      const keyMatch = decodeBody.match(/SecretKeySpec\s*\(\s*String\s*\(\s*"([^"]+)"\s*\)/);
      const ivMatch = decodeBody.match(/IvParameterSpec\s*\(\s*String\s*\(\s*"([^"]+)"\s*\)/);

      if (keyMatch && ivMatch) {
        try {
          const data = JSON.parse(body) as Record<string, Object>;

          // 查找需要解密的字段（值匹配 Base64 格式）
          const fieldsToDecrypt: Array<{ obj: Record<string, Object>, field: string }> = [];
          const findBase64Fields = (obj: Record<string, Object>, parent: Record<string, Object> | null, fieldName: string | null): void => {
            for (const key in obj) {
              const value = obj[key];
              if (typeof value === 'string') {
                const cleaned = String(value).replace(/\{\{/g, '').replace(/\}\}/g, '');
                if (cleaned.match(/^[A-Za-z0-9+/=]{20,}$/)) {
                  fieldsToDecrypt.push({ obj: obj, field: key });
                }
              } else if (typeof value === 'object' && value !== null) {
                findBase64Fields(value as Record<string, Object>, obj, key);
              }
            }
          };

          findBase64Fields(data, null, null);

          for (const { obj, field } of fieldsToDecrypt) {
            const cleaned = String(obj[field]).replace(/\{\{/g, '').replace(/\}\}/g, '');
            const decrypted = await LegadoCrypto.desedeDecrypt(keyMatch[1], ivMatch[1], cleaned);
            if (decrypted && decrypted.length > 0) {
              obj[field] = decrypted;
              console.log(`DESede解密字段 "${field}" 成功`);
            }
          }

          return JSON.stringify(data);
        } catch (e) {
          console.error('DESede解密JSON字段失败:', e);
          return body;
        }
      }

      return body;
    } catch (e) {
      console.error('runDecodeJs失败:', e);
      return body;
    }
  }

  private extractUrlOption(url: string): { url: string, method: string, body: string, headers: Record<string, string> } {
    const request = {
      url: url,
      method: 'GET',
      body: '',
      headers: {} as Record<string, string>
    };

    const optionIndex = url.indexOf(",{");
    if (optionIndex < 0) {
      return request;
    }

    request.url = url.substring(0, optionIndex);
    const optionText = url.substring(optionIndex + 1).replace(/'/g, '"');
    try {
      const option = JSON.parse(optionText) as Record<string, Object>;
      if (option['method'] !== undefined && option['method'] !== null) {
        request.method = String(option['method']).toUpperCase();
      }
      if (option['body'] !== undefined && option['body'] !== null) {
        request.body = String(option['body']);
      }
      if (option['headers'] && typeof option['headers'] === 'object') {
        request.headers = option['headers'] as Record<string, string>;
      }
    } catch (e) {
      console.error('解析URL选项失败:', e);
    }
    return request;
  }

  private parseSourceHeaders(headerStr: string): Record<string, string> {
    const headers: Record<string, string> = {};
    if (!headerStr) return headers;

    // 先尝试直接 JSON 解析
    try {
      const parsed = JSON.parse(headerStr) as Record<string, string>;
      return parsed;
    } catch (e) {
      // 尝试替换单引号为双引号后解析
      try {
        const fixed = headerStr.replace(/'/g, '"');
        const parsed = JSON.parse(fixed) as Record<string, string>;
        return parsed;
      } catch (e2) {
        // 非 JSON 格式，尝试 key:value 逐行解析
        const lines = headerStr.split(/[\n\r]+/);
        for (const line of lines) {
          const colonIndex = line.indexOf(':');
          if (colonIndex > 0) {
            const key = line.substring(0, colonIndex).trim();
            const value = line.substring(colonIndex + 1).trim();
            headers[key] = value;
          }
        }
      }
    }
    return headers;
  }

  private resolveUrl(url: string, baseUrl: string): string {
    baseUrl = this.cleanBaseUrl(baseUrl);
    if (!url || url.startsWith('http') || url.startsWith('data:')) return url;
    if (url.startsWith('//')) return `https:${url}`;
    if (url.startsWith('/')) {
      const match = baseUrl.match(/^(https?:\/\/[^/]+)/);
      return match ? `${match[1]}${url}` : `${baseUrl}${url}`;
    }
    const cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return `${cleanBase}/${url}`;
  }

  private cleanBaseUrl(baseUrl: string): string {
    const commentIndex = baseUrl.indexOf('##');
    return commentIndex >= 0 ? baseUrl.substring(0, commentIndex) : baseUrl;
  }
}

export class AnalyzeByJSoup {
  private content: string = '';

  constructor(content: string) {
    this.content = content;
  }

  parse(selector: string): string[] {
    return [];
  }

  parseFirst(selector: string): string {
    const results = this.parse(selector);
    return results.length > 0 ? results[0] : '';
  }
}

export class AnalyzeByXPath {
  private content: string = '';

  constructor(content: string) {
    this.content = content;
  }

  parse(xpath: string): string[] {
    return [];
  }

  parseFirst(xpath: string): string {
    const results = this.parse(xpath);
    return results.length > 0 ? results[0] : '';
  }
}

export class AnalyzeByJsonPath {
  private content: string = '';

  constructor(content: string) {
    this.content = content;
  }

  parse(jsonPath: string): string[] {
    try {
      const data: Record<string, Object> = JSON.parse(this.content);
      return this.evaluateJsonPath(data, jsonPath);
    } catch (e) {
      return [];
    }
  }

  private evaluateJsonPath(data: Record<string, Object>, path: string): string[] {
    if (!data || !path) return [];

    const results: string[] = [];
    const parts = path.split('.');
    let current: Object = data;

    for (const part of parts) {
      if (part === '$') continue;

      if (part.includes('[') && part.includes(']')) {
        const [key, index] = part.split('[');
        if (key) {
          current = (current as Record<string, Object>)[key];
        }
        if (index && current) {
          const idx = parseInt(index.replace(']', ''));
          current = (current as Object[])[idx];
        }
      } else {
        current = (current as Record<string, Object>)[part];
      }

      if (current === undefined || current === null) {
        return results;
      }
    }

    if (Array.isArray(current)) {
      for (const item of current) {
        results.push(String(item));
      }
    } else {
      results.push(String(current));
    }

    return results;
  }

  parseFirst(jsonPath: string): string {
    const results = this.parse(jsonPath);
    return results.length > 0 ? results[0] : '';
  }
}

export class AnalyzeByRegex {
  private content: string = '';

  constructor(content: string) {
    this.content = content;
  }

  parse(regex: string): string[] {
    try {
      const matches = this.content.match(new RegExp(regex, 'g'));
      return matches || [];
    } catch (e) {
      return [];
    }
  }

  parseFirst(regex: string): string {
    const results = this.parse(regex);
    return results.length > 0 ? results[0] : '';
  }
}
