export class ReaderRegexFontRule {
  id: string = '';
  name: string = '';
  pattern: string = '';
  fontMode: string = 'global';
  fontFamily: string = '';
  fontSize: number = 20;
  emphasisMode: string = 'inherit';
  bubbleStyleId: string = 'inherit';
  emphasisColor: string = '';
  // Kept in schema v2 so older installations can still read a compatible rule.
  highlightColorEnabled: boolean = false;
  shadowColor: string = '';
  expanded: boolean = true;
}

export class ReaderRegexFontRulesData {
  schemaVersion: number = 2;
  rules: ReaderRegexFontRule[] = [];
}

export class ReaderRegexLegacySettings {
  pattern: string = '';
  fontMode: string = 'global';
  fontFamily: string = '';
  fontSize: number = 20;
  shadowColor: string = '';
}

export class ReaderRegexFontCodec {
  static readonly SCHEMA_VERSION: number = 2;

  static decode(raw: string, legacy: ReaderRegexLegacySettings | null = null): ReaderRegexFontRule[] {
    const text = (raw || '').trim();
    if (text) {
      try {
        const parsed = JSON.parse(text) as ReaderRegexFontRulesData | ReaderRegexFontRule[];
        if (Array.isArray(parsed)) {
          return ReaderRegexFontCodec.cleanRules(parsed as ReaderRegexFontRule[]);
        }
        const data = parsed as ReaderRegexFontRulesData;
        if (data && Array.isArray(data.rules)) {
          return ReaderRegexFontCodec.cleanRules(data.rules);
        }
      } catch (_) {
      }
    }
    if (legacy && (legacy.pattern || '').trim()) {
      const rule = new ReaderRegexFontRule();
      rule.id = ReaderRegexFontCodec.newRuleId();
      rule.name = '正则规则';
      rule.pattern = legacy.pattern;
      rule.fontMode = ReaderRegexFontCodec.normalizeFontMode(legacy.fontMode);
      rule.fontFamily = legacy.fontFamily || '';
      rule.fontSize = ReaderRegexFontCodec.normalizeFontSize(legacy.fontSize);
      rule.emphasisMode = (legacy.shadowColor || '').trim() ? 'highlight' : 'none';
      rule.emphasisColor = (legacy.shadowColor || '').trim();
      rule.highlightColorEnabled = rule.emphasisMode === 'highlight';
      rule.shadowColor = rule.emphasisColor;
      return [rule];
    }
    return [];
  }

  static encode(rules: ReaderRegexFontRule[]): string {
    const data = new ReaderRegexFontRulesData();
    data.schemaVersion = ReaderRegexFontCodec.SCHEMA_VERSION;
    data.rules = ReaderRegexFontCodec.cleanRules(rules);
    for (const rule of data.rules) {
      ReaderRegexFontCodec.syncLegacyFields(rule);
    }
    return JSON.stringify(data);
  }

  static cleanRules(source: ReaderRegexFontRule[]): ReaderRegexFontRule[] {
    const result: ReaderRegexFontRule[] = [];
    for (const item of source) {
      if (!item) {
        continue;
      }
      const rule = new ReaderRegexFontRule();
      rule.id = item.id || ReaderRegexFontCodec.newRuleId();
      rule.name = (item.name || '正则规则').trim();
      rule.pattern = (item.pattern || '').trim();
      rule.fontMode = ReaderRegexFontCodec.normalizeFontMode(item.fontMode);
      rule.fontFamily = item.fontFamily || '';
      rule.fontSize = ReaderRegexFontCodec.normalizeFontSize(item.fontSize);
      rule.emphasisMode = ReaderRegexFontCodec.normalizeEmphasisMode(
        item.emphasisMode,
        item.highlightColorEnabled === true
      );
      rule.bubbleStyleId = ReaderRegexFontCodec.normalizeBubbleStyleId(item.bubbleStyleId);
      rule.emphasisColor = ((item.emphasisColor || item.shadowColor) || '').trim();
      rule.highlightColorEnabled = item.highlightColorEnabled === true;
      rule.shadowColor = (item.shadowColor || rule.emphasisColor).trim();
      rule.expanded = item.expanded !== false;
      ReaderRegexFontCodec.syncLegacyFields(rule);
      result.push(rule);
    }
    return result;
  }

  static cloneRule(source: ReaderRegexFontRule): ReaderRegexFontRule {
    const rules = ReaderRegexFontCodec.cleanRules([source]);
    return rules.length > 0 ? rules[0] : new ReaderRegexFontRule();
  }

  static normalizeEmphasisMode(mode: string, legacyEnabled: boolean = false): string {
    const value = (mode || '').trim();
    if (value === 'inherit' || value === 'none' || value === 'text' || value === 'highlight' || value === 'bubble') {
      return value;
    }
    if (value === 'accent') {
      return 'highlight';
    }
    return legacyEnabled ? 'highlight' : 'none';
  }

  static normalizeResolvedEmphasisMode(mode: string): string {
    const value = ReaderRegexFontCodec.normalizeEmphasisMode(mode, false);
    return value === 'inherit' ? 'none' : value;
  }

  static normalizeBubbleStyleId(styleId: string): string {
    const value = (styleId || '').trim();
    if (value === 'inherit' || value === 'qq-soft' || value === 'qq-solid' || value === 'capsule' ||
      value === 'paper' || value === 'neon') {
      return value;
    }
    // Compatibility with early theme drafts.
    if (value === 'soft' || value === 'mist') {
      return 'qq-soft';
    }
    if (value === 'ink') {
      return 'qq-solid';
    }
    return 'inherit';
  }

  static normalizeResolvedBubbleStyleId(styleId: string): string {
    const value = ReaderRegexFontCodec.normalizeBubbleStyleId(styleId);
    return value === 'inherit' ? 'qq-soft' : value;
  }

  static normalizeFontMode(mode: string): string {
    return mode === 'system' || mode === 'custom' ? mode : 'global';
  }

  static normalizeFontSize(value: number): number {
    return Math.max(14, Math.min(Math.round(value || 20), 30));
  }

  static syncLegacyFields(rule: ReaderRegexFontRule): void {
    const mode = ReaderRegexFontCodec.normalizeEmphasisMode(rule.emphasisMode, rule.highlightColorEnabled);
    rule.emphasisMode = mode;
    rule.bubbleStyleId = ReaderRegexFontCodec.normalizeBubbleStyleId(rule.bubbleStyleId);
    rule.emphasisColor = (rule.emphasisColor || rule.shadowColor || '').trim();
    rule.highlightColorEnabled = mode === 'highlight' || mode === 'bubble';
    rule.shadowColor = rule.emphasisColor;
  }

  static newRuleId(): string {
    return `rule_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  }
}

export class ReaderRegexEmphasisContext {
  inheritedMode: string = 'none';
  inheritedBubbleStyleId: string = 'qq-soft';
  inheritedColor: string = '';
  inheritedTextColor: string = '';
  accentColor: string = '#007DFF';
  surfaceColor: string = '#FFFFFF';
  normalTextColor: string = '#1F1F1F';
  darkMode: boolean = false;
}

export class ReaderResolvedRegexEmphasis {
  mode: string = 'none';
  bubbleStyleId: string = 'qq-soft';
  emphasisColor: string = '#007DFF';
  backgroundEnabled: boolean = false;
  backgroundColor: string = '#00000000';
  textColor: string = '#1F1F1F';
  radiusTopLeft: number = 0;
  radiusTopRight: number = 0;
  radiusBottomLeft: number = 0;
  radiusBottomRight: number = 0;
  textShadowRadius: number = 0;
  textShadowColor: string = '#00000000';
  textShadowOffsetX: number = 0;
  textShadowOffsetY: number = 0;
}

export class ReaderRegexBubbleStyleResolver {
  static resolve(rule: ReaderRegexFontRule | null, context: ReaderRegexEmphasisContext): ReaderResolvedRegexEmphasis {
    const result = new ReaderResolvedRegexEmphasis();
    const configuredMode = rule ? ReaderRegexFontCodec.normalizeEmphasisMode(
      rule.emphasisMode,
      rule.highlightColorEnabled
    ) : 'inherit';
    result.mode = configuredMode === 'inherit' ?
      ReaderRegexFontCodec.normalizeResolvedEmphasisMode(context.inheritedMode) : configuredMode;
    const configuredStyle = rule ? ReaderRegexFontCodec.normalizeBubbleStyleId(rule.bubbleStyleId) : 'inherit';
    result.bubbleStyleId = configuredStyle === 'inherit' ?
      ReaderRegexFontCodec.normalizeResolvedBubbleStyleId(context.inheritedBubbleStyleId) : configuredStyle;
    const configuredColor = rule ? (rule.emphasisColor || rule.shadowColor || '').trim() : '';
    result.emphasisColor = ReaderRegexBubbleStyleResolver.normalizeColor(
      configuredColor || context.inheritedColor || context.accentColor,
      context.accentColor
    );
    result.textColor = ReaderRegexBubbleStyleResolver.normalizeColor(
      context.normalTextColor,
      context.darkMode ? '#F2F3F5' : '#1F1F1F'
    );

    if (result.mode === 'text') {
      result.textColor = result.emphasisColor;
      return result;
    }
    if (result.mode === 'highlight') {
      result.backgroundEnabled = true;
      result.backgroundColor = result.emphasisColor;
      result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(result.backgroundColor);
      if (!configuredColor && context.inheritedTextColor) {
        result.textColor = ReaderRegexBubbleStyleResolver.normalizeColor(
          context.inheritedTextColor,
          result.textColor
        );
      }
      ReaderRegexBubbleStyleResolver.setUniformRadius(result, 4);
      return result;
    }
    if (result.mode !== 'bubble') {
      return result;
    }

    result.backgroundEnabled = true;
    ReaderRegexBubbleStyleResolver.applyBubblePreset(result, context);
    if (!configuredColor && context.inheritedTextColor) {
      result.textColor = ReaderRegexBubbleStyleResolver.normalizeColor(
        context.inheritedTextColor,
        result.textColor
      );
    }
    return result;
  }

  private static applyBubblePreset(result: ReaderResolvedRegexEmphasis, context: ReaderRegexEmphasisContext): void {
    const base = result.emphasisColor;
    const surface = ReaderRegexBubbleStyleResolver.normalizeColor(
      context.surfaceColor,
      context.darkMode ? '#111318' : '#FFFFFF'
    );
    if (result.bubbleStyleId === 'qq-solid') {
      result.backgroundColor = base;
      result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(base);
      ReaderRegexBubbleStyleResolver.setRadii(result, 12, 12, 12, 4);
      result.textShadowRadius = 1;
      result.textShadowColor = '#55000000';
      result.textShadowOffsetY = 1;
      return;
    }
    if (result.bubbleStyleId === 'capsule') {
      result.backgroundColor = ReaderRegexBubbleStyleResolver.withAlpha(base, 66);
      const composite = ReaderRegexBubbleStyleResolver.mix(surface, base, 0.26);
      result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(composite);
      ReaderRegexBubbleStyleResolver.setUniformRadius(result, 99);
      return;
    }
    if (result.bubbleStyleId === 'paper') {
      const paper = context.darkMode ? '#59472D' : '#F5E6BF';
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix(paper, base, context.darkMode ? 0.20 : 0.14);
      result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(result.backgroundColor);
      ReaderRegexBubbleStyleResolver.setRadii(result, 3, 7, 3, 7);
      result.textShadowRadius = 0.5;
      result.textShadowColor = context.darkMode ? '#77000000' : '#44FFFFFF';
      result.textShadowOffsetY = 0.5;
      return;
    }
    if (result.bubbleStyleId === 'neon') {
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix('#171225', base, 0.30);
      result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(result.backgroundColor);
      ReaderRegexBubbleStyleResolver.setUniformRadius(result, 7);
      result.textShadowRadius = 8;
      result.textShadowColor = ReaderRegexBubbleStyleResolver.withAlpha(base, 204);
      return;
    }
    result.backgroundColor = ReaderRegexBubbleStyleResolver.withAlpha(base, 56);
    const composite = ReaderRegexBubbleStyleResolver.mix(surface, base, 0.22);
    result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(composite);
    ReaderRegexBubbleStyleResolver.setRadii(result, 10, 10, 10, 3);
    result.textShadowRadius = 0.5;
    result.textShadowColor = context.darkMode ? '#66000000' : '#33FFFFFF';
    result.textShadowOffsetY = 0.5;
  }

  private static setUniformRadius(result: ReaderResolvedRegexEmphasis, radius: number): void {
    ReaderRegexBubbleStyleResolver.setRadii(result, radius, radius, radius, radius);
  }

  private static setRadii(result: ReaderResolvedRegexEmphasis, topLeft: number, topRight: number,
    bottomLeft: number, bottomRight: number): void {
    result.radiusTopLeft = topLeft;
    result.radiusTopRight = topRight;
    result.radiusBottomLeft = bottomLeft;
    result.radiusBottomRight = bottomRight;
  }

  static normalizeColor(value: string, fallback: string): string {
    const text = (value || '').trim();
    if (/^#[0-9a-fA-F]{6}$/.test(text)) {
      return text.toUpperCase();
    }
    if (/^[0-9a-fA-F]{6}$/.test(text)) {
      return `#${text.toUpperCase()}`;
    }
    const fallbackText = (fallback || '').trim();
    if (/^#[0-9a-fA-F]{6}$/.test(fallbackText)) {
      return fallbackText.toUpperCase();
    }
    return '#007DFF';
  }

  static withAlpha(color: string, alpha: number): string {
    const normalized = ReaderRegexBubbleStyleResolver.normalizeColor(color, '#007DFF');
    return `#${ReaderRegexBubbleStyleResolver.componentToHex(alpha)}${normalized.substring(1)}`;
  }

  static mix(first: string, second: string, secondRatio: number): string {
    const a = ReaderRegexBubbleStyleResolver.normalizeColor(first, '#FFFFFF');
    const b = ReaderRegexBubbleStyleResolver.normalizeColor(second, '#007DFF');
    const ratio = Math.max(0, Math.min(secondRatio, 1));
    const red = ReaderRegexBubbleStyleResolver.channel(a, 1) * (1 - ratio) +
      ReaderRegexBubbleStyleResolver.channel(b, 1) * ratio;
    const green = ReaderRegexBubbleStyleResolver.channel(a, 3) * (1 - ratio) +
      ReaderRegexBubbleStyleResolver.channel(b, 3) * ratio;
    const blue = ReaderRegexBubbleStyleResolver.channel(a, 5) * (1 - ratio) +
      ReaderRegexBubbleStyleResolver.channel(b, 5) * ratio;
    return `#${ReaderRegexBubbleStyleResolver.componentToHex(red)}` +
      `${ReaderRegexBubbleStyleResolver.componentToHex(green)}` +
      `${ReaderRegexBubbleStyleResolver.componentToHex(blue)}`;
  }

  static contrastTextColor(backgroundColor: string): string {
    const color = ReaderRegexBubbleStyleResolver.normalizeColor(backgroundColor, '#007DFF');
    const red = ReaderRegexBubbleStyleResolver.channel(color, 1) / 255;
    const green = ReaderRegexBubbleStyleResolver.channel(color, 3) / 255;
    const blue = ReaderRegexBubbleStyleResolver.channel(color, 5) / 255;
    const luminance = red * 0.299 + green * 0.587 + blue * 0.114;
    return luminance > 0.60 ? '#2F261D' : '#FFF9F2';
  }

  private static channel(color: string, start: number): number {
    return parseInt(color.substring(start, start + 2), 16);
  }

  private static componentToHex(value: number): string {
    return Math.max(0, Math.min(Math.round(value), 255)).toString(16).padStart(2, '0').toUpperCase();
  }
}
