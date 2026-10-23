import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/** 漫画阅读方式。条漫为上下连续滚动；ltr/rtl 为单页左右翻页（rtl 为日漫的从右往左）。 */
export class ReaderComicMode {
  static readonly WEBTOON: string = 'webtoon';
  static readonly LTR: string = 'ltr';
  static readonly RTL: string = 'rtl';

  static normalize(value: string): string {
    return value === ReaderComicMode.LTR || value === ReaderComicMode.RTL ? value : ReaderComicMode.WEBTOON;
  }

  static isPaged(value: string): boolean {
    return value === ReaderComicMode.LTR || value === ReaderComicMode.RTL;
  }

  static label(value: string): string {
    if (value === ReaderComicMode.LTR) return '从左往右';
    if (value === ReaderComicMode.RTL) return '从右往左';
    return '条漫';
  }
}

export class ReaderComicBackground {
  static readonly BLACK: string = 'black';
  static readonly WHITE: string = 'white';
  static readonly THEME: string = 'theme';

  static normalize(value: string): string {
    return value === ReaderComicBackground.WHITE || value === ReaderComicBackground.THEME ? value :
      ReaderComicBackground.BLACK;
  }
}

export class ReaderComicFit {
  /** 宽度铺满，按原图比例取高度。 */
  static readonly WIDTH: string = 'width';
  /** 整张图放进一屏，必要时左右留边。 */
  static readonly SCREEN: string = 'screen';

  static normalize(value: string): string {
    return value === ReaderComicFit.SCREEN ? value : ReaderComicFit.WIDTH;
  }
}

/** 设置面板里并排选项块的一项。 */
export class ReaderComicOption {
  value: string = '';
  label: string = '';
  /** 非空时在文字前画一个色块（背景色选项）。 */
  swatch: string = '';

  constructor(value: string, label: string, swatch: string = '') {
    this.value = value;
    this.label = label;
    this.swatch = swatch;
  }
}

/** 漫画模式的全局设置。阅读方式另有按书覆盖（书籍变量 readerComicReadingMode）。 */
export class ReaderComicSettings {
  static readonly PAGE_GAPS: number[] = [0, 6, 16];
  static readonly PRELOAD_COUNTS: number[] = [0, 3, 5, 10];

  defaultMode: string = ReaderComicMode.WEBTOON;
  background: string = ReaderComicBackground.BLACK;
  pageGap: number = 0;
  fit: string = ReaderComicFit.WIDTH;
  /** 点击屏幕两侧翻一屏；关闭后点哪里都呼出菜单。 */
  tapTurn: boolean = true;
  /** 角落里的话名、页码、时间与电量。 */
  infoBar: boolean = true;
  /** 双击放大/还原；关闭后单击不必等待双击判定。 */
  doubleTapZoom: boolean = true;
  /** 横屏或宽屏时翻页模式并排两页。 */
  dualPage: boolean = true;
  /** 网络图片向后预先下载的张数。 */
  preloadCount: number = 5;
  /** 端侧 AI 超分（会员功能）；会员到期后保留开关值，续费后自动恢复。 */
  superResolution: boolean = false;

  copy(): ReaderComicSettings {
    const next = new ReaderComicSettings();
    next.defaultMode = this.defaultMode;
    next.background = this.background;
    next.pageGap = this.pageGap;
    next.fit = this.fit;
    next.tapTurn = this.tapTurn;
    next.infoBar = this.infoBar;
    next.doubleTapZoom = this.doubleTapZoom;
    next.dualPage = this.dualPage;
    next.preloadCount = this.preloadCount;
    next.superResolution = this.superResolution;
    return next;
  }

  toJson(): string {
    const record: Record<string, Object> = {
      'defaultMode': this.defaultMode,
      'background': this.background,
      'pageGap': this.pageGap,
      'fit': this.fit,
      'tapTurn': this.tapTurn,
      'infoBar': this.infoBar,
      'doubleTapZoom': this.doubleTapZoom,
      'dualPage': this.dualPage,
      'preloadCount': this.preloadCount,
      'superResolution': this.superResolution
    };
    return JSON.stringify(record);
  }

  static parse(raw: string): ReaderComicSettings {
    const settings = new ReaderComicSettings();
    if (!raw) return settings;
    try {
      const record = JSON.parse(raw) as Record<string, Object>;
      settings.defaultMode = ReaderComicMode.normalize(String(record['defaultMode'] ?? ''));
      settings.background = ReaderComicBackground.normalize(String(record['background'] ?? ''));
      settings.pageGap = ReaderComicSettings.nearest(Number(record['pageGap']), ReaderComicSettings.PAGE_GAPS, 0);
      settings.fit = ReaderComicFit.normalize(String(record['fit'] ?? ''));
      settings.tapTurn = record['tapTurn'] !== false;
      settings.infoBar = record['infoBar'] !== false;
      settings.doubleTapZoom = record['doubleTapZoom'] !== false;
      settings.dualPage = record['dualPage'] !== false;
      settings.preloadCount = ReaderComicSettings.nearest(Number(record['preloadCount']),
        ReaderComicSettings.PRELOAD_COUNTS, 5);
      settings.superResolution = record['superResolution'] === true;
    } catch (_) {
    }
    return settings;
  }

  private static nearest(value: number, options: number[], fallback: number): number {
    if (!Number.isFinite(value)) return fallback;
    let best = options[0];
    for (const option of options) {
      if (Math.abs(option - value) < Math.abs(best - value)) best = option;
    }
    return best;
  }
}

/** 存在 reader_settings 偏好文件里，随阅读设置一起备份恢复。 */
export class ReaderComicSettingsStore {
  private static readonly STORE_NAME: string = 'reader_settings';
  private static readonly KEY: string = 'readerComicSettings';
  // 不另做缓存：preferences 实例本身常驻内存，备份恢复写入同一实例后这里能直接读到新值。
  static async load(context: Context): Promise<ReaderComicSettings> {
    let settings = new ReaderComicSettings();
    try {
      const store = await preferences.getPreferences(context, ReaderComicSettingsStore.STORE_NAME);
      const raw = await store.get(ReaderComicSettingsStore.KEY, '');
      settings = ReaderComicSettings.parse(typeof raw === 'string' ? raw : '');
    } catch (error) {
      console.warn('读取漫画设置失败:', error);
    }
    return settings;
  }

  static async save(context: Context, settings: ReaderComicSettings): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, ReaderComicSettingsStore.STORE_NAME);
      await store.put(ReaderComicSettingsStore.KEY, settings.toJson());
      await store.flush();
    } catch (error) {
      console.warn('保存漫画设置失败:', error);
    }
  }
}
