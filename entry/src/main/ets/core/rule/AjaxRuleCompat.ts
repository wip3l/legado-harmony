export interface DirectAjaxRulePlan {
  urlRule: string;
  jsCode: string;
  ajaxAll: boolean;
}

export class AjaxRuleCompat {
  static directResultPlan(rule: string): DirectAjaxRulePlan | null {
    if (!rule || !/java\.ajax(?:All)?\(\s*result\s*\)/.test(rule)) return null;
    const jsIndex = rule.indexOf('@js:');
    if (jsIndex <= 0) return null;
    const urlRule = rule.substring(0, jsIndex).trim();
    if (!urlRule) return null;
    const jsCode = rule.substring(jsIndex + 4);
    return { urlRule: urlRule, jsCode: jsCode, ajaxAll: /java\.ajaxAll\(\s*result\s*\)/.test(jsCode) };
  }

  static applyReplaceChain(value: string, jsCode: string): string {
    let result = value || '';
    const jsonValue = this.applyJsonParseAccess(result, jsCode);
    if (jsonValue !== null) result = jsonValue;

    const matchValue = this.applyMatchAccess(result, jsCode);
    if (matchValue !== null) result = matchValue;

    const replaceRe = /\.replace\(\s*([^,]+)\s*,\s*(["'])([\s\S]*?)\2\s*\)/g;
    let match: RegExpExecArray | null;
    while ((match = replaceRe.exec(jsCode || '')) !== null) {
      try {
        const pattern = this.parseReplacePattern(match[1]);
        if (pattern) result = result.replace(pattern, match[3]);
      } catch (_) {}
    }
    return result;
  }

  private static parseReplacePattern(raw: string): RegExp | null {
    const text = (raw || '').trim();
    const re = text.match(/^\/((?:\\\/|[^/])*)\/([gimsuy]*)$/);
    if (re) {
      const flags = re[2].includes('g') ? re[2] : re[2] + 'g';
      return new RegExp(re[1].replace(/\\\//g, '/'), flags);
    }
    const literal = text.match(/^(["'])([\s\S]*?)\1$/);
    if (literal) return new RegExp(this.escapeRegex(literal[2]), 'g');
    return null;
  }

  private static applyMatchAccess(value: string, jsCode: string): string | null {
    const match = (jsCode || '').match(/(?:java\.ajax(?:All)?\(\s*result\s*\)|String\(\s*java\.ajax(?:All)?\(\s*result\s*\)\s*\)|result)\.match\(\s*(\/(?:\\\/|[^/])*\/[gimsuy]*)\s*\)\s*\[\s*(\d+)\s*\]/);
    if (!match) return null;
    try {
      const parsed = match[1].match(/^\/((?:\\\/|[^/])*)\/([gimsuy]*)$/);
      if (!parsed) return null;
      const found = value.match(new RegExp(parsed[1].replace(/\\\//g, '/'), parsed[2].replace('g', '')));
      const index = parseInt(match[2]);
      return found && found[index] !== undefined ? found[index] : '';
    } catch (_) {
      return null;
    }
  }

  private static applyJsonParseAccess(value: string, jsCode: string): string | null {
    const match = (jsCode || '').match(/JSON\.parse\(\s*(?:String\(\s*)?java\.ajax(?:All)?\(\s*result\s*\)\s*\)?\s*\)((?:\.[A-Za-z_$][A-Za-z0-9_$]*|\[['"][^'"]+['"]\])*)/);
    if (!match || !match[1]) return null;
    try {
      let current: Object | string | number | boolean | null = JSON.parse(value || '{}') as Object;
      const path = match[1];
      const partRe = /\.([A-Za-z_$][A-Za-z0-9_$]*)|\[['"]([^'"]+)['"]\]/g;
      let part: RegExpExecArray | null;
      while ((part = partRe.exec(path)) !== null) {
        const key = part[1] || part[2];
        if (!current || typeof current !== 'object') return '';
        current = (current as Record<string, Object | string | number | boolean | null>)[key];
      }
      if (current === undefined || current === null) return '';
      return typeof current === 'string' ? current : JSON.stringify(current);
    } catch (_) {
      return null;
    }
  }

  private static escapeRegex(value: string): string {
    return (value || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
}
