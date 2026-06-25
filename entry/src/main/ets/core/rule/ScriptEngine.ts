import { EncodedSourceUrl } from '../book/EncodedSourceUrl';
import { RuleContext } from './RuleContext';
import { JsRuntime } from './JsRuntime';

export class ScriptEvalResult {
  handled: boolean = false;
  value: string = '';
}

export class ScriptEngineContext {
  content: string = '';
  baseUrl: string = '';
  ctx: RuleContext = new RuleContext();

  getVar(key: string): string {
    return this.ctx.get(key);
  }

  putVar(key: string, value: string): void {
    this.ctx.put(key, value);
  }

  getSourceKey(): string {
    return this.ctx.get('source.bookSourceUrl') || this.ctx.get('bookSourceUrl');
  }

  getSourceValue(key: string): string {
    return this.ctx.get(`source.${key}`) || this.ctx.get(key);
  }

  getSourceVariable(key?: string): string {
    if (key) return this.ctx.get(`source.variable.${key}`) || this.ctx.get(key);
    return this.ctx.get('source.variable');
  }

  setSourceVariable(value: string, key?: string): void {
    if (key) this.ctx.put(`source.variable.${key}`, value);
    else this.ctx.put('source.variable', value);
  }

  getCache(key: string): string {
    return this.ctx.get(`cache.${key}`) || this.ctx.get(key);
  }

  putCache(key: string, value: string): void {
    this.ctx.put(`cache.${key}`, value);
    this.ctx.put(key, value);
  }

  getJsLib(): string {
    const parts: string[] = [];
    const jsLib = this.ctx.get('source.jsLib') || this.ctx.get('jsLib');
    const comment = this.ctx.get('source.bookSourceComment') || this.ctx.get('bookSourceComment');
    if (jsLib) parts.push(jsLib);
    if (comment) parts.push(comment);
    return parts.join('\n');
  }
}

export interface ScriptEngineBackend {
  evalBlock(code: string, env: ScriptEngineContext): ScriptEvalResult;
  evalResultJs(code: string, value: string, env: ScriptEngineContext): ScriptEvalResult;
}

export class ScriptEngine {
  private static defaultBackend?: ScriptEngineBackend;
  private js: JsRuntime;
  private backend?: ScriptEngineBackend;

  static setDefaultBackend(backend?: ScriptEngineBackend): void {
    ScriptEngine.defaultBackend = backend;
  }

  constructor(js: JsRuntime, backend?: ScriptEngineBackend) {
    this.js = js;
    this.backend = backend || ScriptEngine.defaultBackend;
  }

  evalBlock(code: string, env: ScriptEngineContext): ScriptEvalResult {
    if (this.backend) {
      const backendValue = this.backend.evalBlock(code, env);
      if (backendValue.handled) return backendValue;
    }
    const result = new ScriptEvalResult();
    const value = this.evalKnownJsLibBlock(code, env);
    if (value) {
      result.handled = true;
      result.value = value;
    }
    return result;
  }

  evalResultJs(code: string, value: string, env: ScriptEngineContext): ScriptEvalResult {
    if (this.backend) {
      const backendValue = this.backend.evalResultJs(code, value, env);
      if (backendValue.handled) return backendValue;
    }
    const result = new ScriptEvalResult();
    const knownValue = this.evalKnownResultJs(code, value, env);
    if (knownValue !== null) {
      result.handled = true;
      result.value = knownValue;
      return result;
    }
    if (/\bjava\.(?:base64|hex|md5|sha|url|encodeURI|aes|des|getCookie)/.test(code || '')) {
      this.js.setVar('baseUrl', env.baseUrl);
      result.handled = true;
      result.value = this.js.evaluate(code, value);
    }
    return result;
  }

  private evalKnownJsLibBlock(code: string, env: ScriptEngineContext): string {
    const normalized = code || '';
    const vars: Record<string, string> = { result: env.content, baseUrl: env.baseUrl };

    if (normalized.includes('J(result)') || normalized.includes('JSON.parse')) {
      const articleId = this.extractArticleIdFromContent(env.content) || this.extractArticleIdFromUrl(env.baseUrl);
      if (articleId) {
        vars['id'] = articleId;
        vars['aid'] = articleId;
      }
    }

    const cacheGet = normalized.match(/cache\.getFromMemory\(\s*['"]([^'"]+)['"]\s*\)/);
    if (cacheGet) {
      const value = env.getCache(cacheGet[1]);
      if (value) {
        vars['aid'] = value;
        vars[cacheGet[1]] = value;
      }
    }

    if (!vars['aid']) {
      const fromUrl = this.extractArticleIdFromUrl(env.baseUrl);
      if (fromUrl) vars['aid'] = fromUrl;
    }

    const cachePut = normalized.match(/cache\.putMemory\(\s*['"]([^'"]+)['"]\s*,\s*String\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\)/);
    if (cachePut) {
      const value = vars[cachePut[2]] || env.getVar(cachePut[2]) || '';
      if (value) {
        env.putCache(cachePut[1], value);
      }
    }
    this.applyHostSideEffects(normalized, vars, env);

    const baseExprIndex = normalized.lastIndexOf('Base()');
    const lastExpr = baseExprIndex >= 0 ? normalized.substring(baseExprIndex) : this.extractLastJsExpression(normalized);
    if (!lastExpr) return '';
    return this.evalKnownJsExpression(lastExpr, vars, env);
  }

  private evalKnownResultJs(code: string, value: string, env: ScriptEngineContext): string | null {
    const trimmed = (code || '').trim();
    if (/^Clean\(\s*result\s*\)\s*;?$/.test(trimmed)) return this.cleanJsLibText(value);
    if (/^T\(\s*result\s*\)\s*;?$/.test(trimmed)) return this.cleanJsLibText(value);
    if (/^Cover\(\s*result\s*\)\s*;?$/.test(trimmed)) return this.coverFromArticleId(value);
    const hostFunction = this.evalHostFunctionCall(trimmed, value, env);
    if (hostFunction !== null) return hostFunction;
    if (trimmed.includes('Base()')) {
      const vars: Record<string, string> = { result: value, baseUrl: env.baseUrl };
      const cacheGet = trimmed.match(/cache\.getFromMemory\(\s*['"]([^'"]+)['"]\s*\)/);
      if (cacheGet) {
        const cached = env.getCache(cacheGet[1]);
        if (cached) {
          vars['aid'] = cached;
          vars[cacheGet[1]] = cached;
        }
      }
      if (!vars['aid']) {
        const fromUrl = this.extractArticleIdFromUrl(env.baseUrl);
        if (fromUrl) vars['aid'] = fromUrl;
      }
      const baseExprIndex = trimmed.lastIndexOf('Base()');
      if (baseExprIndex >= 0) {
        const resolved = this.evalKnownJsExpression(trimmed.substring(baseExprIndex), vars, env);
        if (resolved) return resolved;
      }
    }
    return null;
  }

  private evalHostFunctionCall(code: string, value: string, env: ScriptEngineContext): string | null {
    const call = code.match(/^([A-Za-z_$][A-Za-z0-9_$]*)\(\s*(?:result|value|String\(\s*(?:result|value)\s*\))\s*\)\s*;?$/);
    if (!call) return null;
    const func = this.extractFunctionBody(env.getJsLib(), call[1]);
    if (!func) return null;
    const cipherCall = this.evalJavaCipherFunction(func, value);
    if (cipherCall !== null) return cipherCall;
    return null;
  }

  private evalJavaCipherFunction(functionBody: string, value: string): string | null {
    if (!/Cipher\.getInstance|SecretKeySpec|IvParameterSpec/.test(functionBody)) return null;
    const keyMatch = functionBody.match(/SecretKeySpec\s*\(\s*(?:new\s+)?String\s*\(\s*(['"])(.*?)\1\s*\)\.getBytes\(\s*\)\s*,\s*(['"])(.*?)\3\s*\)/) ||
      functionBody.match(/SecretKeySpec\s*\(\s*(['"])(.*?)\1\.getBytes\(\s*\)\s*,\s*(['"])(.*?)\3\s*\)/);
    const ivMatch = functionBody.match(/IvParameterSpec\s*\(\s*(?:new\s+)?String\s*\(\s*(['"])(.*?)\1\s*\)\.getBytes\(\s*\)\s*\)/) ||
      functionBody.match(/IvParameterSpec\s*\(\s*(['"])(.*?)\1\.getBytes\(\s*\)\s*\)/);
    const cipherMatch = functionBody.match(/Cipher\.getInstance\s*\(\s*(['"])(.*?)\1\s*\)/);
    if (!keyMatch || !cipherMatch) return null;
    const key = keyMatch[2];
    const keyAlg = keyMatch[4] || '';
    const iv = ivMatch ? ivMatch[2] : '';
    const transformation = cipherMatch[2] || keyAlg || 'AES/CBC/PKCS5Padding';
    const upper = transformation.toUpperCase();
    const method = upper.startsWith('DES') || upper.startsWith('3DES') || upper.startsWith('TRIPLEDES') ?
      'java.desBase64DecodeToString' : 'java.aesBase64DecodeToString';
    this.js.setVar('result', value);
    return this.js.evaluate(`${method}(result,${this.quoteJsString(key)},${this.quoteJsString(transformation)},${this.quoteJsString(iv)})`, value);
  }

  private extractFunctionBody(code: string, name: string): string {
    const pattern = new RegExp(`function\\s+${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*\\(`);
    const match = pattern.exec(code || '');
    if (!match) return '';
    const braceStart = (code || '').indexOf('{', match.index + match[0].length);
    if (braceStart < 0) return '';
    let depth = 0;
    let quote = '';
    for (let i = braceStart; i < code.length; i++) {
      const ch = code.charAt(i);
      if (quote) {
        if (ch === quote && code.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') {
        quote = ch;
        continue;
      }
      if (ch === '{') depth++;
      else if (ch === '}') {
        depth--;
        if (depth === 0) return code.substring(braceStart + 1, i);
      }
    }
    return '';
  }

  private quoteJsString(value: string): string {
    return `'${(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
  }

  private evalKnownJsExpression(expr: string, vars: Record<string, string>, env: ScriptEngineContext): string {
    let value = (expr || '').trim().replace(/;$/, '');
    if (!value) return '';
    const cleanCall = value.match(/^(?:Clean|T)\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$/);
    if (cleanCall) return this.cleanJsLibText(vars[cleanCall[1]] || '');
    const coverCall = value.match(/^Cover\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$/);
    if (coverCall) return this.coverFromArticleId(vars[coverCall[1]] || '');
    const sourceCall = this.evalSourceCall(value, env);
    if (sourceCall !== null) return sourceCall;
    const cacheCall = this.evalCacheCall(value, env);
    if (cacheCall !== null) return cacheCall;
    value = value.replace(/\bBase\(\)/g, `'${this.extractBaseFunctionHost(env)}'`);
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

  private extractLastJsExpression(code: string): string {
    const trimmed = (code || '').trim();
    const returnMatch = trimmed.match(/return\s+([\s\S]*?);?\s*$/);
    if (returnMatch) return returnMatch[1].trim();
    const parts = trimmed.split(';').map(part => part.trim()).filter(part => part.length > 0);
    for (let i = parts.length - 1; i >= 0; i--) {
      const part = parts[i];
      if (!part.startsWith('var ') && !part.startsWith('let ') && !part.startsWith('const ')) return part;
    }
    return '';
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

  private applyHostSideEffects(code: string, vars: Record<string, string>, env: ScriptEngineContext): void {
    const sourceSetRe = /source\.setVariable\(([\s\S]*?)\)/g;
    let sourceSet: RegExpExecArray | null;
    while ((sourceSet = sourceSetRe.exec(code)) !== null) {
      const args = this.splitArgs(sourceSet[1]);
      if (args.length >= 2) env.setSourceVariable(this.evalHostArg(args[1], vars, env), this.evalHostArg(args[0], vars, env));
      else if (args.length === 1) env.setSourceVariable(this.evalHostArg(args[0], vars, env));
    }

    const cacheLiteralPutRe = /cache\.put(?:Memory)?\(\s*(['"])(.*?)\1\s*,\s*(['"])(.*?)\3\s*\)/g;
    let cacheLiteralPut: RegExpExecArray | null;
    while ((cacheLiteralPut = cacheLiteralPutRe.exec(code)) !== null) {
      env.putCache(cacheLiteralPut[2], cacheLiteralPut[4]);
    }
    const cacheVarPutRe = /cache\.put(?:Memory)?\(\s*(['"])(.*?)\1\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/g;
    let cacheVarPut: RegExpExecArray | null;
    while ((cacheVarPut = cacheVarPutRe.exec(code)) !== null) {
      env.putCache(cacheVarPut[2], vars[cacheVarPut[3]] || env.getVar(cacheVarPut[3]) || '');
    }
  }

  private evalSourceCall(expr: string, env: ScriptEngineContext): string | null {
    const text = (expr || '').trim().replace(/;$/, '');
    if (text === 'source.getKey()' || text === 'source.key') return env.getSourceKey();
    const noArg = text.match(/^source\.getVariable\(\s*\)$/);
    if (noArg) return env.getSourceVariable();
    const withArg = text.match(/^source\.getVariable\(\s*(['"])(.*?)\1\s*\)$/);
    if (withArg) return env.getSourceVariable(withArg[2]);
    const prop = text.match(/^source\.([A-Za-z_][A-Za-z0-9_]*)$/);
    if (prop) return env.getSourceValue(prop[1]);
    return null;
  }

  private evalCacheCall(expr: string, env: ScriptEngineContext): string | null {
    const text = (expr || '').trim().replace(/;$/, '');
    const get = text.match(/^cache\.get(?:FromMemory)?\(\s*(['"])(.*?)\1\s*\)$/);
    if (get) return env.getCache(get[2]);
    return null;
  }

  private evalHostArg(arg: string, vars: Record<string, string>, env: ScriptEngineContext): string {
    const text = (arg || '').trim();
    if (!text) return '';
    const sourceCall = this.evalSourceCall(text, env);
    if (sourceCall !== null) return sourceCall;
    const cacheCall = this.evalCacheCall(text, env);
    if (cacheCall !== null) return cacheCall;
    const stringCall = text.match(/^String\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$/);
    if (stringCall) return vars[stringCall[1]] || env.getVar(stringCall[1]);
    if ((text.startsWith("'") && text.endsWith("'")) || (text.startsWith('"') && text.endsWith('"'))) {
      return text.substring(1, text.length - 1);
    }
    return vars[text] || env.getVar(text) || text;
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
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (ch === ',' && depth === 0) {
        result.push(args.substring(start, i).trim());
        start = i + 1;
      }
    }
    const last = args.substring(start).trim();
    if (last) result.push(last);
    return result;
  }

  private extractArticleIdFromContent(content: string): string {
    try {
      const data = EncodedSourceUrl.asMap(JSON.parse(content || '{}') as Object);
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

  private extractBaseFunctionHost(env: ScriptEngineContext): string {
    const raw = env.getJsLib();
    const baseMatch = raw.match(/function\s+Base\s*\(\s*\)\s*\{\s*return\s*['"]([^'"]+)['"]/);
    if (baseMatch) return baseMatch[1];
    const hostMatch = raw.match(/https?:\/\/[^'"`\s,)]+/);
    if (hostMatch) return hostMatch[0];
    const base = (env.getSourceKey() || env.baseUrl || '')
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
}
