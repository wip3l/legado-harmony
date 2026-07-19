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
  customTextColorEnabled: boolean = false;
  customTextColor: string = '';
  customHighlightEnabled: boolean = false;
  customHighlightColor: string = '';
  customBubbleEnabled: boolean = false;
  customBubbleColor: string = '';
  // Kept in schema v2 so older installations can still read a compatible rule.
  highlightColorEnabled: boolean = false;
  shadowColor: string = '';
  expanded: boolean = true;
}

export class ReaderRegexFontRulesData {
  schemaVersion: number = 3;
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
  static readonly SCHEMA_VERSION: number = 3;

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
      rule.emphasisMode = (legacy.shadowColor || '').trim() ? 'custom' : 'none';
      rule.emphasisColor = (legacy.shadowColor || '').trim();
      rule.customHighlightEnabled = rule.emphasisMode === 'custom';
      rule.customHighlightColor = rule.emphasisColor;
      rule.highlightColorEnabled = rule.customHighlightEnabled;
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
      const legacyEmphasisMode = (item.emphasisMode || '').trim();
      rule.emphasisMode = ReaderRegexFontCodec.normalizeEmphasisMode(
        item.emphasisMode,
        item.highlightColorEnabled === true
      );
      rule.bubbleStyleId = ReaderRegexFontCodec.normalizeBubbleStyleId(item.bubbleStyleId);
      rule.emphasisColor = ((item.emphasisColor || item.shadowColor) || '').trim();
      rule.customTextColorEnabled = item.customTextColorEnabled === true || legacyEmphasisMode === 'text';
      rule.customTextColor = (item.customTextColor ||
        (legacyEmphasisMode === 'text' ? rule.emphasisColor : '')).trim();
      rule.customHighlightEnabled = item.customHighlightEnabled === true || legacyEmphasisMode === 'highlight';
      rule.customHighlightColor = (item.customHighlightColor ||
        (legacyEmphasisMode === 'highlight' ? rule.emphasisColor : '')).trim();
      rule.customBubbleEnabled = item.customBubbleEnabled === true || legacyEmphasisMode === 'bubble';
      rule.customBubbleColor = (item.customBubbleColor ||
        (legacyEmphasisMode === 'bubble' ? rule.emphasisColor : '')).trim();
      if (legacyEmphasisMode === 'text' || legacyEmphasisMode === 'highlight' || legacyEmphasisMode === 'bubble') {
        rule.emphasisMode = 'custom';
      }
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
    if (value === 'inherit' || value === 'none' || value === 'custom') {
      return value;
    }
    if (value === 'text' || value === 'highlight' || value === 'bubble' || value === 'accent') {
      return 'custom';
    }
    return legacyEnabled ? 'highlight' : 'none';
  }

  static normalizeResolvedEmphasisMode(mode: string): string {
    const value = (mode || '').trim();
    if (value === 'text' || value === 'highlight' || value === 'bubble' || value === 'custom') {
      return value;
    }
    return 'none';
  }

  static normalizeBubbleStyleId(styleId: string): string {
    const value = (styleId || '').trim();
    if (value === 'inherit' || value === 'qq-soft' || value === 'qq-solid' || value === 'capsule' ||
      value === 'paper' || value === 'neon' || value === 'classic-glass' || value === 'warm-scroll' ||
      value === 'forest-dew' || value === 'ink-brush' || value === 'neon-pulse' || value === 'strawberry-ribbon' ||
      value === 'crimson-stamp' || value === 'celadon-slip' || value === 'rose-frame' ||
      value === 'moon-halo') {
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
    return Math.max(14, Math.min(Math.round(value || 20), 50));
  }

  static syncLegacyFields(rule: ReaderRegexFontRule): void {
    const mode = ReaderRegexFontCodec.normalizeEmphasisMode(rule.emphasisMode, rule.highlightColorEnabled);
    rule.emphasisMode = mode;
    rule.bubbleStyleId = ReaderRegexFontCodec.normalizeBubbleStyleId(rule.bubbleStyleId);
    rule.customTextColor = (rule.customTextColor || '').trim();
    rule.customHighlightColor = (rule.customHighlightColor || '').trim();
    rule.customBubbleColor = (rule.customBubbleColor || '').trim();
    rule.emphasisColor = (rule.customHighlightColor || rule.customBubbleColor || rule.customTextColor ||
      rule.emphasisColor || rule.shadowColor || '').trim();
    rule.highlightColorEnabled = mode === 'custom' &&
      (rule.customHighlightEnabled || rule.customBubbleEnabled);
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
  textShadows: ShadowOptions[] = [];
  decorationEnabled: boolean = false;
  decorationStyleId: string = 'solid';
  decorationColor: string = '#00000000';
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

    if (result.mode === 'custom' && rule) {
      const bubbleColor = ReaderRegexBubbleStyleResolver.normalizeColor(
        rule.customBubbleColor || context.inheritedColor || context.accentColor,
        context.accentColor
      );
      const highlightColor = ReaderRegexBubbleStyleResolver.normalizeColor(
        rule.customHighlightColor || context.inheritedColor || context.accentColor,
        context.accentColor
      );
      const textColor = ReaderRegexBubbleStyleResolver.normalizeColor(
        rule.customTextColor || context.inheritedTextColor || context.accentColor,
        context.accentColor
      );
      if (rule.customBubbleEnabled) {
        result.emphasisColor = bubbleColor;
        result.backgroundEnabled = true;
        ReaderRegexBubbleStyleResolver.applyBubblePreset(result, context);
      }
      if (rule.customHighlightEnabled) {
        result.emphasisColor = highlightColor;
        result.backgroundEnabled = true;
        result.backgroundColor = highlightColor;
        result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(highlightColor);
        ReaderRegexBubbleStyleResolver.setUniformRadius(result, 4);
        if (rule.customBubbleEnabled) {
          result.textShadowRadius = Math.max(5, result.textShadowRadius);
          result.textShadowColor = ReaderRegexBubbleStyleResolver.withAlpha(bubbleColor, 180);
        }
      }
      if (rule.customTextColorEnabled) {
        result.textColor = textColor;
      }
      return result;
    }

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
    if (result.bubbleStyleId === 'classic-glass') {
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix(surface, base, context.darkMode ? 0.28 : 0.16);
      result.textColor = context.darkMode ? '#DCEBFF' : '#234D72';
      ReaderRegexBubbleStyleResolver.setRadii(result, 12, 12, 12, 3);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.5, context.darkMode ? '#663B5D7D' : '#DDFFFFFF',
        0, -0.5);
      ReaderRegexBubbleStyleResolver.addShadow(result, 2.6,
        ReaderRegexBubbleStyleResolver.withAlpha(base, 124), 0, 1.2);
      return;
    }
    if (result.bubbleStyleId === 'warm-scroll') {
      const parchment = context.darkMode ? '#3F3023' : '#F4E5C9';
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix(parchment, base, context.darkMode ? 0.20 : 0.13);
      result.textColor = context.darkMode ? '#FFE9CE' : '#4A3423';
      ReaderRegexBubbleStyleResolver.setRadii(result, 2, 15, 2, 15);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.5, context.darkMode ? '#5520130A' : '#CCFFF9ED',
        0, -0.7);
      ReaderRegexBubbleStyleResolver.addShadow(result, 1.8,
        ReaderRegexBubbleStyleResolver.withAlpha(base, 96), 1, 1.4);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.4, '#668B6338', -0.8, 0.5);
      return;
    }
    if (result.bubbleStyleId === 'forest-dew') {
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix(surface, base, context.darkMode ? 0.25 : 0.18);
      result.textColor = context.darkMode ? '#DDF5E5' : '#234B35';
      ReaderRegexBubbleStyleResolver.setRadii(result, 99, 99, 99, 11);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.5, context.darkMode ? '#5524382D' : '#D8FFFFFF',
        -0.5, -0.7);
      ReaderRegexBubbleStyleResolver.addShadow(result, 3.2,
        ReaderRegexBubbleStyleResolver.withAlpha(base, 110), 0.8, 1.2);
      return;
    }
    if (result.bubbleStyleId === 'ink-brush') {
      const inkPaper = context.darkMode ? '#25292D' : '#E4E3DE';
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix(inkPaper, base, context.darkMode ? 0.16 : 0.10);
      result.textColor = context.darkMode ? '#F1F3F4' : '#252B30';
      ReaderRegexBubbleStyleResolver.setRadii(result, 1, 7, 1, 7);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.4, context.darkMode ? '#553E4750' : '#AAFFFFFF',
        -0.8, -0.5);
      ReaderRegexBubbleStyleResolver.addShadow(result, 1.1, context.darkMode ? '#CC000000' : '#7724292D',
        1.2, 1.2);
      return;
    }
    if (result.bubbleStyleId === 'neon-pulse') {
      const neonSurface = context.darkMode ? '#101426' : '#ECEEFF';
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix(neonSurface, base,
        context.darkMode ? 0.24 : 0.14);
      result.textColor = context.darkMode ? '#DDFCFF' : '#263C72';
      ReaderRegexBubbleStyleResolver.setRadii(result, 6, 15, 6, 15);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.5, '#CCECFFFF', 0, 0);
      ReaderRegexBubbleStyleResolver.addShadow(result, 4,
        ReaderRegexBubbleStyleResolver.withAlpha(base, context.darkMode ? 196 : 126), 0, 0);
      ReaderRegexBubbleStyleResolver.addShadow(result, 8, '#77954DFF', 1, 0);
      return;
    }
    if (result.bubbleStyleId === 'strawberry-ribbon') {
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix(surface, base, context.darkMode ? 0.30 : 0.20);
      result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(result.backgroundColor);
      ReaderRegexBubbleStyleResolver.setRadii(result, 18, 18, 18, 6);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.6, context.darkMode ? '#55263544' : '#CCFFFFFF',
        0, -0.5);
      ReaderRegexBubbleStyleResolver.addShadow(result, 3, ReaderRegexBubbleStyleResolver.withAlpha(base, 116),
        0, 1.5);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.8, '#77E76E77', 1, 0.8);
      return;
    }
    if (result.bubbleStyleId === 'crimson-stamp') {
      result.backgroundColor = ReaderRegexBubbleStyleResolver.withAlpha(base, context.darkMode ? 64 : 34);
      result.textColor = context.darkMode ? '#FFE9E2' : ReaderRegexBubbleStyleResolver.mix('#3A2420', base, 0.48);
      ReaderRegexBubbleStyleResolver.setRadii(result, 2, 9, 2, 9);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.4,
        ReaderRegexBubbleStyleResolver.withAlpha(base, 174), -1, 0);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.7,
        context.darkMode ? '#99000000' : '#6630201D', 1, 1);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.3,
        context.darkMode ? '#55FFF1EA' : '#88FFF9F5', 0, -1);
      return;
    }
    if (result.bubbleStyleId === 'celadon-slip') {
      const paper = context.darkMode ? '#28342D' : '#F1EBDD';
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix(paper, base, context.darkMode ? 0.25 : 0.18);
      result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(result.backgroundColor);
      ReaderRegexBubbleStyleResolver.setRadii(result, 3, 13, 3, 13);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.5, context.darkMode ? '#44202924' : '#AAFFFFFF',
        0, -0.5);
      ReaderRegexBubbleStyleResolver.addShadow(result, 1.2,
        ReaderRegexBubbleStyleResolver.withAlpha(base, 92), 0.8, 1);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.5, '#668E765D', -0.6, 0.7);
      return;
    }
    if (result.bubbleStyleId === 'rose-frame') {
      result.backgroundColor = ReaderRegexBubbleStyleResolver.withAlpha(base, context.darkMode ? 62 : 42);
      const composite = ReaderRegexBubbleStyleResolver.mix(surface, base, context.darkMode ? 0.34 : 0.24);
      result.textColor = ReaderRegexBubbleStyleResolver.contrastTextColor(composite);
      ReaderRegexBubbleStyleResolver.setRadii(result, 19, 7, 19, 7);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.5, context.darkMode ? '#55251318' : '#AAFFFFFF',
        0, -0.5);
      ReaderRegexBubbleStyleResolver.addShadow(result, 2.4,
        ReaderRegexBubbleStyleResolver.withAlpha(base, 112), 0, 1);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.8, '#66B99A6B', 1, 1);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.4,
        context.darkMode ? '#66FFE8E6' : '#887E3540', -0.8, 0.3);
      return;
    }
    if (result.bubbleStyleId === 'moon-halo') {
      const night = context.darkMode ? '#0B1728' : '#E8F0F9';
      result.backgroundColor = ReaderRegexBubbleStyleResolver.mix(night, base, context.darkMode ? 0.24 : 0.16);
      result.textColor = context.darkMode ? '#D9EEFF' : '#2D5274';
      ReaderRegexBubbleStyleResolver.setUniformRadius(result, 13);
      ReaderRegexBubbleStyleResolver.addShadow(result, 0.5, context.darkMode ? '#CCEDF7FF' : '#99FFFFFF',
        0, 0);
      ReaderRegexBubbleStyleResolver.addShadow(result, 3,
        ReaderRegexBubbleStyleResolver.withAlpha(base, 172), 0, 0);
      ReaderRegexBubbleStyleResolver.addShadow(result, 8,
        ReaderRegexBubbleStyleResolver.withAlpha(base, 88), 0, 0);
      ReaderRegexBubbleStyleResolver.addShadow(result, 4, '#557A6CFF', 1, 0);
      return;
    }
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

  private static addShadow(result: ReaderResolvedRegexEmphasis, radius: number, color: string,
    offsetX: number, offsetY: number): void {
    result.textShadows.push({ radius: radius, color: color, offsetX: offsetX, offsetY: offsetY });
  }

  private static setDecoration(result: ReaderResolvedRegexEmphasis, styleId: string, color: string): void {
    result.decorationEnabled = true;
    result.decorationStyleId = styleId;
    result.decorationColor = color;
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
