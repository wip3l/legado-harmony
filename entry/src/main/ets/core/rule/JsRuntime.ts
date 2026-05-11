import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export class JsRuntime {
  private vars: Record<string, string> = {};

  setVar(k: string, v: string): void { this.vars[k] = v; }
  getVar(k: string): string { return this.vars[k] || ''; }

  evalTemplate(tpl: string): string {
    if (!tpl.includes('{{')) return tpl;
    return tpl.replace(/\{\{([^}]+)\}\}/g, (_: string, expr: string) => this.evalExpr(expr.trim()));
  }

  private evalExpr(expr: string): string {
    try {
      expr = this.replaceDateExpressions(expr);
      expr = expr.replace(/Date\.now\(\)/g, String(Date.now()));

      expr = this.replaceFunctionCalls(expr, 'Math.round', (v: string) => String(Math.round(this.evalNumber(v))));
      expr = this.replaceFunctionCalls(expr, 'Math.floor', (v: string) => String(Math.floor(this.evalNumber(v))));
      expr = this.replaceFunctionCalls(expr, 'Math.ceil', (v: string) => String(Math.ceil(this.evalNumber(v))));

      expr = this.replaceFunctionCalls(expr, 'java.base64Encode', (v: string) => this.base64(this.evalStr(v)));
      expr = this.replaceFunctionCalls(expr, 'java.md5Encode', (v: string) => this.md5(this.evalStr(v)));
      expr = this.replaceFunctionCalls(expr, 'encodeURIComponent', (v: string) => encodeURIComponent(this.evalStr(v)));

      for (const k in this.vars) {
        const value = this.vars[k];
        const replacement = value.match(/^-?\d+(\.\d+)?$/) ? value : `"${value}"`;
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
    let start = result.indexOf(`${name}(`);
    while (start >= 0) {
      const openIndex = start + name.length;
      const closeIndex = this.findMatchingParen(result, openIndex);
      if (closeIndex < 0) break;
      const arg = result.substring(openIndex + 1, closeIndex);
      result = result.substring(0, start) + mapper(arg) + result.substring(closeIndex + 1);
      start = result.indexOf(`${name}(`);
    }
    return result;
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

  private md5(input: string): string {
    try {
      const md = cryptoFramework.createMd('MD5');
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

  aesBase64DecodeToString(data: string, key: string, iv: string): string {
    try {
      const textEncoder = new util.TextEncoder();
      const textDecoder = util.TextDecoder.create('utf-8');
      const base64 = new util.Base64Helper();

      // Base64 解码
      const dataBytes = base64.decodeSync(data);

      // Key: UTF-8 编码后填/截为 16 字节
      const keyRaw = textEncoder.encodeInto(key);
      const key16 = new Uint8Array(16);
      for (let i = 0; i < 16; i++) {
        key16[i] = i < keyRaw.length ? keyRaw[i] : 0;
      }

      // IV: UTF-8 编码后填/截为 16 字节
      const ivRaw = textEncoder.encodeInto(iv);
      const iv16 = new Uint8Array(16);
      for (let i = 0; i < 16; i++) {
        iv16[i] = i < ivRaw.length ? ivRaw[i] : 0;
      }

      // 创建对称密钥
      const keyGen = cryptoFramework.createSymKeyGenerator('AES128');
      const symKey = keyGen.convertKeySync({ data: key16 });

      // 创建 IV 参数
      const ivParams: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: iv16 }
      };

      // AES-CBC 解密
      const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS5');
      cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivParams);
      const outBlob = cipher.doFinalSync({ data: dataBytes });

      return textDecoder.decodeWithStream(outBlob.data, { stream: false });
    } catch (e) {
      console.error('[JsRuntime] AES解密失败:', JSON.stringify(e));
      return '';
    }
  }
}
