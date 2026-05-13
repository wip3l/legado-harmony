import { JsRuntime } from './JsRuntime';
import { RuleContext } from './RuleContext';
import { VerificationSupport } from '../http/VerificationSupport';

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
    // 防止超大内容进入正则
    if (this.content.length > 500000) return [];
    const items = this.analyze(rule);
    return items.length > 0 ? items : [this.content];
  }

  // === 核心解析 ===

  analyze(rule: string): string[] {
    if (!rule) return [];
    const effective = this.stripProcessor(rule);
    if (!effective) return [];

    if (effective.includes('||')) {
      const parts = effective.split('||').map(part => part.trim()).filter(part => part.length > 0);
      for (const part of parts) {
        const values = this.analyze(part);
        if (values.length > 0) return values;
      }
      return [];
    }

    if (effective.includes('&&')) {
      const values: string[] = [];
      const parts = effective.split('&&').map(part => part.trim()).filter(part => part.length > 0);
      for (const part of parts) {
        values.push(...this.analyze(part));
      }
      return values;
    }

    // 模板规则优先处理，避免 /book/{{$.id}} 被误当 CSS
    if (effective.includes('{{')) {
      return [this.evalTemplateRule(effective)];
    }

    if (/^\$\d+$/.test(effective)) {
      const jsonV = this.evalJsonPath(effective);
      if (jsonV !== undefined && jsonV !== null) return [String(jsonV)];
    }

    const xpathV = this.evalXPathBasic(effective);
    if (xpathV.length > 0) return xpathV;

    const legacyV = this.evalLegacyRule(effective);
    if (legacyV.length > 0) return legacyV;

    // JSONPath
    const jsonV = this.evalJsonPath(effective);
    if (Array.isArray(jsonV)) return (jsonV as Object[]).map(v => typeof v === 'string' ? v as string : JSON.stringify(v));
    if (jsonV !== undefined && jsonV !== null) return [String(jsonV)];

    // CSS 选择器
    const cssV = this.evalCss(effective);
    if (cssV.length > 0) return cssV;

    // Regex
    if (effective.startsWith('%')) {
      const m = this.content.match(effective.substring(1));
      return m ? [m[0]] : [];
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

    // 处理 @put:{key:value} - 存储变量（value 为 JSONPath 或字段名）
    const putMatch = rule.match(/@put:\{([^}]+)\}/);
    if (putMatch) {
      const putStr = putMatch[1];
      const parts = putStr.split(/[,;]/);
      for (const part of parts) {
        const kv = part.split(':');
        if (kv.length >= 2) {
          const k = kv[0].trim();
          const rawV = kv.slice(1).join(':').trim();
          // 解析 value：如果是 $..xxx 或 $.xxx，从 content JSON 中取实际值
          let v = rawV;
          if (rawV.startsWith('$..') || rawV.startsWith('$.')) {
            try {
              const data = JSON.parse(this.content) as Record<string, Object>;
              if (rawV.startsWith('$..')) {
                const found = this.deepFind(data as Object, rawV.substring(3));
                if (found !== undefined) v = String(found);
              } else {
                const key = rawV.substring(2);
                const found = (data as Record<string, Object>)[key];
                if (found !== undefined) v = String(found);
              }
            } catch (_) {}
          }
          this.ctx.put(k, v);
        }
      }
      // 继续解析去除 @put: 后的规则
      rule = rule.replace(putMatch[0], '').trim();
      if (!rule) return '';
    }

    // 处理 @get:{key} 替换
    rule = rule.replace(/@get:\{(\w+)\}/g, (_: string, key: string) => {
      return this.ctx.get(key);
    });

    // 处理 @js: 前缀规则（JS 模板拼接，如 @js:'url'+$.nid+'/'+$.cid）
    if (rule.startsWith('@js:')) {
      return this.evalJsTemplate(rule.substring(4), this.content);
    }

    const a = this.analyze(rule);
    return a.length > 0 ? this.applyProcessor(a[0], rule) : '';
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
    const iv = args.length >= 3 ? this.stripQuotes(args[2]) : '';
    return this.js.aesBase64DecodeToString(data, key, iv);
  }

  private evalJsTemplate(expr: string, sourceJson: string): string {
    if (!expr) return '';
    expr = expr.trim();
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
      if (rule.startsWith('@.')) return this.getByPath(data, rule.substring(2));
      return this.getByPath(data, rule);
    } catch (_) {
      return undefined;
    }
  }

  private getByPath(obj: Object, path: string): Object | string | undefined {
    if (!obj || !path) return undefined;
    path = path.trim();

    // $..list[*] → 递归搜索
    if (path.startsWith('$..')) {
      const selector = path.substring(3);
      return this.deepFindBySelector(obj, selector);
    }

    // $.data[*] → 按层级
    const parts = path.replace(/^\$\./, '').replace(/\$/, '').split('.');
    let cur: Object = obj;
    for (const p of parts) {
      if (p === '[*]' || p === '*') {
        if (Array.isArray(cur)) return cur.map(v => typeof v === 'string' ? v : JSON.stringify(v));
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
      } else if (part === 'text' || part === 'ownText' || part === 'textNodes') {
        current = current.map(item => this.stripHtml(item)).filter(v => v.length > 0);
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
      return this.matchElements(selector);
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
    const selectors = this.splitCssSelector(sel);
    if (selectors.length > 1) {
      let contexts: string[] = [this.content];
      for (const part of selectors) {
        const next: string[] = [];
        for (const ctx of contexts) {
          next.push(...this.matchSimpleElements(ctx, part));
        }
        contexts = next;
        if (contexts.length === 0) break;
      }
      return contexts;
    }

    return this.matchSimpleElements(this.content, sel);
  }

  private matchSimpleElements(html: string, sel: string): string[] {
    if (!html || !sel) return [];
    const parsed = this.parseSimpleSelector(sel);
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
        res.push(this.sliceWholeElement(html, m.index, fullStartTag, m[1]));
        if (res.length > 5000) break;
      }
      const filtered = parsed.excludeIndex === null ? res : this.excludeIndex(res, parsed.excludeIndex);
      if (parsed.indexStart !== null) return this.pickRange(filtered, parsed.indexStart, parsed.indexEnd);
      return filtered;
    } catch (_) {
      return [];
    }
  }

  private extractAttr(html: string, attr: string): string {
    const re = new RegExp(`\\s${this.escapeRegex(attr)}\\s*=\\s*["']([^"']*)["']`, 'i');
    const m = html.match(re);
    return m ? m[1] : '';
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
      if (/\s/.test(ch) && bracket === 0) {
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
    s = s.replace(/\s*>\s*/g, ' ');
    return s;
  }

  private parseSimpleSelector(sel: string): {
    tag: string,
    id: string,
    classes: string[],
    attrs: Array<Record<string, string>>,
    notAttrs: Array<Record<string, string>>,
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
    const tagMatch = s.match(/^[A-Za-z][A-Za-z0-9_-]*/);
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
    return { tag, id, classes, attrs, notAttrs, indexStart, indexEnd, excludeIndex };
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
        case '~=': if (!new RegExp(`(^|\\s)${this.escapeRegex(expect)}(\\s|$)`).test(value)) return false; break;
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
        case '~=': if (new RegExp(`(^|\\s)${this.escapeRegex(expect)}(\\s|$)`).test(value)) return true; break;
        case '|=': if (value === expect || value.startsWith(expect + '-')) return true; break;
      }
    }
    return false;
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
    const idMatch = rule.match(/\/\/([a-zA-Z][\w-]*)\[@id=["']([^"']+)["']\]/);
    if (idMatch) {
      const root = this.matchSimpleElements(this.content, `${idMatch[1]}#${idMatch[2]}`);
      if (root.length === 0) return [];
      if (rule.endsWith('/a')) {
        const anchors: string[] = [];
        for (const item of root) anchors.push(...new AnalyzeRule(item, this.baseUrl, this.ctx).matchElements('a'));
        return anchors;
      }
    }

    const metaMatch = rule.match(/^\/\/meta\[@property=['"]([^'"]+)['"]\]\/@content$/);
    if (metaMatch) {
      const metas = this.matchSimpleElements(this.content, `meta[property="${metaMatch[1]}"]`);
      return metas.map(item => this.extractAttr(item, 'content')).filter(v => v.length > 0);
    }

    return [];
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
    return value;
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
    let result = template.replace(/\{\{([^}]+)\}\}/g, (_: string, expr: string) => {
      const rule = expr.trim();
      if (rule.startsWith('@get:{')) {
        const m = rule.match(/@get:\{(\w+)\}/);
        return m ? this.ctx.get(m[1]) : '';
      }
      if (rule.startsWith('$') || rule.startsWith('@.')) {
        const v = this.evalJsonPath(rule);
        if (Array.isArray(v)) return v.map(item => String(item)).join(',');
        return v === undefined || v === null ? '' : String(v);
      }
      if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(rule)) {
        const ctxVal = this.ctx.get(rule);
        if (ctxVal) return ctxVal;
      }
      return this.js.evalTemplate(`{{${rule}}}`);
    });

    const jsIndex = result.indexOf('@js:');
    if (jsIndex > 0) {
      result = result.substring(0, jsIndex);
    }
    return result;
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

    // 处理 @js: 后缀（AES解密等）
    const jsSuffix = rule.match(/@js:(.+)$/);
    if (jsSuffix) {
      const jsCode = jsSuffix[1];
      if (jsCode.startsWith('java.aesBase64DecodeToString')) {
        value = this.applyAesDecrypt(value, jsCode);
        if (!value) return '';
      } else {
        value = this.evalResultJs(jsCode, value);
      }
    }

    const parts = rule.split('##');
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

  private applyAesDecrypt(value: string, jsCode: string): string {
    // 解析 java.aesBase64DecodeToString(result, "key", "iv")
    const m = jsCode.match(/java\.aesBase64DecodeToString\(([^)]+)\)/);
    if (!m) return value;
    const args = this.splitArgs(m[1]);
    // args[0] 通常是 result（已由 value 提供），args[1] 是 key，args[2] 是 iv
    if (args.length >= 2) {
      const key = this.stripQuotes(args[1]);
      const iv = args.length >= 3 ? this.stripQuotes(args[2]) : '';
      return this.js.aesBase64DecodeToString(value, key, iv);
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

  private resolveUrl(url: string): string {
    if (!url || url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:' + url;
    if (url.startsWith('/')) {
      const m = this.baseUrl.match(/^(https?:\/\/[^/]+)/);
      return m ? m[0] + url : this.baseUrl + url;
    }
    const b = this.baseUrl.endsWith('/') ? this.baseUrl.substring(0, this.baseUrl.length - 1) : this.baseUrl;
    return b + '/' + url;
  }
}
