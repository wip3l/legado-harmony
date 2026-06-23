export interface DirectAjaxRulePlan {
  urlRule: string;
  jsCode: string;
}

export class AjaxRuleCompat {
  static directResultPlan(rule: string): DirectAjaxRulePlan | null {
    if (!rule || !/java\.ajax\(\s*result\s*\)/.test(rule)) return null;
    const jsIndex = rule.indexOf('@js:');
    if (jsIndex <= 0) return null;
    const urlRule = rule.substring(0, jsIndex).trim();
    if (!urlRule) return null;
    return { urlRule: urlRule, jsCode: rule.substring(jsIndex + 4) };
  }

  static applyReplaceChain(value: string, jsCode: string): string {
    let result = value || '';
    const replaceRe = /\.replace\(\s*\/((?:\\\/|[^/])*)\/([gimsuy]*)\s*,\s*(["'])([\s\S]*?)\3\s*\)/g;
    let match: RegExpExecArray | null;
    while ((match = replaceRe.exec(jsCode || '')) !== null) {
      try {
        const flags = match[2].includes('g') ? match[2] : match[2] + 'g';
        result = result.replace(new RegExp(match[1].replace(/\\\//g, '/'), flags), match[4]);
      } catch (_) {}
    }
    return result;
  }
}
