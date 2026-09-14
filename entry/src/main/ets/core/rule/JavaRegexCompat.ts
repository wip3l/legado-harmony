/**
 * Translates the Java/Kotlin regex dialect used by Android Legado (book sources and
 * replacement/purification rules) into a JavaScript RegExp.
 *
 * Android Legado compiles every rule with java.util.regex.Pattern, so rule authors write
 * constructs JavaScript has no syntax for. Such rules throw "Invalid group" / "Nothing to
 * repeat" at RegExp construction time here, and because every call site wraps the compile in
 * try/catch the rule is skipped silently: text keeps its HTML or punctuation and the user only
 * sees a red "规则无效" in the rule list.
 *
 * Everything rewritten below is either impossible or awkward to express in JS:
 * - inline flag groups `(?i)`, `(?m)`, `(?s)`, `(?is)`, `(?mi)`, `(?-i)` — JS只能把标志传给
 *   构造函数，所以标志被提升为 RegExp flags（位置信息丢失，见各 note）。
 * - possessive quantifiers `a*+`, `a++`, `a?+`, `a{2,3}+` — JS 只有贪婪/惰性，降级为贪婪。
 * - atomic groups `(?>…)` — JS 无原子组，降级为普通分组。
 * - `\Q…\E` 字面量引用、`\h`/`\H`/`\v`/`\V`/`\R`、`\z`/`\Z`、`\p{…}`。
 * - replacement 串里的 `$0`（Java 的整个匹配）与 `\` 转义。
 */
export interface JavaRegexConversion {
  source: string;
  flags: string;
  /** 近似转换的说明，供界面提示或日志使用。 */
  notes: string[];
}

interface EscapeToken {
  text: string;
  next: number;
}

interface GroupToken {
  text: string;
  next: number;
  flags: string;
  removedFlags: string;
  commentsMode: boolean;
  inlineFlags: boolean;
}

export class JavaRegexCompat {
  private static readonly HORIZONTAL_CONTENT = ' \\t\\u00A0\\u1680\\u2000-\\u200A\\u202F\\u205F\\u3000';
  private static readonly VERTICAL_CONTENT = '\\n\\x0B\\f\\r\\x85\\u2028\\u2029';
  private static readonly LINE_BREAK = '(?:\\r\\n|[\\n\\x0B\\f\\r\\x85\\u2028\\u2029])';
  private static readonly INPUT_END = '(?![\\s\\S])';
  private static readonly INPUT_END_OR_TERMINATOR =
    '(?=(?:\\r\\n|[\\n\\r\\x85\\u2028\\u2029])?(?![\\s\\S]))';
  private static readonly INLINE_FLAG_LETTERS = 'imsuxdU';
  private static readonly CONVERTIBLE_FLAGS = 'ims';
  private static readonly LITERAL_METACHARACTERS = '\\^$.*+?()[]{}|';
  private static readonly BRACE_QUANTIFIER = /^\{\d+(?:,\d*)?\}|^\{,\d+\}/;
  private static readonly CACHE_LIMIT = 512;
  private static cache: Map<string, JavaRegexConversion> = new Map<string, JavaRegexConversion>();

  /**
   * Compiles a Legado regex into a fresh RegExp. A fresh object is returned on purpose: global
   * regexes carry lastIndex state, so sharing one instance between test() and replace() calls
   * would skip matches.
   */
  static compile(pattern: string, flags: string = ''): RegExp {
    const conversion = JavaRegexCompat.convert(pattern, flags);
    return new RegExp(conversion.source, conversion.flags);
  }

  /** 转换结果按 pattern+flags 缓存，因为界面会按帧对每条规则重复校验。 */
  static convert(pattern: string, flags: string = ''): JavaRegexConversion {
    const source = pattern || '';
    const key = `${flags}\u0001${source}`;
    const cached = JavaRegexCompat.cache.get(key);
    if (cached) {
      return cached;
    }
    const conversion = JavaRegexCompat.translate(source, flags);
    if (JavaRegexCompat.cache.size >= JavaRegexCompat.CACHE_LIMIT) {
      JavaRegexCompat.cache.clear();
    }
    JavaRegexCompat.cache.set(key, conversion);
    return conversion;
  }

  /** 转换说明，未做任何改写时返回空数组。 */
  static notes(pattern: string, flags: string = ''): string[] {
    return JavaRegexCompat.convert(pattern, flags).notes.slice();
  }

  static isSupported(pattern: string, flags: string = ''): boolean {
    try {
      JavaRegexCompat.compile(pattern, flags);
      return true;
    } catch (_) {
      return false;
    }
  }

  /**
   * 编译失败后的可读原因。引擎的原生报错只有一句 "Syntax error."，而这几类 Java 专有写法是
   * 转换层无法等价的，单独指出来才能让用户知道该改规则而不是怀疑应用。
   */
  static unsupportedHint(pattern: string): string {
    const source = pattern || '';
    const known: string[] = [];
    if (/\\[pP]\{(?:Is|In|java|com)/.test(source)) {
      known.push('Java 专有 Unicode 属性名');
    }
    if (/\(\?P[<=]/.test(source)) {
      known.push('Python 风格命名分组');
    }
    if (/\[[^\]]*&&/.test(source)) {
      known.push('字符类交集');
    }
    return known.length > 0 ? `含 JavaScript 无法等价的写法：${known.join('、')}` : '';
  }

  /**
   * Java 的替换串语义：`$0` 是整个匹配，`\` 是转义符（因此 `\d` 是字面量 d）。
   * JavaScript 用 `$&` 表示整个匹配，且反斜杠是普通字符，需要在此对齐。
   */
  static convertReplacement(replacement: string): string {
    const text = replacement || '';
    let result = '';
    for (let index = 0; index < text.length; index++) {
      const ch = text.charAt(index);
      if (ch === '\\') {
        const escaped = index + 1 < text.length ? text.charAt(index + 1) : '';
        if (escaped) {
          result += escaped === '$' ? '$$' : escaped;
          index++;
        }
        continue;
      }
      const after = text.charAt(index + 1);
      if (ch === '$' && after === '0' && !JavaRegexCompat.isDigit(text.charAt(index + 2))) {
        result += '$&';
        index++;
        continue;
      }
      result += ch;
    }
    return result;
  }

  private static isDigit(value: string): boolean {
    return value.length === 1 && value >= '0' && value <= '9';
  }

  private static translate(pattern: string, extraFlags: string): JavaRegexConversion {
    const notes: string[] = [];
    let flags = extraFlags || '';
    // `\p{…}` 在 JavaScript 里必须配合 u 标志，否则会被当成字面量 p{…}。
    const needsUnicode = /\\[pP]\{/.test(pattern);
    if (needsUnicode && !flags.includes('u')) {
      flags += 'u';
    }
    let result = '';
    let index = 0;
    let inClass = false;
    let commentsMode = false;

    while (index < pattern.length) {
      const ch = pattern.charAt(index);

      if (ch === '\\') {
        const token = JavaRegexCompat.translateEscape(pattern, index, inClass, notes);
        result += token.text;
        index = token.next;
        continue;
      }

      if (inClass) {
        if (ch === ']') {
          inClass = false;
        } else if (ch === '&' && pattern.charAt(index + 1) === '&') {
          notes.push('字符类交集（&&）在 JavaScript 中按字面量处理，结果与 Android 不同');
        }
        result += ch;
        index++;
        continue;
      }

      if (commentsMode) {
        if (JavaRegexCompat.isPatternWhitespace(ch)) {
          index++;
          continue;
        }
        if (ch === '#') {
          while (index < pattern.length && pattern.charAt(index) !== '\n') {
            index++;
          }
          continue;
        }
      }

      if (ch === '[') {
        result += '[';
        index++;
        if (pattern.charAt(index) === '^') {
          result += '^';
          index++;
        }
        if (pattern.charAt(index) === ']') {
          // `[]a]` 里首个 `]` 是字面量，Java 与 JS 规则一致，这里显式转义避免歧义。
          result += '\\]';
          index++;
        }
        inClass = true;
        continue;
      }

      if (ch === '(' && pattern.charAt(index + 1) === '?') {
        const group = JavaRegexCompat.translateGroup(pattern, index, notes);
        if (group) {
          const previousFlags = flags;
          commentsMode = commentsMode || group.commentsMode;
          for (let i = 0; i < group.flags.length; i++) {
            const flag = group.flags.charAt(i);
            if (!flags.includes(flag)) {
              flags += flag;
            }
          }
          for (let i = 0; i < group.removedFlags.length; i++) {
            flags = flags.replace(group.removedFlags.charAt(i), '');
          }
          if (group.inlineFlags) {
            if (result.length > 0 && group.flags) {
              notes.push('内联标志不在规则开头，已提升为整条规则的标志');
            }
            for (let i = 0; i < group.removedFlags.length; i++) {
              const flag = group.removedFlags.charAt(i);
              if (previousFlags.includes(flag)) {
                notes.push(`内联关闭标志 (?-${flag}) 无法只作用于局部，已关闭整条规则的该标志`);
              }
            }
          }
          result += group.text;
          index = group.next;
          continue;
        }
      }

      if (ch === '{') {
        const quantifier = JavaRegexCompat.BRACE_QUANTIFIER.exec(pattern.substring(index));
        if (quantifier) {
          result += quantifier[0];
          index += quantifier[0].length;
          if (pattern.charAt(index) === '+') {
            notes.push('占有量词（+）已降级为贪婪量词');
            index++;
          }
          continue;
        }
        result += needsUnicode ? '\\{' : '{';
        index++;
        continue;
      }

      if (ch === '*' || ch === '+' || ch === '?') {
        result += ch;
        index++;
        if (pattern.charAt(index) === '+') {
          notes.push('占有量词（+）已降级为贪婪量词');
          index++;
        }
        continue;
      }

      if (ch === '}' && needsUnicode) {
        result += '\\}';
        index++;
        continue;
      }

      result += ch;
      index++;
    }

    return { source: result, flags: flags, notes: JavaRegexCompat.unique(notes) };
  }

  private static isPatternWhitespace(ch: string): boolean {
    return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' || ch === '\f' || ch === '\u000B';
  }

  private static unique(values: string[]): string[] {
    const result: string[] = [];
    for (let i = 0; i < values.length; i++) {
      if (result.indexOf(values[i]) < 0) {
        result.push(values[i]);
      }
    }
    return result;
  }

  private static translateEscape(pattern: string, index: number, inClass: boolean,
    notes: string[]): EscapeToken {
    const next = pattern.charAt(index + 1);
    if (!next) {
      return { text: '\\', next: index + 1 };
    }
    if (next === 'Q') {
      const end = pattern.indexOf('\\E', index + 2);
      const literal = end < 0 ? pattern.substring(index + 2) : pattern.substring(index + 2, end);
      if (end < 0) {
        notes.push('\\Q 缺少配对的 \\E，已按字面量处理到规则结尾');
      }
      return { text: JavaRegexCompat.escapeLiteral(literal), next: end < 0 ? pattern.length : end + 2 };
    }
    if (next === 'E') {
      notes.push('孤立的 \\E 已忽略');
      return { text: '', next: index + 2 };
    }
    if (next === 'h') {
      return {
        text: inClass ? JavaRegexCompat.HORIZONTAL_CONTENT : `[${JavaRegexCompat.HORIZONTAL_CONTENT}]`,
        next: index + 2
      };
    }
    if (next === 'H') {
      if (inClass) {
        notes.push('字符类内的 \\H 无法取反，已按水平空白字符处理');
        return { text: JavaRegexCompat.HORIZONTAL_CONTENT, next: index + 2 };
      }
      return { text: `[^${JavaRegexCompat.HORIZONTAL_CONTENT}]`, next: index + 2 };
    }
    if (next === 'v') {
      return {
        text: inClass ? JavaRegexCompat.VERTICAL_CONTENT : `[${JavaRegexCompat.VERTICAL_CONTENT}]`,
        next: index + 2
      };
    }
    if (next === 'V') {
      if (inClass) {
        notes.push('字符类内的 \\V 无法取反，已按垂直空白字符处理');
        return { text: JavaRegexCompat.VERTICAL_CONTENT, next: index + 2 };
      }
      return { text: `[^${JavaRegexCompat.VERTICAL_CONTENT}]`, next: index + 2 };
    }
    if (next === 'R') {
      return {
        text: inClass ? JavaRegexCompat.VERTICAL_CONTENT : JavaRegexCompat.LINE_BREAK,
        next: index + 2
      };
    }
    if (next === 'z') {
      return { text: inClass ? '$' : JavaRegexCompat.INPUT_END, next: index + 2 };
    }
    if (next === 'Z') {
      return { text: inClass ? '$' : JavaRegexCompat.INPUT_END_OR_TERMINATOR, next: index + 2 };
    }
    if ((next === 'p' || next === 'P') && pattern.charAt(index + 2) === '{') {
      const close = pattern.indexOf('}', index + 3);
      if (close > 0) {
        const body = pattern.substring(index + 3, close);
        if (!JavaRegexCompat.isJavaScriptPropertyName(body)) {
          notes.push(`\\p{${body}} 的属性名 JavaScript 不支持，规则可能仍无法编译`);
        }
        return { text: pattern.substring(index, close + 1), next: close + 1 };
      }
    }
    if (next === 'u' && pattern.charAt(index + 2) === '{') {
      // JS 的 `\u{1F600}` 形式：整体复制，避免后续把 `{` 当成量词或字面量花括号处理。
      const close = pattern.indexOf('}', index + 3);
      if (close > 0) {
        return { text: pattern.substring(index, close + 1), next: close + 1 };
      }
    }
    if (next === 'G' || next === 'X' || next === 'A') {
      // Java 的 `\G`（上次匹配结尾）、`\X`（字形簇）、`\A`（输入开头）在 JavaScript 中
      // 没有对应语义，会被当成字面量字符，必须提示而不是静默给出错误结果。
      notes.push(`\\${next} 在 JavaScript 中没有对应语义，将按字面量字符处理`);
    }
    return { text: `\\${next}`, next: index + 2 };
  }

  private static isJavaScriptPropertyName(body: string): boolean {
    // JS 只认通用类别名（L、Lu、Letter、Nd…）和 `Script=…`/`sc=…` 形式，Java 的
    // `IsGreek`、`InCJKUnifiedIdeographs`、`javaLowerCase` 一类名字会被 u 模式拒绝。
    return /^[A-Za-z]+(?:=[A-Za-z_]+)?$/.test(body) && !/^(?:Is|In|java)/.test(body);
  }

  private static translateGroup(pattern: string, index: number, notes: string[]): GroupToken | null {
    let cursor = index + 2;
    let enabled = '';
    while (cursor < pattern.length &&
      JavaRegexCompat.INLINE_FLAG_LETTERS.indexOf(pattern.charAt(cursor)) >= 0) {
      enabled += pattern.charAt(cursor);
      cursor++;
    }
    let disabled = '';
    if (pattern.charAt(cursor) === '-') {
      let probe = cursor + 1;
      let letters = '';
      while (probe < pattern.length &&
        JavaRegexCompat.INLINE_FLAG_LETTERS.indexOf(pattern.charAt(probe)) >= 0) {
        letters += pattern.charAt(probe);
        probe++;
      }
      if (letters) {
        disabled = letters;
        cursor = probe;
      }
    }

    if (pattern.charAt(cursor) === ')' && (enabled || disabled)) {
      return JavaRegexCompat.translateInlineFlags(enabled, disabled, cursor + 1, notes);
    }

    const marker = pattern.charAt(index + 2);
    if (marker === '>') {
      notes.push('原子组 (?>…) 在 JavaScript 中没有对应实现，已按普通分组处理');
      return JavaRegexCompat.passThrough('(?:', index + 3);
    }
    if (marker === ':' || marker === '=' || marker === '!') {
      return JavaRegexCompat.passThrough(`(?${marker}`, index + 3);
    }
    if (marker === '<') {
      const after = pattern.charAt(index + 3);
      if (after === '=' || after === '!') {
        return JavaRegexCompat.passThrough(`(?<${after}`, index + 4);
      }
      return JavaRegexCompat.passThrough('(?<', index + 3);
    }
    // 未知构造（例如 Java 不支持的 Python 式分组）：保留原文，让引擎给出真实报错。
    return JavaRegexCompat.passThrough('(?', index + 2);
  }

  private static translateInlineFlags(enabled: string, disabled: string, next: number,
    notes: string[]): GroupToken {
    let flags = '';
    let removedFlags = '';
    let commentsMode = false;
    for (let i = 0; i < enabled.length; i++) {
      const letter = enabled.charAt(i);
      if (JavaRegexCompat.CONVERTIBLE_FLAGS.includes(letter)) {
        if (!flags.includes(letter)) {
          flags += letter;
        }
      } else if (letter === 'x') {
        commentsMode = true;
        notes.push('(?x) 自由空白模式已按 Java 语义忽略空白与 # 注释');
      } else {
        notes.push(`内联标志 (?${letter}) 在 JavaScript 中没有对应项，已忽略`);
      }
    }
    for (let i = 0; i < disabled.length; i++) {
      const letter = disabled.charAt(i);
      if (JavaRegexCompat.CONVERTIBLE_FLAGS.includes(letter)) {
        removedFlags += letter;
      }
    }
    return {
      text: '', next: next, flags: flags, removedFlags: removedFlags,
      commentsMode: commentsMode, inlineFlags: true
    };
  }

  private static passThrough(text: string, next: number): GroupToken {
    return {
      text: text, next: next, flags: '', removedFlags: '',
      commentsMode: false, inlineFlags: false
    };
  }

  private static escapeLiteral(text: string): string {
    let result = '';
    for (let index = 0; index < text.length; index++) {
      const ch = text.charAt(index);
      if (ch === '\n') {
        result += '\\n';
      } else if (ch === '\r') {
        result += '\\r';
      } else if (ch === '\t') {
        result += '\\t';
      } else if (ch === '\f') {
        result += '\\f';
      } else if (ch === '\u000B') {
        result += '\\x0B';
      } else if (JavaRegexCompat.LITERAL_METACHARACTERS.includes(ch)) {
        result += `\\${ch}`;
      } else {
        result += ch;
      }
    }
    return result;
  }
}
