import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { CookieStore } from '../http/CookieStore';
import { JsonPathEvaluator } from './JsonPathEvaluator';

export class JsRuntime {
  private vars: Record<string, string> = {};
  private jsonContext: Object | null = null;

  setVar(k: string, v: string): void { this.vars[k] = v; }
  getVar(k: string): string { return this.vars[k] || ''; }
  setJsonContext(text: string): void {
    try {
      this.jsonContext = JSON.parse(text || '{}') as Object;
    } catch (_) {
      this.jsonContext = null;
    }
  }

  evaluate(expression: string, result: string = ''): string {
    this.vars['result'] = result;
    this.setJsonContext(result);
    return this.evalExpr(expression.replace(/^\s*(?:return\s+)?/, '').replace(/;\s*$/, ''));
  }

  evalTemplate(tpl: string): string {
    if (!tpl.includes('{{')) return tpl;
    return tpl.replace(/\{\{([\s\S]*?)\}\}/g, (_: string, expr: string) => this.evalExpr(expr.trim()));
  }

  private evalExpr(expr: string): string {
    try {
      const statements = this.splitStatements(expr);
      if (statements.length > 1) {
        let last = '';
        for (const statement of statements) last = this.evalExpr(statement);
        return last;
      }
      const commaStatements = this.splitTopLevel(expr, [',']);
      if (commaStatements.length > 1) {
        let last = '';
        for (const statement of commaStatements) last = this.evalExpr(statement);
        return last;
      }
      const assignIndex = this.indexOfTopLevelAssignment(expr);
      if (assignIndex > 0) {
        const key = expr.substring(0, assignIndex).replace(/^(?:var|let|const)\s+/, '').trim();
        if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
          const value = this.evalExpr(expr.substring(assignIndex + 1));
          this.setVar(key, value);
          return value;
        }
      }
      expr = this.replaceDateExpressions(expr);
      expr = expr.replace(/Date\.now\(\)/g, String(Date.now()));

      expr = this.replaceFunctionCalls(expr, 'Math.round', (v: string) => String(Math.round(this.evalNumber(v))));
      expr = this.replaceFunctionCalls(expr, 'Math.floor', (v: string) => String(Math.floor(this.evalNumber(v))));
      expr = this.replaceFunctionCalls(expr, 'Math.ceil', (v: string) => String(Math.ceil(this.evalNumber(v))));

      expr = this.replaceFunctionCalls(expr, 'java.base64Encode', (v: string) => this.base64(this.evalStr(this.splitArgs(v)[0] || v)));
      expr = this.replaceFunctionCalls(expr, 'java.base64EncodeToString', (v: string) => this.base64(this.evalStr(this.splitArgs(v)[0] || v)));
      expr = this.replaceFunctionCalls(expr, 'java.base64Decode', (v: string) => this.base64Decode(this.evalStr(this.splitArgs(v)[0] || v)));
      expr = this.replaceFunctionCalls(expr, 'java.hexDecodeToString', (v: string) => this.hexDecodeToString(this.evalStr(this.splitArgs(v)[0] || v)));
      expr = this.replaceFunctionCalls(expr, 'java.hexEncodeToString', (v: string) => this.hexEncodeToString(this.evalStr(this.splitArgs(v)[0] || v)));
      expr = this.replaceFunctionCalls(expr, 'java.md5Encode16', (v: string) => this.md5(this.evalStr(v)).substring(8, 24));
      expr = this.replaceFunctionCalls(expr, 'java.md5Encode', (v: string) => this.digest('MD5', this.evalStr(v)));
      expr = this.replaceFunctionCalls(expr, 'java.sha1Encode', (v: string) => this.digest('SHA1', this.evalStr(v)));
      expr = this.replaceFunctionCalls(expr, 'java.sha256Encode', (v: string) => this.digest('SHA256', this.evalStr(v)));
      expr = this.replaceFunctionCalls(expr, 'java.urlEncode', (v: string) => encodeURIComponent(this.evalStr(this.splitArgs(v)[0] || v)));
      expr = this.replaceFunctionCalls(expr, 'java.urlDecode', (v: string) => this.urlDecode(this.evalStr(this.splitArgs(v)[0] || v)));
      expr = this.replaceFunctionCalls(expr, 'java.getCookie', (v: string) => this.cookieValue(v));
      expr = this.replaceFunctionCalls(expr, 'java.put', (v: string) => this.putVar(v));
      expr = this.replaceFunctionCalls(expr, 'java.get', (v: string) => this.getVarCall(v));
      expr = this.replaceFunctionCalls(expr, 'cookie.getCookie', (v: string) => this.cookieValue(v));
      expr = this.replaceFunctionCalls(expr, 'java.timeFormat', (v: string) => this.timeFormatCall(v));
      expr = this.replaceGetStringListCalls(expr);
      expr = this.replaceFunctionCalls(expr, 'java.getString', (v: string) => this.javaGetStringCall(v));
      expr = this.replaceFunctionCalls(expr, 'java.getElement', (v: string) => this.javaGetStringCall(v));
      expr = this.replaceFunctionCalls(expr, 'java.t2s', (v: string) => this.evalStr(v));
      expr = this.replaceFunctionCalls(expr, 'String', (v: string) => this.evalStr(v));
      expr = this.replaceFunctionCalls(expr, 'encodeURIComponent', (v: string) => encodeURIComponent(this.evalStr(v)));
      expr = this.replaceFunctionCalls(expr, 'encodeURI', (v: string) => encodeURI(this.evalStr(v)));
      expr = this.replaceFunctionCalls(expr, 'java.encodeURI', (v: string) => encodeURIComponent(this.evalStr(this.splitArgs(v)[0] || v)));
      expr = this.replaceFunctionCalls(expr, 'java.aesBase64DecodeToString', (v: string) => this.evalAes(v, false));
      expr = this.replaceFunctionCalls(expr, 'java.aesEncodeToBase64String', (v: string) => this.evalAes(v, true));
      expr = this.replaceFunctionCalls(expr, 'java.desBase64DecodeToString', (v: string) => this.evalDes(v, false));
      expr = this.replaceFunctionCalls(expr, 'java.desEncodeToBase64String', (v: string) => this.evalDes(v, true));

      expr = this.replaceNoArgCalls(expr);
      this.applyCookieSideEffects(expr);

      for (const k in this.vars) {
        const value = this.vars[k];
        const escaped = value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
        const replacement = value.match(/^-?\d+(\.\d+)?$/) ? value : `"${escaped}"`;
        expr = expr.replace(new RegExp('\\b' + k + '\\b', 'g'), replacement);
      }

      if (/^[\d\s+\-*/%.()]+$/.test(expr)) {
        return String(this.evalNumber(expr));
      }

      const parts = this.splitConcat(expr);
      if (parts.length > 1) {
        return parts.map((part: string) => this.evalStr(part)).join('');
      }

      expr = this.stripQuotes(expr);
      return expr;
    } catch (e) {
      return expr;
    }
  }

  private evalSimple(expr: string): string {
    expr = this.replaceDateExpressions(expr);
    for (const k in this.vars) expr = expr.replace(new RegExp('\\b' + k + '\\b', 'g'), this.vars[k]);
    try {
      if (/^[\d\s+\-*/%.()]+$/.test(expr)) return String(this.evalNumber(expr));
      return expr;
    } catch (e) { return expr; }
  }

  private evalStr(s: string): string {
    let v = s.trim();
    v = this.replaceDateExpressions(v);
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.substring(1, v.length - 1);
    const parts = this.splitConcat(v);
    if (parts.length > 1) return parts.map((part: string) => this.evalStr(part)).join('');
    for (const k in this.vars) v = v.replace(new RegExp('\\b' + k + '\\b', 'g'), this.vars[k]);
    return v;
  }

  private replaceDateExpressions(expr: string): string {
    const now = new Date();
    return expr
      .replace(/new\s+Date\(\)\.getTime\(\)(?:\.toString\(\))?/g, String(now.getTime()))
      .replace(/new\s+Date\(\)\.getMinutes\(\)(?:\.toString\(\))?/g, String(now.getMinutes()))
      .replace(/new\s+Date\(\)\.getHours\(\)(?:\.toString\(\))?/g, String(now.getHours()))
      .replace(/new\s+Date\(\)\.getDate\(\)(?:\.toString\(\))?/g, String(now.getDate()))
      .replace(/new\s+Date\(\)\.getMonth\(\)(?:\.toString\(\))?/g, String(now.getMonth()))
      .replace(/new\s+Date\(\)\.getFullYear\(\)(?:\.toString\(\))?/g, String(now.getFullYear()))
      .replace(/new\s+Date\(\)(?:\.toString\(\))?/g, String(now.getTime()));
  }

  private replaceFunctionCalls(expr: string, name: string, mapper: (arg: string) => string): string {
    let result = expr;
    let start = this.indexOfFunctionCall(result, name);
    while (start >= 0) {
      const openIndex = start + name.length;
      const closeIndex = this.findMatchingParen(result, openIndex);
      if (closeIndex < 0) break;
      const arg = result.substring(openIndex + 1, closeIndex);
      result = result.substring(0, start) + mapper(arg) + result.substring(closeIndex + 1);
      start = this.indexOfFunctionCall(result, name);
    }
    return result;
  }

  private indexOfFunctionCall(text: string, name: string): number {
    let start = text.indexOf(`${name}(`);
    while (start >= 0) {
      const prev = start > 0 ? text.charAt(start - 1) : '';
      if (!/[A-Za-z0-9_.$]/.test(prev)) return start;
      start = text.indexOf(`${name}(`, start + 1);
    }
    return -1;
  }

  private replaceNoArgCalls(expr: string): string {
    return expr
      .replace(/\bjava\.androidId\(\)/g, this.androidId())
      .replace(/\bjava\.randomUUID\(\)/g, this.randomUuid())
      .replace(/\bDate\.now\(\)/g, String(Date.now()));
  }

  private replaceGetStringListCalls(expr: string): string {
    let result = expr;
    let start = this.indexOfFunctionCall(result, 'java.getStringList');
    while (start >= 0) {
      const openIndex = start + 'java.getStringList'.length;
      const closeIndex = this.findMatchingParen(result, openIndex);
      if (closeIndex < 0) break;
      const arg = result.substring(openIndex + 1, closeIndex);
      let end = closeIndex + 1;
      let replacement = this.quoteString(this.javaGetStringListCall(arg).join(','));

      const tail = result.substring(end);
      const joinMatch = tail.match(/^\s*\.join\s*\(\s*([\s\S]*?)\s*\)/);
      const toArrayJoinMatch = tail.match(/^\s*\.toArray\s*\(\s*\)\s*\.join\s*\(\s*([\s\S]*?)\s*\)/);
      const mapJoinMatch = tail.match(/^\s*\.toArray\s*\(\s*\)\s*\.map\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*=>\s*([\s\S]+?)\)\s*\.join\s*\(\s*([\s\S]*?)\s*\)/);
      if (mapJoinMatch) {
        end += mapJoinMatch[0].length;
        const values = this.javaGetStringListCall(arg);
        const mapped: string[] = [];
        for (const value of values) mapped.push(this.evalArrowExpression(mapJoinMatch[2], mapJoinMatch[1], value));
        replacement = this.quoteString(mapped.join(this.evalStr(mapJoinMatch[3])));
      } else if (toArrayJoinMatch) {
        end += toArrayJoinMatch[0].length;
        replacement = this.quoteString(this.javaGetStringListCall(arg).join(this.evalStr(toArrayJoinMatch[1])));
      } else if (joinMatch) {
        end += joinMatch[0].length;
        replacement = this.quoteString(this.javaGetStringListCall(arg).join(this.evalStr(joinMatch[1])));
      }

      result = result.substring(0, start) + replacement + result.substring(end);
      start = this.indexOfFunctionCall(result, 'java.getStringList');
    }
    return result;
  }

  private javaGetStringCall(rawArgs: string): string {
    const args = this.splitArgs(rawArgs);
    const key = this.evalStr(args[0] || '');
    const values = this.readJsonValues(key);
    if (values.length === 0) return '';
    return this.jsonValueToString(values[0]);
  }

  private javaGetStringListCall(rawArgs: string): string[] {
    const args = this.splitArgs(rawArgs);
    const key = this.evalStr(args[0] || '');
    return this.readJsonValues(key).map(value => this.jsonValueToString(value));
  }

  private readJsonValues(pathOrKey: string): Object[] {
    const data = this.jsonContext;
    if (!data || !pathOrKey) return [];
    const key = this.normalizeJsonPath(pathOrKey.trim());
    if (key.startsWith('$') || key.startsWith('@.')) {
      return JsonPathEvaluator.evaluate(data, key.startsWith('@.') ? '$.' + key.substring(2) : key);
    }
    const direct = (data as Record<string, Object>)[key];
    if (direct !== undefined && direct !== null) return [direct];
    const deep: Object[] = [];
    this.deepRead(data, key, deep);
    return deep;
  }

  private normalizeJsonPath(path: string): string {
    return (path || '').replace(/\[(\*|\d+)\]([A-Za-z_$][A-Za-z0-9_$-]*)/g, '[$1].$2');
  }

  private deepRead(value: Object, key: string, out: Object[]): void {
    if (!value || typeof value !== 'object') return;
    if (Array.isArray(value)) {
      for (const item of value as Object[]) this.deepRead(item, key, out);
      return;
    }
    const record = value as Record<string, Object>;
    if (record[key] !== undefined && record[key] !== null) out.push(record[key]);
    for (const childKey in record) this.deepRead(record[childKey], key, out);
  }

  private jsonValueToString(value: Object): string {
    if (value === undefined || value === null) return '';
    return typeof value === 'string' ? value as string : JSON.stringify(value);
  }

  private evalArrowExpression(expr: string, name: string, value: string): string {
    const marker = new RegExp('\\b' + name + '\\b', 'g');
    return this.evalStr(expr.replace(marker, this.quoteString(value)));
  }

  private quoteString(value: string): string {
    return `"${(value || '').replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  }

  private applyCookieSideEffects(expr: string): void {
    const setRe = /\bcookie\.setCookie\(\s*([^,]+)\s*,\s*([^)]+)\)/g;
    let setMatch: RegExpExecArray | null;
    while ((setMatch = setRe.exec(expr)) !== null) {
      CookieStore.setCookies(this.evalStr(setMatch[1]), this.evalStr(setMatch[2]));
      CookieStore.saveAsync();
    }

    const removeRe = /\bcookie\.removeCookie\(\s*([^)]+)\)/g;
    let removeMatch: RegExpExecArray | null;
    while ((removeMatch = removeRe.exec(expr)) !== null) {
      const args = this.splitArgs(removeMatch[1]);
      const url = this.evalStr(args[0] || '');
      const name = args.length > 1 ? this.evalStr(args[1]) : '';
      CookieStore.removeCookie(url, name || undefined);
    }
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
      if (ch === ')') {
        depth--;
        if (depth === 0) return i;
      }
    }
    return -1;
  }

  private splitConcat(expr: string): string[] {
    const parts: string[] = [];
    let depth = 0;
    let quote = '';
    let start = 0;
    for (let i = 0; i < expr.length; i++) {
      const ch = expr.charAt(i);
      if (quote) {
        if (ch === quote && expr.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '(') depth++;
      if (ch === ')') depth--;
      if (ch === '+' && depth === 0) {
        parts.push(expr.substring(start, i).trim());
        start = i + 1;
      }
    }
    parts.push(expr.substring(start).trim());
    return parts;
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

  private stripQuotes(value: string): string {
    const v = value.trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      return v.substring(1, v.length - 1);
    }
    return v;
  }

  private evalNumber(expr: string): number {
    const values: number[] = [];
    const ops: string[] = [];
    const text = expr.replace(/\s+/g, '');
    let i = 0;
    while (i < text.length) {
      const ch = text.charAt(i);
      if ((ch >= '0' && ch <= '9') || ch === '.' ||
        (ch === '-' && (i === 0 || this.isOperator(text.charAt(i - 1)) || text.charAt(i - 1) === '('))) {
        let j = i + 1;
        while (j < text.length && /[\d.]/.test(text.charAt(j))) j++;
        values.push(Number(text.substring(i, j)));
        i = j;
        continue;
      }
      if (ch === '(') ops.push(ch);
      else if (ch === ')') {
        while (ops.length > 0 && ops[ops.length - 1] !== '(') this.applyNumberOp(values, ops.pop() || '');
        if (ops.length > 0) ops.pop();
      } else if (this.isOperator(ch)) {
        while (ops.length > 0 && this.precedence(ops[ops.length - 1]) >= this.precedence(ch)) {
          this.applyNumberOp(values, ops.pop() || '');
        }
        ops.push(ch);
      }
      i++;
    }
    while (ops.length > 0) this.applyNumberOp(values, ops.pop() || '');
    return values.length > 0 && !Number.isNaN(values[0]) ? values[0] : 0;
  }

  private isOperator(ch: string): boolean {
    return ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '%';
  }

  private precedence(op: string): number {
    return op === '+' || op === '-' ? 1 : op === '*' || op === '/' || op === '%' ? 2 : 0;
  }

  private applyNumberOp(values: number[], op: string): void {
    if (values.length < 2) return;
    const b = values.pop() as number;
    const a = values.pop() as number;
    if (op === '+') values.push(a + b);
    if (op === '-') values.push(a - b);
    if (op === '*') values.push(a * b);
    if (op === '/') values.push(b === 0 ? 0 : a / b);
    if (op === '%') values.push(b === 0 ? 0 : a % b);
  }

  private base64(input: string): string {
    try {
      const e = new util.TextEncoder();
      return new util.Base64Helper().encodeToStringSync(e.encodeInto(input));
    } catch (_) { return input; }
  }

  private base64Decode(input: string): string {
    try {
      const data = new util.Base64Helper().decodeSync(input);
      return util.TextDecoder.create('utf-8').decodeWithStream(data, { stream: false });
    } catch (_) { return input; }
  }

  private hexDecodeToString(input: string): string {
    try {
      const clean = input.replace(/^0x/i, '').replace(/\s+/g, '');
      const bytes: number[] = [];
      for (let i = 0; i < clean.length; i += 2) {
        bytes.push(parseInt(clean.substring(i, i + 2), 16));
      }
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(bytes), { stream: false });
    } catch (_) { return input; }
  }

  private splitStatements(expr: string): string[] {
    return this.splitTopLevel(expr, [';']);
  }

  private splitTopLevel(expr: string, separators: string[]): string[] {
    const parts: string[] = [];
    let depth = 0;
    let quote = '';
    let regex = false;
    let start = 0;
    for (let i = 0; i < expr.length; i++) {
      const ch = expr.charAt(i);
      if (regex) {
        if (ch === '/' && expr.charAt(i - 1) !== '\\') regex = false;
        continue;
      }
      if (quote) {
        if (ch === quote && expr.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '/' && this.isRegexStart(expr, i)) { regex = true; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && separators.includes(ch)) {
        const part = expr.substring(start, i).trim();
        if (part) parts.push(part);
        start = i + 1;
      }
    }
    const last = expr.substring(start).trim();
    if (last) parts.push(last);
    return parts;
  }

  private indexOfTopLevelAssignment(expr: string): number {
    let depth = 0;
    let quote = '';
    let regex = false;
    for (let i = 0; i < expr.length; i++) {
      const ch = expr.charAt(i);
      if (regex) {
        if (ch === '/' && expr.charAt(i - 1) !== '\\') regex = false;
        continue;
      }
      if (quote) {
        if (ch === quote && expr.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '/' && this.isRegexStart(expr, i)) { regex = true; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && ch === '=') {
        const prev = i > 0 ? expr.charAt(i - 1) : '';
        const next = i + 1 < expr.length ? expr.charAt(i + 1) : '';
        if (prev !== '=' && prev !== '!' && prev !== '>' && prev !== '<' && next !== '=' && next !== '>') return i;
      }
    }
    return -1;
  }

  private isRegexStart(expr: string, index: number): boolean {
    let i = index - 1;
    while (i >= 0 && /\s/.test(expr.charAt(i))) i--;
    if (i < 0) return true;
    return '([{=,:?;!&|'.includes(expr.charAt(i));
  }

  private hexEncodeToString(input: string): string {
    try {
      const bytes = new util.TextEncoder().encodeInto(input);
      let value = '';
      for (let i = 0; i < bytes.length; i++) value += bytes[i].toString(16).padStart(2, '0');
      return value;
    } catch (_) { return input; }
  }

  private urlDecode(input: string): string {
    try { return decodeURIComponent(input.replace(/\+/g, '%20')); } catch (_) { return input; }
  }

  private md5(input: string): string {
    return this.digest('MD5', input);
  }

  private digest(algorithm: string, input: string): string {
    try {
      const md = cryptoFramework.createMd(algorithm);
      const e = new util.TextEncoder();
      md.updateSync({ data: e.encodeInto(input) });
      const r = md.digestSync();
      let hex = '';
      for (let i = 0; i < r.data.length; i++) {
        const b = r.data[i];
        hex += (b < 16 ? '0' : '') + b.toString(16);
      }
      return hex;
    } catch (_) { return input; }
  }

  private timeFormat(timestamp: number): string {
    if (!timestamp || Number.isNaN(timestamp)) return '';
    const millis = timestamp < 100000000000 ? timestamp * 1000 : timestamp;
    const date = new Date(millis);
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value);
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  }

  private timeFormatCall(rawArgs: string): string {
    const args = this.splitArgs(rawArgs);
    const timestamp = this.evalNumber(this.evalStr(args[0] || ''));
    if (args.length < 2) return this.timeFormat(timestamp);
    const millis = timestamp < 100000000000 ? timestamp * 1000 : timestamp;
    const date = new Date(millis);
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value);
    return this.evalStr(args[1])
      .replace(/yyyy/g, String(date.getFullYear()))
      .replace(/MM/g, pad(date.getMonth() + 1))
      .replace(/dd/g, pad(date.getDate()))
      .replace(/HH/g, pad(date.getHours()))
      .replace(/mm/g, pad(date.getMinutes()))
      .replace(/ss/g, pad(date.getSeconds()));
  }

  private cookieValue(rawArgs: string): string {
    const args = this.splitArgs(rawArgs);
    const url = this.evalStr(args[0] || '');
    const name = args.length > 1 ? this.evalStr(args[1]) : '';
    return name ? CookieStore.getCookieValue(url, name) : CookieStore.getCookie(url);
  }

  private putVar(rawArgs: string): string {
    const args = this.splitArgs(rawArgs);
    const key = this.evalStr(args[0] || '');
    const value = this.evalStr(args[1] || '');
    if (key) this.setVar(key, value);
    return value;
  }

  private getVarCall(rawArgs: string): string {
    const args = this.splitArgs(rawArgs);
    const key = this.evalStr(args[0] || '');
    return this.getVar(key);
  }

  private androidId(): string {
    return 'legado_harmony_' + this.md5('legado-harmony').substring(0, 16);
  }

  private randomUuid(): string {
    const seed = `${Date.now()}${Math.random()}`;
    const hex = this.md5(seed);
    return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}`;
  }

  aesBase64DecodeToString(data: string, key: string, iv: string, transformation: string = 'AES/CBC/PKCS5Padding'): string {
    return this.symmetricBase64(data, key, transformation, iv, false);
  }

  private evalAes(rawArgs: string, encrypt: boolean): string {
    const args = this.splitArgs(rawArgs);
    return this.symmetricBase64(
      this.evalStr(args[0] || ''), this.evalStr(args[1] || ''),
      this.evalStr(args[2] || 'AES/CBC/PKCS5Padding'), this.evalStr(args[3] || ''), encrypt
    );
  }

  private evalDes(rawArgs: string, encrypt: boolean): string {
    const args = this.splitArgs(rawArgs);
    return this.symmetricBase64(
      this.evalStr(args[0] || ''), this.evalStr(args[1] || ''),
      this.evalStr(args[2] || 'DES/CBC/PKCS5Padding'), this.evalStr(args[3] || ''), encrypt
    );
  }

  private symmetricBase64(data: string, key: string, transformation: string, iv: string, encrypt: boolean): string {
    try {
      const textEncoder = new util.TextEncoder();
      const textDecoder = util.TextDecoder.create('utf-8');
      const base64 = new util.Base64Helper();
      const upper = transformation.toUpperCase();
      const isTripleDes = upper.startsWith('DESEDE') || upper.startsWith('3DES') || upper.startsWith('TRIPLEDES');
      const isDes = !isTripleDes && upper.startsWith('DES');
      const mode = upper.includes('/ECB/') ? 'ECB' : 'CBC';
      const padding = upper.includes('NOPADDING') ? 'NoPadding' : upper.includes('PKCS7') ? 'PKCS7' : 'PKCS5';
      const rawKey = textEncoder.encodeInto(key);
      const keyLength = isTripleDes ? 24 : isDes ? 8 : (rawKey.length >= 32 ? 32 : rawKey.length >= 24 ? 24 : 16);
      const keyAlgorithm = isTripleDes ? '3DES192' : isDes ? 'DES' : `AES${keyLength * 8}`;
      const keyGen = cryptoFramework.createSymKeyGenerator(keyAlgorithm);
      const symKey = keyGen.convertKeySync({ data: this.fixedBytes(rawKey, keyLength) });
      const cipherName = isTripleDes ? `${keyAlgorithm}|${mode}|${padding}` :
        isDes ? `${keyAlgorithm}|${mode}|${padding}` : `${keyAlgorithm}|${mode}|${padding}`;
      const cipher = cryptoFramework.createCipher(cipherName);
      const params: cryptoFramework.IvParamsSpec | null = mode === 'ECB' ? null : {
        algName: 'IvParamsSpec',
        iv: { data: this.fixedBytes(textEncoder.encodeInto(iv), (isDes || isTripleDes) ? 8 : 16) }
      };
      cipher.initSync(encrypt ? cryptoFramework.CryptoMode.ENCRYPT_MODE : cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
      const input = encrypt ? textEncoder.encodeInto(data) : base64.decodeSync(data);
      const outBlob = cipher.doFinalSync({ data: input });
      return encrypt ? base64.encodeToStringSync(outBlob.data) : textDecoder.decodeWithStream(outBlob.data, { stream: false });
    } catch (e) {
      console.error('[JsRuntime] 对称加解密失败:', JSON.stringify(e));
      return '';
    }
  }

  private fixedBytes(bytes: Uint8Array, length: number): Uint8Array {
    const result = new Uint8Array(length);
    for (let i = 0; i < length; i++) result[i] = i < bytes.length ? bytes[i] : 0;
    return result;
  }
}
