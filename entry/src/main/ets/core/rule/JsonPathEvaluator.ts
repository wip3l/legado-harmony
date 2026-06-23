interface JsonPathToken {
  kind: string;
  name: string;
  names: string[];
  indexes: number[];
  start: number | null;
  end: number | null;
  step: number;
  expression: string;
}

export class JsonPathEvaluator {
  static evaluate(root: Object, path: string): Object[] {
    const value = (path || '').trim();
    if (!value) return [];
    const tokens = this.tokenize(value);
    if (tokens.length === 0 && (value === '$' || value === '@')) return [root];
    if (tokens.length === 0) return [];

    let current: Object[] = [root];
    for (const token of tokens) {
      current = this.applyToken(current, token);
      if (current.length === 0) break;
    }
    return current;
  }

  private static tokenize(path: string): JsonPathToken[] {
    const tokens: JsonPathToken[] = [];
    let i = path.startsWith('$') || path.startsWith('@') ? 1 : 0;
    while (i < path.length) {
      if (/\s/.test(path.charAt(i))) { i++; continue; }
      if (path.substring(i, i + 2) === '..') {
        i += 2;
        if (path.charAt(i) === '*') {
          tokens.push(this.token('recursiveWildcard'));
          i++;
          continue;
        }
        if (path.charAt(i) === '[') {
          const close = this.findBracket(path, i);
          if (close < 0) return [];
          const inner = path.substring(i + 1, close).trim();
          const names = this.parseNames(inner);
          if (names.length === 0) return [];
          const token = this.token('recursiveProperty');
          token.names = names;
          tokens.push(token);
          i = close + 1;
          continue;
        }
        const read = this.readName(path, i);
        if (!read.name) return [];
        const token = this.token('recursiveProperty');
        token.names = [read.name];
        tokens.push(token);
        i = read.end;
        continue;
      }
      if (path.charAt(i) === '.') {
        i++;
        if (path.charAt(i) === '[') continue;
        if (path.charAt(i) === '*') {
          tokens.push(this.token('wildcard'));
          i++;
          continue;
        }
        const read = this.readName(path, i);
        if (!read.name) return [];
        const token = this.token('property');
        token.name = read.name;
        tokens.push(token);
        i = read.end;
        continue;
      }
      if (path.charAt(i) === '[') {
        const close = this.findBracket(path, i);
        if (close < 0) return [];
        const token = this.parseBracket(path.substring(i + 1, close).trim());
        if (!token) return [];
        tokens.push(token);
        i = close + 1;
        continue;
      }
      const read = this.readName(path, i);
      if (!read.name) return [];
      const token = this.token('property');
      token.name = read.name;
      tokens.push(token);
      i = read.end;
    }
    return tokens;
  }

  private static token(kind: string): JsonPathToken {
    return { kind: kind, name: '', names: [], indexes: [], start: null, end: null, step: 1, expression: '' };
  }

  private static readName(path: string, start: number): { name: string, end: number } {
    let i = start;
    while (i < path.length && !/[.\[\]\s]/.test(path.charAt(i))) i++;
    return { name: path.substring(start, i), end: i };
  }

  private static findBracket(path: string, start: number): number {
    let depth = 0;
    let quote = '';
    for (let i = start; i < path.length; i++) {
      const ch = path.charAt(i);
      if (quote) {
        if (ch === quote && path.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '[' || ch === '(') depth++;
      if (ch === ']' || ch === ')') {
        depth--;
        if (depth === 0) return i;
      }
    }
    return -1;
  }

  private static parseBracket(inner: string): JsonPathToken | null {
    if (inner === '*') return this.token('wildcard');
    if (inner.startsWith('?(') && inner.endsWith(')')) {
      const token = this.token('filter');
      token.expression = inner.substring(2, inner.length - 1).trim();
      return token;
    }
    if (inner.includes(':') && /^\s*-?\d*\s*:\s*-?\d*(?:\s*:\s*-?\d+)?\s*$/.test(inner)) {
      const parts = inner.split(':');
      const token = this.token('slice');
      token.start = parts[0].trim() ? parseInt(parts[0]) : null;
      token.end = parts[1].trim() ? parseInt(parts[1]) : null;
      token.step = parts.length > 2 && parseInt(parts[2]) !== 0 ? parseInt(parts[2]) : 1;
      return token;
    }
    const names = this.parseNames(inner);
    if (names.length > 0) {
      const token = this.token(names.length === 1 ? 'property' : 'properties');
      token.name = names[0];
      token.names = names;
      return token;
    }
    if (/^\s*-?\d+(?:\s*,\s*-?\d+)*\s*$/.test(inner)) {
      const token = this.token('indexes');
      token.indexes = inner.split(',').map(value => parseInt(value.trim()));
      return token;
    }
    return null;
  }

  private static parseNames(inner: string): string[] {
    if (!/^\s*(['"])[\s\S]*\1\s*(?:,\s*(['"])[\s\S]*\2\s*)*$/.test(inner)) return [];
    const names: string[] = [];
    const re = /(['"])((?:\\.|(?!\1)[\s\S])*)\1/g;
    let match: RegExpExecArray | null;
    while ((match = re.exec(inner)) !== null) names.push(match[2].replace(/\\(['"\\])/g, '$1'));
    return names;
  }

  private static applyToken(values: Object[], token: JsonPathToken): Object[] {
    const out: Object[] = [];
    for (const value of values) {
      if (token.kind === 'property') this.readProperty(value, token.name, out);
      else if (token.kind === 'properties') {
        for (const name of token.names) this.readProperty(value, name, out);
      } else if (token.kind === 'recursiveProperty') {
        for (const name of token.names) this.deepRead(value, name, out);
      } else if (token.kind === 'wildcard') this.readWildcard(value, out);
      else if (token.kind === 'recursiveWildcard') this.deepWildcard(value, out);
      else if (token.kind === 'indexes') this.readIndexes(value, token.indexes, out);
      else if (token.kind === 'slice') this.readSlice(value, token.start, token.end, token.step, out);
      else if (token.kind === 'filter') this.readFilter(value, token.expression, out);
    }
    return out;
  }

  private static readProperty(value: Object, name: string, out: Object[]): void {
    if (Array.isArray(value)) {
      for (const item of value as Object[]) this.readProperty(item, name, out);
      return;
    }
    if (!value || typeof value !== 'object') return;
    const found = (value as Record<string, Object>)[name];
    if (found !== undefined && found !== null) out.push(found);
  }

  private static readWildcard(value: Object, out: Object[]): void {
    if (Array.isArray(value)) {
      out.push(...value as Object[]);
    } else if (value && typeof value === 'object') {
      const record = value as Record<string, Object>;
      for (const key in record) if (record[key] !== undefined && record[key] !== null) out.push(record[key]);
    }
  }

  private static deepRead(value: Object, name: string, out: Object[]): void {
    if (!value || typeof value !== 'object') return;
    if (Array.isArray(value)) {
      for (const item of value as Object[]) this.deepRead(item, name, out);
      return;
    }
    const record = value as Record<string, Object>;
    if (record[name] !== undefined && record[name] !== null) out.push(record[name]);
    for (const key in record) this.deepRead(record[key], name, out);
  }

  private static deepWildcard(value: Object, out: Object[]): void {
    if (!value || typeof value !== 'object') return;
    const children: Object[] = [];
    this.readWildcard(value, children);
    for (const child of children) {
      out.push(child);
      this.deepWildcard(child, out);
    }
  }

  private static readIndexes(value: Object, indexes: number[], out: Object[]): void {
    if (!Array.isArray(value)) return;
    const array = value as Object[];
    for (const raw of indexes) {
      const index = raw < 0 ? array.length + raw : raw;
      if (index >= 0 && index < array.length) out.push(array[index]);
    }
  }

  private static readSlice(value: Object, start: number | null, end: number | null, step: number, out: Object[]): void {
    if (!Array.isArray(value) || step === 0) return;
    const array = value as Object[];
    let from = start === null ? (step > 0 ? 0 : array.length - 1) : (start < 0 ? array.length + start : start);
    let to = end === null ? (step > 0 ? array.length : -1) : (end < 0 ? array.length + end : end);
    if (step > 0) {
      from = Math.max(0, from);
      to = Math.min(array.length, to);
      for (let i = from; i < to; i += step) out.push(array[i]);
    } else {
      from = Math.min(array.length - 1, from);
      to = Math.max(-1, to);
      for (let i = from; i > to; i += step) out.push(array[i]);
    }
  }

  private static readFilter(value: Object, expression: string, out: Object[]): void {
    const candidates = Array.isArray(value) ? value as Object[] : [value];
    for (const candidate of candidates) if (this.matchesFilter(candidate, expression)) out.push(candidate);
  }

  private static matchesFilter(value: Object, expression: string): boolean {
    const orParts = this.splitLogical(expression, '||');
    if (orParts.length > 1) return orParts.some(part => this.matchesFilter(value, part));
    const andParts = this.splitLogical(expression, '&&');
    if (andParts.length > 1) return andParts.every(part => this.matchesFilter(value, part));
    let expr = expression.trim();
    if (expr.startsWith('!')) return !this.matchesFilter(value, expr.substring(1));
    const match = expr.match(/^(@(?:\.[A-Za-z0-9_$-]+|\[['"][^'"]+['"]\])*)\s*(==|!=|>=|<=|>|<|=~)\s*([\s\S]+)$/);
    if (!match) return this.resolveFilterValue(value, expr) !== undefined;
    const left = this.resolveFilterValue(value, match[1]);
    const rightText = match[3].trim();
    if (match[2] === '=~') {
      const regex = rightText.match(/^\/([\s\S]*)\/([gimsuy]*)$/);
      if (!regex) return false;
      try { return new RegExp(regex[1], regex[2].replace('g', '')).test(String(left === undefined ? '' : left)); } catch (_) { return false; }
    }
    const right = this.parseLiteral(rightText);
    const leftNumber = Number(left);
    const rightNumber = Number(right);
    const numeric = left !== undefined && right !== undefined && !Number.isNaN(leftNumber) && !Number.isNaN(rightNumber);
    const a = numeric ? leftNumber : String(left === undefined ? '' : left);
    const b = numeric ? rightNumber : String(right === undefined ? '' : right);
    if (match[2] === '==') return a === b;
    if (match[2] === '!=') return a !== b;
    if (match[2] === '>') return a > b;
    if (match[2] === '<') return a < b;
    if (match[2] === '>=') return a >= b;
    return a <= b;
  }

  private static resolveFilterValue(value: Object, path: string): Object | string | number | boolean | undefined {
    const results = this.evaluate(value, path.trim());
    return results.length > 0 ? results[0] as Object | string | number | boolean : undefined;
  }

  private static parseLiteral(text: string): Object | string | number | boolean | undefined {
    const value = text.trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      return value.substring(1, value.length - 1);
    }
    if (value === 'true') return true;
    if (value === 'false') return false;
    if (value === 'null') return undefined;
    if (!Number.isNaN(Number(value))) return Number(value);
    return value;
  }

  private static splitLogical(expression: string, delimiter: string): string[] {
    const parts: string[] = [];
    let quote = '';
    let depth = 0;
    let start = 0;
    for (let i = 0; i <= expression.length - delimiter.length; i++) {
      const ch = expression.charAt(i);
      if (quote) {
        if (ch === quote && expression.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '(' || ch === '[') depth++;
      if (ch === ')' || ch === ']') depth--;
      if (depth === 0 && expression.substring(i, i + delimiter.length) === delimiter) {
        parts.push(expression.substring(start, i).trim());
        start = i + delimiter.length;
        i += delimiter.length - 1;
      }
    }
    parts.push(expression.substring(start).trim());
    return parts.filter(part => part.length > 0);
  }
}
