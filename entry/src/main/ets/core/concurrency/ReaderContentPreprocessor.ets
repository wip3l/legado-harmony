import taskpool from '@ohos.taskpool';
import { Book } from '../../model/data/Book';
import { ReaderReplaceRule } from '../../utils/ReaderReplaceRuleStore';

/**
 * Pure TaskPool entry. It deliberately owns no UI or database state so a pathological imported
 * replacement rule cannot block ArkUI's event loop.
 */
@Concurrent
function applyReaderRulesInTask(text: string, rulesJson: string, scopeText: string): string {
  let rules: Record<string, Object>[] = [];
  try {
    const parsed = JSON.parse(rulesJson || '[]') as Object;
    if (Array.isArray(parsed)) rules = parsed as Record<string, Object>[];
  } catch (_) {
    return text;
  }
  // Reader action markers are app-internal interaction metadata (paragraph-comment bubbles,
  // source buttons) baked into the content text. They are not book prose, and cleaning rules
  // such as `\[.*?\]` or "strip non-CJK" must never destroy them, so every rule is applied per
  // plain-text segment and the markers are reattached verbatim afterwards.
  const hasMarkers = (text || '').indexOf('[[LEGADO_READER_ACTION') >= 0;
  const segments: string[] = hasMarkers ?
    (text || '').split(/(\[\[LEGADO_READER_ACTION(?:_V[23])?:[\s\S]*?\]\])/g) : [text || ''];
  const target = (scopeText || '').toLowerCase();
  for (let index = 0; index < rules.length; index++) {
    const rule = rules[index];
    if (rule['enabled'] === false || rule['applyToContent'] === false) continue;
    const pattern = String(rule['pattern'] || '');
    if (!pattern || pattern.length > 4096) continue;

    let scopeAllowed = true;
    const includeTokens = String(rule['scope'] || '').split(/[\n,，;；]+/)
      .map((value: string): string => value.trim().toLowerCase())
      .filter((value: string): boolean => !!value);
    if (includeTokens.length > 0) {
      scopeAllowed = false;
      for (let tokenIndex = 0; tokenIndex < includeTokens.length; tokenIndex++) {
        const token = includeTokens[tokenIndex];
        let matches = false;
        if (token.startsWith('/') && token.lastIndexOf('/') > 0) {
          const end = token.lastIndexOf('/');
          try { matches = new RegExp(token.substring(1, end), token.substring(end + 1)).test(target); } catch (_) {}
        } else if (token.includes('*')) {
          const escaped = token.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
          try { matches = new RegExp(escaped, 'i').test(target); } catch (_) {}
        } else {
          matches = target.includes(token);
        }
        if (matches) {
          scopeAllowed = true;
          break;
        }
      }
    }
    if (!scopeAllowed) continue;
    const excludeTokens = String(rule['excludeScope'] || '').split(/[\n,，;；]+/)
      .map((value: string): string => value.trim().toLowerCase())
      .filter((value: string): boolean => !!value);
    let excluded = false;
    for (let tokenIndex = 0; tokenIndex < excludeTokens.length; tokenIndex++) {
      const token = excludeTokens[tokenIndex];
      let matches = false;
      if (token.startsWith('/') && token.lastIndexOf('/') > 0) {
        const end = token.lastIndexOf('/');
        try { matches = new RegExp(token.substring(1, end), token.substring(end + 1)).test(target); } catch (_) {}
      } else if (token.includes('*')) {
        const escaped = token.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
        try { matches = new RegExp(escaped, 'i').test(target); } catch (_) {}
      } else {
        matches = target.includes(token);
      }
      if (matches) {
        excluded = true;
        break;
      }
    }
    if (excluded) continue;

    try {
      const replacement = String(rule['replacement'] || '');
      let matcher: RegExp | null = null;
      let plain = '';
      if (rule['isRegex'] !== false) {
        // Nested unbounded quantifiers are a common source of catastrophic backtracking. Imported
        // rules with this shape are skipped instead of occupying a TaskPool worker indefinitely.
        if (/(?:\([^)]*[+*][^)]*\)|\[[^\]]+\][+*])[+*{]/.test(pattern)) continue;
        matcher = new RegExp(pattern, 'g');
      } else {
        plain = pattern;
      }
      // Even indices are plain text; odd indices are captured markers kept out of rule scope.
      for (let si = 0; si < segments.length; si += 2) {
        const segment = segments[si];
        if (!segment) continue;
        if (matcher !== null) segments[si] = segment.replace(matcher, replacement);
        else segments[si] = segment.split(plain).join(replacement);
      }
    } catch (_) {
    }
  }
  return segments.join('');
}

export class ReaderContentPreprocessor {
  static hasActiveContentRules(rules: ReaderReplaceRule[]): boolean {
    return rules.some((rule: ReaderReplaceRule): boolean =>
      rule.enabled !== false && rule.applyToContent !== false && !!rule.pattern);
  }

  static async apply(text: string, rules: ReaderReplaceRule[], book: Book | null): Promise<string> {
    if (!text || !ReaderContentPreprocessor.hasActiveContentRules(rules)) return text;
    const scopeText = book ? `${book.name || ''}\n${book.author || ''}\n${book.originName || ''}\n` +
      `${book.origin || ''}\n${book.bookUrl || ''}` : '';
    try {
      const value = await taskpool.execute(applyReaderRulesInTask, text, JSON.stringify(rules), scopeText);
      return typeof value === 'string' ? value : text;
    } catch (error) {
      console.warn('[ReaderPreprocessor] TaskPool failed, keep original content:', error);
      return text;
    }
  }
}
