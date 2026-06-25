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

class ScriptFunction {
  params: string[] = [];
  body: string = '';
}

class ScriptReturnSignal {
  value: Object = '';
}

class ArkTsJsEngineBackend implements ScriptEngineBackend {
  evalBlock(code: string, env: ScriptEngineContext): ScriptEvalResult {
    return new ArkTsJsRunner(env).run(code, env.content);
  }

  evalResultJs(code: string, value: string, env: ScriptEngineContext): ScriptEvalResult {
    return new ArkTsJsRunner(env).run(code, value);
  }
}

class ArkTsJsRunner {
  private env: ScriptEngineContext;
  private vars: Record<string, Object> = {};
  private functions: Record<string, ScriptFunction> = {};

  constructor(env: ScriptEngineContext) {
    this.env = env;
  }

  run(code: string, resultValue: string): ScriptEvalResult {
    const out = new ScriptEvalResult();
    const script = (code || '').trim();
    if (!script || this.requiresHostFallback(script)) return out;
    this.vars['result'] = resultValue;
    this.vars['baseUrl'] = this.env.baseUrl;
    try {
      const body = this.collectFunctions(this.stripLineComments(script));
      let last: Object = '';
      const statements = this.splitStatements(body);
      for (const statement of statements) {
        const value = this.evalStatement(statement);
        if (value !== undefined && value !== null) last = value;
      }
      out.handled = true;
      out.value = this.toString(last);
      return out;
    } catch (_) {
      return out;
    }
  }

  private requiresHostFallback(code: string): boolean {
    const jsLib = this.env.getJsLib();
    return /\bjava\.(?:ajax|ajaxAll|post|connect|aes|des|getCookie|cookie)|\b(?:JavaImporter|Packages|Cipher|SecretKeySpec|IvParameterSpec)\b/.test(code) ||
      /\b(?:JavaImporter|Packages|Cipher|SecretKeySpec|IvParameterSpec)\b/.test(jsLib);
  }

  private stripLineComments(code: string): string {
    return (code || '').split('\n').map(line => {
      const index = line.indexOf('//');
      if (index < 0) return line;
      const before = line.substring(0, index);
      return this.isInsideQuote(line, index) ? line : before;
    }).join('\n');
  }

  private isInsideQuote(text: string, index: number): boolean {
    let quote = '';
    for (let i = 0; i < index; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
      } else if (ch === '"' || ch === "'" || ch === '`') {
        quote = ch;
      }
    }
    return quote.length > 0;
  }

  private collectFunctions(code: string): string {
    let text = code || '';
    let index = 0;
    while (index < text.length) {
      const match = /function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(([^)]*)\)\s*\{/.exec(text.substring(index));
      if (!match) break;
      const start = index + match.index;
      const braceStart = text.indexOf('{', start + match[0].length - 1);
      const braceEnd = this.findMatching(text, braceStart, '{', '}');
      if (braceEnd < 0) break;
      const fn = new ScriptFunction();
      fn.params = match[2].split(',').map(item => item.trim()).filter(item => item.length > 0);
      fn.body = text.substring(braceStart + 1, braceEnd);
      this.functions[match[1]] = fn;
      text = text.substring(0, start) + text.substring(braceEnd + 1);
      index = start;
    }
    return text;
  }

  private evalStatement(statement: string): Object | undefined {
    let text = (statement || '').trim();
    if (!text) return undefined;
    if (text.startsWith('return ')) {
      const signal = new ScriptReturnSignal();
      signal.value = this.evalExpression(text.substring(7));
      return signal as Object;
    }

    const ifValue = this.evalIfStatement(text);
    if (ifValue !== undefined) return ifValue;

    const declare = text.match(/^(?:var|let|const)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*([\s\S]+)$/);
    if (declare) {
      const value = this.evalExpression(declare[2]);
      this.vars[declare[1]] = value;
      return value;
    }

    const assign = text.match(/^([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*([\s\S]+)$/);
    if (assign) {
      const value = this.evalExpression(assign[2]);
      this.vars[assign[1]] = value;
      return value;
    }

    return this.evalExpression(text);
  }

  private evalIfStatement(text: string): Object | undefined {
    if (!text.startsWith('if')) return undefined;
    const open = text.indexOf('(');
    const close = open >= 0 ? this.findMatching(text, open, '(', ')') : -1;
    if (open < 0 || close < 0) return undefined;
    const condition = this.truthy(this.evalExpression(text.substring(open + 1, close)));
    let rest = text.substring(close + 1).trim();
    let thenPart = '';
    let elsePart = '';
    if (rest.startsWith('{')) {
      const end = this.findMatching(rest, 0, '{', '}');
      if (end < 0) return undefined;
      thenPart = rest.substring(1, end);
      rest = rest.substring(end + 1).trim();
    } else {
      const elseIndex = this.indexOfTopLevelWord(rest, 'else');
      thenPart = elseIndex >= 0 ? rest.substring(0, elseIndex).trim() : rest;
      rest = elseIndex >= 0 ? rest.substring(elseIndex).trim() : '';
    }
    if (rest.startsWith('else')) {
      elsePart = rest.substring(4).trim();
      if (elsePart.startsWith('{')) {
        const end = this.findMatching(elsePart, 0, '{', '}');
        elsePart = end >= 0 ? elsePart.substring(1, end) : '';
      }
    }
    return this.evalStatements(condition ? thenPart : elsePart);
  }

  private evalStatements(code: string): Object {
    let last: Object = '';
    const statements = this.splitStatements(code || '');
    for (const statement of statements) {
      const value = this.evalStatement(statement);
      if (value instanceof ScriptReturnSignal) return value;
      if (value !== undefined && value !== null) last = value;
    }
    return last;
  }

  private evalExpression(expr: string): Object {
    let text = (expr || '').trim().replace(/;\s*$/, '');
    if (!text) return '';
    if (text.startsWith('return ')) text = text.substring(7).trim();
    text = this.unwrapParens(text);

    const question = this.indexOfTopLevel(text, '?');
    if (question >= 0) {
      const colon = this.indexOfTopLevelFrom(text, ':', question + 1);
      if (colon > question) {
        return this.truthy(this.evalExpression(text.substring(0, question))) ?
          this.evalExpression(text.substring(question + 1, colon)) :
          this.evalExpression(text.substring(colon + 1));
      }
    }

    const direct = this.evalLiteralOrVariable(text);
    if (direct !== undefined) return direct;

    const compare = this.findComparison(text);
    if (compare.index >= 0) {
      const left = this.evalExpression(text.substring(0, compare.index));
      const right = this.evalExpression(text.substring(compare.index + compare.op.length));
      return this.compareValues(left, right, compare.op);
    }

    const plus = this.splitTopLevel(text, '+');
    if (plus.length > 1) {
      const values = plus.map(part => this.evalExpression(part));
      const numeric = values.every(item => typeof item === 'number' || /^-?\d+(?:\.\d+)?$/.test(this.toString(item)));
      if (numeric) return values.reduce((sum: number, item: Object) => sum + Number(this.toString(item)), 0);
      return values.map(item => this.toString(item)).join('');
    }

    const minus = this.splitTopLevel(text, '-');
    if (minus.length > 1) {
      let value = Number(this.toString(this.evalExpression(minus[0])));
      for (let i = 1; i < minus.length; i++) value -= Number(this.toString(this.evalExpression(minus[i])));
      return Number.isNaN(value) ? '' : value;
    }

    const callValue = this.evalFunctionOrHostCall(text);
    if (callValue !== undefined) return callValue;

    return this.evalChain(text);
  }

  private evalLiteralOrVariable(text: string): Object | undefined {
    if ((text.startsWith('"') && text.endsWith('"')) || (text.startsWith("'") && text.endsWith("'"))) {
      return this.unescapeString(text.substring(1, text.length - 1));
    }
    if (text.startsWith('`') && text.endsWith('`')) return this.evalTemplateLiteral(text.substring(1, text.length - 1));
    if (text === 'true') return true;
    if (text === 'false') return false;
    if (text === 'null') return null as Object;
    if (/^\/[\s\S]+\/[gimsuy]*$/.test(text)) return text;
    if (/^-?\d+(?:\.\d+)?$/.test(text)) return Number(text);
    if (/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(text) && this.vars[text] !== undefined) return this.vars[text];
    return undefined;
  }

  private evalFunctionOrHostCall(text: string): Object | undefined {
    const call = text.match(/^([A-Za-z_$][A-Za-z0-9_$.]*)\s*\(([\s\S]*)\)$/);
    if (!call) return undefined;
    const name = call[1];
    const args = this.splitArgs(call[2]).map(arg => this.evalExpression(arg));
    if (name === 'JSON.parse') {
      try { return JSON.parse(this.toString(args[0])); } catch (_) { return {}; }
    }
    if (name === 'JSON.stringify') return JSON.stringify(args[0]);
    if (name === 'String') return this.toString(args[0]);
    if (name === 'Number') return Number(this.toString(args[0]));
    if (name === 'parseInt') return parseInt(this.toString(args[0]));
    if (name === 'encodeURIComponent') return encodeURIComponent(this.toString(args[0]));
    if (name === 'decodeURIComponent') {
      try { return decodeURIComponent(this.toString(args[0])); } catch (_) { return this.toString(args[0]); }
    }
    if (name === 'source.getKey') return this.env.getSourceKey();
    if (name === 'source.getVariable') return this.env.getSourceVariable(args.length > 0 ? this.toString(args[0]) : undefined);
    if (name === 'source.setVariable') {
      if (args.length >= 2) this.env.setSourceVariable(this.toString(args[1]), this.toString(args[0]));
      else this.env.setSourceVariable(this.toString(args[0]));
      return args.length >= 2 ? this.toString(args[1]) : this.toString(args[0]);
    }
    if (name === 'cache.get' || name === 'cache.getFromMemory') return this.env.getCache(this.toString(args[0]));
    if (name === 'cache.put' || name === 'cache.putMemory') {
      this.env.putCache(this.toString(args[0]), this.toString(args[1]));
      return this.toString(args[1]);
    }
    if (this.functions[name]) return this.callUserFunction(name, args);
    return undefined;
  }

  private callUserFunction(name: string, args: Object[]): Object {
    const fn = this.functions[name];
    const snapshot: Record<string, Object> = {};
    for (const key in this.vars) snapshot[key] = this.vars[key];
    for (let i = 0; i < fn.params.length; i++) this.vars[fn.params[i]] = args[i] || '';
    const value = this.evalStatements(fn.body);
    this.vars = snapshot;
    if (value instanceof ScriptReturnSignal) return value.value;
    return value;
  }

  private evalChain(expr: string): Object {
    const callBase = expr.match(/^([A-Za-z_$][A-Za-z0-9_$.]*)\s*\(/);
    let current: Object = '';
    let index = -1;
    if (callBase && this.isCallableChainBase(callBase[1])) {
      const open = expr.indexOf('(', callBase[1].length);
      const end = this.findMatching(expr, open, '(', ')');
      if (end < 0) return '';
      const baseValue = this.evalFunctionOrHostCall(expr.substring(0, end + 1));
      if (baseValue === undefined) return '';
      current = baseValue;
      index = end + 1;
    } else {
      const firstEnd = this.firstChainBreak(expr);
      if (firstEnd <= 0) return '';
      current = this.evalExpression(expr.substring(0, firstEnd));
      index = firstEnd;
    }
    while (index < expr.length) {
      const ch = expr.charAt(index);
      if (ch === '.') {
        const next = this.readIdentifier(expr, index + 1);
        if (!next.name) return '';
        index = next.end;
        if (expr.charAt(index) === '(') {
          const end = this.findMatching(expr, index, '(', ')');
          if (end < 0) return '';
          const rawArgs = this.splitArgs(expr.substring(index + 1, end));
          const args = (next.name === 'map' || next.name === 'filter') ?
            rawArgs as Object[] : rawArgs.map(arg => this.evalExpression(arg));
          current = this.applyMethod(current, next.name, args);
          index = end + 1;
        } else {
          current = this.readProperty(current, next.name);
        }
      } else if (ch === '[') {
        const end = this.findMatching(expr, index, '[', ']');
        if (end < 0) return '';
        current = this.readProperty(current, this.toString(this.evalExpression(expr.substring(index + 1, end))));
        index = end + 1;
      } else {
        return '';
      }
    }
    return current;
  }

  private isCallableChainBase(name: string): boolean {
    return !name.includes('.') || name === 'JSON.parse' || name === 'JSON.stringify' ||
      name.startsWith('source.') || name.startsWith('cache.');
  }

  private applyMethod(target: Object, name: string, args: Object[]): Object {
    const text = this.toString(target);
    if (name === 'replace') {
      const pattern = this.asRegExp(args[0]);
      return pattern ? text.replace(pattern, this.toString(args[1])) : text.split(this.toString(args[0])).join(this.toString(args[1]));
    }
    if (name === 'match') {
      const pattern = this.asRegExp(args[0]);
      const match = pattern ? text.match(pattern) : null;
      return match ? Array.from(match) as Object : [];
    }
    if (name === 'substring') return text.substring(Number(this.toString(args[0])), args.length > 1 ? Number(this.toString(args[1])) : undefined);
    if (name === 'substr') return text.substr(Number(this.toString(args[0])), args.length > 1 ? Number(this.toString(args[1])) : undefined);
    if (name === 'slice') {
      if (Array.isArray(target)) return (target as Object[]).slice(Number(this.toString(args[0])), args.length > 1 ? Number(this.toString(args[1])) : undefined) as Object;
      return text.slice(Number(this.toString(args[0])), args.length > 1 ? Number(this.toString(args[1])) : undefined);
    }
    if (name === 'split') return text.split(this.toString(args[0])) as Object;
    if (name === 'join' && Array.isArray(target)) return (target as Object[]).map(item => this.toString(item)).join(this.toString(args[0]));
    if (name === 'trim') return text.trim();
    if (name === 'toString') return text;
    if (name === 'toLowerCase') return text.toLowerCase();
    if (name === 'toUpperCase') return text.toUpperCase();
    if (name === 'map' && Array.isArray(target)) return this.applyArrowMap(target as Object[], this.toString(args[0]));
    if (name === 'filter' && Array.isArray(target)) return this.applyArrowFilter(target as Object[], this.toString(args[0]));
    return '';
  }

  private applyArrowMap(items: Object[], rawArrow: string): Object {
    const arrow = rawArrow.match(/^\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*=>\s*([\s\S]+)$/);
    if (!arrow) return items;
    const out: Object[] = [];
    for (const item of items) {
      this.vars[arrow[1]] = item;
      out.push(this.evalExpression(arrow[2]));
    }
    return out as Object;
  }

  private applyArrowFilter(items: Object[], rawArrow: string): Object {
    const arrow = rawArrow.match(/^\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*=>\s*([\s\S]+)$/);
    if (!arrow) return items;
    const out: Object[] = [];
    for (const item of items) {
      this.vars[arrow[1]] = item;
      if (this.truthy(this.evalExpression(arrow[2]))) out.push(item);
    }
    return out as Object;
  }

  private readProperty(target: Object, key: string): Object {
    if (key === 'length') {
      if (Array.isArray(target)) return (target as Object[]).length;
      return this.toString(target).length;
    }
    if (Array.isArray(target) && /^-?\d+$/.test(key)) return (target as Object[])[Number(key)] || '';
    if (target && typeof target === 'object') {
      const record = target as Record<string, Object>;
      return record[key] !== undefined && record[key] !== null ? record[key] : '';
    }
    return '';
  }

  private asRegExp(value: Object): RegExp | null {
    const text = this.toString(value);
    const match = text.match(/^\/([\s\S]*)\/([gimsuy]*)$/);
    if (!match) return null;
    try { return new RegExp(match[1].replace(/\\\//g, '/'), match[2]); } catch (_) { return null; }
  }

  private splitStatements(code: string): string[] {
    return this.splitByTopLevel(code || '', [';', '\n']);
  }

  private splitArgs(args: string): string[] {
    return this.splitByTopLevel(args || '', [',']);
  }

  private splitTopLevel(text: string, separator: string): string[] {
    return this.splitByTopLevel(text, [separator]);
  }

  private splitByTopLevel(text: string, separators: string[]): string[] {
    const parts: string[] = [];
    let quote = '';
    let depth = 0;
    let start = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && separators.includes(ch)) {
        const part = text.substring(start, i).trim();
        if (part) parts.push(part);
        start = i + 1;
      }
    }
    const last = text.substring(start).trim();
    if (last) parts.push(last);
    return parts;
  }

  private indexOfTopLevel(text: string, target: string): number {
    return this.indexOfTopLevelFrom(text, target, 0);
  }

  private indexOfTopLevelFrom(text: string, target: string, from: number): number {
    let quote = '';
    let depth = 0;
    for (let i = from; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && ch === target) return i;
    }
    return -1;
  }

  private indexOfTopLevelWord(text: string, word: string): number {
    const pattern = new RegExp(`\\b${word}\\b`, 'g');
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(text)) !== null) {
      let quote = '';
      let depth = 0;
      for (let i = 0; i < match.index; i++) {
        const ch = text.charAt(i);
        if (quote) {
          if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        } else if (ch === '"' || ch === "'" || ch === '`') quote = ch;
        else if (ch === '(' || ch === '[' || ch === '{') depth++;
        else if (ch === ')' || ch === ']' || ch === '}') depth--;
      }
      if (!quote && depth === 0) return match.index;
    }
    return -1;
  }

  private findMatching(text: string, openIndex: number, open: string, close: string): number {
    let depth = 0;
    let quote = '';
    for (let i = openIndex; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === open) depth++;
      if (ch === close) {
        depth--;
        if (depth === 0) return i;
      }
    }
    return -1;
  }

  private unwrapParens(text: string): string {
    let value = text.trim();
    while (value.startsWith('(')) {
      const end = this.findMatching(value, 0, '(', ')');
      if (end !== value.length - 1) break;
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  private findComparison(text: string): { index: number, op: string } {
    const ops = ['===', '!==', '>=', '<=', '==', '!=', '>', '<'];
    for (const op of ops) {
      const index = this.indexOfTopLevelOperator(text, op);
      if (index >= 0) return { index: index, op: op };
    }
    return { index: -1, op: '' };
  }

  private indexOfTopLevelOperator(text: string, op: string): number {
    let quote = '';
    let depth = 0;
    for (let i = 0; i <= text.length - op.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && text.substring(i, i + op.length) === op) return i;
    }
    return -1;
  }

  private compareValues(left: Object, right: Object, op: string): boolean {
    const ln = Number(this.toString(left));
    const rn = Number(this.toString(right));
    const numeric = !Number.isNaN(ln) && !Number.isNaN(rn) && this.toString(left) !== '' && this.toString(right) !== '';
    const a: Object = numeric ? ln : this.toString(left);
    const b: Object = numeric ? rn : this.toString(right);
    if (op === '===' || op === '==') return a === b;
    if (op === '!==' || op === '!=') return a !== b;
    if (op === '>=') return a >= b;
    if (op === '<=') return a <= b;
    if (op === '>') return a > b;
    if (op === '<') return a < b;
    return false;
  }

  private firstChainBreak(text: string): number {
    let quote = '';
    let depth = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && (ch === '.' || ch === '[')) return i;
    }
    return -1;
  }

  private readIdentifier(text: string, start: number): { name: string, end: number } {
    let end = start;
    while (end < text.length && /[A-Za-z0-9_$]/.test(text.charAt(end))) end++;
    return { name: text.substring(start, end), end: end };
  }

  private evalTemplateLiteral(text: string): string {
    return text.replace(/\$\{([\s\S]*?)\}/g, (_: string, expr: string) => this.toString(this.evalExpression(expr)));
  }

  private unescapeString(text: string): string {
    return (text || '').replace(/\\n/g, '\n').replace(/\\r/g, '\r').replace(/\\t/g, '\t')
      .replace(/\\"/g, '"').replace(/\\'/g, "'").replace(/\\\\/g, '\\');
  }

  private truthy(value: Object): boolean {
    if (value === undefined || value === null) return false;
    if (typeof value === 'boolean') return value;
    const text = this.toString(value);
    return text.length > 0 && text !== 'false' && text !== '0';
  }

  private toString(value: Object): string {
    if (value === undefined || value === null) return '';
    if (typeof value === 'string') return value as string;
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    if (Array.isArray(value)) return (value as Object[]).map(item => this.toString(item)).join(',');
    try { return JSON.stringify(value); } catch (_) { return String(value); }
  }
}

export class ScriptEngine {
  private static defaultBackend?: ScriptEngineBackend = new ArkTsJsEngineBackend();
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
