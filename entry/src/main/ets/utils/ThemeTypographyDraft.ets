import { ReaderSettings } from './ReaderSettingsStore';

/**
 * 主题排版页尚未保存的草稿。阅读字体页带 DRAFT_PARAM 打开时读写这一份，
 * 而不是正在使用的阅读设置；主题排版页回到前台时按 revision 判断要不要刷新。
 */
export class ThemeTypographyDraft {
  static readonly DRAFT_PARAM: string = 'themeTypographyDraft';
  private static draft: ReaderSettings | null = null;
  private static draftRevision: number = 0;

  static begin(settings: ReaderSettings): void {
    ThemeTypographyDraft.draft = settings;
    ThemeTypographyDraft.draftRevision++;
  }

  static current(): ReaderSettings | null {
    return ThemeTypographyDraft.draft;
  }

  static revision(): number {
    return ThemeTypographyDraft.draftRevision;
  }

  /** 阅读字体页只提交它管理的字段：正文字号、正文与标题字体、正则强调规则。 */
  static applyFontStyle(source: ReaderSettings): void {
    const target = ThemeTypographyDraft.draft;
    if (!target) return;
    target.fontSize = source.fontSize || target.fontSize;
    target.bodyFontMode = source.bodyFontMode;
    target.bodyFontFamily = source.bodyFontFamily || '';
    target.titleFontMode = source.titleFontMode;
    target.titleFontFamily = source.titleFontFamily || '';
    target.titleFontSize = source.titleFontSize;
    target.regexFontEnabled = source.regexFontEnabled;
    target.regexFontPattern = source.regexFontPattern || '';
    target.regexFontMode = source.regexFontMode;
    target.regexFontFamily = source.regexFontFamily || '';
    target.regexFontSize = source.regexFontSize;
    target.regexShadowColor = source.regexShadowColor || '';
    target.regexFontRulesRaw = source.regexFontRulesRaw || '';
    ThemeTypographyDraft.draftRevision++;
  }

  static end(): void {
    ThemeTypographyDraft.draft = null;
    ThemeTypographyDraft.draftRevision++;
  }
}
