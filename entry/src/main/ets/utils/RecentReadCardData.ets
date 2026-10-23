import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { Book } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { BookCoverCache } from './BookCoverCache';
import { BookshelfSortHelper } from './BookshelfSortHelper';
import { BookCoverResolver } from './BookCoverResolver';
import { ThemeBookCoverSettings } from './ThemeBookCoverSettings';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ThemeIds } from '../theme/ThemeModels';
import { CoverGallerySnapshot, CoverGalleryStore } from './CoverGalleryStore';
import { SearchExplorePendingBook } from './SearchExplorePendingBook';
import { PrivateShelfStore } from './PrivateShelfStore';
import { AppThemeSettingsStore } from './AppThemeSettingsStore';

export const RECENT_READ_FORM_NAME = 'RecentReadForm';
export const RECENT_READ_FORM_ABILITY = 'RecentReadFormAbility';
export const RECENT_READ_FORM_MODULE = 'entry';
export const RECENT_READ_DIMENSION_2_2 = 2;
export const RECENT_READ_DIMENSION_2_4 = 3;
export const RECENT_READ_DIMENSION_4_4 = 4;
export const RECENT_READ_DEFAULT_DIMENSION = RECENT_READ_DIMENSION_2_4;
export const RECENT_READ_MAX_BOOKS = 5;
const CARD_BACKGROUND_LIGHT = '#F7F8FA';
const CARD_BACKGROUND_DARK = '#191B1F';

export class RecentReadCardData {
  version: number = 0;
  orderSignature: string = '';
  dimension: number = RECENT_READ_DEFAULT_DIMENSION;
  darkMode: boolean = false;
  count: number = 0;
  emptyTitle: string = '暂无最近阅读';
  emptySubtitle: string = '打开书架阅读后会显示在这里';
  accentColor: string = '#007DFF';
  accentBackgroundColor: string = '#1A007DFF';
  cardBackgroundColor: string = '#F7F8FA';

  book0Name: string = '';
  book0Chapter: string = '';
  book0Brief: string = '';
  book0Progress: string = '';
  book0Percent: number = -1;
  book0Time: string = '';
  book0Url: string = '';
  book0Cover: string = '';

  book1Name: string = '';
  book1Chapter: string = '';
  book1Brief: string = '';
  book1Progress: string = '';
  book1Percent: number = -1;
  book1Time: string = '';
  book1Url: string = '';
  book1Cover: string = '';

  book2Name: string = '';
  book2Chapter: string = '';
  book2Brief: string = '';
  book2Progress: string = '';
  book2Percent: number = -1;
  book2Time: string = '';
  book2Url: string = '';
  book2Cover: string = '';

  book3Name: string = '';
  book3Chapter: string = '';
  book3Brief: string = '';
  book3Progress: string = '';
  book3Percent: number = -1;
  book3Time: string = '';
  book3Url: string = '';
  book3Cover: string = '';

  book4Name: string = '';
  book4Chapter: string = '';
  book4Brief: string = '';
  book4Progress: string = '';
  book4Percent: number = -1;
  book4Time: string = '';
  book4Url: string = '';
  book4Cover: string = '';
  formImages: Record<string, number> = {};
}

/** 书在卡片上的展示字段，按下标写入 RecentReadCardData 的 book{N}* 字段。 */
class RecentReadCardBook {
  name: string = '';
  chapter: string = '';
  brief: string = '';
  progress: string = '';
  percent: number = -1;
  time: string = '';
  url: string = '';
  cover: string = '';
}

export class RecentReadCardDataProvider {
  static empty(
    dimension: number = RECENT_READ_DEFAULT_DIMENSION,
    darkMode: boolean = false
  ): RecentReadCardData {
    const data = new RecentReadCardData();
    data.version = Date.now();
    data.dimension = RecentReadCardDataProvider.normalizeDimension(dimension);
    data.darkMode = darkMode;
    data.cardBackgroundColor = darkMode ? CARD_BACKGROUND_DARK : CARD_BACKGROUND_LIGHT;
    return data;
  }

  static async load(
    context: Context,
    dimension: number = RECENT_READ_DEFAULT_DIMENSION,
    darkMode: boolean = false
  ): Promise<RecentReadCardData> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const books = BookshelfSortHelper.getRecentReadBooks(
      PrivateShelfStore.publicBooks(SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks())),
      RecentReadCardDataProvider.bookCountFor(dimension));
    let coverSettings = new CoverGallerySnapshot();
    try {
      coverSettings = await CoverGalleryStore.load(context);
    } catch (e) {
      console.warn('加载卡片封面图集设置失败:', e);
    }
    const accent = await RecentReadCardDataProvider.themeAccentColor(context, darkMode);
    return await RecentReadCardDataProvider.fromBooks(context, books, dimension, darkMode, coverSettings, accent);
  }

  /** 2×2 只放最近一本，2×4 一主两副，4×4 一主四行。 */
  private static bookCountFor(dimension: number): number {
    if (dimension === RECENT_READ_DIMENSION_2_2) {
      return 1;
    }
    if (dimension === RECENT_READ_DIMENSION_4_4) {
      return RECENT_READ_MAX_BOOKS;
    }
    return 3;
  }

  private static async fromBooks(
    context: Context,
    books: Book[],
    dimension: number,
    darkMode: boolean,
    coverSettings: CoverGallerySnapshot,
    accent: string
  ): Promise<RecentReadCardData> {
    const data = RecentReadCardDataProvider.empty(dimension, darkMode);
    data.accentColor = accent;
    data.accentBackgroundColor = RecentReadCardDataProvider.alphaColor(accent, darkMode ? '33' : '1A');
    data.cardBackgroundColor = RecentReadCardDataProvider.mixColor(
      darkMode ? CARD_BACKGROUND_DARK : CARD_BACKGROUND_LIGHT, accent, darkMode ? 0.08 : 0.05);
    const shown = books.slice(0, RECENT_READ_MAX_BOOKS);
    data.count = shown.length;
    data.orderSignature = shown
      .map((book: Book) => `${book.bookUrl}#${BookshelfSortHelper.getBookReadTime(book)}`)
      .join('|');
    if (shown.length > 0) {
      data.emptyTitle = '';
      data.emptySubtitle = '';
    }
    for (let i = 0; i < shown.length; i++) {
      await RecentReadCardDataProvider.fillBook(context, data, i, shown[i], darkMode, coverSettings);
    }
    return data;
  }

  private static async fillBook(
    context: Context,
    data: RecentReadCardData,
    index: number,
    book: Book,
    darkMode: boolean,
    coverSettings: CoverGallerySnapshot
  ): Promise<void> {
    const item = new RecentReadCardBook();
    item.name = book.name || '未命名书籍';
    const started = Book.hasStartedReading(book);
    item.chapter = started ? (book.durChapterTitle || '继续阅读') : '未读';
    item.brief = started ? RecentReadCardDataProvider.chapterBrief(item.chapter) : '未读';
    item.progress = RecentReadCardDataProvider.progressText(book);
    item.percent = RecentReadCardDataProvider.progressPercent(book);
    item.time = RecentReadCardDataProvider.formatReadTime(BookshelfSortHelper.getBookReadTime(book), data.version);
    item.url = book.bookUrl;
    item.cover = await RecentReadCardDataProvider.resolveCover(context, data, book, index, darkMode, coverSettings);
    RecentReadCardDataProvider.assignBook(data, index, item);
  }

  private static assignBook(data: RecentReadCardData, index: number, item: RecentReadCardBook): void {
    if (index === 0) {
      data.book0Name = item.name;
      data.book0Chapter = item.chapter;
      data.book0Brief = item.brief;
      data.book0Progress = item.progress;
      data.book0Percent = item.percent;
      data.book0Time = item.time;
      data.book0Url = item.url;
      data.book0Cover = item.cover;
      return;
    }
    if (index === 1) {
      data.book1Name = item.name;
      data.book1Chapter = item.chapter;
      data.book1Brief = item.brief;
      data.book1Progress = item.progress;
      data.book1Percent = item.percent;
      data.book1Time = item.time;
      data.book1Url = item.url;
      data.book1Cover = item.cover;
      return;
    }
    if (index === 2) {
      data.book2Name = item.name;
      data.book2Chapter = item.chapter;
      data.book2Brief = item.brief;
      data.book2Progress = item.progress;
      data.book2Percent = item.percent;
      data.book2Time = item.time;
      data.book2Url = item.url;
      data.book2Cover = item.cover;
      return;
    }
    if (index === 3) {
      data.book3Name = item.name;
      data.book3Chapter = item.chapter;
      data.book3Brief = item.brief;
      data.book3Progress = item.progress;
      data.book3Percent = item.percent;
      data.book3Time = item.time;
      data.book3Url = item.url;
      data.book3Cover = item.cover;
      return;
    }
    if (index === 4) {
      data.book4Name = item.name;
      data.book4Chapter = item.chapter;
      data.book4Brief = item.brief;
      data.book4Progress = item.progress;
      data.book4Percent = item.percent;
      data.book4Time = item.time;
      data.book4Url = item.url;
      data.book4Cover = item.cover;
      return;
    }
  }

  private static async resolveCover(
    context: Context,
    data: RecentReadCardData,
    book: Book,
    index: number,
    darkMode: boolean,
    coverSettings: CoverGallerySnapshot
  ): Promise<string> {
    const covers = BookCoverResolver.sourceCovers(book, darkMode, coverSettings);
    let raw: ResourceStr = covers[0] || '';
    // 卡片扩展可在主页面尚未初始化时运行，主题从持久化设置读取。
    try {
      const themeSettings = await AppThemeSettingsStore.load(context);
      if (themeSettings.themeBookCoverEnabled) {
        const theme = themeSettings.themeId === ThemeIds.CUSTOM ?
          AppThemeSettingsStore.customTheme(themeSettings, darkMode) : BuiltinThemeRegistry.findById(themeSettings.themeId);
        const themeCovers = ThemeBookCoverSettings.coversForAsset(book, theme.book.coverAssetId);
        if (themeCovers.length > 0) raw = themeCovers[0];
      }
    } catch (error) {
      console.warn('加载卡片主题封面设置失败:', error);
    }
    if (!raw) {
      return '';
    }
    try {
      const coverPath = await BookCoverResolver.prepareFile(context, raw);
      if (coverPath) {
        const imageKey = RecentReadCardDataProvider.coverImageKey(index, data.version);
        const file = fs.openSync(coverPath, fs.OpenMode.READ_ONLY);
        data.formImages[imageKey] = file.fd;
        return `memory://${imageKey}`;
      }
      return typeof raw === 'string' ? await BookCoverCache.resolveCover(context, raw) : '';
    } catch (e) {
      console.warn('解析最近阅读卡片封面失败:', e);
      return typeof raw === 'string' ? raw : '';
    }
  }

  /** 「8/420」，章节数未知时为空串。 */
  private static progressText(book: Book): string {
    if (book.totalChapterNum <= 0) {
      return '';
    }
    const current = Math.min(book.totalChapterNum, Math.max(1, book.durChapterIndex + 1));
    return `${current}/${book.totalChapterNum}`;
  }

  /** 按章节估算的阅读百分比，未读为 0，章节数未知为 -1（卡片不画进度条）。 */
  private static progressPercent(book: Book): number {
    if (!Book.hasStartedReading(book)) {
      return 0;
    }
    if (book.totalChapterNum <= 0) {
      return -1;
    }
    const current = Math.min(book.totalChapterNum, Math.max(1, book.durChapterIndex + 1));
    return Math.max(0, Math.min(100, Math.round(current * 100 / book.totalChapterNum)));
  }

  /** 去掉「第8章 」这类序号前缀，只剩章节名；去完为空则保留原标题。 */
  private static chapterBrief(title: string): string {
    const brief = title.replace(/^\s*第\s*[0-9零〇一二三四五六七八九十百千万两]+\s*[章节回卷集话部篇]\s*[:：、.\-—]?\s*/, '');
    return brief || title;
  }

  private static async themeAccentColor(context: Context, darkMode: boolean): Promise<string> {
    try {
      const settings = await AppThemeSettingsStore.load(context);
      return darkMode ? settings.darkAccentColor : settings.lightAccentColor;
    } catch (e) {
      console.warn('加载最近阅读卡片主题色失败:', e);
      return darkMode ? AppThemeSettingsStore.DEFAULT_DARK_ACCENT_COLOR : AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR;
    }
  }

  private static alphaColor(color: string, alpha: string): string {
    const normalized = AppThemeSettingsStore.normalizeColor(color, AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR);
    return `#${alpha}${normalized.substring(1)}`;
  }

  private static coverImageKey(index: number, version: number): string {
    return `book${index}Cover${version}`;
  }

  private static normalizeDimension(dimension: number): number {
    return dimension > 0 ? dimension : RECENT_READ_DEFAULT_DIMENSION;
  }

  /** 「今天 14:20」「昨天 09:05」「10-12 14:20」，跨年为「2025-10-12」，没有阅读时间为空串。 */
  private static formatReadTime(time: number, now: number): string {
    if (time <= 0) {
      return '';
    }
    const date = new Date(time);
    const today = new Date(now);
    const clock = `${RecentReadCardDataProvider.pad2(date.getHours())}:${RecentReadCardDataProvider.pad2(date.getMinutes())}`;
    const dayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
    if (time >= dayStart) {
      return `今天 ${clock}`;
    }
    if (time >= dayStart - 24 * 60 * 60 * 1000) {
      return `昨天 ${clock}`;
    }
    const monthDay =
      `${RecentReadCardDataProvider.pad2(date.getMonth() + 1)}-${RecentReadCardDataProvider.pad2(date.getDate())}`;
    if (date.getFullYear() === today.getFullYear()) {
      return `${monthDay} ${clock}`;
    }
    return `${date.getFullYear()}-${monthDay}`;
  }

  /** 把 tint 按 ratio 混进 base，两者都是 #RRGGBB。 */
  private static mixColor(base: string, tint: string, ratio: number): string {
    const from = AppThemeSettingsStore.normalizeColor(base, CARD_BACKGROUND_LIGHT);
    const to = AppThemeSettingsStore.normalizeColor(tint, AppThemeSettingsStore.DEFAULT_LIGHT_ACCENT_COLOR);
    let result = '#';
    for (let i = 1; i < 7; i += 2) {
      const a = parseInt(from.substring(i, i + 2), 16);
      const b = parseInt(to.substring(i, i + 2), 16);
      const value = Math.round(a + (b - a) * ratio);
      result += (value < 16 ? '0' : '') + value.toString(16).toUpperCase();
    }
    return result;
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
