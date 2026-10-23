import { HexColor } from '../../utils/HexColor';

/** 页眉页脚槽位可选的信息项。值会写入设置并参与云同步，不能改名。 */
export class ReaderInfoItem {
  static readonly NONE: string = 'none';
  static readonly BOOK: string = 'book';
  static readonly AUTHOR: string = 'author';
  static readonly CHAPTER_TITLE: string = 'chapter_title';
  static readonly CHAPTER_INDEX_TITLE: string = 'chapter_index_title';
  static readonly BOOK_CHAPTER: string = 'book_chapter';
  static readonly PAGE: string = 'page';
  static readonly PAGES_LEFT: string = 'pages_left';
  static readonly CHAPTER_PERCENT: string = 'chapter_percent';
  static readonly CHAPTER_PROGRESS: string = 'chapter_progress';
  static readonly BOOK_PERCENT: string = 'book_percent';
  static readonly TIME: string = 'time';
  static readonly BATTERY: string = 'battery';
  static readonly TIME_BATTERY: string = 'time_battery';

  static readonly VALUES: string[] = [
    ReaderInfoItem.NONE,
    ReaderInfoItem.BOOK,
    ReaderInfoItem.AUTHOR,
    ReaderInfoItem.CHAPTER_TITLE,
    ReaderInfoItem.CHAPTER_INDEX_TITLE,
    ReaderInfoItem.BOOK_CHAPTER,
    ReaderInfoItem.PAGE,
    ReaderInfoItem.PAGES_LEFT,
    ReaderInfoItem.CHAPTER_PERCENT,
    ReaderInfoItem.CHAPTER_PROGRESS,
    ReaderInfoItem.BOOK_PERCENT,
    ReaderInfoItem.TIME,
    ReaderInfoItem.BATTERY,
    ReaderInfoItem.TIME_BATTERY
  ];

  static readonly LABELS: string[] = [
    '不显示',
    '书名',
    '作者',
    '章节标题',
    '章节序号 + 标题',
    '书名 + 章节标题',
    '当前页 / 总页数',
    '本章剩余页数',
    '本章百分比',
    '章节进度',
    '全书百分比',
    '时间',
    '电量',
    '时间 + 电量'
  ];

  static normalize(item: string, fallback: string): string {
    const value = typeof item === 'string' ? item.trim().toLowerCase() : '';
    return ReaderInfoItem.VALUES.indexOf(value) >= 0 ? value : fallback;
  }

  static usesTime(item: string): boolean {
    return item === ReaderInfoItem.TIME || item === ReaderInfoItem.TIME_BATTERY;
  }

  static usesBattery(item: string): boolean {
    return item === ReaderInfoItem.BATTERY || item === ReaderInfoItem.TIME_BATTERY;
  }
}

/** 进度条位置。 */
export class ReaderInfoProgressBar {
  static readonly NONE: string = 'none';
  static readonly HEADER: string = 'header';
  static readonly FOOTER: string = 'footer';
  static readonly VALUES: string[] = [
    ReaderInfoProgressBar.NONE, ReaderInfoProgressBar.HEADER, ReaderInfoProgressBar.FOOTER
  ];
  static readonly LABELS: string[] = ['不显示', '页眉下方', '页脚上方'];

  static readonly SCOPE_CHAPTER: string = 'chapter';
  static readonly SCOPE_BOOK: string = 'book';
  static readonly SCOPE_VALUES: string[] = [ReaderInfoProgressBar.SCOPE_CHAPTER, ReaderInfoProgressBar.SCOPE_BOOK];
  static readonly SCOPE_LABELS: string[] = ['本章进度', '全书进度'];
}

/**
 * 页眉页脚的槽位与外观配置。整体序列化成一个 JSON 字符串保存，
 * 页眉、页脚各自的总开关仍沿用原有的两个布尔设置。
 */
export class ReaderInfoBarConfig {
  static readonly FONT_SIZE_MIN: number = 10;
  static readonly FONT_SIZE_MAX: number = 40;
  static readonly FONT_SIZE_DEFAULT: number = 12;
  static readonly OPACITY_MIN: number = 30;
  static readonly OPACITY_MAX: number = 100;
  static readonly OPACITY_STEP: number = 10;
  static readonly FIXED_SIDE_PADDING: number = 28;
  static readonly OFFSET_MAX: number = 350;
  static readonly OFFSET_STEP: number = 2;
  static readonly SHRINK_MIN: number = -350;
  static readonly SHRINK_MAX: number = 350;
  static readonly SHRINK_STEP: number = 1;

  headerLeft: string = ReaderInfoItem.CHAPTER_TITLE;
  headerCenter: string = ReaderInfoItem.NONE;
  headerRight: string = ReaderInfoItem.NONE;
  footerLeft: string = ReaderInfoItem.CHAPTER_INDEX_TITLE;
  footerCenter: string = ReaderInfoItem.NONE;
  footerRight: string = ReaderInfoItem.PAGE;
  /** 仅用于读取旧版共用字号；新配置使用下面的独立字号。 */
  fontSize?: number;
  headerFontSize: number = ReaderInfoBarConfig.FONT_SIZE_DEFAULT;
  footerFontSize: number = ReaderInfoBarConfig.FONT_SIZE_DEFAULT;
  /** 文字颜色；空字符串表示沿用当前阅读主题。 */
  headerColor: string = '';
  footerColor: string = '';
  /** 仅用于读取旧版共用不透明度。 */
  opacity?: number;
  /** 页眉、页脚文字不透明度，百分比。 */
  headerOpacity: number = ReaderInfoBarConfig.OPACITY_MAX;
  footerOpacity: number = ReaderInfoBarConfig.OPACITY_MAX;
  /** 左右边距跟随正文边距；关闭时使用固定边距。 */
  followMargin: boolean = false;
  /** 页眉在默认位置基础上再下移的距离（vp）。 */
  headerOffset: number = 0;
  /** 页脚在默认位置基础上再上移的距离（vp），用来让开手势指示条。 */
  footerOffset: number = 0;
  /** 左右两侧在原有边距基础上的收缩距离（vp），负数向外扩展。 */
  headerShrink: number = 0;
  footerShrink: number = 0;
  headerDivider: boolean = false;
  footerDivider: boolean = false;
  progressBar: string = ReaderInfoProgressBar.NONE;
  progressScope: string = ReaderInfoProgressBar.SCOPE_CHAPTER;

  /** 由旧版的三个内容选项和进度条开关推导，保证升级后显示不变。 */
  static fromLegacy(headerContentMode: string, footerLeftMode: string, footerProgressMode: string,
    footerShowProgressBar: boolean): ReaderInfoBarConfig {
    const config = new ReaderInfoBarConfig();
    if (headerContentMode === 'book') {
      config.headerLeft = ReaderInfoItem.BOOK;
    } else if (headerContentMode === 'book_chapter') {
      config.headerLeft = ReaderInfoItem.BOOK_CHAPTER;
    } else if (headerContentMode === 'none') {
      config.headerLeft = ReaderInfoItem.NONE;
    }
    if (footerLeftMode === 'title') {
      config.footerLeft = ReaderInfoItem.CHAPTER_TITLE;
    } else if (footerLeftMode === 'none') {
      config.footerLeft = ReaderInfoItem.NONE;
    }
    if (footerProgressMode === 'percentage') {
      config.footerRight = ReaderInfoItem.CHAPTER_PERCENT;
    } else if (footerProgressMode === 'chapter') {
      config.footerRight = ReaderInfoItem.CHAPTER_PROGRESS;
    } else if (footerProgressMode === 'book') {
      config.footerRight = ReaderInfoItem.BOOK_PERCENT;
      config.progressScope = ReaderInfoProgressBar.SCOPE_BOOK;
    } else if (footerProgressMode === 'none') {
      config.footerRight = ReaderInfoItem.NONE;
    }
    if (footerShowProgressBar) config.progressBar = ReaderInfoProgressBar.FOOTER;
    return config;
  }

  /** 解析已保存的配置；内容为空或损坏时返回 null，由调用方回退到旧设置。 */
  static parse(raw: string): ReaderInfoBarConfig | null {
    if (typeof raw !== 'string' || !raw.trim()) return null;
    try {
      const source = JSON.parse(raw) as ReaderInfoBarConfig;
      if (!source || typeof source !== 'object') return null;
      const defaults = new ReaderInfoBarConfig();
      const config = new ReaderInfoBarConfig();
      config.headerLeft = ReaderInfoItem.normalize(source.headerLeft, defaults.headerLeft);
      config.headerCenter = ReaderInfoItem.normalize(source.headerCenter, defaults.headerCenter);
      config.headerRight = ReaderInfoItem.normalize(source.headerRight, defaults.headerRight);
      config.footerLeft = ReaderInfoItem.normalize(source.footerLeft, defaults.footerLeft);
      config.footerCenter = ReaderInfoItem.normalize(source.footerCenter, defaults.footerCenter);
      config.footerRight = ReaderInfoItem.normalize(source.footerRight, defaults.footerRight);
      config.headerFontSize = ReaderInfoBarConfig.clampFontSize(source.headerFontSize ?? source.fontSize);
      config.footerFontSize = ReaderInfoBarConfig.clampFontSize(source.footerFontSize ?? source.fontSize);
      config.headerColor = ReaderInfoBarConfig.normalizeColor(source.headerColor);
      config.footerColor = ReaderInfoBarConfig.normalizeColor(source.footerColor);
      config.headerOpacity = ReaderInfoBarConfig.clampOpacity(source.headerOpacity ?? source.opacity);
      config.footerOpacity = ReaderInfoBarConfig.clampOpacity(source.footerOpacity ?? source.opacity);
      config.followMargin = source.followMargin === true;
      config.headerOffset = ReaderInfoBarConfig.clampOffset(source.headerOffset);
      config.footerOffset = ReaderInfoBarConfig.clampOffset(source.footerOffset);
      config.headerShrink = ReaderInfoBarConfig.clampShrink(source.headerShrink);
      config.footerShrink = ReaderInfoBarConfig.clampShrink(source.footerShrink);
      config.headerDivider = source.headerDivider === true;
      config.footerDivider = source.footerDivider === true;
      config.progressBar = ReaderInfoProgressBar.VALUES.indexOf(source.progressBar) >= 0 ?
        source.progressBar : ReaderInfoProgressBar.NONE;
      config.progressScope = source.progressScope === ReaderInfoProgressBar.SCOPE_BOOK ?
        ReaderInfoProgressBar.SCOPE_BOOK : ReaderInfoProgressBar.SCOPE_CHAPTER;
      return config;
    } catch (_) {
      return null;
    }
  }

  static clampFontSize(value: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) return ReaderInfoBarConfig.FONT_SIZE_DEFAULT;
    return Math.max(ReaderInfoBarConfig.FONT_SIZE_MIN, Math.min(Math.round(value), ReaderInfoBarConfig.FONT_SIZE_MAX));
  }

  static normalizeColor(value: string): string {
    return typeof value === 'string' ? HexColor.parse(value) : '';
  }

  textColor(header: boolean, fallback: string): string {
    return (header ? this.headerColor : this.footerColor) || fallback;
  }

  static clampOffset(value: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
    return Math.max(0, Math.min(Math.round(value), ReaderInfoBarConfig.OFFSET_MAX));
  }

  static clampOpacity(value: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) return ReaderInfoBarConfig.OPACITY_MAX;
    return Math.max(ReaderInfoBarConfig.OPACITY_MIN, Math.min(Math.round(value), ReaderInfoBarConfig.OPACITY_MAX));
  }

  static clampShrink(value: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
    return Math.max(ReaderInfoBarConfig.SHRINK_MIN, Math.min(Math.round(value), ReaderInfoBarConfig.SHRINK_MAX));
  }

  /** 左右对称收缩；向外最多到屏幕边缘，向内仍保留可显示文字的宽度。 */
  sidePadding(header: boolean, left: boolean, marginLeft: number, marginRight: number, width: number): number {
    const shrink = header ? this.headerShrink : this.footerShrink;
    const baseLeft = this.followMargin ? marginLeft : ReaderInfoBarConfig.FIXED_SIDE_PADDING;
    const baseRight = this.followMargin ? marginRight : ReaderInfoBarConfig.FIXED_SIDE_PADDING;
    const insetLeft = Math.max(0, baseLeft + shrink);
    const insetRight = Math.max(0, baseRight + shrink);
    const total = insetLeft + insetRight;
    // 视口尚未测量时先使用设置值；测量后限制极端收缩，兼容分屏和横屏。
    const allowedTotal = width > 0 ? Math.max(0, width - Math.min(width, 96)) : total;
    const scale = total > allowedTotal ? allowedTotal / total : 1;
    return (left ? insetLeft : insetRight) * scale;
  }

  serialize(): string {
    return JSON.stringify(this);
  }

  copy(): ReaderInfoBarConfig {
    const parsed = ReaderInfoBarConfig.parse(this.serialize());
    return parsed ? parsed : new ReaderInfoBarConfig();
  }

  headerHasContent(): boolean {
    return this.headerLeft !== ReaderInfoItem.NONE || this.headerCenter !== ReaderInfoItem.NONE ||
      this.headerRight !== ReaderInfoItem.NONE;
  }

  /** 页眉需要占位：有任一槽位内容，或进度条放在页眉。 */
  headerVisible(): boolean {
    return this.headerHasContent() || this.progressBar === ReaderInfoProgressBar.HEADER;
  }

  private slots(headerEnabled: boolean, footerEnabled: boolean): string[] {
    const slots: string[] = [];
    if (headerEnabled) {
      slots.push(this.headerLeft, this.headerCenter, this.headerRight);
    }
    if (footerEnabled) {
      slots.push(this.footerLeft, this.footerCenter, this.footerRight);
    }
    return slots;
  }

  /** 当前显示的槽位里是否有时间或电量，决定是否需要每分钟刷新。 */
  usesClock(headerEnabled: boolean, footerEnabled: boolean): boolean {
    return this.slots(headerEnabled, footerEnabled).some((item: string): boolean =>
      ReaderInfoItem.usesTime(item) || ReaderInfoItem.usesBattery(item));
  }

  /** 页眉文字行高度（vp）。由字号直接推算，不依赖异步测量，避免打开书时二次分页。 */
  headerLineHeight(): number {
    return Math.round(this.headerFontSize * 1.5);
  }

  /** 页眉文字行以外的附加高度：进度条或分隔线。 */
  headerExtraHeight(): number {
    if (this.progressBar === ReaderInfoProgressBar.HEADER) return 5;
    return this.headerDivider ? 4 : 0;
  }

  /** 页脚文字行以外的附加高度：进度条或分隔线。 */
  footerExtraHeight(): number {
    if (this.progressBar === ReaderInfoProgressBar.FOOTER) return 5;
    return this.footerDivider ? 4 : 0;
  }

  /** 只包含会改变正文可用高度的项；内容槽位变化不需要重新分页。 */
  layoutIdentity(): string {
    return `${this.headerFontSize}_${this.footerFontSize}_${this.headerVisible()}_` +
      `${this.headerExtraHeight()}_${this.footerExtraHeight()}_` +
      `${this.headerOffset}_${this.footerOffset}`;
  }
}

/** 生成槽位文字所需的阅读状态快照。 */
export class ReaderInfoBarContext {
  bookName: string = '';
  author: string = '';
  chapterTitle: string = '';
  chapterIndex: number = 0;
  chapterCount: number = 0;
  pageIndex: number = 0;
  pageCount: number = 0;
  /** 横屏双页时一次显示两页。 */
  doublePage: boolean = false;
  timeText: string = '';
  /** 电量百分比；小于 0 表示读取不到。 */
  batteryPercent: number = -1;
}

export class ReaderInfoBarText {
  static of(item: string, context: ReaderInfoBarContext): string {
    const pageCount = Math.max(1, context.pageCount);
    const pageIndex = Math.max(0, Math.min(context.pageIndex, pageCount - 1));
    const chapterCount = Math.max(1, context.chapterCount);
    const chapterIndex = Math.max(0, Math.min(context.chapterIndex, chapterCount - 1));
    const bookName = context.bookName || '未命名书籍';
    if (item === ReaderInfoItem.BOOK) return bookName;
    if (item === ReaderInfoItem.AUTHOR) return context.author;
    if (item === ReaderInfoItem.CHAPTER_TITLE) return context.chapterTitle;
    if (item === ReaderInfoItem.CHAPTER_INDEX_TITLE) {
      return context.chapterCount <= 0 ? bookName : `${chapterIndex + 1}/${chapterCount} ${context.chapterTitle}`;
    }
    if (item === ReaderInfoItem.BOOK_CHAPTER) {
      return context.chapterTitle ? `${bookName} · ${context.chapterTitle}` : bookName;
    }
    if (item === ReaderInfoItem.PAGE) {
      if (context.doublePage) {
        return `${pageIndex + 1}-${Math.min(pageIndex + 2, pageCount)}/${pageCount}`;
      }
      return `${pageIndex + 1}/${pageCount}`;
    }
    if (item === ReaderInfoItem.PAGES_LEFT) {
      const shown = context.doublePage ? Math.min(pageIndex + 2, pageCount) : pageIndex + 1;
      return `剩余 ${Math.max(0, pageCount - shown)} 页`;
    }
    if (item === ReaderInfoItem.CHAPTER_PERCENT) {
      return `${Math.round(ReaderInfoBarText.chapterPercent(context))}%`;
    }
    if (item === ReaderInfoItem.CHAPTER_PROGRESS) return `${chapterIndex + 1}/${chapterCount} 章`;
    if (item === ReaderInfoItem.BOOK_PERCENT) {
      return `${ReaderInfoBarText.bookPercent(context).toFixed(1)}%`;
    }
    if (item === ReaderInfoItem.TIME) return context.timeText;
    if (item === ReaderInfoItem.BATTERY) return ReaderInfoBarText.batteryText(context);
    if (item === ReaderInfoItem.TIME_BATTERY) {
      const battery = ReaderInfoBarText.batteryText(context);
      return context.timeText && battery ? `${context.timeText}  ${battery}` : (context.timeText || battery);
    }
    return '';
  }

  /** 槽位里画在电池图标之前的文字；纯电量项没有前置文字。 */
  static leading(item: string, context: ReaderInfoBarContext): string {
    if (item === ReaderInfoItem.BATTERY) return '';
    if (item === ReaderInfoItem.TIME_BATTERY) return context.timeText;
    return ReaderInfoBarText.of(item, context);
  }

  /** 槽位需要画电池图标时返回电量百分比，否则返回 -1。 */
  static battery(item: string, context: ReaderInfoBarContext): number {
    if (!ReaderInfoItem.usesBattery(item) || context.batteryPercent < 0) return -1;
    return Math.round(Math.min(100, context.batteryPercent));
  }

  static batteryText(context: ReaderInfoBarContext): string {
    return context.batteryPercent >= 0 ? `${Math.round(Math.min(100, context.batteryPercent))}%` : '';
  }

  static chapterPercent(context: ReaderInfoBarContext): number {
    const pageCount = Math.max(1, context.pageCount);
    const pageIndex = Math.max(0, Math.min(context.pageIndex, pageCount - 1));
    return Math.max(0, Math.min(100, ((pageIndex + 1) / pageCount) * 100));
  }

  /** 全书进度 = 已读完的章节数 + 当前章内的页进度。 */
  static bookPercent(context: ReaderInfoBarContext): number {
    const chapterCount = Math.max(1, context.chapterCount);
    const chapterIndex = Math.max(0, Math.min(context.chapterIndex, chapterCount - 1));
    const inChapter = ReaderInfoBarText.chapterPercent(context) / 100;
    return Math.max(0, Math.min(100, ((chapterIndex + inChapter) / chapterCount) * 100));
  }
}
