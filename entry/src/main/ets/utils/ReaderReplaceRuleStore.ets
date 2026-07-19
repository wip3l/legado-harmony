import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { Book } from '../model/data/Book';

export class ReaderReplaceRule {
  id: number = 0;
  name: string = '';
  group: string = '默认';
  pattern: string = '';
  replacement: string = '';
  applyToTitle: boolean = true;
  applyToContent: boolean = true;
  isRegex: boolean = true;
  scope: string = '';
  excludeScope: string = '';
  timeoutMs: number = 3000;
  enabled: boolean = true;
}

export class ReaderReplaceRuleCheck {
  state: string = 'noMatch';
  label: string = '当前章节未匹配';
  valid: boolean = true;
  scopeMatched: boolean = true;
  titleMatched: boolean = false;
  contentMatched: boolean = false;
  changed: boolean = false;
}

export class ReaderReplaceRuleStore {
  static readonly UPDATE_TIME_KEY: string = 'readerReplaceRulesUpdateTime';
  private static readonly STORE_NAME: string = 'reader_replace_rules';
  private static readonly RULES_KEY: string = 'rulesV1';
  private static cachedRules: ReaderReplaceRule[] | null = null;

  static async load(context: Context, force: boolean = false): Promise<ReaderReplaceRule[]> {
    if (!force && ReaderReplaceRuleStore.cachedRules) {
      return ReaderReplaceRuleStore.cloneRules(ReaderReplaceRuleStore.cachedRules);
    }
    const store = await preferences.getPreferences(context, ReaderReplaceRuleStore.STORE_NAME);
    const value = await store.get(ReaderReplaceRuleStore.RULES_KEY, '');
    const raw = typeof value === 'string' ? value : '';
    const rules = ReaderReplaceRuleStore.decode(raw);
    ReaderReplaceRuleStore.cachedRules = ReaderReplaceRuleStore.cloneRules(rules);
    return rules;
  }

  static async save(context: Context, rules: ReaderReplaceRule[]): Promise<void> {
    const normalized = rules.map((rule: ReaderReplaceRule) => ReaderReplaceRuleStore.normalize(rule));
    ReaderReplaceRuleStore.cachedRules = ReaderReplaceRuleStore.cloneRules(normalized);
    const store = await preferences.getPreferences(context, ReaderReplaceRuleStore.STORE_NAME);
    await store.put(ReaderReplaceRuleStore.RULES_KEY, JSON.stringify(normalized));
    await store.flush();
    AppStorage.setOrCreate(ReaderReplaceRuleStore.UPDATE_TIME_KEY, Date.now());
  }

  static newRule(): ReaderReplaceRule {
    const rule = new ReaderReplaceRule();
    rule.id = Date.now();
    return rule;
  }

  static applyTitle(text: string, rules: ReaderReplaceRule[], book: Book | null): string {
    return ReaderReplaceRuleStore.apply(text, rules, book, true);
  }

  static applyContent(text: string, rules: ReaderReplaceRule[], book: Book | null): string {
    return ReaderReplaceRuleStore.apply(text, rules, book, false);
  }

  static checkRule(sourceRule: ReaderReplaceRule, book: Book | null,
    title: string, content: string): ReaderReplaceRuleCheck {
    const result = new ReaderReplaceRuleCheck();
    const rule = ReaderReplaceRuleStore.normalize(sourceRule);
    if (!rule.enabled) {
      result.state = 'disabled';
      result.label = '已禁用';
      return result;
    }
    if (!rule.pattern) {
      result.state = 'invalid';
      result.label = '规则无效：匹配内容为空';
      result.valid = false;
      return result;
    }
    result.scopeMatched = ReaderReplaceRuleStore.matchesBookScope(rule, book);
    if (!result.scopeMatched) {
      result.state = 'outOfScope';
      result.label = '不适用于当前书籍';
      return result;
    }
    try {
      if (rule.isRegex) {
        const titleRegex = new RegExp(rule.pattern, 'g');
        const contentRegex = new RegExp(rule.pattern, 'g');
        result.titleMatched = rule.applyToTitle && !!title && titleRegex.test(title);
        result.contentMatched = rule.applyToContent && !!content && contentRegex.test(content);
        if (result.titleMatched) {
          result.changed = title.replace(new RegExp(rule.pattern, 'g'), rule.replacement) !== title;
        }
        if (result.contentMatched) {
          result.changed = result.changed ||
            content.replace(new RegExp(rule.pattern, 'g'), rule.replacement) !== content;
        }
      } else {
        result.titleMatched = rule.applyToTitle && !!title && title.includes(rule.pattern);
        result.contentMatched = rule.applyToContent && !!content && content.includes(rule.pattern);
        if (result.titleMatched) {
          result.changed = title.split(rule.pattern).join(rule.replacement) !== title;
        }
        if (result.contentMatched) {
          result.changed = result.changed || content.split(rule.pattern).join(rule.replacement) !== content;
        }
      }
    } catch (error) {
      result.state = 'invalid';
      result.label = `规则无效：${error instanceof Error ? error.message : String(error)}`;
      result.valid = false;
      return result;
    }
    if (result.titleMatched || result.contentMatched) {
      result.state = result.changed ? 'effective' : 'matched';
      result.label = result.changed ? '当前章节已生效' : '已匹配，替换结果未变化';
    }
    return result;
  }

  private static apply(
    text: string,
    rules: ReaderReplaceRule[],
    book: Book | null,
    title: boolean
  ): string {
    if (!text || rules.length === 0) {
      return text;
    }
    let result = text;
    for (const sourceRule of rules) {
      const rule = ReaderReplaceRuleStore.normalize(sourceRule);
      if (!rule.enabled || !rule.pattern || (title ? !rule.applyToTitle : !rule.applyToContent) ||
        !ReaderReplaceRuleStore.matchesBookScope(rule, book)) {
        continue;
      }
      const startedAt = Date.now();
      try {
        if (rule.isRegex) {
          result = result.replace(new RegExp(rule.pattern, 'g'), rule.replacement);
        } else {
          result = result.split(rule.pattern).join(rule.replacement);
        }
      } catch (error) {
        console.warn(`替换净化规则无效: ${rule.name || rule.pattern}`, error);
      }
      if (Date.now() - startedAt > rule.timeoutMs) {
        console.warn(`替换净化规则执行超时: ${rule.name || rule.pattern}`);
      }
    }
    return result;
  }

  private static matchesBookScope(rule: ReaderReplaceRule, book: Book | null): boolean {
    const target = ReaderReplaceRuleStore.bookScopeText(book);
    const includes = ReaderReplaceRuleStore.scopeTokens(rule.scope);
    if (includes.length > 0 && !includes.some((token: string) =>
      ReaderReplaceRuleStore.scopeTokenMatches(token, target))) {
      return false;
    }
    const excludes = ReaderReplaceRuleStore.scopeTokens(rule.excludeScope);
    return !excludes.some((token: string) => ReaderReplaceRuleStore.scopeTokenMatches(token, target));
  }

  private static bookScopeText(book: Book | null): string {
    if (!book) {
      return '';
    }
    return `${book.name || ''}\n${book.author || ''}\n${book.originName || ''}\n` +
      `${book.origin || ''}\n${book.bookUrl || ''}`.toLowerCase();
  }

  private static scopeTokens(value: string): string[] {
    return (value || '').split(/[\n,，;；]+/)
      .map((item: string) => item.trim().toLowerCase())
      .filter((item: string) => !!item);
  }

  private static scopeTokenMatches(token: string, target: string): boolean {
    if (!token) {
      return false;
    }
    if (token.startsWith('/') && token.lastIndexOf('/') > 0) {
      const end = token.lastIndexOf('/');
      try {
        return new RegExp(token.substring(1, end), token.substring(end + 1)).test(target);
      } catch (_) {
        return target.includes(token);
      }
    }
    if (token.includes('*')) {
      const escaped = token.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
      try {
        return new RegExp(escaped, 'i').test(target);
      } catch (_) {
        return false;
      }
    }
    return target.includes(token);
  }

  private static decode(raw: string): ReaderReplaceRule[] {
    if (!raw) {
      return [];
    }
    try {
      const values = JSON.parse(raw) as ReaderReplaceRule[];
      if (!Array.isArray(values)) {
        return [];
      }
      return values.map((rule: ReaderReplaceRule) => ReaderReplaceRuleStore.normalize(rule));
    } catch (error) {
      console.warn('读取替换净化规则失败:', error);
      return [];
    }
  }

  private static normalize(source: ReaderReplaceRule): ReaderReplaceRule {
    const rule = new ReaderReplaceRule();
    rule.id = Number(source?.id) > 0 ? Number(source.id) : Date.now();
    rule.name = `${source?.name || ''}`.trim();
    rule.group = `${source?.group || '默认'}`.trim() || '默认';
    rule.pattern = `${source?.pattern || ''}`;
    rule.replacement = `${source?.replacement || ''}`;
    rule.applyToTitle = source?.applyToTitle !== false;
    rule.applyToContent = source?.applyToContent !== false;
    rule.isRegex = source?.isRegex !== false;
    rule.scope = `${source?.scope || ''}`;
    rule.excludeScope = `${source?.excludeScope || ''}`;
    const timeout = Math.round(Number(source?.timeoutMs));
    rule.timeoutMs = Number.isNaN(timeout) ? 3000 : Math.max(100, Math.min(timeout, 10000));
    rule.enabled = source?.enabled !== false;
    return rule;
  }

  static cloneRule(source: ReaderReplaceRule): ReaderReplaceRule {
    return ReaderReplaceRuleStore.normalize(source);
  }

  private static cloneRules(rules: ReaderReplaceRule[]): ReaderReplaceRule[] {
    return rules.map((rule: ReaderReplaceRule) => ReaderReplaceRuleStore.cloneRule(rule));
  }
}
