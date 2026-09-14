/**
 * 导入其它「阅读」实现的替换净化规则。
 *
 * 同一功能在不同实现里用了不同字段名，直接按本应用的字段读取会得到空 pattern，
 * 于是导入报「未找到有效的替换净化规则」。这里按别名把三种已知来源统一映射：
 *
 * - 本应用导出：pattern / replacement / isRegex / isEnabled / applyToTitle / applyToContent
 * - 阅读(Legado)导出：pattern / replacement / isRegex / isEnabled / isEnabledForTitle /
 *   isEnabledForContent / timeoutMillisecond / scope / excludeScope / order
 * - YueDu(阅读分支)的 Share/Rule.txt：regex / replacement / enable / replaceSummary /
 *   serialNumber / id（这类的 pattern 字段名就叫 regex，且没有名字字段）
 *
 * 只用别名匹配，不依赖字段顺序和多余字段；识别不了的条目计入 skipped，由调用方提示用户。
 */
export interface ImportedReplaceRule {
  id: number;
  name: string;
  group: string;
  pattern: string;
  replacement: string;
  isRegex: boolean;
  enabled: boolean;
  applyToTitle: boolean;
  applyToContent: boolean;
  scope: string;
  excludeScope: string;
  timeoutMs: number;
  /** 导入文件里的顺序（serialNumber/order），用于保持应用顺序；缺省时按数组下标。 */
  order: number;
}

export interface ReplaceRuleImportResult {
  rules: ImportedReplaceRule[];
  /** 识别出的来源，用于提示文案。 */
  formatLabel: string;
  /** 缺少可用匹配规则的条目数。 */
  skipped: number;
  /** 带正文范围条件（scopeContent）的条目数：本应用没有该字段，会被忽略，需要如实告知。 */
  ignoredContentScope: number;
}

export class ReplaceRuleImport {
  private static readonly PATTERN_KEYS = ['pattern', 'regex', 'matchRegex', 'match', 'rule', 'regular'];
  private static readonly REPLACEMENT_KEYS = ['replacement', 'replace', 'replaceWith', 'replaceText'];
  private static readonly NAME_KEYS = ['name', 'ruleName', 'title', 'replaceSummary'];
  private static readonly GROUP_KEYS = ['group', 'groupName', 'category'];
  private static readonly ENABLED_KEYS = ['enabled', 'enable', 'isEnabled', 'isEnable'];
  private static readonly TITLE_KEYS = ['applyToTitle', 'isEnabledForTitle', 'enabledForTitle'];
  private static readonly CONTENT_KEYS = ['applyToContent', 'isEnabledForContent', 'enabledForContent'];
  private static readonly REGEX_KEYS = ['isRegex', 'isRegEx', 'isRegexp', 'useRegex'];
  private static readonly TIMEOUT_KEYS = ['timeoutMs', 'timeoutMillisecond', 'timeout'];
  private static readonly SCOPE_KEYS = ['scope'];
  private static readonly EXCLUDE_SCOPE_KEYS = ['excludeScope'];
  private static readonly ORDER_KEYS = ['serialNumber', 'order', 'sort', 'sortOrder', 'sequence'];
  private static readonly ARRAY_KEYS = [
    'rules', 'replaceRules', 'readerReplaceRules', 'ruleList', 'list', 'items', 'data'
  ];

  static parse(raw: string): ReplaceRuleImportResult {
    const text = (raw || '').replace(/^\uFEFF/, '').trim();
    if (!text) {
      throw new Error('规则内容为空');
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(text) as Object;
    } catch (_) {
      throw new Error('内容不是有效的 JSON（支持阅读/YueDu 导出的 JSON 规则文件）');
    }
    const entries = ReplaceRuleImport.entries(parsed);
    if (entries.length === 0) {
      throw new Error('JSON 中未找到规则数组');
    }
    const rules: ImportedReplaceRule[] = [];
    let skipped = 0;
    let ignoredContentScope = 0;
    for (let index = 0; index < entries.length; index++) {
      const converted = ReplaceRuleImport.entry(entries[index], index);
      if (!converted) {
        skipped++;
        continue;
      }
      rules.push(converted);
      if (ReplaceRuleImport.readString(entries[index], ['scopeContent'])) {
        ignoredContentScope++;
      }
    }
    if (rules.length === 0) {
      throw new Error('未找到有效的替换净化规则（未识别到 pattern/regex 字段）');
    }
    rules.sort((left: ImportedReplaceRule, right: ImportedReplaceRule): number => left.order - right.order);
    return {
      rules: rules, formatLabel: ReplaceRuleImport.formatLabel(entries),
      skipped: skipped, ignoredContentScope: ignoredContentScope
    };
  }

  /**
   * 除本应用自己的导出外，其它来源都要先问用户是否转换：字段名和正则方言都会被改写，
   * 用户有权在写入规则列表前拒绝。
   */
  static needsConfirm(result: ReplaceRuleImportResult): boolean {
    return result.formatLabel !== '本应用';
  }

  static confirmTitle(result: ReplaceRuleImportResult): string {
    return `检测到${result.formatLabel}净化规则`;
  }

  static confirmMessage(result: ReplaceRuleImportResult): string {
    const parts: string[] = [
      `将把 ${result.rules.length} 条规则转换为本应用格式后导入：字段名按别名映射，` +
        `正则按 Android/Java 方言转换（例如 (?m)、(?is)、占有量词）。`
    ];
    if (result.skipped > 0) {
      parts.push(`其中 ${result.skipped} 条缺少匹配规则，导入时会跳过。`);
    }
    if (result.ignoredContentScope > 0) {
      parts.push(`其中 ${result.ignoredContentScope} 条带正文范围条件，本应用暂不支持，将被忽略。`);
    }
    parts.push('是否继续导入？');
    return parts.join('');
  }

  private static entries(parsed: Object): Record<string, Object>[] {
    if (Array.isArray(parsed)) {
      return parsed as Record<string, Object>[];
    }
    if (!parsed || typeof parsed !== 'object') {
      return [];
    }
    const record = parsed as Record<string, Object>;
    for (const key of ReplaceRuleImport.ARRAY_KEYS) {
      const value = record[key];
      if (Array.isArray(value)) {
        return value as Record<string, Object>[];
      }
    }
    return [];
  }

  private static entry(source: Record<string, Object>, index: number): ImportedReplaceRule | null {
    const pattern = ReplaceRuleImport.readString(source, ReplaceRuleImport.PATTERN_KEYS);
    if (!pattern) {
      return null;
    }
    const replacement = ReplaceRuleImport.readString(source, ReplaceRuleImport.REPLACEMENT_KEYS);
    const explicitRegex = ReplaceRuleImport.readBoolean(source, ReplaceRuleImport.REGEX_KEYS);
    // 字段名直接叫 regex 的格式（YueDu）必然是正则；其余默认按正则处理，与本应用默认一致。
    const isRegex = explicitRegex !== null ? explicitRegex : true;
    const name = ReplaceRuleImport.readString(source, ReplaceRuleImport.NAME_KEYS);
    const order = ReplaceRuleImport.readNumber(source, ReplaceRuleImport.ORDER_KEYS);
    return {
      id: ReplaceRuleImport.readNumber(source, ['id']),
      name: name || pattern.substring(0, 24),
      group: ReplaceRuleImport.readString(source, ReplaceRuleImport.GROUP_KEYS) || '导入规则',
      pattern: pattern,
      replacement: replacement,
      isRegex: isRegex,
      enabled: ReplaceRuleImport.readBoolean(source, ReplaceRuleImport.ENABLED_KEYS) !== false,
      applyToTitle: ReplaceRuleImport.readBoolean(source, ReplaceRuleImport.TITLE_KEYS) !== false,
      applyToContent: ReplaceRuleImport.readBoolean(source, ReplaceRuleImport.CONTENT_KEYS) !== false,
      scope: ReplaceRuleImport.scopeToken(ReplaceRuleImport.readString(source, ReplaceRuleImport.SCOPE_KEYS)),
      excludeScope: ReplaceRuleImport.scopeToken(
        ReplaceRuleImport.readString(source, ReplaceRuleImport.EXCLUDE_SCOPE_KEYS)),
      timeoutMs: ReplaceRuleImport.normalizeTimeout(
        ReplaceRuleImport.readNumber(source, ReplaceRuleImport.TIMEOUT_KEYS)),
      order: Number.isFinite(order) ? order : index
    };
  }

  private static readString(source: Record<string, Object>, keys: string[]): string {
    for (const key of keys) {
      const value = source[key];
      if (typeof value === 'string' && value.length > 0) {
        return value;
      }
    }
    return '';
  }

  private static readBoolean(source: Record<string, Object>, keys: string[]): boolean | null {
    for (const key of keys) {
      const value = source[key];
      if (typeof value === 'boolean') {
        return value;
      }
      if (value === 'true' || value === 'false') {
        return value === 'true';
      }
    }
    return null;
  }

  private static readNumber(source: Record<string, Object>, keys: string[]): number {
    for (const key of keys) {
      const value = source[key];
      if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
      }
      if (typeof value === 'string' && value.trim() !== '') {
        const parsed = Number(value);
        if (Number.isFinite(parsed)) {
          return parsed;
        }
      }
    }
    return Number.NaN;
  }

  private static normalizeTimeout(value: number): number {
    if (!Number.isFinite(value)) {
      return 3000;
    }
    return Math.max(100, Math.min(Math.round(value), 10000));
  }

  /**
   * 阅读的 scope/excludeScope 是正则，本应用的作用域用 `/正则/标志` 或子串表示。
   * 含正则元字符的值补成 `/…/` 形式，其余保持子串匹配；含分隔符时无法安全转换，原样保留。
   */
  private static scopeToken(value: string): string {
    const token = (value || '').trim();
    if (!token || token.startsWith('/')) {
      return token;
    }
    if (!/[.*+?^$()|[\]{}\\]/.test(token) || /[\n,;，；]/.test(token)) {
      return token;
    }
    return `/${token}/`;
  }

  private static formatLabel(entries: Record<string, Object>[]): string {
    let hasReplaceSummary = false;
    let hasRegexKey = false;
    let hasPatternKey = false;
    let hasLegadoKey = false;
    for (const entry of entries) {
      if ('replaceSummary' in entry) hasReplaceSummary = true;
      if ('regex' in entry) hasRegexKey = true;
      if ('pattern' in entry) hasPatternKey = true;
      if ('isEnabled' in entry || 'isEnabledForContent' in entry || 'timeoutMillisecond' in entry) {
        hasLegadoKey = true;
      }
    }
    if (hasReplaceSummary || (hasRegexKey && !hasPatternKey)) return '阅读(YueDu)';
    if (hasLegadoKey) return '阅读(Legado)';
    return '本应用';
  }
}
