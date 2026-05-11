import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class JsEvaluator {
  private variables: Record<string, string> = {};

  setVariable(key: string, value: string): void {
    this.variables[key] = value;
  }

  evalTemplate(template: string): string {
    if (!template.includes('{{')) return template;

    return template.replace(/\{\{([^}]+)\}\}/g, (_: string, expr: string) => {
      return this.evalExpression(expr.trim());
    });
  }

  private evalExpression(expr: string): string {
    try {
      expr = this.replaceDateExpressions(expr);

      expr = expr.replace(/Date\.now\(\)/g, String(Date.now()));

      expr = this.replaceFunctionCalls(expr, 'Math.round', (val: string) => {
        return String(Math.round(this.evalNumber(val)));
      });

      expr = this.replaceFunctionCalls(expr, 'Math.floor', (val: string) => {
        return String(Math.floor(this.evalNumber(val)));
      });

      expr = this.replaceFunctionCalls(expr, 'Math.ceil', (val: string) => {
        return String(Math.ceil(this.evalNumber(val)));
      });

      expr = this.replaceFunctionCalls(expr, 'java.base64Encode', (val: string) => {
        return this.base64Encode(this.evalString(val));
      });

      expr = this.replaceFunctionCalls(expr, 'java.md5Encode', (val: string) => {
        return this.md5Encode(this.evalString(val));
      });

      expr = this.replaceFunctionCalls(expr, 'java.base64Decode', (val: string) => {
        return this.base64Decode(this.evalString(val));
      });

      expr = this.replaceFunctionCalls(expr, 'encodeURIComponent', (val: string) => {
        return encodeURIComponent(this.evalString(val));
      });

      // 处理变量替换: key, page
      for (const key in this.variables) {
        const value = this.variables[key];
        const replacement = value.match(/^-?\d+(\.\d+)?$/) ? value : `"${value}"`;
        expr = expr.replace(new RegExp('\\b' + key + '\\b', 'g'), replacement);
      }

      const numericExpr = expr.match(/^[\d\s+\-*/%.()]+$/);
      if (numericExpr) {
        return String(this.evalNumber(expr));
      }

      // 字符串拼接: "a"+"b" → "ab"
      expr = expr.replace(/"([^"]*)"\s*\+\s*"([^"]*)"/g, '"$1$2"');

      // 字符串拼接: "a"+var+"b" → "a"value"b"
      expr = expr.replace(/"([^"]*)"\s*\+\s*(\w+)\s*\+\s*"([^"]*)"/g, '"$1$2$3"');

      // 移除引号
      expr = expr.replace(/^"|"$/g, '');

      return expr;
    } catch (e) {
      console.error('JS表达式求值失败:', expr, e);
      return expr;
    }
  }

  private evalSimple(expr: string): string {
    try {
      expr = this.replaceDateExpressions(expr);
      expr = expr.replace(/Date\.now\(\)/g, String(Date.now()));

      const numExpr = expr.match(/^[\d\s+\-*/%.]+$/);
      if (numExpr) {
        return String(this.evalNumber(expr));
      }
      return expr;
    } catch (e) {
      return expr;
    }
  }

  private evalString(expr: string): string {
    let val = expr.trim();
    val = this.replaceDateExpressions(val);
    val = val.replace(/Date\.now\(\)/g, String(Date.now()));

    const parts = this.splitConcat(val);
    if (parts.length > 1) {
      return parts.map((part: string) => this.evalString(part)).join('');
    }

    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.substring(1, val.length - 1);
    }

    for (const key in this.variables) {
      val = val.replace(new RegExp('\\b' + key + '\\b', 'g'), this.variables[key]);
    }
    return val;
  }

  private replaceDateExpressions(expr: string): string {
    const now = new Date();
    return expr
      .replace(/new Date\(\)\.getTime\(\)(?:\.toString\(\))?/g, String(now.getTime()))
      .replace(/new Date\(\)\.getMinutes\(\)(?:\.toString\(\))?/g, String(now.getMinutes()))
      .replace(/new Date\(\)\.getHours\(\)(?:\.toString\(\))?/g, String(now.getHours()))
      .replace(/new Date\(\)\.getDate\(\)(?:\.toString\(\))?/g, String(now.getDate()))
      .replace(/new Date\(\)\.getMonth\(\)(?:\.toString\(\))?/g, String(now.getMonth()))
      .replace(/new Date\(\)\.getFullYear\(\)(?:\.toString\(\))?/g, String(now.getFullYear()))
      .replace(/new Date\(\)(?:\.toString\(\))?/g, String(now.getTime()));
  }

  private replaceFunctionCalls(expr: string, name: string, mapper: (arg: string) => string): string {
    let result = expr;
    let start = result.indexOf(`${name}(`);
    while (start >= 0) {
      const openIndex = start + name.length;
      const closeIndex = this.findMatchingParen(result, openIndex);
      if (closeIndex < 0) {
        break;
      }
      const arg = result.substring(openIndex + 1, closeIndex);
      const replacement = mapper(arg);
      result = result.substring(0, start) + replacement + result.substring(closeIndex + 1);
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
        if (ch === quote && text.charAt(i - 1) !== '\\') {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === '(') {
        depth++;
      } else if (ch === ')') {
        depth--;
        if (depth === 0) {
          return i;
        }
      }
    }
    return -1;
  }

  private splitConcat(expr: string): string[] {
    const parts: string[] = [];
    let quote = '';
    let depth = 0;
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

      if (ch === '(') {
        ops.push(ch);
      } else if (ch === ')') {
        while (ops.length > 0 && ops[ops.length - 1] !== '(') {
          this.applyNumberOp(values, ops.pop() || '');
        }
        if (ops.length > 0) ops.pop();
      } else if (this.isOperator(ch)) {
        while (ops.length > 0 && this.precedence(ops[ops.length - 1]) >= this.precedence(ch)) {
          this.applyNumberOp(values, ops.pop() || '');
        }
        ops.push(ch);
      }
      i++;
    }

    while (ops.length > 0) {
      this.applyNumberOp(values, ops.pop() || '');
    }

    return values.length > 0 && !Number.isNaN(values[0]) ? values[0] : 0;
  }

  private isOperator(ch: string): boolean {
    return ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '%' ;
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

  private base64Encode(input: string): string {
    try {
      const textEncoder = new util.TextEncoder();
      const uint8Arr = textEncoder.encodeInto(input);
      const helper = new util.Base64Helper();
      return helper.encodeToStringSync(uint8Arr);
    } catch (e) {
      return input;
    }
  }

  private base64Decode(input: string): string {
    try {
      const textDecoder = util.TextDecoder.create('utf-8');
      const helper = new util.Base64Helper();
      const uint8Arr = helper.decodeSync(input);
      return textDecoder.decodeWithStream(uint8Arr, { stream: false });
    } catch (e) {
      return input;
    }
  }

  private md5Encode(input: string): string {
    try {
      const md = cryptoFramework.createMd('MD5');
      const textEncoder = new util.TextEncoder();
      const dataBlob: cryptoFramework.DataBlob = { data: textEncoder.encodeInto(input) };
      md.updateSync(dataBlob);
      const result = md.digestSync();
      // 转16进制字符串
      return this.toHex(result.data);
    } catch (e) {
      console.error('MD5失败:', e);
      return input;
    }
  }

  private toHex(data: Uint8Array): string {
    const hexChars = '0123456789abcdef';
    let result = '';
    for (let i = 0; i < data.length; i++) {
      const byte = data[i];
      result += hexChars.charAt((byte >> 4) & 0x0f);
      result += hexChars.charAt(byte & 0x0f);
    }
    return result;
  }
}
